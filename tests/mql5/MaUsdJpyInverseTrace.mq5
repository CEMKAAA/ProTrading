#property strict
#define OnInit TraceInit
#define OnDeinit TraceDeinit
#define OnTimer TraceTimer
#define OnTick TraceTick
#define OnChartEvent TraceEvent
#define OnTradeTransaction TraceTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart()
{
   g_rtSignalTf=PERIOD_M5;g_rtMaCrossMode=MA_CROSS_ORIGINAL_MTF;
   g_rtTargetLeg=ORB_TARGET_R350;g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   g_rtSlDistancePct=100;g_rtPipSlMode=false;
   g_btNativeParity=true;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;
   g_btSpreadPts=0;g_btSlippagePts=0;g_btCommissionPerLot=0;
   g_rtAdvancedReverse=false;g_rtTimeExit=false;g_rtBEOnTp1=false;
   g_maReverseExit=false;g_maIndependent=false;
   datetime from=D'2026.09.24 18:00',through=D'2026.09.25 00:00';
   bool ready=false;
   for(int retry=0;retry<30;retry++)
   {
      if(MaCrossAuditBuild(_Symbol,PERIOD_M5,from,through,g_rtMaCrossMode,
         MA_CROSS_PAIR_FAST,InpMaFastLength,InpMaMediumLength,InpMaSlowLength))
      {ready=true;break;}
      Sleep(500);
   }
   if(!ready){Print("USD_TRACE history unavailable");return;}
   int f=FileOpen("MaUsdJpyInverseTrace.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(f==INVALID_HANDLE)return;
   FileWrite(f,"signal","raw","engine","inverse","first_tick","bid","ask","bar_close",
      "valid","entry","sl","tp","outcome","exit_time","exit_price","cost_r","net_r");
   InitializeHistoricalTickReplayCoverage();
   for(int i=0;i<ArraySize(g_maCrossAuditEvents);i++)
   {
      MaCrossAuditEvent e=g_maCrossAuditEvents[i];
      g_orbHigh=e.high;g_orbLow=e.low;g_orbStartServer=e.signalTime;
      g_orbEndServer=e.signalTime;g_tradeEndServer=e.signalTime+86400;
      MqlTick quote;ZeroMemory(quote);
      OrbAdvFindFirstQuote((long)(e.signalTime+300)*1000,(long)TimeCurrent()*1000,quote);
      for(int engine=0;engine<2;engine++)for(int inverse=0;inverse<2;inverse++)
      {
         g_rtAdvancedAuditEngine=engine!=0;g_rtInvertMode=inverse!=0;
         bool sourceBuy=e.direction>0,isBuy=inverse!=0?!sourceBuy:sourceBuy;
         double buffer=InpSlBufferPoints*_Point;
         double rawSl=sourceBuy?e.low-buffer:e.high+buffer;
         double sl=0,risk=0;string detail="";
         if(!ResolveExecutionStop(sourceBuy,isBuy,e.close,rawSl,sl,risk,detail))continue;
         datetime used=g_tradeEndServer;
         HistResult r=SimulateHistoricalLifecycleAdvanced(e.signalTime,g_tradeEndServer,TimeCurrent(),
            e.close,sl,isBuy,PriceAtLeg(isBuy,e.close,risk,1),PriceAtLeg(isBuy,e.close,risk,2),
            PriceAtLeg(isBuy,e.close,risk,3),0,used);
         FileWrite(f,TimeToString(e.signalTime,TIME_DATE|TIME_MINUTES),e.direction,
            engine,inverse,TimeToString((datetime)quote.time,TIME_DATE|TIME_SECONDS),
            DoubleToString(quote.bid,3),DoubleToString(quote.ask,3),DoubleToString(e.close,3),r.valid,
            DoubleToString(r.simEntry,3),DoubleToString(r.simSl,3),DoubleToString(r.simTarget,3),
            r.outcome,TimeToString(r.exitTime,TIME_DATE|TIME_SECONDS),DoubleToString(r.exitPrice,3),
            DoubleToString(r.costR,6),DoubleToString(r.netR,6));
      }
   }
   FileClose(f);
   MqlTick ticks[];
   int count=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,
      (ulong)D'2026.09.24 21:00'*1000,(ulong)D'2026.09.24 21:16'*1000);
   int quotes=FileOpen("MaUsdJpyInverseQuotes.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   FileWrite(quotes,"time","time_msc","bid","ask","spread","event");
   bool normalSl=false,inverseTp=false,inverseSl=false;
   double widest=0;int widestAt=-1;
   for(int i=0;i<count;i++)
   {
      if(ticks[i].bid<=0||ticks[i].ask<=0)continue;
      string event="";
      if(!normalSl&&ticks[i].bid<=158.819){normalSl=true;event+="NORMAL_SL;";}
      if(!inverseTp&&ticks[i].ask<=158.819){inverseTp=true;event+="INVERSE_TP;";}
      if(!inverseSl&&ticks[i].ask>=159.098){inverseSl=true;event+="INVERSE_SL;";}
      if(ticks[i].ask-ticks[i].bid>widest){widest=ticks[i].ask-ticks[i].bid;widestAt=i;}
      if(event!="")FileWrite(quotes,TimeToString((datetime)ticks[i].time,TIME_DATE|TIME_SECONDS),
         ticks[i].time_msc,DoubleToString(ticks[i].bid,3),DoubleToString(ticks[i].ask,3),
         DoubleToString(ticks[i].ask-ticks[i].bid,3),event);
   }
   if(widestAt>=0)FileWrite(quotes,TimeToString((datetime)ticks[widestAt].time,TIME_DATE|TIME_SECONDS),
      ticks[widestAt].time_msc,DoubleToString(ticks[widestAt].bid,3),DoubleToString(ticks[widestAt].ask,3),
      DoubleToString(widest,3),"MAX_SPREAD_IN_INTERVAL");
   FileClose(quotes);
   Print("USD_TRACE complete events=",ArraySize(g_maCrossAuditEvents));
}
