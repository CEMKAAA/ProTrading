from datetime import datetime

import numpy as np
import pandas as pd
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import simulation_routes as sim_routes
from dashboard.backend.core.workbench.ml_diagnostic import compute_feature_diagnostic
from dashboard.backend.models.database import Base, SimulationSession


def _db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    return SessionLocal()


def _make_df(rows: int = 700, shift_second_half: bool = False) -> pd.DataFrame:
    idx = pd.date_range("2026-01-01", periods=rows, freq="5min", tz="UTC")
    x = np.arange(rows, dtype=float)
    close = 100.0 + (0.008 * x) + (1.5 * np.sin(x / 15.0))
    if shift_second_half:
        half = rows // 2
        close[half:] = close[half:] + (2.5 * np.sin(np.arange(rows - half) / 2.0))
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


def test_compute_feature_diagnostic_basic_shape():
    res = compute_feature_diagnostic(_make_df(500), lags=5, split_ratio=0.7, drift_warn_pct=50.0)
    assert res["ok"] is True
    assert isinstance(res["features"], list) and len(res["features"]) > 0
    assert "summary" in res
    first = res["features"][0]
    assert "name" in first and "drift_pct" in first


def test_compute_feature_diagnostic_warning_on_drift():
    res = compute_feature_diagnostic(_make_df(700, shift_second_half=True), lags=5, split_ratio=0.7, drift_warn_pct=20.0)
    assert res["ok"] is True
    assert res["regime_warning"] is True
    assert float(res["max_drift_pct"]) >= 20.0


def test_ml_diagnostic_route_engine_bars(monkeypatch):
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

        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: _FakeEngine(_make_df(500)))
        req = sim_routes.ResearchMLDiagnosticRequest(lags=5, split_ratio=0.7, drift_warn_pct=50.0)
        out = sim_routes.workbench_research_ml_diagnostic(session_id=int(sim.id), req=req, db=db)
        assert out["ok"] is True
        assert out["research_only"] is True
        assert out["scan_source"] == "engine_visible"
    finally:
        db.close()


def test_ml_diagnostic_route_client_bars(monkeypatch):
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

        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: _FakeEngine(_make_df(500)))
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
        req = sim_routes.ResearchMLDiagnosticRequest(
            lags=5,
            split_ratio=0.7,
            drift_warn_pct=50.0,
            bars=bars,
        )
        out = sim_routes.workbench_research_ml_diagnostic(session_id=int(sim.id), req=req, db=db)
        assert out["ok"] is True
        assert out["scan_source"] == "client_live"
    finally:
        db.close()


def test_ml_diagnostic_route_insufficient_data(monkeypatch):
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

        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: _FakeEngine(_make_df(10)))
        req = sim_routes.ResearchMLDiagnosticRequest()
        with pytest.raises(HTTPException) as exc:
            sim_routes.workbench_research_ml_diagnostic(session_id=int(sim.id), req=req, db=db)
        assert exc.value.status_code == 400
        assert "Insufficient bars" in str(exc.value.detail)
    finally:
        db.close()
