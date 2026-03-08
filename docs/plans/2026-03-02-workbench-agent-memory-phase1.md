# 2026-03-02 Workbench Agent Memory - Phase 1

## Goal

Provide durable, retrieval-augmented memory for the unified Workbench Agent so it can keep trader-specific rules/preferences across sessions.

## What Phase 1 Implements

1. Persistent memory store in DB:
   - Table: `workbench_agent_memories`
   - Model: `WorkbenchAgentMemoryModel`
2. Retrieval in agent context:
   - `agent/chat` and `agent/run-once` now enrich context with relevant memory hits.
3. Write path:
   - Explicit teaching-style user messages are captured as durable memory notes.
   - Tool-call support: `search_memory` and `save_memory_note`.
4. API surface:
   - `GET /api/v1/simulation/sessions/{id}/agent/memory`
   - `POST /api/v1/simulation/sessions/{id}/agent/memory`
   - `DELETE /api/v1/simulation/sessions/{id}/agent/memory/{memory_id}`
5. Frontend proxy support:
   - Matching Flask proxy routes under `/api/simulation/...`.

## Retrieval Design

Ranking uses lightweight lexical scoring (no external embedding dependency in Phase 1):

1. Token overlap between query and memory content.
2. Importance score (`0.0..1.0`).
3. Recency decay.
4. Scope boosts:
   - SESSION memory for current session.
   - SYMBOL memory for current symbol.
   - GLOBAL memory fallback.
5. Optional timeframe match boost.

Top hits are attached under context key: `memory.hits`.

## Storage Scopes

1. `GLOBAL`: user doctrine/preferences across all sessions.
2. `SESSION`: local notes for one replay/live session.
3. `SYMBOL`: reusable notes for the same instrument across sessions.

## Safety and Limits

1. Memory rows are deduplicated by fingerprint.
2. Per-scope retention cap is enforced (`_AGENT_MEMORY_MAX_PER_SCOPE`).
3. Content is normalized and bounded.

## Next Phases

1. Phase 2: structured memory extraction (summary/intent classifier).
2. Phase 3: memory pinning/editing in UI and explicit “remember this” UX.
3. Phase 4: optional embeddings/vector index for semantic retrieval quality.
4. Phase 5: memory policy controls (confidence thresholds, TTL per type).
