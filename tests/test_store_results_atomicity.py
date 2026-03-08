"""
Backtest result persistence atomicity tests.

Ensures _store_results commits all-or-nothing:
- Success path persists metrics and run_manifest.
- Failure during trade conversion rolls back result mutations.
"""

from datetime import datetime

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.models.database import (
    Base,
    BacktestConfigModel,
    BacktestResultModel,
    BacktestStatus,
    BacktestTradeModel,
)
from dashboard.backend.services.backtest_service import BacktestService


def _make_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    return Session, engine


def _seed_config_and_result(session):
    cfg = BacktestConfigModel(
        name="atomicity-test",
        strategy_id="orb_strategy",
        symbol="XAUUSD",
        timeframe="M5",
        start_date=datetime(2024, 1, 1),
        end_date=datetime(2024, 1, 31),
    )
    session.add(cfg)
    session.commit()
    session.refresh(cfg)

    result = BacktestResultModel(
        config_id=cfg.id,
        status=BacktestStatus.RUNNING,
        started_at=datetime.utcnow(),
    )
    session.add(result)
    session.commit()
    session.refresh(result)
    return cfg, result


def test_store_results_success_persists_run_manifest():
    Session, _engine = _make_session()
    s1 = Session()
    _cfg, result = _seed_config_and_result(s1)

    payload = {
        "metrics": {
            "total_trades": 0,
            "winning_trades": 0,
            "losing_trades": 0,
            "win_rate": 0.0,
            "initial_balance": 10000.0,
            "final_balance": 10000.0,
            "total_profit": 0.0,
            "total_loss": 0.0,
            "net_profit": 0.0,
            "profit_factor": 0.0,
            "max_drawdown": 0.0,
            "max_drawdown_percent": 0.0,
            "sharpe_ratio": 0.0,
            "sortino_ratio": 0.0,
            "calmar_ratio": 0.0,
            "avg_win": 0.0,
            "avg_loss": 0.0,
            "largest_win": 0.0,
            "largest_loss": 0.0,
            "avg_trade_duration": 0.0,
            "avg_rr_ratio": 0.0,
            "expectancy": 0.0,
        },
        "trades": [],
        "equity_curve": [],
        "daily_pnl": {},
        "monthly_returns": {},
        "regime_analysis": {"enabled": False},
        "run_manifest": {"code_hash": "abc123", "effective_config": {"symbol": "XAUUSD"}},
        "data_hash": "deadbeef",
    }

    BacktestService._store_results(s1, result, payload)
    result_id = result.id
    s1.close()

    s2 = Session()
    saved = s2.query(BacktestResultModel).filter(BacktestResultModel.id == result_id).first()
    assert saved is not None
    assert saved.status == BacktestStatus.COMPLETED
    assert saved.run_manifest == payload["run_manifest"]
    assert saved.data_hash == payload["data_hash"]
    s2.close()


def test_store_results_rolls_back_on_trade_conversion_error():
    Session, _engine = _make_session()
    s1 = Session()
    _cfg, result = _seed_config_and_result(s1)

    payload = {
        "metrics": {
            "total_trades": 1,
            "winning_trades": 1,
            "losing_trades": 0,
            "win_rate": 100.0,
            "initial_balance": 10000.0,
            "final_balance": 10100.0,
            "total_profit": 100.0,
            "total_loss": 0.0,
            "net_profit": 100.0,
            "profit_factor": 99.0,
            "max_drawdown": 0.0,
            "max_drawdown_percent": 0.0,
            "sharpe_ratio": 0.0,
            "sortino_ratio": 0.0,
            "calmar_ratio": 0.0,
            "avg_win": 100.0,
            "avg_loss": 0.0,
            "largest_win": 100.0,
            "largest_loss": 0.0,
            "avg_trade_duration": 30.0,
            "avg_rr_ratio": 1.0,
            "expectancy": 100.0,
        },
        "trades": [
            {
                "trade_number": 1,
                "direction": "INVALID_DIRECTION",  # triggers TradeDirection(...) ValueError
                "entry_time": datetime(2024, 1, 2, 10, 0).isoformat(),
                "exit_time": datetime(2024, 1, 2, 10, 30).isoformat(),
                "entry_price": 100.0,
                "exit_price": 101.0,
                "stop_loss": 99.0,
                "take_profit": 103.0,
                "lot_size": 1.0,
                "profit_loss": 100.0,
                "r_multiple": 1.0,
            }
        ],
        "equity_curve": [],
        "daily_pnl": {},
        "monthly_returns": {},
        "run_manifest": {"code_hash": "should-not-persist"},
        "data_hash": "should-not-persist",
    }

    with pytest.raises(Exception):
        BacktestService._store_results(s1, result, payload)
    result_id = result.id
    s1.close()

    s2 = Session()
    saved = s2.query(BacktestResultModel).filter(BacktestResultModel.id == result_id).first()
    assert saved is not None
    # Must remain pre-call state due to rollback.
    assert saved.status == BacktestStatus.RUNNING
    assert saved.completed_at is None
    assert saved.run_manifest is None
    assert saved.data_hash is None
    assert s2.query(BacktestTradeModel).filter(BacktestTradeModel.result_id == result_id).count() == 0
    s2.close()
