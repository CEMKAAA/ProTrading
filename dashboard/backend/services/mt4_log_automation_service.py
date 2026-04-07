"""
MT4 Log Automation Service

Reads MT4 terminal logs, discovers indicator activity, and exposes
indicator-level automation toggles for downstream strategy workflows.
"""

from __future__ import annotations

import logging
import math
import os
import re
import threading
import time
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Callable


logger = logging.getLogger(__name__)


class MT4LogAutomationService:
    def __init__(self, on_indicator_signal: Optional[Callable[..., None]] = None) -> None:
        self._on_indicator_signal = on_indicator_signal
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._lock = threading.RLock()

        self._running: bool = False
        self._last_error: str = ""
        self._last_tick_iso: str = ""

        self._events: List[Dict[str, Any]] = []
        self._events_max: int = 5000
        self._event_next_id: int = 0

        self._indicator_logs: Dict[str, List[Dict[str, Any]]] = {}
        self._indicator_stats: Dict[str, Dict[str, Any]] = {}
        self._file_offsets: Dict[str, int] = {}

        self._forward_total: int = 0
        self._forward_ok: int = 0
        self._forward_fail: int = 0
        self._last_forward_iso: str = ""
        self._last_forward_indicator: str = ""
        self._last_forward_error: str = ""
        self._forward_skip_stale: int = 0
        self._forward_skip_duplicate: int = 0
        self._forward_seen_keys: Dict[str, float] = {}

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
            if not key.startswith("MT4_LOG_AUTOMATION_"):
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
    def _enabled(cls) -> bool:
        v = str(cls._get_env_value("MT4_LOG_AUTOMATION_ENABLED", "0")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @classmethod
    def _data_path(cls) -> str:
        return str(cls._get_env_value("MT4_LOG_AUTOMATION_DATA_PATH", "")).strip()

    @classmethod
    def _poll_sec(cls) -> float:
        try:
            raw = float(cls._get_env_value("MT4_LOG_AUTOMATION_POLL_SEC", "2"))
        except Exception:
            raw = 2.0
        if not math.isfinite(float(raw)):
            raw = 2.0
        return float(max(0.5, min(30.0, float(raw))))

    @classmethod
    def _backfill_lines(cls) -> int:
        try:
            raw = int(float(cls._get_env_value("MT4_LOG_AUTOMATION_BACKFILL_LINES", "200")))
        except Exception:
            raw = 200
        return int(max(0, min(2000, raw)))

    @classmethod
    def _active_indicator_names(cls) -> List[str]:
        raw = str(cls._get_env_value("MT4_LOG_AUTOMATION_ACTIVE_INDICATORS", "")).strip()
        return [str(x).strip() for x in raw.split("|") if str(x).strip()]

    @classmethod
    def _restore_active_indicators_on_start(cls) -> bool:
        # Default OFF: indicators should not auto-trade after restart
        # unless user explicitly starts automation from panel.
        v = str(cls._get_env_value("MT4_LOG_AUTOMATION_RESTORE_ACTIVE_ON_START", "0")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @classmethod
    def _forward_max_signal_age_sec(cls) -> float:
        try:
            raw = float(cls._get_env_value("MT4_LOG_AUTOMATION_FORWARD_MAX_SIGNAL_AGE_SEC", "0"))
        except Exception:
            raw = 0.0
        if not math.isfinite(float(raw)):
            raw = 0.0
        return float(max(0.0, min(86400.0, float(raw))))

    @classmethod
    def _forward_dedupe_window_sec(cls) -> float:
        try:
            raw = float(cls._get_env_value("MT4_LOG_AUTOMATION_FORWARD_DEDUPE_WINDOW_SEC", "3600"))
        except Exception:
            raw = 3600.0
        if not math.isfinite(float(raw)):
            raw = 3600.0
        return float(max(30.0, min(86400.0, float(raw))))

    @staticmethod
    def _now_iso() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _to_unix_or_none(value: Any) -> Optional[float]:
        if isinstance(value, (int, float)):
            try:
                v = float(value)
                if math.isfinite(v) and v > 0:
                    return float(v)
            except Exception:
                return None
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

    @staticmethod
    def _indicator_key(name: Any) -> str:
        s = str(name or "").strip().lower()
        s = re.sub(r"\s+", " ", s)
        return s

    @staticmethod
    def _safe_decode(raw: bytes) -> str:
        for enc in ("utf-8-sig", "utf-16", "cp1254", "latin-1"):
            try:
                return raw.decode(enc, errors="ignore")
            except Exception:
                continue
        return raw.decode(errors="ignore")

    @classmethod
    def _extract_indicator_parts(cls, payload: str) -> Tuple[str, str, str, str]:
        txt = str(payload or "").strip()
        if not txt:
            return "", "", "", ""
        # Custom indicator load line
        m_custom = re.match(
            r"^Custom indicator\s+(.+?)\s+([A-Z0-9]{3,12}),([A-Z0-9]+):\s*(.*)$",
            txt,
            flags=re.IGNORECASE,
        )
        if m_custom:
            raw_name = str(m_custom.group(1) or "").strip()
            clean = raw_name.split("\\")[-1].strip() if raw_name else raw_name
            return clean, str(m_custom.group(2) or "").upper(), str(m_custom.group(3) or "").upper(), str(m_custom.group(4) or "")
        # Generic indicator output line
        m_line = re.match(
            r"^(.+?)\s+([A-Z0-9]{3,12}),([A-Z0-9]+):\s*(.*)$",
            txt,
            flags=re.IGNORECASE,
        )
        if m_line:
            name = str(m_line.group(1) or "").strip()
            return name, str(m_line.group(2) or "").upper(), str(m_line.group(3) or "").upper(), str(m_line.group(4) or "")
        return "", "", "", txt

    @staticmethod
    def _classify_kind(message: str) -> str:
        m = str(message or "").strip().lower()
        if not m:
            return "empty"
        if "alert" in m:
            return "alert"
        if "loaded successfully" in m:
            return "loaded"
        if "initialized" in m:
            return "initialized"
        if "deinitialized" in m:
            return "deinitialized"
        return "log"

    @staticmethod
    def _normalize_signal_text(text: str) -> str:
        raw = str(text or "")
        if not raw:
            return ""
        try:
            raw = unicodedata.normalize("NFKD", raw)
        except Exception:
            pass
        return str(raw).strip().lower()

    @classmethod
    def _signal_profile(cls, *, indicator: str, message: str) -> str:
        hay = f"{str(indicator or '')} {str(message or '')}".strip()
        m = cls._normalize_signal_text(hay)
        if not m:
            return ""
        if "intrepid" in m:
            return "intrepid"
        if "hydra" in m:
            return "hydra"
        if "fxnuke" in m:
            return "fxnuke"
        if "uranus" in m:
            return "uranus"
        return "generic"

    @classmethod
    def _signal_hint(cls, *, indicator: str, message: str) -> str:
        m = cls._normalize_signal_text(message)
        p = cls._signal_profile(indicator=indicator, message=message)
        if not m:
            return ""

        # Profile-specific mappings.
        if p == "intrepid":
            if re.search(r"\bturned\s+up\b", m):
                return "BUY"
            if re.search(r"\bturned\s+down\b", m):
                return "SELL"
        if p == "hydra":
            h = re.search(r"\bhydra\s*:\s*(buy|sell)\b", m)
            if h:
                return str(h.group(1) or "").upper()
        if p == "fxnuke":
            if re.search(r"\bfxnuke\b.*\bbuy\b", m):
                return "BUY"
            if re.search(r"\bfxnuke\b.*\bsell\b", m):
                return "SELL"
        if p == "uranus":
            if re.search(r"\buranus\b.*\bbuy\b", m):
                return "BUY"
            if re.search(r"\buranus\b.*\bsell\b", m):
                return "SELL"

        # Generic fallback mappings.
        has_buy = bool(re.search(r"\b(buy|long)\b", m))
        has_sell = bool(re.search(r"\b(sell|short)\b", m))
        if has_buy and not has_sell:
            return "BUY"
        if has_sell and not has_buy:
            return "SELL"
        return ""

    def _set_error(self, message: str) -> None:
        with self._lock:
            self._last_error = str(message or "")

    def _touch(self) -> None:
        with self._lock:
            self._last_tick_iso = self._now_iso()

    def _discover_active_files(self, base_path: Path) -> List[Path]:
        out: List[Path] = []
        candidates = [base_path / "logs", base_path / "MQL4" / "Logs"]
        for d in candidates:
            if not d.exists() or not d.is_dir():
                continue
            rows = sorted(d.glob("*.log"), key=lambda p: p.stat().st_mtime if p.exists() else 0.0, reverse=True)
            out.extend(rows[:6])
        unique: List[Path] = []
        seen: set[str] = set()
        for p in out:
            k = str(p.resolve())
            if k in seen:
                continue
            seen.add(k)
            unique.append(p)
        return unique

    def _append_event(self, event: Dict[str, Any]) -> None:
        indicator = str(event.get("indicator") or "").strip()
        indicator_key = self._indicator_key(indicator)
        with self._lock:
            self._event_next_id += 1
            event["id"] = int(self._event_next_id)
            self._events.append(dict(event))
            if len(self._events) > int(self._events_max):
                self._events = self._events[-int(self._events_max):]

            if indicator_key:
                rows = self._indicator_logs.setdefault(indicator_key, [])
                rows.append(dict(event))
                if len(rows) > 1000:
                    self._indicator_logs[indicator_key] = rows[-1000:]

                st = self._indicator_stats.setdefault(
                    indicator_key,
                    {
                        "indicator": indicator,
                        "key": indicator_key,
                        "event_count": 0,
                        "signal_hint_count": 0,
                        "last_signal_hint": "",
                        "last_signal_profile": "",
                        "last_signal_seen": "",
                        "last_signal_message": "",
                        "automation_enabled": False,
                        "last_seen": "",
                        "last_symbol": "",
                        "last_timeframe": "",
                        "forward_ok": 0,
                        "forward_fail": 0,
                    },
                )
                st["indicator"] = indicator or st.get("indicator") or indicator_key
                st["event_count"] = int(st.get("event_count") or 0) + 1
                if str(event.get("signal_hint") or ""):
                    st["signal_hint_count"] = int(st.get("signal_hint_count") or 0) + 1
                    st["last_signal_hint"] = str(event.get("signal_hint") or "")
                    st["last_signal_profile"] = str(event.get("signal_profile") or "")
                    st["last_signal_seen"] = str(event.get("event_ts") or self._now_iso())
                    st["last_signal_message"] = str(event.get("message") or "")[:240]
                st["last_seen"] = str(event.get("event_ts") or self._now_iso())
                st["last_symbol"] = str(event.get("symbol") or "")
                st["last_timeframe"] = str(event.get("timeframe") or "")

    def _parse_line(self, *, line: str, source_file: str, file_date: str) -> Optional[Dict[str, Any]]:
        raw = str(line or "").strip()
        if not raw:
            return None
        m = re.match(r"^\s*(\d+)\t([0-9:.]+)\t(.*)$", raw)
        if not m:
            return None
        level = int(m.group(1))
        tpart = str(m.group(2) or "").strip()
        payload = str(m.group(3) or "").strip()
        indicator, symbol, timeframe, message = self._extract_indicator_parts(payload)
        if not message:
            message = payload
        kind = self._classify_kind(message)
        profile = self._signal_profile(indicator=indicator, message=message)
        hint = self._signal_hint(indicator=indicator, message=message)
        ts_iso = self._now_iso()
        try:
            if re.match(r"^\d{8}$", str(file_date or "")):
                dt = datetime.strptime(f"{file_date} {tpart[:12]}", "%Y%m%d %H:%M:%S.%f")
                ts_iso = dt.replace(tzinfo=datetime.now().astimezone().tzinfo).astimezone(timezone.utc).isoformat()
        except Exception:
            ts_iso = self._now_iso()
        return {
            "event_ts": ts_iso,
            "source_file": str(source_file),
            "level": int(level),
            "time": str(tpart),
            "indicator": str(indicator or "").strip(),
            "indicator_key": self._indicator_key(indicator),
            "symbol": str(symbol or "").upper(),
            "timeframe": str(timeframe or "").upper(),
            "kind": str(kind),
            "signal_hint": str(hint),
            "signal_profile": str(profile),
            "message": str(message or "").strip()[:2000],
            "raw": raw[:3000],
        }

    def _maybe_forward_signal(self, event: Dict[str, Any], *, from_backfill: bool = False) -> None:
        if self._on_indicator_signal is None:
            return
        if bool(from_backfill):
            return
        indicator = str(event.get("indicator") or "").strip()
        k = self._indicator_key(indicator)
        if not k:
            return
        with self._lock:
            st = self._indicator_stats.get(k) or {}
            enabled = bool(st.get("automation_enabled"))
        if not enabled:
            return
        if not str(event.get("signal_hint") or ""):
            return
        now_ts = time.time()
        max_age = float(self._forward_max_signal_age_sec())
        ev_unix = self._to_unix_or_none(event.get("event_ts"))
        if max_age > 0.0 and ev_unix is not None and (float(now_ts) - float(ev_unix)) > float(max_age):
            with self._lock:
                self._forward_skip_stale += 1
            return
        profile = str(event.get("signal_profile") or "").strip().lower()
        hint = str(event.get("signal_hint") or "").strip().upper()
        symbol = str(event.get("symbol") or "").strip().upper()
        timeframe = str(event.get("timeframe") or "").strip().upper()
        msg_norm = re.sub(r"\s+", " ", str(event.get("message") or "").strip().lower())
        dedupe_key = f"{k}|{profile}|{symbol}|{timeframe}|{hint}|{msg_norm}"
        with self._lock:
            prev_ts = float(self._forward_seen_keys.get(dedupe_key) or 0.0)
            if prev_ts > 0.0 and (float(now_ts) - float(prev_ts)) <= float(self._forward_dedupe_window_sec()):
                self._forward_skip_duplicate += 1
                return
            self._forward_seen_keys[dedupe_key] = float(now_ts)
            if len(self._forward_seen_keys) > 10000:
                cutoff = float(now_ts) - float(max(self._forward_dedupe_window_sec(), 600.0))
                self._forward_seen_keys = {
                    str(key): float(ts)
                    for key, ts in self._forward_seen_keys.items()
                    if float(ts) >= float(cutoff)
                }

        payload = {
            "indicator": str(indicator),
            "symbol": str(symbol),
            "timeframe": str(timeframe),
            "signal_hint": str(hint),
            "signal_profile": str(profile),
            "message": str(event.get("message") or ""),
            "event_ts": str(event.get("event_ts") or ""),
        }
        try:
            self._on_indicator_signal(**payload)
            with self._lock:
                self._forward_total += 1
                self._forward_ok += 1
                self._last_forward_iso = self._now_iso()
                self._last_forward_indicator = str(indicator)
                self._last_forward_error = ""
                if k in self._indicator_stats:
                    self._indicator_stats[k]["forward_ok"] = int(self._indicator_stats[k].get("forward_ok") or 0) + 1
        except Exception as exc:
            with self._lock:
                self._forward_total += 1
                self._forward_fail += 1
                self._last_forward_iso = self._now_iso()
                self._last_forward_indicator = str(indicator)
                self._last_forward_error = f"{type(exc).__name__}: {str(exc)[:180]}"
                if k in self._indicator_stats:
                    self._indicator_stats[k]["forward_fail"] = int(self._indicator_stats[k].get("forward_fail") or 0) + 1

    def _process_file_backfill(self, p: Path, max_lines: int) -> None:
        try:
            rows = p.read_bytes().splitlines()
        except Exception:
            return
        if max_lines > 0 and len(rows) > max_lines:
            rows = rows[-max_lines:]
        file_date = p.stem if re.match(r"^\d{8}$", p.stem or "") else ""
        for b in rows:
            text = self._safe_decode(bytes(b))
            ev = self._parse_line(line=text, source_file=str(p.name), file_date=file_date)
            if not isinstance(ev, dict):
                continue
            self._append_event(ev)
            self._maybe_forward_signal(ev, from_backfill=True)
        try:
            self._file_offsets[str(p.resolve())] = int(p.stat().st_size)
        except Exception:
            pass

    def _process_file_incremental(self, p: Path) -> None:
        key = str(p.resolve())
        try:
            size = int(p.stat().st_size)
        except Exception:
            return
        prev = int(self._file_offsets.get(key, 0))
        if prev > size:
            prev = 0
        if prev == size:
            return
        try:
            with p.open("rb") as f:
                f.seek(prev)
                raw = f.read(max(0, size - prev))
            self._file_offsets[key] = int(size)
        except Exception:
            return
        lines = self._safe_decode(raw).splitlines()
        file_date = p.stem if re.match(r"^\d{8}$", p.stem or "") else ""
        for text in lines:
            ev = self._parse_line(line=text, source_file=str(p.name), file_date=file_date)
            if not isinstance(ev, dict):
                continue
            self._append_event(ev)
            self._maybe_forward_signal(ev)

    def is_running(self) -> bool:
        with self._lock:
            return bool(self._running)

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        if not self._enabled():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run_thread, daemon=True, name="mt4-log-automation")
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        t = self._thread
        if t is not None and t.is_alive():
            t.join(timeout=10.0)
        self._thread = None
        with self._lock:
            self._running = False

    def _run_thread(self) -> None:
        with self._lock:
            self._running = True
            self._last_error = ""
        try:
            self._run_loop()
        except Exception as exc:
            self._set_error(f"listener_crashed:{type(exc).__name__}:{str(exc)[:220]}")
            logger.exception("mt4_log_automation_crashed")
        finally:
            with self._lock:
                self._running = False

    def _run_loop(self) -> None:
        path_raw = self._data_path()
        base = Path(path_raw) if path_raw else None
        if not base or (not base.exists()) or (not base.is_dir()):
            self._set_error("invalid_mt4_data_path")
            return

        if self._restore_active_indicators_on_start():
            active_names = {self._indicator_key(x) for x in self._active_indicator_names()}
            with self._lock:
                for k in active_names:
                    st = self._indicator_stats.setdefault(
                        k,
                        {
                            "indicator": k,
                            "key": k,
                            "event_count": 0,
                            "signal_hint_count": 0,
                            "last_signal_hint": "",
                            "last_signal_profile": "",
                            "last_signal_seen": "",
                            "last_signal_message": "",
                            "automation_enabled": True,
                            "last_seen": "",
                            "last_symbol": "",
                            "last_timeframe": "",
                            "forward_ok": 0,
                            "forward_fail": 0,
                        },
                    )
                    st["automation_enabled"] = True

        files = self._discover_active_files(base)
        if not files:
            self._set_error("no_log_files_found")
            return
        for p in files:
            self._process_file_backfill(p, self._backfill_lines())
        self._touch()
        while not self._stop.is_set():
            files = self._discover_active_files(base)
            for p in files:
                if str(p.resolve()) not in self._file_offsets:
                    self._process_file_backfill(p, self._backfill_lines())
                else:
                    self._process_file_incremental(p)
            self._touch()
            time.sleep(float(self._poll_sec()))

    def get_state(self, *, limit: int = 200) -> Dict[str, Any]:
        lim = int(max(20, min(1000, int(limit or 200))))
        with self._lock:
            events = [dict(x) for x in self._events[-lim:]]
            stats = [dict(v) for v in self._indicator_stats.values()]
            files = list(self._file_offsets.keys())
            out = {
                "ok": True,
                "config": {
                    "enabled": bool(self._enabled()),
                    "data_path": str(self._data_path()),
                    "poll_sec": float(self._poll_sec()),
                    "backfill_lines": int(self._backfill_lines()),
                    "active_indicators": list(self._active_indicator_names()),
                    "restore_active_on_start": bool(self._restore_active_indicators_on_start()),
                },
                "running": bool(self._running),
                "last_error": str(self._last_error or ""),
                "last_tick": str(self._last_tick_iso or ""),
                "forward_total": int(self._forward_total),
                "forward_ok": int(self._forward_ok),
                "forward_fail": int(self._forward_fail),
                "forward_skip_stale": int(self._forward_skip_stale),
                "forward_skip_duplicate": int(self._forward_skip_duplicate),
                "last_forward": str(self._last_forward_iso or ""),
                "last_forward_indicator": str(self._last_forward_indicator or ""),
                "last_forward_error": str(self._last_forward_error or ""),
                "watched_files_count": int(len(files)),
                "watched_files": files[-12:],
                "indicator_count": int(len(stats)),
                "indicators": sorted(stats, key=lambda r: str((r or {}).get("last_seen") or ""), reverse=True),
                "events": events,
            }
        return out

    def update_config(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        p = payload if isinstance(payload, dict) else {}
        updates: Dict[str, Any] = {}
        if "enabled" in p:
            updates["MT4_LOG_AUTOMATION_ENABLED"] = "1" if bool(p.get("enabled")) else "0"
        if "data_path" in p:
            updates["MT4_LOG_AUTOMATION_DATA_PATH"] = str(p.get("data_path") or "").strip()
        if "poll_sec" in p:
            try:
                sec = float(p.get("poll_sec"))
            except Exception:
                sec = 2.0
            sec = float(max(0.5, min(30.0, sec)))
            updates["MT4_LOG_AUTOMATION_POLL_SEC"] = f"{sec:.2f}"
        if "backfill_lines" in p:
            try:
                cnt = int(float(p.get("backfill_lines")))
            except Exception:
                cnt = 200
            cnt = int(max(0, min(2000, cnt)))
            updates["MT4_LOG_AUTOMATION_BACKFILL_LINES"] = str(cnt)
        if "restore_active_on_start" in p:
            updates["MT4_LOG_AUTOMATION_RESTORE_ACTIVE_ON_START"] = "1" if bool(p.get("restore_active_on_start")) else "0"
        ok, status = self._upsert_env_values(updates)
        if self.is_running():
            self.stop()
        if self._enabled():
            self.start()
        out = self.get_state(limit=200)
        out["persist_ok"] = bool(ok)
        out["persist_status"] = str(status)
        out["updated"] = {str(k): str(v) for k, v in updates.items()}
        return out

    def set_indicator_automation(self, *, indicator: str, enabled: bool) -> Dict[str, Any]:
        name = str(indicator or "").strip()
        if not name:
            return {"ok": False, "error": "missing_indicator"}
        key = self._indicator_key(name)
        with self._lock:
            st = self._indicator_stats.setdefault(
                key,
                {
                    "indicator": name,
                    "key": key,
                    "event_count": 0,
                    "signal_hint_count": 0,
                    "last_signal_hint": "",
                    "last_signal_profile": "",
                    "last_signal_seen": "",
                    "last_signal_message": "",
                    "automation_enabled": bool(enabled),
                    "last_seen": "",
                    "last_symbol": "",
                    "last_timeframe": "",
                    "forward_ok": 0,
                    "forward_fail": 0,
                },
            )
            st["indicator"] = name or st.get("indicator") or key
            st["automation_enabled"] = bool(enabled)
            names = [
                str(v.get("indicator") or "").strip()
                for v in self._indicator_stats.values()
                if bool(v.get("automation_enabled")) and str(v.get("indicator") or "").strip()
            ]
        names = sorted(set(names), key=lambda x: x.lower())
        ok, status = self._upsert_env_values({"MT4_LOG_AUTOMATION_ACTIVE_INDICATORS": "|".join(names)})
        out = self.get_state(limit=200)
        out["persist_ok"] = bool(ok)
        out["persist_status"] = str(status)
        out["updated"] = {"MT4_LOG_AUTOMATION_ACTIVE_INDICATORS": "|".join(names)}
        return out

    def get_indicator_logs(self, *, indicator: str, limit: int = 120) -> Dict[str, Any]:
        return self.get_indicator_logs_filtered(indicator=indicator, limit=limit, alerts_only=False)

    def get_indicator_logs_filtered(self, *, indicator: str, limit: int = 120, alerts_only: bool = True) -> Dict[str, Any]:
        key = self._indicator_key(indicator)
        lim = int(max(20, min(1000, int(limit or 120))))
        with self._lock:
            source_rows = [dict(x) for x in self._indicator_logs.get(key, [])]
            st = dict(self._indicator_stats.get(key) or {})
        if alerts_only:
            source_rows = [r for r in source_rows if str((r or {}).get("kind") or "").strip().lower() == "alert"]
        rows = source_rows[-lim:]
        for r in rows:
            msg = str((r or {}).get("message") or "")
            if msg.lower().startswith("alert:"):
                r["message"] = msg[6:].strip()
        return {
            "ok": True,
            "indicator": str(st.get("indicator") or indicator),
            "key": str(key),
            "stats": st,
            "rows": rows,
            "count": int(len(rows)),
            "alerts_only": bool(alerts_only),
        }
