# 2026-03-02 Workbench Agent Memory - Phase 7

## Scope

Phase 7 enforces personality stability:

1. Character/persona/tone stay locked.
2. Strategy/process knowledge can still adapt from outcomes.

## Implemented

1. Locked identity profile in session config
   - Key: `simulation_session.config_json.agent_identity`
   - Fields:
     - `enabled`
     - `version`
     - `lock_personality`
     - `persona`
     - `tone`
     - `risk_doctrine`
     - `immutable_rules`

2. Identity API
   - `GET /api/v1/simulation/sessions/{id}/agent/identity`
   - `POST /api/v1/simulation/sessions/{id}/agent/identity`
   - Flask proxy endpoints added under `/api/simulation/...`.

3. Prompt-level hard guard
   - Agent system prompt now explicitly states identity is locked.
   - Includes serialized `Locked Identity JSON` context for deterministic enforcement.

4. Memory write guard against personality drift
   - Model/user memory note writes are filtered when they attempt persona/tone/character mutation.
   - Applies to:
     - `memory_notes` persistence path
     - generic memory add path (all sources)
     - auto teaching extractor path

5. Context lock
   - Chat/run-once context always injects identity from session config after merge.
   - Client payload cannot override locked identity.

## Outcome

The agent can continue learning strategy and execution lessons while maintaining a stable apprentice personality and tone over time.

