"""
Deterministic earnings-event dataset and selector utilities.

These helpers transform bar-level earnings datasets into event-level rows
that can be used for deterministic trade selection before backtesting.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from pathlib import Path
from typing import Dict, Iterable, List, Optional

import numpy as np
import pandas as pd


REQUIRED_EARNINGS_COLUMNS: List[str] = [
    "open",
    "high",
    "low",
    "close",
    "volume",
    "earnings_event",
    "days_to_earnings",
    "is_pre_earnings_day",
    "next_earnings_date",
    "planned_exit_date",
    "iv_front",
    "iv_back",
    "iv_45d",
    "iv30",
    "rv30",
    "volume30",
]


def parse_hhmm(value: str) -> time:
    hh, mm = [int(x) for x in str(value).split(":")]
    return time(hh, mm)


def load_earnings_bars_csv(path: str) -> pd.DataFrame:
    """
    Load a prepared earnings bars CSV and normalize its DateTime index.
    """
    csv_path = Path(path)
    if not csv_path.exists():
        raise FileNotFoundError(f"Input CSV not found: {csv_path}")

    df = pd.read_csv(csv_path, index_col=0)
    if df.empty:
        raise ValueError(f"Input CSV is empty: {csv_path}")

    if not isinstance(df.index, pd.DatetimeIndex):
        df.index = pd.to_datetime(df.index, errors="coerce")
    else:
        df.index = pd.to_datetime(df.index, errors="coerce")
    df = df[~df.index.isna()]
    if df.empty:
        raise ValueError(f"Input CSV has no parseable datetime index: {csv_path}")

    if df.index.tz is None:
        df.index = df.index.tz_localize("America/New_York")
    else:
        df.index = df.index.tz_convert("America/New_York")

    missing = [c for c in REQUIRED_EARNINGS_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"Input CSV missing required columns: {missing}")

    # Normalize common boolean-like columns.
    df["earnings_event"] = _coerce_bool(df["earnings_event"])
    df["is_pre_earnings_day"] = _coerce_bool(df["is_pre_earnings_day"])
    return df.sort_index()


def _coerce_bool(series: pd.Series) -> pd.Series:
    s = series.astype(str).str.strip().str.lower()
    truthy = {"1", "true", "t", "yes", "y"}
    return s.isin(truthy) | (pd.to_numeric(series, errors="coerce").fillna(0) > 0)


def infer_bar_interval(df: pd.DataFrame) -> timedelta:
    if len(df) < 2:
        return timedelta(minutes=15)
    diffs = pd.Series(df.index[1:] - df.index[:-1])
    diffs = diffs[diffs > pd.Timedelta(0)]
    if diffs.empty:
        return timedelta(minutes=15)
    return diffs.mode().iloc[0].to_pytimedelta()


def build_event_level_dataset(
    df: pd.DataFrame,
    symbol: str,
    entry_time: str = "15:45",
    exit_time: str = "09:45",
    front_dte_days: float = 7.0,
    expected_move_scale: float = 1.0,
) -> pd.DataFrame:
    """
    Convert bar-level earnings features into one row per event.

    Matching strategy behavior:
    - Signal bar is the bar that precedes intended entry by one bar interval.
    - Entry reference price is the signal bar close.
    - Realized move is measured to the first bar at/after configured exit time
      on the post-earnings trading day.
    """
    missing = [c for c in REQUIRED_EARNINGS_COLUMNS if c not in df.columns]
    if missing:
        raise ValueError(f"DataFrame missing required columns: {missing}")

    if len(df) < 3:
        return pd.DataFrame()

    bar_interval = infer_bar_interval(df)
    entry_t = parse_hhmm(entry_time)
    exit_t = parse_hhmm(exit_time)

    trading_days = sorted(pd.unique(df.index.date))
    if len(trading_days) < 3:
        return pd.DataFrame()

    event_days = sorted(pd.unique(df[df["earnings_event"].astype(bool)].index.date))
    if not event_days:
        return pd.DataFrame()

    day_to_idx = {d: i for i, d in enumerate(trading_days)}
    rows: List[Dict[str, object]] = []

    for event_day in event_days:
        idx = day_to_idx.get(event_day)
        if idx is None or idx == 0 or idx >= len(trading_days) - 1:
            continue

        entry_day = trading_days[idx - 1]
        exit_day = trading_days[idx + 1]

        entry_day_df = df[df.index.date == entry_day]
        exit_day_df = df[df.index.date == exit_day]
        if entry_day_df.empty or exit_day_df.empty:
            continue

        target_entry_ts = pd.Timestamp(
            datetime.combine(entry_day, entry_t),
            tz=df.index.tz,
        )
        target_signal_ts = target_entry_ts - pd.Timedelta(bar_interval)
        signal_candidates = entry_day_df[entry_day_df.index <= target_signal_ts]
        if signal_candidates.empty:
            continue
        signal_ts = signal_candidates.index[-1]
        signal_row = signal_candidates.iloc[-1]

        target_exit_ts = pd.Timestamp(
            datetime.combine(exit_day, exit_t),
            tz=df.index.tz,
        )
        exit_candidates = exit_day_df[exit_day_df.index >= target_exit_ts]
        if exit_candidates.empty:
            exit_ts = exit_day_df.index[-1]
            exit_row = exit_day_df.iloc[-1]
        else:
            exit_ts = exit_candidates.index[0]
            exit_row = exit_candidates.iloc[0]

        entry_price = _to_float(signal_row.get("close"))
        exit_price = _to_float(exit_row.get("close"))
        iv_front = _to_float(signal_row.get("iv_front"))
        iv_back = _to_float(signal_row.get("iv_back"))
        iv_far = _to_float(signal_row.get("iv_45d"))
        iv30 = _to_float(signal_row.get("iv30"))
        rv30 = _to_float(signal_row.get("rv30"))
        volume30 = _to_float(signal_row.get("volume30"))

        if any(v is None for v in [entry_price, exit_price, iv_front, iv_back, iv_far, iv30, rv30, volume30]):
            continue
        if entry_price <= 0 or rv30 <= 0:
            continue

        expected_move_pct = max(iv_front * np.sqrt(max(front_dte_days, 1.0) / 365.0) * expected_move_scale, 0.0)
        expected_move_abs = entry_price * expected_move_pct
        realized_move_abs = abs(exit_price - entry_price)
        realized_move_pct = realized_move_abs / entry_price
        edge_abs = expected_move_abs - realized_move_abs
        edge_pct = expected_move_pct - realized_move_pct
        term_slope = iv_far - iv_front
        iv30_rv30_ratio = iv30 / rv30

        rows.append(
            {
                "symbol": symbol.upper(),
                "entry_day": entry_day.isoformat(),
                "event_day": event_day.isoformat(),
                "exit_day": exit_day.isoformat(),
                "signal_ts": signal_ts.isoformat(),
                "entry_ts_target": target_entry_ts.isoformat(),
                "exit_ts": exit_ts.isoformat(),
                "entry_ref_price": float(entry_price),
                "exit_price": float(exit_price),
                "expected_move_pct": float(expected_move_pct),
                "expected_move_abs": float(expected_move_abs),
                "realized_move_pct": float(realized_move_pct),
                "realized_move_abs": float(realized_move_abs),
                "edge_pct": float(edge_pct),
                "edge_abs": float(edge_abs),
                "iv_front": float(iv_front),
                "iv_back": float(iv_back),
                "iv_45d": float(iv_far),
                "iv30": float(iv30),
                "rv30": float(rv30),
                "iv30_rv30_ratio": float(iv30_rv30_ratio),
                "term_structure_slope": float(term_slope),
                "volume30": float(volume30),
            }
        )

    out = pd.DataFrame(rows)
    if out.empty:
        return out
    return out.sort_values("signal_ts").reset_index(drop=True)


def select_trade_candidates(
    events_df: pd.DataFrame,
    term_structure_max_slope: float,
    min_avg_volume30: float,
    min_iv30_rv30_ratio: float,
    min_edge_pct: float = 0.0,
) -> pd.DataFrame:
    """
    Apply deterministic rule filters and mark selected trade candidates.
    """
    if events_df is None or events_df.empty:
        return pd.DataFrame()

    out = events_df.copy()
    out["rule_term_structure"] = out["term_structure_slope"] <= float(term_structure_max_slope)
    out["rule_volume30"] = out["volume30"] >= float(min_avg_volume30)
    out["rule_iv30_rv30"] = out["iv30_rv30_ratio"] >= float(min_iv30_rv30_ratio)
    out["rule_edge"] = out["edge_pct"] >= float(min_edge_pct)
    out["selected"] = (
        out["rule_term_structure"]
        & out["rule_volume30"]
        & out["rule_iv30_rv30"]
        & out["rule_edge"]
    )
    out["selection_score"] = (
        out[["rule_term_structure", "rule_volume30", "rule_iv30_rv30", "rule_edge"]]
        .sum(axis=1)
        .astype(int)
    )
    return out.sort_values(["selected", "edge_pct"], ascending=[False, False]).reset_index(drop=True)


def summarize_selection(candidates_df: pd.DataFrame) -> Dict[str, int]:
    if candidates_df is None or candidates_df.empty:
        return {"events": 0, "selected": 0}
    return {
        "events": int(len(candidates_df)),
        "selected": int(candidates_df["selected"].sum()),
    }


def _to_float(value) -> Optional[float]:
    try:
        if value is None or pd.isna(value):
            return None
        return float(value)
    except Exception:
        return None
