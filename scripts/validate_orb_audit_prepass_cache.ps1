$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$files = @(
    "OrbUltimateEA.mq5",
    "A05OrbEA.mq5",
    "A10OrbEA.mq5",
    "N10OrbEA.mq5",
    "Q10OrbEA.mq5"
)

function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
}

foreach ($name in $files) {
    $path = Join-Path $root "IndicatorCodeExamples\$name"
    $source = [System.IO.File]::ReadAllText($path)

    Assert-True ($source.Contains("bool FindHistBreakoutAfterRates(")) "$name has no cached-rate breakout scanner"
    Assert-True ($source.Contains("scanFromIndex=baseIndex+1;")) "$name does not advance by raw candidate index"
    Assert-True ($source.Contains("preserves overlapping N-bar confirmations exactly")) "$name lacks overlap-preservation guard"
    Assert-True ($source.Contains("int daySignalCount=CopyRates(_Symbol,g_rtSignalTf,oe,te,daySignalRates);")) "$name does not load each audit day once"
    Assert-True ($source.Contains("FindHistBreakoutAfterRates(daySignalRates,daySignalCount")) "$name prepass still uses the repeated I/O scanner"
    Assert-True ($source.Contains('g_histAuditStage="PREP";')) "$name has no preparation progress stage"
    Assert-True ($source.Contains('g_histAuditStage="CALC";')) "$name has no calculation progress stage"
    Assert-True ($source.Contains('35.0*(double)done/(double)MathMax(1,g_histRunDays)')) "$name does not expose real prepass progress"
    Assert-True ($source.Contains('40.0+60.0*(double)done/(double)MathMax(1,g_histRunDays)')) "$name does not expose real calculation progress"
    Assert-True ($source.Contains('g_histRejectedWindowRaw+=ProcessHistoricalPrepDay(g_histPrepBack);')) "$name prepass is not incrementally scheduled"

    $buildStart = $source.IndexOf("int BuildHistoricalWindowSignals(")
    $buildEnd = $source.IndexOf("bool FindNewDayAcceptedReverseExit(", $buildStart)
    Assert-True ($buildStart -ge 0 -and $buildEnd -gt $buildStart) "$name window prepass boundaries not found"
    $buildBody = $source.Substring($buildStart, $buildEnd - $buildStart)
    Assert-True (-not $buildBody.Contains("FindHistBreakoutAfter(oe,te")) "$name still performs repeated per-candidate CopyRates"

    # Accuracy invariants from the original scanner must remain in the cached helper.
    foreach ($invariant in @(
        "closeTime<effectiveFrom||closeTime>to",
        "!EntryWindowAllowsAt(closeTime)",
        "r[i].close>hi+mb",
        "r[i].close<lo-mb",
        "i + InpConfirmBars - 1 >= c",
        "r[confirmIdx].time<=afterSignalTime",
        "MathMin(20,bi)"
    )) {
        Assert-True ($source.Contains($invariant)) "$name lost breakout invariant: $invariant"
    }
}

Write-Output "ORB audit prepass cache and chronology invariants passed for $($files.Count) files."
