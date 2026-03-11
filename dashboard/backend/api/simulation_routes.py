"""
Simulation Dashboard API Routes
Interactive trading simulation with replay and step-by-step guidance
"""

import asyncio
import hashlib
import uuid
import math
import re
import os
import ipaddress
import pandas as pd
from time import perf_counter
import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Body
from fastapi import Request
from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy import desc, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field, ValidationError, field_validator, model_validator
from typing import Optional, List, Dict, Any, Literal, Tuple
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse
import json
import logging
from threading import Lock, RLock

from ..models.database import (
    get_db,
    SessionLocal,
    SimulationSession,
    SimulationTrade,
    AIBotRunModel,
    WorkbenchCopilotSessionModel,
    WorkbenchCopilotEventModel,
    WorkbenchCopilotAdviceModel,
    WorkbenchCopilotActionModel,
    WorkbenchCopilotSnapshotModel,
    WorkbenchCopilotJobModel,
    WorkbenchAgentSessionModel,
    WorkbenchAgentEventModel,
    WorkbenchAgentActionModel,
    WorkbenchAgentSnapshotModel,
    WorkbenchAgentMemoryModel,
)
from ..core.simulation_engine import INSTRUMENT_SPECS, SimulationReplayEngine
from ..core.instrument_specs import get_instrument
from ..core.simulation_step_definitions import get_step_definitions, get_all_strategy_steps
from ..core.strategy_registry import StrategyRegistry
from ..core.strategies.factory import create_strategy
from ..core.workbench import WORKBENCH_ID, get_tool, list_tools as list_workbench_tools
from ..core.workbench.coach import WorkbenchCoach, build_workbench_context
from ..core.workbench.consultant import WorkbenchConsultant
from ..core.workbench.agent import WorkbenchAgent
from ..core.workbench.circuit_breaker import get_circuit_breaker
from ..core.workbench.cost_model import DEFAULT_TC_RATE, INSTRUMENT_SPREAD, WorkbenchCostModel
from ..core.workbench.delta_context import get_delta_manager
from ..core.workbench.intent_classifier import get_tools_for_intent
from ..core.workbench.parameter_optimizer import (
    count_combinations,
    count_float_combinations,
    count_sma_crossover_combinations,
    optimize_mean_reversion,
    optimize_sma_crossover,
    parse_float_range,
    parse_int_range,
)
from ..core.workbench.ml_diagnostic import compute_feature_diagnostic
from ..core.workbench_copilot import (
    normalize_copilot_mode,
    normalize_copilot_config,
    process_copilot_iteration,
)
from ..services.workbench_copilot_runtime import (
    set_runtime as set_copilot_runtime,
    get_runtime as get_copilot_runtime,
    clear_runtime as clear_copilot_runtime,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/simulation", tags=["Simulation"])

# In-memory engine cache with LRU eviction
MAX_CACHED_ENGINES = 20
_engines: Dict[int, SimulationReplayEngine] = {}
_engine_access_order: List[int] = []  # Most recently accessed at end

_COPILOT_SENSITIVE_CONFIG_KEYS = {
    "openai_api_key",
    "anthropic_api_key",
    "api_key",
    "llm_api_key",
}

_MT5_SERVICE_SINGLETON = None
_COST_SPREAD_SOURCE_MANUAL = "manual"
_COST_SPREAD_SOURCE_MT5 = "mt5_live"
_AGENT_SNAPSHOT_MAX_PER_SESSION = 5000
_AGENT_EVENT_PAYLOAD_MAX_BYTES = 64 * 1024
_AGENT_CONTEXT_BARS_MAX = 220
_AGENT_CONTEXT_BARS_MAX_INBOUND = 1200
_AGENT_CONTEXT_ITEMS_MAX_INBOUND = 300
_AGENT_TOOL_STATE_MAX_BYTES_INBOUND = 256 * 1024
_AGENT_SESSION_LOCKS: Dict[int, RLock] = {}
_AGENT_SESSION_LOCKS_GUARD = Lock()
_AGENT_MEMORY_MAX_PER_SCOPE = 800
_AGENT_MEMORY_SEARCH_FETCH_CAP = _AGENT_MEMORY_MAX_PER_SCOPE
_AGENT_MEMORY_PRUNE_MIN_INTERVAL_SEC = 30.0
_AGENT_MEMORY_PRUNE_LAST_RUN: Dict[int, datetime] = {}
_AGENT_MEMORY_CHARGRAM_N = 3
_AGENT_MEMORY_CHARGRAM_MAX = 240
_AGENT_MEMORY_SYNONYM_MAP: Dict[str, List[str]] = {
    "fvg": ["fair", "value", "gap", "imbalance"],
    "htf": ["higher", "timeframe", "high_timeframe"],
    "ltf": ["lower", "timeframe", "low_timeframe"],
    "m15": ["15m", "15min"],
    "h1": ["1h", "60m", "60min"],
    "h4": ["4h", "240m", "240min"],
    "d1": ["1d", "daily"],
    "buy": ["long", "bullish"],
    "sell": ["short", "bearish"],
    "mitigation": ["mitigate", "fill", "filled", "touch"],
    "breaker": ["break", "breakout", "invalidated"],
    "sl": ["stop", "stoploss", "stop_loss"],
    "tp": ["target", "takeprofit", "take_profit"],
}
_AGENT_MEMORY_POLICY_DEFAULT = {
    "enabled": True,
    "ttl_days_default": 180.0,
    "ttl_days_by_type": {
        "trader_rule": 365.0,
        "note": 120.0,
        "agent_reply": 30.0,
    },
    "pinned_never_expires": True,
    "min_importance": 0.10,
    "max_hits": 12,
    "recency_half_life_days": 21.0,
    "pin_bonus": 0.25,
}
_AGENT_IDENTITY_PRESETS = {
    "apprentice": {
        "enabled": True,
        "version": 1,
        "lock_personality": True,
        "persona": "Learning trader focused on understanding setups before executing.",
        "tone": "Direct, educational, risk-aware.",
        "risk_doctrine": [
            "Capital preservation first. Every trade needs a clear invalidation level and stop-loss.",
            "Explain the reasoning behind every setup: what confirms it, what invalidates it.",
        ],
        "immutable_rules": [
            "Never fabricate data or bypass risk constraints.",
        ],
    },
    "master_quant": {
        "enabled": True,
        "version": 1,
        "lock_personality": True,
        "persona": "Professional quant trader executing systematic HTF-to-LTF strategies.",
        "tone": "Decisive, evidence-driven, execution-focused.",
        "risk_doctrine": [
            "Capital preservation is non-negotiable. Every entry needs invalidation, position sizing, and defined expiry.",
            "Only trade asymmetric setups: HTF bias aligned with LTF confirmation. Unconfirmed signals are noise.",
        ],
        "immutable_rules": [
            "Never fabricate data or bypass risk constraints.",
        ],
    },
}
_AGENT_IDENTITY_DEFAULT = dict(_AGENT_IDENTITY_PRESETS["master_quant"])
_AGENT_IDENTITY_MUTATION_TYPES = {"identity", "persona", "personality", "tone", "style", "character"}
_AGENT_NEWS_CACHE: Dict[str, Dict[str, Any]] = {}
_AGENT_NEWS_CACHE_LOCK = Lock()
_AGENT_NEWS_FETCH_LOCK = Lock()
_AGENT_NEWS_CACHE_TTL_SEC = 45.0
_AGENT_NEWS_CACHE_MAX_ENTRIES = 512
_AGENT_NEWS_CACHE_HITS = 0
_AGENT_NEWS_CACHE_MISSES = 0
_AGENT_NEWS_FETCH_COUNT = 0
_AGENT_NEWS_FETCH_ERROR_COUNT = 0
_AGENT_NEWS_COUNTERS_LOCK = Lock()
_AGENT_NEWS_SUMMARY_CACHE: Dict[str, Dict[str, Any]] = {}
_AGENT_NEWS_SUMMARY_CACHE_LOCK = Lock()
_AGENT_NEWS_SUMMARY_CACHE_TTL_SEC = 20 * 60.0  # 20 minutes
_AGENT_NEWS_SUMMARY_CACHE_MAX_ENTRIES = 512

_AGENT_NEWS_SYMBOL_MAP: Dict[str, str] = {
    "XAUUSD": "GLD",
    "XAU": "GLD",
    "GOLD": "GLD",
    "US500": "SPY",
    "SP500": "SPY",
    "SPX500": "SPY",
    "SPX": "SPY",
    "NAS100": "QQQ",
    "US100": "QQQ",
    "NQ100": "QQQ",
    "NDX": "QQQ",
    "US30": "DIA",
    "DJ30": "DIA",
    "DJIA": "DIA",
    "GER40": "EWG",
    "DAX40": "EWG",
    "DAX": "EWG",
    "UK100": "EWU",
    "FTSE100": "EWU",
    "EURUSD": "FXE",
    "GBPUSD": "FXB",
    "USDJPY": "FXY",
    "AUDUSD": "FXA",
    "USDCAD": "FXC",
    "USDCHF": "FXF",
    "BTCUSD": "IBIT",
    "ETHUSD": "ETHA",
}

# Deliberately excludes XAU/XAUUSD because GLD is an ETF proxy, not spot-gold news.
_AGENT_IBKR_NEWS_PROXY_SYMBOL_MAP: Dict[str, str] = {
    "US500": "SPY",
    "SP500": "SPY",
    "SPX500": "SPY",
    "SPX": "SPY",
    "NAS100": "QQQ",
    "US100": "QQQ",
    "NQ100": "QQQ",
    "NDX": "QQQ",
    "US30": "DIA",
    "DJ30": "DIA",
    "DJIA": "DIA",
    "GER40": "EWG",
    "DAX40": "EWG",
    "DAX": "EWG",
    "UK100": "EWU",
    "FTSE100": "EWU",
    "EURUSD": "FXE",
    "GBPUSD": "FXB",
    "USDJPY": "FXY",
    "AUDUSD": "FXA",
    "USDCAD": "FXC",
    "USDCHF": "FXF",
    "BTCUSD": "IBIT",
    "ETHUSD": "ETHA",
}

_AGENT_NEWS_HIGH_IMPACT_KEYWORDS = [
    "fomc",
    "federal reserve",
    "powell",
    "cpi",
    "ppi",
    "nfp",
    "payroll",
    "interest rate",
    "rate decision",
    "ecb",
    "boe",
    "boj",
    "inflation",
    "geopolit",
    "war",
    "tariff",
    "sanction",
    "gdp",
    "unemployment",
]
_AGENT_NEWS_HIGH_IMPACT_SUBSTRINGS = [
    "geopolit",
]

_AGENT_STRATEGY_TOOL_GROUPS: Dict[str, Dict[str, Any]] = {
    "htf_fvg_trading": {
        "parent": "run_mtf_analysis",
        "children": [
            "scan_tool",
            "scan_draw_fvg_range",
            "get_indicator_values",
        ],
    },
}

_AGENT_STRATEGY_TOOL_ACCESS_MODES = {"all", "parent", "child"}
_AGENT_TOOL_SELECTION_MODES = {"autonomous", "guided", "minimal"}


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _get_agent_session_lock(simulation_session_id: int) -> RLock:
    sid = int(simulation_session_id)
    with _AGENT_SESSION_LOCKS_GUARD:
        lock = _AGENT_SESSION_LOCKS.get(sid)
        if lock is None:
            lock = RLock()
            _AGENT_SESSION_LOCKS[sid] = lock
        return lock


def _get_mt5_service_singleton():
    """Reuse one MT5 service instance to avoid repeated init/shutdown churn."""
    global _MT5_SERVICE_SINGLETON
    if _MT5_SERVICE_SINGLETON is None:
        from ..services.live_service import LiveTradingService

        _MT5_SERVICE_SINGLETON = LiveTradingService()
    return _MT5_SERVICE_SINGLETON


def _clear_cached_engine(session_id: int) -> None:
    """Drop session engine from cache + access-order list."""
    _engines.pop(session_id, None)
    while session_id in _engine_access_order:
        _engine_access_order.remove(session_id)


def _supported_strategy_ids() -> List[str]:
    """Strategies that are both registered and supported by strategy factory."""
    ids: List[str] = []
    for strategy in StrategyRegistry.get_all_strategies():
        if create_strategy(strategy.id, {}) is not None:
            ids.append(strategy.id)
    return ids


def _default_steps_for_strategy(strategy_id: str) -> Dict[str, Any]:
    """Fallback step guide for strategies without dedicated simulation docs."""
    if strategy_id == WORKBENCH_ID:
        return {
            "name": "Trader's Workbench",
            "description": "Free Trading Workbench",
            "steps": [],
        }
    return {
        "name": strategy_id.replace("_", " ").title(),
        "description": "Replay mode with strategy context and manual execution practice.",
        "steps": [
            {
                "id": "sim_1",
                "title": "Load Market Context",
                "description": "Wait for the day/session context and directional bias to initialize.",
                "condition": "has_day_context",
                "icon": "bi-compass",
            },
            {
                "id": "sim_2",
                "title": "Wait for Setup",
                "description": "Only act when the strategy reports a valid setup suggestion.",
                "condition": "strategy_setup_detected",
                "icon": "bi-lightning-charge",
            },
            {
                "id": "sim_3",
                "title": "Execute with Risk",
                "description": "Enter with predefined stop loss/take profit and consistent size.",
                "condition": "has_open_position",
                "icon": "bi-cursor",
            },
            {
                "id": "sim_4",
                "title": "Review Outcome",
                "description": "After close, review P&L, R-multiple, and whether rules were followed.",
                "condition": "position_closed",
                "icon": "bi-journal-check",
            },
        ],
        "info": {
            "what": "This strategy currently uses a generic simulation guide. Follow setup, risk, and review discipline.",
            "best_conditions": "Use liquid sessions and avoid forcing trades when no setup is present.",
            "common_mistakes": [
                "Entering before setup confirmation.",
                "Changing stop loss after entry.",
                "Oversizing after wins/losses.",
            ],
            "glossary": {
                "Setup": "A valid trade condition produced by strategy logic.",
                "R-multiple": "Profit/loss relative to your initial stop distance.",
            },
        },
    }


# ── Pydantic models ──────────────────────────────────────────────

class CreateSessionRequest(BaseModel):
    strategy_id: str
    symbol: str = "XAUUSD"
    timeframe: str = "M1"
    data_file: Optional[str] = None
    initial_balance: float = 10000.0
    config: Optional[Dict[str, Any]] = None
    allow_empty_replay: bool = False


class AdvanceRequest(BaseModel):
    count: int = Field(default=1, ge=1, le=500)
    indicators_mode: str = "delta"  # "delta" (fast) | "full" (compat)


class TradeRequest(BaseModel):
    direction: str  # BUY | SELL
    stop_loss: float
    take_profit: Optional[float] = None
    lot_size: float = Field(default=0.01, gt=0.0, le=100.0)
    entry_price: Optional[float] = None
    bar_time_unix: Optional[int] = None
    cost_spread: Optional[float] = None
    cost_tc_rate: Optional[float] = None
    cost_spread_source: Optional[str] = None

    @model_validator(mode="after")
    def _validate_positive_levels(self):
        if self.stop_loss is None or not math.isfinite(float(self.stop_loss)) or float(self.stop_loss) <= 0.0:
            raise ValueError("stop_loss must be a positive finite number")
        if self.take_profit is not None and (not math.isfinite(float(self.take_profit)) or float(self.take_profit) <= 0.0):
            raise ValueError("take_profit must be a positive finite number")
        if self.entry_price is not None and (not math.isfinite(float(self.entry_price)) or float(self.entry_price) <= 0.0):
            raise ValueError("entry_price must be a positive finite number")
        return self


class CloseTradeRequest(BaseModel):
    exit_price: Optional[float] = None
    bar_time_unix: Optional[int] = None
    cost_spread: Optional[float] = None
    cost_tc_rate: Optional[float] = None
    cost_spread_source: Optional[str] = None


class CostModelUpdateRequest(BaseModel):
    enabled: Optional[bool] = None
    spread: Optional[float] = None
    tc_rate: Optional[float] = None
    spread_source: Optional[str] = None


# ── Helper ──────────────────────────────────────────────────────

def _get_or_create_engine(session: SimulationSession, db: Session) -> SimulationReplayEngine:
    """Get cached engine or create new one for this session (with LRU eviction)."""
    if session.id in _engines:
        # Move to end of access order (most recent)
        while session.id in _engine_access_order:
            _engine_access_order.remove(session.id)
        _engine_access_order.append(session.id)
        return _engines[session.id]
    # On cache miss, rebuild from persisted session bar so rewind states stay consistent.
    engine = _rebuild_engine_to_bar(session, session.current_bar, db)
    while len(_engines) >= MAX_CACHED_ENGINES and _engine_access_order:
        evict_id = _engine_access_order.pop(0)
        _engines.pop(evict_id, None)
    _engines[session.id] = engine
    _engine_access_order.append(session.id)
    return engine


def _sync_session(
    session: SimulationSession,
    engine: SimulationReplayEngine,
    db: Session,
    auto_commit: bool = True,
):
    """Sync engine state back to database."""
    session.current_bar = engine.current_bar
    session.current_balance = engine.balance
    session.total_pnl = engine.balance - session.initial_balance
    session.trades_count = len(engine.closed_trades)
    session.wins = sum(1 for t in engine.closed_trades if (t.get("pnl") or 0) > 0)
    session.losses = sum(1 for t in engine.closed_trades if (t.get("pnl") or 0) < 0)
    session.updated_at = datetime.utcnow()
    if auto_commit:
        db.commit()
    else:
        db.flush()


def _run_advance(
    session: SimulationSession,
    engine: SimulationReplayEngine,
    count: int,
    indicators_mode: str,
    db: Session,
) -> Dict[str, Any]:
    """Shared advance executor used by HTTP route and WS stream."""
    target = min(engine.current_bar + count, engine.total_bars - 1)
    result = engine.advance_to_bar(target)

    mode = (indicators_mode or "delta").strip().lower()
    if mode not in ("delta", "full"):
        mode = "delta"

    if mode == "delta":
        result["indicators"] = result.get("indicators_delta", {})
        result["indicators_mode"] = "delta"
        result.pop("indicators_delta", None)
    else:
        result["indicators_mode"] = "full"
        result.pop("indicators_delta", None)

    use_cost_model = _is_cost_model_enabled(session)
    cost_model = _session_cost_model(session) if use_cost_model else None

    # Persist any closed trades
    for ct in result.get("closed_trades", []):
        trade_id = ct.get("id")
        if trade_id:
            trade = db.query(SimulationTrade).get(trade_id)
            if trade:
                raw_pnl = float(ct.get("pnl") or 0.0)
                trade.exit_price = ct["exit_price"]
                trade.exit_bar = ct["exit_bar"]
                trade.exit_time = ct.get("exit_time")
                trade.exit_reason = ct.get("exit_reason")
                trade.raw_pnl = raw_pnl
                trade.pnl = raw_pnl
                trade.r_multiple = ct.get("r_multiple")
                trade.status = "closed"
                trade.exit_mid_price = float(ct["exit_price"]) if ct.get("exit_price") is not None else None
                trade.exit_fill_price = float(ct["exit_price"]) if ct.get("exit_price") is not None else None
                if use_cost_model and cost_model is not None and trade.exit_mid_price is not None:
                    ct = _apply_close_cost_adjustment(
                        session=session,
                        engine=engine,
                        trade=trade,
                        close_result=ct,
                        exit_mid_price=float(trade.exit_mid_price),
                        cost_model=cost_model,
                    )
                    trade.exit_price = _to_float_or_none(ct.get("exit_price"))
                    trade.exit_fill_price = trade.exit_price
                    trade.pnl = _to_float_or_none(ct.get("pnl"))
                    trade.raw_pnl = _to_float_or_none(ct.get("raw_pnl"))
                    trade.spread_cost = _to_float_or_none(ct.get("spread_cost"))
                    trade.turnover_cost = _to_float_or_none(ct.get("turnover_cost"))
                    trade.total_cost = _to_float_or_none(ct.get("total_cost"))
                    trade.cost_breakdown_json = ct.get("cost_breakdown") if isinstance(ct.get("cost_breakdown"), dict) else None
                else:
                    trade.spread_cost = 0.0
                    trade.turnover_cost = 0.0
                    trade.total_cost = 0.0

    _sync_session(session, engine, db, auto_commit=False)

    if engine.current_bar >= engine.total_bars - 1:
        session.status = "completed"
        db.flush()

    result["trades_count"] = session.trades_count
    result["wins"] = session.wins
    result["losses"] = session.losses
    result["total_pnl"] = session.total_pnl
    result["balance"] = session.current_balance
    result["initial_balance"] = session.initial_balance
    result["status"] = session.status
    try:
        _record_copilot_iteration(session=session, advance_result=result, db=db, auto_commit=False)
    except Exception as exc:
        logger.warning("Copilot iteration skipped: %s", exc)
    db.commit()
    return result


def _rebuild_engine_to_bar(session: SimulationSession, target_bar: int, db: Session) -> SimulationReplayEngine:
    """
    Rebuild engine state from scratch to target bar.
    Keeps day context and manual-trade state aligned after rewind/seek.
    """
    _clear_cached_engine(session.id)
    config = json.loads(session.config_json) if session.config_json else {}
    engine = SimulationReplayEngine(
        strategy_id=session.strategy_id,
        symbol=session.symbol,
        timeframe=session.timeframe,
        data_file=session.data_file,
        config=config,
    )
    if engine.total_bars <= 0:
        return engine

    return _restore_engine_state_for_bar(engine, session, target_bar, db)


def _restore_engine_state_for_bar(
    engine: SimulationReplayEngine,
    session: SimulationSession,
    target_bar: int,
    db: Session,
) -> SimulationReplayEngine:
    """Restore engine cursor/day/trade state for a target bar without full replay."""
    target = max(0, min(target_bar, engine.total_bars - 1))
    # Fast seek: avoid replaying every bar from 0..target.
    # We only need cursor position, day context, and persisted trade state.
    engine.current_bar = target
    engine._has_streamed_bar = True
    engine._indicators_cache = {}
    engine._indicator_offsets = {}
    if engine._strategy_available and engine.df is not None and not engine.df.empty:
        try:
            bar_date = engine.df.index[target]
            day_date = bar_date.date() if hasattr(bar_date, "date") else bar_date
            engine.current_date = day_date
            daily_slice = engine._daily_df[engine._daily_df.index.date <= day_date]
            intraday_slice = engine.df.iloc[: target + 1]
            engine.day_context = engine._strategy.initialize_day(day_date, daily_slice, intraday_slice)
        except Exception:
            engine.day_context = None

    trades = db.query(SimulationTrade).filter(
        SimulationTrade.session_id == session.id
    ).order_by(SimulationTrade.id).all()

    closed_trades: List[Dict[str, Any]] = []
    open_positions: List[Dict[str, Any]] = []
    realized_pnl = 0.0

    for t in trades:
        if t.entry_bar is None or t.entry_bar > target:
            continue
        closed_by_target = (t.exit_bar is not None and t.exit_bar <= target)
        if closed_by_target:
            pnl = float(t.pnl or 0.0)
            realized_pnl += pnl
            closed_trades.append(
                {
                    "id": t.id,
                    "direction": t.direction,
                    "entry_price": float(t.entry_price),
                    "exit_price": float(t.exit_price) if t.exit_price is not None else None,
                    "exit_bar": int(t.exit_bar),
                    "exit_time": t.exit_time,
                    "exit_reason": t.exit_reason,
                    "pnl": pnl,
                    "r_multiple": float(t.r_multiple or 0.0),
                    "lot_size": float(t.lot_size or 0.0),
                }
            )
        else:
            open_positions.append(
                {
                    "id": t.id,
                    "direction": t.direction,
                    "entry_price": float(t.entry_price),
                    "entry_bar": int(t.entry_bar),
                    "entry_time": t.entry_time,
                    "stop_loss": float(t.stop_loss),
                    "take_profit": float(t.take_profit) if t.take_profit is not None else None,
                    "lot_size": float(t.lot_size or 0.01),
                }
            )

    engine.closed_trades = closed_trades
    engine.open_positions = open_positions
    engine.balance = float(session.initial_balance) + realized_pnl
    engine.current_bar = target

    return engine


def _get_active_copilot(
    simulation_session_id: int,
    db: Session,
) -> Optional[WorkbenchCopilotSessionModel]:
    return (
        db.query(WorkbenchCopilotSessionModel)
        .filter(WorkbenchCopilotSessionModel.simulation_session_id == int(simulation_session_id))
        .filter(WorkbenchCopilotSessionModel.status == "ACTIVE")
        .order_by(WorkbenchCopilotSessionModel.created_at.desc())
        .first()
    )


def _get_active_agent(
    simulation_session_id: int,
    db: Session,
) -> Optional[WorkbenchAgentSessionModel]:
    return (
        db.query(WorkbenchAgentSessionModel)
        .filter(WorkbenchAgentSessionModel.simulation_session_id == int(simulation_session_id))
        .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
        .order_by(WorkbenchAgentSessionModel.created_at.desc())
        .first()
    )


def _get_latest_agent(
    simulation_session_id: int,
    db: Session,
) -> Optional[WorkbenchAgentSessionModel]:
    return (
        db.query(WorkbenchAgentSessionModel)
        .filter(WorkbenchAgentSessionModel.simulation_session_id == int(simulation_session_id))
        .order_by(WorkbenchAgentSessionModel.created_at.desc())
        .first()
    )


def _ensure_agent_session(
    simulation_session_id: int,
    db: Session,
    mode: str = "LOOP",
    provider: str = "deterministic",
    model_label: Optional[str] = None,
    permissions: Optional[Dict[str, Any]] = None,
    config: Optional[Dict[str, Any]] = None,
    runtime: Optional[Dict[str, Any]] = None,
    copilot_session_id: Optional[int] = None,
) -> WorkbenchAgentSessionModel:
    lock = _get_agent_session_lock(int(simulation_session_id))
    with lock:
        active_rows = (
            db.query(WorkbenchAgentSessionModel)
            .filter(WorkbenchAgentSessionModel.simulation_session_id == int(simulation_session_id))
            .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
            .order_by(WorkbenchAgentSessionModel.created_at.desc(), WorkbenchAgentSessionModel.id.desc())
            .all()
        )
        row = active_rows[0] if active_rows else None
        if len(active_rows) > 1:
            # Race recovery: keep newest active row, close older duplicates.
            for dup in active_rows[1:]:
                dup.status = "STOPPED"
                dup.stopped_at = _utc_now()
                dup.updated_at = _utc_now()
                db.add(dup)

        if row is None:
            row = WorkbenchAgentSessionModel(
                simulation_session_id=int(simulation_session_id),
                copilot_session_id=int(copilot_session_id) if copilot_session_id is not None else None,
                mode=str(mode or "LOOP"),
                status="ACTIVE",
                provider=str(provider or "deterministic"),
                model_label=str(model_label or "").strip() or None,
                permissions_json=permissions if isinstance(permissions, dict) else {},
                config_json=config if isinstance(config, dict) else {},
                runtime_json=runtime if isinstance(runtime, dict) else {},
                last_snapshot_json={},
                created_at=_utc_now(),
                updated_at=_utc_now(),
            )
            db.add(row)
            db.flush()
            return row

        row.status = "ACTIVE"
        row.mode = str(mode or row.mode or "LOOP")
        row.provider = str(provider or row.provider or "deterministic")
        if model_label is not None:
            row.model_label = str(model_label or "").strip() or None
        if isinstance(permissions, dict):
            row.permissions_json = permissions
        if isinstance(config, dict):
            row.config_json = config
        if isinstance(runtime, dict):
            row.runtime_json = runtime
        if copilot_session_id is not None:
            row.copilot_session_id = int(copilot_session_id)
        row.updated_at = _utc_now()
        row.stopped_at = None
        db.add(row)
        db.flush()
        return row


def _safe_agent_event_payload(payload: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Bound stored event payload size to avoid DB bloat from oversized context blobs."""
    obj = payload if isinstance(payload, dict) else {}
    try:
        raw = json.dumps(obj, ensure_ascii=True, sort_keys=True)
    except Exception:
        return {"_truncated": True, "_reason": "non_serializable_payload"}
    if len(raw.encode("utf-8")) <= int(_AGENT_EVENT_PAYLOAD_MAX_BYTES):
        return obj
    preview = raw[:2000]
    return {
        "_truncated": True,
        "_reason": "payload_too_large",
        "_max_bytes": int(_AGENT_EVENT_PAYLOAD_MAX_BYTES),
        "_approx_size_bytes": int(len(raw.encode("utf-8"))),
        "preview": preview,
    }


def _agent_emit_event(
    agent: Optional[WorkbenchAgentSessionModel],
    event_type: str,
    db: Session,
    payload: Optional[Dict[str, Any]] = None,
    severity: str = "info",
) -> Optional[WorkbenchAgentEventModel]:
    if agent is None:
        return None
    ev = WorkbenchAgentEventModel(
        agent_session_id=int(agent.id),
        event_type=str(event_type or "UNKNOWN"),
        severity=str(severity or "info"),
        payload_json=_safe_agent_event_payload(payload),
        created_at=_utc_now(),
    )
    db.add(ev)
    db.flush()
    return ev


def _agent_store_snapshot(
    agent: Optional[WorkbenchAgentSessionModel],
    simulation_session: SimulationSession,
    db: Session,
    source: str,
    patch: Optional[Dict[str, Any]] = None,
) -> None:
    if agent is None:
        return
    base = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
    snap = dict(base)
    snap.update(
        {
            "ts": _utc_now().isoformat(),
            "session_id": int(simulation_session.id),
            "strategy_id": str(simulation_session.strategy_id or ""),
            "symbol": str(simulation_session.symbol or ""),
            "timeframe": str(simulation_session.timeframe or ""),
            "current_bar": int(simulation_session.current_bar or 0),
            "total_bars": int(simulation_session.total_bars or 0),
            "balance": float(simulation_session.current_balance or 0.0),
            "initial_balance": float(simulation_session.initial_balance or 0.0),
            "total_pnl": float(simulation_session.total_pnl or 0.0),
            "trades_count": int(simulation_session.trades_count or 0),
            "wins": int(simulation_session.wins or 0),
            "losses": int(simulation_session.losses or 0),
        }
    )
    if isinstance(patch, dict):
        snap.update(patch)

    agent.last_snapshot_json = snap
    agent.updated_at = _utc_now()
    db.add(agent)
    db.add(
        WorkbenchAgentSnapshotModel(
            agent_session_id=int(agent.id),
            bar_index=int(simulation_session.current_bar or 0),
            source=str(source or "external"),
            snapshot_json=snap,
            created_at=_utc_now(),
        )
    )
    db.flush()
    keep = max(1, int(_AGENT_SNAPSHOT_MAX_PER_SESSION))
    total = (
        db.query(WorkbenchAgentSnapshotModel)
        .filter(WorkbenchAgentSnapshotModel.agent_session_id == int(agent.id))
        .count()
    )
    overflow = int(total - keep)
    if overflow > 0:
        stale_ids = (
            db.query(WorkbenchAgentSnapshotModel.id)
            .filter(WorkbenchAgentSnapshotModel.agent_session_id == int(agent.id))
            .order_by(WorkbenchAgentSnapshotModel.id.asc())
            .limit(int(overflow))
            .all()
        )
        stale_values = [int(r[0]) for r in stale_ids if r and r[0] is not None]
        if stale_values:
            (
                db.query(WorkbenchAgentSnapshotModel)
                .filter(WorkbenchAgentSnapshotModel.id.in_(stale_values))
                .delete(synchronize_session=False)
            )


def _agent_usage_safe_int(v: Any, default: int = 0) -> int:
    try:
        if v is None:
            return int(default)
        return int(v)
    except Exception:
        return int(default)


def _agent_usage_safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        return float(v)
    except Exception:
        return float(default)


def _normalize_agent_usage_payload(raw: Any) -> Dict[str, Any]:
    src = raw if isinstance(raw, dict) else {}
    inp = max(0, _agent_usage_safe_int(src.get("input_tokens"), 0))
    out = max(0, _agent_usage_safe_int(src.get("output_tokens"), 0))
    total = max(0, _agent_usage_safe_int(src.get("total_tokens"), inp + out))
    calls = max(0, _agent_usage_safe_int(src.get("api_calls"), 0))
    est = max(0.0, _agent_usage_safe_float(src.get("estimated_cost_usd"), 0.0))
    return {
        "provider": str(src.get("provider") or ""),
        "model": str(src.get("model") or ""),
        "input_tokens": int(inp),
        "output_tokens": int(out),
        "total_tokens": int(total),
        "api_calls": int(calls),
        "estimated_cost_usd": float(est),
        "cost_estimate_source": str(src.get("cost_estimate_source") or ""),
    }


def _agent_rollup_usage_meter(
    prev_snapshot: Dict[str, Any],
    usage: Dict[str, Any],
) -> Dict[str, Any]:
    u = _normalize_agent_usage_payload(usage)
    prev = prev_snapshot if isinstance(prev_snapshot, dict) else {}
    meter = prev.get("usage_meter") if isinstance(prev.get("usage_meter"), dict) else {}
    out = dict(meter)

    now = datetime.now(timezone.utc)
    day = now.date().isoformat()
    prev_day = str(out.get("day") or "")
    if prev_day != day:
        out["day"] = day
        out["day_input_tokens"] = 0
        out["day_output_tokens"] = 0
        out["day_total_tokens"] = 0
        out["day_estimated_cost_usd"] = 0.0
        out["day_llm_calls"] = 0

    out["lifetime_input_tokens"] = max(0, _agent_usage_safe_int(out.get("lifetime_input_tokens"), 0))
    out["lifetime_output_tokens"] = max(0, _agent_usage_safe_int(out.get("lifetime_output_tokens"), 0))
    out["lifetime_total_tokens"] = max(0, _agent_usage_safe_int(out.get("lifetime_total_tokens"), 0))
    out["lifetime_estimated_cost_usd"] = max(0.0, _agent_usage_safe_float(out.get("lifetime_estimated_cost_usd"), 0.0))
    out["lifetime_llm_calls"] = max(0, _agent_usage_safe_int(out.get("lifetime_llm_calls"), 0))

    out["day_input_tokens"] = max(0, _agent_usage_safe_int(out.get("day_input_tokens"), 0) + int(u["input_tokens"]))
    out["day_output_tokens"] = max(0, _agent_usage_safe_int(out.get("day_output_tokens"), 0) + int(u["output_tokens"]))
    out["day_total_tokens"] = max(0, _agent_usage_safe_int(out.get("day_total_tokens"), 0) + int(u["total_tokens"]))
    out["day_estimated_cost_usd"] = max(0.0, _agent_usage_safe_float(out.get("day_estimated_cost_usd"), 0.0) + float(u["estimated_cost_usd"]))
    out["day_llm_calls"] = max(0, _agent_usage_safe_int(out.get("day_llm_calls"), 0) + int(u["api_calls"]))

    out["lifetime_input_tokens"] = max(0, _agent_usage_safe_int(out.get("lifetime_input_tokens"), 0) + int(u["input_tokens"]))
    out["lifetime_output_tokens"] = max(0, _agent_usage_safe_int(out.get("lifetime_output_tokens"), 0) + int(u["output_tokens"]))
    out["lifetime_total_tokens"] = max(0, _agent_usage_safe_int(out.get("lifetime_total_tokens"), 0) + int(u["total_tokens"]))
    out["lifetime_estimated_cost_usd"] = max(0.0, _agent_usage_safe_float(out.get("lifetime_estimated_cost_usd"), 0.0) + float(u["estimated_cost_usd"]))
    out["lifetime_llm_calls"] = max(0, _agent_usage_safe_int(out.get("lifetime_llm_calls"), 0) + int(u["api_calls"]))

    out["last_provider"] = str(u.get("provider") or out.get("last_provider") or "")
    out["last_model"] = str(u.get("model") or out.get("last_model") or "")
    out["last_usage"] = u
    out["last_call_at"] = now.isoformat()
    return out


def _normalize_memory_scope(v: Any) -> str:
    s = str(v or "SESSION").strip().upper()
    if s not in {"GLOBAL", "SESSION", "SYMBOL"}:
        return "SESSION"
    return s


def _normalize_memory_type(v: Any) -> str:
    s = str(v or "note").strip().lower()
    if not s:
        return "note"
    return re.sub(r"[^a-z0-9_]+", "_", s)[:40] or "note"


def _memory_tokens(text: Any) -> List[str]:
    raw = str(text or "").lower()
    parts = re.findall(r"[a-z0-9_]+", raw)
    if not parts:
        return []
    stop = {
        "the",
        "and",
        "for",
        "with",
        "this",
        "that",
        "from",
        "when",
        "then",
        "your",
        "have",
        "will",
        "into",
        "about",
        "what",
        "where",
        "just",
        "also",
    }
    out: List[str] = []
    for p in parts:
        t = str(p).strip()
        if len(t) < 2 or t in stop:
            continue
        out.append(t)
    return out


def _memory_expand_tokens(tokens: Any) -> set[str]:
    base = tokens if isinstance(tokens, list) else []
    out: set[str] = set()
    for tok in base:
        t = str(tok or "").strip().lower()
        if not t:
            continue
        out.add(t)
        # Common suffix trimming for lightweight normalization.
        if len(t) > 4 and t.endswith("ing"):
            out.add(t[:-3])
        if len(t) > 4 and t.endswith("ed"):
            out.add(t[:-2])
        if len(t) > 3 and t.endswith("s"):
            out.add(t[:-1])
        syn = _AGENT_MEMORY_SYNONYM_MAP.get(t)
        if isinstance(syn, list):
            for s in syn:
                st = str(s or "").strip().lower()
                if st:
                    out.add(st)
    return out


def _memory_chargrams(text: Any, n: int = _AGENT_MEMORY_CHARGRAM_N, cap: int = _AGENT_MEMORY_CHARGRAM_MAX) -> set[str]:
    raw = re.sub(r"\s+", " ", str(text or "").strip().lower())
    if not raw:
        return set()
    if len(raw) <= int(n):
        return {raw}
    out: set[str] = set()
    max_len = min(len(raw), int(cap))
    for i in range(0, max_len - int(n) + 1):
        g = raw[i : i + int(n)]
        if g.strip():
            out.add(g)
    return out


def _memory_overlap_scores(query_text: str, content_text: str) -> tuple[float, float, float]:
    qtxt = str(query_text or "").strip()
    ctxt = str(content_text or "").strip()
    q_tokens = set(_memory_tokens(qtxt))
    c_tokens = set(_memory_tokens(ctxt))
    lexical = float(len(q_tokens.intersection(c_tokens))) / float(max(1, len(q_tokens)))
    q_exp = _memory_expand_tokens(list(q_tokens))
    c_exp = _memory_expand_tokens(list(c_tokens))
    semantic = float(len(q_exp.intersection(c_exp))) / float(max(1, len(q_exp)))
    qg = _memory_chargrams(qtxt)
    cg = _memory_chargrams(ctxt)
    char_sim = 0.0
    if qg and cg:
        union = qg.union(cg)
        if union:
            char_sim = float(len(qg.intersection(cg))) / float(len(union))
    return lexical, semantic, char_sim


def _memory_fingerprint(
    *,
    content: str,
    memory_type: str,
    scope: str,
    symbol: Optional[str],
    timeframe: Optional[str],
) -> str:
    base = "|".join(
        [
            str(scope or ""),
            str(memory_type or ""),
            str(symbol or ""),
            str(timeframe or ""),
            re.sub(r"\s+", " ", str(content or "").strip().lower()),
        ]
    )
    return hashlib.sha256(base.encode("utf-8")).hexdigest()


def _sanitize_memory_policy(raw: Any) -> Dict[str, Any]:
    src = raw if isinstance(raw, dict) else {}
    base = dict(_AGENT_MEMORY_POLICY_DEFAULT)
    out: Dict[str, Any] = {}
    out["enabled"] = bool(src.get("enabled", base["enabled"]))
    try:
        out["ttl_days_default"] = max(1.0, min(3650.0, float(src.get("ttl_days_default", base["ttl_days_default"]))))
    except Exception:
        out["ttl_days_default"] = float(base["ttl_days_default"])
    by_type_src = src.get("ttl_days_by_type") if isinstance(src.get("ttl_days_by_type"), dict) else {}
    by_type: Dict[str, float] = {}
    defaults = base.get("ttl_days_by_type") if isinstance(base.get("ttl_days_by_type"), dict) else {}
    merged_types = {**defaults, **by_type_src}
    for k, v in merged_types.items():
        key = _normalize_memory_type(k)
        try:
            days = max(1.0, min(3650.0, float(v)))
        except Exception:
            continue
        by_type[key] = days
    out["ttl_days_by_type"] = by_type
    out["pinned_never_expires"] = bool(src.get("pinned_never_expires", base["pinned_never_expires"]))
    try:
        out["min_importance"] = max(0.0, min(1.0, float(src.get("min_importance", base["min_importance"]))))
    except Exception:
        out["min_importance"] = float(base["min_importance"])
    try:
        out["max_hits"] = int(max(1, min(50, int(src.get("max_hits", base["max_hits"])))))
    except Exception:
        out["max_hits"] = int(base["max_hits"])
    try:
        out["recency_half_life_days"] = max(1.0, min(365.0, float(src.get("recency_half_life_days", base["recency_half_life_days"]))))
    except Exception:
        out["recency_half_life_days"] = float(base["recency_half_life_days"])
    try:
        out["pin_bonus"] = max(0.0, min(1.0, float(src.get("pin_bonus", base["pin_bonus"]))))
    except Exception:
        out["pin_bonus"] = float(base["pin_bonus"])
    return out


def _memory_policy_from_session_config(session: SimulationSession) -> Dict[str, Any]:
    cfg = _session_config_dict(session)
    raw = cfg.get("agent_memory_policy") if isinstance(cfg.get("agent_memory_policy"), dict) else {}
    return _sanitize_memory_policy(raw)


def _memory_policy_update_session_config(
    *,
    session: SimulationSession,
    patch: Dict[str, Any],
) -> Dict[str, Any]:
    cfg = _session_config_dict(session)
    raw = cfg.get("agent_memory_policy") if isinstance(cfg.get("agent_memory_policy"), dict) else {}
    merged = dict(raw)
    patch_dict = patch if isinstance(patch, dict) else {}
    ttl_existing = raw.get("ttl_days_by_type") if isinstance(raw.get("ttl_days_by_type"), dict) else {}
    ttl_patch = patch_dict.get("ttl_days_by_type") if isinstance(patch_dict.get("ttl_days_by_type"), dict) else None
    for k, v in patch_dict.items():
        if k == "ttl_days_by_type":
            continue
        merged[k] = v
    if ttl_patch is not None:
        merged["ttl_days_by_type"] = {**ttl_existing, **ttl_patch}
    clean = _sanitize_memory_policy(merged)
    cfg = dict(cfg)
    cfg["agent_memory_policy"] = clean
    session.config_json = json.dumps(cfg)
    return clean


def _sanitize_agent_identity(raw: Any) -> Dict[str, Any]:
    src = raw if isinstance(raw, dict) else {}
    base = dict(_AGENT_IDENTITY_DEFAULT)
    out: Dict[str, Any] = {}
    out["enabled"] = bool(src.get("enabled", base["enabled"]))
    try:
        out["version"] = int(max(1, min(10_000, int(src.get("version", base["version"])))))
    except Exception:
        out["version"] = int(base["version"])
    out["lock_personality"] = bool(src.get("lock_personality", base["lock_personality"]))
    out["persona"] = str(src.get("persona", base["persona"]) or base["persona"]).strip()[:300]
    out["tone"] = str(src.get("tone", base["tone"]) or base["tone"]).strip()[:300]

    def _norm_list(v: Any, fallback: List[str], max_items: int = 12) -> List[str]:
        if not isinstance(v, list):
            return [str(x)[:220] for x in fallback]
        rows: List[str] = []
        for item in v[: max_items]:
            s = re.sub(r"\s+", " ", str(item or "").strip())
            if len(s) >= 4:
                rows.append(s[:220])
        return rows or [str(x)[:220] for x in fallback]

    out["risk_doctrine"] = _norm_list(src.get("risk_doctrine"), list(base["risk_doctrine"]))
    out["immutable_rules"] = _norm_list(src.get("immutable_rules"), list(base["immutable_rules"]))
    return out


def _agent_identity_from_session_config(session: SimulationSession) -> Dict[str, Any]:
    cfg = _session_config_dict(session)
    raw = cfg.get("agent_identity") if isinstance(cfg.get("agent_identity"), dict) else {}
    return _sanitize_agent_identity(raw)


def _agent_identity_update_session_config(
    *,
    session: SimulationSession,
    patch: Dict[str, Any],
) -> Dict[str, Any]:
    cfg = _session_config_dict(session)
    raw = cfg.get("agent_identity") if isinstance(cfg.get("agent_identity"), dict) else {}
    merged = dict(raw)
    patch_dict = patch if isinstance(patch, dict) else {}
    merged.update(patch_dict)
    clean = _sanitize_agent_identity(merged)
    cfg = dict(cfg)
    cfg["agent_identity"] = clean
    session.config_json = json.dumps(cfg)
    return clean


def _agent_identity_preset_payload(profile_raw: Any) -> Tuple[Optional[str], Optional[Dict[str, Any]]]:
    key = str(profile_raw or "").strip().lower()
    if key in {"master", "master_quant", "quant", "pro"}:
        preset_key = "master_quant"
    elif key in {"apprentice", "basic", "default"}:
        preset_key = "apprentice"
    else:
        return None, None
    src = _AGENT_IDENTITY_PRESETS.get(preset_key)
    if not isinstance(src, dict):
        return None, None
    patch = {
        "enabled": bool(src.get("enabled", True)),
        "version": int(src.get("version", 1)),
        "lock_personality": bool(src.get("lock_personality", True)),
        "persona": str(src.get("persona") or ""),
        "tone": str(src.get("tone") or ""),
        "risk_doctrine": list(src.get("risk_doctrine") or []),
        "immutable_rules": list(src.get("immutable_rules") or []),
    }
    return preset_key, patch


def _memory_note_targets_identity(*, content: str, memory_type: str, identity: Optional[Dict[str, Any]] = None) -> bool:
    ident = _sanitize_agent_identity(identity or {})
    if not bool(ident.get("lock_personality", True)):
        return False
    mtype = _normalize_memory_type(memory_type)
    if mtype in _AGENT_IDENTITY_MUTATION_TYPES:
        return True
    text = re.sub(r"\s+", " ", str(content or "").strip().lower())
    if not text:
        return False
    patterns = [
        r"\b(change|switch|update|rewrite|override)\s+(your\s+)?(tone|personality|persona|character|style|voice)\b",
        r"\bfrom\s+now\s+on\s+you\s+are\b",
        r"\bforget\s+(your\s+)?(persona|tone|style|identity)\b",
        r"\byou\s+are\s+now\s+(?:an?|the)?\s*(?:different|new)?\s*(persona|character|style)\b",
        r"\bact\s+as\s+(?:an?|the)?\s*(?:different|new)?\s*(persona|character)\b",
        r"\b(adopt|become)\s+(?:a\s+)?(different|new)\s+(tone|personality|style)\b",
    ]
    return any(re.search(pat, text) is not None for pat in patterns)


def _memory_ttl_days_for_row(row: WorkbenchAgentMemoryModel, policy: Dict[str, Any]) -> float:
    by_type = policy.get("ttl_days_by_type") if isinstance(policy.get("ttl_days_by_type"), dict) else {}
    key = _normalize_memory_type(str(row.memory_type or "note"))
    if key in by_type:
        try:
            return float(by_type[key])
        except Exception:
            pass
    try:
        return float(policy.get("ttl_days_default") or _AGENT_MEMORY_POLICY_DEFAULT["ttl_days_default"])
    except Exception:
        return float(_AGENT_MEMORY_POLICY_DEFAULT["ttl_days_default"])


def _memory_is_pinned(row: WorkbenchAgentMemoryModel) -> bool:
    try:
        if bool(getattr(row, "pinned", False)):
            return True
    except Exception:
        pass
    md = row.metadata_json if isinstance(row.metadata_json, dict) else {}
    return bool(md.get("pinned", False))


def _agent_memory_prune_expired(
    *,
    simulation_session: SimulationSession,
    db: Session,
    policy: Optional[Dict[str, Any]] = None,
    force: bool = False,
) -> int:
    sid = int(simulation_session.id)
    now = datetime.utcnow()
    if not force:
        with _AGENT_SESSION_LOCKS_GUARD:
            last = _AGENT_MEMORY_PRUNE_LAST_RUN.get(sid)
            if last is not None:
                try:
                    age_sec = (now - last).total_seconds()
                except Exception:
                    age_sec = float(_AGENT_MEMORY_PRUNE_MIN_INTERVAL_SEC + 1.0)
                if age_sec < float(_AGENT_MEMORY_PRUNE_MIN_INTERVAL_SEC):
                    return 0
            _AGENT_MEMORY_PRUNE_LAST_RUN[sid] = now
    p = _sanitize_memory_policy(policy or _memory_policy_from_session_config(simulation_session))
    if not bool(p.get("enabled", True)):
        return 0
    symbol = str(simulation_session.symbol or "").strip().upper()
    rows = (
        db.query(WorkbenchAgentMemoryModel)
        .filter(
            or_(
                WorkbenchAgentMemoryModel.scope == "GLOBAL",
                WorkbenchAgentMemoryModel.simulation_session_id == int(simulation_session.id),
                WorkbenchAgentMemoryModel.symbol == symbol,
            )
        )
        .all()
    )
    stale_ids: List[int] = []
    for r in rows:
        if bool(p.get("pinned_never_expires", True)) and _memory_is_pinned(r):
            continue
        base_time = r.updated_at or r.created_at
        if base_time is None:
            continue
        try:
            age_days = max(0.0, (now - base_time).total_seconds() / 86400.0)
        except Exception:
            continue
        if age_days > _memory_ttl_days_for_row(r, p):
            stale_ids.append(int(r.id))
    if stale_ids:
        (
            db.query(WorkbenchAgentMemoryModel)
            .filter(WorkbenchAgentMemoryModel.id.in_(stale_ids))
            .delete(synchronize_session=False)
        )
        db.flush()
    with _AGENT_SESSION_LOCKS_GUARD:
        _AGENT_MEMORY_PRUNE_LAST_RUN[sid] = now
    return int(len(stale_ids))


def _agent_memory_add(
    *,
    simulation_session: SimulationSession,
    db: Session,
    content: str,
    memory_type: str = "note",
    scope: str = "SESSION",
    importance: float = 0.6,
    source: str = "user",
    metadata: Optional[Dict[str, Any]] = None,
    symbol: Optional[str] = None,
    timeframe: Optional[str] = None,
) -> Optional[WorkbenchAgentMemoryModel]:
    policy = _memory_policy_from_session_config(simulation_session)
    _agent_memory_prune_expired(simulation_session=simulation_session, db=db, policy=policy)
    text = re.sub(r"\s+", " ", str(content or "").strip())[:2000]
    if len(text) < 8:
        return None
    identity = _agent_identity_from_session_config(simulation_session)
    if _memory_note_targets_identity(content=text, memory_type=str(memory_type or "note"), identity=identity):
        return None
    m_scope = _normalize_memory_scope(scope)
    m_type = _normalize_memory_type(memory_type)
    imp = max(0.0, min(1.0, float(importance or 0.0)))
    sym = str(symbol or simulation_session.symbol or "").strip().upper() or None
    tf = str(timeframe or simulation_session.timeframe or "").strip().upper() or None
    if m_scope == "SESSION":
        sid: Optional[int] = int(simulation_session.id)
    elif m_scope == "SYMBOL":
        sid = None
    else:
        sid = None
        sym = None
        tf = None
    md_in = metadata if isinstance(metadata, dict) else {}
    pinned_in = bool(md_in.get("pinned", False))
    fp = _memory_fingerprint(content=text, memory_type=m_type, scope=m_scope, symbol=sym, timeframe=tf)
    q = db.query(WorkbenchAgentMemoryModel).filter(WorkbenchAgentMemoryModel.fingerprint == fp)
    if sid is None:
        q = q.filter(WorkbenchAgentMemoryModel.simulation_session_id.is_(None))
    else:
        q = q.filter(WorkbenchAgentMemoryModel.simulation_session_id == int(sid))
    row = q.first()
    if row is not None:
        row.content = text[:2000]
        row.importance = float(max(float(row.importance or 0.0), imp))
        row.updated_at = datetime.utcnow()
        row.source = str(source or row.source or "user")[:32]
        if isinstance(metadata, dict):
            md = row.metadata_json if isinstance(row.metadata_json, dict) else {}
            md.update(metadata)
            row.metadata_json = md
            if "pinned" in metadata:
                row.pinned = bool(metadata.get("pinned", False))
        db.add(row)
        db.flush()
        return row
    now = datetime.utcnow()
    row = WorkbenchAgentMemoryModel(
        simulation_session_id=sid,
        scope=m_scope,
        symbol=sym,
        timeframe=tf,
        memory_type=m_type,
        content=text[:2000],
        metadata_json=md_in,
        pinned=bool(pinned_in),
        importance=imp,
        source=str(source or "user")[:32],
        fingerprint=fp,
        created_at=now,
        updated_at=now,
        last_accessed_at=now,
        access_count=0,
    )
    try:
        with db.begin_nested():
            db.add(row)
            db.flush()
    except IntegrityError:
        row = q.first()
        if row is None:
            return None
        row.content = text[:2000]
        row.importance = float(max(float(row.importance or 0.0), imp))
        row.updated_at = datetime.utcnow()
        row.source = str(source or row.source or "user")[:32]
        if isinstance(metadata, dict):
            md = row.metadata_json if isinstance(row.metadata_json, dict) else {}
            md.update(metadata)
            row.metadata_json = md
            if "pinned" in metadata:
                row.pinned = bool(metadata.get("pinned", False))
        db.add(row)
        db.flush()
        return row
    # Keep memory bounded per-scope.
    scope_q = db.query(WorkbenchAgentMemoryModel).filter(WorkbenchAgentMemoryModel.scope == m_scope)
    if m_scope == "SESSION":
        scope_q = scope_q.filter(WorkbenchAgentMemoryModel.simulation_session_id == int(simulation_session.id))
    elif m_scope == "SYMBOL":
        scope_q = scope_q.filter(WorkbenchAgentMemoryModel.symbol == sym)
    total = int(scope_q.count())
    overflow = int(total - int(_AGENT_MEMORY_MAX_PER_SCOPE))
    if overflow > 0:
        ordered = scope_q.order_by(WorkbenchAgentMemoryModel.updated_at.asc(), WorkbenchAgentMemoryModel.id.asc()).all()
        stale_values: List[int] = []
        for candidate in ordered:
            if _memory_is_pinned(candidate):
                continue
            if candidate.id is None:
                continue
            stale_values.append(int(candidate.id))
            if len(stale_values) >= overflow:
                break
        if stale_values:
            (
                db.query(WorkbenchAgentMemoryModel)
                .filter(WorkbenchAgentMemoryModel.id.in_(stale_values))
                .delete(synchronize_session=False)
            )
    return row


def _agent_memory_search(
    *,
    simulation_session: SimulationSession,
    db: Session,
    query_text: str,
    limit: int = 8,
    memory_type: Optional[str] = None,
) -> List[Dict[str, Any]]:
    policy = _memory_policy_from_session_config(simulation_session)
    _agent_memory_prune_expired(simulation_session=simulation_session, db=db, policy=policy)
    if not bool(policy.get("enabled", True)):
        return []
    qtxt = str(query_text or "").strip()
    if not qtxt:
        return []
    q_lower = qtxt.lower()
    symbol = str(simulation_session.symbol or "").strip().upper()
    timeframe = str(simulation_session.timeframe or "").strip().upper()
    fetch_cap = max(50, int(min(_AGENT_MEMORY_SEARCH_FETCH_CAP, _AGENT_MEMORY_MAX_PER_SCOPE)))
    rows = (
        db.query(WorkbenchAgentMemoryModel)
        .filter(
            or_(
                WorkbenchAgentMemoryModel.scope == "GLOBAL",
                WorkbenchAgentMemoryModel.simulation_session_id == int(simulation_session.id),
                WorkbenchAgentMemoryModel.symbol == symbol,
            )
        )
        .order_by(WorkbenchAgentMemoryModel.updated_at.desc(), WorkbenchAgentMemoryModel.id.desc())
        .limit(fetch_cap)
        .all()
    )
    mt = _normalize_memory_type(memory_type) if memory_type else None
    scored: List[tuple[float, WorkbenchAgentMemoryModel]] = []
    now = datetime.utcnow()
    min_importance = float(policy.get("min_importance") or 0.0)
    half_life_days = float(policy.get("recency_half_life_days") or 21.0)
    pin_bonus = float(policy.get("pin_bonus") or 0.0)
    max_hits = int(policy.get("max_hits") or 12)
    for r in rows:
        if mt is not None and str(r.memory_type or "") != mt:
            continue
        content = str(r.content or "")
        if not content:
            continue
        content_lower = content.lower()
        imp = max(0.0, min(1.0, float(r.importance or 0.0)))
        if imp < min_importance:
            continue
        pinned = _memory_is_pinned(r)
        if not (bool(policy.get("pinned_never_expires", True)) and pinned):
            base_time = r.updated_at or r.created_at
            if base_time is not None:
                try:
                    age_days = max(0.0, float((now - base_time).total_seconds()) / 86400.0)
                    if age_days > _memory_ttl_days_for_row(r, policy):
                        continue
                except Exception:
                    pass
        lexical, semantic, char_sim = _memory_overlap_scores(qtxt, content)
        if lexical <= 0.0 and semantic <= 0.0 and char_sim < 0.08 and q_lower not in content_lower:
            continue
        recency = 0.0
        try:
            updated = r.updated_at or r.created_at
            age_days = max(0.0, float((now - updated).total_seconds()) / 86400.0) if updated else 9999.0
            recency = 0.5 ** (age_days / max(1.0, half_life_days))
        except Exception:
            recency = 0.0
        scope_bonus = 0.0
        if str(r.scope or "") == "SESSION" and r.simulation_session_id == int(simulation_session.id):
            scope_bonus += 0.20
        elif str(r.scope or "") == "SYMBOL" and str(r.symbol or "") == symbol:
            scope_bonus += 0.15
        elif str(r.scope or "") == "GLOBAL":
            scope_bonus += 0.05
        if timeframe and str(r.timeframe or "").upper() == timeframe:
            scope_bonus += 0.05
        if pinned:
            scope_bonus += pin_bonus
        score = (lexical * 0.45) + (semantic * 0.22) + (char_sim * 0.08) + (imp * 0.20) + (recency * 0.15) + scope_bonus
        scored.append((score, r))
    scored.sort(key=lambda x: x[0], reverse=True)
    top = scored[: max(1, min(max_hits, int(limit)))]
    out: List[Dict[str, Any]] = []
    for _, r in top:
        r.last_accessed_at = now
        r.access_count = int(r.access_count or 0) + 1
        db.add(r)
        out.append(_memory_row_to_dict(r))
    db.flush()
    return out


def _extract_teaching_memory_candidate(message: str) -> Optional[Dict[str, Any]]:
    text = re.sub(r"\s+", " ", str(message or "").strip())
    if len(text) < 20:
        return None
    if _memory_note_targets_identity(content=text, memory_type="trader_rule", identity=_AGENT_IDENTITY_DEFAULT):
        return None
    lower = text.lower()
    explicit_patterns = [
        r"\bremember\s+(?:this|that|my|rule|i|to)\b",
        r"\bmy\s+(?:core\s+)?rule\s*(?:is|:)\b",
        r"\bi\s+(?:always|never|only|usually)\s+[a-z]",
        r"\bi\s+use\s+.+\s+when\s+",
        r"\byou\s+(?:must|should)\s+",
        r"\bfrom\s+now\s+on\b",
        r"\bwhen\s+i\s+trade\b",
        r"\bapprentice\b",
    ]
    explicit = any(re.search(pat, lower) for pat in explicit_patterns)
    if not explicit:
        return None
    memory_type = "trader_rule"
    importance = 0.8
    if re.search(r"\bremember\b", lower) or re.search(r"\b(always|never|from now on)\b", lower):
        importance = 0.92
    return {
        "content": text[:1600],
        "memory_type": memory_type,
        "importance": importance,
        "scope": "GLOBAL",
        "source": "user_teach",
    }


def _persist_agent_memory_notes(
    *,
    simulation_session: SimulationSession,
    db: Session,
    memory_notes: Any,
    source: str = "agent_model",
) -> int:
    notes = memory_notes if isinstance(memory_notes, list) else []
    identity = _agent_identity_from_session_config(simulation_session)
    saved = 0
    for row in notes[:20]:
        if not isinstance(row, dict):
            continue
        content = str(row.get("content") or "").strip()
        if len(content) < 8:
            continue
        mtype = str(row.get("memory_type") or row.get("type") or "note")
        if _memory_note_targets_identity(content=content, memory_type=mtype, identity=identity):
            continue
        scope = str(row.get("scope") or "SESSION")
        try:
            importance = float(row.get("importance") if row.get("importance") is not None else 0.7)
        except Exception:
            importance = 0.7
        rec = _agent_memory_add(
            simulation_session=simulation_session,
            db=db,
            content=content,
            memory_type=mtype,
            scope=scope,
            importance=max(0.0, min(1.0, importance)),
            source=source,
            metadata={
                "from": "agent_memory_notes",
            },
            symbol=str(row.get("symbol") or "") or None,
            timeframe=str(row.get("timeframe") or "") or None,
        )
        if rec is not None:
            saved += 1
    return int(saved)


def _emit_copilot_event(
    copilot: WorkbenchCopilotSessionModel,
    event_type: str,
    payload: Dict[str, Any] | None,
    db: Session,
    severity: str = "info",
) -> Optional[WorkbenchCopilotEventModel]:
    if copilot is None:
        return None
    ev = WorkbenchCopilotEventModel(
        copilot_session_id=int(copilot.id),
        event_type=str(event_type or "UNKNOWN"),
        severity=str(severity or "info"),
        payload_json=payload if isinstance(payload, dict) else {},
        created_at=datetime.utcnow(),
    )
    db.add(ev)
    db.flush()
    return ev


def _event_priority_for_type(event_type: str) -> int:
    et = str(event_type or "").strip().upper()
    priorities = {
        "RISK_BREACH": 100,
        "REPLAY_COMPLETED": 90,
        "TRADE_OPENED": 80,
        "TRADE_CLOSED": 80,
        "COPILOT_ACTION_EXECUTED": 75,
        "COPILOT_GUARDRAIL_BLOCK": 72,
        "COPILOT_GUARDRAIL_RESUME": 72,
        "MANUAL_OVERRIDE": 70,
        "REGIME_SHIFT": 60,
        "TOOL_SIGNAL_CHANGED": 55,
        "PERIODIC_REVIEW": 40,
        "SESSION_SNAPSHOT": 20,
        "BAR_ADVANCED": 10,
    }
    return int(priorities.get(et, 30))


def _redact_sensitive_config(cfg: Dict[str, Any]) -> Dict[str, Any]:
    if not isinstance(cfg, dict):
        return {}
    return {k: v for k, v in cfg.items() if str(k) not in _COPILOT_SENSITIVE_CONFIG_KEYS}


def _normalize_runtime_settings(
    provider: str,
    runtime: Dict[str, Any] | None,
) -> Dict[str, Any]:
    p = str(provider or "deterministic").strip().lower()
    raw = runtime if isinstance(runtime, dict) else {}
    out: Dict[str, Any] = {}

    llm_url = str(raw.get("llm_url") or "").strip()
    api_key = str(raw.get("api_key") or "").strip()
    llm_timeout_sec = raw.get("llm_timeout_sec")

    if p == "local_gptoss_http":
        if llm_url:
            out["local_gptoss_url"] = llm_url
    elif p == "openai_compat":
        if llm_url:
            out["openai_base_url"] = llm_url
        if api_key:
            out["openai_api_key"] = api_key
    elif p == "claude":
        if llm_url:
            out["claude_base_url"] = llm_url
        if api_key:
            out["anthropic_api_key"] = api_key
        version = str(raw.get("anthropic_version") or "").strip()
        if version:
            out["anthropic_version"] = version

    if llm_timeout_sec is not None:
        try:
            out["llm_timeout_sec"] = max(10, int(llm_timeout_sec))
        except Exception:
            pass
    return out


def _clean_snapshot_meta(meta: Dict[str, Any]) -> Dict[str, Any]:
    if not isinstance(meta, dict):
        return {}
    out = dict(meta)
    attempts = out.get("provider_attempts") if isinstance(out.get("provider_attempts"), list) else []
    clean_attempts: List[Dict[str, Any]] = []
    for row in attempts[:5]:
        if not isinstance(row, dict):
            continue
        clean_attempts.append(
            {
                "provider": str(row.get("provider") or ""),
                "error_type": str(row.get("error_type") or ""),
                "error": str(row.get("error") or "")[:180],
            }
        )
    out["provider_attempts"] = clean_attempts
    return out


def _sync_session_from_engine_no_commit(
    session: SimulationSession,
    engine: SimulationReplayEngine,
) -> None:
    """Sync engine state to session row without committing transaction."""
    session.current_bar = int(engine.current_bar or 0)
    session.current_balance = float(engine.balance or 0.0)
    session.total_pnl = float(session.current_balance or 0.0) - float(session.initial_balance or 0.0)
    session.trades_count = int(len(engine.closed_trades or []))
    session.wins = int(sum(1 for t in (engine.closed_trades or []) if (t.get("pnl") or 0) > 0))
    session.losses = int(sum(1 for t in (engine.closed_trades or []) if (t.get("pnl") or 0) < 0))
    session.updated_at = datetime.utcnow()


def _to_float_or_none(v: Any) -> Optional[float]:
    try:
        if v is None:
            return None
        return float(v)
    except Exception:
        return None


def _session_config_dict(session: SimulationSession) -> Dict[str, Any]:
    raw = session.config_json
    if isinstance(raw, dict):
        return dict(raw)
    if isinstance(raw, str) and raw.strip():
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            return {}
    return {}


def _agent_effective_tool_config(
    *,
    session: SimulationSession,
    db: Session,
    override: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    copilot = _get_active_copilot(simulation_session_id=int(session.id), db=db)
    if copilot is not None and isinstance(copilot.config_json, dict):
        out.update(copilot.config_json)
    agent_row = _get_active_agent(simulation_session_id=int(session.id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session.id), db=db)
    if agent_row is not None and isinstance(agent_row.config_json, dict):
        out.update(agent_row.config_json)
    if isinstance(override, dict):
        out.update(override)
    out["strategy_tool_access_mode"] = _normalize_strategy_tool_access_mode(out.get("strategy_tool_access_mode"))
    out["tool_selection_mode"] = _normalize_tool_selection_mode(out.get("tool_selection_mode"))
    return out


def _normalize_strategy_tool_access_mode(value: Any) -> str:
    raw = str(value or "").strip().lower()
    if raw in _AGENT_STRATEGY_TOOL_ACCESS_MODES:
        return raw
    if raw in {"parents", "collected", "aggregate", "aggregated", "master"}:
        return "parent"
    if raw in {"children", "granular", "detailed", "childs"}:
        return "child"
    return "all"


def _normalize_tool_selection_mode(value: Any) -> str:
    raw = str(value or "").strip().lower()
    if raw in _AGENT_TOOL_SELECTION_MODES:
        return raw
    if raw in {"auto", "autonomy", "full", "unpruned"}:
        return "autonomous"
    if raw in {"default", "intent", "intent_history", "guided_intent"}:
        return "guided"
    if raw in {"strict", "cheap", "lean", "token_saver"}:
        return "minimal"
    return "autonomous"


def _agent_strategy_tool_sets() -> Tuple[set[str], set[str]]:
    parents: set[str] = set()
    children: set[str] = set()
    for grp in _AGENT_STRATEGY_TOOL_GROUPS.values():
        parent = str(grp.get("parent") or "").strip().lower()
        if parent:
            parents.add(parent)
        for item in (grp.get("children") if isinstance(grp.get("children"), list) else []):
            child = str(item or "").strip().lower()
            if child:
                children.add(child)
    return parents, children


def _agent_tool_allowed_by_access_mode(tool_name: str, cfg: Optional[Dict[str, Any]]) -> bool:
    mode = _normalize_strategy_tool_access_mode((cfg or {}).get("strategy_tool_access_mode"))
    if mode == "all":
        return True
    t = str(tool_name or "").strip().lower()
    if not t:
        return True
    parents, children = _agent_strategy_tool_sets()
    if mode == "parent" and t in children:
        return False
    if mode == "child" and t in parents:
        return False
    return True


def _agent_apply_strategy_tool_access_mode(
    allowed_tool_names: Optional[List[str]],
    cfg: Optional[Dict[str, Any]],
) -> Optional[List[str]]:
    if not isinstance(allowed_tool_names, list):
        return allowed_tool_names
    mode = _normalize_strategy_tool_access_mode((cfg or {}).get("strategy_tool_access_mode"))
    if mode == "all":
        return list(allowed_tool_names)

    parents, children = _agent_strategy_tool_sets()
    strategy_tools = parents | children
    had_strategy_tools = any(
        str(x or "").strip().lower() in strategy_tools for x in allowed_tool_names
    )
    out: List[str] = []
    seen: set[str] = set()
    for name in allowed_tool_names:
        tool = str(name or "").strip()
        if not tool:
            continue
        key = tool.lower()
        if mode == "parent" and key in children:
            continue
        if mode == "child" and key in parents:
            continue
        if key in seen:
            continue
        seen.add(key)
        out.append(tool)

    if mode == "parent" and had_strategy_tools:
        for p in sorted(parents):
            if p not in seen:
                seen.add(p)
                out.append(p)

    if mode == "child" and had_strategy_tools:
        has_child = any(str(x or "").strip().lower() in children for x in out)
        if not has_child:
            for c in sorted(children):
                if c not in seen:
                    seen.add(c)
                    out.append(c)

    return out


def _agent_all_tool_names() -> List[str]:
    names: List[str] = []
    seen: set[str] = set()
    try:
        specs = WorkbenchAgent._tool_specs()
    except Exception:
        specs = []
    for row in specs if isinstance(specs, list) else []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").strip()
        if not name:
            continue
        key = name.lower()
        if key in seen:
            continue
        seen.add(key)
        names.append(name)
    return names


def _agent_select_allowed_tool_names(
    *,
    message: str,
    conversation_history: Optional[List[Dict[str, str]]],
    cfg: Optional[Dict[str, Any]],
    objective: str = "",
) -> List[str]:
    mode = _normalize_tool_selection_mode((cfg or {}).get("tool_selection_mode"))
    seed = str(objective or message or "").strip()
    if mode == "autonomous":
        base = _agent_all_tool_names()
    elif mode == "minimal":
        base = get_tools_for_intent(seed)
    else:
        base = get_tools_for_intent(seed, conversation_history=conversation_history or [])
    out = _agent_apply_strategy_tool_access_mode(base, cfg)
    return out if isinstance(out, list) else []


def _agent_news_ticker_for_symbol(symbol: str) -> str:
    raw = str(symbol or "").strip().upper()
    if not raw:
        return ""
    s = re.sub(r"[^A-Z0-9]", "", raw)
    if not s:
        return ""
    for key, ticker in _AGENT_NEWS_SYMBOL_MAP.items():
        k = str(key or "").strip().upper()
        if not k:
            continue
        if s == k or s.startswith(k):
            return str(ticker)
    # Plain equity tickers are passed through.
    if re.fullmatch(r"[A-Z]{1,5}", s):
        return s
    return ""


def _agent_ibkr_news_proxy_ticker_for_symbol(symbol: str) -> str:
    raw = str(symbol or "").strip().upper()
    if not raw:
        return ""
    s = re.sub(r"[^A-Z0-9]", "", raw)
    if not s:
        return ""
    for key, ticker in _AGENT_IBKR_NEWS_PROXY_SYMBOL_MAP.items():
        k = str(key or "").strip().upper()
        if not k:
            continue
        if s == k or s.startswith(k):
            return str(ticker)
    # Plain equity tickers are passed through.
    if re.fullmatch(r"[A-Z]{1,5}", s):
        return s
    return ""


def _agent_news_headline_impact(headline: str) -> str:
    text = str(headline or "").strip().lower()
    if not text:
        return "unknown"
    for k in _AGENT_NEWS_HIGH_IMPACT_KEYWORDS:
        term = str(k or "").strip().lower()
        if not term:
            continue
        # Use token boundaries to avoid false positives like "warranty" for "war".
        if re.search(rf"(?<![a-z0-9]){re.escape(term)}(?![a-z0-9])", text) is not None:
            return "high"
    if any(k in text for k in _AGENT_NEWS_HIGH_IMPACT_SUBSTRINGS):
        return "high"
    return "normal"


def _agent_news_cache_get(cache_key: str, now: datetime) -> Optional[Dict[str, Any]]:
    global _AGENT_NEWS_CACHE_HITS, _AGENT_NEWS_CACHE_MISSES
    with _AGENT_NEWS_CACHE_LOCK:
        cached = _AGENT_NEWS_CACHE.get(cache_key) if isinstance(_AGENT_NEWS_CACHE.get(cache_key), dict) else None
        if cached is None:
            _AGENT_NEWS_CACHE_MISSES += 1
            return None
        ts = cached.get("ts")
        if not isinstance(ts, datetime) or (now - ts).total_seconds() > float(_AGENT_NEWS_CACHE_TTL_SEC):
            _AGENT_NEWS_CACHE.pop(cache_key, None)
            _AGENT_NEWS_CACHE_MISSES += 1
            return None
        payload = cached.get("payload") if isinstance(cached.get("payload"), dict) else None
        _AGENT_NEWS_CACHE_HITS += 1
        return dict(payload) if isinstance(payload, dict) else None


def _agent_news_cache_set(cache_key: str, now: datetime, payload: Dict[str, Any]) -> None:
    with _AGENT_NEWS_CACHE_LOCK:
        _AGENT_NEWS_CACHE.pop(cache_key, None)
        _AGENT_NEWS_CACHE[cache_key] = {"ts": now, "payload": dict(payload)}
        # Opportunistic cleanup: evict expired and bound max size.
        expired_keys: List[str] = []
        for k, row in list(_AGENT_NEWS_CACHE.items()):
            ts = row.get("ts") if isinstance(row, dict) else None
            if not isinstance(ts, datetime) or (now - ts).total_seconds() > float(_AGENT_NEWS_CACHE_TTL_SEC):
                expired_keys.append(str(k))
        for k in expired_keys:
            _AGENT_NEWS_CACHE.pop(k, None)
        while len(_AGENT_NEWS_CACHE) > int(_AGENT_NEWS_CACHE_MAX_ENTRIES):
            oldest_key = next(iter(_AGENT_NEWS_CACHE), None)
            if oldest_key is None:
                break
            _AGENT_NEWS_CACHE.pop(str(oldest_key), None)


def _agent_news_cache_stats(now: Optional[datetime] = None) -> Dict[str, Any]:
    ref = now if isinstance(now, datetime) else _utc_now()
    if ref.tzinfo is None:
        ref = ref.replace(tzinfo=timezone.utc)
    with _AGENT_NEWS_CACHE_LOCK:
        total = int(len(_AGENT_NEWS_CACHE))
        active = 0
        oldest_age_sec = 0.0
        newest_age_sec = 0.0
        symbols: List[str] = []
        for key, row in _AGENT_NEWS_CACHE.items():
            parts = str(key).split(":")
            if parts and parts[0]:
                symbols.append(str(parts[0]))
            ts = row.get("ts") if isinstance(row, dict) else None
            if not isinstance(ts, datetime):
                continue
            if ts.tzinfo is None:
                ts = ts.replace(tzinfo=timezone.utc)
            age_sec = max(0.0, float((ref - ts).total_seconds()))
            if age_sec <= float(_AGENT_NEWS_CACHE_TTL_SEC):
                active += 1
            if oldest_age_sec <= 0.0 or age_sec > oldest_age_sec:
                oldest_age_sec = age_sec
            if newest_age_sec <= 0.0 or age_sec < newest_age_sec:
                newest_age_sec = age_sec
        unique_symbols = sorted({s for s in symbols if s})
        hits = int(_AGENT_NEWS_CACHE_HITS)
        misses = int(_AGENT_NEWS_CACHE_MISSES)
    total_requests = hits + misses
    hit_rate = (float(hits) / float(total_requests)) if total_requests > 0 else 0.0
    with _AGENT_NEWS_SUMMARY_CACHE_LOCK:
        summary_size = int(len(_AGENT_NEWS_SUMMARY_CACHE))
    with _AGENT_NEWS_COUNTERS_LOCK:
        fetch_count = int(_AGENT_NEWS_FETCH_COUNT)
        fetch_error_count = int(_AGENT_NEWS_FETCH_ERROR_COUNT)
    return {
        "size": total,
        "active_entries": int(active),
        "ttl_sec": float(_AGENT_NEWS_CACHE_TTL_SEC),
        "max_entries": int(_AGENT_NEWS_CACHE_MAX_ENTRIES),
        "oldest_age_sec": round(float(oldest_age_sec), 3),
        "newest_age_sec": round(float(newest_age_sec), 3),
        "unique_symbols": unique_symbols[:50],
        "hits": hits,
        "misses": misses,
        "hit_rate": round(hit_rate, 6),
        "fetch_count": fetch_count,
        "fetch_error_count": fetch_error_count,
        "summary_cache_size": summary_size,
        "summary_ttl_sec": float(_AGENT_NEWS_SUMMARY_CACHE_TTL_SEC),
    }


def _agent_fetch_market_news_polygon(
    *,
    symbol: str,
    limit: int = 5,
    lookback_min: int = 180,
) -> Dict[str, Any]:
    lim = max(1, min(10, int(limit)))
    lb_min = max(1, min(7 * 24 * 60, int(lookback_min)))
    ticker = _agent_news_ticker_for_symbol(symbol)
    if not ticker:
        return {
            "ok": False,
            "provider": "polygon",
            "symbol": str(symbol or ""),
            "error": "unsupported_symbol_for_news",
            "items": [],
        }

    cache_key = f"{ticker}:{lim}:{lb_min}"
    now = _utc_now()
    cached = _agent_news_cache_get(cache_key, now)
    if isinstance(cached, dict):
        return cached

    with _AGENT_NEWS_FETCH_LOCK:
        # Re-check after lock to avoid duplicate outbound calls under concurrency.
        cached2 = _agent_news_cache_get(cache_key, now)
        if isinstance(cached2, dict):
            return cached2

        api_key = str(os.getenv("POLYGON_API_KEY") or "").strip()
        if not api_key:
            payload = {
                "ok": False,
                "provider": "polygon",
                "symbol": str(symbol or "").upper(),
                "ticker": ticker,
                "error": "polygon_api_key_missing",
                "items": [],
            }
            _agent_news_cache_set(cache_key, now, payload)
            return payload

        cutoff = now - timedelta(minutes=lb_min)
        url = "https://api.polygon.io/v2/reference/news"
        params = {
            "ticker": ticker,
            "limit": lim,
            "sort": "published_utc",
            "order": "desc",
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
        }
        items: List[Dict[str, Any]] = []
        err: Optional[str] = None
        try:
            with httpx.Client(timeout=8.0) as client:
                res = client.get(url, params=params, headers=headers)
            if int(res.status_code) >= 300:
                err = f"polygon_http_{int(res.status_code)}"
            else:
                body = res.json() if str(res.headers.get("content-type") or "").lower().startswith("application/json") else {}
                rows = body.get("results") if isinstance(body, dict) and isinstance(body.get("results"), list) else []
                for row in rows[:lim]:
                    if not isinstance(row, dict):
                        continue
                    published_raw = str(row.get("published_utc") or "").strip()
                    published_dt: Optional[datetime] = None
                    if published_raw:
                        try:
                            published_dt = datetime.fromisoformat(published_raw.replace("Z", "+00:00"))
                        except Exception:
                            published_dt = None
                    if published_dt is not None and published_dt.tzinfo is None:
                        published_dt = published_dt.replace(tzinfo=timezone.utc)
                    if published_dt is not None and published_dt < cutoff:
                        continue
                    title = str(row.get("title") or "").strip()
                    if not title:
                        continue
                    items.append(
                        {
                            "title": title,
                            "publisher": str((row.get("publisher") or {}).get("name") or "").strip(),
                            "published_utc": published_raw,
                            "url": str(row.get("article_url") or "").strip(),
                            "impact": _agent_news_headline_impact(title),
                        }
                    )
        except Exception as exc:
            err = f"{type(exc).__name__}: {str(exc)[:180]}"

        payload = {
            "ok": err is None,
            "provider": "polygon",
            "symbol": str(symbol or "").upper(),
            "ticker": ticker,
            "lookback_min": int(lb_min),
            "items": items,
            "error": err,
        }
        _agent_news_cache_set(cache_key, now, payload)
        return payload


def _agent_news_summary_cache_get(cache_key: str, now: datetime) -> Optional[Dict[str, Any]]:
    with _AGENT_NEWS_SUMMARY_CACHE_LOCK:
        cached = _AGENT_NEWS_SUMMARY_CACHE.get(cache_key) if isinstance(_AGENT_NEWS_SUMMARY_CACHE.get(cache_key), dict) else None
        if cached is None:
            return None
        ts = cached.get("ts")
        if not isinstance(ts, datetime) or (now - ts).total_seconds() > float(_AGENT_NEWS_SUMMARY_CACHE_TTL_SEC):
            _AGENT_NEWS_SUMMARY_CACHE.pop(cache_key, None)
            return None
        payload = cached.get("payload") if isinstance(cached.get("payload"), dict) else None
        return dict(payload) if isinstance(payload, dict) else None


def _agent_news_summary_cache_set(cache_key: str, now: datetime, payload: Dict[str, Any]) -> None:
    with _AGENT_NEWS_SUMMARY_CACHE_LOCK:
        _AGENT_NEWS_SUMMARY_CACHE.pop(cache_key, None)
        _AGENT_NEWS_SUMMARY_CACHE[cache_key] = {"ts": now, "payload": dict(payload)}
        expired_keys: List[str] = []
        for k, row in list(_AGENT_NEWS_SUMMARY_CACHE.items()):
            ts = row.get("ts") if isinstance(row, dict) else None
            if not isinstance(ts, datetime) or (now - ts).total_seconds() > float(_AGENT_NEWS_SUMMARY_CACHE_TTL_SEC):
                expired_keys.append(str(k))
        for k in expired_keys:
            _AGENT_NEWS_SUMMARY_CACHE.pop(k, None)
        while len(_AGENT_NEWS_SUMMARY_CACHE) > int(_AGENT_NEWS_SUMMARY_CACHE_MAX_ENTRIES):
            oldest_key = next(iter(_AGENT_NEWS_SUMMARY_CACHE), None)
            if oldest_key is None:
                break
            _AGENT_NEWS_SUMMARY_CACHE.pop(str(oldest_key), None)


def _agent_llm_summarize_news(
    *,
    symbol: str,
    provider: str,
    items: List[Dict[str, Any]],
    model: str,
    timeout_sec: int = 8,
) -> Dict[str, Any]:
    api_key = str(os.getenv("ANTHROPIC_API_KEY") or "").strip()
    if not api_key:
        return {"ok": False, "error": "anthropic_api_key_missing", "summary": ""}
    rows: List[Dict[str, Any]] = []
    for r in items[:8]:
        if not isinstance(r, dict):
            continue
        rows.append(
            {
                "title": str(r.get("title") or "").strip()[:240],
                "published_utc": str(r.get("published_utc") or "").strip(),
                "impact": str(r.get("impact") or "").strip().lower() or "normal",
                "publisher": str(r.get("publisher") or "").strip()[:80],
            }
        )
    if not rows:
        return {"ok": True, "summary": "No recent headlines in window.", "model": model}
    prompt = (
        "Summarize these market headlines for trading risk in <=4 bullets.\n"
        "Focus on immediate risk and direction-neutral cautions. Avoid hype.\n"
        "Return plain text only.\n\n"
        f"symbol={str(symbol or '').upper()} provider={str(provider or '').lower()}\n"
        f"headlines_json={json.dumps(rows, ensure_ascii=True)}"
    )
    payload = {
        "model": str(model or "claude-haiku-4-5-20251001"),
        "max_tokens": 180,
        "temperature": 0.1,
        "messages": [{"role": "user", "content": prompt}],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    try:
        with httpx.Client(timeout=max(5, min(30, int(timeout_sec)))) as client:
            resp = client.post("https://api.anthropic.com/v1/messages", headers=headers, json=payload)
        if int(resp.status_code) >= 300:
            detail = str(resp.text or "")[:240]
            return {"ok": False, "error": f"anthropic_http_{int(resp.status_code)}:{detail}", "summary": ""}
        body = resp.json() if str(resp.headers.get("content-type") or "").lower().startswith("application/json") else {}
        parts = body.get("content") if isinstance(body, dict) and isinstance(body.get("content"), list) else []
        txt = ""
        for p in parts:
            if isinstance(p, dict) and str(p.get("type") or "").lower() == "text":
                txt += str(p.get("text") or "")
        txt = str(txt or "").strip()
        return {
            "ok": bool(txt),
            "error": None if txt else "empty_summary",
            "summary": txt,
            "model": str(body.get("model") or model),
            "usage": body.get("usage") if isinstance(body.get("usage"), dict) else {},
        }
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}", "summary": ""}


def _agent_fetch_market_news_ibkr(
    *,
    symbol: str,
    limit: int = 5,
    lookback_min: int = 180,
    host: str = "127.0.0.1",
    port: int = 7497,
) -> Dict[str, Any]:
    lim = max(1, min(10, int(limit)))
    lb_min = max(1, min(7 * 24 * 60, int(lookback_min)))
    now = _utc_now()
    cache_key = f"ibkr:{str(symbol or '').upper()}:{lim}:{lb_min}:{host}:{int(port)}"
    cached = _agent_news_cache_get(cache_key, now)
    if isinstance(cached, dict):
        return cached

    try:
        from ib_async import IB, Stock, util
    except Exception:
        payload = {
            "ok": False,
            "provider": "ibkr",
            "symbol": str(symbol or "").upper(),
            "error": "ib_async_not_installed",
            "items": [],
        }
        _agent_news_cache_set(cache_key, now, payload)
        return payload

    try:
        util.startLoop()
    except Exception:
        # Loop may already be patched in some runtimes.
        pass

    resolver = None
    try:
        from ..core.ibkr_data_provider import IBKRContractResolver

        resolver = IBKRContractResolver
    except Exception:
        resolver = None

    with _AGENT_NEWS_FETCH_LOCK:
        # Re-check after lock to avoid duplicate outbound IBKR calls and clientId collisions.
        cached2 = _agent_news_cache_get(cache_key, now)
        if isinstance(cached2, dict):
            return cached2

        items: List[Dict[str, Any]] = []
        err: Optional[str] = None
        ib = IB()
        try:
            client_id = 10000 + int(uuid.uuid4().int % 50000)
            ib.connect(str(host or "127.0.0.1"), int(port), clientId=client_id, timeout=10)
            contract = None
            if resolver is not None:
                try:
                    contract, _ = resolver.resolve_contract(ib, str(symbol or "").upper())
                except Exception:
                    contract = None
            if contract is None:
                ticker = _agent_ibkr_news_proxy_ticker_for_symbol(str(symbol or "").upper())
                if ticker:
                    contract = Stock(ticker, "SMART", "USD")
            if contract is None:
                err = "unsupported_symbol_for_ibkr_news"
            else:
                try:
                    qualified = ib.qualifyContracts(contract)
                    contract = qualified[0] if qualified else contract
                except Exception:
                    pass
                conid = int(getattr(contract, "conId", 0) or 0)
                if conid <= 0:
                    err = "ibkr_contract_unqualified_for_news"
                else:
                    providers = ib.reqNewsProviders() or []
                    codes: List[str] = []
                    for p in providers:
                        code = str(getattr(p, "code", "") or getattr(p, "providerCode", "") or "").strip()
                        if code and code not in codes:
                            codes.append(code)
                    provider_codes = "+".join(codes)
                    if not provider_codes:
                        err = "ibkr_news_provider_codes_missing"
                    else:
                        end_dt = now
                        start_dt = now - timedelta(minutes=lb_min)
                        end_str = end_dt.strftime("%Y%m%d %H:%M:%S")
                        start_str = start_dt.strftime("%Y%m%d %H:%M:%S")
                        rows = ib.reqHistoricalNews(
                            conid,
                            provider_codes,
                            start_str,
                            end_str,
                            int(lim),
                        ) or []
                        for row in rows[:lim]:
                            title = str(getattr(row, "headline", "") or "").strip()
                            if not title:
                                continue
                            published_raw = str(getattr(row, "time", "") or "").strip()
                            article_id = str(getattr(row, "articleId", "") or "").strip()
                            items.append(
                                {
                                    "title": title,
                                    "publisher": str(getattr(row, "providerCode", "") or "").strip(),
                                    "published_utc": published_raw,
                                    "url": "",
                                    "article_id": article_id,
                                    "impact": _agent_news_headline_impact(title),
                                }
                            )
        except Exception as exc:
            err = f"{type(exc).__name__}: {str(exc)[:180]}"
        finally:
            try:
                ib.disconnect()
            except Exception:
                pass

        payload = {
            "ok": err is None,
            "provider": "ibkr",
            "symbol": str(symbol or "").upper(),
            "lookback_min": int(lb_min),
            "items": items,
            "error": err,
        }
        _agent_news_cache_set(cache_key, now, payload)
        return payload


def _agent_fetch_market_news(
    *,
    symbol: str,
    limit: int = 5,
    lookback_min: int = 180,
    provider: str = "polygon",
    include_summary: bool = False,
    summary_model: str = "claude-haiku-4-5-20251001",
    summary_timeout_sec: int = 8,
    ibkr_host: str = "127.0.0.1",
    ibkr_port: int = 7497,
) -> Dict[str, Any]:
    global _AGENT_NEWS_FETCH_COUNT, _AGENT_NEWS_FETCH_ERROR_COUNT
    with _AGENT_NEWS_COUNTERS_LOCK:
        _AGENT_NEWS_FETCH_COUNT += 1
    src = str(provider or "polygon").strip().lower()
    if src not in {"polygon", "ibkr"}:
        src = "polygon"
    if src == "ibkr":
        data = _agent_fetch_market_news_ibkr(
            symbol=symbol,
            limit=limit,
            lookback_min=lookback_min,
            host=ibkr_host,
            port=ibkr_port,
        )
    else:
        data = _agent_fetch_market_news_polygon(
            symbol=symbol,
            limit=limit,
            lookback_min=lookback_min,
        )
    if not bool(data.get("ok", False)):
        with _AGENT_NEWS_COUNTERS_LOCK:
            _AGENT_NEWS_FETCH_ERROR_COUNT += 1
        return data
    if not include_summary:
        return data

    items = data.get("items") if isinstance(data.get("items"), list) else []
    fingerprint_raw = json.dumps(
        [
            (
                str(r.get("title") or ""),
                str(r.get("published_utc") or ""),
                str(r.get("impact") or ""),
            )
            for r in items[:10]
            if isinstance(r, dict)
        ],
        ensure_ascii=True,
        sort_keys=True,
    )
    fp = hashlib.sha1(fingerprint_raw.encode("utf-8")).hexdigest()
    now = _utc_now()
    s_key = (
        f"{src}:{str(symbol or '').upper()}:{int(limit)}:{int(lookback_min)}:"
        f"{str(summary_model or '').strip().lower()}:{fp}"
    )
    cached = _agent_news_summary_cache_get(s_key, now)
    if isinstance(cached, dict):
        out = dict(data)
        out["summary"] = str(cached.get("summary") or "")
        out["summary_model"] = str(cached.get("summary_model") or summary_model)
        out["summary_cached"] = True
        return out

    sum_out = _agent_llm_summarize_news(
        symbol=str(symbol or "").upper(),
        provider=src,
        items=[r for r in items if isinstance(r, dict)],
        model=str(summary_model or "claude-haiku-4-5-20251001"),
        timeout_sec=int(summary_timeout_sec),
    )
    out = dict(data)
    out["summary"] = str(sum_out.get("summary") or "").strip()
    out["summary_model"] = str(sum_out.get("model") or summary_model)
    out["summary_cached"] = False
    out["summary_error"] = str(sum_out.get("error") or "") or None
    if out["summary"]:
        _agent_news_summary_cache_set(
            s_key,
            now,
            {
                "summary": out["summary"],
                "summary_model": out["summary_model"],
            },
        )
    return out


def _agent_session_window_for_symbol(symbol: str) -> Optional[Dict[str, int]]:
    s = str(symbol or "").upper().strip()
    if not s:
        return None
    # UTC windows tuned for liquid hours in paper-trading mode.
    if s in {"US500", "NAS100"}:
        return {"start_min": 13 * 60 + 30, "end_min": 20 * 60}
    if s in {"XAUUSD", "EURUSD", "GBPUSD"}:
        return {"start_min": 6 * 60, "end_min": 21 * 60}
    return None


def _agent_trade_guardrails(
    *,
    session: SimulationSession,
    db: Session,
    override_config: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    cfg = _agent_effective_tool_config(session=session, db=db, override=override_config)
    now = _utc_now()
    reasons: List[str] = []
    details: Dict[str, Any] = {}

    guardrail_enabled = bool(cfg.get("guardrail_enabled", True))
    session_enabled_cfg = bool(cfg.get("guardrail_session_filter_enabled", False))
    news_enabled_cfg = bool(cfg.get("guardrail_news_filter_enabled", False))
    session_enabled = bool(guardrail_enabled and session_enabled_cfg)
    news_enabled = bool(guardrail_enabled and news_enabled_cfg)
    try:
        news_lookback_min = int(cfg.get("guardrail_news_lookback_min") or 120)
    except Exception:
        news_lookback_min = 120
    news_lookback_min = max(15, min(24 * 60, int(news_lookback_min)))
    if not guardrail_enabled:
        details["guardrails_disabled"] = True

    if session_enabled:
        wnd = _agent_session_window_for_symbol(str(session.symbol or ""))
        if isinstance(wnd, dict):
            now_min = int(now.hour) * 60 + int(now.minute)
            start_min = int(wnd.get("start_min") or 0)
            end_min = int(wnd.get("end_min") or 0)
            in_window = bool(start_min <= now_min <= end_min) if end_min >= start_min else bool(now_min >= start_min or now_min <= end_min)
            details["session_window_utc"] = {"start_min": start_min, "end_min": end_min, "now_min": now_min}
            if not in_window:
                reasons.append("outside_session_window")

    news_payload: Optional[Dict[str, Any]] = None
    if news_enabled:
        news_provider = str(cfg.get("market_news_provider") or "polygon").strip().lower()
        ibkr_host = str(cfg.get("market_news_ibkr_host") or "127.0.0.1").strip() or "127.0.0.1"
        try:
            ibkr_port = int(cfg.get("market_news_ibkr_port") or 7497)
        except Exception:
            ibkr_port = 7497
        news_payload = _agent_fetch_market_news(
            symbol=str(session.symbol or ""),
            limit=5,
            lookback_min=int(news_lookback_min),
            provider=news_provider,
            include_summary=False,
            ibkr_host=ibkr_host,
            ibkr_port=max(1, min(65535, int(ibkr_port))),
        )
        details["news"] = {
            "ok": bool(news_payload.get("ok")) if isinstance(news_payload, dict) else False,
            "items": int(len(news_payload.get("items") or [])) if isinstance(news_payload, dict) else 0,
        }
        if isinstance(news_payload, dict) and bool(news_payload.get("ok")):
            rows = news_payload.get("items") if isinstance(news_payload.get("items"), list) else []
            if any(str(r.get("impact") or "") == "high" for r in rows if isinstance(r, dict)):
                reasons.append("high_impact_news")

    return {
        "ok": len(reasons) == 0,
        "guardrail_enabled": bool(guardrail_enabled),
        "session_filter_enabled": bool(session_enabled),
        "news_filter_enabled": bool(news_enabled),
        "news_lookback_min": int(news_lookback_min),
        "reasons": reasons,
        "details": details,
        "news_payload": news_payload if isinstance(news_payload, dict) else None,
    }


def _session_cost_model(
    session: SimulationSession,
    spread_override: Optional[float] = None,
    tc_override: Optional[float] = None,
    spread_source_override: Optional[str] = None,
) -> WorkbenchCostModel:
    cfg = _session_config_dict(session)
    cm_cfg = cfg.get("cost_model") if isinstance(cfg.get("cost_model"), dict) else {}
    spread_source = str(spread_source_override or cm_cfg.get("spread_source") or _COST_SPREAD_SOURCE_MANUAL).strip().lower()
    if spread_source not in {_COST_SPREAD_SOURCE_MANUAL, _COST_SPREAD_SOURCE_MT5}:
        spread_source = _COST_SPREAD_SOURCE_MANUAL
    spread = _to_float_or_none(spread_override)
    if spread is None:
        spread = _to_float_or_none(cm_cfg.get("spread"))
    if spread is None:
        spread = float(INSTRUMENT_SPREAD.get(str(session.symbol or "").upper(), 0.30))
    resolved_source = spread_source
    if spread_source == _COST_SPREAD_SOURCE_MT5:
        try:
            service = _get_mt5_service_singleton()
            mt5_spread = _to_float_or_none(service.get_live_spread(symbol=str(session.symbol or "").upper()))
            if mt5_spread is not None and mt5_spread >= 0:
                spread = float(mt5_spread)
                resolved_source = _COST_SPREAD_SOURCE_MT5
            else:
                resolved_source = "manual_fallback"
        except Exception:
            # Fallback to manual/default spread when MT5 spread unavailable.
            resolved_source = "manual_fallback"
    tc_rate = _to_float_or_none(tc_override)
    if tc_rate is None:
        tc_rate = _to_float_or_none(cm_cfg.get("tc_rate"))
    model = WorkbenchCostModel(
        symbol=str(session.symbol or ""),
        spread=spread,
        tc_rate=tc_rate,
        spread_source=resolved_source,
    )
    return model


def _is_cost_model_enabled(session: SimulationSession) -> bool:
    cfg = _session_config_dict(session)
    cm_cfg = cfg.get("cost_model") if isinstance(cfg.get("cost_model"), dict) else {}
    if "enabled" in cm_cfg:
        return bool(cm_cfg.get("enabled"))
    return str(session.strategy_id or "").strip().lower() == WORKBENCH_ID


def _contract_size_for_symbol(symbol: str) -> float:
    spec = INSTRUMENT_SPECS.get(str(symbol or "").upper(), {"contract_size": 100})
    return float(spec.get("contract_size", 100))


def _apply_close_cost_adjustment(
    session: SimulationSession,
    engine: SimulationReplayEngine,
    trade: SimulationTrade,
    close_result: Dict[str, Any],
    exit_mid_price: float,
    cost_model: WorkbenchCostModel,
) -> Dict[str, Any]:
    raw_pnl = float(close_result.get("pnl") or 0.0)
    lot_size = float(trade.lot_size or 0.01)
    contract_size = _contract_size_for_symbol(session.symbol)
    summary = cost_model.cost_summary(
        entry_mid=float(trade.entry_mid_price if trade.entry_mid_price is not None else trade.entry_price),
        exit_mid=float(exit_mid_price),
        direction=str(trade.direction or "BUY"),
        lot_size=lot_size,
        contract_size=contract_size,
    )
    entry_mid_stored = _to_float_or_none(trade.entry_mid_price)
    entry_fill_stored = _to_float_or_none(trade.entry_fill_price if trade.entry_fill_price is not None else trade.entry_price)
    observed_exit = _to_float_or_none(close_result.get("exit_price"))
    expected_exit = _to_float_or_none(summary.get("exit_fill"))
    close_fill_for_cost = expected_exit if expected_exit is not None else (_to_float_or_none(exit_mid_price) or observed_exit or 0.0)
    entry_spread_points = abs(entry_fill_stored - entry_mid_stored) if (entry_mid_stored is not None and entry_fill_stored is not None) else 0.0
    close_spread_points = abs(float(close_fill_for_cost) - float(exit_mid_price))
    spread_points_total = float(entry_spread_points + close_spread_points)
    spread_cost_total = float(spread_points_total * lot_size * contract_size)
    summary["spread_points_total"] = spread_points_total
    summary["spread_cost_total"] = spread_cost_total
    summary["spread_source"] = str(getattr(cost_model, "spread_source", _COST_SPREAD_SOURCE_MANUAL))
    if observed_exit is not None and expected_exit is not None and abs(expected_exit - observed_exit) > 1e-12:
        sign = 1.0 if str(trade.direction or "").upper() == "BUY" else -1.0
        spread_delta = float((expected_exit - observed_exit) * sign * lot_size * contract_size)
        raw_pnl = float(raw_pnl + spread_delta)
        engine.balance = float(engine.balance + spread_delta)
    turnover_cost = float(summary.get("turnover_cost") or 0.0)
    summary["total_cost"] = float(spread_cost_total + turnover_cost)
    net_pnl = float(raw_pnl - turnover_cost)

    engine.balance -= turnover_cost
    if engine.closed_trades:
        for rec in reversed(engine.closed_trades):
            if int(rec.get("id") or -1) == int(trade.id):
                rec["pnl"] = round(net_pnl, 2)
                rec["raw_pnl"] = round(raw_pnl, 2)
                rec["spread_cost"] = round(spread_cost_total, 2)
                rec["turnover_cost"] = round(turnover_cost, 2)
                rec["total_cost"] = round(float(summary.get("total_cost") or 0.0), 2)
                rec["cost_breakdown"] = summary
                rec["exit_price"] = float(summary.get("exit_fill") or rec.get("exit_price") or 0.0)
                break

    summary_out = {
        **summary,
        "raw_pnl": round(raw_pnl, 2),
        "net_pnl": round(net_pnl, 2),
    }
    close_result["pnl"] = round(net_pnl, 2)
    close_result["raw_pnl"] = round(raw_pnl, 2)
    close_result["spread_cost"] = round(spread_cost_total, 2)
    close_result["turnover_cost"] = round(turnover_cost, 2)
    close_result["total_cost"] = round(float(summary.get("total_cost") or 0.0), 2)
    close_result["cost_breakdown"] = summary_out
    close_result["exit_price"] = float(summary.get("exit_fill") or close_result.get("exit_price") or 0.0)
    return close_result


def _derive_tp_from_rr(entry_price: float, stop_loss: float, direction: str, rr_target: float) -> Optional[float]:
    risk = abs(float(entry_price) - float(stop_loss))
    if risk <= 0:
        return None
    rr = max(0.5, float(rr_target))
    if str(direction).upper() == "BUY":
        return float(entry_price + (risk * rr))
    return float(entry_price - (risk * rr))


def _validate_entry_levels(direction: str, entry_price: float, stop_loss: float, take_profit: Optional[float]) -> bool:
    d = str(direction or "").upper()
    if d not in {"BUY", "SELL"}:
        return False
    if d == "BUY":
        if not (float(stop_loss) < float(entry_price)):
            return False
        if take_profit is not None and not (float(take_profit) > float(entry_price)):
            return False
        return True
    if not (float(stop_loss) > float(entry_price)):
        return False
    if take_profit is not None and not (float(take_profit) < float(entry_price)):
        return False
    return True


def _lot_step_decimals(step: float) -> int:
    s = f"{float(step):.10f}".rstrip("0").rstrip(".")
    if "." not in s:
        return 0
    return max(0, min(8, len(s.split(".")[1])))


def _normalize_lot_for_instrument(
    *,
    lot_size: float,
    min_lot: float,
    max_lot: float,
    lot_step: float,
) -> float:
    lot = float(lot_size)
    lo = max(0.0, float(min_lot))
    hi = max(lo, float(max_lot))
    step = max(1e-6, float(lot_step))
    lot = max(lo, min(hi, lot))
    # Floor to volume step to avoid accidental over-risk.
    steps = math.floor(((lot - lo) / step) + 1e-9)
    norm = lo + (max(0, int(steps)) * step)
    norm = max(lo, min(hi, norm))
    return round(norm, _lot_step_decimals(step))


def _compute_recent_loss_streak(session_id: int, db: Session) -> int:
    rows = (
        db.query(SimulationTrade.pnl)
        .filter(SimulationTrade.session_id == int(session_id))
        .filter(SimulationTrade.status == "closed")
        .order_by(SimulationTrade.id.desc())
        .limit(100)
        .all()
    )
    streak = 0
    for row in rows:
        pnl = _to_float_or_none(row[0] if isinstance(row, tuple) else getattr(row, "pnl", None))
        if pnl is None:
            continue
        if pnl < 0:
            streak += 1
            continue
        break
    return int(streak)


def _auto_paper_guardrail_state(
    copilot: WorkbenchCopilotSessionModel,
    session: SimulationSession,
    db: Session,
) -> Dict[str, Any]:
    cfg = copilot.config_json if isinstance(copilot.config_json, dict) else {}
    initial_balance = float(session.initial_balance or 0.0)
    current_balance = float(session.current_balance or 0.0)
    drawdown_usd = max(0.0, initial_balance - current_balance)
    dd_stop = max(10.0, float(cfg.get("auto_paper_session_drawdown_stop_usd", 300.0) or 300.0))
    max_losses = max(1, int(cfg.get("auto_paper_max_consecutive_losses", 3) or 3))
    max_open_positions = max(1, int(cfg.get("auto_paper_max_open_positions", 1) or 1))
    manual_pause = bool(cfg.get("auto_paper_manual_pause", False))
    open_positions = (
        db.query(SimulationTrade.id)
        .filter(SimulationTrade.session_id == int(session.id))
        .filter(SimulationTrade.status == "open")
        .count()
    )
    loss_streak = _compute_recent_loss_streak(session_id=int(session.id), db=db)

    blocked_reason: Optional[str] = None
    if manual_pause:
        blocked_reason = "manual_pause"
    elif drawdown_usd >= dd_stop:
        blocked_reason = "drawdown_limit"
    elif loss_streak >= max_losses:
        blocked_reason = "loss_streak_limit"
    elif open_positions >= max_open_positions:
        blocked_reason = "max_open_positions"

    return {
        "manual_pause": bool(manual_pause),
        "blocked": bool(blocked_reason),
        "blocked_reason": blocked_reason,
        "drawdown_usd": float(drawdown_usd),
        "drawdown_stop_usd": float(dd_stop),
        "loss_streak": int(loss_streak),
        "max_consecutive_losses": int(max_losses),
        "open_positions": int(open_positions),
        "max_open_positions": int(max_open_positions),
    }


def _build_tool_zone_preview(zones: Any) -> List[Dict[str, Any]]:
    preview: List[Dict[str, Any]] = []
    if not isinstance(zones, list):
        return preview
    for z in zones[:20]:
        if not isinstance(z, dict):
            continue
        preview.append(
            {
                "type": str(z.get("type") or ""),
                "top": float(z.get("top")) if z.get("top") is not None else None,
                "bottom": float(z.get("bottom")) if z.get("bottom") is not None else None,
                "origin_top": float(z.get("origin_top")) if z.get("origin_top") is not None else None,
                "origin_bottom": float(z.get("origin_bottom")) if z.get("origin_bottom") is not None else None,
                "gap_size": float(z.get("gap_size")) if z.get("gap_size") is not None else None,
                "original_gap_size": float(z.get("original_gap_size")) if z.get("original_gap_size") is not None else None,
                "current_gap_size": float(z.get("current_gap_size")) if z.get("current_gap_size") is not None else None,
                "z_score": float(z.get("z_score")) if z.get("z_score") is not None else None,
                "signal_strength": float(z.get("signal_strength")) if z.get("signal_strength") is not None else None,
                "sma_value": float(z.get("sma_value")) if z.get("sma_value") is not None else None,
                "upper_band": float(z.get("upper_band")) if z.get("upper_band") is not None else None,
                "lower_band": float(z.get("lower_band")) if z.get("lower_band") is not None else None,
                "distance": float(z.get("distance")) if z.get("distance") is not None else None,
                "trend_direction": str(z.get("trend_direction") or ""),
                "trend_timeframe": str(z.get("trend_timeframe") or ""),
                "trend_base_timeframe": str(z.get("trend_base_timeframe") or ""),
                "trend_aligned": bool(z.get("trend_aligned", False)),
                "mitigations": int(z.get("mitigations") or 0),
                "filled": bool(z.get("filled", False)),
                "filled_at_unix": int(z.get("filled_at_unix") or 0),
                "last_mitigated_unix": int(z.get("last_mitigated_unix") or 0),
                "bar_index": int(z.get("bar_index") or 0),
                "start_time_unix": int(z.get("start_time_unix") or 0),
                "end_time_unix": int(z.get("end_time_unix") or 0),
            }
        )
    return preview


def _build_tool_state_patch(
    tool_id: str,
    zones_count: int,
    zones_preview: List[Dict[str, Any]],
    config: Dict[str, Any],
    trend: Dict[str, Any],
    movement_strength: Dict[str, Any],
    current_state: Dict[str, Any],
    scan_source: Optional[str] = None,
) -> Dict[str, Any]:
    tid = str(tool_id or "").strip().lower()
    patch: Dict[str, Any] = {
        "tool_id": tid,
        "active": True,
        "zones_count": int(zones_count),
        "zones_preview": zones_preview,
        "config": config,
        "trend": trend,
        "movement_strength": movement_strength,
        "current_state": current_state,
    }
    if scan_source is not None:
        patch["scan_source"] = str(scan_source)
    if tid == "fvg":
        patch.update(
            {
                "fvg_enabled": True,
                "fvg_last_zone_count": int(zones_count),
                "fvg_config": config,
                "fvg_zones_preview": zones_preview,
                "fvg_trend": trend,
                "fvg_movement_strength": movement_strength,
            }
        )
    if tid == "mean_rev":
        patch.update(
            {
                "mean_rev_enabled": True,
                "mean_rev_last_zone_count": int(zones_count),
                "mean_rev_config": config,
                "mean_rev_zones_preview": zones_preview,
                "mean_rev_current_state": current_state,
            }
        )
    if tid == "liquidity":
        patch.update(
            {
                "liquidity_enabled": True,
                "liquidity_last_zone_count": int(zones_count),
                "liquidity_config": config,
                "liquidity_zones_preview": zones_preview,
                "liquidity_current_state": current_state,
            }
        )
    return patch


def _scan_tool_for_copilot(
    tool_id: str,
    engine: SimulationReplayEngine,
    config: Dict[str, Any],
) -> Dict[str, Any]:
    tid = str(tool_id or "").strip().lower()
    tool = get_tool(tid)
    if not tool:
        return {"ok": False, "error": f"unknown_tool:{tid or 'empty'}"}
    if engine.df is None or engine.df.empty:
        return {"ok": False, "error": "engine_no_data"}

    visible_df = engine.df.iloc[: engine.current_bar + 1]
    raw_cfg = config if isinstance(config, dict) else {}
    cfg_tf = str(raw_cfg.get("timeframe") or "").strip().upper()
    merged_config = {
        **tool.get_default_config(),
        **raw_cfg,
        "symbol": engine.symbol,
        # Respect explicitly requested scan timeframe (e.g. H4) instead of always forcing session/chart TF.
        "timeframe": cfg_tf or str(engine.timeframe or "M5"),
    }
    trend_meta: Dict[str, Any] = {}
    movement_strength: Dict[str, Any] = {}
    trend_fn = getattr(tool, "compute_trend_context", None)
    if callable(trend_fn):
        try:
            trend_meta = trend_fn(visible_df, merged_config) or {}
        except Exception:
            trend_meta = {}
    strength_fn = getattr(tool, "compute_movement_strength", None)
    if callable(strength_fn):
        try:
            movement_strength = strength_fn(visible_df, merged_config, trend_ctx=trend_meta) or {}
        except Exception:
            movement_strength = {}
    current_state: Dict[str, Any] = {}
    current_state_fn = getattr(tool, "compute_current_state", None)
    if callable(current_state_fn):
        try:
            current_state = current_state_fn(visible_df, merged_config) or {}
        except Exception:
            current_state = {}
    scan_config = dict(merged_config)
    if trend_meta:
        scan_config["_trend_context"] = trend_meta
    try:
        zones = tool.scan(visible_df, scan_config)
    except Exception as exc:
        return {"ok": False, "error": f"scan_failed:{type(exc).__name__}:{str(exc)[:120]}"}

    zones_preview = _build_tool_zone_preview(zones)
    return {
        "ok": True,
        "tool_id": tid,
        "zones_count": int(len(zones)) if isinstance(zones, list) else 0,
        "zones_preview": zones_preview,
        "config": merged_config,
        "trend": trend_meta,
        "movement_strength": movement_strength,
        "current_state": current_state,
    }


def _maybe_apply_auto_paper_actions(
    copilot: WorkbenchCopilotSessionModel,
    session: SimulationSession,
    db: Session,
    max_actions: int = 1,
) -> int:
    """
    Execute safe copilot actions in AUTO_PAPER mode.

    Phase 8 scope:
    - Auto close open paper trade on high-confidence exit/risk advice.
    - Auto open paper trade on high-confidence entry advice with valid SL/TP.
    - Auto refresh tool signals (AUTO_TOOL_SCAN) under confidence + cooldown gates.
    """
    if str(copilot.mode or "").strip().upper() != "AUTO_PAPER":
        return 0
    if session is None or str(session.status or "").lower() != "active":
        return 0
    cfg = copilot.config_json if isinstance(copilot.config_json, dict) else {}
    min_conf_entry = max(0.0, min(1.0, float(cfg.get("auto_paper_min_conf_entry", 0.90) or 0.90)))
    min_conf_exit = max(0.0, min(1.0, float(cfg.get("auto_paper_min_conf_exit", 0.80) or 0.80)))
    min_conf_scan = max(0.0, min(1.0, float(cfg.get("auto_tool_scan_min_conf", 0.70) or 0.70)))
    rr_target = max(0.5, float(cfg.get("auto_paper_rr_target", 1.8) or 1.8))
    require_tp = bool(cfg.get("auto_paper_require_tp", True))
    enable_auto_tool_scan = bool(cfg.get("enable_auto_tool_scan", True))
    tool_scan_cooldown = max(0, int(cfg.get("auto_tool_scan_cooldown_bars", 5) or 5))
    bar_cooldown = max(0, int(cfg.get("auto_paper_action_cooldown_bars", 2) or 2))
    max_per_iter_cfg = max(1, int(cfg.get("auto_paper_max_actions_per_iteration", 1) or 1))
    max_actions = min(max(1, int(max_actions)), max_per_iter_cfg)

    pending_advices = (
        db.query(WorkbenchCopilotAdviceModel)
        .filter(WorkbenchCopilotAdviceModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotAdviceModel.status == "NEW")
        .filter(WorkbenchCopilotAdviceModel.delivery == "ACTIONABLE")
        .order_by(
            WorkbenchCopilotAdviceModel.source_event_priority.desc(),
            WorkbenchCopilotAdviceModel.created_at.asc(),
        )
        .limit(max(1, int(max_actions * 4)))
        .all()
    )
    if not pending_advices:
        return 0

    engine = _get_or_create_engine(session, db)
    use_cost_model = _is_cost_model_enabled(session)
    cost_model = _session_cost_model(session) if use_cost_model else None
    last_snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
    meta = last_snapshot.get("__copilot_meta") if isinstance(last_snapshot.get("__copilot_meta"), dict) else {}
    last_auto_bar = int(meta.get("last_auto_action_bar", -10_000_000) or -10_000_000)
    last_tool_scan_bar = int(meta.get("last_tool_scan_bar", -10_000_000) or -10_000_000)
    entry_reject_streak = int(meta.get("entry_reject_streak", 0) or 0)
    entry_reject_suppress_n = max(2, int(cfg.get("auto_paper_entry_reject_suppress_n", 3) or 3))
    current_bar = int(session.current_bar or engine.current_bar or 0)
    if (current_bar - last_auto_bar) < bar_cooldown:
        return 0
    guard = _auto_paper_guardrail_state(copilot=copilot, session=session, db=db)
    last_guard_reason = str(meta.get("guardrail_reason") or "").strip().lower()
    guard_reason_now = str(guard.get("blocked_reason") or "").strip().lower()
    if guard.get("blocked") and guard_reason_now and guard_reason_now != last_guard_reason:
        _emit_copilot_event(
            copilot=copilot,
            event_type="COPILOT_GUARDRAIL_BLOCK",
            severity="warning",
            payload={
                **guard,
                "_priority": _event_priority_for_type("COPILOT_GUARDRAIL_BLOCK"),
            },
            db=db,
        )
    elif (not guard.get("blocked")) and last_guard_reason:
        _emit_copilot_event(
            copilot=copilot,
            event_type="COPILOT_GUARDRAIL_RESUME",
            severity="info",
            payload={
                **guard,
                "_priority": _event_priority_for_type("COPILOT_GUARDRAIL_RESUME"),
            },
            db=db,
        )

    executed = 0
    for adv in pending_advices:
        action_json = adv.action_json if isinstance(adv.action_json, dict) else {}
        evidence_json = adv.evidence_json if isinstance(adv.evidence_json, dict) else {}
        action_type = str(action_json.get("action_type") or adv.advice_type or "").strip().upper()
        confidence = float(adv.confidence) if adv.confidence is not None else 0.0

        if action_type not in {
            "AUTO_PAPER_EXIT",
            "SUGGEST_EXIT",
            "SUGGEST_RISK_ADJUSTMENT",
            "AUTO_PAPER_ENTRY",
            "SUGGEST_ENTRY",
            "AUTO_TOOL_SCAN",
        }:
            continue

        # Manual pause is an explicit operator override; suppress all autonomous actions.
        if str(guard.get("blocked_reason") or "") == "manual_pause":
            adv.status = "ACKNOWLEDGED"
            continue

        if action_type == "AUTO_TOOL_SCAN":
            if not enable_auto_tool_scan:
                adv.status = "ACKNOWLEDGED"
                continue
            if confidence < min_conf_scan:
                adv.status = "ACKNOWLEDGED"
                continue
            if (current_bar - last_tool_scan_bar) < tool_scan_cooldown:
                adv.status = "ACKNOWLEDGED"
                continue
            tool_id = str(action_json.get("tool_id") or "fvg").strip().lower()
            tool_cfg = action_json.get("config") if isinstance(action_json.get("config"), dict) else {}
            scan_result = _scan_tool_for_copilot(tool_id=tool_id, engine=engine, config=tool_cfg)
            if not scan_result.get("ok"):
                adv.status = "REJECTED"
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_TOOL_SCAN",
                        payload_json={"error": str(scan_result.get("error") or "scan_failed"), "tool_id": tool_id},
                        note="Auto tool scan failed",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                continue

            zones_count = int(scan_result.get("zones_count") or 0)
            zones_preview = scan_result.get("zones_preview") if isinstance(scan_result.get("zones_preview"), list) else []
            merged_cfg = scan_result.get("config") if isinstance(scan_result.get("config"), dict) else {}
            trend_meta = scan_result.get("trend") if isinstance(scan_result.get("trend"), dict) else {}
            movement_strength = scan_result.get("movement_strength") if isinstance(scan_result.get("movement_strength"), dict) else {}
            current_state = scan_result.get("current_state") if isinstance(scan_result.get("current_state"), dict) else {}
            tool_state_patch = _build_tool_state_patch(
                tool_id=tool_id,
                zones_count=zones_count,
                zones_preview=zones_preview,
                config=merged_cfg,
                trend=trend_meta,
                movement_strength=movement_strength,
                current_state=current_state,
            )
            db.add(
                WorkbenchCopilotActionModel(
                    copilot_session_id=int(copilot.id),
                    advice_id=int(adv.id),
                    action_type="AUTO_TOOL_SCAN",
                    payload_json={
                        "tool_id": tool_id,
                        "zones_count": zones_count,
                        "zones_preview": zones_preview,
                        "trend": trend_meta,
                        "movement_strength": movement_strength,
                        "current_state": current_state,
                        "confidence": confidence,
                    },
                    note="Auto tool scan executed by copilot",
                    requested_by="COPILOT",
                    status="EXECUTED",
                    created_at=datetime.utcnow(),
                )
            )
            adv.status = "EXECUTED"
            _emit_copilot_event(
                copilot=copilot,
                event_type="COPILOT_ACTION_EXECUTED",
                severity="info",
                payload={
                    "action_type": "AUTO_TOOL_SCAN",
                    "advice_id": int(adv.id),
                    "tool_id": tool_id,
                    "zones_count": zones_count,
                    "trend": trend_meta,
                    "movement_strength": movement_strength,
                    "current_state": current_state,
                },
                db=db,
            )
            _emit_copilot_event(
                copilot=copilot,
                event_type="TOOL_SIGNAL_CHANGED",
                severity="info",
                payload={
                    "tool_id": tool_id,
                    "bar_index": int(engine.current_bar or 0),
                    "zones_count": zones_count,
                    "zones_preview": zones_preview,
                    "config": merged_cfg,
                    "trend": trend_meta,
                    "movement_strength": movement_strength,
                    "current_state": current_state,
                    "tool_state": tool_state_patch,
                    "_priority": _event_priority_for_type("TOOL_SIGNAL_CHANGED"),
                },
                db=db,
            )
            last_snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
            tool_state = last_snapshot.get("tool_state") if isinstance(last_snapshot.get("tool_state"), dict) else {}
            tools_full = last_snapshot.get("tool_state_full") if isinstance(last_snapshot.get("tool_state_full"), dict) else {}
            tools_full[str(tool_id)] = {
                "enabled": True,
                "scan_count": int((tools_full.get(str(tool_id), {}).get("scan_count") if isinstance(tools_full.get(str(tool_id)), dict) else 0) or 0) + 1,
                "last_zone_count": zones_count,
                "zones_sample": zones_preview,
                "config": merged_cfg,
                "current_state": current_state,
            }
            tool_state = {**tool_state, **tool_state_patch}
            if tool_id == "fvg":
                tool_state["fvg_scan_count"] = int(tool_state.get("fvg_scan_count") or 0) + 1
            if tool_id == "mean_rev":
                tool_state["mean_rev_scan_count"] = int(tool_state.get("mean_rev_scan_count") or 0) + 1
            if tool_id == "liquidity":
                tool_state["liquidity_scan_count"] = int(tool_state.get("liquidity_scan_count") or 0) + 1
            last_snapshot["tool_state"] = tool_state
            last_snapshot["tool_state_full"] = tools_full
            copilot.last_snapshot_json = last_snapshot
            copilot.updated_at = datetime.utcnow()
            last_tool_scan_bar = int(current_bar)
            executed += 1
        elif action_type in {"AUTO_PAPER_EXIT", "SUGGEST_EXIT", "SUGGEST_RISK_ADJUSTMENT"}:
            open_trade = (
                db.query(SimulationTrade)
                .filter(SimulationTrade.session_id == int(session.id))
                .filter(SimulationTrade.status == "open")
                .order_by(SimulationTrade.id.asc())
                .first()
            )
            if confidence < min_conf_exit:
                adv.status = "ACKNOWLEDGED"
                continue
            if open_trade is None:
                adv.status = "ACKNOWLEDGED"
                continue
            exit_mid = None
            if engine.df is not None and not engine.df.empty and engine.current_bar < engine.total_bars:
                exit_mid = float(engine.df.iloc[engine.current_bar]["close"])
            else:
                exit_mid = _to_float_or_none(open_trade.entry_price)
            exit_fill = float(exit_mid if exit_mid is not None else open_trade.entry_price)
            if use_cost_model and cost_model is not None and exit_mid is not None:
                close_side = "sell" if str(open_trade.direction or "").upper() == "BUY" else "buy"
                exit_fill = float(cost_model.apply_fill_spread(float(exit_mid), close_side))
            try:
                close_result = engine.close_position(int(open_trade.id), exit_price_override=exit_fill)
            except Exception as exc:
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_PAPER_EXIT",
                        payload_json={
                            "trade_id": int(open_trade.id),
                            "error": str(exc)[:220],
                        },
                        note="Auto-paper exit failed",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                adv.status = "REJECTED"
                continue
            if use_cost_model and cost_model is not None and exit_mid is not None:
                close_result = _apply_close_cost_adjustment(
                    session=session,
                    engine=engine,
                    trade=open_trade,
                    close_result=close_result,
                    exit_mid_price=float(exit_mid),
                    cost_model=cost_model,
                )

            open_trade.exit_price = _to_float_or_none(close_result.get("exit_price"))
            open_trade.exit_mid_price = float(exit_mid) if exit_mid is not None else None
            open_trade.exit_fill_price = _to_float_or_none(close_result.get("exit_price"))
            open_trade.exit_bar = close_result.get("exit_bar")
            open_trade.exit_time = close_result.get("exit_time")
            open_trade.exit_reason = "copilot_auto"
            open_trade.raw_pnl = _to_float_or_none(close_result.get("raw_pnl")) if close_result.get("raw_pnl") is not None else _to_float_or_none(close_result.get("pnl"))
            open_trade.pnl = _to_float_or_none(close_result.get("pnl"))
            open_trade.spread_cost = _to_float_or_none(close_result.get("spread_cost")) if close_result.get("spread_cost") is not None else 0.0
            open_trade.turnover_cost = _to_float_or_none(close_result.get("turnover_cost")) if close_result.get("turnover_cost") is not None else 0.0
            open_trade.total_cost = _to_float_or_none(close_result.get("total_cost")) if close_result.get("total_cost") is not None else 0.0
            open_trade.cost_breakdown_json = close_result.get("cost_breakdown") if isinstance(close_result.get("cost_breakdown"), dict) else None
            open_trade.r_multiple = close_result.get("r_multiple")
            open_trade.status = "closed"
            _sync_session_from_engine_no_commit(session, engine)

            db.add(
                WorkbenchCopilotActionModel(
                    copilot_session_id=int(copilot.id),
                    advice_id=int(adv.id),
                    action_type="AUTO_PAPER_EXIT",
                    payload_json={
                        "trade_id": int(open_trade.id),
                        "exit_price": float(open_trade.exit_price) if open_trade.exit_price is not None else None,
                        "pnl": float(open_trade.pnl) if open_trade.pnl is not None else None,
                        "r_multiple": float(open_trade.r_multiple) if open_trade.r_multiple is not None else None,
                        "source_advice_type": str(adv.advice_type or ""),
                        "confidence": confidence,
                    },
                    note="Auto-paper close executed by copilot",
                    requested_by="COPILOT",
                    status="EXECUTED",
                    created_at=datetime.utcnow(),
                )
            )
            adv.status = "EXECUTED"

            _emit_copilot_event(
                copilot=copilot,
                event_type="COPILOT_ACTION_EXECUTED",
                severity="info",
                payload={
                    "action_type": "AUTO_PAPER_EXIT",
                    "advice_id": int(adv.id),
                    "trade_id": int(open_trade.id),
                    "pnl": float(open_trade.pnl) if open_trade.pnl is not None else None,
                },
                db=db,
            )
            _emit_copilot_event(
                copilot=copilot,
                event_type="TRADE_CLOSED",
                severity="info",
                payload={
                    "trade_id": int(open_trade.id),
                    "exit_price": float(open_trade.exit_price) if open_trade.exit_price is not None else None,
                    "pnl": float(open_trade.pnl) if open_trade.pnl is not None else None,
                    "r_multiple": float(open_trade.r_multiple) if open_trade.r_multiple is not None else None,
                    "exit_reason": "copilot_auto",
                    "_priority": _event_priority_for_type("TRADE_CLOSED"),
                },
                db=db,
            )

            executed += 1
        else:
            # AUTO_PAPER_ENTRY / SUGGEST_ENTRY
            open_trade = (
                db.query(SimulationTrade)
                .filter(SimulationTrade.session_id == int(session.id))
                .filter(SimulationTrade.status == "open")
                .order_by(SimulationTrade.id.asc())
                .first()
            )
            if confidence < min_conf_entry:
                adv.status = "ACKNOWLEDGED"
                continue
            if entry_reject_streak >= entry_reject_suppress_n:
                adv.status = "ACKNOWLEDGED"
                continue
            if bool(guard.get("blocked")):
                adv.status = "REJECTED"
                entry_reject_streak += 1
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_PAPER_ENTRY",
                        payload_json={
                            "error": "guardrail_blocked",
                            "guardrail_reason": str(guard.get("blocked_reason") or ""),
                        },
                        note=f"Auto-paper entry blocked by guardrail: {guard.get('blocked_reason')}",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                continue
            if open_trade is not None:
                adv.status = "ACKNOWLEDGED"
                continue
            if int(guard.get("open_positions") or 0) >= int(guard.get("max_open_positions") or 1):
                adv.status = "REJECTED"
                entry_reject_streak += 1
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_PAPER_ENTRY",
                        payload_json={"error": "max_open_positions", **guard},
                        note="Auto-paper entry blocked: max open positions reached",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                continue

            direction = str(action_json.get("direction") or "").strip().upper()
            if direction not in {"BUY", "SELL"}:
                # Try a weak fallback from tool evidence when available.
                zones_preview = evidence_json.get("zones_preview") if isinstance(evidence_json.get("zones_preview"), list) else []
                if zones_preview:
                    z = zones_preview[-1] if isinstance(zones_preview[-1], dict) else {}
                    zt = str(z.get("type") or "").lower()
                    if "bull" in zt:
                        direction = "BUY"
                    elif "bear" in zt:
                        direction = "SELL"
                    elif "buy" in zt:
                        direction = "BUY"
                    elif "sell" in zt:
                        direction = "SELL"

            if direction not in {"BUY", "SELL"}:
                adv.status = "REJECTED"
                entry_reject_streak += 1
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_PAPER_ENTRY",
                        payload_json={"error": "missing_direction"},
                        note="Auto-paper entry rejected: missing direction",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                continue

            if engine.df is None or engine.df.empty or engine.current_bar >= engine.total_bars:
                adv.status = "REJECTED"
                entry_reject_streak += 1
                continue
            entry_mid_price = float(engine.df.iloc[engine.current_bar]["close"])
            entry_fill_price = float(entry_mid_price)
            if use_cost_model and cost_model is not None:
                open_side = "buy" if direction == "BUY" else "sell"
                entry_fill_price = float(cost_model.apply_fill_spread(float(entry_mid_price), open_side))
            stop_loss = _to_float_or_none(action_json.get("stop_loss"))
            take_profit = _to_float_or_none(action_json.get("take_profit"))
            lot_size = _to_float_or_none(action_json.get("lot_size"))
            if lot_size is None or lot_size <= 0:
                lot_size = 0.01

            # Fallback level derivation from zone boundaries when present.
            zone_top = _to_float_or_none(action_json.get("zone_top") if action_json.get("zone_top") is not None else evidence_json.get("zone_top"))
            zone_bottom = _to_float_or_none(action_json.get("zone_bottom") if action_json.get("zone_bottom") is not None else evidence_json.get("zone_bottom"))
            if stop_loss is None:
                if direction == "BUY" and zone_bottom is not None and zone_bottom < entry_fill_price:
                    stop_loss = zone_bottom
                elif direction == "SELL" and zone_top is not None and zone_top > entry_fill_price:
                    stop_loss = zone_top

            if stop_loss is None:
                adv.status = "REJECTED"
                entry_reject_streak += 1
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_PAPER_ENTRY",
                        payload_json={"error": "missing_stop_loss", "direction": direction},
                        note="Auto-paper entry rejected: missing stop loss",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                continue

            if take_profit is None:
                take_profit = _derive_tp_from_rr(
                    entry_price=entry_fill_price,
                    stop_loss=stop_loss,
                    direction=direction,
                    rr_target=rr_target,
                )
            if require_tp and take_profit is None:
                adv.status = "REJECTED"
                entry_reject_streak += 1
                continue

            if not _validate_entry_levels(direction, entry_fill_price, stop_loss, take_profit):
                adv.status = "REJECTED"
                entry_reject_streak += 1
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_PAPER_ENTRY",
                        payload_json={
                            "error": "invalid_levels",
                            "direction": direction,
                            "entry_price": entry_fill_price,
                            "stop_loss": stop_loss,
                            "take_profit": take_profit,
                        },
                        note="Auto-paper entry rejected: invalid SL/TP placement",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                continue

            try:
                trade_result = engine.execute_trade(
                    direction=direction,
                    sl=float(stop_loss),
                    tp=float(take_profit) if take_profit is not None else None,
                    lot_size=float(lot_size),
                    entry_price_override=entry_fill_price,
                )
            except Exception as exc:
                adv.status = "REJECTED"
                entry_reject_streak += 1
                db.add(
                    WorkbenchCopilotActionModel(
                        copilot_session_id=int(copilot.id),
                        advice_id=int(adv.id),
                        action_type="AUTO_PAPER_ENTRY",
                        payload_json={"error": str(exc)[:220]},
                        note="Auto-paper entry failed in engine",
                        requested_by="COPILOT",
                        status="REJECTED",
                        created_at=datetime.utcnow(),
                    )
                )
                continue

            trade_row = SimulationTrade(
                session_id=int(session.id),
                direction=direction,
                entry_price=trade_result.get("entry_price"),
                entry_mid_price=float(entry_mid_price),
                entry_fill_price=float(entry_fill_price),
                entry_bar=trade_result.get("entry_bar"),
                entry_time=trade_result.get("entry_time"),
                stop_loss=float(stop_loss),
                take_profit=float(take_profit) if take_profit is not None else None,
                lot_size=float(lot_size),
                spread_value=float(cost_model.spread) if use_cost_model and cost_model is not None else None,
                tc_rate=float(cost_model.tc_rate) if use_cost_model and cost_model is not None else None,
                status="open",
            )
            db.add(trade_row)
            db.flush()
            if engine.open_positions:
                engine.open_positions[-1]["id"] = int(trade_row.id)

            _sync_session_from_engine_no_commit(session, engine)
            db.add(
                WorkbenchCopilotActionModel(
                    copilot_session_id=int(copilot.id),
                    advice_id=int(adv.id),
                    action_type="AUTO_PAPER_ENTRY",
                    payload_json={
                        "trade_id": int(trade_row.id),
                        "direction": direction,
                        "entry_price": float(trade_row.entry_price),
                        "stop_loss": float(trade_row.stop_loss),
                        "take_profit": float(trade_row.take_profit) if trade_row.take_profit is not None else None,
                        "lot_size": float(trade_row.lot_size or 0.01),
                        "confidence": confidence,
                    },
                    note="Auto-paper entry executed by copilot",
                    requested_by="COPILOT",
                    status="EXECUTED",
                    created_at=datetime.utcnow(),
                )
            )
            adv.status = "EXECUTED"
            entry_reject_streak = 0
            _emit_copilot_event(
                copilot=copilot,
                event_type="COPILOT_ACTION_EXECUTED",
                severity="info",
                payload={
                    "action_type": "AUTO_PAPER_ENTRY",
                    "advice_id": int(adv.id),
                    "trade_id": int(trade_row.id),
                },
                db=db,
            )
            _emit_copilot_event(
                copilot=copilot,
                event_type="TRADE_OPENED",
                severity="info",
                payload={
                    "trade_id": int(trade_row.id),
                    "direction": direction,
                    "entry_price": float(trade_row.entry_price),
                    "stop_loss": float(trade_row.stop_loss),
                    "take_profit": float(trade_row.take_profit) if trade_row.take_profit is not None else None,
                    "lot_size": float(trade_row.lot_size or 0.01),
                    "_priority": _event_priority_for_type("TRADE_OPENED"),
                },
                db=db,
            )
            executed += 1

        # Update snapshot/meta after each executed auto action.
        if executed > 0:
            current_bar = int(session.current_bar or engine.current_bar or 0)
            last_snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
            meta = last_snapshot.get("__copilot_meta") if isinstance(last_snapshot.get("__copilot_meta"), dict) else {}
            is_tool_scan = action_type == "AUTO_TOOL_SCAN"
            meta = {
                **meta,
                "last_auto_action_bar": int(current_bar),
                "last_tool_scan_bar": int(last_tool_scan_bar),
                "auto_actions_executed": int(meta.get("auto_actions_executed") or 0) + 1,
                "auto_tool_scans_executed": int(meta.get("auto_tool_scans_executed") or 0) + (1 if is_tool_scan else 0),
                "entry_reject_streak": int(entry_reject_streak),
                "guardrail_blocked": bool(guard.get("blocked")),
                "guardrail_reason": str(guard.get("blocked_reason") or ""),
            }
            last_snapshot["__copilot_meta"] = meta
            last_snapshot.update(
                {
                    "current_bar": int(session.current_bar or 0),
                    "balance": float(session.current_balance or 0.0),
                    "total_pnl": float(session.total_pnl or 0.0),
                    "trades_count": int(session.trades_count or 0),
                    "wins": int(session.wins or 0),
                    "losses": int(session.losses or 0),
                    "open_positions_count": int(len(engine.open_positions or [])),
                    "guardrails": guard,
                }
            )
            copilot.last_snapshot_json = last_snapshot
            copilot.updated_at = datetime.utcnow()

        if executed >= max_actions:
            break

    # Persist current guardrail info even when no action executed.
    if executed == 0:
        last_snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
        meta = last_snapshot.get("__copilot_meta") if isinstance(last_snapshot.get("__copilot_meta"), dict) else {}
        meta = {
            **meta,
            "last_tool_scan_bar": int(last_tool_scan_bar),
            "entry_reject_streak": int(entry_reject_streak),
            "guardrail_blocked": bool(guard.get("blocked")),
            "guardrail_reason": str(guard.get("blocked_reason") or ""),
        }
        last_snapshot["__copilot_meta"] = meta
        last_snapshot["guardrails"] = guard
        copilot.last_snapshot_json = last_snapshot
        copilot.updated_at = datetime.utcnow()

    return executed


def _runtime_summary(runtime: Dict[str, Any]) -> Dict[str, Any]:
    if not isinstance(runtime, dict):
        return {"configured": False}
    has_key = bool(runtime.get("openai_api_key") or runtime.get("anthropic_api_key"))
    return {
        "configured": bool(runtime),
        "has_api_key": has_key,
        "openai_base_url": str(runtime.get("openai_base_url") or "") if runtime.get("openai_base_url") else None,
        "claude_base_url": str(runtime.get("claude_base_url") or "") if runtime.get("claude_base_url") else None,
        "local_gptoss_url": str(runtime.get("local_gptoss_url") or "") if runtime.get("local_gptoss_url") else None,
    }


def _store_copilot_snapshot(
    copilot: WorkbenchCopilotSessionModel,
    snapshot: Dict[str, Any],
    db: Session,
    source: str = "advance",
) -> None:
    if copilot is None:
        return
    bar_index = int(snapshot.get("current_bar") or 0)
    row = WorkbenchCopilotSnapshotModel(
        copilot_session_id=int(copilot.id),
        bar_index=bar_index,
        source=str(source or "advance"),
        snapshot_json=snapshot if isinstance(snapshot, dict) else {},
        created_at=datetime.utcnow(),
    )
    db.add(row)
    # Keep snapshot table bounded per copilot session.
    cfg = copilot.config_json if isinstance(copilot.config_json, dict) else {}
    keep_n = max(200, int(cfg.get("snapshot_retention") or 5000))
    stale_ids = (
        db.query(WorkbenchCopilotSnapshotModel.id)
        .filter(WorkbenchCopilotSnapshotModel.copilot_session_id == int(copilot.id))
        .order_by(desc(WorkbenchCopilotSnapshotModel.id))
        .offset(keep_n)
        .limit(2000)
        .all()
    )
    if stale_ids:
        stale_id_values = [int(r[0]) for r in stale_ids]
        (
            db.query(WorkbenchCopilotSnapshotModel)
            .filter(WorkbenchCopilotSnapshotModel.id.in_(stale_id_values))
            .delete(synchronize_session=False)
        )


def _has_pending_or_running_job(copilot_session_id: int, db: Session) -> bool:
    cnt = (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(copilot_session_id))
        .filter(WorkbenchCopilotJobModel.status.in_(["PENDING", "RUNNING"]))
        .count()
    )
    return int(cnt or 0) > 0


def _enqueue_copilot_advice_job(
    copilot: WorkbenchCopilotSessionModel,
    snapshot: Dict[str, Any],
    events: List[Dict[str, Any]],
    config: Dict[str, Any],
    event_id_by_type: Dict[str, int],
    db: Session,
) -> bool:
    if not events:
        return False
    if _has_pending_or_running_job(int(copilot.id), db):
        return False

    meta = snapshot.get("__copilot_meta") if isinstance(snapshot.get("__copilot_meta"), dict) else {}
    current_bar = int(snapshot.get("current_bar") or 0)
    last_job_bar = int(meta.get("last_job_bar", -10_000_000) or -10_000_000)
    min_interval = max(0, int(config.get("job_min_interval_bars", 3) or 3))
    if (current_bar - last_job_bar) < min_interval:
        return False

    payload = {
        "snapshot": snapshot,
        "events": events,
        "mode": str(copilot.mode or "ADVISE"),
        "provider": str(copilot.provider or "deterministic"),
        "model_label": str(copilot.model_label or ""),
        "config": _redact_sensitive_config(config),
        "event_id_by_type": {str(k): int(v) for k, v in (event_id_by_type or {}).items()},
        "bar_index": current_bar,
    }
    db.add(
        WorkbenchCopilotJobModel(
            copilot_session_id=int(copilot.id),
            simulation_session_id=int(copilot.simulation_session_id),
            job_type="ADVICE_GENERATION",
            status="PENDING",
            priority=50,
            payload_json=payload,
            created_at=datetime.utcnow(),
        )
    )
    meta = {
        **meta,
        "last_job_bar": int(current_bar),
    }
    snapshot["__copilot_meta"] = meta
    copilot.last_snapshot_json = snapshot
    return True


def _apply_completed_copilot_jobs(
    copilot: WorkbenchCopilotSessionModel,
    db: Session,
    max_jobs: int = 5,
) -> int:
    jobs = (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotJobModel.status == "COMPLETED")
        .order_by(WorkbenchCopilotJobModel.id.asc())
        .limit(max(1, int(max_jobs)))
        .all()
    )
    applied = 0
    for job in jobs:
        result = job.result_json if isinstance(job.result_json, dict) else {}
        payload = job.payload_json if isinstance(job.payload_json, dict) else {}
        event_id_by_type = payload.get("event_id_by_type") if isinstance(payload.get("event_id_by_type"), dict) else {}
        provider_meta = result.get("provider_meta") if isinstance(result.get("provider_meta"), dict) else {}
        provider_used = str(provider_meta.get("provider_used") or "deterministic")
        provider_attempts = provider_meta.get("provider_attempts") if isinstance(provider_meta.get("provider_attempts"), list) else []
        advices = result.get("advices") if isinstance(result.get("advices"), list) else []
        for adv in advices:
            if not isinstance(adv, dict):
                continue
            source_event_type = str(adv.get("source_event_type") or "")
            evidence_json = adv.get("evidence_json") if isinstance(adv.get("evidence_json"), dict) else {}
            evidence_json = {
                **evidence_json,
                "_event_priority": int(adv.get("source_event_priority") or 0),
                "_provider_used": provider_used,
                "_async_job_id": int(job.id),
            }
            action_json = adv.get("action_json") if isinstance(adv.get("action_json"), dict) else {}
            action_json = {
                **action_json,
                "delivery": str(adv.get("delivery") or "ACTIONABLE"),
                "provider_used": provider_used,
            }
            db.add(
                WorkbenchCopilotAdviceModel(
                    copilot_session_id=int(copilot.id),
                    event_id=int(event_id_by_type.get(source_event_type)) if str(event_id_by_type.get(source_event_type, "")).strip() else None,
                    advice_type=str(adv.get("advice_type") or "REVIEW_NOTE"),
                    summary=str(adv.get("summary") or ""),
                    confidence=float(adv.get("confidence")) if adv.get("confidence") is not None else None,
                    source_event_priority=int(adv.get("source_event_priority") or 0),
                    delivery=str(adv.get("delivery") or "ACTIONABLE"),
                    evidence_json=evidence_json,
                    action_json=action_json,
                    status=str(adv.get("status") or "NEW"),
                    created_at=datetime.utcnow(),
                )
            )
        last_snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
        meta = last_snapshot.get("__copilot_meta") if isinstance(last_snapshot.get("__copilot_meta"), dict) else {}
        meta = {
            **meta,
            "provider_used": provider_used,
            "provider_attempts": provider_attempts,
            "last_applied_job_id": int(job.id),
        }
        last_snapshot["__copilot_meta"] = meta
        copilot.last_snapshot_json = last_snapshot
        copilot.updated_at = datetime.utcnow()

        job.status = "APPLIED"
        job.finished_at = datetime.utcnow()
        applied += 1
    if applied > 0:
        sim_session = db.query(SimulationSession).get(int(copilot.simulation_session_id))
        if sim_session is not None:
            _maybe_apply_auto_paper_actions(
                copilot=copilot,
                session=sim_session,
                db=db,
                max_actions=1,
            )
        db.commit()
    return applied


def _record_external_copilot_event(
    simulation_session_id: int,
    event_type: str,
    payload: Dict[str, Any],
    db: Session,
    severity: str = "info",
    auto_commit: bool = True,
) -> None:
    copilot = _get_active_copilot(int(simulation_session_id), db)
    if copilot is None:
        return
    cfg = copilot.config_json if isinstance(copilot.config_json, dict) else {}
    snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
    meta = snapshot.get("__copilot_meta") if isinstance(snapshot.get("__copilot_meta"), dict) else {}
    last_event_bar = dict(meta.get("last_event_bar") or {})
    last_sig_bar = dict(meta.get("last_sig_bar") or {})
    current_bar = int(snapshot.get("current_bar") or 0)
    event_type_norm = str(event_type or "").strip().upper()
    event_cd_map = cfg.get("event_cooldowns") if isinstance(cfg.get("event_cooldowns"), dict) else {}
    global_cd = max(0, int(cfg.get("global_cooldown_bars", 0) or 0))
    global_last = int(meta.get("last_event_global_bar", -10_000_000) or -10_000_000)
    if (current_bar - global_last) < global_cd:
        return
    et_cd = max(0, int(event_cd_map.get(event_type_norm, 0) or 0))
    et_last = int(last_event_bar.get(event_type_norm, -10_000_000) or -10_000_000)
    if (current_bar - et_last) < et_cd:
        return
    dedupe_window = max(1, int(cfg.get("dedupe_window_bars", 8) or 8))
    raw = json.dumps(
        {"event_type": event_type_norm, "payload": payload if isinstance(payload, dict) else {}},
        sort_keys=True,
        ensure_ascii=True,
    )
    sig = hashlib.sha1(raw.encode("utf-8")).hexdigest()
    sig_last = int(last_sig_bar.get(sig, -10_000_000) or -10_000_000)
    if (current_bar - sig_last) < dedupe_window:
        return

    _emit_copilot_event(
        copilot=copilot,
        event_type=event_type,
        payload={
            **(payload if isinstance(payload, dict) else {}),
            "_priority": _event_priority_for_type(event_type_norm),
        },
        db=db,
        severity=severity,
    )
    last_event_bar[event_type_norm] = current_bar
    last_sig_bar[sig] = current_bar
    min_keep = current_bar - (dedupe_window * 4)
    last_sig_bar = {k: int(v) for k, v in last_sig_bar.items() if int(v) >= min_keep}
    snapshot["__copilot_meta"] = {
        **meta,
        "last_event_bar": {k: int(v) for k, v in last_event_bar.items()},
        "last_sig_bar": {k: int(v) for k, v in last_sig_bar.items()},
        "last_event_global_bar": int(current_bar),
    }
    copilot.last_snapshot_json = snapshot
    copilot.updated_at = datetime.utcnow()
    if auto_commit:
        db.commit()


def _store_external_snapshot(
    simulation_session: SimulationSession,
    db: Session,
    source: str,
    patch: Dict[str, Any] | None = None,
    auto_commit: bool = True,
) -> None:
    copilot = _get_active_copilot(int(simulation_session.id), db)
    if copilot is None:
        return

    base = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
    snapshot = dict(base)
    snapshot.update({
        "ts": datetime.utcnow().isoformat(),
        "session_id": int(simulation_session.id),
        "strategy_id": str(simulation_session.strategy_id or ""),
        "symbol": str(simulation_session.symbol or ""),
        "timeframe": str(simulation_session.timeframe or ""),
        "current_bar": int(simulation_session.current_bar or 0),
        "total_bars": int(simulation_session.total_bars or 0),
        "balance": float(simulation_session.current_balance or 0.0),
        "initial_balance": float(simulation_session.initial_balance or 0.0),
        "total_pnl": float(simulation_session.total_pnl or 0.0),
        "trades_count": int(simulation_session.trades_count or 0),
        "wins": int(simulation_session.wins or 0),
        "losses": int(simulation_session.losses or 0),
    })
    if isinstance(patch, dict):
        snapshot.update(patch)

    copilot.last_snapshot_json = snapshot
    copilot.updated_at = datetime.utcnow()
    _store_copilot_snapshot(copilot=copilot, snapshot=snapshot, db=db, source=source)
    if auto_commit:
        db.commit()


def _copilot_state_payload(
    copilot: WorkbenchCopilotSessionModel,
    db: Session,
    events_limit: int = 10,
    advices_limit: int = 10,
) -> Dict[str, Any]:
    _apply_completed_copilot_jobs(copilot=copilot, db=db, max_jobs=10)
    events_count = (
        db.query(WorkbenchCopilotEventModel)
        .filter(WorkbenchCopilotEventModel.copilot_session_id == int(copilot.id))
        .count()
    )
    advices_count = (
        db.query(WorkbenchCopilotAdviceModel)
        .filter(WorkbenchCopilotAdviceModel.copilot_session_id == int(copilot.id))
        .count()
    )
    actions_count = (
        db.query(WorkbenchCopilotActionModel)
        .filter(WorkbenchCopilotActionModel.copilot_session_id == int(copilot.id))
        .count()
    )
    copilot_actions_executed = (
        db.query(WorkbenchCopilotActionModel)
        .filter(WorkbenchCopilotActionModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotActionModel.requested_by == "COPILOT")
        .filter(WorkbenchCopilotActionModel.status == "EXECUTED")
        .count()
    )
    auto_tool_scans_executed = (
        db.query(WorkbenchCopilotActionModel)
        .filter(WorkbenchCopilotActionModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotActionModel.requested_by == "COPILOT")
        .filter(WorkbenchCopilotActionModel.status == "EXECUTED")
        .filter(WorkbenchCopilotActionModel.action_type == "AUTO_TOOL_SCAN")
        .count()
    )
    snapshots_count = (
        db.query(WorkbenchCopilotSnapshotModel)
        .filter(WorkbenchCopilotSnapshotModel.copilot_session_id == int(copilot.id))
        .count()
    )
    jobs_pending = (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotJobModel.status == "PENDING")
        .count()
    )
    jobs_running = (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotJobModel.status == "RUNNING")
        .count()
    )
    jobs_completed = (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotJobModel.status == "APPLIED")
        .count()
    )
    jobs_failed = (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(copilot.id))
        .filter(WorkbenchCopilotJobModel.status == "FAILED")
        .count()
    )
    recent_events_rows = (
        db.query(WorkbenchCopilotEventModel)
        .filter(WorkbenchCopilotEventModel.copilot_session_id == int(copilot.id))
        .order_by(WorkbenchCopilotEventModel.created_at.desc())
        .limit(int(events_limit))
        .all()
    )
    recent_advice_rows = (
        db.query(WorkbenchCopilotAdviceModel)
        .filter(WorkbenchCopilotAdviceModel.copilot_session_id == int(copilot.id))
        .order_by(WorkbenchCopilotAdviceModel.created_at.desc())
        .limit(int(advices_limit))
        .all()
    )
    recent_snapshot_rows = (
        db.query(WorkbenchCopilotSnapshotModel)
        .filter(WorkbenchCopilotSnapshotModel.copilot_session_id == int(copilot.id))
        .order_by(WorkbenchCopilotSnapshotModel.created_at.desc())
        .limit(5)
        .all()
    )
    recent_action_rows = (
        db.query(WorkbenchCopilotActionModel)
        .filter(WorkbenchCopilotActionModel.copilot_session_id == int(copilot.id))
        .order_by(WorkbenchCopilotActionModel.created_at.desc())
        .limit(8)
        .all()
    )
    recent_job_rows = (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(copilot.id))
        .order_by(WorkbenchCopilotJobModel.created_at.desc())
        .limit(5)
        .all()
    )
    last_snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else {}
    last_meta = last_snapshot.get("__copilot_meta") if isinstance(last_snapshot.get("__copilot_meta"), dict) else {}
    clean_meta = _clean_snapshot_meta(last_meta)
    safe_cfg = _redact_sensitive_config(copilot.config_json if isinstance(copilot.config_json, dict) else {})
    runtime_summary = _runtime_summary(get_copilot_runtime(int(copilot.id)))
    guardrails = last_snapshot.get("guardrails") if isinstance(last_snapshot.get("guardrails"), dict) else {}
    if not guardrails:
        guardrails = {
            "manual_pause": bool(safe_cfg.get("auto_paper_manual_pause", False)),
            "blocked": bool(last_meta.get("guardrail_blocked", False)),
            "blocked_reason": str(last_meta.get("guardrail_reason") or "") or None,
        }
    return {
        "copilot_session_id": int(copilot.id),
        "agent_session_id": int(copilot.id),
        "simulation_session_id": int(copilot.simulation_session_id),
        "active": str(copilot.status or "STOPPED").upper() == "ACTIVE",
        "status": str(copilot.status or "STOPPED"),
        "mode": str(copilot.mode or "ADVISE"),
        "provider": str(copilot.provider or "deterministic"),
        "model_label": str(copilot.model_label or ""),
        "runtime": runtime_summary,
        "config": safe_cfg,
        "guardrails": guardrails,
        "last_snapshot": last_snapshot,
        "provider_used": str(last_meta.get("provider_used") or str(copilot.provider or "deterministic")),
        "provider_attempts": clean_meta.get("provider_attempts", []),
        "provider_fallback_reason": str(clean_meta.get("provider_fallback_reason") or ""),
        "counts": {
            "events": int(events_count),
            "advices": int(advices_count),
            "actions": int(actions_count),
            "copilot_actions_executed": int(copilot_actions_executed),
            "agent_actions_executed": int(copilot_actions_executed),
            "auto_tool_scans_executed": int(auto_tool_scans_executed),
            "agent_tool_scans_executed": int(auto_tool_scans_executed),
            "snapshots": int(snapshots_count),
            "jobs_pending": int(jobs_pending),
            "jobs_running": int(jobs_running),
            "jobs_completed": int(jobs_completed),
            "jobs_failed": int(jobs_failed),
        },
        "recent_events": [
            {
                "id": int(e.id),
                "event_type": str(e.event_type or ""),
                "severity": str(e.severity or "info"),
                "payload": e.payload_json if isinstance(e.payload_json, dict) else {},
                "created_at": e.created_at.isoformat() if e.created_at else None,
            }
            for e in recent_events_rows
        ],
        "recent_advices": [
            {
                "id": int(a.id),
                "event_id": int(a.event_id) if a.event_id is not None else None,
                "advice_type": str(a.advice_type or ""),
                "summary": str(a.summary or ""),
                "confidence": float(a.confidence) if a.confidence is not None else None,
                "evidence": a.evidence_json if isinstance(a.evidence_json, dict) else {},
                "action": a.action_json if isinstance(a.action_json, dict) else {},
                "source_event_priority": int(a.source_event_priority or 0),
                "delivery": str(a.delivery or ""),
                "status": str(a.status or "NEW"),
                "created_at": a.created_at.isoformat() if a.created_at else None,
            }
            for a in recent_advice_rows
        ],
        "recent_snapshots": [
            {
                "id": int(s.id),
                "bar_index": int(s.bar_index or 0),
                "source": str(s.source or "advance"),
                "created_at": s.created_at.isoformat() if s.created_at else None,
            }
            for s in recent_snapshot_rows
        ],
        "recent_actions": [
            {
                "id": int(a.id),
                "advice_id": int(a.advice_id) if a.advice_id is not None else None,
                "action_type": str(a.action_type or ""),
                "requested_by": str(a.requested_by or ""),
                "status": str(a.status or ""),
                "note": str(a.note or "") if a.note is not None else None,
                "payload": a.payload_json if isinstance(a.payload_json, dict) else {},
                "created_at": a.created_at.isoformat() if a.created_at else None,
            }
            for a in recent_action_rows
        ],
        "recent_jobs": [
            {
                "id": int(j.id),
                "status": str(j.status or ""),
                "job_type": str(j.job_type or ""),
                "attempts": int(j.attempts or 0),
                "error": str(j.error or "")[:200] if j.error else None,
                "created_at": j.created_at.isoformat() if j.created_at else None,
                "started_at": j.started_at.isoformat() if j.started_at else None,
                "finished_at": j.finished_at.isoformat() if j.finished_at else None,
            }
            for j in recent_job_rows
        ],
        "created_at": copilot.created_at.isoformat() if copilot.created_at else None,
        "updated_at": copilot.updated_at.isoformat() if copilot.updated_at else None,
        "stopped_at": copilot.stopped_at.isoformat() if copilot.stopped_at else None,
    }


def _record_copilot_iteration(
    session: SimulationSession,
    advance_result: Dict[str, Any],
    db: Session,
    auto_commit: bool = True,
) -> None:
    """If an active copilot exists, persist events/advices for this iteration."""
    copilot = _get_active_copilot(int(session.id), db)
    if not copilot:
        return
    _apply_completed_copilot_jobs(copilot=copilot, db=db, max_jobs=5)

    prev_snapshot = copilot.last_snapshot_json if isinstance(copilot.last_snapshot_json, dict) else None
    config = copilot.config_json if isinstance(copilot.config_json, dict) else {}
    provider = str(copilot.provider or "deterministic").strip().lower()
    chain = config.get("provider_chain") if isinstance(config.get("provider_chain"), list) else []
    has_non_deterministic = (provider != "deterministic") or any(
        str(p or "").strip().lower() != "deterministic" for p in chain
    )
    use_async_jobs = bool(config.get("async_llm_jobs", True)) and has_non_deterministic
    provider_for_sync = "deterministic" if use_async_jobs else provider
    snapshot, events, advices = process_copilot_iteration(
        prev_snapshot=prev_snapshot,
        session=session,
        advance_result=advance_result,
        mode=str(copilot.mode or "ADVISE"),
        provider=provider_for_sync,
        model_label=str(copilot.model_label or ""),
        config=config,
    )
    copilot.last_snapshot_json = snapshot
    copilot.updated_at = datetime.utcnow()
    _store_copilot_snapshot(copilot=copilot, snapshot=snapshot, db=db, source="advance")

    event_id_by_type: Dict[str, int] = {}
    for ev in events:
        ev_payload = ev.get("payload") if isinstance(ev.get("payload"), dict) else {}
        ev_payload = {**ev_payload, "_priority": int(ev.get("priority") or 0)}
        event_row = _emit_copilot_event(
            copilot=copilot,
            event_type=str(ev.get("event_type") or "UNKNOWN"),
            severity=str(ev.get("severity") or "info"),
            payload=ev_payload,
            db=db,
        )
        if event_row is not None:
            event_id_by_type[str(event_row.event_type)] = int(event_row.id)

    if use_async_jobs:
        enqueued = _enqueue_copilot_advice_job(
            copilot=copilot,
            snapshot=snapshot,
            events=events,
            config=config,
            event_id_by_type=event_id_by_type,
            db=db,
        )
        if enqueued:
            if auto_commit:
                db.commit()
            else:
                db.flush()
            return

    for adv in advices:
        source_event_type = str(adv.get("source_event_type") or "")
        evidence_json = adv.get("evidence_json") if isinstance(adv.get("evidence_json"), dict) else {}
        evidence_json = {
            **evidence_json,
            "_event_priority": int(adv.get("source_event_priority") or 0),
        }
        action_json = adv.get("action_json") if isinstance(adv.get("action_json"), dict) else {}
        action_json = {
            **action_json,
            "delivery": str(adv.get("delivery") or "ACTIONABLE"),
        }
        advice_row = WorkbenchCopilotAdviceModel(
            copilot_session_id=int(copilot.id),
            event_id=event_id_by_type.get(source_event_type),
            advice_type=str(adv.get("advice_type") or "REVIEW_NOTE"),
            summary=str(adv.get("summary") or ""),
            confidence=float(adv.get("confidence")) if adv.get("confidence") is not None else None,
            source_event_priority=int(adv.get("source_event_priority") or 0),
            delivery=str(adv.get("delivery") or "ACTIONABLE"),
            evidence_json=evidence_json,
            action_json=action_json,
            status=str(adv.get("status") or "NEW"),
            created_at=datetime.utcnow(),
        )
        db.add(advice_row)
    db.flush()
    _maybe_apply_auto_paper_actions(
        copilot=copilot,
        session=session,
        db=db,
        max_actions=1,
    )
    if auto_commit:
        db.commit()
    else:
        db.flush()


# ── Endpoints ──────────────────────────────────────────────────

@router.post("/sessions")
def create_session(req: CreateSessionRequest, db: Session = Depends(get_db)):
    """Create a new simulation session."""
    supported_ids = set(_supported_strategy_ids())
    if req.strategy_id != WORKBENCH_ID and req.strategy_id not in supported_ids:
        raise HTTPException(400, f"Unsupported simulation strategy: {req.strategy_id}")

    config = req.config or {}
    config["initial_balance"] = req.initial_balance
    if req.strategy_id == WORKBENCH_ID:
        cm = config.get("cost_model") if isinstance(config.get("cost_model"), dict) else {}
        spread_source = str(cm.get("spread_source") or _COST_SPREAD_SOURCE_MANUAL).strip().lower()
        if spread_source not in {_COST_SPREAD_SOURCE_MANUAL, _COST_SPREAD_SOURCE_MT5}:
            spread_source = _COST_SPREAD_SOURCE_MANUAL
        config["cost_model"] = {
            "enabled": bool(cm.get("enabled", True)),
            "spread": float(cm.get("spread") if cm.get("spread") is not None else INSTRUMENT_SPREAD.get(str(req.symbol or "").upper(), 0.30)),
            "tc_rate": float(cm.get("tc_rate") if cm.get("tc_rate") is not None else DEFAULT_TC_RATE),
            "spread_source": spread_source,
        }

    session = SimulationSession(
        strategy_id=req.strategy_id,
        symbol=req.symbol,
        timeframe=req.timeframe,
        data_file=req.data_file,
        initial_balance=req.initial_balance,
        current_balance=req.initial_balance,
        config_json=json.dumps(config),
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    # Create engine immediately and require usable replay data.
    try:
        engine = _get_or_create_engine(session, db)
        if engine.total_bars <= 0:
            # Live-mode bootstrap path: allow session creation with no replay CSV bars.
            # MT5/Databento live feeds can populate runtime bars after session start.
            if bool(req.allow_empty_replay) and str(req.strategy_id or "") == WORKBENCH_ID:
                session.total_bars = 0
                session.current_bar = 0
                db.commit()
                logger.info(
                    "create_session live bootstrap without replay data: session=%s symbol=%s timeframe=%s",
                    int(session.id),
                    str(req.symbol or "").upper(),
                    str(req.timeframe or "").upper(),
                )
            else:
                raise HTTPException(
                    400,
                    f"No replay data loaded for {req.symbol} {req.timeframe}. "
                    "Check data files and CSV format.",
                )
        else:
            session.total_bars = engine.total_bars
            db.commit()
    except HTTPException:
        _clear_cached_engine(session.id)
        db.delete(session)
        db.commit()
        raise
    except Exception as e:
        _clear_cached_engine(session.id)
        db.delete(session)
        db.commit()
        raise HTTPException(400, f"Unable to initialize simulation session: {e}")

    return {
        "id": session.id,
        "strategy_id": session.strategy_id,
        "symbol": session.symbol,
        "timeframe": session.timeframe,
        "total_bars": session.total_bars,
        "initial_balance": session.initial_balance,
        "status": session.status,
        "cost_model": (config.get("cost_model") if isinstance(config.get("cost_model"), dict) else None),
    }


@router.get("/sessions")
def list_sessions(
    strategy_id: Optional[str] = Query(default=None),
    status: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
):
    """List recent simulation sessions for session switching/multi-session workflows."""
    q = db.query(SimulationSession)
    if strategy_id is not None and str(strategy_id).strip():
        q = q.filter(SimulationSession.strategy_id == str(strategy_id).strip())
    if status is not None and str(status).strip():
        q = q.filter(SimulationSession.status == str(status).strip().lower())
    rows = q.order_by(desc(SimulationSession.updated_at), desc(SimulationSession.id)).limit(int(limit)).all()
    out = []
    for s in rows:
        out.append(
            {
                "id": int(s.id),
                "strategy_id": str(s.strategy_id or ""),
                "symbol": str(s.symbol or ""),
                "timeframe": str(s.timeframe or ""),
                "mode": str(s.mode or ""),
                "status": str(s.status or ""),
                "current_bar": int(s.current_bar or 0),
                "total_bars": int(s.total_bars or 0),
                "initial_balance": float(s.initial_balance or 0.0),
                "current_balance": float(s.current_balance or 0.0),
                "total_pnl": float(s.total_pnl or 0.0),
                "trades_count": int(s.trades_count or 0),
                "updated_at": s.updated_at.isoformat() if getattr(s, "updated_at", None) else None,
            }
        )
    return {"ok": True, "count": len(out), "sessions": out}


@router.get("/sessions/{session_id}")
def get_session(session_id: int, db: Session = Depends(get_db)):
    """Get session state."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    trades = db.query(SimulationTrade).filter(
        SimulationTrade.session_id == session_id
    ).order_by(SimulationTrade.id.desc()).limit(50).all()

    cfg = _session_config_dict(session)
    return {
        "id": session.id,
        "strategy_id": session.strategy_id,
        "symbol": session.symbol,
        "timeframe": session.timeframe,
        "mode": session.mode,
        "current_bar": session.current_bar,
        "total_bars": session.total_bars,
        "initial_balance": session.initial_balance,
        "current_balance": session.current_balance,
        "total_pnl": session.total_pnl,
        "trades_count": session.trades_count,
        "wins": session.wins,
        "losses": session.losses,
        "status": session.status,
        "cost_model": cfg.get("cost_model") if isinstance(cfg.get("cost_model"), dict) else None,
        "trades": [
            {
                "id": t.id,
                "direction": t.direction,
                "entry_price": t.entry_price,
                "entry_mid_price": t.entry_mid_price,
                "entry_fill_price": t.entry_fill_price,
                "spread_value": t.spread_value,
                "tc_rate": t.tc_rate,
                "stop_loss": t.stop_loss,
                "take_profit": t.take_profit,
                "lot_size": t.lot_size,
                "exit_price": t.exit_price,
                "exit_mid_price": t.exit_mid_price,
                "exit_fill_price": t.exit_fill_price,
                "raw_pnl": t.raw_pnl,
                "spread_cost": t.spread_cost,
                "turnover_cost": t.turnover_cost,
                "total_cost": t.total_cost,
                "cost_breakdown": t.cost_breakdown_json,
                "pnl": t.pnl,
                "r_multiple": t.r_multiple,
                "status": t.status,
                "exit_reason": t.exit_reason,
            }
            for t in trades
        ],
    }


@router.post("/sessions/{session_id}/cost-model")
def update_session_cost_model(session_id: int, req: CostModelUpdateRequest, db: Session = Depends(get_db)):
    """Update per-session workbench cost model config."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    cfg = _session_config_dict(session)
    cm = cfg.get("cost_model") if isinstance(cfg.get("cost_model"), dict) else {}
    symbol = str(session.symbol or "").upper()
    default_spread = float(INSTRUMENT_SPREAD.get(symbol, 0.30))
    current_enabled = bool(cm.get("enabled", str(session.strategy_id or "").strip().lower() == WORKBENCH_ID))
    current_spread = _to_float_or_none(cm.get("spread"))
    current_tc = _to_float_or_none(cm.get("tc_rate"))
    current_source = str(cm.get("spread_source") or _COST_SPREAD_SOURCE_MANUAL).strip().lower()
    if current_source not in {_COST_SPREAD_SOURCE_MANUAL, _COST_SPREAD_SOURCE_MT5}:
        current_source = _COST_SPREAD_SOURCE_MANUAL
    next_enabled = current_enabled if req.enabled is None else bool(req.enabled)
    next_spread = current_spread if req.spread is None else max(0.0, float(req.spread))
    next_tc = current_tc if req.tc_rate is None else max(0.0, float(req.tc_rate))
    next_source = current_source if req.spread_source is None else str(req.spread_source).strip().lower()
    if next_source not in {_COST_SPREAD_SOURCE_MANUAL, _COST_SPREAD_SOURCE_MT5}:
        next_source = _COST_SPREAD_SOURCE_MANUAL
    cfg["cost_model"] = {
        "enabled": bool(next_enabled),
        "spread": float(default_spread if next_spread is None else next_spread),
        "tc_rate": float(DEFAULT_TC_RATE if next_tc is None else next_tc),
        "spread_source": next_source,
    }
    session.config_json = json.dumps(cfg)
    session.updated_at = datetime.utcnow()
    db.commit()

    return {
        "ok": True,
        "session_id": int(session.id),
        "cost_model": cfg["cost_model"],
    }


@router.delete("/sessions/{session_id}")
def delete_session(session_id: int, db: Session = Depends(get_db)):
    """End and delete a simulation session."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    # Clean up engine cache
    _clear_cached_engine(session_id)

    agent_rows = (
        db.query(WorkbenchAgentSessionModel)
        .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
        .all()
    )
    for a in agent_rows:
        db.query(WorkbenchAgentActionModel).filter(WorkbenchAgentActionModel.agent_session_id == int(a.id)).delete()
        db.query(WorkbenchAgentEventModel).filter(WorkbenchAgentEventModel.agent_session_id == int(a.id)).delete()
        db.query(WorkbenchAgentSnapshotModel).filter(WorkbenchAgentSnapshotModel.agent_session_id == int(a.id)).delete()
        db.delete(a)

    copilot_rows = (
        db.query(WorkbenchCopilotSessionModel)
        .filter(WorkbenchCopilotSessionModel.simulation_session_id == int(session_id))
        .all()
    )
    for c in copilot_rows:
        clear_copilot_runtime(int(c.id))
        db.query(WorkbenchCopilotJobModel).filter(WorkbenchCopilotJobModel.copilot_session_id == int(c.id)).delete()
        db.query(WorkbenchCopilotActionModel).filter(WorkbenchCopilotActionModel.copilot_session_id == int(c.id)).delete()
        db.query(WorkbenchCopilotAdviceModel).filter(WorkbenchCopilotAdviceModel.copilot_session_id == int(c.id)).delete()
        db.query(WorkbenchCopilotEventModel).filter(WorkbenchCopilotEventModel.copilot_session_id == int(c.id)).delete()
        db.query(WorkbenchCopilotSnapshotModel).filter(WorkbenchCopilotSnapshotModel.copilot_session_id == int(c.id)).delete()
        db.delete(c)

    # Delete trades and session
    db.query(SimulationTrade).filter(SimulationTrade.session_id == session_id).delete()
    db.delete(session)
    db.commit()
    return {"ok": True}


@router.post("/sessions/{session_id}/advance")
def advance_bars(session_id: int, req: AdvanceRequest, db: Session = Depends(get_db)):
    """Advance N bars. Returns new bars, indicators, step states, trade updates."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if session.status != "active":
        raise HTTPException(400, "Session is not active")

    engine = _get_or_create_engine(session, db)
    return _run_advance(session, engine, req.count, req.indicators_mode, db)


@router.post("/sessions/{session_id}/seek")
def seek_bar(
    session_id: int,
    bar: int = Query(..., ge=0),
    include_bars: bool = Query(default=False),
    bars_limit: int = Query(default=1500, ge=100, le=10000),
    db: Session = Depends(get_db),
):
    """Seek to a specific bar position (for rewind sync)."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    engine = _get_or_create_engine(session, db)
    prev_bar = int(session.current_bar or 0)
    target = min(bar, engine.total_bars - 1) if engine.total_bars > 0 else 0
    target = max(target, 0)
    engine = _restore_engine_state_for_bar(engine, session, target, db)

    session.status = "completed" if engine.total_bars > 0 and target >= (engine.total_bars - 1) else "active"
    _sync_session(session, engine, db)

    # Re-evaluate steps and indicators at the new position
    indicators = engine._compute_indicators()
    steps = engine._evaluate_steps()
    overlays = engine._get_chart_overlays()
    suggestion = engine._get_strategy_suggestion()
    open_pnl = engine._compute_open_pnl()

    payload = {
        "current_bar": engine.current_bar,
        "total_bars": engine.total_bars,
        "indicators": indicators,
        "indicators_mode": "full",
        "steps": steps,
        "overlays": overlays,
        "suggestion": suggestion,
        "open_pnl": open_pnl,
        "open_positions": engine.open_positions,
        "balance": engine.balance,
        "initial_balance": session.initial_balance,
        "trades_count": session.trades_count,
        "wins": session.wins,
        "losses": session.losses,
        "total_pnl": session.total_pnl,
    }

    if include_bars and engine.df is not None and not engine.df.empty:
        start_idx = max(0, (target + 1) - int(bars_limit))
        bars_df = engine.df.iloc[start_idx: target + 1]
        bars = []
        for ts, row in bars_df.iterrows():
            bars.append(
                {
                    "time": int(ts.timestamp()) if hasattr(ts, "timestamp") else 0,
                    "open": float(row.get("open", 0.0)),
                    "high": float(row.get("high", 0.0)),
                    "low": float(row.get("low", 0.0)),
                    "close": float(row.get("close", 0.0)),
                    "volume": float(row.get("volume", 0.0)),
                }
            )
        payload["bars"] = bars
        payload["bars_start_index"] = start_idx

    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="MANUAL_OVERRIDE",
        payload={
            "override_type": "SEEK",
            "from_bar": prev_bar,
            "to_bar": int(target),
            "include_bars": bool(include_bars),
        },
        severity="info",
        db=db,
    )
    _store_external_snapshot(
        simulation_session=session,
        db=db,
        source="seek",
        patch={
            "current_bar": int(target),
            "last_override": {"type": "SEEK", "from_bar": prev_bar, "to_bar": int(target)},
        },
    )
    return payload


@router.post("/sessions/{session_id}/reset")
def reset_session(session_id: int, db: Session = Depends(get_db)):
    """Reset session to bar 0."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    prev_bar = int(session.current_bar or 0)

    # Clear trades
    db.query(SimulationTrade).filter(SimulationTrade.session_id == session_id).delete()

    # Reset session state
    session.current_bar = 0
    session.current_balance = session.initial_balance
    session.total_pnl = 0.0
    session.trades_count = 0
    session.wins = 0
    session.losses = 0
    session.status = "active"
    db.commit()

    # Destroy cached engine (will be re-created on next advance)
    _clear_cached_engine(session_id)

    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="MANUAL_OVERRIDE",
        payload={
            "override_type": "RESET",
            "from_bar": prev_bar,
            "to_bar": 0,
        },
        severity="info",
        db=db,
    )
    _store_external_snapshot(
        simulation_session=session,
        db=db,
        source="reset",
        patch={
            "current_bar": 0,
            "last_override": {"type": "RESET", "from_bar": prev_bar, "to_bar": 0},
        },
    )

    return {"ok": True, "status": "active"}


@router.post("/sessions/{session_id}/trade")
def execute_trade(session_id: int, req: TradeRequest, db: Session = Depends(get_db)):
    """Execute a manual trade in the simulation."""
    auto_commit = not bool(getattr(db, "_suppress_commit", False))
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if session.status != "active":
        raise HTTPException(400, "Session is not active")

    engine = _get_or_create_engine(session, db)

    # Check for existing open position
    open_count = db.query(SimulationTrade).filter(
        SimulationTrade.session_id == session_id,
        SimulationTrade.status == "open",
    ).count()
    if open_count > 0:
        raise HTTPException(400, "Already have an open position. Close it first.")

    if req.direction not in ("BUY", "SELL"):
        raise HTTPException(400, "Direction must be BUY or SELL")

    entry_mid = _to_float_or_none(req.entry_price)
    if entry_mid is None:
        if engine.df is None or engine.df.empty or engine.current_bar >= engine.total_bars:
            raise HTTPException(400, "No market data available for trade entry price")
        entry_mid = float(engine.df.iloc[engine.current_bar]["close"])
    use_cost_model = _is_cost_model_enabled(session)
    cm = _session_cost_model(session, req.cost_spread, req.cost_tc_rate, req.cost_spread_source) if use_cost_model else None
    entry_fill = float(entry_mid)
    if use_cost_model and cm is not None:
        open_side = "buy" if str(req.direction).upper() == "BUY" else "sell"
        entry_fill = float(cm.apply_fill_spread(float(entry_mid), open_side))

    trade_result = engine.execute_trade(
        direction=req.direction,
        sl=req.stop_loss,
        tp=req.take_profit,
        lot_size=req.lot_size,
        entry_price_override=entry_fill,
        entry_time_unix=req.bar_time_unix,
    )

    # Persist trade to DB
    trade = SimulationTrade(
        session_id=session_id,
        direction=req.direction,
        entry_price=float(trade_result["entry_price"]),
        entry_bar=trade_result["entry_bar"],
        entry_time=trade_result.get("entry_time"),
        stop_loss=req.stop_loss,
        take_profit=req.take_profit,
        lot_size=req.lot_size,
        entry_mid_price=float(entry_mid),
        entry_fill_price=float(entry_fill),
        spread_value=float(cm.spread) if use_cost_model and cm is not None else None,
        tc_rate=float(cm.tc_rate) if use_cost_model and cm is not None else None,
    )
    db.add(trade)
    if auto_commit:
        db.commit()
    else:
        db.flush()
    db.refresh(trade)

    # Update engine's position with DB id
    if engine.open_positions:
        engine.open_positions[-1]["id"] = trade.id

    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="TRADE_OPENED",
        payload={
            "trade_id": int(trade.id),
            "direction": str(trade.direction or ""),
            "entry_price": float(trade.entry_price),
            "stop_loss": float(trade.stop_loss),
            "take_profit": float(trade.take_profit) if trade.take_profit is not None else None,
            "lot_size": float(trade.lot_size or 0.0),
        },
        severity="info",
        db=db,
        auto_commit=auto_commit,
    )
    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="MANUAL_OVERRIDE",
        payload={
            "override_type": "MANUAL_TRADE_ENTRY",
            "trade_id": int(trade.id),
        },
        severity="info",
        db=db,
        auto_commit=auto_commit,
    )
    _store_external_snapshot(
        simulation_session=session,
        db=db,
        source="manual",
        patch={
            "open_positions_count": int(len(engine.open_positions or [])),
            "last_manual_action": {"type": "MANUAL_TRADE_ENTRY", "trade_id": int(trade.id)},
        },
        auto_commit=auto_commit,
    )

    return {
        "id": trade.id,
        "direction": trade.direction,
        "entry_price": trade.entry_price,
        "entry_mid_price": trade.entry_mid_price,
        "entry_fill_price": trade.entry_fill_price,
        "entry_bar": trade.entry_bar,
        "stop_loss": trade.stop_loss,
        "take_profit": trade.take_profit,
        "lot_size": trade.lot_size,
        "spread_value": trade.spread_value,
        "tc_rate": trade.tc_rate,
        "status": "open",
    }


@router.post("/sessions/{session_id}/close-trade/{trade_id}")
def close_trade(
    session_id: int,
    trade_id: int,
    req: CloseTradeRequest = Body(default_factory=CloseTradeRequest),
    db: Session = Depends(get_db),
):
    """Manually close an open position."""
    auto_commit = not bool(getattr(db, "_suppress_commit", False))
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    trade = db.query(SimulationTrade).get(trade_id)
    if not trade or trade.session_id != session_id:
        raise HTTPException(404, "Trade not found in this session")
    if trade.status != "open":
        raise HTTPException(400, "Trade is already closed")

    engine = _get_or_create_engine(session, db)
    exit_mid = _to_float_or_none(req.exit_price)
    if exit_mid is None:
        if engine.df is None or engine.df.empty or engine.current_bar >= engine.total_bars:
            raise HTTPException(400, "No market data available for close exit price")
        exit_mid = float(engine.df.iloc[engine.current_bar]["close"])
    use_cost_model = _is_cost_model_enabled(session)
    cm = _session_cost_model(session, req.cost_spread, req.cost_tc_rate, req.cost_spread_source) if use_cost_model else None
    exit_fill = float(exit_mid)
    if use_cost_model and cm is not None:
        close_side = "sell" if str(trade.direction or "").upper() == "BUY" else "buy"
        exit_fill = float(cm.apply_fill_spread(float(exit_mid), close_side))

    close_result = engine.close_position(
        trade_id,
        exit_price_override=exit_fill,
        exit_time_unix=req.bar_time_unix,
    )
    if use_cost_model and cm is not None:
        close_result = _apply_close_cost_adjustment(
            session=session,
            engine=engine,
            trade=trade,
            close_result=close_result,
            exit_mid_price=float(exit_mid),
            cost_model=cm,
        )

    trade.exit_price = _to_float_or_none(close_result.get("exit_price"))
    trade.exit_mid_price = float(exit_mid)
    trade.exit_fill_price = _to_float_or_none(close_result.get("exit_price"))
    trade.exit_bar = close_result["exit_bar"]
    trade.exit_time = close_result.get("exit_time")
    trade.exit_reason = "manual"
    trade.raw_pnl = _to_float_or_none(close_result.get("raw_pnl")) if close_result.get("raw_pnl") is not None else _to_float_or_none(close_result.get("pnl"))
    trade.pnl = _to_float_or_none(close_result.get("pnl"))
    trade.spread_cost = _to_float_or_none(close_result.get("spread_cost")) if close_result.get("spread_cost") is not None else 0.0
    trade.turnover_cost = _to_float_or_none(close_result.get("turnover_cost")) if close_result.get("turnover_cost") is not None else 0.0
    trade.total_cost = _to_float_or_none(close_result.get("total_cost")) if close_result.get("total_cost") is not None else 0.0
    trade.cost_breakdown_json = close_result.get("cost_breakdown") if isinstance(close_result.get("cost_breakdown"), dict) else None
    trade.r_multiple = close_result.get("r_multiple")
    trade.status = "closed"

    _sync_session_from_engine_no_commit(session, engine)
    if auto_commit:
        db.commit()
    else:
        db.flush()

    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="TRADE_CLOSED",
        payload={
            "trade_id": int(trade.id),
            "exit_price": float(trade.exit_price) if trade.exit_price is not None else None,
            "pnl": float(trade.pnl) if trade.pnl is not None else None,
            "r_multiple": float(trade.r_multiple) if trade.r_multiple is not None else None,
            "exit_reason": str(trade.exit_reason or "manual"),
        },
        severity="info",
        db=db,
        auto_commit=auto_commit,
    )
    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="MANUAL_OVERRIDE",
        payload={
            "override_type": "MANUAL_TRADE_CLOSE",
            "trade_id": int(trade.id),
        },
        severity="info",
        db=db,
        auto_commit=auto_commit,
    )
    _store_external_snapshot(
        simulation_session=session,
        db=db,
        source="manual",
        patch={
            "open_positions_count": int(len(engine.open_positions or [])),
            "last_manual_action": {"type": "MANUAL_TRADE_CLOSE", "trade_id": int(trade.id)},
        },
        auto_commit=auto_commit,
    )

    return {
        "id": trade.id,
        "direction": trade.direction,
        "entry_price": trade.entry_price,
        "exit_price": trade.exit_price,
        "exit_mid_price": trade.exit_mid_price,
        "exit_fill_price": trade.exit_fill_price,
        "stop_loss": trade.stop_loss,
        "take_profit": trade.take_profit,
        "lot_size": trade.lot_size,
        "spread_value": trade.spread_value,
        "tc_rate": trade.tc_rate,
        "raw_pnl": trade.raw_pnl,
        "spread_cost": trade.spread_cost,
        "turnover_cost": trade.turnover_cost,
        "total_cost": trade.total_cost,
        "cost_breakdown": trade.cost_breakdown_json,
        "pnl": trade.pnl,
        "r_multiple": trade.r_multiple,
        "exit_reason": trade.exit_reason,
        "status": "closed",
    }


@router.get("/sessions/{session_id}/performance")
def get_performance(session_id: int, db: Session = Depends(get_db)):
    """Get performance stats and trade log."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    trades = db.query(SimulationTrade).filter(
        SimulationTrade.session_id == session_id,
        SimulationTrade.status == "closed",
    ).order_by(SimulationTrade.id).all()

    pnls = [t.pnl or 0 for t in trades]
    wins = [p for p in pnls if p > 0]
    losses = [p for p in pnls if p < 0]
    breakevens = [p for p in pnls if p == 0]

    return {
        "total_trades": len(trades),
        "wins": len(wins),
        "losses": len(losses),
        "breakevens": len(breakevens),
        "win_rate": (len(wins) / len(trades) * 100) if trades else 0,
        "total_pnl": sum(pnls),
        "avg_win": (sum(wins) / len(wins)) if wins else 0,
        "avg_loss": (sum(losses) / len(losses)) if losses else 0,
        "avg_r": (sum(t.r_multiple or 0 for t in trades) / len(trades)) if trades else 0,
        "initial_balance": session.initial_balance,
        "current_balance": session.current_balance,
        "trade_log": [
            {
                "id": t.id,
                "direction": t.direction,
                "entry_price": t.entry_price,
                "entry_mid_price": t.entry_mid_price,
                "entry_fill_price": t.entry_fill_price,
                "spread_value": t.spread_value,
                "tc_rate": t.tc_rate,
                "exit_price": t.exit_price,
                "exit_mid_price": t.exit_mid_price,
                "exit_fill_price": t.exit_fill_price,
                "stop_loss": t.stop_loss,
                "take_profit": t.take_profit,
                "raw_pnl": t.raw_pnl,
                "spread_cost": t.spread_cost,
                "turnover_cost": t.turnover_cost,
                "total_cost": t.total_cost,
                "cost_breakdown": t.cost_breakdown_json,
                "pnl": t.pnl,
                "r_multiple": t.r_multiple,
                "exit_reason": t.exit_reason,
                "entry_time": t.entry_time,
                "exit_time": t.exit_time,
            }
            for t in trades
        ],
    }


@router.get("/strategies")
def list_simulation_strategies():
    """List registered strategies that can actually run in simulation."""
    try:
        all_steps = get_all_strategy_steps()
        items = []
        for s in StrategyRegistry.get_all_strategies():
            if create_strategy(s.id, {}) is None:
                continue
            steps = all_steps.get(s.id) or _default_steps_for_strategy(s.id)
            items.append(
                {
                    "strategy_id": s.id,
                    "name": steps.get("name", s.name),
                    "step_count": len(steps.get("steps", [])),
                }
            )
        return items
    except Exception as e:
        logger.error(f"Error loading step definitions: {e}")
        return []


@router.get("/strategies/{strategy_id}/steps")
def get_strategy_steps(strategy_id: str):
    """Get step definitions for one strategy."""
    if strategy_id not in set(_supported_strategy_ids()):
        raise HTTPException(404, f"Strategy not available for simulation: {strategy_id}")
    steps = get_step_definitions(strategy_id) or _default_steps_for_strategy(strategy_id)
    return steps


@router.get("/data-files")
def list_data_files(
    symbol: Optional[str] = None,
    timeframe: Optional[str] = None,
):
    """List available CSV files for replay."""
    from pathlib import Path

    data_dir = Path(__file__).resolve().parents[2] / "data" / "historical"
    if not data_dir.exists():
        return []

    files = []
    for f in sorted(data_dir.glob("*.csv")):
        name = f.stem.upper()
        # Try to extract symbol and timeframe from filename
        parts = name.split("_")
        file_symbol = parts[0] if parts else ""
        file_tf = parts[1] if len(parts) > 1 else ""

        if symbol and symbol.upper() != file_symbol:
            continue
        if timeframe and timeframe.upper() != file_tf:
            continue

        size_mb = f.stat().st_size / (1024 * 1024)
        files.append({
            "filename": f.name,
            "symbol": file_symbol,
            "timeframe": file_tf,
            "size_mb": round(size_mb, 2),
        })

    return files


@router.websocket("/ws/sessions/{session_id}/play")
async def ws_playback(
    websocket: WebSocket,
    session_id: int,
    speed: int = Query(default=1, ge=1, le=100),
    tick_ms: int = Query(default=500, ge=20, le=5000),
    indicators_mode: str = Query(default="delta"),
):
    """
    Stream replay ticks over WebSocket for lower-overhead playback.
    HTTP endpoints remain as fallback.
    """
    await websocket.accept()
    db = SessionLocal()
    try:
        session = db.query(SimulationSession).get(session_id)
        if not session:
            await websocket.send_json({"type": "error", "message": "Session not found"})
            await websocket.close(code=4404)
            return
        if session.status != "active":
            await websocket.send_json({"type": "completed", "message": f"Session status: {session.status}"})
            await websocket.close()
            return

        await websocket.send_json(
            {
                "type": "ready",
                "session_id": session_id,
                "speed": speed,
                "tick_ms": tick_ms,
                "indicators_mode": indicators_mode,
            }
        )

        while True:
            session = db.query(SimulationSession).get(session_id)
            if not session:
                await websocket.send_json({"type": "error", "message": "Session not found"})
                break
            if session.status != "active":
                await websocket.send_json({"type": "completed", "message": f"Session status: {session.status}"})
                break

            engine = _get_or_create_engine(session, db)
            if engine.total_bars <= 0 or engine.current_bar >= engine.total_bars - 1:
                session.status = "completed"
                db.commit()
                await websocket.send_json({"type": "completed", "message": "Replay complete"})
                break

            payload = _run_advance(session, engine, speed, indicators_mode, db)
            await websocket.send_json({"type": "tick", "data": payload})
            await asyncio.sleep(max(0.02, tick_ms / 1000.0))
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        try:
            await websocket.send_json({"type": "error", "message": str(exc)})
        except Exception:
            pass
    finally:
        db.close()


# ── Workbench Tool Endpoints ──────────────────────────────────────────

@router.get("/mt5/status")
def simulation_mt5_status(
    symbol: str = Query(default="XAUUSD"),
    timeframe: str = Query(default="M15"),
):
    """MT5 readiness/status for simulation live candle streaming."""
    try:
        service = _get_mt5_service_singleton()
        status = service.get_status(symbol=symbol)
        candle = service.get_current_candle(symbol=symbol, timeframe=timeframe)
        sym_info = service.get_symbol_info(symbol=symbol)
        resolved_symbol = (
            candle.get("resolved_symbol")
            if isinstance(candle.get("resolved_symbol"), str)
            else status.get("symbol_resolved")
        )
        connected = bool(status.get("mt5_available")) and ("error" not in candle)
        status_error = None
        if not connected:
            if isinstance(candle, dict) and str(candle.get("error") or "").strip():
                status_error = str(candle.get("error") or "").strip()
            elif isinstance(sym_info, dict) and str(sym_info.get("error") or "").strip():
                status_error = str(sym_info.get("error") or "").strip()
        return {
            "ok": True,
            "symbol": str(symbol).upper(),
            "resolved_symbol": str(resolved_symbol or ""),
            "timeframe": str(timeframe).upper(),
            "mt5_connected": connected,
            "error": status_error,
            "status": status,
            "current_candle": candle,
            "symbol_info": sym_info,
        }
    except Exception as exc:
        return {
            "ok": False,
            "symbol": str(symbol).upper(),
            "timeframe": str(timeframe).upper(),
            "mt5_connected": False,
            "error": f"{type(exc).__name__}: {str(exc)}",
        }


@router.get("/mt5/symbols")
def simulation_mt5_symbols(
    search: str = Query(default=""),
    limit: int = Query(default=800, ge=1, le=5000),
    include_hidden: bool = Query(default=True),
):
    """Return broker symbols from active MT5 terminal for broker-independent symbol selection."""
    try:
        service = _get_mt5_service_singleton()
        rows = service.list_symbols(search=search, limit=limit, include_hidden=include_hidden)
        return {
            "ok": True,
            "count": int(len(rows)),
            "symbols": rows,
        }
    except Exception as exc:
        return {
            "ok": False,
            "count": 0,
            "symbols": [],
            "error": f"{type(exc).__name__}: {str(exc)}",
        }


@router.websocket("/ws/mt5/live")
async def ws_mt5_live(
    websocket: WebSocket,
    symbol: str = Query(default="XAUUSD"),
    timeframe: str = Query(default="M15"),
    history: int = Query(default=300, ge=2, le=10000),
    poll_ms: int = Query(default=1000, ge=250, le=10000),
):
    """
    Stream live MT5 candles for Workbench chart view.

    Messages:
    - {"type":"snapshot","bars":[...]}
    - {"type":"tick","bars":[latest_bar]}
    - {"type":"warning","message":"..."}
    - {"type":"error","message":"..."}
    """
    await websocket.accept()
    try:
        service = _get_mt5_service_singleton()
        symbol_u = str(symbol or "XAUUSD").upper()
        tf_u = str(timeframe or "M15").upper()

        bars = service.get_recent_candles(symbol=symbol_u, timeframe=tf_u, count=history)
        if not bars:
            await websocket.send_json({"type": "error", "message": f"No MT5 candle data for {symbol_u} {tf_u}"})
            await websocket.close(code=4404)
            return

        snapshot_bars = [
            {
                "time": int(b.get("time_unix") or 0),
                "open": float(b.get("open") or 0.0),
                "high": float(b.get("high") or 0.0),
                "low": float(b.get("low") or 0.0),
                "close": float(b.get("close") or 0.0),
                "volume": int(b.get("volume") or 0),
            }
            for b in bars
        ]
        await websocket.send_json(
            {
                "type": "snapshot",
                "symbol": symbol_u,
                "resolved_symbol": str(bars[-1].get("symbol") or ""),
                "timeframe": tf_u,
                "bars": snapshot_bars,
            }
        )

        last_sig = None
        while True:
            latest = service.get_recent_candles(symbol=symbol_u, timeframe=tf_u, count=2)
            if not latest:
                await websocket.send_json(
                    {
                        "type": "warning",
                        "message": f"No MT5 update for {symbol_u} {tf_u}; retrying...",
                    }
                )
                await asyncio.sleep(max(0.25, float(poll_ms) / 1000.0))
                continue

            lb = latest[-1]
            bar = {
                "time": int(lb.get("time_unix") or 0),
                "open": float(lb.get("open") or 0.0),
                "high": float(lb.get("high") or 0.0),
                "low": float(lb.get("low") or 0.0),
                "close": float(lb.get("close") or 0.0),
                "volume": int(lb.get("volume") or 0),
            }
            sig = (
                int(bar["time"]),
                float(bar["open"]),
                float(bar["high"]),
                float(bar["low"]),
                float(bar["close"]),
                int(bar["volume"]),
            )
            if sig != last_sig:
                await websocket.send_json(
                    {
                        "type": "tick",
                        "symbol": symbol_u,
                        "resolved_symbol": str(lb.get("symbol") or ""),
                        "timeframe": tf_u,
                        "bars": [bar],
                    }
                )
                last_sig = sig

            await asyncio.sleep(max(0.25, float(poll_ms) / 1000.0))
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        try:
            await websocket.send_json({"type": "error", "message": f"{type(exc).__name__}: {str(exc)}"})
        except Exception:
            pass


@router.get("/databento/status")
def simulation_databento_status(
    symbol: str = Query(default="NAS100"),
    timeframe: str = Query(default="M1"),
    dataset: str = Query(default="GLBX.MDP3"),
    stype_in: str = Query(default="continuous"),
    db_symbol: Optional[str] = Query(default=None),
):
    """Databento readiness/status for simulation live candle streaming."""
    try:
        from ..services.databento_live_service import DatabentoLiveService

        service = DatabentoLiveService(api_key=None, dataset=dataset, stype_in=stype_in)
        status = service.get_status(symbol=symbol, timeframe=timeframe, db_symbol=db_symbol)
        return {
            "ok": bool(status.get("ok")),
            "symbol": str(symbol).upper(),
            "timeframe": str(timeframe).upper(),
            "databento_connected": bool(status.get("connected")),
            "status": status,
        }
    except Exception as exc:
        return {
            "ok": False,
            "symbol": str(symbol).upper(),
            "timeframe": str(timeframe).upper(),
            "databento_connected": False,
            "error": f"{type(exc).__name__}: {str(exc)}",
        }


class DatabentoStatusRequest(BaseModel):
    symbol: str = "NAS100"
    timeframe: str = "M1"
    api_key: Optional[str] = None
    dataset: str = "GLBX.MDP3"
    stype_in: str = "continuous"
    db_symbol: Optional[str] = None


class LiveHistoryRequest(BaseModel):
    source: Literal["mt5", "databento"] = "mt5"
    symbol: str = "XAUUSD"
    timeframe: str = "M15"
    count: int = Field(default=600, ge=50, le=5000)
    lookback_days: float = Field(default=3.0, ge=0.1, le=60.0)
    api_key: Optional[str] = None
    dataset: str = "GLBX.MDP3"
    stype_in: str = "continuous"
    db_symbol: Optional[str] = None


@router.post("/databento/status")
def simulation_databento_status_post(req: DatabentoStatusRequest):
    """Databento readiness/status without exposing API key in URL query."""
    try:
        from ..services.databento_live_service import DatabentoLiveService

        service = DatabentoLiveService(api_key=req.api_key, dataset=req.dataset, stype_in=req.stype_in)
        status = service.get_status(symbol=req.symbol, timeframe=req.timeframe, db_symbol=req.db_symbol)
        return {
            "ok": bool(status.get("ok")),
            "symbol": str(req.symbol).upper(),
            "timeframe": str(req.timeframe).upper(),
            "databento_connected": bool(status.get("connected")),
            "status": status,
        }
    except Exception as exc:
        return {
            "ok": False,
            "symbol": str(req.symbol).upper(),
            "timeframe": str(req.timeframe).upper(),
            "databento_connected": False,
            "error": f"{type(exc).__name__}: {str(exc)}",
        }


@router.post("/live/history")
def simulation_live_history(req: LiveHistoryRequest):
    """
    Fetch recent bars for a chosen live data source/timeframe.
    Used by Workbench tools (e.g. MTF FVG scans) without switching chart timeframe.
    """
    source = str(req.source or "mt5").strip().lower()

    symbol_u = str(req.symbol or "XAUUSD").upper()
    tf_u = str(req.timeframe or "M15").upper()
    count = max(50, min(int(req.count), 5000))

    try:
        if source == "databento":
            from ..services.databento_live_service import DatabentoLiveService, TIMEFRAME_TO_MINUTES

            tf_mins = int(TIMEFRAME_TO_MINUTES.get(tf_u, 15))
            lookback_minutes = max(int(float(req.lookback_days or 3.0) * 1440.0), count * max(1, tf_mins) + 60)

            service = DatabentoLiveService(
                api_key=req.api_key,
                dataset=req.dataset,
                stype_in=req.stype_in,
            )
            bars = service.get_recent_candles(
                symbol=symbol_u,
                timeframe=tf_u,
                count=count,
                db_symbol=req.db_symbol,
                lookback_minutes=lookback_minutes,
                min_refresh_sec=0.0,
            )
        else:
            service = _get_mt5_service_singleton()
            bars = service.get_recent_candles(symbol=symbol_u, timeframe=tf_u, count=count)

        if not isinstance(bars, list):
            bars = []

        payload_bars = [
            {
                "time": int(b.get("time_unix") or 0),
                "open": float(b.get("open") or 0.0),
                "high": float(b.get("high") or 0.0),
                "low": float(b.get("low") or 0.0),
                "close": float(b.get("close") or 0.0),
                "volume": float(b.get("volume") or 0.0),
            }
            for b in bars
            if isinstance(b, dict)
        ]
        return {
            "ok": True,
            "source": source,
            "symbol": symbol_u,
            "timeframe": tf_u,
            "count": int(len(payload_bars)),
            "bars": payload_bars,
        }
    except Exception as exc:
        return {
            "ok": False,
            "source": source,
            "symbol": symbol_u,
            "timeframe": tf_u,
            "count": 0,
            "bars": [],
            "error": f"{type(exc).__name__}: {str(exc)}",
        }


@router.websocket("/ws/databento/live")
async def ws_databento_live(
    websocket: WebSocket,
    symbol: str = Query(default="NAS100"),
    timeframe: str = Query(default="M1"),
    dataset: str = Query(default="GLBX.MDP3"),
    stype_in: str = Query(default="continuous"),
    db_symbol: Optional[str] = Query(default=None),
    history: int = Query(default=300, ge=2, le=10000),
    poll_ms: int = Query(default=15000, ge=1000, le=60000),
):
    """
    Stream live Databento candles for simulation/workbench chart view.

    Messages:
    - {"type":"snapshot","bars":[...]}
    - {"type":"tick","bars":[latest_bar]}
    - {"type":"warning","message":"..."}
    - {"type":"error","message":"..."}
    """
    await websocket.accept()
    try:
        from ..services.databento_live_service import DatabentoLiveService
        from ..services.databento_live_service import TIMEFRAME_TO_MINUTES

        runtime_api_key = None
        # Prefer first-message auth for security; avoids URL query key exposure.
        if not runtime_api_key:
            try:
                auth_msg = await asyncio.wait_for(websocket.receive_json(), timeout=2.5)
                if isinstance(auth_msg, dict):
                    runtime_api_key = str(auth_msg.get("api_key") or "").strip() or None
            except Exception:
                runtime_api_key = None

        service = DatabentoLiveService(api_key=runtime_api_key, dataset=dataset, stype_in=stype_in)
        symbol_u = str(symbol or "NAS100").upper()
        tf_u = str(timeframe or "M1").upper()
        tf_mins = int(TIMEFRAME_TO_MINUTES.get(tf_u, 1))
        effective_poll_ms = max(5000, int(poll_ms))
        if effective_poll_ms > int(poll_ms):
            await websocket.send_json(
                {
                    "type": "warning",
                    "message": "Databento polling interval clamped to 5000ms minimum for cost control.",
                }
            )

        bars = service.get_recent_candles(
            symbol=symbol_u,
            timeframe=tf_u,
            count=history,
            db_symbol=db_symbol,
        )
        if not bars:
            await websocket.send_json({"type": "error", "message": f"No Databento candle data for {symbol_u} {tf_u}"})
            await websocket.close(code=4404)
            return

        snapshot_bars = [
            {
                "time": int(b.get("time_unix") or 0),
                "open": float(b.get("open") or 0.0),
                "high": float(b.get("high") or 0.0),
                "low": float(b.get("low") or 0.0),
                "close": float(b.get("close") or 0.0),
                "volume": int(b.get("volume") or 0),
            }
            for b in bars
        ]
        await websocket.send_json(
            {
                "type": "snapshot",
                "source": "databento",
                "symbol": symbol_u,
                "timeframe": tf_u,
                "bars": snapshot_bars,
            }
        )

        last_sig = None
        while True:
            latest = service.get_recent_candles(
                symbol=symbol_u,
                timeframe=tf_u,
                count=3,
                db_symbol=db_symbol,
                lookback_minutes=max(45, tf_mins * 8),
                min_refresh_sec=max(3.0, float(effective_poll_ms) / 1000.0 - 0.25),
            )
            if not latest:
                await websocket.send_json(
                    {
                        "type": "warning",
                        "message": f"No Databento update for {symbol_u} {tf_u}; retrying...",
                    }
                )
                await asyncio.sleep(max(1.0, float(effective_poll_ms) / 1000.0))
                continue

            lb = latest[-1]
            bar = {
                "time": int(lb.get("time_unix") or 0),
                "open": float(lb.get("open") or 0.0),
                "high": float(lb.get("high") or 0.0),
                "low": float(lb.get("low") or 0.0),
                "close": float(lb.get("close") or 0.0),
                "volume": int(lb.get("volume") or 0),
            }
            sig = (
                int(bar["time"]),
                float(bar["open"]),
                float(bar["high"]),
                float(bar["low"]),
                float(bar["close"]),
                int(bar["volume"]),
            )
            if sig != last_sig:
                await websocket.send_json(
                    {
                        "type": "tick",
                        "source": "databento",
                        "symbol": symbol_u,
                        "timeframe": tf_u,
                        "bars": [bar],
                    }
                )
                last_sig = sig

            await asyncio.sleep(max(1.0, float(effective_poll_ms) / 1000.0))
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        try:
            await websocket.send_json({"type": "error", "message": f"{type(exc).__name__}: {str(exc)}"})
        except Exception:
            pass


@router.get("/workbench/tools")
def workbench_list_tools():
    """List available workbench analysis tools."""
    return list_workbench_tools()


class ToolScanRequest(BaseModel):
    config: Dict[str, Any] = Field(default_factory=dict)
    bars: List[Dict[str, Any]] = Field(default_factory=list)


class ResearchOptimizeRequest(BaseModel):
    strategy_type: str = "sma_crossover"  # sma_crossover | mean_reversion
    params: Dict[str, Any] = Field(default_factory=dict)
    tc_rate: float = Field(default=0.0001, ge=0.0, le=0.1)
    top_n: int = Field(default=50, ge=5, le=200)
    max_combinations: int = Field(default=2500, ge=50, le=20000)
    bars: List[Dict[str, Any]] = Field(default_factory=list)


class ResearchMLDiagnosticRequest(BaseModel):
    lags: int = Field(default=5, ge=1, le=50)
    split_ratio: float = Field(default=0.7, ge=0.5, le=0.9)
    drift_warn_pct: float = Field(default=50.0, ge=5.0, le=500.0)
    params: Dict[str, Any] = Field(default_factory=dict)
    bars: List[Dict[str, Any]] = Field(default_factory=list)


class CoachEvaluateRequest(BaseModel):
    provider: str = "deterministic"  # deterministic | local_gptoss_http | openai_compat | claude
    model_label: Optional[str] = None
    llm_url: Optional[str] = None
    api_key: Optional[str] = None
    timeout_sec: Optional[int] = Field(default=None, ge=10, le=600)
    notes: Optional[str] = None
    tool_state: Dict[str, Any] = Field(default_factory=dict)


class ConsultantChatRequest(BaseModel):
    provider: str = "local_gptoss_http"  # deterministic | local_gptoss_http | openai_compat | claude
    model_label: Optional[str] = None
    llm_url: Optional[str] = None
    api_key: Optional[str] = None
    timeout_sec: Optional[int] = Field(default=None, ge=10, le=600)
    message: str = Field(min_length=1, max_length=4000)
    conversation_history: List[Dict[str, str]] = Field(default_factory=list)
    context_snapshot: Dict[str, Any] = Field(default_factory=dict)


class CopilotStartRequest(BaseModel):
    mode: str = "ADVISE"  # OBSERVE | ADVISE | ASSIST | AUTO_PAPER
    provider: str = "deterministic"
    model_label: Optional[str] = None
    config: Dict[str, Any] = Field(default_factory=dict)
    runtime: Dict[str, Any] = Field(default_factory=dict)


class CopilotActionRequest(BaseModel):
    action_type: str
    advice_id: Optional[int] = None
    payload: Dict[str, Any] = Field(default_factory=dict)
    note: Optional[str] = None


class CopilotToolStateRequest(BaseModel):
    tool_state: Dict[str, Any] = Field(default_factory=dict)
    event_type: str = "TOOL_SIGNAL_CHANGED"
    severity: str = "info"


# Phase 1 unified Workbench Agent contracts (additive only).

AgentProviderLiteral = Literal["deterministic", "local_gptoss_http", "openai_compat", "claude"]
AgentLoopModeLiteral = Literal["CHAT", "RUN_ONCE", "LOOP"]
AgentActionTypeLiteral = Literal[
    "SCAN_TOOL",
    "SET_INDICATOR_VISIBILITY",
    "RUN_RESEARCH_OPTIMIZER",
    "RUN_ML_DIAGNOSTIC",
    "PROPOSE_TRADE_ENTRY",
    "PROPOSE_TRADE_EXIT",
    "EXECUTE_TRADE_ENTRY",
    "EXECUTE_TRADE_EXIT",
    "REVIEW_NOTE",
]
AgentActionStatusLiteral = Literal[
    "PROPOSED",
    "APPROVED",
    "REJECTED",
    "EXECUTED",
    "BLOCKED_POLICY",
    "FAILED",
]
AgentRequestedByLiteral = Literal["USER", "AGENT"]
_AGENT_ALLOWED_ACTION_TYPES = {
    "SCAN_TOOL",
    "SET_INDICATOR_VISIBILITY",
    "RUN_RESEARCH_OPTIMIZER",
    "RUN_ML_DIAGNOSTIC",
    "PROPOSE_TRADE_ENTRY",
    "PROPOSE_TRADE_EXIT",
    "EXECUTE_TRADE_ENTRY",
    "EXECUTE_TRADE_EXIT",
    "REVIEW_NOTE",
}
_AGENT_ACTION_TYPE_ALIASES = {
    "MONITOR": "REVIEW_NOTE",
    "WATCH": "REVIEW_NOTE",
    "OBSERVE": "REVIEW_NOTE",
    "TRADE_SETUP": "PROPOSE_TRADE_ENTRY",
    "ENTRY_SETUP": "PROPOSE_TRADE_ENTRY",
    "EXIT_SETUP": "PROPOSE_TRADE_EXIT",
    "RESEARCH": "RUN_RESEARCH_OPTIMIZER",
    "OPTIMIZE": "RUN_RESEARCH_OPTIMIZER",
    "TOOL_SCAN": "SCAN_TOOL",
    "SCAN": "SCAN_TOOL",
    "INDICATORS": "SET_INDICATOR_VISIBILITY",
    "ML": "RUN_ML_DIAGNOSTIC",
}


class AgentProviderConfig(BaseModel):
    provider: AgentProviderLiteral = "deterministic"
    model_label: Optional[str] = None
    llm_url: Optional[str] = None
    timeout_sec: int = Field(default=45, ge=10, le=600)
    # Runtime secret only. Must never be persisted in DB.
    api_key: Optional[str] = None

    @field_validator("llm_url")
    @classmethod
    def _validate_llm_url(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        s = str(v).strip()
        if not s:
            return None
        parsed = urlparse(s)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("llm_url must be a valid http/https URL")
        return s

    @model_validator(mode="after")
    def _validate_llm_url_by_provider(self):
        s = str(self.llm_url or "").strip()
        if not s:
            return self

        parsed = urlparse(s)
        host = str(parsed.hostname or "").strip().lower()
        provider_name = str(self.provider or "").strip().lower()
        allow_internal = provider_name == "local_gptoss_http"

        if host in {"localhost", "0.0.0.0"} and not allow_internal:
            raise ValueError("llm_url must not point to localhost/internal addresses")

        if host:
            try:
                ip = ipaddress.ip_address(host)
            except ValueError:
                # Hostname (DNS) is allowed.
                return self

            is_internal = (
                ip.is_private
                or ip.is_loopback
                or ip.is_link_local
                or ip.is_reserved
                or ip.is_multicast
                or ip.is_unspecified
            )
            if is_internal and not allow_internal:
                raise ValueError("llm_url must not point to private/internal IP addresses")
        return self


class AgentPermissionConfig(BaseModel):
    can_chat: bool = True
    can_scan_tools: bool = True
    can_use_research: bool = False
    can_manage_indicators: bool = True
    can_place_trades: bool = False
    can_close_trades: bool = False
    can_auto_execute: bool = False
    requires_user_confirm_for_trade: bool = True

    @model_validator(mode="before")
    @classmethod
    def _normalize_permission_rules_before(cls, data: Any):
        if not isinstance(data, dict):
            return data
        out = dict(data)
        can_auto = bool(out.get("can_auto_execute", False))
        requires_confirm = bool(out.get("requires_user_confirm_for_trade", True))
        if can_auto:
            # Auto execution requires full trade permissions and no manual confirm.
            out["can_place_trades"] = True
            out["can_close_trades"] = True
            out["requires_user_confirm_for_trade"] = False
        elif requires_confirm:
            # Confirmed/manual mode cannot be auto-exec.
            out["can_auto_execute"] = False
        return out

    @model_validator(mode="after")
    def _validate_permission_rules(self):
        # Final guardrail normalization (tolerant): avoid 422 for stale clients.
        if bool(self.can_auto_execute):
            self.can_place_trades = True
            self.can_close_trades = True
            self.requires_user_confirm_for_trade = False
        elif bool(self.requires_user_confirm_for_trade):
            self.can_auto_execute = False
        return self


def _compact_tool_state_for_agent(payload: Any) -> Dict[str, Any]:
    """Keep only salient tool-state fields for agent reasoning."""
    src = payload if isinstance(payload, dict) else {}
    out: Dict[str, Any] = {}
    if src.get("active_tools") is not None:
        out["active_tools"] = src.get("active_tools")
    for key in (
        "fvg_enabled",
        "fvg_last_zone_count",
        "fvg_config",
        "fvg_movement_strength",
        "fvg_trend",
        "mean_rev_enabled",
        "mean_rev_last_zone_count",
        "mean_rev_config",
        "mean_rev_current_state",
        "liquidity_enabled",
        "liquidity_last_zone_count",
        "liquidity_config",
        "liquidity_current_state",
        "indicator_visibility",
    ):
        if key in src:
            out[key] = src.get(key)
    return out


class AgentContextSnapshot(BaseModel):
    bars: List[Dict[str, Any]] = Field(default_factory=list)
    tool_state: Dict[str, Any] = Field(default_factory=dict)
    indicators: Dict[str, Any] = Field(default_factory=dict)
    session_stats: Dict[str, Any] = Field(default_factory=dict)
    open_positions: List[Dict[str, Any]] = Field(default_factory=list)
    recent_trades: List[Dict[str, Any]] = Field(default_factory=list)
    metadata: Dict[str, Any] = Field(default_factory=dict)

    @field_validator("bars", mode="before")
    @classmethod
    def _sanitize_bars(cls, v: Any) -> List[Dict[str, Any]]:
        if not isinstance(v, list):
            return []
        src = v[-int(_AGENT_CONTEXT_BARS_MAX_INBOUND) :]
        rows: List[Dict[str, Any]] = []
        for b in src:
            if not isinstance(b, dict):
                continue
            try:
                t = int(b.get("time") or 0)
                o = float(b.get("open"))
                h = float(b.get("high"))
                l = float(b.get("low"))
                c = float(b.get("close"))
                vv = float(b.get("volume") or 0.0)
            except Exception:
                continue
            if t <= 0:
                continue
            if not (
                math.isfinite(o)
                and math.isfinite(h)
                and math.isfinite(l)
                and math.isfinite(c)
                and math.isfinite(vv)
            ):
                continue
            rows.append(
                {
                    "time": t,
                    "open": o,
                    "high": h,
                    "low": l,
                    "close": c,
                    "volume": vv,
                }
            )
        return rows

    @field_validator("open_positions", "recent_trades", mode="before")
    @classmethod
    def _trim_lists(cls, v: Any) -> List[Dict[str, Any]]:
        if not isinstance(v, list):
            return []
        src = v[-int(_AGENT_CONTEXT_ITEMS_MAX_INBOUND) :]
        return [row for row in src if isinstance(row, dict)]

    @field_validator("tool_state", mode="before")
    @classmethod
    def _compact_tool_state(cls, v: Any) -> Dict[str, Any]:
        obj = v if isinstance(v, dict) else {}
        try:
            raw = json.dumps(obj, ensure_ascii=True, sort_keys=True)
        except Exception:
            return {}
        if len(raw.encode("utf-8")) <= int(_AGENT_TOOL_STATE_MAX_BYTES_INBOUND):
            return obj
        return _compact_tool_state_for_agent(obj)


class AgentToolCall(BaseModel):
    tool_id: str = Field(min_length=1, max_length=80)
    args: Dict[str, Any] = Field(default_factory=dict)
    result: Dict[str, Any] = Field(default_factory=dict)


class AgentProposedAction(BaseModel):
    action_type: AgentActionTypeLiteral
    summary: str = Field(default="", max_length=1000)
    payload: Dict[str, Any] = Field(default_factory=dict)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


class AgentChatRequest(BaseModel):
    provider: AgentProviderConfig = Field(default_factory=AgentProviderConfig)
    permissions: AgentPermissionConfig = Field(default_factory=AgentPermissionConfig)
    config: Dict[str, Any] = Field(default_factory=dict)
    message: str = Field(min_length=1, max_length=6000)
    conversation_history: List[Dict[str, str]] = Field(default_factory=list, max_length=40)
    context_snapshot: AgentContextSnapshot = Field(default_factory=AgentContextSnapshot)
    allow_tools: bool = True
    max_tool_steps: int = Field(default=4, ge=0, le=10)


class AgentRunOnceRequest(BaseModel):
    provider: AgentProviderConfig = Field(default_factory=AgentProviderConfig)
    permissions: AgentPermissionConfig = Field(default_factory=AgentPermissionConfig)
    config: Dict[str, Any] = Field(default_factory=dict)
    context_snapshot: AgentContextSnapshot = Field(default_factory=AgentContextSnapshot)
    objective: str = Field(default="", max_length=1000)
    allow_tools: bool = True
    max_tool_steps: int = Field(default=4, ge=0, le=10)


class AgentLoopStartRequest(BaseModel):
    provider: AgentProviderConfig = Field(default_factory=AgentProviderConfig)
    permissions: AgentPermissionConfig = Field(default_factory=AgentPermissionConfig)
    loop_interval_sec: float = Field(default=5.0, ge=0.5, le=120.0)
    mode: AgentLoopModeLiteral = "LOOP"
    config: Dict[str, Any] = Field(default_factory=dict)
    runtime: Dict[str, Any] = Field(default_factory=dict)


class AgentActionRequest(BaseModel):
    action_id: Optional[int] = None
    requested_by: AgentRequestedByLiteral = "USER"
    action_type: AgentActionTypeLiteral
    status: AgentActionStatusLiteral = "APPROVED"
    reason: Optional[str] = None
    payload: Dict[str, Any] = Field(default_factory=dict)


class AgentResponse(BaseModel):
    ok: bool = True
    session_id: int
    provider: AgentProviderLiteral = "deterministic"
    model_label: Optional[str] = None
    message: str = ""
    tool_calls: List[AgentToolCall] = Field(default_factory=list)
    proposed_actions: List[AgentProposedAction] = Field(default_factory=list)
    usage: Dict[str, Any] = Field(default_factory=dict)
    audit: Dict[str, Any] = Field(default_factory=dict)


class AgentMemoryWriteRequest(BaseModel):
    content: str = Field(min_length=8, max_length=2000)
    memory_type: str = Field(default="note", max_length=40)
    scope: Literal["GLOBAL", "SESSION", "SYMBOL"] = "SESSION"
    importance: float = Field(default=0.7, ge=0.0, le=1.0)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    symbol: Optional[str] = None
    timeframe: Optional[str] = None


class AgentMemoryUpdateRequest(BaseModel):
    content: Optional[str] = Field(default=None, min_length=8, max_length=2000)
    memory_type: Optional[str] = Field(default=None, max_length=40)
    scope: Optional[Literal["GLOBAL", "SESSION", "SYMBOL"]] = None
    importance: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    metadata: Optional[Dict[str, Any]] = None
    symbol: Optional[str] = None
    timeframe: Optional[str] = None
    pinned: Optional[bool] = None


class AgentMemoryPolicyRequest(BaseModel):
    enabled: Optional[bool] = None
    ttl_days_default: Optional[float] = Field(default=None, ge=1.0, le=3650.0)
    ttl_days_by_type: Optional[Dict[str, float]] = None
    pinned_never_expires: Optional[bool] = None
    min_importance: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    max_hits: Optional[int] = Field(default=None, ge=1, le=50)
    recency_half_life_days: Optional[float] = Field(default=None, ge=1.0, le=365.0)
    pin_bonus: Optional[float] = Field(default=None, ge=0.0, le=1.0)


class AgentIdentityRequest(BaseModel):
    enabled: Optional[bool] = None
    version: Optional[int] = Field(default=None, ge=1, le=10000)
    lock_personality: Optional[bool] = None
    persona: Optional[str] = Field(default=None, max_length=300)
    tone: Optional[str] = Field(default=None, max_length=300)
    risk_doctrine: Optional[List[str]] = Field(default=None, max_length=12)
    immutable_rules: Optional[List[str]] = Field(default=None, max_length=12)


def _agent_state_payload(state: Any, include_legacy_aliases: bool = False) -> Dict[str, Any]:
    """Normalize state for /agent/* routes with optional legacy aliases."""
    if not isinstance(state, dict):
        return {}
    out = dict(state)
    agent_session_id = out.get("agent_session_id")
    if agent_session_id is None:
        agent_session_id = out.get("copilot_session_id")
    if agent_session_id is not None:
        out["agent_session_id"] = int(agent_session_id)
    if not include_legacy_aliases:
        out.pop("copilot_session_id", None)

    counts = out.get("counts") if isinstance(out.get("counts"), dict) else {}
    counts = dict(counts)
    counts["agent_actions_executed"] = int(
        counts.get("agent_actions_executed")
        if counts.get("agent_actions_executed") is not None
        else counts.get("copilot_actions_executed") or 0
    )
    counts["agent_tool_scans_executed"] = int(
        counts.get("agent_tool_scans_executed")
        if counts.get("agent_tool_scans_executed") is not None
        else counts.get("auto_tool_scans_executed") or 0
    )
    if not include_legacy_aliases:
        counts.pop("copilot_actions_executed", None)
        counts.pop("auto_tool_scans_executed", None)
    out["counts"] = counts
    return out


def _agent_loop_facade_response(
    payload: Any,
    session_id: int,
    include_legacy_aliases: bool = False,
) -> Any:
    """Build agent-first response wrappers for loop lifecycle endpoints."""
    if not isinstance(payload, dict):
        return payload
    state = payload.get("state") if isinstance(payload.get("state"), dict) else None
    if not isinstance(state, dict):
        return payload
    agent_state = _agent_state_payload(state, include_legacy_aliases=include_legacy_aliases)
    cfg = agent_state.get("config") if isinstance(agent_state.get("config"), dict) else {}
    perms = cfg.get("agent_permissions") if isinstance(cfg.get("agent_permissions"), dict) else {}
    out = dict(payload)
    out["session_id"] = int(session_id)
    out["active"] = bool(agent_state.get("active", False))
    out["status"] = str(agent_state.get("status") or "NOT_STARTED")
    out["provider"] = str(agent_state.get("provider") or "deterministic")
    out["model_label"] = str(agent_state.get("model_label") or "") or None
    agent_session_id = payload.get("agent_session_id")
    if agent_session_id is None:
        agent_session_id = agent_state.get("agent_session_id")
    if agent_session_id is not None:
        out["agent_session_id"] = int(agent_session_id)
    out["permissions"] = perms
    out["state"] = agent_state
    out["agent_state"] = agent_state
    if include_legacy_aliases:
        out["copilot_state"] = state
    return out


def _model_to_dict(model: Any) -> Dict[str, Any]:
    if model is None:
        return {}
    if isinstance(model, dict):
        return dict(model)
    try:
        fn = getattr(model, "model_dump", None)
        if callable(fn):
            out = fn()
            if isinstance(out, dict):
                return out
    except Exception:
        pass
    try:
        fn = getattr(model, "dict", None)
        if callable(fn):
            out = fn()
            if isinstance(out, dict):
                return out
    except Exception:
        pass
    return {}


def _normalize_agent_proposed_actions(raw: Any) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    if not isinstance(raw, list):
        return out
    for row in raw[:20]:
        if not isinstance(row, dict):
            continue
        raw_action = str(row.get("action_type") or "").strip().upper()
        if not raw_action:
            continue
        action_type = _AGENT_ACTION_TYPE_ALIASES.get(raw_action, raw_action)
        if action_type not in _AGENT_ALLOWED_ACTION_TYPES:
            action_type = "REVIEW_NOTE"
        payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
        if raw_action and raw_action != action_type:
            payload = dict(payload)
            payload["_raw_action_type"] = raw_action
        try:
            confidence = float(row.get("confidence") if row.get("confidence") is not None else 0.0)
        except Exception:
            confidence = 0.0
        out.append(
            {
                "action_type": action_type,
                "summary": str(row.get("summary") or "").strip()[:1000],
                "payload": payload,
                "confidence": max(0.0, min(1.0, confidence)),
            }
        )
    return out


def _agent_tool_calls_list(raw: Any) -> List[Dict[str, Any]]:
    if not isinstance(raw, list):
        return []
    out: List[Dict[str, Any]] = []
    for row in raw[:40]:
        if isinstance(row, dict):
            out.append(row)
    return out


def _agent_tool_call_succeeded(row: Any, tool_id: str) -> bool:
    if not isinstance(row, dict):
        return False
    tid = str(row.get("tool_id") or "").strip().lower()
    if tid != str(tool_id or "").strip().lower():
        return False
    result = row.get("result") if isinstance(row.get("result"), dict) else {}
    return bool(result.get("ok", False))


def _agent_tool_ids_from_calls(raw: Any) -> List[str]:
    out: List[str] = []
    for row in _agent_tool_calls_list(raw):
        tid = str(row.get("tool_id") or "").strip()
        if not tid:
            continue
        out.append(tid)
    return out[:20]


def _agent_pending_trigger_count(agent_row: Optional[WorkbenchAgentSessionModel]) -> int:
    rows = _get_agent_trade_triggers(agent_row)
    n = 0
    for r in rows:
        if not isinstance(r, dict):
            continue
        st = str(r.get("status") or "pending").strip().lower()
        if st in {"pending", "pending_approval"}:
            n += 1
    return int(n)


def _agent_claims_waiting_for_trigger(text: str) -> bool:
    t = str(text or "").lower()
    if not t:
        return False
    has_wait_word = any(
        x in t
        for x in [
            "waiting for",
            "monitoring",
            "watching",
            "monitor each",
            "monitoring each",
            "will execute",
            "monitoring mode active",
        ]
    )
    has_explicit_condition = any(
        re.search(pat, t, flags=re.IGNORECASE) is not None
        for pat in [
            r"(?:candle\s+close|close)\s+(?:below|above)\s+\d+(?:\.\d+)?",
            r"(?:if|when)\s+price\s+(?:is\s+)?(?:below|above)\s+\d+(?:\.\d+)?",
            r"(?:wait|waiting)\s+for\s+price\s+(?:to\s+be\s+|to\s+go\s+|to\s+)?(?:below|above)\s+\d+(?:\.\d+)?",
            r"(?:wait|waiting)\s+for\s+(?:a\s+)?close\s+(?:below|above)\s+\d+(?:\.\d+)?",
            r"(?:break(?:s|ing)?)\s+(?:below|above)\s+\d+(?:\.\d+)?",
        ]
    )
    return bool(has_wait_word and has_explicit_condition)


def _agent_user_allows_auto_schedule(text: str) -> bool:
    """Return True only when user text explicitly asks to arm/schedule a trigger.

    This prevents backend auto-recovery from scheduling entries when the user asks
    for analysis/reporting first (for example: "do not schedule until section A-D").
    """
    t = str(text or "").lower()
    if not t:
        return False
    deny_phrases = [
        "do not schedule",
        "don't schedule",
        "dont schedule",
        "no scheduling",
        "do not arm",
        "don't arm",
        "dont arm",
        "report first",
        "analysis first",
    ]
    if any(x in t for x in deny_phrases):
        return False

    has_schedule_verb = any(
        x in t
        for x in [
            "schedule trigger",
            "schedule entry",
            "arm trigger",
            "set trigger",
            "create trigger",
            "place conditional",
            "monitor and enter",
        ]
    )
    has_wait_then_enter = (
        re.search(
            r"(?:wait|waiting)\s+for[\s\S]{0,80}\b(?:then|and)\b[\s\S]{0,40}\b(?:enter|buy|sell|execute)\b",
            t,
            flags=re.IGNORECASE,
        )
        is not None
    )
    return bool(has_schedule_verb or has_wait_then_enter)


def _agent_claims_trade_executed(text: str) -> bool:
    t = str(text or "").lower()
    if not t:
        return False
    return any(
        x in t
        for x in [
            "trade executed",
            "approved and executed",
            "order executed",
            "order placed",
            "position opened",
            "close trade executed",
        ]
    )


def _agent_extract_schedule_trade_args(*, user_message: str, model_reply: str) -> Optional[Dict[str, Any]]:
    # Prefer user intent, then allow model-derived completion of missing fields.
    msg = str(user_message or "")
    rep = str(model_reply or "")
    merged = f"{msg}\n{rep}"
    lower = merged.lower()

    cond = None
    level = None
    trigger_patterns = [
        # Guard against accidental matches like "close trade below ...".
        (r"(?:candle\s+close|close(?!\s+trade(?:\s|$)))\s+below\s+(\d+(?:\.\d+)?)", "close_below"),
        (r"(?:candle\s+close|close(?!\s+trade(?:\s|$)))\s+above\s+(\d+(?:\.\d+)?)", "close_above"),
        (r"(?:if|when)\s+price\s+(?:is\s+)?below\s+(\d+(?:\.\d+)?)", "price_below"),
        (r"(?:if|when)\s+price\s+(?:is\s+)?above\s+(\d+(?:\.\d+)?)", "price_above"),
        (r"(?:wait|waiting)\s+for\s+price\s+(?:to\s+be\s+|to\s+go\s+|to\s+)?below\s+(\d+(?:\.\d+)?)", "price_below"),
        (r"(?:wait|waiting)\s+for\s+price\s+(?:to\s+be\s+|to\s+go\s+|to\s+)?above\s+(\d+(?:\.\d+)?)", "price_above"),
        (r"(?:wait|waiting)\s+for\s+(?:a\s+)?close\s+below\s+(\d+(?:\.\d+)?)", "close_below"),
        (r"(?:wait|waiting)\s+for\s+(?:a\s+)?close\s+above\s+(\d+(?:\.\d+)?)", "close_above"),
        (r"(?:break(?:s|ing)?\s+below)\s+(\d+(?:\.\d+)?)", "price_below"),
        (r"(?:break(?:s|ing)?\s+above)\s+(\d+(?:\.\d+)?)", "price_above"),
    ]
    for pat, c in trigger_patterns:
        m = re.search(pat, lower, flags=re.IGNORECASE)
        if not m:
            continue
        try:
            px = float(m.group(1))
        except Exception:
            continue
        if not math.isfinite(px) or px <= 0:
            continue
        cond = c
        level = float(px)
        break
    if cond is None or level is None:
        return None

    direction = ""
    if re.search(r"\b(buy|long)\b", lower):
        direction = "BUY"
    elif re.search(r"\b(sell|short)\b", lower):
        direction = "SELL"
    if direction not in {"BUY", "SELL"}:
        return None

    sl = None
    sl_m = re.search(r"(?:\bsl\b|stop(?:\s*loss)?)\s*[:=]?\s*(\d+(?:\.\d+)?)", lower, flags=re.IGNORECASE)
    if sl_m:
        try:
            sl = float(sl_m.group(1))
        except Exception:
            sl = None
    if sl is None or (not math.isfinite(sl)) or sl <= 0:
        return None

    tp = None
    tp_m = re.search(r"(?:\btp\b|take(?:\s*profit)?)\s*[:=]?\s*(\d+(?:\.\d+)?)", lower, flags=re.IGNORECASE)
    if tp_m:
        try:
            tp_val = float(tp_m.group(1))
            tp = float(tp_val) if math.isfinite(tp_val) and tp_val > 0 else None
        except Exception:
            tp = None

    lot_size = 0.01
    lot_m = re.search(r"(?:\blot(?:_size)?\b|size)\s*[:=]?\s*(\d+(?:\.\d+)?)", lower, flags=re.IGNORECASE)
    if lot_m:
        try:
            lv = float(lot_m.group(1))
            if math.isfinite(lv) and lv > 0:
                lot_size = min(100.0, max(0.01, lv))
        except Exception:
            pass

    tf = None
    tf_m = re.search(r"\b(m1|m5|m15|m30|h1|h4|d1)\b", lower, flags=re.IGNORECASE)
    if tf_m:
        tf = str(tf_m.group(1) or "").strip().upper()

    if not _validate_entry_levels(direction, float(level), float(sl), tp):
        return None
    out: Dict[str, Any] = {
        "condition": str(cond),
        "trigger_price": float(level),
        "direction": str(direction),
        "stop_loss": float(sl),
        "lot_size": float(lot_size),
    }
    if tp is not None:
        out["take_profit"] = float(tp)
    if tf:
        out["timeframe"] = tf
    return out


def _agent_enforce_execution_truth(
    *,
    out: Dict[str, Any],
    user_message: str,
    session: SimulationSession,
    agent_row: WorkbenchAgentSessionModel,
    db: Session,
    permissions: Dict[str, Any],
    context_snapshot: Dict[str, Any],
) -> Dict[str, Any]:
    if not isinstance(out, dict):
        return {"ok": False, "error": "invalid_agent_output"}
    result = dict(out)
    warnings: List[str] = []
    prev_w = result.get("integrity_warning")
    if isinstance(prev_w, str) and prev_w.strip():
        warnings.append(prev_w.strip())

    def _add_warning(code: str) -> None:
        c = str(code or "").strip()
        if not c:
            return
        if c not in warnings:
            warnings.append(c)

    calls = _agent_tool_calls_list(result.get("tool_calls"))
    reply = str(result.get("reply") or "")
    wait_claim = _agent_claims_waiting_for_trigger(reply)
    exec_claim = _agent_claims_trade_executed(reply)
    wait_intent = _agent_claims_waiting_for_trigger(str(user_message or ""))
    auto_schedule_allowed = _agent_user_allows_auto_schedule(str(user_message or ""))

    schedule_ok = any(_agent_tool_call_succeeded(c, "schedule_trade_entry") for c in calls)
    place_ok = any(_agent_tool_call_succeeded(c, "place_trade") for c in calls)
    close_ok = any(_agent_tool_call_succeeded(c, "close_trade") for c in calls)
    pending_count = _agent_pending_trigger_count(agent_row)

    # Recovery path: user asked for conditional monitoring, model forgot tool call.
    if (wait_intent or wait_claim) and auto_schedule_allowed and (not schedule_ok) and pending_count <= 0:
        auto_args = _agent_extract_schedule_trade_args(
            user_message=str(user_message or ""),
            model_reply=reply,
        )
        if auto_args is not None:
            auto_res = _agent_execute_tool(
                session=session,
                db=db,
                permissions=permissions if isinstance(permissions, dict) else {},
                context_snapshot=context_snapshot if isinstance(context_snapshot, dict) else {},
                tool_name="schedule_trade_entry",
                args=auto_args,
                atomic=True,
            )
            calls.append({"tool_id": "schedule_trade_entry", "args": auto_args, "result": auto_res})
            result["tool_calls"] = calls
            if bool(auto_res.get("ok", False)):
                schedule_ok = True
                pending_count = _agent_pending_trigger_count(agent_row)
                cond_txt = str(auto_args.get("condition") or "")
                px_txt = f"{float(auto_args.get('trigger_price')):.5f}".rstrip("0").rstrip(".")
                result["reply"] = (
                    f"Conditional entry trigger armed in backend: {cond_txt} @ {px_txt}.\n\n"
                    + str(reply or "")
                ).strip()
            else:
                err = str(auto_res.get("error") or "schedule_trade_entry_failed")
                result["reply"] = (
                    "Execution integrity check: no trigger was armed in backend. "
                    f"schedule_trade_entry failed: {err}.\n\n{str(reply or '')}"
                ).strip()
                _add_warning("trigger_schedule_failed")
        else:
            result["reply"] = (
                "Execution integrity check: no trigger is armed in backend yet. "
                "I need explicit condition + direction + stop-loss to schedule a conditional entry.\n\n"
                f"{str(reply or '')}"
            ).strip()
            _add_warning("trigger_not_armed")

    # Never allow execution claims without verifiable tool success in this turn.
    if exec_claim and not (place_ok or close_ok):
        note = (
            "Execution integrity check: no trade execution occurred in backend in this turn. "
            "No order was placed/closed."
        )
        cur = str(result.get("reply") or "")
        result["reply"] = f"{note}\n\n{cur}".strip()
        _add_warning("unverified_execution_claim")

    # Never allow waiting claims without pending trigger evidence.
    if (wait_claim or (wait_intent and auto_schedule_allowed)) and (not schedule_ok) and _agent_pending_trigger_count(agent_row) <= 0:
        note = "Execution integrity check: monitoring claim blocked because there is no pending backend trigger."
        cur = str(result.get("reply") or "")
        if note not in cur:
            result["reply"] = f"{note}\n\n{cur}".strip()
        _add_warning("unverified_waiting_claim")

    if warnings:
        result["integrity_warning"] = warnings[-1]
        result["integrity_warnings"] = warnings[:8]

    return result


def _agent_default_context(
    session: SimulationSession,
    db: Session,
) -> Dict[str, Any]:
    engine = _get_or_create_engine(session, db)
    identity = _agent_identity_from_session_config(session)
    bars: List[Dict[str, Any]] = []
    if engine.df is not None and not engine.df.empty:
        end_idx = int(min(engine.current_bar, max(0, len(engine.df) - 1)))
        start_idx = max(0, end_idx - int(_AGENT_CONTEXT_BARS_MAX))
        use_df = engine.df.iloc[start_idx : end_idx + 1]
        for ts, row in use_df.iterrows():
            try:
                o = float(row.get("open", 0.0))
                h = float(row.get("high", 0.0))
                l = float(row.get("low", 0.0))
                c = float(row.get("close", 0.0))
                vol = float(row.get("volume", 0.0))
            except Exception:
                continue
            if not all(math.isfinite(v) for v in (o, h, l, c, vol)):
                continue
            bars.append(
                {
                    "time": int(ts.timestamp()) if hasattr(ts, "timestamp") else 0,
                    "open": o,
                    "high": h,
                    "low": l,
                    "close": c,
                    "volume": vol,
                }
            )

    open_rows = (
        db.query(SimulationTrade)
        .filter(SimulationTrade.session_id == int(session.id))
        .filter(SimulationTrade.status == "open")
        .order_by(SimulationTrade.id.asc())
        .all()
    )
    closed_rows = (
        db.query(SimulationTrade)
        .filter(SimulationTrade.session_id == int(session.id))
        .filter(SimulationTrade.status == "closed")
        .order_by(SimulationTrade.id.desc())
        .limit(20)
        .all()
    )
    open_positions = [
        {
            "id": int(t.id),
            "direction": str(t.direction or ""),
            "entry_price": float(t.entry_price) if t.entry_price is not None else None,
            "stop_loss": float(t.stop_loss) if t.stop_loss is not None else None,
            "take_profit": float(t.take_profit) if t.take_profit is not None else None,
            "lot_size": float(t.lot_size) if t.lot_size is not None else None,
        }
        for t in open_rows
    ]
    recent_trades = [
        {
            "id": int(t.id),
            "direction": str(t.direction or ""),
            "entry_price": float(t.entry_price) if t.entry_price is not None else None,
            "exit_price": float(t.exit_price) if t.exit_price is not None else None,
            "pnl": float(t.pnl) if t.pnl is not None else None,
            "r_multiple": float(t.r_multiple) if t.r_multiple is not None else None,
            "exit_reason": str(t.exit_reason or "") if t.exit_reason else None,
            "status": str(t.status or ""),
        }
        for t in closed_rows
    ]
    copilot = _get_active_copilot(simulation_session_id=int(session.id), db=db)
    tool_state = {}
    if copilot is not None and isinstance(copilot.last_snapshot_json, dict):
        tool_state = copilot.last_snapshot_json.get("tool_state") if isinstance(copilot.last_snapshot_json.get("tool_state"), dict) else {}
    agent_row = _get_active_agent(simulation_session_id=int(session.id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session.id), db=db)
    scheduled_triggers: List[Dict[str, Any]] = []
    if agent_row is not None:
        for tr in _agent_trigger_rows_from_agent(agent_row):
            if not isinstance(tr, dict):
                continue
            if str(tr.get("status") or "").lower() != "pending":
                continue
            scheduled_triggers.append(tr)
            if len(scheduled_triggers) >= 30:
                break

    return {
        "session": {
            "id": int(session.id),
            "strategy_id": str(session.strategy_id or ""),
            "symbol": str(session.symbol or ""),
            "timeframe": str(session.timeframe or ""),
            "current_bar": int(session.current_bar or 0),
            "total_bars": int(session.total_bars or 0),
        },
        "bars": bars,
        "tool_state": tool_state,
        "indicators": {},
        "session_stats": {
            "initial_balance": float(session.initial_balance or 0.0),
            "current_balance": float(session.current_balance or 0.0),
            "total_pnl": float(session.total_pnl or 0.0),
            "trades_count": int(session.trades_count or 0),
            "wins": int(session.wins or 0),
            "losses": int(session.losses or 0),
        },
        "open_positions": open_positions,
        "recent_trades": recent_trades,
        "scheduled_triggers": scheduled_triggers,
        "identity": identity,
        "metadata": {
            "generated_at": _utc_now().isoformat(),
        },
    }


def _agent_merge_context(base: Dict[str, Any], patch: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(base or {})
    p = patch if isinstance(patch, dict) else {}
    for key, val in p.items():
        if key in {"tool_state", "indicators", "session_stats", "metadata"} and isinstance(val, dict):
            cur = out.get(key) if isinstance(out.get(key), dict) else {}
            out[key] = {**cur, **val}
            continue
        if key in {"bars", "open_positions", "recent_trades"} and isinstance(val, list) and len(val) > 0:
            out[key] = val
            continue
        if val is not None:
            out[key] = val
    return out


def _normalize_agent_trigger_condition(v: Any) -> Optional[str]:
    c = str(v or "").strip().lower()
    if c in {"close_below", "close_above", "price_below", "price_above"}:
        return c
    aliases = {
        "below_close": "close_below",
        "above_close": "close_above",
        "candle_close_below": "close_below",
        "candle_close_above": "close_above",
        "cross_below": "price_below",
        "cross_above": "price_above",
    }
    return aliases.get(c)


def _agent_effective_max_tool_steps(provider_name: Any, requested_steps: Any) -> int:
    try:
        n = int(requested_steps)
    except Exception:
        n = 0
    n = max(0, min(10, n))
    p = str(provider_name or "").strip().lower()
    if p in {"claude", "openai_compat"}:
        # External providers are TPM-sensitive; keep tool loops bounded, but configurable.
        try:
            cap = int(str(os.getenv("WORKBENCH_EXTERNAL_MAX_TOOL_STEPS") or "10").strip())
        except Exception:
            cap = 10
        cap = max(1, min(10, cap))
        return min(n, cap)
    return n


def _normalize_agent_trigger_state(v: Any, *, has_precondition: bool = False) -> str:
    s = str(v or "").strip().lower()
    if s in {"waiting_precondition", "waiting_entry"}:
        return s
    return "waiting_precondition" if has_precondition else "waiting_entry"


def _get_agent_trade_triggers(agent_row: Optional[WorkbenchAgentSessionModel]) -> List[Dict[str, Any]]:
    if agent_row is None or not isinstance(agent_row.last_snapshot_json, dict):
        return []
    raw = agent_row.last_snapshot_json.get("agent_trade_triggers")
    if not isinstance(raw, list):
        return []
    out: List[Dict[str, Any]] = []
    for r in raw[:200]:
        if isinstance(r, dict):
            out.append(dict(r))
    return out


def _set_agent_trade_triggers(
    *,
    agent_row: Optional[WorkbenchAgentSessionModel],
    triggers: List[Dict[str, Any]],
) -> None:
    if agent_row is None:
        return
    base = agent_row.last_snapshot_json if isinstance(agent_row.last_snapshot_json, dict) else {}
    snap = dict(base)
    snap["agent_trade_triggers"] = triggers[:200]
    agent_row.last_snapshot_json = snap
    agent_row.updated_at = _utc_now()


def _agent_trigger_rows_from_agent(agent_row: Optional[WorkbenchAgentSessionModel]) -> List[Dict[str, Any]]:
    rows = _get_agent_trade_triggers(agent_row)
    out: List[Dict[str, Any]] = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        tr = dict(r)
        trade_args = tr.get("trade_args") if isinstance(tr.get("trade_args"), dict) else {}
        tr["trade_args"] = {
            "direction": str(trade_args.get("direction") or "").upper(),
            "stop_loss": _to_float_or_none(trade_args.get("stop_loss")),
            "take_profit": _to_float_or_none(trade_args.get("take_profit")),
            "lot_size": _to_float_or_none(trade_args.get("lot_size")),
            "entry_price": _to_float_or_none(trade_args.get("entry_price")),
        }
        tr["condition"] = str(tr.get("condition") or "").lower()
        tr["trigger_price"] = _to_float_or_none(tr.get("trigger_price"))
        status_norm = str(tr.get("status") or "pending").lower()
        if status_norm == "cancelled":
            status_norm = "canceled"
        tr["status"] = status_norm
        if tr.get("canceled_at") is None and tr.get("cancelled_at") is not None:
            tr["canceled_at"] = str(tr.get("cancelled_at") or "") or None
        pre = tr.get("precondition") if isinstance(tr.get("precondition"), dict) else None
        if pre is not None:
            tr["precondition"] = {
                "condition": str(pre.get("condition") or "").lower(),
                "trigger_price": _to_float_or_none(pre.get("trigger_price")),
                "hit_at": str(pre.get("hit_at") or "") or None,
                "hit_price": _to_float_or_none(pre.get("hit_price")),
            }
        cancel_rule = tr.get("cancel_rule") if isinstance(tr.get("cancel_rule"), dict) else None
        if cancel_rule is not None:
            tr["cancel_rule"] = {
                "condition": str(cancel_rule.get("condition") or "").lower(),
                "trigger_price": _to_float_or_none(cancel_rule.get("trigger_price")),
                "hit_at": str(cancel_rule.get("hit_at") or "") or None,
                "hit_price": _to_float_or_none(cancel_rule.get("hit_price")),
            }
        tr["state"] = _normalize_agent_trigger_state(tr.get("state"), has_precondition=isinstance(pre, dict))
        tr["timeframe"] = str(tr.get("timeframe") or "").upper() or None
        tr["id"] = str(tr.get("id") or "")
        out.append(tr)
    return out


def _agent_indicator_values_from_bars(
    bars: Any,
    *,
    max_rows: int = 600,
) -> Dict[str, Any]:
    rows_limit = max(30, min(2000, int(max_rows)))
    bars_df = _bars_payload_to_df(bars, max_rows=rows_limit, min_rows=5)
    if bars_df is None or bars_df.empty:
        return {}
    close = bars_df["close"].astype(float)
    high = bars_df["high"].astype(float)
    low = bars_df["low"].astype(float)

    ema20 = close.ewm(span=20, adjust=False).mean()
    ema50 = close.ewm(span=50, adjust=False).mean()
    ema200 = close.ewm(span=200, adjust=False).mean()
    sma20 = close.rolling(window=20, min_periods=1).mean()
    sma50 = close.rolling(window=50, min_periods=1).mean()
    sma200 = close.rolling(window=200, min_periods=1).mean()
    std20 = close.rolling(window=20, min_periods=1).std(ddof=0).fillna(0.0)

    delta = close.diff().fillna(0.0)
    gain = delta.clip(lower=0.0)
    loss = (-delta.clip(upper=0.0))
    avg_gain = gain.ewm(alpha=(1.0 / 14.0), adjust=False).mean()
    avg_loss = loss.ewm(alpha=(1.0 / 14.0), adjust=False).mean()
    avg_loss = avg_loss.where(avg_loss > 1e-12, other=1e-12)
    rs = avg_gain / avg_loss
    rsi14 = 100.0 - (100.0 / (1.0 + rs))

    prev_close = close.shift(1).fillna(close.iloc[0])
    tr_components = pd.concat(
        [
            (high - low).abs(),
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    )
    tr = tr_components.max(axis=1)
    atr14 = tr.rolling(window=14, min_periods=1).mean()

    low14 = low.rolling(window=14, min_periods=1).min()
    high14 = high.rolling(window=14, min_periods=1).max()
    denom = (high14 - low14).where((high14 - low14) > 1e-12, other=1e-12)
    stoch_k = ((close - low14) / denom) * 100.0
    stoch_d = stoch_k.rolling(window=3, min_periods=1).mean()

    def _last(series: Any, digits: int = 5) -> Optional[float]:
        try:
            val = float(series.iloc[-1])
        except Exception:
            return None
        if not math.isfinite(val):
            return None
        return float(round(val, int(digits)))

    lookback = min(20, max(0, len(close) - 1))
    change_pct_20: Optional[float] = None
    if lookback > 0:
        base = float(close.iloc[-1 - lookback])
        if abs(base) > 1e-12:
            change_pct_20 = float(round(((float(close.iloc[-1]) - base) / base) * 100.0, 3))

    trend_bias = "mixed"
    e20 = _last(ema20)
    e50 = _last(ema50)
    e200 = _last(ema200)
    if e20 is not None and e50 is not None and e200 is not None:
        if e20 > e50 > e200:
            trend_bias = "bullish"
        elif e20 < e50 < e200:
            trend_bias = "bearish"

    return {
        "trend_bias": trend_bias,
        "change_pct_20": change_pct_20,
        "ema20": e20,
        "ema50": e50,
        "ema200": e200,
        "sma20": _last(sma20),
        "sma50": _last(sma50),
        "sma200": _last(sma200),
        "rsi14": _last(rsi14, 2),
        "atr14": _last(atr14, 3),
        "bb_mid": _last(sma20),
        "bb_upper": _last(sma20 + (2.0 * std20)),
        "bb_lower": _last(sma20 - (2.0 * std20)),
        "stoch_k": _last(stoch_k, 2),
        "stoch_d": _last(stoch_d, 2),
    }


def _agent_positions_detail_payload(
    *,
    session: SimulationSession,
    db: Session,
    open_limit: int,
    recent_limit: int,
) -> Dict[str, Any]:
    o_lim = max(1, min(50, int(open_limit)))
    r_lim = max(1, min(100, int(recent_limit)))
    open_rows = (
        db.query(SimulationTrade)
        .filter(SimulationTrade.session_id == int(session.id))
        .filter(SimulationTrade.status == "open")
        .order_by(SimulationTrade.id.asc())
        .limit(o_lim)
        .all()
    )
    recent_rows = (
        db.query(SimulationTrade)
        .filter(SimulationTrade.session_id == int(session.id))
        .filter(SimulationTrade.status == "closed")
        .order_by(SimulationTrade.id.desc())
        .limit(r_lim)
        .all()
    )
    open_positions = [
        {
            "id": int(t.id),
            "direction": str(t.direction or "").upper(),
            "entry_price": _to_float_or_none(t.entry_price),
            "stop_loss": _to_float_or_none(t.stop_loss),
            "take_profit": _to_float_or_none(t.take_profit),
            "lot_size": _to_float_or_none(t.lot_size),
            "opened_at": t.opened_at.isoformat() if getattr(t, "opened_at", None) is not None else None,
        }
        for t in open_rows
    ]
    recent_trades = [
        {
            "id": int(t.id),
            "direction": str(t.direction or "").upper(),
            "entry_price": _to_float_or_none(t.entry_price),
            "exit_price": _to_float_or_none(t.exit_price),
            "pnl": _to_float_or_none(t.pnl),
            "r_multiple": _to_float_or_none(t.r_multiple),
            "exit_reason": str(t.exit_reason or "") or None,
            "status": str(t.status or "").lower(),
            "closed_at": t.closed_at.isoformat() if getattr(t, "closed_at", None) is not None else None,
        }
        for t in recent_rows
    ]
    return {
        "open_positions": open_positions,
        "recent_trades": recent_trades,
        "open_count": int(len(open_positions)),
        "recent_count": int(len(recent_trades)),
    }


def _agent_scheduled_triggers_payload(
    *,
    session: SimulationSession,
    db: Session,
    include_non_pending: bool,
    limit: int,
) -> Dict[str, Any]:
    lim = max(1, min(200, int(limit)))
    agent_row = _get_active_agent(simulation_session_id=int(session.id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session.id), db=db)
    rows = _agent_trigger_rows_from_agent(agent_row)
    pending_count = sum(1 for r in rows if isinstance(r, dict) and str(r.get("status") or "").lower() == "pending")
    if not bool(include_non_pending):
        rows = [r for r in rows if isinstance(r, dict) and str(r.get("status") or "").lower() == "pending"]
    return {
        "triggers": rows[:lim],
        "total_count": int(len(_agent_trigger_rows_from_agent(agent_row))),
        "pending_count": int(pending_count),
        "returned_count": int(min(lim, len(rows))),
    }


def _agent_market_snapshot_payload(
    *,
    session: SimulationSession,
    db: Session,
    context_snapshot: Dict[str, Any],
    bars_limit: int,
    include_bars: bool,
    include_indicators: bool,
) -> Dict[str, Any]:
    lim = max(5, min(400, int(bars_limit)))
    raw_bars = context_snapshot.get("bars") if isinstance(context_snapshot.get("bars"), list) else []
    bars: List[Dict[str, Any]] = []
    for b in raw_bars[-1200:]:
        nb = _normalize_live_bar(b)
        if nb is not None:
            bars.append(nb)

    if not bars:
        try:
            engine = _get_or_create_engine(session, db)
            if engine.df is not None and not engine.df.empty:
                end_idx = int(min(engine.current_bar, max(0, len(engine.df) - 1)))
                start_idx = max(0, end_idx - 240)
                use_df = engine.df.iloc[start_idx : end_idx + 1]
                for ts, row in use_df.iterrows():
                    try:
                        bars.append(
                            {
                                "time": int(ts.timestamp()) if hasattr(ts, "timestamp") else 0,
                                "open": float(row.get("open")),
                                "high": float(row.get("high")),
                                "low": float(row.get("low")),
                                "close": float(row.get("close")),
                                "volume": float(row.get("volume") or 0.0),
                            }
                        )
                    except Exception:
                        continue
        except Exception:
            bars = []

    indicators = _agent_indicator_values_from_bars(bars, max_rows=max(120, lim * 6)) if include_indicators else {}
    last_bar = bars[-1] if bars else {}
    positions_detail = _agent_positions_detail_payload(session=session, db=db, open_limit=20, recent_limit=20)
    trigger_payload = _agent_scheduled_triggers_payload(
        session=session,
        db=db,
        include_non_pending=False,
        limit=20,
    )
    return {
        "session": {
            "id": int(session.id),
            "symbol": str(session.symbol or ""),
            "timeframe": str(session.timeframe or ""),
            "current_bar": int(session.current_bar or 0),
            "total_bars": int(session.total_bars or 0),
        },
        "current_price": _to_float_or_none(last_bar.get("close")),
        "last_bar_time": int(last_bar.get("time") or 0) if isinstance(last_bar, dict) else 0,
        "bars_count": int(len(bars)),
        "bars": (bars[-lim:] if include_bars else []),
        "indicators": indicators,
        "open_positions_count": int(positions_detail.get("open_count") or 0),
        "pending_triggers_count": int(trigger_payload.get("pending_count") or 0),
        "session_stats": {
            "initial_balance": _to_float_or_none(session.initial_balance),
            "current_balance": _to_float_or_none(session.current_balance),
            "total_pnl": _to_float_or_none(session.total_pnl),
            "trades_count": int(session.trades_count or 0),
            "wins": int(session.wins or 0),
            "losses": int(session.losses or 0),
        },
    }


def _agent_timeframe_to_minutes(tf_like: Any) -> int:
    tf = str(tf_like or "").strip().upper()
    if tf in {"M1"}:
        return 1
    if tf in {"M5"}:
        return 5
    if tf in {"M15"}:
        return 15
    if tf in {"M30"}:
        return 30
    if tf in {"H1"}:
        return 60
    if tf in {"H4"}:
        return 240
    if tf in {"D1"}:
        return 1440
    return 15


def _agent_default_history_days_for_timeframe(tf_like: Any) -> float:
    # Aim for enough bars for indicators/trend/FVG quality on HTF without forcing huge payloads.
    tf_min = max(1, _agent_timeframe_to_minutes(tf_like))
    target_bars = 180.0
    days = (target_bars * float(tf_min)) / 1440.0
    return max(2.0, min(60.0, float(days)))


def _agent_market_context_from_snapshot(
    *,
    session: SimulationSession,
    context_snapshot: Dict[str, Any],
) -> Dict[str, Any]:
    tool_state = context_snapshot.get("tool_state") if isinstance(context_snapshot.get("tool_state"), dict) else {}
    mctx = tool_state.get("market_context") if isinstance(tool_state.get("market_context"), dict) else {}
    symbol = str(mctx.get("symbol") or session.symbol or "XAUUSD").strip().upper() or "XAUUSD"
    timeframe = str(mctx.get("timeframe") or session.timeframe or "M15").strip().upper() or "M15"
    source = str(mctx.get("source") or "mt5").strip().lower() or "mt5"
    if source not in {"mt5", "databento"}:
        source = "mt5"
    try:
        history_days = float(mctx.get("history_days") or 0.0)
    except Exception:
        history_days = 0.0
    if not math.isfinite(history_days) or history_days <= 0:
        history_days = _agent_default_history_days_for_timeframe(timeframe)
    history_days = max(0.1, min(60.0, float(history_days)))
    return {
        "symbol": symbol,
        "timeframe": timeframe,
        "source": source,
        "history_days": history_days,
    }


def _agent_fetch_live_history_bars(
    *,
    source: str,
    symbol: str,
    timeframe: str,
    history_days: float,
    count: int,
    databento_api_key: Optional[str] = None,
) -> Tuple[List[Dict[str, Any]], Optional[str]]:
    src = str(source or "mt5").strip().lower()
    if src not in {"mt5", "databento"}:
        src = "mt5"
    sym = str(symbol or "XAUUSD").strip().upper() or "XAUUSD"
    tf = str(timeframe or "M15").strip().upper() or "M15"
    try:
        hd = float(history_days)
    except Exception:
        hd = _agent_default_history_days_for_timeframe(tf)
    hd = max(0.1, min(120.0, float(hd)))
    try:
        c = int(count)
    except Exception:
        c = 300
    c = max(50, min(5000, c))
    try:
        req = LiveHistoryRequest(
            source=src,
            symbol=sym,
            timeframe=tf,
            count=c,
            lookback_days=hd,
            api_key=str(databento_api_key or "").strip() or None,
        )
        out = simulation_live_history(req)
        if not isinstance(out, dict):
            logger.warning(
                "agent_live_history_fetch_failed source=%s symbol=%s timeframe=%s reason=invalid_response",
                src,
                sym,
                tf,
            )
            return [], "live_history_unavailable:invalid_response"
        ok = bool(out.get("ok", False))
        err_text = str(out.get("error") or "").strip()
        rows = out.get("bars") if isinstance(out.get("bars"), list) else []
        bars: List[Dict[str, Any]] = []
        for raw in rows:
            nb = _normalize_live_bar(raw)
            if nb is not None:
                bars.append(nb)
        if len(bars) <= 0:
            if not ok:
                logger.warning(
                    "agent_live_history_fetch_failed source=%s symbol=%s timeframe=%s reason=%s",
                    src,
                    sym,
                    tf,
                    (err_text or "source_not_ready")[:180],
                )
                return [], f"live_history_unavailable:{(err_text or 'source_not_ready')[:180]}"
            logger.warning(
                "agent_live_history_fetch_failed source=%s symbol=%s timeframe=%s reason=empty_bars",
                src,
                sym,
                tf,
            )
            return [], "live_history_unavailable:empty_bars"
        return bars, None
    except Exception as exc:
        logger.warning(
            "agent_live_history_fetch_failed source=%s symbol=%s timeframe=%s err=%s",
            src,
            sym,
            tf,
            f"{type(exc).__name__}: {str(exc)[:180]}",
        )
        return [], f"live_history_unavailable:{type(exc).__name__}"


def _agent_scan_tool_from_bars(
    *,
    tool_id: str,
    bars: List[Dict[str, Any]],
    symbol: str,
    timeframe: str,
    config: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    tid = str(tool_id or "").strip().lower()
    tool = get_tool(tid)
    if tool is None:
        return {"ok": False, "error": f"unknown_tool:{tid or 'empty'}"}
    bars_df = _bars_payload_to_df(bars, max_rows=50000, min_rows=3)
    if bars_df is None or bars_df.empty:
        return {"ok": False, "error": "insufficient_bars"}

    raw_cfg = config if isinstance(config, dict) else {}
    merged_config = {
        **tool.get_default_config(),
        **raw_cfg,
        "symbol": str(symbol or "XAUUSD").strip().upper() or "XAUUSD",
        "timeframe": str(timeframe or "M15").strip().upper() or "M15",
    }

    trend_meta: Dict[str, Any] = {}
    movement_strength: Dict[str, Any] = {}
    current_state: Dict[str, Any] = {}
    trend_fn = getattr(tool, "compute_trend_context", None)
    if callable(trend_fn):
        try:
            trend_meta = trend_fn(bars_df, merged_config) or {}
        except Exception:
            trend_meta = {}
    strength_fn = getattr(tool, "compute_movement_strength", None)
    if callable(strength_fn):
        try:
            movement_strength = strength_fn(bars_df, merged_config, trend_ctx=trend_meta) or {}
        except Exception:
            movement_strength = {}
    current_state_fn = getattr(tool, "compute_current_state", None)
    if callable(current_state_fn):
        try:
            current_state = current_state_fn(bars_df, merged_config) or {}
        except Exception:
            current_state = {}
    scan_config = dict(merged_config)
    if trend_meta:
        scan_config["_trend_context"] = trend_meta
    try:
        zones = tool.scan(bars_df, scan_config)
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
    zones = zones if isinstance(zones, list) else []
    return {
        "ok": True,
        "data": {
            "tool_id": tid,
            "zones": zones,
            "count": int(len(zones)),
            "scan_source": "agent_live_fetch",
            "scan_timeframe": str(scan_config.get("timeframe") or ""),
            "trend": trend_meta,
            "movement_strength": movement_strength,
            "current_state": current_state,
        },
    }


def _agent_fvg_zone_status(zone: Dict[str, Any]) -> str:
    filled = bool(zone.get("filled", False))
    cur_gap = _to_float_or_none(zone.get("current_gap_size"))
    mitigations = int(zone.get("mitigations") or 0)
    if filled or (cur_gap is not None and cur_gap <= 1e-9):
        return "filled"
    if mitigations > 0:
        return "partially_mitigated"
    return "unfilled"


def _agent_run_mtf_analysis(
    *,
    session: SimulationSession,
    db: Session,
    context_snapshot: Dict[str, Any],
    payload: Dict[str, Any],
    effective_cfg: Dict[str, Any],
) -> Dict[str, Any]:
    allowed_tfs = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"}
    mctx = _agent_market_context_from_snapshot(
        session=session,
        context_snapshot=context_snapshot if isinstance(context_snapshot, dict) else {},
    )
    symbol = str(payload.get("symbol") or mctx.get("symbol") or session.symbol or "XAUUSD").strip().upper() or "XAUUSD"
    source = str(payload.get("source") or mctx.get("source") or "mt5").strip().lower() or "mt5"
    if source not in {"mt5", "databento"}:
        source = "mt5"

    execution_tf = str(payload.get("execution_timeframe") or mctx.get("timeframe") or session.timeframe or "M15").strip().upper()
    if execution_tf not in allowed_tfs:
        execution_tf = "M15"

    raw_htf = payload.get("htf_timeframes") if isinstance(payload.get("htf_timeframes"), list) else ["D1", "H4"]
    htf_tfs: List[str] = []
    for tf in raw_htf:
        s = str(tf or "").strip().upper()
        if s in allowed_tfs and s != execution_tf and s not in htf_tfs:
            htf_tfs.append(s)
    if not htf_tfs:
        for fallback_tf in ["D1", "H4"]:
            if fallback_tf != execution_tf:
                htf_tfs.append(fallback_tf)

    try:
        htf_history_days = float(payload.get("htf_history_days")) if payload.get("htf_history_days") is not None else None
    except Exception:
        htf_history_days = None
    try:
        ltf_history_days = float(payload.get("ltf_history_days")) if payload.get("ltf_history_days") is not None else None
    except Exception:
        ltf_history_days = None

    tf_results: Dict[str, Dict[str, Any]] = {}
    tf_bars: Dict[str, List[Dict[str, Any]]] = {}
    for tf in [*htf_tfs, execution_tf]:
        tf_min = max(1, _agent_timeframe_to_minutes(tf))
        if tf == execution_tf and ltf_history_days is not None and math.isfinite(ltf_history_days) and ltf_history_days > 0:
            days = float(max(0.5, min(60.0, ltf_history_days)))
        elif tf != execution_tf and htf_history_days is not None and math.isfinite(htf_history_days) and htf_history_days > 0:
            days = float(max(0.5, min(120.0, htf_history_days)))
        elif tf == execution_tf:
            base_days = _agent_default_history_days_for_timeframe(tf)
            days = float(max(10.0 if tf_min <= 30 else 5.0, min(30.0, base_days * 2.0)))
        else:
            days = _agent_default_history_days_for_timeframe(tf)

        est_count = int((float(days) * 1440.0) / float(tf_min)) + 30
        bars_live, live_err = _agent_fetch_live_history_bars(
            source=source,
            symbol=symbol,
            timeframe=tf,
            history_days=days,
            count=max(120, min(5000, est_count)),
            databento_api_key=str(effective_cfg.get("databento_api_key") or ""),
        )
        tf_bars[tf] = bars_live if isinstance(bars_live, list) else []
        if len(tf_bars[tf]) < 20:
            tf_results[tf] = {
                "timeframe": tf,
                "bars_count": int(len(tf_bars[tf])),
                "history_days": float(round(days, 3)),
                "scan_error": str(live_err or "live_history_unavailable"),
                "fallback_used": False,
                "zones": [],
                "zones_count": 0,
                "active_zones_count": 0,
                "trend": {"direction": "unknown"},
                "movement_strength": {"state": "insufficient_data", "score": 0.0, "gas_low": True},
            }
            continue

        scan_out = _agent_scan_tool_from_bars(
            tool_id="fvg",
            bars=tf_bars[tf],
            symbol=symbol,
            timeframe=tf,
            config={
                "timeframe": tf,
                "show_filled": True,
                "trend_filter_enabled": False,
            },
        )
        if not bool(scan_out.get("ok")):
            tf_results[tf] = {
                "timeframe": tf,
                "bars_count": int(len(tf_bars[tf])),
                "history_days": float(round(days, 3)),
                "scan_error": str(scan_out.get("error") or "scan_failed"),
                "fallback_used": False,
                "zones": [],
                "zones_count": 0,
                "active_zones_count": 0,
                "trend": {"direction": "unknown"},
                "movement_strength": {"state": "insufficient_data", "score": 0.0, "gas_low": True},
            }
            continue

        scan_data = scan_out.get("data") if isinstance(scan_out.get("data"), dict) else {}
        zones_raw = scan_data.get("zones") if isinstance(scan_data.get("zones"), list) else []
        fallback_used = False
        if tf in htf_tfs and htf_history_days is None and len(zones_raw) == 0:
            fallback_days_map = {"D1": 90.0, "H4": 45.0}
            fallback_days = float(fallback_days_map.get(tf, 0.0))
            if fallback_days > float(days) + 0.5:
                est_fb_count = int((fallback_days * 1440.0) / float(tf_min)) + 30
                fb_bars, fb_err = _agent_fetch_live_history_bars(
                    source=source,
                    symbol=symbol,
                    timeframe=tf,
                    history_days=fallback_days,
                    count=max(120, min(5000, est_fb_count)),
                    databento_api_key=str(effective_cfg.get("databento_api_key") or ""),
                )
                if len(fb_bars) >= 20:
                    fb_scan_out = _agent_scan_tool_from_bars(
                        tool_id="fvg",
                        bars=fb_bars,
                        symbol=symbol,
                        timeframe=tf,
                        config={
                            "timeframe": tf,
                            "show_filled": True,
                            "trend_filter_enabled": False,
                        },
                    )
                    if bool(fb_scan_out.get("ok")):
                        fb_scan_data = fb_scan_out.get("data") if isinstance(fb_scan_out.get("data"), dict) else {}
                        fb_zones_raw = fb_scan_data.get("zones") if isinstance(fb_scan_data.get("zones"), list) else []
                        if len(fb_zones_raw) > 0:
                            tf_bars[tf] = fb_bars
                            days = float(fallback_days)
                            scan_data = fb_scan_data
                            zones_raw = fb_zones_raw
                            fallback_used = True
                elif fb_err:
                    logger.info(
                        "agent_mtf_fallback_fetch_failed tf=%s symbol=%s err=%s",
                        str(tf),
                        str(symbol),
                        str(fb_err)[:180],
                    )
        zones: List[Dict[str, Any]] = []
        for z in zones_raw:
            if not isinstance(z, dict):
                continue
            top = _to_float_or_none(z.get("top"))
            bottom = _to_float_or_none(z.get("bottom"))
            if top is None or bottom is None:
                continue
            z_top = float(max(top, bottom))
            z_bottom = float(min(top, bottom))
            z_type = str(z.get("type") or "").strip().lower()
            direction = "bullish" if z_type.startswith("bullish") else ("bearish" if z_type.startswith("bearish") else "unknown")
            status = _agent_fvg_zone_status(z)
            zones.append(
                {
                    "type": z_type,
                    "direction": direction,
                    "top": z_top,
                    "bottom": z_bottom,
                    "gap_size": _to_float_or_none(z.get("gap_size")) or abs(z_top - z_bottom),
                    "current_gap_size": _to_float_or_none(z.get("current_gap_size")),
                    "mitigations": int(z.get("mitigations") or 0),
                    "filled": bool(z.get("filled", False)),
                    "status": status,
                    "trend_aligned": bool(z.get("trend_aligned", False)),
                    "bar_index": int(z.get("bar_index") or 0),
                    "start_time_unix": int(z.get("start_time_unix") or 0),
                    "end_time_unix": int(z.get("end_time_unix") or 0),
                }
            )
        active_count = sum(1 for z in zones if str(z.get("status") or "") in {"unfilled", "partially_mitigated"})
        tf_results[tf] = {
            "timeframe": tf,
            "bars_count": int(len(tf_bars[tf])),
            "history_days": float(round(days, 3)),
            "scan_error": None,
            "fallback_used": bool(fallback_used),
            "zones": zones,
            "zones_count": int(len(zones)),
            "active_zones_count": int(active_count),
            "trend": scan_data.get("trend") if isinstance(scan_data.get("trend"), dict) else {"direction": "unknown"},
            "movement_strength": scan_data.get("movement_strength") if isinstance(scan_data.get("movement_strength"), dict) else {},
        }

    ltf_bars = tf_bars.get(execution_tf) if isinstance(tf_bars.get(execution_tf), list) else []
    current_price = None
    if ltf_bars:
        current_price = _to_float_or_none(ltf_bars[-1].get("close") if isinstance(ltf_bars[-1], dict) else None)
    if current_price is None:
        for tf in [execution_tf, *htf_tfs]:
            bars_try = tf_bars.get(tf) if isinstance(tf_bars.get(tf), list) else []
            if bars_try:
                current_price = _to_float_or_none(bars_try[-1].get("close") if isinstance(bars_try[-1], dict) else None)
                if current_price is not None:
                    break

    def _avg_true_range_proxy(rows: List[Dict[str, Any]], max_rows: int = 30) -> Optional[float]:
        if not isinstance(rows, list) or not rows:
            return None
        sample = rows[-max(3, int(max_rows)) :]
        vals: List[float] = []
        for r in sample:
            if not isinstance(r, dict):
                continue
            hi = _to_float_or_none(r.get("high"))
            lo = _to_float_or_none(r.get("low"))
            if hi is None or lo is None:
                continue
            rng = abs(float(hi) - float(lo))
            if math.isfinite(rng) and rng > 0:
                vals.append(float(rng))
        if len(vals) < 3:
            return None
        return float(sum(vals) / float(len(vals)))

    ltf_indicators = _agent_indicator_values_from_bars(ltf_bars, max_rows=1200) if len(ltf_bars) >= 30 else {}
    ltf_scan = tf_results.get(execution_tf) if isinstance(tf_results.get(execution_tf), dict) else {}
    inst_for_limits = get_instrument(symbol)
    ltf_atr14 = _to_float_or_none(ltf_indicators.get("atr14"))
    if ltf_atr14 is None or ltf_atr14 <= 0:
        ltf_atr14 = _avg_true_range_proxy(ltf_bars, max_rows=30)
    if ltf_atr14 is None or ltf_atr14 <= 0:
        ltf_atr14 = float(max(float(inst_for_limits.point_value) * 20.0, 0.01))
    if isinstance(ltf_indicators, dict) and (ltf_indicators.get("atr14") is None):
        ltf_indicators["atr14"] = float(ltf_atr14)

    pos = _agent_positions_detail_payload(session=session, db=db, open_limit=10, recent_limit=10)
    open_positions = pos.get("open_positions") if isinstance(pos.get("open_positions"), list) else []
    trigger_payload = _agent_scheduled_triggers_payload(
        session=session,
        db=db,
        include_non_pending=False,
        limit=100,
    )
    pending_triggers = trigger_payload.get("triggers") if isinstance(trigger_payload.get("triggers"), list) else []

    d1_dir = str((tf_results.get("D1") or {}).get("trend", {}).get("direction") or "").strip().lower()
    h4_dir = str((tf_results.get("H4") or {}).get("trend", {}).get("direction") or "").strip().lower()
    bias = "unknown"
    if d1_dir in {"bullish", "bearish"}:
        bias = d1_dir
    elif h4_dir in {"bullish", "bearish"}:
        bias = h4_dir

    anchors: List[Dict[str, Any]] = []
    counter_bias_zones: List[Dict[str, Any]] = []
    for tf in htf_tfs:
        tfr = tf_results.get(tf) if isinstance(tf_results.get(tf), dict) else {}
        for z in (tfr.get("zones") if isinstance(tfr.get("zones"), list) else []):
            if not isinstance(z, dict):
                continue
            status = str(z.get("status") or "")
            if status not in {"unfilled", "partially_mitigated"}:
                continue
            top = _to_float_or_none(z.get("top"))
            bottom = _to_float_or_none(z.get("bottom"))
            if top is None or bottom is None:
                continue
            distance = None
            if current_price is not None:
                distance = float(min(abs(float(current_price) - float(top)), abs(float(current_price) - float(bottom))))
            row = {
                "timeframe": tf,
                "type": str(z.get("type") or ""),
                "direction": str(z.get("direction") or ""),
                "top": float(top),
                "bottom": float(bottom),
                "status": status,
                "mitigations": int(z.get("mitigations") or 0),
                "gap_size": _to_float_or_none(z.get("gap_size")),
                "distance_from_price": distance,
            }
            if bias in {"bullish", "bearish"} and str(row.get("direction") or "") != bias:
                counter_bias_zones.append(row)
            else:
                anchors.append(row)
    tf_rank = {"D1": 0, "H4": 1, "H1": 2, "M30": 3, "M15": 4, "M5": 5, "M1": 6}
    anchors.sort(key=lambda z: (float(z.get("distance_from_price") if z.get("distance_from_price") is not None else 10**12), int(tf_rank.get(str(z.get("timeframe") or ""), 9))))
    counter_bias_zones.sort(key=lambda z: (float(z.get("distance_from_price") if z.get("distance_from_price") is not None else 10**12), int(tf_rank.get(str(z.get("timeframe") or ""), 9))))

    # ── Fix 1: Filter anchors by execution relevance (ATR-based proximity). ──
    # Zones beyond 8x ATR from current price are context-only, not trigger-worthy.
    _anchor_proximity_limit = float(ltf_atr14) * 8.0 if (ltf_atr14 is not None and ltf_atr14 > 0) else None
    execution_anchors: List[Dict[str, Any]] = []
    context_only_anchors: List[Dict[str, Any]] = []
    for _a in anchors:
        _dist = _a.get("distance_from_price")
        if _anchor_proximity_limit is not None and _dist is not None and float(_dist) > _anchor_proximity_limit:
            _a["execution_relevant"] = False
            context_only_anchors.append(_a)
        else:
            _a["execution_relevant"] = True
            execution_anchors.append(_a)

    blockers: List[str] = []
    soft_blockers: List[str] = []
    confidence_warnings: List[str] = []
    if len(open_positions) > 0:
        blockers.append("open_position_exists")
    if current_price is None:
        blockers.append("current_price_unavailable")
    if not execution_anchors:
        if anchors:
            soft_blockers.append("no_execution_relevant_anchor")
            confidence_warnings.append("all_anchors_too_distant")
            # Keep a proposal path for operator-reviewed setups instead of hard-blocking.
            execution_anchors = anchors[:1]
        else:
            blockers.append("no_htf_anchor_zone")
    if bias not in {"bullish", "bearish"}:
        confidence_warnings.append("htf_bias_unknown")
    if d1_dir in {"bullish", "bearish"} and h4_dir in {"bullish", "bearish"} and d1_dir != h4_dir:
        confidence_warnings.append("htf_bias_conflict")

    # ── Fix 2: Detect LTF exhaustion and add confidence warnings. ──
    ltf_movement = ltf_scan.get("movement_strength") if isinstance(ltf_scan.get("movement_strength"), dict) else {}
    ltf_gas_low = bool(ltf_movement.get("gas_low", False))
    ltf_mov_state = str(ltf_movement.get("state") or "").strip().lower()
    if ltf_gas_low or ltf_mov_state == "exhausted":
        confidence_warnings.append("ltf_movement_exhausted")

    best_setup: Optional[Dict[str, Any]] = None
    duplicate_pending = False
    if not blockers:
        anchor = execution_anchors[0]
        inst = get_instrument(symbol)
        rr_target = _to_float_or_none(payload.get("rr_target"))
        if rr_target is None or (not math.isfinite(rr_target)) or rr_target <= 0:
            rr_target = 2.0
        rr_target = float(max(1.0, min(6.0, rr_target)))
        risk_percent = _to_float_or_none(payload.get("risk_percent"))
        if risk_percent is None or (not math.isfinite(risk_percent)) or risk_percent <= 0:
            risk_percent = 0.5
        risk_percent = float(max(0.1, min(5.0, risk_percent)))
        requested_risk_percent = float(risk_percent)
        risk_derated = False
        if ltf_gas_low or ltf_mov_state == "exhausted":
            capped_risk = float(min(risk_percent, 0.25))
            if capped_risk < float(risk_percent):
                risk_percent = capped_risk
                risk_derated = True
                confidence_warnings.append("risk_derated_for_exhaustion")

        top = float(anchor["top"])
        bottom = float(anchor["bottom"])
        atr14 = _to_float_or_none(ltf_indicators.get("atr14"))
        gap = abs(top - bottom)
        min_buffer = max(float(inst.point_value) * 2.0, gap * 0.10)
        if atr14 is not None and atr14 > 0:
            min_buffer = max(min_buffer, float(atr14) * 0.05)

        setup_direction = bias if bias in {"bullish", "bearish"} else str(anchor.get("direction") or "").strip().lower()
        if setup_direction not in {"bullish", "bearish"}:
            blockers.append("anchor_direction_unknown")
            setup_direction = "bullish"

        if setup_direction == "bullish":
            entry_ref = float(top)
            direction = "BUY"
            precondition = {"condition": "close_below", "trigger_price": float(top)}
            condition = {"condition": "close_above", "trigger_price": float(top)}
            cancel_rule = {"condition": "close_below", "trigger_price": float(bottom)}
            stop_loss = float(bottom - min_buffer)
        else:
            entry_ref = float(bottom)
            direction = "SELL"
            precondition = {"condition": "close_above", "trigger_price": float(bottom)}
            condition = {"condition": "close_below", "trigger_price": float(bottom)}
            cancel_rule = {"condition": "close_above", "trigger_price": float(top)}
            stop_loss = float(top + min_buffer)

        risk_distance = abs(float(entry_ref) - float(stop_loss))
        if risk_distance <= 0 or not math.isfinite(risk_distance):
            blockers.append("invalid_risk_distance")
        else:
            reward_distance = float(risk_distance * rr_target)
            take_profit_rr = float(entry_ref + reward_distance) if direction == "BUY" else float(entry_ref - reward_distance)
            take_profit = float(take_profit_rr)
            tp_basis = "rr_multiple"

            # Optional structural target from the nearest opposite-direction active zone on LTF.
            ltf_zones = ltf_scan.get("zones") if isinstance(ltf_scan.get("zones"), list) else []
            structure_candidates: List[float] = []
            for z in ltf_zones:
                if not isinstance(z, dict):
                    continue
                if str(z.get("status") or "") not in {"unfilled", "partially_mitigated"}:
                    continue
                z_dir = str(z.get("direction") or "")
                z_top = _to_float_or_none(z.get("top"))
                z_bottom = _to_float_or_none(z.get("bottom"))
                if z_top is None or z_bottom is None:
                    continue
                if direction == "BUY":
                    if z_dir == "bearish" and float(z_bottom) > float(entry_ref):
                        structure_candidates.append(float(z_bottom))
                else:
                    if z_dir == "bullish" and float(z_top) < float(entry_ref):
                        structure_candidates.append(float(z_top))
            structural_tp = None
            if structure_candidates:
                structural_tp = min(structure_candidates) if direction == "BUY" else max(structure_candidates)
                struct_reward = abs(float(structural_tp) - float(entry_ref))
                struct_rr = struct_reward / float(risk_distance) if risk_distance > 0 else 0.0
                if struct_rr >= 1.20:
                    take_profit = float(structural_tp)
                    reward_distance = float(struct_reward)
                    tp_basis = "structure"
            rr = reward_distance / risk_distance if risk_distance > 0 else None

            balance = _to_float_or_none(session.current_balance)
            if balance is None or balance <= 0:
                balance = _to_float_or_none(session.initial_balance) or 10000.0
            risk_amount = float(balance * (risk_percent / 100.0))
            value_per_1lot = float(inst.contract_size)
            lot_raw = risk_amount / (risk_distance * value_per_1lot) if (risk_distance > 0 and value_per_1lot > 0) else float(inst.min_lot)
            lot_size = _normalize_lot_for_instrument(
                lot_size=float(lot_raw),
                min_lot=float(inst.min_lot),
                max_lot=min(100.0, float(inst.max_lot)),
                lot_step=float(inst.lot_step),
            )

            tf_min = max(1, _agent_timeframe_to_minutes(execution_tf))
            atr_eff = float(atr14) if (atr14 is not None and atr14 > 0) else max(float(inst.point_value) * 10.0, risk_distance * 1.5)
            pullback_bars_est = abs(float(current_price) - float(entry_ref)) / max(atr_eff, float(inst.point_value))
            expiry_hours = max(6.0, min(24.0, (pullback_bars_est * float(tf_min) / 60.0) * 4.0))
            expires_sec = int(max(6 * 3600, min(24 * 3600, int(round(expiry_hours * 3600.0)))))

            for tr in pending_triggers:
                if not isinstance(tr, dict):
                    continue
                if str(tr.get("status") or "").lower() != "pending":
                    continue
                tr_cond = str(tr.get("condition") or "").lower()
                tr_price = _to_float_or_none(tr.get("trigger_price"))
                tr_pre = tr.get("precondition") if isinstance(tr.get("precondition"), dict) else {}
                tr_ta = tr.get("trade_args") if isinstance(tr.get("trade_args"), dict) else {}
                if (
                    tr_cond == str(condition["condition"])
                    and tr_price is not None
                    and abs(float(tr_price) - float(condition["trigger_price"])) <= (float(inst.point_value) * 2.0)
                    and str(tr_ta.get("direction") or "").upper() == direction
                    and str(tr.get("timeframe") or "").upper() == str(execution_tf)
                    and str(tr_pre.get("condition") or "").lower() == str(precondition["condition"])
                    and _to_float_or_none(tr_pre.get("trigger_price")) is not None
                    and abs(float(_to_float_or_none(tr_pre.get("trigger_price")) or 0.0) - float(precondition["trigger_price"])) <= (float(inst.point_value) * 2.0)
                ):
                    duplicate_pending = True
                    break
            if duplicate_pending:
                blockers.append("duplicate_pending_trigger")

            # ── Fix 3: Compute verified risk_usd from instrument spec. ──
            actual_risk_usd = float(risk_distance * value_per_1lot * lot_size)

            # ── Fix 4: Build calc_trace so LLM (and user) can verify math. ──
            calc_trace = {
                "contract_size": float(inst.contract_size),
                "price_increment": float(inst.point_value),
                "money_per_price_unit_per_1lot": float(value_per_1lot),
                "lot_step": float(inst.lot_step),
                "balance": float(balance),
                "risk_percent": float(round(risk_percent, 4)),
                "risk_percent_requested": float(round(requested_risk_percent, 4)),
                "risk_amount_target": float(round(risk_amount, 2)),
                "risk_amount_actual": float(round(actual_risk_usd, 2)),
                "lot_raw": float(round(lot_raw, 6)),
                "lot_normalized": float(lot_size),
                "unit": "price_units",
                "risk_formula": "abs(entry_ref - stop_loss) * money_per_price_unit_per_1lot * lot_size",
            }

            # ── Fix 5: Setup-level warnings for LLM to cite. ──
            setup_warnings: List[str] = []
            if ltf_gas_low or ltf_mov_state == "exhausted":
                setup_warnings.append("LTF movement exhausted — impulse may be fading. Consider smaller size or waiting for fresh momentum.")
            if risk_derated:
                setup_warnings.append(
                    f"Risk derated for exhausted movement: requested {requested_risk_percent:.2f}% -> effective {risk_percent:.2f}%."
                )
            if abs(actual_risk_usd - risk_amount) > (risk_amount * 0.05):
                setup_warnings.append(f"Lot rounding causes actual risk ${actual_risk_usd:.2f} vs target ${risk_amount:.2f}.")
            anchor_dist = anchor.get("distance_from_price")
            if anchor_dist is not None and ltf_atr14 is not None and ltf_atr14 > 0 and float(anchor_dist) > float(ltf_atr14) * 5.0:
                setup_warnings.append(f"Anchor is {float(anchor_dist):.2f} price units away ({float(anchor_dist) / float(ltf_atr14):.1f}x ATR) — pullback required.")

            best_setup = {
                "direction": direction,
                "anchor_timeframe": str(anchor.get("timeframe") or ""),
                "entry_ref": float(round(entry_ref, 5)),
                "stop_loss": float(round(stop_loss, 5)),
                "take_profit": float(round(take_profit, 5)),
                "take_profit_rr": float(round(take_profit_rr, 5)),
                "risk_distance": float(round(risk_distance, 5)),
                "reward_distance": float(round(reward_distance, 5)),
                "rr": float(round(rr or 0.0, 4)),
                "tp_basis": tp_basis,
                "risk_percent": float(round(risk_percent, 4)),
                "requested_risk_percent": float(round(requested_risk_percent, 4)),
                "risk_derated": bool(risk_derated),
                "risk_amount": float(round(risk_amount, 4)),
                "risk_amount_actual": float(round(actual_risk_usd, 2)),
                "lot_size": float(lot_size),
                "timeframe": str(execution_tf),
                "expires_sec": int(expires_sec),
                "precondition": precondition,
                "condition": condition,
                "cancel_rule": cancel_rule,
                "calc_trace": calc_trace,
                "warnings": setup_warnings,
            }

    include_news = bool(payload.get("include_news", False))
    news_payload: Optional[Dict[str, Any]] = None
    if include_news:
        try:
            news_limit = int(payload.get("news_limit") or 5)
        except Exception:
            news_limit = 5
        try:
            news_lookback_min = int(payload.get("news_lookback_min") or effective_cfg.get("guardrail_news_lookback_min") or 240)
        except Exception:
            news_lookback_min = 240
        news_provider = str(payload.get("provider") or effective_cfg.get("market_news_provider") or "polygon").strip().lower()
        news_payload = _agent_fetch_market_news(
            symbol=symbol,
            limit=max(1, min(10, int(news_limit))),
            lookback_min=max(15, min(24 * 60, int(news_lookback_min))),
            provider=news_provider,
            include_summary=True,
            summary_model=str(effective_cfg.get("market_news_summary_model") or "claude-haiku-4-5-20251001").strip(),
            summary_timeout_sec=max(4, min(30, int(effective_cfg.get("market_news_llm_timeout_sec") or 8))),
            ibkr_host=str(effective_cfg.get("market_news_ibkr_host") or "127.0.0.1").strip() or "127.0.0.1",
            ibkr_port=max(1, min(65535, int(_agent_usage_safe_int(effective_cfg.get("market_news_ibkr_port"), 7497)))),
        )

    manual_confirmation_required = bool(
        len(soft_blockers) > 0
        or ("ltf_movement_exhausted" in confidence_warnings)
        or ("risk_derated_for_exhaustion" in confidence_warnings)
    )

    summary: Dict[str, Any] = {
        "symbol": symbol,
        "source": source,
        "execution_timeframe": execution_tf,
        "current_price": current_price,
        "position_state": {
            "open_positions_count": int(len(open_positions)),
            "pending_triggers_count": int(trigger_payload.get("pending_count") or 0),
        },
        "htf_bias": {
            "direction": bias,
            "d1_direction": d1_dir or "unknown",
            "h4_direction": h4_dir or "unknown",
            "conflict": bool(d1_dir in {"bullish", "bearish"} and h4_dir in {"bullish", "bearish"} and d1_dir != h4_dir),
        },
        "scan_summary": {
            tf: {
                "bars_count": int((tf_results.get(tf) or {}).get("bars_count") or 0),
                "history_days": float((tf_results.get(tf) or {}).get("history_days") or 0.0),
                "fallback_used": bool((tf_results.get(tf) or {}).get("fallback_used", False)),
                "zones_count": int((tf_results.get(tf) or {}).get("zones_count") or 0),
                "active_zones_count": int((tf_results.get(tf) or {}).get("active_zones_count") or 0),
                "trend_direction": str(((tf_results.get(tf) or {}).get("trend") or {}).get("direction") or "unknown"),
                "movement_strength": (tf_results.get(tf) or {}).get("movement_strength") if isinstance((tf_results.get(tf) or {}).get("movement_strength"), dict) else {},
                "error": (tf_results.get(tf) or {}).get("scan_error"),
            }
            for tf in [*htf_tfs, execution_tf]
        },
        "htf_anchors": execution_anchors[:20],
        "htf_context_only_anchors": context_only_anchors[:10],
        "counter_bias_zones": counter_bias_zones[:20],
        "ltf_confirmation": {
            "timeframe": execution_tf,
            "trend_direction": str((ltf_scan.get("trend") or {}).get("direction") or "unknown"),
            "movement_strength": ltf_scan.get("movement_strength") if isinstance(ltf_scan.get("movement_strength"), dict) else {},
            "indicators": ltf_indicators,
        },
        "best_setup": best_setup,
        "duplicate_pending_trigger": bool(duplicate_pending),
        "trigger_ready": bool(best_setup is not None and not blockers),
        "manual_confirmation_required": bool(manual_confirmation_required),
        "blockers": blockers[:12],
        "soft_blockers": soft_blockers[:12],
        "confidence_warnings": confidence_warnings[:12],
        "tool_state_patch": {
            "mtf_analysis": {
                "generated_at": _utc_now().isoformat(),
                "symbol": symbol,
                "execution_timeframe": execution_tf,
                "bias": bias,
                "trigger_ready": bool(best_setup is not None and not blockers),
                "manual_confirmation_required": bool(manual_confirmation_required),
                "blockers": blockers[:6],
                "soft_blockers": soft_blockers[:6],
                "warnings": confidence_warnings[:6],
                "best_setup": best_setup,
            }
        },
    }
    if news_payload is not None:
        summary["news"] = news_payload
    return summary


def _agent_execute_tool(
    *,
    session: SimulationSession,
    db: Session,
    permissions: Dict[str, Any],
    context_snapshot: Dict[str, Any],
    tool_name: str,
    args: Dict[str, Any],
    tool_config: Optional[Dict[str, Any]] = None,
    atomic: bool = True,
) -> Dict[str, Any]:
    tname = str(tool_name or "").strip()
    payload = args if isinstance(args, dict) else {}
    perms = permissions if isinstance(permissions, dict) else {}
    effective_cfg = _agent_effective_tool_config(session=session, db=db, override=tool_config)
    if not _agent_tool_allowed_by_access_mode(tname, effective_cfg):
        mode = _normalize_strategy_tool_access_mode(effective_cfg.get("strategy_tool_access_mode"))
        return {"ok": False, "error": f"tool_blocked_by_access_mode:{mode}:{tname}"}

    if tname == "scan_tool":
        if not bool(perms.get("can_scan_tools", True)):
            return {"ok": False, "error": "permission_denied:can_scan_tools"}
        tool_id = str(payload.get("tool_id") or "fvg").strip().lower()
        cfg = payload.get("config") if isinstance(payload.get("config"), dict) else {}
        cfg = dict(cfg)
        tf_arg = str(payload.get("timeframe") or "").strip().upper()
        if tf_arg in {"M1", "M5", "M15", "M30", "H1", "H4", "D1"}:
            cfg["timeframe"] = tf_arg
        try:
            lb_days = float(payload.get("lookback_days")) if payload.get("lookback_days") is not None else None
        except Exception:
            lb_days = None
        if lb_days is not None and math.isfinite(lb_days) and lb_days > 0:
            cfg["lookback_days"] = max(0.1, min(60.0, float(lb_days)))
        bars_from_payload = isinstance(payload.get("bars"), list)
        bars = payload.get("bars") if bars_from_payload else (context_snapshot.get("bars") if isinstance(context_snapshot.get("bars"), list) else [])
        mctx = _agent_market_context_from_snapshot(session=session, context_snapshot=context_snapshot if isinstance(context_snapshot, dict) else {})
        tf_scan = str(cfg.get("timeframe") or mctx.get("timeframe") or session.timeframe or "M15").strip().upper()
        ctx_tf = str(mctx.get("timeframe") or session.timeframe or "M15").strip().upper()
        # Important: context bars are usually chart-timeframe bars. If agent explicitly asks another
        # timeframe (e.g., D1/H4 from M15 session), force timeframe-specific fetch instead of scanning
        # mismatched bars and returning false "0 zone" negatives.
        if (not bars_from_payload) and len(bars) >= 20 and tf_scan != ctx_tf:
            bars = []
        if len(bars) < 20:
            src = str(payload.get("source") or mctx.get("source") or "mt5").strip().lower()
            sym = str(payload.get("symbol") or mctx.get("symbol") or session.symbol or "XAUUSD").strip().upper()
            try:
                hd = float(cfg.get("lookback_days") or payload.get("history_days") or mctx.get("history_days") or _agent_default_history_days_for_timeframe(tf_scan))
            except Exception:
                hd = _agent_default_history_days_for_timeframe(tf_scan)
            tf_min = max(1, _agent_timeframe_to_minutes(tf_scan))
            est_count = int((max(0.1, min(60.0, float(hd))) * 1440.0) / float(tf_min)) + 20
            bars_live, live_err = _agent_fetch_live_history_bars(
                source=src,
                symbol=sym,
                timeframe=tf_scan,
                history_days=float(hd),
                count=max(80, min(5000, est_count)),
                databento_api_key=str(effective_cfg.get("databento_api_key") or ""),
            )
            if len(bars_live) >= 20:
                bars = bars_live
            elif len(bars) < 20:
                return {"ok": False, "error": str(live_err or "live_history_unavailable")}
        req = ToolScanRequest(config=cfg, bars=bars if isinstance(bars, list) else [])
        try:
            data = workbench_scan_tool(session_id=int(session.id), tool_id=tool_id, req=req, db=db)
            return {"ok": True, "data": data}
        except HTTPException as exc:
            return {"ok": False, "error": str(exc.detail)}

    if tname == "scan_draw_fvg_range":
        if bool(effective_cfg.get("telegram_bridge", False)):
            return {"ok": False, "error": "unsupported_in_telegram:no_chart_selection"}
        if not bool(perms.get("can_scan_tools", True)):
            return {"ok": False, "error": "permission_denied:can_scan_tools"}
        bars = payload.get("bars") if isinstance(payload.get("bars"), list) else (context_snapshot.get("bars") if isinstance(context_snapshot.get("bars"), list) else [])
        if not isinstance(bars, list) or len(bars) < 3:
            return {"ok": False, "error": "insufficient_bars"}
        try:
            i0 = int(payload.get("start_index"))
            i1 = int(payload.get("end_index"))
        except Exception:
            return {"ok": False, "error": "invalid_range_indexes"}
        lo = max(0, min(i0, i1))
        hi = min(len(bars) - 1, max(i0, i1))
        selected = bars[lo : hi + 1]
        if len(selected) < 3:
            return {"ok": False, "error": "selection_too_small"}
        cfg = payload.get("config") if isinstance(payload.get("config"), dict) else {}
        cfg = {**cfg, "show_filled": True}
        req = ToolScanRequest(config=cfg, bars=selected)
        try:
            data = workbench_scan_tool(session_id=int(session.id), tool_id="fvg", req=req, db=db)
            return {"ok": True, "data": data, "selection": {"start_index": lo, "end_index": hi, "bars": len(selected)}}
        except HTTPException as exc:
            return {"ok": False, "error": str(exc.detail)}

    if tname == "run_mtf_analysis":
        if not bool(perms.get("can_scan_tools", True)):
            return {"ok": False, "error": "permission_denied:can_scan_tools"}
        try:
            data = _agent_run_mtf_analysis(
                session=session,
                db=db,
                context_snapshot=context_snapshot if isinstance(context_snapshot, dict) else {},
                payload=payload if isinstance(payload, dict) else {},
                effective_cfg=effective_cfg if isinstance(effective_cfg, dict) else {},
            )
            return {"ok": True, "data": data}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "get_market_snapshot":
        if not bool(perms.get("can_chat", True)):
            return {"ok": False, "error": "permission_denied:can_chat"}
        bars_limit = _agent_usage_safe_int(payload.get("bars_limit"), 40)
        include_bars = bool(payload.get("include_bars", True))
        include_indicators = bool(payload.get("include_indicators", True))
        ctx_obj = context_snapshot if isinstance(context_snapshot, dict) else {}
        bars_ctx = ctx_obj.get("bars") if isinstance(ctx_obj.get("bars"), list) else []
        if len(bars_ctx) < 20:
            mctx = _agent_market_context_from_snapshot(session=session, context_snapshot=ctx_obj)
            tf_snap = str(payload.get("timeframe") or mctx.get("timeframe") or session.timeframe or "M15").strip().upper()
            src = str(payload.get("source") or mctx.get("source") or "mt5").strip().lower()
            sym = str(payload.get("symbol") or mctx.get("symbol") or session.symbol or "XAUUSD").strip().upper()
            try:
                hd = float(payload.get("history_days") or mctx.get("history_days") or _agent_default_history_days_for_timeframe(tf_snap))
            except Exception:
                hd = _agent_default_history_days_for_timeframe(tf_snap)
            tf_min = max(1, _agent_timeframe_to_minutes(tf_snap))
            est_count = int((max(0.1, min(60.0, float(hd))) * 1440.0) / float(tf_min)) + 20
            bars_live, live_err = _agent_fetch_live_history_bars(
                source=src,
                symbol=sym,
                timeframe=tf_snap,
                history_days=float(hd),
                count=max(120, min(5000, max(int(bars_limit) * 6, est_count))),
                databento_api_key=str(effective_cfg.get("databento_api_key") or ""),
            )
            if len(bars_live) >= 20:
                ctx_obj = dict(ctx_obj)
                ctx_obj["bars"] = bars_live
            elif len(bars_ctx) < 20:
                return {"ok": False, "error": str(live_err or "live_history_unavailable")}
        try:
            data = _agent_market_snapshot_payload(
                session=session,
                db=db,
                context_snapshot=ctx_obj,
                bars_limit=max(5, min(400, int(bars_limit))),
                include_bars=include_bars,
                include_indicators=include_indicators,
            )
            return {"ok": True, "data": data}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "get_positions_detail":
        if not bool(perms.get("can_chat", True)):
            return {"ok": False, "error": "permission_denied:can_chat"}
        open_limit = _agent_usage_safe_int(payload.get("open_limit"), 20)
        recent_limit = _agent_usage_safe_int(payload.get("recent_limit"), 20)
        try:
            data = _agent_positions_detail_payload(
                session=session,
                db=db,
                open_limit=max(1, min(50, int(open_limit))),
                recent_limit=max(1, min(100, int(recent_limit))),
            )
            return {"ok": True, "data": data}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "get_indicator_values":
        if not bool(perms.get("can_chat", True)):
            return {"ok": False, "error": "permission_denied:can_chat"}
        bars = payload.get("bars") if isinstance(payload.get("bars"), list) else (
            context_snapshot.get("bars") if isinstance(context_snapshot.get("bars"), list) else []
        )
        bars_limit = _agent_usage_safe_int(payload.get("bars_limit"), 300)
        if len(bars) < 30:
            mctx = _agent_market_context_from_snapshot(session=session, context_snapshot=context_snapshot if isinstance(context_snapshot, dict) else {})
            tf_ind = str(payload.get("timeframe") or mctx.get("timeframe") or session.timeframe or "M15").strip().upper()
            src = str(payload.get("source") or mctx.get("source") or "mt5").strip().lower()
            sym = str(payload.get("symbol") or mctx.get("symbol") or session.symbol or "XAUUSD").strip().upper()
            try:
                hd = float(payload.get("history_days") or mctx.get("history_days") or _agent_default_history_days_for_timeframe(tf_ind))
            except Exception:
                hd = _agent_default_history_days_for_timeframe(tf_ind)
            tf_min = max(1, _agent_timeframe_to_minutes(tf_ind))
            est_count = int((max(0.1, min(60.0, float(hd))) * 1440.0) / float(tf_min)) + 20
            bars_live, live_err = _agent_fetch_live_history_bars(
                source=src,
                symbol=sym,
                timeframe=tf_ind,
                history_days=float(hd),
                count=max(120, min(5000, max(int(bars_limit), est_count))),
                databento_api_key=str(effective_cfg.get("databento_api_key") or ""),
            )
            if len(bars_live) >= 30:
                bars = bars_live
            elif len(bars) < 30:
                return {"ok": False, "error": str(live_err or "live_history_unavailable")}
        try:
            data = _agent_indicator_values_from_bars(bars, max_rows=max(30, min(2000, int(bars_limit))))
            if not data:
                return {"ok": False, "error": "insufficient_bars_for_indicators"}
            return {"ok": True, "data": data}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "get_scheduled_triggers":
        if not bool(perms.get("can_chat", True)):
            return {"ok": False, "error": "permission_denied:can_chat"}
        include_non_pending = bool(payload.get("include_non_pending", False))
        limit = _agent_usage_safe_int(payload.get("limit"), 20)
        try:
            data = _agent_scheduled_triggers_payload(
                session=session,
                db=db,
                include_non_pending=include_non_pending,
                limit=max(1, min(200, int(limit))),
            )
            return {"ok": True, "data": data}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "get_market_news":
        if not bool(perms.get("can_chat", True)):
            return {"ok": False, "error": "permission_denied:can_chat"}
        symbol = str(payload.get("symbol") or session.symbol or "").strip().upper()
        try:
            limit = int(payload.get("limit") or 5)
        except Exception:
            limit = 5
        try:
            lookback_min = int(payload.get("lookback_min") or effective_cfg.get("guardrail_news_lookback_min") or 180)
        except Exception:
            lookback_min = 180
        provider = str(payload.get("provider") or effective_cfg.get("market_news_provider") or "polygon").strip().lower()
        include_summary_raw = payload.get("include_summary")
        if include_summary_raw is None:
            include_summary = bool(effective_cfg.get("market_news_llm_summary_enabled", False))
        else:
            include_summary = bool(include_summary_raw)
        summary_model = str(
            payload.get("summary_model")
            or effective_cfg.get("market_news_summary_model")
            or "claude-haiku-4-5-20251001"
        ).strip()
        try:
            summary_timeout_sec = int(
                payload.get("summary_timeout_sec")
                or effective_cfg.get("market_news_llm_timeout_sec")
                or 8
            )
        except Exception:
            summary_timeout_sec = 8
        ibkr_host = str(effective_cfg.get("market_news_ibkr_host") or "127.0.0.1").strip() or "127.0.0.1"
        try:
            ibkr_port = int(effective_cfg.get("market_news_ibkr_port") or 7497)
        except Exception:
            ibkr_port = 7497
        data = _agent_fetch_market_news(
            symbol=symbol,
            limit=max(1, min(10, int(limit))),
            lookback_min=max(15, min(24 * 60, int(lookback_min))),
            provider=provider,
            include_summary=bool(include_summary),
            summary_model=summary_model,
            summary_timeout_sec=max(4, min(30, int(summary_timeout_sec))),
            ibkr_host=ibkr_host,
            ibkr_port=max(1, min(65535, int(ibkr_port))),
        )
        return {"ok": True, "data": data}

    if tname == "place_trade":
        try:
            logger.info(
                "agent_tool_attempt tool=place_trade session=%s can_place=%s requires_confirm=%s can_auto=%s direction=%s sl=%s tp=%s lot=%s entry=%s",
                int(session.id),
                bool(perms.get("can_place_trades", False)),
                bool(perms.get("requires_user_confirm_for_trade", True)),
                bool(perms.get("can_auto_execute", False)),
                str(payload.get("direction") or "").upper(),
                payload.get("stop_loss"),
                payload.get("take_profit"),
                payload.get("lot_size"),
                payload.get("entry_price"),
            )
        except Exception:
            pass
        if not bool(perms.get("can_place_trades", False)):
            logger.info("agent_tool_blocked tool=place_trade reason=permission_denied:can_place_trades session=%s", int(session.id))
            return {"ok": False, "error": "permission_denied:can_place_trades"}
        guardrails = _agent_trade_guardrails(session=session, db=db, override_config=effective_cfg)
        if not bool(guardrails.get("ok", True)):
            reasons = guardrails.get("reasons") if isinstance(guardrails.get("reasons"), list) else []
            reason = str(reasons[0]) if reasons else "guardrail_blocked"
            return {
                "ok": False,
                "error": f"blocked:guardrail:{reason}",
                "guardrails": {
                    "guardrail_enabled": bool(guardrails.get("guardrail_enabled", True)),
                    "session_filter_enabled": bool(guardrails.get("session_filter_enabled")),
                    "news_filter_enabled": bool(guardrails.get("news_filter_enabled")),
                    "reasons": reasons,
                    "details": guardrails.get("details") if isinstance(guardrails.get("details"), dict) else {},
                },
            }
        if bool(perms.get("requires_user_confirm_for_trade", True)):
            logger.info("agent_tool_blocked tool=place_trade reason=requires_confirmation session=%s", int(session.id))
            return {
                "ok": False,
                "error": "blocked:requires_user_confirm_for_trade",
                "requires_confirmation": True,
                "pending_action": {
                    "tool": "place_trade",
                    "args": {
                        "direction": str(payload.get("direction") or "").strip().upper(),
                        "stop_loss": payload.get("stop_loss"),
                        "take_profit": payload.get("take_profit"),
                        "lot_size": payload.get("lot_size"),
                        "entry_price": payload.get("entry_price"),
                        "bar_time_unix": payload.get("bar_time_unix"),
                        "cost_spread": payload.get("cost_spread"),
                        "cost_tc_rate": payload.get("cost_tc_rate"),
                        "cost_spread_source": payload.get("cost_spread_source"),
                    },
                    "message": "Trade requires explicit user approval before execution.",
                },
            }
        try:
            req = TradeRequest(
                direction=str(payload.get("direction") or "").strip().upper(),
                stop_loss=float(payload.get("stop_loss")),
                take_profit=_to_float_or_none(payload.get("take_profit")),
                lot_size=float(payload.get("lot_size") or 0.01),
                entry_price=_to_float_or_none(payload.get("entry_price")),
                bar_time_unix=int(payload.get("bar_time_unix")) if payload.get("bar_time_unix") is not None else None,
                cost_spread=_to_float_or_none(payload.get("cost_spread")),
                cost_tc_rate=_to_float_or_none(payload.get("cost_tc_rate")),
                cost_spread_source=str(payload.get("cost_spread_source")) if payload.get("cost_spread_source") is not None else None,
            )
            if atomic:
                prev_suppress = bool(getattr(db, "_suppress_commit", False))
                setattr(db, "_suppress_commit", True)
                try:
                    data = execute_trade(session_id=int(session.id), req=req, db=db)
                finally:
                    setattr(db, "_suppress_commit", prev_suppress)
            else:
                data = execute_trade(session_id=int(session.id), req=req, db=db)
            try:
                logger.info(
                    "agent_tool_executed tool=place_trade session=%s trade_id=%s direction=%s entry=%s",
                    int(session.id),
                    data.get("id") if isinstance(data, dict) else None,
                    str(data.get("direction") if isinstance(data, dict) else req.direction),
                    data.get("entry_price") if isinstance(data, dict) else None,
                )
            except Exception:
                pass
            return {"ok": True, "data": data}
        except HTTPException as exc:
            logger.warning(
                "agent_tool_error tool=place_trade session=%s http_error=%s",
                int(session.id),
                str(exc.detail),
            )
            return {"ok": False, "error": str(exc.detail)}
        except Exception as exc:
            logger.warning(
                "agent_tool_error tool=place_trade session=%s err=%s",
                int(session.id),
                f"{type(exc).__name__}: {str(exc)[:180]}",
            )
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "schedule_trade_entry":
        if not bool(perms.get("can_place_trades", False)):
            return {"ok": False, "error": "permission_denied:can_place_trades"}
        schedule_guardrail_policy = {
            "guardrail_enabled": bool(effective_cfg.get("guardrail_enabled", True)),
            "session_filter_enabled": bool(effective_cfg.get("guardrail_session_filter_enabled", False)),
            "news_filter_enabled": bool(effective_cfg.get("guardrail_news_filter_enabled", False)),
            "news_lookback_min": max(15, min(24 * 60, int(effective_cfg.get("guardrail_news_lookback_min") or 120))),
            "news_provider": str(effective_cfg.get("market_news_provider") or "polygon").strip().lower() or "polygon",
            "news_ibkr_host": str(effective_cfg.get("market_news_ibkr_host") or "127.0.0.1").strip() or "127.0.0.1",
            "news_ibkr_port": max(1, min(65535, int(_agent_usage_safe_int(effective_cfg.get("market_news_ibkr_port"), 7497)))),
            "trigger_requires_approval": bool(effective_cfg.get("watchdog_trigger_requires_approval", False)),
        }
        condition = _normalize_agent_trigger_condition(payload.get("condition"))
        if condition is None:
            return {"ok": False, "error": "invalid_condition"}
        try:
            trigger_price = float(payload.get("trigger_price"))
        except Exception:
            return {"ok": False, "error": "invalid_trigger_price"}
        if not math.isfinite(trigger_price) or trigger_price <= 0:
            return {"ok": False, "error": "invalid_trigger_price"}

        direction = str(payload.get("direction") or "").strip().upper()
        if direction not in {"BUY", "SELL"}:
            return {"ok": False, "error": "invalid_direction"}
        try:
            stop_loss = float(payload.get("stop_loss"))
        except Exception:
            return {"ok": False, "error": "invalid_stop_loss"}
        if not math.isfinite(stop_loss) or stop_loss <= 0:
            return {"ok": False, "error": "invalid_stop_loss"}
        take_profit = _to_float_or_none(payload.get("take_profit"))
        lot_size = _to_float_or_none(payload.get("lot_size"))
        lot_value = float(lot_size if lot_size is not None else 0.01)
        if lot_value <= 0.0:
            lot_value = 0.01
        if lot_value > 100.0:
            lot_value = 100.0
        # Server-side math validation and lot normalization.
        # This guards against LLM arithmetic errors before persisting trigger state.
        entry_ref = _to_float_or_none(payload.get("entry_ref"))
        if entry_ref is None:
            entry_ref = float(trigger_price)
        if entry_ref is None or (not math.isfinite(float(entry_ref))) or float(entry_ref) <= 0:
            return {"ok": False, "error": "invalid_entry_ref"}
        entry_ref = float(entry_ref)
        if not _validate_entry_levels(direction, float(entry_ref), float(stop_loss), take_profit):
            return {"ok": False, "error": "invalid_levels_for_entry_ref"}
        risk_distance = abs(float(entry_ref) - float(stop_loss))
        if (not math.isfinite(risk_distance)) or risk_distance <= 0.0:
            return {"ok": False, "error": "invalid_risk_distance"}
        reward_distance: Optional[float] = None
        rr_calc: Optional[float] = None
        if take_profit is not None:
            reward_distance = abs(float(take_profit) - float(entry_ref))
            if (not math.isfinite(float(reward_distance))) or float(reward_distance) <= 0.0:
                return {"ok": False, "error": "invalid_reward_distance"}
            rr_calc = float(reward_distance) / float(risk_distance)
        expected_rr = _to_float_or_none(payload.get("expected_rr"))
        if expected_rr is not None:
            if rr_calc is None:
                return {"ok": False, "error": "expected_rr_requires_take_profit"}
            if (not math.isfinite(float(expected_rr))) or float(expected_rr) <= 0.0:
                return {"ok": False, "error": "invalid_expected_rr"}
            if abs(float(rr_calc) - float(expected_rr)) > 0.10:
                return {
                    "ok": False,
                    "error": "rr_mismatch",
                    "details": {
                        "expected_rr": round(float(expected_rr), 4),
                        "calculated_rr": round(float(rr_calc), 4),
                    },
                }
        min_rr = _to_float_or_none(payload.get("min_rr"))
        if min_rr is not None:
            if rr_calc is None:
                return {"ok": False, "error": "min_rr_requires_take_profit"}
            if float(rr_calc) + 1e-9 < float(min_rr):
                return {
                    "ok": False,
                    "error": "rr_below_min",
                    "details": {
                        "min_rr": round(float(min_rr), 4),
                        "calculated_rr": round(float(rr_calc), 4),
                    },
                }
        inst = get_instrument(str(session.symbol or "XAUUSD").upper())
        lot_value = _normalize_lot_for_instrument(
            lot_size=float(lot_value),
            min_lot=float(inst.min_lot),
            max_lot=min(100.0, float(inst.max_lot)),
            lot_step=float(inst.lot_step),
        )
        risk_amount = _to_float_or_none(payload.get("risk_amount"))
        risk_percent = _to_float_or_none(payload.get("risk_percent"))
        account_balance = _to_float_or_none(payload.get("account_balance"))
        if account_balance is None:
            account_balance = _to_float_or_none(session.current_balance)
        if account_balance is None:
            account_balance = _to_float_or_none(session.initial_balance)
        if risk_amount is None and risk_percent is not None and account_balance is not None and account_balance > 0:
            # risk_percent is interpreted as percent (e.g. 0.5 => 0.5%).
            risk_amount = float(account_balance) * (float(risk_percent) / 100.0)
        if risk_amount is not None:
            if (not math.isfinite(float(risk_amount))) or float(risk_amount) <= 0.0:
                return {"ok": False, "error": "invalid_risk_amount"}
            value_per_1lot = _to_float_or_none(payload.get("point_value_per_1lot"))
            if value_per_1lot is None:
                value_per_1lot = float(inst.contract_size)
            if (not math.isfinite(float(value_per_1lot))) or float(value_per_1lot) <= 0.0:
                return {"ok": False, "error": "invalid_point_value_per_1lot"}
            expected_lot_raw = float(risk_amount) / (float(risk_distance) * float(value_per_1lot))
            expected_lot = _normalize_lot_for_instrument(
                lot_size=expected_lot_raw,
                min_lot=float(inst.min_lot),
                max_lot=min(100.0, float(inst.max_lot)),
                lot_step=float(inst.lot_step),
            )
            lot_tol = max(float(inst.lot_step) * 1.01, 0.01)
            if abs(float(lot_value) - float(expected_lot)) > float(lot_tol):
                return {
                    "ok": False,
                    "error": "lot_size_mismatch_with_risk_model",
                    "details": {
                        "provided_lot_size": round(float(lot_value), 4),
                        "expected_lot_size": round(float(expected_lot), 4),
                        "risk_amount": round(float(risk_amount), 4),
                        "risk_distance": round(float(risk_distance), 5),
                        "value_per_1lot": round(float(value_per_1lot), 6),
                    },
                }
        if not _validate_entry_levels(direction, float(trigger_price), float(stop_loss), take_profit):
            return {"ok": False, "error": "invalid_levels_for_trigger_price"}
        timeframe = str(payload.get("timeframe") or session.timeframe or "M15").strip().upper()
        if timeframe not in {"M1", "M5", "M15", "M30", "H1", "H4", "D1"}:
            timeframe = str(session.timeframe or "M15").strip().upper() or "M15"
        expires_sec = _agent_usage_safe_int(payload.get("expires_sec"), 6 * 3600)
        expires_sec = max(60, min(7 * 24 * 3600, int(expires_sec)))
        pre_raw = payload.get("precondition") if isinstance(payload.get("precondition"), dict) else {}
        pre_cond_raw = payload.get("precondition_condition")
        if pre_cond_raw is None and isinstance(pre_raw, dict):
            pre_cond_raw = pre_raw.get("condition")
        pre_price_raw = payload.get("precondition_price")
        if pre_price_raw is None and isinstance(pre_raw, dict):
            pre_price_raw = pre_raw.get("trigger_price")
        pre_cond_present = pre_cond_raw is not None and str(pre_cond_raw).strip() != ""
        pre_price_present = pre_price_raw is not None and str(pre_price_raw).strip() != ""
        has_precondition_fields = pre_cond_present or pre_price_present
        precondition: Optional[Dict[str, Any]] = None
        if has_precondition_fields:
            if not (pre_cond_present and pre_price_present):
                return {"ok": False, "error": "precondition_incomplete:provide_condition_and_trigger_price"}
            pre_cond = _normalize_agent_trigger_condition(pre_cond_raw)
            if pre_cond is None:
                return {"ok": False, "error": "invalid_precondition_condition"}
            try:
                pre_price = float(pre_price_raw)
            except Exception:
                return {"ok": False, "error": "invalid_precondition_price"}
            if not math.isfinite(pre_price) or pre_price <= 0:
                return {"ok": False, "error": "invalid_precondition_price"}
            if str(pre_cond) == str(condition) and abs(float(pre_price) - float(trigger_price)) < 1e-9:
                return {"ok": False, "error": "precondition_must_differ_from_entry_condition"}
            precondition = {
                "condition": str(pre_cond),
                "trigger_price": float(pre_price),
            }
        cancel_raw = payload.get("cancel_rule") if isinstance(payload.get("cancel_rule"), dict) else {}
        cancel_cond_raw = payload.get("cancel_condition")
        if cancel_cond_raw is None and isinstance(cancel_raw, dict):
            cancel_cond_raw = cancel_raw.get("condition")
        cancel_price_raw = payload.get("cancel_trigger_price")
        if cancel_price_raw is None and isinstance(cancel_raw, dict):
            cancel_price_raw = cancel_raw.get("trigger_price")
        cancel_cond_present = cancel_cond_raw is not None and str(cancel_cond_raw).strip() != ""
        cancel_price_present = cancel_price_raw is not None and str(cancel_price_raw).strip() != ""
        has_cancel_fields = cancel_cond_present or cancel_price_present
        cancel_rule: Optional[Dict[str, Any]] = None
        if has_cancel_fields:
            if not (cancel_cond_present and cancel_price_present):
                return {"ok": False, "error": "cancel_rule_incomplete:provide_condition_and_trigger_price"}
            cancel_cond = _normalize_agent_trigger_condition(cancel_cond_raw)
            if cancel_cond is None:
                return {"ok": False, "error": "invalid_cancel_condition"}
            try:
                cancel_price = float(cancel_price_raw)
            except Exception:
                return {"ok": False, "error": "invalid_cancel_trigger_price"}
            if not math.isfinite(cancel_price) or cancel_price <= 0:
                return {"ok": False, "error": "invalid_cancel_trigger_price"}
            if str(cancel_cond) == str(condition) and abs(float(cancel_price) - float(trigger_price)) < 1e-9:
                return {"ok": False, "error": "cancel_rule_must_differ_from_entry_condition"}
            cancel_rule = {
                "condition": str(cancel_cond),
                "trigger_price": float(cancel_price),
            }

        trigger = {
            "id": f"trg_{uuid.uuid4().hex[:10]}",
            "status": "pending",
            "state": "waiting_precondition" if isinstance(precondition, dict) else "waiting_entry",
            "created_at": _utc_now().isoformat(),
            "expires_at": (_utc_now() + timedelta(seconds=int(expires_sec))).isoformat(),
            "condition": str(condition),
            "trigger_price": float(trigger_price),
            "timeframe": str(timeframe),
            "trade_args": {
                "direction": str(direction),
                "stop_loss": float(stop_loss),
                "take_profit": float(take_profit) if take_profit is not None else None,
                "lot_size": float(lot_value),
                "entry_price": None,
            },
            "validation": {
                "entry_ref": float(entry_ref),
                "risk_distance": float(risk_distance),
                "reward_distance": float(reward_distance) if reward_distance is not None else None,
                "rr": float(rr_calc) if rr_calc is not None else None,
                "symbol": str(inst.symbol),
                "contract_size": float(inst.contract_size),
                "min_lot": float(inst.min_lot),
                "max_lot": float(inst.max_lot),
                "lot_step": float(inst.lot_step),
            },
            "guardrails": schedule_guardrail_policy,
        }
        if isinstance(precondition, dict):
            trigger["precondition"] = dict(precondition)
        if isinstance(cancel_rule, dict):
            trigger["cancel_rule"] = dict(cancel_rule)

        agent_row = _get_active_agent(simulation_session_id=int(session.id), db=db)
        if agent_row is None:
            agent_row = _get_latest_agent(simulation_session_id=int(session.id), db=db)
        if agent_row is None:
            return {"ok": False, "error": "agent_session_not_found"}
        triggers = _get_agent_trade_triggers(agent_row)

        # Keep unique pending triggers for the same semantic setup.
        pre_sem = "none"
        if isinstance(precondition, dict):
            pre_sem = f"{str(precondition.get('condition') or '').lower()}@{round(float(precondition.get('trigger_price') or 0.0), 5)}"
        cancel_sem = "none"
        if isinstance(cancel_rule, dict):
            cancel_sem = f"{str(cancel_rule.get('condition') or '').lower()}@{round(float(cancel_rule.get('trigger_price') or 0.0), 5)}"
        sem = (
            f"{condition}|{round(float(trigger_price), 5)}|{direction}|"
            f"{round(float(stop_loss), 5)}|{round(float(take_profit), 5) if take_profit is not None else 'none'}|"
            f"{round(float(lot_value), 3)}|{timeframe}|pre={pre_sem}|cancel={cancel_sem}"
        )
        for t in triggers:
            if not isinstance(t, dict):
                continue
            if str(t.get("status") or "").lower() != "pending":
                continue
            ta = t.get("trade_args") if isinstance(t.get("trade_args"), dict) else {}
            tpv = _to_float_or_none(ta.get("take_profit"))
            tp_pre = t.get("precondition") if isinstance(t.get("precondition"), dict) else None
            tp_pre_sem = "none"
            if isinstance(tp_pre, dict):
                tp_pre_sem = (
                    f"{str(tp_pre.get('condition') or '').lower()}@"
                    f"{round(_to_float_or_none(tp_pre.get('trigger_price')) or 0.0, 5)}"
                )
            tp_cancel = t.get("cancel_rule") if isinstance(t.get("cancel_rule"), dict) else None
            tp_cancel_sem = "none"
            if isinstance(tp_cancel, dict):
                tp_cancel_sem = (
                    f"{str(tp_cancel.get('condition') or '').lower()}@"
                    f"{round(_to_float_or_none(tp_cancel.get('trigger_price')) or 0.0, 5)}"
                )
            sem_t = (
                f"{str(t.get('condition') or '').lower()}|{round(_to_float_or_none(t.get('trigger_price')) or 0.0, 5)}|"
                f"{str(ta.get('direction') or '').upper()}|{round(_to_float_or_none(ta.get('stop_loss')) or 0.0, 5)}|"
                f"{round(float(tpv), 5) if tpv is not None else 'none'}|"
                f"{round(_to_float_or_none(ta.get('lot_size')) or 0.01, 3)}|{str(t.get('timeframe') or '').upper()}|"
                f"pre={tp_pre_sem}|cancel={tp_cancel_sem}"
            )
            if sem_t == sem:
                return {"ok": True, "data": {"trigger": t, "deduped": True, "pending_count": int(len(triggers))}}

        triggers.append(trigger)
        _set_agent_trade_triggers(agent_row=agent_row, triggers=triggers)
        db.add(agent_row)
        return {"ok": True, "data": {"trigger": trigger, "pending_count": int(len(triggers))}}

    if tname == "cancel_scheduled_entry":
        agent_row = _get_active_agent(simulation_session_id=int(session.id), db=db)
        if agent_row is None:
            agent_row = _get_latest_agent(simulation_session_id=int(session.id), db=db)
        if agent_row is None:
            return {"ok": False, "error": "agent_session_not_found"}
        trigger_id = str(payload.get("trigger_id") or "").strip()
        cancel_all = bool(payload.get("cancel_all", False))
        triggers = _get_agent_trade_triggers(agent_row)
        if not triggers:
            return {"ok": True, "data": {"cancelled": 0, "pending_count": 0}}
        cancelled = 0
        next_triggers: List[Dict[str, Any]] = []
        for t in triggers:
            if not isinstance(t, dict):
                continue
            st = str(t.get("status") or "").lower()
            tid = str(t.get("id") or "").strip()
            should_cancel = False
            if st == "pending":
                if cancel_all:
                    should_cancel = True
                elif trigger_id and tid == trigger_id:
                    should_cancel = True
            if should_cancel:
                t2 = dict(t)
                t2["status"] = "canceled"
                t2["canceled_at"] = _utc_now().isoformat()
                next_triggers.append(t2)
                cancelled += 1
            else:
                next_triggers.append(dict(t))
        _set_agent_trade_triggers(agent_row=agent_row, triggers=next_triggers)
        db.add(agent_row)
        pending_count = sum(1 for t in next_triggers if isinstance(t, dict) and str(t.get("status") or "").lower() == "pending")
        return {"ok": True, "data": {"cancelled": int(cancelled), "pending_count": int(pending_count)}}

    if tname == "close_trade":
        try:
            logger.info(
                "agent_tool_attempt tool=close_trade session=%s can_close=%s requires_confirm=%s trade_id=%s",
                int(session.id),
                bool(perms.get("can_close_trades", False)),
                bool(perms.get("requires_user_confirm_for_trade", True)),
                payload.get("trade_id"),
            )
        except Exception:
            pass
        if not bool(perms.get("can_close_trades", False)):
            logger.info("agent_tool_blocked tool=close_trade reason=permission_denied:can_close_trades session=%s", int(session.id))
            return {"ok": False, "error": "permission_denied:can_close_trades"}
        trade_id_raw = payload.get("trade_id")
        try:
            trade_id = int(trade_id_raw)
        except Exception:
            return {"ok": False, "error": "invalid_trade_id"}
        trade_row = (
            db.query(SimulationTrade)
            .filter(SimulationTrade.id == int(trade_id))
            .filter(SimulationTrade.session_id == int(session.id))
            .filter(SimulationTrade.status == "open")
            .first()
        )
        if trade_row is None:
            return {"ok": False, "error": "trade_not_open_or_not_found"}
        if bool(perms.get("requires_user_confirm_for_trade", True)):
            logger.info("agent_tool_blocked tool=close_trade reason=requires_confirmation session=%s", int(session.id))
            return {
                "ok": False,
                "error": "blocked:requires_user_confirm_for_trade",
                "requires_confirmation": True,
                "pending_action": {
                    "tool": "close_trade",
                    "args": {
                        "trade_id": int(trade_id),
                        "exit_price": payload.get("exit_price"),
                        "bar_time_unix": payload.get("bar_time_unix"),
                        "cost_spread": payload.get("cost_spread"),
                        "cost_tc_rate": payload.get("cost_tc_rate"),
                        "cost_spread_source": payload.get("cost_spread_source"),
                    },
                    "message": "Close trade requires explicit user approval before execution.",
                },
            }
        try:
            req = CloseTradeRequest(
                exit_price=_to_float_or_none(payload.get("exit_price")),
                bar_time_unix=int(payload.get("bar_time_unix")) if payload.get("bar_time_unix") is not None else None,
                cost_spread=_to_float_or_none(payload.get("cost_spread")),
                cost_tc_rate=_to_float_or_none(payload.get("cost_tc_rate")),
                cost_spread_source=str(payload.get("cost_spread_source")) if payload.get("cost_spread_source") is not None else None,
            )
            if atomic:
                prev_suppress = bool(getattr(db, "_suppress_commit", False))
                setattr(db, "_suppress_commit", True)
                try:
                    data = close_trade(session_id=int(session.id), trade_id=trade_id, req=req, db=db)
                finally:
                    setattr(db, "_suppress_commit", prev_suppress)
            else:
                data = close_trade(session_id=int(session.id), trade_id=trade_id, req=req, db=db)
            try:
                logger.info(
                    "agent_tool_executed tool=close_trade session=%s trade_id=%s exit_price=%s",
                    int(session.id),
                    int(trade_id),
                    data.get("exit_price") if isinstance(data, dict) else None,
                )
            except Exception:
                pass
            return {"ok": True, "data": data}
        except HTTPException as exc:
            logger.warning(
                "agent_tool_error tool=close_trade session=%s http_error=%s",
                int(session.id),
                str(exc.detail),
            )
            return {"ok": False, "error": str(exc.detail)}
        except Exception as exc:
            logger.warning(
                "agent_tool_error tool=close_trade session=%s err=%s",
                int(session.id),
                f"{type(exc).__name__}: {str(exc)[:180]}",
            )
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "run_research_optimize":
        if not bool(perms.get("can_use_research", False)):
            return {"ok": False, "error": "permission_denied:can_use_research"}
        try:
            bars = payload.get("bars") if isinstance(payload.get("bars"), list) else (context_snapshot.get("bars") if isinstance(context_snapshot.get("bars"), list) else [])
            req = ResearchOptimizeRequest(
                strategy_type=str(payload.get("strategy_type") or "sma_crossover"),
                params=payload.get("params") if isinstance(payload.get("params"), dict) else {},
                top_n=int(payload.get("top_n") or 15),
                tc_rate=float(payload.get("tc_rate") or DEFAULT_TC_RATE),
                max_combinations=int(payload.get("max_combinations") or 2500),
                bars=bars if isinstance(bars, list) else [],
            )
            data = workbench_research_optimize(session_id=int(session.id), req=req, db=db)
            return {"ok": True, "data": data}
        except HTTPException as exc:
            return {"ok": False, "error": str(exc.detail)}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "run_ml_diagnostic":
        if not bool(perms.get("can_use_research", False)):
            return {"ok": False, "error": "permission_denied:can_use_research"}
        try:
            bars = payload.get("bars") if isinstance(payload.get("bars"), list) else (context_snapshot.get("bars") if isinstance(context_snapshot.get("bars"), list) else [])
            req = ResearchMLDiagnosticRequest(
                lags=int(payload.get("lags") or 5),
                split_ratio=float(payload.get("split_ratio") or 0.7),
                drift_warn_pct=float(payload.get("drift_warn_pct") or 50.0),
                params=payload.get("params") if isinstance(payload.get("params"), dict) else {},
                bars=bars if isinstance(bars, list) else [],
            )
            data = workbench_research_ml_diagnostic(session_id=int(session.id), req=req, db=db)
            return {"ok": True, "data": data}
        except HTTPException as exc:
            return {"ok": False, "error": str(exc.detail)}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "set_indicator_visibility":
        if not bool(perms.get("can_manage_indicators", True)):
            return {"ok": False, "error": "permission_denied:can_manage_indicators"}
        vis = payload.get("visibility") if isinstance(payload.get("visibility"), dict) else {}
        return {"ok": True, "data": {"visibility": vis, "note": "frontend_apply_required"}}

    if tname == "set_market_context":
        # Frontend applies live/replay context switch; backend validates and returns sanitized payload.
        allowed_symbols = {"XAUUSD", "NAS100", "US500", "GBPUSD", "EURUSD"}
        allowed_tfs = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"}
        symbol = str(payload.get("symbol") or session.symbol or "XAUUSD").strip().upper()
        timeframe = str(payload.get("timeframe") or session.timeframe or "M15").strip().upper()
        source = str(payload.get("source") or "mt5").strip().lower()
        try:
            history_days = float(payload.get("history_days") if payload.get("history_days") is not None else 2.0)
        except Exception:
            history_days = 2.0
        if symbol not in allowed_symbols:
            symbol = str(session.symbol or "XAUUSD").strip().upper() or "XAUUSD"
        if timeframe not in allowed_tfs:
            timeframe = str(session.timeframe or "M15").strip().upper() or "M15"
        if source not in {"mt5", "databento"}:
            source = "mt5"
        history_days = max(0.1, min(60.0, history_days))
        return {
            "ok": True,
            "data": {
                "tool_id": "set_market_context",
                "symbol": symbol,
                "timeframe": timeframe,
                "source": source,
                "history_days": history_days,
                "note": "frontend_apply_required",
            },
        }

    if tname == "set_agent_personality":
        profile = str(
            payload.get("profile")
            or payload.get("preset")
            or payload.get("personality")
            or ""
        ).strip()
        preset_key, patch = _agent_identity_preset_payload(profile)
        if preset_key is None or not isinstance(patch, dict):
            return {"ok": False, "error": "invalid_profile:use_master_quant_or_apprentice"}
        if payload.get("lock_personality") is not None:
            patch["lock_personality"] = bool(payload.get("lock_personality"))
        clean = _agent_identity_update_session_config(session=session, patch=patch)
        db.add(session)
        return {
            "ok": True,
            "data": {
                "profile": str(preset_key),
                "identity": clean,
                "message": f"Agent personality switched to {preset_key}.",
            },
        }

    if tname == "search_memory":
        query = str(payload.get("query") or "").strip()
        if not query:
            return {"ok": False, "error": "missing_query"}
        try:
            limit = int(payload.get("limit") or 8)
        except Exception:
            limit = 8
        mtype = str(payload.get("memory_type") or "").strip() or None
        try:
            hits = _agent_memory_search(
                simulation_session=session,
                db=db,
                query_text=query,
                limit=max(1, min(20, limit)),
                memory_type=mtype,
            )
            return {"ok": True, "data": {"query": query, "hits": hits, "count": int(len(hits))}}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

    if tname == "save_memory_note":
        content = str(payload.get("content") or "").strip()
        if len(content) < 8:
            return {"ok": False, "error": "content_too_short"}
        scope = _normalize_memory_scope(payload.get("scope"))
        mtype = _normalize_memory_type(payload.get("memory_type") or "note")
        try:
            importance = float(payload.get("importance") if payload.get("importance") is not None else 0.8)
        except Exception:
            importance = 0.8
        metadata = payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {}
        row = _agent_memory_add(
            simulation_session=session,
            db=db,
            content=content,
            memory_type=mtype,
            scope=scope,
            importance=max(0.0, min(1.0, importance)),
            source="agent_tool",
            metadata=metadata,
            symbol=str(payload.get("symbol") or "") or None,
            timeframe=str(payload.get("timeframe") or "") or None,
        )
        if row is None:
            return {"ok": False, "error": "memory_rejected"}
        return {
            "ok": True,
            "data": {
                "id": int(row.id),
                "scope": str(row.scope or ""),
                "memory_type": str(row.memory_type or ""),
                "content": str(row.content or ""),
                "importance": float(row.importance or 0.0),
            },
        }

    return {"ok": False, "error": f"unknown_tool:{tname or 'empty'}"}


def _agent_tool_state_from_tool_calls(tool_calls: Any) -> Dict[str, Any]:
    """Extract tool_state patch from agent tool call results.

    This is needed when agent chat/run-once executes without an active copilot loop;
    in that case tool scan outputs should still be visible to the UI from agent snapshot.
    """
    patch: Dict[str, Any] = {}
    calls = tool_calls if isinstance(tool_calls, list) else []
    for raw in calls:
        if not isinstance(raw, dict):
            continue
        tool_name = str(raw.get("tool_id") or "").strip().lower()
        result = raw.get("result") if isinstance(raw.get("result"), dict) else {}
        if not result or (result.get("ok") is False):
            continue
        data = result.get("data") if isinstance(result.get("data"), dict) else {}
        if not data:
            continue

        if tool_name in {"scan_tool", "scan_draw_fvg_range"}:
            args = raw.get("args") if isinstance(raw.get("args"), dict) else {}
            cfg = args.get("config") if isinstance(args.get("config"), dict) else {}
            scanned_tool = str(
                data.get("tool_id")
                or args.get("tool_id")
                or ("fvg" if tool_name == "scan_draw_fvg_range" else "")
            ).strip().lower()
            if scanned_tool not in {"fvg", "mean_rev", "liquidity"}:
                continue
            zones = data.get("zones") if isinstance(data.get("zones"), list) else []
            zones_preview = _build_tool_zone_preview(zones)
            try:
                zones_count = int(data.get("count"))
            except Exception:
                zones_count = int(len(zones))
            if not isinstance(cfg, dict):
                cfg = {}
            if data.get("scan_timeframe") is not None:
                cfg = {**cfg, "timeframe": str(data.get("scan_timeframe") or "")}
            trend = data.get("trend") if isinstance(data.get("trend"), dict) else {}
            movement_strength = data.get("movement_strength") if isinstance(data.get("movement_strength"), dict) else {}
            current_state = data.get("current_state") if isinstance(data.get("current_state"), dict) else {}
            scan_source = str(
                data.get("scan_source")
                or ("agent_draw_selection" if tool_name == "scan_draw_fvg_range" else "agent_scan")
            )
            tsp = _build_tool_state_patch(
                tool_id=scanned_tool,
                zones_count=zones_count,
                zones_preview=zones_preview,
                config=cfg,
                trend=trend,
                movement_strength=movement_strength,
                current_state=current_state,
                scan_source=scan_source,
            )
            patch.update(tsp)
            if tool_name == "scan_draw_fvg_range":
                selection = result.get("selection") if isinstance(result.get("selection"), dict) else {}
                if selection:
                    patch["draw_fvg_selection"] = {
                        "start_index": int(selection.get("start_index") or 0),
                        "end_index": int(selection.get("end_index") or 0),
                        "bars": int(selection.get("bars") or 0),
                    }
        elif tool_name == "run_mtf_analysis":
            tsp = data.get("tool_state_patch") if isinstance(data.get("tool_state_patch"), dict) else {}
            if tsp:
                patch.update(tsp)

        if tool_name == "set_indicator_visibility":
            vis = data.get("visibility") if isinstance(data.get("visibility"), dict) else {}
            if vis:
                patch["indicator_visibility"] = vis
        elif tool_name == "set_market_context":
            try:
                history_days = float(data.get("history_days") or 0.0)
            except Exception:
                history_days = 0.0
            patch["market_context"] = {
                "symbol": str(data.get("symbol") or ""),
                "timeframe": str(data.get("timeframe") or ""),
                "source": str(data.get("source") or ""),
                "history_days": history_days,
            }

    return patch


def _normalize_live_bar(raw: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(raw, dict):
        return None
    try:
        t = int(raw.get("time") or 0)
        o = float(raw.get("open"))
        h = float(raw.get("high"))
        l = float(raw.get("low"))
        c = float(raw.get("close"))
        v = float(raw.get("volume") or 0.0)
        if t <= 0:
            return None
        if not all(math.isfinite(x) for x in (o, h, l, c, v)):
            return None
        return {
            "time": t,
            "open": o,
            "high": h,
            "low": l,
            "close": c,
            "volume": v,
        }
    except Exception:
        return None


def _bars_payload_to_df(
    bars: Any,
    *,
    max_rows: int,
    min_rows: int,
) -> Optional[pd.DataFrame]:
    """Parse client-provided bars into a normalized OHLCV DataFrame."""
    if not isinstance(bars, list) or len(bars) < int(min_rows):
        return None
    rows: List[Dict[str, float]] = []
    for b in bars[: max(1, int(max_rows))]:
        if not isinstance(b, dict):
            continue
        try:
            t = int(b.get("time") or 0)
            o = float(b.get("open"))
            h = float(b.get("high"))
            l = float(b.get("low"))
            c = float(b.get("close"))
            v = float(b.get("volume") or 0.0)
            if t <= 0:
                continue
            rows.append({"time": t, "open": o, "high": h, "low": l, "close": c, "volume": v})
        except Exception:
            continue
    if len(rows) < int(min_rows):
        return None
    bars_df = pd.DataFrame(rows)
    bars_df = bars_df.sort_values("time").drop_duplicates(subset=["time"], keep="last")
    bars_df["dt"] = pd.to_datetime(bars_df["time"], unit="s", utc=True, errors="coerce")
    bars_df = bars_df.dropna(subset=["dt"]).set_index("dt")
    bars_df = bars_df[["open", "high", "low", "close", "volume"]]
    if bars_df.empty or len(bars_df) < int(min_rows):
        return None
    return bars_df


def _build_live_advance_result(
    session: SimulationSession,
    tool_state_payload: Dict[str, Any],
    db: Session,
) -> Optional[Dict[str, Any]]:
    live_bar = _normalize_live_bar(tool_state_payload.get("live_bar"))
    if live_bar is None:
        return None

    live_stream = tool_state_payload.get("live_stream") if isinstance(tool_state_payload.get("live_stream"), dict) else {}
    try:
        current_bar = int(live_stream.get("bar_index") or session.current_bar or 0)
    except Exception:
        current_bar = int(session.current_bar or 0)
    try:
        total_bars = int(live_stream.get("total_bars") or max(current_bar + 1, int(session.total_bars or 0)))
    except Exception:
        total_bars = max(current_bar + 1, int(session.total_bars or 0))

    # Keep open positions in snapshot consistent for event/policy logic.
    open_rows = (
        db.query(SimulationTrade)
        .filter(SimulationTrade.session_id == int(session.id))
        .filter(SimulationTrade.status == "open")
        .order_by(SimulationTrade.id.asc())
        .all()
    )
    open_positions: List[Dict[str, Any]] = []
    for t in open_rows:
        open_positions.append(
            {
                "id": int(t.id),
                "direction": str(t.direction or ""),
                "entry_price": float(t.entry_price),
                "entry_bar": int(t.entry_bar or 0),
                "entry_time": str(t.entry_time or ""),
                "stop_loss": float(t.stop_loss),
                "take_profit": float(t.take_profit) if t.take_profit is not None else None,
                "lot_size": float(t.lot_size or 0.01),
            }
        )

    indicators = tool_state_payload.get("indicator_last")
    if not isinstance(indicators, dict):
        indicators = {}

    return {
        "current_bar": int(max(0, current_bar)),
        "total_bars": int(max(1, total_bars)),
        "bars": [live_bar],
        "indicators": indicators,
        "open_positions": open_positions,
        "closed_trades": [],
        "open_pnl": 0.0,
        "balance": float(session.current_balance or 0.0),
        "initial_balance": float(session.initial_balance or 0.0),
        "trades_count": int(session.trades_count or 0),
        "wins": int(session.wins or 0),
        "losses": int(session.losses or 0),
        "total_pnl": float(session.total_pnl or 0.0),
        "status": str(session.status or "active"),
        "tool_state": tool_state_payload,
    }


def _ai_run_to_dict(row: AIBotRunModel) -> Dict[str, Any]:
    report = row.report_json if isinstance(row.report_json, dict) else {}
    req = row.request_json if isinstance(row.request_json, dict) else {}
    return {
        "run_id": str(row.run_id),
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "status": str(row.status or "UNKNOWN"),
        "strategy_id": str(row.strategy_id or ""),
        "context_id": str(row.context_id or ""),
        "provider": str(row.provider or "deterministic"),
        "model_label": str(row.model_label or ""),
        "llm_used": bool(report.get("llm_used")),
        "request": req,
        "report": report,
        "error": row.error,
    }


@router.post("/sessions/{session_id}/tools/{tool_id}/scan")
def workbench_scan_tool(
    session_id: int,
    tool_id: str,
    req: ToolScanRequest = ToolScanRequest(),
    db: Session = Depends(get_db),
):
    """Run a workbench tool scan on the current visible bars."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    tool = get_tool(tool_id)
    if not tool:
        raise HTTPException(404, f"Unknown tool: {tool_id}")

    engine = _get_or_create_engine(session, db)
    has_client_bars = isinstance(req.bars, list) and len(req.bars) >= 3
    if (engine.df is None or engine.df.empty) and not has_client_bars:
        return {"tool_id": tool_id, "zones": []}

    # Default source: replay engine bars up to current position.
    visible_df = engine.df.iloc[: engine.current_bar + 1] if (engine.df is not None and not engine.df.empty) else None
    scan_df = visible_df

    # If client provided chart bars (live mode), prefer those for scan accuracy.
    scan_source = "engine_visible"
    if has_client_bars:
        bars_df = _bars_payload_to_df(req.bars, max_rows=20000, min_rows=3)
        if bars_df is not None:
            scan_df = bars_df
            scan_source = "client_live"

    if scan_df is None or len(scan_df) == 0:
        return {"tool_id": tool_id, "zones": [], "scan_source": scan_source, "count": 0}

    raw_cfg = req.config if isinstance(req.config, dict) else {}
    try:
        lookback_bars = int(raw_cfg.get("lookback_bars") or 0)
    except Exception:
        lookback_bars = 0
    if lookback_bars > 0:
        scan_df = scan_df.tail(max(3, lookback_bars))
    try:
        lookback_days = float(raw_cfg.get("lookback_days") or 0.0)
    except Exception:
        lookback_days = 0.0
    if lookback_days > 0 and len(scan_df.index) > 0:
        try:
            cutoff = scan_df.index[-1] - timedelta(days=lookback_days)
            scan_df = scan_df[scan_df.index >= cutoff]
        except Exception:
            pass
    if len(scan_df) < 3:
        if visible_df is not None and len(visible_df) >= 3:
            scan_df = visible_df.tail(3)
            scan_source = "engine_tail_fallback"
        else:
            scan_df = scan_df.tail(3)
    cfg_tf = str(raw_cfg.get("timeframe") or "").strip().upper()
    merged_config = {
        **tool.get_default_config(),
        **req.config,
        "symbol": engine.symbol,
        # Respect explicitly requested scan timeframe (e.g. H4) instead of always forcing session/chart TF.
        "timeframe": cfg_tf or str(engine.timeframe or "M5"),
    }
    trend_meta: Dict[str, Any] = {}
    movement_strength: Dict[str, Any] = {}
    trend_fn = getattr(tool, "compute_trend_context", None)
    trend_df = visible_df if (visible_df is not None and len(visible_df) >= 3) else scan_df
    if callable(trend_fn):
        try:
            trend_meta = trend_fn(trend_df, merged_config) or {}
        except Exception:
            trend_meta = {}
    strength_fn = getattr(tool, "compute_movement_strength", None)
    if callable(strength_fn):
        try:
            movement_strength = strength_fn(scan_df, merged_config, trend_ctx=trend_meta) or {}
        except Exception:
            movement_strength = {}
    current_state: Dict[str, Any] = {}
    current_state_fn = getattr(tool, "compute_current_state", None)
    if callable(current_state_fn):
        try:
            current_state = current_state_fn(scan_df, merged_config) or {}
        except Exception:
            current_state = {}
    scan_config = dict(merged_config)
    if trend_meta:
        scan_config["_trend_context"] = trend_meta
    zones = tool.scan(scan_df, scan_config)
    zones_preview = _build_tool_zone_preview(zones)
    tool_state_patch = _build_tool_state_patch(
        tool_id=str(tool_id),
        zones_count=int(len(zones)),
        zones_preview=zones_preview,
        config=merged_config,
        trend=trend_meta,
        movement_strength=movement_strength,
        current_state=current_state,
        scan_source=scan_source,
    )
    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="TOOL_SIGNAL_CHANGED",
        payload={
            "tool_id": str(tool_id),
            "bar_index": int(engine.current_bar or max(0, len(scan_df) - 1)),
            "zones_count": int(len(zones)),
            "zones_preview": zones_preview,
            "scan_source": scan_source,
            "config": merged_config,
            "trend": trend_meta,
            "movement_strength": movement_strength,
            "current_state": current_state,
            "tool_state": tool_state_patch,
        },
        severity="info",
        db=db,
    )
    _store_external_snapshot(
        simulation_session=session,
        db=db,
        source="tool_scan",
        patch={
            "current_bar": int(engine.current_bar or 0),
            "tool_state": tool_state_patch,
        },
    )
    return {
        "tool_id": tool_id,
        "zones": zones,
        "count": len(zones),
        "scan_source": scan_source,
        "scan_timeframe": str(merged_config.get("timeframe") or ""),
        "trend": trend_meta,
        "movement_strength": movement_strength,
        "current_state": current_state,
    }


@router.post("/sessions/{session_id}/tools/research/optimize")
def workbench_research_optimize(
    session_id: int,
    req: ResearchOptimizeRequest,
    db: Session = Depends(get_db),
):
    """Run research-only parameter optimization on session bars."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Research optimizer currently supports Workbench sessions only")

    engine = _get_or_create_engine(session, db)
    has_client_bars = isinstance(req.bars, list) and len(req.bars) >= 20

    visible_df = engine.df.iloc[: engine.current_bar + 1] if (engine.df is not None and not engine.df.empty) else None
    scan_df = visible_df
    scan_source = "engine_visible"
    if has_client_bars:
        bars_df = _bars_payload_to_df(req.bars, max_rows=50000, min_rows=20)
        if bars_df is not None:
            scan_df = bars_df
            scan_source = "client_live"

    if scan_df is None or len(scan_df) < 20:
        raise HTTPException(400, "Insufficient bars for optimization (need at least 20)")

    raw_params = req.params if isinstance(req.params, dict) else {}
    try:
        lookback_bars = int(raw_params.get("lookback_bars") or 0)
    except Exception:
        lookback_bars = 0
    if lookback_bars > 0:
        scan_df = scan_df.tail(max(20, min(50000, lookback_bars)))
    try:
        lookback_days = float(raw_params.get("lookback_days") or 0.0)
    except Exception:
        lookback_days = 0.0
    if lookback_days > 0 and len(scan_df.index) > 0:
        try:
            cutoff = scan_df.index[-1] - timedelta(days=lookback_days)
            scan_df = scan_df[scan_df.index >= cutoff]
        except Exception:
            pass
    if len(scan_df) < 20:
        raise HTTPException(400, "Insufficient bars after lookback filter (need at least 20)")

    strategy_type = str(req.strategy_type or "sma_crossover").strip().lower()
    t0 = perf_counter()

    if strategy_type == "sma_crossover":
        fast_range = parse_int_range(
            raw_params,
            key="fast",
            start_default=10,
            stop_default=65,
            step_default=5,
            min_v=2,
            max_v=400,
        )
        slow_range = parse_int_range(
            raw_params,
            key="slow",
            start_default=40,
            stop_default=255,
            step_default=10,
            min_v=3,
            max_v=800,
        )
        combo_count = count_sma_crossover_combinations(fast_range=fast_range, slow_range=slow_range)
        if combo_count > int(req.max_combinations):
            raise HTTPException(
                400,
                f"Too many combinations (estimated {combo_count}). Reduce ranges or raise max_combinations.",
            )
        result = optimize_sma_crossover(
            scan_df,
            fast_range=fast_range,
            slow_range=slow_range,
            tc=float(req.tc_rate),
        )
        range_echo: Dict[str, Any] = {
            "fast_range": list(fast_range),
            "slow_range": list(slow_range),
        }
    elif strategy_type == "mean_reversion":
        sma_range = parse_int_range(
            raw_params,
            key="sma",
            start_default=15,
            stop_default=85,
            step_default=5,
            min_v=5,
            max_v=500,
        )
        dev_range = parse_float_range(
            raw_params,
            key="dev",
            start_default=1.2,
            stop_default=3.1,
            step_default=0.2,
            min_v=0.2,
            max_v=8.0,
        )
        combo_count = count_combinations([sma_range]) * count_float_combinations([dev_range])
        if combo_count > int(req.max_combinations):
            raise HTTPException(
                400,
                f"Too many combinations (estimated {combo_count}). Reduce ranges or raise max_combinations.",
            )
        result = optimize_mean_reversion(
            scan_df,
            sma_range=sma_range,
            dev_range=dev_range,
            tc=float(req.tc_rate),
        )
        range_echo = {
            "sma_range": list(sma_range),
            "dev_range": [float(dev_range[0]), float(dev_range[1]), float(dev_range[2])],
        }
    else:
        raise HTTPException(400, f"Unsupported strategy_type: {strategy_type}")

    elapsed_ms = int(max(0.0, (perf_counter() - t0) * 1000.0))
    top_n = int(max(1, req.top_n))
    rows = list(result.get("results") or [])
    result["results"] = rows[:top_n]
    result["elapsed_ms"] = elapsed_ms
    result["scan_source"] = scan_source
    result["top_n"] = top_n
    result["tc_rate"] = float(req.tc_rate)
    result["range"] = range_echo
    result["bars_used"] = int(len(scan_df))
    result["research_only"] = True
    return result


@router.post("/sessions/{session_id}/tools/research/ml-diagnostic")
def workbench_research_ml_diagnostic(
    session_id: int,
    req: ResearchMLDiagnosticRequest,
    db: Session = Depends(get_db),
):
    """Run research-only ML feature hygiene diagnostic on session bars."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "ML diagnostic currently supports Workbench sessions only")

    engine = _get_or_create_engine(session, db)
    has_client_bars = isinstance(req.bars, list) and len(req.bars) >= 20

    visible_df = engine.df.iloc[: engine.current_bar + 1] if (engine.df is not None and not engine.df.empty) else None
    scan_df = visible_df
    scan_source = "engine_visible"
    if has_client_bars:
        bars_df = _bars_payload_to_df(req.bars, max_rows=50000, min_rows=20)
        if bars_df is not None:
            scan_df = bars_df
            scan_source = "client_live"

    if scan_df is None or len(scan_df) < 20:
        raise HTTPException(400, "Insufficient bars for ML diagnostic (need at least 20)")

    raw_params = req.params if isinstance(req.params, dict) else {}
    try:
        lookback_bars = int(raw_params.get("lookback_bars") or 0)
    except Exception:
        lookback_bars = 0
    if lookback_bars > 0:
        scan_df = scan_df.tail(max(20, min(50000, lookback_bars)))
    try:
        lookback_days = float(raw_params.get("lookback_days") or 0.0)
    except Exception:
        lookback_days = 0.0
    if lookback_days > 0 and len(scan_df.index) > 0:
        try:
            cutoff = scan_df.index[-1] - timedelta(days=lookback_days)
            scan_df = scan_df[scan_df.index >= cutoff]
        except Exception:
            pass
    if len(scan_df) < 20:
        raise HTTPException(400, "Insufficient bars after lookback filter (need at least 20)")

    res = compute_feature_diagnostic(
        scan_df,
        lags=int(req.lags),
        split_ratio=float(req.split_ratio),
        drift_warn_pct=float(req.drift_warn_pct),
    )
    res["research_only"] = True
    res["scan_source"] = scan_source
    res["bars_used"] = int(len(scan_df))
    return res


def _workbench_start_copilot_impl(
    session_id: int,
    req: CopilotStartRequest,
    db: Session,
    auto_commit: bool = True,
) -> Dict[str, Any]:
    """Start or reconfigure always-on Workbench copilot loop."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Copilot loop currently supports Workbench sessions only")

    mode = normalize_copilot_mode(req.mode)
    config = normalize_copilot_config(req.config)
    persisted_config = _redact_sensitive_config(config)
    provider = str(req.provider or "deterministic").strip().lower()
    model_label = str(req.model_label or "").strip() or None
    runtime_settings = _normalize_runtime_settings(provider=provider, runtime=req.runtime)

    row = _get_active_copilot(simulation_session_id=session_id, db=db)
    if row is None:
        row = WorkbenchCopilotSessionModel(
            simulation_session_id=int(session_id),
            mode=mode,
            status="ACTIVE",
            provider=provider,
            model_label=model_label,
            config_json=persisted_config,
            last_snapshot_json={},
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(row)
        db.flush()
    else:
        row.mode = mode
        row.provider = provider
        row.model_label = model_label
        row.config_json = persisted_config
        row.status = "ACTIVE"
        row.updated_at = datetime.utcnow()
        row.stopped_at = None

    db.add(
        WorkbenchCopilotEventModel(
            copilot_session_id=int(row.id),
            event_type="COPILOT_STARTED",
            severity="info",
            payload_json={
                "mode": mode,
                "provider": provider,
                "config": persisted_config,
            },
            created_at=datetime.utcnow(),
        )
    )
    if auto_commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    if runtime_settings:
        set_copilot_runtime(int(row.id), runtime_settings)
    else:
        clear_copilot_runtime(int(row.id))
    return {"ok": True, "state": _copilot_state_payload(row, db=db)}


@router.post("/sessions/{session_id}/copilot/start")
def workbench_start_copilot(
    session_id: int,
    req: CopilotStartRequest,
    db: Session = Depends(get_db),
):
    return _workbench_start_copilot_impl(session_id=session_id, req=req, db=db, auto_commit=True)


def _workbench_stop_copilot_impl(
    session_id: int,
    db: Session,
    auto_commit: bool = True,
) -> Dict[str, Any]:
    """Stop active Workbench copilot loop."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    row = _get_active_copilot(simulation_session_id=session_id, db=db)
    if row is None:
        raise HTTPException(404, "No active copilot session")

    row.status = "STOPPED"
    row.updated_at = datetime.utcnow()
    row.stopped_at = datetime.utcnow()
    (
        db.query(WorkbenchCopilotJobModel)
        .filter(WorkbenchCopilotJobModel.copilot_session_id == int(row.id))
        .filter(WorkbenchCopilotJobModel.status.in_(["PENDING", "RUNNING"]))
        .update(
            {
                "status": "CANCELLED",
                "finished_at": datetime.utcnow(),
                "error": "Cancelled on copilot stop",
            },
            synchronize_session=False,
        )
    )
    db.add(
        WorkbenchCopilotEventModel(
            copilot_session_id=int(row.id),
            event_type="COPILOT_STOPPED",
            severity="info",
            payload_json={},
            created_at=datetime.utcnow(),
        )
    )
    if auto_commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    clear_copilot_runtime(int(row.id))
    return {"ok": True, "state": _copilot_state_payload(row, db=db)}


@router.post("/sessions/{session_id}/copilot/stop")
def workbench_stop_copilot(
    session_id: int,
    db: Session = Depends(get_db),
):
    return _workbench_stop_copilot_impl(session_id=session_id, db=db, auto_commit=True)


def _workbench_pause_auto_paper_impl(
    session_id: int,
    db: Session,
    auto_commit: bool = True,
) -> Dict[str, Any]:
    """Pause AUTO_PAPER entries/exits via manual guardrail flag."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    row = _get_active_copilot(simulation_session_id=session_id, db=db)
    if row is None:
        raise HTTPException(404, "No active copilot session")

    cfg = row.config_json if isinstance(row.config_json, dict) else {}
    cfg["auto_paper_manual_pause"] = True
    row.config_json = _redact_sensitive_config(cfg)
    row.updated_at = datetime.utcnow()
    _emit_copilot_event(
        copilot=row,
        event_type="COPILOT_GUARDRAIL_BLOCK",
        severity="warning",
        payload={
            "manual_pause": True,
            "blocked": True,
            "blocked_reason": "manual_pause",
            "_priority": _event_priority_for_type("COPILOT_GUARDRAIL_BLOCK"),
        },
        db=db,
    )
    if auto_commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    return {"ok": True, "state": _copilot_state_payload(row, db=db)}


@router.post("/sessions/{session_id}/copilot/pause-auto")
def workbench_pause_auto_paper(
    session_id: int,
    db: Session = Depends(get_db),
):
    return _workbench_pause_auto_paper_impl(session_id=session_id, db=db, auto_commit=True)


def _workbench_resume_auto_paper_impl(
    session_id: int,
    db: Session,
    auto_commit: bool = True,
) -> Dict[str, Any]:
    """Resume AUTO_PAPER by clearing manual guardrail pause."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    row = _get_active_copilot(simulation_session_id=session_id, db=db)
    if row is None:
        raise HTTPException(404, "No active copilot session")

    cfg = row.config_json if isinstance(row.config_json, dict) else {}
    cfg["auto_paper_manual_pause"] = False
    row.config_json = _redact_sensitive_config(cfg)
    row.updated_at = datetime.utcnow()
    _emit_copilot_event(
        copilot=row,
        event_type="COPILOT_GUARDRAIL_RESUME",
        severity="info",
        payload={
            "manual_pause": False,
            "blocked": False,
            "blocked_reason": None,
            "_priority": _event_priority_for_type("COPILOT_GUARDRAIL_RESUME"),
        },
        db=db,
    )
    if auto_commit:
        db.commit()
        db.refresh(row)
    else:
        db.flush()
    return {"ok": True, "state": _copilot_state_payload(row, db=db)}


@router.post("/sessions/{session_id}/copilot/resume-auto")
def workbench_resume_auto_paper(
    session_id: int,
    db: Session = Depends(get_db),
):
    return _workbench_resume_auto_paper_impl(session_id=session_id, db=db, auto_commit=True)


@router.get("/sessions/{session_id}/copilot/state")
def workbench_get_copilot_state(
    session_id: int,
    db: Session = Depends(get_db),
):
    """Get current copilot status and recent outputs."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    row = _get_active_copilot(simulation_session_id=session_id, db=db)
    if row is None:
        row = (
            db.query(WorkbenchCopilotSessionModel)
            .filter(WorkbenchCopilotSessionModel.simulation_session_id == int(session_id))
            .order_by(WorkbenchCopilotSessionModel.created_at.desc())
            .first()
        )
        if row is None:
            return {"active": False, "status": "NOT_STARTED"}
    return _copilot_state_payload(row, db=db)


def _workbench_log_copilot_action_impl(
    session_id: int,
    req: CopilotActionRequest,
    db: Session,
    auto_commit: bool = True,
) -> Dict[str, Any]:
    """Log user/collaboration action for copilot audit trail."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")

    row = _get_active_copilot(simulation_session_id=session_id, db=db)
    if row is None:
        row = (
            db.query(WorkbenchCopilotSessionModel)
            .filter(WorkbenchCopilotSessionModel.simulation_session_id == int(session_id))
            .order_by(WorkbenchCopilotSessionModel.created_at.desc())
            .first()
        )
    if row is None:
        raise HTTPException(400, "Copilot session not started")

    action_type = str(req.action_type or "").strip().upper()
    if not action_type:
        raise HTTPException(400, "action_type is required")
    execute_aliases = {
        "EXECUTE",
        "EXECUTED",
        "SUGGEST_ENTRY",
        "SUGGEST_EXIT",
        "SUGGEST_RISK_ADJUSTMENT",
        "AUTO_PAPER_ENTRY",
        "AUTO_PAPER_EXIT",
    }
    action_status = "EXECUTED"
    if action_type in {"REJECT", "REJECTED"}:
        action_status = "REJECTED"
    elif action_type in {"ACCEPT", "ACCEPTED", "ACK", "ACKNOWLEDGE", "ACKNOWLEDGED"}:
        action_status = "APPROVED"
    elif action_type not in execute_aliases:
        action_status = "EXECUTED"

    action_row = WorkbenchCopilotActionModel(
        copilot_session_id=int(row.id),
        advice_id=int(req.advice_id) if req.advice_id is not None else None,
        action_type=action_type,
        payload_json=req.payload if isinstance(req.payload, dict) else {},
        note=str(req.note or "").strip() or None,
        requested_by="USER",
        status=action_status,
        created_at=datetime.utcnow(),
    )
    db.add(action_row)

    if req.advice_id is not None:
        advice = (
            db.query(WorkbenchCopilotAdviceModel)
            .filter(WorkbenchCopilotAdviceModel.id == int(req.advice_id))
            .filter(WorkbenchCopilotAdviceModel.copilot_session_id == int(row.id))
            .first()
        )
        if advice:
            if action_type in {"REJECT", "REJECTED"}:
                advice.status = "REJECTED"
            elif action_type in execute_aliases:
                advice.status = "EXECUTED"
            elif action_type in {"ACCEPT", "ACCEPTED", "ACK", "ACKNOWLEDGE", "ACKNOWLEDGED"}:
                advice.status = "ACKNOWLEDGED"
            else:
                advice.status = "ACKNOWLEDGED"

    _emit_copilot_event(
        copilot=row,
        event_type="MANUAL_OVERRIDE",
        severity="info",
        payload={
            "override_type": "COPILOT_ACTION",
            "action_type": action_type,
            "advice_id": int(req.advice_id) if req.advice_id is not None else None,
            "note": str(req.note or "").strip() or None,
        },
        db=db,
    )

    if auto_commit:
        db.commit()
        db.refresh(action_row)
    else:
        db.flush()
    return {
        "ok": True,
        "action_id": int(action_row.id),
        "copilot_session_id": int(row.id),
    }


@router.post("/sessions/{session_id}/copilot/action")
def workbench_log_copilot_action(
    session_id: int,
    req: CopilotActionRequest,
    db: Session = Depends(get_db),
):
    return _workbench_log_copilot_action_impl(session_id=session_id, req=req, db=db, auto_commit=True)


def _workbench_copilot_tool_state_impl(
    session_id: int,
    req: CopilotToolStateRequest,
    db: Session,
    auto_commit: bool = True,
) -> Dict[str, Any]:
    """Push full tool usage payload into copilot stream (future-tool compatible)."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    row = _get_active_copilot(simulation_session_id=session_id, db=db)
    if row is None:
        return {"ok": False, "active": False, "message": "Copilot not active"}

    payload = req.tool_state if isinstance(req.tool_state, dict) else {}
    event_type = str(req.event_type or "TOOL_SIGNAL_CHANGED").strip().upper()
    severity = str(req.severity or "info").strip().lower()

    # Live tick path: update copilot snapshot/advice loop from live bars without
    # relying on replay-engine bar advancement.
    if event_type == "LIVE_TICK":
        advance_result = _build_live_advance_result(
            session=session,
            tool_state_payload=payload,
            db=db,
        )
        if advance_result is None:
            return {"ok": False, "active": True, "message": "LIVE_TICK ignored: missing/invalid live_bar"}
        try:
            _record_copilot_iteration(
                session=session,
                advance_result=advance_result,
                db=db,
            )
        except Exception as exc:
            logger.warning("LIVE_TICK copilot iteration failed: %s", exc)
            return {"ok": False, "active": True, "message": f"LIVE_TICK processing failed: {type(exc).__name__}"}
        return {"ok": True, "active": True, "mode": "live_tick_processed"}

    _emit_copilot_event(
        copilot=row,
        event_type=event_type,
        severity=severity,
        payload=payload,
        db=db,
    )
    _store_external_snapshot(
        simulation_session=session,
        db=db,
        source="tool_scan",
        patch={
            "tool_state": payload,
            "current_bar": int(session.current_bar or 0),
        },
        auto_commit=auto_commit,
    )
    if not auto_commit:
        db.flush()
    return {"ok": True, "active": True}


@router.post("/sessions/{session_id}/copilot/tool-state")
def workbench_copilot_tool_state(
    session_id: int,
    req: CopilotToolStateRequest,
    db: Session = Depends(get_db),
):
    return _workbench_copilot_tool_state_impl(session_id=session_id, req=req, db=db, auto_commit=True)


def workbench_agent_tool_state(
    session_id: int,
    req: CopilotToolStateRequest,
    db: Session = Depends(get_db),
):
    """Agent alias for tool state/tick pushes (backed by copilot runtime)."""
    payload = req.tool_state if isinstance(req.tool_state, dict) else {}
    try:
        raw = json.dumps(payload, ensure_ascii=True, sort_keys=True)
    except Exception:
        raise HTTPException(400, "tool_state must be JSON serializable")
    if len(raw.encode("utf-8")) > int(_AGENT_TOOL_STATE_MAX_BYTES_INBOUND):
        raise HTTPException(413, f"tool_state payload too large (>{int(_AGENT_TOOL_STATE_MAX_BYTES_INBOUND)} bytes)")

    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    out = _workbench_copilot_tool_state_impl(session_id=session_id, req=req, db=db, auto_commit=False)
    copilot = _get_active_copilot(simulation_session_id=int(session_id), db=db)
    agent = _ensure_agent_session(
        simulation_session_id=int(session_id),
        db=db,
        mode="LOOP",
        provider=str(copilot.provider or "deterministic") if copilot is not None else "deterministic",
        model_label=str(copilot.model_label or "") if copilot is not None else None,
        permissions=(copilot.config_json or {}).get("agent_permissions", {}) if (copilot is not None and isinstance(copilot.config_json, dict)) else {},
        config=copilot.config_json if (copilot is not None and isinstance(copilot.config_json, dict)) else {},
        runtime=_runtime_summary(get_copilot_runtime(int(copilot.id))) if copilot is not None else {},
        copilot_session_id=int(copilot.id) if copilot is not None else None,
    )
    _agent_emit_event(
        agent=agent,
        event_type=str(req.event_type or "TOOL_SIGNAL_CHANGED"),
        payload={
            "severity": str(req.severity or "info"),
            "tool_state_keys": sorted(list((req.tool_state or {}).keys())) if isinstance(req.tool_state, dict) else [],
        },
        severity=str(req.severity or "info"),
        db=db,
    )
    _agent_store_snapshot(
        agent=agent,
        simulation_session=session,
        db=db,
        source="tool_state",
        patch={"tool_state": req.tool_state if isinstance(req.tool_state, dict) else {}},
    )
    db.commit()
    if isinstance(out, dict):
        msg = str(out.get("message") or "")
        if msg:
            out = dict(out)
            out["message"] = msg.replace("Copilot", "Agent").replace("copilot", "agent")
        out["agent_session_id"] = int(agent.id)
    return out


@router.get("/sessions/{session_id}/agent/admin")
def workbench_agent_admin_status(
    session_id: int,
    clear_news_cache: bool = Query(False),
    db: Session = Depends(get_db),
):
    """Tiny admin endpoint for agent guardrail config and news-cache diagnostics."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if clear_news_cache:
        global _AGENT_NEWS_CACHE_HITS, _AGENT_NEWS_CACHE_MISSES, _AGENT_NEWS_FETCH_COUNT, _AGENT_NEWS_FETCH_ERROR_COUNT
        with _AGENT_NEWS_CACHE_LOCK:
            _AGENT_NEWS_CACHE.clear()
            _AGENT_NEWS_CACHE_HITS = 0
            _AGENT_NEWS_CACHE_MISSES = 0
        with _AGENT_NEWS_COUNTERS_LOCK:
            _AGENT_NEWS_FETCH_COUNT = 0
            _AGENT_NEWS_FETCH_ERROR_COUNT = 0
        with _AGENT_NEWS_SUMMARY_CACHE_LOCK:
            _AGENT_NEWS_SUMMARY_CACHE.clear()
    cfg = _agent_effective_tool_config(session=session, db=db)
    return {
        "ok": True,
        "session_id": int(session_id),
        "guardrails": {
            "enabled": bool(cfg.get("guardrail_enabled", True)),
            "session_filter_enabled": bool(cfg.get("guardrail_session_filter_enabled", False)),
            "news_filter_enabled": bool(cfg.get("guardrail_news_filter_enabled", False)),
            "news_lookback_min": max(15, min(24 * 60, int(cfg.get("guardrail_news_lookback_min") or 120))),
            "market_news_provider": str(cfg.get("market_news_provider") or "polygon").strip().lower() or "polygon",
            "market_news_llm_summary_enabled": bool(cfg.get("market_news_llm_summary_enabled", False)),
            "market_news_summary_model": str(cfg.get("market_news_summary_model") or "claude-haiku-4-5-20251001"),
            "market_news_ibkr_host": str(cfg.get("market_news_ibkr_host") or "127.0.0.1"),
            "market_news_ibkr_port": int(_agent_usage_safe_int(cfg.get("market_news_ibkr_port"), 7497)),
            "anthropic_api_key_configured": bool(str(os.getenv("ANTHROPIC_API_KEY") or "").strip()),
            "trigger_requires_approval": bool(cfg.get("watchdog_trigger_requires_approval", False)),
        },
        "tool_access": {
            "tool_selection_mode": _normalize_tool_selection_mode(
                cfg.get("tool_selection_mode")
            ),
            "strategy_tool_access_mode": _normalize_strategy_tool_access_mode(
                cfg.get("strategy_tool_access_mode")
            )
        },
        "news_cache": _agent_news_cache_stats(),
    }


@router.post("/sessions/{session_id}/agent/tool-state")
async def workbench_agent_tool_state_http(
    session_id: int,
    request: Request,
    db: Session = Depends(get_db),
):
    """HTTP route with streaming size guard before JSON parsing."""
    max_bytes = int(_AGENT_TOOL_STATE_MAX_BYTES_INBOUND)
    size = 0
    chunks: List[bytes] = []
    async for chunk in request.stream():
        if not isinstance(chunk, (bytes, bytearray)):
            continue
        size += len(chunk)
        if size > max_bytes:
            raise HTTPException(413, f"tool_state payload too large (>{max_bytes} bytes)")
        chunks.append(bytes(chunk))
    raw_body = b"".join(chunks)
    try:
        parsed = json.loads(raw_body.decode("utf-8") if isinstance(raw_body, (bytes, bytearray)) else "{}")
    except Exception:
        raise HTTPException(400, "Invalid JSON payload")
    try:
        req = CopilotToolStateRequest.model_validate(parsed if isinstance(parsed, dict) else {})
    except ValidationError as exc:
        raise HTTPException(422, f"Invalid tool-state payload: {str(exc)[:300]}")
    return workbench_agent_tool_state(session_id=session_id, req=req, db=db)


@router.post("/sessions/{session_id}/coach/evaluate")
def workbench_evaluate_session(
    session_id: int,
    req: CoachEvaluateRequest,
    db: Session = Depends(get_db),
):
    """Evaluate a workbench session and return a coaching report."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Coach evaluation is currently available only for Workbench sessions")

    trades = (
        db.query(SimulationTrade)
        .filter(SimulationTrade.session_id == session_id)
        .order_by(SimulationTrade.id.asc())
        .all()
    )
    trade_rows: List[Dict[str, Any]] = []
    for t in trades:
        trade_rows.append(
            {
                "id": int(t.id),
                "direction": str(t.direction or ""),
                "entry_price": float(t.entry_price) if t.entry_price is not None else None,
                "stop_loss": float(t.stop_loss) if t.stop_loss is not None else None,
                "take_profit": float(t.take_profit) if t.take_profit is not None else None,
                "lot_size": float(t.lot_size) if t.lot_size is not None else None,
                "exit_price": float(t.exit_price) if t.exit_price is not None else None,
                "pnl": float(t.pnl) if t.pnl is not None else None,
                "r_multiple": float(t.r_multiple) if t.r_multiple is not None else None,
                "status": str(t.status or ""),
                "exit_reason": str(t.exit_reason or "") if t.exit_reason is not None else None,
            }
        )

    session_payload = {
        "id": int(session.id),
        "strategy_id": str(session.strategy_id or ""),
        "symbol": str(session.symbol or ""),
        "timeframe": str(session.timeframe or ""),
        "current_bar": int(session.current_bar or 0),
        "total_bars": int(session.total_bars or 0),
        "initial_balance": float(session.initial_balance or 0.0),
        "current_balance": float(session.current_balance or 0.0),
        "total_pnl": float(session.total_pnl or 0.0),
    }
    context = build_workbench_context(
        session=session_payload,
        trades=trade_rows,
        tool_state=req.tool_state or {},
        notes=req.notes,
    )

    coach = WorkbenchCoach()
    run_id = uuid.uuid4().hex[:16]
    provider = str(req.provider or "deterministic").strip().lower()
    model_label = str(req.model_label or "").strip() or None
    try:
        report = coach.evaluate(
            context=context,
            provider=provider,
            model_label=model_label,
            llm_url=req.llm_url,
            api_key=req.api_key,
            timeout_sec=req.timeout_sec,
        )
        row = AIBotRunModel(
            run_id=run_id,
            status="COMPLETED",
            strategy_id="workbench",
            context_id=str(session_id),
            provider=provider,
            model_label=report.get("model") if isinstance(report, dict) else model_label,
            request_json={
                "provider": provider,
                "model_label": model_label,
                "timeout_sec": req.timeout_sec,
                "notes": req.notes,
                "tool_state": req.tool_state or {},
            },
            report_json=report if isinstance(report, dict) else {},
            execution_plan_json=[],
            notes_json=[],
            error=None,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return {"ok": True, "run_id": run_id, "status": "COMPLETED", "report": report}
    except Exception as exc:
        row = AIBotRunModel(
            run_id=run_id,
            status="FAILED",
            strategy_id="workbench",
            context_id=str(session_id),
            provider=provider,
            model_label=model_label,
            request_json={
                "provider": provider,
                "model_label": model_label,
                "timeout_sec": req.timeout_sec,
                "notes": req.notes,
                "tool_state": req.tool_state or {},
            },
            report_json={},
            execution_plan_json=[],
            notes_json=[],
            error=f"{type(exc).__name__}: {str(exc)}",
        )
        db.add(row)
        db.commit()
        raise HTTPException(500, f"Coach evaluation failed: {type(exc).__name__}: {str(exc)}")


@router.post("/sessions/{session_id}/consultant/chat")
def workbench_consultant_chat(
    session_id: int,
    req: ConsultantChatRequest,
    db: Session = Depends(get_db),
):
    """Chat endpoint for Workbench AI consultant companion."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Consultant chat is available only for Workbench sessions")

    consultant = WorkbenchConsultant()
    out = consultant.chat(
        message=req.message,
        context=req.context_snapshot or {},
        conversation_history=req.conversation_history or [],
        provider=req.provider,
        model_label=req.model_label,
        llm_url=req.llm_url,
        api_key=req.api_key,
        timeout_sec=req.timeout_sec,
    )
    return out


@router.post("/sessions/{session_id}/agent/chat")
def workbench_agent_chat(
    session_id: int,
    req: AgentChatRequest,
    db: Session = Depends(get_db),
):
    """Unified Agent chat entrypoint with tool-calling support."""
    agent_session_id: Optional[int] = None
    merged_ctx: Dict[str, Any] = {}
    perms: Dict[str, Any] = {}
    provider_cfg: Dict[str, Any] = {}
    effective_tool_cfg: Dict[str, Any] = {}
    try:
        session = db.query(SimulationSession).get(session_id)
        if not session:
            raise HTTPException(404, "Session not found")
        if str(session.strategy_id or "") != WORKBENCH_ID:
            raise HTTPException(400, "Agent chat is available only for Workbench sessions")

        base_ctx = _agent_default_context(session=session, db=db)
        user_ctx = _model_to_dict(req.context_snapshot)
        merged_ctx = _agent_merge_context(base_ctx, user_ctx)
        # Identity profile is locked by session config; never overridden by client context.
        merged_ctx["identity"] = _agent_identity_from_session_config(session)
        try:
            memory_hits = _agent_memory_search(
                simulation_session=session,
                db=db,
                query_text=str(req.message or ""),
                limit=8,
                memory_type=None,
            )
        except Exception:
            memory_hits = []
        if memory_hits:
            mem_obj = merged_ctx.get("memory") if isinstance(merged_ctx.get("memory"), dict) else {}
            mem_obj = {
                **mem_obj,
                "query": str(req.message or ""),
                "hits": memory_hits,
            }
            merged_ctx["memory"] = mem_obj
        perms = _model_to_dict(req.permissions)
        provider_cfg = _model_to_dict(req.provider)
        if not bool(perms.get("can_chat", True)):
            raise HTTPException(403, "permission_denied:can_chat")

        copilot = _get_active_copilot(simulation_session_id=int(session.id), db=db)
        merged_cfg = {
            **(copilot.config_json if (copilot is not None and isinstance(copilot.config_json, dict)) else {}),
            **(req.config if isinstance(req.config, dict) else {}),
        }
        effective_tool_cfg = _agent_effective_tool_config(
            session=session,
            db=db,
            override=merged_cfg,
        )
        agent_row = _ensure_agent_session(
            simulation_session_id=int(session.id),
            db=db,
            mode="CHAT",
            provider=str(provider_cfg.get("provider") or "deterministic"),
            model_label=str(provider_cfg.get("model_label") or "").strip() or None,
            permissions=perms,
            config=merged_cfg,
            runtime={
                "llm_url": provider_cfg.get("llm_url"),
                "timeout_sec": int(provider_cfg.get("timeout_sec") or 45),
            },
            copilot_session_id=int(copilot.id) if copilot is not None else None,
        )
        agent_session_id = int(agent_row.id)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        try:
            db.close()
        except Exception:
            pass

    allowed_tool_names: Optional[List[str]] = []
    if bool(req.allow_tools):
        allowed_tool_names = _agent_select_allowed_tool_names(
            message=str(req.message or ""),
            conversation_history=req.conversation_history or [],
            cfg=effective_tool_cfg,
        )

    def _executor(name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        tool_db = SessionLocal()
        try:
            tool_session = tool_db.query(SimulationSession).get(session_id)
            if tool_session is None:
                return {"ok": False, "error": "session_not_found"}
            logger.info(
                "agent_chat_tool_dispatch session=%s tool=%s args_keys=%s",
                int(session_id),
                str(name or ""),
                list((args or {}).keys())[:10],
            )
            out = _agent_execute_tool(
                session=tool_session,
                db=tool_db,
                permissions=perms,
                context_snapshot=merged_ctx,
                tool_name=name,
                args=args,
                tool_config=effective_tool_cfg,
                atomic=False,
            )
            if isinstance(out, dict) and bool(out.get("ok", False)):
                tsp = _agent_tool_state_from_tool_calls(
                    [{"tool_id": str(name or ""), "args": (args if isinstance(args, dict) else {}), "result": out}]
                )
                if isinstance(tsp, dict) and tsp:
                    cur_ts = merged_ctx.get("tool_state") if isinstance(merged_ctx.get("tool_state"), dict) else {}
                    merged_ctx["tool_state"] = {**cur_ts, **tsp}
                # set_market_context only returns sanitized intent (frontend_apply_required);
                # clear stale bars so subsequent tool calls in this same chat turn re-fetch
                # timeframe-correct history instead of reusing old chart bars.
                if str(name or "").strip().lower() == "set_market_context":
                    merged_ctx["bars"] = []
                # If snapshot returned bars, keep them available for follow-up tools in this turn.
                data_obj = out.get("data") if isinstance(out.get("data"), dict) else {}
                if isinstance(data_obj.get("bars"), list) and len(data_obj.get("bars")) >= 20:
                    merged_ctx["bars"] = data_obj.get("bars")
            logger.info(
                "agent_chat_tool_result session=%s tool=%s ok=%s error=%s",
                int(session_id),
                str(name or ""),
                bool(out.get("ok")) if isinstance(out, dict) else False,
                out.get("error") if isinstance(out, dict) else None,
            )
            tool_db.commit()
            return out
        except Exception as exc:
            tool_db.rollback()
            logger.warning(
                "agent_chat_tool_exception session=%s tool=%s err=%s",
                int(session_id),
                str(name or ""),
                f"{type(exc).__name__}: {str(exc)[:180]}",
            )
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
        finally:
            tool_db.close()

    provider_name = str(provider_cfg.get("provider") or "deterministic")
    delta_mgr = get_delta_manager(str(session_id))
    market_summary = merged_ctx.get("market_summary") if isinstance(merged_ctx.get("market_summary"), dict) else {}
    stats_obj = merged_ctx.get("session_stats") if isinstance(merged_ctx.get("session_stats"), dict) else {}
    bars_obj = merged_ctx.get("bars") if isinstance(merged_ctx.get("bars"), list) else []
    last_price_from_bars = None
    if bars_obj:
        last_bar = bars_obj[-1] if isinstance(bars_obj[-1], dict) else {}
        if isinstance(last_bar, dict):
            try:
                last_price_from_bars = float(last_bar.get("close")) if last_bar.get("close") is not None else None
            except Exception:
                last_price_from_bars = None
    delta_input = {
        "last_price": market_summary.get("current_price", last_price_from_bars),
        "atr_14": market_summary.get("atr14", market_summary.get("range20", 1.0)),
        "balance": stats_obj.get("current_balance"),
        "positions": merged_ctx.get("open_positions", []),
        "triggers": merged_ctx.get("scheduled_triggers", []),
    }
    merged_ctx["_delta_context"] = delta_mgr.compute_delta(delta_input)
    cb = get_circuit_breaker()
    provider_for_call = provider_name
    fallback_provider = cb.get_fallback(provider_name)
    if fallback_provider:
        provider_for_call = str(fallback_provider)
        logger.warning(
            "agent_chat_circuit_breaker_fallback session=%s from=%s to=%s",
            int(session_id),
            provider_name,
            provider_for_call,
        )
    model_label_for_call = provider_cfg.get("model_label")
    llm_url_for_call = provider_cfg.get("llm_url")
    api_key_for_call = provider_cfg.get("api_key")
    if provider_for_call != provider_name:
        # Use provider defaults for fallback provider to avoid invalid URL/key mismatches.
        model_label_for_call = None
        llm_url_for_call = None
        api_key_for_call = None
    max_steps_eff = _agent_effective_max_tool_steps(provider_for_call, req.max_tool_steps)
    agent = WorkbenchAgent()
    out = agent.chat(
        message=req.message,
        context=merged_ctx,
        conversation_history=req.conversation_history,
        provider=provider_for_call,
        model_label=model_label_for_call,
        llm_url=llm_url_for_call,
        api_key=api_key_for_call,
        timeout_sec=provider_cfg.get("timeout_sec"),
        permissions=perms,
        tool_executor=_executor,
        allow_tools=bool(req.allow_tools),
        max_tool_steps=max_steps_eff,
        allowed_tool_names=allowed_tool_names,
        objective="chat",
    )
    if provider_for_call == provider_name:
        if bool(out.get("ok", False)):
            cb.record_success(provider_name)
        else:
            err_text = str(out.get("error") or "")
            if any(tok in err_text for tok in ("429", "500", "502", "503", "504", "529", "Timeout", "ReadTimeout", "ConnectTimeout")):
                cb.record_failure(provider_name)

    persist_db = SessionLocal()
    lock = _get_agent_session_lock(int(session_id))
    try:
        with lock:
            session_p = persist_db.query(SimulationSession).get(session_id)
            if session_p is None:
                raise HTTPException(404, "Session not found")
            agent_row_p = (
                persist_db.query(WorkbenchAgentSessionModel).get(int(agent_session_id))
                if agent_session_id is not None
                else None
            )
            if agent_row_p is None:
                agent_row_p = _ensure_agent_session(
                    simulation_session_id=int(session_id),
                    db=persist_db,
                    mode="CHAT",
                    provider=str(provider_cfg.get("provider") or "deterministic"),
                    model_label=str(provider_cfg.get("model_label") or "").strip() or None,
                    permissions=perms,
                    config=(req.config if isinstance(req.config, dict) else {}),
                    runtime={
                        "llm_url": provider_cfg.get("llm_url"),
                        "timeout_sec": int(provider_cfg.get("timeout_sec") or 45),
                    },
                    copilot_session_id=None,
                )
                agent_session_id = int(agent_row_p.id)
            out = _agent_enforce_execution_truth(
                out=out if isinstance(out, dict) else {},
                user_message=str(req.message or ""),
                session=session_p,
                agent_row=agent_row_p,
                db=persist_db,
                permissions=perms,
                context_snapshot=merged_ctx,
            )
            saved_memory_notes = _persist_agent_memory_notes(
                simulation_session=session_p,
                db=persist_db,
                memory_notes=out.get("memory_notes"),
                source="agent_model",
            )
            usage_payload = _normalize_agent_usage_payload(out.get("usage"))
            prev_snap = agent_row_p.last_snapshot_json if isinstance(agent_row_p.last_snapshot_json, dict) else {}
            usage_meter = _agent_rollup_usage_meter(prev_snap, usage_payload)
            teach = _extract_teaching_memory_candidate(str(req.message or ""))
            if teach is not None:
                _agent_memory_add(
                    simulation_session=session_p,
                    db=persist_db,
                    content=str(teach.get("content") or ""),
                    memory_type=str(teach.get("memory_type") or "trader_rule"),
                    scope=str(teach.get("scope") or "GLOBAL"),
                    importance=float(teach.get("importance") or 0.8),
                    source=str(teach.get("source") or "user_teach"),
                    metadata={
                        "from": "agent_chat",
                        "session_id": int(session_id),
                    },
                )
                saved_memory_notes += 1
            _agent_emit_event(
                agent=agent_row_p,
                event_type="AGENT_CHAT",
                payload={
                    "ok": bool(out.get("ok", False)),
                    "tool_calls": int(len(out.get("tool_calls") or [])),
                    "tool_ids": _agent_tool_ids_from_calls(out.get("tool_calls")),
                    "proposed_actions": int(len(out.get("proposed_actions") or [])),
                    "memory_saved": int(saved_memory_notes),
                    "provider": str(provider_cfg.get("provider") or "deterministic"),
                    "usage": usage_payload,
                    "integrity_warning": str(out.get("integrity_warning") or "") or None,
                },
                severity="info" if bool(out.get("ok", False)) else "warning",
                db=persist_db,
            )
            _agent_store_snapshot(
                agent=agent_row_p,
                simulation_session=session_p,
                db=persist_db,
                source="chat",
                patch={
                    "tool_state": {
                        **(
                            merged_ctx.get("tool_state")
                            if isinstance(merged_ctx.get("tool_state"), dict)
                            else {}
                        ),
                        **_agent_tool_state_from_tool_calls(out.get("tool_calls")),
                    },
                    "agent_last_message": str(out.get("reply") or out.get("error") or "")[:2000],
                    "memory_saved": int(saved_memory_notes),
                    "usage_meter": usage_meter,
                    "last_usage": usage_payload,
                },
            )
            _record_external_copilot_event(
                simulation_session_id=int(session_id),
                event_type="MANUAL_OVERRIDE",
                payload={
                    "override_type": "AGENT_CHAT",
                    "provider": str(provider_cfg.get("provider") or "deterministic"),
                    "ok": bool(out.get("ok", False)),
                    "tool_calls": int(len(out.get("tool_calls") or [])),
                    "usage": usage_payload,
                },
                severity="info" if bool(out.get("ok", False)) else "warning",
                db=persist_db,
                auto_commit=False,
            )
            persist_db.commit()
    except Exception:
        persist_db.rollback()
        raise
    finally:
        persist_db.close()

    final_message = str(out.get("reply") or out.get("error") or "").strip()
    if not final_message:
        tc = out.get("tool_calls") if isinstance(out.get("tool_calls"), list) else []
        if tc:
            final_message = "Tool execution completed, but no final assistant text was generated. Ask me to summarize the latest tool results."
        elif bool(out.get("ok", False)):
            final_message = "No assistant text was generated for this turn."

    return AgentResponse(
        ok=bool(out.get("ok", False)),
        session_id=int(session_id),
        provider=str(out.get("provider") or provider_cfg.get("provider") or "deterministic"),
        model_label=str(out.get("model") or provider_cfg.get("model_label") or "") or None,
        message=final_message,
        tool_calls=out.get("tool_calls") if isinstance(out.get("tool_calls"), list) else [],
        proposed_actions=_normalize_agent_proposed_actions(out.get("proposed_actions")),
        usage=_normalize_agent_usage_payload(out.get("usage")),
        audit={
            "agent_session_id": int(agent_session_id or 0),
            "generated_at": out.get("generated_at"),
            "raw_text": out.get("raw_text"),
            "memory_notes": out.get("memory_notes") if isinstance(out.get("memory_notes"), list) else [],
            "usage": _normalize_agent_usage_payload(out.get("usage")),
            "error": out.get("error"),
        },
    )


@router.post("/sessions/{session_id}/agent/run-once")
def workbench_agent_run_once(
    session_id: int,
    req: AgentRunOnceRequest,
    db: Session = Depends(get_db),
):
    """Run one agent reasoning cycle against current context."""
    agent_session_id: Optional[int] = None
    merged_ctx: Dict[str, Any] = {}
    perms: Dict[str, Any] = {}
    provider_cfg: Dict[str, Any] = {}
    effective_tool_cfg: Dict[str, Any] = {}
    try:
        session = db.query(SimulationSession).get(session_id)
        if not session:
            raise HTTPException(404, "Session not found")
        if str(session.strategy_id or "") != WORKBENCH_ID:
            raise HTTPException(400, "Agent run-once is available only for Workbench sessions")

        base_ctx = _agent_default_context(session=session, db=db)
        user_ctx = _model_to_dict(req.context_snapshot)
        merged_ctx = _agent_merge_context(base_ctx, user_ctx)
        # Identity profile is locked by session config; never overridden by client context.
        merged_ctx["identity"] = _agent_identity_from_session_config(session)
        query_for_memory = str(req.objective or "").strip()
        if not query_for_memory:
            query_for_memory = "latest session context risk review"
        try:
            memory_hits = _agent_memory_search(
                simulation_session=session,
                db=db,
                query_text=query_for_memory,
                limit=6,
                memory_type=None,
            )
        except Exception:
            memory_hits = []
        if memory_hits:
            mem_obj = merged_ctx.get("memory") if isinstance(merged_ctx.get("memory"), dict) else {}
            mem_obj = {
                **mem_obj,
                "query": query_for_memory,
                "hits": memory_hits,
            }
            merged_ctx["memory"] = mem_obj
        perms = _model_to_dict(req.permissions)
        provider_cfg = _model_to_dict(req.provider)
        copilot = _get_active_copilot(simulation_session_id=int(session.id), db=db)
        merged_cfg = {
            **(copilot.config_json if (copilot is not None and isinstance(copilot.config_json, dict)) else {}),
            **(req.config if isinstance(req.config, dict) else {}),
        }
        effective_tool_cfg = _agent_effective_tool_config(
            session=session,
            db=db,
            override=merged_cfg,
        )
        agent_row = _ensure_agent_session(
            simulation_session_id=int(session.id),
            db=db,
            mode="RUN_ONCE",
            provider=str(provider_cfg.get("provider") or "deterministic"),
            model_label=str(provider_cfg.get("model_label") or "").strip() or None,
            permissions=perms,
            config=merged_cfg,
            runtime={
                "llm_url": provider_cfg.get("llm_url"),
                "timeout_sec": int(provider_cfg.get("timeout_sec") or 45),
            },
            copilot_session_id=int(copilot.id) if copilot is not None else None,
        )
        agent_session_id = int(agent_row.id)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        try:
            db.close()
        except Exception:
            pass

    allowed_tool_names: Optional[List[str]] = []
    if bool(req.allow_tools):
        objective_for_intent = str(req.objective or "").strip() or "review setup and propose next actions"
        allowed_tool_names = _agent_select_allowed_tool_names(
            message="",
            conversation_history=[],
            cfg=effective_tool_cfg,
            objective=objective_for_intent,
        )

    def _executor(name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        tool_db = SessionLocal()
        try:
            tool_session = tool_db.query(SimulationSession).get(session_id)
            if tool_session is None:
                return {"ok": False, "error": "session_not_found"}
            logger.info(
                "agent_run_once_tool_dispatch session=%s tool=%s args_keys=%s",
                int(session_id),
                str(name or ""),
                list((args or {}).keys())[:10],
            )
            out = _agent_execute_tool(
                session=tool_session,
                db=tool_db,
                permissions=perms,
                context_snapshot=merged_ctx,
                tool_name=name,
                args=args,
                tool_config=effective_tool_cfg,
                atomic=False,
            )
            if isinstance(out, dict) and bool(out.get("ok", False)):
                tsp = _agent_tool_state_from_tool_calls(
                    [{"tool_id": str(name or ""), "args": (args if isinstance(args, dict) else {}), "result": out}]
                )
                if isinstance(tsp, dict) and tsp:
                    cur_ts = merged_ctx.get("tool_state") if isinstance(merged_ctx.get("tool_state"), dict) else {}
                    merged_ctx["tool_state"] = {**cur_ts, **tsp}
                if str(name or "").strip().lower() == "set_market_context":
                    merged_ctx["bars"] = []
                data_obj = out.get("data") if isinstance(out.get("data"), dict) else {}
                if isinstance(data_obj.get("bars"), list) and len(data_obj.get("bars")) >= 20:
                    merged_ctx["bars"] = data_obj.get("bars")
            logger.info(
                "agent_run_once_tool_result session=%s tool=%s ok=%s error=%s",
                int(session_id),
                str(name or ""),
                bool(out.get("ok")) if isinstance(out, dict) else False,
                out.get("error") if isinstance(out, dict) else None,
            )
            tool_db.commit()
            return out
        except Exception as exc:
            tool_db.rollback()
            logger.warning(
                "agent_run_once_tool_exception session=%s tool=%s err=%s",
                int(session_id),
                str(name or ""),
                f"{type(exc).__name__}: {str(exc)[:180]}",
            )
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
        finally:
            tool_db.close()

    provider_name = str(provider_cfg.get("provider") or "deterministic")
    delta_mgr = get_delta_manager(str(session_id))
    market_summary = merged_ctx.get("market_summary") if isinstance(merged_ctx.get("market_summary"), dict) else {}
    stats_obj = merged_ctx.get("session_stats") if isinstance(merged_ctx.get("session_stats"), dict) else {}
    bars_obj = merged_ctx.get("bars") if isinstance(merged_ctx.get("bars"), list) else []
    last_price_from_bars = None
    if bars_obj:
        last_bar = bars_obj[-1] if isinstance(bars_obj[-1], dict) else {}
        if isinstance(last_bar, dict):
            try:
                last_price_from_bars = float(last_bar.get("close")) if last_bar.get("close") is not None else None
            except Exception:
                last_price_from_bars = None
    delta_input = {
        "last_price": market_summary.get("current_price", last_price_from_bars),
        "atr_14": market_summary.get("atr14", market_summary.get("range20", 1.0)),
        "balance": stats_obj.get("current_balance"),
        "positions": merged_ctx.get("open_positions", []),
        "triggers": merged_ctx.get("scheduled_triggers", []),
    }
    merged_ctx["_delta_context"] = delta_mgr.compute_delta(delta_input)
    cb = get_circuit_breaker()
    provider_for_call = provider_name
    fallback_provider = cb.get_fallback(provider_name)
    if fallback_provider:
        provider_for_call = str(fallback_provider)
        logger.warning(
            "agent_run_once_circuit_breaker_fallback session=%s from=%s to=%s",
            int(session_id),
            provider_name,
            provider_for_call,
        )
    model_label_for_call = provider_cfg.get("model_label")
    llm_url_for_call = provider_cfg.get("llm_url")
    api_key_for_call = provider_cfg.get("api_key")
    if provider_for_call != provider_name:
        model_label_for_call = None
        llm_url_for_call = None
        api_key_for_call = None
    max_steps_eff = _agent_effective_max_tool_steps(provider_for_call, req.max_tool_steps)
    agent = WorkbenchAgent()
    out = agent.run_once(
        context=merged_ctx,
        objective=str(req.objective or "").strip(),
        provider=provider_for_call,
        model_label=model_label_for_call,
        llm_url=llm_url_for_call,
        api_key=api_key_for_call,
        timeout_sec=provider_cfg.get("timeout_sec"),
        permissions=perms,
        tool_executor=_executor,
        allow_tools=bool(req.allow_tools),
        max_tool_steps=max_steps_eff,
        allowed_tool_names=allowed_tool_names,
    )
    if provider_for_call == provider_name:
        if bool(out.get("ok", False)):
            cb.record_success(provider_name)
        else:
            err_text = str(out.get("error") or "")
            if any(tok in err_text for tok in ("429", "500", "502", "503", "504", "529", "Timeout", "ReadTimeout", "ConnectTimeout")):
                cb.record_failure(provider_name)

    persist_db = SessionLocal()
    lock = _get_agent_session_lock(int(session_id))
    try:
        with lock:
            session_p = persist_db.query(SimulationSession).get(session_id)
            if session_p is None:
                raise HTTPException(404, "Session not found")
            agent_row_p = (
                persist_db.query(WorkbenchAgentSessionModel).get(int(agent_session_id))
                if agent_session_id is not None
                else None
            )
            if agent_row_p is None:
                agent_row_p = _ensure_agent_session(
                    simulation_session_id=int(session_id),
                    db=persist_db,
                    mode="RUN_ONCE",
                    provider=str(provider_cfg.get("provider") or "deterministic"),
                    model_label=str(provider_cfg.get("model_label") or "").strip() or None,
                    permissions=perms,
                    config=(req.config if isinstance(req.config, dict) else {}),
                    runtime={
                        "llm_url": provider_cfg.get("llm_url"),
                        "timeout_sec": int(provider_cfg.get("timeout_sec") or 45),
                    },
                    copilot_session_id=None,
                )
                agent_session_id = int(agent_row_p.id)
            out = _agent_enforce_execution_truth(
                out=out if isinstance(out, dict) else {},
                user_message=str(req.objective or ""),
                session=session_p,
                agent_row=agent_row_p,
                db=persist_db,
                permissions=perms,
                context_snapshot=merged_ctx,
            )
            saved_memory_notes = _persist_agent_memory_notes(
                simulation_session=session_p,
                db=persist_db,
                memory_notes=out.get("memory_notes"),
                source="agent_model",
            )
            usage_payload = _normalize_agent_usage_payload(out.get("usage"))
            prev_snap = agent_row_p.last_snapshot_json if isinstance(agent_row_p.last_snapshot_json, dict) else {}
            usage_meter = _agent_rollup_usage_meter(prev_snap, usage_payload)
            _agent_emit_event(
                agent=agent_row_p,
                event_type="AGENT_RUN_ONCE",
                payload={
                    "ok": bool(out.get("ok", False)),
                    "objective": str(req.objective or ""),
                    "tool_calls": int(len(out.get("tool_calls") or [])),
                    "tool_ids": _agent_tool_ids_from_calls(out.get("tool_calls")),
                    "proposed_actions": int(len(out.get("proposed_actions") or [])),
                    "memory_saved": int(saved_memory_notes),
                    "provider": str(provider_cfg.get("provider") or "deterministic"),
                    "usage": usage_payload,
                    "integrity_warning": str(out.get("integrity_warning") or "") or None,
                },
                severity="info" if bool(out.get("ok", False)) else "warning",
                db=persist_db,
            )
            _agent_store_snapshot(
                agent=agent_row_p,
                simulation_session=session_p,
                db=persist_db,
                source="run_once",
                patch={
                    "tool_state": {
                        **(
                            merged_ctx.get("tool_state")
                            if isinstance(merged_ctx.get("tool_state"), dict)
                            else {}
                        ),
                        **_agent_tool_state_from_tool_calls(out.get("tool_calls")),
                    },
                    "agent_last_message": str(out.get("reply") or out.get("error") or "")[:2000],
                    "memory_saved": int(saved_memory_notes),
                    "usage_meter": usage_meter,
                    "last_usage": usage_payload,
                },
            )
            _record_external_copilot_event(
                simulation_session_id=int(session_id),
                event_type="PERIODIC_REVIEW",
                payload={
                    "source": "AGENT_RUN_ONCE",
                    "provider": str(provider_cfg.get("provider") or "deterministic"),
                    "ok": bool(out.get("ok", False)),
                    "tool_calls": int(len(out.get("tool_calls") or [])),
                    "usage": usage_payload,
                },
                severity="info" if bool(out.get("ok", False)) else "warning",
                db=persist_db,
                auto_commit=False,
            )
            persist_db.commit()
    except Exception:
        persist_db.rollback()
        raise
    finally:
        persist_db.close()

    return AgentResponse(
        ok=bool(out.get("ok", False)),
        session_id=int(session_id),
        provider=str(out.get("provider") or provider_cfg.get("provider") or "deterministic"),
        model_label=str(out.get("model") or provider_cfg.get("model_label") or "") or None,
        message=str(out.get("reply") or out.get("error") or ""),
        tool_calls=out.get("tool_calls") if isinstance(out.get("tool_calls"), list) else [],
        proposed_actions=_normalize_agent_proposed_actions(out.get("proposed_actions")),
        usage=_normalize_agent_usage_payload(out.get("usage")),
        audit={
            "agent_session_id": int(agent_session_id or 0),
            "generated_at": out.get("generated_at"),
            "raw_text": out.get("raw_text"),
            "memory_notes": out.get("memory_notes") if isinstance(out.get("memory_notes"), list) else [],
            "usage": _normalize_agent_usage_payload(out.get("usage")),
            "error": out.get("error"),
        },
    )


@router.post("/sessions/{session_id}/agent/start")
def workbench_agent_start(
    session_id: int,
    req: AgentLoopStartRequest,
    db: Session = Depends(get_db),
):
    """Start unified Agent loop by wiring to existing copilot runtime."""
    provider_cfg = _model_to_dict(req.provider)
    perms = _model_to_dict(req.permissions)
    config = dict(req.config or {})
    config["agent_unified"] = True
    config["agent_permissions"] = perms
    config["agent_loop_interval_sec"] = float(req.loop_interval_sec)
    # Make LLM review cadence responsive for live/interactive loops unless user overrides it.
    if config.get("review_interval_bars") is None:
        config["review_interval_bars"] = 10

    auto_exec_enabled = bool(perms.get("can_auto_execute", False))
    can_trade = bool(perms.get("can_place_trades", False) and perms.get("can_close_trades", False))
    requires_confirm = bool(perms.get("requires_user_confirm_for_trade", True))
    mode = "AUTO_PAPER" if (auto_exec_enabled and can_trade and not requires_confirm) else "ADVISE"

    runtime = dict(req.runtime or {})
    if provider_cfg.get("llm_url") and runtime.get("llm_url") is None:
        runtime["llm_url"] = provider_cfg.get("llm_url")
    if provider_cfg.get("api_key") and runtime.get("api_key") is None:
        runtime["api_key"] = provider_cfg.get("api_key")
    if provider_cfg.get("timeout_sec") is not None and runtime.get("llm_timeout_sec") is None:
        runtime["llm_timeout_sec"] = int(provider_cfg.get("timeout_sec"))
    # Runtime secrets are allowed for live execution path, but must never be persisted.
    runtime_for_db = {
        k: v
        for k, v in runtime.items()
        if str(k) not in {"api_key", "openai_api_key", "anthropic_api_key", "claude_api_key", "llm_api_key"}
    }

    cop_req = CopilotStartRequest(
        mode=mode,
        provider=str(provider_cfg.get("provider") or "deterministic"),
        model_label=str(provider_cfg.get("model_label") or "").strip() or None,
        config=config,
        runtime=runtime,
    )
    raw = _workbench_start_copilot_impl(session_id=session_id, req=cop_req, db=db, auto_commit=False)
    copilot = _get_active_copilot(simulation_session_id=int(session_id), db=db)
    agent_row = _ensure_agent_session(
        simulation_session_id=int(session_id),
        db=db,
        mode=str(req.mode or "LOOP"),
        provider=str(provider_cfg.get("provider") or "deterministic"),
        model_label=str(provider_cfg.get("model_label") or "").strip() or None,
        permissions=perms,
        config=config,
        runtime=runtime_for_db,
        copilot_session_id=int(copilot.id) if copilot is not None else None,
    )
    session = db.query(SimulationSession).get(session_id)
    if session is not None:
        _agent_emit_event(
            agent=agent_row,
            event_type="AGENT_STARTED",
            payload={
                "mode": str(req.mode or "LOOP"),
                "provider": str(provider_cfg.get("provider") or "deterministic"),
                "loop_interval_sec": float(req.loop_interval_sec),
                "copilot_mode": mode,
            },
            db=db,
        )
        _agent_store_snapshot(
            agent=agent_row,
            simulation_session=session,
            db=db,
            source="start",
            patch={
                "tool_state": {},
                "usage_meter": {
                    "day": _utc_now().date().isoformat(),
                    "day_input_tokens": 0,
                    "day_output_tokens": 0,
                    "day_total_tokens": 0,
                    "day_estimated_cost_usd": 0.0,
                    "day_llm_calls": 0,
                    "lifetime_input_tokens": 0,
                    "lifetime_output_tokens": 0,
                    "lifetime_total_tokens": 0,
                    "lifetime_estimated_cost_usd": 0.0,
                    "lifetime_llm_calls": 0,
                    "last_provider": "",
                    "last_model": "",
                    "last_usage": {},
                },
            },
        )
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Database commit failed")
    out = _agent_loop_facade_response(raw, session_id=session_id)
    if isinstance(out, dict):
        out["agent_session_id"] = int(agent_row.id)
    return out


@router.post("/sessions/{session_id}/agent/stop")
def workbench_agent_stop(
    session_id: int,
    db: Session = Depends(get_db),
):
    """Stop unified Agent loop (copilot-backed)."""
    raw = _workbench_stop_copilot_impl(session_id=session_id, db=db, auto_commit=False)
    session = db.query(SimulationSession).get(session_id)
    agent_row = _get_active_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is not None:
        agent_row.status = "STOPPED"
        agent_row.updated_at = _utc_now()
        agent_row.stopped_at = _utc_now()
        if session is not None:
            _agent_emit_event(agent=agent_row, event_type="AGENT_STOPPED", payload={}, db=db)
            _agent_store_snapshot(agent=agent_row, simulation_session=session, db=db, source="stop", patch={})
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Database commit failed")
    out = _agent_loop_facade_response(raw, session_id=session_id)
    if isinstance(out, dict) and agent_row is not None:
        out["agent_session_id"] = int(agent_row.id)
    return out


@router.post("/sessions/{session_id}/agent/pause")
def workbench_agent_pause(
    session_id: int,
    db: Session = Depends(get_db),
):
    """Pause unified Agent auto actions."""
    raw = _workbench_pause_auto_paper_impl(session_id=session_id, db=db, auto_commit=False)
    session = db.query(SimulationSession).get(session_id)
    agent_row = _get_active_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is not None and session is not None:
        _agent_emit_event(
            agent=agent_row,
            event_type="AGENT_PAUSED",
            payload={"reason": "manual_pause"},
            severity="warning",
            db=db,
        )
        _agent_store_snapshot(agent=agent_row, simulation_session=session, db=db, source="pause", patch={})
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Database commit failed")
    out = _agent_loop_facade_response(raw, session_id=session_id)
    if isinstance(out, dict) and agent_row is not None:
        out["agent_session_id"] = int(agent_row.id)
    return out


@router.post("/sessions/{session_id}/agent/resume")
def workbench_agent_resume(
    session_id: int,
    db: Session = Depends(get_db),
):
    """Resume unified Agent auto actions."""
    raw = _workbench_resume_auto_paper_impl(session_id=session_id, db=db, auto_commit=False)
    session = db.query(SimulationSession).get(session_id)
    agent_row = _get_active_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is not None and session is not None:
        _agent_emit_event(
            agent=agent_row,
            event_type="AGENT_RESUMED",
            payload={},
            severity="info",
            db=db,
        )
        _agent_store_snapshot(agent=agent_row, simulation_session=session, db=db, source="resume", patch={})
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Database commit failed")
    out = _agent_loop_facade_response(raw, session_id=session_id)
    if isinstance(out, dict) and agent_row is not None:
        out["agent_session_id"] = int(agent_row.id)
    return out


@router.get("/sessions/{session_id}/agent/state")
def workbench_agent_state(
    session_id: int,
    include_legacy_aliases: bool = Query(False),
    db: Session = Depends(get_db),
):
    """Unified Agent state facade over existing copilot state."""
    state = workbench_get_copilot_state(session_id=session_id, db=db)
    agent_state = _agent_state_payload(state, include_legacy_aliases=include_legacy_aliases)
    agent_row = _get_active_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session_id), db=db)
    cfg = {}
    if isinstance(agent_state, dict):
        cfg = agent_state.get("config") if isinstance(agent_state.get("config"), dict) else {}
    perms = cfg.get("agent_permissions") if isinstance(cfg.get("agent_permissions"), dict) else {}
    if agent_row is not None and isinstance(agent_row.permissions_json, dict):
        perms = dict(agent_row.permissions_json)
    if isinstance(agent_state, dict) and agent_row is not None:
        agent_state["agent_session_id"] = int(agent_row.id)
        if not include_legacy_aliases:
            agent_state.pop("copilot_session_id", None)
        if not isinstance(agent_state.get("last_snapshot"), dict) and isinstance(agent_row.last_snapshot_json, dict):
            agent_state["last_snapshot"] = dict(agent_row.last_snapshot_json)
    usage_meter: Dict[str, Any] = {}
    scheduled_triggers: List[Dict[str, Any]] = []
    if agent_row is not None and isinstance(agent_row.last_snapshot_json, dict):
        um = agent_row.last_snapshot_json.get("usage_meter")
        if isinstance(um, dict):
            usage_meter = dict(um)
            if isinstance(agent_state, dict):
                agent_state["usage_meter"] = usage_meter
        scheduled_triggers = _agent_trigger_rows_from_agent(agent_row)
        if isinstance(agent_state, dict):
            agent_state["scheduled_triggers"] = scheduled_triggers
    events_count = 0
    actions_count = 0
    snapshots_count = 0
    recent_events: List[Dict[str, Any]] = []
    recent_actions: List[Dict[str, Any]] = []
    if agent_row is not None:
        events_count = (
            db.query(WorkbenchAgentEventModel)
            .filter(WorkbenchAgentEventModel.agent_session_id == int(agent_row.id))
            .count()
        )
        actions_count = (
            db.query(WorkbenchAgentActionModel)
            .filter(WorkbenchAgentActionModel.agent_session_id == int(agent_row.id))
            .count()
        )
        snapshots_count = (
            db.query(WorkbenchAgentSnapshotModel)
            .filter(WorkbenchAgentSnapshotModel.agent_session_id == int(agent_row.id))
            .count()
        )
        rows_e = (
            db.query(WorkbenchAgentEventModel)
            .filter(WorkbenchAgentEventModel.agent_session_id == int(agent_row.id))
            .order_by(WorkbenchAgentEventModel.created_at.desc())
            .limit(8)
            .all()
        )
        recent_events = [
            {
                "id": int(e.id),
                "event_type": str(e.event_type or ""),
                "severity": str(e.severity or "info"),
                "payload": e.payload_json if isinstance(e.payload_json, dict) else {},
                "created_at": e.created_at.isoformat() if e.created_at else None,
            }
            for e in rows_e
        ]
        rows_a = (
            db.query(WorkbenchAgentActionModel)
            .filter(WorkbenchAgentActionModel.agent_session_id == int(agent_row.id))
            .order_by(WorkbenchAgentActionModel.created_at.desc())
            .limit(8)
            .all()
        )
        recent_actions = [
            {
                "id": int(a.id),
                "copilot_action_id": int(a.copilot_action_id) if a.copilot_action_id is not None else None,
                "action_type": str(a.action_type or ""),
                "status": str(a.status or ""),
                "requested_by": str(a.requested_by or ""),
                "reason": str(a.reason or "") if a.reason is not None else None,
                "payload": a.payload_json if isinstance(a.payload_json, dict) else {},
                "result": a.result_json if isinstance(a.result_json, dict) else {},
                "created_at": a.created_at.isoformat() if a.created_at else None,
            }
            for a in rows_a
        ]
    if isinstance(agent_state, dict):
        agent_state["recent_agent_events"] = recent_events
        agent_state["recent_agent_actions"] = recent_actions
    out = {
        "ok": True,
        "session_id": int(session_id),
        "agent_session_id": int(agent_row.id) if agent_row is not None else (
            int(agent_state.get("agent_session_id")) if isinstance(agent_state, dict) and agent_state.get("agent_session_id") is not None else None
        ),
        "active": bool(agent_state.get("active", False)) if isinstance(agent_state, dict) else False,
        "status": str(agent_state.get("status") or "NOT_STARTED") if isinstance(agent_state, dict) else "NOT_STARTED",
        "provider": str(agent_state.get("provider") or "deterministic") if isinstance(agent_state, dict) else "deterministic",
        "model_label": (str(agent_state.get("model_label") or "") if isinstance(agent_state, dict) else "") or None,
        "permissions": perms,
        "usage_meter": usage_meter,
        "scheduled_triggers": scheduled_triggers,
        "state": agent_state,
        "agent_state": agent_state,
        "agent_audit": {
            "events": int(events_count),
            "actions": int(actions_count),
            "snapshots": int(snapshots_count),
            "recent_events": recent_events,
            "recent_actions": recent_actions,
        },
    }
    if include_legacy_aliases and isinstance(state, dict):
        out["copilot_state"] = state
    return out


@router.get("/sessions/{session_id}/agent/triggers")
def workbench_agent_triggers_list(
    session_id: int,
    db: Session = Depends(get_db),
):
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent triggers are available only for Workbench sessions")
    agent_row = _get_active_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session_id), db=db)
    rows = _agent_trigger_rows_from_agent(agent_row)
    return {
        "ok": True,
        "session_id": int(session_id),
        "agent_session_id": int(agent_row.id) if agent_row is not None else None,
        "count": int(len(rows)),
        "triggers": rows,
    }


@router.delete("/sessions/{session_id}/agent/triggers")
def workbench_agent_triggers_cancel_all(
    session_id: int,
    all: bool = Query(default=False),
    db: Session = Depends(get_db),
):
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent triggers are available only for Workbench sessions")
    if not bool(all):
        raise HTTPException(400, "Set all=true to cancel all pending triggers")
    agent_row = _get_active_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is None:
        return {"ok": True, "session_id": int(session_id), "cancelled": 0, "triggers": []}
    rows = _get_agent_trade_triggers(agent_row)
    cancelled = 0
    next_rows: List[Dict[str, Any]] = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        rr = dict(r)
        st = str(rr.get("status") or "pending").lower()
        if st in {"pending", "pending_approval"}:
            rr["status"] = "canceled"
            rr["canceled_at"] = _utc_now().isoformat()
            cancelled += 1
        next_rows.append(rr)
    _set_agent_trade_triggers(agent_row=agent_row, triggers=next_rows)
    db.add(agent_row)
    _agent_emit_event(
        agent=agent_row,
        event_type="AGENT_TRIGGER_CANCELLED_ALL",
        payload={"cancelled": int(cancelled)},
        severity="info",
        db=db,
    )
    db.commit()
    return {
        "ok": True,
        "session_id": int(session_id),
        "cancelled": int(cancelled),
        "triggers": _agent_trigger_rows_from_agent(agent_row),
    }


@router.delete("/sessions/{session_id}/agent/triggers/{trigger_id}")
def workbench_agent_trigger_cancel(
    session_id: int,
    trigger_id: str,
    db: Session = Depends(get_db),
):
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent triggers are available only for Workbench sessions")
    tid = str(trigger_id or "").strip()
    if not tid:
        raise HTTPException(400, "trigger_id is required")
    agent_row = _get_active_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is None:
        agent_row = _get_latest_agent(simulation_session_id=int(session_id), db=db)
    if agent_row is None:
        raise HTTPException(404, "Agent session not found")
    rows = _get_agent_trade_triggers(agent_row)
    found = False
    changed = False
    next_rows: List[Dict[str, Any]] = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        rr = dict(r)
        if str(rr.get("id") or "").strip() == tid:
            found = True
            st = str(rr.get("status") or "pending").lower()
            if st in {"pending", "pending_approval"}:
                rr["status"] = "canceled"
                rr["canceled_at"] = _utc_now().isoformat()
                changed = True
        next_rows.append(rr)
    if not found:
        raise HTTPException(404, "Trigger not found")
    if changed:
        _set_agent_trade_triggers(agent_row=agent_row, triggers=next_rows)
        db.add(agent_row)
        _agent_emit_event(
            agent=agent_row,
            event_type="AGENT_TRIGGER_CANCELLED",
            payload={"trigger_id": tid},
            severity="info",
            db=db,
        )
        db.commit()
    return {
        "ok": True,
        "session_id": int(session_id),
        "cancelled": bool(changed),
        "trigger_id": tid,
        "triggers": _agent_trigger_rows_from_agent(agent_row),
    }


@router.get("/sessions/{session_id}/agent/memory")
def workbench_agent_memory_list(
    session_id: int,
    query: str = Query(default=""),
    limit: int = Query(default=20, ge=1, le=100),
    memory_type: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
):
    """List/search persistent agent memories relevant to this workbench session."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent memory is available only for Workbench sessions")
    policy = _memory_policy_from_session_config(session)
    _agent_memory_prune_expired(simulation_session=session, db=db, policy=policy)
    qtxt = str(query or "").strip()
    if qtxt:
        rows = _agent_memory_search(
            simulation_session=session,
            db=db,
            query_text=qtxt,
            limit=int(limit),
            memory_type=memory_type,
        )
        return {"ok": True, "session_id": int(session_id), "query": qtxt, "count": int(len(rows)), "memories": rows, "policy": policy}
    symbol = str(session.symbol or "").strip().upper()
    rows_q = (
        db.query(WorkbenchAgentMemoryModel)
        .filter(
            or_(
                WorkbenchAgentMemoryModel.scope == "GLOBAL",
                WorkbenchAgentMemoryModel.simulation_session_id == int(session.id),
                WorkbenchAgentMemoryModel.symbol == symbol,
            )
        )
        .order_by(WorkbenchAgentMemoryModel.updated_at.desc(), WorkbenchAgentMemoryModel.id.desc())
    )
    if memory_type:
        rows_q = rows_q.filter(WorkbenchAgentMemoryModel.memory_type == _normalize_memory_type(memory_type))
    rows = rows_q.limit(int(limit)).all()
    out: List[Dict[str, Any]] = [_memory_row_to_dict(r) for r in rows]
    return {"ok": True, "session_id": int(session_id), "query": "", "count": int(len(out)), "memories": out, "policy": policy}


@router.get("/sessions/{session_id}/agent/memory-policy")
def workbench_agent_memory_policy_get(
    session_id: int,
    db: Session = Depends(get_db),
):
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent memory policy is available only for Workbench sessions")
    policy = _memory_policy_from_session_config(session)
    return {"ok": True, "session_id": int(session_id), "policy": policy}


@router.post("/sessions/{session_id}/agent/memory-policy")
def workbench_agent_memory_policy_set(
    session_id: int,
    req: AgentMemoryPolicyRequest,
    db: Session = Depends(get_db),
):
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent memory policy is available only for Workbench sessions")
    patch = req.model_dump(exclude_none=True)
    clean = _memory_policy_update_session_config(session=session, patch=patch)
    db.add(session)
    _agent_memory_prune_expired(simulation_session=session, db=db, policy=clean, force=True)
    db.commit()
    return {"ok": True, "session_id": int(session_id), "policy": clean}


@router.get("/sessions/{session_id}/agent/identity")
def workbench_agent_identity_get(
    session_id: int,
    db: Session = Depends(get_db),
):
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent identity is available only for Workbench sessions")
    identity = _agent_identity_from_session_config(session)
    return {"ok": True, "session_id": int(session_id), "identity": identity}


@router.post("/sessions/{session_id}/agent/identity")
def workbench_agent_identity_set(
    session_id: int,
    req: AgentIdentityRequest,
    db: Session = Depends(get_db),
):
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent identity is available only for Workbench sessions")
    patch = req.model_dump(exclude_none=True)
    clean = _agent_identity_update_session_config(session=session, patch=patch)
    db.add(session)
    db.commit()
    return {"ok": True, "session_id": int(session_id), "identity": clean}


@router.post("/sessions/{session_id}/agent/memory")
def workbench_agent_memory_add(
    session_id: int,
    req: AgentMemoryWriteRequest,
    db: Session = Depends(get_db),
):
    """Persist a manual memory note for the unified agent."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent memory is available only for Workbench sessions")
    row = _agent_memory_add(
        simulation_session=session,
        db=db,
        content=str(req.content or ""),
        memory_type=str(req.memory_type or "note"),
        scope=str(req.scope or "SESSION"),
        importance=float(req.importance or 0.7),
        source="manual",
        metadata=req.metadata if isinstance(req.metadata, dict) else {},
        symbol=req.symbol,
        timeframe=req.timeframe,
    )
    if row is None:
        raise HTTPException(400, "Memory rejected")
    db.commit()
    return {
        "ok": True,
        "session_id": int(session_id),
        "memory": _memory_row_to_dict(row),
    }


def _memory_row_to_dict(row: WorkbenchAgentMemoryModel) -> Dict[str, Any]:
    md = row.metadata_json if isinstance(row.metadata_json, dict) else {}
    pinned = _memory_is_pinned(row)
    if "pinned" not in md:
        md = dict(md)
        md["pinned"] = bool(pinned)
    return {
        "id": int(row.id),
        "scope": str(row.scope or ""),
        "memory_type": str(row.memory_type or ""),
        "content": str(row.content or ""),
        "symbol": str(row.symbol or "") if row.symbol else None,
        "timeframe": str(row.timeframe or "") if row.timeframe else None,
        "importance": float(row.importance or 0.0),
        "source": str(row.source or ""),
        "metadata": md,
        "pinned": bool(pinned),
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        "access_count": int(row.access_count or 0),
    }


def _memory_row_visible_for_session(
    *,
    row: WorkbenchAgentMemoryModel,
    session: SimulationSession,
) -> bool:
    symbol = str(session.symbol or "").strip().upper()
    return bool(
        str(row.scope or "") == "GLOBAL"
        or (row.simulation_session_id is not None and int(row.simulation_session_id) == int(session.id))
        or (row.symbol is not None and str(row.symbol or "").upper() == symbol)
    )


@router.patch("/sessions/{session_id}/agent/memory/{memory_id}")
def workbench_agent_memory_update(
    session_id: int,
    memory_id: int,
    req: AgentMemoryUpdateRequest,
    db: Session = Depends(get_db),
):
    """Update one memory row (pin/edit/scope/type/importance)."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent memory is available only for Workbench sessions")
    row = db.query(WorkbenchAgentMemoryModel).get(int(memory_id))
    if row is None:
        raise HTTPException(404, "Memory not found")
    if not _memory_row_visible_for_session(row=row, session=session):
        raise HTTPException(403, "Forbidden memory scope")

    if req.content is not None:
        row.content = re.sub(r"\s+", " ", str(req.content or "").strip())[:2000]
    if req.memory_type is not None:
        row.memory_type = _normalize_memory_type(req.memory_type)
    if req.scope is not None:
        row.scope = _normalize_memory_scope(req.scope)
    if req.importance is not None:
        row.importance = max(0.0, min(1.0, float(req.importance)))
    if req.symbol is not None:
        row.symbol = str(req.symbol or "").strip().upper() or None
    if req.timeframe is not None:
        row.timeframe = str(req.timeframe or "").strip().upper() or None
    scope_now = str(row.scope or "SESSION").upper()
    if scope_now == "SESSION":
        row.simulation_session_id = int(session.id)
        if not row.symbol:
            row.symbol = str(session.symbol or "").strip().upper() or None
        if not row.timeframe:
            row.timeframe = str(session.timeframe or "").strip().upper() or None
    elif scope_now == "SYMBOL":
        row.simulation_session_id = None
        if not row.symbol:
            row.symbol = str(session.symbol or "").strip().upper() or None
        if not row.timeframe:
            row.timeframe = str(session.timeframe or "").strip().upper() or None
    else:
        row.simulation_session_id = None
        row.symbol = None
        row.timeframe = None
    md = row.metadata_json if isinstance(row.metadata_json, dict) else {}
    if isinstance(req.metadata, dict):
        md.update(req.metadata)
        if "pinned" in req.metadata:
            row.pinned = bool(req.metadata.get("pinned", False))
    if req.pinned is not None:
        row.pinned = bool(req.pinned)
        md["pinned"] = bool(req.pinned)
        if bool(req.pinned):
            row.importance = max(float(row.importance or 0.0), 0.95)
    row.metadata_json = md
    row.updated_at = datetime.utcnow()
    row.fingerprint = _memory_fingerprint(
        content=str(row.content or ""),
        memory_type=str(row.memory_type or ""),
        scope=str(row.scope or ""),
        symbol=(str(row.symbol or "") or None),
        timeframe=(str(row.timeframe or "") or None),
    )
    db.add(row)
    db.commit()
    return {"ok": True, "session_id": int(session_id), "memory": _memory_row_to_dict(row)}


@router.delete("/sessions/{session_id}/agent/memory/{memory_id}")
def workbench_agent_memory_delete(
    session_id: int,
    memory_id: int,
    db: Session = Depends(get_db),
):
    """Delete one memory row visible to this session scope."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent memory is available only for Workbench sessions")
    row = db.query(WorkbenchAgentMemoryModel).get(int(memory_id))
    if row is None:
        raise HTTPException(404, "Memory not found")
    visible = _memory_row_visible_for_session(row=row, session=session)
    if not visible:
        raise HTTPException(403, "Forbidden memory scope")
    db.delete(row)
    db.commit()
    return {"ok": True, "session_id": int(session_id), "deleted_id": int(memory_id)}


@router.post("/sessions/{session_id}/agent/action")
def workbench_agent_action(
    session_id: int,
    req: AgentActionRequest,
    db: Session = Depends(get_db),
):
    """Apply/record a unified Agent action."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    if str(session.strategy_id or "") != WORKBENCH_ID:
        raise HTTPException(400, "Agent action is available only for Workbench sessions")

    row = _get_active_copilot(simulation_session_id=int(session.id), db=db)
    perms = {}
    if row is not None and isinstance(row.config_json, dict):
        perms = row.config_json.get("agent_permissions") if isinstance(row.config_json.get("agent_permissions"), dict) else {}
    if not perms:
        perms = {
            "can_place_trades": False,
            "can_close_trades": False,
            "requires_user_confirm_for_trade": True,
            "can_use_research": False,
            "can_scan_tools": True,
            "can_manage_indicators": True,
        }
    agent_row = _ensure_agent_session(
        simulation_session_id=int(session.id),
        db=db,
        mode="LOOP",
        provider=str(row.provider or "deterministic") if row is not None else "deterministic",
        model_label=str(row.model_label or "") if row is not None else None,
        permissions=perms,
        config=row.config_json if (row is not None and isinstance(row.config_json, dict)) else {},
        runtime=_runtime_summary(get_copilot_runtime(int(row.id))) if row is not None else {},
        copilot_session_id=int(row.id) if row is not None else None,
    )

    execution_result: Optional[Dict[str, Any]] = None
    if str(req.status).upper() == "EXECUTED":
        if req.action_type == "EXECUTE_TRADE_ENTRY":
            execution_result = _agent_execute_tool(
                session=session,
                db=db,
                permissions=perms,
                context_snapshot=_agent_default_context(session=session, db=db),
                tool_name="place_trade",
                args=req.payload if isinstance(req.payload, dict) else {},
            )
        elif req.action_type == "EXECUTE_TRADE_EXIT":
            execution_result = _agent_execute_tool(
                session=session,
                db=db,
                permissions=perms,
                context_snapshot=_agent_default_context(session=session, db=db),
                tool_name="close_trade",
                args=req.payload if isinstance(req.payload, dict) else {},
            )

    copilot_log = None
    copilot_action_id: Optional[int] = None
    if row is not None:
        mapped_type = str(req.action_type or "").strip().upper()
        if str(req.status).upper() == "REJECTED":
            mapped_type = "REJECTED"
        elif str(req.status).upper() == "APPROVED":
            mapped_type = "APPROVED"
        elif str(req.status).upper() == "EXECUTED":
            mapped_type = "EXECUTED"
        cop_req = CopilotActionRequest(
            action_type=mapped_type,
            advice_id=int(req.action_id) if req.action_id is not None else None,
            payload={
                "agent_action_type": str(req.action_type),
                "status": str(req.status),
                "payload": req.payload if isinstance(req.payload, dict) else {},
                "execution_result": execution_result,
            },
            note=req.reason,
        )
        copilot_log = _workbench_log_copilot_action_impl(session_id=session_id, req=cop_req, db=db, auto_commit=False)
        if isinstance(copilot_log, dict) and copilot_log.get("action_id") is not None:
            try:
                copilot_action_id = int(copilot_log.get("action_id"))
            except Exception:
                copilot_action_id = None

    agent_action = WorkbenchAgentActionModel(
        agent_session_id=int(agent_row.id),
        copilot_action_id=copilot_action_id,
        action_type=str(req.action_type),
        status=str(req.status),
        requested_by=str(req.requested_by),
        reason=str(req.reason or "").strip() or None,
        payload_json=req.payload if isinstance(req.payload, dict) else {},
        result_json=execution_result if isinstance(execution_result, dict) else {},
        created_at=datetime.utcnow(),
    )
    db.add(agent_action)
    _agent_emit_event(
        agent=agent_row,
        event_type="AGENT_ACTION",
        payload={
            "requested_by": str(req.requested_by),
            "action_type": str(req.action_type),
            "status": str(req.status),
        },
        db=db,
    )
    _agent_store_snapshot(
        agent=agent_row,
        simulation_session=session,
        db=db,
        source="action",
        patch={"agent_last_action": str(req.action_type)},
    )
    _record_external_copilot_event(
        simulation_session_id=int(session.id),
        event_type="MANUAL_OVERRIDE",
        payload={
            "override_type": "AGENT_ACTION",
            "requested_by": str(req.requested_by),
            "action_type": str(req.action_type),
            "status": str(req.status),
        },
        severity="info",
        db=db,
        auto_commit=False,
    )
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(500, "Database commit failed")
    db.refresh(agent_action)
    return {
        "ok": True,
        "session_id": int(session.id),
        "agent_session_id": int(agent_row.id),
        "agent_action_id": int(agent_action.id),
        "action_type": str(req.action_type),
        "status": str(req.status),
        "execution_result": execution_result,
        "audit": copilot_log,
    }


@router.get("/sessions/{session_id}/coach/evaluations")
def workbench_list_evaluations(
    session_id: int,
    limit: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """List recent coaching evaluations for a session."""
    session = db.query(SimulationSession).get(session_id)
    if not session:
        raise HTTPException(404, "Session not found")
    rows = (
        db.query(AIBotRunModel)
        .filter(AIBotRunModel.strategy_id == "workbench")
        .filter(AIBotRunModel.context_id == str(session_id))
        .order_by(AIBotRunModel.created_at.desc())
        .limit(limit)
        .all()
    )
    return [_ai_run_to_dict(r) for r in rows]


@router.get("/sessions/{session_id}/coach/evaluations/{run_id}")
def workbench_get_evaluation(
    session_id: int,
    run_id: str,
    db: Session = Depends(get_db),
):
    """Fetch one coaching evaluation run by ID."""
    row = (
        db.query(AIBotRunModel)
        .filter(AIBotRunModel.run_id == str(run_id))
        .filter(AIBotRunModel.strategy_id == "workbench")
        .filter(AIBotRunModel.context_id == str(session_id))
        .first()
    )
    if not row:
        raise HTTPException(404, "Evaluation run not found")
    return _ai_run_to_dict(row)
