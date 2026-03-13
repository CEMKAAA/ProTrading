"""
Backend-native MT5 live tick relay for Workbench Agent triggers.

This removes trigger execution dependence on browser LIVE_TICK pushes by polling
MT5 directly for sessions explicitly marked as live-enabled.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from ..models.database import SessionLocal, SimulationSession, WorkbenchAgentSessionModel
from .agent_watchdog_service import get_agent_watchdog_service


logger = logging.getLogger(__name__)


def _json_obj(value: Any) -> Dict[str, Any]:
    if isinstance(value, dict):
        return dict(value)
    if isinstance(value, str):
        raw = str(value).strip()
        if not raw:
            return {}
        try:
            obj = json.loads(raw)
            return obj if isinstance(obj, dict) else {}
        except Exception:
            return {}
    return {}


class AgentLiveTickService:
    def __init__(self) -> None:
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()

    @staticmethod
    def _enabled() -> bool:
        raw = str(os.getenv("AGENT_BACKEND_LIVE_TICKS_ENABLED", "1")).strip().lower()
        return raw not in {"0", "false", "no", "off"}

    @staticmethod
    def _interval_sec() -> float:
        try:
            raw = float(os.getenv("AGENT_BACKEND_LIVE_TICKS_INTERVAL_SEC", "1.0"))
        except Exception:
            raw = 1.0
        return max(0.25, min(5.0, raw))

    @staticmethod
    def _session_live_control(session: SimulationSession) -> Dict[str, Any]:
        cfg = _json_obj(getattr(session, "config_json", None))
        live = cfg.get("live_control") if isinstance(cfg.get("live_control"), dict) else {}
        return dict(live)

    @classmethod
    def _backend_live_enabled(cls, session: SimulationSession) -> bool:
        live = cls._session_live_control(session)
        source = str(live.get("source") or "").strip().lower()
        return (
            str(getattr(session, "mode", "") or "").strip().lower() == "live"
            and bool(live.get("enabled", False))
            and bool(live.get("backend_native", False))
            and source == "mt5"
        )

    @staticmethod
    def _has_pending_trigger(agent: WorkbenchAgentSessionModel) -> bool:
        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        rows = snap.get("agent_trade_triggers") if isinstance(snap.get("agent_trade_triggers"), list) else []
        for row in rows:
            if not isinstance(row, dict):
                continue
            status = str(row.get("status") or "pending").strip().lower()
            state = str(row.get("state") or "").strip().lower()
            if status == "pending" and state in {"", "waiting_precondition", "waiting_entry"}:
                return True
        return False

    @staticmethod
    def _fetch_mt5_live_bar(session: SimulationSession) -> Optional[Dict[str, Any]]:
        try:
            from ..api import simulation_routes as sim_routes

            service = sim_routes._get_mt5_service_singleton()
            bars = service.get_recent_candles(
                symbol=str(session.symbol or "").strip() or "XAUUSD",
                timeframe=str(session.timeframe or "").strip().upper() or "M15",
                count=1,
            )
            if not isinstance(bars, list) or not bars:
                return None
            row = bars[-1] if isinstance(bars[-1], dict) else None
            if not isinstance(row, dict):
                return None
            ts = int(row.get("time_unix") or row.get("time") or 0)
            if ts <= 0:
                return None
            now_ts = int(datetime.now(timezone.utc).timestamp())
            return {
                "time": ts,
                "open": float(row.get("open") or 0.0),
                "high": float(row.get("high") or 0.0),
                "low": float(row.get("low") or 0.0),
                "close": float(row.get("close") or 0.0),
                "volume": float(row.get("volume") or 0.0),
                "asof_time": now_ts,
            }
        except Exception:
            return None

    @staticmethod
    def _store_agent_live_snapshot(
        agent: WorkbenchAgentSessionModel,
        session: SimulationSession,
        live_bar: Dict[str, Any],
    ) -> None:
        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        snap = dict(snap)
        tool_state = snap.get("tool_state") if isinstance(snap.get("tool_state"), dict) else {}
        tool_state = dict(tool_state)
        tool_state["live_feed_active"] = True
        tool_state["live_source"] = "mt5"
        tool_state["live_stream"] = {
            "bar_index": int(getattr(session, "current_bar", 0) or 0),
            "total_bars": int(getattr(session, "total_bars", 0) or 0),
            "pushed_at_ms": int(datetime.now(timezone.utc).timestamp() * 1000.0),
            "backend_native": True,
        }
        tool_state["live_bar"] = dict(live_bar)
        snap["tool_state"] = tool_state
        agent.last_snapshot_json = snap
        agent.updated_at = datetime.utcnow()

    def _process_once(self) -> None:
        db = SessionLocal()
        try:
            rows = (
                db.query(WorkbenchAgentSessionModel, SimulationSession)
                .join(SimulationSession, SimulationSession.id == WorkbenchAgentSessionModel.simulation_session_id)
                .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
                .filter(SimulationSession.status == "active")
                .all()
            )
            watchdog = get_agent_watchdog_service()
            for agent, session in rows:
                try:
                    if not self._backend_live_enabled(session):
                        continue
                    if not self._has_pending_trigger(agent):
                        continue
                    live_bar = self._fetch_mt5_live_bar(session)
                    if not isinstance(live_bar, dict):
                        continue
                    self._store_agent_live_snapshot(agent, session, live_bar)
                    out = watchdog.process_live_tick(
                        db=db,
                        agent=agent,
                        session=session,
                        live_bar=live_bar,
                        auto_commit=False,
                    )
                    if int(out.get("trigger_events_count") or 0) > 0:
                        logger.info(
                            "Backend MT5 tick relay processed trigger events: session=%s agent=%s events=%s",
                            int(session.id),
                            int(agent.id),
                            list(out.get("trigger_event_types") or []),
                        )
                    if bool(db.new) or bool(db.dirty) or bool(db.deleted):
                        db.commit()
                except Exception as exc:
                    db.rollback()
                    logger.exception(
                        "Backend MT5 tick relay failed for session=%s agent=%s: %s",
                        int(getattr(session, "id", 0) or 0),
                        int(getattr(agent, "id", 0) or 0),
                        exc,
                    )
        finally:
            db.close()

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                if self._enabled():
                    self._process_once()
            except Exception as exc:
                logger.exception("Backend MT5 tick relay loop failed: %s", exc)
            self._stop.wait(self._interval_sec())

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True, name="agent-live-tick-relay")
        self._thread.start()
        logger.info("Backend MT5 live tick relay started")

    def stop(self) -> None:
        self._stop.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        logger.info("Backend MT5 live tick relay stopped")
