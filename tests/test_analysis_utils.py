from __future__ import annotations

import math

import pandas as pd

from dashboard.backend.core.workbench.analysis_utils import (
    detect_fvg_zones,
    evaluate_sweep_rejection,
    filter_sweep_candidates,
)
from dashboard.backend.core.workbench.fvg_tool import FVGTool


def test_rejection_ratio_from_boundary_not_ref():
    out = evaluate_sweep_rejection(
        pool_boundary=104.0,
        swept_price=106.0,
        bar_high=106.0,
        bar_low=98.0,
    )
    assert math.isclose(float(out["rejection_ratio"]), 0.25, rel_tol=1e-6, abs_tol=1e-6)
    assert str(out["rejection_quality"]) == "weak"


def test_sweep_candidate_ranking_prefers_quality_before_distance():
    sweeps = [
        {
            "type": "liquidity_sweep_low",
            "swept_price": 99.4,
            "rejection_ratio": 0.35,
            "rejection_quality": "moderate",
            "bar_index": 18,
        },
        {
            "type": "liquidity_sweep_low",
            "swept_price": 99.8,
            "rejection_ratio": 0.75,
            "rejection_quality": "strong",
            "bar_index": 17,
        },
    ]
    ranked = filter_sweep_candidates(
        sweeps,
        entry_price=100.0,
        direction="bullish",
        atr=2.0,
        max_age_bars=10,
        max_distance_atr=1.0,
        min_rejection_ratio=0.30,
        current_bar_index=20,
    )
    assert len(ranked) == 2
    assert float(ranked[0]["rejection_ratio"]) == 0.75
    assert str(ranked[0]["rejection_quality"]) == "strong"


def test_fvg_detection_matches_tool_scan():
    idx = pd.date_range("2026-03-12", periods=5, freq="15min", tz="UTC")
    bars = pd.DataFrame(
        {
            "open": [99.7, 99.8, 100.0, 100.4, 100.6],
            "high": [100.0, 100.1, 100.2, 100.7, 100.9],
            "low": [99.3, 99.6, 100.3, 100.5, 100.7],
            "close": [99.8, 99.9, 100.4, 100.6, 100.8],
            "volume": [100.0] * 5,
        },
        index=idx,
    )
    cfg = {"symbol": "XAUUSD", "strictness": 3, "trend_filter_enabled": False}
    helper_zones = detect_fvg_zones(bars, cfg)
    tool_zones = FVGTool().scan(bars, cfg)

    assert len(helper_zones) == len(tool_zones)
    assert [str(z.get("type") or "") for z in helper_zones] == [str(z.get("type") or "") for z in tool_zones]
    assert [float(z.get("top") or 0.0) for z in helper_zones] == [float(z.get("top") or 0.0) for z in tool_zones]
