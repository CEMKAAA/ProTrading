"""
Engine parity utilities.

Compares key performance outputs between reference and candidate engines.
"""

from __future__ import annotations

from typing import Any, Dict, Optional


DEFAULT_TOLERANCES: Dict[str, float] = {
    # Absolute delta in trade count
    "max_trade_count_delta": 0.0,
    # Relative delta in net profit (% of reference absolute value)
    "max_net_profit_delta_pct": 0.5,
    # Absolute delta in win rate percentage points
    "max_win_rate_delta": 0.25,
    # Absolute delta in max drawdown percentage points
    "max_drawdown_delta": 0.5,
    # Absolute delta in Sharpe ratio
    "max_sharpe_delta": 0.10,
}


def _safe_float(value: Any, fallback: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return fallback


def _pct_delta(reference: float, candidate: float) -> float:
    denom = abs(reference)
    if denom <= 1e-9:
        return 0.0 if abs(candidate) <= 1e-9 else 100.0
    return abs(candidate - reference) / denom * 100.0


def compare_engine_results(
    reference_results: Dict[str, Any],
    candidate_results: Dict[str, Any],
    tolerances: Optional[Dict[str, float]] = None,
) -> Dict[str, Any]:
    """
    Compare two backtest result payloads and produce pass/fail diagnostics.
    """
    tol = dict(DEFAULT_TOLERANCES)
    if tolerances:
        tol.update({k: _safe_float(v, tol.get(k, 0.0)) for k, v in tolerances.items()})

    ref_m = (reference_results or {}).get("metrics", {}) or {}
    cand_m = (candidate_results or {}).get("metrics", {}) or {}

    ref_trades = int(_safe_float(ref_m.get("total_trades", 0), 0.0))
    cand_trades = int(_safe_float(cand_m.get("total_trades", 0), 0.0))
    ref_net = _safe_float(ref_m.get("net_profit", 0.0), 0.0)
    cand_net = _safe_float(cand_m.get("net_profit", 0.0), 0.0)
    ref_wr = _safe_float(ref_m.get("win_rate", 0.0), 0.0)
    cand_wr = _safe_float(cand_m.get("win_rate", 0.0), 0.0)
    ref_dd = _safe_float(ref_m.get("max_drawdown_percent", 0.0), 0.0)
    cand_dd = _safe_float(cand_m.get("max_drawdown_percent", 0.0), 0.0)
    ref_sh = _safe_float(ref_m.get("sharpe_ratio", 0.0), 0.0)
    cand_sh = _safe_float(cand_m.get("sharpe_ratio", 0.0), 0.0)

    trade_count_delta = abs(cand_trades - ref_trades)
    net_profit_delta_pct = _pct_delta(ref_net, cand_net)
    win_rate_delta = abs(cand_wr - ref_wr)
    drawdown_delta = abs(cand_dd - ref_dd)
    sharpe_delta = abs(cand_sh - ref_sh)

    checks = [
        {
            "name": "trade_count",
            "delta": trade_count_delta,
            "threshold": tol["max_trade_count_delta"],
            "passed": trade_count_delta <= tol["max_trade_count_delta"],
        },
        {
            "name": "net_profit_pct",
            "delta": round(net_profit_delta_pct, 6),
            "threshold": tol["max_net_profit_delta_pct"],
            "passed": net_profit_delta_pct <= tol["max_net_profit_delta_pct"],
        },
        {
            "name": "win_rate",
            "delta": round(win_rate_delta, 6),
            "threshold": tol["max_win_rate_delta"],
            "passed": win_rate_delta <= tol["max_win_rate_delta"],
        },
        {
            "name": "max_drawdown_percent",
            "delta": round(drawdown_delta, 6),
            "threshold": tol["max_drawdown_delta"],
            "passed": drawdown_delta <= tol["max_drawdown_delta"],
        },
        {
            "name": "sharpe_ratio",
            "delta": round(sharpe_delta, 6),
            "threshold": tol["max_sharpe_delta"],
            "passed": sharpe_delta <= tol["max_sharpe_delta"],
        },
    ]

    passed = all(c["passed"] for c in checks)
    return {
        "passed": passed,
        "checks": checks,
        "reference": {
            "total_trades": ref_trades,
            "net_profit": ref_net,
            "win_rate": ref_wr,
            "max_drawdown_percent": ref_dd,
            "sharpe_ratio": ref_sh,
        },
        "candidate": {
            "total_trades": cand_trades,
            "net_profit": cand_net,
            "win_rate": cand_wr,
            "max_drawdown_percent": cand_dd,
            "sharpe_ratio": cand_sh,
        },
        "tolerances": tol,
    }

