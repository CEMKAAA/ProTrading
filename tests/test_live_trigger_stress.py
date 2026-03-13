from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import simulation_routes as sim_routes
from dashboard.backend.models.database import (
    Base,
    SimulationSession,
    SimulationTrade,
    WorkbenchAgentSessionModel,
)
from dashboard.backend.services import agent_live_tick_service as live_tick_mod
from dashboard.backend.services.agent_live_tick_service import AgentLiveTickService
from dashboard.backend.services.agent_watchdog_service import AgentWatchdogService


def _session_factory():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    return sessionmaker(bind=engine, autocommit=False, autoflush=False)


def _seed_live_session(SessionLocal, *, requires_approval: bool, trigger_args: dict):
    db = SessionLocal()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps(
                {
                    "live_control": {
                        "enabled": True,
                        "source": "mt5",
                        "backend_native": True,
                    }
                }
            ),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={
                "can_place_trades": True,
                "requires_user_confirm_for_trade": requires_approval,
            },
            config={
                "agent_permissions": {
                    "can_place_trades": True,
                    "requires_user_confirm_for_trade": requires_approval,
                }
            },
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={
                "can_place_trades": True,
                "requires_user_confirm_for_trade": requires_approval,
            },
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args=trigger_args,
            atomic=True,
        )
        assert out.get("ok") is True
        db.commit()
        return int(sim.id), int(agent.id)
    finally:
        db.close()


def test_stress_backend_mt5_relay_processes_multiple_live_sessions_in_one_pass(monkeypatch):
    SessionLocal = _session_factory()
    reclaim_args = {
        "condition": "close_above",
        "trigger_price": 5186.83,
        "precondition": {"condition": "price_below", "trigger_price": 5186.83},
        "direction": "BUY",
        "stop_loss": 5148.16,
        "take_profit": 5226.77,
        "lot_size": 0.01,
        "timeframe": "M15",
    }
    close_only_args = {
        "condition": "close_above",
        "trigger_price": 5186.83,
        "direction": "BUY",
        "stop_loss": 5148.16,
        "take_profit": 5226.77,
        "lot_size": 0.01,
        "timeframe": "M15",
    }
    sid_exec, _ = _seed_live_session(SessionLocal, requires_approval=False, trigger_args=reclaim_args)
    sid_pending, _ = _seed_live_session(SessionLocal, requires_approval=False, trigger_args=close_only_args)
    sid_approval, _ = _seed_live_session(SessionLocal, requires_approval=True, trigger_args=reclaim_args)

    now_ts = int(datetime.now(timezone.utc).timestamp())
    bars = {
        int(sid_exec): {
            "time": now_ts,
            "open": 5188.20,
            "high": 5190.10,
            "low": 5184.58,
            "close": 5189.35,
            "volume": 100.0,
            "asof_time": now_ts,
        },
        int(sid_pending): {
            "time": now_ts,
            "open": 5188.20,
            "high": 5190.10,
            "low": 5180.00,
            "close": 5184.50,
            "volume": 100.0,
            "asof_time": now_ts,
        },
        int(sid_approval): {
            "time": now_ts,
            "open": 5188.20,
            "high": 5190.10,
            "low": 5184.58,
            "close": 5189.35,
            "volume": 100.0,
            "asof_time": now_ts,
        },
    }

    watchdog = AgentWatchdogService()
    monkeypatch.setattr(live_tick_mod, "SessionLocal", SessionLocal)
    monkeypatch.setattr(live_tick_mod, "get_agent_watchdog_service", lambda: watchdog)
    svc = AgentLiveTickService()
    monkeypatch.setattr(svc, "_fetch_mt5_live_bar", lambda session: dict(bars[int(session.id)]))
    svc._process_once()

    db = SessionLocal()
    try:
        def _trigger_status(session_id: int) -> str:
            agent = (
                db.query(WorkbenchAgentSessionModel)
                .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                .first()
            )
            rows = sim_routes._agent_trigger_rows_from_agent(agent)
            assert len(rows) == 1
            return str(rows[0].get("status") or "").lower()

        assert _trigger_status(sid_exec) == "executed"
        assert _trigger_status(sid_pending) == "pending"
        assert _trigger_status(sid_approval) == "pending_approval"
    finally:
        db.close()


def test_stress_backend_mt5_relay_repeated_same_bar_polls_do_not_duplicate_execution(monkeypatch):
    SessionLocal = _session_factory()
    reclaim_args = {
        "condition": "close_above",
        "trigger_price": 5186.83,
        "precondition": {"condition": "price_below", "trigger_price": 5186.83},
        "direction": "BUY",
        "stop_loss": 5148.16,
        "take_profit": 5226.77,
        "lot_size": 0.01,
        "timeframe": "M15",
    }
    session_id, _ = _seed_live_session(SessionLocal, requires_approval=False, trigger_args=reclaim_args)

    now_ts = int(datetime.now(timezone.utc).timestamp())
    live_bar = {
        "time": now_ts,
        "open": 5188.20,
        "high": 5190.10,
        "low": 5184.58,
        "close": 5189.35,
        "volume": 100.0,
        "asof_time": now_ts,
    }

    watchdog = AgentWatchdogService()
    monkeypatch.setattr(live_tick_mod, "SessionLocal", SessionLocal)
    monkeypatch.setattr(live_tick_mod, "get_agent_watchdog_service", lambda: watchdog)
    svc = AgentLiveTickService()
    monkeypatch.setattr(svc, "_fetch_mt5_live_bar", lambda _session: dict(live_bar))

    for _ in range(3):
        svc._process_once()

    db = SessionLocal()
    try:
        agent = (
            db.query(WorkbenchAgentSessionModel)
            .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
            .first()
        )
        rows = sim_routes._agent_trigger_rows_from_agent(agent)
        assert len(rows) == 1
        first = rows[0]
        assert str(first.get("status") or "").lower() == "executed"

        trades = db.query(SimulationTrade).filter(SimulationTrade.session_id == int(session_id)).all()
        assert len(trades) == 1
    finally:
        db.close()


def test_stress_backend_mt5_relay_same_bar_burst_updates_complete_reclaim_progression(monkeypatch):
    SessionLocal = _session_factory()
    reclaim_args = {
        "condition": "close_above",
        "trigger_price": 5186.83,
        "precondition": {"condition": "price_below", "trigger_price": 5186.83},
        "direction": "BUY",
        "stop_loss": 5148.16,
        "take_profit": 5226.77,
        "lot_size": 0.01,
        "timeframe": "M15",
    }
    session_id, _ = _seed_live_session(SessionLocal, requires_approval=False, trigger_args=reclaim_args)

    now_ts = int(datetime.now(timezone.utc).timestamp())
    live_bars = [
        {
            "time": now_ts,
            "open": 5188.20,
            "high": 5185.60,
            "low": 5184.58,
            "close": 5185.20,
            "volume": 100.0,
            "asof_time": now_ts,
        },
        {
            "time": now_ts,
            "open": 5188.20,
            "high": 5190.10,
            "low": 5184.58,
            "close": 5189.35,
            "volume": 150.0,
            "asof_time": now_ts + 1,
        },
    ]

    watchdog = AgentWatchdogService()
    monkeypatch.setattr(live_tick_mod, "SessionLocal", SessionLocal)
    monkeypatch.setattr(live_tick_mod, "get_agent_watchdog_service", lambda: watchdog)
    svc = AgentLiveTickService()
    idx = {"value": 0}

    def _next_bar(_session):
        cur = min(idx["value"], len(live_bars) - 1)
        bar = dict(live_bars[cur])
        idx["value"] += 1
        return bar

    monkeypatch.setattr(svc, "_fetch_mt5_live_bar", _next_bar)

    svc._process_once()
    db = SessionLocal()
    try:
        agent = (
            db.query(WorkbenchAgentSessionModel)
            .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
            .first()
        )
        rows = sim_routes._agent_trigger_rows_from_agent(agent)
        assert len(rows) == 1
        first = rows[0]
        assert str(first.get("status") or "").lower() == "pending"
        assert str(first.get("state") or "").lower() == "waiting_entry"
    finally:
        db.close()

    svc._process_once()
    db = SessionLocal()
    try:
        agent = (
            db.query(WorkbenchAgentSessionModel)
            .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
            .first()
        )
        rows = sim_routes._agent_trigger_rows_from_agent(agent)
        assert len(rows) == 1
        first = rows[0]
        assert str(first.get("status") or "").lower() == "executed"
        assert abs(float(first.get("executed_price")) - 5190.10) < 1e-9
    finally:
        db.close()
