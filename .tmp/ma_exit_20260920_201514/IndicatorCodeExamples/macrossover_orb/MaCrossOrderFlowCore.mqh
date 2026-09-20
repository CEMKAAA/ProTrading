#ifndef MACROSS_ORDER_FLOW_CORE_MQH
#define MACROSS_ORDER_FLOW_CORE_MQH
// Original implementation. Quote activity is NOT executed/aggressor volume.
enum MC_OF_MODE { MC_OF_OFF=0, MC_OF_BREAKOUT=1, MC_OF_REJECTION=2, MC_OF_EITHER=3 };
struct McOfConfig
{
   int mode,lookback,bins;
   double valueArea,minActivity,minDelta;
};
struct McOfSnapshot
{
   bool valid;
   double poc,val,vah,profileCount,buy,sell,neutral,activity,delta;
   string reason;
};
bool McOfConfigValid(const McOfConfig &c)
{
   return c.mode>=0&&c.mode<=3&&c.lookback>=2&&c.lookback<=128&&c.bins>=4&&c.bins<=256
      &&MathIsValidNumber(c.valueArea)&&c.valueArea>=0.1&&c.valueArea<=1
      &&MathIsValidNumber(c.minActivity)&&c.minActivity>=0&&c.minActivity<=100
      &&MathIsValidNumber(c.minDelta)&&c.minDelta>=0&&c.minDelta<=1;
}
string McOfConfigText(const McOfConfig &c)
{
   return (string)c.mode+","+(string)c.lookback+","+(string)c.bins+","+DoubleToString(c.valueArea,8)
      +","+DoubleToString(c.minActivity,8)+","+DoubleToString(c.minDelta,8);
}
// Strict, canonical serialization prevents malformed presets silently becoming OFF.
bool McOfConfigRead(string text,McOfConfig &c)
{
   string v[];if(StringSplit(text,',',v)!=6)return false;
   McOfConfig n;n.mode=(int)StringToInteger(v[0]);n.lookback=(int)StringToInteger(v[1]);n.bins=(int)StringToInteger(v[2]);
   n.valueArea=StringToDouble(v[3]);n.minActivity=StringToDouble(v[4]);n.minDelta=StringToDouble(v[5]);
   if(!McOfConfigValid(n)||McOfConfigText(n)!=text)return false;c=n;return true;
}
// Ties: lower POC; symmetric expansion on equal adjacent volume. Edge prices,
// not bin centers, define VAL/VAH. Each observation belongs to exactly one bin.
bool McOfValueArea(const double &hist[],double low,double step,double fraction,McOfSnapshot &s)
{
   int n=ArraySize(hist),poc=0;double total=0;
   if(n<1||step<=0||fraction<=0||fraction>1)return false;
   for(int i=0;i<n;i++){if(!MathIsValidNumber(hist[i])||hist[i]<0)return false;total+=hist[i];if(hist[i]>hist[poc])poc=i;}
   if(total<=0)return false;
   int left=poc,right=poc;double sum=hist[poc];
   while(sum<total*fraction&&(left>0||right<n-1))
   {
      double a=left>0?hist[left-1]:-1,b=right<n-1?hist[right+1]:-1;
      if(a>=b&&left>0){left--;sum+=hist[left];}
      if(b>=a&&right<n-1){right++;sum+=hist[right];}
   }
   s.poc=low+(poc+0.5)*step;s.val=low+left*step;s.vah=low+(right+1)*step;s.profileCount=total;
   return true;
}
// Pure calculation: no terminal, files, clock, trading or future data access.
// rates[] = N reference candles + ONE completed signal candle, chronological.
bool McOfCalculate(const MqlTick &ticks[],const MqlRates &rates[],int seconds,double tickSize,
                   const McOfConfig &c,McOfSnapshot &s)
{
   ZeroMemory(s);s.reason="OF_DATA_INVALID";
   int n=ArraySize(rates),nt=ArraySize(ticks);
   if(!McOfConfigValid(c)||n!=c.lookback+1||nt<1||seconds<=0||tickSize<=0)return false;
   double low=DBL_MAX,high=-DBL_MAX;
   for(int b=0;b<n;b++)
   {
      if(rates[b].tick_volume<=0||!MathIsValidNumber(rates[b].high)||!MathIsValidNumber(rates[b].low)
         ||!MathIsValidNumber(rates[b].close)||rates[b].close<rates[b].low||rates[b].close>rates[b].high
         ||rates[b].high<rates[b].low||rates[b].low<=0
         ||(b>0&&rates[b].time<rates[b-1].time+seconds))return false;
      if(b<n-1){low=MathMin(low,rates[b].low);high=MathMax(high,rates[b].high);}
   }
   double step=MathMax(tickSize,(high-low)/c.bins);
   double hist[];ArrayResize(hist,c.bins);ArrayInitialize(hist,0);
   long counts[];ArrayResize(counts,n);ArrayInitialize(counts,0);
   int bar=0;double previous=0;long lastTime=-1;
   for(int i=0;i<nt;i++)
   {
      long t=ticks[i].time_msc;
      if(t<lastTime){s.reason="OF_DATA_UNSORTED";return false;}lastTime=t;
      if(t<(long)rates[0].time*1000)continue;
      if(t>=(long)(rates[n-1].time+seconds)*1000)break;
      // Bid-update count matches bid-candle construction; ask-only changes
      // must not be mislabeled as trades or directional volume.
      if((ticks[i].flags&TICK_FLAG_BID)==0)continue;
      double price=ticks[i].bid;if(!MathIsValidNumber(price)||price<=0)return false;
      while(bar<n-1&&t>=(long)rates[bar+1].time*1000)bar++;
      if(t>=(long)(rates[bar].time+seconds)*1000){s.reason="OF_DATA_BAR_GAP";return false;}
      if(price<rates[bar].low-tickSize*0.51||price>rates[bar].high+tickSize*0.51)
         {s.reason="OF_DATA_PRICE_MISMATCH";return false;}
      counts[bar]++;
      if(bar<n-1)
      {
         int bin=(int)MathFloor((price-low)/step);bin=MathMax(0,MathMin(c.bins-1,bin));hist[bin]++;
      }
      else
      {
         if(previous<=0||price==previous)s.neutral++;
         else if(price>previous)s.buy++;else s.sell++;
      }
      previous=price;
   }
   // No fabricated OHLC fallback. Missing history OR incompatible broker tick
   // volume semantics invalidate the snapshot rather than biasing its delta.
   for(int b=0;b<n;b++)if(counts[b]!=rates[b].tick_volume)
      {s.reason="OF_DATA_COVERAGE bar="+(string)rates[b].time+" bid="+(string)counts[b]+" expected="+(string)rates[b].tick_volume;return false;}
   if(!McOfValueArea(hist,low,step,c.valueArea,s))return false;
   double signal=s.buy+s.sell+s.neutral;
   s.activity=signal/(s.profileCount/c.lookback);
   s.delta=signal>0?(s.buy-s.sell)/signal:0;
   s.valid=true;s.reason="OF_QUOTE_PROXY";return true;
}
bool McOfAllows(const McOfConfig &c,const McOfSnapshot &s,const MqlRates &signal,int direction)
{
   if(c.mode==MC_OF_OFF)return true;
   if(!McOfConfigValid(c)||!s.valid||(direction!=1&&direction!=-1)
      ||!MathIsValidNumber(s.activity)||!MathIsValidNumber(s.delta)
      ||s.activity<c.minActivity||direction*s.delta<c.minDelta)return false;
   bool breakout=direction>0?signal.close>s.vah:signal.close<s.val;
   bool rejection=direction>0?(signal.low<s.val&&signal.close>=s.val&&signal.close<=s.vah)
                             :(signal.high>s.vah&&signal.close<=s.vah&&signal.close>=s.val);
   return c.mode==MC_OF_BREAKOUT?breakout:(c.mode==MC_OF_REJECTION?rejection:breakout||rejection);
}
#endif
