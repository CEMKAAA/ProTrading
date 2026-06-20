# ORB Implementation Roadmap

This roadmap defines the exact implementation order for extending `RealOrbStrategy.mq5`.

Goal: add advanced ORB entry, stop, target, and daily management modes without breaking the current working baseline.

Baseline rule:
- Existing ORB behavior must remain the default.
- Every new feature must be behind an input/dashboard toggle.
- Every phase must compile cleanly before moving to the next phase.
- Every phase must update:
  - live execution path
  - historical chart signals
  - internal backtest rows
  - audit labels/log detail
  - native MT5 validation compatibility

Related plan files:
- `ORB_EXIT_ENGINE_IMPLEMENTATION_PLAN.md`
- `ORB_PULLBACK_RETEST_IMPLEMENTATION_PLAN.md`
- `ORB_IMBALANCE_MODEL_IMPLEMENTATION_PLAN.md`
- `ORB_STOP_TARGET_MODE_MATRIX.md`

## Phase 0 - Baseline Lock

Purpose: freeze the current known-good ORB behavior.

Tasks:
- Confirm current build compiles.
- Record current default behavior:
  - entry: breakout close
  - initial SL: ORB opposite side
  - target: selected R leg
  - HC/BE: OFF by default
  - FVG: OFF by default
  - auto session: ON
- Run a small historical chart redraw check.
- Run one internal 2W check.

Exit criteria:
- Compile: 0 errors, 0 warnings.
- Existing default chart output still appears.
- Dashboard still loads.
- No new feature active by default.

## Phase 1 - Exit / SL Engine

Purpose: add professional stop and exit modes first, because exits are currently the biggest expectancy lever.

New modes:
1. `FIXED_TARGET`
   - Existing behavior.

2. `EOD_ONLY_CAT_STOP`
   - Catastrophic SL.
   - No fixed TP.
   - Close at session end.

3. `ORB_MIDPOINT_INVALIDATION`
   - BUY exits if closed candle falls below ORB midpoint.
   - SELL exits if closed candle rises above ORB midpoint.

4. `ATR_TRAIL`
   - Chandelier-style trailing stop.
   - BUY trail = highest high since entry - ATR * multiplier.
   - SELL trail = lowest low since entry + ATR * multiplier.

5. `EMA_DYNAMIC_STOP`
   - EMA50/EMA100 exit.

6. `VWAP_DYNAMIC_STOP`
   - Session VWAP invalidation.

Implementation scope:
- Add `ORB_EXIT_ENGINE_MODE`.
- Add runtime vars and dashboard button.
- Add live `ManagePositions()` handling.
- Add historical simulation handling.
- Add backtest combo output columns.
- Add audit events:
  - `eod_exit`
  - `orb_mid_exit`
  - `atr_trail_update`
  - `ema_exit`
  - `vwap_exit`

Default:
- `FIXED_TARGET`

Exit criteria:
- Default results match pre-phase baseline.
- Each exit mode can be selected from dashboard.
- Each exit mode appears in internal backtest result CSV.
- Chart labels show exit mode and final outcome.
- Native MT5 sample validation can be run for at least one exit mode.

## Phase 2 - Target Engine

Purpose: separate target selection from stop/exit management.

New target modes:
1. `FIXED_R_LEG`
   - Existing TP1..TP6 behavior.

2. `RANGE_HEIGHT_TARGET`
   - TP distance = ORB range * multiplier.

3. `EOD_TARGET`
   - No fixed TP.
   - Position closes at end of session or dynamic exit.

4. `AUTO_STOP_SIZE_TARGET`
   - If stop size is small: target 2R.
   - If stop size is large: target 1R.

Implementation scope:
- Add `ORB_TARGET_MODE`.
- Add `InpRangeTargetMultiplier`.
- Add `InpSmallStopThresholdPts`.
- Add `InpSmallStopTargetR`.
- Add `InpLargeStopTargetR`.
- Centralize target calculation in one helper:
  - `ResolveTargetPriceAndR(...)`
- Update live open logic.
- Update historical sim.
- Update backtest CSV.
- Update chart label:
  - `TPMODE=RANGE`
  - `TPMODE=EOD`
  - `TPMODE=AUTO`

Default:
- `FIXED_R_LEG`

Exit criteria:
- Existing fixed R behavior unchanged.
- Range-height target matches ORB range visually.
- EOD target opens with no fixed TP or broker-safe equivalent.
- Auto target logs selected R and stop size.

## Phase 3 - Pullback Retest Entry Mode

Purpose: add optional retest entry model.

New entry modes:
1. `BREAKOUT_CLOSE`
   - Existing behavior.

2. `PULLBACK_RETEST`
   - Breakout must happen first.
   - Price retests ORH/ORL.
   - Price confirms continuation.

3. `BREAKOUT_OR_RETEST`
   - Allows direct breakout or retest fallback.

Implementation scope:
- Add `ORB_ENTRY_MODE`.
- Add pending breakout state machine.
- Add retest tolerance and max wait bars.
- Add historical `FindHistPullbackRetest()`.
- Add dashboard button:
  - `ENTRY: BRK/RT/BOTH`
- Add audit events:
  - `breakout_seen`
  - `retest_seen`
  - `retest_confirmed`
  - `retest_expired`
  - `retest_opposite_reset`

Default:
- `BREAKOUT_CLOSE`

Exit criteria:
- Default breakout entries unchanged.
- Retest mode does not open until retest confirmation.
- Chart shows both breakout marker and retest entry marker.
- Internal backtest can compare BRK vs RT vs BOTH.

## Phase 4 - 1M Imbalance Entry Model

Purpose: implement the trader-style 15m ORB + 1m imbalance model.

New confirmation/entry model:
- `1M_IMBALANCE_ENTRY`

Rules:
- Mark ORH/ORL.
- Wait for breakout close.
- Then wait for 1m imbalance/FVG in breakout direction.
- Enter on imbalance confirmation.
- SL can be imbalance low/high.
- Target can be auto 1R/2R based on stop size.

Implementation scope:
- Add `ORB_CONFIRMATION_MODEL`.
- Reuse/extend `FindFreshFvgRates()` for M1 context.
- Add live wait state:
  - breakout seen
  - imbalance wait started
  - imbalance found
  - entry opened
  - expired
- Add imbalance SL source.
- Add auto stop-size target integration.
- Add dashboard:
  - `CONF: OFF/FVG/1M-IMB`
  - `IMB SL: ON/OFF`
  - `IMB wait: N`
- Add audit:
  - `imbalance_wait_start`
  - `imbalance_found`
  - `imbalance_expired`
  - `imbalance_entry_opened`
  - `imbalance_sl_selected`

Default:
- OFF.

Exit criteria:
- Existing FVG filter still works.
- 1M imbalance mode is separate from FVG filter.
- Chart labels show:
  - ORB breakout time
  - imbalance confirmation time
  - actual entry time
  - SL source
  - target source

## Phase 5 - Daily Management Rules

Purpose: add discipline rules from discretionary ORB models.

Rules:
1. `MAX_TRADES_PER_DAY`
   - default 1.
   - optional 2.

2. `STOP_AFTER_GREEN_TRADE`
   - if first trade closes green, no more trades that session.

Implementation scope:
- Add daily PnL/result tracker.
- Add block event:
  - `daily_max_trades_block`
  - `daily_green_done_block`
- Ensure reset uses auto session day, not NY-only day.

Default:
- Existing one-trade behavior should stay.
- `STOP_AFTER_GREEN_TRADE` default OFF unless preset says otherwise.

Exit criteria:
- Rules are visible on dashboard.
- Audit shows why a later signal was blocked.

## Phase 6 - Premarket Bias / Liquidity Prep Filters

Purpose: optional advanced filters, not required for first implementation.

Candidate filters:
- previous day high/low
- overnight high/low
- session VWAP bias
- liquidity draw direction
- major news block

Implementation warning:
- Do not add these until phases 1-5 are stable.
- These can easily overfit or silently block good ORB trades.

Default:
- OFF.

Exit criteria:
- Each bias filter must produce visible reason labels and audit rows.
- No silent blocking.

## Validation Protocol For Every Phase

For every phase:

1. Compile:
   - `0 errors, 0 warnings`.

2. Baseline check:
   - With all new modes OFF, default output must match prior baseline as closely as possible.

3. Internal historical check:
   - Run 2W and 5W audit.
   - Confirm chart labels match obvious winners/losers.

4. Native MT5 validation:
   - Use `MT5_EVENT_VALIDATION_PIPELINE.md`.
   - Validate at least:
     - one winning event
     - one losing event
     - one edge-case same-bar event

5. Log/audit:
   - New mode name must appear in chart label and CSV/backtest rows.

6. Presets:
   - Existing presets must remain usable.
   - New experimental presets should go under:
     - `EaPresets/ORB15/Experimental/...`

## Recommended Implementation Order

Exact order:

1. Phase 0 - Baseline Lock
2. Phase 1 - Exit / SL Engine
3. Phase 2 - Target Engine
4. Phase 3 - Pullback Retest Entry
5. Phase 4 - 1M Imbalance Entry
6. Phase 5 - Daily Management Rules
7. Phase 6 - Premarket Bias / Liquidity Prep

Do not implement phases 3 or 4 before phase 1 and 2 are stable. Entry experiments are not useful if exit/target accounting is still unstable.

