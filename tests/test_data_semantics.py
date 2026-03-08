"""
Data semantics tests for CSV parsing and resampling boundaries.
"""

import pandas as pd

from dashboard.backend.core.data_provider import HistoricalDataProvider


def test_parse_csv_with_naive_datetime_assumes_utc_then_converts_to_ny():
    provider = HistoricalDataProvider()
    df = pd.DataFrame(
        {
            "datetime": ["2024-01-02 15:00:00", "2024-01-02 15:01:00"],
            "open": [100.0, 101.0],
            "high": [101.0, 102.0],
            "low": [99.0, 100.0],
            "close": [100.5, 101.5],
            "volume": [10, 20],
        }
    )

    parsed = provider._parse_csv_with_headers(df)
    assert parsed is not None
    assert str(parsed.index.tz) == "America/New_York"
    # 15:00 UTC -> 10:00 NY (EST in January)
    assert parsed.index[0].hour == 10
    assert parsed.index[0].minute == 0


def test_parse_csv_with_aware_datetime_converts_to_ny_without_relocalizing():
    provider = HistoricalDataProvider()
    df = pd.DataFrame(
        {
            "datetime": ["2024-01-02T15:00:00+00:00", "2024-01-02T15:01:00+00:00"],
            "open": [100.0, 101.0],
            "high": [101.0, 102.0],
            "low": [99.0, 100.0],
            "close": [100.5, 101.5],
            "volume": [10, 20],
        }
    )

    parsed = provider._parse_csv_with_headers(df)
    assert parsed is not None
    assert str(parsed.index.tz) == "America/New_York"
    assert parsed.index[0].hour == 10
    assert parsed.index[0].minute == 0


def test_resample_m1_to_d1_uses_calendar_day_boundaries():
    provider = HistoricalDataProvider()
    idx = pd.DatetimeIndex(
        [
            "2024-01-02 23:58:00",
            "2024-01-02 23:59:00",
            "2024-01-03 00:00:00",
            "2024-01-03 00:01:00",
        ],
        tz="America/New_York",
    )
    m1 = pd.DataFrame(
        {
            "open": [10.0, 11.0, 20.0, 21.0],
            "high": [11.0, 12.0, 21.0, 22.0],
            "low": [9.0, 10.0, 19.0, 20.0],
            "close": [10.5, 11.5, 20.5, 21.5],
            "volume": [1, 2, 3, 4],
            "spread": [0.1, 0.2, 0.3, 0.4],
        },
        index=idx,
    )

    d1 = provider._resample_data(m1, "D1")
    assert d1 is not None
    assert len(d1) == 2

    first_day = d1.iloc[0]
    second_day = d1.iloc[1]

    assert first_day["open"] == 10.0
    assert first_day["high"] == 12.0
    assert first_day["low"] == 9.0
    assert first_day["close"] == 11.5
    assert first_day["volume"] == 3

    assert second_day["open"] == 20.0
    assert second_day["high"] == 22.0
    assert second_day["low"] == 19.0
    assert second_day["close"] == 21.5
    assert second_day["volume"] == 7
