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
      if(state==1)
      {
         MqlRates context[];ArraySetAsSeries(context,false);
         int n=CopyRates(_Symbol,PERIOD_M5,r[count-2].time,g_mcOf.lookback+1,context);
         if(n==g_mcOf.lookback+1)
         {
            MqlTick tape[];ResetLastError();
            int nt=CopyTicksRange(_Symbol,tape,COPY_TICKS_INFO,(ulong)context[0].time*1000,(ulong)(context[n-1].time+300)*1000-1);
            int err=GetLastError();McOfSnapshot direct;
            bool valid=err==0&&McOfCalculate(tape,context,300,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),g_mcOf,direct);
            int slot=-1;string key=McOfCacheKey(_Symbol,PERIOD_M5,r[count-2].time);
            for(int j=0;j<256;j++)if(g_mcOfCache[j].key==key){slot=j;break;}
            bool same=valid&&slot>=0;
            if(same)
            {
               McOfSnapshot remote=g_mcOfCache[slot].snapshot;
               same=direct.poc==remote.poc&&direct.val==remote.val&&direct.vah==remote.vah
                  &&direct.delta==remote.delta&&direct.activity==remote.activity&&direct.profileCount==remote.profileCount;
            }
            report+="WORKER_VS_DIRECT ticks="+(string)nt+" error="+(string)err+" valid="+(string)valid+" exact_match="+(string)same+"\n";
            string reason="",detail="";
            bool allowed=McOfFilter(_Symbol,PERIOD_M5,r[count-2].time,1,reason,detail);
            report+="DECISION buy="+(string)allowed+" "+reason+" "+detail+"\n";
         }
      }
   }
   McOfRelease();
   int f=FileOpen("20260920_203224_MaOrderFlowFeedProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,report);FileClose(f);}Print(report);
}
