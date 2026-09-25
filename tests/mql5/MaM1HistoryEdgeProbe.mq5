#property script_show_inputs
input int InpDays=14;

void OnStart()
{
   string symbol="XAUUSDm";
   ENUM_TIMEFRAMES tf=PERIOD_M1;
   datetime from=TimeCurrent()-(datetime)((long)InpDays*86400L+200L*60L);
   datetime to=from+7*86400;
   long first=SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE);
   long bars=SeriesInfoInteger(symbol,tf,SERIES_BARS_COUNT);
   long maxBars=TerminalInfoInteger(TERMINAL_MAXBARS);
   Print("MA_M1_EDGE_BEGIN days=",InpDays," from=",TimeToString(from,TIME_DATE|TIME_MINUTES),
         " first=",first," bars=",bars," max=",maxBars);
   MqlRates rates[];
   ulong started=GetTickCount64();
   ResetLastError();
   int copied=CopyRates(symbol,tf,from,to,rates);
   int error=GetLastError();
   Print("MA_M1_EDGE_END copied=",copied," error=",error,
         " elapsed_ms=",GetTickCount64()-started,
         " oldest=",copied>0?TimeToString(rates[0].time,TIME_DATE|TIME_MINUTES):"none");
   started=GetTickCount64();
   int oldBars=Bars(symbol,tf,from,TimeCurrent());
   Print("MA_M1_BARS_2W count=",oldBars," elapsed_ms=",GetTickCount64()-started);
   datetime fiveYearFrom=TimeCurrent()-(datetime)(1825L*86400L+200L*60L);
   started=GetTickCount64();
   oldBars=Bars(symbol,tf,fiveYearFrom,TimeCurrent());
   Print("MA_M1_BARS_5Y count=",oldBars," elapsed_ms=",GetTickCount64()-started);
}
