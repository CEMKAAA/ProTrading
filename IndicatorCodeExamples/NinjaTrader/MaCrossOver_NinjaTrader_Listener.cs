#region Using declarations
using System;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public class MaCrossOverNinjaTraderListener : ProductionFileBridgeNinjaCore
    {
        protected override string ListenerTitle { get { return "MA Crossover Ninja Listener"; } }
        protected override string DefaultBridgeLatestPath
        {
            get
            {
                return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
                    + "\\MetaQuotes\\Terminal\\Common\\Files\\MaCrossOverBridge_Latest.csv";
            }
        }
        protected override string DefaultSourceNamespace { get { return "MaCrossOver|"; } }
        protected override string DefaultSourceTimeframeFilter { get { return "5"; } }
        protected override int DefaultBridgeChannel { get { return 1; } }
        protected override bool DefaultSourceTfToChartPeriodSetting { get { return false; } }
        protected override bool RequireAcceptedSignalSealSetting { get { return true; } }
        protected override string DefaultSourceSymbolAliasesCsv { get { return "JP225m,JP225,JPN225m,JPN225"; } }
        protected override bool DefaultRebaseMappedLevelsToLiveEntry { get { return true; } }
        protected override string DefaultOrderPrefix { get { return "MACROSSNT"; } }
        protected override string DefaultAuditPrefix { get { return "MaCrossOver_Ninja_Audit_"; } }
    }
}
