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
int g_mcOfHandles[3]={INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE};
string g_mcOfMail[3],g_mcOfOwners[3];
datetime g_mcOfRequests[3];ulong g_mcOfRequestedMs[3];
bool g_mcOfAuditContext=false;
string McOfIdentity(){return g_mcOf.mode==0?"":"|ORDERFLOW_QUOTE_V1="+McOfConfigText(g_mcOf);}
void McOfRelease()
{
   for(int i=0;i<3;i++)
   {
      if(g_mcOfMail[i]!="")GlobalVariableDel(g_mcOfMail[i]+"alive");
      if(g_mcOfHandles[i]!=INVALID_HANDLE)IndicatorRelease(g_mcOfHandles[i]);
      if(g_mcOfMail[i]!="")GlobalVariablesDeleteAll(g_mcOfMail[i]);
      g_mcOfHandles[i]=INVALID_HANDLE;g_mcOfMail[i]="";g_mcOfOwners[i]="";g_mcOfRequests[i]=0;
   }
}
void McOfReset()
{
   McOfRelease();
   for(int i=0;i<256;i++)g_mcOfCache[i].key="";
   g_mcOfNext=0;g_mcOfDataIncomplete=false;g_mcOfStatus=g_mcOf.mode==0?"OFF":"QUOTE PROXY / WAIT";
}
string McOfCacheKey(string symbol,ENUM_TIMEFRAMES tf,datetime signalTime)
{return symbol+"/"+(string)tf+"/"+(string)signalTime+McOfIdentity();}
// Returns 1 ready, 0 pending, -1 unavailable. No price-history I/O in the EA.
int McOfPrepare(string symbol,ENUM_TIMEFRAMES tf,datetime signalTime,bool historical,string &error,int laneOverride=-1)
{
   error="";if(g_mcOf.mode==0)return 1;
   string key=McOfCacheKey(symbol,tf,signalTime);
   for(int i=0;i<256;i++)if(g_mcOfCache[i].key==key)return 1;
   int lane=laneOverride==2?2:(historical?1:0);
   string owner=symbol+"/"+(string)tf+McOfIdentity();
   if(g_mcOfOwners[lane]!=owner||g_mcOfHandles[lane]==INVALID_HANDLE)
   {
      if(g_mcOfMail[lane]!="")GlobalVariableDel(g_mcOfMail[lane]+"alive");
      if(g_mcOfHandles[lane]!=INVALID_HANDLE)IndicatorRelease(g_mcOfHandles[lane]);
      if(g_mcOfMail[lane]!="")GlobalVariablesDeleteAll(g_mcOfMail[lane]);
      g_mcOfMail[lane]="MCOF."+(string)ChartID()+"."+(string)GetMicrosecondCount()+"."+(string)lane+".";
      string fields[]={"alive","request","ready","state","code","poc","val","vah","count","buy","sell","neutral","activity","delta","close","high","low"};
      for(int f=0;f<ArraySize(fields);f++)
      {
         if(!GlobalVariableTemp(g_mcOfMail[lane]+fields[f])){error="OF_DATA_MAILBOX";return -1;}
         GlobalVariableSet(g_mcOfMail[lane]+fields[f],0);
      }
      GlobalVariableSet(g_mcOfMail[lane]+"alive",1);
      g_mcOfRequests[lane]=0;g_mcOfOwners[lane]=owner;
      g_mcOfHandles[lane]=iCustom(symbol,tf,"MaCrossOrderFlowWorker",g_mcOfMail[lane],McOfConfigText(g_mcOf));
      if(g_mcOfHandles[lane]==INVALID_HANDLE){error="OF_DATA_WORKER_MISSING";return -1;}
   }
   string box=g_mcOfMail[lane];
   if(g_mcOfRequests[lane]!=signalTime)
   {
      g_mcOfRequests[lane]=signalTime;g_mcOfRequestedMs[lane]=GetTickCount64();
      GlobalVariableSet(box+"ready",0);GlobalVariableSet(box+"request",(double)signalTime);
   }
   if((datetime)GlobalVariableGet(box+"ready")!=signalTime)
   {error=GetTickCount64()-g_mcOfRequestedMs[lane]>35000?"OF_DATA_WORKER_TIMEOUT":"OF_DATA_PENDING";return error=="OF_DATA_PENDING"?0:-1;}
   int state=(int)GlobalVariableGet(box+"state");
   if(state!=1)
   {
      error="OF_DATA_"+(state<0?"UNAVAILABLE":"PENDING")+" code="+(string)(int)GlobalVariableGet(box+"code");
      if(GetTickCount64()-g_mcOfRequestedMs[lane]>35000){error="OF_DATA_WORKER_TIMEOUT";return -1;}
      return state<0?-1:0;
   }
   McOfCached result;ZeroMemory(result);result.key=key;result.snapshot.valid=true;
   result.snapshot.poc=GlobalVariableGet(box+"poc");result.snapshot.val=GlobalVariableGet(box+"val");result.snapshot.vah=GlobalVariableGet(box+"vah");
   result.snapshot.profileCount=GlobalVariableGet(box+"count");result.snapshot.buy=GlobalVariableGet(box+"buy");
   result.snapshot.sell=GlobalVariableGet(box+"sell");result.snapshot.neutral=GlobalVariableGet(box+"neutral");
   result.snapshot.activity=GlobalVariableGet(box+"activity");result.snapshot.delta=GlobalVariableGet(box+"delta");
   result.signal.time=signalTime;result.signal.close=GlobalVariableGet(box+"close");
   result.signal.high=GlobalVariableGet(box+"high");result.signal.low=GlobalVariableGet(box+"low");
   if((datetime)GlobalVariableGet(box+"ready")!=signalTime){error="OF_DATA_PENDING";return 0;}
   if(result.snapshot.profileCount<=0||!MathIsValidNumber(result.snapshot.delta)||MathAbs(result.snapshot.delta)>1
      ||!MathIsValidNumber(result.snapshot.activity)||result.snapshot.activity<0||result.snapshot.val>result.snapshot.vah
      ||result.signal.low>result.signal.close||result.signal.close>result.signal.high)
   {error="OF_DATA_INVALID_RESPONSE";return -1;}
   g_mcOfCache[g_mcOfNext]=result;g_mcOfNext=(g_mcOfNext+1)%256;return 1;
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
   string key=McOfCacheKey(symbol,tf,signalTime);
   McOfSnapshot snapshot;MqlRates signal;ZeroMemory(snapshot);ZeroMemory(signal);bool found=false;
   for(int i=0;i<256;i++)if(g_mcOfCache[i].key==key)
   {snapshot=g_mcOfCache[i].snapshot;signal=g_mcOfCache[i].signal;found=true;break;}
   if(!found)
   {
      string error="";int state=McOfPrepare(symbol,tf,signalTime,g_mcOfAuditContext,error);
      if(state!=1)
      {
         reason=error;detail="ORDERFLOW: "+error;g_mcOfStatus=detail;
         if(g_mcOfAuditContext&&state<0)g_mcOfDataIncomplete=true;
         return false;
      }
      int slot=(g_mcOfNext+255)%256;snapshot=g_mcOfCache[slot].snapshot;signal=g_mcOfCache[slot].signal;
   }
   bool allowed=McOfAllows(g_mcOf,snapshot,signal,direction);
   detail="OF_QUOTE_PROXY val="+DoubleToString(snapshot.val,8)+" vah="+DoubleToString(snapshot.vah,8)
      +" poc="+DoubleToString(snapshot.poc,8)+" activity="+DoubleToString(snapshot.activity,4)
      +" delta="+DoubleToString(snapshot.delta,4)+" direction="+(string)direction;
   reason=allowed?"":"OF_BLOCK";g_mcOfStatus=allowed?"QUOTE PROXY: PASS":"QUOTE PROXY: BLOCK";
   return allowed;
}
#endif
