#define CAPACITY_PROBE_ANCHOR D'2026.10.01 16:01:53'
#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
datetime CapacityProbeNow(){return CAPACITY_PROBE_ANCHOR;}
#define TimeCurrent CapacityProbeNow
#include "MaCrossOverOrbEA.mq5"
int checks=0,failed=0;
void Check(bool ok,string name){checks++;if(!ok){failed++;Print("CAPACITY_FAIL ",name);}}
#ifndef CAPACITY_BASELINE
#define MA_CAPACITY_NO_LAB
#include "MaOpenCapacityChecks.mqh"
#endif
string CapacityIdentity()
{
   string text=(string)g_histTotal+"|"+(string)g_histWins+"|"+(string)g_histLosses+"|"+(string)g_histOpen+"|"+AuditMemoPrice(g_histNetR);
   for(int i=0;i<ArraySize(g_axTrades);i++)
   {
      AxTrade item=g_axTrades[i];text+="|"+(string)item.signalTime+"|"+(string)item.entryTime+"|"+(string)item.exitTime
         +"|"+(string)item.direction+"|"+item.outcome+"|"+AuditMemoPrice(item.entry)+"|"+AuditMemoPrice(item.sl)
         +"|"+AuditMemoPrice(item.tp)+"|"+AuditMemoPrice(item.exitPrice)+"|"+AuditMemoPrice(item.netR);
   }
   return OrbMlSha256(text);
}
bool RunAudit(int weeks)
{
   for(int attempt=0;attempt<5;attempt++)
   {
      g_rtHistoricalWeeks=weeks;g_histNeedsRedraw=true;g_lastHistBuild=0;DrawHistoricalSignals();ulong start=GetTickCount64();
      while(g_histAuditRunning&&!IsStopped()&&GetTickCount64()-start<180000)ProcessHistoricalAuditStep();
      EventKillTimer();if(!g_histAuditRunning&&!g_histCoveragePending&&g_histTotal>0&&g_histInvalid==0)return true;
      MqlRates warm[];ENUM_TIMEFRAMES tf[]={PERIOD_M1,PERIOD_M5,PERIOD_H1,PERIOD_H2,PERIOD_H4,PERIOD_D1};
      for(int i=0;i<ArraySize(tf);i++)CopyRates(_Symbol,tf[i],1,10000,warm);Sleep(3000);
   }
   return false;
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_auditRuntime=false;g_axNotify=false;g_axSchedule=false;
   g_rtSignalTf=PERIOD_M5;g_rtMaCrossMode=MA_CROSS_PIVOT_ST;g_rtMaCrossPair=MA_CROSS_PAIR_FAST;
   g_rtNasConfirmation=false;g_rtNasStateGate=false;g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_rtFilterAtr=false;g_rtFilterVol=false;g_rtFilterDay=false;g_rtEntryWindow=false;g_mcOf.mode=0;
   g_rtInvertMode=false;g_rtAdvancedReverse=false;g_rtDisplacement=false;g_rtFvgMode=ORB_FVG_OFF;
   g_rtTimeExit=false;g_rtBEOnTp1=false;g_rtHalfBeLeg=0;g_rtFilteredWindowReverseExit=false;g_rtPostTradeDispBlockExit=false;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtTargetMode=ORB_TARGET_R_LEG;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   g_rtPipSlMode=true;g_rtPipSlPips=30;g_rtCustomR=1;g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;
   g_orbRfEnabled=false;for(int i=0;i<6;i++)g_regimeAllowed[i]=true;
   TCalStrategyApplyText(TCalStrategyOffText());g_dailyMaxLosses=0;g_dailyTargetWins=0;
   g_maIndependent=false;g_maMaxConsecutive=1;g_maReverseExit=true;g_maReverseWait=0;g_rtAdvancedAuditEngine=true;
   Check(RunAudit(5),"legacy 5W exact tick baseline");string legacy=CapacityIdentity();int legacyTrades=g_histTotal;
#ifndef CAPACITY_BASELINE
   CheckOpenCapacity();g_maIndependent=true;g_maMaxConsecutive=10;g_maReverseExit=false;g_rtPipSlPips=8000;
   Check(RunAudit(5),"MaCross 5W MAX10 audit");CheckCapacityAuditIntervals("MACROSS 5W MAX10");
   Check(g_histOpen==10&&g_histTotal==10,"MaCross mixed signals saturate total ten open positions");
   int open10=g_histOpen;g_maMaxConsecutive=3;Check(RunAudit(5),"MaCross MAX3 audit");CheckCapacityAuditIntervals("MACROSS 5W MAX3");
   Check(g_histOpen==3&&g_histTotal==3,"MaCross lower limit recalculates occupancy");int open3=g_histOpen;
   g_maReverseExit=true;Check(RunAudit(2),"MaCross reverse closures recycle slots");CheckCapacityAuditIntervals("MACROSS 2W RECYCLE");
   Check(g_histTotal>3&&g_histWins+g_histLosses>0,"MaCross closes release capacity");
   string warm=CapacityIdentity();g_orbReplayMemo.Reset("CAPACITY_COLD");MaCrossAuditInvalidate();DeleteHist();
   Check(RunAudit(2)&&warm==CapacityIdentity(),"MaCross capacity warm/cold parity");
   MaRenderOpenCounter(true);ChartRedraw();ChartScreenShot(0,"MaCrossOpenCounter.png",1600,900);
#endif
   int report=FileOpen("MaCapacity_after_2f40798bf3.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(report!=INVALID_HANDLE)
   {
      string text="checks="+(string)checks+" failed="+(string)failed+" legacy_hash="+legacy+" legacy_trades="+(string)legacyTrades;
#ifndef CAPACITY_BASELINE
      text+=" max10_open="+(string)open10+" max3_open="+(string)open3;
#endif
      FileWriteString(report,text+"\n");FileClose(report);
   }
   EventKillTimer();
}
