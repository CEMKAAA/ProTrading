from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import simulation_routes as sim_routes
from dashboard.backend.models.database import Base, SimulationSession, WorkbenchAgentSessionModel
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


def test_smoke_backend_mt5_relay_executes_reclaim_trigger_without_browser(monkeypatch):
    SessionLocal = _session_factory()
    trigger_args = {
        "condition": "close_above",
        "trigger_price": 5186.83,
        "precondition": {"condition": "price_below", "trigger_price": 5186.83},
        "direction": "BUY",
        "stop_loss": 5148.16,
        "take_profit": 5226.77,
        "lot_size": 0.01,
        "timeframe": "M15",
    }
    session_id, _agent_id = _seed_live_session(SessionLocal, requires_approval=False, trigger_args=trigger_args)

    fresh_ts = int(datetime.now(timezone.utc).timestamp())
    live_bar = {
        "time": fresh_ts,
        "open": 5188.20,
        "high": 5190.10,
        "low": 5184.58,
        "close": 5189.35,
        "volume": 100.0,
        "asof_time": fresh_ts,
    }

    monkeypatch.setattr(live_tick_mod, "SessionLocal", SessionLocal)
    monkeypatch.setattr(live_tick_mod, "get_agent_watchdog_service", lambda: AgentWatchdogService())
    svc = AgentLiveTickService()
    monkeypatch.setattr(svc, "_fetch_mt5_live_bar", lambda _session: dict(live_bar))
    svc._process_once(run_watchdog=True, run_automation=False)

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

        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        tool_state = snap.get("tool_state") if isinstance(snap.get("tool_state"), dict) else {}
        assert str(tool_state.get("live_source") or "") == "mt5"
        assert bool((tool_state.get("live_stream") or {}).get("backend_native")) is True
    finally:
        db.close()


def test_smoke_backend_mt5_relay_keeps_close_only_trigger_pending_intrabar(monkeypatch):
    SessionLocal = _session_factory()
    trigger_args = {
        "condition": "close_above",
        "trigger_price": 5186.83,
        "direction": "BUY",
        "stop_loss": 5148.16,
        "take_profit": 5226.77,
        "lot_size": 0.01,
        "timeframe": "M15",
    }
    session_id, _agent_id = _seed_live_session(SessionLocal, requires_approval=False, trigger_args=trigger_args)

    fresh_ts = int(datetime.now(timezone.utc).timestamp())
    live_bar = {
        "time": fresh_ts,
        "open": 5188.20,
        "high": 5190.10,
        "low": 5180.00,
        "close": 5184.50,
        "volume": 100.0,
        "asof_time": fresh_ts,
    }

    monkeypatch.setattr(live_tick_mod, "SessionLocal", SessionLocal)
    monkeypatch.setattr(live_tick_mod, "get_agent_watchdog_service", lambda: AgentWatchdogService())
    svc = AgentLiveTickService()
    monkeypatch.setattr(svc, "_fetch_mt5_live_bar", lambda _session: dict(live_bar))
    svc._process_once(run_watchdog=True, run_automation=False)

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


def test_smoke_backend_mt5_relay_preserves_manual_confirmation_gate(monkeypatch):
    SessionLocal = _session_factory()
    trigger_args = {
        "condition": "close_above",
        "trigger_price": 5186.83,
        "precondition": {"condition": "price_below", "trigger_price": 5186.83},
        "direction": "BUY",
        "stop_loss": 5148.16,
        "take_profit": 5226.77,
        "lot_size": 0.01,
        "timeframe": "M15",
    }
    session_id, _agent_id = _seed_live_session(SessionLocal, requires_approval=True, trigger_args=trigger_args)

    fresh_ts = int(datetime.now(timezone.utc).timestamp())
    live_bar = {
        "time": fresh_ts,
        "open": 5188.20,
        "high": 5190.10,
        "low": 5184.58,
        "close": 5189.35,
        "volume": 100.0,
        "asof_time": fresh_ts,
    }

    monkeypatch.setattr(live_tick_mod, "SessionLocal", SessionLocal)
    monkeypatch.setattr(live_tick_mod, "get_agent_watchdog_service", lambda: AgentWatchdogService())
    svc = AgentLiveTickService()
    monkeypatch.setattr(svc, "_fetch_mt5_live_bar", lambda _session: dict(live_bar))
    svc._process_once(run_watchdog=True, run_automation=False)

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
        assert str(first.get("status") or "").lower() == "pending_approval"
    finally:
        db.close()
