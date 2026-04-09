"""
MT4/MT5 Log Automation Service

Reads MetaTrader terminal logs (MQL4 + MQL5), discovers indicator activity,
and exposes indicator-level automation toggles for downstream strategy workflows.
"""

from __future__ import annotations

import logging
import math
import os
import re
import threading
import time
import unicodedata
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Callable


logger = logging.getLogger(__name__)


class MT4LogAutomationService:
    _ALLOWED_AUTOMATION_TOKENS: Tuple[str, ...] = (
        "hydra signals indicator",
        "forex uranus direction",
        "forexcypersystem",
        "forexcyper",
        "alchemy pulse",
        "intrepid trend direction",
    )

    def __init__(
        self,
        on_indicator_signal: Optional[Callable[..., None]] = None,
        on_log_event: Optional[Callable[..., None]] = None,
    ) -> None:
        self._on_indicator_signal = on_indicator_signal
        self._on_log_event = on_log_event
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
        self._instance_stats: Dict[str, Dict[str, Any]] = {}
        self._file_offsets: Dict[str, int] = {}

        self._forward_total: int = 0
        self._forward_ok: int = 0
        self._forward_fail: int = 0
        self._last_forward_iso: str = ""
        self._last_forward_indicator: str = ""
        self._last_forward_error: str = ""
        self._forward_skip_stale: int = 0
        self._forward_skip_duplicate: int = 0
        self._forward_skip_backfill: int = 0
        self._forward_skip_disabled: int = 0
        self._forward_skip_no_hint: int = 0
        self._forward_skip_no_callback: int = 0
        self._forward_seen_keys: Dict[str, float] = {}
        self._ingest_seen_keys: Dict[str, float] = {}

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
    def _data_paths(cls) -> List[str]:
        raw = str(cls._data_path() or "").strip()
        if not raw:
            return []
        parts = [str(x).strip() for x in re.split(r"[|\n;]+", raw) if str(x).strip()]
        out: List[str] = []
        seen: set[str] = set()
        for p in parts:
            k = str(Path(p)).strip().lower()
            if not k or k in seen:
                continue
            seen.add(k)
            out.append(str(p))
        return out

    @classmethod
    def _poll_sec(cls) -> float:
        try:
            raw = float(cls._get_env_value("MT4_LOG_AUTOMATION_POLL_SEC", "0.5"))
        except Exception:
            raw = 0.5
        if not math.isfinite(float(raw)):
            raw = 0.5
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
    def _default_indicator_lot(cls) -> float:
        try:
            raw = float(cls._get_env_value("MT4_LOG_AUTOMATION_DEFAULT_INDICATOR_LOT", "0.05"))
        except Exception:
            raw = 0.05
        if not math.isfinite(float(raw)) or float(raw) <= 0.0:
            raw = 0.05
        return float(max(0.01, min(100.0, float(raw))))

    @classmethod
    def _indicator_lot_overrides(cls) -> Dict[str, float]:
        raw = str(cls._get_env_value("MT4_LOG_AUTOMATION_INDICATOR_LOTS", "{}")).strip()
        if not raw:
            return {}
        try:
            obj = json.loads(raw)
        except Exception:
            return {}
        out: Dict[str, float] = {}
        if not isinstance(obj, dict):
            return out
        for k, v in obj.items():
            key = cls._indicator_key(k)
            if not key:
                continue
            try:
                lot = float(v)
            except Exception:
                continue
            if not math.isfinite(float(lot)) or float(lot) <= 0.0:
                continue
            out[key] = float(max(0.01, min(100.0, float(lot))))
        return out

    @classmethod
    def _serialize_indicator_lot_overrides(cls, lot_map: Dict[str, Any]) -> str:
        cleaned: Dict[str, float] = {}
        for k, v in (lot_map or {}).items():
            key = cls._indicator_key(k)
            if not key:
                continue
            try:
                lot = float(v)
            except Exception:
                continue
            if not math.isfinite(float(lot)) or float(lot) <= 0.0:
                continue
            cleaned[key] = float(max(0.01, min(100.0, float(lot))))
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @classmethod
    def _indicator_lot_for_key(cls, key: str) -> float:
        k = cls._indicator_key(key)
        if not k:
            return float(cls._default_indicator_lot())
        lot_map = cls._indicator_lot_overrides()
        if k in lot_map:
            return float(lot_map[k])
        return float(cls._default_indicator_lot())

    @classmethod
    def _active_instance_keys(cls) -> List[str]:
        raw = str(cls._get_env_value("MT4_LOG_AUTOMATION_ACTIVE_INSTANCES", "[]")).strip()
        if not raw:
            return []
        items: List[str] = []
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                items = [str(x or "").strip() for x in parsed]
            elif isinstance(parsed, dict):
                items = [str(k or "").strip() for k, v in parsed.items() if bool(v)]
            elif isinstance(parsed, str):
                items = [str(x).strip() for x in parsed.split("|")]
        except Exception:
            items = [str(x).strip() for x in raw.split("|")]
        out: List[str] = []
        seen: set[str] = set()
        for item in items:
            k = str(item or "").strip().lower()
            if not k or k in seen:
                continue
            seen.add(k)
            out.append(str(item).strip())
        return out

    @classmethod
    def _instance_automation_overrides(cls) -> Dict[str, bool]:
        raw = str(cls._get_env_value("MT4_LOG_AUTOMATION_INSTANCE_AUTOMATION", "{}")).strip()
        out: Dict[str, bool] = {}
        if raw:
            try:
                obj = json.loads(raw)
                if isinstance(obj, dict):
                    for k, v in obj.items():
                        key = str(k or "").strip().lower()
                        if not key:
                            continue
                        out[key] = bool(v)
            except Exception:
                out = {}
        # Backward compatibility: if only ACTIVE_INSTANCES exists,
        # treat them as explicit ON overrides.
        for k in cls._active_instance_keys():
            kk = str(k or "").strip().lower()
            if kk and kk not in out:
                out[kk] = True
        return out

    @classmethod
    def _serialize_instance_automation_overrides(cls, overrides: Dict[str, Any]) -> str:
        cleaned: Dict[str, bool] = {}
        for k, v in (overrides or {}).items():
            key = str(k or "").strip().lower()
            if not key:
                continue
            cleaned[key] = bool(v)
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @classmethod
    def _instance_lot_overrides(cls) -> Dict[str, float]:
        raw = str(cls._get_env_value("MT4_LOG_AUTOMATION_INSTANCE_LOTS", "{}")).strip()
        if not raw:
            return {}
        try:
            obj = json.loads(raw)
        except Exception:
            return {}
        if not isinstance(obj, dict):
            return {}
        out: Dict[str, float] = {}
        for k, v in obj.items():
            key = str(k or "").strip().lower()
            if not key:
                continue
            try:
                lot = float(v)
            except Exception:
                continue
            if not math.isfinite(float(lot)) or float(lot) <= 0.0:
                continue
            out[key] = float(max(0.01, min(100.0, float(lot))))
        return out

    @classmethod
    def _serialize_instance_lot_overrides(cls, lot_map: Dict[str, Any]) -> str:
        cleaned: Dict[str, float] = {}
        for k, v in (lot_map or {}).items():
            key = str(k or "").strip().lower()
            if not key:
                continue
            try:
                lot = float(v)
            except Exception:
                continue
            if not math.isfinite(float(lot)) or float(lot) <= 0.0:
                continue
            cleaned[key] = float(max(0.01, min(100.0, float(lot))))
        return json.dumps(cleaned, ensure_ascii=True, sort_keys=True, separators=(",", ":"))

    @classmethod
    def _instance_key(cls, *, indicator: str, symbol: str, timeframe: str) -> str:
        ik = cls._indicator_key(indicator)
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        if not ik or not sym or not tf:
            return ""
        return f"{ik}|{sym}|{tf}"

    @classmethod
    def _instance_key_parts(cls, key: str) -> Tuple[str, str, str]:
        raw = str(key or "").strip()
        if not raw:
            return "", "", ""
        parts = raw.split("|")
        if len(parts) < 3:
            return raw, "", ""
        return str(parts[0] or ""), str(parts[1] or "").upper(), str(parts[2] or "").upper()

    @classmethod
    def _instance_lot_for_key(cls, key: str) -> float:
        k = str(key or "").strip().lower()
        if not k:
            return float(cls._default_indicator_lot())
        inst_lots = cls._instance_lot_overrides()
        if k in inst_lots:
            return float(inst_lots[k])
        ik, _sym, _tf = cls._instance_key_parts(k)
        if ik:
            return float(cls._indicator_lot_for_key(ik))
        return float(cls._default_indicator_lot())

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

    @classmethod
    def _forward_new_file_grace_sec(cls) -> float:
        """
        When a brand-new log file appears while listener is already running
        (daily rotation/session restart), allow forwarding only for very recent
        rows from its initial backfill window so fresh signals are not lost.
        """
        try:
            raw = float(cls._get_env_value("MT4_LOG_AUTOMATION_FORWARD_NEW_FILE_GRACE_SEC", "120"))
        except Exception:
            raw = 120.0
        if not math.isfinite(float(raw)):
            raw = 120.0
        return float(max(5.0, min(600.0, float(raw))))

    @classmethod
    def _ingest_dedupe_window_sec(cls) -> float:
        try:
            raw = float(cls._get_env_value("MT4_LOG_AUTOMATION_INGEST_DEDUPE_WINDOW_SEC", "21600"))
        except Exception:
            raw = 21600.0
        if not math.isfinite(float(raw)):
            raw = 21600.0
        return float(max(60.0, min(86400.0, float(raw))))

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

    @classmethod
    def _is_indicator_automation_allowed(cls, name_or_key: Any) -> bool:
        key = cls._indicator_key(name_or_key)
        if not key:
            return False
        return any(str(tok) in key for tok in cls._ALLOWED_AUTOMATION_TOKENS)

    @staticmethod
    def _safe_decode(raw: bytes) -> str:
        if not raw:
            return ""
        # MT5 MQL5\Logs are commonly UTF-16 LE; decode those first.
        if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
            try:
                return raw.decode("utf-16", errors="ignore")
            except Exception:
                pass
        if b"\x00" in raw[:200]:
            try:
                return raw.decode("utf-16-le", errors="ignore")
            except Exception:
                pass
        for enc in ("utf-8-sig", "cp1254", "latin-1"):
            try:
                return raw.decode(enc, errors="ignore")
            except Exception:
                continue
        return raw.decode(errors="ignore")

    @staticmethod
    def _terminal_group_from_path(path_value: str) -> str:
        p = str(path_value or "").strip().lower().replace("/", "\\")
        if not p:
            return "unknown"
        is_mt5 = "\\mql5\\logs\\" in p
        is_mt4 = "\\mql4\\logs\\" in p or ("\\logs\\" in p and not is_mt5)
        if is_mt5 and ("\\demo\\" in p or " demo" in p or "_demo" in p or "-demo" in p):
            return "mt5_demo"
        if is_mt5:
            return "mt5"
        if is_mt4:
            return "mt4"
        if "\\mt5\\" in p and ("\\demo\\" in p or " demo" in p or "_demo" in p or "-demo" in p):
            return "mt5_demo"
        if "\\mt5\\" in p:
            return "mt5"
        if "\\mt4\\" in p:
            return "mt4"
        return "unknown"

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
        # Parenthesized format: "IndicatorName (SYMBOL,TF): message"
        m_paren = re.match(
            r"^(.+?)\s*\(([A-Z0-9._#-]{3,20}),([A-Z0-9]+)\)\s*:?\s*(.*)$",
            txt,
            flags=re.IGNORECASE,
        )
        if m_paren:
            name = str(m_paren.group(1) or "").strip()
            name = re.sub(r"^\s*custom\s+indicator\s+", "", name, flags=re.IGNORECASE).strip()
            if "\\" in name:
                name = name.split("\\")[-1].strip()
            return (
                str(name or "").strip(),
                str(m_paren.group(2) or "").upper(),
                str(m_paren.group(3) or "").upper(),
                str(m_paren.group(4) or ""),
            )
        # Space-delimited format: "IndicatorName SYMBOL TF: message"
        m_space = re.match(
            r"^(.+?)\s+([A-Z0-9._#-]{3,20})\s+([A-Z0-9]+)\s*:?\s*(.*)$",
            txt,
            flags=re.IGNORECASE,
        )
        if m_space:
            name = str(m_space.group(1) or "").strip()
            name = re.sub(r"^\s*custom\s+indicator\s+", "", name, flags=re.IGNORECASE).strip()
            if "\\" in name:
                name = name.split("\\")[-1].strip()
            return (
                str(name or "").strip(),
                str(m_space.group(2) or "").upper(),
                str(m_space.group(3) or "").upper(),
                str(m_space.group(4) or ""),
            )
        # Generic indicator output line
        m_line = re.match(
            r"^(.+?)\s+([A-Z0-9._#-]{3,20}),([A-Z0-9]+)\s*:?\s*(.*)$",
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
        if "forexcypersytem" in m or "forex cypersytem" in m or "forexcyper" in m or "forex cyper" in m:
            return "forexcyper"
        if "alchemy pulse" in m or "alchemypulse" in m or "alchemy" in m:
            return "alchemy"
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
            if re.search(r"\bturned\s+up\b", m):
                return "BUY"
            if re.search(r"\bturned\s+down\b", m):
                return "SELL"
            if re.search(r"\buranus\b.*\bbuy\b", m):
                return "BUY"
            if re.search(r"\buranus\b.*\bsell\b", m):
                return "SELL"
        if p == "alchemy":
            if re.search(r"\b(buy|long|bull(?:ish)?|turned\s+up|cross(?:ed)?\s+up|signal\s+up)\b", m):
                return "BUY"
            if re.search(r"\b(sell|short|bear(?:ish)?|turned\s+down|cross(?:ed)?\s+down|signal\s+down)\b", m):
                return "SELL"
        if p == "forexcyper":
            if re.search(r"\b(buy|long|bull(?:ish)?|turned\s+up|cross(?:ed)?\s+up|signal\s+up|uptrend)\b", m):
                return "BUY"
            if re.search(r"\b(sell|short|bear(?:ish)?|turned\s+down|cross(?:ed)?\s+down|signal\s+down|downtrend)\b", m):
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
        candidates = [base_path / "logs", base_path / "MQL4" / "Logs", base_path / "MQL5" / "Logs"]
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

    def _append_event(self, event: Dict[str, Any], *, from_backfill: bool = False) -> None:
        indicator = str(event.get("indicator") or "").strip()
        indicator_key = self._indicator_key(indicator)
        with self._lock:
            ingest_now = float(time.time())
            ingest_key = "|".join(
                [
                    str(event.get("source_path") or event.get("source_file") or ""),
                    str(event.get("time") or ""),
                    str(event.get("raw") or ""),
                ]
            ).strip()
            if ingest_key:
                prev_ingest_ts = float(self._ingest_seen_keys.get(ingest_key) or 0.0)
                if prev_ingest_ts > 0.0 and (ingest_now - prev_ingest_ts) <= float(self._ingest_dedupe_window_sec()):
                    return
                self._ingest_seen_keys[ingest_key] = ingest_now
                if len(self._ingest_seen_keys) > 30000:
                    ingest_cutoff = ingest_now - float(max(self._ingest_dedupe_window_sec(), 600.0))
                    self._ingest_seen_keys = {
                        str(k): float(ts)
                        for k, ts in self._ingest_seen_keys.items()
                        if float(ts) >= float(ingest_cutoff)
                    }

            symbol = str(event.get("symbol") or "").strip().upper()
            timeframe = str(event.get("timeframe") or "").strip().upper()
            if indicator_key and (not symbol or not timeframe):
                try:
                    candidates = {
                        (
                            str((row or {}).get("symbol") or "").strip().upper(),
                            str((row or {}).get("timeframe") or "").strip().upper(),
                        )
                        for row in self._instance_stats.values()
                        if self._indicator_key((row or {}).get("indicator_key") or (row or {}).get("indicator")) == indicator_key
                    }
                    candidates = {(s, tf) for (s, tf) in candidates if s and tf}
                except Exception:
                    candidates = set()
                if len(candidates) == 1:
                    s0, tf0 = next(iter(candidates))
                    if not symbol:
                        symbol = str(s0 or "").strip().upper()
                    if not timeframe:
                        timeframe = str(tf0 or "").strip().upper()
                prev_st = self._indicator_stats.get(indicator_key) or {}
                if not symbol:
                    symbol = str(prev_st.get("last_symbol") or "").strip().upper()
                if not timeframe:
                    timeframe = str(prev_st.get("last_timeframe") or "").strip().upper()
            event["symbol"] = str(symbol or "")
            event["timeframe"] = str(timeframe or "")
            inst_key = self._instance_key(indicator=indicator, symbol=symbol, timeframe=timeframe)
            event["instance_key"] = str(inst_key or "")

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
                        "lot_size": float(self._indicator_lot_for_key(indicator_key)),
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
                if str(event.get("symbol") or "").strip():
                    st["last_symbol"] = str(event.get("symbol") or "")
                if str(event.get("timeframe") or "").strip():
                    st["last_timeframe"] = str(event.get("timeframe") or "")
                lot_raw = st.get("lot_size")
                if lot_raw:
                    try:
                        lot = float(lot_raw)
                        if not math.isfinite(float(lot)) or float(lot) <= 0.0:
                            st["lot_size"] = float(self._indicator_lot_for_key(indicator_key))
                    except Exception:
                        st["lot_size"] = float(self._indicator_lot_for_key(indicator_key))
                else:
                    st["lot_size"] = float(self._indicator_lot_for_key(indicator_key))

            if inst_key:
                overrides = self._instance_automation_overrides()
                explicit_flag = inst_key.lower() in overrides
                explicit_enabled = bool(overrides.get(inst_key.lower()))
                row = self._instance_stats.setdefault(
                    inst_key,
                    {
                        "instance_key": inst_key,
                        "indicator": indicator,
                        "indicator_key": indicator_key,
                        "symbol": symbol,
                        "timeframe": timeframe,
                        "event_count": 0,
                        "signal_hint_count": 0,
                        "last_signal_hint": "",
                        "last_signal_profile": "",
                        "last_signal_seen": "",
                        "last_signal_message": "",
                        "automation_enabled": bool(explicit_enabled) if explicit_flag else False,
                        "automation_mode": "explicit" if explicit_flag else "inherit",
                        "lot_size": float(self._instance_lot_for_key(inst_key)),
                        "last_seen": "",
                        "last_terminal_group": "",
                        "forward_ok": 0,
                        "forward_fail": 0,
                    },
                )
                row["indicator"] = indicator or row.get("indicator") or indicator_key
                row["indicator_key"] = indicator_key
                row["symbol"] = symbol
                row["timeframe"] = timeframe
                row["event_count"] = int(row.get("event_count") or 0) + 1
                if str(event.get("signal_hint") or ""):
                    row["signal_hint_count"] = int(row.get("signal_hint_count") or 0) + 1
                    row["last_signal_hint"] = str(event.get("signal_hint") or "")
                    row["last_signal_profile"] = str(event.get("signal_profile") or "")
                    row["last_signal_seen"] = str(event.get("event_ts") or self._now_iso())
                    row["last_signal_message"] = str(event.get("message") or "")[:240]
                row["last_seen"] = str(event.get("event_ts") or self._now_iso())
                row["last_terminal_group"] = str(event.get("terminal_group") or row.get("last_terminal_group") or "")
                if str(row.get("automation_mode") or "") != "explicit":
                    row["automation_enabled"] = False
                lot_raw = row.get("lot_size")
                if lot_raw:
                    try:
                        lot = float(lot_raw)
                        if not math.isfinite(float(lot)) or float(lot) <= 0.0:
                            row["lot_size"] = float(self._instance_lot_for_key(inst_key))
                    except Exception:
                        row["lot_size"] = float(self._instance_lot_for_key(inst_key))
                else:
                    row["lot_size"] = float(self._instance_lot_for_key(inst_key))
        self._emit_log_event(event, from_backfill=bool(from_backfill))

    def _parse_line(
        self,
        *,
        line: str,
        source_file: str,
        file_date: str,
        source_path: str = "",
    ) -> Optional[Dict[str, Any]]:
        raw = str(line or "").strip()
        if not raw:
            return None
        level = 0
        tpart = ""
        indicator = ""
        symbol = ""
        timeframe = ""
        message = ""

        # MT4-style: "<level>\t<time>\t<payload>"
        m_mt4 = re.match(r"^\s*(\d+)\t([0-9:.]+)\t(.*)$", raw)
        if m_mt4:
            level = int(m_mt4.group(1))
            tpart = str(m_mt4.group(2) or "").strip()
            payload = str(m_mt4.group(3) or "").strip()
            indicator, symbol, timeframe, message = self._extract_indicator_parts(payload)
        else:
            # MT5-style: "<code>\t<level>\t<time>\t<source>\t<message>"
            m_mt5 = re.match(r"^\s*([A-Z0-9]{1,6})\t(\d+)\t([0-9:.]+)\t([^\t]+)\t(.*)$", raw, flags=re.IGNORECASE)
            if not m_mt5:
                return None
            level = int(m_mt5.group(2))
            tpart = str(m_mt5.group(3) or "").strip()
            source = str(m_mt5.group(4) or "").strip()
            message = str(m_mt5.group(5) or "").strip()
            mm = re.match(r"^(.+?)\s*\(([A-Z0-9._#-]{3,20}),([A-Z0-9]+)\)\s*$", source, flags=re.IGNORECASE)
            if mm:
                indicator = str(mm.group(1) or "").strip()
                symbol = str(mm.group(2) or "").upper()
                timeframe = str(mm.group(3) or "").upper()
            else:
                indicator = str(source).strip()
                src_norm = str(source or "").strip().lower()
                if src_norm in {"indicators", "indicator", "experts", "expert", "scripts", "script"}:
                    p_ind, p_sym, p_tf, p_msg = self._extract_indicator_parts(message)
                    if str(p_ind or "").strip():
                        indicator = str(p_ind or "").strip()
                    if str(p_sym or "").strip():
                        symbol = str(p_sym or "").strip().upper()
                    if str(p_tf or "").strip():
                        timeframe = str(p_tf or "").strip().upper()
                    if str(p_msg or "").strip():
                        message = str(p_msg or "").strip()
        if not message:
            message = raw
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
            "source_path": str(source_path or ""),
            "terminal_group": str(self._terminal_group_from_path(str(source_path or source_file))),
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

    def _enrich_event_for_view(self, event: Dict[str, Any]) -> Dict[str, Any]:
        row = dict(event or {})
        indicator = str(row.get("indicator") or "").strip()
        symbol = str(row.get("symbol") or "").strip().upper()
        timeframe = str(row.get("timeframe") or "").strip().upper()
        needs_parse = (not symbol or not timeframe or indicator.lower() in {"indicator", "indicators"})
        if needs_parse:
            p_ind, p_sym, p_tf, _p_msg = self._extract_indicator_parts(str(row.get("message") or ""))
            if str(p_ind or "").strip() and indicator.lower() in {"indicator", "indicators", ""}:
                indicator = str(p_ind or "").strip()
            if str(p_sym or "").strip() and not symbol:
                symbol = str(p_sym or "").strip().upper()
            if str(p_tf or "").strip() and not timeframe:
                timeframe = str(p_tf or "").strip().upper()
        row["indicator"] = str(indicator or row.get("indicator") or "")
        row["indicator_key"] = self._indicator_key(row.get("indicator"))
        row["symbol"] = str(symbol or "")
        row["timeframe"] = str(timeframe or "")
        if not str(row.get("instance_key") or "").strip():
            ik = self._instance_key(
                indicator=str(row.get("indicator") or ""),
                symbol=str(row.get("symbol") or ""),
                timeframe=str(row.get("timeframe") or ""),
            )
            row["instance_key"] = str(ik or "")
        return row

    @staticmethod
    def _is_alarm_like_event(event: Dict[str, Any]) -> bool:
        ev = event if isinstance(event, dict) else {}
        sh = str(ev.get("signal_hint") or "").strip().upper()
        if sh in {"BUY", "SELL"}:
            return True
        msg = str(ev.get("message") or "").strip()
        kind = str(ev.get("kind") or "").strip().lower()
        if kind == "alert":
            lower_msg = msg.lower()
            noisy_lifecycle = (
                lower_msg.startswith("custom indicator ")
                and any(tok in lower_msg for tok in (" loaded", " removed", " initialized", " deinitialized", " uninit", " succes"))
            )
            if noisy_lifecycle and not re.search(r"\b(buy|sell|long|short|signal|turned up|turned down)\b", msg, flags=re.IGNORECASE):
                return False
            return True
        if re.search(r"\b(buy|sell|long|short)\b", msg, flags=re.IGNORECASE):
            return True
        if re.search(r"\bturned\s+up\b|\bturned\s+down\b|\bsignal\b|\balert\b|\balarm\b", msg, flags=re.IGNORECASE):
            return True
        return False

    def _emit_log_event(self, event: Dict[str, Any], *, from_backfill: bool = False) -> None:
        if bool(from_backfill):
            return
        cb = self._on_log_event
        if cb is None:
            return
        if not self._is_alarm_like_event(event):
            return
        try:
            cb(event=dict(event or {}))
        except Exception:
            logger.exception("mt4_log_event_callback_failed")

    def _maybe_forward_signal(self, event: Dict[str, Any], *, from_backfill: bool = False) -> None:
        callback = self._on_indicator_signal
        if callback is None:
            # Safety fallback: if callback wasn't bound (or was lost after reload),
            # try forwarding directly via telegram bridge singleton.
            try:
                from ..main import telegram_bridge_service  # local import to avoid hard dependency at module import time

                if telegram_bridge_service is not None:
                    callback = lambda **payload: telegram_bridge_service.ingest_mt4_indicator_signal(payload=dict(payload or {}))
            except Exception:
                callback = None
        if callback is None:
            with self._lock:
                self._forward_skip_no_callback += 1
            return
        if bool(from_backfill):
            with self._lock:
                self._forward_skip_backfill += 1
            return
        indicator = str(event.get("indicator") or "").strip()
        k = self._indicator_key(indicator)
        if not k:
            return
        if not self._is_indicator_automation_allowed(k):
            with self._lock:
                self._forward_skip_disabled += 1
            return
        symbol = str(event.get("symbol") or "").strip().upper()
        timeframe = str(event.get("timeframe") or "").strip().upper()
        inst_key = self._instance_key(indicator=indicator, symbol=symbol, timeframe=timeframe)
        lot_override = float(self._indicator_lot_for_key(k))
        enabled = False
        with self._lock:
            st = self._indicator_stats.get(k) or {}
            ind_enabled = bool(st.get("automation_enabled"))
            enabled = bool(ind_enabled)
            try:
                lot_override = float(st.get("lot_size") or self._indicator_lot_for_key(k))
            except Exception:
                lot_override = float(self._indicator_lot_for_key(k))
            if inst_key:
                inst = self._instance_stats.get(inst_key) or {}
                mode = str(inst.get("automation_mode") or "inherit").strip().lower()
                if mode == "explicit":
                    enabled = bool(inst.get("automation_enabled"))
                try:
                    lot_override = float(inst.get("lot_size") or self._instance_lot_for_key(inst_key) or lot_override)
                except Exception:
                    lot_override = float(self._instance_lot_for_key(inst_key) or lot_override)
        if not enabled:
            with self._lock:
                self._forward_skip_disabled += 1
            return
        if not str(event.get("signal_hint") or ""):
            with self._lock:
                self._forward_skip_no_hint += 1
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
            "instance_key": str(inst_key or ""),
            "lot_override": float(max(0.01, min(100.0, lot_override))),
        }
        try:
            callback(**payload)
            with self._lock:
                self._forward_total += 1
                self._forward_ok += 1
                self._last_forward_iso = self._now_iso()
                self._last_forward_indicator = str(indicator)
                self._last_forward_error = ""
                if k in self._indicator_stats:
                    self._indicator_stats[k]["forward_ok"] = int(self._indicator_stats[k].get("forward_ok") or 0) + 1
                if inst_key and inst_key in self._instance_stats:
                    self._instance_stats[inst_key]["forward_ok"] = int(self._instance_stats[inst_key].get("forward_ok") or 0) + 1
        except Exception as exc:
            with self._lock:
                self._forward_total += 1
                self._forward_fail += 1
                self._last_forward_iso = self._now_iso()
                self._last_forward_indicator = str(indicator)
                self._last_forward_error = f"{type(exc).__name__}: {str(exc)[:180]}"
                if k in self._indicator_stats:
                    self._indicator_stats[k]["forward_fail"] = int(self._indicator_stats[k].get("forward_fail") or 0) + 1
                if inst_key and inst_key in self._instance_stats:
                    self._instance_stats[inst_key]["forward_fail"] = int(self._instance_stats[inst_key].get("forward_fail") or 0) + 1

    def _process_file_backfill(self, p: Path, max_lines: int, *, allow_runtime_forward_recent: bool = False) -> None:
        try:
            raw = p.read_bytes()
        except Exception:
            return
        rows = self._safe_decode(raw).splitlines()
        if max_lines > 0 and len(rows) > max_lines:
            rows = rows[-max_lines:]
        file_date = p.stem if re.match(r"^\d{8}$", p.stem or "") else ""
        now_unix = float(time.time())
        grace_sec = float(self._forward_new_file_grace_sec())
        for text in rows:
            ev = self._parse_line(
                line=text,
                source_file=str(p.name),
                file_date=file_date,
                source_path=str(p.resolve()),
            )
            if not isinstance(ev, dict):
                continue
            is_recent = False
            if allow_runtime_forward_recent:
                ev_unix = self._to_unix_or_none(ev.get("event_ts"))
                is_recent = (
                    ev_unix is not None
                    and float(ev_unix) <= (now_unix + 5.0)
                    and (now_unix - float(ev_unix)) <= grace_sec
                )
            self._append_event(ev, from_backfill=not bool(is_recent))
            if allow_runtime_forward_recent:
                self._maybe_forward_signal(ev, from_backfill=not bool(is_recent))
            else:
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
            ev = self._parse_line(
                line=text,
                source_file=str(p.name),
                file_date=file_date,
                source_path=str(p.resolve()),
            )
            if not isinstance(ev, dict):
                continue
            self._append_event(ev, from_backfill=False)
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
        bases: List[Path] = []
        for path_raw in self._data_paths():
            p = Path(path_raw)
            if p.exists() and p.is_dir():
                bases.append(p)
        if not bases:
            self._set_error("invalid_mt4_data_path")
            return

        def collect_files() -> List[Path]:
            all_rows: List[Path] = []
            seen: set[str] = set()
            for b in bases:
                for p in self._discover_active_files(b):
                    k = str(p.resolve())
                    if k in seen:
                        continue
                    seen.add(k)
                    all_rows.append(p)
            return sorted(
                all_rows,
                key=lambda p: p.stat().st_mtime if p.exists() else 0.0,
                reverse=True,
            )

        if self._restore_active_indicators_on_start():
            active_names = {
                self._indicator_key(x)
                for x in self._active_indicator_names()
                if self._is_indicator_automation_allowed(x)
            }
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
                            "lot_size": float(self._indicator_lot_for_key(k)),
                            "last_seen": "",
                            "last_symbol": "",
                            "last_timeframe": "",
                            "forward_ok": 0,
                            "forward_fail": 0,
                        },
                    )
                    st["automation_enabled"] = True
                    st["lot_size"] = float(self._indicator_lot_for_key(k))
            instance_overrides = self._instance_automation_overrides()
            with self._lock:
                for inst_key, enabled_flag in instance_overrides.items():
                    ik, sym, tf = self._instance_key_parts(inst_key)
                    if not self._is_indicator_automation_allowed(ik):
                        continue
                    row = self._instance_stats.setdefault(
                        inst_key,
                        {
                            "instance_key": inst_key,
                            "indicator": ik,
                            "indicator_key": ik,
                            "symbol": sym,
                            "timeframe": tf,
                            "event_count": 0,
                            "signal_hint_count": 0,
                            "last_signal_hint": "",
                            "last_signal_profile": "",
                            "last_signal_seen": "",
                            "last_signal_message": "",
                            "automation_enabled": bool(enabled_flag),
                            "automation_mode": "explicit",
                            "lot_size": float(self._instance_lot_for_key(inst_key)),
                            "last_seen": "",
                            "last_terminal_group": "",
                            "forward_ok": 0,
                            "forward_fail": 0,
                        },
                    )
                    row["automation_enabled"] = bool(enabled_flag)
                    row["automation_mode"] = "explicit"
                    row["lot_size"] = float(self._instance_lot_for_key(inst_key))

        files = collect_files()
        if not files:
            self._set_error("no_log_files_found")
            return
        for p in files:
            # Startup backfill: never auto-trade historical rows.
            self._process_file_backfill(p, self._backfill_lines(), allow_runtime_forward_recent=False)
        self._touch()
        while not self._stop.is_set():
            files = collect_files()
            for p in files:
                if str(p.resolve()) not in self._file_offsets:
                    # Runtime-discovered new file: forward only very recent rows
                    # from initial window so first fresh signals are not dropped.
                    self._process_file_backfill(p, self._backfill_lines(), allow_runtime_forward_recent=True)
                else:
                    self._process_file_incremental(p)
            self._touch()
            time.sleep(float(self._poll_sec()))

    def get_state(self, *, limit: int = 200) -> Dict[str, Any]:
        lim = int(max(20, min(1000, int(limit or 200))))
        active_cfg = [
            str(x).strip()
            for x in self._active_indicator_names()
            if str(x).strip() and self._is_indicator_automation_allowed(x)
        ]
        lot_overrides = self._indicator_lot_overrides()
        instance_automation = self._instance_automation_overrides()
        active_instance_cfg = sorted(
            [
                str(k)
                for k, v in instance_automation.items()
                if bool(v) and self._is_indicator_automation_allowed(self._instance_key_parts(str(k))[0])
            ]
        )
        instance_lot_overrides = self._instance_lot_overrides()
        with self._lock:
            events_all = [self._enrich_event_for_view(dict(x)) for x in self._events]
            events = events_all[-lim:]
            cutoff_24h = float(time.time()) - 86400.0
            events_recent_24h = [
                dict(e)
                for e in events_all
                if (self._to_unix_or_none((e or {}).get("event_ts")) or 0.0) >= cutoff_24h
            ]
            if len(events_recent_24h) > 3000:
                events_recent_24h = events_recent_24h[-3000:]
            stats_map: Dict[str, Dict[str, Any]] = {str(k): dict(v) for k, v in self._indicator_stats.items()}
            instance_map: Dict[str, Dict[str, Any]] = {str(k): dict(v) for k, v in self._instance_stats.items()}
            for name in active_cfg:
                key = self._indicator_key(name)
                if not key:
                    continue
                row = stats_map.setdefault(
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
                        "automation_enabled": False,
                        "lot_size": float(lot_overrides.get(key) or self._default_indicator_lot()),
                        "last_seen": "",
                        "last_symbol": "",
                        "last_timeframe": "",
                        "forward_ok": 0,
                        "forward_fail": 0,
                    },
                )
                row["indicator"] = str(row.get("indicator") or name or key)
                row["automation_enabled"] = bool(row.get("automation_enabled"))
                try:
                    lot = float(row.get("lot_size") or 0.0)
                    if not math.isfinite(float(lot)) or float(lot) <= 0.0:
                        row["lot_size"] = float(lot_overrides.get(key) or self._default_indicator_lot())
                except Exception:
                    row["lot_size"] = float(lot_overrides.get(key) or self._default_indicator_lot())
            for inst_key_raw, inst_enabled in instance_automation.items():
                k = str(inst_key_raw or "").strip()
                if not k:
                    continue
                ik, sym, tf = self._instance_key_parts(k)
                row = instance_map.setdefault(
                    k,
                    {
                        "instance_key": k,
                        "indicator": ik,
                        "indicator_key": ik,
                        "symbol": sym,
                        "timeframe": tf,
                        "event_count": 0,
                        "signal_hint_count": 0,
                        "last_signal_hint": "",
                        "last_signal_profile": "",
                        "last_signal_seen": "",
                        "last_signal_message": "",
                        "automation_enabled": bool(inst_enabled),
                        "automation_mode": "explicit",
                        "lot_size": float(instance_lot_overrides.get(k.lower()) or self._instance_lot_for_key(k)),
                        "last_seen": "",
                        "last_terminal_group": "",
                        "forward_ok": 0,
                        "forward_fail": 0,
                    },
                )
                row["automation_mode"] = "explicit"
                row["automation_enabled"] = bool(inst_enabled)
                row["lot_size"] = float(instance_lot_overrides.get(k.lower()) or row.get("lot_size") or self._instance_lot_for_key(k))

            normalized_instances: List[Dict[str, Any]] = []
            for k, row in instance_map.items():
                inst_key = str(k or "").strip()
                indicator_key = str((row or {}).get("indicator_key") or "")
                indicator_name = str((row or {}).get("indicator") or indicator_key or "")
                sym = str((row or {}).get("symbol") or "").strip().upper()
                tf = str((row or {}).get("timeframe") or "").strip().upper()
                if (not sym or not tf) and inst_key:
                    ik2, sym2, tf2 = self._instance_key_parts(inst_key)
                    indicator_key = indicator_key or ik2
                    indicator_name = indicator_name or ik2
                    sym = sym or sym2
                    tf = tf or tf2
                mode = str((row or {}).get("automation_mode") or "inherit").strip().lower()
                explicit_enabled = bool((row or {}).get("automation_enabled"))
                indicator_enabled = bool((stats_map.get(indicator_key, {}) or {}).get("automation_enabled"))
                effective_enabled = bool(explicit_enabled) if mode == "explicit" else bool(indicator_enabled)
                lot_raw = (row or {}).get("lot_size")
                try:
                    lot_val = float(lot_raw if lot_raw is not None else 0.0)
                except Exception:
                    lot_val = 0.0
                if not math.isfinite(float(lot_val)) or float(lot_val) <= 0.0:
                    lot_val = float(instance_lot_overrides.get(inst_key.lower()) or self._instance_lot_for_key(inst_key))
                norm = dict(row or {})
                norm["instance_key"] = inst_key
                norm["indicator_key"] = indicator_key
                norm["indicator"] = indicator_name
                norm["symbol"] = sym
                norm["timeframe"] = tf
                norm["automation_mode"] = "explicit" if mode == "explicit" else "inherit"
                norm["automation_enabled"] = bool(explicit_enabled)
                norm["effective_automation_enabled"] = bool(effective_enabled)
                norm["lot_size"] = float(max(0.01, min(100.0, float(lot_val))))
                normalized_instances.append(norm)
            chart_instances_all = [dict(x) for x in normalized_instances]
            stats = [
                dict(x)
                for x in stats_map.values()
                if self._is_indicator_automation_allowed((x or {}).get("indicator_key") or (x or {}).get("indicator"))
            ]
            files = list(self._file_offsets.keys())
            normalized_instances = [
                dict(x)
                for x in normalized_instances
                if self._is_indicator_automation_allowed((x or {}).get("indicator_key") or (x or {}).get("indicator"))
            ]
            chart_groups_seen: set[str] = set()
            for ev in events:
                g = str((ev or {}).get("terminal_group") or "").strip().lower()
                if g:
                    chart_groups_seen.add(g)
            for inst in normalized_instances:
                g = str((inst or {}).get("last_terminal_group") or "").strip().lower()
                if g:
                    chart_groups_seen.add(g)
            preferred_chart_groups = ["mt4", "mt5", "mt5_demo", "unknown"]
            chart_groups_sorted = [g for g in preferred_chart_groups if g in chart_groups_seen]
            for g in sorted(chart_groups_seen):
                if g not in chart_groups_sorted:
                    chart_groups_sorted.append(g)
            out = {
                "ok": True,
                "config": {
                    "enabled": bool(self._enabled()),
                    "data_path": str(self._data_path()),
                    "poll_sec": float(self._poll_sec()),
                    "backfill_lines": int(self._backfill_lines()),
                    "active_indicators": list(active_cfg),
                    "active_instances": list(active_instance_cfg),
                    "restore_active_on_start": bool(self._restore_active_indicators_on_start()),
                    "default_indicator_lot": float(self._default_indicator_lot()),
                },
                "running": bool(self._running),
                "last_error": str(self._last_error or ""),
                "last_tick": str(self._last_tick_iso or ""),
                "forward_total": int(self._forward_total),
                "forward_ok": int(self._forward_ok),
                "forward_fail": int(self._forward_fail),
                "forward_skip_stale": int(self._forward_skip_stale),
                "forward_skip_duplicate": int(self._forward_skip_duplicate),
                "forward_skip_backfill": int(self._forward_skip_backfill),
                "forward_skip_disabled": int(self._forward_skip_disabled),
                "forward_skip_no_hint": int(self._forward_skip_no_hint),
                "forward_skip_no_callback": int(self._forward_skip_no_callback),
                "last_forward": str(self._last_forward_iso or ""),
                "last_forward_indicator": str(self._last_forward_indicator or ""),
                "last_forward_error": str(self._last_forward_error or ""),
                "watched_files_count": int(len(files)),
                "watched_files": files[-12:],
                "indicator_count": int(len(stats)),
                "instance_count": int(len(normalized_instances)),
                "indicators": sorted(stats, key=lambda r: str((r or {}).get("last_seen") or ""), reverse=True),
                "instances": sorted(normalized_instances, key=lambda r: str((r or {}).get("last_seen") or ""), reverse=True),
                "chart_instances": sorted(chart_instances_all, key=lambda r: str((r or {}).get("last_seen") or ""), reverse=True),
                "events": events,
                "events_recent_24h": events_recent_24h,
                "chart_groups": chart_groups_sorted,
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

    def update_indicator_settings(
        self,
        *,
        indicator: str,
        enabled: Optional[bool] = None,
        lot_size: Optional[float] = None,
    ) -> Dict[str, Any]:
        name = str(indicator or "").strip()
        if not name:
            return {"ok": False, "error": "missing_indicator"}
        key = self._indicator_key(name)
        if not key:
            return {"ok": False, "error": "invalid_indicator"}
        if not self._is_indicator_automation_allowed(key):
            return {
                "ok": False,
                "error": "indicator_not_allowed_for_automation",
                "allowed": [
                    "Hydra Signals Indicator",
                    "Forex Uranus direction",
                    "ForexCyperSystem",
                    "Alchemy Pulse",
                    "Intrepid Trend Direction",
                ],
            }

        lot_value: Optional[float] = None
        if lot_size is not None:
            try:
                lv = float(lot_size)
            except Exception:
                return {"ok": False, "error": "invalid_lot_size"}
            if not math.isfinite(float(lv)) or float(lv) <= 0.0:
                return {"ok": False, "error": "invalid_lot_size"}
            lot_value = float(max(0.01, min(100.0, float(lv))))

        persisted_active_by_key: Dict[str, str] = {
            self._indicator_key(x): str(x).strip()
            for x in self._active_indicator_names()
            if self._indicator_key(x)
        }
        persisted_lots = self._indicator_lot_overrides()

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
                    "automation_enabled": False,
                    "lot_size": float(persisted_lots.get(key) or self._default_indicator_lot()),
                    "last_seen": "",
                    "last_symbol": "",
                    "last_timeframe": "",
                    "forward_ok": 0,
                    "forward_fail": 0,
                },
            )
            st["indicator"] = name or st.get("indicator") or key
            if enabled is not None:
                st["automation_enabled"] = bool(enabled)
            if lot_value is not None:
                st["lot_size"] = float(lot_value)
                persisted_lots[key] = float(lot_value)
            else:
                current_lot = persisted_lots.get(key) or st.get("lot_size") or self._default_indicator_lot()
                st["lot_size"] = float(max(0.01, min(100.0, float(current_lot))))
                persisted_lots[key] = float(st["lot_size"])

            if enabled is not None:
                if bool(enabled):
                    persisted_active_by_key[key] = str(st.get("indicator") or name or key)
                else:
                    persisted_active_by_key.pop(key, None)

            active_names = [
                str(v).strip()
                for _k, v in sorted(persisted_active_by_key.items(), key=lambda it: str(it[1]).lower())
                if str(v).strip()
            ]

        updates = {
            "MT4_LOG_AUTOMATION_ACTIVE_INDICATORS": "|".join(active_names),
            "MT4_LOG_AUTOMATION_INDICATOR_LOTS": self._serialize_indicator_lot_overrides(persisted_lots),
        }
        ok, status = self._upsert_env_values(updates)
        out = self.get_state(limit=200)
        out["persist_ok"] = bool(ok)
        out["persist_status"] = str(status)
        out["updated"] = dict(updates)
        return out

    def update_instance_settings(
        self,
        *,
        indicator: str,
        symbol: str,
        timeframe: str,
        enabled: Optional[bool] = None,
        lot_size: Optional[float] = None,
    ) -> Dict[str, Any]:
        name = str(indicator or "").strip()
        sym = str(symbol or "").strip().upper()
        tf = str(timeframe or "").strip().upper()
        if not name:
            return {"ok": False, "error": "missing_indicator"}
        if not sym or not tf:
            return {"ok": False, "error": "missing_symbol_or_timeframe"}
        if not self._is_indicator_automation_allowed(name):
            return {
                "ok": False,
                "error": "indicator_not_allowed_for_automation",
                "allowed": [
                    "Hydra Signals Indicator",
                    "Forex Uranus direction",
                    "ForexCyperSystem",
                    "Alchemy Pulse",
                    "Intrepid Trend Direction",
                ],
            }
        inst_key = self._instance_key(indicator=name, symbol=sym, timeframe=tf)
        if not inst_key:
            return {"ok": False, "error": "invalid_instance_key"}
        ik = self._indicator_key(name)

        lot_value: Optional[float] = None
        if lot_size is not None:
            try:
                lv = float(lot_size)
            except Exception:
                return {"ok": False, "error": "invalid_lot_size"}
            if not math.isfinite(float(lv)) or float(lv) <= 0.0:
                return {"ok": False, "error": "invalid_lot_size"}
            lot_value = float(max(0.01, min(100.0, float(lv))))

        persisted_automation = self._instance_automation_overrides()
        persisted_lots = self._instance_lot_overrides()

        with self._lock:
            row = self._instance_stats.setdefault(
                inst_key,
                {
                    "instance_key": inst_key,
                    "indicator": name,
                    "indicator_key": ik,
                    "symbol": sym,
                    "timeframe": tf,
                    "event_count": 0,
                    "signal_hint_count": 0,
                    "last_signal_hint": "",
                    "last_signal_profile": "",
                    "last_signal_seen": "",
                    "last_signal_message": "",
                    "automation_enabled": False,
                    "automation_mode": "inherit",
                    "lot_size": float(persisted_lots.get(inst_key.lower()) or self._instance_lot_for_key(inst_key)),
                    "last_seen": "",
                    "forward_ok": 0,
                    "forward_fail": 0,
                },
            )
            row["indicator"] = name
            row["indicator_key"] = ik
            row["symbol"] = sym
            row["timeframe"] = tf

            if enabled is not None:
                row["automation_mode"] = "explicit"
                row["automation_enabled"] = bool(enabled)
                persisted_automation[inst_key.lower()] = bool(enabled)

            if lot_value is not None:
                row["lot_size"] = float(lot_value)
                persisted_lots[inst_key.lower()] = float(lot_value)
            else:
                try:
                    current_lot = float(row.get("lot_size") or 0.0)
                except Exception:
                    current_lot = 0.0
                if not math.isfinite(float(current_lot)) or float(current_lot) <= 0.0:
                    row["lot_size"] = float(persisted_lots.get(inst_key.lower()) or self._instance_lot_for_key(inst_key))
                persisted_lots[inst_key.lower()] = float(row.get("lot_size") or self._instance_lot_for_key(inst_key))

        active_instances = sorted([str(k) for k, v in persisted_automation.items() if bool(v)])
        updates = {
            "MT4_LOG_AUTOMATION_ACTIVE_INSTANCES": json.dumps(active_instances, ensure_ascii=True, separators=(",", ":")),
            "MT4_LOG_AUTOMATION_INSTANCE_AUTOMATION": self._serialize_instance_automation_overrides(persisted_automation),
            "MT4_LOG_AUTOMATION_INSTANCE_LOTS": self._serialize_instance_lot_overrides(persisted_lots),
        }
        ok, status = self._upsert_env_values(updates)
        out = self.get_state(limit=200)
        out["persist_ok"] = bool(ok)
        out["persist_status"] = str(status)
        out["updated"] = dict(updates)
        return out

    def set_indicator_automation(self, *, indicator: str, enabled: bool) -> Dict[str, Any]:
        return self.update_indicator_settings(indicator=indicator, enabled=bool(enabled), lot_size=None)

    def set_instance_automation(self, *, indicator: str, symbol: str, timeframe: str, enabled: bool) -> Dict[str, Any]:
        return self.update_instance_settings(
            indicator=indicator,
            symbol=symbol,
            timeframe=timeframe,
            enabled=bool(enabled),
            lot_size=None,
        )

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
