"""
Advanced Risk Manager
Proper position sizing with fees, accurate P&L calculation, and dynamic risk adjustment
"""

import MetaTrader5 as mt5
from datetime import datetime, timezone
from typing import Dict, Any, Optional, Tuple, List
from dataclasses import dataclass
from zoneinfo import ZoneInfo

from .logger import logger
from .config import get_config, MAGIC_NUMBER


@dataclass
class DailyPerformance:
    """Track daily trading performance"""
    trades_count: int = 0
    wins: int = 0
    losses: int = 0
    closed_pnl: float = 0.0
    floating_pnl: float = 0.0
    total_pnl: float = 0.0
    had_winning_trade: bool = False
    trades_after_win: int = 0


class AdvancedRiskManager:
    """
    Advanced risk management with:
    - Proper fee calculation
    - Combined P&L (closed + floating)
    - Dynamic risk adjustment
    - Position verification
    """

    def __init__(self, symbol: str):
        self.symbol = symbol
        self.daily_performance = DailyPerformance()
        self.can_trade = False
        self._last_check_time: Optional[datetime] = None
        self._last_status_key: Optional[Tuple[Any, ...]] = None
        self._last_status_log_ts: float = 0.0
        self._status_heartbeat_seconds: float = 60.0
        # Circuit breaker reference (set externally by strategy)
        self._circuit_breaker = None
        self._last_reported_trade_count: int = 0

    def set_circuit_breaker(self, cb):
        """Attach a circuit breaker for trade result tracking."""
        self._circuit_breaker = cb

    def check_daily_status(self, is_trending: bool) -> Tuple[bool, str]:
        """
        Check if trading is allowed today based on comprehensive rules.

        Args:
            is_trending: Whether market is trending

        Returns:
            Tuple of (can_trade, reason)
        """
        cfg = get_config()

        # Build NY-day bounded deal window from UTC tick timestamp.
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            self.can_trade = False
            reason = "Cannot get tick data"
            self._log_status_if_needed(reason, 0.0, 0.0, 0)
            return False, reason

        utc_now = datetime.fromtimestamp(tick.time, tz=timezone.utc)
        ny_now = utc_now.astimezone(ZoneInfo("America/New_York"))
        ny_day_start = ny_now.replace(hour=0, minute=0, second=0, microsecond=0)
        from_time = ny_day_start.astimezone(timezone.utc)

        # Get closed deals (our trades only)
        deals = mt5.history_deals_get(from_time, utc_now)

        closed_trades = []
        closed_pnl = 0.0

        if deals:
            for deal in deals:
                if (deal.magic == MAGIC_NUMBER and
                    deal.entry == mt5.DEAL_ENTRY_OUT and
                    deal.symbol == self.symbol):
                    closed_trades.append(deal)
                    closed_pnl += deal.profit + deal.commission + deal.swap
            closed_trades.sort(key=lambda d: d.time)

        # Get floating P&L from open positions
        positions = mt5.positions_get(symbol=self.symbol)
        floating_pnl = 0.0
        our_positions = []

        if positions:
            for pos in positions:
                if pos.magic == MAGIC_NUMBER:
                    our_positions.append(pos)
                    floating_pnl += pos.profit + pos.swap

        # Calculate total P&L (closed + floating)
        total_pnl = closed_pnl + floating_pnl

        # Update performance tracking
        self.daily_performance.trades_count = len(closed_trades)
        self.daily_performance.closed_pnl = closed_pnl
        self.daily_performance.floating_pnl = floating_pnl
        self.daily_performance.total_pnl = total_pnl

        # Count wins/losses
        wins = sum(1 for d in closed_trades if d.profit > 0)
        losses = sum(1 for d in closed_trades if d.profit <= 0)
        self.daily_performance.wins = wins
        self.daily_performance.losses = losses

        # Feed new closed trades to circuit breaker
        if self._circuit_breaker and len(closed_trades) > self._last_reported_trade_count:
            new_trades = closed_trades[self._last_reported_trade_count:]
            for trade in new_trades:
                self._circuit_breaker.record_trade_result(won=(trade.profit > 0))
        self._last_reported_trade_count = len(closed_trades)

        # Check daily loss limit (use TOTAL P&L including floating)
        if total_pnl <= cfg.max_daily_loss_usd:
            self.can_trade = False
            reason = f"Daily loss limit reached: ${total_pnl:.2f}"
            logger.warning(f"DAILY LOSS LIMIT HIT: ${total_pnl:.2f} (closed: ${closed_pnl:.2f}, floating: ${floating_pnl:.2f})")
            self._log_status_if_needed(reason, total_pnl, floating_pnl, wins)
            return False, reason

        # Check max daily trades
        if len(closed_trades) >= cfg.max_daily_trades:
            self.can_trade = False
            reason = f"Max trades reached: {len(closed_trades)}"
            logger.info(f"Max daily trades reached: {len(closed_trades)}/{cfg.max_daily_trades}")
            self._log_status_if_needed(reason, total_pnl, floating_pnl, wins)
            return False, reason

        # Check if we already have open positions
        if len(our_positions) > 0:
            self.can_trade = False
            reason = f"Already have {len(our_positions)} open position(s)"
            self._log_status_if_needed(reason, total_pnl, floating_pnl, wins)
            return False, reason

        # Stop trading after first winning trade when configured.
        if wins > 0:
            self.daily_performance.had_winning_trade = True

            if cfg.stop_after_first_win:
                self.can_trade = False
                reason = "First trade won - stop for the day"
                self._log_status_if_needed(reason, total_pnl, floating_pnl, wins)
                return False, reason

            # Advanced win management: allow limited trades after first win.
            # Count trades after first win
            if losses == 0:
                # All trades were wins
                trades_after_win = wins - 1
            else:
                # Find first win index
                first_win_idx = next((i for i, d in enumerate(closed_trades) if d.profit > 0), 0)
                trades_after_win = len(closed_trades) - first_win_idx - 1

            self.daily_performance.trades_after_win = trades_after_win

            if trades_after_win >= cfg.max_trades_after_win:
                self.can_trade = False
                reason = f"Max trades after win reached: {trades_after_win}"
                self._log_status_if_needed(reason, total_pnl, floating_pnl, wins)
                return False, reason

        # Apply trend filter
        if not is_trending:
            self.can_trade = False
            reason = "Market not trending"
            self._log_status_if_needed(reason, total_pnl, floating_pnl, wins)
            return False, reason

        self.can_trade = True
        reason = "Trading allowed"
        self._log_status_if_needed(reason, total_pnl, floating_pnl, wins)
        return True, reason

    def _log_status_if_needed(self, reason: str, total_pnl: float, floating_pnl: float, wins: int):
        cfg = get_config()
        now_ts = datetime.now(tz=timezone.utc).timestamp()
        status_key = (
            self.can_trade,
            self.daily_performance.trades_count,
            round(total_pnl, 2),
            round(floating_pnl, 2),
            wins,
            reason,
        )
        should_log = (
            status_key != self._last_status_key
            or (now_ts - self._last_status_log_ts) >= self._status_heartbeat_seconds
        )
        if not should_log:
            return

        logger.info(
            f"Daily Status: P&L ${total_pnl:.2f} (closed: ${self.daily_performance.closed_pnl:.2f}, "
            f"floating: ${floating_pnl:.2f}) | Trades: {self.daily_performance.trades_count}/{cfg.max_daily_trades} "
            f"| Wins: {wins} | Can Trade: {self.can_trade} | Reason: {reason}"
        )
        self._last_status_key = status_key
        self._last_status_log_ts = now_ts

    def get_current_risk_percent(self) -> float:
        """
        Get current risk percentage, adjusted based on daily performance.

        Returns:
            Risk percentage to use
        """
        cfg = get_config()
        base_risk = cfg.risk_percent

        # Reduce risk after a winning trade if configured
        if cfg.tighten_risk_after_win and self.daily_performance.had_winning_trade:
            adjusted_risk = base_risk * cfg.risk_reduction_factor
            logger.debug(f"Risk reduced after win: {base_risk}% -> {adjusted_risk}%")
            return adjusted_risk

        return base_risk

    def calculate_position_size(
        self,
        sl_distance_usd: float,
        include_fees: bool = True
    ) -> Tuple[float, Dict[str, float]]:
        """
        Calculate lot size based on risk with fee consideration.

        Args:
            sl_distance_usd: Stop loss distance in USD
            include_fees: Whether to include estimated fees in calculation

        Returns:
            Tuple of (lot_size, calculation_details)
        """
        cfg = get_config()

        account = mt5.account_info()
        if account is None:
            logger.error("Failed to get account info — rejecting trade (no sizing)")
            return 0.0, {"error": "No account info"}

        # Use configured initial balance for position sizing
        balance = cfg.initial_balance
        risk_percent = self.get_current_risk_percent()
        risk_usd = balance * (risk_percent / 100.0)

        # We'll estimate fees AFTER calculating lot size, then iterate to refine
        # For initial calculation, use the full risk amount
        effective_risk = risk_usd
        estimated_fees = 0.0

        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return 0.0, {"error": "No symbol info"}

        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return symbol_info.volume_min, {"error": "No tick data"}

        # Calculate P&L for test lot using MT5's calculation
        test_lot = 0.01
        profit_calc = mt5.order_calc_profit(
            mt5.ORDER_TYPE_BUY,
            self.symbol,
            test_lot,
            tick.ask,
            tick.ask - sl_distance_usd
        )

        if profit_calc is None or profit_calc == 0:
            # Fallback calculation
            sl_points = sl_distance_usd / symbol_info.point
            risk_per_lot = sl_points * symbol_info.trade_tick_value

            if risk_per_lot <= 0:
                return symbol_info.volume_min, {"error": "Invalid risk calculation"}

            lot = effective_risk / risk_per_lot
        else:
            loss_for_test = abs(profit_calc)
            lot = (effective_risk / loss_for_test) * test_lot

        # Round to step
        lot = round(lot / symbol_info.volume_step) * symbol_info.volume_step

        # Clamp to limits
        lot = max(symbol_info.volume_min, min(lot, symbol_info.volume_max))

        # Now calculate proper fee estimate scaled by lot size and refine
        if include_fees:
            # Estimate round-trip costs scaled by lot size
            estimated_fees = (cfg.commission_per_lot * lot) + (cfg.estimated_slippage_usd * lot * 2)

            # If fees are significant (> 5% of risk), recalculate lot with fee deduction
            if estimated_fees > risk_usd * 0.05:
                effective_risk = risk_usd - estimated_fees

                if effective_risk > 0:
                    # Recalculate lot with reduced risk
                    if profit_calc is None or profit_calc == 0:
                        sl_points = sl_distance_usd / symbol_info.point
                        risk_per_lot = sl_points * symbol_info.trade_tick_value
                        if risk_per_lot > 0:
                            lot = effective_risk / risk_per_lot
                    else:
                        loss_for_test = abs(profit_calc)
                        lot = (effective_risk / loss_for_test) * test_lot

                    # Round and clamp again
                    lot = round(lot / symbol_info.volume_step) * symbol_info.volume_step
                    lot = max(symbol_info.volume_min, min(lot, symbol_info.volume_max))

                    # Recalculate fees with final lot
                    estimated_fees = (cfg.commission_per_lot * lot) + (cfg.estimated_slippage_usd * lot * 2)
                else:
                    # Fees exceed entire risk budget — clamp to minimum lot
                    lot = symbol_info.volume_min
                    estimated_fees = (cfg.commission_per_lot * lot) + (cfg.estimated_slippage_usd * lot * 2)
                    effective_risk = 0.0
                    logger.warning(
                        f"Fees (${estimated_fees:.2f}) exceed risk budget (${risk_usd:.2f}), "
                        f"clamped to min lot {lot}"
                    )

        details = {
            "balance": balance,
            "account_balance": account.balance,
            "risk_percent": risk_percent,
            "risk_usd": risk_usd,
            "effective_risk": effective_risk,
            "sl_distance": sl_distance_usd,
            "estimated_fees": estimated_fees,
            "lot_size": lot,
        }

        logger.debug(
            f"Position Size: Balance ${balance:.2f} | Risk ${effective_risk:.2f} ({risk_percent}%) | "
            f"SL ${sl_distance_usd:.2f} | Lot: {lot}"
        )

        return lot, details

    def validate_spread(self) -> Tuple[bool, float]:
        """
        Check if current spread is acceptable.

        Returns:
            Tuple of (is_valid, current_spread)
        """
        cfg = get_config()

        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return False, 0.0

        spread = tick.ask - tick.bid

        if spread > cfg.max_spread_usd:
            logger.warning(f"Spread too high: ${spread:.3f} > ${cfg.max_spread_usd}")
            return False, spread

        return True, spread

    def validate_stop_loss(
        self,
        entry_price: float,
        sl_price: float,
        direction: str
    ) -> Tuple[Optional[float], float]:
        """
        Validate structural stop loss without clamping it away from structure.

        Args:
            entry_price: Entry price
            sl_price: Proposed stop loss
            direction: 'BUY' or 'SELL'

        Returns:
            Tuple of (validated_sl_price or None, sl_distance)
        """
        cfg = get_config()

        if direction == 'BUY':
            sl_distance = entry_price - sl_price
            if sl_price >= entry_price:
                logger.warning(
                    f"Invalid BUY SL (not below entry): entry={entry_price:.2f}, sl={sl_price:.2f}"
                )
                return None, sl_distance
        elif direction == 'SELL':
            sl_distance = sl_price - entry_price
            if sl_price <= entry_price:
                logger.warning(
                    f"Invalid SELL SL (not above entry): entry={entry_price:.2f}, sl={sl_price:.2f}"
                )
                return None, sl_distance
        else:
            logger.warning(f"Unknown direction for SL validation: {direction}")
            return None, 0.0

        if sl_distance < cfg.min_sl_usd or sl_distance > cfg.max_sl_usd:
            logger.info(
                f"Skipping setup: structural SL distance ${sl_distance:.2f} outside "
                f"[${cfg.min_sl_usd:.2f}, ${cfg.max_sl_usd:.2f}]"
            )
            return None, sl_distance

        return sl_price, sl_distance

    def calculate_take_profit(
        self,
        entry_price: float,
        sl_price: float,
        direction: str,
        partial: bool = False
    ) -> float:
        """
        Calculate take profit based on R:R ratio.

        Args:
            entry_price: Entry price
            sl_price: Stop loss price
            direction: 'BUY' or 'SELL'
            partial: If True, calculate partial TP (first target)

        Returns:
            Take profit price
        """
        cfg = get_config()

        sl_distance = abs(entry_price - sl_price)

        # Determine R:R ratio with a hard floor for expectancy protection.
        if partial:
            rr = cfg.first_tp_rr
        elif sl_distance < cfg.rr_threshold_for_2r:
            rr = cfg.rr_tight_sl_target
        else:
            rr = cfg.rr_wide_sl_target
        if not partial:
            rr = max(cfg.min_rr_target, rr)

        tp_distance = sl_distance * rr

        if direction == 'BUY':
            return entry_price + tp_distance
        else:
            return entry_price - tp_distance

    def get_total_open_risk(self) -> float:
        """
        Calculate total risk exposure from open positions (our positions only).

        Returns:
            Total USD at risk
        """
        cfg = get_config()

        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return 0.0

        total_risk = 0.0
        symbol_info = mt5.symbol_info(self.symbol)
        tick = mt5.symbol_info_tick(self.symbol)

        if symbol_info is None or tick is None:
            return 0.0

        for pos in positions:
            # Only count our positions
            if pos.magic != MAGIC_NUMBER:
                continue

            if pos.sl == 0.0:
                # No SL set, use configured risk as estimate
                total_risk += cfg.initial_balance * (cfg.risk_percent / 100.0)
                continue

            # Calculate actual risk from current price to SL
            current_price = tick.bid if pos.type == 0 else tick.ask
            sl_distance = abs(current_price - pos.sl)
            sl_points = sl_distance / symbol_info.point

            risk = pos.volume * sl_points * symbol_info.trade_tick_value
            total_risk += risk

        return total_risk

    def can_open_new_position(self) -> Tuple[bool, str]:
        """
        Check if we can open a new position without exceeding max risk.

        Returns:
            Tuple of (can_open, reason)
        """
        cfg = get_config()

        account = mt5.account_info()
        if account is None:
            return False, "Cannot get account info"

        # Use configured balance
        balance = cfg.initial_balance
        new_trade_risk = balance * (self.get_current_risk_percent() / 100.0)
        current_risk = self.get_total_open_risk()

        total_if_opened = current_risk + new_trade_risk

        if total_if_opened > cfg.max_total_risk_usd:
            reason = f"Max risk exceeded: ${total_if_opened:.2f} > ${cfg.max_total_risk_usd}"
            logger.warning(reason)
            return False, reason

        return True, "OK"

    def get_daily_performance(self) -> DailyPerformance:
        """Get current daily performance metrics"""
        return self.daily_performance

    def reset_daily_state(self):
        """Reset daily performance tracking for new trading day"""
        self.daily_performance = DailyPerformance()
        self.can_trade = False
        self._last_check_time = None
        self._last_reported_trade_count = 0
        logger.info("Risk manager daily state reset")

    def estimate_trade_costs(self, lot_size: float) -> Dict[str, float]:
        """
        Estimate total costs for a trade.

        Args:
            lot_size: Position size

        Returns:
            Dict with cost breakdown
        """
        cfg = get_config()

        commission = cfg.commission_per_lot * lot_size
        slippage_estimate = cfg.estimated_slippage_usd * lot_size * 2  # Entry + Exit
        spread_cost = self.validate_spread()[1] * lot_size * 100  # Approximate

        return {
            "commission": commission,
            "slippage_estimate": slippage_estimate,
            "spread_cost": spread_cost,
            "total_estimate": commission + slippage_estimate + spread_cost
        }
