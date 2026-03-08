"""
Walk-Forward Optimization Engine.

This module runs rolling in-sample optimization + out-of-sample validation
on top of the existing BacktestEngine.
"""

from __future__ import annotations

from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta
from itertools import product
import logging
from typing import Any, Callable, Dict, List, Optional, Tuple

import numpy as np

from .backtest_engine import BacktestConfig, BacktestEngine
from .advanced_backtest_engine import AdvancedEventBacktestEngine
from .advanced_ml_backtest_engine import AdvancedEventMLBacktestEngine
from .metrics_calculator import MetricsCalculator, TradeRecord
from .ml_backtest_engine import MLBacktestConfig, MLBacktestEngine
from .parity_tools import compare_engine_results
from .strategies.factory import create_strategy

logger = logging.getLogger(__name__)


@dataclass
class ParameterRange:
    """Defines a single strategy/backtest parameter search range."""

    name: str
    values: List[Any]


@dataclass
class WalkForwardConfig:
    """Configuration for one walk-forward run."""

    base_config: BacktestConfig
    param_ranges: List[ParameterRange] = field(default_factory=list)
    in_sample_days: int = 180
    out_of_sample_days: int = 60
    step_days: int = 60
    optimization_metric: str = "sharpe_ratio"
    min_trades_per_window: int = 15
    max_workers: int = 4
    strategy_id: Optional[str] = None
    strategy_config: Optional[Dict[str, Any]] = None
    search_mode: str = "random"  # random | exhaustive
    random_samples: int = 200
    random_seed: int = 42
    max_exhaustive_grid_size: int = 5000
    engine_mode: str = "legacy"  # legacy | advanced
    fallback_to_legacy_on_error: bool = True
    parity_check: bool = False
    require_parity_pass: bool = False
    parity_tolerances: Dict[str, float] = field(default_factory=dict)


@dataclass
class WindowDefinition:
    """Single walk-forward window definition."""

    window_id: int
    is_start: datetime
    is_end: datetime
    oos_start: datetime
    oos_end: datetime


@dataclass
class WindowResult:
    """Result bundle for one walk-forward window."""

    window_id: int
    is_start: datetime
    is_end: datetime
    oos_start: datetime
    oos_end: datetime
    best_params: Dict[str, Any]
    is_metrics: Dict[str, Any]
    oos_metrics: Dict[str, Any]
    oos_trades: List[Dict[str, Any]]
    all_is_results: List[Dict[str, Any]]
    param_stability: Dict[str, Dict[str, Any]]


def default_orb_parameter_ranges() -> List[ParameterRange]:
    """Default ORB optimization ranges (signal/execution logic only)."""

    return [
        ParameterRange("bias_min_strength", [20, 30, 40, 50, 60]),
        ParameterRange("trailing_atr_multiplier", [1.0, 1.25, 1.5, 1.75, 2.0, 2.5]),
        ParameterRange("fvg_lookback", [30, 50, 75, 100]),
        ParameterRange("displacement_percentile", [65, 70, 75, 80, 85]),
        ParameterRange("min_fvg_gap", [0.20, 0.30, 0.40, 0.50]),
    ]


def _timeframe_to_delta(timeframe: Optional[str]) -> timedelta:
    """Convert timeframe labels (M1, M5, H1, D1) to a timedelta."""

    if not timeframe:
        return timedelta(minutes=1)
    tf = str(timeframe).strip().upper()
    try:
        if tf.startswith("M"):
            return timedelta(minutes=int(tf[1:]))
        if tf.startswith("H"):
            return timedelta(hours=int(tf[1:]))
        if tf.startswith("D"):
            return timedelta(days=int(tf[1:]))
    except Exception:
        pass
    return timedelta(minutes=1)


def _config_to_dict(config: BacktestConfig) -> Dict[str, Any]:
    """Serialize BacktestConfig for multiprocessing transport."""

    data = asdict(config)
    for key in ("start_date", "end_date"):
        value = data.get(key)
        if isinstance(value, datetime):
            data[key] = value.isoformat()
    data["__config_class"] = "ml" if isinstance(config, MLBacktestConfig) else "base"
    return data


def _dict_to_config(data: Dict[str, Any]) -> BacktestConfig:
    """Deserialize BacktestConfig from a dict."""

    parsed = dict(data)
    cls_marker = parsed.pop("__config_class", "base")
    for key in ("start_date", "end_date"):
        value = parsed.get(key)
        if isinstance(value, str):
            parsed[key] = datetime.fromisoformat(value)
    if cls_marker == "ml":
        return MLBacktestConfig(**parsed)
    return BacktestConfig(**parsed)


def _is_ml_strategy(strategy_id: Optional[str]) -> bool:
    return bool(strategy_id and str(strategy_id).endswith("_ml_strategy"))


def _run_engine(
    config: BacktestConfig,
    strategy,
    strategy_id: Optional[str],
    engine_mode: str,
):
    mode = (engine_mode or "legacy").strip().lower()
    if mode not in {"legacy", "advanced"}:
        mode = "legacy"

    if _is_ml_strategy(strategy_id):
        if mode == "advanced":
            engine = AdvancedEventMLBacktestEngine(config, strategy=strategy)
            return engine.run(progress_callback=None, enable_event_trace=False), "advanced"
        engine = MLBacktestEngine(config, strategy=strategy)
        return engine.run(progress_callback=None), "legacy"

    if mode == "advanced":
        engine = AdvancedEventBacktestEngine(config, strategy=strategy)
        return engine.run(progress_callback=None, enable_event_trace=False), "advanced"

    engine = BacktestEngine(config, strategy=strategy)
    return engine.run(progress_callback=None), "legacy"


def _safe_dt(value: Any) -> Optional[datetime]:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value)
        except Exception:
            return None
    return None


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return fallback


def _generate_param_grid(param_ranges: List[ParameterRange]) -> List[Dict[str, Any]]:
    """Generate the full Cartesian grid of parameter values."""

    if not param_ranges:
        return [{}]

    names = [p.name for p in param_ranges]
    values = [p.values for p in param_ranges]
    grid = [dict(zip(names, combo)) for combo in product(*values)]
    return grid


def _sample_param_grid(
    param_ranges: List[ParameterRange],
    n_samples: int,
    seed: int,
) -> List[Dict[str, Any]]:
    """Randomly sample parameter combinations (deduplicated)."""

    if not param_ranges:
        return [{}]

    rng = np.random.default_rng(seed)
    names = [p.name for p in param_ranges]
    values = [p.values for p in param_ranges]

    sampled: List[Dict[str, Any]] = []
    seen: set[Tuple[Tuple[str, Any], ...]] = set()

    max_unique = int(np.prod([len(v) for v in values]))
    target = max(1, min(n_samples, max_unique))
    max_attempts = target * 10
    attempts = 0

    while len(sampled) < target and attempts < max_attempts:
        combo: Dict[str, Any] = {}
        for name, value_list in zip(names, values):
            picked = rng.choice(value_list)
            if hasattr(picked, "item"):
                picked = picked.item()
            combo[name] = picked
        key = tuple(sorted(combo.items()))
        if key not in seen:
            seen.add(key)
            sampled.append(combo)
        attempts += 1

    if not sampled:
        return [{}]
    return sampled


def _resolve_param_grid(config: WalkForwardConfig) -> List[Dict[str, Any]]:
    """Resolve parameter combinations according to search mode."""

    mode = (config.search_mode or "random").strip().lower()
    if mode == "exhaustive":
        full_grid = _generate_param_grid(config.param_ranges)
        if len(full_grid) > config.max_exhaustive_grid_size:
            logger.warning(
                "Exhaustive grid too large (%d > %d). Falling back to random sampling (%d).",
                len(full_grid),
                config.max_exhaustive_grid_size,
                config.random_samples,
            )
            return _sample_param_grid(
                config.param_ranges,
                n_samples=config.random_samples,
                seed=config.random_seed,
            )
        return full_grid

    return _sample_param_grid(
        config.param_ranges,
        n_samples=config.random_samples,
        seed=config.random_seed,
    )


def _generate_windows(
    total_start: datetime,
    total_end: datetime,
    is_days: int,
    oos_days: int,
    step_days: int,
    timeframe: Optional[str],
) -> List[WindowDefinition]:
    """
    Generate rolling IS/OOS windows.

    Windows are non-overlapping at the IS/OOS boundary by design:
    - IS uses [is_start, is_end] inclusive
    - OOS uses [oos_start, oos_end] inclusive
    - oos_start = is_end + one_bar
    """

    if not total_start or not total_end:
        raise ValueError("Walk-forward requires base_config.start_date and base_config.end_date")
    if total_end <= total_start:
        raise ValueError("end_date must be greater than start_date")
    if is_days <= 0 or oos_days <= 0 or step_days <= 0:
        raise ValueError("Window sizes must be positive days")

    bar_delta = _timeframe_to_delta(timeframe)
    windows: List[WindowDefinition] = []
    cursor = total_start

    while True:
        is_end_exclusive = cursor + timedelta(days=is_days)
        oos_start = is_end_exclusive
        oos_end_exclusive = oos_start + timedelta(days=oos_days)

        is_end = is_end_exclusive - bar_delta
        oos_end = oos_end_exclusive - bar_delta
        if oos_end > total_end:
            break

        windows.append(
            WindowDefinition(
                window_id=len(windows),
                is_start=cursor,
                is_end=is_end,
                oos_start=oos_start,
                oos_end=oos_end,
            )
        )

        cursor += timedelta(days=step_days)

    if not windows:
        required_days = is_days + oos_days
        available_days = max(0, (total_end - total_start).days)
        raise ValueError(
            f"Not enough data for walk-forward: need at least {required_days} days, have {available_days}."
        )

    return windows


def _run_single_backtest(
    base_config_dict: Dict[str, Any],
    param_overrides: Dict[str, Any],
    start_date: datetime,
    end_date: datetime,
    strategy_id: Optional[str] = None,
    strategy_config: Optional[Dict[str, Any]] = None,
    engine_mode: str = "legacy",
    fallback_to_legacy_on_error: bool = True,
) -> Dict[str, Any]:
    """Run one backtest with parameter overrides for the given window."""

    config = _dict_to_config(base_config_dict)
    config.start_date = start_date
    config.end_date = end_date

    unknown_params: List[str] = []
    for name, value in (param_overrides or {}).items():
        if hasattr(config, name):
            setattr(config, name, value)
        else:
            unknown_params.append(name)

    if unknown_params:
        logger.warning("Skipping unknown BacktestConfig params: %s", unknown_params)

    strategy = None
    if strategy_id:
        merged_cfg = dict(strategy_config or {})
        merged_cfg.update(param_overrides or {})
        strategy = create_strategy(strategy_id, merged_cfg)

    used_mode = engine_mode
    try:
        results, used_mode = _run_engine(
            config=config,
            strategy=strategy,
            strategy_id=strategy_id,
            engine_mode=engine_mode,
        )
    except Exception:
        if (engine_mode or "").strip().lower() == "advanced" and fallback_to_legacy_on_error:
            results, used_mode = _run_engine(
                config=config,
                strategy=strategy,
                strategy_id=strategy_id,
                engine_mode="legacy",
            )
            used_mode = "legacy_fallback_on_error"
        else:
            raise

    metrics = results.get("metrics", {})

    return {
        "metrics": metrics,
        "trades": results.get("trades", []),
        "param_overrides": dict(param_overrides or {}),
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
        "trade_count": int(metrics.get("total_trades", 0) or 0),
        "engine_mode_used": used_mode,
    }


def _optimize_in_sample(
    base_config: BacktestConfig,
    param_grid: List[Dict[str, Any]],
    is_start: datetime,
    is_end: datetime,
    optimization_metric: str,
    min_trades: int,
    max_workers: int,
    strategy_id: Optional[str] = None,
    strategy_config: Optional[Dict[str, Any]] = None,
    engine_mode: str = "legacy",
    fallback_to_legacy_on_error: bool = True,
) -> Tuple[Dict[str, Any], Dict[str, Any], List[Dict[str, Any]]]:
    """Optimize parameters on one IS window and return the best candidate."""

    base_dict = _config_to_dict(base_config)
    all_results: List[Dict[str, Any]] = []
    workers = max(1, int(max_workers or 1))

    if workers == 1 or len(param_grid) <= 1:
        for params in param_grid:
            try:
                all_results.append(
                    _run_single_backtest(
                        base_dict,
                        params,
                        is_start,
                        is_end,
                        strategy_id,
                        strategy_config,
                        engine_mode,
                        fallback_to_legacy_on_error,
                    )
                )
            except Exception as exc:
                logger.error("IS backtest failed for params %s: %s", params, exc)
                all_results.append(
                    {
                        "metrics": {},
                        "trades": [],
                        "param_overrides": params,
                        "trade_count": 0,
                        "error": str(exc),
                    }
                )
    else:
        with ProcessPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(
                    _run_single_backtest,
                    base_dict,
                    params,
                    is_start,
                    is_end,
                    strategy_id,
                    strategy_config,
                    engine_mode,
                    fallback_to_legacy_on_error,
                ): params
                for params in param_grid
            }
            for future in as_completed(futures):
                params = futures[future]
                try:
                    all_results.append(future.result())
                except Exception as exc:
                    logger.error("IS backtest failed for params %s: %s", params, exc)
                    all_results.append(
                        {
                            "metrics": {},
                            "trades": [],
                            "param_overrides": params,
                            "trade_count": 0,
                            "error": str(exc),
                        }
                    )

    valid = [r for r in all_results if int(r.get("trade_count", 0) or 0) >= min_trades]
    if not valid:
        logger.warning(
            "No IS candidate met min_trades=%d for %s to %s. Falling back to base parameters.",
            min_trades,
            is_start.date(),
            is_end.date(),
        )
        return {}, {"metrics": {}, "param_overrides": {}}, all_results

    valid.sort(
        key=lambda r: _safe_float(r.get("metrics", {}).get(optimization_metric), fallback=-1e9),
        reverse=True,
    )
    best = valid[0]
    return dict(best.get("param_overrides", {})), best, all_results


def _build_stitched_trade_records(
    trades: List[Dict[str, Any]],
    initial_balance: float,
) -> List[TradeRecord]:
    """Convert serialized trades to TradeRecord and stitch balance continuously."""

    enriched: List[Tuple[str, str, Dict[str, Any]]] = []
    for trade in trades:
        exit_raw = str(trade.get("exit_time") or "")
        entry_raw = str(trade.get("entry_time") or "")
        if not exit_raw and not entry_raw:
            continue
        enriched.append((exit_raw or entry_raw, entry_raw or exit_raw, trade))

    enriched.sort(key=lambda item: (item[0], item[1]))

    records: List[TradeRecord] = []
    balance = float(initial_balance)
    trade_number = 0

    for _, _, trade in enriched:
        entry_time = _safe_dt(trade.get("entry_time"))
        exit_time = _safe_dt(trade.get("exit_time")) or entry_time
        if not entry_time or not exit_time:
            continue

        pnl = _safe_float(trade.get("profit_loss"), 0.0)
        balance_before = balance
        balance_after = balance_before + pnl
        trade_number += 1

        records.append(
            TradeRecord(
                trade_number=trade_number,
                direction=str(trade.get("direction") or "BUY"),
                entry_time=entry_time,
                exit_time=exit_time,
                entry_price=_safe_float(trade.get("entry_price"), 0.0),
                exit_price=_safe_float(trade.get("exit_price"), 0.0),
                stop_loss=_safe_float(trade.get("stop_loss"), 0.0),
                take_profit=_safe_float(trade.get("take_profit"), 0.0),
                lot_size=_safe_float(trade.get("lot_size"), 0.0),
                profit_loss=pnl,
                balance_before=balance_before,
                balance_after=balance_after,
                setup_type=trade.get("setup_type"),
                exit_reason=trade.get("exit_reason"),
                r_multiple=_safe_float(trade.get("r_multiple"), 0.0),
                gross_pnl=_safe_float(trade.get("gross_pnl"), pnl),
                spread_cost=_safe_float(trade.get("spread_cost"), 0.0),
                slippage_cost=_safe_float(trade.get("slippage_cost"), 0.0),
                commission_cost=_safe_float(trade.get("commission_cost"), 0.0),
                swap_cost=_safe_float(trade.get("swap_cost"), 0.0),
                entry_reason=trade.get("entry_reason"),
                ml_features=trade.get("ml_features"),
                max_favorable_excursion=_safe_float(trade.get("max_favorable_excursion"), 0.0),
                max_adverse_excursion=_safe_float(trade.get("max_adverse_excursion"), 0.0),
            )
        )
        balance = balance_after

    return records


class WalkForwardEngine:
    """Rolling IS optimize + OOS evaluate engine."""

    def __init__(self, config: WalkForwardConfig):
        self.config = config
        self.windows: List[WindowResult] = []
        self.param_grid_size: int = 0
        self.effective_engine_mode: str = (config.engine_mode or "legacy").strip().lower()
        self.parity_report: Optional[Dict[str, Any]] = None

    def run(self, progress_callback: Optional[Callable[[float, str], None]] = None) -> Dict[str, Any]:
        """Execute full walk-forward run."""

        windows = _generate_windows(
            self.config.base_config.start_date,
            self.config.base_config.end_date,
            self.config.in_sample_days,
            self.config.out_of_sample_days,
            self.config.step_days,
            self.config.base_config.timeframe,
        )
        param_grid = _resolve_param_grid(self.config)
        self.param_grid_size = len(param_grid)

        logger.info("Walk-forward windows: %d", len(windows))
        logger.info("Parameter combinations per IS window: %d", len(param_grid))

        if self.effective_engine_mode not in {"legacy", "advanced"}:
            self.effective_engine_mode = "legacy"

        if self.effective_engine_mode == "advanced" and self.config.parity_check:
            first_win = windows[0]
            base_dict = _config_to_dict(self.config.base_config)
            legacy_probe = _run_single_backtest(
                base_dict,
                {},
                first_win.is_start,
                first_win.is_end,
                self.config.strategy_id,
                self.config.strategy_config,
                engine_mode="legacy",
                fallback_to_legacy_on_error=True,
            )
            try:
                advanced_probe = _run_single_backtest(
                    base_dict,
                    {},
                    first_win.is_start,
                    first_win.is_end,
                    self.config.strategy_id,
                    self.config.strategy_config,
                    engine_mode="advanced",
                    fallback_to_legacy_on_error=False,
                )
            except Exception:
                if self.config.fallback_to_legacy_on_error:
                    self.parity_report = {
                        "passed": False,
                        "error": "advanced_probe_failed",
                    }
                    self.effective_engine_mode = "legacy"
                    advanced_probe = None
                else:
                    raise
            if advanced_probe is not None:
                self.parity_report = compare_engine_results(
                    legacy_probe,
                    advanced_probe,
                    tolerances=self.config.parity_tolerances,
                )
            if (
                self.parity_report is not None
                and self.config.require_parity_pass
                and not self.parity_report.get("passed", False)
            ):
                if self.config.fallback_to_legacy_on_error:
                    self.effective_engine_mode = "legacy"
                else:
                    raise ValueError("Walk-forward parity check failed and require_parity_pass=True")

        prev_best_params: Dict[str, Any] = {}

        for idx, win in enumerate(windows):
            if progress_callback:
                pct = (idx / max(1, len(windows))) * 100.0
                progress_callback(pct, f"Walk-forward window {idx + 1}/{len(windows)}")

            best_params, best_is_result, all_is_results = _optimize_in_sample(
                base_config=self.config.base_config,
                param_grid=param_grid,
                is_start=win.is_start,
                is_end=win.is_end,
                optimization_metric=self.config.optimization_metric,
                min_trades=self.config.min_trades_per_window,
                max_workers=self.config.max_workers,
                strategy_id=self.config.strategy_id,
                strategy_config=self.config.strategy_config,
                engine_mode=self.effective_engine_mode,
                fallback_to_legacy_on_error=self.config.fallback_to_legacy_on_error,
            )

            oos_result = _run_single_backtest(
                _config_to_dict(self.config.base_config),
                best_params,
                win.oos_start,
                win.oos_end,
                self.config.strategy_id,
                self.config.strategy_config,
                engine_mode=self.effective_engine_mode,
                fallback_to_legacy_on_error=self.config.fallback_to_legacy_on_error,
            )

            stability: Dict[str, Dict[str, Any]] = {}
            for name, value in best_params.items():
                old = prev_best_params.get(name)
                stability[name] = {"old": old, "new": value, "changed": old != value}

            self.windows.append(
                WindowResult(
                    window_id=win.window_id,
                    is_start=win.is_start,
                    is_end=win.is_end,
                    oos_start=win.oos_start,
                    oos_end=win.oos_end,
                    best_params=best_params,
                    is_metrics=best_is_result.get("metrics", {}),
                    oos_metrics=oos_result.get("metrics", {}),
                    oos_trades=oos_result.get("trades", []),
                    all_is_results=all_is_results,
                    param_stability=stability,
                )
            )

            prev_best_params = dict(best_params)

        report = self._compile_report()
        if progress_callback:
            progress_callback(100.0, "Walk-forward completed")
        return report

    def _compile_report(self) -> Dict[str, Any]:
        """Compile stitched OOS report and diagnostics."""

        all_oos_trades: List[Dict[str, Any]] = []
        for win in self.windows:
            for trade in win.oos_trades:
                row = dict(trade)
                row["window_id"] = win.window_id
                all_oos_trades.append(row)

        initial_balance = float(self.config.base_config.initial_balance)
        stitched_records = _build_stitched_trade_records(all_oos_trades, initial_balance)

        metrics_calc = MetricsCalculator(initial_balance=initial_balance)
        if stitched_records:
            equity_curve = [(stitched_records[0].entry_time, initial_balance)]
            for rec in stitched_records:
                equity_curve.append((rec.exit_time or rec.entry_time, rec.balance_after))
        else:
            equity_curve = [(self.config.base_config.start_date, initial_balance)]

        stitched_metrics = metrics_calc.calculate_all_metrics(stitched_records, equity_curve)
        oos_equity_curve = metrics_calc.generate_equity_curve(stitched_records)
        if not oos_equity_curve:
            oos_equity_curve = [
                {
                    "timestamp": self.config.base_config.start_date.isoformat(),
                    "equity": initial_balance,
                    "trade_number": 0,
                }
            ]

        daily_pnl = metrics_calc.calculate_daily_pnl(stitched_records)
        monthly_returns = metrics_calc.calculate_monthly_returns(stitched_records)

        is_metric_values = [
            _safe_float(w.is_metrics.get(self.config.optimization_metric), 0.0)
            for w in self.windows
        ]
        oos_metric_values = [
            _safe_float(w.oos_metrics.get(self.config.optimization_metric), 0.0)
            for w in self.windows
        ]
        avg_is_metric = float(np.mean(is_metric_values)) if is_metric_values else 0.0
        avg_oos_metric = float(np.mean(oos_metric_values)) if oos_metric_values else 0.0
        degradation_ratio = (avg_oos_metric / avg_is_metric) if avg_is_metric > 0 else 0.0

        param_change_counts: Dict[str, Dict[str, int]] = {}
        for w in self.windows:
            for param, info in w.param_stability.items():
                bucket = param_change_counts.setdefault(param, {"total": 0, "changes": 0})
                bucket["total"] += 1
                if info.get("changed"):
                    bucket["changes"] += 1

        param_stability_scores: Dict[str, float] = {}
        for param, counts in param_change_counts.items():
            total = max(1, counts["total"])
            stability = 1.0 - (counts["changes"] / total)
            param_stability_scores[param] = round(stability, 3)

        window_details: List[Dict[str, Any]] = []
        for w in self.windows:
            window_details.append(
                {
                    "window_id": w.window_id,
                    "is_period": f"{w.is_start.date()} to {w.is_end.date()}",
                    "oos_period": f"{w.oos_start.date()} to {w.oos_end.date()}",
                    "best_params": w.best_params,
                    "is_metric": _safe_float(w.is_metrics.get(self.config.optimization_metric), 0.0),
                    "oos_metric": _safe_float(w.oos_metrics.get(self.config.optimization_metric), 0.0),
                    "is_sharpe": _safe_float(w.is_metrics.get("sharpe_ratio"), 0.0),
                    "oos_sharpe": _safe_float(w.oos_metrics.get("sharpe_ratio"), 0.0),
                    "is_win_rate": _safe_float(w.is_metrics.get("win_rate"), 0.0),
                    "oos_win_rate": _safe_float(w.oos_metrics.get("win_rate"), 0.0),
                    "is_net_profit": _safe_float(w.is_metrics.get("net_profit"), 0.0),
                    "oos_net_profit": _safe_float(w.oos_metrics.get("net_profit"), 0.0),
                    "oos_trade_count": int(_safe_float(w.oos_metrics.get("total_trades"), 0.0)),
                }
            )

        verdict = self._generate_verdict(
            degradation_ratio=degradation_ratio,
            stitched_metrics=stitched_metrics,
            param_stability_scores=param_stability_scores,
            total_oos_trades=len(stitched_records),
        )

        return {
            "summary": {
                "total_windows": len(self.windows),
                "optimization_metric": self.config.optimization_metric,
                "param_grid_size": self.param_grid_size,
                "search_mode": self.config.search_mode,
                "requested_engine_mode": self.config.engine_mode,
                "effective_engine_mode": self.effective_engine_mode,
                "random_samples": self.config.random_samples,
                "avg_is_metric": round(avg_is_metric, 6),
                "avg_oos_metric": round(avg_oos_metric, 6),
                "degradation_ratio": round(degradation_ratio, 6),
                "total_oos_trades": len(stitched_records),
                "stitched_oos_pnl": round(_safe_float(stitched_metrics.get("net_profit"), 0.0), 2),
                "stitched_oos_sharpe": round(_safe_float(stitched_metrics.get("sharpe_ratio"), 0.0), 6),
                "stitched_oos_max_drawdown_pct": round(_safe_float(stitched_metrics.get("max_drawdown_percent"), 0.0), 2),
                "stitched_oos_win_rate": round(_safe_float(stitched_metrics.get("win_rate"), 0.0), 2),
                "param_stability_scores": param_stability_scores,
                "stitched_metrics": stitched_metrics,
                "parity_report": self.parity_report,
                "verdict": verdict,
            },
            "oos_equity_curve": oos_equity_curve,
            "oos_trades": [
                {
                    "trade_number": rec.trade_number,
                    "direction": rec.direction,
                    "entry_time": rec.entry_time.isoformat() if rec.entry_time else None,
                    "exit_time": rec.exit_time.isoformat() if rec.exit_time else None,
                    "entry_price": rec.entry_price,
                    "exit_price": rec.exit_price,
                    "stop_loss": rec.stop_loss,
                    "take_profit": rec.take_profit,
                    "lot_size": rec.lot_size,
                    "profit_loss": rec.profit_loss,
                    "r_multiple": rec.r_multiple,
                    "balance_before": rec.balance_before,
                    "balance_after": rec.balance_after,
                    "setup_type": rec.setup_type,
                    "exit_reason": rec.exit_reason,
                    "entry_reason": rec.entry_reason,
                    "gross_pnl": rec.gross_pnl,
                    "spread_cost": rec.spread_cost,
                    "slippage_cost": rec.slippage_cost,
                    "commission_cost": rec.commission_cost,
                    "swap_cost": rec.swap_cost,
                    "ml_features": rec.ml_features,
                    "max_favorable_excursion": rec.max_favorable_excursion,
                    "max_adverse_excursion": rec.max_adverse_excursion,
                }
                for rec in stitched_records
            ],
            "daily_pnl": daily_pnl,
            "monthly_returns": monthly_returns,
            "window_details": window_details,
        }

    def _generate_verdict(
        self,
        degradation_ratio: float,
        stitched_metrics: Dict[str, Any],
        param_stability_scores: Dict[str, float],
        total_oos_trades: int,
    ) -> Dict[str, Any]:
        """Generate pass/warn/fail verdict for allocation readiness."""

        checks: List[Tuple[str, str]] = []
        sharpe = _safe_float(stitched_metrics.get("sharpe_ratio"), 0.0)
        dd_pct = _safe_float(stitched_metrics.get("max_drawdown_percent"), 0.0)

        if degradation_ratio >= 0.5:
            checks.append(("PASS", f"IS→OOS degradation ratio {degradation_ratio:.2f} >= 0.50"))
        elif degradation_ratio >= 0.3:
            checks.append(("WARN", f"IS→OOS degradation ratio {degradation_ratio:.2f} is marginal"))
        else:
            checks.append(("FAIL", f"IS→OOS degradation ratio {degradation_ratio:.2f} < 0.30"))

        if sharpe >= 1.0:
            checks.append(("PASS", f"Stitched OOS Sharpe {sharpe:.2f} >= 1.00"))
        elif sharpe >= 0.5:
            checks.append(("WARN", f"Stitched OOS Sharpe {sharpe:.2f} is marginal"))
        else:
            checks.append(("FAIL", f"Stitched OOS Sharpe {sharpe:.2f} < 0.50"))

        if dd_pct <= 15.0:
            checks.append(("PASS", f"Stitched OOS max drawdown {dd_pct:.1f}% <= 15%"))
        elif dd_pct <= 25.0:
            checks.append(("WARN", f"Stitched OOS max drawdown {dd_pct:.1f}% is elevated"))
        else:
            checks.append(("FAIL", f"Stitched OOS max drawdown {dd_pct:.1f}% > 25%"))

        if total_oos_trades >= 100:
            checks.append(("PASS", f"{total_oos_trades} OOS trades (statistically solid)"))
        elif total_oos_trades >= 50:
            checks.append(("WARN", f"{total_oos_trades} OOS trades (marginal sample size)"))
        else:
            checks.append(("FAIL", f"{total_oos_trades} OOS trades (insufficient sample size)"))

        unstable = [name for name, score in param_stability_scores.items() if score < 0.5]
        if not unstable:
            checks.append(("PASS", "Parameters are stable across windows"))
        else:
            checks.append(("WARN", f"Unstable parameters: {unstable}"))

        fail_count = sum(1 for status, _ in checks if status == "FAIL")
        warn_count = sum(1 for status, _ in checks if status == "WARN")

        if fail_count > 0:
            overall = "FAIL - DO NOT ALLOCATE CAPITAL"
        elif warn_count >= 2:
            overall = "CONDITIONAL - PAPER TRADE BEFORE ALLOCATION"
        else:
            overall = "PASS - PROCEED TO PAPER TRADING"

        return {
            "overall": overall,
            "checks": [{"status": status, "detail": detail} for status, detail in checks],
        }
