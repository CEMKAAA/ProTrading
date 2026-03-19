from datetime import datetime
from types import SimpleNamespace

import numpy as np
import pandas as pd

from dashboard.backend.core.strategies.base import DayContext
from dashboard.backend.core.strategies.factory import create_strategy
from dashboard.backend.core.strategies.trendilo_strategy import TrendiloStrategy
from dashboard.backend.core.strategies.advanced_trendilo_strategy import AdvancedTrendiloStrategy


def _build_df(*, bullish_spike: bool = True) -> pd.DataFrame:
    idx = pd.date_range("2026-01-01", periods=420, freq="15min", tz="UTC")
    base = 100.0 + np.sin(np.arange(420) / 11.0) * 0.08
    close = base.copy()
    if bullish_spike:
        close[-1] = close[-2] + 6.0
    else:
        close[-1] = close[-2] - 6.0
    open_ = np.roll(close, 1)
    open_[0] = close[0]
    high = np.maximum(open_, close) + 0.25
    low = np.minimum(open_, close) - 0.25
    vol = np.full(420, 1000.0)
    vol[-1] = 1600.0
    return pd.DataFrame(
        {
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": vol,
        },
        index=idx,
    )


def test_factory_creates_trendilo_strategy():
    s = create_strategy("trendilo_strategy", {})
    assert isinstance(s, TrendiloStrategy)


def test_factory_creates_advanced_trendilo_strategy():
    s = create_strategy("advanced_trendilo_strategy", {})
    assert isinstance(s, AdvancedTrendiloStrategy)


def test_find_setup_detects_bullish_signal():
    strategy = TrendiloStrategy(
        {
            "trend_filter_length": 120,
            "trendilo_length": 20,
            "trendilo_pct_lookback": 4,
            "adx_threshold": 5.0,
            "rr_ratio": 2.0,
            "atr_stop_mult": 1.5,
        }
    )
    df = _build_df(bullish_spike=True)
    bar = df.iloc[-1]
    setup = strategy.find_setup(
        bar=bar,
        df=df,
        day_context=DayContext(date=datetime(2026, 1, 1), bias="neutral", bias_strength=0, atr=1.0),
        current_bar_index=len(df) - 1,
    )
    assert setup is not None
    assert setup.direction == "BUY"
    assert setup.take_profit is not None
    assert float(setup.take_profit) > float(setup.entry_price)


def test_advanced_trendilo_requires_persistence_when_configured():
    strategy = AdvancedTrendiloStrategy(
        {
            "trend_filter_length": 120,
            "trendilo_length": 20,
            "trendilo_pct_lookback": 4,
            "adx_threshold": 5.0,
            "rr_ratio": 2.0,
            "atr_stop_mult": 1.5,
            "min_persistence_bars": 1000,
            "min_edge_ratio": 0.01,
            "require_adx_rising": False,
            "failed_breakout_cooldown_bars": 0,
            "min_di_spread": 0.0,
        }
    )
    df = _build_df(bullish_spike=True)
    bar = df.iloc[-1]
    setup = strategy.find_setup(
        bar=bar,
        df=df,
        day_context=DayContext(date=datetime(2026, 1, 1), bias="neutral", bias_strength=0, atr=1.0),
        current_bar_index=len(df) - 1,
    )
    assert setup is None


def test_should_close_early_on_bearish_flip_for_long():
    strategy = TrendiloStrategy(
        {
            "trend_filter_length": 120,
            "trendilo_length": 20,
            "trendilo_pct_lookback": 4,
            "adx_threshold": 5.0,
        }
    )
    df = _build_df(bullish_spike=False)
    bar = df.iloc[-1]
    position = SimpleNamespace(direction="BUY")
    reason = strategy.should_close_early(
        bar=bar,
        df=df,
        position=position,
        day_context=DayContext(date=datetime(2026, 1, 1), bias="neutral", bias_strength=0, atr=1.0),
    )
    assert isinstance(reason, str) and reason
