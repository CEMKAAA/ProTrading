import asyncio
from datetime import datetime, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from Strategies.strategy_manager import StrategyManager
from dashboard.backend.api.routes import (
    get_capital_allocation,
    get_unified_portfolio_overview,
)
from dashboard.backend.models.database import (
    Base,
    LiveTradeModel,
    OptionsEdgeTradeJournalModel,
    TradeDirection,
    TradeStatus,
)


def test_strategy_manager_allocations_include_options_proxy(monkeypatch):
    manager = StrategyManager()

    monkeypatch.setattr(manager, "_is_process_running", lambda _sid: False)
    monkeypatch.setattr(manager, "_get_options_journal_open_risk_usd", lambda *args, **kwargs: 1234.5)

    alloc = manager.get_allocated_capital()
    assert "options_edge_manual" in alloc
    assert alloc["options_edge_manual"] == 1234.5


def test_capital_allocation_reports_cross_system_flag(monkeypatch):
    import Strategies.strategy_manager as sm

    monkeypatch.setattr(sm.StrategyManager, "get_account_balance", lambda self: 10000.0)
    monkeypatch.setattr(sm.StrategyManager, "get_allocated_capital", lambda self: {"orb_strategy": 2000.0, "options_edge_manual": 900.0})

    resp = asyncio.run(get_capital_allocation())
    assert resp["total_allocated"] == 2900.0
    assert resp["options_open_risk_usd"] == 900.0
    assert resp["has_cross_system_risk"] is True


def test_unified_portfolio_overview_aggregates_live_and_options(monkeypatch):
    import Strategies.strategy_manager as sm

    monkeypatch.setattr(sm.StrategyManager, "get_account_balance", lambda self: 12000.0)
    monkeypatch.setattr(sm.StrategyManager, "get_allocated_capital", lambda self: {"orb_strategy": 2500.0, "options_edge_manual": 600.0})

    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        db.add(
            LiveTradeModel(
                ticket=100001,
                direction=TradeDirection.BUY,
                status=TradeStatus.CLOSED,
                entry_time=now - timedelta(days=1),
                exit_time=now,
                entry_price=2000.0,
                exit_price=2010.0,
                stop_loss=1990.0,
                take_profit=2020.0,
                current_price=2010.0,
                symbol="XAUUSD",
                lot_size=0.1,
                profit_loss=100.0,
                commission=-2.0,
                swap=-1.0,
            )
        )
        db.add(
            OptionsEdgeTradeJournalModel(
                journal_id="j_open_1",
                created_at=now - timedelta(hours=2),
                status="OPEN",
                scan_id="scan_x",
                trade_candidate_id=1,
                symbol="AAPL",
                structure_type="put_credit_spread",
                max_loss=250.0,
                contracts=2,
            )
        )
        db.add(
            OptionsEdgeTradeJournalModel(
                journal_id="j_closed_1",
                created_at=now - timedelta(days=2),
                closed_at=now,
                status="CLOSED",
                scan_id="scan_y",
                trade_candidate_id=2,
                symbol="MSFT",
                structure_type="iron_condor",
                actual_pnl_total=75.0,
                contracts=1,
            )
        )
        db.commit()

        resp = asyncio.run(get_unified_portfolio_overview(db))
    finally:
        db.close()

    assert resp["account_balance"] == 12000.0
    assert resp["live_trading"]["allocated_capital_usd"] == 2500.0
    assert resp["options_edge"]["open_risk_usd"] == 500.0
    assert resp["options_edge"]["closed_pnl_total_usd"] == 75.0
    assert resp["combined"]["known_open_risk_usd"] == 3100.0
