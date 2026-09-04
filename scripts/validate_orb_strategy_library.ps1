$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$originalPath = Join-Path $root "IndicatorCodeExamples\OrbUltimateEA.mq5"
$strategyPath = Join-Path $root "IndicatorCodeExamples\OrbUltimateEA_StrategyLibrary.mq5"
$libraryPath = Join-Path $root "IndicatorCodeExamples\OrbStrategyPresetLibrary.mqh"

foreach ($path in @($originalPath, $strategyPath, $libraryPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing file: $path" }
}

$original = [IO.File]::ReadAllText($originalPath)
$strategy = [IO.File]::ReadAllText($strategyPath)
$library = [IO.File]::ReadAllText($libraryPath)

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
        if ($inLineComment) { if ($ch -eq "`n") { $inLineComment = $false }; continue }
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

$sacredFunctions = @(
    "BuildOrbForNyDate", "HistDailyAtr", "FindHistBreakoutAfterRates", "FindHistBreakoutAfter",
    "FindHistBreakout", "HasM1Displacement", "ResolveHistoricalEntry", "RateBody",
    "BodyPercentileBefore", "HasDisplacementRates", "FindFreshFvgRates", "AnalyzeModernSetup",
    "ModernFilterAllows", "SimulateTradeTicks", "OrbSignalAvailableTime", "OrbHistoricalArrowPrice",
    "HistCheckAtr", "HistCheckVol", "FindHistOperationalBreakout", "HistCheckDay",
    "AppendOrbWindowSignal", "AppendOrbAcceptedSignal", "AppendOrbOperationalSignal", "DrawOrbWindowSignal",
    "BuildHistoricalWindowSignals", "ProcessHistoricalPrepDay", "FirstOrbSignalAfter",
    "FindNewDayAcceptedReverseExit", "FindFilteredWindowExit", "FindNextHistoricalSignalAfter",
    "OrbAuditWarmupBars", "OrbAuditProbeSeries", "EnsureOrbAuditHistoryCoverage", "OrbResetHistoricalStats",
    "ProcessHistoricalCalcDay", "CancelHistoricalAuditBuild", "FinalizeHistoricalAudit", "ProcessHistoricalAuditStep"
)
foreach ($name in $sacredFunctions) {
    if ((Get-MqlFunctionText $original $name) -cne (Get-MqlFunctionText $strategy $name)) {
        throw "Strategy library changed sacred ORB function: $name"
    }
}

$identities = [regex]::Matches($library, 'OrbPresetIdentity\(p,"([^"]+)","([^"]+)"')
if ($identities.Count -ne 46) { throw "Expected 46 preset identities, found $($identities.Count)" }
$ids = @($identities | ForEach-Object { $_.Groups[1].Value })
$names = @($identities | ForEach-Object { $_.Groups[2].Value })
if (($ids | Sort-Object -Unique).Count -ne 46) { throw "Preset IDs are not unique" }
if (($names | Sort-Object -Unique).Count -ne 46) { throw "Preset names are not unique" }

$metrics = [regex]::Matches($library, '(?m)^\s*case\s+(\d+)\s*:\s*OrbPresetMetric1Y\(')
if ($metrics.Count -ne 46) { throw "Expected 46 frozen 1Y metrics, found $($metrics.Count)" }
$metricIndices = @($metrics | ForEach-Object { [int]$_.Groups[1].Value })
if (($metricIndices -join ',') -ne ((0..45) -join ',')) { throw "Metric indices are not contiguous 0..45" }
foreach ($field in @(
    'metric1yReady', 'metric1yAsOf', 'metric1yTotal', 'metric1yWins', 'metric1yLosses',
    'metric1yNetR', 'metric1yMinCumR', 'metric1yWr'
)) {
    if (-not $library.Contains($field)) { throw "Missing frozen metric field: $field" }
}

foreach ($excluded in @('usdjpy0.4R.png', 'usdjpyEdge.png')) {
    if ($library.Contains($excluded)) { throw "Non-ORB screenshot leaked into preset library: $excluded" }
}

$apply = Get-MqlFunctionText $strategy "OrbStrategyPresetApplyValues"
foreach ($forbidden in @(
    'g_rtRiskPerTradePct', 'g_orbBridgeChannel', 'g_orbBridgeEnabled', 'g_orbBridgeOnly',
    'g_orbNativeWithBridgeOnly', 'g_ftmoMode', 'g_riskLotOnlyMode', 'g_runtimeMagic', 'g_rtEaEnabled'
)) {
    if ($apply.Contains($forbidden)) { throw "Preset apply touches protected runtime: $forbidden" }
}

foreach ($needle in @(
    'PRESET_BLOCKED_ACTIVE_TRADE',
    'PRESET_DISABLE_PUB_FOR_TF_CHANGE_',
    'OrbStrategyPresetFamilyMatches(p.family)',
    'OrbStrategyPresetRestore();',
    'CHARTEVENT_OBJECT_ENDEDIT&&sparam==PREFIX+"EDIT_PRESET_SEARCH"',
    'OrbStrategyPresetMetricCaption(p)',
    'OrbStrategyApplyMetricFilters()',
    'BTN_PRESET_FILTER_CLEAR',
    'OrbProWriteInitMarker();',
    'QueueHistoricalRedraw(0);'
)) {
    if (-not $strategy.Contains($needle)) { throw "Missing strategy-library invariant: $needle" }
}

if ($original.Contains('OrbStrategyPresetLibrary.mqh') -or $original.Contains('APPLY STRATEGY')) {
    throw "Original production ORB was modified with experimental strategy UI"
}

Write-Output "ORB strategy library passed: 46 unique presets + 46 frozen 1Y metrics, 38 sacred functions unchanged, protected runtimes isolated."
