# ORB Exit Engine Implementation Plan

Purpose: extend `RealOrbStrategy.mq5` with multiple professional ORB stop/exit models without changing the existing breakout entry math by default.

Default behavior must remain unchanged:
- `ExitEngineMode = FIXED_TARGET`
- `Partial close = OFF`
- `HC/BE = OFF unless explicitly selected`
- Existing opposite-side ORB SL remains the baseline initial SL.

## Current ORB Features Already Present

- Opening range opposite-side stop:
  - BUY uses ORB low side as raw SL.
  - SELL uses ORB high side as raw SL.
  - `InpSlDistancePct` can scale this distance.

- Range/R target legs:
  - `InpTp1R` through `InpTp6R`.
  - `InpTargetTpLeg`.
  - Current default target can be TP4 = 2R.

- Time/progress exit:
  - `InpUseTimeExit`.
  - `InpTimeExitMinutes`.
  - `InpTimeExitMinProgress`.

- HC/BE:
  - Present, but should remain optional.
  - User preference: full-lot runner is preferred; do not default to HC.

- FVG/imbalance-style filter:
  - `InpFvgMode`.
  - `FindFreshFvgRates()`.
  - This detects a 3-candle gap and can filter entries.

## New Exit Modes

Add enum:

```mql5
enum ORB_EXIT_ENGINE_MODE
{
   ORB_EXIT_FIXED_TARGET=0,
   ORB_EXIT_EOD_ONLY=1,
   ORB_EXIT_ORB_MID_INVALIDATION=2,
   ORB_EXIT_ATR_TRAIL=3,
   ORB_EXIT_EMA_TRAIL=4,
   ORB_EXIT_VWAP_STOP=5
};
```

Inputs:

```mql5
input ORB_EXIT_ENGINE_MODE InpExitEngineMode = ORB_EXIT_FIXED_TARGET;
input bool   InpExitKeepCatastrophicSl = true;
input bool   InpExitCloseAtEod = true;
input int    InpExitTrailStartLeg = 0;        // 0 = immediate/always, 1..6 = start after TP leg touched
input int    InpExitAtrPeriod = 14;
input double InpExitAtrMultiplier = 2.0;
input int    InpExitEmaPeriod = 50;           // allow 50/100 from dashboard
input bool   InpExitUseSessionVwap = true;
input int    InpExitVwapGraceBars = 1;
input int    InpExitMidpointGraceBars = 1;
```

Runtime variables:

```mql5
ORB_EXIT_ENGINE_MODE g_rtExitMode;
int    g_rtExitTrailStartLeg;
int    g_rtExitEmaPeriod;
double g_rtExitAtrMultiplier;
```

## Mode Rules

### 1. Fixed Target

Existing behavior:
- Open full position.
- TP is selected target leg.
- Initial SL is ORB opposite side, scaled by `InpSlDistancePct`.
- Optional HC/BE remains available but default OFF.

### 2. EOD Only + Catastrophic Stop

Purpose: catch full-day runners.

Rules:
- Place initial catastrophic SL at ORB opposite side or scaled ORB side.
- No fixed TP.
- Close at session trade end.
- Optional time/progress exit can still close earlier if enabled.

Implementation:
- If mode is `ORB_EXIT_EOD_ONLY`, pass TP=0 to order send or keep a far target disabled by broker-safe logic.
- `ManagePositions()` closes own positions at `g_tradeEndServer`.

Audit fields:
- `exit_mode=eod_only`
- `catastrophic_sl=...`
- `eod_close=1`

### 3. ORB Midpoint Invalidation

Purpose: early-cut failed breakouts before full SL.

Rules:
- BUY exits if price closes below ORB midpoint after breakout.
- SELL exits if price closes above ORB midpoint after breakout.
- Use closed bars to avoid tick noise.
- Optional grace bars after entry.
- Catastrophic SL remains active.

Implementation:
- Add `OrbMidpoint()` helper.
- In `ManagePositions()`, check latest closed signal TF bar close.
- Do not close on the entry bar unless `InpExitMidpointGraceBars=0`.

Historical simulation:
- At each simulated bar/tick, if midpoint close invalidation occurs before TP/SL, set outcome `ORB_MID_EXIT`.
- Compute netR based on exit price.

### 4. ATR / Chandelier Trail

Purpose: preserve breakout runner while adapting to volatility.

Rules:
- BUY trail = highest high since entry - ATR * multiplier.
- SELL trail = lowest low since entry + ATR * multiplier.
- Trail starts only after selected `InpExitTrailStartLeg`, unless 0.
- Never loosen SL.
- Catastrophic SL remains initial floor/ceiling.

Implementation:
- Store `g_tradeBestHigh`, `g_tradeBestLow`.
- Update on every tick/bar.
- Use ATR on `g_rtSignalTf` or M5/M15; default should be signal TF.
- Modify SL only if broker stop-level allows.

Audit:
- `atr_trail_update`
- fields: `best_high`, `best_low`, `atr`, `mult`, `old_sl`, `new_sl`, `start_leg`.

### 5. EMA 50/100 Dynamic Stop

Purpose: trend-following dynamic exit.

Rules:
- BUY exits if closed candle closes below EMA.
- SELL exits if closed candle closes above EMA.
- EMA period dashboard-selectable: 50 or 100.
- Optional start after TP leg.

Implementation:
- `iMA(_Symbol, g_rtSignalTf, g_rtExitEmaPeriod, 0, MODE_EMA, PRICE_CLOSE)`.
- Use closed bar index 1.
- Do not evaluate before trail start leg is reached.

Historical simulation:
- Load EMA buffer or compute EMA manually for test bars.
- If unavailable, skip EMA mode in historical audit with `ema_unavailable`.

### 6. VWAP / Session VWAP Dynamic Stop

Purpose: intraday institutional benchmark invalidation.

Rules:
- Compute session VWAP from session start to current time.
- BUY exits if closed bar closes below VWAP after grace.
- SELL exits if closed bar closes above VWAP after grace.
- Optional start after TP leg.

Implementation:
- Add `SessionVwap(datetime from, datetime to, ENUM_TIMEFRAMES tf)` using typical price * tick volume.
- For live, recompute incrementally/cached per bar to avoid heavy loops.
- For historical, compute per simulated bar from ORB/session start.

Audit:
- `vwap_exit`
- fields: `vwap`, `close`, `grace_bars`, `start_leg`.

## Dashboard Requirements

Add buttons:
- `EXIT: FIXED/EOD/MID/ATR/EMA/VWAP`
- `TRAIL@ OFF/TP1/TP2/TP3/TP4/TP5/TP6`
- `EMA 50/100`
- `ATR x 1.5/2.0/2.5/3.0`

Dashboard result/audit must include:
- Exit mode.
- Start leg.
- Average winner R.
- Average loser R.
- Full-SL count.
- Early-exit count.
- Runner-to-EOD count.

## Internal Backtest Integration

Expand `OrbBtCombo`:

```mql5
int exitMode;
int trailStartLeg;
int emaPeriod;
double atrMultiplier;
```

Backtest output columns:
- `exit_mode`
- `trail_start_leg`
- `ema_period`
- `atr_multiplier`
- `early_exit_count`
- `eod_exit_count`
- `full_sl_count`
- `avg_win_r`
- `avg_loss_r`
- `max_win_r`
- `max_loss_r`

Important:
- Existing mode must still match previous output when `exit_mode=FIXED_TARGET`.
- Do not let dynamic exits alter entry timing.

## Native MT5 Validation

Use `DocumentsForAi/MT5_EVENT_VALIDATION_PIPELINE.md`.

Validate sample windows:
- Best internal combo.
- Worst trade.
- Random distant trades.
- Same-bar edge cases.
- One US index, one EU index, one Asia index.

## Risk Notes

- Catastrophic SL must not increase money risk. Lot engine must still size by actual initial SL distance.
- If dynamic exit closes earlier, realized loss can be less than 1R.
- Do not tighten initial SL to satisfy risk. Adjust lot only.

