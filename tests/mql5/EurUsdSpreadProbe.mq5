#property strict
input datetime InpStart=D'2026.09.28 00:00';
input int InpHours=48;
void OnStart()
{
   int out=FileOpen("EurUsdSpreadProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"hour_server","ticks","min_pips","median_pips","p95_pips","max_pips","first_bid","first_ask");
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double pip=(digits==3||digits==5)?10.0*point:point;
   datetime start=InpStart;
   for(int hour=0;hour<InpHours;hour++)
   {
      datetime begin=start+hour*3600;
      MqlTick ticks[];
      int count=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)begin*1000,(ulong)(begin+3600)*1000-1);
      double spreads[];int used=0;
      double firstBid=0.0,firstAsk=0.0;
      for(int i=0;i<count;i++)
      {
         if(ticks[i].bid<=0.0||ticks[i].ask<=ticks[i].bid)continue;
         if(used==0){firstBid=ticks[i].bid;firstAsk=ticks[i].ask;}
         ArrayResize(spreads,used+1);
         spreads[used++]=(ticks[i].ask-ticks[i].bid)/pip;
      }
      if(used>0)
      {
         ArraySort(spreads);
         FileWrite(out,TimeToString(begin,TIME_DATE|TIME_MINUTES),used,
            DoubleToString(spreads[0],3),DoubleToString(spreads[used/2],3),
            DoubleToString(spreads[(int)MathFloor((used-1)*0.95)],3),DoubleToString(spreads[used-1],3),
            DoubleToString(firstBid,digits),DoubleToString(firstAsk,digits));
      }
      else FileWrite(out,TimeToString(begin,TIME_DATE|TIME_MINUTES),0,"","","","","","");
      FileFlush(out);
   }
   FileClose(out);
}
