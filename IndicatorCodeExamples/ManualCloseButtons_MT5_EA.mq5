//+------------------------------------------------------------------+
//| Manual Close Buttons MT5 EA                                      |
//| Adds Close Buy / Close Sell / Close All buttons to the chart.    |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

input bool InpOnlyCurrentSymbol = false;       // false = whole MT5 terminal/account
input long InpMagicNumberFilter = -1;          // -1 = all magic numbers
input bool InpClosePendingOrders = false;      // true = also delete pending orders
input int  InpSlippagePoints = 50;
input int  InpMaxClosePasses = 5;
input int  InpButtonX = 12;
input int  InpButtonY = 24;
input int  InpButtonWidth = 112;
input int  InpButtonHeight = 28;
input int  InpButtonGap = 8;
input double InpInitialLot = 0.10;
input double InpLotStep = 0.01;
input long InpOpenMagicNumber = 0;
input string InpOpenComment = "manual_button";
input bool InpAutoCloseProfitEnabled = true;          // Auto-close chart scope when total floating PnL reaches target
input double InpAutoCloseProfitTargetUsd = 50.0;      // Account currency target, e.g. 50 USD
input bool InpAutoCloseUseHjfxTfMagic = true;         // true = chart TF maps to HJFX magic below
input long InpAutoCloseMagicOverride = -1;            // >=0 overrides HJFX TF magic for auto-close only
input bool InpAutoCloseRequireMagic = true;           // true = never auto-close positions outside selected magic
input long InpHjfxMagicM1 = 658701;
input long InpHjfxMagicM5 = 658705;
input long InpHjfxMagicM15 = 658715;
input long InpHjfxMagicM30 = 658730;
input long InpHjfxMagicH1 = 658760;
input int InpAutoCloseCheckSeconds = 1;
input int InpAutoCloseCooldownSeconds = 10;

CTrade trade;

string BTN_CLOSE_BUY = "PT_MANUAL_CLOSE_BUY";
string BTN_CLOSE_SELL = "PT_MANUAL_CLOSE_SELL";
string BTN_CLOSE_ALL = "PT_MANUAL_CLOSE_ALL";
string BTN_LOT_DOWN = "PT_MANUAL_LOT_DOWN";
string BTN_LOT_EDIT = "PT_MANUAL_LOT_EDIT";
string BTN_LOT_UP = "PT_MANUAL_LOT_UP";
string BTN_OPEN_BUY = "PT_MANUAL_OPEN_BUY";
string BTN_OPEN_SELL = "PT_MANUAL_OPEN_SELL";

double g_lot = 0.10;
bool g_auto_close_in_progress = false;
datetime g_last_auto_close_at = 0;

string ChartTimeframeText()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf == PERIOD_M1)   return "M1";
   if(tf == PERIOD_M2)   return "M2";
   if(tf == PERIOD_M3)   return "M3";
   if(tf == PERIOD_M4)   return "M4";
   if(tf == PERIOD_M5)   return "M5";
   if(tf == PERIOD_M6)   return "M6";
   if(tf == PERIOD_M10)  return "M10";
   if(tf == PERIOD_M12)  return "M12";
   if(tf == PERIOD_M15)  return "M15";
   if(tf == PERIOD_M20)  return "M20";
   if(tf == PERIOD_M30)  return "M30";
   if(tf == PERIOD_H1)   return "H1";
   if(tf == PERIOD_H2)   return "H2";
   if(tf == PERIOD_H3)   return "H3";
   if(tf == PERIOD_H4)   return "H4";
   if(tf == PERIOD_H6)   return "H6";
   if(tf == PERIOD_H8)   return "H8";
   if(tf == PERIOD_H12)  return "H12";
   if(tf == PERIOD_D1)   return "D1";
   if(tf == PERIOD_W1)   return "W1";
   if(tf == PERIOD_MN1)  return "MN1";
   return IntegerToString((int)_Period);
}

bool SymbolAllowed(const string symbol)
{
   if(!InpOnlyCurrentSymbol)
      return true;
   return (StringCompare(symbol, _Symbol, false) == 0);
}

bool MagicAllowed(const long magic)
{
   if(InpMagicNumberFilter < 0)
      return true;
   return (magic == InpMagicNumberFilter);
}

long ChartHjfxMagic()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf == PERIOD_M1)   return InpHjfxMagicM1;
   if(tf == PERIOD_M5)   return InpHjfxMagicM5;
   if(tf == PERIOD_M15)  return InpHjfxMagicM15;
   if(tf == PERIOD_M30)  return InpHjfxMagicM30;
   if(tf == PERIOD_H1)   return InpHjfxMagicH1;
   return -1;
}

long AutoCloseMagicFilter()
{
   if(InpAutoCloseMagicOverride >= 0)
      return InpAutoCloseMagicOverride;
   if(InpAutoCloseUseHjfxTfMagic)
      return ChartHjfxMagic();
   return InpMagicNumberFilter;
}

bool AutoClosePositionAllowed(const string symbol, const long magic, const string comment)
{
   // Profit target automation is intentionally scoped to the chart symbol.
   if(StringCompare(symbol, _Symbol, false) != 0)
      return false;

   long selectedMagic = AutoCloseMagicFilter();
   if(selectedMagic >= 0)
   {
      if(magic != selectedMagic)
         return false;
   }
   else if(InpAutoCloseRequireMagic)
      return false;

   return true;
}

bool PositionTypeMatches(const ENUM_POSITION_TYPE type, string side)
{
   StringToUpper(side);
   if(side == "BUY")
      return (type == POSITION_TYPE_BUY);
   if(side == "SELL")
      return (type == POSITION_TYPE_SELL);
   if(side == "ALL")
      return (type == POSITION_TYPE_BUY || type == POSITION_TYPE_SELL);
   return false;
}

bool PendingTypeMatches(const ENUM_ORDER_TYPE type, string side)
{
   StringToUpper(side);
   if(side == "BUY")
      return (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
   if(side == "SELL")
      return (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);
   if(side == "ALL")
      return (
         type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT ||
         type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT
      );
   return false;
}

double SymbolMinLot(const string symbol)
{
   double v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(v <= 0.0)
      v = 0.01;
   return v;
}

double SymbolMaxLot(const string symbol)
{
   double v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(v <= 0.0)
      v = 100.0;
   return v;
}

double SymbolLotStep(const string symbol)
{
   double v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(v <= 0.0)
      v = InpLotStep;
   if(v <= 0.0)
      v = 0.01;
   return v;
}

double NormalizeLot(const string symbol, const double lot)
{
   double minLot = SymbolMinLot(symbol);
   double maxLot = SymbolMaxLot(symbol);
   double step = SymbolLotStep(symbol);
   double v = MathMax(minLot, MathMin(maxLot, lot));
   v = MathFloor((v / step) + 1e-9) * step;
   v = MathMax(minLot, MathMin(maxLot, v));
   return NormalizeDouble(v, 2);
}

string LotText(const double lot)
{
   return DoubleToString(NormalizeLot(_Symbol, lot), 2);
}

void UpdateLotEdit()
{
   if(ObjectFind(0, BTN_LOT_EDIT) >= 0)
      ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_TEXT, LotText(g_lot));
}

void SetLot(const double lot)
{
   g_lot = NormalizeLot(_Symbol, lot);
   UpdateLotEdit();
}

void NudgeLot(const int dir)
{
   double step = SymbolLotStep(_Symbol);
   if(InpLotStep > 0.0)
      step = InpLotStep;
   SetLot(g_lot + (double)dir * step);
}

void ReadLotFromEdit()
{
   if(ObjectFind(0, BTN_LOT_EDIT) < 0)
      return;
   string raw = ObjectGetString(0, BTN_LOT_EDIT, OBJPROP_TEXT);
   StringReplace(raw, ",", ".");
   double v = StringToDouble(raw);
   if(v <= 0.0)
      v = g_lot;
   SetLot(v);
}

bool OpenMarketPosition(string side)
{
   StringToUpper(side);
   if(side != "BUY" && side != "SELL")
      return false;

   ReadLotFromEdit();
   double lot = NormalizeLot(_Symbol, g_lot);
   if(lot <= 0.0)
      return false;

   trade.SetDeviationInPoints(InpSlippagePoints);
   if(InpOpenMagicNumber >= 0)
      trade.SetExpertMagicNumber((ulong)InpOpenMagicNumber);

   ResetLastError();
   bool ok = false;
   if(side == "BUY")
      ok = trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, InpOpenComment);
   else
      ok = trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, InpOpenComment);

   if(!ok)
   {
      Print("ManualCloseButtons: open ", side, " failed symbol=", _Symbol,
            " lot=", DoubleToString(lot, 2),
            " retcode=", trade.ResultRetcode(),
            " desc=", trade.ResultRetcodeDescription(),
            " err=", GetLastError());
      return false;
   }

   Print("ManualCloseButtons: opened ", side, " symbol=", _Symbol, " lot=", DoubleToString(lot, 2));
   return true;
}

int CloseSide(string side)
{
   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   trade.SetDeviationInPoints(InpSlippagePoints);

   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(!SymbolAllowed(symbol) || !MagicAllowed(magic) || !PositionTypeMatches(type, side))
            continue;

         ResetLastError();
         if(trade.PositionClose(ticket))
         {
            affected++;
            changedThisPass++;
         }
         else
         {
            Print("ManualCloseButtons: position close failed ticket=", ticket,
                  " symbol=", symbol,
                  " retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription(),
                  " err=", GetLastError());
         }
      }

      if(InpClosePendingOrders)
      {
         for(int j = OrdersTotal() - 1; j >= 0; j--)
         {
            ulong ticket = OrderGetTicket(j);
            if(ticket == 0 || !OrderSelect(ticket))
               continue;

            string symbol = OrderGetString(ORDER_SYMBOL);
            long magic = OrderGetInteger(ORDER_MAGIC);
            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

            if(!SymbolAllowed(symbol) || !MagicAllowed(magic) || !PendingTypeMatches(type, side))
               continue;

            ResetLastError();
            if(trade.OrderDelete(ticket))
            {
               affected++;
               changedThisPass++;
            }
            else
            {
               Print("ManualCloseButtons: pending delete failed ticket=", ticket,
                     " symbol=", symbol,
                     " retcode=", trade.ResultRetcode(),
                     " desc=", trade.ResultRetcodeDescription(),
                     " err=", GetLastError());
            }
         }
      }

      if(changedThisPass <= 0)
         break;

      Sleep(250);
   }

   Print("ManualCloseButtons: ", side, " close action completed. affected=", affected);
   return affected;
}

double CurrentChartScopeFloatingPnl(int &positionCount)
{
   double total = 0.0;
   positionCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      string comment = PositionGetString(POSITION_COMMENT);
      if(!AutoClosePositionAllowed(symbol, magic, comment))
         continue;

      total += PositionGetDouble(POSITION_PROFIT);
      total += PositionGetDouble(POSITION_SWAP);
      positionCount++;
   }

   return total;
}

int CloseChartScopePositions(const string reason)
{
   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   trade.SetDeviationInPoints(InpSlippagePoints);

   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         string comment = PositionGetString(POSITION_COMMENT);
         if(!AutoClosePositionAllowed(symbol, magic, comment))
            continue;

         ResetLastError();
         if(trade.PositionClose(ticket))
         {
            affected++;
            changedThisPass++;
         }
         else
         {
            Print("ManualCloseButtons: auto profit close failed ticket=", ticket,
                  " symbol=", symbol,
                  " reason=", reason,
                  " retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription(),
                  " err=", GetLastError());
         }
      }

      if(changedThisPass <= 0)
         break;

      Sleep(250);
   }

   Print("ManualCloseButtons: auto profit close completed reason=", reason, " affected=", affected);
   return affected;
}

void CheckAutoCloseProfitTarget()
{
   if(!InpAutoCloseProfitEnabled)
      return;
   if(InpAutoCloseProfitTargetUsd <= 0.0)
      return;
   if(g_auto_close_in_progress)
      return;

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   int cooldown = MathMax(1, InpAutoCloseCooldownSeconds);
   if(g_last_auto_close_at > 0 && nowTs > 0 && (nowTs - g_last_auto_close_at) < cooldown)
      return;

   int count = 0;
   double pnl = CurrentChartScopeFloatingPnl(count);
   if(count <= 0)
      return;

   if(pnl + 1e-8 < InpAutoCloseProfitTargetUsd)
      return;

   g_auto_close_in_progress = true;
   Print("ManualCloseButtons: auto profit target reached symbol=", _Symbol,
         " tf=", ChartTimeframeText(),
         " positions=", count,
         " pnl=", DoubleToString(pnl, 2),
         " target=", DoubleToString(InpAutoCloseProfitTargetUsd, 2));
   CloseChartScopePositions("profit_target");
   g_last_auto_close_at = nowTs;
   g_auto_close_in_progress = false;
}

void CreateButtonSized(const string name, const string text, const int x, const int y, const int w, const color bg)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, InpButtonHeight);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateButton(const string name, const string text, const int x, const int y, const color bg)
{
   CreateButtonSized(name, text, x, y, InpButtonWidth, bg);
}

void CreateLotEdit(const int x, const int y, const int w)
{
   if(ObjectFind(0, BTN_LOT_EDIT) >= 0)
      ObjectDelete(0, BTN_LOT_EDIT);

   ObjectCreate(0, BTN_LOT_EDIT, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_YSIZE, InpButtonHeight);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_FONT, "Arial");
   ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_TEXT, LotText(g_lot));
}

void DeleteButtons()
{
   ObjectDelete(0, BTN_CLOSE_BUY);
   ObjectDelete(0, BTN_CLOSE_SELL);
   ObjectDelete(0, BTN_CLOSE_ALL);
   ObjectDelete(0, BTN_LOT_DOWN);
   ObjectDelete(0, BTN_LOT_EDIT);
   ObjectDelete(0, BTN_LOT_UP);
   ObjectDelete(0, BTN_OPEN_BUY);
   ObjectDelete(0, BTN_OPEN_SELL);
}

int OnInit()
{
   int x = InpButtonX;
   int y = InpButtonY;
   SetLot(InpInitialLot);
   CreateButton(BTN_CLOSE_BUY, "Close Buy", x, y, clrSeaGreen);
   CreateButton(BTN_CLOSE_SELL, "Close Sell", x + InpButtonWidth + InpButtonGap, y, clrFireBrick);
   CreateButton(BTN_CLOSE_ALL, "Close All", x + (InpButtonWidth + InpButtonGap) * 2, y, clrDimGray);

   int y2 = y + InpButtonHeight + InpButtonGap;
   int smallW = 32;
   int editW = 82;
   int tradeW = 78;
   int cx = x;
   CreateButtonSized(BTN_LOT_DOWN, "-", cx, y2, smallW, clrGray);
   cx += smallW + InpButtonGap;
   CreateLotEdit(cx, y2, editW);
   cx += editW + InpButtonGap;
   CreateButtonSized(BTN_LOT_UP, "+", cx, y2, smallW, clrGray);
   cx += smallW + InpButtonGap;
   CreateButtonSized(BTN_OPEN_BUY, "Buy", cx, y2, tradeW, clrGreen);
   cx += tradeW + InpButtonGap;
   CreateButtonSized(BTN_OPEN_SELL, "Sell", cx, y2, tradeW, clrRed);

   if(InpAutoCloseProfitEnabled)
      EventSetTimer(MathMax(1, InpAutoCloseCheckSeconds));

   ChartRedraw();
   Print("ManualCloseButtons initialized. OnlyCurrentSymbol=", InpOnlyCurrentSymbol,
         " MagicFilter=", InpMagicNumberFilter,
         " AutoCloseProfit=", (InpAutoCloseProfitEnabled ? "true" : "false"),
         " AutoTarget=", DoubleToString(InpAutoCloseProfitTargetUsd, 2),
         " ChartScope=", _Symbol, " ", ChartTimeframeText(),
         " AutoMagic=", AutoCloseMagicFilter());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteButtons();
   ChartRedraw();
}

void OnTick()
{
   CheckAutoCloseProfitTarget();
}

void OnTimer()
{
   CheckAutoCloseProfitTarget();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == BTN_LOT_EDIT)
   {
      ReadLotFromEdit();
      ChartRedraw();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == BTN_CLOSE_BUY)
   {
      ObjectSetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE, false);
      CloseSide("BUY");
   }
   else if(sparam == BTN_CLOSE_SELL)
   {
      ObjectSetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE, false);
      CloseSide("SELL");
   }
   else if(sparam == BTN_CLOSE_ALL)
   {
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE, false);
      CloseSide("ALL");
   }
   else if(sparam == BTN_LOT_DOWN)
   {
      ObjectSetInteger(0, BTN_LOT_DOWN, OBJPROP_STATE, false);
      NudgeLot(-1);
   }
   else if(sparam == BTN_LOT_UP)
   {
      ObjectSetInteger(0, BTN_LOT_UP, OBJPROP_STATE, false);
      NudgeLot(1);
   }
   else if(sparam == BTN_OPEN_BUY)
   {
      ObjectSetInteger(0, BTN_OPEN_BUY, OBJPROP_STATE, false);
      OpenMarketPosition("BUY");
   }
   else if(sparam == BTN_OPEN_SELL)
   {
      ObjectSetInteger(0, BTN_OPEN_SELL, OBJPROP_STATE, false);
      OpenMarketPosition("SELL");
   }

   ChartRedraw();
}
