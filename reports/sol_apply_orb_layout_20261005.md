# Sol Advanced Apply and ORB Layout Fixes

## Result

Verified and deployed on 2026-10-05. Both production EAs and all four test
programs compiled with **0 errors and 0 warnings**. Final behavior probes:
ORB 49,415 checks, Sol Advanced 24,641 checks, **74,056 total, zero failures**.

## Behavior

- Sol Advanced NAS / POSITIONS Apply no longer uses the full-strategy flat-exposure guard.
- Fixed preset R and custom R Apply work with owned native positions open.
- Existing broker SL/TP and half-close plans are not modified by Apply.
- Existing native positions retain their NAS/reverse exit policy in the existing ticket-plan storage. New positions capture the newly applied policy; identifier migration copies these fields too.
- Old NAS settings use the existing NAS calculator with a separate native cache. ArraySwap preserves the current audit/entry cache and avoids copying histories.
- MAX may be lowered below current exposure. Existing positions are retained; subsequent entries are blocked until capacity is available.
- Apply reads current edit values, saves NAS runtime settings and queues historical recalculation.
- Full strategy replacement still requires flat exposure. Invalid parameters, unsupported account/target combinations, running batch backtests and pending bridge events remain guarded.
- ORB position controls now sit below ML training, followed by margin, balance and strategy save/timezone controls. The right panel has a 780-pixel logical height. Resize repaints ML controls immediately; TIME MATRIX and entry-direction buttons use the same canvas transform.

## Changed Files

Production source:

- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`
- `IndicatorCodeExamples/SolAdvanced/LiqSolAdvancedNas.mqh`
- `IndicatorCodeExamples/SolAdvanced/LiqStrategyLibrary.mqh`
- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- `IndicatorCodeExamples/orb/OrbPositionRuntime.mqh`
- `IndicatorCodeExamples/orb/OrbStrategyUserLibrary.mqh`

Updated compiled artifacts:

- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.ex5`
- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.ex5`

Documentation and verification:

- `IndicatorCodeExamples/SolAdvanced/README.md`
- `IndicatorCodeExamples/orb/README.md`
- `tests/mql5/SolAdvancedPositionPolicyProbe.mq5`
- `tests/mql5/orbPositionPolicyProbe.mq5`
- `scripts/validate_orb_sol_position_policy.ps1`
- `reports/sol_apply_orb_layout_20261005.md`

MaCross, EntryLab, normal Liq, channel variants, CSV formats and listener sources
were not changed. No spread-wait execution feature was added.

## Verification Scope

The isolated MT5 worker ran scripts with Experts disabled. Native exposure,
close and modify calls were simulated; **no trading orders were submitted**.
Tests exercised Apply with two opposite owned positions, MAX=1, current edit
values, runtime reload, audit queueing, custom/preset R, retention of old
reverse ON/OFF rules, old-versus-new NAS event caches and position-plan copying.

ORB UI tests rendered 1280x720 and 1600x900 canvases, checked control existence,
panel containment, resize behavior and non-overlap, and produced screenshots
that were visually inspected.

Default historical regression used JP225m/M5, 2W, with cutoff frozen at
2026-10-02 22:00. The pre-change and final source produced identical complete
trade traces, not merely identical headline counts:

| EA | Trades | W | L | OPEN | DATA | Net R | Trace SHA256 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ORB | 10 | 6 | 4 | 0 | 0 | -1 | `80eec1ff55a3c6827374776254583db680c138cbb8cc0d1d628176744ed5f408` |
| Sol Advanced | 6 | 5 | 0 | 1 | 0 | 8.30550000 | `4a22ff889c6bdfa9a4c1902db8dcb3454eeca606930054affd0f85ab8f06a49d` |

This is a bounded regression test, not proof for every symbol, configuration or
broker execution. Existing positions predating this release acquire their policy
snapshot before the first NAS/R Apply, using the then-current settings; earlier
unrecorded settings cannot be reconstructed.

## Deployment and Evidence

- `C:\MT5\DEMO\MQL5\Experts\orb`: 47 required files, all SHA256 matched.
- `C:\MT5\DEMO\MQL5\Experts\SolAdvanced`: 23 required files, all SHA256 matched.
- Shared `NativeMarginPreview.mqh`, `NativeMarginQuote.mqh` and `ResearchFiveYearLeaderboard.mqh` already matched DEMO and were not changed.
- Workspace EX5 files were updated from the verified build.

Evidence is reused in `tmp/position_policy_20261004`: `verification.json`,
`deployment.json`, behavior-probe results, baseline/candidate replay traces,
compile logs and `ui/orbPositionLayout_1280x720.png` /
`ui/orbPositionLayout_1600x900.png`.

New position-exit settings are **MT5-native only**. This change does not add a
listener close-message protocol or retroactively edit cTrader positions.
