"""Simple provider circuit breaker for agent chat failover."""

from __future__ import annotations

import threading
import time
from typing import Any, Dict, Optional


class ProviderCircuitBreaker:
    def __init__(
        self,
        *,
        fail_threshold: int = 3,
        window_sec: float = 60.0,
        open_sec: float = 300.0,
        fallback_map: Optional[Dict[str, str]] = None,
    ) -> None:
        self.fail_threshold = max(1, int(fail_threshold))
        self.window_sec = max(1.0, float(window_sec))
        self.open_sec = max(5.0, float(open_sec))
        self.fallback_map = dict(fallback_map or {"claude": "local_gptoss_http", "openai_compat": "local_gptoss_http"})
        self._state: Dict[str, Dict[str, Any]] = {}
        self._lock = threading.Lock()

    def _now(self) -> float:
        return time.time()

    def _row(self, provider: str) -> Dict[str, Any]:
        key = str(provider or "").strip().lower()
        row = self._state.get(key)
        if row is None:
            row = {"failures": [], "open_until": 0.0}
            self._state[key] = row
        return row

    def get_fallback(self, provider: str) -> Optional[str]:
        key = str(provider or "").strip().lower()
        if not key:
            return None
        with self._lock:
            row = self._row(key)
            now = self._now()
            if float(row.get("open_until") or 0.0) > now:
                return str(self.fallback_map.get(key) or "").strip() or None
            return None

    def is_open(self, provider: str) -> bool:
        key = str(provider or "").strip().lower()
        if not key:
            return False
        with self._lock:
            row = self._row(key)
            return float(row.get("open_until") or 0.0) > self._now()

    def record_success(self, provider: str) -> None:
        key = str(provider or "").strip().lower()
        if not key:
            return
        with self._lock:
            row = self._row(key)
            row["failures"] = []
            row["open_until"] = 0.0

    def record_failure(self, provider: str) -> None:
        key = str(provider or "").strip().lower()
        if not key:
            return
        with self._lock:
            row = self._row(key)
            now = self._now()
            failures = [float(x) for x in list(row.get("failures") or []) if now - float(x) <= self.window_sec]
            failures.append(now)
            row["failures"] = failures
            if len(failures) >= self.fail_threshold:
                row["open_until"] = now + self.open_sec

    def snapshot(self) -> Dict[str, Any]:
        with self._lock:
            now = self._now()
            return {
                k: {
                    "recent_failures": len([x for x in list(v.get("failures") or []) if now - float(x) <= self.window_sec]),
                    "open_until": float(v.get("open_until") or 0.0),
                }
                for k, v in self._state.items()
            }


_GLOBAL_BREAKER = ProviderCircuitBreaker()


def get_circuit_breaker() -> ProviderCircuitBreaker:
    return _GLOBAL_BREAKER
