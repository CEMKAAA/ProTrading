"""
Trade Executor for HTF Reversal Strategy
Handles order execution, position management, and special exit logic
"""

import MetaTrader5 as mt5
import pandas as pd
import time
from typing import Optional, Dict, List
from .logger import logger
from .config import (
    MAGIC_NUMBER, DEFAULT_RR_RATIO,
    TRAILING_ENABLED, TRAILING_START_RR, TRAILING_LOCK_PERCENT,
    PARTIAL_TP_PERCENT, EXIT_CHECK_TIMEFRAME
)


class TradeExecutor:
    """
    Handles trade execution for swing trades.

    Special exit logic:
    - Unless H4 candle closes below the wick of the lowest candle
      (if buying reversal), remain in trade
    - Take profits at major retest areas of broken S/R
    """

    def __init__(self, symbol: str):
        self.symbol = symbol
        self.entry_candle_low = None  # For tracking exit condition
        self.entry_candle_high = None

    def execute_trade(
        self,
        direction: str,
        entry_price: float,
        sl_price: float,
        tp_price: float,
        lot_size: float,
        comment: str = ""
    ) -> bool:
        """
        Execute market order.

        Args:
            direction: 'BUY' or 'SELL'
            entry_price: Entry price
            sl_price: Stop loss
            tp_price: Take profit
            lot_size: Position size
            comment: Order comment

        Returns:
            True if successful
        """
        order_type = mt5.ORDER_TYPE_BUY if direction == 'BUY' else mt5.ORDER_TYPE_SELL

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": lot_size,
            "type": order_type,
            "price": entry_price,
            "sl": sl_price,
            "tp": tp_price,
            "magic": MAGIC_NUMBER,
            "comment": comment[:31],
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = self._send_with_retry(request)

        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            # Store entry candle info for exit logic
            df = mt5.copy_rates_from_pos(self.symbol, EXIT_CHECK_TIMEFRAME, 0, 1)
            if df is not None and len(df) > 0:
                candle = df[0]
                self.entry_candle_low = candle['low']
                self.entry_candle_high = candle['high']

            logger.info(
                f"{direction} EXECUTED | Entry: {entry_price:.2f} | "
                f"SL: {sl_price:.2f} | TP: {tp_price:.2f} | Lot: {lot_size}"
            )
            return True

        logger.error("Trade execution failed")
        return False

    def _send_with_retry(self, request: Dict, max_retries: int = 3):
        """Send order with retry logic"""
        for attempt in range(max_retries):
            result = mt5.order_send(request)

            if result.retcode == mt5.TRADE_RETCODE_DONE:
                return result

            if result.retcode in [mt5.TRADE_RETCODE_REQUOTE,
                                  mt5.TRADE_RETCODE_PRICE_CHANGED]:
                logger.warning(f"Requote (attempt {attempt + 1})")
                time.sleep(0.3)

                tick = mt5.symbol_info_tick(self.symbol)
                if tick:
                    is_buy = request['type'] == mt5.ORDER_TYPE_BUY
                    request['price'] = tick.ask if is_buy else tick.bid
                continue

            logger.error(f"Order failed: {result.comment} (Code: {result.retcode})")
            return None

        logger.error("Max retries exceeded")
        return None

    def check_h4_exit_condition(self, position_type: int) -> bool:
        """
        Check if H4 candle closes below/above the wick of entry candle.

        Exit logic:
        - For BUY: exit if H4 closes below the wick of the lowest candle
        - For SELL: exit if H4 closes above the wick of the highest candle

        Args:
            position_type: 0 for BUY, 1 for SELL

        Returns:
            True if exit condition met
        """
        # Get latest completed H4 candle
        rates = mt5.copy_rates_from_pos(self.symbol, EXIT_CHECK_TIMEFRAME, 1, 1)

        if rates is None or len(rates) == 0:
            return False

        h4_close = rates[0]['close']
        h4_low = rates[0]['low']
        h4_high = rates[0]['high']

        if position_type == 0:  # BUY position
            # Exit if H4 closes below the wick of lowest candle
            if self.entry_candle_low and h4_close < self.entry_candle_low:
                logger.info(
                    f"H4 exit condition: close ${h4_close:.2f} < "
                    f"entry candle low ${self.entry_candle_low:.2f}"
                )
                return True

            # Update tracking to current candle if it's lower
            if h4_low < self.entry_candle_low:
                self.entry_candle_low = h4_low

        else:  # SELL position
            # Exit if H4 closes above the wick of highest candle
            if self.entry_candle_high and h4_close > self.entry_candle_high:
                logger.info(
                    f"H4 exit condition: close ${h4_close:.2f} > "
                    f"entry candle high ${self.entry_candle_high:.2f}"
                )
                return True

            # Update tracking
            if h4_high > self.entry_candle_high:
                self.entry_candle_high = h4_high

        return False

    def manage_positions(self, broken_levels: List[float] = None):
        """
        Manage open positions.

        - Check H4 exit condition
        - Manage trailing stops
        - Take partial profits at broken S/R levels

        Args:
            broken_levels: List of broken S/R levels for TP
        """
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return

        for pos in positions:
            if pos.magic != MAGIC_NUMBER:
                continue

            # Check H4 exit condition
            if self.check_h4_exit_condition(pos.type):
                self.close_position(pos.ticket, "H4 Exit Condition")
                continue

            # Manage trailing stop
            if TRAILING_ENABLED:
                self._manage_trailing(pos)

            # Check partial TP at broken levels
            if broken_levels:
                self._check_partial_tp(pos, broken_levels)

    def _manage_trailing(self, position):
        """Manage trailing stop for a position"""
        tick = mt5.symbol_info_tick(self.symbol)
        symbol_info = mt5.symbol_info(self.symbol)

        if tick is None or symbol_info is None:
            return

        entry = position.price_open
        current_sl = position.sl
        is_long = position.type == 0
        price = tick.bid if is_long else tick.ask

        # Calculate profit in R
        sl_distance = abs(entry - current_sl)
        current_profit = price - entry if is_long else entry - price
        profit_in_r = current_profit / sl_distance if sl_distance > 0 else 0

        # Start trailing after TRAILING_START_RR
        if profit_in_r < TRAILING_START_RR:
            return

        # Calculate new SL to lock in profit
        lock_profit = current_profit * (TRAILING_LOCK_PERCENT / 100)

        if is_long:
            new_sl = entry + lock_profit
            should_trail = new_sl > current_sl
        else:
            new_sl = entry - lock_profit
            should_trail = new_sl < current_sl

        if should_trail:
            # Check min distance
            min_stop = symbol_info.trade_stops_level * symbol_info.point
            distance = abs(price - new_sl)

            if distance >= min_stop:
                self._modify_sl(position.ticket, new_sl, position.tp)
                logger.info(f"Trailing SL updated to ${new_sl:.2f}")

    def _check_partial_tp(self, position, broken_levels: List[float]):
        """Check if price reached a broken S/R level for partial TP"""
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return

        is_long = position.type == 0
        price = tick.bid if is_long else tick.ask

        for level in broken_levels:
            distance = abs(price - level)

            # Within $1 of a broken level
            if distance < 1.0:
                # Take partial profit
                partial_volume = position.volume * (PARTIAL_TP_PERCENT / 100)

                if partial_volume >= 0.01:
                    self._partial_close(position, partial_volume, f"Partial TP @ ${level:.2f}")
                    broken_levels.remove(level)
                    break

    def _partial_close(self, position, volume: float, comment: str):
        """Close part of a position"""
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return

        close_type = mt5.ORDER_TYPE_SELL if position.type == 0 else mt5.ORDER_TYPE_BUY
        price = tick.bid if close_type == mt5.ORDER_TYPE_SELL else tick.ask

        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info:
            volume = round(volume / symbol_info.volume_step) * symbol_info.volume_step
            volume = max(symbol_info.volume_min, volume)

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": volume,
            "type": close_type,
            "position": position.ticket,
            "price": price,
            "magic": MAGIC_NUMBER,
            "comment": comment[:31],
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = self._send_with_retry(request)
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            logger.info(f"Partial close: {volume} lots - {comment}")

    def _modify_sl(self, ticket: int, new_sl: float, tp: float):
        """Modify position SL"""
        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "position": ticket,
            "symbol": self.symbol,
            "sl": new_sl,
            "tp": tp
        }

        result = self._send_with_retry(request, max_retries=2)
        return result and result.retcode == mt5.TRADE_RETCODE_DONE

    def close_position(self, ticket: int, comment: str = "Close"):
        """Close a position by ticket"""
        position = mt5.positions_get(ticket=ticket)
        if not position:
            return

        pos = position[0]
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return

        close_type = mt5.ORDER_TYPE_SELL if pos.type == 0 else mt5.ORDER_TYPE_BUY
        price = tick.bid if close_type == mt5.ORDER_TYPE_SELL else tick.ask

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": pos.volume,
            "type": close_type,
            "position": ticket,
            "price": price,
            "magic": MAGIC_NUMBER,
            "comment": comment[:31],
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = self._send_with_retry(request)
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            logger.info(f"Position {ticket} closed: {comment}")

    def close_all_positions(self, comment: str = "Close All"):
        """Close all positions"""
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return

        for pos in positions:
            if pos.magic == MAGIC_NUMBER:
                self.close_position(pos.ticket, comment)
