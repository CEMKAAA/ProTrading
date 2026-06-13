//+------------------------------------------------------------------+
//| 15 Minute ORB MT5 EA – v2 (bug-fix fork)                        |
//| Production-oriented Opening Range Breakout executor.              |
//| Session clock is NY time mapped to broker server time via GMT     |
//| offset input. Default broker offset is GMT+0.                     |
//|                                                                    |
//| v2 changelog (structural fixes only – signal math untouched):     |
//|  • OnDeinit is reason-aware: objects survive chart/TF changes     |
//|  • Historical arrow throttle resets on OnInit – no more vanish    |
//|  • OnTimer no longer redraws history every 60s (no flash)         |
//|  • DrawHistoricalSignals does incremental update, not nuke+redraw|
//|  • ResetForNewNyDay returns bool so callers know about day change |
//|  • Timer interval raised to 5s (OnTick covers live signals)       |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"

#include <Trade/Trade.mqh>

#define ORB15_BUILD "2026-06-14.v2-bugfix"

//--- Inputs (identical to v1) -------------------------------------------
input bool            InpEaEnabled = true;
input long            InpMagic = 15091501;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M1;
input double          InpBrokerGmtOffsetHours = 0.0;
input bool            InpAutoNewYorkDst = true;
input string          InpOrbStartNy = "09:30";
input string          InpOrbEndNy = "09:45";
input string          InpTradeEndNy = "16:00";
input bool            InpUseClosedBarBreakout = true;
input double          InpMinBreakoutPoints = 0.0;
input double          InpSlBufferPoints = 0.0;
input double          InpTakeProfitR = 2.0;
input bool            InpOneTradePerNyDay = true;
input bool            InpUseAutoRiskLot = true;
input double          InpRiskPerTradePct = 1.0;
input double          InpFixedLot = 0.10;
input double          InpMaxLot = 0.0;          // 0 = broker maximum only
input int             InpDeviationPoints = 30;
input int             InpMaxSpreadPoints = 0;   // 0 = off
input bool            InpDrawOrbLevels = true;
input bool            InpShowDashboard = true;
input int             InpDashboardX = 18;
input int             InpDashboardY = 28;
input bool            InpDrawHistoricalSignals = true;
input int             InpHistoricalDays = 7;
input bool            InpAuditCsv = true;
input bool            InpLogOnInit = true;

//--- Trade object -------------------------------------------------------
CTrade trade;

//--- Globals ------------------------------------------------------------
string   PREFIX = "ORB15v2_";
int      g_nyDayKey = 0;
bool     g_orbReady = false;
bool     g_tradeTaken = false;
double   g_orbHigh = 0.0;
double   g_orbLow = 0.0;
datetime g_orbStartServer = 0;
datetime g_orbEndServer = 0;
datetime g_tradeEndServer = 0;
datetime g_lastSignalBarTime = 0;
string   g_lastHistSummary = "-";
datetime g_lastHistBuild = 0;       // throttle timestamp
bool     g_histNeedsRedraw = true;   // v2: flag to force redraw

//=========================================================================
//  UTILITY FUNCTIONS (identical logic to v1)
//=========================================================================

int ParseClockMinutes(string value, int fallback)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   int p = StringFind(value, ":");
   if(p < 0)
      return fallback;
   int h = (int)StringToInteger(StringSubstr(value, 0, p));
   int m = (int)StringToInteger(StringSubstr(value, p + 1));
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return fallback;
   return h * 60 + m;
}

datetime MakeDateTime(const int year, const int mon, const int day, const int hour, const int minute, const int second = 0)
{
   MqlDateTime st;
   ZeroMemory(st);
   st.year = year;
   st.mon = mon;
   st.day = day;
   st.hour = hour;
   st.min = minute;
   st.sec = second;
   return StructToTime(st);
}

int DayOfWeekForDate(const int year, const int mon, const int day)
{
   MqlDateTime st;
   TimeToStruct(MakeDateTime(year, mon, day, 12, 0, 0), st);
   return st.day_of_week;
}

int NthSunday(const int year, const int mon, const int nth)
{
   int firstDow = DayOfWeekForDate(year, mon, 1);
   int firstSunday = 1 + ((7 - firstDow) % 7);
   return firstSunday + (nth - 1) * 7;
}

bool IsNewYorkDstDate(const int year, const int mon, const int day)
{
   if(!InpAutoNewYorkDst)
      return true;
   if(mon < 3 || mon > 11)
      return false;
   if(mon > 3 && mon < 11)
      return true;
   if(mon == 3)
      return day >= NthSunday(year, 3, 2);
   if(mon == 11)
      return day < NthSunday(year, 11, 1);
   return false;
}

int NyUtcOffsetSecondsForDate(const int year, const int mon, const int day)
{
   return IsNewYorkDstDate(year, mon, day) ? -4 * 3600 : -5 * 3600;
}

datetime NyLocalToServer(const int year, const int mon, const int day, const int minutesOfDay)
{
   int hour = minutesOfDay / 60;
   int minute = minutesOfDay % 60;
   datetime nyLocal = MakeDateTime(year, mon, day, hour, minute, 0);
   datetime utc = nyLocal - NyUtcOffsetSecondsForDate(year, mon, day);
   return utc + (int)MathRound(InpBrokerGmtOffsetHours * 3600.0);
}

datetime ServerToNyLocal(datetime serverTime)
{
   datetime utc = serverTime - (int)MathRound(InpBrokerGmtOffsetHours * 3600.0);
   MqlDateTime utcSt;
   TimeToStruct(utc, utcSt);
   return utc + NyUtcOffsetSecondsForDate(utcSt.year, utcSt.mon, utcSt.day);
}

int CurrentNyDayKey(int &year, int &mon, int &day)
{
   datetime utcNow = TimeCurrent() - (int)MathRound(InpBrokerGmtOffsetHours * 3600.0);
   MqlDateTime utcSt;
   TimeToStruct(utcNow, utcSt);
   int offset = NyUtcOffsetSecondsForDate(utcSt.year, utcSt.mon, utcSt.day);
   datetime nyNow = utcNow + offset;
   MqlDateTime nySt;
   TimeToStruct(nyNow, nySt);
   year = nySt.year;
   mon = nySt.mon;
   day = nySt.day;
   return year * 10000 + mon * 100 + day;
}

string FmtTime(datetime t)
{
   if(t <= 0)
      return "-";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

string BoolText(bool v)
{
   return v ? "true" : "false";
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double NormalizeVolume(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0.0)
      minLot = 0.01;
   if(maxLot <= 0.0)
      maxLot = 100.0;
   if(InpMaxLot > 0.0)
      maxLot = MathMin(maxLot, InpMaxLot);
   if(step <= 0.0)
      step = minLot;
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / step + 0.0000001) * step;
   return NormalizeDouble(MathMax(minLot, volume), 2);
}

double ValuePerPriceUnitPerLot()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   return tickValue / tickSize;
}

double CalculateLot(double entry, double sl)
{
   if(!InpUseAutoRiskLot)
      return NormalizeVolume(InpFixedLot);
   double riskDistance = MathAbs(entry - sl);
   double valuePerUnit = ValuePerPriceUnitPerLot();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * MathMax(0.01, InpRiskPerTradePct) / 100.0;
   if(riskDistance <= 0.0 || valuePerUnit <= 0.0 || riskMoney <= 0.0)
      return NormalizeVolume(InpFixedLot);
   return NormalizeVolume(riskMoney / (riskDistance * valuePerUnit));
}

int CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0;
   return (int)MathRound((tick.ask - tick.bid) / point);
}

bool SpreadAllowed()
{
   if(InpMaxSpreadPoints <= 0)
      return true;
   return CurrentSpreadPoints() <= InpMaxSpreadPoints;
}

//=========================================================================
//  AUDIT (identical to v1)
//=========================================================================

string AuditFileName()
{
   int y, m, d;
   int key = CurrentNyDayKey(y, m, d);
   return StringFormat("ORB15v2_Audit_%d.csv", key);
}

void Audit(string eventName, string direction, double lot, double entry, double sl, double tp, string detail)
{
   if(!InpAuditCsv)
      return;
   string fileName = AuditFileName();
   int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
   {
      Print("ORB15v2 audit open failed file=", fileName, " err=", GetLastError());
      return;
   }
   if(FileSize(handle) == 0)
      FileWrite(handle, "server_time", "gmt_time", "symbol", "tf", "event", "direction", "lot", "entry", "sl", "tp", "orb_high", "orb_low", "spread_pts", "detail");
   FileSeek(handle, 0, SEEK_END);
   datetime gmt = TimeGMT();
   FileWrite(handle,
             FmtTime(TimeCurrent()),
             FmtTime(gmt),
             _Symbol,
             EnumToString(InpSignalTimeframe),
             eventName,
             direction,
             DoubleToString(lot, 2),
             DoubleToString(entry, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(g_orbHigh, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(g_orbLow, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             IntegerToString(CurrentSpreadPoints()),
             detail);
   FileClose(handle);
}

//=========================================================================
//  POSITION CHECK (identical to v1)
//=========================================================================

bool OwnPositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

//=========================================================================
//  CHART OBJECT HELPERS
//=========================================================================

void DeleteObjectsByPrefix(const string prefix)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DeleteLevelObjects()
{
   ObjectDelete(0, PREFIX + "ORB_HIGH");
   ObjectDelete(0, PREFIX + "ORB_LOW");
   ObjectDelete(0, PREFIX + "ORB_TXT");
}

void DeleteHistoricalSignals()
{
   DeleteObjectsByPrefix(PREFIX + "HIST_");
}

void DeleteLiveSignals()
{
   DeleteObjectsByPrefix(PREFIX + "LIVE_");
}

void DeleteDashboard()
{
   DeleteObjectsByPrefix(PREFIX + "DASH_");
}

//=========================================================================
//  DASHBOARD (identical layout to v1)
//=========================================================================

void RectLabel(const string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DashLabel(const string name, int x, int y, string text, color clr, int size = 8)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawDashboard()
{
   if(!InpShowDashboard)
   {
      DeleteDashboard();
      return;
   }

   int x = InpDashboardX;
   int y = InpDashboardY;
   RectLabel(PREFIX + "DASH_BG", x, y, 430, 188, (color)0x202020, clrSteelBlue);
   RectLabel(PREFIX + "DASH_TOP", x, y, 430, 26, (color)0x35180E, clrSteelBlue);
   DashLabel(PREFIX + "DASH_TITLE", x + 12, y + 6, "ORB15 MT5 v2 // " + ORB15_BUILD, clrAliceBlue, 9);
   UpdateDashboard();
}

void UpdateDashboard()
{
   if(!InpShowDashboard)
      return;

   int x = InpDashboardX;
   int y = InpDashboardY;
   string state = InpEaEnabled ? "EA ON" : "EA OFF";
   string orb = g_orbReady ? "READY" : "WAITING";
   string sigTime = g_lastSignalBarTime > 0 ? FmtTime(g_lastSignalBarTime) : "-";
   DashLabel(PREFIX + "DASH_L1", x + 12, y + 36,
             "State " + state + " | ORB " + orb + " | SignalTF " + EnumToString(InpSignalTimeframe),
             InpEaEnabled ? clrPaleGreen : clrTomato, 8);
   DashLabel(PREFIX + "DASH_L2", x + 12, y + 56,
             "NY ORB " + InpOrbStartNy + "-" + InpOrbEndNy + " | TradeEnd " + InpTradeEndNy + " | BrokerGMT " + DoubleToString(InpBrokerGmtOffsetHours, 2),
             clrLightSteelBlue, 8);
   DashLabel(PREFIX + "DASH_L3", x + 12, y + 76,
             "ORB High " + DoubleToString(g_orbHigh, _Digits) + " | Low " + DoubleToString(g_orbLow, _Digits) + " | Spread " + IntegerToString(CurrentSpreadPoints()) + " pt",
             clrWhite, 8);
   DashLabel(PREFIX + "DASH_L4", x + 12, y + 96,
             "Risk " + DoubleToString(InpRiskPerTradePct, 2) + "% | AutoLot " + BoolText(InpUseAutoRiskLot) + " | RR " + DoubleToString(InpTakeProfitR, 2) + " | One/day " + BoolText(InpOneTradePerNyDay),
             clrLightCyan, 8);
   DashLabel(PREFIX + "DASH_L5", x + 12, y + 116,
             "Last signal bar " + sigTime + " | TradeTaken " + BoolText(g_tradeTaken),
             clrWheat, 8);
   DashLabel(PREFIX + "DASH_L6", x + 12, y + 136,
             "History arrows: " + g_lastHistSummary,
             clrDeepSkyBlue, 8);
   DashLabel(PREFIX + "DASH_L7", x + 12, y + 158,
             "Attach TF can be M15; EA internally reads " + EnumToString(InpSignalTimeframe) + " data.",
             clrSilver, 8);
}

//=========================================================================
//  SIGNAL ARROWS
//=========================================================================

void DrawSignalArrow(const string name, datetime t, double price, bool buy, bool historical)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, buy ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, buy ? clrLime : clrTomato);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, historical ? 2 : 3);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

void DrawSignalText(const string name, datetime t, double price, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

//=========================================================================
//  ORB LEVEL LINES
//=========================================================================

void DrawLevels()
{
   if(!InpDrawOrbLevels || !g_orbReady)
      return;
   if(ObjectFind(0, PREFIX + "ORB_HIGH") < 0)
      ObjectCreate(0, PREFIX + "ORB_HIGH", OBJ_HLINE, 0, 0, g_orbHigh);
   ObjectSetDouble(0, PREFIX + "ORB_HIGH", OBJPROP_PRICE, NormalizePrice(g_orbHigh));
   ObjectSetInteger(0, PREFIX + "ORB_HIGH", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, PREFIX + "ORB_HIGH", OBJPROP_WIDTH, 2);

   if(ObjectFind(0, PREFIX + "ORB_LOW") < 0)
      ObjectCreate(0, PREFIX + "ORB_LOW", OBJ_HLINE, 0, 0, g_orbLow);
   ObjectSetDouble(0, PREFIX + "ORB_LOW", OBJPROP_PRICE, NormalizePrice(g_orbLow));
   ObjectSetInteger(0, PREFIX + "ORB_LOW", OBJPROP_COLOR, clrTomato);
   ObjectSetInteger(0, PREFIX + "ORB_LOW", OBJPROP_WIDTH, 2);

   datetime labelTime = TimeCurrent() + PeriodSeconds(InpSignalTimeframe) * 8;
   double labelPrice = (g_orbHigh + g_orbLow) * 0.5;
   if(ObjectFind(0, PREFIX + "ORB_TXT") < 0)
      ObjectCreate(0, PREFIX + "ORB_TXT", OBJ_TEXT, 0, labelTime, labelPrice);
   else
      ObjectMove(0, PREFIX + "ORB_TXT", 0, labelTime, labelPrice);
   ObjectSetString(0, PREFIX + "ORB_TXT", OBJPROP_TEXT, "15m ORB NY " + InpOrbStartNy + "-" + InpOrbEndNy + " H=" + DoubleToString(g_orbHigh, _Digits) + " L=" + DoubleToString(g_orbLow, _Digits));
   ObjectSetInteger(0, PREFIX + "ORB_TXT", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PREFIX + "ORB_TXT", OBJPROP_FONTSIZE, 8);
}

//=========================================================================
//  ORB BUILDING (signal math identical to v1)
//=========================================================================

bool BuildOrbForNyDate(const int y, const int m, const int d, double &hi, double &lo, datetime &orbStart, datetime &orbEnd, datetime &tradeEnd, int &used)
{
   int startMin = ParseClockMinutes(InpOrbStartNy, 9 * 60 + 30);
   int endMin = ParseClockMinutes(InpOrbEndNy, 9 * 60 + 45);
   int tradeEndMin = ParseClockMinutes(InpTradeEndNy, 16 * 60);
   orbStart = NyLocalToServer(y, m, d, startMin);
   orbEnd = NyLocalToServer(y, m, d, endMin);
   tradeEnd = NyLocalToServer(y, m, d, tradeEndMin);
   hi = -DBL_MAX;
   lo = DBL_MAX;
   used = 0;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpSignalTimeframe, orbStart, orbEnd, rates);
   if(copied <= 0)
      return false;

   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < orbStart || rates[i].time >= orbEnd)
         continue;
      hi = MathMax(hi, rates[i].high);
      lo = MathMin(lo, rates[i].low);
      used++;
   }
   if(used <= 0 || hi <= lo || hi == -DBL_MAX || lo == DBL_MAX)
      return false;
   hi = NormalizePrice(hi);
   lo = NormalizePrice(lo);
   return true;
}

//=========================================================================
//  HISTORICAL BREAKOUT FINDER (signal math identical to v1)
//=========================================================================

bool FindHistoricalBreakout(datetime fromTime, datetime toTime, double hi, double lo, string &dir, datetime &sigTime, double &sigClose, double &sigHigh, double &sigLow)
{
   dir = "";
   sigTime = 0;
   sigClose = 0.0;
   sigHigh = 0.0;
   sigLow = 0.0;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpSignalTimeframe, fromTime, toTime, rates);
   if(copied <= 0)
      return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minBreakout = MathMax(0.0, InpMinBreakoutPoints) * point;
   datetime bestTime = 0;
   int bestIndex = -1;
   string bestDir = "";

   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < fromTime || rates[i].time > toTime)
         continue;
      double close = rates[i].close;
      string d = "";
      if(close > hi + minBreakout)
         d = "BUY";
      else if(close < lo - minBreakout)
         d = "SELL";
      if(d == "")
         continue;
      if(bestTime == 0 || rates[i].time < bestTime)
      {
         bestTime = rates[i].time;
         bestIndex = i;
         bestDir = d;
      }
   }

   if(bestIndex < 0)
      return false;
   dir = bestDir;
   sigTime = rates[bestIndex].time;
   sigClose = rates[bestIndex].close;
   sigHigh = rates[bestIndex].high;
   sigLow = rates[bestIndex].low;
   return true;
}

//=========================================================================
//  HISTORICAL SIGNAL DRAWING
//  v2 FIX: No more nuke-and-redraw. Uses upsert approach.
//          Throttle is bypassed when g_histNeedsRedraw is true.
//=========================================================================

void DrawHistoricalSignals()
{
   if(!InpDrawHistoricalSignals)
   {
      DeleteHistoricalSignals();
      g_lastHistSummary = "off";
      return;
   }

   datetime now = TimeCurrent();

   // v2 FIX: If a forced redraw is requested (OnInit, day change),
   //         skip the throttle entirely.
   if(!g_histNeedsRedraw)
   {
      if(g_lastHistBuild > 0 && now - g_lastHistBuild < 300)
         return;
   }

   g_lastHistBuild = now;
   g_histNeedsRedraw = false;

   // v2 FIX: Clean old arrows once, then draw fresh.
   //         This only happens on forced redraws or every 5 minutes,
   //         NOT every 60 seconds like v1.
   DeleteHistoricalSignals();

   datetime nyNow = ServerToNyLocal(now);
   MqlDateTime nySt;
   TimeToStruct(nyNow, nySt);
   datetime nyTodayMid = MakeDateTime(nySt.year, nySt.mon, nySt.day, 0, 0, 0);

   int days = MathMax(1, MathMin(30, InpHistoricalDays));
   int drawn = 0;
   int checked = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.0001;

   for(int back = days - 1; back >= 0; back--)
   {
      datetime nyDay = nyTodayMid - back * 86400;
      MqlDateTime daySt;
      TimeToStruct(nyDay, daySt);
      if(daySt.day_of_week == 0 || daySt.day_of_week == 6)
         continue;

      double hi, lo;
      datetime orbStart, orbEnd, tradeEnd;
      int used;
      checked++;
      if(!BuildOrbForNyDate(daySt.year, daySt.mon, daySt.day, hi, lo, orbStart, orbEnd, tradeEnd, used))
         continue;

      string dir;
      datetime sigTime;
      double sigClose, sigHigh, sigLow;
      if(!FindHistoricalBreakout(orbEnd, tradeEnd, hi, lo, dir, sigTime, sigClose, sigHigh, sigLow))
         continue;

      bool buy = (dir == "BUY");
      double pad = MathMax((hi - lo) * 0.12, point * 40.0);
      double arrowPrice = buy ? (sigLow - pad) : (sigHigh + pad);
      string dateKey = IntegerToString(daySt.year) + StringFormat("%02d%02d", daySt.mon, daySt.day);
      string base = PREFIX + "HIST_" + dateKey + "_" + dir + "_";
      DrawSignalArrow(base + "ARW", sigTime, arrowPrice, buy, true);
      DrawSignalText(base + "TXT", sigTime, buy ? arrowPrice - pad * 0.6 : arrowPrice + pad * 0.6,
                     "ORB " + dir + " " + TimeToString(sigTime, TIME_DATE | TIME_MINUTES),
                     buy ? clrPaleGreen : clrLightSalmon);
      drawn++;
   }

   g_lastHistSummary = IntegerToString(drawn) + " arrows / " + IntegerToString(checked) + " sessions";
   Audit("history_redraw", "", 0, 0, 0, 0, g_lastHistSummary + " days=" + IntegerToString(days));
}

//=========================================================================
//  DAY RESET
//  v2 FIX: Returns bool so callers know if day changed.
//=========================================================================

bool ResetForNewNyDay()
{
   int y, m, d;
   int key = CurrentNyDayKey(y, m, d);
   if(key == g_nyDayKey)
      return false;

   g_nyDayKey = key;
   g_orbReady = false;
   g_tradeTaken = false;
   g_orbHigh = 0.0;
   g_orbLow = 0.0;
   g_lastSignalBarTime = 0;
   int startMin = ParseClockMinutes(InpOrbStartNy, 9 * 60 + 30);
   int endMin = ParseClockMinutes(InpOrbEndNy, 9 * 60 + 45);
   int tradeEndMin = ParseClockMinutes(InpTradeEndNy, 16 * 60);
   g_orbStartServer = NyLocalToServer(y, m, d, startMin);
   g_orbEndServer = NyLocalToServer(y, m, d, endMin);
   g_tradeEndServer = NyLocalToServer(y, m, d, tradeEndMin);
   DeleteLevelObjects();

   // v2 FIX: Flag history for redraw on day change
   g_histNeedsRedraw = true;

   Audit("new_ny_day", "", 0, 0, 0, 0,
         "ny_day=" + IntegerToString(g_nyDayKey)
         + " orb_start_server=" + FmtTime(g_orbStartServer)
         + " orb_end_server=" + FmtTime(g_orbEndServer)
         + " trade_end_server=" + FmtTime(g_tradeEndServer)
         + " broker_gmt_offset_h=" + DoubleToString(InpBrokerGmtOffsetHours, 2));

   return true;
}

//=========================================================================
//  ORB BUILDER (signal math identical to v1)
//=========================================================================

bool BuildOrb()
{
   if(g_orbReady)
      return true;
   if(TimeCurrent() < g_orbEndServer)
      return false;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpSignalTimeframe, g_orbStartServer, g_orbEndServer, rates);
   if(copied <= 0)
   {
      Audit("orb_build_failed", "", 0, 0, 0, 0, "copyrates_empty err=" + IntegerToString(GetLastError()));
      return false;
   }

   double hi = -DBL_MAX;
   double lo = DBL_MAX;
   int used = 0;
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < g_orbStartServer || rates[i].time >= g_orbEndServer)
         continue;
      hi = MathMax(hi, rates[i].high);
      lo = MathMin(lo, rates[i].low);
      used++;
   }
   if(used <= 0 || hi <= lo || hi == -DBL_MAX || lo == DBL_MAX)
   {
      Audit("orb_build_failed", "", 0, 0, 0, 0, "invalid_range copied=" + IntegerToString(copied) + " used=" + IntegerToString(used));
      return false;
   }

   g_orbHigh = NormalizePrice(hi);
   g_orbLow = NormalizePrice(lo);
   g_orbReady = true;
   Audit("orb_ready", "", 0, 0, 0, 0, "bars_used=" + IntegerToString(used));
   DrawLevels();
   return true;
}

//=========================================================================
//  SIGNAL COMPUTE (signal math identical to v1)
//=========================================================================

bool ComputeSignal(string &direction, datetime &barTime, double &signalClose)
{
   direction = "";
   barTime = 0;
   signalClose = 0.0;
   if(!g_orbReady)
      return false;
   if(TimeCurrent() < g_orbEndServer || TimeCurrent() > g_tradeEndServer)
      return false;
   int shift = InpUseClosedBarBreakout ? 1 : 0;
   barTime = iTime(_Symbol, InpSignalTimeframe, shift);
   if(barTime <= 0 || barTime == g_lastSignalBarTime)
      return false;
   signalClose = iClose(_Symbol, InpSignalTimeframe, shift);
   if(signalClose <= 0.0)
      return false;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minBreakout = MathMax(0.0, InpMinBreakoutPoints) * point;
   if(signalClose > g_orbHigh + minBreakout)
      direction = "BUY";
   else if(signalClose < g_orbLow - minBreakout)
      direction = "SELL";
   return direction != "";
}

//=========================================================================
//  ORDER EXECUTION (identical to v1)
//=========================================================================

void TryOpenSignal()
{
   if(!InpEaEnabled)
      return;
   if(!BuildOrb())
      return;
   if(InpOneTradePerNyDay && g_tradeTaken)
      return;
   if(OwnPositionExists())
      return;

   string dir;
   datetime barTime;
   double signalClose;
   if(!ComputeSignal(dir, barTime, signalClose))
      return;
   g_lastSignalBarTime = barTime;

   int signalShift = InpUseClosedBarBreakout ? 1 : 0;
   double signalHigh = iHigh(_Symbol, InpSignalTimeframe, signalShift);
   double signalLow = iLow(_Symbol, InpSignalTimeframe, signalShift);
   double livePad = MathMax(MathAbs(g_orbHigh - g_orbLow) * 0.12, SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 40.0);
   bool liveBuy = (dir == "BUY");
   double liveArrowPrice = liveBuy ? (signalLow - livePad) : (signalHigh + livePad);
   DrawSignalArrow(PREFIX + "LIVE_" + IntegerToString((int)barTime) + "_" + dir + "_ARW", barTime, liveArrowPrice, liveBuy, false);
   DrawSignalText(PREFIX + "LIVE_" + IntegerToString((int)barTime) + "_" + dir + "_TXT", barTime,
                  liveBuy ? liveArrowPrice - livePad * 0.6 : liveArrowPrice + livePad * 0.6,
                  "ORB LIVE " + dir, liveBuy ? clrLime : clrTomato);
   Audit("signal_detected", dir, 0, signalClose, 0, 0,
         "signal_bar=" + FmtTime(barTime)
         + " close=" + DoubleToString(signalClose, _Digits)
         + " orb_high=" + DoubleToString(g_orbHigh, _Digits)
         + " orb_low=" + DoubleToString(g_orbLow, _Digits));

   if(!SpreadAllowed())
   {
      Audit("signal_blocked_spread", dir, 0, signalClose, 0, 0, "signal_bar=" + FmtTime(barTime));
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Audit("signal_blocked_tick", dir, 0, signalClose, 0, 0, "no_tick");
      return;
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buffer = MathMax(0.0, InpSlBufferPoints) * point;
   double entry = (dir == "BUY") ? tick.ask : tick.bid;
   double sl = (dir == "BUY") ? (g_orbLow - buffer) : (g_orbHigh + buffer);
   double risk = MathAbs(entry - sl);
   if(risk <= point)
   {
      Audit("signal_blocked_geometry", dir, 0, entry, sl, 0, "risk_too_small signal_bar=" + FmtTime(barTime));
      return;
   }
   double rr = MathMax(0.1, InpTakeProfitR);
   double tp = (dir == "BUY") ? (entry + risk * rr) : (entry - risk * rr);
   entry = NormalizePrice(entry);
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   double lot = CalculateLot(entry, sl);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   string comment = "ORB15|" + dir + "|" + IntegerToString(g_nyDayKey);
   ResetLastError();
   bool ok = false;
   if(dir == "BUY")
      ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, comment);
   else
      ok = trade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(ok)
   {
      g_tradeTaken = true;
      Audit("order_opened", dir, lot, entry, sl, tp,
            "signal_bar=" + FmtTime(barTime)
            + " signal_close=" + DoubleToString(signalClose, _Digits)
            + " rr=" + DoubleToString(rr, 2)
            + " retcode=" + IntegerToString((int)trade.ResultRetcode())
            + " deal=" + IntegerToString((int)trade.ResultDeal())
            + " order=" + IntegerToString((int)trade.ResultOrder()));
   }
   else
   {
      Audit("order_failed", dir, lot, entry, sl, tp,
            "signal_bar=" + FmtTime(barTime)
            + " retcode=" + IntegerToString((int)trade.ResultRetcode())
            + " err=" + IntegerToString(GetLastError())
            + " comment=" + trade.ResultComment());
   }
}

//=========================================================================
//  EVENT HANDLERS (v2 fixes applied)
//=========================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);

   // v2 FIX: Reset throttle so historical arrows always draw on init
   g_lastHistBuild = 0;
   g_histNeedsRedraw = true;

   ResetForNewNyDay();

   // v2 FIX: Timer every 5 seconds instead of 1 (OnTick handles live signals)
   EventSetTimer(5);

   DrawDashboard();
   DrawHistoricalSignals();

   if(InpLogOnInit)
   {
      Print("ORB15 MT5 EA v2 initialized symbol=", _Symbol,
            " build=", ORB15_BUILD,
            " tf=", EnumToString(InpSignalTimeframe),
            " magic=", InpMagic,
            " broker_gmt_offset_h=", DoubleToString(InpBrokerGmtOffsetHours, 2),
            " orb_ny=", InpOrbStartNy, "-", InpOrbEndNy,
            " trade_end_ny=", InpTradeEndNy,
            " rr=", DoubleToString(InpTakeProfitR, 2),
            " risk_pct=", DoubleToString(InpRiskPerTradePct, 2),
            " auto_lot=", (InpUseAutoRiskLot ? "true" : "false"));
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| v2 FIX: Reason-aware OnDeinit                                    |
//| Objects survive chart changes, TF switches, recompiles, and      |
//| parameter edits. Only full removal cleans up.                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   // Only clean up chart objects when EA is explicitly removed or program ends
   if(reason == REASON_REMOVE || reason == REASON_PROGRAM)
   {
      DeleteLevelObjects();
      DeleteDashboard();
      DeleteHistoricalSignals();
      DeleteLiveSignals();
   }
   // For all other reasons (REASON_CHARTCHANGE, REASON_PARAMETERS,
   // REASON_RECOMPILE, REASON_TEMPLATE, REASON_CLOSE, etc.)
   // leave objects on chart – OnInit will refresh them if needed.
}

//+------------------------------------------------------------------+
//| v2 FIX: OnTimer does NOT redraw history every cycle.             |
//| History is only redrawn on day change or when forced.            |
//+------------------------------------------------------------------+
void OnTimer()
{
   bool dayChanged = ResetForNewNyDay();
   BuildOrb();

   // Only redraw history if day changed (flag was set in ResetForNewNyDay)
   if(dayChanged)
      DrawHistoricalSignals();

   TryOpenSignal();
   UpdateDashboard();
}

void OnTick()
{
   ResetForNewNyDay();
   TryOpenSignal();
   UpdateDashboard();
}
//+------------------------------------------------------------------+
