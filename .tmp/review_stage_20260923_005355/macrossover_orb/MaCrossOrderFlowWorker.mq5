#property strict
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots 1
#property indicator_type1 DRAW_NONE
#include "MaCrossOrderFlowCore.mqh"
// Runs in indicator context: history synchronization must never wait inside
// the trading EA. Private terminal globals form a two-phase response mailbox.
input string InpMailbox="";
input string InpConfig="";
double dummy[];
McOfConfig config;
datetime request=0;
ulong started=0,lastAttempt=0;
bool finished=false;
MqlTick cachedTicks[];
bool Alive(){return StringLen(InpMailbox)>0&&GlobalVariableCheck(InpMailbox+"alive");}
void Publish(int state,int code,const McOfSnapshot &s,const MqlRates &bar)
{
   if(!Alive()||(datetime)GlobalVariableGet(InpMailbox+"request")!=request)return;
   GlobalVariableSet(InpMailbox+"ready",0);
   GlobalVariableSet(InpMailbox+"state",state);GlobalVariableSet(InpMailbox+"code",code);
   GlobalVariableSet(InpMailbox+"poc",s.poc);GlobalVariableSet(InpMailbox+"val",s.val);GlobalVariableSet(InpMailbox+"vah",s.vah);
   GlobalVariableSet(InpMailbox+"count",s.profileCount);GlobalVariableSet(InpMailbox+"buy",s.buy);
   GlobalVariableSet(InpMailbox+"sell",s.sell);GlobalVariableSet(InpMailbox+"neutral",s.neutral);
   GlobalVariableSet(InpMailbox+"activity",s.activity);GlobalVariableSet(InpMailbox+"delta",s.delta);
   GlobalVariableSet(InpMailbox+"close",bar.close);GlobalVariableSet(InpMailbox+"high",bar.high);GlobalVariableSet(InpMailbox+"low",bar.low);
   GlobalVariableSet(InpMailbox+"ready",(double)request);
}
void Work()
{
   if(!Alive())return;
   datetime wanted=(datetime)GlobalVariableGet(InpMailbox+"request");
   if(wanted<=0)return;
   ulong now=GetTickCount64();
   if(wanted!=request){request=wanted;started=now;lastAttempt=0;finished=false;}
   if(finished||(lastAttempt>0&&now-lastAttempt<250))return;
   lastAttempt=now;
   McOfSnapshot s;MqlRates signal;ZeroMemory(s);ZeroMemory(signal);
   MqlRates bars[];ArraySetAsSeries(bars,false);
   int n=CopyRates(_Symbol,_Period,request,config.lookback+1,bars),sec=PeriodSeconds(_Period);
   int code=1;
   bool ready=n==config.lookback+1&&sec>0&&bars[n-1].time==request
      &&request+sec<=TimeCurrent()&&SeriesInfoInteger(_Symbol,_Period,SERIES_SYNCHRONIZED);
   if(ready)
   {
      long expected=0;for(int b=0;b<n;b++)expected+=bars[b].tick_volume;
      if(expected<=0||expected>250000){code=2;ready=false;finished=true;}
      else
      {
         ResetLastError();
         // CopyTicks (unlike relying on CopyTicksRange timing) explicitly
         // guarantees an immediate, partial return in indicator context.
         // The pure core ignores later ticks and verifies exact per-bar mass.
         uint limit=(uint)MathMin(500000,MathMax(1024,expected*4+16));
         int count=ArraySize(cachedTicks);
         bool covered=count>0&&cachedTicks[0].time_msc<=(long)bars[0].time*1000
            &&cachedTicks[count-1].time_msc>=(long)(bars[n-1].time+sec)*1000;
         if(!covered)count=CopyTicks(_Symbol,cachedTicks,COPY_TICKS_INFO,(ulong)bars[0].time*1000,limit);
         int err=GetLastError();ready=count>0&&err==0;code=err==0?3:err;
         if(ready)
         {
            ready=McOfCalculate(cachedTicks,bars,sec,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),config,s);
            code=ready?0:4;
            if(ready)signal=bars[n-1];
         }
      }
   }
   if(ready){finished=true;Publish(1,0,s,signal);}
   else if(finished||now-started>=30000){finished=true;Publish(-1,code,s,signal);}
   else Publish(0,code,s,signal);
}
int OnInit()
{
   if(!Alive()||!McOfConfigRead(InpConfig,config))return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,dummy,INDICATOR_DATA);
   if(!EventSetMillisecondTimer(100))return INIT_FAILED;
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){EventKillTimer();}
void OnTimer(){Work();}
int OnCalculate(const int total,const int previous,const datetime &time[],const double &open[],
                const double &high[],const double &low[],const double &close[],const long &ticks[],
                const long &volume[],const int &spread[])
{Work();return total;}
