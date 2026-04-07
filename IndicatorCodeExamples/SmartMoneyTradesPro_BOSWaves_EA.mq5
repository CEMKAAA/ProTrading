//+------------------------------------------------------------------+
//| Smart Money Trades Pro EA [BOSWaves]                            |
//| Pine Script v5 -> MQL5 EA conversion                            |
//| Faithful structure/target logic with minimal trade execution    |
//| Opens one position on confirmed BOS/CHoCH break, uses SL/TP3    |
//| TP1/TP2 remain informational, matching original indicator logic |
//+------------------------------------------------------------------+
#property strict
#property copyright "BOSWaves"
#property version   "1.00"

input int    structurePeriod = 20;      // Structure Detection Period
input string confirmationType = "Body"; // Break Confirmation: Body or Wick
input bool   showCHoCH = true;          // Display Change of Character
input bool   showTable = true;          // Show Info Table
input string tablePosition = "Top Right"; // Top Left | Top Right | Bottom Left | Bottom Right

input double lotSize = 0.10;            // Fixed Lot Size
input int    slippagePoints = 20;       // Max Deviation
input long   magicNumber = 20260403;    // EA Magic Number
input double atrMultiplier = 2.0;       // ATR Volatility Multiplier

input color  bullColor = clrMediumSeaGreen;
input color  bearColor = clrTomato;
input color  neutralColor = clrGray;
input color  successColor = clrLimeGreen;
input color  dangerColor = clrCrimson;
input color  bgColor = C'30,30,30';
input color  textColor = clrWhite;

int      g_atrHandle = INVALID_HANDLE;
datetime g_lastBarTime = 0;

double   g_lastHigh = 0.0;
double   g_lastLow = 0.0;
datetime g_lastHighTime = 0;
datetime g_lastLowTime = 0;
int      g_trendDirection = 0;
bool     g_highBreakPending = false;
bool     g_lowBreakPending = false;

double   g_entryLevel = 0.0;
double   g_tp1Level = 0.0;
double   g_tp2Level = 0.0;
double   g_tp3Level = 0.0;
double   g_stopLevel = 0.0;
int      g_tradeDirection = 0; // 1 buy, -1 sell, 0 flat
bool     g_tp1Hit = false;
bool     g_tp2Hit = false;
bool     g_tp3Hit = false;
datetime g_lastTradeSignalTime = 0;
ulong    g_activeTicket = 0;

string   PREFIX = "SMT_BW_";

//+------------------------------------------------------------------+
int OnInit()
{
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle. Error=", GetLastError());
      return(INIT_FAILED);
   }

   DrawDashboard();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   DeleteAllObjects();
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenPosition();
   UpdateVisuals();

   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;

   g_lastBarTime = barTime;
   ProcessNewBar();
}

//+------------------------------------------------------------------+
void ProcessNewBar()
{
   int bars = Bars(_Symbol, PERIOD_CURRENT);
   if(bars < (structurePeriod * 2 + 10))
      return;

   double atr = GetATRValue(1);
   if(atr <= 0.0)
      return;

   double swingHigh = DetectSwingHigh(structurePeriod);
   double swingLow = DetectSwingLow(structurePeriod);

   if(swingHigh > 0.0)
   {
      g_lastHigh = swingHigh;
      g_lastHighTime = iTime(_Symbol, PERIOD_CURRENT, structurePeriod + 1);
      g_highBreakPending = true;
   }
   if(swingLow > 0.0)
   {
      g_lastLow = swingLow;
      g_lastLowTime = iTime(_Symbol, PERIOD_CURRENT, structurePeriod + 1);
      g_lowBreakPending = true;
   }

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);

   bool bullBreak = false;
   bool bearBreak = false;

   if(g_highBreakPending && g_lastHigh > 0.0)
   {
      bool brokenHigh = (StringCompare(confirmationType, "Body", false) == 0) ? (close1 > g_lastHigh) : (high1 > g_lastHigh);
      if(brokenHigh)
      {
         bullBreak = true;
         g_highBreakPending = false;
      }
   }

   if(g_lowBreakPending && g_lastLow > 0.0)
   {
      bool brokenLow = (StringCompare(confirmationType, "Body", false) == 0) ? (close1 < g_lastLow) : (low1 < g_lastLow);
      if(brokenLow)
      {
         bearBreak = true;
         g_lowBreakPending = false;
      }
   }

   int prevTrend = g_trendDirection;
   if(bullBreak)
      g_trendDirection = 1;
   else if(bearBreak)
      g_trendDirection = -1;

   bool isChoch = ((prevTrend == -1 && g_trendDirection == 1) || (prevTrend == 1 && g_trendDirection == -1));

   if(bullBreak && g_lastHigh > 0.0)
      ActivateSignal(1, g_lastHigh, atr, g_lastHighTime, isChoch);
   else if(bearBreak && g_lastLow > 0.0)
      ActivateSignal(-1, g_lastLow, atr, g_lastLowTime, isChoch);
}

//+------------------------------------------------------------------+
void ActivateSignal(const int direction, const double structureLevel, const double atr, const datetime pivotTime, const bool isChoch)
{
   double targetRange = atr * atrMultiplier;
   g_entryLevel = NormalizePrice(structureLevel);
   g_lastTradeSignalTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   g_tradeDirection = direction;
   g_tp1Hit = false;
   g_tp2Hit = false;
   g_tp3Hit = false;

   if(direction > 0)
   {
      g_tp1Level = NormalizePrice(g_entryLevel + targetRange * 0.8);
      g_tp2Level = NormalizePrice(g_entryLevel + targetRange * 1.6);
      g_tp3Level = NormalizePrice(g_entryLevel + targetRange * 2.8);
      g_stopLevel = NormalizePrice(g_entryLevel - targetRange * 1.2);
      DrawBreakObjects(true, pivotTime, g_entryLevel, isChoch, atr);
      Print("Bull structure break: entry=", g_entryLevel, " sl=", g_stopLevel, " tp3=", g_tp3Level);
   }
   else
   {
      g_tp1Level = NormalizePrice(g_entryLevel - targetRange * 0.8);
      g_tp2Level = NormalizePrice(g_entryLevel - targetRange * 1.6);
      g_tp3Level = NormalizePrice(g_entryLevel - targetRange * 2.8);
      g_stopLevel = NormalizePrice(g_entryLevel + targetRange * 1.2);
      DrawBreakObjects(false, pivotTime, g_entryLevel, isChoch, atr);
      Print("Bear structure break: entry=", g_entryLevel, " sl=", g_stopLevel, " tp3=", g_tp3Level);
   }

   ResetTradeObjects();
   DrawTradeObjects();
   ExecuteSignalTrade(direction);
}

//+------------------------------------------------------------------+
void ExecuteSignalTrade(const int direction)
{
   ulong ticket = 0;
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)-1;
   double volume = 0.0, openPrice = 0.0, sl = 0.0, tp = 0.0;
   bool hasManaged = FindManagedPosition(ticket, posType, volume, openPrice, sl, tp);
   if(hasManaged)
   {
      if(!ClosePositionByTicket(ticket))
      {
         Print("Failed to close existing managed position before new signal.");
         return;
      }
      g_activeTicket = 0;
   }

   double volumeNorm = NormalizeVolume(lotSize);
   if(volumeNorm <= 0.0)
   {
      Print("Invalid normalized lot size: ", lotSize);
      return;
   }

   bool ok = false;
   if(direction > 0)
      ok = SendMarketOrder(ORDER_TYPE_BUY, volumeNorm, g_stopLevel, g_tp3Level, "SMT_BW_BUY");
   else
      ok = SendMarketOrder(ORDER_TYPE_SELL, volumeNorm, g_stopLevel, g_tp3Level, "SMT_BW_SELL");

   if(!ok)
      return;

   Sleep(100);
   ulong newTicket = 0;
   if(FindManagedPosition(newTicket, posType, volume, openPrice, sl, tp))
      g_activeTicket = newTicket;
}

//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   ulong ticket = 0;
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)-1;
   double volume = 0.0, openPrice = 0.0, sl = 0.0, tp = 0.0;

   if(!FindManagedPosition(ticket, posType, volume, openPrice, sl, tp))
   {
      if(g_activeTicket != 0 || g_tradeDirection != 0)
      {
         g_activeTicket = 0;
         ResetTradeState();
      }
      return;
   }

   g_activeTicket = ticket;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(posType == POSITION_TYPE_BUY)
   {
      if(!g_tp1Hit && bid >= g_tp1Level)
      {
         g_tp1Hit = true;
         DeleteObjectByName(PREFIX + "TP1_LINE");
      }
      if(!g_tp2Hit && bid >= g_tp2Level)
      {
         g_tp2Hit = true;
         DeleteObjectByName(PREFIX + "TP2_LINE");
      }
      if(!g_tp3Hit && bid >= g_tp3Level)
      {
         g_tp3Hit = true;
         DeleteObjectByName(PREFIX + "TP3_LINE");
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(!g_tp1Hit && ask <= g_tp1Level)
      {
         g_tp1Hit = true;
         DeleteObjectByName(PREFIX + "TP1_LINE");
      }
      if(!g_tp2Hit && ask <= g_tp2Level)
      {
         g_tp2Hit = true;
         DeleteObjectByName(PREFIX + "TP2_LINE");
      }
      if(!g_tp3Hit && ask <= g_tp3Level)
      {
         g_tp3Hit = true;
         DeleteObjectByName(PREFIX + "TP3_LINE");
      }
   }
}

//+------------------------------------------------------------------+
double GetATRValue(const int shift)
{
   if(g_atrHandle == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) < 1)
      return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
double DetectSwingHigh(const int period)
{
   int center = period + 1;
   if(Bars(_Symbol, PERIOD_CURRENT) < (center + period + 2))
      return 0.0;

   double pivot = iHigh(_Symbol, PERIOD_CURRENT, center);
   if(pivot <= 0.0)
      return 0.0;

   for(int i = 1; i <= period; i++)
   {
      if(iHigh(_Symbol, PERIOD_CURRENT, center - i) >= pivot)
         return 0.0;
      if(iHigh(_Symbol, PERIOD_CURRENT, center + i) >= pivot)
         return 0.0;
   }
   return pivot;
}

//+------------------------------------------------------------------+
double DetectSwingLow(const int period)
{
   int center = period + 1;
   if(Bars(_Symbol, PERIOD_CURRENT) < (center + period + 2))
      return 0.0;

   double pivot = iLow(_Symbol, PERIOD_CURRENT, center);
   if(pivot <= 0.0)
      return 0.0;

   for(int i = 1; i <= period; i++)
   {
      if(iLow(_Symbol, PERIOD_CURRENT, center - i) <= pivot)
         return 0.0;
      if(iLow(_Symbol, PERIOD_CURRENT, center + i) <= pivot)
         return 0.0;
   }
   return pivot;
}

//+------------------------------------------------------------------+
bool FindManagedPosition(ulong &ticket, ENUM_POSITION_TYPE &posType, double &volume, double &openPrice, double &sl, double &tp)
{
   ticket = 0;
   posType = (ENUM_POSITION_TYPE)-1;
   volume = 0.0;
   openPrice = 0.0;
   sl = 0.0;
   tp = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;

      ticket = tk;
      posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      volume = PositionGetDouble(POSITION_VOLUME);
      openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      sl = PositionGetDouble(POSITION_SL);
      tp = PositionGetDouble(POSITION_TP);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool ClosePositionByTicket(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   if(volume <= 0.0)
      return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.magic = magicNumber;
   req.position = ticket;
   req.volume = NormalizeVolume(volume);
   req.deviation = slippagePoints;
   req.type_filling = GetFillingMode();
   req.type_time = ORDER_TIME_GTC;
   req.comment = "SMT_BW_CLOSE";

   if(posType == POSITION_TYPE_BUY)
   {
      req.type = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      req.type = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   bool ok = OrderSend(req, res);
   if(!ok || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL))
   {
      Print("ClosePositionByTicket failed. retcode=", res.retcode, " error=", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool SendMarketOrder(const ENUM_ORDER_TYPE orderType, const double volume, const double sl, const double tp, const string comment)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.magic = magicNumber;
   req.volume = NormalizeVolume(volume);
   req.deviation = slippagePoints;
   req.type = orderType;
   req.type_filling = GetFillingMode();
   req.type_time = ORDER_TIME_GTC;
   req.comment = comment;

   if(orderType == ORDER_TYPE_BUY)
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   req.sl = NormalizePrice(sl);
   req.tp = NormalizePrice(tp);

   bool ok = OrderSend(req, res);
   if(!ok || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      Print("OrderSend failed. retcode=", res.retcode, " error=", GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   long fill = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, fill))
   {
      if((fill & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;
      if((fill & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
   }
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
double NormalizeVolume(const double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = 0.01;

   double v = MathMax(minLot, MathMin(maxLot, volume));
   v = MathFloor(v / step) * step;
   return NormalizeDouble(v, 2);
}

//+------------------------------------------------------------------+
void UpdateVisuals()
{
   DrawDashboard();
   DrawInfoTable();

   if(g_tradeDirection == 0)
      return;

   datetime t1 = g_lastTradeSignalTime;
   datetime t2 = iTime(_Symbol, PERIOD_CURRENT, 0) + (PeriodSeconds(PERIOD_CURRENT) * 15);
   if(t1 <= 0 || t2 <= t1)
      return;

   UpdateTrendLine(PREFIX + "ENTRY_LINE", t1, g_entryLevel, t2, g_entryLevel);
   UpdateTrendLine(PREFIX + "SL_LINE", t1, g_stopLevel, t2, g_stopLevel);

   if(!g_tp1Hit)
      UpdateTrendLine(PREFIX + "TP1_LINE", t1, g_tp1Level, t2, g_tp1Level);
   if(!g_tp2Hit)
      UpdateTrendLine(PREFIX + "TP2_LINE", t1, g_tp2Level, t2, g_tp2Level);
   if(!g_tp3Hit)
      UpdateTrendLine(PREFIX + "TP3_LINE", t1, g_tp3Level, t2, g_tp3Level);

   UpdateRectangle(PREFIX + "RISK_BOX", t1, g_entryLevel, t2, g_stopLevel, dangerColor);
   UpdateRectangle(PREFIX + "REWARD_BOX", t1, g_entryLevel, t2, g_tp3Level, successColor);
}

//+------------------------------------------------------------------+
void DrawTradeObjects()
{
   if(g_tradeDirection == 0 || g_lastTradeSignalTime <= 0)
      return;

   datetime t1 = g_lastTradeSignalTime;
   datetime t2 = t1 + (PeriodSeconds(PERIOD_CURRENT) * 15);

   CreateTrendLine(PREFIX + "ENTRY_LINE", t1, g_entryLevel, t2, g_entryLevel, clrWhite, STYLE_SOLID, 2);
   CreateTrendLine(PREFIX + "SL_LINE", t1, g_stopLevel, t2, g_stopLevel, dangerColor, STYLE_SOLID, 2);
   CreateTrendLine(PREFIX + "TP1_LINE", t1, g_tp1Level, t2, g_tp1Level, successColor, STYLE_DASH, 1);
   CreateTrendLine(PREFIX + "TP2_LINE", t1, g_tp2Level, t2, g_tp2Level, successColor, STYLE_DASH, 1);
   CreateTrendLine(PREFIX + "TP3_LINE", t1, g_tp3Level, t2, g_tp3Level, successColor, STYLE_SOLID, 2);

   CreateRectangle(PREFIX + "RISK_BOX", t1, g_entryLevel, t2, g_stopLevel, dangerColor);
   CreateRectangle(PREFIX + "REWARD_BOX", t1, g_entryLevel, t2, g_tp3Level, successColor);

   CreateText(PREFIX + "TP1_TEXT", t2, g_tp1Level, "TP1: " + DoubleToString(g_tp1Level, _Digits), successColor);
   CreateText(PREFIX + "TP2_TEXT", t2, g_tp2Level, "TP2: " + DoubleToString(g_tp2Level, _Digits), successColor);
   CreateText(PREFIX + "TP3_TEXT", t2, g_tp3Level, "TP3: " + DoubleToString(g_tp3Level, _Digits), successColor);
   CreateText(PREFIX + "SL_TEXT", t2, g_stopLevel, "SL: " + DoubleToString(g_stopLevel, _Digits), dangerColor);
}

//+------------------------------------------------------------------+
void DrawBreakObjects(const bool bullish, const datetime pivotTime, const double level, const bool isChoch, const double atr)
{
   string lineName = PREFIX + "BREAK_LINE";
   string labelName = PREFIX + "BREAK_LABEL";
   DeleteObjectByName(lineName);
   DeleteObjectByName(labelName);

   datetime nowBar = iTime(_Symbol, PERIOD_CURRENT, 1);
   CreateTrendLine(lineName, pivotTime, level, nowBar, level, (bullish ? bullColor : bearColor), STYLE_DOT, 2);

   double refPrice = bullish ? HighestHigh(1, 5) + (atr * 0.5) : LowestLow(1, 5) - (atr * 0.5);
   string txt = (isChoch && showCHoCH ? (bullish ? "CHoCH ^" : "CHoCH v") : (bullish ? "BOS ^" : "BOS v"));
   CreateText(labelName, nowBar, refPrice, txt, (bullish ? bullColor : bearColor));

   string arrowName = PREFIX + (bullish ? "BULL_ARROW" : "BEAR_ARROW");
   DeleteObjectByName(arrowName);
   CreateArrow(arrowName, nowBar, bullish ? (LowestLow(1, 3) - atr * 0.15) : (HighestHigh(1, 3) + atr * 0.15), bullish, (bullish ? bullColor : bearColor));
}

//+------------------------------------------------------------------+
void DrawDashboard()
{
   string name = PREFIX + "DASHBOARD";
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 260);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 10);
   ObjectSetString(0, name, OBJPROP_TEXT, "Join Telegram @FundedMillionAiress");
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
}

//+------------------------------------------------------------------+
void DrawInfoTable()
{
   string bg = PREFIX + "INFO_BG";
   string txt = PREFIX + "INFO_TXT";

   if(g_tradeDirection == 0 || !showTable)
   {
      DeleteObjectByName(bg);
      DeleteObjectByName(txt);
      return;
   }

   int corner = CORNER_RIGHT_UPPER;
   if(tablePosition == "Top Left")
      corner = CORNER_LEFT_UPPER;
   else if(tablePosition == "Bottom Left")
      corner = CORNER_LEFT_LOWER;
   else if(tablePosition == "Bottom Right")
      corner = CORNER_RIGHT_LOWER;

   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   if(ObjectFind(0, txt) < 0)
      ObjectCreate(0, txt, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, bg, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 240);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 145);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, clrDimGray);

   string directionText = (g_tradeDirection > 0 ? "LONG" : "SHORT");
   color dirColor = (g_tradeDirection > 0 ? bullColor : bearColor);

   double slDistance = MathAbs(g_entryLevel - g_stopLevel);
   double tp1Distance = MathAbs(g_tp1Level - g_entryLevel);
   double tp2Distance = MathAbs(g_tp2Level - g_entryLevel);
   double tp3Distance = MathAbs(g_tp3Level - g_entryLevel);
   double rrRatio = (slDistance > 0.0 ? ((tp1Distance + tp2Distance + tp3Distance) / 3.0) / slDistance : 0.0);

   string body =
      "TRADE INFO\n"
      "Direction: " + directionText + "\n"
      "Entry: " + DoubleToString(g_entryLevel, _Digits) + "\n"
      "Stop Loss: " + DoubleToString(g_stopLevel, _Digits) + "\n"
      "TP1: " + DoubleToString(g_tp1Level, _Digits) + (g_tp1Hit ? "  [hit]" : "") + "\n"
      "TP2: " + DoubleToString(g_tp2Level, _Digits) + (g_tp2Hit ? "  [hit]" : "") + "\n"
      "TP3: " + DoubleToString(g_tp3Level, _Digits) + (g_tp3Hit ? "  [hit]" : "") + "\n"
      "Risk/Reward: 1:" + DoubleToString(rrRatio, 2);

   ObjectSetInteger(0, txt, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, txt, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, txt, OBJPROP_YDISTANCE, 28);
   ObjectSetString(0, txt, OBJPROP_TEXT, body);
   ObjectSetString(0, txt, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, txt, OBJPROP_COLOR, textColor);
}

//+------------------------------------------------------------------+
void CreateTrendLine(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color clr, const ENUM_LINE_STYLE style, const int width)
{
   DeleteObjectByName(name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
void UpdateTrendLine(const string name, const datetime t1, const double p1, const datetime t2, const double p2)
{
   if(ObjectFind(0, name) < 0)
      return;
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
}

//+------------------------------------------------------------------+
void CreateRectangle(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color clr)
{
   DeleteObjectByName(name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
}

//+------------------------------------------------------------------+
void UpdateRectangle(const string name, const datetime t1, const double p1, const datetime t2, const double p2, const color clr)
{
   if(ObjectFind(0, name) < 0)
      return;
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
void CreateText(const string name, const datetime when, const double price, const string text, const color clr)
{
   DeleteObjectByName(name);
   ObjectCreate(0, name, OBJ_TEXT, 0, when, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
}

//+------------------------------------------------------------------+
void CreateArrow(const string name, const datetime when, const double price, const bool bullish, const color clr)
{
   DeleteObjectByName(name);
   ObjectCreate(0, name, OBJ_ARROW, 0, when, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, bullish ? 241 : 242);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
double HighestHigh(const int startShift, const int count)
{
   double out = -DBL_MAX;
   for(int i = startShift; i < startShift + count; i++)
      out = MathMax(out, iHigh(_Symbol, PERIOD_CURRENT, i));
   return out;
}

//+------------------------------------------------------------------+
double LowestLow(const int startShift, const int count)
{
   double out = DBL_MAX;
   for(int i = startShift; i < startShift + count; i++)
      out = MathMin(out, iLow(_Symbol, PERIOD_CURRENT, i));
   return out;
}

//+------------------------------------------------------------------+
void ResetTradeObjects()
{
   DeleteObjectByName(PREFIX + "ENTRY_LINE");
   DeleteObjectByName(PREFIX + "SL_LINE");
   DeleteObjectByName(PREFIX + "TP1_LINE");
   DeleteObjectByName(PREFIX + "TP2_LINE");
   DeleteObjectByName(PREFIX + "TP3_LINE");
   DeleteObjectByName(PREFIX + "RISK_BOX");
   DeleteObjectByName(PREFIX + "REWARD_BOX");
   DeleteObjectByName(PREFIX + "TP1_TEXT");
   DeleteObjectByName(PREFIX + "TP2_TEXT");
   DeleteObjectByName(PREFIX + "TP3_TEXT");
   DeleteObjectByName(PREFIX + "SL_TEXT");
}

//+------------------------------------------------------------------+
void ResetTradeState()
{
   g_entryLevel = 0.0;
   g_tp1Level = 0.0;
   g_tp2Level = 0.0;
   g_tp3Level = 0.0;
   g_stopLevel = 0.0;
   g_tradeDirection = 0;
   g_tp1Hit = false;
   g_tp2Hit = false;
   g_tp3Hit = false;
   g_lastTradeSignalTime = 0;
   ResetTradeObjects();
}

//+------------------------------------------------------------------+
void DeleteObjectByName(const string name)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
}

//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   string names[] =
   {
      PREFIX + "BREAK_LINE",
      PREFIX + "BREAK_LABEL",
      PREFIX + "BULL_ARROW",
      PREFIX + "BEAR_ARROW",
      PREFIX + "ENTRY_LINE",
      PREFIX + "SL_LINE",
      PREFIX + "TP1_LINE",
      PREFIX + "TP2_LINE",
      PREFIX + "TP3_LINE",
      PREFIX + "RISK_BOX",
      PREFIX + "REWARD_BOX",
      PREFIX + "TP1_TEXT",
      PREFIX + "TP2_TEXT",
      PREFIX + "TP3_TEXT",
      PREFIX + "SL_TEXT",
      PREFIX + "INFO_BG",
      PREFIX + "INFO_TXT",
      PREFIX + "DASHBOARD"
   };

   for(int i = 0; i < ArraySize(names); i++)
      DeleteObjectByName(names[i]);
}
