"""Source-contract checks, not broker execution simulation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "IndicatorCodeExamples"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8-sig")


def main():
    for platform, suffix, old, new in (
        ("NinjaTrader", "NinjaTrader", "ORBNT", "MACROSSNT"),
        ("Quantower", "Quantower", "ORBQW", "MACROSSQW"),
    ):
        base = read(f"{platform}/OrbUltimate_{suffix}_Listener.cs")
        expected = (base.replace("OrbUltimate", "MaCrossOver")
                    .replace("ORB Ultimate", "MA Crossover")
                    .replace(old, new).replace('"15"', '"5"'))
        assert read(f"{platform}/MaCrossOver_{suffix}_Listener.cs") == expected
        core = read(f"{platform}/ProductionFileBridge{platform if platform == 'Quantower' else 'Ninja'}Core.cs")
        identity = ("channel_filter", "source_filter", "tf_filter") if platform == "NinjaTrader" else (
            "signal.Channel != BridgeChannel", "SourceTimeframeFilter", "expectedSource")
        for invariant in (*identity, "acceptance_seal_missing", "IsCloseOnlySignal", "RiskBudget"):
            assert invariant in core, (platform, invariant)
    ct = read("macrossover_orb/MaCrossOver_cTrader_Listener.cs")
    for invariant in ("MaCrossOverBridge_Latest.csv", 'DefaultValue = "MaCrossOver|"',
                      'DefaultValue = "MACROSS_CT"', '"|TF"', "channel_filter",
                      "source_filter", "tf_filter", "acceptance_seal_missing",
                      'BlockOrderRetry(sig, "close_failed", "close_only_retry", 10)',
                      "PositionOwnedByThisBridge", "QueueEmergencyClose", "PartialClosed"):
        assert invariant in ct, invariant
    publisher = read("macrossover_orb/OrbUltimate_ProfessionalPipeline.mqh")
    for invariant in ("MaCrossOverBridge_Latest_", '"MaCrossOver|"', "|ACCEPTED1",
                      "accepted_signal=1", "risk_pct", "bridge_channel"):
        assert invariant in publisher, invariant
    print("PASS: 2 identity-only futures adapters; cTrader and publisher source contracts")


if __name__ == "__main__":
    main()
