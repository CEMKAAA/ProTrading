from __future__ import annotations

import pandas as pd

from dashboard.backend.core.workbench.fvg_tool import FVGTool


def _build_three_bar_gap_df(gap: float) -> pd.DataFrame:
    idx = pd.date_range("2026-03-12", periods=3, freq="15min", tz="UTC")
    c1_high = 100.0
    c3_low = c1_high + float(gap)
    return pd.DataFrame(
        {
            "open": [99.7, 99.8, c3_low + 0.1],
            "high": [100.0, 100.1, c3_low + 0.4],
            "low": [99.3, 99.6, c3_low],
            "close": [99.8, 99.9, c3_low + 0.2],
            "volume": [100.0, 100.0, 100.0],
        },
        index=idx,
    )


def test_fvg_symbol_suffix_uses_instrument_gap_calibration():
    tool = FVGTool()
    bars = _build_three_bar_gap_df(gap=0.3)
    zones_gold = tool.scan(bars, {"symbol": "XAUUSDm", "strictness": 3})
    zones_index = tool.scan(bars, {"symbol": "NAS100m", "strictness": 3})
    assert len(zones_gold) >= 1
    assert len(zones_index) == 0


def test_fvg_invalid_min_gap_falls_back_to_symbol_default():
    tool = FVGTool()
    bars = _build_three_bar_gap_df(gap=0.2)
    zones = tool.scan(
        bars,
        {
            "symbol": "XAUUSDm",
            "strictness": 3,
            "min_gap": "auto",
        },
    )
    assert isinstance(zones, list)
    assert len(zones) >= 1
