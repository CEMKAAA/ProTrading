# ORB Pullback Retest Mode Implementation Plan

Purpose: add an optional ORB entry mode based on breakout, pullback to breakout level, and continuation. This comes from the practical observation that legitimate breakouts often retest the old range boundary, but not always.

Default behavior must remain unchanged:
- `EntryMode = BREAKOUT_CLOSE`
- Pullback retest mode OFF.

## Concept

Normal ORB entry:
- Mark ORH/ORL.
- Enter when price closes above ORH or below ORL.

Pullback retest entry:
- Detect valid breakout close.
- Wait for price to pull back near breakout level.
- Enter only if price rejects that level and moves again in breakout direction.

This may reduce false breakouts but will miss some strong no-pullback runners.

## New Enum

```mql5
enum ORB_ENTRY_MODE
{
   ORB_ENTRY_BREAKOUT_CLOSE=0,
   ORB_ENTRY_PULLBACK_RETEST=1,
   ORB_ENTRY_BREAKOUT_OR_RETEST=2
};
```

Inputs:

```mql5
input ORB_ENTRY_MODE InpEntryMode = ORB_ENTRY_BREAKOUT_CLOSE;
input int    InpRetestMaxWaitBars = 12;
input double InpRetestTolerancePts = 0.0;
input int    InpRetestConfirmBars = 1;
input bool   InpRetestRequireCloseBackInDirection = true;
input bool   InpRetestUseBreakoutLevelStop = false;
```

Runtime:

```mql5
ORB_ENTRY_MODE g_rtEntryMode;
datetime g_pendingBreakoutTime;
string   g_pendingBreakoutDir;
double   g_pendingBreakoutLevel;
int      g_pendingBreakoutBarsWaited;
```

## BUY Retest Rules

1. Breakout close above ORH.
2. Retest condition:
   - low touches ORH +/- tolerance, or close returns near ORH.
3. Rejection/confirmation:
   - close back above ORH, or bullish close after retest.
4. Entry:
   - enter on confirmation close or next bar open depending current fill mode.
5. SL:
   - default still ORB low/catastrophic SL.
   - optional tighter SL under retest swing low can be added later.

## SELL Retest Rules

1. Breakout close below ORL.
2. Retest condition:
   - high touches ORL +/- tolerance.
3. Rejection/confirmation:
   - close back below ORL, or bearish close after retest.
4. Entry:
   - enter on confirmation.
5. SL:
   - default ORB high/catastrophic SL.

## State Machine

States:
- `NONE`
- `BREAKOUT_SEEN`
- `RETEST_SEEN`
- `CONFIRMED`
- `EXPIRED`

Live implementation:
- `ComputeSignal()` should branch by entry mode.
- For `BREAKOUT_CLOSE`, keep current behavior.
- For `PULLBACK_RETEST`, do not open at first breakout; create pending state.
- Expire pending setup after `InpRetestMaxWaitBars`.
- If opposite breakout appears before retest, reset state.

Historical implementation:
- Add `FindHistPullbackRetest()` separate from `FindHistBreakout()`.
- Do not contaminate existing breakout-close results.

Backtest combo expansion:
- `entry_mode`
- `retest_wait_bars`
- `retest_tolerance_pts`

Dashboard:
- `ENTRY: BRK / RETEST / BOTH`
- `RT wait: N`
- `RT tol: pts`

Audit:
- `breakout_seen`
- `retest_seen`
- `retest_confirmed`
- `retest_expired`
- `retest_opposite_reset`

## Risks

- Retest mode will miss high-momentum runners.
- Retest mode can improve fill and reduce false breakouts.
- It should be tested separately from FVG mode; do not combine everything by default.

