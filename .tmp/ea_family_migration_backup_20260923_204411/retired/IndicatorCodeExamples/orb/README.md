# ORB EA Family  Generated grouping. Canonical editable sources remain in `IndicatorCodeExamples/`. Do not edit this mirror independently; use `scripts/sync_workspace_ea_families.ps1` after changing canonical sources. Verify with `scripts/sync_workspace_ea_families.ps1 -Check`.  ## Entry Points 
- `OrbUltimateEA.mq5`
- `OrbUltimateEA_StrategyLibrary.mq5`
- `OrbUltimateEA_Channel.mq5`

Compile MQ5 entry points only, not MQH files. `<Trade/...>` comes from the MT5 standard Include folder.
EX5 files are copies of available root binaries; synchronization is not recompilation.
The older ORB Channel variant is retained separately; inclusion here does not upgrade it.

## Local Include Dependencies

| Used by | Includes |
| --- | --- |
| `OrbStrategyCampaignModels.mqh` | `OrbStrategyCampaignRegistry.mqh` |
| `OrbStrategyLeaderboard.mqh` | `OrbStrategyLeaderboardData.mqh` |
| `OrbStrategyLeaderboard.mqh` | `OrbStrategyLeaderboardFiveYear.mqh` |
| `OrbStrategyLeaderboard.mqh` | `OrbStrategyRegimeLeaderboard.mqh` |
| `OrbStrategyMLPipeline.mqh` | `OrbStrategyCampaignModels.mqh` |
| `OrbStrategyMLPipeline.mqh` | `OrbStrategyMLConfig.mqh` |
| `OrbStrategyMLPipeline.mqh` | `OrbStrategyMLCore.mqh` |
| `OrbStrategyMLPipeline.mqh` | `OrbStrategyMLHistory.mqh` |
| `OrbStrategyMLPipeline.mqh` | `OrbStrategyMLJobs.mqh` |
| `OrbStrategyMLPipeline.mqh` | `OrbStrategyR7Runtime.mqh` |
| `OrbStrategyModelSlot.mqh` | `OrbStrategyR7Core.mqh` |
| `OrbStrategyR7Core.mqh` | `OrbStrategyMLCore.mqh` |
| `OrbStrategyR7Runtime.mqh` | `OrbStrategyModelSlot.mqh` |
| `OrbStrategyRegimeLeaderboard.mqh` | `OrbStrategyModelSlot.mqh` |
| `OrbStrategyUserLibrary.mqh` | `OrbStrategyUserContract.mqh` |
| `OrbUltimateEA.mq5` | `AuditMemoIndex.mqh` |
| `OrbUltimateEA.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `OrbUltimateEA.mq5` | `NasUltimate_Core.mqh` |
| `OrbUltimateEA.mq5` | `OrbAdvancedAuditEngine.mqh` |
| `OrbUltimateEA.mq5` | `OrbReplayMemoEpoch.mqh` |
| `OrbUltimateEA.mq5` | `OrbStrategyPresetLibrary.mqh` |
| `OrbUltimateEA.mq5` | `OrbUltimate_ProfessionalPipeline.mqh` |
| `OrbUltimateEA.mq5` | `OrbUltimate_RegimeMatrix.mqh` |
| `OrbUltimateEA.mq5` | `TradeDayCalendarPublisher.mqh` |
| `OrbUltimateEA_Channel.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `OrbUltimateEA_Channel.mq5` | `OrbUltimate_ProfessionalPipeline_Channel.mqh` |
| `OrbUltimateEA_Channel.mq5` | `OrbUltimate_RegimeMatrix.mqh` |
| `OrbUltimateEA_Channel.mq5` | `TradeDayCalendarPublisher.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `AuditMemoIndex.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `LiqNarrativeSol_RegimeV3.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `NasUltimate_Core.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbAdvancedAuditEngine.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbReplayMemoEpoch.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbStrategyLeaderboard.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbStrategyMLCore.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbStrategyMLPipeline.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbStrategyPresetLibrary.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbStrategyUserLibrary.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbStrategyUserMetrics.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbUltimate_ProfessionalPipeline.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `OrbUltimate_RegimeMatrix.mqh` |
| `OrbUltimateEA_StrategyLibrary.mq5` | `TradeDayCalendarPublisher.mqh` |

Shared includes may appear in several families. SHA-256 hashes are recorded in `manifest.json`.
Listeners, research data, trained models and SacredVersions are not moved or duplicated here.
