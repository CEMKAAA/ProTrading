// Closed-bar-only signal kernels ported from MaCrossOver.pine and Crossover2.pine.
// This file intentionally has no execution, audit, or bridge side effects.
#ifndef MACROSS_SIGNAL_CORE_MQH
#define MACROSS_SIGNAL_CORE_MQH

enum MA_CROSS_SIGNAL_MODE
{
   MA_CROSS_ORIGINAL_MTF = 0,
   MA_CROSS_EMA_50_200  = 1,
   MA_CROSS_TRENDLINE   = 2,
   MA_CROSS_PIVOT_ST    = 3,
   MA_CROSS_SCALP_PULLBACK = 4
};

// Mirrors MaCrossOver.pine's Cross Mode input. It applies only to MA MTF;
// the four Crossover2 kernels have their own fixed definitions.
enum MA_CROSS_PAIR
{
   MA_CROSS_PAIR_FAST = 0,   // EMA fast vs EMA medium
   MA_CROSS_PAIR_MEDIUM = 1, // EMA fast vs local HMA slow
   MA_CROSS_PAIR_SLOW = 2    // EMA medium vs local HMA slow
};

struct MaCrossSignal
{
   bool valid;
   int direction; // +1 BUY, -1 SELL
   datetime barTime;
   double price;
};

double McEmaAt(const MqlRates &r[],const int at,const int len)
{
   if(len<1||at<0||ArraySize(r)<=at)return 0.0;
   const double a=2.0/(len+1.0);
   double v=r[0].close;
   for(int i=1;i<=at;i++)v=a*r[i].close+(1.0-a)*v;
   return v;
}

double McWmaClose(const MqlRates &r[],const int at,const int len)
{
   if(len<1||at-len+1<0)return 0.0;
   double n=0.0,d=0.0;
   for(int i=0;i<len;i++){const double w=(double)(i+1);n+=r[at-len+1+i].close*w;d+=w;}
   return d>0.0?n/d:0.0;
}

double McHmaAt(const MqlRates &r[],const int at,const int len)
{
   const int half=MathMax(1,len/2), root=MathMax(1,(int)MathRound(MathSqrt((double)len)));
   if(at-len-root+2<0)return 0.0;
   double n=0.0,d=0.0;
   for(int i=0;i<root;i++)
   {
      const int p=at-root+1+i;
      const double raw=2.0*McWmaClose(r,p,half)-McWmaClose(r,p,len);
      const double w=(double)(i+1);n+=raw*w;d+=w;
   }
   return d>0.0?n/d:0.0;
}

double McTrueRange(const MqlRates &r[],const int i)
{
   if(i<=0||i>=ArraySize(r))return r[i].high-r[i].low;
   return MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i-1].close),MathAbs(r[i].low-r[i-1].close)));
}

double McAtrAt(const MqlRates &r[],const int at,const int len)
{
   if(at<1||len<1)return 0.0;
   const int start=MathMax(1,at-len+1);
   double v=0.0;int c=0;
   for(int i=start;i<=at;i++){v+=McTrueRange(r,i);c++;}
   return c>0?v/(double)c:0.0;
}

bool McCrossUp(const double a0,const double b0,const double a1,const double b1){return a0>b0&&a1<=b1;}
bool McCrossDown(const double a0,const double b0,const double a1,const double b1){return a0<b0&&a1>=b1;}

bool McIsPivotHigh(const MqlRates &r[],const int at,const int left,const int right)
{
   if(at-left<0||at+right>=ArraySize(r))return false;
   const double x=r[at].high;
   for(int i=at-left;i<=at+right;i++)if(i!=at&&r[i].high>=x)return false;
   return true;
}

bool McIsPivotLow(const MqlRates &r[],const int at,const int left,const int right)
{
   if(at-left<0||at+right>=ArraySize(r))return false;
   const double x=r[at].low;
   for(int i=at-left;i<=at+right;i++)if(i!=at&&r[i].low<=x)return false;
   return true;
}

bool McTrendlineSignal(const MqlRates &r[],const int at,int &dir)
{
   const int len=24;
   if(at<len*3)return false;
   double upper=0.0,lower=0.0,slopeHi=0.0,slopeLo=0.0;
   bool haveUpper=false,haveLower=false;
   for(int i=len*2;i<=at;i++)
   {
      const int pivot=i-len;
      const double slope=McAtrAt(r,i,len)/(double)len*1.6;
      if(McIsPivotHigh(r,pivot,len,len)){upper=r[pivot].high;slopeHi=slope;haveUpper=true;}
      else if(haveUpper)upper-=slopeHi;
      if(McIsPivotLow(r,pivot,len,len)){lower=r[pivot].low;slopeLo=slope;haveLower=true;}
      else if(haveLower)lower+=slopeLo;
      if(i==at && haveUpper && McCrossUp(r[i].close,upper,r[i-1].close,upper+slopeHi)) {dir=1;return true;}
      if(i==at && haveLower && McCrossDown(r[i].close,lower,r[i-1].close,lower-slopeLo)) {dir=-1;return true;}
   }
   return false;
}

bool McPivotSuperTrendSignal(const MqlRates &r[],const int at,int &dir)
{
   const int pd=10, pivotLen=2;
   if(at<pd+pivotLen*2+2)return false;
   double center=0.0,tUp=0.0,tDn=0.0;int trend=1;
   bool haveCenter=false;
   for(int i=pivotLen*2;i<=at;i++)
   {
      const int pivot=i-pivotLen;
      double pp=0.0;bool hasPp=false;
      if(McIsPivotHigh(r,pivot,pivotLen,pivotLen)){pp=r[pivot].high;hasPp=true;}
      else if(McIsPivotLow(r,pivot,pivotLen,pivotLen)){pp=r[pivot].low;hasPp=true;}
      if(hasPp){center=haveCenter?(center*2.0+pp)/3.0:pp;haveCenter=true;}
      if(!haveCenter)continue;
      const double atr=McAtrAt(r,i,pd), up=center-3.0*atr, dn=center+3.0*atr;
      if(i==pivotLen*2){tUp=up;tDn=dn;continue;}
      const double prevClose=r[i-1].close,prevUp=tUp,prevDn=tDn;
      tUp=prevClose>prevUp?MathMax(up,prevUp):up;
      tDn=prevClose<prevDn?MathMin(dn,prevDn):dn;
      const int previous=trend;
      if(r[i].close>prevDn)trend=1; else if(r[i].close<prevUp)trend=-1;
      if(i==at&&trend!=previous){dir=trend;return true;}
   }
   return false;
}

bool McScalpPullbackSignal(const MqlRates &r[],const int at,int &dir)
{
   if(at<650)return false;
   const int n=at+1;
   double haOpen[],haClose[],haHigh[],haLow[];
   ArrayResize(haOpen,n);ArrayResize(haClose,n);ArrayResize(haHigh,n);ArrayResize(haLow,n);
   for(int i=0;i<n;i++)
   {
      haClose[i]=(r[i].open+r[i].high+r[i].low+r[i].close)/4.0;
      haOpen[i]=(i==0?(r[i].open+r[i].close)/2.0:(haOpen[i-1]+haClose[i-1])/2.0);
      haHigh[i]=MathMax(r[i].high,MathMax(haOpen[i],haClose[i]));
      haLow[i]=MathMin(r[i].low,MathMin(haOpen[i],haClose[i]));
   }
   double fast=haClose[0],med=haClose[0],pacC=haClose[0],pacU=haHigh[0],pacL=haLow[0];
   int state=0,lastBelow=-100000,lastAbove=-100000;
   for(int i=1;i<=at;i++)
   {
      fast+=(haClose[i]-fast)*2.0/13.0;med+=(haClose[i]-med)*2.0/201.0;
      pacC+=(haClose[i]-pacC)*2.0/35.0;pacU+=(haHigh[i]-pacU)*2.0/35.0;pacL+=(haLow[i]-pacL)*2.0/35.0;
      if(haClose[i]<pacC)lastBelow=i;if(haClose[i]>pacC)lastAbove=i;
      const int trend=(fast>med&&pacL>med)?1:((fast<med&&pacU<med)?-1:0);
      const bool buy=trend==1&&haOpen[i]<pacU&&haClose[i]>pacU&&(i-lastBelow)<=3;
      const bool sell=trend==-1&&haOpen[i]>pacL&&haClose[i]<pacL&&(i-lastAbove)<=3;
      const int previous=state;
      if(previous==1&&haClose[i]<pacC)state=0;
      else if(previous==-1&&haClose[i]>pacC)state=0;
      else if(previous==0&&buy)state=1;
      else if(previous==0&&sell)state=-1;
      if(i==at&&previous==0&&state!=0){dir=state;return true;}
   }
   return false;
}

int McFindRateAtOrBefore(const MqlRates &r[],const datetime when)
{
   int lo=0,hi=ArraySize(r)-1,answer=-1;
   while(lo<=hi)
   {
      const int mid=lo+(hi-lo)/2;
      if(r[mid].time<=when){answer=mid;lo=mid+1;}else hi=mid-1;
   }
   return answer;
}

bool MaCrossSignalAt(const MqlRates &r[],const int at,const MA_CROSS_SIGNAL_MODE mode,
                     const MA_CROSS_PAIR pair,const int fastLen,const int mediumLen,const int slowLen,
                     const MqlRates &h4[],int &dir)
{
   dir=0;
   if(at<250||at>=ArraySize(r))return false;
   if(mode==MA_CROSS_ORIGINAL_MTF)
   {
      const double fast0=McEmaAt(r,at,fastLen),medium0=McEmaAt(r,at,mediumLen),slow0=McHmaAt(r,at,slowLen);
      const double fast1=McEmaAt(r,at-1,fastLen),medium1=McEmaAt(r,at-1,mediumLen),slow1=McHmaAt(r,at-1,slowLen);
      double short0=fast0,long0=medium0,short1=fast1,long1=medium1;
      if(pair==MA_CROSS_PAIR_MEDIUM){long0=slow0;long1=slow1;}
      else if(pair==MA_CROSS_PAIR_SLOW){short0=medium0;long0=slow0;short1=medium1;long1=slow1;}
      if(short0<=0.0||long0<=0.0||short1<=0.0||long1<=0.0)return false;
      if(McCrossUp(short0,long0,short1,long1))dir=1;else if(McCrossDown(short0,long0,short1,long1))dir=-1;
      if(dir!=0)
      {
         const int hAt=McFindRateAtOrBefore(h4,r[at].time);
         const double hma=McHmaAt(h4,hAt,slowLen);
         if(hma<=0.0||((dir>0)&&r[at].close<=hma)||((dir<0)&&r[at].close>=hma))dir=0;
      }
   }
   else if(mode==MA_CROSS_EMA_50_200)
   {
      const double a0=McEmaAt(r,at,50),b0=McEmaAt(r,at,200),a1=McEmaAt(r,at-1,50),b1=McEmaAt(r,at-1,200);
      if(McCrossUp(a0,b0,a1,b1))dir=1;else if(McCrossDown(a0,b0,a1,b1))dir=-1;
   }
   else if(mode==MA_CROSS_TRENDLINE)McTrendlineSignal(r,at,dir);
   else if(mode==MA_CROSS_PIVOT_ST)McPivotSuperTrendSignal(r,at,dir);
   else if(mode==MA_CROSS_SCALP_PULLBACK)McScalpPullbackSignal(r,at,dir);
   return dir!=0;
}

bool MaCrossComputeSignal(const string symbol,const ENUM_TIMEFRAMES tf,const MA_CROSS_SIGNAL_MODE mode,
                          const MA_CROSS_PAIR pair,const int fastLen,const int mediumLen,const int slowLen,
                          MaCrossSignal &out)
{
   out.valid=false;out.direction=0;out.barTime=0;out.price=0.0;
   const int bars=(mode==MA_CROSS_SCALP_PULLBACK?900:600);
   MqlRates r[];ArraySetAsSeries(r,false);
   const int copied=CopyRates(symbol,tf,0,bars,r);
   const int at=copied-2;
   if(at<250)return false;
   MqlRates h[];ArraySetAsSeries(h,false);CopyRates(symbol,PERIOD_H4,0,slowLen+40,h);
   int dir=0;
   MaCrossSignalAt(r,at,mode,pair,fastLen,mediumLen,slowLen,h,dir);
   if(dir==0)return false;
   out.valid=true;out.direction=dir;out.barTime=r[at].time;out.price=r[at].close;return true;
}

string MaCrossModeText(const MA_CROSS_SIGNAL_MODE mode)
{
   if(mode==MA_CROSS_ORIGINAL_MTF)return "MA MTF";
   if(mode==MA_CROSS_EMA_50_200)return "EMA 50/200";
   if(mode==MA_CROSS_TRENDLINE)return "Trendline";
   if(mode==MA_CROSS_PIVOT_ST)return "Pivot ST";
   return "Scalp Pullback";
}

string MaCrossPairText(const MA_CROSS_PAIR pair)
{
   if(pair==MA_CROSS_PAIR_MEDIUM)return "MED";
   if(pair==MA_CROSS_PAIR_SLOW)return "SLOW";
   return "FAST";
}
#endif
