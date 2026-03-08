"""
Risk Management for HTF Reversal Strategy
Position sizing, daily limits, and exposure control
"""

import MetaTrader5 as mt5
from datetime import datetime, timedelta
from .logger import logger
from .config import (
    RISK_PERCENT, MAX_SPREAD_USD, MAX_DAILY_LOSS_USD,
    MAX_TOTAL_RISK_USD, MIN_SL_USD, MAX_SL_USD, MAGIC_NUMBER,
    DEFAULT_RR_RATIO, INITIAL_BALANCE
)


class RiskManager:
    """Manages risk for swing trades"""

    def __init__(self, symbol: str):
        self.symbol = symbol
        self.daily_trades_count = 0
        self.daily_profit = 0.0
        self.can_trade = True

    def check_daily_status(self):
        """Check if trading is allowed based on daily limits"""
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            self.can_trade = False
            return

        broker_now = datetime.fromtimestamp(tick.time)
        from_time = broker_now - timedelta(hours=24)

        deals = mt5.history_deals_get(from_time, broker_now)

        if deals is None:
            self.can_trade = True
            self.daily_profit = 0.0
            self.daily_trades_count = 0
            return

        # Filter our trades
        our_deals = [
            d for d in deals
            if d.magic == MAGIC_NUMBER and
            d.entry == mt5.DEAL_ENTRY_OUT and
            d.symbol == self.symbol
        ]

        self.daily_trades_count = len(our_deals)
        self.daily_profit = sum(d.profit for d in our_deals)

        # Check daily loss limit
        if self.daily_profit <= MAX_DAILY_LOSS_USD:
            self.can_trade = False
            logger.warning(f"Daily loss limit hit: ${self.daily_profit:.2f}")
            return

        self.can_trade = True
        logger.info(
            f"Daily status: P&L ${self.daily_profit:.2f}, "
            f"Trades: {self.daily_trades_count}"
        )

    def calculate_position_size(self, sl_distance_usd: float) -> float:
        """
        Calculate lot size based on risk percentage.

        Args:
            sl_distance_usd: Stop loss distance in USD

        Returns:
            Lot size
        """
        account = mt5.account_info()
        if account is None:
            logger.error("Failed to get account info")
            return 0.01

        # Use configured capital allocation instead of full account balance
        # This allows multiple strategies to share one MT5 account
        balance = INITIAL_BALANCE
        risk_usd = balance * (RISK_PERCENT / 100.0)
        logger.debug(f"Using allocated capital: ${balance:.2f} (account: ${account.balance:.2f})")

        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            return 0.01

        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return symbol_info.volume_min

        # Calculate lot size
        test_lot = 0.01
        profit_calc = mt5.order_calc_profit(
            mt5.ORDER_TYPE_BUY,
            self.symbol,
            test_lot,
            tick.ask,
            tick.ask - sl_distance_usd
        )

        if profit_calc is None or profit_calc == 0:
            # Fallback
            sl_points = sl_distance_usd / symbol_info.point
            risk_per_lot = sl_points * symbol_info.trade_tick_value

            if risk_per_lot <= 0:
                return symbol_info.volume_min

            lot = risk_usd / risk_per_lot
        else:
            loss_for_test = abs(profit_calc)
            lot = (risk_usd / loss_for_test) * test_lot

        # Round and clamp
        lot = round(lot / symbol_info.volume_step) * symbol_info.volume_step
        lot = max(symbol_info.volume_min, min(lot, symbol_info.volume_max))

        logger.debug(f"Position size: {lot} lots (risk ${risk_usd:.2f})")
        return lot

    def validate_spread(self) -> bool:
        """Check if spread is acceptable"""
        tick = mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return False

        spread = tick.ask - tick.bid

        if spread > MAX_SPREAD_USD:
            logger.warning(f"Spread too wide: ${spread:.3f}")
            return False

        return True

    def validate_stop_loss(
        self,
        entry_price: float,
        sl_price: float,
        direction: str
    ) -> float:
        """
        Ensure SL is within acceptable range.

        Args:
            entry_price: Entry price
            sl_price: Proposed SL
            direction: 'BUY' or 'SELL'

        Returns:
            Adjusted SL price
        """
        if direction == 'BUY':
            sl_distance = entry_price - sl_price
        else:
            sl_distance = sl_price - entry_price

        # Clamp
        sl_distance = max(MIN_SL_USD, min(MAX_SL_USD, sl_distance))

        # Adjust
        if direction == 'BUY':
            return entry_price - sl_distance
        else:
            return entry_price + sl_distance

    def calculate_take_profit(
        self,
        entry_price: float,
        sl_price: float,
        direction: str,
        rr_ratio: float = None
    ) -> float:
        """
        Calculate take profit based on R:R ratio.

        Args:
            entry_price: Entry price
            sl_price: Stop loss price
            direction: 'BUY' or 'SELL'
            rr_ratio: Risk/reward ratio (default from config)

        Returns:
            Take profit price
        """
        rr_ratio = rr_ratio or DEFAULT_RR_RATIO
        sl_distance = abs(entry_price - sl_price)
        tp_distance = sl_distance * rr_ratio

        if direction == 'BUY':
            return entry_price + tp_distance
        else:
            return entry_price - tp_distance

    def get_total_open_risk(self) -> float:
        """Calculate total risk from open positions"""
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

            if pos.sl == 0.0:
                total_risk += INITIAL_BALANCE * (RISK_PERCENT / 100.0)
                continue

            current_price = tick.bid if pos.type == 0 else tick.ask
            sl_distance = abs(current_price - pos.sl)
            sl_points = sl_distance / symbol_info.point

            risk = pos.volume * sl_points * symbol_info.trade_tick_value
            total_risk += risk

        return total_risk

    def can_open_new_position(self) -> bool:
        """Check if new position can be opened"""
        account = mt5.account_info()
        if account is None:
            return False

        # Use configured capital allocation
        new_trade_risk = INITIAL_BALANCE * (RISK_PERCENT / 100.0)
        current_risk = self.get_total_open_risk()

        total = current_risk + new_trade_risk

        if total > MAX_TOTAL_RISK_USD:
            logger.warning(f"Max risk exceeded: ${total:.2f}")
            return False

        return True
