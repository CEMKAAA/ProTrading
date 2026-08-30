$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot

function Assert-Contains {
    param(
        [string]$RelativePath,
        [string[]]$Needles
    )

    $path = Join-Path $repo $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing file: $RelativePath"
    }
    $text = [IO.File]::ReadAllText($path)
    foreach ($needle in $Needles) {
        if (-not $text.Contains($needle)) {
            throw "Missing channel-isolation invariant in $RelativePath`: $needle"
        }
    }
}

Assert-Contains "IndicatorCodeExamples/OrbUltimate_ProfessionalPipeline.mqh" @(
    'string OrbProChannelTag(){return "C"+IntegerToString(g_orbBridgeChannel);}',
    '"risk_pct","bridge_channel"',
    'OrbProChannelEvent(eventId)',
    '"OrbUltimateBridge_Latest_"+OrbProChannelTag()'
)

Assert-Contains "IndicatorCodeExamples/IQCapital_MT5_Listener_Core.mqh" @(
    'input int    InpBridgeChannel = IQC_DEFAULT_BRIDGE_CHANNEL',
    'sig.bridgeChannel = (int)StringToInteger',
    'sig.bridgeChannel != expectedChannel',
    'bool PositionChannelMatches(ulong ticket)',
    'GlobalVariableSet(PosKey(ticket, "BCH"), sig.bridgeChannel)',
    '"AFB|C" + IntegerToString(sig.bridgeChannel)',
    '"AFBB|C" + IntegerToString(sig.bridgeChannel)',
    'StringFind(lower, "_latest_c")',
    'bool IsCloseOnlySignal(const BridgeSignal &sig)',
    'CloseSameDirectionPositions(sig, closeOnlyDetail)'
)

Assert-Contains "IndicatorCodeExamples/OrbUltimate_IQCapital_MT5_Listener_EA.mq5" @(
    '#define IQC_DEFAULT_FILE "OrbUltimateBridge_Latest_C1.csv"',
    '#define IQC_DEFAULT_BRIDGE_CHANNEL 1',
    '#define IQC_DEFAULT_PREFER_SCOPED_LATEST true',
    '#define IQC_DEFAULT_FAIL_IF_SCOPED_MISSING true'
)

foreach ($file in @(
    "IndicatorCodeExamples/OrbUltimate_cTrader_Listener.cs",
    "IndicatorCodeExamples/OrbUltimate_cTrader_Listener_Channel.cs"
)) {
    Assert-Contains $file @(
        '[Parameter("Bridge Channel"',
        'sig.Channel <= 0 || sig.Channel != BridgeChannel',
        'private IEnumerable<Position> ScopedPositions',
        'ContainsText(sig.EventId, "invalidate_close")',
        'CloseSameDirectionPositions(sig, out var closeOnlyDetail)'
    )
}

Assert-Contains "IndicatorCodeExamples/NinjaTrader/ProductionFileBridgeNinjaCore.cs" @(
    'public int BridgeChannel { get; set; }',
    'if(sig.Channel != BridgeChannel)',
    '|C" + BridgeChannel',
    'ContainsText(sig.EventId, "invalidate_close")',
    'ProcessCloseOnly(sig);',
    'ScopedTrades(sig.SourceTf).Where(t => t.Direction == sig.Direction)'
)
Assert-Contains "IndicatorCodeExamples/NinjaTrader/OrbUltimate_NinjaTrader_Listener.cs" @(
    'DefaultBridgeChannel'
)

Assert-Contains "IndicatorCodeExamples/Quantower/ProductionFileBridgeQuantowerCore.cs" @(
    'public int BridgeChannel { get; set; }',
    'if (signal.Channel != BridgeChannel)',
    '|C" + BridgeChannel',
    'ContainsText(signal.EventId, "invalidate_close")',
    'ProcessCloseOnly(signal, out detail)',
    'states.Values.Where(x => x.Direction == signal.Direction && SameText(x.SourceTf, NormalizeTf(signal.SourceTf)))'
)

Write-Output "ORB channel isolation checks passed across MT5 publisher, MT5/cTrader/NinjaTrader/Quantower listeners."
