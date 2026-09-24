#property strict
void OnStart()
{
   string symbols[]={"JP225m","USDJPYm","USTECm"};
   int out=FileOpen("LeaderboardFiveYearCoverage.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"symbol","selected","first_m1","first_h1","first_d1","max_bars");
   for(int i=0;i<ArraySize(symbols);i++)
   {
      string s=symbols[i];bool selected=SymbolInfoInteger(s,SYMBOL_SELECT)!=0;
      datetime m1=(datetime)SeriesInfoInteger(s,PERIOD_M1,SERIES_FIRSTDATE);
      datetime h1=(datetime)SeriesInfoInteger(s,PERIOD_H1,SERIES_FIRSTDATE);
      datetime d1=(datetime)SeriesInfoInteger(s,PERIOD_D1,SERIES_FIRSTDATE);
      FileWrite(out,s,selected?1:0,TimeToString(m1,TIME_DATE),TimeToString(h1,TIME_DATE),
         TimeToString(d1,TIME_DATE),(long)TerminalInfoInteger(TERMINAL_MAXBARS));
   }
   FileClose(out);
}
