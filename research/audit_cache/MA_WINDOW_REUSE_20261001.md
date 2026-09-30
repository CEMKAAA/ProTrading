# MaCross window reuse verification: 2026-10-01

## Result

For `usdjpyM50.01ModelIndependentMode` on a USDJPYm M1 chart, after
the 5Y audit, the complete 3Y audit call took **875 ms**. The corresponding
forced-cold 3Y call took 2,859 ms. The first 5Y call took 7,438 ms.
These include audit setup, calculation and chart commit, not just signal
kernel timings. Measurements used an isolated MT5 worker and actual
broker-synchronized history, with a fixed endpoint within the test.
They are not a universal latency guarantee for every chart or setting.

Warm and forced-cold 3Y results matched exactly: 5,814 trades, 5,737 W,
71 L, 6 O, zero DATA. Per-trade hashes include signal/entry/exit time,
direction, outcome, reason, geometry, exit price, net R and aggregate
cumulative/peak drawdown. Visible chart objects also matched: type,
time/price coordinates, color, text, arrow code and anchor. No PnL,
execution-price or admission calculation was changed to obtain this speed.

## Fixes

- Retain the raw signal superset, select smaller windows with binary bounds,
  and compare closed-source-bar coverage rather than the current second.
- Batch historical prefix cleanup instead of interleaving synchronous
  enumeration with chart deletion.
- Retain identical drawing payloads across window switches. Recalculate
  window-dependent admission and statistics normally; reuse only drawings
  whose complete payload matches. A smaller window hides excluded drawings
  instead of deleting and recreating every included drawing.
- Track chart-object deletion events to invalidate affected drawings rather
  than issuing a synchronous ObjectFind for every cached chart object.
  If event tracking cannot be enabled, the existence-check fallback remains.
- Clear drawing pools when relevant settings change; keep the committed
  snapshot until a replacement successfully commits. Cancelled new drawings
  remain hidden. Pool revision prefixes prevent stale delete events from
  invalidating a newer pool.
- Scan obsolete MA_OBS objects once, not the entire historical chart on every
  window switch. Current live code only queues reconciliation and does not
  create these obsolete objects.

Production files changed across this cache repair:

- `IndicatorCodeExamples/macrossover_orb/MaCrossAuditCache.mqh`
- `IndicatorCodeExamples/macrossover_orb/MaCrossEventAudit.mqh`
- `IndicatorCodeExamples/macrossover_orb/MaHistoricalVisualCache.mqh` (new)
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.ex5` (verified build)

## Evidence

- `.tmp/ma_replay_window_20261001_002004/result.txt`: complete 5Y -> 3Y
  broker-history test, unchanged data epoch, 7,144 lifecycle cache hits,
  28 recalculated misses; 5,799 drawing hits and 15 misses.
- Drawing unit tests: hidden staging, commit, cancel, hide/show roundtrip,
  deleted-object invalidation and changed-configuration cleanup passed.
- `.tmp/time_matrix_compile_20261001_002100`: all three production EAs
  compile with 0 errors and 0 warnings; 343 TIME MATRIX/strategy checks pass.
  Only the verified MaCross executable is released by this change.
- `.tmp/ma_window_20261001_002351/result.txt`: 3,710 deterministic signal-cache
  checks across six modes pass. That probe's optional live-history timing
  was unavailable (`real_ready=false`); it is not used as the broker-data
  parity evidence. The full replay test above supplies that evidence.
- `python tests/test_audit_csv_patch_contract.py`: 20 source contracts pass.
- The ProcessHistoricalCalcDay block preceding the drawing section matches
  `.tmp/time_matrix_compile_20260930_231404` exactly after newline normalization:
  admission, PnL, CSV capture and audit statistics are unchanged.

## Limits

Reuse is instance-local, not a persistent five-year database. Restart,
changed parameters or relevant market-history changes still require the
appropriate rebuild. OPEN/DATA trade outcomes are not frozen into cached
final results. Window-dependent daily limits, TIME MATRIX and independent
position capacity are replayed: slicing a final 5Y admitted-trade list is
not an equivalent calculation. New/differing drawing payloads are rendered
normally; cache exhaustion falls back to normal rendering. No listener,
bridge schema, live signal kernel or trade geometry was modified.

## Release

The DEMO terminal was closed. The verified MaCross `.mq5`, `.ex5` and
required dependencies were deployed to
`C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb` and required parent include
locations. All 49 deployed SHA-256 hashes match the verified stage.
The canonical workspace executable also matches the verified build.
No ORB or Sol Advanced executable/source was deployed by this release.

Backup: `.tmp/ma_window_deploy_backup_20261001_002654`.
Release stage: `.tmp/time_matrix_compile_20261001_002100`.
