# 2026-02-28 Workbench Unified Agent - Phase 1 Contract

## Objective

Unify Workbench AI surfaces (`coach`, `consultant`, `copilot`) into one user-facing `Agent` while preserving existing behavior and audit trails.

Phase 1 delivers the contracts and safety model only. No destructive removal of old routes/modules in this phase.

## Scope (Phase 1)

1. Define unified Agent API and payload schemas.
2. Define permission model for tool use and trade execution.
3. Define action/audit event schema.
4. Define provider profiles and runtime secret handling.
5. Define migration and compatibility strategy for old endpoints.

## Out of Scope (Phase 1)

1. Full Agent orchestration engine.
2. New loop worker implementation.
3. UI replacement/removal of old modals.
4. Auto-execution behavior changes.

## Current State

Workbench currently exposes separate responsibilities:

1. `coach`: one-shot evaluation report (`/coach/evaluate`).
2. `consultant`: chat endpoint (`/consultant/chat`).
3. `copilot`: always-on event loop + advice/action stream (`/copilot/*`).

These are valid technical layers but fragmented UX.

## Target API Surface (Unified)

All under `/api/v1/simulation/sessions/{session_id}/agent/*`:

1. `POST /chat`
2. `POST /run-once`
3. `POST /start`
4. `POST /stop`
5. `POST /pause`
6. `POST /resume`
7. `GET /state`
8. `POST /action`

### Semantics

1. `chat`: conversational turn with optional tool calls.
2. `run-once`: one decision cycle over current context.
3. `start/stop`: controls continuous loop lifecycle.
4. `pause/resume`: keeps session active but blocks autonomous actions.
5. `state`: merged status, last outputs, action queue.
6. `action`: user approval/rejection/execute on proposed actions.

## Permission Model

Agent permission flags (per session):

1. `can_chat`
2. `can_scan_tools`
3. `can_use_research`
4. `can_manage_indicators`
5. `can_place_trades`
6. `can_close_trades`
7. `can_auto_execute`
8. `requires_user_confirm_for_trade`

### Hard Rules

1. If `can_place_trades=false`, any trade action must be blocked server-side.
2. If `can_auto_execute=true`, `can_place_trades` and `can_close_trades` must both be true.
3. If `requires_user_confirm_for_trade=true`, autonomous trade execution is disallowed.

## Action and Audit Schema

### Agent Action Types

1. `SCAN_TOOL`
2. `SET_INDICATOR_VISIBILITY`
3. `RUN_RESEARCH_OPTIMIZER`
4. `RUN_ML_DIAGNOSTIC`
5. `PROPOSE_TRADE_ENTRY`
6. `PROPOSE_TRADE_EXIT`
7. `EXECUTE_TRADE_ENTRY`
8. `EXECUTE_TRADE_EXIT`
9. `REVIEW_NOTE`

### Agent Action Status

1. `PROPOSED`
2. `APPROVED`
3. `REJECTED`
4. `EXECUTED`
5. `BLOCKED_POLICY`
6. `FAILED`

### Audit Requirements

Every action record must include:

1. `requested_by` (`USER` or `AGENT`)
2. `action_type`
3. `status`
4. `reason`
5. `payload_json`
6. `created_at`

## Provider Profiles

Supported providers:

1. `deterministic`
2. `local_gptoss_http`
3. `openai_compat`
4. `claude`

### Provider Runtime Fields

1. `provider`
2. `model_label`
3. `llm_url`
4. `timeout_sec`
5. `api_key` (runtime only, not persisted)

### Secret Resolution Order

1. request runtime `api_key`
2. provider-specific runtime keys
3. environment variables

For Claude in this codebase, resolve both:

1. `ANTHROPIC_API_KEY`
2. `CLAUDE_API_KEY`

## Backward Compatibility Strategy

Phase 1 keeps old routes working. Unified Agent will be additive first.

1. Existing `coach/consultant/copilot` endpoints stay intact.
2. New `agent` contracts map to existing internals in Phase 2 adapter layer.
3. Old UI can run during migration window behind feature flag.

## Data Model Strategy

Phase 1 can reuse current tables for immediate compatibility:

1. `workbench_copilot_sessions`
2. `workbench_copilot_events`
3. `workbench_copilot_advices`
4. `workbench_copilot_actions`
5. `workbench_copilot_snapshots`

Optional Phase 4 adds dedicated `workbench_agent_*` tables after stabilization.

## Codex and Opus Work Split

### Codex (Phase 1)

1. Spec and contracts in backend API models.
2. Secret alias compatibility (`CLAUDE_API_KEY`).
3. Validation constraints for permission and action models.

### Opus (Phase 1)

1. Contract review and payload consistency checks.
2. UI migration map from 3 panels to 1 Agent panel.
3. Backward-compatibility verification checklist.

## Acceptance Criteria (Phase 1)

1. Unified contract document exists and is implementation-ready.
2. Backend contains explicit Agent request/response models.
3. Claude key alias support works with `CLAUDE_API_KEY`.
4. No regressions in existing coach/consultant/copilot routes.

## Phase 2 Handoff

Phase 2 builds `WorkbenchAgent` orchestrator and new `/agent/*` routes using these contracts, with adapter calls into existing tool/trade/research services.
