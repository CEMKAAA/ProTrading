from math import sqrt

import pandas as pd

from dashboard.backend.core.earnings_edge_tools import (
    build_event_level_dataset,
    select_trade_candidates,
)


def _bars_df():
    idx = pd.to_datetime(
        [
            "2024-01-02 15:15",
            "2024-01-02 15:30",
            "2024-01-02 15:45",
            "2024-01-03 10:00",
            "2024-01-04 09:30",
            "2024-01-04 09:45",
        ]
    ).tz_localize("America/New_York")
    return pd.DataFrame(
        {
            "open": [100.0, 100.0, 100.1, 100.2, 100.5, 100.6],
            "high": [100.1, 100.2, 100.3, 101.0, 100.8, 100.9],
            "low": [99.8, 99.9, 100.0, 99.8, 100.3, 100.4],
            "close": [100.0, 101.0, 99.0, 100.2, 100.4, 102.0],
            "volume": [1000, 1000, 1000, 1000, 1000, 1000],
            "earnings_event": [False, False, False, True, False, False],
            "days_to_earnings": [1, 1, 1, 0, 999, 999],
            "is_pre_earnings_day": [True, True, True, False, False, False],
            "next_earnings_date": ["2024-01-03"] * 6,
            "planned_exit_date": ["2024-01-04"] * 6,
            "iv_front": [0.20, 0.50, 0.10, 0.45, 0.35, 0.30],
            "iv_back": [0.18, 0.30, 0.09, 0.29, 0.24, 0.20],
            "iv_45d": [0.12, 0.40, 0.08, 0.35, 0.28, 0.25],
            "iv30": [0.25, 0.60, 0.12, 0.50, 0.45, 0.40],
            "rv30": [0.20, 0.30, 0.20, 0.28, 0.25, 0.23],
            "volume30": [9_000_000] * 6,
        },
        index=idx,
    )


def test_build_event_level_dataset_uses_signal_bar_before_entry_time():
    df = _bars_df()
    events = build_event_level_dataset(
        df,
        symbol="AAPL",
        entry_time="15:45",
        exit_time="09:45",
        front_dte_days=7.0,
        expected_move_scale=1.0,
    )

    assert len(events) == 1
    row = events.iloc[0]
    # Strategy signal bar should be 15:30 for a 15:45 intended entry on M15.
    assert row["signal_ts"].startswith("2024-01-02T15:30:00")
    assert row["entry_ts_target"].startswith("2024-01-02T15:45:00")
    assert row["exit_ts"].startswith("2024-01-04T09:45:00")

    entry_ref = 101.0  # close at 15:30
    expected_move_pct = 0.50 * sqrt(7.0 / 365.0)
    expected_move_abs = entry_ref * expected_move_pct
    realized_move_abs = abs(102.0 - entry_ref)
    edge_abs = expected_move_abs - realized_move_abs

    assert abs(row["entry_ref_price"] - entry_ref) < 1e-9
    assert abs(row["expected_move_abs"] - expected_move_abs) < 1e-9
    assert abs(row["realized_move_abs"] - realized_move_abs) < 1e-9
    assert abs(row["edge_abs"] - edge_abs) < 1e-9


def test_select_trade_candidates_applies_all_rules():
    events = pd.DataFrame(
        [
            {
                "symbol": "AAPL",
                "term_structure_slope": -0.10,
                "volume30": 9_000_000,
                "iv30_rv30_ratio": 1.8,
                "edge_pct": 0.03,
            },
            {
                "symbol": "AAPL",
                "term_structure_slope": -0.02,
                "volume30": 3_000_000,
                "iv30_rv30_ratio": 1.1,
                "edge_pct": -0.01,
            },
        ]
    )
    selected = select_trade_candidates(
        events_df=events,
        term_structure_max_slope=-0.05,
        min_avg_volume30=5_000_000,
        min_iv30_rv30_ratio=1.25,
        min_edge_pct=0.0,
    )

    assert len(selected) == 2
    assert bool(selected.iloc[0]["selected"]) is True
    assert int(selected.iloc[0]["selection_score"]) == 4
    assert bool(selected.iloc[1]["selected"]) is False
    assert int(selected.iloc[1]["selection_score"]) == 0
