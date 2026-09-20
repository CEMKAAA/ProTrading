# MaCross order-flow confirmation: implementation and release gate

Date: 2026-09-20

## Status

Workspace integration, default OFF. NOT released to live terminals.
This is a bid-quote-activity proxy, not exchange aggressor volume, DOM,
market depth, or identification of institutional traders. No profitability claim.
Native exchange trade-volume/BUY/SELL support is not implemented in this version.

## Research and deliberate differences

- Reference: https://github.com/srlcarlg/srl-ctrader-indicators
- Reviewed computational sections of `Order Flow Ticks v2.0.cs` and
  `Free Volume Profile v2.0.cs`, plus repository README/license. Not a claim
  of a line-by-line audit of every indicator in the repository.
- The tick indicator classifies price changes; it is not necessarily reading
  exchange aggressor prints. Its `RankVolume` implementation adds cumulative
  up-minus-down counters to DeltaRank on successive observations. Repeating
  that in our filter would count prior directional events multiple times.
- We count each qualifying BID update once. Equal prices are neutral, not
  counted once as a buy AND once as a sell. Ask-only ticks are excluded.
- The reference value-area routine uses grouped adjacent levels and special
  fallbacks. Ours is an explicitly defined contiguous single-row expansion
  from POC, choosing greater adjacent activity and both sides on a tie.
  This is conceptually related, NOT an exact numerical port of its plots.
- No third-party source was copied into the new implementation.
- `OrderflowBarStatistics.pine` has a noncommercial license; it is not copied.
  `VolumeFootprint.pine` estimates allocation from lower-timeframe bars; that
  is not substituted for missing ticks in this implementation.

Official data contracts:
https://www.mql5.com/en/docs/series/copyticksrange
https://www.mql5.com/en/docs/constants/structures/mqltick

`CopyTicksRange` may return a positive count with a history timeout error.
Both the returned data AND GetLastError must be checked.

## Deterministic calculation

For a completed signal candle T:

1. Take N preceding completed signal-timeframe candles, excluding T.
2. Bin their bid updates across the reference low/high; one observation per bin.
3. POC is the maximum-count row; ties use the lower row.
4. Expand contiguously until the configured fraction of activity is enclosed.
   VAL/VAH are row edges. Default fraction: 0.70.
5. On T only, classify each bid update by comparison with the preceding bid.
   Delta = (up - down) / (up + down + neutral).
6. Activity ratio = T's bid-update count / mean reference-candle count.
7. Test the EFFECTIVE execution direction, including full inversion.

Buy acceptance requires activity >= threshold and delta >= threshold, plus:

- BREAKOUT: close > VAH.
- REJECTION: low < VAL and VAL <= close <= VAH.
- EITHER: one of those conditions.

Sell is symmetric. BREAKOUT is acceptance outside value, not a requirement
to cross the boundary for the first time on T. This filters an existing MA
setup; it does not generate its own setup or use future retests.

Defaults: OFF, N=24, bins=32, value area=0.70, activity=1.0, delta=0.10.
These are research starting values, not optimized or validated winning settings.

## Integration

- `macrossover_orb/MaCrossOrderFlowCore.mqh`: pure profile/delta/rules.
- `macrossover_orb/MaCrossOrderFlow.mqh`: data adapter, bounded snapshot cache,
  settings, diagnostic reasons.
- `macrossover_orb/MaCrossOrderFlowWorker.mq5`: private indicator worker. Compile
  this indicator alongside the EA in the same directory. It is loaded by iCustom,
  not attached manually to a chart. Three separate mailboxes isolate live entry,
  audit preparation, and legacy filtered-reverse reconstruction.
- `ModernFilterAllows` is shared by live, historical and filtered reverse
  candidate construction. Pine signal kernels remain unchanged.
- Dashboard header button cycles OFF / BREAK / REJECT / EITHER.
- Other settings are in EA Inputs, under ORDER FLOW; not editable text fields
  on the dashboard yet. Save the strategy to persist the runtime mode.
- `MAOF1` metadata saves all six settings. Old records load OFF.
- Audit/metric and pending-NAS identities include enabled OF settings.
- Toggle changes cancel pending NAS/retest/imbalance entries, not positions.
- An OF-rejected setup cannot create a filtered-window exit event. The filter
  itself does not change stops, targets or emit closes. Normal admitted reverse
  signals still obey the existing reverse-exit policy.
- No listener source files or CSV schemas changed. Entry publication remains
  downstream of the shared acceptance chain.

## Missing data and performance limits

- Requires synchronized series and complete closed-bar context.
- Bid-update counts must exactly match each reference and signal candle's
  tick_volume. A broker with different volume semantics is NOT silently adapted;
  it is reported unsupported/incomplete until investigated.
- Out-of-order ticks, inconsistent price ranges, any tick retrieval error and
  missing coverage block the candidate. There is no OHLC fallback.
- Audit PREP waits on the current candidate instead of advancing and treating
  unavailable data as a rejected setup. On timeout/error it aborts with
  INCOMPLETE ORDER FLOW, clears current counters, and does not persist metrics.
- The live path keeps a pending latest closed candle retryable. Once the next
  closed candle arrives, the old request cannot reappear as a late entry.
- Preparation memo reuse is deliberately disabled when OF is enabled until
  a robust tick-history revision key exists. OFF retains previous memo behavior.
- Snapshot cache is bounded to 256 entries. Reference work is limited to
  128 bars and 250,000 expected bid updates per request.
- The EA adapter no longer calls CopyRates/CopyTicks/CopyTicksRange. Indicator
  context uses CopyTicks with a bounded request (maximum 500,000 observations),
  whose documented indicator semantics are immediate return with background
  synchronization. Full per-bar validation remains mandatory. Extra ticks after
  the signal candle are ignored by the pure calculation.
- Requests have a 30-second worker deadline and a 35-second EA watchdog. Worker
  responses commit the requested candle timestamp last. Unique per-chart,
  per-lane, per-worker-lifetime temporary globals prevent cross-chart results.
  Old/mismatched responses cannot validate a new request. No trade APIs exist
  in the worker.
- This is not a constant-time guarantee: copying/processing up to the configured
  data budget still consumes CPU, and indicators for a symbol share a thread.
- No 5Y benchmark or claim of complete five-year tick history has been made.

## Validation

Commands:

```powershell
& scripts/validate_ma_exit_policy.ps1 -RunProbes
& scripts/validate_ma_orderflow.ps1 -RunProbe
& scripts/validate_ma_orderflow.ps1 -RunProbe -Feed
```

Tests use a separate test terminal with Experts disabled, not production charts.
Core tests cover mass conservation, deterministic value area, signal-candle
exclusion, future-tick exclusion, buy/sell symmetry, neutral/ask-only handling,
incomplete history, malformed config, and settings roundtrip. Integration tests
cover effective inverted direction, unchanged OFF gate, preset restoration,
pending-config identity, and OF rejection not becoming a window exit.

2026-09-20 feed diagnostic:

- JP225m M5 bars were available, but SERIES_SYNCHRONIZED was false in the worker.
- Production adapter blocked all three requests with OF_DATA_BARS.
- Separate offline diagnostic returned 2,936 ticks AND error 4403. These partial
  ticks were rejected, not used to report a valid profile or a tradable setup.
- Successful synchronized broker-data parity and paper-forward checks remain
  required beyond the single-candle check below. No live trading or production
  deployment was performed.

Asynchronous follow-up:

- `.tmp/ma_orderflow_20260920_203049`: ready after 1,235 ms / 12 polls;
  maximum EA polling call 16 ms.
- `.tmp/ma_orderflow_20260920_203224`: timeout after 35,125 ms / 319 polls;
  maximum EA polling call 31 ms. This run used CopyTicksRange in the worker.
- Worker changed to explicitly documented indicator CopyTicks semantics.
- `.tmp/ma_orderflow_20260920_203357`: ready after 2,203 ms / 21 polls;
  maximum EA polling call 15 ms. 2,936 ticks, zero retrieval error, exact match
  between worker result and direct core on POC/VAL/VAH/delta/activity/count.
- That sample rejected a BUY: activity 0.3483, delta 0.0476. It is a data-path
  test, NOT evidence of profitability or successful end-to-end order execution.

Reference for indicator vs EA synchronization behavior:
https://www.mql5.com/en/docs/series/copyticks

## Before release

1. Soak-test the asynchronous worker in an actual EA chart, including dashboard
   interaction, simultaneous channels, disconnection and restoration.
2. Verify tick-volume semantics on each intended broker/symbol; only one recent
   JP225 candle currently has a successful real-data comparison.
3. Extend worker/direct parity from the checked candle to recorded tapes,
   multiple symbols, reloads, and longer historical windows.
4. Paper-run both accepted and rejected signals through NAT/PUB paths.
5. Benchmark cold/warm audits; verify UI responsiveness and incomplete retry.
6. Only then compare chronological holdout performance to OF-OFF strategies.
