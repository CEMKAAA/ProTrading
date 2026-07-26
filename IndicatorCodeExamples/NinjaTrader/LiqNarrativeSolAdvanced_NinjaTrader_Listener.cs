#region Using declarations
using System;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public class LiqNarrativeSolAdvancedNinjaTraderListener : ProductionFileBridgeNinjaCore
    {
        protected override string ListenerTitle { get { return "Liq Narrative Sol Advanced Ninja Listener"; } }
        protected override string DefaultBridgeLatestPath
        {
            get
            {
                return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
                    + "\\MetaQuotes\\Terminal\\Common\\Files\\LiqNarrativeSolAdvancedBridge_Latest.csv";
            }
        }
        protected override string DefaultSourceNamespace { get { return "LiqNarrativeSolAdvanced|"; } }
        protected override string DefaultSourceTimeframeFilter { get { return "60"; } }
        protected override bool DefaultSourceTfToChartPeriodSetting { get { return false; } }
        protected override string DefaultSourceSymbolAliasesCsv { get { return "JP225m,JP225,JPN225m,JPN225"; } }
        protected override bool DefaultRebaseMappedLevelsToLiveEntry { get { return true; } }
        protected override string DefaultOrderPrefix { get { return "LNADVNT"; } }
        protected override string DefaultAuditPrefix { get { return "LiqNarrativeSolAdvanced_Ninja_Audit_"; } }
    }
}
