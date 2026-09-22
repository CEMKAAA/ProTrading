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
#define MC_OF_CACHE_SLOTS 65536
McOfCached g_mcOfCache[MC_OF_CACHE_SLOTS];
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
void McOfReset(bool clearSnapshots=true)
{
   McOfRelease();
   if(clearSnapshots)for(int i=0;i<MC_OF_CACHE_SLOTS;i++)g_mcOfCache[i].key="";
   g_mcOfDataIncomplete=false;g_mcOfStatus=g_mcOf.mode==0?"OFF":"QUOTE PROXY / WAIT";
}
string McOfCacheKey(string symbol,ENUM_TIMEFRAMES tf,datetime signalTime)
{return symbol+"/"+(string)tf+"/"+(string)signalTime+"/"+(string)g_mcOf.lookback+"/"
   +(string)g_mcOf.bins+"/"+DoubleToString(g_mcOf.valueArea,8);}
int McOfCacheSlot(const string key)
{
   uint hash=2166136261;
   for(int i=0;i<StringLen(key);i++)hash=(hash^(uint)StringGetCharacter(key,i))*16777619;
   int start=(int)(hash%MC_OF_CACHE_SLOTS);
   for(int i=0;i<MC_OF_CACHE_SLOTS;i++)
   {
      int slot=(start+i)%MC_OF_CACHE_SLOTS;
      if(g_mcOfCache[slot].key==""||g_mcOfCache[slot].key==key)return slot;
   }
   return -1;
}
// Returns 1 ready, 0 pending, -1 unavailable. No price-history I/O in the EA.
int McOfPrepare(string symbol,ENUM_TIMEFRAMES tf,datetime signalTime,bool historical,string &error,int laneOverride=-1)
{
   error="";if(g_mcOf.mode==0)return 1;
   string key=McOfCacheKey(symbol,tf,signalTime);
   int slot=McOfCacheSlot(key);
   if(slot>=0&&g_mcOfCache[slot].key==key)return 1;
   if(slot<0)
   {
      // A multi-year M1 audit can exceed the bounded cache. Rotate instead of
      // failing the data audit or treating a capacity limit as a trade veto.
      for(int i=0;i<MC_OF_CACHE_SLOTS;i++)g_mcOfCache[i].key="";
      slot=McOfCacheSlot(key);
   }
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
   g_mcOfCache[slot]=result;return 1;
}
bool McOfInit()
{
   g_mcOf.mode=(int)InpOrderFlowMode;g_mcOf.lookback=InpOrderFlowLookback;g_mcOf.bins=InpOrderFlowBins;
   g_mcOf.valueArea=NormalizeDouble(InpOrderFlowValueArea,8);g_mcOf.minActivity=NormalizeDouble(InpOrderFlowMinActivity,8);g_mcOf.minDelta=NormalizeDouble(InpOrderFlowMinDelta,8);
   McOfReset();return McOfConfigValid(g_mcOf);
}
string McOfModeName()
{
   if(g_mcOf.mode==1)return "OF: BREAK";if(g_mcOf.mode==2)return "OF: REJECT";
   if(g_mcOf.mode==3)return "OF: EITHER";
   if(g_mcOf.mode==4)return "OF: PROFILE";
   if(g_mcOf.mode==5)return "OF: ACTIVITY";
   if(g_mcOf.mode==6)return "OF: DELTA";
   return "OF: OFF";
}
bool McOfFilter(string symbol,ENUM_TIMEFRAMES tf,datetime signalTime,int direction,string &reason,string &detail)
{
   if(g_mcOf.mode==0)return true;
   string key=McOfCacheKey(symbol,tf,signalTime);
   McOfSnapshot snapshot;MqlRates signal;ZeroMemory(snapshot);ZeroMemory(signal);bool found=false;
   int slot=McOfCacheSlot(key);
   if(slot>=0&&g_mcOfCache[slot].key==key)
   {snapshot=g_mcOfCache[slot].snapshot;signal=g_mcOfCache[slot].signal;found=true;}
   if(!found)
   {
      string error="";int state=McOfPrepare(symbol,tf,signalTime,g_mcOfAuditContext,error);
      if(state!=1)
      {
         reason=error;detail="ORDERFLOW: "+error;g_mcOfStatus=detail;
         if(g_mcOfAuditContext&&state<0)g_mcOfDataIncomplete=true;
         return false;
      }
      slot=McOfCacheSlot(key);
      if(slot<0||g_mcOfCache[slot].key!=key){reason="OF_CACHE_MISS";detail="ORDERFLOW: "+reason;return false;}
      snapshot=g_mcOfCache[slot].snapshot;signal=g_mcOfCache[slot].signal;
   }
   bool allowed=McOfAllows(g_mcOf,snapshot,signal,direction);
   detail="OF_QUOTE_PROXY val="+DoubleToString(snapshot.val,8)+" vah="+DoubleToString(snapshot.vah,8)
      +" poc="+DoubleToString(snapshot.poc,8)+" activity="+DoubleToString(snapshot.activity,4)
      +" delta="+DoubleToString(snapshot.delta,4)+" direction="+(string)direction;
   reason=allowed?"":"OF_BLOCK";g_mcOfStatus=allowed?"QUOTE PROXY: PASS":"QUOTE PROXY: BLOCK";
   return allowed;
}
#endif
