# Guided Trading Simulation Control Plane - Implementation Plan

## 1. Objective

Build a new **Guided Trading Simulation** layer inside the existing `Trading Systems` module so a beginner can run each strategy step-by-step with:

- an `Open Trading Simulation` button per strategy
- strategy-specific visual guidance (ex: ORB first 15m high/low, breakout/FVG confirmation)
- plain-language instruction cards ("what to do now", "why", "what invalidates it")
- a simulation-safe workflow (no accidental live order placement)

This plan is designed for collaborative implementation by both agents (Codex + Opus), with clear parallel workstreams.

## 2. Non-Negotiable UX Requirements

1. Every strategy must have a **simple guide card** for beginners.
2. Every strategy simulation page must answer:
   - `Current Step`
   - `Why this step`
   - `What you wait for`
   - `What invalidates setup`
   - `What action to take now`
3. Strategy evidence must be visible without calculations by user.
4. Simulation mode must be clearly separated from live mode.

## 3. Current-State Audit (From Codebase)

### 3.1 Frontend

- Trading Systems page exists: `dashboard/frontend/templates/trading_systems.html`
- Current actions:
  - Start strategy
  - Stop strategy
  - View details modal
- No dedicated simulation workspace page yet.

### 3.2 Backend

- Strategy listing endpoint exists: `GET /api/v1/strategies`
- Start/stop endpoints exist.
- Current strategy state polling exists (`/strategies/{strategy_id}/state`).
- No simulation session model/endpoints.

### 3.3 Critical Strategy Mapping Mismatch (Must Fix First)

Registry (`dashboard/backend/core/strategy_registry.py`) has:

- `orb_strategy`
- `advanced_orb_strategy`
- `orb_ml_strategy`
- `advanced_orb_ml_strategy`
- `liquidity_sweep_strategy`
- `keltner_breakout_strategy`
- `b_profile_reversion_strategy`
- `earnings_volatility_strategy`

Runtime manager (`Strategies/strategy_manager.py` STRATEGY_PATHS) has:

- `orb_strategy`
- `advanced_orb_strategy`
- `liquidity_sweep_strategy`
- `keltner_breakout_strategy`
- `orb_ml_strategy`
- `advanced_orb_ml_strategy`
- `liquidity_sweep_ml_strategy`
- `keltner_breakout_ml_strategy`

Meaning:

- some strategies are listed but not runnable from manager
- some runnable strategies are not listed in registry

This mismatch must be reconciled before production simulation UX.

## 4. Product Scope

## 4.1 Phase-1 In Scope

- Open Simulation button in Trading Systems cards
- New simulation workspace page (generic shell + strategy-specific panels)
- Beginner info card modal per strategy
- Step engine for:
  - ORB
  - Advanced ORB
  - Liquidity Sweep
  - Keltner Breakout
- ML wrappers inherit same base-step UI + ML confidence panel
- Simulation session persistence and timeline

## 4.2 Phase-2 In Scope

- B-Profile Reversion simulation dashboard
- Earnings Volatility simulation dashboard
- Replay mode for backtest-only strategies if live process not available

## 4.3 Out of Scope (for now)

- autonomous live execution by LLM
- broker-level options execution in simulation page
- full visual charting platform replacement

## 5. Target Architecture

## 5.1 Core Principle

Do **not** build 8 separate ad-hoc pages.

Build one generic **Simulation Workspace Shell** and plug strategy-specific adapters into it.

## 5.2 New Components

1. Simulation Session Store
- DB tables for session, events, user actions, step transitions

2. Simulation Playbook Engine
- strategy -> playbook definition
- playbook -> steps -> rules -> statuses
- statuses: `WAIT`, `READY`, `ACTIONABLE`, `BLOCKED`, `DONE`

3. Strategy Telemetry Adapter Layer
- normalizes bot states into a standard schema
- strategy-specific enrichers compute explainable signals

4. Beginner Instruction Layer
- per-strategy plain-language cards
- "5-year-old version" for each step

5. Simulation Workspace UI
- unified layout
- strategy-specific widgets injected dynamically

## 6. Data Contracts

## 6.1 Standard Telemetry Contract (New)

Each strategy adapter must produce:

```json
{
  "strategy_id": "orb_strategy",
  "timestamp": "ISO-8601",
  "mode": "demo|live",
  "market": {
    "symbol": "XAUUSD",
    "timeframe": "M1",
    "price": 0.0,
    "spread": 0.0
  },
  "risk": {
    "can_trade": true,
    "daily_trades": 0,
    "daily_pnl": 0.0,
    "open_positions": 0
  },
  "step_inputs": {},
  "signals": [],
  "explanations": []
}
```

## 6.2 Strategy-Specific Inputs

### ORB / Advanced ORB

- first 15m high/low
- orb range quality
- breakout side
- displacement flag
- FVG presence/size
- bias strength
- invalidation reason

### Liquidity Sweep

- tracked liquidity levels
- sweep detected + direction
- rejection confirmation
- FVG confirmation (if required)
- minimum RR check

### Keltner Breakout

- squeeze on/off and fire
- channel break side
- ADX gate status
- momentum confirmation
- trend filter status

### ML Wrappers

- base setup status
- ML probability
- threshold pass/fail
- dynamic RR suggestion (if enabled)

### B-Profile Reversion (Phase-2)

- profile shape classification
- failed auction trigger
- value area targets
- invalidation above/below structure

### Earnings Volatility (Phase-2)

- event timing window
- term-structure condition
- volume/liquidity gate
- structure type suitability

## 7. Backend Implementation Plan

## 7.1 New Files

- `dashboard/backend/core/trading_simulation/playbooks.py`
- `dashboard/backend/core/trading_simulation/evaluator.py`
- `dashboard/backend/core/trading_simulation/adapters.py`
- `dashboard/backend/core/trading_simulation/session_service.py`
- `dashboard/backend/core/trading_simulation/education.py`

## 7.2 DB Changes

Modify `dashboard/backend/models/database.py`:

- `TradingSimulationSessionModel`
- `TradingSimulationEventModel`
- `TradingSimulationActionModel`

Add migration entries in `_run_migrations()`.

## 7.3 Schema Changes

Modify `dashboard/backend/models/schemas.py`:

- simulation session request/response models
- step status models
- strategy guide models

## 7.4 API Routes

Modify `dashboard/backend/api/routes.py`:

- `POST /trading-simulation/sessions`
- `GET /trading-simulation/sessions/{session_id}`
- `GET /trading-simulation/sessions/{session_id}/state`
- `POST /trading-simulation/sessions/{session_id}/action`
- `GET /trading-simulation/strategies/{strategy_id}/guide`
- `GET /trading-simulation/strategies/{strategy_id}/playbook`

## 7.5 Strategy State Ingestion

Use existing manager state plus strategy state file readers.

Add adapter fallback behavior:

- If telemetry missing, mark step as `WAIT` and expose why.
- Never fabricate readiness.

## 8. Frontend Implementation Plan

## 8.1 Trading Systems Page

Modify `dashboard/frontend/templates/trading_systems.html`:

- add button: `Open Trading Simulation`
- add info icon beside strategy name to open beginner guide modal

Modify JS section:

- open simulation route with strategy context
- preload strategy guide summary snippet

## 8.2 New Simulation Page

Add `dashboard/frontend/templates/trading_simulation_workspace.html`

Sections:

1. Header
- strategy
- symbol/timeframe
- simulation mode badge
- session status

2. Step Timeline
- step list with status badges
- current actionable step highlighted

3. "Do This Now" card
- one action sentence
- one reason sentence
- one invalidation sentence

4. Evidence Panel
- raw metrics used for decision
- explicit threshold comparisons

5. Strategy Visual Panel
- ORB panel / sweep panel / keltner panel (component swap by strategy)

6. Beginner Info Card Modal
- plain-language setup explanation
- common mistakes
- checklist before entry

7. Action Journal
- user marks "I see condition", "I entered paper trade", "I skipped"

## 8.3 Frontend Route Wiring

Modify `dashboard/frontend/app.py`:

- route for simulation workspace page
- proxy endpoints for simulation APIs

## 9. Strategy Guide Content Plan

Create one structured guide object per strategy:

- `what_this_strategy_is`
- `when_not_to_trade`
- `step_by_step`
- `common_mistakes`
- `risk_rules`
- `example_scenario`

This should be stored in backend (`education.py`) and rendered dynamically.

## 10. Reconciliation Plan (Registry vs Manager)

Before simulation rollout:

1. Build capability matrix endpoint:
- listed
- runnable
- has_live_state
- has_playbook

2. Decide truth source:
- recommended: registry remains product catalog
- manager becomes executable catalog

3. Add explicit status flags in UI:
- `Live Runnable`
- `Replay Only`
- `Coming Soon`

This removes hidden failures for users.

## 11. Delivery Phases and Milestones

## Phase 0 - Architecture Lock (2-3 days)

- finalize capability matrix
- lock telemetry contract
- lock simulation state machine

Exit criteria:
- approved API contract
- approved UI wireframes

## Phase 1 - ORB Pilot (4-6 days)

- simulation backend foundation
- ORB step evaluator
- ORB simulation dashboard + beginner guide

Exit criteria:
- user can run ORB simulation session end-to-end
- all ORB steps clearly visible with evidence

## Phase 2 - Core Strategy Expansion (5-7 days)

- Advanced ORB
- Liquidity Sweep
- Keltner Breakout

Exit criteria:
- 4 base live strategies supported with strategy-specific visuals

## Phase 3 - ML Strategy Layer (3-4 days)

- ORB+ML
- Advanced ORB+ML
- Liquidity Sweep+ML
- Keltner Breakout+ML (if kept in manager)

Exit criteria:
- ML threshold + probability shown in plain language

## Phase 4 - Backtest/Replay Strategies (4-6 days)

- B-Profile Reversion
- Earnings Volatility
- replay mode if no live process

Exit criteria:
- no strategy card opens into dead page

## Phase 5 - Hardening (3-5 days)

- audit logs
- session resume
- stale-state handling
- UX polish and accessibility

Exit criteria:
- production acceptance checklist passed

## 12. Parallel Work Allocation (Codex + Opus)

## Workstream A (Codex)

- backend session models/schemas/routes
- playbook evaluator engine
- telemetry adapters
- unit + integration tests
- performance and error handling

## Workstream B (Opus)

- simulation workspace UX + components
- strategy guide copy + info cards
- trading systems button integration
- strategy visual widgets
- end-user walkthrough copy

## Integration Checkpoints

1. Contract freeze checkpoint
2. ORB pilot checkpoint
3. Core 4 strategies checkpoint
4. Full strategy matrix checkpoint
5. Production readiness checkpoint

## 13. Test Strategy

## 13.1 Backend Tests

- playbook rule tests per strategy
- telemetry adapter tests
- API contract tests
- stale/partial telemetry behavior tests

## 13.2 Frontend Tests

- simulation page rendering with mock data
- step transitions and status badges
- info card content and modal behavior
- broken strategy fallback states

## 13.3 End-to-End Tests

- start simulation from Trading Systems
- receive live state updates
- complete step checklist
- log paper action
- session persists and resumes

## 13.4 Regression Tests

- existing strategy start/stop unaffected
- capital allocation/governor unaffected
- options modules unaffected

## 14. Observability and Safety

Add telemetry logs:

- simulation session created/stopped
- step state transitions
- missing telemetry reasons
- user actions in session

Safety defaults:

- simulation defaults to `demo`
- no live execution calls from simulation page
- explicit confirmation if user attempts mode switch

## 15. Risks and Mitigations

1. Inconsistent strategy state payloads
- mitigate with adapter layer + schema validation

2. Strategy not live-runnable but shown as active
- mitigate with capability matrix + explicit badges

3. Beginner overload from too much data
- mitigate with progressive disclosure:
  - simple card first
  - advanced metrics expandable

4. Timezone confusion
- mitigate with explicit NY + broker time display everywhere

5. UI becoming strategy-specific spaghetti
- mitigate with shell + pluggable widget architecture

## 16. Acceptance Criteria

Product accepted when:

1. Every strategy card has `Open Trading Simulation`.
2. User can run simulation for each listed strategy as `Live Runnable` or `Replay Only`.
3. Every strategy shows a beginner info card with plain-language checklist.
4. ORB simulation clearly displays:
   - first 15m NY high/low
   - breakout status
   - displacement/FVG confirmation
   - actionable next step
5. No simulation action can accidentally place live order without explicit mode switch.
6. Existing Trading Systems features continue to work.

## 17. Immediate Next Step

Implement **Phase 0** first:

- capability matrix endpoint
- strategy mapping reconciliation
- simulation telemetry schema freeze

No UI development starts before Phase 0 is accepted.

