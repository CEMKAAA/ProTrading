//+------------------------------------------------------------------+
//| NAS Ultimate Algo EA with SATS risk engine                       |
//| Partial TP variant: TP legs remain, no automatic SL -> BE.       |
//| Signal source: IndicatorCodeExamples/NasIndicator.pine           |
//| Risk source: SuperTrend_SATS_EA TP/SL logic                      |
//+------------------------------------------------------------------+
#property strict
#property version "1.10"

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
input int    InpDeviationPoints = 30;
input bool   InpEnforceTpTouchClose = true; // Safety watchdog: close managed positions if live price touches broker TP.
input double InpTpTouchCloseTolerancePoints = 2.0;
input int    InpTpTouchWatchdogTimerMs = 100;
input int    InpTpTouchCloseRetryCount = 2;
input long   InpMagic = 27052712;
input int    InpHistoryBars = 20000;
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
   g_runtimeMagic = InpMagic * 1000000 + chartPart;
   return g_runtimeMagic;
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
      if((long)PositionGetInteger(POSITION_MAGIC) != RuntimeMagic())
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
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_tradeStartTimeRuntime = InpTradeStartTime;
   g_tradeEndTimeRuntime = InpTradeEndTime;
   g_totalLotRuntime = InpTotalLot;
   g_fixedLotRuntime = InpFixedLot;
   g_spreadMaxPointsRuntime = MathMax(0.0, InpSpreadWidePoints);
   g_eaEnabledRuntime = InpEaEnabled;
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
   EnforceManagedTpTouchClose(false);
   if(!g_dashboardDoorFinished)
      UpdateDashboard();
}

void OnTick()
{
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
         " widen_wide_pct=", DoubleToString(InpSlWidenWidePct, 1));
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
      return true;
   }

   bool calculated = SATS_CalculateRiskLevelsAtSignal(rates, copied, BuildRiskSettings(), signalIndex, direction,
                                                      entry, sl, tp1, tp2, tp3, effAtr);
   if(!calculated)
      return false;
   ApplyStructuralSwingStop(rates, copied, signalIndex, direction, entry, sl, tp1, tp2, tp3);
   ApplyAdaptiveSlWiden(direction, entry, sl, tp1, tp2, tp3);
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
      g_lastExecutionBlockReason = "broker_order_open_failed";
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

   double leg = LegVolume();
   if(leg <= 0.0)
   {
      Print("NAS SATS Partial-NoBE EA: invalid leg volume from total lot ", InpTotalLot);
      return false;
   }

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
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
   bool anyOpened = false;

   for(int i = 0; i < 3; i++)
   {
      bool ok = trade.PositionOpen(_Symbol, type, leg, price, g_lastSl, tps[i], comments[i]);
      if(!ok)
         Print("NAS SATS Partial-NoBE EA open failed leg=", i + 1, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      else
         anyOpened = true;
   }
   return anyOpened;
}

bool OpenFixedOneToThreeR(const int direction)
{
   double lot = FixedVolume();
   if(lot <= 0.0)
   {
      Print("NAS SATS Fixed 1:3R EA: invalid fixed lot ", InpFixedLot);
      return false;
   }

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string comment = direction > 0 ? "NAS_FIXED_3R_BUY" : "NAS_FIXED_3R_SELL";
   bool ok = trade.PositionOpen(_Symbol, type, lot, price, g_lastSl, g_lastTp3, comment);
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
   return (long)PositionGetInteger(POSITION_MAGIC) == RuntimeMagic();
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
      if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != RuntimeMagic())
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
      "DASH_SPREAD_MAX_LBL", "DASH_CFG_NOTE", "DASH_H0", "DASH_H1", "DASH_H2", "DASH_H3",
      "BTN_CLOSE_ALL", "BTN_CLOSE_1_3", "BTN_BE", "BTN_APPLY_WINDOW", "BTN_EA_TOGGLE",
      "EDIT_START", "EDIT_END", "EDIT_LOT", "EDIT_SPREAD_MAX"
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

void ApplyDashboardSettings(const string source)
{
   ApplyTradingWindowFromDashboard(source);
   ApplyLotFromDashboard(source);
   ApplySpreadMaxFromDashboard(source);
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
      CreateLabel("DASH_5", 38, 181, "Risk: SATS SL | fixed lot=" + DoubleToString(FixedVolume(), 2)
                  + " | TP=" + DoubleToString(InpFixedRR, 1) + "R | reverse closes", accentBlue);
   else if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
      CreateLabel("DASH_5", 38, 181, "Risk: SATS TP/SL | partial TP ON | TP1 => SL->BE", accentBlue);
   else
      CreateLabel("DASH_5", 38, 181, "Risk: SATS TP/SL | partial TP ON | SL->BE OFF", accentBlue);

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
   CreateLabel("DASH_CFG_NOTE", 684, 220, "MaxSpr 0=OFF | G/N/W Good/Normal/Wide; >0 blocks above max", muted, 7);

   CreateLabel("DASH_H0", 690, 250, "Recent NAS signals", titleColor, 8);
   CreateLabel("DASH_H1", 690, 276, UiShort(g_historySummary[0], 35), muted, 7);
   CreateLabel("DASH_H2", 690, 303, UiShort(g_historySummary[1], 35), muted, 7);
   CreateLabel("DASH_H3", 690, 330, UiShort(g_historySummary[2], 35), muted, 7);
   UpdateDoorAnimation();
}