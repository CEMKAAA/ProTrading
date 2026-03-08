"""
Advanced Trade Executor
Slippage protection, position verification, partial profits, retry logic, and proper trailing
"""

import MetaTrader5 as mt5
import numpy as np
import pandas as pd
from datetime import datetime
from typing import Optional, Dict, Any, Tuple, List
from dataclasses import dataclass
import time as time_module

from .logger import logger
from .config import get_config, MAGIC_NUMBER, TARGET_SYMBOL


@dataclass
class ExecutionResult:
    """Result of trade execution"""
    success: bool
    ticket: Optional[int]
    actual_entry: Optional[float]
    actual_sl: Optional[float]
    actual_tp: Optional[float]
    lot_size: float
    slippage: float
    error: Optional[str]
    execution_time_ms: int


@dataclass
class PositionInfo:
    """Information about an open position"""
    ticket: int
    direction: str
    entry_price: float
    current_price: float
    volume: float
    sl: float
    tp: float
    profit: float
    swap: float
    open_time: datetime
    comment: str
    is_partial: bool  # True if this is a partial position


class AdvancedTradeExecutor:
    """
    Advanced trade execution with:
    - Slippage protection
    - Position verification
    - Retry logic for requotes
    - Partial profit taking
    - Proper trailing stop management
    - Structural SL preservation
    """

    def __init__(self, symbol: str = TARGET_SYMBOL):
        self.symbol = symbol
        self._partial_positions: Dict[int, Dict] = {}  # Track partial close state
        # Circuit breaker reference (set externally by strategy)
        self._circuit_breaker = None
        # Adaptive trailing cache
        self._atr_percentile_cache: Optional[float] = None
        self._atr_percentile_time = None

    def set_circuit_breaker(self, cb):
        """Attach a circuit breaker for fill quality and error tracking."""
        self._circuit_breaker = cb

    def get_current_tick(self) -> Tuple[Optional[float], Optional[float]]:
        """
        Get current bid/ask prices.

        Returns:
            Tuple of (bid, ask) or (None, None) if unavailable
        """
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return None, None
        return tick.bid, tick.ask

    def execute_trade(
        self,
        direction: str,
        lot_size: float,
        sl_price: float,
        tp_price: float,
        comment: str = "AdvORB",
        max_retries: int = 3
    ) -> ExecutionResult:
        """
        Execute a trade with slippage protection, verification, and retry logic.

        Args:
            direction: 'BUY' or 'SELL'
            lot_size: Position size
            sl_price: Stop loss price (STRUCTURAL - preserved exactly)
            tp_price: Take profit price (adjusted based on actual entry)
            comment: Trade comment
            max_retries: Maximum retry attempts on requotes

        Returns:
            ExecutionResult with execution details
        """
        cfg = get_config()
        start_time = time_module.time()

        for attempt in range(max_retries):
            # Get current prices
            bid, ask = self.get_current_tick()
            if bid is None:
                if self._circuit_breaker:
                    self._circuit_breaker.record_error("no_tick_data")
                return ExecutionResult(
                    success=False, ticket=None, actual_entry=None,
                    actual_sl=None, actual_tp=None, lot_size=lot_size,
                    slippage=0, error="Cannot get tick data",
                    execution_time_ms=0
                )

            # Determine entry price and order type
            if direction == 'BUY':
                order_type = mt5.ORDER_TYPE_BUY
                entry_price = ask
            else:
                order_type = mt5.ORDER_TYPE_SELL
                entry_price = bid

            # KEEP STRUCTURAL SL - don't recalculate from distance
            # Only adjust TP proportionally based on actual entry vs expected
            actual_sl = sl_price  # Preserve structural SL exactly

            # Calculate TP based on R:R from actual entry to SL
            sl_distance = abs(entry_price - actual_sl)
            original_tp_distance = abs(tp_price - entry_price)

            # Calculate R:R ratio from original TP
            if sl_distance > 0:
                rr_ratio = original_tp_distance / sl_distance
            else:
                rr_ratio = 2.0  # Default

            # Recalculate TP based on actual entry and SL
            if direction == 'BUY':
                actual_tp = entry_price + (sl_distance * rr_ratio)
            else:
                actual_tp = entry_price - (sl_distance * rr_ratio)

            # Build order request with slippage protection
            request = {
                "action": mt5.TRADE_ACTION_DEAL,
                "symbol": self.symbol,
                "volume": lot_size,
                "type": order_type,
                "price": entry_price,
                "sl": actual_sl,
                "tp": actual_tp,
                "deviation": cfg.max_slippage_points,  # Slippage protection!
                "magic": MAGIC_NUMBER,
                "comment": comment,
                "type_time": mt5.ORDER_TIME_GTC,
                "type_filling": mt5.ORDER_FILLING_IOC,
            }

            # Send order
            result = mt5.order_send(request)
            execution_time = int((time_module.time() - start_time) * 1000)

            if result is None:
                error = mt5.last_error()
                logger.error(f"Order send failed: {error}")
                if self._circuit_breaker:
                    self._circuit_breaker.record_error("order_send_null")
                if attempt < max_retries - 1:
                    logger.info(f"Retrying... (attempt {attempt + 2}/{max_retries})")
                    time_module.sleep(0.2)
                    continue
                return ExecutionResult(
                    success=False, ticket=None, actual_entry=None,
                    actual_sl=None, actual_tp=None, lot_size=lot_size,
                    slippage=0, error=f"Order failed: {error}",
                    execution_time_ms=execution_time
                )

            # Handle requotes
            if result.retcode == mt5.TRADE_RETCODE_REQUOTE:
                logger.warning(f"Requote received (attempt {attempt + 1}/{max_retries})")
                if attempt < max_retries - 1:
                    time_module.sleep(0.1)
                    continue
                if self._circuit_breaker:
                    self._circuit_breaker.record_error("requote_max_retries")
                return ExecutionResult(
                    success=False, ticket=None, actual_entry=None,
                    actual_sl=None, actual_tp=None, lot_size=lot_size,
                    slippage=0, error="Requote - max retries exceeded",
                    execution_time_ms=execution_time
                )

            if result.retcode != mt5.TRADE_RETCODE_DONE:
                logger.error(f"Order rejected: {result.retcode} - {result.comment}")
                if self._circuit_breaker:
                    self._circuit_breaker.record_error(f"retcode_{result.retcode}")
                return ExecutionResult(
                    success=False, ticket=None, actual_entry=None,
                    actual_sl=None, actual_tp=None, lot_size=lot_size,
                    slippage=0, error=f"Rejected: {result.comment}",
                    execution_time_ms=execution_time
                )

            # CRITICAL: Verify position exists
            time_module.sleep(0.1)  # Brief delay for position to register
            position = self._verify_position(result.order)

            if position is None:
                logger.error(f"Position verification failed for ticket {result.order}")
                if self._circuit_breaker:
                    self._circuit_breaker.record_error("position_verification_failed")
                return ExecutionResult(
                    success=False, ticket=result.order, actual_entry=result.price,
                    actual_sl=actual_sl, actual_tp=actual_tp, lot_size=lot_size,
                    slippage=abs(result.price - entry_price),
                    error="Position verification failed",
                    execution_time_ms=execution_time
                )

            # Calculate actual slippage and audit fill quality
            slippage = abs(result.price - entry_price)
            self._audit_fill_quality(entry_price, result.price, slippage, direction)

            logger.info(
                f"TRADE EXECUTED: {direction} {lot_size} @ {result.price:.2f} "
                f"(req: {entry_price:.2f}, slip: ${slippage:.3f}) | "
                f"SL: {actual_sl:.2f} (structural) | TP: {actual_tp:.2f} | "
                f"Ticket: {result.order} | Verified: True"
            )

            return ExecutionResult(
                success=True,
                ticket=result.order,
                actual_entry=result.price,
                actual_sl=actual_sl,
                actual_tp=actual_tp,
                lot_size=lot_size,
                slippage=slippage,
                error=None,
                execution_time_ms=execution_time
            )

        # Should not reach here
        return ExecutionResult(
            success=False, ticket=None, actual_entry=None,
            actual_sl=None, actual_tp=None, lot_size=lot_size,
            slippage=0, error="Max retries exceeded",
            execution_time_ms=int((time_module.time() - start_time) * 1000)
        )

    def _verify_position(self, ticket: int, retries: int = 3) -> Optional[Any]:
        """
        Verify a position exists after execution.

        Args:
            ticket: Order ticket to verify
            retries: Number of verification attempts

        Returns:
            Position object or None if not found
        """
        for attempt in range(retries):
            positions = mt5.positions_get(ticket=ticket)
            if positions and len(positions) > 0:
                return positions[0]
            time_module.sleep(0.1 * (attempt + 1))

        return None

    def _audit_fill_quality(self, requested: float, actual: float, slippage: float, direction: str):
        """Tiered fill quality logging + circuit breaker integration."""
        cfg = get_config()

        if slippage >= cfg.fill_quality_critical_usd:
            logger.critical(
                f"EXCESSIVE SLIPPAGE: ${slippage:.3f} on {direction} "
                f"(requested={requested:.2f}, filled={actual:.2f})"
            )
        elif slippage >= cfg.fill_quality_warn_usd:
            logger.warning(
                f"High slippage: ${slippage:.3f} on {direction} "
                f"(requested={requested:.2f}, filled={actual:.2f})"
            )

        if self._circuit_breaker:
            self._circuit_breaker.record_fill(requested, actual, direction)

    def get_our_positions(self) -> List[PositionInfo]:
        """
        Get all positions opened by this strategy.
        Also cleans up stale _partial_positions entries for closed positions.

        Returns:
            List of PositionInfo objects
        """
        positions = mt5.positions_get(symbol=self.symbol)

        # Collect current open ticket IDs for cleanup
        open_tickets = set()

        if not positions:
            # No positions open - clean up all partial tracking
            if self._partial_positions:
                logger.debug(f"Cleaning up {len(self._partial_positions)} stale partial position entries")
                self._partial_positions.clear()
            return []

        our_positions = []
        for pos in positions:
            if pos.magic == MAGIC_NUMBER:
                open_tickets.add(pos.ticket)
                our_positions.append(PositionInfo(
                    ticket=pos.ticket,
                    direction='BUY' if pos.type == 0 else 'SELL',
                    entry_price=pos.price_open,
                    current_price=pos.price_current,
                    volume=pos.volume,
                    sl=pos.sl,
                    tp=pos.tp,
                    profit=pos.profit,
                    swap=pos.swap,
                    open_time=datetime.utcfromtimestamp(pos.time),
                    comment=pos.comment,
                    is_partial=pos.ticket in self._partial_positions
                ))

        # Clean up stale _partial_positions entries for positions that no longer exist
        stale_tickets = [t for t in self._partial_positions if t not in open_tickets]
        for ticket in stale_tickets:
            logger.debug(f"Removing stale partial position entry: {ticket}")
            del self._partial_positions[ticket]

        return our_positions

    def close_partial(
        self,
        ticket: int,
        percent: int = 50
    ) -> ExecutionResult:
        """
        Close a partial portion of a position.
        Note: After partial close, the remaining position may have a NEW ticket number.

        Args:
            ticket: Position ticket
            percent: Percentage to close (default 50%)

        Returns:
            ExecutionResult
        """
        cfg = get_config()
        start_time = time_module.time()

        # Get position
        positions = mt5.positions_get(ticket=ticket)
        if not positions:
            return ExecutionResult(
                success=False, ticket=ticket, actual_entry=None,
                actual_sl=None, actual_tp=None, lot_size=0,
                slippage=0, error="Position not found",
                execution_time_ms=0
            )

        pos = positions[0]
        volume_to_close = pos.volume * (percent / 100)

        # Round to lot step
        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info:
            volume_to_close = round(volume_to_close / symbol_info.volume_step) * symbol_info.volume_step
            volume_to_close = max(symbol_info.volume_min, volume_to_close)

        # Don't close if remaining would be too small
        remaining = pos.volume - volume_to_close
        if remaining < symbol_info.volume_min:
            volume_to_close = pos.volume  # Close all

        # Determine close price
        bid, ask = self.get_current_tick()
        if pos.type == 0:  # BUY position closes at bid
            close_price = bid
            order_type = mt5.ORDER_TYPE_SELL
        else:  # SELL position closes at ask
            close_price = ask
            order_type = mt5.ORDER_TYPE_BUY

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": self.symbol,
            "volume": volume_to_close,
            "type": order_type,
            "position": ticket,
            "price": close_price,
            "deviation": cfg.max_slippage_points,
            "magic": MAGIC_NUMBER,
            "comment": f"Partial {percent}%",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(request)
        execution_time = int((time_module.time() - start_time) * 1000)

        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            error = result.comment if result else str(mt5.last_error())
            if self._circuit_breaker:
                self._circuit_breaker.record_error("partial_close_failed")
            return ExecutionResult(
                success=False, ticket=ticket, actual_entry=None,
                actual_sl=None, actual_tp=None, lot_size=volume_to_close,
                slippage=0, error=f"Partial close failed: {error}",
                execution_time_ms=execution_time
            )

        # Track partial position state
        self._partial_positions[ticket] = {
            "original_volume": pos.volume,
            "closed_volume": volume_to_close,
            "remaining_volume": pos.volume - volume_to_close,
            "partial_profit": (close_price - pos.price_open) * volume_to_close * 100 if pos.type == 0 else (pos.price_open - close_price) * volume_to_close * 100
        }

        logger.info(f"PARTIAL CLOSE: {percent}% of ticket {ticket} | Closed {volume_to_close} lots")

        return ExecutionResult(
            success=True,
            ticket=ticket,
            actual_entry=close_price,
            actual_sl=None,
            actual_tp=None,
            lot_size=volume_to_close,
            slippage=0,
            error=None,
            execution_time_ms=execution_time
        )

    def close_position(self, ticket: int) -> ExecutionResult:
        """Close an entire position"""
        return self.close_partial(ticket, percent=100)

    def close_all_positions(self, reason: str = "Close all") -> List[ExecutionResult]:
        """Close all positions opened by this strategy"""
        results = []
        positions = self.get_our_positions()

        for pos in positions:
            result = self.close_position(pos.ticket)
            result.error = reason if not result.success else None
            results.append(result)

        return results

    def modify_sl(self, ticket: int, new_sl: float) -> bool:
        """
        Modify stop loss for a position.

        Args:
            ticket: Position ticket
            new_sl: New stop loss price

        Returns:
            True if successful
        """
        positions = mt5.positions_get(ticket=ticket)
        if not positions:
            return False

        pos = positions[0]

        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "symbol": self.symbol,
            "position": ticket,
            "sl": new_sl,
            "tp": pos.tp,
            "magic": MAGIC_NUMBER,
        }

        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            logger.error(f"Failed to modify SL: {result.comment if result else 'Unknown error'}")
            return False

        logger.debug(f"SL modified: Ticket {ticket} -> SL {new_sl:.2f}")
        return True

    def modify_tp(self, ticket: int, new_tp: float) -> bool:
        """
        Modify take profit for a position.

        Args:
            ticket: Position ticket
            new_tp: New take profit price

        Returns:
            True if successful
        """
        positions = mt5.positions_get(ticket=ticket)
        if not positions:
            return False

        pos = positions[0]

        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "symbol": self.symbol,
            "position": ticket,
            "sl": pos.sl,
            "tp": new_tp,
            "magic": MAGIC_NUMBER,
        }

        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            return False

        return True

    def _get_current_position_ticket(self, original_ticket: int) -> Optional[int]:
        """
        Get current ticket for a position that may have changed after partial close.
        Some brokers assign new tickets after partial closes.

        Args:
            original_ticket: Original position ticket

        Returns:
            Current ticket or None if position not found
        """
        # First try the original ticket
        positions = mt5.positions_get(ticket=original_ticket)
        if positions and len(positions) > 0:
            return original_ticket

        # If not found, search by our magic number for remaining position
        all_positions = mt5.positions_get(symbol=self.symbol)
        if not all_positions:
            return None

        for pos in all_positions:
            if pos.magic == MAGIC_NUMBER:
                # Check if this might be the same position (similar entry price and direction)
                if original_ticket in self._partial_positions:
                    partial_info = self._partial_positions[original_ticket]
                    # This is a heuristic - same volume as remaining
                    if abs(pos.volume - partial_info['remaining_volume']) < 0.001:
                        return pos.ticket

        return None

    def _get_adaptive_trail_multiplier(self, atr: float, df: Optional[pd.DataFrame] = None) -> float:
        """
        Compute vol-regime-adjusted trailing multiplier.

        Low volatility  (ATR < 20th percentile) -> tighter trail (lock more profit)
        Normal volatility                       -> standard multiplier
        High volatility (ATR > 80th percentile) -> wider trail (avoid premature stop)
        """
        cfg = get_config()

        if not cfg.adaptive_trailing:
            return cfg.trailing_atr_multiplier

        if atr is None or atr <= 0 or df is None or len(df) < 50:
            return cfg.trailing_atr_multiplier

        # Cache percentile computation per bar
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
            atr_series = tr.rolling(window=14).mean().dropna()

            if len(atr_series) < 20:
                return cfg.trailing_atr_multiplier

            percentile = float((atr_series < atr).mean())
            self._atr_percentile_cache = percentile
            self._atr_percentile_time = current_bar_time

        if percentile < 0.20:
            factor = cfg.adaptive_trailing_low_vol_factor
        elif percentile > 0.80:
            factor = cfg.adaptive_trailing_high_vol_factor
        else:
            factor = 1.0

        return cfg.trailing_atr_multiplier * factor

    def manage_trailing_stops(self, atr: float, df: Optional[pd.DataFrame] = None) -> Dict[int, str]:
        """
        Manage trailing stops for all open positions with adaptive vol-regime multiplier.

        Args:
            atr: Current ATR value
            df: Optional DataFrame for adaptive trailing percentile calculation

        Returns:
            Dict of ticket -> action taken
        """
        cfg = get_config()
        actions = {}
        positions = self.get_our_positions()

        # Compute adaptive trail multiplier once per call
        trail_multiplier = self._get_adaptive_trail_multiplier(atr, df)

        for pos in positions:
            # Get current ticket (may have changed after partial)
            current_ticket = self._get_current_position_ticket(pos.ticket)
            if current_ticket is None:
                continue

            # Calculate current profit in R
            sl_distance = abs(pos.entry_price - pos.sl)
            if sl_distance == 0:
                continue

            if pos.direction == 'BUY':
                current_profit_distance = pos.current_price - pos.entry_price
            else:
                current_profit_distance = pos.entry_price - pos.current_price

            current_r = current_profit_distance / sl_distance

            # Step 1: Move to breakeven at configured R level
            if current_r >= cfg.move_to_breakeven_at_rr:
                if pos.direction == 'BUY' and pos.sl < pos.entry_price:
                    # Move SL to entry + small buffer
                    new_sl = pos.entry_price + 0.10
                    if self.modify_sl(current_ticket, new_sl):
                        actions[current_ticket] = "moved_to_breakeven"
                        continue
                elif pos.direction == 'SELL' and pos.sl > pos.entry_price:
                    new_sl = pos.entry_price - 0.10
                    if self.modify_sl(current_ticket, new_sl):
                        actions[current_ticket] = "moved_to_breakeven"
                        continue

            # Step 2: ATR trailing stop with adaptive multiplier
            if cfg.use_trailing and current_r >= 1.0:
                trailing_distance = atr * trail_multiplier

                if pos.direction == 'BUY':
                    new_sl = pos.current_price - trailing_distance
                    # Only move SL up, never down
                    if new_sl > pos.sl:
                        if self.modify_sl(current_ticket, new_sl):
                            actions[current_ticket] = f"trail_to_{new_sl:.2f}(mul:{trail_multiplier:.2f})"
                else:
                    new_sl = pos.current_price + trailing_distance
                    # Only move SL down, never up
                    if new_sl < pos.sl:
                        if self.modify_sl(current_ticket, new_sl):
                            actions[current_ticket] = f"trail_to_{new_sl:.2f}(mul:{trail_multiplier:.2f})"

        return actions

    def manage_partial_profits(self) -> Dict[int, str]:
        """
        Manage partial profit taking for open positions.

        Returns:
            Dict of ticket -> action taken
        """
        cfg = get_config()
        if not cfg.enable_partial_tp:
            return {}

        actions = {}
        positions = self.get_our_positions()

        for pos in positions:
            # Skip if already partially closed
            if pos.ticket in self._partial_positions:
                continue

            # Calculate current profit in R
            sl_distance = abs(pos.entry_price - pos.sl)
            if sl_distance == 0:
                continue

            if pos.direction == 'BUY':
                current_profit_distance = pos.current_price - pos.entry_price
            else:
                current_profit_distance = pos.entry_price - pos.current_price

            current_r = current_profit_distance / sl_distance

            # Take partial profit at first target
            if current_r >= cfg.first_tp_rr:
                result = self.close_partial(pos.ticket, cfg.partial_tp_percent)
                if result.success:
                    actions[pos.ticket] = f"partial_tp_{cfg.partial_tp_percent}%"

                    # Move SL to breakeven for remainder
                    # Find the new ticket if it changed
                    new_ticket = self._get_current_position_ticket(pos.ticket)
                    if new_ticket:
                        if pos.direction == 'BUY':
                            self.modify_sl(new_ticket, pos.entry_price + 0.10)
                        else:
                            self.modify_sl(new_ticket, pos.entry_price - 0.10)

        return actions
