#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

void ConfigureProbe()
{
   g_rtSignalTf=PERIOD_M1;g_rtMaCrossMode=(MA_CROSS_SIGNAL_MODE)3;
   g_rtTargetLeg=ORB_TARGET_R100;g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   g_rtPipSlMode=true;g_rtPipSlPips=StringFind(_Symbol,"XAU")>=0?300:10;
   g_rtFilterAtr=false;g_rtFilterVol=false;g_rtFilterDay=false;
   g_rtDisplacement=false;g_rtFvgMode=ORB_FVG_OFF;
   g_rtNasConfirmation=false;g_rtNasStateGate=false;
   g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_rtTimeExit=false;g_rtFilteredWindowReverseExit=false;
   g_rtPostTradeDispBlockExit=false;g_maReverseExit=false;
   g_maIndependent=false;g_rtInvertMode=false;
   g_btNativeParity=true;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;
   g_btSlippagePts=0;g_btSpreadPts=0;g_btCommissionPerLot=0;
   g_mcOf.mode=MC_OF_OFF;g_orbRfEnabled=false;g_mlEnabled=false;
   g_rtAdvancedAuditEngine=true;g_tcalEnabled=false;
   for(int i=0;i<ORB_REGIME_COUNT;i++)g_regimeAllowed[i]=true;
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   ConfigureProbe();
   int f=FileOpen("AuditPerf_baseline_b35e4eab.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   int trades=FileOpen("AuditPerf_baseline_b35e4eab.trace",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE||trades==INVALID_HANDLE)return;
   datetime until=iTime(_Symbol,PERIOD_M1,1)+60;
   datetime from=until-140*86400;
   bool ready=false;
   ulong begin=GetTickCount64();
   for(int retry=0;retry<30;retry++)
   {
      if(MaCrossAuditBuild(_Symbol,g_rtSignalTf,from,until,g_rtMaCrossMode,g_rtMaCrossPair,
         InpMaFastLength,InpMaMediumLength,InpMaSlowLength)){ready=true;break;}
      Sleep(500);
   }
   FileWriteString(f,"signal_ms="+(string)(GetTickCount64()-begin)+" ready="+(string)ready+"\n");FileFlush(f);
   if(!ready){FileClose(f);FileClose(trades);return;}
   for(int run=0;run<2;run++)
   {
      begin=GetTickCount64();
      g_histRunNow=until;g_histRunDays=140;g_histRunPoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      g_maAuditPositionUntil=0;g_maHistSeriesDir=0;g_maHistSeriesCount=0;
      OrbResetHistoricalStats();BeginHistoricalSnapshot();InitializeHistoricalTickReplayCoverage();
      OrbAdvancedAuditResetRunStats();
      g_histFiltered=0;g_histInvalid=0;
      ArrayResize(g_histAcceptedSignals,0);ArrayResize(g_histOperationalSignals,0);
      ArrayResize(g_histWindowSignals,0);ArrayResize(g_regimeReferenceSignals,0);
      ArrayResize(g_regimeReferenceWindows,0);
      int count=ArraySize(g_maCrossAuditEvents);ArrayResize(g_histDaySnapshots,count);
      for(int i=0;i<count;i++)ProcessMaHistoricalPrepEvent(i);
      ulong prep=GetTickCount64()-begin;
      for(int i=0;i<count;i++)
      {
         if(IsStopped())break;
         ProcessHistoricalCalcDay(i);
      }
      FileWriteString(f,StringFormat("run=%d total_ms=%I64u prep_ms=%I64u signals=%d total=%d W=%d L=%d O=%d DATA=%d R=%.12f disk=%I64d cold=%I64d exact_ticks=%I64d\n",
         run,GetTickCount64()-begin,prep,count,g_histTotal,g_histWins,g_histLosses,g_histOpen,g_histInvalid,g_histNetR,
         g_orbAdvIndexDiskHits,g_orbAdvIndexColdBuilds,g_orbAdvExactTicks));FileFlush(f);
      for(int i=0;i<ArraySize(g_axTrades);i++)
      {
         AxTrade t=g_axTrades[i];
         FileWriteString(trades,StringFormat("%d|%I64d|%I64d|%I64d|%d|%d|%d|%d|%.17g|%.17g|%.17g|%.17g|%.17g|%s|%s\n",
            run,(long)t.signalTime,(long)t.entryTime,(long)t.exitTime,t.direction,(int)t.valid,(int)t.closed,(int)t.won,
            t.entry,t.sl,t.tp,t.exitPrice,t.netR,t.outcome,t.reason));
      }
   }
   FileClose(f);FileClose(trades);EventKillTimer();
}
