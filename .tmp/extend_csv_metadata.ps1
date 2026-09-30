$ErrorActionPreference='Stop'
$root=(Resolve-Path .).Path
$utf8=New-Object Text.UTF8Encoding($false)
function Edit($p,$f){$s=[IO.File]::ReadAllText($p);$s=& $f $s;[IO.File]::WriteAllText($p,$s,$utf8)}
foreach($folder in @('macrossover_orb','orb')){
 $name=if($folder -eq 'orb'){'OrbUltimateEA_StrategyLibrary.mq5'}else{'MaCrossOverOrbEA.mq5'}
 $p=Join-Path $root "IndicatorCodeExamples/$folder/$name"
 Edit $p {
  param($s)
  $s=$s.Replace('double simEntry;  // actual simulated fill entry','double entrySpreadPoints; // observed entry quote, EMPTY_VALUE if unavailable'+"`n   "+'double simEntry;  // actual simulated fill entry')
  $s=$s.Replace('   datetime fillTime;',"   double tickEntrySpreadPoints;`n   datetime fillTime;")
  $s=$s.Replace('fillTime=g_histTickResume.fillTime;brokerExitAt=g_histTickResume.brokerExitAt;','fillTime=g_histTickResume.fillTime;brokerExitAt=g_histTickResume.brokerExitAt;'+"`n      "+'res.entrySpreadPoints=g_histTickResume.tickEntrySpreadPoints;')
  $s=$s.Replace('fillTime=(datetime)firstTick.time;','fillTime=(datetime)firstTick.time;'+"`n      "+'res.entrySpreadPoints=(firstTick.ask-firstTick.bid)/pt;')
  $s=$s.Replace('g_histTickResume.fillTime=fillTime;g_histTickResume.brokerExitAt=brokerExitAt;','g_histTickResume.fillTime=fillTime;g_histTickResume.brokerExitAt=brokerExitAt;'+"`n      "+'g_histTickResume.tickEntrySpreadPoints=res.entrySpreadPoints;')
  $s=$s.Replace('res.simEntry=entry;res.entryTime=0;','res.simEntry=entry;res.entryTime=0;res.entrySpreadPoints=EMPTY_VALUE;')
  $s=$s.Replace('csv.entry=sim.simEntry;','csv.entrySpreadPoints=sim.entrySpreadPoints;csv.spreadBasis=sim.entrySpreadPoints!=EMPTY_VALUE?"ENTRY_BID_ASK_QUOTE":"NOT_CAPTURED_BAR_MODEL";'+"`n      "+'csv.entry=sim.simEntry;')
  return $s
 }
 $p=Join-Path $root "IndicatorCodeExamples/$folder/OrbAdvancedAuditEngine.mqh"
 Edit $p {
  param($s)
  $s=$s.Replace('res.simEntry=entry;res.entryTime=fillTime;','res.entrySpreadPoints=(firstTick.ask-firstTick.bid)/point;'+"`n   "+'res.simEntry=entry;res.entryTime=fillTime;')
  $s=$s.Replace('advanced.simEntry=entry;advanced.entryTime=0;','advanced.simEntry=entry;advanced.entryTime=0;advanced.entrySpreadPoints=EMPTY_VALUE;')
  return $s
 }
}
$p=Join-Path $root 'IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5'
Edit $p {
 param($s)
 $s=$s.Replace('   datetime traceExitTime;',"   datetime traceEntryTime;`n   double traceEntrySpread;`n   string traceEntryBasis;`n   datetime traceExitTime;")
 $s=$s.Replace('double           g_lastSimExecEntry = 0.0;',"datetime g_lastSimEntryTime=0;`ndouble g_lastSimEntrySpread=EMPTY_VALUE;`nstring g_lastSimEntryBasis=`"UNKNOWN`";`ndatetime g_histSignalEntryTime[];`ndouble g_histSignalEntrySpread[];`nstring g_histSignalEntryBasis[];`ndouble           g_lastSimExecEntry = 0.0;")
 $s=$s.Replace('   g_lastSimExecDir = 0;',"   g_lastSimEntryTime=0;g_lastSimEntrySpread=EMPTY_VALUE;g_lastSimEntryBasis=`"UNKNOWN`";`n   g_lastSimExecDir = 0;")
 $s=$s.Replace('         g_lastSimExecEntry = g_simCache[i].traceEntry;',"         g_lastSimEntryTime=g_simCache[i].traceEntryTime;g_lastSimEntrySpread=g_simCache[i].traceEntrySpread;g_lastSimEntryBasis=g_simCache[i].traceEntryBasis;`n         g_lastSimExecEntry = g_simCache[i].traceEntry;")
 $s=$s.Replace('   g_simCache[n].traceEntry = g_lastSimExecEntry;',"   g_simCache[n].traceEntryTime=g_lastSimEntryTime;g_simCache[n].traceEntrySpread=g_lastSimEntrySpread;g_simCache[n].traceEntryBasis=g_lastSimEntryBasis;`n   g_simCache[n].traceEntry = g_lastSimExecEntry;")
 $s=$s.Replace('   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);',"   g_lastSimEntryTime=sig.availableTime;g_lastSimEntrySpread=effectiveSpreadPts;g_lastSimEntryBasis=g_btSpreadPts>0?`"CONFIGURED_BAR_SPREAD`":`"HISTORICAL_BAR_SPREAD`";`n   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);")
 # The more-indented tick trace was also matched above: set its exact quote metadata immediately after capture.
 $s=$s.Replace('               halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);',"               g_lastSimEntryTime=(datetime)ticks[first].time;g_lastSimEntrySpread=(ticks[first].ask-ticks[first].bid)/point;g_lastSimEntryBasis=`"ENTRY_BID_ASK_QUOTE`";`n               halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);")
 $s=$s.Replace('   ArrayResize(g_histSignalR, ArraySize(g_histSignals));',"   ArrayResize(g_histSignalEntryTime,ArraySize(g_histSignals));ArrayResize(g_histSignalEntrySpread,ArraySize(g_histSignals));ArrayResize(g_histSignalEntryBasis,ArraySize(g_histSignals));`n   ArrayResize(g_histSignalR, ArraySize(g_histSignals));")
 $s=$s.Replace('      g_histSignalExecEntry[i] = g_lastSimExecEntry;',"      g_histSignalEntryTime[i]=g_lastSimEntryTime;g_histSignalEntrySpread[i]=g_lastSimEntrySpread;g_histSignalEntryBasis[i]=g_lastSimEntryBasis;`n      g_histSignalExecEntry[i] = g_lastSimExecEntry;")
 return $s
}
$p=Join-Path $root 'IndicatorCodeExamples/SolAdvanced/AuditTradeCsvAdapter.mqh'
Edit $p {
 param($s)
 $s=$s.Replace('         t.entry=g_histSignalExecEntry[i];',"         t.entryTime=g_histSignalEntryTime[i];t.localTime=t.entryTime;t.entryClock=g_histSignalEntryBasis[i]==`"ENTRY_BID_ASK_QUOTE`"?`"AUDIT_FILL`":`"MODELED_BAR_TIME`";`n         t.entrySpreadPoints=g_histSignalEntrySpread[i];t.spreadBasis=g_histSignalEntryBasis[i];`n         t.entry=g_histSignalExecEntry[i];")
 return $s
}
foreach($dir in @('orb','SolAdvanced')){foreach($f in @('AuditTradeCsv.mqh','AuditQuantFeatures.mqh','AuditSignalFeatures.mqh')){Copy-Item -LiteralPath "IndicatorCodeExamples/macrossover_orb/$f" -Destination "IndicatorCodeExamples/$dir/$f"}}
