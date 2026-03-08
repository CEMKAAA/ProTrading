"""
ORB Strategy Class - Registered with StrategyRegistry
"""

import sys
import os

# Add parent paths to allow imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any, Tuple
from datetime import datetime, timezone
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class GoldORBStrategy(BaseStrategy):
    """
    Gold ORB Trading Strategy with ICT Concepts

    Features:
    - Opening Range Breakout (ORB) detection
    - Fair Value Gaps (FVG)
    - Order Blocks (OB)
    - Liquidity detection
    - Multi-session analysis (Asian, London, NY)
    - Dynamic risk management
    - ATR-based trailing stops
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="orb_strategy",
            name="Gold ORB + ICT Strategy",
            description="Opening Range Breakout strategy for XAUUSD with ICT concepts including FVG, Order Blocks, and multi-session analysis.",
            version="2.0.0",
            author="ProTrading",
            timeframes=["M1"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.40,
                "max_daily_loss_usd": -150.0,
                "orb_start_time": "09:30",
                "orb_end_time": "09:45",
                "trade_start_time": "09:45",
                "trade_end_time": "16:00",
            }
        )

    def __init__(self):
        super().__init__()
        self.bot = None
        self._last_idle_reason = None
        self._last_idle_reason_ts = 0.0
        self._idle_reason_heartbeat_seconds = 120.0

    def initialize(self) -> bool:
        """Initialize strategy components"""
        try:
            # Import here to avoid circular imports
            import MetaTrader5 as mt5
            from .config import TARGET_SYMBOL, MAGIC_NUMBER, get_runtime_symbol
            from .logger import logger
            from .data_manager import DataManager
            from .session_analyzer import SessionAnalyzer
            from .ict_analyzer import ICTAnalyzer
            from .risk_manager import RiskManager
            from .trade_executor import TradeExecutor
            from .bot_state import BotStateManager
            from Strategies.shared.cross_asset_filter_live import LiveCrossAssetRegimeFilter
            from Strategies.shared.databento_orderflow_filter_live import LiveDatabentoOrderflowFilter
            from Strategies.shared.circuit_breaker import StrategyCircuitBreaker, CircuitBreakerConfig
            from Strategies.shared.mt5_health import MT5HealthMonitor
            from Strategies.shared.structured_logging import attach_structured_logging
            from .config import (
                ENABLE_CROSS_ASSET_FILTER, REGIME_TIMEFRAME, REGIME_LOOKBACK_BARS,
                REGIME_RETURN_BARS, REGIME_SIGNAL_THRESHOLD, REGIME_BLOCK_COUNTERTREND,
                REGIME_TAILWIND_RISK_MULTIPLIER, REGIME_HEADWIND_RISK_MULTIPLIER,
                REGIME_NEUTRAL_RISK_MULTIPLIER, REGIME_SYMBOL_DXY, REGIME_SYMBOL_YIELD,
                REGIME_SYMBOL_RISKOFF, REGIME_SYMBOL_RISKON, REGIME_WEIGHT_DXY,
                REGIME_WEIGHT_YIELD, REGIME_WEIGHT_RISKOFF, REGIME_WEIGHT_RISKON,
                REGIME_EVAL_INTERVAL_SECONDS,
                ENABLE_ORDERFLOW_FILTER, ORDERFLOW_EVAL_INTERVAL_SECONDS,
                ORDERFLOW_LOOKBACK_MINUTES, ORDERFLOW_MIN_TRADES,
                ORDERFLOW_SIGNAL_THRESHOLD, ORDERFLOW_BLOCK_COUNTERTREND,
                ORDERFLOW_REDUCE_SIZE_IN_HEADWIND, ORDERFLOW_TAILWIND_RISK_MULTIPLIER,
                ORDERFLOW_HEADWIND_RISK_MULTIPLIER, ORDERFLOW_NEUTRAL_RISK_MULTIPLIER,
                ORDERFLOW_DATASET, ORDERFLOW_SCHEMA, ORDERFLOW_STYPE_IN, ORDERFLOW_SYMBOL,
                CB_MAX_CONSECUTIVE_LOSSES, CB_MAX_CONSECUTIVE_ERRORS,
                CB_ERROR_WINDOW_SECONDS, CB_MAX_ERRORS_IN_WINDOW,
                CB_COOLDOWN_SECONDS, CB_MAX_AVG_SLIPPAGE_USD,
                CLOSE_AT_SESSION_END, SESSION_END_MINUTES_BEFORE,
            )
            import pytz

            # Initialize MT5
            if not mt5.initialize():
                self.error_message = f"MT5 Init Failed: {mt5.last_error()}"
                return False

            # Verify symbol
            if not mt5.symbol_select(TARGET_SYMBOL, True):
                self.error_message = f"Symbol {TARGET_SYMBOL} not available"
                return False

            import time
            time.sleep(1)

            # Verify connection
            if mt5.symbol_info_tick(TARGET_SYMBOL) is None:
                self.error_message = "No price data available"
                return False

            # Store references
            self.mt5 = mt5
            self.logger = logger
            self.symbol = get_runtime_symbol()
            self.magic = MAGIC_NUMBER

            # Detect timezone
            self.broker_tz = self._detect_broker_timezone()
            self.ny_tz = pytz.timezone('America/New_York')

            # Initialize components
            self.data_manager = DataManager(TARGET_SYMBOL, self.broker_tz, self.ny_tz)
            self.session_analyzer = SessionAnalyzer(self.data_manager)
            self.ict_analyzer = ICTAnalyzer()
            self.risk_manager = RiskManager(TARGET_SYMBOL)
            self.trade_executor = TradeExecutor(TARGET_SYMBOL)
            self.state_manager = BotStateManager()
            self.cross_asset_filter = LiveCrossAssetRegimeFilter(
                self.mt5,
                self.logger,
                self._map_tf_to_mt5(REGIME_TIMEFRAME),
                {
                    "enable_cross_asset_filter": ENABLE_CROSS_ASSET_FILTER,
                    "regime_lookback_bars": REGIME_LOOKBACK_BARS,
                    "regime_return_bars": REGIME_RETURN_BARS,
                    "regime_signal_threshold": REGIME_SIGNAL_THRESHOLD,
                    "regime_block_countertrend": REGIME_BLOCK_COUNTERTREND,
                    "regime_tailwind_risk_multiplier": REGIME_TAILWIND_RISK_MULTIPLIER,
                    "regime_headwind_risk_multiplier": REGIME_HEADWIND_RISK_MULTIPLIER,
                    "regime_neutral_risk_multiplier": REGIME_NEUTRAL_RISK_MULTIPLIER,
                    "regime_symbol_dxy": REGIME_SYMBOL_DXY,
                    "regime_symbol_yield": REGIME_SYMBOL_YIELD,
                    "regime_symbol_riskoff": REGIME_SYMBOL_RISKOFF,
                    "regime_symbol_riskon": REGIME_SYMBOL_RISKON,
                    "regime_weight_dxy": REGIME_WEIGHT_DXY,
                    "regime_weight_yield": REGIME_WEIGHT_YIELD,
                    "regime_weight_riskoff": REGIME_WEIGHT_RISKOFF,
                    "regime_weight_riskon": REGIME_WEIGHT_RISKON,
                    "regime_eval_interval_seconds": REGIME_EVAL_INTERVAL_SECONDS,
                },
            )
            self.orderflow_filter = LiveDatabentoOrderflowFilter(
                self.logger,
                {
                    "enable_orderflow_filter": ENABLE_ORDERFLOW_FILTER,
                    "orderflow_eval_interval_seconds": ORDERFLOW_EVAL_INTERVAL_SECONDS,
                    "orderflow_lookback_minutes": ORDERFLOW_LOOKBACK_MINUTES,
                    "orderflow_min_trades": ORDERFLOW_MIN_TRADES,
                    "orderflow_signal_threshold": ORDERFLOW_SIGNAL_THRESHOLD,
                    "orderflow_block_countertrend": ORDERFLOW_BLOCK_COUNTERTREND,
                    "orderflow_reduce_size_in_headwind": ORDERFLOW_REDUCE_SIZE_IN_HEADWIND,
                    "orderflow_tailwind_risk_multiplier": ORDERFLOW_TAILWIND_RISK_MULTIPLIER,
                    "orderflow_headwind_risk_multiplier": ORDERFLOW_HEADWIND_RISK_MULTIPLIER,
                    "orderflow_neutral_risk_multiplier": ORDERFLOW_NEUTRAL_RISK_MULTIPLIER,
                    "orderflow_dataset": ORDERFLOW_DATASET,
                    "orderflow_schema": ORDERFLOW_SCHEMA,
                    "orderflow_stype_in": ORDERFLOW_STYPE_IN,
                    "orderflow_symbol": ORDERFLOW_SYMBOL,
                },
            )

            # Circuit breaker - strategy-level safety
            self.circuit_breaker = StrategyCircuitBreaker(
                logger=logger,
                config=CircuitBreakerConfig(
                    max_consecutive_losses=CB_MAX_CONSECUTIVE_LOSSES,
                    max_consecutive_errors=CB_MAX_CONSECUTIVE_ERRORS,
                    error_window_seconds=CB_ERROR_WINDOW_SECONDS,
                    max_errors_in_window=CB_MAX_ERRORS_IN_WINDOW,
                    cooldown_seconds=CB_COOLDOWN_SECONDS,
                    max_avg_slippage_usd=CB_MAX_AVG_SLIPPAGE_USD,
                ),
                strategy_id="orb_strategy",
            )
            self.trade_executor.set_circuit_breaker(self.circuit_breaker)
            self.risk_manager.set_circuit_breaker(self.circuit_breaker)

            # MT5 connection health monitor
            self.mt5_health = MT5HealthMonitor(
                logger=logger,
                symbol=TARGET_SYMBOL,
                magic_number=MAGIC_NUMBER,
                max_reconnect_attempts=5,
                base_backoff_seconds=2.0,
                max_backoff_seconds=60.0,
                heartbeat_timeout_seconds=120.0,
            )

            # State
            self.current_date = None
            self.orb_ready = False
            self.last_signal_time = None
            self._last_reconcile_ts = 0.0
            self._reconcile_interval = 60.0  # seconds between reconciliation checks

            # Attach structured logging (JSON file + critical alerts)
            attach_structured_logging(logger, strategy_id="orb_strategy")

            logger.info("=" * 60)
            logger.info("GOLD ORB BOT INITIALIZED")
            logger.info(f"Symbol: {TARGET_SYMBOL}")
            logger.info(f"Magic: {MAGIC_NUMBER}")
            logger.info(f"Broker TZ: {self.broker_tz}")
            logger.info("=" * 60)

            return True

        except Exception as e:
            self.error_message = str(e)
            return False

    def _map_tf_to_mt5(self, tf: str):
        tfu = str(tf).upper()
        return {
            "M1": self.mt5.TIMEFRAME_M1,
            "M5": self.mt5.TIMEFRAME_M5,
            "M15": self.mt5.TIMEFRAME_M15,
            "M30": self.mt5.TIMEFRAME_M30,
            "H1": self.mt5.TIMEFRAME_H1,
            "H4": self.mt5.TIMEFRAME_H4,
            "D1": self.mt5.TIMEFRAME_D1,
        }.get(tfu, self.mt5.TIMEFRAME_M15)

    def _detect_broker_timezone(self):
        """Use UTC as source timezone for MT5 timestamps."""
        import pytz

        self.logger.info("[BROKER TZ] Using UTC source timestamps from MT5")
        return pytz.UTC

    def run(self):
        """Main strategy loop"""
        from datetime import time
        import time as time_module
        from .config import (
            ORB_END_TIME, TRADE_START_TIME, TRADE_END_TIME,
            NO_TRADE_WINDOWS, MIN_BARS_FOR_ANALYSIS
        )

        self.logger.info("BOT STARTED - Entering main loop")

        while self._running:
            try:
                # MT5 connection health check with auto-reconnect
                if not self.mt5_health.ensure_connected():
                    delay = self.mt5_health.get_backoff_delay()
                    self.logger.warning(f"MT5 connection unhealthy — backing off {delay:.0f}s")
                    if self.circuit_breaker:
                        self.circuit_breaker.record_error("mt5_connection_lost")
                    time_module.sleep(delay)
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
                    self.logger.info("Friday close - sleeping until Monday")
                    time_module.sleep(300)
                    continue

                # Trading hours check
                if not (TRADE_START_TIME <= now.time() <= TRADE_END_TIME):
                    self._log_idle_reason_if_needed("Outside trading hours")
                    time_module.sleep(30)
                    continue

                # News filter
                if self._is_in_news_window(now):
                    self._log_idle_reason_if_needed("News blackout window")
                    time_module.sleep(60)
                    continue

                # End-of-session close (close positions N minutes before trade end)
                if CLOSE_AT_SESSION_END:
                    from datetime import timedelta
                    trade_end_dt = now.replace(
                        hour=TRADE_END_TIME.hour, minute=TRADE_END_TIME.minute,
                        second=0, microsecond=0,
                    )
                    close_dt = trade_end_dt - timedelta(minutes=SESSION_END_MINUTES_BEFORE)
                    if now.time() >= close_dt.time() and now.time() <= TRADE_END_TIME:
                        positions = self.mt5.positions_get(symbol=self.symbol)
                        our_positions = [p for p in (positions or []) if p.magic == MAGIC_NUMBER]
                        if our_positions:
                            self.logger.info(
                                f"End-of-session close: {len(our_positions)} position(s) "
                                f"({SESSION_END_MINUTES_BEFORE}min before session end)"
                            )
                            self.trade_executor.close_all_positions("Session End")

                # Periodic position reconciliation
                now_ts = time_module.time()
                if now_ts - self._last_reconcile_ts >= self._reconcile_interval:
                    self._last_reconcile_ts = now_ts
                    recon = self.mt5_health.reconcile_positions()
                    if recon["actual"]:
                        self.logger.debug(
                            f"Position reconciliation: {len(recon['actual'])} open position(s)"
                        )

                # Circuit breaker check
                cb_tripped, cb_reason = self.circuit_breaker.check()
                if cb_tripped:
                    self._log_idle_reason_if_needed(f"Circuit breaker: {cb_reason}")
                    time_module.sleep(30)
                    continue

                # Manage trailing stops (priority)
                if self.trade_executor.manage_trailing_stops(self.data_manager):
                    time_module.sleep(1)
                    continue

                # Check if we can trade
                can_trade, risk_reason = self.risk_manager.check_daily_status(
                    self.session_analyzer.is_trending
                )

                if not can_trade:
                    self._log_idle_reason_if_needed(f"Risk gate: {risk_reason}")
                    time_module.sleep(60)
                    continue

                # Check max risk
                if not self.risk_manager.can_open_new_position():
                    self._log_idle_reason_if_needed("Risk gate: max portfolio exposure reached")
                    time_module.sleep(30)
                    continue

                # Get data
                df = self.data_manager.get_data()

                if df.empty or len(df) < MIN_BARS_FOR_ANALYSIS:
                    self._log_idle_reason_if_needed("Insufficient market data")
                    time_module.sleep(5)
                    continue

                # Wait for ORB
                if not self._check_orb_ready(now):
                    self._log_idle_reason_if_needed("Waiting for ORB lock/validation")
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
                    self.logger.info(f"SETUP FOUND: {setup['reason']}")
                    self._execute_setup(setup)
                else:
                    self._log_idle_reason_if_needed("No valid setup on latest signal bar")

                # Sleep between iterations
                time_module.sleep(2)

            except KeyboardInterrupt:
                self.logger.info("Bot stopped by user")
                break

            except Exception as e:
                self.logger.error(f"Loop error: {e}", exc_info=True)
                time_module.sleep(5)

    def shutdown(self):
        """Cleanup and shutdown"""
        if hasattr(self, 'state_manager'):
            self.state_manager.set_stopped()
        if hasattr(self, 'mt5'):
            self.mt5.shutdown()
        if hasattr(self, 'logger'):
            self.logger.info("Bot shutdown complete")

    def get_state(self) -> Dict[str, Any]:
        """Return current state for dashboard"""
        if hasattr(self, 'state_manager'):
            return self.state_manager.read_state()
        return {
            "strategy_id": "orb_strategy",
            "is_connected": False,
            "is_running": self._running,
            "status": self.status.value,
        }

    def _get_current_time_ny(self):
        """Get current time in NY timezone"""
        from datetime import datetime
        tick = self.mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return None

        broker_now = datetime.fromtimestamp(tick.time, tz=self.broker_tz)
        return broker_now.astimezone(self.ny_tz)

    def _is_in_news_window(self, now):
        """Check if current time is in a news blackout window"""
        from .config import NO_TRADE_WINDOWS
        for start, end in NO_TRADE_WINDOWS:
            if start <= now <= end:
                self.logger.info(f"In news blackout: {start} - {end}")
                return True
        return False

    def _log_idle_reason_if_needed(self, reason: str):
        now_ts = datetime.now(tz=timezone.utc).timestamp()
        if (
            reason == self._last_idle_reason
            and (now_ts - self._last_idle_reason_ts) < self._idle_reason_heartbeat_seconds
        ):
            return
        self.logger.info(f"No trade: {reason}")
        self._last_idle_reason = reason
        self._last_idle_reason_ts = now_ts

    def _update_dashboard_state(self, now):
        """Update state for dashboard"""
        try:
            tick = self.mt5.symbol_info_tick(self.symbol)
            current_price = tick.bid if tick else None
            spread = round(tick.ask - tick.bid, 3) if tick else None

            account = self.mt5.account_info()
            balance = account.balance if account else 0.0
            equity = account.equity if account else 0.0
            margin_level = (account.equity / account.margin * 100) if account and account.margin > 0 else None

            positions = self.mt5.positions_get(symbol=self.symbol)
            open_positions = len(positions) if positions else 0
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
                daily_trades=self.risk_manager.daily_trades_count if hasattr(self.risk_manager, 'daily_trades_count') else 0,
                daily_pnl=daily_pnl,
                can_trade=self.risk_manager.can_trade if hasattr(self.risk_manager, 'can_trade') else False,
                balance=balance,
                equity=equity,
                margin_level=margin_level,
                open_positions=open_positions,
            )
        except Exception as e:
            self.logger.debug(f"State update error: {e}")

    def _handle_new_day(self, today):
        """Reset and prepare for new trading day"""
        from .config import ORB_END_TIME

        self.current_date = today
        self.orb_ready = False
        self.last_signal_time = None

        self.session_analyzer.reset()
        self.data_manager.clear_cache()
        self.trade_executor.last_atr_time = None
        self.trade_executor.cached_atr = None
        self.circuit_breaker.reset()

        self.session_analyzer.analyze_premarket(today)

        self.logger.info("=" * 60)
        self.logger.info(f"NEW TRADING DAY: {today}")
        self.logger.info("=" * 60)

    def _check_orb_ready(self, now):
        """Calculate ORB if time is right"""
        from .config import ORB_END_TIME

        if self.orb_ready:
            return True

        if now.time() < ORB_END_TIME:
            return False

        # Recompute premarket context at ORB lock time so bias/levels are based
        # on the latest available NY-session data, not midnight state.
        self.session_analyzer.analyze_premarket(self.current_date)
        orb_calculated = self.session_analyzer.calculate_orb(self.current_date)

        if orb_calculated and self.session_analyzer.is_orb_valid():
            self.orb_ready = True
            return True

        return False

    def _find_trade_setup(self, df):
        """Scan for trade setups based on ICT concepts"""
        from .config import MIN_ORB_RANGE_ATR, MAX_ORB_RANGE_ATR, BIAS_MIN_STRENGTH

        # ATR-normalized ORB quality filter.
        try:
            atr_series = self.trade_executor._get_atr(self.data_manager)
            atr = atr_series if atr_series and atr_series > 0 else 0.0
        except Exception:
            atr = 0.0

        current_close = df.iloc[-2].close
        bias, bias_strength = self._calculate_bias_strength(current_close, atr if atr > 0 else 1.0)
        self.session_analyzer.bias = bias
        self.session_analyzer.bias_strength = bias_strength

        if bias == 'neutral' or bias_strength < BIAS_MIN_STRENGTH:
            return None

        if atr > 0:
            orb_range = abs(self.session_analyzer.orb_high - self.session_analyzer.orb_low)
            orb_range_atr = orb_range / atr
            if orb_range_atr < MIN_ORB_RANGE_ATR or orb_range_atr > MAX_ORB_RANGE_ATR:
                return None

        # Bullish setup
        if bias == 'bullish' and current_close > self.session_analyzer.orb_high:
            fvg = self.ict_analyzer.find_fvg(df, 'bullish')

            if fvg:
                self.logger.info(f"Bullish FVG found | Gap: ${fvg['size']:.2f}")
                # ORB+imbalance model: SL anchored to imbalance boundary.
                sl = fvg['bottom']

                return {
                    'direction': 'BUY',
                    'entry': current_close,
                    'sl': sl,
                    'reason': 'Bullish ORB Breakout + 3-Candle Imbalance'
                }

        # Bearish setup
        elif bias == 'bearish' and current_close < self.session_analyzer.orb_low:
            fvg = self.ict_analyzer.find_fvg(df, 'bearish')

            if fvg:
                self.logger.info(f"Bearish FVG found | Gap: ${fvg['size']:.2f}")
                # ORB+imbalance model: SL anchored to imbalance boundary.
                sl = fvg['top']

                return {
                    'direction': 'SELL',
                    'entry': current_close,
                    'sl': sl,
                    'reason': 'Bearish ORB Breakout + 3-Candle Imbalance'
                }

        return None

    def _execute_setup(self, setup):
        """Execute trade from setup"""
        from .config import MAX_SPREAD_TO_SL_RATIO

        direction = setup['direction']
        sl = setup['sl']

        if not self.risk_manager.validate_spread():
            self.logger.warning("Spread too wide - skipping trade")
            return

        tick = self.mt5.symbol_info_tick(self.symbol)
        if tick is None:
            self.logger.warning("No tick data - skipping trade")
            return

        entry = tick.ask if direction == 'BUY' else tick.bid
        if direction == 'BUY' and sl >= entry:
            self.logger.info(f"Skipping BUY setup: structural SL {sl:.2f} not below entry {entry:.2f}")
            return
        if direction == 'SELL' and sl <= entry:
            self.logger.info(f"Skipping SELL setup: structural SL {sl:.2f} not above entry {entry:.2f}")
            return

        sl = self.risk_manager.validate_stop_loss(entry, sl, direction)
        if sl is None:
            return

        sl_distance = abs(entry - sl)
        spread_now = tick.ask - tick.bid
        if MAX_SPREAD_TO_SL_RATIO > 0 and sl_distance > 0:
            spread_to_sl = spread_now / sl_distance
            if spread_to_sl > MAX_SPREAD_TO_SL_RATIO:
                self.logger.info(
                    f"Skipping setup: spread/SL ratio {spread_to_sl:.2f} > {MAX_SPREAD_TO_SL_RATIO:.2f} "
                    f"(spread={spread_now:.3f}, SL={sl_distance:.3f})"
                )
                return

        lot_size = self.risk_manager.calculate_position_size(sl_distance)

        if lot_size <= 0:
            self.logger.warning("Position sizing returned 0 — cannot trade (MT5 data unavailable?)")
            return

        # Cross-asset regime gate (fail-open if drivers are unavailable).
        try:
            allowed, risk_multiplier, decision, reason = self.cross_asset_filter.allow_trade(direction)
        except Exception:
            allowed, risk_multiplier, decision, reason = True, 1.0, None, "cross_asset_fail_open_exception"
        if not allowed:
            self.logger.info(f"Trade blocked by cross-asset regime: {reason}")
            return
        lot_size = round(max(0.01, lot_size * risk_multiplier), 2)
        if risk_multiplier != 1.0:
            self.logger.info(
                f"Cross-asset risk multiplier applied: {risk_multiplier:.2f} | "
                f"bias={decision.bias if decision else 'neutral'} score={decision.score if decision else 0.0:.3f}"
            )

        # Databento orderflow gate (fail-open on missing key/data/network).
        try:
            of_allowed, of_mul, of_decision, of_reason = self.orderflow_filter.allow_trade(direction)
        except Exception:
            of_allowed, of_mul, of_decision, of_reason = True, 1.0, None, "orderflow_fail_open_exception"
        if not of_allowed:
            self.logger.info(f"Trade blocked by Databento orderflow filter: {of_reason}")
            return
        lot_size = round(max(0.01, lot_size * of_mul), 2)
        if of_mul != 1.0:
            self.logger.info(
                f"Orderflow risk multiplier applied: {of_mul:.2f} | "
                f"bias={of_decision.bias if of_decision else 'neutral'} "
                f"score={of_decision.score if of_decision else 0.0:.3f} "
                f"n={of_decision.sample_count if of_decision else 0}"
            )

        success = self.trade_executor.execute_trade(
            direction=direction,
            sl_price=sl,
            lot_size=lot_size,
            comment=setup['reason'][:31],
            entry_price=entry,
        )

        if success:
            self.logger.info(f"TRADE OPENED: {setup['reason']}")
        else:
            self.logger.error("Trade execution failed")

    def _calculate_bias_strength(self, current_price: float, atr: float) -> Tuple[str, int]:
        """Bias scoring aligned with backtest ORB strategy."""
        if atr <= 0:
            atr = 1.0

        orb_high = self.session_analyzer.orb_high
        orb_low = self.session_analyzer.orb_low
        asian_high = self.session_analyzer.asian_high
        asian_low = self.session_analyzer.asian_low
        pd_high = self.session_analyzer.pd_high
        pd_low = self.session_analyzer.pd_low
        london_high = self.session_analyzer.london_high
        london_low = self.session_analyzer.london_low

        bullish_score = 0
        bearish_score = 0

        if orb_high is not None and orb_low is not None:
            if current_price > orb_high:
                extension = (current_price - orb_high) / atr
                bullish_score += min(30, int(15 + extension * 15))
            elif current_price < orb_low:
                extension = (orb_low - current_price) / atr
                bearish_score += min(30, int(15 + extension * 15))

        if asian_high is not None and asian_low is not None:
            if current_price > asian_high:
                extension = (current_price - asian_high) / atr
                bullish_score += min(25, int(12 + extension * 13))
            elif current_price < asian_low:
                extension = (asian_low - current_price) / atr
                bearish_score += min(25, int(12 + extension * 13))

        if pd_high is not None and pd_low is not None:
            if current_price > pd_high:
                extension = (current_price - pd_high) / atr
                bullish_score += min(25, int(12 + extension * 13))
            elif current_price < pd_low:
                extension = (pd_low - current_price) / atr
                bearish_score += min(25, int(12 + extension * 13))

        if london_high is not None and london_low is not None:
            london_mid = (london_high + london_low) / 2
            if current_price > london_high:
                bullish_score += 15
            elif current_price > london_mid:
                bullish_score += 8
            elif current_price < london_low:
                bearish_score += 15
            elif current_price < london_mid:
                bearish_score += 8

        if bullish_score > bearish_score:
            return "bullish", min(100, bullish_score)
        if bearish_score > bullish_score:
            return "bearish", min(100, bearish_score)
        return "neutral", 0
