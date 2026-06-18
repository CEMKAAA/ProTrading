//+------------------------------------------------------------------+
//| Gold BO ATR Account Governor MT5 EA                              |
//| External account brake for closed-source Gold BO ATR EAs.         |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

#define GBG_BUILD "2026-06-18.gold-bo-atr-account-governor"
#define GBG_PREFIX "GBG_"

input bool   InpGovernorEnabled          = true;
input bool   InpOnlyCurrentSymbol        = false;
input string InpManagedMagicCsv          = "25011850,250118"; // -1 or empty = all magics
input string InpCommentContains          = "";               // optional extra filter
input bool   InpCloseAllAccountOnBreach  = false;            // dangerous: false = only managed magics
input bool   InpDeletePendingOrders      = true;
input bool   InpClosePositionsOnBreach   = true;
input bool   InpFailClosedUntilNextDay   = true;
input double InpDailyLossLimitPct        = 5.0;
input double InpMaxDrawdownPct           = 10.0;
input double InpSafetyBufferPct          = 95.0;
input double InpInitialBalanceOverride   = 0.0;
input int    InpDayResetHourGmt          = 0;
input int    InpCheckSeconds             = 1;
input int    InpMaxClosePasses           = 5;
input int    InpDeviationPoints          = 50;
input bool   InpAuditCsv                 = true;
input bool   InpShowDashboard            = true;
input int    InpDashboardX               = 12;
input int    InpDashboardY               = 20;

CTrade trade;

datetime g_last_check = 0;
datetime g_last_audit = 0;
string   g_status = "INIT";
string   g_reason = "";
double   g_day_start_equity = 0.0;
double   g_initial_balance = 0.0;
double   g_daily_dd_pct = 0.0;
double   g_total_dd_pct = 0.0;
int      g_managed_positions = 0;
int      g_managed_orders = 0;

string Trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string Key(const string suffix)
{
   return GBG_PREFIX + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + suffix;
}

bool MagicInCsv(const long magic)
{
   string csv = Trim(InpManagedMagicCsv);
   if(csv == "" || csv == "-1")
      return true;

   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string p = Trim(parts[i]);
      if(p == "") continue;
      if((long)StringToInteger(p) == magic)
         return true;
   }
   return false;
}

bool SymbolAllowed(const string symbol)
{
   if(!InpOnlyCurrentSymbol)
      return true;
   return symbol == _Symbol;
}

bool CommentAllowed(const string comment)
{
   string needle = Trim(InpCommentContains);
   if(needle == "")
      return true;
   return StringFind(comment, needle) >= 0;
}

bool PositionManaged()
{
   if(InpCloseAllAccountOnBreach)
      return SymbolAllowed(PositionGetString(POSITION_SYMBOL));

   string symbol = PositionGetString(POSITION_SYMBOL);
   long magic = (long)PositionGetInteger(POSITION_MAGIC);
   string comment = PositionGetString(POSITION_COMMENT);
   return SymbolAllowed(symbol) && MagicInCsv(magic) && CommentAllowed(comment);
}

bool OrderManaged()
{
   if(InpCloseAllAccountOnBreach)
      return SymbolAllowed(OrderGetString(ORDER_SYMBOL));

   string symbol = OrderGetString(ORDER_SYMBOL);
   long magic = (long)OrderGetInteger(ORDER_MAGIC);
   string comment = OrderGetString(ORDER_COMMENT);
   return SymbolAllowed(symbol) && MagicInCsv(magic) && CommentAllowed(comment);
}

datetime GmtDayStart()
{
   datetime now = TimeGMT();
   MqlDateTime st;
   TimeToStruct(now, st);
   st.hour = MathMax(0, MathMin(23, InpDayResetHourGmt));
   st.min = 0;
   st.sec = 0;
   datetime start = StructToTime(st);
   if(now < start)
      start -= 86400;
   return start;
}

datetime NextGmtDayStart()
{
   return GmtDayStart() + 86400;
}

double InitialBalance()
{
   if(InpInitialBalanceOverride > 0.0)
      return InpInitialBalanceOverride;
   string k = Key("INITIAL_BALANCE");
   if(!GlobalVariableCheck(k))
      GlobalVariableSet(k, MathMax(0.01, AccountInfoDouble(ACCOUNT_BALANCE)));
   return MathMax(0.01, GlobalVariableGet(k));
}

double DayStartEquity()
{
   datetime day = GmtDayStart();
   string k = Key("DAY_START_EQUITY_" + IntegerToString((int)day));
   if(!GlobalVariableCheck(k))
      GlobalVariableSet(k, MathMax(0.01, AccountInfoDouble(ACCOUNT_EQUITY)));
   return MathMax(0.01, GlobalVariableGet(k));
}

datetime KillUntil()
{
   string k = Key("KILL_UNTIL_GMT");
   if(!GlobalVariableCheck(k))
      return 0;
   return (datetime)GlobalVariableGet(k);
}

bool KillActive()
{
   datetime until = KillUntil();
   if(until <= 0)
      return false;
   if(TimeGMT() >= until)
   {
      GlobalVariableDel(Key("KILL_UNTIL_GMT"));
      return false;
   }
   return true;
}

void ArmKill(const string reason)
{
   if(!InpFailClosedUntilNextDay)
      return;
   datetime until = NextGmtDayStart();
   GlobalVariableSet(Key("KILL_UNTIL_GMT"), (double)until);
   g_reason = reason;
}

string TimeText(datetime t)
{
   if(t <= 0) return "-";
   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

string AuditFile()
{
   MqlDateTime st;
   TimeToStruct(TimeGMT(), st);
   return "GoldBoAtr_AccountGovernor_" + StringFormat("%04d%02d%02d", st.year, st.mon, st.day) + ".csv";
}

void Audit(const string event_name, const string detail)
{
   if(!InpAuditCsv)
      return;
   int flags = FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI;
   string file = AuditFile();
   bool exists = FileIsExist(file);
   int h = FileOpen(file, flags);
   if(h == INVALID_HANDLE)
      return;
   if(!exists || FileSize(h) == 0)
      FileWrite(h, "gmt_time", "event", "status", "reason", "equity", "balance", "day_start_equity",
                "initial_balance", "daily_dd_pct", "total_dd_pct", "positions", "orders", "kill_until", "detail");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeText(TimeGMT()), event_name, g_status, g_reason,
             DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
             DoubleToString(g_day_start_equity, 2),
             DoubleToString(g_initial_balance, 2),
             DoubleToString(g_daily_dd_pct, 3),
             DoubleToString(g_total_dd_pct, 3),
             g_managed_positions, g_managed_orders, TimeText(KillUntil()), detail);
   FileClose(h);
}

void CountManaged()
{
   g_managed_positions = 0;
   g_managed_orders = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionManaged()) g_managed_positions++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderManaged()) g_managed_orders++;
   }
}

void DeleteManagedOrders()
{
   if(!InpDeletePendingOrders)
      return;
   for(int pass = 0; pass < MathMax(1, InpMaxClosePasses); pass++)
   {
      bool any = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0 || !OrderSelect(ticket)) continue;
         if(!OrderManaged()) continue;
         any = true;
         bool ok = trade.OrderDelete(ticket);
         Audit(ok ? "order_deleted" : "order_delete_failed",
               "ticket=" + IntegerToString((long)ticket) + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription());
      }
      if(!any) break;
   }
}

void CloseManagedPositions()
{
   if(!InpClosePositionsOnBreach)
      return;
   for(int pass = 0; pass < MathMax(1, InpMaxClosePasses); pass++)
   {
      bool any = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(!PositionManaged()) continue;
         any = true;
         string symbol = PositionGetString(POSITION_SYMBOL);
         double vol = PositionGetDouble(POSITION_VOLUME);
         bool ok = trade.PositionClose(ticket);
         Audit(ok ? "position_closed" : "position_close_failed",
               "ticket=" + IntegerToString((long)ticket) + " symbol=" + symbol + " vol=" + DoubleToString(vol, 2)
               + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription());
      }
      if(!any) break;
   }
}

bool Breached(string &reason)
{
   g_initial_balance = InitialBalance();
   g_day_start_equity = DayStartEquity();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_daily_dd_pct = g_day_start_equity > 0.0 ? MathMax(0.0, (g_day_start_equity - equity) / g_day_start_equity * 100.0) : 0.0;
   g_total_dd_pct = g_initial_balance > 0.0 ? MathMax(0.0, (g_initial_balance - equity) / g_initial_balance * 100.0) : 0.0;

   double safety = MathMax(1.0, MathMin(100.0, InpSafetyBufferPct)) / 100.0;
   if(InpDailyLossLimitPct > 0.0 && g_daily_dd_pct >= InpDailyLossLimitPct * safety)
   {
      reason = "daily_dd " + DoubleToString(g_daily_dd_pct, 2) + "% >= " + DoubleToString(InpDailyLossLimitPct * safety, 2) + "%";
      return true;
   }
   if(InpMaxDrawdownPct > 0.0 && g_total_dd_pct >= InpMaxDrawdownPct * safety)
   {
      reason = "max_dd " + DoubleToString(g_total_dd_pct, 2) + "% >= " + DoubleToString(InpMaxDrawdownPct * safety, 2) + "%";
      return true;
   }
   reason = "";
   return false;
}

void EnforceBrake(const string reason)
{
   g_status = "KILL";
   g_reason = reason;
   DeleteManagedOrders();
   CloseManagedPositions();
}

void DrawDashboard()
{
   if(!InpShowDashboard)
      return;
   string bg = GBG_PREFIX + "BG";
   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpDashboardX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, InpDashboardY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 470);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 118);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'18,22,30');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, g_status == "KILL" ? clrTomato : clrDodgerBlue);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, 1000000);

   string lines[5];
   lines[0] = "GOLD BO ATR GOVERNOR | " + GBG_BUILD;
   lines[1] = "status=" + g_status + " reason=" + (g_reason == "" ? "-" : g_reason);
   lines[2] = "dailyDD=" + DoubleToString(g_daily_dd_pct, 2) + "% / " + DoubleToString(InpDailyLossLimitPct, 2)
      + "%  totalDD=" + DoubleToString(g_total_dd_pct, 2) + "% / " + DoubleToString(InpMaxDrawdownPct, 2) + "%";
   lines[3] = "managed pos=" + IntegerToString(g_managed_positions) + " orders=" + IntegerToString(g_managed_orders)
      + " magic=[" + InpManagedMagicCsv + "]";
   lines[4] = "kill_until=" + TimeText(KillUntil()) + " resetGMT=" + IntegerToString(MathMax(0, MathMin(23, InpDayResetHourGmt)));

   for(int i = 0; i < 5; i++)
   {
      string obj = GBG_PREFIX + "L" + IntegerToString(i);
      if(ObjectFind(0, obj) < 0)
         ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, InpDashboardX + 12);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, InpDashboardY + 10 + i * 20);
      ObjectSetString(0, obj, OBJPROP_TEXT, lines[i]);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, i == 1 && g_status == "KILL" ? clrLightSalmon : clrWhite);
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, i == 0 ? 9 : 8);
      ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
      ObjectSetInteger(0, obj, OBJPROP_ZORDER, 1000001);
   }
}

void CheckGovernor()
{
   CountManaged();
   string breach_reason = "";
   bool breach = Breached(breach_reason);
   bool kill = KillActive();

   if(!InpGovernorEnabled)
   {
      g_status = "OFF";
      g_reason = "";
   }
   else if(breach)
   {
      ArmKill(breach_reason);
      EnforceBrake(breach_reason);
      Audit("breach", breach_reason);
   }
   else if(kill)
   {
      EnforceBrake("kill_until_next_day");
   }
   else
   {
      g_status = "ARMED";
      g_reason = "";
   }

   if(g_last_audit == 0 || TimeGMT() - g_last_audit >= 60)
   {
      g_last_audit = TimeGMT();
      Audit("heartbeat", "timer");
   }
   DrawDashboard();
}

int OnInit()
{
   trade.SetDeviationInPoints(InpDeviationPoints);
   EventSetTimer(MathMax(1, InpCheckSeconds));
   g_initial_balance = InitialBalance();
   g_day_start_equity = DayStartEquity();
   Audit("init", "loaded");
   CheckGovernor();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, GBG_PREFIX) == 0)
         ObjectDelete(0, n);
   }
   Audit("deinit", "reason=" + IntegerToString(reason));
}

void OnTimer()
{
   CheckGovernor();
}

void OnTick()
{
   datetime now = TimeGMT();
   if(g_last_check == 0 || now - g_last_check >= MathMax(1, InpCheckSeconds))
   {
      g_last_check = now;
      CheckGovernor();
   }
}
