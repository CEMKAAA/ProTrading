#!/usr/bin/env python3
"""Verify NAS cTrader listener is the proven Liq listener plus one NAS guard."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = (root / "IndicatorCodeExamples/LiquidityNarrative_cTrader_Listener.cs").read_text(encoding="utf-8-sig")
dst = (root / "IndicatorCodeExamples/NasUltimate_cTrader_Listener.cs").read_text(encoding="utf-8-sig")
expected = src
expected = expected.replace("LiquidityNarrativeCTraderListener", "NasUltimateCTraderListener")
expected = expected.replace("LiquidityNarrativeBridge", "NasUltimateBridge")
expected = expected.replace("LiquidityNarrative_cTrader", "NasUltimate_cTrader")
expected = expected.replace("LiquidityNarrative cTrader Listener", "NAS Ultimate cTrader Listener")
expected = expected.replace("LiquidityNarrative_cTrader_Audit_", "NasUltimate_cTrader_Audit_")
expected = expected.replace('DefaultValue = "LN_CT"', 'DefaultValue = "NAS_CT"')
expected = expected.replace(
    '[Parameter("Source Filter", DefaultValue = "")]',
    '[Parameter("Source Filter", DefaultValue = "NasUltimate")]',
)
expected = expected.replace(
    'private const string Build = "2026-07-20.audit-writer-isolation-v3";',
    'private const string Build = "2026-07-22.nas-production-listener-v2-single-order";',
)
identity_tail = """            return true;
        }

        private string ResolveBridgeReadPath()"""
single_order_guard = """            if (!ContainsText(sig.Source, "|shape=single_order"))
            {
                reason = $"execution_shape_filter source={sig.Source} expected=single_order";
                return false;
            }
            return true;
        }

        private string ResolveBridgeReadPath()"""
assert identity_tail in expected
expected = expected.replace(identity_tail, single_order_guard)
assert dst == expected, "listener contains changes beyond identity adaptation plus the reviewed NAS single-order guard"

required = [
    "UseBridgeRiskPct", "Account.Equity", "ResolveVolume", "VolumeForFixedRisk",
    "AmountRisked", "FailIfExactProtectionFails", "PostFillRiskGuard",
    "ManageHalfClose", "RepairOpenPositionStates", "ClaimEvent", "CommitEvent",
    "ReleaseEvent", "PreferScopedLatest", "CloseReverseAcrossSourceTf",
    "PermanentRejectGuard", "NoMoneyRetryShrink", "MappedBasisGuardPctRisk",
]
missing = [item for item in required if item not in dst]
assert not missing, missing
assert "NasUltimateBridge_Latest.csv" in dst
assert 'DefaultValue = "NAS_CT"' in dst
assert 'DefaultValue = "NasUltimate"' in dst
assert "execution_shape_filter" in dst and "|shape=single_order" in dst

print("NAS cTrader listener verification: PASS")
print("base=LiquidityNarrative listener adaptation=IDENTITY_PLUS_SINGLE_ORDER_GUARD")
print("risk=LOCAL_CTRADER_CAPITAL exact_protection=ON durable_claims=ON hcbe_repair=ON")
