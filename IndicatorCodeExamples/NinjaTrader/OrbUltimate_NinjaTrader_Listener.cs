#region Using declarations
using System;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public class OrbUltimateNinjaTraderListener : ProductionFileBridgeNinjaCore
    {
        protected override string ListenerTitle { get { return "ORB Ultimate Ninja Listener"; } }
        protected override string DefaultBridgeLatestPath
        {
            get
            {
                return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
                    + "\\MetaQuotes\\Terminal\\Common\\Files\\OrbUltimateBridge_Latest.csv";
            }
        }
        protected override string DefaultSourceNamespace { get { return "OrbUltimate|"; } }
        protected override string DefaultSourceTimeframeFilter { get { return "15"; } }
        protected override bool DefaultSourceTfToChartPeriodSetting { get { return false; } }
        protected override string DefaultSourceSymbolAliasesCsv { get { return "JP225m,JP225,JPN225m,JPN225"; } }
        protected override bool DefaultRebaseMappedLevelsToLiveEntry { get { return true; } }
        protected override string DefaultOrderPrefix { get { return "ORBNT"; } }
        protected override string DefaultAuditPrefix { get { return "OrbUltimate_Ninja_Audit_"; } }
    }
}
