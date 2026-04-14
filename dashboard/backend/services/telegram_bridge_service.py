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
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
from fastapi import HTTPException

from .live_service import LiveTradingService
from ..models.database import (
    SessionLocal,
    SimulationSession,
    SimulationTrade,
    TelegramAutomationExecutionLogModel,
    WorkbenchAgentEventModel,
    WorkbenchAgentSessionModel,
    WorkbenchCopilotSessionModel,
    engine,
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


def _to_float_or_none(value: Any) -> Optional[float]:
    try:
        if value is None:
            return None
        f = float(value)
    except Exception:
        return None
    if not math.isfinite(float(f)):
        return None
    return float(f)


def _to_unix_or_none(value: Any) -> Optional[float]:
    if isinstance(value, (int, float)):
        try:
            v = float(value)
            if math.isfinite(v) and v > 0:
                return float(v)
        except Exception:
            pass
    if isinstance(value, datetime):
        dt = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
        return float(dt.timestamp())
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return float(dt.timestamp())
    except Exception:
        return None


class TelegramBridgeService:
    _DEADZONE_WATCH_BASE: List[Tuple[str, List[str]]] = [
        ("BTCUSD", ["BTCUSD", "BTCUSDM", "BTCUSDm", "BTCUSDT"]),
        ("ETHUSD", ["ETHUSD", "ETHUSDM", "ETHUSDm", "ETHUSDT"]),
        ("EURUSD", ["EURUSD", "EURUSDm"]),
        ("GBPUSD", ["GBPUSD", "GBPUSDm"]),
        ("USDJPY", ["USDJPY", "USDJPYm"]),
        ("AUDUSD", ["AUDUSD", "AUDUSDm"]),
        ("XAUUSD", ["XAUUSD", "XAUUSDm", "GOLD", "GOLDm"]),
    ]
    _CONFIRM_SIGNAL_DEFAULT_CHANNEL_TITLES: Tuple[str, ...] = ("Elite Pips Academy",)
    _CONFIRM_SIGNAL_DEFAULT_REQUIRE_CONFIRM_TITLES: Tuple[str, ...] = ("Elite Pips Academy",)
    _CONFIRM_SIGNAL_DEFAULT_NO_CONFIRM_TITLES: Tuple[str, ...] = ("PAROZGOLD_TRADER", "PAROZ GOLD TRADER")
    _CONFIRM_SIGNAL_SOURCE_PROFILE_RULES: Tuple[Tuple[str, Tuple[str, ...]], ...] = (
        ("elite", ("Elite Pips Academy",)),
        ("paroz", ("PAROZGOLD_TRADER", "PAROZ GOLD TRADER")),
        ("fx_mastermind", ("Trade With Fx Mastermind", "FxMasterMindOfficial2652")),
        ("market_king", ("MARKET ANALYSIS KING",)),
        ("gold_vip", ("GOLD VIP SIGNALS",)),
        ("henry", ("HENRY TRADER",)),
    )
    _CONFIRM_SIGNAL_SYMBOL_ALIASES: Dict[str, str] = {
        "GOLD": "XAUUSD",
        "XAU": "XAUUSD",
    }
    _MT4_EXEC_KNOWN_PROFILES: frozenset[str] = frozenset(
        {
            "hydra",
            "intrepid",
            "generic",
            "fxnuke",
            "uranus",
            "alchemy",
            "forexcyper",
            "supplydemand",
        }
    )
    _MT4_EXEC_DEFAULT_ENABLED_PROFILES: frozenset[str] = frozenset(
        {
            "hydra",
            "intrepid",
            "fxnuke",
            "uranus",
            "alchemy",
            "forexcyper",
            "supplydemand",
        }
    )

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

    @staticmethod
    def _normalize_mt_indicator_key(value: Any) -> str:
        raw = str(value or "").strip().lower()
        if not raw:
            return ""
        raw = re.sub(r"[^a-z0-9]+", " ", raw)
        raw = re.sub(r"\s+", " ", raw).strip()
        return raw

    @staticmethod
    def _normalize_mt4_indicator_name(value: Any) -> str:
        raw = str(value or "").strip()
        if not raw:
            return ""
        raw = raw.replace("/", "\\")
        if "\\" in raw:
            raw = str(raw.split("\\")[-1] or "").strip()
        raw = re.sub(r"\s+", " ", raw).strip()
        return raw

    @classmethod
    def _active_profile(cls) -> str:
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
        is_telegram_key = key.upper().startswith("TELEGRAM_")
        is_indicator_bridge_key = key.upper().startswith("INDICATOR_BRIDGE_")
        scoped = cls._profile_scoped_key(key)
        if is_telegram_key:
            # Telegram bridge must be configured only from dashboard/.env to avoid
            # host-level env var collisions across different machines/services.
            if scoped:
                sf = str(cls._read_env_file_value(scoped) or "").strip()
                if sf:
                    return sf
            fv = str(cls._read_env_file_value(key) or "").strip()
            if fv:
                return fv
            return str(default or "")
        if is_indicator_bridge_key:
            # Indicator bridge runtime controls are edited from dashboard/.env during live tuning.
            # Prefer file values over process env to avoid stale overrides after hot edits.
            fv = str(cls._read_env_file_value(key) or "").strip()
            if fv:
                return fv
            v = str(os.getenv(key) or "").strip()
            if v:
                return v
            return str(default or "")
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
        self._entry_watch_thread: Optional[threading.Thread] = None
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
        self._callback_actions_by_chat: Dict[int, Dict[str, Dict[str, Any]]] = {}
        self._callback_action_order_by_chat: Dict[int, List[str]] = {}
        self._next_callback_id_by_chat: Dict[int, int] = {}
        self._last_screener_scan_by_chat_session: Dict[Tuple[int, int], Dict[str, Any]] = {}
        self._last_warn_key: str = ""
        self._last_warn_at: float = 0.0
        self._live_service: Optional[LiveTradingService] = None
        self._deadzone_watch_last_run_ts: float = 0.0
        self._deadzone_watch_resolved_cache: List[Dict[str, str]] = []
        self._deadzone_watch_resolved_cache_ts: float = 0.0
        self._deadzone_watch_last_color: Dict[Tuple[str, str], str] = {}
        self._deadzone_watch_last_alert_key: Dict[Tuple[str, str], str] = {}
        self._deadzone_watch_last_alert_ts: Dict[Tuple[str, str], float] = {}
        self._deadzone_watch_pending_noncore: Dict[Tuple[str, str], Dict[str, Any]] = {}
        self._pending_deadzone_quick_trade_by_chat: Dict[int, Dict[str, Any]] = {}
        self._pending_live_tp_flow_by_chat: Dict[int, Dict[str, Any]] = {}
        self._next_reply_markup_by_chat: Dict[int, Dict[str, Any]] = {}
        self._active_confirmation_signal_ladders: Dict[str, Dict[str, Any]] = {}
        self._pending_confirmation_signals: Dict[str, Dict[str, Any]] = {}
        self._pending_entry_signals: Dict[str, Dict[str, Any]] = {}
        self._confirm_signal_feed: List[Dict[str, Any]] = []
        self._confirm_signal_feed_keys: set[str] = set()
        self._confirm_signal_feed_next_id: int = 0
        self._confirm_signal_feed_max: int = 5000
        self._confirm_signal_dedupe: Dict[str, float] = {}
        self._source_reentry_guard: Dict[str, Dict[str, Any]] = {}
        self._mt4_signal_dedupe: Dict[str, float] = {}
        self._indicator_event_id_seen: Dict[str, float] = {}
        self._mt4_bridge_combo_registry: Dict[str, float] = {}
        self._indicator_reversal_pending: Dict[str, Dict[str, Any]] = {}
        self._indicator_reversal_replay_inflight: set[str] = set()
        self._indicator_last_valid_signal: Dict[str, Dict[str, Any]] = {}
        self._indicator_clear_fallback_last_ts: Dict[str, float] = {}
        self._indicator_mode_exec_locks: Dict[str, threading.Lock] = {}
        self._indicator_recent_open: Dict[str, Dict[str, Any]] = {}
        self._indicator_sync_last_dir: Dict[str, Dict[str, Dict[str, Any]]] = {}
        self._indicator_bridge_instances: Dict[str, Dict[str, Any]] = {}
        self._indicator_rsi_telemetry: Dict[str, Dict[str, Any]] = {}
        self._indicator_rsi_telemetry_seq: int = 0
        self._automation_execution_logs: List[Dict[str, Any]] = []
        self._automation_execution_logs_next_id: int = 0
        self._automation_execution_logs_max: int = 5000
        self._execution_log_table_ready: bool = False
        self._execution_close_dedupe: Dict[int, float] = {}

    def _warn_throttled(self, key: str, message: str, *, min_interval_sec: float = 30.0) -> None:
        now_ts = time.time()
        k = str(key or "warn")
        if k != self._last_warn_key or (now_ts - float(self._last_warn_at)) >= float(min_interval_sec):
            logger.warning("%s", message)
            self._last_warn_key = k
            self._last_warn_at = now_ts

    def _indicator_mode_exec_lock(self, mode_source_tag: Any) -> threading.Lock:
        key = str(mode_source_tag or "").strip().lower()
        if not key:
            key = "__default__"
        with self._lock:
            row = self._indicator_mode_exec_locks.get(str(key))
            if row is not None:
                return row
            lock = threading.Lock()
            self._indicator_mode_exec_locks[str(key)] = lock
            if len(self._indicator_mode_exec_locks) > 10000:
                # Keep lock map bounded; live keys will be recreated on demand.
                self._indicator_mode_exec_locks = {
                    str(k): v
                    for k, v in self._indicator_mode_exec_locks.items()
                    if hasattr(v, "locked") and (not bool(v.locked()))
                }
            return lock

    @staticmethod
    def _indicator_open_debounce_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_INDICATOR_OPEN_DEBOUNCE_SEC", "2.5"))
        except Exception:
            raw = 2.5
        if not math.isfinite(float(raw)):
            raw = 2.5
        return float(max(0.0, min(30.0, float(raw))))

    @staticmethod
    def _indicator_recent_open_key(source_tag: Any, direction: Any) -> str:
        return f"{str(source_tag or '').strip().lower()}|{str(direction or '').strip().upper()}"

    def _mark_indicator_recent_open(self, *, source_tag: Any, direction: Any, ticket: Any = None, now_ts: Optional[float] = None) -> None:
        tag = str(source_tag or "").strip().lower()
        side = str(direction or "").strip().upper()
        if not tag or side not in {"BUY", "SELL"}:
            return
        ts = float(time.time() if now_ts is None else now_ts)
        key = self._indicator_recent_open_key(tag, side)
        row = {
            "source_tag": str(tag),
            "direction": str(side),
            "ticket": int(_to_float_or_none(ticket) or 0),
            "opened_ts": float(ts),
            "updated_ts": float(ts),
        }
        with self._lock:
            self._indicator_recent_open[str(key)] = dict(row)
            if len(self._indicator_recent_open) > 10000:
                cutoff = float(ts) - float(max(self._indicator_open_debounce_sec(), 15.0))
                self._indicator_recent_open = {
                    str(k): dict(v)
                    for k, v in self._indicator_recent_open.items()
                    if float(_to_float_or_none((v or {}).get("updated_ts")) or 0.0) >= float(cutoff)
                }

    def _clear_indicator_recent_open(self, *, source_tag: Any, direction: Optional[Any] = None) -> None:
        tag = str(source_tag or "").strip().lower()
        if not tag:
            return
        with self._lock:
            if direction is None:
                keep: Dict[str, Dict[str, Any]] = {}
                for k, v in self._indicator_recent_open.items():
                    row = dict(v or {})
                    row_tag = str(row.get("source_tag") or "").strip().lower()
                    if row_tag != tag:
                        keep[str(k)] = row
                self._indicator_recent_open = keep
                return
            side = str(direction or "").strip().upper()
            key = self._indicator_recent_open_key(tag, side)
            self._indicator_recent_open.pop(str(key), None)

    def _has_indicator_recent_open(self, *, source_tag: Any, direction: Any, now_ts: Optional[float] = None) -> bool:
        tag = str(source_tag or "").strip().lower()
        side = str(direction or "").strip().upper()
        if not tag or side not in {"BUY", "SELL"}:
            return False
        ttl = float(self._indicator_open_debounce_sec())
        if float(ttl) <= 0.0:
            return False
        ts = float(time.time() if now_ts is None else now_ts)
        key = self._indicator_recent_open_key(tag, side)
        with self._lock:
            row = dict(self._indicator_recent_open.get(str(key)) or {})
            if not row:
                return False
            seen_ts = float(_to_float_or_none(row.get("opened_ts")) or 0.0)
            if seen_ts <= 0.0:
                return False
            age = float(max(0.0, float(ts) - float(seen_ts)))
            if age <= float(ttl):
                return True
            self._indicator_recent_open.pop(str(key), None)
        return False

    @staticmethod
    def _parse_positive_number(value: Any) -> Optional[float]:
        raw = str(value or "").strip().replace(",", ".")
        if not raw:
            return None
        try:
            num = float(raw)
        except Exception:
            return None
        if not math.isfinite(float(num)) or float(num) <= 0.0:
            return None
        return float(num)

    def _set_next_reply_markup(self, chat_id: int, markup: Optional[Dict[str, Any]]) -> None:
        cid = int(chat_id)
        with self._lock:
            if isinstance(markup, dict) and markup:
                self._next_reply_markup_by_chat[cid] = dict(markup)
            else:
                self._next_reply_markup_by_chat.pop(cid, None)

    def _pop_next_reply_markup(self, chat_id: int) -> Optional[Dict[str, Any]]:
        cid = int(chat_id)
        with self._lock:
            val = self._next_reply_markup_by_chat.pop(cid, None)
        return val if isinstance(val, dict) and val else None

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
    def _deadzone_colorflip_enabled() -> bool:
        # Hard-disabled by product decision: deadzone color-flip alerts are not needed.
        return False

    @staticmethod
    def _deadzone_colorflip_interval_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_DEADZONE_COLORFLIP_INTERVAL_SEC", "5"))
        except Exception:
            raw = 5.0
        return max(1.0, min(60.0, raw))

    @staticmethod
    def _deadzone_colorflip_history_count() -> int:
        try:
            raw = int(TelegramBridgeService._get_env_value("TELEGRAM_DEADZONE_COLORFLIP_HISTORY_COUNT", "220"))
        except Exception:
            raw = 220
        return max(80, min(1000, raw))

    @staticmethod
    def _deadzone_noncore_filter_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_DEADZONE_NONCORE_FILTER_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _deadzone_noncore_confirm_polls() -> int:
        try:
            raw = int(TelegramBridgeService._get_env_value("TELEGRAM_DEADZONE_NONCORE_CONFIRM_POLLS", "2"))
        except Exception:
            raw = 2
        return max(1, min(5, raw))

    @staticmethod
    def _deadzone_noncore_min_hold_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_DEADZONE_NONCORE_MIN_HOLD_SEC", "4"))
        except Exception:
            raw = 4.0
        return max(0.0, min(60.0, raw))

    @staticmethod
    def _deadzone_noncore_cooldown_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_DEADZONE_NONCORE_ALERT_COOLDOWN_SEC", "30"))
        except Exception:
            raw = 30.0
        return max(0.0, min(600.0, raw))

    @staticmethod
    def _confirm_signal_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNALS_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _confirm_signal_default_timeframe() -> str:
        raw = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_DEFAULT_TIMEFRAME", "M5")).strip().upper()
        return raw or "M5"

    @staticmethod
    def _confirm_signal_default_lot() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_DEFAULT_LOT", "0.05"))
        except Exception:
            raw = 0.05
        if not math.isfinite(float(raw)) or float(raw) <= 0.0:
            raw = 0.05
        return float(max(0.001, min(100.0, float(raw))))

    @staticmethod
    def _confirm_signal_force_single_trade_01() -> bool:
        # Emergency fallback: disable partial ladder and open one 0.01 trade.
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_FORCE_SINGLE_TRADE_01", "0")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _confirm_signal_allow_message_single_trade_override() -> bool:
        v = str(
            TelegramBridgeService._get_env_value(
                "TELEGRAM_CONFIRM_SIGNAL_ALLOW_MESSAGE_SINGLE_TRADE_OVERRIDE",
                "1",
            )
        ).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _confirm_signal_eval_mode() -> str:
        raw = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_EVAL_MODE", "deterministic")).strip().lower()
        if raw in {"ai", "ai_assist", "assist"}:
            return "ai_assist"
        return "deterministic"

    @staticmethod
    def _confirm_signal_ai_provider() -> str:
        raw = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_AI_PROVIDER", "claude")).strip().lower()
        if raw in {"openai", "gpt"}:
            return "openai"
        return "claude"

    @staticmethod
    def _confirm_signal_ai_model() -> str:
        raw = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_AI_MODEL", "")).strip()
        if raw:
            return raw
        provider = TelegramBridgeService._confirm_signal_ai_provider()
        return "claude-3-5-haiku-latest" if provider == "claude" else "gpt-4o-mini"

    @staticmethod
    def _confirm_signal_ai_timeout_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_AI_TIMEOUT_SEC", "10"))
        except Exception:
            raw = 10.0
        if not math.isfinite(float(raw)):
            raw = 10.0
        return float(max(2.0, min(30.0, float(raw))))

    @staticmethod
    def _confirm_signal_tp_distribution_mode() -> str:
        raw = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_TP_DISTRIBUTION", "equal")).strip().lower()
        if raw in {"equal", "even", "balanced"}:
            return "equal"
        if raw in {"front", "front_loaded", "frontloaded", "early"}:
            return "front_loaded"
        if raw in {"runner", "back", "back_loaded", "backloaded", "late"}:
            return "runner"
        return "equal"

    @classmethod
    def _confirm_signal_channel_titles(cls) -> List[str]:
        raw = str(cls._get_env_value("TELEGRAM_CONFIRM_SIGNAL_CHANNEL_TITLES", "")).strip()
        items = [str(x).strip() for x in raw.split("|") if str(x).strip()]
        if not items:
            items = [str(x).strip() for x in cls._CONFIRM_SIGNAL_DEFAULT_CHANNEL_TITLES if str(x).strip()]
        return items

    @staticmethod
    def _confirm_signal_requires_confirm() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_REQUIRE_CONFIRM", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @classmethod
    def _confirm_signal_require_confirm_titles(cls) -> List[str]:
        raw = str(cls._get_env_value("TELEGRAM_CONFIRM_SIGNAL_REQUIRE_CONFIRM_CHANNEL_TITLES", "")).strip()
        items = [str(x).strip() for x in raw.split("|") if str(x).strip()]
        if not items:
            items = [str(x).strip() for x in cls._CONFIRM_SIGNAL_DEFAULT_REQUIRE_CONFIRM_TITLES if str(x).strip()]
        return items

    @classmethod
    def _confirm_signal_no_confirm_titles(cls) -> List[str]:
        raw = str(cls._get_env_value("TELEGRAM_CONFIRM_SIGNAL_NO_CONFIRM_CHANNEL_TITLES", "")).strip()
        items = [str(x).strip() for x in raw.split("|") if str(x).strip()]
        if not items:
            items = [str(x).strip() for x in cls._CONFIRM_SIGNAL_DEFAULT_NO_CONFIRM_TITLES if str(x).strip()]
        return items

    @staticmethod
    def _confirm_signal_confirm_window_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_CONFIRM_WINDOW_SEC", "1800"))
        except Exception:
            raw = 1800.0
        if not math.isfinite(float(raw)):
            raw = 1800.0
        return float(max(30.0, min(7200.0, float(raw))))

    @staticmethod
    def _confirm_signal_dedupe_window_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_DEDUPE_SEC", "90"))
        except Exception:
            raw = 90.0
        if not math.isfinite(float(raw)):
            raw = 90.0
        return float(max(0.0, min(3600.0, float(raw))))

    @staticmethod
    def _confirm_signal_wait_entry_zone() -> bool:
        # Execute only when live price enters [entry_low, entry_high] inclusive.
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_WAIT_ENTRY_ZONE", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _confirm_signal_entry_wait_max_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_ENTRY_WAIT_MAX_SEC", "1800"))
        except Exception:
            raw = 1800.0
        if not math.isfinite(float(raw)):
            raw = 1800.0
        return float(max(30.0, min(14400.0, float(raw))))

    @staticmethod
    def _confirm_signal_entry_attempt_cooldown_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_ENTRY_ATTEMPT_COOLDOWN_SEC", "0.35"))
        except Exception:
            raw = 0.35
        if not math.isfinite(float(raw)):
            raw = 0.35
        return float(max(0.1, min(30.0, float(raw))))

    @staticmethod
    def _confirm_signal_entry_watch_interval_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_ENTRY_WATCH_INTERVAL_SEC", "0.25"))
        except Exception:
            raw = 0.25
        if not math.isfinite(float(raw)):
            raw = 0.25
        return float(max(0.05, min(2.0, float(raw))))

    @staticmethod
    def _build_execution_trace_id(*, source_key: str, symbol: str, direction: str) -> str:
        ts_ms = int(time.time() * 1000)
        seed = f"{str(source_key or '').strip().lower()}|{str(symbol or '').strip().upper()}|{str(direction or '').strip().upper()}|{int(ts_ms)}"
        sig = abs(hash(seed)) % 1000000
        return f"tgx-{int(ts_ms)}-{int(sig):06d}"

    @staticmethod
    def _normalize_confirm_source_name(value: Any) -> str:
        raw = str(value or "").strip()
        if not raw:
            return ""
        norm = unicodedata.normalize("NFKC", raw)
        norm = str(norm).casefold()
        norm = re.sub(r"[^a-z0-9]+", " ", norm)
        norm = re.sub(r"\s+", " ", norm).strip()
        return norm

    @classmethod
    def _confirm_signal_source_key(cls, chat_id: int, source_name: Any) -> str:
        src = cls._normalize_confirm_source_name(source_name)
        if not src:
            src = "unknown"
        return f"{int(chat_id)}:{src}"

    @classmethod
    def _source_matches_rule(cls, source_name: Any, rule_name: Any) -> bool:
        s = cls._normalize_confirm_source_name(source_name)
        r = cls._normalize_confirm_source_name(rule_name)
        if not s or not r:
            return False
        if s == r or s in r or r in s:
            return True
        # Extra tolerance for channel aliases like:
        # "PAROZGOLD_TRADER" vs "PAROZ GOLD TRADER" vs "t.me/PAROZGOLD_TRADER"
        s_compact = re.sub(r"[^a-z0-9]+", "", s)
        r_compact = re.sub(r"[^a-z0-9]+", "", r)
        if not s_compact or not r_compact:
            return False
        return bool(
            s_compact == r_compact
            or s_compact in r_compact
            or r_compact in s_compact
        )

    @classmethod
    def _resolve_confirm_signal_source_profile(cls, source_names: List[Any]) -> str:
        names = [str(x).strip() for x in (source_names or []) if str(x).strip()]
        for profile, rules in cls._CONFIRM_SIGNAL_SOURCE_PROFILE_RULES:
            for name in names:
                for rule in rules:
                    if cls._source_matches_rule(name, rule):
                        return str(profile)
        return "generic"

    @staticmethod
    def _confirm_signal_reentry_guard_ttl_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SIGNAL_REENTRY_GUARD_TTL_SEC", "21600"))
        except Exception:
            raw = 21600.0
        if not math.isfinite(float(raw)):
            raw = 21600.0
        return float(max(300.0, min(172800.0, float(raw))))

    @staticmethod
    def _confirm_signal_reentry_guard_stale_no_active_sec() -> float:
        try:
            raw = float(
                TelegramBridgeService._get_env_value(
                    "TELEGRAM_CONFIRM_SIGNAL_REENTRY_GUARD_STALE_NO_ACTIVE_SEC",
                    "120",
                )
            )
        except Exception:
            raw = 120.0
        if not math.isfinite(float(raw)):
            raw = 120.0
        return float(max(10.0, min(3600.0, float(raw))))

    @staticmethod
    def _profile_requires_tp_progress_gate(profile: Any) -> bool:
        p = str(profile or "").strip().lower()
        return p in {"henry", "gold_vip"}

    @classmethod
    def _extract_signal_hint_from_text(cls, text: Any) -> Dict[str, str]:
        raw = unicodedata.normalize("NFKC", str(text or ""))
        if not raw.strip():
            return {"symbol": "", "direction": ""}
        symbol = ""
        direction = ""
        m = re.search(r"(?im)#?\s*([A-Z]{3,12})\s*[_\-\s]\s*(BUY|SELL)\b", raw)
        if m:
            symbol = cls._normalize_signal_symbol(m.group(1))
            direction = str(m.group(2) or "").strip().upper()
            return {"symbol": str(symbol), "direction": str(direction)}
        m2 = re.search(r"(?im)#?\s*([A-Z]{3,12})\b", raw)
        if m2:
            symbol = cls._normalize_signal_symbol(m2.group(1))
        return {"symbol": str(symbol), "direction": str(direction)}

    @staticmethod
    def _reentry_guard_key(source_key: str, symbol: str, direction: str) -> str:
        return f"{str(source_key).strip()}|{str(symbol).strip().upper()}|{str(direction).strip().upper()}"

    def _should_block_reentry_before_tp(self, *, source_key: str, signal: Dict[str, Any]) -> bool:
        symbol = self._normalize_signal_symbol((signal or {}).get("symbol"))
        direction = str((signal or {}).get("direction") or "").strip().upper()
        if not symbol or direction not in {"BUY", "SELL"}:
            return False
        key = self._reentry_guard_key(str(source_key), str(symbol), str(direction))
        now_ts = float(time.time())
        ttl = float(self._confirm_signal_reentry_guard_ttl_sec())
        stale_no_active_sec = float(self._confirm_signal_reentry_guard_stale_no_active_sec())
        with self._lock:
            row = self._source_reentry_guard.get(str(key))
            if not isinstance(row, dict):
                return False
            waiting = bool(row.get("awaiting_tp", False))
            updated_ts = _to_float_or_none(row.get("updated_ts")) or 0.0
            if waiting and updated_ts > 0.0 and (now_ts - float(updated_ts)) > ttl:
                # Guard expired; fail open.
                row["awaiting_tp"] = False
                row["updated_ts"] = float(now_ts)
                self._source_reentry_guard[str(key)] = dict(row)
                return False
            if waiting and updated_ts > 0.0 and (now_ts - float(updated_ts)) > stale_no_active_sec:
                has_active_ladder = False
                for ladder in self._active_confirmation_signal_ladders.values():
                    if not isinstance(ladder, dict):
                        continue
                    ladder_src = str(ladder.get("source_key") or "").strip()
                    ladder_sym = self._normalize_signal_symbol(ladder.get("symbol"))
                    ladder_dir = str(ladder.get("direction") or "").strip().upper()
                    if ladder_src != str(source_key).strip():
                        continue
                    if ladder_sym != str(symbol):
                        continue
                    if ladder_dir != str(direction):
                        continue
                    has_active_ladder = True
                    break
                if not has_active_ladder:
                    # Self-heal stale guard records left behind by older flows.
                    row["awaiting_tp"] = False
                    row["updated_ts"] = float(now_ts)
                    row["last_event"] = "stale_guard_auto_cleared"
                    self._source_reentry_guard[str(key)] = dict(row)
                    return False
            return bool(waiting)

    def _mark_reentry_signal_started(self, *, source_key: str, signal: Dict[str, Any], profile: str) -> None:
        symbol = self._normalize_signal_symbol((signal or {}).get("symbol"))
        direction = str((signal or {}).get("direction") or "").strip().upper()
        if not symbol or direction not in {"BUY", "SELL"}:
            return
        key = self._reentry_guard_key(str(source_key), str(symbol), str(direction))
        now_ts = float(time.time())
        row = {
            "source_key": str(source_key),
            "symbol": str(symbol),
            "direction": str(direction),
            "profile": str(profile or "").strip().lower(),
            "awaiting_tp": True,
            "tp_seen": False,
            "created_ts": float(now_ts),
            "updated_ts": float(now_ts),
            "last_event": "signal",
            "signal": {
                "entry_low": _to_float_or_none((signal or {}).get("entry_low")),
                "entry_high": _to_float_or_none((signal or {}).get("entry_high")),
                "stop_loss": _to_float_or_none((signal or {}).get("stop_loss")),
            },
        }
        with self._lock:
            self._source_reentry_guard[str(key)] = dict(row)

    def _mark_reentry_progress_from_execution(
        self,
        *,
        source_key: str,
        symbol: Any,
        direction: Any,
        event_kind: str,
    ) -> None:
        src = str(source_key or "").strip()
        sym = self._normalize_signal_symbol(symbol)
        side = str(direction or "").strip().upper()
        evt = str(event_kind or "").strip().lower()
        if not src or not sym or side not in {"BUY", "SELL"}:
            return
        key = self._reentry_guard_key(str(src), str(sym), str(side))
        now_ts = float(time.time())
        with self._lock:
            row = dict(self._source_reentry_guard.get(str(key)) or {})
            if not isinstance(row, dict) or not row:
                return
            if evt == "tp_hit":
                row["awaiting_tp"] = False
                row["tp_seen"] = True
                row["last_event"] = "tp_hit_exec"
            else:
                row["awaiting_tp"] = False
                row["last_event"] = (str(evt) if str(evt) else "closed_exec")
            row["updated_ts"] = float(now_ts)
            self._source_reentry_guard[str(key)] = dict(row)

    def _apply_reentry_progress_from_message(self, *, source_key: str, text: Any, msg_kind: str) -> None:
        kind = str(msg_kind or "").strip().lower()
        if kind not in {"tp_hit", "sl_hit", "close_instruction"}:
            return
        hint = self._extract_signal_hint_from_text(text)
        hint_symbol = self._normalize_signal_symbol((hint or {}).get("symbol"))
        hint_dir = str((hint or {}).get("direction") or "").strip().upper()
        now_ts = float(time.time())
        updates: List[str] = []
        with self._lock:
            candidates: List[Tuple[str, Dict[str, Any]]] = []
            for k, row in self._source_reentry_guard.items():
                if not isinstance(row, dict):
                    continue
                if str(row.get("source_key") or "") != str(source_key):
                    continue
                if not bool(row.get("awaiting_tp", False)):
                    continue
                row_sym = self._normalize_signal_symbol(row.get("symbol"))
                row_dir = str(row.get("direction") or "").strip().upper()
                if hint_symbol and row_sym != hint_symbol:
                    continue
                if hint_dir and row_dir != hint_dir:
                    continue
                candidates.append((str(k), dict(row)))
            # Fallback: no explicit symbol/dir in message -> apply to most recent waiting cycle of this source.
            if not candidates and (not hint_symbol and not hint_dir):
                all_waiting: List[Tuple[str, Dict[str, Any], float]] = []
                for k, row in self._source_reentry_guard.items():
                    if not isinstance(row, dict):
                        continue
                    if str(row.get("source_key") or "") != str(source_key):
                        continue
                    if not bool(row.get("awaiting_tp", False)):
                        continue
                    ts = _to_float_or_none(row.get("updated_ts")) or 0.0
                    all_waiting.append((str(k), dict(row), float(ts)))
                all_waiting.sort(key=lambda x: float(x[2]), reverse=True)
                if all_waiting:
                    candidates.append((str(all_waiting[0][0]), dict(all_waiting[0][1])))
            for k, row in candidates:
                if kind == "tp_hit":
                    row["awaiting_tp"] = False
                    row["tp_seen"] = True
                    row["last_event"] = "tp_hit"
                elif kind == "sl_hit":
                    row["awaiting_tp"] = False
                    row["last_event"] = "sl_hit"
                elif kind == "close_instruction":
                    row["awaiting_tp"] = False
                    row["last_event"] = "close_instruction"
                row["updated_ts"] = float(now_ts)
                self._source_reentry_guard[str(k)] = dict(row)
                updates.append(str(k))
        if updates:
            logger.info(
                "telegram_reentry_guard_progress source=%s kind=%s updated=%s",
                str(source_key),
                str(kind),
                ",".join(updates[:5]),
            )

    @classmethod
    def _profile_accepts_signal_text(cls, text: Any, source_profile: str) -> bool:
        profile = str(source_profile or "generic").strip().lower() or "generic"
        raw = unicodedata.normalize("NFKC", str(text or ""))
        if not raw.strip():
            return False
        if profile == "elite":
            return bool(
                re.search(r"(?im)\bNOW\b", raw)
                and re.search(r"(?im)\bTP\s*1\b|\bTP1\b", raw)
                and re.search(r"(?im)\bSL\b", raw)
            )
        if profile == "paroz":
            return bool(
                re.search(r"(?im)^\s*(?:#?\s*(?:XAUUSD|GOLD))\s+(BUY|SELL)\b", raw)
                and len(re.findall(r"(?im)\bTP\s*[:\-]\s*[0-9]+(?:\.[0-9]+)?\b", raw)) >= 2
                and re.search(r"(?im)\bSL\s*[:\-]?\s*[0-9]+(?:\.[0-9]+)?\b", raw)
            )
        if profile == "fx_mastermind":
            return bool(
                re.search(r"(?im)^\s*#\s*[A-Z]{3,12}\s*[_\-\s]+(BUY|SELL)\b", raw)
                and re.search(r"(?im)\bSL(?:\s*[1-9]\d*)?\s*[:\-]?\s*[0-9]+(?:\.[0-9]+)?\b", raw)
                and re.search(r"(?im)\bTP", raw)
            )
        if profile == "market_king":
            return bool(
                re.search(r"(?im)^\s*(?:#?\s*XAUUSD)\s+(BUY|SELL)\b", raw)
                and len(re.findall(r"(?im)\bTP\s*[:\-]?\s*[0-9]+(?:\.[0-9]+)?\b", raw)) >= 2
                and re.search(r"(?im)\bSL\s*[:\-]?\s*[0-9]+(?:\.[0-9]+)?\b", raw)
            )
        if profile == "gold_vip":
            return bool(
                re.search(r"(?im)^\s*(?:#?\s*(?:XAUUSD|GOLD))\s+(BUY|SELL)\b", raw)
                and len(re.findall(r"(?im)\bTP\s*[:\-]?\s*[0-9]+(?:\.[0-9]+)?\b", raw)) >= 2
                and re.search(r"(?im)\bSL\s*[:\-]?\s*[0-9]+(?:\.[0-9]+)?\b", raw)
            )
        if profile == "henry":
            return bool(
                re.search(r"(?im)^\s*#?\s*XAUUSD(?:\s+#?\s*GOLD)?\s*[_\-\s]+(BUY|SELL)\s+[0-9]+(?:\.[0-9]+)?\s*(?:/|-)\s*[0-9]+(?:\.[0-9]+)?\s*$", raw)
                and re.search(r"(?im)\bSL\s*[:\-]?\s*[0-9]+(?:\.[0-9]+)?\b", raw)
                and re.search(r"(?im)\bTP", raw)
            )
        return True

    @classmethod
    def _parse_confirmation_signal_for_sources(
        cls,
        text: Any,
        source_names: Optional[List[Any]] = None,
    ) -> Optional[Dict[str, Any]]:
        parsed = cls._parse_confirmation_signal(text)
        if not isinstance(parsed, dict):
            return None
        profile = cls._resolve_confirm_signal_source_profile(list(source_names or []))
        if not cls._profile_accepts_signal_text(text, profile):
            return None
        out = dict(parsed)
        out["source_profile"] = str(profile)
        return out

    @classmethod
    def _classify_confirm_signal_message_for_sources(
        cls,
        text: Any,
        source_names: Optional[List[Any]] = None,
    ) -> str:
        kind = cls._classify_confirm_signal_message(text)
        if str(kind) != "signal":
            return str(kind)
        parsed = cls._parse_confirmation_signal_for_sources(text, source_names=list(source_names or []))
        return "signal" if isinstance(parsed, dict) else "other"

    @classmethod
    def _confirm_signal_requires_confirm_for_source(cls, source_name: Any) -> bool:
        no_confirm = [x for x in cls._confirm_signal_no_confirm_titles() if str(x).strip()]
        for row in no_confirm:
            if cls._source_matches_rule(source_name, row):
                return False
        require_confirm = [x for x in cls._confirm_signal_require_confirm_titles() if str(x).strip()]
        for row in require_confirm:
            if cls._source_matches_rule(source_name, row):
                return True
        return bool(cls._confirm_signal_requires_confirm())

    @classmethod
    def _confirm_signal_requires_confirm_for_sources(cls, source_names: List[Any]) -> bool:
        names = [x for x in (source_names or []) if str(x).strip()]
        if not names:
            return bool(cls._confirm_signal_requires_confirm())
        no_confirm = [x for x in cls._confirm_signal_no_confirm_titles() if str(x).strip()]
        for name in names:
            for rule in no_confirm:
                if cls._source_matches_rule(name, rule):
                    return False
        require_confirm = [x for x in cls._confirm_signal_require_confirm_titles() if str(x).strip()]
        for name in names:
            for rule in require_confirm:
                if cls._source_matches_rule(name, rule):
                    return True
        # If an explicit require-confirm list exists, only those sources should require confirm.
        if require_confirm:
            return False
        return bool(cls._confirm_signal_requires_confirm())

    @classmethod
    def _is_confirm_signal_message(cls, text: Any) -> bool:
        norm = cls._normalize_confirm_source_name(text)
        if not norm:
            return False
        return bool(re.search(r"\bconfirm signal\b", norm))

    @staticmethod
    def _upsert_env_values(updates: Dict[str, Any]) -> Tuple[bool, str]:
        if not isinstance(updates, dict) or not updates:
            return False, "no_updates"
        repo_root = Path(__file__).resolve().parents[3]
        env_path = repo_root / "dashboard" / ".env"
        try:
            lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
        except Exception as exc:
            return False, f"read_env_failed:{type(exc).__name__}:{str(exc)[:140]}"
        normalized: Dict[str, str] = {}
        for k, v in updates.items():
            key = str(k or "").strip().upper()
            if not key.startswith("TELEGRAM_"):
                continue
            if v is None:
                continue
            normalized[key] = str(v).strip()
        if not normalized:
            return False, "no_valid_updates"
        out_lines: List[str] = []
        replaced: set[str] = set()
        for line in lines:
            raw = str(line or "")
            if "=" not in raw:
                out_lines.append(raw)
                continue
            key = str(raw.split("=", 1)[0]).strip().upper()
            if key in normalized:
                out_lines.append(f"{key}={normalized[key]}")
                replaced.add(key)
            else:
                out_lines.append(raw)
        for key, val in normalized.items():
            if key not in replaced:
                out_lines.append(f"{key}={val}")
        try:
            env_path.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")
        except Exception as exc:
            return False, f"write_env_failed:{type(exc).__name__}:{str(exc)[:140]}"
        return True, "ok"

    @staticmethod
    def _classify_confirm_signal_message(text: Any) -> str:
        raw = str(text or "").replace("\r", "\n").strip()
        if not raw:
            return "empty"
        raw_norm = unicodedata.normalize("NFKC", raw)
        if TelegramBridgeService._is_confirm_signal_message(raw_norm):
            return "confirm_signal"
        if (
            re.search(r"(?im)\bclose\s+it\b", raw_norm)
            or re.search(r"(?im)\bclose\s+now\b", raw_norm)
            or re.search(r"(?im)\bsave\s+(?:your\s+)?profit(?:s)?\b", raw_norm)
            or re.search(r"(?im)\bwait\s+for\s+better\s+sniper\s+entry\b", raw_norm)
        ):
            return "close_instruction"
        if (
            re.search(r"(?im)\bTP\s*(?:[1-9]\d*)?\s*HIT\b", raw_norm)
            or re.search(r"(?im)\ball\s+target(?:s)?\s+(?:successfully\s+)?(?:hit|completed)\b", raw_norm)
            or re.search(r"(?im)\btarget(?:s)?\s+completed\b", raw_norm)
        ):
            return "tp_hit"
        if re.search(r"(?im)\b(?:SL(?:\s*[1-9]\d*)?|STOP\s*LOSS)\b.*\bHIT\b", raw_norm):
            return "sl_hit"
        if TelegramBridgeService._parse_confirmation_signal(raw_norm):
            return "signal"
        if re.search(
            (
                r"(?im)^\s*#?\s*[A-Z]{3,12}"
                r"(?:\s+#?\s*[A-Z]{3,12})?"
                r"\s*(?:[_\-\s]+)(BUY|SELL)\s+"
                r"(?:NOW\s+)?[0-9]+(?:\.[0-9]+)?"
                r"(?:\s*(?:/|-|TO)\s*[0-9]+(?:\.[0-9]+)?)?\s*$"
            ),
            raw_norm,
        ):
            return "signal"
        return "other"

    @classmethod
    def _normalize_signal_symbol(cls, value: Any) -> str:
        raw = str(value or "").strip().upper()
        if not raw:
            return ""
        return str(cls._CONFIRM_SIGNAL_SYMBOL_ALIASES.get(raw, raw)).strip().upper()

    @classmethod
    def _parse_close_instruction_signal_hint(cls, text: Any) -> Dict[str, Any]:
        raw = str(text or "").strip()
        if not raw:
            return {}
        if not (
            re.search(r"(?im)\bclose\s+it\b", raw)
            or re.search(r"(?im)\bclose\s+now\b", raw)
            or re.search(r"(?im)\bsave\s+(?:your\s+)?profit(?:s)?\b", raw)
            or re.search(r"(?im)\bwait\s+for\s+better\s+sniper\s+entry\b", raw)
        ):
            return {}
        # Examples:
        #   #XAUUSD_SELL
        #   #XAUUSD SELL
        #   XAUUSD SELL
        sym = ""
        side = ""
        m = re.search(r"(?im)#?\s*([A-Z]{3,12})\s*[_\-\s]\s*(BUY|SELL)\b", raw)
        if m:
            sym = cls._normalize_signal_symbol(m.group(1))
            side = str(m.group(2) or "").strip().upper()
        return {
            "is_close_instruction": True,
            "symbol": str(sym),
            "direction": str(side),
        }

    def _append_confirm_signal_feed(
        self,
        *,
        source: str,
        chat: Optional[Dict[str, Any]],
        text: str,
        kind: str,
        parsed: Optional[Dict[str, Any]] = None,
        event_ts: Optional[Any] = None,
        source_message_id: Optional[int] = None,
    ) -> None:
        src = str(source or "").strip() or "unknown"
        src_norm = self._normalize_confirm_source_name(src)
        src_msg_id = int(source_message_id or 0)
        dedupe_key = f"{src_norm}|{int(src_msg_id)}" if src_msg_id > 0 else ""
        event_unix = _to_unix_or_none(event_ts)
        event_iso = None
        if isinstance(event_ts, datetime):
            dt = event_ts if event_ts.tzinfo is not None else event_ts.replace(tzinfo=timezone.utc)
            event_iso = dt.isoformat()
        elif isinstance(event_ts, str):
            event_iso = str(event_ts or "").strip() or None
        elif event_unix is not None:
            try:
                event_iso = datetime.fromtimestamp(float(event_unix), tz=timezone.utc).isoformat()
            except Exception:
                event_iso = None
        row = {
            "id": int(self._confirm_signal_feed_next_id + 1),
            "ts": self._now_iso(),
            "event_ts": str(event_iso or self._now_iso()),
            "event_unix": float(event_unix if event_unix is not None else time.time()),
            "source_message_id": int(src_msg_id),
            "source": str(src),
            "chat_title": str((chat or {}).get("title") or "").strip(),
            "kind": str(kind or "other"),
            "text": str(text or "").strip()[:4000],
            "parsed": dict(parsed) if isinstance(parsed, dict) else None,
        }
        with self._lock:
            if dedupe_key and dedupe_key in self._confirm_signal_feed_keys:
                return
            self._confirm_signal_feed_next_id = int(row["id"])
            self._confirm_signal_feed.append(row)
            if dedupe_key:
                self._confirm_signal_feed_keys.add(str(dedupe_key))
            if len(self._confirm_signal_feed) > int(self._confirm_signal_feed_max):
                self._confirm_signal_feed = self._confirm_signal_feed[-int(self._confirm_signal_feed_max):]
                rebuilt: set[str] = set()
                for r in self._confirm_signal_feed:
                    try:
                        smid = int((r or {}).get("source_message_id") or 0)
                    except Exception:
                        smid = 0
                    if smid <= 0:
                        continue
                    sname = self._normalize_confirm_source_name((r or {}).get("source"))
                    if not sname:
                        continue
                    rebuilt.add(f"{sname}|{int(smid)}")
                self._confirm_signal_feed_keys = rebuilt

    def _append_automation_execution_log(
        self,
        *,
        source_type: str,
        source_name: str,
        trigger: str,
        status: str,
        symbol: Optional[str] = None,
        timeframe: Optional[str] = None,
        direction: Optional[str] = None,
        lot: Optional[float] = None,
        stop_loss: Optional[float] = None,
        final_tp: Optional[float] = None,
        stages_total: Optional[int] = None,
        stages_opened: Optional[int] = None,
        ticket: Optional[int] = None,
        message: Optional[str] = None,
        profile: Optional[str] = None,
        indicator: Optional[str] = None,
        source_tag: Optional[str] = None,
        event_ts: Optional[Any] = None,
        realized_pnl: Optional[float] = None,
        max_profit: Optional[float] = None,
        max_loss: Optional[float] = None,
        close_reason: Optional[str] = None,
        opened_at: Optional[Any] = None,
        combo_key: Optional[str] = None,
        execution_mode: Optional[str] = None,
        order_number: Optional[int] = None,
        deal_number: Optional[int] = None,
        trace_id: Optional[str] = None,
        stage: Optional[str] = None,
        stage_status: Optional[str] = None,
        stage_payload: Optional[Dict[str, Any]] = None,
        error_code: Optional[str] = None,
    ) -> None:
        self._ensure_execution_log_table()
        event_unix = _to_unix_or_none(event_ts)
        event_dt: Optional[datetime] = None
        if event_unix is not None:
            try:
                event_dt = datetime.fromtimestamp(float(event_unix), tz=timezone.utc).replace(tzinfo=None)
            except Exception:
                event_dt = None
        elif isinstance(event_ts, datetime):
            event_dt = (event_ts if event_ts.tzinfo is not None else event_ts.replace(tzinfo=timezone.utc)).replace(tzinfo=None)
        row = {
            "id": 0,
            "ts": self._now_iso(),
            "event_ts": str(event_ts or self._now_iso()),
            "source_type": str(source_type or "").strip() or "unknown",
            "source_name": str(source_name or "").strip() or "unknown",
            "trigger": str(trigger or "").strip() or "unknown",
            "status": str(status or "").strip().lower() or "unknown",
            "symbol": str(symbol or "").strip().upper(),
            "timeframe": str(timeframe or "").strip().upper(),
            "direction": str(direction or "").strip().upper(),
            "lot": (_to_float_or_none(lot) if lot is not None else None),
            "stop_loss": (_to_float_or_none(stop_loss) if stop_loss is not None else None),
            "final_tp": (_to_float_or_none(final_tp) if final_tp is not None else None),
            "stages_total": (int(stages_total) if stages_total is not None else None),
            "stages_opened": (int(stages_opened) if stages_opened is not None else None),
            "ticket": (int(ticket) if ticket is not None else None),
            "message": str(message or "").strip()[:500],
            "profile": str(profile or "").strip().lower(),
            "indicator": str(indicator or "").strip(),
            "source_tag": str(source_tag or "").strip().lower(),
        }
        # Strict bridge hygiene: indicator automation audit rows must carry a
        # deterministic MT4/MT5 bridge source tag. Reject malformed indicator rows.
        if str(row.get("source_type") or "").strip().lower() == "mt_indicator":
            if not self._is_bridge_source_tag(row.get("source_tag")):
                logger.warning(
                    "indicator_execution_log_rejected_invalid_source_tag source=%s indicator=%s symbol=%s timeframe=%s tag=%s",
                    str(row.get("source_name") or ""),
                    str(row.get("indicator") or ""),
                    str(row.get("symbol") or ""),
                    str(row.get("timeframe") or ""),
                    str(row.get("source_tag") or ""),
                )
                return
        for attempt in range(8):
            db = SessionLocal()
            try:
                model = TelegramAutomationExecutionLogModel(
                    created_at=datetime.now(timezone.utc).replace(tzinfo=None),
                    event_ts=event_dt,
                    source_type=str(row.get("source_type") or "unknown"),
                    source_name=str(row.get("source_name") or "unknown"),
                    trigger=str(row.get("trigger") or "unknown"),
                    status=str(row.get("status") or "unknown"),
                    symbol=str(row.get("symbol") or "") or None,
                    timeframe=str(row.get("timeframe") or "") or None,
                    direction=str(row.get("direction") or "") or None,
                    lot=_to_float_or_none(row.get("lot")),
                    stop_loss=_to_float_or_none(row.get("stop_loss")),
                    final_tp=_to_float_or_none(row.get("final_tp")),
                    stages_total=(int(row["stages_total"]) if row.get("stages_total") is not None else None),
                    stages_opened=(int(row["stages_opened"]) if row.get("stages_opened") is not None else None),
                    ticket=(int(row["ticket"]) if row.get("ticket") is not None else None),
                    profile=str(row.get("profile") or "") or None,
                    indicator=str(row.get("indicator") or "") or None,
                    source_tag=str(row.get("source_tag") or "") or None,
                    message=str(row.get("message") or "") or None,
                    extra_json={
                        "ts_iso": str(row.get("ts") or ""),
                        "event_ts_raw": str(event_ts or ""),
                        "realized_pnl": _to_float_or_none(realized_pnl),
                        "max_profit": _to_float_or_none(max_profit),
                        "max_loss": _to_float_or_none(max_loss),
                        "close_reason": str(close_reason or "").strip() or None,
                        "opened_at": str(opened_at or "").strip() or None,
                        "combo_key": str(combo_key or "").strip().lower() or None,
                        "execution_mode": str(execution_mode or "").strip().lower() or None,
                        "order_number": (int(order_number) if order_number is not None else None),
                        "deal_number": (int(deal_number) if deal_number is not None else None),
                        "trace_id": str(trace_id or "").strip() or None,
                        "stage": str(stage or "").strip().lower() or None,
                        "stage_status": str(stage_status or "").strip().lower() or None,
                        "stage_payload": (dict(stage_payload) if isinstance(stage_payload, dict) else None),
                        "error_code": str(error_code or "").strip().lower() or None,
                    },
                )
                db.add(model)
                db.commit()
                break
            except Exception as exc:
                try:
                    db.rollback()
                except Exception:
                    pass
                msg = str(exc or "").lower()
                if "database is locked" in msg and attempt < 7:
                    time.sleep(min(0.40, 0.05 * float(attempt + 1)))
                    continue
                logger.exception("telegram_automation_execution_log_persist_failed")
                break
            finally:
                try:
                    db.close()
                except Exception:
                    pass

    def get_automation_execution_logs(self, *, limit: int = 200) -> List[Dict[str, Any]]:
        self._ensure_execution_log_table()
        lim = int(max(20, min(1000, int(limit or 200))))
        db = SessionLocal()
        try:
            rows_rev = (
                db.query(TelegramAutomationExecutionLogModel)
                .order_by(TelegramAutomationExecutionLogModel.id.desc())
                .limit(int(lim))
                .all()
            )
        except Exception:
            logger.exception("telegram_automation_execution_log_read_failed")
            return []
        finally:
            try:
                db.close()
            except Exception:
                pass

        out: List[Dict[str, Any]] = []
        for r in reversed(list(rows_rev)):
            created = r.created_at if isinstance(r.created_at, datetime) else None
            event_d = r.event_ts if isinstance(r.event_ts, datetime) else None
            created_iso = (
                created.replace(tzinfo=timezone.utc).isoformat()
                if isinstance(created, datetime)
                else self._now_iso()
            )
            event_iso = (
                event_d.replace(tzinfo=timezone.utc).isoformat()
                if isinstance(event_d, datetime)
                else created_iso
            )
            out.append(
                {
                    "id": int(r.id or 0),
                    "ts": str(created_iso),
                    "event_ts": str(event_iso),
                    "source_type": str(r.source_type or "unknown"),
                    "source_name": str(r.source_name or "unknown"),
                    "trigger": str(r.trigger or "unknown"),
                    "status": str(r.status or "unknown"),
                    "symbol": str(r.symbol or ""),
                    "timeframe": str(r.timeframe or ""),
                    "direction": str(r.direction or ""),
                    "lot": _to_float_or_none(r.lot),
                    "stop_loss": _to_float_or_none(r.stop_loss),
                    "final_tp": _to_float_or_none(r.final_tp),
                    "stages_total": (int(r.stages_total) if r.stages_total is not None else None),
                    "stages_opened": (int(r.stages_opened) if r.stages_opened is not None else None),
                    "ticket": (int(r.ticket) if r.ticket is not None else None),
                    "message": str(r.message or ""),
                    "profile": str(r.profile or ""),
                    "indicator": str(r.indicator or ""),
                    "source_tag": str(r.source_tag or ""),
                    "realized_pnl": _to_float_or_none((_json_obj(r.extra_json or {})).get("realized_pnl")),
                    "max_profit": _to_float_or_none((_json_obj(r.extra_json or {})).get("max_profit")),
                    "max_loss": _to_float_or_none((_json_obj(r.extra_json or {})).get("max_loss")),
                    "close_reason": str((_json_obj(r.extra_json or {})).get("close_reason") or ""),
                    "opened_at": str((_json_obj(r.extra_json or {})).get("opened_at") or ""),
                    "combo_key": str((_json_obj(r.extra_json or {})).get("combo_key") or ""),
                    "execution_mode": str((_json_obj(r.extra_json or {})).get("execution_mode") or ""),
                    "order_number": (int(_to_float_or_none((_json_obj(r.extra_json or {})).get("order_number")) or 0) or None),
                    "deal_number": (int(_to_float_or_none((_json_obj(r.extra_json or {})).get("deal_number")) or 0) or None),
                    "trace_id": str((_json_obj(r.extra_json or {})).get("trace_id") or ""),
                    "stage": str((_json_obj(r.extra_json or {})).get("stage") or ""),
                    "stage_status": str((_json_obj(r.extra_json or {})).get("stage_status") or ""),
                    "stage_payload": (_json_obj((_json_obj(r.extra_json or {})).get("stage_payload"))),
                    "error_code": str((_json_obj(r.extra_json or {})).get("error_code") or ""),
                }
            )
        return out

    def _ensure_execution_log_table(self) -> None:
        with self._lock:
            if bool(self._execution_log_table_ready):
                return
        try:
            TelegramAutomationExecutionLogModel.__table__.create(bind=engine, checkfirst=True)
        except Exception:
            logger.exception("telegram_automation_execution_log_table_ensure_failed")
            return
        with self._lock:
            self._execution_log_table_ready = True

    @staticmethod
    def _execution_report_lookback_days() -> int:
        try:
            raw = int(float(TelegramBridgeService._get_env_value("TELEGRAM_EXECUTION_REPORT_LOOKBACK_DAYS", "14")))
        except Exception:
            raw = 14
        return max(1, min(60, int(raw)))

    @staticmethod
    def _execution_close_dedupe_window_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_EXECUTION_CLOSE_DEDUPE_SEC", "120"))
        except Exception:
            raw = 120.0
        if not math.isfinite(float(raw)):
            raw = 120.0
        return max(5.0, min(86400.0, float(raw)))

    def _should_log_ticket_close(self, ticket: int) -> bool:
        try:
            t = int(ticket)
        except Exception:
            t = 0
        if t <= 0:
            return True
        now_ts = float(time.time())
        with self._lock:
            prev = float(self._execution_close_dedupe.get(t) or 0.0)
            if prev > 0.0 and (now_ts - prev) <= float(self._execution_close_dedupe_window_sec()):
                return False
            self._execution_close_dedupe[t] = now_ts
            if len(self._execution_close_dedupe) > 5000:
                cutoff = now_ts - 86400.0
                self._execution_close_dedupe = {
                    int(k): float(v)
                    for k, v in self._execution_close_dedupe.items()
                    if float(v) >= cutoff
                }
        return True

    def _resolve_position_realized_stats(
        self,
        *,
        svc: LiveTradingService,
        ticket: int,
        symbol: Optional[str] = None,
    ) -> Dict[str, Any]:
        t = int(ticket or 0)
        if t <= 0:
            return {"realized_pnl": None, "close_count": 0, "last_close_ts": None}
        try:
            deals = svc.get_position_deals(
                position_ticket=int(t),
                days=int(self._execution_report_lookback_days()),
                symbol=(str(symbol or "").strip() or None),
            )
        except Exception:
            deals = []
        realized = 0.0
        close_count = 0
        last_close_ts: Optional[str] = None
        for d in deals:
            if not isinstance(d, dict):
                continue
            entry_code = int(_to_float_or_none(d.get("entry_code")) or 0)
            if entry_code not in {1, 2, 3}:
                continue
            profit = _to_float_or_none(d.get("profit")) or 0.0
            commission = _to_float_or_none(d.get("commission")) or 0.0
            swap = _to_float_or_none(d.get("swap")) or 0.0
            realized += float(profit + commission + swap)
            close_count += 1
            ts = str(d.get("time") or "").strip()
            if ts and (not last_close_ts or ts > last_close_ts):
                last_close_ts = ts
        if close_count <= 0:
            return {"realized_pnl": None, "close_count": 0, "last_close_ts": None}
        return {
            "realized_pnl": float(realized),
            "close_count": int(close_count),
            "last_close_ts": str(last_close_ts or ""),
        }

    @staticmethod
    def _is_bridge_source_tag(value: Any) -> bool:
        tag = str(value or "").strip().lower()
        return bool(tag.startswith("mt4|") or tag.startswith("mt5|"))

    @classmethod
    def _source_type_from_source_tag(cls, value: Any) -> str:
        return "mt_indicator" if cls._is_bridge_source_tag(value) else "telegram_channel"

    def _append_closed_execution_log_from_row(
        self,
        *,
        row: Dict[str, Any],
        reason: str,
        svc: Optional[LiveTradingService] = None,
        event_ts: Optional[Any] = None,
    ) -> None:
        meta = dict(row or {})
        ticket = int(_to_float_or_none(meta.get("broker_ticket")) or 0)
        if ticket <= 0:
            return
        if not self._should_log_ticket_close(int(ticket)):
            return
        service = svc if isinstance(svc, LiveTradingService) else self._get_live_service()
        symbol = str(meta.get("symbol") or "").strip().upper()
        pnl_stats = self._resolve_position_realized_stats(
            svc=service,
            ticket=int(ticket),
            symbol=symbol,
        )
        max_profit = _to_float_or_none(meta.get("max_profit"))
        max_loss = _to_float_or_none(meta.get("max_loss"))
        stage_lots = meta.get("stage_lots") if isinstance(meta.get("stage_lots"), list) else []
        total_lot = 0.0
        for x in stage_lots:
            v = _to_float_or_none(x)
            if v is not None and float(v) > 0.0:
                total_lot += float(v)
        lot_val = float(total_lot) if total_lot > 0.0 else None
        combo_key = self._build_execution_combo_key(
            source_type=self._source_type_from_source_tag(meta.get("source_tag")),
            source_name=str(meta.get("source_name") or "unknown"),
            indicator=str(meta.get("indicator") or "").strip(),
            symbol=symbol,
            timeframe=str(meta.get("timeframe") or "").strip().upper(),
        )
        self._append_automation_execution_log(
            source_type=self._source_type_from_source_tag(meta.get("source_tag")),
            source_name=str(meta.get("source_name") or "unknown"),
            trigger="position_closed",
            status="closed",
            symbol=symbol,
            timeframe=str(meta.get("timeframe") or ""),
            direction=str(meta.get("direction") or "").strip().upper(),
            lot=lot_val,
            ticket=int(ticket),
            message=str(reason or "closed"),
            profile=str(meta.get("profile") or "").strip().lower(),
            indicator=str(meta.get("indicator") or "").strip(),
            source_tag=str(meta.get("source_tag") or "").strip().lower(),
            event_ts=(event_ts if event_ts is not None else pnl_stats.get("last_close_ts")),
            realized_pnl=_to_float_or_none(pnl_stats.get("realized_pnl")),
            max_profit=max_profit,
            max_loss=max_loss,
            close_reason=str(reason or "").strip() or "closed",
            opened_at=str(meta.get("created_at") or "").strip() or None,
            combo_key=str(combo_key),
            execution_mode=str(meta.get("execution_mode") or "").strip().lower() or None,
            trace_id=str(meta.get("trace_id") or "").strip() or None,
            stage="position_close",
            stage_status="closed",
            error_code=str(reason or "").strip().lower() or None,
        )
        self._mark_reentry_progress_from_execution(
            source_key=str(meta.get("source_key") or ""),
            symbol=str(symbol),
            direction=str(meta.get("direction") or "").strip().upper(),
            event_kind=str(reason or "closed"),
        )

    @staticmethod
    def _build_execution_combo_key(
        *,
        source_type: Any,
        source_name: Any,
        indicator: Any,
        symbol: Any,
        timeframe: Any,
    ) -> str:
        st = str(source_type or "").strip().lower() or "unknown"
        src_name = str(source_name or "").strip().lower() or "unknown"
        ind = str(indicator or "").strip().lower()
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        base = ind if (st == "mt_indicator" and ind) else src_name
        return f"{st}|{base}|{sym}|{tf}"

    def get_mt4_indicator_bot_monitor(
        self,
        *,
        limit: int = 300,
        instance_rows: Optional[List[Dict[str, Any]]] = None,
        recent_events: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        lim = int(max(10, min(1000, int(limit or 300))))
        with self._lock:
            ladders = [dict(v) for v in self._active_confirmation_signal_ladders.values() if isinstance(v, dict)]
        mt4_rows = [r for r in ladders if str(r.get("source_tag") or "").strip().lower().startswith("mt4|")]

        svc = self._get_live_service()
        symbols = sorted({str(r.get("symbol") or "").strip().upper() for r in mt4_rows if str(r.get("symbol") or "").strip()})
        open_by_symbol: Dict[str, List[Dict[str, Any]]] = {}
        for sym in symbols:
            try:
                open_by_symbol[str(sym)] = [dict(x) for x in (svc.get_open_positions(symbol=str(sym)) or []) if isinstance(x, dict)]
            except Exception:
                open_by_symbol[str(sym)] = []

        rows: List[Dict[str, Any]] = []
        for row in mt4_rows:
            ticket = int(_to_float_or_none(row.get("broker_ticket")) or 0)
            symbol = str(row.get("symbol") or "").strip().upper()
            timeframe = str(row.get("timeframe") or "").strip().upper()
            direction = str(row.get("direction") or "").strip().upper()
            source_name = str(row.get("source_name") or "unknown").strip() or "unknown"
            indicator = str(row.get("indicator") or "").strip()
            profile = str(row.get("profile") or "").strip().lower()
            tps = row.get("tps") if isinstance(row.get("tps"), list) else []
            next_tp_index = int(row.get("next_tp_index") or 1)
            pos_rows = list(open_by_symbol.get(symbol) or [])
            live_pos = next((p for p in pos_rows if int(_to_float_or_none(p.get("ticket")) or 0) == ticket), None)
            current_profit = _to_float_or_none((live_pos or {}).get("profit_loss"))
            current_price = _to_float_or_none((live_pos or {}).get("current_price"))
            rows.append(
                {
                    "source_name": str(source_name),
                    "indicator": str(indicator),
                    "profile": str(profile),
                    "symbol": str(symbol),
                    "timeframe": str(timeframe),
                    "direction": str(direction),
                    "ticket": int(ticket),
                    "opened_at": str(row.get("created_at") or ""),
                    "next_tp_index": int(next_tp_index),
                    "total_tps": int(len(tps)),
                    "max_profit": _to_float_or_none(row.get("max_profit")),
                    "max_loss": _to_float_or_none(row.get("max_loss")),
                    "current_profit": _to_float_or_none(current_profit),
                    "current_price": _to_float_or_none(current_price),
                    "source_tag": str(row.get("source_tag") or "").strip().lower(),
                    "combo_key": self._build_execution_combo_key(
                        source_type="mt_indicator",
                        source_name=source_name,
                        indicator=indicator,
                        symbol=symbol,
                        timeframe=timeframe,
                    ),
                }
            )
        rows.sort(key=lambda r: str(r.get("opened_at") or ""), reverse=True)
        rows = rows[:lim]

        def _infer_profile_from_indicator(indicator_name: str) -> str:
            key = self._normalize_mt_indicator_key(indicator_name)
            if ("supply demand" in key) or ("zulu wave arrows" in key):
                return "supplydemand"
            if "intrepid" in key:
                return "intrepid"
            if "hydra" in key:
                return "hydra"
            if "uranus" in key:
                return "uranus"
            if "alchemy" in key:
                return "alchemy"
            if "fxnuke" in key:
                return "fxnuke"
            if "forexcyper" in key or "cyper" in key:
                return "forexcyper"
            return "generic"

        def _instance_combo_key(indicator_name: str, symbol_name: str, timeframe_name: str) -> str:
            return (
                f"{self._normalize_mt_indicator_key(indicator_name)}|"
                f"{str(symbol_name or '').strip().upper()}|"
                f"{str(timeframe_name or '').strip().upper()}"
            ).lower()

        def _extract_bridge_chart_row(ev: Dict[str, Any]) -> Optional[Dict[str, Any]]:
            if not isinstance(ev, dict):
                return None
            if str(ev.get("terminal_group") or "").strip().lower() != "mt4":
                return None
            ind_key = str(ev.get("indicator_key") or "").strip().lower()
            ind_name = str(ev.get("indicator") or "").strip().lower()
            if ind_key != "protrading_mt4_bridge_ea" and "protrading_mt4_bridge_ea" not in ind_name:
                return None

            symbol = str(ev.get("symbol") or "").strip().upper()
            timeframe = str(ev.get("timeframe") or "").strip().upper()
            msg = str(ev.get("message") or ev.get("raw") or "").strip()
            ev_ts = str(ev.get("event_ts") or "").strip()
            profile = str(ev.get("signal_profile") or "").strip().lower()
            resolved_indicator = ""

            m_init = re.search(
                r"MT4Bridge initialized:\s*(.+?)\s*\|\s*([A-Z0-9_]+)\s+([A-Z0-9_]+)",
                msg,
                flags=re.IGNORECASE,
            )
            if m_init:
                resolved_indicator = str(m_init.group(1) or "").strip()
                symbol = symbol or str(m_init.group(2) or "").strip().upper()
                timeframe = timeframe or str(m_init.group(3) or "").strip().upper()

            if not resolved_indicator:
                m_input_indicator = re.search(r"InpIndicatorName\s*=\s*([^;\r\n]+)", msg, flags=re.IGNORECASE)
                if m_input_indicator:
                    resolved_indicator = str(m_input_indicator.group(1) or "").strip()
            if not profile:
                m_input_profile = re.search(r"InpSignalProfile\s*=\s*([^;\r\n]+)", msg, flags=re.IGNORECASE)
                if m_input_profile:
                    profile = str(m_input_profile.group(1) or "").strip().lower()
            if not resolved_indicator:
                m_json = re.search(r"\"indicator\"\s*:\s*\"([^\"]+)\"", msg)
                if m_json:
                    resolved_indicator = str(m_json.group(1) or "").strip()

            resolved_indicator = self._normalize_mt4_indicator_name(resolved_indicator) or resolved_indicator
            if not resolved_indicator or not symbol or not timeframe:
                return None

            profile = str(profile or _infer_profile_from_indicator(resolved_indicator)).strip().lower()
            if not profile or profile == "generic":
                return None
            runtime_cfg = self._resolve_mt4_instance_runtime_config(
                indicator=str(resolved_indicator),
                symbol=str(symbol),
                timeframe=str(timeframe),
            )

            combo_key = self._build_execution_combo_key(
                source_type="mt_indicator",
                source_name=resolved_indicator,
                indicator=resolved_indicator,
                symbol=symbol,
                timeframe=timeframe,
            )
            ckey = str(combo_key or "").strip().lower()
            if not ckey:
                return None
            return {
                "indicator": str(resolved_indicator),
                "symbol": str(symbol),
                "timeframe": str(timeframe),
                "instance_key": str(runtime_cfg.get("instance_key") or ev.get("instance_key") or f"{resolved_indicator}|{symbol}|{timeframe}"),
                "lot_size": _to_float_or_none(runtime_cfg.get("lot_size")),
                "automation_mode": "bridge",
                "control_mode": str(runtime_cfg.get("automation_mode") or "inherit"),
                "automation_enabled": bool(runtime_cfg.get("automation_enabled")),
                "effective_automation_enabled": bool(runtime_cfg.get("effective_automation_enabled")),
                "mode_advanced_enabled": bool(runtime_cfg.get("mode_advanced_enabled")),
                "mode_normal_enabled": bool(runtime_cfg.get("mode_normal_enabled")),
                "mode_sync_enabled": bool(runtime_cfg.get("mode_sync_enabled")),
                "sync": dict(runtime_cfg.get("sync") or {}),
                "last_seen": str(ev_ts),
                "source_tag": f"mt4|{profile}|{self._normalize_mt_indicator_key(resolved_indicator)}|{symbol}|{timeframe}",
                "combo_key": ckey,
                "bridge_active": True,
            }

        ladder_by_instance: Dict[str, Dict[str, Any]] = {}
        for row in rows:
            ckey = _instance_combo_key(
                str(row.get("indicator") or row.get("source_name") or ""),
                str(row.get("symbol") or ""),
                str(row.get("timeframe") or ""),
            )
            if ckey:
                ladder_by_instance[ckey] = dict(row)

        bot_rows: List[Dict[str, Any]] = []
        if isinstance(instance_rows, list):
            for inst in instance_rows:
                if not isinstance(inst, dict):
                    continue
                effective_enabled = bool(inst.get("effective_automation_enabled"))
                if not effective_enabled:
                    continue
                group = str(inst.get("last_terminal_group") or "").strip().lower()
                if group == "mt4":
                    # MT4 charts are bridge-driven. Do not surface log-instance
                    # rows here, otherwise monitor mixes bridge and log sources.
                    continue
                if group and group not in {"mt5", "mt5_demo", "unknown"}:
                    continue
                indicator = str(inst.get("indicator") or inst.get("indicator_key") or "").strip()
                symbol = str(inst.get("symbol") or "").strip().upper()
                timeframe = str(inst.get("timeframe") or "").strip().upper()
                if not indicator or not symbol or not timeframe:
                    continue
                combo = _instance_combo_key(indicator, symbol, timeframe)
                linked_ladder = dict(ladder_by_instance.get(combo) or {})
                profile = str(inst.get("last_signal_profile") or "").strip().lower() or _infer_profile_from_indicator(indicator)
                indicator_key = self._normalize_mt_indicator_key(indicator)
                source_tag = f"mt4|{profile}|{indicator_key}|{symbol}|{timeframe}"
                bot_rows.append(
                    {
                        "indicator": str(indicator),
                        "symbol": str(symbol),
                        "timeframe": str(timeframe),
                        "instance_key": str(inst.get("instance_key") or combo),
                        "lot_size": _to_float_or_none(inst.get("lot_size")),
                        "automation_mode": str(inst.get("automation_mode") or "inherit").strip().lower() or "inherit",
                        "effective_automation_enabled": bool(effective_enabled),
                        "last_seen": str(inst.get("last_seen") or ""),
                        "source_tag": str(source_tag),
                        "combo_key": self._build_execution_combo_key(
                            source_type="mt_indicator",
                            source_name=str(indicator),
                            indicator=str(indicator),
                            symbol=str(symbol),
                            timeframe=str(timeframe),
                        ),
                        "has_open_ladder": bool(linked_ladder),
                        "ladder_ticket": int(_to_float_or_none(linked_ladder.get("ticket")) or 0),
                    }
                )

        # Fallback for iCustom Bridge mode:
        # include MT4 Bridge EA chart instances even when MT4 log-automation
        # indicator/instance toggles are disabled.
        if isinstance(recent_events, list):
            existing_combo_keys = {str(r.get("combo_key") or "").strip().lower() for r in bot_rows}
            bridge_by_key: Dict[str, Dict[str, Any]] = {}
            for ev in recent_events:
                row = _extract_bridge_chart_row(ev)
                if not isinstance(row, dict):
                    continue
                ckey = str(row.get("combo_key") or "").strip().lower()
                prev = bridge_by_key.get(ckey)
                if prev is None or str(row.get("last_seen") or "") > str(prev.get("last_seen") or ""):
                    bridge_by_key[ckey] = dict(row)
            for ckey, row in bridge_by_key.items():
                if ckey in existing_combo_keys:
                    for idx, existing in enumerate(bot_rows):
                        if str((existing or {}).get("combo_key") or "").strip().lower() != ckey:
                            continue
                        merged_existing = dict(existing or {})
                        merged_existing["automation_mode"] = "bridge"
                        merged_existing["control_mode"] = str(row.get("control_mode") or merged_existing.get("control_mode") or merged_existing.get("automation_mode") or "inherit")
                        merged_existing["automation_enabled"] = bool(row.get("automation_enabled"))
                        merged_existing["effective_automation_enabled"] = bool(row.get("effective_automation_enabled"))
                        merged_existing["lot_size"] = _to_float_or_none(row.get("lot_size")) or _to_float_or_none(merged_existing.get("lot_size"))
                        merged_existing["bridge_active"] = True
                        merged_existing["last_seen"] = str(row.get("last_seen") or merged_existing.get("last_seen") or "")
                        merged_existing["instance_key"] = str(row.get("instance_key") or merged_existing.get("instance_key") or "")
                        bot_rows[idx] = merged_existing
                        break
                    continue
                linked_ladder = dict(ladder_by_instance.get(
                    _instance_combo_key(
                        str(row.get("indicator") or ""),
                        str(row.get("symbol") or ""),
                        str(row.get("timeframe") or ""),
                    )
                ) or {})
                merged = dict(row)
                merged["bridge_active"] = True
                merged["has_open_ladder"] = bool(linked_ladder)
                merged["ladder_ticket"] = int(_to_float_or_none(linked_ladder.get("ticket")) or 0)
                bot_rows.append(merged)
        bot_rows.sort(key=lambda r: str(r.get("last_seen") or ""), reverse=True)
        bot_rows = bot_rows[:lim]
        bot_open_count = len([r for r in bot_rows if bool(r.get("has_open_ladder"))])
        bot_idle_count = len([r for r in bot_rows if bool(r.get("effective_automation_enabled")) and not bool(r.get("has_open_ladder"))])
        return {
            "ok": True,
            "updated_at": self._now_iso(),
            "active_count": int(len(rows)),
            "rows": rows,
            "bot_active_count": int(len([r for r in bot_rows if bool(r.get("effective_automation_enabled"))])),
            "bot_open_count": int(bot_open_count),
            "bot_idle_count": int(bot_idle_count),
            "bot_rows": bot_rows,
        }

    def get_automation_execution_report(self, *, limit: int = 200) -> Dict[str, Any]:
        rows = self.get_automation_execution_logs(limit=max(200, min(5000, int(limit or 200))))
        combos: Dict[str, Dict[str, Any]] = {}

        for r in rows:
            if not isinstance(r, dict):
                continue
            source_type = str(r.get("source_type") or "unknown").strip().lower() or "unknown"
            source_name = str(r.get("source_name") or "unknown").strip() or "unknown"
            indicator = str(r.get("indicator") or "").strip()
            symbol = str(r.get("symbol") or "").strip().upper()
            timeframe = str(r.get("timeframe") or "").strip().upper()
            base_name = indicator if (source_type == "mt_indicator" and indicator) else source_name
            key = f"{source_type}|{base_name.lower()}|{symbol}|{timeframe}"
            row = combos.get(key)
            if row is None:
                row = {
                    "source_type": source_type,
                    "source_name": source_name,
                    "indicator": indicator,
                    "symbol": symbol,
                    "timeframe": timeframe,
                    "combo_name": base_name,
                    "opened_count": 0,
                    "closed_count": 0,
                    "failed_count": 0,
                    "win_count": 0,
                    "loss_count": 0,
                    "total_realized_pnl": 0.0,
                    "best_trade_pnl": None,
                    "worst_trade_pnl": None,
                }
                combos[key] = row

            status = str(r.get("status") or "").strip().lower()
            if status == "opened":
                row["opened_count"] = int(row.get("opened_count") or 0) + 1
            elif status in {"failed", "deferred", "rejected"}:
                row["failed_count"] = int(row.get("failed_count") or 0) + 1
            elif status == "closed":
                row["closed_count"] = int(row.get("closed_count") or 0) + 1
                pnl = _to_float_or_none(r.get("realized_pnl"))
                if pnl is not None:
                    row["total_realized_pnl"] = float(row.get("total_realized_pnl") or 0.0) + float(pnl)
                    best = _to_float_or_none(row.get("best_trade_pnl"))
                    worst = _to_float_or_none(row.get("worst_trade_pnl"))
                    row["best_trade_pnl"] = float(pnl) if (best is None or float(pnl) > float(best)) else float(best)
                    row["worst_trade_pnl"] = float(pnl) if (worst is None or float(pnl) < float(worst)) else float(worst)
                    if float(pnl) >= 0.0:
                        row["win_count"] = int(row.get("win_count") or 0) + 1
                    else:
                        row["loss_count"] = int(row.get("loss_count") or 0) + 1

        out_rows = [dict(v) for v in combos.values()]
        for r in out_rows:
            closed = int(r.get("closed_count") or 0)
            total = float(r.get("total_realized_pnl") or 0.0)
            r["avg_realized_pnl"] = (float(total) / float(closed)) if closed > 0 else 0.0
            wins = int(r.get("win_count") or 0)
            r["win_rate_pct"] = (float(wins) * 100.0 / float(closed)) if closed > 0 else 0.0
        out_rows.sort(key=lambda x: (float(x.get("total_realized_pnl") or 0.0), float(x.get("avg_realized_pnl") or 0.0)), reverse=True)
        lim = int(max(10, min(1000, int(limit or 200))))
        out_rows = out_rows[:lim]
        return {
            "ok": True,
            "rows": out_rows,
            "count": int(len(out_rows)),
            "generated_at": self._now_iso(),
        }

    def get_telegram_automation_state(self, *, limit: int = 120) -> Dict[str, Any]:
        lim = int(max(20, min(500, int(limit or 120))))
        with self._lock:
            raw_feed = [dict(r) for r in self._confirm_signal_feed[-(lim * 4) :]]
            pending = [dict(v) for v in self._pending_confirmation_signals.values()]
            pending_entry = [dict(v) for v in self._pending_entry_signals.values()]
            active = [dict(v) for v in self._active_confirmation_signal_ladders.values()]
        exec_logs = self.get_automation_execution_logs(limit=lim)
        exec_report = self.get_automation_execution_report(limit=200)
        # Defensive read-time de-duplication so legacy duplicated rows do not spam UI.
        # Keep newest instance for source_message_id-keyed events.
        deduped_rev: List[Dict[str, Any]] = []
        seen_keys: set[str] = set()
        for r in reversed(raw_feed):
            try:
                smid = int((r or {}).get("source_message_id") or 0)
            except Exception:
                smid = 0
            if smid > 0:
                sname = self._normalize_confirm_source_name((r or {}).get("source"))
                key = f"{sname}|{int(smid)}" if sname else f"|{int(smid)}"
                if key in seen_keys:
                    continue
                seen_keys.add(key)
            deduped_rev.append(dict(r))
            if len(deduped_rev) >= lim:
                break
        feed = list(reversed(deduped_rev))
        return {
            "ok": True,
            "config": {
                "enabled": bool(self._confirm_signal_enabled()),
                "channels": list(self._confirm_signal_channel_titles()),
                "default_timeframe": str(self._confirm_signal_default_timeframe()),
                "default_lot": float(self._confirm_signal_default_lot()),
                "force_single_trade_01": bool(self._confirm_signal_force_single_trade_01()),
                "allow_message_single_trade_override": bool(self._confirm_signal_allow_message_single_trade_override()),
                "distribution_mode": str(self._confirm_signal_tp_distribution_mode()),
                "require_confirm": bool(self._confirm_signal_requires_confirm()),
                "require_confirm_channels": list(self._confirm_signal_require_confirm_titles()),
                "no_confirm_channels": list(self._confirm_signal_no_confirm_titles()),
                "confirm_window_sec": float(self._confirm_signal_confirm_window_sec()),
                "wait_entry_zone": bool(self._confirm_signal_wait_entry_zone()),
                "entry_wait_max_sec": float(self._confirm_signal_entry_wait_max_sec()),
                "entry_attempt_cooldown_sec": float(self._confirm_signal_entry_attempt_cooldown_sec()),
                "entry_watch_interval_sec": float(self._confirm_signal_entry_watch_interval_sec()),
                "evaluation_mode": str(self._confirm_signal_eval_mode()),
                "ai_provider": str(self._confirm_signal_ai_provider()),
                "ai_model": str(self._confirm_signal_ai_model()),
                "ai_timeout_sec": float(self._confirm_signal_ai_timeout_sec()),
            },
            "pending_confirm_count": int(len(pending)),
            "pending_entry_count": int(len(pending_entry)),
            "active_ladder_count": int(len(active)),
            "feed": feed,
            "execution_logs": exec_logs,
            "execution_report": exec_report,
        }

    def update_telegram_automation_config(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        p = payload if isinstance(payload, dict) else {}
        channels_raw = p.get("channels")
        channels: List[str] = []
        if isinstance(channels_raw, str):
            channels = [str(x).strip() for x in re.split(r"[\n|,]+", str(channels_raw)) if str(x).strip()]
        elif isinstance(channels_raw, list):
            channels = [str(x).strip() for x in channels_raw if str(x).strip()]
        updates: Dict[str, Any] = {}
        if "enabled" in p:
            updates["TELEGRAM_CONFIRM_SIGNALS_ENABLED"] = "1" if bool(p.get("enabled")) else "0"
        if channels:
            updates["TELEGRAM_CONFIRM_SIGNAL_CHANNEL_TITLES"] = "|".join(channels)
        if "default_timeframe" in p:
            tf = str(p.get("default_timeframe") or "M5").strip().upper()
            updates["TELEGRAM_CONFIRM_SIGNAL_DEFAULT_TIMEFRAME"] = tf or "M5"
        if "default_lot" in p:
            lot = _to_float_or_none(p.get("default_lot"))
            if lot is not None and lot > 0.0:
                updates["TELEGRAM_CONFIRM_SIGNAL_DEFAULT_LOT"] = f"{float(lot):.4f}"
        if "force_single_trade_01" in p:
            updates["TELEGRAM_CONFIRM_SIGNAL_FORCE_SINGLE_TRADE_01"] = "1" if bool(p.get("force_single_trade_01")) else "0"
        if "allow_message_single_trade_override" in p:
            updates["TELEGRAM_CONFIRM_SIGNAL_ALLOW_MESSAGE_SINGLE_TRADE_OVERRIDE"] = (
                "1" if bool(p.get("allow_message_single_trade_override")) else "0"
            )
        if "distribution_mode" in p:
            mode = str(p.get("distribution_mode") or "equal").strip().lower()
            if mode not in {"equal", "front_loaded", "runner"}:
                mode = "equal"
            updates["TELEGRAM_CONFIRM_SIGNAL_TP_DISTRIBUTION"] = mode
        if "require_confirm" in p:
            updates["TELEGRAM_CONFIRM_SIGNAL_REQUIRE_CONFIRM"] = "1" if bool(p.get("require_confirm")) else "0"
        if "require_confirm_channels" in p:
            raw = p.get("require_confirm_channels")
            vals: List[str] = []
            if isinstance(raw, str):
                vals = [str(x).strip() for x in re.split(r"[\n|,]+", raw) if str(x).strip()]
            elif isinstance(raw, list):
                vals = [str(x).strip() for x in raw if str(x).strip()]
            updates["TELEGRAM_CONFIRM_SIGNAL_REQUIRE_CONFIRM_CHANNEL_TITLES"] = "|".join(vals)
        if "no_confirm_channels" in p:
            raw = p.get("no_confirm_channels")
            vals: List[str] = []
            if isinstance(raw, str):
                vals = [str(x).strip() for x in re.split(r"[\n|,]+", raw) if str(x).strip()]
            elif isinstance(raw, list):
                vals = [str(x).strip() for x in raw if str(x).strip()]
            updates["TELEGRAM_CONFIRM_SIGNAL_NO_CONFIRM_CHANNEL_TITLES"] = "|".join(vals)
        if "confirm_window_sec" in p:
            sec = _to_float_or_none(p.get("confirm_window_sec"))
            if sec is not None and sec > 0:
                updates["TELEGRAM_CONFIRM_SIGNAL_CONFIRM_WINDOW_SEC"] = f"{int(max(30, min(7200, int(sec))))}"
        if "wait_entry_zone" in p:
            updates["TELEGRAM_CONFIRM_SIGNAL_WAIT_ENTRY_ZONE"] = "1" if bool(p.get("wait_entry_zone")) else "0"
        if "entry_wait_max_sec" in p:
            sec = _to_float_or_none(p.get("entry_wait_max_sec"))
            if sec is not None and sec > 0:
                updates["TELEGRAM_CONFIRM_SIGNAL_ENTRY_WAIT_MAX_SEC"] = f"{int(max(30, min(14400, int(sec))))}"
        if "entry_attempt_cooldown_sec" in p:
            sec = _to_float_or_none(p.get("entry_attempt_cooldown_sec"))
            if sec is not None and sec > 0:
                updates["TELEGRAM_CONFIRM_SIGNAL_ENTRY_ATTEMPT_COOLDOWN_SEC"] = f"{float(max(0.1, min(30.0, float(sec)))):.2f}"
        if "entry_watch_interval_sec" in p:
            sec = _to_float_or_none(p.get("entry_watch_interval_sec"))
            if sec is not None and sec > 0:
                updates["TELEGRAM_CONFIRM_SIGNAL_ENTRY_WATCH_INTERVAL_SEC"] = f"{float(max(0.05, min(2.0, float(sec)))):.2f}"
        if "evaluation_mode" in p:
            mode = str(p.get("evaluation_mode") or "deterministic").strip().lower()
            if mode not in {"deterministic", "ai_assist"}:
                mode = "deterministic"
            updates["TELEGRAM_CONFIRM_SIGNAL_EVAL_MODE"] = mode
        if "ai_provider" in p:
            prov = str(p.get("ai_provider") or "claude").strip().lower()
            if prov not in {"claude", "openai"}:
                prov = "claude"
            updates["TELEGRAM_CONFIRM_SIGNAL_AI_PROVIDER"] = prov
        if "ai_model" in p:
            mdl = str(p.get("ai_model") or "").strip()
            if mdl:
                updates["TELEGRAM_CONFIRM_SIGNAL_AI_MODEL"] = mdl
        if "ai_timeout_sec" in p:
            sec = _to_float_or_none(p.get("ai_timeout_sec"))
            if sec is not None and sec > 0:
                updates["TELEGRAM_CONFIRM_SIGNAL_AI_TIMEOUT_SEC"] = f"{float(max(2.0, min(30.0, float(sec)))):.1f}"
        ok, status = self._upsert_env_values(updates)
        state = self.get_telegram_automation_state(limit=120)
        state["persist_ok"] = bool(ok)
        state["persist_status"] = str(status)
        state["updated"] = {str(k): str(v) for k, v in updates.items()}
        return state

    def evaluate_confirmation_signal_ai(self, *, text: str, parsed_signal: Dict[str, Any]) -> Dict[str, Any]:
        mode = self._confirm_signal_eval_mode()
        if mode != "ai_assist":
            return {"ok": True, "mode": "deterministic", "allow": True, "reason": "deterministic_mode"}
        provider = self._confirm_signal_ai_provider()
        timeout = float(self._confirm_signal_ai_timeout_sec())
        model = self._confirm_signal_ai_model()
        if provider == "claude":
            api_key = str(self._get_env_value("CLAUDE_API_KEY", "") or self._get_env_value("ANTHROPIC_API_KEY", "")).strip()
            if not api_key:
                return {"ok": True, "mode": "ai_assist", "provider": "claude", "allow": True, "reason": "missing_api_key_fallback"}
            url = "https://api.anthropic.com/v1/messages"
            prompt = (
                "You are a strict signal validator. Return JSON only: "
                "{\"allow\":true|false,\"reason\":\"...\"}. "
                "Allow only if message is a valid trading signal with symbol, direction, SL, and TP levels."
                f"\nMessage:\n{text}\nParsed:\n{json.dumps(parsed_signal, ensure_ascii=False)}"
            )
            headers = {
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            }
            body = {
                "model": model,
                "max_tokens": 120,
                "temperature": 0,
                "messages": [{"role": "user", "content": prompt}],
            }
            try:
                with httpx.Client(timeout=timeout, trust_env=False) as client:
                    resp = client.post(url, headers=headers, json=body)
                if int(resp.status_code) != 200:
                    return {"ok": True, "mode": "ai_assist", "provider": "claude", "allow": True, "reason": f"http_{int(resp.status_code)}_fallback"}
                data = resp.json() if "application/json" in str(resp.headers.get("content-type") or "") else {}
                content = data.get("content") if isinstance(data, dict) else None
                text_out = ""
                if isinstance(content, list) and content and isinstance(content[0], dict):
                    text_out = str(content[0].get("text") or "").strip()
                m = re.search(r"\{.*\}", text_out, flags=re.DOTALL)
                parsed = json.loads(m.group(0)) if m else {}
                allow = bool(parsed.get("allow", True)) if isinstance(parsed, dict) else True
                reason = str(parsed.get("reason") or "ai_assist") if isinstance(parsed, dict) else "ai_assist"
                return {"ok": True, "mode": "ai_assist", "provider": "claude", "allow": bool(allow), "reason": reason}
            except Exception as exc:
                return {"ok": True, "mode": "ai_assist", "provider": "claude", "allow": True, "reason": f"error_fallback:{type(exc).__name__}"}
        return {"ok": True, "mode": "ai_assist", "provider": provider, "allow": True, "reason": "provider_not_implemented_fallback"}

    @staticmethod
    def _extract_message_source_names(msg: Optional[Dict[str, Any]], chat: Optional[Dict[str, Any]]) -> List[str]:
        out: List[str] = []
        candidates: List[Any] = []
        if isinstance(chat, dict):
            candidates.extend(
                [
                    chat.get("title"),
                    chat.get("username"),
                    chat.get("first_name"),
                    chat.get("last_name"),
                ]
            )
        if isinstance(msg, dict):
            candidates.extend(
                [
                    msg.get("forward_from_chat"),
                    msg.get("sender_chat"),
                    msg.get("author_signature"),
                ]
            )
            fwd_origin = msg.get("forward_origin") if isinstance(msg.get("forward_origin"), dict) else None
            if isinstance(fwd_origin, dict):
                candidates.extend(
                    [
                        fwd_origin.get("chat"),
                        fwd_origin.get("sender_user_name"),
                        fwd_origin.get("author_signature"),
                    ]
                )
        for item in candidates:
            if isinstance(item, dict):
                vals = [
                    item.get("title"),
                    item.get("username"),
                    item.get("first_name"),
                    item.get("last_name"),
                ]
            else:
                vals = [item]
            for val in vals:
                s = str(val or "").strip()
                if not s:
                    continue
                out.append(s)
                if s.startswith("@"):
                    out.append(s[1:])
        seen: set[str] = set()
        uniq: List[str] = []
        for val in out:
            key = str(val).strip().casefold()
            if not key or key in seen:
                continue
            seen.add(key)
            uniq.append(str(val).strip())
        return uniq

    @classmethod
    def _message_matches_confirm_signal_source(cls, msg: Optional[Dict[str, Any]], chat: Optional[Dict[str, Any]]) -> bool:
        wanted = {cls._normalize_confirm_source_name(x) for x in cls._confirm_signal_channel_titles() if str(x).strip()}
        wanted.discard("")
        if not wanted:
            return False
        got = cls._extract_message_source_names(msg, chat)
        for name in got:
            g = cls._normalize_confirm_source_name(name)
            if not g:
                continue
            for w in wanted:
                if g == w or g in w or w in g:
                    return True
        return False

    @staticmethod
    def _parse_confirmation_signal(text: Any) -> Optional[Dict[str, Any]]:
        raw = str(text or "").replace("\r", "\n")
        if not raw.strip():
            return None
        # Normalize styled/Unicode numerals and separators (e.g. TP1, SL1, full-width glyphs).
        raw_norm = unicodedata.normalize("NFKC", raw)
        head = re.search(
            (
                r"(?im)^\s*#?\s*([A-Z]{3,12})"
                r"(?:\s+#?\s*([A-Z]{3,12}))?"
                r"\s*(?:[_\-\s]+)(BUY|SELL)\s+"
                r"(?:NOW\s+)?([0-9]+(?:\.[0-9]+)?)"
                r"(?:\s*(?:/|-|TO)\s*([0-9]+(?:\.[0-9]+)?))?\s*$"
            ),
            raw_norm,
        )
        if head is None:
            return None

        symbol_raw = str(head.group(1) or "").strip().upper()
        symbol_alt_raw = str(head.group(2) or "").strip().upper()
        symbol = str(TelegramBridgeService._CONFIRM_SIGNAL_SYMBOL_ALIASES.get(symbol_raw, symbol_raw))
        if symbol_alt_raw:
            symbol_alt = str(TelegramBridgeService._CONFIRM_SIGNAL_SYMBOL_ALIASES.get(symbol_alt_raw, symbol_alt_raw))
            if symbol_alt and symbol_alt != symbol and symbol_raw in {"GOLD", "XAU"}:
                symbol = symbol_alt

        direction = str(head.group(3) or "").strip().upper()
        try:
            entry_a = float(head.group(4))
            entry_b = float(head.group(5)) if str(head.group(5) or "").strip() else float(entry_a)
        except Exception:
            return None

        tps: List[Dict[str, Any]] = []
        seen_idx: set[int] = set()
        tp_unindexed: List[float] = []
        indexed_spans: List[Tuple[int, int]] = []

        tp_indexed_iter = re.finditer(
            r"(?im)\bTP\s*([1-9]\d*)(?:\s*[:\-]\s*|\s+)([0-9]+(?:\.[0-9]+)?)\b",
            raw_norm,
        )
        for m in tp_indexed_iter:
            idx_raw = str(m.group(1) or "").strip()
            px_raw = str(m.group(2) or "").strip()
            try:
                idx = int(idx_raw)
                px = float(px_raw)
            except Exception:
                continue
            if idx <= 0 or (not math.isfinite(float(px))) or float(px) <= 0.0 or idx in seen_idx:
                continue
            seen_idx.add(idx)
            indexed_spans.append((int(m.start()), int(m.end())))
            tps.append({"index": int(idx), "price": float(px)})

        tp_plain_iter = re.finditer(
            r"(?im)\bTP\s*[:\-]?\s*([0-9]+(?:\.[0-9]+)?)\b",
            raw_norm,
        )
        for m in tp_plain_iter:
            s = int(m.start())
            e = int(m.end())
            if any(s < se and e > ss for ss, se in indexed_spans):
                continue
            px_raw = str(m.group(1) or "").strip()
            try:
                px = float(px_raw)
            except Exception:
                continue
            if (not math.isfinite(float(px))) or float(px) <= 0.0:
                continue
            tp_unindexed.append(float(px))

        if tp_unindexed:
            next_idx = int(max(seen_idx) + 1) if seen_idx else 1
            for px in tp_unindexed:
                while next_idx in seen_idx:
                    next_idx += 1
                seen_idx.add(next_idx)
                tps.append({"index": int(next_idx), "price": float(px)})
                next_idx += 1

        tps.sort(key=lambda r: int(r.get("index") or 0))

        sl_match = re.search(r"(?im)\bSL(?:[1-9]\d*)?\s*[:\-]?\s*([0-9]+(?:\.[0-9]+)?)\b", raw_norm)
        if sl_match is None or not tps:
            return None
        try:
            stop_loss = float(sl_match.group(1))
        except Exception:
            return None
        if (not math.isfinite(float(stop_loss))) or float(stop_loss) <= 0.0:
            return None

        entry_low = float(min(entry_a, entry_b))
        entry_high = float(max(entry_a, entry_b))
        entry_mid = float((entry_low + entry_high) * 0.5)
        force_single_trade = bool(
            re.search(r"(?im)\bNO[\s_\-]*PARTIAL(?:S)?\b", raw_norm)
            or re.search(r"(?im)\bSINGLE[\s_\-]*(?:TP|TARGET|TRADE)\b", raw_norm)
            or re.search(r"(?im)\bFULL[\s_\-]*TP\b", raw_norm)
            or re.search(r"(?im)\bNO[\s_\-]*LADDER\b", raw_norm)
        )
        return {
            "symbol": str(symbol),
            "direction": str(direction),
            "entry_low": float(entry_low),
            "entry_high": float(entry_high),
            "entry_mid": float(entry_mid),
            "stop_loss": float(stop_loss),
            "tps": list(tps),
            "force_single_trade": bool(force_single_trade),
            "raw_text": raw.strip(),
        }

    @staticmethod
    def _mt4_exec_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_MT4_EXECUTION_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _mt4_exec_max_signal_age_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_MT4_MAX_SIGNAL_AGE_SEC", "0"))
        except Exception:
            raw = 0.0
        if not math.isfinite(float(raw)):
            raw = 0.0
        return max(0.0, min(86400.0, float(raw)))

    @staticmethod
    def _mt4_exec_dedupe_window_sec() -> float:
        try:
            # Bridge dedupe is for near-term retry noise, not long-term direction memory.
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_MT4_DEDUPE_WINDOW_SEC", "30"))
        except Exception:
            raw = 30.0
        if not math.isfinite(float(raw)):
            raw = 30.0
        return max(5.0, min(86400.0, float(raw)))

    @staticmethod
    def _mt4_bridge_source_lock_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_MT4_BRIDGE_SOURCE_LOCK_SEC", "43200"))
        except Exception:
            raw = 43200.0
        if not math.isfinite(float(raw)):
            raw = 43200.0
        return max(60.0, min(604800.0, float(raw)))

    @staticmethod
    def _indicator_reversal_confirm_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("INDICATOR_BRIDGE_REVERSAL_CONFIRM_SEC", "20"))
        except Exception:
            raw = 20.0
        if not math.isfinite(float(raw)):
            raw = 20.0
        return max(0.0, min(300.0, float(raw)))

    @staticmethod
    def _indicator_clear_fallback_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("INDICATOR_BRIDGE_CLEAR_FALLBACK_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _indicator_clear_fallback_max_age_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("INDICATOR_BRIDGE_CLEAR_FALLBACK_MAX_AGE_SEC", "1800"))
        except Exception:
            raw = 1800.0
        if not math.isfinite(float(raw)):
            raw = 1800.0
        return max(5.0, min(86400.0, float(raw)))

    @staticmethod
    def _indicator_clear_fallback_cooldown_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("INDICATOR_BRIDGE_CLEAR_FALLBACK_COOLDOWN_SEC", "20"))
        except Exception:
            raw = 20.0
        if not math.isfinite(float(raw)):
            raw = 20.0
        return max(1.0, min(600.0, float(raw)))

    @staticmethod
    def _indicator_event_id_window_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("INDICATOR_BRIDGE_EVENT_ID_WINDOW_SEC", "86400"))
        except Exception:
            raw = 86400.0
        if not math.isfinite(float(raw)):
            raw = 86400.0
        return max(60.0, min(7.0 * 86400.0, float(raw)))

    @staticmethod
    def _legacy_mt4_log_ingest_enabled() -> bool:
        # Hard-disable legacy log ingest in bridge-only architecture to avoid
        # accidental dual-ingest and mixed execution sources.
        return False

    @staticmethod
    def _indicator_bridge_include_configured_rows() -> bool:
        v = str(TelegramBridgeService._get_env_value("INDICATOR_BRIDGE_MONITOR_INCLUDE_CONFIGURED", "0")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _indicator_bridge_live_heartbeat_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("INDICATOR_BRIDGE_MONITOR_HEARTBEAT_SEC", "180"))
        except Exception:
            raw = 180.0
        if not math.isfinite(float(raw)):
            raw = 180.0
        return max(10.0, min(86400.0, float(raw)))

    @staticmethod
    def _mt4_exec_profile_enabled(profile: str) -> bool:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_ENABLED"
        default_val = "1" if p in TelegramBridgeService._MT4_EXEC_DEFAULT_ENABLED_PROFILES else "0"
        v = str(TelegramBridgeService._get_env_value(key, default_val)).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _mt4_exec_normalized_profile(profile: str) -> str:
        p = str(profile or "generic").strip().lower() or "generic"
        if p in {"supply_demand", "supply-demand"}:
            p = "supplydemand"
        if p not in TelegramBridgeService._MT4_EXEC_KNOWN_PROFILES:
            p = "generic"
        return str(p)

    @staticmethod
    def _mt4_exec_profile_lot(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_LOT"
        raw = _to_float_or_none(TelegramBridgeService._get_env_value(key, ""))
        if raw is None or float(raw) <= 0.0:
            raw = 0.10
        # MT4 indicator automation uses 5-stage partial TP ladder; keep minimum lot at 0.05
        # so each stage can close 0.01 on symbols with 0.01 volume_step.
        return max(0.05, min(100.0, float(raw)))

    @staticmethod
    def _indicator_bridge_family(value: Any) -> str:
        raw = str(value or "").strip().lower()
        if raw == "mt5":
            return "mt5"
        return "mt4"

    @staticmethod
    def _indicator_bridge_env_key(family: str, suffix: str) -> str:
        fam = "MT5" if str(family or "").strip().lower() == "mt5" else "MT4"
        return f"INDICATOR_BRIDGE_{fam}_{str(suffix or '').strip().upper()}"

    @staticmethod
    def _upsert_indicator_bridge_env_values(updates: Dict[str, Any]) -> Tuple[bool, str]:
        if not isinstance(updates, dict) or not updates:
            return False, "no_updates"
        repo_root = Path(__file__).resolve().parents[3]
        env_path = repo_root / "dashboard" / ".env"
        try:
            lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
        except Exception as exc:
            return False, f"read_env_failed:{type(exc).__name__}:{str(exc)[:140]}"
        normalized: Dict[str, str] = {}
        for k, v in updates.items():
            key = str(k or "").strip().upper()
            if not key.startswith("INDICATOR_BRIDGE_"):
                continue
            normalized[key] = str(v if v is not None else "").strip()
        if not normalized:
            return False, "no_valid_updates"
        out_lines: List[str] = []
        replaced: set[str] = set()
        for line in lines:
            raw = str(line or "")
            if "=" not in raw:
                out_lines.append(raw)
                continue
            key = str(raw.split("=", 1)[0]).strip().upper()
            if key in normalized:
                out_lines.append(f"{key}={normalized[key]}")
                replaced.add(key)
            else:
                out_lines.append(raw)
        for key, val in normalized.items():
            if key not in replaced:
                out_lines.append(f"{key}={val}")
        try:
            env_path.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")
        except Exception as exc:
            return False, f"write_env_failed:{type(exc).__name__}:{str(exc)[:140]}"
        return True, "ok"

    @classmethod
    def _indicator_bridge_default_lot(cls, family: Any) -> float:
        key = cls._indicator_bridge_env_key(cls._indicator_bridge_family(family), "DEFAULT_LOT")
        raw = _to_float_or_none(cls._get_env_value(key, "0.10"))
        if raw is None or float(raw) <= 0.0:
            raw = 0.10
        return float(max(0.01, min(100.0, float(raw))))

    @classmethod
    def _indicator_bridge_instance_key(
        cls,
        *,
        family: Any,
        indicator: Any,
        symbol: Any,
        timeframe: Any,
    ) -> str:
        fam = cls._indicator_bridge_family(family)
        indicator_key = cls._normalize_mt_indicator_key(cls._normalize_mt4_indicator_name(indicator) or indicator)
        symbol_key = str(symbol or "").strip().upper()
        timeframe_key = str(timeframe or "").strip().upper()
        if not indicator_key or not symbol_key or not timeframe_key:
            return ""
        return f"{fam}|{indicator_key}|{symbol_key}|{timeframe_key}"

    @classmethod
    def _parse_indicator_bridge_instance_key(cls, value: Any) -> Dict[str, str]:
        raw = str(value or "").strip().lower()
        if not raw:
            return {}
        parts = [str(x or "").strip() for x in raw.split("|")]
        if len(parts) != 4:
            return {}
        family = cls._indicator_bridge_family(parts[0])
        indicator_key = str(parts[1] or "").strip()
        symbol = str(parts[2] or "").strip().upper()
        timeframe = str(parts[3] or "").strip().upper()
        if not indicator_key or not symbol or not timeframe:
            return {}
        # Best-effort human-readable label for rows that exist only in persisted config.
        indicator_display = " ".join(str(x).capitalize() for x in indicator_key.split())
        return {
            "terminal_family": str(family),
            "indicator_key": str(indicator_key),
            "indicator": str(indicator_display or indicator_key),
            "symbol": str(symbol),
            "timeframe": str(timeframe),
            "instance_key": f"{family}|{indicator_key}|{symbol}|{timeframe}",
        }

    @classmethod
    def _indicator_bridge_instance_automation_overrides(cls, family: Any) -> Dict[str, bool]:
        key = cls._indicator_bridge_env_key(cls._indicator_bridge_family(family), "INSTANCE_AUTOMATION")
        raw = str(cls._get_env_value(key, "{}")).strip()
        out: Dict[str, bool] = {}
        if not raw:
            return out
        try:
            obj = json.loads(raw)
        except Exception:
            return out
        if not isinstance(obj, dict):
            return out
        for k, v in obj.items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            out[item] = bool(v)
        return out

    @classmethod
    def _serialize_indicator_bridge_instance_automation_overrides(cls, overrides: Dict[str, Any]) -> str:
        cleaned: Dict[str, bool] = {}
        for k, v in (overrides or {}).items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            cleaned[item] = bool(v)
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @classmethod
    def _indicator_bridge_instance_lot_overrides(cls, family: Any) -> Dict[str, float]:
        key = cls._indicator_bridge_env_key(cls._indicator_bridge_family(family), "INSTANCE_LOTS")
        raw = str(cls._get_env_value(key, "{}")).strip()
        out: Dict[str, float] = {}
        if not raw:
            return out
        try:
            obj = json.loads(raw)
        except Exception:
            return out
        if not isinstance(obj, dict):
            return out
        for k, v in obj.items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            lot = _to_float_or_none(v)
            if lot is None or float(lot) <= 0.0:
                continue
            out[item] = float(max(0.01, min(100.0, float(lot))))
        return out

    @classmethod
    def _serialize_indicator_bridge_instance_lot_overrides(cls, lot_map: Dict[str, Any]) -> str:
        cleaned: Dict[str, float] = {}
        for k, v in (lot_map or {}).items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            lot = _to_float_or_none(v)
            if lot is None or float(lot) <= 0.0:
                continue
            cleaned[item] = float(max(0.01, min(100.0, float(lot))))
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @classmethod
    def _indicator_bridge_instance_mode_lot_overrides(cls, family: Any) -> Dict[str, Dict[str, float]]:
        key = cls._indicator_bridge_env_key(cls._indicator_bridge_family(family), "INSTANCE_MODE_LOTS")
        raw = str(cls._get_env_value(key, "{}")).strip()
        out: Dict[str, Dict[str, float]] = {}
        if not raw:
            return out
        try:
            obj = json.loads(raw)
        except Exception:
            return out
        if not isinstance(obj, dict):
            return out
        for k, v in obj.items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            cfg = v if isinstance(v, dict) else {}
            row: Dict[str, float] = {}
            for m in ("advanced", "advanced_v2", "normal", "sync"):
                lot = _to_float_or_none(cfg.get(m))
                if lot is None or float(lot) <= 0.0:
                    continue
                row[m] = float(max(0.01, min(100.0, float(lot))))
            if row:
                out[item] = row
        return out

    @classmethod
    def _serialize_indicator_bridge_instance_mode_lot_overrides(cls, lot_map: Dict[str, Any]) -> str:
        cleaned: Dict[str, Dict[str, float]] = {}
        for k, v in (lot_map or {}).items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            cfg = v if isinstance(v, dict) else {}
            row: Dict[str, float] = {}
            for m in ("advanced", "advanced_v2", "normal", "sync"):
                lot = _to_float_or_none(cfg.get(m))
                if lot is None or float(lot) <= 0.0:
                    continue
                row[m] = float(max(0.01, min(100.0, float(lot))))
            if row:
                cleaned[item] = row
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @classmethod
    def _indicator_bridge_instance_mode_overrides(cls, family: Any) -> Dict[str, Dict[str, bool]]:
        key = cls._indicator_bridge_env_key(cls._indicator_bridge_family(family), "INSTANCE_MODES")
        raw = str(cls._get_env_value(key, "{}")).strip()
        out: Dict[str, Dict[str, bool]] = {}
        if not raw:
            return out
        try:
            obj = json.loads(raw)
        except Exception:
            return out
        if not isinstance(obj, dict):
            return out
        for k, v in obj.items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            cfg = v if isinstance(v, dict) else {}
            out[item] = {
                "advanced": bool(cfg.get("advanced", True)),
                "advanced_v2": bool(cfg.get("advanced_v2", False)),
                "normal": bool(cfg.get("normal", False)),
                "sync": bool(cfg.get("sync", False)),
            }
        return out

    @classmethod
    def _serialize_indicator_bridge_instance_mode_overrides(cls, mode_map: Dict[str, Any]) -> str:
        cleaned: Dict[str, Dict[str, bool]] = {}
        for k, v in (mode_map or {}).items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            cfg = v if isinstance(v, dict) else {}
            cleaned[item] = {
                "advanced": bool(cfg.get("advanced", True)),
                "advanced_v2": bool(cfg.get("advanced_v2", False)),
                "normal": bool(cfg.get("normal", False)),
                "sync": bool(cfg.get("sync", False)),
            }
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @staticmethod
    def _indicator_bridge_default_signal_confirm_sec(timeframe: Any) -> float:
        tf = TelegramBridgeService._normalize_tf_token(timeframe, "M5")
        if str(tf) == "M5":
            key = "INDICATOR_BRIDGE_SIGNAL_CONFIRM_SEC_M5"
            default_raw = "60"
        else:
            key = "INDICATOR_BRIDGE_SIGNAL_CONFIRM_SEC"
            default_raw = str(TelegramBridgeService._indicator_reversal_confirm_sec())
        try:
            raw = float(TelegramBridgeService._get_env_value(key, default_raw))
        except Exception:
            raw = float(default_raw)
        if not math.isfinite(float(raw)):
            raw = float(default_raw)
        return float(max(0.0, min(300.0, float(raw))))

    @classmethod
    def _indicator_bridge_instance_signal_confirm_overrides(cls, family: Any) -> Dict[str, float]:
        key = cls._indicator_bridge_env_key(cls._indicator_bridge_family(family), "INSTANCE_SIGNAL_CONFIRM_SEC")
        raw = str(cls._get_env_value(key, "{}")).strip()
        out: Dict[str, float] = {}
        if not raw:
            return out
        try:
            obj = json.loads(raw)
        except Exception:
            return out
        if not isinstance(obj, dict):
            return out
        for k, v in obj.items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            sec = _to_float_or_none(v)
            if sec is None or (not math.isfinite(float(sec))):
                continue
            out[item] = float(max(0.0, min(300.0, float(sec))))
        return out

    @classmethod
    def _serialize_indicator_bridge_instance_signal_confirm_overrides(cls, sec_map: Dict[str, Any]) -> str:
        cleaned: Dict[str, float] = {}
        for k, v in (sec_map or {}).items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            sec = _to_float_or_none(v)
            if sec is None or (not math.isfinite(float(sec))):
                continue
            cleaned[item] = float(max(0.0, min(300.0, float(sec))))
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @staticmethod
    def _normalize_tf_token(value: Any, default: str = "M5") -> str:
        raw = str(value or "").strip().upper()
        if not raw:
            raw = str(default or "M5").strip().upper()
        tf_map = {
            "1": "M1",
            "5": "M5",
            "15": "M15",
            "30": "M30",
            "60": "H1",
            "240": "H4",
            "1440": "D1",
            "10080": "W1",
            "43200": "MN1",
        }
        raw = tf_map.get(raw, raw)
        valid = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN1"}
        return raw if raw in valid else str(default or "M5").strip().upper()

    @classmethod
    def _indicator_bridge_instance_sync_overrides(cls, family: Any) -> Dict[str, Dict[str, Any]]:
        key = cls._indicator_bridge_env_key(cls._indicator_bridge_family(family), "INSTANCE_SYNC")
        raw = str(cls._get_env_value(key, "{}")).strip()
        out: Dict[str, Dict[str, Any]] = {}
        if not raw:
            return out
        try:
            obj = json.loads(raw)
        except Exception:
            return out
        if not isinstance(obj, dict):
            return out
        for k, v in obj.items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            cfg = v if isinstance(v, dict) else {}
            # Backward compatibility for old anchor/trigger/logic schema.
            direction_tf_raw = cfg.get("direction_tf", cfg.get("anchor_tf", "M5"))
            entry_tf_raw = cfg.get("entry_tf", cfg.get("trigger_tf", "M1"))
            exit_tf_raw = cfg.get("exit_tf", cfg.get("trigger_tf", "M1"))
            reentry_raw = cfg.get("reentry_enabled", True)
            out[item] = {
                "direction_tf": cls._normalize_tf_token(direction_tf_raw, "M5"),
                "entry_tf": cls._normalize_tf_token(entry_tf_raw, "M1"),
                "exit_tf": cls._normalize_tf_token(exit_tf_raw, "M1"),
                "reentry_enabled": bool(reentry_raw),
            }
        return out

    @classmethod
    def _serialize_indicator_bridge_instance_sync_overrides(cls, sync_map: Dict[str, Any]) -> str:
        cleaned: Dict[str, Dict[str, Any]] = {}
        for k, v in (sync_map or {}).items():
            item = str(k or "").strip().lower()
            if not item:
                continue
            cfg = v if isinstance(v, dict) else {}
            cleaned[item] = {
                "direction_tf": cls._normalize_tf_token(cfg.get("direction_tf"), "M5"),
                "entry_tf": cls._normalize_tf_token(cfg.get("entry_tf"), "M1"),
                "exit_tf": cls._normalize_tf_token(cfg.get("exit_tf"), "M1"),
                "reentry_enabled": bool(cfg.get("reentry_enabled", True)),
            }
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    def _resolve_indicator_bridge_instance_runtime_config(
        self,
        *,
        family: Any,
        indicator: Any,
        symbol: Any,
        timeframe: Any,
    ) -> Dict[str, Any]:
        terminal_family = self._indicator_bridge_family(family)
        indicator_name = self._normalize_mt4_indicator_name(indicator) or str(indicator or "").strip()
        symbol_name = str(symbol or "").strip().upper()
        timeframe_name = str(timeframe or "").strip().upper()
        instance_key = self._indicator_bridge_instance_key(
            family=terminal_family,
            indicator=indicator_name,
            symbol=symbol_name,
            timeframe=timeframe_name,
        )
        overrides = self._indicator_bridge_instance_automation_overrides(terminal_family)
        instance_key_l = str(instance_key or "").strip().lower()
        explicit_present = bool(instance_key_l and instance_key_l in overrides)
        explicit_enabled = bool(overrides.get(instance_key_l)) if explicit_present else False
        lot_overrides = self._indicator_bridge_instance_lot_overrides(terminal_family)
        lot_size = _to_float_or_none(lot_overrides.get(instance_key_l))
        if lot_size is None or float(lot_size) <= 0.0:
            lot_size = float(self._indicator_bridge_default_lot(terminal_family))
        mode_lot_overrides = self._indicator_bridge_instance_mode_lot_overrides(terminal_family)
        mode_lot_cfg = dict(mode_lot_overrides.get(instance_key_l) or {})
        mode_advanced_lot = _to_float_or_none(mode_lot_cfg.get("advanced"))
        mode_advanced_v2_lot = _to_float_or_none(mode_lot_cfg.get("advanced_v2"))
        mode_normal_lot = _to_float_or_none(mode_lot_cfg.get("normal"))
        mode_sync_lot = _to_float_or_none(mode_lot_cfg.get("sync"))
        if mode_advanced_lot is None or float(mode_advanced_lot) <= 0.0:
            mode_advanced_lot = float(lot_size)
        if mode_advanced_v2_lot is None or float(mode_advanced_v2_lot) <= 0.0:
            mode_advanced_v2_lot = float(lot_size)
        if mode_normal_lot is None or float(mode_normal_lot) <= 0.0:
            mode_normal_lot = float(lot_size)
        if mode_sync_lot is None or float(mode_sync_lot) <= 0.0:
            mode_sync_lot = float(lot_size)
        mode_overrides = self._indicator_bridge_instance_mode_overrides(terminal_family)
        mode_cfg = mode_overrides.get(instance_key_l) if instance_key_l else {}
        mode_advanced = bool((mode_cfg or {}).get("advanced", True))
        mode_advanced_v2 = bool((mode_cfg or {}).get("advanced_v2", False))
        mode_normal = bool((mode_cfg or {}).get("normal", False))
        mode_sync = bool((mode_cfg or {}).get("sync", False))
        signal_confirm_overrides = self._indicator_bridge_instance_signal_confirm_overrides(terminal_family)
        signal_confirm_sec = _to_float_or_none(signal_confirm_overrides.get(instance_key_l))
        if signal_confirm_sec is None:
            signal_confirm_sec = float(self._indicator_bridge_default_signal_confirm_sec(timeframe_name))
        sync_overrides = self._indicator_bridge_instance_sync_overrides(terminal_family)
        sync_cfg = dict(sync_overrides.get(instance_key_l) or {})
        sync_direction_tf = self._normalize_tf_token(sync_cfg.get("direction_tf"), "M5")
        sync_entry_tf = self._normalize_tf_token(sync_cfg.get("entry_tf"), "M1")
        sync_exit_tf = self._normalize_tf_token(sync_cfg.get("exit_tf"), "M1")
        sync_reentry_enabled = bool(sync_cfg.get("reentry_enabled", True))
        return {
            "terminal_family": str(terminal_family),
            "indicator": str(indicator_name),
            "symbol": str(symbol_name),
            "timeframe": str(timeframe_name),
            "instance_key": str(instance_key),
            "automation_mode": ("explicit" if explicit_present else "inherit"),
            "automation_enabled": bool(explicit_enabled),
            "effective_automation_enabled": bool(explicit_enabled),
            "lot_size": _to_float_or_none(lot_size),
            "execution_modes": {
                "advanced": bool(mode_advanced),
                "advanced_v2": bool(mode_advanced_v2),
                "normal": bool(mode_normal),
                "sync": bool(mode_sync),
            },
            "mode_advanced_enabled": bool(mode_advanced),
            "mode_advanced_v2_enabled": bool(mode_advanced_v2),
            "mode_normal_enabled": bool(mode_normal),
            "mode_sync_enabled": bool(mode_sync),
            "mode_lots": {
                "advanced": float(mode_advanced_lot),
                "advanced_v2": float(mode_advanced_v2_lot),
                "normal": float(mode_normal_lot),
                "sync": float(mode_sync_lot),
            },
            "mode_advanced_lot": float(mode_advanced_lot),
            "mode_advanced_v2_lot": float(mode_advanced_v2_lot),
            "mode_normal_lot": float(mode_normal_lot),
            "mode_sync_lot": float(mode_sync_lot),
            "signal_confirm_sec": float(max(0.0, min(300.0, float(signal_confirm_sec)))),
            "sync": {
                "direction_tf": str(sync_direction_tf),
                "entry_tf": str(sync_entry_tf),
                "exit_tf": str(sync_exit_tf),
                "reentry_enabled": bool(sync_reentry_enabled),
            },
        }

    def _resolve_mt4_instance_runtime_config(
        self,
        *,
        indicator: Any,
        symbol: Any,
        timeframe: Any,
    ) -> Dict[str, Any]:
        indicator_name = self._normalize_mt4_indicator_name(indicator) or str(indicator or "").strip()
        symbol_name = str(symbol or "").strip().upper()
        timeframe_name = str(timeframe or "").strip().upper()
        out: Dict[str, Any] = {
            "indicator": str(indicator_name),
            "symbol": str(symbol_name),
            "timeframe": str(timeframe_name),
            "instance_key": "",
            "automation_mode": "inherit",
            "automation_enabled": False,
            "effective_automation_enabled": False,
            "lot_size": None,
            "indicator_allowed": False,
            "indicator_enabled": False,
        }
        if not indicator_name or not symbol_name or not timeframe_name:
            return out
        try:
            from .mt4_log_automation_service import MT4LogAutomationService
        except Exception:
            return out

        allowed = bool(MT4LogAutomationService._is_indicator_automation_allowed(indicator_name))
        indicator_key = str(MT4LogAutomationService._indicator_key(indicator_name) or "").strip()
        instance_key = str(
            MT4LogAutomationService._instance_key(
                indicator=str(indicator_name),
                symbol=str(symbol_name),
                timeframe=str(timeframe_name),
            )
            or ""
        ).strip()
        indicator_enabled = False
        if indicator_key:
            active_indicator_keys = {
                str(MT4LogAutomationService._indicator_key(x) or "").strip()
                for x in (MT4LogAutomationService._active_indicator_names() or [])
                if str(MT4LogAutomationService._indicator_key(x) or "").strip()
            }
            indicator_enabled = bool(indicator_key in active_indicator_keys)
        instance_overrides = MT4LogAutomationService._instance_automation_overrides()
        instance_key_l = str(instance_key or "").strip().lower()
        explicit_present = bool(instance_key_l and instance_key_l in instance_overrides)
        explicit_enabled = bool(instance_overrides.get(instance_key_l)) if explicit_present else False
        effective_enabled = bool(explicit_enabled) if explicit_present else bool(indicator_enabled)
        if not allowed:
            effective_enabled = False
        lot_size = None
        if instance_key:
            lot_size = _to_float_or_none(MT4LogAutomationService._instance_lot_for_key(instance_key))
        if lot_size is None or float(lot_size) <= 0.0:
            lot_size = _to_float_or_none(self._mt4_exec_profile_lot("generic"))
        out.update(
            {
                "instance_key": str(instance_key),
                "automation_mode": ("explicit" if explicit_present else "inherit"),
                "automation_enabled": bool(explicit_enabled),
                "effective_automation_enabled": bool(effective_enabled),
                "lot_size": _to_float_or_none(lot_size),
                "indicator_allowed": bool(allowed),
                "indicator_enabled": bool(indicator_enabled),
            }
        )
        return out

    def register_indicator_bridge_instance(
        self,
        *,
        terminal_family: Any,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        family = self._indicator_bridge_family(terminal_family)
        p = payload if isinstance(payload, dict) else {}
        indicator_raw = str(p.get("indicator") or p.get("indicator_name") or "").strip()
        indicator = self._normalize_mt4_indicator_name(indicator_raw) or indicator_raw or f"{family.upper()}Bridge"
        symbol_raw = str(p.get("symbol") or p.get("pair") or "").strip().upper()
        symbol = str(self._CONFIRM_SIGNAL_SYMBOL_ALIASES.get(symbol_raw, symbol_raw))
        timeframe = str(p.get("timeframe") or p.get("tf") or self._confirm_signal_default_timeframe()).strip().upper() or "M5"
        profile = str(p.get("signal_profile") or p.get("profile") or "").strip().lower()
        message = str(p.get("message") or p.get("raw_text") or "").strip()
        event_ts = str(p.get("event_ts") or self._now_iso()).strip() or self._now_iso()
        bridge_event_type = str(p.get("bridge_event_type") or p.get("event_type") or "signal").strip().lower() or "signal"
        instance_key = self._indicator_bridge_instance_key(
            family=family,
            indicator=indicator,
            symbol=symbol,
            timeframe=timeframe,
        )
        runtime_cfg = self._resolve_indicator_bridge_instance_runtime_config(
            family=family,
            indicator=indicator,
            symbol=symbol,
            timeframe=timeframe,
        )
        row = {
            "terminal_family": str(family),
            "indicator": str(indicator),
            "profile": str(profile),
            "symbol": str(symbol),
            "timeframe": str(timeframe),
            "instance_key": str(instance_key),
            "last_seen": str(event_ts),
            "bridge_event_type": str(bridge_event_type),
            "message": str(message),
            "automation_mode": str(runtime_cfg.get("automation_mode") or "inherit"),
            "automation_enabled": bool(runtime_cfg.get("automation_enabled")),
            "effective_automation_enabled": bool(runtime_cfg.get("effective_automation_enabled")),
            "lot_size": _to_float_or_none(runtime_cfg.get("lot_size")),
            "execution_modes": dict(runtime_cfg.get("execution_modes") or {}),
            "mode_advanced_enabled": bool(runtime_cfg.get("mode_advanced_enabled")),
            "mode_normal_enabled": bool(runtime_cfg.get("mode_normal_enabled")),
            "mode_sync_enabled": bool(runtime_cfg.get("mode_sync_enabled")),
            "mode_lots": dict(runtime_cfg.get("mode_lots") or {}),
            "sync": dict(runtime_cfg.get("sync") or {}),
            "source_tag": (
                f"{family}|{str(profile or 'generic').strip().lower()}|"
                f"{self._normalize_mt_indicator_key(indicator)}|{str(symbol).strip().upper()}|{str(timeframe).strip().upper()}"
            ),
        }
        if not instance_key:
            return row
        with self._lock:
            prev = self._indicator_bridge_instances.get(str(instance_key))
            if isinstance(prev, dict):
                merged = dict(prev)
                merged.update(
                    {
                        k: v
                        for k, v in row.items()
                        if v is not None and v != "" and v != []
                    }
                )
                row = merged
            self._indicator_bridge_instances[str(instance_key)] = dict(row)
            if len(self._indicator_bridge_instances) > 5000:
                cutoff = time.time() - (7.0 * 86400.0)
                compacted: Dict[str, Dict[str, Any]] = {}
                for k, v in self._indicator_bridge_instances.items():
                    seen_ts = _to_unix_or_none((v or {}).get("last_seen"))
                    if seen_ts is None or float(seen_ts) >= float(cutoff):
                        compacted[str(k)] = dict(v)
                self._indicator_bridge_instances = compacted
        return dict(row)

    def update_indicator_bridge_instance_settings(
        self,
        *,
        terminal_family: Any,
        indicator: Any,
        symbol: Any,
        timeframe: Any,
        enabled: Optional[bool] = None,
        lot_size: Optional[float] = None,
        mode_advanced_enabled: Optional[bool] = None,
        mode_advanced_v2_enabled: Optional[bool] = None,
        mode_normal_enabled: Optional[bool] = None,
        mode_sync_enabled: Optional[bool] = None,
        mode_advanced_lot: Optional[float] = None,
        mode_advanced_v2_lot: Optional[float] = None,
        mode_normal_lot: Optional[float] = None,
        mode_sync_lot: Optional[float] = None,
        signal_confirm_sec: Optional[float] = None,
        sync_direction_tf: Optional[str] = None,
        sync_entry_tf: Optional[str] = None,
        sync_exit_tf: Optional[str] = None,
        sync_reentry_enabled: Optional[bool] = None,
    ) -> Dict[str, Any]:
        family = self._indicator_bridge_family(terminal_family)
        instance_key = self._indicator_bridge_instance_key(
            family=family,
            indicator=indicator,
            symbol=symbol,
            timeframe=timeframe,
        )
        if not instance_key:
            return {"ok": False, "error": "invalid_instance_key"}
        auto_map = self._indicator_bridge_instance_automation_overrides(family)
        lot_map = self._indicator_bridge_instance_lot_overrides(family)
        mode_map = self._indicator_bridge_instance_mode_overrides(family)
        mode_lot_map = self._indicator_bridge_instance_mode_lot_overrides(family)
        signal_confirm_map = self._indicator_bridge_instance_signal_confirm_overrides(family)
        sync_map = self._indicator_bridge_instance_sync_overrides(family)
        if enabled is not None:
            auto_map[str(instance_key).lower()] = bool(enabled)
        if lot_size is not None:
            lot_val = _to_float_or_none(lot_size)
            if lot_val is None or float(lot_val) <= 0.0:
                return {"ok": False, "error": "invalid_lot_size"}
            lot_map[str(instance_key).lower()] = float(max(0.01, min(100.0, float(lot_val))))
        if mode_advanced_enabled is not None or mode_advanced_v2_enabled is not None or mode_normal_enabled is not None or mode_sync_enabled is not None:
            mk = str(instance_key).lower()
            prev = dict(mode_map.get(mk) or {"advanced": True, "advanced_v2": False, "normal": False, "sync": False})
            if mode_advanced_enabled is not None:
                prev["advanced"] = bool(mode_advanced_enabled)
            if mode_advanced_v2_enabled is not None:
                prev["advanced_v2"] = bool(mode_advanced_v2_enabled)
            if mode_normal_enabled is not None:
                prev["normal"] = bool(mode_normal_enabled)
            if mode_sync_enabled is not None:
                prev["sync"] = bool(mode_sync_enabled)
            mode_map[mk] = {
                "advanced": bool(prev.get("advanced", True)),
                "advanced_v2": bool(prev.get("advanced_v2", False)),
                "normal": bool(prev.get("normal", False)),
                "sync": bool(prev.get("sync", False)),
            }
        if mode_advanced_lot is not None or mode_advanced_v2_lot is not None or mode_normal_lot is not None or mode_sync_lot is not None:
            mk = str(instance_key).lower()
            prev_lots = dict(mode_lot_map.get(mk) or {})
            if mode_advanced_lot is not None:
                v = _to_float_or_none(mode_advanced_lot)
                if v is None or float(v) <= 0.0:
                    return {"ok": False, "error": "invalid_mode_advanced_lot"}
                prev_lots["advanced"] = float(max(0.01, min(100.0, float(v))))
            if mode_advanced_v2_lot is not None:
                v = _to_float_or_none(mode_advanced_v2_lot)
                if v is None or float(v) <= 0.0:
                    return {"ok": False, "error": "invalid_mode_advanced_v2_lot"}
                prev_lots["advanced_v2"] = float(max(0.01, min(100.0, float(v))))
            if mode_normal_lot is not None:
                v = _to_float_or_none(mode_normal_lot)
                if v is None or float(v) <= 0.0:
                    return {"ok": False, "error": "invalid_mode_normal_lot"}
                prev_lots["normal"] = float(max(0.01, min(100.0, float(v))))
            if mode_sync_lot is not None:
                v = _to_float_or_none(mode_sync_lot)
                if v is None or float(v) <= 0.0:
                    return {"ok": False, "error": "invalid_mode_sync_lot"}
                prev_lots["sync"] = float(max(0.01, min(100.0, float(v))))
            mode_lot_map[mk] = dict(prev_lots)
        if signal_confirm_sec is not None:
            mk = str(instance_key).lower()
            v = _to_float_or_none(signal_confirm_sec)
            if v is None or (not math.isfinite(float(v))):
                return {"ok": False, "error": "invalid_signal_confirm_sec"}
            signal_confirm_map[mk] = float(max(0.0, min(300.0, float(v))))
        if (
            sync_direction_tf is not None
            or sync_entry_tf is not None
            or sync_exit_tf is not None
            or sync_reentry_enabled is not None
        ):
            mk = str(instance_key).lower()
            prev_sync = dict(sync_map.get(mk) or {})
            if sync_direction_tf is not None:
                prev_sync["direction_tf"] = self._normalize_tf_token(sync_direction_tf, "M5")
            if sync_entry_tf is not None:
                prev_sync["entry_tf"] = self._normalize_tf_token(sync_entry_tf, "M1")
            if sync_exit_tf is not None:
                prev_sync["exit_tf"] = self._normalize_tf_token(sync_exit_tf, "M1")
            if sync_reentry_enabled is not None:
                prev_sync["reentry_enabled"] = bool(sync_reentry_enabled)
            sync_map[mk] = {
                "direction_tf": self._normalize_tf_token(prev_sync.get("direction_tf"), "M5"),
                "entry_tf": self._normalize_tf_token(prev_sync.get("entry_tf"), "M1"),
                "exit_tf": self._normalize_tf_token(prev_sync.get("exit_tf"), "M1"),
                "reentry_enabled": bool(prev_sync.get("reentry_enabled", True)),
            }
        ok, status = self._upsert_indicator_bridge_env_values(
            {
                self._indicator_bridge_env_key(family, "INSTANCE_AUTOMATION"): self._serialize_indicator_bridge_instance_automation_overrides(auto_map),
                self._indicator_bridge_env_key(family, "INSTANCE_LOTS"): self._serialize_indicator_bridge_instance_lot_overrides(lot_map),
                self._indicator_bridge_env_key(family, "INSTANCE_MODES"): self._serialize_indicator_bridge_instance_mode_overrides(mode_map),
                self._indicator_bridge_env_key(family, "INSTANCE_MODE_LOTS"): self._serialize_indicator_bridge_instance_mode_lot_overrides(mode_lot_map),
                self._indicator_bridge_env_key(family, "INSTANCE_SIGNAL_CONFIRM_SEC"): self._serialize_indicator_bridge_instance_signal_confirm_overrides(signal_confirm_map),
                self._indicator_bridge_env_key(family, "INSTANCE_SYNC"): self._serialize_indicator_bridge_instance_sync_overrides(sync_map),
            }
        )
        runtime_cfg = self._resolve_indicator_bridge_instance_runtime_config(
            family=family,
            indicator=indicator,
            symbol=symbol,
            timeframe=timeframe,
        )
        with self._lock:
            prev = self._indicator_bridge_instances.get(str(instance_key))
            if isinstance(prev, dict):
                prev["automation_mode"] = str(runtime_cfg.get("automation_mode") or "inherit")
                prev["automation_enabled"] = bool(runtime_cfg.get("automation_enabled"))
                prev["effective_automation_enabled"] = bool(runtime_cfg.get("effective_automation_enabled"))
                prev["lot_size"] = _to_float_or_none(runtime_cfg.get("lot_size"))
                prev["execution_modes"] = dict(runtime_cfg.get("execution_modes") or {})
                prev["mode_advanced_enabled"] = bool(runtime_cfg.get("mode_advanced_enabled"))
                prev["mode_advanced_v2_enabled"] = bool(runtime_cfg.get("mode_advanced_v2_enabled"))
                prev["mode_normal_enabled"] = bool(runtime_cfg.get("mode_normal_enabled"))
                prev["mode_sync_enabled"] = bool(runtime_cfg.get("mode_sync_enabled"))
                prev["mode_lots"] = dict(runtime_cfg.get("mode_lots") or {})
                prev["signal_confirm_sec"] = _to_float_or_none(runtime_cfg.get("signal_confirm_sec"))
                prev["sync"] = dict(runtime_cfg.get("sync") or {})
                self._indicator_bridge_instances[str(instance_key)] = dict(prev)
        return {
            "ok": bool(ok),
            "persist_status": str(status),
            "runtime": runtime_cfg,
        }

    def _get_indicator_bridge_bot_monitor(
        self,
        *,
        terminal_family: Any,
        limit: int = 300,
        active_only: bool = False,
    ) -> Dict[str, Any]:
        family = self._indicator_bridge_family(terminal_family)
        lim = int(max(10, min(1000, int(limit or 300))))
        ttl_sec = 7.0 * 86400.0
        now_ts = time.time()
        with self._lock:
            ladders = [dict(v) for v in self._active_confirmation_signal_ladders.values() if isinstance(v, dict)]
            registry_rows = [dict(v) for v in self._indicator_bridge_instances.values() if isinstance(v, dict)]
        family_prefix = f"{family}|"
        ladder_rows = [r for r in ladders if str(r.get("source_tag") or "").strip().lower().startswith(family_prefix)]
        auto_map = self._indicator_bridge_instance_automation_overrides(family)
        lot_map = self._indicator_bridge_instance_lot_overrides(family)
        mode_map = self._indicator_bridge_instance_mode_overrides(family)
        mode_lot_map = self._indicator_bridge_instance_mode_lot_overrides(family)
        signal_confirm_map = self._indicator_bridge_instance_signal_confirm_overrides(family)
        sync_map = self._indicator_bridge_instance_sync_overrides(family)
        configured_keys = {
            str(k or "").strip().lower()
            for k in (
                list(auto_map.keys())
                + list(lot_map.keys())
                + list(mode_map.keys())
                + list(mode_lot_map.keys())
                + list(signal_confirm_map.keys())
                + list(sync_map.keys())
            )
            if str(k or "").strip()
        }
        include_configured_rows = bool(self._indicator_bridge_include_configured_rows())
        heartbeat_live_sec = float(self._indicator_bridge_live_heartbeat_sec())
        svc = self._get_live_service()
        symbols = sorted({str(r.get("symbol") or "").strip().upper() for r in ladder_rows if str(r.get("symbol") or "").strip()})
        open_by_symbol: Dict[str, List[Dict[str, Any]]] = {}
        for sym in symbols:
            try:
                open_by_symbol[str(sym)] = [dict(x) for x in (svc.get_open_positions(symbol=str(sym)) or []) if isinstance(x, dict)]
            except Exception:
                open_by_symbol[str(sym)] = []

        open_rows: List[Dict[str, Any]] = []
        ladder_by_instance: Dict[str, Dict[str, Any]] = {}
        for row in ladder_rows:
            ticket = int(_to_float_or_none(row.get("broker_ticket")) or 0)
            symbol = str(row.get("symbol") or "").strip().upper()
            timeframe = str(row.get("timeframe") or "").strip().upper()
            direction = str(row.get("direction") or "").strip().upper()
            indicator = str(row.get("indicator") or row.get("source_name") or "unknown").strip() or "unknown"
            instance_key = self._indicator_bridge_instance_key(
                family=family,
                indicator=indicator,
                symbol=symbol,
                timeframe=timeframe,
            )
            pos_rows = list(open_by_symbol.get(symbol) or [])
            live_pos = next((p for p in pos_rows if int(_to_float_or_none(p.get("ticket")) or 0) == ticket), None)
            current_profit = _to_float_or_none((live_pos or {}).get("profit_loss"))
            current_price = _to_float_or_none((live_pos or {}).get("current_price"))
            out_row = {
                "terminal_family": str(family),
                "instance_key": str(instance_key),
                "indicator": str(indicator),
                "symbol": str(symbol),
                "timeframe": str(timeframe),
                "execution_mode": str(row.get("execution_mode") or "advanced").strip().lower(),
                "direction": str(direction),
                "ticket": int(ticket),
                "opened_at": str(row.get("created_at") or ""),
                "state": "OPEN",
                "max_profit": _to_float_or_none(row.get("max_profit")),
                "max_loss": _to_float_or_none(row.get("max_loss")),
                "current_profit": _to_float_or_none(current_profit),
                "current_price": _to_float_or_none(current_price),
                "source_tag": str(row.get("source_tag") or "").strip().lower(),
                "profile": str(row.get("profile") or "").strip().lower(),
                "combo_key": self._build_execution_combo_key(
                    source_type="mt_indicator",
                    source_name=str(indicator),
                    indicator=str(indicator),
                    symbol=str(symbol),
                    timeframe=str(timeframe),
                ),
            }
            open_rows.append(out_row)
            ladder_by_instance[str(instance_key).lower()] = dict(out_row)

        bot_rows: List[Dict[str, Any]] = []
        registry_by_key: Dict[str, Dict[str, Any]] = {}
        for row in registry_rows:
            if str(row.get("terminal_family") or "").strip().lower() != family:
                continue
            seen_unix = _to_unix_or_none(row.get("last_seen"))
            if seen_unix is not None and (float(now_ts) - float(seen_unix)) > float(ttl_sec):
                continue
            indicator = str(row.get("indicator") or "").strip()
            symbol = str(row.get("symbol") or "").strip().upper()
            timeframe = str(row.get("timeframe") or "").strip().upper()
            instance_key = str(row.get("instance_key") or "").strip()
            if not indicator or not symbol or not timeframe or not instance_key:
                continue
            registry_by_key[str(instance_key).lower()] = dict(row)

        # Optional: include persisted instance configs even without heartbeat/signal.
        if include_configured_rows:
            for cfg_key in configured_keys:
                if str(cfg_key).lower() in registry_by_key:
                    continue
                parsed = self._parse_indicator_bridge_instance_key(cfg_key)
                if not isinstance(parsed, dict) or not parsed:
                    continue
                if str(parsed.get("terminal_family") or "").strip().lower() != family:
                    continue
                registry_by_key[str(cfg_key).lower()] = {
                    "terminal_family": str(family),
                    "instance_key": str(parsed.get("instance_key") or cfg_key),
                    "indicator": str(parsed.get("indicator") or parsed.get("indicator_key") or "").strip(),
                    "symbol": str(parsed.get("symbol") or "").strip().upper(),
                    "timeframe": str(parsed.get("timeframe") or "").strip().upper(),
                    "last_seen": "",
                    "bridge_event_type": "configured",
                    "message": "Persisted bridge config",
                }

        for row in registry_by_key.values():
            indicator = str(row.get("indicator") or "").strip()
            symbol = str(row.get("symbol") or "").strip().upper()
            timeframe = str(row.get("timeframe") or "").strip().upper()
            instance_key = str(row.get("instance_key") or "").strip()
            if not indicator or not symbol or not timeframe or not instance_key:
                continue
            runtime_cfg = self._resolve_indicator_bridge_instance_runtime_config(
                family=family,
                indicator=indicator,
                symbol=symbol,
                timeframe=timeframe,
            )
            linked = dict(ladder_by_instance.get(str(instance_key).lower()) or {})
            merged = dict(row)
            last_seen_unix = _to_unix_or_none(row.get("last_seen"))
            is_live_heartbeat = bool(last_seen_unix is not None and (float(now_ts) - float(last_seen_unix)) <= float(heartbeat_live_sec))
            is_configured = bool(str(row.get("bridge_event_type") or "").strip().lower() == "configured")
            inferred_state = "CONFIGURED" if is_configured else ("IDLE" if is_live_heartbeat else "STALE")
            latest_rsi = self._latest_indicator_rsi_telemetry(
                family=str(family),
                symbol=str(symbol),
                timeframe=str(timeframe),
                max_age_sec=86400.0,
            )
            merged.update(
                {
                    "terminal_family": str(family),
                    "instance_key": str(instance_key),
                    "indicator": str(indicator),
                    "symbol": str(symbol),
                    "timeframe": str(timeframe),
                    "automation_mode": str(runtime_cfg.get("automation_mode") or "inherit"),
                    "automation_enabled": bool(runtime_cfg.get("automation_enabled")),
                    "effective_automation_enabled": bool(runtime_cfg.get("effective_automation_enabled")),
                    "lot_size": _to_float_or_none(runtime_cfg.get("lot_size")),
                    "execution_modes": dict(runtime_cfg.get("execution_modes") or {}),
                    "mode_advanced_enabled": bool(runtime_cfg.get("mode_advanced_enabled")),
                    "mode_advanced_v2_enabled": bool(runtime_cfg.get("mode_advanced_v2_enabled")),
                    "mode_normal_enabled": bool(runtime_cfg.get("mode_normal_enabled")),
                    "mode_sync_enabled": bool(runtime_cfg.get("mode_sync_enabled")),
                    "mode_lots": dict(runtime_cfg.get("mode_lots") or {}),
                    "signal_confirm_sec": _to_float_or_none(runtime_cfg.get("signal_confirm_sec")),
                    "sync": dict(runtime_cfg.get("sync") or {}),
                    "state": ("OPEN" if linked else inferred_state),
                    "has_open_ladder": bool(linked),
                    "has_live_heartbeat": bool(is_live_heartbeat),
                    "active_execution_mode": str(linked.get("execution_mode") or "").strip().lower(),
                    "ticket": int(_to_float_or_none(linked.get("ticket")) or 0),
                    "direction": str(linked.get("direction") or "").strip().upper(),
                    "opened_at": str(linked.get("opened_at") or ""),
                    "max_profit": _to_float_or_none(linked.get("max_profit")),
                    "max_loss": _to_float_or_none(linked.get("max_loss")),
                    "current_profit": _to_float_or_none(linked.get("current_profit")),
                    "current_price": _to_float_or_none(linked.get("current_price")),
                    "combo_key": str(linked.get("combo_key") or self._build_execution_combo_key(
                        source_type="mt_indicator",
                        source_name=str(indicator),
                        indicator=str(indicator),
                        symbol=str(symbol),
                        timeframe=str(timeframe),
                    )),
                    "rsi_value": (_to_float_or_none((latest_rsi or {}).get("rsi_value")) if isinstance(latest_rsi, dict) else None),
                    "rsi_seen_ts": (_to_float_or_none((latest_rsi or {}).get("seen_ts")) if isinstance(latest_rsi, dict) else None),
                    "rsi_seen_at": (
                        datetime.fromtimestamp(float(_to_float_or_none((latest_rsi or {}).get("seen_ts")) or 0.0), tz=timezone.utc).isoformat()
                        if isinstance(latest_rsi, dict) and _to_float_or_none((latest_rsi or {}).get("seen_ts")) is not None
                        else ""
                    ),
                    "rsi_indicator": (str((latest_rsi or {}).get("indicator") or "") if isinstance(latest_rsi, dict) else ""),
                    "rsi_indicator_tf": (str((latest_rsi or {}).get("indicator_tf") or "") if isinstance(latest_rsi, dict) else ""),
                    "rsi_period": (_to_float_or_none((latest_rsi or {}).get("rsi_period")) if isinstance(latest_rsi, dict) else None),
                }
            )
            if active_only:
                if not bool(merged.get("effective_automation_enabled")):
                    continue
                if not (bool(merged.get("has_open_ladder")) or bool(merged.get("has_live_heartbeat"))):
                    continue
            bot_rows.append(merged)
        bot_rows.sort(key=lambda r: (str(r.get("opened_at") or ""), str(r.get("last_seen") or "")), reverse=True)
        bot_rows = bot_rows[:lim]
        return {
            "ok": True,
            "terminal_family": str(family),
            "updated_at": self._now_iso(),
            "active_only": bool(active_only),
            "rows": open_rows[:lim],
            "bot_rows": bot_rows,
            "bot_active_count": int(len([r for r in bot_rows if bool(r.get("effective_automation_enabled"))])),
            "bot_open_count": int(len([r for r in bot_rows if bool(r.get("has_open_ladder"))])),
            "bot_idle_count": int(len([r for r in bot_rows if bool(r.get("effective_automation_enabled")) and not bool(r.get("has_open_ladder"))])),
        }

    def get_mt5_indicator_bot_monitor(self, *, limit: int = 300, active_only: bool = False) -> Dict[str, Any]:
        return self._get_indicator_bridge_bot_monitor(terminal_family="mt5", limit=limit, active_only=active_only)

    @staticmethod
    def _execution_terminal_family_from_row(row: Dict[str, Any]) -> str:
        source_tag = str((row or {}).get("source_tag") or "").strip().lower()
        if source_tag.startswith("mt5|"):
            return "MT5"
        if source_tag.startswith("mt4|"):
            return "MT4"
        return "-"

    @staticmethod
    def _execution_session_name(value: Any) -> str:
        unix_ts = _to_unix_or_none(value)
        if unix_ts is None:
            return "-"
        dt = datetime.fromtimestamp(float(unix_ts), tz=timezone.utc)
        mins = int(dt.hour) * 60 + int(dt.minute)
        if 0 <= mins < 9 * 60:
            return "tokyo"
        if 7 * 60 <= mins < 16 * 60:
            return "london"
        if 13 * 60 <= mins < 22 * 60:
            return "new_york"
        return "off_session"

    def get_indicator_execution_audit_rows(self, *, limit: int = 500) -> Dict[str, Any]:
        raw_rows = self.get_automation_execution_logs(limit=max(100, min(5000, int(limit or 500))))
        out_rows: List[Dict[str, Any]] = []
        for row in raw_rows:
            if not isinstance(row, dict):
                continue
            if str(row.get("source_type") or "").strip().lower() != "mt_indicator":
                continue
            if not self._is_bridge_source_tag(row.get("source_tag")):
                continue
            opened_at = str(row.get("opened_at") or "").strip()
            event_ts = str(row.get("event_ts") or row.get("ts") or "").strip()
            status = str(row.get("status") or "").strip().lower()
            out_rows.append(
                {
                    "id": int(row.get("id") or 0),
                    "terminal_family": self._execution_terminal_family_from_row(row),
                    "indicator": str(row.get("indicator") or row.get("source_name") or "").strip(),
                    "source_name": str(row.get("source_name") or "").strip(),
                    "symbol": str(row.get("symbol") or "").strip().upper(),
                    "timeframe": str(row.get("timeframe") or "").strip().upper(),
                    "direction": str(row.get("direction") or "").strip().upper(),
                    "lot": _to_float_or_none(row.get("lot")),
                    "status": str(status),
                    "ticket": int(_to_float_or_none(row.get("ticket")) or 0) or None,
                    "order_number": int(_to_float_or_none(row.get("order_number")) or 0) or None,
                    "opened_at": str(opened_at),
                    "closed_at": (str(event_ts) if status == "closed" else ""),
                    "session_name": self._execution_session_name(opened_at or event_ts),
                    "max_profit": _to_float_or_none(row.get("max_profit")),
                    "max_loss": _to_float_or_none(row.get("max_loss")),
                    "realized_pnl": _to_float_or_none(row.get("realized_pnl")),
                    "close_reason": str(row.get("close_reason") or "").strip(),
                    "final_tp": _to_float_or_none(row.get("final_tp")),
                    "stop_loss": _to_float_or_none(row.get("stop_loss")),
                    "execution_mode": str(row.get("execution_mode") or "").strip().lower(),
                    "event_ts": str(event_ts),
                    "message": str(row.get("message") or "").strip(),
                    "source_tag": str(row.get("source_tag") or "").strip().lower(),
                    "combo_key": str(row.get("combo_key") or "").strip().lower(),
                }
            )
        out_rows.sort(key=lambda r: str(r.get("event_ts") or r.get("opened_at") or ""), reverse=True)
        lim = int(max(20, min(5000, int(limit or 500))))
        out_rows = out_rows[:lim]
        return {
            "ok": True,
            "rows": out_rows,
            "count": int(len(out_rows)),
            "generated_at": self._now_iso(),
        }

    def get_indicator_bridge_state(self, *, limit: int = 300, active_only: bool = False) -> Dict[str, Any]:
        lim = int(max(20, min(1000, int(limit or 300))))
        mt4_monitor = self._get_indicator_bridge_bot_monitor(terminal_family="mt4", limit=lim, active_only=active_only)
        mt5_monitor = self._get_indicator_bridge_bot_monitor(terminal_family="mt5", limit=lim, active_only=active_only)
        execution_logs = self.get_indicator_execution_audit_rows(limit=max(200, lim))
        execution_report = self.get_automation_execution_report(limit=200)
        rsi_telemetry = self.get_indicator_rsi_telemetry(limit=max(200, lim))
        return {
            "ok": True,
            "updated_at": self._now_iso(),
            "active_only": bool(active_only),
            "mt4_monitor": mt4_monitor,
            "mt5_monitor": mt5_monitor,
            "execution_logs": execution_logs,
            "execution_report": execution_report,
            "rsi_telemetry": rsi_telemetry,
        }

    @staticmethod
    def _mt4_exec_profile_atr_period(profile: str) -> int:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_ATR_PERIOD"
        try:
            raw = int(float(TelegramBridgeService._get_env_value(key, "14")))
        except Exception:
            raw = 14
        return max(5, min(100, int(raw)))

    @staticmethod
    def _mt4_exec_profile_sl_atr(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_SL_ATR"
        try:
            # Default loosened for indicator-driven entries to reduce noise stop-outs.
            raw = float(TelegramBridgeService._get_env_value(key, "2.2"))
        except Exception:
            raw = 2.2
        if not math.isfinite(float(raw)):
            raw = 2.2
        return max(0.2, min(10.0, float(raw)))

    @staticmethod
    def _mt4_exec_profile_tp_atr(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_TP_ATR"
        try:
            # Indicator TP base distance in ATR units.
            raw = float(TelegramBridgeService._get_env_value(key, "1.0"))
        except Exception:
            raw = 1.0
        if not math.isfinite(float(raw)):
            raw = 1.0
        return max(0.3, min(20.0, float(raw)))

    @staticmethod
    def _mt4_exec_profile_tp_levels(profile: str) -> List[float]:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_TP_LEVELS"
        raw = str(TelegramBridgeService._get_env_value(key, "0.6,1.0,1.5,2.2,3.2") or "").strip()
        vals: List[float] = []
        for part in re.split(r"[,;| ]+", raw):
            s = str(part or "").strip()
            if not s:
                continue
            try:
                v = float(s)
            except Exception:
                continue
            if math.isfinite(float(v)) and float(v) > 0.0:
                vals.append(float(v))
        if not vals:
            vals = [0.6, 1.0, 1.5, 2.2, 3.2]
        vals = sorted(float(x) for x in vals if float(x) > 0.0)
        if len(vals) > 12:
            vals = vals[:12]
        return list(vals)

    @staticmethod
    def _mt4_exec_profile_tp_levels_range(profile: str) -> List[float]:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_TP_LEVELS_RANGE"
        raw = str(TelegramBridgeService._get_env_value(key, "0.45,0.75,1.05,1.40,1.90") or "").strip()
        vals: List[float] = []
        for part in re.split(r"[,;| ]+", raw):
            s = str(part or "").strip()
            if not s:
                continue
            try:
                v = float(s)
            except Exception:
                continue
            if math.isfinite(float(v)) and float(v) > 0.0:
                vals.append(float(v))
        if not vals:
            vals = [0.45, 0.75, 1.05, 1.40, 1.90]
        vals = sorted(float(x) for x in vals if float(x) > 0.0)
        if len(vals) > 12:
            vals = vals[:12]
        return list(vals)

    @staticmethod
    def _mt4_exec_profile_tp_levels_trend(profile: str) -> List[float]:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_TP_LEVELS_TREND"
        # Trend runner defaults: push the last target further so winners can run.
        raw = str(TelegramBridgeService._get_env_value(key, "0.90,1.60,2.60,4.00,6.20") or "").strip()
        vals: List[float] = []
        for part in re.split(r"[,;| ]+", raw):
            s = str(part or "").strip()
            if not s:
                continue
            try:
                v = float(s)
            except Exception:
                continue
            if math.isfinite(float(v)) and float(v) > 0.0:
                vals.append(float(v))
        if not vals:
            vals = [0.90, 1.60, 2.60, 4.00, 6.20]
        vals = sorted(float(x) for x in vals if float(x) > 0.0)
        if len(vals) > 12:
            vals = vals[:12]
        return list(vals)

    @staticmethod
    def _mt4_exec_profile_stage_weights(profile: str) -> List[float]:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_STAGE_WEIGHTS"
        raw = str(TelegramBridgeService._get_env_value(key, "40,25,15,10,10") or "").strip()
        vals: List[float] = []
        for part in re.split(r"[,;| ]+", raw):
            s = str(part or "").strip()
            if not s:
                continue
            try:
                v = float(s)
            except Exception:
                continue
            if math.isfinite(float(v)) and float(v) > 0.0:
                vals.append(float(v))
        if not vals:
            vals = [40.0, 25.0, 15.0, 10.0, 10.0]
        return list(vals)

    @staticmethod
    def _mt4_exec_profile_stage_weights_range(profile: str) -> List[float]:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_STAGE_WEIGHTS_RANGE"
        raw = str(TelegramBridgeService._get_env_value(key, "50,25,15,7,3") or "").strip()
        vals: List[float] = []
        for part in re.split(r"[,;| ]+", raw):
            s = str(part or "").strip()
            if not s:
                continue
            try:
                v = float(s)
            except Exception:
                continue
            if math.isfinite(float(v)) and float(v) > 0.0:
                vals.append(float(v))
        if not vals:
            vals = [50.0, 25.0, 15.0, 7.0, 3.0]
        return list(vals)

    @staticmethod
    def _mt4_exec_profile_stage_weights_trend(profile: str) -> List[float]:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_STAGE_WEIGHTS_TREND"
        # Trend runner defaults: keep more size for late trend extension.
        raw = str(TelegramBridgeService._get_env_value(key, "15,15,20,20,30") or "").strip()
        vals: List[float] = []
        for part in re.split(r"[,;| ]+", raw):
            s = str(part or "").strip()
            if not s:
                continue
            try:
                v = float(s)
            except Exception:
                continue
            if math.isfinite(float(v)) and float(v) > 0.0:
                vals.append(float(v))
        if not vals:
            vals = [15.0, 15.0, 20.0, 20.0, 30.0]
        return list(vals)

    @staticmethod
    def _mt4_exec_profile_tp_r_start(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_TP_R_START"
        try:
            # Wider-by-default TP ladder for indicator automation.
            raw = float(TelegramBridgeService._get_env_value(key, "1.4"))
        except Exception:
            raw = 1.4
        if not math.isfinite(float(raw)):
            raw = 1.4
        return max(0.1, min(5.0, float(raw)))

    @staticmethod
    def _mt4_exec_profile_tp_r_step(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_TP_R_STEP"
        try:
            raw = float(TelegramBridgeService._get_env_value(key, "0.7"))
        except Exception:
            raw = 0.7
        if not math.isfinite(float(raw)):
            raw = 0.7
        return max(0.1, min(5.0, float(raw)))

    @staticmethod
    def _mt4_exec_profile_regime_mode(profile: str) -> str:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_REGIME_MODE"
        raw = str(TelegramBridgeService._get_env_value(key, "auto") or "").strip().lower()
        if raw in {"trend", "range", "auto"}:
            return str(raw)
        return "auto"

    @staticmethod
    def _mt4_exec_profile_hard_sl_mode(profile: str) -> str:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_HARD_SL_MODE"
        raw = str(TelegramBridgeService._get_env_value(key, "catastrophic") or "").strip().lower()
        if raw in {"none", "atr", "catastrophic"}:
            return str(raw)
        return "catastrophic"

    @staticmethod
    def _mt4_exec_profile_catastrophic_sl_atr(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_CATASTROPHIC_SL_ATR"
        try:
            raw = float(TelegramBridgeService._get_env_value(key, "9.0"))
        except Exception:
            raw = 9.0
        if not math.isfinite(float(raw)):
            raw = 9.0
        return max(2.0, min(40.0, float(raw)))

    @staticmethod
    def _mt4_exec_profile_regime_er_threshold(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_REGIME_ER_THRESHOLD"
        try:
            raw = float(TelegramBridgeService._get_env_value(key, "0.42"))
        except Exception:
            raw = 0.42
        if not math.isfinite(float(raw)):
            raw = 0.42
        return max(0.05, min(0.95, float(raw)))

    @staticmethod
    def _mt4_exec_profile_regime_donchian_atr_threshold(profile: str) -> float:
        p = TelegramBridgeService._mt4_exec_normalized_profile(profile)
        key = f"TELEGRAM_MT4_PROFILE_{str(p).upper()}_REGIME_DONCHIAN_ATR_THRESHOLD"
        try:
            raw = float(TelegramBridgeService._get_env_value(key, "3.0"))
        except Exception:
            raw = 3.0
        if not math.isfinite(float(raw)):
            raw = 3.0
        return max(0.5, min(20.0, float(raw)))

    @staticmethod
    def _calc_atr_from_bars(bars: Any, period: int = 14) -> Optional[float]:
        if not isinstance(bars, list) or len(bars) < 3:
            return None
        rows = [dict(x) for x in bars if isinstance(x, dict)]
        if len(rows) < 3:
            return None
        trs: List[float] = []
        for i in range(1, len(rows)):
            try:
                h = float(rows[i].get("high"))
                l = float(rows[i].get("low"))
                pc = float(rows[i - 1].get("close"))
            except Exception:
                continue
            if not all(math.isfinite(v) for v in (h, l, pc)):
                continue
            tr = max(abs(h - l), abs(h - pc), abs(l - pc))
            if math.isfinite(float(tr)) and float(tr) > 0.0:
                trs.append(float(tr))
        if not trs:
            return None
        n = max(1, min(int(period or 14), len(trs)))
        v = sum(trs[-n:]) / float(n)
        if not math.isfinite(float(v)) or float(v) <= 0.0:
            return None
        return float(v)

    @staticmethod
    def _calc_robust_atr_from_bars(bars: Any, period: int = 14) -> Optional[float]:
        """
        Robust ATR for stop placement:
        - uses fast ATR (period)
        - uses slower ATR (2*period)
        - uses TR percentile floor on recent window
        and returns a conservative (larger) volatility estimate.
        """
        if not isinstance(bars, list) or len(bars) < 3:
            return None
        rows = [dict(x) for x in bars if isinstance(x, dict)]
        if len(rows) < 3:
            return None
        trs: List[float] = []
        for i in range(1, len(rows)):
            try:
                h = float(rows[i].get("high"))
                l = float(rows[i].get("low"))
                pc = float(rows[i - 1].get("close"))
            except Exception:
                continue
            if not all(math.isfinite(v) for v in (h, l, pc)):
                continue
            tr = max(abs(h - l), abs(h - pc), abs(l - pc))
            if math.isfinite(float(tr)) and float(tr) > 0.0:
                trs.append(float(tr))
        if not trs:
            return None

        n_fast = max(1, min(int(period or 14), len(trs)))
        atr_fast = sum(trs[-n_fast:]) / float(n_fast)

        n_slow = max(n_fast, min(int(max(n_fast * 2, n_fast + 5)), len(trs)))
        atr_slow = sum(trs[-n_slow:]) / float(n_slow)

        lookback = max(n_fast, min(len(trs), 40))
        bucket = sorted(trs[-lookback:])
        idx = int(max(0, min(len(bucket) - 1, round((len(bucket) - 1) * 0.60))))
        tr_p60 = float(bucket[idx]) if bucket else float(atr_fast)

        robust = max(float(atr_fast), float(atr_slow) * 0.90, float(tr_p60))
        if not math.isfinite(float(robust)) or float(robust) <= 0.0:
            return None
        return float(robust)

    @staticmethod
    def _calc_adx_from_bars(bars: Any, period: int = 14) -> Optional[float]:
        rows = [dict(x) for x in (bars or []) if isinstance(x, dict)]
        p = int(max(5, min(50, int(period or 14))))
        if len(rows) < int((p * 3) + 5):
            return None
        highs: List[float] = []
        lows: List[float] = []
        closes: List[float] = []
        for r in rows:
            h = _to_float_or_none(r.get("high"))
            l = _to_float_or_none(r.get("low"))
            c = _to_float_or_none(r.get("close"))
            if h is None or l is None or c is None:
                continue
            if not (math.isfinite(float(h)) and math.isfinite(float(l)) and math.isfinite(float(c))):
                continue
            highs.append(float(h))
            lows.append(float(l))
            closes.append(float(c))
        if len(highs) < int((p * 3) + 5):
            return None
        tr: List[float] = []
        pdm: List[float] = []
        mdm: List[float] = []
        for i in range(1, len(highs)):
            up_move = float(highs[i] - highs[i - 1])
            dn_move = float(lows[i - 1] - lows[i])
            plus_dm = up_move if (up_move > dn_move and up_move > 0.0) else 0.0
            minus_dm = dn_move if (dn_move > up_move and dn_move > 0.0) else 0.0
            t = max(
                abs(float(highs[i] - lows[i])),
                abs(float(highs[i] - closes[i - 1])),
                abs(float(lows[i] - closes[i - 1])),
            )
            tr.append(float(max(t, 0.0)))
            pdm.append(float(max(plus_dm, 0.0)))
            mdm.append(float(max(minus_dm, 0.0)))
        if len(tr) < int(p + 2):
            return None
        # Wilder smoothing
        tr14 = sum(tr[:p])
        pdm14 = sum(pdm[:p])
        mdm14 = sum(mdm[:p])
        dx_vals: List[float] = []
        for i in range(p, len(tr)):
            tr14 = float(tr14 - (tr14 / float(p)) + tr[i])
            pdm14 = float(pdm14 - (pdm14 / float(p)) + pdm[i])
            mdm14 = float(mdm14 - (mdm14 / float(p)) + mdm[i])
            if tr14 <= 0.0:
                continue
            plus_di = float(100.0 * (pdm14 / tr14))
            minus_di = float(100.0 * (mdm14 / tr14))
            denom = float(plus_di + minus_di)
            if denom <= 0.0:
                continue
            dx = float(100.0 * abs(plus_di - minus_di) / denom)
            if math.isfinite(dx):
                dx_vals.append(float(dx))
        if len(dx_vals) < p:
            return None
        adx = float(sum(dx_vals[-p:]) / float(p))
        if not math.isfinite(adx):
            return None
        return float(max(0.0, min(100.0, adx)))

    @staticmethod
    def _calc_bb_width_from_bars(bars: Any, period: int = 20, stdev_mult: float = 2.0) -> Optional[float]:
        rows = [dict(x) for x in (bars or []) if isinstance(x, dict)]
        p = int(max(5, min(100, int(period or 20))))
        closes: List[float] = []
        for r in rows:
            c = _to_float_or_none(r.get("close"))
            if c is None or (not math.isfinite(float(c))):
                continue
            closes.append(float(c))
        if len(closes) < p:
            return None
        bucket = closes[-p:]
        mean = float(sum(bucket) / float(p))
        var = float(sum((x - mean) ** 2 for x in bucket) / float(p))
        std = float(math.sqrt(max(0.0, var)))
        width = float((mean + stdev_mult * std) - (mean - stdev_mult * std))
        if not math.isfinite(width):
            return None
        return float(max(0.0, width))

    @staticmethod
    def _estimate_mt4_market_regime(
        *,
        bars: Any,
        atr_value: Optional[float],
        efficiency_lookback: int = 16,
        er_threshold: float = 0.42,
        donchian_atr_threshold: float = 3.0,
    ) -> Dict[str, Any]:
        rows = [dict(x) for x in (bars or []) if isinstance(x, dict)]
        lookback = int(max(6, min(120, int(efficiency_lookback or 16))))
        if len(rows) < int(lookback + 2):
            return {"regime": "unknown", "efficiency_ratio": None, "donchian_atr_ratio": None}

        closes: List[float] = []
        highs: List[float] = []
        lows: List[float] = []
        for r in rows[-(lookback + 1):]:
            c = _to_float_or_none(r.get("close"))
            h = _to_float_or_none(r.get("high"))
            l = _to_float_or_none(r.get("low"))
            if c is None or h is None or l is None:
                continue
            if not (math.isfinite(float(c)) and math.isfinite(float(h)) and math.isfinite(float(l))):
                continue
            closes.append(float(c))
            highs.append(float(h))
            lows.append(float(l))
        if len(closes) < int(lookback + 1):
            return {"regime": "unknown", "efficiency_ratio": None, "donchian_atr_ratio": None}

        directional_move = abs(float(closes[-1]) - float(closes[0]))
        path_move = 0.0
        for i in range(1, len(closes)):
            path_move += abs(float(closes[i]) - float(closes[i - 1]))
        if path_move <= 0.0:
            er = 0.0
        else:
            er = float(directional_move / float(path_move))
        er = max(0.0, min(1.0, float(er)))

        donchian_width = float(max(highs) - min(lows))
        atr = _to_float_or_none(atr_value)
        if atr is None or float(atr) <= 0.0:
            atr = None
        donchian_atr_ratio = (float(donchian_width) / float(atr)) if atr else None

        regime = "range"
        if donchian_atr_ratio is None:
            regime = "trend" if float(er) >= float(er_threshold) else "range"
        elif float(er) >= float(er_threshold) and float(donchian_atr_ratio) >= float(donchian_atr_threshold):
            regime = "trend"

        return {
            "regime": str(regime),
            "efficiency_ratio": float(er),
            "donchian_atr_ratio": (_to_float_or_none(donchian_atr_ratio)),
        }

    def _close_mt4_reverse_positions(
        self,
        *,
        symbol: str,
        incoming_direction: str,
        timeframe: Optional[str] = None,
        source_tag: Optional[str] = None,
        close_reason: Optional[str] = None,
    ) -> Dict[str, Any]:
        sym = str(symbol or "").strip().upper()
        incoming = str(incoming_direction or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        wanted_tag = str(source_tag or "").strip().lower()
        if not sym or incoming not in {"BUY", "SELL"}:
            return {"ok": False, "error": "invalid_reverse_close_payload"}
        opposite = "SELL" if incoming == "BUY" else "BUY"
        reason_txt = str(close_reason or "").strip() or "closed_by_reverse_signal"
        svc = self._get_live_service()

        with self._lock:
            ladders = {str(k): dict(v) for k, v in self._active_confirmation_signal_ladders.items()}

        remove_keys: List[str] = []
        closed_tickets: set[int] = set()
        failed: List[str] = []
        closed_count = 0

        def _is_position_missing_error(err: Any) -> bool:
            txt = str(err or "").strip().lower()
            if not txt:
                return False
            needles = (
                "position_not_found",
                "trade_not_open_or_not_found",
                "position not found",
                "not found",
            )
            return any(n in txt for n in needles)

        for key, row in ladders.items():
            row_sym = str((row or {}).get("symbol") or "").strip().upper()
            row_dir = str((row or {}).get("direction") or "").strip().upper()
            row_tf = str((row or {}).get("timeframe") or "").strip().upper()
            row_tag = str((row or {}).get("source_tag") or "").strip().lower()
            ticket = int((row or {}).get("broker_ticket") or 0)
            if row_sym != sym or row_dir != opposite or ticket <= 0:
                continue
            if tf and row_tf and row_tf != tf:
                continue
            if wanted_tag and row_tag != wanted_tag:
                continue
            if not self._is_bridge_source_tag(row_tag):
                continue
            out = svc.close_position(
                symbol=str(sym),
                position_ticket=int(ticket),
                comment="mt4_reverse_close",
            )
            if bool((out or {}).get("ok")):
                closed_count += 1
                closed_tickets.add(int(ticket))
                self._append_closed_execution_log_from_row(
                    row=dict(row),
                    reason=str(reason_txt),
                    svc=svc,
                )
                remove_keys.append(str(key))
            else:
                err_txt = str((out or {}).get("error") or "close_failed")[:120]
                if _is_position_missing_error(err_txt):
                    # Stale in-memory ladder ticket; prune and continue (do not block new signal open).
                    remove_keys.append(str(key))
                    logger.info(
                        "mt4_reverse_close_stale_ladder_pruned ticket=%s symbol=%s tag=%s err=%s",
                        int(ticket),
                        str(sym),
                        str(row_tag),
                        str(err_txt),
                    )
                else:
                    failed.append(f"ladder#{int(ticket)}:{str(err_txt)}")

        # Deterministic isolation: when a combo-specific source_tag is provided,
        # fallback-close only orphan tickets from execution logs for the exact combo.
        if wanted_tag:
            matched = int(closed_count)
            if matched <= 0:
                orphan_tickets = self._find_orphan_open_tickets_for_source_tag(
                    source_tag=str(wanted_tag),
                    symbol=str(sym),
                    timeframe=str(tf or ""),
                    direction=str(opposite),
                )
                for ticket in orphan_tickets:
                    if int(ticket) in closed_tickets:
                        continue
                    out = svc.close_position(
                        symbol=str(sym),
                        position_ticket=int(ticket),
                        comment="mt4_reverse_close_orphan",
                    )
                    if bool((out or {}).get("ok")):
                        closed_count += 1
                        closed_tickets.add(int(ticket))
                        self._append_automation_execution_log(
                            source_type="mt_indicator",
                            source_name="mt4_reverse_close_orphan",
                            trigger="reverse_signal",
                            status="closed",
                            symbol=str(sym),
                            timeframe=str(tf or ""),
                            direction=str(opposite),
                            ticket=int(ticket),
                            message=f"{str(reason_txt)}_orphan",
                            source_tag=str(wanted_tag),
                            combo_key=self._build_execution_combo_key(
                                source_type="mt_indicator",
                                source_name="mt4_reverse_close_orphan",
                                indicator="",
                                symbol=str(sym),
                                timeframe=str(tf or ""),
                            ),
                        )
                    else:
                        err_txt = str((out or {}).get("error") or "close_failed")[:120]
                        if _is_position_missing_error(err_txt):
                            # DB orphan ticket is stale: mark it closed to avoid repeated retries.
                            self._append_automation_execution_log(
                                source_type="mt_indicator",
                                source_name="mt4_reverse_close_orphan",
                                trigger="reverse_signal",
                                status="closed",
                                symbol=str(sym),
                                timeframe=str(tf or ""),
                                direction=str(opposite),
                                ticket=int(ticket),
                                message=f"{str(reason_txt)}_orphan_not_found",
                                source_tag=str(wanted_tag),
                                combo_key=self._build_execution_combo_key(
                                    source_type="mt_indicator",
                                    source_name="mt4_reverse_close_orphan",
                                    indicator="",
                                    symbol=str(sym),
                                    timeframe=str(tf or ""),
                                ),
                            )
                            logger.info(
                                "mt4_reverse_close_stale_orphan_pruned ticket=%s symbol=%s tag=%s err=%s",
                                int(ticket),
                                str(sym),
                                str(wanted_tag),
                                str(err_txt),
                            )
                        else:
                            failed.append(f"orphan#{int(ticket)}:{str(err_txt)}")

            # Recovery pass: close broker-live tickets that belong to this source_tag
            # even if DB history already contains a stale "closed" row.
            historical_tickets = self._find_historical_tickets_for_source_tag(
                source_tag=str(wanted_tag),
                symbol=str(sym),
                timeframe=str(tf or ""),
                direction=str(opposite),
                limit=50000,
            )
            if historical_tickets:
                try:
                    open_rows = svc.get_open_positions(symbol=str(sym)) or []
                except Exception:
                    open_rows = []
                for pos in open_rows:
                    ticket = int(_to_float_or_none((pos or {}).get("ticket")) or 0)
                    pos_dir = str((pos or {}).get("direction") or "").strip().upper()
                    if ticket <= 0 or pos_dir != opposite:
                        continue
                    if int(ticket) in closed_tickets:
                        continue
                    if int(ticket) not in historical_tickets:
                        continue
                    out = svc.close_position(
                        symbol=str(sym),
                        position_ticket=int(ticket),
                        comment="mt4_reverse_close_recover",
                    )
                    if bool((out or {}).get("ok")):
                        closed_count += 1
                        closed_tickets.add(int(ticket))
                        self._append_automation_execution_log(
                            source_type="mt_indicator",
                            source_name="mt4_reverse_close_orphan",
                            trigger="reverse_signal",
                            status="closed",
                            symbol=str(sym),
                            timeframe=str(tf or ""),
                            direction=str(opposite),
                            ticket=int(ticket),
                            message=f"{str(reason_txt)}_orphan_recovered",
                            source_tag=str(wanted_tag),
                            combo_key=self._build_execution_combo_key(
                                source_type="mt_indicator",
                                source_name="mt4_reverse_close_orphan",
                                indicator="",
                                symbol=str(sym),
                                timeframe=str(tf or ""),
                            ),
                        )
                    else:
                        err_txt = str((out or {}).get("error") or "close_failed")[:120]
                        if _is_position_missing_error(err_txt):
                            self._append_automation_execution_log(
                                source_type="mt_indicator",
                                source_name="mt4_reverse_close_orphan",
                                trigger="reverse_signal",
                                status="closed",
                                symbol=str(sym),
                                timeframe=str(tf or ""),
                                direction=str(opposite),
                                ticket=int(ticket),
                                message=f"{str(reason_txt)}_orphan_not_found",
                                source_tag=str(wanted_tag),
                                combo_key=self._build_execution_combo_key(
                                    source_type="mt_indicator",
                                    source_name="mt4_reverse_close_orphan",
                                    indicator="",
                                    symbol=str(sym),
                                    timeframe=str(tf or ""),
                                ),
                            )
                        else:
                            failed.append(f"recover#{int(ticket)}:{str(err_txt)}")

        # Legacy fallback (tagless) for generic mt4 comments.
        if not wanted_tag:
            try:
                open_rows = svc.get_open_positions(symbol=str(sym)) or []
            except Exception:
                open_rows = []
            for pos in open_rows:
                ticket = int((pos or {}).get("ticket") or 0)
                pos_dir = str((pos or {}).get("direction") or "").strip().upper()
                comment = str((pos or {}).get("comment") or "").strip().lower()
                if ticket <= 0 or pos_dir != opposite:
                    continue
                if int(ticket) in closed_tickets:
                    continue
                if not comment.startswith("mt4"):
                    continue
                out = svc.close_position(
                    symbol=str(sym),
                    position_ticket=int(ticket),
                    comment="mt4_reverse_close",
                )
                if bool((out or {}).get("ok")):
                    closed_count += 1
                    closed_tickets.add(int(ticket))
                    self._append_automation_execution_log(
                        source_type="mt_indicator",
                        source_name="mt4_reverse_close",
                        trigger="reverse_signal",
                        status="closed",
                        symbol=str(sym),
                        timeframe=str(tf or ""),
                        direction=str(opposite),
                        ticket=int(ticket),
                        message=f"{str(reason_txt)}_fallback",
                        source_tag="mt4|reverse",
                        combo_key=self._build_execution_combo_key(
                            source_type="mt_indicator",
                            source_name="mt4_reverse_close",
                            indicator="",
                            symbol=str(sym),
                            timeframe=str(tf or ""),
                        ),
                    )
                    # if this ticket exists in ladder map, remove it too
                    for key, row in ladders.items():
                        if int((row or {}).get("broker_ticket") or 0) == int(ticket):
                            remove_keys.append(str(key))
                else:
                    err_txt = str((out or {}).get("error") or "close_failed")[:120]
                    if _is_position_missing_error(err_txt):
                        logger.info(
                            "mt4_reverse_close_stale_pos_ignored ticket=%s symbol=%s err=%s",
                            int(ticket),
                            str(sym),
                            str(err_txt),
                        )
                    else:
                        failed.append(f"pos#{int(ticket)}:{str(err_txt)}")

        if remove_keys:
            with self._lock:
                for key in set(remove_keys):
                    self._active_confirmation_signal_ladders.pop(str(key), None)
        if int(closed_count) > 0 and str(wanted_tag):
            self._clear_indicator_recent_open(source_tag=str(wanted_tag))

        if failed:
            return {
                "ok": False,
                "closed_count": int(closed_count),
                "failed_count": int(len(failed)),
                "errors": failed[:8],
            }
        return {"ok": True, "closed_count": int(closed_count), "failed_count": 0}

    def _find_orphan_open_tickets_for_source_tag(
        self,
        *,
        source_tag: str,
        symbol: str,
        timeframe: str,
        direction: str,
        limit: int = 20000,
    ) -> List[int]:
        wanted_tag = str(source_tag or "").strip().lower()
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        d = str(direction or "").strip().upper()
        if not wanted_tag or not sym or d not in {"BUY", "SELL"}:
            return []
        lim = int(max(200, min(100000, int(limit or 20000))))
        db = SessionLocal()
        try:
            q = (
                db.query(TelegramAutomationExecutionLogModel)
                .filter(TelegramAutomationExecutionLogModel.source_type == "mt_indicator")
                .filter(TelegramAutomationExecutionLogModel.source_tag == wanted_tag)
                .filter(TelegramAutomationExecutionLogModel.symbol == sym)
                .filter(TelegramAutomationExecutionLogModel.direction == d)
            )
            if tf:
                q = q.filter(TelegramAutomationExecutionLogModel.timeframe == tf)
            rows = (
                q.order_by(TelegramAutomationExecutionLogModel.id.desc())
                .limit(int(lim))
                .all()
            )
        except Exception:
            logger.exception(
                "mt4_reverse_orphan_query_failed tag=%s symbol=%s timeframe=%s direction=%s",
                wanted_tag,
                sym,
                tf,
                d,
            )
            return []
        finally:
            try:
                db.close()
            except Exception:
                pass

        opened: set[int] = set()
        closed: set[int] = set()
        for r in rows:
            ticket = int(r.ticket or 0)
            if ticket <= 0:
                continue
            status = str(r.status or "").strip().lower()
            if status == "opened":
                opened.add(int(ticket))
            elif status == "closed":
                closed.add(int(ticket))
        return sorted(int(t) for t in (opened - closed) if int(t) > 0)

    def _find_historical_tickets_for_source_tag(
        self,
        *,
        source_tag: str,
        symbol: str,
        timeframe: str,
        direction: str,
        limit: int = 50000,
    ) -> set[int]:
        wanted_tag = str(source_tag or "").strip().lower()
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        d = str(direction or "").strip().upper()
        if not wanted_tag or not sym or d not in {"BUY", "SELL"}:
            return set()
        lim = int(max(500, min(200000, int(limit or 50000))))
        db = SessionLocal()
        try:
            q = (
                db.query(TelegramAutomationExecutionLogModel.ticket)
                .filter(TelegramAutomationExecutionLogModel.source_type == "mt_indicator")
                .filter(TelegramAutomationExecutionLogModel.source_tag == wanted_tag)
                .filter(TelegramAutomationExecutionLogModel.symbol == sym)
                .filter(TelegramAutomationExecutionLogModel.direction == d)
                .filter(TelegramAutomationExecutionLogModel.ticket.isnot(None))
            )
            if tf:
                q = q.filter(TelegramAutomationExecutionLogModel.timeframe == tf)
            rows = (
                q.order_by(TelegramAutomationExecutionLogModel.id.desc())
                .limit(int(lim))
                .all()
            )
        except Exception:
            logger.exception(
                "mt4_reverse_historical_query_failed tag=%s symbol=%s timeframe=%s direction=%s",
                wanted_tag,
                sym,
                tf,
                d,
            )
            return set()
        finally:
            try:
                db.close()
            except Exception:
                pass

        out: set[int] = set()
        for r in rows:
            try:
                t = int(getattr(r, "ticket", 0) or 0)
            except Exception:
                t = 0
            if t > 0:
                out.add(int(t))
        return out

    def _has_live_open_for_source_tag_direction(
        self,
        *,
        source_tag: str,
        symbol: str,
        timeframe: str,
        direction: str,
        svc: LiveTradingService,
    ) -> bool:
        wanted_tag = str(source_tag or "").strip().lower()
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        d = str(direction or "").strip().upper()
        if not wanted_tag or not sym or d not in {"BUY", "SELL"}:
            return False
        try:
            open_rows = svc.get_open_positions(symbol=str(sym)) or []
        except Exception:
            open_rows = []
        live_tickets: set[int] = set()
        for row in open_rows:
            t = int(_to_float_or_none((row or {}).get("ticket")) or 0)
            if t > 0:
                live_tickets.add(int(t))
        if not live_tickets:
            return False

        with self._lock:
            ladders = [dict(v) for v in self._active_confirmation_signal_ladders.values() if isinstance(v, dict)]
        for row in ladders:
            row_tag = str((row or {}).get("source_tag") or "").strip().lower()
            row_sym = str((row or {}).get("symbol") or "").strip().upper()
            row_tf = str((row or {}).get("timeframe") or "").strip().upper()
            row_dir = str((row or {}).get("direction") or "").strip().upper()
            row_ticket = int(_to_float_or_none((row or {}).get("broker_ticket")) or 0)
            if row_tag != wanted_tag or row_sym != sym or row_dir != d or row_ticket <= 0:
                continue
            if tf and row_tf and row_tf != tf:
                continue
            if int(row_ticket) in live_tickets:
                return True

        orphan = self._find_orphan_open_tickets_for_source_tag(
            source_tag=str(wanted_tag),
            symbol=str(sym),
            timeframe=str(tf),
            direction=str(d),
            limit=20000,
        )
        for t in orphan:
            if int(t) in live_tickets:
                return True
        historical = self._find_historical_tickets_for_source_tag(
            source_tag=str(wanted_tag),
            symbol=str(sym),
            timeframe=str(tf),
            direction=str(d),
            limit=50000,
        )
        for t in historical:
            if int(t) in live_tickets:
                return True
        return False

    @staticmethod
    def _indicator_sync_base_key(*, family: Any, profile: Any, indicator_key: Any, symbol: Any) -> str:
        return (
            f"{str(family or '').strip().lower()}|{str(profile or '').strip().lower()}|"
            f"{str(indicator_key or '').strip().lower()}|{str(symbol or '').strip().upper()}"
        )

    @classmethod
    def _build_sync_mode_source_tag(
        cls,
        *,
        family: Any,
        profile: Any,
        indicator_key: Any,
        symbol: Any,
        direction_tf: Any,
        entry_tf: Any,
        exit_tf: Any,
    ) -> str:
        fam = cls._indicator_bridge_family(family)
        prof = str(profile or "").strip().lower()
        ikey = cls._normalize_mt_indicator_key(indicator_key)
        sym = str(symbol or "").strip().upper()
        d_tf = cls._normalize_tf_token(direction_tf, "M5")
        e_tf = cls._normalize_tf_token(entry_tf, "M1")
        x_tf = cls._normalize_tf_token(exit_tf, "M1")
        return f"{fam}|{prof}|{ikey}|{sym}|sync|d={d_tf}|e={e_tf}|x={x_tf}".lower()

    def _record_indicator_sync_direction(
        self,
        *,
        base_key: str,
        timeframe: str,
        direction: str,
        now_ts: float,
        message: Any = None,
    ) -> None:
        bk = str(base_key or "").strip().lower()
        tf = self._normalize_tf_token(timeframe, "M5")
        side = str(direction or "").strip().upper()
        if not bk or side not in {"BUY", "SELL"}:
            return
        with self._lock:
            row = dict(self._indicator_sync_last_dir.get(bk) or {})
            row[tf] = {
                "direction": str(side),
                "seen_ts": float(now_ts),
                "message": str(message or "")[:180],
            }
            self._indicator_sync_last_dir[bk] = row
            if len(self._indicator_sync_last_dir) > 5000:
                cutoff = float(now_ts) - 7.0 * 86400.0
                compacted: Dict[str, Dict[str, Dict[str, Any]]] = {}
                for k, v in self._indicator_sync_last_dir.items():
                    if not isinstance(v, dict):
                        continue
                    vv = {
                        str(tfk): dict(tfr)
                        for tfk, tfr in v.items()
                        if float(_to_float_or_none((tfr or {}).get("seen_ts")) or 0.0) >= cutoff
                    }
                    if vv:
                        compacted[str(k)] = vv
                self._indicator_sync_last_dir = compacted

    def _read_indicator_sync_direction(
        self,
        *,
        base_key: str,
        timeframe: str,
    ) -> Optional[str]:
        bk = str(base_key or "").strip().lower()
        tf = self._normalize_tf_token(timeframe, "M5")
        if not bk:
            return None
        with self._lock:
            row = dict(self._indicator_sync_last_dir.get(bk) or {})
        side = str((row.get(tf) or {}).get("direction") or "").strip().upper()
        if side in {"BUY", "SELL"}:
            return str(side)
        return None

    def _record_indicator_rsi_telemetry(
        self,
        *,
        family: str,
        symbol: str,
        timeframe: str,
        indicator: str,
        profile: str,
        rsi_value: float,
        now_ts: float,
        event_ts: Any = None,
        indicator_tf: Any = None,
        rsi_period: Any = None,
    ) -> Dict[str, Any]:
        fam = str(self._indicator_bridge_family(family))
        sym = str(symbol or "").strip().upper()
        tf = self._normalize_tf_token(timeframe, "M5")
        ind = str(indicator or "").strip() or "RSI"
        prof = str(profile or "").strip().lower() or "rsi_telemetry"
        key = f"{fam}|{sym}|{tf}"
        row: Dict[str, Any] = {
            "key": str(key),
            "terminal_family": str(fam),
            "symbol": str(sym),
            "timeframe": str(tf),
            "indicator": str(ind),
            "signal_profile": str(prof),
            "rsi_value": float(rsi_value),
            "seen_ts": float(now_ts),
            "event_ts": event_ts,
            "indicator_tf": str(indicator_tf or "").strip().upper(),
            "rsi_period": (_to_float_or_none(rsi_period)),
        }
        with self._lock:
            self._indicator_rsi_telemetry_seq = int(self._indicator_rsi_telemetry_seq) + 1
            row["seq"] = int(self._indicator_rsi_telemetry_seq)
            self._indicator_rsi_telemetry[str(key)] = dict(row)
            if len(self._indicator_rsi_telemetry) > 10000:
                cutoff = float(now_ts) - 86400.0
                self._indicator_rsi_telemetry = {
                    str(k): dict(v)
                    for k, v in self._indicator_rsi_telemetry.items()
                    if float(_to_float_or_none((v or {}).get("seen_ts")) or 0.0) >= cutoff
                }
        return dict(row)

    def _latest_indicator_rsi_telemetry(
        self,
        *,
        family: str,
        symbol: str,
        timeframe: str,
        max_age_sec: float = 300.0,
    ) -> Optional[Dict[str, Any]]:
        fam = str(self._indicator_bridge_family(family))
        sym = str(symbol or "").strip().upper()
        tf = self._normalize_tf_token(timeframe, "M5")
        key = f"{fam}|{sym}|{tf}"
        with self._lock:
            row = dict(self._indicator_rsi_telemetry.get(str(key)) or {})
        if not row:
            return None
        seen_ts = float(_to_float_or_none(row.get("seen_ts")) or 0.0)
        if seen_ts <= 0.0:
            return None
        if float(max_age_sec) > 0.0 and (time.time() - float(seen_ts)) > float(max_age_sec):
            return None
        val = _to_float_or_none(row.get("rsi_value"))
        if val is None or (not math.isfinite(float(val))):
            return None
        row["rsi_value"] = float(val)
        return dict(row)

    def get_indicator_rsi_telemetry(
        self,
        *,
        limit: int = 300,
        terminal_family: Optional[str] = None,
    ) -> Dict[str, Any]:
        lim = int(max(10, min(5000, int(limit or 300))))
        family_filter = str(terminal_family or "").strip().lower()
        with self._lock:
            seq = int(self._indicator_rsi_telemetry_seq)
            rows = [dict(v) for v in self._indicator_rsi_telemetry.values() if isinstance(v, dict)]
        if family_filter in {"mt4", "mt5"}:
            rows = [r for r in rows if str(r.get("terminal_family") or "").strip().lower() == family_filter]
        rows.sort(key=lambda r: float(_to_float_or_none(r.get("seen_ts")) or 0.0), reverse=True)
        rows = rows[:lim]
        for row in rows:
            seen_ts = _to_float_or_none(row.get("seen_ts"))
            if seen_ts is None:
                row["seen_at"] = ""
            else:
                row["seen_at"] = datetime.fromtimestamp(float(seen_ts), tz=timezone.utc).isoformat()
        return {
            "ok": True,
            "rows": rows,
            "count": int(len(rows)),
            "seq": int(seq),
            "updated_at": self._now_iso(),
        }

    def _check_indicator_reversal_stability(
        self,
        *,
        combo_source_tag: str,
        incoming_direction: str,
        now_ts: float,
        force_wait: bool = False,
        confirm_sec: Optional[float] = None,
    ) -> Dict[str, Any]:
        combo = str(combo_source_tag or "").strip().lower()
        direction = str(incoming_direction or "").strip().upper()
        if not combo or direction not in {"BUY", "SELL"}:
            return {"ok": True, "ready": True, "reason": "invalid_guard_input"}

        wait_sec = _to_float_or_none(confirm_sec)
        if wait_sec is None:
            wait_sec = float(self._indicator_reversal_confirm_sec())
        wait_sec = float(max(0.0, min(300.0, float(wait_sec))))
        if wait_sec <= 0.0:
            return {"ok": True, "ready": True, "reason": "guard_disabled"}

        opposite = "SELL" if direction == "BUY" else "BUY"
        with self._lock:
            has_opposite_active = any(
                isinstance(v, dict)
                and str((v or {}).get("source_tag") or "").strip().lower() == combo
                and str((v or {}).get("direction") or "").strip().upper() == opposite
                and int(_to_float_or_none((v or {}).get("broker_ticket")) or 0) > 0
                for v in self._active_confirmation_signal_ladders.values()
            )
            pending = dict(self._indicator_reversal_pending.get(str(combo)) or {})

        pending_dir = str(pending.get("direction") or "").strip().upper()
        has_pending_same_dir = bool(pending_dir == direction)
        should_wait = bool(force_wait) or bool(has_opposite_active) or bool(has_pending_same_dir)
        if not bool(should_wait):
            with self._lock:
                self._indicator_reversal_pending.pop(str(combo), None)
            return {"ok": True, "ready": True, "reason": "no_reverse_guard_needed"}

        first_seen_ts = float(now_ts)
        seen_count = 1
        if has_pending_same_dir:
            first_seen_ts = float(_to_float_or_none(pending.get("first_seen_ts")) or now_ts)
            seen_count = int(_to_float_or_none(pending.get("seen_count")) or 1) + 1

        elapsed = float(max(0.0, float(now_ts) - float(first_seen_ts)))
        if elapsed < float(wait_sec):
            remaining = float(max(0.0, float(wait_sec) - float(elapsed)))
            with self._lock:
                prev_pending = dict(self._indicator_reversal_pending.get(str(combo)) or {})
                next_pending = {
                    "direction": str(direction),
                    "first_seen_ts": float(first_seen_ts),
                    "last_seen_ts": float(now_ts),
                    "required_sec": float(wait_sec),
                    "seen_count": int(max(1, int(seen_count))),
                }
                for extra_key in (
                    "replay_terminal_family",
                    "replay_payload",
                    "replay_queued_ts",
                    "replay_last_attempt_ts",
                ):
                    if extra_key in prev_pending:
                        next_pending[extra_key] = prev_pending.get(extra_key)
                self._indicator_reversal_pending[str(combo)] = dict(next_pending)
                if len(self._indicator_reversal_pending) > 5000:
                    cutoff = float(now_ts) - 86400.0
                    self._indicator_reversal_pending = {
                        str(k): dict(v)
                        for k, v in self._indicator_reversal_pending.items()
                        if float(_to_float_or_none((v or {}).get("last_seen_ts")) or 0.0) >= cutoff
                    }
            return {
                "ok": True,
                "ready": False,
                "reason": "reversal_guard_waiting",
                "required_sec": float(wait_sec),
                "elapsed_sec": float(elapsed),
                "remaining_sec": float(remaining),
            }

        with self._lock:
            self._indicator_reversal_pending.pop(str(combo), None)
        return {
            "ok": True,
            "ready": True,
            "reason": "reversal_guard_passed",
            "required_sec": float(wait_sec),
            "elapsed_sec": float(elapsed),
        }

    def _clear_indicator_reversal_pending_for_combo_prefix(self, *, combo_prefix: str) -> int:
        prefix = str(combo_prefix or "").strip().lower()
        if not prefix:
            return 0
        removed = 0
        with self._lock:
            keys = list((self._indicator_reversal_pending or {}).keys())
            for k in keys:
                kk = str(k or "").strip().lower()
                if kk == prefix or kk.startswith(prefix + "|"):
                    self._indicator_reversal_pending.pop(str(k), None)
                    removed += 1
        return int(removed)

    def _clear_indicator_signal_dedupe_for_combo_prefix(self, *, combo_prefix: str) -> int:
        prefix = str(combo_prefix or "").strip().lower()
        if not prefix:
            return 0
        match_prefix = str(prefix) + "|"
        removed = 0
        with self._lock:
            keys = list((self._mt4_signal_dedupe or {}).keys())
            for k in keys:
                kk = str(k or "").strip().lower()
                if kk.startswith(match_prefix):
                    self._mt4_signal_dedupe.pop(str(k), None)
                    removed += 1
        return int(removed)

    def _check_and_mark_indicator_event_id(
        self,
        *,
        family: str,
        indicator_key: str,
        symbol: str,
        timeframe: str,
        event_id: str,
        now_ts: float,
    ) -> bool:
        eid = str(event_id or "").strip()
        if not eid:
            return True
        key = (
            f"{str(family or '').strip().lower()}|{str(indicator_key or '').strip().lower()}|"
            f"{str(symbol or '').strip().upper()}|{str(timeframe or '').strip().upper()}|{eid}"
        )
        win = float(self._indicator_event_id_window_sec())
        with self._lock:
            prev = float(self._indicator_event_id_seen.get(str(key)) or 0.0)
            if prev > 0.0 and (float(now_ts) - float(prev)) <= float(win):
                return False
            self._indicator_event_id_seen[str(key)] = float(now_ts)
            if len(self._indicator_event_id_seen) > 20000:
                cutoff = float(now_ts) - float(win)
                self._indicator_event_id_seen = {
                    str(k): float(v)
                    for k, v in self._indicator_event_id_seen.items()
                    if float(v) >= float(cutoff)
                }
        return True

    def _record_indicator_last_valid_direction(
        self,
        *,
        combo_prefix: str,
        direction: str,
        now_ts: float,
        indicator: str,
        profile: str,
        symbol: str,
        timeframe: str,
    ) -> None:
        combo = str(combo_prefix or "").strip().lower()
        side = str(direction or "").strip().upper()
        if not combo or side not in {"BUY", "SELL"}:
            return
        with self._lock:
            prev_row = dict(self._indicator_last_valid_signal.get(str(combo)) or {})
        current_dir = str(prev_row.get("direction") or "").strip().upper()
        previous_dir = str(prev_row.get("previous_direction") or "").strip().upper()
        current_seen = float(_to_float_or_none(prev_row.get("seen_ts")) or 0.0)
        previous_seen = float(_to_float_or_none(prev_row.get("previous_seen_ts")) or 0.0)

        if side != current_dir:
            if current_dir in {"BUY", "SELL"}:
                previous_dir = str(current_dir)
                previous_seen = float(current_seen or now_ts)
            current_dir = str(side)
            current_seen = float(now_ts)
        else:
            current_seen = float(now_ts)

        row = {
            "direction": str(current_dir),
            "seen_ts": float(current_seen),
            "previous_direction": (str(previous_dir) if previous_dir in {"BUY", "SELL"} else ""),
            "previous_seen_ts": (float(previous_seen) if previous_dir in {"BUY", "SELL"} else 0.0),
            "indicator": str(indicator or ""),
            "profile": str(profile or ""),
            "symbol": str(symbol or "").strip().upper(),
            "timeframe": str(timeframe or "").strip().upper(),
        }
        with self._lock:
            self._indicator_last_valid_signal[str(combo)] = dict(row)
            if len(self._indicator_last_valid_signal) > 10000:
                cutoff = float(now_ts) - float(self._indicator_clear_fallback_max_age_sec())
                self._indicator_last_valid_signal = {
                    str(k): dict(v)
                    for k, v in self._indicator_last_valid_signal.items()
                    if float(_to_float_or_none((v or {}).get("seen_ts")) or 0.0) >= cutoff
                }

    def _read_indicator_last_valid_direction(self, *, combo_prefix: str, now_ts: float) -> Tuple[Optional[str], float]:
        combo = str(combo_prefix or "").strip().lower()
        if not combo:
            return (None, 0.0)
        with self._lock:
            row = dict(self._indicator_last_valid_signal.get(str(combo)) or {})
        side_current = str((row or {}).get("direction") or "").strip().upper()
        ts_current = float(_to_float_or_none((row or {}).get("seen_ts")) or 0.0)
        side_prev = str((row or {}).get("previous_direction") or "").strip().upper()
        ts_prev = float(_to_float_or_none((row or {}).get("previous_seen_ts")) or 0.0)

        # Clear fallback should prefer previous stable direction when available.
        if side_prev in {"BUY", "SELL"} and ts_prev > 0.0:
            side = str(side_prev)
            seen_ts = float(ts_prev)
        else:
            side = str(side_current)
            seen_ts = float(ts_current)

        age = float(max(0.0, float(now_ts) - float(seen_ts))) if seen_ts > 0.0 else 0.0
        if side not in {"BUY", "SELL"} or seen_ts <= 0.0:
            return (None, age)
        if age > float(self._indicator_clear_fallback_max_age_sec()):
            return (None, age)
        return (str(side), age)

    def _check_indicator_clear_fallback_cooldown(self, *, combo_prefix: str, now_ts: float) -> bool:
        combo = str(combo_prefix or "").strip().lower()
        if not combo:
            return False
        cool = float(self._indicator_clear_fallback_cooldown_sec())
        with self._lock:
            prev = float(self._indicator_clear_fallback_last_ts.get(str(combo)) or 0.0)
        if prev > 0.0 and (float(now_ts) - float(prev)) < float(cool):
            return False
        return True

    def _mark_indicator_clear_fallback(self, *, combo_prefix: str, now_ts: float) -> None:
        combo = str(combo_prefix or "").strip().lower()
        if not combo:
            return
        with self._lock:
            self._indicator_clear_fallback_last_ts[str(combo)] = float(now_ts)
            if len(self._indicator_clear_fallback_last_ts) > 10000:
                cutoff = float(now_ts) - float(max(60.0, self._indicator_clear_fallback_max_age_sec()))
                self._indicator_clear_fallback_last_ts = {
                    str(k): float(v)
                    for k, v in self._indicator_clear_fallback_last_ts.items()
                    if float(v) >= cutoff
                }

    def _queue_indicator_reversal_replay(
        self,
        *,
        combo_source_tag: str,
        terminal_family: str,
        payload: Dict[str, Any],
        now_ts: float,
    ) -> None:
        combo = str(combo_source_tag or "").strip().lower()
        if not combo or not isinstance(payload, dict) or not payload:
            return
        with self._lock:
            row = dict(self._indicator_reversal_pending.get(str(combo)) or {})
            row["replay_terminal_family"] = str(self._indicator_bridge_family(terminal_family))
            row["replay_payload"] = dict(payload)
            row["replay_queued_ts"] = float(now_ts)
            self._indicator_reversal_pending[str(combo)] = dict(row)
        # Deterministic fallback: process reversal replay even if polling/maintenance
        # loops are not running (or are delayed by long-poll blocking).
        self._schedule_indicator_reversal_replay(combo_source_tag=str(combo))

    def _schedule_indicator_reversal_replay(self, *, combo_source_tag: str) -> None:
        combo = str(combo_source_tag or "").strip().lower()
        if not combo:
            return
        with self._lock:
            if combo in self._indicator_reversal_replay_inflight:
                return
            row = dict(self._indicator_reversal_pending.get(str(combo)) or {})
            required = float(_to_float_or_none(row.get("required_sec")) or 0.0)
            first_seen = float(_to_float_or_none(row.get("first_seen_ts")) or 0.0)
            if required <= 0.0 or first_seen <= 0.0:
                return
            self._indicator_reversal_replay_inflight.add(str(combo))

        def _worker() -> None:
            # Keep a bounded retry window to avoid stuck pending entries.
            timeout_at = float(time.time()) + 90.0
            try:
                while not self._stop.is_set():
                    with self._lock:
                        raw = dict(self._indicator_reversal_pending.get(str(combo)) or {})
                    if not raw:
                        return
                    required_sec = float(_to_float_or_none(raw.get("required_sec")) or 0.0)
                    first_ts = float(_to_float_or_none(raw.get("first_seen_ts")) or 0.0)
                    if required_sec <= 0.0 or first_ts <= 0.0:
                        return
                    due_ts = float(first_ts) + float(required_sec)
                    now_ts = float(time.time())
                    if now_ts < due_ts:
                        self._stop.wait(min(1.0, max(0.05, due_ts - now_ts)))
                        continue

                    # Due reached: actively push replay until combo clears or timeout.
                    self._process_indicator_reversal_pending_replays()
                    with self._lock:
                        still_pending = bool(self._indicator_reversal_pending.get(str(combo)))
                    if not still_pending:
                        return
                    if float(time.time()) >= float(timeout_at):
                        logger.warning(
                            "indicator_reversal_replay_timeout combo=%s pending_not_cleared",
                            str(combo),
                        )
                        return
                    self._stop.wait(1.0)
            except Exception as exc:
                logger.warning(
                    "indicator_reversal_replay_worker_failed combo=%s err=%s",
                    str(combo),
                    str(exc)[:220],
                )
            finally:
                with self._lock:
                    self._indicator_reversal_replay_inflight.discard(str(combo))

        th = threading.Thread(
            target=_worker,
            daemon=True,
            name=f"indicator-reversal-replay-{str(combo)[-20:]}",
        )
        th.start()

    def _process_indicator_reversal_pending_replays(self) -> None:
        now_ts = float(time.time())
        candidates: List[Tuple[str, str, Dict[str, Any]]] = []
        with self._lock:
            for combo, raw in (self._indicator_reversal_pending or {}).items():
                row = dict(raw or {})
                required = float(_to_float_or_none(row.get("required_sec")) or 0.0)
                first_seen = float(_to_float_or_none(row.get("first_seen_ts")) or 0.0)
                family = str(row.get("replay_terminal_family") or "").strip().lower()
                payload = row.get("replay_payload")
                if required <= 0.0 or first_seen <= 0.0:
                    continue
                if (now_ts - float(first_seen)) < float(required):
                    continue
                if not family or not isinstance(payload, dict) or not payload:
                    continue
                last_attempt = float(_to_float_or_none(row.get("replay_last_attempt_ts")) or 0.0)
                if (now_ts - float(last_attempt)) < 1.0:
                    continue
                row["replay_last_attempt_ts"] = float(now_ts)
                self._indicator_reversal_pending[str(combo)] = dict(row)
                candidates.append((str(combo), str(family), dict(payload)))

        for combo, family, payload in candidates:
            try:
                p = dict(payload)
                p["__guard_replay"] = True
                p["bridge_event_type"] = "signal"
                p["ingest_source"] = "bridge"
                self.ingest_indicator_bridge_signal(
                    terminal_family=str(family),
                    payload=p,
                )
            except Exception as exc:
                logger.warning(
                    "indicator_reversal_pending_replay_failed combo=%s family=%s err=%s",
                    str(combo),
                    str(family),
                    str(exc)[:220],
                )

    def _execute_indicator_sync_mode(
        self,
        *,
        family: str,
        profile: str,
        indicator: str,
        indicator_key: str,
        symbol_exec_raw: str,
        timeframe: str,
        incoming_direction: str,
        lot: float,
        now_ts: float,
        mode_source_tag: str,
        sync_cfg: Dict[str, Any],
        signal_confirm_sec: Optional[float],
        audit_event_ts: Any,
    ) -> Dict[str, Any]:
        direction_tf = self._normalize_tf_token((sync_cfg or {}).get("direction_tf"), "M5")
        entry_tf = self._normalize_tf_token((sync_cfg or {}).get("entry_tf"), "M1")
        exit_tf = self._normalize_tf_token((sync_cfg or {}).get("exit_tf"), "M1")
        reentry_enabled = bool((sync_cfg or {}).get("reentry_enabled", True))
        current_tf = self._normalize_tf_token(timeframe, "M5")
        side = str(incoming_direction or "").strip().upper()
        if side not in {"BUY", "SELL"}:
            return {"ok": False, "executed": False, "reason": "invalid_sync_direction"}

        base_key = self._indicator_sync_base_key(
            family=str(family),
            profile=str(profile),
            indicator_key=str(indicator_key),
            symbol=str(symbol_exec_raw).strip().upper(),
        )
        self._record_indicator_sync_direction(
            base_key=str(base_key),
            timeframe=str(current_tf),
            direction=str(side),
            now_ts=float(now_ts),
            message=f"{indicator}:{symbol_exec_raw}:{current_tf}",
        )
        direction_dir = self._read_indicator_sync_direction(base_key=str(base_key), timeframe=str(direction_tf))

        close_reason = f"sync_exit_tf_{str(current_tf).lower()}_reverse_vs_direction_tf_{str(direction_tf).lower()}"
        reverse_out = self._close_mt4_reverse_positions(
            symbol=str(symbol_exec_raw),
            incoming_direction=str(side),
            timeframe="",
            source_tag=str(mode_source_tag),
            close_reason=str(close_reason),
        )
        if not bool((reverse_out or {}).get("ok")):
            return {
                "ok": False,
                "executed": False,
                "reason": "sync_reverse_close_failed",
                "message": "reverse_close_failed: " + " | ".join(str(x) for x in ((reverse_out or {}).get("errors") or [])[:3]),
            }

        should_open = False
        skip_reason = ""
        if direction_dir not in {"BUY", "SELL"}:
            skip_reason = f"sync_wait_direction_tf:{direction_tf}"
        elif current_tf == entry_tf and side == direction_dir:
            should_open = True
        elif bool(reentry_enabled) and current_tf == exit_tf and side == direction_dir:
            should_open = True
        elif current_tf == exit_tf and side != direction_dir:
            skip_reason = f"sync_exit_only:{exit_tf}:dir_tf={direction_tf}:{direction_dir}"
        else:
            skip_reason = f"sync_ignore_tf:{current_tf}:entry={entry_tf}:exit={exit_tf}"

        if not should_open:
            return {
                "ok": True,
                "executed": False,
                "reason": str(skip_reason or "sync_no_open"),
                "reverse_close": dict(reverse_out or {}),
                "direction_tf": str(direction_tf),
                "entry_tf": str(entry_tf),
                "exit_tf": str(exit_tf),
                "direction_dir": str(direction_dir or ""),
            }

        svc = self._get_live_service()
        if self._has_live_open_for_source_tag_direction(
            source_tag=str(mode_source_tag),
            symbol=str(symbol_exec_raw),
            timeframe="",
            direction=str(side),
            svc=svc,
        ):
            return {
                "ok": True,
                "executed": False,
                "reason": "same_direction_already_open",
                "reverse_close": dict(reverse_out or {}),
            }

        guard = self._check_indicator_reversal_stability(
            combo_source_tag=str(mode_source_tag),
            incoming_direction=str(side),
            now_ts=float(now_ts),
            force_wait=True,
            confirm_sec=signal_confirm_sec,
        )
        if not bool((guard or {}).get("ready")):
            return {
                "ok": True,
                "executed": False,
                "reason": "reversal_guard_waiting",
                "wait": dict(guard or {}),
                "reverse_close": dict(reverse_out or {}),
            }

        exec_msg = self._execute_indicator_normal_signal(
            chat_id=int(self._allowed_chat_id() or 0),
            symbol=str(symbol_exec_raw),
            timeframe=str(current_tf),
            direction=str(side),
            lot=float(lot),
            source_tag=str(mode_source_tag),
            comment_prefix=str(family),
            audit_ctx={
                "source_type": "mt_indicator",
                "source_name": str(indicator),
                "trigger": "sync_signal",
                "profile": str(profile),
                "indicator": str(indicator),
                "event_ts": audit_event_ts,
            },
            execution_mode="sync",
        )
        executed = str(exec_msg or "").strip().lower().startswith("normal mode order executed")
        return {
            "ok": True,
            "executed": bool(executed),
            "reason": ("" if executed else "sync_open_failed"),
            "message": str(exec_msg),
            "reverse_close": dict(reverse_out or {}),
            "direction_tf": str(direction_tf),
            "entry_tf": str(entry_tf),
            "exit_tf": str(exit_tf),
            "direction_dir": str(direction_dir or ""),
            "reentry_enabled": bool(reentry_enabled),
        }

    def ingest_indicator_bridge_signal(
        self,
        *,
        terminal_family: Any,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        family = self._indicator_bridge_family(terminal_family)
        p = payload if isinstance(payload, dict) else {}
        bridge_event_type = str(p.get("bridge_event_type") or p.get("event_type") or "signal").strip().lower() or "signal"
        registered = self.register_indicator_bridge_instance(terminal_family=family, payload=p)

        indicator_raw = str(p.get("indicator") or "").strip()
        indicator = self._normalize_mt4_indicator_name(indicator_raw) or indicator_raw or f"{family.upper()}Indicator"
        indicator_key = self._normalize_mt_indicator_key(indicator)
        profile = str(p.get("signal_profile") or p.get("profile") or "").strip().lower() or "generic"
        ingest_source = str(p.get("ingest_source") or "bridge").strip().lower() or "bridge"
        hint = str(p.get("signal_hint") or p.get("direction") or "").strip().upper()
        symbol_raw = str(p.get("symbol") or "").strip().upper()
        symbol = str(self._CONFIRM_SIGNAL_SYMBOL_ALIASES.get(symbol_raw, symbol_raw))
        timeframe = str(p.get("timeframe") or self._confirm_signal_default_timeframe()).strip().upper() or "M5"
        message = str(p.get("message") or "").strip()
        event_ts = p.get("event_ts")
        event_id = str(p.get("event_id") or "").strip()
        source = f"{family.upper()}:{indicator}"
        combo_prefix = (
            f"{family}|{str(profile)}|{str(indicator_key)}|{str(symbol).strip().upper()}|{str(timeframe).strip().upper()}"
        )
        neutral_hints = {"", "NONE", "NEUTRAL", "FLAT", "OFF", "CLEAR", "0"}

        if bridge_event_type in {"register", "heartbeat", "status", "init"} and hint not in {"BUY", "SELL"}:
            return {
                "ok": True,
                "executed": False,
                "reason": "bridge_registered",
                "runtime": self._resolve_indicator_bridge_instance_runtime_config(
                    family=family,
                    indicator=indicator,
                    symbol=symbol,
                    timeframe=timeframe,
                ),
                "bridge": registered,
            }

        if bridge_event_type in {"rsi_telemetry", "telemetry_rsi", "rsi_metric"}:
            rsi_val = _to_float_or_none(p.get("rsi_value"))
            if rsi_val is None:
                rsi_val = _to_float_or_none(p.get("value"))
            if rsi_val is None or (not math.isfinite(float(rsi_val))):
                return {"ok": False, "executed": False, "error": "invalid_rsi_telemetry"}
            telem = self._record_indicator_rsi_telemetry(
                family=str(family),
                symbol=str(symbol),
                timeframe=str(timeframe),
                indicator=str(indicator),
                profile=str(profile),
                rsi_value=float(rsi_val),
                now_ts=float(time.time()),
                event_ts=event_ts,
                indicator_tf=p.get("indicator_tf"),
                rsi_period=p.get("rsi_period"),
            )
            return {
                "ok": True,
                "executed": False,
                "reason": "rsi_telemetry_recorded",
                "telemetry": telem,
                "bridge": registered,
            }

        if bridge_event_type in {"signal_clear", "clear", "state_clear"} or hint in neutral_hints:
            removed = self._clear_indicator_reversal_pending_for_combo_prefix(combo_prefix=str(combo_prefix))
            removed_dedupe = self._clear_indicator_signal_dedupe_for_combo_prefix(combo_prefix=str(combo_prefix))
            runtime_cfg = self._resolve_indicator_bridge_instance_runtime_config(
                family=family,
                indicator=indicator,
                symbol=symbol,
                timeframe=timeframe,
            )
            fallback_result: Optional[Dict[str, Any]] = None
            fallback_reason = ""
            fallback_dir = ""
            fallback_age_sec: Optional[float] = None
            now_clear_ts = float(time.time())
            if self._indicator_clear_fallback_enabled():
                fallback_dir, fallback_age = self._read_indicator_last_valid_direction(
                    combo_prefix=str(combo_prefix),
                    now_ts=float(now_clear_ts),
                )
                fallback_age_sec = float(fallback_age)
                if fallback_dir in {"BUY", "SELL"} and self._check_indicator_clear_fallback_cooldown(
                    combo_prefix=str(combo_prefix),
                    now_ts=float(now_clear_ts),
                ):
                    self._mark_indicator_clear_fallback(
                        combo_prefix=str(combo_prefix),
                        now_ts=float(now_clear_ts),
                    )
                    fallback_reason = "fallback_to_latest_valid_after_clear"
                    fallback_payload = {
                        "indicator": str(indicator),
                        "signal_profile": str(profile),
                        "signal_hint": str(fallback_dir),
                        "symbol": str(symbol),
                        "timeframe": str(timeframe),
                        "message": str(fallback_reason),
                        "event_ts": datetime.now(timezone.utc).isoformat(),
                        "ingest_source": "bridge",
                        "bridge_event_type": "signal",
                    }
                    try:
                        fb = self.ingest_indicator_bridge_signal(
                            terminal_family=str(family),
                            payload=dict(fallback_payload),
                        )
                        fallback_result = dict(fb or {})
                    except Exception as exc:
                        fallback_result = {
                            "ok": False,
                            "executed": False,
                            "error": f"fallback_exception:{type(exc).__name__}:{str(exc)[:180]}",
                        }
                elif fallback_dir in {"BUY", "SELL"}:
                    fallback_reason = "fallback_skipped_cooldown"
                else:
                    fallback_reason = "fallback_unavailable_no_last_valid"
            if str(fallback_reason or "").strip():
                self._append_automation_execution_log(
                    source_type="mt_indicator",
                    source_name=str(indicator),
                    trigger="signal_clear_fallback",
                    status=("executed" if bool((fallback_result or {}).get("executed")) else "skipped"),
                    symbol=str(symbol),
                    timeframe=str(timeframe),
                    direction=(str(fallback_dir) if fallback_dir in {"BUY", "SELL"} else None),
                    profile=str(profile),
                    indicator=str(indicator),
                    source_tag=str(combo_prefix),
                    message=str(fallback_reason),
                    stage="fallback",
                    stage_status=("executed" if bool((fallback_result or {}).get("executed")) else "skipped"),
                    stage_payload={
                        "fallback_direction": (str(fallback_dir) if fallback_dir in {"BUY", "SELL"} else ""),
                        "fallback_age_sec": (_to_float_or_none(fallback_age_sec)),
                        "fallback_result": (dict(fallback_result) if isinstance(fallback_result, dict) else None),
                    },
                    error_code=(None if bool((fallback_result or {}).get("executed")) else str(fallback_reason)),
                )
            return {
                "ok": True,
                "executed": False,
                "reason": "signal_cleared",
                "cleared_pending_count": int(removed),
                "cleared_dedupe_count": int(removed_dedupe),
                "fallback_reason": str(fallback_reason),
                "fallback_direction": (str(fallback_dir) if fallback_dir in {"BUY", "SELL"} else ""),
                "fallback_age_sec": (_to_float_or_none(fallback_age_sec)),
                "fallback_result": (dict(fallback_result) if isinstance(fallback_result, dict) else None),
                "runtime": runtime_cfg,
                "bridge": registered,
            }

        if hint not in {"BUY", "SELL"}:
            return {"ok": False, "error": "invalid_direction", "executed": False}
        if not symbol:
            return {"ok": False, "error": "missing_symbol", "executed": False}

        now_ts = time.time()
        if event_id:
            if not self._check_and_mark_indicator_event_id(
                family=str(family),
                indicator_key=str(indicator_key),
                symbol=str(symbol),
                timeframe=str(timeframe),
                event_id=str(event_id),
                now_ts=float(now_ts),
            ):
                return {
                    "ok": True,
                    "executed": False,
                    "reason": "duplicate_event_id",
                    "event_id": str(event_id),
                    "bridge": registered,
                }
        combo_key = f"{family}|{indicator_key}|{symbol}|{timeframe}"
        lock_sec = float(self._mt4_bridge_source_lock_sec())
        with self._lock:
            if ingest_source == "bridge" and combo_key:
                self._mt4_bridge_combo_registry[str(combo_key)] = float(now_ts)
            elif combo_key:
                bridge_seen_ts = float(self._mt4_bridge_combo_registry.get(str(combo_key)) or 0.0)
                if bridge_seen_ts > 0.0 and (float(now_ts) - float(bridge_seen_ts)) <= float(lock_sec):
                    return {"ok": True, "executed": False, "reason": "bridge_source_locked"}
            if len(self._mt4_bridge_combo_registry) > 5000:
                cutoff = float(now_ts) - float(lock_sec)
                self._mt4_bridge_combo_registry = {
                    str(k): float(v) for k, v in self._mt4_bridge_combo_registry.items() if float(v) >= float(cutoff)
                }

        ev_unix = _to_unix_or_none(event_ts)
        max_age = float(self._mt4_exec_max_signal_age_sec())
        if max_age > 0.0 and ev_unix is not None and (float(now_ts) - float(ev_unix)) > float(max_age):
            return {"ok": True, "executed": False, "reason": "stale_signal"}

        if not self._mt4_exec_enabled():
            return {"ok": True, "executed": False, "reason": "indicator_execution_disabled"}

        if not self._mt4_exec_profile_enabled(profile):
            return {"ok": True, "executed": False, "reason": f"profile_disabled:{profile}"}

        runtime_cfg = self._resolve_indicator_bridge_instance_runtime_config(
            family=family,
            indicator=indicator,
            symbol=symbol,
            timeframe=timeframe,
        )
        if not bool(runtime_cfg.get("effective_automation_enabled")):
            return {"ok": True, "executed": False, "reason": "instance_disabled", "runtime": runtime_cfg}

        svc = self._get_live_service()
        info = svc.get_symbol_info(symbol=str(symbol))
        if isinstance(info, dict) and str(info.get("error") or "").strip():
            return {"ok": False, "executed": False, "error": str(info.get("error"))[:220]}
        symbol_exec_raw = str((info or {}).get("resolved_symbol") or symbol).strip() or str(symbol)
        symbol_exec = str(symbol_exec_raw).strip().upper()
        digits = int((info or {}).get("digits") or 2)
        point = _to_float_or_none((info or {}).get("point")) or (0.01 if digits <= 2 else 0.0001)
        min_stops_points = _to_float_or_none((info or {}).get("trade_stops_level")) or 0.0
        min_stop_dist = float(max(0.0, float(min_stops_points) * float(point)))

        tick = svc.get_symbol_tick(symbol=str(symbol_exec_raw), resolve_symbol=False)
        ask = _to_float_or_none((tick or {}).get("ask"))
        bid = _to_float_or_none((tick or {}).get("bid"))
        last = _to_float_or_none((tick or {}).get("last"))

        bars = svc.get_recent_candles(
            symbol=str(symbol_exec_raw),
            timeframe=str(timeframe),
            count=max(40, self._mt4_exec_profile_atr_period(profile) + 10),
            resolve_symbol=False,
        )
        atr_period = int(self._mt4_exec_profile_atr_period(profile))
        atr = self._calc_robust_atr_from_bars(bars, period=int(atr_period))

        entry_price = ask if hint == "BUY" else bid
        if entry_price is None:
            entry_price = last
        if entry_price is None and isinstance(bars, list) and bars:
            entry_price = _to_float_or_none((bars[-1] or {}).get("close"))
        if entry_price is None or (not math.isfinite(float(entry_price))) or float(entry_price) <= 0.0:
            return {"ok": False, "executed": False, "error": "entry_price_unavailable"}

        sync_base_key = self._indicator_sync_base_key(
            family=str(family),
            profile=str(profile),
            indicator_key=str(indicator_key),
            symbol=str(symbol_exec).strip().upper(),
        )
        self._record_indicator_sync_direction(
            base_key=str(sync_base_key),
            timeframe=str(timeframe),
            direction=str(hint),
            now_ts=float(now_ts),
            message=str(message),
        )

        default_dist = max(float(point) * 120.0, abs(float(entry_price)) * 0.001)
        sl_distance = float(atr or default_dist) * float(self._mt4_exec_profile_sl_atr(profile))
        sl_distance = max(float(sl_distance), float(min_stop_dist) * 1.80, float(point) * 25.0)
        tp_base_distance = float(atr or default_dist) * float(self._mt4_exec_profile_tp_atr(profile))
        tp_base_distance = max(float(tp_base_distance), float(min_stop_dist) * 2.20, float(point) * 40.0)
        tp_r_start = float(self._mt4_exec_profile_tp_r_start(profile))
        tp_r_step = float(self._mt4_exec_profile_tp_r_step(profile))
        base_tp_multipliers = [float(x) for x in self._mt4_exec_profile_tp_levels(profile)]
        if not base_tp_multipliers:
            base_tp_multipliers = [float(tp_r_start + tp_r_step * i) for i in range(5)]
        base_stage_weights = [float(x) for x in self._mt4_exec_profile_stage_weights(profile)]
        regime_mode = str(self._mt4_exec_profile_regime_mode(profile))
        regime_info = self._estimate_mt4_market_regime(
            bars=bars,
            atr_value=atr,
            efficiency_lookback=max(8, min(80, int(atr_period))),
            er_threshold=float(self._mt4_exec_profile_regime_er_threshold(profile)),
            donchian_atr_threshold=float(self._mt4_exec_profile_regime_donchian_atr_threshold(profile)),
        )
        inferred_regime = str((regime_info or {}).get("regime") or "unknown").strip().lower() or "unknown"
        active_regime = str(regime_mode)
        if active_regime not in {"trend", "range"}:
            active_regime = "trend" if inferred_regime == "trend" else "range"
        if active_regime == "trend":
            tp_multipliers = [float(x) for x in self._mt4_exec_profile_tp_levels_trend(profile)]
            stage_weights = [float(x) for x in self._mt4_exec_profile_stage_weights_trend(profile)]
        elif active_regime == "range":
            tp_multipliers = [float(x) for x in self._mt4_exec_profile_tp_levels_range(profile)]
            stage_weights = [float(x) for x in self._mt4_exec_profile_stage_weights_range(profile)]
        else:
            tp_multipliers = list(base_tp_multipliers)
            stage_weights = list(base_stage_weights)
        if not tp_multipliers:
            tp_multipliers = list(base_tp_multipliers)
        if not stage_weights:
            stage_weights = list(base_stage_weights)
        if not tp_multipliers:
            tp_multipliers = [float(tp_r_start + tp_r_step * i) for i in range(5)]

        if hint == "BUY":
            tp_prices = [float(entry_price + tp_base_distance * float(rm)) for rm in tp_multipliers]
        else:
            tp_prices = [float(entry_price - tp_base_distance * float(rm)) for rm in tp_multipliers]

        hard_sl_mode = str(self._mt4_exec_profile_hard_sl_mode(profile))
        stop_loss: Optional[float] = None
        no_stop_loss = True
        if hard_sl_mode in {"atr", "catastrophic"}:
            sl_order_distance = float(sl_distance)
            if hard_sl_mode == "catastrophic":
                sl_order_distance = float(atr or default_dist) * float(self._mt4_exec_profile_catastrophic_sl_atr(profile))
                sl_order_distance = max(float(sl_order_distance), float(min_stop_dist) * 3.0, float(point) * 120.0)
            if hint == "BUY":
                stop_loss = float(entry_price - sl_order_distance)
                stop_loss = min(float(stop_loss), float(entry_price - max(min_stop_dist * 1.10, point * 2.0)))
            else:
                stop_loss = float(entry_price + sl_order_distance)
                stop_loss = max(float(stop_loss), float(entry_price + max(min_stop_dist * 1.10, point * 2.0)))
            stop_loss = round(float(stop_loss), int(max(0, digits)))
            no_stop_loss = False

        tps = [{"index": int(i + 1), "price": round(float(px), int(max(0, digits)))} for i, px in enumerate(tp_prices)]
        signal = {
            "symbol": str(symbol_exec_raw),
            "direction": str(hint),
            "entry_low": round(float(entry_price), int(max(0, digits))),
            "entry_high": round(float(entry_price), int(max(0, digits))),
            "entry_mid": round(float(entry_price), int(max(0, digits))),
            "digits": int(digits),
            "point": float(point),
            "min_stop_dist": float(min_stop_dist),
            "atr": _to_float_or_none(atr),
            "stop_loss": (_to_float_or_none(stop_loss) if stop_loss is not None else None),
            "no_stop_loss": bool(no_stop_loss),
            "tps": list(tps),
            "raw_text": str(message),
            "timeframe": str(timeframe),
            "virtual_sl_distance": float(sl_distance),
            "stage_weights": list(stage_weights),
            "market_regime": str(active_regime),
            "hard_sl_mode": str(hard_sl_mode),
            # Advanced lock policy:
            # - Trend: default lock disabled (let winners run)
            # - Range: lock enabled with stricter arming and minimum close profit floor.
            "profit_lock_enabled": (False if str(active_regime) == "trend" else True),
            "profit_lock_retrace_pct": (0.82 if str(active_regime) == "trend" else 0.55),
            "profit_lock_arm_after_tp": (5 if str(active_regime) == "trend" else 3),
            "profit_lock_min_peak_usd": (90.0 if str(active_regime) == "trend" else 25.0),
            "profit_lock_min_hold_sec": (480.0 if str(active_regime) == "trend" else 150.0),
            "profit_lock_min_close_usd": (25.0 if str(active_regime) == "trend" else 8.0),
        }
        latest_rsi = self._latest_indicator_rsi_telemetry(
            family=str(family),
            symbol=str(symbol_exec),
            timeframe=str(timeframe),
            max_age_sec=300.0,
        )
        if isinstance(latest_rsi, dict) and _to_float_or_none(latest_rsi.get("rsi_value")) is not None:
            signal["rsi_value"] = float(_to_float_or_none(latest_rsi.get("rsi_value")) or 0.0)
            signal["rsi_indicator"] = str(latest_rsi.get("indicator") or "")
            signal["rsi_indicator_tf"] = str(latest_rsi.get("indicator_tf") or "")
            signal["rsi_period"] = _to_float_or_none(latest_rsi.get("rsi_period"))
            signal["rsi_seen_ts"] = _to_float_or_none(latest_rsi.get("seen_ts"))
        combo_source_tag = (
            f"{family}|{str(profile)}|{str(indicator_key)}|{str(symbol_exec).strip().upper()}|{str(timeframe).strip().upper()}"
        )

        is_guard_replay = str(p.get("__guard_replay") or "").strip().lower() in {"1", "true", "yes", "on"}
        if not bool(is_guard_replay):
            msg_norm = re.sub(r"\s+", " ", str(message or "").strip().lower())
            dedupe_key = (
                f"{family}|{profile}|{indicator_key}|{str(symbol_exec).strip().upper()}|"
                f"{str(timeframe).strip().upper()}|{hint}|{msg_norm}"
            )
            with self._lock:
                prev = float(self._mt4_signal_dedupe.get(dedupe_key) or 0.0)
                if prev > 0.0 and (float(now_ts) - float(prev)) <= float(self._mt4_exec_dedupe_window_sec()):
                    return {"ok": True, "executed": False, "reason": "duplicate_signal", "runtime": runtime_cfg, "bridge": registered}
                self._mt4_signal_dedupe[dedupe_key] = float(now_ts)
                if len(self._mt4_signal_dedupe) > 10000:
                    cutoff = float(now_ts) - float(max(self._mt4_exec_dedupe_window_sec(), 600.0))
                    self._mt4_signal_dedupe = {
                        str(k): float(v) for k, v in self._mt4_signal_dedupe.items() if float(v) >= float(cutoff)
                    }

        lot = float(_to_float_or_none(runtime_cfg.get("lot_size")) or self._mt4_exec_profile_lot(profile))
        lot_override = _to_float_or_none(p.get("lot_override"))
        if lot_override is not None and float(lot_override) > 0.0:
            lot = float(max(0.01, min(100.0, float(lot_override))))
        mode_lots_cfg = dict(runtime_cfg.get("mode_lots") or {})
        chat_id = int(self._allowed_chat_id() or 0)
        mode_cfg = dict(runtime_cfg.get("execution_modes") or {})
        sync_cfg = dict(runtime_cfg.get("sync") or {})
        mode_plan = [
            ("advanced", bool(mode_cfg.get("advanced", True))),
            ("advanced_v2", bool(mode_cfg.get("advanced_v2", False))),
            ("normal", bool(mode_cfg.get("normal", False))),
            ("sync", bool(mode_cfg.get("sync", False))),
        ]
        selected_modes = [m for m, en in mode_plan if bool(en)]
        if not selected_modes:
            return {
                "ok": True,
                "executed": False,
                "reason": "no_execution_mode_enabled",
                "runtime": runtime_cfg,
                "bridge": registered,
            }

        mode_results: List[Dict[str, Any]] = []
        executed_any = False
        market_closed_only = True
        any_waiting = False
        waiting_detail: Optional[Dict[str, Any]] = None
        first_message = ""
        for mode in selected_modes:
            mode_lot = float(_to_float_or_none(mode_lots_cfg.get(str(mode))) or lot)
            if str(mode) == "sync":
                mode_source_tag = self._build_sync_mode_source_tag(
                    family=str(family),
                    profile=str(profile),
                    indicator_key=str(indicator_key),
                    symbol=str(symbol_exec).strip().upper(),
                    direction_tf=(sync_cfg or {}).get("direction_tf"),
                    entry_tf=(sync_cfg or {}).get("entry_tf"),
                    exit_tf=(sync_cfg or {}).get("exit_tf"),
                )
                mode_exec_lock = self._indicator_mode_exec_lock(str(mode_source_tag))
                with mode_exec_lock:
                    sync_out = self._execute_indicator_sync_mode(
                        family=str(family),
                        profile=str(profile),
                        indicator=str(indicator),
                        indicator_key=str(indicator_key),
                        symbol_exec_raw=str(symbol_exec_raw),
                        timeframe=str(timeframe),
                        incoming_direction=str(hint),
                        lot=float(mode_lot),
                        now_ts=float(now_ts),
                        mode_source_tag=str(mode_source_tag),
                        sync_cfg=dict(sync_cfg),
                        signal_confirm_sec=_to_float_or_none(runtime_cfg.get("signal_confirm_sec")),
                        audit_event_ts=event_ts,
                    )
                executed = bool((sync_out or {}).get("executed"))
                executed_any = bool(executed_any or executed)
                mode_results.append(
                    {
                        "mode": "sync",
                        "ok": bool((sync_out or {}).get("ok", True)),
                        "executed": bool(executed),
                        "reason": str((sync_out or {}).get("reason") or ""),
                        "message": str((sync_out or {}).get("message") or ""),
                        "sync": {
                            "direction_tf": str((sync_out or {}).get("direction_tf") or sync_cfg.get("direction_tf") or ""),
                            "entry_tf": str((sync_out or {}).get("entry_tf") or sync_cfg.get("entry_tf") or ""),
                            "exit_tf": str((sync_out or {}).get("exit_tf") or sync_cfg.get("exit_tf") or ""),
                            "direction_dir": str((sync_out or {}).get("direction_dir") or ""),
                            "reentry_enabled": bool((sync_out or {}).get("reentry_enabled", sync_cfg.get("reentry_enabled", True))),
                        },
                    }
                )
                if not first_message:
                    first_message = str((sync_out or {}).get("message") or "")
                if str((sync_out or {}).get("reason") or "") not in {"market_closed"}:
                    market_closed_only = False
                if str((sync_out or {}).get("reason") or "") == "reversal_guard_waiting":
                    any_waiting = True
                    if waiting_detail is None:
                        waiting_detail = dict((sync_out or {}).get("wait") or {})
                    self._queue_indicator_reversal_replay(
                        combo_source_tag=str(mode_source_tag),
                        terminal_family=str(family),
                        payload={
                            "indicator": str(indicator),
                            "signal_profile": str(profile),
                            "signal_hint": str(hint),
                            "symbol": str(symbol_exec).strip().upper(),
                            "timeframe": str(timeframe).strip().upper(),
                            "message": str(message),
                            "event_ts": event_ts,
                            "bridge_event_type": "signal",
                            "ingest_source": "bridge",
                        },
                        now_ts=float(now_ts),
                    )
                continue

            mode_source_tag = f"{str(combo_source_tag)}|{str(mode)}"
            mode_exec_lock = self._indicator_mode_exec_lock(str(mode_source_tag))
            with mode_exec_lock:
                reverse_out = self._close_mt4_reverse_positions(
                    symbol=str(symbol_exec_raw),
                    incoming_direction=str(hint),
                    timeframe=str(timeframe),
                    source_tag=str(mode_source_tag),
                )
                if not bool((reverse_out or {}).get("ok")):
                    reverse_msg = "reverse_close_failed: " + " | ".join(str(x) for x in ((reverse_out or {}).get("errors") or [])[:3])
                    mode_results.append(
                        {
                            "mode": str(mode),
                            "ok": False,
                            "executed": False,
                            "reason": "reverse_close_failed",
                            "message": str(reverse_msg)[:220],
                        }
                    )
                    market_closed_only = False
                    continue
                if int((reverse_out or {}).get("closed_count") or 0) > 0:
                    self._clear_indicator_recent_open(source_tag=str(mode_source_tag))

                if self._has_live_open_for_source_tag_direction(
                    source_tag=str(mode_source_tag),
                    symbol=str(symbol_exec_raw),
                    timeframe=str(timeframe),
                    direction=str(hint),
                    svc=svc,
                ):
                    mode_results.append(
                        {
                            "mode": str(mode),
                            "ok": True,
                            "executed": False,
                            "reason": "same_direction_already_open",
                            "message": "skip_open_same_direction_live_exists",
                        }
                    )
                    market_closed_only = False
                    continue
                if self._has_indicator_recent_open(
                    source_tag=str(mode_source_tag),
                    direction=str(hint),
                    now_ts=float(now_ts),
                ):
                    mode_results.append(
                        {
                            "mode": str(mode),
                            "ok": True,
                            "executed": False,
                            "reason": "recent_open_debounce",
                            "message": "skip_open_recent_open_debounce",
                        }
                    )
                    market_closed_only = False
                    continue

                mode_guard = self._check_indicator_reversal_stability(
                    combo_source_tag=str(mode_source_tag),
                    incoming_direction=str(hint),
                    now_ts=float(now_ts),
                    force_wait=True,
                    confirm_sec=_to_float_or_none(runtime_cfg.get("signal_confirm_sec")),
                )
                if not bool((mode_guard or {}).get("ready")):
                    any_waiting = True
                    if waiting_detail is None:
                        waiting_detail = dict(mode_guard or {})
                    mode_results.append(
                        {
                            "mode": str(mode),
                            "ok": True,
                            "executed": False,
                            "reason": "reversal_guard_waiting",
                            "message": "reversal_guard_waiting_after_close",
                            "wait": dict(mode_guard or {}),
                        }
                    )
                    self._queue_indicator_reversal_replay(
                        combo_source_tag=str(mode_source_tag),
                        terminal_family=str(family),
                        payload={
                            "indicator": str(indicator),
                            "signal_profile": str(profile),
                            "signal_hint": str(hint),
                            "symbol": str(symbol_exec).strip().upper(),
                            "timeframe": str(timeframe).strip().upper(),
                            "message": str(message),
                            "event_ts": event_ts,
                            "bridge_event_type": "signal",
                            "ingest_source": "bridge",
                        },
                        now_ts=float(now_ts),
                    )
                    continue

                if str(mode) == "normal":
                    exec_msg = self._execute_indicator_normal_signal(
                        chat_id=int(chat_id),
                        symbol=str(symbol_exec_raw),
                        timeframe=str(timeframe),
                        direction=str(hint),
                        lot=float(mode_lot),
                        source_tag=str(mode_source_tag),
                        comment_prefix=str(family),
                        audit_ctx={
                            "source_type": "mt_indicator",
                            "source_name": str(indicator),
                            "trigger": "indicator_signal",
                            "profile": str(profile),
                            "indicator": str(indicator),
                            "event_ts": event_ts,
                        },
                    )
                    executed = str(exec_msg or "").strip().lower().startswith("normal mode order executed")
                    deferred_market_closed = str(exec_msg or "").strip().lower().startswith("normal mode deferred: market closed")
                else:
                    exec_msg = self._execute_confirmation_signal_auto(
                        chat_id=int(chat_id),
                        signal=dict(signal),
                        lot_override=float(mode_lot),
                        source_tag=str(mode_source_tag),
                        comment_prefix=str(family),
                        audit_ctx={
                            "source_type": "mt_indicator",
                            "source_name": str(indicator),
                            "trigger": "indicator_signal",
                            "profile": str(profile),
                            "indicator": str(indicator),
                            "event_ts": event_ts,
                        },
                        execution_mode=("advanced_v2" if str(mode) == "advanced_v2" else "advanced"),
                    )
                    executed = str(exec_msg or "").strip().lower().startswith("confirmation ladder executed")
                    deferred_market_closed = str(exec_msg or "").strip().lower().startswith("confirmation deferred: market closed")

            executed_any = bool(executed_any or executed)
            if not deferred_market_closed:
                market_closed_only = False
            mode_results.append(
                {
                    "mode": str(mode),
                    "ok": True,
                    "executed": bool(executed),
                    "reason": ("market_closed" if deferred_market_closed else ""),
                    "message": str(exec_msg),
                }
            )
            if not first_message:
                first_message = str(exec_msg or "")

        has_stable_direction_signal = bool(executed_any)
        if not has_stable_direction_signal:
            for row in (mode_results or []):
                reason_row = str((row or {}).get("reason") or "").strip().lower()
                if reason_row in {"same_direction_already_open", "recent_open_debounce"}:
                    has_stable_direction_signal = True
                    break
        if has_stable_direction_signal:
            self._record_indicator_last_valid_direction(
                combo_prefix=str(combo_prefix),
                direction=str(hint),
                now_ts=float(now_ts),
                indicator=str(indicator),
                profile=str(profile),
                symbol=str(symbol_exec),
                timeframe=str(timeframe),
            )

        if (not executed_any) and bool(any_waiting):
            return {
                "ok": True,
                "executed": False,
                "reason": "reversal_guard_waiting",
                "wait": dict(waiting_detail or {}),
                "runtime": runtime_cfg,
                "bridge": registered,
                "mode_results": mode_results,
            }

        return {
            "ok": True,
            "executed": bool(executed_any),
            "message": str(first_message),
            "reason": ("market_closed" if (market_closed_only and not executed_any) else ""),
            "runtime": runtime_cfg,
            "bridge": registered,
            "mode_results": mode_results,
        }

    def ingest_mt4_indicator_signal(self, *, payload: Dict[str, Any]) -> Dict[str, Any]:
        p = payload if isinstance(payload, dict) else {}
        indicator_raw = str(p.get("indicator") or "").strip()
        indicator = self._normalize_mt4_indicator_name(indicator_raw) or indicator_raw or "MT4Indicator"
        indicator_key = self._normalize_mt_indicator_key(indicator)
        profile = str(p.get("signal_profile") or "").strip().lower() or "generic"
        ingest_source = str(p.get("ingest_source") or "unknown").strip().lower() or "unknown"
        hint = str(p.get("signal_hint") or "").strip().upper()
        symbol_raw = str(p.get("symbol") or "").strip().upper()
        symbol = str(self._CONFIRM_SIGNAL_SYMBOL_ALIASES.get(symbol_raw, symbol_raw))
        timeframe = str(p.get("timeframe") or self._confirm_signal_default_timeframe()).strip().upper() or "M5"
        message = str(p.get("message") or "").strip()
        event_ts = p.get("event_ts")
        source = f"MT4:{indicator}"

        if hint not in {"BUY", "SELL"}:
            return {"ok": False, "error": "invalid_direction", "executed": False}
        if not symbol:
            return {"ok": False, "error": "missing_symbol", "executed": False}

        now_ts = time.time()
        combo_key = f"{indicator_key}|{symbol}|{timeframe}"
        lock_sec = float(self._mt4_bridge_source_lock_sec())
        with self._lock:
            if ingest_source == "bridge" and combo_key:
                self._mt4_bridge_combo_registry[str(combo_key)] = float(now_ts)
            elif combo_key:
                bridge_seen_ts = float(self._mt4_bridge_combo_registry.get(str(combo_key)) or 0.0)
                if bridge_seen_ts > 0.0 and (float(now_ts) - float(bridge_seen_ts)) <= float(lock_sec):
                    return {"ok": True, "executed": False, "reason": "bridge_source_locked"}
            if len(self._mt4_bridge_combo_registry) > 5000:
                cutoff = float(now_ts) - float(lock_sec)
                self._mt4_bridge_combo_registry = {
                    str(k): float(v) for k, v in self._mt4_bridge_combo_registry.items() if float(v) >= float(cutoff)
                }
        if ingest_source == "log" and (not self._legacy_mt4_log_ingest_enabled()):
            return {"ok": True, "executed": False, "reason": "legacy_mt4_log_ingest_disabled"}

        ev_unix = _to_unix_or_none(event_ts)
        max_age = float(self._mt4_exec_max_signal_age_sec())
        if max_age > 0.0 and ev_unix is not None and (float(now_ts) - float(ev_unix)) > float(max_age):
            return {"ok": True, "executed": False, "reason": "stale_signal"}

        # Apply deterministic dedupe even when execution is disabled/profile-gated,
        # so repeated identical payloads don't flood monitoring/logging surfaces.
        msg_norm = re.sub(r"\s+", " ", str(message or "").strip().lower())
        dedupe_key = (
            f"{profile}|{indicator_key}|{str(symbol).strip().upper()}|"
            f"{str(timeframe).strip().upper()}|{hint}|{msg_norm}"
        )
        with self._lock:
            prev = float(self._mt4_signal_dedupe.get(dedupe_key) or 0.0)
            if prev > 0.0 and (float(now_ts) - float(prev)) <= float(self._mt4_exec_dedupe_window_sec()):
                return {"ok": True, "executed": False, "reason": "duplicate_signal"}
            self._mt4_signal_dedupe[dedupe_key] = float(now_ts)
            if len(self._mt4_signal_dedupe) > 10000:
                cutoff = float(now_ts) - float(max(self._mt4_exec_dedupe_window_sec(), 600.0))
                self._mt4_signal_dedupe = {
                    str(k): float(v) for k, v in self._mt4_signal_dedupe.items() if float(v) >= float(cutoff)
                }

        if not self._mt4_exec_enabled():
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_signal",
                parsed={"symbol": str(symbol), "direction": str(hint), "profile": str(profile)},
                event_ts=event_ts,
                source_message_id=None,
            )
            return {"ok": True, "executed": False, "reason": "mt4_execution_disabled"}

        if not self._mt4_exec_profile_enabled(profile):
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_signal",
                parsed={"symbol": str(symbol), "direction": str(hint), "profile": str(profile)},
                event_ts=event_ts,
                source_message_id=None,
            )
            return {"ok": True, "executed": False, "reason": f"profile_disabled:{profile}"}

        runtime_cfg = self._resolve_mt4_instance_runtime_config(
            indicator=str(indicator),
            symbol=str(symbol),
            timeframe=str(timeframe),
        )
        if not bool(runtime_cfg.get("indicator_allowed")):
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_signal_rejected",
                parsed={"symbol": str(symbol), "direction": str(hint), "profile": str(profile), "reason": "indicator_not_allowed"},
                event_ts=event_ts,
                source_message_id=None,
            )
            return {"ok": True, "executed": False, "reason": "indicator_not_allowed"}
        if not bool(runtime_cfg.get("effective_automation_enabled")):
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_signal_disabled",
                parsed={
                    "symbol": str(symbol),
                    "direction": str(hint),
                    "profile": str(profile),
                    "instance_key": str(runtime_cfg.get("instance_key") or ""),
                    "reason": "instance_disabled",
                },
                event_ts=event_ts,
                source_message_id=None,
            )
            return {"ok": True, "executed": False, "reason": "instance_disabled"}

        svc = self._get_live_service()
        info = svc.get_symbol_info(symbol=str(symbol))
        if isinstance(info, dict) and str(info.get("error") or "").strip():
            return {"ok": False, "executed": False, "error": str(info.get("error"))[:220]}
        symbol_exec_raw = str((info or {}).get("resolved_symbol") or symbol).strip() or str(symbol)
        symbol_exec = str(symbol_exec_raw).strip().upper()
        digits = int((info or {}).get("digits") or 2)
        point = _to_float_or_none((info or {}).get("point")) or (0.01 if digits <= 2 else 0.0001)
        min_stops_points = _to_float_or_none((info or {}).get("trade_stops_level")) or 0.0
        min_stop_dist = float(max(0.0, float(min_stops_points) * float(point)))

        tick = svc.get_symbol_tick(symbol=str(symbol_exec_raw), resolve_symbol=False)
        ask = _to_float_or_none((tick or {}).get("ask"))
        bid = _to_float_or_none((tick or {}).get("bid"))
        last = _to_float_or_none((tick or {}).get("last"))

        bars = svc.get_recent_candles(
            symbol=str(symbol_exec_raw),
            timeframe=str(timeframe),
            count=max(40, self._mt4_exec_profile_atr_period(profile) + 10),
            resolve_symbol=False,
        )
        atr_period = int(self._mt4_exec_profile_atr_period(profile))
        atr = self._calc_robust_atr_from_bars(bars, period=int(atr_period))

        entry_price = ask if hint == "BUY" else bid
        if entry_price is None:
            entry_price = last
        if entry_price is None and isinstance(bars, list) and bars:
            entry_price = _to_float_or_none((bars[-1] or {}).get("close"))
        if entry_price is None or (not math.isfinite(float(entry_price))) or float(entry_price) <= 0.0:
            return {"ok": False, "executed": False, "error": "entry_price_unavailable"}

        default_dist = max(float(point) * 120.0, abs(float(entry_price)) * 0.001)
        sl_distance = float(atr or default_dist) * float(self._mt4_exec_profile_sl_atr(profile))
        # Keep reference SL distance loose (used as volatility/risk reference only).
        sl_distance = max(float(sl_distance), float(min_stop_dist) * 1.80, float(point) * 25.0)
        tp_base_distance = float(atr or default_dist) * float(self._mt4_exec_profile_tp_atr(profile))
        # Keep TP distance away from micro-noise and broker min-stop constraints.
        tp_base_distance = max(float(tp_base_distance), float(min_stop_dist) * 2.20, float(point) * 40.0)
        tp_r_start = float(self._mt4_exec_profile_tp_r_start(profile))
        tp_r_step = float(self._mt4_exec_profile_tp_r_step(profile))
        base_tp_multipliers = [float(x) for x in self._mt4_exec_profile_tp_levels(profile)]
        if not base_tp_multipliers:
            base_tp_multipliers = [float(tp_r_start + tp_r_step * i) for i in range(5)]
        base_stage_weights = [float(x) for x in self._mt4_exec_profile_stage_weights(profile)]
        regime_mode = str(self._mt4_exec_profile_regime_mode(profile))
        regime_info = self._estimate_mt4_market_regime(
            bars=bars,
            atr_value=atr,
            efficiency_lookback=max(8, min(80, int(atr_period))),
            er_threshold=float(self._mt4_exec_profile_regime_er_threshold(profile)),
            donchian_atr_threshold=float(self._mt4_exec_profile_regime_donchian_atr_threshold(profile)),
        )
        inferred_regime = str((regime_info or {}).get("regime") or "unknown").strip().lower() or "unknown"
        active_regime = str(regime_mode)
        if active_regime not in {"trend", "range"}:
            active_regime = "trend" if inferred_regime == "trend" else "range"
        if active_regime == "trend":
            tp_multipliers = [float(x) for x in self._mt4_exec_profile_tp_levels_trend(profile)]
            stage_weights = [float(x) for x in self._mt4_exec_profile_stage_weights_trend(profile)]
        elif active_regime == "range":
            tp_multipliers = [float(x) for x in self._mt4_exec_profile_tp_levels_range(profile)]
            stage_weights = [float(x) for x in self._mt4_exec_profile_stage_weights_range(profile)]
        else:
            tp_multipliers = list(base_tp_multipliers)
            stage_weights = list(base_stage_weights)
        if not tp_multipliers:
            tp_multipliers = list(base_tp_multipliers)
        if not stage_weights:
            stage_weights = list(base_stage_weights)
        if not tp_multipliers:
            tp_multipliers = [float(tp_r_start + tp_r_step * i) for i in range(5)]

        if hint == "BUY":
            tp_prices = [float(entry_price + tp_base_distance * float(rm)) for rm in tp_multipliers]
        else:
            tp_prices = [float(entry_price - tp_base_distance * float(rm)) for rm in tp_multipliers]

        hard_sl_mode = str(self._mt4_exec_profile_hard_sl_mode(profile))
        stop_loss: Optional[float] = None
        no_stop_loss = True
        if hard_sl_mode in {"atr", "catastrophic"}:
            sl_order_distance = float(sl_distance)
            if hard_sl_mode == "catastrophic":
                sl_order_distance = float(atr or default_dist) * float(self._mt4_exec_profile_catastrophic_sl_atr(profile))
                sl_order_distance = max(float(sl_order_distance), float(min_stop_dist) * 3.0, float(point) * 120.0)
            if hint == "BUY":
                stop_loss = float(entry_price - sl_order_distance)
                stop_loss = min(float(stop_loss), float(entry_price - max(min_stop_dist * 1.10, point * 2.0)))
            else:
                stop_loss = float(entry_price + sl_order_distance)
                stop_loss = max(float(stop_loss), float(entry_price + max(min_stop_dist * 1.10, point * 2.0)))
            stop_loss = round(float(stop_loss), int(max(0, digits)))
            no_stop_loss = False

        tps = [{"index": int(i + 1), "price": round(float(px), int(max(0, digits)))} for i, px in enumerate(tp_prices)]
        signal = {
            "symbol": str(symbol_exec_raw),
            "direction": str(hint),
            "entry_low": round(float(entry_price), int(max(0, digits))),
            "entry_high": round(float(entry_price), int(max(0, digits))),
            "entry_mid": round(float(entry_price), int(max(0, digits))),
            "digits": int(digits),
            "point": float(point),
            "min_stop_dist": float(min_stop_dist),
            "atr": _to_float_or_none(atr),
            "stop_loss": (_to_float_or_none(stop_loss) if stop_loss is not None else None),
            "no_stop_loss": bool(no_stop_loss),
            "tps": list(tps),
            "raw_text": str(message),
            "timeframe": str(timeframe),
            "virtual_sl_distance": float(sl_distance),
            "stage_weights": list(stage_weights),
            "market_regime": str(active_regime),
            "hard_sl_mode": str(hard_sl_mode),
            # Advanced lock policy:
            # - Trend: default lock disabled (let winners run)
            # - Range: lock enabled with stricter arming and minimum close profit floor.
            "profit_lock_enabled": (False if str(active_regime) == "trend" else True),
            "profit_lock_retrace_pct": (0.82 if str(active_regime) == "trend" else 0.55),
            "profit_lock_arm_after_tp": (5 if str(active_regime) == "trend" else 3),
            "profit_lock_min_peak_usd": (90.0 if str(active_regime) == "trend" else 25.0),
            "profit_lock_min_hold_sec": (480.0 if str(active_regime) == "trend" else 150.0),
            "profit_lock_min_close_usd": (25.0 if str(active_regime) == "trend" else 8.0),
        }
        combo_source_tag = (
            f"mt4|{str(profile)}|{str(indicator_key)}|{str(symbol_exec).strip().upper()}|{str(timeframe).strip().upper()}"
        )
        reverse_out = self._close_mt4_reverse_positions(
            symbol=str(symbol_exec_raw),
            incoming_direction=str(hint),
            timeframe=str(timeframe),
            source_tag=str(combo_source_tag),
        )
        if not bool((reverse_out or {}).get("ok")):
            reverse_msg = (
                "reverse_close_failed: "
                + " | ".join(str(x) for x in ((reverse_out or {}).get("errors") or [])[:3])
            )
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_reverse_close_failed",
                parsed={
                    "symbol": str(symbol_exec_raw),
                    "direction": str(hint),
                    "profile": str(profile),
                    "reverse_close": dict(reverse_out or {}),
                },
                event_ts=event_ts,
                source_message_id=None,
            )
            return {"ok": False, "executed": False, "error": str(reverse_msg)[:220]}
        if int((reverse_out or {}).get("closed_count") or 0) > 0:
            self._clear_indicator_recent_open(source_tag=str(combo_source_tag))
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_reverse_close_done",
                parsed={
                    "symbol": str(symbol_exec_raw),
                    "direction": str(hint),
                    "profile": str(profile),
                    "reverse_close": dict(reverse_out or {}),
                },
                event_ts=event_ts,
                source_message_id=None,
            )
        guard = self._check_indicator_reversal_stability(
            combo_source_tag=str(combo_source_tag),
            incoming_direction=str(hint),
            now_ts=float(now_ts),
            force_wait=(int((reverse_out or {}).get("closed_count") or 0) > 0),
        )
        if not bool((guard or {}).get("ready")):
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_reversal_guard_waiting",
                parsed={
                    "symbol": str(symbol_exec_raw),
                    "direction": str(hint),
                    "profile": str(profile),
                    "wait": dict(guard or {}),
                    "reverse_close": dict(reverse_out or {}),
                },
                event_ts=event_ts,
                source_message_id=None,
            )
            self._queue_indicator_reversal_replay(
                combo_source_tag=str(combo_source_tag),
                terminal_family="mt4",
                payload={
                    "indicator": str(indicator),
                    "signal_profile": str(profile),
                    "signal_hint": str(hint),
                    "symbol": str(symbol_exec).strip().upper(),
                    "timeframe": str(timeframe).strip().upper(),
                    "message": str(message),
                    "event_ts": event_ts,
                    "bridge_event_type": "signal",
                    "ingest_source": "bridge",
                },
                now_ts=float(now_ts),
            )
            return {"ok": True, "executed": False, "reason": "reversal_guard_waiting", "wait": guard, "runtime": runtime_cfg}

        if self._has_live_open_for_source_tag_direction(
            source_tag=str(combo_source_tag),
            symbol=str(symbol_exec_raw),
            timeframe=str(timeframe),
            direction=str(hint),
            svc=svc,
        ):
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_exec_skip_same_direction_open",
                parsed={
                    "symbol": str(symbol_exec_raw),
                    "direction": str(hint),
                    "profile": str(profile),
                    "timeframe": str(timeframe),
                    "reason": "same_direction_already_open",
                },
                event_ts=event_ts,
                source_message_id=None,
            )
            return {"ok": True, "executed": False, "reason": "same_direction_already_open", "runtime": runtime_cfg}
        if self._has_indicator_recent_open(
            source_tag=str(combo_source_tag),
            direction=str(hint),
            now_ts=float(now_ts),
        ):
            self._append_confirm_signal_feed(
                source=str(source),
                chat={"title": str(source), "type": "channel"},
                text=str(message),
                kind="mt4_exec_skip_recent_open",
                parsed={
                    "symbol": str(symbol_exec_raw),
                    "direction": str(hint),
                    "profile": str(profile),
                    "timeframe": str(timeframe),
                    "reason": "recent_open_debounce",
                },
                event_ts=event_ts,
                source_message_id=None,
            )
            return {"ok": True, "executed": False, "reason": "recent_open_debounce", "runtime": runtime_cfg}

        lot = float(_to_float_or_none(runtime_cfg.get("lot_size")) or self._mt4_exec_profile_lot(profile))
        lot_override = _to_float_or_none(p.get("lot_override"))
        if lot_override is not None and float(lot_override) > 0.0:
            lot = float(max(0.01, min(100.0, float(lot_override))))
        chat_id = int(self._allowed_chat_id() or 0)
        exec_msg = self._execute_confirmation_signal_auto(
            chat_id=int(chat_id),
            signal=dict(signal),
            lot_override=float(lot),
            source_tag=str(combo_source_tag),
            comment_prefix="mt4",
            audit_ctx={
                "source_type": "mt_indicator",
                "source_name": str(indicator),
                "trigger": "indicator_signal",
                "profile": str(profile),
                "indicator": str(indicator),
                "event_ts": event_ts,
            },
        )
        executed = str(exec_msg or "").strip().lower().startswith("confirmation ladder executed")
        deferred_market_closed = str(exec_msg or "").strip().lower().startswith("confirmation deferred: market closed")

        self._append_confirm_signal_feed(
            source=str(source),
            chat={"title": str(source), "type": "channel"},
            text=str(message),
            kind=("mt4_exec" if executed else ("mt4_exec_deferred" if deferred_market_closed else "mt4_exec_failed")),
            parsed={
                "symbol": str(symbol_exec_raw),
                "direction": str(hint),
                "profile": str(profile),
                "timeframe": str(timeframe),
                "lot": float(lot),
                "sl_atr": float(self._mt4_exec_profile_sl_atr(profile)),
                "tp_atr": float(self._mt4_exec_profile_tp_atr(profile)),
                "tp_r_start": float(tp_r_start),
                "tp_r_step": float(tp_r_step),
                "regime_mode": str(regime_mode),
                "inferred_regime": str(inferred_regime),
                "active_regime": str(active_regime),
                "efficiency_ratio": _to_float_or_none((regime_info or {}).get("efficiency_ratio")),
                "donchian_atr_ratio": _to_float_or_none((regime_info or {}).get("donchian_atr_ratio")),
                "hard_sl_mode": str(hard_sl_mode),
                "catastrophic_sl_atr": float(self._mt4_exec_profile_catastrophic_sl_atr(profile)),
                "tp_levels": list(tp_multipliers),
                "stage_weights": list(stage_weights),
                "signal": dict(signal),
                "execution_message": str(exec_msg),
            },
            event_ts=event_ts,
            source_message_id=None,
        )
        out: Dict[str, Any] = {"ok": True, "executed": bool(executed), "message": str(exec_msg)}
        if deferred_market_closed:
            out["reason"] = "market_closed"
        return out

    def ingest_mt5_indicator_signal(self, *, payload: Dict[str, Any]) -> Dict[str, Any]:
        return self.ingest_indicator_bridge_signal(terminal_family="mt5", payload=payload)

    def _get_live_service(self) -> LiveTradingService:
        svc = self._live_service
        if svc is None:
            svc = LiveTradingService()
            self._live_service = svc
        return svc

    def _resolve_deadzone_watch_symbols(self) -> List[Dict[str, str]]:
        now = time.time()
        if self._deadzone_watch_resolved_cache and (now - float(self._deadzone_watch_resolved_cache_ts)) <= 300.0:
            return list(self._deadzone_watch_resolved_cache)
        svc = self._get_live_service()
        rows: List[Dict[str, str]] = []
        seen: set[Tuple[str, str]] = set()
        for label, aliases in self._DEADZONE_WATCH_BASE:
            resolved = None
            for alias in aliases:
                try:
                    got = svc.resolve_symbol_name(str(alias))
                except Exception:
                    got = None
                if got:
                    resolved = str(got)
                    break
            if not resolved:
                continue
            key = (str(label).upper(), str(resolved).upper())
            if key in seen:
                continue
            seen.add(key)
            rows.append({"label": str(label).upper(), "resolved": str(resolved)})
        self._deadzone_watch_resolved_cache = list(rows)
        self._deadzone_watch_resolved_cache_ts = now
        return rows

    @staticmethod
    def _normalize_live_bars_for_color_engine(bars: Any) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        if not isinstance(bars, list):
            return out
        for b in bars:
            if not isinstance(b, dict):
                continue
            t_raw = b.get("time_unix")
            if t_raw is None:
                t_raw = b.get("time")
            t_unix: Optional[int] = None
            try:
                t_unix = int(t_raw)
            except Exception:
                try:
                    s = str(t_raw or "").strip()
                    if s:
                        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
                        t_unix = int(dt.timestamp())
                except Exception:
                    t_unix = None
            if t_unix is None or int(t_unix) <= 0:
                continue
            try:
                o = float(b.get("open"))
                h = float(b.get("high"))
                l = float(b.get("low"))
                c = float(b.get("close"))
                v = float(b.get("volume") or 0.0)
                if not all(math.isfinite(x) for x in (o, h, l, c, v)):
                    continue
                out.append(
                    {
                        "time": int(t_unix),
                        "open": float(o),
                        "high": float(h),
                        "low": float(l),
                        "close": float(c),
                        "volume": float(v),
                    }
                )
            except Exception:
                continue
        return out

    @staticmethod
    def _deadzone_quick_trade_direction(from_color: Any, to_color: Any) -> Optional[str]:
        f = str(from_color or "").strip().lower()
        t = str(to_color or "").strip().lower()
        if f == "red" and t == "green":
            return "BUY"
        if f == "green" and t == "red":
            return "SELL"
        return None

    @staticmethod
    def _is_deadzone_core_symbol(resolved_symbol: Any) -> bool:
        s = str(resolved_symbol or "").strip().upper()
        if not s:
            return False
        return s.startswith("BTCUSD") or s.startswith("XAUUSD") or s.startswith("GOLD")

    def _build_deadzone_colorflip_alert_payload(
        self,
        *,
        chat_id: int,
        label: str,
        resolved: str,
        timeframe: str,
        from_color: str,
        to_color: str,
        price: Optional[float],
        rsi: Optional[float],
    ) -> Tuple[str, Optional[Dict[str, Any]]]:
        msg = (
            "Deadzone color flip (global watch)\n"
            f"Watch: {str(label).upper()}\n"
            f"Symbol/TF: {str(resolved)} {str(timeframe).upper()}\n"
            f"Flip: {str(from_color).upper()} -> {str(to_color).upper()}\n"
            f"Price: {('-' if price is None else f'{float(price):.2f}')}\n"
            f"RSI(14): {('-' if rsi is None else f'{float(rsi):.2f}')}\n"
            f"Time (UTC): {datetime.now(timezone.utc).isoformat()}"
        )
        markup = None
        if self._deadzone_quick_trade_direction(from_color, to_color) in {"BUY", "SELL"}:
            markup = {
                "inline_keyboard": [
                    [
                        self._inline_button(
                            int(chat_id),
                            "Quick Trade",
                            {
                                "type": "deadzone_quick_trade_start",
                                "symbol": str(resolved),
                                "timeframe": str(timeframe).upper(),
                                "from_color": str(from_color),
                                "to_color": str(to_color),
                                "one_shot": True,
                            },
                        )
                    ]
                ]
            }
        return msg, markup

    def _resolve_quick_trade_session(self, chat_id: int, symbol: str, timeframe: str) -> Tuple[Optional[int], str]:
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        if not sym:
            return None, "missing_symbol"
        db = SessionLocal()
        try:
            try:
                from ..api import simulation_routes as sim_routes
                symbols_equivalent = sim_routes._symbols_equivalent
            except Exception:
                symbols_equivalent = lambda a, b: str(a or "").strip().upper() == str(b or "").strip().upper()
            sid_default = self._resolve_default_session_id(int(chat_id))
            if sid_default is not None:
                row = db.query(SimulationSession).get(int(sid_default))
                if row is not None and str(row.strategy_id or "") == "_workbench":
                    row_sym = str(row.symbol or "").strip().upper()
                    row_tf = str(row.timeframe or "").strip().upper()
                    row_mode = str(getattr(row, "mode", "") or "").strip().lower()
                    if symbols_equivalent(row_sym, sym) and (not tf or row_tf == tf) and row_mode == "live":
                        return int(row.id), "default_live_match"
            rows = (
                db.query(SimulationSession)
                .filter(SimulationSession.strategy_id == "_workbench")
                .filter(SimulationSession.status == "active")
                .order_by(SimulationSession.updated_at.desc())
                .limit(200)
                .all()
            )
            for r in rows:
                rs = str(getattr(r, "symbol", "") or "").strip().upper()
                rt = str(getattr(r, "timeframe", "") or "").strip().upper()
                rm = str(getattr(r, "mode", "") or "").strip().lower()
                if symbols_equivalent(rs, sym) and rt == tf and rm == "live":
                    return int(r.id), "active_live_symbol_tf_match"
            for r in rows:
                rs = str(getattr(r, "symbol", "") or "").strip().upper()
                rt = str(getattr(r, "timeframe", "") or "").strip().upper()
                if symbols_equivalent(rs, sym) and rt == tf:
                    return int(r.id), "active_symbol_tf_match"
            for r in rows:
                rs = str(getattr(r, "symbol", "") or "").strip().upper()
                rm = str(getattr(r, "mode", "") or "").strip().lower()
                if symbols_equivalent(rs, sym) and rm == "live":
                    return int(r.id), "active_live_symbol_match"
            for r in rows:
                rs = str(getattr(r, "symbol", "") or "").strip().upper()
                if symbols_equivalent(rs, sym):
                    return int(r.id), "active_symbol_match"
            return None, "no_session_for_symbol"
        finally:
            try:
                db.close()
            except Exception:
                pass

    @staticmethod
    def _signal_price_zone_state(signal: Dict[str, Any], current_price: Optional[float]) -> str:
        px = _to_float_or_none(current_price)
        lo = _to_float_or_none(signal.get("entry_low"))
        hi = _to_float_or_none(signal.get("entry_high"))
        if px is None or lo is None or hi is None:
            return "unknown"
        if float(lo) <= float(px) <= float(hi):
            return "inside_zone"
        if float(px) < float(lo):
            return "below_zone"
        return "above_zone"

    @staticmethod
    def _is_price_inside_entry_zone(signal: Dict[str, Any], current_price: Optional[float]) -> bool:
        px = _to_float_or_none(current_price)
        lo = _to_float_or_none(signal.get("entry_low"))
        hi = _to_float_or_none(signal.get("entry_high"))
        if px is None or lo is None or hi is None:
            return False
        low = float(min(lo, hi))
        high = float(max(lo, hi))
        return bool(float(low) <= float(px) <= float(high))

    def _signal_live_price(self, *, signal: Dict[str, Any]) -> Optional[float]:
        symbol = str(signal.get("symbol") or "").strip()
        direction = str(signal.get("direction") or "").strip().upper()
        timeframe = str(signal.get("timeframe") or self._confirm_signal_default_timeframe()).strip().upper() or "M5"
        if not symbol:
            return None
        svc = self._get_live_service()
        px: Optional[float] = None
        try:
            tick = svc.get_symbol_tick(symbol=str(symbol), resolve_symbol=True)
        except Exception:
            tick = {}
        if isinstance(tick, dict):
            bid = _to_float_or_none((tick or {}).get("bid"))
            ask = _to_float_or_none((tick or {}).get("ask"))
            last = _to_float_or_none((tick or {}).get("last"))
            if direction == "BUY":
                px = ask if ask is not None else (last if last is not None else bid)
            elif direction == "SELL":
                px = bid if bid is not None else (last if last is not None else ask)
            else:
                px = last if last is not None else (bid if bid is not None else ask)
        if px is not None:
            return float(px)
        try:
            bars = svc.get_recent_candles(
                symbol=str(symbol),
                timeframe=str(timeframe),
                count=1,
                resolve_symbol=True,
            )
        except Exception:
            bars = []
        if isinstance(bars, list) and bars and isinstance(bars[-1], dict):
            return _to_float_or_none((bars[-1] or {}).get("close"))
        return None

    def _position_close_ref_price(
        self,
        *,
        svc: LiveTradingService,
        symbol: str,
        direction: str,
        pos: Dict[str, Any],
    ) -> Optional[float]:
        """
        Return the executable close-side reference for TP/SL checks.
        BUY positions close at bid, SELL positions close at ask.
        """
        side = str(direction or "").strip().upper()
        fallback = _to_float_or_none((pos or {}).get("current_price"))
        tick: Dict[str, Any] = {}
        try:
            tick = dict(svc.get_symbol_tick(symbol=str(symbol), resolve_symbol=False) or {})
        except Exception:
            tick = {}
        bid = _to_float_or_none(tick.get("bid"))
        ask = _to_float_or_none(tick.get("ask"))
        last = _to_float_or_none(tick.get("last"))
        if side == "BUY":
            return bid if bid is not None else (fallback if fallback is not None else (last if last is not None else ask))
        if side == "SELL":
            return ask if ask is not None else (fallback if fallback is not None else (last if last is not None else bid))
        return fallback if fallback is not None else (last if last is not None else (bid if bid is not None else ask))

    def _signal_recent_zone_touch(self, *, signal: Dict[str, Any]) -> bool:
        symbol = str(signal.get("symbol") or "").strip()
        if not symbol:
            return False
        lo = _to_float_or_none(signal.get("entry_low"))
        hi = _to_float_or_none(signal.get("entry_high"))
        if lo is None or hi is None:
            return False
        z_low = float(min(lo, hi))
        z_high = float(max(lo, hi))
        svc = self._get_live_service()
        try:
            # M1 high/low catches very short "touch then reverse" moves that can be missed by one-off ticks.
            bars = svc.get_recent_candles(
                symbol=str(symbol),
                timeframe="M1",
                count=2,
                resolve_symbol=True,
            )
        except Exception:
            bars = []
        if not isinstance(bars, list):
            return False
        for b in bars[-2:]:
            if not isinstance(b, dict):
                continue
            bh = _to_float_or_none((b or {}).get("high"))
            bl = _to_float_or_none((b or {}).get("low"))
            if bh is None or bl is None:
                continue
            if float(bh) >= float(z_low) and float(bl) <= float(z_high):
                return True
        return False

    def _queue_entry_signal(
        self,
        *,
        chat_id: int,
        signal: Dict[str, Any],
        source_label: str,
        source_key: str,
        lot_override: Optional[float] = None,
        source_tag: Optional[str] = None,
        comment_prefix: str = "tgc",
        audit_ctx: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        now_ts = float(time.time())
        sig = dict(signal or {})
        key_seed = (
            f"{str(source_key)}|{str(sig.get('symbol') or '').upper()}|{str(sig.get('direction') or '').upper()}|"
            f"{float(sig.get('entry_low') or 0.0):.5f}|{float(sig.get('entry_high') or 0.0):.5f}|"
            f"{float(sig.get('stop_loss') or 0.0):.5f}"
        )
        key_base = f"{str(source_key)}|{abs(hash(key_seed)) % 10000000:07d}"
        qid = f"{key_base}|{int(now_ts * 1000)}"
        row = {
            "id": str(qid),
            "chat_id": int(chat_id),
            "source_label": str(source_label or "").strip() or "unknown",
            "source_key": str(source_key or "").strip() or "unknown",
            "trace_id": str(sig.get("trace_id") or "").strip(),
            "signal": dict(sig),
            "lot_override": (_to_float_or_none(lot_override) if lot_override is not None else None),
            "source_tag": str(source_tag or "").strip(),
            "comment_prefix": str(comment_prefix or "tgc").strip() or "tgc",
            "audit_ctx": dict(audit_ctx or {}),
            "created_ts": float(now_ts),
            "last_attempt_ts": 0.0,
            "attempt_count": 0,
            "last_error": "",
            "last_zone_state": "unknown",
        }
        with self._lock:
            while qid in self._pending_entry_signals:
                now_ts = float(time.time())
                qid = f"{key_base}|{int(now_ts * 1000)}"
                row["id"] = str(qid)
                row["created_ts"] = float(now_ts)
            self._pending_entry_signals[str(qid)] = dict(row)
        return dict(row)

    def _queue_pending_confirmation_signal(
        self,
        *,
        chat_id: int,
        source_label: str,
        source_key: str,
        signal: Dict[str, Any],
        created_ts: Optional[float] = None,
    ) -> Dict[str, Any]:
        now_ts = float(created_ts if created_ts is not None else time.time())
        src_key = str(source_key or "").strip() or "unknown"
        src_label = str(source_label or "").strip() or "unknown"
        sym = str((signal or {}).get("symbol") or "").strip().upper()
        key_base = f"{src_key}|{sym or 'NA'}"
        qid = f"{key_base}|{int(now_ts * 1000)}"
        row = {
            "id": str(qid),
            "chat_id": int(chat_id),
            "source_label": str(src_label),
            "source_key": str(src_key),
            "trace_id": str((signal or {}).get("trace_id") or "").strip(),
            "signal": dict(signal or {}),
            "created_ts": float(now_ts),
        }
        with self._lock:
            stale_keys: List[str] = []
            for k, v in self._pending_confirmation_signals.items():
                if not isinstance(v, dict):
                    continue
                row_source_key = str(v.get("source_key") or k)
                row_signal = v.get("signal") if isinstance(v.get("signal"), dict) else {}
                row_sym = str((row_signal or {}).get("symbol") or "").strip().upper()
                if row_source_key == src_key and row_sym == sym:
                    stale_keys.append(str(k))
            for k in stale_keys:
                self._pending_confirmation_signals.pop(str(k), None)

            while qid in self._pending_confirmation_signals:
                now_ts = float(time.time())
                qid = f"{key_base}|{int(now_ts * 1000)}"
                row["id"] = str(qid)
                row["created_ts"] = float(now_ts)
            self._pending_confirmation_signals[str(qid)] = dict(row)
        return dict(row)

    def _pick_pending_confirmation_signal(
        self,
        *,
        candidate_source_keys: List[str],
    ) -> Tuple[Optional[str], Optional[Dict[str, Any]]]:
        candidates = [str(x).strip() for x in (candidate_source_keys or []) if str(x).strip()]
        if not candidates:
            return None, None
        with self._lock:
            best_key: Optional[str] = None
            best_row: Optional[Dict[str, Any]] = None
            best_ts: float = -1.0
            for k, v in self._pending_confirmation_signals.items():
                if not isinstance(v, dict):
                    continue
                row_source_key = str(v.get("source_key") or k)
                if row_source_key not in candidates:
                    continue
                created_ts = _to_float_or_none(v.get("created_ts")) or 0.0
                if best_row is None or float(created_ts) >= float(best_ts):
                    best_key = str(k)
                    best_row = dict(v)
                    best_ts = float(created_ts)
        return best_key, best_row

    def _push_pending_entry_signals(self) -> None:
        with self._lock:
            queue_rows = {str(k): dict(v) for k, v in self._pending_entry_signals.items()}
        if not queue_rows:
            return
        now_ts = float(time.time())
        wait_max = float(self._confirm_signal_entry_wait_max_sec())
        cooldown = float(self._confirm_signal_entry_attempt_cooldown_sec())
        remove_keys: List[str] = []

        for key, row in queue_rows.items():
            signal = row.get("signal") if isinstance(row.get("signal"), dict) else None
            if not isinstance(signal, dict):
                remove_keys.append(str(key))
                continue
            trace_id = str(row.get("trace_id") or signal.get("trace_id") or "").strip() or None
            created_ts = _to_float_or_none(row.get("created_ts")) or 0.0
            if created_ts > 0.0 and (now_ts - float(created_ts)) > wait_max:
                remove_keys.append(str(key))
                self._append_automation_execution_log(
                    source_type=str((row.get("audit_ctx") or {}).get("source_type") or "telegram_channel"),
                    source_name=str(row.get("source_label") or "unknown"),
                    trigger="entry_wait_expired",
                    status="expired",
                    symbol=str(signal.get("symbol") or "").strip().upper(),
                    timeframe=str(signal.get("timeframe") or "").strip().upper(),
                    direction=str(signal.get("direction") or "").strip().upper(),
                    lot=_to_float_or_none(row.get("lot_override")),
                    stop_loss=_to_float_or_none(signal.get("stop_loss")),
                    message="entry_zone_not_reached_in_time",
                    source_tag=str(row.get("source_tag") or "").strip().lower() or None,
                    execution_mode=str((row.get("audit_ctx") or {}).get("execution_mode") or "").strip().lower() or None,
                    trace_id=trace_id,
                    stage="entry_wait",
                    stage_status="expired",
                    error_code="entry_wait_timeout",
                    stage_payload={
                        "queue_id": str(row.get("id") or ""),
                        "wait_max_sec": float(wait_max),
                        "age_sec": float(max(0.0, now_ts - float(created_ts))),
                    },
                )
                self._send_text(
                    int(row.get("chat_id") or 0),
                    (
                        "Entry wait expired (zone not reached)\n"
                        f"Source: {str(row.get('source_label') or 'unknown')}\n"
                        f"Symbol: {str(signal.get('symbol') or '').upper()} {str(signal.get('direction') or '').upper()}"
                    ),
                )
                continue
            last_attempt = _to_float_or_none(row.get("last_attempt_ts")) or 0.0
            if last_attempt > 0.0 and (now_ts - float(last_attempt)) < cooldown:
                continue
            live_px = self._signal_live_price(signal=signal)
            inside_zone = self._is_price_inside_entry_zone(signal, live_px)
            prev_state = str(row.get("last_zone_state") or "unknown")
            zone_state = str(self._signal_price_zone_state(signal, live_px))
            crossed_zone = (
                prev_state in {"below_zone", "above_zone"}
                and zone_state in {"below_zone", "above_zone"}
                and prev_state != zone_state
            )
            age_sec = float(now_ts - float(created_ts)) if created_ts > 0.0 else 999999.0
            touched_recently = bool(age_sec <= 70.0 and self._signal_recent_zone_touch(signal=signal))
            with self._lock:
                cur = self._pending_entry_signals.get(str(key))
                if isinstance(cur, dict):
                    cur["last_zone_state"] = str(zone_state)
                    self._pending_entry_signals[str(key)] = dict(cur)
            if not (inside_zone or crossed_zone or touched_recently):
                continue
            self._append_automation_execution_log(
                source_type=str((row.get("audit_ctx") or {}).get("source_type") or "telegram_channel"),
                source_name=str(row.get("source_label") or "unknown"),
                trigger="entry_wait_trigger",
                status="dispatch",
                symbol=str(signal.get("symbol") or "").strip().upper(),
                timeframe=str(signal.get("timeframe") or "").strip().upper(),
                direction=str(signal.get("direction") or "").strip().upper(),
                lot=_to_float_or_none(row.get("lot_override")),
                stop_loss=_to_float_or_none(signal.get("stop_loss")),
                message=f"entry_trigger:{zone_state}",
                source_tag=str(row.get("source_tag") or "").strip().lower() or None,
                execution_mode=str((row.get("audit_ctx") or {}).get("execution_mode") or "").strip().lower() or None,
                trace_id=trace_id,
                stage="entry_wait",
                stage_status="triggered",
                stage_payload={
                    "queue_id": str(row.get("id") or ""),
                    "zone_state": str(zone_state),
                    "inside_zone": bool(inside_zone),
                    "crossed_zone": bool(crossed_zone),
                    "touched_recently": bool(touched_recently),
                    "live_price": _to_float_or_none(live_px),
                },
            )
            exec_msg = self._execute_confirmation_signal_auto(
                chat_id=int(row.get("chat_id") or 0),
                signal=dict(signal),
                lot_override=_to_float_or_none(row.get("lot_override")),
                source_tag=str(row.get("source_tag") or ""),
                comment_prefix=str(row.get("comment_prefix") or "tgc"),
                audit_ctx=dict(row.get("audit_ctx") or {}),
            )
            msg_l = str(exec_msg or "").strip().lower()
            ok_opened = self._is_confirmation_exec_opened(exec_msg)
            deferred = msg_l.startswith("confirmation deferred: market closed")
            if ok_opened:
                src_profile = str(signal.get("source_profile") or "").strip().lower()
                if self._profile_requires_tp_progress_gate(src_profile):
                    self._mark_reentry_signal_started(
                        source_key=str(row.get("source_key") or ""),
                        signal=dict(signal),
                        profile=str(src_profile),
                    )
                remove_keys.append(str(key))
                self._send_text(
                    int(row.get("chat_id") or 0),
                    (
                        "Entry trigger hit, order executed\n"
                        f"Source: {str(row.get('source_label') or 'unknown')}\n"
                        f"{str(exec_msg)}"
                    ),
                )
                continue
            with self._lock:
                cur = self._pending_entry_signals.get(str(key))
                if isinstance(cur, dict):
                    cur["last_attempt_ts"] = float(now_ts)
                    cur["attempt_count"] = int(cur.get("attempt_count") or 0) + 1
                    cur["last_error"] = str(exec_msg or "")
                    self._pending_entry_signals[str(key)] = dict(cur)
            if deferred:
                continue
            self._append_automation_execution_log(
                source_type=str((row.get("audit_ctx") or {}).get("source_type") or "telegram_channel"),
                source_name=str(row.get("source_label") or "unknown"),
                trigger="entry_wait_execute_failed",
                status="failed",
                symbol=str(signal.get("symbol") or "").strip().upper(),
                timeframe=str(signal.get("timeframe") or "").strip().upper(),
                direction=str(signal.get("direction") or "").strip().upper(),
                lot=_to_float_or_none(row.get("lot_override")),
                stop_loss=_to_float_or_none(signal.get("stop_loss")),
                message=str(exec_msg or "")[:260],
                source_tag=str(row.get("source_tag") or "").strip().lower() or None,
                execution_mode=str((row.get("audit_ctx") or {}).get("execution_mode") or "").strip().lower() or None,
                trace_id=trace_id,
                stage="entry_wait",
                stage_status="failed",
                error_code="execution_failed",
                stage_payload={
                    "queue_id": str(row.get("id") or ""),
                    "attempt_count": int((self._pending_entry_signals.get(str(key), {}) or {}).get("attempt_count") or 0),
                },
            )
            # For non-market-closed failures keep queued until wait timeout, but do not spam every tick.

        if remove_keys:
            with self._lock:
                for key in remove_keys:
                    self._pending_entry_signals.pop(str(key), None)

    def _build_confirmation_signal_markup(self, chat_id: int, signal: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        tps = signal.get("tps") if isinstance(signal.get("tps"), list) else []
        if not tps:
            return None
        rows: List[List[Dict[str, Any]]] = []
        cur: List[Dict[str, Any]] = []
        for row in tps[:5]:
            if not isinstance(row, dict):
                continue
            idx = int(row.get("index") or 0)
            px = _to_float_or_none(row.get("price"))
            if idx <= 0 or px is None:
                continue
            cur.append(
                self._inline_button(
                    int(chat_id),
                    f"TP{int(idx)}",
                    {
                        "type": "confirm_signal_execute",
                        "signal": dict(signal),
                        "tp_index": int(idx),
                        "one_shot": True,
                    },
                )
            )
            if len(cur) >= 3:
                rows.append(cur)
                cur = []
        if cur:
            rows.append(cur)
        rows.append([self._inline_button(int(chat_id), "Cancel", {"type": "confirm_signal_cancel", "one_shot": True})])
        return {"inline_keyboard": rows}

    def _format_confirmation_signal_alert(
        self,
        *,
        signal: Dict[str, Any],
        timeframe: str,
        current_price: Optional[float],
        source_label: str,
    ) -> str:
        tps = signal.get("tps") if isinstance(signal.get("tps"), list) else []
        tp_lines: List[str] = []
        for row in tps[:5]:
            if not isinstance(row, dict):
                continue
            idx = int(row.get("index") or 0)
            px = _to_float_or_none(row.get("price"))
            if idx <= 0 or px is None:
                continue
            tp_lines.append(f"TP{int(idx)} {float(px):.5f}")
        zone_state = self._signal_price_zone_state(signal, current_price)
        zone_text = {
            "inside_zone": "inside entry zone",
            "below_zone": "below entry zone",
            "above_zone": "above entry zone",
        }.get(str(zone_state), "entry zone unknown")
        return (
            "Confirmation signal detected\n"
            f"Source: {str(source_label)}\n"
            f"Symbol/TF: {str(signal.get('symbol') or '').upper()} {str(timeframe).upper()}\n"
            f"Direction: {str(signal.get('direction') or '').upper()}\n"
            f"Mode: {('single_trade (no partial)' if bool(signal.get('force_single_trade')) else 'tp_ladder')}\n"
            f"Entry zone: {float(signal.get('entry_low') or 0.0):.5f} / {float(signal.get('entry_high') or 0.0):.5f}\n"
            f"SL: {float(signal.get('stop_loss') or 0.0):.5f}\n"
            f"Market: {('-' if current_price is None else f'{float(current_price):.5f}')} ({zone_text})\n"
            f"Default lot: {float(self._confirm_signal_default_lot()):.4f}\n"
            + "\n".join(tp_lines)
            + "\nAuto-executing TP ladder."
        )

    def _build_confirmation_ladder_lots(self, *, symbol: str, total_lot: float, stage_count: int) -> Tuple[Optional[List[float]], Optional[str]]:
        svc = self._get_live_service()
        info = svc.get_symbol_info(symbol=str(symbol))
        if isinstance(info, dict) and str(info.get("error") or "").strip():
            return None, f"Symbol info unavailable for {str(symbol).upper()}: {str(info.get('error'))[:140]}"
        vol_min = _to_float_or_none((info or {}).get("volume_min")) or 0.01
        vol_step = _to_float_or_none((info or {}).get("volume_step")) or 0.01
        vol_max = _to_float_or_none((info or {}).get("volume_max")) or float(total_lot)
        vol_step = max(1e-6, float(vol_step))
        vol_min = max(float(vol_step), float(vol_min))
        total = max(0.0, min(float(total_lot), float(max(vol_min, vol_max))))
        min_required = float(vol_step) * float(stage_count)
        if float(total) + 1e-12 < float(min_required):
            return None, (
                f"default_lot_too_small_for_5tp: lot={float(total):.4f} "
                f"min_required={float(min_required):.4f} step={float(vol_step):.4f}"
            )
        step_units_total = int(math.floor(float(total) / float(vol_step) + 1e-9))
        if step_units_total < int(stage_count):
            return None, (
                f"default_lot_too_small_for_5tp: lot={float(total):.4f} "
                f"min_required={float(min_required):.4f} step={float(vol_step):.4f}"
            )
        mode = self._confirm_signal_tp_distribution_mode()
        units = self._build_confirmation_stage_units(
            total_units=int(step_units_total),
            stage_count=int(stage_count),
            mode=str(mode),
        )
        if not units:
            return None, "invalid_tp_stage_distribution"
        lots: List[float] = [float(u) * float(vol_step) for u in units]
        if not lots or any(float(x) < float(vol_min) - 1e-12 for x in lots):
            return None, (
                f"default_lot_too_small_for_5tp: lot={float(total):.4f} "
                f"min_required={float(min_required):.4f} step={float(vol_step):.4f}"
            )
        lots[-1] = float(max(vol_min, round(float(step_units_total) * float(vol_step) - sum(lots[:-1]), 8)))
        return lots, None

    @staticmethod
    def _tp_stage_cap_for_profile(profile: Any) -> int:
        p = str(profile or "").strip().lower()
        # Elite channels are explicitly fixed to 5 TP logic.
        if p == "elite":
            return 5
        # 0 => no explicit cap; use all parsed TPs (subject to lot feasibility fallback).
        return 0

    @staticmethod
    def _compress_tps_for_stage_count(tps: List[Dict[str, Any]], stage_count: int) -> List[Dict[str, Any]]:
        rows = [dict(x) for x in (tps or []) if isinstance(x, dict)]
        n = len(rows)
        if n <= 0:
            return []
        s = int(max(1, min(int(stage_count), n)))
        if s >= n:
            return rows
        if s == 1:
            return [dict(rows[-1])]
        selected: List[int] = []
        last = -1
        for i in range(s):
            target = (float(i) * float(n - 1)) / float(s - 1)
            idx = int(round(target))
            if idx <= last:
                idx = int(last + 1)
            max_idx_allowed = int((n - 1) - (s - 1 - i))
            if idx > max_idx_allowed:
                idx = max_idx_allowed
            idx = max(0, min(n - 1, int(idx)))
            selected.append(int(idx))
            last = int(idx)
        return [dict(rows[i]) for i in selected]

    @classmethod
    def _select_execution_tps(cls, *, tps_all: List[Dict[str, Any]], source_profile: str, force_single: bool) -> List[Dict[str, Any]]:
        rows = [dict(x) for x in (tps_all or []) if isinstance(x, dict)]
        if not rows:
            return []
        if bool(force_single):
            # Single-trade mode should target the final channel TP, not TP1.
            return cls._compress_tps_for_stage_count(rows, 1)
        cap = int(cls._tp_stage_cap_for_profile(source_profile))
        if cap > 0:
            return [dict(x) for x in rows[:cap]]
        return rows

    @staticmethod
    def _build_confirmation_stage_units(*, total_units: int, stage_count: int, mode: str) -> List[int]:
        total = int(total_units)
        stages = int(stage_count)
        if total <= 0 or stages <= 0 or total < stages:
            return []
        base = [1 for _ in range(stages)]
        remain = int(total - stages)
        if remain <= 0:
            return base
        m = str(mode or "equal").strip().lower()
        if m == "front_loaded":
            weights = [float(stages - i) for i in range(stages)]
        elif m == "runner":
            weights = [float(i + 1) for i in range(stages)]
        else:
            weights = [1.0 for _ in range(stages)]
        wsum = float(sum(weights))
        if wsum <= 0.0:
            return []
        extras_floor = [0 for _ in range(stages)]
        fracs: List[Tuple[float, int]] = []
        assigned = 0
        for i in range(stages):
            exact = (float(remain) * float(weights[i])) / wsum
            floor_u = int(math.floor(exact + 1e-12))
            extras_floor[i] = floor_u
            assigned += floor_u
            fracs.append((float(exact - float(floor_u)), int(i)))
        leftovers = int(remain - assigned)
        if leftovers > 0:
            # Largest remainder method for deterministic integer distribution.
            fracs.sort(key=lambda x: (-float(x[0]), int(x[1])))
            for j in range(leftovers):
                idx = int(fracs[j % len(fracs)][1])
                extras_floor[idx] += 1
        out = [int(base[i] + extras_floor[i]) for i in range(stages)]
        if sum(out) != total:
            return []
        return out

    @staticmethod
    def _build_weighted_stage_units(*, total_units: int, stage_count: int, weights: List[float]) -> List[int]:
        total = int(total_units)
        stages = int(stage_count)
        if total <= 0 or stages <= 0 or total < stages:
            return []
        w_in = [float(x) for x in (weights or []) if math.isfinite(float(x)) and float(x) > 0.0]
        if not w_in:
            w_in = [1.0 for _ in range(stages)]
        if len(w_in) < stages:
            w_in.extend([float(w_in[-1])] * (stages - len(w_in)))
        elif len(w_in) > stages:
            w_in = w_in[:stages]
        wsum = float(sum(w_in))
        if wsum <= 0.0:
            return []

        # Largest remainder on total units for closest weighted allocation.
        base = [0 for _ in range(stages)]
        frac_rows: List[Tuple[float, int]] = []
        assigned = 0
        for i in range(stages):
            exact = (float(total) * float(w_in[i])) / float(wsum)
            fu = int(math.floor(exact + 1e-12))
            base[i] = int(max(0, fu))
            assigned += int(base[i])
            frac_rows.append((float(exact - float(fu)), int(i)))

        leftovers = int(total - assigned)
        if leftovers > 0:
            frac_rows.sort(key=lambda x: (-float(x[0]), int(x[1])))
            for j in range(leftovers):
                idx = int(frac_rows[j % len(frac_rows)][1])
                base[idx] = int(base[idx] + 1)

        # Enforce at least 1 unit per stage by borrowing from the largest buckets.
        for i in range(stages):
            if int(base[i]) > 0:
                continue
            donor = -1
            donor_units = 0
            for d in range(stages):
                u = int(base[d])
                if u > 1 and u > donor_units:
                    donor = int(d)
                    donor_units = int(u)
            if donor < 0:
                return []
            base[donor] = int(base[donor] - 1)
            base[i] = int(base[i] + 1)

        if sum(int(x) for x in base) != total:
            return []
        if any(int(x) < 1 for x in base):
            return []
        return [int(x) for x in base]

    def _build_confirmation_ladder_lots_weighted(
        self,
        *,
        symbol: str,
        total_lot: float,
        stage_count: int,
        weights: List[float],
    ) -> Tuple[Optional[List[float]], Optional[str]]:
        svc = self._get_live_service()
        info = svc.get_symbol_info(symbol=str(symbol))
        if isinstance(info, dict) and str(info.get("error") or "").strip():
            return None, f"Symbol info unavailable for {str(symbol).upper()}: {str(info.get('error'))[:140]}"
        vol_min = _to_float_or_none((info or {}).get("volume_min")) or 0.01
        vol_step = _to_float_or_none((info or {}).get("volume_step")) or 0.01
        vol_max = _to_float_or_none((info or {}).get("volume_max")) or float(total_lot)
        vol_step = max(1e-6, float(vol_step))
        vol_min = max(float(vol_step), float(vol_min))
        total = max(0.0, min(float(total_lot), float(max(vol_min, vol_max))))
        step_units_total = int(math.floor(float(total) / float(vol_step) + 1e-9))
        if step_units_total < int(stage_count):
            min_required = float(vol_step) * float(stage_count)
            return None, (
                f"default_lot_too_small_for_weighted_stages: lot={float(total):.4f} "
                f"min_required={float(min_required):.4f} step={float(vol_step):.4f}"
            )
        units = self._build_weighted_stage_units(
            total_units=int(step_units_total),
            stage_count=int(stage_count),
            weights=list(weights or []),
        )
        if not units:
            return None, "invalid_weighted_stage_distribution"
        lots: List[float] = [float(u) * float(vol_step) for u in units]
        if not lots or any(float(x) < float(vol_min) - 1e-12 for x in lots):
            return None, "weighted_stage_lot_below_symbol_min"
        # Ensure exact sum after float rounding drift.
        lots[-1] = float(max(vol_min, round(float(step_units_total) * float(vol_step) - sum(lots[:-1]), 8)))
        return lots, None

    def _register_confirmation_ladder(
        self,
        *,
        chat_id: int,
        session_id: int,
        symbol: str,
        timeframe: str,
        direction: str,
        trade_id: int,
        broker_ticket: int,
        stage_lots: List[float],
        tps: List[Dict[str, Any]],
        source_tag: Optional[str] = None,
        order_comment: Optional[str] = None,
        source_key: Optional[str] = None,
        source_name: Optional[str] = None,
        profile: Optional[str] = None,
        indicator: Optional[str] = None,
        execution_mode: Optional[str] = None,
        profit_lock_enabled: Optional[bool] = None,
        profit_lock_retrace_pct: Optional[float] = None,
        profit_lock_arm_after_tp: Optional[int] = None,
        profit_lock_min_peak_usd: Optional[float] = None,
        profit_lock_min_hold_sec: Optional[float] = None,
        profit_lock_min_close_usd: Optional[float] = None,
        entry_price: Optional[float] = None,
        initial_stop_loss: Optional[float] = None,
        no_stop_loss: Optional[bool] = None,
        extra_state: Optional[Dict[str, Any]] = None,
        trace_id: Optional[str] = None,
    ) -> None:
        key = f"{int(chat_id)}:{int(session_id)}:{int(trade_id)}:{int(broker_ticket)}"
        row = {
            "chat_id": int(chat_id),
            "session_id": int(session_id),
            "trade_id": int(trade_id),
            "broker_ticket": int(broker_ticket),
            "symbol": str(symbol).strip().upper(),
            "timeframe": str(timeframe).strip().upper(),
            "direction": str(direction).strip().upper(),
            "stage_lots": [float(x) for x in stage_lots],
            "tps": [dict(x) for x in tps if isinstance(x, dict)],
            "next_tp_index": 1,
            "created_at": self._now_iso(),
            "source_tag": str(source_tag or "").strip().lower(),
            "order_comment": str(order_comment or "").strip(),
            "source_key": str(source_key or "").strip(),
            "source_name": str(source_name or "").strip(),
            "profile": str(profile or "").strip().lower(),
            "indicator": str(indicator or "").strip(),
            "execution_mode": str(execution_mode or "").strip().lower() or "advanced",
            "max_profit": None,
            "max_loss": None,
            "profit_lock_enabled": (bool(profit_lock_enabled) if profit_lock_enabled is not None else None),
            "profit_lock_retrace_pct": (_to_float_or_none(profit_lock_retrace_pct) if profit_lock_retrace_pct is not None else None),
            "profit_lock_arm_after_tp": (int(profit_lock_arm_after_tp) if profit_lock_arm_after_tp is not None else None),
            "profit_lock_min_peak_usd": (_to_float_or_none(profit_lock_min_peak_usd) if profit_lock_min_peak_usd is not None else None),
            "profit_lock_min_hold_sec": (_to_float_or_none(profit_lock_min_hold_sec) if profit_lock_min_hold_sec is not None else None),
            "profit_lock_min_close_usd": (_to_float_or_none(profit_lock_min_close_usd) if profit_lock_min_close_usd is not None else None),
            "entry_price": _to_float_or_none(entry_price),
            "initial_stop_loss": _to_float_or_none(initial_stop_loss),
            "no_stop_loss": bool(no_stop_loss) if no_stop_loss is not None else None,
            "last_sl_update_tp_index": 0,
            "last_applied_sl": None,
            "missing_seen_count": 0,
            "missing_first_ts": None,
            "trace_id": str(trace_id or "").strip(),
        }
        if isinstance(extra_state, dict) and extra_state:
            for k, v in extra_state.items():
                key_name = str(k or "").strip()
                if not key_name:
                    continue
                row[key_name] = v
        with self._lock:
            self._active_confirmation_signal_ladders[str(key)] = row

    def _build_advanced_v2_signal_plan(
        self,
        *,
        signal: Dict[str, Any],
        direction: str,
        entry_price: float,
        digits: int,
        point: float,
        min_stop_dist: float,
        atr: Optional[float],
    ) -> Dict[str, Any]:
        side = str(direction or "").strip().upper()
        d = 1.0 if side == "BUY" else -1.0
        entry = float(entry_price)
        slippage_buffer_pct = 0.0008
        stop_loss_raw = _to_float_or_none(signal.get("stop_loss"))
        if stop_loss_raw is not None and math.isfinite(float(stop_loss_raw)):
            r_dist = abs(float(entry) - float(stop_loss_raw))
        else:
            r_dist = _to_float_or_none(signal.get("virtual_sl_distance")) or _to_float_or_none(atr) or 0.0
        r_dist = float(max(float(r_dist), float(min_stop_dist) * 1.80, float(point) * 25.0, abs(float(entry)) * 0.0005))
        raw_sl = float(entry - (d * float(r_dist)))
        buffer_abs = float(abs(entry) * float(slippage_buffer_pct))
        internal_sl = float(raw_sl - (d * buffer_abs))
        tp_rr = [1.0, 2.0, 3.0, None]
        tps = []
        for idx, rr in enumerate(tp_rr, start=1):
            if rr is None:
                tps.append({"index": int(idx), "price": None})
            else:
                px = float(entry + (d * r_dist * float(rr)))
                tps.append({"index": int(idx), "price": round(float(px), int(max(0, digits)))})
        plan = {
            "tps": list(tps),
            "stage_weights": [0.25, 0.25, 0.25, 0.25],
            "profit_lock_enabled": False,
            "profit_lock_retrace_pct": None,
            "profit_lock_arm_after_tp": None,
            "profit_lock_min_peak_usd": None,
            "profit_lock_min_hold_sec": None,
            "profit_lock_min_close_usd": None,
            "v2_cfg": {
                "r_distance": float(r_dist),
                "slippage_buffer_pct": float(slippage_buffer_pct),
                "raw_sl": round(float(raw_sl), int(max(0, digits))),
                "internal_sl": round(float(internal_sl), int(max(0, digits))),
                "trail_atr_mult": 1.5,
                "trail_chandelier": 2.0,
                "trail_widen_adx": 40.0,
                "cons_adx_thresh": 25.0,
                "cons_atr_ratio": 0.7,
                "cons_bb_thresh": 0.4,
            },
        }
        return plan

    @staticmethod
    def _is_confirmation_exec_opened(exec_msg: Any) -> bool:
        msg = str(exec_msg or "").strip().lower()
        if not msg:
            return False
        return bool(
            msg.startswith("confirmation ladder executed")
            or msg.startswith("normal mode order executed")
            or msg == "exec_ok"
        )

    def _execute_confirmation_signal_auto(
        self,
        *,
        chat_id: int,
        signal: Dict[str, Any],
        lot_override: Optional[float] = None,
        source_tag: Optional[str] = None,
        comment_prefix: str = "tgc",
        audit_ctx: Optional[Dict[str, Any]] = None,
        execution_mode: str = "advanced",
    ) -> str:
        audit = dict(audit_ctx or {})
        audit_source_type = str(audit.get("source_type") or "telegram_channel").strip() or "telegram_channel"
        audit_source_name = str(audit.get("source_name") or "unknown").strip() or "unknown"
        audit_source_key = str(audit.get("source_key") or "").strip()
        audit_trigger = str(audit.get("trigger") or "entry_signal").strip() or "entry_signal"
        audit_profile = str(audit.get("profile") or "").strip().lower()
        audit_indicator = str(audit.get("indicator") or "").strip()
        audit_event_ts = audit.get("event_ts")
        exec_mode = str(execution_mode or "advanced").strip().lower() or "advanced"
        trace_id = str(signal.get("trace_id") or audit.get("trace_id") or "").strip()

        symbol = str(signal.get("symbol") or "").strip().upper()
        direction = str(signal.get("direction") or "").strip().upper()
        stop_loss = _to_float_or_none(signal.get("stop_loss"))
        allow_no_sl = bool(signal.get("no_stop_loss"))
        timeframe = str(signal.get("timeframe") or self._confirm_signal_default_timeframe()).strip().upper() or "M5"
        tps_all = [dict(r) for r in (signal.get("tps") if isinstance(signal.get("tps"), list) else []) if isinstance(r, dict)]
        signal_profile = str(signal.get("source_profile") or audit_profile or "").strip().lower()
        if (not audit_profile) and signal_profile:
            audit_profile = str(signal_profile)
        if not trace_id:
            trace_id = self._build_execution_trace_id(
                source_key=str(audit_source_key),
                symbol=str(symbol),
                direction=str(direction),
            )
            signal["trace_id"] = str(trace_id)
        self._append_automation_execution_log(
            source_type=audit_source_type,
            source_name=audit_source_name,
            trigger="signal_exec_start",
            status="processing",
            symbol=symbol,
            timeframe=timeframe,
            direction=direction,
            lot=_to_float_or_none(lot_override),
            stop_loss=stop_loss,
            stages_total=len(tps_all),
            message="execution_started",
            profile=audit_profile,
            indicator=audit_indicator,
            source_tag=source_tag,
            event_ts=audit_event_ts,
            execution_mode=exec_mode,
            trace_id=str(trace_id),
            stage="validate",
            stage_status="started",
            stage_payload={
                "entry_low": _to_float_or_none(signal.get("entry_low")),
                "entry_high": _to_float_or_none(signal.get("entry_high")),
                "entry_mid": _to_float_or_none(signal.get("entry_mid")),
                "allow_no_sl": bool(allow_no_sl),
                "requested_tp_count": int(len(tps_all)),
                "requested_mode": str(exec_mode),
            },
        )
        if direction not in {"BUY", "SELL"} or (not symbol) or (not tps_all) or ((not allow_no_sl) and stop_loss is None):
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="rejected",
                symbol=symbol,
                timeframe=timeframe,
                direction=direction,
                stop_loss=stop_loss,
                stages_total=len(tps_all),
                message="invalid_signal_payload",
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                execution_mode=exec_mode,
                trace_id=str(trace_id),
                stage="validate",
                stage_status="failed",
                error_code="invalid_signal_payload",
            )
            return "Signal payload invalid for auto TP execution."
        lot = float(self._confirm_signal_default_lot())
        lot_ovr = _to_float_or_none(lot_override)
        if lot_ovr is not None and float(lot_ovr) > 0.0:
            lot = float(lot_ovr)
        stage_mode = str(self._confirm_signal_tp_distribution_mode())
        allow_msg_single = bool(self._confirm_signal_allow_message_single_trade_override())
        force_single = bool(
            self._confirm_signal_force_single_trade_01()
            or (allow_msg_single and bool(signal.get("force_single_trade")))
        )
        extra_ladder_state: Dict[str, Any] = {}
        if str(exec_mode) == "advanced_v2":
            digits_v2 = int(_to_float_or_none(signal.get("digits")) or 5)
            point_v2 = _to_float_or_none(signal.get("point")) or 0.0001
            min_stop_dist_v2 = _to_float_or_none(signal.get("min_stop_dist")) or 0.0
            atr_v2 = _to_float_or_none(signal.get("atr"))
            entry_v2 = _to_float_or_none(signal.get("entry_mid"))
            if entry_v2 is None or float(entry_v2) <= 0.0:
                entry_v2 = _to_float_or_none(signal.get("entry_high"))
            if entry_v2 is None or float(entry_v2) <= 0.0:
                entry_v2 = _to_float_or_none(signal.get("entry_low"))
            if entry_v2 is not None and float(entry_v2) > 0.0:
                v2_plan = self._build_advanced_v2_signal_plan(
                    signal=signal,
                    direction=direction,
                    entry_price=float(entry_v2),
                    digits=int(digits_v2),
                    point=float(point_v2),
                    min_stop_dist=float(min_stop_dist_v2),
                    atr=_to_float_or_none(atr_v2),
                )
                tps_all = [dict(x) for x in (v2_plan.get("tps") or []) if isinstance(x, dict)]
                signal["stage_weights"] = list(v2_plan.get("stage_weights") or [])
                signal["profit_lock_enabled"] = v2_plan.get("profit_lock_enabled")
                signal["profit_lock_retrace_pct"] = v2_plan.get("profit_lock_retrace_pct")
                signal["profit_lock_arm_after_tp"] = v2_plan.get("profit_lock_arm_after_tp")
                signal["profit_lock_min_peak_usd"] = v2_plan.get("profit_lock_min_peak_usd")
                signal["profit_lock_min_hold_sec"] = v2_plan.get("profit_lock_min_hold_sec")
                signal["profit_lock_min_close_usd"] = v2_plan.get("profit_lock_min_close_usd")
                stage_mode = "advanced_v2_rr4"
                extra_ladder_state["advanced_v2_cfg"] = dict(v2_plan.get("v2_cfg") or {})
        if force_single:
            # Emergency mode disables partial laddering, but keeps operator-selected lot sizing.
            stage_mode = "single_trade"
        active_tps: List[Dict[str, Any]] = self._select_execution_tps(
            tps_all=list(tps_all),
            source_profile=str(signal_profile),
            force_single=bool(force_single),
        )
        desired_stages = int(max(1, len(active_tps)))
        weighted_stage_mode = bool(
            (str(audit_source_type).strip().lower() == "mt_indicator")
            and isinstance(signal.get("stage_weights"), list)
            and len(signal.get("stage_weights") or []) > 0
        )
        stage_weights = [
            float(x)
            for x in (signal.get("stage_weights") if isinstance(signal.get("stage_weights"), list) else [])
            if _to_float_or_none(x) is not None and float(_to_float_or_none(x) or 0.0) > 0.0
        ]
        if weighted_stage_mode and (not force_single):
            stage_mode = "weighted_indicator"
        if weighted_stage_mode:
            stage_lots, stage_err = self._build_confirmation_ladder_lots_weighted(
                symbol=str(symbol),
                total_lot=float(lot),
                stage_count=int(desired_stages),
                weights=list(stage_weights),
            )
        else:
            stage_lots, stage_err = self._build_confirmation_ladder_lots(
                symbol=str(symbol),
                total_lot=float(lot),
                stage_count=int(desired_stages),
            )
        if stage_lots is None:
            # Fallback: if lot is too small for full 5-stage split, degrade to max feasible stages.
            try:
                info = self._get_live_service().get_symbol_info(symbol=str(symbol))
            except Exception:
                info = {}
            vol_step = _to_float_or_none((info or {}).get("volume_step")) or 0.01
            max_stages = int(math.floor(float(lot) / float(max(vol_step, 1e-6))))
            max_stages = int(max(1, min(int(desired_stages), int(max_stages))))
            if int(self._tp_stage_cap_for_profile(signal_profile)) > 0 and (not force_single):
                active_tps = [dict(x) for x in active_tps[:max_stages]]
            else:
                active_tps = self._compress_tps_for_stage_count(list(active_tps), int(max_stages))
            if weighted_stage_mode:
                stage_lots, stage_err = self._build_confirmation_ladder_lots_weighted(
                    symbol=str(symbol),
                    total_lot=float(lot),
                    stage_count=int(len(active_tps)),
                    weights=list(stage_weights),
                )
            else:
                stage_lots, stage_err = self._build_confirmation_ladder_lots(
                    symbol=str(symbol),
                    total_lot=float(lot),
                    stage_count=int(len(active_tps)),
                )
        if stage_lots is None:
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="failed",
                symbol=symbol,
                timeframe=timeframe,
                direction=direction,
                lot=lot,
                stop_loss=stop_loss,
                stages_total=len(tps_all),
                message=str(stage_err),
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                execution_mode=exec_mode,
                trace_id=str(trace_id),
                stage="lot_planning",
                stage_status="failed",
                error_code="lot_planning_failed",
            )
            return f"Confirmation trade failed: {str(stage_err)}"
        take_profit = _to_float_or_none((active_tps[-1] or {}).get("price")) if active_tps else None
        if take_profit is None and str(exec_mode) != "advanced_v2":
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="failed",
                symbol=symbol,
                timeframe=timeframe,
                direction=direction,
                lot=lot,
                stop_loss=stop_loss,
                stages_total=len(tps_all),
                message="invalid_take_profit",
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                execution_mode=exec_mode,
                trace_id=str(trace_id),
                stage="validate",
                stage_status="failed",
                error_code="invalid_take_profit",
            )
            return "Confirmation trade failed: invalid_take_profit"
        self._append_automation_execution_log(
            source_type=audit_source_type,
            source_name=audit_source_name,
            trigger="signal_exec_plan",
            status="planned",
            symbol=symbol,
            timeframe=timeframe,
            direction=direction,
            lot=lot,
            stop_loss=stop_loss,
            final_tp=take_profit,
            stages_total=len(tps_all),
            stages_opened=len(stage_lots),
            message="execution_plan_ready",
            profile=audit_profile,
            indicator=audit_indicator,
            source_tag=source_tag,
            event_ts=audit_event_ts,
            execution_mode=exec_mode,
            trace_id=str(trace_id),
            stage="planning",
            stage_status="ok",
            stage_payload={
                "stage_mode": str(stage_mode),
                "active_tps": [dict(x) for x in active_tps],
                "stage_lots": [float(x) for x in stage_lots],
                "force_single": bool(force_single),
                "allow_message_single_override": bool(allow_msg_single),
            },
        )
        svc = self._get_live_service()
        pref = re.sub(r"[^a-z0-9]", "", str(comment_prefix or "tgc").strip().lower())[:8] or "tgc"
        marker = f"{pref}{int(time.time() * 1000) % 10000000000:010d}"
        try:
            if str(exec_mode) == "advanced_v2":
                order_stop_loss = None
            else:
                order_stop_loss = None if bool(allow_no_sl) else float(stop_loss)
            data = svc.place_market_order(
                symbol=str(symbol),
                direction=str(direction),
                lot_size=float(lot),
                stop_loss=order_stop_loss,
                take_profit=(None if take_profit is None else float(take_profit)),
                comment=str(marker),
            )
            if not bool((data or {}).get("ok")):
                err_txt = str((data or {}).get("error") or "order_failed")
                if self._is_invalid_stops_error(err_txt):
                    if bool(allow_no_sl) or str(exec_mode) == "advanced_v2":
                        if take_profit is None:
                            retry_data = dict(data or {})
                        else:
                            retry_data = self._retry_order_for_invalid_tp_only(
                                svc=svc,
                                symbol=str(symbol),
                                direction=str(direction),
                                lot=float(lot),
                                take_profit=float(take_profit),
                                comment=str(marker),
                            )
                    elif bool(allow_no_sl):
                        retry_data = self._retry_order_for_invalid_tp_only(
                            svc=svc,
                            symbol=str(symbol),
                            direction=str(direction),
                            lot=float(lot),
                            take_profit=float(take_profit),
                            comment=str(marker),
                        )
                    else:
                        retry_data = self._retry_order_for_invalid_stops(
                            svc=svc,
                            symbol=str(symbol),
                            direction=str(direction),
                            lot=float(lot),
                            stop_loss=float(stop_loss),
                            take_profit=float(take_profit),
                            comment=str(marker),
                        )
                    if bool((retry_data or {}).get("ok")):
                        data = dict(retry_data or {})
                    else:
                        retry_err = str((retry_data or {}).get("error") or "").strip()
                        if retry_err:
                            err_txt = f"{err_txt} | retry_failed:{retry_err}"
                market_closed = self._is_market_closed_error(err_txt)
                if not bool((data or {}).get("ok")):
                    self._append_automation_execution_log(
                        source_type=audit_source_type,
                        source_name=audit_source_name,
                        trigger=audit_trigger,
                        status=("deferred" if market_closed else "failed"),
                        symbol=symbol,
                        timeframe=timeframe,
                        direction=direction,
                        lot=lot,
                        stop_loss=stop_loss,
                        final_tp=take_profit,
                        stages_total=len(tps_all),
                        stages_opened=len(stage_lots),
                        message=("market_closed" if market_closed else err_txt),
                        profile=audit_profile,
                        indicator=audit_indicator,
                        source_tag=source_tag,
                        event_ts=audit_event_ts,
                        execution_mode=exec_mode,
                        trace_id=str(trace_id),
                        stage="order_send",
                        stage_status=("deferred" if market_closed else "failed"),
                        error_code=("market_closed" if market_closed else "order_send_failed"),
                        stage_payload={
                            "broker_error": str(err_txt or "")[:240],
                            "retry_applied": bool("retry_failed" in str(err_txt or "")),
                        },
                    )
                    if market_closed:
                        return "Confirmation deferred: market closed (broker retcode 10018)."
                    return f"Confirmation trade failed: {err_txt[:220]}"
            broker_ticket = int(_to_float_or_none((data or {}).get("position")) or 0)
            if broker_ticket <= 0:
                broker_ticket = int(_to_float_or_none((data or {}).get("order")) or 0)
            if broker_ticket <= 0:
                broker_ticket = int(_to_float_or_none((data or {}).get("deal")) or 0)
            try:
                rows = svc.get_open_positions(symbol=str(symbol))
            except Exception:
                rows = []
            by_marker = [
                dict(r)
                for r in (rows or [])
                if str((r or {}).get("direction") or "").strip().upper() == str(direction)
                and str((r or {}).get("comment") or "").strip() == str(marker)
            ]
            if by_marker:
                # Prefer marker-resolved live position ticket for ladder tracking.
                broker_ticket = int(max(int((r or {}).get("ticket") or 0) for r in by_marker))
            if broker_ticket > 0:
                self._register_confirmation_ladder(
                    chat_id=int(chat_id),
                    session_id=0,
                    symbol=str(symbol),
                    timeframe=str(timeframe),
                    direction=str(direction),
                    trade_id=0,
                    broker_ticket=int(broker_ticket),
                    stage_lots=list(stage_lots),
                    tps=list(active_tps),
                    source_tag=source_tag,
                    order_comment=str(marker),
                    source_key=str(audit_source_key),
                    source_name=str(audit_source_name),
                    profile=str(audit_profile),
                    indicator=str(audit_indicator),
                    execution_mode=exec_mode,
                    profit_lock_enabled=(bool(signal.get("profit_lock_enabled")) if signal.get("profit_lock_enabled") is not None else None),
                    profit_lock_retrace_pct=_to_float_or_none(signal.get("profit_lock_retrace_pct")),
                    profit_lock_arm_after_tp=int(_to_float_or_none(signal.get("profit_lock_arm_after_tp")) or 0),
                    profit_lock_min_peak_usd=_to_float_or_none(signal.get("profit_lock_min_peak_usd")),
                    profit_lock_min_hold_sec=_to_float_or_none(signal.get("profit_lock_min_hold_sec")),
                    profit_lock_min_close_usd=_to_float_or_none(signal.get("profit_lock_min_close_usd")),
                    entry_price=_to_float_or_none(signal.get("entry_mid")),
                    initial_stop_loss=_to_float_or_none(order_stop_loss),
                    no_stop_loss=bool(allow_no_sl),
                    extra_state=dict(extra_ladder_state or {}),
                    trace_id=str(trace_id),
                )
            if broker_ticket > 0:
                self._mark_indicator_recent_open(
                    source_tag=source_tag,
                    direction=direction,
                    ticket=int(broker_ticket),
                )
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="opened",
                symbol=symbol,
                timeframe=timeframe,
                direction=direction,
                lot=float((data or {}).get("lot_size") or lot),
                stop_loss=stop_loss,
                final_tp=take_profit,
                stages_total=len(tps_all),
                stages_opened=len(stage_lots),
                ticket=int(broker_ticket) if broker_ticket > 0 else None,
                message="order_opened",
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                opened_at=self._now_iso(),
                combo_key=self._build_execution_combo_key(
                    source_type=audit_source_type,
                    source_name=audit_source_name,
                    indicator=audit_indicator,
                    symbol=symbol,
                    timeframe=timeframe,
                ),
                execution_mode=exec_mode,
                order_number=(int(_to_float_or_none((data or {}).get("order")) or 0) or None),
                deal_number=(int(_to_float_or_none((data or {}).get("deal")) or 0) or None),
                trace_id=str(trace_id),
                stage="order_send",
                stage_status="opened",
                stage_payload={
                    "stage_mode": str(stage_mode),
                    "stage_lots": [float(x) for x in stage_lots],
                    "active_tps": [dict(x) for x in active_tps],
                },
            )
            if self._profile_requires_tp_progress_gate(signal_profile) and str(audit_source_key).strip():
                self._mark_reentry_signal_started(
                    source_key=str(audit_source_key),
                    signal=dict(signal),
                    profile=str(signal_profile),
                )
            stage_desc = " | ".join(
                (
                    f"TP{int((row or {}).get('index') or 0)}=RUNNER"
                    if _to_float_or_none((row or {}).get("price")) is None
                    else f"TP{int((row or {}).get('index') or 0)}={float((row or {}).get('price') or 0.0):.5f}"
                )
                for row in active_tps
            )
            lot_desc = " / ".join(f"{float(x):.4f}" for x in stage_lots)
            sl_text = "none (indicator mode)" if order_stop_loss is None else f"{float(order_stop_loss):.5f}"
            final_tp_text = "runner_only" if take_profit is None else f"{float(take_profit):.5f}"
            return (
                "Confirmation ladder executed\n"
                "Execution: standalone_mt5\n"
                f"Symbol: {str(symbol)} {str(timeframe)}\n"
                f"Direction: {str(direction)}\n"
                f"SL: {sl_text}\n"
                f"Final TP: {final_tp_text}\n"
                f"Lot: {float((data or {}).get('lot_size') or lot):.4f}\n"
                f"Stages: {int(len(stage_lots))}/{int(len(tps_all))}\n"
                f"Stage mode: {stage_mode}\n"
                f"Stage lots: {lot_desc}\n"
                f"Targets: {stage_desc}\n"
                f"Ticket: {int(broker_ticket)}"
            )
        except Exception as exc:
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="failed",
                symbol=symbol,
                timeframe=timeframe,
                direction=direction,
                lot=lot,
                stop_loss=stop_loss,
                final_tp=take_profit,
                stages_total=len(tps_all),
                message=f"{type(exc).__name__}: {str(exc)[:220]}",
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                execution_mode=exec_mode,
                trace_id=str(trace_id),
                stage="exception",
                stage_status="failed",
                error_code=type(exc).__name__.lower(),
            )
            return f"Confirmation trade failed: {type(exc).__name__}: {str(exc)[:220]}"

    def _execute_indicator_normal_signal(
        self,
        *,
        chat_id: int,
        symbol: str,
        timeframe: str,
        direction: str,
        lot: float,
        source_tag: Optional[str],
        audit_ctx: Optional[Dict[str, Any]] = None,
        comment_prefix: str = "mt",
        execution_mode: str = "normal",
    ) -> str:
        audit = dict(audit_ctx or {})
        audit_source_type = str(audit.get("source_type") or "mt_indicator").strip() or "mt_indicator"
        audit_source_name = str(audit.get("source_name") or "unknown").strip() or "unknown"
        audit_source_key = str(audit.get("source_key") or "").strip()
        audit_trigger = str(audit.get("trigger") or "indicator_signal").strip() or "indicator_signal"
        audit_profile = str(audit.get("profile") or "").strip().lower()
        audit_indicator = str(audit.get("indicator") or "").strip()
        audit_event_ts = audit.get("event_ts")
        exec_mode = str(execution_mode or "normal").strip().lower() or "normal"
        trace_id = str(audit.get("trace_id") or "").strip()

        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper() or "M5"
        side = str(direction or "").strip().upper()
        if not trace_id:
            trace_id = self._build_execution_trace_id(
                source_key=str(audit_source_key),
                symbol=str(sym),
                direction=str(side),
            )
        qty = float(max(0.01, min(100.0, float(_to_float_or_none(lot) or 0.01))))
        if side not in {"BUY", "SELL"} or not sym:
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="rejected",
                symbol=sym,
                timeframe=tf,
                direction=side,
                lot=qty,
                message="invalid_normal_signal_payload",
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                execution_mode=exec_mode,
                trace_id=str(trace_id),
            )
            return "Normal mode trade failed: invalid payload."

        svc = self._get_live_service()
        pref = re.sub(r"[^a-z0-9]", "", str(comment_prefix or "mt").strip().lower())[:8] or "mt"
        marker = f"{pref}{int(time.time() * 1000) % 10000000000:010d}"
        try:
            data = svc.place_market_order(
                symbol=str(sym),
                direction=str(side),
                lot_size=float(qty),
                stop_loss=None,
                take_profit=None,
                comment=str(marker),
            )
            if not bool((data or {}).get("ok")):
                err_txt = str((data or {}).get("error") or "order_failed")
                market_closed = self._is_market_closed_error(err_txt)
                self._append_automation_execution_log(
                    source_type=audit_source_type,
                    source_name=audit_source_name,
                    trigger=audit_trigger,
                    status=("deferred" if market_closed else "failed"),
                    symbol=sym,
                    timeframe=tf,
                    direction=side,
                    lot=qty,
                    message=("market_closed" if market_closed else err_txt),
                    profile=audit_profile,
                    indicator=audit_indicator,
                    source_tag=source_tag,
                    event_ts=audit_event_ts,
                    execution_mode=exec_mode,
                    trace_id=str(trace_id),
                )
                if market_closed:
                    return "Normal mode deferred: market closed."
                return f"Normal mode trade failed: {err_txt[:220]}"

            broker_ticket = int(_to_float_or_none((data or {}).get("position")) or 0)
            if broker_ticket <= 0:
                broker_ticket = int(_to_float_or_none((data or {}).get("order")) or 0)
            if broker_ticket <= 0:
                broker_ticket = int(_to_float_or_none((data or {}).get("deal")) or 0)
            try:
                rows = svc.get_open_positions(symbol=str(sym))
            except Exception:
                rows = []
            by_marker = [
                dict(r)
                for r in (rows or [])
                if str((r or {}).get("direction") or "").strip().upper() == str(side)
                and str((r or {}).get("comment") or "").strip() == str(marker)
            ]
            if by_marker:
                broker_ticket = int(max(int((r or {}).get("ticket") or 0) for r in by_marker))

            if broker_ticket > 0:
                self._register_confirmation_ladder(
                    chat_id=int(chat_id),
                    session_id=0,
                    symbol=str(sym),
                    timeframe=str(tf),
                    direction=str(side),
                    trade_id=0,
                    broker_ticket=int(broker_ticket),
                    stage_lots=[float(qty)],
                    tps=[{"index": 1, "price": 0.0}],
                    source_tag=source_tag,
                    order_comment=str(marker),
                    source_key=str(audit_source_key),
                    source_name=str(audit_source_name),
                    profile=str(audit_profile),
                    indicator=str(audit_indicator),
                    execution_mode=exec_mode,
                    entry_price=None,
                    initial_stop_loss=None,
                    no_stop_loss=True,
                    trace_id=str(trace_id),
                )
                self._mark_indicator_recent_open(
                    source_tag=source_tag,
                    direction=side,
                    ticket=int(broker_ticket),
                )
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="opened",
                symbol=sym,
                timeframe=tf,
                direction=side,
                lot=float((data or {}).get("lot_size") or qty),
                ticket=int(broker_ticket) if broker_ticket > 0 else None,
                message="order_opened",
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                opened_at=self._now_iso(),
                combo_key=self._build_execution_combo_key(
                    source_type=audit_source_type,
                    source_name=audit_source_name,
                    indicator=audit_indicator,
                    symbol=sym,
                    timeframe=tf,
                ),
                execution_mode=exec_mode,
                order_number=(int(_to_float_or_none((data or {}).get("order")) or 0) or None),
                deal_number=(int(_to_float_or_none((data or {}).get("deal")) or 0) or None),
                trace_id=str(trace_id),
            )
            return (
                "Normal mode order executed\n"
                "Execution: standalone_mt5\n"
                f"Symbol: {str(sym)} {str(tf)}\n"
                f"Direction: {str(side)}\n"
                "SL: none\n"
                "TP: none\n"
                f"Lot: {float((data or {}).get('lot_size') or qty):.4f}\n"
                f"Ticket: {int(broker_ticket)}"
            )
        except Exception as exc:
            self._append_automation_execution_log(
                source_type=audit_source_type,
                source_name=audit_source_name,
                trigger=audit_trigger,
                status="failed",
                symbol=sym,
                timeframe=tf,
                direction=side,
                lot=qty,
                message=f"{type(exc).__name__}: {str(exc)[:220]}",
                profile=audit_profile,
                indicator=audit_indicator,
                source_tag=source_tag,
                event_ts=audit_event_ts,
                execution_mode=exec_mode,
                trace_id=str(trace_id),
            )
            return f"Normal mode trade failed: {type(exc).__name__}: {str(exc)[:220]}"

    @staticmethod
    def _is_market_closed_error(err: Any) -> bool:
        txt = str(err or "").strip().upper()
        if not txt:
            return False
        if "MARKET_CLOSED" in txt:
            return True
        if "RETCODE_MARKET_CLOSED" in txt:
            return True
        if "10018" in txt:
            return True
        return ("MARKET CLOSED" in txt)

    @staticmethod
    def _is_invalid_stops_error(err: Any) -> bool:
        txt = str(err or "").strip().upper()
        if not txt:
            return False
        if "INVALID_STOPS" in txt:
            return True
        if "RETCODE_INVALID_STOPS" in txt:
            return True
        if "10016" in txt:
            return True
        return ("INVALID STOPS" in txt)

    @staticmethod
    def _normalize_price(price: float, digits: int) -> float:
        try:
            d = int(max(0, min(10, int(digits))))
        except Exception:
            d = 5
        return float(round(float(price), d))

    def _retry_order_for_invalid_tp_only(
        self,
        *,
        svc: LiveTradingService,
        symbol: str,
        direction: str,
        lot: float,
        take_profit: float,
        comment: str,
    ) -> Dict[str, Any]:
        try:
            info = svc.get_symbol_info(symbol=str(symbol))
        except Exception:
            info = {}
        resolved_symbol = str((info or {}).get("resolved_symbol") or symbol).strip() or str(symbol)
        digits = int((info or {}).get("digits") or 5)
        point = _to_float_or_none((info or {}).get("point")) or (0.01 if digits <= 2 else 0.0001)
        stops_pts = _to_float_or_none((info or {}).get("trade_stops_level")) or 0.0
        freeze_pts = _to_float_or_none((info or {}).get("trade_freeze_level")) or 0.0
        min_dist = float(max(stops_pts, freeze_pts, 10.0)) * float(point)

        try:
            tick = svc.get_symbol_tick(symbol=str(resolved_symbol), resolve_symbol=False)
        except Exception:
            tick = {}
        if not isinstance(tick, dict) or str((tick or {}).get("error") or "").strip():
            try:
                tick = svc.get_symbol_tick(symbol=str(symbol), resolve_symbol=True)
            except Exception:
                tick = {}
        ask = _to_float_or_none((tick or {}).get("ask"))
        bid = _to_float_or_none((tick or {}).get("bid"))
        last = _to_float_or_none((tick or {}).get("last"))
        entry = ask if str(direction).upper() == "BUY" else bid
        if entry is None:
            entry = last
        if entry is None:
            try:
                bars = svc.get_recent_candles(
                    symbol=str(resolved_symbol),
                    timeframe="M1",
                    count=1,
                    resolve_symbol=False,
                )
            except Exception:
                bars = []
            if isinstance(bars, list) and bars and isinstance(bars[-1], dict):
                entry = _to_float_or_none((bars[-1] or {}).get("close"))
        if entry is None or float(entry) <= 0.0:
            return {"ok": False, "error": "retry_entry_price_unavailable"}

        tp_dist = abs(float(take_profit) - float(entry))
        want = float(max(min_dist * 1.8, float(point) * 40.0))
        tp_dist = max(float(tp_dist), float(want))

        if str(direction).upper() == "BUY":
            tp2 = self._normalize_price(float(entry) + float(tp_dist), digits)
        else:
            tp2 = self._normalize_price(float(entry) - float(tp_dist), digits)

        try:
            return svc.place_market_order(
                symbol=str(resolved_symbol),
                direction=str(direction),
                lot_size=float(lot),
                stop_loss=None,
                take_profit=float(tp2),
                comment=str(comment),
            )
        except Exception as exc:
            return {"ok": False, "error": f"retry_exception:{type(exc).__name__}:{str(exc)[:180]}"}

    def _retry_order_for_invalid_stops(
        self,
        *,
        svc: LiveTradingService,
        symbol: str,
        direction: str,
        lot: float,
        stop_loss: float,
        take_profit: float,
        comment: str,
    ) -> Dict[str, Any]:
        try:
            info = svc.get_symbol_info(symbol=str(symbol))
        except Exception:
            info = {}
        resolved_symbol = str((info or {}).get("resolved_symbol") or symbol).strip() or str(symbol)
        digits = int((info or {}).get("digits") or 5)
        point = _to_float_or_none((info or {}).get("point")) or (0.01 if digits <= 2 else 0.0001)
        stops_pts = _to_float_or_none((info or {}).get("trade_stops_level")) or 0.0
        freeze_pts = _to_float_or_none((info or {}).get("trade_freeze_level")) or 0.0
        min_dist = float(max(stops_pts, freeze_pts, 10.0)) * float(point)

        try:
            tick = svc.get_symbol_tick(symbol=str(resolved_symbol), resolve_symbol=False)
        except Exception:
            tick = {}
        if not isinstance(tick, dict) or str((tick or {}).get("error") or "").strip():
            try:
                tick = svc.get_symbol_tick(symbol=str(symbol), resolve_symbol=True)
            except Exception:
                tick = {}
        ask = _to_float_or_none((tick or {}).get("ask"))
        bid = _to_float_or_none((tick or {}).get("bid"))
        last = _to_float_or_none((tick or {}).get("last"))
        entry = ask if str(direction).upper() == "BUY" else bid
        if entry is None:
            entry = last
        if entry is None:
            try:
                bars = svc.get_recent_candles(
                    symbol=str(resolved_symbol),
                    timeframe="M1",
                    count=1,
                    resolve_symbol=False,
                )
            except Exception:
                bars = []
            if isinstance(bars, list) and bars and isinstance(bars[-1], dict):
                entry = _to_float_or_none((bars[-1] or {}).get("close"))
        if entry is None:
            slf = _to_float_or_none(stop_loss)
            tpf = _to_float_or_none(take_profit)
            if slf is not None and tpf is not None and float(slf) > 0.0 and float(tpf) > 0.0:
                entry = float(slf + tpf) * 0.5
        if entry is None or float(entry) <= 0.0:
            return {"ok": False, "error": "retry_entry_price_unavailable"}

        sl_dist = abs(float(entry) - float(stop_loss))
        tp_dist = abs(float(take_profit) - float(entry))
        want = float(max(min_dist * 1.5, float(point) * 30.0))
        sl_dist = max(float(sl_dist), float(want))
        tp_dist = max(float(tp_dist), float(want))

        if str(direction).upper() == "BUY":
            sl2 = self._normalize_price(float(entry) - float(sl_dist), digits)
            tp2 = self._normalize_price(float(entry) + float(tp_dist), digits)
        else:
            sl2 = self._normalize_price(float(entry) + float(sl_dist), digits)
            tp2 = self._normalize_price(float(entry) - float(tp_dist), digits)

        try:
            return svc.place_market_order(
                symbol=str(resolved_symbol),
                direction=str(direction),
                lot_size=float(lot),
                stop_loss=float(sl2),
                take_profit=float(tp2),
                comment=str(comment),
            )
        except Exception as exc:
            return {"ok": False, "error": f"retry_exception:{type(exc).__name__}:{str(exc)[:180]}"}

    @staticmethod
    def _confirm_profit_lock_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_PROFIT_LOCK_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _confirm_profit_lock_retrace_pct() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_PROFIT_LOCK_RETRACE_PCT", "0.40"))
        except Exception:
            raw = 0.40
        if not math.isfinite(float(raw)):
            raw = 0.40
        return max(0.05, min(0.95, float(raw)))

    @staticmethod
    def _confirm_profit_lock_arm_after_tp() -> int:
        try:
            raw = int(float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_PROFIT_LOCK_ARM_AFTER_TP", "2")))
        except Exception:
            raw = 2
        return max(1, min(10, int(raw)))

    @staticmethod
    def _confirm_profit_lock_min_peak_usd() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_PROFIT_LOCK_MIN_PEAK_USD", "0.0"))
        except Exception:
            raw = 0.0
        if not math.isfinite(float(raw)):
            raw = 0.0
        return max(0.0, min(1000000.0, float(raw)))

    @staticmethod
    def _confirm_profit_lock_min_hold_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_PROFIT_LOCK_MIN_HOLD_SEC", "0.0"))
        except Exception:
            raw = 0.0
        if not math.isfinite(float(raw)):
            raw = 0.0
        return max(0.0, min(86400.0, float(raw)))

    @staticmethod
    def _confirm_profit_lock_min_close_usd() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_PROFIT_LOCK_MIN_CLOSE_USD", "0.0"))
        except Exception:
            raw = 0.0
        if not math.isfinite(float(raw)):
            raw = 0.0
        return max(0.0, min(1000000.0, float(raw)))

    @staticmethod
    def _confirm_ladder_missing_retries() -> int:
        try:
            raw = int(float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_LADDER_MISSING_RETRIES", "4")))
        except Exception:
            raw = 4
        return int(max(1, min(30, int(raw))))

    @staticmethod
    def _confirm_ladder_missing_grace_sec() -> float:
        try:
            raw = float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_LADDER_MISSING_GRACE_SEC", "8.0"))
        except Exception:
            raw = 8.0
        if not math.isfinite(float(raw)):
            raw = 8.0
        return float(max(0.0, min(300.0, float(raw))))

    @staticmethod
    def _confirm_sl_guard_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SL_GUARD_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _confirm_sl_guard_start_tp() -> int:
        try:
            raw = int(float(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SL_GUARD_START_TP", "1")))
        except Exception:
            raw = 1
        return max(1, min(5, int(raw)))

    @staticmethod
    def _confirm_sl_guard_lock_ratios() -> List[float]:
        raw = str(TelegramBridgeService._get_env_value("TELEGRAM_CONFIRM_SL_GUARD_LOCK_RATIOS", "")).strip()
        parsed: List[float] = []
        if raw:
            for tok in re.split(r"[,\|; ]+", raw):
                t = str(tok or "").strip()
                if not t:
                    continue
                try:
                    v = float(t)
                except Exception:
                    continue
                if not math.isfinite(float(v)):
                    continue
                parsed.append(max(0.0, min(0.99, float(v))))
        if not parsed:
            parsed = [0.00, 0.35, 0.55, 0.72, 0.85]
        while len(parsed) < 5:
            parsed.append(float(parsed[-1]))
        return [float(x) for x in parsed[:5]]

    def _apply_confirmation_guard_stop(
        self,
        *,
        svc: LiveTradingService,
        row: Dict[str, Any],
        pos: Dict[str, Any],
        hit_tp_index: int,
        target_px: float,
    ) -> Dict[str, Any]:
        if not bool(self._confirm_sl_guard_enabled()):
            return {"ok": True, "updated": False, "reason": "sl_guard_disabled"}
        tp_idx = int(max(1, int(hit_tp_index or 1)))
        if tp_idx < int(self._confirm_sl_guard_start_tp()):
            return {"ok": True, "updated": False, "reason": "sl_guard_not_armed"}

        sym = str((row or {}).get("symbol") or "").strip().upper()
        direction = str((row or {}).get("direction") or "").strip().upper()
        ticket = int(_to_float_or_none((row or {}).get("broker_ticket")) or 0)
        if not sym or direction not in {"BUY", "SELL"} or ticket <= 0:
            return {"ok": False, "updated": False, "error": "invalid_ladder_row"}

        entry = _to_float_or_none((pos or {}).get("entry_price"))
        if entry is None:
            entry = _to_float_or_none((row or {}).get("entry_price"))
        if entry is None or float(entry) <= 0.0:
            return {"ok": False, "updated": False, "error": "entry_price_unavailable"}

        exec_mode = str((row or {}).get("execution_mode") or "").strip().lower()
        is_v2 = str(exec_mode) == "advanced_v2"

        info: Dict[str, Any] = {}
        try:
            info = dict(svc.get_symbol_info(symbol=str(sym)) or {})
        except Exception:
            info = {}
        digits = int(_to_float_or_none(info.get("digits")) or 5)
        point = _to_float_or_none(info.get("point")) or (0.0001 if digits >= 3 else 0.01)
        stops_points = _to_float_or_none(info.get("trade_stops_level")) or 0.0
        freeze_points = _to_float_or_none(info.get("trade_freeze_level")) or 0.0
        min_stop_dist = float(max(0.0, float(stops_points + freeze_points) * float(point)))

        if bool(is_v2):
            v2_cfg = dict((row or {}).get("advanced_v2_cfg") or {})
            r_dist = _to_float_or_none(v2_cfg.get("r_distance"))
            if r_dist is None or float(r_dist) <= 0.0:
                r_dist = abs(float(target_px) - float(entry))
            r_dist = float(max(float(r_dist or 0.0), float(point) * 10.0))
            slip_pct = _to_float_or_none(v2_cfg.get("slippage_buffer_pct"))
            slip_pct = float(slip_pct) if (slip_pct is not None and math.isfinite(float(slip_pct))) else 0.0008
            # TP1 -> BE(+buffer), TP2 -> +0.5R, TP3 -> +1R, TP4 no fixed SL move
            if int(tp_idx) == 1:
                be_off = float(max(float(point) * 2.0, abs(float(entry)) * float(slip_pct) * 0.5))
                desired = float(entry + (be_off if direction == "BUY" else -be_off))
            elif int(tp_idx) == 2:
                desired = float(entry + ((0.5 * float(r_dist)) if direction == "BUY" else (-0.5 * float(r_dist))))
            elif int(tp_idx) == 3:
                desired = float(entry + ((1.0 * float(r_dist)) if direction == "BUY" else (-1.0 * float(r_dist))))
            else:
                return {"ok": True, "updated": False, "reason": "v2_runner_no_fixed_sl_move"}

            existing_internal = _to_float_or_none(v2_cfg.get("internal_sl"))
            if existing_internal is not None:
                if direction == "BUY":
                    desired = max(float(desired), float(existing_internal))
                else:
                    desired = min(float(desired), float(existing_internal))
            if not math.isfinite(float(desired)) or float(desired) <= 0.0:
                return {"ok": False, "updated": False, "error": "invalid_v2_internal_sl"}
            desired = round(float(desired), int(max(0, digits)))
            if existing_internal is not None and abs(float(desired) - float(existing_internal)) < max(float(point), 1e-9):
                return {"ok": True, "updated": False, "reason": "v2_internal_sl_unchanged", "stop_loss": float(existing_internal)}

            raw_visible = float(desired + ((abs(float(entry)) * float(slip_pct)) if direction == "BUY" else (-abs(float(entry)) * float(slip_pct))))
            raw_visible = round(float(raw_visible), int(max(0, digits)))
            v2_cfg["internal_sl"] = float(desired)
            v2_cfg["raw_sl"] = float(raw_visible)
            row["advanced_v2_cfg"] = dict(v2_cfg)
            row["last_sl_update_tp_index"] = int(tp_idx)
            row["last_applied_sl"] = float(desired)
            self._append_automation_execution_log(
                source_type=self._source_type_from_source_tag((row or {}).get("source_tag")),
                source_name=str((row or {}).get("source_name") or "unknown"),
                trigger="sl_guard_update",
                status="success",
                symbol=str(sym),
                timeframe=str((row or {}).get("timeframe") or ""),
                direction=str(direction),
                ticket=int(ticket),
                message=f"sl_moved_tp{int(tp_idx)}:{float(desired):.5f}",
                profile=str((row or {}).get("profile") or "").strip().lower(),
                indicator=str((row or {}).get("indicator") or "").strip(),
                source_tag=str((row or {}).get("source_tag") or "").strip().lower(),
                max_profit=_to_float_or_none((row or {}).get("max_profit")),
                max_loss=_to_float_or_none((row or {}).get("max_loss")),
                execution_mode=str((row or {}).get("execution_mode") or "").strip().lower() or None,
                trace_id=str((row or {}).get("trace_id") or "").strip() or None,
                stage="sl_update",
                stage_status="success",
            )
            return {"ok": True, "updated": True, "stop_loss": float(desired), "raw_sl": float(raw_visible)}
        else:
            ratios = list(self._confirm_sl_guard_lock_ratios())
            ratio = float(ratios[min(len(ratios) - 1, max(0, tp_idx - 1))])
            be_buffer = float(max(float(point) * 4.0, float(min_stop_dist) * 0.20))
            profit_span = abs(float(target_px) - float(entry))
            lock_dist = float(max(float(be_buffer), float(profit_span) * float(ratio)))
            desired = (float(entry) + float(lock_dist)) if direction == "BUY" else (float(entry) - float(lock_dist))

        tick: Dict[str, Any] = {}
        try:
            tick = dict(svc.get_symbol_tick(symbol=str(sym), resolve_symbol=False) or {})
        except Exception:
            tick = {}
        bid = _to_float_or_none(tick.get("bid"))
        ask = _to_float_or_none(tick.get("ask"))
        market_px = _to_float_or_none((pos or {}).get("current_price"))
        if direction == "BUY":
            ref = bid if bid is not None else market_px
            if ref is not None and float(ref) > 0.0:
                desired = min(float(desired), float(ref) - max(float(min_stop_dist), float(point) * 2.0))
        else:
            ref = ask if ask is not None else market_px
            if ref is not None and float(ref) > 0.0:
                desired = max(float(desired), float(ref) + max(float(min_stop_dist), float(point) * 2.0))

        existing_sl = _to_float_or_none((pos or {}).get("stop_loss"))
        if existing_sl is not None and float(existing_sl) > 0.0:
            if direction == "BUY":
                desired = max(float(desired), float(existing_sl))
            else:
                desired = min(float(desired), float(existing_sl))

        if not math.isfinite(float(desired)) or float(desired) <= 0.0:
            return {"ok": False, "updated": False, "error": "invalid_sl_target"}
        desired = round(float(desired), int(max(0, digits)))

        if existing_sl is not None and abs(float(desired) - float(existing_sl)) < max(float(point), 1e-9):
            return {"ok": True, "updated": False, "reason": "sl_unchanged", "stop_loss": float(existing_sl)}

        out = svc.modify_position_sl_tp(
            symbol=str(sym),
            position_ticket=int(ticket),
            stop_loss=float(desired),
            take_profit=_to_float_or_none((pos or {}).get("take_profit")),
            comment=f"tg_sl_tp{int(tp_idx)}",
        )
        if bool((out or {}).get("ok")):
            row["last_sl_update_tp_index"] = int(tp_idx)
            row["last_applied_sl"] = float(desired)
            self._append_automation_execution_log(
                source_type=self._source_type_from_source_tag((row or {}).get("source_tag")),
                source_name=str((row or {}).get("source_name") or "unknown"),
                trigger="sl_guard_update",
                status="success",
                symbol=str(sym),
                timeframe=str((row or {}).get("timeframe") or ""),
                direction=str(direction),
                ticket=int(ticket),
                message=f"sl_moved_tp{int(tp_idx)}:{float(desired):.5f}",
                profile=str((row or {}).get("profile") or "").strip().lower(),
                indicator=str((row or {}).get("indicator") or "").strip(),
                source_tag=str((row or {}).get("source_tag") or "").strip().lower(),
                max_profit=_to_float_or_none((row or {}).get("max_profit")),
                max_loss=_to_float_or_none((row or {}).get("max_loss")),
                execution_mode=str((row or {}).get("execution_mode") or "").strip().lower() or None,
                trace_id=str((row or {}).get("trace_id") or "").strip() or None,
                stage="sl_update",
                stage_status="success",
            )
            return {"ok": True, "updated": True, "stop_loss": float(desired)}

        err_txt = str((out or {}).get("error") or "modify_failed")[:180]
        self._append_automation_execution_log(
            source_type=self._source_type_from_source_tag((row or {}).get("source_tag")),
            source_name=str((row or {}).get("source_name") or "unknown"),
            trigger="sl_guard_update",
            status="failed",
            symbol=str(sym),
            timeframe=str((row or {}).get("timeframe") or ""),
            direction=str(direction),
            ticket=int(ticket),
            message=f"sl_move_failed_tp{int(tp_idx)}:{err_txt}",
            profile=str((row or {}).get("profile") or "").strip().lower(),
            indicator=str((row or {}).get("indicator") or "").strip(),
            source_tag=str((row or {}).get("source_tag") or "").strip().lower(),
            max_profit=_to_float_or_none((row or {}).get("max_profit")),
            max_loss=_to_float_or_none((row or {}).get("max_loss")),
            execution_mode=str((row or {}).get("execution_mode") or "").strip().lower() or None,
            trace_id=str((row or {}).get("trace_id") or "").strip() or None,
            stage="sl_update",
            stage_status="success",
        )
        return {"ok": False, "updated": False, "error": err_txt}

    def _apply_confirmation_dynamic_stop(
        self,
        *,
        svc: LiveTradingService,
        row: Dict[str, Any],
        pos: Dict[str, Any],
        desired_stop: float,
        reason_tag: str,
    ) -> Dict[str, Any]:
        sym = str((row or {}).get("symbol") or "").strip().upper()
        direction = str((row or {}).get("direction") or "").strip().upper()
        ticket = int(_to_float_or_none((row or {}).get("broker_ticket")) or 0)
        if not sym or direction not in {"BUY", "SELL"} or ticket <= 0:
            return {"ok": False, "updated": False, "error": "invalid_ladder_row"}
        info: Dict[str, Any] = {}
        try:
            info = dict(svc.get_symbol_info(symbol=str(sym)) or {})
        except Exception:
            info = {}
        digits = int(_to_float_or_none(info.get("digits")) or 5)
        point = _to_float_or_none(info.get("point")) or (0.0001 if digits >= 3 else 0.01)
        stops_points = _to_float_or_none(info.get("trade_stops_level")) or 0.0
        freeze_points = _to_float_or_none(info.get("trade_freeze_level")) or 0.0
        min_stop_dist = float(max(0.0, float(stops_points + freeze_points) * float(point)))
        desired = _to_float_or_none(desired_stop)
        if desired is None or (not math.isfinite(float(desired))) or float(desired) <= 0.0:
            return {"ok": False, "updated": False, "error": "invalid_dynamic_sl"}
        tick: Dict[str, Any] = {}
        try:
            tick = dict(svc.get_symbol_tick(symbol=str(sym), resolve_symbol=False) or {})
        except Exception:
            tick = {}
        bid = _to_float_or_none(tick.get("bid"))
        ask = _to_float_or_none(tick.get("ask"))
        market_px = _to_float_or_none((pos or {}).get("current_price"))
        if direction == "BUY":
            ref = bid if bid is not None else market_px
            if ref is not None and float(ref) > 0.0:
                desired = min(float(desired), float(ref) - max(float(min_stop_dist), float(point) * 2.0))
        else:
            ref = ask if ask is not None else market_px
            if ref is not None and float(ref) > 0.0:
                desired = max(float(desired), float(ref) + max(float(min_stop_dist), float(point) * 2.0))
        existing_sl = _to_float_or_none((pos or {}).get("stop_loss"))
        if existing_sl is not None and float(existing_sl) > 0.0:
            if direction == "BUY":
                desired = max(float(desired), float(existing_sl))
            else:
                desired = min(float(desired), float(existing_sl))
        desired = round(float(desired), int(max(0, digits)))
        if existing_sl is not None and abs(float(desired) - float(existing_sl)) < max(float(point), 1e-9):
            return {"ok": True, "updated": False, "reason": "sl_unchanged", "stop_loss": float(existing_sl)}
        out = svc.modify_position_sl_tp(
            symbol=str(sym),
            position_ticket=int(ticket),
            stop_loss=float(desired),
            take_profit=_to_float_or_none((pos or {}).get("take_profit")),
            comment=f"tg_{str(reason_tag or 'dynamic_sl')[:24]}",
        )
        if bool((out or {}).get("ok")):
            row["last_applied_sl"] = float(desired)
            self._append_automation_execution_log(
                source_type=self._source_type_from_source_tag((row or {}).get("source_tag")),
                source_name=str((row or {}).get("source_name") or "unknown"),
                trigger="sl_guard_update",
                status="success",
                symbol=str(sym),
                timeframe=str((row or {}).get("timeframe") or ""),
                direction=str(direction),
                ticket=int(ticket),
                message=f"{str(reason_tag)}:{float(desired):.5f}",
                profile=str((row or {}).get("profile") or "").strip().lower(),
                indicator=str((row or {}).get("indicator") or "").strip(),
                source_tag=str((row or {}).get("source_tag") or "").strip().lower(),
                max_profit=_to_float_or_none((row or {}).get("max_profit")),
                max_loss=_to_float_or_none((row or {}).get("max_loss")),
                execution_mode=str((row or {}).get("execution_mode") or "").strip().lower() or None,
                trace_id=str((row or {}).get("trace_id") or "").strip() or None,
                stage="sl_update",
                stage_status="success",
            )
            return {"ok": True, "updated": True, "stop_loss": float(desired)}
        return {"ok": False, "updated": False, "error": str((out or {}).get("error") or "modify_failed")[:180]}

    def _update_advanced_v2_runner_stop(
        self,
        *,
        svc: LiveTradingService,
        row: Dict[str, Any],
        pos: Dict[str, Any],
    ) -> Dict[str, Any]:
        direction = str((row or {}).get("direction") or "").strip().upper()
        if direction not in {"BUY", "SELL"}:
            return {"ok": False, "updated": False, "error": "invalid_direction"}
        next_idx = int(_to_float_or_none((row or {}).get("next_tp_index")) or 1)
        # Runner trailing after TP3.
        if int(next_idx) < 4:
            return {"ok": True, "updated": False, "reason": "runner_not_armed"}
        sym = str((row or {}).get("symbol") or "").strip().upper()
        tf = str((row or {}).get("timeframe") or "M5").strip().upper() or "M5"
        bars = svc.get_recent_candles(symbol=str(sym), timeframe=str(tf), count=80, resolve_symbol=False)
        atr_now = _to_float_or_none(self._calc_robust_atr_from_bars(bars, period=14))
        if atr_now is None or float(atr_now) <= 0.0:
            return {"ok": False, "updated": False, "error": "atr_unavailable"}
        atr_20 = _to_float_or_none(self._calc_robust_atr_from_bars(bars, period=20))
        adx = _to_float_or_none(self._calc_adx_from_bars(bars, period=14))
        bb_width = _to_float_or_none(self._calc_bb_width_from_bars(bars, period=20, stdev_mult=2.0))
        cfg = dict((row or {}).get("advanced_v2_cfg") or {})
        trail_atr_mult = _to_float_or_none(cfg.get("trail_atr_mult"))
        trail_chandelier = _to_float_or_none(cfg.get("trail_chandelier"))
        trail_widen_adx = _to_float_or_none(cfg.get("trail_widen_adx"))
        slip_pct = _to_float_or_none(cfg.get("slippage_buffer_pct"))
        slip_pct = float(slip_pct) if (slip_pct is not None and math.isfinite(float(slip_pct))) else 0.0008
        mult = float(trail_atr_mult) if trail_atr_mult is not None else 1.5
        if adx is not None and float(adx) >= float(trail_widen_adx if trail_widen_adx is not None else 40.0):
            mult = float(trail_chandelier) if trail_chandelier is not None else 2.0
        current_price = _to_float_or_none((pos or {}).get("current_price"))
        if current_price is None or float(current_price) <= 0.0:
            return {"ok": False, "updated": False, "error": "current_price_unavailable"}
        if direction == "BUY":
            desired = float(current_price) - float(mult) * float(atr_now)
        else:
            desired = float(current_price) + float(mult) * float(atr_now)
        info: Dict[str, Any] = {}
        try:
            info = dict(svc.get_symbol_info(symbol=str(sym)) or {})
        except Exception:
            info = {}
        digits = int(_to_float_or_none(info.get("digits")) or 5)
        point = _to_float_or_none(info.get("point")) or (0.0001 if digits >= 3 else 0.01)
        desired = round(float(desired), int(max(0, digits)))
        existing_internal = _to_float_or_none(cfg.get("internal_sl"))
        if existing_internal is not None:
            if direction == "BUY":
                desired = max(float(desired), float(existing_internal))
            else:
                desired = min(float(desired), float(existing_internal))
        if existing_internal is not None and abs(float(desired) - float(existing_internal)) < max(float(point), 1e-9):
            return {"ok": True, "updated": False, "reason": "v2_internal_sl_unchanged"}
        cfg["internal_sl"] = float(desired)
        # Keep a visible/raw counterpart for audit readability.
        entry = _to_float_or_none((pos or {}).get("entry_price"))
        if entry is None or float(entry) <= 0.0:
            entry = _to_float_or_none((row or {}).get("entry_price"))
        if entry is not None and float(entry) > 0.0:
            raw_visible = float(desired + ((abs(float(entry)) * float(slip_pct)) if direction == "BUY" else (-abs(float(entry)) * float(slip_pct))))
            cfg["raw_sl"] = round(float(raw_visible), int(max(0, digits)))
        row["advanced_v2_cfg"] = dict(cfg)
        row["last_applied_sl"] = float(desired)
        self._append_automation_execution_log(
            source_type=self._source_type_from_source_tag((row or {}).get("source_tag")),
            source_name=str((row or {}).get("source_name") or "unknown"),
            trigger="sl_guard_update",
            status="success",
            symbol=str(sym),
            timeframe=str((row or {}).get("timeframe") or ""),
            direction=str(direction),
            ticket=int(_to_float_or_none((row or {}).get("broker_ticket")) or 0),
            message=f"sl_trail_v2_tp{int(next_idx)}:{float(desired):.5f}",
            profile=str((row or {}).get("profile") or "").strip().lower(),
            indicator=str((row or {}).get("indicator") or "").strip(),
            source_tag=str((row or {}).get("source_tag") or "").strip().lower(),
            max_profit=_to_float_or_none((row or {}).get("max_profit")),
            max_loss=_to_float_or_none((row or {}).get("max_loss")),
            execution_mode=str((row or {}).get("execution_mode") or "").strip().lower() or None,
            trace_id=str((row or {}).get("trace_id") or "").strip() or None,
            stage="sl_update",
            stage_status="failed",
        )
        return {"ok": True, "updated": True, "stop_loss": float(desired)}

    def _push_confirmation_signal_ladders(self) -> None:
        with self._lock:
            ladders = {str(k): dict(v) for k, v in self._active_confirmation_signal_ladders.items()}
        if not ladders:
            return
        svc = self._get_live_service()
        profit_lock_enabled = bool(self._confirm_profit_lock_enabled())
        profit_lock_retrace = float(self._confirm_profit_lock_retrace_pct())
        profit_lock_arm_after_tp = int(self._confirm_profit_lock_arm_after_tp())
        profit_lock_min_peak = float(self._confirm_profit_lock_min_peak_usd())
        profit_lock_min_hold = float(self._confirm_profit_lock_min_hold_sec())
        profit_lock_min_close = float(self._confirm_profit_lock_min_close_usd())
        missing_retries = int(self._confirm_ladder_missing_retries())
        missing_grace_sec = float(self._confirm_ladder_missing_grace_sec())
        remove_keys: List[str] = []
        for key, row in ladders.items():
            sym = str(row.get("symbol") or "").strip().upper()
            ticket = int(row.get("broker_ticket") or 0)
            direction = str(row.get("direction") or "").strip().upper()
            execution_mode = str(row.get("execution_mode") or "advanced").strip().lower() or "advanced"
            next_idx = int(row.get("next_tp_index") or 1)
            tps = row.get("tps") if isinstance(row.get("tps"), list) else []
            stage_lots = row.get("stage_lots") if isinstance(row.get("stage_lots"), list) else []
            if not sym or ticket <= 0 or direction not in {"BUY", "SELL"}:
                remove_keys.append(str(key))
                continue
            if execution_mode != "normal" and (next_idx <= 0 or next_idx > len(tps)):
                remove_keys.append(str(key))
                continue
            try:
                rows = svc.get_open_positions(symbol=str(sym))
            except Exception:
                rows = []
            pos = next((dict(r) for r in rows if int((r or {}).get("ticket") or 0) == int(ticket)), None)
            if not isinstance(pos, dict):
                miss_count = int(_to_float_or_none(row.get("missing_seen_count")) or 0) + 1
                first_miss_ts = _to_float_or_none(row.get("missing_first_ts"))
                if first_miss_ts is None or float(first_miss_ts) <= 0.0:
                    first_miss_ts = float(time.time())
                row["missing_seen_count"] = int(miss_count)
                row["missing_first_ts"] = float(first_miss_ts)
                miss_elapsed = float(max(0.0, float(time.time()) - float(first_miss_ts)))
                if int(miss_count) >= int(missing_retries) and float(miss_elapsed) >= float(missing_grace_sec):
                    self._append_closed_execution_log_from_row(
                        row=dict(row),
                        reason="position_closed_or_stopped",
                        svc=svc,
                    )
                    remove_keys.append(str(key))
                else:
                    with self._lock:
                        self._active_confirmation_signal_ladders[str(key)] = dict(row)
                continue
            row["missing_seen_count"] = 0
            row["missing_first_ts"] = None
            cur_profit = _to_float_or_none(pos.get("profit_loss"))
            if cur_profit is not None:
                prev_max = _to_float_or_none(row.get("max_profit"))
                prev_min = _to_float_or_none(row.get("max_loss"))
                row["max_profit"] = float(cur_profit) if (prev_max is None or float(cur_profit) > float(prev_max)) else float(prev_max)
                row["max_loss"] = float(cur_profit) if (prev_min is None or float(cur_profit) < float(prev_min)) else float(prev_min)
            if execution_mode in {"normal", "sync"}:
                with self._lock:
                    self._active_confirmation_signal_ladders[str(key)] = dict(row)
                continue
            current_price = _to_float_or_none(pos.get("current_price"))
            close_ref_price = self._position_close_ref_price(
                svc=svc,
                symbol=str(sym),
                direction=str(direction),
                pos=dict(pos),
            )
            if close_ref_price is None:
                close_ref_price = current_price
            target_row = dict(tps[next_idx - 1]) if (next_idx - 1) < len(tps) else {}
            target_px = _to_float_or_none(target_row.get("price"))
            if close_ref_price is None:
                with self._lock:
                    self._active_confirmation_signal_ladders[str(key)] = dict(row)
                continue
            if execution_mode == "advanced_v2":
                v2_cfg = dict((row or {}).get("advanced_v2_cfg") or {})
                internal_sl = _to_float_or_none(v2_cfg.get("internal_sl"))
                if internal_sl is not None:
                    sl_hit = bool(float(close_ref_price) < float(internal_sl)) if direction == "BUY" else bool(float(close_ref_price) > float(internal_sl))
                    if bool(sl_hit):
                        close_out = svc.close_position(
                            symbol=str(sym),
                            position_ticket=int(ticket),
                            comment="tg_sl_v2",
                        )
                        if bool((close_out or {}).get("ok")):
                            self._append_closed_execution_log_from_row(
                                row=dict(row),
                                reason="sl_hit_v2",
                                svc=svc,
                            )
                            remove_keys.append(str(key))
                            continue
            if target_px is None:
                if execution_mode == "advanced_v2":
                    _ = self._update_advanced_v2_runner_stop(
                        svc=svc,
                        row=row,
                        pos=pos,
                    )
                with self._lock:
                    self._active_confirmation_signal_ladders[str(key)] = dict(row)
                continue
            hit = bool(float(close_ref_price) >= float(target_px)) if direction == "BUY" else bool(float(close_ref_price) <= float(target_px))
            if not hit:
                if execution_mode == "advanced_v2":
                    _ = self._update_advanced_v2_runner_stop(
                        svc=svc,
                        row=row,
                        pos=pos,
                    )
                    with self._lock:
                        self._active_confirmation_signal_ladders[str(key)] = dict(row)
                    continue
                # Profit-lock: after configured TP stage, if live PnL retraces from peak by pct, close full.
                row_profit_lock_enabled = (row.get("profit_lock_enabled") if "profit_lock_enabled" in row else None)
                effective_profit_lock_enabled = bool(profit_lock_enabled) if row_profit_lock_enabled is None else bool(row_profit_lock_enabled)
                if effective_profit_lock_enabled and cur_profit is not None and float(cur_profit) > 0.0:
                    row_retrace = _to_float_or_none(row.get("profit_lock_retrace_pct"))
                    row_arm_after_tp = int(_to_float_or_none(row.get("profit_lock_arm_after_tp")) or 0)
                    row_min_peak = _to_float_or_none(row.get("profit_lock_min_peak_usd"))
                    row_min_hold = _to_float_or_none(row.get("profit_lock_min_hold_sec"))
                    row_min_close = _to_float_or_none(row.get("profit_lock_min_close_usd"))
                    effective_retrace = float(row_retrace) if row_retrace is not None else float(profit_lock_retrace)
                    effective_retrace = max(0.05, min(0.95, float(effective_retrace)))
                    effective_arm_after_tp = int(row_arm_after_tp) if int(row_arm_after_tp) > 0 else int(profit_lock_arm_after_tp)
                    effective_min_peak = float(row_min_peak) if row_min_peak is not None else float(profit_lock_min_peak)
                    effective_min_peak = max(0.0, min(1000000.0, float(effective_min_peak)))
                    effective_min_hold = float(row_min_hold) if row_min_hold is not None else float(profit_lock_min_hold)
                    effective_min_hold = max(0.0, min(86400.0, float(effective_min_hold)))
                    effective_min_close = float(row_min_close) if row_min_close is not None else float(profit_lock_min_close)
                    effective_min_close = max(0.0, min(1000000.0, float(effective_min_close)))
                    current_stage_hit = int(max(0, int(next_idx) - 1))
                    if current_stage_hit >= int(effective_arm_after_tp):
                        peak_profit = _to_float_or_none(row.get("peak_profit"))
                        if peak_profit is None or float(cur_profit) > float(peak_profit):
                            peak_profit = float(cur_profit)
                        row["peak_profit"] = float(peak_profit)
                        created_ts = _to_unix_or_none(row.get("created_at"))
                        held_sec = float(time.time() - float(created_ts)) if created_ts is not None else 0.0
                        hold_ok = float(held_sec) >= float(effective_min_hold)
                        peak_ok = float(peak_profit) >= float(effective_min_peak)
                        trigger_level = float(peak_profit) * float(1.0 - float(effective_retrace))
                        if hold_ok and peak_ok and float(cur_profit) <= float(trigger_level) and float(cur_profit) >= float(effective_min_close):
                            close_out = svc.close_position(
                                symbol=str(sym),
                                position_ticket=int(ticket),
                                comment="tg_profit_lock",
                            )
                            if bool((close_out or {}).get("ok")):
                                self._append_closed_execution_log_from_row(
                                    row=dict(row),
                                    reason="closed_by_profit_lock",
                                    svc=svc,
                                )
                                remove_keys.append(str(key))
                                continue
                with self._lock:
                    self._active_confirmation_signal_ladders[str(key)] = dict(row)
                continue
            is_final = bool(next_idx >= len(tps))
            if is_final:
                self._append_closed_execution_log_from_row(
                    row=dict(row),
                    reason="final_tp_reached",
                    svc=svc,
                )
                self._send_text(
                    int(row.get("chat_id") or 0),
                    (
                        f"Confirmation ladder final target reached\n"
                        f"{sym} {direction} | TP{int(next_idx)} @ {float(target_px):.5f}\n"
                        f"Ticket: #{int(ticket)}"
                    ),
                )
                remove_keys.append(str(key))
                continue
            close_lot = _to_float_or_none(stage_lots[next_idx - 1] if (next_idx - 1) < len(stage_lots) else None)
            if close_lot is None or close_lot <= 0.0:
                remove_keys.append(str(key))
                continue
            out = svc.close_position(
                symbol=str(sym),
                position_ticket=int(ticket),
                lot_size=float(close_lot),
                comment=f"tg_confirm_tp{int(next_idx)}",
            )
            if bool((out or {}).get("ok")):
                _ = self._apply_confirmation_guard_stop(
                    svc=svc,
                    row=row,
                    pos=pos,
                    hit_tp_index=int(next_idx),
                    target_px=float(target_px),
                )
                self._mark_reentry_progress_from_execution(
                    source_key=str(row.get("source_key") or ""),
                    symbol=str(sym),
                    direction=str(direction),
                    event_kind="tp_hit",
                )
                self._append_automation_execution_log(
                    source_type=self._source_type_from_source_tag(row.get("source_tag")),
                    source_name=str(row.get("source_name") or "unknown"),
                    trigger="tp_hit",
                    status="tp_partial",
                    symbol=str(sym),
                    timeframe=str(row.get("timeframe") or ""),
                    direction=str(direction),
                    lot=float(close_lot),
                    ticket=int(ticket),
                    message=f"tp{int(next_idx)}_partial_closed",
                    profile=str(row.get("profile") or "").strip().lower(),
                    indicator=str(row.get("indicator") or "").strip(),
                    source_tag=str(row.get("source_tag") or "").strip().lower(),
                    max_profit=_to_float_or_none(row.get("max_profit")),
                    max_loss=_to_float_or_none(row.get("max_loss")),
                    execution_mode=str(row.get("execution_mode") or "").strip().lower() or None,
                    trace_id=str(row.get("trace_id") or "").strip() or None,
                    stage="tp_partial",
                    stage_status="success",
                    stage_payload={
                        "tp_index": int(next_idx),
                        "tp_target": float(target_px),
                        "close_lot": float(close_lot),
                        "next_tp_index_after": int(next_idx + 1),
                    },
                )
                self._send_text(
                    int(row.get("chat_id") or 0),
                    (
                        f"Confirmation ladder partial TP done\n"
                        f"{sym} {direction} | TP{int(next_idx)} hit @ {float(target_px):.5f}\n"
                        f"Closed lot: {float(close_lot):.4f}\n"
                        f"Ticket: #{int(ticket)}"
                    ),
                )
                row["next_tp_index"] = int(next_idx + 1)
                with self._lock:
                    self._active_confirmation_signal_ladders[str(key)] = dict(row)
            else:
                self._append_automation_execution_log(
                    source_type=self._source_type_from_source_tag(row.get("source_tag")),
                    source_name=str(row.get("source_name") or "unknown"),
                    trigger="tp_hit",
                    status="failed",
                    symbol=str(sym),
                    timeframe=str(row.get("timeframe") or ""),
                    direction=str(direction),
                    lot=float(close_lot),
                    ticket=int(ticket),
                    message=f"tp{int(next_idx)}_partial_failed:{str((out or {}).get('error') or 'close_failed')[:160]}",
                    profile=str(row.get("profile") or "").strip().lower(),
                    indicator=str(row.get("indicator") or "").strip(),
                    source_tag=str(row.get("source_tag") or "").strip().lower(),
                    max_profit=_to_float_or_none(row.get("max_profit")),
                    max_loss=_to_float_or_none(row.get("max_loss")),
                    execution_mode=str(row.get("execution_mode") or "").strip().lower() or None,
                    trace_id=str(row.get("trace_id") or "").strip() or None,
                    stage="tp_partial",
                    stage_status="failed",
                    error_code="partial_close_failed",
                    stage_payload={
                        "tp_index": int(next_idx),
                        "tp_target": float(target_px),
                    },
                )
                self._send_text(
                    int(row.get("chat_id") or 0),
                    (
                        f"Confirmation ladder partial TP failed\n"
                        f"{sym} {direction} | TP{int(next_idx)}\n"
                        f"Error: {str((out or {}).get('error') or 'close_failed')[:180]}"
                    ),
                )
                remove_keys.append(str(key))
        if remove_keys:
            with self._lock:
                for key in remove_keys:
                    self._active_confirmation_signal_ladders.pop(str(key), None)

    def _handle_close_instruction_message(
        self,
        *,
        chat_id: int,
        source_label: str,
        text: str,
        event_ts: Optional[Any] = None,
    ) -> str:
        hint = self._parse_close_instruction_signal_hint(text)
        if not bool((hint or {}).get("is_close_instruction")):
            return "Close instruction ignored (not recognized)."
        source_key = self._confirm_signal_source_key(int(chat_id), str(source_label))
        hint_symbol = self._normalize_signal_symbol((hint or {}).get("symbol"))
        hint_side = str((hint or {}).get("direction") or "").strip().upper()

        with self._lock:
            rows = [(str(k), dict(v)) for k, v in self._active_confirmation_signal_ladders.items() if isinstance(v, dict)]
        if not rows:
            return "Close instruction received, but no active ladder position found."

        matches: List[Tuple[str, Dict[str, Any], float]] = []
        for k, row in rows:
            row_source_key = str(row.get("source_key") or "").strip()
            row_source_name = str(row.get("source_name") or "").strip()
            if row_source_key and row_source_key != source_key:
                continue
            if (not row_source_key) and (row_source_name and not self._source_matches_rule(row_source_name, source_label)):
                continue
            row_symbol = self._normalize_signal_symbol(row.get("symbol"))
            row_side = str(row.get("direction") or "").strip().upper()
            if hint_symbol and row_symbol != hint_symbol:
                continue
            if hint_side and row_side != hint_side:
                continue
            created_ts = _to_unix_or_none(row.get("created_at")) or 0.0
            matches.append((str(k), dict(row), float(created_ts)))

        if not matches:
            return (
                "Close instruction received, but no source-matching active position found.\n"
                f"Source: {str(source_label)}"
            )

        # Close the newest matching position for this source/symbol/direction.
        matches.sort(key=lambda x: float(x[2]), reverse=True)
        target_key, target_row, _ts = matches[0]
        ticket = int(target_row.get("broker_ticket") or 0)
        symbol = self._normalize_signal_symbol(target_row.get("symbol"))
        direction = str(target_row.get("direction") or "").strip().upper()
        if ticket <= 0 or not symbol:
            return "Close instruction received, but matching position metadata is invalid."

        svc = self._get_live_service()
        out = svc.close_position(
            symbol=str(symbol),
            position_ticket=int(ticket),
            comment="tg_close_instruction",
        )
        if not bool((out or {}).get("ok")):
            self._append_automation_execution_log(
                source_type="telegram_channel",
                source_name=str(source_label),
                trigger="close_instruction",
                status="failed",
                symbol=str(symbol),
                direction=str(direction),
                ticket=int(ticket),
                message=str((out or {}).get("error") or "close_failed")[:180],
                event_ts=event_ts,
                trace_id=str((target_row or {}).get("trace_id") or "").strip() or None,
                stage="close_instruction",
                stage_status="failed",
                error_code="close_failed",
            )
            return (
                "Close instruction failed\n"
                f"Source: {str(source_label)}\n"
                f"Symbol: {str(symbol)} {str(direction)}\n"
                f"Ticket: {int(ticket)}\n"
                f"Error: {str((out or {}).get('error') or 'close_failed')[:180]}"
            )

        with self._lock:
            self._active_confirmation_signal_ladders.pop(str(target_key), None)
        self._append_automation_execution_log(
            source_type="telegram_channel",
            source_name=str(source_label),
            trigger="close_instruction",
            status="closed",
            symbol=str(symbol),
            direction=str(direction),
            ticket=int(ticket),
            message="closed_by_channel_instruction",
            event_ts=event_ts,
            trace_id=str((target_row or {}).get("trace_id") or "").strip() or None,
            stage="close_instruction",
            stage_status="closed",
        )

        self._append_closed_execution_log_from_row(
            row=dict(target_row),
            reason="closed_by_channel_instruction",
            svc=svc,
            event_ts=event_ts,
        )
        return (
            "Close instruction executed\n"
            f"Source: {str(source_label)}\n"
            f"Symbol: {str(symbol)} {str(direction)}\n"
            f"Ticket: {int(ticket)}"
        )

    def _handle_confirmation_signal_message(
        self,
        *,
        chat_id: int,
        msg: Optional[Dict[str, Any]],
        chat: Optional[Dict[str, Any]],
        text: str,
        push_only: bool,
    ) -> Optional[str]:
        if not self._confirm_signal_enabled():
            return None
        source_names = self._extract_message_source_names(msg, chat)
        source_label = next((str(x) for x in source_names if str(x).strip()), "manual")
        source_ok = self._message_matches_confirm_signal_source(msg, chat)
        if not source_ok:
            chat_type = str((chat or {}).get("type") or "").strip().lower()
            if chat_type == "channel":
                return None
            allowed = self._allowed_chat_id()
            if int(chat_id) != int(allowed or 0):
                return None
            source_label = "manual paste"
        msg_kind = self._classify_confirm_signal_message_for_sources(text, source_names=source_names)
        parsed_for_feed = self._parse_confirmation_signal_for_sources(text, source_names=source_names) if msg_kind == "signal" else None
        self._append_confirm_signal_feed(
            source=str(source_label),
            chat=chat if isinstance(chat, dict) else {},
            text=str(text),
            kind=str(msg_kind),
            parsed=parsed_for_feed,
            event_ts=((msg or {}).get("date") if isinstance(msg, dict) else None),
            source_message_id=int(((msg or {}).get("message_id") if isinstance(msg, dict) else 0) or 0),
        )
        source_key = self._confirm_signal_source_key(int(chat_id), source_label)
        msg_event_ts = ((msg or {}).get("date") if isinstance(msg, dict) else None)
        if msg_kind in {"tp_hit", "sl_hit", "close_instruction"}:
            self._apply_reentry_progress_from_message(
                source_key=str(source_key),
                text=str(text),
                msg_kind=str(msg_kind),
            )
        require_confirm = self._confirm_signal_requires_confirm_for_sources(source_names)
        if msg_kind == "close_instruction":
            out = self._handle_close_instruction_message(
                chat_id=int(chat_id),
                source_label=str(source_label),
                text=str(text),
                event_ts=((msg or {}).get("date") if isinstance(msg, dict) else None),
            )
            if push_only:
                self._send_text(int(chat_id), out, reply_markup=None)
                return ""
            return out

        if require_confirm and self._is_confirm_signal_message(text):
            candidates: List[str] = []
            for name in source_names:
                key = self._confirm_signal_source_key(int(chat_id), name)
                if key not in candidates:
                    candidates.append(key)
            fallback_key = self._confirm_signal_source_key(int(chat_id), source_label)
            if fallback_key not in candidates:
                candidates.append(fallback_key)
            pending_key, pending_row = self._pick_pending_confirmation_signal(
                candidate_source_keys=list(candidates),
            )
            if not isinstance(pending_row, dict):
                self._append_automation_execution_log(
                    source_type="telegram_channel",
                    source_name=str(source_label),
                    trigger="confirm_signal_received",
                    status="ignored",
                    message="confirm_signal_no_pending",
                    event_ts=msg_event_ts,
                    stage="confirm",
                    stage_status="ignored",
                    error_code="pending_not_found",
                )
                out = "Confirm Signal received, but no pending confirmation signal was found."
                if push_only:
                    self._send_text(int(chat_id), out, reply_markup=None)
                    return ""
                return out
            created_ts = _to_float_or_none(pending_row.get("created_ts")) or 0.0
            if (time.time() - float(created_ts)) > float(self._confirm_signal_confirm_window_sec()):
                if pending_key:
                    with self._lock:
                        self._pending_confirmation_signals.pop(str(pending_key), None)
                self._append_automation_execution_log(
                    source_type="telegram_channel",
                    source_name=str(source_label),
                    trigger="confirm_signal_received",
                    status="expired",
                    symbol=str(((pending_row.get("signal") or {}).get("symbol") or "")).strip().upper(),
                    direction=str(((pending_row.get("signal") or {}).get("direction") or "")).strip().upper(),
                    message="confirm_signal_pending_expired",
                    event_ts=msg_event_ts,
                    trace_id=str(((pending_row.get("signal") or {}).get("trace_id") or "")).strip() or None,
                    stage="confirm",
                    stage_status="expired",
                    error_code="pending_expired",
                )
                out = "Confirm Signal received, but pending signal expired."
                if push_only:
                    self._send_text(int(chat_id), out, reply_markup=None)
                    return ""
                return out
            if pending_key:
                with self._lock:
                    self._pending_confirmation_signals.pop(str(pending_key), None)
            signal = pending_row.get("signal") if isinstance(pending_row.get("signal"), dict) else None
            if not isinstance(signal, dict):
                self._append_automation_execution_log(
                    source_type="telegram_channel",
                    source_name=str(source_label),
                    trigger="confirm_signal_received",
                    status="failed",
                    message="confirm_signal_invalid_pending_payload",
                    event_ts=msg_event_ts,
                    stage="confirm",
                    stage_status="failed",
                    error_code="invalid_pending_signal",
                )
                out = "Confirm Signal received, but pending signal payload is invalid."
                if push_only:
                    self._send_text(int(chat_id), out, reply_markup=None)
                    return ""
                return out
            self._append_automation_execution_log(
                source_type="telegram_channel",
                source_name=str(source_label),
                trigger="confirm_signal_received",
                status="dispatch",
                symbol=str(signal.get("symbol") or "").strip().upper(),
                timeframe=str(signal.get("timeframe") or self._confirm_signal_default_timeframe()).strip().upper(),
                direction=str(signal.get("direction") or "").strip().upper(),
                stop_loss=_to_float_or_none(signal.get("stop_loss")),
                stages_total=len(signal.get("tps") or []),
                message="confirm_signal_dispatch_execute",
                event_ts=msg_event_ts,
                trace_id=str(signal.get("trace_id") or "").strip() or None,
                stage="confirm",
                stage_status="dispatch",
            )
            exec_msg = self._execute_confirmation_signal_auto(
                chat_id=int(chat_id),
                signal=dict(signal),
                audit_ctx={
                    "source_type": "telegram_channel",
                    "source_name": str(source_label),
                    "source_key": str(pending_row.get("source_key") or fallback_key),
                    "trigger": "confirm_signal",
                    "event_ts": msg_event_ts,
                    "trace_id": str(signal.get("trace_id") or "").strip() or None,
                },
            )
            source_profile = str((signal or {}).get("source_profile") or "").strip().lower()
            pending_source_key = str(pending_row.get("source_key") or fallback_key)
            if self._profile_requires_tp_progress_gate(source_profile) and self._is_confirmation_exec_opened(exec_msg):
                self._mark_reentry_signal_started(
                    source_key=str(pending_source_key),
                    signal=dict(signal),
                    profile=str(source_profile),
                )
            out = f"Confirm Signal received.\n\n{exec_msg}"
            if push_only:
                self._send_text(int(chat_id), out, reply_markup=None)
                return ""
            return out

        signal = self._parse_confirmation_signal_for_sources(text, source_names=source_names)
        if not isinstance(signal, dict):
            return None
        trace_id = str(signal.get("trace_id") or "").strip()
        if not trace_id:
            trace_id = self._build_execution_trace_id(
                source_key=str(source_key),
                symbol=str(signal.get("symbol") or ""),
                direction=str(signal.get("direction") or ""),
            )
            signal["trace_id"] = str(trace_id)
        self._append_automation_execution_log(
            source_type="telegram_channel",
            source_name=str(source_label),
            trigger="signal_received",
            status="received",
            symbol=str(signal.get("symbol") or "").strip().upper(),
            timeframe=str(self._confirm_signal_default_timeframe()).strip().upper(),
            direction=str(signal.get("direction") or "").strip().upper(),
            stop_loss=_to_float_or_none(signal.get("stop_loss")),
            stages_total=len(signal.get("tps") or []),
            message="signal_parsed",
            event_ts=msg_event_ts,
            trace_id=str(trace_id),
            stage="ingest",
            stage_status="ok",
            stage_payload={
                "entry_low": _to_float_or_none(signal.get("entry_low")),
                "entry_high": _to_float_or_none(signal.get("entry_high")),
                "entry_mid": _to_float_or_none(signal.get("entry_mid")),
                "stop_loss": _to_float_or_none(signal.get("stop_loss")),
                "tps": [dict(x) for x in (signal.get("tps") or []) if isinstance(x, dict)][:12],
                "source_profile": str(signal.get("source_profile") or "").strip().lower(),
            },
        )
        ai_eval = self.evaluate_confirmation_signal_ai(text=str(text), parsed_signal=dict(signal))
        if isinstance(ai_eval, dict):
            signal["ai_eval"] = dict(ai_eval)
            if not bool(ai_eval.get("allow", True)):
                self._append_automation_execution_log(
                    source_type="telegram_channel",
                    source_name=str(source_label),
                    trigger="signal_ai_eval",
                    status="blocked",
                    symbol=str(signal.get("symbol") or "").strip().upper(),
                    timeframe=str(self._confirm_signal_default_timeframe()).strip().upper(),
                    direction=str(signal.get("direction") or "").strip().upper(),
                    message=str(ai_eval.get("reason") or "blocked"),
                    event_ts=msg_event_ts,
                    trace_id=str(trace_id),
                    stage="ai_eval",
                    stage_status="blocked",
                    error_code="ai_blocked",
                    stage_payload=dict(ai_eval or {}),
                )
                out = (
                    "Confirmation signal blocked by AI evaluation.\n"
                    f"Reason: {str(ai_eval.get('reason') or 'blocked')}"
                )
                if push_only:
                    self._send_text(int(chat_id), out, reply_markup=None)
                    return ""
                return out
        source_profile = str(signal.get("source_profile") or "").strip().lower()
        if self._profile_requires_tp_progress_gate(source_profile):
            if self._should_block_reentry_before_tp(source_key=str(source_key), signal=dict(signal)):
                self._append_automation_execution_log(
                    source_type="telegram_channel",
                    source_name=str(source_label),
                    trigger="signal_reentry_gate",
                    status="ignored",
                    symbol=str(signal.get("symbol") or "").strip().upper(),
                    timeframe=str(self._confirm_signal_default_timeframe()).strip().upper(),
                    direction=str(signal.get("direction") or "").strip().upper(),
                    message="reentry_gate_blocked_before_tp",
                    event_ts=msg_event_ts,
                    trace_id=str(trace_id),
                    stage="gate",
                    stage_status="blocked",
                    error_code="reentry_gate_block",
                )
                out = (
                    "Signal ignored (previous cycle still has no TP progress)\n"
                    f"Source: {str(source_label)}\n"
                    f"Symbol: {str(signal.get('symbol') or '').upper()} {str(signal.get('direction') or '').upper()}\n"
                    "Rule: same source+symbol+direction requires at least one TP hit before next entry."
                )
                if push_only:
                    self._send_text(int(chat_id), out, reply_markup=None)
                    return ""
                return out
        dedupe_key = (
            f"{str(source_key)}|"
            f"{str(signal.get('symbol') or '').upper()}|"
            f"{str(signal.get('direction') or '').upper()}|"
            f"single:{('1' if bool(signal.get('force_single_trade')) else '0')}|"
            f"{float(signal.get('entry_low') or 0.0):.5f}|"
            f"{float(signal.get('entry_high') or 0.0):.5f}|"
            f"{float(signal.get('stop_loss') or 0.0):.5f}|"
            + ",".join(f"{int((r or {}).get('index') or 0)}:{float((r or {}).get('price') or 0.0):.5f}" for r in (signal.get("tps") or []))
        )
        now_ts = time.time()
        with self._lock:
            dedupe_window = float(self._confirm_signal_dedupe_window_sec())
            if dedupe_window > 0.0:
                prev = float(self._confirm_signal_dedupe.get(str(dedupe_key)) or 0.0)
                if prev > 0.0 and (float(now_ts) - float(prev)) <= float(dedupe_window):
                    self._append_automation_execution_log(
                        source_type="telegram_channel",
                        source_name=str(source_label),
                        trigger="signal_deduped",
                        status="ignored",
                        symbol=str(signal.get("symbol") or "").strip().upper(),
                        timeframe=str(self._confirm_signal_default_timeframe()).strip().upper(),
                        direction=str(signal.get("direction") or "").strip().upper(),
                        message="duplicate_signal_within_window",
                        event_ts=msg_event_ts,
                        trace_id=str(trace_id),
                        stage="dedupe",
                        stage_status="ignored",
                        error_code="dedupe_window",
                    )
                    return None
                self._confirm_signal_dedupe[str(dedupe_key)] = float(now_ts)
                if len(self._confirm_signal_dedupe) > 10000:
                    cutoff = float(now_ts) - float(max(600.0, dedupe_window * 2.0))
                    self._confirm_signal_dedupe = {
                        str(k): float(v)
                        for k, v in self._confirm_signal_dedupe.items()
                        if float(v) >= float(cutoff)
                    }
        signal["timeframe"] = str(self._confirm_signal_default_timeframe())
        current_price: Optional[float] = None
        if require_confirm:
            # Confirm-required channels can spend a little extra time for context text.
            # No-confirm channels should execute with minimal latency.
            svc = self._get_live_service()
            try:
                bars = svc.get_recent_candles(
                    symbol=str(signal.get("symbol") or ""),
                    timeframe=str(signal.get("timeframe") or "M5"),
                    count=1,
                    resolve_symbol=True,
                )
                if isinstance(bars, list) and bars and isinstance(bars[-1], dict):
                    current_price = _to_float_or_none((bars[-1] or {}).get("close"))
            except Exception:
                current_price = None
        message = self._format_confirmation_signal_alert(
            signal=signal,
            timeframe=str(signal.get("timeframe") or "M5"),
            current_price=current_price,
            source_label=str(source_label),
        )
        if require_confirm:
            queued_confirm = self._queue_pending_confirmation_signal(
                chat_id=int(chat_id),
                source_label=str(source_label),
                source_key=str(source_key),
                signal=dict(signal),
                created_ts=float(now_ts),
            )
            self._append_automation_execution_log(
                source_type="telegram_channel",
                source_name=str(source_label),
                trigger="signal_pending_confirm",
                status="queued",
                symbol=str(signal.get("symbol") or "").strip().upper(),
                timeframe=str(signal.get("timeframe") or "").strip().upper(),
                direction=str(signal.get("direction") or "").strip().upper(),
                stop_loss=_to_float_or_none(signal.get("stop_loss")),
                stages_total=len(signal.get("tps") or []),
                message="waiting_confirm_signal",
                event_ts=msg_event_ts,
                trace_id=str(trace_id),
                stage="pending_confirm",
                stage_status="queued",
                stage_payload={"queue_id": str((queued_confirm or {}).get("id") or "")},
            )
            out = f"{message}\n\nPending confirmation stored. Waiting for message: Confirm Signal"
        else:
            if self._confirm_signal_wait_entry_zone():
                queued = self._queue_entry_signal(
                    chat_id=int(chat_id),
                    signal=dict(signal),
                    source_label=str(source_label),
                    source_key=str(source_key),
                    lot_override=None,
                    source_tag="telegram_noconfirm",
                    comment_prefix="tgn",
                    audit_ctx={
                        "source_type": "telegram_channel",
                        "source_name": str(source_label),
                        "source_key": str(source_key),
                        "trigger": "entry_signal",
                        "event_ts": msg_event_ts,
                        "trace_id": str(trace_id),
                    },
                )
                self._append_automation_execution_log(
                    source_type="telegram_channel",
                    source_name=str(source_label),
                    trigger="signal_pending_entry_zone",
                    status="queued",
                    symbol=str(signal.get("symbol") or "").strip().upper(),
                    timeframe=str(signal.get("timeframe") or "").strip().upper(),
                    direction=str(signal.get("direction") or "").strip().upper(),
                    stop_loss=_to_float_or_none(signal.get("stop_loss")),
                    stages_total=len(signal.get("tps") or []),
                    message="waiting_entry_zone",
                    event_ts=msg_event_ts,
                    trace_id=str(trace_id),
                    stage="entry_wait",
                    stage_status="queued",
                    stage_payload={"queue_id": str((queued or {}).get("id") or "")},
                )
                out = (
                    f"{message}\n\n"
                    "Signal queued. Waiting for live price to reach entry zone "
                    "(lower/upper inclusive).\n"
                    f"Queue ID: {str((queued or {}).get('id') or '-')}"
                )
            else:
                exec_msg = self._execute_confirmation_signal_auto(
                    chat_id=int(chat_id),
                    signal=signal,
                    audit_ctx={
                        "source_type": "telegram_channel",
                        "source_name": str(source_label),
                        "source_key": str(source_key),
                        "trigger": "entry_signal",
                        "event_ts": msg_event_ts,
                        "trace_id": str(trace_id),
                    },
                )
                if self._profile_requires_tp_progress_gate(source_profile) and self._is_confirmation_exec_opened(exec_msg):
                    self._mark_reentry_signal_started(
                        source_key=str(source_key),
                        signal=dict(signal),
                        profile=str(source_profile),
                    )
                out = f"{message}\n\n{exec_msg}"
        if push_only:
            self._send_text(int(chat_id), out, reply_markup=None)
            return ""
        return out

    def ingest_external_channel_message(
        self,
        *,
        source_title: str,
        text: str,
        source_username: Optional[str] = None,
        source_id: Optional[int] = None,
        feed_only: bool = False,
        source_message_ts: Optional[Any] = None,
        source_message_id: Optional[int] = None,
    ) -> None:
        """Ingest channel messages coming from non-bot listener (e.g., Telethon user account)."""
        raw = str(text or "").strip()
        if not raw:
            return
        chat = {
            "id": int(source_id or 0),
            "type": "channel",
            "title": str(source_title or "").strip() or "channel",
            "username": str(source_username or "").strip() or None,
        }
        msg = {
            "text": raw,
            "chat": dict(chat),
            "sender_chat": dict(chat),
        }
        if bool(feed_only):
            source_names = self._extract_message_source_names(msg, chat)
            source_label = next((str(x) for x in source_names if str(x).strip()), str(chat.get("title") or "channel"))
            kind = self._classify_confirm_signal_message_for_sources(raw, source_names=source_names)
            parsed = self._parse_confirmation_signal_for_sources(raw, source_names=source_names) if kind == "signal" else None
            self._append_confirm_signal_feed(
                source=str(source_label),
                chat=chat,
                text=raw,
                kind=str(kind),
                parsed=parsed,
                event_ts=source_message_ts,
                source_message_id=source_message_id,
            )
            return
        target_chat = self._allowed_chat_id()
        if target_chat is None:
            source_names = self._extract_message_source_names(msg, chat)
            source_label = next((str(x) for x in source_names if str(x).strip()), str(chat.get("title") or "channel"))
            kind = self._classify_confirm_signal_message_for_sources(raw, source_names=source_names)
            parsed = self._parse_confirmation_signal_for_sources(raw, source_names=source_names) if kind == "signal" else None
            self._append_confirm_signal_feed(
                source=str(source_label),
                chat=chat,
                text=raw,
                kind=str(kind),
                parsed=parsed,
            )
            return
        try:
            handled = self._handle_confirmation_signal_message(
                chat_id=int(target_chat),
                msg=msg,
                chat=chat,
                text=raw,
                push_only=True,
            )
            if handled is None:
                source_names = self._extract_message_source_names(msg, chat)
                source_label = next((str(x) for x in source_names if str(x).strip()), str(chat.get("title") or "channel"))
                kind = self._classify_confirm_signal_message_for_sources(raw, source_names=source_names)
                parsed = self._parse_confirmation_signal_for_sources(raw, source_names=source_names) if kind == "signal" else None
                self._append_confirm_signal_feed(
                    source=str(source_label),
                    chat=chat,
                    text=raw,
                    kind=str(kind),
                    parsed=parsed,
                    event_ts=source_message_ts,
                    source_message_id=source_message_id,
                )
        except Exception:
            logger.exception("external_channel_ingest_failed")

    def _cancel_deadzone_quick_trade(self, chat_id: int) -> str:
        cid = int(chat_id)
        with self._lock:
            existed = self._pending_deadzone_quick_trade_by_chat.pop(cid, None)
        self._set_next_reply_markup(cid, None)
        return "Quick Trade flow canceled." if existed else "No active Quick Trade flow."

    def _close_live_positions_quick(self, *, symbol: Optional[str] = None) -> str:
        svc = self._get_live_service()
        target = str(symbol or "").strip().upper()
        try:
            rows = svc.get_open_positions(symbol=(target if target else None))
        except Exception as exc:
            return f"Close failed: could not read open positions ({type(exc).__name__}: {str(exc)[:120]})."
        if not isinstance(rows, list) or not rows:
            return "No active MT5 position found."
        closed = 0
        failed = 0
        fail_msgs: List[str] = []
        for r in rows:
            ticket = int((r or {}).get("ticket") or 0)
            sym = str((r or {}).get("symbol") or "").strip().upper()
            if ticket <= 0 or not sym:
                failed += 1
                continue
            try:
                out = svc.close_position(
                    symbol=str(sym),
                    position_ticket=int(ticket),
                    comment="tg_quick_close",
                )
            except Exception as exc:
                failed += 1
                fail_msgs.append(f"{sym}#{ticket}: {type(exc).__name__}")
                continue
            if bool((out or {}).get("ok")):
                closed += 1
            else:
                failed += 1
                fail_msgs.append(f"{sym}#{ticket}: {str((out or {}).get('error') or 'close_failed')[:80]}")
        tail = ""
        if fail_msgs:
            tail = "\nFailed: " + " | ".join(fail_msgs[:3])
        return f"Close active positions done. Closed={int(closed)} Failed={int(failed)}{tail}"

    def _build_position_select_markup(self, *, positions: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        rows: List[List[Dict[str, str]]] = []
        for p in positions[:12]:
            ticket = int((p or {}).get("ticket") or 0)
            sym = str((p or {}).get("symbol") or "").strip().upper()
            direction = str((p or {}).get("direction") or "").strip().upper()
            pnl = _to_float_or_none((p or {}).get("profit_loss"))
            if ticket <= 0 or not sym:
                continue
            label = f"{sym} {direction} #{ticket}"
            if pnl is not None and math.isfinite(float(pnl)):
                label += f" ({float(pnl):+.2f})"
            cb = f"ytq|ct|{int(ticket)}|{sym}"
            rows.append([{"text": str(label)[:64], "callback_data": str(cb)}])
        if not rows:
            return None
        rows.append([{"text": "Cancel", "callback_data": "ytq|x"}])
        return {"inline_keyboard": rows}

    def _open_position_close_selector(self, *, symbol: Optional[str] = None) -> Tuple[str, Optional[Dict[str, Any]]]:
        svc = self._get_live_service()
        target = str(symbol or "").strip().upper()
        try:
            rows = svc.get_open_positions(symbol=(target if target else None))
        except Exception as exc:
            return f"Could not load MT5 positions ({type(exc).__name__}: {str(exc)[:120]}).", None
        if not isinstance(rows, list) or not rows:
            return "No active MT5 position found.", None
        markup = self._build_position_select_markup(positions=rows)
        if not isinstance(markup, dict):
            return "No closable position found.", None
        return f"Select position to close ({len(rows)} open):", markup

    def _close_live_position_by_ticket(self, *, symbol: str, ticket: int) -> str:
        sym = str(symbol or "").strip().upper()
        t = int(ticket or 0)
        if not sym or t <= 0:
            return "Invalid close payload."
        svc = self._get_live_service()
        try:
            out = svc.close_position(symbol=str(sym), position_ticket=int(t), comment="tg_quick_close_selected")
        except Exception as exc:
            return f"Close failed for {sym} #{t}: {type(exc).__name__}: {str(exc)[:120]}"
        if bool((out or {}).get("ok")):
            px = _to_float_or_none((out or {}).get("price"))
            return f"Position closed: {sym} #{t}" + (f" @ {float(px):.5f}" if px is not None else "")
        return f"Close failed for {sym} #{t}: {str((out or {}).get('error') or 'close_failed')[:180]}"

    def _cancel_live_tp_flow(self, chat_id: int) -> str:
        cid = int(chat_id)
        with self._lock:
            existed = self._pending_live_tp_flow_by_chat.pop(cid, None)
        self._set_next_reply_markup(cid, None)
        return "TP flow canceled." if existed else "No active TP flow."

    def _start_live_tp_flow(self, chat_id: int) -> str:
        cid = int(chat_id)
        svc = self._get_live_service()
        try:
            rows = svc.get_open_positions(symbol=None)
        except Exception as exc:
            return f"Could not load MT5 open positions ({type(exc).__name__}: {str(exc)[:140]})."
        if not isinstance(rows, list) or not rows:
            return "No active MT5 position found."
        choices: List[Dict[str, Any]] = []
        lines: List[str] = ["Open positions (pick number):"]
        for idx, p in enumerate(rows, start=1):
            ticket = int((p or {}).get("ticket") or 0)
            symbol = str((p or {}).get("symbol") or "").strip().upper()
            direction = str((p or {}).get("direction") or "").strip().upper()
            lot = _to_float_or_none((p or {}).get("lot_size"))
            pnl = _to_float_or_none((p or {}).get("profit_loss"))
            if ticket <= 0 or not symbol:
                continue
            choices.append(
                {
                    "idx": int(idx),
                    "ticket": int(ticket),
                    "symbol": str(symbol),
                    "direction": str(direction),
                    "lot_size": float(lot or 0.0),
                    "profit_loss": float(pnl or 0.0),
                }
            )
            lot_txt = "-" if lot is None else f"{float(lot):.2f}"
            pnl_txt = "-" if pnl is None else f"{float(pnl):+.2f}"
            lines.append(f"{int(idx)}) {symbol} {direction} #{ticket} lot={lot_txt} pnl={pnl_txt}")
        if not choices:
            return "No selectable MT5 position found."
        state = {
            "type": "live_tp_manage",
            "stage": "await_index",
            "choices": choices,
            "created_at": self._now_iso(),
        }
        with self._lock:
            self._pending_live_tp_flow_by_chat[cid] = state
        lines.append("Send position number. Type 'cancel' to abort.")
        return "\n".join(lines)

    def _live_tp_execute_partial_close(self, *, symbol: str, ticket: int, target_profit_usd: float) -> str:
        svc = self._get_live_service()
        sym = str(symbol or "").strip().upper()
        t = int(ticket or 0)
        want = float(target_profit_usd or 0.0)
        if not sym or t <= 0 or (not math.isfinite(want)) or want <= 0.0:
            return "Invalid partial TP request."
        try:
            current_rows = svc.get_open_positions(symbol=str(sym))
        except Exception as exc:
            return f"Could not refresh position for partial TP ({type(exc).__name__}: {str(exc)[:120]})."
        row = None
        for r in current_rows if isinstance(current_rows, list) else []:
            if int((r or {}).get("ticket") or 0) == int(t):
                row = r
                break
        if not isinstance(row, dict):
            return f"Position not found or already closed: {sym} #{t}."
        current_pnl = _to_float_or_none((row or {}).get("profit_loss"))
        current_lot = _to_float_or_none((row or {}).get("lot_size"))
        if current_pnl is None or current_lot is None or (not math.isfinite(float(current_lot))) or float(current_lot) <= 0.0:
            return "Position data unavailable for partial TP."
        if float(current_pnl) <= 0.0:
            return f"Position is not in profit now ({float(current_pnl):+.2f}). Partial TP requires positive P/L."
        take_usd = float(min(float(want), float(current_pnl)))
        raw_lot = float(current_lot) * (float(take_usd) / float(current_pnl))
        if (not math.isfinite(raw_lot)) or raw_lot <= 0.0:
            return "Could not compute partial close lot."
        info = svc.get_symbol_info(symbol=str(sym))
        if isinstance(info, dict) and str(info.get("error") or "").strip():
            return f"Symbol info unavailable for {sym}: {str(info.get('error'))[:120]}"
        vol_min = _to_float_or_none((info or {}).get("volume_min")) or 0.01
        vol_step = _to_float_or_none((info or {}).get("volume_step")) or 0.01
        vol_max = _to_float_or_none((info or {}).get("volume_max")) or float(current_lot)
        vol_step = max(1e-6, float(vol_step))
        vol_min = max(vol_step, float(vol_min))
        cap_max = min(float(current_lot), float(max(vol_min, vol_max)))
        lot_units = math.floor(float(raw_lot) / float(vol_step))
        lot_norm = float(lot_units) * float(vol_step)
        lot_norm = min(cap_max, max(0.0, float(lot_norm)))
        if float(lot_norm) <= 0.0:
            return "Requested TP amount is too small for broker lot step."
        if float(lot_norm) < float(vol_min):
            min_take = float(current_pnl) * (float(vol_min) / float(current_lot))
            return (
                f"Requested TP too small for {sym}. Min realizable now is about ${float(min_take):.2f} "
                f"(min lot {float(vol_min):.2f})."
            )
        if float(lot_norm) >= float(current_lot) - (float(vol_step) * 0.5):
            out = svc.close_position(symbol=str(sym), position_ticket=int(t), comment="tg_tp_take_all")
            if bool((out or {}).get("ok")):
                return f"Take-all profit executed: {sym} #{t} closed."
            return f"Take-all profit failed: {str((out or {}).get('error') or 'close_failed')[:160]}"
        out = svc.close_position(
            symbol=str(sym),
            position_ticket=int(t),
            lot_size=float(lot_norm),
            comment="tg_tp_partial",
        )
        if not bool((out or {}).get("ok")):
            return f"Partial TP failed: {str((out or {}).get('error') or 'close_failed')[:160]}"
        realized_est = float(current_pnl) * (float(lot_norm) / float(current_lot))
        return (
            f"Partial TP done: {sym} #{t}\n"
            f"Closed lot: {float(lot_norm):.2f}/{float(current_lot):.2f}\n"
            f"Estimated realized: ${float(realized_est):.2f}"
        )

    def _handle_live_tp_flow_text(self, chat_id: int, raw: str) -> Optional[str]:
        cid = int(chat_id)
        with self._lock:
            state = dict(self._pending_live_tp_flow_by_chat.get(cid) or {})
        if not state or str(state.get("type") or "") != "live_tp_manage":
            return None
        text = str(raw or "").strip()
        lowered = text.lower()
        if lowered in {"cancel", "abort", "/cancel", "/stop", "stop"}:
            return self._cancel_live_tp_flow(cid)
        stage = str(state.get("stage") or "")
        choices = state.get("choices") if isinstance(state.get("choices"), list) else []
        if stage == "await_index":
            if not str(text).isdigit():
                return "Send position number (example: 1). Type 'cancel' to abort."
            idx = int(text)
            selected = None
            for c in choices:
                if int((c or {}).get("idx") or 0) == int(idx):
                    selected = dict(c)
                    break
            if not isinstance(selected, dict):
                return f"Invalid number. Choose between 1 and {int(len(choices))}."
            pnl = _to_float_or_none(selected.get("profit_loss")) or 0.0
            state["selected"] = selected
            state["stage"] = "await_action"
            with self._lock:
                self._pending_live_tp_flow_by_chat[cid] = dict(state)
            markup = {
                "inline_keyboard": [
                    [
                        self._inline_button(
                            int(cid),
                            "Take All Profit (Close Full)",
                            {
                                "type": "tp_take_all",
                                "symbol": str(selected.get("symbol") or ""),
                                "ticket": int(selected.get("ticket") or 0),
                                "one_shot": True,
                            },
                        )
                    ],
                    [self._inline_button(int(cid), "Cancel", {"type": "tp_flow_cancel", "one_shot": True})],
                ]
            }
            self._set_next_reply_markup(int(cid), markup)
            return (
                f"Selected: {str(selected.get('symbol'))} {str(selected.get('direction'))} #{int(selected.get('ticket') or 0)} | pnl={float(pnl):+.2f}\n"
                "Choose action:\n"
                "1) Close full position\n"
                "2) Take partial profit ($) and keep running\n"
                "3) Take all profit (close full)\n"
                "Reply with 1/2/3."
            )
        if stage == "await_action":
            sel = state.get("selected") if isinstance(state.get("selected"), dict) else {}
            symbol = str(sel.get("symbol") or "").strip().upper()
            ticket = int(sel.get("ticket") or 0)
            if ticket <= 0 or not symbol:
                return "Selected position is missing. Start again with /tp."
            if text == "1":
                msg = self._close_live_position_by_ticket(symbol=symbol, ticket=ticket)
                with self._lock:
                    self._pending_live_tp_flow_by_chat.pop(cid, None)
                return msg
            if text == "3":
                msg = self._live_tp_execute_partial_close(symbol=symbol, ticket=ticket, target_profit_usd=1e12)
                with self._lock:
                    self._pending_live_tp_flow_by_chat.pop(cid, None)
                return msg
            if text == "2":
                state["stage"] = "await_partial_amount"
                with self._lock:
                    self._pending_live_tp_flow_by_chat[cid] = dict(state)
                return "Enter profit amount to realize in USD (example: 10)."
            return "Invalid action. Reply with 1, 2 or 3."
        if stage == "await_partial_amount":
            sel = state.get("selected") if isinstance(state.get("selected"), dict) else {}
            symbol = str(sel.get("symbol") or "").strip().upper()
            ticket = int(sel.get("ticket") or 0)
            amt = self._parse_positive_number(text)
            if amt is None:
                return "Enter a positive USD amount (example: 10)."
            msg = self._live_tp_execute_partial_close(symbol=symbol, ticket=ticket, target_profit_usd=float(amt))
            with self._lock:
                self._pending_live_tp_flow_by_chat.pop(cid, None)
            return msg
        return None

    def _handle_external_quick_trade_callback(self, chat_id: int, data: str) -> Tuple[str, Optional[Dict[str, Any]]]:
        raw = str(data or "").strip()
        parts = [str(x or "").strip() for x in raw.split("|")]
        if len(parts) < 2 or str(parts[0]).lower() != "ytq":
            return "Unsupported callback action.", None
        cmd = str(parts[1]).lower()
        if cmd == "o":
            if len(parts) < 5:
                return "Invalid quick-trade callback payload.", None
            symbol = str(parts[2] or "").strip()
            timeframe = str(parts[3] or "M5").strip().upper()
            direction = str(parts[4] or "").strip().upper()
            from_color = str(parts[5] or "").strip().lower() if len(parts) >= 6 else ""
            to_color = str(parts[6] or "").strip().lower() if len(parts) >= 7 else ""
            action = {
                "type": "deadzone_quick_trade_start",
                "symbol": str(symbol),
                "timeframe": str(timeframe),
                "direction": str(direction),
                "from_color": str(from_color),
                "to_color": str(to_color),
            }
            return self._start_deadzone_quick_trade_flow(int(chat_id), action), None
        if cmd == "c":
            scope = str(parts[2] or "ALL").strip().upper() if len(parts) >= 3 else "ALL"
            if scope in {"ALL", "*"}:
                return self._close_live_positions_quick(symbol=None), None
            return self._close_live_positions_quick(symbol=str(scope)), None
        if cmd == "ls":
            scope = str(parts[2] or "ALL").strip().upper() if len(parts) >= 3 else "ALL"
            if scope in {"ALL", "*"}:
                return self._open_position_close_selector(symbol=None)
            return self._open_position_close_selector(symbol=str(scope))
        if cmd == "ct":
            if len(parts) < 4:
                return "Invalid close-ticket callback payload.", None
            try:
                ticket = int(parts[2])
            except Exception:
                return "Invalid position ticket.", None
            symbol = str(parts[3] or "").strip().upper()
            return self._close_live_position_by_ticket(symbol=symbol, ticket=int(ticket)), None
        if cmd == "x":
            return "Selection canceled.", None
        return "Unsupported quick-trade callback command.", None

    def _start_deadzone_quick_trade_flow(self, chat_id: int, action: Dict[str, Any]) -> str:
        symbol = str((action or {}).get("symbol") or "").strip()
        timeframe = str((action or {}).get("timeframe") or "").strip().upper() or "M15"
        from_color = str((action or {}).get("from_color") or "").strip().lower()
        to_color = str((action or {}).get("to_color") or "").strip().lower()
        direction_raw = str((action or {}).get("direction") or "").strip().upper()
        direction = direction_raw if direction_raw in {"BUY", "SELL"} else self._deadzone_quick_trade_direction(from_color, to_color)
        if direction not in {"BUY", "SELL"}:
            return "Quick Trade direction invalid. Use BUY or SELL."
        sid, reason = self._resolve_quick_trade_session(int(chat_id), str(symbol), str(timeframe))
        if sid is None or int(sid) <= 0:
            return (
                f"No active Workbench session found for {str(symbol).upper()} {str(timeframe).upper()}.\n"
                "Start/select a matching live Workbench session first, then tap Quick Trade again."
            )
        session_mode = "unknown"
        db_mode = SessionLocal()
        try:
            srow = db_mode.query(SimulationSession).get(int(sid))
            if srow is not None:
                session_mode = str(getattr(srow, "mode", "") or "").strip().upper() or "UNKNOWN"
        except Exception:
            session_mode = "unknown"
        finally:
            try:
                db_mode.close()
            except Exception:
                pass
        state = {
            "type": "deadzone_quick_trade",
            "stage": "await_lot",
            "session_id": int(sid),
            "symbol": str(symbol).strip(),
            "timeframe": str(timeframe).upper(),
            "from_color": str(from_color),
            "to_color": str(to_color),
            "direction": str(direction),
            "resolver": str(reason),
            "session_mode": str(session_mode),
            "created_at": self._now_iso(),
        }
        with self._lock:
            self._pending_deadzone_quick_trade_by_chat[int(chat_id)] = state
        self._set_next_reply_markup(int(chat_id), None)
        return (
            "Quick Trade armed\n"
            f"Session: #{int(sid)} [{str(session_mode)}] | {str(symbol).strip()} {str(timeframe).upper()}\n"
            f"Flip: {str(from_color).upper()} -> {str(to_color).upper()} => {str(direction)}\n"
            "Enter Lot size (example: 0.02). Type 'cancel' to abort."
        )

    def _build_deadzone_quick_trade_preview(
        self,
        *,
        chat_id: int,
        state: Dict[str, Any],
        risk_usd: float,
        lot_size: float,
        tp_usd: float,
    ) -> Tuple[str, Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
        symbol_raw = str(state.get("symbol") or "").strip()
        symbol = str(symbol_raw).upper()
        timeframe = str(state.get("timeframe") or "").strip().upper() or "M15"
        direction = str(state.get("direction") or "").strip().upper()
        session_id = int(state.get("session_id") or 0)
        if session_id <= 0 or direction not in {"BUY", "SELL"} or not symbol:
            return "Quick Trade state is invalid. Start again from the alert.", None, None
        svc = self._get_live_service()
        try:
            bars = svc.get_recent_candles(
                symbol=str(symbol_raw or symbol),
                timeframe=str(timeframe),
                count=5,
                resolve_symbol=True,
            )
        except Exception:
            bars = []
        if not isinstance(bars, list) or not bars:
            return f"Could not load live price for {symbol} {timeframe}.", None, None
        last = bars[-1] if isinstance(bars[-1], dict) else {}
        try:
            entry_price = float(last.get("close"))
        except Exception:
            entry_price = math.nan
        if not math.isfinite(float(entry_price)) or float(entry_price) <= 0.0:
            return f"Invalid entry price for {symbol} {timeframe}.", None, None
        bar_time_unix = int(last.get("time_unix") or 0)

        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes

            session = db.query(SimulationSession).get(int(session_id))
            if session is None or str(session.strategy_id or "") != "_workbench":
                return f"Session #{int(session_id)} not available.", None, None
            trade_math = sim_routes._session_trade_math_context(
                session=session,
                symbol=str(session.symbol or symbol),
            )
            value_per_1lot = sim_routes._to_float_or_none((trade_math or {}).get("value_per_1lot"))
            min_lot = sim_routes._to_float_or_none((trade_math or {}).get("min_lot"))
            max_lot = sim_routes._to_float_or_none((trade_math or {}).get("max_lot"))
            lot_step = sim_routes._to_float_or_none((trade_math or {}).get("lot_step"))
            point = sim_routes._to_float_or_none((trade_math or {}).get("point"))
            if value_per_1lot is None or (not math.isfinite(float(value_per_1lot))) or float(value_per_1lot) <= 0.0:
                return "Symbol economics unavailable (value_per_1lot).", None, None
            lot_norm = float(
                sim_routes._normalize_lot_for_instrument(
                    lot_size=float(lot_size),
                    min_lot=float(min_lot if min_lot is not None else 0.01),
                    max_lot=float(max_lot if max_lot is not None else 100.0),
                    lot_step=float(lot_step if lot_step is not None else 0.01),
                )
            )
            if not math.isfinite(float(lot_norm)) or float(lot_norm) <= 0.0:
                return "Invalid lot size after broker normalization.", None, None
            risk_distance = float(risk_usd) / (float(value_per_1lot) * float(lot_norm))
            if (not math.isfinite(float(risk_distance))) or float(risk_distance) <= 0.0:
                return "Risk distance is invalid. Check risk/lot values.", None, None
            tp_distance = float(tp_usd) / (float(value_per_1lot) * float(lot_norm))
            if (not math.isfinite(float(tp_distance))) or float(tp_distance) <= 0.0:
                return "TP distance is invalid. Check TP USD / lot values.", None, None
            sl_raw = float(entry_price) - float(risk_distance) if direction == "BUY" else float(entry_price) + float(risk_distance)
            tp_raw = float(entry_price) + float(tp_distance) if direction == "BUY" else float(entry_price) - float(tp_distance)
            if point is not None and math.isfinite(float(point)) and float(point) > 0.0:
                sl_raw = round(float(sl_raw) / float(point)) * float(point)
                tp_raw = round(float(tp_raw) / float(point)) * float(point)
            stop_loss = float(sl_raw)
            take_profit = float(tp_raw)
            if (not math.isfinite(float(stop_loss))) or float(stop_loss) <= 0.0:
                return "Calculated Stop Loss is invalid.", None, None
            if (not math.isfinite(float(take_profit))) or float(take_profit) <= 0.0:
                return "Calculated Take Profit is invalid.", None, None
            risk_actual = abs(float(entry_price) - float(stop_loss)) * float(value_per_1lot) * float(lot_norm)
            tp_actual = abs(float(take_profit) - float(entry_price)) * float(value_per_1lot) * float(lot_norm)
            sl_distance_pct = (abs(float(entry_price) - float(stop_loss)) / float(entry_price) * 100.0) if float(entry_price) > 0.0 else None
            tp_distance_pct = (abs(float(take_profit) - float(entry_price)) / float(entry_price) * 100.0) if float(entry_price) > 0.0 else None
            state_next = dict(state)
            state_next.update(
                {
                    "stage": "await_confirm",
                    "risk_usd": float(risk_usd),
                    "tp_usd": float(tp_usd),
                    "lot_size": float(lot_norm),
                    "entry_price": float(entry_price),
                    "stop_loss": float(stop_loss),
                    "take_profit": float(take_profit),
                    "bar_time_unix": int(bar_time_unix),
                    "value_per_1lot": float(value_per_1lot),
                    "risk_actual_usd": float(risk_actual),
                    "tp_actual_usd": float(tp_actual),
                    "sl_distance_pct": float(sl_distance_pct) if sl_distance_pct is not None and math.isfinite(float(sl_distance_pct)) else None,
                    "tp_distance_pct": float(tp_distance_pct) if tp_distance_pct is not None and math.isfinite(float(tp_distance_pct)) else None,
                    "updated_at": self._now_iso(),
                }
            )
            message = (
                "Quick Trade preview\n"
                f"Session: #{int(session_id)} | {str(symbol)} {str(timeframe)}\n"
                f"Direction: {str(direction)}\n"
                f"Entry: {float(entry_price):.5f}\n"
                f"SL: {float(stop_loss):.5f}\n"
                f"TP: {float(take_profit):.5f}\n"
                f"Lot: {float(lot_norm):.4f}\n"
                f"Risk (target): ${float(risk_usd):.2f}\n"
                f"Risk (calc): ${float(risk_actual):.2f}\n"
                f"TP (target): ${float(tp_usd):.2f}\n"
                f"TP (calc): ${float(tp_actual):.2f}\n"
                f"SL distance: {('-' if sl_distance_pct is None else f'{float(sl_distance_pct):.4f}%')}\n"
                f"TP distance: {('-' if tp_distance_pct is None else f'{float(tp_distance_pct):.4f}%')}\n"
                "Confirm trade?"
            )
            markup = {
                "inline_keyboard": [
                    [
                        self._inline_button(int(chat_id), "Confirm Quick Trade", {"type": "deadzone_quick_trade_confirm", "one_shot": True}),
                        self._inline_button(int(chat_id), "Cancel", {"type": "deadzone_quick_trade_cancel", "one_shot": True}),
                    ]
                ]
            }
            return message, markup, state_next
        except Exception as exc:
            return f"Quick Trade preview failed: {type(exc).__name__}: {str(exc)[:180]}", None, None
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _execute_deadzone_quick_trade_confirm(self, chat_id: int) -> str:
        with self._lock:
            state = dict(self._pending_deadzone_quick_trade_by_chat.get(int(chat_id)) or {})
        if not state or str(state.get("type")) != "deadzone_quick_trade":
            return "No pending Quick Trade flow."
        if str(state.get("stage") or "") != "await_confirm":
            return "Quick Trade is waiting for Lot/Risk/TP inputs first."
        session_id = int(state.get("session_id") or 0)
        direction = str(state.get("direction") or "").strip().upper()
        stop_loss = self._parse_positive_number(state.get("stop_loss"))
        take_profit = self._parse_positive_number(state.get("take_profit"))
        lot_size = self._parse_positive_number(state.get("lot_size"))
        entry_price = self._parse_positive_number(state.get("entry_price"))
        bar_time_unix = int(state.get("bar_time_unix") or 0)
        if session_id <= 0 or direction not in {"BUY", "SELL"} or stop_loss is None or take_profit is None or lot_size is None:
            return "Quick Trade state is invalid. Start again from the alert."
        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes

            phrase = str(getattr(sim_routes, "_LIVE_CONFIRMATION_PHRASE", "CONFIRM_LIVE_ORDER"))
            req = sim_routes.TradeRequest(
                direction=str(direction),
                stop_loss=float(stop_loss),
                take_profit=float(take_profit),
                lot_size=float(lot_size),
                entry_price=float(entry_price) if entry_price is not None else None,
                bar_time_unix=int(bar_time_unix) if int(bar_time_unix) > 0 else None,
                confirm_live_order=True,
                live_confirmation_phrase=str(phrase),
            )
            data = sim_routes.execute_trade(session_id=int(session_id), req=req, db=db)
            with self._lock:
                self._pending_deadzone_quick_trade_by_chat.pop(int(chat_id), None)
            self._set_next_reply_markup(int(chat_id), None)
            return (
                "Quick Trade executed\n"
                f"Session: #{int(session_id)}\n"
                f"Trade ID: {int((data or {}).get('id') or 0)}\n"
                f"Direction: {str((data or {}).get('direction') or direction).upper()}\n"
                f"Entry: {float((data or {}).get('entry_price') or 0.0):.5f}\n"
                f"Lot: {float((data or {}).get('lot_size') or lot_size):.4f}"
            )
        except HTTPException as exc:
            return f"Quick Trade failed: {str(exc.detail)[:220]}"
        except Exception as exc:
            return f"Quick Trade failed: {type(exc).__name__}: {str(exc)[:220]}"
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _handle_deadzone_quick_trade_text(self, chat_id: int, raw: str) -> Optional[str]:
        cid = int(chat_id)
        with self._lock:
            state = dict(self._pending_deadzone_quick_trade_by_chat.get(cid) or {})
        if not state or str(state.get("type")) != "deadzone_quick_trade":
            return None
        text = str(raw or "").strip()
        lowered = text.lower()
        if text.startswith("/") and lowered not in {"/cancel", "/confirm"}:
            return None
        if lowered in {"cancel", "abort", "stop", "/stop"}:
            return self._cancel_deadzone_quick_trade(cid)
        if lowered in {"/cancel"} and len(text.split()) == 1:
            return self._cancel_deadzone_quick_trade(cid)

        stage = str(state.get("stage") or "")
        if stage == "await_lot":
            lot = self._parse_positive_number(text)
            if lot is None:
                return "Enter Lot size as a positive number (example: 0.02). Type 'cancel' to abort."
            state["lot_size"] = float(lot)
            state["stage"] = "await_risk"
            state["updated_at"] = self._now_iso()
            with self._lock:
                self._pending_deadzone_quick_trade_by_chat[cid] = dict(state)
            return "Enter Risk USD (example: 10). Type 'cancel' to abort."

        if stage == "await_risk":
            risk = self._parse_positive_number(text)
            if risk is None:
                return "Enter Risk USD as a positive number (example: 10). Type 'cancel' to abort."
            state["risk_usd"] = float(risk)
            state["stage"] = "await_tp"
            state["updated_at"] = self._now_iso()
            with self._lock:
                self._pending_deadzone_quick_trade_by_chat[cid] = dict(state)
            return "Enter TP USD (example: 20). Type 'cancel' to abort."

        if stage == "await_tp":
            tp_usd = self._parse_positive_number(text)
            if tp_usd is None:
                return "Enter TP USD as a positive number (example: 20). Type 'cancel' to abort."
            lot = self._parse_positive_number(state.get("lot_size"))
            if lot is None:
                state["stage"] = "await_lot"
                with self._lock:
                    self._pending_deadzone_quick_trade_by_chat[cid] = dict(state)
                return "Lot value expired. Enter Lot size again."
            risk = self._parse_positive_number(state.get("risk_usd"))
            if risk is None:
                state["stage"] = "await_risk"
                with self._lock:
                    self._pending_deadzone_quick_trade_by_chat[cid] = dict(state)
                return "Risk value expired. Enter Risk USD again."
            msg, markup, state_next = self._build_deadzone_quick_trade_preview(
                chat_id=cid,
                state=state,
                risk_usd=float(risk),
                lot_size=float(lot),
                tp_usd=float(tp_usd),
            )
            if isinstance(state_next, dict) and state_next:
                with self._lock:
                    self._pending_deadzone_quick_trade_by_chat[cid] = dict(state_next)
            if isinstance(markup, dict) and markup:
                self._set_next_reply_markup(cid, markup)
            return msg

        if stage == "await_confirm":
            if lowered in {"confirm", "yes", "y", "/confirm"}:
                return self._execute_deadzone_quick_trade_confirm(cid)
            return "Tap 'Confirm Quick Trade' button (or type 'confirm'). Type 'cancel' to abort."

        return None

    def _push_deadzone_colorflip_alerts(self) -> None:
        if not self._deadzone_colorflip_enabled():
            return
        if not self._enabled() or not self._token():
            return
        target_chat = self._allowed_chat_id()
        if target_chat is None:
            return
        now_ts = time.time()
        if (now_ts - float(self._deadzone_watch_last_run_ts)) < float(self._deadzone_colorflip_interval_sec()):
            return
        self._deadzone_watch_last_run_ts = now_ts
        try:
            from ..api import simulation_routes as sim_routes
        except Exception:
            return
        svc = self._get_live_service()
        watch_symbols = self._resolve_deadzone_watch_symbols()
        if not watch_symbols:
            return
        noncore_filter_enabled = bool(self._deadzone_noncore_filter_enabled())
        noncore_confirm_polls = int(self._deadzone_noncore_confirm_polls())
        noncore_min_hold_sec = float(self._deadzone_noncore_min_hold_sec())
        noncore_cooldown_sec = float(self._deadzone_noncore_cooldown_sec())
        tf_list = ("M5", "M15")
        bars_count = int(self._deadzone_colorflip_history_count())
        for row in watch_symbols:
            label = str(row.get("label") or "").upper()
            resolved = str(row.get("resolved") or "")
            if not label or not resolved:
                continue
            for tf in tf_list:
                try:
                    bars = svc.get_recent_candles(
                        symbol=str(resolved),
                        timeframe=str(tf),
                        count=int(bars_count),
                        resolve_symbol=False,
                    )
                except Exception:
                    bars = []
                if not isinstance(bars, list) or len(bars) < 80:
                    continue
                try:
                    bars_norm = self._normalize_live_bars_for_color_engine(bars)
                    df = sim_routes._bars_payload_to_df(bars_norm, max_rows=2000, min_rows=80)
                except Exception:
                    df = None
                if df is None or df.empty:
                    continue
                try:
                    cstate = sim_routes._strategy_automation_color_from_bars(
                        bars_df=df,
                        strategy_key="deadzone_pro",
                        preset_cfg={},
                        volume_sma_period=20,
                        closed_bar_only=False,
                    )
                except Exception:
                    continue
                color_now = str((cstate or {}).get("color") or "gray").strip().lower()
                if color_now not in {"green", "red", "gray"}:
                    color_now = "gray"
                key = (str(resolved).upper(), str(tf).upper())
                is_core = bool(self._is_deadzone_core_symbol(resolved))
                prev = str(self._deadzone_watch_last_color.get(key) or "").strip().lower()
                self._deadzone_watch_last_color[key] = str(color_now)
                if prev not in {"green", "red", "gray"}:
                    with self._lock:
                        self._deadzone_watch_pending_noncore.pop(key, None)
                    continue
                bar_unix = int((bars_norm[-1] or {}).get("time") or 0) if isinstance(bars_norm[-1], dict) and bars_norm else 0
                alert_key = f"{bar_unix}:{prev}>{color_now}:{key[0]}:{key[1]}"
                try:
                    rsi_now = sim_routes._rsi_last(df["close"], period=14)
                except Exception:
                    rsi_now = None
                try:
                    px = float(df["close"].iloc[-1])
                except Exception:
                    px = None

                # Keep BTC/XAU behavior unchanged: immediate intrabar alert on flip.
                if is_core or (not noncore_filter_enabled):
                    with self._lock:
                        self._deadzone_watch_pending_noncore.pop(key, None)
                    if prev == color_now:
                        continue
                    if str(self._deadzone_watch_last_alert_key.get(key) or "") == str(alert_key):
                        continue
                    msg, markup = self._build_deadzone_colorflip_alert_payload(
                        chat_id=int(target_chat),
                        label=label,
                        resolved=str(resolved),
                        timeframe=str(tf).upper(),
                        from_color=str(prev),
                        to_color=str(color_now),
                        price=px,
                        rsi=rsi_now,
                    )
                    try:
                        with self._lock:
                            sent = bool(self._send_text(int(target_chat), msg, reply_markup=markup))
                    except Exception:
                        sent = False
                    if sent:
                        self._deadzone_watch_last_alert_key[key] = str(alert_key)
                        self._deadzone_watch_last_alert_ts[key] = float(now_ts)
                        logger.info(
                            "telegram_deadzone_global_colorflip_sent label=%s symbol=%s timeframe=%s from=%s to=%s",
                            str(label),
                            str(resolved),
                            str(tf),
                            str(prev),
                            str(color_now),
                        )
                    continue

                # Non-core light filter path (persistence + short hold + short cooldown).
                with self._lock:
                    pending = dict(self._deadzone_watch_pending_noncore.get(key) or {})
                if prev != color_now:
                    pending = {
                        "label": str(label),
                        "resolved": str(resolved),
                        "timeframe": str(tf).upper(),
                        "from_color": str(prev),
                        "to_color": str(color_now),
                        "started_ts": float(now_ts),
                        "polls": 1,
                        "bar_unix": int(bar_unix),
                        "price": px,
                        "rsi": rsi_now,
                        "alert_key": str(alert_key),
                    }
                    with self._lock:
                        self._deadzone_watch_pending_noncore[key] = dict(pending)
                    continue

                if not pending:
                    continue

                target_color = str(pending.get("to_color") or "").strip().lower()
                if target_color != color_now:
                    with self._lock:
                        self._deadzone_watch_pending_noncore.pop(key, None)
                    continue

                pending["polls"] = int(pending.get("polls") or 0) + 1
                pending["bar_unix"] = int(bar_unix)
                pending["price"] = px
                pending["rsi"] = rsi_now
                with self._lock:
                    self._deadzone_watch_pending_noncore[key] = dict(pending)

                started_ts = float(pending.get("started_ts") or now_ts)
                polls = int(pending.get("polls") or 0)
                since_start = float(now_ts) - float(started_ts)
                if polls < int(noncore_confirm_polls):
                    continue
                if since_start < float(noncore_min_hold_sec):
                    continue
                last_alert_ts = float(self._deadzone_watch_last_alert_ts.get(key) or 0.0)
                if (float(now_ts) - float(last_alert_ts)) < float(noncore_cooldown_sec):
                    continue
                pending_alert_key = str(pending.get("alert_key") or "")
                if pending_alert_key and str(self._deadzone_watch_last_alert_key.get(key) or "") == pending_alert_key:
                    with self._lock:
                        self._deadzone_watch_pending_noncore.pop(key, None)
                    continue
                msg, markup = self._build_deadzone_colorflip_alert_payload(
                    chat_id=int(target_chat),
                    label=str(pending.get("label") or label),
                    resolved=str(pending.get("resolved") or resolved),
                    timeframe=str(pending.get("timeframe") or str(tf).upper()),
                    from_color=str(pending.get("from_color") or prev),
                    to_color=str(pending.get("to_color") or color_now),
                    price=pending.get("price"),
                    rsi=pending.get("rsi"),
                )
                try:
                    with self._lock:
                        sent = bool(self._send_text(int(target_chat), msg, reply_markup=markup))
                except Exception:
                    sent = False
                with self._lock:
                    self._deadzone_watch_pending_noncore.pop(key, None)
                if sent:
                    self._deadzone_watch_last_alert_key[key] = str(pending_alert_key or alert_key)
                    self._deadzone_watch_last_alert_ts[key] = float(now_ts)
                    logger.info(
                        "telegram_deadzone_global_colorflip_sent_noncore label=%s symbol=%s timeframe=%s from=%s to=%s polls=%s hold_sec=%.2f",
                        str(pending.get("label") or label),
                        str(pending.get("resolved") or resolved),
                        str(pending.get("timeframe") or str(tf).upper()),
                        str(pending.get("from_color") or prev),
                        str(pending.get("to_color") or color_now),
                        int(polls),
                        float(since_start),
                    )

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
    def _screener_page_size() -> int:
        try:
            raw = int(TelegramBridgeService._get_env_value("TELEGRAM_SCREENER_PAGE_SIZE", "6"))
        except Exception:
            raw = 6
        return max(3, min(20, raw))

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

    @staticmethod
    def _keyboard_enabled() -> bool:
        v = str(TelegramBridgeService._get_env_value("TELEGRAM_UI_KEYBOARD_ENABLED", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    def _main_reply_keyboard(self) -> Dict[str, Any]:
        return {
            "keyboard": [
                [{"text": "/latest"}, {"text": "/status"}, {"text": "/summary"}],
                [{"text": "/runtime"}, {"text": "/triggers"}, {"text": "/strategy"}],
                [{"text": "/screener"}, {"text": "/menu"}],
                [{"text": "/newsession XAUUSD M15 live mt5 10000"}],
                [{"text": "/hidekeyboard"}],
            ],
            "resize_keyboard": True,
            "one_time_keyboard": False,
            "selective": False,
        }

    @staticmethod
    def _to_base36(num: int) -> str:
        chars = "0123456789abcdefghijklmnopqrstuvwxyz"
        n = int(max(0, int(num or 0)))
        if n == 0:
            return "0"
        out = []
        while n:
            n, r = divmod(n, 36)
            out.append(chars[r])
        return "".join(reversed(out))

    def _register_callback_action(self, chat_id: int, action: Dict[str, Any]) -> str:
        cid = int(chat_id)
        with self._lock:
            nxt = int(self._next_callback_id_by_chat.get(cid, 0)) + 1
            self._next_callback_id_by_chat[cid] = nxt
            token = self._to_base36(nxt)
            rows = self._callback_actions_by_chat.setdefault(cid, {})
            order = self._callback_action_order_by_chat.setdefault(cid, [])
            rows[token] = dict(action or {})
            order.append(token)
            # Keep bounded memory.
            max_keep = 600
            while len(order) > max_keep:
                old = order.pop(0)
                rows.pop(old, None)
            return token

    def _consume_callback_action(self, chat_id: int, token: str) -> Optional[Dict[str, Any]]:
        cid = int(chat_id)
        tok = str(token or "").strip()
        if not tok:
            return None
        with self._lock:
            rows = self._callback_actions_by_chat.get(cid) or {}
            action = rows.get(tok)
            if action is None:
                return None
            one_shot = bool((action or {}).get("one_shot", True))
            if one_shot:
                rows.pop(tok, None)
                order = self._callback_action_order_by_chat.get(cid) or []
                if tok in order:
                    order.remove(tok)
            return dict(action)

    def _inline_button(self, chat_id: int, text: str, action: Dict[str, Any]) -> Dict[str, Any]:
        token = self._register_callback_action(int(chat_id), action)
        return {"text": str(text), "callback_data": f"cb:{token}"}

    def _build_pending_inline_keyboard(self, chat_id: int) -> Optional[Dict[str, Any]]:
        rows = self._get_pending(int(chat_id))
        if not rows:
            return None
        kb: List[List[Dict[str, Any]]] = []
        for p in rows[:4]:
            pid = int(p.get("id") or 0)
            if pid <= 0:
                continue
            kb.append(
                [
                    self._inline_button(
                        int(chat_id),
                        f"Approve #{pid}",
                        {"type": "pending_approve", "pending_id": int(pid), "one_shot": True},
                    ),
                    self._inline_button(
                        int(chat_id),
                        f"Cancel #{pid}",
                        {"type": "pending_cancel", "pending_id": int(pid), "one_shot": True},
                    ),
                ]
            )
        if not kb:
            return None
        return {"inline_keyboard": kb}

    def _build_session_inline_keyboard(self, chat_id: int, session_id: int) -> Dict[str, Any]:
        sid = int(session_id)
        return {
            "inline_keyboard": [
                [
                    self._inline_button(int(chat_id), f"Use #{sid}", {"type": "use_session", "session_id": sid}),
                    self._inline_button(int(chat_id), "Status", {"type": "session_status", "session_id": sid}),
                ],
                [
                    self._inline_button(int(chat_id), "Runtime", {"type": "session_runtime", "session_id": sid}),
                    self._inline_button(int(chat_id), "Triggers", {"type": "session_triggers", "session_id": sid}),
                ],
                [
                    self._inline_button(int(chat_id), "Run Screener", {"type": "session_screener", "session_id": sid}),
                ],
            ]
        }

    def _build_triggers_inline_keyboard(self, chat_id: int, session_id: int) -> Optional[Dict[str, Any]]:
        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes

            out = sim_routes.workbench_agent_triggers_list(session_id=int(session_id), db=db)
            rows = out.get("triggers") if isinstance(out, dict) else []
            if not isinstance(rows, list) or not rows:
                return None
            kb: List[List[Dict[str, Any]]] = []
            for r in rows[:6]:
                if not isinstance(r, dict):
                    continue
                tid = str(r.get("id") or "").strip()
                if not tid:
                    continue
                st = str(r.get("status") or "").lower()
                buttons = [
                    self._inline_button(
                        int(chat_id),
                        f"Details {tid[-6:]}",
                        {"type": "trigger_details", "session_id": int(session_id), "trigger_id": tid},
                    )
                ]
                if st in {"pending", "pending_approval"}:
                    buttons.append(
                        self._inline_button(
                            int(chat_id),
                            f"Cancel {tid[-6:]}",
                            {"type": "trigger_cancel", "session_id": int(session_id), "trigger_id": tid, "one_shot": True},
                        )
                    )
                kb.append(buttons)
            if not kb:
                return None
            return {"inline_keyboard": kb}
        except Exception:
            return None
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _build_screener_inline_keyboard(self, chat_id: int, session_id: int, page: int = 0) -> Optional[Dict[str, Any]]:
        key = (int(chat_id), int(session_id))
        with self._lock:
            scan = self._last_screener_scan_by_chat_session.get(key)
        if not isinstance(scan, dict):
            return None
        strategy = str(scan.get("strategy") or "mtf")
        scan_tf = str(scan.get("scan_tf") or "M15")
        exec_tf = str(scan.get("exec_tf") or scan_tf)
        opportunities = scan.get("opportunities") if isinstance(scan.get("opportunities"), list) else []
        if not opportunities:
            return None
        page_size = int(self._screener_page_size())
        total = int(len(opportunities))
        total_pages = max(1, int(math.ceil(float(total) / float(page_size))))
        page_idx = int(max(0, min(total_pages - 1, int(page or 0))))
        start = int(page_idx * page_size)
        end = int(min(total, start + page_size))
        kb: List[List[Dict[str, Any]]] = []
        for row in opportunities[start:end]:
            if not isinstance(row, dict):
                continue
            sym = str(row.get("symbol") or "").strip().upper()
            if not sym:
                continue
            direction = str(row.get("direction") or "").strip().upper()
            conf = float(row.get("confidence") or 0.0)
            kb.append(
                [
                    self._inline_button(
                        int(chat_id),
                        f"Analyze {sym}",
                        {
                            "type": "screener_analyze",
                            "session_id": int(session_id),
                            "strategy": strategy,
                            "symbol": sym,
                            "scan_tf": scan_tf,
                            "exec_tf": exec_tf,
                        },
                    ),
                    self._inline_button(
                        int(chat_id),
                        f"One-Click {sym} {direction}",
                        {
                            "type": "screener_oneclick",
                            "session_id": int(session_id),
                            "strategy": strategy,
                            "symbol": sym,
                            "scan_tf": scan_tf,
                            "exec_tf": exec_tf,
                        },
                    ),
                ]
            )
        if total_pages > 1:
            nav_row: List[Dict[str, Any]] = []
            if page_idx > 0:
                nav_row.append(
                    self._inline_button(
                        int(chat_id),
                        "Prev",
                        {
                            "type": "screener_page",
                            "session_id": int(session_id),
                            "strategy": strategy,
                            "scan_tf": scan_tf,
                            "exec_tf": exec_tf,
                            "page": int(page_idx - 1),
                        },
                    )
                )
            nav_row.append(
                self._inline_button(
                    int(chat_id),
                    f"Page {int(page_idx + 1)}/{int(total_pages)}",
                    {"type": "noop", "text": f"Screener page {int(page_idx + 1)} of {int(total_pages)}"},
                )
            )
            if page_idx < (total_pages - 1):
                nav_row.append(
                    self._inline_button(
                        int(chat_id),
                        "Next",
                        {
                            "type": "screener_page",
                            "session_id": int(session_id),
                            "strategy": strategy,
                            "scan_tf": scan_tf,
                            "exec_tf": exec_tf,
                            "page": int(page_idx + 1),
                        },
                    )
                )
            kb.append(nav_row)
        kb.append(
            [
                self._inline_button(
                        int(chat_id),
                        f"{sym} conf {conf:.1f}",
                        {"type": "noop", "text": f"{sym} confidence {conf:.1f}/100"},
                    )
                ]
            )
        kb.append(
            [
                self._inline_button(
                    int(chat_id),
                    "Refresh Screener",
                    {
                        "type": "screener_refresh",
                        "session_id": int(session_id),
                        "strategy": strategy,
                        "scan_tf": scan_tf,
                        "exec_tf": exec_tf,
                    },
                )
            ]
        )
        return {"inline_keyboard": kb}

    def _format_botprofile(self) -> str:
        profile = self._active_profile()
        scoped_token_key = self._profile_scoped_key("TELEGRAM_BOT_TOKEN", profile)
        scoped_chat_key = self._profile_scoped_key("TELEGRAM_ALLOWED_CHAT_ID", profile)
        scoped_enabled_key = self._profile_scoped_key("TELEGRAM_ENABLED", profile)
        lines = [
            f"Telegram profile: {profile}",
            "Resolution source: dashboard/.env only",
            f"Keys checked: {scoped_token_key or 'TELEGRAM_BOT_TOKEN'} / {scoped_chat_key or 'TELEGRAM_ALLOWED_CHAT_ID'} / {scoped_enabled_key or 'TELEGRAM_ENABLED'}",
            "Fallback keys: TELEGRAM_BOT_TOKEN / TELEGRAM_ALLOWED_CHAT_ID / TELEGRAM_ENABLED",
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
            # Telegram bridge should not inherit host-level proxy env vars by default.
            # Local broken proxies (e.g. 127.0.0.1:9) can otherwise hard-fail bot delivery.
            with httpx.Client(timeout=timeout_sec, http2=False, trust_env=False) as client:
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

    def _send_text(self, chat_id: int, text: str, reply_markup: Optional[Dict[str, Any]] = None) -> bool:
        chunks = self._chunk_text(text, limit=3500)
        for idx, chunk in enumerate(chunks):
            try:
                params: Dict[str, Any] = {
                    "chat_id": int(chat_id),
                    "text": chunk,
                }
                if idx == 0 and isinstance(reply_markup, dict) and reply_markup:
                    try:
                        params["reply_markup"] = json.dumps(reply_markup, ensure_ascii=False)
                    except Exception:
                        pass
                self._tg_request(
                    "sendMessage",
                    params=params,
                    timeout_sec=15.0,
                    http_method="POST",
                )
            except Exception as exc:
                logger.warning("telegram sendMessage failed: %s", str(exc)[:220])
                return False
        return True

    def send_system_alert(self, text: str, *, chat_id: Optional[int] = None) -> bool:
        """
        Best-effort outbound alert helper for backend services.
        Returns True when send attempt completed without local validation errors.
        """
        msg = str(text or "").strip()
        if not msg:
            return False
        if not self._enabled():
            return False
        token = self._token()
        if not token:
            return False
        target = int(chat_id) if chat_id is not None else self._allowed_chat_id()
        if target is None:
            return False
        try:
            with self._lock:
                return bool(self._send_text(int(target), msg))
        except Exception as exc:
            logger.warning("telegram system alert failed: %s", str(exc)[:220])
            return False

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
            strategy_profile = "classic_htf_fvg"
            strategy_preset = "default"
            try:
                from ..api import simulation_routes as sim_routes

                strategy_profile = sim_routes._normalize_agent_strategy_profile(
                    (_cfg if isinstance(_cfg, dict) else {}).get("agent_strategy_profile")
                )
                strategy_preset = sim_routes._normalize_agent_strategy_preset(
                    (_cfg if isinstance(_cfg, dict) else {}).get("agent_strategy_preset")
                )
            except Exception:
                pass
            lines = [
                f"Runtime | Session #{int(session.id)} | {str(session.symbol or '').upper()} {str(session.timeframe or '').upper()}",
                f"Provider: {p} | Model: {model}",
                f"LLM URL: {llm_url if llm_url else '(provider default)'}",
                f"API key: {'YES' if has_api_key else 'MISSING'}",
                f"Strategy: {strategy_profile} | Preset: {strategy_preset}",
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
            is_live_mt5_exec = False
            try:
                is_live_mt5_exec = bool(sim_routes._is_live_mt5_execution_enabled(session))
            except Exception:
                is_live_mt5_exec = False
            _provider_cfg, perms_cfg, _tool_cfg = self._resolve_provider_and_permissions(int(session_id))
            approved_perms = dict(perms_cfg if isinstance(perms_cfg, dict) else {})
            approved_perms["can_place_trades"] = True
            approved_perms["can_close_trades"] = True
            approved_perms["requires_user_confirm_for_trade"] = False
            args_for_exec = dict(args) if isinstance(args, dict) else {}
            if is_live_mt5_exec and tool in {"place_trade", "close_trade"}:
                phrase = str(getattr(sim_routes, "_LIVE_CONFIRMATION_PHRASE", "CONFIRM_LIVE_ORDER"))
                args_for_exec["confirm_live_order"] = True
                args_for_exec["live_confirmation_phrase"] = phrase
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
                args=args_for_exec,
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

    def _strategy_profile_choices(self) -> List[Tuple[str, str]]:
        return [
            ("classic_htf_fvg", "classic"),
            ("htf_fvg_liquidity_reclaim_v2", "liquidity"),
            ("orb_ny_15m_imbalance", "orb"),
            ("trendilo_confirmation_v1", "trendilo"),
            ("advanced_trendilo_confirmation_v1", "advanced_trendilo"),
            ("trendilo_lsma_confirmation_v1", "trendilo_lsma"),
        ]

    def _format_strategy_help(self) -> str:
        choices = ", ".join(f"{label} ({profile})" for profile, label in self._strategy_profile_choices())
        return (
            "Usage: /strategy [name] [session_id]\n"
            f"Available: {choices}"
        )

    def _set_strategy_profile(self, session_id: int, profile_raw: Any, preset_raw: Optional[Any] = None) -> str:
        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes

            raw = str(profile_raw or "").strip().lower()
            allowed_raw = {p for p, _label in self._strategy_profile_choices()}
            allowed_raw.update(label for _p, label in self._strategy_profile_choices())
            allowed_raw.update(
                {
                    "classic",
                    "legacy",
                    "mtf",
                    "htf_fvg",
                    "classic_fvg",
                    "liquidity",
                    "liq",
                    "liquidity_reclaim",
                    "htf_fvg_liquidity_reclaim",
                    "htf_fvg_liquidity_reclaim_strategy",
                    "liquidity_reclaim_v2",
                    "v2",
                    "orb",
                    "opening_range",
                    "opening_range_breakout",
                    "orb_15m",
                    "orb_ny_15m",
                    "orb_imbalance",
                    "trendilo",
                    "trendilo_strategy",
                    "trendilo_v1",
                    "trendilo_confirmation",
                    "advanced_trendilo",
                    "advanced_trendilo_strategy",
                    "advanced_trendilo_v1",
                    "trendilo_advanced",
                    "advanced_trendilo_confirmation",
                    "trendilo_lsma",
                    "trendilo_lsma_strategy",
                    "trendilo_lsma_v1",
                    "lsma",
                    "lsma_trendilo",
                    "trendilo_lsma_confirmation",
                }
            )
            if raw and raw not in allowed_raw:
                return self._format_strategy_help()
            profile = sim_routes._normalize_agent_strategy_profile(profile_raw)
            preset = sim_routes._normalize_agent_strategy_preset(preset_raw)

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
            cfg["agent_strategy_profile"] = profile
            if preset_raw is not None and str(preset_raw).strip():
                cfg["agent_strategy_preset"] = preset
            row.config_json = cfg
            row.updated_at = datetime.utcnow()
            db.add(row)
            db.commit()
            return (
                f"Strategy set to '{profile}'"
                f"{f' with preset {preset}' if preset_raw is not None and str(preset_raw).strip() else ''}"
                f" for session #{int(session_id)}."
            )
        except Exception as exc:
            db.rollback()
            return f"Strategy update failed: {type(exc).__name__}: {str(exc)[:180]}"
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

    @staticmethod
    def _extract_trailing_session_arg(tokens: List[str]) -> Tuple[Optional[int], List[str]]:
        if not tokens:
            return None, tokens
        tail = str(tokens[-1]).strip()
        if not tail.isdigit():
            return None, tokens
        try:
            return int(tail), tokens[:-1]
        except Exception:
            return None, tokens

    def _active_scan_strategy(self, session_id: int) -> str:
        try:
            from ..api import simulation_routes as sim_routes

            _provider, _perms, cfg = self._resolve_provider_and_permissions(int(session_id))
            profile = sim_routes._normalize_agent_strategy_profile(
                (cfg if isinstance(cfg, dict) else {}).get("agent_strategy_profile")
            )
        except Exception:
            profile = "classic_htf_fvg"
        mapping = {
            "classic_htf_fvg": "mtf",
            "htf_fvg_liquidity_reclaim_v2": "htf_reclaim",
            "orb_ny_15m_imbalance": "orb",
            "trendilo_confirmation_v1": "trendilo",
            "advanced_trendilo_confirmation_v1": "advanced_trendilo",
            "trendilo_lsma_confirmation_v1": "trendilo_lsma",
        }
        return str(mapping.get(str(profile), "mtf"))

    def _create_workbench_session_core(
        self,
        *,
        symbol: str,
        timeframe: str,
        mode: str = "live",
        source: str = "mt5",
        initial_balance: float = 10000.0,
        execution_mode: str = "paper",
    ) -> Dict[str, Any]:
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        md = str(mode or "live").strip().lower()
        src = str(source or "mt5").strip().lower()
        exec_mode = str(execution_mode or "paper").strip().lower()
        try:
            bal = float(initial_balance)
        except Exception:
            bal = 10000.0
        if not sym or not tf:
            raise ValueError("invalid_symbol_or_timeframe")
        if md not in {"live", "replay"}:
            raise ValueError("invalid_mode")
        if src not in {"mt5", "databento"}:
            src = "mt5"
        bal = max(100.0, min(10_000_000.0, float(bal)))

        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes

            cost_model = {
                "enabled": True,
                "spread": 0.30,
                "tc_rate": 0.0005,
                "spread_source": "manual",
            }
            cfg: Dict[str, Any] = {"cost_model": cost_model}
            allow_empty_replay = False
            if md == "live":
                allow_empty_replay = True
                cfg["live_control"] = {
                    "enabled": True,
                    "source": str(src),
                    "backend_native": bool(src == "mt5"),
                    "use_active_account": bool(src == "mt5"),
                    "execution_mode": ("mt5" if exec_mode == "mt5" else "paper"),
                    "kill_switch_enabled": False,
                    "max_risk_per_trade_usd": 25.0,
                    "max_lot_per_trade": 5.0,
                    "require_confirmation_for_live_order": True,
                }
            req = sim_routes.CreateSessionRequest(
                strategy_id="_workbench",
                symbol=str(sym),
                timeframe=str(tf),
                mode=str(md),
                data_file=None,
                initial_balance=float(bal),
                config=cfg,
                allow_empty_replay=bool(allow_empty_replay),
            )
            out = sim_routes.create_session(req=req, db=db)
            if not isinstance(out, dict) or out.get("id") is None:
                raise RuntimeError("invalid_backend_response")
            return out
        finally:
            try:
                db.close()
            except Exception:
                pass

    def _create_workbench_session(
        self,
        *,
        chat_id: int,
        symbol: str,
        timeframe: str,
        mode: str = "live",
        source: str = "mt5",
        initial_balance: float = 10000.0,
        execution_mode: str = "paper",
    ) -> str:
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        md = str(mode or "live").strip().lower()
        try:
            out = self._create_workbench_session_core(
                symbol=sym,
                timeframe=tf,
                mode=md,
                source=source,
                initial_balance=float(initial_balance),
                execution_mode=str(execution_mode),
            )
            sid = int(out.get("id"))
            self._set_default_session(int(chat_id), int(sid))
            return (
                f"Session created: #{sid}\n"
                f"Symbol/TF: {str(out.get('symbol') or sym).upper()} {str(out.get('timeframe') or tf).upper()}\n"
                f"Mode: {str(out.get('mode') or md).lower()} | Balance: {float(out.get('initial_balance') or initial_balance):.2f}\n"
                f"Total bars: {int(out.get('total_bars') or 0)}\n"
                f"Default session set to #{sid}."
            )
        except ValueError:
            return "Usage: /newsession <symbol> <timeframe> [live|replay] [mt5|databento] [balance]"
        except HTTPException as exc:
            return f"Session creation failed: {str(exc.detail)[:220]}"
        except Exception as exc:
            return f"Session creation failed: {type(exc).__name__}: {str(exc)[:180]}"

    def _run_strategy_screener(
        self,
        *,
        chat_id: Optional[int] = None,
        session_id: int,
        strategy: str,
        universe: str,
        universe_limit: int,
        timeframe: str,
        execution_timeframe: str,
        max_results: int = 20,
    ) -> str:
        sid = int(session_id)
        strategy_in = str(strategy or "").strip().lower() or "mtf"
        strategy_alias = {
            "1": "mtf",
            "strategy1": "mtf",
            "classic": "mtf",
            "mtf": "mtf",
            "2": "htf_reclaim",
            "strategy2": "htf_reclaim",
            "reclaim": "htf_reclaim",
            "htf_reclaim": "htf_reclaim",
            "liquidity": "htf_reclaim",
            "3": "orb",
            "strategy3": "orb",
            "orb": "orb",
            "4": "trendilo",
            "strategy4": "trendilo",
            "trendilo": "trendilo",
            "5": "advanced_trendilo",
            "strategy5": "advanced_trendilo",
            "advanced_trendilo": "advanced_trendilo",
            "advanced_trendilo_strategy": "advanced_trendilo",
            "trendilo_advanced": "advanced_trendilo",
            "6": "trendilo_lsma",
            "strategy6": "trendilo_lsma",
            "trendilo_lsma": "trendilo_lsma",
            "trendilo_lsma_strategy": "trendilo_lsma",
            "lsma": "trendilo_lsma",
            "lsma_trendilo": "trendilo_lsma",
        }
        strategy_key = str(strategy_alias.get(strategy_in, "mtf"))
        universe_key = str(universe or "market_mixed_top").strip().lower() or "market_mixed_top"
        tf_scan = str(timeframe or "M15").strip().upper() or "M15"
        tf_exec = str(execution_timeframe or tf_scan).strip().upper() or tf_scan
        limit = int(max(5, min(200, int(universe_limit or 80))))
        max_rows = int(max(1, min(50, int(max_results or 20))))

        db = SessionLocal()
        try:
            from ..api import simulation_routes as sim_routes

            session = db.query(SimulationSession).get(int(sid))
            if session is None:
                return f"Session #{int(sid)} not found."
            if str(session.strategy_id or "") != "_workbench":
                return f"Session #{int(sid)} is not a Workbench session."
            try:
                ctx = sim_routes._agent_default_context(session=session, db=db)
            except Exception:
                ctx = {}
            cfg = sim_routes._agent_effective_tool_config(session=session, db=db)
            payload = {
                "strategy": str(strategy_key),
                "source": "mt5",
                "universe": str(universe_key),
                "universe_limit": int(limit),
                "timeframe": str(tf_scan),
                "execution_timeframe": str(tf_exec),
                "summary_only": True,
                "include_non_tradeable": False,
                "max_results": int(max_rows),
            }
            data = sim_routes._agent_scan_strategy_tradeable(
                session=session,
                db=db,
                context_snapshot=ctx if isinstance(ctx, dict) else {},
                payload=payload,
                effective_cfg=cfg if isinstance(cfg, dict) else {},
            )
            if not isinstance(data, dict):
                return "Screener failed: invalid backend response."
            opportunities = data.get("opportunities") if isinstance(data.get("opportunities"), list) else []
            if chat_id is not None:
                try:
                    with self._lock:
                        self._last_screener_scan_by_chat_session[(int(chat_id), int(sid))] = {
                            "strategy": str(strategy_key),
                            "scan_tf": str(tf_scan),
                            "exec_tf": str(tf_exec),
                            "opportunities": [dict(r) for r in opportunities if isinstance(r, dict)],
                            "generated_at": self._now_iso(),
                        }
                except Exception:
                    pass
            out = [
                (
                    f"Screener | strategy={strategy_key} | tf={tf_scan} | exec={tf_exec}\n"
                    f"Universe={str(data.get('universe_resolved') or universe_key)}({int(data.get('universe_symbol_count') or 0)}) "
                    f"scanned={int(data.get('symbols_scanned') or 0)} ok={int(data.get('ok_count') or 0)} "
                    f"err={int(data.get('error_count') or 0)} tradeable={int(data.get('tradeable_count') or 0)} "
                    f"elapsed={int(data.get('elapsed_ms') or 0)}ms"
                )
            ]
            if not opportunities:
                out.append("No tradeable symbols found in this scan.")
                return "\n".join(out)
            out.append("Top tradeable:")
            for i, row in enumerate(opportunities[:max_rows], 1):
                if not isinstance(row, dict):
                    continue
                args = row.get("schedule_trade_entry_args") if isinstance(row.get("schedule_trade_entry_args"), dict) else {}
                out.append(
                    f"{i}) {str(row.get('symbol') or '').upper()} {str(row.get('direction') or '').upper()} "
                    f"conf={float(row.get('confidence') or 0.0):.1f} rr={float(row.get('rr') or 0.0):.2f} "
                    f"entry={args.get('entry_ref', row.get('entry_ref'))} sl={args.get('stop_loss', row.get('stop_loss'))} "
                    f"tp={args.get('take_profit', row.get('take_profit'))} lot={args.get('lot_size', row.get('lot_size'))}"
                )
            out.append("To schedule one: /ask schedule symbol <SYMBOL> using screener args.")
            return "\n".join(out)
        except Exception as exc:
            return f"Screener failed: {type(exc).__name__}: {str(exc)[:180]}"
        finally:
            try:
                db.close()
            except Exception:
                pass

    @staticmethod
    def _strategy_key_to_profile_alias(strategy_key: str) -> str:
        sk = str(strategy_key or "").strip().lower()
        mapping = {
            "mtf": "classic",
            "htf_reclaim": "liquidity",
            "orb": "orb",
            "trendilo": "trendilo",
            "advanced_trendilo": "advanced_trendilo",
            "trendilo_lsma": "trendilo_lsma",
        }
        return str(mapping.get(sk, "classic"))

    @staticmethod
    def _premade_analysis_prompt(strategy_key: str) -> str:
        sk = str(strategy_key or "").strip().lower()
        if sk == "trendilo":
            return (
                "Run tools now. Validate Trendilo gates for the active session symbol/timeframe. "
                "Output only: TRADEABLE_TODAY or NOT_TRADEABLE_TODAY, gate audit, and exact "
                "schedule_trade_entry args if tradeable. Do NOT execute any trade."
            )
        if sk == "advanced_trendilo":
            return (
                "Run tools now. Validate Advanced Trendilo gates for the active session symbol/timeframe. "
                "Output only: TRADEABLE_TODAY or NOT_TRADEABLE_TODAY, gate audit including persistence/edge/ADX-rising/DI-spread, "
                "and exact schedule_trade_entry args if tradeable. Do NOT execute any trade."
            )
        if sk == "trendilo_lsma":
            return (
                "Run tools now. Validate Trendilo LSMA gates for the active session symbol/timeframe. "
                "Use Pine-parity LSMA+HMA combine direction (green=long, red=short, yellow=neutral). "
                "Output only: TRADEABLE_TODAY or NOT_TRADEABLE_TODAY, gate audit, and exact schedule_trade_entry args if tradeable. "
                "Do NOT execute any trade."
            )
        if sk == "orb":
            return (
                "Run ORB analysis for active session symbol/timeframe and decide if today is tradeable. "
                "Output gate audit, tradeability verdict, and exact schedule_trade_entry args if valid. "
                "Do NOT execute any trade."
            )
        if sk == "htf_reclaim":
            return (
                "Run HTF FVG + Liquidity Reclaim analysis for active session symbol/timeframe. "
                "Return gate audit, watch/block/ready decision, and exact schedule_trade_entry args if valid. "
                "Do NOT execute any trade."
            )
        return (
            "Run MTF analysis for active session symbol/timeframe. "
            "Return setup quality, tradeability verdict, and exact schedule_trade_entry args if valid. "
            "Do NOT execute any trade."
        )

    def _execute_callback_action(self, chat_id: int, action: Dict[str, Any]) -> Tuple[str, Optional[Dict[str, Any]]]:
        atype = str((action or {}).get("type") or "").strip().lower()
        if atype == "noop":
            return str((action or {}).get("text") or "OK"), None

        if atype == "deadzone_quick_trade_start":
            return self._start_deadzone_quick_trade_flow(int(chat_id), action), None

        if atype == "deadzone_quick_trade_confirm":
            return self._execute_deadzone_quick_trade_confirm(int(chat_id)), None

        if atype == "deadzone_quick_trade_cancel":
            return self._cancel_deadzone_quick_trade(int(chat_id)), None

        if atype == "deadzone_quick_trade_close_all":
            scope = str((action or {}).get("scope") or "ALL").strip().upper()
            if scope in {"ALL", "*"}:
                return self._close_live_positions_quick(symbol=None), None
            return self._close_live_positions_quick(symbol=str(scope)), None

        if atype == "tp_take_all":
            symbol = str((action or {}).get("symbol") or "").strip().upper()
            ticket = int((action or {}).get("ticket") or 0)
            if ticket <= 0 or not symbol:
                return "Invalid take-all action payload.", None
            msg = self._live_tp_execute_partial_close(symbol=symbol, ticket=ticket, target_profit_usd=1e12)
            with self._lock:
                self._pending_live_tp_flow_by_chat.pop(int(chat_id), None)
            return msg, None

        if atype == "tp_flow_cancel":
            return self._cancel_live_tp_flow(int(chat_id)), None

        if atype == "use_session":
            sid = int((action or {}).get("session_id") or 0)
            if sid <= 0:
                return "Invalid session.", None
            db = SessionLocal()
            try:
                row = db.query(SimulationSession).get(int(sid))
                if row is None:
                    return f"Session #{sid} not found.", None
                if str(row.strategy_id or "") != "_workbench":
                    return f"Session #{sid} is not a Workbench session.", None
                self._set_default_session(int(chat_id), int(sid))
                return f"Default session set to #{sid} ({str(row.symbol or '').upper()} {str(row.timeframe or '').upper()}).", self._build_session_inline_keyboard(int(chat_id), int(sid))
            finally:
                db.close()

        if atype == "session_status":
            sid = int((action or {}).get("session_id") or 0)
            return self._format_status(int(sid)), self._build_session_inline_keyboard(int(chat_id), int(sid))

        if atype == "session_runtime":
            sid = int((action or {}).get("session_id") or 0)
            return self._format_runtime(int(sid)), self._build_session_inline_keyboard(int(chat_id), int(sid))

        if atype == "session_triggers":
            sid = int((action or {}).get("session_id") or 0)
            return self._format_triggers(int(sid)), self._build_triggers_inline_keyboard(int(chat_id), int(sid))

        if atype == "session_screener":
            sid = int((action or {}).get("session_id") or 0)
            msg = self._run_strategy_screener(
                chat_id=int(chat_id),
                session_id=int(sid),
                strategy=self._active_scan_strategy(int(sid)),
                universe="market_mixed_top",
                universe_limit=80,
                timeframe="M15",
                execution_timeframe="M15",
                max_results=20,
            )
            return msg, self._build_screener_inline_keyboard(int(chat_id), int(sid))

        if atype == "pending_approve":
            pid = int((action or {}).get("pending_id") or 0)
            return self._execute_pending_approval(int(chat_id), int(pid)), self._build_pending_inline_keyboard(int(chat_id))

        if atype == "pending_cancel":
            pid = int((action or {}).get("pending_id") or 0)
            return self._cancel_pending_approval(int(chat_id), int(pid)), self._build_pending_inline_keyboard(int(chat_id))

        if atype == "trigger_cancel":
            sid = int((action or {}).get("session_id") or 0)
            tid = str((action or {}).get("trigger_id") or "").strip()
            if sid <= 0 or not tid:
                return "Invalid trigger action.", None
            db = SessionLocal()
            try:
                from ..api import simulation_routes as sim_routes

                out = sim_routes.workbench_agent_trigger_cancel(session_id=int(sid), trigger_id=str(tid), db=db)
                ok = bool((out or {}).get("ok"))
                cancelled = bool((out or {}).get("cancelled"))
                txt = (
                    f"Trigger {tid} cancelled."
                    if (ok and cancelled)
                    else (f"Trigger {tid} was not pending/cancellable." if ok else f"Trigger cancel failed: {str((out or {}).get('error') or 'unknown')[:180]}")
                )
                return txt, self._build_triggers_inline_keyboard(int(chat_id), int(sid))
            except HTTPException as exc:
                return f"Trigger cancel failed: {str(exc.detail)[:180]}", self._build_triggers_inline_keyboard(int(chat_id), int(sid))
            except Exception as exc:
                return f"Trigger cancel failed: {type(exc).__name__}: {str(exc)[:180]}", self._build_triggers_inline_keyboard(int(chat_id), int(sid))
            finally:
                try:
                    db.close()
                except Exception:
                    pass

        if atype == "trigger_details":
            sid = int((action or {}).get("session_id") or 0)
            tid = str((action or {}).get("trigger_id") or "").strip()
            if sid <= 0 or not tid:
                return "Invalid trigger action.", None
            db = SessionLocal()
            try:
                from ..api import simulation_routes as sim_routes

                out = sim_routes.workbench_agent_triggers_list(session_id=int(sid), db=db)
                rows = out.get("triggers") if isinstance(out, dict) else []
                row = None
                for r in rows if isinstance(rows, list) else []:
                    if isinstance(r, dict) and str(r.get("id") or "").strip() == tid:
                        row = r
                        break
                if not isinstance(row, dict):
                    return f"Trigger {tid} not found.", self._build_triggers_inline_keyboard(int(chat_id), int(sid))
                return (
                    f"Trigger {tid}\n"
                    f"status={str(row.get('status') or '').upper()} dir={str(row.get('direction') or '').upper()} tf={str(row.get('timeframe') or '').upper()}\n"
                    f"condition={row.get('condition')} @ {row.get('trigger_price')}\n"
                    f"pre={row.get('precondition')}\n"
                    f"cancel={row.get('cancel_rule')}\n"
                    f"entry={row.get('entry_ref')} sl={row.get('stop_loss')} tp={row.get('take_profit')} lot={row.get('lot_size')}",
                    self._build_triggers_inline_keyboard(int(chat_id), int(sid)),
                )
            except Exception as exc:
                return f"Trigger details failed: {type(exc).__name__}: {str(exc)[:180]}", self._build_triggers_inline_keyboard(int(chat_id), int(sid))
            finally:
                try:
                    db.close()
                except Exception:
                    pass

        if atype in {"screener_refresh", "screener_analyze", "screener_oneclick"}:
            sid = int((action or {}).get("session_id") or self._resolve_default_session_id(int(chat_id)) or 0)
            strategy = str((action or {}).get("strategy") or "mtf").strip().lower()
            scan_tf = str((action or {}).get("scan_tf") or "M15").strip().upper()
            exec_tf = str((action or {}).get("exec_tf") or scan_tf).strip().upper()
            if sid <= 0:
                return "No active Workbench session found.", None
            if atype == "screener_refresh":
                msg = self._run_strategy_screener(
                    chat_id=int(chat_id),
                    session_id=int(sid),
                    strategy=str(strategy),
                    universe="market_mixed_top",
                    universe_limit=80,
                    timeframe=str(scan_tf),
                    execution_timeframe=str(exec_tf),
                    max_results=20,
                )
                return msg, self._build_screener_inline_keyboard(int(chat_id), int(sid))

            symbol = str((action or {}).get("symbol") or "").strip().upper()
            if not symbol:
                return "Invalid screener symbol.", None
            # One-click flow: create session -> set strategy -> run premade analysis prompt.
            try:
                created = self._create_workbench_session_core(
                    symbol=str(symbol),
                    timeframe=str(exec_tf),
                    mode="live",
                    source="mt5",
                    initial_balance=10000.0,
                )
                new_sid = int(created.get("id"))
                self._set_default_session(int(chat_id), int(new_sid))
            except Exception as exc:
                return f"One-click failed at session creation: {type(exc).__name__}: {str(exc)[:180]}", None

            profile_alias = self._strategy_key_to_profile_alias(str(strategy))
            set_out = self._set_strategy_profile(int(new_sid), profile_alias, None)
            if "failed" in str(set_out).lower():
                return f"One-click failed at strategy set: {set_out}", self._build_session_inline_keyboard(int(chat_id), int(new_sid))

            prompt = self._premade_analysis_prompt(str(strategy))
            if atype == "screener_analyze":
                prompt = (
                    f"Symbol selected from screener: {symbol}. "
                    + prompt
                )
            reply = self._run_agent_chat(int(chat_id), int(new_sid), prompt)
            return reply, self._build_pending_inline_keyboard(int(chat_id)) or self._build_session_inline_keyboard(int(chat_id), int(new_sid))

        if atype == "screener_page":
            sid = int((action or {}).get("session_id") or self._resolve_default_session_id(int(chat_id)) or 0)
            if sid <= 0:
                return "No active Workbench session found.", None
            try:
                page_idx = int((action or {}).get("page") or 0)
            except Exception:
                page_idx = 0
            key = (int(chat_id), int(sid))
            with self._lock:
                scan = self._last_screener_scan_by_chat_session.get(key)
            if not isinstance(scan, dict):
                return "Screener results expired. Run /screener again.", None
            opportunities = scan.get("opportunities") if isinstance(scan.get("opportunities"), list) else []
            total = int(len(opportunities))
            page_size = int(self._screener_page_size())
            total_pages = max(1, int(math.ceil(float(total) / float(page_size)))) if total > 0 else 1
            page_idx = int(max(0, min(total_pages - 1, int(page_idx))))
            text = f"Screener page {int(page_idx + 1)}/{int(total_pages)} ({int(total)} symbols)"
            return text, self._build_screener_inline_keyboard(int(chat_id), int(sid), page=page_idx)

        return "Unsupported action.", None

    def _handle_text(self, chat_id: int, text: str) -> str:
        raw = str(text or "").strip()
        if not raw:
            return "Empty message."
        pending_quick = self._handle_deadzone_quick_trade_text(int(chat_id), raw)
        if isinstance(pending_quick, str) and pending_quick.strip():
            return pending_quick
        pending_tp = self._handle_live_tp_flow_text(int(chat_id), raw)
        if isinstance(pending_tp, str) and pending_tp.strip():
            return pending_tp
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
                "/menu\n"
                "- Purpose: Show quick-action Telegram buttons.\n"
                "- Params: none\n"
                "- Example: /menu\n\n"
                "/hidekeyboard\n"
                "- Purpose: Hide Telegram quick-action buttons.\n"
                "- Params: none\n"
                "- Example: /hidekeyboard\n\n"
                "/latest\n"
                "- Purpose: Show latest active Workbench session.\n"
                "- Params: none\n"
                "- Example: /latest\n\n"
                "/newsession <symbol> <timeframe> [live|replay] [mt5|databento] [balance]\n"
                "- Purpose: Create a new Workbench session from Telegram and set it as default.\n"
                "- Params: symbol/timeframe required.\n"
                "- Example: /newsession XAUUSD M15 live mt5 10000\n\n"
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
                "/tp\n"
                "- Purpose: Manage open MT5 positions from Telegram (close full or take partial profit in USD).\n"
                "- Params: none\n"
                "- Example: /tp\n\n"
                "/identity master|apprentice [session_id]\n"
                "- Purpose: Switch agent personality preset.\n"
                "- Params: profile (required), optional session_id\n"
                "- Example: /identity master\n\n"
                "/strategy [name] [session_id]\n"
                "- Purpose: Show or set the active trading strategy profile used by Telegram /ask.\n"
                "- Params: optional strategy name, optional session_id\n"
                "- Example: /strategy liquidity\n\n"
                "/toolmode [all|parent|child] [session_id]\n"
                "- Purpose: Choose strategy tool mode (all=parent+child, parent=parent tool plus raw verification scans, child=granular tools).\n"
                "- Params: optional mode, optional session_id\n"
                "- Example: /toolmode parent\n\n"
                "/toolselect [autonomous|guided|minimal] [session_id]\n"
                "- Purpose: Choose tool-selection policy (autonomous=LLM decides, guided=intent-aware prune, minimal=core tools only).\n"
                "- Params: optional mode, optional session_id\n"
                "- Example: /toolselect guided\n\n"
                "/screener [strategy] [universe] [limit] [scan_tf] [exec_tf] [session_id]\n"
                "- Purpose: Run deterministic universal strategy screener (no LLM wait).\n"
                "- Params: optional; defaults to active strategy, market_mixed_top, 80, M15, M15.\n"
                "- Example: /screener trendilo market 80 M15 M5\n\n"
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

        if cmd_l in {"/menu", "/keyboard", "/showkeyboard"}:
            return "Quick-action keyboard enabled."

        if cmd_l in {"/hidekeyboard", "/hidekb"}:
            return "Quick-action keyboard hidden."

        if cmd_l in {"/siglot", "/signallot"}:
            if not args:
                return f"Current confirmation signal default lot: {float(self._confirm_signal_default_lot()):.4f}"
            lot = self._parse_positive_number(args[0])
            if lot is None:
                return "Usage: /siglot <positive_lot>"
            repo_root = Path(__file__).resolve().parents[3]
            env_path = repo_root / "dashboard" / ".env"
            try:
                lines = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
            except Exception:
                lines = []
            key = "TELEGRAM_CONFIRM_SIGNAL_DEFAULT_LOT"
            out_lines: List[str] = []
            replaced = False
            for line in lines:
                if str(line).strip().startswith(f"{key}="):
                    out_lines.append(f"{key}={float(lot):.4f}")
                    replaced = True
                else:
                    out_lines.append(str(line))
            if not replaced:
                out_lines.append(f"{key}={float(lot):.4f}")
            try:
                env_path.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")
            except Exception as exc:
                return f"Could not persist default signal lot: {type(exc).__name__}: {str(exc)[:140]}"
            return f"Confirmation signal default lot set to {float(lot):.4f}."

        if cmd_l in {"/latest", "/latestsession"}:
            return self._format_latest_session(chat_id)

        if cmd_l in {"/newsession", "/new"}:
            if len(args) < 2:
                return "Usage: /newsession <symbol> <timeframe> [live|replay] [mt5|databento] [balance]"
            symbol = str(args[0] or "").strip().upper()
            timeframe = str(args[1] or "").strip().upper()
            mode = str(args[2] or "live").strip().lower() if len(args) >= 3 else "live"
            source = str(args[3] or "mt5").strip().lower() if len(args) >= 4 else "mt5"
            try:
                balance = float(args[4]) if len(args) >= 5 else 10000.0
            except Exception:
                balance = 10000.0
            return self._create_workbench_session(
                chat_id=int(chat_id),
                symbol=symbol,
                timeframe=timeframe,
                mode=mode,
                source=source,
                initial_balance=float(balance),
            )

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

        if cmd_l in {"/tp", "/takeprofit", "/tpmanage"}:
            return self._start_live_tp_flow(int(chat_id))

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

        if cmd_l == "/strategy":
            sid = self._resolve_default_session_id(chat_id)
            if sid is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            if not args:
                _provider, _perms, cfg = self._resolve_provider_and_permissions(int(sid))
                try:
                    from ..api import simulation_routes as sim_routes

                    profile = sim_routes._normalize_agent_strategy_profile(
                        (cfg if isinstance(cfg, dict) else {}).get("agent_strategy_profile")
                    )
                    preset = sim_routes._normalize_agent_strategy_preset(
                        (cfg if isinstance(cfg, dict) else {}).get("agent_strategy_preset")
                    )
                except Exception:
                    profile = "classic_htf_fvg"
                    preset = "default"
                return (
                    f"Session #{int(sid)} strategy: {profile} | preset: {preset}\n"
                    f"{self._format_strategy_help()}"
                )
            profile_raw = str(args[0] or "").strip().lower()
            target_sid = int(sid)
            if profile_raw in {"show", "status"}:
                if len(args) >= 2 and str(args[1]).isdigit():
                    target_sid = int(args[1])
                _provider, _perms, cfg = self._resolve_provider_and_permissions(int(target_sid))
                try:
                    from ..api import simulation_routes as sim_routes

                    profile = sim_routes._normalize_agent_strategy_profile(
                        (cfg if isinstance(cfg, dict) else {}).get("agent_strategy_profile")
                    )
                    preset = sim_routes._normalize_agent_strategy_preset(
                        (cfg if isinstance(cfg, dict) else {}).get("agent_strategy_preset")
                    )
                except Exception:
                    profile = "classic_htf_fvg"
                    preset = "default"
                return f"Session #{int(target_sid)} strategy: {profile} | preset: {preset}"
            if profile_raw.isdigit():
                target_sid = int(profile_raw)
                _provider, _perms, cfg = self._resolve_provider_and_permissions(int(target_sid))
                try:
                    from ..api import simulation_routes as sim_routes

                    profile = sim_routes._normalize_agent_strategy_profile(
                        (cfg if isinstance(cfg, dict) else {}).get("agent_strategy_profile")
                    )
                    preset = sim_routes._normalize_agent_strategy_preset(
                        (cfg if isinstance(cfg, dict) else {}).get("agent_strategy_preset")
                    )
                except Exception:
                    profile = "classic_htf_fvg"
                    preset = "default"
                return f"Session #{int(target_sid)} strategy: {profile} | preset: {preset}"
            preset_raw = None
            if len(args) >= 2 and not str(args[1]).isdigit():
                preset_raw = args[1]
            if len(args) >= 2 and str(args[-1]).isdigit():
                target_sid = int(args[-1])
            return self._set_strategy_profile(target_sid, profile_raw, preset_raw)

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

        if cmd_l in {"/screener", "/scan"}:
            sid_default = self._resolve_default_session_id(chat_id)
            if sid_default is None:
                return "No active Workbench session found. Start one in dashboard, or use /use <session_id>."
            sid_tail, rest = self._extract_trailing_session_arg(args)
            target_sid = int(sid_tail) if sid_tail is not None else int(sid_default)
            strategy = str(rest[0] or "").strip().lower() if len(rest) >= 1 else self._active_scan_strategy(int(target_sid))
            universe = str(rest[1] or "market_mixed_top").strip().lower() if len(rest) >= 2 else "market_mixed_top"
            try:
                universe_limit = int(rest[2]) if len(rest) >= 3 else 80
            except Exception:
                universe_limit = 80
            scan_tf = str(rest[3] or "M15").strip().upper() if len(rest) >= 4 else "M15"
            exec_tf = str(rest[4] or scan_tf).strip().upper() if len(rest) >= 5 else scan_tf
            return self._run_strategy_screener(
                chat_id=int(chat_id),
                session_id=int(target_sid),
                strategy=str(strategy),
                universe=str(universe),
                universe_limit=int(universe_limit),
                timeframe=str(scan_tf),
                execution_timeframe=str(exec_tf),
                max_results=20,
            )

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
        channel_msg = upd.get("channel_post") if isinstance(upd.get("channel_post"), dict) else None
        if channel_msg is not None:
            chat = channel_msg.get("chat") if isinstance(channel_msg.get("chat"), dict) else {}
            text = str(channel_msg.get("text") or channel_msg.get("caption") or "").strip()
            if not text:
                return
            source_names = self._extract_message_source_names(channel_msg, chat)
            source_label = next((str(x) for x in source_names if str(x).strip()), str((chat or {}).get("title") or "channel"))
            msg_kind = self._classify_confirm_signal_message_for_sources(text, source_names=source_names)
            parsed = self._parse_confirmation_signal_for_sources(text, source_names=source_names) if msg_kind == "signal" else None
            target_chat = self._allowed_chat_id()
            if target_chat is None:
                try:
                    self._append_confirm_signal_feed(
                        source=str(source_label),
                        chat=chat if isinstance(chat, dict) else {},
                        text=str(text),
                        kind=str(msg_kind),
                        parsed=parsed,
                    )
                except Exception:
                    logger.exception("telegram channel_post feed capture failed")
                return
            try:
                handled = self._handle_confirmation_signal_message(
                    chat_id=int(target_chat),
                    msg=channel_msg,
                    chat=chat,
                    text=text,
                    push_only=True,
                )
                if handled is None:
                    # Signal handler ignored this message (e.g. source mismatch);
                    # still expose it in panel feed so operator can confirm ingestion.
                    self._append_confirm_signal_feed(
                        source=str(source_label),
                        chat=chat if isinstance(chat, dict) else {},
                        text=str(text),
                        kind=str(msg_kind),
                        parsed=parsed,
                    )
            except Exception:
                logger.exception("telegram channel_post signal handling failed")
            return
        cq = upd.get("callback_query") if isinstance(upd.get("callback_query"), dict) else None
        if cq is not None:
            msg = cq.get("message") if isinstance(cq.get("message"), dict) else {}
            chat = msg.get("chat") if isinstance(msg.get("chat"), dict) else {}
            chat_id = int(chat.get("id") or 0) if chat.get("id") is not None else 0
            if chat_id <= 0:
                return
            allowed = self._allowed_chat_id()
            if allowed is not None and int(chat_id) != int(allowed):
                logger.warning("telegram unauthorized callback chat_id=%s ignored", int(chat_id))
                return
            cbid = str(cq.get("id") or "").strip()
            data = str(cq.get("data") or "").strip()
            reply = "Unsupported callback action."
            markup = None
            try:
                if data.startswith("cb:"):
                    token = str(data.split(":", 1)[1] or "").strip()
                    action = self._consume_callback_action(int(chat_id), token)
                    if not isinstance(action, dict):
                        reply = "Action expired. Run the command again."
                    else:
                        reply, markup = self._execute_callback_action(int(chat_id), action)
                elif data.startswith("ytq|"):
                    reply, markup = self._handle_external_quick_trade_callback(int(chat_id), data)
            except Exception as exc:
                logger.exception("telegram callback handling failed")
                reply = f"Callback failed: {type(exc).__name__}: {str(exc)[:180]}"
                markup = None
            finally:
                if cbid:
                    try:
                        self._tg_request(
                            "answerCallbackQuery",
                            params={"callback_query_id": cbid, "text": str(reply or "OK")[:120]},
                            timeout_sec=10.0,
                            http_method="POST",
                        )
                    except Exception:
                        pass
            self._send_text(chat_id, reply, reply_markup=markup)
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
        signal_reply = None
        try:
            signal_handled = self._handle_confirmation_signal_message(
                chat_id=int(chat_id),
                msg=msg,
                chat=chat,
                text=text,
                push_only=False,
            )
            if isinstance(signal_handled, str):
                signal_reply = signal_handled
        except Exception:
            logger.exception("telegram confirmation signal handling failed")
            signal_reply = None
        if isinstance(signal_reply, str) and signal_reply.strip():
            self._send_text(chat_id, signal_reply, reply_markup=None)
            return
        parts = text.split()
        cmd_raw = str(parts[0] if parts else "").strip()
        cmd_norm = str(cmd_raw.split("@", 1)[0] if cmd_raw else "").strip().lower()
        args = parts[1:] if len(parts) > 1 else []
        try:
            reply = self._handle_text(chat_id, text)
        except Exception as exc:
            logger.exception("telegram command handling failed")
            reply = f"Command failed: {type(exc).__name__}: {str(exc)[:180]}"
        reply_markup: Optional[Dict[str, Any]] = None
        if cmd_norm in {"/hidekeyboard", "/hidekb"}:
            reply_markup = {"remove_keyboard": True, "selective": False}
            self._send_text(chat_id, reply, reply_markup=reply_markup)
            return
        if self._keyboard_enabled() and cmd_norm in {"/start", "/help", "/menu", "/keyboard", "/showkeyboard"}:
            reply_markup = self._main_reply_keyboard()
            self._send_text(chat_id, reply, reply_markup=reply_markup)
            return
        if cmd_norm in {"/latest", "/latestsession"}:
            m = re.search(r"#(\d+)", str(reply))
            if m:
                try:
                    reply_markup = self._build_session_inline_keyboard(int(chat_id), int(m.group(1)))
                except Exception:
                    reply_markup = None
        elif cmd_norm == "/triggers":
            sid_arg, _rest = self._extract_session_arg(args)
            sid = int(sid_arg) if sid_arg is not None else int(self._resolve_default_session_id(int(chat_id)) or 0)
            if sid > 0:
                reply_markup = self._build_triggers_inline_keyboard(int(chat_id), int(sid))
        elif cmd_norm in {"/screener", "/scan"}:
            sid_tail, _rest = self._extract_trailing_session_arg(args)
            sid = int(sid_tail) if sid_tail is not None else int(self._resolve_default_session_id(int(chat_id)) or 0)
            if sid > 0:
                reply_markup = self._build_screener_inline_keyboard(int(chat_id), int(sid))
        elif cmd_norm == "/ask" or not cmd_norm.startswith("/"):
            reply_markup = self._build_pending_inline_keyboard(int(chat_id))
        override_markup = self._pop_next_reply_markup(int(chat_id))
        if isinstance(override_markup, dict) and override_markup:
            reply_markup = override_markup
        self._send_text(chat_id, reply, reply_markup=reply_markup)

    def _poll_once(self) -> None:
        timeout = max(1.0, min(25.0, self._poll_interval_sec()))
        params = {
            "timeout": int(timeout),
            "offset": int(self._offset),
            "allowed_updates": '["message","callback_query","channel_post"]',
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
                self._warn_throttled(
                    "telegram_poll_failed",
                    f"Telegram bridge poll failed: {str(exc)[:220]}",
                    min_interval_sec=max(10.0, self._poll_interval_sec() * 5.0),
                )
                # Backoff on transient Telegram API failures.
                self._stop.wait(max(1.0, self._poll_interval_sec()))
                continue
            try:
                self._push_watchdog_alerts()
            except Exception as exc:
                logger.warning("Telegram watchdog push failed: %s", str(exc)[:220])
            try:
                self._push_pending_entry_signals()
            except Exception as exc:
                logger.warning("Telegram pending-entry push failed: %s", str(exc)[:220])
            try:
                self._push_confirmation_signal_ladders()
            except Exception as exc:
                logger.warning("Telegram confirmation ladder push failed: %s", str(exc)[:220])
            try:
                self._process_indicator_reversal_pending_replays()
            except Exception as exc:
                logger.warning("Telegram reversal replay push failed: %s", str(exc)[:220])
            try:
                self._push_deadzone_colorflip_alerts()
            except Exception as exc:
                logger.warning("Telegram deadzone colorflip push failed: %s", str(exc)[:220])
        logger.info("Telegram bridge service loop stopped")

    def _maintenance_loop(self) -> None:
        """
        Lightweight runtime loop when Telegram bot polling is disabled/unavailable.
        Keeps confirmation entry+ladder engines alive for external channel listener.
        """
        logger.info("Telegram bridge maintenance loop started")
        while not self._stop.is_set():
            try:
                self._push_pending_entry_signals()
            except Exception as exc:
                logger.warning("Telegram pending-entry push failed (maintenance): %s", str(exc)[:220])
            try:
                self._push_confirmation_signal_ladders()
            except Exception as exc:
                logger.warning("Telegram confirmation ladder push failed (maintenance): %s", str(exc)[:220])
            try:
                self._process_indicator_reversal_pending_replays()
            except Exception as exc:
                logger.warning("Telegram reversal replay push failed (maintenance): %s", str(exc)[:220])
            # Keep cadence tight so TP stages react quickly.
            self._stop.wait(1.0)
        logger.info("Telegram bridge maintenance loop stopped")

    def _entry_watch_loop(self) -> None:
        """
        High-frequency pending-entry watcher.
        Runs independently from Telegram polling so fast zone touches are not missed.
        """
        logger.info("Telegram bridge entry-watch loop started")
        while not self._stop.is_set():
            try:
                self._push_pending_entry_signals()
            except Exception as exc:
                logger.warning("Telegram pending-entry push failed (entry-watch): %s", str(exc)[:220])
            # Dynamic pacing: tight when queue exists, relaxed otherwise.
            with self._lock:
                has_pending = bool(self._pending_entry_signals)
            base = float(self._confirm_signal_entry_watch_interval_sec())
            sleep_sec = float(base if has_pending else max(0.5, base))
            self._stop.wait(max(0.05, sleep_sec))
        logger.info("Telegram bridge entry-watch loop stopped")

    def start(self) -> None:
        if (self._thread and self._thread.is_alive()) or (self._entry_watch_thread and self._entry_watch_thread.is_alive()):
            return
        profile = self._active_profile()
        run_polling = bool(self._enabled())
        run_signal_engines = bool(self._confirm_signal_enabled())
        if run_polling:
            token = self._token()
            allowed = self._allowed_chat_id()
            if not token:
                scoped = self._profile_scoped_key("TELEGRAM_BOT_TOKEN", profile)
                logger.warning(
                    "Telegram bridge polling unavailable: TELEGRAM_BOT_TOKEN missing (profile=%s, scoped_key=%s)",
                    str(profile),
                    str(scoped or "none"),
                )
                run_polling = False
            if allowed is None:
                scoped = self._profile_scoped_key("TELEGRAM_ALLOWED_CHAT_ID", profile)
                logger.warning(
                    "Telegram bridge polling unavailable: TELEGRAM_ALLOWED_CHAT_ID missing/invalid (profile=%s, scoped_key=%s)",
                    str(profile),
                    str(scoped or "none"),
                )
                run_polling = False
        self._stop.clear()
        if run_signal_engines:
            self._entry_watch_thread = threading.Thread(target=self._entry_watch_loop, daemon=True, name="telegram-bridge-entry-watch")
            self._entry_watch_thread.start()
        if run_polling:
            self._prepare_polling()
            self._thread = threading.Thread(target=self._loop, daemon=True, name="telegram-bridge")
            self._thread.start()
            logger.info("Telegram bridge polling started (profile=%s)", str(profile))
            return

        if run_signal_engines:
            self._thread = threading.Thread(target=self._maintenance_loop, daemon=True, name="telegram-bridge-maint")
            self._thread.start()
            logger.info("Telegram bridge maintenance mode started (confirmation ladder only)")
            return

        logger.info("Telegram bridge disabled (no polling and confirmation automation off)")

    def stop(self) -> None:
        self._stop.set()
        th = self._thread
        ew = self._entry_watch_thread
        if th and th.is_alive():
            th.join(timeout=5.0)
        if ew and ew.is_alive():
            ew.join(timeout=5.0)
        self._thread = None
        self._entry_watch_thread = None
        with self._lock:
            self._indicator_reversal_replay_inflight.clear()
        logger.info("Telegram bridge service stopped")


