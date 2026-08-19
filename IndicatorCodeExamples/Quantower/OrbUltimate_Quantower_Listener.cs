using TradingPlatform.BusinessLayer;

namespace ProTradingSystem.Quantower
{
    public sealed class OrbUltimateQuantowerListener : ProductionFileBridgeQuantowerCore
    {
        public OrbUltimateQuantowerListener()
        {
            Name = "ORB Ultimate - MT5 Bridge";
            Description = "Production Quantower listener for OrbUltimate MT5 CSV signals.";
            ConfigureDefaults(
                "%APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\OrbUltimateBridge_Latest.csv",
                "OrbUltimate|",
                "15",
                "JP225m,JP225,JPN225m,JPN225",
                "ORBQW");
            BridgeChannel = 1;
        }
    }
}
