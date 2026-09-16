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
};

MaCrossAuditEvent g_maCrossAuditEvents[];
datetime g_maCrossAuditFrom=0;
datetime g_maCrossAuditTo=0;
MA_CROSS_SIGNAL_MODE g_maCrossAuditMode=MA_CROSS_ORIGINAL_MTF;
MA_CROSS_PAIR g_maCrossAuditPair=MA_CROSS_PAIR_FAST;
ENUM_TIMEFRAMES g_maCrossAuditTf=PERIOD_CURRENT;
int g_maCrossAuditFast=0,g_maCrossAuditMedium=0,g_maCrossAuditSlow=0;
bool g_maCrossAuditReady=false;

void MaCrossAuditInvalidate()
{
   ArrayResize(g_maCrossAuditEvents,0);
   g_maCrossAuditReady=false;
   g_maCrossAuditFrom=0;g_maCrossAuditTo=0;g_maCrossAuditTf=PERIOD_CURRENT;
}

// The live kernel intentionally evaluates only one closed bar, where its
// straightforward EMA/HMA helpers are ideal for readability.  Calling that
// same O(bar_index) kernel for every bar in a multi-year audit made the cache
// build quadratic and left the dashboard frozen before its audit state began.
// These series helpers implement the identical recursive definitions in one
// forward pass; they are used only to enumerate historical closed-bar events.
void McAuditEmaSeries(const MqlRates &rates[],const int length,double &out[])
{
   int count=ArraySize(rates);ArrayResize(out,count);if(count<=0)return;
   double alpha=2.0/(MathMax(1,length)+1.0);out[0]=rates[0].close;
   for(int i=1;i<count;i++)out[i]=alpha*rates[i].close+(1.0-alpha)*out[i-1];
}

void McAuditWmaSeries(const double &source[],const int length,double &out[])
{
   int count=ArraySize(source);ArrayResize(out,count);ArrayInitialize(out,0.0);
   if(count<=0||length<1)return;
   double sum=0.0,weighted=0.0,den=(double)length*(length+1.0)/2.0;
   for(int i=0;i<count;i++)
   {
      if(i<length)
      {
         sum+=source[i];weighted+=source[i]*(i+1);
         if(i==length-1)out[i]=weighted/den;
      }
      else
      {
         weighted=weighted-sum+(double)length*source[i];
         sum=sum-source[i-length]+source[i];
         out[i]=weighted/den;
      }
   }
}

void McAuditHmaSeries(const MqlRates &rates[],const int length,double &out[])
{
   int count=ArraySize(rates);ArrayResize(out,count);ArrayInitialize(out,0.0);
   if(count<=0||length<1)return;
   double close[],halfWma[],fullWma[],raw[],rawWma[];
   ArrayResize(close,count);ArrayResize(raw,count);ArrayInitialize(raw,0.0);
   for(int i=0;i<count;i++)close[i]=rates[i].close;
   int half=MathMax(1,length/2),root=MathMax(1,(int)MathRound(MathSqrt((double)length)));
   McAuditWmaSeries(close,half,halfWma);McAuditWmaSeries(close,length,fullWma);
   for(int i=length-1;i<count;i++)raw[i]=2.0*halfWma[i]-fullWma[i];
   McAuditWmaSeries(raw,root,rawWma);
   for(int i=length+root-2;i<count;i++)out[i]=rawWma[i];
}

void McAuditAtrSeries(const MqlRates &rates[],const int length,double &out[])
{
   int count=ArraySize(rates);ArrayResize(out,count);ArrayInitialize(out,0.0);
   if(count<=1)return;
   double prefix[];ArrayResize(prefix,count);prefix[0]=0.0;
   for(int i=1;i<count;i++)prefix[i]=prefix[i-1]+McTrueRange(rates,i);
   for(int i=1;i<count;i++)
   {
      int start=MathMax(1,i-MathMax(1,length)+1);
      double sum=prefix[i]-(start>0?prefix[start-1]:0.0);
      out[i]=sum/(double)(i-start+1);
   }
}

void McAuditAppend(const MqlRates &rates[],const int index,const int direction,const datetime from,const datetime to,
                   const double &volumePrefix[])
{
   if(direction==0||index<0||index>=ArraySize(rates)||rates[index].time<from||rates[index].time>to)return;
   MaCrossAuditEvent event;
   event.signalTime=rates[index].time;event.close=rates[index].close;event.high=rates[index].high;
   event.low=rates[index].low;event.volume=(double)rates[index].tick_volume;event.direction=direction;
   int used=MathMin(20,index);
   double total=used>0?volumePrefix[index-1]-(index-used>0?volumePrefix[index-used-1]:0.0):0.0;
   event.priorVolume=used>0?total/(double)used:0.0;
   int slot=ArraySize(g_maCrossAuditEvents);ArrayResize(g_maCrossAuditEvents,slot+1);g_maCrossAuditEvents[slot]=event;
}

void McAuditOriginalEvents(const MqlRates &rates[],const MqlRates &h4[],const int fastLen,const int mediumLen,const int slowLen,
                           const MA_CROSS_PAIR pair,const datetime from,const datetime to,const double &volumePrefix[])
{
   double fast[],medium[],slow[],h4Slow[];
   McAuditEmaSeries(rates,fastLen,fast);McAuditEmaSeries(rates,mediumLen,medium);McAuditHmaSeries(rates,slowLen,slow);
   McAuditHmaSeries(h4,slowLen,h4Slow);
   for(int i=250;i<ArraySize(rates);i++)
   {
      double a0=fast[i],b0=medium[i],a1=fast[i-1],b1=medium[i-1];
      if(pair==MA_CROSS_PAIR_MEDIUM){b0=slow[i];b1=slow[i-1];}
      else if(pair==MA_CROSS_PAIR_SLOW){a0=medium[i];b0=slow[i];a1=medium[i-1];b1=slow[i-1];}
      int dir=McCrossUp(a0,b0,a1,b1)?1:(McCrossDown(a0,b0,a1,b1)?-1:0);
      if(dir==0)continue;
      int hAt=McFindRateAtOrBefore(h4,rates[i].time);
      double hma=(hAt>=0&&hAt<ArraySize(h4Slow)?h4Slow[hAt]:0.0);
      if(hma<=0.0||((dir>0)&&rates[i].close<=hma)||((dir<0)&&rates[i].close>=hma))continue;
      McAuditAppend(rates,i,dir,from,to,volumePrefix);
   }
}

void McAuditEma50200Events(const MqlRates &rates[],const datetime from,const datetime to,const double &volumePrefix[])
{
   double fast[],slow[];McAuditEmaSeries(rates,50,fast);McAuditEmaSeries(rates,200,slow);
   for(int i=250;i<ArraySize(rates);i++)
      McAuditAppend(rates,i,McCrossUp(fast[i],slow[i],fast[i-1],slow[i-1])?1:(McCrossDown(fast[i],slow[i],fast[i-1],slow[i-1])?-1:0),from,to,volumePrefix);
}

void McAuditTrendlineEvents(const MqlRates &rates[],const datetime from,const datetime to,const double &volumePrefix[])
{
   const int length=24;double atr[];McAuditAtrSeries(rates,length,atr);
   double upper=0.0,lower=0.0,slopeHi=0.0,slopeLo=0.0;bool haveUpper=false,haveLower=false;
   for(int i=length*2;i<ArraySize(rates);i++)
   {
      int pivot=i-length;double slope=atr[i]/(double)length*1.6;
      if(McIsPivotHigh(rates,pivot,length,length)){upper=rates[pivot].high;slopeHi=slope;haveUpper=true;}
      else if(haveUpper)upper-=slopeHi;
      if(McIsPivotLow(rates,pivot,length,length)){lower=rates[pivot].low;slopeLo=slope;haveLower=true;}
      else if(haveLower)lower+=slopeLo;
      int dir=0;
      if(haveUpper&&McCrossUp(rates[i].close,upper,rates[i-1].close,upper+slopeHi))dir=1;
      else if(haveLower&&McCrossDown(rates[i].close,lower,rates[i-1].close,lower-slopeLo))dir=-1;
      McAuditAppend(rates,i,dir,from,to,volumePrefix);
   }
}

void McAuditPivotStEvents(const MqlRates &rates[],const datetime from,const datetime to,const double &volumePrefix[])
{
   const int pd=10,pivotLen=2;double atr[];McAuditAtrSeries(rates,pd,atr);
   double center=0.0,tUp=0.0,tDn=0.0;int trend=1;bool haveCenter=false;
   for(int i=pivotLen*2;i<ArraySize(rates);i++)
   {
      int pivot=i-pivotLen;double pp=0.0;bool hasPp=false;
      if(McIsPivotHigh(rates,pivot,pivotLen,pivotLen)){pp=rates[pivot].high;hasPp=true;}
      else if(McIsPivotLow(rates,pivot,pivotLen,pivotLen)){pp=rates[pivot].low;hasPp=true;}
      if(hasPp){center=haveCenter?(center*2.0+pp)/3.0:pp;haveCenter=true;}
      if(!haveCenter)continue;
      double up=center-3.0*atr[i],dn=center+3.0*atr[i];
      if(i==pivotLen*2){tUp=up;tDn=dn;continue;}
      double prevClose=rates[i-1].close,prevUp=tUp,prevDn=tDn;
      tUp=prevClose>prevUp?MathMax(up,prevUp):up;
      tDn=prevClose<prevDn?MathMin(dn,prevDn):dn;
      int previous=trend;if(rates[i].close>prevDn)trend=1;else if(rates[i].close<prevUp)trend=-1;
      McAuditAppend(rates,i,trend!=previous?trend:0,from,to,volumePrefix);
   }
}

void McAuditScalpEvents(const MqlRates &rates[],const datetime from,const datetime to,const double &volumePrefix[])
{
   int count=ArraySize(rates);if(count<651)return;
   double haOpen=(rates[0].open+rates[0].close)/2.0,haClose=(rates[0].open+rates[0].high+rates[0].low+rates[0].close)/4.0;
   double fast=haClose,medium=haClose,pacC=haClose,pacU=MathMax(rates[0].high,MathMax(haOpen,haClose)),pacL=MathMin(rates[0].low,MathMin(haOpen,haClose));
   int state=0,lastBelow=-100000,lastAbove=-100000;
   for(int i=1;i<count;i++)
   {
      double nextClose=(rates[i].open+rates[i].high+rates[i].low+rates[i].close)/4.0;
      double nextOpen=(haOpen+haClose)/2.0;double nextHigh=MathMax(rates[i].high,MathMax(nextOpen,nextClose)),nextLow=MathMin(rates[i].low,MathMin(nextOpen,nextClose));
      haOpen=nextOpen;haClose=nextClose;
      fast+=(haClose-fast)*2.0/13.0;medium+=(haClose-medium)*2.0/201.0;pacC+=(haClose-pacC)*2.0/35.0;pacU+=(nextHigh-pacU)*2.0/35.0;pacL+=(nextLow-pacL)*2.0/35.0;
      if(haClose<pacC)lastBelow=i;if(haClose>pacC)lastAbove=i;
      int trend=(fast>medium&&pacL>medium)?1:((fast<medium&&pacU<medium)?-1:0);
      bool buy=trend==1&&haOpen<pacU&&haClose>pacU&&(i-lastBelow)<=3;
      bool sell=trend==-1&&haOpen>pacL&&haClose<pacL&&(i-lastAbove)<=3;
      int previous=state;if(previous==1&&haClose<pacC)state=0;else if(previous==-1&&haClose>pacC)state=0;else if(previous==0&&buy)state=1;else if(previous==0&&sell)state=-1;
      if(i>=650&&previous==0&&state!=0)McAuditAppend(rates,i,state,from,to,volumePrefix);
   }
}

bool MaCrossAuditBuild(const string symbol,const ENUM_TIMEFRAMES tf,const datetime from,const datetime to,
                       const MA_CROSS_SIGNAL_MODE mode,const MA_CROSS_PAIR pair,
                       const int fastLen,const int mediumLen,const int slowLen)
{
   if(g_maCrossAuditReady&&g_maCrossAuditFrom<=from&&g_maCrossAuditTo>=to
      &&g_maCrossAuditMode==mode&&g_maCrossAuditPair==pair&&g_maCrossAuditTf==tf&&g_maCrossAuditFast==fastLen
      &&g_maCrossAuditMedium==mediumLen&&g_maCrossAuditSlow==slowLen)return true;
   const int seconds=MathMax(60,PeriodSeconds(tf));
   const int warmup=mode==MA_CROSS_SCALP_PULLBACK?900:MathMax(600,slowLen+80);
   const datetime warmFrom=from-(datetime)((long)warmup*(long)seconds);
   MqlRates r[],h4[];ArraySetAsSeries(r,false);ArraySetAsSeries(h4,false);
   const int copied=CopyRates(symbol,tf,warmFrom,to,r);
   if(copied<=warmup)return false;
   CopyRates(symbol,PERIOD_H4,warmFrom-(datetime)(260L*4L*3600L),to,h4);
   ArrayResize(g_maCrossAuditEvents,0);
   double volumePrefix[];ArrayResize(volumePrefix,copied);volumePrefix[0]=(double)r[0].tick_volume;
   for(int i=1;i<copied;i++)volumePrefix[i]=volumePrefix[i-1]+(double)r[i].tick_volume;
   if(mode==MA_CROSS_ORIGINAL_MTF)McAuditOriginalEvents(r,h4,fastLen,mediumLen,slowLen,pair,from,to,volumePrefix);
   else if(mode==MA_CROSS_EMA_50_200)McAuditEma50200Events(r,from,to,volumePrefix);
   else if(mode==MA_CROSS_TRENDLINE)McAuditTrendlineEvents(r,from,to,volumePrefix);
   else if(mode==MA_CROSS_PIVOT_ST)McAuditPivotStEvents(r,from,to,volumePrefix);
   else McAuditScalpEvents(r,from,to,volumePrefix);
   g_maCrossAuditFrom=from;g_maCrossAuditTo=to;g_maCrossAuditMode=mode;g_maCrossAuditPair=pair;g_maCrossAuditTf=tf;
   g_maCrossAuditFast=fastLen;g_maCrossAuditMedium=mediumLen;g_maCrossAuditSlow=slowLen;
   g_maCrossAuditReady=true;
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
   for(int i=MaCrossAuditFirstAfter(after);i<ArraySize(g_maCrossAuditEvents);i++)
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
