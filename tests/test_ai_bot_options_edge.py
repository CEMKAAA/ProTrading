import asyncio

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api.routes import (
    get_ai_bot_run,
    list_ai_bot_runs,
    run_ai_bot_options_edge_plan,
    run_options_edge_scan,
)
from dashboard.backend.models.database import Base
from dashboard.backend.models.schemas import (
    AIBotOptionsEdgePlanRequest,
    OptionsEdgeScanRequest,
    OptionsEdgeUniverseRow,
)


def _sample_universe():
    return [
        OptionsEdgeUniverseRow(
            symbol="AAPL",
            sector="Technology",
            price=190.0,
            iv30=0.40,
            hv30=0.20,
            iv_rank_252=0.72,
            avg_opt_volume_30d=25000,
            avg_oi_30d=90000,
            avg_bid_ask_pct=0.01,
            days_to_earnings=25,
            borrow_rate=0.01,
            trend_20d_return=0.02,
            put_call_skew=0.10,
        ),
        OptionsEdgeUniverseRow(
            symbol="MSFT",
            sector="Technology",
            price=410.0,
            iv30=0.34,
            hv30=0.19,
            iv_rank_252=0.66,
            avg_opt_volume_30d=21000,
            avg_oi_30d=82000,
            avg_bid_ask_pct=0.011,
            days_to_earnings=18,
            borrow_rate=0.01,
            trend_20d_return=0.01,
            put_call_skew=0.08,
        ),
    ]


def _sample_chain():
    rows = []
    for symbol, spot in [("AAPL", 190.0), ("MSFT", 410.0)]:
        rows.extend(
            [
                {
                    "symbol": symbol,
                    "expiry_date": "2026-03-20",
                    "option_type": "P",
                    "strike": spot - 5,
                    "bid": 3.4,
                    "ask": 3.8,
                    "delta": -0.25,
                    "theta": -0.08,
                    "vega": 0.12,
                    "volume": 500,
                    "oi": 2000,
                },
                {
                    "symbol": symbol,
                    "expiry_date": "2026-03-20",
                    "option_type": "P",
                    "strike": spot - 10,
                    "bid": 1.6,
                    "ask": 1.9,
                    "delta": -0.12,
                    "theta": -0.04,
                    "vega": 0.07,
                    "volume": 420,
                    "oi": 1800,
                },
                {
                    "symbol": symbol,
                    "expiry_date": "2026-03-20",
                    "option_type": "C",
                    "strike": spot + 5,
                    "bid": 3.3,
                    "ask": 3.7,
                    "delta": 0.24,
                    "theta": -0.08,
                    "vega": 0.12,
                    "volume": 480,
                    "oi": 1900,
                },
                {
                    "symbol": symbol,
                    "expiry_date": "2026-03-20",
                    "option_type": "C",
                    "strike": spot + 10,
                    "bid": 1.5,
                    "ask": 1.8,
                    "delta": 0.12,
                    "theta": -0.04,
                    "vega": 0.07,
                    "volume": 410,
                    "oi": 1700,
                },
            ]
        )
    return rows


def test_ai_bot_options_edge_plan_and_persistence():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = SessionLocal()
    try:
        scan_req = OptionsEdgeScanRequest(
            universe=_sample_universe(),
            option_chain=_sample_chain(),
            build_strategies=True,
            top_n=2,
            max_sector_fraction=1.0,
        )
        scan_resp = asyncio.run(run_options_edge_scan(scan_req, db))

        plan_req = AIBotOptionsEdgePlanRequest(
            provider="deterministic",
            account_balance=10000.0,
            risk_pct=1.0,
            max_contracts_cap=5,
            dry_run=True,
        )
        run_resp = asyncio.run(run_ai_bot_options_edge_plan(scan_resp.scan_id, plan_req, db))
        got_run = asyncio.run(get_ai_bot_run(run_resp.run_id, db))
        listed = asyncio.run(
            list_ai_bot_runs(
                strategy_id="options_edge",
                context_id=scan_resp.scan_id,
                status=None,
                limit=5,
                db=db,
            )
        )
    finally:
        db.close()

    assert run_resp.status == "COMPLETED"
    assert run_resp.strategy_id == "options_edge"
    assert run_resp.context_id == scan_resp.scan_id
    assert isinstance(run_resp.execution_plan, list)
    assert len(run_resp.execution_plan) >= 1
    assert got_run.run_id == run_resp.run_id
    assert len(listed) >= 1
    assert listed[0].run_id == run_resp.run_id

