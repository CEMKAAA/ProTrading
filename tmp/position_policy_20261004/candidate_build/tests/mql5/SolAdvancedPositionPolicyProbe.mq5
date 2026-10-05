#property strict
// Simulated exposure only; this probe never starts the EA or submits orders.
bool mockExposure=false;
int mockOpen=2,mockSelected=0;
int mockCloseCalls=0,mockModifyCalls=0;
#include <Trade/Trade.mqh>
class ProbeTrade:public CTrade
{
public:
   bool PositionClose(const ulong ticket,const ulong deviation=ULONG_MAX)
   {if(!mockExposure)return CTrade::PositionClose(ticket,deviation);mockCloseCalls++;return true;}
   bool PositionClose(const string symbol,const ulong deviation=ULONG_MAX)
   {if(!mockExposure)return CTrade::PositionClose(symbol,deviation);mockCloseCalls++;return true;}
   bool PositionModify(const ulong ticket,const double sl,const double tp)
   {if(!mockExposure)return CTrade::PositionModify(ticket,sl,tp);mockModifyCalls++;return true;}
   bool PositionModify(const string symbol,const double sl,const double tp)
   {if(!mockExposure)return CTrade::PositionModify(symbol,sl,tp);mockModifyCalls++;return true;}
   uint ResultRetcode() const
   {return mockExposure?TRADE_RETCODE_DONE:CTrade::ResultRetcode();}
};
#define CTrade ProbeTrade
long RuntimeMagic();
int ProbePositionsTotal(){return mockExposure?mockOpen:PositionsTotal();}
ulong ProbePositionGetTicket(int index)
{
   if(!mockExposure)return PositionGetTicket(index);
   mockSelected=index;return index>=0&&index<mockOpen?(ulong)(900000+index):0;
}
string ProbePositionGetString(ENUM_POSITION_PROPERTY_STRING key)
{return mockExposure&&key==POSITION_SYMBOL?_Symbol:PositionGetString(key);}
bool ProbePositionGetString(ENUM_POSITION_PROPERTY_STRING key,string &value)
{if(!mockExposure)return PositionGetString(key,value);value=ProbePositionGetString(key);return true;}
long ProbePositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER key)
{
   if(!mockExposure)return PositionGetInteger(key);
   if(key==POSITION_MAGIC)return RuntimeMagic();
   if(key==POSITION_TYPE)return mockSelected%2==0?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   if(key==POSITION_TIME)return (long)TimeCurrent()-3600;
   return 0;
}
bool ProbePositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER key,long &value)
{if(!mockExposure)return PositionGetInteger(key,value);value=ProbePositionGetInteger(key);return true;}
long ProbeAccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER key)
{return mockExposure&&key==ACCOUNT_MARGIN_MODE?ACCOUNT_MARGIN_MODE_RETAIL_HEDGING:AccountInfoInteger(key);}
#define PositionsTotal ProbePositionsTotal
#define PositionGetTicket ProbePositionGetTicket
#define PositionGetString ProbePositionGetString
#define PositionGetInteger ProbePositionGetInteger
#define AccountInfoInteger ProbeAccountInfoInteger
#define OnInit PolicyInit
#define OnDeinit PolicyDeinit
#define OnTick PolicyTick
#define OnTimer PolicyTimer
#define OnChartEvent PolicyEvent
#define OnTradeTransaction PolicyTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef PositionsTotal
#undef PositionGetTicket
#undef PositionGetString
#undef PositionGetInteger
#undef AccountInfoInteger
#undef CTrade
#include "MaPositionReference.mqh"
int checks=0,failed=0;
void Check(bool value,string name){checks++;if(!value){failed++;Print("FAIL ",name);}}
void ClickTarget(string action)
{
   g_liqLibraryRPicker=true;g_liqLibraryOpen=false;g_liqLibraryOpenedAt=0;
   LiqLibraryDraw();
   if(action=="CUSTOM_APPLY")ObjectSetString(0,LiqLibraryObject("CUSTOM_VALUE"),OBJPROP_TEXT,"0.75");
   string key=LiqLibraryObject(action);
   Check(ObjectFind(0,key)>=0,"target control present");
   long x=ObjectGetInteger(0,key,OBJPROP_XDISTANCE)+2;
   double y=(double)ObjectGetInteger(0,key,OBJPROP_YDISTANCE)+2;
   Check(LiqLibraryEvent(CHARTEVENT_CLICK,"",x,y),"target click consumed");
}
void CheckNativeNasCache()
{
   datetime closed=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,1),now=TimeCurrent(),opened=now-600;
   Check(closed>0,"closed bar available for cache fixture");if(closed<=0)return;
   LnNasPolicy old;LnNasDefaults(old);old.exitMode=2;old.flowVolume=true;old.flowMultiplier=9;
   ArrayResize(g_lnNasEvents,1);ZeroMemory(g_lnNasEvents[0]);
   g_lnNasEvents[0].at=now-20;g_lnNasEvents[0].dir=1;
   g_lnNasEvents[0].stateAllowed=true;g_lnNasEvents[0].flowAllowed=true;LnNasIndexEvents();
   g_lnNasBar=closed;g_lnNasSeed=opened;g_lnNasSignature="CURRENT_FIXTURE";
   ArrayResize(g_lnNasNativeCaches,1);
   g_lnNasNativeCaches[0].key=(string)old.sensitivity+"|"+(string)old.stateVolume+"|"+DoubleToString(old.stateMultiplier,8)
      +"|"+(string)old.flowVolume+"|"+DoubleToString(old.flowMultiplier,8);
   g_lnNasNativeCaches[0].signature=_Symbol+"|"+(string)_Period+"|"+(string)old.sensitivity+"|"
      +(string)old.stateVolume+"|"+DoubleToString(old.stateMultiplier,8)+"|"
      +(string)old.flowVolume+"|"+DoubleToString(old.flowMultiplier,8);
   g_lnNasNativeCaches[0].bar=closed;g_lnNasNativeCaches[0].seed=opened;
   ArrayResize(g_lnNasNativeCaches[0].events,1);ZeroMemory(g_lnNasNativeCaches[0].events[0]);
   g_lnNasNativeCaches[0].events[0].at=opened+180;g_lnNasNativeCaches[0].events[0].dir=-1;
   g_lnNasNativeCaches[0].events[0].stateAllowed=true;g_lnNasNativeCaches[0].events[0].flowAllowed=true;
   ArrayResize(g_lnNasNativeCaches[0].state,1);g_lnNasNativeCaches[0].state[0]=0;
   ArrayResize(g_lnNasNativeCaches[0].flow,1);g_lnNasNativeCaches[0].flow[0]=0;
   ArrayResize(g_lnNasNativeCaches[0].buy,2);ArrayInitialize(g_lnNasNativeCaches[0].buy,-1);
   ArrayResize(g_lnNasNativeCaches[0].sell,2);g_lnNasNativeCaches[0].sell[0]=0;g_lnNasNativeCaches[0].sell[1]=-1;
   string current=LnNasPack(g_lnNas);ArrayFree(g_histRawCache);
   Check(LnNasNativeExitAt(old,1,opened,now)==opened+180,"open trade uses its original NAS event stream");
   Check(LnNasNativeExitAt(old,1,opened,now)==opened+180&&ArraySize(g_lnNasNativeCaches)==1,
      "original policy cache reused without downloading or rebuilding");
   Check(LnNasPack(g_lnNas)==current&&g_lnNasSignature=="CURRENT_FIXTURE"&&g_lnNasBar==closed
      &&ArraySize(g_lnNasEvents)==1&&g_lnNasEvents[0].dir==1&&g_lnNasEvents[0].at==now-20
      &&g_lnNasNextBuy[0]==0&&g_lnNasNextSell[0]==-1,"native exits leave audit/entry NAS cache untouched");
   LnNasInvalidate();ArrayFree(g_lnNasNativeCaches);
}
void CheckApplyWithExposure()
{
   mockExposure=true;g_btRunning=false;ArrayFree(g_bridgePending);
   LnNasDefaults(g_lnNas);g_lnNas.reverseExit=false;
   for(ulong ticket=900000;ticket<900004;ticket++)
   {for(int j=0;j<ArraySize(g_lnNasPlanFields);j++)GlobalVariableDel(TicketKey(ticket,g_lnNasPlanFields[j]));
      GlobalVariableDel(TicketKey(ticket,"nasVersion"));}
   g_targetModel=ERL_TARGET_FIXED_R;
   Check(LnNasOpenCount()==2,"mock owns two opposite native positions");
   Check(!LiqLibraryCanApply(),"full strategy replacement retains flat guard");
   Check(LiqLibraryCanApply(false),"filter/R edits allowed with owned positions");
   g_btRunning=true;Check(!LiqLibraryCanApply(false),"active batch backtest guard retained");g_btRunning=false;
   ArrayResize(g_bridgePending,1);Check(!LiqLibraryCanApply(false),"pending bridge guard retained");ArrayFree(g_bridgePending);
   string runtime=LiqLibraryFolder()+"\\nas_"+LiqLibraryHash(LnNasKey())+".txt",original="";
   bool existed=FileIsExist(runtime,FILE_COMMON);
   bool restore=existed&&LiqLibraryRead(runtime,original);
   Check(!existed||restore,"runtime snapshot readable");
   if(existed&&!restore){mockExposure=false;return;}
   g_lnNasDraft=g_lnNas;
   g_lnNasDraft.independent=true;g_lnNasDraft.gate=2;g_lnNasDraft.exitMode=2;
   g_lnNasDraft.stateVolume=true;g_lnNasDraft.flowVolume=true;g_lnNasDraft.reverseExit=false;
   g_lnNasPanel=true;LnNasDrawPanel();
   ObjectSetString(0,LnNasObject("SVM"),OBJPROP_TEXT,"2.75");
   ObjectSetString(0,LnNasObject("FVM"),OBJPROP_TEXT,"1.25");
   ObjectSetString(0,LnNasObject("SENS"),OBJPROP_TEXT,"6");
   ObjectSetString(0,LnNasObject("AGE"),OBJPROP_TEXT,"180");
   ObjectSetString(0,LnNasObject("MAX"),OBJPROP_TEXT,"1");
   ObjectSetString(0,LnNasObject("WAIT"),OBJPROP_TEXT,"03:20");
   ObjectSetString(0,LnNasObject("RWAIT"),OBJPROP_TEXT,"00:45");
   g_lnNasLastActionAt=0;g_configRefreshPending=false;
   Check(LnNasPanelEvent(CHARTEVENT_OBJECT_CLICK,LnNasObject("APPLY")),"NAS Apply handled with exposure");
   Check(g_lnNas.independent&&g_lnNas.maxSameOpen==1&&g_lnNas.gate==2&&g_lnNas.exitMode==2
      &&g_lnNas.stateVolume&&g_lnNas.flowVolume&&!g_lnNas.reverseExit
      &&g_lnNas.stateMultiplier==2.75&&g_lnNas.flowMultiplier==1.25&&g_lnNas.sensitivity==6
      &&g_lnNas.entryAgeMinutes==180&&g_lnNas.waitMinutes==200&&g_lnNas.reverseWaitMinutes==45,
      "NAS Apply reads every current field while MAX below exposure");
   Check(g_configRefreshPending&&g_configRefreshRebuildSignals,"NAS Apply queues audit recalculation");
   Check(LnNasOpenCount()==2,"applying lower MAX does not force liquidation");
   LnNasPolicy owned;bool required=false,inverse=false;
   LnNasPositionPolicy(900000,owned,required,inverse);
   Check(owned.gate==0&&owned.exitMode==0&&!owned.reverseExit
      &&!owned.independent&&!required&&!inverse,"owned positions retain original exit settings");
   Check(LnNasPreserveOwnedPolicies(),"repeated Apply can preserve owned settings");
   LnNasPositionPolicy(900000,owned,required,inverse);
   Check(owned.gate==0&&owned.exitMode==0,"repeated Apply cannot overwrite an open position snapshot");
   string packed=LnNasPack(g_lnNas);
   Check(LnNasLoadRuntime()&&LnNasPack(g_lnNas)==packed,"applied NAS settings survive reload");
   Check(LnNasStorePositionPolicy(900002),"future trade stores new exit policy");
   LnNasPositionPolicy(900002,owned,required,inverse);
   Check(LnNasPack(owned)==packed,"future trade uses newly applied NAS policy");
   LnNasCopyPositionPolicy(900002,900003);
   LnNasPositionPolicy(900003,owned,required,inverse);
   Check(LnNasPack(owned)==packed,"position identifier migration retains policy");
   g_lnNas.reverseExit=true;g_lnNas.reverseWaitMinutes=0;
   // Old reverse OFF must remain OFF even if the new global policy enables it.
   Check(LnNasCloseCausalReverse(TimeCurrent(),1,false),"reverse close dispatch succeeds");
   Check(mockCloseCalls==0,"old reverse OFF stays OFF when new settings enable reverse");
   g_lnNas.reverseExit=false;
   SetPlan(900001,"nasReverse",1);SetPlan(900001,"nasRWait",1);
   Check(LnNasCloseCausalReverse(TimeCurrent(),1,false)&&mockCloseCalls==1,
      "old reverse ON stays ON when new settings disable reverse");
   mockCloseCalls=0;
   LnNasManageNative();Check(mockCloseCalls==0,"new NAS exit cannot retroactively close old NAS-OFF positions");
   SetPlan(900001,"nasReverse",0);SetPlan(900001,"nasRWait",0);
   CheckNativeNasCache();
   g_lnNas.gate=0;g_lnNas.exitMode=0;g_fileBridgeOnlyMode=false;
   ErlSignal signal;ZeroMemory(signal);signal.dir=1;signal.availableTime=TimeCurrent();
   Check(!LnNasLiveAccept(signal)&&g_lastBlock=="MAX_OPEN","lower MAX blocks only future entries");
   g_lnNasPanel=false;DeleteByPrefix(PFX+"NAS_");
   g_configRefreshPending=false;ClickTarget("CUSTOM_APPLY");
   Check(g_target==ERL_RR_CUSTOM&&TargetR(g_target)==0.75&&!g_liqLibraryRPicker
      &&g_configRefreshPending,"custom R applies with owned positions and queues audit");
   g_configRefreshPending=false;ClickTarget("RSTEP100");
   Check(TargetR(g_target)==5.0&&!g_liqLibraryRPicker&&g_configRefreshPending,
      "preset R applies with owned positions and queues audit");
   Check(LnNasOpenCount()==2,"R edits do not liquidate positions");
   Check(mockCloseCalls==0&&mockModifyCalls==0,"Apply never closes or modifies existing native orders");
   for(ulong ticket=900000;ticket<900004;ticket++)
   {for(int j=0;j<ArraySize(g_lnNasPlanFields);j++)GlobalVariableDel(TicketKey(ticket,g_lnNasPlanFields[j]));
      GlobalVariableDel(TicketKey(ticket,"nasVersion"));}
   if(restore)Check(LiqLibraryAtomicWrite(runtime,original),"runtime fixture restored");
   else Check(FileDelete(runtime,FILE_COMMON),"runtime fixture removed");
   mockExposure=false;g_configRefreshPending=false;g_configRefreshRebuildSignals=false;
   EventKillTimer();
}
void CheckMaReference()
{
   PolicyMaEvent reference[];ErlSignal events[];
   ArrayResize(reference,6);ArrayResize(events,6);
   int times[]={990,1000,1100,1250,1300,1450},opened[]={1000,1100,1300};
   int waits[]={0,1,5,30},through[]={950,1000,1100,1250,1300,1450,1500,3000};
   g_lnNas.reverseExit=true;
   for(int mask=0;mask<64;mask++)for(int inv=0;inv<2;inv++)
   {
      g_invertMode=inv!=0;
      for(int i=0;i<6;i++)
      {
         reference[i].signalTime=times[i]-60;reference[i].direction=(mask&(1<<i))!=0?1:-1;
         ZeroMemory(events[i]);events[i].availableTime=times[i];events[i].dir=reference[i].direction;
      }
      for(int d=-1;d<=1;d+=2)for(int o=0;o<3;o++)for(int w=0;w<4;w++)for(int u=0;u<8;u++)
         Check(LnNasReverseAt(events,d,opened[o],through[u],waits[w])
            ==ReferenceMaKernelExitAt(reference,opened[o],d,through[u],waits[w],60,inv!=0),
            "MaCross exact reverse reference");
   }
   g_invertMode=false;
}
void OnStart()
{
   LnNasDefaults(g_lnNas);g_invertMode=false;
   LnNasPolicy copy;
   Check(LnNasUnpack(LnNasPack(g_lnNas),copy)&&copy.reverseExit==InpCloseOnReverse&&!copy.independent,"existing defaults preserved");
   g_lnNas.independent=true;g_lnNas.maxSameOpen=20;g_lnNas.reverseWaitMinutes=30;g_lnNas.reverseExit=false;
   Check(LnNasUnpack(LnNasPack(g_lnNas),copy)&&LnNasPack(copy)==LnNasPack(g_lnNas),"all position settings round trip");
   ErlSignal raw[];ArrayResize(raw,4);
   for(int i=0;i<4;i++)ZeroMemory(raw[i]);
   raw[0].availableTime=990;raw[0].dir=-1;
   raw[1].availableTime=1100;raw[1].dir=-1;
   raw[2].availableTime=1250;raw[2].dir=1;
   raw[3].availableTime=1450;raw[3].dir=-1;
   Check(LnNasReverseAt(raw,1,1000,5000,5)==0,"reverse OFF");
   g_lnNas.reverseExit=true;
   Check(LnNasReverseAt(raw,1,1000,1200,5)==0,"wait pending");
   Check(LnNasReverseAt(raw,1,1000,1400,5)==0,"latest same side cancels wait latch");
   Check(LnNasReverseAt(raw,1,1000,1500,5)==1450,"post-wait opposite closes");
   ArrayResize(raw,2);
   Check(LnNasReverseAt(raw,1,1000,1400,5)==1300,"grace latch expiry");
   ArrayResize(raw,1);
   Check(LnNasReverseAt(raw,1,1000,5000,5)==0,"pre-entry excluded");
   g_lnNas.independent=true;g_lnNas.maxSameOpen=1;
   ArrayResize(g_histSignals,2);ArrayResize(g_histSignalValid,2);ArrayResize(g_histSignalClosed,2);
   ArrayResize(g_histSignalExitTime,2);ArrayResize(g_histSignalInvalidReason,2);
   ZeroMemory(g_histSignals[0]);ZeroMemory(g_histSignals[1]);
   g_histSignals[0].dir=1;g_histSignals[0].availableTime=1000;
   g_histSignals[1].dir=1;g_histSignals[1].availableTime=1100;
   g_histSignalValid[0]=true;g_histSignalClosed[0]=false;g_histSignalInvalidReason[0]="";
   Check(LnNasAuditCap(1)==1,"MAX total concurrent same-side");
   g_histSignals[1].dir=-1;
   Check(LnNasAuditCap(1)==1,"MAX total blocks independent opposite too");
   g_histSignals[1].dir=1;g_histSignalClosed[0]=true;g_histSignalExitTime[0]=1100;
   Check(LnNasAuditCap(1)==0,"same timestamp completed exit releases slot");
   g_lnNas.independent=false;g_lnNas.reverseExit=false;g_histSignals[1].dir=-1;g_histSignalClosed[0]=false;
   Check(LnNasAuditCap(1)==1,"legacy reverse OFF blocks second position");
   g_histSignalInvalidReason[0]="LEGACY_ACTIVE";g_histSignalValid[0]=false;
   Check(LnNasAuditCap(1)==0,"rejected entries consume no slot");
   g_lnNas.independent=true;g_lnNas.maxSameOpen=10;g_lnNas.reverseExit=false;
   ArrayResize(g_histSignals,12);ArrayResize(g_histSignalValid,12);ArrayResize(g_histSignalClosed,12);
   ArrayResize(g_histSignalExitTime,12);ArrayResize(g_histSignalInvalidReason,12);
   for(int n=0;n<12;n++)
   {
      ZeroMemory(g_histSignals[n]);g_histSignals[n].availableTime=1000+n;g_histSignals[n].dir=n<6?1:-1;
      g_histSignalValid[n]=true;g_histSignalClosed[n]=false;g_histSignalExitTime[n]=0;
      g_histSignalInvalidReason[n]="";
      if(n<=10)Check((LnNasAuditCap(n)==0)==ReferenceMaOpenCapacityAllows(n,10),"MaCross total capacity reference");
   }
   g_histSignalInvalidReason[10]="MAX_OPEN";g_histSignalValid[10]=false;
   g_invertMode=true;
   Check(LnNasAuditCap(10)==1,"inverse capacity follows actual audited OPEN trades");
   g_invertMode=false;
   g_histSignalClosed[0]=true;g_histSignalExitTime[0]=1011;
   Check(LnNasAuditCap(11)==0,"mixed 6 BUY + 4 SELL releases total slot; blocked entry excluded");
   g_histSignalValid[0]=false;g_histSignalClosed[0]=false;
   Check(LnNasAuditCap(11)==-1,"unknown opposite-side capacity remains DATA");
   g_lnNas.maxSameOpen=1000;g_lnNas.reverseWaitMinutes=5999;
   Check(LnNasUnpack(LnNasPack(g_lnNas),copy),"MaCross MAX and duration ranges persist");
   int wait=0;
   Check(LnNasParseDuration("99:59",wait,5999)&&wait==5999,"MaCross reverse wait range");
   Check(!LnNasParseDuration("25:00",wait),"NAS wait range unchanged");
   CheckMaReference();
   CheckApplyWithExposure();
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed);FileClose(f);}
}
