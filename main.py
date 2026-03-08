"""
Main Trading Bot - Orchestrates all components
"""

import MetaTrader5 as mt5
from datetime import datetime, time, timezone
import time as time_module
import pytz

from logger import logger
from config import (
    TARGET_SYMBOL, MAGIC_NUMBER,
    ORB_END_TIME, TRADE_START_TIME, TRADE_END_TIME,
    NO_TRADE_WINDOWS, MIN_BARS_FOR_ANALYSIS
)
from data_manager import DataManager
from session_analyzer import SessionAnalyzer
from ict_analyzer import ICTAnalyzer
from risk_manager import RiskManager
from trade_executor import TradeExecutor
from bot_state import BotStateManager


class GoldORBBot:
    """
    Advanced Gold ORB Trading Bot with ICT Concepts
    
    Features:
    - Fair Value Gaps (FVG)
    - Order Blocks (OB)
    - Liquidity detection
    - Multi-session analysis (Asian, London, NY)
    - Dynamic risk management
    - ATR-based trailing stops
    """
    
    def __init__(self):
        # Initialize MT5
        if not mt5.initialize():
            raise RuntimeError(f"MT5 Init Failed: {mt5.last_error()}")
        
        # Verify symbol
        if not mt5.symbol_select(TARGET_SYMBOL, True):
            raise RuntimeError(f"Symbol {TARGET_SYMBOL} not available")
        
        time_module.sleep(1)
        
        # Verify connection
        if mt5.symbol_info_tick(TARGET_SYMBOL) is None:
            raise RuntimeError("No price data available")
        
        # Detect timezone
        self.broker_tz = self._detect_broker_timezone()
        self.ny_tz = pytz.timezone('America/New_York')
        
        # Initialize components
        self.data_manager = DataManager(TARGET_SYMBOL, self.broker_tz, self.ny_tz)
        self.session_analyzer = SessionAnalyzer(self.data_manager)
        self.ict_analyzer = ICTAnalyzer()
        self.risk_manager = RiskManager(TARGET_SYMBOL)
        self.trade_executor = TradeExecutor(TARGET_SYMBOL)
        
        # State
        self.current_date = None
        self.orb_ready = False
        self.last_signal_time = None

        # State manager for dashboard communication
        self.state_manager = BotStateManager()

        logger.info("=" * 60)
        logger.info("🚀 GOLD ORB BOT INITIALIZED")
        logger.info(f"📊 Symbol: {TARGET_SYMBOL}")
        logger.info(f"🎯 Magic: {MAGIC_NUMBER}")
        logger.info(f"⏰ Broker TZ: {self.broker_tz}")
        logger.info("=" * 60)
    
    def _detect_broker_timezone(self):
        """Detect broker server timezone offset from UTC"""
        tick = mt5.symbol_info_tick(TARGET_SYMBOL)
        broker_time = datetime.fromtimestamp(tick.time)
        # Use timezone-aware UTC instead of deprecated utcfromtimestamp
        utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)
        offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
        offset_hours = offset_minutes // 60
        
        logger.info(f"[BROKER TZ] Detected Broker Offset: UTC{'+' if offset_hours >= 0 else ''}{offset_hours}")
        return pytz.FixedOffset(offset_minutes)
    
    def _get_current_time_ny(self):
        """Get current time in NY timezone"""
        tick = mt5.symbol_info_tick(TARGET_SYMBOL)
        if tick is None:
            return None
        
        broker_now = datetime.fromtimestamp(tick.time).replace(tzinfo=self.broker_tz)
        return broker_now.astimezone(self.ny_tz)
    
    def _is_in_news_window(self, now):
        """Check if current time is in a news blackout window"""
        for start, end in NO_TRADE_WINDOWS:
            if start <= now <= end:
                logger.info(f"⏸️ In news blackout: {start} - {end}")
                return True
        return False
    
    def _update_dashboard_state(self, now):
        """Update state for dashboard"""
        try:
            # Get current tick
            tick = mt5.symbol_info_tick(TARGET_SYMBOL)
            current_price = tick.bid if tick else None
            spread = round(tick.ask - tick.bid, 3) if tick else None

            # Get account info
            account = mt5.account_info()
            balance = account.balance if account else 0.0
            equity = account.equity if account else 0.0
            margin_level = (account.equity / account.margin * 100) if account and account.margin > 0 else None

            # Get open positions
            positions = mt5.positions_get(symbol=TARGET_SYMBOL)
            open_positions = len(positions) if positions else 0

            # Calculate daily P&L from positions
            daily_pnl = sum(p.profit for p in positions) if positions else 0.0

            self.state_manager.update_state(
                is_running=True,
                current_time_ny=now.isoformat() if now else None,
                current_price=current_price,
                spread=spread,
                session_bias=self.session_analyzer.bias if hasattr(self.session_analyzer, 'bias') else None,
                is_trending=self.session_analyzer.is_trending if hasattr(self.session_analyzer, 'is_trending') else False,
                orb_high=self.session_analyzer.orb_high if hasattr(self.session_analyzer, 'orb_high') else None,
                orb_low=self.session_analyzer.orb_low if hasattr(self.session_analyzer, 'orb_low') else None,
                asian_high=self.session_analyzer.asian_high if hasattr(self.session_analyzer, 'asian_high') else None,
                asian_low=self.session_analyzer.asian_low if hasattr(self.session_analyzer, 'asian_low') else None,
                daily_trades=self.risk_manager.daily_trade_count if hasattr(self.risk_manager, 'daily_trade_count') else 0,
                daily_pnl=daily_pnl,
                can_trade=self.risk_manager.can_trade if hasattr(self.risk_manager, 'can_trade') else False,
                balance=balance,
                equity=equity,
                margin_level=margin_level,
                open_positions=open_positions,
            )
        except Exception as e:
            logger.debug(f"State update error: {e}")

    def _handle_new_day(self, today):
        """Reset and prepare for new trading day"""
        self.current_date = today
        self.orb_ready = False
        self.last_signal_time = None
        
        # Reset components
        self.session_analyzer.reset()
        self.data_manager.clear_cache()
        self.trade_executor.last_atr_time = None
        self.trade_executor.cached_atr = None
        
        # Analyze premarket
        self.session_analyzer.analyze_premarket(today)
        
        logger.info("=" * 60)
        logger.info(f"📅 NEW TRADING DAY: {today}")
        logger.info("=" * 60)
    
    def _check_orb_ready(self, now):
        """Calculate ORB if time is right"""
        if self.orb_ready:
            return True
        
        if now.time() < ORB_END_TIME:
            return False
        
        # Calculate ORB
        orb_calculated = self.session_analyzer.calculate_orb(self.current_date)
        
        if orb_calculated and self.session_analyzer.is_orb_valid():
            self.orb_ready = True
            return True
        
        return False
    
    def _find_trade_setup(self, df):
        """
        Scan for trade setups based on ICT concepts
        
        Returns:
            dict with setup info or None
        """
        bias = self.session_analyzer.bias
        
        if bias == 'neutral':
            return None
        
        # Check for breakout
        current_close = df.iloc[-2].close
        
        # Bullish setup
        if bias == 'bullish' and current_close > self.session_analyzer.orb_high:
            # Look for FVG
            fvg = self.ict_analyzer.find_fvg(df, 'bullish')
            
            if fvg:
                logger.info(f"🟢 Bullish FVG found | Gap: ${fvg['size']:.2f}")
                
                # Look for order block for confluence
                ob = self.ict_analyzer.find_order_block(df, 'bullish')
                
                # Entry at FVG bottom (or OB if available)
                entry = df.iloc[-2].close
                
                if ob:
                    sl = ob['low']
                    logger.info(f"📦 Bullish OB found @ {ob['low']:.2f}")
                else:
                    sl = fvg['bottom']
                
                return {
                    'direction': 'BUY',
                    'entry': entry,
                    'sl': sl,
                    'reason': 'Bullish FVG + ORB Breakout'
                }
        
        # Bearish setup
        elif bias == 'bearish' and current_close < self.session_analyzer.orb_low:
            # Look for FVG
            fvg = self.ict_analyzer.find_fvg(df, 'bearish')
            
            if fvg:
                logger.info(f"🔴 Bearish FVG found | Gap: ${fvg['size']:.2f}")
                
                # Look for order block
                ob = self.ict_analyzer.find_order_block(df, 'bearish')
                
                entry = df.iloc[-2].close
                
                if ob:
                    sl = ob['high']
                    logger.info(f"📦 Bearish OB found @ {ob['high']:.2f}")
                else:
                    sl = fvg['top']
                
                return {
                    'direction': 'SELL',
                    'entry': entry,
                    'sl': sl,
                    'reason': 'Bearish FVG + ORB Breakout'
                }
        
        return None
    
    def _execute_setup(self, setup):
        """
        Execute trade from setup
        
        Args:
            setup: dict from _find_trade_setup
        """
        direction = setup['direction']
        entry = setup['entry']
        sl = setup['sl']
        
        # Validate spread
        if not self.risk_manager.validate_spread():
            logger.warning("⚠️ Spread too wide - skipping trade")
            return
        
        # Validate SL distance
        sl = self.risk_manager.validate_stop_loss(entry, sl, direction)
        
        # Calculate position size
        sl_distance = abs(entry - sl)
        lot_size = self.risk_manager.calculate_position_size(sl_distance)
        
        # Execute
        success = self.trade_executor.execute_trade(
            direction=direction,
            entry_price=entry,
            sl_price=sl,
            lot_size=lot_size,
            comment=setup['reason'][:31]
        )
        
        if success:
            logger.info(f"✅ TRADE OPENED: {setup['reason']}")
        else:
            logger.error("❌ Trade execution failed")
    
    def run(self):
        """Main bot loop"""
        logger.info("🤖 BOT STARTED - Entering main loop")
        logger.info("")
        
        while True:
            try:
                # Check MT5 connection
                terminal = mt5.terminal_info()
                if terminal is None or not terminal.connected:
                    logger.warning("⚠️ MT5 disconnected - reconnecting...")
                    if not mt5.initialize():
                        time_module.sleep(10)
                        continue
                
                # Get current time
                now = self._get_current_time_ny()
                if now is None:
                    time_module.sleep(1)
                    continue

                # Update dashboard state
                self._update_dashboard_state(now)

                # Handle new day
                if self.current_date != now.date():
                    self._handle_new_day(now.date())
                
                # Friday close
                if now.weekday() == 4 and now.time() > time(15, 30):
                    self.trade_executor.close_all_positions("Friday Close")
                    logger.info("🔒 Friday close - sleeping until Monday")
                    time_module.sleep(300)
                    continue
                
                # Trading hours check
                if not (TRADE_START_TIME <= now.time() <= TRADE_END_TIME):
                    time_module.sleep(30)
                    continue
                
                # News filter
                if self._is_in_news_window(now):
                    time_module.sleep(60)
                    continue
                
                # Manage trailing stops (priority)
                if self.trade_executor.manage_trailing_stops(self.data_manager):
                    time_module.sleep(1)
                    continue
                
                # Check if we can trade
                self.risk_manager.check_daily_status(
                    self.session_analyzer.is_trending
                )
                
                if not self.risk_manager.can_trade:
                    time_module.sleep(60)
                    continue
                
                # Check max risk
                if not self.risk_manager.can_open_new_position():
                    time_module.sleep(30)
                    continue
                
                # Get data
                df = self.data_manager.get_data()
                
                if df.empty or len(df) < MIN_BARS_FOR_ANALYSIS:
                    logger.warning("⚠️ Insufficient data")
                    time_module.sleep(5)
                    continue
                
                # Wait for ORB
                if not self._check_orb_ready(now):
                    time_module.sleep(10)
                    continue
                
                # Prevent duplicate signals
                signal_time = df.index[-2]
                if self.last_signal_time == signal_time:
                    time_module.sleep(1)
                    continue
                
                self.last_signal_time = signal_time
                
                # Look for setup
                setup = self._find_trade_setup(df)
                
                if setup:
                    logger.info(f"🎯 SETUP FOUND: {setup['reason']}")
                    self._execute_setup(setup)
                
                # Sleep between iterations
                time_module.sleep(2)
            
            except KeyboardInterrupt:
                logger.info("⏹️ Bot stopped by user")
                break
            
            except Exception as e:
                logger.error(f"❌ Loop error: {e}", exc_info=True)
                time_module.sleep(5)
        
        # Cleanup
        self.state_manager.set_stopped()
        mt5.shutdown()
        logger.info("👋 Bot shutdown complete")


def main():
    """Entry point"""
    try:
        bot = GoldORBBot()
        bot.run()
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}", exc_info=True)
        mt5.shutdown()


if __name__ == "__main__":
    main()
