"""
Telegram user-account channel listener service (Telethon-based).

Purpose:
- Read channel messages even when bot cannot be added as admin.
- Forward ingested messages to TelegramBridgeService automation pipeline.
"""

from __future__ import annotations

import asyncio
import logging
import math
import os
import re
import threading
import time
import unicodedata
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple


logger = logging.getLogger(__name__)


class TelegramUserListenerService:
    def __init__(self, on_message: Callable[..., None]) -> None:
        self._on_message = on_message
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._lock = threading.RLock()
        self._running: bool = False
        self._last_error: str = ""
        self._last_tick_iso: str = ""
        self._last_seen_msg_id: Dict[str, int] = {}
        self._pending_phone_hash_by_phone: Dict[str, str] = {}
        self._resolved_channels: List[Dict[str, Any]] = []
        self._skipped_specs: List[Dict[str, Any]] = []
        self._forward_total: int = 0
        self._forward_ok: int = 0
        self._forward_fail: int = 0
        self._last_forward_iso: str = ""
        self._last_forward_error: str = ""
        self._last_forward_source: str = ""
        self._last_forward_message_id: int = 0

    @staticmethod
    def _read_env_file_value(var_name: str) -> Optional[str]:
        repo_root = Path(__file__).resolve().parents[3]
        candidates = [repo_root / "dashboard" / ".env", repo_root / ".env"]
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
    def _get_env_value(cls, name: str, default: str = "") -> str:
        key = str(name or "").strip()
        if not key:
            return str(default or "")
        # Telegram settings from dashboard/.env first.
        fv = str(cls._read_env_file_value(key) or "").strip()
        if fv:
            return fv
        v = str(os.getenv(key) or "").strip()
        if v:
            return v
        return str(default or "")

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

    @staticmethod
    def _import_telethon():
        try:
            from telethon import TelegramClient  # type: ignore
            from telethon.errors import SessionPasswordNeededError  # type: ignore
            return TelegramClient, SessionPasswordNeededError, None
        except Exception as exc:
            return None, None, exc

    @staticmethod
    def _norm_lookup(value: Any) -> str:
        raw = str(value or "").strip()
        if not raw:
            return ""
        norm = unicodedata.normalize("NFKC", raw)
        norm = " ".join(norm.split())
        return str(norm).strip().lower()

    @staticmethod
    def _now_iso() -> str:
        return datetime.now(timezone.utc).isoformat()

    @classmethod
    def _enabled(cls) -> bool:
        v = str(cls._get_env_value("TELEGRAM_USER_LISTENER_ENABLED", "0")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @classmethod
    def _api_id(cls) -> int:
        try:
            return int(float(cls._get_env_value("TELEGRAM_USER_API_ID", "0")))
        except Exception:
            return 0

    @classmethod
    def _api_hash(cls) -> str:
        return str(cls._get_env_value("TELEGRAM_USER_API_HASH", "")).strip()

    @classmethod
    def _session_path(cls) -> str:
        raw = str(cls._get_env_value("TELEGRAM_USER_SESSION_PATH", "dashboard/data/telegram_user_listener")).strip()
        return raw or "dashboard/data/telegram_user_listener"

    @classmethod
    def _channels(cls) -> List[str]:
        raw = str(cls._get_env_value("TELEGRAM_USER_CHANNELS", "")).strip()
        items = [str(x).strip() for x in raw.split("|") if str(x).strip()]
        return items

    @classmethod
    def _poll_sec(cls) -> float:
        try:
            raw = float(cls._get_env_value("TELEGRAM_USER_POLL_SEC", "3"))
        except Exception:
            raw = 3.0
        if not math.isfinite(float(raw)):
            raw = 3.0
        return float(max(1.0, min(30.0, float(raw))))

    @classmethod
    def _skip_history_on_start(cls) -> bool:
        v = str(cls._get_env_value("TELEGRAM_USER_SKIP_HISTORY_ON_START", "1")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @classmethod
    def _feed_backfill_count(cls) -> int:
        try:
            raw = int(float(cls._get_env_value("TELEGRAM_USER_FEED_BACKFILL_COUNT", "8")))
        except Exception:
            raw = 8
        return int(max(0, min(50, raw)))

    @classmethod
    def _feed_backfill_hours(cls) -> float:
        try:
            raw = float(cls._get_env_value("TELEGRAM_USER_FEED_BACKFILL_HOURS", "24"))
        except Exception:
            raw = 24.0
        if not math.isfinite(float(raw)):
            raw = 24.0
        return float(max(1.0, min(168.0, float(raw))))

    @classmethod
    def _feed_backfill_max_messages(cls) -> int:
        try:
            raw = int(float(cls._get_env_value("TELEGRAM_USER_FEED_BACKFILL_MAX_MESSAGES", "2000")))
        except Exception:
            raw = 2000
        return int(max(100, min(10000, int(raw))))

    def status(self) -> Dict[str, Any]:
        _client, _pwd, telethon_err = self._import_telethon()
        pipeline_connected = bool(callable(self._on_message))
        pipeline_target = ""
        try:
            if pipeline_connected:
                pipeline_target = f"{getattr(self._on_message, '__module__', '')}.{getattr(self._on_message, '__qualname__', getattr(self._on_message, '__name__', 'callback'))}"
        except Exception:
            pipeline_target = "callback"
        with self._lock:
            running = bool(self._running)
            last_error = str(self._last_error or "")
            last_tick = str(self._last_tick_iso or "")
            resolved = [dict(x) for x in self._resolved_channels]
            skipped = [dict(x) for x in self._skipped_specs]
            forward_total = int(self._forward_total)
            forward_ok = int(self._forward_ok)
            forward_fail = int(self._forward_fail)
            last_forward_iso = str(self._last_forward_iso or "")
            last_forward_error = str(self._last_forward_error or "")
            last_forward_source = str(self._last_forward_source or "")
            last_forward_message_id = int(self._last_forward_message_id or 0)
        return {
            "ok": True,
            "enabled": bool(self._enabled()),
            "running": running,
            "telethon_available": telethon_err is None,
            "telethon_error": (None if telethon_err is None else f"{type(telethon_err).__name__}: {str(telethon_err)[:180]}"),
            "pipeline_connected": pipeline_connected,
            "pipeline_target": str(pipeline_target),
            "api_id_set": bool(self._api_id() > 0),
            "api_hash_set": bool(bool(self._api_hash())),
            "session_path": str(self._session_path()),
            "channels": list(self._channels()),
            "poll_sec": float(self._poll_sec()),
            "skip_history_on_start": bool(self._skip_history_on_start()),
            "feed_backfill_count": int(self._feed_backfill_count()),
            "feed_backfill_hours": float(self._feed_backfill_hours()),
            "feed_backfill_max_messages": int(self._feed_backfill_max_messages()),
            "last_error": last_error,
            "last_tick": last_tick,
            "forward_total": forward_total,
            "forward_ok": forward_ok,
            "forward_fail": forward_fail,
            "last_forward": last_forward_iso,
            "last_forward_error": last_forward_error,
            "last_forward_source": last_forward_source,
            "last_forward_message_id": last_forward_message_id,
            "resolved_channels": resolved,
            "skipped_specs": skipped,
        }

    def update_config(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        p = payload if isinstance(payload, dict) else {}
        updates: Dict[str, Any] = {}
        if "enabled" in p:
            updates["TELEGRAM_USER_LISTENER_ENABLED"] = "1" if bool(p.get("enabled")) else "0"
        if "api_id" in p:
            try:
                api_id = int(float(p.get("api_id")))
            except Exception:
                api_id = 0
            updates["TELEGRAM_USER_API_ID"] = str(max(0, api_id))
        if "api_hash" in p:
            updates["TELEGRAM_USER_API_HASH"] = str(p.get("api_hash") or "").strip()
        if "session_path" in p:
            updates["TELEGRAM_USER_SESSION_PATH"] = str(p.get("session_path") or "").strip()
        if "channels" in p:
            ch_raw = p.get("channels")
            channels: List[str] = []
            if isinstance(ch_raw, str):
                channels = [str(x).strip() for x in ch_raw.splitlines() if str(x).strip()]
            elif isinstance(ch_raw, list):
                channels = [str(x).strip() for x in ch_raw if str(x).strip()]
            updates["TELEGRAM_USER_CHANNELS"] = "|".join(channels)
        if "poll_sec" in p:
            try:
                sec = float(p.get("poll_sec"))
            except Exception:
                sec = 3.0
            sec = max(1.0, min(30.0, sec))
            updates["TELEGRAM_USER_POLL_SEC"] = f"{sec:.1f}"
        if "skip_history_on_start" in p:
            updates["TELEGRAM_USER_SKIP_HISTORY_ON_START"] = "1" if bool(p.get("skip_history_on_start")) else "0"
        if "feed_backfill_count" in p:
            try:
                cnt = int(float(p.get("feed_backfill_count")))
            except Exception:
                cnt = 8
            updates["TELEGRAM_USER_FEED_BACKFILL_COUNT"] = str(int(max(0, min(50, cnt))))
        if "feed_backfill_hours" in p:
            try:
                hrs = float(p.get("feed_backfill_hours"))
            except Exception:
                hrs = 24.0
            updates["TELEGRAM_USER_FEED_BACKFILL_HOURS"] = f"{float(max(1.0, min(168.0, hrs))):.2f}"
        if "feed_backfill_max_messages" in p:
            try:
                mx = int(float(p.get("feed_backfill_max_messages")))
            except Exception:
                mx = 2000
            updates["TELEGRAM_USER_FEED_BACKFILL_MAX_MESSAGES"] = str(int(max(100, min(10000, mx))))
        ok, status = self._upsert_env_values(updates)
        # Apply runtime state immediately after config persist.
        if self.is_running():
            self.stop()
        if self._enabled():
            self.start()
        out = self.status()
        out["persist_ok"] = bool(ok)
        out["persist_status"] = str(status)
        out["updated"] = {str(k): str(v) for k, v in updates.items()}
        return out

    def is_running(self) -> bool:
        with self._lock:
            return bool(self._running)

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        if not self._enabled():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run_thread, daemon=True, name="telegram-user-listener")
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        t = self._thread
        if t is not None and t.is_alive():
            t.join(timeout=10.0)
        self._thread = None
        with self._lock:
            self._running = False

    def _set_error(self, value: str) -> None:
        with self._lock:
            self._last_error = str(value or "")

    def _touch(self) -> None:
        with self._lock:
            self._last_tick_iso = self._now_iso()

    def _forward_message(self, **kwargs: Any) -> None:
        source_title = str(kwargs.get("source_title") or "").strip()
        try:
            self._on_message(**kwargs)
            with self._lock:
                self._forward_total += 1
                self._forward_ok += 1
                self._last_forward_iso = self._now_iso()
                self._last_forward_error = ""
                self._last_forward_source = source_title
                self._last_forward_message_id = int(kwargs.get("source_message_id") or 0)
        except TypeError:
            # Backward-compatible callback signature.
            fallback = {
                "source_title": kwargs.get("source_title"),
                "text": kwargs.get("text"),
                "source_username": kwargs.get("source_username"),
                "source_id": kwargs.get("source_id"),
            }
            try:
                self._on_message(**fallback)
                with self._lock:
                    self._forward_total += 1
                    self._forward_ok += 1
                    self._last_forward_iso = self._now_iso()
                    self._last_forward_error = ""
                    self._last_forward_source = source_title
                    self._last_forward_message_id = int(kwargs.get("source_message_id") or 0)
            except Exception as exc:
                with self._lock:
                    self._forward_total += 1
                    self._forward_fail += 1
                    self._last_forward_iso = self._now_iso()
                    self._last_forward_error = f"{type(exc).__name__}: {str(exc)[:140]}"
                    self._last_forward_source = source_title
                    self._last_forward_message_id = int(kwargs.get("source_message_id") or 0)
                raise
        except Exception as exc:
            with self._lock:
                self._forward_total += 1
                self._forward_fail += 1
                self._last_forward_iso = self._now_iso()
                self._last_forward_error = f"{type(exc).__name__}: {str(exc)[:140]}"
                self._last_forward_source = source_title
                self._last_forward_message_id = int(kwargs.get("source_message_id") or 0)
            raise

    def _run_thread(self) -> None:
        try:
            asyncio.run(self._run_loop())
        except Exception as exc:
            self._set_error(f"listener_crashed:{type(exc).__name__}:{str(exc)[:220]}")
            logger.exception("telegram_user_listener_crashed")
        finally:
            with self._lock:
                self._running = False

    async def _run_loop(self) -> None:
        TelegramClient, _SessionPasswordNeededError, telethon_err = self._import_telethon()
        if TelegramClient is None:
            self._set_error(f"telethon_import_failed:{type(telethon_err).__name__}:{str(telethon_err)[:180]}")
            return
        api_id = int(self._api_id())
        api_hash = str(self._api_hash())
        channels = list(self._channels())
        if api_id <= 0 or not api_hash:
            self._set_error("missing_user_api_credentials")
            return
        if not channels:
            self._set_error("no_channels_configured")
            return
        session_path = str(self._session_path())
        client = TelegramClient(session_path, api_id, api_hash)
        await client.connect()
        try:
            if not await client.is_user_authorized():
                self._set_error("user_session_not_authorized")
                return
            entities: Dict[str, Any] = {}
            resolved_rows: List[Dict[str, Any]] = []
            skipped_rows: List[Dict[str, Any]] = []
            with self._lock:
                self._running = True
                self._last_error = ""
                self._resolved_channels = []
                self._skipped_specs = []
            for ch in channels:
                try:
                    ent = await self._resolve_channel_entity(client, ch)
                    if ent is None:
                        skipped_rows.append({"spec": str(ch), "reason": "not_found"})
                        continue
                    entities[str(ch)] = ent
                    resolved_rows.append(
                        {
                            "spec": str(ch),
                            "id": int(getattr(ent, "id", 0) or 0),
                            "title": str(getattr(ent, "title", "") or ""),
                            "username": str(getattr(ent, "username", "") or ""),
                        }
                    )
                except Exception as exc:
                    logger.warning("telegram_user_listener_channel_resolve_failed channel=%s err=%s", str(ch), str(exc)[:160])
                    skipped_rows.append({"spec": str(ch), "reason": f"resolve_failed:{type(exc).__name__}"})
            with self._lock:
                self._resolved_channels = list(resolved_rows)
                self._skipped_specs = list(skipped_rows)
            if not entities:
                self._set_error("no_resolved_channels")
                return
            if self._skip_history_on_start():
                for _key, ent in list(entities.items()):
                    try:
                        backfill = int(self._feed_backfill_count())
                        backfill_hours = float(self._feed_backfill_hours())
                        backfill_max = int(self._feed_backfill_max_messages())
                        if backfill > 0:
                            cutoff = datetime.now(timezone.utc) - timedelta(hours=float(backfill_hours))
                            hist_rows: List[Any] = []
                            async for hm in client.iter_messages(ent, limit=int(backfill_max)):
                                hdate = getattr(hm, "date", None)
                                if isinstance(hdate, datetime):
                                    hd = hdate if hdate.tzinfo is not None else hdate.replace(tzinfo=timezone.utc)
                                    if hd < cutoff:
                                        break
                                hist_rows.append(hm)
                            for hm in reversed(hist_rows):
                                htext = str(getattr(hm, "message", "") or "")
                                if not htext:
                                    htext = str(getattr(hm, "raw_text", "") or "")
                                if not htext:
                                    continue
                                title = str(getattr(ent, "title", "") or _key)
                                username = str(getattr(ent, "username", "") or "")
                                hmid = int(getattr(hm, "id", 0) or 0)
                                try:
                                    self._forward_message(
                                        source_title=title,
                                        text=htext,
                                        source_username=(username or None),
                                        source_id=int(getattr(ent, "id", 0) or 0),
                                        feed_only=True,
                                        source_message_ts=getattr(hm, "date", None),
                                        source_message_id=int(hmid),
                                    )
                                except Exception:
                                    logger.exception("telegram_user_listener_history_feed_failed")
                        latest = await client.get_messages(ent, limit=1)
                        if latest:
                            m0 = latest[0]
                            mid0 = int(getattr(m0, "id", 0) or 0)
                            if mid0 > 0:
                                eid0 = str(getattr(ent, "id", _key))
                                self._last_seen_msg_id[eid0] = int(mid0)
                    except Exception:
                        continue
            started_at_utc = datetime.now(timezone.utc)
            while not self._stop.is_set():
                for key, ent in list(entities.items()):
                    try:
                        msgs = await client.get_messages(ent, limit=40)
                        eid = str(getattr(ent, "id", key))
                        last_seen = int(self._last_seen_msg_id.get(eid, 0))
                        for m in reversed(list(msgs or [])):
                            mid = int(getattr(m, "id", 0) or 0)
                            if mid <= 0 or mid <= last_seen:
                                continue
                            mdate = getattr(m, "date", None)
                            try:
                                if isinstance(mdate, datetime):
                                    md = mdate if mdate.tzinfo is not None else mdate.replace(tzinfo=timezone.utc)
                                    if md < started_at_utc:
                                        self._last_seen_msg_id[eid] = int(max(self._last_seen_msg_id.get(eid, 0), mid))
                                        continue
                            except Exception:
                                pass
                            text = str(getattr(m, "message", "") or "")
                            if not text:
                                text = str(getattr(m, "raw_text", "") or "")
                            if not text:
                                # Keep media-only messages out for now.
                                self._last_seen_msg_id[eid] = int(max(self._last_seen_msg_id.get(eid, 0), mid))
                                continue
                            title = str(getattr(ent, "title", "") or key)
                            username = str(getattr(ent, "username", "") or "")
                            try:
                                self._forward_message(
                                    source_title=title,
                                    text=text,
                                    source_username=(username or None),
                                    source_id=int(getattr(ent, "id", 0) or 0),
                                    source_message_ts=getattr(m, "date", None),
                                    source_message_id=int(mid),
                                )
                            except Exception:
                                logger.exception("telegram_user_listener_on_message_failed")
                            self._last_seen_msg_id[eid] = int(max(self._last_seen_msg_id.get(eid, 0), mid))
                    except Exception as exc:
                        self._set_error(f"poll_channel_failed:{str(key)}:{type(exc).__name__}:{str(exc)[:120]}")
                self._touch()
                await asyncio.sleep(float(self._poll_sec()))
        finally:
            try:
                await client.disconnect()
            except Exception:
                pass

    @staticmethod
    def _is_supported_entity(ent: Any) -> bool:
        # Flexible mode: accept channels, groups, and user dialogs.
        return ent is not None

    async def _resolve_channel_entity(self, client: Any, spec_raw: Any) -> Optional[Any]:
        spec = str(spec_raw or "").strip()
        if not spec:
            return None
        spec_norm = self._norm_lookup(spec)
        candidates: List[str] = []
        if spec:
            candidates.append(spec)
        m = re.search(r"t\.me/([A-Za-z0-9_+]+)", spec, flags=re.IGNORECASE)
        if m:
            slug = str(m.group(1) or "").strip()
            if slug:
                candidates.append(slug)
                if not slug.startswith("+"):
                    candidates.append(f"@{slug}")
        if spec.startswith("@"):
            candidates.append(spec[1:])
        ent = None
        for cand in candidates:
            try:
                ent = await client.get_entity(cand)
                if self._is_supported_entity(ent):
                    return ent
            except Exception:
                ent = None
        # Fallback: match dialog title for cases where user entered display title.
        needle = str(spec_norm).replace("@", "").strip()
        if not needle:
            return None
        try:
            async for dlg in client.iter_dialogs():
                e = getattr(dlg, "entity", None)
                if not self._is_supported_entity(e):
                    continue
                title = self._norm_lookup(getattr(e, "title", ""))
                username = self._norm_lookup(getattr(e, "username", ""))
                dlg_name = self._norm_lookup(getattr(dlg, "name", ""))
                first_name = self._norm_lookup(getattr(e, "first_name", ""))
                last_name = self._norm_lookup(getattr(e, "last_name", ""))
                full_name = self._norm_lookup(f"{first_name} {last_name}".strip())
                if title == needle or username == needle or needle in title:
                    return e
                if dlg_name == needle or needle in dlg_name:
                    return e
                if first_name == needle or last_name == needle or full_name == needle:
                    return e
        except Exception:
            return None
        return None

    def send_login_code(self, phone: str) -> Dict[str, Any]:
        was_running = bool(self.is_running())
        if was_running:
            self.stop()
        try:
            return asyncio.run(self._send_login_code_async(phone))
        finally:
            if was_running and self._enabled():
                self.start()

    async def _send_login_code_async(self, phone: str) -> Dict[str, Any]:
        TelegramClient, _SessionPasswordNeededError, telethon_err = self._import_telethon()
        if TelegramClient is None:
            return {"ok": False, "error": f"telethon_import_failed:{type(telethon_err).__name__}"}
        api_id = int(self._api_id())
        api_hash = str(self._api_hash())
        if api_id <= 0 or not api_hash:
            return {"ok": False, "error": "missing_user_api_credentials"}
        ph = str(phone or "").strip()
        if not ph:
            return {"ok": False, "error": "missing_phone"}
        client = TelegramClient(str(self._session_path()), api_id, api_hash)
        await client.connect()
        try:
            sent = await client.send_code_request(ph)
            code_hash = str(getattr(sent, "phone_code_hash", "") or "").strip()
            with self._lock:
                self._pending_phone_hash_by_phone[ph] = code_hash
            return {"ok": True, "phone": ph}
        except Exception as exc:
            return {"ok": False, "error": f"send_code_failed:{type(exc).__name__}:{str(exc)[:180]}"}
        finally:
            try:
                await client.disconnect()
            except Exception:
                pass

    def verify_login_code(self, phone: str, code: str, password: Optional[str] = None) -> Dict[str, Any]:
        was_running = bool(self.is_running())
        if was_running:
            self.stop()
        try:
            return asyncio.run(self._verify_login_code_async(phone=phone, code=code, password=password))
        finally:
            if was_running and self._enabled():
                self.start()

    async def _verify_login_code_async(self, *, phone: str, code: str, password: Optional[str]) -> Dict[str, Any]:
        TelegramClient, SessionPasswordNeededError, telethon_err = self._import_telethon()
        if TelegramClient is None:
            return {"ok": False, "error": f"telethon_import_failed:{type(telethon_err).__name__}"}
        api_id = int(self._api_id())
        api_hash = str(self._api_hash())
        if api_id <= 0 or not api_hash:
            return {"ok": False, "error": "missing_user_api_credentials"}
        ph = str(phone or "").strip()
        pin = str(code or "").strip()
        if not ph or not pin:
            return {"ok": False, "error": "missing_phone_or_code"}
        with self._lock:
            code_hash = str(self._pending_phone_hash_by_phone.get(ph) or "").strip()
        client = TelegramClient(str(self._session_path()), api_id, api_hash)
        await client.connect()
        try:
            try:
                if code_hash:
                    await client.sign_in(phone=ph, code=pin, phone_code_hash=code_hash)
                else:
                    await client.sign_in(phone=ph, code=pin)
            except SessionPasswordNeededError:
                pwd = str(password or "").strip()
                if not pwd:
                    return {"ok": False, "error": "password_required"}
                await client.sign_in(password=pwd)
            ok = bool(await client.is_user_authorized())
            if ok:
                with self._lock:
                    self._pending_phone_hash_by_phone.pop(ph, None)
                return {"ok": True, "authorized": True}
            return {"ok": False, "error": "not_authorized"}
        except Exception as exc:
            return {"ok": False, "error": f"verify_code_failed:{type(exc).__name__}:{str(exc)[:180]}"}
        finally:
            try:
                await client.disconnect()
            except Exception:
                pass
