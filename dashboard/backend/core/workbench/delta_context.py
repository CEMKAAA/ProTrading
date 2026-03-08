"""Delta context tracking for Workbench Agent sessions."""

from __future__ import annotations

import threading
from typing import Any, Dict, List, Optional

_MANAGERS: Dict[str, "DeltaContextManager"] = {}
_MANAGERS_LOCK = threading.Lock()
PRICE_MOVE_ATR_THRESHOLD = 0.3


def get_delta_manager(session_id: str) -> "DeltaContextManager":
    sid = str(session_id or "")
    with _MANAGERS_LOCK:
        mgr = _MANAGERS.get(sid)
        if mgr is None:
            mgr = DeltaContextManager(session_id=sid)
            _MANAGERS[sid] = mgr
        return mgr


def reset_delta_manager(session_id: str) -> None:
    with _MANAGERS_LOCK:
        _MANAGERS.pop(str(session_id or ""), None)


def _to_float(v: Any, fallback: float = 0.0) -> float:
    try:
        out = float(v)
        if out != out:  # NaN check
            return float(fallback)
        return out
    except Exception:
        return float(fallback)


def _position_ids(rows: Any) -> List[Any]:
    out: List[Any] = []
    if not isinstance(rows, list):
        return out
    for row in rows:
        if not isinstance(row, dict):
            continue
        rid = row.get("id")
        if rid is not None:
            out.append(rid)
    return out


class DeltaContextManager:
    def __init__(self, session_id: str) -> None:
        self.session_id = str(session_id or "")
        self._last: Dict[str, Any] = {}
        self._turn_count = 0
        self._lock = threading.Lock()

    @property
    def turn_count(self) -> int:
        return int(self._turn_count)

    def compute_delta(self, current: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        with self._lock:
            ctx = current if isinstance(current, dict) else {}
            last = self._last if isinstance(self._last, dict) else {}
            is_first = not bool(last)
            delta: Dict[str, Any] = {}

            cur_price = ctx.get("last_price")
            old_price = last.get("last_price")
            atr = _to_float(ctx.get("atr_14"), 1.0)
            if cur_price is not None:
                if is_first:
                    delta["price"] = cur_price
                elif old_price is not None and atr > 0:
                    move_atr = abs(_to_float(cur_price) - _to_float(old_price)) / atr
                    if move_atr > float(PRICE_MOVE_ATR_THRESHOLD):
                        delta["price"] = cur_price
                        delta["price_move_atr"] = round(move_atr, 2)

            cur_balance = ctx.get("balance")
            old_balance = last.get("balance")
            if cur_balance is not None and (is_first or cur_balance != old_balance):
                delta["balance"] = cur_balance

            cur_positions = ctx.get("positions") if isinstance(ctx.get("positions"), list) else []
            old_positions = last.get("positions") if isinstance(last.get("positions"), list) else []
            cur_ids = set(_position_ids(cur_positions))
            old_ids = set(_position_ids(old_positions))
            opened_ids = cur_ids - old_ids
            closed_ids = old_ids - cur_ids
            if opened_ids:
                delta["positions_opened"] = [p for p in cur_positions if isinstance(p, dict) and p.get("id") in opened_ids]
            if closed_ids:
                delta["positions_closed_ids"] = sorted(list(closed_ids), key=lambda x: str(x))

            cur_triggers = ctx.get("triggers") if isinstance(ctx.get("triggers"), list) else []
            old_triggers = last.get("triggers") if isinstance(last.get("triggers"), list) else []
            cur_trigger_count = len(cur_triggers)
            old_trigger_count = len(old_triggers)
            if is_first or cur_trigger_count != old_trigger_count:
                delta["trigger_count"] = int(cur_trigger_count)
                if not is_first:
                    delta["triggers_changed"] = True

            self._last = {
                "last_price": cur_price,
                "atr_14": ctx.get("atr_14"),
                "balance": cur_balance,
                "positions": list(cur_positions),
                "triggers": list(cur_triggers),
            }
            self._turn_count += 1
            return delta
