#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   // No production OnInit, runtime files, broker orders or publishers are called.
   g_htf=PERIOD_H2;g_entryTf=PERIOD_H1;g_swingLookback=5;
   g_target=ERL_RR_TP4;g_hc=ERL_HC_OFF;g_targetModel=ERL_TARGET_FIXED_R;
   g_entryModel=ERL_ENTRY_LEGACY_HTF_FVG_TAP;g_stopModel=ERL_STOP_FIRST_FVG_CANDLE;
   g_useAsiaLiquidityTarget=true;g_allowDuplicateEntries=true;
   g_pipSlMode=true;g_pipSlPips=StringFind(_Symbol,"XAU")>=0?1500:100;
   g_slDistancePct=100;g_slBufferAtrPct=10;
   g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btSameBarPolicy=BT_SAMEBAR_CONSERVATIVE;
   g_btSpreadPts=0;g_btSlippagePts=0;g_btCommissionPerLot=0;
   g_tcalEnabled=false;g_solRegimeFilterEnabled=false;
   for(int i=0;i<LIQ_MACRO_REGIME_COUNT;i++)g_macroRegimeAllowed[i]=true;
   LnNasDefaults(g_lnNas);g_lnNas.reverseExit=false;
   g_histWeeks=20;
   int f=FileOpen("AuditPerf_optimized_439eb026.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   int trace=FileOpen("AuditPerf_optimized_439eb026.trace",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE||trace==INVALID_HANDLE)return;
   for(int run=0;run<3;run++)
   {
      if(run==2){g_target=ERL_RR_TP2;SimCacheClear();}
      ulong start=GetTickCount64();
      RecalculateHistoricalStats(false);
      FileWriteString(f,StringFormat("run=%d total_ms=%I64u signals=%d total=%d W=%d L=%d O=%d DATA=%d R=%.12f\n",
         run,GetTickCount64()-start,ArraySize(g_histSignals),g_hist.total,g_hist.wins,g_hist.losses,g_hist.open,g_hist.invalid,g_hist.netR));FileFlush(f);
      for(int i=0;i<ArraySize(g_histSignals);i++)
         FileWriteString(trace,StringFormat("%d|%s|%I64d|%I64d|%I64d|%d|%d|%d|%d|%.17g|%.17g|%.17g|%.17g|%s|%s\n",
            run,g_histSignals[i].id,(long)g_histSignals[i].availableTime,(long)g_histSignalEntryTime[i],(long)g_histSignalExitTime[i],
            g_histSignalExecDir[i],(int)g_histSignalValid[i],(int)g_histSignalClosed[i],(int)g_histSignalWon[i],
            g_histSignalExecEntry[i],g_histSignalExecSl[i],g_histSignalExecTp[i],g_histSignalR[i],g_histSignalExitReason[i],g_histSignalInvalidReason[i]));
   }
   FileClose(f);FileClose(trace);EventKillTimer();
}
