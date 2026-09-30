# MaCross audit window reuse: 2026-09-30

## Scope

Strategy: `usdjpyM50.01ModelIndependentMode`, user record 66, USDJPYm.
Test chart M1, source signals M5, Trendline mode, independent positions,
0.01R, pip stop 800, saved TIME MATRIX and daily limits applied in memory.
No native orders, publication or strategy-metric writes were enabled by the
probe. The user's DEMO chart and its current settings were not changed.

Production files changed:

- `IndicatorCodeExamples/macrossover_orb/MaCrossAuditCache.mqh`
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`

## Causes and fixes

1. Raw signal cache compared its endpoint with the advancing wall clock.
   It now compares closed-source-bar coverage, not the current second.
2. A smaller-window cache hit did not select an isolated window view. The
   cache now retains its immutable superset and selects a bounded view by
   two binary searches. Signal indicator formulas are unchanged.
3. Chart cleanup interleaved synchronous object enumeration with queued
   deletion, then enumerated both historical generations at commit. Prefix
   deletion is now native/batched. Subsequent commits delete the known old
   generation without enumerating both snapshots. Initial legacy cleanup
   retains the fallback; cancelled builds retain the previous snapshot.

## Actual full-audit measurement

Isolated MT5 worker, real broker history, frozen endpoint within each run.
Do not confuse the 78 ms signal-kernel benchmark with full audit time.

| Measurement | Before cleanup fix | Final |
| --- | ---: | ---: |
| Complete 5Y to 3Y call, including setup and chart work | 35.844 s | 6.141 s |
| Warm 3Y calculation stage | 0.953 s | 1.015 s |
| Warm 3Y snapshot commit | 24.344 s | 2.485 s |
| Final forced-cold 3Y complete call | - | 5.703 s |

The final warm calculation reused 7,144 closed-trade lifecycle records;
28 misses were recalculated. Cache data epochs did not change in the warm
run. Warm versus cold total chart time is workload-dependent: cached
calculation is faster, but drawing and deleting thousands of objects is
not instantaneous. These are worker measurements, not a guaranteed live
dashboard latency or a single controlled before/after timing sample.

Warm and forced-cold results matched exactly by a per-trade identity hash:
5,814 trades, 5,737 W, 71 L, 6 O, 0 DATA. The comparison includes signal,
entry and exit timestamps, direction, outcome, reason, entry/SL/TP/exit
prices, net R and aggregate cumulative/peak drawdown. Settings were not
modified to improve performance or results.

Evidence:

- `.tmp/ma_replay_window_20260930_225407/result.txt`: before chart fixes.
- `.tmp/ma_replay_window_20260930_231253/result.txt`: final complete replay.
- `.tmp/ma_window_20260930_223707/result.txt`: 3,714 signal-cache checks,
  six signal modes, window selection, parameter invalidation and real history.
- `python tests/test_audit_csv_patch_contract.py`: 20 contracts passed;
  execution/geometry/lifecycle bodies and CSV feature modules unchanged.
- `.tmp/time_matrix_compile_20260930_231404`: all three production EAs
  compile with 0 errors and 0 warnings; 343 TIME MATRIX checks passed.
  Final MaCross executable copied into its canonical workspace folder.

## Limits

This is instance-local reuse, not a persistent five-year database. Restart,
changed source-bar state, history seed, signal mode, timeframe or indicator
length invalidates the signal kernel as appropriate. Existing lifecycle
hashes remain responsible for geometry and filter changes. OPEN/DATA rows
are not frozen into final outcomes. Window-dependent admission (position
capacity, daily limits and TIME MATRIX) is still reapplied chronologically;
simply slicing the final five-year trade list would be incorrect.

## Release

DEMO was closed before publishing. MaCross and its 47 dependencies/binary
files were deployed to `C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb` and
required parent include locations; all 48 SHA-256 hashes matched. No ORB
or Sol Advanced entry point/executable was deployed by this release.
Backup: `.tmp/ma_window_deploy_backup_20260930_232216`.
