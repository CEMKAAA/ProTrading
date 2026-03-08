# AI Bot Infrastructure (Phase 1)

## Scope

This document describes the first production-grade AI bot control layer added to ProTradingSystem.

Current implementation focus:
- Options Edge scan -> AI plan generation -> persisted execution intents.
- Pluggable LLM providers:
  - `deterministic`
  - `local_gptoss_http`
  - `openai_compat`

This phase does **not** directly send broker orders. It is paper-first by design (`dry_run=true` default) and outputs structured execution intents.

## Existing Live Trading Architecture (already in system)

Live strategy launch path:

1. Frontend `Trading Systems` page:
   - `dashboard/frontend/templates/trading_systems.html`
   - User selects strategy + preset + symbol/timeframe + mode.
2. Frontend -> Backend API:
   - `POST /api/v1/strategies/{strategy_id}/start`
3. Backend Strategy manager:
   - `Strategies/strategy_manager.py`
   - Loads strategy config, validates capital/governor, starts strategy process via `subprocess.Popen`.
4. Strategy process runs standalone `main.py`:
   - Example: `Strategies/ORBStrategy/main.py`
   - Writes state JSON consumed by dashboard.

Important implication:
- The 9 live strategies are currently process-driven strategy engines.
- Options Edge lives in dashboard backend domain (`/options-edge/*`) and is not currently one of those live process strategies.

## New AI Bot Control Plane Added

### New core module
- `dashboard/backend/core/ai_bot/options_edge_agent.py`

Responsibilities:
- Load persisted options-edge context (`scan`, `candidates`, `trade candidates`).
- Generate report using selected provider.
- Convert report `trade_decisions` into executable intents with risk-aware contract sizing.

### New persistence model
- `dashboard/backend/models/database.py`
  - `AIBotRunModel` (`ai_bot_runs`)
  - Stores request, report, execution plan, status, provider/model, errors.

### New APIs
- `POST /api/v1/ai-bots/options-edge/plan/{scan_id}`
- `GET /api/v1/ai-bots/runs/{run_id}`
- `GET /api/v1/ai-bots/runs`

### Frontend integration
- `dashboard/frontend/app.py`
  - Added AI plan generation route for scan detail.
- `dashboard/frontend/templates/options_edge_scan_detail.html`
  - Added "AI Trader Bot Plan" panel:
    - provider/model/account/risk inputs
    - dry-run toggle
    - latest plan table with action/reason/evidence

## Provider Behavior

### deterministic
- Uses deterministic report builder.
- Produces explainable, numeric-only decisions.

### local_gptoss_http
- Uses local GPT-OSS sidecar path through options-edge reporter.
- Good for local/private inference.

### openai_compat
- Calls OpenAI-compatible `/chat/completions`.
- Requires API key and (optionally) custom base URL.
- Strict JSON response is enforced and normalized.

## Safety Design

- Default mode is dry-run (paper intents).
- Contract sizing caps by account risk and `max_contracts_cap`.
- If risk budget cannot support a trade, intent downgrades to `WATCH`.
- No direct broker execution in this phase.

## How this scales to the 9 live strategies

Target extension pattern:

1. Add a strategy-specific agent adapter under `dashboard/backend/core/ai_bot/`.
   - Input: normalized strategy state/config/features.
   - Output: standardized plan actions.
2. Reuse `ai_bot_runs` table and run endpoints.
3. Add execution adapters:
   - `paper` (first)
   - `mt5/live` (later, guarded)
4. Add per-strategy risk guardrails (max daily risk, cooldown, invalidation rules).

## Why not immediate full auto-execution?

Because current live strategies are process-isolated loops, forcing immediate autonomous order placement from a new LLM layer would introduce unsafe coupling and high operational risk.

The safer path is:
- phase-by-phase integration
- explicit plan outputs
- operator review
- then gated execution for selected strategies.

## NautilusTrader integration note

Nautilus can be a strong execution/runtime candidate when you need:
- strict backtest/live parity on an event-driven engine
- richer venue adapter model
- lower-latency/high-frequency workflows

But immediate full migration is high effort because this repo already has:
- custom StrategyManager process model
- MT5-centric live pipeline
- dashboard APIs tied to existing strategy lifecycle

Recommended path:
- keep current engine for near-term delivery
- add an execution adapter boundary in AI bot layer
- prototype a single strategy in Nautilus runtime before any full migration decision

