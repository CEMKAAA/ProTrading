"""
Phase 0/1 Validator

Implements:
- Phase 0 baseline freeze
- Purged walk-forward ON/OFF comparison
- Block-bootstrap Monte Carlo robustness checks
- Hard-gate pass/fail decisions
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, fields
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple
import json
import logging

import numpy as np

from .advanced_backtest_engine import AdvancedEventBacktestEngine
from .advanced_ml_backtest_engine import AdvancedEventMLBacktestEngine
from .backtest_engine import BacktestConfig, BacktestEngine
from .ml_backtest_engine import MLBacktestConfig, MLBacktestEngine
from .parity_tools import compare_engine_results
from .strategies.factory import create_strategy

logger = logging.getLogger(__name__)


@dataclass
class Phase01GateConfig:
    # Walk-forward
    wf_folds: int = 6
    wf_test_days: int = 30
    wf_purge_days: int = 2

    # Monte Carlo
    mc_iterations: int = 1000
    mc_block_size: int = 5
    mc_seed: int = 42

    # Hard gates
    min_dd_improvement_pct: float = 0.0          # require non-worse DD by default
    min_expectancy_retention_ratio: float = 0.9  # keep >=90% of expectancy
    min_trade_retention_ratio: float = 0.6       # keep >=60% of trade count
    max_wf_folds_with_negative_delta: int = 3
    require_regime_activation_on: bool = True
    min_regime_coverage_ratio: float = 0.90
    engine_mode: str = "legacy"  # legacy | advanced
    fallback_to_legacy_on_error: bool = True
    parity_check: bool = False
    require_parity_pass: bool = False
    parity_tolerances: Dict[str, float] = None


class Phase01Validator:
    def __init__(self, data_dir: Path | None = None):
        root = Path(__file__).resolve().parent.parent.parent  # dashboard
        self.data_dir = data_dir or (root / "data")
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.baseline_file = self.data_dir / "phase01_baseline.json"

    @staticmethod
    def _to_backtest_config(
        base_cfg: Dict[str, Any],
        enable_regime: bool,
        is_ml_strategy: bool = False,
    ) -> BacktestConfig:
        target_cls = MLBacktestConfig if is_ml_strategy else BacktestConfig
        valid_fields = {f.name for f in fields(target_cls)}
        kwargs = {k: v for k, v in base_cfg.items() if k in valid_fields}
        kwargs["enable_cross_asset_filter"] = bool(enable_regime)
        return target_cls(**kwargs)

    @staticmethod
    def _run_engine_once(
        strategy_id: str,
        strategy_cfg: Dict[str, Any],
        config_obj: BacktestConfig,
        engine_mode: str,
    ) -> Dict[str, Any]:
        mode = (engine_mode or "legacy").strip().lower()
        if mode not in {"legacy", "advanced"}:
            mode = "legacy"
        is_ml = str(strategy_id).endswith("_ml_strategy")
        strategy = create_strategy(strategy_id, strategy_cfg)

        if is_ml:
            if mode == "advanced":
                engine = AdvancedEventMLBacktestEngine(config_obj, strategy=strategy)
                return engine.run(progress_callback=None, enable_event_trace=False)
            engine = MLBacktestEngine(config_obj, strategy=strategy)
            return engine.run()

        if mode == "advanced":
            engine = AdvancedEventBacktestEngine(config_obj, strategy=strategy)
            return engine.run(progress_callback=None, enable_event_trace=False)
        engine = BacktestEngine(config_obj, strategy=strategy)
        return engine.run()

    @staticmethod
    def _extract_core_metrics(results: Dict[str, Any]) -> Dict[str, float]:
        m = results.get("metrics", {})
        return {
            "total_trades": float(m.get("total_trades", 0.0)),
            "max_drawdown_percent": float(m.get("max_drawdown_percent", 0.0)),
            "expectancy": float(m.get("expectancy", 0.0)),
            "net_profit": float(m.get("net_profit", 0.0)),
            "sharpe_ratio": float(m.get("sharpe_ratio", 0.0)),
            "avg_slippage_cost": float(m.get("total_slippage_cost", 0.0)) / max(1.0, float(m.get("total_trades", 0.0))),
        }

    @staticmethod
    def _delta(on: Dict[str, float], off: Dict[str, float]) -> Dict[str, float]:
        return {
            "trades_delta": on["total_trades"] - off["total_trades"],
            "drawdown_pct_delta": on["max_drawdown_percent"] - off["max_drawdown_percent"],
            "expectancy_delta": on["expectancy"] - off["expectancy"],
            "net_profit_delta": on["net_profit"] - off["net_profit"],
            "sharpe_delta": on["sharpe_ratio"] - off["sharpe_ratio"],
        }

    def freeze_baseline(self, strategy_id: str, preset_name: str, config_snapshot: Dict[str, Any], metrics_off: Dict[str, float]):
        safe_snapshot: Dict[str, Any] = {}
        for k, v in config_snapshot.items():
            if isinstance(v, datetime):
                safe_snapshot[k] = v.isoformat()
            elif isinstance(v, (str, int, float, bool)) or v is None:
                safe_snapshot[k] = v
            else:
                safe_snapshot[k] = str(v)

        payload = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "strategy_id": strategy_id,
            "preset_name": preset_name,
            "config_snapshot": safe_snapshot,
            "baseline_off_metrics": metrics_off,
        }
        self.baseline_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return payload

    @staticmethod
    def _build_walkforward_windows(
        start: datetime,
        end: datetime,
        folds: int,
        test_days: int,
        purge_days: int,
    ) -> List[Tuple[datetime, datetime]]:
        windows: List[Tuple[datetime, datetime]] = []
        cursor_end = end
        for _ in range(folds):
            test_start = cursor_end - timedelta(days=test_days)
            if test_start <= start:
                break
            windows.append((test_start, cursor_end))
            cursor_end = test_start - timedelta(days=purge_days)
            if cursor_end <= start:
                break
        windows.reverse()
        return windows

    @staticmethod
    def _block_bootstrap_drawdown(
        trade_pnls: List[float],
        initial_balance: float,
        iterations: int,
        block_size: int,
        seed: int,
    ) -> Dict[str, float]:
        if not trade_pnls:
            return {"p95_drawdown_percent": 0.0, "p99_drawdown_percent": 0.0, "median_drawdown_percent": 0.0}

        rng = np.random.default_rng(seed)
        pnl = np.array(trade_pnls, dtype=float)
        n = len(pnl)
        block = max(1, min(block_size, n))
        dd_values = []

        for _ in range(iterations):
            sampled = []
            while len(sampled) < n:
                i = int(rng.integers(0, n))
                sampled.extend(pnl[i:i + block].tolist())
            sampled = sampled[:n]

            equity = initial_balance
            peak = initial_balance
            max_dd_pct = 0.0
            for x in sampled:
                equity += x
                if equity > peak:
                    peak = equity
                dd = max(0.0, peak - equity)
                dd_pct = (dd / peak * 100.0) if peak > 0 else 0.0
                if dd_pct > max_dd_pct:
                    max_dd_pct = dd_pct
            dd_values.append(max_dd_pct)

        arr = np.array(dd_values, dtype=float)
        return {
            "p95_drawdown_percent": float(np.percentile(arr, 95)),
            "p99_drawdown_percent": float(np.percentile(arr, 99)),
            "median_drawdown_percent": float(np.percentile(arr, 50)),
        }

    def run_phase01(
        self,
        strategy_id: str,
        preset_name: str,
        strategy_config: Dict[str, Any],
        gate_cfg: Phase01GateConfig | None = None,
    ) -> Dict[str, Any]:
        gate = gate_cfg or Phase01GateConfig()
        cfg = dict(strategy_config)
        start = cfg["start_date"]
        end = cfg["end_date"]
        initial_balance = float(cfg.get("initial_balance", 10000.0))
        is_ml_strategy = str(strategy_id).endswith("_ml_strategy")
        requested_engine_mode = (gate.engine_mode or "legacy").strip().lower()
        if requested_engine_mode not in {"legacy", "advanced"}:
            requested_engine_mode = "legacy"
        effective_engine_mode = requested_engine_mode

        def run_with_mode(config_dict: Dict[str, Any], enable_regime: bool):
            config_obj = self._to_backtest_config(
                config_dict,
                enable_regime=enable_regime,
                is_ml_strategy=is_ml_strategy,
            )
            used_mode = requested_engine_mode
            try:
                results = self._run_engine_once(
                    strategy_id=strategy_id,
                    strategy_cfg=config_dict,
                    config_obj=config_obj,
                    engine_mode=requested_engine_mode,
                )
            except Exception:
                if requested_engine_mode == "advanced" and gate.fallback_to_legacy_on_error:
                    results = self._run_engine_once(
                        strategy_id=strategy_id,
                        strategy_cfg=config_dict,
                        config_obj=config_obj,
                        engine_mode="legacy",
                    )
                    used_mode = "legacy_fallback_on_error"
                else:
                    raise
            return results, used_mode

        off_results, off_mode_used = run_with_mode(cfg, enable_regime=False)
        on_results, on_mode_used = run_with_mode(cfg, enable_regime=True)

        parity_report = None
        if gate.parity_check and requested_engine_mode == "advanced":
            legacy_off = self._run_engine_once(
                strategy_id=strategy_id,
                strategy_cfg=cfg,
                config_obj=self._to_backtest_config(cfg, enable_regime=False, is_ml_strategy=is_ml_strategy),
                engine_mode="legacy",
            )
            legacy_on = self._run_engine_once(
                strategy_id=strategy_id,
                strategy_cfg=cfg,
                config_obj=self._to_backtest_config(cfg, enable_regime=True, is_ml_strategy=is_ml_strategy),
                engine_mode="legacy",
            )
            parity_off = compare_engine_results(
                legacy_off,
                off_results,
                tolerances=gate.parity_tolerances or {},
            )
            parity_on = compare_engine_results(
                legacy_on,
                on_results,
                tolerances=gate.parity_tolerances or {},
            )
            parity_report = {
                "off": parity_off,
                "on": parity_on,
                "passed": bool(parity_off.get("passed") and parity_on.get("passed")),
            }
            if gate.require_parity_pass and not parity_report["passed"]:
                if gate.fallback_to_legacy_on_error:
                    off_results = legacy_off
                    on_results = legacy_on
                    off_mode_used = "legacy_fallback_on_parity"
                    on_mode_used = "legacy_fallback_on_parity"
                    effective_engine_mode = "legacy"
                else:
                    raise ValueError("Phase01 parity check failed and require_parity_pass=True")

        off_m = self._extract_core_metrics(off_results)
        on_m = self._extract_core_metrics(on_results)
        delta = self._delta(on_m, off_m)

        baseline = self.freeze_baseline(strategy_id, preset_name, strategy_config, off_m)

        # Purged walk-forward comparison
        wf_windows = self._build_walkforward_windows(
            start=start,
            end=end,
            folds=gate.wf_folds,
            test_days=gate.wf_test_days,
            purge_days=gate.wf_purge_days,
        )
        wf_rows = []
        negative_delta_folds = 0
        invalid_regime_folds = 0
        for i, (w_start, w_end) in enumerate(wf_windows, start=1):
            fold_cfg = dict(cfg)
            fold_cfg["start_date"] = w_start
            fold_cfg["end_date"] = w_end

            fold_off, fold_off_mode_used = run_with_mode(fold_cfg, enable_regime=False)
            fold_on, fold_on_mode_used = run_with_mode(fold_cfg, enable_regime=True)
            fm_off = self._extract_core_metrics(fold_off)
            fm_on = self._extract_core_metrics(fold_on)
            d = self._delta(fm_on, fm_off)
            fold_regime = fold_on.get("regime_analysis") or {}
            fold_regime_enabled = bool(fold_regime.get("enabled", False))
            fold_regime_coverage = float(fold_regime.get("coverage_ratio", 0.0) or 0.0)
            if gate.require_regime_activation_on and (not fold_regime_enabled or fold_regime_coverage < gate.min_regime_coverage_ratio):
                invalid_regime_folds += 1

            if d["net_profit_delta"] < 0 and d["drawdown_pct_delta"] > 0:
                negative_delta_folds += 1

            wf_rows.append(
                {
                    "fold": i,
                    "start": w_start.isoformat(),
                    "end": w_end.isoformat(),
                    "off": fm_off,
                    "on": fm_on,
                    "engine_mode_off": fold_off_mode_used,
                    "engine_mode_on": fold_on_mode_used,
                    "regime_enabled_on": fold_regime_enabled,
                    "regime_coverage_on": fold_regime_coverage,
                    "delta": d,
                }
            )

        # Block-bootstrap Monte Carlo
        off_trade_pnls = [float(t.get("profit_loss", 0.0)) for t in off_results.get("trades", [])]
        on_trade_pnls = [float(t.get("profit_loss", 0.0)) for t in on_results.get("trades", [])]
        mc_off = self._block_bootstrap_drawdown(
            off_trade_pnls, initial_balance, gate.mc_iterations, gate.mc_block_size, gate.mc_seed
        )
        mc_on = self._block_bootstrap_drawdown(
            on_trade_pnls, initial_balance, gate.mc_iterations, gate.mc_block_size, gate.mc_seed
        )

        # Hard gates
        dd_improvement = off_m["max_drawdown_percent"] - on_m["max_drawdown_percent"]
        expectancy_ratio = (on_m["expectancy"] / off_m["expectancy"]) if abs(off_m["expectancy"]) > 1e-9 else 1.0
        trade_ratio = (on_m["total_trades"] / off_m["total_trades"]) if off_m["total_trades"] > 0 else 1.0

        regime_on = on_results.get("regime_analysis") or {}
        regime_enabled_on = bool(regime_on.get("enabled", False))
        regime_coverage_on = float(regime_on.get("coverage_ratio", 0.0) or 0.0)
        regime_active_ok = (
            (not gate.require_regime_activation_on)
            or (regime_enabled_on and regime_coverage_on >= gate.min_regime_coverage_ratio)
        )

        gates = {
            "regime_activation_valid": regime_active_ok,
            "dd_not_worse": dd_improvement >= gate.min_dd_improvement_pct,
            "expectancy_retained": expectancy_ratio >= gate.min_expectancy_retention_ratio,
            "trade_count_retained": trade_ratio >= gate.min_trade_retention_ratio,
            "wf_negative_folds_ok": negative_delta_folds <= gate.max_wf_folds_with_negative_delta,
            "wf_regime_valid": invalid_regime_folds == 0,
            "mc_p95_drawdown_not_worse": mc_on["p95_drawdown_percent"] <= mc_off["p95_drawdown_percent"],
        }
        phase1_pass = all(gates.values())

        return {
            "phase0": {
                "baseline_frozen": True,
                "baseline_file": str(self.baseline_file),
                "baseline": baseline,
                "evaluation_method": {
                    "walk_forward": {
                        "type": "purged",
                        "folds": gate.wf_folds,
                        "test_days": gate.wf_test_days,
                        "purge_days": gate.wf_purge_days,
                        "engine_mode_requested": requested_engine_mode,
                        "engine_mode_effective": effective_engine_mode,
                    },
                    "monte_carlo": {
                        "type": "block_bootstrap",
                        "iterations": gate.mc_iterations,
                        "block_size": gate.mc_block_size,
                    },
                    "full_cost_model": True,
                },
            },
            "phase1": {
                "single_run_off": off_m,
                "single_run_on": on_m,
                "single_run_engine_mode_off": off_mode_used,
                "single_run_engine_mode_on": on_mode_used,
                "parity_report": parity_report,
                "single_run_delta": delta,
                "regime_analysis_on": on_results.get("regime_analysis"),
                "walk_forward_rows": wf_rows,
                "monte_carlo": {"off": mc_off, "on": mc_on},
                "hard_gates": gates,
                "pass": phase1_pass,
                "diagnostics": {
                    "dd_improvement_pct": dd_improvement,
                    "expectancy_ratio": expectancy_ratio,
                    "trade_ratio": trade_ratio,
                    "wf_negative_folds": negative_delta_folds,
                    "regime_enabled_on": regime_enabled_on,
                    "regime_coverage_on": regime_coverage_on,
                    "wf_invalid_regime_folds": invalid_regime_folds,
                },
            },
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        }
