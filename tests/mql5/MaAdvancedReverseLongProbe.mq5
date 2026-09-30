#define OnInit MaPairedUnusedInit
#define OnDeinit MaPairedUnusedDeinit
#define OnTimer MaPairedUnusedTimer
#define OnTick MaPairedUnusedTick
#define OnChartEvent MaPairedUnusedChartEvent
#define OnTradeTransaction MaPairedUnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

void OnStart()
{
   int out=FileOpen("MaAdvancedReverseLongProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"invert","signal_time","source_direction","status","net_r");
   for(int retry=0;retry<60&&!TerminalInfoInteger(TERMINAL_CONNECTED);retry++)Sleep(500);
   datetime until=TimeCurrent(),from=until-35*86400;
   g_rtSignalTf=PERIOD_M1;g_rtMaCrossMode=MA_CROSS_TRENDLINE;
   g_rtTargetLeg=ORB_TARGET_R100;g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   g_rtPipSlMode=true;g_rtPipSlPips=300;
   g_rtFilterAtr=false;g_rtFilterVol=false;g_rtFilterDay=false;
   g_rtDisplacement=false;g_rtFvgMode=ORB_FVG_OFF;
   g_rtNasConfirmation=false;g_rtNasStateGate=false;
   g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_rtTimeExit=false;g_rtFilteredWindowReverseExit=false;
   g_rtPostTradeDispBlockExit=false;g_maReverseExit=false;g_maIndependent=false;
   g_btNativeParity=true;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;
   g_mcOf.mode=MC_OF_OFF;g_orbRfEnabled=false;g_mlEnabled=false;
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID),point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   for(int direction=0;direction<2;direction++)
   {
      bool sourceBuy=direction==0;double rawSl=price+(sourceBuy?-1:1)*1000*point;
      OrbPureSwapGeometry swap;string why="";
      bool ok=ResolvePureSwapGeometry(sourceBuy,!sourceBuy,price,price,rawSl,swap,why);
      if(!ok||MathAbs(swap.execRisk-swap.sourceRisk)>TickSize()
         ||MathAbs(swap.execTargetR-swap.sourceTargetR)>0.001)
      {FileWrite(out,"ERROR","SWAP",direction,why);FileClose(out);return;}
   }
   for(int i=0;i<ORB_REGIME_COUNT;i++)g_regimeAllowed[i]=true;
   string detail="";bool hard=false;
   for(int retry=0;retry<30;retry++)
      if(EnsureOrbAuditHistoryCoverage(35,detail,hard))break;
      else Sleep(500);
   bool ready=false;
   for(int retry=0;retry<60;retry++)
   {
      if(MaCrossAuditBuild(_Symbol,g_rtSignalTf,from,until,g_rtMaCrossMode,g_rtMaCrossPair,
         InpMaFastLength,InpMaMediumLength,InpMaSlowLength)){ready=true;break;}
      Sleep(500);
   }
   if(!ready){FileWrite(out,"ERROR","MA_HISTORY",detail);FileClose(out);return;}
   for(int invert=0;invert<2;invert++)
   {
      g_rtInvertMode=(invert!=0);g_rtAdvancedReverse=(invert!=0);
      g_histRunNow=until;g_histRunDays=35;g_histRunPoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      g_maAuditPositionUntil=0;g_maHistSeriesDir=0;g_maHistSeriesCount=0;
      OrbResetHistoricalStats();BeginHistoricalSnapshot();InitializeHistoricalTickReplayCoverage();
      ArrayResize(g_histAcceptedSignals,0);ArrayResize(g_histOperationalSignals,0);
      ArrayResize(g_histWindowSignals,0);ArrayResize(g_regimeReferenceSignals,0);
      ArrayResize(g_regimeReferenceWindows,0);
      int count=ArraySize(g_maCrossAuditEvents);ArrayResize(g_histDaySnapshots,count);
      for(int i=0;i<count;i++)ProcessMaHistoricalPrepEvent(i);
      for(int i=0;i<count;i++)
      {
         if(IsStopped())break;
         int before=g_histTotal;
         int beforeWins=g_histWins,beforeLosses=g_histLosses;
         double beforeNetR=g_histNetR;
         ProcessHistoricalCalcDay(i);
         if(g_histTotal>before)
            FileWrite(out,invert,(long)g_maCrossAuditEvents[i].signalTime,
               g_maCrossAuditEvents[i].direction,
               g_histWins>beforeWins?"W":(g_histLosses>beforeLosses?"L":"DATA"),
               g_histNetR-beforeNetR);
      }
      FileWrite(out,"SUMMARY",invert,count,g_histTotal,g_histWins,g_histLosses,g_histNetR);
      FileFlush(out);
   }
   FileClose(out);
}

