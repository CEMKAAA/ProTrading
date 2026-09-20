// Offline script-only data adapter. Never deployed to an EA chart.
// Shared math and exact per-bar coverage checks are unchanged.
int McOfPrepare(string symbol,ENUM_TIMEFRAMES tf,datetime at,bool historical,string &error,int laneOverride=-1)
{
 error="";if(g_mcOf.mode==0)return 1;
 string key=McOfCacheKey(symbol,tf,at);
 for(int j=0;j<256;j++)if(g_mcOfCache[j].key==key)return 1;
 McOfCached r;ZeroMemory(r);r.key=key;
 string path=campaignCache+"\\"+symbol+"_"+(string)tf+"_"+(string)(long)at+".csv";
 int f=FileOpen(path,FILE_READ|FILE_CSV|FILE_ANSI,',');
 if(f!=INVALID_HANDLE)
 {
  r.snapshot.poc=StringToDouble(FileReadString(f));r.snapshot.val=StringToDouble(FileReadString(f));
  r.snapshot.vah=StringToDouble(FileReadString(f));r.snapshot.profileCount=StringToDouble(FileReadString(f));
  r.snapshot.buy=StringToDouble(FileReadString(f));r.snapshot.sell=StringToDouble(FileReadString(f));
  r.snapshot.neutral=StringToDouble(FileReadString(f));r.snapshot.activity=StringToDouble(FileReadString(f));
  r.snapshot.delta=StringToDouble(FileReadString(f));r.signal.close=StringToDouble(FileReadString(f));
  r.signal.high=StringToDouble(FileReadString(f));r.signal.low=StringToDouble(FileReadString(f));
  string seal=FileReadString(f);FileClose(f);
  if(seal!="COMPLETE"){error="CACHE_UNSEALED";g_mcOfDataIncomplete=true;return -1;}
  r.snapshot.valid=true;r.signal.time=at;
 }
 else
 {
  MqlRates bars[];MqlTick ticks[];int n=CopyRates(symbol,tf,at,g_mcOf.lookback+1,bars);
  int sec=PeriodSeconds(tf);
  if(n!=g_mcOf.lookback+1||bars[n-1].time!=at||sec<=0)
  {error="OF_DATA_BARS";g_mcOfDataIncomplete=true;return -1;}
  ResetLastError();int nt=CopyTicksRange(symbol,ticks,COPY_TICKS_INFO,(ulong)bars[0].time*1000,(ulong)(at+sec)*1000-1);
  int err=GetLastError();
  if(nt<=0||err!=0){error="OF_DATA_TICKS_"+(string)err;g_mcOfDataIncomplete=true;return -1;}
  if(!McOfCalculate(ticks,bars,sec,SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),g_mcOf,r.snapshot))
  {error=r.snapshot.reason;g_mcOfDataIncomplete=true;return -1;}
  r.signal=bars[n-1];
  f=FileOpen(path,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
  if(f==INVALID_HANDLE){error="CACHE_WRITE_FAILED";g_mcOfDataIncomplete=true;return -1;}
  FileWrite(f,r.snapshot.poc,r.snapshot.val,r.snapshot.vah,r.snapshot.profileCount,r.snapshot.buy,
     r.snapshot.sell,r.snapshot.neutral,r.snapshot.activity,r.snapshot.delta,r.signal.close,r.signal.high,r.signal.low,"COMPLETE");
  FileFlush(f);FileClose(f);
 }
 r.snapshot.reason="OF_QUOTE_PROXY";
 g_mcOfCache[g_mcOfNext]=r;g_mcOfNext=(g_mcOfNext+1)%256;return 1;
}
