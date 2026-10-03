#property strict

void WriteResult(int file,string line)
{
   FileWriteString(file,line+"\r\n");FileFlush(file);Print(line);
}

void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   int file=FileOpen("EntryLabTickAvailability.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file==INVALID_HANDLE)return;
   ulong started=GetTickCount64();
   while(!TerminalInfoInteger(TERMINAL_CONNECTED)&&GetTickCount64()-started<45000&&!IsStopped())Sleep(250);
   WriteResult(file,"server="+AccountInfoString(ACCOUNT_SERVER)+" symbol="+_Symbol
      +" connected="+(string)TerminalInfoInteger(TERMINAL_CONNECTED));
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)){FileClose(file);return;}
   SymbolSelect(_Symbol,true);
   datetime dates[]={D'2021.10.04 12:00',D'2024.10.04 12:00',D'2025.10.06 12:00',D'2025.12.15 12:00',D'2026.01.02 12:00',D'2026.09.17 12:00'};
   for(int i=0;i<ArraySize(dates)&&!IsStopped();i++)
   {
      for(int attempt=1;attempt<=3&&!IsStopped();attempt++)
      {
         MqlTick ticks[];ResetLastError();ulong ms=GetTickCount64();
         int count=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,(ulong)dates[i]*1000,(ulong)(dates[i]+3600)*1000-1);
         int error=GetLastError();
         WriteResult(file,"RANGE "+TimeToString(dates[i],TIME_DATE|TIME_MINUTES)+" attempt="+(string)attempt
            +" count="+(string)count+" error="+(string)error+" elapsed_ms="+(string)(GetTickCount64()-ms)
            +" first="+(count>0?TimeToString(ticks[0].time,TIME_DATE|TIME_SECONDS):"NONE"));
         if(count>0&&error==0)break;
         Sleep(1500);
      }
      MqlTick first[];ResetLastError();
      int count=CopyTicks(_Symbol,first,COPY_TICKS_INFO,(ulong)dates[i]*1000,1);int error=GetLastError();
      WriteResult(file,"NEXT "+TimeToString(dates[i],TIME_DATE|TIME_MINUTES)+" count="+(string)count+" error="+(string)error
         +" first="+(count>0?TimeToString(first[0].time,TIME_DATE|TIME_SECONDS):"NONE"));
      ENUM_TIMEFRAMES frames[]={PERIOD_M1,PERIOD_M5};
      for(int j=0;j<ArraySize(frames);j++)
      {
         MqlRates bars[];int countBars=-1,errorBars=0;
         for(int attempt=0;attempt<3&&!IsStopped();attempt++)
         {
            ResetLastError();countBars=CopyRates(_Symbol,frames[j],dates[i],dates[i]+3600-1,bars);errorBars=GetLastError();
            if(countBars>0&&errorBars==0)break;Sleep(1000);
         }
         WriteResult(file,"BARS "+TimeToString(dates[i],TIME_DATE|TIME_MINUTES)+" tf="+EnumToString(frames[j])
            +" count="+(string)countBars+" error="+(string)errorBars
            +" first="+(countBars>0?TimeToString(bars[0].time,TIME_DATE|TIME_MINUTES):"NONE"));
      }
   }
   WriteResult(file,"DONE elapsed_ms="+(string)(GetTickCount64()-started));FileClose(file);
}
