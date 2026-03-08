"""Shared advice routing helpers for confidence and delivery."""

from __future__ import annotations

from typing import Any, Dict, List


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        return float(v)
    except Exception:
        return float(default)


def route_advices_by_confidence(
    advices: List[Dict[str, Any]],
    config: Dict[str, Any] | None,
) -> List[Dict[str, Any]]:
    """Apply confidence thresholds and annotate delivery/status.

    Keeps suppressed entries for audit with:
    - delivery="SUPPRESS"
    - status="SKIPPED_LOW_CONF"
    """
    cfg = config or {}
    min_conf_actionable = _safe_float(cfg.get("min_confidence_actionable"), 0.75)
    min_conf_watch = _safe_float(cfg.get("min_confidence_watch"), 0.55)
    if min_conf_watch > min_conf_actionable:
        min_conf_watch = min_conf_actionable

    routed: List[Dict[str, Any]] = []
    for adv in advices:
        conf = _safe_float(adv.get("confidence"), 0.0)
        if conf >= min_conf_actionable:
            adv["delivery"] = "ACTIONABLE"
            adv["status"] = "NEW"
        elif conf >= min_conf_watch:
            adv["delivery"] = "WATCH"
            adv["status"] = "NEW"
            adv["action_json"] = {}
        else:
            adv["delivery"] = "SUPPRESS"
            adv["status"] = "SKIPPED_LOW_CONF"
            adv["action_json"] = {}
        routed.append(adv)
    return routed

