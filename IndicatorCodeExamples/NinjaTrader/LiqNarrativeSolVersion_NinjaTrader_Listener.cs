#region Using declarations
using System;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public class LiqNarrativeSolVersionNinjaTraderListener : ProductionFileBridgeNinjaCore
    {
        protected override string ListenerTitle { get { return "Liq Narrative Sol Version Ninja Listener"; } }
        protected override string DefaultBridgeLatestPath
        {
            get
            {
                return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
                    + "\\MetaQuotes\\Terminal\\Common\\Files\\LiqNarrativeSolBridge_Latest.csv";
            }
        }
        protected override string DefaultSourceNamespace { get { return "LiqNarrativeSol|"; } }
        protected override string DefaultSourceTimeframeFilter { get { return "60"; } }
        protected override bool DefaultSourceTfToChartPeriodSetting { get { return false; } }
        protected override string DefaultSourceSymbolAliasesCsv { get { return "JP225m,JP225,JPN225m,JPN225"; } }
        protected override bool DefaultRebaseMappedLevelsToLiveEntry { get { return true; } }
        protected override string DefaultOrderPrefix { get { return "LNSOLNT"; } }
        protected override string DefaultAuditPrefix { get { return "LiqNarrativeSolVersion_Ninja_Audit_"; } }
    }
}
