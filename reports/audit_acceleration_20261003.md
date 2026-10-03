# Exact Audit Acceleration / 2026-10-03

## Measured Results

Frozen pre-change source and accelerated source were compiled separately and run in the same isolated MT5 worker. All measured runs below completed without DATA records. Network downloads are not included in the speedup claim: broker history and existing V2 day indexes were already available. The first audit means cold EA outcome caches, not a first-ever broker download. No broker orders or entry publishers were invoked.

| Workload | Before (s) | After (s) | Speedup |
| :--- | ---: | ---: | ---: |
| MaCross XAUUSD M1 / 20W / first audit | 149,563 | 24,671 | 6,06x |
| MaCross XAUUSD M1 / 20W / unchanged repeat | 0,282 | 1,172 | 0,24x |
| MaCross XAUUSD M1 / 20W / changed R target | 125,078 | 24,360 | 5,13x |
| Entry Lab builtin XAUUSD M1 / 20W / first audit | 159,453 | 18,422 | 8,66x |
| Entry Lab builtin XAUUSD M1 / 20W / unchanged repeat | 157,687 | 0,281 | 561,16x |
| Entry Lab builtin XAUUSD M1 / 20W / changed R target | 128,375 | 17,578 | 7,30x |
| Sol USDJPY H1 / 20W / first audit | 13,140 | 2,172 | 6,05x |
| Sol USDJPY H1 / 20W / unchanged repeat | 0,938 | 0,422 | 2,22x |
| Sol USDJPY H1 / 20W / changed R target | 7,453 | 1,250 | 5,96x |
| Sol USDJPY H1 / 5Y / first audit | 38,453 | 7,109 | 5,41x |
| Sol USDJPY H1 / 5Y / unchanged repeat | 1,062 | 0,375 | 2,83x |
| Sol USDJPY H1 / 5Y / changed R target | 28,672 | 3,016 | 9,51x |

MaCross/Entry Lab timing includes signal preparation, filtering, lifecycle execution, statistics, chart-object creation/commit and ChartRedraw. Initial Pine signal-kernel construction and tick synchronization are logged separately. Sol uses the production synchronous recalculation path including macro reference statistics and final dashboard draw. These are workload measurements, not a guarantee for every symbol, setup or broker.

The unchanged-repeat path was already cached in the old engine and need not improve by 4x. The target applies to actual recalculation workloads. The Orb shared ADV path has correctness/compile verification but no independent whole-ORB-session speed benchmark in this campaign.

## Bottleneck And Changes

- MaCross baseline spent 148.230 seconds of its 149.563-second first audit in 5292 tick reads. Final accelerated reads: 510 calls / 23361.319 ms, with the same 497729 exact replay ticks examined. Rendering was not the bottleneck. An earlier accelerated run took 16.156 seconds end-to-end; the table reports the later final rerun, not the fastest observation.
- Orb/MaCross/Entry Lab ADV candidate-minute reads now use exact zero-copy slices of the existing shared quote cache, with four-hour read batching and bounded extension. Failed bulk reads fall back to the original guarded exact-range reader.
- Completed ADV day-index pages use a bounded 64-slot ownership-swap cache instead of repeatedly copying arrays or rereading a revisited day. Reset and mode changes clear these pages; the mutable current day is not retained.
- Sol uses completed six-hour exact-quote pages, 64-tick extrema skip proofs, and minute extrema built from exact Bid/Ask quotes. A proof can only skip intervals with no possible state-changing SL/TP/HC event. Candidate intervals still use the original chronological tick loop. Exact last-quote time and price are retained for OPEN and forced exits.
- Sol NAS predecessor/successor queries now use indexed chronological lookups rather than repeatedly scanning the entire prefix. Formula, direction, lookback age, wait semantics and raw-signal boundaries are preserved.
- Entry Lab had an existing completed-outcome cache bug: its epoch included the engine identity, but the final consistency check omitted it. Both outcome and prepared-context checks now compare the same complete identity. The final repeated audit recorded 2122 memo hits and no tick reads; engine changes still invalidate the key.
- Sol quote pages have a 64 MiB retention budget; a single oversized input may exist transiently without being retained. Completed-minute proof storage is separately capped at 32768 hours (about 120 MiB plus metadata). Capacity exhaustion disables further caching, not execution or correctness.
- Completed Sol summaries are invalidated on server/symbol/tick-size changes, earlier history, non-append bar backfill, history reset and synchronization transitions. Explicit invalidation is also available internally. There is no new persistent cache format.
- Signal kernels, entry/SL/TP/inversion mathematics, cost formulas, strategy schemas, CSV schemas, publishing and listeners were not changed. The legacy/default Orb/MaCross/Entry Lab engine remains the reference path; acceleration requires the existing ADV setting. Sol accelerates its existing tick-replay path.

## Correctness Evidence

14177 trade trace rows match the frozen source in original chronological order, byte for byte. These traces include fills, geometry, exit timestamps, outcomes, W/L/O/DATA status and R. No positive/negative PnL was substituted or rounded into a target result.

| Test family | Checks | Failed |
| :--- | ---: | ---: |
| Sol | 266179 | 0 |
| Orb | 1510 | 0 |
| Ma | 1213 | 0 |
| Lab | 1213 | 0 |

Total assertions: 270115. Sol tests include 72 real-market accelerated-versus-reference cases varying stop distance, HC, inversion, slippage/commission settings, fixed/reverse targets and forced horizons. NAS tests compare indexed answers with literal linear reference implementations. Quote tests cover inclusive endpoints, duplicate timestamps, empty minutes, last executable quote preservation, reset, LRU eviction and mutable current-day safety.

All four canonical production mains compile with 0 errors and 0 warnings. Matching a reference is regression evidence, not proof that every historical assumption in the older engine is correct, nor a guarantee of live broker execution or universal 4-5x speedup. Broker tick revisions that do not expose a history/sync change require explicit invalidation or an EA reload.

Timings are observed wall-clock samples, not confidence intervals. Compilation/system contention affects elapsed time. The final MaCross repeat was slower than its frozen already-cached repeat; no improvement is claimed for that row. Five-year, all-symbol strategy campaigns, first-time tick downloads and live fills were not exhaustively tested. Entry Lab market performance here uses its inherited builtin Close/Reverse engine, not every custom builder engine.

## Reproduction

Harness: `scripts/audit_perf_campaign.ps1`. Frozen and optimized source/data/results: `
C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\.tmp\audit_perf_20261003_162037
`. Do not rerun Prepare against modified source when comparing with this baseline.

Use Baseline or Optimized with Family Ma, Lab or Sol; Symbol XAUUSDm or USDJPYm; Weeks 20 or 260. Checks runs the corresponding family tests. Compile builds all four production mains. Correctness and performance probes do not run production OnInit or submit orders.

## Production Files

- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- `IndicatorCodeExamples/orb/OrbAdvancedAuditEngine.mqh`
- `IndicatorCodeExamples/orb/OrbAuditRamCache.mqh`
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`
- `IndicatorCodeExamples/macrossover_orb/OrbAdvancedAuditEngine.mqh`
- `IndicatorCodeExamples/macrossover_orb/OrbAuditRamCache.mqh`
- `IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5`
- `IndicatorCodeExamples/entry_engine_lab/OrbAdvancedAuditEngine.mqh`
- `IndicatorCodeExamples/entry_engine_lab/OrbAuditRamCache.mqh`
- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`
- `IndicatorCodeExamples/SolAdvanced/LiqAuditQuoteCache.mqh`
- `IndicatorCodeExamples/SolAdvanced/LiqSolAdvancedNas.mqh`

Matching EX5 binaries and README release notes are updated alongside these canonical files. No root-level legacy EA or other listener family is deployed.

## Deployment

Published 181 files to the four canonical DEMO folders with SHA256 checks. Backup: C:\Users\Cem\Desktop\projeler\YapayZekaUygulamalari\ProTradingSystem\.tmp\audit_acceleration_backup_20261003_183628.

