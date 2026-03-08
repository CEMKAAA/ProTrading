"""Deterministic conversation history compression utilities."""

from __future__ import annotations

from typing import Any, Dict, List


def _normalize_history(history: Any) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    if not isinstance(history, list):
        return out
    for row in history:
        if not isinstance(row, dict):
            continue
        role = str(row.get("role") or "").strip().lower()
        if role not in {"user", "assistant"}:
            continue
        content = str(row.get("content") or "").strip()
        if not content:
            continue
        out.append({"role": role, "content": content})
    return out


def _build_summary(rows: List[Dict[str, str]], max_items: int = 6, max_chars_each: int = 180) -> str:
    parts: List[str] = []
    if not rows:
        return "No prior context."
    # Bias toward recent context; older turns are less informative for current execution.
    picked = rows[-max(1, int(max_items)) :]
    for row in picked:
        role = "U" if str(row.get("role")) == "user" else "A"
        text = str(row.get("content") or "").replace("\n", " ").strip()
        if len(text) > int(max_chars_each):
            text = text[: int(max_chars_each)] + "..."
        parts.append(f"{role}: {text}")
    return " | ".join(parts)


def compress_history(history: Any, *, keep_recent: int = 2, min_messages_to_compress: int = 8) -> List[Dict[str, str]]:
    """Compress old turns into a single system summary, keep recent turns raw."""
    rows = _normalize_history(history)
    k = max(1, int(keep_recent))
    if len(rows) < max(int(min_messages_to_compress), k + 2):
        return rows
    old_rows = rows[:-k]
    recent_rows = rows[-k:]
    summary_text = _build_summary(old_rows)
    first_recent_role = str(recent_rows[0].get("role") or "").strip().lower() if recent_rows else "user"
    summary_role = "assistant" if first_recent_role == "user" else "user"
    return [{"role": summary_role, "content": f"[Session summary] {summary_text}"}] + recent_rows
