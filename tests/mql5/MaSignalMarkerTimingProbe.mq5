#property strict
#define OnInit MarkerUnusedInit
#define OnDeinit MarkerUnusedDeinit
#define OnTimer MarkerUnusedTimer
#define OnTick MarkerUnusedTick
#define OnChartEvent MarkerUnusedChartEvent
#define OnTradeTransaction MarkerUnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

int markerChecks=0,markerFailed=0;
void MarkerCheck(bool ok,string label,int report)
{
   markerChecks++;
   if(!ok){markerFailed++;FileWriteString(report,"FAIL "+label+"\n");}
}

void OnStart()
{
   for(int i=0;i<60&&!TerminalInfoInteger(TERMINAL_CONNECTED);i++)Sleep(500);
   int report=FileOpen("MaSignalMarkerTimingProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(report==INVALID_HANDLE)return;
   g_rtSignalTf=PERIOD_M15;
   MqlRates bars[];
   for(int tfIndex=0;tfIndex<2;tfIndex++)
   {
      ENUM_TIMEFRAMES tf=tfIndex==0?PERIOD_M15:PERIOD_M1;
      int count=CopyRates(_Symbol,tf,D'2026.09.17 11:45',D'2026.09.17 12:30',bars);
      for(int i=0;i<count;i++)
         FileWriteString(report,StringFormat("BAR tf=%d time=%s O=%.3f H=%.3f L=%.3f C=%.3f\n",
            (int)tf,TimeToString(bars[i].time,TIME_DATE|TIME_MINUTES),bars[i].open,bars[i].high,bars[i].low,bars[i].close));
   }
   MqlTick ticks[];
   int count=CopyTicks(_Symbol,ticks,COPY_TICKS_INFO,(ulong)D'2026.09.17 12:30'*1000,1);
   if(count>0)FileWriteString(report,StringFormat("FILL time=%s bid=%.3f ask=%.3f error=%d\n",
      TimeToString((datetime)ticks[0].time,TIME_DATE|TIME_SECONDS),ticks[0].bid,ticks[0].ask,GetLastError()));
   bool built=false;
   for(int retry=0;retry<10&&!built;retry++)
   {
      built=MaCrossAuditBuild(_Symbol,PERIOD_M15,D'2026.09.17 00:00',D'2026.09.18 00:00',
         MA_CROSS_TRENDER_IQ,MA_CROSS_PAIR_FAST,InpMaFastLength,InpMaMediumLength,InpMaSlowLength);
      if(!built)Sleep(500);
   }
   FileWriteString(report,"BUILD="+(built?"OK":g_maCrossAuditFailure)+"\n");
   for(int i=0;i<ArraySize(g_maCrossAuditEvents);i++)
   {
      MaCrossAuditEvent event=g_maCrossAuditEvents[i];
      FileWriteString(report,StringFormat("EVENT time=%s dir=%d close=%.3f high=%.3f low=%.3f old_arrow=%.3f available=%s\n",
         TimeToString(event.signalTime,TIME_DATE|TIME_MINUTES),event.direction,event.close,event.high,event.low,
         MaCrossCandleArrowPrice(event.direction>0,event.high,event.low),
         TimeToString(BarCloseTime(PERIOD_M15,event.signalTime),TIME_DATE|TIME_MINUTES)));
   }
   g_rtEntryMode=ORB_ENTRY_BREAKOUT;g_rtExitMode=ORB_EXIT_FIXED_TARGET;
   g_rtTargetMode=ORB_TARGET_R_LEG;g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;g_rtCustomR=0.01;
   g_rtPipSlMode=true;g_rtPipSlPips=800.0;g_rtAdvancedReverseMaxCostPct=100.0;
   BeginHistoricalSnapshot();
   for(int mode=0;mode<4;mode++)
   {
      g_rtAdvancedAuditEngine=(mode>=2);g_rtInvertMode=(mode%2==1);
      HistResult sim=SimulateTrade(D'2026.09.17 12:15',D'2026.09.17 13:00',155.341,163.341,
         g_rtInvertMode,0,0,0,0,false);
      FileWriteString(report,StringFormat("SIM mode=%d valid=%d outcome=%s entry=%.3f sl=%.3f tp=%.3f R=%.8f exit=%s price=%.3f\n",
         mode,(int)sim.valid,sim.outcome,sim.simEntry,sim.simSl,sim.simTarget,sim.netR,
         TimeToString(sim.exitTime,TIME_DATE|TIME_SECONDS),sim.exitPrice));
      MarkerCheck(sim.entryTime==D'2026.09.17 12:30',"fill time mode="+(string)mode,report);
      datetime markerBar=0;double markerPrice=0,pad=0;
      MaCrossTradeMarker(sim.entryTime,g_rtInvertMode,sim.simEntry,markerBar,markerPrice,pad);
      MarkerCheck(markerBar==D'2026.09.17 12:30',"M1 fill candle mode="+(string)mode,report);
      MarkerCheck(g_rtInvertMode?markerPrice<155.343:markerPrice>155.432,
         "marker outside fill candle mode="+(string)mode,report);
      MarkerCheck(g_rtInvertMode?155.343-markerPrice<0.025:markerPrice-155.432<0.025,
         "marker padding follows M1 candle mode="+(string)mode,report);
      DrawOrbExecutionVisual(g_rtInvertMode?"BUY":"SELL",sim.entryTime,D'2026.09.17 12:15',
         sim.simEntry,sim.simSl,"marker probe");
      string arrow=OrbExecutionVisualBase(sim.entryTime,g_rtInvertMode?1:-1)+"ARW";
      MarkerCheck((datetime)ObjectGetInteger(0,arrow,OBJPROP_TIME)==markerBar,
         "execution object time mode="+(string)mode,report);
      MarkerCheck(MathAbs(ObjectGetDouble(0,arrow,OBJPROP_PRICE)-markerPrice)<_Point*0.5,
         "execution object price mode="+(string)mode,report);
      FileWriteString(report,StringFormat("MARKER mode=%d fill=%s candle=%s price=%.3f pad=%.3f\n",
         mode,TimeToString(sim.entryTime,TIME_DATE|TIME_SECONDS),TimeToString(markerBar,TIME_DATE|TIME_MINUTES),markerPrice,pad));
   }
   g_rtMaCrossMode=MA_CROSS_TRENDER_IQ;g_rtInvertMode=false;g_rtAdvancedAuditEngine=false;
   g_histRunNow=D'2026.09.17 13:00';g_histRunDays=1;g_histRunPoint=_Point;
   g_rtFilterVol=false;g_rtDisplacement=false;g_rtFvgMode=ORB_FVG_OFF;
   g_rtFilterDay=false;g_rtNasConfirmation=false;g_rtNasStateGate=false;
   for(int bucket=0;bucket<ORB_REGIME_COUNT;bucket++)g_regimeAllowed[bucket]=true;
   g_maIndependent=false;g_maReverseExit=false;g_maAuditPositionUntil=0;
   OrbResetHistoricalStats();
   ArrayResize(g_histDaySnapshots,ArraySize(g_maCrossAuditEvents));
   for(int i=0;i<ArraySize(g_maCrossAuditEvents);i++)ProcessMaHistoricalPrepEvent(i);
   for(int i=0;i<ArraySize(g_maCrossAuditEvents);i++)
   {
      datetime signal=g_maCrossAuditEvents[i].signalTime;
      if(signal!=D'2026.09.17 12:15')continue;
      ProcessHistoricalCalcDay(i);
      string arrow=MaHistoryEventBase(signal,"SELL")+"ARW";
      MarkerCheck(ObjectFind(0,arrow)>=0,"historical arrow exists",report);
      MarkerCheck((datetime)ObjectGetInteger(0,arrow,OBJPROP_TIME)==D'2026.09.17 12:30',
         "historical arrow uses actual fill candle",report);
      MarkerCheck(MathAbs(ObjectGetDouble(0,arrow,OBJPROP_PRICE)-155.450)<_Point*0.5,
         "historical arrow uses displayed M1 high",report);
      string entryLine=HistoricalObjectRoot()+"LVL_"+(string)(long)signal+"_SELL_ENTRY";
      MarkerCheck((datetime)ObjectGetInteger(0,entryLine,OBJPROP_TIME)==D'2026.09.17 12:30',
         "entry line starts at fill time",report);
   }
   FileWriteString(report,StringFormat("CHECKS=%d FAILED=%d\n",markerChecks,markerFailed));
   FileClose(report);
}
