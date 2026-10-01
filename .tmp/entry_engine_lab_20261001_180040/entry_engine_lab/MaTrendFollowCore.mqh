// Port of Trender [IQ] by Trading-IQ, TrendFollow.pine.
// This Source Code Form is subject to the Mozilla Public License, v. 2.0.
// If a copy was not distributed, obtain one at https://mozilla.org/MPL/2.0/.
#ifndef MA_TREND_FOLLOW_CORE_MQH
#define MA_TREND_FOLLOW_CORE_MQH
// Closed bars, chronological, same starting bar as Pine required for parity.
// Default configuration: Balanced / Steady / Close / log geometry.
class McTrendFollow
{
   double level,slope,p00,p01,p11,noise,base,positive,negative;
   double rail,velocity,previousClose;
   int cooldown,bars,leg;
   bool seeded,railReady,trendOn;
public:
   void Reset()
   {
      level=slope=p00=p01=p11=base=positive=negative=0;
      rail=velocity=previousClose=0;noise=1;cooldown=bars=leg=0;
      seeded=railReady=trendOn=false;
   }
   int State(){return leg;}
   double Rail(){return MathExp(rail);}
   int Push(const MqlRates &b,double tickSize)
   {
      double observation=MathLog(MathMax(b.close,tickSize));
      double hi=MathLog(MathMax(b.high,tickSize)),lo=MathLog(MathMax(b.low,tickSize));
      if(!seeded)
      {
         level=observation;
         double prev=MathLog(MathMax(bars>0?previousClose:b.open,tickSize));
         double tr=MathMax(hi-lo,MathMax(MathAbs(hi-prev),MathAbs(lo-prev)));
         if(tr>0){base=MathMax(0.25*tr*tr,1e-12);p00=10*base;p11=0.1*base;seeded=true;}
      }
      double deviation=0,conviction=0;bool up=false,down=false;
      if(seeded)
      {
         double measurement=base*noise,process=0.05*measurement;
         double predicted=level+slope;
         double a=p00+2*p01+p11+process/3.0,bv=p01+p11+process*0.5,c=p11+process;
         double variance=a+measurement,innovation=observation-predicted;
         deviation=MathSqrt(MathMax(variance,1e-18));
         double z=innovation/deviation,weight=MathAbs(z)<=2.5?1.0:2.5/MathAbs(z);
         double robust=innovation*weight,k0=a/variance,k1=bv/variance;
         level=predicted+k0*robust;slope=slope+k1*robust;
         p00=a-k0*a;p01=bv-k0*bv;p11=c-k1*bv;
         positive=MathMax(0,positive+z-0.5);negative=MathMax(0,negative-z-0.5);
         up=positive>6;down=negative>6;
         if(up||down){cooldown=10;positive=negative=0;}
         double gain=cooldown>0?0.15:0.02;cooldown=MathMax(0,cooldown-1);
         if(bars>10&&variance>0)
            noise=MathMax(0.25,MathMin(16,noise*MathExp(gain*(MathMin(innovation*innovation/variance,9.0)-1.0))));
         conviction=MathAbs(slope)/MathSqrt(MathMax(p11,1e-18));
      }
      int old=leg;
      if(!railReady){rail=level;railReady=true;}
      double band=1.05*deviation,freeze=0.15*band,error=level-rail;
      if(trendOn&&conviction<0.35)trendOn=false;
      else if(!trendOn&&conviction>1.0)trendOn=true;
      double speed=0.20*deviation;
      if(leg==0)
      {
         if(error>band||(trendOn&&error>freeze)){leg=1;velocity=speed;}
         else if(error< -band||(trendOn&&error< -freeze)){leg=-1;velocity=speed;}
      }
      if(leg==1&&error< -band&&down){leg=-1;velocity=speed;}
      else if(leg==-1&&error>band&&up){leg=1;velocity=speed;}
      if(leg==1)
      {
         rail+=MathMin(velocity,MathMax(error,0));
         if(level-rail<=freeze&&!trendOn)leg=0;
      }
      else if(leg==-1)
      {
         rail-=MathMin(velocity,MathMax(-error,0));
         if(rail-level<=freeze&&!trendOn)leg=0;
      }
      previousClose=b.close;bars++;
      return bars>1&&leg!=0&&leg!=old?leg:0;
   }
};
#endif
