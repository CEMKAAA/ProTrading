"""In-memory runtime settings for workbench copilot sessions.

Used for sensitive values (API keys) and ephemeral provider runtime config.
These settings are never persisted to the database.
"""

from __future__ import annotations

import threading
from typing import Any, Dict


_RUNTIME_BY_SESSION: Dict[int, Dict[str, Any]] = {}
_LOCK = threading.Lock()


def set_runtime(copilot_session_id: int, runtime: Dict[str, Any] | None) -> None:
    sid = int(copilot_session_id)
    payload = runtime if isinstance(runtime, dict) else {}
    with _LOCK:
        _RUNTIME_BY_SESSION[sid] = dict(payload)


def get_runtime(copilot_session_id: int) -> Dict[str, Any]:
    sid = int(copilot_session_id)
    with _LOCK:
        row = _RUNTIME_BY_SESSION.get(sid) or {}
        return dict(row)


def clear_runtime(copilot_session_id: int) -> None:
    sid = int(copilot_session_id)
    with _LOCK:
        _RUNTIME_BY_SESSION.pop(sid, None)

