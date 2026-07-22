#!/usr/bin/env python3
"""Causal multi-timeframe market-regime research for LiqNarrativeSolVersion.

The script never edits or executes the EA. Descriptive performance episodes
are kept separate from the causal market state that was knowable at each month
open. H1, H2, H4, and D1 returns share the same completed D1-session anchors,
so lower timeframes do not receive a larger effective lookback by accident.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd


TIMEFRAMES = ("H1", "H2", "H4", "D1")
HORIZONS = (5, 20, 100)


def metrics(frame: pd.DataFrame) -> dict:
    if frame.empty:
        return {"trades": 0, "wins": 0, "losses": 0, "wr": None, "net_r": 0.0, "avg_r": None}
    wins = int(frame["won"].sum())
    trades = int(len(frame))
    return {
        "trades": trades,
        "wins": wins,
        "losses": trades - wins,
        "wr": float(wins / trades),
        "net_r": float(frame["r"].sum()),
        "avg_r": float(frame["r"].mean()),
    }


def load_rates(rate_dir: Path) -> dict[str, pd.DataFrame]:
    rates: dict[str, pd.DataFrame] = {}
    for timeframe in TIMEFRAMES:
        path = rate_dir / f"JP225m_{timeframe}.parquet"
        frame = pd.read_parquet(path).sort_values("time").reset_index(drop=True)
        frame["time"] = pd.to_datetime(frame["time"], utc=True)
        rates[timeframe] = frame
    return rates


def completed_close_index(frame: pd.DataFrame, timestamp: pd.Timestamp) -> int:
    """Return the last bar whose successor has opened by timestamp.

    Using the successor's open as the close-availability boundary also handles
    broker session gaps without assuming that every clock-hour has a bar.
    """
    return int(frame["time"].searchsorted(timestamp, side="right") - 2)


def synchronized_features(
    months: pd.PeriodIndex, rates: dict[str, pd.DataFrame]
) -> pd.DataFrame:
    daily = rates["D1"]
    rows: list[dict] = []
    for month in months:
        timestamp = pd.Timestamp(month.start_time, tz="UTC")
        daily_index = completed_close_index(daily, timestamp)
        row: dict[str, object] = {"month": str(month), "feature_time": timestamp}
        if daily_index < max(HORIZONS):
            rows.append(row)
            continue

        for horizon in HORIZONS:
            anchor_time = daily.iloc[daily_index - horizon]["time"]
            for timeframe, frame in rates.items():
                current_index = completed_close_index(frame, timestamp)
                anchor_index = int(frame["time"].searchsorted(anchor_time, side="right") - 1)
                column = f"{timeframe.lower()}_ret_{horizon}s_pct"
                if current_index < 0 or anchor_index < 0:
                    row[column] = np.nan
                    continue
                current_close = float(frame.iloc[current_index]["close"])
                anchor_close = float(frame.iloc[anchor_index]["close"])
                row[column] = (current_close / anchor_close - 1.0) * 100.0
        rows.append(row)

    features = pd.DataFrame(rows)
    for horizon in HORIZONS:
        columns = [f"{timeframe.lower()}_ret_{horizon}s_pct" for timeframe in TIMEFRAMES]
        features[f"all_tf_ret_{horizon}s_pct"] = features[columns].median(axis=1, skipna=True)
    features["fast_h1_h2_ret_5s_pct"] = features[
        ["h1_ret_5s_pct", "h2_ret_5s_pct"]
    ].median(axis=1, skipna=True)
    features["slow_h4_d1_ret_100s_pct"] = features[
        ["h4_ret_100s_pct", "d1_ret_100s_pct"]
    ].median(axis=1, skipna=True)
    return features


def add_causal_regime(features: pd.DataFrame, hysteresis_pct: float) -> pd.DataFrame:
    out = features.copy()
    direction = 0
    age = 0
    directions: list[str] = []
    ages: list[int] = []
    phases: list[str] = []

    for row in out.itertuples(index=False):
        macro = getattr(row, "all_tf_ret_100s_pct")
        fast = getattr(row, "fast_h1_h2_ret_5s_pct")
        previous = direction
        if pd.notna(macro):
            if macro >= hysteresis_pct:
                direction = 1
            elif macro <= -hysteresis_pct:
                direction = -1

        if direction == 0:
            age = 0
            phase = "UNINITIALIZED"
        else:
            age = age + 1 if direction == previous else 1
            if pd.isna(fast):
                phase = "UNKNOWN"
            elif direction > 0:
                phase = "UP_ALIGNED" if fast >= 0.0 else "UP_PULLBACK"
            else:
                phase = "DOWN_ALIGNED" if fast <= 0.0 else "DOWN_REBOUND"
        directions.append({1: "UP", -1: "DOWN", 0: "UNKNOWN"}[direction])
        ages.append(age)
        phases.append(phase)

    out["macro_regime"] = directions
    out["macro_regime_age_months"] = ages
    out["causal_market_phase"] = phases
    return out


def monthly_performance(trades: pd.DataFrame) -> pd.DataFrame:
    grouped = trades.groupby("month", observed=True).agg(
        trades=("won", "size"),
        wins=("won", "sum"),
        net_r=("r", "sum"),
        avg_r=("r", "mean"),
    ).reset_index()
    grouped["losses"] = grouped["trades"] - grouped["wins"]
    grouped["wr"] = grouped["wins"] / grouped["trades"]
    grouped["observed_performance"] = np.select(
        [grouped["avg_r"] >= 0.12, grouped["avg_r"] <= -0.12],
        ["GOOD", "BAD"],
        default="BREAK_EVEN",
    )
    grouped["month"] = grouped["month"].astype(str)
    return grouped


def adaptive_episodes(monthly: pd.DataFrame, penalty: float = 3.0) -> pd.DataFrame:
    """Retrospective 3-6 month segmentation; never a live trading input."""
    frame = monthly.sort_values("month").reset_index(drop=True).copy()
    count = len(frame)
    best = np.full(count + 1, np.inf)
    previous = np.full(count + 1, -1, dtype=int)
    best[0] = 0.0
    for end in range(1, count + 1):
        for length in range(3, 7):
            start = end - length
            if start < 0 or not np.isfinite(best[start]):
                continue
            part = frame.iloc[start:end]
            trades = float(part["trades"].sum())
            net_r = float(part["net_r"].sum())
            # Sum of squared trade R around the segment mean is equivalent up
            # to a constant; monthly aggregate supplies the between-group term.
            score = best[start] - net_r * net_r / trades + penalty
            if score < best[end]:
                best[end] = score
                previous[end] = start

    if previous[count] < 0:
        raise RuntimeError("Unable to partition monthly history into 3-6 month episodes")

    bounds: list[tuple[int, int]] = []
    end = count
    while end > 0:
        start = int(previous[end])
        bounds.append((start, end))
        end = start
    bounds.reverse()

    rows: list[dict] = []
    for index, (start, end) in enumerate(bounds, start=1):
        part = frame.iloc[start:end]
        trades = int(part["trades"].sum())
        wins = int(part["wins"].sum())
        net_r = float(part["net_r"].sum())
        avg_r = net_r / trades
        rows.append(
            {
                "episode": index,
                "start_month": part.iloc[0]["month"],
                "end_month": part.iloc[-1]["month"],
                "months": int(len(part)),
                "trades": trades,
                "wins": wins,
                "losses": trades - wins,
                "wr": wins / trades,
                "net_r": net_r,
                "avg_r": avg_r,
                "observed_performance": "GOOD" if avg_r >= 0.12 else ("BAD" if avg_r <= -0.12 else "BREAK_EVEN"),
            }
        )
    return pd.DataFrame(rows)


def fixed_four_month_blocks(monthly: pd.DataFrame) -> pd.DataFrame:
    """Calendar-aligned blocks expose neutral periods without optimized cuts."""
    frame = monthly.sort_values("month").reset_index(drop=True)
    rows: list[dict] = []
    for start in range(0, len(frame), 4):
        part = frame.iloc[start : start + 4]
        if part.empty:
            continue
        trades = int(part["trades"].sum())
        wins = int(part["wins"].sum())
        net_r = float(part["net_r"].sum())
        avg_r = net_r / trades
        rows.append(
            {
                "block": len(rows) + 1,
                "start_month": part.iloc[0]["month"],
                "end_month": part.iloc[-1]["month"],
                "months": int(len(part)),
                "trades": trades,
                "wins": wins,
                "losses": trades - wins,
                "wr": wins / trades,
                "net_r": net_r,
                "avg_r": avg_r,
                "observed_performance": "GOOD" if avg_r >= 0.12 else ("BAD" if avg_r <= -0.12 else "BREAK_EVEN"),
            }
        )
    return pd.DataFrame(rows)


def grouped_metrics(frame: pd.DataFrame, group_column: str) -> dict:
    result: dict[str, dict] = {}
    for value, part in frame.groupby(group_column, dropna=False):
        result[str(value)] = metrics(part)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dataset", type=Path, default=Path("logs/sol_v14_pattern_research.dataset.csv")
    )
    parser.add_argument("--rates", type=Path, default=Path("logs/sol_jp225_rates"))
    parser.add_argument("--out-prefix", type=Path, default=Path("logs/sol_market_regimes"))
    parser.add_argument("--hysteresis-pct", type=float, default=5.0)
    args = parser.parse_args()

    trades = pd.read_csv(args.dataset, parse_dates=["available"])
    trades["available"] = pd.to_datetime(trades["available"], utc=True)
    trades = trades[trades["available"].dt.year >= 2021].copy()
    trades["won"] = trades["result"].eq("WIN").astype(int)
    trades["month"] = trades["available"].dt.tz_localize(None).dt.to_period("M")

    months = pd.period_range(trades["month"].min(), trades["month"].max(), freq="M")
    features = add_causal_regime(synchronized_features(months, load_rates(args.rates)), args.hysteresis_pct)
    monthly = monthly_performance(trades).merge(features, on="month", how="left", validate="one_to_one")
    episodes = adaptive_episodes(monthly)
    blocks = fixed_four_month_blocks(monthly)
    enriched = trades.assign(month=trades["month"].astype(str)).merge(
        features[["month", "macro_regime", "macro_regime_age_months", "causal_market_phase"]],
        on="month",
        how="left",
        validate="many_to_one",
    )

    splits = {
        "development_2021_2022": enriched[enriched["available"].dt.year <= 2022],
        "validation_2023": enriched[enriched["available"].dt.year == 2023],
        "forward_2024_plus": enriched[enriched["available"].dt.year >= 2024],
        "full_2021_plus": enriched,
    }
    current = monthly.iloc[-1]
    report = {
        "status": "RESEARCH_ONLY_NOT_A_PRODUCTION_FILTER",
        "data_start": str(trades["available"].min()),
        "data_end": str(trades["available"].max()),
        "sample": metrics(trades),
        "timeframes": list(TIMEFRAMES),
        "completed_session_horizons": list(HORIZONS),
        "causality": "Month M uses only bars completed before the UTC open of month M.",
        "episode_warning": "Adaptive episodes use realized outcomes and are descriptive only.",
        "block_warning": "Fixed four-month blocks are descriptive and use no optimized boundary placement.",
        "detector": {
            "macro": "median H1/H2/H4/D1 return over the same 100 completed D1 sessions",
            "macro_hysteresis_pct": args.hysteresis_pct,
            "transition": "median H1/H2 return over the same 5 completed D1 sessions",
            "phase_labels": ["UP_ALIGNED", "UP_PULLBACK", "DOWN_ALIGNED", "DOWN_REBOUND"],
        },
        "current_month": {
            "month": current["month"],
            "macro_regime": current["macro_regime"],
            "macro_regime_age_months": int(current["macro_regime_age_months"]),
            "causal_market_phase": current["causal_market_phase"],
            "all_tf_ret_100s_pct": None if pd.isna(current["all_tf_ret_100s_pct"]) else float(current["all_tf_ret_100s_pct"]),
            "fast_h1_h2_ret_5s_pct": None if pd.isna(current["fast_h1_h2_ret_5s_pct"]) else float(current["fast_h1_h2_ret_5s_pct"]),
        },
        "phase_performance": {
            name: grouped_metrics(frame, "causal_market_phase") for name, frame in splits.items()
        },
        "fixed_four_month_blocks": blocks.to_dict(orient="records"),
        "episodes": episodes.to_dict(orient="records"),
    }

    args.out_prefix.parent.mkdir(parents=True, exist_ok=True)
    monthly.to_csv(args.out_prefix.with_suffix(".monthly.csv"), index=False)
    blocks.to_csv(args.out_prefix.with_suffix(".blocks4.csv"), index=False)
    episodes.to_csv(args.out_prefix.with_suffix(".episodes.csv"), index=False)
    args.out_prefix.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report["current_month"], indent=2))
    print(episodes.to_string(index=False))


if __name__ == "__main__":
    main()



