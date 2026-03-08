import asyncio
from datetime import datetime

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api.routes import (
    options_edge_journal_close,
    options_edge_journal_delete,
    options_edge_journal_list,
    options_edge_journal_stats,
    options_edge_journal_track,
)
from dashboard.backend.models.database import (
    Base,
    OptionsEdgeScanRunModel,
    OptionsEdgeTradeCandidateModel,
)
from dashboard.backend.models.schemas import (
    OptionsEdgeJournalCloseRequest,
    OptionsEdgeJournalTrackRequest,
)


def _seed_scan_and_trade(db):
    scan_id = "scan_journal_01"
    db.add(
        OptionsEdgeScanRunModel(
            scan_id=scan_id,
            scan_ts=datetime(2026, 2, 1, 15, 0, 0),
            status="COMPLETED",
            universe_size=10,
            passed_gate_count=5,
            selected_count=3,
            top_n=3,
            max_sector_fraction=0.35,
            summary_json={"selected_count": 3},
        )
    )
    trade = OptionsEdgeTradeCandidateModel(
        scan_id=scan_id,
        symbol="AAPL",
        structure_type="put_credit_spread",
        expiry_date="2026-03-20",
        dte=30,
        legs_json=[{"action": "SELL", "option_type": "P"}, {"action": "BUY", "option_type": "P"}],
        net_credit=1.4,
        max_profit=140.0,
        max_loss=260.0,
        pop_est=0.64,
        delta_net=-11.0,
        theta_net=4.5,
        vega_net=-6.0,
        quality_flags=[],
    )
    db.add(trade)
    db.commit()
    db.refresh(trade)
    return scan_id, trade.id


def test_journal_track_close_stats_delete():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = SessionLocal()
    try:
        scan_id, trade_id = _seed_scan_and_trade(db)
        track_req = OptionsEdgeJournalTrackRequest(
            scan_id=scan_id,
            trade_candidate_id=trade_id,
            contracts=2,
            account_balance_at_entry=12000.0,
            risk_pct_at_entry=2.0,
            notes="seed test",
        )
        tracked = asyncio.run(options_edge_journal_track(track_req, db))
        assert tracked.status == "OPEN"
        assert tracked.symbol == "AAPL"
        assert tracked.trade_candidate_id == trade_id

        rows = asyncio.run(options_edge_journal_list(None, 100, db))
        assert len(rows) == 1
        assert rows[0].journal_id == tracked.journal_id

        close_req = OptionsEdgeJournalCloseRequest(
            exit_credit=0.6,
            actual_pnl=55.0,
            exit_reason="profit_target",
            notes="closed in test",
        )
        closed = asyncio.run(options_edge_journal_close(tracked.journal_id, close_req, db))
        assert closed.status == "CLOSED"
        assert closed.actual_pnl_total == 110.0

        stats = asyncio.run(options_edge_journal_stats(db))
        assert stats.total == 1
        assert stats.closed == 1
        assert stats.wins == 1
        assert stats.total_pnl == 110.0

        deleted = asyncio.run(options_edge_journal_delete(tracked.journal_id, db))
        assert deleted["ok"] is True
        rows_after = asyncio.run(options_edge_journal_list(None, 100, db))
        assert len(rows_after) == 0
    finally:
        db.close()

