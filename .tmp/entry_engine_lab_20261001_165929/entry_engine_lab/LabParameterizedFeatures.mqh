#ifndef LAB_PARAMETERIZED_FEATURES_MQH
#define LAB_PARAMETERIZED_FEATURES_MQH
// One causal provider per distinct (indicator, period), shared by both sides.
class LabOperandStream
{
   int kind,period,count,head,dhead,dtail;double ring[],sum,sumSq,ema,value,previous,oldClose,oldHigh,oldLow,deque[];int indices[];
   LabAverage up,down,tr,plus,minus,adx;McRollingHma hma;
public:
   int Kind(){return kind;}int Period(){return period;}double Current(){return value;}double Previous(){return previous;}
   void Reset(int feature,int n)
   {kind=feature;period=n;count=head=dhead=dtail=0;sum=sumSq=ema=oldClose=oldHigh=oldLow=0;value=previous=EMPTY_VALUE;
      ArrayResize(ring,n);ArrayInitialize(ring,0);ArrayResize(deque,n+1);ArrayResize(indices,n+1);
      up.Reset(n);down.Reset(n);tr.Reset(n);plus.Reset(n);minus.Reset(n);adx.Reset(n);hma.Reset(n);}
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
      if(kind>=38&&kind<=40){double old=ring[head];sum+=b.close-old;sumSq+=b.close*b.close-old*old;ring[head]=b.close;head=(head+1)%period;
         if(count+1>=period){double mean=sum/period,sd=MathSqrt(MathMax(0,sumSq/period-mean*mean));value=kind==40?mean:(kind==38?mean+1.5*sd:mean-1.5*sd);}}
      if(kind==41||kind==42){int size=period+1;while(dhead!=dtail&&indices[dhead]<count-period)dhead=(dhead+1)%size;
         if(count>=period&&dhead!=dtail)value=deque[dhead];double next=kind==41?b.high:b.low;
         while(dhead!=dtail){int back=(dtail+size-1)%size;if(kind==41?deque[back]>next:deque[back]<next)break;dtail=back;}
         deque[dtail]=next;indices[dtail]=count;dtail=(dtail+1)%size;}
      if(kind==43){double range=b.high-b.low;if(count>0)range=MathMax(range,MathMax(MathAbs(b.high-oldClose),MathAbs(b.low-oldClose)));tr.Push(range,z);
         if(z!=EMPTY_VALUE&&z>0)value=MathAbs(b.close-b.open)/z;}
      oldClose=b.close;oldHigh=b.high;oldLow=b.low;count++;
   }
};
#endif
