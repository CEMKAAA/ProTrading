$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$base=Join-Path $root 'IndicatorCodeExamples'
$utf8=New-Object Text.UTF8Encoding($false)
function WriteUtf8($path,$text){$temp=$path+".csv-edit.tmp";[IO.File]::WriteAllText($temp,$text,$utf8);if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,($path+".csv-backup"))}else{[IO.File]::Move($temp,$path)}}
function Once($text,$old,$new){
 if(!$text.Contains($old)){throw "Anchor missing: $old"}
 if($text.IndexOf($old)-ne $text.LastIndexOf($old)){throw "Anchor repeated: $old"}
 return $text.Replace($old,$new)
}
$matrix=Join-Path $base 'macrossover_orb/TradeCalendarMatrix.mqh'
$m=[IO.File]::ReadAllText($matrix)
if(!$m.Contains('g_tcalCsvRequested')){
$m=Once $m '#include "DailyTradeQuota.mqh"' "#include `"DailyTradeQuota.mqh`"`n`nbool g_tcalCsvRequested=false;`nstring g_tcalCsvStatus=`"Current audit, one row per trade`";"
$m=Once $m '   if(g_tcalView==4&&g_tcalPage>0)' @'
   TCalObj("MOD_CSV",OBJ_BUTTON,x+16,y+457,178,18,"EXPORT AUDIT CSV",C'43,93,105',clrWhite,8);
   TCalObj("MOD_CSV_STATUS",OBJ_LABEL,x+205,y+459,0,0,StringSubstr(g_tcalCsvStatus,0,65),clrBlack,clrSilver,8);
   if(g_tcalView==4&&g_tcalPage>0)
'@
$m=Once $m '   string rowTags[6]=' "   if(clicked==TCalId(`"MOD_CSV`")){g_tcalCsvRequested=true;return true;}`n   string rowTags[6]="
}
foreach($folder in @('macrossover_orb','orb','SolAdvanced','')){WriteUtf8 (Join-Path (Join-Path $base $folder) 'TradeCalendarMatrix.mqh') $m}

$entries=@(@('macrossover_orb','MaCrossOverOrbEA.mq5'),@('orb','OrbUltimateEA_StrategyLibrary.mq5'),@('SolAdvanced','LiqNarrativeSol_Advanced.mq5'))
foreach($item in $entries){
 $dir=Join-Path $base $item[0];$path=Join-Path $dir $item[1]
 $text=[IO.File]::ReadAllText($path).Replace("`r`n","`n")
 if($text.Contains('#include "AuditTradeCsv.mqh"')){throw 'Already integrated'}
 $text=Once $text '#include "TradeCalendarMatrix.mqh"' "#include `"TradeCalendarMatrix.mqh`"`n#include `"AuditTradeCsv.mqh`""
 $text=[regex]::Replace($text,'(void OnDeinit\(const int reason\)\s*\{)','$1'+"`n   AxAbort(`"EA detached`");",1)
 $text=[regex]::Replace($text,'(void OnChartEvent\([^\n]+\)\s*\{)','$1'+"`n   if(AxEvent(id,lparam))return;",1)
 $text=Once $text "   if(TCalEvent(id,lparam,dparam,sparam))`n   {" "   if(TCalEvent(id,lparam,dparam,sparam))`n   {`n      if(g_tcalCsvRequested){g_tcalCsvRequested=false;AxStart();}"
 $settings=New-Object 'System.Collections.Generic.List[string]'
 foreach($match in [regex]::Matches($text,'(?m)^\s*input\s+\w+\s+(Inp\w+)\s*=')){
  $name=$match.Groups[1].Value
  if($name -notmatch '(Password|Secret|Token|ApiKey|Login)'){$settings.Add("   AxSetting(h,r,`"input_$name`",(string)$name);")}
 }
 if($item[0] -ne 'SolAdvanced'){
  $contract=[IO.File]::ReadAllText((Join-Path $dir 'OrbStrategyUserContract.mqh'))
  $dump=[regex]::Match($contract,'(?s)string OrbCustomRuntimeDump\(\).*?return out;\}').Value
  $vars=@([regex]::Matches($dump,'\bg_\w+\b')|ForEach-Object{$_.Value}|Select-Object -Unique)
  $vars+=@('g_rtCustomR','g_rtAdvancedReverse','g_rtAdvancedReverseMaxCostPct','g_orbRfEnabled')
  if($item[0] -eq 'macrossover_orb'){$vars+=@('g_maIndependent','g_maMaxConsecutive','g_maReverseExit','g_maReverseWait')}
  foreach($name in ($vars|Select-Object -Unique)){$settings.Add("   AxSetting(h,r,`"$name`",(string)$name);")}
  $settings.Add('   for(int i=0;i<ORB_REGIME_COUNT;i++)AxSetting(h,r,"regime_allowed_"+(string)i,(string)g_regimeAllowed[i]);')
  $settings.Add('   for(int i=0;i<ORB_RF_COUNT;i++)AxSetting(h,r,"rf_blocked_"+(string)i,(string)g_orbRfBlocked[i]);')
  if($item[0] -eq 'macrossover_orb'){$settings.Add('   AxSetting(h,r,"orderflow_config",McOfConfigText(g_mcOf));')}
  else {$settings.Add('   AxSetting(h,r,"broker_clock",OrbBrokerClockKey());')}
  $text=Once $text "void OrbResetHistoricalStats()`n{" "void OrbResetHistoricalStats()`n{`n   AxReset();"
  $text=Once $text "void CancelHistoricalAuditBuild()`n{" "void CancelHistoricalAuditBuild()`n{`n   AxAbort(`"CSV cancelled: audit restarted`");g_axReady=false;"
  $text=Once $text "void QueueHistoricalRedraw(const uint debounceMs=120)`n{" "void QueueHistoricalRedraw(const uint debounceMs=120)`n{`n   AxAbort(`"CSV cancelled: settings changed`");g_axReady=false;"
  # Timestamp is diagnostic metadata only. Mirror MaCross's existing trace in Orb.
  if($item[0] -eq 'orb'){
   $text=Once $text '   double simEntry;  // actual simulated fill entry' "   datetime entryTime; // first executable tick or modeled bar fill`n   double simEntry;  // actual simulated fill entry"
   $text=Once $text "   res.simEntry=entry;`n   res.simSl=sl;" "   res.simEntry=entry;res.entryTime=fillTime;`n   res.simSl=sl;"
   $text=$text.Replace('res.simEntry=entry;res.simSl=sl;res.simTarget=0;res.costR=0;','res.simEntry=entry;res.entryTime=0;res.simSl=sl;res.simTarget=0;res.costR=0;')
   $text=Once $text '   res.simEntry=NormalizePrice(entry);' "   res.entryTime=(g_btFillMode==BT_FILL_SIGNAL_CLOSE?BarCloseTime(entryTf,r[0].time):r[1].time);`n   res.simEntry=NormalizePrice(entry);"
   $advpath=Join-Path $dir 'OrbAdvancedAuditEngine.mqh';$adv=[IO.File]::ReadAllText($advpath)
   $adv=Once $adv 'res.simEntry=entry;res.simSl=sl;res.simTarget=fixedTarget?targetPrice:0.0;' 'res.simEntry=entry;res.entryTime=fillTime;res.simSl=sl;res.simTarget=fixedTarget?targetPrice:0.0;'
   $adv=Once $adv 'advanced.simEntry=entry;advanced.simSl=sl;advanced.simTarget=0;advanced.costR=0;' 'advanced.simEntry=entry;advanced.entryTime=0;advanced.simSl=sl;advanced.simTarget=0;advanced.costR=0;'
   WriteUtf8 $advpath $adv
  }
  $text=Once $text '      g_histTotal++;' @'
      AxTrade csv;ZeroMemory(csv);
      csv.signalTime=sigT;csv.availableTime=OrbSignalAvailableTime(entryT);
      csv.entryTime=sim.entryTime;csv.entryClock=sim.entryTime>0?"AUDIT_FILL":"UNAVAILABLE";
      csv.exitTime=sim.exitTime;csv.localTime=ServerToSessionLocal(csv.entryTime>0?csv.entryTime:csv.availableTime);
      csv.rawDirection=dir=="BUY"?1:-1;csv.direction=isBuy?1:-1;
      csv.valid=sim.valid;csv.closed=finalOutcome;csv.won=sim.netR>1e-8;
      csv.entry=sim.simEntry;csv.sl=sim.simSl;csv.tp=sim.simTarget;csv.exitPrice=sim.exitPrice;
      csv.netR=sim.netR;csv.costR=sim.costR;csv.outcome=sim.outcome;csv.reason=sim.invalidReason;
      csv.plannedEntry=entry;csv.plannedSl=sl;csv.plannedTp=tp1;
      csv.regionHigh=hi;csv.regionLow=lo;csv.regime=regimeBucket;csv.rf=rfIndex;
      csv.context=modernDetail+" "+entryDetail+" "+regimeDetail+" "+invertDetail;
      AxCapture(csv);
      g_histTotal++;
'@
  $text=Once $text "void FinalizeHistoricalAudit()`n{" "void FinalizeHistoricalAudit()`n{`n   AxSealCurrent();"
  $finish="   AxSeal(`"$($item[0])`",OrbStrategyPresetCurrentName(),g_rtSignalTf,g_histRunNow,h,r);"
 }else{
  $capture=[regex]::Match($text,'(?s)int LiqLibraryCapture\(double &v\[\]\).*?return ArraySize\(v\);\}').Value
  foreach($match in [regex]::Matches($capture,'v\[\d+\]=(?:\(double\))?(g_\w+(?:\[\d+\])?);')){
   $expr=$match.Groups[1].Value;$name=$expr.Replace('[','_').Replace(']','')
   $settings.Add("   AxSetting(h,r,`"$name`",(string)$expr);")
  }
  foreach($name in @('g_customTargetR','g_btSpreadPts','g_btSlippagePts','g_btCommissionPerLot')){$settings.Add("   AxSetting(h,r,`"$name`",(string)$name);")}
  foreach($field in @('gate','exitMode','stateVolume','flowVolume','independent','reverseExit','stateMultiplier','flowMultiplier','sensitivity','waitMinutes','entryAgeMinutes','maxSameOpen','reverseWaitMinutes')){
   $settings.Add("   AxSetting(h,r,`"nas_$field`",(string)g_lnNas.$field);")
  }
  $text=Once $text "void BeginHistoricalAuditProgress()`n{" "void BeginHistoricalAuditProgress()`n{`n   AxReset();"
  $text=Once $text "void RefreshAfterConfigChange(bool rebuildSignals = true)`n{" "void RefreshAfterConfigChange(bool rebuildSignals = true)`n{`n   AxAbort(`"CSV cancelled: settings changed`");g_axReady=false;"
  $text=Once $text '   EndHistoricalAuditProgress();' "   AxCollectSol();AxSealCurrent();`n   EndHistoricalAuditProgress();"
  $finish='   AxSeal("SolAdvanced",g_liqLibraryName,g_entryTf,TimeCurrent(),h,r);'
 }
 $settings.Add('   AxSetting(h,r,"time_matrix",TCalStrategyText());')
 $settings.Add('   AxSetting(h,r,"entry_direction",(string)g_entryDirection);')
 $settings.Add('   AxSetting(h,r,"daily_max_losses",(string)g_dailyMaxLosses);')
 $settings.Add('   AxSetting(h,r,"daily_target_wins",(string)g_dailyTargetWins);')
 $settings.Add('   AxSetting(h,r,"daily_start_minute",(string)g_dailyStartMinute);')
 $adapter="// Export adapter: diagnostics only. Does not evaluate signals or change orders.`nvoid AxSealCurrent()`n{`n   string h=`"`",r=`"`";`n"+($settings -join "`n")+"`n$finish`n}`n"
 if($item[0] -eq 'SolAdvanced'){
  $adapter+=@'
void AxCollectSol()
{
   ArrayFree(g_axTrades);
   for(int i=0;i<ArraySize(g_histSignals);i++)
   {
      string reason=g_histSignalInvalidReason[i];
      if(reason=="DAILY_QUOTA"||reason=="MAX_SAME_OPEN"||reason=="INVERSE_GAP_BLOCK")continue;
      ErlSignal sig=g_histSignals[i];AxTrade t;ZeroMemory(t);
      t.signalTime=sig.entryTime;t.availableTime=sig.availableTime;t.entryTime=sig.availableTime;
      t.entryClock="SCHEDULED_AVAILABLE_TIME";t.localTime=t.entryTime;
      t.rawDirection=sig.dir;t.valid=g_histSignalValid[i];t.closed=g_histSignalClosed[i];t.won=g_histSignalWon[i];
      t.direction=t.valid?g_histSignalExecDir[i]:EffectiveTradeDir(sig.dir);
      if(t.valid)
      {
         t.entry=g_histSignalExecEntry[i];t.sl=g_histSignalExecSl[i];t.tp=g_histSignalExecTp[i];
         t.exitTime=g_histSignalExitTime[i];t.netR=g_histSignalR[i];
      }
      t.costR=EMPTY_VALUE;t.outcome=t.valid?(t.closed?(t.won?"WIN":"LOSS"):"OPEN"):"DATA";
      t.reason=t.valid?g_histSignalExitReason[i]:reason;
      t.plannedEntry=sig.entry;t.plannedSl=sig.sl;t.plannedTp=sig.tp1;t.regionHigh=sig.fvgHigh;t.regionLow=sig.fvgLow;
      t.regime=-1;t.rf=-1;t.context=sig.reason+" | sweep="+AxNumber(sig.sweepLevel)+" | external_target="+AxNumber(sig.externalTarget);
      AxCapture(t);
   }
}
'@
 }
 WriteUtf8 (Join-Path $dir 'AuditTradeCsvAdapter.mqh') $adapter
 $text+="`n#include `"AuditTradeCsvAdapter.mqh`"`n"
 WriteUtf8 $path $text
 if($item[0] -ne 'macrossover_orb'){Copy-Item -LiteralPath (Join-Path $base 'macrossover_orb/AuditTradeCsv.mqh') -Destination (Join-Path $dir 'AuditTradeCsv.mqh')}
}
