#property strict
// No EA event loop and no orders: emulate two owned BTC positions.
int selectionCalls=0,selectionOpen=2;
string selectionSymbol="BTCUSDm";
#include <Trade/Trade.mqh>
class SelectionTrade:public CTrade
{
public:
   bool PositionClose(const ulong ticket,const ulong deviation=ULONG_MAX)
   {selectionCalls++;return false;}
   bool PositionClose(const string symbol,const ulong deviation=ULONG_MAX)
   {selectionCalls++;return false;}
   bool PositionModify(const ulong ticket,const double sl,const double tp)
   {selectionCalls++;return false;}
   bool PositionModify(const string symbol,const double sl,const double tp)
   {selectionCalls++;return false;}
};
long RuntimeMagic();
int SelectionPositionsTotal(){return selectionOpen;}
ulong SelectionPositionGetTicket(int i){return i>=0&&i<selectionOpen?(ulong)(910000+i):0;}
string SelectionPositionGetString(ENUM_POSITION_PROPERTY_STRING key){return key==POSITION_SYMBOL?selectionSymbol:"";}
bool SelectionPositionGetString(ENUM_POSITION_PROPERTY_STRING key,string &value)
{value=SelectionPositionGetString(key);return true;}
long SelectionPositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER key)
{return key==POSITION_MAGIC?RuntimeMagic():0;}
bool SelectionPositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER key,long &value)
{value=SelectionPositionGetInteger(key);return true;}
long SelectionAccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER key)
{if(key==ACCOUNT_MARGIN_MODE)return ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;if(key==ACCOUNT_LOGIN)return 828282;return AccountInfoInteger(key);}
bool SelectionOrderSend(const MqlTradeRequest &request,MqlTradeResult &result){selectionCalls++;return false;}
#define CTrade SelectionTrade
#define PositionsTotal SelectionPositionsTotal
#define PositionGetTicket SelectionPositionGetTicket
#define PositionGetString SelectionPositionGetString
#define PositionGetInteger SelectionPositionGetInteger
#define AccountInfoInteger SelectionAccountInfoInteger
#define OrderSend SelectionOrderSend
#define OrderSendAsync SelectionOrderSend
#define _Symbol selectionSymbol
#define OnInit SelectionInit
#define OnDeinit SelectionDeinit
#define OnTick SelectionTick
#define OnTimer SelectionTimer
#define OnChartEvent SelectionEvent
#define OnTradeTransaction SelectionTransaction
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
#undef OrderSend
#undef OrderSendAsync
#undef CTrade
#undef _Symbol
int selectionChecks=0,selectionFailed=0;
void SelectionCheck(bool value,string name)
{selectionChecks++;if(!value)selectionFailed++;Print(value?"BTC_SELECTION_PASS ":"BTC_SELECTION_FAIL ",name);}
void SelectionExpectImage(int i)
{
   double expected[],actual[];string name="";
   SelectionCheck(LiqImageRead(LiqImagePath(i),name,expected),"BTC image readable");
   SelectionCheck(LiqLibraryApply(LiqImagePath(i)),"BTC strategy applies with owned positions");
   LiqLibraryCapture(actual);bool same=ArraySize(expected)==ArraySize(actual);
   for(int k=0;same&&k<ArraySize(actual);k++)same=actual[k]==expected[k];
   SelectionCheck(same&&g_liqLibraryName==name&&g_liqLibrarySelected==LiqImagePath(i),"all image settings and selected identity applied");
   SelectionCheck(g_configRefreshPending&&g_configRefreshRebuildSignals,"audit refresh queued");
   LnNasPolicy old;bool required=false,inverse=false;
   LnNasPositionPolicy(910000,old,required,inverse);
   SelectionCheck(old.gate==2&&old.exitMode==2&&old.sensitivity==6
      &&old.reverseWaitMinutes==45&&!old.reverseExit&&inverse&&!required,"old policy remains immutable");
   SelectionCheck(GetPlan(910000,"entry")==80000&&GetPlan(910000,"sl")==79000
      &&GetPlan(910000,"target")==81000&&GetPlan(910000,"hc")==0,"old entry SL TP and half-close plan unchanged");
   SelectionCheck(selectionCalls==0&&LnNasOpenCount()==2,"no existing order closed modified or submitted");
}
void OnStart()
{
   Print("BTC_SELECTION_START no EA handlers or live orders");
   g_btRunning=false;ArrayFree(g_bridgePending);g_eaEnabled=false;LnNasDefaults(g_lnNas);
   g_lnNas.gate=2;g_lnNas.exitMode=2;g_lnNas.sensitivity=6;g_lnNas.reverseExit=false;
   g_lnNas.reverseWaitMinutes=45;g_invertMode=true;g_targetModel=ERL_TARGET_FIXED_R;
   for(int day=0;day<7;day++)g_tcalDayHours[day]=16777215;
   for(ulong ticket=910000;ticket<910003;ticket++)
   {for(int k=0;k<ArraySize(g_lnNasPlanFields);k++)GlobalVariableDel(TicketKey(ticket,g_lnNasPlanFields[k]));GlobalVariableDel(TicketKey(ticket,"nasVersion"));}
   SetPlan(910000,"entry",80000);SetPlan(910000,"sl",79000);SetPlan(910000,"target",81000);SetPlan(910000,"hc",0);
   int first=-1,second=-1;
   for(int i=0;i<ArraySize(g_liqImagePresets);i++)
   {if(g_liqImagePresets[i].name=="btcgoon")first=i;if(g_liqImagePresets[i].name=="BTCUSDLiqNarrative")second=i;}
   SelectionCheck(first>=0&&second>=0,"both BTC strategies found");
   if(first>=0&&second>=0)
   {
      SelectionExpectImage(first);SelectionExpectImage(second);
      LnNasPolicy next;LnNasDefaults(next);
      SelectionCheck(LnNasPack(g_lnNas)==LnNasPack(next)&&!g_tcalEnabled,"image selection clears inherited filters");
      SelectionCheck(LnNasStorePositionPolicy(910002),"future trade snapshots new policy");
      LnNasPolicy saved;bool required=false,inverse=false;LnNasPositionPolicy(910002,saved,required,inverse);
      SelectionCheck(LnNasPack(saved)==LnNasPack(next)&&!inverse,"future trade uses new strategy policy");
      string chosen=g_liqLibrarySelected;double before[],after[];LiqLibraryCapture(before);
      g_btRunning=true;SelectionCheck(!LiqLibraryApply(LiqImagePath(first)),"running backtest still protected");g_btRunning=false;
      ArrayResize(g_bridgePending,1);SelectionCheck(!LiqLibraryApply(LiqImagePath(first)),"pending bridge still protected");ArrayFree(g_bridgePending);
      SelectionCheck(!LiqLibraryApply("no_such_btc_strategy.lns"),"invalid strategy rejected");
      LiqLibraryCapture(after);bool unchanged=ArraySize(before)==ArraySize(after);
      for(int k=0;unchanged&&k<ArraySize(before);k++)unchanged=before[k]==after[k];
      SelectionCheck(unchanged&&g_liqLibrarySelected==chosen,"failed apply leaves current settings and selection unchanged");
      g_liqLibraryPanel=true;g_liqLibraryOpen=true;g_liqLibraryOpenedAt=0;
      g_liqLibraryPage=0;g_liqLibraryQuery="";g_liqLibraryFavorites=false;
      LiqLibraryScan();int slot=-1;
      for(int i=0;i<ArraySize(g_liqLibraryFiles);i++)if(g_liqLibraryFiles[i]==LiqImagePath(first))slot=i;
      SelectionCheck(slot>=0&&slot<6,"BTC choice available on first results page");
      if(slot>=0&&slot<6)
      {
         LiqLibraryDraw();ChartRedraw();string object=LiqLibraryObject("PICK"+(string)slot);
         long x=ObjectGetInteger(0,object,OBJPROP_XDISTANCE)+2;
         double y=(double)ObjectGetInteger(0,object,OBJPROP_YDISTANCE)+2;
         g_btRunning=true;
         SelectionCheck(LiqLibraryEvent(CHARTEVENT_CLICK,"",x,y)&&g_liqLibrarySelected==chosen,"blocked UI pick keeps applied selection");
         g_btRunning=false;g_liqLibraryOpenedAt=0;
         SelectionCheck(LiqLibraryEvent(CHARTEVENT_CLICK,"",x,y)&&g_liqLibraryName=="btcgoon"&&!g_liqLibraryOpen,"BTC UI pick applies and closes results");
      }
   }
   SelectionCheck(selectionCalls==0,"probe attempted no native orders");
   EventKillTimer();ObjectsDeleteAll(0,PFX);
   int out=FileOpen("SolAdvancedBtcSelectionProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(out!=INVALID_HANDLE){FileWriteString(out,"checks="+(string)selectionChecks+" failed="+(string)selectionFailed+" order_attempts="+(string)selectionCalls);FileClose(out);}
}
