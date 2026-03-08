# 2026-03-02 Workbench Agent Memory - Phase 4

## Scope

Phase 4 adds memory governance policies so retention and retrieval quality can be controlled explicitly.

## Implemented

1. Memory policy model (session-scoped config)
   - Stored at: `simulation_session.config_json.agent_memory_policy`
   - Fields:
     - `enabled`
     - `ttl_days_default`
     - `ttl_days_by_type`
     - `pinned_never_expires`
     - `min_importance`
     - `max_hits`
     - `recency_half_life_days`
     - `pin_bonus`

2. Policy-aware retrieval and pruning
   - Retrieval now:
     - skips expired memories (unless pinned and `pinned_never_expires=true`)
     - filters by `min_importance`
     - uses exponential recency decay via `recency_half_life_days`
     - applies pin bonus and bounded max hits
   - Expired memory rows are pruned during list/search/add and policy update.

3. Policy API
   - `GET /api/v1/simulation/sessions/{id}/agent/memory-policy`
   - `POST /api/v1/simulation/sessions/{id}/agent/memory-policy`
   - Flask proxy routes added under `/api/simulation/...`.

4. UI controls
   - Agent Memory panel now includes policy controls:
     - enable/disable
     - pinned no-expire
     - default TTL
     - minimum importance
     - max retrieval hits
   - Apply button updates backend policy.

## Outcome

Memory now has predictable lifecycle behavior and tunable retrieval quality, instead of unbounded organic growth.
