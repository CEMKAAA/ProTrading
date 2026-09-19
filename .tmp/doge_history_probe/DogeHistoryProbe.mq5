#property strict
void OnStart(){
 string s="DOGEUSDm";SymbolSelect(s,true);MqlRates r[];ArraySetAsSeries(r,false);
 int n=-1;for(int k=0;k<20;k++){ResetLastError();n=CopyRates(s,PERIOD_M5,0,1000,r);if(n>0)break;Sleep(500);}
 int err=GetLastError();datetime now=TimeTradeServer();if(now==0)now=TimeCurrent();
 MqlRates recent[];int nr=CopyRates(s,PERIOD_M5,now-14*86400,now,recent);
 string t="now="+TimeToString(now,TIME_DATE|TIME_SECONDS)+" bars="+(string)n+" err="+(string)err+" recent_2w="+(string)nr+" trade_mode="+(string)SymbolInfoInteger(s,SYMBOL_TRADE_MODE)+"\n";
 for(int i=MathMax(0,n-12);i<n;i++)t+=TimeToString(r[i].time,TIME_DATE|TIME_MINUTES)+" o="+DoubleToString(r[i].open,8)+" h="+DoubleToString(r[i].high,8)+" l="+DoubleToString(r[i].low,8)+" c="+DoubleToString(r[i].close,8)+" vol="+(string)r[i].tick_volume+"\n";
 int f=FileOpen("DogeHistoryProbe.txt",FILE_WRITE|FILE_TXT);if(f!=INVALID_HANDLE){FileWriteString(f,t);FileClose(f);}Print(t);
}
