param([string]$Campaign='OrbMLCampaign_20260909')
$ErrorActionPreference='Stop'
if($Campaign -notmatch '^OrbMLCampaign_[A-Za-z0-9_]+$'){throw 'Unsafe campaign name'}
& (Join-Path $PSScriptRoot 'build_orb_ml_export_probe.ps1')
$root=Split-Path -Parent $PSScriptRoot
$seed=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLExportProbe'
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLCampaign'
[IO.Directory]::CreateDirectory($dest)|Out-Null
$source=[IO.File]::ReadAllText((Join-Path $seed 'OrbMLExportProbe.mq5'))
$source=$source.Substring(0,$source.LastIndexOf('void OnStart()'))
# Freeze the audit observation cutoff only in the generated research script.
if(!$source.Contains('datetime currentTime=TimeCurrent();')){throw 'Audit cutoff anchor changed'}
$source=$source.Replace('datetime currentTime=TimeCurrent();',"datetime currentTime=D'2026.09.09 00:00:00';")
$source+=@'
void CampaignRecord(int index,const OrbStrategyPreset &p,const string status,const string detail)
{
   string path="CAMPAIGN\\manifest_"+_Symbol+".tsv";
   int h=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,'\t',CP_UTF8);
   if(h==INVALID_HANDLE){Print("CAMPAIGN MANIFEST ERROR ",GetLastError());return;}
   if(FileSize(h)==0)FileWrite(h,"index","id","name","symbol","chart_tf","signal_tf","status","rows","invalid","missing_features","net_r","min_cum_r","wr","spread_points","config","dataset","path","detail");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,index,p.id,p.name,_Symbol,(int)_Period,PeriodSeconds(g_rtSignalTf),status,g_mlWritten,g_histInvalid,g_mlMissing,
      DoubleToString(g_histNetR,12),DoubleToString(g_histMinCumulativeR,12),DoubleToString(g_histWins+g_histLosses>0?100.0*g_histWins/(g_histWins+g_histLosses):0,8),
      g_btSpreadPts,g_mlConfig,g_mlDataset,g_mlFilePath,detail);
   FileFlush(h);FileClose(h);
   Print("CAMPAIGN ",index," ",p.id," ",status," ",detail);
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;
   g_rtAdvancedAuditEngine=true;g_rtSlDistancePct=InpSlDistancePct;
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;g_btNativeParity=InpBacktestNativeParity;
   g_btSpreadPts=InpBacktestSpreadPts>0?InpBacktestSpreadPts:(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   // Frozen first-export broker cost observations; do not change costs between retries.
   if(_Symbol=="JP225m")g_btSpreadPts=31.0;
   else if(_Symbol=="USDJPYm")g_btSpreadPts=10.0;
   else if(_Symbol=="USTECm")g_btSpreadPts=112.0;
   g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   string base=OrbCustomRuntimeDump(),baseFields[];StringSplit(base,'\n',baseFields);
   OrbUserReload(true);int count=OrbStrategyPresetCount();
   for(int i=0;i<count&&!IsStopped();i++)
   {
      OrbStrategyPreset p;if(!OrbStrategyPresetLoad(i,p))continue;
      if(!OrbStrategyPresetFamilyMatches(p.family))continue;
      if(FileIsExist("CAMPAIGN\\Done\\"+p.id+".done",FILE_COMMON))continue;
      CancelHistoricalAuditBuild();g_histRedrawQueued=false;g_lastHistBuild=0;g_histNeedsRedraw=true;
      g_mlWritten=0;g_mlMissing=0;g_mlConfig="";g_mlDataset="";g_mlFilePath="";
      OrbCustomRuntimeRead(baseFields,0,true);
      string reason="";
      if(OrbUserPreset(p)&&!OrbUserValidate(p,reason)){CampaignRecord(i,p,"CONFIG_BLOCK",reason);continue;}
      OrbStrategyPresetApplyValues(p);g_strategyPresetIndex=i;g_strategyCandidateIndex=i;
      if(!OrbStrategyPresetMatchesRuntime(p)){CampaignRecord(i,p,"CONFIG_BLOCK","roundtrip mismatch");continue;}
      RegimeV3Update(true);
      int snapshot=FileOpen("CAMPAIGN\\Settings\\"+p.id+".txt",FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(snapshot!=INVALID_HANDLE){OrbMlWriteUtf8(snapshot,p.name+"\n"+_Symbol+"\n"+(string)(int)_Period+"\n"+OrbCustomInputSignature()+"\n"+OrbCustomRuntimeDump());FileClose(snapshot);}
      if(!OrbMlStartExport()){CampaignRecord(i,p,"START_BLOCK",g_mlStatus);continue;}
      CampaignRecord(i,p,"STARTED","frozen cutoff 2026.09.09 00:00 broker");
      ulong started=GetTickCount64(),last=0;
      while(g_mlExport&&!IsStopped()&&GetTickCount64()-started<1200000)
      {
         if(!g_histAuditRunning&&g_histCoveragePending&&TimeLocal()>=g_histCoverageNextRetry)QueueHistoricalRedraw(0);
         ProcessQueuedHistoricalRedraw();ProcessHistoricalAuditStep();OrbMlExportStep();
         if(GetTickCount64()-last>15000){Print("CAMPAIGN PROGRESS ",p.id," ",g_mlStatus);last=GetTickCount64();}
         Sleep(1);
      }
      if(g_mlExport)OrbMlAbort("CAMPAIGN TIMEOUT/STOP");
      bool complete=FileIsExist(g_mlFilePath+".complete",FILE_COMMON);
      CampaignRecord(i,p,complete?"EXPORTED":"EXPORT_FAILED",g_mlStatus);
      if(complete)
      {
         int done=FileOpen("CAMPAIGN\\Done\\"+p.id+".done",FILE_WRITE|FILE_BIN|FILE_COMMON);
         if(done!=INVALID_HANDLE){OrbMlWriteUtf8(done,g_mlFilePath+"\n"+g_mlConfig+"\n");FileClose(done);}
      }
      EventKillTimer();
   }
   int done=FileOpen("CAMPAIGN\\symbol_"+_Symbol+".finished",FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(done!=INVALID_HANDLE){OrbMlWriteUtf8(done,"finished\n");FileClose(done);}
   Print("CAMPAIGN SYMBOL COMPLETE ",_Symbol);EventKillTimer();
}
'@
function Isolate([string]$text){
    $text=$text.Replace('CAMPAIGN\\',$Campaign+'\\')
    $text=$text.Replace('"OrbML\\','"'+$Campaign+'\\')
    return $text.Replace('"OrbStrategyUserLibrary\\','"'+$Campaign+'\\UserStrategies\\')
}
[IO.File]::WriteAllText((Join-Path $dest 'OrbMLCampaign.mq5'),(Isolate $source),[Text.UTF8Encoding]::new($false))
foreach($f in Get-ChildItem -LiteralPath $seed -Filter '*.mqh'){
    $text=Isolate ([IO.File]::ReadAllText($f.FullName))
    if($f.Name -eq 'OrbStrategyMLPipeline.mqh' -and $text.Contains('datetime entryTime=OrbSignalAvailableTime(record.entryBar);')){
        # Research exporter timestamps must match the simulator's M1 imbalance
        # entry clock, not the M5/M15 breakout clock. No strategy rules change.
        $text=$text.Replace('datetime entryTime=OrbSignalAvailableTime(record.entryBar);','datetime entryTime=BarCloseTime(RuntimeEntryTf(),record.entryBar);')
        # Preserve the complete audit-capture invariant; only compact after its
        # row-count check when the final as-of timestamp has been assigned.
        $text=$text.Replace('g_mlAsOf=g_histRunNow;',
            'g_mlAsOf=g_histRunNow; int kept=0; for(int j=0;j<ArraySize(g_mlTrades);j++){if(OrbSignalAvailableTime(g_mlTrades[j].signalBar)>g_mlAsOf||BarCloseTime(RuntimeEntryTf(),g_mlTrades[j].entryBar)>g_mlAsOf)continue; if(kept!=j)g_mlTrades[kept]=g_mlTrades[j]; kept++;} ArrayResize(g_mlTrades,kept);')
    }
    [IO.File]::WriteAllText((Join-Path $dest $f.Name),$text,[Text.UTF8Encoding]::new($false))
}
[IO.File]::WriteAllText((Join-Path $dest '.gitignore'),"*`n")
$out=Join-Path $root ('logs/'+$Campaign)
[IO.Directory]::CreateDirectory($out)|Out-Null
foreach($symbol in @('JP225m','USDJPYm','USTECm')){
    $ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbMLCampaign\OrbMLCampaign`r`nSymbol=$symbol`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
    [IO.File]::WriteAllText((Join-Path $out ($symbol+'.ini')),$ini)
}
Write-Output ('No-order campaign script prepared: '+$dest)
