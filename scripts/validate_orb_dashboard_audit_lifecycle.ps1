$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$files = @(
    'OrbUltimateEA.mq5',
    'A05OrbEA.mq5',
    'A10OrbEA.mq5',
    'N10OrbEA.mq5',
    'Q10OrbEA.mq5'
)
$referencePath = Join-Path $root 'IndicatorCodeExamples/OrbUltimateEA.mq5'
$referenceText = [IO.File]::ReadAllText($referencePath)
$sharedFunctions = @(
    'bool FindNasConfirmation(string dir',
    'bool FindNasTransitionAfter(string wantedDir',
    'bool FindLatestNasSignalAfter(datetime afterExclusive',
    'bool SimulateTradeTicks(datetime sigTime',
    'HistResult SimulateTrade(datetime sigTime',
    'int BuildHistoricalWindowSignals(int days',
    'void DrawHistoricalSignals()'
)

function Get-FunctionBody([string]$text, [string]$signature) {
    $start = $text.IndexOf($signature)
    if ($start -lt 0) { throw "Missing function: $signature" }
    $open = $text.IndexOf('{', $start)
    $depth = 0
    for ($i = $open; $i -lt $text.Length; $i++) {
        if ($text[$i] -eq '{') { $depth++ }
        elseif ($text[$i] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $text.Substring($start, $i - $start + 1) }
        }
    }
    throw "Unclosed function: $signature"
}

foreach ($name in $files) {
    $path = Join-Path $root "IndicatorCodeExamples/$name"
    $text = [IO.File]::ReadAllText($path)

    foreach ($required in @(
        'g_histRedrawQueued',
        'g_histAuditCancelRequested',
        'const ulong budgetMs=30;',
        'EventSetMillisecondTimer(200);',
        'ProcessHistoricalPrepDay(g_histPrepBack)',
        'ProcessHistoricalCalcDay(g_histCalcBack)',
        'QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;',
        'ProcessQueuedHistoricalRedraw();',
        'sim.outcome=="SL"',
        'sim.outcome=="NAS_OPPOSITE_EXIT"',
        'sim.outcome=="NEW_DAY_REVERSE_EXIT"',
        'AUD QUEUED',
        'NAS_VOL_BLOCKED_CLOSE_PENDING',
        'ClearNasPending("nas_volume_toggled")',
        'NAS-X',
        'DAY-REV'
        'BuildHistoricalNasEventCache(days,currentTime,nasCacheDetail);'
        'NAS_CACHE_OK'
        'g_histActiveGeneration'
        'BeginHistoricalSnapshot();'
        'CommitHistoricalSnapshot();'
        'ResolveHistoricalForcedExitPrice(forcedExitTime'
        'CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL'
        'CopyRates(_Symbol,PERIOD_M1,eventTime-60,eventTime+120,m1)'
        'RenderHistoricalAuditProgress();'
    )) {
        if (-not $text.Contains($required)) { throw "$name missing lifecycle invariant: $required" }
    }

    $eventStart = $text.IndexOf('void OnChartEvent(')
    if ($eventStart -lt 0) { throw "$name missing OnChartEvent" }
    $eventBody = $text.Substring($eventStart)
    if ($eventBody.Contains('DrawHistoricalSignals();')) {
        throw "$name still executes the blocking historical rebuild inside OnChartEvent"
    }
    if ($eventBody.Contains('NAS_VOL_BLOCKED_ACTIVE_LIFECYCLE')) {
        throw "$name still makes the NAS VOL toggle appear frozen during an owned lifecycle"
    }
    if ($text.Contains('Sleep(2);')) {
        throw "$name still uses a cosmetic blocking progress yield"
    }

    $drawHist = Get-FunctionBody $text 'void DrawHistoricalSignals()'
    $coverageAt = $drawHist.IndexOf('if(!EnsureOrbAuditHistoryCoverage')
    $beginAt = $drawHist.IndexOf('BeginHistoricalSnapshot();')
    if ($coverageAt -lt 0 -or $beginAt -lt 0) { throw "$name historical snapshot lifecycle incomplete" }
    if ($drawHist.Substring($coverageAt, $beginAt - $coverageAt).Contains('DeleteHist();')) {
        throw "$name deletes the visible historical snapshot while history coverage is pending"
    }
    $finalize = Get-FunctionBody $text 'void FinalizeHistoricalAudit()'
    if (-not $finalize.Contains('CommitHistoricalSnapshot();')) { throw "$name does not atomically commit the completed generation" }

    $timer = Get-FunctionBody $text 'void OnTimer()'
    $tradeAt = $timer.IndexOf('TryOpenSignal();ManagePositions();ProcessNasOppositeExit();')
    $auditAt = $timer.IndexOf('ProcessHistoricalAuditStep();')
    if ($tradeAt -lt 0 -or $auditAt -le $tradeAt) { throw "$name lets history work run before live execution management" }

    $forcedResolver = Get-FunctionBody $text 'bool ResolveHistoricalForcedExitPrice('
    if (-not $forcedResolver.Contains('COPY_TICKS_ALL') -or -not $forcedResolver.Contains('PERIOD_M1')) {
        throw "$name forced exit resolver is not tick/M1 bounded"
    }
    $sim = Get-FunctionBody $text 'HistResult SimulateTrade(datetime sigTime'
    foreach ($requiredForced in @('forcedSlHit','forcedTargetHit','res.exitPrice=forcedPrice','SimSignedR(isBuy,entry,px,risk)')) {
        if (-not $sim.Contains($requiredForced)) { throw "$name forced-exit R invariant missing: $requiredForced" }
    }
    $tickSim = Get-FunctionBody $text 'bool SimulateTradeTicks(datetime sigTime'
    foreach ($requiredTickForced in @('forcedSlHit','forcedTargetHit','res.exitPrice=closePx')) {
        if (-not $tickSim.Contains($requiredTickForced)) { throw "$name tick forced-exit invariant missing: $requiredTickForced" }
    }

    $breakout = Get-FunctionBody $text 'bool FindHistOperationalBreakout('
    if ($breakout.Contains('OrbNasVolumeFilterAllows')) {
        throw "$name NAS volume filter leaked into the independent ORB breakout engine"
    }
    foreach ($signature in @('bool FindNasConfirmation(string dir','bool FindNasTransitionAfter(string wantedDir','bool FindLatestNasSignalAfter(datetime afterExclusive')) {
        $nasLookup = Get-FunctionBody $text $signature
        if (-not $nasLookup.Contains('g_histNasCacheActive')) { throw "$name NAS historical lookup bypasses the immutable cache: $signature" }
    }
    foreach ($signature in $sharedFunctions) {
        $actual = (Get-FunctionBody $text $signature) -replace "`r`n", "`n"
        $expected = (Get-FunctionBody $referenceText $signature) -replace "`r`n", "`n"
        if ($actual -ne $expected) { throw "$name diverged from production ORB shared function: $signature" }
    }

    $reset = 'g_histStopLossExits=0;g_histNasOppositeExits=0;g_histNewDayReverseExits=0;'
    $resetCount = ([regex]::Matches($text, [regex]::Escape($reset))).Count
    if ($resetCount -ne 1) { throw "$name must reset exit counters once at audit initialization; actual=$resetCount" }
}

Write-Host "ORB atomic snapshot, NAS cache, responsive progress and exact forced-exit checks passed for $($files.Count) files."
