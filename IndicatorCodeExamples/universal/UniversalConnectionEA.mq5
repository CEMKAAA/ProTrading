#property strict
#property version "1.03"
#property description "Stratum subscriber connection. Starts in standby. Trading requires leased web authority."
#include "generated/sdk.mqh"

bool g_ucTrading=false;
ulong g_ucAuthorityUntil=0;
bool g_ucLiveContext=false;
string g_ucInstallation="",g_ucRealm="";
datetime g_ucAuditAsOf=0;
datetime UcAuditNow(){return g_ucAuditAsOf>0?g_ucAuditAsOf:TimeCurrent();}
bool UcCanEnter(){return g_ucLiveContext&&g_ucTrading&&GetTickCount64()<g_ucAuthorityUntil&&!MQLInfoInteger(MQL_TESTER);}
bool UcObjectCreate(long chart,string name,ENUM_OBJECT type,int window,datetime t,double p,datetime t2=0,double p2=0,datetime t3=0,double p3=0){return false;}
bool UcObjectDelete(long chart,string name){return false;}
int UcObjectsDeleteAll(long chart,string prefix,int window=-1,int type=-1){return 0;}
int UcObjectsDeleteAll(long chart,int window=-1,int type=-1){return 0;}
string UcVariableKey(string key)
{
   // Existing OF indicator worker owns a unique ChartID/microsecond mailbox.
   // Its public IPC keys must remain identical on both sides.
   if(StringFind(key,"MCOF.")==0)return key;
   ulong h=2166136261;for(int i=0;i<StringLen(key);i++)h=(h^(ulong)StringGetCharacter(key,i))*16777619;
   return "UC."+StringSubstr(g_ucInstallation,0,18)+"."+g_ucRealm+"."+(string)h;
}
bool UcVariableCheck(string key){return GlobalVariableCheck(UcVariableKey(key));}
double UcVariableGet(string key){return GlobalVariableGet(UcVariableKey(key));}
datetime UcVariableSet(string key,double value){return GlobalVariableSet(UcVariableKey(key),value);}
bool UcVariableDel(string key){return GlobalVariableDel(UcVariableKey(key));}
bool UcVariableSetOnCondition(string key,double value,double expected){return GlobalVariableSetOnCondition(UcVariableKey(key),value,expected);}
bool UcVariableTemp(string key){return GlobalVariableTemp(UcVariableKey(key));}
bool UcLocalSettingExists(string key){return false;}
class UcTrade: public CTrade
{
public:
   bool PositionOpen(const string symbol,const ENUM_ORDER_TYPE type,const double volume,const double price,
                     const double sl,const double tp,const string comment="")
   {if(!UcCanEnter())return false;return CTrade::PositionOpen(symbol,type,volume,price,sl,tp,comment);}
   bool Buy(const double volume,const string symbol=NULL,double price=0,const double sl=0,const double tp=0,const string comment="")
   {if(!UcCanEnter())return false;return CTrade::Buy(volume,symbol,price,sl,tp,comment);}
   bool Sell(const double volume,const string symbol=NULL,double price=0,const double sl=0,const double tp=0,const string comment="")
   {if(!UcCanEnter())return false;return CTrade::Sell(volume,symbol,price,sl,tp,comment);}
};
#include "generated/orb.mqh"
#include "generated/macross.mqh"
#include "generated/sol.mqh"
#include "generated/entrylab.mqh"
#include "generated/live_orb.mqh"
#include "generated/live_macross.mqh"
#include "generated/live_sol.mqh"
#include "generated/live_entrylab.mqh"
#include "generated/orb_settings.mqh"
#include "generated/macross_settings.mqh"
#include "generated/sol_settings.mqh"
#include "generated/entrylab_settings.mqh"
#include "UniversalRuntime.mqh"

int OnInit(){return UcInit();}
void OnDeinit(const int reason){UcShutdown();}
void OnTick(){UcLiveTick();}
void OnTimer(){UcTimer();}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result){UcTransaction(trans,request,result);}
