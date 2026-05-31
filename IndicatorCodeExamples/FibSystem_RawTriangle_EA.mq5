//+------------------------------------------------------------------+
//| FibSystem raw PPO triangle EA                                    |
//| Signal source: IndicatorCodeExamples/FibSystem.pine              |
//| Trades the raw PPO high/low triangles only.                      |
//| lime triangleup  = PPO local low  = BUY                          |
//| red triangledown = PPO local high = SELL                         |
//+------------------------------------------------------------------+
#property strict
#property version "1.18"

#include <Trade/Trade.mqh>

enum FIB_SIGNAL_BAR_MODE
{
   FIB_SIGNAL_BAR_LIVE = 0,
   FIB_SIGNAL_BAR_CLOSED = 1
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
double   g_lastExecutionPrice = 0.0;
datetime g_lastExecutionTime = 0;
double   g_lastSignalVisualClose = 0.0;
double   g_lastSignalDecisionClose = 0.0;
datetime g_lastSignalVisualTime = 0;
datetime g_lastSignalDecisionTime = 0;
ulong    g_lastOpenedTicket = 0;

string PREFIX = "FIB_RAW_TRI_EA_";

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
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 250);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'10,12,38');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'125,84,255');
   ObjectSetInteger(0, bg, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);

   CreateLabel("TITLE", 24, 36, "FibSystem Raw PPO Triangle EA", C'168,185,255', 11);
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

   CreateLabel("MODE", 24, 82, "Mode: " + string(InpSignalBarMode == FIB_SIGNAL_BAR_CLOSED ? "CLOSED BAR" : "LIVE BAR") + " / same-dir block " + string(InpBlockSameDirectionUntilReverse ? "ON" : "OFF"), C'210,212,255', 8);
   CreateLabel("PNL1", 24, 106, "Total PnL: " + DoubleToString(total, 2) + "   Daily: " + DoubleToString(daily, 2) + "   Open: " + DoubleToString(open, 2), C'105,255,210', 9);
   CreateLabel("PNL2", 24, 128, "Max DD(chart EA): " + DoubleToString(g_maxDd, 2) + "   Open dir: " + DirectionText(ManagedPositionDirection()) + "   SL pts: " + IntegerToString(EffectiveStopLossPoints()) + " / cat " + DoubleToString(InpCatastrophicStopPercent, 2) + "%", C'255,210,135', 8);
   CreateLabel("SIG", 24, 150, "Last raw triangle: " + g_lastSignalText, C'210,230,255', 8);
   CreateLabel("WIN", 24, 178, "Trading window: " + TradingWindowText(), IsTradingTimeOpen() ? C'90,255,160' : C'255,95,140', 8);
   string provisional = g_liveProvisionalActive
                        ? (" provisional=" + DirectionText(g_liveProvisionalDirection) + " until close")
                        : "";
   CreateLabel("ACT", 24, 206, "Action: " + g_lastActionText + "   accepted=" + DirectionText(g_lastAcceptedDirection) + " signal=" + DirectionText(g_lastSignalDirection) + provisional, C'185,165,255', 8);
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
   CreateLabel("AUDIT", 24, 228, audit, C'135,225,255', 8);
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
      "ACT",
      "BTN_CLOSE_ALL",
      "BTN_CLOSE_ONE",
      "EDIT_START",
      "EDIT_END",
      "BTN_APPLY_TIME",
      "AUDIT"
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

   Print("FibSystem RawTriangle EA initialized symbol=", _Symbol,
         " tf=", EnumToString(_Period),
         " mode=", (InpSignalBarMode == FIB_SIGNAL_BAR_CLOSED ? "closed" : "live"),
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
