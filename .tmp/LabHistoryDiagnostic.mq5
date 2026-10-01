#property strict
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   ulong start=GetTickCount64();while(!TerminalInfoInteger(TERMINAL_CONNECTED)&&GetTickCount64()-start<30000)Sleep(250);
   int out=FileOpen("LabHistoryDiagnostic.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(out==INVALID_HANDLE)return;
   datetime times[]={D'2025.10.01 19:44',D'2025.10.02 03:00',D'2024.10.03 19:44',D'2026.09.17 19:44'};
   for(int i=0;i<ArraySize(times);i++)
   {
      MqlTick ticks[];ResetLastError();int n=CopyTicks(_Symbol,ticks,COPY_TICKS_INFO,(ulong)times[i]*1000,1);int err=GetLastError();
      FileWriteString(out,"COPY "+TimeToString(times[i])+" n="+(string)n+" err="+(string)err+" first="+(n>0?TimeToString((datetime)ticks[0].time):"NONE")+"\n");FileFlush(out);
      ResetLastError();n=CopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)times[i]*1000,(ulong)(times[i]+900)*1000);err=GetLastError();
      FileWriteString(out,"RANGE "+TimeToString(times[i])+" n="+(string)n+" err="+(string)err+" first="+(n>0?TimeToString((datetime)ticks[0].time):"NONE")+"\n");FileFlush(out);
   }
   FileClose(out);
}
