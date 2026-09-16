#property strict
#include "../../IndicatorCodeExamples/MaCrossOver_Core.mqh"
double DirectWma(const MqlRates &r[],int last,int len)
{
   if(last<len-1)return EMPTY_VALUE;double sum=0;
   for(int k=0;k<len;k++)sum+=(k+1)*r[last-len+1+k].close;
   return sum/((double)len*(len+1)/2);
}
double DirectHma(const MqlRates &r[],int last,int len)
{
   int root=MathMax(1,(int)MathRound(MathSqrt(len)));if(last<len+root-2)return EMPTY_VALUE;
   double sum=0;for(int k=0;k<root;k++){int at=last-root+1+k;sum+=(k+1)*(2*DirectWma(r,at,len/2)-DirectWma(r,at,len));}
   return sum/((double)root*(root+1)/2);
}
void OnStart()
{
   string symbols[]={"JP225m","USDJPYm","BTCUSDm"};ENUM_TIMEFRAMES frames[]={PERIOD_M5,PERIOD_M15,PERIOD_H1};
   int file=FileOpen("MaCrossOverSignalProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
   if(file==INVALID_HANDLE)return;
   FileWrite(file,"symbol","tf","from","to","chart_bars","raw_cross","htf_pass","other_filter_pass","reference_cross","reference_htf_pass","cross_mismatch","htf_mismatch","m1_bars","zero_spread_m1","status");
   for(int symbol=0;symbol<ArraySize(symbols);symbol++)for(int frame=0;frame<ArraySize(frames);frame++)
   {
      string name=symbols[symbol];ENUM_TIMEFRAMES tf=frames[frame];SymbolSelect(name,true);
      datetime now=TimeCurrent(),since=now-14*86400,from=since-45*86400;
      MqlRates r[],higher[],minutes[];int n=0,h=0;int hf=iMA(name,tf,9,0,MODE_EMA,PRICE_CLOSE),hm=iMA(name,tf,27,0,MODE_EMA,PRICE_CLOSE);
      double referenceFast[],referenceMedium[];
      for(int attempt=0;attempt<40;attempt++)
      {
         n=CopyRates(name,tf,from,now,r);h=CopyRates(name,PERIOD_H4,(datetime)(since-450*14400),now,higher);
         if(n>1000&&h>250&&CopyBuffer(hf,0,from,now,referenceFast)==n&&CopyBuffer(hm,0,from,now,referenceMedium)==n)break;
         Sleep(100);
      }
      int raw=0,pass=0,accepted=0,ref=0,refPass=0,mismatch=0,htfMismatch=0;
      string status="OK";
      if(n<=1000||h<=250||ArraySize(referenceFast)!=n||ArraySize(referenceMedium)!=n)status="INCOMPLETE_HISTORY";
      else
      {
         MaConfig c;MaDefaults(c);MaSeries s;MaCalculate(r,c,s);double close[],hma[];ArrayResize(close,h);
         for(int j=0;j<h;j++)close[j]=higher[j].close;MaHma(close,200,hma);
         for(int i=1;i<n;i++)
         {
            datetime available=r[i].time+PeriodSeconds(tf);if(r[i].time<since||available>now)continue;
            int d=referenceFast[i]>referenceMedium[i]&&referenceFast[i-1]<=referenceMedium[i-1]?1:
               (referenceFast[i]<referenceMedium[i]&&referenceFast[i-1]>=referenceMedium[i-1]?-1:0);
            if(d!=0)ref++;if(s.direction[i]!=0)raw++;if(d!=s.direction[i])mismatch++;
            int j=MaLastClosed(higher,available,14400);double expected=j>=0?DirectHma(higher,j,200):EMPTY_VALUE;
            bool a=s.direction[i]!=0&&j>=0&&MaValid(hma[j])&&s.direction[i]*(r[i].close-hma[j])>0;
            bool b=d!=0&&MaValid(expected)&&d*(r[i].close-expected)>0;
            if(a)pass++;if(b)refPass++;if(a!=b)htfMismatch++;
            int dir=0;string reason;if(MaFilter(r,i,s,c,higher,hma,PeriodSeconds(tf),0,dir,reason))accepted++;
         }
         if(mismatch>0||htfMismatch>0)status="MISMATCH";
      }
      int m=CopyRates(name,PERIOD_M1,since,now,minutes),zero=0;for(int i=0;i<m;i++)if(minutes[i].spread<=0)zero++;
      FileWrite(file,name,EnumToString(tf),TimeToString(since),TimeToString(now),n,raw,pass,accepted,ref,refPass,mismatch,htfMismatch,m,zero,status);
      Print("MA_SIGNAL_PROBE ",name," ",EnumToString(tf)," raw=",raw," pass=",pass," reference=",ref," mismatches=",mismatch+htfMismatch," ",status);
      if(hf!=INVALID_HANDLE)IndicatorRelease(hf);if(hm!=INVALID_HANDLE)IndicatorRelease(hm);
   }
   FileClose(file);
}
