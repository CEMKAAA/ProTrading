"""
Long-running deploy campaign for strategy validation and tuning.

Goals:
- Run baseline deploy presets
- Sweep available presets per strategy
- Apply targeted parameter override variants for failing cases
- Stop tuning a case once it meets strict criteria
- Persist checkpoints so campaign can run for many hours

Usage:
    python -u scripts/run_deploy_campaign.py
    python -u scripts/run_deploy_campaign.py --max-override-runs 20 --only earnings_volatility_strategy
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from dashboard.backend.core.backtest_engine import BacktestEngine
from dashboard.backend.core.config_builder import build_config_from_preset
from dashboard.backend.core.instrument_specs import get_instrument
from dashboard.backend.core.strategies.factory import create_strategy
from dashboard.backend.core.strategy_registry import StrategyRegistry


RESULTS_DIR = PROJECT_ROOT / "scripts" / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)

EARNINGS_SRC_DIR = PROJECT_ROOT / "data" / "historical"
BACKEND_CSV_DIR = PROJECT_ROOT / "dashboard" / "data" / "historical"
BACKEND_CSV_DIR.mkdir(parents=True, exist_ok=True)


CRITERIA = {
    "max_drawdown_pct_lt": 15.0,
    "sharpe_gt": 1.0,
    "profit_factor_gt": 1.3,
    "win_rate_gt": 40.0,
    "net_profit_gt": 5000.0,
}


@dataclass
class Scenario:
    name: str
    strategy_id: str
    seed_preset: str
    symbol: str
    timeframe: str
    start: str
    end: str
    csv_file: Optional[str] = None  # Optional explicit CSV filename in dashboard/data/historical


def _now() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def _parse_dt(s: str) -> datetime:
    return datetime.strptime(s, "%Y-%m-%d")


def _pass_fail(metrics: Dict[str, Any]) -> tuple[bool, List[str]]:
    reasons: List[str] = []
    if float(metrics.get("max_drawdown_pct", 1e9)) >= CRITERIA["max_drawdown_pct_lt"]:
        reasons.append(f"DD {metrics.get('max_drawdown_pct', 0):.2f}% >= {CRITERIA['max_drawdown_pct_lt']:.2f}%")
    if float(metrics.get("sharpe_ratio", -1e9)) <= CRITERIA["sharpe_gt"]:
        reasons.append(f"Sharpe {metrics.get('sharpe_ratio', 0):.3f} <= {CRITERIA['sharpe_gt']:.3f}")
    if float(metrics.get("profit_factor", -1e9)) <= CRITERIA["profit_factor_gt"]:
        reasons.append(f"PF {metrics.get('profit_factor', 0):.3f} <= {CRITERIA['profit_factor_gt']:.3f}")
    if float(metrics.get("win_rate", -1e9)) <= CRITERIA["win_rate_gt"]:
        reasons.append(f"WR {metrics.get('win_rate', 0):.2f}% <= {CRITERIA['win_rate_gt']:.2f}%")
    if float(metrics.get("net_profit", -1e9)) <= CRITERIA["net_profit_gt"]:
        reasons.append(f"Net ${metrics.get('net_profit', 0):.2f} <= ${CRITERIA['net_profit_gt']:.2f}")
    return len(reasons) == 0, reasons


def _score(metrics: Dict[str, Any]) -> float:
    """Higher is better; rewards criteria alignment and profitability."""
    if metrics.get("strategy_id") == "earnings_volatility_strategy":
        # Earnings campaign priority: Sharpe + drawdown quality first, then net.
        dd = float(metrics.get("max_drawdown_pct", 999))
        sharpe = float(metrics.get("sharpe_ratio", -999))
        pf = float(metrics.get("profit_factor", -999))
        net = float(metrics.get("net_profit", -1e9))
        wr = float(metrics.get("win_rate", -999))
        trades = float(metrics.get("total_trades", 0))
        score = 0.0
        score += sharpe * 4.0
        score += pf * 2.0
        score += net / 2000.0
        score += max(0.0, wr - 40.0) * 0.03
        score += min(trades, 100) * 0.02
        score -= max(0.0, dd - 15.0) * 1.2
        return score

    dd = float(metrics.get("max_drawdown_pct", 999))
    sharpe = float(metrics.get("sharpe_ratio", -999))
    pf = float(metrics.get("profit_factor", -999))
    wr = float(metrics.get("win_rate", -999))
    net = float(metrics.get("net_profit", -1e9))
    trades = float(metrics.get("total_trades", 0))
    score = 0.0
    score += net / 1000.0
    score += sharpe * 2.0
    score += pf * 1.5
    score += (wr - 40.0) * 0.05
    score += min(trades, 200) * 0.01
    score -= max(0.0, dd - 15.0) * 0.5
    return score


def _is_better_result(candidate: Dict[str, Any], incumbent: Optional[Dict[str, Any]]) -> bool:
    """Return True if candidate should replace incumbent as scenario best."""
    if incumbent is None:
        return True
    c_pass = bool(candidate.get("passed", False))
    i_pass = bool(incumbent.get("passed", False))
    if c_pass != i_pass:
        return c_pass  # Always prefer PASS over FAIL.

    # If both same pass/fail class, compare score then net as tiebreak.
    c_score = float(candidate.get("score", -1e9))
    i_score = float(incumbent.get("score", -1e9))
    if c_score != i_score:
        return c_score > i_score
    return float(candidate.get("net_profit", -1e9)) > float(incumbent.get("net_profit", -1e9))


def _mirror_earnings_csvs() -> int:
    """Mirror top-level earnings CSVs into backend csv dir used by HistoricalDataProvider."""
    count = 0
    for src in sorted(EARNINGS_SRC_DIR.glob("*_earnings.csv")):
        dst = BACKEND_CSV_DIR / src.name
        if not dst.exists() or src.stat().st_mtime > dst.stat().st_mtime:
            shutil.copy2(src, dst)
            count += 1
    return count


def _available_presets(strategy_id: str, symbol: str) -> List[str]:
    s = StrategyRegistry.get_strategy(strategy_id)
    if not s:
        return []
    out = []
    for p in s.presets:
        if p.symbols and symbol not in p.symbols:
            continue
        out.append(p.id)
    return out


def _run_once(
    scenario: Scenario,
    preset_id: str,
    overrides: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    start_date = _parse_dt(scenario.start)
    end_date = _parse_dt(scenario.end)
    csv_files = [scenario.csv_file] if scenario.csv_file else None

    config, preset_cfg = build_config_from_preset(
        strategy_id=scenario.strategy_id,
        preset_id=preset_id,
        symbol=scenario.symbol,
        timeframe=scenario.timeframe,
        start_date=start_date,
        end_date=end_date,
        initial_balance=10000.0,
        data_source="csv_only",
        csv_files=csv_files,
        overrides=overrides or None,
    )

    strategy_cfg = dict(preset_cfg)
    if overrides:
        strategy_cfg.update({k: v for k, v in overrides.items() if v is not None})
    strategy_cfg["symbol"] = scenario.symbol
    strategy_cfg["_instrument"] = get_instrument(scenario.symbol)

    strategy = create_strategy(scenario.strategy_id, strategy_cfg)
    engine = BacktestEngine(config, strategy=strategy)

    progress_state = {"last_pct": -1}

    def progress_cb(progress: float, message: str) -> None:
        pct = int(progress)
        # Print at ~5% steps and always at completion.
        if pct >= progress_state["last_pct"] + 5 or pct >= 100:
            print(f"    [progress] {pct:3d}% | {message}", flush=True)
            progress_state["last_pct"] = pct

    t0 = time.time()
    result = engine.run(progress_callback=progress_cb)
    elapsed = time.time() - t0
    m = result.get("metrics", {})
    ms = result.get("microstructure_analysis") or {}
    metrics = {
        "strategy_id": scenario.strategy_id,
        "preset": preset_id,
        "scenario_name": scenario.name,
        "symbol": scenario.symbol,
        "timeframe": scenario.timeframe,
        "period": f"{scenario.start} to {scenario.end}",
        "elapsed_sec": round(elapsed, 2),
        "total_trades": float(m.get("total_trades", 0)),
        "win_rate": float(m.get("win_rate", 0)),
        "profit_factor": float(m.get("profit_factor", 0)),
        "sharpe_ratio": float(m.get("sharpe_ratio", 0)),
        "max_drawdown_pct": float(m.get("max_drawdown_percent", 0)),
        "net_profit": float(m.get("net_profit", 0)),
        "final_balance": float(m.get("final_balance", 0)),
        "data_hash": result.get("data_hash"),
        "engine_status": str(result.get("status", "")),
        "engine_error": str(result.get("error_message", "")),
        "micro_trade_count": float(ms.get("trade_count", 0)),
        "micro_avg_fill_probability": float(ms.get("avg_fill_probability", 0.0)),
        "micro_total_impact_usd": float(ms.get("total_impact_usd", 0.0)),
    }
    passed, fail_reasons = _pass_fail(metrics)
    metrics["passed"] = passed
    metrics["fail_reasons"] = fail_reasons
    metrics["score"] = _score(metrics)
    return metrics


def _override_variants(strategy_id: str) -> List[Dict[str, Any]]:
    """
    Targeted override search space per strategy.
    Ordered roughly from conservative risk control to profit expansion.
    """
    if strategy_id in {"orb_strategy", "advanced_orb_strategy"}:
        return [
            # Profit scaling: MUST match daily loss limit to risk. At 0.5% risk on $10k = $50/trade.
            # A single loss must not trigger daily stop-out.
            {"risk_percent": 0.75, "max_daily_loss_usd": -120.0, "max_total_risk_usd": 150.0},
            {"risk_percent": 1.0, "max_daily_loss_usd": -160.0, "max_total_risk_usd": 200.0},
            {"risk_percent": 1.25, "max_daily_loss_usd": -200.0, "max_total_risk_usd": 250.0},
            # FVG-optional threshold tuning
            {"fvg_optional_threshold": 60},
            {"fvg_optional_threshold": 65},
            {"fvg_optional_threshold": 70},
            {"fvg_optional_threshold": None},  # Disable FVG-optional
            # Bias tuning
            {"bias_min_strength": 35},
            {"bias_min_strength": 50},
            # Allow 2nd trade after first win (more trades on strong days)
            {"stop_after_first_win": False, "max_daily_trades": 3},
            # Combined: higher risk + FVG-optional
            {"risk_percent": 0.75, "max_daily_loss_usd": -120.0, "fvg_optional_threshold": 65},
            {"risk_percent": 1.0, "max_daily_loss_usd": -160.0, "fvg_optional_threshold": 65},
            # Quality relaxation: slightly easier displacement
            {"displacement_percentile": 80, "max_opposing_wick_ratio": 0.30},
        ]
    if strategy_id == "liquidity_sweep_strategy":
        return [
            # Risk scaling
            {"risk_percent": 1.0},
            {"risk_percent": 1.25},
            {"risk_percent": 1.5},
            # Trade frequency
            {"max_daily_trades": 3},
            {"max_daily_trades": 4},
            # Sweep sensitivity: shallower penetration → more sweeps detected
            {"sweep_min_penetration_atr": 0.2, "min_rr_ratio": 2.5},
            {"sweep_min_penetration_atr": 0.25, "min_rr_ratio": 2.8},
            # Rejection quality: lower percentile → more entries
            {"rejection_body_percentile": 50},
            {"rejection_body_percentile": 55},
            # FVG gate: disable to catch sweeps without FVG confirmation
            {"require_fvg_after_sweep": False, "rejection_body_percentile": 65},
            # Combined profit scaling
            {"risk_percent": 1.25, "max_daily_trades": 3, "sweep_min_penetration_atr": 0.25},
            {"risk_percent": 1.0, "require_fvg_after_sweep": False, "rejection_body_percentile": 60},
        ]
    if strategy_id == "keltner_breakout_strategy":
        return [
            # Risk scaling
            {"risk_percent": 1.5},
            {"risk_percent": 1.75},
            {"risk_percent": 2.0},
            # Trade frequency
            {"max_daily_trades": 3},
            {"max_daily_trades": 4},
            # ADX threshold: lower → more setups
            {"min_adx": 15},
            {"min_adx": 18},
            # Squeeze lookback: wider → catches more squeeze events
            {"squeeze_lookback": 10},
            {"squeeze_lookback": 12},
            # R:R tuning
            {"rr_ratio": 2.0},
            {"rr_ratio": 3.0},
            # Combined: scaled risk + relaxed filters
            {"risk_percent": 1.5, "min_adx": 18, "squeeze_lookback": 10},
            {"risk_percent": 1.75, "max_daily_trades": 3, "squeeze_lookback": 10},
        ]
    if strategy_id == "earnings_volatility_strategy":
        return [
            # --- Risk scaling (primary lever for net profit with fixed trade count) ---
            {"vol_structure": "long_calendar", "risk_percent": 8.0},
            {"vol_structure": "long_calendar", "risk_percent": 10.0},
            {"vol_structure": "long_calendar", "risk_percent": 12.0},
            {"vol_structure": "long_calendar", "risk_percent": 15.0},
            # --- Edge portfolio (best pooled config from prior campaign) ---
            {
                "vol_structure": "long_calendar",
                "risk_percent": 8.0,
                "term_structure_max_slope": -0.04,
                "min_avg_volume30": 4_000_000,
                "min_iv30_rv30_ratio": 1.18,
                "move_penalty_mult": 0.9,
                "breach_penalty_mult": 2.3,
            },
            # --- Edge portfolio at higher risk ---
            {
                "vol_structure": "long_calendar",
                "risk_percent": 12.0,
                "term_structure_max_slope": -0.04,
                "min_avg_volume30": 4_000_000,
                "min_iv30_rv30_ratio": 1.18,
                "move_penalty_mult": 0.9,
                "breach_penalty_mult": 2.3,
            },
            {
                "vol_structure": "long_calendar",
                "risk_percent": 15.0,
                "term_structure_max_slope": -0.04,
                "min_avg_volume30": 4_000_000,
                "min_iv30_rv30_ratio": 1.18,
                "move_penalty_mult": 0.9,
                "breach_penalty_mult": 2.3,
            },
            # --- Alpha filter relaxation (more trade opportunities) ---
            {"term_structure_max_slope": -0.03, "min_avg_volume30": 3_000_000, "min_iv30_rv30_ratio": 1.10},
            {"term_structure_max_slope": -0.04, "min_avg_volume30": 4_000_000, "min_iv30_rv30_ratio": 1.18},
            # --- Combined: loose filters + high risk ---
            {
                "risk_percent": 15.0,
                "term_structure_max_slope": -0.03,
                "min_avg_volume30": 3_000_000,
                "min_iv30_rv30_ratio": 1.10,
                "move_penalty_mult": 0.9,
                "breach_penalty_mult": 2.3,
            },
            # --- Penalty tuning ---
            {"move_penalty_mult": 0.8, "breach_penalty_mult": 2.0},
            {"move_penalty_mult": 0.9, "breach_penalty_mult": 2.3},
            # --- Straddle variant ---
            {"vol_structure": "short_straddle", "risk_percent": 4.0, "min_avg_volume30": 5_000_000, "min_iv30_rv30_ratio": 1.20},
        ]
    if strategy_id == "b_profile_reversion_strategy":
        return [
            # --- Tier 1: Profile relaxation (b-shape is the #1 blocker at 75%) ---
            {"min_b_shape_score": 0.50, "min_lower_distribution_share": 0.52, "max_upper_tail_share": 0.28},
            {"min_b_shape_score": 0.45, "min_lower_distribution_share": 0.48, "max_upper_tail_share": 0.32},
            {"min_b_shape_score": 0.42, "min_lower_distribution_share": 0.45, "max_upper_tail_share": 0.35},
            # --- Tier 2: Entry geometry relaxation (breakout+reentry in same bar is very rare) ---
            {"breakout_buffer_atr": 0.04, "reentry_buffer_atr": 0.01},
            {"breakout_buffer_atr": 0.02, "reentry_buffer_atr": 0.0},
            {"breakout_buffer_atr": 0.0, "reentry_buffer_atr": 0.0},
            # --- Tier 3: Bearish pressure relaxation ---
            {"min_bear_body_atr": 0.08, "max_close_to_low_ratio": 0.52, "min_upper_wick_ratio": 0.12},
            {"min_bear_body_atr": 0.05, "max_close_to_low_ratio": 0.58, "min_upper_wick_ratio": 0.08},
            # --- Tier 4: R:R reduction (4.5x target kills setups where VAL is close) ---
            {"min_rr_ratio": 3.0, "stretch_rr_ratio": 4.5},
            {"min_rr_ratio": 2.5, "stretch_rr_ratio": 3.5},
            # --- Tier 5: Session window expansion ---
            {"trade_end_time": "15:00"},
            {"trade_start_time": "09:30", "trade_end_time": "15:30"},
            # --- Tier 6: Constituent mode ---
            {"constituent_confirmation_mode": "auto"},
            {"constituent_confirmation_mode": "off"},
            # --- Tier 7: Combined moderate relaxation (~15 trades expected) ---
            {
                "min_b_shape_score": 0.48,
                "min_lower_distribution_share": 0.50,
                "max_upper_tail_share": 0.30,
                "breakout_buffer_atr": 0.04,
                "reentry_buffer_atr": 0.01,
                "min_rr_ratio": 3.0,
                "stretch_rr_ratio": 4.5,
                "constituent_confirmation_mode": "auto",
            },
            # --- Tier 8: Combined aggressive relaxation (~30-40 trades expected) ---
            {
                "min_b_shape_score": 0.42,
                "min_lower_distribution_share": 0.45,
                "max_upper_tail_share": 0.35,
                "breakout_buffer_atr": 0.02,
                "reentry_buffer_atr": 0.0,
                "min_bear_body_atr": 0.06,
                "max_close_to_low_ratio": 0.55,
                "min_upper_wick_ratio": 0.10,
                "min_rr_ratio": 2.5,
                "stretch_rr_ratio": 3.5,
                "trade_end_time": "15:00",
                "constituent_confirmation_mode": "auto",
            },
            # --- Tier 9: Max relaxation with constituent (reliable mode) ---
            {
                "min_b_shape_score": 0.40,
                "min_lower_distribution_share": 0.45,
                "max_upper_tail_share": 0.35,
                "breakout_buffer_atr": 0.02,
                "reentry_buffer_atr": 0.0,
                "min_bear_body_atr": 0.05,
                "max_close_to_low_ratio": 0.58,
                "min_upper_wick_ratio": 0.08,
                "min_rr_ratio": 2.5,
                "stretch_rr_ratio": 3.5,
                "trade_start_time": "09:30",
                "trade_end_time": "15:30",
                "constituent_confirmation_mode": "auto",
                "one_trade_per_day": False,
                "max_daily_trades": 2,
            },
            # --- Tier 10: Max relaxation without constituent (~80+ trades) ---
            {
                "min_b_shape_score": 0.40,
                "min_lower_distribution_share": 0.45,
                "max_upper_tail_share": 0.35,
                "breakout_buffer_atr": 0.02,
                "reentry_buffer_atr": 0.0,
                "min_bear_body_atr": 0.05,
                "max_close_to_low_ratio": 0.58,
                "min_upper_wick_ratio": 0.08,
                "min_rr_ratio": 2.5,
                "stretch_rr_ratio": 3.5,
                "trade_start_time": "09:30",
                "trade_end_time": "15:30",
                "constituent_confirmation_mode": "off",
                "one_trade_per_day": False,
                "max_daily_trades": 2,
            },
            # --- Tier 11: Risk scaling on aggressive configs ---
            {
                "min_b_shape_score": 0.42,
                "breakout_buffer_atr": 0.02,
                "reentry_buffer_atr": 0.0,
                "min_bear_body_atr": 0.06,
                "min_rr_ratio": 2.5,
                "constituent_confirmation_mode": "auto",
                "risk_percent": 1.25,
            },
            {
                "min_b_shape_score": 0.42,
                "breakout_buffer_atr": 0.02,
                "reentry_buffer_atr": 0.0,
                "min_bear_body_atr": 0.06,
                "min_rr_ratio": 2.5,
                "constituent_confirmation_mode": "auto",
                "risk_percent": 1.5,
            },
        ]
    return []


def _default_scenarios() -> List[Scenario]:
    # Maximized date ranges matching actual CSV data availability.
    # XAUUSD Dukascopy: 2022-01-01 to 2025-01-01 (3 years, no gap)
    # NAS100 Dukascopy: 2023-01-02 to 2026-02-13 (3+ years)
    # US500 Dukascopy:  2024-01-01 to 2026-02-12 (~2 years only)
    # Earnings CSVs:    2023-01-01 to 2026-02-13 (3+ years)
    return [
        # --- 6 DEPLOY strategies ---
        Scenario("orb_advanced_aggressive_xau", "orb_strategy", "advanced_aggressive", "XAUUSD", "M1", "2022-01-01", "2024-12-31"),
        Scenario("orb_nas100_tuned", "orb_strategy", "nas100_tuned", "NAS100", "M1", "2023-01-02", "2026-02-13"),
        Scenario("advanced_orb_us500_tuned", "advanced_orb_strategy", "us500_tuned", "US500", "M1", "2024-01-01", "2026-02-12"),
        Scenario("liq_conservative_nas_m15", "liquidity_sweep_strategy", "conservative", "NAS100", "M15", "2023-01-02", "2026-02-13"),
        Scenario("liq_nas100_m15_safe", "liquidity_sweep_strategy", "nas100_m15_safe", "NAS100", "M15", "2023-01-02", "2026-02-13"),
        Scenario("keltner_xau_scaled", "keltner_breakout_strategy", "xauusd_scaled", "XAUUSD", "M15", "2022-01-01", "2024-12-31"),
        # --- B-Profile Reversion (index mean-reversion) ---
        Scenario(
            "bprofile_nas100_default",
            "b_profile_reversion_strategy",
            "default",
            "NAS100",
            "M30",
            "2024-01-01",
            "2026-02-13",
            "NAS100_M30_20240101_20260213_bprofile_enriched.csv",
        ),
        Scenario(
            "bprofile_us500_default",
            "b_profile_reversion_strategy",
            "default",
            "US500",
            "M30",
            "2024-01-01",
            "2026-02-12",
            "US500_M30_20240101_20260212_bprofile_enriched.csv",
        ),
        Scenario(
            "bprofile_nas100_max7_gapdown",
            "b_profile_reversion_strategy",
            "max7_gapdown",
            "NAS100",
            "M30",
            "2025-01-02",
            "2026-02-12",
            "NAS100_M30_20250101_20260213_bprofile_enriched_max7.csv",
        ),
        # --- Earnings IV Crush (all 6 stocks, full 3-year range) ---
        Scenario("earnings_aapl_default", "earnings_volatility_strategy", "default", "AAPL", "M15", "2023-01-01", "2026-02-13", "AAPL_M15_20230101_20260216_earnings.csv"),
        Scenario("earnings_msft_default", "earnings_volatility_strategy", "default", "MSFT", "M15", "2023-01-01", "2026-02-13", "MSFT_M15_20230101_20260217_earnings.csv"),
        Scenario("earnings_nvda_default", "earnings_volatility_strategy", "default", "NVDA", "M15", "2023-01-01", "2026-02-13", "NVDA_M15_20230101_20260217_earnings.csv"),
        Scenario("earnings_amzn_default", "earnings_volatility_strategy", "default", "AMZN", "M15", "2023-01-01", "2026-02-13", "AMZN_M15_20230101_20260217_earnings.csv"),
        Scenario("earnings_meta_default", "earnings_volatility_strategy", "default", "META", "M15", "2023-01-01", "2026-02-13", "META_M15_20230101_20260217_earnings.csv"),
        Scenario("earnings_tsla_default", "earnings_volatility_strategy", "default", "TSLA", "M15", "2023-01-01", "2026-02-13", "TSLA_M15_20230101_20260217_earnings.csv"),
    ]


def _is_fatal_data_error(metrics: Dict[str, Any]) -> bool:
    text = " ".join(
        str(metrics.get(k, ""))
        for k in ("error", "engine_error")
    ).lower()
    fatal_markers = [
        "data validation failed",
        "failed to fetch historical data",
        "no data from csv or mt5",
        "no data received for",
        "no csv file found",
        "max gap =",
        "excessive gaps",
    ]
    return any(m in text for m in fatal_markers)


def _micro_suffix(metrics: Dict[str, Any]) -> str:
    mt = float(metrics.get("micro_trade_count", 0))
    if mt <= 0:
        return ""
    return (
        f" | MicroTrades={int(mt)} Fill={float(metrics.get('micro_avg_fill_probability', 0)):.3f} "
        f"Impact=${float(metrics.get('micro_total_impact_usd', 0)):.2f}"
    )


def main():
    parser = argparse.ArgumentParser(description="Run long deploy backtest campaign with iterative tuning.")
    parser.add_argument("--only", type=str, default=None, help="Run only one strategy_id")
    parser.add_argument("--max-override-runs", type=int, default=30, help="Max override trials per scenario after preset sweep")
    parser.add_argument("--max-attempts-per-scenario", type=int, default=30, help="Hard cap on total runs per scenario (baseline + preset sweep + override)")
    parser.add_argument("--exhaustive", action="store_true", help="Do not stop a scenario early on first PASS; evaluate all configured variants")
    parser.add_argument("--campaign-name", type=str, default=f"deploy_campaign_{_now()}")
    args = parser.parse_args()

    mirrored = _mirror_earnings_csvs()
    print(f"[preflight] mirrored earnings csvs into dashboard/data/historical: {mirrored}")

    scenarios = _default_scenarios()
    if args.only:
        scenarios = [s for s in scenarios if s.strategy_id == args.only]
        if not scenarios:
            raise ValueError(f"No scenarios found for --only={args.only}")

    checkpoint_path = RESULTS_DIR / f"{args.campaign_name}.json"
    state: Dict[str, Any] = {
        "campaign_name": args.campaign_name,
        "started_at": datetime.now().isoformat(),
        "criteria": CRITERIA,
        "scenarios": [asdict(s) for s in scenarios],
        "runs": [],
        "best_by_scenario": {},
    }

    def persist():
        checkpoint_path.write_text(json.dumps(state, indent=2), encoding="utf-8")

    print(f"[campaign] starting: {args.campaign_name}")
    print(f"[campaign] checkpoint: {checkpoint_path}")

    for i, scenario in enumerate(scenarios, start=1):
        print("\n" + "=" * 120)
        print(f"[scenario {i}/{len(scenarios)}] {scenario.name} | {scenario.strategy_id} {scenario.seed_preset} {scenario.symbol} {scenario.timeframe}")
        print("=" * 120)

        run_candidates: List[Dict[str, Any]] = []
        seen = set()

        # 1) Seed preset baseline ONLY (no preset sweep - DEPLOY presets are already the winners)
        run_candidates.append({"preset": scenario.seed_preset, "overrides": None, "stage": "baseline"})
        seen.add((scenario.seed_preset, json.dumps({}, sort_keys=True)))

        best: Optional[Dict[str, Any]] = None
        scenario_fatal = False
        attempts = 0

        # Baseline + preset sweep loop
        for rc in run_candidates:
            if attempts >= int(args.max_attempts_per_scenario):
                print(f"[STOP] reached max attempts ({args.max_attempts_per_scenario}) for scenario '{scenario.name}'", flush=True)
                break
            preset = rc["preset"]
            overrides = rc["overrides"]
            stage = rc["stage"]
            print(f"[run] stage={stage:<12} preset={preset:<20} overrides={overrides or {}}")
            attempts += 1
            try:
                metrics = _run_once(scenario, preset, overrides=overrides)
            except Exception as e:
                metrics = {
                    "strategy_id": scenario.strategy_id,
                    "scenario_name": scenario.name,
                    "preset": preset,
                    "symbol": scenario.symbol,
                    "timeframe": scenario.timeframe,
                    "error": str(e),
                    "passed": False,
                    "fail_reasons": [f"runtime_error: {e}"],
                    "score": -1e9,
                    "stage": stage,
                    "overrides": overrides or {},
                }

            metrics["stage"] = stage
            metrics["overrides"] = overrides or {}
            state["runs"].append(metrics)
            if _is_better_result(metrics, best):
                best = metrics
            state["best_by_scenario"][scenario.name] = best
            persist()

            if _is_fatal_data_error(metrics):
                print(f"[SKIP] fatal data issue for scenario '{scenario.name}': {metrics.get('error') or metrics.get('engine_error')}", flush=True)
                scenario_fatal = True
                break

            if metrics.get("passed"):
                print(
                    f"[PASS] trades={int(metrics['total_trades'])} WR={metrics['win_rate']:.2f}% "
                    f"PF={metrics['profit_factor']:.2f} Sharpe={metrics['sharpe_ratio']:.2f} "
                    f"DD={metrics['max_drawdown_pct']:.2f}% Net=${metrics['net_profit']:.2f}"
                    f"{_micro_suffix(metrics)}"
                )
                if not args.exhaustive:
                    break
            else:
                print(
                    f"[FAIL] trades={int(metrics.get('total_trades', 0))} WR={metrics.get('win_rate', 0):.2f}% "
                    f"PF={metrics.get('profit_factor', 0):.2f} Sharpe={metrics.get('sharpe_ratio', 0):.2f} "
                    f"DD={metrics.get('max_drawdown_pct', 0):.2f}% Net=${metrics.get('net_profit', 0):.2f}"
                    f"{_micro_suffix(metrics)}"
                )

        if scenario_fatal:
            continue

        if best and best.get("passed") and not args.exhaustive:
            continue

        # 3) Targeted override tuning on current best preset
        if best is None:
            continue

        tune_preset = best.get("preset", scenario.seed_preset)
        variants = _override_variants(scenario.strategy_id)[: max(0, int(args.max_override_runs))]
        print(f"[tune] preset={tune_preset} variant_trials={len(variants)}")
        for idx, ov in enumerate(variants, start=1):
            if attempts >= int(args.max_attempts_per_scenario):
                print(f"[STOP] reached max attempts ({args.max_attempts_per_scenario}) for scenario '{scenario.name}'", flush=True)
                break
            key = (tune_preset, json.dumps(ov, sort_keys=True))
            if key in seen:
                continue
            seen.add(key)
            print(f"[run] stage=override    {idx:02d}/{len(variants)} preset={tune_preset:<20} overrides={ov}")
            attempts += 1
            try:
                metrics = _run_once(scenario, tune_preset, overrides=ov)
            except Exception as e:
                metrics = {
                    "strategy_id": scenario.strategy_id,
                    "scenario_name": scenario.name,
                    "preset": tune_preset,
                    "symbol": scenario.symbol,
                    "timeframe": scenario.timeframe,
                    "error": str(e),
                    "passed": False,
                    "fail_reasons": [f"runtime_error: {e}"],
                    "score": -1e9,
                    "stage": "override",
                    "overrides": ov,
                }
            metrics["stage"] = "override"
            metrics["overrides"] = ov
            state["runs"].append(metrics)
            if _is_better_result(metrics, best):
                best = metrics
                state["best_by_scenario"][scenario.name] = best
            persist()

            if _is_fatal_data_error(metrics):
                print(f"[SKIP] fatal data issue during tuning for '{scenario.name}': {metrics.get('error') or metrics.get('engine_error')}", flush=True)
                break

            if metrics.get("passed"):
                print(
                    f"[PASS] trades={int(metrics['total_trades'])} WR={metrics['win_rate']:.2f}% "
                    f"PF={metrics['profit_factor']:.2f} Sharpe={metrics['sharpe_ratio']:.2f} "
                    f"DD={metrics['max_drawdown_pct']:.2f}% Net=${metrics['net_profit']:.2f}"
                    f"{_micro_suffix(metrics)}"
                )
                if not args.exhaustive:
                    break
            else:
                print(
                    f"[FAIL] trades={int(metrics.get('total_trades', 0))} WR={metrics.get('win_rate', 0):.2f}% "
                    f"PF={metrics.get('profit_factor', 0):.2f} Sharpe={metrics.get('sharpe_ratio', 0):.2f} "
                    f"DD={metrics.get('max_drawdown_pct', 0):.2f}% Net=${metrics.get('net_profit', 0):.2f}"
                    f"{_micro_suffix(metrics)}"
                )

    # Final summary
    state["completed_at"] = datetime.now().isoformat()
    persist()

    print("\n" + "#" * 120)
    print("[summary] best result per scenario")
    print("#" * 120)
    for scenario in scenarios:
        b = state["best_by_scenario"].get(scenario.name)
        if not b:
            print(f"- {scenario.name}: no result")
            continue
        status = "PASS" if b.get("passed") else "FAIL"
        print(
            f"- {scenario.name}: {status} | preset={b.get('preset')} stage={b.get('stage')} "
            f"WR={b.get('win_rate', 0):.2f}% PF={b.get('profit_factor', 0):.2f} "
            f"Sharpe={b.get('sharpe_ratio', 0):.2f} DD={b.get('max_drawdown_pct', 0):.2f}% "
            f"Net=${b.get('net_profit', 0):.2f}{_micro_suffix(b)}"
        )

    print(f"[campaign] finished. checkpoint={checkpoint_path}")


if __name__ == "__main__":
    main()
