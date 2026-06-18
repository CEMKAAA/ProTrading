//+------------------------------------------------------------------+
//| NAS Ultimate Algo EA with SATS risk engine                       |
//| Partial TP variant: TP legs remain, no automatic SL -> BE.       |
//| Signal source: IndicatorCodeExamples/NasIndicator.pine           |
//| Risk source: SuperTrend_SATS_EA TP/SL logic                      |
//+------------------------------------------------------------------+
#property strict
#property version "1.26"

#include <Trade/Trade.mqh>
#include "NasUltimate_Core.mqh"
#include "SuperTrend_SATS_Core.mqh"

#ifndef SATS_CORE_HAS_SIGNAL_RISK_HELPER
   #error "NasUltimate_SATS_EA requires the updated SuperTrend_SATS_Core.mqh from IndicatorCodeExamples. Copy/compile the matching .mqh next to this EA."
#endif

enum NAS_SIGNAL_BAR_MODE
{
   NAS_SIGNAL_BAR_LIVE = 0,
   NAS_SIGNAL_BAR_CLOSED = 1
};

enum NAS_RISK_ENGINE
{
   NAS_RISK_SATS = 0,
   NAS_RISK_PINE = 1
};

enum NAS_EXECUTION_MODE
{
   NAS_EXEC_PARTIAL_NO_BE = 0,
   NAS_EXEC_FIXED_1_TO_3R = 1,
   NAS_EXEC_PARTIAL_BE_ORIGINAL = 2
};

input int    InpNasSensitivity = 4;
input int    InpNasRsiLength = 14;
input int    InpNasAtrRisk = 1;
input int    InpNasAtrLen = 14;
input double InpPineRiskDistanceMultiplier = 1.125;
input bool   InpUseStructuralSwingStop = true;
input int    InpSwingLookbackBars = 80;
input int    InpSwingLeftBars = 3;
input int    InpSwingRightBars = 2;
input int    InpSwingAtrPeriod = 14;
input double InpSwingMinProminenceAtr = 0.75;
input double InpSwingMinDepartureAtr = 1.00;
input double InpSwingBufferAtr = 0.20;
input bool   InpAdaptiveSlWidenEnabled = true;
input double InpSlWidenTightPct = 30.0;
input double InpSlWidenNormalPct = 25.0;
input double InpSlWidenWidePct = 20.0;
input double InpFinalRiskScalePct = 75.0; // 100=unchanged; 75 trims final SL/TP distance by 25%.
input NAS_SIGNAL_BAR_MODE InpSignalBarMode = NAS_SIGNAL_BAR_CLOSED;
input NAS_RISK_ENGINE InpRiskEngine = NAS_RISK_PINE;
input bool   InpBlockSameDirectionUntilReverse = true;
input bool   InpUseTradingTimeWindow = true;
input string InpTradeStartTime = "09:00";
input string InpTradeEndTime = "14:00";
input bool   InpSpreadGovernorEnabled = true;
input double InpSpreadGoodPoints = 0.0;    // 0 = auto by symbol
input double InpSpreadNormalPoints = 0.0;  // 0 = auto by symbol
input double InpSpreadWidePoints = 0.0;    // 0 = auto by symbol, red/blocked above this
input bool   InpEaEnabled = true;

input SATS_PRESET InpRiskPreset = SATS_PRESET_AUTO;
input SATS_SOURCE InpRiskSource = SATS_SOURCE_CLOSE;
input int    InpRiskAtrLen = 13;
input double InpRiskBaseMult = 2.0;
input bool   InpRiskUseAdaptive = true;
input int    InpRiskErLen = 20;
input double InpRiskAdaptStrength = 0.5;
input int    InpRiskAtrBaselineLen = 100;
input bool   InpRiskUseTqi = true;
input double InpRiskQualityStrength = 0.4;
input double InpRiskQualityCurve = 1.5;
input bool   InpRiskSmoothMult = true;
input bool   InpRiskUseAsymBands = true;
input double InpRiskAsymStrength = 0.5;
input bool   InpRiskUseEffAtr = true;
input bool   InpRiskUseCharFlip = true;
input int    InpRiskCharFlipMinAge = 5;
input double InpRiskCharFlipHigh = 0.55;
input double InpRiskCharFlipLow = 0.25;
input double InpRiskTqiWeightEr = 0.35;
input double InpRiskTqiWeightVol = 0.20;
input double InpRiskTqiWeightStruct = 0.25;
input double InpRiskTqiWeightMom = 0.20;
input int    InpRiskTqiStructLen = 20;
input int    InpRiskTqiMomLen = 10;
input int    InpRiskPivotLen = 3;
input int    InpRiskRsiLen = 14;
input int    InpRiskVolLen = 20;
input double InpRiskSlAtrMult = 1.5;
input double InpTp1R = 1.0;
input double InpTp2R = 2.0;
input double InpTp3R = 3.0;

input double InpTotalLot = 0.03;
input NAS_EXECUTION_MODE InpExecutionMode = NAS_EXEC_PARTIAL_NO_BE;
input double InpFixedLot = 0.03;
input double InpFixedRR = 3.0;
input bool   InpAdvancedLotEngineEnabled = true;
input int    InpAdvancedLotDailyAtrPeriod = 14;
input bool   InpAdvancedAccountRiskEnabled = true;
input double InpAccountRiskPerTradePct = 1.00;
input double InpAccountRiskDailyAtrExposurePct = 2.00;
input double InpAccountRiskMaxPortfolioPct = 4.00;
input double InpAccountRiskDailyLossLimitPct = 0.00;
input double InpAccountRiskMaxDrawdownPct = 0.00;
input double InpAccountRiskMaxMarginUsagePct = 40.00;
input double InpAccountRiskInitialBalanceOverride = 0.00;
input int    InpAccountRiskDayResetHourGmt = 0;
input bool   InpAccountRiskLiquidateOnBreach = true;
input double InpAccountRiskSafetyBufferPct = 95.00;
input double InpAdvancedLotMax = 0.00; // 0=broker maximum only.
input bool   InpAccountRiskBlockUnprotectedPositions = true;
input bool   InpAccountRiskFailClosed = true;
input bool   InpAccountRiskAuditEnabled = true;
input int    InpAccountRiskAuditIntervalSeconds = 60;
input int    InpDeviationPoints = 30;
input bool   InpEnforceTpTouchClose = true; // Safety watchdog: close managed positions if live price touches broker TP.
input double InpTpTouchCloseTolerancePoints = 2.0;
input int    InpTpTouchWatchdogTimerMs = 100;
input int    InpTpTouchCloseRetryCount = 2;
input long   InpMagic = 27052712;
input int    InpHistoryBars = 60000;
input int    InpSignalCalcBars = 5000;
input bool   InpCloseExistingOnNewSignal = true;
input bool   InpDrawTradeLevels = true;
input bool   InpDrawExecutionArrows = true;
input bool   InpTradeLatestSignalOnAttach = false;
input bool   InpDrawLastSignalsOnStart = true;
input int    InpStartupSignalCount = 3;
input bool   InpReconcileLiveSignalsOnBarClose = true;
input bool   InpCloseVanishedLiveSignalPosition = true;
input bool   InpSignalParityAudit = true;
input bool   InpAuditNoSignalEvaluations = false;
input bool   InpShowDashboard = true;

CTrade trade;
long     g_runtimeMagic = 0;
datetime g_lastBarTime = 0;
datetime g_lastSignalTime = 0;
int      g_lastSignalKeyDirection = 0;
datetime g_processedBuySignalBarTime = 0;
datetime g_processedSellSignalBarTime = 0;
int      g_lastExecutedDirection = 0;
datetime g_liveSignalBarTime = 0;
int      g_liveSignalDirection = 0;
datetime g_lastNoSignalAuditBarTime = 0;
int      g_lastDirection = 0;
double   g_lastEntry = 0.0;
double   g_lastSl = 0.0;
double   g_lastTp1 = 0.0;
double   g_lastTp2 = 0.0;
double   g_lastTp3 = 0.0;
bool     g_beMoved = false;
double   g_equityPeak = 0.0;
double   g_maxDd = 0.0;
string   g_historySummary[3];
string   g_tradeStartTimeRuntime = "";
string   g_tradeEndTimeRuntime = "";
double   g_totalLotRuntime = 0.0;
double   g_fixedLotRuntime = 0.0;
bool     g_eaEnabledRuntime = true;
string   g_lastExecutionStatus = "READY";
string   g_lastExecutionBlockReason = "";
double   g_lastSpreadPoints = 0.0;
string   g_lastSpreadStatus = "UNKNOWN";
double   g_spreadMaxPointsRuntime = 0.0;
uint     g_lastTpTouchWatchdogMs = 0;
bool     g_lastRiskUsedStructuralStop = false;
double   g_lastRiskBaseSl = 0.0;
double   g_lastRiskSwingPrice = 0.0;
double   g_lastRiskSwingAtr = 0.0;
double   g_lastRiskSwingProminence = 0.0;
int      g_lastRiskSwingAgeBars = -1;
double   g_lastRiskPreWidenSl = 0.0;
double   g_lastRiskWidenPct = 0.0;
double   g_lastRiskFinalScalePct = 100.0;
double   g_finalRiskScalePctRuntime = 100.0;
double   g_lastAdvancedLot = 0.0;
string   g_lastAdvancedLotDetail = "";
uint     g_lastAccountRiskGuardMs = 0;
double   g_accountRiskLockValue = 0.0;

string PREFIX = "NAS_SATS_NO_BE_EA_";
uint     g_dashboardDoorStartMs = 0;
bool     g_dashboardDoorFinished = false;
bool     g_dashboardCollapsed = false;
bool     g_dashboardOpening = false;
uint     g_visualMetricsCacheMs = 0;

struct NasVisualMetrics
{
   bool ok;
   double price;
   double superTrend;
   double sma13;
   double buyPct;
   double sellPct;
   bool buyArmed;
   bool sellArmed;
   string status;
};

NasVisualMetrics g_visualMetricsCache;

long RuntimeMagic()
{
   if(g_runtimeMagic != 0)
      return g_runtimeMagic;
   ulong chartId = ChartID();
   long chartPart = (long)(chartId % 1000000);
   if(InpAdvancedAccountRiskEnabled)
   {
      long safeInput = InpMagic % 1000000000000;
      if(safeInput < 0)
         safeInput = -safeInput;
      long safeBase = safeInput * 1000000 + chartPart;
      g_runtimeMagic = 4000000000000000000 + safeBase;
   }
   else
      g_runtimeMagic = InpMagic * 1000000 + chartPart;
   return g_runtimeMagic;
}

long NormalRuntimeMagic()
{
   long chartPart = (long)(ChartID() % 1000000);
   return InpMagic * 1000000 + chartPart;
}

long FtmoRuntimeMagic()
{
   long chartPart = (long)(ChartID() % 1000000);
   long safeInput = InpMagic % 1000000000000;
   if(safeInput < 0)
      safeInput = -safeInput;
   return 4000000000000000000 + safeInput * 1000000 + chartPart;
}

bool RuntimeMagicOwned(const long magic)
{
   return magic == NormalRuntimeMagic() || magic == FtmoRuntimeMagic();
}

int SignalBarsToCopy()
{
   return MathMax(InpSignalCalcBars, 300);
}

int LoadNasRates(MqlRates &rates[], const int barsToCopy, const bool applyLiveTick)
{
   int copied = CopyRates(_Symbol, _Period, 0, barsToCopy, rates);
   if(copied <= 0)
      return copied;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   if(applyLiveTick && copied > 0)
   {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
      {
         double liveClose = tick.bid > 0.0 ? tick.bid : (tick.last > 0.0 ? tick.last : rates[copied - 1].close);
         if(liveClose > 0.0)
         {
            int i = copied - 1;
            rates[i].close = liveClose;
            rates[i].high = MathMax(rates[i].high, liveClose);
            rates[i].low = MathMin(rates[i].low, liveClose);
         }
      }
   }
   return copied;
}

bool WasDirectionProcessedOnBar(const datetime signalTime, const int direction)
{
   if(direction > 0)
      return g_processedBuySignalBarTime == signalTime;
   if(direction < 0)
      return g_processedSellSignalBarTime == signalTime;
   return false;
}

void MarkDirectionProcessedOnBar(const datetime signalTime, const int direction)
{
   if(direction > 0)
      g_processedBuySignalBarTime = signalTime;
   else if(direction < 0)
      g_processedSellSignalBarTime = signalTime;
}

void ClearLiveSignalObjects(const datetime signalTime, const int direction)
{
   if(signalTime <= 0 || direction == 0)
      return;
   string side = direction > 0 ? "BUY" : "SELL";
   string stamp = IntegerToString((int)signalTime) + "_" + side;
   ObjectDelete(0, PREFIX + "LIVE_EXEC_" + stamp + "_ARW");
   ObjectDelete(0, PREFIX + "LIVE_EXEC_" + stamp + "_TXT");
}

void ClearTradeLevelObjects()
{
   ObjectDelete(0, PREFIX + "ENTRY");
   ObjectDelete(0, PREFIX + "SL");
   ObjectDelete(0, PREFIX + "TP1");
   ObjectDelete(0, PREFIX + "TP2");
   ObjectDelete(0, PREFIX + "TP3");
   ObjectDelete(0, PREFIX + "ENTRY_TXT");
   ObjectDelete(0, PREFIX + "SL_TXT");
   ObjectDelete(0, PREFIX + "TP1_TXT");
   ObjectDelete(0, PREFIX + "TP2_TXT");
   ObjectDelete(0, PREFIX + "TP3_TXT");
}

void HydrateExecutedDirectionFromOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!RuntimeMagicOwned((long)PositionGetInteger(POSITION_MAGIC)))
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      g_lastExecutedDirection = type == POSITION_TYPE_BUY ? 1 : -1;
      Print("NAS SATS EA hydrated last executed direction from open position dir=",
            (g_lastExecutedDirection > 0 ? "BUY" : "SELL"),
            " ticket=", ticket);
      return;
   }
}

int ParseClockMinutes(const string value, const int fallbackMinutes)
{
   int colon = StringFind(value, ":");
   if(colon <= 0)
      return fallbackMinutes;
   int hour = (int)StringToInteger(StringSubstr(value, 0, colon));
   int minute = (int)StringToInteger(StringSubstr(value, colon + 1));
   if(hour == 24 && minute == 0)
      return 24 * 60;
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return fallbackMinutes;
   return hour * 60 + minute;
}

int ServerClockMinutes()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour * 60 + dt.min;
}

bool IsTradingTimeOpen()
{
   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   int startMin = ParseClockMinutes(startText, 0);
   int endMin = ParseClockMinutes(endText, 1439);
   if(startMin == endMin)
      return true;
   int nowMin = ServerClockMinutes();
   if(startMin < endMin)
      return nowMin >= startMin && nowMin <= endMin;
   return nowMin >= startMin || nowMin <= endMin;
}

string TradingTimeStateText()
{
   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   return string(IsTradingTimeOpen() ? "OPEN " : "CLOSED ")
          + startText + "-" + endText
          + " server=" + TimeToString(TimeCurrent(), TIME_MINUTES);
}

void AutoSpreadThresholds(double &goodPts, double &normalPts, double &widePts)
{
   string sym = _Symbol;
   StringToUpper(sym);

   goodPts = 100.0;
   normalPts = 300.0;
   widePts = 800.0;

   if(StringFind(sym, "USTEC") >= 0 || StringFind(sym, "NAS") >= 0 || StringFind(sym, "US100") >= 0 || StringFind(sym, "NDX") >= 0)
   {
      goodPts = 180.0;
      normalPts = 350.0;
      widePts = 800.0;
   }
   else if(StringFind(sym, "DE30") >= 0 || StringFind(sym, "GER40") >= 0 || StringFind(sym, "DAX") >= 0)
   {
      goodPts = 35.0;
      normalPts = 80.0;
      widePts = 200.0;
   }
   else if(StringFind(sym, "UK100") >= 0 || StringFind(sym, "FTSE") >= 0)
   {
      goodPts = 120.0;
      normalPts = 250.0;
      widePts = 500.0;
   }
   else if(StringFind(sym, "FR40") >= 0 || StringFind(sym, "CAC") >= 0)
   {
      goodPts = 180.0;
      normalPts = 450.0;
      widePts = 1000.0;
   }
   else if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      goodPts = 180.0;
      normalPts = 350.0;
      widePts = 800.0;
   }
   else if(StringFind(sym, "EUR") >= 0 || StringFind(sym, "GBP") >= 0 || StringFind(sym, "USD") >= 0 || StringFind(sym, "JPY") >= 0)
   {
      goodPts = 20.0;
      normalPts = 50.0;
      widePts = 120.0;
   }

   if(InpSpreadGoodPoints > 0.0)
      goodPts = InpSpreadGoodPoints;
   if(InpSpreadNormalPoints > 0.0)
      normalPts = InpSpreadNormalPoints;
   if(InpSpreadWidePoints > 0.0)
      widePts = InpSpreadWidePoints;

   if(g_spreadMaxPointsRuntime > 0.0)
      widePts = g_spreadMaxPointsRuntime;

   normalPts = MathMax(normalPts, goodPts);
   if(g_spreadMaxPointsRuntime > 0.0)
   {
      normalPts = MathMin(normalPts, widePts);
      goodPts = MathMin(goodPts, normalPts);
   }
   else
   {
      widePts = MathMax(widePts, normalPts);
   }
}

bool SpreadSnapshot(double &bid,
                    double &ask,
                    double &spreadPts,
                    string &status,
                    color &statusColor,
                    double &goodPts,
                    double &normalPts,
                    double &widePts)
{
   AutoSpreadThresholds(goodPts, normalPts, widePts);

   MqlTick tick;
   bool hasTick = SymbolInfoTick(_Symbol, tick);
   bid = hasTick && tick.bid > 0.0 ? tick.bid : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ask = hasTick && tick.ask > 0.0 ? tick.ask : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(bid <= 0.0 || ask <= 0.0 || point <= 0.0)
   {
      spreadPts = 0.0;
      status = "BLOCKED";
      statusColor = C'221,55,78';
      return false;
   }

   spreadPts = MathMax(0.0, (ask - bid) / point);
   if(spreadPts <= goodPts)
   {
      status = "GOOD";
      statusColor = C'80,255,180';
      return true;
   }
   if(spreadPts <= normalPts)
   {
      status = "NORMAL";
      statusColor = C'90,178,255';
      return true;
   }
   if(spreadPts <= widePts)
   {
      status = "WIDE";
      statusColor = C'255,204,82';
      return true;
   }

   if(g_spreadMaxPointsRuntime <= 0.0)
   {
      status = "NO-BLOCK";
      statusColor = C'255,204,82';
      return true;
   }

   status = "BLOCKED";
   statusColor = C'221,55,78';
   return false;
}

bool IsSpreadExecutionAllowed(string &reason)
{
   double bid, ask, spreadPts, goodPts, normalPts, widePts;
   string status;
   color statusColor;
   bool allowed = SpreadSnapshot(bid, ask, spreadPts, status, statusColor, goodPts, normalPts, widePts);
   g_lastSpreadPoints = spreadPts;
   g_lastSpreadStatus = status;

   if(!InpSpreadGovernorEnabled)
   {
      reason = "spread_governor_disabled";
      return true;
   }

   if(allowed)
   {
      reason = status + "_SPREAD";
      return true;
   }

   reason = "spread_blocked status=" + status
            + " spread_pts=" + DoubleToString(spreadPts, 0)
            + " good=" + DoubleToString(goodPts, 0)
            + " normal=" + DoubleToString(normalPts, 0)
            + " wide=" + DoubleToString(widePts, 0);
   return false;
}

NasSettings BuildNasSettings()
{
   NasSettings s;
   s.sensitivity = InpNasSensitivity;
   s.rsiLength = InpNasRsiLength;
   s.atrRisk = InpNasAtrRisk;
   s.atrLen = InpNasAtrLen;
   return s;
}

SATSSettings BuildRiskSettings()
{
   SATSSettings s;
   s.preset = InpRiskPreset;
   s.source = InpRiskSource;
   s.atrLen = InpRiskAtrLen;
   s.baseMult = InpRiskBaseMult;
   s.useAdaptive = InpRiskUseAdaptive;
   s.erLen = InpRiskErLen;
   s.adaptStrength = InpRiskAdaptStrength;
   s.atrBaselineLen = InpRiskAtrBaselineLen;
   s.useTqi = InpRiskUseTqi;
   s.qualityStrength = InpRiskQualityStrength;
   s.qualityCurve = InpRiskQualityCurve;
   s.smoothMult = InpRiskSmoothMult;
   s.useAsymBands = InpRiskUseAsymBands;
   s.asymStrength = InpRiskAsymStrength;
   s.useEffAtr = InpRiskUseEffAtr;
   s.useCharFlip = InpRiskUseCharFlip;
   s.charFlipMinAge = InpRiskCharFlipMinAge;
   s.charFlipHigh = InpRiskCharFlipHigh;
   s.charFlipLow = InpRiskCharFlipLow;
   s.tqiWeightEr = InpRiskTqiWeightEr;
   s.tqiWeightVol = InpRiskTqiWeightVol;
   s.tqiWeightStruct = InpRiskTqiWeightStruct;
   s.tqiWeightMom = InpRiskTqiWeightMom;
   s.tqiStructLen = InpRiskTqiStructLen;
   s.tqiMomLen = InpRiskTqiMomLen;
   s.pivotLen = InpRiskPivotLen;
   s.rsiLen = InpRiskRsiLen;
   s.volLen = InpRiskVolLen;
   s.slAtrMult = InpRiskSlAtrMult;
   s.tp1R = InpTp1R;
   s.tp2R = InpTp2R;
   s.tp3R = InpTp3R;
   s.tradeMaxAge = 100;
   s.useAutoCalib = false;
   s.calibWindow = 20;
   s.calibBadR = 0.0;
   s.calibGoodR = 0.7;
   s.calibStepQ = 0.05;
   s.calibCooldown = 5;
   s.calibMinQ = 0.1;
   s.calibMaxQ = 0.9;
   return s;
}

int OnInit()
{
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(InpExecutionMode != NAS_EXEC_FIXED_1_TO_3R && marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("NAS SATS initialization blocked: partial three-leg execution requires a hedging account. margin_mode=",
            EnumToString(marginMode));
      return INIT_PARAMETERS_INCORRECT;
   }
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_tradeStartTimeRuntime = InpTradeStartTime;
   g_tradeEndTimeRuntime = InpTradeEndTime;
   g_totalLotRuntime = InpTotalLot;
   g_fixedLotRuntime = InpFixedLot;
   g_spreadMaxPointsRuntime = MathMax(0.0, InpSpreadWidePoints);
   g_eaEnabledRuntime = InpEaEnabled;
   g_finalRiskScalePctRuntime = MathMax(10.0, MathMin(200.0, InpFinalRiskScalePct));
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   HydrateExecutedDirectionFromOpenPosition();
   PrintStartupDiagnostics();
   BaselineStartupSignal();
   DrawDashboard();
   EventSetMillisecondTimer(40);
   if(InpDrawLastSignalsOnStart)
   {
      DrawRecentSignalHistory();
      UpdateDashboard();
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PREFIX);
}

void OnTimer()
{
   EnforceAccountRiskBreach();
   WriteAccountRiskAudit("snapshot", "periodic_health", true);
   EnforceManagedTpTouchClose(false);
   if(!g_dashboardDoorFinished)
      UpdateDashboard();
}

void OnTick()
{
   EnforceAccountRiskBreach();
   ManageOpenPositions();
   UpdateDashboard();

   if(InpSignalBarMode == NAS_SIGNAL_BAR_LIVE)
   {
      datetime curBar = iTime(_Symbol, _Period, 0);
      if(curBar != 0 && curBar != g_lastBarTime)
      {
         if(g_lastBarTime != 0)
            ReconcileLiveSignalAfterBarClose();
         g_lastBarTime = curBar;
      }
      ProcessSignalBar();
      return;
   }

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == 0 || curBar == g_lastBarTime)
      return;
   g_lastBarTime = curBar;
   ProcessSignalBar();
}

void PrintStartupDiagnostics()
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double leg = LegVolume();

   Print("NAS SATS Partial-NoBE EA initialized symbol=", _Symbol,
         " timeframe=", EnumToString(_Period),
         " runtime_magic=", RuntimeMagic(),
         " chart_id=", (long)ChartID(),
         " execution_mode=", EnumToString(InpExecutionMode),
         " signal_bar_mode=", EnumToString(InpSignalBarMode),
         " ea_enabled=", InpEaEnabled);
   Print("NAS SATS config risk_engine=", EnumToString(InpRiskEngine),
         " risk_preset=", EnumToString(InpRiskPreset),
         " risk_source=", EnumToString(InpRiskSource),
         " history_bars=", InpHistoryBars,
         " signal_calc_bars=", SignalBarsToCopy(),
         " total_lot=", DoubleToString(InpTotalLot, 8),
         " fixed_lot=", DoubleToString(InpFixedLot, 8),
         " fixed_rr=", DoubleToString(InpFixedRR, 2),
         " same_direction_hard_safety=true");
   Print("NAS SATS structural_stop enabled=", InpUseStructuralSwingStop,
         " lookback=", InpSwingLookbackBars,
         " left=", InpSwingLeftBars,
         " right=", InpSwingRightBars,
         " atr_period=", InpSwingAtrPeriod,
         " min_prominence_atr=", DoubleToString(InpSwingMinProminenceAtr, 2),
         " min_departure_atr=", DoubleToString(InpSwingMinDepartureAtr, 2),
         " buffer_atr=", DoubleToString(InpSwingBufferAtr, 2),
         " adaptive_widen=", InpAdaptiveSlWidenEnabled,
         " widen_tight_pct=", DoubleToString(InpSlWidenTightPct, 1),
         " widen_normal_pct=", DoubleToString(InpSlWidenNormalPct, 1),
         " widen_wide_pct=", DoubleToString(InpSlWidenWidePct, 1),
         " final_scale_pct=", DoubleToString(InpFinalRiskScalePct, 1));
   Print("NAS SATS execution spread_governor_enabled=", InpSpreadGovernorEnabled,
         " spread_good_pts=", DoubleToString(InpSpreadGoodPoints, 1),
         " spread_normal_pts=", DoubleToString(InpSpreadNormalPoints, 1),
         " spread_wide_pts=", DoubleToString(InpSpreadWidePoints, 1),
         " enforce_tp_touch_close=", InpEnforceTpTouchClose,
         " tp_touch_tolerance_points=", DoubleToString(InpTpTouchCloseTolerancePoints, 1),
         " tp_touch_timer_ms=", InpTpTouchWatchdogTimerMs,
         " tp_touch_retries=", InpTpTouchCloseRetryCount,
         " leg_lot=", DoubleToString(leg, 8),
         " volume_min=", DoubleToString(minLot, 8),
         " volume_max=", DoubleToString(maxLot, 8),
         " volume_step=", DoubleToString(step, 8));
   Print("NAS SATS account risk enabled=", InpAdvancedAccountRiskEnabled,
         " advanced_lot=", InpAdvancedLotEngineEnabled,
         " scoped_magic=", RuntimeMagic(),
         " risk_per_trade_pct=", DoubleToString(InpAccountRiskPerTradePct, 3),
         " atr_exposure_pct=", DoubleToString(InpAccountRiskDailyAtrExposurePct, 3),
         " max_portfolio_pct=", DoubleToString(InpAccountRiskMaxPortfolioPct, 3),
         " daily_loss_limit_pct=", DoubleToString(InpAccountRiskDailyLossLimitPct, 3),
         " max_drawdown_pct=", DoubleToString(InpAccountRiskMaxDrawdownPct, 3),
         " max_margin_usage_pct=", DoubleToString(InpAccountRiskMaxMarginUsagePct, 3),
         " day_reset_hour_gmt=", MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt)),
         " d1_atr_period=", InpAdvancedLotDailyAtrPeriod,
         " max_lot=", DoubleToString(InpAdvancedLotMax, 2));

   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), InpSignalBarMode == NAS_SIGNAL_BAR_LIVE);
   if(copied < 200)
   {
      Print("NAS SATS EA startup probe skipped: insufficient bars copied=", copied);
      return;
   }

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   int scanFrom = LastSignalScanIndex(copied);
   for(int i = scanFrom; i >= 0; i--)
   {
      if(!p[i].buy && !p[i].sell)
         continue;
      int dir = p[i].buy ? 1 : -1;
      double atr = 0.0;
      if(CalculateRisk(rates, copied, i, dir, p[i], g_lastEntry, g_lastSl, g_lastTp1, g_lastTp2, g_lastTp3, atr))
      {
         Print("NAS SATS EA startup last_signal dir=", (dir > 0 ? "BUY" : "SELL"),
               " copied_bars=", copied,
               " mode=", EnumToString(InpSignalBarMode),
               " risk_engine=", EnumToString(InpRiskEngine),
               " label=", NasSignalText(p[i]),
               " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
               " nas_st=", DoubleToString(p[i].superTrend, _Digits),
               " entry=", DoubleToString(g_lastEntry, _Digits),
               " sl=", DoubleToString(g_lastSl, _Digits),
               " tp1=", DoubleToString(g_lastTp1, _Digits),
               " tp2=", DoubleToString(g_lastTp2, _Digits),
               " tp3=", DoubleToString(g_lastTp3, _Digits));
      }
      return;
   }
   Print("NAS SATS EA startup last_signal: none within copied bars=", copied);
}

void BaselineStartupSignal()
{
   if(InpTradeLatestSignalOnAttach)
   {
      Print("NAS SATS EA startup baseline disabled by input; latest closed signal may execute on attach.");
      return;
   }

   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), InpSignalBarMode == NAS_SIGNAL_BAR_LIVE);
   if(copied < 200)
      return;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   int scanFrom = LastSignalScanIndex(copied);
   for(int i = scanFrom; i >= 0; i--)
   {
      if(p[i].buy || p[i].sell)
      {
         g_lastSignalTime = rates[i].time;
         g_lastSignalKeyDirection = p[i].buy ? 1 : -1;
         if(g_lastExecutedDirection == 0)
            g_lastExecutedDirection = g_lastSignalKeyDirection;
         Print("NAS SATS EA startup baseline registered dir=", (p[i].buy ? "BUY" : "SELL"),
               " copied_bars=", copied,
               " mode=", EnumToString(InpSignalBarMode),
               " label=", NasSignalText(p[i]),
               " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
               " no historical execution emitted.");
         return;
      }
   }
}

int LastSignalScanIndex(const int copied)
{
   if(copied <= 0)
      return -1;
   if(InpSignalBarMode == NAS_SIGNAL_BAR_LIVE)
      return copied - 1;
   return copied - 2;
}

string NasSignalText(const NasPoint &p)
{
   if(p.buy)
      return p.sma8 >= p.sma9 ? "Buy" : "Strong Buy";
   if(p.sell)
      return p.sma8 <= p.sma9 ? "Sell" : "Strong Sell";
   return "-";
}

void PrintSignalParityAudit(const MqlRates &rates[],
                            const NasPoint &p[],
                            const int i,
                            const string stage)
{
   if(!InpSignalParityAudit || i < 1)
      return;
   double prevClose = rates[i - 1].close;
   double prevSt = p[i - 1].superTrend;
   bool crossUp = NAS_Crossover(rates[i].close, p[i].superTrend, prevClose, prevSt);
   bool crossDown = NAS_Crossunder(rates[i].close, p[i].superTrend, prevClose, prevSt);
   Print("NAS_SIGNAL_AUDIT stage=", stage,
         " mode=", EnumToString(InpSignalBarMode),
         " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
         " close=", DoubleToString(rates[i].close, _Digits),
         " prev_close=", DoubleToString(prevClose, _Digits),
         " st=", DoubleToString(p[i].superTrend, _Digits),
         " prev_st=", DoubleToString(prevSt, _Digits),
         " sma13=", DoubleToString(p[i].sma13, _Digits),
         " cross_up=", (crossUp ? "true" : "false"),
         " cross_down=", (crossDown ? "true" : "false"),
         " buy=", (p[i].buy ? "true" : "false"),
         " sell=", (p[i].sell ? "true" : "false"),
         " label=", NasSignalText(p[i]));
}

double SwingAtrAt(const MqlRates &rates[], const int index, const int period)
{
   int len = MathMax(2, period);
   int first = MathMax(0, index - len + 1);
   int count = index - first + 1;
   if(count < 2)
      return 0.0;
   double sum = 0.0;
   for(int i = first; i <= index; i++)
      sum += NAS_TrueRange(rates, i);
   return sum / (double)count;
}

bool FindStructuralSwingStop(const MqlRates &rates[],
                             const int copied,
                             const int signalIndex,
                             const int direction,
                             const double entry,
                             double &swingPrice,
                             double &structuralSl,
                             double &swingAtr,
                             double &prominenceAtr,
                             int &ageBars)
{
   swingPrice = 0.0;
   structuralSl = 0.0;
   swingAtr = 0.0;
   prominenceAtr = 0.0;
   ageBars = -1;
   if(!InpUseStructuralSwingStop || copied <= 0 || signalIndex < 2 || direction == 0)
      return false;

   int left = MathMax(2, InpSwingLeftBars);
   int right = MathMax(1, InpSwingRightBars);
   int newestCandidate = signalIndex - right;
   int oldestCandidate = MathMax(left, signalIndex - MathMax(left + right + 1, InpSwingLookbackBars));
   if(newestCandidate < oldestCandidate)
      return false;

   double minProminence = MathMax(0.0, InpSwingMinProminenceAtr);
   double minDeparture = MathMax(0.0, InpSwingMinDepartureAtr);
   for(int candidate = newestCandidate; candidate >= oldestCandidate; candidate--)
   {
      if(candidate - left < 0 || candidate + right > signalIndex)
         continue;
      double atr = SwingAtrAt(rates, candidate, InpSwingAtrPeriod);
      if(atr <= 0.0)
         continue;

      bool pivot = true;
      bool strictLeft = false;
      bool strictRight = false;
      double leftExtreme = direction > 0 ? -DBL_MAX : DBL_MAX;
      double rightExtreme = direction > 0 ? -DBL_MAX : DBL_MAX;
      double pivotPrice = direction > 0 ? rates[candidate].low : rates[candidate].high;

      for(int k = candidate - left; k < candidate; k++)
      {
         if(direction > 0)
         {
            if(rates[k].low < pivotPrice)
               pivot = false;
            if(rates[k].low > pivotPrice)
               strictLeft = true;
            leftExtreme = MathMax(leftExtreme, rates[k].high);
         }
         else
         {
            if(rates[k].high > pivotPrice)
               pivot = false;
            if(rates[k].high < pivotPrice)
               strictLeft = true;
            leftExtreme = MathMin(leftExtreme, rates[k].low);
         }
      }
      for(int k = candidate + 1; k <= candidate + right; k++)
      {
         if(direction > 0)
         {
            if(rates[k].low < pivotPrice)
               pivot = false;
            if(rates[k].low > pivotPrice)
               strictRight = true;
            rightExtreme = MathMax(rightExtreme, rates[k].high);
         }
         else
         {
            if(rates[k].high > pivotPrice)
               pivot = false;
            if(rates[k].high < pivotPrice)
               strictRight = true;
            rightExtreme = MathMin(rightExtreme, rates[k].low);
         }
      }
      if(!pivot || !strictLeft || !strictRight)
         continue;

      double leftProminence = direction > 0 ? leftExtreme - pivotPrice : pivotPrice - leftExtreme;
      double rightProminence = direction > 0 ? rightExtreme - pivotPrice : pivotPrice - rightExtreme;
      double prominence = MathMin(leftProminence, rightProminence) / atr;
      if(prominence < minProminence)
         continue;

      double postExtreme = direction > 0 ? -DBL_MAX : DBL_MAX;
      for(int k = candidate + 1; k <= signalIndex; k++)
      {
         if(direction > 0)
            postExtreme = MathMax(postExtreme, rates[k].high);
         else
            postExtreme = MathMin(postExtreme, rates[k].low);
      }
      double departure = direction > 0 ? postExtreme - pivotPrice : pivotPrice - postExtreme;
      double closeDeparture = direction > 0 ? rates[signalIndex].close - pivotPrice : pivotPrice - rates[signalIndex].close;
      if(departure < atr * minDeparture || closeDeparture < atr * minDeparture * 0.5)
         continue;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double buffer = MathMax(point * 5.0, atr * MathMax(0.0, InpSwingBufferAtr));
      double candidateSl = direction > 0 ? pivotPrice - buffer : pivotPrice + buffer;
      if((direction > 0 && (candidateSl >= entry || pivotPrice >= entry))
         || (direction < 0 && (candidateSl <= entry || pivotPrice <= entry)))
         continue;

      swingPrice = pivotPrice;
      structuralSl = candidateSl;
      swingAtr = atr;
      prominenceAtr = prominence;
      ageBars = signalIndex - candidate;
      return true;
   }
   return false;
}

bool ApplyStructuralSwingStop(const MqlRates &rates[],
                              const int copied,
                              const int signalIndex,
                              const int direction,
                              const double entry,
                              double &sl,
                              double &tp1,
                              double &tp2,
                              double &tp3)
{
   g_lastRiskUsedStructuralStop = false;
   g_lastRiskBaseSl = sl;
   g_lastRiskSwingPrice = 0.0;
   g_lastRiskSwingAtr = 0.0;
   g_lastRiskSwingProminence = 0.0;
   g_lastRiskSwingAgeBars = -1;
   if(!InpUseStructuralSwingStop)
      return false;

   double baseRisk = MathAbs(entry - sl);
   if(baseRisk <= 0.0)
      return false;
   double r1 = MathAbs(tp1 - entry) / baseRisk;
   double r2 = MathAbs(tp2 - entry) / baseRisk;
   double r3 = MathAbs(tp3 - entry) / baseRisk;

   double swingPrice, structuralSl, swingAtr, prominenceAtr;
   int ageBars;
   if(!FindStructuralSwingStop(rates, copied, signalIndex, direction, entry,
                               swingPrice, structuralSl, swingAtr, prominenceAtr, ageBars))
      return false;
   double structuralRisk = MathAbs(entry - structuralSl);
   g_lastRiskSwingPrice = swingPrice;
   g_lastRiskSwingAtr = swingAtr;
   g_lastRiskSwingProminence = prominenceAtr;
   g_lastRiskSwingAgeBars = ageBars;
   if(structuralRisk <= baseRisk + SymbolInfoDouble(_Symbol, SYMBOL_POINT))
      return false;

   sl = structuralSl;
   tp1 = direction > 0 ? entry + structuralRisk * r1 : entry - structuralRisk * r1;
   tp2 = direction > 0 ? entry + structuralRisk * r2 : entry - structuralRisk * r2;
   tp3 = direction > 0 ? entry + structuralRisk * r3 : entry - structuralRisk * r3;
   g_lastRiskUsedStructuralStop = true;
   return true;
}

bool ApplyAdaptiveSlWiden(const int direction,
                          const double entry,
                          double &sl,
                          double &tp1,
                          double &tp2,
                          double &tp3)
{
   g_lastRiskPreWidenSl = sl;
   g_lastRiskWidenPct = 0.0;
   if(!InpAdaptiveSlWidenEnabled || direction == 0)
      return false;
   double rawRisk = MathAbs(entry - sl);
   double farTpDistance = MathMax(MathAbs(tp1 - entry), MathMax(MathAbs(tp2 - entry), MathAbs(tp3 - entry)));
   if(rawRisk <= 0.0 || farTpDistance <= 0.0)
      return false;

   double ratio = rawRisk / farTpDistance;
   double pct = ratio <= 0.20 ? InpSlWidenTightPct : (ratio <= 0.50 ? InpSlWidenNormalPct : InpSlWidenWidePct);
   pct = MathMax(0.0, MathMin(200.0, pct)) / 100.0;
   if(pct <= 0.0)
      return false;
   double widenedRisk = MathMin(farTpDistance, rawRisk * (1.0 + pct));
   if(widenedRisk <= rawRisk)
      return false;

   sl = direction > 0 ? entry - widenedRisk : entry + widenedRisk;
   g_lastRiskWidenPct = pct * 100.0;
   return true;
}

bool ApplyFinalRiskScale(const int direction,
                         const double entry,
                         double &sl,
                         double &tp1,
                         double &tp2,
                         double &tp3)
{
   g_lastRiskFinalScalePct = 100.0;
   if(direction == 0 || entry <= 0.0)
      return false;

   double pct = MathMax(10.0, MathMin(200.0, g_finalRiskScalePctRuntime));
   g_lastRiskFinalScalePct = pct;
   if(MathAbs(pct - 100.0) < 0.0001)
      return false;

   double rawRisk = MathAbs(entry - sl);
   if(rawRisk <= 0.0)
      return false;

   double r1 = MathAbs(tp1 - entry) / rawRisk;
   double r2 = MathAbs(tp2 - entry) / rawRisk;
   double r3 = MathAbs(tp3 - entry) / rawRisk;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = MathMax(point * 20.0, (double)stopLevelPoints * point * 1.5);
   double targetRisk = MathMax(minStop, rawRisk * pct / 100.0);
   if(MathAbs(targetRisk - rawRisk) <= point * 0.5)
      return false;

   sl = direction > 0 ? entry - targetRisk : entry + targetRisk;
   tp1 = direction > 0 ? entry + targetRisk * r1 : entry - targetRisk * r1;
   tp2 = direction > 0 ? entry + targetRisk * r2 : entry - targetRisk * r2;
   tp3 = direction > 0 ? entry + targetRisk * r3 : entry - targetRisk * r3;
   return true;
}

bool CalculateRisk(const MqlRates &rates[],
                   const int copied,
                   const int signalIndex,
                   const int direction,
                   const NasPoint &signalPoint,
                   double &entry,
                   double &sl,
                   double &tp1,
                   double &tp2,
                   double &tp3,
                   double &effAtr)
{
   if(InpRiskEngine == NAS_RISK_PINE)
   {
      entry = signalPoint.nasEntry;
      sl = signalPoint.nasSl;
      tp1 = signalPoint.nasTp1;
      tp2 = signalPoint.nasTp2;
      tp3 = signalPoint.nasTp3;
      effAtr = 0.0;
      if(!NAS_IsValid(entry) || !NAS_IsValid(sl) || !NAS_IsValid(tp1) || !NAS_IsValid(tp2) || !NAS_IsValid(tp3))
         return false;

      double mult = MathMax(0.1, InpPineRiskDistanceMultiplier);
      if(MathAbs(mult - 1.0) > 1e-9)
      {
         double risk = MathAbs(entry - sl) * mult;
         sl = direction > 0 ? entry - risk : entry + risk;
         tp1 = direction > 0 ? entry + risk * 1.0 : entry - risk * 1.0;
         tp2 = direction > 0 ? entry + risk * 2.0 : entry - risk * 2.0;
         tp3 = direction > 0 ? entry + risk * 3.0 : entry - risk * 3.0;
      }
      ApplyStructuralSwingStop(rates, copied, signalIndex, direction, entry, sl, tp1, tp2, tp3);
      ApplyAdaptiveSlWiden(direction, entry, sl, tp1, tp2, tp3);
      ApplyFinalRiskScale(direction, entry, sl, tp1, tp2, tp3);
      return true;
   }

   bool calculated = SATS_CalculateRiskLevelsAtSignal(rates, copied, BuildRiskSettings(), signalIndex, direction,
                                                      entry, sl, tp1, tp2, tp3, effAtr);
   if(!calculated)
      return false;
   ApplyStructuralSwingStop(rates, copied, signalIndex, direction, entry, sl, tp1, tp2, tp3);
   ApplyAdaptiveSlWiden(direction, entry, sl, tp1, tp2, tp3);
   ApplyFinalRiskScale(direction, entry, sl, tp1, tp2, tp3);
   return true;
}

void ProcessSignalBar()
{
   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), InpSignalBarMode == NAS_SIGNAL_BAR_LIVE);
   if(copied < 200)
      return;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);

   int i = LastSignalScanIndex(copied);
   if(i < 1)
      return;
   int direction = p[i].buy ? 1 : (p[i].sell ? -1 : 0);
   if(direction == 0)
   {
      if(InpAuditNoSignalEvaluations && rates[i].time != g_lastNoSignalAuditBarTime)
      {
         PrintSignalParityAudit(rates, p, i, "no_signal_eval");
         g_lastNoSignalAuditBarTime = rates[i].time;
      }
      return;
   }
   PrintSignalParityAudit(rates, p, i, "signal_detected");
   if(rates[i].time == g_lastSignalTime && direction == g_lastSignalKeyDirection)
      return;
   if(WasDirectionProcessedOnBar(rates[i].time, direction))
   {
      Print("NAS SATS EA duplicate live signal ignored dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]));
      return;
   }

   if(!g_eaEnabledRuntime)
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "global_ea_kill_switch_off";
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]), "EA OFF");
      Print("NAS SATS EA global kill switch blocked signal dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]));
      UpdateDashboard();
      return;
   }

   bool tradingWindowOpen = IsTradingTimeOpen();
   if(!tradingWindowOpen)
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]), "WINDOW");
      int openDir = ManagedPositionDirection();
      if(InpCloseExistingOnNewSignal && openDir != 0 && openDir != direction)
      {
         CloseManagedPositions();
         Print("NAS SATS EA reverse signal closed existing position outside trading window dir=",
               (direction > 0 ? "BUY" : "SELL"),
               " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
               " trading_window=", TradingTimeStateText(),
               " no_new_entry=true",
               " same_direction_lock_retained=", (g_lastExecutedDirection > 0 ? "BUY" : (g_lastExecutedDirection < 0 ? "SELL" : "NONE")));
      }
      else
      {
         Print("NAS SATS EA signal ignored outside trading window dir=",
               (direction > 0 ? "BUY" : "SELL"),
               " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
               " trading_window=", TradingTimeStateText(),
               " audit=window_before_same_direction_guard");
      }
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "trading_window_closed";
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      return;
   }

   if(direction == g_lastExecutedDirection)
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      Print("NAS SATS EA same-direction signal ignored dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]),
            " reason=already_executed_direction_waiting_for_opposite",
            " hard_safety=true",
            " input_block_same_direction=", (InpBlockSameDirectionUntilReverse ? "true" : "false"));
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "same_direction_waiting_for_opposite";
      return;
   }

   string spreadReason = "";
   if(!IsSpreadExecutionAllowed(spreadReason))
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = spreadReason;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]), "SPREAD");
      Print("NAS SATS EA spread governor blocked signal dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]),
            " reason=", spreadReason);
      UpdateDashboard();
      return;
   }

   double effAtr = 0.0;
   if(!CalculateRisk(rates, copied, i, direction, p[i], g_lastEntry, g_lastSl, g_lastTp1, g_lastTp2, g_lastTp3, effAtr))
   {
      Print("NAS SATS EA risk calculation failed signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " direction=", (direction > 0 ? "BUY" : "SELL"));
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "risk_calculation_failed";
      return;
   }

   datetime expectedClose = rates[i].time + PeriodSeconds(_Period);
   int signalDelaySec = (int)(TimeCurrent() - expectedClose);

   g_lastSignalTime = rates[i].time;
   g_lastSignalKeyDirection = direction;
   g_lastDirection = direction;
   g_lastEntry = NormalizeDouble(g_lastEntry, _Digits);
   g_lastSl = NormalizeDouble(g_lastSl, _Digits);
   g_lastTp1 = NormalizeDouble(g_lastTp1, _Digits);
   g_lastTp2 = NormalizeDouble(g_lastTp2, _Digits);
   g_lastTp3 = NormalizeDouble(g_lastTp3, _Digits);
   ApplyExecutionModeRisk(direction);
   g_beMoved = false;
   g_lastExecutionStatus = "EXECUTING";
   g_lastExecutionBlockReason = "";

   if(InpCloseExistingOnNewSignal)
      CloseManagedPositions();

   Print("NAS SATS EA executing signal dir=", (direction > 0 ? "BUY" : "SELL"),
         " copied_bars=", copied,
         " mode=", EnumToString(InpSignalBarMode),
         " execution_mode=", EnumToString(InpExecutionMode),
         " risk_engine=", EnumToString(InpRiskEngine),
         " label=", NasSignalText(p[i]),
         " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
         " expected_close=", TimeToString(expectedClose, TIME_DATE|TIME_SECONDS),
         " delay_sec=", signalDelaySec,
         " nas_st=", DoubleToString(p[i].superTrend, _Digits),
         " pine_entry=", DoubleToString(g_lastEntry, _Digits),
         " sats_eff_atr=", DoubleToString(effAtr, _Digits),
         " base_sl=", DoubleToString(g_lastRiskBaseSl, _Digits),
         " structural_stop_used=", (g_lastRiskUsedStructuralStop ? "true" : "false"),
         " swing_price=", DoubleToString(g_lastRiskSwingPrice, _Digits),
         " swing_age_bars=", g_lastRiskSwingAgeBars,
         " swing_atr=", DoubleToString(g_lastRiskSwingAtr, _Digits),
         " swing_prominence_atr=", DoubleToString(g_lastRiskSwingProminence, 2),
         " pre_widen_sl=", DoubleToString(g_lastRiskPreWidenSl, _Digits),
         " sl_widen_pct=", DoubleToString(g_lastRiskWidenPct, 1),
         " sl=", DoubleToString(g_lastSl, _Digits),
         " tp1=", DoubleToString(g_lastTp1, _Digits),
         " tp2=", DoubleToString(g_lastTp2, _Digits),
         " tp3=", DoubleToString(g_lastTp3, _Digits));

   bool opened = OpenThreeLegs(direction);
   if(opened)
   {
      g_lastExecutedDirection = direction;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpSignalBarMode == NAS_SIGNAL_BAR_LIVE)
      {
         g_liveSignalBarTime = rates[i].time;
         g_liveSignalDirection = direction;
      }
      if(InpDrawTradeLevels)
         DrawTradeLevels(direction);
      if(InpDrawExecutionArrows)
         DrawExecutionSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]));
      g_lastExecutionStatus = "OPENED";
      g_lastExecutionBlockReason = "";
   }
   else
   {
      g_lastExecutionStatus = "BLOCKED";
      if(g_lastExecutionBlockReason == "")
         g_lastExecutionBlockReason = "broker_order_open_failed";
      if(StringFind(g_lastExecutionBlockReason, "lock_busy") >= 0)
      {
         g_lastSignalTime = 0;
         g_lastSignalKeyDirection = 0;
         Print("NAS SATS EA signal deferred for account risk lock retry dir=",
               (direction > 0 ? "BUY" : "SELL"),
               " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS));
      }
   }
}

void ReconcileLiveSignalAfterBarClose()
{
   if(!InpReconcileLiveSignalsOnBarClose || g_liveSignalBarTime <= 0 || g_liveSignalDirection == 0)
      return;

   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), false);
   if(copied < 200)
      return;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);

   int closedIndex = -1;
   int scanStop = copied - 6;
   if(scanStop < 0)
      scanStop = 0;
   for(int i = copied - 2; i >= scanStop; i--)
   {
      if(rates[i].time == g_liveSignalBarTime)
      {
         closedIndex = i;
         break;
      }
   }

   if(closedIndex < 0)
   {
      Print("NAS SATS EA live reconcile skipped: signal bar not found bar=",
            TimeToString(g_liveSignalBarTime, TIME_DATE|TIME_SECONDS),
            " dir=", (g_liveSignalDirection > 0 ? "BUY" : "SELL"));
      return;
   }

   int confirmedDirection = p[closedIndex].buy ? 1 : (p[closedIndex].sell ? -1 : 0);
   PrintSignalParityAudit(rates, p, closedIndex, "live_reconcile_closed_bar");
   if(confirmedDirection == g_liveSignalDirection)
   {
      Print("NAS SATS EA live signal confirmed on bar close dir=",
            (g_liveSignalDirection > 0 ? "BUY" : "SELL"),
            " bar=", TimeToString(g_liveSignalBarTime, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[closedIndex]));
      g_liveSignalBarTime = 0;
      g_liveSignalDirection = 0;
      return;
   }

   Print("NAS SATS EA live signal vanished on bar close dir=",
         (g_liveSignalDirection > 0 ? "BUY" : "SELL"),
         " bar=", TimeToString(g_liveSignalBarTime, TIME_DATE|TIME_SECONDS),
         " confirmed=", (confirmedDirection > 0 ? "BUY" : (confirmedDirection < 0 ? "SELL" : "NONE")),
         " action=cleanup",
         " close_position=", (InpCloseVanishedLiveSignalPosition ? "true" : "false"));

   if(InpCloseVanishedLiveSignalPosition && ManagedPositionDirection() == g_liveSignalDirection)
      CloseManagedPositions();

   ClearLiveSignalObjects(g_liveSignalBarTime, g_liveSignalDirection);
   if(ManagedPositionDirection() == 0)
   {
      ClearTradeLevelObjects();
      // Do not clear g_lastExecutedDirection here. Same-direction re-entry
      // must stay blocked until an opposite NAS signal is actually accepted.
   }
   if(g_lastSignalTime == g_liveSignalBarTime && g_lastSignalKeyDirection == g_liveSignalDirection)
   {
      g_lastSignalTime = 0;
      g_lastSignalKeyDirection = 0;
   }

   g_liveSignalBarTime = 0;
   g_liveSignalDirection = 0;
   UpdateDashboard();
   ChartRedraw(0);
}

int MaxTpHitBeforeExit(const MqlRates &rates[], const NasPoint &p[], const int signalIndex, const int direction, const int lastIndex, string &outcome)
{
   double entry, sl, tp1, tp2, tp3, atr;
   int maxHit = 0;
   outcome = "open";
   if(!CalculateRisk(rates, lastIndex + 1, signalIndex, direction, p[signalIndex], entry, sl, tp1, tp2, tp3, atr))
   {
      outcome = "risk unavailable";
      return 0;
   }

   int end = lastIndex;
   for(int j = signalIndex + 1; j <= lastIndex; j++)
   {
      if(j > signalIndex + 1 && (p[j].buy || p[j].sell))
      {
         end = j - 1;
         outcome = "next signal";
         break;
      }
   }

   for(int j = signalIndex + 1; j <= end; j++)
   {
      bool tp1Hit = direction > 0 ? rates[j].high >= tp1 : rates[j].low <= tp1;
      bool tp2Hit = direction > 0 ? rates[j].high >= tp2 : rates[j].low <= tp2;
      bool tp3Hit = direction > 0 ? rates[j].high >= tp3 : rates[j].low <= tp3;
      bool slHit = direction > 0 ? rates[j].low <= sl : rates[j].high >= sl;
      if(tp1Hit) maxHit = MathMax(maxHit, 1);
      if(tp2Hit) maxHit = MathMax(maxHit, 2);
      if(tp3Hit) maxHit = MathMax(maxHit, 3);
      if(tp3Hit)
      {
         outcome = "TP3";
         break;
      }
      if(slHit)
      {
         outcome = "SL";
         break;
      }
      if(j - signalIndex >= 100)
      {
         outcome = "timeout";
         break;
      }
   }
   return maxHit;
}

void DrawRecentSignalHistory()
{
   ObjectsDeleteAll(0, PREFIX + "HIST_");

   MqlRates rates[];
   int copied = LoadNasRates(rates, MathMax(InpHistoryBars, 300), false);
   if(copied < 200)
   {
      Print("NAS SATS EA history overlay skipped: insufficient bars copied=", copied);
      return;
   }

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);

   for(int h = 0; h < 3; h++)
      g_historySummary[h] = "-";

   int drawn = 0;
   int wanted = MathMax(1, InpStartupSignalCount);
   for(int i = copied - 2; i >= 0 && drawn < wanted; i--)
   {
      if(!p[i].buy && !p[i].sell)
         continue;
      int direction = p[i].buy ? 1 : -1;
      double entry, sl, tp1, tp2, tp3, atr;
      if(!CalculateRisk(rates, copied, i, direction, p[i], entry, sl, tp1, tp2, tp3, atr))
         continue;
      string outcome = "";
      int maxTp = MaxTpHitBeforeExit(rates, p, i, direction, copied - 2, outcome);
      DrawHistoricalSignal(drawn + 1, direction, rates[i].time, rates[i].high, rates[i].low, entry, maxTp, outcome);
      if(drawn < 3)
      {
         g_historySummary[drawn] = "#" + IntegerToString(drawn + 1) + " " + (direction > 0 ? "BUY " : "SELL ")
                                  + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES)
                                  + " E=" + DoubleToString(entry, _Digits)
                                  + " max=" + (maxTp > 0 ? "TP" + IntegerToString(maxTp) : "none")
                                  + " " + outcome;
      }
      Print("NAS SATS EA history signal#", drawn + 1,
            " dir=", (direction > 0 ? "BUY" : "SELL"),
            " label=", NasSignalText(p[i]),
            " risk_engine=", EnumToString(InpRiskEngine),
            " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
            " nas_st=", DoubleToString(p[i].superTrend, _Digits),
            " entry=", DoubleToString(entry, _Digits),
            " max_tp=", maxTp,
            " outcome=", outcome);
      drawn++;
   }
   Print("NAS SATS EA history overlay drawn=", drawn, " requested=", wanted);
}

double NormalizeVolume(const double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double v = MathFloor(volume / step) * step;
   v = MathMax(minLot, MathMin(maxLot, v));
   return NormalizeDouble(v, 8);
}

string AccountRiskKey(const string kind)
{
   return "PTS_FTMO_RISK_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + kind;
}

bool AccountRiskMagicScoped(const long magic)
{
   return magic >= 4000000000000000000 && magic < 5000000000000000000;
}

datetime AccountRiskGmtDayStart()
{
   datetime now = TimeGMT();
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   datetime shifted = now - resetHour * 3600;
   return shifted - (shifted % 86400) + resetHour * 3600;
}

datetime AccountRiskStartGmt()
{
   string key = AccountRiskKey("START_GMT");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, (double)TimeGMT());
   return (datetime)GlobalVariableGet(key);
}

void AccountRiskCacheInvalidate()
{
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   GlobalVariableSet(AccountRiskKey("METRICS_TS_H" + IntegerToString(resetHour)), 0.0);
}

double AccountRiskInitialBalance()
{
   if(InpAccountRiskInitialBalanceOverride > 0.0)
      return InpAccountRiskInitialBalanceOverride;
   string key = AccountRiskKey("INITIAL_BALANCE");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, MathMax(0.01, AccountInfoDouble(ACCOUNT_BALANCE)));
   return MathMax(0.01, GlobalVariableGet(key));
}

void AccountRiskScopePerformance(double &closedAll, double &closedToday, double &floating)
{
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   string cacheSuffix = "_H" + IntegerToString(resetHour);
   string cacheTsKey = AccountRiskKey("METRICS_TS" + cacheSuffix);
   string closedAllKey = AccountRiskKey("CLOSED_ALL" + cacheSuffix);
   string closedTodayKey = AccountRiskKey("CLOSED_TODAY" + cacheSuffix);
   string floatingKey = AccountRiskKey("FLOATING" + cacheSuffix);
   double nowLocal = (double)TimeLocal();
   if(GlobalVariableCheck(cacheTsKey)
      && nowLocal - GlobalVariableGet(cacheTsKey) < 1.0
      && GlobalVariableCheck(closedAllKey)
      && GlobalVariableCheck(closedTodayKey)
      && GlobalVariableCheck(floatingKey))
   {
      closedAll = GlobalVariableGet(closedAllKey);
      closedToday = GlobalVariableGet(closedTodayKey);
      floating = GlobalVariableGet(floatingKey);
      return;
   }
   closedAll = 0.0;
   closedToday = 0.0;
   floating = 0.0;
   datetime dayStartGmt = AccountRiskGmtDayStart();
   datetime startGmt = AccountRiskStartGmt();
   datetime serverNow = TimeTradeServer();
   datetime gmtNow = TimeGMT();
   datetime dayStartServer = dayStartGmt + (serverNow - gmtNow);
   datetime startServer = startGmt + (serverNow - gmtNow);
   datetime historyStartServer = MathMax(dayStartServer, startServer);
   if(HistorySelect(startServer, serverNow))
   {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;
         ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
            continue;
         if(!AccountRiskMagicScoped((long)HistoryDealGetInteger(ticket, DEAL_MAGIC)))
            continue;
         double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                    + HistoryDealGetDouble(ticket, DEAL_FEE);
         closedAll += pnl;
         if((datetime)HistoryDealGetInteger(ticket, DEAL_TIME) >= historyStartServer)
            closedToday += pnl;
      }
   }
   for(int j = PositionsTotal() - 1; j >= 0; j--)
   {
      ulong ticket = PositionGetTicket(j);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      floating += PositionGetDouble(POSITION_PROFIT)
                + PositionGetDouble(POSITION_SWAP);
   }
   GlobalVariableSet(closedAllKey, closedAll);
   GlobalVariableSet(closedTodayKey, closedToday);
   GlobalVariableSet(floatingKey, floating);
   GlobalVariableSet(cacheTsKey, nowLocal);
}

void AccountRiskMetrics(double &riskCapital, double &dailyLossPct, double &totalDdPct)
{
   double initial = AccountRiskInitialBalance();
   double closedAll, closedToday, floating;
   AccountRiskScopePerformance(closedAll, closedToday, floating);
   double scopeEquity = MathMax(0.01, initial + closedAll + floating);
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   datetime dayStartGmt = AccountRiskGmtDayStart();
   string suffix = "_H" + IntegerToString(resetHour);
   string dayKey = AccountRiskKey("DAY_SCOPE_" + IntegerToString((int)dayStartGmt) + suffix);
   string lastEquityKey = AccountRiskKey("LAST_SCOPE_EQUITY" + suffix);
   string lastEquityTimeKey = AccountRiskKey("LAST_SCOPE_EQUITY_GMT" + suffix);
   if(!GlobalVariableCheck(dayKey))
   {
      double reconstructed = MathMax(0.01, initial + closedAll - closedToday);
      if(GlobalVariableCheck(lastEquityKey) && GlobalVariableCheck(lastEquityTimeKey))
      {
         datetime previousGmt = (datetime)GlobalVariableGet(lastEquityTimeKey);
         if(previousGmt <= dayStartGmt && dayStartGmt - previousGmt <= 300)
            reconstructed = MathMax(0.01, GlobalVariableGet(lastEquityKey));
      }
      GlobalVariableSet(dayKey, reconstructed);
   }
   double dayStartScope = MathMax(0.01, GlobalVariableGet(dayKey));
   GlobalVariableSet(lastEquityKey, scopeEquity);
   GlobalVariableSet(lastEquityTimeKey, (double)TimeGMT());
   riskCapital = MathMax(0.01, MathMin(AccountInfoDouble(ACCOUNT_EQUITY), scopeEquity));
   dailyLossPct = MathMax(0.0, (dayStartScope - scopeEquity) / dayStartScope * 100.0);
   totalDdPct = MathMax(0.0, -(closedAll + floating) / initial * 100.0);
}

double ClosedDailyAtr(const string symbol, const int period)
{
   int handle = iATR(symbol, PERIOD_D1, MathMax(2, period));
   if(handle == INVALID_HANDLE)
      return 0.0;
   double values[];
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(handle, 0, 1, 1, values);
   IndicatorRelease(handle);
   if(copied != 1 || !MathIsValidNumber(values[0]) || values[0] <= 0.0)
      return 0.0;
   return values[0];
}

bool AccountOpenRisk(double &riskMoney, int &unprotectedCount)
{
   riskMoney = 0.0;
   unprotectedCount = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string symbol = PositionGetSymbol(i);
      if(symbol == "")
         continue;
      if(!AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
      {
         unprotectedCount++;
         continue;
      }
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      bool exposed = (posType == POSITION_TYPE_BUY && sl < entry)
                  || (posType == POSITION_TYPE_SELL && sl > entry);
      if(!exposed)
         continue;
      ENUM_ORDER_TYPE orderType = posType == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double result = 0.0;
      if(!OrderCalcProfit(orderType, symbol, volume, entry, sl, result))
      {
         unprotectedCount++;
         continue;
      }
      riskMoney += MathMax(0.0, -result);
   }
   return true;
}

bool AccountRiskLockAcquire()
{
   string key = AccountRiskKey("LOCK");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   for(int i = 0; i < 50; i++)
   {
      double observed = GlobalVariableGet(key);
      double now = (double)TimeLocal();
      double leaseUntil = MathFloor(observed);
      if(leaseUntil <= now)
      {
         long chartPart = (long)(ChartID() % 100000);
         double tokenFraction = (double)(chartPart * 10 + (GetTickCount() % 10) + 1) / 1000001.0;
         double candidate = MathFloor(now + 30.0) + tokenFraction;
         if(GlobalVariableSetOnCondition(key, candidate, observed))
         {
            g_accountRiskLockValue = candidate;
            return true;
         }
      }
      Sleep(5);
   }
   return false;
}

void AccountRiskLockRelease()
{
   if(g_accountRiskLockValue > 0.0)
      GlobalVariableSetOnCondition(AccountRiskKey("LOCK"), 0.0, g_accountRiskLockValue);
   g_accountRiskLockValue = 0.0;
}

bool AccountRiskAuditClaimSnapshot()
{
   int interval = MathMax(15, InpAccountRiskAuditIntervalSeconds);
   string key = AccountRiskKey("AUDIT_SNAPSHOT_GMT");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   double now = (double)TimeGMT();
   double observed = GlobalVariableGet(key);
   if(now - observed < interval)
      return false;
   return GlobalVariableSetOnCondition(key, now, observed);
}

bool AccountRiskAuditFileLock(double &token)
{
   token = 0.0;
   string key = AccountRiskKey("AUDIT_FILE_LOCK");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   uint started = GetTickCount();
   while((uint)(GetTickCount() - started) < 10)
   {
      double observed = GlobalVariableGet(key);
      double now = (double)TimeLocal();
      if(observed <= 0.0 || MathFloor(observed) <= now)
      {
         double candidate = MathFloor(now + 2.0) + (double)((ChartID() % 100000) + 1) / 100001.0;
         if(GlobalVariableSetOnCondition(key, candidate, observed))
         {
            token = candidate;
            return true;
         }
      }
      Sleep(1);
   }
   return false;
}

void AccountRiskAuditFileUnlock(const double token)
{
   if(token > 0.0)
      GlobalVariableSetOnCondition(AccountRiskKey("AUDIT_FILE_LOCK"), 0.0, token);
}

string AccountRiskPositionSummary(int &openCount, int &protectedCount, int &unprotectedCount, double &totalVolume, double &openRisk)
{
   openCount = 0;
   protectedCount = 0;
   unprotectedCount = 0;
   totalVolume = 0.0;
   openRisk = 0.0;
   string summary = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)
         || !AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      openCount++;
      totalVolume += volume;
      double risk = -1.0;
      bool exposed = (posType == POSITION_TYPE_BUY && sl > 0.0 && sl < entry)
                  || (posType == POSITION_TYPE_SELL && sl > entry);
      if(exposed)
      {
         double result = 0.0;
         ENUM_ORDER_TYPE orderType = posType == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(OrderCalcProfit(orderType, symbol, volume, entry, sl, result))
         {
            risk = MathMax(0.0, -result);
            openRisk += risk;
            protectedCount++;
         }
         else
            unprotectedCount++;
      }
      else
         unprotectedCount++;
      if(StringLen(summary) < 1800)
      {
         if(StringLen(summary) > 0)
            summary += "|";
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         summary += (string)ticket + ":" + symbol + ":" + (posType == POSITION_TYPE_BUY ? "BUY" : "SELL")
            + ":v=" + DoubleToString(volume, 4)
            + ":e=" + DoubleToString(entry, digits)
            + ":sl=" + DoubleToString(sl, digits)
            + ":risk=" + (risk >= 0.0 ? DoubleToString(risk, 2) : "UNPROTECTED");
      }
   }
   return summary;
}

void WriteAccountRiskAudit(const string eventName, const string detail, const bool periodic)
{
   if(!InpAdvancedAccountRiskEnabled || !InpAccountRiskAuditEnabled)
      return;
   if(periodic && !AccountRiskAuditClaimSnapshot())
      return;
   double closedAll, closedToday, floating;
   AccountRiskScopePerformance(closedAll, closedToday, floating);
   double riskCapital, dailyLossPct, totalDdPct;
   AccountRiskMetrics(riskCapital, dailyLossPct, totalDdPct);
   double initial = AccountRiskInitialBalance();
   double scopeEquity = MathMax(0.01, initial + closedAll + floating);
   int openCount, protectedCount, unprotectedCount;
   double totalVolume, openRisk;
   string positions = AccountRiskPositionSummary(openCount, protectedCount, unprotectedCount, totalVolume, openRisk);
   double tradeBudget = riskCapital * MathMax(0.0, InpAccountRiskPerTradePct) / 100.0;
   double atrBudget = riskCapital * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double portfolioBudget = riskCapital * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginUsagePct = riskCapital > 0.0 ? margin / riskCapital * 100.0 : 100.0;
   string fileName = "AccountRiskAudit_MT5_" + NasAuditDate(TimeGMT()) + ".csv";
   double auditLock = 0.0;
   if(!AccountRiskAuditFileLock(auditLock))
      return;
   int h = FileOpen(fileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      AccountRiskAuditFileUnlock(auditLock);
      return;
   }
   bool empty = FileSize(h) <= 0;
   FileSeek(h, 0, SEEK_END);
   if(empty)
      FileWrite(h, "ts_gmt", "ts_server", "event", "build", "terminal", "account", "reporter", "symbol", "timeframe",
         "initial_balance", "account_balance", "account_equity", "scope_closed_all", "scope_closed_today", "scope_floating",
         "scope_equity", "risk_capital", "daily_loss_pct", "total_dd_pct", "margin", "margin_usage_pct", "open_positions",
         "protected_positions", "unprotected_positions", "total_volume", "open_sl_risk", "trade_budget", "atr_budget",
         "portfolio_budget", "available_portfolio_risk", "safety_pct", "day_reset_gmt", "positions", "detail");
   FileWrite(h, TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS), TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName, "1.25", "MT5", (string)AccountInfoInteger(ACCOUNT_LOGIN), "NasUltimate", _Symbol, EnumToString(_Period),
      DoubleToString(initial, 2), DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), DoubleToString(closedAll, 2),
      DoubleToString(closedToday, 2), DoubleToString(floating, 2), DoubleToString(scopeEquity, 2),
      DoubleToString(riskCapital, 2), DoubleToString(dailyLossPct, 3), DoubleToString(totalDdPct, 3),
      DoubleToString(margin, 2), DoubleToString(marginUsagePct, 3), IntegerToString(openCount),
      IntegerToString(protectedCount), IntegerToString(unprotectedCount), DoubleToString(totalVolume, 4),
      DoubleToString(openRisk, 2), DoubleToString(tradeBudget, 2), DoubleToString(atrBudget, 2),
      DoubleToString(portfolioBudget, 2), DoubleToString(MathMax(0.0, portfolioBudget - openRisk), 2),
      DoubleToString(InpAccountRiskSafetyBufferPct, 1),
      IntegerToString(MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt))), positions, detail);
   FileFlush(h);
   FileClose(h);
   AccountRiskAuditFileUnlock(auditLock);
}

void EnforceAccountRiskBreach()
{
   if(!InpAdvancedAccountRiskEnabled || !InpAccountRiskLiquidateOnBreach)
      return;
   uint guardNow = GetTickCount();
   if(guardNow - g_lastAccountRiskGuardMs < 100)
      return;
   g_lastAccountRiskGuardMs = guardNow;
   double riskCapital, dailyPct, totalPct;
   AccountRiskMetrics(riskCapital, dailyPct, totalPct);
   double safety = MathMax(1.0, MathMin(100.0, InpAccountRiskSafetyBufferPct)) / 100.0;
   bool breached = (InpAccountRiskDailyLossLimitPct > 0.0 && dailyPct >= InpAccountRiskDailyLossLimitPct * safety)
      || (InpAccountRiskMaxDrawdownPct > 0.0 && totalPct >= InpAccountRiskMaxDrawdownPct * safety);
   if(!breached)
      return;
   string attemptKey = AccountRiskKey("BREACH_ATTEMPT");
   double now = (double)TimeLocal();
   if(GlobalVariableCheck(attemptKey) && now - GlobalVariableGet(attemptKey) < 2.0)
      return;
   GlobalVariableSet(attemptKey, now);
   if(!AccountRiskLockAcquire())
      return;
   AccountRiskCacheInvalidate();
   AccountRiskMetrics(riskCapital, dailyPct, totalPct);
   breached = (InpAccountRiskDailyLossLimitPct > 0.0 && dailyPct >= InpAccountRiskDailyLossLimitPct * safety)
      || (InpAccountRiskMaxDrawdownPct > 0.0 && totalPct >= InpAccountRiskMaxDrawdownPct * safety);
   if(!breached)
   {
      AccountRiskLockRelease();
      return;
   }
   Print("NAS SATS ACCOUNT RISK LIQUIDATION daily_loss_pct=", DoubleToString(dailyPct, 3),
         " total_dd_pct=", DoubleToString(totalPct, 3),
         " safety_pct=", DoubleToString(InpAccountRiskSafetyBufferPct, 1));
   WriteAccountRiskAudit("liquidation_triggered",
      "daily_loss_pct=" + DoubleToString(dailyPct, 3) + " total_dd_pct=" + DoubleToString(totalPct, 3), false);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)
         || !AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(!trade.PositionClose(ticket))
         Print("NAS SATS account risk close failed ticket=", ticket,
               " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)
         || !AccountRiskMagicScoped((long)OrderGetInteger(ORDER_MAGIC)))
         continue;
      if(!trade.OrderDelete(ticket))
         Print("NAS SATS account risk pending delete failed ticket=", ticket,
               " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   AccountRiskCacheInvalidate();
   WriteAccountRiskAudit("liquidation_complete", "scoped_positions_close_attempted", false);
   AccountRiskLockRelease();
}

double NormalizeRiskVolume(const double requested, const int divisor)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double configuredMax = InpAdvancedLotMax > 0.0 ? MathMin(maxLot, InpAdvancedLotMax) : maxLot;
   double capped = MathMin(requested, configuredMax);
   if(capped < minLot)
      return 0.0;
   long units = (long)MathFloor(capped / step + 0.0000001);
   int split = MathMax(1, divisor);
   long minUnits = (long)MathCeil(minLot / step - 0.0000001);
   long requiredUnits = minUnits * split;
   if(units < requiredUnits)
      return 0.0;
   units -= units % split;
   if(units < requiredUnits)
      return 0.0;
   double volume = NormalizeDouble((double)units * step, 8);
   if(volume < minLot || volume > configuredMax)
      return 0.0;
   return volume;
}

double ResolveAdvancedVolume(const int direction, const double entry, const double sl, string &detail)
{
   double fallback = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? FixedVolume() : NormalizeVolume(g_totalLotRuntime > 0.0 ? g_totalLotRuntime : InpTotalLot);
   int divisor = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? 1 : 3;
   if(!InpAdvancedAccountRiskEnabled)
   {
      double manualVolume = NormalizeRiskVolume(fallback, divisor);
      detail = "advanced_account_risk=off manual_volume=" + DoubleToString(manualVolume, 4);
      return manualVolume;
   }
   bool advancedLotEnabled = InpAdvancedLotEngineEnabled;

   double equity, dailyLossPct, totalDdPct;
   AccountRiskMetrics(equity, dailyLossPct, totalDdPct);
   double marginUsagePct = equity > 0.0 ? AccountInfoDouble(ACCOUNT_MARGIN) / equity * 100.0 : 100.0;
   double safety = MathMax(1.0, MathMin(100.0, InpAccountRiskSafetyBufferPct)) / 100.0;
   if(equity <= 0.0
      || (InpAccountRiskDailyLossLimitPct > 0.0 && dailyLossPct >= InpAccountRiskDailyLossLimitPct * safety)
      || (InpAccountRiskMaxDrawdownPct > 0.0 && totalDdPct >= InpAccountRiskMaxDrawdownPct * safety)
      || (InpAccountRiskMaxMarginUsagePct > 0.0 && marginUsagePct >= InpAccountRiskMaxMarginUsagePct))
   {
      detail = "account_risk_block equity=" + DoubleToString(equity, 2)
         + " daily_loss_pct=" + DoubleToString(dailyLossPct, 3)
         + " total_dd_pct=" + DoubleToString(totalDdPct, 3)
         + " margin_usage_pct=" + DoubleToString(marginUsagePct, 3);
      return 0.0;
   }

   double dailyAtr = ClosedDailyAtr(_Symbol, InpAdvancedLotDailyAtrPeriod);
   if(sl <= 0.0 || MathAbs(entry - sl) <= 0.0 || dailyAtr <= 0.0)
   {
      detail = "advanced_lot_invalid_inputs atr=" + DoubleToString(dailyAtr, _Digits)
         + " entry=" + DoubleToString(entry, _Digits)
         + " sl=" + DoubleToString(sl, _Digits);
      return InpAccountRiskFailClosed ? 0.0 : fallback;
   }

   ENUM_ORDER_TYPE orderType = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double slResult = 0.0;
   double atrResult = 0.0;
   double atrExit = direction > 0 ? entry - dailyAtr : entry + dailyAtr;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, slResult)
      || !OrderCalcProfit(orderType, _Symbol, 1.0, entry, atrExit, atrResult))
   {
      detail = "advanced_lot_profit_calc_failed err=" + IntegerToString(GetLastError());
      return InpAccountRiskFailClosed ? 0.0 : fallback;
   }
   double slMoneyPerLot = MathAbs(slResult);
   double atrMoneyPerLot = MathAbs(atrResult);
   if(slMoneyPerLot <= 0.0 || atrMoneyPerLot <= 0.0)
   {
      detail = "advanced_lot_invalid_money_per_lot";
      return InpAccountRiskFailClosed ? 0.0 : fallback;
   }

   double openRisk = 0.0;
   int unprotectedCount = 0;
   AccountOpenRisk(openRisk, unprotectedCount);
   if(InpAccountRiskBlockUnprotectedPositions && unprotectedCount > 0)
   {
      detail = "account_risk_block unprotected_positions=" + IntegerToString(unprotectedCount);
      return 0.0;
   }

   double tradeBudget = equity * MathMax(0.0, InpAccountRiskPerTradePct) / 100.0;
   double atrBudget = equity * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double portfolioBudget = equity * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double availablePortfolio = MathMax(0.0, portfolioBudget - openRisk);
   if(tradeBudget <= 0.0 || atrBudget <= 0.0 || availablePortfolio <= 0.0)
   {
      detail = "account_risk_block exhausted_budget open_risk=" + DoubleToString(openRisk, 2)
         + " portfolio_budget=" + DoubleToString(portfolioBudget, 2);
      return 0.0;
   }

   double slVolume = tradeBudget / slMoneyPerLot;
   double atrVolume = atrBudget / atrMoneyPerLot;
   double portfolioVolume = availablePortfolio / slMoneyPerLot;
   double rawVolume = advancedLotEnabled ? MathMin(slVolume, MathMin(atrVolume, portfolioVolume)) : fallback;
   double volume = advancedLotEnabled ? NormalizeRiskVolume(rawVolume, divisor) : NormalizeRiskVolume(fallback, divisor);
   double projectedRisk = slMoneyPerLot * volume;
   double projectedAtr = atrMoneyPerLot * volume;
   if(volume <= 0.0
      || projectedRisk > tradeBudget + 0.01
      || projectedRisk > availablePortfolio + 0.01
      || projectedAtr > atrBudget + 0.01)
   {
      detail = "account_risk_block volume_below_min_or_budget raw=" + DoubleToString(rawVolume, 4)
         + " projected_risk=" + DoubleToString(projectedRisk, 2)
         + " projected_atr=" + DoubleToString(projectedAtr, 2);
      return 0.0;
   }

   double requiredMargin = 0.0;
   bool marginCalculated = OrderCalcMargin(orderType, _Symbol, volume, entry, requiredMargin);
   double projectedMarginPct = equity > 0.0
      ? (AccountInfoDouble(ACCOUNT_MARGIN) + requiredMargin) / equity * 100.0
      : 100.0;
   if(!marginCalculated
      || requiredMargin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)
      || (InpAccountRiskMaxMarginUsagePct > 0.0 && projectedMarginPct > InpAccountRiskMaxMarginUsagePct))
   {
      detail = "account_risk_block insufficient_margin volume=" + DoubleToString(volume, 4)
         + " required=" + DoubleToString(requiredMargin, 2)
         + " projected_margin_pct=" + DoubleToString(projectedMarginPct, 3);
      return 0.0;
   }

   detail = (advancedLotEnabled ? "advanced_lot=account_risk" : "advanced_lot=off_risk_validated")
      + " equity=" + DoubleToString(equity, 2)
      + " daily_atr=" + DoubleToString(dailyAtr, _Digits)
      + " sl_money_per_lot=" + DoubleToString(slMoneyPerLot, 2)
      + " atr_money_per_lot=" + DoubleToString(atrMoneyPerLot, 2)
      + " open_risk=" + DoubleToString(openRisk, 2)
      + " trade_budget=" + DoubleToString(tradeBudget, 2)
      + " atr_budget=" + DoubleToString(atrBudget, 2)
      + " portfolio_budget=" + DoubleToString(portfolioBudget, 2)
      + " sl_volume=" + DoubleToString(slVolume, 4)
      + " atr_volume=" + DoubleToString(atrVolume, 4)
      + " portfolio_volume=" + DoubleToString(portfolioVolume, 4)
      + " final_volume=" + DoubleToString(volume, 4)
      + " projected_risk=" + DoubleToString(projectedRisk, 2)
      + " daily_loss_pct=" + DoubleToString(dailyLossPct, 3)
      + " total_dd_pct=" + DoubleToString(totalDdPct, 3);
   return volume;
}

double LegVolume()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double totalLot = g_totalLotRuntime > 0.0 ? g_totalLotRuntime : InpTotalLot;
   return NormalizeVolume(MathFloor((totalLot / 3.0) / step) * step);
}

double FixedVolume()
{
   double fixedLot = g_fixedLotRuntime > 0.0 ? g_fixedLotRuntime : InpFixedLot;
   return NormalizeVolume(fixedLot);
}

void ApplyExecutionModeRisk(const int direction)
{
   if(InpExecutionMode != NAS_EXEC_FIXED_1_TO_3R)
      return;
   double risk = MathAbs(g_lastEntry - g_lastSl);
   if(risk <= 0.0)
      return;
   double rr = MathMax(0.1, InpFixedRR);
   double tp = direction > 0 ? g_lastEntry + risk * rr : g_lastEntry - risk * rr;
   tp = NormalizeDouble(tp, _Digits);
   g_lastTp1 = tp;
   g_lastTp2 = tp;
   g_lastTp3 = tp;
}

bool OpenThreeLegs(const int direction)
{
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      return OpenFixedOneToThreeR(direction);

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool riskLockHeld = false;
   if(InpAdvancedAccountRiskEnabled && !AccountRiskLockAcquire())
   {
      g_lastAdvancedLotDetail = "account_risk_block lock_busy";
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      WriteAccountRiskAudit("lot_blocked", "mode=partial dir=" + IntegerToString(direction) + " " + g_lastAdvancedLotDetail, false);
      return false;
   }
   riskLockHeld = InpAdvancedAccountRiskEnabled;
   if(riskLockHeld)
      AccountRiskCacheInvalidate();
   g_lastAdvancedLotDetail = "";
   double totalVolume = ResolveAdvancedVolume(direction, price, g_lastSl, g_lastAdvancedLotDetail);
   string riskGeometry = "mode=partial dir=" + IntegerToString(direction)
      + " entry=" + DoubleToString(price, _Digits) + " sl=" + DoubleToString(g_lastSl, _Digits)
      + " base_sl=" + DoubleToString(g_lastRiskBaseSl, _Digits)
      + " structural_used=" + (g_lastRiskUsedStructuralStop ? "1" : "0")
      + " swing=" + DoubleToString(g_lastRiskSwingPrice, _Digits)
      + " swing_age=" + IntegerToString(g_lastRiskSwingAgeBars)
      + " swing_atr=" + DoubleToString(g_lastRiskSwingAtr, _Digits)
      + " prominence_atr=" + DoubleToString(g_lastRiskSwingProminence, 2)
      + " pre_widen_sl=" + DoubleToString(g_lastRiskPreWidenSl, _Digits)
      + " widen_pct=" + DoubleToString(g_lastRiskWidenPct, 2)
      + " final_scale_pct=" + DoubleToString(g_lastRiskFinalScalePct, 2)
      + " " + g_lastAdvancedLotDetail;
   g_lastAdvancedLot = totalVolume;
   if(totalVolume <= 0.0)
   {
      if(riskLockHeld)
         AccountRiskLockRelease();
      WriteAccountRiskAudit("lot_blocked", riskGeometry, false);
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      Print("NAS SATS Partial-NoBE EA: account risk blocked open reason=", g_lastAdvancedLotDetail);
      return false;
   }
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0)
      step = 0.01;
   double leg = NormalizeDouble(totalVolume / 3.0, 8);
   double legUnits = leg / step;
   bool exactLeg = MathAbs(legUnits - MathRound(legUnits)) <= 0.0000001;
   if(leg < minLot - 0.0000001 || !exactLeg)
   {
      if(riskLockHeld)
         AccountRiskLockRelease();
      g_lastExecutionBlockReason = "invalid_leg_after_advanced_lot " + g_lastAdvancedLotDetail;
      Print("NAS SATS Partial-NoBE EA: invalid leg volume from advanced total lot ", DoubleToString(totalVolume, 8));
      return false;
   }
   Print("NAS SATS advanced lot resolved mode=partial total=", DoubleToString(totalVolume, 8),
         " leg=", DoubleToString(leg, 8), " ", g_lastAdvancedLotDetail);
   double tps[3] = {g_lastTp1, g_lastTp2, g_lastTp3};
   string comments[3];
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
   {
      comments[0] = "NAS_ORIG_TP1_BE";
      comments[1] = "NAS_ORIG_TP2_BE";
      comments[2] = "NAS_ORIG_TP3_BE";
   }
   else
   {
      comments[0] = "NAS_NOBE_TP1";
      comments[1] = "NAS_NOBE_TP2";
      comments[2] = "NAS_NOBE_TP3";
   }
   ulong existingTickets[];
   int existingCount = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong existingTicket = PositionGetTicket(p);
      if(existingTicket == 0 || !PositionSelectByTicket(existingTicket) || !IsManagedPosition())
         continue;
      ArrayResize(existingTickets, existingCount + 1);
      existingTickets[existingCount++] = existingTicket;
   }
   int openedCount = 0;

   for(int i = 0; i < 3; i++)
   {
      bool requestOk = trade.PositionOpen(_Symbol, type, leg, price, g_lastSl, tps[i], comments[i]);
      uint retcode = trade.ResultRetcode();
      bool ok = requestOk && (retcode == TRADE_RETCODE_DONE
         || retcode == TRADE_RETCODE_DONE_PARTIAL
         || retcode == TRADE_RETCODE_PLACED);
      if(!ok)
         Print("NAS SATS Partial-NoBE EA open failed leg=", i + 1, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      else
         openedCount++;
   }
   if(openedCount != 3)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition())
            continue;
         bool existed = false;
         for(int e = 0; e < existingCount; e++)
         {
            if(existingTickets[e] == ticket)
            {
               existed = true;
               break;
            }
         }
         if(existed)
            continue;
         if(!trade.PositionClose(ticket))
            Print("NAS SATS partial batch rollback failed ticket=", ticket,
                  " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
      if(riskLockHeld)
         AccountRiskCacheInvalidate();
      if(riskLockHeld)
         AccountRiskLockRelease();
      g_lastExecutionBlockReason = "partial_batch_incomplete opened=" + IntegerToString(openedCount) + "/3";
      WriteAccountRiskAudit("lot_selected",
         riskGeometry + " opened_legs=" + IntegerToString(openedCount) + " execution=partial_batch_incomplete", false);
      return false;
   }
   if(riskLockHeld)
      AccountRiskCacheInvalidate();
   if(riskLockHeld)
      AccountRiskLockRelease();
   WriteAccountRiskAudit("lot_selected",
      riskGeometry + " opened_legs=" + IntegerToString(openedCount), false);
   return true;
}

bool OpenFixedOneToThreeR(const int direction)
{
   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool riskLockHeld = false;
   if(InpAdvancedAccountRiskEnabled && !AccountRiskLockAcquire())
   {
      g_lastAdvancedLotDetail = "account_risk_block lock_busy";
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      WriteAccountRiskAudit("lot_blocked", "mode=fixed dir=" + IntegerToString(direction) + " " + g_lastAdvancedLotDetail, false);
      return false;
   }
   riskLockHeld = InpAdvancedAccountRiskEnabled;
   if(riskLockHeld)
      AccountRiskCacheInvalidate();
   g_lastAdvancedLotDetail = "";
   double lot = ResolveAdvancedVolume(direction, price, g_lastSl, g_lastAdvancedLotDetail);
   string fixedRiskGeometry = "mode=fixed dir=" + IntegerToString(direction)
      + " entry=" + DoubleToString(price, _Digits) + " sl=" + DoubleToString(g_lastSl, _Digits)
      + " base_sl=" + DoubleToString(g_lastRiskBaseSl, _Digits)
      + " structural_used=" + (g_lastRiskUsedStructuralStop ? "1" : "0")
      + " swing=" + DoubleToString(g_lastRiskSwingPrice, _Digits)
      + " swing_age=" + IntegerToString(g_lastRiskSwingAgeBars)
      + " swing_atr=" + DoubleToString(g_lastRiskSwingAtr, _Digits)
      + " prominence_atr=" + DoubleToString(g_lastRiskSwingProminence, 2)
      + " pre_widen_sl=" + DoubleToString(g_lastRiskPreWidenSl, _Digits)
      + " widen_pct=" + DoubleToString(g_lastRiskWidenPct, 2)
      + " final_scale_pct=" + DoubleToString(g_lastRiskFinalScalePct, 2)
      + " " + g_lastAdvancedLotDetail;
   g_lastAdvancedLot = lot;
   if(lot <= 0.0)
   {
      if(riskLockHeld)
         AccountRiskLockRelease();
      WriteAccountRiskAudit("lot_blocked", fixedRiskGeometry, false);
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      Print("NAS SATS Fixed 1:3R EA: account risk blocked open reason=", g_lastAdvancedLotDetail);
      return false;
   }
   Print("NAS SATS advanced lot resolved mode=fixed lot=", DoubleToString(lot, 8),
         " ", g_lastAdvancedLotDetail);

   string comment = direction > 0 ? "NAS_FIXED_3R_BUY" : "NAS_FIXED_3R_SELL";
   bool requestOk = trade.PositionOpen(_Symbol, type, lot, price, g_lastSl, g_lastTp3, comment);
   uint retcode = trade.ResultRetcode();
   bool ok = requestOk && (retcode == TRADE_RETCODE_DONE
      || retcode == TRADE_RETCODE_DONE_PARTIAL
      || retcode == TRADE_RETCODE_PLACED);
   if(ok && riskLockHeld)
      AccountRiskCacheInvalidate();
   if(riskLockHeld)
      AccountRiskLockRelease();
   WriteAccountRiskAudit("lot_selected",
      fixedRiskGeometry + " order_retcode=" + IntegerToString((int)retcode), false);
   if(!ok)
   {
      Print("NAS SATS Fixed 1:3R open failed ret=", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription(),
            " lot=", DoubleToString(lot, 8),
            " sl=", DoubleToString(g_lastSl, _Digits),
            " tp=", DoubleToString(g_lastTp3, _Digits));
      return false;
   }
   return true;
}

bool IsManagedPosition()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   return RuntimeMagicOwned((long)PositionGetInteger(POSITION_MAGIC));
}

int ManagedPositionDirection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      return type == POSITION_TYPE_BUY ? 1 : -1;
   }
   return 0;
}

void CloseManagedPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPosition())
         trade.PositionClose(ticket);
   }
}

void CloseOneLeg()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPosition())
      {
         trade.PositionClose(ticket);
         return;
      }
   }
}

void MoveRemainingToBE()
{
   if(InpExecutionMode != NAS_EXEC_PARTIAL_BE_ORIGINAL)
   {
      Print("NAS SATS EA: SL -> BE ignored by selected execution mode.");
      return;
   }
   if(g_lastEntry <= 0.0)
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;
      double tp = PositionGetDouble(POSITION_TP);
      trade.PositionModify(ticket, NormalizeDouble(g_lastEntry, _Digits), tp);
   }
   g_beMoved = true;
}

string NasAuditDate(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
}

void WriteTpWatchdogAudit(const string eventName, const ulong ticket, const string dirText, const double vol, const double entry, const double tp, const double closePx, const string reason)
{
   string fileName = "NasUltimate_TpWatchdog_" + NasAuditDate(TimeGMT()) + ".csv";
   int h = FileOpen(fileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
   {
      Print("NAS SATS TP watchdog audit open failed err=", GetLastError(), " file=", fileName);
      return;
   }
   bool empty = FileSize(h) <= 0;
   FileSeek(h, 0, SEEK_END);
   if(empty)
      FileWrite(h, "ts_gmt", "ts_server", "event", "symbol", "timeframe", "magic", "ticket", "direction", "volume", "entry", "tp", "close_px", "bid", "ask", "tolerance_points", "reason");
   FileWrite(
      h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName,
      _Symbol,
      EnumToString(_Period),
      (string)RuntimeMagic(),
      (string)ticket,
      dirText,
      DoubleToString(vol, 8),
      DoubleToString(entry, _Digits),
      DoubleToString(tp, _Digits),
      DoubleToString(closePx, _Digits),
      DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits),
      DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits),
      DoubleToString(InpTpTouchCloseTolerancePoints, 1),
      reason
   );
   FileClose(h);
}

void EnforceManagedTpTouchClose(const bool force)
{
   if(!InpEnforceTpTouchClose)
      return;
   uint nowMs = GetTickCount();
   int minMs = MathMax(20, InpTpTouchWatchdogTimerMs);
   if(!force && g_lastTpTouchWatchdogMs > 0 && nowMs - g_lastTpTouchWatchdogMs < (uint)minMs)
      return;
   g_lastTpTouchWatchdogMs = nowMs;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;

      double tp = PositionGetDouble(POSITION_TP);
      if(tp <= 0.0)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      int direction = type == POSITION_TYPE_BUY ? 1 : -1;
      double closePx = direction > 0 ? bid : ask;
      double tol = MathMax(0.0, InpTpTouchCloseTolerancePoints) * _Point;
      bool touched = direction > 0 ? (bid + tol >= tp) : (ask - tol <= tp);
      if(!touched)
         continue;

      string dirText = direction > 0 ? "BUY" : "SELL";
      double vol = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      bool ok = false;
      int attempts = MathMax(1, InpTpTouchCloseRetryCount);
      for(int attempt = 1; attempt <= attempts; attempt++)
      {
         ResetLastError();
         ok = trade.PositionClose(ticket);
         if(ok)
            break;
         Print("NAS SATS TP watchdog close attempt failed ticket=", ticket,
               " attempt=", attempt,
               " ret=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription());
      }
      if(ok)
      {
         Print("NAS SATS TP watchdog closed ticket=", ticket,
               " dir=", dirText,
               " vol=", DoubleToString(vol, 8),
               " entry=", DoubleToString(entry, _Digits),
               " tp=", DoubleToString(tp, _Digits),
               " close_px=", DoubleToString(closePx, _Digits),
               " tolerance_pts=", DoubleToString(InpTpTouchCloseTolerancePoints, 1));
         WriteTpWatchdogAudit("tp_watchdog_closed", ticket, dirText, vol, entry, tp, closePx, "tp_touched");
      }
      else
      {
         Print("NAS SATS TP watchdog close failed ticket=", ticket,
               " dir=", dirText,
               " tp=", DoubleToString(tp, _Digits),
               " close_px=", DoubleToString(closePx, _Digits),
               " ret=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription());
         WriteTpWatchdogAudit("tp_watchdog_close_failed", ticket, dirText, vol, entry, tp, closePx, "ret=" + (string)trade.ResultRetcode() + " " + trade.ResultRetcodeDescription());
      }
   }
}

void ManageOpenPositions()
{
   EnforceManagedTpTouchClose(true);

   if(InpExecutionMode != NAS_EXEC_PARTIAL_BE_ORIGINAL)
      return;
   if(g_lastDirection == 0 || g_beMoved)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool tp1Touched = g_lastDirection > 0 ? (bid >= g_lastTp1) : (ask <= g_lastTp1);
   if(tp1Touched)
      MoveRemainingToBE();
}

double ManagedOpenPnl()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPosition())
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

double HistoryPnl(const datetime fromTime)
{
   double pnl = 0.0;
   if(!HistorySelect(fromTime, TimeCurrent()))
      return 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      if(!RuntimeMagicOwned((long)HistoryDealGetInteger(deal, DEAL_MAGIC)))
         continue;
      pnl += HistoryDealGetDouble(deal, DEAL_PROFIT);
      pnl += HistoryDealGetDouble(deal, DEAL_SWAP);
      pnl += HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
   return pnl;
}

datetime DayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

void DrawHLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style, const int width)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
}

void DrawHistoricalArrow(const string name, const datetime t, const double price, const int arrowCode, const color clr)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_ARROW, 0, t, price);
   ObjectMove(0, obj, 0, t, price);
   ObjectSetInteger(0, obj, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, 2);
}

void DrawExecutionSignal(const int direction,
                         const datetime signalTime,
                         const double signalHigh,
                         const double signalLow,
                         const string signalLabel)
{
   string side = direction > 0 ? "BUY" : "SELL";
   string stamp = IntegerToString((int)signalTime) + "_" + side;
   double pad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 30.0, MathAbs(signalHigh - signalLow) * 0.45);
   double arrowPrice = direction > 0 ? signalLow - pad : signalHigh + pad;
   double textPrice = direction > 0 ? arrowPrice - pad * 0.55 : arrowPrice + pad * 0.55;
   color clr = direction > 0 ? clrLime : clrTomato;
   int arrowCode = direction > 0 ? 233 : 234;
   string arrowName = "LIVE_EXEC_" + stamp + "_ARW";
   string textName = "LIVE_EXEC_" + stamp + "_TXT";
   DrawHistoricalArrow(arrowName, signalTime, arrowPrice, arrowCode, clr);
   DrawHistoricalText(textName,
                      "EXEC " + signalLabel + " E=" + DoubleToString(g_lastEntry, _Digits),
                      signalTime + PeriodSeconds(_Period),
                      textPrice,
                      clr);
}

void DrawBlockedSignal(const int direction,
                       const datetime signalTime,
                       const double signalHigh,
                       const double signalLow,
                       const string signalLabel,
                       const string reason)
{
   string side = direction > 0 ? "BUY" : "SELL";
   string stamp = IntegerToString((int)signalTime) + "_" + side + "_" + reason;
   double pad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 30.0, MathAbs(signalHigh - signalLow) * 0.45);
   double arrowPrice = direction > 0 ? signalLow - pad : signalHigh + pad;
   double textPrice = direction > 0 ? arrowPrice - pad * 0.55 : arrowPrice + pad * 0.55;
   color clr = direction > 0 ? C'92,174,255' : C'255,128,210';
   int arrowCode = direction > 0 ? 241 : 242;
   string arrowName = "BLOCKED_" + stamp + "_ARW";
   string textName = "BLOCKED_" + stamp + "_TXT";
   DrawHistoricalArrow(arrowName, signalTime, arrowPrice, arrowCode, clr);
   DrawHistoricalText(textName,
                      reason + " " + signalLabel + " signal",
                      signalTime + PeriodSeconds(_Period),
                      textPrice,
                      clr);
}

void DrawHistoricalText(const string name, const string text, const datetime t, const double price, const color clr)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
   ObjectMove(0, obj, 0, t, price);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void DrawHistoricalSignal(const int idx,
                          const int direction,
                          const datetime signalTime,
                          const double signalHigh,
                          const double signalLow,
                          const double entry,
                          const int maxTp,
                          const string outcome)
{
   string base = "HIST_" + IntegerToString(idx) + "_";
   double atrPad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 20.0, MathAbs(signalHigh - signalLow) * 0.35);
   double arrowPrice = direction > 0 ? signalLow - atrPad : signalHigh + atrPad;
   double labelPrice = direction > 0 ? arrowPrice - atrPad * 0.55 : arrowPrice + atrPad * 0.55;
   color clr = direction > 0 ? clrLime : clrTomato;
   int arrowCode = direction > 0 ? 233 : 234;
   string maxText = maxTp > 0 ? "TP" + IntegerToString(maxTp) : "none";
   string txt = (direction > 0 ? "BUY" : "SELL") + " #" + IntegerToString(idx)
                + " E=" + DoubleToString(entry, _Digits)
                + " max=" + maxText
                + " " + outcome;
   DrawHistoricalArrow(base + "ARW", signalTime, arrowPrice, arrowCode, clr);
   DrawHistoricalText(base + "TXT", txt, signalTime + PeriodSeconds(_Period) * 2, labelPrice, clr);
}

void DrawTextLabel(const string name, const string text, const double price, const color clr)
{
   string obj = PREFIX + name;
   datetime t = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * 8;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
   ObjectMove(0, obj, 0, t, price);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
}

void DrawTradeLevels(const int direction)
{
   DrawHLine("ENTRY", g_lastEntry, clrSilver, STYLE_SOLID, 2);
   DrawHLine("SL", g_lastSl, clrRed, STYLE_SOLID, 2);
   string d = direction > 0 ? "BUY" : "SELL";
   DrawTextLabel("ENTRY_TXT", d + " ENTRY " + DoubleToString(g_lastEntry, _Digits), g_lastEntry, clrWhite);
   DrawTextLabel("SL_TXT", "SL " + DoubleToString(g_lastSl, _Digits), g_lastSl, clrRed);

   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
   {
      DrawHLine("TP3", g_lastTp3, clrLime, STYLE_DASH, 2);
      DrawTextLabel("TP3_TXT", "TP 1:" + DoubleToString(InpFixedRR, 1) + "R " + DoubleToString(g_lastTp3, _Digits), g_lastTp3, clrLime);
      ObjectDelete(0, PREFIX + "TP1");
      ObjectDelete(0, PREFIX + "TP2");
      ObjectDelete(0, PREFIX + "TP1_TXT");
      ObjectDelete(0, PREFIX + "TP2_TXT");
      return;
   }

   DrawHLine("TP1", g_lastTp1, clrLime, STYLE_DASH, 1);
   DrawHLine("TP2", g_lastTp2, clrLime, STYLE_DASH, 1);
   DrawHLine("TP3", g_lastTp3, clrLime, STYLE_DASH, 2);
   DrawTextLabel("TP1_TXT", "TP1 " + DoubleToString(g_lastTp1, _Digits), g_lastTp1, clrLime);
   DrawTextLabel("TP2_TXT", "TP2 " + DoubleToString(g_lastTp2, _Digits), g_lastTp2, clrLime);
   DrawTextLabel("TP3_TXT", "TP3 " + DoubleToString(g_lastTp3, _Digits), g_lastTp3, clrLime);
}

double UiClamp(const double v, const double lo, const double hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

int UiClampInt(const int v, const int lo, const int hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

string UiPctText(const double pct)
{
   return IntegerToString((int)MathRound(UiClamp(pct, 0.0, 100.0))) + "%";
}

string UiShort(const string text, const int maxLen)
{
   if(StringLen(text) <= maxLen)
      return text;
   return StringSubstr(text, 0, MathMax(0, maxLen - 3)) + "...";
}

double UiLivePrice(const int direction)
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
   {
      if(direction > 0 && tick.bid > 0.0)
         return tick.bid;
      if(direction < 0 && tick.ask > 0.0)
         return tick.ask;
      if(tick.last > 0.0)
         return tick.last;
   }
   return direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

void CreateRect(const string name, const int x, const int y, const int w, const int h, const color bg, const color border)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, (int)MathMax(1, w));
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, (int)MathMax(1, h));
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, border);
}

void CreateProgressBar(const string name,
                       const int x,
                       const int y,
                       const int w,
                       const int h,
                       const double pct,
                       const string text,
                       const color fill,
                       const color bg,
                       const color border)
{
   double clamped = UiClamp(pct, 0.0, 100.0);
   int fillW = UiClampInt((int)MathRound((double)w * clamped / 100.0), 1, w);
   CreateRect(name + "_BG", x, y, w, h, bg, border);
   CreateRect(name + "_FILL", x + 2, y + 2, MathMax(1, fillW - 4), MathMax(1, h - 4), fill, fill);
   CreateLabel(name + "_TXT", x + 10, y + 3, text, clrWhite, 8);
}

bool BuildNasVisualMetrics(NasVisualMetrics &m)
{
   m.ok = false;
   m.price = 0.0;
   m.superTrend = 0.0;
   m.sma13 = 0.0;
   m.buyPct = 0.0;
   m.sellPct = 0.0;
   m.buyArmed = false;
   m.sellArmed = false;
   m.status = "NAS SENSOR OFFLINE";

   MqlRates rates[];
   int bars = MathMax(300, MathMin(SignalBarsToCopy(), 800));
   int copied = LoadNasRates(rates, bars, true);
   if(copied < 20)
      return false;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   int i = copied - 1;
   int prev = i - 1;
   if(i <= 0 || !NAS_IsValid(p[i].superTrend) || !NAS_IsValid(p[i].sma13) || !NAS_IsValid(p[prev].superTrend))
      return false;

   double price = rates[i].close;
   double st = p[i].superTrend;
   double sma13 = p[i].sma13;
   double prevClose = rates[prev].close;
   double prevSt = p[prev].superTrend;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double barRange = MathMax(rates[i].high - rates[i].low, point * 250.0);
   double scale = MathMax(barRange, MathMax(MathAbs(price - st), MathAbs(price - sma13)));
   if(scale <= 0.0)
      scale = point > 0.0 ? point * 250.0 : 1.0;

   double buySt = price >= st ? 100.0 : 100.0 - ((st - price) / scale) * 100.0;
   double buySma = price >= sma13 ? 100.0 : 100.0 - ((sma13 - price) / scale) * 100.0;
   double sellSt = price <= st ? 100.0 : 100.0 - ((price - st) / scale) * 100.0;
   double sellSma = price <= sma13 ? 100.0 : 100.0 - ((price - sma13) / scale) * 100.0;

   m.buyArmed = prevClose <= prevSt;
   m.sellArmed = prevClose >= prevSt;
   m.buyPct = UiClamp((UiClamp(buySt, 0.0, 100.0) * 0.65) + (UiClamp(buySma, 0.0, 100.0) * 0.35), 0.0, 100.0);
   m.sellPct = UiClamp((UiClamp(sellSt, 0.0, 100.0) * 0.65) + (UiClamp(sellSma, 0.0, 100.0) * 0.35), 0.0, 100.0);

   if(!m.buyArmed && !p[i].buy)
      m.buyPct *= 0.55;
   if(!m.sellArmed && !p[i].sell)
      m.sellPct *= 0.55;

   if(p[i].buy)
      m.buyPct = 100.0;
   if(p[i].sell)
      m.sellPct = 100.0;

   m.ok = true;
   m.price = price;
   m.superTrend = st;
   m.sma13 = sma13;
   if(p[i].buy)
      m.status = "BUY IGNITION";
   else if(p[i].sell)
      m.status = "SELL IGNITION";
   else if(m.buyPct > m.sellPct)
      m.status = m.buyArmed ? "BUY VECTOR ARMED" : "BUY VECTOR WATCH";
   else
      m.status = m.sellArmed ? "SELL VECTOR ARMED" : "SELL VECTOR WATCH";
   return true;
}

bool GetNasVisualMetrics(NasVisualMetrics &m)
{
   uint nowMs = GetTickCount();
   if(g_visualMetricsCache.ok && (nowMs - g_visualMetricsCacheMs) < 250)
   {
      m = g_visualMetricsCache;
      return true;
   }

   bool ok = BuildNasVisualMetrics(m);
   if(ok)
   {
      g_visualMetricsCache = m;
      g_visualMetricsCacheMs = nowMs;
   }
   return ok;
}

bool BuildTradeProgress(double &pct, string &label, color &fill)
{
   pct = 0.0;
   label = "NO LIVE TRADE VECTOR";
   fill = C'66,155,255';

   double totalVolume = 0.0;
   double weightedEntry = 0.0;
   double openPnl = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   int direction = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      int posDir = type == POSITION_TYPE_BUY ? 1 : -1;
      if(direction == 0)
         direction = posDir;
      if(direction != posDir)
         continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSl = PositionGetDouble(POSITION_SL);
      double posTp = PositionGetDouble(POSITION_TP);
      totalVolume += vol;
      weightedEntry += entry * vol;
      openPnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(posSl > 0.0)
         sl = posSl;
      if(posTp > 0.0)
      {
         if(tp <= 0.0)
            tp = posTp;
         else if(direction > 0)
            tp = MathMax(tp, posTp);
         else
            tp = MathMin(tp, posTp);
      }
   }

   if(totalVolume <= 0.0 || direction == 0)
      return false;

   double entryAvg = weightedEntry / totalVolume;
   if(sl <= 0.0)
      sl = g_lastSl;
   if(tp <= 0.0)
      tp = g_lastTp3;
   double px = UiLivePrice(direction);
   if(px <= 0.0 || sl <= 0.0 || tp <= 0.0 || MathAbs(tp - sl) <= 0.0)
      return false;

   if(direction > 0)
      pct = ((px - sl) / (tp - sl)) * 100.0;
   else
      pct = ((sl - px) / (sl - tp)) * 100.0;
   pct = UiClamp(pct, 0.0, 100.0);

   string dirText = direction > 0 ? "BUY" : "SELL";
   fill = direction > 0 ? C'31,141,255' : C'225,49,76';
   label = "LIVE VECTOR " + dirText
           + " Px " + DoubleToString(px, _Digits)
           + " -> TP " + UiPctText(pct)
           + " | PnL " + DoubleToString(openPnl, 2)
           + " | Entry " + DoubleToString(entryAvg, _Digits);
   return true;
}

void CreateLabel(const string name, const int x, const int y, const string text, const color clr, const int size = 9)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void CreateEdit(const string name, const int x, const int y, const int w, const int h, const string text)
{
   string obj = PREFIX + name;
   bool created = false;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
      created = true;
   }
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   if(created)
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'35,43,58');
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C'90,178,255');
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void CreateButton(const string name, const int x, const int y, const int w, const int h, const string text, const color bg)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
}

void DeleteObjectIfExists(const string name)
{
   ObjectDelete(0, PREFIX + name);
}

void DeleteProgressBar(const string name)
{
   DeleteObjectIfExists(name + "_BG");
   DeleteObjectIfExists(name + "_FILL");
   DeleteObjectIfExists(name + "_TXT");
}

void ClearDashboardObjects()
{
   string names[] =
   {
      "DASH_BG", "DASH_HULL", "DASH_CORE", "DASH_ACTION_PANEL", "DASH_LOG_PANEL",
      "DASH_DOOR_L", "DASH_DOOR_R", "DASH_DOOR_TEXT",
      "DASH_DOCK_BG", "DASH_DOCK_STRIPE", "DASH_DOCK_TEXT", "DASH_DOCK_HINT",
      "DASH_COLLAPSED_HINT",
      "BTN_DASH_EXPAND", "BTN_DASH_COLLAPSE",
      "DASH_TITLE", "DASH_SUB", "DASH_1", "DASH_PRICE", "DASH_2", "DASH_3", "DASH_4", "DASH_5",
      "DASH_SENSOR", "DASH_SENSOR_HELP", "DASH_WIN", "DASH_WIN_STATE",
      "DASH_ACTIONS", "DASH_ACTION_HINT", "DASH_START_LBL", "DASH_END_LBL", "DASH_LOT_LBL",
      "DASH_SPREAD_MAX_LBL", "DASH_FINAL_SCALE_LBL", "DASH_CFG_NOTE", "DASH_H0", "DASH_H1", "DASH_H2", "DASH_H3",
      "BTN_CLOSE_ALL", "BTN_CLOSE_1_3", "BTN_BE", "BTN_APPLY_WINDOW", "BTN_EA_TOGGLE",
      "EDIT_START", "EDIT_END", "EDIT_LOT", "EDIT_SPREAD_MAX", "EDIT_FINAL_SCALE"
   };
   for(int i = 0; i < ArraySize(names); i++)
      DeleteObjectIfExists(names[i]);
   DeleteProgressBar("TRADE_VECTOR");
   DeleteProgressBar("BUY_FUEL");
   DeleteProgressBar("SELL_FUEL");
}

void DrawCollapsedDashboardToggle()
{
   CreateRect("DASH_DOCK_BG", 10, 18, 940, 34, C'54,62,75', C'134,158,182');
   CreateRect("DASH_DOCK_STRIPE", 18, 25, 924, 4, C'90,178,255', C'90,178,255');
   CreateLabel("DASH_DOCK_TEXT", 28, 33, "NAS STARSHIP COCKPIT DOCKED", C'216,222,230', 9);
   CreateButton("BTN_DASH_EXPAND", 438, 58, 110, 24, "v EXPAND", C'38,101,176');
   CreateLabel("DASH_DOCK_HINT", 560, 62, "chart view clear", C'184,196,210', 8);
}

void SetDashboardCollapsed(const bool collapsed)
{
   ClearDashboardObjects();
   if(collapsed)
   {
      g_dashboardCollapsed = true;
      g_dashboardOpening = false;
      g_dashboardDoorFinished = true;
      EventKillTimer();
      DrawCollapsedDashboardToggle();
   }
   else
   {
      g_dashboardCollapsed = false;
      g_dashboardOpening = true;
      g_dashboardDoorFinished = false;
      g_dashboardDoorStartMs = GetTickCount();
      DeleteObjectIfExists("BTN_DASH_EXPAND");
      DeleteObjectIfExists("DASH_DOCK_HINT");
      EventSetMillisecondTimer(35);
      DrawDashboard();
   }
   ChartRedraw(0);
}

void CreateButtons()
{
   CreateButton("BTN_DASH_COLLAPSE", 904, 30, 24, 22, "^", C'90,178,255');
   CreateButton("BTN_EA_TOGGLE", 684, 58, 244, 24,
                g_eaEnabledRuntime ? "EA ON - CLICK TO KILL" : "EA OFF - CLICK TO ARM",
                g_eaEnabledRuntime ? C'30,150,95' : C'178,37,57');
   CreateButton("BTN_CLOSE_ALL", 684, 82, 118, 25, "CLOSE ALL", C'178,37,57');
   CreateButton("BTN_CLOSE_1_3", 810, 82, 118, 25,
                InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? "CLOSE ONE" : "CLOSE 1/3",
                C'38,101,176');
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
      CreateButton("BTN_BE", 684, 112, 118, 25, "SL -> BE", C'34,136,160');
   CreateButton("BTN_APPLY_WINDOW", 836, 190, 92, 24, "APPLY", C'38,101,176');
}

bool ApplyTradingWindowFromDashboard(const string source)
{
   string startObj = PREFIX + "EDIT_START";
   string endObj = PREFIX + "EDIT_END";
   if(ObjectFind(0, startObj) < 0 || ObjectFind(0, endObj) < 0)
   {
      Print("NAS SATS EA trading window apply failed missing edit objects source=", source);
      return false;
   }

   string startText = ObjectGetString(0, startObj, OBJPROP_TEXT);
   string endText = ObjectGetString(0, endObj, OBJPROP_TEXT);
   StringTrimLeft(startText);
   StringTrimRight(startText);
   StringTrimLeft(endText);
   StringTrimRight(endText);

   int startMin = ParseClockMinutes(startText, -1);
   int endMin = ParseClockMinutes(endText, -1);
   if(startMin < 0 || endMin < 0)
   {
      Print("NAS SATS EA trading window apply failed invalid time source=", source,
            " start=", startText,
            " end=", endText);
      return false;
   }

   g_tradeStartTimeRuntime = startText;
   g_tradeEndTimeRuntime = endText;
   ObjectSetString(0, startObj, OBJPROP_TEXT, g_tradeStartTimeRuntime);
   ObjectSetString(0, endObj, OBJPROP_TEXT, g_tradeEndTimeRuntime);
   Print("NAS SATS EA trading window updated source=", source,
         " start=", g_tradeStartTimeRuntime,
         " end=", g_tradeEndTimeRuntime,
         " state=", TradingTimeStateText());
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplyLotFromDashboard(const string source)
{
   string lotObj = PREFIX + "EDIT_LOT";
   if(ObjectFind(0, lotObj) < 0)
   {
      Print("NAS SATS EA lot apply failed missing edit object source=", source);
      return false;
   }

   string lotText = ObjectGetString(0, lotObj, OBJPROP_TEXT);
   StringTrimLeft(lotText);
   StringTrimRight(lotText);
   double requested = StringToDouble(lotText);
   if(requested <= 0.0)
   {
      Print("NAS SATS EA lot apply failed invalid lot source=", source, " lot=", lotText);
      return false;
   }

   double normalized = NormalizeVolume(requested);
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      g_fixedLotRuntime = normalized;
   else
      g_totalLotRuntime = normalized;

   ObjectSetString(0, lotObj, OBJPROP_TEXT, DoubleToString(normalized, 2));
   Print("NAS SATS EA lot updated source=", source,
         " mode=", EnumToString(InpExecutionMode),
         " lot=", DoubleToString(normalized, 8));
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplySpreadMaxFromDashboard(const string source)
{
   string spreadObj = PREFIX + "EDIT_SPREAD_MAX";
   if(ObjectFind(0, spreadObj) < 0)
   {
      Print("NAS SATS EA spread max apply failed missing edit object source=", source);
      return false;
   }

   string spreadText = ObjectGetString(0, spreadObj, OBJPROP_TEXT);
   StringTrimLeft(spreadText);
   StringTrimRight(spreadText);
   double requested = StringToDouble(spreadText);
   if(requested < 0.0)
   {
      Print("NAS SATS EA spread max apply failed invalid value source=", source, " max_spread_pts=", spreadText);
      return false;
   }

   g_spreadMaxPointsRuntime = requested;
   ObjectSetString(0, spreadObj, OBJPROP_TEXT, DoubleToString(g_spreadMaxPointsRuntime, 0));
   Print("NAS SATS EA spread max updated source=", source,
         " max_spread_pts=", DoubleToString(g_spreadMaxPointsRuntime, 1),
         " note=", (g_spreadMaxPointsRuntime > 0.0 ? "manual_wide_threshold" : "spread_blocking_off"));
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplyFinalRiskScaleFromDashboard(const string source)
{
   string scaleObj = PREFIX + "EDIT_FINAL_SCALE";
   if(ObjectFind(0, scaleObj) < 0)
   {
      Print("NAS SATS EA final risk scale apply failed missing edit object source=", source);
      return false;
   }

   string scaleText = ObjectGetString(0, scaleObj, OBJPROP_TEXT);
   StringTrimLeft(scaleText);
   StringTrimRight(scaleText);
   double requested = StringToDouble(scaleText);
   if(requested <= 0.0)
   {
      Print("NAS SATS EA final risk scale apply failed invalid value source=", source, " scale_pct=", scaleText);
      return false;
   }

   g_finalRiskScalePctRuntime = MathMax(10.0, MathMin(200.0, requested));
   ObjectSetString(0, scaleObj, OBJPROP_TEXT, DoubleToString(g_finalRiskScalePctRuntime, 0));
   Print("NAS SATS EA final risk scale updated source=", source,
         " final_scale_pct=", DoubleToString(g_finalRiskScalePctRuntime, 2),
         " note=100_keeps_raw_sl_75_trims_distance_by_25pct");
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

void ApplyDashboardSettings(const string source)
{
   ApplyTradingWindowFromDashboard(source);
   ApplyLotFromDashboard(source);
   ApplySpreadMaxFromDashboard(source);
   ApplyFinalRiskScaleFromDashboard(source);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT)
      return;

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == PREFIX + "EDIT_START" || sparam == PREFIX + "EDIT_END")
         ApplyTradingWindowFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_LOT")
         ApplyLotFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_SPREAD_MAX")
         ApplySpreadMaxFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_FINAL_SCALE")
         ApplyFinalRiskScaleFromDashboard("edit_end");
      return;
   }

   if(sparam == PREFIX + "BTN_DASH_COLLAPSE")
      SetDashboardCollapsed(true);
   else if(sparam == PREFIX + "BTN_DASH_EXPAND")
      SetDashboardCollapsed(false);
   else if(sparam == PREFIX + "BTN_EA_TOGGLE")
   {
      g_eaEnabledRuntime = !g_eaEnabledRuntime;
      g_lastExecutionStatus = g_eaEnabledRuntime ? "READY" : "BLOCKED";
      g_lastExecutionBlockReason = g_eaEnabledRuntime ? "" : "global_ea_kill_switch_off";
      Print("NAS SATS EA global kill switch toggled state=", (g_eaEnabledRuntime ? "ON" : "OFF"));
      UpdateDashboard();
      ChartRedraw(0);
   }
   else if(sparam == PREFIX + "BTN_CLOSE_ALL")
      CloseManagedPositions();
   else if(sparam == PREFIX + "BTN_BE")
      MoveRemainingToBE();
   else if(sparam == PREFIX + "BTN_CLOSE_1_3")
      CloseOneLeg();
   else if(sparam == PREFIX + "BTN_APPLY_WINDOW")
      ApplyDashboardSettings("apply_button");
}

void DrawDashboard()
{
   if(!InpShowDashboard)
      return;
   if(g_dashboardCollapsed)
   {
      DrawCollapsedDashboardToggle();
      return;
   }
   if(!g_dashboardOpening && !g_dashboardDoorFinished)
   {
      g_dashboardOpening = true;
      g_dashboardDoorStartMs = GetTickCount();
      EventSetMillisecondTimer(35);
   }
   UpdateDashboard();
}

void DrawDashboardShell(const int height)
{
   int h = UiClampInt(height, 34, 430);
   CreateRect("DASH_BG", 10, 18, 940, h, C'24,30,42', C'134,158,182');
   CreateRect("DASH_HULL", 17, 25, 926, MathMax(22, h - 14), C'40,48,62', C'90,178,255');
   CreateRect("DASH_DOCK_STRIPE", 18, 31, 924, 4, C'90,178,255', C'90,178,255');
   if(h >= 98)
      CreateRect("DASH_CORE", 26, 56, 640, MathMax(20, h - 80), C'18,24,36', C'65,116,172');
   if(h >= 224)
      CreateRect("DASH_ACTION_PANEL", 676, 56, 252, 168, C'31,38,52', C'221,55,78');
   if(h >= 350)
      CreateRect("DASH_LOG_PANEL", 676, 236, 252, 180, C'31,38,52', C'90,178,255');
}

void UpdateDoorAnimation()
{
   if(g_dashboardCollapsed || g_dashboardDoorFinished || g_dashboardDoorStartMs == 0)
      return;

   uint elapsedMs = GetTickCount() - g_dashboardDoorStartMs;
   double open = UiClamp((double)elapsedMs / 700.0, 0.0, 1.0);
   double eased = 1.0 - MathPow(1.0 - open, 3.0);
   int h = 34 + (int)MathRound(396.0 * eased);
   DrawDashboardShell(h);
   CreateLabel("DASH_DOOR_TEXT", 398, 38 + h / 2, "COCKPIT DEPLOY " + UiPctText(open * 100.0), C'216,222,230', 9);

   if(open >= 1.0)
   {
      ObjectDelete(0, PREFIX + "DASH_DOOR_TEXT");
      g_dashboardDoorFinished = true;
      g_dashboardOpening = false;
      EventKillTimer();
      return;
   }
}

void UpdateDashboard()
{
   if(g_dashboardCollapsed)
      return;

   if(!g_dashboardDoorFinished)
   {
      UpdateDoorAnimation();
      if(!g_dashboardDoorFinished)
      {
         ChartRedraw(0);
         return;
      }
   }

   DrawDashboardShell(430);
   CreateButtons();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equityPeak <= 0.0 || equity > g_equityPeak)
      g_equityPeak = equity;
   double dd = g_equityPeak - equity;
   if(dd > g_maxDd)
      g_maxDd = dd;

   double totalPnl = HistoryPnl(0);
   double dailyPnl = HistoryPnl(DayStart());
   double openPnl = ManagedOpenPnl();

   string modeText = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R
                     ? "FIXED 1:" + DoubleToString(InpFixedRR, 1) + "R"
                     : (InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL ? "ORIGINAL PARTIAL BE" : "PARTIAL NO-BE");
   color titleColor = C'108,202,255';
   color accentBlue = C'90,178,255';
   color accentRed = C'221,55,78';
   color muted = C'184,196,210';
   color steel = C'216,222,230';
   double bid = 0.0;
   double ask = 0.0;
   double spreadPts = 0.0;
   double spreadGood = 0.0;
   double spreadNormal = 0.0;
   double spreadWide = 0.0;
   string spreadStatus = "";
   color spreadColor = C'184,196,210';
   bool spreadAllowed = SpreadSnapshot(bid, ask, spreadPts, spreadStatus, spreadColor, spreadGood, spreadNormal, spreadWide);
   g_lastSpreadPoints = spreadPts;
   g_lastSpreadStatus = spreadStatus;

   CreateLabel("DASH_TITLE", 34, 32, "AI STARSHIP NAS COCKPIT", steel, 12);
   CreateLabel("DASH_SUB", 356, 34, "AUTOPILOT " + modeText, titleColor, 9);
   CreateLabel("DASH_1", 38, 66, "Bridge: " + _Symbol + " " + EnumToString(_Period) + " | Magic " + IntegerToString(RuntimeMagic()), clrWhite);
   CreateLabel("DASH_PRICE", 38, 86, "Live price  BID " + DoubleToString(bid, _Digits) + " / ASK " + DoubleToString(ask, _Digits), titleColor);
   CreateLabel("DASH_SPREAD", 38, 106,
               "Live spread " + DoubleToString(spreadPts, 0) + " pt | " + spreadStatus
               + " | G/N/W " + DoubleToString(spreadGood, 0) + "/"
               + DoubleToString(spreadNormal, 0) + "/" + DoubleToString(spreadWide, 0)
               + (g_spreadMaxPointsRuntime > 0.0 ? " | max " + DoubleToString(g_spreadMaxPointsRuntime, 0) : " | max OFF")
               + (InpSpreadGovernorEnabled ? "" : " | governor OFF"),
               InpSpreadGovernorEnabled ? spreadColor : muted, 8);
   CreateLabel("DASH_STATUS", 38, 126,
               "EA " + string(g_eaEnabledRuntime ? "ON" : "OFF") + " | Trade status " + g_lastExecutionStatus
               + (g_lastExecutionBlockReason == "" ? "" : " | " + UiShort(g_lastExecutionBlockReason, 58)),
               (!g_eaEnabledRuntime || g_lastExecutionStatus == "BLOCKED" ? accentRed : (spreadAllowed ? C'80,255,180' : accentRed)), 8);
   CreateLabel("DASH_2", 38, 146, "Total PnL " + DoubleToString(totalPnl, 2) + "   Daily " + DoubleToString(dailyPnl, 2)
               + "   Open " + DoubleToString(openPnl, 2) + "   Max DD " + DoubleToString(g_maxDd, 2), muted);
   string dir = g_lastDirection > 0 ? "BUY" : (g_lastDirection < 0 ? "SELL" : "-");
   CreateLabel("DASH_4", 38, 166, "Last NAS " + dir + " | entry " + DoubleToString(g_lastEntry, _Digits)
               + " | SL " + DoubleToString(g_lastSl, _Digits)
               + " | TP3 " + DoubleToString(g_lastTp3, _Digits), clrWhite);
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      CreateLabel("DASH_5", 38, 181, "FTMO risk " + string(InpAdvancedAccountRiskEnabled ? "ON" : "OFF")
                  + " | lot " + string(InpAdvancedLotEngineEnabled && InpAdvancedAccountRiskEnabled ? "AUTO" : "MANUAL")
                  + " | last lot=" + DoubleToString(g_lastAdvancedLot, 2)
                  + " | risk " + DoubleToString(InpAccountRiskPerTradePct, 2) + "%"
                  + " | TP=" + DoubleToString(InpFixedRR, 1) + "R", accentBlue);
   else if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
      CreateLabel("DASH_5", 38, 181, "FTMO risk " + string(InpAdvancedAccountRiskEnabled ? "ON" : "OFF")
                  + " | last total=" + DoubleToString(g_lastAdvancedLot, 2)
                  + " | portfolio " + DoubleToString(InpAccountRiskMaxPortfolioPct, 2) + "% | TP1 => SL->BE", accentBlue);
   else
      CreateLabel("DASH_5", 38, 181, "FTMO risk " + string(InpAdvancedAccountRiskEnabled ? "ON" : "OFF")
                  + " | last total=" + DoubleToString(g_lastAdvancedLot, 2)
                  + " | portfolio " + DoubleToString(InpAccountRiskMaxPortfolioPct, 2) + "% | SL->BE OFF", accentBlue);

   double tradePct = 0.0;
   string tradeLabel = "";
   color tradeFill = accentBlue;
   if(BuildTradeProgress(tradePct, tradeLabel, tradeFill))
      CreateProgressBar("TRADE_VECTOR", 38, 193, 590, 24, tradePct, tradeLabel, tradeFill, C'42,51,68', C'134,158,182');
   else
      CreateProgressBar("TRADE_VECTOR", 38, 193, 590, 24, 0.0, "LIVE VECTOR STANDBY | no managed position", C'88,96,112', C'42,51,68', C'134,158,182');

   NasVisualMetrics visual;
   if(GetNasVisualMetrics(visual))
   {
      CreateLabel("DASH_SENSOR", 38, 226, "NAS SENSOR " + visual.status
                  + " | ST " + DoubleToString(visual.superTrend, _Digits)
                  + " | SMA13 " + DoubleToString(visual.sma13, _Digits), steel, 8);
      CreateLabel("DASH_SENSOR_HELP", 38, 246, "Fuel = live close proximity to SuperTrend cross + SMA13 filter; visual only, no trade logic mutation.", muted, 7);
      CreateProgressBar("BUY_FUEL", 38, 268, 285, 24, visual.buyPct,
                        "BUY ROCKET FUEL " + UiPctText(visual.buyPct), C'31,141,255', C'35,43,58', C'90,178,255');
      CreateProgressBar("SELL_FUEL", 343, 268, 285, 24, visual.sellPct,
                        "SELL ROCKET FUEL " + UiPctText(visual.sellPct), C'221,55,78', C'35,43,58', C'221,55,78');
   }
   else
   {
      CreateLabel("DASH_SENSOR", 38, 226, "NAS SENSOR awaiting enough live bars", accentRed, 8);
      CreateLabel("DASH_SENSOR_HELP", 38, 246, "Fuel = live close proximity to SuperTrend cross + SMA13 filter; visual only, no trade logic mutation.", muted, 7);
      CreateProgressBar("BUY_FUEL", 38, 268, 285, 24, 0.0, "BUY ROCKET FUEL --", C'31,141,255', C'35,43,58', C'90,178,255');
      CreateProgressBar("SELL_FUEL", 343, 268, 285, 24, 0.0, "SELL ROCKET FUEL --", C'221,55,78', C'35,43,58', C'221,55,78');
   }

   CreateLabel("DASH_WIN", 38, 315, "Trading window", titleColor, 9);
   CreateLabel("DASH_WIN_STATE", 38, 339, TradingTimeStateText(), IsTradingTimeOpen() ? C'80,255,180' : C'255,95,140', 8);
   CreateLabel("DASH_ACTIONS", 696, 34, "AIRLOCK / CONFIG", steel, 9);
   CreateLabel("DASH_ACTION_HINT", 684, 116, "Manual controls", muted, 7);
   CreateLabel("DASH_START_LBL", 684, 146, "Start", muted, 8);
   CreateLabel("DASH_END_LBL", 760, 146, "End", muted, 8);
   CreateLabel("DASH_LOT_LBL", 836, 146, InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? "Fixed lot" : "Total lot", muted, 8);
   CreateEdit("EDIT_START", 684, 164, 68, 22, g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime);
   CreateEdit("EDIT_END", 760, 164, 68, 22, g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime);
   double shownLot = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? FixedVolume() : (g_totalLotRuntime > 0.0 ? g_totalLotRuntime : InpTotalLot);
   CreateEdit("EDIT_LOT", 836, 164, 68, 22, DoubleToString(shownLot, 2));
   CreateLabel("DASH_SPREAD_MAX_LBL", 684, 194, "MaxSpr", muted, 8);
   CreateEdit("EDIT_SPREAD_MAX", 760, 190, 68, 22, DoubleToString(g_spreadMaxPointsRuntime, 0));
   CreateLabel("DASH_FINAL_SCALE_LBL", 836, 194, "SL %", muted, 8);
   CreateEdit("EDIT_FINAL_SCALE", 884, 190, 44, 22, DoubleToString(g_finalRiskScalePctRuntime, 0));
   CreateLabel("DASH_CFG_NOTE", 684, 220, "MaxSpr 0=OFF | SL%: 100 raw, 75 trims distance by 25%", muted, 7);

   CreateLabel("DASH_H0", 690, 250, "Recent NAS signals", titleColor, 8);
   CreateLabel("DASH_H1", 690, 276, UiShort(g_historySummary[0], 35), muted, 7);
   CreateLabel("DASH_H2", 690, 303, UiShort(g_historySummary[1], 35), muted, 7);
   CreateLabel("DASH_H3", 690, 330, UiShort(g_historySummary[2], 35), muted, 7);
   UpdateDoorAnimation();
}
