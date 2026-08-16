using TradingPlatform.BusinessLayer;

namespace ProTradingSystem.Quantower
{
    public sealed class LiqNarrativeSolVersionQuantowerListener : ProductionFileBridgeQuantowerCore
    {
        public LiqNarrativeSolVersionQuantowerListener()
        {
            Name = "Liq Narrative Sol Version - MT5 Bridge";
            Description = "Production Quantower listener for LiqNarrativeSolVersion MT5 CSV signals.";
            ConfigureDefaults(
                "%APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\LiqNarrativeSolBridge_Latest.csv",
                "LiqNarrativeSol|",
                "60",
                "JP225m,JP225,JPN225m,JPN225",
                "LNSOLQW");
        }
    }
}
