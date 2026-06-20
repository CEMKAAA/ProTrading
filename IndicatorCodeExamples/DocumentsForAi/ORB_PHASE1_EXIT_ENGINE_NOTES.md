# ORB Phase 1 Exit Engine Notes

Date: 2026-06-19

EA: `IndicatorCodeExamples/RealOrbStrategy.mq5`

Build:
- `2026-06-19.v4.3-phase1-exit-engine`

## Implemented Modes

New enum:

```mql5
enum ORB_EXIT_ENGINE_MODE
{
   ORB_EXIT_FIXED_TARGET=0,
   ORB_EXIT_EOD_ONLY=1,
   ORB_EXIT_ORB_MID_INVALIDATION=2,
   ORB_EXIT_ATR_TRAIL=3,
   ORB_EXIT_EMA_STOP=4,
   ORB_EXIT_VWAP_STOP=5
};
```

Default:
- `ORB_EXIT_FIXED_TARGET`

This preserves Phase 0 baseline by default.

## Mode Behavior

### EXIT:FIXED

- Existing behavior.
- Opens with selected fixed TP leg.
- Uses ORB opposite-side SL.
- Dynamic exit engine does nothing.

### EXIT:EOD

- Opens with catastrophic ORB SL.
- Opens with `TP=0`.
- Closes at `g_tradeEndServer`.
- Partial 3-leg mode is blocked because EOD-only is incompatible with split fixed TP legs.

Audit events:
- `eod_exit`
- `exit_mode_block` if partial mode is selected.

### EXIT:MID

- Keeps fixed TP.
- Closes early if closed bar invalidates ORB midpoint:
  - BUY: close < ORB midpoint.
  - SELL: close > ORB midpoint.

Audit events:
- `orb_mid_exit`
- `dynamic_exit_probe`

### EXIT:ATR

- Keeps fixed TP.
- Chandelier-style SL trail:
  - BUY: best high since entry - ATR * multiplier.
  - SELL: best low since entry + ATR * multiplier.
- Never loosens SL.
- Uses broker stop-level checks before modify.

Audit events:
- `atr_trail_update`
- `atr_trail_deferred`
- `atr_trail_failed`

### EXIT:EMA

- Keeps fixed TP.
- Closes on closed-bar EMA invalidation:
  - BUY: close < EMA.
  - SELL: close > EMA.
- Runtime EMA period can be 50 or 100.

Audit events:
- `ema_exit`
- `dynamic_exit_probe`

### EXIT:VWAP

- Keeps fixed TP.
- Computes session VWAP from session/ORB start using M1 typical price * tick volume.
- Closes on closed-bar VWAP invalidation:
  - BUY: close < VWAP.
  - SELL: close > VWAP.

Audit events:
- `vwap_exit`
- `dynamic_exit_probe`

## Dashboard Controls

Added controls:
- `EXIT:*`
  - cycles `FIXED -> EOD -> MID -> ATR -> EMA -> VWAP`.
- `XS:*`
  - exit start leg.
  - `XS:NOW` means active immediately.
  - `XS:TPn` means dynamic exit starts after that TP leg has been touched.
- `ATR/EMA`
  - in EMA mode cycles EMA 50/100.
  - otherwise cycles ATR multiplier 1.5/2.0/2.5/3.0.

Dashboard debug labels include:
- `exit_mode`
- `startLeg`
- `atrX`
- `ema`

## Historical Chart Labels

Historical signal labels now include:
- exit mode label
- dynamic outcome:
  - `MID_EXIT`
  - `VWAP_EXIT`
  - `EMA_EXIT`
  - `EOD_EXIT`
  - existing `TPx`, `SL`, `BE`, `open`
- `exitPrice` is printed to Experts log for debugging.

## Internal Backtest

The brute-force internal backtest now includes `exit_mode`.

New column:
- `exit_mode`

Combo count changed:
- previous Phase 0 combo count: `256`
- Phase 1 combo count: `1536`
  - 6 exit modes * previous 256 combos.

Notes:
- Tick replay is preserved for `EXIT:FIXED`.
- Dynamic exit modes intentionally use bar-based closed-bar simulation because MID/EMA/VWAP decisions are close-based.

## Live Debugging Checklist

For each mode:

1. Enable `AUDIT`.
2. Select exit mode from dashboard.
3. Check chart label:
   - it must show `EXIT:*`.
4. Check CSV/Experts events:
   - `dynamic_exit_probe` for MID/EMA/VWAP when no exit.
   - `orb_mid_exit`, `ema_exit`, `vwap_exit`, or `eod_exit` when exit triggers.
   - `atr_trail_update` when ATR trail modifies SL.
5. Verify order TP:
   - FIXED/MID/ATR/EMA/VWAP should have fixed TP.
   - EOD should have TP=0.

## Known Boundaries

- Phase 1 does not implement new target modes. Range-height target and auto 1R/2R are Phase 2.
- Phase 1 does not implement retest entry. That is Phase 3.
- Phase 1 does not implement 1M imbalance entry. That is Phase 4.

