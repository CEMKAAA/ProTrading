$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
function Replace-One([string]$path,[string]$old,[string]$new){
 $text=[IO.File]::ReadAllText($path)
 if(($text.Split(@($old),[StringSplitOptions]::None).Count-1) -ne 1){throw "Expected one match: $path $old"}
 [IO.File]::WriteAllText($path,$text.Replace($old,$new),$utf8)
}
foreach($path in @('IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5','IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5')){
 $text=[IO.File]::ReadAllText($path)
 $old='      if(!TCalAllows(ServerToSessionLocal(OrbSignalAvailableTime(entryT))))'+"`n"+'      {g_histFiltered++;return;}'+"`n"
 if(!$text.Contains($old)){throw "Early calendar gate missing: $path"}
 $text=$text.Replace($old,'')
 $needle='      if(sim.invalidReason=="INVERSE_GAP_BLOCK")'
 if(!$text.Contains($needle)){$needle='   if(sim.invalidReason=="INVERSE_GAP_BLOCK")'}
 $gate=@'
      if(!TCalAllows(ServerToSessionLocal(AxEntryAt(sim.entryTime,OrbSignalAvailableTime(entryT)))))
      {
         g_histFiltered++;
         g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
         return;
      }
'@
 if(!$text.Contains($needle)){throw "Post-simulation gate point missing: $path"}
 $text=$text.Replace($needle,$gate+"`n"+$needle)
 $text=$text.Replace('csv.entryClock=sim.entryTime>0?"AUDIT_FILL":"UNAVAILABLE"','csv.entryClock=AxEntryClock(sim.entryTime,sim.entrySpreadPoints)')
 $text=$text.Replace('csv.reason=sim.invalidReason','csv.reason=AxExitReason(sim.valid,finalOutcome,sim.invalidReason,sim.outcome)')
 $text=$text.Replace('TCalRecord(ServerToSessionLocal(OrbSignalAvailableTime(entryT)),sim.netR)','TCalRecord(csv.localTime,sim.netR)')
 $text=$text.Replace("void OnTimer()`n{","void OnTimer()`n{`r`n   AxTimer();")
 [IO.File]::WriteAllText($path+".csvpatch",$text,$utf8); Move-Item -LiteralPath ($path+".csvpatch") -Destination $path -Force
}
$path='IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5'
$text=[IO.File]::ReadAllText($path)
$text=$text.Replace('if(g_tcalEnabled||g_entryDirection!=0)','if(g_entryDirection!=0)')
$text=$text.Replace('if(TCalAllows(g_histSignals[i].availableTime)&&EntryDirectionAllows(EffectiveTradeDir(g_histSignals[i].dir)))','if(EntryDirectionAllows(EffectiveTradeDir(g_histSignals[i].dir)))')
$needle='      g_histSignalR[i] = r;'
$gate=@'
      if(!TCalAllows(AxEntryAt(g_lastSimEntryTime,g_histSignals[i].availableTime)))
      {
         g_histSignalR[i]=0;g_histSignalClosed[i]=false;g_histSignalWon[i]=false;
         g_histSignalValid[i]=false;g_histSignalInvalidReason[i]="TIME_MATRIX";
         g_histSignalExitTime[i]=0;g_histSignalExitReason[i]="TIME_MATRIX";continue;
      }
'@
if(($text.Split(@($needle),[StringSplitOptions]::None).Count-1) -ne 1){throw 'Sol insertion mismatch'}
$text=$text.Replace($needle,$gate+"`n"+$needle)
$text=$text.Replace('TCalRecordOutcome(g_histSignals[i].availableTime,won)','TCalRecordOutcome(AxEntryAt(g_histSignalEntryTime[i],g_histSignals[i].availableTime),won)')
$text=$text.Replace('g_histSignalInvalidReason[i]=="DAILY_QUOTA"||g_histSignalInvalidReason[i]=="INVERSE_GAP_BLOCK"','g_histSignalInvalidReason[i]=="TIME_MATRIX"||g_histSignalInvalidReason[i]=="DAILY_QUOTA"||g_histSignalInvalidReason[i]=="INVERSE_GAP_BLOCK"')
$text=$text.Replace("void OnTimer()`n{","void OnTimer()`n{`r`n   AxTimer();")
[IO.File]::WriteAllText($path+".csvpatch",$text,$utf8); Move-Item -LiteralPath ($path+".csvpatch") -Destination $path -Force
Replace-One 'IndicatorCodeExamples/SolAdvanced/AuditTradeCsvAdapter.mqh' 'if(reason=="DAILY_QUOTA"||reason=="MAX_SAME_OPEN"||reason=="INVERSE_GAP_BLOCK")' 'if(reason=="TIME_MATRIX"||reason=="DAILY_QUOTA"||reason=="MAX_SAME_OPEN"||reason=="INVERSE_GAP_BLOCK")'
Replace-One 'IndicatorCodeExamples/SolAdvanced/LiqSolAdvancedNas.mqh' '(g_histSignalInvalidReason[i]=="MAX_SAME_OPEN"||g_histSignalInvalidReason[i]=="DAILY_QUOTA")' '(g_histSignalInvalidReason[i]=="TIME_MATRIX"||g_histSignalInvalidReason[i]=="MAX_SAME_OPEN"||g_histSignalInvalidReason[i]=="DAILY_QUOTA")'
foreach($name in @('AuditTradeCsv.mqh','AuditQuantFeatures.mqh','AuditKivancExport.mqh')){
 foreach($dir in @('macrossover_orb','SolAdvanced')){Copy-Item -LiteralPath ('IndicatorCodeExamples/orb/'+$name) -Destination ('IndicatorCodeExamples/'+$dir+'/'+$name) -Force}
}
