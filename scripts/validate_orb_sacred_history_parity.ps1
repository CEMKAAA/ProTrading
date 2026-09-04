$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$sacredPath = Join-Path $root "IndicatorCodeExamples\SacredVersions\ORBSacredVersion.mq5"
$targets = @(
    "OrbUltimateEA.mq5",
    "A05OrbEA.mq5",
    "A10OrbEA.mq5",
    "N10OrbEA.mq5",
    "Q10OrbEA.mq5"
)

$historyFunctions = @(
    "BuildOrbForNyDate",
    "HistDailyAtr",
    "FindHistBreakoutAfterRates",
    "FindHistBreakoutAfter",
    "FindHistBreakout",
    "HasM1Displacement",
    "ResolveHistoricalEntry",
    "RateBody",
    "BodyPercentileBefore",
    "HasDisplacementRates",
    "FindFreshFvgRates",
    "AnalyzeModernSetup",
    "ModernFilterAllows",
    "SimulateTradeTicks",
    "OrbSignalAvailableTime",
    "OrbHistoricalArrowPrice",
    "HistCheckAtr",
    "HistCheckVol",
    "FindHistOperationalBreakout",
    "HistCheckDay",
    "AppendOrbWindowSignal",
    "AppendOrbAcceptedSignal",
    "AppendOrbOperationalSignal",
    "DrawOrbWindowSignal",
    "BuildHistoricalWindowSignals",
    "ProcessHistoricalPrepDay",
    "FirstOrbSignalAfter",
    "FindNewDayAcceptedReverseExit",
    "FindFilteredWindowExit",
    "FindNextHistoricalSignalAfter",
    "OrbAuditWarmupBars",
    "OrbAuditProbeSeries",
    "EnsureOrbAuditHistoryCoverage",
    "OrbResetHistoricalStats",
    "ProcessHistoricalCalcDay",
    "CancelHistoricalAuditBuild",
    "FinalizeHistoricalAudit",
    "ProcessHistoricalAuditStep"
)

function Get-MqlFunctionText([string]$source, [string]$name) {
    $match = [regex]::Match(
        $source,
        "(?m)^(?:bool|int|double|datetime|string|void|color|ulong|long)\s+" + [regex]::Escape($name) + "\s*\("
    )
    if (-not $match.Success) { throw "Function not found: $name" }

    $brace = $source.IndexOf('{', $match.Index + $match.Length)
    if ($brace -lt 0) { throw "Opening brace not found: $name" }

    $depth = 0
    $inString = $false
    $inLineComment = $false
    $inBlockComment = $false
    $escaped = $false

    for ($i = $brace; $i -lt $source.Length; $i++) {
        $ch = $source[$i]
        $next = if ($i + 1 -lt $source.Length) { $source[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($ch -eq "`n") { $inLineComment = $false }
            continue
        }
        if ($inBlockComment) {
            if ($ch -eq '*' -and $next -eq '/') { $inBlockComment = $false; $i++ }
            continue
        }
        if ($inString) {
            if ($escaped) { $escaped = $false; continue }
            if ($ch -eq '\') { $escaped = $true; continue }
            if ($ch -eq '"') { $inString = $false }
            continue
        }

        if ($ch -eq '/' -and $next -eq '/') { $inLineComment = $true; $i++; continue }
        if ($ch -eq '/' -and $next -eq '*') { $inBlockComment = $true; $i++; continue }
        if ($ch -eq '"') { $inString = $true; continue }
        if ($ch -eq '{') { $depth++; continue }
        if ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return ($source.Substring($match.Index, $i - $match.Index + 1) -replace "`r`n", "`n")
            }
        }
    }

    throw "Closing brace not found: $name"
}

$sacred = [System.IO.File]::ReadAllText($sacredPath)
$sacredFunctions = @{}
foreach ($functionName in $historyFunctions) {
    $sacredFunctions[$functionName] = Get-MqlFunctionText $sacred $functionName
}

foreach ($targetName in $targets) {
    $targetPath = Join-Path $root "IndicatorCodeExamples\$targetName"
    $target = [System.IO.File]::ReadAllText($targetPath)

    foreach ($functionName in $historyFunctions) {
        $actual = Get-MqlFunctionText $target $functionName
        if ($actual -cne $sacredFunctions[$functionName]) {
            throw "$targetName changed sacred history function: $functionName"
        }
    }
}

Write-Output "ORB sacred history parity passed for $($historyFunctions.Count) functions across $($targets.Count) production EAs."
