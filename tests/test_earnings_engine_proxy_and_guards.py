"""
Engine-level tests for earnings proxy PnL and guard flags.
"""

from datetime import datetime

import pandas as pd

from dashboard.backend.core.backtest_engine import BacktestConfig, BacktestEngine, DayState, Position
from dashboard.backend.core.strategies.earnings_volatility_strategy import EarningsVolatilityStrategy


def _engine(contract_size: float = 1.0) -> BacktestEngine:
    cfg = BacktestConfig(
        symbol="AAPL",
        timeframe="M15",
        start_date=datetime(2024, 1, 2),
        end_date=datetime(2024, 1, 5, 23, 59, 59),
        initial_balance=10_000.0,
        contract_size=contract_size,
        simulate_spread=False,
        simulate_slippage=False,
        simulate_swap=False,
        use_trailing=False,
        random_seed=42,
    )
    engine = BacktestEngine(cfg)
    engine.day_state = DayState(date=datetime(2024, 1, 2))
    return engine


def _position(
    lot_size: float = 1.0,
    strategy_metadata=None,
    stop_loss: float = 95.0,
    take_profit: float = 105.0,
) -> Position:
    return Position(
        direction="BUY",
        entry_time=datetime(2024, 1, 2, 15, 45),
        entry_price=100.0,
        stop_loss=stop_loss,
        initial_stop_loss=stop_loss,
        take_profit=take_profit,
        lot_size=lot_size,
        setup_type="test",
        bias="neutral",
        orb_high=0.0,
        orb_low=0.0,
        asian_high=0.0,
        asian_low=0.0,
        pd_high=0.0,
        pd_low=0.0,
        strategy_metadata=strategy_metadata or {},
    )


def test_proxy_pnl_short_straddle_known_values_scales_by_lot_and_contract():
    engine = _engine(contract_size=2.0)
    pos = _position(
        lot_size=3.0,
        strategy_metadata={
            "pnl_model": "earnings_short_vol_proxy",
            "structure": "short_straddle",
            "premium_usd": 10.0,
            "expected_move_usd": 5.0,
            "move_penalty_mult": 1.0,
            "breach_penalty_mult": 2.5,
            "iv_point_value": 100.0,
            "calendar_back_vega_weight": 0.35,
            "iv_front_col": "iv_front",
            "iv_back_col": "iv_back",
            "iv_front_entry": 0.60,
            "iv_back_entry": 0.50,
        },
    )
    bar = pd.Series({"close": 102.0, "iv_front": 0.40, "iv_back": 0.50})

    result = engine._compute_proxy_pnl(pos, bar, 102.0)
    assert result is not None
    gross_pnl, diag = result

    # premium 10 + iv_crush_component 20 - move_penalty 4 = 26 per unit
    assert abs(diag["gross_per_unit_usd"] - 26.0) < 1e-9
    assert abs(gross_pnl - (26.0 * 3.0 * 2.0)) < 1e-9


def test_proxy_pnl_calendar_has_loss_floor():
    engine = _engine(contract_size=1.0)
    pos = _position(
        lot_size=1.0,
        strategy_metadata={
            "pnl_model": "earnings_short_vol_proxy",
            "structure": "long_calendar",
            "premium_usd": 10.0,
            "expected_move_usd": 5.0,
            "move_penalty_mult": 1.0,
            "breach_penalty_mult": 2.5,
            "iv_point_value": 100.0,
            "calendar_back_vega_weight": 0.35,
            "iv_front_col": "iv_front",
            "iv_back_col": "iv_back",
            "iv_front_entry": 0.60,
            "iv_back_entry": 0.50,
        },
    )
    # Extreme move, no front/back IV crush benefit -> should clamp at -105% of premium.
    bar = pd.Series({"close": 130.0, "iv_front": 0.60, "iv_back": 0.50})

    result = engine._compute_proxy_pnl(pos, bar, 130.0)
    assert result is not None
    gross_pnl, diag = result

    assert abs(diag["gross_per_unit_usd"] - (-10.5)) < 1e-9
    assert abs(gross_pnl - (-10.5)) < 1e-9


def test_manage_position_respects_disable_sl_tp_flag():
    engine = _engine(contract_size=1.0)
    engine.open_position = _position(
        strategy_metadata={"disable_sl_tp": True, "disable_trailing": True}
    )
    # This bar touches both SL and TP, but disable flag should prevent forced close.
    bar = pd.Series(
        {"open": 100.0, "high": 106.0, "low": 94.0, "close": 101.0},
        name=pd.Timestamp("2024-01-03 10:00", tz="America/New_York"),
    )
    df = pd.DataFrame([bar])

    engine._manage_position(bar, df)

    assert engine.open_position is not None
    assert len(engine.trades) == 0


def test_event_schedule_builder_maps_entry_and_exit_days():
    idx = pd.to_datetime(
        [
            "2024-01-01 12:00",
            "2024-01-02 12:00",
            "2024-01-03 12:00",
            "2024-01-04 12:00",
            "2024-01-05 12:00",
        ]
    ).tz_localize("America/New_York")
    df = pd.DataFrame(
        {"earnings_event": [True, False, True, False, True], "close": [1, 1, 1, 1, 1]},
        index=idx,
    )

    mapping = EarningsVolatilityStrategy._build_event_schedule(df, "earnings_event")
    # Event on Jan-03 => entry Jan-02, exit Jan-04
    assert datetime(2024, 1, 2).date() in mapping
    assert mapping[datetime(2024, 1, 2).date()] == (
        datetime(2024, 1, 3).date(),
        datetime(2024, 1, 4).date(),
    )
    # Edge events (first/last day) are skipped by construction.
    assert datetime(2024, 1, 1).date() not in mapping
    assert datetime(2024, 1, 4).date() not in mapping
