# Smart Context Pipeline - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Cut Workbench Agent input tokens by ~80% via layered prompt caching, delta context, intent-based tool pruning, and conversation compression — with zero quality degradation.

**Architecture:** Six independent components are added to the existing `WorkbenchAgent` pipeline: (1) an intent classifier that selects 3-5 tools per turn instead of 16, (2) a delta context manager that tracks per-session state and sends only changes, (3) a conversation compressor that summarizes old turns, (4) a refactored layered prompt builder optimized for Anthropic prompt caching, (5) expanded deterministic fast-path for zero-LLM queries, and (6) a circuit breaker for automatic Claude→local failover.

**Tech Stack:** Python 3.12, pytest, Anthropic prompt caching (`prompt-caching-2024-07-31`), httpx, existing Pydantic models.

**Key constraint:** `WorkbenchAgent` is stateless (instantiated fresh per request at `simulation_routes.py:7711`). All persistent state (delta tracking, circuit breaker) must live in module-level registries in `simulation_routes.py` or in a new utility module.

---

### Task 1: Intent Classifier Module

**Files:**
- Create: `dashboard/backend/core/workbench/intent_classifier.py`
- Test: `tests/test_workbench_intent_classifier.py`

**Step 1: Write the failing tests**

```python
# tests/test_workbench_intent_classifier.py
import pytest
from dashboard.backend.core.workbench.intent_classifier import classify_intent, get_tools_for_intent

class TestClassifyIntent:
    def test_market_query(self):
        intents = classify_intent("what's the current price?")
        assert "market_query" in intents

    def test_trade_action(self):
        intents = classify_intent("buy 0.1 lots at market with SL at 2900")
        assert "trade_action" in intents

    def test_position_query(self):
        intents = classify_intent("show my open positions and P&L")
        assert "position_query" in intents

    def test_analysis_scan(self):
        intents = classify_intent("scan for FVG patterns on the chart")
        assert "analysis" in intents

    def test_memory_intent(self):
        intents = classify_intent("remember that I prefer 2:1 R:R minimum")
        assert "memory" in intents

    def test_trigger_intent(self):
        intents = classify_intent("show me pending triggers")
        assert "trigger_query" in intents

    def test_research_intent(self):
        intents = classify_intent("run ML diagnostic on recent trades")
        assert "research" in intents

    def test_visibility_intent(self):
        intents = classify_intent("show EMA 200 on the chart")
        assert "visibility" in intents

    def test_multi_intent(self):
        intents = classify_intent("check the price and buy if it breaks above 3000")
        assert "market_query" in intents
        assert "trade_action" in intents

    def test_unknown_defaults_to_market_position(self):
        intents = classify_intent("hello how are you")
        assert "market_query" in intents
        assert "position_query" in intents

class TestGetToolsForIntent:
    def test_market_query_tools(self):
        tools = get_tools_for_intent("what's the price?")
        assert "get_market_snapshot" in tools
        assert "get_indicator_values" in tools
        assert "submit_proposed_actions" in tools
        # Should NOT include unrelated tools
        assert "run_research_optimize" not in tools
        assert "save_memory_note" not in tools

    def test_trade_action_tools(self):
        tools = get_tools_for_intent("buy gold now with SL at 2900")
        assert "place_trade" in tools
        assert "get_market_snapshot" in tools

    def test_always_includes_submit(self):
        tools = get_tools_for_intent("anything")
        assert "submit_proposed_actions" in tools

    def test_returns_list_of_strings(self):
        tools = get_tools_for_intent("scan for setups")
        assert isinstance(tools, list)
        assert all(isinstance(t, str) for t in tools)

    def test_max_reasonable_tool_count(self):
        # Even with multi-intent, should not return all 17
        tools = get_tools_for_intent("buy after scanning FVG and check memory")
        assert len(tools) <= 12
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_intent_classifier.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'dashboard.backend.core.workbench.intent_classifier'`

**Step 3: Write the implementation**

```python
# dashboard/backend/core/workbench/intent_classifier.py
"""Intent classification for Workbench Agent tool pruning.

Maps user messages to relevant tool subsets via regex/keyword matching.
No LLM needed — fast, deterministic, zero cost.
"""

from __future__ import annotations

import re
from typing import Dict, List, Set

# Intent → tool names mapping
TOOL_INTENT_MAP: Dict[str, List[str]] = {
    "market_query":   ["get_market_snapshot", "get_indicator_values"],
    "position_query": ["get_positions_detail", "close_trade"],
    "trade_action":   ["place_trade", "schedule_trade_entry", "cancel_scheduled_entry", "get_market_snapshot"],
    "analysis":       ["scan_tool", "scan_draw_fvg_range", "get_market_snapshot", "get_indicator_values"],
    "research":       ["run_research_optimize", "run_ml_diagnostic"],
    "memory":         ["search_memory", "save_memory_note"],
    "trigger_query":  ["get_scheduled_triggers", "cancel_scheduled_entry"],
    "visibility":     ["set_indicator_visibility", "set_market_context"],
}

# Always available regardless of intent
ALWAYS_INCLUDE: List[str] = ["submit_proposed_actions"]

# Intent detection patterns (compiled once at import time)
INTENT_PATTERNS: Dict[str, re.Pattern] = {
    "market_query":   re.compile(
        r"price|market|chart|candle|bar|level|support|resistance|vwap|ema|rsi|atr|"
        r"trend|bias|snapshot|what.s.*(gold|nas|us500|xau)", re.IGNORECASE
    ),
    "position_query": re.compile(
        r"position|trade[sd]?|pnl|p&l|profit|loss|balance|close\s+(my|the|this|trade|position)|"
        r"portfolio|equity|drawdown|win\s*rate", re.IGNORECASE
    ),
    "trade_action":   re.compile(
        r"\b(buy|sell|long|short|enter|entry|place|execute|go\s+long|go\s+short)\b", re.IGNORECASE
    ),
    "analysis":       re.compile(
        r"scan|fvg|fair.value|setup|pattern|signal|analyz|analys|structure|order\s*block", re.IGNORECASE
    ),
    "research":       re.compile(
        r"optimi[zs]|research|backtest|ml\b|diagnos|feature\s+drift", re.IGNORECASE
    ),
    "memory":         re.compile(
        r"remember|memory|recall|forget|note|rule.*save|preference|teach", re.IGNORECASE
    ),
    "trigger_query":  re.compile(
        r"trigger|schedule|pending|condition|wait\s+for|conditional", re.IGNORECASE
    ),
    "visibility":     re.compile(
        r"\b(show|hide|toggle|display)\b.*\b(indicator|ema|sma|rsi|bb|atr|overlay)\b|"
        r"switch.*(symbol|timeframe|instrument)", re.IGNORECASE
    ),
}

# Default intents when no pattern matches (safe fallback)
DEFAULT_INTENTS = {"market_query", "position_query"}


def classify_intent(message: str) -> Set[str]:
    """Classify user message into intent categories via regex matching."""
    if not message or not isinstance(message, str):
        return set(DEFAULT_INTENTS)

    intents: Set[str] = set()
    for intent_name, pattern in INTENT_PATTERNS.items():
        if pattern.search(message):
            intents.add(intent_name)

    return intents if intents else set(DEFAULT_INTENTS)


def get_tools_for_intent(message: str) -> List[str]:
    """Return sorted list of tool names relevant to the user's message."""
    intents = classify_intent(message)
    tools: Set[str] = set(ALWAYS_INCLUDE)
    for intent in intents:
        tools.update(TOOL_INTENT_MAP.get(intent, []))
    return sorted(tools)
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_intent_classifier.py -v`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add dashboard/backend/core/workbench/intent_classifier.py tests/test_workbench_intent_classifier.py
git commit -m "feat: add intent classifier for agent tool pruning"
```

---

### Task 2: Delta Context Manager

**Files:**
- Create: `dashboard/backend/core/workbench/delta_context.py`
- Test: `tests/test_workbench_delta_context.py`

**Step 1: Write the failing tests**

```python
# tests/test_workbench_delta_context.py
import pytest
from dashboard.backend.core.workbench.delta_context import DeltaContextManager, get_delta_manager

class TestDeltaContextManager:
    def test_first_turn_returns_full_summary(self):
        mgr = DeltaContextManager("sess_1")
        ctx = {
            "last_price": 3050.0,
            "atr_14": 20.0,
            "balance": 10000.0,
            "positions": [{"id": 1, "direction": "BUY", "entry_price": 3040.0}],
            "triggers": [{"id": 10, "status": "pending"}],
        }
        delta = mgr.compute_delta(ctx)
        # First turn: everything is new, so all fields present
        assert "price" in delta
        assert delta["price"] == 3050.0
        assert delta["balance"] == 10000.0
        assert len(delta["positions_opened"]) == 1
        assert delta["trigger_count"] == 1

    def test_no_change_returns_minimal(self):
        mgr = DeltaContextManager("sess_1")
        ctx = {
            "last_price": 3050.0,
            "atr_14": 20.0,
            "balance": 10000.0,
            "positions": [{"id": 1}],
            "triggers": [{"id": 10, "status": "pending"}],
        }
        mgr.compute_delta(ctx)  # first turn
        delta = mgr.compute_delta(ctx)  # second turn, identical
        # Nothing changed: delta should be empty or near-empty
        assert "price" not in delta
        assert "balance" not in delta
        assert "positions_opened" not in delta
        assert "positions_closed_ids" not in delta

    def test_price_move_detected(self):
        mgr = DeltaContextManager("sess_1")
        ctx1 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0, "positions": [], "triggers": []}
        mgr.compute_delta(ctx1)
        ctx2 = {"last_price": 3060.0, "atr_14": 20.0, "balance": 10000.0, "positions": [], "triggers": []}
        delta = mgr.compute_delta(ctx2)
        # 10 / 20 = 0.5 ATR, above 0.3 threshold
        assert "price" in delta
        assert delta["price"] == 3060.0
        assert 0.4 < delta["price_move_atr"] < 0.6

    def test_small_price_move_ignored(self):
        mgr = DeltaContextManager("sess_1")
        ctx1 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0, "positions": [], "triggers": []}
        mgr.compute_delta(ctx1)
        ctx2 = {"last_price": 3053.0, "atr_14": 20.0, "balance": 10000.0, "positions": [], "triggers": []}
        delta = mgr.compute_delta(ctx2)
        # 3 / 20 = 0.15 ATR, below threshold
        assert "price" not in delta

    def test_position_opened(self):
        mgr = DeltaContextManager("sess_1")
        ctx1 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0, "positions": [], "triggers": []}
        mgr.compute_delta(ctx1)
        ctx2 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0,
                "positions": [{"id": 1, "direction": "BUY", "entry_price": 3045.0}], "triggers": []}
        delta = mgr.compute_delta(ctx2)
        assert len(delta.get("positions_opened", [])) == 1
        assert delta["positions_opened"][0]["id"] == 1

    def test_position_closed(self):
        mgr = DeltaContextManager("sess_1")
        ctx1 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0,
                "positions": [{"id": 1}], "triggers": []}
        mgr.compute_delta(ctx1)
        ctx2 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 9900.0,
                "positions": [], "triggers": []}
        delta = mgr.compute_delta(ctx2)
        assert 1 in delta.get("positions_closed_ids", [])
        assert delta["balance"] == 9900.0

    def test_trigger_count_change(self):
        mgr = DeltaContextManager("sess_1")
        ctx1 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0,
                "positions": [], "triggers": [{"id": 10, "status": "pending"}]}
        mgr.compute_delta(ctx1)
        ctx2 = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0,
                "positions": [], "triggers": []}
        delta = mgr.compute_delta(ctx2)
        assert delta.get("triggers_changed") is True
        assert delta["trigger_count"] == 0

    def test_turn_counter(self):
        mgr = DeltaContextManager("sess_1")
        ctx = {"last_price": 3050.0, "atr_14": 20.0, "balance": 10000.0, "positions": [], "triggers": []}
        mgr.compute_delta(ctx)
        mgr.compute_delta(ctx)
        mgr.compute_delta(ctx)
        assert mgr.turn_count == 3

class TestGetDeltaManager:
    def test_returns_same_instance_for_same_session(self):
        m1 = get_delta_manager("test_sess")
        m2 = get_delta_manager("test_sess")
        assert m1 is m2

    def test_returns_different_for_different_session(self):
        m1 = get_delta_manager("sess_a")
        m2 = get_delta_manager("sess_b")
        assert m1 is not m2
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_delta_context.py -v`
Expected: FAIL with `ModuleNotFoundError`

**Step 3: Write the implementation**

```python
# dashboard/backend/core/workbench/delta_context.py
"""Delta context tracking for Workbench Agent sessions.

Tracks state between turns and emits only material changes,
cutting dynamic context from ~1500 tokens to ~50-150 tokens.
"""

from __future__ import annotations

import threading
from typing import Any, Dict, List, Optional

# Module-level registry (keyed by session_id string)
_managers: Dict[str, "DeltaContextManager"] = {}
_managers_lock = threading.Lock()

# Thresholds
PRICE_MOVE_ATR_THRESHOLD = 0.3


def get_delta_manager(session_id: str) -> "DeltaContextManager":
    """Get or create a DeltaContextManager for a session."""
    sid = str(session_id)
    with _managers_lock:
        mgr = _managers.get(sid)
        if mgr is None:
            mgr = DeltaContextManager(sid)
            _managers[sid] = mgr
        return mgr


def reset_delta_manager(session_id: str) -> None:
    """Remove a session's delta manager (e.g. on session stop)."""
    with _managers_lock:
        _managers.pop(str(session_id), None)


class DeltaContextManager:
    """Tracks per-session state across turns, emits deltas."""

    def __init__(self, session_id: str) -> None:
        self.session_id = session_id
        self._last: Dict[str, Any] = {}
        self._turn_count: int = 0

    @property
    def turn_count(self) -> int:
        return self._turn_count

    def compute_delta(self, current: Dict[str, Any]) -> Dict[str, Any]:
        """Compare current context to last snapshot, return only changes."""
        ctx = current if isinstance(current, dict) else {}
        delta: Dict[str, Any] = {}
        is_first = not self._last

        # --- Price ---
        cur_price = ctx.get("last_price")
        old_price = self._last.get("last_price")
        atr = ctx.get("atr_14") or 1.0
        if cur_price is not None:
            if is_first:
                delta["price"] = cur_price
            elif old_price is not None and atr > 0:
                move = abs(float(cur_price) - float(old_price)) / float(atr)
                if move > PRICE_MOVE_ATR_THRESHOLD:
                    delta["price"] = cur_price
                    delta["price_move_atr"] = round(move, 2)

        # --- Balance ---
        cur_bal = ctx.get("balance")
        old_bal = self._last.get("balance")
        if cur_bal is not None and cur_bal != old_bal:
            delta["balance"] = cur_bal

        # --- Positions ---
        cur_positions = ctx.get("positions") if isinstance(ctx.get("positions"), list) else []
        old_positions = self._last.get("positions") if isinstance(self._last.get("positions"), list) else []
        cur_ids = {p.get("id") for p in cur_positions if isinstance(p, dict) and p.get("id") is not None}
        old_ids = {p.get("id") for p in old_positions if isinstance(p, dict) and p.get("id") is not None}

        opened_ids = cur_ids - old_ids
        closed_ids = old_ids - cur_ids
        if opened_ids:
            delta["positions_opened"] = [p for p in cur_positions if p.get("id") in opened_ids]
        if closed_ids:
            delta["positions_closed_ids"] = sorted(closed_ids)

        # --- Triggers ---
        cur_triggers = ctx.get("triggers") if isinstance(ctx.get("triggers"), list) else []
        old_triggers = self._last.get("triggers") if isinstance(self._last.get("triggers"), list) else []
        if len(cur_triggers) != len(old_triggers):
            delta["triggers_changed"] = True
            delta["trigger_count"] = len(cur_triggers)

        # Save snapshot and advance turn
        self._last = dict(ctx)
        self._turn_count += 1
        return delta
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_delta_context.py -v`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add dashboard/backend/core/workbench/delta_context.py tests/test_workbench_delta_context.py
git commit -m "feat: add delta context manager for per-session state tracking"
```

---

### Task 3: Conversation Compressor

**Files:**
- Create: `dashboard/backend/core/workbench/history_compressor.py`
- Test: `tests/test_workbench_history_compressor.py`

**Step 1: Write the failing tests**

```python
# tests/test_workbench_history_compressor.py
import pytest
from dashboard.backend.core.workbench.history_compressor import compress_history

class TestCompressHistory:
    def test_short_history_unchanged(self):
        history = [
            {"role": "user", "content": "hi"},
            {"role": "assistant", "content": "hello"},
        ]
        result = compress_history(history)
        assert result == history  # too short to compress

    def test_long_history_compressed(self):
        history = []
        for i in range(12):
            history.append({"role": "user", "content": f"question {i}"})
            history.append({"role": "assistant", "content": f"answer {i} with some detail about trading"})
        result = compress_history(history, keep_recent=2)
        # Should have: 1 summary + 2 recent messages
        assert len(result) == 3
        assert result[0]["role"] == "system"
        assert "[Session summary]" in result[0]["content"]
        # Last 2 should be preserved verbatim
        assert result[1] == history[-2]
        assert result[2] == history[-1]

    def test_preserves_recent_turns(self):
        history = [
            {"role": "user", "content": f"msg {i}"} for i in range(10)
        ]
        result = compress_history(history, keep_recent=3)
        # Last 3 messages should be untouched
        assert result[-3:] == history[-3:]

    def test_summary_captures_key_content(self):
        history = [
            {"role": "user", "content": "buy gold at 3050"},
            {"role": "assistant", "content": "placed trade BUY XAUUSD at 3050"},
            {"role": "user", "content": "what's my P&L"},
            {"role": "assistant", "content": "current P&L is +$150"},
            {"role": "user", "content": "close all positions"},
            {"role": "assistant", "content": "closed position #1 at +$150"},
            {"role": "user", "content": "show me the chart"},
            {"role": "assistant", "content": "here is the market snapshot"},
        ]
        result = compress_history(history, keep_recent=2)
        summary = result[0]["content"]
        # Should contain some trace of the trade and P&L discussion
        assert "trade" in summary.lower() or "buy" in summary.lower() or "3050" in summary

    def test_threshold_boundary(self):
        # Exactly 4 messages with keep_recent=2 → no compression (need >4)
        history = [{"role": "user", "content": f"msg {i}"} for i in range(4)]
        result = compress_history(history, keep_recent=2)
        assert len(result) == 4  # unchanged

    def test_five_messages_compresses(self):
        history = [{"role": "user", "content": f"msg {i}"} for i in range(5)]
        result = compress_history(history, keep_recent=2)
        assert len(result) == 3  # summary + 2 recent
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_history_compressor.py -v`
Expected: FAIL with `ModuleNotFoundError`

**Step 3: Write the implementation**

```python
# dashboard/backend/core/workbench/history_compressor.py
"""Extractive conversation compression for Workbench Agent.

Compresses old conversation turns into a summary string,
keeping the last N turns verbatim. No LLM needed — pure extraction.
"""

from __future__ import annotations

from typing import Dict, List

# Default settings
DEFAULT_KEEP_RECENT = 2
COMPRESSION_THRESHOLD = 4  # don't compress if <= this many messages
SUMMARY_MAX_POINTS = 6
SUMMARY_POINT_MAX_CHARS = 150


def compress_history(
    history: List[Dict[str, str]],
    keep_recent: int = DEFAULT_KEEP_RECENT,
) -> List[Dict[str, str]]:
    """Compress old history turns into a summary, keep last N raw.

    Returns a new list: [summary_message, ...recent_messages].
    If history is short enough, returns it unchanged.
    """
    if not isinstance(history, list):
        return []
    if len(history) <= COMPRESSION_THRESHOLD:
        return list(history)

    kr = max(1, int(keep_recent))
    old_turns = history[:-kr]
    recent = history[-kr:]

    key_points: List[str] = []
    for turn in old_turns:
        if not isinstance(turn, dict):
            continue
        role = str(turn.get("role") or "").strip().lower()
        content = str(turn.get("content") or "").strip()
        if not content:
            continue

        if role == "user":
            point = f"User: {content[:SUMMARY_POINT_MAX_CHARS]}"
            key_points.append(point)
        elif role == "assistant":
            # Extract the most informative part
            point = _extract_assistant_summary(content)
            if point:
                key_points.append(f"Agent: {point}")

    # Keep last N key points to stay within token budget
    trimmed = key_points[-SUMMARY_MAX_POINTS:]
    summary_text = " | ".join(trimmed) if trimmed else "No significant prior exchanges."

    summary_msg: Dict[str, str] = {
        "role": "system",
        "content": f"[Session summary] {summary_text}",
    }
    return [summary_msg] + list(recent)


def _extract_assistant_summary(content: str) -> str:
    """Extract the most informative snippet from an assistant message."""
    c = content.strip()
    if not c:
        return ""

    # If it looks like JSON, try to extract the reply field
    if c.startswith("{") and '"reply"' in c:
        import json
        try:
            obj = json.loads(c)
            if isinstance(obj, dict) and obj.get("reply"):
                return str(obj["reply"])[:SUMMARY_POINT_MAX_CHARS]
        except (json.JSONDecodeError, ValueError):
            pass

    # Otherwise take the first chunk
    return c[:SUMMARY_POINT_MAX_CHARS]
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_history_compressor.py -v`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add dashboard/backend/core/workbench/history_compressor.py tests/test_workbench_history_compressor.py
git commit -m "feat: add extractive conversation compressor for history trimming"
```

---

### Task 4: Circuit Breaker

**Files:**
- Create: `dashboard/backend/core/workbench/circuit_breaker.py`
- Test: `tests/test_workbench_circuit_breaker.py`

**Step 1: Write the failing tests**

```python
# tests/test_workbench_circuit_breaker.py
import time
import pytest
from dashboard.backend.core.workbench.circuit_breaker import ProviderCircuitBreaker

class TestCircuitBreaker:
    def test_starts_closed(self):
        cb = ProviderCircuitBreaker(failure_threshold=3, window_sec=60)
        assert cb.is_open("claude") is False

    def test_opens_after_threshold_failures(self):
        cb = ProviderCircuitBreaker(failure_threshold=3, window_sec=60)
        cb.record_failure("claude")
        cb.record_failure("claude")
        assert cb.is_open("claude") is False  # 2 < 3
        cb.record_failure("claude")
        assert cb.is_open("claude") is True   # 3 >= 3

    def test_different_providers_independent(self):
        cb = ProviderCircuitBreaker(failure_threshold=2, window_sec=60)
        cb.record_failure("claude")
        cb.record_failure("claude")
        assert cb.is_open("claude") is True
        assert cb.is_open("openai_compat") is False

    def test_fallback_for_claude(self):
        cb = ProviderCircuitBreaker(failure_threshold=2, window_sec=60)
        cb.record_failure("claude")
        cb.record_failure("claude")
        assert cb.get_fallback("claude") == "local_gptoss_http"

    def test_no_fallback_when_closed(self):
        cb = ProviderCircuitBreaker(failure_threshold=3, window_sec=60)
        cb.record_failure("claude")
        assert cb.get_fallback("claude") is None

    def test_record_success_resets(self):
        cb = ProviderCircuitBreaker(failure_threshold=2, window_sec=60)
        cb.record_failure("claude")
        cb.record_failure("claude")
        assert cb.is_open("claude") is True
        cb.record_success("claude")
        assert cb.is_open("claude") is False
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_circuit_breaker.py -v`
Expected: FAIL with `ModuleNotFoundError`

**Step 3: Write the implementation**

```python
# dashboard/backend/core/workbench/circuit_breaker.py
"""Provider circuit breaker for Workbench Agent.

Opens circuit after N failures within a time window,
routing to fallback provider until recovery.
"""

from __future__ import annotations

import time
import threading
from typing import Dict, List, Optional

# Fallback routing map
_FALLBACK_MAP: Dict[str, str] = {
    "claude": "local_gptoss_http",
    "openai_compat": "local_gptoss_http",
}


class ProviderCircuitBreaker:
    """Track failures per provider, open circuit when threshold exceeded."""

    def __init__(
        self,
        failure_threshold: int = 3,
        window_sec: float = 60.0,
    ) -> None:
        self.threshold = max(1, int(failure_threshold))
        self.window_sec = max(1.0, float(window_sec))
        self._failures: Dict[str, List[float]] = {}
        self._lock = threading.Lock()

    def record_failure(self, provider: str) -> None:
        with self._lock:
            now = time.monotonic()
            self._failures.setdefault(provider, []).append(now)
            self._prune(provider, now)

    def record_success(self, provider: str) -> None:
        with self._lock:
            self._failures.pop(provider, None)

    def is_open(self, provider: str) -> bool:
        """True if circuit is OPEN (provider is down)."""
        with self._lock:
            now = time.monotonic()
            self._prune(provider, now)
            recent = self._failures.get(provider, [])
            return len(recent) >= self.threshold

    def get_fallback(self, provider: str) -> Optional[str]:
        """Return fallback provider if circuit is open, else None."""
        if self.is_open(provider):
            return _FALLBACK_MAP.get(provider)
        return None

    def _prune(self, provider: str, now: float) -> None:
        """Remove failures outside the time window."""
        entries = self._failures.get(provider)
        if entries:
            cutoff = now - self.window_sec
            self._failures[provider] = [t for t in entries if t > cutoff]


# Module-level singleton
_circuit_breaker: Optional[ProviderCircuitBreaker] = None
_cb_lock = threading.Lock()


def get_circuit_breaker() -> ProviderCircuitBreaker:
    global _circuit_breaker
    with _cb_lock:
        if _circuit_breaker is None:
            _circuit_breaker = ProviderCircuitBreaker()
        return _circuit_breaker
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_circuit_breaker.py -v`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add dashboard/backend/core/workbench/circuit_breaker.py tests/test_workbench_circuit_breaker.py
git commit -m "feat: add provider circuit breaker with automatic fallback"
```

---

### Task 5: Refactor `_system_prompt_parts` for Layered Caching

This is the core integration task. Modifies `agent.py` to use the new components.

**Files:**
- Modify: `dashboard/backend/core/workbench/agent.py:1155-1227` (`_system_prompt_parts`)
- Modify: `dashboard/backend/core/workbench/agent.py:2300-2340` (`chat()`)
- Modify: `dashboard/backend/core/workbench/agent.py:564-582` (`_trim_history`)
- Test: `tests/test_workbench_smart_context.py`

**Step 1: Write the failing tests**

```python
# tests/test_workbench_smart_context.py
import pytest
from dashboard.backend.core.workbench.agent import WorkbenchAgent

class TestLayeredPromptBuilder:
    def setup_method(self):
        self.agent = WorkbenchAgent()
        self.base_context = {
            "session": {"id": 1, "symbol": "XAUUSD", "timeframe": "M15"},
            "bars": [],
            "identity": {"name": "TestAgent", "tone": "professional"},
            "session_stats": {"current_balance": 10000, "total_pnl": 150, "trades_count": 5},
            "open_positions": [],
            "recent_trades": [],
            "scheduled_triggers": [],
            "tool_state": {},
            "memory": {},
        }
        self.base_perms = {"can_chat": True, "can_place_trades": False}

    def test_intent_pruning_reduces_tool_count(self):
        """When allowed_tool_names is provided, system prompt should have fewer tools."""
        # Full tools
        static_full, _ = self.agent._system_prompt_parts(
            self.base_context, self.base_perms,
            include_tool_summaries=True,
            allowed_tool_names=None,
        )
        # Pruned tools (only market query)
        static_pruned, _ = self.agent._system_prompt_parts(
            self.base_context, self.base_perms,
            include_tool_summaries=True,
            allowed_tool_names=["get_market_snapshot", "get_indicator_values", "submit_proposed_actions"],
        )
        # Pruned should be shorter
        assert len(static_pruned) < len(static_full)

    def test_static_part_stable_across_turns(self):
        """Static part should not change when only dynamic context changes."""
        ctx1 = dict(self.base_context)
        ctx2 = dict(self.base_context)
        ctx2["session_stats"] = {"current_balance": 9500, "total_pnl": -500}
        static1, _ = self.agent._system_prompt_parts(
            ctx1, self.base_perms, allowed_tool_names=["get_market_snapshot"],
        )
        static2, _ = self.agent._system_prompt_parts(
            ctx2, self.base_perms, allowed_tool_names=["get_market_snapshot"],
        )
        # Identity and tools haven't changed, so static should be identical
        assert static1 == static2

    def test_delta_context_in_dynamic(self):
        """When delta_context is provided, dynamic part should use it instead of full context."""
        delta = {"price": 3050.0, "price_move_atr": 0.5}
        _, dynamic = self.agent._system_prompt_parts(
            self.base_context, self.base_perms,
            delta_context=delta,
        )
        assert "3050" in dynamic
        # Should NOT contain full session_stats in dynamic when delta is provided
        # (session_stats go into session layer, not dynamic)

    def test_chat_passes_intent_tools(self):
        """chat() should use intent classifier to set allowed_tool_names when not explicitly provided."""
        calls = []
        def fake_deterministic(**kwargs):
            calls.append(kwargs)
            return {"ok": True, "reply": "test"}
        agent = WorkbenchAgent()
        agent._chat_deterministic = lambda **kw: fake_deterministic(**kw)
        agent.chat(
            message="what's the price?",
            context=self.base_context,
            conversation_history=[],
            provider="deterministic",
            model_label=None,
            llm_url=None,
            api_key=None,
            timeout_sec=30,
            permissions=self.base_perms,
            tool_executor=lambda n, a: {"ok": True},
            allow_tools=True,
            max_tool_steps=4,
        )
        # Intent classifier should have been invoked
        # (we just verify the call went through without error)
        assert len(calls) == 1

class TestHistoryCompression:
    def test_trim_history_with_compression(self):
        history = []
        for i in range(20):
            history.append({"role": "user", "content": f"question {i}"})
            history.append({"role": "assistant", "content": f"answer {i}"})
        result = WorkbenchAgent._trim_history(history, max_messages=12)
        # Should be compressed: summary + recent turns
        assert len(result) <= 12
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_smart_context.py -v`
Expected: FAIL (delta_context parameter doesn't exist yet, intent classifier not integrated)

**Step 3: Modify `_system_prompt_parts` in agent.py**

In `dashboard/backend/core/workbench/agent.py`, add import at top (after line 23):

```python
from dashboard.backend.core.workbench.intent_classifier import get_tools_for_intent
from dashboard.backend.core.workbench.history_compressor import compress_history
```

Then refactor `_system_prompt_parts` (lines 1155-1227) to accept `delta_context` and use a 3-layer structure:

```python
def _system_prompt_parts(
    self,
    context: Dict[str, Any],
    permissions: Dict[str, Any],
    objective: str = "",
    allowed_tool_names: Optional[List[str]] = None,
    include_tool_summaries: bool = True,
    on_demand_mode: bool = False,
    delta_context: Optional[Dict[str, Any]] = None,
) -> Tuple[str, str]:
    ctx = context if isinstance(context, dict) else {}
    identity = ctx.get("identity") if isinstance(ctx.get("identity"), dict) else {}

    # --- Layer 0 + 1: Static (cacheable) ---
    # Build tool section from filtered specs
    tools_section = ""
    if include_tool_summaries:
        tool_lines = []
        for spec in self._tool_specs_filtered(allowed_tool_names):
            if not isinstance(spec, dict):
                continue
            name = str(spec.get("name") or "").strip()
            params = spec.get("parameters") if isinstance(spec.get("parameters"), dict) else {}
            props = params.get("properties") if isinstance(params.get("properties"), dict) else {}
            keys = ", ".join(sorted(list(props.keys()))[: (4 if on_demand_mode else 8)])
            if on_demand_mode:
                tool_lines.append(f"- {name} args: {{{keys}}}")
            else:
                desc = str(spec.get("description") or "").strip()
                tool_lines.append(f"- {name}: {desc}. args: {{{keys}}}")
        if tool_lines:
            tools_section = "Available tools:\n" + "\n".join(tool_lines) + "\n\n"

    # Layer 2: Session config (cacheable — changes only on session switch)
    identity_json = json.dumps(identity, ensure_ascii=True)
    session_info = ctx.get("session") if isinstance(ctx.get("session"), dict) else {}
    session_layer = (
        f"Locked Identity JSON: {identity_json}\n"
        f"Session: symbol={session_info.get('symbol', '?')}, "
        f"timeframe={session_info.get('timeframe', '?')}\n\n"
    )

    if on_demand_mode:
        static_part = (
            "You are Workbench Agent running in compact local mode.\n"
            "Assume context is intentionally minimal. Fetch details on demand using tools.\n"
            "For market data, call get_market_snapshot/get_indicator_values.\n"
            "For positions, call get_positions_detail. For triggers, call get_scheduled_triggers.\n"
            "Respect permissions strictly. Never fabricate executions or prices.\n"
            "Return JSON: {reply, tool_calls?, proposed_actions?, memory_notes?}.\n\n"
            f"{session_layer}"
            f"{tools_section}"
        )
    else:
        static_part = (
            "You are Workbench Agent, a trading co-pilot for paper simulation.\n"
            "Use tools when needed. Do not fabricate prices or tool outputs.\n"
            "Respect permissions strictly; never bypass blocked actions.\n"
            "Trade actions must include risk terms (stop_loss, take_profit when available).\n"
            "When user requests waiting for a trigger, use schedule_trade_entry.\n"
            "For multi-step trigger logic, use schedule_trade_entry with precondition.\n"
            "For explicit execution requests, call place_trade/close_trade when possible.\n"
            "Use memory hits as trader preferences; prefer them unless they conflict with policy.\n"
            "Context JSON is compact. For full details, call get_market_snapshot, get_positions_detail, get_indicator_values, or get_scheduled_triggers.\n"
            "Identity profile is locked. Only strategy/process knowledge may adapt.\n"
            "Return final response as JSON:\n"
            '{"reply":"...","tool_calls":[{"name":"...","args":{}}],"proposed_actions":[{"action_type":"...","summary":"...","payload":{},"confidence":0.0}],"memory_notes":[{"content":"...","memory_type":"trader_rule","scope":"GLOBAL","importance":0.8}]}\n'
            "tool_calls/proposed_actions/memory_notes are optional. Keep reply concise.\n\n"
            f"{session_layer}"
            f"{tools_section}"
        )

    # --- Layer 3: Dynamic (never cached) ---
    # Use delta_context if provided, otherwise build full compact context
    if delta_context is not None:
        ctx_json = json.dumps(delta_context, ensure_ascii=True)
    elif on_demand_mode:
        compact_ctx = self._build_prompt_context_on_demand(ctx)
        ctx_json = json.dumps(compact_ctx, ensure_ascii=True)
    else:
        compact_ctx = self._build_prompt_context(ctx)
        ctx_json = json.dumps(compact_ctx, ensure_ascii=True)

    perm_json = json.dumps(permissions or {}, ensure_ascii=True)
    dynamic_part = (
        f"Objective: {objective}\n"
        f"Permissions JSON: {perm_json}\n"
        f"Context JSON: {ctx_json}\n"
    )
    return static_part, dynamic_part
```

**Step 4: Modify `chat()` method to integrate intent classifier and history compressor**

In `chat()` (lines 2300-2427), add intent classification before system prompt building:

```python
# After line 2329 (perms = ...), before line 2330:
# --- Intent-based tool pruning ---
if allowed_tool_names is None and allow_tools:
    # Auto-detect relevant tools from message
    allowed_tool_names = get_tools_for_intent(msg)

# After line 2327 (history = self._trim_history(...)):
# Replace with:
history = self._trim_history(conversation_history)
if len(history) > 4:
    history = compress_history(history, keep_recent=2)
```

**Step 5: Run tests to verify they pass**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_smart_context.py -v`
Expected: ALL PASS

**Step 6: Run existing agent tests to verify no regressions**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_agent_phase4_critical.py tests/test_workbench_agent_memory_phase2.py -v`
Expected: ALL PASS (existing behavior preserved)

**Step 7: Commit**

```bash
git add dashboard/backend/core/workbench/agent.py tests/test_workbench_smart_context.py
git commit -m "feat: integrate intent classifier + history compressor into agent pipeline"
```

---

### Task 6: Integrate Delta Context into simulation_routes.py

**Files:**
- Modify: `dashboard/backend/api/simulation_routes.py:7595-7726` (agent/chat endpoint)
- Test: `tests/test_workbench_smart_context.py` (add integration test)

**Step 1: Write the failing test**

Add to `tests/test_workbench_smart_context.py`:

```python
class TestDeltaContextIntegration:
    def test_delta_manager_used_in_agent_context(self):
        """Verify delta context is computed from market summary and passed to agent."""
        from dashboard.backend.core.workbench.delta_context import DeltaContextManager

        mgr = DeltaContextManager("integration_test")
        ctx = {
            "last_price": 3050.0,
            "atr_14": 20.0,
            "balance": 10000.0,
            "positions": [],
            "triggers": [],
        }
        # First turn: full
        delta1 = mgr.compute_delta(ctx)
        assert "price" in delta1

        # Second turn: no change
        delta2 = mgr.compute_delta(ctx)
        assert "price" not in delta2  # no material change
```

**Step 2: Modify simulation_routes.py**

At the top of `simulation_routes.py`, add import:

```python
from dashboard.backend.core.workbench.delta_context import get_delta_manager
from dashboard.backend.core.workbench.circuit_breaker import get_circuit_breaker
```

In the `/agent/chat` endpoint handler, after `merged_ctx` is built (around line 7615) and before `agent.chat()` is called (around line 7712), add delta context computation:

```python
# After merged_ctx is built, compute delta for the session
delta_mgr = get_delta_manager(str(session_id))
market_summary = merged_ctx.get("market_summary") or {}
stats = merged_ctx.get("session_stats") if isinstance(merged_ctx.get("session_stats"), dict) else {}
delta_input = {
    "last_price": market_summary.get("current_price"),
    "atr_14": market_summary.get("range20"),  # approximate ATR from range
    "balance": stats.get("current_balance"),
    "positions": merged_ctx.get("open_positions", []),
    "triggers": merged_ctx.get("scheduled_triggers", []),
}
delta_ctx = delta_mgr.compute_delta(delta_input)
```

Then pass `delta_ctx` into agent context so it's available. The simplest approach: add it to `merged_ctx` under a special key that `_system_prompt_parts` can read:

```python
merged_ctx["_delta_context"] = delta_ctx
```

In `agent.py` `chat()` method, extract and pass to `_system_prompt_parts`:

```python
delta_context = safe_context.pop("_delta_context", None)
# Pass to _system_prompt_parts:
system_prompt_static, system_prompt_dynamic = self._system_prompt_parts(
    safe_context, perms,
    objective=objective,
    allowed_tool_names=allowed_tool_names,
    include_tool_summaries=include_tool_summaries,
    on_demand_mode=local_on_demand_mode,
    delta_context=delta_context,
)
```

**Step 3: Add circuit breaker integration**

In the same endpoint handler, before provider dispatch:

```python
# Circuit breaker check
cb = get_circuit_breaker()
fallback = cb.get_fallback(provider_name)
if fallback:
    logger.warning("circuit_breaker: %s is open, falling back to %s", provider_name, fallback)
    provider_name = fallback
```

After `agent.chat()` returns:

```python
if out.get("ok"):
    cb.record_success(provider_name)
else:
    error_str = str(out.get("error") or "")
    if any(code in error_str for code in ["429", "500", "502", "503", "ReadTimeout"]):
        cb.record_failure(provider_name)
```

**Step 4: Run all tests**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_smart_context.py tests/test_workbench_delta_context.py tests/test_workbench_circuit_breaker.py tests/test_workbench_agent_phase4_critical.py -v`
Expected: ALL PASS

**Step 5: Syntax check**

Run: `python -c "import ast, pathlib; ast.parse(pathlib.Path('dashboard/backend/api/simulation_routes.py').read_text(encoding='utf-8')); ast.parse(pathlib.Path('dashboard/backend/core/workbench/agent.py').read_text(encoding='utf-8')); print('OK')"`
Expected: `OK`

**Step 6: Commit**

```bash
git add dashboard/backend/api/simulation_routes.py dashboard/backend/core/workbench/agent.py tests/test_workbench_smart_context.py
git commit -m "feat: integrate delta context + circuit breaker into agent chat endpoint"
```

---

### Task 7: Expand Deterministic Fast Path

**Files:**
- Modify: `dashboard/backend/core/workbench/agent.py:1337-1700` (`_heuristic_tool_plan`)
- Test: `tests/test_workbench_smart_context.py` (add fast-path tests)

**Step 1: Write the failing tests**

Add to `tests/test_workbench_smart_context.py`:

```python
class TestExpandedDeterministicFastPath:
    def setup_method(self):
        self.agent = WorkbenchAgent()
        self.ctx = {
            "session": {"id": 1, "symbol": "XAUUSD", "timeframe": "M15"},
            "bars": [],
            "session_stats": {"current_balance": 10000, "total_pnl": 150,
                             "trades_count": 5, "wins": 3, "losses": 2},
            "open_positions": [{"id": 1, "direction": "BUY", "entry_price": 3040}],
            "scheduled_triggers": [{"id": 10, "status": "pending", "condition": "price > 3050"}],
            "tool_state": {},
        }
        self.perms = {"can_chat": True}

    def test_trade_count_query(self):
        plan = self.agent._heuristic_tool_plan("how many trades today?", self.ctx, self.perms)
        # Should generate a plan that answers from session_stats
        assert any(p.get("name") == "get_positions_detail" for p in plan)

    def test_win_rate_query(self):
        plan = self.agent._heuristic_tool_plan("what's my win rate?", self.ctx, self.perms)
        assert any(p.get("name") == "get_positions_detail" for p in plan)

    def test_trigger_status_query(self):
        plan = self.agent._heuristic_tool_plan("show pending triggers", self.ctx, self.perms)
        assert any(p.get("name") == "get_scheduled_triggers" for p in plan)

    def test_risk_query(self):
        plan = self.agent._heuristic_tool_plan("what's my current risk?", self.ctx, self.perms)
        assert any(p.get("name") in ("get_positions_detail", "get_market_snapshot") for p in plan)
```

**Step 2: Run tests to verify they fail**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_smart_context.py::TestExpandedDeterministicFastPath -v`
Expected: Some FAIL (new keyword patterns not yet handled)

**Step 3: Add new keyword matches to `_heuristic_tool_plan`**

In `agent.py`, within `_heuristic_tool_plan` (after the existing keyword blocks, around line 1365), add:

```python
# Trade count / win rate / performance queries
if _contains_any(msg, ["how many trades", "trade count", "trades today", "win rate",
                        "win ratio", "performance", "stats"]):
    plan.append({
        "name": "get_positions_detail",
        "args": {"include_closed": True},
    })

# Trigger status queries
if _contains_any(msg, ["show triggers", "pending triggers", "trigger status",
                        "conditional entries", "scheduled entries", "any triggers"]):
    plan.append({
        "name": "get_scheduled_triggers",
        "args": {},
    })

# Risk exposure queries
if _contains_any(msg, ["risk", "exposure", "how much am i risking",
                        "risk level", "current risk"]):
    if not any(p.get("name") == "get_positions_detail" for p in plan):
        plan.append({"name": "get_positions_detail", "args": {}})
    if not any(p.get("name") == "get_market_snapshot" for p in plan):
        plan.append({"name": "get_market_snapshot", "args": {"bars_limit": 10}})

# Summary / status queries
if _contains_any(msg, ["summary", "status", "overview", "dashboard", "what's going on"]):
    if not any(p.get("name") == "get_market_snapshot" for p in plan):
        plan.append({"name": "get_market_snapshot", "args": {"bars_limit": 20}})
    if not any(p.get("name") == "get_positions_detail" for p in plan):
        plan.append({"name": "get_positions_detail", "args": {}})
    if not any(p.get("name") == "get_scheduled_triggers" for p in plan):
        plan.append({"name": "get_scheduled_triggers", "args": {}})
```

**Step 4: Run tests to verify they pass**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_smart_context.py::TestExpandedDeterministicFastPath -v`
Expected: ALL PASS

**Step 5: Run full test suite**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_agent_phase4_critical.py tests/test_workbench_smart_context.py tests/test_workbench_intent_classifier.py tests/test_workbench_delta_context.py tests/test_workbench_circuit_breaker.py tests/test_workbench_history_compressor.py -v`
Expected: ALL PASS

**Step 6: Commit**

```bash
git add dashboard/backend/core/workbench/agent.py tests/test_workbench_smart_context.py
git commit -m "feat: expand deterministic fast path for zero-LLM query handling"
```

---

### Task 8: Final Integration Test + Manual Verification

**Files:**
- Test: `tests/test_workbench_smart_context.py` (add end-to-end integration test)

**Step 1: Write end-to-end integration test**

Add to `tests/test_workbench_smart_context.py`:

```python
class TestEndToEndSmartContext:
    """Verify the full pipeline works together."""

    def test_full_chat_flow_deterministic(self):
        """Verify chat() with all new components active, deterministic provider."""
        agent = WorkbenchAgent()
        ctx = {
            "session": {"id": 1, "symbol": "XAUUSD", "timeframe": "M15"},
            "bars": [],
            "identity": {"name": "TestBot"},
            "session_stats": {"current_balance": 10000},
            "open_positions": [],
            "recent_trades": [],
            "scheduled_triggers": [],
            "tool_state": {},
        }
        result = agent.chat(
            message="what's the current price?",
            context=ctx,
            conversation_history=[],
            provider="deterministic",
            model_label=None,
            llm_url=None,
            api_key=None,
            timeout_sec=30,
            permissions={"can_chat": True},
            tool_executor=lambda n, a: {"ok": True, "data": "mock"},
            allow_tools=True,
            max_tool_steps=4,
        )
        assert result.get("ok") is True

    def test_token_reduction_estimate(self):
        """Verify pruned tool specs are significantly smaller than full specs."""
        full_specs = WorkbenchAgent._tool_specs()
        from dashboard.backend.core.workbench.intent_classifier import get_tools_for_intent
        pruned_names = get_tools_for_intent("what's the price?")
        pruned_specs = WorkbenchAgent._tool_specs_filtered(pruned_names)
        # Pruned should have significantly fewer tools
        assert len(pruned_specs) < len(full_specs)
        assert len(pruned_specs) <= 5  # market_query gives ~3 tools + submit

    def test_history_compression_reduces_tokens(self):
        """Verify compressed history is shorter than raw."""
        import json
        long_history = []
        for i in range(20):
            long_history.append({"role": "user", "content": f"question {i} " * 20})
            long_history.append({"role": "assistant", "content": f"answer {i} " * 20})
        raw_tokens = len(json.dumps(long_history))
        compressed = compress_history(long_history, keep_recent=2)
        compressed_tokens = len(json.dumps(compressed))
        # Compressed should be at least 50% smaller
        assert compressed_tokens < raw_tokens * 0.5
```

**Step 2: Run the complete test suite**

Run: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m pytest tests/test_workbench_smart_context.py tests/test_workbench_intent_classifier.py tests/test_workbench_delta_context.py tests/test_workbench_circuit_breaker.py tests/test_workbench_history_compressor.py tests/test_workbench_agent_phase4_critical.py tests/test_workbench_agent_memory_phase2.py -v`
Expected: ALL PASS

**Step 3: Syntax check all modified files**

Run: `python -c "import ast, pathlib; [ast.parse(pathlib.Path(f).read_text(encoding='utf-8')) for f in ['dashboard/backend/core/workbench/agent.py', 'dashboard/backend/api/simulation_routes.py', 'dashboard/backend/core/workbench/intent_classifier.py', 'dashboard/backend/core/workbench/delta_context.py', 'dashboard/backend/core/workbench/history_compressor.py', 'dashboard/backend/core/workbench/circuit_breaker.py']]; print('ALL OK')"`
Expected: `ALL OK`

**Step 4: Manual verification**

1. Start backend: `cd C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem && python -m uvicorn dashboard.backend.main:app --reload --port 8000`
2. Open frontend at `http://localhost:5000`
3. Open a Workbench session, select Claude provider
4. Send "what's the price?" — verify response works and check backend logs for token usage
5. Send "buy 0.1 lots with SL at 2900" — verify trade tools are included
6. Send 10+ messages — verify history compression kicks in (backend logs)
7. Compare token usage in the usage meter vs before the changes

**Step 5: Commit**

```bash
git add tests/test_workbench_smart_context.py
git commit -m "test: add end-to-end integration tests for smart context pipeline"
```

---

## New Files Created

| File | Purpose |
|---|---|
| `dashboard/backend/core/workbench/intent_classifier.py` | Intent detection + tool pruning |
| `dashboard/backend/core/workbench/delta_context.py` | Per-session state delta tracking |
| `dashboard/backend/core/workbench/history_compressor.py` | Extractive conversation compression |
| `dashboard/backend/core/workbench/circuit_breaker.py` | Provider failover with circuit breaker |
| `tests/test_workbench_intent_classifier.py` | Tests for intent classifier |
| `tests/test_workbench_delta_context.py` | Tests for delta context manager |
| `tests/test_workbench_history_compressor.py` | Tests for history compressor |
| `tests/test_workbench_circuit_breaker.py` | Tests for circuit breaker |
| `tests/test_workbench_smart_context.py` | Integration tests for full pipeline |

## Modified Files

| File | Lines Changed | What Changed |
|---|---|---|
| `dashboard/backend/core/workbench/agent.py` | ~1155-1227, ~2300-2340, ~1365-1420 | Layered prompt builder, intent integration in chat(), expanded deterministic fast path |
| `dashboard/backend/api/simulation_routes.py` | ~7610-7720 | Delta context computation, circuit breaker integration |

## Expected Token Savings

| Component | Tokens Saved Per Turn |
|---|---|
| Intent-based tool pruning (16→4 tools) | ~600-800 |
| Delta context (full→changed-only) | ~800-1200 |
| History compression (20 msgs→summary+2) | ~1000-2000 |
| Layered caching (session in static) | ~200 (via 1/10 cost) |
| Deterministic fast path (no LLM) | ~6600 (full avoidance) |
| **Total per-turn (LLM path)** | **~2,600-4,200** |
| **% of turns avoiding LLM** | **~30-40%** |
