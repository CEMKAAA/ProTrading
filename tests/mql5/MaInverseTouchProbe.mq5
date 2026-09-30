#property strict
void OnStart()
{
   const double tp=1.13756,sl=1.13956;
   datetime from=D'2026.09.24 03:05:00',to=D'2026.09.24 07:50:00';
   int out=FileOpen("MaInverseTouchProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"symbol","ticks","min_bid","min_bid_at","min_ask","min_ask_at",
      "first_bid_tp","first_ask_tp","first_ask_sl","max_ask","max_ask_at","m1_low","m1_low_at");
   double minBid=DBL_MAX,minAsk=DBL_MAX,maxAsk=0,m1Low=DBL_MAX;
   datetime bidAt=0,askAt=0,maxAskAt=0,bidTpAt=0,askTpAt=0,askSlAt=0,m1At=0;
   long count=0;
   for(datetime cursor=from;cursor<to;cursor+=600)
   {
      datetime end=(datetime)MathMin((long)to,(long)cursor+600);
      MqlTick ticks[];
      int copied=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)cursor*1000,(ulong)end*1000-1);
      for(int i=0;i<copied;i++)
      {
         double bid=ticks[i].bid,ask=ticks[i].ask;
         if(bid<=0||ask<=0)continue;
         count++;
         datetime at=(datetime)ticks[i].time;
         if(bid<minBid){minBid=bid;bidAt=at;}
         if(ask<minAsk){minAsk=ask;askAt=at;}
         if(ask>maxAsk){maxAsk=ask;maxAskAt=at;}
         if(bidTpAt==0&&bid<=tp)bidTpAt=at;
         if(askTpAt==0&&ask<=tp)askTpAt=at;
         if(askSlAt==0&&ask>=sl)askSlAt=at;
      }
   }
   MqlRates rates[];
   int bars=CopyRates(_Symbol,PERIOD_M1,from,to,rates);
   for(int i=0;i<bars;i++)if(rates[i].low<m1Low){m1Low=rates[i].low;m1At=rates[i].time;}
   FileWrite(out,_Symbol,count,DoubleToString(minBid,_Digits),TimeToString(bidAt,TIME_DATE|TIME_SECONDS),
      DoubleToString(minAsk,_Digits),TimeToString(askAt,TIME_DATE|TIME_SECONDS),
      TimeToString(bidTpAt,TIME_DATE|TIME_SECONDS),TimeToString(askTpAt,TIME_DATE|TIME_SECONDS),
      TimeToString(askSlAt,TIME_DATE|TIME_SECONDS),DoubleToString(maxAsk,_Digits),
      TimeToString(maxAskAt,TIME_DATE|TIME_SECONDS),DoubleToString(m1Low,_Digits),TimeToString(m1At,TIME_DATE|TIME_MINUTES));
   FileClose(out);
}
