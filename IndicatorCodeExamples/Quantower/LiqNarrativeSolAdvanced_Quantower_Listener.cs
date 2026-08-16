using TradingPlatform.BusinessLayer;

namespace ProTradingSystem.Quantower
{
    public sealed class LiqNarrativeSolAdvancedQuantowerListener : ProductionFileBridgeQuantowerCore
    {
        public LiqNarrativeSolAdvancedQuantowerListener()
        {
            Name = "Liq Narrative Sol Advanced - MT5 Bridge";
            Description = "Production Quantower listener for LiqNarrativeSolAdvanced MT5 CSV signals.";
            ConfigureDefaults(
                "%APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\LiqNarrativeSolAdvancedBridge_Latest.csv",
                "LiqNarrativeSolAdvanced|",
                "60",
                "JP225m,JP225,JPN225m,JPN225",
                "LNADVQW");
        }
    }
}
