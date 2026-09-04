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
    Assert-True ($source.Contains("int daySignalCount=CopyRates(_Symbol,g_rtSignalTf,oe,te,daySignalRates);")) "$name changed the strategy-defining sacred post-ORB volume universe"
    Assert-True ($source.Contains("FindHistBreakoutAfterRates(daySignalRates,daySignalCount")) "$name prepass still uses the repeated I/O scanner"
    Assert-True ($source.Contains('MqlRates r[];int c=CopyRates(_Symbol,g_rtSignalTf,from,to,r);')) "$name fallback scanner changed the sacred post-ORB volume universe"
    Assert-True (-not $source.Contains('LoadHistoricalSignalDayRates(')) "$name still rewrites sacred history with pre-ORB volume bars"
    Assert-True ($source.Contains('MqlRates d1[];ArraySetAsSeries(d1,true);')) "$name changed the sacred manual historical ATR"
    Assert-True ($source.Contains('double atr=HistDailyAtr(g_orbStartServer,InpAtrPeriod);')) "$name live and history ATR implementations can diverge"
    Assert-True ($source.Contains('CopyRates(_Symbol,g_rtSignalTf,g_orbEndServer,signalBar-1,prior)')) "$name live volume baseline does not match sacred post-ORB history"
    Assert-True ($source.Contains('bool CheckVolFilter(datetime signalBar,string &r)')) "$name live volume filter is not bound to the selected sacred candidate"
    Assert-True ($source.Contains('int sh=iBarShift(_Symbol,g_rtSignalTf,signalBar,true);')) "$name live volume can drift to a newer chart bar"
    Assert-True ($source.Contains('return FindHistBreakoutAfter(g_orbEndServer,through,g_orbHigh,g_orbLow,g_lastSignalBarTime,')) "$name closed-bar live selection does not use the sacred breakout scanner"
    Assert-True ($source.Contains('CheckVolFilter(bt,fr)')) "$name live filter does not evaluate the selected signal bar"
    Assert-True ($source.Contains('g_orbOperationalCandidateConsumed=true;')) "$name live does not consume the sacred operational candidate"
    Assert-True ($source.Contains('if(g_orbOperationalCandidateConsumed)')) "$name live can promote a later same-day breakout"
    Assert-True ($source.Contains('bool priorSignal=FindHistOperationalBreakout(g_orbEndServer,startupCutoff')) "$name restart guard does not replay the sacred operational chain"
    Assert-True ($source.Contains('g_histAuditStage="PREP";')) "$name has no preparation progress stage"
    Assert-True ($source.Contains('g_histAuditStage="CALC";')) "$name has no calculation progress stage"
    Assert-True ($source.Contains('SetHistoricalAuditProgress("PREP",1.0,6.0,done,g_histRunDays);')) "$name does not expose real prepass work progress"
    Assert-True ($source.Contains('SetHistoricalAuditProgress("CALC",10.0,90.0,done,g_histRunDays);')) "$name does not expose real calculation work progress"
    Assert-True ($source.Contains('g_histRejectedWindowRaw+=ProcessHistoricalPrepDay(g_histPrepBack);')) "$name prepass is not incrementally scheduled"
    Assert-True ($source.Contains('if(!g_rtFilteredWindowReverseExit&&!g_rtPostTradeDispBlockExit)break;')) "$name scans unnecessary post-entry candidates"
    Assert-True ($source.Contains('bool visualCandidate=(!hasAccepted&&firstWindowIndex<0);')) "$name does not compact visual rejects"
    Assert-True ($source.Contains('AppendOrbOperationalSignal(g_histOperationalSignals')) "$name does not cache operational line boundaries"
    Assert-True ($source.Contains('bool operationalKnown;')) "$name day snapshot does not cache PREP completion"
    Assert-True ($source.Contains('g_histDaySnapshots[back].operationalFound=true;')) "$name does not persist PREP's first operational breakout"
    Assert-True ($source.Contains('g_histDaySnapshots[back].operationalModernDetail=detail;')) "$name loses the cached modern-filter detail"
    Assert-True ($source.Contains('g_histDaySnapshots[back].operationalKnown=true;')) "$name does not finalize the daily operational snapshot"
    Assert-True (-not $source.Contains('bool acceptedKnown;')) "$name replaced the sacred operational candidate with a later fully accepted candidate"
    Assert-True ($source.Contains('g_histDaySnapshots[back].operationalKnown)')) "$name CALC no longer consumes the sacred operational candidate"
    Assert-True ($source.Contains('dir=g_histDaySnapshots[back].operationalDirection;')) "$name CALC no longer preserves sacred candidate identity"
    Assert-True ($source.Contains('datetime visualT=OrbSignalAvailableTime(sigT);')) "$name history marker moved away from closed-bar availability time"
    Assert-True ($source.Contains('void DrawOrbExecutionVisual(string execDir,datetime executedAt,datetime signalBar,double entry,double sl,string entryDetail)')) "$name execution marker lost source signal identity or risk geometry"
    Assert-True ($source.Contains('datetime visualAt=signalBar>0?OrbSignalAvailableTime(signalBar):executedAt;')) "$name execution marker does not share sacred history availability timing"
    Assert-True ($source.Contains('double arrowPrice=OrbHistoricalArrowPrice(isBuy,entry,risk);')) "$name execution marker does not share sacred history price geometry"
    Assert-True ($source.Contains('DrawOrbExecutionVisual(execDir,executedAt,signalBar,entry,sl,entryDetail);')) "$name bridge-only execution marker lost source signal geometry"
    Assert-True ($source.Contains('DrawOrbExecutionVisual(execDir,TimeCurrent(),signalBar,entry,sl,entryDetail);')) "$name native execution marker lost source signal geometry"
    Assert-True ($source.Contains('operationalFound=FindHistOperationalBreakout(')) "$name lost the safe uncached fallback scanner"
    Assert-True ($source.Contains('FirstOrbSignalAfter(signals,afterTime)')) "$name does not binary-seek chronological exit streams"
    Assert-True ($source.Contains('PrepareHistoricalTickReplayRange(fromMs,toMs,scanFirst,scanAfter)')) "$name does not use the direct indexed tick-cache view"
    Assert-True ($source.Contains('CopyTicksRange(_Symbol,g_histTickReplayCache,COPY_TICKS_INFO')) "$name tick cache is not built from the exact bid/ask-change stream"
    Assert-True ($source.Contains('HistoricalTickLowerBound(fromMs)')) "$name tick cache lacks exact lower-bound slicing"
    Assert-True ($source.Contains('HistoricalTickUpperBound(toMs)')) "$name tick cache lacks exact upper-bound slicing"
    Assert-True ($source.Contains('BuildHistoricalTickReplayBlocks(rebuildFromTick);')) "$name does not incrementally rebuild exact tick-block extrema"
    Assert-True ($source.Contains('int firstBlock=MathMax(0,MathMin(blockCount,rebuildFromTick/ORB_HIST_TICK_BLOCK_SIZE));')) "$name rebuilds unchanged tick blocks after an append"
    Assert-True ($source.Contains('void InitializeHistoricalTickReplayCoverage()')) "$name does not probe tick coverage once per audit"
    Assert-True ($source.Contains('CopyTicks(_Symbol,firstQuote,COPY_TICKS_INFO')) "$name does not locate the first available quote tick"
    Assert-True ($source.Contains('if(g_histTickCoverageKnown&&fromMs<g_histTickFirstAvailableMs)return false;')) "$name still retries unavailable old tick history per trade"
    Assert-True ($source.Contains('#define ORB_HIST_TICK_PREFETCH_MINUTES 15')) "$name exact replay does not use the bounded initial tick window"
    Assert-True ($source.Contains('#define ORB_HIST_TICK_BLOCK_SIZE 256')) "$name exact replay does not use the parity-tested fine-grained tick index"
    Assert-True ($source.Contains('struct OrbHistoricalTickResumeState')) "$name has no exact replay continuation state"
    Assert-True ($source.Contains('g_histTickResume.nextIndex=scanAfter;')) "$name does not resume exact replay after the previous horizon"
    Assert-True ($source.Contains('g_histTickResume.maxTp=res.maxTp;')) "$name loses TP/HCBE state while extending the replay horizon"
    Assert-True ($source.Contains('g_histTickResume.effectiveSl=effSl;g_histTickResume.beApplied=beApplied;')) "$name loses effective SL/BE state while extending the replay horizon"
    Assert-True ($source.Contains('g_histTickResumeAllowed=true;')) "$name lifecycle does not enable scoped continuation"
    Assert-True ($source.Contains('g_histTickResumeAllowed=false;')) "$name continuation state can leak beyond one lifecycle"
    Assert-True ($source.Contains('horizon<now&&expand<20')) "$name shortened the maximum exact lifecycle horizon"
    Assert-True ($source.Contains('HistoricalTickBlockCanSkip(block,isBuy,entry,risk,effSl,tps,res.maxTp')) "$name does not use conservative block pruning"
    Assert-True ($source.Contains('block.validQuotes<=0')) "$name tick blocks do not preserve invalid-quote semantics"
    Assert-True ($source.Contains('if(forcedExitTime>fillTime&&lastTime>=forcedExitTime)return false;')) "$name could skip a forced-exit boundary"
    Assert-True ($source.Contains('if(isBuy?(minClose<=effSl):(maxClose>=effSl))return false;')) "$name could skip a stop-loss event"
    Assert-True ($source.Contains('copied=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,fromMs,toMs);')) "$name lost the exact bid/ask direct-I/O fallback"

    $tickStart = $source.IndexOf('bool SimulateTradeTicks(datetime sigTime')
    $tickEnd = $source.IndexOf('HistResult SimulateTrade(datetime sigTime', $tickStart)
    Assert-True ($tickStart -ge 0 -and $tickEnd -gt $tickStart) "$name tick simulator boundaries not found"
    $tickBody = $source.Substring($tickStart, $tickEnd - $tickStart)
    Assert-True (-not $tickBody.Contains('CopyHistoricalTickReplaySlice(')) "$name still allocates and copies the tick slice per trade"

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
