// Causal streaming primitives shared by live and historical signals.
#ifndef MA_CROSS_PINE_STREAM_MQH
#define MA_CROSS_PINE_STREAM_MQH
#define MC_KERNEL_REVISION "pine-stream-3-trender"
class McRollingWma
{
   double ring[],sum,weighted;int length,count,head;
public:
   void Reset(int period){length=MathMax(1,period);ArrayResize(ring,length);ArrayInitialize(ring,0);sum=weighted=0;count=head=0;}
   bool Push(double value,double &out)
   {
      out=0;
      if(count<length){sum+=value;weighted+=(count+1)*value;ring[head]=value;count++;}
      else {weighted=weighted-sum+length*value;sum+=value-ring[head];ring[head]=value;}
      head=(head+1)%length;
      // Periodic exact rebase bounds numerical drift; amortized O(1).
      if(count==length&&head==0){sum=weighted=0;for(int k=0;k<length;k++){sum+=ring[k];weighted+=(k+1)*ring[k];}}
      if(count<length)return false;
      out=weighted/((double)length*(length+1)/2);return true;
   }
};
class McRollingHma
{
   McRollingWma half,full,root;
public:
   void Reset(int period){half.Reset(MathMax(1,period/2));full.Reset(period);root.Reset(MathMax(1,(int)MathRound(MathSqrt((double)period))));}
   bool Push(double value,double &out)
   {double a,b;bool ha=half.Push(value,a),hb=full.Push(value,b);out=0;if(!ha||!hb)return false;return root.Push(2*a-b,out);}
};
class McWilderAtr
{
   int length,count;double sum,value,previous;
public:
   void Reset(int period){length=period;count=0;sum=value=previous=0;}
   bool Push(const MqlRates &bar,double &out)
   {
      double tr=bar.high-bar.low;
      if(count>0)tr=MathMax(tr,MathMax(MathAbs(bar.high-previous),MathAbs(bar.low-previous)));
      previous=bar.close;count++;
      if(count<=length){sum+=tr;if(count==length)value=sum/length;}else value=(value*(length-1)+tr)/length;
      out=value;return count>=length;
   }
};
#include "MaTrendFollowCore.mqh"
#include "LabEntryLogic.mqh"
class McPineKernel
{
   LabRuleStream lab;
   McTrendFollow trender;
   double trenderTick;
   MA_CROSS_SIGNAL_MODE mode;MA_CROSS_PAIR pair;
   int count,fastLen,mediumLen,state,lastBelow,lastAbove,trend;
   double fast,medium,prevA,prevB,previousClose,haOpen,haClose,pacC,pacU,pacL;
   double center,tUp,tDn,upper,lower,slopeHi,slopeLo,previousUpper,previousLower;
   bool havePair,haveCenter,haveBands,haveUpper,haveLower,hadUpper,hadLower;
   MqlRates history[49];McRollingHma slow;McWilderAtr atr;
   bool Pivot(int width,bool high,double &price)
   {
      if(count<2*width)return false;
      int pivot=count-width;price=high?history[pivot%49].high:history[pivot%49].low;
      for(int k=count-2*width;k<=count;k++)
      {
         if(k==pivot)continue;
         double x=high?history[k%49].high:history[k%49].low;
         // Right-hand ties disqualify the older extremum.
         if(high?(k<pivot?x>price:x>=price):(k<pivot?x<price:x<=price))return false;
      }
      return true;
   }
public:
   void Reset(MA_CROSS_SIGNAL_MODE m,MA_CROSS_PAIR p,int f,int med,int s)
   {
      lab.Reset(g_labEngine);trender.Reset();
      trenderTick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      mode=m;pair=p;fastLen=m==MA_CROSS_EMA_50_200?50:MathMax(1,f);mediumLen=m==MA_CROSS_EMA_50_200?200:MathMax(1,med);
      count=0;state=0;lastBelow=lastAbove=-100000000;trend=1;
      fast=medium=prevA=prevB=previousClose=haOpen=haClose=pacC=pacU=pacL=0;
      center=tUp=tDn=upper=lower=slopeHi=slopeLo=previousUpper=previousLower=0;
      havePair=haveCenter=haveBands=haveUpper=haveLower=hadUpper=hadLower=false;
      slow.Reset(MathMax(1,s));atr.Reset(m==MA_CROSS_TRENDLINE?24:10);
   }
   double MarkerPrice(){return mode==MA_CROSS_PIVOT_ST&&haveBands?(trend==1?tUp:tDn):0.0;}
   double LabAtr(){return lab.PolicyAtr();}int LabExits(){return lab.ExitMask();}
   int Push(const MqlRates &bar,double confirmedHtfHma=0)
   {
      if(mode==MA_CROSS_LAB_RULES)return lab.Push(bar);
      if(mode==MA_CROSS_TRENDER_IQ)return trender.Push(bar,trenderTick);
      history[count%49]=bar;int direction=0;
      if(mode==MA_CROSS_ORIGINAL_MTF||mode==MA_CROSS_EMA_50_200)
      {
         if(count==0){fast=medium=bar.close;}else {fast+=(bar.close-fast)*2/(fastLen+1.0);medium+=(bar.close-medium)*2/(mediumLen+1.0);}
         double s=0,a=fast,b=medium;bool ready=true;
         if(mode==MA_CROSS_ORIGINAL_MTF&&pair!=MA_CROSS_PAIR_FAST){ready=slow.Push(bar.close,s);b=s;if(pair==MA_CROSS_PAIR_SLOW)a=medium;}
         if(ready&&havePair)
         {
            direction=McCrossUp(a,b,prevA,prevB)?1:(McCrossDown(a,b,prevA,prevB)?-1:0);
            if(mode==MA_CROSS_ORIGINAL_MTF&&(confirmedHtfHma<=0||(direction>0&&bar.close<=confirmedHtfHma)||(direction<0&&bar.close>=confirmedHtfHma)))direction=0;
         }
         prevA=a;prevB=b;havePair=ready;
      }
      else if(mode==MA_CROSS_SCALP_PULLBACK)
      {
         double next=(bar.open+bar.high+bar.low+bar.close)/4;
         haOpen=count==0?(bar.open+bar.close)/2:(haOpen+haClose)/2;haClose=next;
         double hh=MathMax(bar.high,MathMax(haOpen,haClose)),ll=MathMin(bar.low,MathMin(haOpen,haClose));
         if(count==0){fast=medium=pacC=haClose;pacU=hh;pacL=ll;}
         else {fast+=(haClose-fast)*2/13;medium+=(haClose-medium)*2/201;pacC+=(haClose-pacC)*2/35;pacU+=(hh-pacU)*2/35;pacL+=(ll-pacL)*2/35;}
         if(haClose<pacC)lastBelow=count;if(haClose>pacC)lastAbove=count;
         int bias=fast>medium&&pacL>medium?1:(fast<medium&&pacU<medium?-1:0);
         bool buy=bias==1&&haOpen<pacU&&haClose>pacU&&count-lastBelow<=3,sell=bias==-1&&haOpen>pacL&&haClose<pacL&&count-lastAbove<=3;
         int old=state;
         if(old==1&&haClose<pacC)state=0;else if(old==-1&&haClose>pacC)state=0;else if(old==0&&buy)state=1;else if(old==0&&sell)state=-1;
         if(old==0&&state!=0)direction=state;
      }
      else
      {
         double av,ph,pl;bool ar=atr.Push(bar,av);int width=mode==MA_CROSS_TRENDLINE?24:2;
         bool hp=Pivot(width,true,ph),lp=Pivot(width,false,pl);
         if(mode==MA_CROSS_TRENDLINE)
         {
            if(hp&&ar){upper=ph;slopeHi=av/24*1.6;haveUpper=true;}else if(haveUpper)upper-=slopeHi;
            if(lp&&ar){lower=pl;slopeLo=av/24*1.6;haveLower=true;}else if(haveLower)lower+=slopeLo;
            double u=upper-slopeHi*24,l=lower+slopeLo*24;
            if(haveUpper&&hadUpper&&McCrossUp(bar.close,u,previousClose,previousUpper))direction=1;
            else if(haveLower&&hadLower&&McCrossDown(bar.close,l,previousClose,previousLower))direction=-1;
            previousUpper=u;previousLower=l;hadUpper=haveUpper;hadLower=haveLower;
         }
         else
         {
            if(hp||lp){double pp=hp?ph:pl;center=haveCenter?(center*2+pp)/3:pp;haveCenter=true;}
            if(haveCenter&&ar)
            {
               double up=center-3*av,dn=center+3*av;int old=trend;
               if(haveBands){if(bar.close>tDn)trend=1;else if(bar.close<tUp)trend=-1;up=previousClose>tUp?MathMax(up,tUp):up;dn=previousClose<tDn?MathMin(dn,tDn):dn;}
               tUp=up;tDn=dn;haveBands=true;if(old!=trend)direction=trend;
            }
         }
      }
      previousClose=bar.close;count++;return direction;
   }
};
double McFeedHtf(const MqlRates &h4[],int &index,datetime available,McRollingHma &hma,double &value)
{
   // Use only a completed HTF candle, never its future final close.
   while(index<ArraySize(h4)&&h4[index].time+PeriodSeconds(PERIOD_H4)<=available){hma.Push(h4[index].close,value);index++;}
   return value;
}
#endif
