"""
Trade execution: Order placement, modification, trailing stops
"""

import MetaTrader5 as mt5
import time
import pandas as pd
from logger import logger
from config import (
    MAGIC_NUMBER, GOLD_RR_THRESHOLD,
    USE_TRAILING, TRAILING_ATR_PERIOD, TRAILING_ATR_MULTIPLIER
)


class TradeExecutor:
    """Handles all MT5 order operations"""
    
    def __init__(self, symbol):
        self.symbol = symbol
        self.last_atr_time = None
        self.cached_atr = None
        
    def execute_trade(self, direction, entry_price, sl_price, lot_size, comment=""):
        """
        Execute market order with retry logic
        
        Args:
            direction: 'BUY' or 'SELL'
            entry_price: Entry price
            sl_price: Stop loss price
            lot_size: Position size
            comment: Order comment
            
        Returns:
            bool: Success status
        """
        # Calculate TP based on RR
        sl_distance = abs(entry_price - sl_price)
        
        # Dynamic RR: small stops get 2R, larger stops get 1R
        rr_ratio = 2.0 if sl_distance < GOLD_RR_THRESHOLD else 1.0
        tp_distance = sl_distance * rr_ratio
        
        if direction == 'BUY':
            tp_price = entry_price + tp_distance
            order_type = mt5.ORDER_TYPE_BUY
        else:
            tp_price = entry_price - tp_distance
            order_type = mt5.ORDER_TYPE_SELL
        
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": lot_size,
            "type": order_type,
            "price": entry_price,
            "sl": sl_price,
            "tp": tp_price,
            "magic": MAGIC_NUMBER,
            "comment": comment[:31],  # MT5 limit
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        
        result = self._send_with_retry(request)
        
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            logger.info(
                f"✅ {direction} EXECUTED | "
                f"Price: {entry_price:.2f} | "
                f"SL: {sl_price:.2f} | "
                f"TP: {tp_price:.2f} ({rr_ratio}R) | "
                f"Lot: {lot_size}"
            )
            return True
        
        logger.error(f"❌ Trade execution failed")
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
            
            if result.retcode == mt5.TRADE_RETCODE_DONE:
                return result
            
            # Handle requotes
            if result.retcode in [mt5.TRADE_RETCODE_REQUOTE, 
                                  mt5.TRADE_RETCODE_PRICE_CHANGED]:
                logger.warning(f"⚠️ Requote (attempt {attempt + 1}/{max_retries})")
                time.sleep(0.3)
                
                # Update price
                tick = mt5.symbol_info_tick(self.symbol)
                if tick:
                    is_buy = request['type'] == mt5.ORDER_TYPE_BUY
                    request['price'] = tick.ask if is_buy else tick.bid
                continue
            
            # Other errors
            logger.error(
                f"❌ Order failed: {result.comment} "
                f"(Code: {result.retcode})"
            )
            return None
        
        logger.error("❌ Max retries exceeded")
        return None
    
    def manage_trailing_stops(self, data_manager):
        """
        Manage breakeven and ATR-based trailing stops
        
        Process:
        1. Move to breakeven when price reaches 1R
        2. After breakeven, trail by ATR * multiplier
        
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
                            logger.info(f"🔒 Breakeven set @ {new_sl:.2f}")
                            modified = True
                    continue
            
            # Step 2: ATR trailing (only if USE_TRAILING enabled and at BE)
            if not USE_TRAILING or not at_breakeven:
                continue
            
            # Get ATR
            atr = self._get_atr(data_manager)
            if atr is None or atr <= 0:
                continue
            
            trail_offset = atr * TRAILING_ATR_MULTIPLIER
            
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
                            f"📈 Trailing SL: {new_sl:.2f} "
                            f"(ATR: {atr:.2f})"
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
            logger.debug(f"📊 ATR updated: {atr:.3f}")
        
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
        
        logger.warning(f"⚠️ SL modification failed for ticket {ticket}")
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
                "magic": MAGIC_NUMBER,
                "comment": comment[:31],
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }
            
            result = self._send_with_retry(request)
            
            if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                logger.info(f"✅ Position {pos.ticket} closed")
                closed_count += 1
            else:
                logger.error(f"❌ Failed to close position {pos.ticket}")
        
        logger.info(f"🔒 Closed {closed_count} position(s)")
