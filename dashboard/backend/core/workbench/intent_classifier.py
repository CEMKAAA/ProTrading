"""Intent classification for Workbench Agent tool pruning.

This module is intentionally deterministic and lightweight.

IMPORTANT: Tool selection is conversation-aware. Recent history intents
are merged with current message intents so follow-up questions don't
lose tools that were available on the prior turn.
"""

from __future__ import annotations

import re
from typing import Dict, List, Optional, Set

TOOL_INTENT_MAP: Dict[str, List[str]] = {
    "market_query": ["get_market_snapshot", "get_indicator_values"],
    "position_query": ["get_positions_detail", "close_trade"],
    "trade_action": ["place_trade", "schedule_trade_entry", "cancel_scheduled_entry", "get_market_snapshot"],
    "analysis": ["run_mtf_analysis", "run_htf_fvg_liquidity_reclaim_analysis", "scan_tool", "scan_draw_fvg_range", "get_market_snapshot", "get_indicator_values"],
    "news_query": ["get_market_news", "get_market_snapshot"],
    "research": ["run_research_optimize", "run_ml_diagnostic"],
    "memory": ["search_memory", "save_memory_note"],
    "trigger_query": ["get_scheduled_triggers", "cancel_scheduled_entry"],
    "visibility": ["set_indicator_visibility", "set_market_context"],
    "identity": ["set_agent_personality"],
    # Continuation/retry gets broad access so "try again" doesn't lose tools.
    "continuation": [
        "run_mtf_analysis", "run_htf_fvg_liquidity_reclaim_analysis", "scan_tool", "scan_draw_fvg_range",
        "get_market_snapshot", "get_indicator_values", "get_positions_detail",
        "schedule_trade_entry", "cancel_scheduled_entry", "get_scheduled_triggers",
        "get_market_news", "place_trade", "close_trade",
    ],
}

ALWAYS_INCLUDE: List[str] = ["submit_proposed_actions"]
EXPLICIT_TOOL_NAMES: Set[str] = {
    "scan_tool",
    "scan_draw_fvg_range",
    "run_mtf_analysis",
    "run_htf_fvg_liquidity_reclaim_analysis",
    "get_market_snapshot",
    "get_positions_detail",
    "get_indicator_values",
    "get_scheduled_triggers",
    "get_market_news",
    "place_trade",
    "close_trade",
    "schedule_trade_entry",
    "cancel_scheduled_entry",
    "run_research_optimize",
    "run_ml_diagnostic",
    "set_indicator_visibility",
    "set_market_context",
    "set_agent_personality",
    "search_memory",
    "save_memory_note",
}

INTENT_PATTERNS: Dict[str, re.Pattern[str]] = {
    "market_query": re.compile(
        r"price|market|chart|candle|bar|level|support|resistance|vwap|ema|rsi|atr|trend|bias|snapshot|quote",
        re.IGNORECASE,
    ),
    "position_query": re.compile(
        r"position|trade[sd]?|pnl|p&l|profit|loss|balance|portfolio|equity|drawdown|win\s*rate|close\s+(trade|position)",
        re.IGNORECASE,
    ),
    "trade_action": re.compile(
        r"\b(buy|sell|long|short|enter|entry|place|execute|go\s+long|go\s+short|open\s+trade)\b",
        re.IGNORECASE,
    ),
    "analysis": re.compile(
        r"scan|fvg|fair\s*value\s*gap|setup|pattern|signal|analy[sz]e|structure|order\s*block|mitigation|breaker|liquidity|sweep|equal\s+high|equal\s+low|stop\s*hunt",
        re.IGNORECASE,
    ),
    "news_query": re.compile(
        r"news|headline|calendar|macro|economic|fomc|cpi|nfp|powell|rate\s*decision",
        re.IGNORECASE,
    ),
    "research": re.compile(
        r"optimi[sz]e|research|backtest|ml\b|diagnos|feature\s+drift|parameter",
        re.IGNORECASE,
    ),
    "memory": re.compile(
        r"remember|memory|recall|forget|note|preference|teach|lesson",
        re.IGNORECASE,
    ),
    "trigger_query": re.compile(
        r"trigger|schedule|pending|condition|wait\s+for|conditional|armed",
        re.IGNORECASE,
    ),
    "visibility": re.compile(
        r"\b(show|hide|toggle|display|enable|disable)\b.*\b(indicator|ema|sma|rsi|bb|atr|overlay)\b|switch.*(symbol|timeframe|market)",
        re.IGNORECASE,
    ),
    "identity": re.compile(
        r"\b(master|apprentice|persona|personality|identity|profile)\b.*\b(switch|set|change|use)\b|\b(use|set|switch)\b.*\b(master|apprentice|profile)\b",
        re.IGNORECASE,
    ),
    "continuation": re.compile(
        r"\b(try\s+again|retry|redo|rerun|re[\-\s]?run|do\s+it\s+again|run\s+again|repeat|continue|go\s+ahead|proceed|same\s+again|one\s+more\s+time|canceled?\s+it)\b",
        re.IGNORECASE,
    ),
}

DEFAULT_INTENTS: Set[str] = {"market_query", "position_query"}


def classify_intent(message: str) -> Set[str]:
    """Classify a message into one or more high-level intent buckets."""
    if not isinstance(message, str) or not message.strip():
        return set(DEFAULT_INTENTS)
    intents: Set[str] = set()
    for intent_name, pattern in INTENT_PATTERNS.items():
        if pattern.search(message):
            intents.add(intent_name)
    return intents if intents else set(DEFAULT_INTENTS)


def get_tools_for_intent(
    message: str,
    conversation_history: Optional[List[Dict]] = None,
) -> List[str]:
    """Return a pruned tool-name list for the given message.

    When ``conversation_history`` is provided, intents from the last few
    **user** messages are merged so follow-up questions (e.g. "why did you
    enter that?") don't lose tools that were available on the prior turn.
    """
    raw = str(message or "")
    current_intents = classify_intent(raw)

    # Merge intents from recent conversation history (last 4 user messages).
    merged_intents: Set[str] = set(current_intents)
    if isinstance(conversation_history, list):
        recent_user_msgs: List[str] = []
        for row in reversed(conversation_history):
            if not isinstance(row, dict):
                continue
            if str(row.get("role") or "").strip().lower() != "user":
                continue
            content = str(row.get("content") or "").strip()
            if content:
                recent_user_msgs.append(content)
            if len(recent_user_msgs) >= 4:
                break
        for hist_msg in recent_user_msgs:
            merged_intents.update(classify_intent(hist_msg))

    tools: Set[str] = set(ALWAYS_INCLUDE)
    for intent in merged_intents:
        tools.update(TOOL_INTENT_MAP.get(intent, []))
    # If user explicitly names tools (common in operator prompts), always allow them.
    msg = raw.lower()
    for tool_name in EXPLICIT_TOOL_NAMES:
        if tool_name in msg:
            tools.add(tool_name)
    # Also check explicit tool names in recent history.
    if isinstance(conversation_history, list):
        for row in conversation_history[-6:]:
            if not isinstance(row, dict):
                continue
            hist_content = str(row.get("content") or "").strip().lower()
            for tool_name in EXPLICIT_TOOL_NAMES:
                if tool_name in hist_content:
                    tools.add(tool_name)
    return sorted(tools)
