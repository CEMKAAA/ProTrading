# Manual Audit To Strategy Search Verification

Follow-up: the separate 48H case below was subsequently addressed with an
explicit M1 bar-model workaround. See `orb_reverse_48h_workaround_20261013.md`.
The original investigation below remains dated evidence, not the latest status.

Release: 2026-10-13. Scope: canonical ORB, MaCross, Sol Advanced and Entry Lab.
Manual audits update CURRENT only. No strategy definition, MEGA archive, bridge,
listener, web application or campaign manifest was changed by these tests.

## Behavior

- Audit completion records the actual completed window under the saved setup's
  exact identity, without requiring another Save action.
- Nine bounded summaries retain actual completed audits for audit-before-save
  and save-under-new-name. Smaller windows are never fabricated from aggregates.
- Execution identity includes time masks, direction, daily quotas and inverse
  cost tolerance. Changing these settings cannot publish a stale result.
- Sol's execution fingerprint excludes the audit-window selector. Same-name
  saves that change only that metadata preserve validated CURRENT windows.
  Changed geometry or filters do not inherit prior evidence.
- CURRENT search lists poll shared Common files every five seconds while open
  and idle. Closed lists reload when opened. This is polling, not instantaneous
  cross-terminal event delivery; an instance's running audit can delay polling.
- ORB built-ins read validated results using their original audit symbol even
  when ALL-pairs search is displayed on another chart. Seventeen previously
  missing 5Y built-in results were recovered without rerunning their audits.
- Real DATA/incomplete coverage never replaces a previously valid result.

## Files Changed

All paths below are under `IndicatorCodeExamples`:

- `orb/OrbUltimateEA_StrategyLibrary.mq5` and matching `.ex5`
- `orb/OrbStrategyPresetLibrary.mqh`
- `orb/OrbStrategyUserLibrary.mqh`
- `orb/OrbStrategyUserMetrics.mqh`
- `orb/StrategyWindowMetrics.mqh`
- `macrossover_orb/MaCrossOverOrbEA.mq5` and matching `.ex5`
- `macrossover_orb/OrbStrategyUserLibrary.mqh`
- `macrossover_orb/OrbStrategyUserMetrics.mqh`
- `macrossover_orb/StrategyWindowMetrics.mqh`
- `entry_engine_lab/EntryEngineLabEA.mq5` and matching `.ex5`
- `entry_engine_lab/OrbStrategyUserLibrary.mqh`
- `entry_engine_lab/OrbStrategyUserMetrics.mqh`
- `entry_engine_lab/StrategyWindowMetrics.mqh`
- `SolAdvanced/LiqNarrativeSol_Advanced.mq5` and matching `.ex5`
- `SolAdvanced/LiqStrategyLibrary.mqh`
- `SolAdvanced/LiqStrategyWindowMetrics.mqh`
- `SolAdvanced/StrategyWindowMetrics.mqh`

Focused verification sources:

- `scripts/validate_strategy_metrics.ps1`
- `tests/mql5/StrategyMetricsPersistenceChecks.mqh`
- `tests/mql5/StrategyMetricsOrbLiveAudit.mq5`
- `tests/mql5/OrbReverseFallbackProbe.mq5`

## Verification Results

All four canonical production sources compiled with 0 errors and 0 warnings.

- Persistence: ORB 71, MaCross 71, Sol 115, Entry Lab 71; 328 checks, 0 failures.
  These are explicit counter/storage fixtures, not market-profitability tests.
- Strategy-search R/mode regression: 174 checks, 0 failures.
- Time Matrix, timezone save, hour actions and strategy serialization regression:
  343 checks, 0 failures.
- Reverse fallback ordering probe: 7 checks, 0 failures. Ordinary bar-policy TP
  before the 48H boundary remains unchanged; an unresolved timed exit inside or
  at the start of a bar stays DATA when exact quotes are unavailable.
- Native research tests used the existing isolated worker with Algo Trading OFF.
  No live EA initialization or order-entry handlers ran in the focused probes.

### Actual Saved Strategy Audit

`0.20RStarJp225DailyNextDayOff`, ORB, JP225m/M5, saved configuration unchanged.
The normal ORB audit engine ran each window. The automatic CURRENT write was
read back with the same identity and compared with the engine's headline
W/L/O/F, Net R, MinCum and cutoff. All nine windows matched; DATA count was zero.

Frozen broker cutoff: epoch 1791880874. Values are historical test evidence,
not a claim that a later moving window has identical results.

| Window | Total | W | L | O | F | Net R | MinCum R | Exact Readback |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 5Y | 433 | 383 | 50 | 0 | 0 | 20.488125 | -3.571000 | Yes |
| 4Y | 359 | 313 | 46 | 0 | 0 | 11.659625 | -12.399500 | Yes |
| 3Y | 286 | 255 | 31 | 0 | 0 | 16.528125 | -7.531000 | Yes |
| 2Y | 201 | 186 | 15 | 0 | 0 | 20.473250 | -3.585875 | Yes |
| 1Y | 113 | 109 | 4 | 0 | 0 | 17.710125 | 0 | Yes |
| 20W | 50 | 48 | 2 | 0 | 0 | 7.600000 | 0 | Yes |
| 10W | 24 | 23 | 1 | 0 | 0 | 3.600000 | 0 | Yes |
| 5W | 13 | 12 | 1 | 0 | 0 | 1.400000 | -0.200000 | Yes |
| 2W | 6 | 6 | 0 | 0 | 0 | 1.200000 | 0 | Yes |

Evidence: `reports/verification_build/strategy_metrics/named-audit.csv`.
This is one actual broker-backed nine-window market case; it is not exhaustive
market parity verification of every saved strategy in every family.

## Separate GBPUSD 48H Investigation

`gbpusdFirst`, GBPUSDm/M5, MA REV EXIT ON, wait 48:00.
The modified test setup was deliberately not selected for persistence, so its
results never overwrote the original saved `gbpusdFirst` configuration/result.

Reproduced before patch:

- 20W: 76W / 6L / 1O / 0 DATA.
- 1Y: 0W / 0L / 258 DATA.
- 2Y: 0W / 0L / 515 DATA.
- 5Y: 0W / 0L / 1293 DATA.

A blanket reverse-tick requirement invalidated even natural TP/SL closures
before the reverse deadline. The patch retains the existing ordinary bar-policy
closures before that boundary, but refuses to invent exact timed-exit prices.

Remaining limitation: the actual timed-exit cases before 2026 still lack quote
ticks in this connected Exness worker. Direct `CopyTicks(..., COPY_TICKS_INFO,
requested_time, 1)` requests for 2021-10-29, 2024-10-21, 2025-10-30 and 2025-11-03
all returned 2026-01-01 22:05 as the first available quote, with error 0.
This identifies a real replay coverage boundary in the tested terminal/provider;
it does not prove no other historical provider could supply those quotes.

Consequently, a genuine unknown timed exit can still make subsequent Legacy
admission uncertain. No unknown slot was fabricated as released, and no DATA
was relabeled W/L. The >20W reverse-48H case is therefore not fully resolved as a
complete exact audit with the currently available history.

Evidence: `gbp-before.csv`, `gbp-after.csv`, `reverse-fallback.json` and
`tick-availability.csv` in the bounded verification directory.

## Deployment

Twenty-one changed source/header/binary files were copied to:

- `C:\MT5\DEMO\MQL5\Experts\orb`
- `C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb`
- `C:\MT5\DEMO\MQL5\Experts\SolAdvanced`
- `C:\MT5\DEMO\MQL5\Experts\EntryEngineLab`

All required existing headers were compared as well. Destination SHA256 values
match canonical sources and compiled binaries. Exact paths and hashes are in
`reports/verification_build/strategy_metrics/deployment.json`.

The user's running DEMO terminal was not stopped. Already-loaded chart EAs must
be reloaded to execute the newly deployed binary.
