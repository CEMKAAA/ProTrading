"""
CSV parser should preserve non-OHLC strategy feature columns.
"""

import pandas as pd

from dashboard.backend.core.data_provider import HistoricalDataProvider


def test_parse_csv_with_headers_preserves_strategy_columns(tmp_path):
    csv_path = tmp_path / "AAPL_M15_test.csv"
    src = pd.DataFrame(
        {
            "datetime": [
                "2024-01-02 15:15:00",
                "2024-01-02 15:30:00",
                "2024-01-02 15:45:00",
            ],
            "open": [100.0, 100.1, 100.2],
            "high": [100.2, 100.3, 100.4],
            "low": [99.8, 99.9, 100.0],
            "close": [100.1, 100.2, 100.3],
            "volume": [1000, 1200, 1100],
            "earnings_event": [0, 0, 0],
            "days_to_earnings": [1, 1, 1],
            "is_pre_earnings_day": [True, True, True],
            "next_earnings_date": ["2024-01-03", "2024-01-03", "2024-01-03"],
            "planned_exit_date": ["2024-01-04", "2024-01-04", "2024-01-04"],
            "iv_front": [0.60, 0.61, 0.62],
            "iv_back": [0.50, 0.50, 0.50],
            "iv_45d": [0.45, 0.45, 0.45],
            "iv30": [0.58, 0.59, 0.60],
            "rv30": [0.30, 0.30, 0.30],
            "volume30": [9_000_000, 9_000_000, 9_000_000],
        }
    )
    src.to_csv(csv_path, index=False)

    provider = HistoricalDataProvider()
    parsed = provider._parse_csv_file(csv_path)

    assert parsed is not None
    for col in [
        "earnings_event",
        "days_to_earnings",
        "is_pre_earnings_day",
        "next_earnings_date",
        "planned_exit_date",
        "iv_front",
        "iv_back",
        "iv_45d",
        "iv30",
        "rv30",
        "volume30",
    ]:
        assert col in parsed.columns
    assert int(parsed["days_to_earnings"].iloc[0]) == 1
    assert float(parsed["iv_front"].iloc[-1]) == 0.62
