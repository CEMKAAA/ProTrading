//+------------------------------------------------------------------+
//| NAS Ultimate Signal Lab v2.2 â€” PRODUCTION                         |
//| Toggleable signal modes + HC+BE partial close + full execution.    |
//| FTMO-grade account risk, spread governor, TP watchdog.             |
//| Signal source: NasUltimate_Core.mqh                                |
//+------------------------------------------------------------------+
#property strict
#property version "2.20"
#include <Trade/Trade.mqh>
#include "NasUltimate_Core.mqh"

#define NAS_V2_BUILD "2026-06-16.v2.4-bt-effective-window"

//=====================================================================
//  ENUMS
//=====================================================================
enum NAS_SIGNAL_MODE
{
   NAS_MODE_ST_SMA13  = 0,
   NAS_MODE_ST_ONLY   = 1,
   NAS_MODE_ST_SMA8   = 2,
   NAS_MODE_ST_SMA5   = 3,
   NAS_MODE_ST_SMA21  = 4
};
enum NAS_RR_MODE { NAS_RR_1=0, NAS_RR_2=1, NAS_RR_3=2 };
enum BT_FILL_MODE { BT_FILL_SIGNAL_CLOSE=0, BT_FILL_NEXT_BAR_OPEN=1, BT_FILL_CONSERVATIVE=2 };
enum BT_SAME_BAR_POLICY { BT_SAMEBAR_CONSERVATIVE=0, BT_SAMEBAR_NEAREST_OPEN=1, BT_SAMEBAR_TP_FIRST=2, BT_SAMEBAR_SL_FIRST=3 };

//=====================================================================
//  INPUTS â€” SIGNAL
//=====================================================================
input int             InpSensitivity       = 4;
input int             InpRsiLength         = 14;
input int             InpAtrRisk           = 1;
input int             InpAtrLen            = 14;
input NAS_SIGNAL_MODE InpSignalMode        = NAS_MODE_ST_SMA13;
input NAS_RR_MODE     InpRRMode            = NAS_RR_2;
input double          InpPineRiskMult      = 1.125;
input bool            InpBlockSameDir      = true;

//=== INPUTS â€” EXECUTION ================================================
input bool   InpEaEnabled             = true;
input long   InpMagic                 = 27052712;
input int    InpDeviationPoints       = 30;
input bool   InpCloseOnReverse        = true;
input bool   InpUseTradingWindow      = false;
input string InpTradeStartTime        = "";
input string InpTradeEndTime          = "";
input string InpNoTradeWindowsGmt     = "21:55-22:10";

//=== INPUTS â€” SPREAD GOVERNOR ==========================================
input bool   InpSpreadEnabled         = true;
input double InpSpreadGoodPts         = 0.0;
input double InpSpreadNormalPts       = 0.0;
input double InpSpreadWidePts         = 0.0;

//=== INPUTS â€” TP TOUCH WATCHDOG ========================================
input bool   InpEnforceTpTouch        = true;
input double InpTpTouchTolPts         = 2.0;
input int    InpTpTouchTimerMs        = 100;
input int    InpTpTouchRetries        = 2;

//=== INPUTS â€” LOT SIZING & ACCOUNT RISK (FTMO) ========================
input bool   InpAdvancedLotEnabled    = true;
input int    InpLotDailyAtrPeriod     = 14;
input bool   InpAccountRiskEnabled    = true;
input double InpRiskPerTradePct       = 1.00;
input double InpAtrExposurePct        = 2.00;
input double InpMaxPortfolioPct       = 4.00;
input double InpDailyLossLimitPct     = 0.00;
input double InpMaxDrawdownPct        = 0.00;
input double InpMaxMarginUsagePct     = 40.00;
input double InpInitialBalanceOverride= 0.0;
input int    InpDayResetHourGmt       = 0;
input bool   InpLiquidateOnBreach     = true;
input double InpSafetyBufferPct       = 95.00;
input double InpAdvancedLotMax        = 0.0;
input bool   InpBlockUnprotected      = true;
input bool   InpFailClosed            = true;
input bool   InpAuditEnabled          = true;
input int    InpAuditIntervalSec      = 60;
input double InpFixedLot              = 0.03;

//=== INPUTS â€” AUDIT ENGINE =============================================
input bool   InpAuditTradeCsv             = true;
input bool   InpAuditPositionProbe        = true;
input int    InpAuditPositionProbeSec     = 30;
input bool   InpAuditProbeOnChangeOnly    = true;
input int    InpAuditHistoryScanSec       = 2;

//=== INPUTS â€” DISPLAY ==================================================
input bool InpShowDashboard           = true;
input int  InpDashX                   = 10;
input int  InpDashY                   = 18;
input int  InpHistoryDays             = 14;
input int  InpCalcBars                = 5000;
input BT_FILL_MODE InpBacktestFillMode = BT_FILL_SIGNAL_CLOSE;
input BT_SAME_BAR_POLICY InpBacktestSameBarPolicy = BT_SAMEBAR_NEAREST_OPEN;
input double InpBacktestSpreadPts       = 0.0;
input double InpBacktestSlippagePts     = 0.0;
input double InpBacktestCommissionPerLot= 0.0;

//=====================================================================
//  RUNTIME STATE
//=====================================================================
CTrade trade;
string PREFIX = "NAS_V3_LAB_";

NAS_SIGNAL_MODE g_mode        = NAS_MODE_ST_SMA13;
NAS_RR_MODE     g_rr          = NAS_RR_2;
int             g_sensitivity = 4;
bool            g_needsRedraw = true;
datetime        g_lastBuild   = 0;
bool            g_eaEnabled   = true;

// Half-close + SL->BE state
bool   g_hcTp1 = false;   // HC+BE at TP1 (for 1:2R, 1:3R)
bool   g_hcTp2 = false;   // HC+BE at TP2 (for 1:3R only)

// Signal state
datetime g_lastSignalTime     = 0;
int      g_lastSignalDir      = 0;
int      g_lastExecDir        = 0;
datetime g_lastBarTime        = 0;
datetime g_processedBuyBar    = 0;
datetime g_processedSellBar   = 0;

// Trade state
double   g_lastEntry=0, g_lastSl=0, g_lastTp=0;
string   g_lastStatus         = "READY";
string   g_lastBlockReason    = "";
double   g_lastSpreadPts      = 0;
string   g_lastSpreadStatus   = "?";

// Account risk state
long     g_runtimeMagic       = 0;
double   g_equityPeak         = 0;
uint     g_lastTpWatchMs      = 0;
uint     g_lastRiskGuardMs    = 0;
double   g_lockValue          = 0;
double   g_lastAdvLot         = 0;
string   g_lastAdvDetail      = "";

// Backtest stats
int    g_total=0, g_wins=0, g_losses=0, g_other=0;
double g_netR=0;
double g_totalWonR=0, g_totalLostR=0;
double g_sumRiskPts=0;
string g_statLine="-";

// Audit engine state
datetime g_auditLastProbeTime    = 0;
string   g_auditLastProbeHash    = "";
datetime g_auditLastHistTime     = 0;
ulong    g_auditLastHistTicket   = 0;
datetime g_auditLastHistScan     = 0;
datetime g_auditLastRiskSnap     = 0;

// Brute-force backtest engine
struct BtSignal { int barIdx; int dir; double entry; double sl; double risk; int nextSig; };
struct BtCombo  { int sensIdx; int modeIdx; int rrIdx; bool hc1; bool hc2; };
struct BtStats  { int total; int wins; int losses; int other; double wonR; double lostR; double netR; };

bool     g_btRunning     = false;
int      g_btStep        = 0;
int      g_btTotal       = 0;
int      g_btWeeks       = 2;
string   g_btFileName    = "";
string   g_btLastResult  = "";
uint     g_btStartMs     = 0;
uint     g_btElapsedMs   = 0;
BT_FILL_MODE g_btFillMode = BT_FILL_SIGNAL_CLOSE;
BT_SAME_BAR_POLICY g_btSameBarPolicy = BT_SAMEBAR_NEAREST_OPEN;
double   g_btSpreadPts = 0.0;
double   g_btSlippagePts = 0.0;
double   g_btCommissionPerLot = 0.0;

BtCombo  g_btCombos[];

// Cached signal lists are stored flat because MQL5 does not support
// resizeable jagged arrays of structs reliably.
#define BT_MAX_GROUPS 25
#define BT_SENS_COUNT 5
#define BT_MODE_COUNT 5
BtSignal g_btSigs[];
int      g_btSigOffset[BT_MAX_GROUPS];
int      g_btSigCount[BT_MAX_GROUPS];
MqlRates g_btRates[];
int      g_btRatesCopied = 0;
datetime g_btCutoff      = 0;
int      g_btSensVals[]  = {2,3,4,5,6};
NAS_SIGNAL_MODE g_btModes[] = {NAS_MODE_ST_SMA13,NAS_MODE_ST_ONLY,NAS_MODE_ST_SMA8,NAS_MODE_ST_SMA5,NAS_MODE_ST_SMA21};

//=====================================================================
//  MAGIC NUMBER (FTMO-compatible scoping)
//=====================================================================
long RuntimeMagic()
{
   if(g_runtimeMagic!=0) return g_runtimeMagic;
   long cp=(long)(ChartID()%1000000);
   if(InpAccountRiskEnabled)
   {
      long safe=InpMagic%1000000000000; if(safe<0)safe=-safe;
      g_runtimeMagic=4000000000000000000+safe*1000000+cp;
   }
   else g_runtimeMagic=InpMagic*1000000+cp;
   return g_runtimeMagic;
}
long NormalMagic(){return InpMagic*1000000+(long)(ChartID()%1000000);}
long FtmoMagic(){long safe=InpMagic%1000000000000;if(safe<0)safe=-safe;return 4000000000000000000+safe*1000000+(long)(ChartID()%1000000);}
bool MagicOwned(long m){return m==NormalMagic()||m==FtmoMagic();}
bool MagicScoped(long m){return m>=4000000000000000000&&m<5000000000000000000;}

//=====================================================================
//  UTILITY
//=====================================================================
double NormPrice(double p){return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}
double NormVol(double v){double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(st<=0)st=0.01;if(InpAdvancedLotMax>0)mx=MathMin(mx,InpAdvancedLotMax);v=MathFloor(v/st+1e-7)*st;return NormalizeDouble(MathMax(mn,MathMin(mx,v)),8);}
double TickSize(){double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(ts<=0)ts=SymbolInfoDouble(_Symbol,SYMBOL_POINT);return ts>0?ts:0.00001;}
double NormTradePrice(double p){double ts=TickSize();return NormPrice(MathRound(p/ts)*ts);}
double MinStopDistance(){double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=TickSize();long st=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);long fr=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);return MathMax((double)MathMax(st,fr)*pt,TickSize());}
string ModeLabel(NAS_SIGNAL_MODE m){switch(m){case NAS_MODE_ST_SMA13:return"ST+SMA13";case NAS_MODE_ST_ONLY:return"ST ONLY";case NAS_MODE_ST_SMA8:return"ST+SMA8";case NAS_MODE_ST_SMA5:return"ST+SMA5";case NAS_MODE_ST_SMA21:return"ST+SMA21";}return"?";}
string RRLabel(NAS_RR_MODE r){switch(r){case NAS_RR_1:return"1:1R";case NAS_RR_2:return"1:2R";case NAS_RR_3:return"1:3R";}return"?";}
double RRMult(NAS_RR_MODE r){switch(r){case NAS_RR_1:return 1.0;case NAS_RR_2:return 2.0;case NAS_RR_3:return 3.0;}return 2.0;}
string BtFillLabel(BT_FILL_MODE m){switch(m){case BT_FILL_SIGNAL_CLOSE:return"SIGNAL";case BT_FILL_NEXT_BAR_OPEN:return"NEXT";case BT_FILL_CONSERVATIVE:return"CONS";}return"SIGNAL";}
string BtSameBarLabel(BT_SAME_BAR_POLICY p){switch(p){case BT_SAMEBAR_CONSERVATIVE:return"CONS";case BT_SAMEBAR_NEAREST_OPEN:return"NEAR";case BT_SAMEBAR_TP_FIRST:return"TP1ST";case BT_SAMEBAR_SL_FIRST:return"SL1ST";}return"CONS";}
double BtCostR(double risk)
{
   if(risk<=0)return 0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.00001;
   double cost=(MathMax(0,g_btSpreadPts)+MathMax(0,g_btSlippagePts))*pt/risk;
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(ts>0&&tv>0&&g_btCommissionPerLot>0)
   {
      double riskMoney=(risk/ts)*tv;
      if(riskMoney>0)cost+=g_btCommissionPerLot/riskMoney;
   }
   return cost;
}
bool BtTpFirst(int d,double openPx,double sl,double tp)
{
   if(g_btSameBarPolicy==BT_SAMEBAR_TP_FIRST)return true;
   if(g_btSameBarPolicy==BT_SAMEBAR_SL_FIRST||g_btSameBarPolicy==BT_SAMEBAR_CONSERVATIVE)return false;
   double dTp=d>0?(tp-openPx):(openPx-tp);
   double dSl=d>0?(openPx-sl):(sl-openPx);
   return dTp<dSl;
}
int ParseClock(string v,int fb){int c=StringFind(v,":");if(c<0)return fb;int h=(int)StringToInteger(StringSubstr(v,0,c));int m=(int)StringToInteger(StringSubstr(v,c+1));if(h==24&&m==0)return 1440;if(h<0||h>23||m<0||m>59)return fb;return h*60+m;}
int ServerClockMin(){MqlDateTime d;TimeToStruct(TimeCurrent(),d);return d.hour*60+d.min;}
int GmtClockMin(){MqlDateTime d;TimeToStruct(TimeGMT(),d);return d.hour*60+d.min;}
string TrimText(string s){StringTrimLeft(s);StringTrimRight(s);return s;}
bool MinuteInRange(int minute,string rangeText)
{
   string r=TrimText(rangeText);int sep=StringFind(r,"-");if(sep<=0)return false;
   int a=ParseClock(StringSubstr(r,0,sep),-1),b=ParseClock(StringSubstr(r,sep+1),-1);
   if(a<0||b<0)return false;if(a==b)return true;
   return (a<b)?(minute>=a&&minute<b):(minute>=a||minute<b);
}
bool IsNoTradeWindowGmt()
{
   string raw=TrimText(InpNoTradeWindowsGmt);if(raw=="")return false;
   StringReplace(raw,";",",");StringReplace(raw,"|",",");
   string parts[];int n=StringSplit(raw,',',parts);int m=GmtClockMin();
   for(int i=0;i<n;i++)if(MinuteInRange(m,parts[i]))return true;
   return false;
}
double CalcSMA(const MqlRates &r[],int i,int p){if(i<p-1)return EMPTY_VALUE;double s=0;for(int k=i-p+1;k<=i;k++)s+=r[k].close;return s/(double)p;}

//=====================================================================
//  POSITION HELPERS
//=====================================================================
bool IsManagedPos(){return PositionGetString(POSITION_SYMBOL)==_Symbol && MagicOwned((long)PositionGetInteger(POSITION_MAGIC));}
int ManagedDir(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(IsManagedPos())return(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;}return 0;}
int ManagedCount(){int c=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(IsManagedPos())c++;}return c;}
void CloseManaged(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(IsManagedPos()){bool ok=trade.PositionClose(t);if(!ok)NasAudit_TradeWrite("close_failed","NAS_V3_LAB",IntegerToString((long)t),"",PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),"ret="+IntegerToString((int)trade.ResultRetcode()),PositionGetDouble(POSITION_PROFIT),trade.ResultRetcodeDescription());}}}
void HydrateDirection(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(IsManagedPos()){g_lastExecDir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;return;}}}

bool ValidateOpenStops(int dir,double entry,double sl,double tp,string &reason)
{
   double md=MinStopDistance();
   if(entry<=0||sl<=0||tp<=0){reason="zero_geometry";return false;}
   if(dir>0)
   {
      if(sl>=entry-md){reason="buy_sl_inside_stop_level";return false;}
      if(tp<=entry+md){reason="buy_tp_inside_stop_level";return false;}
   }
   else
   {
      if(sl<=entry+md){reason="sell_sl_inside_stop_level";return false;}
      if(tp>=entry-md){reason="sell_tp_inside_stop_level";return false;}
   }
   return true;
}

void BuildExecutableGeometry(int dir,double liveEntry,double rawSl,NAS_RR_MODE rr,double &execSl,double &execTp,string &detail)
{
   double md=MinStopDistance()*1.20;
   double ts=TickSize();
   double originalSl=NormTradePrice(rawSl);
   execSl=originalSl;
   if(dir>0 && execSl>=liveEntry-md)
      execSl=NormTradePrice(liveEntry-md);
   if(dir<0 && execSl<=liveEntry+md)
      execSl=NormTradePrice(liveEntry+md);

   double risk=MathAbs(liveEntry-execSl);
   if(risk<=ts)
   {
      risk=MathMax(md,ts*10.0);
      execSl=NormTradePrice(dir>0?liveEntry-risk:liveEntry+risk);
   }
   execTp=NormTradePrice(dir>0?liveEntry+risk*RRMult(rr):liveEntry-risk*RRMult(rr));
   detail="";
   if(MathAbs(originalSl-execSl)>ts*0.5)
      detail="sl_adjusted_for_live_fill original_sl="+DoubleToString(originalSl,_Digits)+" exec_sl="+DoubleToString(execSl,_Digits)+" ";
}

ulong NewestManagedTicket()
{
   ulong best=0;
   datetime bestTime=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0||!PositionSelectByTicket(t)||!IsManagedPos())continue;
      datetime tm=(datetime)PositionGetInteger(POSITION_TIME);
      if(best==0||tm>=bestTime){best=t;bestTime=tm;}
   }
   return best;
}

bool SendNasMarketOrder(int dir,double lot,double px,double sl,double tp,string comment,string &detail)
{
   ENUM_ORDER_TYPE ot=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   bool ok=trade.PositionOpen(_Symbol,ot,lot,px,sl,tp,comment);
   uint rc=trade.ResultRetcode();
   if(ok&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED))
   {
      detail="order_ok ret="+IntegerToString((int)rc);
      return true;
   }

   if(rc!=TRADE_RETCODE_INVALID_STOPS && rc!=10016)
   {
      detail="order_failed ret="+IntegerToString((int)rc)+" "+trade.ResultRetcodeDescription();
      return false;
   }

   string firstFail="invalid_stops ret="+IntegerToString((int)rc)+" "+trade.ResultRetcodeDescription();
   bool naked=trade.PositionOpen(_Symbol,ot,lot,px,0,0,comment+"|naked");
   uint nakedRc=trade.ResultRetcode();
   if(!(naked&&(nakedRc==TRADE_RETCODE_DONE||nakedRc==TRADE_RETCODE_DONE_PARTIAL||nakedRc==TRADE_RETCODE_PLACED)))
   {
      detail=firstFail+" naked_failed ret="+IntegerToString((int)nakedRc)+" "+trade.ResultRetcodeDescription();
      return false;
   }

   ulong ticket=NewestManagedTicket();
   if(ticket>0&&PositionSelectByTicket(ticket))
   {
      bool mod=trade.PositionModify(ticket,sl,tp);
      uint modRc=trade.ResultRetcode();
      if(mod)
      {
         detail=firstFail+" naked_modify_ok ticket="+IntegerToString((long)ticket);
         return true;
      }
      bool closed=trade.PositionClose(ticket);
      detail=firstFail+" naked_modify_failed ret="+IntegerToString((int)modRc)+" "+trade.ResultRetcodeDescription()+" emergency_close="+(closed?"1":"0");
      return false;
   }

   detail=firstFail+" naked_opened_but_ticket_not_found";
   return false;
}

bool CanModifySlTo(double sl,int dir,string &reason)
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double md=MinStopDistance();
   if(bid<=0||ask<=0||sl<=0){reason="no_tick";return false;}
   if(dir>0 && sl>bid-md){reason="be_inside_buy_stop_level";return false;}
   if(dir<0 && sl<ask+md){reason="be_inside_sell_stop_level";return false;}
   return true;
}

string NasPosKey(ulong t,string f){return "NAS_V3_LAB_POS_"+IntegerToString((long)t)+"_"+f;}
double NasPosGet(ulong t,string f,double def)
{
   string k=NasPosKey(t,f);
   if(!GlobalVariableCheck(k))GlobalVariableSet(k,def);
   return GlobalVariableGet(k);
}
void NasPosSet(ulong t,string f,double v){GlobalVariableSet(NasPosKey(t,f),v);}

double PartialCloseVolume(double vol)
{
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(st<=0)st=0.01;if(mn<=0)mn=st;
   double part=MathFloor((vol*0.5)/st+1e-7)*st;
   if(part<mn||vol-part<mn)return 0;
   return NormalizeDouble(part,8);
}

void ManageHcBe()
{
   if((!g_hcTp1&&!g_hcTp2)||g_rr==NAS_RR_1)return;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0||ask<=0)return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t)||!IsManagedPos())continue;
      int dir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double origSl=NasPosGet(t,"ORIG_SL",curSl);
      if(origSl<=0||entry<=0||vol<=0)continue;
      double risk=MathAbs(entry-origSl);if(risk<=TickSize())continue;
      double px=dir>0?bid:ask;
      double be=NormTradePrice(entry);
      bool tp1Done=NasPosGet(t,"TP1_DONE",0)>0.5;
      bool tp2Done=NasPosGet(t,"TP2_DONE",0)>0.5;
      double trg1=dir>0?entry+risk:entry-risk;
      double trg2=dir>0?entry+risk*2.0:entry-risk*2.0;
      bool hit1=dir>0?px>=trg1:px<=trg1;
      bool hit2=dir>0?px>=trg2:px<=trg2;
      bool doTp1=g_hcTp1&&!tp1Done&&hit1&&g_rr>=NAS_RR_2;
      bool doTp2=g_hcTp2&&!tp2Done&&hit2&&g_rr==NAS_RR_3;
      if(doTp1||doTp2)
      {
         string leg=doTp1?"TP1":"TP2";
         double part=PartialCloseVolume(vol);
         bool markDone=false;
         if(part>0)
         {
            bool closed=trade.PositionClosePartial(t,part);
            NasAudit_TradeWrite(closed?"half_close":"half_close_failed","NAS_V3_LAB",IntegerToString((long)t),dir>0?"BUY":"SELL",part,entry,curSl,tp,leg,PositionGetDouble(POSITION_PROFIT),"ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
            markDone=closed;
         }
         else
         {
            NasAudit_TradeWrite("half_close_skip","NAS_V3_LAB",IntegerToString((long)t),dir>0?"BUY":"SELL",vol,entry,curSl,tp,"volume_too_small",PositionGetDouble(POSITION_PROFIT),"");
            markDone=true;
         }
         if(!markDone)continue;
         if(doTp1)NasPosSet(t,"TP1_DONE",1);else NasPosSet(t,"TP2_DONE",1);
      }
      bool needsBe=(NasPosGet(t,"TP1_DONE",0)>0.5||NasPosGet(t,"TP2_DONE",0)>0.5);
      if(needsBe && ((dir>0&&curSl<be)||(dir<0&&curSl>be)))
      {
         string rr="";
         if(CanModifySlTo(be,dir,rr))
         {
            bool mod=trade.PositionModify(t,be,tp);
            NasAudit_TradeWrite(mod?"sl_to_be":"sl_to_be_failed","NAS_V3_LAB",IntegerToString((long)t),dir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),entry,be,tp,rr,PositionGetDouble(POSITION_PROFIT),"ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
         }
         else NasAudit_TradeWrite("sl_to_be_deferred","NAS_V3_LAB",IntegerToString((long)t),dir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),entry,be,tp,rr,PositionGetDouble(POSITION_PROFIT),"");
      }
   }
}

//=====================================================================
//  SPREAD GOVERNOR
//=====================================================================
void AutoSpreadThresholds(double &gd,double &nm,double &wd)
{
   string sym=_Symbol;StringToUpper(sym);
   gd=100;nm=300;wd=800;
   if(StringFind(sym,"USTEC")>=0||StringFind(sym,"NAS")>=0||StringFind(sym,"US100")>=0||StringFind(sym,"NDX")>=0){gd=180;nm=350;wd=800;}
   else if(StringFind(sym,"XAU")>=0||StringFind(sym,"GOLD")>=0){gd=180;nm=350;wd=800;}
   else if(StringFind(sym,"EUR")>=0||StringFind(sym,"GBP")>=0||StringFind(sym,"USD")>=0||StringFind(sym,"JPY")>=0){gd=20;nm=50;wd=120;}
   else if(StringFind(sym,"DE30")>=0||StringFind(sym,"GER40")>=0||StringFind(sym,"DAX")>=0){gd=35;nm=80;wd=200;}
   if(InpSpreadGoodPts>0)gd=InpSpreadGoodPts;if(InpSpreadNormalPts>0)nm=InpSpreadNormalPts;if(InpSpreadWidePts>0)wd=InpSpreadWidePts;
   nm=MathMax(nm,gd);wd=MathMax(wd,nm);
}
bool SpreadAllowed(string &reason)
{
   if(!InpSpreadEnabled){reason="spread_off";return true;}
   MqlTick tk;if(!SymbolInfoTick(_Symbol,tk)){reason="no_tick";return false;}
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0){reason="no_point";return false;}
   double sp=MathMax(0,(tk.ask-tk.bid)/pt);g_lastSpreadPts=sp;
   double gd,nm,wd;AutoSpreadThresholds(gd,nm,wd);
   if(sp<=gd){g_lastSpreadStatus="GOOD";reason="GOOD";return true;}
   if(sp<=nm){g_lastSpreadStatus="NORMAL";reason="NORMAL";return true;}
   if(sp<=wd){g_lastSpreadStatus="WIDE";reason="WIDE";return true;}
   g_lastSpreadStatus="BLOCKED";reason="spread_blocked "+DoubleToString(sp,0)+">"+DoubleToString(wd,0);return false;
}

//=====================================================================
//  TRADING TIME WINDOW
//=====================================================================
bool IsWindowOpen()
{
   if(IsNoTradeWindowGmt()) return false;
   if(!InpUseTradingWindow) return true;
   if(TrimText(InpTradeStartTime)=="" || TrimText(InpTradeEndTime)=="") return true;
   int s=ParseClock(InpTradeStartTime,0),e=ParseClock(InpTradeEndTime,1439),n=ServerClockMin();
   if(s==e)return true;
   return s<e?(n>=s&&n<=e):(n>=s||n<=e);
}
string WindowText()
{
   if(IsNoTradeWindowGmt()) return "CLOSED no-trade GMT "+InpNoTradeWindowsGmt;
   if(!InpUseTradingWindow || TrimText(InpTradeStartTime)=="" || TrimText(InpTradeEndTime)=="") return "OPEN 24/7";
   return(IsWindowOpen()?"OPEN ":"CLOSED ")+InpTradeStartTime+"-"+InpTradeEndTime;
}

//=====================================================================
//  ACCOUNT RISK ENGINE (FTMO)
//=====================================================================
string RiskKey(string k){return "PTS_FTMO_RISK_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+k;}
datetime RiskDayStart(){datetime n=TimeGMT();int rh=MathMax(0,MathMin(23,InpDayResetHourGmt));datetime sh=n-rh*3600;return sh-(sh%86400)+rh*3600;}
datetime RiskStartGmt(){string k=RiskKey("START_GMT");if(!GlobalVariableCheck(k))GlobalVariableSet(k,(double)TimeGMT());return(datetime)GlobalVariableGet(k);}
double RiskInitialBal(){if(InpInitialBalanceOverride>0)return InpInitialBalanceOverride;string k=RiskKey("INITIAL_BALANCE");if(!GlobalVariableCheck(k))GlobalVariableSet(k,MathMax(0.01,AccountInfoDouble(ACCOUNT_BALANCE)));return MathMax(0.01,GlobalVariableGet(k));}

void RiskScopePerf(double &closedAll,double &closedToday,double &floating)
{
   int rh=MathMax(0,MathMin(23,InpDayResetHourGmt));string sfx="_H"+IntegerToString(rh);
   string cts=RiskKey("METRICS_TS"+sfx);double nowL=(double)TimeLocal();
   if(GlobalVariableCheck(cts)&&nowL-GlobalVariableGet(cts)<1.0
      &&GlobalVariableCheck(RiskKey("CLOSED_ALL"+sfx))
      &&GlobalVariableCheck(RiskKey("CLOSED_TODAY"+sfx))
      &&GlobalVariableCheck(RiskKey("FLOATING"+sfx)))
   {closedAll=GlobalVariableGet(RiskKey("CLOSED_ALL"+sfx));closedToday=GlobalVariableGet(RiskKey("CLOSED_TODAY"+sfx));floating=GlobalVariableGet(RiskKey("FLOATING"+sfx));return;}
   closedAll=0;closedToday=0;floating=0;
   datetime ds=RiskDayStart(),ss=RiskStartGmt(),sn=TimeTradeServer(),gn=TimeGMT();
   datetime dsS=ds+(sn-gn),ssS=ss+(sn-gn),hsS=MathMax(dsS,ssS);
   if(HistorySelect(ssS,sn)){for(int i=0;i<HistoryDealsTotal();i++){ulong t=HistoryDealGetTicket(i);if(t==0)continue;ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(t,DEAL_TYPE);if(dt!=DEAL_TYPE_BUY&&dt!=DEAL_TYPE_SELL)continue;if(!MagicScoped((long)HistoryDealGetInteger(t,DEAL_MAGIC)))continue;double pnl=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE);closedAll+=pnl;if((datetime)HistoryDealGetInteger(t,DEAL_TIME)>=hsS)closedToday+=pnl;}}
   for(int j=PositionsTotal()-1;j>=0;j--){ulong t=PositionGetTicket(j);if(t==0||!PositionSelectByTicket(t))continue;if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))continue;floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}
   GlobalVariableSet(RiskKey("CLOSED_ALL"+sfx),closedAll);GlobalVariableSet(RiskKey("CLOSED_TODAY"+sfx),closedToday);GlobalVariableSet(RiskKey("FLOATING"+sfx),floating);GlobalVariableSet(cts,nowL);
}

void RiskMetrics(double &cap,double &dailyPct,double &totalPct)
{
   double init=RiskInitialBal(),cAll,cToday,fl;RiskScopePerf(cAll,cToday,fl);
   double scopeEq=MathMax(0.01,init+cAll+fl);
   int rh=MathMax(0,MathMin(23,InpDayResetHourGmt));string sfx="_H"+IntegerToString(rh);
   datetime ds=RiskDayStart();string dk=RiskKey("DAY_SCOPE_"+IntegerToString((int)ds)+sfx);
   if(!GlobalVariableCheck(dk))GlobalVariableSet(dk,MathMax(0.01,init+cAll-cToday));
   double dayStart=MathMax(0.01,GlobalVariableGet(dk));
   cap=MathMax(0.01,MathMin(AccountInfoDouble(ACCOUNT_EQUITY),scopeEq));
   dailyPct=MathMax(0,(dayStart-scopeEq)/dayStart*100.0);
   totalPct=MathMax(0,-(cAll+fl)/init*100.0);
}

bool RiskLockAcquire(){string k=RiskKey("LOCK");if(!GlobalVariableCheck(k))GlobalVariableSet(k,0);for(int i=0;i<50;i++){double obs=GlobalVariableGet(k);double now=(double)TimeLocal();if(MathFloor(obs)<=now){long cp=(long)(ChartID()%100000);double tok=MathFloor(now+30.0)+(double)(cp*10+(GetTickCount()%10)+1)/1000001.0;if(GlobalVariableSetOnCondition(k,tok,obs)){g_lockValue=tok;return true;}}Sleep(5);}return false;}
void RiskLockRelease(){if(g_lockValue>0)GlobalVariableSetOnCondition(RiskKey("LOCK"),0.0,g_lockValue);g_lockValue=0;}
void RiskCacheInvalidate(){int rh=MathMax(0,MathMin(23,InpDayResetHourGmt));GlobalVariableSet(RiskKey("METRICS_TS_H"+IntegerToString(rh)),0.0);}

void EnforceRiskBreach()
{
   if(!InpAccountRiskEnabled||!InpLiquidateOnBreach)return;
   uint now=GetTickCount();if(now-g_lastRiskGuardMs<100)return;g_lastRiskGuardMs=now;
   double cap,dp,tp;RiskMetrics(cap,dp,tp);
   double sf=MathMax(1,MathMin(100,InpSafetyBufferPct))/100.0;
   bool breach=(InpDailyLossLimitPct>0&&dp>=InpDailyLossLimitPct*sf)||(InpMaxDrawdownPct>0&&tp>=InpMaxDrawdownPct*sf);
   if(!breach)return;
   string ak=RiskKey("BREACH_ATTEMPT");double nowL=(double)TimeLocal();
   if(GlobalVariableCheck(ak)&&nowL-GlobalVariableGet(ak)<2)return;GlobalVariableSet(ak,nowL);
   if(!RiskLockAcquire())return;RiskCacheInvalidate();RiskMetrics(cap,dp,tp);
   breach=(InpDailyLossLimitPct>0&&dp>=InpDailyLossLimitPct*sf)||(InpMaxDrawdownPct>0&&tp>=InpMaxDrawdownPct*sf);
   if(!breach){RiskLockRelease();return;}
   Print("NAS_V3_LAB LIQUIDATION daily=",DoubleToString(dp,3)," dd=",DoubleToString(tp,3));
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t)||!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))continue;trade.PositionClose(t);}
   RiskCacheInvalidate();RiskLockRelease();
}

//=====================================================================
//  ADVANCED LOT SIZING
//=====================================================================
double ClosedDailyAtr(){int h=iATR(_Symbol,PERIOD_D1,MathMax(2,InpLotDailyAtrPeriod));if(h==INVALID_HANDLE)return 0;double v[];ArraySetAsSeries(v,true);int c=CopyBuffer(h,0,1,1,v);IndicatorRelease(h);return(c==1&&v[0]>0)?v[0]:0;}

double ResolveVolume(int dir,double entry,double sl,string &detail)
{
   double fallback=NormVol(InpFixedLot);
   if(!InpAccountRiskEnabled){detail="risk_off lot="+DoubleToString(fallback,4);return fallback;}
   double eq,dp,tp;RiskMetrics(eq,dp,tp);
   double mu=eq>0?AccountInfoDouble(ACCOUNT_MARGIN)/eq*100:100;
   double sf=MathMax(1,MathMin(100,InpSafetyBufferPct))/100.0;
   if(eq<=0||(InpDailyLossLimitPct>0&&dp>=InpDailyLossLimitPct*sf)||(InpMaxDrawdownPct>0&&tp>=InpMaxDrawdownPct*sf)||(InpMaxMarginUsagePct>0&&mu>=InpMaxMarginUsagePct))
   {detail="risk_block eq="+DoubleToString(eq,2)+" dp="+DoubleToString(dp,3);return 0;}
   double atr=ClosedDailyAtr();
   if(sl<=0||MathAbs(entry-sl)<=0||atr<=0){detail="invalid_inputs";return InpFailClosed?0:fallback;}
   ENUM_ORDER_TYPE ot=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double slRes=0,atrRes=0,atrExit=dir>0?entry-atr:entry+atr;
   if(!OrderCalcProfit(ot,_Symbol,1.0,entry,sl,slRes)||!OrderCalcProfit(ot,_Symbol,1.0,entry,atrExit,atrRes)){detail="calc_fail";return InpFailClosed?0:fallback;}
   double slMpl=MathAbs(slRes),atrMpl=MathAbs(atrRes);
   if(slMpl<=0||atrMpl<=0){detail="zero_mpl";return InpFailClosed?0:fallback;}
   double openRisk=0;int unprot=0;
   for(int i=PositionsTotal()-1;i>=0;i--){string sym=PositionGetSymbol(i);if(sym==""||!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))continue;double psl=PositionGetDouble(POSITION_SL);if(psl<=0){unprot++;continue;}ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double pe=PositionGetDouble(POSITION_PRICE_OPEN);double pv=PositionGetDouble(POSITION_VOLUME);bool exp=(pt==POSITION_TYPE_BUY&&psl<pe)||(pt==POSITION_TYPE_SELL&&psl>pe);if(!exp)continue;double r=0;if(OrderCalcProfit(pt==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,sym,pv,pe,psl,r))openRisk+=MathMax(0,-r);else unprot++;}
   if(InpBlockUnprotected&&unprot>0){detail="unprotected="+IntegerToString(unprot);return 0;}
   double tb=eq*MathMax(0,InpRiskPerTradePct)/100,ab=eq*MathMax(0,InpAtrExposurePct)/100,pb=eq*MathMax(0,InpMaxPortfolioPct)/100;
   double avail=MathMax(0,pb-openRisk);
   if(tb<=0||ab<=0||avail<=0){detail="budget_exhausted";return 0;}
   double slV=tb/slMpl,atrV=ab/atrMpl,pV=avail/slMpl;
   double raw=InpAdvancedLotEnabled?MathMin(slV,MathMin(atrV,pV)):InpFixedLot;
   double vol=NormVol(raw);
   if(vol<=0){detail="vol_zero";return 0;}
   double reqM=0;bool mc=OrderCalcMargin(ot,_Symbol,vol,entry,reqM);
   double projM=eq>0?(AccountInfoDouble(ACCOUNT_MARGIN)+reqM)/eq*100:100;
   if(!mc||reqM>AccountInfoDouble(ACCOUNT_MARGIN_FREE)||(InpMaxMarginUsagePct>0&&projM>InpMaxMarginUsagePct)){detail="margin_block";return 0;}
   detail="lot="+DoubleToString(vol,4)+" sl_v="+DoubleToString(slV,4)+" atr_v="+DoubleToString(atrV,4);
   return vol;
}

//=====================================================================
//  TP TOUCH WATCHDOG
//=====================================================================
void EnforceTpTouch()
{
   if(!InpEnforceTpTouch)return;
   uint now=GetTickCount();if(g_lastTpWatchMs>0&&now-g_lastTpWatchMs<(uint)MathMax(20,InpTpTouchTimerMs))return;
   g_lastTpWatchMs=now;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0||ask<=0)return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t)||!IsManagedPos())continue;
      double tpx=PositionGetDouble(POSITION_TP);if(tpx<=0)continue;
      int d=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double tol=MathMax(0,InpTpTouchTolPts)*_Point;
      bool hit=d>0?(bid+tol>=tpx):(ask-tol<=tpx);
      if(!hit)continue;
      NasAudit_TradeWrite("tp_watchdog_close","NAS_V3_LAB",IntegerToString((int)t),d>0?"BUY":"SELL",
         PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),
         PositionGetDouble(POSITION_SL),tpx,"tp_touch",PositionGetDouble(POSITION_PROFIT),"");
      for(int a=0;a<MathMax(1,InpTpTouchRetries);a++){if(trade.PositionClose(t))break;}
   }
}

//=====================================================================
//  SIGNAL MODE APPLICATION (Wilder ATR, pre-computed SMAs)
//=====================================================================
void ApplySignalMode(const MqlRates &rates[],NasPoint &p[],int n,NAS_SIGNAL_MODE mode)
{
   double wAtr[];NAS_WilderATR(rates,n,InpAtrLen,wAtr);
   double sma5[],sma21[];
   if(mode==NAS_MODE_ST_SMA5||mode==NAS_MODE_ST_SMA21){ArrayResize(sma5,n);ArrayResize(sma21,n);for(int i=0;i<n;i++){sma5[i]=CalcSMA(rates,i,5);sma21[i]=CalcSMA(rates,i,21);}}
   for(int i=1;i<n;i++)
   {
      bool cu=NAS_Crossover(rates[i].close,p[i].superTrend,rates[i-1].close,p[i-1].superTrend);
      bool cd=NAS_Crossunder(rates[i].close,p[i].superTrend,rates[i-1].close,p[i-1].superTrend);
      switch(mode)
      {
         case NAS_MODE_ST_ONLY:  p[i].buy=cu;p[i].sell=cd;break;
         case NAS_MODE_ST_SMA13: p[i].buy=cu&&NAS_IsValid(p[i].sma13)&&rates[i].close>=p[i].sma13;p[i].sell=cd&&NAS_IsValid(p[i].sma13)&&rates[i].close<=p[i].sma13;break;
         case NAS_MODE_ST_SMA8:  p[i].buy=cu&&NAS_IsValid(p[i].sma8)&&rates[i].close>=p[i].sma8;p[i].sell=cd&&NAS_IsValid(p[i].sma8)&&rates[i].close<=p[i].sma8;break;
         case NAS_MODE_ST_SMA5:  p[i].buy=cu&&sma5[i]!=EMPTY_VALUE&&rates[i].close>=sma5[i];p[i].sell=cd&&sma5[i]!=EMPTY_VALUE&&rates[i].close<=sma5[i];break;
         case NAS_MODE_ST_SMA21: p[i].buy=cu&&sma21[i]!=EMPTY_VALUE&&rates[i].close>=sma21[i];p[i].sell=cd&&sma21[i]!=EMPTY_VALUE&&rates[i].close<=sma21[i];break;
      }
      if(p[i].buy||p[i].sell)
      {
         int d=p[i].buy?1:-1;
         if(NAS_IsValid(wAtr[i]))
         {
            double ab=wAtr[i]*(double)InpAtrRisk;
            p[i].nasEntry=rates[i].close;
            p[i].nasSl=d>0?rates[i].low-ab:rates[i].high+ab;
            double rk=MathAbs(p[i].nasEntry-p[i].nasSl)*MathMax(0.1,InpPineRiskMult);
            p[i].nasSl=d>0?p[i].nasEntry-rk:p[i].nasEntry+rk;
            p[i].nasTp1=d>0?p[i].nasEntry+rk:p[i].nasEntry-rk;
            p[i].nasTp2=d>0?p[i].nasEntry+rk*2:p[i].nasEntry-rk*2;
            p[i].nasTp3=d>0?p[i].nasEntry+rk*3:p[i].nasEntry-rk*3;
         }
      }
   }
}

//=====================================================================
//  LIVE SIGNAL PIPELINE
//=====================================================================
void ProcessSignalBar()
{
   if(!g_eaEnabled)return;
   MqlRates rates[];int copied=CopyRates(_Symbol,_Period,0,MathMax(InpCalcBars,300),rates);
   if(copied<200)return;
   if(rates[0].time>rates[copied-1].time)ArrayReverse(rates,0,WHOLE_ARRAY);
   NasSettings cfg;cfg.sensitivity=g_sensitivity;cfg.rsiLength=InpRsiLength;cfg.atrRisk=InpAtrRisk;cfg.atrLen=InpAtrLen;
   NasPoint p[];NAS_Calculate(rates,copied,cfg,p);
   ApplySignalMode(rates,p,copied,g_mode);

   int si=copied-2;
   if(si<1)return;
   int dir=p[si].buy?1:(p[si].sell?-1:0);
   if(dir==0)return;

   if(rates[si].time==g_lastSignalTime&&dir==g_lastSignalDir)return;
   if(dir>0&&g_processedBuyBar==rates[si].time)return;
   if(dir<0&&g_processedSellBar==rates[si].time)return;

   g_lastSignalTime=rates[si].time;g_lastSignalDir=dir;
   if(dir>0)g_processedBuyBar=rates[si].time;else g_processedSellBar=rates[si].time;

   string dirStr=dir>0?"BUY":"SELL";

   if(!IsWindowOpen())
   {
      if(InpCloseOnReverse&&ManagedDir()!=0&&ManagedDir()!=dir)CloseManaged();
      NasAudit_TradeWrite("signal_skip_window",ModeLabel(g_mode),"",dirStr,0,0,0,0,"window_closed",0,"");
      g_lastStatus="BLOCKED";g_lastBlockReason="window_closed";return;
   }
   if(InpBlockSameDir&&dir==g_lastExecDir)
   {
      NasAudit_TradeWrite("signal_skip_samedir",ModeLabel(g_mode),"",dirStr,0,0,0,0,"same_dir",0,"");
      g_lastStatus="BLOCKED";g_lastBlockReason="same_dir";return;
   }
   string sr="";
   if(!SpreadAllowed(sr))
   {
      NasAudit_TradeWrite("signal_skip_spread",ModeLabel(g_mode),"",dirStr,0,0,0,0,sr,0,"spread="+DoubleToString(g_lastSpreadPts,0));
      g_lastStatus="BLOCKED";g_lastBlockReason=sr;return;
   }
   if(!NAS_IsValid(p[si].nasEntry)||!NAS_IsValid(p[si].nasSl))
   {
      NasAudit_TradeWrite("signal_skip_geometry",ModeLabel(g_mode),"",dirStr,0,0,0,0,"invalid_risk",0,"");
      g_lastStatus="BLOCKED";g_lastBlockReason="invalid_risk";return;
   }

   double signalEntry=NormTradePrice(p[si].nasEntry),signalSl=NormTradePrice(p[si].nasSl);
   double signalRisk=MathAbs(signalEntry-signalSl);if(signalRisk<=SymbolInfoDouble(_Symbol,SYMBOL_POINT)*5)return;
   double signalTp=NormTradePrice(dir>0?signalEntry+signalRisk*RRMult(g_rr):signalEntry-signalRisk*RRMult(g_rr));
   g_lastEntry=signalEntry;g_lastSl=signalSl;g_lastTp=signalTp;

   NasAudit_TradeWrite("signal_received",ModeLabel(g_mode),"",dirStr,0,g_lastEntry,g_lastSl,g_lastTp,"confirmed_signal",0,
      "risk="+DoubleToString(signalRisk,_Digits)+" rr="+RRLabel(g_rr));

   if(InpCloseOnReverse&&ManagedDir()!=0&&ManagedDir()!=dir)
   {
      NasAudit_TradeWrite("reverse_close",ModeLabel(g_mode),"",dirStr,0,0,0,0,"close_on_reverse",0,"");
      CloseManaged();
   }

   bool lockHeld=false;
   if(InpAccountRiskEnabled)
   {
      if(!RiskLockAcquire())
      {
         NasAudit_TradeWrite("signal_skip_risk",ModeLabel(g_mode),"",dirStr,0,g_lastEntry,g_lastSl,g_lastTp,"lock_busy",0,"");
         g_lastStatus="BLOCKED";g_lastBlockReason="lock_busy";return;
      }
      lockHeld=true;RiskCacheInvalidate();
   }
   g_lastAdvDetail="";

   double px=dir>0?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   px=NormTradePrice(px);
   double execSl=0,execTp=0;
   string geomDetail="";
   BuildExecutableGeometry(dir,px,signalSl,g_rr,execSl,execTp,geomDetail);
   g_lastEntry=px;g_lastSl=execSl;g_lastTp=execTp;
   double execRisk=MathAbs(px-execSl);
   NasAudit_TradeWrite("exec_geometry",ModeLabel(g_mode),"",dirStr,0,px,execSl,execTp,"live_fill_geometry",0,
      geomDetail+"signal_entry="+DoubleToString(signalEntry,_Digits)+" signal_sl="+DoubleToString(signalSl,_Digits)+" signal_tp="+DoubleToString(signalTp,_Digits)+" exec_risk="+DoubleToString(execRisk,_Digits));

   double lot=ResolveVolume(dir,px,execSl,g_lastAdvDetail);
   g_lastAdvLot=lot;
   if(lot<=0)
   {
      NasAudit_TradeWrite("signal_skip_risk",ModeLabel(g_mode),"",dirStr,0,g_lastEntry,g_lastSl,g_lastTp,"lot_zero",0,g_lastAdvDetail);
      if(lockHeld)RiskLockRelease();g_lastStatus="BLOCKED";g_lastBlockReason=g_lastAdvDetail;return;
   }

   trade.SetExpertMagicNumber(RuntimeMagic());trade.SetDeviationInPoints(InpDeviationPoints);trade.SetTypeFillingBySymbol(_Symbol);
   string stopReason="";
   if(!ValidateOpenStops(dir,px,execSl,execTp,stopReason))
   {
      if(lockHeld)RiskLockRelease();
      NasAudit_TradeWrite("signal_skip_stops",ModeLabel(g_mode),"",dirStr,lot,px,execSl,execTp,stopReason,0,g_lastAdvDetail);
      g_lastStatus="BLOCKED";g_lastBlockReason=stopReason;return;
   }
   string cm="NAS_V3_LAB_"+(dir>0?"BUY":"SELL")+"_"+ModeLabel(g_mode);
   string sendDetail="";
   bool success=SendNasMarketOrder(dir,lot,px,execSl,execTp,cm,sendDetail);
   uint rc=trade.ResultRetcode();
   if(lockHeld){RiskCacheInvalidate();RiskLockRelease();}
   if(success)
   {
      g_lastExecDir=dir;g_lastStatus="OPENED";g_lastBlockReason="";
      NasAudit_TradeWrite("order_sent",ModeLabel(g_mode),"",dirStr,lot,px,execSl,execTp,sendDetail,0,
         "lot="+DoubleToString(lot,4)+" "+geomDetail+g_lastAdvDetail);
      Print("NAS_V3_LAB OPENED ",dirStr," lot=",DoubleToString(lot,4)," entry=",DoubleToString(px,_Digits)," sl=",DoubleToString(execSl,_Digits)," tp=",DoubleToString(execTp,_Digits)," mode=",ModeLabel(g_mode));
   }
   else
   {
      g_lastStatus="FAIL";g_lastBlockReason="ret="+IntegerToString((int)rc);
      NasAudit_TradeWrite("order_failed",ModeLabel(g_mode),"",dirStr,lot,px,execSl,execTp,"ret="+IntegerToString((int)rc),0,sendDetail);
      Print("NAS_V3_LAB OPEN FAIL ret=",rc," ",trade.ResultRetcodeDescription());
   }
}

//=====================================================================
//  TRADE SIMULATION â€” with HC+BE partial close support
//  Tracks lot fraction through TP levels. EXIT/T/O compute actual R.
//=====================================================================
struct SimResult{string outcome;double netR;bool isWin;bool isLoss;};

SimResult SimulateTrade(const MqlRates &rates[],const NasPoint &p[],int si,int d,
                        double e,double sl,int last,double risk,
                        bool hcTp1,bool hcTp2,NAS_RR_MODE rr)
{
   SimResult r; r.outcome="open"; r.netR=0; r.isWin=false; r.isLoss=false;
   if(si>=last||risk<=0) return r;
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN && si+1<=last) e=rates[si+1].open;
   else if(g_btFillMode==BT_FILL_CONSERVATIVE && si+1<=last)
   {
      double no=rates[si+1].open;
      e=d>0?MathMax(e,no):MathMin(e,no);
   }
   risk=MathAbs(e-sl);
   if(risk<=0)return r;

   double rrm     = RRMult(rr);
   double tp1     = d>0 ? e+risk     : e-risk;
   double tp2     = d>0 ? e+risk*2.0 : e-risk*2.0;
   double finalTp = d>0 ? e+risk*rrm : e-risk*rrm;

   double curSl   = sl;
   double lotFrac = 1.0;
   double accR    = 0.0;
   bool   tp1Done = false;
   bool   tp2Done = false;

   // Find trade end bar (next signal or array end)
   int endBar = last;
   for(int j=si+1; j<=last; j++)
   {
      if(j>si+1 && (p[j].buy || p[j].sell)) { endBar=j-1; break; }
   }

   for(int j=si+1; j<=endBar; j++)
   {
      // --- Check SL hit ---
      bool slHit = d>0 ? (rates[j].low <= curSl) : (rates[j].high >= curSl);

      // --- Check TP levels ---
      bool tp1Hit = !tp1Done && (d>0 ? (rates[j].high >= tp1) : (rates[j].low <= tp1));
      bool finalHit = d>0 ? (rates[j].high >= finalTp) : (rates[j].low <= finalTp);

      // Same-bar SL + final TP conflict: use open-distance priority
      if(slHit && finalHit)
      {
         double dTp = d>0 ? (finalTp - rates[j].open) : (rates[j].open - finalTp);
         double dSl = d>0 ? (rates[j].open - curSl) : (curSl - rates[j].open);
         bool tpFirst=false;
         if(g_btSameBarPolicy==BT_SAMEBAR_TP_FIRST)tpFirst=true;
         else if(g_btSameBarPolicy==BT_SAMEBAR_SL_FIRST||g_btSameBarPolicy==BT_SAMEBAR_CONSERVATIVE)tpFirst=false;
         else tpFirst=(dTp<dSl);
         if(tpFirst)
         {
            // Process intermediate HC legs first
            if(tp1Hit && hcTp1 && rrm>=2.0)
            {
               accR += 1.0 * lotFrac * 0.5;
               lotFrac *= 0.5;
               curSl = e; // SLâ†’BE
               tp1Done = true;
            }
            bool tp2Hit = !tp2Done && rrm>=3.0 && (d>0?(rates[j].high>=tp2):(rates[j].low<=tp2));
            if(tp2Hit && hcTp2 && rrm>=3.0)
            {
               accR += 2.0 * lotFrac * 0.5;
               lotFrac *= 0.5;
               tp2Done = true;
            }
            accR += rrm * lotFrac;
            r.netR = accR-BtCostR(risk); r.outcome = "TP"; r.isWin = (r.netR>0); r.isLoss=(r.netR<0);
            return r;
         }
         else // SL closer â†’ SL first
         {
            double slR = (curSl == e) ? 0.0 : -1.0;
            accR += slR * lotFrac;
            r.netR = accR-BtCostR(risk); r.outcome = (curSl==e) ? "BE" : "SL";
            r.isWin = (r.netR > 0); r.isLoss = (r.netR < 0);
            return r;
         }
      }

      // --- Process TP1 half-close ---
      if(tp1Hit && hcTp1 && rrm >= 2.0)
      {
         accR += 1.0 * lotFrac * 0.5;
         lotFrac *= 0.5;
         curSl = e; // SLâ†’BE
         tp1Done = true;
      }

      // --- Process TP2 half-close ---
      bool tp2Hit = !tp2Done && rrm>=3.0 && (d>0?(rates[j].high>=tp2):(rates[j].low<=tp2));
      if(tp2Hit && hcTp2 && rrm >= 3.0)
      {
         accR += 2.0 * lotFrac * 0.5;
         lotFrac *= 0.5;
         tp2Done = true;
      }

      // --- Re-evaluate SL after HC moved it to BE ---
      if(tp1Done || tp2Done)
         slHit = d>0 ? (rates[j].low <= curSl) : (rates[j].high >= curSl);

      // --- Final TP hit (after HC processing) ---
      if(finalHit)
      {
         accR += rrm * lotFrac;
         r.netR = accR-BtCostR(risk); r.outcome = "TP"; r.isWin = (r.netR>0); r.isLoss=(r.netR<0);
         return r;
      }

      // --- SL hit (after TP processing on same bar) ---
      if(slHit)
      {
         double slR = (curSl == e) ? 0.0 : -1.0;
         accR += slR * lotFrac;
         r.netR = accR-BtCostR(risk);
         r.outcome = (curSl == e) ? "BE" : "SL";
         r.isWin = (r.netR > 0); r.isLoss = (r.netR < 0);
         return r;
      }

      // --- Timeout ---
      if(j - si >= 200)
      {
         double closePx = rates[j].close;
         double pnl = d>0 ? (closePx-e) : (e-closePx);
         accR += (pnl / risk) * lotFrac;
         r.netR = accR-BtCostR(risk); r.outcome = "T/O";
         r.isWin = (r.netR > 0); r.isLoss = (r.netR < 0);
         return r;
      }
   }

   // --- Closed by next signal: compute actual R at next bar open ---
   if(endBar < last && (p[endBar+1].buy || p[endBar+1].sell))
   {
      double closePx = rates[endBar+1].open;
      double pnl = d>0 ? (closePx-e) : (e-closePx);
      accR += (pnl / risk) * lotFrac;
      r.netR = accR-BtCostR(risk); r.outcome = "EXIT";
      r.isWin = (r.netR > 0); r.isLoss = (r.netR < 0);
   }
   return r;
}

//=====================================================================
//  HISTORICAL SIGNAL DRAWING + SIMULATION
//=====================================================================
void DelByPrefix(const string pfx){for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--){string n=ObjectName(0,i,0,-1);if(StringFind(n,pfx)==0)ObjectDelete(0,n);}}
void DelHist(){DelByPrefix(PREFIX+"HIST_");}
void DelDash(){DelByPrefix(PREFIX+"DASH_");DelByPrefix(PREFIX+"BTN_");DelByPrefix(PREFIX+"EDIT_");}

void MkRect(const string nm,int x,int y,int w,int h,color bg,color bd){string o=PREFIX+nm;if(ObjectFind(0,o)<0)ObjectCreate(0,o,OBJ_RECTANGLE_LABEL,0,0,0);ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,o,OBJPROP_XSIZE,MathMax(1,w));ObjectSetInteger(0,o,OBJPROP_YSIZE,MathMax(1,h));ObjectSetInteger(0,o,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,o,OBJPROP_BORDER_COLOR,bd);ObjectSetInteger(0,o,OBJPROP_BACK,false);ObjectSetInteger(0,o,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,o,OBJPROP_HIDDEN,true);}
void MkLabel(const string nm,int x,int y,string txt,color c,int sz=9){string o=PREFIX+nm;if(ObjectFind(0,o)<0)ObjectCreate(0,o,OBJ_LABEL,0,0,0);ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);ObjectSetString(0,o,OBJPROP_TEXT,txt);ObjectSetInteger(0,o,OBJPROP_COLOR,c);ObjectSetInteger(0,o,OBJPROP_FONTSIZE,sz);ObjectSetString(0,o,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,o,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,o,OBJPROP_HIDDEN,true);}
void MkBtn(const string nm,int x,int y,int w,int h,string txt,color bg){string o=PREFIX+nm;if(ObjectFind(0,o)<0)ObjectCreate(0,o,OBJ_BUTTON,0,0,0);ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,o,OBJPROP_XSIZE,w);ObjectSetInteger(0,o,OBJPROP_YSIZE,h);ObjectSetString(0,o,OBJPROP_TEXT,txt);ObjectSetInteger(0,o,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,o,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,o,OBJPROP_FONTSIZE,8);ObjectSetString(0,o,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,o,OBJPROP_STATE,false);}
void MkEdit(const string nm,int x,int y,int w,int h,string txt){string o=PREFIX+nm;if(ObjectFind(0,o)<0){ObjectCreate(0,o,OBJ_EDIT,0,0,0);ObjectSetString(0,o,OBJPROP_TEXT,txt);ObjectSetInteger(0,o,OBJPROP_BGCOLOR,C'38,46,60');ObjectSetInteger(0,o,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,o,OBJPROP_BORDER_COLOR,C'80,100,130');ObjectSetInteger(0,o,OBJPROP_FONTSIZE,8);ObjectSetString(0,o,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,o,OBJPROP_ALIGN,ALIGN_CENTER);ObjectSetInteger(0,o,OBJPROP_READONLY,false);ObjectSetInteger(0,o,OBJPROP_SELECTABLE,false);}ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,o,OBJPROP_XSIZE,w);ObjectSetInteger(0,o,OBJPROP_YSIZE,h);}
void MkArrow(const string nm,datetime t,double pr,int code,color c){string o=PREFIX+nm;if(ObjectFind(0,o)<0)ObjectCreate(0,o,OBJ_ARROW,0,t,pr);else ObjectMove(0,o,0,t,pr);ObjectSetInteger(0,o,OBJPROP_ARROWCODE,code);ObjectSetInteger(0,o,OBJPROP_COLOR,c);ObjectSetInteger(0,o,OBJPROP_WIDTH,2);ObjectSetInteger(0,o,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,o,OBJPROP_HIDDEN,false);}
void MkText(const string nm,datetime t,double pr,string txt,color c){string o=PREFIX+nm;if(ObjectFind(0,o)<0)ObjectCreate(0,o,OBJ_TEXT,0,t,pr);else ObjectMove(0,o,0,t,pr);ObjectSetString(0,o,OBJPROP_TEXT,txt);ObjectSetInteger(0,o,OBJPROP_COLOR,c);ObjectSetInteger(0,o,OBJPROP_FONTSIZE,8);ObjectSetString(0,o,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,o,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,o,OBJPROP_HIDDEN,false);}

// Hide a button by moving it off-screen
void HideBtn(const string nm){string o=PREFIX+nm;if(ObjectFind(0,o)>=0){ObjectSetInteger(0,o,OBJPROP_XDISTANCE,-9999);ObjectSetInteger(0,o,OBJPROP_YDISTANCE,-9999);}}

void DrawHistoricalSignals()
{
   datetime now=TimeCurrent();
   if(!g_needsRedraw&&g_lastBuild>0&&now-g_lastBuild<300)return;
   g_lastBuild=now;g_needsRedraw=false;DelHist();
   MqlRates rates[];int copied=CopyRates(_Symbol,_Period,0,MathMax(InpCalcBars,300),rates);
   if(copied<200){g_statLine="no data";return;}
   if(rates[0].time>rates[copied-1].time)ArrayReverse(rates,0,WHOLE_ARRAY);
   NasSettings cfg;cfg.sensitivity=g_sensitivity;cfg.rsiLength=InpRsiLength;cfg.atrRisk=InpAtrRisk;cfg.atrLen=InpAtrLen;
   NasPoint p[];NAS_Calculate(rates,copied,cfg,p);
   ApplySignalMode(rates,p,copied,g_mode);
   int days=MathMax(1,MathMin(30,InpHistoryDays));datetime cutoff=now-days*86400;
   g_total=0;g_wins=0;g_losses=0;g_other=0;g_netR=0;
   g_totalWonR=0;g_totalLostR=0;g_sumRiskPts=0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.01;
   Print("NAS_V3_LAB ======= HIST Mode=",ModeLabel(g_mode)," RR=",RRLabel(g_rr)," S=",g_sensitivity,
         " HC1=",g_hcTp1?" ON":" OFF"," HC2=",g_hcTp2?" ON":" OFF"," =======");
   for(int i=1;i<copied-1;i++)
   {
      if(rates[i].time<cutoff)continue;
      if(!p[i].buy&&!p[i].sell)continue;
      if(!NAS_IsValid(p[i].nasEntry)||!NAS_IsValid(p[i].nasSl))continue;
      int d=p[i].buy?1:-1;double entry=p[i].nasEntry,sl=p[i].nasSl,risk=MathAbs(entry-sl);
      if(risk<=pt*5)continue;
      g_total++;
      g_sumRiskPts+=risk/pt;

      SimResult sim=SimulateTrade(rates,p,i,d,entry,sl,copied-1,risk,g_hcTp1,g_hcTp2,g_rr);
      if(sim.isWin)g_wins++;
      if(sim.isLoss)g_losses++;
      if(sim.outcome!="TP"&&sim.outcome!="SL")g_other++;
      g_netR+=sim.netR;
      if(sim.netR>0)g_totalWonR+=sim.netR;
      if(sim.netR<0)g_totalLostR+=MathAbs(sim.netR);

      Print("NAS_V3_LAB #",g_total," ",d>0?"BUY":"SELL"," ",TimeToString(rates[i].time,TIME_DATE|TIME_MINUTES),
            " E=",DoubleToString(entry,_Digits)," SL=",DoubleToString(sl,_Digits),
            " => ",sim.outcome," ",DoubleToString(sim.netR,2),"R");
      double pad=MathMax(MathAbs(rates[i].high-rates[i].low)*0.15,pt*40);
      double ap=d>0?rates[i].low-pad:rates[i].high+pad;
      string k="HIST_"+IntegerToString(i)+"_"+(d>0?"B":"S");
      color arClr=sim.isWin?clrLime:(sim.isLoss?clrTomato:clrGold);
      MkArrow(k+"_A",rates[i].time,ap,d>0?233:234,arClr);
      string rTxt=DoubleToString(sim.netR,2)+"R";
      MkText(k+"_T",rates[i].time,d>0?ap-pad*0.6:ap+pad*0.6,
             (d>0?"BUY ":"SELL ")+sim.outcome+" "+rTxt,
             sim.isWin?clrPaleGreen:(sim.isLoss?clrLightSalmon:clrKhaki));
   }
   int resolved=g_wins+g_losses;
   double wr=resolved>0?(double)g_wins/(double)resolved*100:0;
   g_statLine=IntegerToString(g_total)+" sig | "+IntegerToString(g_wins)+"W "+IntegerToString(g_losses)+"L "+IntegerToString(g_other)+"E"
              +" | WR "+DoubleToString(wr,1)+"%"
              +" | Net "+DoubleToString(g_netR,1)+"R";
   Print("NAS_V3_LAB ======= ",g_statLine," =======");
}

//=====================================================================
//  AUDIT ENGINE â€” Trade CSV, Position Probe, History Scan, Risk Audit
//  Pattern: Signatics Bridge EA (daily-rotated CSV, append+header)
//=====================================================================

// --- Date string for daily file rotation ---
string NasAudit_DateStr(datetime t)
{
   MqlDateTime d; TimeToStruct(t,d);
   return StringFormat("%04d%02d%02d",d.year,d.mon,d.day);
}

void NasBT_ProcessAudit(string ev,string detail)
{
   string fileName="NasV3Lab_BacktestProcess_"+NasAudit_DateStr(TimeGMT())+".csv";
   bool exists=FileIsExist(fileName);
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return;
   if(!exists||FileSize(h)==0)
      FileWrite(h,"gmt_time","server_time","event","build","symbol","chart_tf","result_file","weeks","requested_from","loaded_from","loaded_to","rates_copied","rates_requested","coverage_pct","combos_total","step","elapsed_ms","detail");
   FileSeek(h,0,SEEK_END);
   datetime loadedFrom=(g_btRatesCopied>0?g_btRates[0].time:0);
   datetime loadedTo=(g_btRatesCopied>0?g_btRates[g_btRatesCopied-1].time:0);
   double requestedSec=MathMax(1.0,(double)g_btWeeks*7.0*86400.0);
   double loadedSec=(loadedFrom>0&&loadedTo>loadedFrom)?(double)(loadedTo-loadedFrom):0.0;
   double coverage=MathMin(100.0,loadedSec/requestedSec*100.0);
   int sec=PeriodSeconds(_Period);if(sec<=0)sec=60;
   int barsNeeded=(int)MathCeil(requestedSec/(double)sec)+500;
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      ev,NAS_V2_BUILD,_Symbol,EnumToString(_Period),g_btFileName,
      IntegerToString(g_btWeeks),
      TimeToString(g_btCutoff,TIME_DATE|TIME_SECONDS),
      loadedFrom>0?TimeToString(loadedFrom,TIME_DATE|TIME_SECONDS):"",
      loadedTo>0?TimeToString(loadedTo,TIME_DATE|TIME_SECONDS):"",
      IntegerToString(g_btRatesCopied),IntegerToString(barsNeeded),
      DoubleToString(coverage,2),IntegerToString(g_btTotal),IntegerToString(g_btStep),
      IntegerToString((int)g_btElapsedMs),detail);
   FileClose(h);
}

// --- Format price with symbol digits ---
string NasAudit_Px(double p)
{
   if(p<=0) return "0";
   return DoubleToString(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}

// --- TF to string helper ---
string NasAudit_TF()
{
   return EnumToString(_Period);
}

//---------------------------------------------------------------------
// LAYER 1: Trade Lifecycle CSV
// Every signal, skip, open, close, toggle event is logged here.
// File: NasV3Lab_TradeAudit_YYYYMMDD.csv
//---------------------------------------------------------------------
void NasAudit_TradeWrite(string eventName,string source,string eventId,string direction,
                         double lot,double price,double sl,double tp,
                         string reason,double pnl,string extra)
{
   if(!InpAuditTradeCsv) return;
   string fileName="NasV3Lab_TradeAudit_"+NasAudit_DateStr(TimeGMT())+".csv";
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE){Print("NAS_AUDIT trade csv open fail err=",GetLastError());return;}
   bool empty=(FileSize(h)<=0);
   FileSeek(h,0,SEEK_END);
   if(empty)
      FileWrite(h,"ts_gmt","ts_server","ts_local","ms","event","build","symbol","timeframe",
         "mode","rr","sensitivity","hc_tp1","hc_tp2","source","event_id","direction",
         "lot","price","sl","tp","bid","ask","spread","reason","pnl","extra");
   int ms=(int)(GetTickCount()%1000);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   long sp=(long)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
      IntegerToString(ms),
      eventName, NAS_V2_BUILD, _Symbol, NasAudit_TF(),
      ModeLabel(g_mode), RRLabel(g_rr), IntegerToString(g_sensitivity),
      (g_hcTp1?"1":"0"), (g_hcTp2?"1":"0"),
      source, eventId, direction,
      DoubleToString(lot,4), NasAudit_Px(price), NasAudit_Px(sl), NasAudit_Px(tp),
      NasAudit_Px(bid), NasAudit_Px(ask), IntegerToString(sp),
      reason, DoubleToString(pnl,2), extra);
   FileClose(h);
}

//---------------------------------------------------------------------
// LAYER 2: Position Probe CSV
// Periodic snapshot of all managed positions with live R, SL dist, PnL.
// File: NasV3Lab_PositionProbe_YYYYMMDD.csv
//---------------------------------------------------------------------
void NasAudit_PositionProbe()
{
   if(!InpAuditPositionProbe) return;
   datetime now=TimeCurrent();
   int interval=MathMax(5,InpAuditPositionProbeSec);
   if(g_auditLastProbeTime>0 && now-g_auditLastProbeTime<interval) return;
   g_auditLastProbeTime=now;

   string fileName="NasV3Lab_PositionProbe_"+NasAudit_DateStr(TimeGMT())+".csv";
   string hash="";
   int count=0;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0||!PositionSelectByTicket(t)||!IsManagedPos()) continue;
      int d=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      string dir=d>0?"BUY":"SELL";
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double lots=PositionGetDouble(POSITION_VOLUME);
      double px=d>0?bid:ask;
      double risk=MathAbs(entry-sl);
      double currentR=0,targetRR=0,slDistPts=0;
      if(risk>_Point)
      {
         currentR=d>0?(px-entry)/risk:(entry-px)/risk;
         targetRR=tp>0?(d>0?(tp-entry)/risk:(entry-tp)/risk):0;
      }
      slDistPts=MathAbs(px-sl)/_Point;
      double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      count++;
      hash+=IntegerToString((int)t)+":"+DoubleToString(lots,2)+":"+NasAudit_Px(sl)+":"+DoubleToString(currentR,2)+";";

      // Write each position row
      int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
      if(h==INVALID_HANDLE) continue;
      bool empty=(FileSize(h)<=0);
      FileSeek(h,0,SEEK_END);
      if(empty)
         FileWrite(h,"ts_gmt","ts_server","ms","event","build","symbol","timeframe",
            "ticket","direction","lots","entry","sl","tp","px","bid","ask","spread",
            "risk","target_rr","current_r","sl_dist_pts","hc1","hc2","pnl","extra");
      int ms=(int)(GetTickCount()%1000);
      FileWrite(h,
         TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
         TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         IntegerToString(ms),
         "position_probe", NAS_V2_BUILD, _Symbol, NasAudit_TF(),
         IntegerToString((int)t), dir, DoubleToString(lots,4),
         NasAudit_Px(entry), NasAudit_Px(sl), NasAudit_Px(tp), NasAudit_Px(px),
         NasAudit_Px(bid), NasAudit_Px(ask),
         IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)),
         DoubleToString(risk,_Digits), DoubleToString(targetRR,3),
         DoubleToString(currentR,3), DoubleToString(slDistPts,0),
         (g_hcTp1?"1":"0"), (g_hcTp2?"1":"0"),
         DoubleToString(pnl,2), "magic="+IntegerToString(RuntimeMagic()));
      FileClose(h);
   }

   if(count<=0)
   {
      hash="flat";
      if(!InpAuditProbeOnChangeOnly || hash!=g_auditLastProbeHash)
      {
         int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
         if(h!=INVALID_HANDLE)
         {
            bool empty=(FileSize(h)<=0);
            FileSeek(h,0,SEEK_END);
            if(empty)
               FileWrite(h,"ts_gmt","ts_server","ms","event","build","symbol","timeframe",
                  "ticket","direction","lots","entry","sl","tp","px","bid","ask","spread",
                  "risk","target_rr","current_r","sl_dist_pts","hc1","hc2","pnl","extra");
            FileWrite(h,
               TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
               TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
               IntegerToString((int)(GetTickCount()%1000)),
               "position_probe_flat", NAS_V2_BUILD, _Symbol, NasAudit_TF(),
               "0","","0","0","0","0","0",
               NasAudit_Px(bid), NasAudit_Px(ask),
               IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)),
               "0","0","0","0","0","0","0","no_managed_positions");
            FileClose(h);
         }
      }
   }
   g_auditLastProbeHash=hash;
}

//---------------------------------------------------------------------
// LAYER 3: History Audit Scan
// Detects newly closed trades and writes them to the Trade Audit CSV.
// File: NasV3Lab_TradeAudit_YYYYMMDD.csv (same as Layer 1)
//---------------------------------------------------------------------
void NasAudit_HistoryScan()
{
   if(!InpAuditTradeCsv) return;
   int interval=MathMax(1,InpAuditHistoryScanSec);
   datetime now=TimeCurrent();
   if(g_auditLastHistScan>0 && now-g_auditLastHistScan<interval) return;
   g_auditLastHistScan=now;

   datetime newestTime=g_auditLastHistTime;
   ulong newestTicket=g_auditLastHistTicket;
   int scanned=0;

   if(!HistorySelect(now-86400*3,now)) return; // last 3 days

   for(int i=HistoryDealsTotal()-1;i>=0 && scanned<100;i--)
   {
      ulong dealTicket=HistoryDealGetTicket(i);
      if(dealTicket==0) continue;
      ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket,DEAL_TYPE);
      if(dt!=DEAL_TYPE_BUY && dt!=DEAL_TYPE_SELL) continue;
      ENUM_DEAL_ENTRY de=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
      if(de!=DEAL_ENTRY_OUT && de!=DEAL_ENTRY_INOUT) continue;
      if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=_Symbol) continue;
      if(!MagicOwned((long)HistoryDealGetInteger(dealTicket,DEAL_MAGIC))) continue;
      scanned++;

      datetime ct=(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
      if(ct<g_auditLastHistTime || (ct==g_auditLastHistTime && dealTicket<=g_auditLastHistTicket))
         continue;
      string dealAuditKey="NAS_V3_LAB_HIST_DEAL_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+_Symbol+"_"+IntegerToString((long)dealTicket);
      if(GlobalVariableCheck(dealAuditKey))
         continue;

      // Determine close type
      double closePx=HistoryDealGetDouble(dealTicket,DEAL_PRICE);
      double pnl=HistoryDealGetDouble(dealTicket,DEAL_PROFIT)
                +HistoryDealGetDouble(dealTicket,DEAL_SWAP)
                +HistoryDealGetDouble(dealTicket,DEAL_COMMISSION)
                +HistoryDealGetDouble(dealTicket,DEAL_FEE);
      double vol=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      string dir=dt==DEAL_TYPE_BUY?"SELL":"BUY"; // closing a SELL = BUY deal, and vice versa
      long posId=(long)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);

      // Try to find the original SL/TP from the position
      double origSl=0,origTp=0,origEntry=0;
      if(HistorySelectByPosition(posId))
      {
         for(int k=HistoryDealsTotal()-1;k>=0;k--)
         {
            ulong ot=HistoryDealGetTicket(k);
            if(ot==0) continue;
            ENUM_DEAL_ENTRY oe=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ot,DEAL_ENTRY);
            if(oe==DEAL_ENTRY_IN)
            {
               origEntry=HistoryDealGetDouble(ot,DEAL_PRICE);
               break;
            }
         }
         // Re-select the full history range
         HistorySelect(now-86400*3,now);
      }

      // Classify close type
      string eventName="history_close";
      string extra="pos_id="+IntegerToString((int)posId)+" deal="+IntegerToString((int)dealTicket);
      if(origEntry>0)
         extra+=" orig_entry="+NasAudit_Px(origEntry);

      NasAudit_TradeWrite(eventName,"NAS_V3_LAB",IntegerToString((int)dealTicket),dir,vol,closePx,origSl,origTp,
         "history_close",pnl,extra);
      GlobalVariableSet(dealAuditKey,(double)TimeCurrent());

      if(ct>newestTime || (ct==newestTime && dealTicket>newestTicket))
      {
         newestTime=ct;
         newestTicket=dealTicket;
      }
   }
   g_auditLastHistTime=newestTime;
   g_auditLastHistTicket=newestTicket;
}

//---------------------------------------------------------------------
// LAYER 3b: Account Risk Audit Snapshot
// Periodic equity/DD/margin CSV for FTMO compliance monitoring.
// File: NasV3Lab_RiskAudit_YYYYMMDD.csv
//---------------------------------------------------------------------
bool NasAudit_RiskClaimSnapshot()
{
   int interval=MathMax(15,InpAuditIntervalSec);
   string key=RiskKey("AUDIT_SNAP_GMT");
   if(!GlobalVariableCheck(key)) GlobalVariableSet(key,0.0);
   double nowD=(double)TimeGMT();
   double observed=GlobalVariableGet(key);
   if(nowD-observed<interval) return false;
   return GlobalVariableSetOnCondition(key,nowD,observed);
}

void NasAudit_RiskSnapshot()
{
   if(!InpAccountRiskEnabled || !InpAuditEnabled) return;
   if(!NasAudit_RiskClaimSnapshot()) return;

   double cap,dp,tpp;RiskMetrics(cap,dp,tpp);
   double initial=RiskInitialBal();
   double cAll,cToday,fl;RiskScopePerf(cAll,cToday,fl);
   double scopeEq=MathMax(0.01,initial+cAll+fl);
   double mu=cap>0?AccountInfoDouble(ACCOUNT_MARGIN)/cap*100:100;

   // Position summary
   int openC=0;double totalVol=0,openRisk=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))continue;
      openC++;totalVol+=PositionGetDouble(POSITION_VOLUME);
      double sl=PositionGetDouble(POSITION_SL);
      if(sl>0)
      {
         double pe=PositionGetDouble(POSITION_PRICE_OPEN);
         double pv=PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double r=0;
         if(OrderCalcProfit(pt==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
            PositionGetString(POSITION_SYMBOL),pv,pe,sl,r))
            openRisk+=MathMax(0,-r);
      }
   }

   double tb=cap*MathMax(0,InpRiskPerTradePct)/100;
   double ab=cap*MathMax(0,InpAtrExposurePct)/100;
   double pb=cap*MathMax(0,InpMaxPortfolioPct)/100;

   string fileName="NasV3Lab_RiskAudit_"+NasAudit_DateStr(TimeGMT())+".csv";
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE){Print("NAS_AUDIT risk csv open fail");return;}
   bool empty=(FileSize(h)<=0);
   FileSeek(h,0,SEEK_END);
   if(empty)
      FileWrite(h,"ts_gmt","ts_server","event","build","account","symbol","timeframe",
         "initial_balance","account_balance","account_equity","scope_closed_all","scope_closed_today",
         "scope_floating","scope_equity","risk_capital","daily_loss_pct","total_dd_pct",
         "margin","margin_usage_pct","open_positions","total_volume","open_sl_risk",
         "trade_budget","atr_budget","portfolio_budget","available_risk","safety_pct");
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      "risk_snapshot", NAS_V2_BUILD,
      IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), _Symbol, NasAudit_TF(),
      DoubleToString(initial,2), DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
      DoubleToString(cAll,2), DoubleToString(cToday,2), DoubleToString(fl,2),
      DoubleToString(scopeEq,2), DoubleToString(cap,2),
      DoubleToString(dp,3), DoubleToString(tpp,3),
      DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN),2), DoubleToString(mu,3),
      IntegerToString(openC), DoubleToString(totalVol,3), DoubleToString(openRisk,2),
      DoubleToString(tb,2), DoubleToString(ab,2), DoubleToString(pb,2),
      DoubleToString(MathMax(0,pb-openRisk),2), DoubleToString(InpSafetyBufferPct,1));
   FileClose(h);
}

//=====================================================================
//  BRUTE-FORCE BACKTEST ENGINE (async state machine)
//=====================================================================
void BT_GenerateCombos()
{
   ArrayResize(g_btCombos,0);
   for(int si=0;si<BT_SENS_COUNT;si++)
   for(int mi=0;mi<BT_MODE_COUNT;mi++)
   for(int ri=0;ri<3;ri++)
   {
      if(ri==0){BtCombo c;c.sensIdx=si;c.modeIdx=mi;c.rrIdx=ri;c.hc1=false;c.hc2=false;int n=ArraySize(g_btCombos);ArrayResize(g_btCombos,n+1);g_btCombos[n]=c;}
      else if(ri==1){for(int h=0;h<2;h++){BtCombo c;c.sensIdx=si;c.modeIdx=mi;c.rrIdx=ri;c.hc1=(h==1);c.hc2=false;int n=ArraySize(g_btCombos);ArrayResize(g_btCombos,n+1);g_btCombos[n]=c;}}
      else{for(int h1=0;h1<2;h1++)for(int h2=0;h2<2;h2++){BtCombo c;c.sensIdx=si;c.modeIdx=mi;c.rrIdx=ri;c.hc1=(h1==1);c.hc2=(h2==1);int n=ArraySize(g_btCombos);ArrayResize(g_btCombos,n+1);g_btCombos[n]=c;}}
   }
   g_btTotal=ArraySize(g_btCombos);
}

void BT_PrecomputeSignals()
{
   ArrayFree(g_btSigs);
   ArrayInitialize(g_btSigOffset,0);
   ArrayInitialize(g_btSigCount,0);
   // Layer 1: CopyRates (already done in g_btRates)
   NasSettings cfg;cfg.rsiLength=InpRsiLength;cfg.atrRisk=InpAtrRisk;cfg.atrLen=InpAtrLen;
   for(int si=0;si<BT_SENS_COUNT;si++)
   {
      cfg.sensitivity=g_btSensVals[si];
      // Layer 2: NAS_Calculate per sensitivity
      NasPoint baseP[];NAS_Calculate(g_btRates,g_btRatesCopied,cfg,baseP);
      for(int mi=0;mi<BT_MODE_COUNT;mi++)
      {
         // Layer 3: ApplySignalMode on copy
         NasPoint modeP[];ArrayResize(modeP,g_btRatesCopied);
         for(int k=0;k<g_btRatesCopied;k++) modeP[k]=baseP[k];
         ApplySignalMode(g_btRates,modeP,g_btRatesCopied,g_btModes[mi]);
         // Extract signals into lightweight BtSignal[]
         int gIdx=si*BT_MODE_COUNT+mi;
         g_btSigOffset[gIdx]=ArraySize(g_btSigs);
         g_btSigCount[gIdx]=0;
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.01;
         for(int i=1;i<g_btRatesCopied-1;i++)
         {
            if(g_btRates[i].time<g_btCutoff) continue;
            if(!modeP[i].buy&&!modeP[i].sell) continue;
            if(!NAS_IsValid(modeP[i].nasEntry)||!NAS_IsValid(modeP[i].nasSl)) continue;
            int d=modeP[i].buy?1:-1;
            double risk=MathAbs(modeP[i].nasEntry-modeP[i].nasSl);
            if(risk<=pt*5) continue;
            BtSignal s;s.barIdx=i;s.dir=d;s.entry=modeP[i].nasEntry;s.sl=modeP[i].nasSl;s.risk=risk;s.nextSig=-1;
            int n=g_btSigCount[gIdx];
            int flat=ArraySize(g_btSigs);
            ArrayResize(g_btSigs,flat+1);
            g_btSigs[flat]=s;
            // Link previous signal's nextSig
            if(n>0) g_btSigs[g_btSigOffset[gIdx]+n-1].nextSig=i;
            g_btSigCount[gIdx]=n+1;
         }
      }
   }
}

void BT_Start()
{
   if(g_btRunning) return;
   g_btWeeks=MathMax(1,g_btWeeks);
   g_btStartMs=GetTickCount();
   g_btElapsedMs=0;
   g_btCutoff=TimeCurrent()-g_btWeeks*7*86400;
   // Layer 1: CopyRates
   int sec=PeriodSeconds(_Period);
   if(sec<=0)sec=60;
   int barsNeeded=(int)MathCeil((double)g_btWeeks*7.0*86400.0/(double)sec)+500;
   int copyBars=MathMax(MathMax(InpCalcBars,300),barsNeeded);
   g_btRatesCopied=CopyRates(_Symbol,_Period,0,copyBars,g_btRates);
   if(g_btRatesCopied<200){g_btTotal=0;g_btStep=0;NasBT_ProcessAudit("start_failed","not_enough_data copyBars="+IntegerToString(copyBars));Print("BT: not enough data");return;}
   if(g_btRates[0].time>g_btRates[g_btRatesCopied-1].time) ArrayReverse(g_btRates,0,WHOLE_ARRAY);
   // Generate combos
   BT_GenerateCombos();
   // Precompute (Layer 2+3) â€” ~400ms blocking, acceptable
   BT_PrecomputeSignals();
   // Open CSV
   MqlDateTime d;TimeToStruct(TimeGMT(),d);
   g_btFileName="NasV3Lab_BruteBacktest_"+StringFormat("%04d%02d%02d_%02d%02d%02d",d.year,d.mon,d.day,d.hour,d.min,d.sec)+".csv";
   int h=FileOpen(g_btFileName,FILE_CSV|FILE_WRITE|FILE_SHARE_READ,',');
   if(h!=INVALID_HANDLE)
   {
      FileWrite(h,"timestamp","symbol","chart_tf","signal_mode","sensitivity","rr_mode","hc_tp1","hc_tp2","weeks",
         "effective_from","loaded_from","loaded_to","rates_copied",
         "fill_mode","same_bar_policy","spread_pts","slippage_pts","commission_per_lot",
         "total_signals","wins","losses","other","win_rate","be_win_rate",
         "total_won_r","total_lost_r","net_r","pf","edge_pct","avg_r_per_trade");
      FileClose(h);
   }
   g_btStep=0;g_btRunning=true;g_btLastResult="Starting...";
   string coverageDetail=(g_btRatesCopied>0&&g_btRates[0].time>g_btCutoff)?"insufficient_history":"ok";
   coverageDetail+=" effective_from="+TimeToString(g_btCutoff,TIME_DATE|TIME_SECONDS)+" copyBars="+IntegerToString(copyBars)+" first="+(g_btRatesCopied>0?TimeToString(g_btRates[0].time,TIME_DATE|TIME_SECONDS):"")+" note=loaded_from_includes_warmup";
   NasBT_ProcessAudit("start",coverageDetail);
   Print("BT: started ",g_btTotal," combos, ",g_btWeeks," weeks");
}

void BT_Tick()
{
   if(!g_btRunning||g_btStep>=g_btTotal) return;
   BtCombo combo=g_btCombos[g_btStep];
   int gIdx=combo.sensIdx*BT_MODE_COUNT+combo.modeIdx;
   int sigN=g_btSigCount[gIdx];
   NAS_RR_MODE rr=(NAS_RR_MODE)combo.rrIdx;
   double rrm=RRMult(rr);
   // Simulate all signals for this combo
   BtStats st;st.total=0;st.wins=0;st.losses=0;st.other=0;st.wonR=0;st.lostR=0;st.netR=0;
   for(int s=0;s<sigN;s++)
   {
      BtSignal sig=g_btSigs[g_btSigOffset[gIdx]+s];
      int endBar=(sig.nextSig>0)?sig.nextSig-1:g_btRatesCopied-1;
      // Inline lightweight simulation (same math as SimulateTrade but without NasPoint[])
      double e=sig.entry,sl=sig.sl,risk=sig.risk;
      int d=sig.dir,si=sig.barIdx;
      if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN && si+1<g_btRatesCopied) e=g_btRates[si+1].open;
      else if(g_btFillMode==BT_FILL_CONSERVATIVE && si+1<g_btRatesCopied)
      {
         double no=g_btRates[si+1].open;
         e=d>0?MathMax(e,no):MathMin(e,no);
      }
      risk=MathAbs(e-sl);
      if(risk<=0)continue;
      double tp1=d>0?e+risk:e-risk;
      double tp2=d>0?e+risk*2.0:e-risk*2.0;
      double fTp=d>0?e+risk*rrm:e-risk*rrm;
      double curSl=sl,lotFrac=1.0,accR=0;
      bool tp1Done=false,tp2Done=false,resolved=false;
      for(int j=si+1;j<=endBar&&!resolved;j++)
      {
         bool slH=d>0?(g_btRates[j].low<=curSl):(g_btRates[j].high>=curSl);
         bool t1H=!tp1Done&&(d>0?(g_btRates[j].high>=tp1):(g_btRates[j].low<=tp1));
         bool fH=d>0?(g_btRates[j].high>=fTp):(g_btRates[j].low<=fTp);
         if(slH&&fH){
            if(BtTpFirst(d,g_btRates[j].open,curSl,fTp)){if(t1H&&combo.hc1&&rrm>=2){accR+=lotFrac*0.5;lotFrac*=0.5;curSl=e;tp1Done=true;}
               bool t2H=!tp2Done&&rrm>=3&&(d>0?(g_btRates[j].high>=tp2):(g_btRates[j].low<=tp2));
               if(t2H&&combo.hc2&&rrm>=3){accR+=2*lotFrac*0.5;lotFrac*=0.5;tp2Done=true;}
               accR+=rrm*lotFrac;resolved=true;
            }else{double slR=(curSl==e)?0:-1;accR+=slR*lotFrac;
               resolved=true;}continue;}
         if(t1H&&combo.hc1&&rrm>=2){accR+=lotFrac*0.5;lotFrac*=0.5;curSl=e;tp1Done=true;}
         bool t2H=!tp2Done&&rrm>=3&&(d>0?(g_btRates[j].high>=tp2):(g_btRates[j].low<=tp2));
         if(t2H&&combo.hc2&&rrm>=3){accR+=2*lotFrac*0.5;lotFrac*=0.5;tp2Done=true;}
         if(tp1Done||tp2Done) slH=d>0?(g_btRates[j].low<=curSl):(g_btRates[j].high>=curSl);
         if(fH){accR+=rrm*lotFrac;resolved=true;}
         else if(slH){double slR=(curSl==e)?0:-1;accR+=slR*lotFrac;
            resolved=true;}
         else if(j-si>=200){double cp=g_btRates[j].close;double pnl=d>0?(cp-e):(e-cp);accR+=(pnl/risk)*lotFrac;
            resolved=true;}
      }
      if(!resolved){// closed by next signal
         if(endBar<g_btRatesCopied-1){double cp=g_btRates[endBar+1].open;double pnl=d>0?(cp-e):(e-cp);accR+=(pnl/risk)*lotFrac;}
      }
      double finalR=accR-BtCostR(risk);
      if(finalR>0){st.wonR+=finalR;st.wins++;}else if(finalR<0){st.lostR+=MathAbs(finalR);st.losses++;}else st.other++;
      st.total++;
      st.netR+=finalR;
   }
   // Write CSV row
   BT_WriteRow(combo,st);
   // Update state
   int res=st.wins+st.losses;
   double wr=res>0?(double)st.wins/res*100:0;
   g_btLastResult=ModeLabel(g_btModes[combo.modeIdx])+" S="+IntegerToString(g_btSensVals[combo.sensIdx])
      +" "+RRLabel((NAS_RR_MODE)combo.rrIdx)+(combo.hc1?" HC1":"")+(combo.hc2?" HC2":"")
      +" "+IntegerToString(st.wins)+"W "+IntegerToString(st.losses)+"L WR="+DoubleToString(wr,1)+"% Net="+DoubleToString(st.netR,1)+"R";
   g_btStep++;
   if(g_btStep>=g_btTotal) BT_Finish();
   UpdateDashboard();ChartRedraw(0);
}

void BT_WriteRow(const BtCombo &c,const BtStats &s)
{
   int h=FileOpen(g_btFileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   int res=s.wins+s.losses;
   double wr=res>0?(double)s.wins/res*100:0;
   NAS_RR_MODE rr=(NAS_RR_MODE)c.rrIdx;
   double beWr=1.0/(1.0+RRMult(rr))*100;
   double pf=s.lostR>0?s.wonR/s.lostR:(s.wonR>0?99.9:0);
   double edge=wr-beWr;
   double avgR=s.total>0?s.netR/s.total:0;
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      _Symbol,EnumToString(_Period),
      ModeLabel(g_btModes[c.modeIdx]),IntegerToString(g_btSensVals[c.sensIdx]),
      RRLabel(rr),(c.hc1?"1":"0"),(c.hc2?"1":"0"),IntegerToString(g_btWeeks),
      TimeToString(g_btCutoff,TIME_DATE|TIME_SECONDS),
      g_btRatesCopied>0?TimeToString(g_btRates[0].time,TIME_DATE|TIME_SECONDS):"",
      g_btRatesCopied>0?TimeToString(g_btRates[g_btRatesCopied-1].time,TIME_DATE|TIME_SECONDS):"",
      IntegerToString(g_btRatesCopied),
      BtFillLabel(g_btFillMode),BtSameBarLabel(g_btSameBarPolicy),
      DoubleToString(g_btSpreadPts,2),DoubleToString(g_btSlippagePts,2),DoubleToString(g_btCommissionPerLot,2),
      IntegerToString(s.total),IntegerToString(s.wins),IntegerToString(s.losses),IntegerToString(s.other),
      DoubleToString(wr,2),DoubleToString(beWr,2),
      DoubleToString(s.wonR,2),DoubleToString(s.lostR,2),DoubleToString(s.netR,2),
      DoubleToString(pf,2),DoubleToString(edge,2),DoubleToString(avgR,3));
   FileClose(h);
}

void BT_Finish()
{
   g_btRunning=false;
   g_btElapsedMs=GetTickCount()-g_btStartMs;
   uint elapsed=g_btElapsedMs;
   Print("BT: COMPLETE ",g_btTotal," combos in ",elapsed,"ms â†’ ",g_btFileName);
   g_btLastResult="DONE "+IntegerToString(g_btTotal)+" combos in "+DoubleToString(g_btElapsedMs/1000.0,1)+"s";
   NasBT_ProcessAudit("finish","completed");
   // Free cached data
   ArrayFree(g_btRates);g_btRatesCopied=0;
   ArrayFree(g_btSigs);ArrayInitialize(g_btSigOffset,0);ArrayInitialize(g_btSigCount,0);
   ArrayFree(g_btCombos);
}

void BT_Stop()
{
   if(!g_btRunning) return;
   g_btRunning=false;
   g_btLastResult="STOPPED at "+IntegerToString(g_btStep)+"/"+IntegerToString(g_btTotal);
   ArrayFree(g_btRates);g_btRatesCopied=0;
   ArrayFree(g_btSigs);ArrayInitialize(g_btSigOffset,0);ArrayInitialize(g_btSigCount,0);
   ArrayFree(g_btCombos);
   Print("BT: stopped at step ",g_btStep);
}

//=====================================================================
//  DASHBOARD â€” v2.2 wide layout (640x570)
//=====================================================================
void DrawDashboard()
{
   if(!InpShowDashboard){DelDash();return;}
   int x=InpDashX,y=InpDashY,W=640,H=570;
   // Main panel
   MkRect("DASH_BG",x,y,W,H,C'20,26,36',C'55,130,200');
   // Title bar
   MkRect("DASH_TOP",x,y,W,32,C'14,18,28',C'55,130,200');
   MkRect("DASH_STRIPE",x+6,y+6,W-12,3,C'80,165,245',C'80,165,245');
   MkLabel("DASH_TITLE",x+14,y+12,"NAS SIGNAL LAB v2.2 // "+NAS_V2_BUILD,C'220,228,238',10);
   UpdateDashboard();
}
void UpdateDashboard()
{
   if(!InpShowDashboard)return;
   int x=InpDashX,y=InpDashY,W=640;
   color ac=C'80,165,245',mt=C'150,162,178',on=C'25,115,65',off=C'68,68,76';
   int bh=20; // button height (standard)
   int pad=14; // left padding
   int iW=W-2*pad; // inner content width

   // â”€â”€â”€â”€â”€â”€â”€ ROW 0: Active config summary â”€â”€â”€â”€â”€â”€â”€
   int ry=y+38;
   string hcLbl="";
   if(g_rr==NAS_RR_2) hcLbl=g_hcTp1?" [HC@TP1]":"";
   if(g_rr==NAS_RR_3) hcLbl=(g_hcTp1?" [HC@1]":"")+(g_hcTp2?" [HC@2]":"");
   MkLabel("DASH_L1",x+pad,ry,
           ModeLabel(g_mode)+" | "+RRLabel(g_rr)+hcLbl+" | S="+IntegerToString(g_sensitivity)+" | "+EnumToString(_Period)+" | "+_Symbol,
           C'80,255,180',8);

   // â”€â”€â”€â”€â”€â”€â”€ SECTION: CONTROLS â”€â”€â”€â”€â”€â”€â”€
   int secY=ry+20;
   MkRect("DASH_SEC1_BG",x+4,secY,W-8,82,C'26,32,44',C'45,90,150');
   MkLabel("DASH_SEC1_T",x+pad,secY+4,"â–¸ CONTROLS",ac,8);
   MkRect("DASH_SEC1_L",x+pad,secY+18,iW,1,C'45,90,150',C'45,90,150');

   // Signal mode buttons â€” row 1
   int btnY1=secY+24;
   MkLabel("DASH_MLBL",x+pad,btnY1+3,"SIGNAL:",C'120,140,165',7);
   int bx=x+pad+62;int bw=90;int bg=4;
   MkBtn("BTN_M0",bx,          btnY1,bw,bh,"ST+SMA13",g_mode==NAS_MODE_ST_SMA13?on:off);
   MkBtn("BTN_M1",bx+(bw+bg),  btnY1,bw,bh,"ST ONLY", g_mode==NAS_MODE_ST_ONLY?on:off);
   MkBtn("BTN_M2",bx+2*(bw+bg),btnY1,bw,bh,"ST+SMA8", g_mode==NAS_MODE_ST_SMA8?on:off);
   MkBtn("BTN_M3",bx+3*(bw+bg),btnY1,bw,bh,"ST+SMA5", g_mode==NAS_MODE_ST_SMA5?on:off);
   MkBtn("BTN_M4",bx+4*(bw+bg),btnY1,bw-4,bh,"ST+SMA21",g_mode==NAS_MODE_ST_SMA21?on:off);

   // RR + Sensitivity + HC â€” row 2
   int btnY2=btnY1+26;
   MkLabel("DASH_RLBL",x+pad,btnY2+3,"R:R:",C'120,140,165',7);
   int rx=x+pad+42;
   MkBtn("BTN_RR0",rx,      btnY2,52,bh,"1:1R",g_rr==NAS_RR_1?on:off);
   MkBtn("BTN_RR1",rx+56,   btnY2,52,bh,"1:2R",g_rr==NAS_RR_2?on:off);
   MkBtn("BTN_RR2",rx+112,  btnY2,52,bh,"1:3R",g_rr==NAS_RR_3?on:off);

   // Sensitivity buttons
   MkLabel("DASH_SLBL",x+pad+215,btnY2+3,"SENS:",C'120,140,165',7);
   int sx=x+pad+258;int sw=42;
   MkBtn("BTN_S2",sx,       btnY2,sw,bh,"S=2",g_sensitivity==2?on:off);
   MkBtn("BTN_S3",sx+(sw+3),btnY2,sw,bh,"S=3",g_sensitivity==3?on:off);
   MkBtn("BTN_S4",sx+2*(sw+3),btnY2,sw,bh,"S=4",g_sensitivity==4?on:off);
   MkBtn("BTN_S5",sx+3*(sw+3),btnY2,sw,bh,"S=5",g_sensitivity==5?on:off);
   MkBtn("BTN_S6",sx+4*(sw+3),btnY2,sw,bh,"S=6",g_sensitivity==6?on:off);

   // HC+BE â€” row 3 (conditional, inside CONTROLS section)
   int btnY3=btnY2+26;
   color hcOn=C'0,85,130',hcOff=C'55,55,62';
   if(g_rr==NAS_RR_1)
   {
      HideBtn("BTN_HC1"); HideBtn("BTN_HC2");
      MkLabel("DASH_HCLBL",x+pad,btnY3+3,"HC+BE: N/A (1:1R)",C'85,85,95',7);
   }
   else if(g_rr==NAS_RR_2)
   {
      MkLabel("DASH_HCLBL",x+pad,btnY3+3,"HC+BE:",C'120,140,165',7);
      MkBtn("BTN_HC1",x+pad+62,btnY3,120,bh,g_hcTp1?"HC@TP1: ON":"HC@TP1: OFF",g_hcTp1?hcOn:hcOff);
      HideBtn("BTN_HC2");
   }
   else // 1:3R
   {
      MkLabel("DASH_HCLBL",x+pad,btnY3+3,"HC+BE:",C'120,140,165',7);
      MkBtn("BTN_HC1",x+pad+62,btnY3,120,bh,g_hcTp1?"HC@TP1: ON":"HC@TP1: OFF",g_hcTp1?hcOn:hcOff);
      MkBtn("BTN_HC2",x+pad+188,btnY3,120,bh,g_hcTp2?"HC@TP2: ON":"HC@TP2: OFF",g_hcTp2?hcOn:hcOff);
   }

   // â”€â”€â”€â”€â”€â”€â”€ SECTION: AUDIT RESULTS â”€â”€â”€â”€â”€â”€â”€
   int sec2Y=secY+88;
   MkRect("DASH_SEC2_BG",x+4,sec2Y,W-8,126,C'26,32,44',C'45,90,150');
   MkLabel("DASH_SEC2_T",x+pad,sec2Y+4,
           "â–¸ AUDIT  "+IntegerToString(InpHistoryDays)+"D | "+ModeLabel(g_mode)+" | "+RRLabel(g_rr)
           +(g_hcTp1?" +HC@1":"")+(g_hcTp2?" +HC@2":""),ac,8);
   MkRect("DASH_SEC2_L",x+pad,sec2Y+18,iW,1,C'45,90,150',C'45,90,150');

   int resolved=g_wins+g_losses;
   double wr=resolved>0?(double)g_wins/(double)resolved*100:0;
   color wc=wr>=50?C'80,255,180':C'255,95,140';

   // Stats line 1: signal count + WR
   int stY=sec2Y+24;
   MkLabel("DASH_S1a",x+pad,stY,
           IntegerToString(g_total)+" signals | "+IntegerToString(g_wins)+"W  "+IntegerToString(g_losses)+"L  "+IntegerToString(g_other)+"E"
           +"  |  WR "+DoubleToString(wr,1)+"%  ("+IntegerToString(resolved)+" resolved)",wc,9);

   // Stats line 2: R Won / R Lost / Net
   int stY2=stY+20;
   MkLabel("DASH_RWON",x+pad,stY2,
           "Won: +"+DoubleToString(g_totalWonR,2)+"R  |  Lost: -"+DoubleToString(g_totalLostR,2)+"R  |  Net: "+DoubleToString(g_netR,2)+"R",
           g_netR>=0?C'80,255,180':C'255,95,140',9);

   // Stats line 3: dollar PnL
   int stY3=stY2+18;
   double tickVal=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSz=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double pt2=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt2<=0)pt2=0.01;
   double avgRiskPts=g_total>0?g_sumRiskPts/(double)g_total:0;
   double dolPerR=(tickSz>0&&tickVal>0)?(avgRiskPts*(tickVal/tickSz)*InpFixedLot*pt2):0;
   if(dolPerR>0)
   {
      double dolWon=g_totalWonR*dolPerR;
      double dolLost=g_totalLostR*dolPerR;
      double dolNet=g_netR*dolPerR;
      MkLabel("DASH_PNL",x+pad,stY3,
              "~PnL: +$"+DoubleToString(dolWon,0)+"  /  -$"+DoubleToString(dolLost,0)+"  =  $"+DoubleToString(dolNet,0)
              +"  ("+DoubleToString(InpFixedLot,2)+" lot)",
              dolNet>=0?C'80,255,180':C'255,95,140',8);
   }
   else
      MkLabel("DASH_PNL",x+pad,stY3,"E[R]="+DoubleToString(g_total>0?g_netR/(double)g_total:0,3)+"R/trade",mt,8);

   // WR bar
   int barY=stY3+18;
   int barW=iW,barH=12;
   MkRect("DASH_WRB",x+pad,barY,barW,barH,C'38,46,60',C'80,100,130');
   int fw=(int)MathRound((double)barW*MathMax(0,MathMin(100,wr))/100);
   if(fw>2)MkRect("DASH_WRF",x+pad+1,barY+1,fw-2,barH-2,wc,wc);

   // PF / Edge line
   int pfY=barY+18;
   double pf=g_totalLostR>0?g_totalWonR/g_totalLostR:(g_totalWonR>0?99.9:0);
   double be_wr=1.0/(1.0+RRMult(g_rr))*100;
   string edge=wr>be_wr?"EDGE +"+DoubleToString(wr-be_wr,1)+"%":"NO EDGE";
   MkLabel("DASH_PF",x+pad,pfY,
           "PF "+DoubleToString(pf,2)+"  |  BE WR="+DoubleToString(be_wr,1)+"%  |  "+edge,
           wr>be_wr?C'80,255,180':C'255,95,140',9);

   // â”€â”€â”€â”€â”€â”€â”€ SECTION: EXECUTION â”€â”€â”€â”€â”€â”€â”€
   int sec3Y=sec2Y+132;
   MkRect("DASH_SEC3_BG",x+4,sec3Y,W-8,100,C'26,32,44',C'45,90,150');
   MkLabel("DASH_SEC3_T",x+pad,sec3Y+4,"â–¸ EXECUTION",ac,8);
   MkRect("DASH_SEC3_L",x+pad,sec3Y+18,iW,1,C'45,90,150',C'45,90,150');

   // EA + Close buttons
   int exY=sec3Y+24;
   MkBtn("BTN_EA",x+pad,exY,100,bh,g_eaEnabled?"EA: ON":"EA: OFF",g_eaEnabled?C'30,150,95':C'178,37,57');
   MkBtn("BTN_CLOSE",x+pad+108,exY,96,bh,"CLOSE ALL",C'178,37,57');

   // Spread status (same row, right side)
   string spTxt="Spread: "+g_lastSpreadStatus+" "+DoubleToString(g_lastSpreadPts,0)+"pts";
   MkLabel("DASH_SP",x+pad+220,exY+3,spTxt,
           g_lastSpreadStatus=="GOOD"?C'80,255,180':(g_lastSpreadStatus=="BLOCKED"?C'255,95,140':C'255,204,82'),8);

   // Window + status
   int exY2=exY+24;
   MkLabel("DASH_WIN",x+pad,exY2,
           "Window: "+WindowText()+"  |  Legs: "+IntegerToString(ManagedCount())+"  |  "+g_lastStatus,
           IsWindowOpen()?C'80,255,180':C'255,204,82',8);

   // Block reason or magic
   int exY3=exY2+20;
   if(g_lastBlockReason!="")
      MkLabel("DASH_BLK",x+pad,exY3,"Block: "+g_lastBlockReason,C'255,204,82',7);
   else
      MkLabel("DASH_BLK",x+pad,exY3,"Magic: "+IntegerToString(RuntimeMagic())+"  |  FTMO: "+(InpAccountRiskEnabled?"ON":"OFF"),C'125,140,160',7);

   // Risk info
   int exY4=exY3+18;
   if(InpAccountRiskEnabled)
   {
      double cap,dp,tpp;RiskMetrics(cap,dp,tpp);
      MkLabel("DASH_RISK",x+pad,exY4,
              "Risk: Daily "+DoubleToString(dp,1)+"% / "+DoubleToString(InpDailyLossLimitPct,0)+"%  |  DD "+DoubleToString(tpp,1)+"% / "+DoubleToString(InpMaxDrawdownPct,0)+"%  |  Lot "+DoubleToString(g_lastAdvLot,4),
              dp>InpDailyLossLimitPct*0.8?C'255,95,140':C'125,140,160',7);
   }
   else
      MkLabel("DASH_RISK",x+pad,exY4,"FixedLot="+DoubleToString(InpFixedLot,4)+"  |  RiskMult="+DoubleToString(InpPineRiskMult,3),C'125,140,160',7);

   // â”€â”€â”€â”€â”€â”€â”€ SECTION: BACKTEST ENGINE â”€â”€â”€â”€â”€â”€â”€
   int sec4Y=sec3Y+106;
   MkRect("DASH_SEC4_BG",x+4,sec4Y,W-8,142,C'26,32,44',C'45,90,150');
   MkLabel("DASH_SEC4_T",x+pad,sec4Y+4,"â–¸ BACKTEST ENGINE",ac,8);
   MkRect("DASH_SEC4_L",x+pad,sec4Y+18,iW,1,C'45,90,150',C'45,90,150');

   // Weeks input + buttons
   int btY=sec4Y+24;
   MkLabel("DASH_BTWLBL",x+pad,btY+3,"Weeks:",C'120,140,165',7);
   // OBJ_EDIT for weeks input
   string editName=PREFIX+"EDIT_BT_WEEKS";
   if(ObjectFind(0,editName)<0)
   {
      ObjectCreate(0,editName,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,editName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetString(0,editName,OBJPROP_TEXT,IntegerToString(g_btWeeks));
      ObjectSetInteger(0,editName,OBJPROP_BGCOLOR,C'38,46,60');
      ObjectSetInteger(0,editName,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,editName,OBJPROP_BORDER_COLOR,C'80,100,130');
      ObjectSetInteger(0,editName,OBJPROP_FONTSIZE,9);
      ObjectSetString(0,editName,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,editName,OBJPROP_ALIGN,ALIGN_CENTER);
      ObjectSetInteger(0,editName,OBJPROP_READONLY,false);
      ObjectSetInteger(0,editName,OBJPROP_SELECTABLE,false);
   }
   ObjectSetInteger(0,editName,OBJPROP_XDISTANCE,x+pad+52);
   ObjectSetInteger(0,editName,OBJPROP_YDISTANCE,btY);
   ObjectSetInteger(0,editName,OBJPROP_XSIZE,42);
   ObjectSetInteger(0,editName,OBJPROP_YSIZE,bh);

   color runBg=g_btRunning?C'80,80,80':C'30,120,70';
   MkBtn("BTN_BT_RUN",x+pad+100,btY,130,bh,g_btRunning?"RUNNING...":"â–¶ RUN BACKTEST",runBg);
   MkBtn("BTN_BT_STOP",x+pad+236,btY,70,bh,"â–  STOP",g_btRunning?C'178,37,57':C'60,60,68');

   // Combo count label
   MkLabel("DASH_BTCNT",x+pad+316,btY+3,"175 combos",C'100,112,130',7);

   int optY=btY+26;
   MkLabel("DASH_BTFILL_L",x+pad,optY+3,"Fill:",C'120,140,165',7);
   MkBtn("BTN_BTF_SIGNAL",x+pad+38,optY,58,bh,"SIGNAL",g_btFillMode==BT_FILL_SIGNAL_CLOSE?C'38,101,176':C'55,55,62');
   MkBtn("BTN_BTF_NEXT",x+pad+100,optY,50,bh,"NEXT",g_btFillMode==BT_FILL_NEXT_BAR_OPEN?C'38,101,176':C'55,55,62');
   MkBtn("BTN_BTF_CONS",x+pad+154,optY,50,bh,"CONS",g_btFillMode==BT_FILL_CONSERVATIVE?C'38,101,176':C'55,55,62');
   MkLabel("DASH_BTSB_L",x+pad+214,optY+3,"Same:",C'120,140,165',7);
   MkBtn("BTN_BTSB_CONS",x+pad+254,optY,50,bh,"CONS",g_btSameBarPolicy==BT_SAMEBAR_CONSERVATIVE?C'38,101,176':C'55,55,62');
   MkBtn("BTN_BTSB_NEAR",x+pad+308,optY,50,bh,"NEAR",g_btSameBarPolicy==BT_SAMEBAR_NEAREST_OPEN?C'38,101,176':C'55,55,62');
   MkBtn("BTN_BTSB_TP",x+pad+362,optY,52,bh,"TP1ST",g_btSameBarPolicy==BT_SAMEBAR_TP_FIRST?C'38,101,176':C'55,55,62');
   MkBtn("BTN_BTSB_SL",x+pad+418,optY,52,bh,"SL1ST",g_btSameBarPolicy==BT_SAMEBAR_SL_FIRST?C'38,101,176':C'55,55,62');

   int costY=optY+24;
   MkLabel("DASH_BTSP_L",x+pad,costY+3,"Spr:",C'120,140,165',7);
   MkEdit("EDIT_BT_SPREAD",x+pad+28,costY,46,bh,DoubleToString(g_btSpreadPts,1));
   MkLabel("DASH_BTSLIP_L",x+pad+82,costY+3,"Slip:",C'120,140,165',7);
   MkEdit("EDIT_BT_SLIP",x+pad+118,costY,46,bh,DoubleToString(g_btSlippagePts,1));
   MkLabel("DASH_BTCOMM_L",x+pad+172,costY+3,"Comm/Lot:",C'120,140,165',7);
   MkEdit("EDIT_BT_COMM",x+pad+236,costY,58,bh,DoubleToString(g_btCommissionPerLot,2));
   MkLabel("DASH_BTASSUMP",x+pad+304,costY+3,"defaults=0 means old model",C'100,112,130',7);

   // Progress bar
   int pbY=costY+26;
   int pbW=iW,pbH=14;
   MkRect("DASH_BTPB_BG",x+pad,pbY,pbW,pbH,C'38,46,60',C'60,80,110');
   if(g_btRunning||g_btStep>0)
   {
      double pct=g_btTotal>0?(double)g_btStep/(double)g_btTotal:0;
      int fw=(int)MathRound(pbW*MathMax(0,MathMin(1,pct)));
      if(fw>2) MkRect("DASH_BTPB_FG",x+pad+1,pbY+1,fw-2,pbH-2,C'60,200,120',C'60,200,120');
      else MkRect("DASH_BTPB_FG",x+pad+1,pbY+1,1,pbH-2,C'38,46,60',C'38,46,60');
      uint elapsed=g_btRunning?(GetTickCount()-g_btStartMs):g_btElapsedMs;
      string pTxt=IntegerToString(g_btStep)+"/"+IntegerToString(g_btTotal)
         +" ("+IntegerToString((int)(pct*100))+"%)  "
         +DoubleToString(elapsed/1000.0,1)+"s";
      MkLabel("DASH_BTPROG",x+pad+4,pbY+1,pTxt,clrWhite,8);
   }
   else
   {
      MkRect("DASH_BTPB_FG",x+pad+1,pbY+1,1,pbH-2,C'38,46,60',C'38,46,60');
      MkLabel("DASH_BTPROG",x+pad+4,pbY+1,g_btLastResult!=""?g_btLastResult:"Ready",C'100,112,130',8);
   }

   // Last result line
   int lrY=pbY+18;
   if(g_btRunning&&g_btStep>0)
      MkLabel("DASH_BTLAST",x+pad,lrY,g_btLastResult,C'150,200,170',7);
   else if(g_btLastResult!="")
      MkLabel("DASH_BTLAST",x+pad,lrY,g_btLastResult,C'100,112,130',7);
   else
      MkLabel("DASH_BTLAST",x+pad,lrY,"",C'100,112,130',7);

   // â”€â”€â”€â”€â”€â”€â”€ FOOTER â”€â”€â”€â”€â”€â”€â”€
   int fY=sec4Y+148;
   MkRect("DASH_FOOT_L",x+pad,fY,iW,1,C'45,90,150',C'45,90,150');
   MkLabel("DASH_VER",x+pad,fY+4,
           "ATR("+IntegerToString(InpAtrLen)+")x"+IntegerToString(InpAtrRisk)
           +"  |  ST ATR(11)x"+IntegerToString(g_sensitivity)
           +"  |  SameDir="+(InpBlockSameDir?"BLOCK":"ALLOW"),C'100,112,130',7);
}

//=====================================================================
//  EVENT HANDLERS
//=====================================================================
int OnInit()
{
   g_mode=InpSignalMode;g_rr=InpRRMode;g_sensitivity=MathMax(1,MathMin(10,InpSensitivity));
   g_eaEnabled=InpEaEnabled;g_needsRedraw=true;g_lastBuild=0;
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;
   g_btSpreadPts=InpBacktestSpreadPts;g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   g_equityPeak=AccountInfoDouble(ACCOUNT_EQUITY);
   // Auto-disable HC based on RR
   if(g_rr==NAS_RR_1){g_hcTp1=false;g_hcTp2=false;}
   if(g_rr==NAS_RR_2){g_hcTp2=false;}
   trade.SetExpertMagicNumber(RuntimeMagic());trade.SetDeviationInPoints(InpDeviationPoints);trade.SetTypeFillingBySymbol(_Symbol);
   HydrateDirection();
   DrawDashboard();DrawHistoricalSignals();UpdateDashboard();
   EventSetMillisecondTimer(40);
   NasAudit_TradeWrite("ea_init","NAS_V3_LAB","","",0,0,0,0,"init",0,
      "mode="+ModeLabel(g_mode)+" rr="+RRLabel(g_rr)+" s="+IntegerToString(g_sensitivity)
      +" magic="+IntegerToString(RuntimeMagic())+" ftmo="+(InpAccountRiskEnabled?"ON":"OFF"));
   Print("NAS_V3_LAB v2.2 prod init ",_Symbol," tf=",EnumToString(_Period)," mode=",ModeLabel(g_mode)," rr=",RRLabel(g_rr),
         " hc1=",g_hcTp1," hc2=",g_hcTp2," magic=",RuntimeMagic()," ftmo=",InpAccountRiskEnabled);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){EventKillTimer();DelHist();DelDash();}

void OnTimer()
{
   EnforceRiskBreach();
   EnforceTpTouch();
   ManageHcBe();
   NasAudit_PositionProbe();
   NasAudit_HistoryScan();
   NasAudit_RiskSnapshot();
   BT_Tick();
   if(g_needsRedraw){DrawHistoricalSignals();UpdateDashboard();ChartRedraw(0);}
}

void OnTick()
{
   EnforceRiskBreach();
   EnforceTpTouch();
   ManageHcBe();
   UpdateDashboard();
   datetime cur=iTime(_Symbol,_Period,0);
   if(cur!=0&&cur!=g_lastBarTime)
   {
      g_lastBarTime=cur;
      ProcessSignalBar();
      g_needsRedraw=true;
      DrawHistoricalSignals();
      UpdateDashboard();
      ChartRedraw(0);
   }
}

void OnChartEvent(const int id,const long &lp,const double &dp,const string &sp)
{
   if(id!=CHARTEVENT_OBJECT_CLICK)return;
   bool nr=false;
   // Signal mode
   if(sp==PREFIX+"BTN_M0"){g_mode=NAS_MODE_ST_SMA13;nr=true;}
   else if(sp==PREFIX+"BTN_M1"){g_mode=NAS_MODE_ST_ONLY;nr=true;}
   else if(sp==PREFIX+"BTN_M2"){g_mode=NAS_MODE_ST_SMA8;nr=true;}
   else if(sp==PREFIX+"BTN_M3"){g_mode=NAS_MODE_ST_SMA5;nr=true;}
   else if(sp==PREFIX+"BTN_M4"){g_mode=NAS_MODE_ST_SMA21;nr=true;}
   // RR â€” auto-disable HC when changing RR
   else if(sp==PREFIX+"BTN_RR0"){g_rr=NAS_RR_1;g_hcTp1=false;g_hcTp2=false;nr=true;}
   else if(sp==PREFIX+"BTN_RR1"){g_rr=NAS_RR_2;g_hcTp2=false;nr=true;}
   else if(sp==PREFIX+"BTN_RR2"){g_rr=NAS_RR_3;nr=true;}
   // Sensitivity
   else if(sp==PREFIX+"BTN_S2"){g_sensitivity=2;nr=true;}
   else if(sp==PREFIX+"BTN_S3"){g_sensitivity=3;nr=true;}
   else if(sp==PREFIX+"BTN_S4"){g_sensitivity=4;nr=true;}
   else if(sp==PREFIX+"BTN_S5"){g_sensitivity=5;nr=true;}
   else if(sp==PREFIX+"BTN_S6"){g_sensitivity=6;nr=true;}
   // HC+BE toggles
   else if(sp==PREFIX+"BTN_HC1")
   {
      g_hcTp1=!g_hcTp1;
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);
      nr=true;
   }
   else if(sp==PREFIX+"BTN_HC2")
   {
      g_hcTp2=!g_hcTp2;
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);
      nr=true;
   }
   // EA toggle
   else if(sp==PREFIX+"BTN_EA")
   {
      g_eaEnabled=!g_eaEnabled;g_lastStatus=g_eaEnabled?"READY":"EA_OFF";
      NasAudit_TradeWrite("ea_toggle","NAS_V3_LAB","","",0,0,0,0,g_eaEnabled?"EA_ON":"EA_OFF",0,"");
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   // Close All
   else if(sp==PREFIX+"BTN_CLOSE")
   {
      CloseManaged();g_lastExecDir=0;
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   // Backtest buttons
   else if(sp==PREFIX+"BTN_BTF_SIGNAL"){g_btFillMode=BT_FILL_SIGNAL_CLOSE;nr=true;}
   else if(sp==PREFIX+"BTN_BTF_NEXT"){g_btFillMode=BT_FILL_NEXT_BAR_OPEN;nr=true;}
   else if(sp==PREFIX+"BTN_BTF_CONS"){g_btFillMode=BT_FILL_CONSERVATIVE;nr=true;}
   else if(sp==PREFIX+"BTN_BTSB_CONS"){g_btSameBarPolicy=BT_SAMEBAR_CONSERVATIVE;nr=true;}
   else if(sp==PREFIX+"BTN_BTSB_NEAR"){g_btSameBarPolicy=BT_SAMEBAR_NEAREST_OPEN;nr=true;}
   else if(sp==PREFIX+"BTN_BTSB_TP"){g_btSameBarPolicy=BT_SAMEBAR_TP_FIRST;nr=true;}
   else if(sp==PREFIX+"BTN_BTSB_SL"){g_btSameBarPolicy=BT_SAMEBAR_SL_FIRST;nr=true;}
   else if(sp==PREFIX+"BTN_BT_RUN")
   {
      if(!g_btRunning)
      {
         string wkTxt=ObjectGetString(0,PREFIX+"EDIT_BT_WEEKS",OBJPROP_TEXT);
         g_btWeeks=MathMax(1,(int)StringToInteger(wkTxt));
         g_btSpreadPts=MathMax(0,StringToDouble(ObjectGetString(0,PREFIX+"EDIT_BT_SPREAD",OBJPROP_TEXT)));
         g_btSlippagePts=MathMax(0,StringToDouble(ObjectGetString(0,PREFIX+"EDIT_BT_SLIP",OBJPROP_TEXT)));
         g_btCommissionPerLot=MathMax(0,StringToDouble(ObjectGetString(0,PREFIX+"EDIT_BT_COMM",OBJPROP_TEXT)));
         BT_Start();
      }
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sp==PREFIX+"BTN_BT_STOP")
   {
      BT_Stop();
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }

   if(nr)
   {
      ObjectSetInteger(0,sp,OBJPROP_STATE,false);
      g_needsRedraw=true;g_lastBuild=0;
      DrawHistoricalSignals();UpdateDashboard();ChartRedraw(0);
      Print("NAS_V3_LAB changed: ",ModeLabel(g_mode)," RR=",RRLabel(g_rr)," S=",g_sensitivity,
            " HC1=",g_hcTp1," HC2=",g_hcTp2);
   }
}
//+------------------------------------------------------------------+


