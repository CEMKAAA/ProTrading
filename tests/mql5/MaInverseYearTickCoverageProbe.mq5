#property strict
void OnStart()
{
   datetime from=D'2025.10.02 03:00:00';
   datetime to=from+3600;
   int waitedMs=0;
   while(!TerminalInfoInteger(TERMINAL_CONNECTED)&&waitedMs<30000)
   {
      Sleep(500);
      waitedMs+=500;
   }
   SymbolSelect(_Symbol,true);
   MqlRates bars[];
   ResetLastError();
   int barCount=CopyRates(_Symbol,PERIOD_M1,from,to,bars);
   int barError=GetLastError();
   int out=FileOpen("MaInverseYearTickCoverageProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"attempt","connected","waited_ms","range_count","range_error","first_time","last_time","bar_count","bar_error");
   MqlTick earliest[];
   ResetLastError();
   int earliestCount=CopyTicks(_Symbol,earliest,COPY_TICKS_INFO,(ulong)from*1000,1);
   int earliestError=GetLastError();
   FileWrite(out,"earliest",(int)TerminalInfoInteger(TERMINAL_CONNECTED),waitedMs,earliestCount,earliestError,
      earliestCount>0?TimeToString((datetime)earliest[0].time,TIME_DATE|TIME_SECONDS):"-",
      "-",barCount,barError);
   FileFlush(out);
   for(int attempt=1;attempt<=3;attempt++)
   {
      MqlTick range[];
      ResetLastError();
      int count=CopyTicksRange(_Symbol,range,COPY_TICKS_INFO,(ulong)from*1000,(ulong)to*1000-1);
      int error=GetLastError();
      FileWrite(out,attempt,(int)TerminalInfoInteger(TERMINAL_CONNECTED),waitedMs,count,error,
         count>0?TimeToString((datetime)range[0].time,TIME_DATE|TIME_SECONDS):"-",
         count>0?TimeToString((datetime)range[count-1].time,TIME_DATE|TIME_SECONDS):"-",
         barCount,barError);
      FileFlush(out);
      if(count>0&&error==0)break;
      Sleep(3000);
   }
   FileClose(out);
}
