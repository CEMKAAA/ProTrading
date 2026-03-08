# Smart Context Pipeline - Design Document

**Date:** 2026-03-04
**Status:** Approved
**Goal:** Cut agent input tokens by ~80% while maintaining Claude-quality output via intelligent context management.

## Context

The Workbench Agent currently sends ~6,600 tokens per turn to Claude (system prompt + full context + all 16 tool schemas + unbounded history). Codex added an `on_demand_mode` for local GPT-OSS that reduces context to counts-only, but this is a provider-specific patch. The Smart Context Pipeline is a universal architectural improvement that benefits ALL providers.

### Current Token Flow (per turn, estimated)

| Component | Tokens | Cached? |
|---|---|---|
| System prompt (static_part) | ~1,800 | Partially (Claude only) |
| System prompt (dynamic_part) | ~1,500 | No |
| Conversation history | ~2,000+ | No |
| User message | ~100 | No |
| Tool schemas (Claude native) | ~1,200 | No |
| **Total** | **~6,600** | |

### Target Token Flow

| Component | Tokens | Cached? |
|---|---|---|
| Cache Layer 0: Role + rules + JSON schema | ~400 | Yes (1/10 cost) |
| Cache Layer 1: Pruned tool schemas (3-5 tools) | ~300 | Yes (1/10 cost) |
| Cache Layer 2: Session config + identity | ~200 | Yes (1/10 cost) |
| Dynamic: Market delta + permissions | ~300 | No |
| Compressed history (summary + 2 recent) | ~800 | No |
| User message | ~100 | No |
| **Total** | **~2,100** | |
| **Effective cost** | **~1,310** | (cached at 1/10) |

## Architecture

### Component 1: Layered Prompt Builder

Replace the current `_system_prompt_parts()` which returns `(static_part, dynamic_part)` with a 4-layer builder.

**Layer 0 - Static (cached, never changes):**
- Role definition (compact)
- Behavior rules (permissions, no fabrication, risk terms)
- Output JSON schema example
- ~400 tokens

**Layer 1 - Tools (cached, changes per intent):**
- Tool schemas filtered by intent classification
- Only 3-5 tools per turn, not all 16
- Uses `classify_intent()` to select relevant tools
- ~200-400 tokens (down from ~1,200)

**Layer 2 - Session (cached, changes on session switch):**
- Symbol, timeframe, strategy name
- Risk parameters (risk_percent, max_daily_loss)
- Identity profile JSON
- ~200 tokens

**Layer 3 - Dynamic (never cached, minimal):**
- Delta context (only what changed since last turn)
- Current permissions JSON
- Objective string
- ~200-400 tokens

For Claude: Layers 0-2 are sent with `cache_control: {"type": "ephemeral"}` as a single cached prefix. Layer 3 is appended after.

For OpenAI: All layers concatenated (no caching benefit, but still smaller due to pruning).

For Local GPT-OSS: Uses existing `on_demand_mode` from Codex, but benefits from tool pruning and delta context.

### Component 2: DeltaContextManager

Server-side singleton per session that tracks state across turns.

```python
class DeltaContextManager:
    def __init__(self, session_id: str):
        self.session_id = session_id
        self._last_snapshot: Dict[str, Any] = {}
        self._turn_count: int = 0

    def compute_delta(self, current_context: Dict[str, Any]) -> Dict[str, Any]:
        """Return only material changes since last turn."""
        delta = {}

        # Price: only if moved > 0.3 ATR
        cur_price = current_context.get("last_price")
        old_price = self._last_snapshot.get("last_price")
        atr = current_context.get("atr_14", 1.0)
        if cur_price and old_price and atr:
            move = abs(cur_price - old_price) / atr
            if move > 0.3:
                delta["price"] = cur_price
                delta["price_move_atr"] = round(move, 2)

        # Positions: only report opens/closes
        old_ids = {p["id"] for p in self._last_snapshot.get("positions", [])}
        new_ids = {p["id"] for p in current_context.get("positions", [])}
        if old_ids != new_ids:
            delta["positions_opened"] = [p for p in current_context["positions"] if p["id"] not in old_ids]
            delta["positions_closed_ids"] = list(old_ids - new_ids)

        # Balance: only if changed
        old_bal = self._last_snapshot.get("balance")
        new_bal = current_context.get("balance")
        if old_bal != new_bal:
            delta["balance"] = new_bal

        # Triggers: only if count changed
        old_trig = len(self._last_snapshot.get("triggers", []))
        new_trig = len(current_context.get("triggers", []))
        if old_trig != new_trig:
            delta["triggers_changed"] = True
            delta["trigger_count"] = new_trig

        self._last_snapshot = current_context
        self._turn_count += 1
        return delta
```

Stored in a dict keyed by session_id within the `WorkbenchAgent` instance (or a module-level registry).

### Component 3: Intent Classifier + Tool Pruner

Regex/keyword-based intent detection that maps user messages to relevant tool subsets.

```python
TOOL_INTENT_MAP = {
    "market_query":   ["get_market_snapshot", "get_indicator_values"],
    "position_query": ["get_positions_detail", "close_trade"],
    "trade_action":   ["place_trade", "schedule_trade_entry", "cancel_scheduled_entry", "get_market_snapshot"],
    "analysis":       ["scan_tool", "scan_draw_fvg_range", "get_market_snapshot", "get_indicator_values"],
    "research":       ["run_research_optimize", "run_ml_diagnostic"],
    "memory":         ["search_memory", "save_memory_note"],
    "trigger_query":  ["get_scheduled_triggers", "cancel_scheduled_entry"],
    "visibility":     ["set_indicator_visibility", "set_market_context"],
}
ALWAYS_INCLUDE = ["submit_proposed_actions"]

INTENT_PATTERNS = {
    "market_query":   r"price|market|chart|candle|bar|level|support|resistance|vwap|ema|rsi|atr",
    "position_query": r"position|trade|pnl|profit|loss|balance|open\s+trade|close",
    "trade_action":   r"\b(buy|sell|long|short|enter|entry|place|execute)\b",
    "analysis":       r"scan|fvg|fair.value|setup|pattern|signal|analyz|analys",
    "research":       r"optimi|research|backtest|ml\b|diagnos",
    "memory":         r"remember|memory|recall|forget|note",
    "trigger_query":  r"trigger|schedule|pending|condition|wait\s+for",
    "visibility":     r"show|hide|indicator|overlay|switch|symbol|timeframe",
}

def classify_intent(message: str) -> Set[str]:
    intents = set()
    lower = message.lower()
    for intent, pattern in INTENT_PATTERNS.items():
        if re.search(pattern, lower):
            intents.add(intent)
    if not intents:
        intents = {"market_query", "position_query"}  # safe default
    return intents

def get_tools_for_intent(message: str) -> List[str]:
    intents = classify_intent(message)
    tools = set(ALWAYS_INCLUDE)
    for intent in intents:
        tools.update(TOOL_INTENT_MAP.get(intent, []))
    return sorted(tools)
```

This integrates into `chat()` before system prompt construction. The `allowed_tool_names` parameter already exists and flows through to Claude's native tool schemas AND to the inline tools_section.

### Component 4: Conversation Compressor

After every 8 turns, compress old history into a summary.

```python
COMPRESSION_INTERVAL = 8  # turns before compression
KEEP_RECENT = 2           # raw turns to keep

def maybe_compress_history(self, history: list) -> list:
    if len(history) <= KEEP_RECENT + 2:
        return history

    # Check if we have a previous summary
    has_summary = (history and history[0].get("role") == "system"
                   and "[Session summary]" in str(history[0].get("content", "")))

    old_turns = history[:-KEEP_RECENT]
    recent = history[-KEEP_RECENT:]

    # Build summary from old turns (server-side, no LLM needed for basic extraction)
    key_points = []
    for turn in old_turns:
        content = str(turn.get("content", ""))
        role = turn.get("role", "")
        if role == "assistant" and ("proposed_actions" in content or "trade" in content.lower()):
            key_points.append(content[:200])
        elif role == "user" and len(content) > 50:
            key_points.append(f"User asked: {content[:100]}")

    summary_text = " | ".join(key_points[-6:])  # keep last 6 key points
    summary_msg = {"role": "system", "content": f"[Session summary: {summary_text}]"}

    return [summary_msg] + recent
```

For a more sophisticated version, we can use a cheap LLM call (Haiku) to generate the summary, but the extractive approach above costs zero tokens and works well enough.

### Component 5: Expanded Deterministic Fast Path

Extend `_heuristic_tool_plan` to handle more query types without any LLM call:

**Currently handled (~8 types):** price, positions, indicators, FVG scan, research, ML diagnostic, visibility, market context switch.

**New additions:**
- "how many trades today?" → `session_stats.trades_count`
- "what's my win rate?" → compute from `session_stats`
- "show triggers" / "any pending entries?" → `get_scheduled_triggers`
- "what's my risk?" → compute from `open_positions` + `risk_params`
- "summary" / "status" → aggregate from all cached state

**Goal:** 30-40% of all turns answered at $0 cost.

### Component 6: Claude API Circuit Breaker + Local Fallback

```python
class ProviderCircuitBreaker:
    def __init__(self, failure_threshold=3, recovery_sec=300):
        self._failures: Dict[str, List[float]] = {}
        self.threshold = failure_threshold
        self.recovery_sec = recovery_sec

    def record_failure(self, provider: str):
        now = time.time()
        self._failures.setdefault(provider, []).append(now)
        # Trim old failures
        self._failures[provider] = [t for t in self._failures[provider] if now - t < 60]

    def is_open(self, provider: str) -> bool:
        """True = circuit is OPEN (provider is down, use fallback)."""
        now = time.time()
        recent = [t for t in self._failures.get(provider, []) if now - t < 60]
        return len(recent) >= self.threshold

    def get_fallback(self, provider: str) -> Optional[str]:
        if self.is_open(provider):
            if provider == "claude":
                return "local_gptoss_http"
        return None
```

Integrated into `chat()`: if `circuit_breaker.is_open("claude")`, automatically route to local with on_demand_mode.

## File Changes

| File | Change |
|---|---|
| `agent.py` | New: `DeltaContextManager`, `classify_intent()`, `get_tools_for_intent()`, `maybe_compress_history()`, `ProviderCircuitBreaker`. Modify: `_system_prompt_parts()` → 4-layer builder, `chat()` → intent classification + delta context + circuit breaker |
| `simulation_routes.py` | New: `_delta_managers` dict per session, pass delta to agent. Minor route changes |
| No frontend changes needed | Pipeline is transparent to UI |

## Constraints

- All changes are additive to existing code paths
- Claude prompt caching is already partially implemented (static/dynamic split exists)
- Codex's local on_demand_mode, timeout/retry, and SSRF bypass remain unchanged
- No new dependencies required
- Deterministic provider path unchanged

## Success Metrics

| Metric | Current | Target |
|---|---|---|
| Input tokens per turn (Claude) | ~6,600 | ~2,100 (~1,310 effective) |
| % turns needing LLM | ~95% | ~60-70% |
| Latency per turn (Claude) | ~2-3s | ~1-2s (smaller input) |
| Monthly cost (2-3 sessions, active use) | ~$30-50 | ~$8-15 |
| Quality (trade decision accuracy) | Baseline | No degradation |
