# ORB Reverse Exit 48H Workaround

## Scope And Method

Canonical ORB only. No entry-signal mathematics, saved strategy definitions,
bridge protocol, listener, MEGA archive or other production EA was changed.

- Preserve 48:00 as elapsed broker-calendar time, not 48 trading hours.
- Retain exact tick replay wherever the existing engine obtains complete quotes.
- Preserve the existing ordinary bar-policy TP/SL simulation before the deadline.
- In the normal fixed-target fallback, switch to M1 only in the bar containing
  or following the reverse deadline. A closed market advances the modeled exit
  to the first available M1 bar, never the last bar before the event.
- Allow a higher-timeframe bar to start before its first available minute only
  when that minute is within the same bar and has the same recorded open.
- Keep occupancy until the resolved exit time; never release an unknown slot.
- A sub-minute deadline with unavailable quote ordering remains DATA. Invalid or
  inconsistent M1 data remains DATA. The workaround does not relax full inverse
  quote requirements or unrelated dynamic/time-exit modes.

M1 opens and recorded bar spread are a model, not historical execution quotes.
Modeled closes carry `M1 MODEL` / `NOT TICK-EXACT` in chart/audit diagnostics and
`exit_price_basis=M1_OPEN_SPREAD_MODEL_NOT_TICK_EXACT` in CSV context and internal
trace details. The existing CSV schema is unchanged. A SELL market exit's modeled
ask already contains its spread; that spread is not charged again as entry spread.
Slippage/commission settings continue through the existing cost function.

## Observed Boundary Issue

GBPUSDm, 2022-01-03: M5 contains the 08:30 bar with open 1.35120. M1 has no
08:30 bar; its first minute is 08:31 with the same open 1.35120. Requiring a
complete M1 prefix from every entry unnecessarily poisoned Legacy occupancy.
The final implementation leaves pre-deadline lifecycle processing unchanged
and reads M1 only at the forced-exit boundary.

## Verification

- Production ORB compile: 0 errors, 0 warnings.
- Seventeen focused checks passed: natural TP parity, minute-aligned modeled
  exits, sub-minute uncertainty, Friday-to-weekend reopening, occupancy release,
  SELL spread handling, strict inverse behavior, and ADV/normal fallback parity.
  These tests use recorded GBPUSD bars with quote replay deliberately unavailable;
  they do not establish exact historical execution prices.
- Sixty-four reverse-OFF cases matched the pre-change `SimulateTrade` function
  for verdict, exit time/price, entry/SL/TP geometry, milestones, costs and Net R.
- Time Matrix/timezone/strategy serialization regression: 343 checks, 0 failures.
- Research probes ran in the existing isolated worker with Algo Trading OFF.

### Original Reported Setup, Temporarily With MA REV 48H

Loaded `gbpusdFirst`, GBPUSDm/M5, then enabled MA REV / 48:00 only in the test.
This is a modified setup: the original strategy record and its normal-mode
CURRENT metrics were deliberately not overwritten. Accordingly its test CSV's
`savedExact=false` is expected, not a persistence failure.

Cutoff epoch: 1791901997.

| Window | Total | W | L | O | DATA | Net R | M1 Modeled Exits |
|---|---:|---:|---:|---:|---:|---:|---:|
| 20W | 83 | 77 | 6 | 0 | 0 | 0.8298 | 0 |
| 1Y | 217 | 202 | 15 | 0 | 0 | 1.5146 | 3 |
| 2Y | 447 | 416 | 31 | 0 | 0 | 2.1238 | 19 |
| 5Y | 1088 | 984 | 104 | 0 | 0 | -2.9014 | 90 |

### Saved 48H Variant And Automatic CURRENT Readback

Loaded the actual saved `gbpusdFirstMaRev48Hours`, GBPUSDm/M5, without changing
its parameters. Its settings differ from the original setup above. All nine
windows completed with DATA=0. Automatic persisted CURRENT values matched the
native audit headline W/L/O/F, Net R, MinCum and cutoff in all nine windows.

Cutoff epoch: 1791900308.

| Window | Total | W | L | O | Net R | MinCum R | M1 Modeled Exits |
|---|---:|---:|---:|---:|---:|---:|---:|
| 5Y | 1090 | 992 | 98 | 0 | -2.0870 | -4.1452 | 84 |
| 4Y | 881 | 806 | 75 | 0 | 0.3604 | -1.6978 | 61 |
| 3Y | 654 | 599 | 55 | 0 | 0.4380 | -1.6202 | 42 |
| 2Y | 448 | 419 | 29 | 0 | 1.9862 | -0.0278 | 17 |
| 1Y | 214 | 198 | 16 | 0 | 1.4138 | 0 | 4 |
| 20W | 80 | 74 | 6 | 0 | 0.7462 | 0 | 0 |
| 10W | 39 | 36 | 3 | 0 | 0.3682 | -0.2118 | 0 |
| 5W | 23 | 23 | 0 | 0 | 0.4600 | 0 | 0 |
| 2W | 10 | 10 | 0 | 0 | 0.2000 | 0 | 0 |

These are completed model audits, not a claim of profitable or tick-exact live
execution. Earlier bars may also use the engine's existing normal bar policy.

Evidence under `reports/verification_build/strategy_metrics`:

- `gbp-original-reverse.csv`
- `gbp-workaround.csv`
- `minute-gap.csv`
- `reverse-fallback.json`
- `default-parity.json`
- `orb_production.log`
- `orb_workaround_deployment.json`

## Released Files

Canonical `IndicatorCodeExamples/orb` and `C:\MT5\DEMO\MQL5\Experts\orb` contain
matching SHA256 versions of:

- `OrbUltimateEA_StrategyLibrary.mq5`
- `OrbUltimateEA_StrategyLibrary.ex5`
- `OrbAdvancedAuditEngine.mqh`

Updated verification sources are `tests/mql5/OrbReverseFallbackProbe.mq5` and
`tests/mql5/StrategyMetricsOrbLiveAudit.mq5`. No user terminal was forcibly closed.
