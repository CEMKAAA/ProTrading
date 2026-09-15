# NAS EA Family  Generated grouping. Canonical editable sources remain in `IndicatorCodeExamples/`. Do not edit this mirror independently; use `scripts/sync_workspace_ea_families.ps1` after changing canonical sources. Verify with `scripts/sync_workspace_ea_families.ps1 -Check`.  ## Entry Points 
- `NasUltimate_SATS_PartialNoBE_EA.mq5`
- `NasUltimate_StrategyLibrary.mq5`

Compile MQ5 entry points only, not MQH files. `<Trade/...>` comes from the MT5 standard Include folder.
EX5 files are copies of available root binaries; synchronization is not recompilation.
The older ORB Channel variant is retained separately; inclusion here does not upgrade it.

## Local Include Dependencies

| Used by | Includes |
| --- | --- |
| `NasStrategyModelSlot.mqh` | `NasStrategyR7Core.mqh` |
| `NasStrategyR7Core.mqh` | `NasStrategyMLCore.mqh` |
| `NasStrategyResearch.mqh` | `AuditMemoIndex.mqh` |
| `NasStrategyResearch.mqh` | `NasStrategyFeatures.mqh` |
| `NasStrategyWorkbench.mqh` | `NasStrategyInputProfile.mqh` |
| `NasStrategyWorkbench.mqh` | `NasStrategyLeaderboard.mqh` |
| `NasStrategyWorkbench.mqh` | `NasStrategyMLCore.mqh` |
| `NasStrategyWorkbench.mqh` | `NasStrategyModelSlot.mqh` |
| `NasStrategyWorkbench.mqh` | `NasStrategyPresets.mqh` |
| `NasStrategyWorkbench.mqh` | `NasStrategyResearch.mqh` |
| `NasUltimate_SATS_PartialNoBE_EA.mq5` | `LiqNarrativeMacroRegime.mqh` |
| `NasUltimate_SATS_PartialNoBE_EA.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `NasUltimate_SATS_PartialNoBE_EA.mq5` | `NasStrategyWorkbench.mqh` |
| `NasUltimate_SATS_PartialNoBE_EA.mq5` | `NasUltimate_Core.mqh` |
| `NasUltimate_SATS_PartialNoBE_EA.mq5` | `NasUltimate_ProfessionalPipeline.mqh` |
| `NasUltimate_SATS_PartialNoBE_EA.mq5` | `SuperTrend_SATS_Core.mqh` |
| `NasUltimate_StrategyLibrary.mq5` | `NasUltimate_SATS_PartialNoBE_EA.mq5` |

Shared includes may appear in several families. SHA-256 hashes are recorded in `manifest.json`.
Listeners, research data, trained models and SacredVersions are not moved or duplicated here.
