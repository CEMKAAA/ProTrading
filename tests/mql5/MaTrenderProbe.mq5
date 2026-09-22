#property strict
#property script_show_inputs
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossSignalCore.mqh"
void OnStart()
{
   int f=FileOpen("MaTrenderProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(f==INVALID_HANDLE)return;
   FileWrite(f,"i","open","high","low","close","rail","state","signal","streamSignal","flatState");
   McTrendFollow rail,flat;rail.Reset();flat.Reset();
   McPineKernel kernel;kernel.Reset(MA_CROSS_TRENDER_IQ,MA_CROSS_PAIR_FAST,12,26,200);
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   for(int i=0;i<3000;i++)
   {
      MqlRates b;ZeroMemory(b);b.time=(datetime)(1600000000+i*300);
      b.close=i<20?100:100+12*MathSin(i*0.039)+3*MathCos(i*0.17)+(i%197==0?14:0);
      b.open=i<20?100:b.close+MathSin(i*0.1);
      b.high=MathMax(b.open,b.close)+(i<20?0:0.4);
      b.low=MathMin(b.open,b.close)-(i<20?0:0.6);
      int signal=rail.Push(b,tick),stream=kernel.Push(b);
      MqlRates z=b;z.open=z.high=z.low=z.close=100;flat.Push(z,tick);
      FileWrite(f,i,DoubleToString(b.open,16),DoubleToString(b.high,16),DoubleToString(b.low,16),DoubleToString(b.close,16),
         DoubleToString(rail.Rail(),16),rail.State(),signal,stream,flat.State());
   }
   FileFlush(f);FileClose(f);
}
