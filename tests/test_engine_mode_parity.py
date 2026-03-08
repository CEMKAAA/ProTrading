"""
Legacy vs advanced engine parity test on deterministic synthetic data.
"""

from dataclasses import replace
from datetime import datetime

import pandas as pd

from dashboard.backend.core.advanced_backtest_engine import AdvancedEventBacktestEngine
from dashboard.backend.core.backtest_engine import BacktestConfig, BacktestEngine
from dashboard.backend.core.strategies.base import BacktestStrategy, DayContext, TradeSetup


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


class DeterministicSingleTradeStrategy(BacktestStrategy):
    """Non-ORB strategy that emits exactly one setup per run."""

    def __init__(self, config):
        super().__init__(config)
        self._triggered = False

    def initialize_day(self, date, daily_df, intraday_df):
        return DayContext(date=date, bias="neutral", bias_strength=0, atr=1.0)

    def find_setup(self, bar, df, day_context, current_bar_index):
        if self._triggered or len(df) < 2:
            return None
        self._triggered = True
        entry_ref = float(bar["close"])
        return TradeSetup(
            direction="BUY",
            entry_price=entry_ref,
            stop_loss=entry_ref - 1.0,
            take_profit=entry_ref + 2.0,
            setup_type="deterministic-single-trade",
            confidence=100.0,
            metadata={},
        )


def _build_test_data():
    idx = pd.date_range("2024-01-02 09:30", periods=8, freq="15min", tz="America/New_York")
    df = pd.DataFrame(
        {
            "open": [100.0, 100.2, 101.0, 101.2, 101.5, 101.7, 101.8, 101.9],
            "high": [100.4, 100.8, 101.4, 103.0, 101.9, 102.0, 102.1, 102.2],
            "low": [99.8, 100.0, 100.6, 100.9, 101.2, 101.5, 101.6, 101.7],
            "close": [100.2, 100.5, 101.2, 102.8, 101.6, 101.8, 101.9, 102.0],
            "volume": [10, 12, 11, 15, 9, 8, 7, 6],
            "spread": [0.0] * 8,
        },
        index=idx,
    )
    daily = pd.DataFrame(
        {
            "open": [100.0],
            "high": [103.0],
            "low": [99.8],
            "close": [102.0],
            "volume": [78],
        },
        index=pd.DatetimeIndex([pd.Timestamp("2024-01-02 00:00:00", tz="America/New_York")]),
    )
    return df, daily


def _base_config():
    return BacktestConfig(
        symbol="NAS100",
        timeframe="M15",
        start_date=datetime(2024, 1, 2),
        end_date=datetime(2024, 1, 2, 23, 59, 59),
        initial_balance=10000.0,
        risk_percent=1.0,
        simulate_spread=False,
        simulate_slippage=False,
        simulate_swap=False,
        use_trailing=False,
        max_daily_trades=5,
        trade_start_time="09:30",
        trade_end_time="12:00",
        data_source="csv_only",
        random_seed=42,
    )


def test_legacy_and_advanced_engines_produce_same_result_on_deterministic_setup():
    df, daily = _build_test_data()

    legacy_cfg = _base_config()
    advanced_cfg = replace(legacy_cfg)

    legacy_engine = BacktestEngine(legacy_cfg, strategy=DeterministicSingleTradeStrategy({}))
    advanced_engine = AdvancedEventBacktestEngine(
        advanced_cfg, strategy=DeterministicSingleTradeStrategy({})
    )
    legacy_engine.data_provider = StubHistoricalDataProvider(df, daily)
    advanced_engine.data_provider = StubHistoricalDataProvider(df, daily)

    legacy_results = legacy_engine.run()
    advanced_results = advanced_engine.run()

    legacy_metrics = legacy_results["metrics"]
    advanced_metrics = advanced_results["metrics"]

    assert legacy_metrics["total_trades"] == advanced_metrics["total_trades"]
    assert legacy_metrics["winning_trades"] == advanced_metrics["winning_trades"]
    assert legacy_metrics["losing_trades"] == advanced_metrics["losing_trades"]
    assert legacy_metrics["net_profit"] == advanced_metrics["net_profit"]
    assert legacy_metrics["final_balance"] == advanced_metrics["final_balance"]

    assert len(legacy_results["trades"]) == len(advanced_results["trades"]) == 1
    assert legacy_results["trades"][0]["direction"] == advanced_results["trades"][0]["direction"]
    assert legacy_results["trades"][0]["exit_reason"] == advanced_results["trades"][0]["exit_reason"]
    assert legacy_results["trades"][0]["profit_loss"] == advanced_results["trades"][0]["profit_loss"]
