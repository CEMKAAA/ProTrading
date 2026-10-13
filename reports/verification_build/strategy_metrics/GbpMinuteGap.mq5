#property strict
void OnStart(){
 int f=FileOpen("GbpMinuteGap.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
 FileWrite(f,"tf","count","error","time","open","high","low","close","spread");
 ENUM_TIMEFRAMES frames[]={PERIOD_M5,PERIOD_M1};
 for(int k=0;k<2;k++){
  MqlRates bars[];ResetLastError();int count=CopyRates(_Symbol,frames[k],D'2022.01.03 08:20',D'2022.01.03 09:00',bars);int error=GetLastError();
  for(int i=0;i<count;i++)FileWrite(f,EnumToString(frames[k]),count,error,TimeToString(bars[i].time),bars[i].open,bars[i].high,bars[i].low,bars[i].close,bars[i].spread);
 }
 FileClose(f);
}
