//+------------------------------------------------------------------+
//| SuperTrend SATS EA                                                |
//| Pine source: IndicatorCodeExamples/SuperTrend.pine                |
//| Uses the same SuperTrend_SATS_Core.mqh calculation as indicator.  |
//| Opens 3 equal legs, closes TP1 leg at TP1, then moves remaining   |
//| SL to break-even.                                                 |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>
#include "SuperTrend_SATS_Core.mqh"

input SATS_PRESET InpPreset = SATS_PRESET_AUTO;
input SATS_SOURCE InpSource = SATS_SOURCE_CLOSE;
input int    InpAtrLen = 13;
input double InpBaseMult = 2.0;
input bool   InpUseAdaptive = true;
input int    InpErLen = 20;
input double InpAdaptStrength = 0.5;
input int    InpAtrBaselineLen = 100;
input bool   InpUseTqi = true;
input double InpQualityStrength = 0.4;
input double InpQualityCurve = 1.5;
input bool   InpSmoothMult = true;
input bool   InpUseAsymBands = true;
input double InpAsymStrength = 0.5;
input bool   InpUseEffAtr = true;
input bool   InpUseCharFlip = true;
input int    InpCharFlipMinAge = 5;
input double InpCharFlipHigh = 0.55;
input double InpCharFlipLow = 0.25;
input double InpTqiWeightEr = 0.35;
input double InpTqiWeightVol = 0.20;
input double InpTqiWeightStruct = 0.25;
input double InpTqiWeightMom = 0.20;
input int    InpTqiStructLen = 20;
input int    InpTqiMomLen = 10;
input int    InpPivotLen = 3;
input int    InpRsiLen = 14;
input int    InpVolLen = 20;
input double InpSlAtrMult = 1.5;
input double InpTp1R = 1.0;
input double InpTp2R = 2.0;
input double InpTp3R = 3.0;

input double InpTotalLot = 0.04;
input int    InpDeviationPoints = 30;
input long   InpMagic = 27052791;
input int    InpHistoryBars = 20000;
input bool   InpCloseExistingOnNewSignal = true;
input bool   InpDrawTradeLevels = true;
input bool   InpDrawExecutionArrows = true;
input bool   InpTradeLatestSignalOnAttach = false;
input bool   InpDrawLastSignalsOnStart = true;
input int    InpStartupSignalCount = 3;
input bool   InpShowDashboard = true;
input int    InpTrailAtrLen = 14;
input double InpTrailAtrMult = 1.5;
input bool   InpUseAtrTrailAfterTP1 = true;
input bool   InpMoveToBEAfterTP1 = true;
input bool   InpEnableLearningFilter = false;
input bool   InpLearningObserveOnly = true;
input double InpLearningThreshold = 0.55;
input double InpLearningRate = 0.05;
input bool   InpTelemetryEnabled = true;
input int    InpTelemetryEverySeconds = 1;
input bool   InpTelemetryUseCommonFiles = true;
input int    InpTelemetryRsiLen = 14;
input int    InpTelemetryAdxLen = 14;
input int    InpTelemetryAtrLen = 14;
input int    InpTelemetryHmaLen = 55;
input int    InpTelemetryEmaFastLen = 9;
input int    InpTelemetryEmaSlowLen = 21;
input int    InpTelemetrySmaLen = 50;
input int    InpTelemetryMacdFast = 12;
input int    InpTelemetryMacdSlow = 26;
input int    InpTelemetryMacdSignal = 9;

CTrade trade;
int      g_atrHandle = INVALID_HANDLE;
datetime g_lastBarTime = 0;
datetime g_lastSignalTime = 0;
int      g_lastDirection = 0;
double   g_lastEntry = 0.0;
double   g_lastSl = 0.0;
double   g_lastTp1 = 0.0;
double   g_lastTp2 = 0.0;
double   g_lastTp3 = 0.0;
bool     g_beMoved = false;
bool     g_trailingActive = false;
double   g_highestCloseSinceEntry = 0.0;
double   g_lowestCloseSinceEntry = 0.0;
double   g_equityPeak = 0.0;
double   g_maxDd = 0.0;
string   g_historySummary[3];
double   g_learningScore = 0.50;
int      g_learningSamples = 0;
int      g_learningWins = 0;
int      g_learningLosses = 0;
string   g_learningDecision = "observe";

string PREFIX = "SATS_ADV_EA_";

bool IsManagedPosition();

#include "AdvancedTradeTelemetry.mqh"

SATSSettings BuildSettings()
{
   SATSSettings s;
   s.preset = InpPreset;
   s.source = InpSource;
   s.atrLen = InpAtrLen;
   s.baseMult = InpBaseMult;
   s.useAdaptive = InpUseAdaptive;
   s.erLen = InpErLen;
   s.adaptStrength = InpAdaptStrength;
   s.atrBaselineLen = InpAtrBaselineLen;
   s.useTqi = InpUseTqi;
   s.qualityStrength = InpQualityStrength;
   s.qualityCurve = InpQualityCurve;
   s.smoothMult = InpSmoothMult;
   s.useAsymBands = InpUseAsymBands;
   s.asymStrength = InpAsymStrength;
   s.useEffAtr = InpUseEffAtr;
   s.useCharFlip = InpUseCharFlip;
   s.charFlipMinAge = InpCharFlipMinAge;
   s.charFlipHigh = InpCharFlipHigh;
   s.charFlipLow = InpCharFlipLow;
   s.tqiWeightEr = InpTqiWeightEr;
   s.tqiWeightVol = InpTqiWeightVol;
   s.tqiWeightStruct = InpTqiWeightStruct;
   s.tqiWeightMom = InpTqiWeightMom;
   s.tqiStructLen = InpTqiStructLen;
   s.tqiMomLen = InpTqiMomLen;
   s.pivotLen = InpPivotLen;
   s.rsiLen = InpRsiLen;
   s.volLen = InpVolLen;
   s.slAtrMult = InpSlAtrMult;
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
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   g_atrHandle = iATR(_Symbol, _Period, InpTrailAtrLen);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("SATS Advanced EA init failed: cannot create ATR handle len=", InpTrailAtrLen, " err=", GetLastError());
      return INIT_FAILED;
   }
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   TelemetryInit();
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

void PrintStartupDiagnostics()
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double leg = LegVolume();
   bool terminalTradeAllowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool mqlTradeAllowed = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool accountTradeAllowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);

   Print("SATS EA initialized symbol=", _Symbol,
         " timeframe=", EnumToString(_Period),
         " magic=", InpMagic,
         " preset=", EnumToString(InpPreset),
         " source=", EnumToString(InpSource),
         " history_bars=", InpHistoryBars,
         " total_lot=", DoubleToString(InpTotalLot, 8),
         " leg_lot=", DoubleToString(leg, 8),
         " volume_min=", DoubleToString(minLot, 8),
         " volume_max=", DoubleToString(maxLot, 8),
         " volume_step=", DoubleToString(step, 8));
   Print("SATS EA trade permissions terminal=", terminalTradeAllowed,
         " mql=", mqlTradeAllowed,
         " account=", accountTradeAllowed,
         " close_existing_on_signal=", InpCloseExistingOnNewSignal);

   MqlRates rates[];
   int copied = CopyRates(_Symbol, _Period, 0, MathMax(InpHistoryBars, 300), rates);
   if(copied < 150)
   {
      Print("SATS EA startup probe skipped: insufficient bars copied=", copied);
      return;
   }
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   SATSPoint p[];
   SATSSettings s = BuildSettings();
   SATS_Calculate(rates, copied, s, p);
   int last = -1;
   for(int i = copied - 2; i >= 0; i--)
   {
      if(p[i].buy || p[i].sell)
      {
         last = i;
         break;
      }
   }
   if(last >= 0)
      Print("SATS EA startup last_signal dir=", (p[last].buy ? "BUY" : "SELL"),
            " copied_bars=", copied,
            " bar=", TimeToString(rates[last].time, TIME_DATE|TIME_MINUTES),
            " entry=", DoubleToString(p[last].entry, _Digits),
            " sl=", DoubleToString(p[last].sl, _Digits),
            " tp1=", DoubleToString(p[last].tp1, _Digits),
            " tp2=", DoubleToString(p[last].tp2, _Digits),
            " tp3=", DoubleToString(p[last].tp3, _Digits));
   else
      Print("SATS EA startup last_signal: none within copied bars=", copied);
}

void BaselineStartupSignal()
{
   if(InpTradeLatestSignalOnAttach)
   {
      Print("SATS EA startup baseline disabled by input; latest closed signal may execute on attach.");
      return;
   }

   MqlRates rates[];
   int copied = CopyRates(_Symbol, _Period, 0, MathMax(InpHistoryBars, 300), rates);
   if(copied < 150)
      return;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   SATSPoint p[];
   SATSSettings s = BuildSettings();
   SATS_Calculate(rates, copied, s, p);

   for(int i = copied - 2; i >= 0; i--)
   {
      if(p[i].buy || p[i].sell)
      {
         g_lastSignalTime = rates[i].time;
         Print("SATS EA startup baseline registered dir=", (p[i].buy ? "BUY" : "SELL"),
               " copied_bars=", copied,
               " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
               " no historical execution emitted.");
         return;
      }
   }
}

void OnDeinit(const int reason)
{
   TelemetryDeinit();
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   ObjectsDeleteAll(0, PREFIX);
}

void OnTick()
{
   ManageOpenPositions();
   TelemetryLogOpenPositions();
   UpdateDashboard();

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == 0 || curBar == g_lastBarTime)
      return;
   g_lastBarTime = curBar;
   ProcessClosedBarSignal();
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
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal))
      return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
      return;
   if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
      return;
   TelemetryLogDeal(deal);
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;

   double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT)
                + HistoryDealGetDouble(deal, DEAL_SWAP)
                + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   g_learningSamples++;
   if(pnl >= 0.0)
   {
      g_learningWins++;
      g_learningScore += InpLearningRate * (1.0 - g_learningScore);
   }
   else
   {
      g_learningLosses++;
      g_learningScore -= InpLearningRate * g_learningScore;
   }
   g_learningScore = MathMax(0.0, MathMin(1.0, g_learningScore));
}

void ProcessClosedBarSignal()
{
   MqlRates rates[];
   int need = MathMax(InpHistoryBars, 300);
   int copied = CopyRates(_Symbol, _Period, 0, need, rates);
   if(copied < 150)
      return;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   SATSPoint p[];
   SATSSettings s = BuildSettings();
   SATS_Calculate(rates, copied, s, p);

   int i = copied - 2; // last closed candle, matching Pine barstate.isconfirmed.
   if(i < 1)
      return;
   int direction = p[i].buy ? 1 : (p[i].sell ? -1 : 0);
   if(direction == 0 || rates[i].time == g_lastSignalTime)
      return;
   datetime expectedClose = rates[i].time + PeriodSeconds(_Period);
   int signalDelaySec = (int)(TimeCurrent() - expectedClose);

   g_lastSignalTime = rates[i].time;
   g_lastDirection = direction;
   g_lastEntry = NormalizeDouble(p[i].entry, _Digits);
   g_lastSl = NormalizeDouble(p[i].sl, _Digits);
   g_lastTp1 = NormalizeDouble(p[i].tp1, _Digits);
   g_lastTp2 = NormalizeDouble(p[i].tp2, _Digits);
   g_lastTp3 = NormalizeDouble(p[i].tp3, _Digits);
   g_beMoved = false;
   g_trailingActive = false;
   g_highestCloseSinceEntry = p[i].entry;
   g_lowestCloseSinceEntry = p[i].entry;

   if(InpCloseExistingOnNewSignal)
      CloseManagedPositions();
   g_learningDecision = LearningAllowsTrade() ? "allowed" : "blocked";
   if(InpEnableLearningFilter && !InpLearningObserveOnly && !LearningAllowsTrade())
   {
      Print("SATS Advanced EA learning filter blocked signal dir=", (direction > 0 ? "BUY" : "SELL"),
            " score=", DoubleToString(g_learningScore, 3),
            " threshold=", DoubleToString(InpLearningThreshold, 3));
      return;
   }
   Print("SATS EA executing signal dir=", (direction > 0 ? "BUY" : "SELL"),
         " copied_bars=", copied,
         " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
         " expected_close=", TimeToString(expectedClose, TIME_DATE|TIME_SECONDS),
         " delay_sec=", signalDelaySec,
         " pine_entry=", DoubleToString(g_lastEntry, _Digits),
         " sl=", DoubleToString(g_lastSl, _Digits),
         " tp1=", DoubleToString(g_lastTp1, _Digits),
         " tp2=", DoubleToString(g_lastTp2, _Digits),
         " tp3=", DoubleToString(g_lastTp3, _Digits));
   bool opened = OpenThreeLegs(direction);
   if(opened)
   {
      if(InpDrawTradeLevels)
         DrawTradeLevels(direction);
      if(InpDrawExecutionArrows)
         DrawExecutionSignal(direction, rates[i].time, rates[i].high, rates[i].low);
   }
}

int MaxTpHitBeforeExit(const SATSPoint &p[], const MqlRates &rates[], const int signalIndex, const int signalDirection, const int lastIndex, string &outcome)
{
   int maxHit = 0;
   int end = lastIndex;
   outcome = "open";
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
      bool tp1 = signalDirection > 0 ? rates[j].high >= p[signalIndex].tp1 : rates[j].low <= p[signalIndex].tp1;
      bool tp2 = signalDirection > 0 ? rates[j].high >= p[signalIndex].tp2 : rates[j].low <= p[signalIndex].tp2;
      bool tp3 = signalDirection > 0 ? rates[j].high >= p[signalIndex].tp3 : rates[j].low <= p[signalIndex].tp3;
      bool sl = signalDirection > 0 ? rates[j].low <= p[signalIndex].sl : rates[j].high >= p[signalIndex].sl;
      if(tp1) maxHit = MathMax(maxHit, 1);
      if(tp2) maxHit = MathMax(maxHit, 2);
      if(tp3) maxHit = MathMax(maxHit, 3);
      if(tp3)
      {
         outcome = "TP3";
         break;
      }
      if(sl)
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
   int copied = CopyRates(_Symbol, _Period, 0, MathMax(InpHistoryBars, 300), rates);
   if(copied < 150)
   {
      Print("SATS EA history overlay skipped: insufficient bars copied=", copied);
      return;
   }
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   SATSPoint p[];
   SATSSettings s = BuildSettings();
   SATS_Calculate(rates, copied, s, p);

   int drawn = 0;
   int wanted = MathMax(1, InpStartupSignalCount);
   for(int h = 0; h < 3; h++)
      g_historySummary[h] = "-";
   for(int i = copied - 2; i >= 0 && drawn < wanted; i--)
   {
      if(!p[i].buy && !p[i].sell)
         continue;
      int direction = p[i].buy ? 1 : -1;
      string outcome = "";
      int maxTp = MaxTpHitBeforeExit(p, rates, i, direction, copied - 2, outcome);
      DrawHistoricalSignal(drawn + 1, direction, rates[i].time, rates[i].high, rates[i].low, p[i].entry, maxTp, outcome);
      if(drawn < 3)
      {
         g_historySummary[drawn] = "#" + IntegerToString(drawn + 1) + " " + (direction > 0 ? "BUY " : "SELL ")
                                  + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES)
                                  + " E=" + DoubleToString(p[i].entry, _Digits)
                                  + " max=" + (maxTp > 0 ? "TP" + IntegerToString(maxTp) : "none")
                                  + " " + outcome;
      }
      Print("SATS EA history signal#", drawn + 1,
            " dir=", (direction > 0 ? "BUY" : "SELL"),
            " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
            " entry=", DoubleToString(p[i].entry, _Digits),
            " max_tp=", maxTp,
            " outcome=", outcome);
      drawn++;
   }
   Print("SATS EA history overlay drawn=", drawn, " requested=", wanted);
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
   double leg = MathFloor((InpTotalLot / 4.0) / step) * step;
   return NormalizeVolume(leg);
}

bool OpenThreeLegs(const int direction)
{
   double leg = LegVolume();
   if(leg <= 0.0)
   {
      Print("SATS EA: invalid leg volume from total lot ", InpTotalLot);
      return false;
   }

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = g_lastSl;
   double tps[4] = {g_lastTp1, g_lastTp2, g_lastTp3, g_lastTp3};
   string comments[4] = {"SATS_ADV_TP1_25", "SATS_ADV_TP2_25", "SATS_ADV_RUN_25A", "SATS_ADV_RUN_25B"};
   bool anyOpened = false;

   for(int i = 0; i < 4; i++)
   {
      bool ok = trade.PositionOpen(_Symbol, type, leg, price, sl, tps[i], comments[i]);
      if(!ok)
         Print("SATS EA open failed leg=", i + 1, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      else
         anyOpened = true;
   }
   return anyOpened;
}

bool IsManagedPosition()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
      return false;
   return true;
}

bool LearningAllowsTrade()
{
   if(!InpEnableLearningFilter)
      return true;
   return g_learningScore >= InpLearningThreshold;
}

double CurrentAtr()
{
   if(g_atrHandle == INVALID_HANDLE)
      return 0.0;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
      return 0.0;
   return atr[0];
}

double AdvancedStopCandidate()
{
   if(g_lastDirection == 0)
      return 0.0;
   double close1 = iClose(_Symbol, _Period, 1);
   if(close1 <= 0.0)
      close1 = g_lastEntry;
   if(g_highestCloseSinceEntry <= 0.0)
      g_highestCloseSinceEntry = g_lastEntry;
   if(g_lowestCloseSinceEntry <= 0.0)
      g_lowestCloseSinceEntry = g_lastEntry;

   if(g_lastDirection > 0)
      g_highestCloseSinceEntry = MathMax(g_highestCloseSinceEntry, close1);
   else
      g_lowestCloseSinceEntry = MathMin(g_lowestCloseSinceEntry, close1);

   double atr = CurrentAtr();
   if(!InpUseAtrTrailAfterTP1 || atr <= 0.0)
      return NormalizeDouble(g_lastEntry, _Digits);

   double trail = g_lastDirection > 0
                  ? g_highestCloseSinceEntry - InpTrailAtrMult * atr
                  : g_lowestCloseSinceEntry + InpTrailAtrMult * atr;
   double be = NormalizeDouble(g_lastEntry, _Digits);
   double candidate = InpMoveToBEAfterTP1
                      ? (g_lastDirection > 0 ? MathMax(be, trail) : MathMin(be, trail))
                      : trail;
   return NormalizeDouble(candidate, _Digits);
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
   double newStop = AdvancedStopCandidate();
   if(newStop <= 0.0)
      newStop = NormalizeDouble(g_lastEntry, _Digits);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;
      double tp = PositionGetDouble(POSITION_TP);
      double oldSl = PositionGetDouble(POSITION_SL);
      long type = PositionGetInteger(POSITION_TYPE);
      bool improves = (type == POSITION_TYPE_BUY && (oldSl <= 0.0 || newStop > oldSl))
                      || (type == POSITION_TYPE_SELL && (oldSl <= 0.0 || newStop < oldSl));
      if(improves)
         trade.PositionModify(ticket, newStop, tp);
   }
   g_beMoved = true;
   g_trailingActive = true;
}

void ManageOpenPositions()
{
   if(g_lastDirection == 0)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool tp1Touched = g_lastDirection > 0 ? (bid >= g_lastTp1) : (ask <= g_lastTp1);
   if(tp1Touched && (!g_beMoved || !g_trailingActive))
      MoveRemainingToBE();
   else if(g_trailingActive)
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

void DrawSegment(const string name, const datetime t1, const datetime t2, const double price, const color clr, const ENUM_LINE_STYLE style, const int width)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TREND, 0, t1, price, t2, price);
   ObjectMove(0, obj, 0, t1, price);
   ObjectMove(0, obj, 1, t2, price);
   ObjectSetInteger(0, obj, OBJPROP_RAY_RIGHT, false);
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
                         const double signalLow)
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
                      "EXEC " + side + " E=" + DoubleToString(g_lastEntry, _Digits),
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
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 560);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 270);
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

   CreateLabel("DASH_TITLE", 22, 28, "SATS ADVANCED EXECUTION DESK", clrAqua, 11);
   CreateLabel("DASH_1", 22, 52, "Symbol/TF: " + _Symbol + " " + EnumToString(_Period), clrWhite);
   CreateLabel("DASH_2", 22, 70, "Total PnL: " + DoubleToString(totalPnl, 2) + "   Daily: " + DoubleToString(dailyPnl, 2), clrWhite);
   CreateLabel("DASH_3", 22, 88, "Open PnL: " + DoubleToString(openPnl, 2) + "   Max DD: " + DoubleToString(g_maxDd, 2), clrWhite);
   string dir = g_lastDirection > 0 ? "BUY" : (g_lastDirection < 0 ? "SELL" : "-");
   CreateLabel("DASH_4", 22, 106, "Last: " + dir + " entry=" + DoubleToString(g_lastEntry, _Digits), clrWhite);
   CreateLabel("DASH_5", 22, 124, "Exit: TP1 25%, TP2 25%, TP3/trail 50% | trail=" + (g_trailingActive ? "ON" : "OFF"), clrSilver);
   CreateLabel("DASH_6", 22, 142, "Learning: score=" + DoubleToString(g_learningScore, 3)
               + " samples=" + IntegerToString(g_learningSamples)
               + " W/L=" + IntegerToString(g_learningWins) + "/" + IntegerToString(g_learningLosses)
               + " mode=" + (InpEnableLearningFilter ? (InpLearningObserveOnly ? "observe" : "filter") : "off")
               + " last=" + g_learningDecision, clrSilver, 8);
   CreateLabel("DASH_7", 22, 160, "Telemetry: " + string(InpTelemetryEnabled ? "ON" : "OFF")
               + " every " + IntegerToString(InpTelemetryEverySeconds) + "s"
               + " | CSV=" + TelemetryFileName(), clrSilver, 8);
   CreateLabel("DASH_H0", 22, 182, "Recent SATS signals:", clrAqua);
   CreateLabel("DASH_H1", 22, 198, g_historySummary[0], clrSilver, 8);
   CreateLabel("DASH_H2", 22, 214, g_historySummary[1], clrSilver, 8);
   CreateLabel("DASH_H3", 22, 230, g_historySummary[2], clrSilver, 8);
}
