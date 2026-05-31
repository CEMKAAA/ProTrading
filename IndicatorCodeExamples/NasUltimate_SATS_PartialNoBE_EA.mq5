//+------------------------------------------------------------------+
//| NAS Ultimate Algo EA with SATS risk engine                       |
//| Partial TP variant: TP legs remain, no automatic SL -> BE.       |
//| Signal source: IndicatorCodeExamples/NasIndicator.pine           |
//| Risk source: SuperTrend_SATS_EA TP/SL logic                      |
//+------------------------------------------------------------------+
#property strict
#property version "1.06"

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
input double InpPineRiskDistanceMultiplier = 1.0;
input NAS_SIGNAL_BAR_MODE InpSignalBarMode = NAS_SIGNAL_BAR_CLOSED;
input NAS_RISK_ENGINE InpRiskEngine = NAS_RISK_PINE;
input bool   InpBlockSameDirectionUntilReverse = true;
input bool   InpUseTradingTimeWindow = true;
input string InpTradeStartTime = "09:00";
input string InpTradeEndTime = "14:00";

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

string PREFIX = "NAS_SATS_NO_BE_EA_";

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
   if(!InpUseTradingTimeWindow)
      return true;
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
   if(!InpUseTradingTimeWindow)
      return "OFF";
   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   return string(IsTradingTimeOpen() ? "OPEN " : "CLOSED ")
          + startText + "-" + endText
          + " server=" + TimeToString(TimeCurrent(), TIME_MINUTES);
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
   g_tradeStartTimeRuntime = InpTradeStartTime;
   g_tradeEndTimeRuntime = InpTradeEndTime;
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   HydrateExecutedDirectionFromOpenPosition();
   PrintStartupDiagnostics();
   BaselineStartupSignal();
   DrawDashboard();
   CreateButtons();
   if(InpDrawLastSignalsOnStart)
   {
      DrawRecentSignalHistory();
      UpdateDashboard();
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
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
         " base_magic=", InpMagic,
         " runtime_magic=", RuntimeMagic(),
         " chart_id=", (long)ChartID(),
         " execution_mode=", EnumToString(InpExecutionMode),
         " nas_sensitivity=", InpNasSensitivity,
         " nas_atr_risk=", InpNasAtrRisk,
         " nas_atr_len=", InpNasAtrLen,
         " pine_risk_distance_multiplier=", DoubleToString(InpPineRiskDistanceMultiplier, 2),
         " signal_bar_mode=", EnumToString(InpSignalBarMode),
         " block_same_direction_until_reverse=", InpBlockSameDirectionUntilReverse,
         " risk_engine=", EnumToString(InpRiskEngine),
         " risk_preset=", EnumToString(InpRiskPreset),
         " risk_source=", EnumToString(InpRiskSource),
         " history_bars=", InpHistoryBars,
         " signal_calc_bars=", SignalBarsToCopy(),
         " total_lot=", DoubleToString(InpTotalLot, 8),
         " fixed_lot=", DoubleToString(InpFixedLot, 8),
         " fixed_rr=", DoubleToString(InpFixedRR, 2),
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
      return true;
   }

   return SATS_CalculateRiskLevelsAtSignal(rates, copied, BuildRiskSettings(), signalIndex, direction,
                                           entry, sl, tp1, tp2, tp3, effAtr);
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
         g_lastExecutedDirection = 0;
         Print("NAS SATS EA reverse signal closed existing position outside trading window dir=",
               (direction > 0 ? "BUY" : "SELL"),
               " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
               " trading_window=", TradingTimeStateText(),
               " no_new_entry=true");
      }
      else
      {
         Print("NAS SATS EA signal ignored outside trading window dir=",
               (direction > 0 ? "BUY" : "SELL"),
               " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
               " trading_window=", TradingTimeStateText(),
               " audit=window_before_same_direction_guard");
      }
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      return;
   }

   if(InpBlockSameDirectionUntilReverse && direction == g_lastExecutedDirection)
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      Print("NAS SATS EA same-direction signal ignored dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]),
            " reason=already_executed_direction_waiting_for_opposite");
      return;
   }

   double effAtr = 0.0;
   if(!CalculateRisk(rates, copied, i, direction, p[i], g_lastEntry, g_lastSl, g_lastTp1, g_lastTp2, g_lastTp3, effAtr))
   {
      Print("NAS SATS EA risk calculation failed signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " direction=", (direction > 0 ? "BUY" : "SELL"));
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
      if(g_lastExecutedDirection == g_liveSignalDirection)
         g_lastExecutedDirection = 0;
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
   return NormalizeVolume(MathFloor((InpTotalLot / 3.0) / step) * step);
}

double FixedVolume()
{
   return NormalizeVolume(InpFixedLot);
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

void ManageOpenPositions()
{
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
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'18,23,54');
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C'111,84,255');
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

void CreateButtons()
{
   CreateButton("BTN_CLOSE_ALL", 500, 58, 110, 24, "CLOSE ALL", C'109,30,95');
   CreateButton("BTN_CLOSE_1_3", 500, 88, 110, 24,
                InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? "CLOSE ONE" : "CLOSE 1/3",
                C'38,65,145');
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
      CreateButton("BTN_BE", 500, 118, 110, 24, "SL -> BE", C'40,116,145');
   CreateButton("BTN_APPLY_WINDOW", 406, 176, 72, 22, "APPLY", C'92,67,220');
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

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT)
      return;

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == PREFIX + "EDIT_START" || sparam == PREFIX + "EDIT_END")
         ApplyTradingWindowFromDashboard("edit_end");
      return;
   }

   if(sparam == PREFIX + "BTN_CLOSE_ALL")
      CloseManagedPositions();
   else if(sparam == PREFIX + "BTN_BE")
      MoveRemainingToBE();
   else if(sparam == PREFIX + "BTN_CLOSE_1_3")
      CloseOneLeg();
   else if(sparam == PREFIX + "BTN_APPLY_WINDOW")
      ApplyTradingWindowFromDashboard("apply_button");
}

void DrawDashboard()
{
   if(!InpShowDashboard)
      return;
   string bg = PREFIX + "DASH_BG";
   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 18);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 620);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 285);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'13,16,42');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'111,84,255');
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'111,84,255');
   UpdateDashboard();
}

void UpdateDashboard()
{
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
                     ? "FIXED 1:3R"
                     : (InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL ? "ORIGINAL PARTIAL BE" : "PARTIAL NO-BE");
   color titleColor = C'99,219,255';
   color accent = C'186,148,255';
   color muted = C'172,183,226';
   CreateLabel("DASH_TITLE", 24, 30, "NAS + SATS " + modeText + " DESK", titleColor, 11);
   CreateLabel("DASH_1", 24, 54, "Symbol/TF: " + _Symbol + " " + EnumToString(_Period), clrWhite);
   CreateLabel("DASH_2", 24, 74, "Total PnL: " + DoubleToString(totalPnl, 2) + "   Daily: " + DoubleToString(dailyPnl, 2), muted);
   CreateLabel("DASH_3", 24, 94, "Open PnL: " + DoubleToString(openPnl, 2) + "   Max DD: " + DoubleToString(g_maxDd, 2), muted);
   string dir = g_lastDirection > 0 ? "BUY" : (g_lastDirection < 0 ? "SELL" : "-");
   CreateLabel("DASH_4", 24, 114, "Last NAS: " + dir + " entry=" + DoubleToString(g_lastEntry, _Digits), clrWhite);
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      CreateLabel("DASH_5", 24, 134, "Risk: SATS SL | fixed lot=" + DoubleToString(FixedVolume(), 2)
                  + " | TP=" + DoubleToString(InpFixedRR, 1) + "R | reverse closes", accent);
   else if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
      CreateLabel("DASH_5", 24, 134, "Risk: SATS TP/SL | partial TP ON | TP1 => SL->BE", accent);
   else
      CreateLabel("DASH_5", 24, 134, "Risk: SATS TP/SL | partial TP ON | SL->BE OFF", accent);

   CreateLabel("DASH_WIN", 24, 158, "Trading window", titleColor, 9);
   CreateLabel("DASH_WIN_STATE", 24, 180, TradingTimeStateText(), IsTradingTimeOpen() ? C'80,255,180' : C'255,95,140', 8);
   CreateLabel("DASH_START_LBL", 250, 158, "Start", muted, 8);
   CreateLabel("DASH_END_LBL", 330, 158, "End", muted, 8);
   CreateEdit("EDIT_START", 248, 176, 64, 22, g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime);
   CreateEdit("EDIT_END", 328, 176, 64, 22, g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime);
   CreateLabel("DASH_ACTIONS", 500, 36, "Actions", titleColor, 9);

   CreateLabel("DASH_H0", 24, 212, "Recent NAS signals:", titleColor);
   CreateLabel("DASH_H1", 24, 228, g_historySummary[0], muted, 8);
   CreateLabel("DASH_H2", 24, 244, g_historySummary[1], muted, 8);
   CreateLabel("DASH_H3", 24, 260, g_historySummary[2], muted, 8);
}
