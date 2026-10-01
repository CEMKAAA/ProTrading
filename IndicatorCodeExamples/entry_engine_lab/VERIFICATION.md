# Verification: 2026-10-01

## Current Release: 1.06 Independent Policy

Build: `EntryEngineLab-1.06-IndependentPolicy`.
Evidence: `.tmp/entry_engine_lab_20261001_232313/result.txt`.

```
checks=10300 failed=0 trades=40 audit_same=true
rsi_error=0.0000000000 adx_error=0.0000000000
history_source=BROKER_SYNCHRONIZED profile=PIP_FOCUSED
```

Production and full-EA probe compile: 0 errors, 0 warnings. The isolated
worker used EURUSDm on Exness-MT5Trial15; native orders/PUB were disabled.

The custom policy shape no longer rejects INDEPENDENT. Historical cooldown
uses the latest completed exit from the capacity heap, never a future simulated
close. The Bollinger M1 2W Independent MAX10 audit produces closed trades with
zero DATA, peak concurrency <=10, OPEN <=10 and matching warm/cold hashes.
Legacy admission and all ten entry formulas are unchanged on covered data.

The engine picker includes ENGINE EXITS ON/OFF. Tests invoke the real modal
handler, round-trip OFF through strategy save/load, and verify that OFF removes
actual LAB_RULE_EXIT/LAB_TIME_EXIT outcomes. Its tick replay matches the same
SL/TP policy with holding/rule exit definitions removed. Existing LAB2/3/4
records default to ON. SL/TP, NAS, MA reverse and entry cooldown are not disabled.

EURUSDm 1Y and 2Y requested ranges were tested separately. The broker returns
no ticks for sampled 2024/2025 intervals and its first returned quote is
2026-01-01 22:05. The EA now explicitly blocks these incomplete policy audits
as TICK HISTORY UNAVAILABLE instead of presenting 0W/0L after the first DATA
locks Legacy occupancy. This does NOT establish a complete 1Y/2Y result;
additional broker quote history is required. No OHLC exact exits are invented.

The first 1.06 test had one fixture failure because its shape assertion had
not initialized FIXED/BREAK/HC OFF. The corrected fixture and added OFF tick
replay checks passed in the final run above. Failed stages were not released.

## Previous Release: 1.05 Classic Pip

Verified production build: `EntryEngineLab-1.05-ClassicPip`.
Evidence: `.tmp/entry_engine_lab_20261001_223229/result.txt`.

```
checks=10278 failed=0 trades=110 audit_same=true
rsi_error=0.0000000000 adx_error=0.0000000000
history_source=BROKER_SYNCHRONIZED profile=PIP_FOCUSED
```

Production EA and full-EA probe compiled with 0 errors and 0 warnings.
The isolated worker connected and synchronized with Exness-MT5Trial15.
No native order or bridge message was submitted.

Custom policy engines now always use the standard pip SL and the selected
dashboard R. The engine ATR geometry override and policy-imposed target ratio
were removed. Entry formulas, cooldown, rule exits and time exits remain.
Former ATR geometry results are intentionally not preserved.

The actual dashboard event handlers were tested for pip edits 0.1 and 0.5,
and R selections 0.1 and 0.5. Recorded tick audits additionally verified:

- R 0.5 -> 0.1 changes actual TP geometry and cached audit results.
- R 0.1 -> 0.5 restores the original audit hash.
- Pip SL 25 -> 10 changes actual SL geometry without a manual cache reset.
- Warm/cold audits match entry/exit times, fills, SL/TP, outcomes and net R.
- Strategy restore and explicit engine activation restore the pip edit.
- Rule/time exits retain actual fill-to-exit PnL; ADV/default hashes match.
- Capacity slots recycle after exits; max=3 has OPEN=3, peak=3, DATA=0.

The focused run also retains all ten independent recipe formula checks,
six built-in kernel comparisons, picker tests and policy publication guards.
It is not live broker execution or profitability validation. Quotes are
not fabricated, PnL is not forced to the target R, and very small pip/R
distances remain subject to tick-size rounding and broker stop limits.

## Historical Evidence: 1.04 And Earlier

The sections below describe previous releases, not current ATR behavior.
Previous pip-policy release evidence:
`.tmp/entry_engine_lab_20261001_220240/result.txt`

```
checks=10270 failed=0 trades=54 audit_same=true
rsi_error=0.0000000000 adx_error=0.0000000000
history_source=LOCAL_FIXED profile=PIP_FOCUSED
```

The full campaign immediately before the final SL-input synchronization fix
passed 10312 checks with zero failures in
`.tmp/entry_engine_lab_20261001_211147/result.txt`. The final focused run
retains all ten independent recipe formula checks, dashboard controls,
pip tick audits, native/audit exit clocks, ADV/default parity, strategy
restoration, warm/cold reuse and concurrent-capacity checks. It omits only
the repeated ten-engine ATR audit campaign and its final campaign cache test.
Production EA and both probes compiled with 0 errors and 0 warnings.
No native order or bridge message was submitted.

Previous normal broker-data run (before the engine pip override):
`.tmp/entry_engine_lab_20261001_185624/result.txt`

```
checks=10293 failed=0 trades=52 audit_same=true
rsi_error=0.0000000000 adx_error=0.0000000000
history_source=BROKER_SYNCHRONIZED
```

EA and full-EA probe both compiled with 0 errors and 0 warnings.
The isolated worker connected to Exness-MT5Trial15. No native orders or
publisher messages were submitted by the probe.

For the deliberately unoptimized test engine (RSI14 crosses 50), USDJPYm M5,
fixed 30-pip SL and the inherited 2R target, the final 2W audit contained
52 trades with the total concurrent-position limit applied. This is a functionality fixture, not a profitable strategy
recommendation. Warm 5W-to-2W and forced-cold 2W hashes
matched counts, signal/entry/exit times, direction, geometry and net R.

Parameterized EMA9/SMA50 crossover was checked on 10000 recorded bars.
The six built-in kernels, with all three pairing choices, were compared on
the same bars with an extracted unmodified MaCross kernel. Directions and
marker prices matched. Fixed RSI/ADX values matched native MT5 indicators;
parameterized SMA was also checked against native iMA.

Other checks cover gate truth tables, unknown values, independent BUY/SELL
conditions, cross semantics, FVG chronology, serialization, same-name engine
update, modal event interception/current edit values, preview entry guard,
live/history custom signal kernel, and strategy engine snapshot restoration.

The ten scalper recipes were independently evaluated on 10000 bars. Checks
include entry and separate long/short exit predicates, Wilder ATR snapshots,
population Bollinger deviation and previous-five-bar extrema excluding the
current bar. Each recipe also completed a USDJPYm M1 2W tick audit with zero
DATA results; see SCALPER_AUDIT.md for the measured, negative outcomes.

Policy checks cover single-position occupancy, cooldown candle boundaries,
ATR geometry, all ten ON/OFF serialization round trips, current modal edits,
modal object click priority above the dashboard, and strategy restoration of
all policy fields. A separate wide-ATR fixture exercises rule/time exits:
recorded net R equals actual signed fill-to-exit R less configured costs,
native/audit helper exit clocks agree, and ADV/legacy audit hashes match.
The campaign cutoff is frozen only in the test probe so differential runs
compare the same window; production clocks, prices and fills are unchanged.

Publisher-enabled and NAT-disabled policy entries are rejected by the native
guard. These tests did not submit real orders: broker execution, latency,
slippage, and historical broker stop/freeze-limit changes remain unverified.
New policy engines require PUB OFF and NAT ON; no listener exit support is
implied. Missing exact tick coverage is not converted into invented outcomes.

ORB and Sol Advanced source folders remained unchanged. MaCross received the
explicitly requested matching native counter and concurrent-capacity fix.
Its pre-change/new Legacy 5W test matched 138 trades, counts, timestamps,
geometry and net R exactly; see macrossover_orb/OPEN_CAPACITY_VERIFICATION.md.
Before
copying the final EX5 to the workspace family, the staged MQ5 and required
MQH files were hash-compared to canonical sources.

Not verified: live order submission, new-family listener execution, every
filter combination, very large custom engines, or visual layout on all
resolutions. Those are not implied by these regression results.

## Picker And Open-Capacity Regression

The blank lists were reproduced: MQL5 StringFind(name, "") returned -1,
rejecting every item. The focused pre-fix run failed 18 of 22 checks.
The corrected explicit empty-query branch passed all 22 checks; engine and
feature picker screenshots were inspected in
`.tmp/entry_engine_lab_20261001_182243`. Pagination exposes 16 default engines
and all 44 features. Modal coordinates are not dashboard-scaled a second time.

The full run also validated total BUY+SELL simultaneous occupancy on broker
tick data, not a consecutive-signal counter:

| Fixture | Accepted Trades | Open At Cutoff | Peak Open | DATA |
| --- | ---: | ---: | ---: | ---: |
| 5W, MAX=10, wide stops | 10 | 10 | 10 | 0 |
| 5W, MAX=3, wide stops | 3 | 3 | 3 | 0 |
| 2W, MAX=3, reverse exits | 778 | 3 | 3 | 0 |

The live OPEN counter reads symbol/magic-owned native positions. No live order
was submitted in these tests. Existing over-limit exposure is not liquidated;
new entries are blocked and applying a limit below current exposure is rejected.
Unknown historical exits conservatively retain a slot through the cutoff.

## Historical 1.04 Custom-Engine Pip SL

Build: EntryEngineLab-1.04-PipPolicy. The existing SL row now switches a policy
engine between ENG ATR and PIP ON. APPLY reads the current pip edit. Pip mode
scales TP from the rounded SL distance using the engine's existing tpAtr/slAtr
ratio; cooldown, rule exits and holding limits are not removed. Changes apply
to subsequent entries and recalculated audits, not existing broker positions.

LAB4 stores the engine pip mode and distance. Existing LAB2/LAB3 records load
with pip override OFF, irrespective of the previously selected engine. Their
default serialization and ATR geometry are unchanged. Engine snapshots in
strategies and active-engine persistence include the new fields.
Explicit strategy restore and engine activation replace the SL input with
the engine's applied value; routine redraws preserve unapplied user edits.

The regression invokes the actual dashboard event handler for the SL buttons.
It compares replayed entry/sl/tp fields against the native geometry helpers;
plannedTp is the inherited first target-leg field, not the policy's real TP.
No outcomes, fills or production coverage guards are overridden by the test.

The tick geometry regression found a resume defect: entry, risk, target and
effective stop were restored from the filled trade snapshot, but the reported
SL could remain the incoming plan (one tick away on the reproduced case).
Resume now restores its original executable SL as well. No price-path scan,
exit rule or win/loss classification has been replaced.

The first connected attempt could not complete history tests after the worker
lost its broker connection. The local-history fixture validates all stored
bars before accepting its frozen synchronization flag and retains the actual
tick replay. This is not live execution validation.
