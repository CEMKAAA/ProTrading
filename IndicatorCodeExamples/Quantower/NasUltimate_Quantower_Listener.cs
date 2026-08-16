using TradingPlatform.BusinessLayer;

namespace ProTradingSystem.Quantower
{
    public sealed class NasUltimateQuantowerListener : ProductionFileBridgeQuantowerCore
    {
        public NasUltimateQuantowerListener()
        {
            Name = "NAS Ultimate - MT5 Bridge";
            Description = "Production Quantower listener for NasUltimate SATS PartialNoBE MT5 CSV signals.";
            ConfigureDefaults(
                "%APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\NasUltimateBridge_Latest.csv",
                "NasUltimate|",
                "5",
                "BTCUSDm,BTCUSD,BTCUSDT,XBTUSD",
                "NASQW");
        }
    }
}
