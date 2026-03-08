from datetime import datetime

import numpy as np
import pandas as pd
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import simulation_routes as sim_routes
from dashboard.backend.core.workbench.parameter_optimizer import (
    _range_float,
    count_sma_crossover_combinations,
    optimize_mean_reversion,
    optimize_sma_crossover,
    parse_float_range,
    parse_int_range,
)
from dashboard.backend.models.database import Base, SimulationSession


def _db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    return SessionLocal()


def _make_df(rows: int = 600) -> pd.DataFrame:
    idx = pd.date_range("2026-01-01", periods=rows, freq="5min", tz="UTC")
    x = np.arange(rows, dtype=float)
    # Trend + oscillation so both families generate non-trivial results.
    close = 100.0 + (0.01 * x) + (2.0 * np.sin(x / 18.0))
    return pd.DataFrame(
        {
            "open": close - 0.05,
            "high": close + 0.10,
            "low": close - 0.10,
            "close": close,
            "volume": np.full(rows, 1.0),
        },
        index=idx,
    )


class _FakeEngine:
    def __init__(self, df: pd.DataFrame):
        self.df = df
        self.current_bar = len(df) - 1
        self.total_bars = len(df)
        self.symbol = "XAUUSD"
        self.timeframe = "M5"


def test_optimize_sma_crossover_basic_shape():
    df = _make_df(400)
    res = optimize_sma_crossover(df, fast_range=(10, 30, 5), slow_range=(40, 80, 10), tc=0.0001)
    assert res["strategy_type"] == "sma_crossover"
    assert isinstance(res.get("results"), list)
    assert res["total_combinations"] > 0
    assert res["optimal"] is not None
    assert "fast" in res["optimal"] and "slow" in res["optimal"]
    first = res["results"][0]
    assert "sharpe" in first and "max_drawdown" in first and "trade_count" in first


def test_optimize_mean_reversion_basic_shape():
    df = _make_df(500)
    res = optimize_mean_reversion(df, sma_range=(15, 45, 5), dev_range=(1.2, 2.2, 0.2), tc=0.0001)
    assert res["strategy_type"] == "mean_reversion"
    assert isinstance(res.get("results"), list)
    assert res["total_combinations"] > 0
    assert res["optimal"] is not None
    assert "sma" in res["optimal"] and "dev" in res["optimal"]
    first = res["results"][0]
    assert "sharpe" in first and "max_drawdown" in first and "trade_count" in first


def test_float_range_is_stable_and_exclusive_stop():
    vals = _range_float(1.2, 3.1, 0.2, decimals=4)
    assert vals[0] == 1.2
    assert vals[-1] == 3.0
    assert all(v < 3.1 for v in vals)


def test_parse_ranges_and_sma_combo_count():
    ir = parse_int_range(
        {"fast_range": [10, 40, 5]},
        key="fast",
        start_default=10,
        stop_default=40,
        step_default=5,
        min_v=2,
        max_v=200,
    )
    fr = parse_float_range(
        {"dev_start": 1.2, "dev_stop": 2.2, "dev_step": 0.2},
        key="dev",
        start_default=1.0,
        stop_default=2.0,
        step_default=0.2,
        min_v=0.2,
        max_v=8.0,
    )
    assert ir == (10, 40, 5)
    assert fr[0] == 1.2 and fr[2] == 0.2

    fast = (10, 30, 5)  # 10,15,20,25
    slow = (20, 40, 10)  # 20,30
    # Valid: (10,20),(10,30),(15,20),(15,30),(20,30),(25,30) => 6
    assert count_sma_crossover_combinations(fast, slow) == 6


def test_research_optimize_route_sma(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=500,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        fake_engine = _FakeEngine(_make_df(500))
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)

        req = sim_routes.ResearchOptimizeRequest(
            strategy_type="sma_crossover",
            params={
                "fast_start": 10,
                "fast_stop": 40,
                "fast_step": 5,
                "slow_start": 45,
                "slow_stop": 95,
                "slow_step": 10,
                "lookback_days": 10,
            },
            tc_rate=0.0001,
            top_n=10,
            max_combinations=2000,
        )
        out = sim_routes.workbench_research_optimize(session_id=int(sim.id), req=req, db=db)
        assert out["strategy_type"] == "sma_crossover"
        assert out["research_only"] is True
        assert out["total_combinations"] >= 1
        assert len(out["results"]) <= 10
        assert out["scan_source"] == "engine_visible"
        assert out["results"] and "sharpe" in out["results"][0]
    finally:
        db.close()


def test_research_optimize_route_mean_reversion(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=500,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        fake_engine = _FakeEngine(_make_df(500))
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)

        req = sim_routes.ResearchOptimizeRequest(
            strategy_type="mean_reversion",
            params={
                "sma_start": 15,
                "sma_stop": 45,
                "sma_step": 5,
                "dev_start": 1.2,
                "dev_stop": 2.4,
                "dev_step": 0.2,
            },
            tc_rate=0.0001,
            top_n=12,
            max_combinations=2000,
        )
        out = sim_routes.workbench_research_optimize(session_id=int(sim.id), req=req, db=db)
        assert out["strategy_type"] == "mean_reversion"
        assert out["research_only"] is True
        assert out["total_combinations"] >= 1
        assert len(out["results"]) <= 12
        assert out["results"] and "max_drawdown" in out["results"][0]
    finally:
        db.close()


def test_research_optimize_route_invalid_strategy(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=200,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        fake_engine = _FakeEngine(_make_df(300))
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)
        req = sim_routes.ResearchOptimizeRequest(strategy_type="not_real")
        with pytest.raises(HTTPException) as exc:
            sim_routes.workbench_research_optimize(session_id=int(sim.id), req=req, db=db)
        assert exc.value.status_code == 400
        assert "Unsupported strategy_type" in str(exc.value.detail)
    finally:
        db.close()


def test_research_optimize_route_insufficient_data(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=10,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        fake_engine = _FakeEngine(_make_df(10))
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)
        req = sim_routes.ResearchOptimizeRequest(strategy_type="sma_crossover")
        with pytest.raises(HTTPException) as exc:
            sim_routes.workbench_research_optimize(session_id=int(sim.id), req=req, db=db)
        assert exc.value.status_code == 400
        assert "Insufficient bars" in str(exc.value.detail)
    finally:
        db.close()


def test_research_optimize_route_client_bars_source(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=500,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        # Engine has valid bars, but we pass client bars and expect source=client_live.
        fake_engine = _FakeEngine(_make_df(500))
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)

        df_client = _make_df(180)
        bars = []
        for ts, row in df_client.iterrows():
            bars.append(
                {
                    "time": int(ts.timestamp()),
                    "open": float(row["open"]),
                    "high": float(row["high"]),
                    "low": float(row["low"]),
                    "close": float(row["close"]),
                    "volume": float(row["volume"]),
                }
            )

        req = sim_routes.ResearchOptimizeRequest(
            strategy_type="sma_crossover",
            params={"fast_start": 10, "fast_stop": 20, "fast_step": 5, "slow_start": 30, "slow_stop": 50, "slow_step": 10},
            bars=bars,
        )
        out = sim_routes.workbench_research_optimize(session_id=int(sim.id), req=req, db=db)
        assert out["scan_source"] == "client_live"
        assert out["bars_used"] >= 20
    finally:
        db.close()


def test_research_optimize_route_lookback_bars_applied(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=700,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        fake_engine = _FakeEngine(_make_df(700))
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)

        req = sim_routes.ResearchOptimizeRequest(
            strategy_type="sma_crossover",
            params={
                "fast_start": 10,
                "fast_stop": 20,
                "fast_step": 5,
                "slow_start": 30,
                "slow_stop": 50,
                "slow_step": 10,
                "lookback_bars": 120,
            },
            top_n=10,
            max_combinations=500,
        )
        out = sim_routes.workbench_research_optimize(session_id=int(sim.id), req=req, db=db)
        assert out["bars_used"] == 120
    finally:
        db.close()


def test_research_optimize_route_combo_limit(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=600,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        fake_engine = _FakeEngine(_make_df(600))
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)

        req = sim_routes.ResearchOptimizeRequest(
            strategy_type="mean_reversion",
            params={
                "sma_start": 10,
                "sma_stop": 200,
                "sma_step": 2,
                "dev_start": 0.5,
                "dev_stop": 5.0,
                "dev_step": 0.1,
            },
            max_combinations=100,
        )
        with pytest.raises(HTTPException) as exc:
            sim_routes.workbench_research_optimize(session_id=int(sim.id), req=req, db=db)
        assert exc.value.status_code == 400
        assert "Too many combinations" in str(exc.value.detail)
        assert "estimated" in str(exc.value.detail)
    finally:
        db.close()
