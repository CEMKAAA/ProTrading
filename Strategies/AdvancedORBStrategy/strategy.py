"""
Advanced Gold ORB Strategy - Main Strategy Class
Production-level implementation with all fixes and improvements
"""

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, Tuple, List
import time as time_module

from Strategies.base import BaseStrategy, StrategyInfo

from .config import (
    get_config, get_runtime_symbol, STRATEGY_ID, STRATEGY_NAME, STRATEGY_VERSION,
    TARGET_SYMBOL, TIMEFRAME, MAGIC_NUMBER
)
from .logger import logger
from .bot_state import get_state_manager
from .risk_manager import AdvancedRiskManager
from .ict_analyzer import AdvancedICTAnalyzer
from .session_analyzer import AdvancedSessionAnalyzer
from .trade_executor import AdvancedTradeExecutor
from Strategies.shared.cross_asset_filter_live import LiveCrossAssetRegimeFilter
from Strategies.shared.databento_orderflow_filter_live import LiveDatabentoOrderflowFilter
from Strategies.shared.circuit_breaker import StrategyCircuitBreaker, CircuitBreakerConfig
from Strategies.shared.mt5_health import MT5HealthMonitor
from Strategies.shared.structured_logging import attach_structured_logging


# Strategy metadata - used for registration
_STRATEGY_INFO = StrategyInfo(
    id=STRATEGY_ID,
    name=STRATEGY_NAME,
    description=(
        "Production-level Opening Range Breakout strategy with advanced ICT concepts. "
        "Features: Dynamic thresholds, slippage protection, partial profits, "
        "liquidity sweep detection, proper timezone handling, and atomic state management."
    ),
    version=STRATEGY_VERSION,
    author="ProTrading",
    timeframes=["M1"],
    symbols=["XAUUSD"],
    parameters={
        "risk_percent": {"type": "float", "default": 1.0, "min": 0.1, "max": 5.0},
        "max_spread": {"type": "float", "default": 0.40, "min": 0.1, "max": 1.0},
        "max_daily_loss": {"type": "float", "default": 150.0, "min": 50, "max": 500},
        "max_slippage_points": {"type": "int", "default": 10, "min": 1, "max": 50},
        "partial_tp_percent": {"type": "int", "default": 50, "min": 25, "max": 75},
        "use_adaptive_orb": {"type": "bool", "default": True},
        "use_liquidity_sweeps": {"type": "bool", "default": True},
    }
)


class AdvancedGoldORBStrategy(BaseStrategy):
    """
    Production-level Gold ORB + ICT Strategy

    Key improvements over basic version:
    - Real-time entry prices (not stale bar close)
    - Slippage protection with deviation parameter
    - Accurate P&L (closed + floating)
    - Proper timezone detection
    - Position verification after execution
    - Dynamic FVG thresholds (ATR-based)
    - Adaptive ORB window
    - Bias strength scoring (0-100)
    - Cached Order Block calculations
    - Partial profit taking
    - Liquidity sweep detection
    - End-of-session position management
    - Atomic state file writes
    """

    def __init__(self):
        super().__init__()
        self.symbol = get_runtime_symbol()
        self.timeframe = TIMEFRAME

        # Core components
        self.risk_manager: Optional[AdvancedRiskManager] = None
        self.ict_analyzer: Optional[AdvancedICTAnalyzer] = None
        self.session_analyzer: Optional[AdvancedSessionAnalyzer] = None
        self.executor: Optional[AdvancedTradeExecutor] = None
        self.state_manager = get_state_manager()

        # Data cache
        self._data_cache: Optional[pd.DataFrame] = None
        self._last_cache_time: Optional[datetime] = None
        self._cache_bar_count: int = 0

        # State tracking
        self._initialized = False
        self._last_bar_time: Optional[datetime] = None
        self._current_day: Optional[int] = None
        self._last_no_trade_reason: Optional[str] = None
        self._last_no_trade_reason_ts: float = 0.0
        self._no_trade_reason_heartbeat_seconds: float = 120.0
        self._last_reconcile_ts: float = 0.0
        self._reconcile_interval: float = 60.0  # seconds between reconciliation checks

    def _map_tf_to_mt5(self, tf: str):
        tfu = str(tf).upper()
        return {
            "M1": mt5.TIMEFRAME_M1,
            "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15,
            "M30": mt5.TIMEFRAME_M30,
            "H1": mt5.TIMEFRAME_H1,
            "H4": mt5.TIMEFRAME_H4,
            "D1": mt5.TIMEFRAME_D1,
        }.get(tfu, mt5.TIMEFRAME_M15)

    def initialize(self) -> bool:
        """Initialize strategy and connect to MT5"""
        logger.info(f"Initializing {STRATEGY_NAME} v{STRATEGY_VERSION}")

        # Initialize MT5
        if not mt5.initialize():
            error = mt5.last_error()
            logger.error(f"MT5 initialization failed: {error}")
            self.state_manager.record_error(f"MT5 init failed: {error}")
            return False

        # Verify symbol
        symbol_info = mt5.symbol_info(self.symbol)
        if symbol_info is None:
            logger.error(f"Symbol {self.symbol} not found")
            return False

        if not symbol_info.visible:
            if not mt5.symbol_select(self.symbol, True):
                logger.error(f"Failed to select {self.symbol}")
                return False

        # Initialize components
        self.risk_manager = AdvancedRiskManager(self.symbol)
        self.ict_analyzer = AdvancedICTAnalyzer(self.symbol)
        self.session_analyzer = AdvancedSessionAnalyzer(self.symbol)
        self.executor = AdvancedTradeExecutor(self.symbol)
        cfg = get_config()
        self.cross_asset_filter = LiveCrossAssetRegimeFilter(
            mt5,
            logger,
            self._map_tf_to_mt5(cfg.regime_timeframe),
            {
                "enable_cross_asset_filter": cfg.enable_cross_asset_filter,
                "regime_lookback_bars": cfg.regime_lookback_bars,
                "regime_return_bars": cfg.regime_return_bars,
                "regime_signal_threshold": cfg.regime_signal_threshold,
                "regime_block_countertrend": cfg.regime_block_countertrend,
                "regime_tailwind_risk_multiplier": cfg.regime_tailwind_risk_multiplier,
                "regime_headwind_risk_multiplier": cfg.regime_headwind_risk_multiplier,
                "regime_neutral_risk_multiplier": cfg.regime_neutral_risk_multiplier,
                "regime_symbol_dxy": cfg.regime_symbol_dxy,
                "regime_symbol_yield": cfg.regime_symbol_yield,
                "regime_symbol_riskoff": cfg.regime_symbol_riskoff,
                "regime_symbol_riskon": cfg.regime_symbol_riskon,
                "regime_weight_dxy": cfg.regime_weight_dxy,
                "regime_weight_yield": cfg.regime_weight_yield,
                "regime_weight_riskoff": cfg.regime_weight_riskoff,
                "regime_weight_riskon": cfg.regime_weight_riskon,
                "regime_eval_interval_seconds": cfg.regime_eval_interval_seconds,
            },
        )
        self.orderflow_filter = LiveDatabentoOrderflowFilter(
            logger,
            {
                "enable_orderflow_filter": cfg.enable_orderflow_filter,
                "orderflow_eval_interval_seconds": cfg.orderflow_eval_interval_seconds,
                "orderflow_lookback_minutes": cfg.orderflow_lookback_minutes,
                "orderflow_min_trades": cfg.orderflow_min_trades,
                "orderflow_signal_threshold": cfg.orderflow_signal_threshold,
                "orderflow_block_countertrend": cfg.orderflow_block_countertrend,
                "orderflow_reduce_size_in_headwind": cfg.orderflow_reduce_size_in_headwind,
                "orderflow_tailwind_risk_multiplier": cfg.orderflow_tailwind_risk_multiplier,
                "orderflow_headwind_risk_multiplier": cfg.orderflow_headwind_risk_multiplier,
                "orderflow_neutral_risk_multiplier": cfg.orderflow_neutral_risk_multiplier,
                "orderflow_dataset": cfg.orderflow_dataset,
                "orderflow_schema": cfg.orderflow_schema,
                "orderflow_stype_in": cfg.orderflow_stype_in,
                "orderflow_symbol": cfg.orderflow_symbol,
            },
        )

        # Circuit breaker - strategy-level safety
        self.circuit_breaker = StrategyCircuitBreaker(
            logger=logger,
            config=CircuitBreakerConfig(
                max_consecutive_losses=cfg.cb_max_consecutive_losses,
                max_consecutive_errors=cfg.cb_max_consecutive_errors,
                error_window_seconds=cfg.cb_error_window_seconds,
                max_errors_in_window=cfg.cb_max_errors_in_window,
                cooldown_seconds=cfg.cb_cooldown_seconds,
                max_avg_slippage_usd=cfg.cb_max_avg_slippage_usd,
            ),
            strategy_id=STRATEGY_ID,
        )
        self.executor.set_circuit_breaker(self.circuit_breaker)
        self.risk_manager.set_circuit_breaker(self.circuit_breaker)

        # MT5 connection health monitor
        self.mt5_health = MT5HealthMonitor(
            logger=logger,
            symbol=self.symbol,
            magic_number=MAGIC_NUMBER,
            max_reconnect_attempts=5,
            base_backoff_seconds=2.0,
            max_backoff_seconds=60.0,
            heartbeat_timeout_seconds=120.0,
        )

        # Detect broker timezone
        tick = mt5.symbol_info_tick(self.symbol)
        if tick:
            broker_time = datetime.utcfromtimestamp(tick.time)
            self.session_analyzer.detect_broker_timezone(broker_time)

        # Update state
        self.state_manager.set_connected(True)

        # Attach structured logging (JSON file + critical alerts)
        attach_structured_logging(logger, strategy_id=STRATEGY_ID)

        self._initialized = True
        logger.info("Strategy initialized successfully")
        return True

    def run(self):
        """Main strategy loop"""
        if not self._initialized:
            if not self.initialize():
                return

        logger.info("Starting main strategy loop")
        cfg = get_config()

        while self._running:
            try:
                # Refresh config periodically
                cfg = get_config()
                if hasattr(self, "cross_asset_filter") and self.cross_asset_filter:
                    self.cross_asset_filter.update_settings({
                        "enable_cross_asset_filter": cfg.enable_cross_asset_filter,
                        "regime_lookback_bars": cfg.regime_lookback_bars,
                        "regime_return_bars": cfg.regime_return_bars,
                        "regime_signal_threshold": cfg.regime_signal_threshold,
                        "regime_block_countertrend": cfg.regime_block_countertrend,
                        "regime_tailwind_risk_multiplier": cfg.regime_tailwind_risk_multiplier,
                        "regime_headwind_risk_multiplier": cfg.regime_headwind_risk_multiplier,
                        "regime_neutral_risk_multiplier": cfg.regime_neutral_risk_multiplier,
                        "regime_symbol_dxy": cfg.regime_symbol_dxy,
                        "regime_symbol_yield": cfg.regime_symbol_yield,
                        "regime_symbol_riskoff": cfg.regime_symbol_riskoff,
                        "regime_symbol_riskon": cfg.regime_symbol_riskon,
                        "regime_weight_dxy": cfg.regime_weight_dxy,
                        "regime_weight_yield": cfg.regime_weight_yield,
                        "regime_weight_riskoff": cfg.regime_weight_riskoff,
                        "regime_weight_riskon": cfg.regime_weight_riskon,
                        "regime_eval_interval_seconds": cfg.regime_eval_interval_seconds,
                    })
                if hasattr(self, "orderflow_filter") and self.orderflow_filter:
                    self.orderflow_filter.update_settings({
                        "enable_orderflow_filter": cfg.enable_orderflow_filter,
                        "orderflow_eval_interval_seconds": cfg.orderflow_eval_interval_seconds,
                        "orderflow_lookback_minutes": cfg.orderflow_lookback_minutes,
                        "orderflow_min_trades": cfg.orderflow_min_trades,
                        "orderflow_signal_threshold": cfg.orderflow_signal_threshold,
                        "orderflow_block_countertrend": cfg.orderflow_block_countertrend,
                        "orderflow_reduce_size_in_headwind": cfg.orderflow_reduce_size_in_headwind,
                        "orderflow_tailwind_risk_multiplier": cfg.orderflow_tailwind_risk_multiplier,
                        "orderflow_headwind_risk_multiplier": cfg.orderflow_headwind_risk_multiplier,
                        "orderflow_neutral_risk_multiplier": cfg.orderflow_neutral_risk_multiplier,
                        "orderflow_dataset": cfg.orderflow_dataset,
                        "orderflow_schema": cfg.orderflow_schema,
                        "orderflow_stype_in": cfg.orderflow_stype_in,
                        "orderflow_symbol": cfg.orderflow_symbol,
                    })

                # MT5 connection health check with auto-reconnect
                if not self.mt5_health.ensure_connected():
                    delay = self.mt5_health.get_backoff_delay()
                    logger.warning(f"MT5 connection unhealthy — backing off {delay:.0f}s")
                    if self.circuit_breaker:
                        self.circuit_breaker.record_error("mt5_connection_lost")
                    time_module.sleep(delay)
                    continue

                # Get current tick
                tick = mt5.symbol_info_tick(self.symbol)
                if tick is None:
                    logger.warning("Cannot get tick data after health check, retrying...")
                    time_module.sleep(1)
                    continue

                broker_time = datetime.utcfromtimestamp(tick.time)
                ny_time = self.session_analyzer.broker_to_ny_time(broker_time)

                # Handle new day
                if self._current_day != ny_time.day:
                    self._handle_new_day(ny_time)
                    self._current_day = ny_time.day

                # Get market data
                df = self._get_data(force_refresh=False)
                if df is None or len(df) < cfg.min_bars_for_analysis:
                    time_module.sleep(1)
                    continue

                # Run ICT analysis
                ict_analysis = self.ict_analyzer.analyze(df)
                atr = ict_analysis.get('atr', 1.0)

                # Run session analysis
                session_data = self.session_analyzer.analyze(df, broker_time, atr)

                # Check trading window
                in_window, window_reason = self.session_analyzer.is_in_trading_window(broker_time)

                # Check daily status
                can_trade, trade_reason = self.risk_manager.check_daily_status(session_data.is_trending)

                # Update dashboard state
                self._update_state(tick, ny_time, session_data, ict_analysis, can_trade, trade_reason)

                # Periodic position reconciliation
                now_ts = time_module.time()
                if now_ts - self._last_reconcile_ts >= self._reconcile_interval:
                    self._last_reconcile_ts = now_ts
                    recon = self.mt5_health.reconcile_positions()
                    if recon["actual"]:
                        logger.debug(
                            f"Position reconciliation: {len(recon['actual'])} open position(s)"
                        )

                # Circuit breaker check - hard safety gate
                cb_tripped, cb_reason = self.circuit_breaker.check()
                if cb_tripped:
                    self._log_no_trade_reason_if_needed(f"Circuit breaker: {cb_reason}")
                    time_module.sleep(30)
                    continue

                # Manage existing positions first
                positions = self.executor.get_our_positions()
                if positions:
                    self._manage_positions(positions, atr, ny_time, cfg)

                gate_reason = None
                if not in_window:
                    gate_reason = f"Window gate: {window_reason}"
                elif not can_trade:
                    gate_reason = f"Risk gate: {trade_reason}"
                elif positions:
                    gate_reason = f"Position gate: {len(positions)} open position(s)"

                # Check for new entry signals
                if gate_reason:
                    self._log_no_trade_reason_if_needed(gate_reason)
                else:
                    signal_skip_reason = self._check_for_signals(df, session_data, ict_analysis, tick)
                    if signal_skip_reason:
                        self._log_no_trade_reason_if_needed(signal_skip_reason)

                # Sleep until next check
                time_module.sleep(2)

            except KeyboardInterrupt:
                logger.info("Strategy stopped by user")
                break
            except Exception as e:
                logger.error(f"Error in main loop: {e}", exc_info=True)
                self.state_manager.record_error(str(e))
                time_module.sleep(5)

        self.shutdown()

    def _get_data(self, force_refresh: bool = False) -> Optional[pd.DataFrame]:
        """
        Get market data with intelligent caching.

        Args:
            force_refresh: Force cache refresh

        Returns:
            DataFrame with OHLCV data
        """
        cfg = get_config()

        # Check if cache is fresh
        if not force_refresh and self._data_cache is not None:
            tick = mt5.symbol_info_tick(self.symbol)
            if tick:
                current_bar_time = datetime.utcfromtimestamp(tick.time)

                # Only refresh if new bar formed or cache is old
                if (self._last_bar_time is not None and
                    current_bar_time.minute == self._last_bar_time.minute and
                    self._cache_bar_count < cfg.cache_refresh_interval_bars):
                    return self._data_cache

        # Fetch new data
        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, cfg.data_cache_bars)
        if rates is None or len(rates) == 0:
            return None

        df = pd.DataFrame(rates)
        # MT5 rates timestamps are in UTC (seconds since epoch)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df.set_index('time', inplace=True)

        # Convert index from UTC to NY time in one vectorized operation
        # This fixes the UTC vs broker time issue and enables faster session filtering
        if self.session_analyzer:
            df = self.session_analyzer.convert_df_index_to_ny(df)

        self._data_cache = df
        self._last_cache_time = datetime.now()
        self._cache_bar_count += 1

        # Track bar time for cache invalidation
        tick = mt5.symbol_info_tick(self.symbol)
        if tick:
            self._last_bar_time = datetime.utcfromtimestamp(tick.time)

        return df

    def _handle_new_day(self, ny_time: datetime):
        """Handle daily reset - clears all caches and resets state"""
        logger.info(f"New trading day: {ny_time.date()}")

        # Reset local caches
        self._cache_bar_count = 0
        self._data_cache = None
        self._last_bar_time = None

        # Reset session analyzer caches (ORB, Asian range, etc.)
        if self.session_analyzer:
            self.session_analyzer.clear_daily_cache()

        # Reset ICT analyzer caches (Order Blocks, FVGs)
        if self.ict_analyzer:
            self.ict_analyzer.reset_cache()

        # Reset risk manager daily performance
        if self.risk_manager:
            self.risk_manager.reset_daily_state()

        # Reset circuit breaker daily state
        if hasattr(self, 'circuit_breaker') and self.circuit_breaker:
            self.circuit_breaker.reset()

        # Force data refresh
        self._get_data(force_refresh=True)

    def _update_state(
        self,
        tick: Any,
        ny_time: datetime,
        session_data: Any,
        ict_analysis: Dict,
        can_trade: bool,
        trade_reason: str
    ):
        """Update dashboard state with current data"""
        account = mt5.account_info()
        positions = self.executor.get_our_positions()
        daily_perf = self.risk_manager.get_daily_performance()

        # Calculate floating P&L
        floating_pnl = sum(p.profit + p.swap for p in positions)

        # Update market data
        self.state_manager.update_market_data(
            price=tick.bid,
            spread=tick.ask - tick.bid,
            time_ny=ny_time,
            balance=account.balance if account else 0,
            equity=account.equity if account else 0,
            margin_level=account.margin_level if account and account.margin > 0 else None
        )

        # Update session data
        self.state_manager.update_session_data(
            orb_high=session_data.orb.high,
            orb_low=session_data.orb.low,
            asian_high=session_data.asian_high,
            asian_low=session_data.asian_low,
            bias=session_data.bias.direction,
            bias_strength=session_data.bias.strength,
            is_trending=session_data.is_trending,
            orb_extended=session_data.orb.is_extended
        )

        # Update performance
        self.state_manager.update_daily_performance(
            trades=daily_perf.trades_count,
            wins=daily_perf.wins,
            losses=daily_perf.losses,
            pnl_closed=daily_perf.closed_pnl,
            pnl_floating=floating_pnl
        )

        # Update trade status
        self.state_manager.update_trade_status(can_trade, trade_reason)

        # Update ICT patterns
        self.state_manager.update({
            "active_fvgs": len(ict_analysis.get('fvgs', [])),
            "active_obs": len(ict_analysis.get('order_blocks', [])),
            "recent_sweeps": len(ict_analysis.get('sweeps', [])),
        })

    def _check_for_signals(
        self,
        df: pd.DataFrame,
        session_data: Any,
        ict_analysis: Dict,
        tick: Any
    ) -> Optional[str]:
        """Check for and execute trade signals"""
        cfg = get_config()

        # Check bias strength requirement
        if session_data.bias.strength < cfg.bias_min_strength:
            return f"Signal gate: bias strength {session_data.bias.strength} < {cfg.bias_min_strength}"

        # Check ORB validity
        if not session_data.orb.is_valid:
            return "Signal gate: ORB invalid"

        # Confirm breakout with completed signal bar close (reduces fake intrabar breaks).
        if len(df) < 3:
            return "Signal gate: insufficient bars for breakout confirmation"
        signal_bar = df.iloc[-2]
        signal_close = signal_bar.close
        current_bid = tick.bid
        current_ask = tick.ask

        # Determine direction based on bias and ORB breakout
        direction = None

        if session_data.bias.direction == 'bullish' and session_data.orb.breakout_direction == 'bullish':
            if signal_close > session_data.orb.high and current_ask > session_data.orb.high:
                direction = 'BUY'
        elif session_data.bias.direction == 'bearish' and session_data.orb.breakout_direction == 'bearish':
            if signal_close < session_data.orb.low and current_bid < session_data.orb.low:
                direction = 'SELL'

        if direction is None:
            return "Signal gate: no confirmed ORB breakout"

        # Check ICT conditions - pass existing analysis to avoid double analyze()
        ict_valid, ict_details = self.ict_analyzer.check_entry_conditions(
            df, direction, current_bid, existing_analysis=ict_analysis
        )

        if not ict_valid:
            return "Signal gate: ICT entry conditions not met"

        # Check spread
        spread_ok, spread = self.risk_manager.validate_spread()
        if not spread_ok:
            return f"Risk gate: spread too high (${spread:.3f})"

        # Check risk capacity
        can_open, open_reason = self.risk_manager.can_open_new_position()
        if not can_open:
            logger.info(f"Cannot open: {open_reason}")
            return f"Risk gate: {open_reason}"

        # Calculate entry, SL, TP using CURRENT tick prices
        if direction == 'BUY':
            entry_price = tick.ask  # Buy at ask
            sl_price = self.ict_analyzer.get_optimal_sl('BUY', entry_price, df, existing_analysis=ict_analysis)
        else:
            entry_price = tick.bid  # Sell at bid
            sl_price = self.ict_analyzer.get_optimal_sl('SELL', entry_price, df, existing_analysis=ict_analysis)

        # Reject wrong-side structural SL before risk validation.
        if direction == 'BUY' and sl_price >= entry_price:
            logger.info(
                f"Skipping BUY setup: structural SL {sl_price:.2f} not below entry {entry_price:.2f}"
            )
            return "Signal gate: BUY structural SL invalid"
        if direction == 'SELL' and sl_price <= entry_price:
            logger.info(
                f"Skipping SELL setup: structural SL {sl_price:.2f} not above entry {entry_price:.2f}"
            )
            return "Signal gate: SELL structural SL invalid"

        # Validate SL
        sl_price, sl_distance = self.risk_manager.validate_stop_loss(entry_price, sl_price, direction)
        if sl_price is None:
            return "Risk gate: SL distance outside allowed bounds"

        # Cost-efficiency gate: avoid setups where spread dominates structural risk.
        if cfg.max_spread_to_sl_ratio > 0 and sl_distance > 0:
            spread_to_sl = spread / sl_distance
            if spread_to_sl > cfg.max_spread_to_sl_ratio:
                return (
                    f"Risk gate: spread/SL ratio {spread_to_sl:.2f} > "
                    f"{cfg.max_spread_to_sl_ratio:.2f}"
                )

        # Calculate position size
        lot_size, size_details = self.risk_manager.calculate_position_size(sl_distance)

        if lot_size <= 0:
            logger.warning(f"Position sizing returned 0 — cannot trade: {size_details}")
            return "Risk gate: position sizing failed"

        # Cross-asset regime gate (fail-open if macro data unavailable).
        try:
            allowed, risk_multiplier, decision, reason = self.cross_asset_filter.allow_trade(direction)
        except Exception:
            allowed, risk_multiplier, decision, reason = True, 1.0, None, "cross_asset_fail_open_exception"
        if not allowed:
            logger.info(f"Trade blocked by cross-asset regime: {reason}")
            return f"Regime gate: {reason}"
        risk_multiplier = max(0.05, min(float(risk_multiplier), 2.0))
        lot_size = round(max(0.01, lot_size * risk_multiplier), 2)
        if risk_multiplier != 1.0:
            logger.info(
                f"Cross-asset risk multiplier applied: {risk_multiplier:.2f} | "
                f"bias={decision.bias if decision else 'neutral'} score={decision.score if decision else 0.0:.3f}"
            )

        # Databento orderflow gate (fail-open on missing key/data/network).
        try:
            of_allowed, of_mul, of_decision, of_reason = self.orderflow_filter.allow_trade(direction)
        except Exception:
            of_allowed, of_mul, of_decision, of_reason = True, 1.0, None, "orderflow_fail_open_exception"
        if not of_allowed:
            logger.info(f"Trade blocked by Databento orderflow filter: {of_reason}")
            return f"Orderflow gate: {of_reason}"
        lot_size = round(max(0.01, lot_size * of_mul), 2)
        if of_mul != 1.0:
            logger.info(
                f"Orderflow risk multiplier applied: {of_mul:.2f} | "
                f"bias={of_decision.bias if of_decision else 'neutral'} "
                f"score={of_decision.score if of_decision else 0.0:.3f} "
                f"n={of_decision.sample_count if of_decision else 0}"
            )

        # Calculate TP
        tp_price = self.risk_manager.calculate_take_profit(entry_price, sl_price, direction)

        # Build trade comment
        comment = f"AdvORB_{session_data.bias.direction[:3]}_{session_data.bias.strength}"

        # Log signal
        logger.info(
            f"SIGNAL: {direction} | Entry: {entry_price:.2f} | SL: {sl_price:.2f} ({sl_distance:.2f}) | "
            f"TP: {tp_price:.2f} | Lot: {lot_size} | Bias: {session_data.bias.direction} "
            f"({session_data.bias.strength}) | ICT Score: {ict_details['total_score']}"
        )

        self.state_manager.record_signal(direction, {
            "entry": entry_price,
            "sl": sl_price,
            "tp": tp_price,
            "lot": lot_size,
            "bias_strength": session_data.bias.strength,
            "ict_score": ict_details['total_score']
        })

        # Execute trade
        result = self.executor.execute_trade(
            direction=direction,
            lot_size=lot_size,
            sl_price=sl_price,
            tp_price=tp_price,
            comment=comment
        )

        if result.success:
            self.state_manager.record_trade({
                "ticket": result.ticket,
                "direction": direction,
                "entry": result.actual_entry,
                "sl": result.actual_sl,
                "tp": result.actual_tp,
                "lot": lot_size,
                "slippage": result.slippage
            })
            return None
        else:
            logger.error(f"Trade execution failed: {result.error}")
            return f"Execution gate: {result.error}"

    def _log_no_trade_reason_if_needed(self, reason: str):
        now_ts = time_module.time()
        if (
            reason == self._last_no_trade_reason
            and (now_ts - self._last_no_trade_reason_ts) < self._no_trade_reason_heartbeat_seconds
        ):
            return
        logger.info(f"No trade: {reason}")
        self._last_no_trade_reason = reason
        self._last_no_trade_reason_ts = now_ts

    def _manage_positions(
        self,
        positions: List,
        atr: float,
        ny_time: datetime,
        cfg: Any
    ):
        """Manage open positions - trailing, partials, session close"""

        # Check for end-of-session close
        if cfg.close_positions_at_session_end:
            trade_end = datetime.combine(
                ny_time.date(),
                datetime.strptime(f"{cfg.trade_end_hour}:{cfg.trade_end_minute}", "%H:%M").time()
            )
            close_time = trade_end - timedelta(minutes=cfg.session_end_close_minutes_before)

            if ny_time >= close_time:
                logger.info("End of session - closing all positions")
                results = self.executor.close_all_positions("End of session")
                for r in results:
                    if r.success:
                        logger.info(f"Closed position {r.ticket}")
                return

        # Manage partial profits
        partial_actions = self.executor.manage_partial_profits()
        for ticket, action in partial_actions.items():
            logger.info(f"Partial action: Ticket {ticket} -> {action}")

        # Manage trailing stops with adaptive multiplier
        df = self._data_cache
        trailing_actions = self.executor.manage_trailing_stops(atr, df=df)
        for ticket, action in trailing_actions.items():
            logger.debug(f"Trailing action: Ticket {ticket} -> {action}")

    def shutdown(self):
        """Clean shutdown"""
        logger.info("Shutting down strategy...")

        self.state_manager.set_connected(False)
        self.state_manager.update({
            "status": "stopped",
            "is_running": False,
        })

        mt5.shutdown()
        logger.info("Strategy shutdown complete")

    # BaseStrategy interface methods
    @classmethod
    def get_info(cls) -> StrategyInfo:
        """Return strategy metadata"""
        return _STRATEGY_INFO

    def get_id(self) -> str:
        return STRATEGY_ID

    def get_name(self) -> str:
        return STRATEGY_NAME

    def get_version(self) -> str:
        return STRATEGY_VERSION

    def get_state(self) -> Dict[str, Any]:
        """Return current strategy state for dashboard display"""
        return self.state_manager.get_all()
