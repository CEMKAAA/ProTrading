//+------------------------------------------------------------------+
//| Risk Rectangle MT4 EA                                            |
//| Draggable rectangle risk/price-height calculator.                |
//+------------------------------------------------------------------+
#property strict

enum PnlCalcMode
{
   PNL_CONTRACT_SIZE = 0,
   PNL_BROKER_TICK_VALUE = 1
};

input double InpInitialLot = 0.10;
input double InpLotStep = 0.01;
input double InpMinLot = 0.01;
input double InpMaxLot = 100.0;
input PnlCalcMode InpPnLCalcMode = PNL_CONTRACT_SIZE;
input color  InpRectangleColor = clrDodgerBlue;
input color  InpPanelTextColor = clrWhite;
input color  InpPanelBackColor = clrBlack;
input int    InpInitialBarsWide = 80;
input double InpInitialHeightATRMult = 2.0;
input int    InpAtrPeriod = 14;
input int    InpPanelCorner = CORNER_LEFT_UPPER;
input int    InpPanelX = 12;
input int    InpPanelY = 28;
input int    InpValueBoxWidth = 170;
input int    InpValueBoxHeight = 22;
input bool   InpShowContractDebug = true;
input bool   InpKeepObjectsOnRemove = false;

string RECT_NAME = "PT_RISK_RECTANGLE_BOX";
string LABEL_NAME = "PT_RISK_RECTANGLE_LABEL";
string VALUE_BOX = "PT_RISK_RECTANGLE_VALUE_BOX";
string VALUE_LABEL = "PT_RISK_RECTANGLE_VALUE_LABEL";
string BTN_LOT_DOWN = "PT_RISK_RECTANGLE_LOT_DOWN";
string EDIT_LOT = "PT_RISK_RECTANGLE_LOT_EDIT";
string BTN_LOT_UP = "PT_RISK_RECTANGLE_LOT_UP";
string BTN_RESET = "PT_RISK_RECTANGLE_RESET";

double g_lot = 0.10;

double _clamp_lot(double lot)
{
   double minLot = InpMinLot;
   double maxLot = InpMaxLot;
   double brokerMin = MarketInfo(Symbol(), MODE_MINLOT);
   double brokerMax = MarketInfo(Symbol(), MODE_MAXLOT);
   if(brokerMin > 0.0)
      minLot = MathMax(minLot, brokerMin);
   if(brokerMax > 0.0)
      maxLot = MathMin(maxLot, brokerMax);
   if(maxLot < minLot)
      maxLot = minLot;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return NormalizeDouble(lot, 2);
}

double _parse_lot(string raw, double fallback)
{
   string txt = StringTrimLeft(StringTrimRight(raw));
   StringReplace(txt, ",", ".");
   double lot = StrToDouble(txt);
   if(lot <= 0.0)
      lot = fallback;
   return _clamp_lot(lot);
}

string _money(double value)
{
   return DoubleToString(value, 2);
}

string _price(double value)
{
   return DoubleToString(value, Digits);
}

double _pip_point()
{
   if(Digits == 3 || Digits == 5)
      return Point * 10.0;
   return Point;
}

bool _object_exists(string name)
{
   return ObjectFind(0, name) >= 0;
}

void _set_button(string name, string text, int x, int y, int w, int h, color backColor)
{
   if(!_object_exists(name))
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, backColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void _set_lot_edit()
{
   if(!_object_exists(EDIT_LOT))
      ObjectCreate(0, EDIT_LOT, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_XDISTANCE, InpPanelX + 34);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_XSIZE, 64);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_YSIZE, 22);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, EDIT_LOT, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(g_lot, 2));
}

void _create_controls()
{
   _set_button(BTN_LOT_DOWN, "-", InpPanelX, InpPanelY, 28, 22, clrDimGray);
   _set_lot_edit();
   _set_button(BTN_LOT_UP, "+", InpPanelX + 104, InpPanelY, 28, 22, clrDimGray);
   _set_button(BTN_RESET, "Reset Box", InpPanelX + 138, InpPanelY, 78, 22, clrSteelBlue);

   if(!_object_exists(LABEL_NAME))
      ObjectCreate(0, LABEL_NAME, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LABEL_NAME, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, LABEL_NAME, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, LABEL_NAME, OBJPROP_YDISTANCE, InpPanelY + 28);
   ObjectSetInteger(0, LABEL_NAME, OBJPROP_COLOR, InpPanelTextColor);
   ObjectSetInteger(0, LABEL_NAME, OBJPROP_BGCOLOR, InpPanelBackColor);
   ObjectSetInteger(0, LABEL_NAME, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, LABEL_NAME, OBJPROP_SELECTABLE, false);

   if(!_object_exists(VALUE_BOX))
      ObjectCreate(0, VALUE_BOX, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_XDISTANCE, InpPanelX + 222);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_XSIZE, MathMax(120, InpValueBoxWidth));
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_YSIZE, MathMax(24, InpValueBoxHeight));
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_BACK, false);
   ObjectSetInteger(0, VALUE_BOX, OBJPROP_SELECTABLE, false);

   if(!_object_exists(VALUE_LABEL))
      ObjectCreate(0, VALUE_LABEL, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, VALUE_LABEL, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, VALUE_LABEL, OBJPROP_XDISTANCE, InpPanelX + 230);
   ObjectSetInteger(0, VALUE_LABEL, OBJPROP_YDISTANCE, InpPanelY + 4);
   ObjectSetInteger(0, VALUE_LABEL, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, VALUE_LABEL, OBJPROP_FONTSIZE, 12);
   ObjectSetInteger(0, VALUE_LABEL, OBJPROP_SELECTABLE, false);
}

void _create_or_reset_rectangle()
{
   int barsWide = MathMax(5, InpInitialBarsWide);
   int rightShift = MathMin(5, MathMax(1, Bars - 2));
   int leftShift = MathMin(Bars - 1, rightShift + barsWide);
   datetime t1 = Time[leftShift];
   datetime t2 = Time[rightShift];
   double atr = iATR(Symbol(), Period(), MathMax(1, InpAtrPeriod), 1);
   if(atr <= 0.0)
      atr = MathMax(Point * 100.0, (High[1] - Low[1]));
   double mid = Bid;
   if(mid <= 0.0)
      mid = Close[1];
   double halfHeight = MathMax(Point * 10.0, atr * MathMax(0.1, InpInitialHeightATRMult) * 0.5);
   double p1 = NormalizeDouble(mid + halfHeight, Digits);
   double p2 = NormalizeDouble(mid - halfHeight, Digits);

   if(_object_exists(RECT_NAME))
      ObjectDelete(0, RECT_NAME);
   ObjectCreate(0, RECT_NAME, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, RECT_NAME, OBJPROP_COLOR, InpRectangleColor);
   ObjectSetInteger(0, RECT_NAME, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, RECT_NAME, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, RECT_NAME, OBJPROP_BACK, false);
   ObjectSetInteger(0, RECT_NAME, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, RECT_NAME, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, RECT_NAME, OBJPROP_HIDDEN, false);
}

void _ensure_rectangle()
{
   if(!_object_exists(RECT_NAME))
      _create_or_reset_rectangle();
}

double _risk_money_from_height_tick(double priceHeight)
{
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickSize <= 0.0)
      tickSize = Point;
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;
   return MathAbs(priceHeight) / tickSize * tickValue * g_lot;
}

double _risk_money_from_height_contract(double priceHeight)
{
   double lotSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   if(lotSize <= 0.0)
      return 0.0;
   return MathAbs(priceHeight) * lotSize * g_lot;
}

double _risk_money_from_height(double priceHeight)
{
   double contractRisk = _risk_money_from_height_contract(priceHeight);
   double tickRisk = _risk_money_from_height_tick(priceHeight);
   if(InpPnLCalcMode == PNL_BROKER_TICK_VALUE)
      return tickRisk;
   if(contractRisk > 0.0)
      return contractRisk;
   return tickRisk;
}

double _value_per_price_unit_per_lot()
{
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickSize <= 0.0)
      tickSize = Point;
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   return tickValue / tickSize;
}

int _bars_between(datetime t1, datetime t2)
{
   int sh1 = iBarShift(Symbol(), Period(), t1, false);
   int sh2 = iBarShift(Symbol(), Period(), t2, false);
   if(sh1 < 0 || sh2 < 0)
      return 0;
   return MathAbs(sh1 - sh2) + 1;
}

void _update_panel()
{
   _ensure_rectangle();
   double p1 = ObjectGetDouble(0, RECT_NAME, OBJPROP_PRICE1);
   double p2 = ObjectGetDouble(0, RECT_NAME, OBJPROP_PRICE2);
   datetime t1 = (datetime)ObjectGetInteger(0, RECT_NAME, OBJPROP_TIME1);
   datetime t2 = (datetime)ObjectGetInteger(0, RECT_NAME, OBJPROP_TIME2);

   double highPrice = MathMax(p1, p2);
   double lowPrice = MathMin(p1, p2);
   double height = MathAbs(highPrice - lowPrice);
   double points = (Point > 0.0 ? height / Point : 0.0);
   double pips = (_pip_point() > 0.0 ? height / _pip_point() : 0.0);
   double riskMoney = _risk_money_from_height(height);
   int barsCovered = _bars_between(t1, t2);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double lotSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   double valuePerUnit = _value_per_price_unit_per_lot();
   double tickRisk = _risk_money_from_height_tick(height);
   double contractRisk = _risk_money_from_height_contract(height);

   string txt = "";
   txt += "Risk Rectangle\n";
   txt += "Symbol/TF: " + Symbol() + " " + IntegerToString(Period()) + "\n";
   txt += "Lot: " + DoubleToString(g_lot, 2) + "\n";
   txt += "Top: " + _price(highPrice) + " | Bottom: " + _price(lowPrice) + "\n";
   txt += "Height: " + _price(height) + " (" + DoubleToString(points, 1) + " points / " + DoubleToString(pips, 1) + " pips)\n";
   txt += "Approx PnL/Risk: $" + _money(riskMoney) + "\n";
   txt += "Time span: " + IntegerToString(barsCovered) + " bars\n";
   txt += "Drag body to move. Drag corners/sides to resize.";
   if(InpShowContractDebug)
   {
      txt += "\n";
      txt += "TickSize: " + DoubleToString(tickSize, 8) + " | TickValue: $" + _money(tickValue) + "\n";
      txt += "LotSize: " + DoubleToString(lotSize, 2) + " | $/1.00/lot: " + _money(valuePerUnit) + "\n";
      txt += "BrokerTick PnL: $" + _money(tickRisk) + " | Contract PnL: $" + _money(contractRisk);
   }

   ObjectSetString(0, LABEL_NAME, OBJPROP_TEXT, txt);
   ObjectSetString(
      0,
      VALUE_LABEL,
      OBJPROP_TEXT,
      "Approx PnL: $" + _money(riskMoney)
   );
   ChartRedraw(0);
}

int OnInit()
{
   g_lot = _clamp_lot(InpInitialLot);
   _create_controls();
   _ensure_rectangle();
   _update_panel();
   EventSetTimer(1);
   Print("RiskRectangle initialized. Drag/resize the rectangle to measure price height and lot-based PnL.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(!InpKeepObjectsOnRemove)
   {
      ObjectDelete(0, RECT_NAME);
      ObjectDelete(0, LABEL_NAME);
      ObjectDelete(0, VALUE_BOX);
      ObjectDelete(0, VALUE_LABEL);
      ObjectDelete(0, BTN_LOT_DOWN);
      ObjectDelete(0, EDIT_LOT);
      ObjectDelete(0, BTN_LOT_UP);
      ObjectDelete(0, BTN_RESET);
   }
}

void OnTick()
{
   _update_panel();
}

void OnTimer()
{
   _update_panel();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == BTN_LOT_DOWN)
      {
         g_lot = _clamp_lot(g_lot - MathMax(0.01, InpLotStep));
         ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(g_lot, 2));
         _update_panel();
      }
      else if(sparam == BTN_LOT_UP)
      {
         g_lot = _clamp_lot(g_lot + MathMax(0.01, InpLotStep));
         ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(g_lot, 2));
         _update_panel();
      }
      else if(sparam == BTN_RESET)
      {
         _create_or_reset_rectangle();
         _update_panel();
      }
   }
   else if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == EDIT_LOT)
   {
      g_lot = _parse_lot(ObjectGetString(0, EDIT_LOT, OBJPROP_TEXT), g_lot);
      ObjectSetString(0, EDIT_LOT, OBJPROP_TEXT, DoubleToString(g_lot, 2));
      _update_panel();
   }
   else if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_CHART_CHANGE)
   {
      _update_panel();
   }
}
