// Immutable per-audit event cache. It keeps history and live signal timing on
// the same closed-bar kernels and avoids recomputing indicators per ORB day.
#ifndef MACROSS_AUDIT_CACHE_MQH
#define MACROSS_AUDIT_CACHE_MQH

struct MaCrossAuditEvent
{
   datetime signalTime;
   double close;
   double high;
   double low;
   double volume;
   double priorVolume;
   int direction;
   double markerPrice;
};

MaCrossAuditEvent g_maCrossAuditEvents[];
MaCrossAuditEvent g_maCrossAuditStoredEvents[];
datetime g_maCrossAuditFrom=0;
datetime g_maCrossAuditTo=0;
MA_CROSS_SIGNAL_MODE g_maCrossAuditMode=MA_CROSS_ORIGINAL_MTF;
MA_CROSS_PAIR g_maCrossAuditPair=MA_CROSS_PAIR_FAST;
ENUM_TIMEFRAMES g_maCrossAuditTf=PERIOD_CURRENT;
int g_maCrossAuditFast=0,g_maCrossAuditMedium=0,g_maCrossAuditSlow=0;
bool g_maCrossAuditReady=false;
string g_maCrossAuditFailure="";

void MaCrossAuditInvalidate()
{
   ArrayResize(g_maCrossAuditEvents,0);
   ArrayResize(g_maCrossAuditStoredEvents,0);
   g_maCrossAuditReady=false;
   g_maCrossAuditFrom=0;g_maCrossAuditTo=0;g_maCrossAuditTf=PERIOD_CURRENT;
}

string g_maCrossAuditSymbol="";
datetime g_maCrossAuditSeed=0,g_maCrossAuditHtfSeed=0,g_maCrossAuditClosed=0;
ulong g_maCrossAuditBuildMs=0;
long g_maCrossAuditBars=0;
long g_maCrossAuditBuildCount=0,g_maCrossAuditReuseCount=0;

void MaCrossAuditSelect(const datetime from,const datetime end)
{
   int lo=0,hi=ArraySize(g_maCrossAuditStoredEvents);
   while(lo<hi)
   {int mid=lo+(hi-lo)/2;if(g_maCrossAuditStoredEvents[mid].signalTime<from)lo=mid+1;else hi=mid;}
   int first=lo;hi=ArraySize(g_maCrossAuditStoredEvents);
   while(lo<hi)
   {int mid=lo+(hi-lo)/2;if(g_maCrossAuditStoredEvents[mid].signalTime<=end)lo=mid+1;else hi=mid;}
   int count=lo-first;ArrayResize(g_maCrossAuditEvents,count);
   if(count>0)ArrayCopy(g_maCrossAuditEvents,g_maCrossAuditStoredEvents,0,first,count);
}

bool MaCrossAuditBuild(const string symbol,const ENUM_TIMEFRAMES tf,const datetime from,const datetime to,
                       const MA_CROSS_SIGNAL_MODE mode,const MA_CROSS_PAIR pair,
                       const int fastLen,const int mediumLen,const int slowLen)
{
   g_maCrossAuditFailure="";
   datetime seed=McHistorySeed(symbol,tf),closed=iTime(symbol,tf,1);
   datetime hSeed=mode==MA_CROSS_ORIGINAL_MTF?McHistorySeed(symbol,PERIOD_H4):0;
   const int seconds=PeriodSeconds(tf);
   // Cache closed candles, not the advancing wall-clock second within a candle.
   datetime end=MathMin(closed,to-seconds);
   if(g_maCrossAuditReady&&SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED)
      &&(mode!=MA_CROSS_ORIGINAL_MTF||SeriesInfoInteger(symbol,PERIOD_H4,SERIES_SYNCHRONIZED))
      &&g_maCrossAuditSymbol==symbol&&g_maCrossAuditFrom<=from&&g_maCrossAuditTo>=end
      &&g_maCrossAuditSeed==seed&&g_maCrossAuditHtfSeed==hSeed&&g_maCrossAuditClosed==closed
      &&g_maCrossAuditMode==mode&&g_maCrossAuditPair==pair&&g_maCrossAuditTf==tf
      &&g_maCrossAuditFast==fastLen&&g_maCrossAuditMedium==mediumLen&&g_maCrossAuditSlow==slowLen)
   {MaCrossAuditSelect(from,end);g_maCrossAuditReuseCount++;return true;}
   g_maCrossAuditReady=false;
   if(seed<=0||closed<=0||!SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED))
   {g_maCrossAuditFailure="signal series not synchronized";return false;}
   // A historical end time may cut through a candle. That candle is not an event.
   MqlRates rates[],higher[];ArraySetAsSeries(rates,false);ArraySetAsSeries(higher,false);
   ulong started=GetTickCount64();
   ResetLastError();
   int count=CopyRates(symbol,tf,seed,end,rates);
   int copyError=GetLastError();
   if(count<1||rates[0].time!=seed)
   {
      g_maCrossAuditFailure="signal CopyRates copied="+IntegerToString(count)
         +" error="+IntegerToString(copyError)
         +" seed="+TimeToString(seed,TIME_DATE|TIME_MINUTES)
         +" first="+(count>0?TimeToString(rates[0].time,TIME_DATE|TIME_MINUTES):"none")
         +" bars="+IntegerToString((int)SeriesInfoInteger(symbol,tf,SERIES_BARS_COUNT))
         +" max="+IntegerToString((int)TerminalInfoInteger(TERMINAL_MAXBARS));
      return false;
   }
   if(mode==MA_CROSS_ORIGINAL_MTF)
   {
      if(hSeed<=0||!SeriesInfoInteger(symbol,PERIOD_H4,SERIES_SYNCHRONIZED))
      {g_maCrossAuditFailure="H4 series not synchronized";return false;}
      ResetLastError();
      int hc=CopyRates(symbol,PERIOD_H4,hSeed,end+seconds-PeriodSeconds(PERIOD_H4),higher);
      if(hc<1||higher[0].time!=hSeed)
      {g_maCrossAuditFailure="H4 CopyRates copied="+IntegerToString(hc)+" error="+IntegerToString(GetLastError());return false;}
   }
   McPineKernel kernel;kernel.Reset(mode,pair,fastLen,mediumLen,slowLen);
   McRollingHma hma;hma.Reset(200);int h=0;double hv=0,volumeSum=0;
   ArrayResize(g_maCrossAuditStoredEvents,0);
   for(int i=0;i<count;i++)
   {
      if(IsStopped()){MaCrossAuditInvalidate();return false;}
      if(mode==MA_CROSS_ORIGINAL_MTF)McFeedHtf(higher,h,rates[i].time+seconds,hma,hv);
      int dir=kernel.Push(rates[i],hv);
      if(dir!=0&&rates[i].time>=from)
      {
         int slot=ArraySize(g_maCrossAuditStoredEvents);ArrayResize(g_maCrossAuditStoredEvents,slot+1,4096);
         g_maCrossAuditStoredEvents[slot].signalTime=rates[i].time;
         g_maCrossAuditStoredEvents[slot].close=rates[i].close;g_maCrossAuditStoredEvents[slot].high=rates[i].high;
         g_maCrossAuditStoredEvents[slot].low=rates[i].low;g_maCrossAuditStoredEvents[slot].volume=(double)rates[i].tick_volume;
         g_maCrossAuditStoredEvents[slot].priorVolume=i>0?volumeSum/MathMin(i,20):0;
         g_maCrossAuditStoredEvents[slot].direction=dir;
         g_maCrossAuditStoredEvents[slot].markerPrice=kernel.MarkerPrice();
      }
      volumeSum+=(double)rates[i].tick_volume;
      if(i>=20)volumeSum-=(double)rates[i-20].tick_volume;
   }
   g_maCrossAuditSymbol=symbol;g_maCrossAuditSeed=seed;g_maCrossAuditHtfSeed=hSeed;g_maCrossAuditClosed=closed;
   g_maCrossAuditFrom=from;g_maCrossAuditTo=end;g_maCrossAuditMode=mode;g_maCrossAuditPair=pair;g_maCrossAuditTf=tf;
   g_maCrossAuditFast=fastLen;g_maCrossAuditMedium=mediumLen;g_maCrossAuditSlow=slowLen;g_maCrossAuditReady=true;
   g_maCrossAuditBars=count;g_maCrossAuditBuildMs=GetTickCount64()-started;
   g_maCrossAuditBuildCount++;MaCrossAuditSelect(from,end);
   Print("MA_KERNEL ",MC_KERNEL_REVISION," symbol=",symbol," tf=",(int)tf," mode=",(int)mode,
         " bars=",count," events=",ArraySize(g_maCrossAuditEvents)," ms=",g_maCrossAuditBuildMs);
   return true;
}
int MaCrossAuditFirstAfter(const datetime after)
{
   int lo=0,hi=ArraySize(g_maCrossAuditEvents);
   while(lo<hi){const int mid=lo+(hi-lo)/2;if(g_maCrossAuditEvents[mid].signalTime<=after)lo=mid+1;else hi=mid;}
   return lo;
}

bool MaCrossAuditNext(const datetime from,const datetime to,const datetime after,
                      string &dir,datetime &time,double &close,double &high,double &low,double &vol,double &priorVol)
{
   dir="";time=0;close=high=low=vol=priorVol=0.0;
   for(int i=MaCrossAuditFirstAfter(MathMax(after,from-1));i<ArraySize(g_maCrossAuditEvents);i++)
   {
      const MaCrossAuditEvent event=g_maCrossAuditEvents[i];
      if(event.signalTime<from)continue;
      if(event.signalTime>to)break;
      dir=event.direction>0?"BUY":"SELL";time=event.signalTime;close=event.close;high=event.high;low=event.low;vol=event.volume;priorVol=event.priorVolume;
      return true;
   }
   return false;
}
#endif
