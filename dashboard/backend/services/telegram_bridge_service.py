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

from .live_service import LiveTradingService
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

    def _warn_throttled(self, key: str, message: str, *, min_interval_sec: float = 30.0) -> None:
        now_ts = time.time()
        k = str(key or "warn")
        if k != self._last_warn_key or (now_ts - float(self._last_warn_at)) >= float(min_interval_sec):
            logger.warning("%s", message)
            self._last_warn_key = k
            self._last_warn_at = now_ts

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
            sid_default = self._resolve_default_session_id(int(chat_id))
            if sid_default is not None:
                row = db.query(SimulationSession).get(int(sid_default))
                if row is not None and str(row.strategy_id or "") == "_workbench":
                    row_sym = str(row.symbol or "").strip().upper()
                    row_tf = str(row.timeframe or "").strip().upper()
                    row_mode = str(getattr(row, "mode", "") or "").strip().lower()
                    if row_sym == sym and (not tf or row_tf == tf) and row_mode == "live":
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
                if rs == sym and rt == tf and rm == "live":
                    return int(r.id), "active_live_symbol_tf_match"
            for r in rows:
                rs = str(getattr(r, "symbol", "") or "").strip().upper()
                rt = str(getattr(r, "timeframe", "") or "").strip().upper()
                if rs == sym and rt == tf:
                    return int(r.id), "active_symbol_tf_match"
            for r in rows:
                rs = str(getattr(r, "symbol", "") or "").strip().upper()
                rm = str(getattr(r, "mode", "") or "").strip().lower()
                if rs == sym and rm == "live":
                    return int(r.id), "active_live_symbol_match"
            for r in rows:
                rs = str(getattr(r, "symbol", "") or "").strip().upper()
                if rs == sym:
                    return int(r.id), "active_symbol_match"
            return None, "no_session_for_symbol"
        finally:
            try:
                db.close()
            except Exception:
                pass

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
    ) -> Dict[str, Any]:
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        md = str(mode or "live").strip().lower()
        src = str(source or "mt5").strip().lower()
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
                    # Default new Telegram sessions to paper execution.
                    # Users can explicitly switch to live_mt5 later.
                    "use_active_account": bool(src == "mt5"),
                    "execution_mode": "paper",
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
            "allowed_updates": '["message","callback_query"]',
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
                self._push_deadzone_colorflip_alerts()
            except Exception as exc:
                logger.warning("Telegram deadzone colorflip push failed: %s", str(exc)[:220])
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
