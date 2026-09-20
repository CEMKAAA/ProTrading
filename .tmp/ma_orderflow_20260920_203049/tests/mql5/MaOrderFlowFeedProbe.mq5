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
      // Exercise the real indicator mailbox while retaining EA/script responsiveness.
      ulong begin=GetTickCount64(),worst=0;int state=0,polls=0;string error="";
      while(state==0&&GetTickCount64()-begin<38000)
      {
         ulong start=GetTickCount64();state=McOfPrepare(_Symbol,PERIOD_M5,r[count-2].time,true,error);
         worst=MathMax(worst,GetTickCount64()-start);polls++;if(state==0)Sleep(100);
      }
      report+="ASYNC state="+(string)state+" polls="+(string)polls+" max_call_ms="+(string)worst
         +" elapsed_ms="+(string)(GetTickCount64()-begin)+" reason="+error+"\n";
   }
   McOfRelease();
   int f=FileOpen("20260920_203049_MaOrderFlowFeedProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,report);FileClose(f);}Print(report);
}
