"""
Shared risk management: Position sizing, daily limits, exposure control.
Parameterizable version used by all live strategies.
"""

import MetaTrader5 as mt5
from datetime import datetime, timedelta


class RiskManager:
    """Manages all risk parameters and position sizing."""

    def __init__(self, symbol, magic_number, risk_percent=1.0, max_spread=0.40,
                 max_daily_loss=-150.0, max_total_risk=200.0, max_daily_trades=2,
                 initial_balance=10000.0, min_sl=1.0, max_sl=10.0, logger=None):
        """
        Args:
            symbol: Trading symbol
            magic_number: Unique magic number for this strategy
            risk_percent: Risk per trade as % of balance
            max_spread: Maximum spread allowed (USD)
            max_daily_loss: Stop trading after this loss (negative USD)
            max_total_risk: Max cumulative open position risk (USD)
            max_daily_trades: Maximum trades per day
            initial_balance: Capital allocation for position sizing
            min_sl: Minimum stop loss distance (USD)
            max_sl: Maximum stop loss distance (USD)
            logger: Logger instance
        """
        self.symbol = symbol
        self.magic_number = magic_number
        self.risk_percent = risk_percent
        self.max_spread = max_spread
        self.max_daily_loss = -abs(max_daily_loss)
        self.max_total_risk = max_total_risk
        self.max_daily_trades = max_daily_trades
        self.initial_balance = initial_balance
        self.min_sl = min_sl
        self.max_sl = max_sl
        self.logger = logger

        self.daily_trades_count = 0
        self.daily_profit = 0.0
        self.can_trade = False

    def _log(self, level, msg):
        if self.logger:
            getattr(self.logger, level)(msg)

    def check_daily_status(self, is_trending=True):
        """
        Check if trading is allowed today based on rules.

        Args:
            is_trending: bool from trend filter
        """
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            self.can_trade = is_trending
            self.daily_profit = 0.0
            self.daily_trades_count = 0
            return
        broker_now = datetime.fromtimestamp(tick.time)
        # Use broker's day start (midnight) instead of rolling 24h window
        # This aligns with session-based daily resets
        from_time = broker_now.replace(hour=0, minute=0, second=0, microsecond=0)

        deals = mt5.history_deals_get(from_time, broker_now)
        if deals is None:
            self.can_trade = is_trending
            self.daily_profit = 0.0
            self.daily_trades_count = 0
            return

        our_deals = [d for d in deals
                     if d.magic == self.magic_number and
                     d.entry == mt5.DEAL_ENTRY_OUT and
                     d.symbol == self.symbol]

        self.daily_trades_count = len(our_deals)
        self.daily_profit = sum(d.profit for d in our_deals)

        if self.daily_profit <= self.max_daily_loss:
            self.can_trade = False
            self._log('warning', f"DAILY LOSS LIMIT HIT: ${self.daily_profit:.2f}")
            return

        if self.daily_trades_count >= self.max_daily_trades:
            self.can_trade = False
            self._log('info', f"Max trades reached ({self.daily_trades_count})")
        else:
            self.can_trade = True

        self.can_trade = self.can_trade and is_trending

        if not is_trending:
            self._log('info', "Not trending - no trades allowed")

        self._log('info',
                  f"Daily P&L: ${self.daily_profit:.2f} | "
                  f"Trades: {self.daily_trades_count}/{self.max_daily_trades} | "
                  f"Can Trade: {self.can_trade}")

    def calculate_position_size(self, sl_distance_usd):
        """
        Calculate lot size based on risk percentage.

        Args:
            sl_distance_usd: Stop loss distance in USD

        Returns:
            float: Lot size
        """
        account = mt5.account_info()
        if account is None:
            self._log('error', "Failed to get account info")
            return 0.01

        balance = self.initial_balance
        risk_usd = balance * (self.risk_percent / 100.0)
        self._log('debug', f"Using allocated capital: ${balance:.2f} (account: ${account.balance:.2f})")

        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return 0.01

        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return symbol_info.volume_min

        test_lot = 0.01
        profit_calc = mt5.order_calc_profit(
            mt5.ORDER_TYPE_BUY,
            self.symbol,
            test_lot,
            tick.ask,
            tick.ask - sl_distance_usd
        )

        if profit_calc is None or profit_calc == 0:
            sl_points = sl_distance_usd / symbol_info.point
            risk_per_lot = sl_points * symbol_info.trade_tick_value

            if risk_per_lot <= 0:
                return symbol_info.volume_min

            lot = risk_usd / risk_per_lot
        else:
            loss_for_test = abs(profit_calc)
            lot = (risk_usd / loss_for_test) * test_lot

        lot = round(lot / symbol_info.volume_step) * symbol_info.volume_step
        lot = max(symbol_info.volume_min, min(lot, symbol_info.volume_max))

        self._log('debug', f"Risk ${risk_usd:.2f} | SL ${sl_distance_usd:.2f} | Lot: {lot}")
        return lot

    def validate_spread(self):
        """Check if current spread is acceptable."""
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return False

        spread = tick.ask - tick.bid

        if spread > self.max_spread:
            self._log('warning', f"Spread too high: ${spread:.3f} > ${self.max_spread}")
            return False

        return True

    def validate_stop_loss(self, entry_price, sl_price, direction):
        """
        Ensure SL is within acceptable range.

        Returns:
            float: Adjusted SL price
        """
        if direction == 'BUY':
            sl_distance = entry_price - sl_price
        else:
            sl_distance = sl_price - entry_price

        sl_distance = max(self.min_sl, min(self.max_sl, sl_distance))

        if direction == 'BUY':
            adjusted_sl = entry_price - sl_distance
        else:
            adjusted_sl = entry_price + sl_distance

        self._log('debug', f"SL Distance: ${sl_distance:.2f} | Adjusted SL: {adjusted_sl:.2f}")
        return adjusted_sl

    def get_total_open_risk(self):
        """Calculate total risk exposure from open positions."""
        positions = mt5.positions_get(symbol=self.symbol)
        if not positions:
            return 0.0

        total_risk = 0.0
        symbol_info = mt5.symbol_info(self.symbol)
        tick = mt5.symbol_info_tick(self.symbol)

        if symbol_info is None or tick is None:
            return 0.0

        for pos in positions:
            if pos.magic != self.magic_number:
                continue

            if pos.sl == 0.0:
                total_risk += self.initial_balance * (self.risk_percent / 100.0)
                continue

            current_price = tick.bid if pos.type == 0 else tick.ask
            sl_distance = abs(current_price - pos.sl)
            sl_points = sl_distance / symbol_info.point

            risk = pos.volume * sl_points * symbol_info.trade_tick_value
            total_risk += risk

        return total_risk

    def can_open_new_position(self):
        """Check if we can open a new position without exceeding max risk."""
        account = mt5.account_info()
        if account is None:
            return False

        balance = self.initial_balance
        new_trade_risk = balance * (self.risk_percent / 100.0)
        current_risk = self.get_total_open_risk()

        total_if_opened = current_risk + new_trade_risk

        if total_if_opened > self.max_total_risk:
            self._log('warning',
                      f"Max risk exceeded: ${total_if_opened:.2f} > ${self.max_total_risk}")
            return False

        return True
