#!/usr/bin/env python3
"""Causal online policy selection for JP225 Sol Advanced research.

Every shadow-policy score uses only trades whose result was observable before
the current setup. This prevents unresolved trades and the current trade from
leaking into the routing decision. The script is research-only; any survivor
still requires implementation and full MT5 EA-path validation.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
from numba import njit

from research_sol_sequential_router import (
    RISK_PRICE,
    Router,
    fallback_continuation,
    next_opposite_available,
    resolve_router,
)


BAR_NS = 60 * 1_000_000_000


@dataclass(frozen=True)
class Selector:
    library: str
    window: int
    minimum: int
    margin_r: float
    switch_confirmations: int

    @property
    def name(self) -> str:
        return (
            f"{self.library}_n{self.window}_min{self.minimum}_"
            f"m{self.margin_r:g}_k{self.switch_confirmations}"
        )


def market_decisions(frame: pd.DataFrame, bars: dict[str, np.ndarray], route: str) -> pd.DataFrame:
    continuation = fallback_continuation(frame, route)
    source = frame["src_rev"].to_numpy(int)
    directions = np.where(continuation, -source, source)
    available = frame["available"].astype("int64").to_numpy()
    indices = np.searchsorted(bars["time"], available, side="left")
    indices = np.minimum(indices, len(bars["time"]) - 1)
    return pd.DataFrame({
        "direction": directions,
        "entry_index": indices.astype(int),
        "entry": bars["open"][indices].astype(float),
        "trigger": np.repeat("market", len(frame)),
    })


@njit(cache=True)
def _simulate_core(
    times: np.ndarray,
    highs: np.ndarray,
    lows: np.ndarray,
    opens: np.ndarray,
    closes: np.ndarray,
    directions: np.ndarray,
    entry_indices: np.ndarray,
    entries: np.ndarray,
    reverse_times: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    count = len(directions)
    filled = np.ones(count, dtype=np.bool_)
    won = np.zeros(count, dtype=np.bool_)
    pnl_r = np.zeros(count, dtype=np.float64)
    entry_time_ns = np.zeros(count, dtype=np.int64)
    exit_known_ns = np.zeros(count, dtype=np.int64)
    reason_code = np.zeros(count, dtype=np.int8)
    for i in range(count):
        entry_index = int(entry_indices[i])
        entry_time = int(times[entry_index])
        reverse_time = int(reverse_times[i])
        if reverse_time != 0 and entry_time >= reverse_time:
            filled[i] = False
            exit_known_ns[i] = reverse_time
            reason_code[i] = 4
            continue
        end = int(np.searchsorted(times, reverse_time, side="left")) if reverse_time != 0 else len(times)
        entry = float(entries[i])
        direction = int(directions[i])
        sl = entry - direction * RISK_PRICE
        tp = entry + direction * 2.0 * RISK_PRICE
        entry_time_ns[i] = entry_time
        closed = False
        for bar in range(entry_index, end):
            hit_sl = lows[bar] <= sl if direction > 0 else highs[bar] >= sl
            hit_tp = highs[bar] >= tp if direction > 0 else lows[bar] <= tp
            # Preserve the adverse same-bar ordering used by the Python reference.
            if hit_sl:
                pnl_r[i] = -1.0
                exit_known_ns[i] = int(times[bar] + BAR_NS)
                reason_code[i] = 1
                closed = True
                break
            if hit_tp:
                won[i] = True
                pnl_r[i] = 2.0
                exit_known_ns[i] = int(times[bar] + BAR_NS)
                reason_code[i] = 2
                closed = True
                break
        if not closed:
            if reverse_time != 0:
                exit_price = float(opens[end]) if end < len(opens) else float(closes[-1])
                exit_known_ns[i] = reverse_time
                reason_code[i] = 3
            else:
                exit_price = float(closes[-1])
                exit_known_ns[i] = int(times[-1] + BAR_NS)
                reason_code[i] = 5
            pnl_r[i] = direction * (exit_price - entry) / RISK_PRICE
            won[i] = pnl_r[i] > 0.0
    return filled, won, pnl_r, entry_time_ns, exit_known_ns, reason_code


def simulate_detailed(
    frame: pd.DataFrame,
    bars: dict[str, np.ndarray],
    decisions: pd.DataFrame,
) -> pd.DataFrame:
    available = frame["available"].astype("int64").to_numpy()
    directions = decisions["direction"].to_numpy(dtype=np.int64)
    reverse_times = next_opposite_available(available, directions)
    values = _simulate_core(
        bars["time"], bars["high"], bars["low"], bars["open"], bars["close"],
        directions,
        decisions["entry_index"].to_numpy(dtype=np.int64),
        decisions["entry"].to_numpy(dtype=np.float64),
        reverse_times,
    )
    reason_labels = np.asarray([
        "unknown", "sl", "tp", "reverse", "unfilled_before_reverse", "open_end"
    ], dtype=object)
    return pd.DataFrame({
        "filled": values[0],
        "won": values[1],
        "r": values[2],
        "entry_time_ns": values[3],
        "exit_known_ns": values[4],
        "exit_reason": reason_labels[values[5]],
    })

def completed_score(
    shadow: pd.DataFrame,
    now_ns: int,
    window: int,
    minimum: int,
) -> tuple[float, int]:
    known = shadow[(shadow["filled"]) & (shadow["exit_known_ns"] <= now_ns)]
    if len(known) < minimum:
        return float("-inf"), int(len(known))
    recent = known.sort_values("exit_known_ns").tail(window)
    # Fixed 2R geometry makes mean realized R the direct expectancy estimate.
    return float(recent["r"].mean()), int(len(recent))


def completed_score_series(
    shadow: pd.DataFrame,
    setup_times_ns: np.ndarray,
    window: int,
    minimum: int,
) -> tuple[np.ndarray, np.ndarray]:
    known = shadow[shadow["filled"]].sort_values("exit_known_ns")
    exits = known["exit_known_ns"].to_numpy(dtype=np.int64)
    realized = known["r"].to_numpy(dtype=np.float64)
    cumulative = np.concatenate(([0.0], np.cumsum(realized)))
    positions = np.searchsorted(exits, setup_times_ns, side="right")
    counts = positions.astype(np.int64)
    starts = np.maximum(0, positions - window)
    sums = cumulative[positions] - cumulative[starts]
    denominators = positions - starts
    scores = np.full(len(setup_times_ns), -np.inf, dtype=np.float64)
    eligible = positions >= minimum
    scores[eligible] = sums[eligible] / denominators[eligible]
    return scores, counts

def select_online(
    frame: pd.DataFrame,
    policy_names: list[str],
    shadows: dict[str, pd.DataFrame],
    selector: Selector,
) -> tuple[np.ndarray, pd.DataFrame]:
    selected: list[str] = []
    diagnostics: list[dict[str, object]] = []
    active = "v14_market"
    pending = ""
    pending_count = 0
    setup_times_ns = frame["available"].astype("int64").to_numpy()
    score_paths: dict[str, np.ndarray] = {}
    count_paths: dict[str, np.ndarray] = {}
    for policy in policy_names:
        score_paths[policy], count_paths[policy] = completed_score_series(
            shadows[policy], setup_times_ns, selector.window, selector.minimum
        )
    for row_index, setup in enumerate(frame.itertuples(index=False)):
        scores = {policy: float(score_paths[policy][row_index]) for policy in policy_names}
        counts = {policy: int(count_paths[policy][row_index]) for policy in policy_names}
        finite = [name for name in policy_names if np.isfinite(scores[name])]
        desired = max(finite, key=lambda name: scores[name]) if finite else "v14_market"
        if desired != active:
            advantage = scores[desired] - scores.get(active, float("-inf"))
            if advantage >= selector.margin_r:
                if pending == desired:
                    pending_count += 1
                else:
                    pending, pending_count = desired, 1
                if pending_count >= selector.switch_confirmations:
                    active = desired
                    pending, pending_count = "", 0
            else:
                pending, pending_count = "", 0
        else:
            pending, pending_count = "", 0
        selected.append(active)
        diagnostics.append({
            "selected": active,
            "desired": desired,
            **{f"score_{name}": scores[name] for name in policy_names},
            **{f"count_{name}": counts[name] for name in policy_names},
        })
    return np.asarray(selected, dtype=object), pd.DataFrame(diagnostics)


def combine_decisions(
    selected: np.ndarray,
    decisions: dict[str, pd.DataFrame],
) -> pd.DataFrame:
    rows = []
    for i, policy in enumerate(selected):
        row = decisions[str(policy)].iloc[i].to_dict()
        row["policy"] = str(policy)
        rows.append(row)
    return pd.DataFrame(rows)

def combine_shadow_results(
    selected: np.ndarray,
    shadows: dict[str, pd.DataFrame],
) -> pd.DataFrame:
    rows = [shadows[str(policy)].iloc[i].to_dict() for i, policy in enumerate(selected)]
    return pd.DataFrame(rows)


def summarize(frame: pd.DataFrame, results: pd.DataFrame, selected: np.ndarray) -> dict:
    merged = pd.DataFrame({
        "year": frame["year"].to_numpy(int),
        "filled": results["filled"].to_numpy(bool),
        "won": results["won"].to_numpy(bool),
        "r": results["r"].to_numpy(float),
        "policy": selected,
    })
    filled = merged[merged["filled"]]
    by_year: dict[str, dict[str, object]] = {}
    for year, all_year in merged.groupby("year"):
        trades = all_year[all_year["filled"]]
        by_year[str(int(year))] = {
            "setups": int(len(all_year)),
            "trades": int(len(trades)),
            "retention": float(len(trades) / len(all_year)),
            "wins": int(trades["won"].sum()),
            "wr": float(trades["won"].mean()) if len(trades) else None,
            "net_r": float(trades["r"].sum()),
            "policy_counts": {str(k): int(v) for k, v in all_year["policy"].value_counts().items()},
        }
    return {
        "trades": int(len(filled)),
        "retention": float(len(filled) / len(merged)),
        "wins": int(filled["won"].sum()),
        "wr": float(filled["won"].mean()),
        "net_r": float(filled["r"].sum()),
        "by_year": by_year,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("m1_rates", type=Path)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_adaptive_policy.json"))
    args = parser.parse_args()

    frame = pd.read_csv(args.dataset, low_memory=False)
    frame["available"] = pd.to_datetime(frame["available"], utc=True)
    frame["year"] = frame["available"].dt.year
    rates = pd.read_parquet(args.m1_rates).sort_values("time").reset_index(drop=True)
    bars = {name: rates[name].to_numpy(float) for name in ("open", "high", "low", "close")}
    bars["time"] = pd.to_datetime(rates["time"], utc=True).astype("int64").to_numpy()

    decisions = {
        "v14_market": market_decisions(frame, bars, "v14"),
        "oco33": resolve_router(frame, bars, Router(0.33, 0.33, 720, True, "v14")),
        "oco50": resolve_router(frame, bars, Router(0.50, 0.33, 720, True, "v14")),
    }
    shadows = {name: simulate_detailed(frame, bars, policy) for name, policy in decisions.items()}
    libraries = {
        "two": ["v14_market", "oco33"],
        "three": ["v14_market", "oco33", "oco50"],
    }
    selectors = [
        Selector(library, window, minimum, margin, confirmations)
        for library in libraries
        for window in (20, 30, 50, 75, 100, 150, 250)
        for minimum in (10, 20, 30)
        if minimum <= window
        for margin in (0.0, 0.05, 0.10, 0.20)
        for confirmations in (1, 3, 5)
    ]
    development_years = ("2021", "2022", "2023")
    holdout_years = ("2024", "2025", "2026")
    candidates = []
    for selector in selectors:
        policy_names = libraries[selector.library]
        selected, diagnostics = select_online(frame, policy_names, shadows, selector)
        approximate = combine_shadow_results(selected, shadows)
        metrics = summarize(frame, approximate, selected)
        metrics["selector"] = selector.name
        metrics["dev_min_wr"] = min(metrics["by_year"][year]["wr"] or 0.0 for year in development_years)
        metrics["holdout_min_wr"] = min(metrics["by_year"][year]["wr"] or 0.0 for year in holdout_years)
        metrics["full_min_retention"] = min(
            metrics["by_year"][year]["retention"] for year in development_years + holdout_years
        )
        candidates.append({
            "selector": selector,
            "selected": selected,
            "diagnostics": diagnostics,
            "approximate": metrics,
        })

    ranked_approximate = sorted(
        candidates,
        key=lambda item: (item["approximate"]["dev_min_wr"], item["approximate"]["wr"]),
        reverse=True,
    )
    shortlist = []
    seen_paths: set[tuple[str, ...]] = set()
    for candidate in ranked_approximate:
        key = tuple(candidate["selected"].tolist())
        if key in seen_paths:
            continue
        seen_paths.add(key)
        shortlist.append(candidate)
        if len(shortlist) >= 36:
            break

    rows = []
    detail_frames = []
    for candidate in shortlist:
        selector = candidate["selector"]
        selected = candidate["selected"]
        actual_decisions = combine_decisions(selected, decisions)
        result = simulate_detailed(frame, bars, actual_decisions)
        metrics = summarize(frame, result, selected)
        metrics["selector"] = selector.name
        metrics["approx_dev_min_wr"] = candidate["approximate"]["dev_min_wr"]
        metrics["dev_min_wr"] = min(metrics["by_year"][year]["wr"] or 0.0 for year in development_years)
        metrics["holdout_min_wr"] = min(metrics["by_year"][year]["wr"] or 0.0 for year in holdout_years)
        metrics["full_min_retention"] = min(
            metrics["by_year"][year]["retention"] for year in development_years + holdout_years
        )
        rows.append(metrics)
        if len(detail_frames) < 3:
            detail = pd.concat([
                frame[["available", "year"]].reset_index(drop=True),
                candidate["diagnostics"],
                result.add_prefix("actual_"),
            ], axis=1)
            detail["selector"] = selector.name
            detail_frames.append(detail)

    ranked = sorted(rows, key=lambda row: (row["dev_min_wr"], row["wr"]), reverse=True)
    high_retention = [row for row in ranked if row["full_min_retention"] >= 0.95]
    report = {
        "warning": (
            "Causal M1 OHLC shadow-policy approximation. Selection uses only exit_known_ns <= setup time; "
            "any finalist requires MT5 EA-path validation and forward paper testing."
        ),
        "geometry": {"sl_price": RISK_PRICE, "target_r": 2.0},
        "policy_library": list(decisions),
        "selector_count": len(selectors),
        "exact_shortlist_count": len(rows),
        "top_development": ranked[:40],
        "top_high_retention_development": high_retention[:40],
        "all": rows,
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if detail_frames:
        pd.concat(detail_frames, ignore_index=True).to_parquet(args.out.with_suffix(".details.parquet"), index=False)
    print(json.dumps({"selectors": len(rows), "top": high_retention[:12]}, indent=2))


if __name__ == "__main__":
    main()
