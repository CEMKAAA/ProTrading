# Four-EA Native Margin Panel

## Scope

Canonical sources remain in their existing family folders:

- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`
- `IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5`
- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`

Only display calculations and Sol strategy-panel spacing changed. The former
EntryLab-only, narrow SL-row preview is replaced by a readable right-panel
section next to the existing BALANCE controls. Sol displays it directly below
BALANCE; its strategy save row and panel click boundary move down accordingly.
No signal, lot normalization, order execution, audit, listener, CSV, strategy
definition or bridge risk calculation has been replaced.

## Meaning

BUY/SELL TEMINAT estimates the standalone margin for volume determined by the
EA's existing applied pip SL and native risk-sizing helper, before admission
and portfolio caps. MIN LOT separately uses SYMBOL_VOLUME_MIN. All estimates
use OrderCalcMargin and account currency. SL cash risk uses OrderCalcProfit.
Leverage comes from the account, not a hardcoded 1:500.

Minimum-volume risk overrun or insufficient free margin is orange. Unknown
quotes/connection/valid applied pip geometry are N/A. The minimum-volume margin
remains available without pip mode because margin does not depend on SL.
Margin is not an entry fee, guaranteed order acceptance or minimum safe account
equity; spread, fees, existing exposure, fills and stop-out buffers matter.

## Evidence

Stage: `.tmp/native_balance_20261002_204222`.
Validator: `scripts/validate_native_balance.ps1`.
Replay UI check: `-RunPrepared -RecompileProbes`.
All four production EAs and all four full-EA probes compile without errors or
warnings. Reports: MaCross 49/0, Orb 49/0, EntryLab 49/0, SolAdvanced 43/0
(checks/failed). The test-only viewport is 1600x900 for a hidden worker;
broker quote, margin and profit APIs remain real. Native orders and publisher
messages are not sent. The screenshot lifecycle creates backgrounds before
controls, matching a fresh EA dashboard initialization.

Deployment uses `scripts/deploy_native_balance.ps1`, which checks the complete
quoted dependency graph against the verified stage, requires the DEMO terminal
closed, backs up destination files, and verifies deployed SHA256 hashes. The
four destination folders are `orb`, `MaCrossOverOrb`, `EntryEngineLab` and
`SolAdvanced` under `C:\MT5\DEMO\MQL5\Experts`.
