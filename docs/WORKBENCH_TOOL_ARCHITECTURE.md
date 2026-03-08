# Workbench Tool Architecture (Extension Guide)

This document explains how the Workbench tooling system is built today and how to add new tools safely.

Primary goal: future additions like `mitigation` and `breaker` (both normal scan and drawing-assisted scan) should be additive, low-risk, and consistent with current behavior.

## 1. Current architecture at a glance

The Workbench stack has five layers:

1. Tool definition layer (backend)
2. Tool execution routes (backend)
3. Session state + snapshot propagation (backend)
4. Chart/tool UI and local tool state (frontend)
5. Agent tool-calling orchestration (backend + frontend)

### Main files

- Tool base contract: `dashboard/backend/core/workbench/tool_base.py`
- Tool registry: `dashboard/backend/core/workbench/__init__.py`
- Tool implementations:
  - `dashboard/backend/core/workbench/fvg_tool.py`
  - `dashboard/backend/core/workbench/mean_rev_tool.py`
- Core routes and execution:
  - `dashboard/backend/api/simulation_routes.py`
- Agent tool planner/executor contracts:
  - `dashboard/backend/core/workbench/agent.py`
  - `dashboard/backend/api/simulation_routes.py` (`_agent_execute_tool`)
- Frontend tool state and rendering:
  - `dashboard/frontend/static/js/workbench.js`
  - `dashboard/frontend/templates/workbench.html`
- Flask proxy passthrough:
  - `dashboard/frontend/app.py`

## 2. Backend tool contract

All tools derive from `WorkbenchTool`:

- `tool_id` (stable ID)
- `display_name`
- `icon`
- `description`
- `scan(df, config) -> List[Dict]`
- `get_default_config()` (default includes `strictness: 3`)
- `normalize_strictness(...)` helper

Design constraint:
- `scan()` must be pure with respect to input data/config (no DB writes, no global mutation).
- Return output as chart-ready dict rows (zones/signals).

## 3. Tool registry pattern

Registry file: `dashboard/backend/core/workbench/__init__.py`

`WORKBENCH_TOOLS` holds singleton tool instances. Routes and agent executor use `get_tool(tool_id)`.

Why this is scalable:
- No route changes needed per new tool.
- `GET /simulation/workbench/tools` auto-exposes metadata via `list_tools()`.
- Default config and strictness metadata are surfaced to UI from a single source.

## 4. Tool execution route flow

Main endpoint:
- `POST /api/v1/simulation/sessions/{session_id}/tools/{tool_id}/scan`
- Function: `workbench_scan_tool(...)` in `simulation_routes.py`

Execution flow:

1. Validate session and tool ID.
2. Resolve bar source:
   - Preferred: client bars (`req.bars`) for live mode accuracy.
   - Fallback: engine visible bars (`engine.df[:current_bar+1]`).
3. Apply lookback controls (`lookback_bars`, `lookback_days`).
4. Merge config:
   - tool defaults
   - request config
   - symbol/timeframe context
5. Optional derived calls on tool:
   - `compute_trend_context(...)`
   - `compute_movement_strength(...)`
   - `compute_current_state(...)`
6. Call `tool.scan(...)`.
7. Build preview payload via `_build_tool_zone_preview(...)`.
8. Build persisted tool-state patch via `_build_tool_state_patch(...)`.
9. Emit `TOOL_SIGNAL_CHANGED` event and store snapshot.
10. Return full scan response to caller.

Key detail:
- Route already supports both replay and live chart bars. This is why tools are reusable across data modes.

## 5. Drawing-assisted tool pattern

Current drawing tool is implemented as a logical tool action (`scan_draw_fvg_range`) in agent/runtime, with UI picks on frontend.

Frontend behavior (`workbench.js`):
- User toggles drawing mode and picks two bars on chart.
- Selected bar window is sliced from `allBars`.
- Client sends only selected bars to normal scan route (`tools/fvg/scan`).
- UI displays resulting zones and creator markers.

Backend behavior:
- `_agent_execute_tool(..., tool_name="scan_draw_fvg_range")` maps selected indices to subset bars, then reuses normal `workbench_scan_tool`.
- Result is transformed into tool-state patch by `_agent_tool_state_from_tool_calls(...)`.

This is the preferred architecture for future drawing tools:
- Keep one canonical scan implementation per domain tool.
- Drawing mode should only define how the bar subset is selected.

## 6. Agent integration architecture

### Tool schema surface

`WorkbenchAgent._tool_specs()` defines callable tools:

- `scan_tool`
- `scan_draw_fvg_range`
- `place_trade`
- `close_trade`
- `run_research_optimize`
- `run_ml_diagnostic`
- `set_indicator_visibility`

Provider support:
- OpenAI-compatible: structured `tools` payload.
- Claude: transformed to `input_schema`.
- Local GPT-OSS: tool list embedded into prompt + JSON pass.

### Runtime executor

`_agent_execute_tool(...)` in `simulation_routes.py` is the canonical tool dispatcher. It enforces permission gates per action:

- `can_scan_tools`
- `can_use_research`
- `can_manage_indicators`
- `can_place_trades`
- `can_close_trades`
- `requires_user_confirm_for_trade`

Trade atomicity detail:
- For agent-triggered trade actions, `_suppress_commit` is set during nested calls so parent route controls final transaction boundary.

### Tool results to chart state

`_agent_tool_state_from_tool_calls(...)` maps successful tool call results into persisted tool-state patch fields like:

- `fvg_last_zone_count`
- `fvg_zones_preview`
- `mean_rev_last_zone_count`
- `indicator_visibility`
- `draw_fvg_selection`

Frontend periodically reads agent/copilot state and can render the same visual artifacts as manual tool usage.

## 7. Frontend tool state model

Main local state source:
- `getToolStatePayload()` in `workbench.js`

It exports:

- `active_tools`
- per-tool config and counters
- compatibility fields (`fvg_*`, `mean_rev_*`)

This payload is pushed to backend via:
- `/api/simulation/sessions/{id}/agent/tool-state`

Rendering:
- `ChartZoneRenderer` draws zones as overlay divs and extension lines.
- Tool inspectors render summarized zone lists and stats.
- Marker helpers (example: FVG creator markers) annotate source bars.

## 8. How to add a new normal scan tool

Example target: `breaker` tool.

1. Create tool class:
   - File: `dashboard/backend/core/workbench/breaker_tool.py`
   - Inherit `WorkbenchTool`
   - Implement metadata + `scan(...)`
   - Optional: `compute_trend_context`, `compute_movement_strength`, `compute_current_state`
2. Register tool:
   - Add singleton in `WORKBENCH_TOOLS` in `dashboard/backend/core/workbench/__init__.py`
3. Add UI card:
   - `dashboard/frontend/templates/workbench.html`
   - Toggle + config controls + scan/clear buttons + inspector area
4. Wire UI handlers:
   - `dashboard/frontend/static/js/workbench.js`
   - Add `toolStates.breaker`
   - Implement `scanBreaker()` and clear functions
   - Update `getToolStatePayload()`
5. Agent support:
   - Add new tool schema to `_tool_specs()` in `agent.py`
   - Add path in `_agent_execute_tool(...)`
   - Extend `_agent_tool_state_from_tool_calls(...)` if custom patch mapping is needed
6. Tests:
   - Tool logic unit tests
   - Route integration tests
   - Agent tool-call mapping tests

## 9. How to add a new drawing tool

Example target: `draw_breaker_range`.

Recommended pattern:

1. Reuse normal `breaker` scan route and logic.
2. Frontend:
   - Add drawing toggle + pick state (`toolStates.draw_breaker`)
   - Click-to-pick bars
   - Slice selected bars and POST to `tools/breaker/scan`
3. Agent:
   - Add tool schema `scan_draw_breaker_range`
   - In `_agent_execute_tool(...)`, convert index range to selected bars and call canonical scan route
4. Persist selection context:
   - Extend `_agent_tool_state_from_tool_calls(...)` to record selected range metadata for UI

Do not duplicate breaker detection logic for draw mode. Draw mode should only change bar selection.

## 10. Zone payload conventions (recommended)

For chart interoperability, each returned zone/signal row should include:

- `type`
- `top`
- `bottom`
- `start_time_unix`
- `end_time_unix`
- `bar_index`

Optional but useful:

- `filled` / `mitigations`
- `original_gap_size`, `current_gap_size`
- `origin_top`, `origin_bottom`
- `scan_timeframe`
- `style` (`bg`, `border`, `line`)

Keep numeric values finite and JSON-safe.

## 11. Data source compatibility rules

Tool route already supports:
- replay engine bars
- live client bars

To stay compatible:
- treat `req.bars` as authoritative if present
- ensure min bar requirements are explicit
- avoid relying on engine-only internals inside tool code

## 12. Performance and safety rules

Performance:
- Respect row caps on inbound bars.
- Keep preview payload small (`zones_preview`) for looped agent updates.
- Prefer derived summaries in snapshots; keep full zones in direct scan response.

Safety:
- Enforce permission gates in executor, not just frontend.
- Keep provider tool-name allowlists active.
- Keep API keys out of persisted runtime JSON.
- Validate finite OHLCV data before tool computation.

## 13. Testing checklist for each new tool

Minimum:

1. Tool unit test: detection logic with deterministic fixture bars.
2. Route test: `tools/{tool_id}/scan` returns expected schema.
3. Live-bars test: scan with `req.bars` path works.
4. Agent dispatch test: tool call reaches executor and maps result.
5. Tool-state patch test: preview fields update for UI.
6. Frontend smoke: scan/clear buttons, overlay draw, inspector count.

## 14. Known extension points

- Future tools listed in UI placeholders can be activated without route redesign.
- Agent already supports mixed tool orchestration.
- Research and indicator routes are already callable as tools.
- Drawing workflow can be reused for any selection-based detector.

## 15. Practical recommendation for upcoming course-driven tools

When you add `mitigation` and `breaker`:

1. Implement them as normal tools first (`scan_tool` path).
2. Add draw variants second (selection wrapper only).
3. Reuse zone renderer and inspector conventions.
4. Add agent tool specs immediately so chat/loop can use them.
5. Add tests before UI polish to lock detection behavior.

This keeps functionality stable while the toolset grows quickly.
