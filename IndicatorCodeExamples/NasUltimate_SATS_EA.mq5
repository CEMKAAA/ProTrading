//+------------------------------------------------------------------+
//| NAS Ultimate Algo EA with SATS risk engine                       |
//| Signal source: IndicatorCodeExamples/NasIndicator.pine           |
//| Risk source: SuperTrend_SATS_EA TP/SL logic                      |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

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

input int    InpNasSensitivity = 4;
input int    InpNasRsiLength = 14;
input int    InpNasAtrRisk = 1;
input int    InpNasAtrLen = 14;
input NAS_SIGNAL_BAR_MODE InpSignalBarMode = NAS_SIGNAL_BAR_LIVE;
input NAS_RISK_ENGINE InpRiskEngine = NAS_RISK_PINE;

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
input int    InpDeviationPoints = 30;
input long   InpMagic = 27052711;
input int    InpHistoryBars = 20000;
input int    InpSignalCalcBars = 5000;
input bool   InpCloseExistingOnNewSignal = true;
input bool   InpDrawTradeLevels = true;
input bool   InpDrawExecutionArrows = true;
input bool   InpTradeLatestSignalOnAttach = false;
input bool   InpDrawLastSignalsOnStart = true;
input int    InpStartupSignalCount = 3;
input bool   InpShowDashboard = true;
input bool   InpUseHtfRegimeFilter = false;
input ENUM_TIMEFRAMES InpHtfRegimeTimeframe = PERIOD_H4;
input int    InpHtfRegimeSmaLen = 200;
input bool   InpUseHtfTrendFilter = false;
input ENUM_TIMEFRAMES InpHtfTrendTimeframe = PERIOD_H1;
input int    InpHtfTrendFastLen = 50;
input int    InpHtfTrendSlowLen = 200;
input bool   InpBlockSameDirectionUntilOpposite = false;

CTrade trade;
datetime g_lastBarTime = 0;
datetime g_lastSignalTime = 0;
int      g_lastSignalKeyDirection = 0;
datetime g_processedBuySignalBarTime = 0;
datetime g_processedSellSignalBarTime = 0;
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
int      g_auditWindowDays = 14;
int      g_historyDrawnCount = 0;
int      g_lastAcceptedDirection = 0;
bool     g_useHtfRegimeFilter = false;
ENUM_TIMEFRAMES g_htfRegimeTimeframe = PERIOD_H4;
int      g_htfRegimeSmaLen = 200;
bool     g_useHtfTrendFilter = false;
ENUM_TIMEFRAMES g_htfTrendTimeframe = PERIOD_H1;
int      g_htfTrendFastLen = 50;
int      g_htfTrendSlowLen = 200;
bool     g_blockSameDirectionUntilOpposite = false;

string PREFIX = "NAS_SATS_EA_";

int SignalBarsToCopy()
{
   return MathMax(InpSignalCalcBars, 300);
}

int AuditWindowBars()
{
   int sec = PeriodSeconds(_Period);
   if(sec <= 0)
      sec = 60;
   long estimated = ((long)g_auditWindowDays * 86400L) / sec + 300L;
   if(estimated < 500L)
      estimated = 500L;
   if(estimated > 250000L)
      estimated = 250000L;
   return (int)estimated;
}

datetime AuditWindowStart()
{
   return TimeCurrent() - (datetime)((long)g_auditWindowDays * 86400L);
}

string AuditWindowLabel()
{
   if(g_auditWindowDays <= 14)
      return "2W";
   if(g_auditWindowDays <= 35)
      return "5W";
   if(g_auditWindowDays <= 70)
      return "10W";
   return "20W";
}

void RefreshAuditOverlay()
{
   DrawRecentSignalHistory();
   UpdateDashboard();
}

void SetAuditWindowDays(const int days)
{
   if(days <= 0 || g_auditWindowDays == days)
      return;
   g_auditWindowDays = days;
   RefreshAuditOverlay();
}

double NAS_SMA_Range(const MqlRates &rates[], const int fromIndex, const int toIndex)
{
   if(fromIndex < 0 || toIndex < fromIndex)
      return NAS_Empty();
   double sum = 0.0;
   int count = 0;
   for(int i = fromIndex; i <= toIndex; i++)
   {
      if(!NAS_IsValid(rates[i].close))
         return NAS_Empty();
      sum += rates[i].close;
      count++;
   }
   return count > 0 ? sum / (double)count : NAS_Empty();
}

double NAS_EMA_AtIndex(const MqlRates &rates[], const int index, const int len)
{
   if(index < 0 || len <= 1)
      return index >= 0 ? rates[index].close : NAS_Empty();
   double alpha = 2.0 / ((double)len + 1.0);
   double ema = rates[0].close;
   for(int i = 1; i <= index; i++)
      ema = alpha * rates[i].close + (1.0 - alpha) * ema;
   return ema;
}

bool BuildHigherTfRates(const ENUM_TIMEFRAMES tf, const datetime signalTime, const int minBars, MqlRates &out[], int &outIndex)
{
   outIndex = -1;
   int shift = iBarShift(_Symbol, tf, signalTime, false);
   if(shift < 0)
      return false;
   int need = MathMax(minBars + shift + 20, 300);
   MqlRates tmp[];
   int copied = CopyRates(_Symbol, tf, 0, need, tmp);
   if(copied <= shift || copied < minBars)
      return false;
   if(tmp[0].time > tmp[copied - 1].time)
      ArrayReverse(tmp, 0, WHOLE_ARRAY);
   ArrayResize(out, copied);
   ArrayCopy(out, tmp);
   outIndex = copied - 1 - shift;
   if(outIndex < 0 || outIndex >= copied)
      return false;
   return true;
}

bool HtfRegimeAllows(const datetime signalTime, const int direction, string &reason)
{
   reason = "";
   if(!g_useHtfRegimeFilter)
      return true;
   MqlRates htf[];
   int idx = -1;
   if(!BuildHigherTfRates(g_htfRegimeTimeframe, signalTime, g_htfRegimeSmaLen + 2, htf, idx))
   {
      reason = "htf_regime_data_unavailable";
      return false;
   }
   double sma = NAS_SMA_Range(htf, MathMax(0, idx - g_htfRegimeSmaLen + 1), idx);
   if(!NAS_IsValid(sma))
   {
      reason = "htf_regime_sma_invalid";
      return false;
   }
   if(direction > 0 && htf[idx].close < sma)
   {
      reason = "htf_regime_bearish";
      return false;
   }
   if(direction < 0 && htf[idx].close > sma)
   {
      reason = "htf_regime_bullish";
      return false;
   }
   return true;
}

bool HtfTrendAllows(const datetime signalTime, const int direction, string &reason)
{
   reason = "";
   if(!g_useHtfTrendFilter)
      return true;
   MqlRates htf[];
   int idx = -1;
   int minBars = MathMax(g_htfTrendSlowLen, g_htfTrendFastLen) + 2;
   if(!BuildHigherTfRates(g_htfTrendTimeframe, signalTime, minBars, htf, idx))
   {
      reason = "htf_trend_data_unavailable";
      return false;
   }
   double fast = NAS_EMA_AtIndex(htf, idx, g_htfTrendFastLen);
   double slow = NAS_EMA_AtIndex(htf, idx, g_htfTrendSlowLen);
   if(!NAS_IsValid(fast) || !NAS_IsValid(slow))
   {
      reason = "htf_trend_ema_invalid";
      return false;
   }
   if(direction > 0 && fast < slow)
   {
      reason = "htf_trend_bearish";
      return false;
   }
   if(direction < 0 && fast > slow)
   {
      reason = "htf_trend_bullish";
      return false;
   }
   return true;
}

bool CycleDirectionAllows(const int direction, string &reason)
{
   reason = "";
   if(!g_blockSameDirectionUntilOpposite)
      return true;
   if(g_lastAcceptedDirection != 0 && direction == g_lastAcceptedDirection)
   {
      reason = "same_direction_blocked";
      return false;
   }
   return true;
}

bool SignalAcceptanceAllows(const MqlRates &rates[], const int i, const int direction, string &reason)
{
   reason = "";
   if(direction == 0)
      return false;
   if(!CycleDirectionAllows(direction, reason))
      return false;

   string htfReason = "";
   if(!HtfRegimeAllows(rates[i].time, direction, htfReason))
   {
      reason = htfReason;
      return false;
   }

   htfReason = "";
   if(!HtfTrendAllows(rates[i].time, direction, htfReason))
   {
      reason = htfReason;
      return false;
   }

   return true;
}

void RestoreManagedState()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      g_lastAcceptedDirection = (type == POSITION_TYPE_BUY) ? 1 : -1;
      g_lastDirection = g_lastAcceptedDirection;
      g_lastEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      g_lastSl = PositionGetDouble(POSITION_SL);
      g_lastTp1 = PositionGetDouble(POSITION_TP);
      g_lastTp2 = g_lastTp1;
      g_lastTp3 = g_lastTp1;
      return;
   }
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
   g_useHtfRegimeFilter = InpUseHtfRegimeFilter;
   g_htfRegimeTimeframe = InpHtfRegimeTimeframe;
   g_htfRegimeSmaLen = InpHtfRegimeSmaLen;
   g_useHtfTrendFilter = InpUseHtfTrendFilter;
   g_htfTrendTimeframe = InpHtfTrendTimeframe;
   g_htfTrendFastLen = InpHtfTrendFastLen;
   g_htfTrendSlowLen = InpHtfTrendSlowLen;
   g_blockSameDirectionUntilOpposite = InpBlockSameDirectionUntilOpposite;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   PrintStartupDiagnostics();
   BaselineStartupSignal();
   RestoreManagedState();
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

   Print("NAS SATS EA initialized symbol=", _Symbol,
         " timeframe=", EnumToString(_Period),
         " magic=", InpMagic,
         " nas_sensitivity=", InpNasSensitivity,
         " nas_atr_risk=", InpNasAtrRisk,
         " nas_atr_len=", InpNasAtrLen,
         " signal_bar_mode=", EnumToString(InpSignalBarMode),
         " risk_engine=", EnumToString(InpRiskEngine),
         " risk_preset=", EnumToString(InpRiskPreset),
         " risk_source=", EnumToString(InpRiskSource),
         " history_bars=", InpHistoryBars,
         " signal_calc_bars=", SignalBarsToCopy(),
         " total_lot=", DoubleToString(InpTotalLot, 8),
         " leg_lot=", DoubleToString(leg, 8),
         " volume_min=", DoubleToString(minLot, 8),
         " volume_max=", DoubleToString(maxLot, 8),
         " volume_step=", DoubleToString(step, 8));

   MqlRates rates[];
   int copied = CopyRates(_Symbol, _Period, 0, SignalBarsToCopy(), rates);
   if(copied < 200)
   {
      Print("NAS SATS EA startup probe skipped: insufficient bars copied=", copied);
      return;
   }
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

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
   int copied = CopyRates(_Symbol, _Period, 0, SignalBarsToCopy(), rates);
   if(copied < 200)
      return;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   int scanFrom = LastSignalScanIndex(copied);
   for(int i = scanFrom; i >= 0; i--)
   {
      if(p[i].buy || p[i].sell)
      {
         g_lastSignalTime = rates[i].time;
         g_lastSignalKeyDirection = p[i].buy ? 1 : -1;
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
      return NAS_IsValid(entry) && NAS_IsValid(sl) && NAS_IsValid(tp1) && NAS_IsValid(tp2) && NAS_IsValid(tp3);
   }

   return SATS_CalculateRiskLevelsAtSignal(rates, copied, BuildRiskSettings(), signalIndex, direction,
                                           entry, sl, tp1, tp2, tp3, effAtr);
}

void ProcessSignalBar()
{
   MqlRates rates[];
   int copied = CopyRates(_Symbol, _Period, 0, SignalBarsToCopy(), rates);
   if(copied < 200)
      return;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);

   int i = LastSignalScanIndex(copied);
   if(i < 1)
      return;
   int direction = p[i].buy ? 1 : (p[i].sell ? -1 : 0);
   if(direction == 0 || (rates[i].time == g_lastSignalTime && direction == g_lastSignalKeyDirection))
      return;
   if(WasDirectionProcessedOnBar(rates[i].time, direction))
   {
      Print("NAS SATS EA duplicate live signal ignored dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]));
      return;
   }

   string acceptReason = "";
   if(!SignalAcceptanceAllows(rates, i, direction, acceptReason))
   {
      Print("NAS SATS EA signal blocked dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " reason=", acceptReason,
            " label=", NasSignalText(p[i]));
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
   g_beMoved = false;

   if(InpCloseExistingOnNewSignal)
      CloseManagedPositions();

   Print("NAS SATS EA executing signal dir=", (direction > 0 ? "BUY" : "SELL"),
         " copied_bars=", copied,
         " mode=", EnumToString(InpSignalBarMode),
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
      g_lastAcceptedDirection = direction;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawTradeLevels)
         DrawTradeLevels(direction);
      if(InpDrawExecutionArrows)
         DrawExecutionSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]));
   }
}

int MaxTpHitBeforeExit(const MqlRates &rates[],
                       const NasPoint &p[],
                       const int signalIndex,
                       const int direction,
                       const int lastIndex,
                       const double entry,
                       const double sl,
                       const double tp1,
                       const double tp2,
                       const double tp3,
                       string &outcome)
{
   int maxHit = 0;
   outcome = "open";
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
   }
   return maxHit;
}

void DrawRecentSignalHistory()
{
   ObjectsDeleteAll(0, PREFIX + "HIST_");
   g_historyDrawnCount = 0;

   MqlRates rates[];
   datetime fromTime = AuditWindowStart() - (datetime)(PeriodSeconds(_Period) * 300);
   datetime toTime = TimeCurrent();
   int copied = CopyRates(_Symbol, _Period, fromTime, toTime, rates);
   if(copied < 200)
   {
      Print("NAS SATS EA history overlay skipped: insufficient bars copied=", copied);
      return;
   }
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);

   for(int h = 0; h < 3; h++)
      g_historySummary[h] = "-";

   int drawn = 0;
   int wanted = copied;
   datetime windowStart = AuditWindowStart();
   for(int i = copied - 2; i >= 0 && drawn < wanted; i--)
   {
      if(rates[i].time < windowStart)
         break;
      if(!p[i].buy && !p[i].sell)
         continue;
      int direction = p[i].buy ? 1 : -1;
      string acceptReason = "";
      if(!SignalAcceptanceAllows(rates, i, direction, acceptReason))
         continue;
      double entry = p[i].nasEntry;
      double sl = p[i].nasSl;
      double tp1 = p[i].nasTp1;
      double tp2 = p[i].nasTp2;
      double tp3 = p[i].nasTp3;
      if(!NAS_IsValid(entry) || !NAS_IsValid(sl) || !NAS_IsValid(tp1) || !NAS_IsValid(tp2) || !NAS_IsValid(tp3))
         continue;
      string outcome = "";
      int maxTp = MaxTpHitBeforeExit(rates, p, i, direction, copied - 2, entry, sl, tp1, tp2, tp3, outcome);
      DrawHistoricalSignal(drawn + 1, direction, rates[i].time, rates[i].high, rates[i].low, entry, sl, tp1, tp2, tp3, maxTp, outcome);
      if(drawn < 3)
      {
         g_historySummary[drawn] = "#" + IntegerToString(drawn + 1) + " " + (direction > 0 ? "BUY " : "SELL ")
                                  + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES)
                                  + " E=" + DoubleToString(entry, _Digits)
                                  + " SL=" + DoubleToString(sl, _Digits)
                                  + " TP1=" + DoubleToString(tp1, _Digits)
                                  + " TP2=" + DoubleToString(tp2, _Digits)
                                  + " TP3=" + DoubleToString(tp3, _Digits)
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
            " sl=", DoubleToString(sl, _Digits),
            " tp1=", DoubleToString(tp1, _Digits),
            " tp2=", DoubleToString(tp2, _Digits),
            " tp3=", DoubleToString(tp3, _Digits),
            " max_tp=", maxTp,
            " outcome=", outcome);
      drawn++;
   }
   g_historyDrawnCount = drawn;
   Print("NAS SATS EA history overlay drawn=", drawn, " requested=", wanted, " window=", AuditWindowLabel());
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

bool OpenThreeLegs(const int direction)
{
   double leg = LegVolume();
   if(leg <= 0.0)
   {
      Print("NAS SATS EA: invalid leg volume from total lot ", InpTotalLot);
      return false;
   }

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tps[3] = {g_lastTp1, g_lastTp2, g_lastTp3};
   string comments[3] = {"NAS_TP1", "NAS_TP2", "NAS_TP3"};
   bool anyOpened = false;

   for(int i = 0; i < 3; i++)
   {
      bool ok = trade.PositionOpen(_Symbol, type, leg, price, g_lastSl, tps[i], comments[i]);
      if(!ok)
         Print("NAS SATS EA open failed leg=", i + 1, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      else
         anyOpened = true;
   }
   return anyOpened;
}

bool IsManagedPosition()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   return (long)PositionGetInteger(POSITION_MAGIC) == InpMagic;
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
      if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
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
                          const double sl,
                          const double tp1,
                          const double tp2,
                          const double tp3,
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
                + " SL=" + DoubleToString(sl, _Digits)
                + " TP1=" + DoubleToString(tp1, _Digits)
                + " TP2=" + DoubleToString(tp2, _Digits)
                + " TP3=" + DoubleToString(tp3, _Digits)
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
   DrawHLine("TP1", g_lastTp1, clrLime, STYLE_DASH, 1);
   DrawHLine("TP2", g_lastTp2, clrLime, STYLE_DASH, 1);
   DrawHLine("TP3", g_lastTp3, clrLime, STYLE_DASH, 2);
   string d = direction > 0 ? "BUY" : "SELL";
   DrawTextLabel("ENTRY_TXT", d + " ENTRY " + DoubleToString(g_lastEntry, _Digits), g_lastEntry, clrWhite);
   DrawTextLabel("SL_TXT", "SL " + DoubleToString(g_lastSl, _Digits), g_lastSl, clrRed);
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
   CreateButton("BTN_CLOSE_ALL", 18, 148, 110, 24, "CLOSE ALL", clrFireBrick);
   CreateButton("BTN_CLOSE_1_3", 136, 148, 110, 24, "CLOSE 1/3", clrDarkSlateGray);
   CreateButton("BTN_BE", 254, 148, 110, 24, "SL -> BE", clrDarkGreen);
   CreateButton("BTN_AUD_2W", 18, 178, 74, 24, "2W", g_auditWindowDays <= 14 ? clrSeaGreen : clrDimGray);
   CreateButton("BTN_AUD_5W", 98, 178, 74, 24, "5W", g_auditWindowDays <= 35 && g_auditWindowDays > 14 ? clrSeaGreen : clrDimGray);
   CreateButton("BTN_AUD_10W", 178, 178, 74, 24, "10W", g_auditWindowDays <= 70 && g_auditWindowDays > 35 ? clrSeaGreen : clrDimGray);
   CreateButton("BTN_AUD_20W", 258, 178, 74, 24, "20W", g_auditWindowDays > 70 ? clrSeaGreen : clrDimGray);
   CreateButton("BTN_FILT_REG", 18, 208, 110, 24, g_useHtfRegimeFilter ? "HTF REG ON" : "HTF REG OFF", g_useHtfRegimeFilter ? clrSeaGreen : clrDimGray);
   CreateButton("BTN_FILT_TRD", 136, 208, 110, 24, g_useHtfTrendFilter ? "HTF TRND ON" : "HTF TRND OFF", g_useHtfTrendFilter ? clrSeaGreen : clrDimGray);
   CreateButton("BTN_FILT_DUP", 254, 208, 110, 24, g_blockSameDirectionUntilOpposite ? "NO DUP ON" : "NO DUP OFF", g_blockSameDirectionUntilOpposite ? clrSeaGreen : clrDimGray);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam == PREFIX + "BTN_CLOSE_ALL")
      CloseManagedPositions();
   else if(sparam == PREFIX + "BTN_BE")
      MoveRemainingToBE();
   else if(sparam == PREFIX + "BTN_CLOSE_1_3")
      CloseOneLeg();
   else if(sparam == PREFIX + "BTN_AUD_2W")
      SetAuditWindowDays(14);
   else if(sparam == PREFIX + "BTN_AUD_5W")
      SetAuditWindowDays(35);
   else if(sparam == PREFIX + "BTN_AUD_10W")
      SetAuditWindowDays(70);
   else if(sparam == PREFIX + "BTN_AUD_20W")
      SetAuditWindowDays(140);
   else if(sparam == PREFIX + "BTN_FILT_REG")
   {
      g_useHtfRegimeFilter = !g_useHtfRegimeFilter;
      RefreshAuditOverlay();
   }
   else if(sparam == PREFIX + "BTN_FILT_TRD")
   {
      g_useHtfTrendFilter = !g_useHtfTrendFilter;
      RefreshAuditOverlay();
   }
   else if(sparam == PREFIX + "BTN_FILT_DUP")
   {
      g_blockSameDirectionUntilOpposite = !g_blockSameDirectionUntilOpposite;
      RefreshAuditOverlay();
   }
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
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 640);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 380);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'16,20,28');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'55,65,80');
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'55,65,80');
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

   CreateLabel("DASH_TITLE", 22, 28, "NAS + SATS RISK EXECUTION DESK", clrAqua, 11);
   CreateLabel("DASH_1", 22, 52, "Symbol/TF: " + _Symbol + " " + EnumToString(_Period), clrWhite);
   CreateLabel("DASH_2", 22, 70, "Total PnL: " + DoubleToString(totalPnl, 2) + "   Daily: " + DoubleToString(dailyPnl, 2), clrWhite);
   CreateLabel("DASH_3", 22, 88, "Open PnL: " + DoubleToString(openPnl, 2) + "   Max DD: " + DoubleToString(g_maxDd, 2), clrWhite);
   string dir = g_lastDirection > 0 ? "BUY" : (g_lastDirection < 0 ? "SELL" : "-");
   CreateLabel("DASH_4", 22, 106, "Last NAS: " + dir + " entry=" + DoubleToString(g_lastEntry, _Digits), clrWhite);
   CreateLabel("DASH_5", 22, 124, "Risk: SATS TP/SL engine   Window: " + AuditWindowLabel() + "   Signals: " + IntegerToString(g_historyDrawnCount), clrSilver);
   CreateLabel("DASH_6", 22, 142, "Filters: Regime=" + (g_useHtfRegimeFilter ? "ON" : "OFF")
                                + " Trend=" + (g_useHtfTrendFilter ? "ON" : "OFF")
                                + " NoDup=" + (g_blockSameDirectionUntilOpposite ? "ON" : "OFF"), clrSilver);
   CreateLabel("DASH_H0", 22, 250, "Recent NAS signals in window:", clrAqua);
   CreateLabel("DASH_H1", 22, 266, g_historySummary[0], clrSilver, 8);
   CreateLabel("DASH_H2", 22, 282, g_historySummary[1], clrSilver, 8);
   CreateLabel("DASH_H3", 22, 298, g_historySummary[2], clrSilver, 8);
   CreateButtons();
}
