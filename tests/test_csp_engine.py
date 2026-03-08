import numpy as np
import pandas as pd

from dashboard.backend.core.options_edge.csp_engine import CSPLifecycleEngine
from dashboard.backend.core.options_edge.csp_models import CSPBacktestConfig


def _market_df(start: str, periods: int, start_px: float, end_px: float, iv: float = 0.35):
    idx = pd.date_range(start=start, periods=periods, freq="D")
    close = np.linspace(start_px, end_px, periods)
    return pd.DataFrame(
        {
            "date": idx.date,
            "close": close,
            "iv_proxy": np.full(periods, iv),
            "price_vs_sma200": np.full(periods, 5.0),
        }
    )


def test_csp_engine_roll_trigger_helper():
    eng = CSPLifecycleEngine(CSPBacktestConfig())
    assert eng._should_roll(initial_premium=2.0, current_value=0.4, dte=25) is True
    assert eng._should_roll(initial_premium=2.0, current_value=0.15, dte=7) is True
    assert eng._should_roll(initial_premium=2.0, current_value=1.5, dte=20) is False


def test_csp_engine_backtest_generates_premium_events():
    cfg = CSPBacktestConfig(initial_capital=100_000.0, normal_yield_min_pct=0.1, normal_yield_max_pct=15.0)
    eng = CSPLifecycleEngine(cfg)
    df = _market_df("2025-01-01", periods=120, start_px=100.0, end_px=115.0, iv=0.40)
    out = eng.run_symbol_backtest(symbol="AAPL", market_df=df)
    assert out["status"] == "COMPLETED"
    assert out["metrics"]["total_premium_collected"] > 0.0
    assert out["metrics"]["total_events"] > 0
    assert len(out["equity_curve"]) > 0


def test_csp_engine_can_assign_on_downtrend():
    cfg = CSPBacktestConfig(initial_capital=100_000.0, normal_yield_min_pct=0.1, normal_yield_max_pct=20.0)
    eng = CSPLifecycleEngine(cfg)
    df = _market_df("2025-01-01", periods=95, start_px=100.0, end_px=55.0, iv=0.45)
    out = eng.run_symbol_backtest(symbol="TSLA", market_df=df)
    assert out["status"] == "COMPLETED"
    assert out["metrics"]["assigned_count"] >= 1

