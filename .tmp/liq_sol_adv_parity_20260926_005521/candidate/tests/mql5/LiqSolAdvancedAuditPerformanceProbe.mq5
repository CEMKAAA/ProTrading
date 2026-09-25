#property strict
#define OnInit PerfInit
#define OnDeinit PerfDeinit
#define OnTick PerfTick
#define OnTimer PerfTimer
#define OnChartEvent PerfEvent
#define OnTradeTransaction PerfTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

void PrintAuditState(string label, ulong elapsed)
{
   int macroWins=0,macroLosses=0;
   for(int i=0;i<LIQ_MACRO_REGIME_COUNT;i++)
   {
#ifdef LN_SOL_ADV_MACRO_AUDIT_ACTIVE
      macroWins+=g_macroAuditWins[i];
      macroLosses+=g_macroAuditLosses[i];
#else
      macroWins+=g_macroRegimeWins[i];
      macroLosses+=g_macroRegimeLosses[i];
#endif
   }
   Print("SOL_ADV_PERF ",label," elapsed_ms=",elapsed," total=",g_hist.total,
      " wins=",g_hist.wins," losses=",g_hist.losses," open=",g_hist.open,
      " net_r=",DoubleToString(g_hist.netR,6)," macro_w=",macroWins,
      " macro_l=",macroLosses," cache=",ArraySize(g_simCache));
}

void OnStart()
{
   if(PerfInit()!=INIT_SUCCEEDED){Print("SOL_ADV_PERF init_failed");return;}
   ulong started=GetTickCount64();
   g_histWeeks=52;RecalculateHistoricalStats(false);
   PrintAuditState("1Y_COLD",GetTickCount64()-started);
   started=GetTickCount64();
   g_histWeeks=20;RecalculateHistoricalStats(false);
   PrintAuditState("20W_REUSE",GetTickCount64()-started);
   started=GetTickCount64();
   g_histWeeks=52;RecalculateHistoricalStats(false);
   PrintAuditState("1Y_REUSE",GetTickCount64()-started);
   PerfDeinit(0);
}
