param(
    [string]$SourceRoot = "IndicatorCodeExamples"
)

$ErrorActionPreference = "Stop"
$orbFiles = @("OrbUltimateEA.mq5", "A05OrbEA.mq5", "A10OrbEA.mq5", "N10OrbEA.mq5", "Q10OrbEA.mq5")

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($name in $orbFiles) {
    $path = Join-Path $SourceRoot $name
    $source = [IO.File]::ReadAllText((Resolve-Path $path))

    Assert-True ($source.Contains('bool ExtractForexPair(const string symbol,string &base,string &quote)')) "$name has no broker-safe FX pair detector"
    Assert-True ($source.Contains('if(ExtractForexPair(s,fxBase,fxQuote))return ResolveForexSessionProfile(fxBase,fxQuote);')) "$name AUTO mode does not resolve FX pairs"
    Assert-True ($source.Contains('if(base=="JPY"||quote=="JPY"')) "$name does not prioritize Tokyo for JPY crosses"
    Assert-True ($source.Contains('bool IsAutoUsdJpyUtcSession()')) "$name has no explicit AUTO USDJPY UTC00 resolver"
    Assert-True ($source.Contains('return ExtractForexPair(_Symbol,base,quote)&&base=="USD"&&quote=="JPY";')) "$name does not identify broker-suffixed USDJPY safely"
    Assert-True ($source.Contains('return InpUtcMidnightSessionDefault||IsAutoUsdJpyUtcSession();')) "$name does not default AUTO USDJPY to UTC00"
    Assert-True ($source.Contains('string scope=IsAutoUsdJpyUtcSession()?"ORB_UJUTC1.":"ORB_UTC00.";')) "$name can restore a stale generic OFF state over the USDJPY UTC00 default"
    Assert-True ($source.Contains('return ORB_SESSION_FX_SYDNEY;')) "$name has no Sydney FX profile"
    Assert-True ($source.Contains('return ORB_SESSION_FX_LONDON;')) "$name has no London FX profile"
    Assert-True ($source.Contains('return ORB_SESSION_FX_NEW_YORK;')) "$name has no New York FX profile"
    Assert-True ($source.Contains('if(p==ORB_SESSION_FX_SYDNEY)return IsSydneyDstDate(y,mo,d)?11*3600:10*3600;')) "$name Sydney profile is not DST-aware"
    Assert-True ($source.Contains('if(p==ORB_SESSION_FX_LONDON)return IsEuropeDstDate(y,mo,d)?1*3600:0;')) "$name London FX profile is not DST-aware"
    Assert-True ($source.Contains('if(p==ORB_SESSION_FX_NEW_YORK)return NyUtcOffsetSecondsForDate(y,mo,d);')) "$name New York FX profile is not DST-aware"

    $sessionLocal = [regex]::Match($source, '(?s)datetime SessionLocalToServer\(.*?\n\}').Value
    $sessionClock = [regex]::Match($source, '(?s)void SessionClockMinutes\(.*?\n\}').Value
    Assert-True ($sessionLocal.StartsWith('datetime SessionLocalToServer')) "$name SessionLocalToServer block is missing"
    Assert-True ($sessionClock.StartsWith('void SessionClockMinutes')) "$name SessionClockMinutes block is missing"
    Assert-True ($sessionLocal.IndexOf('if(g_rtUtcMidnightSession)') -lt $sessionLocal.IndexOf('ORB_SESSION_PROFILE p=ResolveSessionProfile();')) "$name UTC00 no longer has priority over AUTO session resolution"
    Assert-True ($sessionClock.IndexOf('if(g_rtUtcMidnightSession)') -lt $sessionClock.IndexOf('ORB_SESSION_PROFILE p=ResolveSessionProfile();')) "$name UTC00 clock path no longer has priority"

    $utcToggle = [regex]::Match($source, '(?s)else if\(sparam==PREFIX\+"BTN_UTC_SESSION"\).*?QueueHistoricalRedraw\(\);UpdateDashboard\(\);ChartRedraw\(0\);return;').Value
    Assert-True ($utcToggle.Length -gt 0) "$name UTC00 dashboard handler is missing"
    Assert-True (-not $utcToggle.Contains('||g_retestPending||g_imbPending')) "$name still blocks UTC00 on disposable pending candidates"
    Assert-True ($utcToggle.Contains('else if(OwnPositionExists())') -and $utcToggle.Contains('else if(g_orbBridgePlanActive)')) "$name can change session mode while real native/bridge exposure exists"
    Assert-True ($utcToggle.Contains('ClearRetestState("session_changed");') -and $utcToggle.Contains('ClearImbalanceState("session_changed");') -and $utcToggle.Contains('ClearNasPending("session_changed");')) "$name does not invalidate old-session pending geometry after a UTC00 switch"
}

Write-Output "ORB FX AUTO session and UTC00-priority checks passed for $($orbFiles.Count) files."
