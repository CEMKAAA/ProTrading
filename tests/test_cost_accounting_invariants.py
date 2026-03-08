"""
Cost-accounting invariants for trade close path.

Validates:
- net_pnl accounting: gross - exit_commission + swap
- balance progression consistency with entry/exit commissions + swap
- R-multiple is based on net PnL and initial risk
"""

from datetime import datetime

import pandas as pd
import pytest

from dashboard.backend.core.backtest_engine import BacktestConfig, BacktestEngine, DayState, Position


def _make_engine() -> BacktestEngine:
    config = BacktestConfig(
        symbol="NAS100",
        timeframe="M15",
        start_date=datetime(2024, 1, 1),
        end_date=datetime(2024, 1, 31),
        initial_balance=10000.0,
        contract_size=1.0,
        commission_per_lot=2.0,  # round-trip
        simulate_spread=False,
        simulate_slippage=False,
        simulate_swap=True,
        random_seed=42,
    )
    engine = BacktestEngine(config)
    engine.day_state = DayState(date=datetime(2024, 1, 2))
    return engine


@pytest.mark.parametrize(
    "direction,entry_price,exit_price,swap_pnl",
    [
        ("BUY", 100.0, 110.0, -3.0),
        ("SELL", 100.0, 90.0, -3.0),
        ("BUY", 100.0, 110.0, 2.0),
    ],
)
def test_close_position_cost_accounting_invariants(
    direction: str,
    entry_price: float,
    exit_price: float,
    swap_pnl: float,
) -> None:
    engine = _make_engine()
    lot = 1.0
    entry_commission = (engine.config.commission_per_lot * lot) / 2.0
    exit_commission = (engine.config.commission_per_lot * lot) / 2.0

    # Entry commission is deducted at open, so close starts from this balance.
    engine.balance = engine.config.initial_balance - entry_commission

    if direction == "BUY":
        stop_loss = entry_price - 5.0
        take_profit = entry_price + 15.0
        gross = (exit_price - entry_price) * lot * engine.config.contract_size
    else:
        stop_loss = entry_price + 5.0
        take_profit = entry_price - 15.0
        gross = (entry_price - exit_price) * lot * engine.config.contract_size

    entry_time = pd.Timestamp("2024-01-02 10:00:00", tz="America/New_York").to_pydatetime()
    pos = Position(
        direction=direction,
        entry_time=entry_time,
        entry_price=entry_price,
        stop_loss=stop_loss,
        initial_stop_loss=stop_loss,
        take_profit=take_profit,
        lot_size=lot,
        setup_type="unit-test",
        bias="neutral",
        orb_high=0.0,
        orb_low=0.0,
        asian_high=0.0,
        asian_low=0.0,
        pd_high=0.0,
        pd_low=0.0,
        spread_cost=0.0,
        slippage_cost=0.0,
        commission_cost=entry_commission,
        swap_cost=swap_pnl,
    )
    engine.open_position = pos

    bar = pd.Series(
        {"open": entry_price, "high": max(entry_price, exit_price), "low": min(entry_price, exit_price), "close": exit_price},
        name=pd.Timestamp("2024-01-02 11:00:00", tz="America/New_York"),
    )

    engine._close_position(bar=bar, exit_reason="Unit Test Exit", exit_price=exit_price)
    trade = engine.trades[-1]

    expected_net = gross - exit_commission + swap_pnl
    expected_final_balance = engine.config.initial_balance + gross - entry_commission - exit_commission + swap_pnl
    initial_risk = abs(entry_price - stop_loss) * lot * engine.config.contract_size

    assert trade.gross_pnl == pytest.approx(round(gross, 2))
    assert trade.profit_loss == pytest.approx(round(expected_net, 2))
    assert trade.swap_cost == pytest.approx(round(swap_pnl, 2))
    assert trade.commission_cost == pytest.approx(round(entry_commission + exit_commission, 2))

    assert trade.balance_before == pytest.approx(engine.config.initial_balance - entry_commission)
    assert trade.balance_after == pytest.approx(expected_final_balance)
    assert engine.balance == pytest.approx(expected_final_balance)

    expected_r = round(expected_net / initial_risk, 2)
    assert trade.r_multiple == pytest.approx(expected_r)
