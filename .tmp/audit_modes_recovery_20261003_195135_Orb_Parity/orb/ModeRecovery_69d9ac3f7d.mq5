#define RECOVERY_ORB
#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

int checks=0,failed=0,paired=0,normalW=0,normalL=0,normalO=0,advancedW=0,advancedL=0,advancedO=0;
int halfCases=0,inverseCases=0,forcedCases=0;
double normalR=0,advancedR=0;
string failures="";
void Check(bool ok,string why)
{
   checks++;
   if(!ok){failed++;if(failed<12){Print("MODE_PARITY_FAIL ",why);failures+=why+"\n";}}
}
HistResult EmptyResult(double entry,double sl,int half)
{
   HistResult r;ZeroMemory(r);r.outcome="open";r.invalidReason="NO_MARKET_DATA";
   r.simEntry=entry;r.simSl=sl;r.entrySpreadPoints=EMPTY_VALUE;
   r.targetLeg=RuntimeTargetLeg();r.hcLeg=ClampHalfBeLeg(half,r.targetLeg);
   r.exitMode=RuntimeExitLabel();return r;
}
bool ExactResult(const HistResult &a,const HistResult &b)
{
   return a.maxTp==b.maxTp&&a.outcome==b.outcome&&a.netR==b.netR&&a.isWin==b.isWin
      &&a.entrySpreadPoints==b.entrySpreadPoints&&a.simEntry==b.simEntry&&a.entryTime==b.entryTime
      &&a.simSl==b.simSl&&a.simTarget==b.simTarget&&a.costR==b.costR
      &&a.targetLeg==b.targetLeg&&a.hcLeg==b.hcLeg&&a.exitMode==b.exitMode
      &&a.exitPrice==b.exitPrice&&a.exitTime==b.exitTime&&a.valid==b.valid
      &&a.invalidReason==b.invalidReason;
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   g_rtSignalTf=PERIOD_M5;g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   g_rtPipSlMode=true;g_rtTimeExit=false;
#ifdef RECOVERY_ORB
   g_rtInverseMaxGapPct=100;
#else
   g_rtAdvancedReverse=false;g_rtAdvancedReverseMaxCostPct=100;
#endif
   g_btNativeParity=true;g_btFillMode=BT_FILL_NEXT_BAR_OPEN;
   g_btSpreadPts=0;g_histTickResumeAllowed=false;g_histAuditRunning=true;
   g_histRunNow=D'2026.10.02 20:00';
   MqlRates bars[];ArraySetAsSeries(bars,false);
   int n=CopyRates(_Symbol,g_rtSignalTf,D'2026.09.28 10:00',D'2026.10.01 15:00',bars);
   Check(n>200,"market bar fixtures available");
   int targets[]={ORB_TARGET_R050,ORB_TARGET_R100,ORB_TARGET_R350};
   if(n>200)for(int i=0;i<4;i++)
   {
      datetime at=bars[i*(n-1)/4].time+PeriodSeconds(g_rtSignalTf);
      MqlTick warm[];bool ready=false;
      for(int retry=0;retry<20;retry++)
      {
         ResetLastError();int count=CopyTicksRange(_Symbol,warm,COPY_TICKS_INFO,(ulong)at*1000,(ulong)(at+3600)*1000);
         if(count>0&&GetLastError()==0){ready=true;break;}
         Sleep(500);
      }
      Check(ready,"fixture quote history synchronized sample="+(string)i);
   }
   if(n>200)for(int q=0;q<96;q++)
   {
      MqlRates bar=bars[(q%4)*(n-1)/4];
      bool buy=(q%2)==0;g_rtInvertMode=(q/2)%2!=0;
      g_rtTargetLeg=targets[(q/4)%3];
      double scale=StringFind(_Symbol,"XAU")>=0?30:(StringFind(_Symbol,"BTC")>=0?1000:1);
      g_rtPipSlPips=scale*((q/12)%2==0?10:25);
      g_btSlippagePts=(q/24)%2;g_btCommissionPerLot=(q/48)%2;
      int half=(q%5==0&&LegR(RuntimeTargetLeg())>1.0)?ORB_TARGET_R100:0;
      datetime end=bar.time+3600,forced=q%3==0?bar.time+1200:0;
      if(half>0)halfCases++;if(g_rtInvertMode)inverseCases++;if(forced>0)forcedCases++;
      double entry=bar.close,sl=buy?bar.low-OrbPipSize()*g_rtPipSlPips:bar.high+OrbPipSize()*g_rtPipSlPips;
      HistResult a=EmptyResult(entry,sl,half),b=a;
      ClearHistoricalTickResume();ClearHistoricalTickReplayCache();
      g_rtAdvancedAuditEngine=false;
      bool na=SimulateTradeTicks(bar.time,end,entry,sl,buy,half,true,a,forced,"NAS_REVERSE_EXIT");
      ClearHistoricalTickReplayCache();g_rtAdvancedAuditEngine=true;
      bool nb=SimulateTradeTicksAdvanced(bar.time,end,entry,sl,buy,half,true,b,forced,"NAS_REVERSE_EXIT");
      Check(na&&nb&&a.valid&&b.valid,"both exact tick engines available case="+(string)q
         +" normal="+(string)na+"/"+a.invalidReason+" adv="+(string)nb+"/"+b.invalidReason);
      if(!na||!nb||!a.valid||!b.valid)continue;
      paired++;Check(ExactResult(a,b),"all result fields case="+(string)q+" normal="+a.outcome+" adv="+b.outcome);
      normalR+=a.netR;advancedR+=b.netR;
      if(a.outcome=="open")normalO++;else if(a.isWin)normalW++;else normalL++;
      if(b.outcome=="open")advancedO++;else if(b.isWin)advancedW++;else advancedL++;
   }
   Check(paired==96,"all cases compared without DATA/OHLC fallback");
   Check(halfCases>0&&inverseCases>0&&forcedCases>0,"HC, inversion and forced exits actually exercised");
   Check(normalW==advancedW&&normalL==advancedL&&normalO==advancedO&&normalR==advancedR,"W/L/O and net R parity");
   int f=FileOpen("ModeRecovery_69d9ac3f7d.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE)
   {
      FileWriteString(f,StringFormat("checks=%d failed=%d paired=%d normal=%dW/%dL/%dO advanced=%dW/%dL/%dO normal_R=%.17g advanced_R=%.17g\n",
         checks,failed,paired,normalW,normalL,normalO,advancedW,advancedL,advancedO,normalR,advancedR)+failures);
      FileWriteString(f,"HC_cases="+(string)halfCases+" inverse_cases="+(string)inverseCases+" forced_cases="+(string)forcedCases+"\n");
      FileClose(f);
   }
   g_histAuditRunning=false;EventKillTimer();
}
