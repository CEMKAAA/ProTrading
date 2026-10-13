# Timed Reverse Exit: MaCross, Entry Lab, Sol Advanced

## Scope

Canonical sources only. No changes to ORB, signal generation, entry/SL/TP
geometry, strategy definitions, MEGA archives, listener protocols or native
order placement. No user terminal was stopped and no test submitted orders.
The existing isolated worker and fixed verification folders were reused.

## Reproduced Defects

- MaCross and Entry Lab: a 48-hour deadline in a weekend used a later opening
  price but recorded the Sunday deadline as the exit time. Legacy admission
  additionally preferred that nominal deadline over the resolved exit time.
- Sol Advanced: absence of tick coverage rejected the entire timed-reverse
  simulation before the ordinary bar fallback could resolve an earlier TP/SL.
- Sol Advanced exact quote path: the read ended at the nominal deadline, so a
  first executable quote just after it could not resolve the scheduled exit.
  Price-only acceleration also needed to respect the forced-exit boundary.
- Sol quote-cache retry: a positive but errored second read could be consumed
  without checking its error. Both readers now reject errored quote reads.

## Changes

MaCross and Entry Lab refine only the timed MA reverse boundary into M1 bars,
preserving the existing bar policy before it. A modeled market exit uses the
first available minute open, with recorded spread on SELL, and its actual
timestamp. SELL spread is not charged twice. Both legacy and Independent
capacity stay occupied until that exit. Zero-wait legacy behavior is retained.
Dynamic/time-exit combinations are not silently given a new approximate model.

Sol Advanced permits natural bar-policy TP/SL closures before the boundary.
A pure timed reverse can use a bounded M1 boundary replay without replacing
the shared simulation series. Its existing bar-entry cost convention remains
unchanged; no second SELL spread is introduced. Protective levels and existing
half-close state take priority at the reopening price.

The exact Sol tick path processes the first valid quote at/after the deadline,
after checking protection, and records its actual time. Acceleration cannot
skip across the deadline or let later adverse prices change the exit.

Modeled exits are tagged in the chart/dashboard and existing CSV context;
they are never presented as observed tick fills. Subminute uncertainty,
missing required M1 history, inverse without ticks, and unobserved NAS forced
exits remain DATA. No OHLC-derived exact early-exit PnL is claimed.

Only affected CURRENT setup keys receive an execution-revision marker.
Unaffected keys remain unchanged. Stored definitions and frozen MEGA evidence
are not rewritten; affected CURRENT results require a fresh audit.

## Native Verification

`scripts/validate_timed_reverse.ps1 -Baseline` captured the original functions
in the fixed stage before editing. Before-patch tests failed as expected:
MaCross 2/38, Entry Lab 2/38, Sol 69/72. After patch, expanded checks passed:

| Probe | Passed | Failed |
| --- | ---: | ---: |
| MaTimedReverseProbe | 184 | 0 |
| LabTimedReverseProbe | 184 | 0 |
| SolTimedReverseProbe | 232 | 0 |
| Existing Time Matrix suite | 343 | 0 |
| Total | 943 | 0 |

Fixtures use recorded GBPUSDm M5/M1 bars from October 2025. The Friday entry
has a Sunday 2025-10-26 08:05 deadline; the first recorded reopening minute
is 21:05 that day. BUY and SELL exits now use that available opening, not
08:05. Tests cover slot release, normal/ADV fallback parity, natural earlier
closures, and comparison against pre-change reverse-OFF/zero-wait functions.

Additional Sol tests inject explicitly synthetic quotes through a test-only
API wrapper: no quote exactly at the deadline, a 64-quote block crossing it,
later adverse quotes, protective-stop priority, and positive errored reads.
These prove control-flow ordering, not historical quote coverage or live
execution performance. The production quote API is not replaced.

All three canonical production MQ5 files compiled with **0 errors, 0 warnings**.
This was a focused regression run, not a new all-strategy mega campaign.

## Exact Production Files Changed

- IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5
- IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.ex5
- IndicatorCodeExamples/macrossover_orb/OrbAdvancedAuditEngine.mqh
- IndicatorCodeExamples/macrossover_orb/OrbStrategyUserMetrics.mqh
- IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5
- IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.ex5
- IndicatorCodeExamples/entry_engine_lab/OrbAdvancedAuditEngine.mqh
- IndicatorCodeExamples/entry_engine_lab/OrbStrategyUserMetrics.mqh
- IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5
- IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.ex5
- IndicatorCodeExamples/SolAdvanced/LiqAuditQuoteCache.mqh
- IndicatorCodeExamples/SolAdvanced/LiqStrategyWindowMetrics.mqh
- IndicatorCodeExamples/SolAdvanced/AuditTradeCsvAdapter.mqh

Added test sources: MaTimedReverseProbe.mq5/.mqh, LabTimedReverseProbe.mq5,
SolTimedReverseProbe.mq5 and scripts/validate_timed_reverse.ps1.

## Deployment

All 13 production files above were copied to their matching DEMO directories:

- C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb
- C:\MT5\DEMO\MQL5\Experts\EntryEngineLab
- C:\MT5\DEMO\MQL5\Experts\SolAdvanced

Source/destination SHA256 readback: **13/13 matched**. Evidence and compiler
logs: `reports/verification_build/timed_reverse`, especially `deployment.json`
and the three `*.after.json` probe outputs. Reload an already running chart EA
to ensure it is executing the updated binary; copying does not prove reload.
