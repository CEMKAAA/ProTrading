#property strict
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("FAIL ",label);}}
datetime mockServer=D'2019.09.13 01:32:00',mockLoaded=D'2021.09.19 21:00:00';
datetime mockOrigin=D'2019.09.13 01:30:00';
bool mockSync=true,mockDownload=false;int mockBars=100000;
long MockSeries(const string symbol,ENUM_TIMEFRAMES tf,ENUM_SERIES_INFO_INTEGER property)
{
 if(property==SERIES_TERMINAL_FIRSTDATE)return (long)mockServer;
 if(property==SERIES_SERVER_FIRSTDATE)return (long)mockServer;
 if(property==SERIES_FIRSTDATE)return (long)mockLoaded;
 if(property==SERIES_BARS_COUNT)return mockBars;
 if(property==SERIES_SYNCHRONIZED)return mockSync?1:0;
 return 0;
}
int MockCopyTime(const string symbol,ENUM_TIMEFRAMES tf,datetime from,int count,datetime &times[])
{if(mockDownload)mockLoaded=D'2019.09.13 01:30:00';return -1;}
int MockCopyTime(const string symbol,ENUM_TIMEFRAMES tf,datetime from,datetime until,datetime &times[])
{ArrayResize(times,1);times[0]=mockOrigin;return 1;}
long MockTerminal(ENUM_TERMINAL_INFO_INTEGER property){return 3000000;}
#define SeriesInfoInteger MockSeries
#define CopyTime MockCopyTime
#define TerminalInfoInteger MockTerminal
#include "../../macrossover_orb/MaCrossSignalCore.mqh"
#include "../../macrossover_orb/MaCrossAuditCache.mqh"
#undef SeriesInfoInteger
#undef CopyTime
#undef TerminalInfoInteger
struct HistResult {bool valid;string outcome;string invalidReason;};
enum FixtureExit {ORB_EXIT_FIXED_TARGET,ORB_EXIT_EOD_ONLY,ORB_EXIT_BROKER_TIME};
enum FixtureTarget {ORB_TARGET_R_LEG,ORB_TARGET_EOD};
FixtureExit g_rtExitMode=ORB_EXIT_FIXED_TARGET;
FixtureTarget g_rtTargetMode=ORB_TARGET_R_LEG;
ENUM_TIMEFRAMES fixtureTf=PERIOD_M1;
bool g_histTickResumeAllowed=false;
#define ORB_HIST_TICK_PREFETCH_MINUTES 15
ENUM_TIMEFRAMES RuntimeEntryTf(){return fixtureTf;}
datetime BarCloseTime(ENUM_TIMEFRAMES tf,datetime at){return at+PeriodSeconds(tf);}
datetime BrokerTimeExitFor(datetime at){return at+3600;}
void ClearHistoricalTickResume(){}
HistResult SimulateTrade(datetime at,datetime end,double entry,double sl,bool buy,double tp1,double tp2,double tp3,int half,bool scheduled,datetime forced,string why)
{HistResult r;r.valid=end>at+PeriodSeconds(fixtureTf);r.outcome=r.valid?"win":"DATA";r.invalidReason=r.valid?"":"INVERSE_TICKS_REQUIRED";return r;}

HistResult OrbLifecycle(datetime entryTime,datetime sessionEnd,datetime now,double entry,double sl,bool isBuy,
                                       double tp1,double tp2,double tp3,int halfBeLeg,datetime &usedEnd,
                                       datetime forcedExitTime=0,string forcedExitOutcome="")
{
   ClearHistoricalTickResume();
   g_histTickResumeAllowed=true;
   bool sessionBound=(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD);
   bool brokerBound=(g_rtExitMode==ORB_EXIT_BROKER_TIME);
   int sec=PeriodSeconds(RuntimeEntryTf());if(sec<=0)sec=60;
   datetime horizon=sessionEnd;
   if(sessionBound)
   {
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else if(brokerBound)
   {
      horizon=BrokerTimeExitFor(entryTime)+sec;
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else
   {
      // Fixed-target trades are not session-bound. Start with a compact exact
      // window; unresolved trades expand below without changing chronology.
      datetime firstEnd=BarCloseTime(RuntimeEntryTf(),entryTime);
      if(firstEnd<entryTime+sec)firstEnd=entryTime+sec;
      firstEnd+=ORB_HIST_TICK_PREFETCH_MINUTES*60;
      horizon=firstEnd;
      if(forcedExitTime>entryTime&&forcedExitTime<horizon)horizon=forcedExitTime+sec;
      if(horizon>now)horizon=now;
   }
   if(horizon<=entryTime)horizon=now;

   bool scheduledEndReached=(!sessionBound||now>=sessionEnd);
   HistResult sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,scheduledEndReached,forcedExitTime,forcedExitOutcome);
   int expand=0;
   // 15-minute prefetch needs two additional doublings to preserve the old
   // one-hour/16-step maximum horizon. Twenty steps safely covers 5Y audits.
   while(sim.valid&&sim.outcome=="open"&&!sessionBound&&!brokerBound&&horizon<now&&expand<20)
   {
      long span=(long)(horizon-entryTime);
      if(span<ORB_HIST_TICK_PREFETCH_MINUTES*60)span=ORB_HIST_TICK_PREFETCH_MINUTES*60;
      long grown=span*2;
      datetime nextEnd=(datetime)((long)entryTime+grown);
      if(nextEnd>now)nextEnd=now;
      if(nextEnd<=horizon)break;
      horizon=nextEnd;
      sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,true,forcedExitTime,forcedExitOutcome);
      expand++;
   }
   usedEnd=horizon;
   g_histTickResumeAllowed=false;
   ClearHistoricalTickResume();
   return sim;
}

HistResult MaLifecycle(datetime entryTime,datetime sessionEnd,datetime now,double entry,double sl,bool isBuy,
                                       double tp1,double tp2,double tp3,int halfBeLeg,datetime &usedEnd,
                                       datetime forcedExitTime=0,string forcedExitOutcome="")
{
   ClearHistoricalTickResume();
   g_histTickResumeAllowed=true;
   bool sessionBound=(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD);
   bool brokerBound=(g_rtExitMode==ORB_EXIT_BROKER_TIME);
   int sec=PeriodSeconds(RuntimeEntryTf());if(sec<=0)sec=60;
   datetime horizon=sessionEnd;
   if(sessionBound)
   {
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else if(brokerBound)
   {
      horizon=BrokerTimeExitFor(entryTime)+sec;
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else
   {
      // Fixed-target trades are not session-bound. Start with a compact exact
      // window; unresolved trades expand below without changing chronology.
      datetime firstEnd=BarCloseTime(RuntimeEntryTf(),entryTime);
      if(firstEnd<entryTime+sec)firstEnd=entryTime+sec;
      firstEnd+=ORB_HIST_TICK_PREFETCH_MINUTES*60;
      horizon=firstEnd;
      if(forcedExitTime>entryTime&&forcedExitTime<horizon)horizon=forcedExitTime+sec;
      if(horizon>now)horizon=now;
   }
   if(horizon<=entryTime)horizon=now;

   bool scheduledEndReached=(!sessionBound||now>=sessionEnd);
   HistResult sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,scheduledEndReached,forcedExitTime,forcedExitOutcome);
   int expand=0;
   // 15-minute prefetch needs two additional doublings to preserve the old
   // one-hour/16-step maximum horizon. Twenty steps safely covers 5Y audits.
   // A short initial slice can contain only the signal candle before a
   // scheduled market break. Extend it instead of declaring missing history.
   while(((sim.valid&&sim.outcome=="open")||(!sim.valid&&sim.invalidReason=="NO_MARKET_DATA"))&&!sessionBound&&!brokerBound&&horizon<now&&expand<20)
   {
      long span=(long)(horizon-entryTime);
      if(span<ORB_HIST_TICK_PREFETCH_MINUTES*60)span=ORB_HIST_TICK_PREFETCH_MINUTES*60;
      long grown=span*2;
      datetime nextEnd=(datetime)((long)entryTime+grown);
      if(nextEnd>now)nextEnd=now;
      if(nextEnd<=horizon)break;
      horizon=nextEnd;
      sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,true,forcedExitTime,forcedExitOutcome);
      expand++;
   }
   usedEnd=horizon;
   g_histTickResumeAllowed=false;
   ClearHistoricalTickResume();
   return sim;
}

HistResult LabLifecycle(datetime entryTime,datetime sessionEnd,datetime now,double entry,double sl,bool isBuy,
                                       double tp1,double tp2,double tp3,int halfBeLeg,datetime &usedEnd,
                                       datetime forcedExitTime=0,string forcedExitOutcome="")
{
   ClearHistoricalTickResume();
   g_histTickResumeAllowed=true;
   bool sessionBound=(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD);
   bool brokerBound=(g_rtExitMode==ORB_EXIT_BROKER_TIME);
   int sec=PeriodSeconds(RuntimeEntryTf());if(sec<=0)sec=60;
   datetime horizon=sessionEnd;
   if(sessionBound)
   {
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else if(brokerBound)
   {
      horizon=BrokerTimeExitFor(entryTime)+sec;
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else
   {
      // Fixed-target trades are not session-bound. Start with a compact exact
      // window; unresolved trades expand below without changing chronology.
      datetime firstEnd=BarCloseTime(RuntimeEntryTf(),entryTime);
      if(firstEnd<entryTime+sec)firstEnd=entryTime+sec;
      firstEnd+=ORB_HIST_TICK_PREFETCH_MINUTES*60;
      horizon=firstEnd;
      if(forcedExitTime>entryTime&&forcedExitTime<horizon)horizon=forcedExitTime+sec;
      if(horizon>now)horizon=now;
   }
   if(horizon<=entryTime)horizon=now;

   bool scheduledEndReached=(!sessionBound||now>=sessionEnd);
   HistResult sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,scheduledEndReached,forcedExitTime,forcedExitOutcome);
   int expand=0;
   // 15-minute prefetch needs two additional doublings to preserve the old
   // one-hour/16-step maximum horizon. Twenty steps safely covers 5Y audits.
   // A short initial slice can contain only the signal candle before a
   // scheduled market break. Extend it instead of declaring missing history.
   while(((sim.valid&&sim.outcome=="open")||(!sim.valid&&sim.invalidReason=="NO_MARKET_DATA"))&&!sessionBound&&!brokerBound&&horizon<now&&expand<20)
   {
      long span=(long)(horizon-entryTime);
      if(span<ORB_HIST_TICK_PREFETCH_MINUTES*60)span=ORB_HIST_TICK_PREFETCH_MINUTES*60;
      long grown=span*2;
      datetime nextEnd=(datetime)((long)entryTime+grown);
      if(nextEnd>now)nextEnd=now;
      if(nextEnd<=horizon)break;
      horizon=nextEnd;
      sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,true,forcedExitTime,forcedExitOutcome);
      expand++;
   }
   usedEnd=horizon;
   g_histTickResumeAllowed=false;
   ClearHistoricalTickResume();
   return sim;
}
void OnStart(){
 string detail="";bool blocked=false;
 datetime seed=McHistorySeed("fixture",PERIOD_M15);
 Check(seed==D'2019.09.13 01:30:00',"stable server-aligned origin");
 Check(!McHistoryReady("fixture",PERIOD_M15,seed,detail,blocked)&&!blocked,"partial synchronized suffix waits");
 mockLoaded=D'2020.01.01';Check(seed==McHistorySeed("fixture",PERIOD_M15),"loaded-prefix expansion never changes origin");
 mockDownload=true;Check(McHistoryReady("fixture",PERIOD_M15,seed,detail,blocked),"download completion releases readiness");
 mockDownload=false;mockLoaded=D'2020.01.01';mockBars=3000000;
 Check(!McHistoryReady("fixture",PERIOD_M15,seed,detail,blocked)&&blocked,"MaxBars is explicit not silently truncated");
 mockServer=D'2018.02.09';mockLoaded=D'2018.02.09 10:00';mockOrigin=mockLoaded;
 datetime gapSeed=McHistorySeed("BTCfixture",PERIOD_M5);
 Check(gapSeed==mockLoaded,"first real bar, not nonexistent midnight");
 g_maCrossAuditReady=true;g_maCrossAuditSymbol="BTCfixture";g_maCrossAuditTf=PERIOD_M5;
 g_maCrossAuditMode=MA_CROSS_TRENDER_IQ;g_maCrossAuditSeed=gapSeed;
 mockLoaded=D'2018.02.09 09:00';mockOrigin=mockLoaded;
 Check(!MaCrossAuditOriginStable(),"late first-day prefix invalidates in-flight audit");
 mockServer=0;Check(McHistorySeed("fixture",PERIOD_M15)==0,"unknown broker origin is not fabricated");
 ENUM_TIMEFRAMES frames[]={PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4};
 datetime at=D'2026.10.08 12:00:00',used=0,now=at+86400;
 for(int i=0;i<ArraySize(frames);i++){
 fixtureTf=frames[i];
 HistResult a=OrbLifecycle(at,now,now,100,99,true,101,101,101,0,used);
 Check(a.valid&&used>at+PeriodSeconds(fixtureTf),"ORB fill covered "+EnumToString(fixtureTf));
 HistResult b=MaLifecycle(at,now,now,100,99,true,101,101,101,0,used);
 Check(b.valid&&used>at+PeriodSeconds(fixtureTf),"Ma fill covered "+EnumToString(fixtureTf));
 HistResult c=LabLifecycle(at,now,now,100,99,true,101,101,101,0,used);
 Check(c.valid&&used>at+PeriodSeconds(fixtureTf),"Lab fill covered "+EnumToString(fixtureTf));
 }
 int file=FileOpen("AuditFailureBoundaryProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
 if(file!=INVALID_HANDLE){FileWriteString(file,"{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}");FileClose(file);}
}
