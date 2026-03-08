"""
HTF Reversal Strategy Class - Registered with StrategyRegistry
"""

import sys
import os

# Add parent paths for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any, List
from datetime import datetime, time, timezone
import time as time_module
import pytz

from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class HTFReversalStrategy(BaseStrategy):
    """
    Multi-Timeframe Key Level Reversal Strategy

    Strategy Logic:
    1. Mark key highs/lows on Monthly, Weekly, Daily
    2. Wait for price to reach a key level
    3. Look for consolidation on H4
    4. Wait for spike/breakout of consolidation
    5. Enter on reversal patterns with confluences
    6. Exit when H4 closes below/above entry candle wick
    7. Take profit at broken S/R retest areas
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="htf_reversal_strategy",
            name="HTF Reversal Strategy",
            description="Multi-timeframe key level reversal trading. Analyzes Monthly, Weekly, Daily for key levels, uses H4 for structure, and H1 for entry timing.",
            version="1.0.0",
            author="ProTrading",
            timeframes=["MN1", "W1", "D1", "H4", "H1"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.50,
                "level_proximity_usd": 3.0,
                "min_confluence_score": 2.0,
            }
        )

    def __init__(self):
        super().__init__()
        self.mt5 = None
        self.logger = None

    def initialize(self) -> bool:
        """Initialize strategy components"""
        try:
            import MetaTrader5 as mt5
            from .config import TARGET_SYMBOL, MAGIC_NUMBER
            from .logger import logger
            from .data_manager import MultiTimeframeDataManager
            from .htf_analyzer import HTFAnalyzer
            from .structure_analyzer import StructureAnalyzer
            from .reversal_detector import ReversalDetector
            from .risk_manager import RiskManager
            from .trade_executor import TradeExecutor
            from .bot_state import BotStateManager

            # Initialize MT5
            if not mt5.initialize():
                self.error_message = f"MT5 Init Failed: {mt5.last_error()}"
                return False

            if not mt5.symbol_select(TARGET_SYMBOL, True):
                self.error_message = f"Symbol {TARGET_SYMBOL} not available"
                return False

            time_module.sleep(1)

            if mt5.symbol_info_tick(TARGET_SYMBOL) is None:
                self.error_message = "No price data available"
                return False

            # Store references
            self.mt5 = mt5
            self.logger = logger
            self.symbol = TARGET_SYMBOL
            self.magic = MAGIC_NUMBER

            # Timezone setup
            self.broker_tz = self._detect_broker_timezone()
            self.ny_tz = pytz.timezone('America/New_York')

            # Initialize components
            self.data_manager = MultiTimeframeDataManager(TARGET_SYMBOL, self.broker_tz, self.ny_tz)
            self.htf_analyzer = HTFAnalyzer(self.data_manager)
            self.structure_analyzer = StructureAnalyzer(self.data_manager)
            self.reversal_detector = ReversalDetector(self.data_manager)
            self.risk_manager = RiskManager(TARGET_SYMBOL)
            self.trade_executor = TradeExecutor(TARGET_SYMBOL)
            self.state_manager = BotStateManager()

            # State
            self.current_date = None
            self.key_levels_analyzed = False
            self.last_check_time = None

            logger.info("=" * 60)
            logger.info("HTF REVERSAL STRATEGY INITIALIZED")
            logger.info(f"Symbol: {TARGET_SYMBOL}")
            logger.info(f"Magic: {MAGIC_NUMBER}")
            logger.info("=" * 60)

            return True

        except Exception as e:
            self.error_message = str(e)
            return False

    def _detect_broker_timezone(self):
        """Detect broker timezone"""
        tick = self.mt5.symbol_info_tick(self.symbol)
        broker_time = datetime.fromtimestamp(tick.time)
        utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)
        offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
        return pytz.FixedOffset(offset_minutes)

    def run(self):
        """Main strategy loop"""
        from .config import TRADE_START_TIME, TRADE_END_TIME, LEVEL_PROXIMITY_USD

        self.logger.info("HTF REVERSAL STRATEGY STARTED")

        while self._running:
            try:
                # Check MT5 connection
                terminal = self.mt5.terminal_info()
                if terminal is None or not terminal.connected:
                    self.logger.warning("MT5 disconnected - reconnecting...")
                    if not self.mt5.initialize():
                        time_module.sleep(10)
                        continue

                # Get current time
                now = self._get_current_time_ny()
                if now is None:
                    time_module.sleep(1)
                    continue

                # Update dashboard state
                self._update_dashboard_state(now)

                # Handle new day - re-analyze key levels
                if self.current_date != now.date():
                    self._handle_new_day(now.date())

                # Weekend check
                if now.weekday() >= 5:
                    time_module.sleep(300)
                    continue

                # Trading hours check (wider for swing trading)
                if not (TRADE_START_TIME <= now.time() <= TRADE_END_TIME):
                    time_module.sleep(60)
                    continue

                # Manage existing positions (priority)
                broken_levels = [l.price for l in self.htf_analyzer.broken_levels]
                self.trade_executor.manage_positions(broken_levels)

                # Check if we can trade
                self.risk_manager.check_daily_status()
                if not self.risk_manager.can_trade:
                    time_module.sleep(60)
                    continue

                if not self.risk_manager.can_open_new_position():
                    time_module.sleep(30)
                    continue

                # Get current price
                current_price = self.data_manager.get_current_price()
                if current_price is None:
                    time_module.sleep(5)
                    continue

                # Check if price is at a key level
                at_level, key_level = self.htf_analyzer.is_at_key_level(
                    current_price, LEVEL_PROXIMITY_USD
                )

                if not at_level:
                    # Not at a key level, wait
                    time_module.sleep(30)
                    continue

                self.logger.info(
                    f"Price at key level: {key_level.timeframe} "
                    f"{key_level.level_type} @ ${key_level.price:.2f}"
                )

                # Analyze structure for reversal
                structure_result = self.structure_analyzer.analyze_for_reversal(
                    key_level.price,
                    key_level.level_type
                )

                if not structure_result['reversal_ready']:
                    time_module.sleep(60)
                    continue

                # Stack confluences
                suggested_dir = structure_result['suggested_direction']
                confluence = self.reversal_detector.analyze_confluence(
                    key_level.price,
                    suggested_dir
                )

                # Check if entry is valid
                if not self.reversal_detector.is_entry_valid(confluence, min_score=2.0):
                    self.logger.info(
                        f"Confluence score {confluence.total_score:.1f} - "
                        "waiting for better setup"
                    )
                    time_module.sleep(60)
                    continue

                # Execute trade
                self._execute_reversal_trade(
                    key_level,
                    suggested_dir,
                    confluence
                )

                # Mark level as being traded
                self.htf_analyzer.mark_level_broken(key_level)

                # Sleep after trade
                time_module.sleep(300)

            except KeyboardInterrupt:
                self.logger.info("Strategy stopped by user")
                break

            except Exception as e:
                self.logger.error(f"Loop error: {e}", exc_info=True)
                time_module.sleep(10)

    def shutdown(self):
        """Cleanup and shutdown"""
        if hasattr(self, 'state_manager'):
            self.state_manager.set_stopped()
        if hasattr(self, 'mt5'):
            self.mt5.shutdown()
        if hasattr(self, 'logger'):
            self.logger.info("Strategy shutdown complete")

    def get_state(self) -> Dict[str, Any]:
        """Return current state for dashboard"""
        if hasattr(self, 'state_manager'):
            return self.state_manager.read_state()
        return {
            "strategy_id": "htf_reversal_strategy",
            "is_connected": False,
            "is_running": self._running,
            "status": self.status.value,
        }

    def _get_current_time_ny(self):
        """Get current time in NY timezone"""
        tick = self.mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return None

        broker_now = datetime.fromtimestamp(tick.time).replace(tzinfo=self.broker_tz)
        return broker_now.astimezone(self.ny_tz)

    def _handle_new_day(self, today):
        """Handle new trading day"""
        self.current_date = today
        self.key_levels_analyzed = False

        self.logger.info("=" * 60)
        self.logger.info(f"NEW TRADING DAY: {today}")
        self.logger.info("=" * 60)

        # Analyze all HTF levels
        self.htf_analyzer.analyze_all_timeframes()
        self.htf_analyzer.log_levels()
        self.key_levels_analyzed = True

        # Clear data cache
        self.data_manager.clear_cache()

    def _update_dashboard_state(self, now):
        """Update state for dashboard"""
        try:
            tick = self.mt5.symbol_info_tick(self.symbol)
            current_price = tick.bid if tick else None
            spread = round(tick.ask - tick.bid, 3) if tick else None

            account = self.mt5.account_info()
            balance = account.balance if account else 0.0
            equity = account.equity if account else 0.0

            positions = self.mt5.positions_get(symbol=self.symbol)
            open_positions = len(positions) if positions else 0
            daily_pnl = sum(p.profit for p in positions) if positions else 0.0

            # Get key levels info
            key_levels_info = []
            for level in self.htf_analyzer.key_levels[:10]:  # Top 10
                key_levels_info.append({
                    'price': level.price,
                    'type': level.level_type,
                    'timeframe': level.timeframe,
                    'strength': level.strength,
                })

            # Check if at key level
            at_level, nearest = self.htf_analyzer.is_at_key_level(current_price or 0)
            nearest_info = None
            if nearest:
                nearest_info = {
                    'price': nearest.price,
                    'type': nearest.level_type,
                    'timeframe': nearest.timeframe,
                }

            self.state_manager.update_state(
                is_running=True,
                current_time_ny=now.isoformat() if now else None,
                current_price=current_price,
                spread=spread,
                key_levels=key_levels_info,
                nearest_level=nearest_info,
                at_key_level=at_level,
                daily_trades=self.risk_manager.daily_trades_count,
                daily_pnl=daily_pnl,
                can_trade=self.risk_manager.can_trade,
                balance=balance,
                equity=equity,
                open_positions=open_positions,
            )
        except Exception as e:
            self.logger.debug(f"State update error: {e}")

    def _execute_reversal_trade(self, key_level, direction: str, confluence):
        """Execute reversal trade at key level"""
        from .config import DEFAULT_RR_RATIO

        df = self.data_manager.get_h4_data()
        if df.empty:
            return

        entry_price = df.iloc[-1].close

        # Calculate SL - place below/above the key level
        sl_buffer = 2.0  # $2 buffer beyond the level

        if direction == 'bullish':
            sl_price = key_level.price - sl_buffer
            # Ensure minimum SL distance
            sl_price = self.risk_manager.validate_stop_loss(entry_price, sl_price, 'BUY')
            tp_price = self.risk_manager.calculate_take_profit(entry_price, sl_price, 'BUY')
            trade_direction = 'BUY'
        else:
            sl_price = key_level.price + sl_buffer
            sl_price = self.risk_manager.validate_stop_loss(entry_price, sl_price, 'SELL')
            tp_price = self.risk_manager.calculate_take_profit(entry_price, sl_price, 'SELL')
            trade_direction = 'SELL'

        # Validate spread
        if not self.risk_manager.validate_spread():
            self.logger.warning("Spread too wide - skipping trade")
            return

        # Calculate position size
        sl_distance = abs(entry_price - sl_price)
        lot_size = self.risk_manager.calculate_position_size(sl_distance)

        # Build comment
        comment = f"HTF {key_level.timeframe} {direction[:4]}"

        # Execute
        success = self.trade_executor.execute_trade(
            direction=trade_direction,
            entry_price=entry_price,
            sl_price=sl_price,
            tp_price=tp_price,
            lot_size=lot_size,
            comment=comment
        )

        if success:
            self.logger.info(
                f"REVERSAL TRADE OPENED: {trade_direction} @ ${entry_price:.2f} | "
                f"Key Level: {key_level.timeframe} {key_level.level_type} @ ${key_level.price:.2f} | "
                f"Confluence: {confluence.total_score:.1f}"
            )
