#ifndef MACROSS_ORDER_FLOW_MQH
#define MACROSS_ORDER_FLOW_MQH
#include "MaCrossOrderFlowCore.mqh"
input group "ORDER FLOW - bid tick proxy (not exchange traded volume)"
input MC_OF_MODE InpOrderFlowMode=MC_OF_OFF;
input int InpOrderFlowLookback=24;
input int InpOrderFlowBins=32;
input double InpOrderFlowValueArea=0.70;
input double InpOrderFlowMinActivity=1.0;
input double InpOrderFlowMinDelta=0.10;
McOfConfig g_mcOf={0,24,32,0.70,1.0,0.10};
bool g_mcOfDataIncomplete=false;
string g_mcOfStatus="OFF";
struct McOfCached {string key;McOfSnapshot snapshot;MqlRates signal;};
McOfCached g_mcOfCache[256];int g_mcOfNext=0;
string McOfIdentity(){return g_mcOf.mode==0?"":"|ORDERFLOW_QUOTE_V1="+McOfConfigText(g_mcOf);}
void McOfReset()
{
   for(int i=0;i<256;i++)g_mcOfCache[i].key="";
   g_mcOfNext=0;g_mcOfDataIncomplete=false;g_mcOfStatus=g_mcOf.mode==0?"OFF":"QUOTE PROXY / WAIT";
}
bool McOfInit()
{
   g_mcOf.mode=(int)InpOrderFlowMode;g_mcOf.lookback=InpOrderFlowLookback;g_mcOf.bins=InpOrderFlowBins;
   g_mcOf.valueArea=InpOrderFlowValueArea;g_mcOf.minActivity=InpOrderFlowMinActivity;g_mcOf.minDelta=InpOrderFlowMinDelta;
   McOfReset();return McOfConfigValid(g_mcOf);
}
string McOfModeName()
{
   if(g_mcOf.mode==1)return "OF: BREAK";if(g_mcOf.mode==2)return "OF: REJECT";
   return g_mcOf.mode==3?"OF: EITHER":"OF: OFF";
}
bool McOfFilter(string symbol,ENUM_TIMEFRAMES tf,datetime signalTime,int direction,string &reason,string &detail)
{
   if(g_mcOf.mode==0)return true;
   string key=symbol+"/"+(string)tf+"/"+(string)signalTime+McOfIdentity();
   McOfSnapshot snapshot;MqlRates signal;bool found=false;
   for(int i=0;i<256;i++)if(g_mcOfCache[i].key==key)
   {snapshot=g_mcOfCache[i].snapshot;signal=g_mcOfCache[i].signal;found=true;break;}
   if(!found)
   {
      MqlRates bars[];ArraySetAsSeries(bars,false);int sec=PeriodSeconds(tf);
      int n=CopyRates(symbol,tf,signalTime,g_mcOf.lookback+1,bars);
      string error="OF_DATA_BARS";
      bool ready=n==g_mcOf.lookback+1&&bars[n-1].time==signalTime&&sec>0
         &&signalTime+sec<=TimeCurrent()&&SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED);
      long expected=0;if(ready)for(int b=0;b<n;b++)expected+=bars[b].tick_volume;
      if(ready&&(expected<=0||expected>250000)){ready=false;error="OF_DATA_BUDGET";}
      if(ready)
      {
         MqlTick ticks[];ResetLastError();
         int count=CopyTicksRange(symbol,ticks,COPY_TICKS_INFO,(ulong)bars[0].time*1000,(ulong)(signalTime+sec)*1000-1);
         int err=GetLastError();
         double size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
         ready=count>0&&err==0;
         error="OF_DATA_TICKS error="+(string)err;
         if(ready){ready=McOfCalculate(ticks,bars,sec,size,g_mcOf,snapshot);error=snapshot.reason;}
      }
      if(!ready)
      {
         reason=error;detail="ORDERFLOW INCOMPLETE: "+error;g_mcOfDataIncomplete=true;g_mcOfStatus=detail;
         return false; // Do not memoize transient downloads/errors as market rejections.
      }
      signal=bars[n-1];int slot=g_mcOfNext++%256;
      g_mcOfCache[slot].key=key;g_mcOfCache[slot].snapshot=snapshot;g_mcOfCache[slot].signal=signal;
   }
   bool allowed=McOfAllows(g_mcOf,snapshot,signal,direction);
   detail="OF_QUOTE_PROXY val="+DoubleToString(snapshot.val,8)+" vah="+DoubleToString(snapshot.vah,8)
      +" poc="+DoubleToString(snapshot.poc,8)+" activity="+DoubleToString(snapshot.activity,4)
      +" delta="+DoubleToString(snapshot.delta,4)+" direction="+(string)direction;
   reason=allowed?"":"OF_BLOCK";g_mcOfStatus=allowed?"QUOTE PROXY: PASS":"QUOTE PROXY: BLOCK";
   return allowed;
}
#endif
