#!/usr/bin/env python3
"""Causal structural-entry experiments for JP225 Sol Advanced.

The production signal route and fixed 400-price-unit / 2R geometry are kept.
Only setups whose selected direction conflicts with closed H4/D1 structure are
allowed to wait briefly for a better/confirmed fill. Every policy has a market
fallback so frequency is not intentionally filtered.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from numba import njit


RISK_PRICE = 400.0


@njit(cache=True)
def simulate_policy(bar_time, open_, high, low, close, setup_time, reference,
                    direction, exit_time, active, kind, offset_r, wait_minutes):
    n = len(setup_time)
    filled = np.zeros(n, np.uint8)
    won = np.zeros(n, np.uint8)
    pnl_r = np.zeros(n, np.float64)
    for row in range(n):
        start = np.searchsorted(bar_time, setup_time[row])
        end = len(bar_time) if exit_time[row] <= 0 else np.searchsorted(bar_time, exit_time[row])
        if start >= end or start >= len(bar_time):
            continue

        entry_index = start
        entry = reference[row]
        if active[row]:
            cutoff = setup_time[row] + wait_minutes * 60 * 1_000_000_000
            fallback = np.searchsorted(bar_time, cutoff)
            if fallback >= end:
                continue
            found = False
            target = reference[row]
            if kind == 1:  # pullback, then market fallback
                target = reference[row] - direction[row] * offset_r * RISK_PRICE
                for i in range(start, fallback):
                    touched = low[i] <= target if direction[row] > 0 else high[i] >= target
                    if touched:
                        entry_index = i
                        better_gap = open_[i] < target if direction[row] > 0 else open_[i] > target
                        entry = open_[i] if better_gap else target
                        found = True
                        break
            elif kind == 2:  # breakout, then market fallback
                target = reference[row] + direction[row] * offset_r * RISK_PRICE
                for i in range(start, fallback):
                    touched = high[i] >= target if direction[row] > 0 else low[i] <= target
                    if touched:
                        entry_index = i
                        worse_gap = open_[i] > target if direction[row] > 0 else open_[i] < target
                        entry = open_[i] if worse_gap else target
                        found = True
                        break
            elif kind == 3:  # adverse probe followed by reference reclaim
                probe = reference[row] - direction[row] * offset_r * RISK_PRICE
                probed = False
                for i in range(start, fallback):
                    if not probed:
                        probed = low[i] <= probe if direction[row] > 0 else high[i] >= probe
                    reclaimed = close[i] >= reference[row] if direction[row] > 0 else close[i] <= reference[row]
                    if probed and reclaimed and i + 1 < end:
                        entry_index = i + 1
                        entry = open_[entry_index]
                        found = True
                        break
            if kind == 4:  # fixed causal delay
                found = False
            if not found:
                entry_index = fallback
                entry = open_[entry_index]

        filled[row] = 1
        sl = entry - direction[row] * RISK_PRICE
        tp = entry + direction[row] * 2.0 * RISK_PRICE
        exited = False
        for i in range(entry_index, end):
            hit_sl = low[i] <= sl if direction[row] > 0 else high[i] >= sl
            hit_tp = high[i] >= tp if direction[row] > 0 else low[i] <= tp
            if hit_sl:  # conservative when both levels occur in one M1 bar
                pnl_r[row] = -1.0
                exited = True
                break
            if hit_tp:
                won[row] = 1
                pnl_r[row] = 2.0
                exited = True
                break
        if not exited:
            exit_price = open_[end] if end < len(open_) else close[len(close) - 1]
            pnl_r[row] = direction[row] * (exit_price - entry) / RISK_PRICE
            won[row] = 1 if pnl_r[row] > 0.0 else 0
    return filled, won, pnl_r


def next_opposite_times(times: np.ndarray, directions: np.ndarray) -> np.ndarray:
    result = np.zeros(len(times), dtype=np.int64)
    for i in range(len(times)):
        later = np.flatnonzero(directions[i + 1:] != directions[i])
        if len(later):
            result[i] = times[i + 1 + int(later[0])]
    return result


def summary(frame: pd.DataFrame, filled: np.ndarray, won: np.ndarray, pnl_r: np.ndarray) -> dict:
    result = {
        "trades": int(filled.sum()),
        "retention": float(filled.mean()),
        "wins": int((won * filled).sum()),
        "wr": float(won[filled.astype(bool)].mean()) if filled.any() else None,
        "net_r": float((pnl_r * filled).sum()),
        "by_year": {},
    }
    years = frame["year"].to_numpy(int)
    for year in sorted(np.unique(years)):
        mask = (years == year) & filled.astype(bool)
        result["by_year"][str(year)] = {
            "trades": int(mask.sum()),
            "wr": float(won[mask].mean()) if mask.any() else None,
            "net_r": float(pnl_r[mask].sum()),
        }
    return result


def build_masks(frame: pd.DataFrame, route_sign: np.ndarray) -> dict[str, np.ndarray]:
    aligned = {}
    for name in ("h41_rev", "h43_rev", "h46_rev", "h4bod_rev", "d1bod_rev", "daymov_rev"):
        aligned[name] = route_sign * frame[name].to_numpy(float) >= 0.0
    mismatch_votes = sum((~value).astype(int) for value in aligned.values())
    h4_mismatch = (~aligned["h41_rev"]).astype(int) + (~aligned["h43_rev"]).astype(int) + (~aligned["h46_rev"]).astype(int)
    d1_mismatch = (~aligned["d1bod_rev"]).astype(int) + (~aligned["daymov_rev"]).astype(int)

    selected_h4_room = np.where(
        route_sign > 0, frame["h4_srcroom6"].to_numpy(float), frame["h4_opproom6"].to_numpy(float)
    )
    selected_d1_room = np.where(
        route_sign > 0, frame["d1_srcroom5"].to_numpy(float), frame["d1_opproom5"].to_numpy(float)
    )
    dev = frame["year"].to_numpy(int) <= 2022
    h4_low = selected_h4_room <= np.nanquantile(selected_h4_room[dev], 0.25)
    d1_low = selected_d1_room <= np.nanquantile(selected_d1_room[dev], 0.25)

    masks = {
        "h4_fast_mismatch": ~aligned["h41_rev"],
        "h4_mid_mismatch": ~aligned["h43_rev"],
        "h4_slow_mismatch": ~aligned["h46_rev"],
        "d1_body_mismatch": ~aligned["d1bod_rev"],
        "day_move_mismatch": ~aligned["daymov_rev"],
        "h4_two_mismatch": h4_mismatch >= 2,
        "h4_all_mismatch": h4_mismatch >= 3,
        "d1_both_mismatch": d1_mismatch >= 2,
        "all_vote3_mismatch": mismatch_votes >= 3,
        "all_vote4_mismatch": mismatch_votes >= 4,
        "h4_and_d1_mismatch": (h4_mismatch >= 2) & (d1_mismatch >= 1),
        "h4_low_room": h4_low,
        "d1_low_room": d1_low,
        "both_low_room": h4_low & d1_low,
        "mismatch_and_h4_low_room": (mismatch_votes >= 3) & h4_low,
        "mismatch_and_d1_low_room": (mismatch_votes >= 3) & d1_low,
    }
    return {name: value.astype(np.uint8) for name, value in masks.items()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("v14_dataset", type=Path)
    parser.add_argument("context_dataset", type=Path)
    parser.add_argument("raw_dataset", type=Path)
    parser.add_argument("m1_rates", type=Path)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_structural_entry_router.json"))
    args = parser.parse_args()

    v14 = pd.read_csv(args.v14_dataset, parse_dates=["available"])
    context = pd.read_csv(args.context_dataset, parse_dates=["available"])
    raw = pd.read_parquet(args.raw_dataset)
    raw["available"] = pd.to_datetime(raw["available"], utc=True)
    keep_context = [
        "available", "h41_rev", "h43_rev", "h46_rev", "h4bod_rev",
        "d1bod_rev", "daymov_rev",
    ]
    keep_raw = ["h4_srcroom6", "h4_opproom6", "d1_srcroom5", "d1_opproom5"]
    # The paired counterfactual file contains one same-timestamp opposite setup
    # that the path-dependent v14 audit de-duplicates. Keep rows positionally
    # aligned, then select the context row whose logged quality matches v14.
    context_features = pd.concat(
        [context[keep_context].reset_index(drop=True), raw[keep_raw].reset_index(drop=True)], axis=1
    )
    frame = v14.merge(context_features, on="available")
    frame["_match_error"] = (frame["q_rev"] - frame["quality"]).abs()
    frame = frame.sort_values(["index", "_match_error"]).drop_duplicates("index", keep="first")
    if len(frame) != len(v14):
        raise RuntimeError(f"Expected {len(v14)} one-to-one setups, matched {len(frame)}")
    frame = frame.sort_values("available").reset_index(drop=True)
    frame["year"] = frame["available"].dt.year

    source = frame["src_rev"].to_numpy(np.int64)
    continuation = frame["is_continuation"].astype(bool).to_numpy()
    route_sign = np.where(continuation, -1, 1)
    direction = source * route_sign
    setup_time = frame["available"].astype("int64").to_numpy()
    exit_time = next_opposite_times(setup_time, direction)
    reference = frame["entry"].to_numpy(float)

    rates = pd.read_parquet(args.m1_rates).sort_values("time").reset_index(drop=True)
    bar_time = pd.to_datetime(rates["time"], utc=True).astype("int64").to_numpy()
    open_ = rates["open"].to_numpy(float)
    high = rates["high"].to_numpy(float)
    low = rates["low"].to_numpy(float)
    close = rates["close"].to_numpy(float)

    inactive = np.zeros(len(frame), np.uint8)
    baseline_arrays = simulate_policy(
        bar_time, open_, high, low, close, setup_time, reference, direction,
        exit_time, inactive, 0, 0.0, 0,
    )
    baseline = summary(frame, *baseline_arrays)
    masks = build_masks(frame, route_sign)
    policies = []
    kinds = {1: "pullback", 2: "breakout", 3: "adverse_reclaim", 4: "fixed_delay"}
    for mask_name, active in masks.items():
        for wait in (15, 30, 60, 120, 240):
            for kind, kind_name in kinds.items():
                offsets = (0.05, 0.10, 0.20, 0.33) if kind != 4 else (0.0,)
                for offset in offsets:
                    arrays = simulate_policy(
                        bar_time, open_, high, low, close, setup_time, reference, direction,
                        exit_time, active, kind, offset, wait,
                    )
                    item = {
                        "mask": mask_name,
                        "support": float(active.mean()),
                        "policy": kind_name,
                        "offset_r": offset,
                        "wait_minutes": wait,
                        **summary(frame, *arrays),
                    }
                    policies.append(item)

    def rank_key(item):
        yearly = item["by_year"]
        dev = [yearly[str(y)]["wr"] or 0.0 for y in (2021, 2022, 2023)]
        return min(dev), sum(dev) / len(dev), item["retention"], item["wr"] or 0.0

    ranked = sorted(policies, key=rank_key, reverse=True)
    report = {
        "protocol": "causal M1 OHLC screen; v14 direction and fixed 400-price/2R geometry; conditional wait with mandatory market fallback",
        "warning": "research screen only; any finalist requires the real path-dependent Advanced EA audit",
        "baseline": baseline,
        "candidates": len(policies),
        "top_development_validation": ranked[:50],
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("BASE", baseline["trades"], f"{100 * baseline['wr']:.2f}")
    for item in ranked[:30]:
        years = " ".join(
            f"{year}:{100 * item['by_year'][str(year)]['wr']:.1f}"
            for year in (2021, 2022, 2023, 2024, 2025, 2026)
        )
        print(
            item["mask"], item["policy"], item["offset_r"], item["wait_minutes"],
            f"all={100 * item['wr']:.2f}", f"ret={100 * item['retention']:.1f}", years,
        )


if __name__ == "__main__":
    main()
