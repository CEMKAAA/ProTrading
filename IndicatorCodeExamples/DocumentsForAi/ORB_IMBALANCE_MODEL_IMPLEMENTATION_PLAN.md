# 15m ORB + 1m Imbalance Model Implementation Plan

Purpose: implement an optional professional ORB + imbalance confirmation model inspired by discretionary ORB traders:
- Mark ORH/ORL.
- Wait for clean breakout close.
- Confirm with 1-minute imbalance/FVG in breakout direction.
- Enter on imbalance confirmation.
- Stop below/above imbalance.
- Target 1R-2R depending on stop size.

Default behavior must remain unchanged:
- Existing ORB entry remains default.
- Imbalance model is opt-in.

## What We Already Have

Existing ORB EA has:
- ORH/ORL detection.
- Breakout close detection.
- 3-candle FVG/imbalance-like detection via `FindFreshFvgRates()`.
- `FVG: OFF/OPT/REQ` dashboard mode.
- SL/TP R legs.
- Risk engine.
- Internal backtest and historical chart labels.

What is missing compared to the trader's model:
- Dedicated 1-minute imbalance confirmation after 15m ORB breakout.
- SL based on imbalance high/low.
- Adaptive target: stop size small => 2R, stop size large => 1R.
- Premarket bias/liquidity prep:
  - previous day high/low
  - overnight high/low
  - session bias
  - next liquidity draw
  - major news filter
- “If first trade green, done” rule.
- “1 trade per day, 2 max” rule as a clear configurable risk rule.

## New Mode

```mql5
enum ORB_CONFIRMATION_MODEL
{
   ORB_CONFIRM_NONE=0,
   ORB_CONFIRM_FVG_FILTER=1,
   ORB_CONFIRM_1M_IMBALANCE_ENTRY=2
};
```

Inputs:

```mql5
input ORB_CONFIRMATION_MODEL InpConfirmationModel = ORB_CONFIRM_NONE;
input ENUM_TIMEFRAMES InpImbalanceTf = PERIOD_M1;
input int    InpImbalanceMaxWaitBars = 12;
input double InpMinImbalanceGapPts = 0.0;
input bool   InpImbalanceRequireCloseOutsideRange = true;
input bool   InpUseImbalanceStop = true;
input double InpImbalanceStopBufferPts = 2.0;
input double InpSmallStopThresholdPts = 30.0;
input double InpSmallStopTargetR = 2.0;
input double InpLargeStopTargetR = 1.0;
input int    InpMaxTradesPerDay = 1;
input bool   InpStopAfterGreenTrade = true;
```

## Imbalance Definition

Use the existing 3-candle FVG model:

BUY imbalance:
- candle3.low > candle1.high
- gap size >= minimum points
- middle candle should ideally be displacement candle, but default should not be too strict.

SELL imbalance:
- candle1.low > candle3.high
- gap size >= minimum points.

## Entry Flow

### Long

1. 15m ORB completes.
2. 15m or selected signal TF closes above ORH.
3. Start imbalance wait window on M1.
4. Find bullish 3-candle imbalance.
5. If `InpImbalanceRequireCloseOutsideRange=true`, imbalance confirmation close must remain above ORH.
6. Entry at confirmation close/next open.
7. SL:
   - if `InpUseImbalanceStop=true`, SL below imbalance low minus buffer.
   - otherwise use ORB opposite-side SL.
8. Target:
   - if stop size <= threshold => target 2R.
   - if stop size > threshold => target 1R.

### Short

1. Break below ORL.
2. Wait for bearish M1 imbalance.
3. Entry after confirmation.
4. SL above imbalance high plus buffer.
5. Target 1R/2R according to stop size.

## Bias / Premarket Prep Layer

Add later as optional filters, not part of first implementation:

```mql5
input bool InpUsePreviousDayLevelsBias = false;
input bool InpUseOvernightLevelsBias = false;
input bool InpUseLiquidityDrawBias = false;
input bool InpUseNewsBlock = false;
```

Definitions:
- Previous day high/low from D1.
- Overnight high/low should be symbol/session-specific.
- Bias:
  - bullish if premarket holds above VWAP and targets prior high/overnight high.
  - bearish if below VWAP and targets prior low/overnight low.

Do not hardcode discretionary bias at first. Keep it measurable.

## Existing FVG Mode vs New Imbalance Model

Important distinction:

- Existing `FVG:REQ` is a filter:
  - ORB breakout is still the entry.
  - FVG is only confirmation/filter.

- New `1M_IMBALANCE_ENTRY` is an entry model:
  - breakout starts the setup.
  - actual trade entry waits for imbalance confirmation.
  - SL can be the imbalance low/high.

This distinction must be reflected in audit and dashboard.

## Dashboard

Add:
- `CONF: OFF/FVG/1M-IMB`
- `IMB wait: N`
- `IMB SL: ON/OFF`
- `Target: AUTO 1R/2R`
- `Daily max: 1/2`
- `Green done: ON/OFF`

Historical labels:
- show ORB breakout marker.
- show imbalance confirmation marker.
- show SL source: `SL=IMB` or `SL=ORB`.
- show target source: `TP=AUTO_1R/2R`.

## Backtest Integration

Backtest combo expansion:
- confirmation model
- imbalance wait bars
- imbalance stop on/off
- target auto on/off
- small-stop threshold
- max trades/day
- stop-after-green

CSV columns:
- `confirmation_model`
- `imbalance_tf`
- `imbalance_wait_bars`
- `sl_source`
- `stop_size_pts`
- `target_r`
- `max_trades_per_day`
- `stop_after_green`
- `breakout_time`
- `imbalance_time`
- `entry_time`

## Audit Events

Live:
- `orb_breakout_seen`
- `imbalance_wait_start`
- `imbalance_found`
- `imbalance_expired`
- `imbalance_entry_opened`
- `imbalance_sl_selected`
- `auto_target_selected`
- `daily_green_stop`
- `daily_max_trade_stop`

Backtest:
- same events should be counted in result rows.

## Risk Controls

- Lot size must be calculated from actual SL distance.
- If imbalance SL is very tight, enforce broker stop-level.
- If imbalance SL is too tight and invalid, either:
  - expand to minimum broker-safe distance, or
  - fall back to ORB SL depending input.

Recommended input:

```mql5
input bool InpFallbackToOrbSlIfImbalanceSlInvalid = true;
```

## Implementation Order

1. Add enum/input/dashboard only, default OFF.
2. Implement 1M imbalance scanner using existing FVG logic but on M1.
3. Add live state machine.
4. Add historical simulation path.
5. Add chart labels for breakout vs imbalance entry.
6. Add backtest combo columns.
7. Validate with native MT5 event windows.

