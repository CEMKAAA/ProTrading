#property strict
#include <Trade/Trade.mqh>
bool g_visualFixture=false;
int g_visualSelected=-1;
struct VisualFixturePosition {ulong id;long magic;datetime opened;double entry,sl,tp;int dir;};
VisualFixturePosition g_visualPositions[];
int VisualPositionsTotal(){return g_visualFixture?ArraySize(g_visualPositions):PositionsTotal();}
ulong VisualPositionTicket(int i)
{
   if(!g_visualFixture)return PositionGetTicket(i);
   if(i<0||i>=ArraySize(g_visualPositions))return 0;g_visualSelected=i;return g_visualPositions[i].id;
}
bool VisualPositionSelect(ulong id)
{
   if(!g_visualFixture)return PositionSelectByTicket(id);
   for(int i=0;i<ArraySize(g_visualPositions);i++)if(g_visualPositions[i].id==id){g_visualSelected=i;return true;}
   return false;
}
long VisualPositionInteger(ENUM_POSITION_PROPERTY_INTEGER key)
{
   if(!g_visualFixture)return PositionGetInteger(key);
   if(g_visualSelected<0)return 0;
   if(key==POSITION_MAGIC)return g_visualPositions[g_visualSelected].magic;
   if(key==POSITION_IDENTIFIER)return (long)g_visualPositions[g_visualSelected].id;
   if(key==POSITION_TIME)return (long)g_visualPositions[g_visualSelected].opened;
   if(key==POSITION_TYPE)return g_visualPositions[g_visualSelected].dir>0?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   return 0;
}
bool VisualPositionInteger(ENUM_POSITION_PROPERTY_INTEGER key,long &value){value=VisualPositionInteger(key);return true;}
double VisualPositionDouble(ENUM_POSITION_PROPERTY_DOUBLE key)
{
   if(!g_visualFixture)return PositionGetDouble(key);
   if(g_visualSelected<0)return 0;
   if(key==POSITION_PRICE_OPEN)return g_visualPositions[g_visualSelected].entry;
   if(key==POSITION_SL)return g_visualPositions[g_visualSelected].sl;
   if(key==POSITION_TP)return g_visualPositions[g_visualSelected].tp;
   return 0;
}
bool VisualPositionDouble(ENUM_POSITION_PROPERTY_DOUBLE key,double &value){value=VisualPositionDouble(key);return true;}
string VisualPositionString(ENUM_POSITION_PROPERTY_STRING key)
{
   if(!g_visualFixture)return PositionGetString(key);
   if(key==POSITION_SYMBOL)return _Symbol;
   if(key==POSITION_COMMENT)return "MAI|1791059400";
   return "";
}
bool VisualPositionString(ENUM_POSITION_PROPERTY_STRING key,string &value){value=VisualPositionString(key);return true;}
#define PositionsTotal VisualPositionsTotal
#define PositionGetTicket VisualPositionTicket
#define PositionSelectByTicket VisualPositionSelect
#define PositionGetInteger VisualPositionInteger
#define PositionGetDouble VisualPositionDouble
#define PositionGetString VisualPositionString
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "../../IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
int g_visualChecks=0,g_visualFailed=0;
int g_visualReport=INVALID_HANDLE;
void VisualCheck(bool ok,string message)
{
   g_visualChecks++;if(!ok){g_visualFailed++;FileWriteString(g_visualReport,"FAIL "+message+"\r\n");}
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   ulong start=GetTickCount64();while(!TerminalInfoInteger(TERMINAL_CONNECTED)&&GetTickCount64()-start<45000)Sleep(250);
   g_visualReport=FileOpen("EntryLabNativeVisualProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_visualReport==INVALID_HANDLE)return;
   VisualCheck(TerminalInfoInteger(TERMINAL_CONNECTED),"connected worker");
   PREFIX="LAB_VIS_PROBE_";g_runtimeMagic=4000011026004262155;
   g_maIndependent=true;g_rtSignalTf=PERIOD_M5;g_rtHistoricalWeeks=2;
   MqlRates bars[];CopyRates(_Symbol,PERIOD_M1,0,20,bars);
   g_visualFixture=true;ArrayResize(g_visualPositions,4);
   datetime opened=(datetime)((long)(TimeCurrent()-600)/60*60);double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   for(int i=0;i<4;i++)
   {
      g_visualPositions[i].id=(ulong)(990000001+i);g_visualPositions[i].magic=RuntimeMagic()+(i==3?1:0);
      g_visualPositions[i].opened=opened;g_visualPositions[i].dir=i==1?1:-1;
      g_visualPositions[i].entry=price+i;g_visualPositions[i].sl=price+i+(i==1?-5000:5000);
      g_visualPositions[i].tp=price+i+(i==1?50:-50);
   }
   DrawOrbLiveTradeLevels();ChartRedraw();
   for(int i=0;i<3;i++)
   {
      string base=LabNativeVisualBase(g_visualPositions[i].id);
      VisualCheck(ObjectFind(0,base+"ENTRY")>=0&&ObjectFind(0,base+"SL")>=0&&ObjectFind(0,base+"TP")>=0,"all concurrent positions retain geometry");
      VisualCheck(ObjectGetDouble(0,base+"ENTRY",OBJPROP_PRICE,0)==g_visualPositions[i].entry,"actual entry retained");
      VisualCheck(ObjectGetInteger(0,base+"ARW",OBJPROP_COLOR)==clrGold,"open arrow is neutral, not a sell loss");
   }
   VisualCheck(ObjectFind(0,LabNativeVisualBase(g_visualPositions[3].id)+"ARW")<0,"foreign instance excluded");
   ulong winner=g_visualPositions[0].id;
   LabNativeVisualDraw(winner,-1,opened,opened-300,price,price+5000,price-50,opened+2,5,"[tp]");
   string base=LabNativeVisualBase(winner);ChartRedraw();
   VisualCheck(ObjectGetInteger(0,base+"ARW",OBJPROP_COLOR)==clrLime,"winning sell is green");
   VisualCheck(ObjectGetInteger(0,base+"TP",OBJPROP_TIME,1)-ObjectGetInteger(0,base+"TP",OBJPROP_TIME,0)==60,"same-candle close has one displayed candle of geometry");
   VisualCheck(StringFind(ObjectGetString(0,base+"TXT",OBJPROP_TEXT),"SL=")>=0&&StringFind(ObjectGetString(0,base+"TXT",OBJPROP_TEXT),"TP=")>=0,"closed levels have numeric labels");
   g_visualPositions[0]=g_visualPositions[2];g_visualPositions[1]=g_visualPositions[3];ArrayResize(g_visualPositions,2);
   DrawOrbLiveTradeLevels();ChartRedraw();
   VisualCheck(ObjectFind(0,base+"ENTRY")>=0&&ObjectGetInteger(0,base+"ARW",OBJPROP_COLOR)==clrLime,"refresh does not remove or reset closed result");
   LabNativeVisualDraw(winner,-1,opened,opened-300,price,price+5000,price-50,opened+2,-0.2,"[tp]");
   VisualCheck(ObjectGetInteger(0,base+"ARW",OBJPROP_COLOR)==clrTomato,"cost-negative TP is not falsely green");
   VisualCheck(MathAbs(LabNativeDealNet(5,-1,-3,-2)+1)<1e-9,"profit includes swap, commission and fees");
   VisualCheck(LabNativeResultColor(0)==clrLightSteelBlue,"breakeven is neutral");
   g_visualFixture=false;DeleteByPrefix(PREFIX+"NATIVE_");
   LabNativeVisualRestore();int count=ArraySize(g_labVisualPending),closed=0,positive=0,open=0;
   ulong ids[];ArrayCopy(ids,g_labVisualPending);
   for(int i=0;i<ArraySize(ids);i++)
   {
      if(OrbProPositionStillOpen(ids[i])){open++;continue;}
      if(!HistorySelectByPosition(ids[i]))continue;
      double net=0;datetime end=0;bool owned=false;
      for(int j=0;j<HistoryDealsTotal();j++)
      {
         ulong deal=HistoryDealGetTicket(j);long type=HistoryDealGetInteger(deal,DEAL_TYPE);
         if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
         net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)
            +HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN&&MagicOwned((long)HistoryDealGetInteger(deal,DEAL_MAGIC)))owned=true;
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_OUT)end=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      }
      if(!owned||end==0)continue;
      VisualCheck(LabNativeVisualFromHistory(ids[i]),"native history result reconstructs");closed++;if(net>0)positive++;
      string native=LabNativeVisualBase(ids[i]);ChartRedraw();
      VisualCheck(ObjectGetInteger(0,native+"ARW",OBJPROP_COLOR)==LabNativeResultColor(net),"broker net PnL matches native arrow color");
      VisualCheck(ObjectFind(0,native+"ENTRY")>=0&&ObjectFind(0,native+"SL")>=0&&ObjectFind(0,native+"TP")>=0,"closed broker trades retain all actual levels");
      if(closed<=15)FileWriteString(g_visualReport,"REAL id="+(string)ids[i]+" net="+DoubleToString(net,2)+" closed="+FmtTime(end)+"\r\n");
   }
   LabNativeVisualRefreshOpen();
   MqlTick quote;ZeroMemory(quote);SymbolInfoTick(_Symbol,quote);
   FileWriteString(g_visualReport,"QUOTE bid="+DoubleToString(quote.bid,_Digits)+" ask="+DoubleToString(quote.ask,_Digits)+"\r\n");
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!IsOwnPosition())continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);string native=LabNativeVisualBase(id);
      VisualCheck(ObjectFind(0,native+"ENTRY")>=0&&ObjectFind(0,native+"SL")>=0&&ObjectFind(0,native+"TP")>=0,"all currently open real positions retain geometry");
      FileWriteString(g_visualReport,"OPEN id="+(string)id+" dir="+(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL")
         +" entry="+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),_Digits)+" tp="+DoubleToString(PositionGetDouble(POSITION_TP),_Digits)
         +" pnl="+DoubleToString(PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP),2)+"\r\n");
   }
   VisualCheck(closed>0&&positive>0,"real strategy history contains positive closes");
   FileWriteString(g_visualReport,"checked="+(string)g_visualChecks+" failed="+(string)g_visualFailed+" queued="+(string)count
      +" real_closed="+(string)closed+" positive="+(string)positive+" still_open="+(string)open+"\r\n");
   FileClose(g_visualReport);DeleteByPrefix(PREFIX);ChartRedraw();
}
