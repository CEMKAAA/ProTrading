# LİQ EA Family  Generated grouping. Canonical editable sources remain in `IndicatorCodeExamples/`. Do not edit this mirror independently; use `scripts/sync_workspace_ea_families.ps1` after changing canonical sources. Verify with `scripts/sync_workspace_ea_families.ps1 -Check`.  ## Entry Points 
- `LiquidityNarrative_MT5_EA.mq5`
- `LiquidityNarrative_Invert_MT5_EA.mq5`
- `LiqNarrativeSolVersion.mq5`
- `LiqNarrativeSol_Advanced.mq5`
- `LiquidityNarrative_MT5_EA_Channel.mq5`
- `LiqNarrativeSolVersion_Channel.mq5`
- `LiqNarrativeSol_Advanced_Channel.mq5`

Compile MQ5 entry points only, not MQH files. `<Trade/...>` comes from the MT5 standard Include folder.
EX5 files are copies of available root binaries; synchronization is not recompilation.
The older ORB Channel variant is retained separately; inclusion here does not upgrade it.

## Local Include Dependencies

| Used by | Includes |
| --- | --- |
| `LiqNarrativeSol_Advanced.mq5` | `LiqNarrativeMacroRegime.mqh` |
| `LiqNarrativeSol_Advanced.mq5` | `LiqNarrativeMacroRegimeFilter.mqh` |
| `LiqNarrativeSol_Advanced.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `LiqNarrativeSol_Advanced.mq5` | `TradeDayCalendarPublisher.mqh` |
| `LiqNarrativeSol_Advanced_Channel.mq5` | `LiqNarrativeMacroRegime.mqh` |
| `LiqNarrativeSol_Advanced_Channel.mq5` | `LiqNarrativeMacroRegimeFilter.mqh` |
| `LiqNarrativeSol_Advanced_Channel.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `LiqNarrativeSol_Advanced_Channel.mq5` | `TradeDayCalendarPublisher.mqh` |
| `LiqNarrativeSolVersion.mq5` | `LiqNarrativeMacroRegime.mqh` |
| `LiqNarrativeSolVersion.mq5` | `LiqNarrativeMacroRegimeFilter.mqh` |
| `LiqNarrativeSolVersion.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `LiqNarrativeSolVersion.mq5` | `TradeDayCalendarPublisher.mqh` |
| `LiqNarrativeSolVersion_Channel.mq5` | `LiqNarrativeMacroRegime.mqh` |
| `LiqNarrativeSolVersion_Channel.mq5` | `LiqNarrativeMacroRegimeFilter.mqh` |
| `LiqNarrativeSolVersion_Channel.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `LiqNarrativeSolVersion_Channel.mq5` | `TradeDayCalendarPublisher.mqh` |

Shared includes may appear in several families. SHA-256 hashes are recorded in `manifest.json`.
Listeners, research data, trained models and SacredVersions are not moved or duplicated here.
