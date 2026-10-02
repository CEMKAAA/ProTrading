# Pip SL Ceiling Removal

## Change

Removed the artificial 1000000 pip limit in the four canonical production
EAs. Dashboard Apply, input initialization and strategy validation retain
larger finite values. EntryLab engine-policy validation and its builder
label were updated too. The generic strategy number parser now accepts an
optional limit override; only the pip SL token opts out of its original
1e12 bound. The balance input keeps its existing 1e12 safety limit.

Existing minimum pip values are unchanged: 0.1 for Orb/MaCross/EntryLab,
0 for SolAdvanced. No signal, audit lifecycle, bridge schema, listener,
commission, inversion or lot-sizing mathematics was changed.
Removing a software input ceiling does not make invalid broker prices or
unaffordable risk executable. Existing geometry/margin/risk guards remain.

## Production Source Files

- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`
- `IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5`
- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`
- `IndicatorCodeExamples/orb/NativeRiskBalance.mqh`
- `IndicatorCodeExamples/macrossover_orb/NativeRiskBalance.mqh`
- `IndicatorCodeExamples/entry_engine_lab/NativeRiskBalance.mqh`
- `IndicatorCodeExamples/SolAdvanced/NativeRiskBalance.mqh`
- `IndicatorCodeExamples/orb/OrbStrategyMLCore.mqh`
- `IndicatorCodeExamples/macrossover_orb/OrbStrategyMLCore.mqh`
- `IndicatorCodeExamples/entry_engine_lab/OrbStrategyMLCore.mqh`
- `IndicatorCodeExamples/orb/OrbStrategyUserContract.mqh`
- `IndicatorCodeExamples/macrossover_orb/OrbStrategyUserContract.mqh`
- `IndicatorCodeExamples/entry_engine_lab/OrbStrategyUserContract.mqh`
- `IndicatorCodeExamples/entry_engine_lab/LabEntryLogic.mqh`
- `IndicatorCodeExamples/entry_engine_lab/LabPolicyRuntime.mqh`
- `IndicatorCodeExamples/entry_engine_lab/LabEntryBuilder.mqh`

Regression checks: `tests/mql5/PipCeilingChecks.mqh`, integrated into
`scripts/validate_native_balance.ps1`. README and VERIFICATION updated.

## Verification

Final stage: `.tmp/native_balance_20261003_004942`.
All four production files and all four test probes: 0 errors, 0 warnings.

| Family | Checks | Failed |
| :--- | ---: | ---: |
| Orb | 87 | 0 |
| MaCross | 85 | 0 |
| EntryLab | 92 | 0 |
| SolAdvanced | 75 | 0 |
| Total | 339 | 0 |

Test inputs: 1000001, 2500000.5, 10000000000000 pips.
Exact runtime/serialization equality is required for these values.
Tests cover actual Apply handlers, strategy serialization and validation,
EntryLab custom-engine Apply and serialization, and SolAdvanced's actual
file save/unpack/assignment. Its temporary strategy and lock are deleted.
Existing native balance and real broker margin/profit tests also passed
on USDJPYm. Test scripts do not submit orders or publish entry messages.

An initial run could not connect to Exness and therefore failed broker
margin checks. A later connected full run passed all 339 checks; no failures
were relabeled as successes. The strategy-reader test exposed and fixed
the additional generic-number limit. Sol's script fixture needed ordinary
NAS and all-hours defaults because it deliberately does not run EA OnInit.

This is input/persistence regression verification, not a new forward-order
test or a rerun of all historical strategy campaigns.

## Deployment

Published 4 families / 173 files with backup and SHA256 checks:

- `C:\MT5\DEMO\MQL5\Experts\orb`
- `C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb`
- `C:\MT5\DEMO\MQL5\Experts\EntryEngineLab`
- `C:\MT5\DEMO\MQL5\Experts\SolAdvanced`

Verified EX5 files also copied to their canonical workspace folders.
Backup and deployment manifest:
`.tmp/native_balance_deploy_backup_20261003_005710`.
