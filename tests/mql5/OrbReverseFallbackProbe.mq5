#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("REVERSE FALLBACK FAIL: ",label);}}
void OnStart()
{
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   g_rtSignalTf=PERIOD_M5;g_rtAdvancedAuditEngine=false;g_rtInvertMode=false;
   g_rtPipSlMode=false;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btNativeParity=true;
   g_histTickCoverageKnown=true;g_histTickFirstAvailableMs=ULONG_MAX;
   g_rtTargetLeg=ORB_TARGET_CUSTOM;g_rtTargetMode=ORB_TARGET_R_LEG;g_rtExitMode=ORB_EXIT_FIXED_TARGET;
   g_rtTimeExit=false;g_orbPositions.reverse=false;
   MqlRates bars[];
   int count=CopyRates(_Symbol,PERIOD_M5,D'2025.10.20 08:00',D'2025.10.20 12:00',bars);
   Check(count>=3,"recorded bars available");
   if(count>=3)
   {
      int chosen=-1;
      for(int i=1;i<count;i++)if(bars[i].high-bars[i].open>10*_Point){chosen=i;break;}
      Check(chosen>=1,"positive excursion for deterministic TP");
      if(chosen>=1)
      {
         int i=chosen;datetime at=bars[i-1].time,end=bars[i].time+300;
         double entry=bars[i].open,risk=4*(bars[i].high-bars[i].low);
         double stop=entry-risk;g_rtCustomR=(bars[i].high-entry)*0.5/risk;
         HistResult plain=SimulateTrade(at,end,entry,stop,true,0,0,0,0);
         g_orbPositions.reverse=true;
         HistResult distant=SimulateTrade(at,end,entry,stop,true,0,0,0,0,true,at+2880*60,"NEW_DAY_REVERSE_EXIT");
         Check(plain.valid&&plain.outcome==TargetOutcomeLabel(g_rtTargetLeg),"existing bar-policy target closes before deadline");
         Check(distant.valid&&distant.outcome==plain.outcome&&distant.exitTime==plain.exitTime
            &&distant.netR==plain.netR,"48H deadline preserves earlier bar-policy TP verdict, time and net R");
         g_rtCustomR=100;
         HistResult unresolved=SimulateTrade(at,end,entry,stop,true,0,0,0,0,true,bars[i].time+30,"NEW_DAY_REVERSE_EXIT");
         Check(!unresolved.valid&&unresolved.invalidReason=="REVERSE_TICKS_REQUIRED"&&unresolved.netR==0,
            "deadline inside an M1 bar stays uncertain without ticks");
         unresolved=SimulateTrade(at,end,entry,stop,true,0,0,0,0,true,bars[i].time,"NEW_DAY_REVERSE_EXIT");
         Check(unresolved.valid&&unresolved.modeledReverseExit&&unresolved.exitTime==bars[i].time,
            "minute-aligned exit is explicitly a bar-open model");
         int minutes=0;Check(OrbPositionWaitRead("48:00",minutes)&&minutes==2880,"HH:MM preserves 48 hours");
         g_rtInvertMode=true;
         unresolved=SimulateTrade(at,end,entry,stop,true,0,0,0,0,true,bars[i].time,"NEW_DAY_REVERSE_EXIT");
         Check(!unresolved.valid&&unresolved.invalidReason=="INVERSE_TICKS_REQUIRED","inverse keeps its strict quote requirement");
         g_rtInvertMode=false;
      }
   }
   MqlRates friday[],reopening[];
   datetime fridaySignal=D'2025.10.24 08:00',deadline=fridaySignal+300+2880*60,through=D'2025.10.27 08:00';
   int fridayCount=CopyRates(_Symbol,PERIOD_M5,fridaySignal,fridaySignal+300,friday);
   int nextCount=CopyRates(_Symbol,PERIOD_M1,deadline,through,reopening);
   Check(fridayCount>=2&&nextCount>0,"weekend recorded history available");
   if(fridayCount>=2&&nextCount>0)
   {
      double entry=friday[1].open,risk=0.5;g_rtCustomR=100;
      HistResult buy=SimulateTrade(fridaySignal,through,entry,entry-risk,true,0,0,0,0,true,deadline,"NEW_DAY_REVERSE_EXIT");
      Check(reopening[0].time>deadline,"48H calendar deadline falls in market closure");
      Check(buy.valid&&buy.modeledReverseExit&&buy.outcome=="NEW_DAY_REVERSE_EXIT"
         &&buy.exitTime==reopening[0].time&&buy.exitPrice==NormalizeTradePrice(reopening[0].open),
         "weekend exit uses first available M1 open after deadline, never Friday's close");
      ArrayResize(g_orbPositionReservations,0);OrbPositionReserve(1,buy.valid,buy.exitTime);
      Check(OrbPositionAuditCap(deadline)==1,"slot remains occupied during closed market");
      Check(OrbPositionAuditCap(buy.exitTime)==0,"slot releases at modeled reopening exit");
      HistResult sell=SimulateTrade(fridaySignal,through,entry,entry+risk,false,0,0,0,0,true,deadline,"NEW_DAY_REVERSE_EXIT");
      double ask=NormalizeTradePrice(reopening[0].open+MathMax(0.0,(double)reopening[0].spread)*_Point);
      Check(sell.valid&&sell.modeledReverseExit&&sell.exitPrice==ask,"SELL reopening uses recorded ask-spread model");
      double expected=SimSignedR(false,entry,ask,risk)-BtCostRForSpread(risk,0);
      Check(MathAbs(sell.netR-expected)<1e-9,"SELL market-exit spread is not double charged");
      g_rtAdvancedAuditEngine=true;datetime usedEnd=0;
      HistResult advanced=SimulateHistoricalLifecycleAdvanced(fridaySignal,through,through,entry,entry-risk,true,
         0,0,0,0,usedEnd,deadline,"NEW_DAY_REVERSE_EXIT");
      Check(advanced.valid&&advanced.modeledReverseExit&&advanced.outcome==buy.outcome
         &&advanced.exitTime==buy.exitTime&&advanced.exitPrice==buy.exitPrice&&advanced.netR==buy.netR,
         "ADV unavailable-tick fallback matches normal BUY weekend exit");
      advanced=SimulateHistoricalLifecycleAdvanced(fridaySignal,through,through,entry,entry+risk,false,
         0,0,0,0,usedEnd,deadline,"NEW_DAY_REVERSE_EXIT");
      Check(advanced.valid&&advanced.modeledReverseExit&&advanced.outcome==sell.outcome
         &&advanced.exitTime==sell.exitTime&&advanced.exitPrice==sell.exitPrice&&advanced.netR==sell.netR,
         "ADV unavailable-tick fallback matches normal SELL weekend exit");
   }
   int f=FileOpen("OrbReverseFallbackProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
