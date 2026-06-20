# ORB Phase 0 Baseline Lock

Date: 2026-06-19

EA: `IndicatorCodeExamples/RealOrbStrategy.mq5`

Build at lock time:
- `2026-06-19.v4.2-phase0-baseline-lock`

Purpose:
- Freeze the current working ORB behavior before adding the Phase 1 exit/SL engine.
- Any later feature must be opt-in and must not change this baseline when disabled.

## Baseline Defaults

Entry:
- Mode: breakout close.
- Signal timeframe: `PERIOD_M15`.
- Closed-bar breakout: enabled.
- Confirmation delay: `InpBreakoutDelayMinutes=5`.
- Confirmation bars: `InpConfirmBars=1`.

Session:
- Auto session by symbol: enabled.
- Session profile: `ORB_SESSION_AUTO`.
- Broker GMT offset: `0.0`.
- US symbols use NY open `09:30-09:45`.
- EU symbols use CET/CEST open `09:00-09:15`.
- UK symbols use London open `08:00-08:15`.
- HK symbols use HKT open `09:30-09:45`.
- JP symbols use JST open `09:00-09:15`.

Initial SL:
- Source: ORB opposite side.
- BUY: ORB low side.
- SELL: ORB high side.
- `InpSlDistancePct=100`.
- `InpSlBufferPoints=0`.

Target:
- Mode: fixed R leg.
- Target leg default: `ORB_TARGET_TP4`.
- TP values:
  - TP1 `0.5R`
  - TP2 `1.0R`
  - TP3 `1.5R`
  - TP4 `2.0R`
  - TP5 `2.5R`
  - TP6 `3.0R`

Position management:
- Execution mode: single position.
- HC/BE default: OFF.
- Legacy BE-on-TP1 default: OFF.
- Time/progress exit default: ON.
- TP touch close watchdog: ON.

Filters:
- ATR range filter: ON.
- Volume filter: ON.
- Day filter: OFF.
- Displacement filter: OFF.
- FVG mode: OFF.

Risk:
- Auto risk lot: ON.
- Risk per trade: `1.0%`.
- Account risk engine: ON.
- Daily loss limit: `0.0` by default.
- Max drawdown limit: `0.0` by default.
- Max margin usage: `40.0%`.

Historical chart/audit:
- Historical signal drawing: ON.
- Default historical window: `5W`.
- Runtime audit CSV: OFF by default.
- Tester trade audit CSV: OFF by default.

Internal backtest defaults:
- Fill mode: `BT_FILL_NEXT_BAR_OPEN`.
- Same-bar policy: `BT_SAMEBAR_CONSERVATIVE`.
- Tick replay: ON.
- Spread `0` means live spread.

## Phase 0 Code Adjustments

Only cosmetic / safety baseline adjustments were allowed:
- Dashboard shell widened from `520` to `620` to prevent current and future controls from crowding.
- Dashboard title now displays `ORB15 COCKPIT // <build>` instead of stale `v3.7`.

No entry math, stop math, target math, or risk math was intentionally changed in Phase 0.

## Required Checks Before Phase 1

1. Compile:
   - Status: passed.
   - Result: `0 errors, 0 warnings`.
   - Compile log: `logs/compile_RealOrbStrategy.mq5.log`.

2. Default behavior:
   - New Phase 1+ features must be OFF by default.
   - Baseline entry must remain breakout close.
   - Baseline SL must remain ORB opposite side.
   - Baseline target must remain fixed R leg.

3. Visual:
   - Dashboard must load.
   - Session label must be visible.
   - Historical signals must render when enabled.
   - Phase 0 code widened the dashboard shell to reduce crowding.

4. Backtest:
   - Internal backtest engine must remain runnable.
   - Native MT5 validation path must remain compatible with `MT5_EVENT_VALIDATION_PIPELINE.md`.

## Notes For Future AI

- Do not implement Phase 1 until this file and `ORB_IMPLEMENTATION_ROADMAP.md` are read.
- If default results change after a new feature is added, first check whether a new runtime default was accidentally enabled.
- Keep all new modes behind explicit enum/input/dashboard toggles.
