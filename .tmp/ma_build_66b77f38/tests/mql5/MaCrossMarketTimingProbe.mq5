#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossSignalCore.mqh"
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossAuditCache.mqh"
void OnStart()
{
   string names[3]={"JP225m","XAUUSDm","USTECm"};
   int f=FileOpen("2ca905e3_MaCrossMarketTiming.jsonl",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(f==INVALID_HANDLE)return;
   for(int s=0;s<3;s++)
   {
      string name=names[s];bool selected=SymbolSelect(name,true);MqlRates r[];
      ulong begin=GetTickCount64();int n=-1;
      for(int attempt=0;attempt<10&&selected;attempt++)
      {
         n=CopyRates(name,PERIOD_M5,1,100000,r);
         if(n>0)break;
         Sleep(500);
      }
      ulong copyMs=GetTickCount64()-begin;
      string json="{\"symbol\":\""+name+"\",\"bars\":"+(string)n+",\"copy_ms\":"+(string)copyMs;
      if(n>0)
      {
         McPineKernel k;k.Reset(MA_CROSS_PIVOT_ST,MA_CROSS_PAIR_FAST,9,27,200);
         ulong start=GetMicrosecondCount();int total=0;
         for(int i=0;i<n;i++)if(k.Push(r[i])!=0)total++;
         json+=",\"kernel_ms\":"+DoubleToString((GetMicrosecondCount()-start)/1000.0,3)+",\"signals\":"+(string)total;
         MaCrossSignal sig;start=GetMicrosecondCount();
         MaCrossComputeSignal(name,PERIOD_M5,MA_CROSS_PIVOT_ST,MA_CROSS_PAIR_FAST,9,27,200,sig);
         if(sig.barTime>0)
         {
            json+=",\"live_ready\":true,\"live_cold_ms\":"+DoubleToString((GetMicrosecondCount()-start)/1000.0,3);
            start=GetMicrosecondCount();
            for(int i=0;i<10000;i++)MaCrossComputeSignal(name,PERIOD_M5,MA_CROSS_PIVOT_ST,MA_CROSS_PAIR_FAST,9,27,200,sig);
            json+=",\"live_10000_same_bar_calls_ms\":"+DoubleToString((GetMicrosecondCount()-start)/1000.0,3);
         }
         else json+=",\"live_ready\":false,\"live_status\":\"series_not_synchronized\"";
      }
      json+="}";FileWriteString(f,json+"\r\n");FileFlush(f);Print("MA_MARKET_TIMING ",json);
   }
   FileClose(f);
}
