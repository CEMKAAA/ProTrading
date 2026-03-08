"""
Risk management: Position sizing, daily limits, exposure control.

Institutional-grade risk with:
- Combined P&L (closed + floating) for daily loss check
- Fee-aware position sizing (commission + estimated slippage deducted from risk budget)
- Structural SL preservation (skip, never clamp)
- SL direction validation
- UTC → NY timezone chain for deal counting
- Stop-after-first-win discipline
"""

import MetaTrader5 as mt5
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from .logger import logger
from .config import (
    RISK_PERCENT, MAX_SPREAD_USD, MAX_DAILY_LOSS_USD,
    MAX_TOTAL_RISK_USD, MIN_SL_USD, MAX_SL_USD, MAGIC_NUMBER,
    INITIAL_BALANCE, MAX_DAILY_TRADES, STOP_AFTER_FIRST_WIN,
    TIGHTEN_RISK_AFTER_WIN, RISK_REDUCTION_FACTOR,
    COMMISSION_PER_LOT, ESTIMATED_SLIPPAGE_USD,
)


class RiskManager:
    """Manages all risk parameters and position sizing"""

    def __init__(self, symbol):
        self.symbol = symbol
        self.daily_trades_count = 0
        self.daily_profit = 0.0
        self.can_trade = False
        self.had_winning_trade = False
        self._last_status_key = None
        self._last_status_log_ts = 0.0
        self._status_heartbeat_seconds = 60.0
        # Circuit breaker reference (set externally by strategy)
        self._circuit_breaker = None

    def set_circuit_breaker(self, cb):
        """Attach a circuit breaker for trade result tracking."""
        self._circuit_breaker = cb

    def check_daily_status(self, is_trending):
        """
        Check if trading is allowed today based on rules.

        Uses combined P&L (closed + floating) for the daily loss gate.

        Rules:
        - Stop after daily loss limit (closed + floating P&L)
        - Max 1 trade if first trade won
        - Max N trades per day
        - Only trade in trending markets

        Args:
            is_trending: bool from trend filter

        Returns:
            tuple: (can_trade: bool, reason: str)
        """
        reason = "unknown"

        # Build NY-day bounded deal window from UTC tick timestamp.
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            self.can_trade = False
            self.daily_profit = 0.0
            self.daily_trades_count = 0
            reason = "No tick data — fail-safe block"
            self._log_status_if_needed(reason)
            return False, reason

        utc_now = datetime.fromtimestamp(tick.time, tz=timezone.utc)
        ny_now = utc_now.astimezone(ZoneInfo("America/New_York"))
        ny_day_start = ny_now.replace(hour=0, minute=0, second=0, microsecond=0)
        from_time = ny_day_start.astimezone(timezone.utc)

        deals = mt5.history_deals_get(from_time, utc_now)
        if deals is None:
            self.can_trade = False
            self.daily_profit = 0.0
            self.daily_trades_count = 0
            reason = "No deal history — fail-safe block"
            self._log_status_if_needed(reason)
            return False, reason

        # Filter our trades only (closed exits)
        our_deals = [d for d in deals
                     if d.magic == MAGIC_NUMBER and
                     d.entry == mt5.DEAL_ENTRY_OUT and
                     d.symbol == self.symbol]

        # Ensure deterministic first-trade logic
        our_deals = sorted(our_deals, key=lambda d: d.time)

        # Feed new closed trades to circuit breaker
        if self._circuit_breaker and len(our_deals) > self.daily_trades_count:
            new_deals = our_deals[self.daily_trades_count:]
            for deal in new_deals:
                self._circuit_breaker.record_trade_result(won=(deal.profit > 0))

        self.daily_trades_count = len(our_deals)

        # Closed P&L including commissions and swaps
        closed_pnl = sum(d.profit + d.commission + d.swap for d in our_deals)

        # Floating P&L from open positions
        floating_pnl = 0.0
        positions = mt5.positions_get(symbol=self.symbol)
        if positions:
            for pos in positions:
                if pos.magic == MAGIC_NUMBER:
                    floating_pnl += pos.profit + pos.swap

        # Track if any trade won today (re-derived each check from day's deals)
        self.had_winning_trade = any(d.profit > 0 for d in our_deals)

        # Combined P&L (institutional: don't ignore floating losses)
        total_pnl = closed_pnl + floating_pnl
        self.daily_profit = total_pnl

        # Check daily loss limit against TOTAL P&L
        if total_pnl <= MAX_DAILY_LOSS_USD:
            self.can_trade = False
            reason = f"Daily loss limit hit (${total_pnl:.2f} = closed ${closed_pnl:.2f} + floating ${floating_pnl:.2f})"
            logger.warning(f"DAILY LOSS LIMIT HIT: {reason}")
            self._log_status_if_needed(reason)
            return False, reason

        # Apply trade count rules
        if self.daily_trades_count == 0:
            self.can_trade = True
            reason = "Trading allowed"
        elif self.daily_trades_count >= MAX_DAILY_TRADES:
            self.can_trade = False
            reason = f"Max trades reached ({self.daily_trades_count}/{MAX_DAILY_TRADES})"
            logger.info(reason)
        elif STOP_AFTER_FIRST_WIN and self.daily_trades_count >= 1:
            first_trade = our_deals[0]
            self.can_trade = first_trade.profit <= 0
            if not self.can_trade:
                reason = f"First trade won ${first_trade.profit:.2f} - no more trades today"
                logger.info(reason)
            else:
                reason = "Trading allowed"
        else:
            self.can_trade = True
            reason = "Trading allowed"

        # Apply trend filter
        self.can_trade = self.can_trade and is_trending

        if not is_trending:
            reason = "Market not trending"

        self._log_status_if_needed(reason)
        return self.can_trade, reason

    def _log_status_if_needed(self, reason: str):
        now_ts = datetime.now(tz=timezone.utc).timestamp()
        status_key = (
            self.can_trade,
            self.daily_trades_count,
            round(self.daily_profit, 2),
            reason,
        )
        should_log = (
            status_key != self._last_status_key
            or (now_ts - self._last_status_log_ts) >= self._status_heartbeat_seconds
        )
        if not should_log:
            return

        logger.info(
            f"Daily P&L: ${self.daily_profit:.2f} | Trades: {self.daily_trades_count}/{MAX_DAILY_TRADES} "
            f"| Can Trade: {self.can_trade} | Reason: {reason}"
        )
        self._last_status_key = status_key
        self._last_status_log_ts = now_ts

    def calculate_position_size(self, sl_distance_usd):
        """
        Calculate lot size based on risk percentage with fee deduction.

        The risk budget is reduced by estimated round-trip costs (commission +
        slippage) so the actual max loss on a stopped-out trade stays within
        the configured RISK_PERCENT.

        Args:
            sl_distance_usd: Stop loss distance in USD

        Returns:
            float: Lot size
        """
        account = mt5.account_info()
        if account is None:
            logger.error("Failed to get account info — rejecting trade (no sizing)")
            return 0.0

        # Use configured capital allocation instead of full account balance
        balance = INITIAL_BALANCE
        risk_pct = RISK_PERCENT
        if TIGHTEN_RISK_AFTER_WIN and self.had_winning_trade:
            risk_pct = RISK_PERCENT * RISK_REDUCTION_FACTOR
            logger.debug(f"Risk reduced after win: {RISK_PERCENT}% -> {risk_pct}%")
        risk_usd = balance * (risk_pct / 100.0)
        logger.debug(f"Using allocated capital: ${balance:.2f} (account: ${account.balance:.2f})")

        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return 0.01

        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return symbol_info.volume_min

        # Calculate P&L for test lot
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
                return symbol_info.volume_min

            lot = risk_usd / risk_per_lot
        else:
            # Use MT5 calculation
            loss_for_test = abs(profit_calc)
            lot = (risk_usd / loss_for_test) * test_lot

        # Round to step
        lot = round(lot / symbol_info.volume_step) * symbol_info.volume_step
        # Clamp to limits
        lot = max(symbol_info.volume_min, min(lot, symbol_info.volume_max))

        # Fee-aware refinement: if estimated costs exceed 5% of risk budget,
        # recalculate with reduced risk to keep total loss within bounds.
        estimated_fees = (COMMISSION_PER_LOT * lot) + (ESTIMATED_SLIPPAGE_USD * lot * 2)
        if estimated_fees > risk_usd * 0.05:
            effective_risk = risk_usd - estimated_fees
            if effective_risk > 0:
                if profit_calc is None or profit_calc == 0:
                    sl_points = sl_distance_usd / symbol_info.point
                    risk_per_lot = sl_points * symbol_info.trade_tick_value
                    if risk_per_lot > 0:
                        lot = effective_risk / risk_per_lot
                else:
                    loss_for_test = abs(profit_calc)
                    lot = (effective_risk / loss_for_test) * test_lot

                lot = round(lot / symbol_info.volume_step) * symbol_info.volume_step
                lot = max(symbol_info.volume_min, min(lot, symbol_info.volume_max))
                estimated_fees = (COMMISSION_PER_LOT * lot) + (ESTIMATED_SLIPPAGE_USD * lot * 2)
            else:
                # Fees exceed entire risk budget — clamp to minimum lot
                lot = symbol_info.volume_min
                estimated_fees = (COMMISSION_PER_LOT * lot) + (ESTIMATED_SLIPPAGE_USD * lot * 2)
                logger.warning(
                    f"Fees (${estimated_fees:.2f}) exceed risk budget (${risk_usd:.2f}), "
                    f"clamped to min lot {lot}"
                )

        logger.debug(
            f"Risk ${risk_usd:.2f} | SL ${sl_distance_usd:.2f} | Lot: {lot} | "
            f"Est. fees: ${estimated_fees:.2f}"
        )
        return lot

    def validate_spread(self):
        """
        Check if current spread is acceptable

        Returns:
            bool
        """
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return False

        spread = tick.ask - tick.bid

        if spread > MAX_SPREAD_USD:
            logger.warning(f"Spread too high: ${spread:.3f} > ${MAX_SPREAD_USD}")
            return False

        return True

    def validate_stop_loss(self, entry_price, sl_price, direction):
        """
        Validate structural SL without altering it.

        Args:
            entry_price: Entry price
            sl_price: Proposed stop loss
            direction: 'BUY' or 'SELL'

        Returns:
            float|None: Structural SL if valid, otherwise None
        """
        if direction == 'BUY':
            sl_distance = entry_price - sl_price
            if sl_price >= entry_price:
                logger.warning(f"Invalid BUY SL (not below entry): entry={entry_price:.2f}, sl={sl_price:.2f}")
                return None
        elif direction == 'SELL':
            sl_distance = sl_price - entry_price
            if sl_price <= entry_price:
                logger.warning(f"Invalid SELL SL (not above entry): entry={entry_price:.2f}, sl={sl_price:.2f}")
                return None
        else:
            logger.warning(f"Unknown direction for SL validation: {direction}")
            return None

        if sl_distance < MIN_SL_USD or sl_distance > MAX_SL_USD:
            logger.info(
                f"Skipping setup: structural SL distance ${sl_distance:.2f} outside "
                f"[${MIN_SL_USD:.2f}, ${MAX_SL_USD:.2f}]"
            )
            return None

        logger.debug(f"Structural SL accepted: distance=${sl_distance:.2f}, sl={sl_price:.2f}")
        return sl_price

    def get_total_open_risk(self):
        """
        Calculate total risk exposure from open positions

        Returns:
            float: Total USD at risk
        """
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return 0.0

        total_risk = 0.0
        symbol_info = mt5.symbol_info(self.symbol)
        tick = mt5.symbol_info_tick(self.symbol)

        if symbol_info is None or tick is None:
            return 0.0

        for pos in positions:
            if pos.magic != MAGIC_NUMBER:
                continue

            # If no SL, use configured risk
            if pos.sl == 0.0:
                total_risk += INITIAL_BALANCE * (RISK_PERCENT / 100.0)
                continue

            # Calculate actual risk
            current_price = tick.bid if pos.type == 0 else tick.ask
            sl_distance = abs(current_price - pos.sl)
            sl_points = sl_distance / symbol_info.point

            risk = pos.volume * sl_points * symbol_info.trade_tick_value
            total_risk += risk

        return total_risk

    def can_open_new_position(self):
        """
        Check if we can open a new position without exceeding max risk

        Returns:
            bool
        """
        account = mt5.account_info()
        if account is None:
            return False

        # Use configured capital allocation
        balance = INITIAL_BALANCE
        new_trade_risk = balance * (RISK_PERCENT / 100.0)
        current_risk = self.get_total_open_risk()

        total_if_opened = current_risk + new_trade_risk

        if total_if_opened > MAX_TOTAL_RISK_USD:
            logger.warning(
                f"Max risk exceeded: ${total_if_opened:.2f} > ${MAX_TOTAL_RISK_USD}"
            )
            return False

        return True
