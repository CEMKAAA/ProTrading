# Campaign Failure Investigation

Investigated on 2026-10-10 while the campaign coordinator remained running.
No production source, saved strategy, campaign wrapper, or original archive was
modified. No corrected native rerun has been completed in this investigation.

## 1. Signal history origin changes during an audit

`btcusd0.10R` has identical settings keys but different 260W results:

| Load path | Trades | Wins | Losses | Net R |
| --- | ---: | ---: | ---: | ---: |
| Campaign | 7498 | 6800 | 698 | -196.14887 |
| Dashboard | 6652 | 6011 | 641 | -200.71052 |

Worker `MQL5/Logs/20261009.log`, starting at lines 16013 and 16093, records:

- First 260W kernel: seed `2021.10.08 03:55`, 525581 bars, 26937 raw events.
- Following window: seed changed to `2020.05.19 00:00`.
- Dashboard 260W kernel: that earlier seed, 671633 bars, 16965 raw events.
- NAS series, settings key, endpoint and saved strategy are unchanged.

`MaCrossSignalCore.mqh:57` uses the currently loaded `SERIES_FIRSTDATE` as the
recursive kernel origin. `MaCrossAuditCache.mqh:79` requests bars only from
that origin. Existing coverage checks cover the audit window plus warmup;
macro preflight synchronizes D1/H1/H2/H4, not the complete signal origin.
Consequently, synchronizing more old signal bars later changes the kernel
origin and state. Synchronization of a loaded suffix is not proof that the
complete reproducible prefix has been loaded.

The same issue appeared in `usdjpy0.05TenderIq` and `usdjpy0.02TenderIq`.
Both paths initially matched at 260W with an M15 seed in September 2021.
During the dashboard run the seed moved to September 2019, changing the
shorter-window signals. This also shows why two matching 5Y totals alone
are not sufficient proof of stable history across subsequent windows.

Required correction: establish the reproducible signal/HTF history prefix
before constructing recursive kernels; verify that prefix remains unchanged
through calculation and before publication. If it changes, discard and rebuild
the calculation, rather than publishing a completed result from an old prefix.
Both native load paths must then match their complete trade traces.

## 2. M15 initial replay horizon stops at the fill boundary

`0.33InvUltimateSetup` is an ORB M15, inverse, fixed-target strategy. Its
260W audit recorded 525 DATA trades and zero visited ticks; its 2W audit
recorded four DATA trades. These results must not be represented as zero trades.

The legacy lifecycle in `orb/OrbUltimateEA_StrategyLibrary.mq5:5900` starts
with `entryTime + 15 minutes`. The tick simulator at line 5230 rejects any
interval whose end is not later than the signal candle's closing time.
For M15 the two times are identical. Therefore it returns before reading ticks.
The inverse path subsequently reports `INVERSE_TICKS_REQUIRED`, and the
expansion loop cannot continue because the initial result is invalid.

The same initial-horizon pattern exists in MaCross and EntryLab. M30/H1
also hit the boundary in this path. Non-inverse calculation can incorrectly
take its OHLC fallback despite available ticks. ADV uses its own larger
horizon, but can reach this defective legacy path when falling back.

A read-only SDK query to the already running DEMO terminal returned JP225m
bid/ask ticks for `2026-09-25 19:46:57 UTC` and `2026-10-08 00:00:00 UTC`.
Those samples do not prove full multi-year tick coverage, but the unconditional
pre-read rejection is a code defect independent of actual tick availability.

Required correction: anchor initial replay prefetch after the actual earliest
fill time, keeping the audit endpoint and any forced-exit bounds intact.
Do not restore the larger arbitrary one-hour prefetch or fabricate OHLC exits.
Test M1/M5/M15/M30/H1, normal/inverse, and ADV fallback with exact native traces.
Genuinely absent old ticks must still remain DATA after this correction.

## Publication And Next Verification

- PARITY_MISMATCH rows were withheld; their counts were not silently repaired.
- The campaign was not stopped or recompiled mid-run.
- The immutable original campaign remains unchanged.
- `failure-investigation.json` preserves compared rows, source hash, log
  evidence and the exact initial-horizon boundary checks.
- Apply and verify production changes at a safe source-version boundary.
  Recalculate affected windows using the unchanged saved settings and endpoint.
  Do not seal MEGA 2 while a real parity failure remains unresolved.
