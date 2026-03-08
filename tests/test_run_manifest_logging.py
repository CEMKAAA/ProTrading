"""
Run manifest coverage tests.
"""

from datetime import datetime

import pandas as pd

from dashboard.backend.core.backtest_engine import BacktestConfig, BacktestEngine
from dashboard.backend.core.strategies.base import BacktestStrategy, DayContext


class NoopStrategy(BacktestStrategy):
    def initialize_day(self, date, daily_df, intraday_df):
        return DayContext(date=date, bias="neutral", bias_strength=0, atr=1.0)

    def find_setup(self, bar, df, day_context, current_bar_index):
        return None


class ManifestStubProvider:
    def __init__(self):
        idx = pd.date_range("2024-01-02 09:30", periods=4, freq="15min", tz="America/New_York")
        self.df = pd.DataFrame(
            {
                "open": [100.0, 100.2, 100.3, 100.4],
                "high": [100.3, 100.4, 100.5, 100.6],
                "low": [99.9, 100.1, 100.2, 100.3],
                "close": [100.2, 100.3, 100.4, 100.5],
                "volume": [10, 10, 10, 10],
                "spread": [0.0, 0.0, 0.0, 0.0],
            },
            index=idx,
        )
        self.daily = pd.DataFrame(
            {
                "open": [100.0],
                "high": [100.6],
                "low": [99.9],
                "close": [100.5],
                "volume": [40],
            },
            index=pd.DatetimeIndex([pd.Timestamp("2024-01-02 00:00:00", tz="America/New_York")]),
        )

    def get_historical_data(self, *args, **kwargs):
        return self.df.copy()

    def validate_data_quality(self, df, min_bars=200):
        return True, "ok"

    def get_daily_data(self, *args, **kwargs):
        return self.daily.copy()

    def get_trading_days(self, df):
        return [datetime(2024, 1, 2)]

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


def test_backtest_results_include_run_manifest_with_effective_config_and_hashes():
    cfg = BacktestConfig(
        symbol="XAUUSD",
        timeframe="M15",
        start_date=datetime(2024, 1, 2),
        end_date=datetime(2024, 1, 2, 23, 59, 59),
        initial_balance=10000.0,
        simulate_spread=False,
        simulate_slippage=False,
        simulate_swap=False,
        data_source="csv_only",
        random_seed=42,
    )
    engine = BacktestEngine(cfg, strategy=NoopStrategy({}))
    engine.data_provider = ManifestStubProvider()
    results = engine.run()

    manifest = results.get("run_manifest")
    assert manifest is not None
    assert isinstance(manifest.get("code_hash"), str) and len(manifest["code_hash"]) == 64
    assert manifest.get("data_hash") == results.get("data_hash")
    assert manifest.get("engine_class") == "BacktestEngine"
    assert manifest.get("effective_config", {}).get("symbol") == "XAUUSD"
    assert manifest.get("effective_config", {}).get("timeframe") == "M15"
