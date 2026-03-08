# 2026-03-02 Workbench Agent Memory - Phase 2

## Scope

Phase 2 adds structured memory extraction and explicit user control paths.

## Implemented

1. Model-output memory extraction
   - Agent now accepts optional `memory_notes` in model JSON output.
   - Notes are normalized (`content`, `memory_type`, `scope`, `importance`, optional symbol/timeframe).
   - Valid notes are persisted during `agent/chat` and `agent/run-once`.

2. Explicit memory commands in chat UX
   - `/remember global: <text>` (also supports `session` / `symbol` scopes)
   - `/memory <query>` to fetch relevant stored notes
   - Implemented in `workbench.js` with backend memory APIs.

3. Prompt contract update
   - System prompt now documents `memory_notes` output schema and behavior.

## Result

The agent can now:

1. Learn explicit lessons you teach.
2. Persist selected model-derived lessons.
3. Retrieve prior lessons during future turns and sessions.
