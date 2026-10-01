#ifndef LAB_PARAMETERIZED_FEATURES_MQH
#define LAB_PARAMETERIZED_FEATURES_MQH
// One causal provider per distinct (indicator, period), shared by both sides.
class LabOperandStream
{
   int kind,period,count,head;double ring[],sum,ema,value,previous,oldClose,oldHigh,oldLow;
   LabAverage up,down,tr,plus,minus,adx;McRollingHma hma;
public:
   int Kind(){return kind;}int Period(){return period;}double Current(){return value;}double Previous(){return previous;}
   void Reset(int feature,int n)
   {kind=feature;period=n;count=head=0;sum=ema=oldClose=oldHigh=oldLow=0;value=previous=EMPTY_VALUE;
      ArrayResize(ring,n);ArrayInitialize(ring,0);up.Reset(n);down.Reset(n);tr.Reset(n);plus.Reset(n);minus.Reset(n);adx.Reset(n);hma.Reset(n);}
   void Push(const MqlRates &b)
   {
      previous=value;value=EMPTY_VALUE;double x,y,z,dx;
      if(kind==32){ema=count==0?b.close:ema+(b.close-ema)*2/(period+1.0);if(count+1>=period)value=ema;}
      if(kind==33){sum+=b.close-ring[head];ring[head]=b.close;head=(head+1)%period;if(count+1>=period)value=sum/period;}
      if(kind==34&&count>0){up.Push(MathMax(0,b.close-oldClose),x);down.Push(MathMax(0,oldClose-b.close),y);if(x!=EMPTY_VALUE&&y!=EMPTY_VALUE)value=y==0?(x==0?50:100):100-100/(1+x/y);}
      if(kind==35){double range=b.high-b.low;if(count>0)range=MathMax(range,MathMax(MathAbs(b.high-oldClose),MathAbs(b.low-oldClose)));tr.Push(range,value);}
      if(kind==36&&count>0){double p=b.high-oldHigh,m=oldLow-b.low;plus.Push(p>m&&p>0?p:0,x);minus.Push(m>p&&m>0?m:0,y);
         if(x!=EMPTY_VALUE&&y!=EMPTY_VALUE){dx=x+y>0?100*MathAbs(x-y)/(x+y):0;adx.Push(dx,z);value=z;}}
      if(kind==37&&!hma.Push(b.close,value))value=EMPTY_VALUE;
      oldClose=b.close;oldHigh=b.high;oldLow=b.low;count++;
   }
};
#endif
