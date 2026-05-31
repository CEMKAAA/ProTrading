//+------------------------------------------------------------------+
//| FibSystem + Price Action Context EA                              |
//| Signal source: IndicatorCodeExamples/FibSystem.pine              |
//| Trades raw PPO triangles through SMC/price-action context gates. |
//| lime triangleup  = PPO local low  = BUY                          |
//| red triangledown = PPO local high = SELL                         |
//+------------------------------------------------------------------+
#property strict
#property version "1.17"

#include <Trade/Trade.mqh>

enum FIB_SIGNAL_BAR_MODE
{
   FIB_SIGNAL_BAR_LIVE = 0,
   FIB_SIGNAL_BAR_CLOSED = 1
};

enum PA_GATE_MODE
{
   PA_GATE_OFF = 0,
   PA_GATE_SOFT = 1,
   PA_GATE_STRICT = 2,
   PA_GATE_ZONE_ONLY = 3
};

input int    InpFastLength = 12;
input int    InpSlowLength = 26;
input int    InpSmoother = 2;
input FIB_SIGNAL_BAR_MODE InpSignalBarMode = FIB_SIGNAL_BAR_CLOSED;
input bool   InpBlockSameDirectionUntilReverse = true;
input bool   InpUseTradingTimeWindow = true;
input string InpTradeStartTime = "09:00";
input string InpTradeEndTime = "14:00";
input double InpLot = 0.01;
input int    InpStopLossPoints = 1000;
input double InpCatastrophicStopPercent = 0.80;
input int    InpTakeProfitPoints = 0;
input PA_GATE_MODE InpPriceActionGate = PA_GATE_SOFT;
input int    InpPaExternalSensitivity = 25;
input int    InpPaInternalSensitivity = 3;
input bool   InpPaUseExternalBias = true;
input bool   InpPaUseInternalBias = true;
input bool   InpPaRequireAvoidOpposingZone = true;
input int    InpPaZoneTolerancePoints = 100;
input bool   InpPaDrawContext = true;
input int    InpPaMaxDrawZones = 5;
input int    InpPaContextBars = 500;
input bool   InpPaRebuildEveryTick = false;
input int    InpPaRedrawSeconds = 5;
input int    InpDeviationPoints = 30;
input long   InpMagic = 29052901;
input int    InpSignalCalcBars = 3000;
input bool   InpCloseExistingOnNewSignal = true;
input bool   InpDrawExecutionArrows = true;
input bool   InpDrawActualExecutionMarker = true;
input bool   InpDrawBackplotPivotSignal = false;
input bool   InpRemoveVanishedLiveSignalObjects = true;
input bool   InpDrawBlockedSignalArrows = false;
input bool   InpDrawRecentSignalsOnStart = true;
input int    InpStartupSignalCount = 10;
input bool   InpTradeLatestSignalOnAttach = false;
input bool   InpShowDashboard = true;

CTrade trade;
long     g_runtimeMagic = 0;
datetime g_lastBarTime = 0;
datetime g_processedBuyDecisionTime = 0;
datetime g_processedSellDecisionTime = 0;
int      g_lastAcceptedDirection = 0;
int      g_lastSignalDirection = 0;
bool     g_liveProvisionalActive = false;
int      g_liveProvisionalDirection = 0;
datetime g_liveProvisionalDecisionTime = 0;
datetime g_liveProvisionalVisualTime = 0;
int      g_liveProvisionalPriorSignalDirection = 0;
datetime g_liveProvisionalExecutionTime = 0;
double   g_liveProvisionalExecutionPrice = 0.0;
datetime g_liveBuyDecisionTime = 0;
datetime g_liveBuyVisualTime = 0;
datetime g_liveBuyExecutionTime = 0;
datetime g_liveSellDecisionTime = 0;
datetime g_liveSellVisualTime = 0;
datetime g_liveSellExecutionTime = 0;
string   g_lastSignalText = "-";
string   g_lastActionText = "startup";
string   g_tradeStartTimeRuntime = "";
string   g_tradeEndTimeRuntime = "";
double   g_equityPeak = 0.0;
double   g_maxDd = 0.0;
datetime g_lastPaBuildBarTime = 0;
datetime g_lastPaDrawTime = 0;
bool     g_paContextReady = false;
double   g_lastExecutionPrice = 0.0;
datetime g_lastExecutionTime = 0;
double   g_lastSignalVisualClose = 0.0;
double   g_lastSignalDecisionClose = 0.0;
datetime g_lastSignalVisualTime = 0;
datetime g_lastSignalDecisionTime = 0;
ulong    g_lastOpenedTicket = 0;

string PREFIX = "FIB_PA_CTX_EA_";

struct PaZone
{
   double top;
   double bottom;
   datetime leftTime;
   int direction;
   string kind;
};

struct PaEvent
{
   int direction;
   string name;
   double level;
   datetime pivotTime;
   datetime eventTime;
};

struct PaContext
{
   int externalBias;
   int internalBias;
   PaEvent externalEvent;
   PaEvent internalEvent;
   bool inDemand;
   bool inSupply;
   bool inBullFvg;
   bool inBearFvg;
   bool inLowerAoe;
   bool inUpperAoe;
   double aoiUpperTop;
   double aoiUpperBottom;
   double aoiLowerTop;
   double aoiLowerBottom;
   int demandCount;
   int supplyCount;
   int bullFvgCount;
   int bearFvgCount;
   string summary;
};

PaZone g_supplyZones[];
PaZone g_demandZones[];
PaZone g_bullFvgZones[];
PaZone g_bearFvgZones[];
PaContext g_lastPaContext;

bool IsValidNumber(const double value)
{
   return value != EMPTY_VALUE && MathIsValidNumber(value) && value < DBL_MAX / 2.0 && value > -DBL_MAX / 2.0;
}

long RuntimeMagic()
{
   if(g_runtimeMagic != 0)
      return g_runtimeMagic;
   ulong chartId = ChartID();
   long chartPart = (long)(chartId % 1000000);
   g_runtimeMagic = InpMagic * 1000000 + chartPart;
   return g_runtimeMagic;
}

int BarsToCopy()
{
   int minBars = MathMax(InpSlowLength + InpSmoother + 20, 100);
   return MathMax(InpSignalCalcBars, minBars);
}

string DirectionText(const int direction)
{
   if(direction > 0)
      return "BUY";
   if(direction < 0)
      return "SELL";
   return "NONE";
}

bool WasProcessed(const datetime decisionTime, const int direction)
{
   if(direction > 0)
      return g_processedBuyDecisionTime == decisionTime;
   if(direction < 0)
      return g_processedSellDecisionTime == decisionTime;
   return false;
}

void MarkProcessed(const datetime decisionTime, const int direction)
{
   if(direction > 0)
      g_processedBuyDecisionTime = decisionTime;
   else if(direction < 0)
      g_processedSellDecisionTime = decisionTime;
}

void ClearLiveProvisional()
{
   g_liveProvisionalActive = false;
   g_liveProvisionalDirection = 0;
   g_liveProvisionalDecisionTime = 0;
   g_liveProvisionalVisualTime = 0;
   g_liveProvisionalPriorSignalDirection = 0;
   g_liveProvisionalExecutionTime = 0;
   g_liveProvisionalExecutionPrice = 0.0;
}

void ArmLiveProvisional(const datetime decisionTime, const datetime visualTime, const int direction, const int priorSignalDirection, const datetime execTime, const double execPrice)
{
   if(InpSignalBarMode != FIB_SIGNAL_BAR_LIVE)
      return;
   g_liveProvisionalActive = true;
   g_liveProvisionalDirection = direction;
   g_liveProvisionalDecisionTime = decisionTime;
   g_liveProvisionalVisualTime = visualTime;
   g_liveProvisionalPriorSignalDirection = priorSignalDirection;
   g_liveProvisionalExecutionTime = execTime;
   g_liveProvisionalExecutionPrice = execPrice;
   if(direction > 0)
   {
      g_liveBuyDecisionTime = decisionTime;
      g_liveBuyVisualTime = visualTime;
      g_liveBuyExecutionTime = execTime;
   }
   else if(direction < 0)
   {
      g_liveSellDecisionTime = decisionTime;
      g_liveSellVisualTime = visualTime;
      g_liveSellExecutionTime = execTime;
   }
}

int ParseClockMinutes(const string value, const int fallbackMinutes)
{
   int colon = StringFind(value, ":");
   if(colon <= 0)
      return fallbackMinutes;
   int hour = (int)StringToInteger(StringSubstr(value, 0, colon));
   int minute = (int)StringToInteger(StringSubstr(value, colon + 1));
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

string TradingWindowText()
{
   if(!InpUseTradingTimeWindow)
      return "OFF";
   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   return string(IsTradingTimeOpen() ? "OPEN " : "CLOSED ") + startText + "-" + endText;
}

void HydrateDirectionFromOpenPosition()
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
      g_lastAcceptedDirection = type == POSITION_TYPE_BUY ? 1 : -1;
      g_lastSignalDirection = g_lastAcceptedDirection;
      Print("FibSystem EA hydrated open direction ", DirectionText(g_lastAcceptedDirection), " ticket=", ticket);
      return;
   }
}

bool CalculatePpo(const MqlRates &rates[], const int bars, double &ppoSmooth[])
{
   if(bars < InpSlowLength + InpSmoother + 5)
      return false;

   double fast[], slow[], macdPct[];
   ArrayResize(fast, bars);
   ArrayResize(slow, bars);
   ArrayResize(macdPct, bars);
   ArrayResize(ppoSmooth, bars);
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(macdPct, true);
   ArraySetAsSeries(ppoSmooth, true);

   double fastAlpha = 2.0 / (MathMax(1, InpFastLength) + 1.0);
   double slowAlpha = 2.0 / (MathMax(1, InpSlowLength) + 1.0);

   for(int i = bars - 1; i >= 0; i--)
   {
      double closePrice = rates[i].close;
      if(i == bars - 1)
      {
         fast[i] = closePrice;
         slow[i] = closePrice;
      }
      else
      {
         fast[i] = fastAlpha * closePrice + (1.0 - fastAlpha) * fast[i + 1];
         slow[i] = slowAlpha * closePrice + (1.0 - slowAlpha) * slow[i + 1];
      }

      if(MathAbs(slow[i]) <= 1e-12)
         macdPct[i] = EMPTY_VALUE;
      else
         macdPct[i] = ((fast[i] - slow[i]) / slow[i]) * 100.0;
   }

   int smoother = MathMax(1, InpSmoother);
   for(int i = bars - 1; i >= 0; i--)
   {
      if(i + smoother - 1 >= bars)
      {
         ppoSmooth[i] = EMPTY_VALUE;
         continue;
      }
      double sum = 0.0;
      bool ok = true;
      for(int k = 0; k < smoother; k++)
      {
         if(!IsValidNumber(macdPct[i + k]))
         {
            ok = false;
            break;
         }
         sum += macdPct[i + k];
      }
      ppoSmooth[i] = ok ? sum / smoother : EMPTY_VALUE;
   }
   return true;
}

int RawTriangleSignalAtDecisionShift(const double &ppoSmooth[], const int bars, const int decisionShift)
{
   if(decisionShift < 0 || decisionShift + 2 >= bars)
      return 0;
   double d0 = ppoSmooth[decisionShift];
   double d1 = ppoSmooth[decisionShift + 1];
   double d2 = ppoSmooth[decisionShift + 2];
   if(!IsValidNumber(d0) || !IsValidNumber(d1) || !IsValidNumber(d2))
      return 0;

   if(d0 > d1 && d1 < d2)
      return 1;
   if(d0 < d1 && d1 > d2)
      return -1;
   return 0;
}

void AddZone(PaZone &zones[], const double top, const double bottom, const datetime leftTime, const int direction, const string kind)
{
   if(top <= bottom)
      return;
   int size = ArraySize(zones);
   ArrayResize(zones, size + 1);
   zones[size].top = top;
   zones[size].bottom = bottom;
   zones[size].leftTime = leftTime;
   zones[size].direction = direction;
   zones[size].kind = kind;
}

void RemoveZoneAt(PaZone &zones[], const int index)
{
   int size = ArraySize(zones);
   if(index < 0 || index >= size)
      return;
   for(int i = index; i < size - 1; i++)
      zones[i] = zones[i + 1];
   ArrayResize(zones, size - 1);
}

void TrimZones(PaZone &zones[], const int keep)
{
   int limit = MathMax(0, keep);
   while(ArraySize(zones) > limit)
      RemoveZoneAt(zones, 0);
}

double HighestHigh(const MqlRates &rates[], const int startShift, const int count, const int bars)
{
   double value = -DBL_MAX;
   for(int i = 0; i < count && startShift + i < bars; i++)
      value = MathMax(value, rates[startShift + i].high);
   return value;
}

double LowestLow(const MqlRates &rates[], const int startShift, const int count, const int bars)
{
   double value = DBL_MAX;
   for(int i = 0; i < count && startShift + i < bars; i++)
      value = MathMin(value, rates[startShift + i].low);
   return value;
}

double AtrAtShift(const MqlRates &rates[], const int bars, const int shift, const int len)
{
   int length = MathMax(1, len);
   if(shift + length >= bars)
      return 0.0;
   double sum = 0.0;
   int used = 0;
   for(int i = shift; i < shift + length && i + 1 < bars; i++)
   {
      double tr1 = rates[i].high - rates[i].low;
      double tr2 = MathAbs(rates[i].high - rates[i + 1].close);
      double tr3 = MathAbs(rates[i].low - rates[i + 1].close);
      sum += MathMax(tr1, MathMax(tr2, tr3));
      used++;
   }
   return used > 0 ? sum / used : 0.0;
}

bool IsPriceInZone(const double price, const PaZone &zone, const double tolerance)
{
   return price <= zone.top + tolerance && price >= zone.bottom - tolerance;
}

void CleanseZonesByClose(PaZone &zones[], const double closePrice, const bool highBlock)
{
   for(int i = ArraySize(zones) - 1; i >= 0; i--)
   {
      bool invalid = highBlock ? (closePrice >= zones[i].top) : (closePrice <= zones[i].bottom);
      if(invalid)
         RemoveZoneAt(zones, i);
   }
}

void CleanseFvgByCandle(PaZone &zones[], const MqlRates &bar, const bool bullishFvg)
{
   for(int i = ArraySize(zones) - 1; i >= 0; i--)
   {
      bool filled = bullishFvg ? (bar.low <= zones[i].bottom) : (bar.high >= zones[i].top);
      if(filled)
         RemoveZoneAt(zones, i);
   }
}

void CalculatePivotAt(const MqlRates &rates[], const int bars, const int processShift, const int length, int &state, double &topSwing, double &bottomSwing)
{
   topSwing = 0.0;
   bottomSwing = 0.0;
   if(processShift + length + 1 >= bars)
      return;

   double up = HighestHigh(rates, processShift, length, bars);
   double dn = LowestLow(rates, processShift, length, bars);
   double cHi = rates[processShift + length].high;
   double cLo = rates[processShift + length].low;
   int previous = state;

   if(cHi > up)
      state = 0;
   else if(cLo < dn)
      state = 1;

   if(state == 0 && previous != 0)
      topSwing = cHi;
   if(state == 1 && previous != 1)
      bottomSwing = cLo;
}

void UpdateStructureBreak(const MqlRates &rates[],
                          const int processShift,
                          double &upAxis,
                          double &dnAxis,
                          datetime &upAxisTime,
                          datetime &dnAxisTime,
                          int &upside,
                          int &downside,
                          int &moving,
                          PaEvent &eventOut)
{
   if(processShift + 1 < 0)
      return;

   if(upAxis > 0.0 && rates[processShift].close > upAxis && rates[processShift + 1].close <= upAxis && upside != 0)
   {
      eventOut.direction = 1;
      eventOut.name = moving < 0 ? "CHoCH" : "BOS";
      eventOut.level = upAxis;
      eventOut.pivotTime = upAxisTime;
      eventOut.eventTime = rates[processShift].time;
      upside = 0;
      moving = 1;
   }

   if(dnAxis > 0.0 && rates[processShift].close < dnAxis && rates[processShift + 1].close >= dnAxis && downside != 0)
   {
      eventOut.direction = -1;
      eventOut.name = moving > 0 ? "CHoCH" : "BOS";
      eventOut.level = dnAxis;
      eventOut.pivotTime = dnAxisTime;
      eventOut.eventTime = rates[processShift].time;
      downside = 0;
      moving = -1;
   }
}

void UpdateContextMembership(PaContext &ctx, const double price, const double tolerance)
{
   ctx.inDemand = false;
   ctx.inSupply = false;
   ctx.inBullFvg = false;
   ctx.inBearFvg = false;

   for(int i = ArraySize(g_demandZones) - 1; i >= 0; i--)
      if(IsPriceInZone(price, g_demandZones[i], tolerance))
         ctx.inDemand = true;
   for(int i = ArraySize(g_supplyZones) - 1; i >= 0; i--)
      if(IsPriceInZone(price, g_supplyZones[i], tolerance))
         ctx.inSupply = true;
   for(int i = ArraySize(g_bullFvgZones) - 1; i >= 0; i--)
      if(IsPriceInZone(price, g_bullFvgZones[i], tolerance))
         ctx.inBullFvg = true;
   for(int i = ArraySize(g_bearFvgZones) - 1; i >= 0; i--)
      if(IsPriceInZone(price, g_bearFvgZones[i], tolerance))
         ctx.inBearFvg = true;

   ctx.inUpperAoe = price <= ctx.aoiUpperTop + tolerance && price >= ctx.aoiUpperBottom - tolerance;
   ctx.inLowerAoe = price <= ctx.aoiLowerTop + tolerance && price >= ctx.aoiLowerBottom - tolerance;
   ctx.demandCount = ArraySize(g_demandZones);
   ctx.supplyCount = ArraySize(g_supplyZones);
   ctx.bullFvgCount = ArraySize(g_bullFvgZones);
   ctx.bearFvgCount = ArraySize(g_bearFvgZones);
}

void AnalyzePriceAction(const MqlRates &rates[], const int bars, PaContext &ctx)
{
   ZeroMemory(ctx);
   ArrayResize(g_supplyZones, 0);
   ArrayResize(g_demandZones, 0);
   ArrayResize(g_bullFvgZones, 0);
   ArrayResize(g_bearFvgZones, 0);

   int extState = 0, intState = 0;
   int extMoving = 0, intMoving = 0;
   int extUpside = 1, extDownside = 1, intUpside = 1, intDownside = 1;
   double extUpAxis = 0.0, extDnAxis = 0.0, intUpAxis = 0.0, intDnAxis = 0.0;
   datetime extUpTime = 0, extDnTime = 0, intUpTime = 0, intDnTime = 0;
   int maxLen = MathMax(InpPaExternalSensitivity, InpPaInternalSensitivity);
   int contextBars = MathMax(100, InpPaContextBars);
   int start = MathMin(bars - maxLen - 3, contextBars);

   for(int shift = start; shift >= 0; shift--)
   {
      double extTop = 0.0, extBottom = 0.0, intTop = 0.0, intBottom = 0.0;
      CalculatePivotAt(rates, bars, shift, MathMax(2, InpPaExternalSensitivity), extState, extTop, extBottom);
      CalculatePivotAt(rates, bars, shift, MathMax(2, InpPaInternalSensitivity), intState, intTop, intBottom);

      if(extTop > 0.0)
      {
         int pivotShift = shift + MathMax(2, InpPaExternalSensitivity);
         extUpside = 1;
         extUpAxis = extTop;
         extUpTime = rates[pivotShift].time;
         AddZone(g_supplyZones, extTop, extTop * 0.998, extUpTime, -1, "SUPPLY_OB");
      }
      if(extBottom > 0.0)
      {
         int pivotShift = shift + MathMax(2, InpPaExternalSensitivity);
         extDownside = 1;
         extDnAxis = extBottom;
         extDnTime = rates[pivotShift].time;
         AddZone(g_demandZones, extBottom * 1.002, extBottom, extDnTime, 1, "DEMAND_OB");
      }
      if(intTop > 0.0)
      {
         int pivotShift = shift + MathMax(2, InpPaInternalSensitivity);
         intUpside = 1;
         intUpAxis = intTop;
         intUpTime = rates[pivotShift].time;
      }
      if(intBottom > 0.0)
      {
         int pivotShift = shift + MathMax(2, InpPaInternalSensitivity);
         intDownside = 1;
         intDnAxis = intBottom;
         intDnTime = rates[pivotShift].time;
      }

      CleanseZonesByClose(g_supplyZones, rates[shift].close, true);
      CleanseZonesByClose(g_demandZones, rates[shift].close, false);
      TrimZones(g_supplyZones, MathMax(1, InpPaMaxDrawZones));
      TrimZones(g_demandZones, MathMax(1, InpPaMaxDrawZones));

      if(shift + 2 < bars)
      {
         int s0 = rates[shift].close > rates[shift].open ? 1 : (rates[shift].close < rates[shift].open ? -1 : 0);
         int s1 = rates[shift + 1].close > rates[shift + 1].open ? 1 : (rates[shift + 1].close < rates[shift + 1].open ? -1 : 0);
         int s2 = rates[shift + 2].close > rates[shift + 2].open ? 1 : (rates[shift + 2].close < rates[shift + 2].open ? -1 : 0);
         int signSum = s0 + s1 + s2;
         if(signSum == 3 && rates[shift].low > rates[shift + 2].high)
            AddZone(g_bullFvgZones, rates[shift].low, rates[shift + 2].high, rates[shift + 1].time, 1, "BULL_FVG");
         if(signSum == -3 && rates[shift + 2].low > rates[shift].high)
            AddZone(g_bearFvgZones, rates[shift + 2].low, rates[shift].high, rates[shift + 1].time, -1, "BEAR_FVG");
      }

      CleanseFvgByCandle(g_bullFvgZones, rates[shift], true);
      CleanseFvgByCandle(g_bearFvgZones, rates[shift], false);
      TrimZones(g_bullFvgZones, MathMax(1, InpPaMaxDrawZones));
      TrimZones(g_bearFvgZones, MathMax(1, InpPaMaxDrawZones));

      UpdateStructureBreak(rates, shift, extUpAxis, extDnAxis, extUpTime, extDnTime, extUpside, extDownside, extMoving, ctx.externalEvent);
      UpdateStructureBreak(rates, shift, intUpAxis, intDnAxis, intUpTime, intDnTime, intUpside, intDownside, intMoving, ctx.internalEvent);
   }

   ctx.externalBias = extMoving;
   ctx.internalBias = intMoving;

   int aoiLen = MathMin(50, bars - 1);
   double maxBody = -DBL_MAX, minBody = DBL_MAX;
   for(int i = 0; i < aoiLen; i++)
   {
      maxBody = MathMax(maxBody, MathMax(rates[i].close, rates[i].open));
      minBody = MathMin(minBody, MathMin(rates[i].close, rates[i].open));
   }
   double atr = AtrAtShift(rates, bars, 0, 14);
   ctx.aoiUpperBottom = maxBody;
   ctx.aoiUpperTop = maxBody + atr;
   ctx.aoiLowerTop = minBody;
   ctx.aoiLowerBottom = minBody - atr;

   double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;
   if(mid <= 0.0)
      mid = rates[0].close;
   double tolerance = InpPaZoneTolerancePoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   UpdateContextMembership(ctx, mid, tolerance);

   ctx.summary = "EXT " + DirectionText(ctx.externalBias) + " " + ctx.externalEvent.name
                 + " / INT " + DirectionText(ctx.internalBias) + " " + ctx.internalEvent.name
                 + " / D=" + IntegerToString(ctx.demandCount)
                 + " S=" + IntegerToString(ctx.supplyCount)
                 + " BFVG=" + IntegerToString(ctx.bullFvgCount)
                 + " SFVG=" + IntegerToString(ctx.bearFvgCount);
}

string PriceActionGateText()
{
   switch(InpPriceActionGate)
   {
      case PA_GATE_OFF: return "OFF";
      case PA_GATE_SOFT: return "SOFT";
      case PA_GATE_STRICT: return "STRICT";
      case PA_GATE_ZONE_ONLY: return "ZONE_ONLY";
   }
   return "UNKNOWN";
}

bool PassPriceActionGate(const int direction, const PaContext &ctx, string &reason)
{
   if(InpPriceActionGate == PA_GATE_OFF)
   {
      reason = "pa gate off";
      return true;
   }

   bool externalAligned = InpPaUseExternalBias && (ctx.externalBias == direction || ctx.externalEvent.direction == direction);
   bool internalAligned = InpPaUseInternalBias && (ctx.internalBias == direction || ctx.internalEvent.direction == direction);
   bool biasAligned = externalAligned || internalAligned || (!InpPaUseExternalBias && !InpPaUseInternalBias);

   bool buyZone = ctx.inDemand || ctx.inBullFvg || ctx.inLowerAoe;
   bool sellZone = ctx.inSupply || ctx.inBearFvg || ctx.inUpperAoe;
   bool zoneAligned = direction > 0 ? buyZone : sellZone;

   bool opposing = direction > 0 ? (ctx.inSupply || ctx.inBearFvg) : (ctx.inDemand || ctx.inBullFvg);
   if(InpPaRequireAvoidOpposingZone && opposing)
   {
      reason = "opposing PA zone";
      return false;
   }

   if(InpPriceActionGate == PA_GATE_SOFT)
   {
      bool ok = biasAligned || zoneAligned;
      reason = ok ? "soft ok" : "soft blocked: no bias/zone";
      return ok;
   }
   if(InpPriceActionGate == PA_GATE_STRICT)
   {
      bool ok = biasAligned && zoneAligned;
      reason = ok ? "strict ok" : "strict blocked: need bias+zone";
      return ok;
   }
   if(InpPriceActionGate == PA_GATE_ZONE_ONLY)
   {
      reason = zoneAligned ? "zone ok" : "zone blocked";
      return zoneAligned;
   }

   reason = "unknown gate";
   return false;
}

bool IsManagedPositionSelected()
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
      if(!IsManagedPositionSelected())
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
      if(IsManagedPositionSelected())
         trade.PositionClose(ticket);
   }
}

void CloseOneManagedPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPositionSelected())
      {
         trade.PositionClose(ticket);
         return;
      }
   }
}

void CloseManagedPositionsByDirection(const int direction)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPositionSelected())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      int posDirection = type == POSITION_TYPE_BUY ? 1 : -1;
      if(posDirection == direction)
         trade.PositionClose(ticket);
   }
}

double NormalizeVolume(const double requested)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double lot = MathMax(minLot, MathMin(maxLot, requested));
   lot = MathFloor(lot / step + 1e-8) * step;
   return NormalizeDouble(lot, 8);
}

int EffectiveStopLossPoints()
{
   int configured = MathMax(1, InpStopLossPoints);
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int brokerMin = MathMax(stopsLevel, freezeLevel) + 10;
   int effective = MathMax(configured, brokerMin);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double refPrice = (bid > 0.0 && ask > 0.0) ? (bid + ask) * 0.5 : MathMax(bid, ask);
   if(InpCatastrophicStopPercent > 0.0 && point > 0.0 && refPrice > 0.0)
   {
      int percentPoints = (int)MathCeil((refPrice * (InpCatastrophicStopPercent / 100.0)) / point);
      effective = MathMax(effective, percentPoints);
   }

   return effective;
}

double NormalizeTradePrice(const double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits);
}

bool OpenTrade(const int direction)
{
   double lot = NormalizeVolume(InpLot);
   if(lot <= 0.0)
   {
      Print("FibSystem EA invalid lot ", InpLot);
      return false;
   }

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = direction > 0 ? ask : bid;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl = 0.0;
   double tp = 0.0;
   int slPoints = EffectiveStopLossPoints();
   sl = direction > 0 ? bid - slPoints * point : ask + slPoints * point;
   sl = NormalizeTradePrice(sl);
   if(InpTakeProfitPoints > 0)
      tp = NormalizeTradePrice(direction > 0 ? price + InpTakeProfitPoints * point : price - InpTakeProfitPoints * point);

   bool ok = trade.PositionOpen(_Symbol, type, lot, price, sl, tp, "FibSystemRawTri");
   if(!ok)
   {
      Print("FibSystem EA open failed dir=", DirectionText(direction),
            " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription(),
            " bid=", DoubleToString(bid, _Digits),
            " ask=", DoubleToString(ask, _Digits),
            " sl=", DoubleToString(sl, _Digits),
            " sl_points=", slPoints,
            " stops=", (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
            " freeze=", (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
      return false;
   }
   g_lastExecutionPrice = trade.ResultPrice() > 0.0 ? trade.ResultPrice() : price;
   g_lastExecutionTime = TimeCurrent();
   g_lastOpenedTicket = trade.ResultOrder();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != RuntimeMagic())
         continue;
      g_lastOpenedTicket = ticket;
      g_lastExecutionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      g_lastExecutionTime = (datetime)PositionGetInteger(POSITION_TIME);
      break;
   }
   Print("FibSystem EA order opened dir=", DirectionText(direction),
         " bid=", DoubleToString(bid, _Digits),
         " ask=", DoubleToString(ask, _Digits),
         " price=", DoubleToString(price, _Digits),
         " sl=", DoubleToString(sl, _Digits),
         " sl_points=", slPoints,
         " catastrophic_pct=", DoubleToString(InpCatastrophicStopPercent, 2),
         " stops=", (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
         " freeze=", (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   g_lastAcceptedDirection = direction;
   return true;
}

double ManagedOpenPnl()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPositionSelected())
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

bool GetManagedOpenPosition(ulong &ticket, int &direction, double &entryPrice, datetime &entryTime, double &pnl)
{
   ticket = 0;
   direction = 0;
   entryPrice = 0.0;
   entryTime = 0;
   pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0 || !PositionSelectByTicket(posTicket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != RuntimeMagic())
         continue;
      ticket = posTicket;
      direction = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      return true;
   }
   return false;
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

void DrawArrow(const string tag, const int direction, const datetime drawTime, const double highPrice, const double lowPrice, const string text)
{
   if(!InpDrawExecutionArrows)
      return;
   string side = DirectionText(direction);
   string stamp = IntegerToString((int)drawTime) + "_" + side + "_" + tag;
   double pad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 35.0, MathAbs(highPrice - lowPrice) * 0.50);
   double arrowPrice = direction > 0 ? lowPrice - pad : highPrice + pad;
   double labelPrice = direction > 0 ? arrowPrice - pad * 0.70 : arrowPrice + pad * 0.70;
   color clr = direction > 0 ? clrLime : clrTomato;
   int arrowCode = direction > 0 ? 233 : 234;
   string arrowName = PREFIX + "ARW_" + stamp;
   string textName = PREFIX + "TXT_" + stamp;

   if(ObjectFind(0, arrowName) < 0)
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, drawTime, arrowPrice);
   ObjectMove(0, arrowName, 0, drawTime, arrowPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);

   if(ObjectFind(0, textName) < 0)
      ObjectCreate(0, textName, OBJ_TEXT, 0, drawTime, labelPrice);
   ObjectMove(0, textName, 0, drawTime, labelPrice);
   ObjectSetString(0, textName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
}

void DrawActualExecutionMarker(const int direction, const datetime execTime, const double execPrice, const string text)
{
   if(!InpDrawActualExecutionMarker || execTime <= 0 || execPrice <= 0.0)
      return;
   string stamp = IntegerToString((int)execTime) + "_" + DirectionText(direction) + "_ACTUAL";
   string arrowName = PREFIX + "ACTUAL_" + stamp;
   string textName = PREFIX + "ACTUAL_TXT_" + stamp;
   color clr = direction > 0 ? C'40,220,255' : C'255,205,60';
   int arrowCode = direction > 0 ? 241 : 242;
   double pad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 25.0, execPrice * 0.00015);
   double textPrice = direction > 0 ? execPrice - pad : execPrice + pad;

   if(ObjectFind(0, arrowName) < 0)
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, execTime, execPrice);
   ObjectMove(0, arrowName, 0, execTime, execPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);

   if(ObjectFind(0, textName) < 0)
      ObjectCreate(0, textName, OBJ_TEXT, 0, execTime, textPrice);
   ObjectMove(0, textName, 0, execTime, textPrice);
   ObjectSetString(0, textName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
}

void DeleteArrowObjects(const string tag, const int direction, const datetime drawTime)
{
   string stamp = IntegerToString((int)drawTime) + "_" + DirectionText(direction) + "_" + tag;
   ObjectDelete(0, PREFIX + "ARW_" + stamp);
   ObjectDelete(0, PREFIX + "TXT_" + stamp);
}

void DeleteActualExecutionMarker(const int direction, const datetime execTime)
{
   string stamp = IntegerToString((int)execTime) + "_" + DirectionText(direction) + "_ACTUAL";
   ObjectDelete(0, PREFIX + "ACTUAL_" + stamp);
   ObjectDelete(0, PREFIX + "ACTUAL_TXT_" + stamp);
}

void DeleteLiveProvisionalObjects()
{
   if(!InpRemoveVanishedLiveSignalObjects || !g_liveProvisionalActive)
      return;
   DeleteArrowObjects("LIVE_SIGNAL", g_liveProvisionalDirection, g_liveProvisionalDecisionTime);
   DeleteArrowObjects("LIVE_PIVOT", g_liveProvisionalDirection, g_liveProvisionalVisualTime);
   if(g_liveProvisionalExecutionTime > 0)
      DeleteActualExecutionMarker(g_liveProvisionalDirection, g_liveProvisionalExecutionTime);
}

void ClearLiveRecord(const int direction)
{
   if(direction > 0)
   {
      g_liveBuyDecisionTime = 0;
      g_liveBuyVisualTime = 0;
      g_liveBuyExecutionTime = 0;
   }
   else if(direction < 0)
   {
      g_liveSellDecisionTime = 0;
      g_liveSellVisualTime = 0;
      g_liveSellExecutionTime = 0;
   }
}

void DeleteLiveRecordObjects(const int direction, const datetime decisionTime, const datetime visualTime, const datetime execTime)
{
   if(decisionTime > 0)
      DeleteArrowObjects("LIVE_SIGNAL", direction, decisionTime);
   if(visualTime > 0)
      DeleteArrowObjects("LIVE_PIVOT", direction, visualTime);
   if(execTime > 0)
      DeleteActualExecutionMarker(direction, execTime);
}

void ReconcileLiveRecordsAfterBarClose(const datetime closedDecisionTime, const int confirmedDirection)
{
   if(InpSignalBarMode != FIB_SIGNAL_BAR_LIVE)
      return;

   if(g_liveBuyDecisionTime == closedDecisionTime)
   {
      if(confirmedDirection != 1)
      {
         CloseManagedPositionsByDirection(1);
         if(InpRemoveVanishedLiveSignalObjects)
            DeleteLiveRecordObjects(1, g_liveBuyDecisionTime, g_liveBuyVisualTime, g_liveBuyExecutionTime);
         Print("FibSystem EA live reconcile removed BUY decision=", TimeToString(closedDecisionTime),
               " confirmed=", DirectionText(confirmedDirection));
      }
      else
      {
         Print("FibSystem EA live reconcile kept BUY decision=", TimeToString(closedDecisionTime));
      }
      ClearLiveRecord(1);
   }

   if(g_liveSellDecisionTime == closedDecisionTime)
   {
      if(confirmedDirection != -1)
      {
         CloseManagedPositionsByDirection(-1);
         if(InpRemoveVanishedLiveSignalObjects)
            DeleteLiveRecordObjects(-1, g_liveSellDecisionTime, g_liveSellVisualTime, g_liveSellExecutionTime);
         Print("FibSystem EA live reconcile removed SELL decision=", TimeToString(closedDecisionTime),
               " confirmed=", DirectionText(confirmedDirection));
      }
      else
      {
         Print("FibSystem EA live reconcile kept SELL decision=", TimeToString(closedDecisionTime));
      }
      ClearLiveRecord(-1);
   }
}

void ProcessSignal(const MqlRates &rates[], const int bars, const int decisionShift, const int direction)
{
   int visualShift = decisionShift + 1;
   if(visualShift >= bars)
      return;
   datetime decisionTime = rates[decisionShift].time;
   datetime visualTime = rates[visualShift].time;
   bool liveDecision = decisionShift == 0;
   string decisionMode = liveDecision ? "LIVE" : "CLOSED";
   // The Pine triangle uses offset=-1 and is backplotted to visualShift.
   // For live trading audit, draw actionable signals on the decision bar.
   datetime actionDrawTime = decisionTime;
   double actionHigh = rates[decisionShift].high;
   double actionLow = rates[decisionShift].low;
   double signalVisualClose = rates[visualShift].close;
   double signalDecisionClose = rates[decisionShift].close;

   if(WasProcessed(decisionTime, direction))
      return;

   g_lastSignalText = decisionMode + " " + DirectionText(direction)
                      + " visual=" + TimeToString(visualTime, TIME_DATE | TIME_MINUTES)
                      + " decision=" + TimeToString(decisionTime, TIME_DATE | TIME_MINUTES);

   if(InpBlockSameDirectionUntilReverse && g_lastSignalDirection == direction)
   {
      MarkProcessed(decisionTime, direction);
      g_lastActionText = decisionMode + " blocked same direction " + DirectionText(direction);
      if(InpDrawBlockedSignalArrows)
         DrawArrow(decisionMode + "_BLOCK", direction, actionDrawTime, actionHigh, actionLow, decisionMode + " BLOCK " + DirectionText(direction));
      Print("FibSystem EA same-direction signal blocked dir=", DirectionText(direction), " mode=", decisionMode, " decision=", TimeToString(decisionTime));
      return;
   }

   string paReason = "";
   if(!PassPriceActionGate(direction, g_lastPaContext, paReason))
   {
      MarkProcessed(decisionTime, direction);
      g_lastActionText = decisionMode + " PA blocked " + DirectionText(direction) + " / " + paReason;
      DrawArrow(decisionMode + "_PA_BLOCK", direction, actionDrawTime, actionHigh, actionLow, decisionMode + " PA BLOCK " + DirectionText(direction));
      Print("FibSystem PA EA blocked dir=", DirectionText(direction),
            " mode=", decisionMode,
            " reason=", paReason,
            " ctx=", g_lastPaContext.summary,
            " decision=", TimeToString(decisionTime));
      return;
   }

   if(!IsTradingTimeOpen())
   {
      MarkProcessed(decisionTime, direction);
      g_lastActionText = decisionMode + " window blocked " + DirectionText(direction);
      DrawArrow(decisionMode + "_WINDOW", direction, actionDrawTime, actionHigh, actionLow, decisionMode + " WINDOW " + DirectionText(direction));
      Print("FibSystem EA trading window blocked dir=", DirectionText(direction), " mode=", decisionMode, " decision=", TimeToString(decisionTime));
      return;
   }

   if(InpCloseExistingOnNewSignal)
      CloseManagedPositions();

   int priorSignalDirection = g_lastSignalDirection;
   bool opened = OpenTrade(direction);
   MarkProcessed(decisionTime, direction);
   if(opened)
   {
      g_lastSignalVisualClose = signalVisualClose;
      g_lastSignalDecisionClose = signalDecisionClose;
      g_lastSignalVisualTime = visualTime;
      g_lastSignalDecisionTime = decisionTime;
      g_lastSignalDirection = direction;
      if(decisionShift == 0)
         ArmLiveProvisional(decisionTime, visualTime, direction, priorSignalDirection, g_lastExecutionTime, g_lastExecutionPrice);
      else
         ClearLiveProvisional();
      g_lastActionText = decisionMode + " opened " + DirectionText(direction);
      DrawArrow(decisionMode + "_SIGNAL", direction, actionDrawTime, actionHigh, actionLow, decisionMode + " SIGNAL " + DirectionText(direction));
      if(InpDrawBackplotPivotSignal)
         DrawArrow(decisionMode + "_PIVOT", direction, visualTime, rates[visualShift].high, rates[visualShift].low, "PIVOT " + DirectionText(direction));
      DrawActualExecutionMarker(direction, g_lastExecutionTime, g_lastExecutionPrice, "EXEC " + DirectionText(direction));
      Print("FibSystem EA opened ", DirectionText(direction),
            " mode=", decisionMode,
            " visual=", TimeToString(visualTime),
            " signal_bar_close=", DoubleToString(signalVisualClose, _Digits),
            " decision=", TimeToString(decisionTime),
            " decision_close=", DoubleToString(signalDecisionClose, _Digits),
            " exec=", TimeToString(g_lastExecutionTime, TIME_DATE | TIME_SECONDS),
            " exec_price=", DoubleToString(g_lastExecutionPrice, _Digits),
            " exec_vs_signal_close=", DoubleToString(g_lastExecutionPrice - signalVisualClose, _Digits),
            " exec_vs_decision_close=", DoubleToString(g_lastExecutionPrice - signalDecisionClose, _Digits));
   }
   else
   {
      g_lastActionText = decisionMode + " open failed " + DirectionText(direction);
      DrawArrow(decisionMode + "_FAIL", direction, actionDrawTime, actionHigh, actionLow, decisionMode + " FAIL " + DirectionText(direction));
   }
}

bool LoadRatesAndPpo(MqlRates &rates[], double &ppoSmooth[], int &bars)
{
   bars = CopyRates(_Symbol, _Period, 0, BarsToCopy(), rates);
   if(bars <= 0)
      return false;
   ArraySetAsSeries(rates, true);
   return CalculatePpo(rates, bars, ppoSmooth);
}

void BaselineStartupSignal()
{
   MqlRates rates[];
   double ppoSmooth[];
   int bars = 0;
   if(!LoadRatesAndPpo(rates, ppoSmooth, bars))
      return;

   // Never consume the current live bar as startup baseline. In LiveBar mode
   // shift=0 must remain executable on the first tick if a raw triangle is active.
   int startShift = 1;
   int maxShift = MathMin(bars - 3, MathMax(100, InpSignalCalcBars));
   for(int shift = startShift; shift <= maxShift; shift++)
   {
      int direction = RawTriangleSignalAtDecisionShift(ppoSmooth, bars, shift);
      if(direction == 0)
         continue;
      datetime decisionTime = rates[shift].time;
      int visualShift = shift + 1;
      g_lastSignalText = DirectionText(direction) + " startup visual=" + TimeToString(rates[visualShift].time, TIME_DATE | TIME_MINUTES);
      if(!InpTradeLatestSignalOnAttach)
      {
         MarkProcessed(decisionTime, direction);
         g_lastSignalDirection = direction;
         g_lastActionText = "startup baseline no execution " + DirectionText(direction);
         Print("FibSystem EA startup baseline dir=", DirectionText(direction), " visual=", TimeToString(rates[visualShift].time), " decision=", TimeToString(decisionTime), " no historical execution emitted.");
      }
      else
      {
         g_lastActionText = "startup latest signal is executable";
      }
      return;
   }
   g_lastSignalText = "NONE within startup lookback";
}

void DrawRecentSignalHistory()
{
   if(!InpDrawRecentSignalsOnStart || InpStartupSignalCount <= 0)
      return;

   MqlRates rates[];
   double ppoSmooth[];
   int bars = 0;
   if(!LoadRatesAndPpo(rates, ppoSmooth, bars))
      return;

   int drawn = 0;
   int lastDrawnDirection = 0;
   for(int shift = 1; shift < bars - 3 && drawn < InpStartupSignalCount; shift++)
   {
      int direction = RawTriangleSignalAtDecisionShift(ppoSmooth, bars, shift);
      if(direction == 0)
         continue;
      if(InpBlockSameDirectionUntilReverse && direction == lastDrawnDirection)
         continue;
      int visualShift = shift + 1;
      DrawArrow("HIST" + IntegerToString(drawn + 1), direction, rates[shift].time, rates[shift].high, rates[shift].low, "HIST DECISION " + DirectionText(direction));
      if(InpDrawBackplotPivotSignal)
         DrawArrow("HIST_PIVOT" + IntegerToString(drawn + 1), direction, rates[visualShift].time, rates[visualShift].high, rates[visualShift].low, "HIST PIVOT " + DirectionText(direction));
      lastDrawnDirection = direction;
      drawn++;
   }
   Print("FibSystem EA history raw PPO triangle overlay drawn=", drawn);
}

void DeletePaContextObjects()
{
   string paPrefix = PREFIX + "PA_";
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, paPrefix) == 0)
         ObjectDelete(0, name);
   }
}

void DrawPaBox(const string name, const datetime leftTime, const double top, const double bottom, const color clr)
{
   if(top <= bottom)
      return;
   string obj = PREFIX + "PA_" + name;
   datetime rightTime = TimeCurrent() + PeriodSeconds(_Period) * 8;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE, 0, leftTime, top, rightTime, bottom);
   ObjectMove(0, obj, 0, leftTime, top);
   ObjectMove(0, obj, 1, rightTime, bottom);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_BACK, true);
   ObjectSetInteger(0, obj, OBJPROP_FILL, true);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, 1);
}

void DrawPaText(const string name, const datetime when, const double price, const string text, const color clr)
{
   string obj = PREFIX + "PA_" + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TEXT, 0, when, price);
   ObjectMove(0, obj, 0, when, price);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
}

void DrawPaEvent(const string prefix, const PaEvent &eventData, const color clr)
{
   if(eventData.direction == 0 || eventData.eventTime == 0 || eventData.pivotTime == 0)
      return;
   string lineName = PREFIX + "PA_" + prefix + "_LINE";
   if(ObjectFind(0, lineName) < 0)
      ObjectCreate(0, lineName, OBJ_TREND, 0, eventData.pivotTime, eventData.level, eventData.eventTime, eventData.level);
   ObjectMove(0, lineName, 0, eventData.pivotTime, eventData.level);
   ObjectMove(0, lineName, 1, eventData.eventTime, eventData.level);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
   DrawPaText(prefix + "_TXT", eventData.eventTime, eventData.level, prefix + " " + eventData.name + " " + DirectionText(eventData.direction), clr);
}

void DrawPriceActionContext(const PaContext &ctx)
{
   if(!InpPaDrawContext)
      return;
   DeletePaContextObjects();

   int maxZones = MathMax(1, InpPaMaxDrawZones);
   int drawn = 0;
   for(int i = ArraySize(g_demandZones) - 1; i >= 0 && drawn < maxZones; i--, drawn++)
      DrawPaBox("DEMAND_" + IntegerToString(drawn), g_demandZones[i].leftTime, g_demandZones[i].top, g_demandZones[i].bottom, C'18,120,88');

   drawn = 0;
   for(int i = ArraySize(g_supplyZones) - 1; i >= 0 && drawn < maxZones; i--, drawn++)
      DrawPaBox("SUPPLY_" + IntegerToString(drawn), g_supplyZones[i].leftTime, g_supplyZones[i].top, g_supplyZones[i].bottom, C'140,35,62');

   drawn = 0;
   for(int i = ArraySize(g_bullFvgZones) - 1; i >= 0 && drawn < maxZones; i--, drawn++)
      DrawPaBox("BULL_FVG_" + IntegerToString(drawn), g_bullFvgZones[i].leftTime, g_bullFvgZones[i].top, g_bullFvgZones[i].bottom, C'112,115,18');

   drawn = 0;
   for(int i = ArraySize(g_bearFvgZones) - 1; i >= 0 && drawn < maxZones; i--, drawn++)
      DrawPaBox("BEAR_FVG_" + IntegerToString(drawn), g_bearFvgZones[i].leftTime, g_bearFvgZones[i].top, g_bearFvgZones[i].bottom, C'125,82,18');

   datetime left = iTime(_Symbol, _Period, MathMin(50, Bars(_Symbol, _Period) - 1));
   DrawPaBox("AOE_UPPER", left, ctx.aoiUpperTop, ctx.aoiUpperBottom, C'90,20,58');
   DrawPaBox("AOE_LOWER", left, ctx.aoiLowerTop, ctx.aoiLowerBottom, C'12,75,70');
   DrawPaEvent("EXT", ctx.externalEvent, ctx.externalEvent.direction > 0 ? clrLime : clrTomato);
   DrawPaEvent("INT", ctx.internalEvent, ctx.internalEvent.direction > 0 ? C'80,220,255' : C'255,170,80');
}

void RefreshPriceActionContextIfNeeded(const MqlRates &rates[], const int bars)
{
   if(InpPriceActionGate == PA_GATE_OFF && !InpPaDrawContext)
      return;

   bool newBar = bars > 0 && rates[0].time != g_lastPaBuildBarTime;
   bool needsFullRebuild = !g_paContextReady || InpPaRebuildEveryTick || newBar;
   double tolerance = InpPaZoneTolerancePoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;
   if(mid <= 0.0 && bars > 0)
      mid = rates[0].close;

   if(needsFullRebuild)
   {
      AnalyzePriceAction(rates, bars, g_lastPaContext);
      g_lastPaBuildBarTime = bars > 0 ? rates[0].time : 0;
      g_paContextReady = true;
   }
   else
   {
      UpdateContextMembership(g_lastPaContext, mid, tolerance);
   }

   if(!InpPaDrawContext)
      return;

   datetime now = TimeCurrent();
   bool redrawByTime = (now - g_lastPaDrawTime) >= MathMax(1, InpPaRedrawSeconds);
   if(needsFullRebuild || redrawByTime)
   {
      DrawPriceActionContext(g_lastPaContext);
      g_lastPaDrawTime = now;
   }
}

void ValidateLiveProvisionalAfterBarClose(const MqlRates &rates[], const double &ppoSmooth[], const int bars)
{
   if(InpSignalBarMode != FIB_SIGNAL_BAR_LIVE || !g_liveProvisionalActive)
      return;
   if(bars < 4)
      return;

   // The decision bar that was live at entry is shift=1 after a new candle opens.
   int confirmedDirection = RawTriangleSignalAtDecisionShift(ppoSmooth, bars, 1);
   ReconcileLiveRecordsAfterBarClose(rates[1].time, confirmedDirection);

   if(rates[1].time != g_liveProvisionalDecisionTime)
      return;
   if(confirmedDirection == g_liveProvisionalDirection)
   {
      g_lastActionText = "live signal confirmed on close " + DirectionText(confirmedDirection);
      Print("FibSystem EA live provisional confirmed dir=", DirectionText(confirmedDirection),
            " decision=", TimeToString(g_liveProvisionalDecisionTime));
      ClearLiveProvisional();
      return;
   }

   CloseManagedPositionsByDirection(g_liveProvisionalDirection);
   DeleteLiveProvisionalObjects();
   g_lastAcceptedDirection = ManagedPositionDirection();
   g_lastSignalDirection = g_liveProvisionalPriorSignalDirection != 0 ? g_liveProvisionalPriorSignalDirection : g_lastAcceptedDirection;
   g_lastActionText = "closed vanished live signal " + DirectionText(g_liveProvisionalDirection);
   Print("FibSystem EA live provisional vanished; closed dir=", DirectionText(g_liveProvisionalDirection),
         " decision=", TimeToString(g_liveProvisionalDecisionTime),
         " confirmed=", DirectionText(confirmedDirection));
   ClearLiveProvisional();
}

void ProcessSignals()
{
   MqlRates rates[];
   double ppoSmooth[];
   int bars = 0;
   if(!LoadRatesAndPpo(rates, ppoSmooth, bars))
      return;

   RefreshPriceActionContextIfNeeded(rates, bars);

   if(InpSignalBarMode == FIB_SIGNAL_BAR_CLOSED)
   {
      if(g_lastBarTime == rates[0].time)
         return;
      g_lastBarTime = rates[0].time;
      int direction = RawTriangleSignalAtDecisionShift(ppoSmooth, bars, 1);
      if(direction != 0)
         ProcessSignal(rates, bars, 1, direction);
      return;
   }

   if(g_lastBarTime != rates[0].time)
   {
      g_lastBarTime = rates[0].time;
      ValidateLiveProvisionalAfterBarClose(rates, ppoSmooth, bars);
      int closedDirection = RawTriangleSignalAtDecisionShift(ppoSmooth, bars, 1);
      if(closedDirection != 0)
         ProcessSignal(rates, bars, 1, closedDirection);
   }

   int direction = RawTriangleSignalAtDecisionShift(ppoSmooth, bars, 0);
   if(direction != 0)
      ProcessSignal(rates, bars, 0, direction);
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
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
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
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C'130,105,255');
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
}

void CreateEdit(const string name, const int x, const int y, const int w, const int h, const string text)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'20,18,54');
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C'120,82,255');
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
}

void DrawDashboard()
{
   if(!InpShowDashboard)
      return;

   string bg = PREFIX + "DASH_BG";
   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 24);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 274);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'10,12,38');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'125,84,255');
   ObjectSetInteger(0, bg, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);

   CreateLabel("TITLE", 24, 36, "FibSystem + Price Action Context EA", C'168,185,255', 11);
   CreateLabel("SUB", 24, 56, _Symbol + " " + EnumToString(_Period) + " / magic " + IntegerToString(RuntimeMagic()), C'135,225,255', 8);
   CreateButton("BTN_CLOSE_ALL", 300, 34, 126, 24, "CLOSE ALL", C'92,38,155');
   CreateButton("BTN_CLOSE_ONE", 300, 62, 126, 24, "CLOSE ONE", C'31,80,160');
   CreateEdit("EDIT_START", 244, 174, 62, 22, g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime);
   CreateEdit("EDIT_END", 314, 174, 62, 22, g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime);
   CreateButton("BTN_APPLY_TIME", 382, 174, 44, 22, "APPLY", C'68,45,170');
}

void UpdateDashboard()
{
   if(!InpShowDashboard)
      return;

   double total = HistoryPnl(0) + ManagedOpenPnl();
   double daily = HistoryPnl(DayStart()) + ManagedOpenPnl();
   double open = ManagedOpenPnl();
   ulong activeTicket = 0;
   int activeDirection = 0;
   double activeEntry = 0.0;
   datetime activeEntryTime = 0;
   double activePnl = 0.0;
   bool hasOpenTrade = GetManagedOpenPosition(activeTicket, activeDirection, activeEntry, activeEntryTime, activePnl);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equityPeak <= 0.0 || equity > g_equityPeak)
      g_equityPeak = equity;
   g_maxDd = MathMax(g_maxDd, g_equityPeak - equity);

   CreateLabel("MODE", 24, 82, "Mode: " + string(InpSignalBarMode == FIB_SIGNAL_BAR_CLOSED ? "CLOSED BAR" : "LIVE BAR") + " / PA " + PriceActionGateText() + " / same-dir " + string(InpBlockSameDirectionUntilReverse ? "ON" : "OFF"), C'210,212,255', 8);
   CreateLabel("PNL1", 24, 106, "Total PnL: " + DoubleToString(total, 2) + "   Daily: " + DoubleToString(daily, 2) + "   Open: " + DoubleToString(open, 2), C'105,255,210', 9);
   CreateLabel("PNL2", 24, 128, "Max DD(chart EA): " + DoubleToString(g_maxDd, 2) + "   Open dir: " + DirectionText(ManagedPositionDirection()) + "   SL pts: " + IntegerToString(EffectiveStopLossPoints()) + " / cat " + DoubleToString(InpCatastrophicStopPercent, 2) + "%", C'255,210,135', 8);
   CreateLabel("SIG", 24, 150, "Last raw triangle: " + g_lastSignalText, C'210,230,255', 8);
   CreateLabel("WIN", 24, 178, "Trading window: " + TradingWindowText(), IsTradingTimeOpen() ? C'90,255,160' : C'255,95,140', 8);
   string provisional = g_liveProvisionalActive
                        ? (" provisional=" + DirectionText(g_liveProvisionalDirection) + " until close")
                        : "";
   CreateLabel("PA", 24, 196, "PA: " + g_lastPaContext.summary, C'180,235,210', 8);
   CreateLabel("ACT", 24, 218, "Action: " + g_lastActionText + "   accepted=" + DirectionText(g_lastAcceptedDirection) + " signal=" + DirectionText(g_lastSignalDirection) + provisional, C'185,165,255', 8);
   string audit = "Audit: no active managed trade";
   if(hasOpenTrade)
   {
      audit = "Audit ticket=" + IntegerToString((long)activeTicket)
            + " " + DirectionText(activeDirection)
            + " entry=" + DoubleToString(activeEntry, _Digits)
            + " pnl=" + DoubleToString(activePnl, 2);
      if(g_lastOpenedTicket == activeTicket && g_lastSignalVisualClose > 0.0)
      {
         audit += " sigClose=" + DoubleToString(g_lastSignalVisualClose, _Digits)
               + " decClose=" + DoubleToString(g_lastSignalDecisionClose, _Digits)
               + " dSig=" + DoubleToString(activeEntry - g_lastSignalVisualClose, _Digits)
               + " dDec=" + DoubleToString(activeEntry - g_lastSignalDecisionClose, _Digits);
      }
      else
      {
         audit += " sig/dec=unknown";
      }
   }
   CreateLabel("AUDIT", 24, 240, audit, C'135,225,255', 8);
}

void DeleteDashboardObjects()
{
   string names[] = {
      "DASH_BG",
      "TITLE",
      "SUB",
      "MODE",
      "PNL1",
      "PNL2",
      "SIG",
      "WIN",
      "PA",
      "ACT",
      "AUDIT",
      "BTN_CLOSE_ALL",
      "BTN_CLOSE_ONE",
      "EDIT_START",
      "EDIT_END",
      "BTN_APPLY_TIME"
   };
   for(int i = 0; i < ArraySize(names); i++)
      ObjectDelete(0, PREFIX + names[i]);
}

int OnInit()
{
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   g_tradeStartTimeRuntime = InpTradeStartTime;
   g_tradeEndTimeRuntime = InpTradeEndTime;
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   HydrateDirectionFromOpenPosition();
   BaselineStartupSignal();
   DrawRecentSignalHistory();
   DrawDashboard();
   UpdateDashboard();

   Print("FibSystem PriceActionContext EA initialized symbol=", _Symbol,
         " tf=", EnumToString(_Period),
         " mode=", (InpSignalBarMode == FIB_SIGNAL_BAR_CLOSED ? "closed" : "live"),
         " pa_gate=", PriceActionGateText(),
         " fast=", InpFastLength,
         " slow=", InpSlowLength,
         " smoother=", InpSmoother,
         " runtime_magic=", RuntimeMagic(),
         " lot=", DoubleToString(InpLot, 8),
         " stop_points=", InpStopLossPoints,
         " catastrophic_pct=", DoubleToString(InpCatastrophicStopPercent, 2),
         " effective_sl_points=", EffectiveStopLossPoints());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteDashboardObjects();
   Print("FibSystem RawTriangle EA deinit reason=", reason);
}

void OnTick()
{
   ProcessSignals();
   UpdateDashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT)
      return;

   if(sparam == PREFIX + "BTN_CLOSE_ALL")
   {
      CloseManagedPositions();
      g_lastAcceptedDirection = ManagedPositionDirection();
      if(g_lastAcceptedDirection != 0)
         g_lastSignalDirection = g_lastAcceptedDirection;
      ClearLiveProvisional();
      g_lastActionText = "manual close all";
      UpdateDashboard();
      return;
   }
   if(sparam == PREFIX + "BTN_CLOSE_ONE")
   {
      CloseOneManagedPosition();
      g_lastAcceptedDirection = ManagedPositionDirection();
      if(g_lastAcceptedDirection != 0)
         g_lastSignalDirection = g_lastAcceptedDirection;
      if(g_lastAcceptedDirection == 0)
         ClearLiveProvisional();
      g_lastActionText = "manual close one";
      UpdateDashboard();
      return;
   }
   if(sparam == PREFIX + "BTN_APPLY_TIME")
   {
      string startObj = PREFIX + "EDIT_START";
      string endObj = PREFIX + "EDIT_END";
      g_tradeStartTimeRuntime = ObjectGetString(0, startObj, OBJPROP_TEXT);
      g_tradeEndTimeRuntime = ObjectGetString(0, endObj, OBJPROP_TEXT);
      g_lastActionText = "window updated " + g_tradeStartTimeRuntime + "-" + g_tradeEndTimeRuntime;
      UpdateDashboard();
      return;
   }
}
