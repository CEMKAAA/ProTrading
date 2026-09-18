using TradingPlatform.BusinessLayer;

namespace ProTradingSystem.Quantower
{
    public sealed class MaCrossOverQuantowerListener : ProductionFileBridgeQuantowerCore
    {
        protected override bool RequireAcceptedSignalSeal { get { return true; } }

        public MaCrossOverQuantowerListener()
        {
            Name = "MA Crossover - MT5 Bridge";
            Description = "Production Quantower listener for MaCrossOver MT5 CSV signals.";
            ConfigureDefaults(
                "%APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\MaCrossOverBridge_Latest.csv",
                "MaCrossOver|",
                "5",
                "JP225m,JP225,JPN225m,JPN225",
                "MACROSSQW");
            BridgeChannel = 1;
        }
    }
}
