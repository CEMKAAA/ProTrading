"""
Service layer for Guided Trading Simulation control plane.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List
from uuid import uuid4

from sqlalchemy.orm import Session

from ...models.database import (
    TradingSimulationActionModel,
    TradingSimulationEventModel,
    TradingSimulationSessionModel,
)
from ..strategy_registry import StrategyRegistry
from .adapters import build_telemetry
from .education import get_strategy_guide
from .evaluator import evaluate_playbook
from .playbooks import get_playbook, has_playbook


def _json_safe(value: Any) -> Any:
    try:
        import numpy as np  # type: ignore

        if isinstance(value, (np.floating, np.integer)):
            return value.item()
    except Exception:
        pass
    if isinstance(value, dict):
        return {str(k): _json_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    return value


def _session_to_dict(row: TradingSimulationSessionModel) -> Dict[str, Any]:
    return {
        "id": row.id,
        "session_uid": row.session_uid,
        "strategy_id": row.strategy_id,
        "symbol": row.symbol,
        "timeframe": row.timeframe,
        "mode": row.mode,
        "status": row.status,
        "current_step_id": row.current_step_id,
        "current_step_status": row.current_step_status,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        "ended_at": row.ended_at.isoformat() if row.ended_at else None,
        "telemetry": row.telemetry_json or {},
        "step_states": row.step_states_json or [],
        "summary": row.summary_json or {},
    }


def _action_row_to_dict(row: TradingSimulationActionModel) -> Dict[str, Any]:
    return {
        "id": row.id,
        "session_id": row.session_id,
        "action_type": row.action_type,
        "step_id": row.step_id,
        "note": row.note,
        "payload": row.payload_json or {},
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


def _log_event(db: Session, session_id: int, event_type: str, payload: Dict[str, Any]) -> None:
    ev = TradingSimulationEventModel(
        session_id=session_id,
        event_type=event_type,
        payload_json=_json_safe(payload),
    )
    db.add(ev)


def _evaluate_and_store(db: Session, row: TradingSimulationSessionModel) -> Dict[str, Any]:
    actions = (
        db.query(TradingSimulationActionModel)
        .filter(TradingSimulationActionModel.session_id == row.id)
        .order_by(TradingSimulationActionModel.id.asc())
        .all()
    )
    action_dicts = [_action_row_to_dict(a) for a in actions]
    telemetry = build_telemetry(row.strategy_id, row.symbol, row.timeframe, mode=row.mode)
    playbook = get_playbook(row.strategy_id)
    eval_result = evaluate_playbook(playbook, telemetry, action_dicts)

    row.telemetry_json = _json_safe(telemetry)
    row.step_states_json = _json_safe(eval_result.get("step_states", []))
    row.summary_json = _json_safe(eval_result.get("summary", {}))
    current_step = eval_result.get("current_step") or {}
    row.current_step_id = current_step.get("id")
    row.current_step_status = current_step.get("status", "WAIT")
    row.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(row)

    payload = _session_to_dict(row)
    payload["current_step"] = current_step
    payload["playbook"] = playbook
    payload["guide"] = get_strategy_guide(row.strategy_id)
    payload["actions"] = action_dicts[-50:]
    return payload


def create_session(
    db: Session,
    strategy_id: str,
    symbol: str,
    timeframe: str,
    mode: str = "demo",
    confirm_live_mode: bool = False,
) -> Dict[str, Any]:
    if StrategyRegistry.get_strategy(strategy_id) is None:
        raise ValueError(f"Unknown strategy_id: {strategy_id}")

    if mode not in ("demo", "live"):
        mode = "demo"
    if mode == "live" and not confirm_live_mode:
        raise ValueError("Live simulation mode requires explicit confirm_live_mode=true.")

    row = TradingSimulationSessionModel(
        session_uid=f"tsim_{uuid4().hex[:16]}",
        strategy_id=strategy_id,
        symbol=(symbol or "XAUUSD").upper(),
        timeframe=(timeframe or "M1").upper(),
        mode=mode,
        status="ACTIVE",
        current_step_status="WAIT",
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    _log_event(db, row.id, "session_created", {"mode": mode})
    db.commit()
    return _evaluate_and_store(db, row)


def get_session(db: Session, session_id: int) -> Dict[str, Any]:
    row = db.query(TradingSimulationSessionModel).get(session_id)
    if not row:
        raise ValueError("Session not found")
    payload = _session_to_dict(row)
    payload["guide"] = get_strategy_guide(row.strategy_id)
    payload["playbook"] = get_playbook(row.strategy_id)
    return payload


def get_state(db: Session, session_id: int) -> Dict[str, Any]:
    row = db.query(TradingSimulationSessionModel).get(session_id)
    if not row:
        raise ValueError("Session not found")
    return _evaluate_and_store(db, row)


def record_action(
    db: Session,
    session_id: int,
    action_type: str,
    step_id: str | None = None,
    note: str | None = None,
    payload: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    row = db.query(TradingSimulationSessionModel).get(session_id)
    if not row:
        raise ValueError("Session not found")

    action = TradingSimulationActionModel(
        session_id=session_id,
        action_type=(action_type or "note").strip().lower(),
        step_id=step_id,
        note=note,
        payload_json=_json_safe(payload or {}),
    )
    db.add(action)
    db.commit()
    db.refresh(action)
    _log_event(
        db,
        session_id,
        "action_recorded",
        {"action_type": action.action_type, "step_id": action.step_id, "note": action.note},
    )
    db.commit()
    state = _evaluate_and_store(db, row)
    state["last_action"] = _action_row_to_dict(action)
    return state


def list_recent_actions(db: Session, session_id: int, limit: int = 100) -> List[Dict[str, Any]]:
    rows = (
        db.query(TradingSimulationActionModel)
        .filter(TradingSimulationActionModel.session_id == session_id)
        .order_by(TradingSimulationActionModel.id.desc())
        .limit(max(1, min(limit, 500)))
        .all()
    )
    return [_action_row_to_dict(r) for r in rows]


def capability_matrix() -> List[Dict[str, Any]]:
    """
    Reconcile registry and manager catalogs.
    listed: in product registry
    runnable: has runtime path
    has_live_state: has a state file mapping in manager
    has_playbook: playbook definitions exist
    """
    registry_ids = {s.id for s in StrategyRegistry.get_all_strategies()}
    try:
        from Strategies.strategy_manager import STRATEGY_PATHS

        strategy_paths = STRATEGY_PATHS if isinstance(STRATEGY_PATHS, dict) else {}
    except Exception:
        strategy_paths = {}

    manager_ids = set(strategy_paths.keys())
    ids = sorted(registry_ids | manager_ids)
    rows: List[Dict[str, Any]] = []

    for sid in ids:
        listed = sid in registry_ids
        runnable = sid in manager_ids
        has_live_state = bool(strategy_paths.get(sid, {}).get("state")) if runnable else False
        has_pb = has_playbook(sid)

        if listed and runnable:
            status_label = "Live Runnable"
        elif listed and not runnable:
            status_label = "Replay Only"
        else:
            status_label = "Coming Soon"

        rows.append(
            {
                "strategy_id": sid,
                "listed": listed,
                "runnable": runnable,
                "has_live_state": has_live_state,
                "has_playbook": has_pb,
                "status_label": status_label,
            }
        )
    return rows
