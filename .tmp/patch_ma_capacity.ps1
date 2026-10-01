$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$encoding=New-Object Text.UTF8Encoding($false)
$header=Join-Path $root 'IndicatorCodeExamples/macrossover_orb/MaIndependentEntries.mqh'
$labHeader=Join-Path $root 'IndicatorCodeExamples/entry_engine_lab/MaIndependentEntries.mqh'
$copy=[IO.File]::ReadAllText($header).Replace('"MA_MULTI."','"ENTRYLAB_MULTI."').Replace('"MaIndependent_"','"EntryLabIndependent_"')
[IO.File]::WriteAllText($labHeader,$copy,$encoding)
function ReplaceChecked([string]$text,[string]$old,[string]$new,[int]$count=1){
 if(([regex]::Matches($text,[regex]::Escape($old))).Count -ne $count){throw "Unexpected source fragment: $old"}
 return $text.Replace($old,$new)
}
foreach($entry in @(@('macrossover_orb','MaCrossOverOrbEA.mq5'),@('entry_engine_lab','EntryEngineLabEA.mq5'))){
 $path=Join-Path $root ('IndicatorCodeExamples/'+$entry[0]+'/'+$entry[1])
 $s=[IO.File]::ReadAllText($path).Replace("`r`n","`n")
 $s=ReplaceChecked $s ' // 1..1000; same-direction series, not concurrent positions' ' // 1..1000; total concurrently open instance-owned native positions'
 $s=ReplaceChecked $s 'g_maHistSeriesDir=0;g_maHistSeriesCount=0;' 'g_maHistSeriesDir=0;g_maHistSeriesCount=0;MaHistoricalCapacityReset();' 2
 $s=ReplaceChecked $s @'
      // Exhausted same-direction candidates cannot become trades. Keep the raw
      // event stream for reversal detection, but skip entry resolution and replay.
      if(g_maIndependent&&g_maHistSeriesDir==(EffectiveOrbDirection(dir)=="BUY"?1:-1)
         &&g_maHistSeriesCount>=g_maMaxConsecutive)
'@ @'
      // Preserve raw signals for exits; reject entries when all concurrent slots are occupied.
      if(g_maIndependent&&!MaHistoricalCapacityAllows(OrbSignalAvailableTime(sigT)))
'@
 $s=ReplaceChecked $s '||!MaSeriesAllows(isBuy?1:-1,g_maHistSeriesDir,g_maHistSeriesCount,g_maMaxConsecutive))' '||!MaHistoricalCapacityAllows(OrbSignalAvailableTime(entryT)))'
 $s=ReplaceChecked $s 'if(sim.valid)g_maHistSeriesCount++;' @'
// Missing exit evidence conservatively occupies a slot through the audit cutoff.
         MaHistoricalCapacityOccupy(sim.valid&&sim.outcome!="open"&&sim.exitTime>0?sim.exitTime:g_histRunNow+1);
'@
 $s=ReplaceChecked $s @'
   if(g_maIndependent&&g_maSeriesDir==(EffectiveOrbDirection(dir)=="BUY"?1:-1)
      &&g_maSeriesCount>=g_maMaxConsecutive)
   {g_lastExecStatus="CONSECUTIVE LIMIT";return;}
'@ @'
   if(g_maIndependent&&!MaOpenCapacityAllows(MaNativeOpenCount(),g_maMaxConsecutive))
   {g_lastExecStatus="OPEN POSITION LIMIT";return;}
'@
 $s=ReplaceChecked $s 'CreateButton("BTN_MA_REV_APPLY",x+313,rootY+309,90,18,"APPLY EXIT",C''38,101,176'');' "CreateButton(`"BTN_MA_REV_APPLY`",x+313,rootY+309,90,18,`"APPLY EXIT`",C'38,101,176');`n   MaRenderOpenCounter(true);"
 $s=ReplaceChecked $s 'OrbProOnTradeTransaction(trans);' "OrbProOnTradeTransaction(trans);`n   MaRenderOpenCounter();"
 $s=ReplaceChecked $s 'ProcessQueuedHistoricalRedraw();' "if(coreDue)MaRenderOpenCounter();`n      ProcessQueuedHistoricalRedraw();"
 if($entry[0] -eq 'entry_engine_lab'){$s=ReplaceChecked $s 'EntryEngineLab-1.02' 'EntryEngineLab-1.03'}
 else{$s=ReplaceChecked $s 'MaCrossORB-0.14-Trender-preview' 'MaCrossORB-0.15-OpenCapacity'}
 [IO.File]::WriteAllText($path,$s,$encoding)
 $path=Join-Path $root ('IndicatorCodeExamples/'+$entry[0]+'/OrbStrategyUserMetrics.mqh')
 $s=[IO.File]::ReadAllText($path)
 $s=ReplaceChecked $s 'string MaEntryMetricMeta(bool independent,int maximum){return !independent&&maximum==1?"":"|MAENTRY1="+(independent?"1":"0")+","+(string)maximum;}' 'string MaEntryMetricMeta(bool independent,int maximum){if(independent)return "|MAENTRY2_TOTAL_OPEN="+(string)maximum;return maximum==1?"":"|MAENTRY1=0,"+(string)maximum;}'
 [IO.File]::WriteAllText($path,$s,$encoding)
}
