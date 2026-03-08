"""
Integration tests for earnings volatility strategy in BacktestEngine.
"""

from datetime import datetime

import pandas as pd

from dashboard.backend.core.backtest_engine import BacktestConfig, BacktestEngine
from dashboard.backend.core.strategies.earnings_volatility_strategy import EarningsVolatilityStrategy


class EarningsStubProvider:
    def __init__(self):
        idx = pd.to_datetime(
            [
                "2024-01-02 15:15",
                "2024-01-02 15:30",
                "2024-01-02 15:45",
                # Earnings day bar (large range that would normally hit SL/TP)
                "2024-01-03 10:00",
                # Day after earnings
                "2024-01-04 09:30",
                "2024-01-04 09:45",
                "2024-01-04 10:00",
            ]
        ).tz_localize("America/New_York")
        self.df = pd.DataFrame(
            {
                "open": [100.0, 100.0, 100.1, 100.2, 100.0, 99.8, 99.9],
                "high": [100.2, 100.3, 100.4, 120.0, 100.2, 100.0, 100.1],
                "low": [99.8, 99.9, 99.7, 80.0, 99.5, 99.4, 99.6],
                "close": [100.0, 100.1, 100.0, 100.2, 99.9, 99.8, 100.0],
                "volume": [1000, 1000, 1000, 1000, 1000, 1000, 1000],
                "spread": [0.0] * 7,
                "earnings_event": [False, False, False, True, False, False, False],
                "days_to_earnings": [1, 1, 1, 0, 999, 999, 999],
                "is_pre_earnings_day": [True, True, True, False, False, False, False],
                "next_earnings_date": ["2024-01-03"] * 7,
                "planned_exit_date": ["2024-01-04"] * 7,
                "iv_front": [0.62, 0.60, 0.61, 0.58, 0.32, 0.28, 0.27],
                "iv_back": [0.50, 0.50, 0.49, 0.49, 0.36, 0.34, 0.34],
                "iv_45d": [0.45, 0.45, 0.45, 0.46, 0.41, 0.40, 0.40],
                "iv30": [0.55, 0.55, 0.55, 0.54, 0.41, 0.40, 0.40],
                "rv30": [0.30] * 7,
                "volume30": [10_000_000] * 7,
            },
            index=idx,
        )
        self.daily = pd.DataFrame(
            {
                "open": [100.0, 100.2, 99.9],
                "high": [100.4, 120.0, 100.2],
                "low": [99.7, 80.0, 99.4],
                "close": [100.0, 100.2, 100.0],
                "volume": [3000, 1000, 3000],
            },
            index=pd.DatetimeIndex(
                [
                    pd.Timestamp("2024-01-02 00:00:00", tz="America/New_York"),
                    pd.Timestamp("2024-01-03 00:00:00", tz="America/New_York"),
                    pd.Timestamp("2024-01-04 00:00:00", tz="America/New_York"),
                ]
            ),
        )

    def get_historical_data(self, *args, **kwargs):
        return self.df.copy()

    def validate_data_quality(self, df, min_bars=200):
        return True, "ok"

    def get_daily_data(self, *args, **kwargs):
        return self.daily.copy()

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


def test_earnings_strategy_uses_timed_exit_and_proxy_pnl():
    cfg = BacktestConfig(
        symbol="AAPL",
        timeframe="M15",
        start_date=datetime(2024, 1, 2),
        end_date=datetime(2024, 1, 4, 23, 59, 59),
        initial_balance=10000.0,
        risk_percent=6.0,
        contract_size=1.0,
        simulate_spread=False,
        simulate_slippage=False,
        simulate_swap=False,
        use_trailing=True,
        trade_start_time="09:30",
        trade_end_time="16:00",
        max_daily_trades=2,
        data_source="csv_only",
        random_seed=42,
    )
    strategy = EarningsVolatilityStrategy(
        {
            "vol_structure": "long_calendar",
            "entry_time": "15:45",
            "exit_time": "09:45",
            "term_structure_max_slope": -0.05,
            "min_avg_volume30": 5_000_000,
            "min_iv30_rv30_ratio": 1.25,
            "allow_event_lookahead": False,
            "simulate_spread": False,
            "simulate_slippage": False,
            "simulate_swap": False,
            "use_trailing": False,
        }
    )

    engine = BacktestEngine(cfg, strategy=strategy)
    engine.data_provider = EarningsStubProvider()
    results = engine.run()

    assert results["metrics"]["total_trades"] == 1
    trade = results["trades"][0]
    assert trade["exit_reason"] == "Post-Earnings Timed Exit"
    assert trade["entry_reason"]["pnl_model"] == "earnings_short_vol_proxy"
    assert "proxy_pnl" in trade["entry_reason"]
