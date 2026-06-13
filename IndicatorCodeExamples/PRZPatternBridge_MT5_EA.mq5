//+------------------------------------------------------------------+
//| PRZ Pattern Bridge MT5 EA                                        |
//| Object-driven bridge for Asiller\PRZ PATTERN / UAlgoHarmonic.    |
//| Direct MT5 execution, dashboard, risk governor, CSV audit.        |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

#define PRZ_BUILD "2026-06-13.0125-optional-fulltp-half-leg"

enum PRZ_ENTRY_MODE
{
   PRZ_ENTRY_ARROW_PRICE = 0,
   PRZ_ENTRY_PRZ_MID = 1
};

input bool           InpEaEnabled = true;
input bool           InpShowDashboard = true;
input bool           InpTradeLatestSignalOnAttach = false;
input string         InpIndicatorObjectPrefix = "UAlgoHarmonic_";
input int            InpMaxObjectScan = 12000;
input PRZ_ENTRY_MODE InpEntryMode = PRZ_ENTRY_ARROW_PRICE;
input string         InpTargetTpIndex = "2";            // blank/0 = no broker TP; 1..3 = full-close TP leg
input bool           InpCloseOppositeOnNewSignal = true;
input bool           InpDrawTradeLevels = true;
input bool           InpAuditCsv = true;
input bool           InpPositionProbeAudit = true;
input int            InpPositionProbeSeconds = 5;

input bool           InpDirectTradingEnabled = true;
input double         InpFixedLot = 0.10;
input int            InpDeviationPoints = 30;
input int            InpMaxSpreadPoints = 0;           // 0 = off
input string         InpAllowedTradeWindowsGmt = "";   // empty = 24/7, csv HH:MM-HH:MM
input string         InpNoTradeWindowsGmt = "";        // csv HH:MM-HH:MM
input long           InpMagic = 61300113;

input bool           InpHalfCloseEnabled = true;
input double         InpHalfClosePercent = 50.0;
input string         InpHalfBeTpIndex = "0";            // blank/0 = no half/BE; 1..3 = TP leg trigger; R = use InpHalfBeAtR
input double         InpHalfBeAtR = 2.0;                // used only when InpHalfBeTpIndex=R
input double         InpBreakEvenOffsetPoints = 0.0;

input bool           InpAdvancedLotEngineEnabled = false;
input int            InpAdvancedLotDailyAtrPeriod = 14;
input double         InpAdvancedLotMax = 0.0;           // 0 = broker max only
input bool           InpAdvancedAccountRiskEnabled = false;
input double         InpAccountRiskPerTradePct = 1.00;
input double         InpAccountRiskDailyAtrExposurePct = 2.00;
input double         InpAccountRiskMaxPortfolioPct = 4.00;
input double         InpAccountRiskDailyLossLimitPct = 5.00; // 0 = disabled
input double         InpAccountRiskMaxDrawdownPct = 10.00;   // 0 = disabled
input double         InpAccountRiskMaxMarginUsagePct = 40.00;
input double         InpAccountRiskInitialBalanceOverride = 0.00;
input int            InpAccountRiskDayResetHourGmt = 0;
input bool           InpAccountRiskLiquidateOnBreach = true;
input double         InpAccountRiskSafetyBufferPct = 95.00;
input bool           InpAccountRiskBlockUnprotectedPositions = true;
input bool           InpAccountRiskFailClosed = true;
input bool           InpAccountRiskAuditEnabled = true;
input int            InpAccountRiskAuditIntervalSeconds = 60;

CTrade trade;

string PREFIX = "PRZ_BRIDGE_MT5_";
long   g_runtimeMagic = 0;
bool   g_dashboardCollapsed = false;
bool   g_eaEnabledRuntime = true;
double g_fixedLotRuntime = 0.0;
double g_maxSpreadRuntime = 0.0;
double g_halfBeRRuntime = 0.0;
int    g_halfBeTpIndexRuntime = -1; // -1 disabled, 1..3 TP leg, 0 R fallback
int    g_targetTpIndexRuntime = 2; // -1 disabled, 1..3 broker TP leg
string g_allowedWindowsRuntime = "";
string g_noTradeWindowsRuntime = "";
string g_lastEventId = "";
datetime g_lastSignalTime = 0;
int    g_lastSignalDir = 0;
string g_lastSignalPattern = "-";
double g_lastSignalEntry = 0.0;
double g_lastSignalSl = 0.0;
double g_lastSignalTp1 = 0.0;
double g_lastSignalTp2 = 0.0;
double g_lastSignalTp3 = 0.0;
string g_lastStatus = "INIT";
string g_lastBlockReason = "";
datetime g_lastProbeAt = 0;
datetime g_lastRiskAuditAt = 0;
uint   g_lastRiskGuardMs = 0;
bool   g_startupBaselineSet = false;

struct PrzSignal
{
   bool ok;
   int id;
   int dir;
   datetime time;
   double entry;
   double sl;
   double tp1;
   double tp2;
   double tp3;
   double przA;
   double przB;
   string pattern;
   string arrName;
   string eventId;
   string detail;
};

string TfString()
{
   return EnumToString((ENUM_TIMEFRAMES)_Period);
}

string FmtTime(datetime t)
{
   if(t <= 0)
      return "-";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

string DateKey(datetime t)
{
   MqlDateTime st;
   TimeToStruct(t, st);
   return StringFormat("%04d%02d%02d", st.year, st.mon, st.day);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

string DirName(int dir)
{
   if(dir > 0) return "BUY";
   if(dir < 0) return "SELL";
   return "";
}

string Lower(string value)
{
   string v = value;
   StringToLower(v);
   return v;
}

string Trim(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

bool StartsWith(string value, string prefix)
{
   return StringSubstr(value, 0, StringLen(prefix)) == prefix;
}

bool Contains(string value, string needle)
{
   return StringFind(value, needle) >= 0;
}

bool ParseIdAfterToken(string name, string token, int &id)
{
   int p = StringFind(name, token);
   if(p < 0)
      return false;
   string tail = StringSubstr(name, p + StringLen(token));
   if(StringLen(tail) <= 0)
      return false;
   id = (int)StringToInteger(tail);
   return id > 0;
}

string ObjName(string role, int id)
{
   return InpIndicatorObjectPrefix + role + "_" + IntegerToString(id);
}

bool ObjectExists(string name)
{
   return ObjectFind(0, name) >= 0;
}

double ObjectPrice(string name, int pointIndex = 0)
{
   if(!ObjectExists(name))
      return 0.0;
   ResetLastError();
   double price = ObjectGetDouble(0, name, OBJPROP_PRICE, pointIndex);
   if(price == 0.0 && GetLastError() != 0)
      price = ObjectGetDouble(0, name, OBJPROP_PRICE);
   return price;
}

datetime ObjectTime(string name, int pointIndex = 0)
{
   if(!ObjectExists(name))
      return 0;
   ResetLastError();
   datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, pointIndex);
   if(t == 0 && GetLastError() != 0)
      t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
   return t;
}

string ObjectText(string name)
{
   if(!ObjectExists(name))
      return "";
   string txt = ObjectGetString(0, name, OBJPROP_TEXT);
   if(txt == "")
      txt = ObjectGetString(0, name, OBJPROP_TOOLTIP);
   return Trim(txt);
}

color ObjectColor(string name)
{
   if(!ObjectExists(name))
      return clrNONE;
   return (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
}

int DirectionFromColor(color c)
{
   int r = (int)(c & 0x0000FF);
   int g = (int)((c & 0x00FF00) >> 8);
   int b = (int)((c & 0xFF0000) >> 16);
   if(g >= 140 && g >= r + 25)
      return 1;
   if(r >= 180 && r >= g + 25)
      return -1;
   if(b >= 120 && r >= 140 && g < 120)
      return -1;
   return 0;
}

double LevelFromObjectOrText(string lineName, string textName)
{
   double p = ObjectPrice(lineName, 0);
   if(p > 0.0)
      return p;
   p = ObjectPrice(textName, 0);
   if(p > 0.0)
      return p;
   string txt = ObjectText(textName);
   int colon = StringFind(txt, ":");
   if(colon >= 0)
      txt = StringSubstr(txt, colon + 1);
   txt = Trim(txt);
   return StringToDouble(txt);
}

bool ValidSignalGeometry(const PrzSignal &s, string &reason)
{
   if(s.entry <= 0.0 || s.sl <= 0.0)
   {
      reason = "missing_entry_sl";
      return false;
   }
   double fullTp = TargetTp(s);
   double halfTp = (g_halfBeTpIndexRuntime >= 1 ? TpByIndex(s, g_halfBeTpIndexRuntime) : 0.0);
   if(s.dir > 0)
   {
      if(!(s.sl < s.entry))
      {
         reason = "invalid_buy_geometry";
         return false;
      }
      if(g_targetTpIndexRuntime >= 1 && fullTp <= s.entry)
      {
         reason = "invalid_buy_full_tp";
         return false;
      }
      if(g_halfBeTpIndexRuntime >= 1 && halfTp <= s.entry)
      {
         reason = "invalid_buy_half_tp";
         return false;
      }
   }
   else if(s.dir < 0)
   {
      if(!(s.sl > s.entry))
      {
         reason = "invalid_sell_geometry";
         return false;
      }
      if(g_targetTpIndexRuntime >= 1 && fullTp >= s.entry)
      {
         reason = "invalid_sell_full_tp";
         return false;
      }
      if(g_halfBeTpIndexRuntime >= 1 && halfTp >= s.entry)
      {
         reason = "invalid_sell_half_tp";
         return false;
      }
   }
   else
   {
      reason = "missing_direction";
      return false;
   }
   reason = "ok";
   return true;
}

bool FindLatestPrzSignal(PrzSignal &out)
{
   ZeroMemory(out);
   out.ok = false;
   int total = ObjectsTotal(0, 0, -1);
   int scan = MathMin(total, MathMax(100, InpMaxObjectScan));
   datetime bestTime = 0;
   int bestId = -1;
   string bestName = "";

   for(int i = total - 1; i >= 0 && (total - i) <= scan; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(!StartsWith(name, InpIndicatorObjectPrefix + "Arr_"))
         continue;
      int id = 0;
      if(!ParseIdAfterToken(name, "Arr_", id))
         continue;
      int dir = DirectionFromColor(ObjectColor(name));
      if(dir == 0)
         continue;
      datetime t = ObjectTime(name, 0);
      if(t <= 0)
         continue;
      if(t > bestTime || (t == bestTime && id > bestId))
      {
         bestTime = t;
         bestId = id;
         bestName = name;
      }
   }

   if(bestId <= 0)
      return false;

   out.id = bestId;
   out.arrName = bestName;
   out.time = bestTime;
   out.dir = DirectionFromColor(ObjectColor(bestName));
   out.pattern = ObjectText(bestName);
   out.entry = ObjectPrice(bestName, 0);
   string przName = ObjName("PRZ", bestId - 3);
   if(ObjectExists(przName))
   {
      out.przA = ObjectPrice(przName, 0);
      out.przB = ObjectPrice(przName, 1);
      if(InpEntryMode == PRZ_ENTRY_PRZ_MID && out.przA > 0.0 && out.przB > 0.0)
         out.entry = (out.przA + out.przB) * 0.5;
   }

   out.sl = LevelFromObjectOrText(ObjName("Line", bestId + 1), ObjName("Txt", bestId + 5));
   out.tp1 = LevelFromObjectOrText(ObjName("Line", bestId + 2), ObjName("Txt", bestId + 6));
   out.tp2 = LevelFromObjectOrText(ObjName("Line", bestId + 3), ObjName("Txt", bestId + 7));
   out.tp3 = LevelFromObjectOrText(ObjName("Line", bestId + 4), ObjName("Txt", bestId + 8));
   out.entry = NormalizePrice(out.entry);
   out.sl = NormalizePrice(out.sl);
   out.tp1 = NormalizePrice(out.tp1);
   out.tp2 = NormalizePrice(out.tp2);
   out.tp3 = NormalizePrice(out.tp3);
   out.ok = true;
   out.eventId = _Symbol + "|" + TfString() + "|PRZ|" + IntegerToString(out.id) + "|" + DirName(out.dir) + "|" + IntegerToString((int)out.time) + "|" + DoubleToString(out.entry, _Digits);
   out.detail = "arr=" + out.arrName
      + " pattern=" + out.pattern
      + " prz_a=" + DoubleToString(out.przA, _Digits)
      + " prz_b=" + DoubleToString(out.przB, _Digits);
   return true;
}

string AuditFileName()
{
   return "PRZPatternBridge_MT5_DirectAudit_" + DateKey(TimeGMT()) + ".csv";
}

void Audit(string eventName, string eventId, string direction, ulong ticket, double lot, double price, double sl, double tp, string reason, string extra)
{
   if(!InpAuditCsv)
      return;
   int h = FileOpen(AuditFileName(), FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      Print("PRZPatternBridge audit open failed err=", GetLastError());
      return;
   }
   if(FileSize(h) == 0)
      FileWrite(h, "server_time", "gmt_time", "local_time", "event", "build", "symbol", "tf", "event_id", "ticket", "direction", "lot", "price", "sl", "tp", "bid", "ask", "spread_pts", "reason", "extra");
   FileSeek(h, 0, SEEK_END);
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   FileWrite(h,
      FmtTime(TimeCurrent()),
      FmtTime(TimeGMT()),
      FmtTime(TimeLocal()),
      eventName,
      PRZ_BUILD,
      _Symbol,
      TfString(),
      eventId,
      (string)ticket,
      direction,
      DoubleToString(lot, 4),
      DoubleToString(price, _Digits),
      DoubleToString(sl, _Digits),
      DoubleToString(tp, _Digits),
      DoubleToString(tick.bid, _Digits),
      DoubleToString(tick.ask, _Digits),
      IntegerToString((int)MathRound((tick.ask - tick.bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT))),
      reason,
      extra);
   FileClose(h);
}

string RiskAuditFileName()
{
   return "PRZPatternBridge_MT5_AccountRiskAudit_" + DateKey(TimeGMT()) + ".csv";
}

long NormalRuntimeMagic()
{
   return InpMagic * 1000000 + (long)(ChartID() % 1000000);
}

long FtmoRuntimeMagic()
{
   long safe = InpMagic % 1000000000000;
   if(safe < 0) safe = -safe;
   return 4000000000000000000 + safe * 1000000 + (long)(ChartID() % 1000000);
}

long RuntimeMagic()
{
   if(g_runtimeMagic != 0)
      return g_runtimeMagic;
   g_runtimeMagic = InpAdvancedAccountRiskEnabled ? FtmoRuntimeMagic() : NormalRuntimeMagic();
   return g_runtimeMagic;
}

bool MagicScoped(long magic)
{
   return magic == NormalRuntimeMagic() || magic == FtmoRuntimeMagic();
}

double VolumeStep()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   return step;
}

double NormalizeVolume(double volume, bool halfSplit)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = VolumeStep();
   if(minLot <= 0.0) minLot = step;
   if(maxLot <= 0.0) maxLot = 100.0;
   if(InpAdvancedLotMax > 0.0)
      maxLot = MathMin(maxLot, InpAdvancedLotMax);
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / step + 0.0000001) * step;
   if(halfSplit && volume >= minLot * 2.0)
   {
      double half = MathFloor((volume * 0.5) / step + 0.0000001) * step;
      if(half < minLot)
         volume = minLot;
   }
   return NormalizeDouble(MathMax(minLot, volume), 4);
}

double MoneyPerLot(double entry, double sl)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   return MathAbs(entry - sl) / tickSize * tickValue;
}

double D1Atr(int period)
{
   int p = MathMax(2, period);
   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_D1, 1, p + 2, rates);
   if(copied < p + 1)
      return 0.0;
   ArraySetAsSeries(rates, true);
   double sum = 0.0;
   int used = 0;
   for(int i = 0; i < copied - 1 && used < p; i++)
   {
      double prev = rates[i + 1].close;
      double tr = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - prev), MathAbs(rates[i].low - prev)));
      if(tr > 0.0)
      {
         sum += tr;
         used++;
      }
   }
   return used > 0 ? sum / used : 0.0;
}

datetime GmtDayStart()
{
   datetime g = TimeGMT();
   MqlDateTime st;
   TimeToStruct(g, st);
   int h = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   st.hour = h;
   st.min = 0;
   st.sec = 0;
   datetime start = StructToTime(st);
   if(g < start)
      start -= 86400;
   return start;
}

double RiskCapital()
{
   if(InpAccountRiskInitialBalanceOverride > 0.0)
      return InpAccountRiskInitialBalanceOverride;
   return MathMax(1.0, AccountInfoDouble(ACCOUNT_EQUITY));
}

void ScopePnl(double &closedAll, double &closedToday, double &floating, int &positions, int &unprotected)
{
   closedAll = 0.0;
   closedToday = 0.0;
   floating = 0.0;
   positions = 0;
   unprotected = 0;
   datetime dayStart = GmtDayStart();
   datetime from = TimeCurrent() - 86400 * 365;
   HistorySelect(from, TimeCurrent());
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      if(!MagicScoped((long)HistoryDealGetInteger(deal, DEAL_MAGIC)))
         continue;
      double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT)
         + HistoryDealGetDouble(deal, DEAL_SWAP)
         + HistoryDealGetDouble(deal, DEAL_COMMISSION)
         + HistoryDealGetDouble(deal, DEAL_FEE);
      closedAll += pnl;
      if((datetime)HistoryDealGetInteger(deal, DEAL_TIME) >= dayStart)
         closedToday += pnl;
   }
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      positions++;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(PositionGetDouble(POSITION_SL) <= 0.0)
         unprotected++;
   }
}

double OpenRiskMoney()
{
   double risk = 0.0;
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0)
         continue;
      risk += MoneyPerLot(open, sl) * vol;
   }
   return risk;
}

bool AccountRiskBreached(string &reason)
{
   if(!InpAdvancedAccountRiskEnabled)
      return false;
   double closedAll, closedToday, floating;
   int positions, unprotected;
   ScopePnl(closedAll, closedToday, floating, positions, unprotected);
   double cap = RiskCapital();
   double safety = MathMax(1.0, MathMin(100.0, InpAccountRiskSafetyBufferPct)) / 100.0;
   double dailyLossPct = MathMax(0.0, -(closedToday + floating)) / cap * 100.0;
   double totalDdPct = MathMax(0.0, -(closedAll + floating)) / cap * 100.0;
   double marginPct = AccountInfoDouble(ACCOUNT_EQUITY) > 0.0 ? AccountInfoDouble(ACCOUNT_MARGIN) / AccountInfoDouble(ACCOUNT_EQUITY) * 100.0 : 0.0;
   if(InpAccountRiskBlockUnprotectedPositions && unprotected > 0)
   {
      reason = "unprotected_position_count=" + IntegerToString(unprotected);
      return true;
   }
   if(InpAccountRiskDailyLossLimitPct > 0.0 && dailyLossPct >= InpAccountRiskDailyLossLimitPct * safety)
   {
      reason = "daily_loss_limit daily_pct=" + DoubleToString(dailyLossPct, 3);
      return true;
   }
   if(InpAccountRiskMaxDrawdownPct > 0.0 && totalDdPct >= InpAccountRiskMaxDrawdownPct * safety)
   {
      reason = "max_drawdown_limit total_pct=" + DoubleToString(totalDdPct, 3);
      return true;
   }
   if(InpAccountRiskMaxMarginUsagePct > 0.0 && marginPct >= InpAccountRiskMaxMarginUsagePct)
   {
      reason = "margin_limit margin_pct=" + DoubleToString(marginPct, 3);
      return true;
   }
   reason = "ok";
   return false;
}

void WriteAccountRiskAudit(string eventName, string detail)
{
   if(!InpAdvancedAccountRiskEnabled || !InpAccountRiskAuditEnabled)
      return;
   datetime now = TimeCurrent();
   if(eventName == "heartbeat" && g_lastRiskAuditAt > 0 && now - g_lastRiskAuditAt < MathMax(15, InpAccountRiskAuditIntervalSeconds))
      return;
   g_lastRiskAuditAt = now;
   double closedAll, closedToday, floating;
   int positions, unprotected;
   ScopePnl(closedAll, closedToday, floating, positions, unprotected);
   double cap = RiskCapital();
   double openRisk = OpenRiskMoney();
   double tradeBudget = cap * MathMax(0.0, InpAccountRiskPerTradePct) / 100.0;
   double portfolioBudget = cap * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   int h = FileOpen(RiskAuditFileName(), FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
      return;
   if(FileSize(h) == 0)
      FileWrite(h, "server_time", "gmt_time", "event", "build", "symbol", "tf", "risk_capital", "trade_budget", "portfolio_budget", "open_risk", "portfolio_remaining", "closed_all", "closed_today", "floating", "positions", "unprotected", "daily_limit_pct", "max_dd_pct", "detail");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h,
      FmtTime(TimeCurrent()), FmtTime(TimeGMT()), eventName, PRZ_BUILD, _Symbol, TfString(),
      DoubleToString(cap, 2), DoubleToString(tradeBudget, 2), DoubleToString(portfolioBudget, 2),
      DoubleToString(openRisk, 2), DoubleToString(MathMax(0.0, portfolioBudget - openRisk), 2),
      DoubleToString(closedAll, 2), DoubleToString(closedToday, 2), DoubleToString(floating, 2),
      IntegerToString(positions), IntegerToString(unprotected),
      DoubleToString(InpAccountRiskDailyLossLimitPct, 2), DoubleToString(InpAccountRiskMaxDrawdownPct, 2), detail);
   FileClose(h);
}

double ResolveLot(double entry, double sl, bool halfSplit, string &detail)
{
   double fixed = NormalizeVolume(g_fixedLotRuntime, halfSplit);
   if(!InpAdvancedLotEngineEnabled && !InpAdvancedAccountRiskEnabled)
   {
      detail = "fixed_lot";
      return fixed;
   }
   string breach;
   if(AccountRiskBreached(breach))
   {
      detail = "blocked_by_account_risk " + breach;
      return InpAccountRiskFailClosed ? 0.0 : fixed;
   }
   double moneyPerLot = MoneyPerLot(entry, sl);
   if(moneyPerLot <= 0.0)
   {
      detail = "money_per_lot_unavailable";
      return InpAccountRiskFailClosed ? 0.0 : fixed;
   }
   double cap = RiskCapital();
   double tradeBudget = cap * MathMax(0.0, InpAccountRiskPerTradePct) / 100.0;
   double portfolioBudget = cap * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double remainingPortfolio = MathMax(0.0, portfolioBudget - OpenRiskMoney());
   double atr = D1Atr(InpAdvancedLotDailyAtrPeriod);
   double atrMoneyPerLot = atr > 0.0 ? (atr / MathMax(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), SymbolInfoDouble(_Symbol, SYMBOL_POINT)) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)) : 0.0;
   double atrBudget = cap * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double byTrade = tradeBudget / moneyPerLot;
   double byPortfolio = remainingPortfolio > 0.0 ? remainingPortfolio / moneyPerLot : 0.0;
   double byAtr = atrMoneyPerLot > 0.0 && atrBudget > 0.0 ? atrBudget / atrMoneyPerLot : byTrade;
   double raw = MathMin(byTrade, MathMin(byPortfolio, byAtr));
   double vol = NormalizeVolume(raw, halfSplit);
   double margin = 0.0;
   ENUM_ORDER_TYPE orderType = entry >= sl ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   bool marginOk = OrderCalcMargin(orderType, _Symbol, vol, entry, margin);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double projectedMarginPct = equity > 0.0 ? (AccountInfoDouble(ACCOUNT_MARGIN) + margin) / equity * 100.0 : 0.0;
   if(InpAccountRiskMaxMarginUsagePct > 0.0 && projectedMarginPct > InpAccountRiskMaxMarginUsagePct)
   {
      detail = "blocked_projected_margin projected=" + DoubleToString(projectedMarginPct, 2);
      return InpAccountRiskFailClosed ? 0.0 : fixed;
   }
   detail = "advanced_lot raw=" + DoubleToString(raw, 4)
      + " vol=" + DoubleToString(vol, 4)
      + " money_per_lot=" + DoubleToString(moneyPerLot, 2)
      + " trade_budget=" + DoubleToString(tradeBudget, 2)
      + " portfolio_remaining=" + DoubleToString(remainingPortfolio, 2)
      + " atr_budget=" + DoubleToString(atrBudget, 2)
      + " projected_margin_pct=" + DoubleToString(projectedMarginPct, 2)
      + " margin_calc=" + (marginOk ? "ok" : "failed");
   WriteAccountRiskAudit("lot_selected", detail);
   return vol;
}

void LiquidateOnBreach()
{
   if(!InpAdvancedAccountRiskEnabled || !InpAccountRiskLiquidateOnBreach)
      return;
   uint ms = GetTickCount();
   if(ms - g_lastRiskGuardMs < 250)
      return;
   g_lastRiskGuardMs = ms;
   string reason;
   if(!AccountRiskBreached(reason))
      return;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      trade.PositionClose(ticket);
      Audit("account_risk_liquidate", "", "", ticket, PositionGetDouble(POSITION_VOLUME), 0, 0, 0, reason, "retcode=" + IntegerToString((int)trade.ResultRetcode()));
   }
   WriteAccountRiskAudit("liquidate_on_breach", reason);
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

bool TimeInWindow(datetime gmt, string range)
{
   range = Trim(range);
   int dash = StringFind(range, "-");
   if(dash < 0)
      return false;
   string a = Trim(StringSubstr(range, 0, dash));
   string b = Trim(StringSubstr(range, dash + 1));
   int ca = StringFind(a, ":");
   int cb = StringFind(b, ":");
   if(ca < 0 || cb < 0)
      return false;
   int am = (int)StringToInteger(StringSubstr(a, 0, ca)) * 60 + (int)StringToInteger(StringSubstr(a, ca + 1));
   int bm = (int)StringToInteger(StringSubstr(b, 0, cb)) * 60 + (int)StringToInteger(StringSubstr(b, cb + 1));
   MqlDateTime st;
   TimeToStruct(gmt, st);
   int now = st.hour * 60 + st.min;
   if(am <= bm)
      return now >= am && now <= bm;
   return now >= am || now <= bm;
}

bool InAnyWindow(string csv)
{
   csv = Trim(csv);
   if(csv == "")
      return false;
   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
      if(TimeInWindow(TimeGMT(), parts[i]))
         return true;
   return false;
}

bool TradeWindowAllowed(string &reason)
{
   if(g_allowedWindowsRuntime != "" && !InAnyWindow(g_allowedWindowsRuntime))
   {
      reason = "outside_allowed_window_gmt=" + g_allowedWindowsRuntime;
      return false;
   }
   if(g_noTradeWindowsRuntime != "" && InAnyWindow(g_noTradeWindowsRuntime))
   {
      reason = "inside_no_trade_window_gmt=" + g_noTradeWindowsRuntime;
      return false;
   }
   reason = "ok";
   return true;
}

double TargetTp(const PrzSignal &s)
{
   if(g_targetTpIndexRuntime < 1)
      return 0.0;
   int idx = MathMax(1, MathMin(3, g_targetTpIndexRuntime));
   if(idx == 1) return s.tp1;
   if(idx == 3) return s.tp3;
   return s.tp2;
}

double TpByIndex(const PrzSignal &s, int idx)
{
   idx = MathMax(1, MathMin(3, idx));
   if(idx == 1) return s.tp1;
   if(idx == 3) return s.tp3;
   return s.tp2;
}

int ParseHalfTpIndex(string value)
{
   value = Trim(value);
   if(value == "" || value == "0")
      return -1;
   string l = Lower(value);
   if(l == "r")
      return 0;
   int idx = (int)StringToInteger(value);
   if(idx < 1 || idx > 3)
      return -1;
   return idx;
}

int ParseTpIndex(string value)
{
   value = Trim(value);
   if(value == "" || value == "0")
      return -1;
   int idx = (int)StringToInteger(value);
   if(idx < 1 || idx > 3)
      return -1;
   return idx;
}

string TargetTpText()
{
   if(g_targetTpIndexRuntime < 1)
      return "";
   return IntegerToString(g_targetTpIndexRuntime);
}

string HalfTpText()
{
   if(g_halfBeTpIndexRuntime < 0)
      return "";
   if(g_halfBeTpIndexRuntime == 0)
      return "R";
   return IntegerToString(g_halfBeTpIndexRuntime);
}

bool HalfBeEnabled()
{
   return InpHalfCloseEnabled && g_halfBeTpIndexRuntime >= 0;
}

bool EffectiveHalfBeEnabled(string &reason)
{
   if(!HalfBeEnabled())
   {
      reason = "half_disabled";
      return false;
   }
   if(g_halfBeTpIndexRuntime >= 1 && g_targetTpIndexRuntime >= 1 && g_targetTpIndexRuntime <= g_halfBeTpIndexRuntime)
   {
      reason = "half_disabled_by_full_tp_order full_tp=" + IntegerToString(g_targetTpIndexRuntime)
         + " half_tp=" + IntegerToString(g_halfBeTpIndexRuntime);
      return false;
   }
   reason = "half_enabled";
   return true;
}

void CloseOppositePositions(int dir, string eventId)
{
   if(!InpCloseOppositeOnNewSignal)
      return;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int posDir = type == POSITION_TYPE_BUY ? 1 : -1;
      if(posDir == dir)
         continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      bool ok = trade.PositionClose(ticket);
      Audit(ok ? "opposite_closed" : "opposite_close_failed", eventId, DirName(posDir), ticket, vol, 0, 0, 0, ok ? "reverse_signal" : "close_failed", "retcode=" + IntegerToString((int)trade.ResultRetcode()) + " comment=" + trade.ResultComment());
   }
}

string StateKey(string kind, ulong ticket)
{
   return "PRZ_MT5|" + _Symbol + "|" + IntegerToString((int)_Period) + "|" + kind + "|" + (string)ticket;
}

void StorePositionState(ulong ticket, const PrzSignal &s, double trigger)
{
   GlobalVariableSet(StateKey("trigger", ticket), trigger);
   GlobalVariableSet(StateKey("half", ticket), 0.0);
   GlobalVariableSet(StateKey("be", ticket), 0.0);
   GlobalVariableSet(StateKey("signal_id", ticket), (double)s.id);
}

bool StateDone(string kind, ulong ticket)
{
   string k = StateKey(kind, ticket);
   return GlobalVariableCheck(k) && GlobalVariableGet(k) > 0.5;
}

void MarkState(string kind, ulong ticket)
{
   GlobalVariableSet(StateKey(kind, ticket), 1.0);
}

double PositionTrigger(ulong ticket, int dir, double open, double sl)
{
   string k = StateKey("trigger", ticket);
   if(GlobalVariableCheck(k))
      return GlobalVariableGet(k);
   if(g_halfBeTpIndexRuntime < 0)
      return 0.0;
   double r = MathAbs(open - sl);
   if(r <= 0.0 || g_halfBeRRuntime <= 0.0)
      return 0.0;
   return dir > 0 ? open + r * g_halfBeRRuntime : open - r * g_halfBeRRuntime;
}

void ManagePositions()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int dir = type == POSITION_TYPE_BUY ? 1 : -1;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double trigger = PositionTrigger(ticket, dir, open, sl);
      if(trigger <= 0.0 || !HalfBeEnabled())
         continue;
      bool touched = dir > 0 ? tick.bid >= trigger : tick.ask <= trigger;
      if(!touched)
         continue;
      if(!StateDone("be", ticket))
      {
         double be = NormalizePrice(open + dir * InpBreakEvenOffsetPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
         bool shouldMove = dir > 0 ? (sl < be) : (sl > be || sl <= 0.0);
         if(shouldMove)
         {
            bool ok = trade.PositionModify(ticket, be, tp);
            Audit(ok ? "sl_to_be_done" : "sl_to_be_failed", "", DirName(dir), ticket, vol, open, be, tp, "trigger_touched", "trigger=" + DoubleToString(trigger, _Digits) + " retcode=" + IntegerToString((int)trade.ResultRetcode()) + " comment=" + trade.ResultComment());
            if(ok)
               MarkState("be", ticket);
         }
         else
            MarkState("be", ticket);
      }
      if(InpHalfCloseEnabled && !StateDone("half", ticket))
      {
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double closeVol = NormalizeVolume(vol * MathMax(1.0, MathMin(99.0, InpHalfClosePercent)) / 100.0, false);
         if(closeVol >= minLot && vol - closeVol >= minLot)
         {
            bool ok = trade.PositionClosePartial(ticket, closeVol, InpDeviationPoints);
            Audit(ok ? "half_close_done" : "half_close_failed", "", DirName(dir), ticket, closeVol, open, sl, tp, "trigger_touched", "trigger=" + DoubleToString(trigger, _Digits) + " retcode=" + IntegerToString((int)trade.ResultRetcode()) + " comment=" + trade.ResultComment());
            if(ok)
               MarkState("half", ticket);
         }
         else
         {
            MarkState("half", ticket);
            Audit("half_close_skipped", "", DirName(dir), ticket, closeVol, open, sl, tp, "volume_too_small", "pos_vol=" + DoubleToString(vol, 4));
         }
      }
   }
}

void WritePositionProbe()
{
   if(!InpPositionProbeAudit)
      return;
   datetime now = TimeCurrent();
   if(g_lastProbeAt > 0 && now - g_lastProbeAt < MathMax(1, InpPositionProbeSeconds))
      return;
   g_lastProbeAt = now;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      Audit("position_probe", "", type == POSITION_TYPE_BUY ? "BUY" : "SELL", ticket,
         PositionGetDouble(POSITION_VOLUME),
         PositionGetDouble(POSITION_PRICE_OPEN),
         PositionGetDouble(POSITION_SL),
         PositionGetDouble(POSITION_TP),
         "heartbeat",
         "pnl=" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2)
         + " trigger=" + DoubleToString(PositionTrigger(ticket, type == POSITION_TYPE_BUY ? 1 : -1, PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL)), _Digits)
         + " half=" + (StateDone("half", ticket) ? "1" : "0")
         + " be=" + (StateDone("be", ticket) ? "1" : "0"));
   }
}

void DrawTradeLevelsForSignal(const PrzSignal &s)
{
   if(!InpDrawTradeLevels)
      return;
   string base = PREFIX + "LEVEL_";
   ObjectDelete(0, base + "ENTRY");
   ObjectDelete(0, base + "SL");
   ObjectDelete(0, base + "TP");
   string names[3] = {base + "ENTRY", base + "SL", base + "TP"};
   double prices[3] = {s.entry, s.sl, TargetTp(s)};
   color cols[3] = {clrDeepSkyBlue, clrTomato, clrLimeGreen};
   for(int i = 0; i < 3; i++)
   {
      if(prices[i] <= 0.0)
         continue;
      ObjectCreate(0, names[i], OBJ_HLINE, 0, 0, prices[i]);
      ObjectSetDouble(0, names[i], OBJPROP_PRICE, prices[i]);
      ObjectSetInteger(0, names[i], OBJPROP_COLOR, cols[i]);
      ObjectSetInteger(0, names[i], OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, names[i], OBJPROP_WIDTH, 1);
   }
}

bool OpenPrzTrade(const PrzSignal &s)
{
   if(!InpDirectTradingEnabled)
   {
      Audit("trade_skipped", s.eventId, DirName(s.dir), 0, 0, s.entry, s.sl, TargetTp(s), "direct_trading_disabled", s.detail);
      return false;
   }
   string reason;
   if(!TradeWindowAllowed(reason))
   {
      g_lastBlockReason = reason;
      Audit("trade_blocked_window", s.eventId, DirName(s.dir), 0, 0, s.entry, s.sl, TargetTp(s), reason, s.detail);
      return false;
   }
   int spread = CurrentSpreadPoints();
   if(g_maxSpreadRuntime > 0.0 && spread > g_maxSpreadRuntime)
   {
      reason = "spread_blocked live=" + IntegerToString(spread) + " max=" + DoubleToString(g_maxSpreadRuntime, 1);
      g_lastBlockReason = reason;
      Audit("trade_blocked_spread", s.eventId, DirName(s.dir), 0, 0, s.entry, s.sl, TargetTp(s), reason, s.detail);
      return false;
   }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Audit("trade_blocked_tick", s.eventId, DirName(s.dir), 0, 0, s.entry, s.sl, TargetTp(s), "no_tick", s.detail);
      return false;
   }
   double liveEntry = s.dir > 0 ? tick.ask : tick.bid;
   string halfReason;
   bool effectiveHalf = EffectiveHalfBeEnabled(halfReason);
   string lotDetail;
   double lot = ResolveLot(liveEntry, s.sl, effectiveHalf, lotDetail);
   if(lot <= 0.0)
   {
      Audit("trade_blocked_lot", s.eventId, DirName(s.dir), 0, lot, liveEntry, s.sl, TargetTp(s), lotDetail, s.detail);
      return false;
   }
   CloseOppositePositions(s.dir, s.eventId);
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   string comment = "PRZ|" + IntegerToString(s.id) + "|" + DirName(s.dir);
   double tp = TargetTp(s);
   ResetLastError();
   bool ok = false;
   if(s.dir > 0)
      ok = trade.Buy(lot, _Symbol, 0.0, s.sl, tp, comment);
   else
      ok = trade.Sell(lot, _Symbol, 0.0, s.sl, tp, comment);
   ulong ticket = trade.ResultOrder();
   if(ok)
   {
      ulong deal = trade.ResultDeal();
      if(deal > 0)
         ticket = deal;
      double risk = MathAbs(liveEntry - s.sl);
      double trigger = 0.0;
      if(effectiveHalf)
      {
         if(g_halfBeTpIndexRuntime >= 1)
            trigger = TpByIndex(s, g_halfBeTpIndexRuntime);
         else if(g_halfBeTpIndexRuntime == 0 && g_halfBeRRuntime > 0.0)
            trigger = s.dir > 0 ? liveEntry + risk * g_halfBeRRuntime : liveEntry - risk * g_halfBeRRuntime;
      }
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong pt = PositionGetTicket(p);
         if(pt > 0 && PositionSelectByTicket(pt) && PositionGetString(POSITION_SYMBOL) == _Symbol && (long)PositionGetInteger(POSITION_MAGIC) == RuntimeMagic())
         {
            ticket = pt;
            break;
         }
      }
      StorePositionState(ticket, s, trigger);
      DrawTradeLevelsForSignal(s);
      g_lastStatus = "ORDER OPENED";
      g_lastBlockReason = "";
      Audit("order_sent", s.eventId, DirName(s.dir), ticket, lot, liveEntry, s.sl, tp, "ok", s.detail + " " + lotDetail + " full_tp=" + TargetTpText() + " half_tp=" + HalfTpText() + " half_state=" + halfReason + " trigger=" + DoubleToString(trigger, _Digits) + " retcode=" + IntegerToString((int)trade.ResultRetcode()));
      return true;
   }
   g_lastStatus = "ORDER FAILED";
   g_lastBlockReason = trade.ResultComment();
   Audit("order_failed", s.eventId, DirName(s.dir), ticket, lot, liveEntry, s.sl, tp, "send_failed", s.detail + " " + lotDetail + " err=" + IntegerToString(GetLastError()) + " retcode=" + IntegerToString((int)trade.ResultRetcode()) + " comment=" + trade.ResultComment());
   return false;
}

void ProcessSignal(string reason)
{
   if(!g_eaEnabledRuntime)
      return;
   PrzSignal s;
   if(!FindLatestPrzSignal(s))
   {
      g_lastStatus = "NO PRZ SIGNAL";
      return;
   }
   g_lastSignalTime = s.time;
   g_lastSignalDir = s.dir;
   g_lastSignalPattern = s.pattern;
   g_lastSignalEntry = s.entry;
   g_lastSignalSl = s.sl;
   g_lastSignalTp1 = s.tp1;
   g_lastSignalTp2 = s.tp2;
   g_lastSignalTp3 = s.tp3;
   if(!g_startupBaselineSet)
   {
      g_startupBaselineSet = true;
      if(!InpTradeLatestSignalOnAttach)
      {
         g_lastEventId = s.eventId;
         g_lastStatus = "BASELINED";
         Audit("startup_baseline", s.eventId, DirName(s.dir), 0, 0, s.entry, s.sl, TargetTp(s), reason, s.detail);
         return;
      }
   }
   if(s.eventId == g_lastEventId)
      return;
   string geom;
   if(!ValidSignalGeometry(s, geom))
   {
      g_lastEventId = s.eventId;
      g_lastStatus = "GEOMETRY BLOCKED";
      g_lastBlockReason = geom;
      Audit("signal_blocked_geometry", s.eventId, DirName(s.dir), 0, 0, s.entry, s.sl, TargetTp(s), geom, s.detail);
      return;
   }
   Audit("signal_received", s.eventId, DirName(s.dir), 0, 0, s.entry, s.sl, TargetTp(s), reason, s.detail);
   g_lastEventId = s.eventId;
   OpenPrzTrade(s);
}

void ObjRect(string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void ObjLabel(string name, int x, int y, string text, color c, int size = 8)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
}

void ObjEdit(string name, int x, int y, int w, string text)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 18);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'20,26,34');
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
}

void ObjButton(string name, int x, int y, int w, string text, color bg)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
}

double FirstOpenProgress()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return 0.0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || !MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if(sl <= 0.0 || tp <= 0.0)
         return 0.0;
      double px = type == POSITION_TYPE_BUY ? tick.bid : tick.ask;
      double lo = MathMin(sl, tp);
      double hi = MathMax(sl, tp);
      if(hi <= lo)
         return 0.0;
      return MathMax(0.0, MathMin(1.0, (px - lo) / (hi - lo)));
   }
   return 0.0;
}

void DeleteDashboard()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0, -1);
      if(StartsWith(n, PREFIX + "DASH_"))
         ObjectDelete(0, n);
   }
}

void DrawDashboard()
{
   if(!InpShowDashboard)
      return;
   int x = 14, y = 26, w = 390, h = g_dashboardCollapsed ? 42 : 265;
   ObjRect(PREFIX + "DASH_BG", x, y, w, h, C'10,14,20', C'78,141,255');
   ObjLabel(PREFIX + "DASH_TITLE", x + 12, y + 9, "PRZ PATTERN BRIDGE MT5  " + string(PRZ_BUILD), C'190,220,255', 8);
   ObjButton(PREFIX + "DASH_COLLAPSE", x + w - 34, y + 8, 24, g_dashboardCollapsed ? "v" : "^", C'52,70,96');
   if(g_dashboardCollapsed)
      return;
   ObjButton(PREFIX + "DASH_EA", x + 12, y + 34, 78, g_eaEnabledRuntime ? "EA ON" : "EA OFF", g_eaEnabledRuntime ? C'15,115,72' : C'130,32,42');
   ObjButton(PREFIX + "DASH_APPLY", x + 300, y + 34, 74, "APPLY", C'40,70,126');
   ObjLabel(PREFIX + "DASH_LBL1", x + 12, y + 63, "lot", clrSilver);
   ObjEdit(PREFIX + "DASH_LOT", x + 48, y + 59, 60, DoubleToString(g_fixedLotRuntime, 2));
   ObjLabel(PREFIX + "DASH_LBL2", x + 120, y + 63, "max spr", clrSilver);
   ObjEdit(PREFIX + "DASH_SPR", x + 180, y + 59, 54, DoubleToString(g_maxSpreadRuntime, 0));
   ObjLabel(PREFIX + "DASH_LBL3", x + 244, y + 63, "tp#", clrSilver);
   ObjEdit(PREFIX + "DASH_TP", x + 276, y + 59, 34, TargetTpText());
   ObjLabel(PREFIX + "DASH_LBL4", x + 314, y + 63, "half", clrSilver);
   ObjEdit(PREFIX + "DASH_HALF", x + 348, y + 59, 32, HalfTpText());
   ObjLabel(PREFIX + "DASH_W1", x + 12, y + 88, "allow GMT", clrSilver);
   ObjEdit(PREFIX + "DASH_ALLOW", x + 92, y + 84, 130, g_allowedWindowsRuntime);
   ObjLabel(PREFIX + "DASH_W2", x + 232, y + 88, "no trade", clrSilver);
   ObjEdit(PREFIX + "DASH_NO", x + 302, y + 84, 76, g_noTradeWindowsRuntime);
   string sig = "latest: " + DirName(g_lastSignalDir) + " " + FmtTime(g_lastSignalTime) + " " + g_lastSignalPattern;
   ObjLabel(PREFIX + "DASH_SIG", x + 12, y + 114, sig, C'210,220,230', 8);
   ObjLabel(PREFIX + "DASH_LV", x + 12, y + 135,
      "E " + DoubleToString(g_lastSignalEntry, _Digits) + " SL " + DoubleToString(g_lastSignalSl, _Digits)
      + " TP1 " + DoubleToString(g_lastSignalTp1, _Digits)
      + " TP2 " + DoubleToString(g_lastSignalTp2, _Digits)
      + " TP3 " + DoubleToString(g_lastSignalTp3, _Digits), C'170,190,210', 7);
   ObjLabel(PREFIX + "DASH_STATUS", x + 12, y + 158, "status: " + g_lastStatus + " " + g_lastBlockReason, C'255,218,120', 8);
   ObjLabel(PREFIX + "DASH_RISK", x + 12, y + 180,
      "risk: " + (InpAdvancedAccountRiskEnabled ? "ON" : "OFF") + " lot-engine: " + (InpAdvancedLotEngineEnabled ? "ON" : "OFF")
      + " spread " + IntegerToString(CurrentSpreadPoints()) + "pt", C'160,210,255', 8);
   double pr = FirstOpenProgress();
   ObjRect(PREFIX + "DASH_BAR_BG", x + 12, y + 205, 360, 14, C'32,38,46', C'64,72,84');
   ObjRect(PREFIX + "DASH_BAR", x + 12, y + 205, (int)MathRound(360.0 * pr), 14, C'0,175,120', C'0,175,120');
   ObjLabel(PREFIX + "DASH_BAR_TXT", x + 150, y + 204, "SL < live price progress > TP", clrWhite, 7);
   ObjLabel(PREFIX + "DASH_FOOT", x + 12, y + 235, "object source: " + InpIndicatorObjectPrefix + "Arr_* / Line_* / Txt_*", C'120,135,150', 7);
}

void ApplyDashboard()
{
   string v;
   v = ObjectGetString(0, PREFIX + "DASH_LOT", OBJPROP_TEXT);
   if(v != "") g_fixedLotRuntime = MathMax(0.0, StringToDouble(v));
   v = ObjectGetString(0, PREFIX + "DASH_SPR", OBJPROP_TEXT);
   if(v != "") g_maxSpreadRuntime = MathMax(0.0, StringToDouble(v));
   v = ObjectGetString(0, PREFIX + "DASH_TP", OBJPROP_TEXT);
   g_targetTpIndexRuntime = ParseTpIndex(v);
   v = ObjectGetString(0, PREFIX + "DASH_HALF", OBJPROP_TEXT);
   g_halfBeTpIndexRuntime = ParseHalfTpIndex(v);
   v = ObjectGetString(0, PREFIX + "DASH_ALLOW", OBJPROP_TEXT);
   g_allowedWindowsRuntime = Trim(v);
   v = ObjectGetString(0, PREFIX + "DASH_NO", OBJPROP_TEXT);
   g_noTradeWindowsRuntime = Trim(v);
   GlobalVariableSet(PREFIX + _Symbol + "_lot", g_fixedLotRuntime);
   GlobalVariableSet(PREFIX + _Symbol + "_spr", g_maxSpreadRuntime);
   GlobalVariableSet(PREFIX + _Symbol + "_tp", g_targetTpIndexRuntime);
   GlobalVariableSet(PREFIX + _Symbol + "_half_tp", g_halfBeTpIndexRuntime);
   g_lastStatus = "SETTINGS APPLIED";
   Audit("dashboard_apply", "", "", 0, g_fixedLotRuntime, 0, 0, 0, "manual", "max_spread=" + DoubleToString(g_maxSpreadRuntime, 1) + " tp=" + TargetTpText() + " half_tp=" + HalfTpText() + " beR=" + DoubleToString(g_halfBeRRuntime, 2));
}

void LoadRuntime()
{
   g_eaEnabledRuntime = InpEaEnabled;
   g_fixedLotRuntime = InpFixedLot;
   g_maxSpreadRuntime = (double)InpMaxSpreadPoints;
   g_halfBeRRuntime = InpHalfBeAtR;
   g_halfBeTpIndexRuntime = ParseHalfTpIndex(InpHalfBeTpIndex);
   g_targetTpIndexRuntime = ParseTpIndex(InpTargetTpIndex);
   g_allowedWindowsRuntime = Trim(InpAllowedTradeWindowsGmt);
   g_noTradeWindowsRuntime = Trim(InpNoTradeWindowsGmt);
   string k;
   k = PREFIX + _Symbol + "_lot";
   if(GlobalVariableCheck(k)) g_fixedLotRuntime = GlobalVariableGet(k);
   k = PREFIX + _Symbol + "_spr";
   if(GlobalVariableCheck(k)) g_maxSpreadRuntime = GlobalVariableGet(k);
   k = PREFIX + _Symbol + "_tp";
   if(GlobalVariableCheck(k)) g_targetTpIndexRuntime = (int)GlobalVariableGet(k);
   k = PREFIX + _Symbol + "_half_tp";
   if(GlobalVariableCheck(k)) g_halfBeTpIndexRuntime = (int)GlobalVariableGet(k);
}

int OnInit()
{
   LoadRuntime();
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   EventSetTimer(1);
   Print("PRZPatternBridge BUILD=", PRZ_BUILD,
      " symbol=", _Symbol, " tf=", TfString(),
      " prefix=", InpIndicatorObjectPrefix,
      " direct=", (InpDirectTradingEnabled ? "true" : "false"),
      " risk=", (InpAdvancedAccountRiskEnabled ? "true" : "false"),
      " lotEngine=", (InpAdvancedLotEngineEnabled ? "true" : "false"),
      " magic=", RuntimeMagic());
   Audit("init", "", "", 0, g_fixedLotRuntime, 0, 0, 0, "loaded", "build=" + string(PRZ_BUILD));
   WriteAccountRiskAudit("init", "loaded");
   DrawDashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
}

void OnTimer()
{
   LiquidateOnBreach();
   ManagePositions();
   WritePositionProbe();
   WriteAccountRiskAudit("heartbeat", "timer");
   ProcessSignal("timer");
   DrawDashboard();
}

void OnTick()
{
   LiquidateOnBreach();
   ManagePositions();
   ProcessSignal("tick");
   DrawDashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREFIX + "DASH_COLLAPSE")
      {
         g_dashboardCollapsed = !g_dashboardCollapsed;
         DeleteDashboard();
         DrawDashboard();
      }
      else if(sparam == PREFIX + "DASH_EA")
      {
         g_eaEnabledRuntime = !g_eaEnabledRuntime;
         g_lastStatus = g_eaEnabledRuntime ? "EA ENABLED" : "EA DISABLED";
         Audit("dashboard_ea_toggle", "", "", 0, 0, 0, 0, 0, g_lastStatus, "");
         DrawDashboard();
      }
      else if(sparam == PREFIX + "DASH_APPLY")
      {
         ApplyDashboard();
         DrawDashboard();
      }
   }
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(StartsWith(sparam, PREFIX + "DASH_"))
         ApplyDashboard();
   }
}
