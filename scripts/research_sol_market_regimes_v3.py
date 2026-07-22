#!/usr/bin/env python3
"""Causal, low-latency hierarchical regime research for SolVersion.

The market-state machine uses completed JP225 bars only. Trade outcomes are
joined afterwards and are used solely by the separate walk-forward edge-hint
estimator. They never influence regime detection or transition confirmation.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
import pandas as pd

from research_sol_market_regimes_v1_frozen import TIMEFRAMES, load_rates, metrics
from research_sol_market_regimes_v2 import (
    build_daily_features,
    resolve_paired_counterfactual,
    summarize,
)


# Core-state hysteresis. A decisive break confirms in three completed sessions;
# an ordinary break requires five. The pending transition is visible on day one.
TREND_SCORE_ENTER = 0.62
TREND_SCORE_EXIT = 0.42
TREND_SCORE_DECISIVE_HIGH = 0.76
TREND_SCORE_DECISIVE_LOW = 0.28
VOL_SCORE_ENTER = 0.62
VOL_SCORE_EXIT = 0.42
VOL_SCORE_DECISIVE_HIGH = 0.76
VOL_SCORE_DECISIVE_LOW = 0.28
FAST_CONFIRM_SESSIONS = 3
NORMAL_CONFIRM_SESSIONS = 5

# Direction has its own state and confirmation path; it is not inferred from a
# one-day sign flip. Pending direction is exposed immediately for live warning.
DIRECTION_ENTER_Z = 0.35
DIRECTION_DECISIVE_Z = 0.75

EDGE_LOOKBACK_DAYS = 730
EDGE_HALF_LIFE_DAYS = 180.0
EDGE_PRIOR_STRENGTH = 20.0
EDGE_MIN_SUPPORT = 20.0


def clip01(value: float) -> float:
    return float(np.clip(value, 0.0, 1.0)) if np.isfinite(value) else 0.0


def sign_name(value: int) -> str:
    return {1: "UP", -1: "DOWN", 0: "UNKNOWN"}[int(value)]


def age_bucket(age: int) -> str:
    if age <= 10:
        return "FRESH"
    if age <= 40:
        return "ESTABLISHED"
    if age <= 80:
        return "MATURE"
    return "LATE"


def phase_family(phase: str) -> str:
    if phase in {"ALIGNED", "ALIGNED_IMPULSE"}:
        return "ALIGNED"
    if "PULLBACK" in phase or "REBOUND" in phase:
        return "COUNTERTREND_RETRACE"
    if phase == "REVERSAL_PRESSURE":
        return "REVERSAL_RISK"
    return "ROTATION"


def lifecycle_family(status: str) -> str:
    if status in {"WATCH", "DEVELOPING"}:
        return "TRANSITION"
    if status == "FRESH_CONFIRMED":
        return "FRESH"
    return "STABLE"


def add_v3_scores(features: pd.DataFrame) -> pd.DataFrame:
    frame = features.copy()
    trend_signal = frame["macro_trend_z"].abs().map(lambda x: clip01(x / 1.50))
    structural_efficiency = frame["efficiency_100"].map(lambda x: clip01(x / 0.35))
    slow_agreement = frame["slow_direction_agreement"].astype(float).clip(0.0, 1.0)

    signs = pd.DataFrame(
        {
            name: np.sign(frame[f"{name}_ret_20s_pct"].astype(float))
            for name in ("h1", "h2", "h4", "d1")
        }
    )
    macro_sign = np.sign(frame["all_tf_ret_100s_pct"].astype(float)).replace(0.0, np.nan)
    directional_persistence = signs.mul(macro_sign, axis=0).gt(0.0).mean(axis=1)
    frame["trend_depth_score"] = (
        0.40 * trend_signal
        + 0.30 * structural_efficiency
        + 0.15 * slow_agreement
        + 0.15 * directional_persistence
    ).clip(0.0, 1.0)

    ratio60 = frame["vol_ratio_60_100"].astype(float)
    ratio20 = frame["vol_ratio_20_100"].astype(float)
    percentile = frame["rv20_trailing_percentile"].astype(float).fillna(0.50)
    frame["volatility_depth_score"] = (
        0.40 * ((ratio60 - 0.75) / 0.70).clip(0.0, 1.0)
        + 0.35 * percentile.clip(0.0, 1.0)
        + 0.25 * ((ratio20 - 0.75) / 0.80).clip(0.0, 1.0)
    ).clip(0.0, 1.0)
    frame["volatility_impulse"] = ratio20 - ratio60

    daily_rv = frame["rv20_daily"].astype(float)
    fast_noise = daily_rv * np.sqrt(5.0) * 100.0
    medium_noise = frame["rv60_daily"].astype(float) * np.sqrt(20.0) * 100.0
    frame["h1_h2_fast_return_pct"] = frame[["h1_ret_5s_pct", "h2_ret_5s_pct"]].median(axis=1)
    frame["h1_h2_medium_return_pct"] = frame[["h1_ret_20s_pct", "h2_ret_20s_pct"]].median(axis=1)
    frame["h1_h2_fast_z"] = frame["h1_h2_fast_return_pct"] / fast_noise.replace(0.0, np.nan)
    frame["h1_h2_medium_z"] = frame["h1_h2_medium_return_pct"] / medium_noise.replace(0.0, np.nan)
    frame["h1_h2_fast_agreement"] = (
        np.sign(frame["h1_ret_5s_pct"]) == np.sign(frame["h2_ret_5s_pct"])
    ).astype(int)
    frame["h1_h2_medium_agreement"] = (
        np.sign(frame["h1_ret_20s_pct"]) == np.sign(frame["h2_ret_20s_pct"])
    ).astype(int)
    return frame


def classify_volatility_depth(row: object) -> str:
    score = float(row.volatility_depth_score)
    ratio20 = float(row.vol_ratio_20_100)
    percentile = float(row.rv20_trailing_percentile)
    if score >= 0.85 or ratio20 >= 1.50 or (np.isfinite(percentile) and percentile >= 0.90):
        return "EXTREME"
    if score >= VOL_SCORE_ENTER:
        return "ELEVATED"
    if score <= 0.28 and (not np.isfinite(percentile) or percentile <= 0.35):
        return "COMPRESSED"
    return "NORMAL"


def classify_h1_h2_phase(row: object, direction: int, direction_pending: int, pending_count: int) -> str:
    if direction == 0:
        return "NEUTRAL_ROTATION"
    fast = direction * float(row.h1_h2_fast_z)
    medium = direction * float(row.h1_h2_medium_z)
    if direction_pending == -direction and pending_count >= 2:
        return "REVERSAL_PRESSURE"
    if medium <= -0.35 and fast <= -0.35 and int(row.h1_h2_medium_agreement) == 1:
        return "REVERSAL_PRESSURE"
    if fast <= -0.75:
        return "DEEP_PULLBACK" if direction > 0 else "DEEP_REBOUND"
    if fast <= -0.20:
        return "SHALLOW_PULLBACK" if direction > 0 else "SHALLOW_REBOUND"
    if fast >= 0.75 and int(row.h1_h2_fast_agreement) == 1:
        return "ALIGNED_IMPULSE"
    if fast >= 0.20:
        return "ALIGNED"
    return "NEUTRAL_ROTATION"


def transition_type(active: str, candidate: str) -> str:
    if not active or not candidate or active == candidate:
        return "NONE"
    old_trend, old_vol = active.split("_", 1)
    new_trend, new_vol = candidate.split("_", 1)
    trend_changed = old_trend != new_trend
    vol_changed = old_vol != new_vol
    if trend_changed and vol_changed:
        return "COMPOUND"
    if trend_changed:
        return f"{old_trend}_TO_{new_trend}"
    return "VOL_EXPANSION" if new_vol == "HIGH_VOL" else "VOL_CONTRACTION"


def structural_hint(core: str, status: str, phase: str, vol_depth: str, age_name: str) -> str:
    if status in {"WATCH", "DEVELOPING"}:
        return "TRANSITION_UNCERTAIN"
    if phase == "REVERSAL_PRESSURE":
        return "REVERSAL_RISK"
    if age_name == "FRESH" and vol_depth == "EXTREME":
        return "PRICE_DISCOVERY_RISK"
    if core.startswith("TREND") and phase in {"ALIGNED", "ALIGNED_IMPULSE"}:
        return "TREND_CONTINUATION_SUPPORT"
    if core.startswith("TREND") and ("PULLBACK" in phase or "REBOUND" in phase):
        return "TREND_RETRACE_SETUP"
    if core.startswith("RANGE") and vol_depth == "COMPRESSED":
        return "RANGE_COMPRESSION"
    if core.startswith("RANGE") and vol_depth in {"ELEVATED", "EXTREME"}:
        return "RANGE_EXPANSION_RISK"
    return "NEUTRAL_STRUCTURE"


def confirmed_state_machine_v3(features: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    frame = add_v3_scores(features).sort_values("regime_available").reset_index(drop=True)
    trend_on = False
    high_vol = False
    active_core = ""
    pending_core = ""
    pending_count = 0
    pending_required = 0
    transition_started = pd.NaT
    effective_age = 0
    confirmed_age = 0

    direction = 0
    pending_direction = 0
    pending_direction_count = 0
    pending_direction_required = 0

    records: list[dict] = []
    events: list[dict] = []

    for row in frame.itertuples(index=False):
        timestamp = row.regime_available
        trend_score = float(row.trend_depth_score)
        vol_score = float(row.volatility_depth_score)

        if trend_on:
            target_trend = trend_score >= TREND_SCORE_EXIT
        else:
            target_trend = trend_score >= TREND_SCORE_ENTER
        if high_vol:
            target_high_vol = vol_score >= VOL_SCORE_EXIT
        else:
            target_high_vol = vol_score >= VOL_SCORE_ENTER

        candidate = f"{'TREND' if target_trend else 'RANGE'}_{'HIGH_VOL' if target_high_vol else 'LOW_VOL'}"
        switch_event = ""
        if not active_core:
            trend_on = target_trend
            high_vol = target_high_vol
            active_core = candidate
            effective_age = 1
            confirmed_age = 1
        elif candidate == active_core:
            pending_core = ""
            pending_count = 0
            pending_required = 0
            transition_started = pd.NaT
            effective_age += 1
            confirmed_age += 1
        else:
            changed_trend = candidate.startswith("TREND") != active_core.startswith("TREND")
            changed_vol = candidate.endswith("HIGH_VOL") != active_core.endswith("HIGH_VOL")
            decisive_trend = (
                (not changed_trend)
                or (candidate.startswith("TREND") and trend_score >= TREND_SCORE_DECISIVE_HIGH)
                or (candidate.startswith("RANGE") and trend_score <= TREND_SCORE_DECISIVE_LOW)
            )
            decisive_vol = (
                (not changed_vol)
                or (candidate.endswith("HIGH_VOL") and vol_score >= VOL_SCORE_DECISIVE_HIGH)
                or (candidate.endswith("LOW_VOL") and vol_score <= VOL_SCORE_DECISIVE_LOW)
            )
            required = FAST_CONFIRM_SESSIONS if decisive_trend and decisive_vol else NORMAL_CONFIRM_SESSIONS
            if candidate == pending_core:
                pending_count += 1
            else:
                pending_core = candidate
                pending_count = 1
                pending_required = required
                transition_started = timestamp
            effective_age += 1
            confirmed_age += 1
            if pending_count >= pending_required:
                old_core = active_core
                event_type = transition_type(old_core, candidate)
                switch_event = f"{old_core}->{candidate}"
                events.append(
                    {
                        "transition_started": transition_started,
                        "transition_confirmed": timestamp,
                        "latency_sessions": pending_count,
                        "required_sessions": pending_required,
                        "old_core": old_core,
                        "new_core": candidate,
                        "transition_type": event_type,
                        "trend_depth_score": trend_score,
                        "volatility_depth_score": vol_score,
                    }
                )
                trend_on = candidate.startswith("TREND")
                high_vol = candidate.endswith("HIGH_VOL")
                active_core = candidate
                effective_age = pending_count
                confirmed_age = 1
                pending_core = ""
                pending_count = 0
                pending_required = 0
                transition_started = pd.NaT

        macro_z = float(row.macro_trend_z)
        direction_candidate = 1 if macro_z >= DIRECTION_ENTER_Z else -1 if macro_z <= -DIRECTION_ENTER_Z else direction
        direction_switch = ""
        if direction == 0 and direction_candidate != 0:
            direction = direction_candidate
        elif direction_candidate == direction:
            pending_direction = 0
            pending_direction_count = 0
            pending_direction_required = 0
        elif direction_candidate != 0:
            required = FAST_CONFIRM_SESSIONS if abs(macro_z) >= DIRECTION_DECISIVE_Z else NORMAL_CONFIRM_SESSIONS
            if direction_candidate == pending_direction:
                pending_direction_count += 1
            else:
                pending_direction = direction_candidate
                pending_direction_count = 1
                pending_direction_required = required
            if pending_direction_count >= pending_direction_required:
                direction_switch = f"{sign_name(direction)}->{sign_name(direction_candidate)}"
                direction = direction_candidate
                pending_direction = 0
                pending_direction_count = 0
                pending_direction_required = 0

        vol_depth = classify_volatility_depth(row)
        phase = classify_h1_h2_phase(row, direction, pending_direction, pending_direction_count)
        if switch_event:
            status = "FRESH_CONFIRMED"
        elif pending_core:
            status = "WATCH" if pending_count == 1 else "DEVELOPING"
        else:
            status = "STABLE"
        age_name = age_bucket(effective_age)
        transition_confidence = pending_count / pending_required if pending_required else 0.0
        active_transition_type = transition_type(active_core, pending_core)
        if switch_event:
            active_transition_type = events[-1]["transition_type"]

        if row.volatility_impulse >= 0.15:
            vol_impulse_state = "EXPANDING"
        elif row.volatility_impulse <= -0.15:
            vol_impulse_state = "CONTRACTING"
        else:
            vol_impulse_state = "STEADY"

        records.append(
            {
                "core_regime_v3": active_core,
                "core_regime_effective_age_sessions": effective_age,
                "core_regime_confirmed_age_sessions": confirmed_age,
                "regime_age_bucket": age_name,
                "transition_status": status,
                "transition_type": active_transition_type,
                "transition_candidate": pending_core,
                "transition_pending_sessions": pending_count,
                "transition_required_sessions": pending_required,
                "transition_confidence": transition_confidence,
                "core_switch_event": switch_event,
                "macro_direction_v3": sign_name(direction),
                "direction_pending": sign_name(pending_direction),
                "direction_pending_sessions": pending_direction_count,
                "direction_switch_event": direction_switch,
                "h1_h2_phase": phase,
                "h1_h2_phase_family": phase_family(phase),
                "volatility_depth": vol_depth,
                "volatility_impulse_state": vol_impulse_state,
                "structural_hint": structural_hint(active_core, status, phase, vol_depth, age_name),
                "full_regime_v3": "|".join(
                    [active_core, age_name, status, sign_name(direction), phase, vol_depth, vol_impulse_state]
                ),
            }
        )
    return pd.concat([frame, pd.DataFrame(records)], axis=1), pd.DataFrame(events)


def weighted_effective_n(weights: np.ndarray) -> float:
    denominator = float(np.square(weights).sum())
    return float(weights.sum() ** 2 / denominator) if denominator > 0.0 else 0.0


def walk_forward_edge_hints(trades: pd.DataFrame) -> pd.DataFrame:
    ordered = trades.sort_values("available").reset_index(drop=True).copy()
    history: deque[int] = deque()
    output: list[dict] = []

    for index, row in ordered.iterrows():
        cutoff = row["available"] - pd.Timedelta(days=EDGE_LOOKBACK_DAYS)
        while history and ordered.iloc[history[0]]["available"] < cutoff:
            history.popleft()
        prior = ordered.iloc[list(history)].copy() if history else ordered.iloc[0:0].copy()

        if prior.empty:
            output.append(
                {
                    "edge_hint": "INSUFFICIENT_HISTORY",
                    "edge_reliability": "INSUFFICIENT_HISTORY",
                    "edge_expected_r": np.nan,
                    "edge_recent_expected_r": np.nan,
                    "edge_older_expected_r": np.nan,
                    "edge_win_probability": np.nan,
                    "edge_effective_support": 0.0,
                    "edge_recent_effective_support": 0.0,
                    "edge_older_effective_support": 0.0,
                    "edge_uncertainty_r": np.nan,
                }
            )
            history.append(index)
            continue

        age_days = (row["available"] - prior["available"]).dt.total_seconds() / 86400.0
        weights = np.exp(-np.log(2.0) * age_days.to_numpy(float) / EDGE_HALF_LIFE_DAYS)
        similarity = np.ones(len(prior), dtype=float)
        similarity *= np.where(prior["core_regime_v3"].eq(row["core_regime_v3"]), 2.50, 0.35)
        similarity *= np.where(prior["h1_h2_phase_family"].eq(row["h1_h2_phase_family"]), 1.80, 0.70)
        similarity *= np.where(prior["volatility_depth"].eq(row["volatility_depth"]), 1.35, 0.85)
        similarity *= np.where(prior["regime_age_bucket"].eq(row["regime_age_bucket"]), 1.20, 0.90)
        similarity *= np.where(
            prior["transition_status"].map(lifecycle_family).eq(lifecycle_family(row["transition_status"])),
            1.25,
            0.85,
        )
        weights *= similarity
        values = prior["base_r"].to_numpy(float)
        wins = (values > 0.0).astype(float)
        effective_n = weighted_effective_n(weights)
        weighted_mean = float(np.average(values, weights=weights))
        weighted_wr = float(np.average(wins, weights=weights))
        global_mean = float(prior["base_r"].mean())
        global_wr = float((prior["base_r"] > 0.0).mean())
        weight_sum = float(weights.sum())
        posterior_mean = (weight_sum * weighted_mean + EDGE_PRIOR_STRENGTH * global_mean) / (
            weight_sum + EDGE_PRIOR_STRENGTH
        )
        posterior_wr = (weight_sum * weighted_wr + EDGE_PRIOR_STRENGTH * global_wr) / (
            weight_sum + EDGE_PRIOR_STRENGTH
        )
        variance = float(np.average(np.square(values - weighted_mean), weights=weights))
        uncertainty = float(np.sqrt(variance / max(effective_n, 1.0)))

        recent_mask = age_days.to_numpy(float) <= EDGE_HALF_LIFE_DAYS
        older_mask = ~recent_mask

        def segment_estimate(mask: np.ndarray) -> tuple[float, float]:
            segment_weights = weights[mask]
            if not np.any(mask) or float(segment_weights.sum()) <= 0.0:
                return np.nan, 0.0
            return (
                float(np.average(values[mask], weights=segment_weights)),
                weighted_effective_n(segment_weights),
            )

        recent_mean, recent_effective_n = segment_estimate(recent_mask)
        older_mean, older_effective_n = segment_estimate(older_mask)
        if recent_effective_n >= 8.0 and older_effective_n >= 12.0:
            if recent_mean >= 0.05 and older_mean >= 0.05:
                reliability = "STABLE_POSITIVE"
            elif recent_mean <= -0.05 and older_mean <= -0.05:
                reliability = "STABLE_NEGATIVE"
            else:
                reliability = "REGIME_CONFLICT"
        elif recent_effective_n >= 8.0:
            reliability = "RECENT_ONLY"
        else:
            reliability = "LOW_SUPPORT"

        if effective_n < EDGE_MIN_SUPPORT:
            hint = "INSUFFICIENT_CONTEXT"
        elif (
            reliability == "STABLE_POSITIVE"
            and posterior_mean >= 0.15
            and posterior_mean - uncertainty >= 0.0
        ):
            hint = "FAVORABLE"
        elif (
            reliability == "STABLE_NEGATIVE"
            and posterior_mean <= -0.08
            and posterior_mean + uncertainty <= 0.05
        ):
            hint = "CAUTION"
        elif reliability == "REGIME_CONFLICT":
            hint = "REGIME_CONFLICT"
        else:
            hint = "MIXED_UNCONFIRMED"
        output.append(
            {
                "edge_hint": hint,
                "edge_reliability": reliability,
                "edge_expected_r": posterior_mean,
                "edge_recent_expected_r": recent_mean,
                "edge_older_expected_r": older_mean,
                "edge_win_probability": posterior_wr,
                "edge_effective_support": effective_n,
                "edge_recent_effective_support": recent_effective_n,
                "edge_older_effective_support": older_effective_n,
                "edge_uncertainty_r": uncertainty,
            }
        )
        history.append(index)
    return pd.concat([ordered, pd.DataFrame(output)], axis=1)


def hint_summary(frame: pd.DataFrame) -> dict:
    result: dict[str, dict] = {}
    for hint, part in frame.groupby("edge_hint"):
        result[str(hint)] = {
            "trades": int(len(part)),
            "wins": int((part["base_r"] > 0.0).sum()),
            "wr": float((part["base_r"] > 0.0).mean()),
            "net_r": float(part["base_r"].sum()),
            "avg_r": float(part["base_r"].mean()),
        }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, default=Path("logs/sol_v14_pattern_research.dataset.csv"))
    parser.add_argument("--paired", type=Path, default=Path("logs/sol_pa_context_walk_forward.dataset.csv"))
    parser.add_argument("--rates", type=Path, default=Path("logs/sol_jp225_rates"))
    parser.add_argument("--out-prefix", type=Path, default=Path("logs/sol_market_regimes_v3"))
    args = parser.parse_args()

    v14 = pd.read_csv(args.dataset, parse_dates=["available"])
    v14["available"] = pd.to_datetime(v14["available"], utc=True)
    paired = pd.read_csv(args.paired, parse_dates=["available"])
    paired["available"] = pd.to_datetime(paired["available"], utc=True)

    states, events = confirmed_state_machine_v3(build_daily_features(load_rates(args.rates)))
    trades = resolve_paired_counterfactual(v14, paired)
    trades = pd.merge_asof(
        trades.sort_values("available"),
        states.sort_values("regime_available"),
        left_on="available",
        right_on="regime_available",
        direction="backward",
    )
    trades["year"] = trades["available"].dt.year
    covered = trades.dropna(subset=["core_regime_v3"]).copy()
    hinted = walk_forward_edge_hints(covered)

    splits = {
        "development_through_2022": hinted[hinted["year"] <= 2022],
        "validation_2023": hinted[hinted["year"] == 2023],
        "forward_2024_plus": hinted[hinted["year"] >= 2024],
        "full_covered": hinted,
    }
    transition_latencies = events["latency_sessions"] if not events.empty else pd.Series(dtype=float)
    report = {
        "status": "RESEARCH_ONLY_OBSERVER_NOT_AN_EXECUTION_FILTER",
        "data_start": str(hinted["available"].min()),
        "data_end": str(hinted["available"].max()),
        "covered_trades": int(len(hinted)),
        "causality": "Regimes use completed bars only. Edge hints use prior trades only.",
        "transition_contract": {
            "watch_latency_sessions": 1,
            "decisive_confirmation_sessions": FAST_CONFIRM_SESSIONS,
            "ordinary_confirmation_sessions": NORMAL_CONFIRM_SESSIONS,
            "confirmed_transitions": int(len(events)),
            "median_confirmation_sessions": float(transition_latencies.median()) if len(events) else None,
            "max_confirmation_sessions": int(transition_latencies.max()) if len(events) else None,
        },
        "formula": {
            "trend_score_enter": TREND_SCORE_ENTER,
            "trend_score_exit": TREND_SCORE_EXIT,
            "vol_score_enter": VOL_SCORE_ENTER,
            "vol_score_exit": VOL_SCORE_EXIT,
            "direction_enter_z": DIRECTION_ENTER_Z,
            "timeframes": list(TIMEFRAMES),
            "layers": [
                "core_regime",
                "regime_age",
                "transition_lifecycle",
                "h1_h2_pullback_rebound",
                "volatility_depth",
                "structural_hint",
                "walk_forward_edge_hint",
            ],
        },
        "base_by_core": {name: summarize(part, "base_r", "core_regime_v3") for name, part in splits.items()},
        "base_by_phase": {name: summarize(part, "base_r", "h1_h2_phase") for name, part in splits.items()},
        "base_by_volatility_depth": {
            name: summarize(part, "base_r", "volatility_depth") for name, part in splits.items()
        },
        "base_by_structural_hint": {
            name: summarize(part, "base_r", "structural_hint") for name, part in splits.items()
        },
        "walk_forward_edge_hints": {name: hint_summary(part) for name, part in splits.items()},
        "baseline": metrics(hinted.rename(columns={"base_r": "r"}).assign(won=hinted["base_r"].gt(0).astype(int))),
    }

    args.out_prefix.parent.mkdir(parents=True, exist_ok=True)
    states.to_csv(args.out_prefix.with_suffix(".daily_states.csv"), index=False)
    events.to_csv(args.out_prefix.with_suffix(".transition_events.csv"), index=False)
    hinted.to_csv(args.out_prefix.with_suffix(".trades.csv"), index=False)
    args.out_prefix.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report["transition_contract"], indent=2))
    print(json.dumps(report["walk_forward_edge_hints"], indent=2))


if __name__ == "__main__":
    main()
