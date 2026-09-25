#property strict
#define LN_FORCE_ASYNC_AUDIT
#define OnInit AsyncInit
#define OnDeinit AsyncDeinit
#define OnTick AsyncTick
#define OnTimer AsyncTimer
#define OnChartEvent AsyncEvent
#define OnTradeTransaction AsyncTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

bool DrainAudit()
{
   for(int i=0;i<10000 && g_auditMacroPending;i++)
      ContinueHistoricalMacroAudit(g_auditGeneration);
   return !g_auditMacroPending;
}

void OnStart()
{
   if(AsyncInit()!=INIT_SUCCEEDED){Print("SOL_ADV_ASYNC init_failed");return;}
   bool initialPending=g_auditMacroPending;
   bool initialDone=DrainAudit();
   int initialTotal=g_hist.total;
   g_histWeeks=52;RecalculateHistoricalStats(false);
   bool pending=g_auditMacroPending;
   int canceledGeneration=g_auditGeneration;
   RefreshAfterConfigChange(false);
   bool canceled=!g_auditMacroPending && g_auditGeneration!=canceledGeneration;
   RecalculateHistoricalStats(false);
   bool completed=DrainAudit();
   int macroWins=0,macroLosses=0;
   for(int i=0;i<LIQ_MACRO_REGIME_COUNT;i++)
   {macroWins+=g_macroAuditWins[i];macroLosses+=g_macroAuditLosses[i];}
   Print("SOL_ADV_ASYNC initial_pending=",initialPending," initial_done=",initialDone,
      " initial_total=",initialTotal," one_year_pending=",pending," cancel_ok=",canceled,
      " completed=",completed," total=",g_hist.total," wins=",g_hist.wins,
      " losses=",g_hist.losses," open=",g_hist.open,
      " net_r=",DoubleToString(g_hist.netR,6)," macro_w=",macroWins," macro_l=",macroLosses);
   AsyncDeinit(0);
}
