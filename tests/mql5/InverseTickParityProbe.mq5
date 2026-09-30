#property strict

input datetime InpFirstTick=D'2026.09.21 00:00';
input int InpTickDays=5;
input int InpEntryDays=4;
input int InpSampleMinutes=15;
input int InpHoldHours=24;
input int InpCoverageToleranceMinutes=5;
input double InpStop1Pips=3.0;
input double InpStop2Pips=10.0;
input double InpStop3Pips=15.0;
input double InpStop4Pips=20.0;
input double InpStop5Pips=30.0;
input double InpStop6Pips=50.0;

void OnStart()
{
   if(InpTickDays<2||InpEntryDays<1||InpEntryDays>=InpTickDays
      ||InpSampleMinutes<1||InpHoldHours<1||InpHoldHours>24*InpTickDays
      ||InpCoverageToleranceMinutes<0)return;
   datetime begin=InpFirstTick,end=begin+InpTickDays*86400;
   MqlTick ticks[];
   int copied=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)begin*1000,(ulong)end*1000-1);
   int out=FileOpen("InverseTickParityProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"entry_time","source_dir","stop_pips","spread_pips","spread_pct","normal","inverse","paired","normal_exit","inverse_exit","forced_normal","forced_inverse","forced_paired","last_tick_msc");
   if(copied<=0)
   {
      FileWrite(out,"DATA",GetLastError(),copied);
      FileClose(out);
      return;
   }
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pip=(digits==3||digits==5)?10.0*point:point;
   double stops[6]={InpStop1Pips,InpStop2Pips,InpStop3Pips,InpStop4Pips,InpStop5Pips,InpStop6Pips};
   long nextSample=(long)begin*1000;
   int sampled=0;
   for(int i=0;i<copied&&ticks[i].time<begin+InpEntryDays*86400;i++)
   {
      if(ticks[i].time_msc<nextSample||ticks[i].bid<=0||ticks[i].ask<=ticks[i].bid)continue;
      nextSample=ticks[i].time_msc+(long)InpSampleMinutes*60*1000;
      sampled++;
      double spread=ticks[i].ask-ticks[i].bid;
      for(int k=0;k<6;k++)for(int direction=-1;direction<=1;direction+=2)
      {
         if(!MathIsValidNumber(stops[k])||stops[k]<=0.0)continue;
         double distance=stops[k]*pip;
         double normalEntry=direction>0?ticks[i].ask:ticks[i].bid;
         double inverseEntry=direction>0?ticks[i].bid:ticks[i].ask;
         double normalSl=normalEntry-direction*distance;
         double normalTp=normalEntry+direction*distance;
         double inverseSl=inverseEntry+direction*distance;
         double inverseTp=inverseEntry-direction*distance;
         int normal=0,inverse=0;
         long normalExit=0,inverseExit=0;
         long deadline=ticks[i].time_msc+(long)InpHoldHours*60*60*1000;
         double lastBid=ticks[i].bid,lastAsk=ticks[i].ask;
         long lastMs=ticks[i].time_msc;
         for(int j=i+1;j<copied&&ticks[j].time_msc<=deadline;j++)
         {
            double bid=ticks[j].bid,ask=ticks[j].ask;
            if(bid<=0||ask<bid)continue;
            lastBid=bid;lastAsk=ask;
            lastMs=ticks[j].time_msc;
            if(normal==0)
            {
               double normalClose=direction>0?bid:ask;
               if(direction>0?normalClose<=normalSl:normalClose>=normalSl)
               {normal=-1;normalExit=ticks[j].time_msc;}
               else if(direction>0?normalClose>=normalTp:normalClose<=normalTp)
               {normal=1;normalExit=ticks[j].time_msc;}
            }
            if(inverse==0)
            {
               double inverseClose=direction>0?ask:bid;
               if(direction>0?inverseClose>=inverseSl:inverseClose<=inverseSl)
               {inverse=-1;inverseExit=ticks[j].time_msc;}
               else if(direction>0?inverseClose<=inverseTp:inverseClose>=inverseTp)
               {inverse=1;inverseExit=ticks[j].time_msc;}
            }
            if(normal!=0&&inverse!=0)break;
         }
         int paired=(normal!=0&&inverse!=0?(normal==-inverse?1:0):-1);
         int forcedNormal=normal,forcedInverse=inverse;
         if(forcedNormal==0&&lastMs>=deadline-(long)InpCoverageToleranceMinutes*60*1000)
         {
            double pnl=direction>0?lastBid-normalEntry:normalEntry-lastAsk;
            forcedNormal=MathAbs(pnl)<point*0.5?0:(pnl>0?1:-1);
         }
         if(forcedInverse==0&&lastMs>=deadline-(long)InpCoverageToleranceMinutes*60*1000)
         {
            double pnl=direction>0?inverseEntry-lastAsk:lastBid-inverseEntry;
            forcedInverse=MathAbs(pnl)<point*0.5?0:(pnl>0?1:-1);
         }
         int forcedPaired=(forcedNormal!=0&&forcedInverse!=0?(forcedNormal==-forcedInverse?1:0):-1);
         FileWrite(out,TimeToString(ticks[i].time,TIME_DATE|TIME_SECONDS),direction,DoubleToString(stops[k],1),
            DoubleToString(spread/pip,3),DoubleToString(spread/distance*100.0,3),normal,inverse,paired,
            (long)normalExit,(long)inverseExit,forcedNormal,forcedInverse,forcedPaired,lastMs);
      }
      if(sampled%25==0)FileFlush(out);
   }
   FileClose(out);
   Print("INVERSE_TICK_PARITY samples=",sampled," ticks=",copied);
}
