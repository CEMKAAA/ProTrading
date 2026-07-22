#!/usr/bin/env python3
"""Research asymmetric causal OCO direction routing with mandatory fallback."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


RISK_PRICE = 400.0


@dataclass(frozen=True)
class Router:
    source_probe_r: float
    opposite_probe_r: float
    wait_minutes: int
    momentum: bool
    fallback: str

    @property
    def name(self) -> str:
        mode = "mom" if self.momentum else "rej"
        return f"{mode}_s{self.source_probe_r:g}_o{self.opposite_probe_r:g}_w{self.wait_minutes}_{self.fallback}"


def fallback_continuation(frame: pd.DataFrame, name: str) -> np.ndarray:
    if name == "reversal":
        return np.zeros(len(frame), dtype=bool)
    hour = frame["available"].dt.hour
    weekday = frame["available"].dt.weekday
    session = hour.between(14, 22)
    quality = frame["q_rev"]
    return ((session & weekday.between(0, 3))
            | (~session & quality.gt(2.17) & quality.le(3.14))).to_numpy(bool)


def resolve_router(frame: pd.DataFrame, bars: dict[str, np.ndarray], router: Router) -> pd.DataFrame:
    fallback_cont = fallback_continuation(frame, router.fallback)
    source_dirs = frame["src_rev"].to_numpy(int)
    available = frame["available"].astype("int64").to_numpy()
    references = frame["entry_rev"].to_numpy(float)
    rows = []
    for i in range(len(frame)):
        start = int(np.searchsorted(bars["time"], available[i], side="left"))
        cutoff = available[i] + router.wait_minutes * 60 * 1_000_000_000
        end = int(np.searchsorted(bars["time"], cutoff, side="left"))
        if i + 1 < len(frame):
            next_signal = int(np.searchsorted(bars["time"], available[i + 1], side="left"))
            end = min(end, next_signal)
        end = max(start + 1, min(end, len(bars["time"])))
        src = source_dirs[i]
        src_level = references[i] + src * router.source_probe_r * RISK_PRICE
        opp_level = references[i] - src * router.opposite_probe_r * RISK_PRICE
        high = bars["high"][start:end]
        low = bars["low"][start:end]
        src_hits = np.flatnonzero(high >= src_level) if src > 0 else np.flatnonzero(low <= src_level)
        opp_hits = np.flatnonzero(low <= opp_level) if src > 0 else np.flatnonzero(high >= opp_level)
        src_hit = int(src_hits[0]) if len(src_hits) else None
        opp_hit = int(opp_hits[0]) if len(opp_hits) else None
        ambiguous = src_hit is not None and opp_hit is not None and src_hit == opp_hit
        if src_hit is None and opp_hit is None or ambiguous:
            direction = -src if fallback_cont[i] else src
            entry_index = end
            if entry_index >= len(bars["time"]):
                entry_index = len(bars["time"]) - 1
            entry = float(bars["open"][entry_index])
            trigger = "fallback" if not ambiguous else "ambiguous_fallback"
        else:
            source_first = opp_hit is None or (src_hit is not None and src_hit < opp_hit)
            direction = src if source_first == router.momentum else -src
            relative_index = src_hit if source_first else opp_hit
            entry_index = start + int(relative_index)
            trigger_level = src_level if source_first else opp_level
            open_price = float(bars["open"][entry_index])
            if direction > 0:
                entry = max(open_price, trigger_level) if source_first == router.momentum else open_price
            else:
                entry = min(open_price, trigger_level) if source_first == router.momentum else open_price
            trigger = "source" if source_first else "opposite"
        rows.append({"direction": direction, "entry_index": entry_index, "entry": entry, "trigger": trigger})
    return pd.DataFrame(rows)


def next_opposite_available(available: np.ndarray, directions: np.ndarray) -> np.ndarray:
    result = np.zeros(len(available), dtype=np.int64)
    next_by_direction = {1: 0, -1: 0}
    for i in range(len(available) - 1, -1, -1):
        result[i] = next_by_direction[-int(directions[i])]
        next_by_direction[int(directions[i])] = int(available[i])
    return result


def simulate(frame: pd.DataFrame, bars: dict[str, np.ndarray], decisions: pd.DataFrame) -> pd.DataFrame:
    available = frame["available"].astype("int64").to_numpy()
    directions = decisions["direction"].to_numpy(int)
    exits = next_opposite_available(available, directions)
    rows = []
    for i, decision in enumerate(decisions.itertuples(index=False)):
        entry_index = int(decision.entry_index)
        if exits[i] and bars["time"][entry_index] >= exits[i]:
            rows.append({"year": int(frame.iloc[i].year), "filled": False, "won": False, "r": 0.0})
            continue
        end = (int(np.searchsorted(bars["time"], exits[i], side="left"))
               if exits[i] else len(bars["time"]))
        entry = float(decision.entry)
        direction = int(decision.direction)
        sl = entry - direction * RISK_PRICE
        tp = entry + direction * 2.0 * RISK_PRICE
        won = False
        pnl_r = 0.0
        closed = False
        for bar in range(entry_index, end):
            hit_sl = bars["low"][bar] <= sl if direction > 0 else bars["high"][bar] >= sl
            hit_tp = bars["high"][bar] >= tp if direction > 0 else bars["low"][bar] <= tp
            if hit_sl:
                won, pnl_r, closed = False, -1.0, True
                break
            if hit_tp:
                won, pnl_r, closed = True, 2.0, True
                break
        if not closed:
            exit_price = bars["open"][end] if end < len(bars["open"]) else bars["close"][-1]
            pnl_r = direction * (exit_price - entry) / RISK_PRICE
            won = pnl_r > 0.0
        rows.append({"year": int(frame.iloc[i].year), "filled": True, "won": won, "r": float(pnl_r)})
    return pd.DataFrame(rows)


def summary(result: pd.DataFrame) -> dict:
    filled = result[result["filled"]]
    by_year = {}
    for year, all_year in result.groupby("year"):
        trades = all_year[all_year["filled"]]
        by_year[str(int(year))] = {
            "setups": int(len(all_year)), "trades": int(len(trades)),
            "retention": float(len(trades) / len(all_year)),
            "wins": int(trades["won"].sum()),
            "wr": float(trades["won"].mean()) if len(trades) else None,
            "net_r": float(trades["r"].sum()),
        }
    return {"trades": int(len(filled)), "retention": float(len(filled) / len(result)),
            "wins": int(filled["won"].sum()), "wr": float(filled["won"].mean()),
            "net_r": float(filled["r"].sum()), "by_year": by_year}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("m1_rates", type=Path)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_sequential_router.json"))
    args = parser.parse_args()
    frame = pd.read_csv(args.dataset, low_memory=False)
    frame["available"] = pd.to_datetime(frame["available"], utc=True)
    frame["year"] = frame["available"].dt.year
    rates = pd.read_parquet(args.m1_rates).sort_values("time").reset_index(drop=True)
    bars = {name: rates[name].to_numpy(float) for name in ("open", "high", "low", "close")}
    bars["time"] = pd.to_datetime(rates["time"], utc=True).astype("int64").to_numpy()
    probes = (0.025, 0.05, 0.10, 0.20, 0.33, 0.50)
    routers = [
        Router(source, opposite, wait, momentum, fallback)
        for source in probes for opposite in probes for wait in (60, 240, 720)
        for momentum in (False, True) for fallback in ("reversal", "v14")
    ]
    rows = []
    for router in routers:
        decisions = resolve_router(frame, bars, router)
        result = simulate(frame, bars, decisions)
        rows.append({"router": router.name, **summary(result)})
    dev_years = {"2021", "2022", "2023"}
    holdout_years = {"2024", "2025", "2026"}
    for row in rows:
        row["dev_min_wr"] = min(row["by_year"][year]["wr"] or 0.0 for year in dev_years)
        row["holdout_min_wr"] = min(row["by_year"][year]["wr"] or 0.0 for year in holdout_years)
        row["full_year_min_retention"] = min(
            row["by_year"][year]["retention"] for year in dev_years | {"2024", "2025"}
        )
    ranked_dev = sorted(rows, key=lambda row: (row["dev_min_wr"], row["wr"]), reverse=True)
    high_retention = [row for row in ranked_dev if row["full_year_min_retention"] >= 0.95]
    report = {
        "warning": "M1 OHLC research approximation; finalists require MT5 EA-path validation",
        "geometry": {"sl_price": RISK_PRICE, "target_r": 2.0},
        "candidate_count": len(rows),
        "top_development": ranked_dev[:30],
        "top_high_retention_development": high_retention[:30],
        "all": rows,
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"candidate_count": len(rows), "top_high_retention": high_retention[:15]}, indent=2))


if __name__ == "__main__":
    main()
