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
   string output="init="+(string)init+"\n";
   if(init==INIT_SUCCEEDED)
   {
      LnNasDefaults(g_lnNas);
      g_lnNas.gate=1;
      g_lnNas.exitMode=0;
      g_lnNas.stateMultiplier=2.0;
      g_lnNas.entryAgeMinutes=120;
      g_histWeeks=2;
      LnNasInvalidate();
      RecalculateHistoricalStats(true);
      output+="total="+(string)g_hist.total+" wins="+(string)g_hist.wins
         +" losses="+(string)g_hist.losses+" open="+(string)g_hist.open
         +" netR="+DoubleToString(g_hist.netR,4)+" invalid="+(string)g_hist.invalid
         +" rejected="+(string)ArraySize(g_lnNasRejected)+" delayed="+(string)ArraySize(g_lnNasDelayed)+"\n";
      for(int i=0;i<ArraySize(g_histSignals);i++)
         output+=(string)i+"|"+TimeToString(g_histSignals[i].availableTime,TIME_DATE|TIME_MINUTES)
            +"|"+g_histSignals[i].id+"|"+g_histSignalInvalidReason[i]
            +"|delayed="+(LnNasDelayed(g_histSignals[i].id)?"1":"0")
            +"|exit="+g_histSignalExitReason[i]
            +"|R="+DoubleToString(g_histSignalR[i],4)+"\n";
   }
   int f=FileOpen("LiqSolAdvancedDe30NasProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,output);FileClose(f);}
   Print("DE30_NAS_PROBE ",output);
   ProbeDeinit(0);
}
