#property strict
datetime g_probeNow=D'2026.09.30 19:00';
datetime ProbeClock(){return g_probeNow;}
datetime ProbeClock(MqlDateTime &dt){TimeToStruct(g_probeNow,dt);return g_probeNow;}
#define TimeCurrent ProbeClock
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "MaCrossOverOrbEA.mq5"
#undef TimeCurrent
string Identity()
{
   string text=(string)g_histTotal+"|"+(string)g_histWins+"|"+(string)g_histLosses+"|"+(string)g_histOpen
      +"|"+(string)g_histInvalid+"|"+AuditMemoPrice(g_histNetR)+"|"+AuditMemoPrice(g_histMinCumulativeR)
      +"|"+AuditMemoPrice(g_histMaxPeakDrawdownR);
   for(int i=0;i<ArraySize(g_axTrades);i++)
   {
      AxTrade t=g_axTrades[i];text+="\n"+(string)t.signalTime+"|"+(string)t.entryTime+"|"+(string)t.exitTime
         +"|"+(string)t.direction+"|"+t.outcome+"|"+t.reason+"|"+AuditMemoPrice(t.netR)
         +"|"+AuditMemoPrice(t.entry)+"|"+AuditMemoPrice(t.sl)+"|"+AuditMemoPrice(t.tp)+"|"+AuditMemoPrice(t.exitPrice);
   }
   return OrbMlSha256(text);
}
bool Run(int weeks)
{
   g_rtHistoricalWeeks=weeks;g_histNeedsRedraw=true;g_lastHistBuild=0;
   DrawHistoricalSignals();ulong started=GetTickCount64();
   while(g_histAuditRunning&&!IsStopped()&&GetTickCount64()-started<300000)ProcessHistoricalAuditStep();
   EventKillTimer();return !g_histAuditRunning&&!g_histCoveragePending&&g_histTotal>0;
}
void OnStart()
{
   if(_Symbol!="USDJPYm"||StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   string old=HistoricalGenerationRoot(1)+"TEST",keep=HistoricalGenerationRoot(2)+"TEST";
   string legacy=PREFIX+"HIST_OLD_TEST",unrelated="MA_WINDOW_UNRELATED";
   ObjectCreate(0,old,OBJ_LABEL,0,0,0);ObjectCreate(0,keep,OBJ_LABEL,0,0,0);
   ObjectCreate(0,legacy,OBJ_LABEL,0,0,0);ObjectCreate(0,unrelated,OBJ_LABEL,0,0,0);
   g_histBuildGeneration=2;CommitHistoricalSnapshot();
   bool clean=ObjectFind(0,old)<0&&ObjectFind(0,legacy)<0&&ObjectFind(0,keep)>=0&&ObjectFind(0,unrelated)>=0;
   BeginHistoricalSnapshot();ObjectCreate(0,old,OBJ_LABEL,0,0,0);CommitHistoricalSnapshot();
   clean=clean&&ObjectFind(0,old)>=0&&ObjectFind(0,keep)<0&&ObjectFind(0,unrelated)>=0;
   BeginHistoricalSnapshot();ObjectCreate(0,keep,OBJ_LABEL,0,0,0);CancelHistoricalAuditBuild();
   clean=clean&&ObjectFind(0,old)>=0&&ObjectFind(0,keep)<0&&ObjectFind(0,unrelated)>=0;
   DeleteHist();clean=clean&&ObjectFind(0,keep)<0&&ObjectFind(0,unrelated)>=0;
   ObjectDelete(0,unrelated);
   OrbUserReload();int slot=66;
   if(!g_userStrategies[slot].valid)return;
   string tokens[];StringSplit(g_userStrategies[slot].runtime,'\n',tokens);
   if(!OrbCustomRuntimeRead(tokens,0,true)||!TCalStrategyApplyText(g_userStrategies[slot].timeMatrix))return;
   g_maIndependent=g_userStrategies[slot].independent;g_maMaxConsecutive=g_userStrategies[slot].maxSeries;
   g_maReverseExit=g_userStrategies[slot].reverseExit;g_maReverseWait=g_userStrategies[slot].reverseWait;
   g_rtAdvancedReverse=g_userStrategies[slot].advancedReverse;
   g_mcOf=g_userStrategies[slot].orderFlow;
   for(int i=0;i<6;i++)g_regimeAllowed[i]=OrbPresetRegimeAllowed(g_userStrategies[slot].preset,i);
   g_orbRfEnabled=g_userStrategies[slot].preset.rfMaster;
   for(int i=0;i<12;i++)g_orbRfBlocked[i]=OrbPresetRfBlocked(g_userStrategies[slot].preset,i);
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_auditRuntime=false;g_axNotify=false;g_axSchedule=false;
   g_probeNow=iTime(_Symbol,PERIOD_M5,0)+2;
   int f=FileOpen("MaAuditReplayWindowProbe_0b62be8a0d.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE)return;
   ulong start=GetTickCount64();bool broad=Run(260);long large=(long)(GetTickCount64()-start);
   long hits=g_orbReplayMemoHits,misses=g_orbReplayMemoMisses,epochs=g_probeEpochChanges;
   start=GetTickCount64();bool warm=Run(156);long warmMs=(long)(GetTickCount64()-start);string a=Identity();
   string diagnostic="warm_hits="+(string)(g_orbReplayMemoHits-hits)+" warm_misses="+(string)(g_orbReplayMemoMisses-misses)
      +" epoch_changes="+(string)(g_probeEpochChanges-epochs);
   g_orbReplayMemo.Reset("FORCE_COLD");MaCrossAuditInvalidate();
   start=GetTickCount64();bool cold=Run(156);long coldMs=(long)(GetTickCount64()-start);string b=Identity();
   FileWriteString(f,"broad="+(broad?"true":"false")+" warm="+(warm?"true":"false")+" cold="+(cold?"true":"false")
      +" same="+(a==b?"true":"false")+" large_ms="+(string)large+" warm_ms="+(string)warmMs+" cold_ms="+(string)coldMs
      +" "+diagnostic+" trades="+(string)g_histTotal+" data="+(string)g_histInvalid
      +" ui_cleanup="+(clean?"true":"false")+"\n");FileClose(f);
}
