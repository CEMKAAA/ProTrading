#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossSignalCore.mqh"
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossAuditCache.mqh"
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("FAIL ",label);}}
double Wma(const MqlRates &r[],int at,int len)
{double s=0;for(int j=0;j<len;j++)s+=(j+1)*r[at-len+1+j].close;return s/(len*(len+1.0)/2);}
double Hma(const MqlRates &r[],int at,int len)
{int root=(int)MathRound(MathSqrt((double)len));double s=0;for(int j=0;j<root;j++)s+=(j+1)*(2*Wma(r,at-root+1+j,len/2)-Wma(r,at-root+1+j,len));return s/(root*(root+1.0)/2);}
void Fixture(MqlRates &r[],int n,int sec=300)
{
   ArrayResize(r,n);ZeroMemory(r);
   for(int i=0;i<n;i++)
   {
      r[i].time=D'2020.01.01'+i*sec;
      r[i].close=1000+40*MathSin(i*0.039)+12*MathSin(i*0.31)+0.001*i;
      r[i].open=i>0?r[i-1].close:r[i].close-1;
      r[i].high=MathMax(r[i].open,r[i].close)+1+(i%7)*0.17;
      r[i].low=MathMin(r[i].open,r[i].close)-1-(i%11)*0.13;
      r[i].tick_volume=100+i%29;
   }
}
void OnStart()
{
   const int n=12000;MqlRates r[],h[];Fixture(r,n);Fixture(h,400,14400);
   int f=FileOpen("2ca905e3_MaCrossPineDirections.txt",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   Check(f!=INVALID_HANDLE,"output opened");if(f==INVALID_HANDLE)return;
   for(int mode=0;mode<7;mode++)
   {
      MA_CROSS_SIGNAL_MODE actual=(MA_CROSS_SIGNAL_MODE)(mode<5?mode:0);
      MA_CROSS_PAIR pair=(MA_CROSS_PAIR)(mode<5?0:mode-4);
      McPineKernel kernel;kernel.Reset(actual,pair,9,27,200);
      McRollingHma hh;hh.Reset(200);double hv=0;int hi=0,total=0;
      for(int i=0;i<n;i++)
      {
         if(actual==MA_CROSS_ORIGINAL_MTF)McFeedHtf(h,hi,r[i].time+300,hh,hv);
         int d=kernel.Push(r[i],hv);if(d!=0)total++;
         FileWriteString(f,(string)mode+","+(string)i+","+(string)d+"\r\n");
         if(i%997==0)
         {
            int ref;MaCrossSignalAt(r,i,actual,pair,9,27,200,h,ref);
            Check(ref==d,"batch/stream mode="+(string)mode+" bar="+(string)i);
         }
      }
      Check(total>0,"mode generates events "+(string)mode);
      Print("MODE ",mode," signals=",total);
   }
   FileClose(f);
   McRollingHma hh;hh.Reset(200);
   for(int i=0;i<n;i++)
   {double value;bool valid=hh.Push(r[i].close,value);if(i>=212&&i%31==0)Check(valid&&MathAbs(value-Hma(r,i,200))<1e-7,"rolling HMA");}
   McWilderAtr atr;atr.Reset(10);double seed=0,expected=0;
   for(int i=0;i<n;i++)
   {
      double tr=i==0?r[i].high-r[i].low:MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-r[i-1].close),MathAbs(r[i].low-r[i-1].close)));
      if(i<10){seed+=tr;if(i==9)expected=seed/10;}else expected=(expected*9+tr)/10;
      double actual;bool ok=atr.Push(r[i],actual);
      Check(ok==(i>=9)&&MathAbs(actual-expected)<1e-10,"Wilder seed/recurrence");
   }
   // A future HTF shock must not affect signals before its close.
   int before,after;MaCrossSignalAt(r,9999,MA_CROSS_ORIGINAL_MTF,MA_CROSS_PAIR_FAST,9,27,200,h,before);
   for(int i=0;i<ArraySize(h);i++)if(h[i].time+14400>r[9999].time+300)h[i].close*=100;
   MaCrossSignalAt(r,9999,MA_CROSS_ORIGINAL_MTF,MA_CROSS_PAIR_FAST,9,27,200,h,after);
   Check(before==after,"future HTF unavailable");
   ArrayResize(g_maCrossAuditEvents,4);
   for(int i=0;i<4;i++){g_maCrossAuditEvents[i].signalTime=100+i*10;g_maCrossAuditEvents[i].direction=1;}
   string dir;datetime tm;double a,b,c,d,e;
   Check(MaCrossAuditNext(120,140,0,dir,tm,a,b,c,d,e)&&tm==120,"inclusive lower bound");
   Check(MaCrossAuditNext(120,140,120,dir,tm,a,b,c,d,e)&&tm==130,"strict after bound");
   int report=FileOpen("2ca905e3_MaCrossPineProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   string json="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+",\"benchmark\":[";
   for(int size=200000;size<=1000000;size+=800000)
   {
      Fixture(r,size);McPineKernel kernel;kernel.Reset(MA_CROSS_PIVOT_ST,MA_CROSS_PAIR_FAST,9,27,200);
      ulong start=GetMicrosecondCount();long events=0;
      for(int i=0;i<size;i++)if(kernel.Push(r[i])!=0)events++;
      double ms=(GetMicrosecondCount()-start)/1000.0;
      json+=(size>200000?",":"")+"{\"bars\":"+(string)size+",\"ms\":"+DoubleToString(ms,3)+",\"events\":"+(string)events+"}";
   }
   json+="]}";if(report!=INVALID_HANDLE){FileWriteString(report,json);FileClose(report);}
   Print("PINE_STREAM_PROBE ",json);
}
