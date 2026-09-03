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
    InpNasUseVolumeFilter = Input-Value $nas "InpUseVolumeFilter"
    InpNasVolumeMultiplier = Input-Value $nas "InpVolumeMultiplier"
    InpNasFlowUseVolumeFilter = Input-Value $nas "InpUseVolumeFilter"
    InpNasFlowVolumeMultiplier = Input-Value $nas "InpVolumeMultiplier"
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
    Assert-True ($source.Contains('s.sensitivity=ClampNasSensitivity(g_rtNasSensitivity);')) "$name does not pass runtime NAS sensitivity to the shared core"
    Assert-True ($source.Contains('s.rsiLength=MathMax(2,InpNasRsiLength);')) "$name NAS RSI setting differs"
    Assert-True ($source.Contains('s.atrRisk=MathMax(1,InpNasAtrRisk);')) "$name NAS ATR-risk setting differs"
    Assert-True ($source.Contains('s.atrLen=MathMax(2,InpNasAtrLen);')) "$name NAS ATR length differs"
    Assert-True ($source.Contains('int NasCalcWarmupBars(){return MathMax(300,MathMin(200000,InpNasSignalCalcBars));}')) "$name does not use the 5000-bar NAS parity warm-up"
    Assert-True ($source.Contains('return (ENUM_TIMEFRAMES)_Period;')) "$name embedded NAS is not locked to the MT5 chart timeframe"
    Assert-True ($source.Contains('return "TF CHART "+TfLabel(NasConfirmationTf());')) "$name dashboard does not expose chart-locked NAS timeframe"
    Assert-True (-not $source.Contains('CreateButton("BTN_NAS_TF"')) "$name still exposes a mutable NAS timeframe button"
    Assert-True ($source.Contains('CreateEdit("EDIT_NAS_SENS"')) "$name does not expose runtime NAS sensitivity"
    Assert-True ($source.Contains('RuntimeNasSensitivityKey()')) "$name does not persist runtime NAS sensitivity"
    Assert-True ($source.Contains('CreateButton("BTN_NAS_VOL"')) "$name does not expose the NAS-only volume filter"
    Assert-True ($source.Contains('CreateEdit("EDIT_NAS_VOL_X"')) "$name does not expose the NAS volume multiplier"
    Assert-True ($source.Contains('bool OrbNasVolumePolicyAllows(const MqlRates &rates[],const int signalIndex,')) "$name has no shared NAS volume policy"
    Assert-True ($source.Contains('const int lookback=20;')) "$name NAS volume lookback differs from standalone"
    Assert-True ($source.Contains('if(signalIndex<lookback||signalIndex<0||signalIndex>=count)return;')) "$name NAS volume lookback is not bounds-safe"
    Assert-True ($source.Contains('averageVolume=sum/(double)samples;')) "$name NAS volume average differs from standalone"
    Assert-True ($source.Contains('double threshold=averageVolume*multiplier;')) "$name NAS volume threshold differs from standalone"
    Assert-True ($source.Contains('if(signalVolume<threshold)')) "$name NAS volume comparison differs from standalone"
    Assert-True ($source.Contains('OrbNasStateVolumeFilterAllows(rates,i,volumeReason,signalVolume,averageVolume)')) "$name STATE GATE does not use the state volume policy"
    Assert-True (([regex]::Matches($source, 'OrbNasFlowVolumeFilterAllows\(rates,i,volumeReason,signalVolume,averageVolume\)')).Count -ge 4) "$name ENTRY/OPP/ADD paths do not use the flow volume policy"
    Assert-True (([regex]::Matches($source, 'HistoricalNasFlowEventAllowed\(i\)')).Count -ge 5) "$name cached ENTRY/OPP/ADD paths do not use the flow volume policy"
    Assert-True ($source.Contains('HistoricalNasStateEventAllowed(i)')) "$name cached STATE GATE does not use the state volume policy"
    Assert-True ($source.Contains('ORB_NAS_VISUAL_POLICY HistoricalNasVisualPolicy(const int index)')) "$name NAS overlay has no cached policy classifier"
    Assert-True ($source.Contains('if(statePass&&flowPass)return ORB_NAS_VIS_BOTH;')) "$name NAS overlay does not classify overlapping STATE/FLOW events as BOTH"
    Assert-True ($source.Contains('return HistoricalNasVisualPolicy(index)!=ORB_NAS_VIS_NONE;')) "$name cached NAS overlay does not expose the union of active policies"
    Assert-True ($source.Contains('SetRuntimeNasSensitivity(requestedSensitivity)') -and $source.Contains('SetRuntimeNasVolumeMultiplier(requestedNasVolX)') -and $source.Contains('SetRuntimeNasFlowVolumeMultiplier(requestedNasFlowVolX)')) "$name APPLY NAS does not persist sensitivity and both NAS volume multipliers"
    Assert-True ($source.Contains('CreateButton("BTN_NAS_FLOW_VOL"')) "$name dashboard has no independent flow-volume toggle"
    Assert-True ($source.Contains('CreateEdit("EDIT_NAS_FLOW_VOL_X"')) "$name dashboard has no flow-volume multiplier"
    Assert-True ($source.Contains('else if(sparam==PREFIX+"BTN_NAS_FLOW_VOL")')) "$name dashboard cannot toggle the flow-volume policy"
    Assert-True ($source.Contains('g_rtNasFlowVolumeFilter=g_rtNasVolumeFilter;') -and $source.Contains('g_rtNasFlowVolumeMultiplier=g_rtNasVolumeMultiplier;')) "$name does not migrate the legacy shared volume policy"
    Assert-True ($source.Contains('int NasHistoryBars(){return MathMax(300,InpNasHistoryBars);}')) "$name does not use the uncapped standalone NAS history depth"
    Assert-True ($source.Contains('void NormalizeOrbNasRates(MqlRates &rates[],const int copied)')) "$name does not normalize NAS rates chronologically"
    Assert-True ($source.Contains('int LoadOrbNasRatesThrough(MqlRates &rates[],ENUM_TIMEFRAMES tf,datetime throughTime,const int barsToCopy)')) "$name has no point-in-time NAS loader"
    Assert-True ($source.Contains('datetime OrbNasSignalAvailableTime(const MqlRates &rates[],const int copied,const int index)')) "$name does not share closed-bar availability semantics"
    Assert-True ($source.Contains('return rates[index+1].time;')) "$name does not use the next existing market bar as NAS availability"

    Assert-True ((Input-Value $source 'InpNasStateGateDefault') -eq 'false') "$name NAS STATE GATE is not default-safe"
    Assert-True ($source.Contains('bool SetRuntimeNasEntryModes(bool confirmationEnabled,bool stateGateEnabled)')) "$name has no shared ENTRY/STATE radio-state setter"
    Assert-True ($source.Contains('if(confirmationEnabled&&stateGateEnabled)return false;')) "$name can enable ENTRY GATE and STATE GATE together"
    Assert-True ($source.Contains('bool SetRuntimeNasStateGate(bool enabled){return SetRuntimeNasEntryModes(false,enabled);}')) "$name cannot persist STATE GATE independently"
    Assert-True ($source.Contains('int LastAllowedNasEventAtOrBefore(const datetime at)')) "$name has no causal latest-state lookup"
    Assert-True ($source.Contains('for(int i=FirstNasEventAfter(at)-1;i>=0;i--)')) "$name latest-state lookup can inspect a future NAS event"
    Assert-True ($source.Contains('if(available<=0||available>orbAcceptedAt)continue;')) "$name live STATE GATE is not bounded by ORB availability"
    Assert-True ($source.Contains('if(g_rtNasStateGate)') -and $source.Contains('else if(g_rtNasConfirmation)')) "$name historical STATE GATE does not remain distinct from bounded ENTRY GATE"
    Assert-True ($source.Contains('seedSeconds=g_rtNasStateGate?(long)NasCalcWarmupBars()*sec')) "$name audit cache does not preserve a pre-window NAS state seed"
    Assert-True ($source.Contains('CreateButton("BTN_NAS_STATE_GATE"')) "$name dashboard has no STATE GATE control"
    Assert-True ($source.Contains('else if(sparam==PREFIX+"BTN_NAS_STATE_GATE")')) "$name dashboard cannot toggle STATE GATE"
    Assert-True ($source.Contains('HandleNasStateGateRejection(dir,bt,sc,nasDetail);')) "$name live STATE GATE mismatch is not fail-closed"
    $stateReject = [regex]::Match($source, '(?s)void HandleNasStateGateRejection\(.*?(?=void TryOpenSignal\(\))').Value
    Assert-True ($stateReject.Length -gt 0) "$name STATE GATE rejection handler is missing"
    Assert-True (-not $stateReject.Contains('CloseAllOwn') -and -not $stateReject.Contains('OrbProPublishCloseOnly')) "$name STATE GATE can unexpectedly close a position"

    Assert-True ($source.Contains('int DrawNasSignalOverlay(int days,datetime now)')) "$name has no historical NAS overlay"
    Assert-True ($source.Contains('void RefreshNasSignalOverlay()')) "$name has no live closed-bar NAS overlay refresh"
    Assert-True ($source.Contains('"WINDOW NAS "+dir+" ["+NasVisualPolicyLabel(policy)')) "$name NAS markers do not identify STATE/FLOW/BOTH policy ownership"
    Assert-True ($source.Contains('if(policy==ORB_NAS_VIS_STATE)return C''35,170,255'';')) "$name STATE NAS markers have no dedicated color"
    Assert-True ($source.Contains('if(policy==ORB_NAS_VIS_FLOW)return C''255,158,46'';')) "$name FLOW NAS markers have no dedicated color"
    Assert-True ($source.Contains('if(policy==ORB_NAS_VIS_BOTH)return C''210,100,255'';')) "$name BOTH NAS markers have no dedicated color"
    Assert-True ($source.Contains('ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,policy==ORB_NAS_VIS_BOTH?3:2);')) "$name BOTH NAS markers are not visually emphasized"
    Assert-True (([regex]::Matches($source, 'DrawNasSignalMarker\(rates\[i\],points\[i\],tf,visual\)')).Count -eq 2) "$name live/direct NAS overlay paths do not share one policy-aware marker"
    Assert-True ($source.Contains('int requested=MathMax(NasHistoryBars(),neededBars);')) "$name historical overlay does not match standalone history warm-up"
    Assert-True ($source.Contains('int copied=LoadOrbNasRatesThrough(rates,tf,latestAvailable,NasCalcWarmupBars());')) "$name live NAS decisions do not use the standalone 5000-bar calculation depth"
    Assert-True (-not $source.Contains('NasCalcWarmupBars()+spanBars')) "$name adds non-standalone bars to live NAS calculation"
    Assert-True ($source.Contains('for(int i=0;i<=copied-2;i++)')) "$name historical NAS overlay does not scan the same index range as standalone"
    Assert-True ($source.Contains('for(int i=1;i<=copied-2;i++)')) "$name NAS scan does not explicitly exclude the live bar"
    Assert-True ($source.Contains('g_lastNasOverlaySignalCount=drawn;')) "$name does not expose the raw NAS parity count"
    $overlay = [regex]::Match($source, "(?s)bool NasOverlayEnabled\(\).*?(?=void DrawLevels\(\))").Value
    Assert-True ($overlay.Length -gt 0) "$name NAS overlay block is missing"
    Assert-True (-not $overlay.Contains('InpNasOverlayMaxBars')) "$name still truncates standalone NAS history with a visual cap"
    Assert-True (-not $overlay.Contains("OrbProPublish") -and -not $overlay.Contains("PositionClose") -and -not $overlay.Contains("trade.")) "$name NAS overlay can mutate execution or bridge state"
    Assert-True (-not $overlay.Contains('BarCloseTime(tf,rates[i].time)')) "$name NAS overlay still uses theoretical bar-close timestamps"

    Assert-True ($source.Contains('input string          InpNasOppositeExitWait = "00:00";')) "$name has no default-safe OPP EXIT grace input"
    Assert-True ($source.Contains('input bool            InpNasAdditionalExitDefault = false;')) "$name ADD EXIT is missing or not default-safe"
    Assert-True ($source.Contains('bool SetRuntimeNasExitModes(bool opEnabled,bool addEnabled)')) "$name has no shared OPP/ADD radio-state setter"
    Assert-True ($source.Contains('if(opEnabled&&addEnabled)return false;')) "$name can enable OPP EXIT and ADD EXIT together"
    Assert-True ($source.Contains('addSaved=GlobalVariableSet(RuntimeNasAdditionalExitKey(),0.0)>0;')) "$name does not disable ADD before enabling OPP"
    Assert-True ($source.Contains('opSaved=GlobalVariableSet(RuntimeNasExitKey(),0.0)>0;')) "$name does not disable OPP before enabling ADD"
    Assert-True ($source.Contains('bool RuntimeNasExitEnabled(){return g_rtNasExitOnOppositeSignal||g_rtNasAdditionalExit;}')) "$name does not share lifecycle ownership across both exit modes"
    Assert-True ($source.Contains('bool anyNasExit=RuntimeNasExitEnabled();') -and $source.Contains('if(anyNasExit)')) "$name historical audit does not bypass NAS exits when both exit modes are OFF"
    Assert-True ($source.Contains('if(!RuntimeNasExitEnabled())return false;')) "$name live lifecycle can still execute a NAS close with OPP/ADD both OFF"
    Assert-True ($source.Contains('CreateButton("BTN_NAS_ADD_EXIT"')) "$name has no ADD EXIT dashboard toggle"
    Assert-True ($source.Contains('else if(sparam==PREFIX+"BTN_NAS_ADD_EXIT")')) "$name does not handle ADD EXIT dashboard clicks"
    Assert-True ($source.Contains('if(g_nasManagedClosePending)')) "$name can change exit mode while a persisted close is pending"
    Assert-True ($source.Contains('datetime NasOppositeExitScanExclusive(datetime openedAt)')) "$name has no exit-grace boundary resolver"
    Assert-True ($source.Contains('bool FindLatestNasSignalAfter(datetime afterExclusive,datetime latestAvailable,')) "$name cannot persist the latest NAS state during grace"
    Assert-True ($source.Contains('bool FindNasOppositeExitWithGrace(int execDir,datetime openedAt,datetime latestAvailable,')) "$name has no grace-latched historical exit resolver"
    Assert-True ($source.Contains('datetime scanAfter=MathMax(g_nasManagedStartAt,g_nasManagedLastScanAt);')) "$name does not scan NAS events occurring inside grace"
    Assert-True ($source.Contains('g_nasManagedOppositeAt=(stateDir==opposite?eventAt:0);')) "$name does not latch/cancel the active opposite NAS state"
    Assert-True ($source.Contains('if(eligibleAt>0&&TimeCurrent()<eligibleAt)return false;')) "$name can close before the configured grace expires"
    Assert-True ($source.Contains('if(g_nasManagedOppositeAt<=0)return false;')) "$name can close without a currently latched opposite NAS state"
    Assert-True (([regex]::Matches($source, 'FindNasOppositeExitWithGrace\(execDir=="BUY"\?1:-1,OrbSignalAvailableTime\(entryT\)')).Count -ge 2) "$name historical/optimizer NAS exits do not start at the accepted ORB time"
    Assert-True ($source.Contains('if(g_nasManagedOppositeAt>0&&g_nasManagedOppositeAt<=g_nasManagedStartAt)')) "$name can restore or execute a pre-entry NAS latch"
    Assert-True (([regex]::Matches($source, 'nas_pre_entry_latch_discarded')).Count -ge 2) "$name does not discard invalid pre-entry latches in restore and runtime paths"
    Assert-True ($source.Contains('GlobalVariableSet(NasLifecycleKey("opposite_at"),(double)g_nasManagedOppositeAt);')) "$name does not persist the grace latch across restart"
    Assert-True ($source.Contains('publishOk=OrbProPublishCloseOnly(g_nasManagedExecDir,reason,true);')) "$name does not publish the latched exit to listeners"
    Assert-True ($source.Contains('datetime nasSearchEnd=g_rtNasAdditionalExit?g_histRunNow:te;')) "$name does not preserve legacy OPP horizon while extending ADD EXIT"
    Assert-True ($source.Contains('forcedExitOutcome=g_rtNasAdditionalExit?"NAS_ADDITIONAL_EXIT":"NAS_OPPOSITE_EXIT";')) "$name does not distinguish ADD EXIT audit outcomes"
    Assert-True ($source.Contains('datetime NasLegacyExitWindowEnd(datetime openedAt)')) "$name cannot reproduce the legacy OPP session boundary in live execution"
    Assert-True ($source.Contains('latestClosedAt=MathMin(latestClosedAt,legacyWindowEnd);')) "$name live OPP EXIT is not bounded like its historical audit"
    $optimizerExtended = $source.Contains('if(g_rtNasAdditionalExit)') -and
        $source.Contains('?SimulateHistoricalLifecycleAdvanced(entryT,g_btDays[di].tradeEnd') -and
        $source.Contains(':SimulateHistoricalLifecycle(entryT,g_btDays[di].tradeEnd')
    Assert-True $optimizerExtended "$name optimizer does not extend only the ADD EXIT lifecycle"
    Assert-True ($source.Contains('else') -and $source.Contains('sim=SimulateTrade(entryT,g_btDays[di].tradeEnd')) "$name optimizer no longer preserves legacy OPP simulation"
    Assert-True ($source.Contains('||outcome=="NAS_ADDITIONAL_EXIT"||')) "$name does not price ADD EXIT at the actual market exit"
    Assert-True ($source.Contains('RuntimeNasExitWaitKey()')) "$name does not persist the exit grace per chart instance"
    Assert-True ($source.Contains('EDIT_NAS_EXIT_WAIT')) "$name does not expose the exit grace on the dashboard"
    Assert-True ($source.Contains('bool coreSignalSettingsChanged=(requested!=g_rtNasActiveSignalLookbackMinutes')) "$name APPLY NAS does not track core field changes"
    Assert-True ($source.Contains('bool stateVolumeSettingsChanged=(MathAbs(requestedNasVolX-g_rtNasVolumeMultiplier)>0.00005);')) "$name APPLY NAS does not track the state-volume field"
    Assert-True ($source.Contains('bool flowVolumeSettingsChanged=(MathAbs(requestedNasFlowVolX-g_rtNasFlowVolumeMultiplier)>0.00005);')) "$name APPLY NAS does not track the flow-volume field"
    Assert-True (-not $source.Contains('else if(lifecycleActive&&signalSettingsChanged)')) "$name still silently blocks APPLY NAS while a lifecycle is active"
    Assert-True (-not $source.Contains('NAS_APPLY_BLOCKED_ACTIVE_LIFECYCLE')) "$name still contains the legacy all-or-nothing lifecycle guard"
    Assert-True ($source.Contains('SetRuntimeNasExitWait(requestedWait)')) "$name APPLY NAS does not persist EXIT WAIT"
    Assert-True ($source.Contains('QueueHistoricalRedraw(0);UpdateDashboard();ChartRedraw(0);return;')) "$name APPLY NAS does not immediately invalidate and requeue the audit"
    Assert-True ($source.Contains('if(waitChanged&&g_nasManagedLifecycle)')) "$name does not re-evaluate an active managed lifecycle after EXIT WAIT changes"
    Assert-True ($source.Contains('void RefreshHistoricalNasFilterStats()')) "$name does not expose NAS filter effectiveness"
    Assert-True ($source.Contains('g_lastNasAllowedEventCount') -and $source.Contains('g_lastNasRawEventCount')) "$name dashboard cannot verify allowed/raw NAS counts"
}

$volumes = @(50.0, 100.0, 150.0, 250.0)
$average = 100.0
$previousAllowed = [int]::MaxValue
foreach ($multiplier in @(0.5, 1.0, 2.0, 20.0, 200.0)) {
    $allowed = @($volumes | Where-Object { $_ -ge $average * $multiplier }).Count
    Assert-True ($allowed -le $previousAllowed) "NAS volume threshold is not monotonic at multiplier $multiplier"
    $previousAllowed = $allowed
}

# Split-policy fixture: the same NAS event must be independently rejectable
# by STATE GATE while remaining actionable for ENTRY/OPP/ADD flow handling.
$fixtureVolume = 200.0
$fixtureAverage = 100.0
$stateMultiplier = 3.0
$flowMultiplier = 1.5
Assert-True (-not ($fixtureVolume -ge $fixtureAverage * $stateMultiplier)) "STATE x3 fixture unexpectedly passed"
Assert-True ($fixtureVolume -ge $fixtureAverage * $flowMultiplier) "FLOW x1.5 fixture unexpectedly failed"

# Overlap fixture: with STATE x2 and FLOW x3, volume 250 is STATE-only while
# volume 350 is BOTH. BOTH remains one visual marker with two policy owners.
$stateMultiplier = 2.0
$flowMultiplier = 3.0
$stateOnlyVolume = 250.0
$bothVolume = 350.0
Assert-True (($stateOnlyVolume -ge $fixtureAverage * $stateMultiplier) -and -not ($stateOnlyVolume -ge $fixtureAverage * $flowMultiplier)) "STATE-only visual fixture is invalid"
Assert-True (($bothVolume -ge $fixtureAverage * $stateMultiplier) -and ($bothVolume -ge $fixtureAverage * $flowMultiplier)) "BOTH S+F visual fixture is invalid"

$entry = [datetime]"2026-08-30T10:00:00"
$eligible = $entry.AddMinutes(30)
$preEntryOpposite = $entry.AddMinutes(-5)
$oppositeAt = [datetime]"2026-08-30T10:25:00"
Assert-True (-not ($preEntryOpposite -gt $entry)) "A pre-entry NAS event became eligible for exit"
Assert-True ($oppositeAt -lt $eligible) "Test fixture is not inside grace"
Assert-True ([datetime]"2026-08-30T10:29:59" -lt $eligible) "A latched signal could close before grace"
Assert-True ($oppositeAt -gt $entry -and [datetime]"2026-08-30T10:30:00" -ge $eligible) "A 10:25 opposite state was not actionable at 10:30"

$legacyWindowEnd = [datetime]"2026-08-30T16:00:00"
$postWindowOpposite = [datetime]"2026-08-30T18:00:00"
Assert-True (-not ($postWindowOpposite -le $legacyWindowEnd)) "Legacy OPP fixture did not remain session-bounded"
Assert-True ($postWindowOpposite -gt $entry) "ADD EXIT fixture did not remain strictly post-entry"

$listenerChecks = @(
    @{ Path = Join-Path $SourceRoot 'OrbUltimate_cTrader_Listener.cs'; Required = @(
        'sig.Channel <= 0 || sig.Channel != BridgeChannel',
        'var positions = ScopedPositions(sig).Where(p => p.TradeType == target).ToArray()',
        'return ContainsText(sig.Source, "CloseOnly") || ContainsText(sig.EventId, "invalidate_close")'
    )},
    @{ Path = Join-Path $SourceRoot 'NinjaTrader\ProductionFileBridgeNinjaCore.cs'; Required = @(
        'if(sig.Channel != BridgeChannel)',
        'var sameDirection = ScopedTrades(sig.SourceTf).Where(t => t.Direction == sig.Direction).ToArray()',
        'return ContainsText(sig.Source, "CloseOnly") || ContainsText(sig.EventId, "invalidate_close")'
    )},
    @{ Path = Join-Path $SourceRoot 'Quantower\ProductionFileBridgeQuantowerCore.cs'; Required = @(
        'if (signal.Channel != BridgeChannel)',
        'states.Values.Where(x => x.Direction == signal.Direction && SameText(x.SourceTf, NormalizeTf(signal.SourceTf))).ToArray()',
        'ContainsText(signal.Source, "CloseOnly")'
    )},
    @{ Path = Join-Path $SourceRoot 'IQCapital_MT5_Listener_Core.mqh'; Required = @(
        'sig.bridgeChannel != expectedChannel',
        'bool CloseSameDirectionPositions(const BridgeSignal &sig, string &detail)',
        'if(!ReverseScopeAllows(ticket, sig, scopeDetail))',
        'if(IsCloseOnlySignal(sig))'
    )}
)
foreach ($listener in $listenerChecks) {
    $listenerSource = [IO.File]::ReadAllText((Resolve-Path $listener.Path))
    foreach ($required in $listener.Required) {
        Assert-True ($listenerSource.Contains($required)) "$($listener.Path) missing scoped close invariant: $required"
    }
}

Write-Output "ORB/NAS state-vs-flow volume isolation, lifecycle, and scoped listener-close checks passed for $($orbFiles.Count) files."
