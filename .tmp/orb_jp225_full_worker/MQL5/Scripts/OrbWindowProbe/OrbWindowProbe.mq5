#property strict
#define OnInit ProbeOriginalInit
#define OnDeinit ProbeOriginalDeinit
#define OnTick ProbeOriginalTick
#define OnTimer ProbeOriginalTimer
#define OnChartEvent ProbeOriginalEvent
#define OnTradeTransaction ProbeOriginalTransaction
#include "OrbUltimateEA_StrategyLibrary.mq5"
string trace="";
void WriteInternalSimAudit(string source,datetime sigTime,datetime simEnd,string dir,double plannedEntry,double plannedSl,const HistResult &sim,string detail)
{
   if(source!="dashboard_hist")return;
   trace+=(string)sigTime+"|"+dir+"|"+sim.outcome+"|"+(string)sim.exitTime+"|"+AuditMemoPrice(sim.exitPrice)
      +"|"+AuditMemoPrice(sim.netR)+"|"+AuditMemoPrice(sim.simEntry)+"|"+AuditMemoPrice(sim.simSl)
      +"|"+AuditMemoPrice(sim.simTarget)+"|"+(string)sim.valid+"|"+sim.invalidReason+"\n";
}
string ResultIdentity()
{
   string s=trace+"|"+(string)g_histTotal+"|"+(string)g_histWins+"|"+(string)g_histLosses+"|"+(string)g_histOpen
      +"|"+(string)g_histInvalid+"|"+AuditMemoPrice(g_histNetR)+"|"+AuditMemoPrice(g_histMinCumulativeR)
      +"|"+AuditMemoPrice(g_histMaxPeakDrawdownR);
   for(int i=0;i<6;i++)s+="|"+(string)g_regimeWins[i]+"|"+(string)g_regimeLosses[i];
   for(int i=0;i<12;i++)s+="|"+(string)g_orbRfWins[i]+"|"+(string)g_orbRfLosses[i];
   return OrbMlSha256(s);
}
bool RunWindow(int weeks)
{
   trace="";g_rtHistoricalWeeks=weeks;g_histNeedsRedraw=true;g_lastHistBuild=0;
   DrawHistoricalSignals();ulong started=GetTickCount64();
   while(g_histAuditRunning&&!IsStopped()&&GetTickCount64()-started<600000)ProcessHistoricalAuditStep();
   EventKillTimer();return !g_histAuditRunning&&!g_histCoveragePending&&g_histTotal>0;
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0||_Symbol!="JP225m")return;
   // Do NOT call OnInit: no plan restoration, news publication or order lifecycle.
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_auditRuntime=false;
   g_rtSignalTf=PERIOD_M15;g_rtUseDelay=false;g_rtFilterAtr=false;g_rtFilterVol=false;
   g_rtPipSlMode=true;g_rtPipSlPips=4000;g_rtHalfBeLeg=0;g_rtTargetLeg=4;
   g_rtAdvancedAuditEngine=true;g_rtNasAdditionalExit=true;g_rtNasOppositeExitWaitMinutes=120;
   g_rtNasFlowVolumeFilter=true;g_rtNasFlowVolumeMultiplier=1.5;
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;g_btNativeParity=InpBacktestNativeParity;
   g_btSpreadPts=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   for(int i=0;i<6;i++)g_regimeAllowed[i]=true;
   RegimeV3Update(true);
   FolderCreate("OrbWindowProbe");
   int h=FileOpen("OrbWindowProbe\\results.jsonl",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(h==INVALID_HANDLE)return;
   // Load cold data first; DATA rows remain explicit, not relabeled.
   RunWindow(260);RunWindow(260);
   int windows[]={260,52,20,10,5,2,260};
   for(int i=0;i<ArraySize(windows)&&!IsStopped();i++)
   {
      long prep=g_orbPrepMemoHits,hits=g_orbReplayMemoHits;ulong start=GetTickCount64();
      bool ok=RunWindow(windows[i]);ulong warm=GetTickCount64()-start;string a=ResultIdentity();
      hits=g_orbReplayMemoHits-hits;prep=g_orbPrepMemoHits-prep;
      g_orbPrepMemo.Reset("FORCE_COLD_"+(string)i);g_orbReplayMemo.Reset("FORCE_COLD_"+(string)i);
      start=GetTickCount64();ok=RunWindow(windows[i])&&ok;ulong cold=GetTickCount64()-start;string b=ResultIdentity();
      string row="{\"weeks\":"+(string)windows[i]+",\"warm_ms\":"+(string)warm+",\"cold_ms\":"+(string)cold
         +",\"prep_hits\":"+(string)prep+",\"memo_hits\":"+(string)hits+",\"signals\":"+(string)g_histTotal
         +",\"same\":"+(a==b?"true":"false")+",\"ok\":"+(ok?"true":"false")+"}";
      FileWriteString(h,row+"\n");FileFlush(h);Print("ORB_WINDOW_PROBE ",row);
   }
   FileClose(h);EventKillTimer();
}
