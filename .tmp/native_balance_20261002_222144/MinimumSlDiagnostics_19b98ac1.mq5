#property strict
#include "orb/NativeRiskBalance.mqh"
#include "NativeMarginQuote.mqh"
void OnStart()
{
 if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
 MqlTick tick;ulong start=GetTickCount64();
 while(GetTickCount64()-start<20000){if(TerminalInfoInteger(TERMINAL_CONNECTED)&&SymbolInfoTick(_Symbol,tick)&&tick.ask>=tick.bid&&tick.bid>0)break;Sleep(100);}
 int file=FileOpen("MinimumSlDiagnostics.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
 if(file==INVALID_HANDLE)return;
 FileWrite(file,"symbol=",_Symbol," currency=",AccountInfoString(ACCOUNT_CURRENCY)," calc_mode=",SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE)," tick_size=",SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE)," minlot=",SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));
 for(int i=0;i<2;i++)
 {
  bool buy=i==0;double entry=buy?tick.ask:tick.bid;
  double step=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_POINT));
  double distance=MathMax(step*10,MathFloor(entry*0.005/(step*10))*step*10);
  double sl=entry+(buy?-1:1)*distance,narrow=entry+(sl-entry)/10,loss=0,small=0;
  bool a=NativeMinimumSlLoss(buy,entry,sl,loss),b=NativeMinimumSlLoss(buy,entry,narrow,small);
  FileWrite(file,"buy=",buy," entry=",entry," SL=",sl," narrow_SL=",narrow," loss=",loss," narrow_loss=",small," ratio=",loss>0?small*10/loss:0," ok=",a&&b);
 }
 FileClose(file);
}