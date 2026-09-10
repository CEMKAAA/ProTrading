$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build_orb_ml_export_probe.ps1')
$root=Split-Path -Parent $PSScriptRoot
$seed=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLExportProbe'
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLHistoryProbe'
[IO.Directory]::CreateDirectory($dest)|Out-Null
$source=[IO.File]::ReadAllText((Join-Path $seed 'OrbMLExportProbe.mq5'))
$source=$source.Substring(0,$source.LastIndexOf('void OnStart()'))
$source+=@'
bool ProbeAuditRun(bool ml,int &total,int &wins,int &losses,double &net,double &dd)
{
   g_mlEnabled=ml;SetHistoricalWeeks(52);QueueHistoricalRedraw(0);
   ulong start=GetTickCount64();
   while(!IsStopped()&&GetTickCount64()-start<240000)
   {
      ProcessQueuedHistoricalRedraw();ProcessHistoricalAuditStep();
      if(!g_histAuditRunning&&!g_histRedrawQueued)break;
      Sleep(1);
   }
   total=g_histTotal;wins=g_histWins;losses=g_histLosses;net=g_histNetR;dd=g_histMaxPeakDrawdownR;
   Print("ML_HISTORY_RUN ml=",ml," total=",total," W=",wins," L=",losses," R=",net," DD=",dd,
      " ",OrbMlHistorySummary()," elapsed=",(double)(GetTickCount64()-start)/1000.0);
   return !g_histAuditRunning&&!g_histRedrawQueued&&!g_histCoveragePending&&g_mlHistoryErrors==0;
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;
   int failed=0,slot=-1;OrbStrategyPreset p;
   for(int i=0;i<OrbStrategyPresetCount();i++)
      if(OrbStrategyPresetLoad(i,p)&&p.id=="jp_05_adv"){slot=i;break;}
   if(slot<0){Print("ML_HISTORY_PROBE FAILED preset");return;}
   g_strategyPresetIndex=slot;g_strategyCandidateIndex=slot;OrbStrategyPresetApplyValues(p);
   string values[];ArrayResize(values,50);
   int f=FileOpen("OrbMLCampaign_20260909_v3\\Settings\\"+p.id+".txt",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON,0,CP_UTF8);
   if(f==INVALID_HANDLE){Print("ML_HISTORY_PROBE FAILED settings");return;}
   for(int i=0;i<50;i++)values[i]=FileReadString(f);FileClose(f);
   if(!OrbCustomRuntimeRead(values,4,true)||!OrbMlLoad()){Print("ML_HISTORY_PROBE FAILED model ",g_mlStatus);return;}
   RegimeV3Update(true);
   int n0,w0,l0,n1,w1,l1,n2,w2,l2;double r0,d0,r1,d1,r2,d2;
   if(!ProbeAuditRun(false,n0,w0,l0,r0,d0))failed++;
   if(!ProbeAuditRun(true,n1,w1,l1,r1,d1))failed++;
   int rejected=g_mlHistoryRejected;
   if(n0<=0||n1<=0||n1>=n0||n1+rejected!=n0||n1!=g_mlHistoryAllowed)failed++;
   if(!ProbeAuditRun(false,n2,w2,l2,r2,d2))failed++;
   if(n0!=n2||w0!=w2||l0!=l2||MathAbs(r0-r2)>1e-9||MathAbs(d0-d2)>1e-9)failed++;
   // Same model with a changed setting must not silently become an unfiltered audit.
   g_mlEnabled=true;g_rtPipSlPips+=1;OrbMlHistoryBegin();
   HistResult dummy;ZeroMemory(dummy);
   if(OrbMlHistoryAllow(TimeCurrent()-86400,"BUY",1,0,TimeCurrent()-86400,dummy)||g_mlHistoryErrors!=1)failed++;
   // Dataset export remains baseline even while live ML is enabled.
   g_mlExport=true;OrbMlHistoryBegin();
   if(g_mlHistoryFiltered||!OrbMlHistoryAllow(0,"BUY",0,0,0,dummy))failed++;
   g_mlExport=false;
   string report="failures="+(string)failed+" baseline="+(string)n0+" W="+(string)w0+" L="+(string)l0
      +" R="+DoubleToString(r0,4)+" DD="+DoubleToString(d0,4)+" filtered="+(string)n1
      +" W="+(string)w1+" L="+(string)l1+" R="+DoubleToString(r1,4)+" DD="+DoubleToString(d1,4)
      +" rejected="+(string)rejected+" restored="+(string)n2;
   Print("ML_HISTORY_PROBE ",report);
   int out=FileOpen("ml_history_probe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(out!=INVALID_HANDLE){FileWrite(out,report);FileClose(out);}
   EventKillTimer();
}
'@
[IO.File]::WriteAllText((Join-Path $dest 'OrbMLHistoryProbe.mq5'),$source,[Text.UTF8Encoding]::new($false))
Get-ChildItem -LiteralPath $seed -Filter '*.mqh'|Copy-Item -Destination $dest
$report=Join-Path $root 'logs/demo_sync_20260909_v688'
[IO.Directory]::CreateDirectory($report)|Out-Null
$ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbMLHistoryProbe\OrbMLHistoryProbe`r`nSymbol=JP225m`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $report 'history_probe.ini'),$ini)
Write-Output 'No-order ML history integration probe generated'
