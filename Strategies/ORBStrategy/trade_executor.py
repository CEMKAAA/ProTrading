"""
Trade execution: Order placement, modification, trailing stops, fill quality audit.

Institutional-grade execution with:
- MT5 deviation parameter for slippage control
- Fill quality validation with tiered logging
- Position verification after execution
- Adaptive ATR trailing (vol-regime aware)
- Breakeven management at 1R
"""

import MetaTrader5 as mt5
import time
import numpy as np
import pandas as pd
from .logger import logger
from .config import (
    MAGIC_NUMBER, GOLD_RR_THRESHOLD,
    RR_TIGHT_SL_TARGET, RR_WIDE_SL_TARGET, MIN_RR_TARGET,
    USE_TRAILING, TRAILING_ATR_PERIOD, TRAILING_ATR_MULTIPLIER,
    MAX_SLIPPAGE_POINTS, FILL_QUALITY_WARN_USD, FILL_QUALITY_CRITICAL_USD,
    ADAPTIVE_TRAILING, ADAPTIVE_TRAILING_LOW_VOL_FACTOR,
    ADAPTIVE_TRAILING_HIGH_VOL_FACTOR,
)


class TradeExecutor:
    """Handles all MT5 order operations with institutional execution quality."""

    def __init__(self, symbol):
        self.symbol = symbol
        self.last_atr_time = None
        self.cached_atr = None
        self._atr_percentile_cache = None
        self._atr_percentile_time = None
        # Fill quality tracking
        self._circuit_breaker = None  # Set externally by strategy

    def set_circuit_breaker(self, cb):
        """Attach a circuit breaker for fill quality tracking."""
        self._circuit_breaker = cb

    def execute_trade(self, direction, sl_price, lot_size, comment="", entry_price=None):
        """
        Execute market order with deviation control, retry logic, and fill audit.

        Args:
            direction: 'BUY' or 'SELL'
            sl_price: Stop loss price
            lot_size: Position size
            comment: Order comment
            entry_price: Optional preferred entry anchor. If None, uses live tick.

        Returns:
            bool: Success status
        """
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            logger.error("No tick data for order execution")
            if self._circuit_breaker:
                self._circuit_breaker.record_error("no_tick_data")
            return False

        if direction == 'BUY':
            live_entry = tick.ask
            order_type = mt5.ORDER_TYPE_BUY
        else:
            live_entry = tick.bid
            order_type = mt5.ORDER_TYPE_SELL

        # Use current tradable price; fallback to provided anchor only if needed.
        entry_price = live_entry if live_entry and live_entry > 0 else entry_price
        if entry_price is None:
            logger.error("Invalid entry price for order execution")
            return False

        # Calculate TP based on RR
        sl_distance = abs(entry_price - sl_price)

        # Dynamic RR with a hard floor to protect expectancy after costs.
        rr_ratio = RR_TIGHT_SL_TARGET if sl_distance < GOLD_RR_THRESHOLD else RR_WIDE_SL_TARGET
        rr_ratio = max(MIN_RR_TARGET, rr_ratio)
        tp_distance = sl_distance * rr_ratio

        if direction == 'BUY':
            tp_price = entry_price + tp_distance
        else:
            tp_price = entry_price - tp_distance

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": lot_size,
            "type": order_type,
            "price": entry_price,
            "sl": sl_price,
            "tp": tp_price,
            "deviation": MAX_SLIPPAGE_POINTS,
            "magic": MAGIC_NUMBER,
            "comment": comment[:31],  # MT5 limit
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = self._send_with_retry(request)

        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            # Fill quality audit
            slippage = abs(result.price - entry_price)
            self._audit_fill_quality(entry_price, result.price, slippage, direction)

            # Position verification — fill is the truth (retcode DONE),
            # but log and record CB error if position not found.
            verified = self._verify_position(result.order)
            if not verified and self._circuit_breaker:
                self._circuit_breaker.record_error("position_verification_failed")

            logger.info(
                f"{direction} EXECUTED | "
                f"Price: {result.price:.2f} (req: {entry_price:.2f}, slip: ${slippage:.3f}) | "
                f"SL: {sl_price:.2f} | "
                f"TP: {tp_price:.2f} ({rr_ratio}R) | "
                f"Lot: {lot_size} | "
                f"Ticket: {result.order} | "
                f"Verified: {verified}"
            )
            return True

        if self._circuit_breaker:
            self._circuit_breaker.record_error("execution_failed")
        logger.error("Trade execution failed")
        return False

    def _audit_fill_quality(self, requested, actual, slippage, direction):
        """Tiered fill quality logging + circuit breaker integration."""
        if slippage >= FILL_QUALITY_CRITICAL_USD:
            logger.critical(
                f"EXCESSIVE SLIPPAGE: ${slippage:.3f} on {direction} "
                f"(requested={requested:.2f}, filled={actual:.2f})"
            )
        elif slippage >= FILL_QUALITY_WARN_USD:
            logger.warning(
                f"High slippage: ${slippage:.3f} on {direction} "
                f"(requested={requested:.2f}, filled={actual:.2f})"
            )

        if self._circuit_breaker:
            self._circuit_breaker.record_fill(requested, actual, direction)

    def _verify_position(self, ticket, retries=3):
        """Verify position exists after execution."""
        for attempt in range(retries):
            positions = mt5.positions_get(ticket=ticket)
            if positions and len(positions) > 0:
                return True
            time.sleep(0.1 * (attempt + 1))

        logger.warning(f"Position verification failed for ticket {ticket}")
        return False

    def _send_with_retry(self, request, max_retries=3):
        """
        Send order with requote handling

        Args:
            request: Order request dict
            max_retries: Number of retry attempts

        Returns:
            MT5 result or None
        """
        for attempt in range(max_retries):
            result = mt5.order_send(request)
            if result is None:
                logger.error(f"order_send failed: {mt5.last_error()}")
                if self._circuit_breaker:
                    self._circuit_breaker.record_error("order_send_null")
                return None

            if result.retcode == mt5.TRADE_RETCODE_DONE:
                return result

            # Handle requotes
            if result.retcode in [mt5.TRADE_RETCODE_REQUOTE,
                                  mt5.TRADE_RETCODE_PRICE_CHANGED]:
                logger.warning(f"Requote (attempt {attempt + 1}/{max_retries})")
                time.sleep(0.3)

                # Update price only for deal requests
                if request.get("action") == mt5.TRADE_ACTION_DEAL and "type" in request:
                    tick = mt5.symbol_info_tick(self.symbol)
                    if tick:
                        is_buy = request['type'] == mt5.ORDER_TYPE_BUY
                        request['price'] = tick.ask if is_buy else tick.bid
                continue

            # Other errors
            logger.error(
                f"Order failed: {result.comment} "
                f"(Code: {result.retcode})"
            )
            if self._circuit_breaker:
                self._circuit_breaker.record_error(f"retcode_{result.retcode}")
            return None

        logger.error("Max retries exceeded")
        if self._circuit_breaker:
            self._circuit_breaker.record_error("requote_max_retries")
        return None

    def _get_adaptive_trail_multiplier(self, data_manager):
        """
        Compute vol-regime-adjusted trailing multiplier.

        Low volatility  (ATR < 20th percentile) -> tighter trail (lock more profit)
        Normal volatility                       -> standard multiplier
        High volatility (ATR > 80th percentile) -> wider trail (avoid premature stop)
        """
        if not ADAPTIVE_TRAILING:
            return TRAILING_ATR_MULTIPLIER

        atr = self._get_atr(data_manager)
        if atr is None or atr <= 0:
            return TRAILING_ATR_MULTIPLIER

        # Cache percentile computation per bar
        df = data_manager.get_data(bars=200)
        if df is None or len(df) < 50:
            return TRAILING_ATR_MULTIPLIER

        current_bar_time = df.index[-1]
        if (self._atr_percentile_time is not None
                and current_bar_time == self._atr_percentile_time
                and self._atr_percentile_cache is not None):
            percentile = self._atr_percentile_cache
        else:
            # Calculate rolling ATR series
            tr = pd.DataFrame({
                'hl': df['high'] - df['low'],
                'hc': abs(df['high'] - df['close'].shift()),
                'lc': abs(df['low'] - df['close'].shift())
            }).max(axis=1)
            atr_series = tr.rolling(window=TRAILING_ATR_PERIOD).mean().dropna()

            if len(atr_series) < 20:
                return TRAILING_ATR_MULTIPLIER

            percentile = float((atr_series < atr).mean())
            self._atr_percentile_cache = percentile
            self._atr_percentile_time = current_bar_time

        if percentile < 0.20:
            factor = ADAPTIVE_TRAILING_LOW_VOL_FACTOR
        elif percentile > 0.80:
            factor = ADAPTIVE_TRAILING_HIGH_VOL_FACTOR
        else:
            factor = 1.0

        return TRAILING_ATR_MULTIPLIER * factor

    def manage_trailing_stops(self, data_manager):
        """
        Manage breakeven and ATR-based trailing stops.

        Process:
        1. Move to breakeven when price reaches 1R
        2. After breakeven, trail by ATR * adaptive multiplier

        Args:
            data_manager: DataManager instance for ATR calculation

        Returns:
            bool: True if any position was modified
        """
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return False

        modified = False

        for pos in positions:
            if pos.magic != MAGIC_NUMBER:
                continue

            # Refresh position data
            current_pos = mt5.positions_get(ticket=pos.ticket)
            if not current_pos:
                continue

            pos = current_pos[0]

            # Get current data
            tick = mt5.symbol_info_tick(self.symbol)
            symbol_info = mt5.symbol_info(self.symbol)

            if tick is None or symbol_info is None:
                continue

            entry = pos.price_open
            current_sl = pos.sl
            current_tp = pos.tp

            if current_sl == 0.0:
                continue

            is_long = pos.type == 0
            price = tick.bid if is_long else tick.ask

            # Check if at breakeven
            at_breakeven = (is_long and current_sl >= entry) or \
                          (not is_long and current_sl <= entry)

            # Step 1: Move to breakeven
            if not at_breakeven:
                risk = abs(entry - current_sl)
                should_be = False
                new_sl = current_sl

                if is_long and price >= (entry + risk):
                    new_sl = entry
                    should_be = True
                elif not is_long and price <= (entry - risk):
                    new_sl = entry
                    should_be = True

                if should_be:
                    # Check min distance
                    min_stop = symbol_info.trade_stops_level * symbol_info.point
                    distance = abs(price - new_sl)

                    if distance >= min_stop:
                        if self._modify_position(pos.ticket, new_sl, current_tp):
                            logger.info(f"Breakeven set @ {new_sl:.2f}")
                            modified = True
                    continue

            # Step 2: ATR trailing (only if USE_TRAILING enabled and at BE)
            if not USE_TRAILING or not at_breakeven:
                continue

            # Get ATR with adaptive multiplier
            atr = self._get_atr(data_manager)
            if atr is None or atr <= 0:
                continue

            trail_multiplier = self._get_adaptive_trail_multiplier(data_manager)
            trail_offset = atr * trail_multiplier

            if is_long:
                new_sl = price - trail_offset
                should_trail = new_sl > current_sl
            else:
                new_sl = price + trail_offset
                should_trail = new_sl < current_sl

            if should_trail:
                # Check min distance
                min_stop = symbol_info.trade_stops_level * symbol_info.point
                distance = abs(price - new_sl)

                if distance >= min_stop:
                    if self._modify_position(pos.ticket, new_sl, current_tp):
                        logger.info(
                            f"Trailing SL: {new_sl:.2f} "
                            f"(ATR: {atr:.2f}, mul: {trail_multiplier:.2f})"
                        )
                        modified = True

        return modified

    def _get_atr(self, data_manager):
        """
        Calculate ATR with caching (updates on new bar only)

        Args:
            data_manager: DataManager instance

        Returns:
            float: ATR value or None
        """
        df = data_manager.get_data(bars=TRAILING_ATR_PERIOD + 10)

        if len(df) < TRAILING_ATR_PERIOD:
            return None

        current_bar_time = df.index[-1]

        # Cache ATR per bar
        if self.last_atr_time is None or current_bar_time > self.last_atr_time:
            # Calculate True Range
            tr = pd.DataFrame({
                'hl': df['high'] - df['low'],
                'hc': abs(df['high'] - df['close'].shift()),
                'lc': abs(df['low'] - df['close'].shift())
            }).max(axis=1)

            # ATR = Moving average of TR
            atr = tr.rolling(window=TRAILING_ATR_PERIOD).mean().iloc[-1]

            self.cached_atr = atr
            self.last_atr_time = current_bar_time
            logger.debug(f"ATR updated: {atr:.3f}")

        return self.cached_atr

    def _modify_position(self, ticket, new_sl, tp):
        """
        Modify position SL/TP

        Args:
            ticket: Position ticket
            new_sl: New stop loss
            tp: Take profit (unchanged)

        Returns:
            bool: Success status
        """
        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "position": ticket,
            "symbol": self.symbol,
            "sl": new_sl,
            "tp": tp
        }

        result = self._send_with_retry(request, max_retries=2)

        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            return True

        logger.warning(f"SL modification failed for ticket {ticket}")
        return False

    def close_all_positions(self, comment="Close All"):
        """
        Close all open positions for this symbol

        Args:
            comment: Close comment
        """
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return

        closed_count = 0

        for pos in positions:
            if pos.magic != MAGIC_NUMBER:
                continue

            tick = mt5.symbol_info_tick(self.symbol)
            if tick is None:
                continue

            # Opposite order type to close
            close_type = mt5.ORDER_TYPE_SELL if pos.type == 0 else mt5.ORDER_TYPE_BUY
            price = tick.bid if close_type == mt5.ORDER_TYPE_SELL else tick.ask

            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.symbol,
                "volume": pos.volume,
                "type": close_type,
                "position": pos.ticket,
                "price": price,
                "deviation": MAX_SLIPPAGE_POINTS,
                "magic": MAGIC_NUMBER,
                "comment": comment[:31],
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }

            result = self._send_with_retry(request)

            if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                logger.info(f"Position {pos.ticket} closed")
                closed_count += 1
            else:
                logger.error(f"Failed to close position {pos.ticket}")

        logger.info(f"Closed {closed_count} position(s)")
