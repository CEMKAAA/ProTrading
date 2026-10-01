class McPineKernelBaseline
{
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
      trender.Reset();
      trenderTick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      mode=m;pair=p;fastLen=m==MA_CROSS_EMA_50_200?50:MathMax(1,f);mediumLen=m==MA_CROSS_EMA_50_200?200:MathMax(1,med);
      count=0;state=0;lastBelow=lastAbove=-100000000;trend=1;
      fast=medium=prevA=prevB=previousClose=haOpen=haClose=pacC=pacU=pacL=0;
      center=tUp=tDn=upper=lower=slopeHi=slopeLo=previousUpper=previousLower=0;
      havePair=haveCenter=haveBands=haveUpper=haveLower=hadUpper=hadLower=false;
      slow.Reset(MathMax(1,s));atr.Reset(m==MA_CROSS_TRENDLINE?24:10);
   }
   double MarkerPrice(){return mode==MA_CROSS_PIVOT_ST&&haveBands?(trend==1?tUp:tDn):0.0;}
   int Push(const MqlRates &bar,double confirmedHtfHma=0)
   {
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