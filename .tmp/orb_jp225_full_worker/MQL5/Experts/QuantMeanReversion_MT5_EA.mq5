//+------------------------------------------------------------------+
//| Quant Mean Reversion MT5 EA                                      |
//| Daily close mean-reversion model based on Quantitativo rules.     |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

#define QMR_BUILD  "2026-06-20.quant-mean-reversion"
#define QMR_PREFIX "QMR_"

enum QMR_MODE
{
   QMR_ORIGINAL = 0,
   QMR_REGIME_LONG_ONLY = 1,
   QMR_DYNAMIC_STOP = 2,
   QMR_LONG_SHORT_SYNTHETIC = 3
};

enum QMR_FILL_MODE
{
   QMR_FILL_NEXT_OPEN = 0,
   QMR_FILL_SIGNAL_CLOSE = 1
};

//=== STRATEGY =========================================================
input bool     InpEaEnabled            = true;
input string   InpDataSymbol           = "";       // Empty = chart symbol.
input QMR_MODE InpMode                 = QMR_DYNAMIC_STOP;
input int      InpMeanRangeDays        = 25;
input int      InpRollingHighDays      = 10;
input double   InpBandMultiplier       = 2.5;
input double   InpIbsLongThreshold     = 0.30;
input double   InpIbsShortThreshold    = 0.70;     // Synthetic short mode only.
input int      InpRegimeSmaDays        = 300;
input bool     InpUseEmergencyAtrStop  = true;     // Catastrophic broker SL for risk sizing.
input int      InpEmergencyAtrDays     = 14;
input double   InpEmergencyAtrMult     = 4.0;
input bool     InpOnePositionOnly      = true;
input bool     InpCloseOnReverse       = true;

//=== EXECUTION / RISK ================================================
input ulong    InpMagic                = 26062001;
input int      InpDeviationPoints      = 50;
input bool     InpUseAutoRiskLot       = true;
input double   InpRiskPerTradePct      = 1.0;
input double   InpFixedLot             = 0.10;
input bool     InpAccountRiskEnabled   = true;
input bool     InpFtmoModeDefault      = false;     // Runtime dashboard toggle can enable FTMO guard without changing presets.
input double   InpMaxPortfolioRiskPct  = 4.0;
input double   InpInitialBalanceOverride = 0.0;
input bool     InpLiquidateOnBreach    = true;
input double   InpDailyLossLimitPct    = 0.0;      // 0 = off.
input double   InpMaxDrawdownPct       = 0.0;      // 0 = off.
input int      InpDayResetHourGmt      = 0;

//=== DASHBOARD / AUDIT / BACKTEST ===================================
input bool     InpShowDashboard        = true;
input int      InpDashboardX           = 14;
input int      InpDashboardY           = 22;
input int      InpHistoricalWeeks      = 20;
input bool     InpShowHistoricalSignals = true;
input bool     InpAuditCsv             = false;
input bool     InpLogOnInit            = false;
input bool     InpTesterTradeAuditCsv  = false;
input QMR_FILL_MODE InpBacktestFillMode = QMR_FILL_NEXT_OPEN;
input double   InpBacktestSpreadPts    = 0.0;
input double   InpBacktestSlippagePts  = 0.0;
input double   InpBacktestCommissionPerLot = 0.0;

CTrade trade;

struct QmrSignal
{
   bool     valid;
   int      dir;
   datetime signalTime;
   double   close;
   double   band;
   double   ibs;
   double   sma;
   double   atr;
   string   reason;
};

struct QmrSimTrade
{
   int      dir;
   datetime signalTime;
   datetime entryTime;
   datetime exitTime;
   double   entry;
   double   exit;
   double   sl;
   double   r;
   double   pnlMoney;
   string   exitReason;
};

bool        g_eaEnabled;
bool        g_ftmoMode;
QMR_MODE    g_mode;
int         g_weeks;
bool        g_auditRuntime;
datetime    g_lastD1Bar = 0;
datetime    g_lastDashboard = 0;
datetime    g_lastRiskGuard = 0;
datetime    g_lastHistBuild = 0;
bool        g_histDirty = true;
int         g_histTotal = 0;
int         g_histWins = 0;
int         g_histLosses = 0;
double      g_histNetR = 0.0;
double      g_histNetMoney = 0.0;
double      g_histMaxDdR = 0.0;
string      g_status = "INIT";
string      g_lastSignal = "-";
string      g_lastReason = "-";
QmrSimTrade g_histTrades[];

string DataSymbol()
{
   string s = InpDataSymbol;
   StringTrimLeft(s);
   StringTrimRight(s);
   return s == "" ? _Symbol : s;
}

string ModeLabel(QMR_MODE m)
{
   if(m == QMR_ORIGINAL) return "ORIGINAL";
   if(m == QMR_REGIME_LONG_ONLY) return "REGIME";
   if(m == QMR_DYNAMIC_STOP) return "DYNSTOP";
   return "LONGSHORT";
}

string BoolText(bool v) { return v ? "ON" : "OFF"; }

bool RiskEnabled() { return InpAccountRiskEnabled || g_ftmoMode; }
double RiskPerTradePct() { return g_ftmoMode ? 1.0 : InpRiskPerTradePct; }
double DailyLossLimitPct() { return g_ftmoMode ? 5.0 : InpDailyLossLimitPct; }
double MaxDrawdownPct() { return g_ftmoMode ? 10.0 : InpMaxDrawdownPct; }
double MaxPortfolioRiskPct() { return g_ftmoMode ? 4.0 : InpMaxPortfolioRiskPct; }

string DateKey(datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return StringFormat("%04d%02d%02d", d.year, d.mon, d.day);
}

string TimeText(datetime t)
{
   if(t <= 0) return "-";
   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

double PointFor(const string symbol)
{
   double p = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return p > 0.0 ? p : _Point;
}

double TickSizeFor(const string symbol)
{
   double t = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   return t > 0.0 ? t : PointFor(symbol);
}

double NormPrice(const string symbol, double price)
{
   double tick = TickSizeFor(symbol);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(tick <= 0.0) return NormalizeDouble(price, digits);
   return NormalizeDouble(MathRound(price / tick) * tick, digits);
}

double NormalizeVolumeFor(const string symbol, double vol)
{
   double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   if(minv <= 0.0) minv = step;
   if(maxv <= 0.0) maxv = 100.0;
   vol = MathMax(minv, MathMin(maxv, vol));
   vol = MathFloor(vol / step + 1e-8) * step;
   return NormalizeDouble(MathMax(minv, vol), 4);
}

bool IsOwnMagic(long magic)
{
   return magic == (long)InpMagic;
}

bool IsOwnPosition()
{
   return PositionGetString(POSITION_SYMBOL) == DataSymbol() && IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC));
}

int OwnPositionCount(int dirFilter = 0)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOwnPosition()) continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      if(dirFilter != 0 && dir != dirFilter) continue;
      count++;
   }
   return count;
}

void DeleteByPrefix(const string prefix)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0) ObjectDelete(0, name);
   }
}

void CreateLabel(const string name, int x, int y, string text, color clr, int size = 8)
{
   string n = QMR_PREFIX + name;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}

void CreateRect(const string name, int x, int y, int w, int h, color bg, color border)
{
   string n = QMR_PREFIX + name;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
}

void CreateButton(const string name, int x, int y, int w, int h, string text, color bg)
{
   string n = QMR_PREFIX + name;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, n, OBJPROP_TEXT, text);
}

bool Clicked(const string sparam, const string shortName)
{
   return sparam == QMR_PREFIX + shortName;
}

double RollingMeanRange(const MqlRates &rates[], int i, int len)
{
   if(i - len + 1 < 0) return 0.0;
   double sum = 0.0;
   for(int k = i - len + 1; k <= i; ++k) sum += MathMax(0.0, rates[k].high - rates[k].low);
   return sum / (double)len;
}

double RollingHigh(const MqlRates &rates[], int i, int len)
{
   if(i - len + 1 < 0) return 0.0;
   double v = rates[i - len + 1].high;
   for(int k = i - len + 2; k <= i; ++k) v = MathMax(v, rates[k].high);
   return v;
}

double RollingLow(const MqlRates &rates[], int i, int len)
{
   if(i - len + 1 < 0) return 0.0;
   double v = rates[i - len + 1].low;
   for(int k = i - len + 2; k <= i; ++k) v = MathMin(v, rates[k].low);
   return v;
}

double SmaClose(const MqlRates &rates[], int i, int len)
{
   if(i - len + 1 < 0) return 0.0;
   double sum = 0.0;
   for(int k = i - len + 1; k <= i; ++k) sum += rates[k].close;
   return sum / (double)len;
}

double AtrSimple(const MqlRates &rates[], int i, int len)
{
   if(i - len + 1 < 1) return 0.0;
   double sum = 0.0;
   for(int k = i - len + 1; k <= i; ++k)
   {
      double tr = MathMax(rates[k].high - rates[k].low,
                  MathMax(MathAbs(rates[k].high - rates[k - 1].close), MathAbs(rates[k].low - rates[k - 1].close)));
      sum += tr;
   }
   return sum / (double)len;
}

double Ibs(const MqlRates &bar)
{
   double range = bar.high - bar.low;
   if(range <= 0.0) return 0.5;
   return (bar.close - bar.low) / range;
}

int WarmupBars()
{
   return MathMax(MathMax(InpMeanRangeDays, InpRollingHighDays), MathMax(InpRegimeSmaDays, InpEmergencyAtrDays)) + 2;
}

bool LoadDailyRates(const string symbol, int weeks, MqlRates &rates[])
{
   SymbolSelect(symbol, true);
   datetime from = TimeCurrent() - (datetime)(86400 * (weeks * 7 + WarmupBars() + 20));
   int copied = CopyRates(symbol, PERIOD_D1, from, TimeCurrent(), rates);
   if(copied < WarmupBars() + 5) return false;
   ArrayResize(rates, copied);
   datetime liveBar = iTime(symbol, PERIOD_D1, 0);
   if(copied > 0 && rates[copied - 1].time >= liveBar)
      ArrayResize(rates, copied - 1);
   return ArraySize(rates) >= WarmupBars() + 5;
}

QmrSignal BuildSignal(const MqlRates &rates[], int i, QMR_MODE mode)
{
   QmrSignal s;
   s.valid = false;
   s.dir = 0;
   s.signalTime = rates[i].time;
   s.close = rates[i].close;
   s.band = 0.0;
   s.ibs = Ibs(rates[i]);
   s.sma = SmaClose(rates, i, InpRegimeSmaDays);
   s.atr = AtrSimple(rates, i, InpEmergencyAtrDays);
   s.reason = "none";

   double meanRange = RollingMeanRange(rates, i, InpMeanRangeDays);
   double high10 = RollingHigh(rates, i, InpRollingHighDays);
   double low10 = RollingLow(rates, i, InpRollingHighDays);
   if(meanRange <= 0.0 || high10 <= 0.0 || low10 <= 0.0 || s.sma <= 0.0)
   {
      s.reason = "warmup";
      return s;
   }

   bool bull = rates[i].close > s.sma;
   bool bear = rates[i].close < s.sma;
   double lowerBand = high10 - InpBandMultiplier * meanRange;
   double upperBand = low10 + InpBandMultiplier * meanRange;

   bool longSignal = rates[i].close < lowerBand && s.ibs < InpIbsLongThreshold;
   bool shortSignal = rates[i].close > upperBand && s.ibs > InpIbsShortThreshold;

   if(mode == QMR_REGIME_LONG_ONLY && !bull)
   {
      s.reason = "regime_bear";
      return s;
   }

   if(mode == QMR_LONG_SHORT_SYNTHETIC && bear && shortSignal)
   {
      s.valid = true;
      s.dir = -1;
      s.band = upperBand;
      s.reason = "synthetic_short";
      return s;
   }

   if(longSignal && (mode != QMR_LONG_SHORT_SYNTHETIC || bull || !bear))
   {
      s.valid = true;
      s.dir = 1;
      s.band = lowerBand;
      s.reason = "long_reversion";
      return s;
   }

   s.reason = longSignal ? "mode_block" : "no_signal";
   return s;
}

bool ExitSignal(const MqlRates &rates[], int i, int dir, QMR_MODE mode, string &reason)
{
   reason = "none";
   double sma = SmaClose(rates, i, InpRegimeSmaDays);
   if(dir > 0)
   {
      if(rates[i].close > rates[i - 1].high)
      {
         reason = "close_gt_yday_high";
         return true;
      }
      if((mode == QMR_DYNAMIC_STOP || mode == QMR_REGIME_LONG_ONLY) && sma > 0.0 && rates[i].close < sma)
      {
         reason = "close_lt_sma_stop";
         return true;
      }
   }
   else
   {
      if(rates[i].close < rates[i - 1].low)
      {
         reason = "close_lt_yday_low";
         return true;
      }
      if(mode == QMR_DYNAMIC_STOP && sma > 0.0 && rates[i].close > sma)
      {
         reason = "close_gt_sma_stop";
         return true;
      }
   }
   return false;
}

double SlForSignal(const string symbol, const QmrSignal &sig, double entry)
{
   if(!InpUseEmergencyAtrStop || sig.atr <= 0.0) return 0.0;
   double dist = MathMax(TickSizeFor(symbol), sig.atr * MathMax(0.1, InpEmergencyAtrMult));
   return NormPrice(symbol, sig.dir > 0 ? entry - dist : entry + dist);
}

double RiskMoneyForLot(const string symbol, double lot, int dir, double entry, double sl)
{
   if(sl <= 0.0 || entry <= 0.0 || lot <= 0.0) return 0.0;
   double profit = 0.0;
   ENUM_ORDER_TYPE type = dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type, symbol, lot, entry, sl, profit)) return 0.0;
   return MathMax(0.0, -profit);
}

double OpenScopeRisk()
{
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      total += RiskMoneyForLot(symbol, vol, dir, entry, sl);
   }
   return total;
}

double CalcLot(const string symbol, int dir, double entry, double sl, string &detail)
{
   if(!InpUseAutoRiskLot)
   {
      detail = "fixed_lot";
      return NormalizeVolumeFor(symbol, InpFixedLot);
   }
   if(sl <= 0.0)
   {
      detail = "no_sl_fixed_lot";
      return NormalizeVolumeFor(symbol, InpFixedLot);
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double budget = equity * MathMax(0.01, RiskPerTradePct()) / 100.0;
   double oneLotRisk = RiskMoneyForLot(symbol, 1.0, dir, entry, sl);
   if(oneLotRisk <= 0.0 || budget <= 0.0)
   {
      detail = "risk_calc_failed";
      return NormalizeVolumeFor(symbol, InpFixedLot);
   }

   if(RiskEnabled())
   {
      double portfolioCap = equity * MathMax(0.01, MaxPortfolioRiskPct()) / 100.0;
      budget = MathMin(budget, MathMax(0.0, portfolioCap - OpenScopeRisk()));
   }
   double lot = budget / oneLotRisk;
   double normalized = NormalizeVolumeFor(symbol, lot);
   detail = "auto lot=" + DoubleToString(normalized, 4) + " budget=" + DoubleToString(budget, 2) + " oneLotRisk=" + DoubleToString(oneLotRisk, 2);
   return normalized;
}

string AuditFile()
{
   return "QuantMeanReversion_Audit_" + DateKey(TimeGMT()) + ".csv";
}

void Audit(const string eventName, const string dir, double lot, double entry, double sl, double exitPx, const string detail)
{
   if(!g_auditRuntime) return;
   string file = AuditFile();
   bool exists = FileIsExist(file);
   int h = FileOpen(file, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   if(!exists || FileSize(h) == 0)
      FileWrite(h, "gmt_time", "event", "build", "symbol", "mode", "dir", "lot", "entry", "sl", "exit", "status", "detail");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeText(TimeGMT()), eventName, QMR_BUILD, DataSymbol(), ModeLabel(g_mode), dir,
             DoubleToString(lot, 4), DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
             DoubleToString(exitPx, _Digits), g_status, detail);
   FileClose(h);
}

double InitialBalance()
{
   if(InpInitialBalanceOverride > 0.0) return InpInitialBalanceOverride;
   string key = QMR_PREFIX + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_INITIAL_BALANCE";
   if(!GlobalVariableCheck(key)) GlobalVariableSet(key, MathMax(0.01, AccountInfoDouble(ACCOUNT_BALANCE)));
   return MathMax(0.01, GlobalVariableGet(key));
}

datetime GmtDayStart()
{
   MqlDateTime d;
   TimeToStruct(TimeGMT(), d);
   d.hour = MathMax(0, MathMin(23, InpDayResetHourGmt));
   d.min = 0;
   d.sec = 0;
   datetime start = StructToTime(d);
   if(TimeGMT() < start) start -= 86400;
   return start;
}

double PnlSince(datetime from, bool onlyToday)
{
   double pnl = 0.0;
   if(!HistorySelect(from, TimeCurrent())) return 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; --i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(!IsOwnMagic((long)HistoryDealGetInteger(deal, DEAL_MAGIC))) continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
      pnl += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return pnl;
}

double FloatingScopePnl()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

void EnforceRiskBreach()
{
   if(!RiskEnabled() || !InpLiquidateOnBreach) return;
   datetime now = TimeCurrent();
   if(now - g_lastRiskGuard < 1) return;
   g_lastRiskGuard = now;

   double init = InitialBalance();
   double floating = FloatingScopePnl();
   double daily = PnlSince(GmtDayStart(), true) + floating;
   double total = PnlSince(0, false) + floating;
   bool breach = false;
   string reason = "";
   if(DailyLossLimitPct() > 0.0 && daily <= -init * DailyLossLimitPct() / 100.0)
   {
      breach = true;
      reason = "daily_loss_breach";
   }
   if(MaxDrawdownPct() > 0.0 && total <= -init * MaxDrawdownPct() / 100.0)
   {
      breach = true;
      reason = reason == "" ? "max_dd_breach" : reason + "|max_dd_breach";
   }
   if(!breach) return;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      trade.PositionClose(ticket);
   }
   g_status = "RISK_BREACH";
   Audit("risk_breach_liquidate", "", 0, 0, 0, 0, reason);
}

double SimMoneyFromR(double r)
{
   return r * 10000.0 * MathMax(0.0, RiskPerTradePct()) / 100.0;
}

void PushTrade(QmrSimTrade &arr[], const QmrSimTrade &tr)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = tr;
}

void Simulate(const MqlRates &rates[], int startIndex, int endIndex, QMR_MODE mode, QmrSimTrade &trades[])
{
   ArrayResize(trades, 0);
   int posDir = 0;
   double entry = 0.0, sl = 0.0, risk = 0.0;
   datetime entryTime = 0, sigTime = 0;

   for(int i = MathMax(startIndex, WarmupBars()); i < endIndex - 1; ++i)
   {
      if(posDir != 0)
      {
         bool stopped = false;
         double exitPx = 0.0;
         string exitReason = "";
         if(sl > 0.0)
         {
            if(posDir > 0 && rates[i + 1].low <= sl)
            {
               stopped = true;
               exitPx = sl;
               exitReason = "emergency_sl";
            }
            if(posDir < 0 && rates[i + 1].high >= sl)
            {
               stopped = true;
               exitPx = sl;
               exitReason = "emergency_sl";
            }
         }

         string closeReason = "";
         if(!stopped && ExitSignal(rates, i, posDir, mode, closeReason))
         {
            exitPx = InpBacktestFillMode == QMR_FILL_SIGNAL_CLOSE ? rates[i].close : rates[i + 1].open;
            exitReason = closeReason;
            stopped = true;
         }

         if(stopped)
         {
            QmrSimTrade tr;
            tr.dir = posDir;
            tr.signalTime = sigTime;
            tr.entryTime = entryTime;
            tr.exitTime = stopped && exitReason == "emergency_sl" ? rates[i + 1].time : (InpBacktestFillMode == QMR_FILL_SIGNAL_CLOSE ? rates[i].time : rates[i + 1].time);
            tr.entry = entry;
            tr.exit = exitPx;
            tr.sl = sl;
            tr.r = risk > 0.0 ? (exitPx - entry) * posDir / risk : 0.0;
            tr.pnlMoney = SimMoneyFromR(tr.r) - InpBacktestCommissionPerLot;
            tr.exitReason = exitReason;
            PushTrade(trades, tr);
            posDir = 0;
         }
      }

      if(posDir != 0) continue;
      QmrSignal sig = BuildSignal(rates, i, mode);
      if(!sig.valid) continue;
      entry = InpBacktestFillMode == QMR_FILL_SIGNAL_CLOSE ? rates[i].close : rates[i + 1].open;
      sl = SlForSignal(DataSymbol(), sig, entry);
      risk = sl > 0.0 ? MathAbs(entry - sl) : MathMax(TickSizeFor(DataSymbol()), sig.atr * MathMax(0.1, InpEmergencyAtrMult));
      if(risk <= 0.0) continue;
      posDir = sig.dir;
      sigTime = sig.signalTime;
      entryTime = InpBacktestFillMode == QMR_FILL_SIGNAL_CLOSE ? rates[i].time : rates[i + 1].time;
   }

   if(posDir != 0 && endIndex > 1)
   {
      int j = endIndex - 1;
      QmrSimTrade tr;
      tr.dir = posDir;
      tr.signalTime = sigTime;
      tr.entryTime = entryTime;
      tr.exitTime = rates[j].time;
      tr.entry = entry;
      tr.exit = rates[j].close;
      tr.sl = sl;
      tr.r = risk > 0.0 ? (tr.exit - entry) * posDir / risk : 0.0;
      tr.pnlMoney = SimMoneyFromR(tr.r);
      tr.exitReason = "open_mark";
      PushTrade(trades, tr);
   }
}

void RebuildHistorical()
{
   MqlRates rates[];
   if(!LoadDailyRates(DataSymbol(), g_weeks, rates))
   {
      g_status = "NO_D1_DATA";
      ArrayResize(g_histTrades, 0);
      g_histTotal = g_histWins = g_histLosses = 0;
      g_histNetR = g_histNetMoney = g_histMaxDdR = 0.0;
      return;
   }

   datetime from = TimeCurrent() - (datetime)(86400 * g_weeks * 7);
   int start = WarmupBars();
   for(int i = WarmupBars(); i < ArraySize(rates); ++i)
   {
      if(rates[i].time >= from)
      {
         start = i;
         break;
      }
   }
   Simulate(rates, start, ArraySize(rates), g_mode, g_histTrades);

   g_histTotal = ArraySize(g_histTrades);
   g_histWins = 0;
   g_histLosses = 0;
   g_histNetR = 0.0;
   g_histNetMoney = 0.0;
   double equityR = 0.0, peakR = 0.0, maxDd = 0.0;
   for(int i = 0; i < g_histTotal; ++i)
   {
      if(g_histTrades[i].r > 0.0) g_histWins++;
      else if(g_histTrades[i].r < 0.0) g_histLosses++;
      g_histNetR += g_histTrades[i].r;
      g_histNetMoney += g_histTrades[i].pnlMoney;
      equityR += g_histTrades[i].r;
      peakR = MathMax(peakR, equityR);
      maxDd = MathMax(maxDd, peakR - equityR);
   }
   g_histMaxDdR = maxDd;
   g_lastHistBuild = TimeCurrent();
   g_histDirty = false;
}

void DrawHistoricalSignals()
{
   DeleteByPrefix(QMR_PREFIX + "SIG_");
   if(!InpShowHistoricalSignals) return;
   int maxDraw = MathMin(ArraySize(g_histTrades), 120);
   int start = MathMax(0, ArraySize(g_histTrades) - maxDraw);
   for(int i = start; i < ArraySize(g_histTrades); ++i)
   {
      QmrSimTrade tr = g_histTrades[i];
      string base = QMR_PREFIX + "SIG_" + IntegerToString(i) + "_";
      double y = tr.dir > 0 ? tr.entry - 3 * PointFor(DataSymbol()) : tr.entry + 3 * PointFor(DataSymbol());
      ObjectCreate(0, base + "A", OBJ_ARROW, 0, tr.signalTime, y);
      ObjectSetInteger(0, base + "A", OBJPROP_ARROWCODE, tr.dir > 0 ? 233 : 234);
      ObjectSetInteger(0, base + "A", OBJPROP_COLOR, tr.r >= 0.0 ? C'70,220,150' : C'255,80,110');
      ObjectSetInteger(0, base + "A", OBJPROP_WIDTH, 2);
      string txt = (tr.dir > 0 ? "BUY " : "SELL ") + (tr.r >= 0.0 ? "WIN " : "LOSS ") + DoubleToString(tr.r, 2) + "R\nSL " + DoubleToString(tr.sl, _Digits) + "\nExit " + tr.exitReason;
      ObjectCreate(0, base + "T", OBJ_TEXT, 0, tr.signalTime, y);
      ObjectSetString(0, base + "T", OBJPROP_TEXT, txt);
      ObjectSetInteger(0, base + "T", OBJPROP_COLOR, tr.r >= 0.0 ? C'70,220,150' : C'255,80,110');
      ObjectSetInteger(0, base + "T", OBJPROP_FONTSIZE, 7);
      ObjectSetString(0, base + "T", OBJPROP_FONT, "Consolas");
   }
}

void UpdateDashboard(bool force = false)
{
   if(!InpShowDashboard) return;
   if(g_histDirty) RebuildHistorical();
   if(force) DrawHistoricalSignals();
   datetime now = TimeCurrent();
   if(!force && now == g_lastDashboard) return;
   g_lastDashboard = now;

   int x = InpDashboardX, y = InpDashboardY, w = 520, h = 245;
   color bg = C'12,18,28', panel = C'20,31,46', ac = C'80,170,255', muted = C'140,155,170';
   CreateRect("BG", x, y, w, h, bg, C'70,110,160');
   CreateRect("TOP", x + 6, y + 6, w - 12, 28, panel, C'70,110,160');
   CreateLabel("TITLE", x + 14, y + 12, "QUANT MR COCKPIT // " + QMR_BUILD, clrWhite, 9);
   CreateLabel("L1", x + 14, y + 44, DataSymbol() + " D1 | Mode " + ModeLabel(g_mode) + " | EA " + BoolText(g_eaEnabled), ac, 8);
   CreateLabel("L2", x + 14, y + 60, "Rules: meanRange " + IntegerToString(InpMeanRangeDays) + " | high " + IntegerToString(InpRollingHighDays) + " | IBS<" + DoubleToString(InpIbsLongThreshold, 2) + " | SMA " + IntegerToString(InpRegimeSmaDays), muted, 8);
   CreateLabel("L3", x + 14, y + 76, "Risk " + DoubleToString(RiskPerTradePct(), 2) + "% | FTMO " + BoolText(g_ftmoMode) + " | Emergency ATR SL " + BoolText(InpUseEmergencyAtrStop) + " x" + DoubleToString(InpEmergencyAtrMult, 1) + " | Audit " + BoolText(g_auditRuntime), muted, 8);

   CreateButton("BTN_EA", x + 14, y + 100, 70, 20, g_eaEnabled ? "EA ON" : "EA OFF", g_eaEnabled ? C'30,130,80' : C'160,45,60');
   CreateButton("BTN_MODE", x + 90, y + 100, 110, 20, ModeLabel(g_mode), C'45,100,175');
   CreateButton("BTN_FTMO", x + 204, y + 100, 74, 20, g_ftmoMode ? "FTMO ON" : "FTMO", g_ftmoMode ? C'30,130,80' : C'75,75,80');
   CreateButton("BTN_2W", x + 282, y + 100, 42, 20, "2W", g_weeks == 2 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_5W", x + 328, y + 100, 42, 20, "5W", g_weeks == 5 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_10W", x + 374, y + 100, 48, 20, "10W", g_weeks == 10 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_20W", x + 426, y + 100, 48, 20, "20W", g_weeks == 20 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_AUDIT", x + 478, y + 100, 62, 20, g_auditRuntime ? "AUD ON" : "AUDIT", g_auditRuntime ? C'120,88,25' : C'75,75,80');

   double wr = g_histTotal > 0 ? 100.0 * (double)g_histWins / (double)g_histTotal : 0.0;
   color wrColor = wr >= 55.0 ? C'80,255,170' : (wr >= 45.0 ? C'255,205,80' : C'255,95,130');
   CreateLabel("S1", x + 14, y + 136, IntegerToString(g_weeks) + "W audit: " + IntegerToString(g_histTotal) + " trades | " + IntegerToString(g_histWins) + "W " + IntegerToString(g_histLosses) + "L | WR " + DoubleToString(wr, 1) + "%", wrColor, 9);
   CreateLabel("S2", x + 14, y + 154, "Net " + DoubleToString(g_histNetR, 2) + "R | $" + DoubleToString(g_histNetMoney, 2) + " | MaxDD " + DoubleToString(g_histMaxDdR, 2) + "R", g_histNetR >= 0.0 ? C'80,255,170' : C'255,95,130', 9);
   CreateLabel("S3", x + 14, y + 172, "Last signal: " + g_lastSignal + " | Status: " + g_status, muted, 8);
   CreateLabel("S4", x + 14, y + 190, "Entry: close < lowerBand and IBS low | Exit: close > yesterday high; dynamic modes add SMA exit.", muted, 7);
   CreateLabel("S5", x + 14, y + 208, "This EA is D1 close based. Attach to any TF; signal source remains D1.", muted, 7);
}

void CloseOwnPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOwnPosition()) continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      bool ok = trade.PositionClose(ticket);
      Audit(ok ? "close" : "close_failed", dir > 0 ? "BUY" : "SELL", vol, entry, sl, 0, reason + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription());
   }
}

bool NewDailyBar()
{
   datetime t = iTime(DataSymbol(), PERIOD_D1, 0);
   if(t <= 0) return false;
   if(g_lastD1Bar == 0)
   {
      g_lastD1Bar = t;
      return true;
   }
   if(t != g_lastD1Bar)
   {
      g_lastD1Bar = t;
      return true;
   }
   return false;
}

bool LoadLiveRates(MqlRates &rates[])
{
   SymbolSelect(DataSymbol(), true);
   int copied = CopyRates(DataSymbol(), PERIOD_D1, 0, WarmupBars() + 20, rates);
   if(copied < WarmupBars() + 3) return false;
   ArraySetAsSeries(rates, true);
   return true;
}

void ProcessDailyClose()
{
   MqlRates rs[];
   if(!LoadLiveRates(rs))
   {
      g_status = "NO_D1_DATA";
      return;
   }

   // Convert the closed-bar series to ascending order for shared math functions.
   int n = ArraySize(rs);
   MqlRates asc[];
   ArrayResize(asc, n);
   for(int i = 0; i < n; ++i) asc[i] = rs[n - 1 - i];
   int closed = n - 2; // last closed D1 bar in ascending array.
   if(closed < WarmupBars()) return;

   string exitReason = "";
   int currentDir = 0;
   if(OwnPositionCount() > 0)
   {
      for(int p = PositionsTotal() - 1; p >= 0; --p)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(!IsOwnPosition()) continue;
         currentDir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
         break;
      }
      if(currentDir != 0 && ExitSignal(asc, closed, currentDir, g_mode, exitReason))
      {
         CloseOwnPositions(exitReason);
         g_status = "EXIT_" + exitReason;
      }
   }

   if(!g_eaEnabled) return;
   if(InpOnePositionOnly && OwnPositionCount() > 0) return;

   QmrSignal sig = BuildSignal(asc, closed, g_mode);
   g_lastReason = sig.reason;
   if(!sig.valid)
   {
      g_lastSignal = "none " + sig.reason;
      return;
   }

   if(InpCloseOnReverse && OwnPositionCount(-sig.dir) > 0) CloseOwnPositions("reverse_signal");
   if(InpOnePositionOnly && OwnPositionCount() > 0) return;

   MqlTick tick;
   if(!SymbolInfoTick(DataSymbol(), tick)) return;
   double entry = sig.dir > 0 ? tick.ask : tick.bid;
   double sl = SlForSignal(DataSymbol(), sig, entry);
   string lotDetail = "";
   double lot = CalcLot(DataSymbol(), sig.dir, entry, sl, lotDetail);
   if(lot <= 0.0)
   {
      Audit("order_blocked", sig.dir > 0 ? "BUY" : "SELL", 0, entry, sl, 0, lotDetail);
      return;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   bool ok = trade.PositionOpen(DataSymbol(), sig.dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot, entry, sl, 0.0, "QMR|" + ModeLabel(g_mode));
   g_lastSignal = (sig.dir > 0 ? "BUY " : "SELL ") + TimeText(sig.signalTime) + " " + sig.reason;
   g_status = ok ? "ORDER_OPENED" : "ORDER_FAILED";
   Audit(ok ? "order_opened" : "order_failed", sig.dir > 0 ? "BUY" : "SELL", lot, entry, sl, 0,
         sig.reason + " ibs=" + DoubleToString(sig.ibs, 3) + " band=" + DoubleToString(sig.band, _Digits) + " sma=" + DoubleToString(sig.sma, _Digits) + " " + lotDetail + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription());
}

void StartBacktestExport()
{
   MqlRates rates[];
   if(!LoadDailyRates(DataSymbol(), g_weeks, rates)) return;
   QmrSimTrade trades[];
   datetime from = TimeCurrent() - (datetime)(86400 * g_weeks * 7);
   int start = WarmupBars();
   for(int i = WarmupBars(); i < ArraySize(rates); ++i)
   {
      if(rates[i].time >= from)
      {
         start = i;
         break;
      }
   }
   Simulate(rates, start, ArraySize(rates), g_mode, trades);
   string file = "QuantMeanReversion_Backtest_" + DateKey(TimeGMT()) + "_" + DataSymbol() + "_" + ModeLabel(g_mode) + ".csv";
   int h = FileOpen(file, FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileWrite(h, "build", "symbol", "mode", "signal_time", "entry_time", "exit_time", "dir", "entry", "sl", "exit", "r", "money", "exit_reason");
   for(int i = 0; i < ArraySize(trades); ++i)
   {
      QmrSimTrade tr = trades[i];
      FileWrite(h, QMR_BUILD, DataSymbol(), ModeLabel(g_mode), TimeText(tr.signalTime), TimeText(tr.entryTime), TimeText(tr.exitTime),
                tr.dir > 0 ? "BUY" : "SELL", DoubleToString(tr.entry, _Digits), DoubleToString(tr.sl, _Digits),
                DoubleToString(tr.exit, _Digits), DoubleToString(tr.r, 4), DoubleToString(tr.pnlMoney, 2), tr.exitReason);
   }
   FileClose(h);
   g_status = "BT_EXPORTED";
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpTesterTradeAuditCsv || !MQLInfoInteger(MQL_TESTER)) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != DataSymbol()) return;
   if(!IsOwnMagic((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC))) return;
   string file = "QuantMeanReversion_TesterDeals_" + DateKey(TimeGMT()) + ".csv";
   bool exists = FileIsExist(file);
   int h = FileOpen(file, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   if(!exists || FileSize(h) == 0)
      FileWrite(h, "time", "deal", "entry", "type", "volume", "price", "profit", "comment");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeText((datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME)), IntegerToString((long)trans.deal),
             IntegerToString((long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY)), IntegerToString((long)HistoryDealGetInteger(trans.deal, DEAL_TYPE)),
             DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 4), DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits),
             DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) + HistoryDealGetDouble(trans.deal, DEAL_FEE), 2),
             HistoryDealGetString(trans.deal, DEAL_COMMENT));
   FileClose(h);
}

int OnInit()
{
   g_eaEnabled = InpEaEnabled;
   g_ftmoMode = InpFtmoModeDefault;
   g_mode = InpMode;
   g_weeks = MathMax(2, MathMin(52, InpHistoricalWeeks));
   g_auditRuntime = InpAuditCsv || InpLogOnInit;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   SymbolSelect(DataSymbol(), true);
   g_lastD1Bar = iTime(DataSymbol(), PERIOD_D1, 0); // Do not auto-trade a stale daily signal on attach.
   EventSetTimer(1);
   RebuildHistorical();
   DrawHistoricalSignals();
   UpdateDashboard(true);
   if(InpLogOnInit) Print("QMR init ", DataSymbol(), " build=", QMR_BUILD, " mode=", ModeLabel(g_mode));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteByPrefix(QMR_PREFIX);
}

void OnTick()
{
   EnforceRiskBreach();
   if(NewDailyBar())
   {
      ProcessDailyClose();
      g_histDirty = true;
   }
}

void OnTimer()
{
   EnforceRiskBreach();
   if(NewDailyBar()) ProcessDailyClose();
   UpdateDashboard(false);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   bool redraw = false;
   if(Clicked(sparam, "BTN_EA"))
   {
      g_eaEnabled = !g_eaEnabled;
      redraw = true;
   }
   else if(Clicked(sparam, "BTN_FTMO"))
   {
      g_ftmoMode = !g_ftmoMode;
      redraw = true;
   }
   else if(Clicked(sparam, "BTN_MODE"))
   {
      int m = (int)g_mode + 1;
      if(m > (int)QMR_LONG_SHORT_SYNTHETIC) m = 0;
      g_mode = (QMR_MODE)m;
      g_histDirty = true;
      redraw = true;
   }
   else if(Clicked(sparam, "BTN_2W")) { g_weeks = 2; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_5W")) { g_weeks = 5; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_10W")) { g_weeks = 10; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_20W")) { g_weeks = 20; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_AUDIT")) { g_auditRuntime = !g_auditRuntime; redraw = true; }

   if(redraw)
   {
      RebuildHistorical();
      DrawHistoricalSignals();
      UpdateDashboard(true);
      ChartRedraw(0);
   }
}
