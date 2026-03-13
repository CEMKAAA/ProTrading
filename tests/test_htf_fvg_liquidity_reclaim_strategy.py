from __future__ import annotations

from datetime import datetime
from types import SimpleNamespace

import pandas as pd

from dashboard.backend.core.strategies.base import DayContext
from dashboard.backend.core.strategies import htf_fvg_liquidity_reclaim_strategy as reclaim_mod
from dashboard.backend.core.strategies.htf_fvg_liquidity_reclaim_strategy import (
    HTFFVGLiquidityReclaimStrategy,
)


def _base_df(periods: int = 220) -> pd.DataFrame:
    idx = pd.date_range("2026-01-05", periods=periods, freq="15min", tz="UTC")
    close = [100.0 + (0.03 * i) for i in range(periods)]
    open_ = [c - 0.05 for c in close]
    high = [c + 0.35 for c in close]
    low = [c - 0.35 for c in close]
    volume = [1000.0] * periods
    return pd.DataFrame(
        {
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": volume,
        },
        index=idx,
    )


def _base_config() -> dict:
    return {
        "symbol": "XAUUSD",
        "timeframe": "M15",
        "required_lookback_bars": 90,
        "min_rejection_ratio": 0.30,
        "sl_buffer_atr": 0.25,
        "min_rr_ratio": 2.5,
        "max_rr_cap": 8.0,
        "bias_min_strength": 30,
        "require_bias_alignment": True,
        "sweep_distance_atr": 0.50,
        "sweep_freshness_hours": 4.0,
        "sweep_freshness_min_bars": 4,
        "momentum_fade_bars": 30,
        "momentum_fade_min_r": 0.5,
    }


def _bullish_fvg() -> dict:
    return {
        "type": "bullish_fvg",
        "top": 106.0,
        "bottom": 104.0,
        "timeframe": "H4",
        "end_time_unix": 1770000000,
        "quality_score": 82.0,
        "quality_label": "strong",
        "distance_from_price": 0.5,
        "mitigations": 0,
    }


def _bullish_sweep(rejection_ratio: float = 0.72, quality: str = "strong") -> dict:
    return {
        "type": "liquidity_sweep_low",
        "swept_price": 103.7,
        "pool_boundary": 104.2,
        "liquidity_level": 104.5,
        "rejection_ratio": rejection_ratio,
        "rejection_quality": quality,
        "swept_pool_touches": 3,
        "bar_index": 216,
        "end_time_unix": 1770000900,
    }


def test_initialize_day_resamples_intraday_data():
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df(96)  # 24h of M15
    ctx = strategy.initialize_day(datetime(2026, 1, 5), None, df)

    assert ctx.atr >= 0.0
    assert not strategy._last_h1_df.empty
    assert not strategy._last_h4_df.empty
    assert len(strategy._last_h1_df) >= 20
    assert len(strategy._last_h4_df) >= 5


def test_initialize_day_uses_prior_daily_bar_only():
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df(96)
    daily_df = pd.DataFrame(
        {
            "open": [99.0, 111.0],
            "high": [110.0, 130.0],
            "low": [95.0, 108.0],
            "close": [105.0, 125.0],
            "volume": [1000.0, 2000.0],
        },
        index=pd.DatetimeIndex(
            [
                pd.Timestamp("2026-01-04 00:00:00", tz="UTC"),
                pd.Timestamp("2026-01-06 00:00:00", tz="UTC"),
            ]
        ),
    )

    ctx = strategy.initialize_day(datetime(2026, 1, 5), daily_df, df)

    assert ctx.levels["daily_close"] == 105.0
    assert ctx.levels["daily_high"] == 110.0
    assert ctx.levels["daily_low"] == 95.0


def test_find_setup_returns_none_without_htf_fvg(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [])

    setup = strategy.find_setup(bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)
    assert setup is None


def test_find_setup_returns_none_without_sweep(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    monkeypatch.setattr(strategy, "_scan_liquidity_map", lambda _df: [])

    setup = strategy.find_setup(bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)
    assert setup is None


def test_find_setup_returns_none_on_weak_rejection(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    monkeypatch.setattr(strategy, "_scan_liquidity_map", lambda _df: [_bullish_sweep(0.20, "weak")])

    setup = strategy.find_setup(bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)
    assert setup is None


def test_find_setup_returns_setup_on_strong_sweep_into_fvg(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    liquidity = [
        _bullish_sweep(),
        {"type": "liquidity_pool_high", "liquidity_level": 112.0},
    ]
    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    monkeypatch.setattr(strategy, "_scan_liquidity_map", lambda _df: liquidity)

    setup = strategy.find_setup(bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)
    assert setup is not None
    assert setup.direction == "BUY"
    assert setup.stop_loss < 103.7
    # Nearest structural target (FVG top=106.0) is below the 2.5R floor,
    # so rr_floor wins.  Old logic picked farthest (112.0), new logic
    # picks nearest structural then enforces min R:R.
    risk = abs(setup.entry_price - setup.stop_loss)
    expected_rr_floor = setup.entry_price + risk * 2.5
    assert abs(setup.take_profit - expected_rr_floor) < 0.01
    assert setup.metadata["target_source"] == "rr_floor"
    assert setup.metadata["sweep_quality"] == "strong"


def test_find_setup_dedupes_same_sweep_when_bar_index_slides(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy({**_base_config(), "min_rr_ratio": 1.0})
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    sweeps = [
        _bullish_sweep(),
        {**_bullish_sweep(), "bar_index": 212},
    ]
    call_count = {"value": 0}

    def _scan_liquidity(_df):
        idx = min(call_count["value"], len(sweeps) - 1)
        call_count["value"] += 1
        return [sweeps[idx], {"type": "liquidity_pool_high", "liquidity_level": 112.0}]

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    monkeypatch.setattr(strategy, "_scan_liquidity_map", _scan_liquidity)

    first = strategy.find_setup(bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)
    second = strategy.find_setup(bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)

    assert first is not None
    assert second is None


def test_find_setup_resets_sweep_keys_when_session_cycle_changes(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy({**_base_config(), "min_rr_ratio": 1.0})
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    monkeypatch.setattr(strategy, "_scan_liquidity_map", lambda _df: [_bullish_sweep(), {"type": "liquidity_pool_high", "liquidity_level": 112.0}])

    asian_bar = bar.copy()
    asian_bar.name = pd.Timestamp("2026-01-05 04:00:00", tz="UTC")
    london_bar = bar.copy()
    london_bar.name = pd.Timestamp("2026-01-05 09:00:00", tz="UTC")

    first = strategy.find_setup(asian_bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)
    second = strategy.find_setup(london_bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0), len(df) - 1)

    assert first is not None
    assert second is not None


def test_find_setup_uses_execution_open_for_rr_gate(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy({**_base_config(), "min_rr_ratio": 1.5})
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    monkeypatch.setattr(
        strategy,
        "_scan_liquidity_map",
        lambda _df: [_bullish_sweep(), {"type": "liquidity_pool_high", "liquidity_level": 112.0}],
    )
    monkeypatch.setattr(strategy, "_compute_stop_loss", lambda *_args, **_kwargs: 104.0)
    monkeypatch.setattr(strategy, "_compute_take_profit", lambda **kwargs: (108.5, "fixed"))

    ctx = DayContext(
        date=datetime(2026, 1, 5),
        atr=1.0,
        levels={"execution_open": 106.5},
    )
    setup = strategy.find_setup(bar, df, ctx, len(df) - 1)

    assert setup is None


def test_find_setup_blocks_on_high_impact_news_when_guardrail_enabled(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy({**_base_config(), "guardrail_news_filter_enabled": True})
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bullish", 60))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    monkeypatch.setattr(strategy, "_scan_liquidity_map", lambda _df: [_bullish_sweep(), {"type": "liquidity_pool_high", "liquidity_level": 112.0}])

    ctx = DayContext(
        date=datetime(2026, 1, 5),
        atr=1.0,
        levels={"news_high_impact": True},
    )
    setup = strategy.find_setup(bar, df, ctx, len(df) - 1)

    assert setup is None


def test_should_close_early_on_fvg_invalidation():
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    bar = pd.Series({"close": 103.5}, name=pd.Timestamp("2026-01-05 15:00", tz="UTC"))
    df = _base_df(20)
    position = SimpleNamespace(
        direction="BUY",
        fvg_top=106.0,
        fvg_bottom=104.0,
        entry_price=105.0,
        stop_loss=102.5,
        entry_time=df.index[-10],
        strategy_metadata={"sweep_extreme": 103.0},
    )

    assert strategy.should_close_early(bar, df, position, DayContext(date=datetime(2026, 1, 5), atr=1.0)) == "FVG Invalidation"


def test_should_close_early_on_momentum_fade():
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df(80)
    bar = pd.Series({"close": 105.2}, name=df.index[-1])
    position = SimpleNamespace(
        direction="BUY",
        fvg_top=106.0,
        fvg_bottom=104.0,
        entry_price=105.0,
        stop_loss=104.0,
        entry_time=df.index[-40],
        strategy_metadata={"sweep_extreme": 103.0},
    )

    assert strategy.should_close_early(bar, df, position, DayContext(date=datetime(2026, 1, 5), atr=1.0)) == "Momentum Fade"


def test_bias_alignment_blocks_countertrend(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    # Use a *moderate* sweep — strong sweeps intentionally override the
    # bias block (A1 fix), so only moderate/weak sweeps are rejected.
    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bearish", 70))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    moderate_sweep = _bullish_sweep(rejection_ratio=0.45, quality="moderate")
    monkeypatch.setattr(strategy, "_scan_liquidity_map", lambda _df: [moderate_sweep, {"type": "liquidity_pool_high", "liquidity_level": 112.0}])

    setup = strategy.find_setup(bar, df, DayContext(date=datetime(2026, 1, 5), atr=1.0, bias="bearish", bias_strength=70), len(df) - 1)
    assert setup is None


def test_bias_alignment_allows_countertrend_when_sweep_is_strong(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    df = _base_df()
    bar = df.iloc[-1].copy()
    bar["low"] = 104.5
    bar["high"] = 106.4
    bar["close"] = 105.5

    monkeypatch.setattr(strategy, "_compute_bias", lambda _df: ("bearish", 70))
    monkeypatch.setattr(strategy, "_scan_htf_fvgs", lambda _df, _atr: [_bullish_fvg()])
    strong_sweep = _bullish_sweep(rejection_ratio=0.72, quality="strong")
    monkeypatch.setattr(
        strategy,
        "_scan_liquidity_map",
        lambda _df: [strong_sweep, {"type": "liquidity_pool_high", "liquidity_level": 112.0}],
    )

    setup = strategy.find_setup(
        bar,
        df,
        DayContext(date=datetime(2026, 1, 5), atr=1.0, bias="bearish", bias_strength=70),
        len(df) - 1,
    )
    assert setup is not None
    assert setup.direction == "BUY"
    assert str(setup.metadata.get("sweep_quality") or "") == "strong"


def test_scan_htf_fvgs_uses_htf_atr_for_proximity_and_scoring(monkeypatch):
    strategy = HTFFVGLiquidityReclaimStrategy(
        {
            **_base_config(),
            "htf_timeframe": "H4",
            "secondary_htf_timeframe": "",
            "fvg_proximity_atr": 2.0,
            "htf_fvg_lookback_bars": 40,
        }
    )
    df = _base_df(220)
    df.iloc[-1, df.columns.get_loc("close")] = 100.0

    htf_idx = pd.date_range("2026-01-01", periods=20, freq="4h", tz="UTC")
    htf_df = pd.DataFrame(
        {
            "open": [100.0] * 20,
            "high": [101.0] * 20,
            "low": [99.0] * 20,
            "close": [100.0] * 20,
            "volume": [1000.0] * 20,
        },
        index=htf_idx,
    )

    monkeypatch.setattr(reclaim_mod, "resample_ohlcv", lambda *_args, **_kwargs: htf_df.copy())
    monkeypatch.setattr(reclaim_mod, "atr_last", lambda data, _period=14: 20.0 if len(data) == len(htf_df) else 1.0)
    monkeypatch.setattr(
        reclaim_mod,
        "detect_fvg_zones",
        lambda *_args, **_kwargs: [
            {
                "type": "bearish_fvg",
                "top": 130.0,
                "bottom": 128.0,
                "gap_size": 2.0,
                "current_gap_size": 2.0,
                "original_gap_size": 2.0,
                "bar_index": len(htf_df) - 1,
                "mitigations": 0,
            }
        ],
    )

    detail = strategy._scan_htf_fvgs_detailed(df, atr=1.0)

    assert int(detail.get("raw_zones_count") or 0) == 1
    assert int(detail.get("candidate_count") or 0) == 1
    candidates = detail.get("candidates") if isinstance(detail.get("candidates"), list) else []
    assert len(candidates) == 1
    assert float(candidates[0].get("distance_from_price") or 0.0) == 28.0
    tf_detail = detail.get("scan_detail") if isinstance(detail.get("scan_detail"), list) else []
    assert len(tf_detail) == 1
    assert float(tf_detail[0].get("proximity_limit") or 0.0) == 40.0


def test_confidence_uses_session_windows_not_raw_utc_buckets():
    strategy = HTFFVGLiquidityReclaimStrategy(_base_config())
    fvg = _bullish_fvg()
    london_sweep = _bullish_sweep()
    asian_sweep = _bullish_sweep()
    # 2026-01-05 09:00 UTC = 04:00 NY => London session
    london_sweep["end_time_unix"] = int(pd.Timestamp("2026-01-05 09:00:00", tz="UTC").timestamp())
    # 2026-01-05 04:00 UTC = 23:00 NY(previous day) => Asian session
    asian_sweep["end_time_unix"] = int(pd.Timestamp("2026-01-05 04:00:00", tz="UTC").timestamp())

    london_score = strategy._compute_confidence(
        fvg=fvg,
        sweep=london_sweep,
        bias="bullish",
        bias_strength=60,
        atr=1.0,
        day_context=DayContext(date=datetime(2026, 1, 5), atr=1.0),
    )
    asian_score = strategy._compute_confidence(
        fvg=fvg,
        sweep=asian_sweep,
        bias="bullish",
        bias_strength=60,
        atr=1.0,
        day_context=DayContext(date=datetime(2026, 1, 5), atr=1.0),
    )

    assert london_score > asian_score
