from __future__ import annotations

from dataclasses import replace
from datetime import datetime

import pandas as pd

from dashboard.backend.core.backtest_engine import BacktestConfig, BacktestEngine
from dashboard.backend.core.strategies.htf_fvg_liquidity_reclaim_strategy import (
    HTFFVGLiquidityReclaimStrategy,
)


class StubHistoricalDataProvider:
    def __init__(self, df: pd.DataFrame, daily_df: pd.DataFrame):
        self._df = df
        self._daily = daily_df

    def get_historical_data(self, *args, **kwargs):
        return self._df.copy()

    def validate_data_quality(self, df, min_bars=200):
        return True, "ok"

    def get_daily_data(self, *args, **kwargs):
        return self._daily.copy()

    def get_trading_days(self, df):
        return [datetime.combine(d, datetime.min.time()) for d in pd.unique(df.index.date)]

    def get_previous_day_session(self, *args, **kwargs):
        return None, None

    def get_asian_session(self, *args, **kwargs):
        return None, None

    def get_london_session(self, *args, **kwargs):
        return None, None

    def get_orb_levels(self, *args, **kwargs):
        return None, None

    def calculate_adr(self, df_daily, period=5):
        return pd.Series([20.0] * len(df_daily), index=df_daily.index)

    def calculate_atr(self, df, period=14):
        return pd.Series([1.0] * len(df), index=df.index)

    def shutdown_mt5(self):
        return None


def _build_test_data():
    idx = pd.date_range("2024-01-02 09:30", periods=64, freq="15min", tz="America/New_York")
    close = [107.0 - (0.03 * i) for i in range(64)]
    open_ = [c - 0.05 for c in close]
    high = [c + 0.45 for c in close]
    low = [c - 0.45 for c in close]
    volume = [1000.0] * 64

    # Signal bar: retraces into the bullish FVG zone.
    low[40] = 104.4
    high[40] = 106.2
    close[40] = 105.4
    open_[40] = 105.1

    # After entry, TP gets hit.
    high[44] = 108.6
    close[44] = 108.1

    df = pd.DataFrame(
        {
            "open": open_,
            "high": high,
            "low": low,
            "close": close,
            "volume": volume,
            "spread": [0.0] * 64,
        },
        index=idx,
    )
    daily = pd.DataFrame(
        {
            "open": [107.0],
            "high": [108.6],
            "low": [103.5],
            "close": [106.2],
            "volume": [64000],
        },
        index=pd.DatetimeIndex([pd.Timestamp("2024-01-02 00:00:00", tz="America/New_York")]),
    )
    return df, daily


def test_strategy_runs_through_engine_without_errors():
    df, daily = _build_test_data()
    cfg = BacktestConfig(
        symbol="XAUUSD",
        timeframe="M15",
        start_date=datetime(2024, 1, 2),
        end_date=datetime(2024, 1, 2, 23, 59, 59),
        initial_balance=10000.0,
        risk_percent=1.0,
        simulate_spread=False,
        simulate_slippage=False,
        simulate_swap=False,
        use_trailing=False,
        max_daily_trades=2,
        trade_start_time="09:30",
        trade_end_time="20:00",
        data_source="csv_only",
        random_seed=42,
    )
    strategy = HTFFVGLiquidityReclaimStrategy(
        {
            "symbol": "XAUUSD",
            "timeframe": "M15",
            "required_lookback_bars": 60,
            "min_rejection_ratio": 0.30,
            "min_rr_ratio": 1.0,
            "sl_buffer_atr": 0.15,
            "bias_min_strength": 30,
        }
    )
    strategy._compute_bias = lambda _df: ("bullish", 60)  # type: ignore[method-assign]
    strategy._scan_htf_fvgs = lambda _df, _atr: [  # type: ignore[method-assign]
        {
            "type": "bullish_fvg",
            "top": 106.0,
            "bottom": 104.0,
            "timeframe": "H4",
            "end_time_unix": 1770000000,
            "quality_score": 80.0,
            "quality_label": "strong",
            "distance_from_price": 0.5,
            "mitigations": 0,
        }
    ]
    strategy._scan_liquidity_map = lambda _df: [  # type: ignore[method-assign]
        {
            "type": "liquidity_sweep_low",
            "swept_price": 103.7,
            "pool_boundary": 104.2,
            "liquidity_level": 104.5,
            "rejection_ratio": 0.72,
            "rejection_quality": "strong",
            "swept_pool_touches": 3,
            "bar_index": max(0, len(_df) - 4),
        },
        {
            "type": "liquidity_pool_high",
            "liquidity_level": 108.0,
        },
    ]

    engine = BacktestEngine(replace(cfg), strategy=strategy)
    engine.data_provider = StubHistoricalDataProvider(df, daily)
    results = engine.run()

    assert results["metrics"]["total_trades"] >= 1
    assert not results.get("error_message")
