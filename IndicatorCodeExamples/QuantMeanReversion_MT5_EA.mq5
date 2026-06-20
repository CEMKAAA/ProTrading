//+------------------------------------------------------------------+
//| Quant Mean Reversion MT5 EA                                      |
//| Daily close mean-reversion model based on Quantitativo rules.     |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

#define QMR_BUILD  "2026-06-20.quant-mean-reversion-cluster-guard"
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

enum QMR_EXIT_MODE
{
   QMR_EXIT_DEFAULT = 0,    // Current behavior: mode-specific classic/dynamic exits.
   QMR_EXIT_YDAY_ONLY = 1,  // Close only on previous-bar high/low reclaim.
   QMR_EXIT_SMA_STOP = 2,   // Classic reclaim plus SMA dynamic stop.
   QMR_EXIT_NAS_TP = 3      // Use NAS-style SL/TP geometry and R target.
};

//=== STRATEGY =========================================================
input bool     InpEaEnabled            = true;
input string   InpDataSymbol           = "";       // Empty = chart symbol.
input QMR_MODE InpMode                 = QMR_DYNAMIC_STOP;
input ENUM_TIMEFRAMES InpSignalTf      = PERIOD_D1;
input int      InpMeanRangeDays        = 25;
input int      InpRollingHighDays      = 10;
input double   InpBandMultiplier       = 2.5;
input double   InpIbsLongThreshold     = 0.30;
input double   InpIbsShortThreshold    = 0.70;     // Synthetic short mode only.
input int      InpRegimeSmaDays        = 300;
input QMR_EXIT_MODE InpExitMode        = QMR_EXIT_DEFAULT;
input bool     InpUseEmergencyAtrStop  = true;     // Catastrophic broker SL for risk sizing.
input int      InpEmergencyAtrDays     = 14;
input double   InpEmergencyAtrMult     = 4.0;
input bool     InpUseNasSlTpMode       = false;    // Optional NAS-style execution geometry; signal math is unchanged.
input int      InpNasSwingLookbackDays = 10;
input double   InpNasSlDistancePct     = 100.0;    // 100 = raw NAS-style distance; 80 = tighter; 120 = wider.
input double   InpNasTargetR           = 2.0;
input bool     InpNasBlockSameDirUntilLoss = true;
input bool     InpFirstTouchOnly       = false;    // ON = only first bar entering the mean-reversion zone is tradable.
input int      InpSignalCooldownBars   = 0;        // 0 = off; blocks same-direction accepted signals for N source-TF bars.
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
input bool     InpRiskLotOnlyModeDefault = false;  // 1% risk-lot mode without FTMO daily/max DD overrides.
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
   double   tp;
   double   r;
   double   pnlMoney;
   string   exitReason;
};

bool        g_eaEnabled;
bool        g_ftmoMode;
bool        g_riskLotOnlyMode;
QMR_MODE    g_mode;
ENUM_TIMEFRAMES g_signalTf;
QMR_EXIT_MODE g_exitMode;
int         g_weeks;
bool        g_auditRuntime;
bool        g_nasSlTpMode;
double      g_nasSlDistancePct;
double      g_nasTargetR;
double      g_bandMultiplier;
double      g_ibsLongThreshold;
int         g_regimeSmaDays;
bool        g_firstTouchOnly;
int         g_signalCooldownBars;
datetime    g_lastD1Bar = 0;
datetime    g_lastAcceptedSignalTime = 0;
int         g_lastAcceptedSignalDir = 0;
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

string TfLabel(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
   }
   return EnumToString(tf);
}

string ExitModeLabel(QMR_EXIT_MODE m)
{
   if(m == QMR_EXIT_YDAY_ONLY) return "YDAY";
   if(m == QMR_EXIT_SMA_STOP) return "SMA";
   if(m == QMR_EXIT_NAS_TP) return "NAS_TP";
   return "DEFAULT";
}

string BoolText(bool v) { return v ? "ON" : "OFF"; }

bool ManagedRiskMode() { return g_ftmoMode || g_riskLotOnlyMode; }
string RuntimeRiskModeLabel() { if(g_ftmoMode) return "FTMO"; if(g_riskLotOnlyMode) return "RISKLOT"; return "NORMAL"; }
bool RiskEnabled() { return InpAccountRiskEnabled || ManagedRiskMode(); }
double RiskPerTradePct() { return ManagedRiskMode() ? 1.0 : InpRiskPerTradePct; }
double DailyLossLimitPct() { return g_ftmoMode ? 5.0 : InpDailyLossLimitPct; }
double MaxDrawdownPct() { return g_ftmoMode ? 10.0 : InpMaxDrawdownPct; }
double MaxPortfolioRiskPct() { return g_ftmoMode ? 4.0 : InpMaxPortfolioRiskPct; }
double ClampNasSlPct(double pct) { if(pct <= 0.0) return 100.0; return MathMax(5.0, MathMin(300.0, pct)); }
double ClampNasTargetR(double r) { return MathMax(0.25, MathMin(10.0, r)); }
int ClampCooldownBars(int bars) { return MathMax(0, MathMin(200, bars)); }
bool UseNasExitGeometry() { return g_nasSlTpMode || g_exitMode == QMR_EXIT_NAS_TP; }
int EffectiveRegimeSmaDays() { return MathMax(0, g_regimeSmaDays); }
int ExitSmaDays()
{
   if(g_exitMode == QMR_EXIT_YDAY_ONLY || g_exitMode == QMR_EXIT_NAS_TP) return 0;
   if(g_exitMode == QMR_EXIT_SMA_STOP) return MathMax(1, EffectiveRegimeSmaDays() > 0 ? EffectiveRegimeSmaDays() : InpRegimeSmaDays);
   if(g_mode == QMR_DYNAMIC_STOP || g_mode == QMR_REGIME_LONG_ONLY)
      return MathMax(1, EffectiveRegimeSmaDays() > 0 ? EffectiveRegimeSmaDays() : InpRegimeSmaDays);
   return 0;
}

int ClampHistoricalWeeks(int weeks)
{
   if(weeks <= 20) return 20;
   if(weeks <= 40) return 40;
   return 52;
}

string HistWindowLabel()
{
   if(g_weeks >= 52) return "1Y";
   return IntegerToString(g_weeks) + "W";
}

bool SmaExitEnabled(QMR_MODE mode)
{
   if(g_exitMode == QMR_EXIT_YDAY_ONLY || g_exitMode == QMR_EXIT_NAS_TP) return false;
   if(g_exitMode == QMR_EXIT_SMA_STOP) return true;
   return (mode == QMR_DYNAMIC_STOP || mode == QMR_REGIME_LONG_ONLY);
}

string NasLockPrefix()
{
   return "QMR_NAS_DUPLOCK|" + DataSymbol() + "|" + IntegerToString((int)InpMagic) + "|";
}

void NasDuplicateLockSet(int dir, datetime sigTime)
{
   if(!InpNasBlockSameDirUntilLoss) return;
   GlobalVariableSet(NasLockPrefix() + "DIR", (double)dir);
   GlobalVariableSet(NasLockPrefix() + "SIG", (double)sigTime);
}

void NasDuplicateLockClear(const string reason)
{
   string p = NasLockPrefix();
   if(GlobalVariableCheck(p + "DIR")) GlobalVariableDel(p + "DIR");
   if(GlobalVariableCheck(p + "SIG")) GlobalVariableDel(p + "SIG");
   if(g_auditRuntime) Audit("nas_duplicate_lock_clear", "", 0, 0, 0, 0, reason);
}

bool NasDuplicateBlocked(int dir, string &detail)
{
   detail = "";
   if(!UseNasExitGeometry() || !InpNasBlockSameDirUntilLoss) return false;
   string k = NasLockPrefix() + "DIR";
   if(!GlobalVariableCheck(k)) return false;
   int lockedDir = (int)MathRound(GlobalVariableGet(k));
   if(lockedDir == dir)
   {
      detail = "nas_duplicate_same_dir_block locked_dir=" + IntegerToString(lockedDir);
      return true;
   }
   return false;
}

bool CooldownBlockedLive(const QmrSignal &sig, string &detail)
{
   detail = "";
   if(g_signalCooldownBars <= 0) return false;
   if(g_lastAcceptedSignalDir != sig.dir || g_lastAcceptedSignalTime <= 0) return false;
   int lastShift = iBarShift(DataSymbol(), g_signalTf, g_lastAcceptedSignalTime, true);
   int currentShift = iBarShift(DataSymbol(), g_signalTf, sig.signalTime, true);
   if(lastShift < 0 || currentShift < 0) return false;
   int barsSince = lastShift - currentShift;
   if(barsSince >= 0 && barsSince <= g_signalCooldownBars)
   {
      detail = "cooldown_same_dir bars_since=" + IntegerToString(barsSince) + " limit=" + IntegerToString(g_signalCooldownBars);
      return true;
   }
   return false;
}

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

void CreateEdit(const string name, int x, int y, int w, int h, string text)
{
   string n = QMR_PREFIX + name;
   bool created = false;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      created = true;
   }
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C'34,42,55');
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C'80,105,135');
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, n, OBJPROP_READONLY, false);
   if(created) ObjectSetString(0, n, OBJPROP_TEXT, text);
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
   return MathMax(MathMax(InpMeanRangeDays, InpRollingHighDays), MathMax(MathMax(EffectiveRegimeSmaDays(), ExitSmaDays()), InpEmergencyAtrDays)) + 2;
}

bool LoadSignalRates(const string symbol, ENUM_TIMEFRAMES tf, int weeks, MqlRates &rates[])
{
   SymbolSelect(symbol, true);
   int sec = PeriodSeconds(tf);
   if(sec <= 0) sec = 86400;
   datetime from = TimeCurrent() - (datetime)(86400 * weeks * 7 + sec * (WarmupBars() + 40));
   int copied = CopyRates(symbol, tf, from, TimeCurrent(), rates);
   if(copied < WarmupBars() + 5) return false;
   ArrayResize(rates, copied);
   datetime liveBar = iTime(symbol, tf, 0);
   if(copied > 0 && rates[copied - 1].time >= liveBar)
      ArrayResize(rates, copied - 1);
   return ArraySize(rates) >= WarmupBars() + 5;
}

int RawSignalDirection(const MqlRates &rates[], int i, QMR_MODE mode)
{
   if(i < 0 || i >= ArraySize(rates)) return 0;
   double meanRange = RollingMeanRange(rates, i, InpMeanRangeDays);
   double high10 = RollingHigh(rates, i, InpRollingHighDays);
   double low10 = RollingLow(rates, i, InpRollingHighDays);
   int regimeDays = EffectiveRegimeSmaDays();
   double sma = regimeDays > 0 ? SmaClose(rates, i, regimeDays) : 0.0;
   bool smaRequired = (mode == QMR_REGIME_LONG_ONLY || mode == QMR_LONG_SHORT_SYNTHETIC);
   if(meanRange <= 0.0 || high10 <= 0.0 || low10 <= 0.0 || (smaRequired && sma <= 0.0)) return 0;

   bool bull = sma > 0.0 && rates[i].close > sma;
   bool bear = sma > 0.0 && rates[i].close < sma;
   double lowerBand = high10 - g_bandMultiplier * meanRange;
   double upperBand = low10 + g_bandMultiplier * meanRange;
   bool longSignal = rates[i].close < lowerBand && Ibs(rates[i]) < g_ibsLongThreshold;
   bool shortSignal = rates[i].close > upperBand && Ibs(rates[i]) > InpIbsShortThreshold;

   if(mode == QMR_REGIME_LONG_ONLY && regimeDays > 0 && !bull) return 0;
   if(mode == QMR_LONG_SHORT_SYNTHETIC && ((regimeDays > 0 && bear) || regimeDays <= 0) && shortSignal) return -1;
   if(longSignal && (mode != QMR_LONG_SHORT_SYNTHETIC || regimeDays <= 0 || bull || !bear)) return 1;
   return 0;
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
   int regimeDays = EffectiveRegimeSmaDays();
   s.sma = regimeDays > 0 ? SmaClose(rates, i, regimeDays) : 0.0;
   s.atr = AtrSimple(rates, i, InpEmergencyAtrDays);
   s.reason = "none";

   double meanRange = RollingMeanRange(rates, i, InpMeanRangeDays);
   double high10 = RollingHigh(rates, i, InpRollingHighDays);
   double low10 = RollingLow(rates, i, InpRollingHighDays);
   bool smaRequired = (mode == QMR_REGIME_LONG_ONLY || mode == QMR_LONG_SHORT_SYNTHETIC);
   if(meanRange <= 0.0 || high10 <= 0.0 || low10 <= 0.0 || (smaRequired && s.sma <= 0.0))
   {
      s.reason = "warmup";
      return s;
   }

   bool hasSma = s.sma > 0.0;
   bool bull = hasSma && rates[i].close > s.sma;
   bool bear = hasSma && rates[i].close < s.sma;
   double lowerBand = high10 - g_bandMultiplier * meanRange;
   double upperBand = low10 + g_bandMultiplier * meanRange;

   bool longSignal = rates[i].close < lowerBand && s.ibs < g_ibsLongThreshold;
   bool shortSignal = rates[i].close > upperBand && s.ibs > InpIbsShortThreshold;

   if(mode == QMR_REGIME_LONG_ONLY && regimeDays > 0 && !bull)
   {
      s.reason = "regime_bear";
      return s;
   }

   if(mode == QMR_LONG_SHORT_SYNTHETIC && ((regimeDays > 0 && bear) || regimeDays <= 0) && shortSignal)
   {
      if(g_firstTouchOnly && RawSignalDirection(rates, i - 1, mode) == -1)
      {
         s.reason = "first_touch_repeat_short";
         return s;
      }
      s.valid = true;
      s.dir = -1;
      s.band = upperBand;
      s.reason = "synthetic_short";
      return s;
   }

   if(longSignal && (mode != QMR_LONG_SHORT_SYNTHETIC || regimeDays <= 0 || bull || !bear))
   {
      if(g_firstTouchOnly && RawSignalDirection(rates, i - 1, mode) == 1)
      {
         s.reason = "first_touch_repeat_long";
         return s;
      }
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
   int exitSma = ExitSmaDays();
   double sma = exitSma > 0 ? SmaClose(rates, i, exitSma) : 0.0;
   if(dir > 0)
   {
      if(rates[i].close > rates[i - 1].high)
      {
         reason = "close_gt_yday_high";
         return true;
      }
      if(SmaExitEnabled(mode) && sma > 0.0 && rates[i].close < sma)
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
      if(SmaExitEnabled(mode) && sma > 0.0 && rates[i].close > sma)
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

bool NasStyleGeometry(const string symbol, const MqlRates &rates[], int i, const QmrSignal &sig,
                      double entry, double &sl, double &tp, string &detail)
{
   sl = 0.0;
   tp = 0.0;
   detail = "";
   if(!UseNasExitGeometry())
   {
      sl = SlForSignal(symbol, sig, entry);
      return true;
   }

   double tick = TickSizeFor(symbol);
   double atr = sig.atr > 0.0 ? sig.atr : AtrSimple(rates, i, InpEmergencyAtrDays);
   if(atr <= tick)
   {
      detail = "nas_geom_no_atr";
      return false;
   }

   int lookback = MathMax(2, InpNasSwingLookbackDays);
   int from = MathMax(1, i - lookback + 1);
   double swing = sig.dir > 0 ? rates[from].low : rates[from].high;
   for(int k = from + 1; k <= i; ++k)
   {
      if(sig.dir > 0) swing = MathMin(swing, rates[k].low);
      else swing = MathMax(swing, rates[k].high);
   }

   double atrDist = MathMax(tick, atr * MathMax(0.1, InpEmergencyAtrMult));
   double swingDist = MathAbs(entry - swing);
   double rawDist = MathMax(atrDist, swingDist);
   double scaledDist = MathMax(tick, rawDist * ClampNasSlPct(g_nasSlDistancePct) / 100.0);
   sl = NormPrice(symbol, sig.dir > 0 ? entry - scaledDist : entry + scaledDist);

   double risk = MathAbs(entry - sl);
   if(risk <= tick)
   {
      detail = "nas_geom_invalid_risk";
      return false;
   }
   double r = ClampNasTargetR(g_nasTargetR);
   tp = NormPrice(symbol, sig.dir > 0 ? entry + risk * r : entry - risk * r);
   detail = "nas_geom=on atr_dist=" + DoubleToString(atrDist, _Digits)
      + " swing_dist=" + DoubleToString(swingDist, _Digits)
      + " sl_pct=" + DoubleToString(ClampNasSlPct(g_nasSlDistancePct), 1)
      + " tp_r=" + DoubleToString(r, 2);
   return true;
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
   if(!InpUseAutoRiskLot && !ManagedRiskMode())
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
      FileWrite(h, "gmt_time", "event", "build", "symbol", "mode", "dir", "lot", "entry", "sl", "exit_or_tp", "status", "detail");
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
   double entry = 0.0, sl = 0.0, tp = 0.0, risk = 0.0;
   datetime entryTime = 0, sigTime = 0;
   int lockedDir = 0;
   int lastAcceptedSignalIndex = -1000000;
   int lastAcceptedSignalDir = 0;
   bool useNasExit = UseNasExitGeometry();

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
               exitReason = useNasExit ? "nas_sl" : "emergency_sl";
            }
            if(posDir < 0 && rates[i + 1].high >= sl)
            {
               stopped = true;
               exitPx = sl;
               exitReason = useNasExit ? "nas_sl" : "emergency_sl";
            }
         }

         if(!stopped && useNasExit && tp > 0.0)
         {
            if(posDir > 0 && rates[i + 1].high >= tp)
            {
               stopped = true;
               exitPx = tp;
               exitReason = "nas_tp";
            }
            if(posDir < 0 && rates[i + 1].low <= tp)
            {
               stopped = true;
               exitPx = tp;
               exitReason = "nas_tp";
            }
         }

         string closeReason = "";
         if(!useNasExit && !stopped && ExitSignal(rates, i, posDir, mode, closeReason))
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
            bool levelExit = (exitReason == "emergency_sl" || exitReason == "nas_sl" || exitReason == "nas_tp");
            tr.exitTime = levelExit ? rates[i + 1].time : (InpBacktestFillMode == QMR_FILL_SIGNAL_CLOSE ? rates[i].time : rates[i + 1].time);
            tr.entry = entry;
            tr.exit = exitPx;
            tr.sl = sl;
            tr.tp = tp;
            tr.r = risk > 0.0 ? (exitPx - entry) * posDir / risk : 0.0;
            tr.pnlMoney = SimMoneyFromR(tr.r) - InpBacktestCommissionPerLot;
            tr.exitReason = exitReason;
            PushTrade(trades, tr);
            if(useNasExit && tr.r < 0.0) lockedDir = 0;
            posDir = 0;
         }
      }

      if(posDir != 0) continue;
      QmrSignal sig = BuildSignal(rates, i, mode);
      if(!sig.valid) continue;
      if(g_signalCooldownBars > 0 && lastAcceptedSignalDir == sig.dir && i - lastAcceptedSignalIndex <= g_signalCooldownBars)
         continue;
      if(useNasExit && InpNasBlockSameDirUntilLoss)
      {
         if(lockedDir != 0 && lockedDir != sig.dir) lockedDir = 0;
         if(lockedDir == sig.dir) continue;
      }
      entry = InpBacktestFillMode == QMR_FILL_SIGNAL_CLOSE ? rates[i].close : rates[i + 1].open;
      string geomDetail = "";
      if(!NasStyleGeometry(DataSymbol(), rates, i, sig, entry, sl, tp, geomDetail)) continue;
      risk = sl > 0.0 ? MathAbs(entry - sl) : MathMax(TickSizeFor(DataSymbol()), sig.atr * MathMax(0.1, InpEmergencyAtrMult));
      if(risk <= 0.0) continue;
      posDir = sig.dir;
      if(useNasExit && InpNasBlockSameDirUntilLoss) lockedDir = sig.dir;
      lastAcceptedSignalIndex = i;
      lastAcceptedSignalDir = sig.dir;
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
      tr.tp = tp;
      tr.r = risk > 0.0 ? (tr.exit - entry) * posDir / risk : 0.0;
      tr.pnlMoney = SimMoneyFromR(tr.r);
      tr.exitReason = "open_mark";
      PushTrade(trades, tr);
   }
}

void RebuildHistorical()
{
   MqlRates rates[];
   if(!LoadSignalRates(DataSymbol(), g_signalTf, g_weeks, rates))
   {
      g_status = "NO_" + TfLabel(g_signalTf) + "_DATA";
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
      string txt = (tr.dir > 0 ? "BUY " : "SELL ") + (tr.r >= 0.0 ? "WIN " : "LOSS ") + DoubleToString(tr.r, 2) + "R\nSL " + DoubleToString(tr.sl, _Digits);
      if(tr.tp > 0.0) txt += "\nTP " + DoubleToString(tr.tp, _Digits);
      txt += "\nExit " + tr.exitReason;
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

   int x = InpDashboardX, y = InpDashboardY, w = 720, h = 405;
   color bg = C'12,18,28', panel = C'20,31,46', ac = C'80,170,255', muted = C'140,155,170';
   CreateRect("BG", x, y, w, h, bg, C'70,110,160');
   CreateRect("TOP", x + 6, y + 6, w - 12, 28, panel, C'70,110,160');
   CreateLabel("TITLE", x + 14, y + 12, "QUANT MR COCKPIT // " + QMR_BUILD, clrWhite, 9);
   CreateLabel("L1", x + 14, y + 44, DataSymbol() + " " + TfLabel(g_signalTf) + " | Mode " + ModeLabel(g_mode) + " | Exit " + ExitModeLabel(g_exitMode) + " | EA " + BoolText(g_eaEnabled), ac, 8);
   CreateLabel("L2", x + 14, y + 60, "Rules: meanRange " + IntegerToString(InpMeanRangeDays) + " | high " + IntegerToString(InpRollingHighDays) + " | band " + DoubleToString(g_bandMultiplier, 2) + " | IBS<" + DoubleToString(g_ibsLongThreshold, 2) + " | Regime " + (EffectiveRegimeSmaDays() > 0 ? IntegerToString(EffectiveRegimeSmaDays()) : "OFF") + " | ExitSMA " + (ExitSmaDays() > 0 ? IntegerToString(ExitSmaDays()) : "OFF"), muted, 8);
   CreateLabel("L3", x + 14, y + 76, "Risk " + DoubleToString(RiskPerTradePct(), 2) + "% | Mode " + RuntimeRiskModeLabel() + " | NAS SL/TP " + BoolText(UseNasExitGeometry()) + " | Audit " + BoolText(g_auditRuntime), muted, 8);

   CreateButton("BTN_EA", x + 14, y + 100, 70, 20, g_eaEnabled ? "EA ON" : "EA OFF", g_eaEnabled ? C'30,130,80' : C'160,45,60');
   CreateButton("BTN_MODE", x + 90, y + 100, 110, 20, ModeLabel(g_mode), C'45,100,175');
   CreateButton("BTN_FTMO", x + 204, y + 100, 58, 20, g_ftmoMode ? "FTMO" : "FTMO", g_ftmoMode ? C'30,130,80' : C'75,75,80');
   CreateButton("BTN_RISKLOT", x + 266, y + 100, 62, 20, g_riskLotOnlyMode ? "RISK" : "RISK", g_riskLotOnlyMode ? C'30,130,80' : C'75,75,80');
   CreateButton("BTN_20W", x + 332, y + 100, 52, 20, "20W", g_weeks == 20 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_40W", x + 388, y + 100, 52, 20, "40W", g_weeks == 40 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_1Y", x + 444, y + 100, 52, 20, "1Y", g_weeks >= 52 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_AUDIT", x + 502, y + 100, 62, 20, g_auditRuntime ? "AUD ON" : "AUDIT", g_auditRuntime ? C'120,88,25' : C'75,75,80');
   CreateButton("BTN_EXPORT", x + 568, y + 100, 78, 20, "EXPORT", C'75,75,80');
   CreateButton("BTN_NASGEOM", x + 14, y + 124, 78, 20, g_nasSlTpMode ? "NAS:ON" : "NAS:OFF", g_nasSlTpMode ? C'30,130,80' : C'75,75,80');
   CreateLabel("NAS_SL_L", x + 100, y + 128, "SL%:", muted, 7);
   CreateEdit("EDIT_NAS_SL", x + 132, y + 124, 48, 20, DoubleToString(g_nasSlDistancePct, 0));
   CreateLabel("NAS_TPR_L", x + 188, y + 128, "TPR:", muted, 7);
   CreateEdit("EDIT_NAS_TPR", x + 222, y + 124, 48, 20, DoubleToString(g_nasTargetR, 2));
   CreateButton("BTN_NAS_APPLY", x + 278, y + 124, 58, 20, "APPLY", C'45,100,175');

   CreateLabel("TF_L", x + 14, y + 154, "TF", muted, 7);
   CreateButton("BTN_TF_D1", x + 48, y + 148, 48, 20, "D1", g_signalTf == PERIOD_D1 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_TF_H4", x + 100, y + 148, 48, 20, "H4", g_signalTf == PERIOD_H4 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_TF_H1", x + 152, y + 148, 48, 20, "H1", g_signalTf == PERIOD_H1 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_TF_M30", x + 204, y + 148, 54, 20, "M30", g_signalTf == PERIOD_M30 ? C'45,100,175' : C'75,75,80');

   CreateLabel("BAND_L", x + 276, y + 154, "Band", muted, 7);
   CreateButton("BTN_BAND_175", x + 318, y + 148, 48, 20, "1.75", MathAbs(g_bandMultiplier - 1.75) < 0.001 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_BAND_200", x + 370, y + 148, 48, 20, "2.00", MathAbs(g_bandMultiplier - 2.0) < 0.001 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_BAND_250", x + 422, y + 148, 48, 20, "2.50", MathAbs(g_bandMultiplier - 2.5) < 0.001 ? C'45,100,175' : C'75,75,80');

   CreateLabel("IBS_L", x + 490, y + 154, "IBS", muted, 7);
   CreateButton("BTN_IBS_025", x + 526, y + 148, 44, 20, "0.25", MathAbs(g_ibsLongThreshold - 0.25) < 0.001 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_IBS_030", x + 574, y + 148, 44, 20, "0.30", MathAbs(g_ibsLongThreshold - 0.30) < 0.001 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_IBS_035", x + 622, y + 148, 44, 20, "0.35", MathAbs(g_ibsLongThreshold - 0.35) < 0.001 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_IBS_040", x + 670, y + 148, 44, 20, "0.40", MathAbs(g_ibsLongThreshold - 0.40) < 0.001 ? C'45,100,175' : C'75,75,80');

   CreateLabel("REG_L", x + 14, y + 178, "Regime", muted, 7);
   CreateButton("BTN_REG_OFF", x + 70, y + 172, 48, 20, "OFF", EffectiveRegimeSmaDays() == 0 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_REG_50", x + 122, y + 172, 42, 20, "50", EffectiveRegimeSmaDays() == 50 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_REG_100", x + 168, y + 172, 46, 20, "100", EffectiveRegimeSmaDays() == 100 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_REG_150", x + 218, y + 172, 46, 20, "150", EffectiveRegimeSmaDays() == 150 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_REG_200", x + 268, y + 172, 46, 20, "200", EffectiveRegimeSmaDays() == 200 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_REG_250", x + 318, y + 172, 46, 20, "250", EffectiveRegimeSmaDays() == 250 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_REG_300", x + 368, y + 172, 46, 20, "300", EffectiveRegimeSmaDays() == 300 ? C'45,100,175' : C'75,75,80');

   CreateLabel("EXIT_L", x + 432, y + 178, "Exit", muted, 7);
   CreateButton("BTN_EXIT_DEF", x + 470, y + 172, 58, 20, "DEF", g_exitMode == QMR_EXIT_DEFAULT ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_EXIT_YDAY", x + 532, y + 172, 58, 20, "YDAY", g_exitMode == QMR_EXIT_YDAY_ONLY ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_EXIT_SMA", x + 594, y + 172, 52, 20, "SMA", g_exitMode == QMR_EXIT_SMA_STOP ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_EXIT_NAS", x + 650, y + 172, 64, 20, "NAS TP", g_exitMode == QMR_EXIT_NAS_TP ? C'45,100,175' : C'75,75,80');

   CreateLabel("CL_L", x + 14, y + 202, "Cluster", muted, 7);
   CreateButton("BTN_FT", x + 70, y + 196, 70, 20, g_firstTouchOnly ? "FT:ON" : "FT:OFF", g_firstTouchOnly ? C'30,130,80' : C'75,75,80');
   CreateButton("BTN_CD_0", x + 146, y + 196, 42, 20, "CD0", g_signalCooldownBars == 0 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_CD_5", x + 192, y + 196, 42, 20, "CD5", g_signalCooldownBars == 5 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_CD_10", x + 238, y + 196, 48, 20, "CD10", g_signalCooldownBars == 10 ? C'45,100,175' : C'75,75,80');
   CreateButton("BTN_CD_20", x + 290, y + 196, 48, 20, "CD20", g_signalCooldownBars == 20 ? C'45,100,175' : C'75,75,80');

   double wr = g_histTotal > 0 ? 100.0 * (double)g_histWins / (double)g_histTotal : 0.0;
   color wrColor = wr >= 55.0 ? C'80,255,170' : (wr >= 45.0 ? C'255,205,80' : C'255,95,130');
   CreateLabel("S1", x + 14, y + 234, HistWindowLabel() + " audit: " + IntegerToString(g_histTotal) + " trades | " + IntegerToString(g_histWins) + "W " + IntegerToString(g_histLosses) + "L | WR " + DoubleToString(wr, 1) + "%", wrColor, 9);
   CreateLabel("S2", x + 14, y + 252, "Net " + DoubleToString(g_histNetR, 2) + "R | $" + DoubleToString(g_histNetMoney, 2) + " | MaxDD " + DoubleToString(g_histMaxDdR, 2) + "R", g_histNetR >= 0.0 ? C'80,255,170' : C'255,95,130', 9);
   CreateLabel("S3", x + 14, y + 270, "Last signal: " + g_lastSignal + " | Status: " + g_status, muted, 8);
   CreateLabel("S4", x + 14, y + 288, "Default reproduces old D1/DYNSTOP/Band2.5/IBS0.30/SMA300 behavior. Buttons are research overrides.", muted, 7);
   CreateLabel("S5", x + 14, y + 306, "Cluster: FT keeps first zone touch only; CD blocks same-direction accepted signals for N source bars.", muted, 7);
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
   datetime t = iTime(DataSymbol(), g_signalTf, 0);
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
   int copied = CopyRates(DataSymbol(), g_signalTf, 0, WarmupBars() + 20, rates);
   if(copied < WarmupBars() + 3) return false;
   ArraySetAsSeries(rates, true);
   return true;
}

void ProcessDailyClose()
{
   MqlRates rs[];
   if(!LoadLiveRates(rs))
   {
      g_status = "NO_" + TfLabel(g_signalTf) + "_DATA";
      return;
   }

   // Convert the closed-bar series to ascending order for shared math functions.
   int n = ArraySize(rs);
   MqlRates asc[];
   ArrayResize(asc, n);
   for(int i = 0; i < n; ++i) asc[i] = rs[n - 1 - i];
   int closed = n - 2; // last closed source-TF bar in ascending array.
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
      if(!UseNasExitGeometry() && currentDir != 0 && ExitSignal(asc, closed, currentDir, g_mode, exitReason))
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
   if(UseNasExitGeometry() && InpNasBlockSameDirUntilLoss && GlobalVariableCheck(NasLockPrefix() + "DIR"))
   {
      int lockedDir = (int)MathRound(GlobalVariableGet(NasLockPrefix() + "DIR"));
      if(lockedDir != 0 && lockedDir != sig.dir) NasDuplicateLockClear("opposite_signal " + (sig.dir > 0 ? "BUY" : "SELL"));
   }
   string duplicateDetail = "";
   if(NasDuplicateBlocked(sig.dir, duplicateDetail))
   {
      g_lastSignal = (sig.dir > 0 ? "BUY " : "SELL ") + TimeText(sig.signalTime) + " " + duplicateDetail;
      g_status = "DUPLICATE_BLOCKED";
      Audit("order_blocked_duplicate", sig.dir > 0 ? "BUY" : "SELL", 0, 0, 0, 0, duplicateDetail);
      return;
   }
   string cooldownDetail = "";
   if(CooldownBlockedLive(sig, cooldownDetail))
   {
      g_lastSignal = (sig.dir > 0 ? "BUY " : "SELL ") + TimeText(sig.signalTime) + " " + cooldownDetail;
      g_status = "COOLDOWN_BLOCKED";
      Audit("order_blocked_cooldown", sig.dir > 0 ? "BUY" : "SELL", 0, 0, 0, 0, cooldownDetail);
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(DataSymbol(), tick)) return;
   double entry = sig.dir > 0 ? tick.ask : tick.bid;
   double sl = 0.0, tp = 0.0;
   string geomDetail = "";
   if(!NasStyleGeometry(DataSymbol(), asc, closed, sig, entry, sl, tp, geomDetail))
   {
      g_status = "GEOMETRY_BLOCKED";
      Audit("order_blocked_geometry", sig.dir > 0 ? "BUY" : "SELL", 0, entry, sl, tp, geomDetail);
      return;
   }
   string lotDetail = "";
   double lot = CalcLot(DataSymbol(), sig.dir, entry, sl, lotDetail);
   if(lot <= 0.0)
   {
      Audit("order_blocked", sig.dir > 0 ? "BUY" : "SELL", 0, entry, sl, 0, lotDetail);
      return;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   bool ok = trade.PositionOpen(DataSymbol(), sig.dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot, entry, sl, tp, "QMR|" + ModeLabel(g_mode));
   if(ok && UseNasExitGeometry()) NasDuplicateLockSet(sig.dir, sig.signalTime);
   if(ok)
   {
      g_lastAcceptedSignalTime = sig.signalTime;
      g_lastAcceptedSignalDir = sig.dir;
   }
   g_lastSignal = (sig.dir > 0 ? "BUY " : "SELL ") + TimeText(sig.signalTime) + " " + sig.reason;
   g_status = ok ? "ORDER_OPENED" : "ORDER_FAILED";
   Audit(ok ? "order_opened" : "order_failed", sig.dir > 0 ? "BUY" : "SELL", lot, entry, sl, tp,
         sig.reason + " ibs=" + DoubleToString(sig.ibs, 3) + " band=" + DoubleToString(sig.band, _Digits) + " sma=" + DoubleToString(sig.sma, _Digits) + " " + geomDetail + " " + lotDetail + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription());
}

void StartBacktestExport()
{
   MqlRates rates[];
   if(!LoadSignalRates(DataSymbol(), g_signalTf, g_weeks, rates)) return;
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
   string file = "QuantMeanReversion_Backtest_" + DateKey(TimeGMT()) + "_" + DataSymbol() + "_" + TfLabel(g_signalTf) + "_" + ModeLabel(g_mode) + ".csv";
   int h = FileOpen(file, FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileWrite(h, "build", "symbol", "tf", "mode", "exit_mode", "band_mult", "ibs_long", "regime_sma", "first_touch_only", "cooldown_bars", "nas_sl_tp_mode", "signal_time", "entry_time", "exit_time", "dir", "entry", "sl", "tp", "exit", "r", "money", "exit_reason");
   for(int i = 0; i < ArraySize(trades); ++i)
   {
      QmrSimTrade tr = trades[i];
      FileWrite(h, QMR_BUILD, DataSymbol(), TfLabel(g_signalTf), ModeLabel(g_mode), ExitModeLabel(g_exitMode),
                DoubleToString(g_bandMultiplier, 2), DoubleToString(g_ibsLongThreshold, 2), IntegerToString(EffectiveRegimeSmaDays()),
                g_firstTouchOnly ? "1" : "0", IntegerToString(g_signalCooldownBars), UseNasExitGeometry() ? "1" : "0",
                TimeText(tr.signalTime), TimeText(tr.entryTime), TimeText(tr.exitTime),
                tr.dir > 0 ? "BUY" : "SELL", DoubleToString(tr.entry, _Digits), DoubleToString(tr.sl, _Digits),
                DoubleToString(tr.tp, _Digits), DoubleToString(tr.exit, _Digits), DoubleToString(tr.r, 4), DoubleToString(tr.pnlMoney, 2), tr.exitReason);
   }
   FileClose(h);
   g_status = "BT_EXPORTED";
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != DataSymbol()) return;
   if(!IsOwnMagic((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC))) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   double dealPnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
      + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
      + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
      + HistoryDealGetDouble(trans.deal, DEAL_FEE);
   if(UseNasExitGeometry() && (entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT))
   {
      if(dealPnl < -0.0001) NasDuplicateLockClear("closed_loss deal=" + IntegerToString((long)trans.deal) + " pnl=" + DoubleToString(dealPnl, 2));
      else Audit("nas_duplicate_lock_kept", "", 0, 0, 0, 0, "closed_non_loss deal=" + IntegerToString((long)trans.deal) + " pnl=" + DoubleToString(dealPnl, 2));
   }

   if(!InpTesterTradeAuditCsv || !MQLInfoInteger(MQL_TESTER)) return;
   string file = "QuantMeanReversion_TesterDeals_" + DateKey(TimeGMT()) + ".csv";
   bool exists = FileIsExist(file);
   int h = FileOpen(file, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   if(!exists || FileSize(h) == 0)
      FileWrite(h, "time", "deal", "entry", "type", "volume", "price", "profit", "comment");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeText((datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME)), IntegerToString((long)trans.deal),
             IntegerToString((long)entryType), IntegerToString((long)HistoryDealGetInteger(trans.deal, DEAL_TYPE)),
             DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 4), DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits),
             DoubleToString(dealPnl, 2),
             HistoryDealGetString(trans.deal, DEAL_COMMENT));
   FileClose(h);
}

int OnInit()
{
   g_eaEnabled = InpEaEnabled;
   g_ftmoMode = InpFtmoModeDefault;
   g_riskLotOnlyMode = (!g_ftmoMode && InpRiskLotOnlyModeDefault);
   g_mode = InpMode;
   g_signalTf = InpSignalTf;
   g_exitMode = InpExitMode;
   g_weeks = ClampHistoricalWeeks(InpHistoricalWeeks);
   g_auditRuntime = InpAuditCsv || InpLogOnInit;
   g_nasSlTpMode = InpUseNasSlTpMode;
   g_nasSlDistancePct = ClampNasSlPct(InpNasSlDistancePct);
   g_nasTargetR = ClampNasTargetR(InpNasTargetR);
   g_bandMultiplier = InpBandMultiplier;
   g_ibsLongThreshold = InpIbsLongThreshold;
   g_regimeSmaDays = MathMax(0, InpRegimeSmaDays);
   g_firstTouchOnly = InpFirstTouchOnly;
   g_signalCooldownBars = ClampCooldownBars(InpSignalCooldownBars);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   SymbolSelect(DataSymbol(), true);
   g_lastD1Bar = iTime(DataSymbol(), g_signalTf, 0); // Do not auto-trade a stale source-TF signal on attach.
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
      if(g_ftmoMode) g_riskLotOnlyMode = false;
      redraw = true;
   }
   else if(Clicked(sparam, "BTN_RISKLOT"))
   {
      g_riskLotOnlyMode = !g_riskLotOnlyMode;
      if(g_riskLotOnlyMode) g_ftmoMode = false;
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
   else if(Clicked(sparam, "BTN_20W")) { g_weeks = 20; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_40W")) { g_weeks = 40; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_1Y")) { g_weeks = 52; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_AUDIT")) { g_auditRuntime = !g_auditRuntime; redraw = true; }
   else if(Clicked(sparam, "BTN_EXPORT")) { StartBacktestExport(); redraw = true; }
   else if(Clicked(sparam, "BTN_NASGEOM"))
   {
      g_nasSlTpMode = !g_nasSlTpMode;
      g_histDirty = true;
      redraw = true;
   }
   else if(Clicked(sparam, "BTN_NAS_APPLY"))
   {
      g_nasSlDistancePct = ClampNasSlPct(StringToDouble(ObjectGetString(0, QMR_PREFIX + "EDIT_NAS_SL", OBJPROP_TEXT)));
      g_nasTargetR = ClampNasTargetR(StringToDouble(ObjectGetString(0, QMR_PREFIX + "EDIT_NAS_TPR", OBJPROP_TEXT)));
      ObjectSetString(0, QMR_PREFIX + "EDIT_NAS_SL", OBJPROP_TEXT, DoubleToString(g_nasSlDistancePct, 0));
      ObjectSetString(0, QMR_PREFIX + "EDIT_NAS_TPR", OBJPROP_TEXT, DoubleToString(g_nasTargetR, 2));
      g_histDirty = true;
      redraw = true;
   }
   else if(Clicked(sparam, "BTN_TF_D1")) { g_signalTf = PERIOD_D1; g_lastD1Bar = iTime(DataSymbol(), g_signalTf, 0); g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_TF_H4")) { g_signalTf = PERIOD_H4; g_lastD1Bar = iTime(DataSymbol(), g_signalTf, 0); g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_TF_H1")) { g_signalTf = PERIOD_H1; g_lastD1Bar = iTime(DataSymbol(), g_signalTf, 0); g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_TF_M30")) { g_signalTf = PERIOD_M30; g_lastD1Bar = iTime(DataSymbol(), g_signalTf, 0); g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_BAND_175")) { g_bandMultiplier = 1.75; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_BAND_200")) { g_bandMultiplier = 2.0; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_BAND_250")) { g_bandMultiplier = 2.5; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_IBS_025")) { g_ibsLongThreshold = 0.25; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_IBS_030")) { g_ibsLongThreshold = 0.30; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_IBS_035")) { g_ibsLongThreshold = 0.35; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_IBS_040")) { g_ibsLongThreshold = 0.40; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_REG_OFF")) { g_regimeSmaDays = 0; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_REG_50")) { g_regimeSmaDays = 50; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_REG_100")) { g_regimeSmaDays = 100; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_REG_150")) { g_regimeSmaDays = 150; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_REG_200")) { g_regimeSmaDays = 200; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_REG_250")) { g_regimeSmaDays = 250; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_REG_300")) { g_regimeSmaDays = 300; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_EXIT_DEF")) { g_exitMode = QMR_EXIT_DEFAULT; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_EXIT_YDAY")) { g_exitMode = QMR_EXIT_YDAY_ONLY; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_EXIT_SMA")) { g_exitMode = QMR_EXIT_SMA_STOP; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_EXIT_NAS")) { g_exitMode = QMR_EXIT_NAS_TP; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_FT")) { g_firstTouchOnly = !g_firstTouchOnly; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_CD_0")) { g_signalCooldownBars = 0; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_CD_5")) { g_signalCooldownBars = 5; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_CD_10")) { g_signalCooldownBars = 10; g_histDirty = true; redraw = true; }
   else if(Clicked(sparam, "BTN_CD_20")) { g_signalCooldownBars = 20; g_histDirty = true; redraw = true; }

   if(redraw)
   {
      RebuildHistorical();
      DrawHistoricalSignals();
      UpdateDashboard(true);
      ChartRedraw(0);
   }
}
