#!/usr/bin/env python3
"""Counterfactual causal entry-path research for JP225 Sol setups.

This is an OHLC research simulator, not a replacement for the EA audit. Any
surviving candidate must be implemented in Advanced and rerun through MT5.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


RISK_PRICE = 400.0  # JP225m 4000 configured pips at 0.1 price units.


@dataclass(frozen=True)
class EntryPolicy:
    name: str
    kind: str
    offset_r: float = 0.0
    wait_minutes: int = 0


def route_vector(frame: pd.DataFrame, name: str) -> np.ndarray:
    if name == "reversal":
        return np.zeros(len(frame), dtype=bool)
    if name == "continuation":
        return np.ones(len(frame), dtype=bool)
    hour = frame["available"].dt.hour
    weekday = frame["available"].dt.weekday
    session = hour.between(14, 22)
    quality = frame["q_rev"]
    return (
        (session & weekday.between(0, 3))
        | (~session & quality.gt(2.17) & quality.le(3.14))
    ).to_numpy(bool)


def next_opposite_times(times: np.ndarray, directions: np.ndarray) -> np.ndarray:
    result = np.zeros(len(times), dtype=np.int64)
    for i in range(len(times)):
        later = np.flatnonzero(directions[i + 1:] != directions[i])
        if len(later):
            result[i] = times[i + 1 + int(later[0])]
    return result


def first_touch(open_: np.ndarray, high: np.ndarray, low: np.ndarray, target: float,
                direction: int, kind: str) -> tuple[int, float] | None:
    if kind == "pullback":
        hit = low <= target if direction > 0 else high >= target
        indices = np.flatnonzero(hit)
        if not len(indices):
            return None
        i = int(indices[0])
        better_gap = open_[i] < target if direction > 0 else open_[i] > target
        return i, float(open_[i] if better_gap else target)
    hit = high >= target if direction > 0 else low <= target
    indices = np.flatnonzero(hit)
    if not len(indices):
        return None
    i = int(indices[0])
    worse_gap = open_[i] > target if direction > 0 else open_[i] < target
    return i, float(open_[i] if worse_gap else target)


def find_entry(policy: EntryPolicy, bars: dict[str, np.ndarray], start: int, end: int,
               direction: int, reference: float) -> tuple[int, float] | None:
    if end <= start:
        return None
    wait_end = end
    if policy.wait_minutes > 0:
        cutoff = bars["time"][start] + policy.wait_minutes * 60 * 1_000_000_000
        wait_end = min(end, int(np.searchsorted(bars["time"], cutoff, side="left")))
    if policy.kind == "market":
        return start, float(bars["open"][start])
    if policy.kind in {"pullback", "breakout"}:
        sign = -1.0 if policy.kind == "pullback" else 1.0
        target = reference + direction * sign * policy.offset_r * RISK_PRICE
        touched = first_touch(
            bars["open"][start:wait_end], bars["high"][start:wait_end],
            bars["low"][start:wait_end], target, direction, policy.kind,
        )
        return None if touched is None else (start + touched[0], touched[1])
    if policy.kind == "pullback_reclaim":
        pullback = reference - direction * policy.offset_r * RISK_PRICE
        touched = first_touch(
            bars["open"][start:wait_end], bars["high"][start:wait_end],
            bars["low"][start:wait_end], pullback, direction, "pullback",
        )
        if touched is None:
            return None
        touch_index = start + touched[0]
        closes = bars["close"][touch_index:wait_end]
        reclaimed = closes >= reference if direction > 0 else closes <= reference
        indices = np.flatnonzero(reclaimed)
        if not len(indices):
            return None
        confirmation = touch_index + int(indices[0])
        entry_index = confirmation + 1
        if entry_index >= end:
            return None
        return entry_index, float(bars["open"][entry_index])
    raise ValueError(policy.kind)


def simulate_trade(bars: dict[str, np.ndarray], entry_index: int, end: int,
                   entry: float, direction: int) -> tuple[bool, str, float]:
    sl = entry - direction * RISK_PRICE
    tp = entry + direction * RISK_PRICE * 2.0
    for i in range(entry_index, end):
        hit_sl = bars["low"][i] <= sl if direction > 0 else bars["high"][i] >= sl
        hit_tp = bars["high"][i] >= tp if direction > 0 else bars["low"][i] <= tp
        if hit_sl and hit_tp:
            return False, "same_bar_sl", -1.0
        if hit_sl:
            return False, "sl", -1.0
        if hit_tp:
            return True, "tp", 2.0
    if end < len(bars["open"]):
        pnl_r = direction * (bars["open"][end] - entry) / RISK_PRICE
        return pnl_r > 0.0, "reverse", float(pnl_r)
    pnl_r = direction * (bars["close"][end - 1] - entry) / RISK_PRICE
    return pnl_r > 0.0, "open_end", float(pnl_r)


def evaluate(frame: pd.DataFrame, bars: dict[str, np.ndarray], route_name: str,
             policy: EntryPolicy) -> pd.DataFrame:
    continuation = route_vector(frame, route_name)
    source = frame["src_rev"].to_numpy(int)
    directions = np.where(continuation, -source, source)
    available_ns = frame["available"].astype("int64").to_numpy()
    exits = next_opposite_times(available_ns, directions)
    rows = []
    for i, setup in enumerate(frame.itertuples(index=False)):
        start = int(np.searchsorted(bars["time"], available_ns[i], side="left"))
        end = (int(np.searchsorted(bars["time"], exits[i], side="left"))
               if exits[i] else len(bars["time"]))
        found = find_entry(policy, bars, start, end, int(directions[i]), float(setup.entry_rev))
        if found is None:
            rows.append({"available": setup.available, "year": setup.year, "filled": False,
                         "won": False, "exit_reason": "unfilled", "r": 0.0})
            continue
        entry_index, entry = found
        won, reason, pnl_r = simulate_trade(bars, entry_index, end, entry, int(directions[i]))
        rows.append({"available": setup.available, "year": setup.year, "filled": True,
                     "won": won, "exit_reason": reason, "r": pnl_r})
    return pd.DataFrame(rows)


def summarize(result: pd.DataFrame) -> dict:
    filled = result[result["filled"]]
    yearly = {}
    for year, all_year in result.groupby("year"):
        trades = all_year[all_year["filled"]]
        yearly[str(int(year))] = {
            "setups": int(len(all_year)), "trades": int(len(trades)),
            "retention": float(len(trades) / len(all_year)),
            "wins": int(trades["won"].sum()),
            "wr": float(trades["won"].mean()) if len(trades) else None,
            "net_r": float(trades["r"].sum()),
        }
    return {
        "setups": int(len(result)), "trades": int(len(filled)),
        "retention": float(len(filled) / len(result)),
        "wins": int(filled["won"].sum()),
        "wr": float(filled["won"].mean()) if len(filled) else None,
        "net_r": float(filled["r"].sum()), "by_year": yearly,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("m1_rates", type=Path)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_entry_path_research.json"))
    args = parser.parse_args()
    frame = pd.read_csv(args.dataset, low_memory=False)
    frame["available"] = pd.to_datetime(frame["available"], utc=True)
    frame["year"] = frame["available"].dt.year
    rates = pd.read_parquet(args.m1_rates).sort_values("time").reset_index(drop=True)
    bars = {name: rates[name].to_numpy(float) for name in ("open", "high", "low", "close")}
    bars["time"] = pd.to_datetime(rates["time"], utc=True).astype("int64").to_numpy()

    policies = [EntryPolicy("market", "market")]
    for wait in (60, 240, 720, 1440):
        for offset in (0.025, 0.05, 0.10, 0.15, 0.20, 0.25, 0.33, 0.50):
            tag = str(offset).replace(".", "p")
            policies.append(EntryPolicy(f"pullback_{tag}_w{wait}", "pullback", offset, wait))
            policies.append(EntryPolicy(f"breakout_{tag}_w{wait}", "breakout", offset, wait))
            policies.append(EntryPolicy(f"pullback_reclaim_{tag}_w{wait}", "pullback_reclaim", offset, wait))

    report_rows = []
    detailed = []
    for route_name in ("reversal", "v14"):
        for policy in policies:
            result = evaluate(frame, bars, route_name, policy)
            summary = summarize(result)
            report_rows.append({"route": route_name, "policy": policy.name, **summary})
            result["route"] = route_name
            result["policy"] = policy.name
            detailed.append(result)
    ranked = sorted(
        report_rows,
        key=lambda row: (
            min((data["wr"] or 0.0) for year, data in row["by_year"].items() if year in {"2021", "2022", "2023"}),
            row["wr"] or 0.0,
        ),
        reverse=True,
    )
    report = {
        "warning": "M1 OHLC approximation; finalists require full EA-path validation",
        "geometry": {"sl_price": RISK_PRICE, "target_r": 2.0},
        "candidates": len(report_rows),
        "top_development_validation": ranked[:40],
        "all": report_rows,
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    pd.concat(detailed, ignore_index=True).to_parquet(args.out.with_suffix(".trades.parquet"), index=False)
    print(json.dumps({"candidates": len(report_rows), "top": ranked[:15]}, indent=2))


if __name__ == "__main__":
    main()
