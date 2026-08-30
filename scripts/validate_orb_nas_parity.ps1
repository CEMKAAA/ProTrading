param(
    [string]$SourceRoot = "IndicatorCodeExamples"
)

$ErrorActionPreference = "Stop"
$orbFiles = @("OrbUltimateEA.mq5", "A05OrbEA.mq5", "A10OrbEA.mq5", "N10OrbEA.mq5", "Q10OrbEA.mq5")

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Input-Value([string]$Source, [string]$Name) {
    $match = [regex]::Match($Source, "(?m)^input\s+\w+\s+" + [regex]::Escape($Name) + "\s*=\s*([^;]+);")
    if (-not $match.Success) { throw "Input not found: $Name" }
    return $match.Groups[1].Value.Trim()
}

$nasPath = Join-Path $SourceRoot "NasUltimate_SATS_PartialNoBE_EA.mq5"
$nas = [IO.File]::ReadAllText((Resolve-Path $nasPath))
$expected = @{
    InpNasSensitivity = Input-Value $nas "InpNasSensitivity"
    InpNasRsiLength   = Input-Value $nas "InpNasRsiLength"
    InpNasAtrRisk     = Input-Value $nas "InpNasAtrRisk"
    InpNasAtrLen      = Input-Value $nas "InpNasAtrLen"
    InpNasSignalCalcBars = Input-Value $nas "InpSignalCalcBars"
    InpNasHistoryBars = Input-Value $nas "InpHistoryBars"
}

Assert-True ($expected.InpNasSensitivity -eq "4") "Main NAS default sensitivity is no longer 4"
Assert-True ($nas.Contains("InpSignalBarMode = NAS_SIGNAL_BAR_CLOSED")) "Main NAS no longer defaults to closed-bar signals"

foreach ($name in $orbFiles) {
    $path = Join-Path $SourceRoot $name
    $source = [IO.File]::ReadAllText((Resolve-Path $path))

    foreach ($key in $expected.Keys) {
        Assert-True ((Input-Value $source $key) -eq $expected[$key]) "$name $key differs from the main NAS EA"
    }

    Assert-True ($source.Contains('#include "NasUltimate_Core.mqh"')) "$name does not use the shared NAS signal core"
    Assert-True ($source.Contains('NAS_Calculate(rates,copied,BuildOrbNasSettings(),points)')) "$name does not calculate the shared NAS points"
    Assert-True ($source.Contains('s.sensitivity=MathMax(1,g_rtNasSensitivity);')) "$name does not pass runtime sensitivity to the NAS core"
    Assert-True ($source.Contains('s.rsiLength=MathMax(2,InpNasRsiLength);')) "$name NAS RSI setting differs"
    Assert-True ($source.Contains('s.atrRisk=MathMax(1,InpNasAtrRisk);')) "$name NAS ATR-risk setting differs"
    Assert-True ($source.Contains('s.atrLen=MathMax(2,InpNasAtrLen);')) "$name NAS ATR length differs"
    Assert-True ($source.Contains('int NasCalcWarmupBars(){return MathMax(300,MathMin(200000,InpNasSignalCalcBars));}')) "$name does not use the 5000-bar NAS parity warm-up"
    Assert-True ($source.Contains('return "ORB_NASTF2."')) "$name still restores the legacy init-time concrete NAS timeframe"
    Assert-True ($source.Contains('return g_rtNasTimeframe==PERIOD_CURRENT?ClampNasTimeframe(g_rtSignalTf):ClampNasTimeframe(g_rtNasTimeframe);')) "$name AUTO NAS timeframe does not follow the runtime ORB Signal TF"
    Assert-True ($source.Contains('ENUM_TIMEFRAMES requested=CycleNasTimeframe(g_rtNasTimeframe);')) "$name cannot cycle through the AUTO NAS timeframe state"
    Assert-True ($source.Contains('"TF AUTO>"+TfLabel(NasConfirmationTf())')) "$name dashboard does not expose AUTO NAS timeframe resolution"
    Assert-True ($source.Contains('"BTN_NAS_TF"') -and $source.Contains('NasTimeframeButtonLabel(),C')) "$name NAS TF button does not use the AUTO-aware label"
    Assert-True (-not $source.Contains(':(NasTimeframeButtonLabel());')) "$name NAS TF label recursively calls itself"
    Assert-True ($source.Contains('if(g_rtNasTimeframe==PERIOD_CURRENT)g_lastNasOverlayClosedBar=0;')) "$name does not invalidate the NAS overlay when its followed Signal TF changes"
    Assert-True ($source.Contains('int NasHistoryBars(){return MathMax(300,MathMin(200000,InpNasHistoryBars));}')) "$name does not use the standalone NAS history depth"
    Assert-True ($source.Contains('void NormalizeOrbNasRates(MqlRates &rates[],const int copied)')) "$name does not normalize NAS rates chronologically"
    Assert-True ($source.Contains('int LoadOrbNasRatesThrough(MqlRates &rates[],ENUM_TIMEFRAMES tf,datetime throughTime,const int barsToCopy)')) "$name has no point-in-time NAS loader"
    Assert-True ($source.Contains('datetime OrbNasSignalAvailableTime(const MqlRates &rates[],const int copied,const int index)')) "$name does not share closed-bar availability semantics"
    Assert-True ($source.Contains('return rates[index+1].time;')) "$name does not use the next existing market bar as NAS availability"

    Assert-True ($source.Contains('int DrawNasSignalOverlay(int days,datetime now)')) "$name has no historical NAS overlay"
    Assert-True ($source.Contains('void RefreshNasSignalOverlay()')) "$name has no live closed-bar NAS overlay refresh"
    Assert-True ($source.Contains('"WINDOW NAS "+dir+" ["+TfLabel(tf)+" S"')) "$name NAS markers are not explicitly labelled"
    Assert-True ($source.Contains('int requested=MathMax(NasHistoryBars(),neededBars);')) "$name historical overlay does not match standalone history warm-up"
    Assert-True ($source.Contains('for(int i=1;i<=copied-2;i++)')) "$name NAS scan does not explicitly exclude the live bar"
    Assert-True ($source.Contains('g_lastNasOverlaySignalCount=drawn;')) "$name does not expose the raw NAS parity count"
    $overlay = [regex]::Match($source, "(?s)bool NasOverlayEnabled\(\).*?(?=void DrawLevels\(\))").Value
    Assert-True ($overlay.Length -gt 0) "$name NAS overlay block is missing"
    Assert-True (-not $overlay.Contains("OrbProPublish") -and -not $overlay.Contains("PositionClose") -and -not $overlay.Contains("trade.")) "$name NAS overlay can mutate execution or bridge state"
    Assert-True (-not $overlay.Contains('BarCloseTime(tf,rates[i].time)')) "$name NAS overlay still uses theoretical bar-close timestamps"

    Assert-True ($source.Contains('input string          InpNasOppositeExitWait = "00:00";')) "$name has no default-safe OPP EXIT grace input"
    Assert-True ($source.Contains('datetime NasOppositeExitScanExclusive(datetime openedAt)')) "$name has no exit-grace boundary resolver"
    Assert-True ($source.Contains('MathMax(NasOppositeExitScanExclusive(g_nasManagedStartAt),g_nasManagedLastScanAt)')) "$name live NAS exit ignores the grace boundary"
    Assert-True (([regex]::Matches($source, 'FindNasTransitionAfter\(execDir=="BUY"\?"SELL":"BUY",NasOppositeExitScanExclusive\(entryT\)')).Count -ge 2) "$name historical/optimizer NAS exits do not share the grace boundary"
    Assert-True ($source.Contains('RuntimeNasExitWaitKey()')) "$name does not persist the exit grace per chart instance"
    Assert-True ($source.Contains('EDIT_NAS_EXIT_WAIT')) "$name does not expose the exit grace on the dashboard"
}

$entry = [datetime]"2026-08-30T10:00:00"
$eligible = $entry.AddMinutes(120)
Assert-True ([datetime]"2026-08-30T11:59:59" -lt $eligible) "A signal inside the grace period was admitted"
Assert-True ([datetime]"2026-08-30T12:00:00" -ge $eligible) "A signal at the grace boundary was rejected"

Write-Output "ORB/NAS parity, overlay isolation, and OPP EXIT grace checks passed for $($orbFiles.Count) files."
