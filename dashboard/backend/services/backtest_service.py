"""
Backtest Service - Orchestrates backtest execution and result storage
"""

from sqlalchemy.orm import Session
from datetime import datetime
import asyncio
import logging
from typing import Any, Dict, List

from ..models.database import (
    BacktestConfigModel, BacktestResultModel, BacktestTradeModel,
    BacktestStatus, TradeDirection, TradeStatus, SessionLocal
)
from ..core.backtest_engine import BacktestEngine, BacktestConfig
from ..core.advanced_backtest_engine import AdvancedEventBacktestEngine
from ..core.advanced_ml_backtest_engine import AdvancedEventMLBacktestEngine
from ..core.ml_backtest_engine import MLBacktestEngine, MLBacktestConfig
from ..core.parity_tools import compare_engine_results
from ..core.strategies.factory import create_strategy
from ..core.instrument_specs import get_instrument
from ..core.config_builder import build_config_from_preset

logger = logging.getLogger(__name__)


def _send_progress(result_id: int, progress: float, message: str):
    """Helper to send progress updates without circular imports"""
    try:
        from ..api.websocket import send_backtest_progress
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.create_task(send_backtest_progress(result_id, progress, message))
    except Exception:
        pass


def _send_completed(result_id: int, status: str, summary: dict):
    """Helper to send completion notifications without circular imports"""
    try:
        from ..api.websocket import send_backtest_completed
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.create_task(send_backtest_completed(result_id, status, summary))
    except Exception:
        pass


class BacktestService:
    """Service layer for backtest operations"""

    def __init__(self, db: Session):
        self.db = db

    @staticmethod
    def _is_ml_strategy(strategy_id: str) -> bool:
        return str(strategy_id or "").endswith("_ml_strategy")

    @staticmethod
    def _run_engine_mode(
        config_model: BacktestConfigModel,
        strategy_id: str,
        strategy_config: Dict[str, Any],
        engine_mode: str,
        progress_callback=None,
        enable_event_trace: bool = False,
    ) -> Dict[str, Any]:
        """
        Run a single backtest using selected engine mode.
        """
        mode = (engine_mode or "legacy").strip().lower()
        if mode not in {"legacy", "advanced"}:
            mode = "legacy"

        is_ml = BacktestService._is_ml_strategy(strategy_id)
        strategy = create_strategy(strategy_id, strategy_config)

        if is_ml:
            config = BacktestService._model_to_ml_config(config_model)
            if mode == "advanced":
                engine = AdvancedEventMLBacktestEngine(config, strategy=strategy)
                return engine.run(
                    progress_callback=progress_callback,
                    enable_event_trace=enable_event_trace,
                )
            engine = MLBacktestEngine(config, strategy=strategy)
            return engine.run(progress_callback=progress_callback)

        config = BacktestService._model_to_config(config_model)
        if mode == "advanced":
            engine = AdvancedEventBacktestEngine(config, strategy=strategy)
            return engine.run(
                progress_callback=progress_callback,
                enable_event_trace=enable_event_trace,
            )
        engine = BacktestEngine(config, strategy=strategy)
        return engine.run(progress_callback=progress_callback)

    @staticmethod
    def run_backtest_task(result_id: int, config_id: int):
        """
        Execute a backtest and store results.
        Called as a background task with its own database session.

        Args:
            result_id: ID of the BacktestResultModel to update
            config_id: ID of the BacktestConfigModel to use
        """
        # Create our own database session for the background task
        db = SessionLocal()

        try:
            # Query the config and result from the database
            config_model = db.query(BacktestConfigModel).filter(
                BacktestConfigModel.id == config_id
            ).first()

            result = db.query(BacktestResultModel).filter(
                BacktestResultModel.id == result_id
            ).first()

            if not config_model:
                logger.error(f"Config {config_id} not found")
                return

            if not result:
                logger.error(f"Result {result_id} not found")
                return

            # Update status to running
            result.status = BacktestStatus.RUNNING
            result.started_at = datetime.utcnow()
            db.commit()

            # Create backtest config from model
            logger.info("=" * 80)
            logger.info(f"STARTING BACKTEST (Result ID: {result_id}, Config ID: {config_id})")
            logger.info("=" * 80)
            logger.info(f"Config Name: {config_model.name}")
            logger.info(f"Strategy ID: {getattr(config_model, 'strategy_id', 'orb_strategy')}")
            logger.info(f"Symbol: {config_model.symbol}")
            logger.info(f"Timeframe: {config_model.timeframe}")
            logger.info(f"Date Range: {config_model.start_date} to {config_model.end_date}")
            logger.info(f"Initial Balance: ${config_model.initial_balance:,.2f}")
            logger.info("=" * 80)

            # Determine engine type based on strategy
            strategy_id = getattr(config_model, 'strategy_id', 'orb_strategy')
            is_ml_strategy = strategy_id.endswith('_ml_strategy')

            # Build a strategy config dict for the factory.
            # This merges optimal_parameters + preset overrides from the
            # strategy registry with any per-model overrides.
            strategy_config = BacktestService._build_strategy_config(config_model)
            strategy = create_strategy(strategy_id, strategy_config)
            if strategy:
                logger.info(f"Using strategy class: {strategy.__class__.__name__}")

            if is_ml_strategy:
                config = BacktestService._model_to_ml_config(config_model)
                engine = MLBacktestEngine(config, strategy=strategy)
                logger.info(f"Using ML Backtest Engine (base: {config.ml_base_strategy_id})")
            else:
                config = BacktestService._model_to_config(config_model)
                engine = BacktestEngine(config, strategy=strategy)

            # Progress callback
            def progress_callback(progress: float, message: str):
                _send_progress(result_id, progress, message)

            # Run backtest
            results = engine.run(progress_callback)

            # Store results
            BacktestService._store_results(db, result, results)

            # Send completion notification
            summary = {
                "total_trades": result.total_trades,
                "win_rate": result.win_rate,
                "net_profit": result.net_profit,
                "max_drawdown_percent": result.max_drawdown_percent,
            }
            _send_completed(result_id, "COMPLETED", summary)

            logger.info(f"Backtest {result_id} completed successfully")

        except Exception as e:
            logger.error(f"Backtest {result_id} failed: {e}", exc_info=True)

            try:
                result = db.query(BacktestResultModel).filter(
                    BacktestResultModel.id == result_id
                ).first()
                if result:
                    result.status = BacktestStatus.FAILED
                    result.error_message = str(e)
                    result.completed_at = datetime.utcnow()
                    db.commit()
            except Exception as db_error:
                logger.error(f"Could not update result status: {db_error}")

            # Send failure notification
            _send_completed(result_id, "FAILED", {"error": str(e)})

        finally:
            db.close()

    @staticmethod
    def run_walk_forward_task(result_id: int, config_id: int, wf_params: dict):
        """
        Execute walk-forward optimization and store stitched OOS results.

        Args:
            result_id: Existing BacktestResultModel row to update.
            config_id: BacktestConfigModel ID.
            wf_params: Walk-forward runtime parameters.
        """
        from ..core.walk_forward import (
            WalkForwardEngine,
            WalkForwardConfig,
            ParameterRange,
            default_orb_parameter_ranges,
        )

        db = SessionLocal()
        try:
            config_model = db.query(BacktestConfigModel).filter(
                BacktestConfigModel.id == config_id
            ).first()
            result = db.query(BacktestResultModel).filter(
                BacktestResultModel.id == result_id
            ).first()

            if not config_model:
                logger.error(f"Config {config_id} not found for walk-forward")
                return
            if not result:
                logger.error(f"Result {result_id} not found for walk-forward")
                return

            result.status = BacktestStatus.RUNNING
            result.started_at = datetime.utcnow()
            db.commit()

            strategy_id = getattr(config_model, "strategy_id", "orb_strategy")
            if BacktestService._is_ml_strategy(strategy_id):
                base_config = BacktestService._model_to_ml_config(config_model)
            else:
                base_config = BacktestService._model_to_config(config_model)
            strategy_config = BacktestService._build_strategy_config(config_model)

            wf_raw = wf_params if isinstance(wf_params, dict) else {}
            raw_ranges = wf_raw.get("param_ranges", [])
            param_ranges: List[ParameterRange] = []
            for item in raw_ranges:
                if not isinstance(item, dict):
                    continue
                name = item.get("name")
                values = item.get("values")
                if not name or not isinstance(values, list) or len(values) == 0:
                    continue
                param_ranges.append(ParameterRange(name=str(name), values=values))

            if not param_ranges:
                if strategy_id in (
                    "orb_strategy",
                    "advanced_orb_strategy",
                    "orb_ml_strategy",
                    "advanced_orb_ml_strategy",
                ):
                    param_ranges = default_orb_parameter_ranges()
                    logger.info("Using default ORB walk-forward parameter ranges")
                else:
                    logger.warning(
                        "No walk-forward param_ranges provided for strategy %s; running fixed-parameter OOS windows.",
                        strategy_id,
                    )

            wf_config = WalkForwardConfig(
                base_config=base_config,
                param_ranges=param_ranges,
                in_sample_days=int(wf_raw.get("in_sample_days", 180)),
                out_of_sample_days=int(wf_raw.get("out_of_sample_days", 60)),
                step_days=int(wf_raw.get("step_days", 60)),
                optimization_metric=str(wf_raw.get("optimization_metric", "sharpe_ratio")),
                min_trades_per_window=int(wf_raw.get("min_trades_per_window", 15)),
                max_workers=int(wf_raw.get("max_workers", 4)),
                strategy_id=strategy_id,
                strategy_config=strategy_config,
                search_mode=str(wf_raw.get("search_mode", "random")),
                random_samples=int(wf_raw.get("random_samples", 200)),
                random_seed=int(wf_raw.get("random_seed", 42)),
                max_exhaustive_grid_size=int(wf_raw.get("max_exhaustive_grid_size", 5000)),
                engine_mode=str(wf_raw.get("engine_mode", "legacy")),
                fallback_to_legacy_on_error=bool(wf_raw.get("fallback_to_legacy_on_error", True)),
                parity_check=bool(wf_raw.get("parity_check", False)),
                require_parity_pass=bool(wf_raw.get("require_parity_pass", False)),
                parity_tolerances=wf_raw.get("parity_tolerances", {}) or {},
            )

            engine = WalkForwardEngine(wf_config)

            def progress_callback(progress: float, message: str):
                _send_progress(result_id, progress, message)

            wf_results = engine.run(progress_callback=progress_callback)
            summary = wf_results.get("summary", {})
            stitched_metrics = summary.get("stitched_metrics", {})

            results_payload = {
                "metrics": stitched_metrics,
                "trades": wf_results.get("oos_trades", []),
                "equity_curve": wf_results.get("oos_equity_curve", []),
                "daily_pnl": wf_results.get("daily_pnl", []),
                "monthly_returns": wf_results.get("monthly_returns", {}),
                "regime_analysis": None,
            }
            BacktestService._store_results(db, result, results_payload)

            result.walk_forward_report = wf_results
            db.commit()

            _send_completed(
                result_id,
                "COMPLETED",
                {
                    "verdict": (summary.get("verdict") or {}).get("overall"),
                    "oos_sharpe": summary.get("stitched_oos_sharpe"),
                    "degradation_ratio": summary.get("degradation_ratio"),
                    "total_oos_trades": summary.get("total_oos_trades"),
                },
            )
            logger.info(f"Walk-forward {result_id} completed successfully")

        except Exception as e:
            logger.error(f"Walk-forward {result_id} failed: {e}", exc_info=True)
            try:
                result = db.query(BacktestResultModel).filter(
                    BacktestResultModel.id == result_id
                ).first()
                if result:
                    result.status = BacktestStatus.FAILED
                    result.error_message = str(e)
                    result.completed_at = datetime.utcnow()
                    db.commit()
            except Exception as db_error:
                logger.error(f"Could not update walk-forward status: {db_error}")
            _send_completed(result_id, "FAILED", {"error": str(e)})
        finally:
            db.close()

    @staticmethod
    def run_advanced_backtest_task(
        result_id: int,
        config_id: int,
        advanced_params: dict,
    ):
        """
        Execute advanced event-driven backtest and store results.

        This runs side-by-side with legacy backtest engine and does not alter
        existing run_backtest_task behavior.
        """
        db = SessionLocal()
        try:
            config_model = db.query(BacktestConfigModel).filter(
                BacktestConfigModel.id == config_id
            ).first()
            result = db.query(BacktestResultModel).filter(
                BacktestResultModel.id == result_id
            ).first()

            if not config_model:
                logger.error(f"Config {config_id} not found for advanced backtest")
                return
            if not result:
                logger.error(f"Result {result_id} not found for advanced backtest")
                return

            result.status = BacktestStatus.RUNNING
            result.started_at = datetime.utcnow()
            db.commit()

            adv_raw = advanced_params if isinstance(advanced_params, dict) else {}
            strategy_id = getattr(config_model, "strategy_id", "orb_strategy")
            strategy_config = BacktestService._build_strategy_config(config_model)
            engine_mode = str(adv_raw.get("engine_mode", "advanced")).strip().lower()
            if engine_mode not in {"legacy", "advanced"}:
                engine_mode = "advanced"
            enable_event_trace = bool(adv_raw.get("enable_event_trace", False))
            fallback_to_legacy_on_error = bool(
                adv_raw.get("fallback_to_legacy_on_error", True)
            )
            parity_check = bool(adv_raw.get("parity_check", False))
            require_parity_pass = bool(adv_raw.get("require_parity_pass", False))
            parity_tolerances = adv_raw.get("parity_tolerances", {}) or {}

            def progress_callback(progress: float, message: str):
                _send_progress(result_id, progress, message)

            used_mode = engine_mode
            try:
                candidate_results = BacktestService._run_engine_mode(
                    config_model=config_model,
                    strategy_id=strategy_id,
                    strategy_config=strategy_config,
                    engine_mode=engine_mode,
                    progress_callback=progress_callback,
                    enable_event_trace=enable_event_trace,
                )
            except Exception:
                if engine_mode == "advanced" and fallback_to_legacy_on_error:
                    logger.warning(
                        "Advanced engine failed, falling back to legacy engine for result_id=%s",
                        result_id,
                    )
                    candidate_results = BacktestService._run_engine_mode(
                        config_model=config_model,
                        strategy_id=strategy_id,
                        strategy_config=strategy_config,
                        engine_mode="legacy",
                        progress_callback=progress_callback,
                    )
                    used_mode = "legacy_fallback_on_error"
                else:
                    raise

            parity_report = None
            if parity_check and used_mode.startswith("advanced"):
                reference_results = BacktestService._run_engine_mode(
                    config_model=config_model,
                    strategy_id=strategy_id,
                    strategy_config=strategy_config,
                    engine_mode="legacy",
                    progress_callback=None,
                )
                parity_report = compare_engine_results(
                    reference_results,
                    candidate_results,
                    tolerances=parity_tolerances,
                )
                if require_parity_pass and not parity_report.get("passed", False):
                    if fallback_to_legacy_on_error:
                        candidate_results = reference_results
                        used_mode = "legacy_fallback_on_parity"
                    else:
                        raise ValueError("Parity check failed and require_parity_pass=True")

            if parity_report is not None:
                candidate_results["parity_report"] = parity_report
                candidate_results["engine_mode_used"] = used_mode

            BacktestService._store_results(db, result, candidate_results)

            if parity_report is not None:
                result.walk_forward_report = {
                    "engine_mode_used": used_mode,
                    "parity_report": parity_report,
                }
                db.commit()

            summary = {
                "engine_mode_used": used_mode,
                "total_events": len(candidate_results.get("event_trace", [])),
                "parity_passed": None if parity_report is None else parity_report.get("passed"),
                "total_trades": result.total_trades,
                "win_rate": result.win_rate,
                "net_profit": result.net_profit,
                "max_drawdown_percent": result.max_drawdown_percent,
            }
            _send_completed(result_id, "COMPLETED", summary)
            logger.info(f"Advanced backtest {result_id} completed successfully")

        except Exception as e:
            logger.error(f"Advanced backtest {result_id} failed: {e}", exc_info=True)
            try:
                result = db.query(BacktestResultModel).filter(
                    BacktestResultModel.id == result_id
                ).first()
                if result:
                    result.status = BacktestStatus.FAILED
                    result.error_message = str(e)
                    result.completed_at = datetime.utcnow()
                    db.commit()
            except Exception as db_error:
                logger.error(f"Could not update advanced backtest status: {db_error}")
            _send_completed(result_id, "FAILED", {"error": str(e)})
        finally:
            db.close()

    @staticmethod
    def _model_to_config(model: BacktestConfigModel) -> BacktestConfig:
        """Convert database model to backtest config.

        Uses the shared ``build_config_from_preset`` so that the UI
        and batch script always produce identical BacktestConfig objects
        for the same preset + symbol combination.  DB model values act
        as per-run overrides (user tweaks in the Simulation Tuning section).
        """
        strategy_id = getattr(model, 'strategy_id', 'orb_strategy')
        preset_id = getattr(model, 'preset_name', None) or getattr(model, 'preset', 'default')

        # Collect every DB model field that may override the preset.
        # None values are ignored by the shared builder.
        overrides = {
            'risk_percent': getattr(model, 'risk_percent', None),
            'max_spread_usd': getattr(model, 'max_spread_usd', None),
            'max_daily_loss_usd': getattr(model, 'max_daily_loss_usd', None),
            'max_total_risk_usd': getattr(model, 'max_total_risk_usd', None),
            'min_sl_usd': getattr(model, 'min_sl_usd', None),
            'max_sl_usd': getattr(model, 'max_sl_usd', None),
            'gold_rr_threshold': model.gold_rr_threshold,
            'min_fvg_gap': getattr(model, 'min_fvg_gap', None),
            'bias_min_strength': getattr(model, 'bias_min_strength', None),
            'max_daily_trades': getattr(model, 'max_daily_trades', None),
            'stop_after_first_win': getattr(model, 'stop_after_first_win', None),
            'use_trailing': getattr(model, 'use_trailing', None),
            'trailing_atr_period': getattr(model, 'trailing_atr_period', None),
            'trailing_atr_multiplier': getattr(model, 'trailing_atr_multiplier', None),
            'min_adr_for_trend': getattr(model, 'min_adr_for_trend', None),
            'adr_period': getattr(model, 'adr_period', None),
            'fvg_lookback': getattr(model, 'fvg_lookback', None),
            'displacement_percentile': getattr(model, 'displacement_percentile', None),
            'displacement_lookback': getattr(model, 'displacement_lookback', None),
            'max_opposing_wick_ratio': getattr(model, 'max_opposing_wick_ratio', None),
            'ob_lookback': getattr(model, 'ob_lookback', None),
            'ob_min_body_percent': getattr(model, 'ob_min_body_percent', None),
            'ob_validation_bars': getattr(model, 'ob_validation_bars', None),
            'liquidity_wick_ratio': getattr(model, 'liquidity_wick_ratio', None),
            'sweep_tolerance_usd': getattr(model, 'sweep_tolerance_usd', None),
            'trade_start_time': getattr(model, 'trade_start_time', None),
            'trade_end_time': getattr(model, 'trade_end_time', None),
            'orb_start_time': getattr(model, 'orb_start_time', None),
            'orb_end_time': getattr(model, 'orb_end_time', None),
            'asian_start': getattr(model, 'asian_start', None),
            'asian_end': getattr(model, 'asian_end', None),
            'london_start': getattr(model, 'london_start', None),
            'london_end': getattr(model, 'london_end', None),
            'slippage_atr_factor': getattr(model, 'slippage_atr_factor', None),
            'simulate_spread': getattr(model, 'simulate_spread', None),
            'use_variable_spread': getattr(model, 'use_variable_spread', None),
            'simulate_slippage': getattr(model, 'simulate_slippage', None),
            'simulate_swap': getattr(model, 'simulate_swap', None),
            'close_before_weekend': getattr(model, 'close_before_weekend', None),
            'friday_close_hour': getattr(model, 'friday_close_hour', None),
            'friday_close_minute': getattr(model, 'friday_close_minute', None),
            'enable_cross_asset_filter': getattr(model, 'enable_cross_asset_filter', None),
            'regime_timeframe': getattr(model, 'regime_timeframe', None),
            'regime_lookback_bars': getattr(model, 'regime_lookback_bars', None),
            'regime_return_bars': getattr(model, 'regime_return_bars', None),
            'regime_signal_threshold': getattr(model, 'regime_signal_threshold', None),
            'regime_strong_threshold': getattr(model, 'regime_strong_threshold', None),
            'regime_block_countertrend': getattr(model, 'regime_block_countertrend', None),
            'regime_reduce_size_in_headwind': getattr(model, 'regime_reduce_size_in_headwind', None),
            'regime_tailwind_risk_multiplier': getattr(model, 'regime_tailwind_risk_multiplier', None),
            'regime_headwind_risk_multiplier': getattr(model, 'regime_headwind_risk_multiplier', None),
            'regime_neutral_risk_multiplier': getattr(model, 'regime_neutral_risk_multiplier', None),
            'regime_symbol_dxy': getattr(model, 'regime_symbol_dxy', None),
            'regime_symbol_yield': getattr(model, 'regime_symbol_yield', None),
            'regime_symbol_riskoff': getattr(model, 'regime_symbol_riskoff', None),
            'regime_symbol_riskon': getattr(model, 'regime_symbol_riskon', None),
            'regime_weight_dxy': getattr(model, 'regime_weight_dxy', None),
            'regime_weight_yield': getattr(model, 'regime_weight_yield', None),
            'regime_weight_riskoff': getattr(model, 'regime_weight_riskoff', None),
            'regime_weight_riskon': getattr(model, 'regime_weight_riskon', None),
            'random_seed': getattr(model, 'random_seed', None),
        }

        config, _ = build_config_from_preset(
            strategy_id=strategy_id,
            preset_id=preset_id,
            symbol=model.symbol,
            timeframe=model.timeframe,
            start_date=model.start_date,
            end_date=model.end_date,
            initial_balance=model.initial_balance,
            data_source=getattr(model, 'data_source', 'csv_only'),
            csv_files=getattr(model, 'csv_files', None),
            overrides=overrides,
        )
        return config

    @staticmethod
    def _model_to_ml_config(model: BacktestConfigModel) -> MLBacktestConfig:
        """Convert database model to ML backtest config"""
        base = BacktestService._model_to_config(model)
        # Build MLBacktestConfig from base config fields + ML fields
        ml_config = MLBacktestConfig(
            **{k: v for k, v in base.__dict__.items()},
            use_ml_filter=getattr(model, 'use_ml_filter', True),
            ml_min_win_probability=getattr(model, 'ml_min_win_probability', 0.55),
            use_ml_dynamic_rr=getattr(model, 'use_ml_dynamic_rr', False),
            ml_base_strategy_id=getattr(model, 'ml_base_strategy_id', 'orb_strategy'),
            ml_model_id=getattr(model, 'ml_model_id', None),
        )
        return ml_config

    @staticmethod
    def _build_strategy_config(model: BacktestConfigModel) -> dict:
        """
        Build a flat dict of strategy parameters from the database model.

        This dict is passed to the strategy factory's ``create_strategy()``
        and contains every parameter the strategy class might look up via
        ``self.config.get(...)``.

        Merges: registry optimal_parameters + preset overrides + DB model overrides.
        """
        from ..core.strategy_registry import StrategyRegistry

        strategy_id = getattr(model, 'strategy_id', 'orb_strategy')
        # BacktestConfigModel stores preset in ``preset_name``.
        # Keep a fallback to legacy ``preset`` for backwards compatibility.
        preset_id = getattr(model, 'preset_name', None) or getattr(model, 'preset', 'default')

        # Start from the full registry config (optimal_parameters + preset)
        config = StrategyRegistry.get_preset_config(
            strategy_id,
            preset_id,
            getattr(model, 'symbol', None),
        )

        # User's chosen symbol takes precedence over preset default
        symbol = getattr(model, 'symbol', None) or config.get('symbol', 'XAUUSD')
        config['symbol'] = symbol

        # Inject instrument metadata so strategies can access it
        inst = get_instrument(symbol)
        config['_instrument'] = inst

        # Fill instrument-specific defaults where the preset didn't set them.
        # These act as sensible fallbacks; db_overrides below can still
        # override any of them with user-chosen values.
        config.setdefault('max_spread_usd', inst.max_spread)
        config.setdefault('min_sl_usd', inst.min_sl)
        config.setdefault('max_sl_usd', inst.max_sl)
        config.setdefault('contract_size', inst.contract_size)
        config.setdefault('gold_rr_threshold', inst.rr_threshold)
        config.setdefault('commission_per_lot', inst.commission_per_lot)
        config.setdefault('swap_long_per_lot', inst.swap_long)
        config.setdefault('swap_short_per_lot', inst.swap_short)
        config.setdefault('min_fvg_gap', inst.min_fvg_gap)
        preset_baseline = dict(config)

        # Legacy configs may store old instrument fallback values from before
        # preset layering was fixed. If a DB value exactly matches instrument
        # fallback while the preset baseline differs, ignore that stale value.
        stale_instrument_fallback = {
            'max_spread_usd': inst.max_spread,
            'min_sl_usd': inst.min_sl,
            'max_sl_usd': inst.max_sl,
            'min_fvg_gap': inst.min_fvg_gap,
            'slippage_atr_factor': inst.slippage_atr_factor,
        }

        def _same_value(a, b, tol: float = 1e-9) -> bool:
            if a is None or b is None:
                return a is b
            try:
                return abs(float(a) - float(b)) <= tol
            except (TypeError, ValueError):
                return a == b

        # Layer on DB model overrides — every user-tunable field that the
        # Run Backtest page can change must appear here so per-run overrides
        # actually reach the engine instead of being masked by the preset.
        db_overrides = {
            # ICT parameters
            'fvg_lookback': getattr(model, 'fvg_lookback', None),
            'displacement_percentile': getattr(model, 'displacement_percentile', None),
            'displacement_lookback': getattr(model, 'displacement_lookback', None),
            'max_opposing_wick_ratio': getattr(model, 'max_opposing_wick_ratio', None),
            'ob_lookback': getattr(model, 'ob_lookback', None),
            'ob_min_body_percent': getattr(model, 'ob_min_body_percent', None),
            'ob_validation_bars': getattr(model, 'ob_validation_bars', None),
            'liquidity_wick_ratio': getattr(model, 'liquidity_wick_ratio', None),
            'sweep_tolerance_usd': getattr(model, 'sweep_tolerance_usd', None),
            # Risk
            'risk_percent': getattr(model, 'risk_percent', None),
            'bias_min_strength': getattr(model, 'bias_min_strength', None),
            'max_daily_loss_usd': getattr(model, 'max_daily_loss_usd', None),
            'max_total_risk_usd': getattr(model, 'max_total_risk_usd', None),
            'max_daily_trades': getattr(model, 'max_daily_trades', None),
            'stop_after_first_win': getattr(model, 'stop_after_first_win', None),
            # Session times
            'trade_start_time': getattr(model, 'trade_start_time', None),
            'trade_end_time': getattr(model, 'trade_end_time', None),
            'orb_start_time': getattr(model, 'orb_start_time', None),
            'orb_end_time': getattr(model, 'orb_end_time', None),
            'asian_start': getattr(model, 'asian_start', None),
            'asian_end': getattr(model, 'asian_end', None),
            'london_start': getattr(model, 'london_start', None),
            'london_end': getattr(model, 'london_end', None),
            # Trailing
            'use_trailing': getattr(model, 'use_trailing', None),
            'trailing_atr_period': getattr(model, 'trailing_atr_period', None),
            'trailing_atr_multiplier': getattr(model, 'trailing_atr_multiplier', None),
            # Trend filter
            'min_adr_for_trend': getattr(model, 'min_adr_for_trend', None),
            'adr_period': getattr(model, 'adr_period', None),
            # Simulation costs
            'contract_size': getattr(model, 'contract_size', None),
            'simulate_spread': getattr(model, 'simulate_spread', None),
            'use_variable_spread': getattr(model, 'use_variable_spread', None),
            'simulate_slippage': getattr(model, 'simulate_slippage', None),
            'slippage_atr_factor': getattr(model, 'slippage_atr_factor', None),
            'min_slippage_usd': getattr(model, 'min_slippage_usd', None),
            'max_slippage_usd': getattr(model, 'max_slippage_usd', None),
            'commission_per_lot': getattr(model, 'commission_per_lot', None),
            'simulate_swap': getattr(model, 'simulate_swap', None),
            'swap_long_per_lot': getattr(model, 'swap_long_per_lot', None),
            'swap_short_per_lot': getattr(model, 'swap_short_per_lot', None),
            'triple_swap_day': getattr(model, 'triple_swap_day', None),
            # Friday close
            'close_before_weekend': getattr(model, 'close_before_weekend', None),
            'friday_close_hour': getattr(model, 'friday_close_hour', None),
            'friday_close_minute': getattr(model, 'friday_close_minute', None),
            # Instrument-specific overrides (user can override instrument defaults)
            'max_spread_usd': getattr(model, 'max_spread_usd', None),
            'min_sl_usd': getattr(model, 'min_sl_usd', None),
            'max_sl_usd': getattr(model, 'max_sl_usd', None),
            'gold_rr_threshold': getattr(model, 'gold_rr_threshold', None),
            'min_fvg_gap': getattr(model, 'min_fvg_gap', None),
            # Cross-asset regime filter
            'enable_cross_asset_filter': getattr(model, 'enable_cross_asset_filter', None),
            'regime_timeframe': getattr(model, 'regime_timeframe', None),
            'regime_lookback_bars': getattr(model, 'regime_lookback_bars', None),
            'regime_return_bars': getattr(model, 'regime_return_bars', None),
            'regime_signal_threshold': getattr(model, 'regime_signal_threshold', None),
            'regime_strong_threshold': getattr(model, 'regime_strong_threshold', None),
            'regime_block_countertrend': getattr(model, 'regime_block_countertrend', None),
            'regime_reduce_size_in_headwind': getattr(model, 'regime_reduce_size_in_headwind', None),
            'regime_tailwind_risk_multiplier': getattr(model, 'regime_tailwind_risk_multiplier', None),
            'regime_headwind_risk_multiplier': getattr(model, 'regime_headwind_risk_multiplier', None),
            'regime_neutral_risk_multiplier': getattr(model, 'regime_neutral_risk_multiplier', None),
            'regime_symbol_dxy': getattr(model, 'regime_symbol_dxy', None),
            'regime_symbol_yield': getattr(model, 'regime_symbol_yield', None),
            'regime_symbol_riskoff': getattr(model, 'regime_symbol_riskoff', None),
            'regime_symbol_riskon': getattr(model, 'regime_symbol_riskon', None),
            'regime_weight_dxy': getattr(model, 'regime_weight_dxy', None),
            'regime_weight_yield': getattr(model, 'regime_weight_yield', None),
            'regime_weight_riskoff': getattr(model, 'regime_weight_riskoff', None),
            'regime_weight_riskon': getattr(model, 'regime_weight_riskon', None),
        }
        for k, v in db_overrides.items():
            if v is None:
                continue
            if k in stale_instrument_fallback:
                baseline_v = preset_baseline.get(k)
                inst_v = stale_instrument_fallback[k]
                if baseline_v is not None and _same_value(v, inst_v) and not _same_value(baseline_v, inst_v):
                    continue
            config[k] = v

        return config

    @staticmethod
    def _store_results(db: Session, result: BacktestResultModel, results: dict):
        """Store backtest results in database"""
        metrics = results.get('metrics', {})

        try:
            # Update result metrics
            result.status = BacktestStatus.COMPLETED
            result.completed_at = datetime.utcnow()

            # Basic metrics
            result.total_trades = metrics.get('total_trades', 0)
            result.winning_trades = metrics.get('winning_trades', 0)
            result.losing_trades = metrics.get('losing_trades', 0)
            result.win_rate = metrics.get('win_rate', 0.0)

            # Financial metrics
            result.initial_balance = metrics.get('initial_balance', 0.0)
            result.final_balance = metrics.get('final_balance', 0.0)
            result.total_profit = metrics.get('total_profit', 0.0)
            result.total_loss = metrics.get('total_loss', 0.0)
            result.net_profit = metrics.get('net_profit', 0.0)
            result.profit_factor = metrics.get('profit_factor', 0.0)

            # Risk metrics
            result.max_drawdown = metrics.get('max_drawdown', 0.0)
            result.max_drawdown_percent = metrics.get('max_drawdown_percent', 0.0)
            result.sharpe_ratio = metrics.get('sharpe_ratio', 0.0)
            result.sortino_ratio = metrics.get('sortino_ratio', 0.0)
            result.calmar_ratio = metrics.get('calmar_ratio', 0.0)

            # Trade statistics
            result.avg_win = metrics.get('avg_win', 0.0)
            result.avg_loss = metrics.get('avg_loss', 0.0)
            result.largest_win = metrics.get('largest_win', 0.0)
            result.largest_loss = metrics.get('largest_loss', 0.0)
            result.avg_trade_duration = metrics.get('avg_trade_duration', 0.0)
            result.avg_rr_ratio = metrics.get('avg_rr_ratio', 0.0)
            result.expectancy = metrics.get('expectancy', 0.0)

            # Curve data
            result.equity_curve = results.get('equity_curve')
            result.drawdown_curve = metrics.get('drawdown_curve')
            result.daily_pnl = results.get('daily_pnl')
            result.monthly_returns = results.get('monthly_returns')
            result.regime_analysis = results.get('regime_analysis')
            result.microstructure_analysis = results.get('microstructure_analysis')
            result.run_manifest = results.get('run_manifest')

            # Data fingerprint for reproducibility
            result.data_hash = results.get('data_hash')

            # ML Stats (if ML engine was used)
            ml_stats = results.get('ml_stats')
            if ml_stats:
                # Don't store individual filtered trades list in DB (too large)
                ml_stats_clean = {k: v for k, v in ml_stats.items() if k != 'filtered_trades'}
                result.ml_stats = ml_stats_clean

            db.flush()

            # Store individual trades
            trades = results.get('trades', [])
            for trade_data in trades:
                trade = BacktestTradeModel(
                    result_id=result.id,
                    trade_number=trade_data.get('trade_number', 0),
                    direction=TradeDirection(trade_data.get('direction', 'BUY')),
                    status=TradeStatus.CLOSED,
                    entry_time=datetime.fromisoformat(trade_data['entry_time']) if trade_data.get('entry_time') else None,
                    exit_time=datetime.fromisoformat(trade_data['exit_time']) if trade_data.get('exit_time') else None,
                    entry_price=trade_data.get('entry_price', 0.0),
                    exit_price=trade_data.get('exit_price'),
                    stop_loss=trade_data.get('stop_loss', 0.0),
                    take_profit=trade_data.get('take_profit'),
                    lot_size=trade_data.get('lot_size', 0.0),
                    profit_loss=trade_data.get('profit_loss', 0.0),
                    r_multiple=trade_data.get('r_multiple', 0.0),
                    setup_type=trade_data.get('setup_type'),
                    exit_reason=trade_data.get('exit_reason'),
                    # Strategy diagnostics
                    entry_reason=trade_data.get('entry_reason'),
                    gross_pnl=trade_data.get('gross_pnl'),
                    spread_cost=trade_data.get('spread_cost'),
                    slippage_cost=trade_data.get('slippage_cost'),
                    commission_cost=trade_data.get('commission_cost'),
                    swap_cost=trade_data.get('swap_cost'),
                    balance_before=trade_data.get('balance_before'),
                    balance_after=trade_data.get('balance_after'),
                    # ML data
                    ml_features=trade_data.get('ml_features'),
                    max_favorable_excursion=trade_data.get('max_favorable_excursion'),
                    max_adverse_excursion=trade_data.get('max_adverse_excursion'),
                )
                db.add(trade)

            db.commit()
        except Exception:
            db.rollback()
            raise

    def get_backtest_progress(self, result_id: int) -> dict:
        """Get current progress of a running backtest"""
        result = self.db.query(BacktestResultModel).filter(
            BacktestResultModel.id == result_id
        ).first()

        if not result:
            return {"error": "Not found"}

        return {
            "result_id": result_id,
            "status": result.status.value,
            "started_at": result.started_at.isoformat() if result.started_at else None,
            "completed_at": result.completed_at.isoformat() if result.completed_at else None,
            "error_message": result.error_message,
        }

    def cancel_backtest(self, result_id: int) -> bool:
        """Cancel a running backtest (if possible)"""
        result = self.db.query(BacktestResultModel).filter(
            BacktestResultModel.id == result_id
        ).first()

        if not result:
            return False

        if result.status == BacktestStatus.RUNNING:
            result.status = BacktestStatus.FAILED
            result.error_message = "Cancelled by user"
            result.completed_at = datetime.utcnow()
            self.db.commit()
            return True

        return False
