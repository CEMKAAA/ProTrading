#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlow.mqh"
// Read-only diagnostics. No order, position, bridge, or account mutation APIs.
void OnStart()
{
   McOfInit();g_mcOf.mode=MC_OF_EITHER;
   MqlRates r[];ArraySetAsSeries(r,false);int count=0;
   for(int i=0;i<15&&count<30;i++){count=CopyRates(_Symbol,PERIOD_M5,1,30,r);if(count<30)Sleep(500);}
   string report="symbol="+_Symbol+" bars="+(string)count+"\n";
   if(count>=30)
   {
      for(int i=count-3;i<count;i++)
      {
         string reason="",detail="";ulong start=GetTickCount64();
         bool allowed=McOfFilter(_Symbol,PERIOD_M5,r[i].time,1,reason,detail);
         report+="bar="+(string)r[i].time+" allowed="+(string)allowed+" ms="+(string)(GetTickCount64()-start)
            +" reason="+reason+" detail="+detail+"\n";
      }
      // Offline diagnostic only: inspect local data separately; never bypass
      // the production adapter's synchronization gate or produce orders.
      MqlRates context[];ArraySetAsSeries(context,false);
      int n=CopyRates(_Symbol,PERIOD_M5,r[count-2].time,g_mcOf.lookback+1,context);
      if(n==g_mcOf.lookback+1)
      {
         MqlTick ticks[];ResetLastError();ulong start=GetTickCount64();
         int nt=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)context[0].time*1000,(ulong)(context[n-1].time+300)*1000-1);
         int err=GetLastError();McOfSnapshot s;
         bool valid=err==0&&McOfCalculate(ticks,context,300,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),g_mcOf,s);
         report+="OFFLINE_DIAGNOSTIC_ONLY ticks="+(string)nt+" error="+(string)err+" valid="+(string)valid
            +" ms="+(string)(GetTickCount64()-start)+" reason="+s.reason+"\n";
      }
   }
   int f=FileOpen("20260920_201337_MaOrderFlowFeedProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,report);FileClose(f);}Print(report);
}
