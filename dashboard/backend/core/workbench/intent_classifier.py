"""Intent classification for Workbench Agent tool pruning.

This module is intentionally deterministic and lightweight.
"""

from __future__ import annotations

import re
from typing import Dict, List, Set

TOOL_INTENT_MAP: Dict[str, List[str]] = {
    "market_query": ["get_market_snapshot", "get_indicator_values"],
    "position_query": ["get_positions_detail", "close_trade"],
    "trade_action": ["place_trade", "schedule_trade_entry", "cancel_scheduled_entry", "get_market_snapshot"],
    "analysis": ["scan_tool", "scan_draw_fvg_range", "get_market_snapshot", "get_indicator_values"],
    "news_query": ["get_market_news", "get_market_snapshot"],
    "research": ["run_research_optimize", "run_ml_diagnostic"],
    "memory": ["search_memory", "save_memory_note"],
    "trigger_query": ["get_scheduled_triggers", "cancel_scheduled_entry"],
    "visibility": ["set_indicator_visibility", "set_market_context"],
    "identity": ["set_agent_personality"],
}

ALWAYS_INCLUDE: List[str] = ["submit_proposed_actions"]
EXPLICIT_TOOL_NAMES: Set[str] = {
    "scan_tool",
    "scan_draw_fvg_range",
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


def get_tools_for_intent(message: str) -> List[str]:
    """Return a pruned tool-name list for the given message."""
    raw = str(message or "")
    intents = classify_intent(raw)
    tools: Set[str] = set(ALWAYS_INCLUDE)
    for intent in intents:
        tools.update(TOOL_INTENT_MAP.get(intent, []))
    # If user explicitly names tools (common in operator prompts), always allow them.
    msg = raw.lower()
    for tool_name in EXPLICIT_TOOL_NAMES:
        if tool_name in msg:
            tools.add(tool_name)
    return sorted(tools)
