#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTimer ProbeTimer
#define OnTick ProbeTick
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

void OnStart()
{
   int out=FileOpen("OrbPairedInvertProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"invert","signal_time","source_direction","status");
   for(int retry=0;retry<60&&!TerminalInfoInteger(TERMINAL_CONNECTED);retry++)Sleep(500);
   g_rtSignalTf=PERIOD_M5;g_rtTargetLeg=ORB_TARGET_R100;
   g_rtTargetMode=ORB_TARGET_R_LEG;g_rtExitMode=ORB_EXIT_FIXED_TARGET;
   g_rtEntryMode=ORB_ENTRY_BREAKOUT;g_rtPipSlMode=true;g_rtPipSlPips=4000;
   g_rtFilterAtr=false;g_rtFilterVol=false;g_rtFilterDay=false;
   g_rtDisplacement=false;g_rtFvgMode=ORB_FVG_OFF;
   g_rtNasConfirmation=false;g_rtNasStateGate=false;
   g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_rtTimeExit=false;g_rtFilteredWindowReverseExit=false;
   g_rtPostTradeDispBlockExit=false;g_mlEnabled=false;g_orbRfEnabled=false;
   g_btNativeParity=true;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;
   double entry=SymbolInfoDouble(_Symbol,SYMBOL_BID),point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   for(int direction=0;direction<2;direction++)
   {
      bool sourceBuy=direction==0;double rawSl=entry+(sourceBuy?-1:1)*1000*point;
      OrbPureSwapGeometry swap;string why="";
      bool ok=ResolvePureSwapGeometry(sourceBuy,!sourceBuy,entry,entry,rawSl,swap,why);
      if(!ok||MathAbs(swap.execSl-swap.sourceTp)>TickSize()
         ||MathAbs(swap.execTp-swap.sourceSl)>TickSize())
      {FileWrite(out,"ERROR","SWAP",direction,why);FileClose(out);return;}
   }
   for(int i=0;i<ORB_REGIME_COUNT;i++)g_regimeAllowed[i]=true;
   string detail="";bool hard=false;bool ready=false;
   for(int retry=0;retry<60;retry++)
   {
      if(EnsureOrbAuditHistoryCoverage(14,detail,hard)){ready=true;break;}
      Sleep(500);
   }
   if(!ready){FileWrite(out,"ERROR","HISTORY",detail);FileClose(out);return;}
   datetime now=TimeCurrent(),local=ServerToSessionLocal(now);
   MqlDateTime day;TimeToStruct(local,day);
   g_histRunNyMid=MakeDateTime(day.year,day.mon,day.day,0,0,0);
   g_histRunNow=now;g_histRunDays=14;
   g_histRunPoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   for(int invert=0;invert<2;invert++)
   {
      g_rtInvertMode=invert!=0;
      OrbResetHistoricalStats();BeginHistoricalSnapshot();InitializeHistoricalTickReplayCoverage();
      ArrayResize(g_histWindowSignals,0);ArrayResize(g_histAcceptedSignals,0);
      ArrayResize(g_histOperationalSignals,0);ArrayResize(g_regimeReferenceSignals,0);
      ArrayResize(g_regimeReferenceWindows,0);ArrayResize(g_histDaySnapshots,14);
      for(int i=13;i>=0;i--)ProcessHistoricalPrepDay(i);
      for(int i=13;i>=0;i--)
      {
         int before=g_histTotal;
         ProcessHistoricalCalcDay(i);
         if(g_histTotal>before)
            FileWrite(out,invert,(long)g_histDaySnapshots[i].operationalSignalTime,
               g_histDaySnapshots[i].operationalDirection,"accepted");
      }
      FileWrite(out,"SUMMARY",invert,g_histTotal,g_histInvalid);
      FileFlush(out);
   }
   FileClose(out);
}
