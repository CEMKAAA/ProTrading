"""Policy helpers for Workbench copilot action permissions."""

from __future__ import annotations

from typing import Dict, Set


MODE_OBSERVE = "OBSERVE"
MODE_ADVISE = "ADVISE"
MODE_ASSIST = "ASSIST"
MODE_AUTO_PAPER = "AUTO_PAPER"


def normalize_mode(mode: str | None) -> str:
    raw = str(mode or MODE_ADVISE).strip().upper()
    if raw in {MODE_OBSERVE, MODE_ADVISE, MODE_ASSIST, MODE_AUTO_PAPER}:
        return raw
    return MODE_ADVISE


def allowed_actions(mode: str | None) -> Set[str]:
    m = normalize_mode(mode)
    if m == MODE_OBSERVE:
        return set()
    if m == MODE_ADVISE:
        return {"SUGGEST_ENTRY", "SUGGEST_EXIT", "SUGGEST_RISK_ADJUSTMENT", "REVIEW_NOTE"}
    if m == MODE_ASSIST:
        return {
            "SUGGEST_ENTRY",
            "SUGGEST_EXIT",
            "SUGGEST_RISK_ADJUSTMENT",
            "AUTO_TOOL_SCAN",
            "REVIEW_NOTE",
        }
    # MODE_AUTO_PAPER
    return {
        "SUGGEST_ENTRY",
        "SUGGEST_EXIT",
        "SUGGEST_RISK_ADJUSTMENT",
        "AUTO_TOOL_SCAN",
        "AUTO_PAPER_ENTRY",
        "AUTO_PAPER_EXIT",
        "REVIEW_NOTE",
    }


def is_action_allowed(mode: str | None, action_type: str | None) -> bool:
    at = str(action_type or "").strip().upper()
    if not at:
        return False
    return at in allowed_actions(mode)


def policy_summary(mode: str | None) -> Dict[str, object]:
    m = normalize_mode(mode)
    return {
        "mode": m,
        "allowed_actions": sorted(list(allowed_actions(m))),
    }

