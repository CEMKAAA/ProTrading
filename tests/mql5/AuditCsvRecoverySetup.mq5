#property strict
void OnStart()
{
   string symbol="AXCSV_"+(string)GetTickCount64();
   bool ok=CustomSymbolCreate(symbol,"AuditFixtures","EURUSDm")&&SymbolSelect(symbol,true);
   MqlRates rates[];ArrayResize(rates,3);
   for(int i=0;i<3;i++)
   {
      ZeroMemory(rates[i]);rates[i].time=D'2026.09.15 00:00'+i*60;
      rates[i].open=1.1;rates[i].high=1.101;rates[i].low=1.099;rates[i].close=1.1;
      rates[i].tick_volume=100;rates[i].spread=2;
   }
   if(ok)ok=CustomRatesUpdate(symbol,rates)==3;
   int f=FileOpen("AuditCsvRecoverySetup.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(f,(ok?symbol:"FAIL")+"\n");FileClose(f);
}
