#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

void RunTickCase(int file,string name,bool reverse,bool clearCache)
{
   LnNasDefaults(g_lnNas);
   g_lnNas.reverseExit=reverse;
   LnNasInvalidate();
   if(clearCache)SimCacheClear();
   ulong start=GetTickCount64();
   g_histWeeks=20;
   RecalculateHistoricalStats(false);
   Print("TICK_STREAM_PERF ",name," ms=",GetTickCount64()-start,
      " total=",g_hist.total," W=",g_hist.wins," L=",g_hist.losses,
      " O=",g_hist.open," DATA=",g_hist.invalid," R=",DoubleToString(g_hist.netR,8));
   for(int i=0;i<ArraySize(g_histSignals);i++)
      FileWrite(file,name,g_histSignals[i].id,g_histSignalValid[i],g_histSignalClosed[i],
         g_histSignalWon[i],DoubleToString(g_histSignalR[i],8),g_histSignalExitTime[i],
         g_histSignalExitReason[i],g_histSignalInvalidReason[i],
         DoubleToString(g_histSignalExecEntry[i],8),DoubleToString(g_histSignalExecSl[i],8),
         DoubleToString(g_histSignalExecTp[i],8));
}
void OnStart()
{
   if(ProbeInit()!=INIT_SUCCEEDED)return;
   int file=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(file==INVALID_HANDLE)return;
   RunTickCase(file,"REVERSE_ON",true,true);
   RunTickCase(file,"REVERSE_OFF",false,true);
   RunTickCase(file,"OFF_REUSE",false,false);
   FileClose(file);
   ProbeDeinit(0);
}
