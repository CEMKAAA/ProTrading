//+------------------------------------------------------------------+
//| Manual Close Buttons MT4 EA                                      |
//| Adds Close Buy / Close Sell / Close All buttons to the chart.    |
//+------------------------------------------------------------------+
#property strict

input bool InpOnlyCurrentSymbol = false;       // false = whole MT4 terminal/account
input int  InpMagicNumberFilter = -1;          // -1 = all magic numbers
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
input int  InpOpenMagicNumber = 0;
input string InpOpenComment = "manual_button";

string BTN_CLOSE_BUY = "PT_MANUAL_CLOSE_BUY";
string BTN_CLOSE_SELL = "PT_MANUAL_CLOSE_SELL";
string BTN_CLOSE_ALL = "PT_MANUAL_CLOSE_ALL";
string BTN_LOT_DOWN = "PT_MANUAL_LOT_DOWN";
string BTN_LOT_EDIT = "PT_MANUAL_LOT_EDIT";
string BTN_LOT_UP = "PT_MANUAL_LOT_UP";
string BTN_OPEN_BUY = "PT_MANUAL_OPEN_BUY";
string BTN_OPEN_SELL = "PT_MANUAL_OPEN_SELL";

double g_lot = 0.10;

bool _symbol_allowed(string symbol)
{
   if(!InpOnlyCurrentSymbol)
      return true;
   return (StringCompare(symbol, Symbol(), false) == 0);
}

bool _magic_allowed(int magic)
{
   if(InpMagicNumberFilter < 0)
      return true;
   return (magic == InpMagicNumberFilter);
}

bool _order_type_matches(int orderType, string side)
{
   string s = side;
   StringToUpper(s);
   if(s == "BUY")
      return (orderType == OP_BUY);
   if(s == "SELL")
      return (orderType == OP_SELL);
   if(s == "ALL")
      return (orderType == OP_BUY || orderType == OP_SELL);
   return false;
}

bool _pending_type_matches(int orderType, string side)
{
   string s = side;
   StringToUpper(s);
   if(s == "BUY")
      return (orderType == OP_BUYLIMIT || orderType == OP_BUYSTOP);
   if(s == "SELL")
      return (orderType == OP_SELLLIMIT || orderType == OP_SELLSTOP);
   if(s == "ALL")
      return (
         orderType == OP_BUYLIMIT || orderType == OP_BUYSTOP ||
         orderType == OP_SELLLIMIT || orderType == OP_SELLSTOP
      );
   return false;
}

double _symbol_min_lot(string symbol)
{
   double v = MarketInfo(symbol, MODE_MINLOT);
   if(v <= 0.0)
      v = 0.01;
   return v;
}

double _symbol_max_lot(string symbol)
{
   double v = MarketInfo(symbol, MODE_MAXLOT);
   if(v <= 0.0)
      v = 100.0;
   return v;
}

double _symbol_lot_step(string symbol)
{
   double v = MarketInfo(symbol, MODE_LOTSTEP);
   if(v <= 0.0)
      v = InpLotStep;
   if(v <= 0.0)
      v = 0.01;
   return v;
}

double _normalize_lot(string symbol, double lot)
{
   double minLot = _symbol_min_lot(symbol);
   double maxLot = _symbol_max_lot(symbol);
   double step = _symbol_lot_step(symbol);
   double v = MathMax(minLot, MathMin(maxLot, lot));
   v = MathFloor((v / step) + 1e-9) * step;
   v = MathMax(minLot, MathMin(maxLot, v));
   return NormalizeDouble(v, 2);
}

string _lot_text(double lot)
{
   return DoubleToString(_normalize_lot(Symbol(), lot), 2);
}

void _update_lot_edit()
{
   if(ObjectFind(0, BTN_LOT_EDIT) >= 0)
      ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_TEXT, _lot_text(g_lot));
}

void _set_lot(double lot)
{
   g_lot = _normalize_lot(Symbol(), lot);
   _update_lot_edit();
}

void _nudge_lot(int dir)
{
   double step = _symbol_lot_step(Symbol());
   if(InpLotStep > 0.0)
      step = InpLotStep;
   _set_lot(g_lot + (double)dir * step);
}

void _read_lot_from_edit()
{
   if(ObjectFind(0, BTN_LOT_EDIT) < 0)
      return;
   string raw = ObjectGetString(0, BTN_LOT_EDIT, OBJPROP_TEXT);
   StringReplace(raw, ",", ".");
   double v = StrToDouble(raw);
   if(v <= 0.0)
      v = g_lot;
   _set_lot(v);
}

double _close_price(string symbol, int orderType)
{
   RefreshRates();
   if(orderType == OP_BUY)
      return MarketInfo(symbol, MODE_BID);
   if(orderType == OP_SELL)
      return MarketInfo(symbol, MODE_ASK);
   return 0.0;
}

bool _close_selected_market_order()
{
   int ticket = OrderTicket();
   string symbol = OrderSymbol();
   int orderType = OrderType();
   double lots = OrderLots();
   double price = _close_price(symbol, orderType);
   if(ticket <= 0 || lots <= 0.0 || price <= 0.0)
      return false;

   ResetLastError();
   bool ok = OrderClose(ticket, lots, price, InpSlippagePoints, clrNONE);
   if(!ok)
   {
      int err = GetLastError();
      Print("ManualCloseButtons: close failed ticket=", ticket, " symbol=", symbol, " err=", err);
   }
   return ok;
}

bool _delete_selected_pending_order()
{
   int ticket = OrderTicket();
   if(ticket <= 0)
      return false;

   ResetLastError();
   bool ok = OrderDelete(ticket, clrNONE);
   if(!ok)
   {
      int err = GetLastError();
      Print("ManualCloseButtons: pending delete failed ticket=", ticket, " symbol=", OrderSymbol(), " err=", err);
   }
   return ok;
}

bool _open_market_order(string side)
{
   string s = side;
   StringToUpper(s);
   if(s != "BUY" && s != "SELL")
      return false;

   _read_lot_from_edit();
   RefreshRates();
   string symbol = Symbol();
   double lot = _normalize_lot(symbol, g_lot);
   int orderType = (s == "BUY") ? OP_BUY : OP_SELL;
   double price = (s == "BUY") ? Ask : Bid;
   if(lot <= 0.0 || price <= 0.0)
      return false;

   ResetLastError();
   int ticket = OrderSend(symbol, orderType, lot, price, InpSlippagePoints, 0.0, 0.0, InpOpenComment, InpOpenMagicNumber, 0, clrNONE);
   if(ticket <= 0)
   {
      int err = GetLastError();
      Print("ManualCloseButtons: open ", s, " failed symbol=", symbol, " lot=", DoubleToString(lot, 2), " err=", err);
      return false;
   }

   Print("ManualCloseButtons: opened ", s, " ticket=", ticket, " symbol=", symbol, " lot=", DoubleToString(lot, 2));
   return true;
}

int _close_side(string side)
{
   int closed = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);

   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            continue;

         string symbol = OrderSymbol();
         int orderType = OrderType();
         int magic = OrderMagicNumber();

         if(!_symbol_allowed(symbol) || !_magic_allowed(magic))
            continue;

         if(_order_type_matches(orderType, side))
         {
            if(_close_selected_market_order())
            {
               closed++;
               changedThisPass++;
            }
            continue;
         }

         if(InpClosePendingOrders && _pending_type_matches(orderType, side))
         {
            if(_delete_selected_pending_order())
            {
               closed++;
               changedThisPass++;
            }
         }
      }

      if(changedThisPass <= 0)
         break;

      Sleep(250);
   }

   Print("ManualCloseButtons: ", side, " close action completed. affected=", closed);
   return closed;
}

void _create_button_sized(string name, string text, int x, int y, int w, color bg)
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

void _create_button(string name, string text, int x, int y, color bg)
{
   _create_button_sized(name, text, x, y, InpButtonWidth, bg);
}

void _create_lot_edit(int x, int y, int w)
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
   ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_TEXT, _lot_text(g_lot));
}

void _delete_buttons()
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
   _set_lot(InpInitialLot);
   _create_button(BTN_CLOSE_BUY, "Close Buy", x, y, clrSeaGreen);
   _create_button(BTN_CLOSE_SELL, "Close Sell", x + InpButtonWidth + InpButtonGap, y, clrFireBrick);
   _create_button(BTN_CLOSE_ALL, "Close All", x + (InpButtonWidth + InpButtonGap) * 2, y, clrDimGray);

   int y2 = y + InpButtonHeight + InpButtonGap;
   int smallW = 32;
   int editW = 82;
   int tradeW = 78;
   int cx = x;
   _create_button_sized(BTN_LOT_DOWN, "-", cx, y2, smallW, clrGray);
   cx += smallW + InpButtonGap;
   _create_lot_edit(cx, y2, editW);
   cx += editW + InpButtonGap;
   _create_button_sized(BTN_LOT_UP, "+", cx, y2, smallW, clrGray);
   cx += smallW + InpButtonGap;
   _create_button_sized(BTN_OPEN_BUY, "Buy", cx, y2, tradeW, clrGreen);
   cx += tradeW + InpButtonGap;
   _create_button_sized(BTN_OPEN_SELL, "Sell", cx, y2, tradeW, clrRed);

   ChartRedraw();
   Print("ManualCloseButtons initialized. OnlyCurrentSymbol=", InpOnlyCurrentSymbol, " MagicFilter=", InpMagicNumberFilter);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   _delete_buttons();
   ChartRedraw();
}

void OnTick()
{
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == BTN_LOT_EDIT)
   {
      _read_lot_from_edit();
      ChartRedraw();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == BTN_CLOSE_BUY)
   {
      ObjectSetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE, false);
      _close_side("BUY");
   }
   else if(sparam == BTN_CLOSE_SELL)
   {
      ObjectSetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE, false);
      _close_side("SELL");
   }
   else if(sparam == BTN_CLOSE_ALL)
   {
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE, false);
      _close_side("ALL");
   }
   else if(sparam == BTN_LOT_DOWN)
   {
      ObjectSetInteger(0, BTN_LOT_DOWN, OBJPROP_STATE, false);
      _nudge_lot(-1);
   }
   else if(sparam == BTN_LOT_UP)
   {
      ObjectSetInteger(0, BTN_LOT_UP, OBJPROP_STATE, false);
      _nudge_lot(1);
   }
   else if(sparam == BTN_OPEN_BUY)
   {
      ObjectSetInteger(0, BTN_OPEN_BUY, OBJPROP_STATE, false);
      _open_market_order("BUY");
   }
   else if(sparam == BTN_OPEN_SELL)
   {
      ObjectSetInteger(0, BTN_OPEN_SELL, OBJPROP_STATE, false);
      _open_market_order("SELL");
   }

   ChartRedraw();
}
