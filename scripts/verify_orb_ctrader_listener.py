#!/usr/bin/env python3
"""Verify ORB listener is an identity adaptation of the proven Liq listener."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = (root / "IndicatorCodeExamples/LiquidityNarrative_cTrader_Listener.cs").read_text(encoding="utf-8-sig")
dst = (root / "IndicatorCodeExamples/OrbUltimate_cTrader_Listener.cs").read_text(encoding="utf-8-sig")
expected = src
replacements = [
    ("public class LiquidityNarrativeCTraderListener : Robot", "public class OrbUltimateCTraderListener : Robot"),
    ('private const string Build = "2026-07-20.audit-writer-isolation-v3";', 'private const string Build = "2026-07-23.orb-production-v1";'),
    ("LiquidityNarrativeBridge_Latest.csv", "OrbUltimateBridge_Latest.csv"),
    ('[Parameter("Source Filter", DefaultValue = "")]', '[Parameter("Source Filter", DefaultValue = "OrbUltimate|")]'),
    ('[Parameter("Label Prefix", DefaultValue = "LN_CT")]', '[Parameter("Label Prefix", DefaultValue = "ORB_CT")]'),
    ('[Parameter("Audit File Prefix", DefaultValue = "LiquidityNarrative_cTrader_Audit_")]', '[Parameter("Audit File Prefix", DefaultValue = "OrbUltimate_cTrader_Audit_")]'),
    ("LiquidityNarrative_cTrader_Locks", "OrbUltimate_cTrader_Locks"),
    ("LiquidityNarrative_cTrader_State", "OrbUltimate_cTrader_State"),
    ("LiquidityNarrative cTrader Listener", "OrbUltimate cTrader Listener"),
    ('"LN_CT_DASH"', '"ORB_CT_DASH"'),
]
for old, new in replacements:
    assert old in expected, old
    expected = expected.replace(old, new)
assert dst == expected, "ORB listener contains changes beyond reviewed identity adaptation"
required = [
    "UseBridgeRiskPct", "Account.Equity", "ResolveVolume", "VolumeForFixedRisk",
    "FailIfExactProtectionFails", "PostFillRiskGuard", "ManageHalfClose",
    "RepairOpenPositionStates", "ClaimEvent", "CommitEvent", "ReleaseEvent",
    "PreferScopedLatest", "CloseReverseAcrossSourceTf", "PermanentRejectGuard",
    "NoMoneyRetryShrink", "MappedBasisGuardPctRisk", "JP225m=JPN225",
]
missing = [item for item in required if item not in dst]
assert not missing, missing
print("ORB cTrader listener verification: PASS")
print("base=LiquidityNarrative listener adaptation=IDENTITY_ONLY")
print("risk=LOCAL_CTRADER_CAPITAL exact_protection=ON durable_claims=ON hcbe_repair=ON jp225_map=ON")
