"""
Regression tests for CSV datetime parsing with mixed timezone offsets.
"""

import pandas as pd

from dashboard.backend.core.data_provider import HistoricalDataProvider


def test_parse_csv_with_mixed_offset_datetime_strings(tmp_path):
    csv_path = tmp_path / "AAPL_M15_mixed_tz.csv"
    src = pd.DataFrame(
        {
            "datetime": [
                "2023-01-03 09:30:00-05:00",
                "2023-01-03 09:45:00-05:00",
                "2023-07-03 09:30:00-04:00",
                "2023-07-03 09:45:00-04:00",
            ],
            "open": [100.0, 101.0, 102.0, 103.0],
            "high": [100.5, 101.5, 102.5, 103.5],
            "low": [99.5, 100.5, 101.5, 102.5],
            "close": [100.2, 101.2, 102.2, 103.2],
            "volume": [1000, 1000, 1000, 1000],
            "earnings_event": [0, 0, 1, 1],
            "iv_front": [0.4, 0.4, 0.4, 0.4],
            "iv_back": [0.3, 0.3, 0.3, 0.3],
            "iv_45d": [0.2, 0.2, 0.2, 0.2],
            "iv30": [0.35, 0.35, 0.35, 0.35],
            "rv30": [0.2, 0.2, 0.2, 0.2],
            "volume30": [8_000_000, 8_000_000, 8_000_000, 8_000_000],
        }
    )
    src.to_csv(csv_path, index=False)

    provider = HistoricalDataProvider()
    parsed = provider._parse_csv_file(csv_path)

    assert parsed is not None
    assert len(parsed) == 4
    assert parsed.index.tz is not None
    assert "America/New_York" in str(parsed.index.tz)
    assert "earnings_event" in parsed.columns
    assert float(parsed["close"].iloc[-1]) == 103.2
