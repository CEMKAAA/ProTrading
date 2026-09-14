#property strict
#define OnInit NasProbeOriginalInit
#define OnDeinit NasProbeOriginalDeinit
#define OnTick NasProbeOriginalTick
#define OnTimer NasProbeOriginalTimer
#define OnChartEvent NasProbeOriginalEvent
#define OnTradeTransaction NasProbeOriginalTransaction
#include "NasUltimate_StrategyLibrary.mq5"
void Quote(MqlRates &q,datetime at,double open,double high,double low,int spread=1)
{
   ZeroMemory(q);q.time=at;q.open=open;q.high=high;q.low=low;q.close=open;q.spread=spread;
}
int ReplayCases()
{
   int failures=0;datetime exitAt;double exitPx,gross,mfe,mae;string reason,quality;
   NasResearchTrade t;ZeroMemory(t);t.entryAt=600;t.entry=100;t.sl=90;t.tp=105;t.direction=1;t.entryValid=true;
   MqlRates q[];ArrayResize(q,2);Quote(q[0],600,100,102,99);Quote(q[1],660,102,106,101);
   if(!NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="TP"||MathAbs(gross-.5)>1e-12||mfe<.5)failures++;
   Quote(q[1],660,98,99,89);
   if(!NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="SL"||gross!=-1||mae!=-1)failures++;
   Quote(q[1],660,88,90,87);
   if(!NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="SL_GAP"||MathAbs(gross+1.2)>1e-12)failures++;
   Quote(q[1],660,100,106,89);
   if(NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||quality!="AMBIGUOUS_M1")failures++;
   t.deadline=660;t.closeDirection=-1;Quote(q[1],660,99,106,98);
   if(!NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="REVERSE"||MathAbs(gross+.1)>1e-12||exitAt!=660)failures++;
   t.closeDirection=0;Quote(q[1],660,101,106,98);
   if(!NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="TIME_EXIT"||MathAbs(gross-.1)>1e-12)failures++;
   t.closeDirection=1;
   if(!NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="REPLACE")failures++;
   t.deadline=0;t.direction=-1;t.sl=110;t.tp=95;
   Quote(q[0],600,100,102,99);Quote(q[1],660,98,100,94.95);
   if(NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="OPEN")failures++;
   Quote(q[1],660,98,100,94.8);
   if(!NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||reason!="TP"||gross!=.5)failures++;
   Quote(q[1],720,98,100,94.8);
   if(NasResearchReplay(t,q,840,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||quality!="M1_GAP")failures++;
   Quote(q[1],660,98,100,94.8,0);
   if(NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||quality!="SPREAD_UNKNOWN")failures++;
   t.entryValid=false;
   if(NasResearchReplay(t,q,780,.1,exitAt,exitPx,gross,reason,quality,mfe,mae)||quality!="ENTRY_UNRESOLVED")failures++;
   return failures;
}
int MemoCases()
{
   AuditMemoIndex memo;int failed=0;memo.Reset("epoch-a");
   for(int i=0;i<20000;i++)if(memo.Add("trade:"+(string)i)!=i)failed++;
   for(int i=19999;i>=0;i--)if(memo.Find("trade:"+(string)i)!=i)failed++;
   if(memo.Find("not-present")!=-1||memo.Add("trade:7")!=7)failed++;
   memo.Reset("epoch-a");if(memo.Find("trade:7")!=7)failed++;
   memo.Reset("epoch-b");if(memo.Find("trade:7")!=-1||memo.Add("new")!=0)failed++;
   if(AuditMemoPrice(1.234567890123456)==AuditMemoPrice(1.234567890123457))failed++;
   return failed;
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   int replayFailed=ReplayCases(),memoFailed=MemoCases(),failed=replayFailed+memoFailed,parsed=0;
   g_eaEnabledRuntime=false;g_nasBridgeEnabledRuntime=false;
   g_tradeStartTimeRuntime=InpTradeStartTime;g_tradeEndTimeRuntime=InpTradeEndTime;
   g_totalLotRuntime=InpTotalLot;g_fixedLotRuntime=InpFixedLot;
   g_accountRiskPerTradePctRuntime=InpAccountRiskPerTradePct;
   LiqMacroRegimeInit();NasLibraryInit();
   for(int i=0;i<ArraySize(g_nasLibrary);i++)
   {
      string a[];double n[];
      if(!NasLibraryParseSettings(g_nasLibrary[i].settings,a,n))failed++;else parsed++;
   }
   string bad[];double numbers[];
   if(NasLibraryParseSettings("garbage",bad,numbers))failed++;
   if(NasLibrarySafeToken("../OrbML"))failed++;
   if(!NasLibraryTime("24:00")||NasLibraryTime("24:01")||NasLibraryTime("xx:00"))failed++;
   int before=ArraySize(g_nasLibrary);
   NasLibraryAddBuiltin("probe_only","No order probe",NasLibrarySymbol(_Symbol),PeriodSeconds(_Period)/60,
      "10:00","17:00",80000,.35,75,true,true,.9);
   g_nasLibrary[before].user=true;g_nasLibrary[before].profile=NasLibraryInputProfile();
   double risk=g_accountRiskPerTradePctRuntime;
   if(!NasLibraryApply(before))failed++;
   if(g_pipSlDistanceRuntime!=80000||MathAbs(g_selectedTargetRRuntime-.35)>1e-10||g_volumeMultiplierRuntime!=.9
      ||g_eaEnabledRuntime||g_nasBridgeEnabledRuntime||risk!=g_accountRiskPerTradePctRuntime)failed++;
   string config=NasLibraryConfig();g_volumeMultiplierRuntime=2;
   if(config==NasLibraryConfig())failed++;
   g_volumeMultiplierRuntime=.9;
   if(config!=NasLibraryConfig())failed++;
   NasLibraryParseSettings(g_nasLibrary[before].settings,bad,numbers);
   string canonical=NasLibrarySettings(),fields[];double values[];
   if(!NasLibraryParseSettings(canonical,fields,values))failed++;
   g_nasBridgeEnabledRuntime=true;
   if(NasLibraryApply(before))failed++;
   g_nasBridgeEnabledRuntime=false;
   string coverage="";
   string symbols[]={"BTCUSDm","US500m","USTECm","USDJPYm","JP225m"};
   for(int s=0;s<ArraySize(symbols);s++)
   {
      bool selected=SymbolSelect(symbols[s],true);
      MqlRates rates[];int n=selected?CopyRates(symbols[s],PERIOD_M5,TimeCurrent()-260*7*86400,TimeCurrent(),rates):0;
      datetime first=n>0?rates[0].time:0;
      coverage+=(s>0?",":"")+"{\"symbol\":\""+symbols[s]+"\",\"selected\":"+(selected?"true":"false")
         +",\"bars\":"+(string)n+",\"first\":"+(string)(long)first+"}";
   }
   string result="{\"failed\":"+(string)failed+",\"replay_cases\":12,\"replay_failed\":"+(string)replayFailed+",\"memo_failed\":"+(string)memoFailed+",\"presets_parsed\":"+(string)parsed+",\"coverage\":["+coverage+"]}";
   FolderCreate("NasLibraryProbe");
   int h=FileOpen("NasLibraryProbe\\result.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(h!=INVALID_HANDLE){FileWriteString(h,result);FileClose(h);}
   Print("NAS_LIBRARY_PROBE ",result);ObjectsDeleteAll(0,NAS_LIB_PREFIX);ObjectsDeleteAll(0,PREFIX);EventKillTimer();
}
