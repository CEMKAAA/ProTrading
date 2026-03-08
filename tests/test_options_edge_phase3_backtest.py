import asyncio
from datetime import datetime, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api.routes import (
    get_options_edge_backtest,
    list_options_edge_backtests,
    run_options_edge_backtest,
)
from dashboard.backend.models.database import (
    Base,
    OptionsEdgeScanRunModel,
    OptionsEdgeTradeCandidateModel,
)
from dashboard.backend.models.schemas import OptionsEdgeBacktestRequest


def _seed_scan_history(db, n_scans: int = 6):
    t0 = datetime(2026, 1, 2, 20, 0, 0)
    scan_ids = []
    for i in range(n_scans):
        sid = f"scan{i:02d}"
        scan_ids.append(sid)
        db.add(
            OptionsEdgeScanRunModel(
                scan_id=sid,
                scan_ts=t0 + timedelta(days=i),
                status="COMPLETED",
                universe_size=50,
                passed_gate_count=20,
                selected_count=4,
                top_n=4,
                max_sector_fraction=0.5,
                summary_json={"selected_count": 4},
            )
        )
        for j in range(3):
            db.add(
                OptionsEdgeTradeCandidateModel(
                    scan_id=sid,
                    symbol=f"SYM{j}",
                    structure_type="put_credit_spread",
                    expiry_date="2026-03-20",
                    dte=35,
                    legs_json=[
                        {"side": "SELL", "type": "P"},
                        {"side": "BUY", "type": "P"},
                    ],
                    net_credit=1.2 + 0.1 * j,
                    max_profit=120.0 + 10.0 * j,
                    max_loss=280.0 + 20.0 * j,
                    pop_est=0.60 + 0.05 * (j % 2),
                    delta_net=-10.0,
                    theta_net=5.0,
                    vega_net=-8.0,
                    quality_flags=[],
                )
            )
    db.commit()
    return scan_ids


def test_options_edge_phase3_backtest_run_and_retrieve():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    db = SessionLocal()
    try:
        scan_ids = _seed_scan_history(db, n_scans=6)
        req = OptionsEdgeBacktestRequest(
            scan_ids=scan_ids,
            initial_balance=10000.0,
            allocation_per_trade_usd=1000.0,
            max_contracts_per_trade=3,
            max_trades_per_scan=2,
            walk_forward_folds=3,
            random_seed=7,
        )
        run_resp = asyncio.run(run_options_edge_backtest(req, db))
        detail_resp = asyncio.run(get_options_edge_backtest(run_resp.run_id, db))
        list_resp = asyncio.run(list_options_edge_backtests(limit=10, db=db))
    finally:
        db.close()

    assert run_resp.status == "COMPLETED"
    assert run_resp.scans_used == 6
    assert run_resp.trades_simulated > 0
    assert run_resp.metrics["total_trades"] == run_resp.trades_simulated
    assert isinstance(run_resp.equity_curve, list)
    assert isinstance(run_resp.trade_log, list)
    assert len(run_resp.equity_curve) >= 1
    assert len(run_resp.trade_log) == run_resp.trades_simulated
    assert run_resp.walk_forward.get("enabled") is True
    assert run_resp.walk_forward.get("fold_count") == 3
    assert "base" in run_resp.stress
    assert "slippage_plus_25_spread_plus_50" in run_resp.stress

    assert detail_resp.run_id == run_resp.run_id
    assert len(list_resp) == 1
    assert list_resp[0].run_id == run_resp.run_id
