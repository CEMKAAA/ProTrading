#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart()
{
   int init=ProbeInit();
   string rows="";
   for(int i=0;i<ArraySize(g_histSignals);i++)
      rows+=g_histSignals[i].id+"|"+(string)g_histSignals[i].dir+"|"
         +(string)g_histSignals[i].availableTime+"|"+DoubleToString(g_histSignalR[i],8)+"|"
         +(string)g_histSignalClosed[i]+"|"+(string)g_histSignalValid[i]+"\n";
   string payload="{\"init\":"+(string)init+",\"total\":"+(string)g_hist.total
      +",\"wins\":"+(string)g_hist.wins+",\"losses\":"+(string)g_hist.losses
      +",\"open\":"+(string)g_hist.open+",\"invalid\":"+(string)g_hist.invalid
      +",\"netR\":"+DoubleToString(g_hist.netR,8)
      +",\"signalHash\":\""+LiqLibraryHash(rows)+"\"}";
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,payload);FileClose(f);}
   ProbeDeinit(0);
}
