"""Parameter grid-search helpers for Workbench research mode."""

from __future__ import annotations

from itertools import product
from typing import Any, Dict, Iterable, List, Sequence, Tuple

import numpy as np
import pandas as pd


def _safe_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def _safe_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except Exception:
        return float(default)


def _normalize_ohlc_df(df: pd.DataFrame) -> pd.DataFrame:
    if df is None or df.empty or "close" not in df.columns:
        return pd.DataFrame(columns=["close", "returns"])
    data = df.copy()
    if not isinstance(data.index, pd.DatetimeIndex):
        data.index = pd.to_datetime(data.index, utc=True, errors="coerce")
    data = data[~data.index.isna()].sort_index()
    data = data[~data.index.duplicated(keep="last")]
    out = pd.DataFrame(index=data.index)
    out["close"] = pd.to_numeric(data["close"], errors="coerce")
    out = out.dropna(subset=["close"])
    out["returns"] = np.log(out["close"] / out["close"].shift(1))
    return out


def _range_int(start: int, stop: int, step: int) -> List[int]:
    st = max(1, int(step))
    if stop <= start:
        return [int(start)]
    vals = list(range(int(start), int(stop), int(st)))
    return vals if vals else [int(start)]


def _range_float(start: float, stop: float, step: float, decimals: int = 6) -> List[float]:
    st = max(1e-9, float(step))
    if stop <= start:
        return [round(float(start), decimals)]
    # Build values via integer step count to avoid floating-accumulation drift.
    span = max(0.0, float(stop) - float(start))
    n_steps = int(np.ceil((span / st) - 1e-12))
    vals = [round(float(start) + (i * st), decimals) for i in range(max(1, n_steps))]
    # Keep exclusive stop semantics (mirror python range).
    vals = [v for v in vals if float(v) < float(stop)]
    return vals if vals else [round(float(start), decimals)]


def _perf_from_strategy_returns(
    returns: pd.Series,
    strategy_returns: pd.Series,
) -> Tuple[float, float]:
    clean = pd.DataFrame({"r": returns, "s": strategy_returns}).dropna()
    if clean.empty:
        return 1.0, 0.0
    creturns = float(np.exp(clean["r"].cumsum()).iloc[-1])
    cstrategy = float(np.exp(clean["s"].cumsum()).iloc[-1])
    return cstrategy, cstrategy - creturns


def _risk_metrics(strategy_returns: pd.Series, trades: pd.Series) -> Dict[str, Any]:
    s = pd.to_numeric(strategy_returns, errors="coerce").dropna()
    if s.empty:
        return {"sharpe": 0.0, "max_drawdown": 0.0, "trade_count": 0}
    std = float(s.std(ddof=0))
    mean = float(s.mean())
    # Per-bar Sharpe scaled by sqrt(N) (timeframe-agnostic).
    sharpe = 0.0 if std <= 1e-12 else (mean / std) * float(np.sqrt(len(s)))
    equity = np.exp(s.cumsum())
    running_max = equity.cummax()
    dd = (equity / running_max) - 1.0
    max_drawdown = float(abs(dd.min())) if len(dd) else 0.0
    t = pd.to_numeric(trades, errors="coerce").fillna(0.0)
    trade_count = int((t > 0.0).sum())
    return {
        "sharpe": float(round(sharpe, 6)),
        "max_drawdown": float(round(max_drawdown, 6)),
        "trade_count": int(trade_count),
    }


def optimize_sma_crossover(
    df: pd.DataFrame,
    fast_range: Tuple[int, int, int],
    slow_range: Tuple[int, int, int],
    tc: float = 0.0001,
) -> Dict[str, Any]:
    """
    Grid-search SMA crossover params.

    Logic source: Experiments/SMABacktester.py optimize pattern.
    Trading-cost adjustment aligns with MeanRev/Con backtest style.
    """
    base = _normalize_ohlc_df(df)
    if len(base) < 30:
        return {
            "strategy_type": "sma_crossover",
            "optimal": None,
            "best_performance": 1.0,
            "results": [],
            "total_combinations": 0,
        }

    fast_vals = _range_int(*fast_range)
    slow_vals = _range_int(*slow_range)

    rows: List[Dict[str, Any]] = []
    for fast, slow in product(fast_vals, slow_vals):
        if int(fast) >= int(slow):
            continue
        data = base.copy()
        data["sma_fast"] = data["close"].rolling(int(fast)).mean()
        data["sma_slow"] = data["close"].rolling(int(slow)).mean()
        data = data.dropna(subset=["sma_fast", "sma_slow", "returns"])
        if data.empty:
            continue
        data["position"] = np.where(data["sma_fast"] > data["sma_slow"], 1.0, -1.0)
        data["strategy"] = data["position"].shift(1) * data["returns"]
        data["trades"] = data["position"].diff().fillna(0.0).abs()
        data["strategy"] = data["strategy"] - (data["trades"] * float(tc))
        perf, outperf = _perf_from_strategy_returns(data["returns"], data["strategy"])
        risk = _risk_metrics(data["strategy"], data["trades"])
        rows.append(
            {
                "fast": int(fast),
                "slow": int(slow),
                "performance": float(round(perf, 6)),
                "outperformance": float(round(outperf, 6)),
                "sharpe": float(risk["sharpe"]),
                "max_drawdown": float(risk["max_drawdown"]),
                "trade_count": int(risk["trade_count"]),
            }
        )

    rows.sort(key=lambda x: float(x.get("performance", 0.0)), reverse=True)
    best = rows[0] if rows else None
    return {
        "strategy_type": "sma_crossover",
        "optimal": {"fast": int(best["fast"]), "slow": int(best["slow"])} if best else None,
        "best_performance": float(best["performance"]) if best else 1.0,
        "results": rows,
        "total_combinations": int(len(rows)),
    }


def optimize_mean_reversion(
    df: pd.DataFrame,
    sma_range: Tuple[int, int, int],
    dev_range: Tuple[float, float, float],
    tc: float = 0.0001,
) -> Dict[str, Any]:
    """
    Grid-search mean-reversion (Bollinger) params.

    Logic source: Experiments/MeanRevBacktester.py optimize pattern.
    """
    base = _normalize_ohlc_df(df)
    if len(base) < 40:
        return {
            "strategy_type": "mean_reversion",
            "optimal": None,
            "best_performance": 1.0,
            "results": [],
            "total_combinations": 0,
        }

    sma_vals = _range_int(*sma_range)
    dev_vals = _range_float(*dev_range, decimals=4)

    rows: List[Dict[str, Any]] = []
    for sma, dev in product(sma_vals, dev_vals):
        data = base.copy()
        data["sma"] = data["close"].rolling(int(sma)).mean()
        roll_std = data["close"].rolling(int(sma)).std()
        data["lower"] = data["sma"] - (roll_std * float(dev))
        data["upper"] = data["sma"] + (roll_std * float(dev))
        data = data.dropna(subset=["sma", "lower", "upper", "returns"])
        if data.empty:
            continue
        data["distance"] = data["close"] - data["sma"]
        data["position"] = np.where(data["close"] < data["lower"], 1.0, np.nan)
        data["position"] = np.where(data["close"] > data["upper"], -1.0, data["position"])
        data["position"] = np.where(
            data["distance"] * data["distance"].shift(1) < 0.0,
            0.0,
            data["position"],
        )
        data["position"] = pd.Series(data["position"], index=data.index).ffill().fillna(0.0)
        data["strategy"] = data["position"].shift(1) * data["returns"]
        data["trades"] = data["position"].diff().fillna(0.0).abs()
        data["strategy"] = data["strategy"] - (data["trades"] * float(tc))
        perf, outperf = _perf_from_strategy_returns(data["returns"], data["strategy"])
        risk = _risk_metrics(data["strategy"], data["trades"])
        rows.append(
            {
                "sma": int(sma),
                "dev": float(round(float(dev), 4)),
                "performance": float(round(perf, 6)),
                "outperformance": float(round(outperf, 6)),
                "sharpe": float(risk["sharpe"]),
                "max_drawdown": float(risk["max_drawdown"]),
                "trade_count": int(risk["trade_count"]),
            }
        )

    rows.sort(key=lambda x: float(x.get("performance", 0.0)), reverse=True)
    best = rows[0] if rows else None
    return {
        "strategy_type": "mean_reversion",
        "optimal": {"sma": int(best["sma"]), "dev": float(best["dev"])} if best else None,
        "best_performance": float(best["performance"]) if best else 1.0,
        "results": rows,
        "total_combinations": int(len(rows)),
    }


def parse_int_range(
    raw: Dict[str, Any],
    key: str,
    start_default: int,
    stop_default: int,
    step_default: int,
    *,
    min_v: int,
    max_v: int,
) -> Tuple[int, int, int]:
    seq = raw.get(f"{key}_range")
    if isinstance(seq, Sequence) and not isinstance(seq, (str, bytes)) and len(seq) >= 3:
        start = _safe_int(seq[0], start_default)
        stop = _safe_int(seq[1], stop_default)
        step = _safe_int(seq[2], step_default)
    else:
        start = _safe_int(raw.get(f"{key}_start"), start_default)
        stop = _safe_int(raw.get(f"{key}_stop"), stop_default)
        step = _safe_int(raw.get(f"{key}_step"), step_default)
    start = max(min_v, min(max_v, int(start)))
    stop = max(min_v + 1, min(max_v + 1, int(stop)))
    step = max(1, int(step))
    if stop <= start:
        stop = min(max_v + 1, start + step)
    return start, stop, step


def parse_float_range(
    raw: Dict[str, Any],
    key: str,
    start_default: float,
    stop_default: float,
    step_default: float,
    *,
    min_v: float,
    max_v: float,
) -> Tuple[float, float, float]:
    seq = raw.get(f"{key}_range")
    if isinstance(seq, Sequence) and not isinstance(seq, (str, bytes)) and len(seq) >= 3:
        start = _safe_float(seq[0], start_default)
        stop = _safe_float(seq[1], stop_default)
        step = _safe_float(seq[2], step_default)
    else:
        start = _safe_float(raw.get(f"{key}_start"), start_default)
        stop = _safe_float(raw.get(f"{key}_stop"), stop_default)
        step = _safe_float(raw.get(f"{key}_step"), step_default)
    start = max(min_v, min(max_v, float(start)))
    stop = max(min_v + 1e-9, min(max_v + 1e-9, float(stop)))
    step = max(1e-6, float(step))
    if stop <= start:
        stop = min(max_v + 1e-9, start + step)
    return start, stop, step


def count_combinations(int_ranges: Iterable[Tuple[int, int, int]]) -> int:
    total = 1
    for start, stop, step in int_ranges:
        total *= len(_range_int(int(start), int(stop), int(step)))
    return int(total)


def count_sma_crossover_combinations(
    fast_range: Tuple[int, int, int],
    slow_range: Tuple[int, int, int],
) -> int:
    fast_vals = _range_int(*fast_range)
    slow_vals = _range_int(*slow_range)
    total = 0
    for fast in fast_vals:
        for slow in slow_vals:
            if int(fast) < int(slow):
                total += 1
    return int(total)


def count_float_combinations(float_ranges: Iterable[Tuple[float, float, float]]) -> int:
    total = 1
    for start, stop, step in float_ranges:
        total *= len(_range_float(float(start), float(stop), float(step)))
    return int(total)
