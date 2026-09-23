param([string]$OriginalGitRef = "")
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$originalPath = Join-Path $root "IndicatorCodeExamples\OrbUltimateEA.mq5"
$strategyPath = Join-Path $root "IndicatorCodeExamples\orb\OrbUltimateEA_StrategyLibrary.mq5"
$libraryPath = Join-Path $root "IndicatorCodeExamples\orb\OrbStrategyPresetLibrary.mqh"

foreach ($path in @($originalPath, $strategyPath, $libraryPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing file: $path" }
}

if ($OriginalGitRef) {
    $original = (git -C $root show "${OriginalGitRef}:IndicatorCodeExamples/OrbUltimateEA.mq5") -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read specified original Git reference' }
    Write-Output "Comparison baseline: $OriginalGitRef (not the user-modified working ORB file)"
} else {
    $original = [IO.File]::ReadAllText($originalPath)
}
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
    $experimental = Get-MqlFunctionText $strategy $name
    # v6.84 intentionally separates reference statistics from the filtered
    # portfolio. These two orchestration bodies require runtime invariance tests;
    # they are not claimed to be byte-identical to the old implementation.
    if ($name -in @('ProcessHistoricalPrepDay','ProcessHistoricalCalcDay')) {
        if (-not $experimental.Contains('g_regimeReference')) { throw "Missing reference universe: $name" }
        continue
    }
    # Explicit observational hooks only; no simulation or signal expression may differ.
    $hooks = @{
        ProcessHistoricalCalcDay = '      OrbMlCapture(sigT,entryT,dir,hi,lo,oe,sim);'
        CancelHistoricalAuditBuild = '   if(g_mlExport)OrbMlAbort("EXPORT CANCELLED: AUDIT RESTARTED");'
        FinalizeHistoricalAudit = '   OrbMlAuditFinished();'
    }
    if ($hooks.ContainsKey($name)) {
        if (-not $experimental.Contains($hooks[$name])) { throw "Missing ML observer hook: $name" }
        $experimental = $experimental.Replace($hooks[$name] + "`n", '')
    }
    if ($name -eq 'CancelHistoricalAuditBuild') {
        $experimental=$experimental.Replace('   ArrayResize(g_regimeReferenceSignals,0);ArrayResize(g_regimeReferenceWindows,0);'+"`n",'')
    }
    if ($name -eq 'FinalizeHistoricalAudit') {
        $experimental=$experimental.Replace('   OrbUserAuditCompleted();'+"`n",'')
    }
    if ((Get-MqlFunctionText $original $name) -cne $experimental) {
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

$backendNames = [regex]::Matches($original, '(?m)^(?:bool|int|double|datetime|string|void|color|ulong|long)\s+(OBT_\w+)\s*\(') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($name in $backendNames) {
    if ((Get-MqlFunctionText $original $name) -cne (Get-MqlFunctionText $strategy $name)) {
        throw "Hidden Backtest Engine backend changed: $name"
    }
}
$dashboard = Get-MqlFunctionText $strategy 'UpdateDashboard'
if ($dashboard -match 'Create(?:Button|Edit|Label|Rect)\("(?:BTN_BT|EDIT_BT|DASH_BT)') {
    throw 'Backtest Engine controls must remain hidden'
}
foreach ($name in @('OrbStrategyToggleFavorite', 'OrbStrategyLoadFavorites')) {
    $body = Get-MqlFunctionText $strategy $name
    foreach ($forbidden in @('OrbStrategyPresetApply', 'QueueHistoricalRedraw', 'OrbPro', 'OrderSend', 'g_rtRisk', 'g_orbBridge')) {
        if ($body.Contains($forbidden)) { throw "Favorite operation touches trading/audit state: $name / $forbidden" }
    }
}
$favoritePath = Get-MqlFunctionText $strategy 'OrbStrategyFavoriteFile'
if (-not $favoritePath.Contains('p.id+".fav"')) { throw 'Favorites must use stable preset IDs' }
foreach ($id in $ids) {
    if ($id -notmatch '^[A-Za-z0-9_-]+$') { throw "Unsafe favorite filename ID: $id" }
}
$events = Get-MqlFunctionText $strategy 'OnChartEvent'
$guardPos = $events.IndexOf('OrbStrategyPopupContains(lparam,dparam)')
$dispatchPos = $events.IndexOf('bool needRedraw=false;')
if ($guardPos -lt 0 -or $guardPos -gt $dispatchPos) { throw 'Popup must consume covered clicks before underlying control dispatch' }
foreach ($needle in @('if(popupControl&&!g_strategyPopupOpen)return;', 'BTN_PRESET_FAVORITES', 'BTN_PRESET_STAR_',
    'if(!g_strategyPopupOpen&&g_strategyPopupDrawn)', 'for(int stale=g_strategyVisibleCount;stale<5;stale++)')) {
    if (-not $strategy.Contains($needle)) { throw "Missing popup/favorites invariant: $needle" }
}

Write-Output "ORB strategy library passed: 46 presets/metrics; 36 signal/audit bodies match baseline after removing explicit observer/reset hooks; 2 reference-stat orchestration bodies require the separate runtime invariance probe; protected runtimes isolated; $($backendNames.Count) Backtest functions unchanged; favorites/overlay source invariants passed."
