#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlowCore.mqh"
// Read-only fixed-trade screening, NOT a strategy lifecycle replay.
void OnStart()
{
 int reader=FileOpen("MaOfScreenInput.csv",FILE_READ|FILE_CSV|FILE_ANSI,',');
 int output=FileOpen("MaOfScreenOutput.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
 if(reader==INVALID_HANDLE||output==INVALID_HANDLE)return;
 FileWrite(output,"id","symbol","time","r","valid","reason","breakout","rejection","either","profile","activity_pass","delta_pass","activity","directional_delta");
 McOfConfig c;c.mode=3;c.lookback=24;c.bins=32;c.valueArea=.7;c.minActivity=1;c.minDelta=.1;
 ulong started=GetTickCount64();
 while(!FileIsEnding(reader)&&!IsStopped())
 {
  string id=FileReadString(reader),symbol=FileReadString(reader);
  int tf=(int)StringToInteger(FileReadString(reader));
  datetime t=(datetime)StringToInteger(FileReadString(reader));
  int dir=(int)StringToInteger(FileReadString(reader));double pnl=StringToDouble(FileReadString(reader));
  SymbolSelect(symbol,true);MqlRates bars[];MqlTick ticks[];McOfSnapshot s;ZeroMemory(s);
  int sec=PeriodSeconds((ENUM_TIMEFRAMES)tf);string reason="BARS";bool valid=false;
  int n=CopyRates(symbol,(ENUM_TIMEFRAMES)tf,t,25,bars);
  if(n==25&&bars[24].time==t&&sec>0)
  {
   ResetLastError();int nt=CopyTicksRange(symbol,ticks,COPY_TICKS_INFO,(ulong)bars[0].time*1000,(ulong)(t+sec)*1000-1);
   int err=GetLastError();reason="TICKS_"+(string)err;
   if(nt>0&&err==0){valid=McOfCalculate(ticks,bars,sec,SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),c,s);reason=s.reason;}
  }
  bool b=false,r=false,e=false;
  if(valid){c.mode=1;b=McOfAllows(c,s,bars[24],dir);c.mode=2;r=McOfAllows(c,s,bars[24],dir);c.mode=3;e=McOfAllows(c,s,bars[24],dir);}
  bool profile=false;
  if(valid)
  {
   bool outside=dir>0?bars[24].close>s.vah:bars[24].close<s.val;
   bool reject=dir>0?(bars[24].low<s.val&&bars[24].close>=s.val&&bars[24].close<=s.vah)
                    :(bars[24].high>s.vah&&bars[24].close<=s.vah&&bars[24].close>=s.val);
   profile=outside||reject;
  }
  FileWrite(output,id,symbol,(long)t,pnl,valid,reason,b,r,e,profile,
     valid&&s.activity>=1,valid&&dir*s.delta>=.1,s.activity,dir*s.delta);FileFlush(output);
  if(GetTickCount64()-started>240000)break;
 }
 FileClose(reader);FileClose(output);
}

