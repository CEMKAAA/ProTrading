$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/UsdJpyDecadeCoverage'
$report=Join-Path $root 'logs/OrbMLPriorFive_20260910'
[IO.Directory]::CreateDirectory($dest)|Out-Null
[IO.Directory]::CreateDirectory($report)|Out-Null
$source=@'
#property strict
#property script_show_inputs
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   string symbol="USDJPYm";SymbolSelect(symbol,true);
   ENUM_TIMEFRAMES frames[]={PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_H1,PERIOD_H2,PERIOD_H4,PERIOD_D1};
   int out=FileOpen("usdjpy_decade_coverage.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"symbol","tf","year","bars","first","last","max_gap_seconds","invalid","error");
   for(int t=0;t<ArraySize(frames)&&!IsStopped();t++)
   {
      for(int year=2014;year<=2026&&!IsStopped();year++)
      {
         datetime from=StringToTime((string)year+".01.01 00:00");
         datetime to=MathMin(StringToTime((string)(year+1)+".01.01 00:00")-1,D'2026.09.09 23:59:59');
         MqlRates rates[];ArraySetAsSeries(rates,false);ResetLastError();
         int n=CopyRates(symbol,frames[t],from,to,rates);
         int error=GetLastError();
         if(n<0){Sleep(1000);ResetLastError();n=CopyRates(symbol,frames[t],from,to,rates);error=GetLastError();}
         int invalid=0;long gap=0;
         for(int i=0;i<n;i++)
         {
            if(rates[i].close<=0||rates[i].high<rates[i].low||(i>0&&rates[i].time<=rates[i-1].time))invalid++;
            if(i>0)gap=MathMax(gap,(long)(rates[i].time-rates[i-1].time));
         }
         string first=n>0?TimeToString(rates[0].time,TIME_DATE|TIME_MINUTES):"";
         string last=n>0?TimeToString(rates[n-1].time,TIME_DATE|TIME_MINUTES):"";
         FileWrite(out,symbol,EnumToString(frames[t]),year,n,first,last,gap,invalid,error);FileFlush(out);
         Print("DECADE_COVERAGE ",EnumToString(frames[t])," ",year," bars=",n," first=",first," last=",last," error=",error);
      }
   }
   FileClose(out);Print("DECADE_COVERAGE FINISHED");
}
'@
[IO.File]::WriteAllText((Join-Path $dest 'UsdJpyDecadeCoverage.mq5'),$source,[Text.UTF8Encoding]::new($false))
$ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=UsdJpyDecadeCoverage\UsdJpyDecadeCoverage`r`nSymbol=USDJPYm`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $report 'coverage.ini'),$ini)
