#!/usr/bin/env python3
"""Static and causal-invariance checks for the Sol V3 regime artifacts."""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from research_sol_market_regimes_v1_frozen import load_rates
from research_sol_market_regimes_v2 import build_daily_features
from research_sol_market_regimes_v3 import confirmed_state_machine_v3


def main() -> None:
    prefix = Path("logs/sol_market_regimes_v3")
    states = pd.read_csv(prefix.with_suffix(".daily_states.csv"))
    events = pd.read_csv(prefix.with_suffix(".transition_events.csv"))
    trades = pd.read_csv(prefix.with_suffix(".trades.csv"))

    assert set(events["latency_sessions"].unique()).issubset({3, 5})
    assert states["transition_confidence"].between(0.0, 1.0).all()
    pending = states["transition_status"].isin(["WATCH", "DEVELOPING"])
    assert states["transition_candidate"].notna().eq(pending).all()
    required = states.loc[pending, "transition_required_sessions"]
    assert set(required.unique()).issubset({3, 5})
    required_columns = [
        "core_regime_v3",
        "regime_age_bucket",
        "transition_status",
        "h1_h2_phase",
        "volatility_depth",
        "structural_hint",
        "edge_hint",
    ]
    assert not trades[required_columns].isna().any().any()

    features = build_daily_features(load_rates(Path("logs/sol_jp225_rates")))
    full, _ = confirmed_state_machine_v3(features)
    compare_columns = [
        "core_regime_v3",
        "core_regime_effective_age_sessions",
        "transition_status",
        "transition_candidate",
        "transition_pending_sessions",
        "macro_direction_v3",
        "h1_h2_phase",
        "volatility_depth",
        "full_regime_v3",
    ]
    for fraction in (0.25, 0.50, 0.75):
        size = max(120, int(len(features) * fraction))
        partial, _ = confirmed_state_machine_v3(features.iloc[:size].copy())
        expected = full.iloc[:size][compare_columns].reset_index(drop=True).fillna("")
        actual = partial[compare_columns].reset_index(drop=True).fillna("")
        pd.testing.assert_frame_equal(actual, expected, check_dtype=False)

    print("V3 regime verification: PASS")
    print(f"states={len(states)} transitions={len(events)} trades={len(trades)}")


if __name__ == "__main__":
    main()