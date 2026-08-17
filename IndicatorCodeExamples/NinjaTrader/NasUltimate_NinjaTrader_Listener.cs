#region Using declarations
using System;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public class NasUltimateNinjaTraderListener : ProductionFileBridgeNinjaCore
    {
        protected override string ListenerTitle { get { return "NAS Ultimate Ninja Listener"; } }
        protected override string DefaultBridgeLatestPath
        {
            get
            {
                return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
                    + "\\MetaQuotes\\Terminal\\Common\\Files\\NasUltimateBridge_Latest.csv";
            }
        }

        protected override string DefaultSourceNamespace { get { return "NasUltimate|"; } }
        protected override string DefaultSourceTimeframeFilter { get { return "5"; } }
        protected override bool DefaultSourceTfToChartPeriodSetting { get { return false; } }
        protected override string DefaultSourceSymbolAliasesCsv { get { return "BTCUSDm,BTCUSD,BTCUSDT,XBTUSD"; } }
        protected override bool DefaultRebaseMappedLevelsToLiveEntry { get { return true; } }
        protected override bool DefaultRebaseOnlyWhenSourceDiffersSetting { get { return false; } }
        protected override string DefaultOrderPrefix { get { return "NASNT"; } }
        protected override string DefaultAuditPrefix { get { return "NasUltimate_Ninja_Audit_"; } }
    }
}
