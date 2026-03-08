"""
Unit tests for earnings volatility strategy logic.
"""

from datetime import datetime
from types import SimpleNamespace

import pandas as pd

from dashboard.backend.core.strategies.base import DayContext
from dashboard.backend.core.strategies.earnings_volatility_strategy import EarningsVolatilityStrategy


def _build_df():
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
            "open": [100.0, 100.0, 100.1, 100.0, 100.2, 100.1],
            "high": [100.2, 100.3, 100.4, 103.0, 100.4, 100.3],
            "low": [99.8, 99.9, 99.9, 97.0, 99.8, 99.7],
            "close": [100.0, 100.1, 100.0, 100.2, 100.1, 100.0],
            "volume": [1000, 1000, 1000, 1000, 1000, 1000],
            "earnings_event": [False, False, False, True, False, False],
            "days_to_earnings": [1, 1, 1, 0, 999, 999],
            "is_pre_earnings_day": [True, True, True, False, False, False],
            "next_earnings_date": ["2024-01-03"] * 6,
            "planned_exit_date": ["2024-01-04"] * 6,
            "iv_front": [0.62, 0.60, 0.61, 0.58, 0.30, 0.28],
            "iv_back": [0.50, 0.50, 0.49, 0.49, 0.34, 0.33],
            "iv_45d": [0.45, 0.45, 0.45, 0.46, 0.40, 0.40],
            "iv30": [0.55, 0.55, 0.55, 0.54, 0.40, 0.39],
            "rv30": [0.30, 0.30, 0.30, 0.30, 0.30, 0.30],
            "volume30": [10_000_000, 10_000_000, 10_000_000, 10_000_000, 10_000_000, 10_000_000],
        },
        index=idx,
    )


def test_find_setup_passes_filters_and_timing():
    strategy = EarningsVolatilityStrategy(
        {
            "entry_time": "15:45",
            "exit_time": "09:45",
            "term_structure_max_slope": -0.05,
            "min_avg_volume30": 5_000_000,
            "min_iv30_rv30_ratio": 1.25,
            "vol_structure": "long_calendar",
        }
    )
    df = _build_df()
    signal_bar = df.loc[pd.Timestamp("2024-01-02 15:30", tz="America/New_York")]

    setup = strategy.find_setup(
        signal_bar,
        df,
        DayContext(date=datetime(2024, 1, 2), bias="neutral", bias_strength=0, atr=1.0),
        current_bar_index=1,
    )

    assert setup is not None
    assert setup.setup_type == "Earnings Long Calendar (Proxy)"
    assert setup.metadata["pnl_model"] == "earnings_short_vol_proxy"
    assert setup.metadata["disable_sl_tp"] is True
    assert setup.metadata["event_date"] == "2024-01-03"
    assert setup.metadata["exit_date"] == "2024-01-04"


def test_should_close_early_at_configured_exit_time():
    strategy = EarningsVolatilityStrategy({})
    position = SimpleNamespace(
        strategy_metadata={
            "strategy": "earnings_volatility_strategy",
            "exit_date": "2024-01-04",
            "exit_time": "09:45",
        }
    )
    day_context = DayContext(date=datetime(2024, 1, 4), bias="neutral", bias_strength=0, atr=1.0)
    df = pd.DataFrame()

    bar_before = pd.Series({"close": 100.0}, name=pd.Timestamp("2024-01-04 09:30", tz="America/New_York"))
    bar_at = pd.Series({"close": 100.0}, name=pd.Timestamp("2024-01-04 09:45", tz="America/New_York"))

    assert strategy.should_close_early(bar_before, df, position, day_context) is None
    assert strategy.should_close_early(bar_at, df, position, day_context) == "Post-Earnings Timed Exit"


def test_find_setup_uses_preknown_schedule_when_lookahead_disabled():
    strategy = EarningsVolatilityStrategy(
        {
            "entry_time": "15:45",
            "exit_time": "09:45",
            "term_structure_max_slope": -0.05,
            "min_avg_volume30": 5_000_000,
            "min_iv30_rv30_ratio": 1.25,
            "allow_event_lookahead": False,
        }
    )
    df = _build_df().copy()
    # Remove event-day labels to prove setup does not rely on future event bars.
    df["earnings_event"] = 0
    signal_bar = df.loc[pd.Timestamp("2024-01-02 15:30", tz="America/New_York")]

    setup = strategy.find_setup(
        signal_bar,
        df,
        DayContext(date=datetime(2024, 1, 2), bias="neutral", bias_strength=0, atr=1.0),
        current_bar_index=1,
    )

    assert setup is not None
    assert setup.metadata["event_date"] == "2024-01-03"
    assert setup.metadata["exit_date"] == "2024-01-04"
