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
   }
   int f=FileOpen("20260920_201228_MaOrderFlowFeedProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,report);FileClose(f);}Print(report);
}
