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
            &&distant.netR==plain.netR,"48H deadline does not invalidate earlier TP");
         g_rtCustomR=100;
         HistResult unresolved=SimulateTrade(at,end,entry,stop,true,0,0,0,0,true,bars[i].time+60,"NEW_DAY_REVERSE_EXIT");
         Check(!unresolved.valid&&unresolved.invalidReason=="REVERSE_TICKS_REQUIRED"&&unresolved.netR==0,
            "deadline inside bar never fabricates exact exit PnL");
         unresolved=SimulateTrade(at,end,entry,stop,true,0,0,0,0,true,bars[i].time,"NEW_DAY_REVERSE_EXIT");
         Check(!unresolved.valid&&unresolved.invalidReason=="REVERSE_TICKS_REQUIRED",
            "deadline at bar open still requires quote");
         int minutes=0;Check(OrbPositionWaitRead("48:00",minutes)&&minutes==2880,"HH:MM preserves 48 hours");
      }
   }
   int f=FileOpen("OrbReverseFallbackProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
