"""
Guided Trading Simulation control-plane routes.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..core.trading_simulation.education import get_strategy_guide
from ..core.trading_simulation.playbooks import get_playbook
from ..core.trading_simulation.session_service import (
    capability_matrix,
    create_session,
    get_session,
    get_state,
    record_action,
)
from ..models.database import get_db
from ..models.schemas import (
    TradingSimulationActionRequest,
    TradingSimulationActionResponse,
    TradingSimulationCapabilityResponse,
    TradingSimulationGuideResponse,
    TradingSimulationSessionCreateRequest,
    TradingSimulationSessionResponse,
)

router = APIRouter(prefix="/trading-simulation", tags=["TradingSimulation"])


@router.get("/capabilities", response_model=list[TradingSimulationCapabilityResponse])
def trading_sim_capabilities():
    return capability_matrix()


@router.post("/sessions", response_model=TradingSimulationSessionResponse)
def trading_sim_create_session(req: TradingSimulationSessionCreateRequest, db: Session = Depends(get_db)):
    try:
        state = create_session(
            db=db,
            strategy_id=req.strategy_id,
            symbol=req.symbol,
            timeframe=req.timeframe,
            mode=req.mode,
            confirm_live_mode=req.confirm_live_mode,
        )
        return state
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/sessions/{session_id}", response_model=TradingSimulationSessionResponse)
def trading_sim_get_session(session_id: int, db: Session = Depends(get_db)):
    try:
        return get_session(db, session_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


@router.get("/sessions/{session_id}/state", response_model=TradingSimulationSessionResponse)
def trading_sim_get_state(session_id: int, db: Session = Depends(get_db)):
    try:
        return get_state(db, session_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


@router.post("/sessions/{session_id}/action", response_model=TradingSimulationActionResponse)
def trading_sim_action(
    session_id: int,
    req: TradingSimulationActionRequest,
    db: Session = Depends(get_db),
):
    try:
        state = record_action(
            db=db,
            session_id=session_id,
            action_type=req.action_type,
            step_id=req.step_id,
            note=req.note,
            payload=req.payload,
        )
        return {"ok": True, "state": state}
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


@router.get("/strategies/{strategy_id}/guide", response_model=TradingSimulationGuideResponse)
def trading_sim_guide(strategy_id: str):
    return get_strategy_guide(strategy_id)


@router.get("/strategies/{strategy_id}/playbook")
def trading_sim_playbook(strategy_id: str):
    return get_playbook(strategy_id)

