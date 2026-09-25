#property strict

void OnStart()
{
   int out=FileOpen("XauSpreadSnapshot.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"kind","time","bid","ask","spread");
   MqlTick live;
   if(SymbolInfoTick(_Symbol,live))
      FileWrite(out,"latest",TimeToString(live.time,TIME_DATE|TIME_SECONDS),
         DoubleToString(live.bid,_Digits),DoubleToString(live.ask,_Digits),
         DoubleToString(live.ask-live.bid,_Digits));
   MqlTick ticks[];
   ulong from=(ulong)StringToTime("2026.09.11 15:03:00")*1000;
   int count=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,from,from+60000);
   for(int i=0;i<count;i++)
   {
      if(ticks[i].bid<=0||ticks[i].ask<=0)continue;
      FileWrite(out,"audit_entry",TimeToString(ticks[i].time,TIME_DATE|TIME_SECONDS),
         DoubleToString(ticks[i].bid,_Digits),DoubleToString(ticks[i].ask,_Digits),
         DoubleToString(ticks[i].ask-ticks[i].bid,_Digits));
      break;
   }
   FileClose(out);
}
