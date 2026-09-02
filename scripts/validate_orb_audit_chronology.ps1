param(
    [string]$SourceRoot = "IndicatorCodeExamples"
)

$ErrorActionPreference = "Stop"
$files = @(
    "OrbUltimateEA.mq5",
    "A05OrbEA.mq5",
    "A10OrbEA.mq5",
    "N10OrbEA.mq5",
    "Q10OrbEA.mq5"
)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

foreach ($name in $files) {
    $path = Join-Path $SourceRoot $name
    $source = [IO.File]::ReadAllText((Resolve-Path $path))

    Assert-True (-not $source.Contains("SimulateTradeCore(")) "$name still contains the paired simulation core"
    Assert-True (-not $source.Contains("HistResultIsConfiguredTarget")) "$name still contains result override logic"
    Assert-True (([regex]::Matches($source, "HistResult SimulateTrade\(")).Count -eq 1) "$name must have exactly one trade simulator"
    Assert-True (-not $source.Contains("if(slHit&&(hitLeg>0||targetTouched)&&res.maxTp==0)")) "$name skips same-bar policy after an earlier milestone"
    Assert-True ($source.Contains('else{res.outcome=beApplied?"BE":"SL";res.exitPrice=effSl;')) "$name does not preserve HCBE during a same-bar collision"
    Assert-True ($source.Contains('DrawOrbHistoricalSegment(levelId+"_SL",levelStart,levelEnd,sim.simSl')) "$name does not draw the simulated SL"
    Assert-True ($source.Contains('DrawOrbHistoricalSegment(levelId+"_TP",levelStart,levelEnd,sim.simTarget')) "$name does not draw the simulated target"
    Assert-True ($source.Contains("BtCostRForSpread(risk,historicalSpreadPts)")) "$name OHLC fallback does not use entry-bar spread"
    Assert-True ($source.Contains('DrawSignalText(base+"EXIT",sim.exitTime,sim.exitPrice')) "$name does not expose the actual simulated exit"
    Assert-True ($source.Contains('" G="+DoubleToString(grossR,2)+"R C="')) "$name does not expose gross/cost/net R"
    Assert-True ($source.Contains('datetime levelEnd=levelStart+MathMax(60,PeriodSeconds(RuntimeEntryTf()))*20;')) "$name historical levels are not capped at 20 entry-TF bars"
    Assert-True (-not $source.Contains('if(sim.exitTime>levelStart&&sim.exitTime<levelEnd)levelEnd=sim.exitTime;')) "$name still collapses reference levels at an early TP/SL exit"

    Assert-True ($source.Contains('InpNasExitOnOppositeSignalDefault = false')) "$name enables the new NAS exit-only behavior by default"
    Assert-True ($source.Contains('return (ENUM_TIMEFRAMES)_Period;')) "$name embedded NAS is not locked to the standalone chart timeframe"
    Assert-True ($source.Contains('s.sensitivity=ClampNasSensitivity(g_rtNasSensitivity);')) "$name embedded NAS does not use the standalone-compatible runtime sensitivity"
    Assert-True ($source.Contains('bool nasExitLifecycle=RuntimeNasExitEnabled();')) "$name does not admit ordinary ORB trades into either NAS exit lifecycle"
    Assert-True ($source.Contains('StartNasManagedLifecycle(execDir,isBuy?1:-1')) "$name NAS lifecycle is not based on actual execution direction"
    Assert-True ($source.Contains('if(anyNasExit)') -and $source.Contains('FindNasOppositeExitWithGrace(execDir=="BUY"?1:-1,OrbSignalAvailableTime(entryT)')) "$name historical NAS exit scan is not bounded by accepted ORB time"
    Assert-True ($source.Contains('OrbProPublishCloseOnly(g_nasManagedExecDir,reason,true)')) "$name NAS exit does not publish a scoped close-only event"
    Assert-True ($source.Contains('OrbProSafeToken(_Symbol)+"."+OrbProTf(g_rtSignalTf)+".C"+IntegerToString(g_orbBridgeChannel)')) "$name NAS lifecycle key is not symbol/TF/channel scoped"
    Assert-True ($source.Contains('"ENTRY GATE ON":"ENTRY GATE OFF"')) "$name NAS entry-gate control is not explicit"
    Assert-True ($source.Contains('RuntimeNasModeLabel()')) "$name does not expose ENTRY/EXIT mode state"

    Assert-True ($source.Contains('void AppendOrbAcceptedSignal(')) "$name does not collect accepted ORB signals for lifecycle exits"
    Assert-True ($source.Contains('bool FindNewDayAcceptedReverseExit(')) "$name has no next-day accepted reverse exit resolver"
    Assert-True ($source.Contains('if(candidateDay<=entryDay)continue;')) "$name allows a same-day signal to trigger the next-day reverse lifecycle"
    Assert-True ($source.Contains('if(signals[i].executionDirection!=opposite)continue;')) "$name does not require an opposite execution direction"
    Assert-True ($source.Contains('forcedExitOutcome="NEW_DAY_REVERSE_EXIT"')) "$name does not route the next-day reverse into simulation"
    Assert-True ($source.Contains('||outcome=="NAS_OPPOSITE_EXIT"||outcome=="NAS_ADDITIONAL_EXIT"||outcome=="NEW_DAY_REVERSE_EXIT";')) "$name does not value NAS/next-day exits at their market exit price"
    Assert-True ($source.Contains('FindNewDayAcceptedReverseExit(g_histAcceptedSignals,entryT,execDir,g_histRunNow')) "$name does not resolve next-day reversal from the accepted signal stream"

    $sameBar = [regex]::Match($source, "(?s)bool BtTpFirst\(.*?\n\}").Value
    Assert-True ($sameBar.Length -gt 0) "$name has no same-bar resolver"
    Assert-True (-not $sameBar.Contains("g_rtInvertMode")) "$name changes same-bar chronology in inversion mode"
    Assert-True ($sameBar.Contains("BT_SAMEBAR_TP_FIRST)return true")) "$name TP-first policy is not deterministic"
    Assert-True ($sameBar.Contains("BT_SAMEBAR_CONSERVATIVE)return false")) "$name conservative policy is not SL-first"

    $tickReplay = [regex]::Match($source, "(?s)bool SimulateTradeTicks\(.*?(?=HistResult SimulateTrade\()").Value
    Assert-True ($tickReplay.Length -gt 0) "$name has no tick replay simulator"
    $tickSl = $tickReplay.IndexOf("bool slHit")
    $tickTp = $tickReplay.IndexOf("bool targetHit")
    Assert-True ($tickSl -ge 0 -and $tickTp -gt $tickSl) "$name does not process tick protection before target evaluation"
}

function Resolve-SyntheticTrade([string]$Side, [double]$Sl, [double]$Tp, [string]$Policy, [object[]]$Bars) {
    foreach ($bar in $Bars) {
        $slHit = if ($Side -eq "BUY") { $bar.Low -le $Sl } else { $bar.High -ge $Sl }
        $tpHit = if ($Side -eq "BUY") { $bar.High -ge $Tp } else { $bar.Low -le $Tp }
        if ($slHit -and $tpHit) {
            if ($Policy -eq "TP_FIRST") { return "WIN" }
            if ($Policy -eq "NEAREST") {
                $tpDistance = if ($Side -eq "BUY") { $Tp - $bar.Open } else { $bar.Open - $Tp }
                $slDistance = if ($Side -eq "BUY") { $bar.Open - $Sl } else { $Sl - $bar.Open }
                return $(if ($tpDistance -lt $slDistance) { "WIN" } else { "LOSS" })
            }
            return "LOSS"
        }
        if ($slHit) { return "LOSS" }
        if ($tpHit) { return "WIN" }
    }
    return "OPEN"
}

$buySlFirst = @(@{ Open = 100.0; High = 105.0; Low = 89.0 }, @{ Open = 100.0; High = 111.0; Low = 95.0 })
$buyTpFirst = @(@{ Open = 100.0; High = 111.0; Low = 95.0 }, @{ Open = 100.0; High = 105.0; Low = 89.0 })
$sellSlFirst = @(@{ Open = 100.0; High = 111.0; Low = 95.0 }, @{ Open = 100.0; High = 105.0; Low = 89.0 })
$sellTpFirst = @(@{ Open = 100.0; High = 105.0; Low = 89.0 }, @{ Open = 100.0; High = 111.0; Low = 95.0 })
$sameBarMiddle = @(@{ Open = 100.0; High = 111.0; Low = 89.0 })
$sameBarNearTp = @(@{ Open = 108.0; High = 111.0; Low = 89.0 })
$sameBarNearSl = @(@{ Open = 92.0; High = 111.0; Low = 89.0 })

Assert-True ((Resolve-SyntheticTrade "BUY" 90.0 110.0 "CONSERVATIVE" $buySlFirst) -eq "LOSS") "BUY red-first chronology failed"
Assert-True ((Resolve-SyntheticTrade "BUY" 90.0 110.0 "CONSERVATIVE" $buyTpFirst) -eq "WIN") "BUY green-first chronology failed"
Assert-True ((Resolve-SyntheticTrade "SELL" 110.0 90.0 "CONSERVATIVE" $sellSlFirst) -eq "LOSS") "SELL red-first chronology failed"
Assert-True ((Resolve-SyntheticTrade "SELL" 110.0 90.0 "CONSERVATIVE" $sellTpFirst) -eq "WIN") "SELL green-first chronology failed"
Assert-True ((Resolve-SyntheticTrade "BUY" 90.0 110.0 "CONSERVATIVE" $sameBarMiddle) -eq "LOSS") "Conservative same-bar policy failed"
Assert-True ((Resolve-SyntheticTrade "BUY" 90.0 110.0 "SL_FIRST" $sameBarMiddle) -eq "LOSS") "SL-first same-bar policy failed"
Assert-True ((Resolve-SyntheticTrade "BUY" 90.0 110.0 "TP_FIRST" $sameBarMiddle) -eq "WIN") "TP-first same-bar policy failed"
Assert-True ((Resolve-SyntheticTrade "BUY" 90.0 110.0 "NEAREST" $sameBarNearTp) -eq "WIN") "Nearest-open TP case failed"
Assert-True ((Resolve-SyntheticTrade "BUY" 90.0 110.0 "NEAREST" $sameBarNearSl) -eq "LOSS") "Nearest-open SL case failed"

function Resolve-SyntheticNewDayReverse([datetime]$EntryTime, [string]$TradeSide, [object[]]$Signals) {
    $entryDay = $EntryTime.Date
    $opposite = if ($TradeSide -eq "BUY") { "SELL" } else { "BUY" }
    foreach ($signal in ($Signals | Sort-Object Time)) {
        if ($signal.Time -le $EntryTime) { continue }
        if ($signal.Time.Date -le $entryDay) { continue }
        if ($signal.Side -ne $opposite) { continue }
        return $signal.Time
    }
    return $null
}

$entry = [datetime]"2026-08-24T09:30:00"
$reverseSignals = @(
    @{ Time = [datetime]"2026-08-24T13:00:00"; Side = "SELL" },
    @{ Time = [datetime]"2026-08-25T09:30:00"; Side = "BUY" },
    @{ Time = [datetime]"2026-08-26T09:30:00"; Side = "SELL" }
)
$resolvedReverse = Resolve-SyntheticNewDayReverse $entry "BUY" $reverseSignals
Assert-True ($resolvedReverse -eq [datetime]"2026-08-26T09:30:00") "Next-day reverse must ignore same-day opposite and next-day same-side signals"
Assert-True ((Resolve-SyntheticNewDayReverse $entry "SELL" @(@{ Time = [datetime]"2026-08-25T09:30:00"; Side = "SELL" })) -eq $null) "Same-side next-day signal must not close the trade"

Write-Output "ORB audit chronology regression checks passed for $($files.Count) files."
