#!/usr/bin/env python3
"""Production-oriented causal regime research for LiqNarrativeSolVersion.

Regimes are inferred only from completed JP225 bars. Trade outcomes are joined
after state generation and are never inputs to the regime state machine.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from research_sol_market_regimes_v1_frozen import TIMEFRAMES, completed_close_index, load_rates, metrics


TREND_ENTER_Z = 0.85
TREND_EXIT_Z = 0.55
EFFICIENCY_ENTER = 0.28
EFFICIENCY_EXIT = 0.18
VOL_RATIO_ENTER = 1.15
VOL_RATIO_EXIT = 0.95
VOL_PERCENTILE_ENTER = 0.70
VOL_PERCENTILE_EXIT = 0.55
STRUCTURAL_STATE_CONFIRM_SESSIONS = 15
TACTICAL_STATE_CONFIRM_SESSIONS = 5
DIRECTION_HYSTERESIS_PCT = 3.0


def percentile_rank(values: np.ndarray, current: float) -> float:
    clean = values[np.isfinite(values)]
    if len(clean) == 0 or not np.isfinite(current):
        return np.nan
    return float(np.mean(clean <= current))


def efficiency_ratio(closes: np.ndarray) -> float:
    if len(closes) < 2:
        return np.nan
    travel = float(np.abs(np.diff(closes)).sum())
    return float(abs(closes[-1] - closes[0]) / travel) if travel > 0.0 else 0.0


def build_daily_features(rates: dict[str, pd.DataFrame]) -> pd.DataFrame:
    daily = rates["D1"]
    daily_close = daily["close"].to_numpy(float)
    log_returns = np.diff(np.log(daily_close), prepend=np.nan)
    rv20_history: list[float] = []
    rows: list[dict] = []

    # Bar i is first knowable when the next D1 session opens.
    for index in range(100, len(daily) - 1):
        available = daily.iloc[index + 1]["time"]
        row: dict[str, object] = {"regime_available": available}
        for horizon in (5, 20, 100):
            anchor_time = daily.iloc[index - horizon]["time"]
            tf_returns: list[float] = []
            for timeframe, frame in rates.items():
                current_index = completed_close_index(frame, available)
                anchor_index = int(frame["time"].searchsorted(anchor_time, side="right") - 1)
                value = np.nan
                if current_index >= 0 and anchor_index >= 0:
                    current_close = float(frame.iloc[current_index]["close"])
                    anchor_close = float(frame.iloc[anchor_index]["close"])
                    value = (current_close / anchor_close - 1.0) * 100.0
                row[f"{timeframe.lower()}_ret_{horizon}s_pct"] = value
                tf_returns.append(value)
            row[f"all_tf_ret_{horizon}s_pct"] = float(np.nanmedian(tf_returns))

        recent20 = log_returns[index - 19 : index + 1]
        recent60 = log_returns[index - 59 : index + 1]
        recent100 = log_returns[index - 99 : index + 1]
        rv20 = float(np.nanstd(recent20, ddof=1))
        rv60 = float(np.nanstd(recent60, ddof=1))
        rv100 = float(np.nanstd(recent100, ddof=1))
        rv20_history.append(rv20)
        trailing = np.asarray(rv20_history[max(0, len(rv20_history) - 252) :], dtype=float)
        row["rv20_daily"] = rv20
        row["rv60_daily"] = rv60
        row["rv100_daily"] = rv100
        row["vol_ratio_20_100"] = rv20 / rv100 if rv100 > 0.0 else np.nan
        row["vol_ratio_60_100"] = rv60 / rv100 if rv100 > 0.0 else np.nan
        row["rv20_trailing_percentile"] = percentile_rank(trailing, rv20) if len(trailing) >= 60 else np.nan
        row["efficiency_20"] = efficiency_ratio(daily_close[index - 20 : index + 1])
        row["efficiency_100"] = efficiency_ratio(daily_close[index - 100 : index + 1])
        noise100_pct = rv100 * np.sqrt(100.0) * 100.0
        row["macro_trend_z"] = row["all_tf_ret_100s_pct"] / noise100_pct if noise100_pct > 0.0 else np.nan
        row["fast_h1_h2_ret_5s_pct"] = float(
            np.nanmedian([row["h1_ret_5s_pct"], row["h2_ret_5s_pct"]])
        )
        h4_sign = np.sign(row["h4_ret_100s_pct"])
        d1_sign = np.sign(row["d1_ret_100s_pct"])
        row["slow_direction_agreement"] = int(h4_sign != 0 and h4_sign == d1_sign)

        h1 = rates["H1"]
        session_anchor = daily.iloc[index - 20]["time"]
        first_h1 = int(h1["time"].searchsorted(session_anchor, side="left"))
        last_h1 = int(h1["time"].searchsorted(available, side="left"))
        session_bars = h1.iloc[first_h1:last_h1].copy()
        session_bars["range"] = session_bars["high"] - session_bars["low"]
        hour = session_bars["time"].dt.hour
        buckets = {
            "ASIA": hour.between(0, 5),
            "EUROPE": hour.between(6, 11),
            "US": hour.between(12, 19),
            "LATE": hour.between(20, 23),
        }
        activity = {
            name: float(session_bars.loc[mask, "range"].mean()) if mask.any() else np.nan
            for name, mask in buckets.items()
        }
        total_activity = float(np.nansum(list(activity.values())))
        for name, value in activity.items():
            row[f"session_{name.lower()}_activity_share"] = value / total_activity if total_activity > 0.0 else np.nan
        finite_activity = {name: value for name, value in activity.items() if np.isfinite(value)}
        row["dominant_session"] = max(finite_activity, key=finite_activity.get) if finite_activity else "UNKNOWN"
        shares = [row[f"session_{name.lower()}_activity_share"] for name in buckets]
        row["session_activity_concentration"] = float(np.nansum(np.square(shares)))
        rows.append(row)
    return pd.DataFrame(rows)


def confirmed_state_machine(features: pd.DataFrame) -> pd.DataFrame:
    frame = features.sort_values("regime_available").reset_index(drop=True).copy()
    structural_trend_on = False
    structural_high_vol = False
    tactical_trend_on = False
    tactical_high_vol = False
    direction = 0
    active_core = ""
    pending_core = ""
    pending_count = 0
    active_tactical = ""
    pending_tactical = ""
    pending_tactical_count = 0
    age = 0
    records: list[dict] = []

    for row in frame.itertuples(index=False):
        trend_z = abs(float(row.macro_trend_z))
        structural_efficiency = float(row.efficiency_100)
        tactical_efficiency = float(row.efficiency_20)
        if structural_trend_on:
            if trend_z < TREND_EXIT_Z or structural_efficiency < 0.10:
                structural_trend_on = False
        elif trend_z >= TREND_ENTER_Z and structural_efficiency >= 0.18 and row.slow_direction_agreement:
            structural_trend_on = True
        if tactical_trend_on:
            if trend_z < TREND_EXIT_Z or tactical_efficiency < EFFICIENCY_EXIT:
                tactical_trend_on = False
        elif trend_z >= TREND_ENTER_Z and tactical_efficiency >= EFFICIENCY_ENTER and row.slow_direction_agreement:
            tactical_trend_on = True

        vol_percentile = float(row.rv20_trailing_percentile)
        structural_vol_ratio = float(row.vol_ratio_60_100)
        tactical_vol_ratio = float(row.vol_ratio_20_100)
        if structural_high_vol:
            if structural_vol_ratio <= VOL_RATIO_EXIT and (not np.isfinite(vol_percentile) or vol_percentile <= VOL_PERCENTILE_EXIT):
                structural_high_vol = False
        elif structural_vol_ratio >= 1.10 or (np.isfinite(vol_percentile) and vol_percentile >= VOL_PERCENTILE_ENTER):
            structural_high_vol = True
        if tactical_high_vol:
            if tactical_vol_ratio <= VOL_RATIO_EXIT and (not np.isfinite(vol_percentile) or vol_percentile <= VOL_PERCENTILE_EXIT):
                tactical_high_vol = False
        elif tactical_vol_ratio >= VOL_RATIO_ENTER or (np.isfinite(vol_percentile) and vol_percentile >= VOL_PERCENTILE_ENTER):
            tactical_high_vol = True

        candidate = f"{'TREND' if structural_trend_on else 'RANGE'}_{'HIGH_VOL' if structural_high_vol else 'LOW_VOL'}"
        if not active_core:
            active_core = candidate
            age = 1
        elif candidate == active_core:
            pending_core = ""
            pending_count = 0
            age += 1
        else:
            if candidate == pending_core:
                pending_count += 1
            else:
                pending_core = candidate
                pending_count = 1
            if pending_count >= STRUCTURAL_STATE_CONFIRM_SESSIONS:
                active_core = candidate
                age = pending_count
                pending_core = ""
                pending_count = 0
            else:
                age += 1

        tactical_candidate = f"{'TREND' if tactical_trend_on else 'RANGE'}_{'HIGH_VOL' if tactical_high_vol else 'LOW_VOL'}"
        if not active_tactical:
            active_tactical = tactical_candidate
        elif tactical_candidate == active_tactical:
            pending_tactical = ""
            pending_tactical_count = 0
        else:
            if tactical_candidate == pending_tactical:
                pending_tactical_count += 1
            else:
                pending_tactical = tactical_candidate
                pending_tactical_count = 1
            if pending_tactical_count >= TACTICAL_STATE_CONFIRM_SESSIONS:
                active_tactical = tactical_candidate
                pending_tactical = ""
                pending_tactical_count = 0

        macro_return = float(row.all_tf_ret_100s_pct)
        if macro_return >= DIRECTION_HYSTERESIS_PCT:
            direction = 1
        elif macro_return <= -DIRECTION_HYSTERESIS_PCT:
            direction = -1
        direction_name = {1: "UP", -1: "DOWN", 0: "UNKNOWN"}[direction]
        fast = float(row.fast_h1_h2_ret_5s_pct)
        if direction == 0:
            phase = "UNKNOWN"
        elif direction > 0:
            phase = "ALIGNED" if fast >= 0.0 else "PULLBACK"
        else:
            phase = "ALIGNED" if fast <= 0.0 else "REBOUND"
        records.append(
            {
                "core_regime": active_core,
                "tactical_regime": active_tactical,
                "core_regime_age_sessions": age,
                "core_pending_candidate": pending_core,
                "core_pending_sessions": pending_count,
                "macro_direction": direction_name,
                "transition_phase": phase,
                "full_regime": f"{active_core}|{active_tactical}|{direction_name}|{phase}",
            }
        )
    return pd.concat([frame, pd.DataFrame(records)], axis=1)


def resolve_paired_counterfactual(v14: pd.DataFrame, paired: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict] = []
    for trade in v14.itertuples(index=False):
        candidates = paired[paired["available"].eq(trade.available)].copy()
        if candidates.empty:
            continue
        if len(candidates) > 1:
            candidates["quality_delta"] = (candidates["q_rev"] - trade.quality).abs()
            candidates = candidates.sort_values("quality_delta").head(1)
        pair = candidates.iloc[0]
        pair_base_r = float(pair["r_cont"] if trade.route == "continuation" else pair["r_rev"])
        flip_r = float(pair["r_rev"] if trade.route == "continuation" else pair["r_cont"])
        rows.append(
            {
                "available": trade.available,
                "base_r": float(trade.r),
                "pair_base_r": pair_base_r,
                "flip_r": flip_r,
                "base_route": trade.route,
            }
        )
    return pd.DataFrame(rows)


def summarize(frame: pd.DataFrame, value: str, group_column: str = "core_regime") -> dict:
    result: dict[str, dict] = {}
    for state, part in frame.groupby(group_column):
        series = part[value]
        result[str(state)] = {
            "trades": int(len(part)),
            "wins": int((series > 0.0).sum()),
            "wr": float((series > 0.0).mean()),
            "net_r": float(series.sum()),
            "avg_r": float(series.mean()),
        }
    return result


def expanding_year_flip_screen(frame: pd.DataFrame, min_support: int = 30) -> tuple[pd.DataFrame, dict]:
    """Screen only: mixed per-row counterfactuals are not an EA-path result."""
    outputs: list[pd.DataFrame] = []
    policies: dict[str, dict] = {}
    for year in sorted(frame["year"].unique()):
        if year < 2023:
            continue
        train = frame[frame["year"] < year]
        test = frame[frame["year"] == year].copy()
        policy: dict[str, str] = {}
        for state, group in train.groupby("core_regime"):
            if len(group) < min_support:
                policy[state] = "NORMAL"
                continue
            base = float(group["base_r"].mean())
            flip = float(group["flip_r"].mean())
            policy[state] = "FLIP" if flip > base + 0.10 and flip > 0.0 else "NORMAL"
        test["policy"] = test["core_regime"].map(policy).fillna("NORMAL")
        test["policy_r"] = np.where(test["policy"].eq("FLIP"), test["flip_r"], test["base_r"])
        outputs.append(test)
        policies[str(int(year))] = policy
    combined = pd.concat(outputs, ignore_index=True) if outputs else pd.DataFrame()
    return combined, policies


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, default=Path("logs/sol_v14_pattern_research.dataset.csv"))
    parser.add_argument("--paired", type=Path, default=Path("logs/sol_pa_context_walk_forward.dataset.csv"))
    parser.add_argument("--rates", type=Path, default=Path("logs/sol_jp225_rates"))
    parser.add_argument("--out-prefix", type=Path, default=Path("logs/sol_market_regimes_v2"))
    args = parser.parse_args()

    v14 = pd.read_csv(args.dataset, parse_dates=["available"])
    v14["available"] = pd.to_datetime(v14["available"], utc=True)
    paired = pd.read_csv(args.paired, parse_dates=["available"])
    paired["available"] = pd.to_datetime(paired["available"], utc=True)
    states = confirmed_state_machine(build_daily_features(load_rates(args.rates)))
    trades = resolve_paired_counterfactual(v14, paired)
    trades = pd.merge_asof(
        trades.sort_values("available"),
        states.sort_values("regime_available"),
        left_on="available",
        right_on="regime_available",
        direction="backward",
    )
    trades["year"] = trades["available"].dt.year
    covered = trades.dropna(subset=["core_regime"]).copy()
    covered["market_context"] = covered["core_regime"] + "|" + covered["dominant_session"]

    splits = {
        "development_through_2022": covered[covered["year"] <= 2022],
        "validation_2023": covered[covered["year"] == 2023],
        "forward_2024_plus": covered[covered["year"] >= 2024],
        "full_covered": covered,
    }
    walk_forward, policies = expanding_year_flip_screen(covered)
    report = {
        "status": "RESEARCH_ONLY_NOT_EA_PATH_VALIDATED",
        "data_start": str(covered["available"].min()),
        "data_end": str(covered["available"].max()),
        "covered_trades": int(len(covered)),
        "regime_formula": {
            "core": "TREND/RANGE x HIGH/LOW_VOL",
            "trend_enter_z": TREND_ENTER_Z,
            "trend_exit_z": TREND_EXIT_Z,
            "efficiency_enter": EFFICIENCY_ENTER,
            "efficiency_exit": EFFICIENCY_EXIT,
            "vol_ratio_enter": VOL_RATIO_ENTER,
            "vol_ratio_exit": VOL_RATIO_EXIT,
            "vol_percentile_enter": VOL_PERCENTILE_ENTER,
            "vol_percentile_exit": VOL_PERCENTILE_EXIT,
            "structural_state_confirmation_sessions": STRUCTURAL_STATE_CONFIRM_SESSIONS,
            "tactical_state_confirmation_sessions": TACTICAL_STATE_CONFIRM_SESSIONS,
            "timeframes": list(TIMEFRAMES),
        },
        "base_by_regime": {name: summarize(part, "base_r") for name, part in splits.items()},
        "flip_by_regime": {name: summarize(part, "flip_r") for name, part in splits.items()},
        "base_by_dominant_session": {
            name: summarize(part, "base_r", "dominant_session") for name, part in splits.items()
        },
        "base_by_market_context": {
            name: summarize(part, "base_r", "market_context") for name, part in splits.items()
        },
        "counterfactual_warning": "Flip rows mix globally routed EA runs. Any finalist requires a dedicated path-dependent EA rerun.",
        "walk_forward_flip_screen": {
            "policies": policies,
            "metrics": metrics(
                walk_forward.rename(columns={"policy_r": "r"}).assign(won=walk_forward["policy_r"].gt(0).astype(int))
            ) if not walk_forward.empty else {},
            "baseline": metrics(
                walk_forward.rename(columns={"base_r": "r"}).assign(won=walk_forward["base_r"].gt(0).astype(int))
            ) if not walk_forward.empty else {},
        },
    }

    args.out_prefix.parent.mkdir(parents=True, exist_ok=True)
    states.to_csv(args.out_prefix.with_suffix(".daily_states.csv"), index=False)
    covered.to_csv(args.out_prefix.with_suffix(".trades.csv"), index=False)
    walk_forward.to_csv(args.out_prefix.with_suffix(".walk_forward_flip.csv"), index=False)
    args.out_prefix.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report["walk_forward_flip_screen"], indent=2))
    for split, values in report["base_by_regime"].items():
        print(split, values)


if __name__ == "__main__":
    main()
