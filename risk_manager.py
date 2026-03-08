"""
Risk management: Position sizing, daily limits, exposure control
"""

import MetaTrader5 as mt5
from datetime import datetime, timedelta
from logger import logger
from config import (
    RISK_PERCENT, MAX_SPREAD_USD, MAX_DAILY_LOSS_USD,
    MAX_TOTAL_RISK_USD, MIN_SL_USD, MAX_SL_USD, MAGIC_NUMBER
)


class RiskManager:
    """Manages all risk parameters and position sizing"""
    
    def __init__(self, symbol):
        self.symbol = symbol
        self.daily_trades_count = 0
        self.daily_profit = 0.0
        self.can_trade = False
        
    def check_daily_status(self, is_trending):
        """
        Check if trading is allowed today based on rules
        
        Rules:
        - Stop after daily loss limit
        - Max 1 trade if first trade won
        - Max 2 trades per day
        - Only trade in trending markets
        
        Args:
            is_trending: bool from trend filter
        """
        # Get today's closed trades
        broker_now = datetime.fromtimestamp(mt5.symbol_info_tick(self.symbol).time)
        from_time = broker_now - timedelta(hours=24)
        
        deals = mt5.history_deals_get(from_time, broker_now)
        if deals is None:
            self.can_trade = is_trending
            self.daily_profit = 0.0
            self.daily_trades_count = 0
            return
        
        # Filter our trades only
        our_deals = [d for d in deals 
                     if d.magic == MAGIC_NUMBER and 
                     d.entry == mt5.DEAL_ENTRY_OUT and
                     d.symbol == self.symbol]
        
        self.daily_trades_count = len(our_deals)
        self.daily_profit = sum(d.profit for d in our_deals)
        
        # Check daily loss limit
        if self.daily_profit <= MAX_DAILY_LOSS_USD:
            self.can_trade = False
            logger.warning(f"🛑 DAILY LOSS LIMIT HIT: ${self.daily_profit:.2f}")
            return
        
        # Apply trade count rules
        if self.daily_trades_count == 0:
            self.can_trade = True
        elif self.daily_trades_count == 1:
            # Only take 2nd trade if first was a loss
            first_trade = our_deals[0]
            self.can_trade = first_trade.profit <= 0
            if not self.can_trade:
                logger.info(f"✅ First trade won ${first_trade.profit:.2f} - no more trades today")
        else:
            # Max 2 trades
            self.can_trade = False
            logger.info(f"⛔ Max trades reached ({self.daily_trades_count})")
        
        # Apply trend filter
        self.can_trade = self.can_trade and is_trending
        
        if not is_trending:
            logger.info("⛔ Not trending - no trades allowed")
        
        logger.info(f"📊 Daily P&L: ${self.daily_profit:.2f} | Trades: {self.daily_trades_count}/2 | Can Trade: {self.can_trade}")
    
    def calculate_position_size(self, sl_distance_usd):
        """
        Calculate lot size based on risk percentage
        
        Args:
            sl_distance_usd: Stop loss distance in USD
            
        Returns:
            float: Lot size
        """
        account = mt5.account_info()
        if account is None:
            logger.error("❌ Failed to get account info")
            return 0.01
        
        balance = account.balance
        risk_usd = balance * (RISK_PERCENT / 100.0)
        
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
        
        logger.debug(f"💰 Risk ${risk_usd:.2f} | SL ${sl_distance_usd:.2f} | Lot: {lot}")
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
            logger.warning(f"⚠️ Spread too high: ${spread:.3f} > ${MAX_SPREAD_USD}")
            return False
        
        return True
    
    def validate_stop_loss(self, entry_price, sl_price, direction):
        """
        Ensure SL is within acceptable range
        
        Args:
            entry_price: Entry price
            sl_price: Proposed stop loss
            direction: 'BUY' or 'SELL'
            
        Returns:
            float: Adjusted SL price
        """
        if direction == 'BUY':
            sl_distance = entry_price - sl_price
        else:
            sl_distance = sl_price - entry_price
        
        # Clamp to min/max
        sl_distance = max(MIN_SL_USD, min(MAX_SL_USD, sl_distance))
        
        # Adjust SL
        if direction == 'BUY':
            adjusted_sl = entry_price - sl_distance
        else:
            adjusted_sl = entry_price + sl_distance
        
        logger.debug(f"📏 SL Distance: ${sl_distance:.2f} | Adjusted SL: {adjusted_sl:.2f}")
        return adjusted_sl
    
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
            
            # If no SL, use account risk
            if pos.sl == 0.0:
                account = mt5.account_info()
                if account:
                    total_risk += account.balance * (RISK_PERCENT / 100.0)
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
        
        balance = account.balance
        new_trade_risk = balance * (RISK_PERCENT / 100.0)
        current_risk = self.get_total_open_risk()
        
        total_if_opened = current_risk + new_trade_risk
        
        if total_if_opened > MAX_TOTAL_RISK_USD:
            logger.warning(
                f"⚠️ Max risk exceeded: ${total_if_opened:.2f} > ${MAX_TOTAL_RISK_USD}"
            )
            return False
        
        return True
