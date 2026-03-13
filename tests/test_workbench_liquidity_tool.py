from __future__ import annotations

import math

import pandas as pd

from dashboard.backend.core.workbench.analysis_utils import atr_last
from dashboard.backend.core.workbench.liquidity_tool import LiquidityTool, _symbol_tick_size


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
            "tolerance_atr_mult": 0.2,
        },
    )
    assert isinstance(zones, list)
    pool_types = {str(z.get("type") or "") for z in zones if isinstance(z, dict)}
    assert "liquidity_pool_high" in pool_types
    sweep_rows = [z for z in zones if isinstance(z, dict) and str(z.get("type") or "").startswith("liquidity_sweep_")]
    assert len(sweep_rows) >= 1
    rr = float(sweep_rows[-1].get("rejection_ratio") or 0.0)
    assert rr > 0.0
    assert str(sweep_rows[-1].get("rejection_quality") or "") in {"weak", "moderate", "strong"}


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


def test_liquidity_tick_size_normalizes_broker_suffixes():
    assert float(_symbol_tick_size("XAUUSDm")) == 0.05
    assert float(_symbol_tick_size("NAS100.r")) == 0.25
    assert float(_symbol_tick_size("US500_cash")) == 0.25


def test_liquidity_sweep_rejection_ratio_uses_pool_boundary_not_cluster_average():
    idx = pd.date_range("2026-03-01", periods=60, freq="15min", tz="UTC")
    close = [99.0 + (0.02 * i) for i in range(60)]
    high = [c + 1.0 for c in close]
    low = [c - 1.0 for c in close]
    open_ = [c - 0.1 for c in close]
    vol = [1000.0 for _ in close]

    for i, px in ((15, 100.0), (25, 102.0), (35, 104.0)):
        high[i] = px
        close[i] = px - 1.0
        if i - 1 >= 0:
            high[i - 1] = min(high[i - 1], px - 2.5)
        if i + 1 < len(high):
            high[i + 1] = min(high[i + 1], px - 2.25)

    high[40] = 106.0
    low[40] = 98.2
    open_[40] = 100.6
    close[40] = 100.8

    bars = pd.DataFrame(
        {
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": vol,
        },
        index=idx,
    )

    tool = LiquidityTool()
    zones = tool.scan(
        bars,
        {
            "symbol": "NAS100",
            "strictness": 1,
            "pivot_span": 1,
            "min_touches": 3,
            "lookback_bars": 60,
            "sweep_lookahead": 20,
            "tolerance_atr_mult": 1.5,
        },
    )

    sweep_rows = [z for z in zones if isinstance(z, dict) and str(z.get("type") or "") == "liquidity_sweep_high"]
    assert len(sweep_rows) >= 1
    sweep = sweep_rows[-1]
    pool_boundary = float(sweep.get("pool_boundary") or 0.0)
    ref_price = float(sweep.get("ref_price") or 0.0)
    swept_price = float(sweep.get("swept_price") or 0.0)
    raw_bar_range = float(sweep.get("sweep_bar_high") or 0.0) - float(sweep.get("sweep_bar_low") or 0.0)
    assert pool_boundary > ref_price
    assert raw_bar_range > 0.0

    # The code clamps bar_range to min(raw, atr*2) so HV bars don't
    # suppress the rejection ratio (B2 fix).  Replicate the clamp here.
    atr = atr_last(bars, 14) or 1.0
    effective_bar_range = min(raw_bar_range, atr * 2.0)

    expected_boundary_ratio = (swept_price - pool_boundary) / effective_bar_range
    old_ref_ratio = (swept_price - ref_price) / effective_bar_range
    actual_ratio = float(sweep.get("rejection_ratio") or 0.0)

    assert math.isclose(actual_ratio, expected_boundary_ratio, rel_tol=1e-6, abs_tol=1e-6)
    # Pool-boundary ratio is small; ref_price ratio would be much larger
    assert actual_ratio < old_ref_ratio
    assert str(sweep.get("rejection_quality") or "") == "weak"
