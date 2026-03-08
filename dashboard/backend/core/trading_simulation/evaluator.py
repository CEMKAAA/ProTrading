"""
Playbook evaluator: telemetry -> step statuses and action guidance.
"""

from __future__ import annotations

from typing import Any, Dict, List, Set

from .playbooks import STEP_STATUSES


def _done_step_ids(actions: List[Dict[str, Any]]) -> Set[str]:
    done: Set[str] = set()
    for a in actions:
        step_id = str(a.get("step_id") or "").strip()
        action_type = str(a.get("action_type") or "").strip().lower()
        if not step_id:
            continue
        if action_type in ("step_done", "confirm_condition", "paper_enter", "paper_close", "skip_setup"):
            done.add(step_id)
    return done


def evaluate_playbook(
    playbook: Dict[str, Any],
    telemetry: Dict[str, Any],
    actions: List[Dict[str, Any]],
) -> Dict[str, Any]:
    steps = list(playbook.get("steps", []))
    signals = telemetry.get("signals", {}) if isinstance(telemetry.get("signals"), dict) else {}
    telemetry_ok = bool(telemetry.get("telemetry_available", False))
    done_ids = _done_step_ids(actions)

    step_states: List[Dict[str, Any]] = []
    previous_all_done = True
    current_step = None

    for step in steps:
        step_id = str(step.get("id") or "")
        ready_signal = str(step.get("ready_signal") or "")
        block_signal = str(step.get("block_signal") or "")
        is_done = step_id in done_ids

        if is_done:
            status = "DONE"
            reason = "Marked complete in action journal."
        elif not telemetry_ok:
            status = "WAIT"
            reason = "Telemetry unavailable."
        elif block_signal and bool(signals.get(block_signal, False)):
            status = "BLOCKED"
            reason = step.get("invalidates") or "Blocked by invalidation signal."
        elif not previous_all_done:
            status = "WAIT"
            reason = "Complete previous step first."
        elif ready_signal and bool(signals.get(ready_signal, False)):
            status = "ACTIONABLE"
            reason = step.get("action_now") or "Actionable now."
        else:
            status = "READY"
            reason = step.get("wait_for") or "Waiting for condition."

        if status not in STEP_STATUSES:
            status = "WAIT"
        if current_step is None and status in ("ACTIONABLE", "READY", "WAIT", "BLOCKED"):
            current_step = {
                "id": step_id,
                "title": step.get("title", "Current Step"),
                "status": status,
                "why": step.get("why", ""),
                "wait_for": step.get("wait_for", ""),
                "invalidates": step.get("invalidates", ""),
                "action_now": step.get("action_now", ""),
                "reason": reason,
            }

        step_states.append(
            {
                "id": step_id,
                "title": step.get("title", step_id),
                "status": status,
                "why": step.get("why", ""),
                "wait_for": step.get("wait_for", ""),
                "invalidates": step.get("invalidates", ""),
                "action_now": step.get("action_now", ""),
                "evidence_keys": list(step.get("evidence_keys", [])),
                "reason": reason,
            }
        )
        previous_all_done = previous_all_done and (status == "DONE")

    if current_step is None and step_states:
        s0 = step_states[-1]
        current_step = {
            "id": s0["id"],
            "title": s0["title"],
            "status": s0["status"],
            "why": s0["why"],
            "wait_for": s0["wait_for"],
            "invalidates": s0["invalidates"],
            "action_now": s0["action_now"],
            "reason": s0["reason"],
        }

    return {
        "step_states": step_states,
        "current_step": current_step,
        "summary": {
            "total_steps": len(step_states),
            "done_steps": sum(1 for s in step_states if s["status"] == "DONE"),
            "blocked_steps": sum(1 for s in step_states if s["status"] == "BLOCKED"),
            "actionable_steps": sum(1 for s in step_states if s["status"] == "ACTIONABLE"),
        },
    }
