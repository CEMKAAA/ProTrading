# ORB Stop / Target Mode Matrix

This document is a compact checklist for ORB stop and target modes to avoid mixing concepts.

## Stop Modes

### 1. ORB Opposite Side Stop

Status: already mostly implemented.

BUY:
- SL below ORB low.

SELL:
- SL above ORB high.

Inputs already present:
- `InpSlBufferPoints`
- `InpSlDistancePct`

Use case:
- Baseline ORB model.

Risk:
- If ORB range is wide, lot must shrink.

### 2. ORB Midpoint Invalidation

Status: not implemented as exit engine.

BUY:
- Exit if closed candle returns below ORB midpoint.

SELL:
- Exit if closed candle returns above ORB midpoint.

Use case:
- Early failed-breakout exit.

Risk:
- Can cut valid retests.

### 3. ATR / Volatility Stop

Status: ATR filter exists, ATR trailing exit not implemented.

Variants:
- Initial ATR SL.
- ATR Chandelier trail.

Recommended:
- Keep ORB initial catastrophic SL.
- Add ATR trail after selected TP leg or after minimum progress.

### 4. EMA 50/100 Dynamic Stop

Status: not implemented.

BUY:
- Exit if close below EMA50/EMA100.

SELL:
- Exit if close above EMA50/EMA100.

Use case:
- Trend-following runner management.

### 5. VWAP / Session VWAP Stop

Status: not implemented.

BUY:
- Exit if close below session VWAP.

SELL:
- Exit if close above session VWAP.

Use case:
- Intraday benchmark invalidation.

## Target Modes

### 1. Fixed R Target

Status: implemented through TP1..TP6.

Example:
- TP4 = 2R.
- TP6 = 3R.

### 2. Range-Height Target

Status: not explicitly implemented.

Rule:
- target distance = ORB high - ORB low.

Implementation:
- Add target mode:

```mql5
enum ORB_TARGET_MODE
{
   ORB_TARGET_R_LEG=0,
   ORB_TARGET_RANGE_HEIGHT=1,
   ORB_TARGET_EOD=2,
   ORB_TARGET_AUTO_STOP_SIZE=3
};
```

When `RANGE_HEIGHT`:
- BUY TP = entry + ORB range * multiplier.
- SELL TP = entry - ORB range * multiplier.

Input:

```mql5
input double InpRangeTargetMultiplier = 1.0;
```

### 3. EOD Target

Status: time exit exists, but not as dedicated target mode.

Rule:
- no fixed TP.
- close at session end.

### 4. Auto Stop-Size Target

Status: not implemented.

Rule from trader model:
- if stop size is small, target 2R.
- if stop size is large, target 1R.

Inputs:

```mql5
input double InpSmallStopThresholdPts = 30.0;
input double InpSmallStopTargetR = 2.0;
input double InpLargeStopTargetR = 1.0;
```

## Recommended Test Sets

Minimal useful combinations:

1. Baseline:
   - Stop: ORB opposite side
   - Target: fixed 2R
   - HC: OFF

2. Runner:
   - Stop: ORB opposite side
   - Target: EOD
   - Dynamic exit: VWAP or ATR trail
   - HC: OFF

3. Fast invalidation:
   - Stop: ORB opposite side catastrophic
   - Dynamic exit: ORB midpoint
   - Target: fixed 2R or EOD

4. Trader imbalance model:
   - Entry: ORB + 1M imbalance
   - Stop: imbalance low/high
   - Target: auto 1R/2R

