"""
Shared trade execution: Order placement, modification, trailing stops.
Parameterizable version used by all live strategies.
"""

import MetaTrader5 as mt5
import time
import pandas as pd

from .trade_journal import TradeJournal


class TradeExecutor:
    """Handles all MT5 order operations."""

    def __init__(self, symbol, magic_number, rr_threshold=3.0,
                 use_trailing=True, trailing_atr_period=14,
                 trailing_atr_multiplier=1.5, logger=None):
        """
        Args:
            symbol: Trading symbol
            magic_number: Unique magic number
            rr_threshold: SL < threshold = 2R target, else use rr_ratio
            use_trailing: Enable ATR trailing stops
            trailing_atr_period: ATR period for trailing
            trailing_atr_multiplier: ATR multiplier for trail distance
            logger: Logger instance
        """
        self.symbol = symbol
        self.magic_number = magic_number
        self.rr_threshold = rr_threshold
        self.use_trailing = use_trailing
        self.trailing_atr_period = trailing_atr_period
        self.trailing_atr_multiplier = trailing_atr_multiplier
        self.logger = logger
        self.last_atr_time = None
        self.cached_atr = None
        self.journal = TradeJournal()
        self.on_trade_close_callback = None
        # MFE/MAE tracker: {ticket: {'entry': price, 'mfe': 0, 'mae': 0, 'sl_dist': dist, 'is_long': bool}}
        self._mfe_mae_tracker = {}

    def _log(self, level, msg):
        if self.logger:
            getattr(self.logger, level)(msg)

    def execute_trade(self, direction, entry_price, sl_price, lot_size,
                      comment="", rr_ratio=None):
        """
        Execute market order with retry logic.

        Args:
            direction: 'BUY' or 'SELL'
            entry_price: Entry price
            sl_price: Stop loss price
            lot_size: Position size
            comment: Order comment
            rr_ratio: Explicit R:R ratio. If None, uses threshold logic.

        Returns:
            bool: Success status
        """
        sl_distance = abs(entry_price - sl_price)

        if rr_ratio is None:
            rr_ratio = 2.0 if sl_distance < self.rr_threshold else 1.5
        # Never use 1:1 on Gold
        rr_ratio = max(2.0, rr_ratio)

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
            "magic": self.magic_number,
            "comment": comment[:31],
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        intended_price = entry_price
        result = self._send_with_retry(request)

        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            actual_price = result.price
            self._log('info',
                      f"{direction} EXECUTED | "
                      f"Price: {actual_price:.2f} | "
                      f"SL: {sl_price:.2f} | "
                      f"TP: {tp_price:.2f} ({rr_ratio}R) | "
                      f"Lot: {lot_size}")

            # Record execution quality (fail-safe)
            try:
                tick = mt5.symbol_info_tick(self.symbol)
                spread = (tick.ask - tick.bid) if tick else 0
                self.journal.record_entry(
                    ticket=result.order,
                    intended_price=intended_price,
                    actual_price=actual_price,
                    spread=spread,
                    lot_size=lot_size,
                    direction=direction,
                    symbol=self.symbol,
                )
            except Exception as e:
                self._log('debug', f"Journal entry recording skipped: {e}")

            # Start MFE/MAE tracking for this position
            try:
                is_long = direction == 'BUY'
                self._mfe_mae_tracker[result.order] = {
                    'entry': actual_price,
                    'mfe': 0.0,
                    'mae': 0.0,
                    'sl_dist': sl_distance,
                    'is_long': is_long,
                }
            except Exception:
                pass

            return True

        self._log('error', "Trade execution failed")
        return False

    def _send_with_retry(self, request, max_retries=3):
        """Send order with requote handling."""
        for attempt in range(max_retries):
            result = mt5.order_send(request)

            if result.retcode == mt5.TRADE_RETCODE_DONE:
                return result

            if result.retcode in [mt5.TRADE_RETCODE_REQUOTE,
                                  mt5.TRADE_RETCODE_PRICE_CHANGED]:
                self._log('warning', f"Requote (attempt {attempt + 1}/{max_retries})")
                time.sleep(0.3)

                tick = mt5.symbol_info_tick(self.symbol)
                if tick:
                    is_buy = request['type'] == mt5.ORDER_TYPE_BUY
                    request['price'] = tick.ask if is_buy else tick.bid
                continue

            self._log('error',
                      f"Order failed: {result.comment} (Code: {result.retcode})")
            return None

        self._log('error', "Max retries exceeded")
        return None

    def manage_trailing_stops(self, data_manager):
        """
        Manage breakeven and ATR-based trailing stops.

        Returns:
            bool: True if any position was modified
        """
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return False

        modified = False

        for pos in positions:
            if pos.magic != self.magic_number:
                continue

            current_pos = mt5.positions_get(ticket=pos.ticket)
            if not current_pos:
                continue

            pos = current_pos[0]

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

            # Update MFE/MAE tracking
            try:
                tracker = self._mfe_mae_tracker.get(pos.ticket)
                if tracker:
                    sl_dist = tracker['sl_dist']
                    if sl_dist > 0:
                        if is_long:
                            excursion = (price - tracker['entry']) / sl_dist
                        else:
                            excursion = (tracker['entry'] - price) / sl_dist
                        if excursion > tracker['mfe']:
                            tracker['mfe'] = excursion
                        if excursion < -tracker['mae']:
                            tracker['mae'] = -excursion
            except Exception:
                pass

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
                    min_stop = symbol_info.trade_stops_level * symbol_info.point
                    distance = abs(price - new_sl)

                    if distance >= min_stop:
                        if self._modify_position(pos.ticket, new_sl, current_tp):
                            self._log('info', f"Breakeven set @ {new_sl:.2f}")
                            modified = True
                    continue

            # Step 2: ATR trailing
            if not self.use_trailing or not at_breakeven:
                continue

            atr = self._get_atr(data_manager)
            if atr is None or atr <= 0:
                continue

            trail_offset = atr * self.trailing_atr_multiplier

            if is_long:
                new_sl = price - trail_offset
                should_trail = new_sl > current_sl
            else:
                new_sl = price + trail_offset
                should_trail = new_sl < current_sl

            if should_trail:
                min_stop = symbol_info.trade_stops_level * symbol_info.point
                distance = abs(price - new_sl)

                if distance >= min_stop:
                    if self._modify_position(pos.ticket, new_sl, current_tp):
                        self._log('info',
                                  f"Trailing SL: {new_sl:.2f} (ATR: {atr:.2f})")
                        modified = True

        return modified

    def _get_atr(self, data_manager):
        """Calculate ATR with caching."""
        df = data_manager.get_data(bars=self.trailing_atr_period + 10)

        if len(df) < self.trailing_atr_period:
            return None

        current_bar_time = df.index[-1]

        if self.last_atr_time is None or current_bar_time > self.last_atr_time:
            tr = pd.DataFrame({
                'hl': df['high'] - df['low'],
                'hc': abs(df['high'] - df['close'].shift()),
                'lc': abs(df['low'] - df['close'].shift())
            }).max(axis=1)

            atr = tr.rolling(window=self.trailing_atr_period).mean().iloc[-1]

            self.cached_atr = atr
            self.last_atr_time = current_bar_time
            self._log('debug', f"ATR updated: {atr:.3f}")

        return self.cached_atr

    def _modify_position(self, ticket, new_sl, tp):
        """Modify position SL/TP."""
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

        self._log('warning', f"SL modification failed for ticket {ticket}")
        return False

    def close_all_positions(self, comment="Close All"):
        """Close all open positions for this symbol."""
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return

        closed_count = 0

        for pos in positions:
            if pos.magic != self.magic_number:
                continue

            tick = mt5.symbol_info_tick(self.symbol)
            if tick is None:
                continue

            close_type = mt5.ORDER_TYPE_SELL if pos.type == 0 else mt5.ORDER_TYPE_BUY
            price = tick.bid if close_type == mt5.ORDER_TYPE_SELL else tick.ask

            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.symbol,
                "volume": pos.volume,
                "type": close_type,
                "position": pos.ticket,
                "price": price,
                "magic": self.magic_number,
                "comment": comment[:31],
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }

            intended_exit = pos.tp if pos.tp else price
            result = self._send_with_retry(request)

            if result and result.retcode == mt5.TRADE_RETCODE_DONE:
                self._log('info', f"Position {pos.ticket} closed")
                closed_count += 1

                # Record exit execution quality (fail-safe)
                try:
                    exit_tick = mt5.symbol_info_tick(self.symbol)
                    exit_spread = (exit_tick.ask - exit_tick.bid) if exit_tick else 0
                    self.journal.record_exit(
                        ticket=pos.ticket,
                        intended_price=intended_exit,
                        actual_price=result.price,
                        spread=exit_spread,
                    )
                except Exception as e:
                    self._log('debug', f"Journal exit recording skipped: {e}")

                # Write MFE/MAE to DB
                try:
                    tracker = self._mfe_mae_tracker.pop(pos.ticket, None)
                    if tracker:
                        self.journal.record_mfe_mae(
                            pos.ticket, tracker['mfe'], tracker['mae']
                        )
                except Exception as e:
                    self._log('debug', f"MFE/MAE recording skipped: {e}")

                # Call trade close callback (for adaptive filter, etc.)
                try:
                    if self.on_trade_close_callback:
                        self.on_trade_close_callback(
                            ticket=pos.ticket,
                            pnl=pos.profit,
                            comment=pos.comment if hasattr(pos, 'comment') else '',
                        )
                except Exception as e:
                    self._log('debug', f"Trade close callback skipped: {e}")
            else:
                self._log('error', f"Failed to close position {pos.ticket}")

        self._log('info', f"Closed {closed_count} position(s)")
