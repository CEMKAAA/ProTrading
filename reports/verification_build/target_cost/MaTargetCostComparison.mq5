#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
datetime ProbeNow(){return (datetime)1791915416;}
#define TimeCurrent ProbeNow
#include "C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem/IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef TimeCurrent
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart()
{
   int f=FileOpen("MaTargetCostComparison.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);if(f==INVALID_HANDLE)return;
   for(int i=0;i<80&&!TerminalInfoInteger(TERMINAL_CONNECTED);i++)Sleep(250);
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)){FileWriteString(f,"ALGO_OFF_REQUIRED");FileClose(f);return;}
   g_runtimeMagic=9192028999;for(int d=0;d<7;d++)g_tcalDayHours[d]=16777215;
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   OrbUserReload(true);OrbStrategyPreset p;bool found=false;
   for(int i=0;i<OrbStrategyPresetCount();i++)if(OrbStrategyPresetLoad(i,p)&&p.name=="usdjpyM50.01Model")
   {g_strategyPresetIndex=i;found=true;break;}
   if(!found||!OrbStrategyPresetApplyValues(p)||!OrbUserMatches(p)){FileWriteString(f,"SAVED_APPLY_FAILED "+g_lastExecStatus);FileClose(f);return;}
   g_strategyPresetIndex=-1; // Research only: never overwrite saved CURRENT results.
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_orbNativeWithBridgeOnly=false;g_auditRuntime=false;g_mlEnabled=false;
   g_swFrozen=false;g_histRedrawQueued=false;g_rtAdvancedAuditEngine=true;
   for(int pass=0;pass<2;pass++){TpCostSet(pass==1,20);
   SetHistoricalWeeks(260);g_histNeedsRedraw=true;g_lastHistBuild=0;DrawHistoricalSignals();
   ulong until=GetTickCount64()+180000;
   while(GetTickCount64()<until&&!IsStopped())
   {
      ProcessHistoricalAuditStep();
      if(!g_histAuditRunning&&!g_histCoveragePending)break;
      if(g_histCoverageHardBlocked)break;
      Sleep(10);
   }
   string out="filter="+(g_tpCostEnabled?"ON20":"OFF")+" blocked="+(string)g_tpCostRejected+" name="+p.name+" total="+(string)g_histTotal+" W="+(string)g_histWins+" L="+(string)g_histLosses
      +" O="+(string)g_histOpen+" DATA="+(string)g_histInvalid+" net="+DoubleToString(g_histNetR,12)
      +" W_R="+DoubleToString(g_histWonR,12)+" L_R="+DoubleToString(g_histLostR,12)
      +" reverse="+(string)g_maReverseExit+" nas="+(string)RuntimeNasExitEnabled()+" hc="+(string)RuntimeHalfBeLeg()
      +" spread="+DoubleToString(g_btSpreadPts,3)+" pip="+DoubleToString(g_rtPipSlPips,3)+"\n";
   int tpW=0,tpL=0,sl=0,other=0;double gross=0,cost=0;string examples="";
   for(int i=0;i<ArraySize(g_axTrades);i++)
   {
      AxTrade t=g_axTrades[i];if(!t.valid||!t.closed)continue;
      bool isTp=StringFind(t.outcome,"TP")==0||t.outcome=="TARGET";
      if(isTp){if(t.netR>1e-8)tpW++;else if(t.netR<-1e-8)tpL++;}
      else if(t.outcome=="SL")sl++;else other++;
      gross+=t.netR+t.costR;cost+=t.costR;
      if(isTp&&t.netR<0&&tpL<=4)examples+="TP_NET_LOSS entry="+TimeToString(t.entryTime,TIME_DATE|TIME_SECONDS)
         +" outcome="+t.outcome+" gross="+DoubleToString(t.netR+t.costR,12)+" cost="+DoubleToString(t.costR,12)
         +" net="+DoubleToString(t.netR,12)+" risk_price="+DoubleToString(MathAbs(t.entry-t.sl),8)
         +" spread_basis="+t.spreadBasis+"\n";
   }
   out+="TP_W="+(string)tpW+" TP_NET_L="+(string)tpL+" SL="+(string)sl+" OTHER="+(string)other
      +" GROSS="+DoubleToString(gross,12)+" COST="+DoubleToString(cost,12)+"\n"+examples;
   FileWriteString(f,out);Print(out);
   }FileClose(f);
}