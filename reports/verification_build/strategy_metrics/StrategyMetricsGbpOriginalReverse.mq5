#define METRICS_STRATEGY_NAME "gbpusdFirst"
#define METRICS_OUTPUT "StrategyMetricsGbpOriginalReverse.csv"
#define METRICS_REVERSE_48H
#property strict
#ifndef METRICS_STRATEGY_NAME
#define METRICS_STRATEGY_NAME "0.20RStarJp225DailyNextDayOff"
#endif
#ifndef METRICS_OUTPUT
#define METRICS_OUTPUT "StrategyMetricsOrbLiveAudit.csv"
#endif
datetime g_metricsAuditClock=0;
datetime MetricsAuditNow(){return g_metricsAuditClock>0?g_metricsAuditClock:TimeCurrent();}
#define TimeCurrent MetricsAuditNow
#define OnInit MetricsInit
#define OnDeinit MetricsDeinit
#define OnTick MetricsTick
#define OnTimer MetricsTimer
#define OnChartEvent MetricsEvent
#define OnTradeTransaction MetricsTransaction
#include "../../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef TimeCurrent
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart()
{
   int out=FileOpen(METRICS_OUTPUT,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"name","symbol","weeks","total","wins","losses","open","flat","data","netR","minCum","savedExact","asOf","detail");
   for(int retry=0;retry<120&&!TerminalInfoInteger(TERMINAL_CONNECTED);retry++)Sleep(500);
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)||TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {FileWrite(out,"","",0,0,0,0,0,0,0,0,0,false,0,"CONNECTED_ALGO_OFF_REQUIRED");FileClose(out);return;}
   g_runtimeMagic=9192028000+(long)(GetTickCount64()%1000000);
   for(int day=0;day<7;day++)g_tcalDayHours[day]=16777215;
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   OrbUserReload(true);OrbStrategyPreset p;bool found=false;
   for(int i=0;i<OrbStrategyPresetCount();i++)
      if(OrbStrategyPresetLoad(i,p)&&p.name==METRICS_STRATEGY_NAME)
      {g_strategyPresetIndex=i;found=true;break;}
   if(!found||!OrbStrategyPresetApplyValues(p)||!OrbUserMatches(p))
   {FileWrite(out,p.name,_Symbol,0,0,0,0,0,0,0,0,0,false,0,"EXACT_SAVED_SETUP_APPLY_FAILED");FileClose(out);return;}
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_orbNativeWithBridgeOnly=false;g_auditRuntime=false;
   g_mlEnabled=false;g_swFrozen=false;g_histRedrawQueued=false;g_metricsAuditClock=TimeCurrent();
#ifdef METRICS_ADVANCED
   g_rtAdvancedAuditEngine=true;
#endif
#ifdef METRICS_REVERSE_48H
   g_orbPositions.reverse=true;g_orbPositions.waitMinutes=2880;
   g_strategyPresetIndex=-1; // Changed geometry/exit policy must not overwrite the original saved setup.
   int windows[]={20,52,104,260};
#else
   int windows[]={260,208,156,104,52,20,10,5,2};
#endif
   for(int w=0;w<ArraySize(windows)&&!IsStopped();w++)
   {
      SetHistoricalWeeks(windows[w]);g_histNeedsRedraw=true;g_lastHistBuild=0;DrawHistoricalSignals();
      ulong deadline=GetTickCount64()+300000,retryAt=0;
      while(GetTickCount64()<deadline&&!IsStopped())
      {
         ProcessHistoricalAuditStep();
         if(!g_histAuditRunning&&!g_histCoveragePending)break;
         if(g_histCoverageHardBlocked)break;
         if(g_histCoveragePending&&GetTickCount64()>retryAt)
         {g_histNeedsRedraw=true;DrawHistoricalSignals();retryAt=GetTickCount64()+5000;}
         Sleep(10);
      }
      int slot=OrbUserSlot(p.id);SwMetric m;
      bool ready=!g_histAuditRunning&&!g_histCoveragePending&&g_histInvalid==0&&slot>=0
         &&SwRead("OrbStrategyUserLibrary\\WindowMetrics",p.id,OrbUserWindowKey(g_userStrategies[slot]),windows[w],m);
      bool exact=ready&&m.total==g_histTotal&&m.wins==g_histWins&&m.losses==g_histLosses
         &&m.open==g_histOpen&&m.flat==g_histFlat&&MathAbs(m.netR-g_histNetR)<1e-9
         &&MathAbs(m.minCum-g_histMinCumulativeR)<1e-9&&m.asOf==g_histRunNow;
      string detail=g_histCoverageDetail;
      if(g_histModeledReverseExits>0)detail+="M1_MODEL="+(string)g_histModeledReverseExits+";NOT_TICK_EXACT";
      FileWrite(out,p.name,_Symbol,windows[w],g_histTotal,g_histWins,g_histLosses,g_histOpen,g_histFlat,g_histInvalid,
         DoubleToString(g_histNetR,12),DoubleToString(g_histMinCumulativeR,12),exact,(long)g_histRunNow,detail);
      if(g_histInvalid>0)
      {
      int shown=0;
      for(int i=0;i<ArraySize(g_axTrades)&&shown<3;i++)if(!g_axTrades[i].valid)
      {
         AxTrade t=g_axTrades[i];
         Print("REVERSE_DATA ",windows[w],"W signal=",TimeToString(t.signalTime)," available=",TimeToString(t.availableTime),
            " reason=",t.reason," context=",t.context," entry=",t.entry," sl=",t.sl," tp=",t.tp);shown++;
      }
      }
      FileFlush(out);Print("NAMED_AUDIT ",windows[w],"W ",g_histWins,"/",g_histLosses," exact_saved=",exact);
#ifndef METRICS_REVERSE_48H
      if(!exact)break;
#endif
   }
   FileClose(out);EventKillTimer();DeleteDash();DeleteHist();
}
