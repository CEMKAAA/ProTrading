from __future__ import annotations

import math

import pandas as pd

from dashboard.backend.core.workbench.liquidity_tool import LiquidityTool


def _build_bars() -> pd.DataFrame:
    idx = pd.date_range("2026-03-01", periods=60, freq="15min", tz="UTC")
    close = [95.0 + (0.08 * i) + math.sin(i / 6.0) for i in range(60)]
    high = [c + 1.2 for c in close]
    low = [c - 1.2 for c in close]
    open_ = [c - 0.2 for c in close]
    vol = [1000.0 for _ in close]

    # Equal-high pool candidates.
    for i in (15, 25, 35):
        high[i] = 100.0
        close[i] = 99.0
        if i - 1 >= 0:
            high[i - 1] = min(high[i - 1], 98.5)
        if i + 1 < len(high):
            high[i + 1] = min(high[i + 1], 98.6)

    # Sweep above the pool with rejection close.
    high[40] = 103.0
    close[40] = 98.4

    df = pd.DataFrame(
        {
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": vol,
        },
        index=idx,
    )
    return df


def test_liquidity_scan_detects_pools_and_sweeps():
    tool = LiquidityTool()
    bars = _build_bars()
    zones = tool.scan(
        bars,
        {
            "symbol": "XAUUSD",
            "strictness": 1,
            "pivot_span": 1,
            "min_touches": 2,
            "lookback_bars": 60,
            "sweep_lookahead": 20,
            "tolerance_atr_mult": 0.8,
        },
    )
    assert isinstance(zones, list)
    pool_types = {str(z.get("type") or "") for z in zones if isinstance(z, dict)}
    assert "liquidity_pool_high" in pool_types


def test_liquidity_current_state_shape():
    tool = LiquidityTool()
    bars = _build_bars()
    state = tool.compute_current_state(
        bars,
        {
            "symbol": "XAUUSD",
            "strictness": 1,
            "pivot_span": 1,
            "min_touches": 2,
            "lookback_bars": 60,
            "sweep_lookahead": 20,
            "tolerance_atr_mult": 0.8,
        },
    )
    assert isinstance(state, dict)
    assert "state" in state
    assert "zones_count" in state
