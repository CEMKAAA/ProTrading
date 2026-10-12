# Frontier Strategy Selection Filters

## Shipped Behavior

- Sol Advanced strategy panel now has `R =`, `APPLY`, `CLEAR` and `MODE`.
- ORB, MaCross and Entry Lab retain their `TP/SL R =` / `APPLY FILTER` controls and now have `MODE` beneath the window/sort controls.
- `MODE` cycles `ALL -> LEGACY -> INDEPENDENT -> ALL` and immediately rebuilds the search results, starting at page 1.
- Mode comes from the saved strategy, not the currently running EA, strategy name, historical trade count or an archived result snapshot.
- Old records without Independent metadata and immutable built-in/image presets remain Legacy.
- R means the saved target/initial-stop architecture, not realized audit Net R. Fixed and saved custom R values are supported.
- An inverted 0.5R strategy still matches 0.5R, not 2R. The old reciprocal comparison in the three ORB-derived screens was removed.
- Exact R filtering uses relative tolerance so distinct tiny custom ratios are not merged by the former absolute 0.000001 tolerance.
- Dynamic target models have no one fixed architecture ratio and are excluded only when the R filter is enabled. Blank R means all architectures.
- The filters intersect with the existing query, favorites, pair, selected-window metric filters and sorting. Missing metrics do not exclude a strategy unless a metric threshold is enabled.
- CLEAR resets mode and R filters; it does not alter saved strategies, runtime execution settings, open positions or campaign results.
- Sol's filter rows have dedicated space above the results popup; lower balance/margin/save controls were moved down by 30 pixels.

## Changed Production Sources

- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`
- `IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5`
- `IndicatorCodeExamples/SolAdvanced/LiqStrategyLibrary.mqh`
- Corresponding four canonical `.ex5` binaries were rebuilt.

No signal generation, audit lifecycle, strategy serialization, order placement, CSV, web or listener code was changed.

## Verification

Four canonical EAs: **0 errors, 0 warnings**. Compile logs are in `reports/verification_build/strategy_selection`.

Native MQL scripts include the actual canonical EA implementations with their event entry points renamed. They do not initialize the production EA or place orders. Tests reuse the existing isolated worker and a fixed bounded build folder; no terminal/history clone or multi-year download is created.

| Family | Checks | Failures |
| --- | ---: | ---: |
| ORB | 40 | 0 |
| MaCross | 40 | 0 |
| Sol Advanced | 54 | 0 |
| Entry Lab | 40 | 0 |
| Total | 174 | 0 |

Coverage: default admission, Legacy/Independent, combined R+mode, inverted architecture, custom tiny ratios, dynamic models, missing metrics, old built-ins, result scanning and restored all-mode counts. Sol additionally covers decimal parsing, actual save/read of isolated temporary fixtures, custom R independence from the active runtime, actual Apply/Clear click handling, rendering and vertical row separation.

The first Sol probe stopped because its uninitialized test-only day-hour masks produced invalid temporary records. The fixture now seeds valid all-hours masks without changing production behavior. The corrected complete run passed. Successful probe records are deleted. Cleanup of the three small invalid failed-run fixtures was rejected by the command policy; they remain under `LiqStrategies` with the `__SELECTION_TEST_24678265_` name prefix and are excluded by the normal record validator.

Visual inspection: `StrategySelectionSol.png` shows the native strategy panel and non-overlapping filter/results rows. No full historical audit was rerun: this is a search/UI-only change, not a new market-result verification.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate_strategy_selection_filters.ps1 -CompileProduction`.

## Deployment

Verified MQ5/EX5 pairs were copied to DEMO `Experts/orb`, `Experts/MaCrossOverOrb`, `Experts/SolAdvanced`, `Experts/EntryEngineLab`, plus the changed Sol `LiqStrategyLibrary.mqh`. SHA-256 readback is in `reports/verification_build/strategy_selection/deployment.json`.

An EA instance already loaded in MT5 must be reattached/restarted to run the new binary; file deployment does not hot-replace the code in a running chart instance.
