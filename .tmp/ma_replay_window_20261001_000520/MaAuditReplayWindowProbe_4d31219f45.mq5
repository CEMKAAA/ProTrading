#define MA_OFFLINE_HISTORY_FIXTURE
#property strict
datetime g_probeNow=D'2026.09.30 19:00';
datetime ProbeClock(){return g_probeNow;}
datetime ProbeClock(MqlDateTime &dt){TimeToStruct(g_probeNow,dt);return g_probeNow;}
#ifdef MA_OFFLINE_HISTORY_FIXTURE
// Test-only frozen local-history fixture. No price, fill or outcome override.
// Broker connectivity is not a completeness flag for a recorded offline dataset.
struct ProbeLocalSeries{ENUM_TIMEFRAMES tf;long first,last,bars;};
ProbeLocalSeries g_probeLocalSeries[];
bool g_probeLocalReady=false;
long ProbeSeriesInfo(const string symbol,const ENUM_TIMEFRAMES tf,const ENUM_SERIES_INFO_INTEGER property)
{
   long value=SeriesInfoInteger(symbol,tf,property);
   if(property!=SERIES_SYNCHRONIZED||value||!g_probeLocalReady||symbol!=_Symbol)return value;
   for(int i=0;i<ArraySize(g_probeLocalSeries);i++)
      if(g_probeLocalSeries[i].tf==tf
         &&g_probeLocalSeries[i].first==SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE)
         &&g_probeLocalSeries[i].last==SeriesInfoInteger(symbol,tf,SERIES_LASTBAR_DATE)
         &&g_probeLocalSeries[i].bars==SeriesInfoInteger(symbol,tf,SERIES_BARS_COUNT))return 1;
   return value;
}
bool FreezeLocalHistory()
{
   ENUM_TIMEFRAMES tfs[]={PERIOD_M1,PERIOD_M5,PERIOD_H1,PERIOD_H2,PERIOD_H4,PERIOD_D1};
   ArrayResize(g_probeLocalSeries,ArraySize(tfs));MqlRates rates[];ArraySetAsSeries(rates,false);
   for(int i=0;i<ArraySize(tfs);i++)
   {
      long first=SeriesInfoInteger(_Symbol,tfs[i],SERIES_FIRSTDATE);
      long last=SeriesInfoInteger(_Symbol,tfs[i],SERIES_LASTBAR_DATE);
      long bars=SeriesInfoInteger(_Symbol,tfs[i],SERIES_BARS_COUNT);
      int count=CopyRates(_Symbol,tfs[i],(datetime)first,(datetime)last,rates);
      if(count<1||count!=bars||rates[0].time!=first||rates[count-1].time!=last)return false;
      g_probeLocalSeries[i].tf=tfs[i];g_probeLocalSeries[i].first=first;
      g_probeLocalSeries[i].last=last;g_probeLocalSeries[i].bars=bars;
   }
   g_probeLocalReady=true;return true;
}
#define SeriesInfoInteger ProbeSeriesInfo
#endif
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
void SortRows(string &rows[],int lo,int hi)
{
   int i=lo,j=hi;string pivot=rows[lo+(hi-lo)/2];
   while(i<=j)
   {
      while(StringCompare(rows[i],pivot)<0)i++;
      while(StringCompare(rows[j],pivot)>0)j--;
      if(i<=j){string temp=rows[i];rows[i++]=rows[j];rows[j--]=temp;}
   }
   if(lo<j)SortRows(rows,lo,j);if(i<hi)SortRows(rows,i,hi);
}
string VisualIdentity()
{
   string rows[];
   for(int i=0;i<ArraySize(g_maVisuals);i++)
   {
      if(!g_maVisuals[i].visible)continue;
      string row="";
      for(int j=0;j<g_maVisuals[i].count;j++)
      {
         string n=g_maVisuals[i].names[j];
         if(ObjectFind(0,n)<0)return "MISSING:"+n;
         int type=(int)ObjectGetInteger(0,n,OBJPROP_TYPE);
         if(ObjectGetInteger(0,n,OBJPROP_TIMEFRAMES)==OBJ_NO_PERIODS)return "HIDDEN:"+n;
         row+=(string)type+"|"+(string)ObjectGetInteger(0,n,OBJPROP_TIME,0)
            +"|"+AuditMemoPrice(ObjectGetDouble(0,n,OBJPROP_PRICE,0))+"|"+(string)ObjectGetInteger(0,n,OBJPROP_COLOR);
         if(type==OBJ_TREND)row+="|"+(string)ObjectGetInteger(0,n,OBJPROP_TIME,1)+"|"+AuditMemoPrice(ObjectGetDouble(0,n,OBJPROP_PRICE,1));
         if(type==OBJ_TEXT)row+="|"+ObjectGetString(0,n,OBJPROP_TEXT);
         if(type==OBJ_ARROW)row+="|"+(string)ObjectGetInteger(0,n,OBJPROP_ARROWCODE)+"|"+(string)ObjectGetInteger(0,n,OBJPROP_ANCHOR);
         row+="\n";
      }
      int k=ArraySize(rows);ArrayResize(rows,k+1,1024);rows[k]=row;
   }
   if(ArraySize(rows)<1)return "EMPTY";
   SortRows(rows,0,ArraySize(rows)-1);string all="";
   for(int i=0;i<ArraySize(rows);i++)all+=rows[i]+"\n";
   return OrbMlSha256(all);
}
bool VisualCacheUnit()
{
   MaVisualBeginAudit(PREFIX+"HIST_POOL_");bool reused=false;
   int slot=MaVisualBeginPlot("UNIT_A",reused);
   string arrow=g_maPlotRoot+"MA_TEST_ARW";
   ObjectCreate(0,arrow,OBJ_ARROW,0,D'2026.09.30',150);
   ObjectCreate(0,g_maPlotRoot+"MA_TEST_TXT",OBJ_TEXT,0,D'2026.09.30',150);
   ObjectCreate(0,g_maPlotRoot+"MA_TEST_LVLTXT",OBJ_TEXT,0,D'2026.09.30',150);
   MaVisualEndPlot(slot,"MA_TEST_","",false,false,false);
   bool ok=!reused&&ObjectGetInteger(0,arrow,OBJPROP_TIMEFRAMES)==OBJ_NO_PERIODS;
   MaVisualCommit();ok=ok&&ObjectGetInteger(0,arrow,OBJPROP_TIMEFRAMES)==OBJ_ALL_PERIODS;
   MaVisualBeginAudit(PREFIX+"HIST_POOL_");MaVisualBeginPlot("UNIT_A",reused);MaVisualAbort();
   ok=ok&&reused&&ObjectGetInteger(0,arrow,OBJPROP_TIMEFRAMES)==OBJ_ALL_PERIODS;
   MaVisualBeginAudit(PREFIX+"HIST_POOL_");MaVisualCommit();
   ok=ok&&ObjectGetInteger(0,arrow,OBJPROP_TIMEFRAMES)==OBJ_NO_PERIODS;
   MaVisualBeginAudit(PREFIX+"HIST_POOL_");MaVisualBeginPlot("UNIT_A",reused);MaVisualCommit();
   ok=ok&&reused&&ObjectGetInteger(0,arrow,OBJPROP_TIMEFRAMES)==OBJ_ALL_PERIODS;
   ObjectDelete(0,arrow);MaVisualBeginAudit(PREFIX+"HIST_POOL_");MaVisualBeginPlot("UNIT_A",reused);
   ok=ok&&!reused;MaVisualAbort();
   DeleteHist();return ok;
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
   clean=clean&&VisualCacheUnit();
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
   ulong waiting=GetTickCount64();MqlRates warmup[];
#ifdef MA_OFFLINE_HISTORY_FIXTURE
   if(!FreezeLocalHistory()){Print("LOCAL_FIXTURE_INCOMPLETE");return;}
#endif
   while(!IsStopped()&&GetTickCount64()-waiting<60000)
   {
      CopyRates(_Symbol,PERIOD_M5,0,1000,warmup);CopyRates(_Symbol,PERIOD_M1,0,1000,warmup);
      CopyRates(_Symbol,PERIOD_H4,0,1000,warmup);
      if(SeriesInfoInteger(_Symbol,PERIOD_M5,SERIES_SYNCHRONIZED)
         &&SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED)
         &&SeriesInfoInteger(_Symbol,PERIOD_H4,SERIES_SYNCHRONIZED))break;
      Sleep(100);
   }
   g_probeNow=iTime(_Symbol,PERIOD_M5,0)+2;
   int f=FileOpen("MaAuditReplayWindowProbe_4d31219f45.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE)return;
   ulong start=GetTickCount64();bool broad=Run(260);long large=(long)(GetTickCount64()-start);
   long hits=g_orbReplayMemoHits,misses=g_orbReplayMemoMisses,epochs=g_probeEpochChanges;
   start=GetTickCount64();bool warm=Run(156);long warmMs=(long)(GetTickCount64()-start);string a=Identity();
   long visualHits=g_maVisualHits,visualMisses=g_maVisualMisses;string va=VisualIdentity();
   string diagnostic="warm_hits="+(string)(g_orbReplayMemoHits-hits)+" warm_misses="+(string)(g_orbReplayMemoMisses-misses)
      +" epoch_changes="+(string)(g_probeEpochChanges-epochs);
   g_orbReplayMemo.Reset("FORCE_COLD");MaCrossAuditInvalidate();
   DeleteByPrefix(PREFIX+"HIST_POOL_");MaVisualReset();
   start=GetTickCount64();bool cold=Run(156);long coldMs=(long)(GetTickCount64()-start);string b=Identity();
   string vb=VisualIdentity();
   FileWriteString(f,"broad="+(broad?"true":"false")+" warm="+(warm?"true":"false")+" cold="+(cold?"true":"false")
      +" same="+(a==b?"true":"false")+" large_ms="+(string)large+" warm_ms="+(string)warmMs+" cold_ms="+(string)coldMs
      +" "+diagnostic+" trades="+(string)g_histTotal+" data="+(string)g_histInvalid
      +" ui_cleanup="+(clean?"true":"false")+" visual_same="+(va==vb&&StringLen(va)==64?"true":"false")
      +" visual_hits="+(string)visualHits+" visual_misses="+(string)visualMisses
#ifdef MA_OFFLINE_HISTORY_FIXTURE
      +" history_source=OFFLINE_LOCAL_FIXED"
#else
      +" history_source=BROKER_SYNCHRONIZED"
#endif
      +"\n");FileClose(f);
}
