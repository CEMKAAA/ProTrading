#property strict
void OnStart(){
 for(int i=0;i<120&&!TerminalInfoInteger(TERMINAL_CONNECTED);i++)Sleep(500);
 int f=FileOpen("GbpTickAvailability.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
 if(f==INVALID_HANDLE)return;
 FileWrite(f,"symbol","connected","requested","count","error","firstQuote","bid","ask");
 datetime dates[]={D'2021.10.29 07:20',D'2024.10.21 07:20',D'2025.10.30 08:45',D'2025.11.03 08:40'};
 for(int i=0;i<ArraySize(dates);i++){
  MqlTick ticks[];ResetLastError();int count=CopyTicks(_Symbol,ticks,COPY_TICKS_INFO,(ulong)dates[i]*1000,1);int error=GetLastError();
  FileWrite(f,_Symbol,(bool)TerminalInfoInteger(TERMINAL_CONNECTED),TimeToString(dates[i]),count,error,count>0?TimeToString((datetime)ticks[0].time):"",count>0?ticks[0].bid:0,count>0?ticks[0].ask:0);FileFlush(f);
 }
 FileClose(f);
}
