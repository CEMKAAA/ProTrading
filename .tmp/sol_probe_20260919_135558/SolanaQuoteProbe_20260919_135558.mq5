#property strict
void OnStart()
{
   string symbol="SOLUSDm";SymbolSelect(symbol,true);
   datetime from=D'2026.09.03 02:00',to=D'2026.09.03 13:00';
   MqlRates rates[];ResetLastError();int bars=CopyRates(symbol,PERIOD_M5,from,to,rates);int barsError=GetLastError();
   MqlTick ticks[];ResetLastError();int count=CopyTicksRange(symbol,ticks,COPY_TICKS_INFO,(ulong)from*1000,(ulong)to*1000);int tickError=GetLastError();
   string result="{\"symbol\":\""+symbol+"\",\"bars\":"+(string)bars+",\"bars_error\":"+(string)barsError+",\"ticks\":"+(string)count+",\"tick_error\":"+(string)tickError+",\"samples\":[";
   int cursor=0;bool comma=false;
   for(int b=0;b<bars;b++)
   {
      datetime available=rates[b].time+300;
      while(cursor<count&&ticks[cursor].time<available)cursor++;
      if(cursor>=count)break;
      MqlTick tick=ticks[cursor];
      if(comma)result+=",";comma=true;
      result+="{\"signal_bar\":\""+TimeToString(rates[b].time,TIME_DATE|TIME_MINUTES)+"\",\"close\":"+DoubleToString(rates[b].close,5)
         +",\"tick_time\":\""+TimeToString(tick.time,TIME_DATE|TIME_SECONDS)+"\",\"bid\":"+DoubleToString(tick.bid,5)+",\"ask\":"+DoubleToString(tick.ask,5)
         +",\"spread\":"+DoubleToString(tick.ask-tick.bid,5)+"}";
   }
   result+="]}";
   int f=FileOpen("SolanaQuoteProbe_20260919_135558.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print("SOL quote probe bars=",bars," ticks=",count," error=",tickError);
}
