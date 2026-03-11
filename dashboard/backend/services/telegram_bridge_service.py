"""
Telegram Bridge Service for Workbench Agent.

Provides a lightweight command interface from Telegram to the existing
Workbench agent/session endpoints without exposing new public HTTP routes.
"""

from __future__ import annotations

import logging
import math
import os
import threading
import time
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
from fastapi import HTTPException

from ..models.database import (
    SessionLocal,
    SimulationSession,
    SimulationTrade,
    WorkbenchAgentEventModel,
    WorkbenchAgentSessionModel,
    WorkbenchCopilotSessionModel,
)


logger = logging.getLogger(__name__)


def _json_obj(value: Any) -> Dict[str, Any]:
    if isinstance(value, dict):
        return value
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


class TelegramBridgeService:
    @staticmethod
    def _read_env_file_value(var_name: str) -> Optional[str]:
        """Lightweight .env lookup without requiring python-dotenv at runtime."""
        repo_root = Path(__file__).resolve().parents[3]
        candidates = [
            repo_root / "dashboard" / ".env",
            repo_root / ".env",
        ]
        for p in candidates:
            if not p.exists():
                continue
            try:
                for raw in p.read_text(encoding="utf-8").splitlines():
                    line = str(raw or "").strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    if str(k).strip() != str(var_name):
                        continue
                    val = str(v).strip().strip('"').strip("'")
                    if val:
                        return val
            except Exception:
                continue
        return None

    @classmethod
    def _normalize_profile_name(cls, value: Any) -> str:
        raw = str(value or "").strip().upper()
        if not raw:
            return "DEFAULT"
        raw = re.sub(r"[^A-Z0-9_]+", "_", raw)
        raw = re.sub(r"_+", "_", raw).strip("_")
        return raw or "DEFAULT"

    @classmethod
    def _active_profile(cls) -> str:
        raw = str(os.getenv("TELEGRAM_ACTIVE_PROFILE") or "").strip()
        if not raw:
            raw = str(os.getenv("TELEGRAM_BOT_PROFILE") or "").strip()
        if not raw:
            raw = str(cls._read_env_file_value("TELEGRAM_ACTIVE_PROFILE") or "").strip()
        if not raw:
            raw = str(cls._read_env_file_value("TELEGRAM_BOT_PROFILE") or "").strip()
        return cls._normalize_profile_name(raw)

    @classmethod
    def _profile_scoped_key(cls, key: str, profile: Optional[str] = None) -> Optional[str]:
        base = str(key or "").strip().upper()
        if not base.startswith("TELEGRAM_"):
            return None
        if base in {"TELEGRAM_ACTIVE_PROFILE", "TELEGRAM_BOT_PROFILE"}:
            return None
        suffix = base[len("TELEGRAM_") :].strip()
        if not suffix:
            return None
        prof = cls._normalize_profile_name(profile if profile is not None else cls._active_profile())
        if prof == "DEFAULT":
            return None
        return f"TELEGRAM_{prof}_{suffix}"

    @classmethod
    def _get_env_value(cls, name: str, default: str = "") -> str:
        key = str(name or "").strip()
        if not key:
            return str(default or "")
        scoped = cls._profile_scoped_key(key)
        if scoped:
            sv = str(os.getenv(scoped) or "").strip()
            if sv:
                return sv
            sf = str(cls._read_env_file_value(scoped) or "").strip()
            if sf:
                return sf
        v = str(os.getenv(key) or "").strip()
        if v:
            return v
        fv = str(cls._read_env_file_value(key) or "").strip()
        if fv:
            return fv
        return str(default or "")

    def __init__(self) -> None:
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._lock = threading.RLock()
        self._offset = 0
        self._default_session_by_chat: Dict[int, int] = {}
        self._history_by_chat_session: Dict[Tuple[int, int, str], List[Dict[str, str]]] = {}
        self._active_conversation_by_chat_session: Dict[Tuple[int, int], str] = {}
        self._pending_approvals_by_chat: Dict[int, List[Dict[str, Any]]] = {}
        self._next_local_approval_id_by_chat: Dict[int, int] = {}
        self._last_ask_at_by_chat: Dict[int, float] = {}
        self._last_watchdog_event_id_by_chat_session: Dict[Tuple[int, int], int] = {}
        self._last_watchdog_check_at_by_chat_session: Dict[Tuple[int, int], float] = {}

    @staticmethod
    def _enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_ENABLED", "0")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _token() -> str:
        return str(TelegramBridgeService._get_env_value("TELEGRAM_BOT_TOKEN", "")).strip()

    @staticmethod
    def _allowed_chat_id() -> Optional[int]:
        raw = str(TelegramBridgeService._get_env_value("TELEGRAM_ALLOWED_CHAT_ID", "")).strip()
        if not raw:
            return None
        try:
            return int(raw)
        except Exception:
            return None

    @staticmethod
    def _poll_interval_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_POLL_INTERVAL_SEC", "2"))
        except Exception:
            raw = 2.0
        return max(1.0, min(30.0, raw))

    @staticmethod
    def _ask_cooldown_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_ASK_COOLDOWN_SEC", "2"))
        except Exception:
            raw = 2.0
        return max(0.0, min(60.0, raw))

    @staticmethod
    def _watchdog_alerts_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_WATCHDOG_ALERTS_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _watchdog_alert_max_events() -> int:
        try:
            raw = int(TelegramBridgeService._get_env_value("TELEGRAM_WATCHDOG_ALERT_MAX_EVENTS", "6"))
        except Exception:
            raw = 6
        return max(1, min(30, raw))

    @staticmethod
    def _watchdog_alert_interval_sec() -> float:
        raw_env = str(TelegramBridgeService._get_env_value("TELEGRAM_WATCHDOG_ALERT_INTERVAL_SEC", "")).strip()
        if raw_env:
            try:
                raw = float(raw_env)
            except Exception:
                raw = 2.0
        else:
            raw = TelegramBridgeService._poll_interval_sec()
        return max(0.5, min(60.0, raw))

    @staticmethod
    def _watchdog_alert_event_types() -> Optional[set[str]]:
        raw = str(
            TelegramBridgeService._get_env_value(
                "TELEGRAM_WATCHDOG_ALERT_EVENT_TYPES",
                (
                    "WATCHDOG_ENTRY_EXECUTED,"
                    "WATCHDOG_ENTRY_PENDING,"
                    "WATCHDOG_ENTRY_FAILED,"
                    "WATCHDOG_ENTRY_CANCELED,"
                    "WATCHDOG_ENTRY_EXPIRED,"
                    "WATCHDOG_DECISION_PENDING,"
                    "WATCHDOG_DECISION_TIMEOUT,"
                    "WATCHDOG_MODEL_REVIEW"
                ),
            )
        ).strip()
        if not raw:
            return None
        if raw == "*":
            return None
        out: set[str] = set()
        for part in raw.split(","):
            tok = str(part or "").strip().upper()
            if tok:
                out.add(tok)
        return out if out else None

    @staticmethod
    def _agent_max_tool_steps() -> int:
        try:
            raw = int(TelegramBridgeService._get_env_value("TELEGRAM_AGENT_MAX_TOOL_STEPS", "10"))
        except Exception:
            raw = 10
        return max(1, min(12, raw))

    @staticmethod
    def _normalize_tool_access_mode(value: Any) -> str:
        raw = str(value or "").strip().lower()
        if raw in {"all", "parent", "child"}:
            return raw
        if raw in {"parents", "collected", "aggregate", "aggregated", "master"}:
            return "parent"
        if raw in {"children", "granular", "detailed", "childs"}:
            return "child"
        return "all"

    @staticmethod
    def _normalize_tool_selection_mode(value: Any) -> str:
        raw = str(value or "").strip().lower()
        if raw in {"autonomous", "guided", "minimal"}:
            return raw
        if raw in {"auto", "full", "all_tools"}:
            return "autonomous"
        if raw in {"default", "intent", "intent_history", "guided_intent"}:
            return "guided"
        if raw in {"min", "least", "strict_minimal"}:
            return "minimal"
        return "autonomous"

    def _base_url(self) -> str:
        return f"https://api.telegram.org/bot{self._token()}"

    def _format_botprofile(self) -> str:
        profile = self._active_profile()
        scoped_token_key = self._profile_scoped_key("TELEGRAM_BOT_TOKEN", profile)
        scoped_chat_key = self._profile_scoped_key("TELEGRAM_ALLOWED_CHAT_ID", profile)
        scoped_enabled_key = self._profile_scoped_key("TELEGRAM_ENABLED", profile)
        lines = [
            f"Telegram profile: {profile}",
            "Resolution order:",
            f"1) {scoped_token_key or 'TELEGRAM_BOT_TOKEN'} / {scoped_chat_key or 'TELEGRAM_ALLOWED_CHAT_ID'} / {scoped_enabled_key or 'TELEGRAM_ENABLED'}",
            "2) TELEGRAM_BOT_TOKEN / TELEGRAM_ALLOWED_CHAT_ID / TELEGRAM_ENABLED",
            f"Enabled: {'YES' if self._enabled() else 'NO'}",
            f"Allowed chat id: {str(self._allowed_chat_id() or 'MISSING')}",
            (
                "To switch bot system-wide set TELEGRAM_ACTIVE_PROFILE in dashboard/.env "
                "and define TELEGRAM_<PROFILE>_BOT_TOKEN + TELEGRAM_<PROFILE>_ALLOWED_CHAT_ID, then restart backend."
            ),
        ]
        return "\n".join(lines)

    @staticmethod
    def _now_iso() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _chunk_text(text: str, limit: int = 3500) -> List[str]:
        raw = str(text or "").strip()
        if not raw:
            return []
        if len(raw) <= limit:
            return [raw]
        chunks: List[str] = []
        cur = raw
        while len(cur) > limit:
            cut = cur.rfind("\n", 0, limit)
            if cut < int(limit * 0.5):
                cut = limit
            chunks.append(cur[:cut].strip())
            cur = cur[cut:].strip()
        if cur:
            chunks.append(cur)
        return chunks

    def _tg_request(
        self,
        method: str,
        *,
        params: Optional[Dict[str, Any]] = None,
        timeout_sec: float = 35.0,
        http_method: str = "GET",
    ) -> Dict[str, Any]:
        url = f"{self._base_url()}/{method}"
        httpx_logger = logging.getLogger("httpx")
        prev_level = httpx_logger.level
        try:
            # Telegram API token lives in endpoint path by design; suppress httpx INFO URL logs.
            if prev_level <= logging.INFO:
                httpx_logger.setLevel(logging.WARNING)
            with httpx.Client(timeout=timeout_sec, http2=False) as client:
                hm = str(http_method or "GET").strip().upper()
                if hm == "POST":
                    resp = client.post(url, data=params or {})
                else:
                    resp = client.get(url, params=params or {})
        finally:
            if prev_level <= logging.INFO:
                httpx_logger.setLevel(prev_level)
        if resp.status_code != 200:
            raise RuntimeError(f"telegram_http_{resp.status_code}:{(resp.text or '')[:200]}")
        body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
        if not isinstance(body, dict) or not bool(body.get("ok")):
            raise RuntimeError(f"telegram_api_error:{str(body)[:220]}")
        return body

    def _send_text(self, chat_id: int, text: str) -> None:
        for chunk in self._chunk_text(text, limit=3500):
            try:
                self._tg_request(
                    "sendMessage",
                    params={
                        "chat_id": int(chat_id),
                        "text": chunk,
                    },
                    timeout_sec=15.0,
                    http_method="POST",
                )
            except Exception as exc:
                logger.warning("telegram sendMessage failed: %s", str(exc)[:220])
                break

    def _can_run_ask(self, chat_id: int) -> Tuple[bool, float]:
        cooldown = float(self._ask_cooldown_sec())
        if cooldown <= 0:
            return True, 0.0
        now = time.time()
        with self._lock:
            last = float(self._last_ask_at_by_chat.get(int(chat_id), 0.0))
            wait = cooldown - (now - last)
            if wait > 0:
                return False, wait
            self._last_ask_at_by_chat[int(chat_id)] = now
        return True, 0.0

    def _next_local_approval_id(self, chat_id: int) -> int:
        with self._lock:
            cur = int(self._next_local_approval_id_by_chat.get(int(chat_id), 0)) + 1
            self._next_local_approval_id_by_chat[int(chat_id)] = cur
            return cur

    def _get_pending(self, chat_id: int) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._pending_approvals_by_chat.get(int(chat_id))
            return list(rows) if isinstance(rows, list) else []

    def _set_pending(self, chat_id: int, rows: List[Dict[str, Any]]) -> None:
        with self._lock:
            self._pending_approvals_by_chat[int(chat_id)] = list(rows)

    def _append_pending(self, chat_id: int, row: Dict[str, Any]) -> None:
        with self._lock:
            rows = self._pending_approvals_by_chat.setdefault(int(chat_id), [])
            rows.append(dict(row))

    def _resolve_default_session_id(self, chat_id: int) -> Optional[int]:
        with self._lock:
            sid = self._default_session_by_chat.get(int(chat_id))
        if sid is not None:
            return int(sid)
        db = SessionLocal()
        try:
            row = (
                db.query(SimulationSession)
                .filter(SimulationSession.strategy_id == "_workbench")
                .filter(SimulationSession.status == "active")
                .order_by(SimulationSession.updated_at.desc())
                .first()
            )
            if row is None:
                row = (
                    db.query(SimulationSession)
                    .filter(SimulationSession.strategy_id == "_workbench")
                    .order_by(SimulationSession.updated_at.desc())
                    .first()
                )
            if row is None:
                return None
            sid = int(row.id)
            with self._lock:
                self._default_session_by_chat[int(chat_id)] = sid
            return sid
        finally:
            db.close()

    def _set_default_session(self, chat_id: int, session_id: int) -> None:
        with self._lock:
            self._default_session_by_chat[int(chat_id)] = int(session_id)

    @staticmethod
    def _conversation_name_norm(name_like: Any) -> str:
        raw = str(name_like or "").strip().lower()
        if not raw:
            return "default"
        clean = "".join(ch for ch in raw if ch.isalnum() or ch in {"_", "-"})
        if not clean:
            return "default"
        return clean[:40]

    def _conversation_meta_key(self, chat_id: int, session_id: int) -> Tuple[int, int]:
        return (int(chat_id), int(session_id))

    def _conversation_get_active(self, chat_id: int, session_id: int) -> str:
        key = self._conversation_meta_key(chat_id, session_id)
        with self._lock:
            cur = self._active_conversation_by_chat_session.get(key)
        return self._conversation_name_norm(cur)

    def _conversation_set_active(self, chat_id: int, session_id: int, name: Any) -> str:
        key = self._conversation_meta_key(chat_id, session_id)
        conv = self._conversation_name_norm(name)
        with self._lock:
            self._active_conversation_by_chat_session[key] = conv
        return conv

    def _conversation_list(self, chat_id: int, session_id: int) -> List[str]:
        cid = int(chat_id)
        sid = int(session_id)
        names = {"default"}
        with self._lock:
            for key in list(self._history_by_chat_session.keys()):
                if not isinstance(key, tuple) or len(key) != 3:
                    continue
                if int(key[0]) == cid and int(key[1]) == sid:
                    names.add(self._conversation_name_norm(key[2]))
            active = self._active_conversation_by_chat_session.get((cid, sid))
            if active:
                names.add(self._conversation_name_norm(active))
        return sorted(names)

    def _history_key(self, chat_id: int, session_id: int) -> Tuple[int, int, str]:
        return (
            int(chat_id),
            int(session_id),
            self._conversation_get_active(chat_id, session_id),
        )

    def _watchdog_key(self, chat_id: int, session_id: int) -> Tuple[int, int]:
        return (int(chat_id), int(session_id))

    def _watchdog_cursor_get(self, chat_id: int, session_id: int) -> Optional[int]:
        key = self._watchdog_key(chat_id, session_id)
        with self._lock:
            cur = self._last_watchdog_event_id_by_chat_session.get(key)
        return int(cur) if cur is not None else None

    def _watchdog_cursor_set(self, chat_id: int, session_id: int, event_id: int) -> None:
        key = self._watchdog_key(chat_id, session_id)
        with self._lock:
            self._last_watchdog_event_id_by_chat_session[key] = int(max(0, int(event_id or 0)))

    def _watchdog_should_check_now(self, chat_id: int, session_id: int) -> bool:
        key = self._watchdog_key(chat_id, session_id)
        now_ts = time.time()
        interval = float(self._watchdog_alert_interval_sec())
        with self._lock:
            prev = float(self._last_watchdog_check_at_by_chat_session.get(key, 0.0))
            if prev > 0.0 and (now_ts - prev) < interval:
                return False
            self._last_watchdog_check_at_by_chat_session[key] = now_ts
        return True

    def _history_get(self, chat_id: int, session_id: int) -> List[Dict[str, str]]:
        key = self._history_key(chat_id, session_id)
        with self._lock:
            rows = self._history_by_chat_session.get(key) or []
            return list(rows[-8:])

    def _history_append(self, chat_id: int, session_id: int, role: str, content: str) -> None:
        key = self._history_key(chat_id, session_id)
        row = {
            "role": "user" if str(role).lower() == "user" else "assistant",
            "content": str(content or "")[:800],
        }
        with self._lock:
            buf = self._history_by_chat_session.setdefault(key, [])
            buf.append(row)
            if len(buf) > 20:
                del buf[:-20]

    def _conversation_clear(self, chat_id: int, session_id: int, name: Optional[str] = None) -> int:
        target = self._conversation_name_norm(name or self._conversation_get_active(chat_id, session_id))
        key = (int(chat_id), int(session_id), target)
        with self._lock:
            rows = self._history_by_chat_session.get(key) or []
            n = int(len(rows))
            if key in self._history_by_chat_session:
                del self._history_by_chat_session[key]
        return n

    def _conversation_clear_all(self, chat_id: int, session_id: int) -> int:
        cid = int(chat_id)
        sid = int(session_id)
        removed = 0
        with self._lock:
            to_del = [
                key for key in list(self._history_by_chat_session.keys())
                if isinstance(key, tuple) and len(key) == 3 and int(key[0]) == cid and int(key[1]) == sid
            ]
            for key in to_del:
                rows = self._history_by_chat_session.get(key) or []
                removed += int(len(rows))
                del self._history_by_chat_session[key]
        return removed

    @staticmethod
    def _extract_session_arg(tokens: List[str]) -> Tuple[Optional[int], List[str]]:
        if not tokens:
            return None, tokens
        head = str(tokens[0]).strip()
        if head.isdigit():
            try:
                return int(head), tokens[1:]
            except Exception:
                return None, tokens
        return None, tokens

    def _format_status(self, session_id: int) -> str:
        db = SessionLocal()
        try:
            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session {int(session_id)} not found."
            open_trades = (
                db.query(SimulationTrade)
                .filter(SimulationTrade.session_id == int(session_id))
                .filter(SimulationTrade.status == "open")
                .order_by(SimulationTrade.id.asc())
                .all()
            )
            latest_price = None
            from ..api import simulation_routes as sim_routes
            try:
                state = sim_routes.workbench_agent_state(session_id=int(session_id), include_legacy_aliases=False, db=db)
            except Exception:
                state = {}
            triggers = []
            if isinstance(state, dict):
                triggers = state.get("scheduled_triggers") if isinstance(state.get("scheduled_triggers"), list) else []
                st = state.get("state") if isinstance(state.get("state"), dict) else {}
                snap = st.get("last_snapshot") if isinstance(st.get("last_snapshot"), dict) else {}
                tool_state = snap.get("tool_state") if isinstance(snap.get("tool_state"), dict) else {}
                live_bar = tool_state.get("live_bar") if isinstance(tool_state.get("live_bar"), dict) else {}
                try:
                    latest_price = float(live_bar.get("close"))
                except Exception:
                    latest_price = None
            pending_triggers = [t for t in triggers if str((t or {}).get("status") or "").lower() in {"pending", "pending_approval"}]
            lines = [
                f"Session #{int(session.id)} | {str(session.symbol or '').upper()} {str(session.timeframe or '').upper()}",
                f"Status: {str(session.status or '').upper()} | Balance: {float(session.current_balance or 0.0):.2f} | PnL: {float(session.total_pnl or 0.0):.2f}",
                f"Open trades: {int(len(open_trades))} | Pending triggers: {int(len(pending_triggers))}",
            ]
            if latest_price is not None and math.isfinite(float(latest_price)):
                lines.append(f"Last price: {float(latest_price):.5f}")
            if open_trades:
                head = open_trades[-1]
                lines.append(
                    f"Last open trade: #{int(head.id)} {str(head.direction or '').upper()} @ {float(head.entry_price or 0.0):.5f} "
                    f"SL {float(head.stop_loss or 0.0):.5f} TP {float(head.take_profit or 0.0):.5f}"
                )
            return "\n".join(lines)
        finally:
            db.close()

    def _format_summary(self, session_id: int) -> str:
        db = SessionLocal()
        try:
            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session {int(session_id)} not found."
            from ..api import simulation_routes as sim_routes
            try:
                ctx = sim_routes._agent_default_context(session=session, db=db)
            except Exception:
                ctx = {}
            try:
                snap = sim_routes._agent_execute_tool(
                    session=session,
                    db=db,
                    permissions={"can_chat": True},
                    context_snapshot=ctx if isinstance(ctx, dict) else {},
                    tool_name="get_market_snapshot",
                    args={"bars_limit": 40, "include_bars": False, "include_indicators": True},
                    atomic=False,
                )
            except Exception:
                snap = {"ok": False, "error": "snapshot_failed"}
            data = snap.get("data") if isinstance(snap, dict) and isinstance(snap.get("data"), dict) else {}
            indicators = data.get("indicators") if isinstance(data.get("indicators"), dict) else {}
            price = data.get("current_price")
            trend = str(indicators.get("trend_bias") or "mixed")
            rsi = indicators.get("rsi14")
            atr = indicators.get("atr14")
            open_count = int(data.get("open_positions_count") or 0) if isinstance(data, dict) else 0
            trig_count = int(data.get("pending_triggers_count") or 0) if isinstance(data, dict) else 0
            lines = [
                f"Summary | Session #{int(session.id)} | {str(session.symbol or '').upper()} {str(session.timeframe or '').upper()}",
                f"Balance: {float(session.current_balance or 0.0):.2f} | PnL: {float(session.total_pnl or 0.0):.2f} | Open: {open_count} | Triggers: {trig_count}",
                f"Trend: {trend} | Price: {price} | RSI14: {rsi} | ATR14: {atr}",
            ]
            return "\n".join(lines)
        finally:
            db.close()

    def _format_triggers(self, session_id: int) -> str:
        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes
            out = sim_routes.workbench_agent_triggers_list(session_id=int(session_id), db=db)
            rows = out.get("triggers") if isinstance(out, dict) and isinstance(out.get("triggers"), list) else []
            if not rows:
                return f"Session #{int(session_id)} has no scheduled triggers."
            lines = [f"Session #{int(session_id)} triggers ({len(rows)}):"]
            for r in rows[:8]:
                if not isinstance(r, dict):
                    continue
                tid = str(r.get("id") or "n/a")
                st = str(r.get("status") or "").upper()
                cond = str(r.get("condition") or "")
                px = r.get("trigger_price")
                side = str(r.get("direction") or "").upper()
                tf = str(r.get("timeframe") or "").upper()
                lines.append(f"- {tid} [{st}] {side} {cond} {px} ({tf})")
            return "\n".join(lines)
        finally:
            db.close()

    def _format_runtime(self, session_id: int) -> str:
        db = SessionLocal()
        try:
            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session {int(session_id)} not found."
            provider, perms, _cfg = self._resolve_provider_and_permissions(int(session_id))
            cfg = _json_obj(session.config_json)
            identity = cfg.get("agent_identity") if isinstance(cfg.get("agent_identity"), dict) else {}
            persona = str(identity.get("persona") or "").strip()
            profile = "unknown"
            if "Master trader and quantitative risk manager" in persona:
                profile = "master_quant"
            elif "Apprentice day-trading analyst" in persona:
                profile = "apprentice"
            p = str(provider.get("provider") or "deterministic").strip().lower() or "deterministic"
            model = str(provider.get("model_label") or "").strip() or "default"
            llm_url = str(provider.get("llm_url") or "").strip()
            has_api_key = bool(provider.get("api_key"))
            tool_mode = self._normalize_tool_access_mode((_cfg if isinstance(_cfg, dict) else {}).get("strategy_tool_access_mode"))
            selection_mode = self._normalize_tool_selection_mode((_cfg if isinstance(_cfg, dict) else {}).get("tool_selection_mode"))
            lines = [
                f"Runtime | Session #{int(session.id)} | {str(session.symbol or '').upper()} {str(session.timeframe or '').upper()}",
                f"Provider: {p} | Model: {model}",
                f"LLM URL: {llm_url if llm_url else '(provider default)'}",
                f"API key: {'YES' if has_api_key else 'MISSING'}",
                f"Tool mode: {tool_mode}",
                f"Tool selection: {selection_mode}",
                f"Identity: {profile}",
                (
                    "Perms: "
                    f"chat={bool(perms.get('can_chat', True))} "
                    f"scan={bool(perms.get('can_scan_tools', True))} "
                    f"place={bool(perms.get('can_place_trades', False))} "
                    f"close={bool(perms.get('can_close_trades', False))} "
                    f"confirm={bool(perms.get('requires_user_confirm_for_trade', True))}"
                ),
            ]
            if p == "deterministic":
                lines.append("Note: deterministic provider returns generic planning replies; select claude/openai/local for full reasoning.")
            elif not has_api_key and p in {"claude", "openai_compat"}:
                lines.append(
                    "Warning: API key missing. Add ANTHROPIC_API_KEY/CLAUDE_API_KEY or OPENAI_API_KEY to dashboard/.env."
                )
            return "\n".join(lines)
        finally:
            db.close()

    def _resolve_provider_and_permissions(self, session_id: int) -> Tuple[Dict[str, Any], Dict[str, Any], Dict[str, Any]]:
        db = SessionLocal()
        try:
            # Prefer unified Agent session config/runtime (same control-plane as Workbench agent chat).
            agent_row = (
                db.query(WorkbenchAgentSessionModel)
                .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
                .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                .first()
            )
            if agent_row is None:
                agent_row = (
                    db.query(WorkbenchAgentSessionModel)
                    .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                    .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                    .first()
                )
            if agent_row is not None:
                cfg = _json_obj(agent_row.config_json)
                perms = _json_obj(agent_row.permissions_json)
                if not perms:
                    perms = _json_obj(cfg.get("agent_permissions"))
                provider_name = str(agent_row.provider or "deterministic").strip() or "deterministic"
                provider = {
                    "provider": provider_name,
                    "model_label": str(agent_row.model_label or "").strip() or None,
                    "timeout_sec": 60,
                }
                rt = _json_obj(agent_row.runtime_json)
                llm_url = ""
                api_key = ""
                p = provider_name.lower()
                if p == "local_gptoss_http":
                    llm_url = str(rt.get("local_gptoss_url") or rt.get("llm_url") or "").strip()
                elif p == "openai_compat":
                    llm_url = str(rt.get("openai_base_url") or rt.get("llm_url") or "").strip()
                    api_key = str(rt.get("openai_api_key") or rt.get("api_key") or "").strip()
                elif p == "claude":
                    llm_url = str(rt.get("claude_base_url") or rt.get("llm_url") or "").strip()
                    api_key = str(rt.get("anthropic_api_key") or rt.get("api_key") or "").strip()
                # Env-var fallback: runtime_json often lacks API key because
                # the Workbench UI sends it per-request without persisting it.
                if not api_key and p == "claude":
                    api_key = self._get_env_value("ANTHROPIC_API_KEY")
                    if not api_key:
                        api_key = self._get_env_value("CLAUDE_API_KEY")
                if not api_key and p == "openai_compat":
                    api_key = self._get_env_value("OPENAI_API_KEY")
                if llm_url:
                    provider["llm_url"] = llm_url
                if api_key:
                    provider["api_key"] = api_key
                timeout = rt.get("llm_timeout_sec", rt.get("timeout_sec"))
                try:
                    tsec = int(timeout) if timeout is not None else 60
                except Exception:
                    tsec = 60
                provider["timeout_sec"] = max(10, min(600, tsec))
                if not isinstance(perms, dict) or not perms:
                    perms = {
                        "can_chat": True,
                        "can_scan_tools": True,
                        "can_use_research": False,
                        "can_manage_indicators": True,
                        "can_place_trades": True,
                        "can_close_trades": True,
                        "can_auto_execute": False,
                        "requires_user_confirm_for_trade": True,
                    }
                return provider, perms, (cfg if isinstance(cfg, dict) else {})

            # Backward-compat fallback for older sessions controlled by copilot rows.
            cop = (
                db.query(WorkbenchCopilotSessionModel)
                .filter(WorkbenchCopilotSessionModel.simulation_session_id == int(session_id))
                .order_by(WorkbenchCopilotSessionModel.created_at.desc())
                .first()
            )
            cfg = _json_obj(cop.config_json) if cop is not None else {}
            perms = _json_obj(cfg.get("agent_permissions"))
            cop_provider_name = str(cop.provider or "deterministic") if cop is not None else "deterministic"
            provider = {
                "provider": cop_provider_name,
                "model_label": str(cop.model_label or "").strip() or None if cop is not None else None,
                "timeout_sec": 60,
            }
            if cop is not None:
                from .workbench_copilot_runtime import get_runtime as get_copilot_runtime
                runtime = get_copilot_runtime(int(cop.id))
                if isinstance(runtime, dict):
                    llm_url = str(runtime.get("llm_url") or "").strip()
                    api_key = str(runtime.get("api_key") or "").strip()
                    timeout = runtime.get("timeout_sec")
                    if llm_url:
                        provider["llm_url"] = llm_url
                    if api_key:
                        provider["api_key"] = api_key
                    try:
                        tsec = int(timeout) if timeout is not None else 60
                    except Exception:
                        tsec = 60
                    provider["timeout_sec"] = max(10, min(600, tsec))
            # Env-var fallback for API key (same as agent-session path).
            cp = cop_provider_name.lower()
            if not provider.get("api_key") and cp == "claude":
                ek = self._get_env_value("ANTHROPIC_API_KEY")
                if not ek:
                    ek = self._get_env_value("CLAUDE_API_KEY")
                if ek:
                    provider["api_key"] = ek
            if not provider.get("api_key") and cp == "openai_compat":
                ek = self._get_env_value("OPENAI_API_KEY")
                if ek:
                    provider["api_key"] = ek
            if not isinstance(perms, dict) or not perms:
                perms = {
                    "can_chat": True,
                    "can_scan_tools": True,
                    "can_use_research": False,
                    "can_manage_indicators": True,
                    "can_place_trades": True,
                    "can_close_trades": True,
                    "can_auto_execute": False,
                    "requires_user_confirm_for_trade": True,
                }
            return provider, perms, (cfg if isinstance(cfg, dict) else {})
        finally:
            db.close()

    @staticmethod
    def _resolve_agent_session_id(db, session_id: int) -> Optional[int]:
        row = (
            db.query(WorkbenchAgentSessionModel)
            .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
            .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
            .order_by(WorkbenchAgentSessionModel.updated_at.desc())
            .first()
        )
        if row is None:
            row = (
                db.query(WorkbenchAgentSessionModel)
                .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                .first()
            )
        if row is None:
            return None
        return int(row.id)

    @staticmethod
    def _format_watchdog_event(session: SimulationSession, ev: WorkbenchAgentEventModel) -> str:
        et = str(ev.event_type or "").strip().upper() or "WATCHDOG_EVENT"
        sev = str(ev.severity or "info").strip().lower() or "info"
        payload = ev.payload_json if isinstance(ev.payload_json, dict) else {}
        lines = [
            (
                f"Watchdog alert: {et} ({sev})\n"
                f"Session #{int(getattr(session, 'id', 0) or 0)} "
                f"{str(getattr(session, 'symbol', '') or '').upper()} "
                f"{str(getattr(session, 'timeframe', '') or '').upper()}"
            )
        ]
        trigger_id = str(payload.get("trigger_id") or "").strip()
        if trigger_id:
            lines.append(f"Trigger: {trigger_id}")
        trade_id = payload.get("trade_id")
        if trade_id is None:
            trade_obj = payload.get("trade") if isinstance(payload.get("trade"), dict) else {}
            trade_id = trade_obj.get("id")
        if trade_id is not None:
            lines.append(f"Trade: #{int(trade_id)}")
        cond = str(payload.get("condition") or "").strip()
        if cond:
            lines.append(f"Condition: {cond}")
        trg_px = payload.get("trigger_price")
        if trg_px is not None:
            lines.append(f"Trigger price: {trg_px}")
        hit_px = payload.get("hit_price")
        if hit_px is not None:
            lines.append(f"Hit price: {hit_px}")
        rec = str(payload.get("recommendation") or "").strip()
        if rec:
            lines.append(f"Recommendation: {rec}")
        msg = str(payload.get("message") or payload.get("error") or "").strip()
        if msg:
            lines.append(f"Note: {msg[:220]}")
        if ev.created_at is not None:
            lines.append(f"At: {ev.created_at.isoformat()}")
        return "\n".join(lines)

    def _push_watchdog_alerts(self) -> None:
        if not self._watchdog_alerts_enabled():
            return
        chat_id = self._allowed_chat_id()
        if chat_id is None:
            return
        session_id = self._resolve_default_session_id(int(chat_id))
        if session_id is None:
            return
        if not self._watchdog_should_check_now(int(chat_id), int(session_id)):
            return
        db = SessionLocal()
        try:
            session = db.query(SimulationSession).get(int(session_id))
            if session is None or str(session.strategy_id or "") != "_workbench":
                return
            agent_session_id = self._resolve_agent_session_id(db=db, session_id=int(session_id))
            if agent_session_id is None:
                return
            cursor = self._watchdog_cursor_get(int(chat_id), int(session_id))
            if cursor is None:
                # First run: start at latest to avoid flooding historical backlog.
                max_row = (
                    db.query(WorkbenchAgentEventModel)
                    .filter(WorkbenchAgentEventModel.agent_session_id == int(agent_session_id))
                    .filter(WorkbenchAgentEventModel.event_type.like("WATCHDOG_%"))
                    .order_by(WorkbenchAgentEventModel.id.desc())
                    .first()
                )
                max_event_id = int(max_row.id) if max_row is not None else 0
                self._watchdog_cursor_set(int(chat_id), int(session_id), int(max_event_id))
                return
            allowed = self._watchdog_alert_event_types()
            rows = (
                db.query(WorkbenchAgentEventModel)
                .filter(WorkbenchAgentEventModel.agent_session_id == int(agent_session_id))
                .filter(WorkbenchAgentEventModel.id > int(cursor))
                .filter(WorkbenchAgentEventModel.event_type.like("WATCHDOG_%"))
                .order_by(WorkbenchAgentEventModel.id.asc())
                .limit(int(self._watchdog_alert_max_events()))
                .all()
            )
            if not rows:
                return
            last_id = int(cursor)
            for ev in rows:
                last_id = max(last_id, int(ev.id))
                et = str(ev.event_type or "").strip().upper()
                if isinstance(allowed, set) and len(allowed) > 0 and et not in allowed:
                    continue
                self._send_text(int(chat_id), self._format_watchdog_event(session, ev))
            self._watchdog_cursor_set(int(chat_id), int(session_id), int(last_id))
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _extract_pending_from_tool_calls(self, chat_id: int, session_id: int, tool_calls: Any) -> List[Dict[str, Any]]:
        rows: List[Dict[str, Any]] = []
        calls = tool_calls if isinstance(tool_calls, list) else []
        for tc in calls:
            if not isinstance(tc, dict):
                continue
            result = tc.get("result") if isinstance(tc.get("result"), dict) else {}
            if not isinstance(result, dict) or result.get("requires_confirmation") is not True:
                continue
            pending = result.get("pending_action") if isinstance(result.get("pending_action"), dict) else {}
            tool = str(pending.get("tool") or tc.get("tool_id") or "").strip().lower()
            args = pending.get("args") if isinstance(pending.get("args"), dict) else {}
            if tool not in {"place_trade", "close_trade"}:
                continue
            local_id = self._next_local_approval_id(chat_id)
            row = {
                "id": int(local_id),
                "session_id": int(session_id),
                "tool": tool,
                "args": dict(args),
                "message": str(pending.get("message") or result.get("error") or "Action requires approval."),
                "created_at": self._now_iso(),
            }
            rows.append(row)
        for r in rows:
            self._append_pending(chat_id, r)
        return rows

    def _run_agent_chat(self, chat_id: int, session_id: int, text: str) -> str:
        provider_cfg, perms_cfg, tool_cfg = self._resolve_provider_and_permissions(session_id)
        req_cfg = dict(tool_cfg) if isinstance(tool_cfg, dict) else {}
        req_cfg["telegram_bridge"] = True
        from ..api import simulation_routes as sim_routes
        req = sim_routes.AgentChatRequest(
            provider=sim_routes.AgentProviderConfig.model_validate(provider_cfg),
            permissions=sim_routes.AgentPermissionConfig.model_validate(perms_cfg),
            config=req_cfg,
            message=str(text or ""),
            conversation_history=self._history_get(chat_id, session_id),
            context_snapshot=sim_routes.AgentContextSnapshot(),
            allow_tools=True,
            max_tool_steps=int(self._agent_max_tool_steps()),
        )
        db = SessionLocal()
        try:
            out = sim_routes.workbench_agent_chat(session_id=int(session_id), req=req, db=db)
        finally:
            try:
                db.close()
            except Exception:
                pass
        payload = out.model_dump() if hasattr(out, "model_dump") else (dict(out) if isinstance(out, dict) else {})
        reply = str(payload.get("message") or payload.get("reply") or "").strip()
        if not reply:
            reply = "No assistant reply text generated."
        pending = self._extract_pending_from_tool_calls(chat_id, session_id, payload.get("tool_calls"))
        if pending:
            lines = ["", f"Pending approvals: {len(pending)}"]
            for p in pending:
                tool = str(p.get("tool") or "")
                args = p.get("args") if isinstance(p.get("args"), dict) else {}
                if tool == "place_trade":
                    lines.append(
                        f"- #{int(p.get('id'))}: place_trade {str(args.get('direction') or '').upper()} "
                        f"SL={args.get('stop_loss')} TP={args.get('take_profit')} lot={args.get('lot_size')}"
                    )
                elif tool == "close_trade":
                    lines.append(f"- #{int(p.get('id'))}: close_trade trade_id={args.get('trade_id')}")
            lines.append("Use /approve <id> or /cancel <id>")
            reply = f"{reply}\n" + "\n".join(lines)
        self._history_append(chat_id, session_id, "user", text)
        self._history_append(chat_id, session_id, "assistant", reply)
        return reply

    def _execute_pending_approval(self, chat_id: int, local_id: int) -> str:
        rows = self._get_pending(chat_id)
        idx = -1
        row: Optional[Dict[str, Any]] = None
        for i, r in enumerate(rows):
            if int(r.get("id") or 0) == int(local_id):
                idx = i
                row = r
                break
        if idx < 0 or row is None:
            return f"Pending approval #{int(local_id)} not found."
        tool = str(row.get("tool") or "").lower()
        args = row.get("args") if isinstance(row.get("args"), dict) else {}
        session_id = int(row.get("session_id") or 0)
        if session_id <= 0:
            return "Invalid pending approval payload (missing session_id)."
        from ..api import simulation_routes as sim_routes
        db = SessionLocal()
        try:
            if tool not in {"place_trade", "close_trade"}:
                return f"Unsupported approval tool: {tool}"
            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session #{int(session_id)} not found."
            _provider_cfg, perms_cfg, _tool_cfg = self._resolve_provider_and_permissions(int(session_id))
            approved_perms = dict(perms_cfg if isinstance(perms_cfg, dict) else {})
            approved_perms["can_place_trades"] = True
            approved_perms["can_close_trades"] = True
            approved_perms["requires_user_confirm_for_trade"] = False
            # Keep approval path decoupled from private context builders.
            # Guardrails for place/close trade rely on session + policy; this minimal
            # context is sufficient and stable across internal refactors.
            ctx = {
                "session": {
                    "id": int(getattr(session, "id", 0) or 0),
                    "symbol": str(getattr(session, "symbol", "") or ""),
                    "timeframe": str(getattr(session, "timeframe", "") or ""),
                    "current_bar": int(getattr(session, "current_bar", 0) or 0),
                    "total_bars": int(getattr(session, "total_bars", 0) or 0),
                }
            }
            res = sim_routes._agent_execute_tool(
                session=session,
                db=db,
                permissions=approved_perms,
                context_snapshot=ctx,
                tool_name=str(tool),
                args=dict(args),
                atomic=False,
            )
            if bool(res.get("ok")):
                data = res.get("data") if isinstance(res.get("data"), dict) else {}
                if tool == "place_trade":
                    msg = f"Approved and executed: {str(data.get('direction') or '').upper()} trade (id={data.get('id')})."
                else:
                    tid = int(args.get("trade_id") or 0)
                    msg = f"Approved and executed: close trade #{int(data.get('id') or tid)}."
            elif bool(res.get("requires_confirmation")):
                msg = "Approval execution blocked: still requires confirmation in policy path."
            else:
                err = str(res.get("error") or "execution_failed")
                # Keep pending for retrial except stale close-trade rows.
                if tool == "close_trade" and err in {"trade_not_open_or_not_found"}:
                    rows.pop(idx)
                    self._set_pending(chat_id, rows)
                    return f"Close request resolved: trade no longer open ({err})."
                return f"Approval execution failed: {err}"
        except HTTPException as exc:
            msg = f"Approval execution failed: {str(exc.detail)}"
        except Exception as exc:
            msg = f"Approval execution failed: {type(exc).__name__}: {str(exc)[:180]}"
        finally:
            try:
                db.close()
            except Exception:
                pass
        rows.pop(idx)
        self._set_pending(chat_id, rows)
        return msg

    def _cancel_pending_approval(self, chat_id: int, local_id: int) -> str:
        rows = self._get_pending(chat_id)
        idx = -1
        for i, r in enumerate(rows):
            if int(r.get("id") or 0) == int(local_id):
                idx = i
                break
        if idx < 0:
            return f"Pending approval #{int(local_id)} not found."
        rows.pop(idx)
        self._set_pending(chat_id, rows)
        return f"Pending approval #{int(local_id)} canceled."

    def _set_identity_profile(self, session_id: int, profile_raw: Any) -> str:
        profile = str(profile_raw or "").strip().lower()
        if profile in {"master", "master_quant", "quant", "pro"}:
            profile = "master_quant"
        elif profile in {"apprentice", "junior"}:
            profile = "apprentice"
        else:
            return "Usage: /identity master|apprentice [session_id]"
        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes

            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session #{int(session_id)} not found."
            if str(session.strategy_id or "") != "_workbench":
                return f"Session #{int(session_id)} is not a Workbench session."
            ctx = sim_routes._agent_default_context(session=session, db=db)
            out = sim_routes._agent_execute_tool(
                session=session,
                db=db,
                permissions={"can_chat": True},
                context_snapshot=ctx if isinstance(ctx, dict) else {},
                tool_name="set_agent_personality",
                args={"profile": profile},
                atomic=False,
            )
            if not isinstance(out, dict) or not bool(out.get("ok")):
                db.rollback()
                err = str((out or {}).get("error") if isinstance(out, dict) else "identity_switch_failed")
                return f"Identity update failed: {err}"
            db.commit()
            data = out.get("data") if isinstance(out.get("data"), dict) else {}
            effective = str(data.get("profile") or profile)
            return f"Identity set to {effective} for session #{int(session_id)}."
        except Exception as exc:
            db.rollback()
            return f"Identity update failed: {type(exc).__name__}: {str(exc)[:180]}"
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _set_tool_access_mode(self, session_id: int, mode_raw: Any) -> str:
        mode = self._normalize_tool_access_mode(mode_raw)
        raw = str(mode_raw or "").strip().lower()
        if raw and raw not in {"all", "parent", "child", "parents", "children", "childs", "collected", "aggregate", "aggregated", "master", "granular", "detailed"}:
            return "Usage: /toolmode <all|parent|child> [session_id]"
        db = SessionLocal()
        try:
            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session #{int(session_id)} not found."
            if str(session.strategy_id or "") != "_workbench":
                return f"Session #{int(session_id)} is not a Workbench session."

            row = (
                db.query(WorkbenchAgentSessionModel)
                .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
                .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                .first()
            )
            if row is None:
                row = (
                    db.query(WorkbenchAgentSessionModel)
                    .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                    .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                    .first()
                )
            if row is None:
                row = WorkbenchAgentSessionModel(
                    simulation_session_id=int(session_id),
                    mode="CHAT",
                    status="ACTIVE",
                    provider="deterministic",
                    model_label=None,
                    permissions_json={
                        "can_chat": True,
                        "can_scan_tools": True,
                        "can_use_research": False,
                        "can_manage_indicators": True,
                        "can_place_trades": True,
                        "can_close_trades": True,
                        "can_auto_execute": False,
                        "requires_user_confirm_for_trade": True,
                    },
                    config_json={},
                    runtime_json={},
                    last_snapshot_json={},
                    created_at=datetime.utcnow(),
                    updated_at=datetime.utcnow(),
                )
                db.add(row)
                db.flush()

            cfg = _json_obj(row.config_json)
            cfg["strategy_tool_access_mode"] = mode
            row.config_json = cfg
            row.updated_at = datetime.utcnow()
            db.add(row)
            db.commit()
            return f"Strategy tool access mode set to '{mode}' for session #{int(session_id)}."
        except Exception as exc:
            db.rollback()
            return f"Tool mode update failed: {type(exc).__name__}: {str(exc)[:180]}"
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _set_tool_selection_mode(self, session_id: int, mode_raw: Any) -> str:
        mode = self._normalize_tool_selection_mode(mode_raw)
        raw = str(mode_raw or "").strip().lower()
        if raw and raw not in {
            "autonomous",
            "guided",
            "minimal",
            "auto",
            "full",
            "all_tools",
            "default",
            "intent",
            "intent_history",
            "guided_intent",
            "min",
            "least",
            "strict_minimal",
        }:
            return "Usage: /toolselect <autonomous|guided|minimal> [session_id]"
        db = SessionLocal()
        try:
            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session #{int(session_id)} not found."
            if str(session.strategy_id or "") != "_workbench":
                return f"Session #{int(session_id)} is not a Workbench session."

            row = (
                db.query(WorkbenchAgentSessionModel)
                .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
                .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                .first()
            )
            if row is None:
                row = (
                    db.query(WorkbenchAgentSessionModel)
                    .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                    .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                    .first()
                )
            if row is None:
                row = WorkbenchAgentSessionModel(
                    simulation_session_id=int(session_id),
                    mode="CHAT",
                    status="ACTIVE",
                    provider="deterministic",
                    model_label=None,
                    permissions_json={
                        "can_chat": True,
                        "can_scan_tools": True,
                        "can_use_research": False,
                        "can_manage_indicators": True,
                        "can_place_trades": True,
                        "can_close_trades": True,
                        "can_auto_execute": False,
                        "requires_user_confirm_for_trade": True,
                    },
                    config_json={},
                    runtime_json={},
                    last_snapshot_json={},
                    created_at=datetime.utcnow(),
                    updated_at=datetime.utcnow(),
                )
                db.add(row)
                db.flush()

            cfg = _json_obj(row.config_json)
            cfg["tool_selection_mode"] = mode
            row.config_json = cfg
            row.updated_at = datetime.utcnow()
            db.add(row)
            db.commit()
            return f"Tool selection mode set to '{mode}' for session #{int(session_id)}."
        except Exception as exc:
            db.rollback()
            return f"Tool selection update failed: {type(exc).__name__}: {str(exc)[:180]}"
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _set_provider_profile(
        self,
        session_id: int,
        provider_raw: Any,
        model_label: Optional[str] = None,
        llm_url: Optional[str] = None,
        api_key: Optional[str] = None,
    ) -> str:
        provider = str(provider_raw or "").strip().lower()
        allowed = {"deterministic", "claude", "openai_compat", "local_gptoss_http"}
        if provider not in allowed:
            return "Usage: /provider set <deterministic|claude|openai_compat|local_gptoss_http> [model] [url] [api_key] [session_id]"
        defaults = {
            "deterministic": {"model": None, "url": None},
            "claude": {"model": "claude-haiku-4-5-20251001", "url": "https://api.anthropic.com"},
            "openai_compat": {"model": "gpt-4.1-mini", "url": "https://api.openai.com/v1"},
            "local_gptoss_http": {"model": "gpt-oss-20b", "url": "http://127.0.0.1:8012"},
        }
        db = SessionLocal()
        try:
            session = db.query(SimulationSession).get(int(session_id))
            if session is None:
                return f"Session #{int(session_id)} not found."
            if str(session.strategy_id or "") != "_workbench":
                return f"Session #{int(session_id)} is not a Workbench session."

            row = (
                db.query(WorkbenchAgentSessionModel)
                .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
                .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                .first()
            )
            if row is None:
                row = (
                    db.query(WorkbenchAgentSessionModel)
                    .filter(WorkbenchAgentSessionModel.simulation_session_id == int(session_id))
                    .order_by(WorkbenchAgentSessionModel.updated_at.desc())
                    .first()
                )
            if row is None:
                row = WorkbenchAgentSessionModel(
                    simulation_session_id=int(session_id),
                    mode="CHAT",
                    status="ACTIVE",
                    provider="deterministic",
                    model_label=None,
                    permissions_json={
                        "can_chat": True,
                        "can_scan_tools": True,
                        "can_use_research": False,
                        "can_manage_indicators": True,
                        "can_place_trades": True,
                        "can_close_trades": True,
                        "can_auto_execute": False,
                        "requires_user_confirm_for_trade": True,
                    },
                    config_json={},
                    runtime_json={},
                    last_snapshot_json={},
                    created_at=datetime.utcnow(),
                    updated_at=datetime.utcnow(),
                )
                db.add(row)
                db.flush()

            model = str(model_label or "").strip() or defaults[provider]["model"]
            url = str(llm_url or "").strip() or defaults[provider]["url"]
            key = str(api_key or "").strip()
            runtime = _json_obj(row.runtime_json)
            # Reset provider-specific auth/url keys to avoid stale cross-provider carry-over.
            for k in (
                "api_key",
                "anthropic_api_key",
                "openai_api_key",
                "claude_base_url",
                "openai_base_url",
                "local_gptoss_url",
            ):
                runtime.pop(k, None)
            if provider == "claude":
                runtime["claude_base_url"] = str(url or defaults["claude"]["url"])
                runtime["llm_url"] = str(url or defaults["claude"]["url"])
                if key:
                    runtime["anthropic_api_key"] = key
                    runtime["api_key"] = key
            elif provider == "openai_compat":
                runtime["openai_base_url"] = str(url or defaults["openai_compat"]["url"])
                runtime["llm_url"] = str(url or defaults["openai_compat"]["url"])
                if key:
                    runtime["openai_api_key"] = key
                    runtime["api_key"] = key
            elif provider == "local_gptoss_http":
                runtime["local_gptoss_url"] = str(url or defaults["local_gptoss_http"]["url"])
                runtime["llm_url"] = str(url or defaults["local_gptoss_http"]["url"])
            else:
                runtime = {}
                model = None

            row.provider = provider
            row.model_label = (str(model).strip() if model is not None else None) or None
            row.runtime_json = runtime
            row.updated_at = datetime.utcnow()
            db.add(row)
            db.commit()
            shown_url = str(url or "").strip() or "(provider default)"
            return (
                f"Provider set for session #{int(session_id)}.\n"
                f"Provider: {provider}\n"
                f"Model: {str(row.model_label or '') or 'default'}\n"
                f"LLM URL: {shown_url}"
            )
        except Exception as exc:
            db.rollback()
            return f"Provider update failed: {type(exc).__name__}: {str(exc)[:180]}"
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _format_latest_session(self, chat_id: int) -> str:
        db = SessionLocal()
        try:
            row = (
                db.query(SimulationSession)
                .filter(SimulationSession.strategy_id == "_workbench")
                .filter(SimulationSession.status == "active")
                .order_by(SimulationSession.updated_at.desc())
                .first()
            )
            if row is None:
                row = (
                    db.query(SimulationSession)
                    .filter(SimulationSession.strategy_id == "_workbench")
                    .order_by(SimulationSession.updated_at.desc())
                    .first()
                )
            if row is None:
                return "No Workbench session found."
            sid = int(row.id)
            default_sid = self._resolve_default_session_id(int(chat_id))
            updated = str(getattr(row, "updated_at", "") or "")
            is_default = (default_sid is not None and int(default_sid) == sid)
            lines = [
                f"Latest Workbench session: #{sid}",
                f"Symbol/TF: {str(row.symbol or '').upper()} {str(row.timeframe or '').upper()}",
                f"Status: {str(row.status or '').upper()}",
                f"Updated: {updated}",
                f"Default: {'YES' if is_default else 'NO'}",
                f"Use it: /use {sid}",
            ]
            return "\n".join(lines)
        finally:
            db.close()

    def _handle_text(self, chat_id: int, text: str) -> str:
        raw = str(text or "").strip()
        if not raw:
            return "Empty message."
        parts = raw.split()
        cmd = str(parts[0] or "").strip()
        if "@" in cmd:
            cmd = cmd.split("@", 1)[0]
        cmd_l = cmd.lower()
        args = parts[1:]

        if cmd_l in {"/start", "/help"}:
            return (
                "NexusTrader Telegram Commands\n\n"
                "/botprofile\n"
                "- Purpose: Show active Telegram bot profile (system-wide) and env resolution order.\n"
                "- Params: none\n"
                "- Example: /botprofile\n\n"
                "/latest\n"
                "- Purpose: Show latest active Workbench session.\n"
                "- Params: none\n"
                "- Example: /latest\n\n"
                "/use <session_id>\n"
                "- Purpose: Set default session for all commands.\n"
                "- Params: session_id (required)\n"
                "- Example: /use 97\n\n"
                "/status [session_id]\n"
                "- Purpose: Balance, PnL, open trades, pending triggers, last price.\n"
                "- Params: optional session_id (uses default if omitted)\n"
                "- Example: /status or /status 97\n\n"
                "/summary [session_id]\n"
                "- Purpose: Compact market/indicator/session snapshot.\n"
                "- Params: optional session_id\n"
                "- Example: /summary\n\n"
                "/runtime [session_id]\n"
                "- Purpose: Show provider/model/url, identity profile, permissions.\n"
                "- Params: optional session_id\n"
                "- Example: /runtime\n\n"
                "/provider [session_id]\n"
                "- Purpose: Alias of runtime (show current provider details).\n"
                "- Params: optional session_id\n"
                "- Example: /provider\n\n"
                "/provider set <provider> [model] [url] [api_key] [session_id]\n"
                "- Purpose: Persist provider/runtime so Telegram /ask uses real LLM.\n"
                "- Params: provider required; model/url/api_key/session_id optional\n"
                "- Example: /provider set claude claude-haiku-4-5-20251001 https://api.anthropic.com - 97\n\n"
                "/triggers [session_id]\n"
                "- Purpose: List scheduled triggers and statuses.\n"
                "- Params: optional session_id\n"
                "- Example: /triggers\n\n"
                "/identity master|apprentice [session_id]\n"
                "- Purpose: Switch agent personality preset.\n"
                "- Params: profile (required), optional session_id\n"
                "- Example: /identity master\n\n"
                "/toolmode [all|parent|child] [session_id]\n"
                "- Purpose: Choose strategy tool mode (all=parent+child, parent=collected tool, child=granular tools).\n"
                "- Params: optional mode, optional session_id\n"
                "- Example: /toolmode parent\n\n"
                "/toolselect [autonomous|guided|minimal] [session_id]\n"
                "- Purpose: Choose tool-selection policy (autonomous=LLM decides, guided=intent-aware prune, minimal=core tools only).\n"
                "- Params: optional mode, optional session_id\n"
                "- Example: /toolselect guided\n\n"
                "/convo list\n"
                "- Purpose: List available Telegram conversation slots for current session.\n"
                "- Params: none\n"
                "- Example: /convo list\n\n"
                "/convo use <name>\n"
                "- Purpose: Switch Telegram chat history slot for current session.\n"
                "- Params: name (required)\n"
                "- Example: /convo use fvg_h4\n\n"
                "/convo clear [name]\n"
                "- Purpose: Clear one conversation slot (active slot if name omitted).\n"
                "- Params: optional name\n"
                "- Example: /convo clear or /convo clear fvg_h4\n\n"
                "/convo reset\n"
                "- Purpose: Clear all conversation slots for current session.\n"
                "- Params: none\n"
                "- Example: /convo reset\n\n"
                "/ask <message>\n"
                "- Purpose: Send explicit agent prompt.\n"
                "- Params: message (required)\n"
                "- Example: /ask Run HTF/LTF FVG scan and propose one trigger.\n\n"
                "/approve <pending_id>\n"
                "- Purpose: Approve pending trade/action created by agent.\n"
                "- Params: pending_id (required)\n"
                "- Example: /approve 1\n\n"
                "/cancel <pending_id>\n"
                "- Purpose: Cancel one pending approval request.\n"
                "- Params: pending_id (required)\n"
                "- Example: /cancel 1\n\n"
                "Tip: Non-command text is treated as /ask."
            )

        if cmd_l in {"/botprofile", "/bot"}:
            return self._format_botprofile()

        if cmd_l in {"/latest", "/latestsession"}:
            return self._format_latest_session(chat_id)

        if cmd_l == "/use":
            if not args or not str(args[0]).isdigit():
                return "Usage: /use <session_id>"
            sid = int(args[0])
            db = SessionLocal()
            try:
                row = db.query(SimulationSession).get(int(sid))
                if row is None:
                    return f"Session #{int(sid)} not found."
                if str(row.strategy_id or "") != "_workbench":
                    return f"Session #{int(sid)} is not a Workbench session."
                self._set_default_session(chat_id, sid)
                return f"Default session set to #{int(sid)} ({str(row.symbol or '').upper()} {str(row.timeframe or '').upper()})."
            finally:
                db.close()

        if cmd_l == "/provider":
            sid_default = self._resolve_default_session_id(chat_id)
            if sid_default is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            if not args:
                return self._format_runtime(int(sid_default))
            if len(args) == 1 and str(args[0]).isdigit():
                return self._format_runtime(int(args[0]))
            tokens = list(args)
            if str(tokens[0] or "").strip().lower() == "set":
                tokens = tokens[1:]
            if not tokens:
                return "Usage: /provider set <deterministic|claude|openai_compat|local_gptoss_http> [model] [url] [api_key] [session_id]"
            target_sid = int(sid_default)
            if str(tokens[-1]).isdigit():
                target_sid = int(tokens.pop())
            provider = str(tokens[0] or "").strip().lower()
            if provider in {"runtime", "show"}:
                return self._format_runtime(int(target_sid))
            model = str(tokens[1]).strip() if len(tokens) >= 2 and str(tokens[1]).strip() not in {"", "-"} else None
            url = str(tokens[2]).strip() if len(tokens) >= 3 and str(tokens[2]).strip() not in {"", "-"} else None
            key = str(tokens[3]).strip() if len(tokens) >= 4 and str(tokens[3]).strip() not in {"", "-"} else None
            return self._set_provider_profile(
                session_id=int(target_sid),
                provider_raw=provider,
                model_label=model,
                llm_url=url,
                api_key=key,
            )

        if cmd_l in {"/status", "/summary", "/runtime", "/triggers"}:
            sid_arg, _rest = self._extract_session_arg(args)
            sid = sid_arg if sid_arg is not None else self._resolve_default_session_id(chat_id)
            if sid is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            if cmd_l == "/triggers":
                return self._format_triggers(int(sid))
            if cmd_l == "/runtime":
                return self._format_runtime(int(sid))
            if cmd_l == "/summary":
                return self._format_summary(int(sid))
            return self._format_status(int(sid))

        if cmd_l == "/identity":
            sid = self._resolve_default_session_id(chat_id)
            if sid is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            if not args:
                rt = self._format_runtime(int(sid))
                line = next((x for x in str(rt).splitlines() if str(x).startswith("Identity: ")), "Identity: unknown")
                return f"{line}\nUsage: /identity master|apprentice [session_id]"
            profile = str(args[0] or "").strip()
            target_sid = int(sid)
            if len(args) >= 2 and str(args[1]).isdigit():
                target_sid = int(args[1])
            return self._set_identity_profile(target_sid, profile)

        if cmd_l == "/toolmode":
            sid = self._resolve_default_session_id(chat_id)
            if sid is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            if not args:
                _provider, _perms, cfg = self._resolve_provider_and_permissions(int(sid))
                mode = self._normalize_tool_access_mode((cfg if isinstance(cfg, dict) else {}).get("strategy_tool_access_mode"))
                return (
                    f"Session #{int(sid)} strategy tool mode: {mode}\n"
                    "Usage: /toolmode <all|parent|child> [session_id]"
                )
            mode_raw = str(args[0] or "").strip().lower()
            target_sid = int(sid)
            if mode_raw in {"show", "status"}:
                if len(args) >= 2 and str(args[1]).isdigit():
                    target_sid = int(args[1])
                    _provider, _perms, cfg = self._resolve_provider_and_permissions(int(target_sid))
                mode = self._normalize_tool_access_mode((cfg if isinstance(cfg, dict) else {}).get("strategy_tool_access_mode"))
                return f"Session #{int(target_sid)} strategy tool mode: {mode}"
            if mode_raw.isdigit():
                target_sid = int(mode_raw)
                _provider, _perms, cfg = self._resolve_provider_and_permissions(int(target_sid))
                mode = self._normalize_tool_access_mode((cfg if isinstance(cfg, dict) else {}).get("strategy_tool_access_mode"))
                return f"Session #{int(target_sid)} strategy tool mode: {mode}"
            if len(args) >= 2 and str(args[1]).isdigit():
                target_sid = int(args[1])
            return self._set_tool_access_mode(target_sid, mode_raw)

        if cmd_l in {"/toolselect", "/toolselection"}:
            sid = self._resolve_default_session_id(chat_id)
            if sid is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            if not args:
                _provider, _perms, cfg = self._resolve_provider_and_permissions(int(sid))
                mode = self._normalize_tool_selection_mode((cfg if isinstance(cfg, dict) else {}).get("tool_selection_mode"))
                return (
                    f"Session #{int(sid)} tool selection mode: {mode}\n"
                    "Usage: /toolselect <autonomous|guided|minimal> [session_id]"
                )
            mode_raw = str(args[0] or "").strip().lower()
            target_sid = int(sid)
            if mode_raw in {"show", "status"}:
                if len(args) >= 2 and str(args[1]).isdigit():
                    target_sid = int(args[1])
                    _provider, _perms, cfg = self._resolve_provider_and_permissions(int(target_sid))
                mode = self._normalize_tool_selection_mode((cfg if isinstance(cfg, dict) else {}).get("tool_selection_mode"))
                return f"Session #{int(target_sid)} tool selection mode: {mode}"
            if mode_raw.isdigit():
                target_sid = int(mode_raw)
                _provider, _perms, cfg = self._resolve_provider_and_permissions(int(target_sid))
                mode = self._normalize_tool_selection_mode((cfg if isinstance(cfg, dict) else {}).get("tool_selection_mode"))
                return f"Session #{int(target_sid)} tool selection mode: {mode}"
            if len(args) >= 2 and str(args[1]).isdigit():
                target_sid = int(args[1])
            return self._set_tool_selection_mode(target_sid, mode_raw)

        if cmd_l == "/convo":
            sid = self._resolve_default_session_id(chat_id)
            if sid is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            if not args:
                active = self._conversation_get_active(chat_id, int(sid))
                names = self._conversation_list(chat_id, int(sid))
                return (
                    f"Conversation active: {active}\n"
                    f"Available: {', '.join(names)}\n"
                    "Usage: /convo list | /convo use <name> | /convo clear [name] | /convo reset"
                )
            sub = str(args[0] or "").strip().lower()
            if sub == "list":
                active = self._conversation_get_active(chat_id, int(sid))
                names = self._conversation_list(chat_id, int(sid))
                return f"Conversation active: {active}\nAvailable: {', '.join(names)}"
            if sub == "use":
                if len(args) < 2:
                    return "Usage: /convo use <name>"
                name = self._conversation_set_active(chat_id, int(sid), args[1])
                return f"Conversation switched to '{name}' for session #{int(sid)}."
            if sub == "clear":
                target = args[1] if len(args) >= 2 else None
                name = self._conversation_name_norm(target or self._conversation_get_active(chat_id, int(sid)))
                n = self._conversation_clear(chat_id, int(sid), target)
                return f"Conversation '{name}' cleared ({int(n)} message(s) removed)."
            if sub in {"reset", "clearall", "clear_all"}:
                n = self._conversation_clear_all(chat_id, int(sid))
                self._conversation_set_active(chat_id, int(sid), "default")
                return f"All conversation histories cleared for session #{int(sid)} ({int(n)} message(s) removed). Active=default."
            return "Usage: /convo list | /convo use <name> | /convo clear [name] | /convo reset"

        if cmd_l == "/ask":
            ask_text = raw[len(parts[0]) :].strip() if parts else ""
            if not ask_text:
                return "Usage: /ask <message>"
            ok, wait = self._can_run_ask(chat_id)
            if not ok:
                return f"Please wait {max(1, int(math.ceil(wait)))}s before the next /ask."
            sid = self._resolve_default_session_id(chat_id)
            if sid is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            return self._run_agent_chat(chat_id, int(sid), ask_text)

        if cmd_l == "/approve":
            if not args or not str(args[0]).isdigit():
                return "Usage: /approve <pending_id>"
            return self._execute_pending_approval(chat_id, int(args[0]))

        if cmd_l == "/cancel":
            if not args or not str(args[0]).isdigit():
                return "Usage: /cancel <pending_id>"
            return self._cancel_pending_approval(chat_id, int(args[0]))

        # Default behavior: treat non-command text as /ask
        sid = self._resolve_default_session_id(chat_id)
        if sid is None:
            return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
        ok, wait = self._can_run_ask(chat_id)
        if not ok:
            return f"Please wait {max(1, int(math.ceil(wait)))}s before the next message."
        return self._run_agent_chat(chat_id, int(sid), raw)

    def _process_update(self, upd: Dict[str, Any]) -> None:
        if not isinstance(upd, dict):
            return
        msg = upd.get("message") if isinstance(upd.get("message"), dict) else None
        if msg is None:
            return
        chat = msg.get("chat") if isinstance(msg.get("chat"), dict) else {}
        chat_id = int(chat.get("id") or 0) if chat.get("id") is not None else 0
        if chat_id <= 0:
            return
        allowed = self._allowed_chat_id()
        if allowed is not None and int(chat_id) != int(allowed):
            logger.warning("telegram unauthorized chat_id=%s ignored", int(chat_id))
            return
        text = str(msg.get("text") or "").strip()
        if not text:
            return
        try:
            reply = self._handle_text(chat_id, text)
        except Exception as exc:
            logger.exception("telegram command handling failed")
            reply = f"Command failed: {type(exc).__name__}: {str(exc)[:180]}"
        self._send_text(chat_id, reply)

    def _poll_once(self) -> None:
        timeout = max(1.0, min(25.0, self._poll_interval_sec()))
        params = {
            "timeout": int(timeout),
            "offset": int(self._offset),
            "allowed_updates": '["message"]',
        }
        body = self._tg_request("getUpdates", params=params, timeout_sec=timeout + 10.0)
        rows = body.get("result") if isinstance(body.get("result"), list) else []
        for row in rows:
            if not isinstance(row, dict):
                continue
            try:
                uid = int(row.get("update_id"))
                self._offset = max(self._offset, uid + 1)
            except Exception:
                pass
            self._process_update(row)

    def _prepare_polling(self) -> None:
        """
        Prepare Telegram endpoint for long-polling mode.

        If a webhook is configured on the token, Telegram rejects getUpdates with
        conflict errors. We explicitly clear webhook to make polling reliable.
        """
        try:
            self._tg_request(
                "deleteWebhook",
                params={"drop_pending_updates": False},
                timeout_sec=15.0,
                http_method="POST",
            )
            logger.info("Telegram polling bootstrap: webhook cleared")
        except Exception as exc:
            logger.warning("Telegram polling bootstrap failed (deleteWebhook): %s", str(exc)[:220])
        try:
            me = self._tg_request("getMe", timeout_sec=15.0, http_method="GET")
            result = me.get("result") if isinstance(me.get("result"), dict) else {}
            uname = str(result.get("username") or "").strip()
            bid = result.get("id")
            logger.info("Telegram polling bootstrap: bot=%s id=%s", (f"@{uname}" if uname else "(unknown)"), str(bid or ""))
        except Exception as exc:
            logger.warning("Telegram polling bootstrap failed (getMe): %s", str(exc)[:220])

    def _loop(self) -> None:
        logger.info("Telegram bridge service loop started")
        while not self._stop.is_set():
            try:
                self._poll_once()
            except Exception as exc:
                logger.warning("Telegram bridge poll failed: %s", str(exc)[:220])
                # Backoff on transient Telegram API failures.
                self._stop.wait(max(1.0, self._poll_interval_sec()))
                continue
            try:
                self._push_watchdog_alerts()
            except Exception as exc:
                logger.warning("Telegram watchdog push failed: %s", str(exc)[:220])
        logger.info("Telegram bridge service loop stopped")

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        if not self._enabled():
            logger.info("Telegram bridge disabled (TELEGRAM_ENABLED=0)")
            return
        token = self._token()
        allowed = self._allowed_chat_id()
        profile = self._active_profile()
        if not token:
            scoped = self._profile_scoped_key("TELEGRAM_BOT_TOKEN", profile)
            logger.warning(
                "Telegram bridge not started: TELEGRAM_BOT_TOKEN missing (profile=%s, scoped_key=%s)",
                str(profile),
                str(scoped or "none"),
            )
            return
        if allowed is None:
            scoped = self._profile_scoped_key("TELEGRAM_ALLOWED_CHAT_ID", profile)
            logger.warning(
                "Telegram bridge not started: TELEGRAM_ALLOWED_CHAT_ID missing/invalid (profile=%s, scoped_key=%s)",
                str(profile),
                str(scoped or "none"),
            )
            return
        self._prepare_polling()
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True, name="telegram-bridge")
        self._thread.start()
        logger.info(
            "Telegram bridge service started (profile=%s, allowed_chat_id=%s)",
            str(profile),
            str(allowed),
        )

    def stop(self) -> None:
        self._stop.set()
        th = self._thread
        if th and th.is_alive():
            th.join(timeout=5.0)
        self._thread = None
        logger.info("Telegram bridge service stopped")
