//+------------------------------------------------------------------+
//| ERL -> IRL Higher Timeframe Swing Model EA                       |
//| Sweep -> reclaim -> HTF FVG -> entry-TF tap automation.           |
//| Dashboard, historical audit, brute-force backtest, risk engine.   |
//+------------------------------------------------------------------+
#property strict
#property version "1.11"

#include <Trade/Trade.mqh>

#define ERL_BUILD "2026-06-19.erl-irl-nonrepaint-strictness"
#define ERL_PREFIX "ERLIRL_"

//=====================================================================
//  ENUMS
//=====================================================================
enum ERL_RR_MODE
{
   ERL_RR_TP1 = 0,   // 0.5R
   ERL_RR_TP2 = 1,   // 1.0R
   ERL_RR_TP3 = 2,   // 1.5R
   ERL_RR_TP4 = 3,   // 2.0R
   ERL_RR_TP5 = 4,   // 2.5R
   ERL_RR_TP6 = 5    // 3.0R
};

enum ERL_HC_MODE
{
   ERL_HC_OFF = 0,
   ERL_HC_TP1 = 1,
   ERL_HC_TP2 = 2,
   ERL_HC_TP3 = 3,
   ERL_HC_TP4 = 4,
   ERL_HC_TP5 = 5
};

enum ERL_ENTRY_MODEL
{
   ERL_ENTRY_LEGACY_HTF_FVG_TAP = 0,
   ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG = 1
};

enum ERL_STOP_MODEL
{
   ERL_STOP_FVG_BOUNDARY = 0,
   ERL_STOP_FIRST_FVG_CANDLE = 1
};

enum ERL_TARGET_MODEL
{
   ERL_TARGET_FIXED_R = 0,
   ERL_TARGET_NEXT_EXTERNAL = 1,
   ERL_TARGET_AUTO_STOP_SIZE = 2
};

enum BT_FILL_MODE
{
   BT_FILL_SIGNAL_CLOSE = 0,
   BT_FILL_NEXT_BAR_OPEN = 1,
   BT_FILL_CONSERVATIVE = 2
};

enum BT_SAME_BAR_POLICY
{
   BT_SAMEBAR_CONSERVATIVE = 0,
   BT_SAMEBAR_NEAREST_OPEN = 1,
   BT_SAMEBAR_TP_FIRST = 2,
   BT_SAMEBAR_SL_FIRST = 3
};

//=====================================================================
//  INPUTS
//=====================================================================
input bool            InpEaEnabled              = true;
input long            InpMagic                  = 31061501;
input int             InpDeviationPoints        = 30;
input bool            InpCloseOnReverse         = true;
input bool            InpBlockSameDirection     = true;

input ENUM_TIMEFRAMES InpDefaultHtf             = PERIOD_H4;
input ENUM_TIMEFRAMES InpDefaultEntryTf         = PERIOD_M30;
input int             InpDefaultSwingLookback   = 5;
input ERL_RR_MODE     InpDefaultTarget          = ERL_RR_TP4;
input ERL_HC_MODE     InpDefaultHalfBe          = ERL_HC_OFF;
input bool            InpDefaultWeeklyBias      = false;
input ERL_ENTRY_MODEL InpDefaultEntryModel      = ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG;
input ERL_STOP_MODEL  InpDefaultStopModel       = ERL_STOP_FIRST_FVG_CANDLE;
input ERL_TARGET_MODEL InpDefaultTargetModel    = ERL_TARGET_NEXT_EXTERNAL;
input bool            InpDefaultRequireIrlTouch = true;
input bool            InpDefaultRequireEntrySweep = true;
input bool            InpDefaultRequireDisplacementFvg = true;

input int             InpCalcHtfBars            = 900;
input int             InpCalcEntryBars          = 5000;
input int             InpMaxSwings              = 20;
input int             InpMaxFvgSearchBars       = 20;
input int             InpEntrySweepLookback     = 3;
input int             InpEntrySweepMaxBars      = 160;
input int             InpEntryFvgMaxWaitBars    = 40;
input int             InpEntryFvgTapMaxBars     = 80;
input int             InpAtrPeriod              = 14;
input double          InpMinFvgAtrPct           = 8.0;
input double          InpSlBufferAtrPct         = 10.0;
input double          InpSlDistancePct          = 100.0;
input double          InpSmallStopThresholdPts  = 30.0;
input ERL_RR_MODE     InpSmallStopTarget        = ERL_RR_TP4;
input ERL_RR_MODE     InpLargeStopTarget        = ERL_RR_TP2;
input int             InpHistoricalDays         = 14;
input int             InpHistoricalWeeks        = 2;
input bool            InpDrawHistoricalSignals  = true;
input bool            InpDrawFvgZones           = true;
input bool            InpDrawLiveLevels         = true;

input bool            InpShowDashboard          = true;
input int             InpDashboardX             = 10;
input int             InpDashboardY             = 18;

input bool            InpAccountRiskEnabled     = true;
input double          InpRiskPerTradePct        = 1.0;
input double          InpMaxPortfolioRiskPct    = 4.0;
input double          InpDailyLossLimitPct      = 0.0;
input double          InpMaxDrawdownPct         = 0.0;
input double          InpInitialBalanceOverride = 0.0;
input double          InpFixedLot               = 0.10;
input double          InpMaxLot                 = 0.0;
input int             InpDayResetHourGmt        = 0;
input bool            InpLiquidateOnBreach      = true;

input bool            InpAuditTradeCsv          = false;
input bool            InpAuditPositionProbe     = false;
input int             InpAuditProbeSec          = 30;
input bool            InpAuditProbeOnChangeOnly = true;
input int             InpAuditHistoryScanSec    = 3;
input bool            InpTesterTradeAuditCsv    = false;
input int             InpTesterTradeAuditMaxRows= 50000;
input string          InpValidationJobId        = "";

input int             InpBacktestWeeks          = 4;
input BT_FILL_MODE    InpBacktestFillMode       = BT_FILL_NEXT_BAR_OPEN;
input BT_SAME_BAR_POLICY InpBacktestSameBarPolicy = BT_SAMEBAR_CONSERVATIVE;
input bool            InpBacktestUseTickReplay  = true;
input double          InpBacktestSpreadPts      = 0.0;
input double          InpBacktestSlippagePts    = 0.0;
input double          InpBacktestCommissionPerLot = 0.0;

//=====================================================================
//  STRUCTS
//=====================================================================
struct SwingLevel
{
   datetime time;
   double   price;
   int      index;
   int      dir;       // +1 high, -1 low
};

struct FvgZone
{
   bool     valid;
   int      dir;       // +1 bullish, -1 bearish
   datetime time;
   double   low;
   double   high;
   double   anchor;
   double   firstLow;
   double   firstHigh;
};

struct ErlSignal
{
   bool     valid;
   int      dir;
   datetime htfTime;
   datetime entryTime;
   double   sweepLevel;
   double   fvgLow;
   double   fvgHigh;
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   tp3;
   double   tp4;
   double   tp5;
   double   tp6;
   double   risk;
   double   externalTarget;
   datetime externalTime;
   string   reason;
   string   id;
};

struct SimStats
{
   int      total;
   int      wins;
   int      losses;
   int      open;
   double   wonR;
   double   lostR;
   double   netR;
   double   pf;
};

struct BtCombo
{
   ENUM_TIMEFRAMES htf;
   ENUM_TIMEFRAMES entryTf;
   int      swing;
   ERL_RR_MODE target;
   ERL_HC_MODE hc;
   bool     bias;
   ERL_ENTRY_MODEL entryModel;
   ERL_STOP_MODEL stopModel;
   ERL_TARGET_MODEL targetModel;
   bool     requireIrlTouch;
   bool     requireEntrySweep;
   bool     requireDisplacementFvg;
};

//=====================================================================
//  GLOBAL STATE
//=====================================================================
CTrade trade;
string PFX = ERL_PREFIX;
string g_testerTradeAuditFile = "";
int    g_testerTradeAuditRows = 0;

bool IsValidationTester()
{
   return (bool)MQLInfoInteger(MQL_TESTER) && StringLen(InpValidationJobId) > 0;
}

bool IsTesterMode()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

bool             g_eaEnabled;
ENUM_TIMEFRAMES  g_htf;
ENUM_TIMEFRAMES  g_entryTf;
int              g_swingLookback;
ERL_RR_MODE      g_target;
ERL_HC_MODE      g_hc;
bool             g_weeklyBias;
ERL_ENTRY_MODEL  g_entryModel;
ERL_STOP_MODEL   g_stopModel;
ERL_TARGET_MODEL g_targetModel;
bool             g_requireIrlTouch = true;
bool             g_requireEntrySweep = true;
bool             g_requireDisplacementFvg = true;
bool             g_auditRuntime = false;
bool             g_dashboardCollapsed = false;

SimStats         g_hist;
string           g_lastStatus = "READY";
string           g_lastBlock  = "";
datetime         g_lastSignalTime = 0;
int              g_lastSignalDir = 0;
string           g_lastSignalId = "";
double           g_lastEntry = 0.0;
double           g_lastSl = 0.0;
double           g_lastTp = 0.0;
double           g_lastSpreadPts = 0.0;
string           g_lastSpreadStatus = "?";

datetime         g_lastAuditProbe = 0;
string           g_lastProbeHash = "";
datetime         g_lastHistoryScan = 0;
ulong            g_lastHistoryTicket = 0;
double           g_equityPeak = 0.0;
datetime         g_lastLiveScanBar = 0;

BtCombo          g_btCombos[];
bool             g_btRunning = false;
int              g_btStep = 0;
int              g_btTotal = 0;
int              g_btWeeks = 4;
string           g_btFileName = "";
string           g_btLastResult = "Ready";
uint             g_btStartMs = 0;
uint             g_btElapsedMs = 0;
datetime         g_btCutoff = 0;
string           g_btCoverageSummary = "";
BT_FILL_MODE     g_btFillMode;
BT_SAME_BAR_POLICY g_btSameBarPolicy;
double           g_btSpreadPts;
double           g_btSlippagePts;
double           g_btCommissionPerLot;
double           g_slDistancePct = 100.0;
int              g_histWeeks = 2;
long             DASH_Z = 1000000;

//=====================================================================
//  BASIC UTILITY
//=====================================================================
string TfLabel(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
   }
   return EnumToString(tf);
}

string DirLabel(int dir)
{
   if(dir > 0) return "BUY";
   if(dir < 0) return "SELL";
   return "-";
}

string TargetLabel(ERL_RR_MODE rr)
{
   return "TP" + IntegerToString((int)rr + 1) + " " + DoubleToString(TargetR(rr), 1) + "R";
}

string HcLabel(ERL_HC_MODE hc)
{
   if(hc == ERL_HC_OFF) return "HC OFF";
   return "HC@TP" + IntegerToString((int)hc);
}

string EntryModelLabel(ERL_ENTRY_MODEL model)
{
   if(model == ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG) return "PRO";
   return "LEGACY";
}

string StopModelLabel(ERL_STOP_MODEL model)
{
   if(model == ERL_STOP_FIRST_FVG_CANDLE) return "FVG1";
   return "ZONE";
}

string TargetModelLabel(ERL_TARGET_MODEL model)
{
   if(model == ERL_TARGET_NEXT_EXTERNAL) return "EXT";
   if(model == ERL_TARGET_AUTO_STOP_SIZE) return "AUTO";
   return "FIXED";
}

string StrictnessLabel(bool irlTouch, bool entrySweep, bool displacementFvg)
{
   return "IRL" + (irlTouch ? "1" : "0") + "-SWP" + (entrySweep ? "1" : "0") + "-DSP" + (displacementFvg ? "1" : "0");
}

string BtFillLabel(BT_FILL_MODE mode)
{
   if(mode == BT_FILL_NEXT_BAR_OPEN) return "NEXT";
   if(mode == BT_FILL_CONSERVATIVE) return "CONS";
   return "SIGNAL";
}

string BtSameLabel(BT_SAME_BAR_POLICY policy)
{
   if(policy == BT_SAMEBAR_NEAREST_OPEN) return "NEAR";
   if(policy == BT_SAMEBAR_TP_FIRST) return "TP1ST";
   if(policy == BT_SAMEBAR_SL_FIRST) return "SL1ST";
   return "CONS";
}

double TargetR(ERL_RR_MODE rr)
{
   int leg = (int)rr + 1;
   return MathMax(0.5, 0.5 * leg);
}

ERL_RR_MODE EffectiveTargetMode(const ErlSignal &sig, ERL_RR_MODE selected, ERL_TARGET_MODEL model)
{
   if(model != ERL_TARGET_AUTO_STOP_SIZE) return selected;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = TickSize();
   double riskPts = point > 0.0 ? sig.risk / point : 0.0;
   return riskPts > 0.0 && riskPts <= InpSmallStopThresholdPts ? InpSmallStopTarget : InpLargeStopTarget;
}

ERL_RR_MODE EffectiveTargetModeByRisk(double risk, ERL_RR_MODE selected, ERL_TARGET_MODEL model)
{
   if(model != ERL_TARGET_AUTO_STOP_SIZE) return selected;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = TickSize();
   double riskPts = point > 0.0 ? risk / point : 0.0;
   return riskPts > 0.0 && riskPts <= InpSmallStopThresholdPts ? InpSmallStopTarget : InpLargeStopTarget;
}

double ClampSlDistancePct(double pct)
{
   return MathMax(10.0, MathMin(300.0, pct));
}

double ApplySlDistancePct(int dir, double entry, double rawSl)
{
   double dist = MathAbs(entry - rawSl) * ClampSlDistancePct(g_slDistancePct) / 100.0;
   if(dist <= 0.0) return rawSl;
   return NormTradePrice(dir > 0 ? entry - dist : entry + dist);
}

double ApproxMoneyFromR(double r)
{
   double base = InpInitialBalanceOverride > 0.0 ? InpInitialBalanceOverride : MathMax(0.01, AccountInfoDouble(ACCOUNT_BALANCE));
   return r * base * MathMax(0.0, InpRiskPerTradePct) / 100.0;
}

int ClampHistWeeks(int weeks)
{
   if(weeks <= 2) return 2;
   if(weeks <= 5) return 5;
   if(weeks <= 10) return 10;
   return 20;
}

int HistDays()
{
   return ClampHistWeeks(g_histWeeks) * 7;
}

double NormPrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double TickSize()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0) tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0) tickSize = 0.00001;
   return tickSize;
}

double NormTradePrice(double price)
{
   double tickSize = TickSize();
   return NormPrice(MathRound(price / tickSize) * tickSize);
}

double ValuePerPriceUnitPerLot()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0) tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0 || tickValue <= 0.0) return 0.0;
   return tickValue / tickSize;
}

double NormalizeVolume(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0.0) minLot = 0.01;
   if(maxLot <= 0.0) maxLot = 100.0;
   if(InpMaxLot > 0.0) maxLot = MathMin(maxLot, InpMaxLot);
   if(step <= 0.0) step = minLot;
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / step + 0.0000001) * step;
   return NormalizeDouble(MathMax(minLot, volume), 8);
}

long RuntimeMagic()
{
   return InpMagic * 1000000 + (long)(ChartID() % 1000000);
}

bool IsOwnMagic(long magic)
{
   return magic == RuntimeMagic();
}

string FmtTime(datetime t)
{
   if(t <= 0) return "-";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

int CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) return 0;
   return (int)MathRound((tick.ask - tick.bid) / point);
}

string FileDate(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
}

string FileStamp(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d%02d%02d_%02d%02d%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

bool CopySeries(ENUM_TIMEFRAMES tf, int bars, MqlRates &rates[])
{
   ArrayFree(rates);
   int copied = CopyRates(_Symbol, tf, 0, bars, rates);
   if(copied <= 20) return false;
   ArraySetAsSeries(rates, true);
   return true;
}

int RequiredBarsForWindow(ENUM_TIMEFRAMES tf, datetime cutoff, int warmupBars)
{
   if(cutoff <= 0) return 0;
   int sec = PeriodSeconds(tf);
   if(sec <= 0) sec = 60;
   double windowSec = MathMax(1.0, (double)(TimeCurrent() - cutoff));
   return (int)MathCeil(windowSec / (double)sec) + MathMax(0, warmupBars);
}

//=====================================================================
//  MARKET DATA HELPERS
//=====================================================================
double AtrFromRates(const MqlRates &rates[], int index, int period)
{
   int total = ArraySize(rates);
   if(index < 1 || index + period >= total) return 0.0;
   double sum = 0.0;
   int count = 0;
   for(int i = index; i < index + period && i + 1 < total; ++i)
   {
      double tr1 = rates[i].high - rates[i].low;
      double tr2 = MathAbs(rates[i].high - rates[i + 1].close);
      double tr3 = MathAbs(rates[i].low - rates[i + 1].close);
      sum += MathMax(tr1, MathMax(tr2, tr3));
      count++;
   }
   return count > 0 ? sum / count : 0.0;
}

bool PreviousWeekBiasAllowsAt(int dir, datetime referenceTime)
{
   MqlRates week[];
   int currentShift = iBarShift(_Symbol, PERIOD_W1, referenceTime, false);
   if(currentShift < 0) currentShift = 0;
   int copied = CopyRates(_Symbol, PERIOD_W1, currentShift + 1, 1, week);
   if(copied < 1) return true;
   bool bull = week[0].close > week[0].open;
   bool bear = week[0].close < week[0].open;
   if(dir > 0) return bull || !bear;
   if(dir < 0) return bear || !bull;
   return true;
}

double MinStopDistance()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = TickSize();
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)MathMax(stops, freeze) * point, TickSize());
}

double RiskMoneyForLot(double lot, int dir, double entry, double sl)
{
   if(lot <= 0.0 || sl <= 0.0) return 0.0;
   double profit = 0.0;
   ENUM_ORDER_TYPE closeSide = dir > 0 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   if(!OrderCalcProfit(closeSide, _Symbol, lot, entry, sl, profit)) return 0.0;
   return MathAbs(profit);
}

bool IsSwingHigh(const MqlRates &rates[], int index, int lookback)
{
   int total = ArraySize(rates);
   if(index - lookback < 1 || index + lookback >= total) return false;
   double price = rates[index].high;
   for(int k = 1; k <= lookback; ++k)
   {
      if(price <= rates[index - k].high) return false; // newer side
      if(price <= rates[index + k].high) return false; // older side
   }
   return true;
}

bool IsSwingLow(const MqlRates &rates[], int index, int lookback)
{
   int total = ArraySize(rates);
   if(index - lookback < 1 || index + lookback >= total) return false;
   double price = rates[index].low;
   for(int k = 1; k <= lookback; ++k)
   {
      if(price >= rates[index - k].low) return false;
      if(price >= rates[index + k].low) return false;
   }
   return true;
}

int CollectSwings(const MqlRates &rates[], int lookback, SwingLevel &swings[])
{
   ArrayFree(swings);
   int total = ArraySize(rates);
   int found = 0;
   for(int i = lookback + 2; i < total - lookback && found < InpMaxSwings * 2; ++i)
   {
      if(IsSwingHigh(rates, i, lookback))
      {
         int n = ArraySize(swings);
         ArrayResize(swings, n + 1);
         swings[n].time = rates[i].time;
         swings[n].price = rates[i].high;
         swings[n].index = i;
         swings[n].dir = 1;
         found++;
      }
      if(IsSwingLow(rates, i, lookback))
      {
         int n = ArraySize(swings);
         ArrayResize(swings, n + 1);
         swings[n].time = rates[i].time;
         swings[n].price = rates[i].low;
         swings[n].index = i;
         swings[n].dir = -1;
         found++;
      }
   }
   return ArraySize(swings);
}

bool IsBullishFvg(const MqlRates &rates[], int midIndex, double minSize, FvgZone &zone)
{
   int total = ArraySize(rates);
   if(midIndex - 1 < 0 || midIndex + 1 >= total) return false;
   double olderHigh = rates[midIndex + 1].high;
   double newerLow = rates[midIndex - 1].low;
   if(olderHigh >= newerLow) return false;
   double size = newerLow - olderHigh;
   if(size < minSize) return false;
   zone.valid = true;
   zone.dir = 1;
   zone.time = rates[midIndex].time;
   zone.low = olderHigh;
   zone.high = newerLow;
   zone.anchor = rates[midIndex].low;
   zone.firstLow = rates[midIndex + 1].low;
   zone.firstHigh = rates[midIndex + 1].high;
   return true;
}

bool IsBearishFvg(const MqlRates &rates[], int midIndex, double minSize, FvgZone &zone)
{
   int total = ArraySize(rates);
   if(midIndex - 1 < 0 || midIndex + 1 >= total) return false;
   double olderLow = rates[midIndex + 1].low;
   double newerHigh = rates[midIndex - 1].high;
   if(olderLow <= newerHigh) return false;
   double size = olderLow - newerHigh;
   if(size < minSize) return false;
   zone.valid = true;
   zone.dir = -1;
   zone.time = rates[midIndex].time;
   zone.low = newerHigh;
   zone.high = olderLow;
   zone.anchor = rates[midIndex].high;
   zone.firstLow = rates[midIndex + 1].low;
   zone.firstHigh = rates[midIndex + 1].high;
   return true;
}

bool DetectSweepReclaim(const MqlRates &rates[], const SwingLevel &swing, int &reclaimIndex)
{
   reclaimIndex = -1;
   // Series arrays: lower index is newer. Scan from just after swing toward latest.
   for(int j = swing.index - 1; j >= 1; --j)
   {
      if(swing.dir < 0)
      {
         bool swept = rates[j].low < swing.price;
         bool reclaimedSame = rates[j].close > swing.price;
         bool reclaimedNext = (j - 1 >= 1 && rates[j - 1].close > swing.price);
         if(swept && (reclaimedSame || reclaimedNext))
         {
            reclaimIndex = reclaimedSame ? j : j - 1;
            return true;
         }
      }
      else
      {
         bool swept = rates[j].high > swing.price;
         bool reclaimedSame = rates[j].close < swing.price;
         bool reclaimedNext = (j - 1 >= 1 && rates[j - 1].close < swing.price);
         if(swept && (reclaimedSame || reclaimedNext))
         {
            reclaimIndex = reclaimedSame ? j : j - 1;
            return true;
         }
      }
   }
   return false;
}

bool FindFirstFvgAfterReclaim(const MqlRates &rates[], int dir, int reclaimIndex, FvgZone &zone)
{
   zone.valid = false;
   double atr = AtrFromRates(rates, MathMax(1, reclaimIndex), InpAtrPeriod);
   double minSize = atr * MathMax(0.0, InpMinFvgAtrPct) / 100.0;
   int maxBars = MathMax(3, InpMaxFvgSearchBars);
   int scanned = 0;
   for(int i = reclaimIndex - 1; i >= 2 && scanned < maxBars; --i, ++scanned)
   {
      FvgZone z;
      ZeroMemory(z);
      bool ok = dir > 0 ? IsBullishFvg(rates, i, minSize, z) : IsBearishFvg(rates, i, minSize, z);
      if(ok)
      {
         zone = z;
         return true;
      }
   }
   return false;
}

bool EntryTapFromFvg(const MqlRates &entryRates[], const FvgZone &zone, int dir, ERL_STOP_MODEL stopModel, ErlSignal &sig)
{
   int total = ArraySize(entryRates);
   if(total < 10) return false;
   double atr = AtrFromRates(entryRates, 1, InpAtrPeriod);
   double buffer = atr * MathMax(0.0, InpSlBufferAtrPct) / 100.0;
   for(int i = total - 2; i >= 1; --i)
   {
      if(entryRates[i].time < zone.time) continue;
      bool tapped = entryRates[i].low <= zone.high && entryRates[i].high >= zone.low;
      if(!tapped) continue;
      double entry = entryRates[i].close;
      double rawStop = (stopModel == ERL_STOP_FIRST_FVG_CANDLE && zone.firstLow > 0.0 && zone.firstHigh > 0.0)
         ? (dir > 0 ? zone.firstLow : zone.firstHigh)
         : (dir > 0 ? zone.low : zone.high);
      double sl = dir > 0 ? rawStop - buffer : rawStop + buffer;
      sl = ApplySlDistancePct(dir, entry, sl);
      double risk = MathAbs(entry - sl);
      if(risk <= TickSize()) continue;
      sig.valid = true;
      sig.dir = dir;
      sig.entryTime = entryRates[i].time;
      sig.entry = NormTradePrice(entry);
      sig.sl = NormTradePrice(sl);
      sig.risk = MathAbs(sig.entry - sig.sl);
      if(sig.risk <= TickSize()) continue;
      sig.tp1 = NormTradePrice(sig.entry + dir * sig.risk * 0.5);
      sig.tp2 = NormTradePrice(sig.entry + dir * sig.risk * 1.0);
      sig.tp3 = NormTradePrice(sig.entry + dir * sig.risk * 1.5);
      sig.tp4 = NormTradePrice(sig.entry + dir * sig.risk * 2.0);
      sig.tp5 = NormTradePrice(sig.entry + dir * sig.risk * 2.5);
      sig.tp6 = NormTradePrice(sig.entry + dir * sig.risk * 3.0);
      sig.fvgLow = zone.low;
      sig.fvgHigh = zone.high;
      sig.reason = "fvg_tap";
      return true;
   }
   return false;
}

bool FindEntrySweepReclaim(const MqlRates &entryRates[], int dir, datetime afterTime, int &reclaimIndex, double &sweepLevel)
{
   reclaimIndex = -1;
   sweepLevel = 0.0;
   SwingLevel entrySwings[];
   int swCount = CollectSwings(entryRates, MathMax(1, InpEntrySweepLookback), entrySwings);
   if(swCount <= 0) return false;

   int scanned = 0;
   for(int i = ArraySize(entryRates) - 2; i >= 2 && scanned < MathMax(10, InpEntrySweepMaxBars); --i)
   {
      if(entryRates[i].time < afterTime) continue;
      scanned++;
      for(int s = 0; s < swCount; ++s)
      {
         if(entrySwings[s].time >= entryRates[i].time) continue;
         if(dir > 0 && entrySwings[s].dir < 0)
         {
            bool swept = entryRates[i].low < entrySwings[s].price;
            bool reclaimed = entryRates[i].close > entrySwings[s].price;
            bool reclaimedNext = (i - 1 >= 1 && entryRates[i - 1].close > entrySwings[s].price);
            if(swept && (reclaimed || reclaimedNext))
            {
               reclaimIndex = reclaimed ? i : i - 1;
               sweepLevel = entrySwings[s].price;
               return true;
            }
         }
         if(dir < 0 && entrySwings[s].dir > 0)
         {
            bool swept = entryRates[i].high > entrySwings[s].price;
            bool reclaimed = entryRates[i].close < entrySwings[s].price;
            bool reclaimedNext = (i - 1 >= 1 && entryRates[i - 1].close < entrySwings[s].price);
            if(swept && (reclaimed || reclaimedNext))
            {
               reclaimIndex = reclaimed ? i : i - 1;
               sweepLevel = entrySwings[s].price;
               return true;
            }
         }
      }
   }
   return false;
}

bool FindEntryFvgAfterReclaim(const MqlRates &entryRates[], int dir, int reclaimIndex, FvgZone &zone)
{
   zone.valid = false;
   double atr = AtrFromRates(entryRates, MathMax(1, reclaimIndex), InpAtrPeriod);
   double minSize = atr * MathMax(0.0, InpMinFvgAtrPct) / 100.0;
   int maxBars = MathMax(3, InpEntryFvgMaxWaitBars);
   int scanned = 0;
   for(int i = reclaimIndex - 1; i >= 2 && scanned < maxBars; --i, ++scanned)
   {
      FvgZone z;
      ZeroMemory(z);
      bool ok = dir > 0 ? IsBullishFvg(entryRates, i, minSize, z) : IsBearishFvg(entryRates, i, minSize, z);
      if(ok)
      {
         zone = z;
         return true;
      }
   }
   return false;
}

bool FindZoneTouchTime(const MqlRates &rates[], const FvgZone &zone, datetime afterTime, datetime &touchTime)
{
   touchTime = 0;
   for(int i = ArraySize(rates) - 2; i >= 1; --i)
   {
      if(rates[i].time < afterTime) continue;
      bool touched = rates[i].low <= zone.high && rates[i].high >= zone.low;
      if(!touched) continue;
      touchTime = rates[i].time;
      return true;
   }
   return false;
}

int FirstClosedBarAtOrAfter(const MqlRates &rates[], datetime afterTime)
{
   for(int i = ArraySize(rates) - 2; i >= 1; --i)
   {
      if(rates[i].time < afterTime) continue;
      return i;
   }
   return -1;
}

bool EntryTapFromFvgLimited(const MqlRates &entryRates[], const FvgZone &zone, int dir, ERL_STOP_MODEL stopModel, int maxTapBars, ErlSignal &sig)
{
   int total = ArraySize(entryRates);
   if(total < 10) return false;
   double atr = AtrFromRates(entryRates, 1, InpAtrPeriod);
   double buffer = atr * MathMax(0.0, InpSlBufferAtrPct) / 100.0;
   int scanned = 0;
   for(int i = total - 2; i >= 1 && scanned < MathMax(3, maxTapBars); --i)
   {
      if(entryRates[i].time < zone.time) continue;
      scanned++;
      bool tapped = entryRates[i].low <= zone.high && entryRates[i].high >= zone.low;
      if(!tapped) continue;
      double entry = entryRates[i].close;
      double rawStop = (stopModel == ERL_STOP_FIRST_FVG_CANDLE && zone.firstLow > 0.0 && zone.firstHigh > 0.0)
         ? (dir > 0 ? zone.firstLow : zone.firstHigh)
         : (dir > 0 ? zone.low : zone.high);
      double sl = dir > 0 ? rawStop - buffer : rawStop + buffer;
      sl = ApplySlDistancePct(dir, entry, sl);
      double risk = MathAbs(entry - sl);
      if(risk <= TickSize()) continue;
      sig.valid = true;
      sig.dir = dir;
      sig.entryTime = entryRates[i].time;
      sig.entry = NormTradePrice(entry);
      sig.sl = NormTradePrice(sl);
      sig.risk = MathAbs(sig.entry - sig.sl);
      if(sig.risk <= TickSize()) continue;
      sig.tp1 = NormTradePrice(sig.entry + dir * sig.risk * 0.5);
      sig.tp2 = NormTradePrice(sig.entry + dir * sig.risk * 1.0);
      sig.tp3 = NormTradePrice(sig.entry + dir * sig.risk * 1.5);
      sig.tp4 = NormTradePrice(sig.entry + dir * sig.risk * 2.0);
      sig.tp5 = NormTradePrice(sig.entry + dir * sig.risk * 2.5);
      sig.tp6 = NormTradePrice(sig.entry + dir * sig.risk * 3.0);
      sig.fvgLow = zone.low;
      sig.fvgHigh = zone.high;
      sig.reason = "entry_sweep_reclaim_displace_fvg_tap";
      return true;
   }
   return false;
}

bool BuildDirectEntryAtBar(const MqlRates &entryRates[], int barIndex, const FvgZone &zone, int dir, ERL_STOP_MODEL stopModel,
   string reason, ErlSignal &sig)
{
   if(barIndex < 1 || barIndex >= ArraySize(entryRates)) return false;
   double atr = AtrFromRates(entryRates, MathMax(1, barIndex), InpAtrPeriod);
   double buffer = atr * MathMax(0.0, InpSlBufferAtrPct) / 100.0;
   double entry = entryRates[barIndex].close;
   double rawStop = (stopModel == ERL_STOP_FIRST_FVG_CANDLE && zone.firstLow > 0.0 && zone.firstHigh > 0.0)
      ? (dir > 0 ? zone.firstLow : zone.firstHigh)
      : (dir > 0 ? zone.low : zone.high);
   double sl = dir > 0 ? rawStop - buffer : rawStop + buffer;
   sl = ApplySlDistancePct(dir, entry, sl);
   double risk = MathAbs(entry - sl);
   if(risk <= TickSize()) return false;
   sig.valid = true;
   sig.dir = dir;
   sig.entryTime = entryRates[barIndex].time;
   sig.entry = NormTradePrice(entry);
   sig.sl = NormTradePrice(sl);
   sig.risk = MathAbs(sig.entry - sig.sl);
   if(sig.risk <= TickSize()) return false;
   sig.tp1 = NormTradePrice(sig.entry + dir * sig.risk * 0.5);
   sig.tp2 = NormTradePrice(sig.entry + dir * sig.risk * 1.0);
   sig.tp3 = NormTradePrice(sig.entry + dir * sig.risk * 1.5);
   sig.tp4 = NormTradePrice(sig.entry + dir * sig.risk * 2.0);
   sig.tp5 = NormTradePrice(sig.entry + dir * sig.risk * 2.5);
   sig.tp6 = NormTradePrice(sig.entry + dir * sig.risk * 3.0);
   sig.fvgLow = zone.low;
   sig.fvgHigh = zone.high;
   sig.reason = reason;
   return true;
}

bool ProEntrySweepReclaimFvg(const MqlRates &entryRates[], const FvgZone &htfIrlZone, int dir, datetime afterTime,
   ERL_STOP_MODEL stopModel, bool requireIrlTouch, bool requireEntrySweep, bool requireDisplacementFvg, ErlSignal &sig)
{
   datetime searchStart = afterTime;
   if(requireIrlTouch)
   {
      datetime irlTouch = 0;
      if(!FindZoneTouchTime(entryRates, htfIrlZone, afterTime, irlTouch)) return false;
      searchStart = irlTouch;
   }

   int entryReclaim = -1;
   double entrySweep = 0.0;
   if(requireEntrySweep)
   {
      if(!FindEntrySweepReclaim(entryRates, dir, searchStart, entryReclaim, entrySweep)) return false;
      searchStart = entryRates[entryReclaim].time;
   }
   else
   {
      entryReclaim = FirstClosedBarAtOrAfter(entryRates, searchStart);
      if(entryReclaim < 1) return false;
   }

   if(requireDisplacementFvg)
   {
      FvgZone entryZone;
      ZeroMemory(entryZone);
      if(!FindEntryFvgAfterReclaim(entryRates, dir, entryReclaim, entryZone)) return false;
      if(!EntryTapFromFvgLimited(entryRates, entryZone, dir, stopModel, InpEntryFvgTapMaxBars, sig)) return false;
   }
   else
   {
      if(!BuildDirectEntryAtBar(entryRates, entryReclaim, htfIrlZone, dir, stopModel, "pro_relaxed_reclaim_close", sig)) return false;
   }
   sig.sweepLevel = entrySweep;
   return true;
}

string SignalId(const ErlSignal &sig, ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES entryTf, int swingLookback, bool bias)
{
   return _Symbol + "|" + TfLabel(htf) + "|" + TfLabel(entryTf) + "|SW" + IntegerToString(swingLookback)
      + "|" + EntryModelLabel(g_entryModel) + "|" + StopModelLabel(g_stopModel) + "|" + TargetModelLabel(g_targetModel)
      + "|" + StrictnessLabel(g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg)
      + "|" + (bias ? "B1" : "B0") + "|" + DirLabel(sig.dir) + "|" + IntegerToString((int)sig.entryTime);
}

void AssignExternalTarget(ErlSignal &sig, const SwingLevel &swings[])
{
   sig.externalTarget = 0.0;
   sig.externalTime = 0;
   double bestDist = DBL_MAX;
   for(int i = 0; i < ArraySize(swings); ++i)
   {
      if(swings[i].time > sig.entryTime) continue;
      if(sig.dir > 0 && swings[i].dir > 0 && swings[i].price > sig.entry)
      {
         double dist = swings[i].price - sig.entry;
         if(dist < bestDist)
         {
            bestDist = dist;
            sig.externalTarget = NormTradePrice(swings[i].price);
            sig.externalTime = swings[i].time;
         }
      }
      if(sig.dir < 0 && swings[i].dir < 0 && swings[i].price < sig.entry)
      {
         double dist = sig.entry - swings[i].price;
         if(dist < bestDist)
         {
            bestDist = dist;
            sig.externalTarget = NormTradePrice(swings[i].price);
            sig.externalTime = swings[i].time;
         }
      }
   }
}

string SignalId(const ErlSignal &sig, ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES entryTf, int swingLookback, bool bias,
   ERL_ENTRY_MODEL entryModel, ERL_STOP_MODEL stopModel, ERL_TARGET_MODEL targetModel,
   bool requireIrlTouch, bool requireEntrySweep, bool requireDisplacementFvg)
{
   return _Symbol + "|" + TfLabel(htf) + "|" + TfLabel(entryTf) + "|SW" + IntegerToString(swingLookback)
      + "|" + EntryModelLabel(entryModel) + "|" + StopModelLabel(stopModel) + "|" + TargetModelLabel(targetModel)
      + "|" + StrictnessLabel(requireIrlTouch, requireEntrySweep, requireDisplacementFvg)
      + "|" + (bias ? "B1" : "B0") + "|" + DirLabel(sig.dir) + "|" + IntegerToString((int)sig.entryTime);
}

int BuildSignals(ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES entryTf, int swingLookback, bool useBias,
   ERL_ENTRY_MODEL entryModel, ERL_STOP_MODEL stopModel, ERL_TARGET_MODEL targetModel,
   bool requireIrlTouch, bool requireEntrySweep, bool requireDisplacementFvg,
   datetime cutoff, ErlSignal &signals[])
{
   ArrayFree(signals);
   MqlRates htfRates[], entryRates[];
   int htfBars = MathMax(InpCalcHtfBars, RequiredBarsForWindow(htf, cutoff, 250));
   int entryBars = MathMax(InpCalcEntryBars, RequiredBarsForWindow(entryTf, cutoff, 500));
   if(!CopySeries(htf, htfBars, htfRates)) return 0;
   if(!CopySeries(entryTf, entryBars, entryRates)) return 0;

   SwingLevel swings[];
   int swCount = CollectSwings(htfRates, swingLookback, swings);
   if(swCount <= 0) return 0;

   for(int s = 0; s < swCount; ++s)
   {
      int dir = swings[s].dir < 0 ? 1 : -1; // sweep low -> buy, sweep high -> sell
      int reclaimIndex = -1;
      if(!DetectSweepReclaim(htfRates, swings[s], reclaimIndex)) continue;
      if(useBias && !PreviousWeekBiasAllowsAt(dir, htfRates[reclaimIndex].time)) continue;
      FvgZone zone;
      ZeroMemory(zone);
      if(!FindFirstFvgAfterReclaim(htfRates, dir, reclaimIndex, zone)) continue;
      ErlSignal sig;
      ZeroMemory(sig);
      bool entryOk = false;
      if(entryModel == ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG)
         entryOk = ProEntrySweepReclaimFvg(entryRates, zone, dir, htfRates[reclaimIndex].time, stopModel,
            requireIrlTouch, requireEntrySweep, requireDisplacementFvg, sig);
      else
         entryOk = EntryTapFromFvg(entryRates, zone, dir, stopModel, sig);
      if(!entryOk) continue;
      if(cutoff > 0 && sig.entryTime < cutoff) continue;
      sig.htfTime = htfRates[reclaimIndex].time;
      if(sig.sweepLevel <= 0.0) sig.sweepLevel = swings[s].price;
      AssignExternalTarget(sig, swings);
      sig.id = SignalId(sig, htf, entryTf, swingLookback, useBias, entryModel, stopModel, targetModel,
         requireIrlTouch, requireEntrySweep, requireDisplacementFvg);
      bool duplicate = false;
      for(int k = 0; k < ArraySize(signals); ++k)
      {
         if(signals[k].id == sig.id)
         {
            duplicate = true;
            break;
         }
      }
      if(duplicate) continue;
      int n = ArraySize(signals);
      ArrayResize(signals, n + 1);
      signals[n] = sig;
   }

   // Sort oldest -> newest for drawing/backtesting readability.
   int n = ArraySize(signals);
   for(int i = 0; i < n - 1; ++i)
   {
      for(int j = i + 1; j < n; ++j)
      {
         if(signals[i].entryTime > signals[j].entryTime)
         {
            ErlSignal tmp = signals[i];
            signals[i] = signals[j];
            signals[j] = tmp;
         }
      }
   }
   return n;
}

double SelectedFixedTarget(const ErlSignal &sig, ERL_RR_MODE target)
{
   if(target == ERL_RR_TP1) return sig.tp1;
   if(target == ERL_RR_TP2) return sig.tp2;
   if(target == ERL_RR_TP3) return sig.tp3;
   if(target == ERL_RR_TP4) return sig.tp4;
   if(target == ERL_RR_TP5) return sig.tp5;
   return sig.tp6;
}

double SelectedTarget(const ErlSignal &sig, ERL_RR_MODE target, ERL_TARGET_MODEL targetModel)
{
   if(targetModel == ERL_TARGET_NEXT_EXTERNAL)
   {
      if(sig.externalTarget > 0.0)
      {
         bool validSide = sig.dir > 0 ? sig.externalTarget > sig.entry + TickSize() : sig.externalTarget < sig.entry - TickSize();
         if(validSide) return sig.externalTarget;
      }
   }
   ERL_RR_MODE effective = EffectiveTargetMode(sig, target, targetModel);
   return SelectedFixedTarget(sig, effective);
}

double SelectedTarget(const ErlSignal &sig, ERL_RR_MODE target)
{
   return SelectedTarget(sig, target, g_targetModel);
}

double HalfTrigger(const ErlSignal &sig, ERL_HC_MODE hc)
{
   if(hc == ERL_HC_TP1) return sig.tp1;
   if(hc == ERL_HC_TP2) return sig.tp2;
   if(hc == ERL_HC_TP3) return sig.tp3;
   if(hc == ERL_HC_TP4) return sig.tp4;
   if(hc == ERL_HC_TP5) return sig.tp5;
   return 0.0;
}

void SanitizeHalfMode()
{
   int targetLeg = (int)g_target + 1;
   int hcLeg = (int)g_hc;
   if(targetLeg <= 1) g_hc = ERL_HC_OFF;
   else if(hcLeg >= targetLeg) g_hc = (ERL_HC_MODE)(targetLeg - 1);
}

//=====================================================================
//  SIMULATION AND HISTORICAL AUDIT
//=====================================================================
int FindEntryBarIndex(const MqlRates &rates[], datetime t)
{
   for(int i = 0; i < ArraySize(rates); ++i)
      if(rates[i].time == t) return i;
   return -1;
}

int ResolveSameBar(const MqlRates &bar, int dir, double openPx, double tp, double sl)
{
   bool hitTp = dir > 0 ? bar.high >= tp : bar.low <= tp;
   bool hitSl = dir > 0 ? bar.low <= sl : bar.high >= sl;
   if(hitTp && !hitSl) return 1;
   if(hitSl && !hitTp) return -1;
   if(!hitTp && !hitSl) return 0;
   if(g_btSameBarPolicy == BT_SAMEBAR_TP_FIRST) return 1;
   if(g_btSameBarPolicy == BT_SAMEBAR_SL_FIRST) return -1;
   if(g_btSameBarPolicy == BT_SAMEBAR_CONSERVATIVE) return -1;
   double distTp = MathAbs(tp - openPx);
   double distSl = MathAbs(openPx - sl);
   return distTp < distSl ? 1 : -1;
}

double TargetPriceForSimulation(const ErlSignal &sig, ERL_RR_MODE target, ERL_TARGET_MODEL targetModel, double simEntry, double simRisk)
{
   if(targetModel == ERL_TARGET_NEXT_EXTERNAL && sig.externalTarget > 0.0)
   {
      bool validSide = sig.dir > 0 ? sig.externalTarget > simEntry + TickSize() : sig.externalTarget < simEntry - TickSize();
      if(validSide) return NormTradePrice(sig.externalTarget);
   }
   ERL_RR_MODE effective = EffectiveTargetModeByRisk(simRisk, target, targetModel);
   return NormTradePrice(simEntry + sig.dir * simRisk * TargetR(effective));
}

double SimulateSignal(const ErlSignal &sig, ERL_RR_MODE target, ERL_HC_MODE hc, ERL_TARGET_MODEL targetModel,
   ENUM_TIMEFRAMES entryTf, datetime maxTime, bool &closed, bool &won)
{
   closed = false;
   won = false;
   MqlRates rates[];
   int simBars = MathMax(InpCalcEntryBars, RequiredBarsForWindow(entryTf, g_btCutoff, 500));
   if(!CopySeries(entryTf, simBars, rates)) return 0.0;
   int entryIdx = FindEntryBarIndex(rates, sig.entryTime);
   if(entryIdx < 1) return 0.0;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = TickSize();
   double rawEntry = sig.entry;
   if(g_btFillMode == BT_FILL_NEXT_BAR_OPEN && entryIdx - 1 >= 1)
   {
      entryIdx = entryIdx - 1;
      rawEntry = rates[entryIdx].open;
   }
   else if(g_btFillMode == BT_FILL_CONSERVATIVE)
   {
      rawEntry = sig.dir > 0 ? rates[entryIdx].high : rates[entryIdx].low;
   }
   double executionCost = MathMax(0.0, g_btSpreadPts + g_btSlippagePts) * point;
   double simEntry = NormTradePrice(rawEntry + sig.dir * executionCost);
   double activeSl = sig.sl;
   double simRisk = MathAbs(simEntry - activeSl);
   if(simRisk <= TickSize()) return 0.0;
   double tp = TargetPriceForSimulation(sig, target, targetModel, simEntry, simRisk);
   double half = 0.0;
   if(hc != ERL_HC_OFF) half = NormTradePrice(simEntry + sig.dir * simRisk * TargetR((ERL_RR_MODE)((int)hc - 1)));
   bool halfDone = (hc == ERL_HC_OFF || half <= 0.0);
   double pnlR = 0.0;
   double commissionR = 0.0;
   double valuePerUnit = ValuePerPriceUnitPerLot();
   if(g_btCommissionPerLot > 0.0 && valuePerUnit > 0.0)
      commissionR = g_btCommissionPerLot / (simRisk * valuePerUnit);

   if(InpBacktestUseTickReplay)
   {
      datetime tickStart = sig.entryTime;
      if((g_btFillMode == BT_FILL_NEXT_BAR_OPEN || g_btFillMode == BT_FILL_CONSERVATIVE) && entryIdx >= 0 && entryIdx < ArraySize(rates))
         tickStart = rates[entryIdx].time;
      datetime tickEnd = maxTime > 0 ? maxTime : TimeCurrent();
      if(tickEnd > tickStart)
      {
         MqlTick ticks[];
         int copied = CopyTicksRange(_Symbol, ticks, COPY_TICKS_ALL, (ulong)tickStart * 1000, (ulong)tickEnd * 1000);
         if(copied > 0)
         {
            int first = -1;
            for(int k = 0; k < copied; ++k)
            {
               if(ticks[k].bid > 0.0 && ticks[k].ask > 0.0)
               {
                  first = k;
                  break;
               }
            }
            if(first >= 0)
            {
               double slip = MathMax(0.0, g_btSlippagePts) * point;
               simEntry = NormTradePrice(sig.dir > 0 ? ticks[first].ask + slip : ticks[first].bid - slip);
               activeSl = sig.sl;
               simRisk = MathAbs(simEntry - activeSl);
               if(simRisk > TickSize())
               {
                  tp = TargetPriceForSimulation(sig, target, targetModel, simEntry, simRisk);
                  half = 0.0;
                  if(hc != ERL_HC_OFF) half = NormTradePrice(simEntry + sig.dir * simRisk * TargetR((ERL_RR_MODE)((int)hc - 1)));
                  halfDone = (hc == ERL_HC_OFF || half <= 0.0);
                  pnlR = 0.0;
                  commissionR = 0.0;
                  if(g_btCommissionPerLot > 0.0 && valuePerUnit > 0.0)
                     commissionR = g_btCommissionPerLot / (simRisk * valuePerUnit);

                  for(int k = first; k < copied; ++k)
                  {
                     double bid = ticks[k].bid;
                     double ask = ticks[k].ask;
                     if(bid <= 0.0 || ask <= 0.0) continue;
                     double closePx = sig.dir > 0 ? bid : ask;

                     if(!halfDone)
                     {
                        bool hitHalf = sig.dir > 0 ? closePx >= half : closePx <= half;
                        if(hitHalf)
                        {
                           double halfR = MathAbs(half - simEntry) / simRisk;
                           pnlR += halfR * 0.5;
                           activeSl = simEntry;
                           halfDone = true;
                        }
                     }

                     bool hitSl = sig.dir > 0 ? closePx <= activeSl : closePx >= activeSl;
                     if(hitSl)
                     {
                        double slR = MathAbs(simEntry - activeSl) / simRisk;
                        pnlR -= halfDone && hc != ERL_HC_OFF ? slR * 0.5 : slR;
                        pnlR -= commissionR;
                        closed = true;
                        won = pnlR > 0.0;
                        return pnlR;
                     }

                     bool hitTp = sig.dir > 0 ? closePx >= tp : closePx <= tp;
                     if(hitTp)
                     {
                        double targetR = MathAbs(tp - simEntry) / simRisk;
                        pnlR += halfDone && hc != ERL_HC_OFF ? targetR * 0.5 : targetR;
                        pnlR -= commissionR;
                        closed = true;
                        won = pnlR > 0.0;
                        return pnlR;
                     }
                  }
               }
            }
         }
      }
   }

   for(int i = entryIdx; i >= 1; --i)
   {
      if(maxTime > 0 && rates[i].time > maxTime) break;
      if(!halfDone)
      {
         bool hitHalf = sig.dir > 0 ? rates[i].high >= half : rates[i].low <= half;
         if(hitHalf)
         {
            double halfR = MathAbs(half - simEntry) / simRisk;
            pnlR += halfR * 0.5;
            activeSl = simEntry;
            halfDone = true;
         }
      }

      double openRef = (i == entryIdx ? simEntry : rates[i].open);
      int res = ResolveSameBar(rates[i], sig.dir, openRef, tp, activeSl);
      if(res > 0)
      {
         double targetR = MathAbs(tp - simEntry) / simRisk;
         pnlR += halfDone && hc != ERL_HC_OFF ? targetR * 0.5 : targetR;
         pnlR -= commissionR;
         closed = true;
         won = pnlR > 0.0;
         return pnlR;
      }
      if(res < 0)
      {
         double slR = MathAbs(simEntry - activeSl) / simRisk;
         pnlR -= halfDone && hc != ERL_HC_OFF ? slR * 0.5 : slR;
         pnlR -= commissionR;
         closed = true;
         won = pnlR > 0.0;
         return pnlR;
      }
   }
   return pnlR;
}

SimStats CalculateStats(ErlSignal &signals[], ERL_RR_MODE target, ERL_HC_MODE hc, ERL_TARGET_MODEL targetModel, ENUM_TIMEFRAMES entryTf)
{
   SimStats st;
   ZeroMemory(st);
   for(int i = 0; i < ArraySize(signals); ++i)
   {
      bool closed = false, won = false;
      double r = SimulateSignal(signals[i], target, hc, targetModel, entryTf, 0, closed, won);
      st.total++;
      st.netR += r;
      if(!closed)
      {
         st.open++;
         continue;
      }
      if(won)
      {
         st.wins++;
         st.wonR += MathMax(0.0, r);
      }
      else
      {
         st.losses++;
         st.lostR += MathAbs(MathMin(0.0, r));
      }
   }
   st.pf = st.lostR > 0.0 ? st.wonR / st.lostR : (st.wonR > 0.0 ? 99.0 : 0.0);
   return st;
}

void RecalculateHistoricalStats()
{
   datetime cutoff = TimeCurrent() - HistDays() * 86400;
   ErlSignal signals[];
   BuildSignals(g_htf, g_entryTf, g_swingLookback, g_weeklyBias, g_entryModel, g_stopModel, g_targetModel, g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg, cutoff, signals);
   g_hist = CalculateStats(signals, g_target, g_hc, g_targetModel, g_entryTf);
}

//=====================================================================
//  RISK ENGINE
//=====================================================================
double BaseCapital()
{
   if(InpInitialBalanceOverride > 0.0) return InpInitialBalanceOverride;
   return AccountInfoDouble(ACCOUNT_BALANCE);
}

double DailyClosedPnl()
{
   MqlDateTime now;
   TimeToStruct(TimeGMT(), now);
   now.hour = InpDayResetHourGmt;
   now.min = 0;
   now.sec = 0;
   datetime start = StructToTime(now);
   if(TimeGMT() < start) start -= 86400;
   HistorySelect(start, TimeCurrent());
   double pnl = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(!IsOwnMagic(magic)) continue;
      long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT) continue;
      pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return pnl;
}

double OwnOpenRiskMoney()
{
   double risk = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0 || vol <= 0.0) continue;
      double profit = 0.0;
      ENUM_ORDER_TYPE side = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      if(OrderCalcProfit(side, _Symbol, vol, open, sl, profit)) risk += MathAbs(profit);
   }
   return risk;
}

bool RiskGateAllows(double entry, double sl, double &lot, string &reason)
{
   reason = "";
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minLot <= 0.0) minLot = 0.01;
   lot = NormalizeVolume(InpFixedLot);

   double riskDistance = MathAbs(entry - sl);
   double valuePerUnit = ValuePerPriceUnitPerLot();
   if(riskDistance <= TickSize() || valuePerUnit <= 0.0)
   {
      reason = "invalid_risk_geometry";
      return false;
   }

   if(InpAccountRiskEnabled)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double base = BaseCapital();
      if(g_equityPeak <= 0.0) g_equityPeak = equity;
      g_equityPeak = MathMax(g_equityPeak, equity);

      double dailyPnl = DailyClosedPnl();
      double ddFromPeak = g_equityPeak - equity;
      if(InpDailyLossLimitPct > 0.0 && dailyPnl <= -base * InpDailyLossLimitPct / 100.0)
      {
         reason = "daily_loss_limit";
         return false;
      }
      if(InpMaxDrawdownPct > 0.0 && ddFromPeak >= base * InpMaxDrawdownPct / 100.0)
      {
         reason = "max_drawdown_limit";
         return false;
      }

      double riskMoney = equity * MathMax(0.01, InpRiskPerTradePct) / 100.0;
      lot = NormalizeVolume(riskMoney / (riskDistance * valuePerUnit));
      double actualRiskMoney = RiskMoneyForLot(lot, sl < entry ? 1 : -1, entry, sl);
      double portfolioCap = equity * MathMax(0.01, InpMaxPortfolioRiskPct) / 100.0;
      if(actualRiskMoney <= 0.0)
      {
         reason = "risk_calc_failed";
         return false;
      }
      if(OwnOpenRiskMoney() + actualRiskMoney > portfolioCap)
      {
         reason = "portfolio_risk_limit";
         return false;
      }
   }

   if(lot < minLot)
   {
      reason = "lot_below_min";
      return false;
   }
   return true;
}

//=====================================================================
//  AUDIT ENGINE
//=====================================================================
void AuditWrite(string eventName, string id, int dir, double entry, double sl, double tp, double lot, string detail)
{
   if(!g_auditRuntime) return;
   if(IsTesterMode()) return;
   string file = "ERL_IRL_TradeAudit_" + FileDate(TimeCurrent()) + ".csv";
   bool exists = FileIsExist(file);
   int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   if(!exists || FileSize(h) == 0)
   {
      FileWrite(h, "server_time", "gmt_time", "symbol", "tf", "event", "id", "dir", "entry", "sl", "tp", "lot", "spread_pts", "status", "detail");
   }
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      _Symbol, TfLabel(_Period), eventName, id, DirLabel(dir), DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
      DoubleToString(tp, _Digits), DoubleToString(lot, 4), DoubleToString(g_lastSpreadPts, 0), g_lastStatus, detail);
   FileClose(h);
}

string ErlTesterAudit_FileStamp()
{
   MqlDateTime d; TimeToStruct(TimeGMT(), d);
   return StringFormat("%04d%02d%02d_%02d%02d%02d", d.year, d.mon, d.day, d.hour, d.min, d.sec);
}

string ErlTesterAudit_DealEntryLabel(long entryType)
{
   if(entryType == DEAL_ENTRY_IN) return "IN";
   if(entryType == DEAL_ENTRY_OUT) return "OUT";
   if(entryType == DEAL_ENTRY_INOUT) return "INOUT";
   if(entryType == DEAL_ENTRY_OUT_BY) return "OUT_BY";
   return IntegerToString((int)entryType);
}

string ErlTesterAudit_DealTypeLabel(long dealType)
{
   if(dealType == DEAL_TYPE_BUY) return "BUY";
   if(dealType == DEAL_TYPE_SELL) return "SELL";
   if(dealType == DEAL_TYPE_BALANCE) return "BALANCE";
   if(dealType == DEAL_TYPE_CREDIT) return "CREDIT";
   return IntegerToString((int)dealType);
}

string ErlTesterAudit_DealReasonLabel(long reason)
{
   if(reason == DEAL_REASON_SL) return "SL";
   if(reason == DEAL_REASON_TP) return "TP";
   if(reason == DEAL_REASON_SO) return "STOP_OUT";
   if(reason == DEAL_REASON_EXPERT) return "EXPERT";
   if(reason == DEAL_REASON_CLIENT) return "CLIENT";
   if(reason == DEAL_REASON_MOBILE) return "MOBILE";
   if(reason == DEAL_REASON_WEB) return "WEB";
   return IntegerToString((int)reason);
}

void ErlTesterAudit_Init()
{
   g_testerTradeAuditRows = 0;
   g_testerTradeAuditFile = "ERL_IRL_TesterTradeAudit_" + ErlTesterAudit_FileStamp() + ".csv";
}

void ErlTesterAudit_WriteDeal(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpTesterTradeAuditCsv || !MQLInfoInteger(MQL_TESTER)) return;
   if(InpTesterTradeAuditMaxRows > 0 && g_testerTradeAuditRows >= InpTesterTradeAuditMaxRows) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   long magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(!IsOwnMagic(magic)) return;

   bool exists = FileIsExist(g_testerTradeAuditFile);
   int h = FileOpen(g_testerTradeAuditFile, FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE) return;
   if(!exists || FileSize(h) == 0)
      FileWrite(h,
         "job_id","engine","ea","build","symbol","timeframe","server_time","gmt_time",
         "deal","position_id","order","entry_type","deal_type","reason","magic",
         "volume","price","request_price","request_sl","request_tp","profit","swap","commission","fee",
         "retcode","comment");
   FileSeek(h, 0, SEEK_END);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   double commission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double fee = HistoryDealGetDouble(trans.deal, DEAL_FEE);
   FileWrite(h,
      InpValidationJobId, "mt5_strategy_tester_trade", "ERL_IRL_SwingModel_EA", ERL_BUILD, _Symbol, TfLabel(_Period),
      TimeToString((datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME), TIME_DATE|TIME_SECONDS),
      TimeToString(TimeGMT(), TIME_DATE|TIME_SECONDS),
      IntegerToString((long)trans.deal),
      IntegerToString((long)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID)),
      IntegerToString((long)HistoryDealGetInteger(trans.deal, DEAL_ORDER)),
      ErlTesterAudit_DealEntryLabel(HistoryDealGetInteger(trans.deal, DEAL_ENTRY)),
      ErlTesterAudit_DealTypeLabel(HistoryDealGetInteger(trans.deal, DEAL_TYPE)),
      ErlTesterAudit_DealReasonLabel(HistoryDealGetInteger(trans.deal, DEAL_REASON)),
      IntegerToString(magic),
      DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 4),
      DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits),
      DoubleToString(request.price, _Digits), DoubleToString(request.sl, _Digits), DoubleToString(request.tp, _Digits),
      DoubleToString(profit, 2), DoubleToString(swap, 2), DoubleToString(commission, 2), DoubleToString(fee, 2),
      IntegerToString((int)result.retcode),
      HistoryDealGetString(trans.deal, DEAL_COMMENT));
   FileClose(h);
   g_testerTradeAuditRows++;
}

void BtAppendCoverage(ENUM_TIMEFRAMES tf, int bars, datetime cutoff, string label, string &detail)
{
   MqlRates rates[];
   int requestedBars = MathMax(bars, RequiredBarsForWindow(tf, cutoff, 500));
   int copied = CopyRates(_Symbol, tf, 0, requestedBars, rates);
   datetime oldest = 0;
   datetime newest = 0;
   for(int i = 0; i < copied; ++i)
   {
      datetime t = rates[i].time;
      if(t <= 0) continue;
      if(oldest == 0 || t < oldest) oldest = t;
      if(newest == 0 || t > newest) newest = t;
   }
   double requestedSec = MathMax(1.0, (double)g_btWeeks * 7.0 * 86400.0);
   double loadedSec = (oldest > 0 && newest > oldest) ? (double)(newest - oldest) : 0.0;
   double coverage = MathMin(100.0, loadedSec / requestedSec * 100.0);
   if(detail != "") detail += " | ";
   detail += label + "=" + TfLabel(tf)
      + " bars=" + IntegerToString(copied) + "/" + IntegerToString(requestedBars)
      + " oldest=" + (oldest > 0 ? TimeToString(oldest, TIME_DATE | TIME_SECONDS) : "")
      + " newest=" + (newest > 0 ? TimeToString(newest, TIME_DATE | TIME_SECONDS) : "")
      + " coverage=" + DoubleToString(coverage, 1) + "%";
   if(cutoff > 0 && oldest > cutoff) detail += " insufficient_history";
}

string BtBuildCoverageSummary()
{
   string detail = "";
   BtAppendCoverage(PERIOD_H4, InpCalcHtfBars, g_btCutoff, "htf_h4", detail);
   BtAppendCoverage(PERIOD_D1, InpCalcHtfBars, g_btCutoff, "htf_d1", detail);
   BtAppendCoverage(PERIOD_M15, InpCalcEntryBars, g_btCutoff, "entry_m15", detail);
   BtAppendCoverage(PERIOD_M30, InpCalcEntryBars, g_btCutoff, "entry_m30", detail);
   BtAppendCoverage(PERIOD_H1, InpCalcEntryBars, g_btCutoff, "entry_h1", detail);
   return detail;
}

void BtProcessAudit(string eventName, string detail)
{
   if(!g_auditRuntime) return;
   if(IsTesterMode() && !IsValidationTester()) return;
   string file = "ERL_IRL_BacktestProcess_" + FileDate(TimeGMT()) + ".csv";
   bool exists = FileIsExist(file);
   int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   if(!exists || FileSize(h) == 0)
   {
      FileWrite(h, "gmt_time", "server_time", "event", "build", "symbol", "chart_tf", "result_file",
         "weeks", "requested_from", "combos_total", "step", "elapsed_ms", "fill_mode", "same_bar_policy",
         "spread_pts", "slippage_pts", "commission_per_lot", "coverage_summary", "detail");
   }
   FileWrite(h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName, ERL_BUILD, _Symbol, TfLabel(_Period), g_btFileName,
      IntegerToString(g_btWeeks),
      g_btCutoff > 0 ? TimeToString(g_btCutoff, TIME_DATE | TIME_SECONDS) : "",
      IntegerToString(g_btTotal), IntegerToString(g_btStep), IntegerToString((int)g_btElapsedMs),
      BtFillLabel(g_btFillMode), BtSameLabel(g_btSameBarPolicy),
      DoubleToString(g_btSpreadPts, 1), DoubleToString(g_btSlippagePts, 1), DoubleToString(g_btCommissionPerLot, 2),
      g_btCoverageSummary, detail);
   FileClose(h);
}

void ProbePositions()
{
   if(!g_auditRuntime) return;
   if(IsTesterMode()) return;
   datetime now = TimeCurrent();
   if(now - g_lastAuditProbe < InpAuditProbeSec) return;
   g_lastAuditProbe = now;

   string hash = "";
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      hash += IntegerToString((int)ticket) + ":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + ";";
   }
   if(InpAuditProbeOnChangeOnly && hash == g_lastProbeHash) return;
   g_lastProbeHash = hash;

   string file = "ERL_IRL_PositionProbe_" + FileDate(now) + ".csv";
   bool exists = FileIsExist(file);
   int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   if(!exists || FileSize(h) == 0)
      FileWrite(h, "server_time", "symbol", "ticket", "type", "volume", "open", "sl", "tp", "bid", "ask", "profit", "risk_money");

   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double risk = 0.0;
      if(sl > 0.0)
      {
         double p = 0.0;
         ENUM_ORDER_TYPE closeSide = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         if(OrderCalcProfit(closeSide, _Symbol, vol, open, sl, p)) risk = MathAbs(p);
      }
      FileWrite(h, TimeToString(now, TIME_DATE | TIME_SECONDS), _Symbol, IntegerToString((int)ticket),
         PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL",
         DoubleToString(vol, 4), DoubleToString(open, _Digits), DoubleToString(sl, _Digits), DoubleToString(PositionGetDouble(POSITION_TP), _Digits),
         DoubleToString(tick.bid, _Digits), DoubleToString(tick.ask, _Digits), DoubleToString(PositionGetDouble(POSITION_PROFIT), 2), DoubleToString(risk, 2));
   }
   FileClose(h);
}

void ScanClosedHistory()
{
   if(!g_auditRuntime) return;
   if(IsTesterMode()) return;
   datetime now = TimeCurrent();
   if(now - g_lastHistoryScan < InpAuditHistoryScanSec) return;
   g_lastHistoryScan = now;
   HistorySelect(now - 86400 * 7, now);
   int total = HistoryDealsTotal();
   for(int i = MathMax(0, total - 80); i < total; ++i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || deal <= g_lastHistoryTicket) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)HistoryDealGetInteger(deal, DEAL_MAGIC))) continue;
      long entryType = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT) continue;
      g_lastHistoryTicket = deal;
      string reason = "closed_by_unknown";
      long why = HistoryDealGetInteger(deal, DEAL_REASON);
      if(why == DEAL_REASON_SL) reason = "closed_by_broker_sl";
      if(why == DEAL_REASON_TP) reason = "closed_by_broker_tp";
      if(why == DEAL_REASON_CLIENT || why == DEAL_REASON_MOBILE || why == DEAL_REASON_WEB) reason = "closed_manual";
      AuditWrite(reason, IntegerToString((int)deal), 0, HistoryDealGetDouble(deal, DEAL_PRICE), 0, 0,
         HistoryDealGetDouble(deal, DEAL_VOLUME), "profit=" + DoubleToString(HistoryDealGetDouble(deal, DEAL_PROFIT), 2));
   }
}

//=====================================================================
//  CHART OBJECT HELPERS
//=====================================================================
void DeleteByPrefix(string prefix)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, prefix) == 0) ObjectDelete(0, name);
   }
}

void RectObj(string id, int x, int y, int w, int h, color bg, color border)
{
   if(IsTesterMode()) return;
   string name = PFX + id;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, DASH_Z);
}

void LabelObj(string id, int x, int y, string text, color clr, int fontSize = 8)
{
   if(IsTesterMode()) return;
   string name = PFX + id;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, DASH_Z + 1);
}

void ButtonObj(string id, int x, int y, int w, int h, string text, color bg)
{
   if(IsTesterMode()) return;
   string name = PFX + id;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, DASH_Z + 2);
}

void EditObj(string id, int x, int y, int w, int h, string text)
{
   if(IsTesterMode()) return;
   string name = PFX + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'38,46,60');
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'90,178,255');
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, DASH_Z + 3);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, DASH_Z + 3);
}

void DrawArrow(string id, datetime t, double price, int dir, color clr)
{
   if(IsTesterMode()) return;
   string name = PFX + "HIST_" + id;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, dir > 0 ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

double SignalArrowPrice(datetime t, int dir, double fallbackEntry, double risk)
{
   int shift = iBarShift(_Symbol, g_entryTf, t, true);
   double pad = MathMax(MathMax(risk, TickSize()) * 0.18, TickSize() * 40.0);
   if(shift >= 0)
   {
      double low = iLow(_Symbol, g_entryTf, shift);
      double high = iHigh(_Symbol, g_entryTf, shift);
      if(dir > 0 && low > 0.0) return low - pad;
      if(dir < 0 && high > 0.0) return high + pad;
   }
   return dir > 0 ? fallbackEntry - pad : fallbackEntry + pad;
}

void DrawChartText(string id, datetime t, double price, string text, color clr)
{
   if(IsTesterMode()) return;
   string name = PFX + "HISTTXT_" + id;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawHLine(string id, double price, color clr, ENUM_LINE_STYLE style = STYLE_DASH)
{
   if(IsTesterMode()) return;
   string name = PFX + id;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawFvgBox(string id, datetime t1, datetime t2, double low, double high, color clr)
{
   if(IsTesterMode()) return;
   if(!InpDrawFvgZones) return;
   string name = PFX + "FVG_" + id;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, high, t2, low);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, high);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, low);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawHistoricalSignals()
{
   DeleteByPrefix(PFX + "HIST_");
   DeleteByPrefix(PFX + "HISTTXT_");
   DeleteByPrefix(PFX + "FVG_");
   if(IsTesterMode()) return;
   if(!InpDrawHistoricalSignals) return;
   datetime cutoff = TimeCurrent() - HistDays() * 86400;
   ErlSignal signals[];
   int count = BuildSignals(g_htf, g_entryTf, g_swingLookback, g_weeklyBias, g_entryModel, g_stopModel, g_targetModel, g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg, cutoff, signals);
   for(int i = 0; i < count; ++i)
   {
      string id = IntegerToString(i) + "_" + IntegerToString((int)signals[i].entryTime);
      bool closed=false, won=false;
      double r=SimulateSignal(signals[i], g_target, g_hc, g_targetModel, g_entryTf, 0, closed, won);
      color clr = won ? C'60,220,140' : (closed ? C'255,80,110' : C'255,204,82');
      double arrowPrice = SignalArrowPrice(signals[i].entryTime, signals[i].dir, signals[i].entry, signals[i].risk);
      DrawArrow(id, signals[i].entryTime, arrowPrice, signals[i].dir, clr);
      double pad = MathMax(MathAbs(signals[i].entry - signals[i].sl) * 0.25, TickSize() * 30.0);
      string txt = DirLabel(signals[i].dir) + " " + (r >= 0 ? "+" : "") + DoubleToString(r, 2) + "R $"
         + (ApproxMoneyFromR(r) >= 0 ? "+" : "") + DoubleToString(ApproxMoneyFromR(r), 2);
      DrawChartText(id, signals[i].entryTime, signals[i].dir > 0 ? arrowPrice - pad : arrowPrice + pad, txt, clr);
      DrawFvgBox(id, signals[i].htfTime, signals[i].entryTime + PeriodSeconds(g_entryTf) * 4, signals[i].fvgLow, signals[i].fvgHigh, clr);
   }
   RecalculateHistoricalStats();
}

void DrawLiveLevelsForPosition()
{
   DeleteByPrefix(PFX + "LV_");
   if(IsTesterMode()) return;
   if(!InpDrawLiveLevels) return;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      DrawHLine("LV_ENTRY_" + IntegerToString((int)ticket), open, C'90,178,255', STYLE_SOLID);
      if(sl > 0) DrawHLine("LV_SL_" + IntegerToString((int)ticket), sl, C'255,80,110', STYLE_DASH);
      if(tp > 0) DrawHLine("LV_TP_" + IntegerToString((int)ticket), tp, C'80,255,180', STYLE_DASH);
   }
}

//=====================================================================
//  LIVE EXECUTION AND POSITION MANAGEMENT
//=====================================================================
string TicketKey(ulong ticket, string field)
{
   return "ERLIRL|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + IntegerToString((int)ticket) + "|" + field;
}

void StorePositionPlan(ulong ticket, const ErlSignal &sig, ERL_HC_MODE hc)
{
   GlobalVariableSet(TicketKey(ticket, "entry"), sig.entry);
   GlobalVariableSet(TicketKey(ticket, "sl"), sig.sl);
   GlobalVariableSet(TicketKey(ticket, "tp1"), sig.tp1);
   GlobalVariableSet(TicketKey(ticket, "tp2"), sig.tp2);
   GlobalVariableSet(TicketKey(ticket, "tp3"), sig.tp3);
   GlobalVariableSet(TicketKey(ticket, "tp4"), sig.tp4);
   GlobalVariableSet(TicketKey(ticket, "tp5"), sig.tp5);
   GlobalVariableSet(TicketKey(ticket, "tp6"), sig.tp6);
   GlobalVariableSet(TicketKey(ticket, "hc"), (double)hc);
   GlobalVariableSet(TicketKey(ticket, "halfDone"), 0.0);
}

double GetPlan(ulong ticket, string field, double fallback = 0.0)
{
   string key = TicketKey(ticket, field);
   if(!GlobalVariableCheck(key)) return fallback;
   return GlobalVariableGet(key);
}

ulong FindNewestOwnPosition()
{
   ulong best = 0;
   datetime bestTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= bestTime)
      {
         bestTime = t;
         best = ticket;
      }
   }
   return best;
}

int OwnPositionCount(int dirFilter = 0)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      if(dirFilter == 0 || dirFilter == dir) count++;
   }
   return count;
}

void CloseOwnPositions(int dirFilter = 0)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      if(dirFilter != 0 && dirFilter != dir) continue;
      trade.PositionClose(ticket);
      AuditWrite("close_request", IntegerToString((int)ticket), dir, PositionGetDouble(POSITION_PRICE_OPEN),
         PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP), PositionGetDouble(POSITION_VOLUME), "manual_or_reverse");
   }
}

void BuildExecutableSignal(const ErlSignal &raw, double liveEntry, ErlSignal &execSig, string &detail)
{
   execSig = raw;
   detail = "";
   double minStop = MinStopDistance() * 1.20;
   execSig.entry = NormTradePrice(liveEntry);
   execSig.sl = NormTradePrice(raw.sl);
   double originalSl = execSig.sl;

   if(execSig.dir > 0)
   {
      if(execSig.sl >= execSig.entry - minStop)
         execSig.sl = NormTradePrice(execSig.entry - minStop);
   }
   else
   {
      if(execSig.sl <= execSig.entry + minStop)
         execSig.sl = NormTradePrice(execSig.entry + minStop);
   }

   execSig.sl = ApplySlDistancePct(execSig.dir, execSig.entry, execSig.sl);
   execSig.risk = MathAbs(execSig.entry - execSig.sl);
   if(execSig.risk <= TickSize())
      execSig.risk = minStop;
   execSig.tp1 = NormTradePrice(execSig.entry + execSig.dir * execSig.risk * 0.5);
   execSig.tp2 = NormTradePrice(execSig.entry + execSig.dir * execSig.risk * 1.0);
   execSig.tp3 = NormTradePrice(execSig.entry + execSig.dir * execSig.risk * 1.5);
   execSig.tp4 = NormTradePrice(execSig.entry + execSig.dir * execSig.risk * 2.0);
   execSig.tp5 = NormTradePrice(execSig.entry + execSig.dir * execSig.risk * 2.5);
   execSig.tp6 = NormTradePrice(execSig.entry + execSig.dir * execSig.risk * 3.0);

   if(MathAbs(originalSl - execSig.sl) > TickSize() * 0.5)
      detail = "broker_stop_adjusted original_sl=" + DoubleToString(originalSl, _Digits) + " adjusted_sl=" + DoubleToString(execSig.sl, _Digits);
}

bool OpenSignal(const ErlSignal &sig)
{
   if(!g_eaEnabled)
   {
      g_lastBlock = "ea_disabled";
      return false;
   }
   if(sig.id == g_lastSignalId)
   {
      g_lastBlock = "duplicate_signal";
      return false;
   }
   if(InpBlockSameDirection && OwnPositionCount(sig.dir) > 0)
   {
      g_lastBlock = "same_direction_position";
      return false;
   }
   if(InpCloseOnReverse && OwnPositionCount(-sig.dir) > 0)
      CloseOwnPositions(-sig.dir);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   g_lastSpreadPts = CurrentSpreadPoints();
   double liveEntry = sig.dir > 0 ? tick.ask : tick.bid;
   ErlSignal execSig;
   string execDetail = "";
   BuildExecutableSignal(sig, liveEntry, execSig, execDetail);
   double tp = SelectedTarget(execSig, g_target);
   double lot = 0.0;
   string riskReason = "";
   if(!RiskGateAllows(execSig.entry, execSig.sl, lot, riskReason))
   {
      g_lastBlock = riskReason;
      AuditWrite("risk_block", sig.id, sig.dir, execSig.entry, execSig.sl, tp, lot, riskReason + " " + execDetail);
      return false;
   }
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = trade.PositionOpen(_Symbol, sig.dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot,
      execSig.entry, execSig.sl, tp, "ERL_IRL " + DirLabel(sig.dir));
   if(!ok)
   {
      string detail = "ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription();
      g_lastStatus = "ORDER_FAILED";
      g_lastBlock = detail;
      AuditWrite("order_failed", sig.id, sig.dir, execSig.entry, execSig.sl, tp, lot, detail + " " + execDetail);
      return false;
   }

   ulong posTicket = FindNewestOwnPosition();
   if(posTicket > 0) StorePositionPlan(posTicket, execSig, g_hc);
   g_lastSignalId = sig.id;
   g_lastSignalTime = sig.entryTime;
   g_lastSignalDir = sig.dir;
   g_lastEntry = execSig.entry;
   g_lastSl = execSig.sl;
   g_lastTp = tp;
   g_lastStatus = "OPENED";
   g_lastBlock = "";
   AuditWrite("order_opened", sig.id, sig.dir, execSig.entry, execSig.sl, tp, lot,
      "signal_entry=" + DoubleToString(sig.entry, _Digits) + " ticket=" + IntegerToString((int)posTicket) + " " + execDetail);
   return true;
}

void TryOpenLatestSignal()
{
   datetime closedBarTime = iTime(_Symbol, g_entryTf, 1);
   if(closedBarTime <= 0) return;
   if(closedBarTime == g_lastLiveScanBar) return;
   g_lastLiveScanBar = closedBarTime;

   datetime cutoff = TimeCurrent() - 7 * 86400;
   ErlSignal signals[];
   int count = BuildSignals(g_htf, g_entryTf, g_swingLookback, g_weeklyBias, g_entryModel, g_stopModel, g_targetModel, g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg, cutoff, signals);
   if(count <= 0)
   {
      g_lastStatus = "NO_SIGNAL";
      return;
   }
   ErlSignal latest = signals[count - 1];
   if(latest.entryTime <= g_lastSignalTime && latest.id == g_lastSignalId) return;
   // Only live-trade fresh signals; historical chart load must not open old setups.
   int freshSec = MathMax(PeriodSeconds(g_entryTf) * 2, 180);
   if(TimeCurrent() - latest.entryTime > freshSec)
   {
      g_lastStatus = "LATEST_OLD";
      g_lastSignalTime = MathMax(g_lastSignalTime, latest.entryTime);
      return;
   }
   OpenSignal(latest);
}

void ManagePositions()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;

      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      ERL_HC_MODE hc = (ERL_HC_MODE)(int)GetPlan(ticket, "hc", (double)ERL_HC_OFF);
      bool halfDone = GetPlan(ticket, "halfDone", 0.0) > 0.5;
      if(hc == ERL_HC_OFF || halfDone) continue;
      double trigger = GetPlan(ticket, "tp" + IntegerToString((int)hc));
      if(trigger <= 0.0) continue;
      bool hit = dir > 0 ? tick.bid >= trigger : tick.ask <= trigger;
      if(!hit) continue;
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = minLot;
      double halfVol = NormalizeVolume(MathFloor((vol * 0.5) / step) * step);
      bool partialOk = false;
      if(halfVol >= minLot && halfVol < vol)
      {
         partialOk = trade.PositionClosePartial(ticket, halfVol);
         AuditWrite(partialOk ? "half_close_done" : "half_close_failed", IntegerToString((int)ticket), dir,
            open, sl, tp, halfVol, "trigger=" + DoubleToString(trigger, _Digits));
      }
      else
      {
         partialOk = true;
         AuditWrite("half_close_skipped_min_volume", IntegerToString((int)ticket), dir,
            open, sl, tp, vol, "trigger=" + DoubleToString(trigger, _Digits));
      }
      if(!partialOk)
         continue;
      bool mod = trade.PositionModify(ticket, NormTradePrice(open), tp);
      AuditWrite(mod ? "sl_to_be_done" : "sl_to_be_failed", IntegerToString((int)ticket), dir, open, open, tp, vol,
         "trigger=" + DoubleToString(trigger, _Digits));
      if(mod)
         GlobalVariableSet(TicketKey(ticket, "halfDone"), 1.0);
   }
}

//=====================================================================
//  BRUTE-FORCE BACKTEST ENGINE
//=====================================================================
void BuildCombos()
{
   ArrayFree(g_btCombos);
   ENUM_TIMEFRAMES htfs[] = { PERIOD_H4, PERIOD_D1 };
   ENUM_TIMEFRAMES etfs[] = { PERIOD_M15, PERIOD_M30, PERIOD_H1 };
   int swings[] = { 3, 5, 8 };
   bool biases[] = { false, true };
   ERL_ENTRY_MODEL entryModels[] = { ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG, ERL_ENTRY_LEGACY_HTF_FVG_TAP };
   ERL_STOP_MODEL stopModels[] = { ERL_STOP_FIRST_FVG_CANDLE, ERL_STOP_FVG_BOUNDARY };
   ERL_TARGET_MODEL targetModels[] = { ERL_TARGET_NEXT_EXTERNAL, ERL_TARGET_AUTO_STOP_SIZE, ERL_TARGET_FIXED_R };
   for(int h = 0; h < ArraySize(htfs); ++h)
   {
      for(int e = 0; e < ArraySize(etfs); ++e)
      {
         for(int s = 0; s < ArraySize(swings); ++s)
         {
            for(int b = 0; b < ArraySize(biases); ++b)
            {
               for(int em = 0; em < ArraySize(entryModels); ++em)
               {
                  for(int sm = 0; sm < ArraySize(stopModels); ++sm)
                  {
                     for(int tm = 0; tm < ArraySize(targetModels); ++tm)
                     {
                        for(int rr = 0; rr < 6; ++rr)
                        {
                           int maxHc = rr == 0 ? 0 : rr;
                           for(int hc = 0; hc <= maxHc; ++hc)
                           {
                              int n = ArraySize(g_btCombos);
                              ArrayResize(g_btCombos, n + 1);
                              g_btCombos[n].htf = htfs[h];
                              g_btCombos[n].entryTf = etfs[e];
                              g_btCombos[n].swing = swings[s];
                              g_btCombos[n].target = (ERL_RR_MODE)rr;
                              g_btCombos[n].hc = (ERL_HC_MODE)hc;
                              g_btCombos[n].bias = biases[b];
                              g_btCombos[n].entryModel = entryModels[em];
                              g_btCombos[n].stopModel = stopModels[sm];
                              g_btCombos[n].targetModel = targetModels[tm];
                              g_btCombos[n].requireIrlTouch = g_requireIrlTouch;
                              g_btCombos[n].requireEntrySweep = g_requireEntrySweep;
                              g_btCombos[n].requireDisplacementFvg = g_requireDisplacementFvg;
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }
   g_btTotal = ArraySize(g_btCombos);
}

bool BtWriteHeader(int h)
{
   return FileWrite(h, "timestamp", "symbol", "htf", "entry_tf", "swing", "entry_model", "stop_model", "target_model", "strictness",
      "target", "hc_be", "weekly_bias", "weeks",
      "total", "wins", "losses", "open", "win_rate", "net_r", "won_r", "lost_r", "pf", "avg_r") > 0;
}

void StartBacktest()
{
   if(g_btRunning) return;
   string edit = PFX + "EDIT_BT_WEEKS";
   if(ObjectFind(0, edit) >= 0)
   {
      int v = (int)StringToInteger(ObjectGetString(0, edit, OBJPROP_TEXT));
      if(v > 0 && v <= 52) g_btWeeks = v;
   }
   string spreadEdit = PFX + "EDIT_BT_SPREAD";
   string slipEdit = PFX + "EDIT_BT_SLIP";
   string commEdit = PFX + "EDIT_BT_COMM";
   if(ObjectFind(0, spreadEdit) >= 0)
   {
      g_btSpreadPts = StringToDouble(ObjectGetString(0, spreadEdit, OBJPROP_TEXT));
      if(g_btSpreadPts <= 0.0) g_btSpreadPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   }
   if(ObjectFind(0, slipEdit) >= 0) g_btSlippagePts = MathMax(0.0, StringToDouble(ObjectGetString(0, slipEdit, OBJPROP_TEXT)));
   if(ObjectFind(0, commEdit) >= 0) g_btCommissionPerLot = MathMax(0.0, StringToDouble(ObjectGetString(0, commEdit, OBJPROP_TEXT)));
   BuildCombos();
   g_btStep = 0;
   g_btRunning = true;
   g_btStartMs = GetTickCount();
   g_btElapsedMs = 0;
   g_btCutoff = TimeCurrent() - g_btWeeks * 7 * 86400;
   g_btLastResult = "Starting";
   g_btFileName = "ERL_IRL_BruteBacktest_" + FileStamp(TimeCurrent()) + ".csv";
   g_btCoverageSummary = BtBuildCoverageSummary();
   int h = FileOpen(g_btFileName, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      BtWriteHeader(h);
      FileClose(h);
   }
   AuditWrite("backtest_start", g_btFileName, 0, 0, 0, 0, 0, "combos=" + IntegerToString(g_btTotal));
   BtProcessAudit("start", "combos=" + IntegerToString(g_btTotal));
}

void StopBacktest()
{
   if(!g_btRunning) return;
   g_btRunning = false;
   g_btElapsedMs = GetTickCount() - g_btStartMs;
   g_btLastResult = "Stopped " + IntegerToString(g_btStep) + "/" + IntegerToString(g_btTotal);
   AuditWrite("backtest_stop", g_btFileName, 0, 0, 0, 0, 0, g_btLastResult);
   BtProcessAudit("stop", g_btLastResult);
}

void BacktestStep()
{
   if(!g_btRunning) return;
   if(g_btStep >= g_btTotal)
   {
      g_btRunning = false;
      g_btElapsedMs = GetTickCount() - g_btStartMs;
      g_btLastResult = "Done " + IntegerToString(g_btTotal) + " rows -> " + g_btFileName;
      AuditWrite("backtest_done", g_btFileName, 0, 0, 0, 0, 0, g_btLastResult);
      BtProcessAudit("finish", g_btLastResult);
      return;
   }

   int h = FileOpen(g_btFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      g_btRunning = false;
      g_btElapsedMs = GetTickCount() - g_btStartMs;
      g_btLastResult = "CSV open failed";
      BtProcessAudit("csv_open_failed", g_btLastResult);
      return;
   }
   FileSeek(h, 0, SEEK_END);

   int batch = 4;
   g_btElapsedMs = GetTickCount() - g_btStartMs;
   datetime cutoff = g_btCutoff;
   for(int n = 0; n < batch && g_btStep < g_btTotal; ++n, ++g_btStep)
   {
      BtCombo c = g_btCombos[g_btStep];
      ErlSignal signals[];
      BuildSignals(c.htf, c.entryTf, c.swing, c.bias, c.entryModel, c.stopModel, c.targetModel, c.requireIrlTouch, c.requireEntrySweep, c.requireDisplacementFvg, cutoff, signals);
      SimStats st = CalculateStats(signals, c.target, c.hc, c.targetModel, c.entryTf);
      double resolved = st.wins + st.losses;
      double wr = resolved > 0 ? (double)st.wins / resolved * 100.0 : 0.0;
      double avg = st.total > 0 ? st.netR / st.total : 0.0;
      FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), _Symbol, TfLabel(c.htf), TfLabel(c.entryTf),
         IntegerToString(c.swing), EntryModelLabel(c.entryModel), StopModelLabel(c.stopModel), TargetModelLabel(c.targetModel),
         StrictnessLabel(c.requireIrlTouch, c.requireEntrySweep, c.requireDisplacementFvg),
         TargetLabel(c.target), HcLabel(c.hc), c.bias ? "ON" : "OFF", IntegerToString(g_btWeeks),
         IntegerToString(st.total), IntegerToString(st.wins), IntegerToString(st.losses), IntegerToString(st.open),
         DoubleToString(wr, 2), DoubleToString(st.netR, 2), DoubleToString(st.wonR, 2), DoubleToString(st.lostR, 2),
         DoubleToString(st.pf, 2), DoubleToString(avg, 3));
      g_btLastResult = TfLabel(c.htf) + " " + TfLabel(c.entryTf) + " SW" + IntegerToString(c.swing) + " "
         + EntryModelLabel(c.entryModel) + " " + StopModelLabel(c.stopModel) + " " + TargetModelLabel(c.targetModel)
         + " " + StrictnessLabel(c.requireIrlTouch, c.requireEntrySweep, c.requireDisplacementFvg)
         + " " + TargetLabel(c.target) + " " + HcLabel(c.hc) + " BIAS=" + (c.bias ? "ON" : "OFF")
         + " -> " + IntegerToString(st.wins) + "W/" + IntegerToString(st.losses) + "L Net=" + DoubleToString(st.netR, 2) + "R";
   }
   FileClose(h);
}

//=====================================================================
//  DASHBOARD
//=====================================================================
void DrawDashboard()
{
   if(IsTesterMode()) return;
   if(!InpShowDashboard)
   {
      DeleteByPrefix(PFX + "DASH_");
      return;
   }
   DeleteByPrefix(PFX + "DASH_");
   int x = InpDashboardX;
   int y = InpDashboardY;
   if(g_dashboardCollapsed)
   {
      RectObj("DASH_MIN_BG", x, y, 760, 34, C'15,20,31', C'90,178,255');
      LabelObj("DASH_MIN_TITLE", x + 14, y + 10,
         "ERL->IRL // " + (g_eaEnabled ? "EA ON" : "EA OFF") + " | " + _Symbol
         + " | " + TfLabel(g_htf) + "->" + TfLabel(g_entryTf)
         + " | " + EntryModelLabel(g_entryModel) + "/" + StopModelLabel(g_stopModel) + "/" + TargetModelLabel(g_targetModel),
         g_eaEnabled ? C'80,255,180' : C'255,95,140', 9);
      ButtonObj("BTN_DASH_TOGGLE", x + 674, y + 7, 72, 20, "EXPAND", C'38,101,176');
      return;
   }
   int W = 760;
   int H = 680;
   RectObj("DASH_BG", x, y, W, H, C'15,20,31', C'90,178,255');
   RectObj("DASH_TOP", x, y, W, 32, C'10,15,26', C'90,178,255');
   RectObj("DASH_STRIPE", x + 8, y + 7, W - 16, 3, C'90,178,255', C'90,178,255');
   LabelObj("DASH_TITLE", x + 14, y + 12, "ERL->IRL SWING MODEL // " + ERL_BUILD, C'225,232,242', 10);
   ButtonObj("BTN_DASH_TOGGLE", x + 674, y + 7, 72, 20, "HIDE", C'70,72,82');
   UpdateDashboard();
}

void UpdateDashboard()
{
   if(IsTesterMode()) return;
   if(!InpShowDashboard) return;
   if(g_dashboardCollapsed)
   {
      DrawDashboard();
      return;
   }
   int x = InpDashboardX;
   int y = InpDashboardY;
   color ac = C'90,178,255';
   color muted = C'145,160,180';
   color on = C'30,130,78';
   color off = C'70,72,82';
   int bh = 20;

   LabelObj("DASH_STATE", x + 14, y + 38,
      (g_eaEnabled ? "EA ON" : "EA OFF") + " | " + _Symbol + " | HTF " + TfLabel(g_htf)
      + " | ENTRY " + TfLabel(g_entryTf) + " | SW" + IntegerToString(g_swingLookback)
      + " | " + EntryModelLabel(g_entryModel) + "/" + StopModelLabel(g_stopModel) + "/" + TargetModelLabel(g_targetModel)
      + " | " + StrictnessLabel(g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg)
      + " | " + TargetLabel(g_target) + " | " + HcLabel(g_hc),
      g_eaEnabled ? C'80,255,180' : C'255,95,140', 8);

   int sec1 = y + 64;
   RectObj("DASH_SEC1", x + 8, sec1, 744, 172, C'24,31,45', C'60,110,170');
   LabelObj("DASH_SEC1_T", x + 16, sec1 + 7, "CONTROLS", ac, 9);
   int row = sec1 + 30;
   LabelObj("DASH_HTF_L", x + 16, row + 4, "HTF:", muted, 8);
   ButtonObj("BTN_HTF_H4", x + 66, row, 54, bh, "H4", g_htf == PERIOD_H4 ? on : off);
   ButtonObj("BTN_HTF_D1", x + 126, row, 54, bh, "D1", g_htf == PERIOD_D1 ? on : off);
   LabelObj("DASH_ETF_L", x + 205, row + 4, "ENTRY:", muted, 8);
   ButtonObj("BTN_ETF_M15", x + 266, row, 58, bh, "M15", g_entryTf == PERIOD_M15 ? on : off);
   ButtonObj("BTN_ETF_M30", x + 330, row, 58, bh, "M30", g_entryTf == PERIOD_M30 ? on : off);
   ButtonObj("BTN_ETF_H1", x + 394, row, 52, bh, "H1", g_entryTf == PERIOD_H1 ? on : off);
   ButtonObj("BTN_EA", x + 584, row, 88, bh, g_eaEnabled ? "EA: ON" : "EA: OFF", g_eaEnabled ? on : C'170,45,62');

   row += 28;
   LabelObj("DASH_SW_L", x + 16, row + 4, "SWING:", muted, 8);
   ButtonObj("BTN_SW_3", x + 76, row, 44, bh, "3", g_swingLookback == 3 ? on : off);
   ButtonObj("BTN_SW_5", x + 126, row, 44, bh, "5", g_swingLookback == 5 ? on : off);
   ButtonObj("BTN_SW_8", x + 176, row, 44, bh, "8", g_swingLookback == 8 ? on : off);
   LabelObj("DASH_TP_L", x + 246, row + 4, "TARGET:", muted, 8);
   ButtonObj("BTN_TP_1", x + 318, row, 52, bh, "TP1", g_target == ERL_RR_TP1 ? on : off);
   ButtonObj("BTN_TP_2", x + 374, row, 52, bh, "TP2", g_target == ERL_RR_TP2 ? on : off);
   ButtonObj("BTN_TP_3", x + 430, row, 52, bh, "TP3", g_target == ERL_RR_TP3 ? on : off);
   ButtonObj("BTN_TP_4", x + 486, row, 52, bh, "TP4", g_target == ERL_RR_TP4 ? on : off);
   ButtonObj("BTN_TP_5", x + 542, row, 52, bh, "TP5", g_target == ERL_RR_TP5 ? on : off);
   ButtonObj("BTN_TP_6", x + 598, row, 52, bh, "TP6", g_target == ERL_RR_TP6 ? on : off);
   ButtonObj("BTN_CLOSE", x + 660, row, 84, bh, "CLOSE ALL", C'170,45,62');

   row += 28;
   LabelObj("DASH_HC_L", x + 16, row + 4, "HC+BE:", muted, 8);
   ButtonObj("BTN_HC_OFF", x + 76, row, 52, bh, "OFF", g_hc == ERL_HC_OFF ? on : off);
   ButtonObj("BTN_HC_TP1", x + 132, row, 54, bh, "TP1", g_hc == ERL_HC_TP1 ? on : ((int)g_target + 1 > 1 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP2", x + 190, row, 54, bh, "TP2", g_hc == ERL_HC_TP2 ? on : ((int)g_target + 1 > 2 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP3", x + 248, row, 54, bh, "TP3", g_hc == ERL_HC_TP3 ? on : ((int)g_target + 1 > 3 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP4", x + 306, row, 54, bh, "TP4", g_hc == ERL_HC_TP4 ? on : ((int)g_target + 1 > 4 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP5", x + 364, row, 54, bh, "TP5", g_hc == ERL_HC_TP5 ? on : ((int)g_target + 1 > 5 ? off : C'35,37,44'));
   LabelObj("DASH_BIAS_L", x + 430, row + 4, "WEEKLY:", muted, 8);
   ButtonObj("BTN_BIAS", x + 490, row, 68, bh, g_weeklyBias ? "ON" : "OFF", g_weeklyBias ? on : off);
   ButtonObj("BTN_AUDIT", x + 660, row, 84, bh, g_auditRuntime ? "AUDIT ON" : "AUDIT OFF", g_auditRuntime ? C'120,88,25' : off);

   row += 28;
   LabelObj("DASH_EM_L", x + 16, row + 4, "ENTRY MODEL:", muted, 8);
   ButtonObj("BTN_ENTRY_PRO", x + 112, row, 62, bh, "PRO", g_entryModel == ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG ? on : off);
   ButtonObj("BTN_ENTRY_LEG", x + 180, row, 78, bh, "LEGACY", g_entryModel == ERL_ENTRY_LEGACY_HTF_FVG_TAP ? on : off);
   LabelObj("DASH_SM_L", x + 276, row + 4, "STOP:", muted, 8);
   ButtonObj("BTN_STOP_FVG1", x + 326, row, 62, bh, "FVG1", g_stopModel == ERL_STOP_FIRST_FVG_CANDLE ? on : off);
   ButtonObj("BTN_STOP_ZONE", x + 394, row, 62, bh, "ZONE", g_stopModel == ERL_STOP_FVG_BOUNDARY ? on : off);
   LabelObj("DASH_TM_L", x + 474, row + 4, "TARGET:", muted, 8);
   ButtonObj("BTN_TM_EXT", x + 538, row, 54, bh, "EXT", g_targetModel == ERL_TARGET_NEXT_EXTERNAL ? on : off);
   ButtonObj("BTN_TM_AUTO", x + 598, row, 58, bh, "AUTO", g_targetModel == ERL_TARGET_AUTO_STOP_SIZE ? on : off);
   ButtonObj("BTN_TM_FIXED", x + 662, row, 68, bh, "FIXED", g_targetModel == ERL_TARGET_FIXED_R ? on : off);

   row += 28;
   LabelObj("DASH_STRICT_L", x + 16, row + 4, "STRICT FILTERS:", muted, 8);
   ButtonObj("BTN_REQ_IRL", x + 130, row, 94, bh, g_requireIrlTouch ? "IRL: ON" : "IRL: OFF", g_requireIrlTouch ? on : off);
   ButtonObj("BTN_REQ_SWEEP", x + 232, row, 104, bh, g_requireEntrySweep ? "SWEEP: ON" : "SWEEP: OFF", g_requireEntrySweep ? on : off);
   ButtonObj("BTN_REQ_DISP", x + 344, row, 96, bh, g_requireDisplacementFvg ? "DISP: ON" : "DISP: OFF", g_requireDisplacementFvg ? on : off);
   LabelObj("DASH_STRICT_HINT", x + 456, row + 4, "OFF = more signals, less strict pro confirmation", C'255,204,82', 8);

   int sec2 = sec1 + 180;
   RectObj("DASH_SEC2", x + 8, sec2, 744, 112, C'24,31,45', C'60,110,170');
   LabelObj("DASH_SEC2_T", x + 16, sec2 + 7, "SIGNAL AUDIT", ac, 9);
   double resolved = g_hist.wins + g_hist.losses;
   double wr = resolved > 0.0 ? (double)g_hist.wins / resolved * 100.0 : 0.0;
   LabelObj("DASH_AUD1", x + 16, sec2 + 30,
      IntegerToString(g_histWeeks) + "W: " + IntegerToString(g_hist.total) + " sig | "
      + IntegerToString(g_hist.wins) + "W " + IntegerToString(g_hist.losses) + "L " + IntegerToString(g_hist.open)
      + "O | WR " + DoubleToString(wr, 1) + "% | Net " + DoubleToString(g_hist.netR, 2) + "R | $ "
      + (ApproxMoneyFromR(g_hist.netR) >= 0 ? "+" : "") + DoubleToString(ApproxMoneyFromR(g_hist.netR), 2),
      g_hist.netR >= 0 ? C'80,255,180' : C'255,95,140', 9);
   ButtonObj("BTN_AUD_2W", x + 520, sec2 + 28, 48, bh, "2W", g_histWeeks == 2 ? C'38,101,176' : off);
   ButtonObj("BTN_AUD_5W", x + 572, sec2 + 28, 48, bh, "5W", g_histWeeks == 5 ? C'38,101,176' : off);
   ButtonObj("BTN_AUD_10W", x + 624, sec2 + 28, 52, bh, "10W", g_histWeeks == 10 ? C'38,101,176' : off);
   ButtonObj("BTN_AUD_20W", x + 680, sec2 + 28, 52, bh, "20W", g_histWeeks == 20 ? C'38,101,176' : off);
   RectObj("DASH_WR_BG", x + 16, sec2 + 58, 420, 14, C'38,46,60', C'60,80,110');
   int fill = (int)MathRound(418.0 * MathMax(0.0, MathMin(100.0, wr)) / 100.0);
   if(fill > 2) RectObj("DASH_WR_FG", x + 17, sec2 + 59, fill, 12, wr >= 50 ? C'80,220,140' : C'255,95,140', wr >= 50 ? C'80,220,140' : C'255,95,140');
   LabelObj("DASH_AUD2", x + 16, sec2 + 80,
      "Won +" + DoubleToString(g_hist.wonR, 2) + "R | Lost -" + DoubleToString(g_hist.lostR, 2) + "R | Avg "
      + DoubleToString(g_hist.total > 0 ? g_hist.netR / g_hist.total : 0.0, 3) + "R/trade", muted, 8);

   int sec3 = sec2 + 120;
   RectObj("DASH_SEC3", x + 8, sec3, 744, 96, C'24,31,45', C'60,110,170');
   LabelObj("DASH_SEC3_T", x + 16, sec3 + 7, "EXECUTION", ac, 9);
   LabelObj("DASH_EX1", x + 16, sec3 + 30,
      "Status: " + g_lastStatus + " | Block: " + (g_lastBlock == "" ? "-" : g_lastBlock)
      + " | Spread " + DoubleToString(g_lastSpreadPts, 0) + " pts | Positions " + IntegerToString(OwnPositionCount()),
      g_lastBlock == "" ? C'80,255,180' : C'255,204,82', 8);
   LabelObj("DASH_EX2", x + 16, sec3 + 52,
      "Last: " + DirLabel(g_lastSignalDir) + " " + FmtTime(g_lastSignalTime)
      + " | Entry " + DoubleToString(g_lastEntry, _Digits) + " SL " + DoubleToString(g_lastSl, _Digits)
      + " TP " + DoubleToString(g_lastTp, _Digits), muted, 8);
   LabelObj("DASH_EX3", x + 16, sec3 + 74,
      "Risk: " + (InpAccountRiskEnabled ? "ON" : "OFF") + " " + DoubleToString(InpRiskPerTradePct, 2)
      + "% | SL% " + DoubleToString(g_slDistancePct, 0) + " | Magic " + IntegerToString((int)RuntimeMagic()), muted, 8);
   LabelObj("DASH_SL_L", x + 510, sec3 + 74, "SL%:", muted, 8);
   EditObj("EDIT_SL_PCT", x + 550, sec3 + 72, 56, bh, DoubleToString(g_slDistancePct, 0));
   ButtonObj("BTN_SL_APPLY", x + 612, sec3 + 72, 70, bh, "APPLY", C'38,101,176');

   int sec4 = sec3 + 104;
   RectObj("DASH_SEC4", x + 8, sec4, 744, 148, C'24,31,45', C'60,110,170');
   LabelObj("DASH_SEC4_T", x + 16, sec4 + 7, "BACKTEST ENGINE", ac, 9);
   int btY = sec4 + 30;
   LabelObj("DASH_BTW_L", x + 16, btY + 4, "Weeks:", muted, 8);
   EditObj("EDIT_BT_WEEKS", x + 76, btY, 42, bh, IntegerToString(g_btWeeks));
   ButtonObj("BTN_BT_RUN", x + 126, btY, 126, bh, g_btRunning ? "RUNNING..." : "RUN BACKTEST", g_btRunning ? C'80,80,80' : on);
   ButtonObj("BTN_BT_STOP", x + 260, btY, 66, bh, "STOP", g_btRunning ? C'170,45,62' : off);
   LabelObj("DASH_BT_COUNT", x + 338, btY + 4, IntegerToString(g_btTotal > 0 ? g_btTotal : 9072) + " combos", muted, 8);

   int optY = btY + 26;
   LabelObj("DASH_FILL_L", x + 16, optY + 4, "Fill:", muted, 8);
   ButtonObj("BTN_FILL_SIGNAL", x + 60, optY, 64, bh, "SIGNAL", g_btFillMode == BT_FILL_SIGNAL_CLOSE ? C'38,101,176' : off);
   ButtonObj("BTN_FILL_NEXT", x + 130, optY, 54, bh, "NEXT", g_btFillMode == BT_FILL_NEXT_BAR_OPEN ? C'38,101,176' : off);
   ButtonObj("BTN_FILL_CONS", x + 190, optY, 54, bh, "CONS", g_btFillMode == BT_FILL_CONSERVATIVE ? C'38,101,176' : off);
   LabelObj("DASH_SAME_L", x + 260, optY + 4, "Same:", muted, 8);
   ButtonObj("BTN_SAME_CONS", x + 308, optY, 54, bh, "CONS", g_btSameBarPolicy == BT_SAMEBAR_CONSERVATIVE ? C'38,101,176' : off);
   ButtonObj("BTN_SAME_NEAR", x + 368, optY, 54, bh, "NEAR", g_btSameBarPolicy == BT_SAMEBAR_NEAREST_OPEN ? C'38,101,176' : off);
   ButtonObj("BTN_SAME_TP", x + 428, optY, 58, bh, "TP1ST", g_btSameBarPolicy == BT_SAMEBAR_TP_FIRST ? C'38,101,176' : off);
   ButtonObj("BTN_SAME_SL", x + 492, optY, 58, bh, "SL1ST", g_btSameBarPolicy == BT_SAMEBAR_SL_FIRST ? C'38,101,176' : off);

   int costY = optY + 26;
   LabelObj("DASH_COST_L1", x + 16, costY + 4, "Spr:", muted, 8);
   EditObj("EDIT_BT_SPREAD", x + 48, costY, 48, bh, DoubleToString(g_btSpreadPts, 1));
   LabelObj("DASH_COST_L2", x + 104, costY + 4, "Slip:", muted, 8);
   EditObj("EDIT_BT_SLIP", x + 140, costY, 48, bh, DoubleToString(g_btSlippagePts, 1));
   LabelObj("DASH_COST_L3", x + 196, costY + 4, "Comm/Lot:", muted, 8);
   EditObj("EDIT_BT_COMM", x + 270, costY, 64, bh, DoubleToString(g_btCommissionPerLot, 2));
   LabelObj("DASH_COST_HINT", x + 344, costY + 4, "0 spread = live spread", muted, 8);

   int pbY = costY + 28;
   RectObj("DASH_BTPB_BG", x + 16, pbY, 640, 14, C'38,46,60', C'60,80,110');
   double pct = g_btTotal > 0 ? (double)g_btStep / (double)g_btTotal : 0.0;
   int pbFill = (int)MathRound(638.0 * MathMax(0.0, MathMin(1.0, pct)));
   if(pbFill > 2) RectObj("DASH_BTPB_FG", x + 17, pbY + 1, pbFill, 12, C'60,200,120', C'60,200,120');
   LabelObj("DASH_BTPB_TXT", x + 22, pbY - 1,
      IntegerToString(g_btStep) + "/" + IntegerToString(g_btTotal) + " " + IntegerToString((int)(pct * 100.0)) + "% | " + g_btLastResult,
      clrWhite, 8);
}

//=====================================================================
//  RISK BREACH AND EVENTS
//=====================================================================
void EnforceRiskBreach()
{
   if(!InpAccountRiskEnabled || !InpLiquidateOnBreach) return;
   if(InpDailyLossLimitPct <= 0.0 && InpMaxDrawdownPct <= 0.0) return;
   double base = BaseCapital();
   if(base <= 0.0) return;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equityPeak <= 0.0) g_equityPeak = equity;
   g_equityPeak = MathMax(g_equityPeak, equity);
   double dailyPnl = DailyClosedPnl();
   double dd = g_equityPeak - equity;
   bool breach = false;
   string why = "";
   if(InpDailyLossLimitPct > 0.0 && dailyPnl <= -base * InpDailyLossLimitPct / 100.0)
   {
      breach = true;
      why = "daily_loss_breach";
   }
   if(InpMaxDrawdownPct > 0.0 && dd >= base * InpMaxDrawdownPct / 100.0)
   {
      breach = true;
      why = "max_drawdown_breach";
   }
   if(breach)
   {
      AuditWrite("risk_liquidation", why, 0, 0, 0, 0, 0, "closing own positions");
      CloseOwnPositions(0);
   }
}

void RefreshAfterConfigChange()
{
   SanitizeHalfMode();
   g_lastLiveScanBar = 0;
   RecalculateHistoricalStats();
   if(IsTesterMode()) return;
   DrawHistoricalSignals();
   UpdateDashboard();
   ChartRedraw(0);
}

bool Clicked(const string sparam, string id)
{
   return sparam == PFX + id;
}

//=====================================================================
//  MT5 EVENT HANDLERS
//=====================================================================
int OnInit()
{
   ErlTesterAudit_Init();
   PFX = ERL_PREFIX + IntegerToString((int)ChartID()) + "_";
   g_eaEnabled = InpEaEnabled;
   g_htf = InpDefaultHtf;
   g_entryTf = InpDefaultEntryTf;
   g_swingLookback = InpDefaultSwingLookback;
   g_target = InpDefaultTarget;
   g_hc = InpDefaultHalfBe;
   g_weeklyBias = InpDefaultWeeklyBias;
   g_entryModel = InpDefaultEntryModel;
   g_stopModel = InpDefaultStopModel;
   g_targetModel = InpDefaultTargetModel;
   g_requireIrlTouch = InpDefaultRequireIrlTouch;
   g_requireEntrySweep = InpDefaultRequireEntrySweep;
   g_requireDisplacementFvg = InpDefaultRequireDisplacementFvg;
   g_slDistancePct = ClampSlDistancePct(InpSlDistancePct);
   g_histWeeks = ClampHistWeeks(InpHistoricalWeeks > 0 ? InpHistoricalWeeks : (int)MathCeil((double)MathMax(1, InpHistoricalDays) / 7.0));
   g_btWeeks = InpBacktestWeeks;
   g_btFillMode = InpBacktestFillMode;
   g_btSameBarPolicy = InpBacktestSameBarPolicy;
   g_btSpreadPts = InpBacktestSpreadPts > 0.0 ? InpBacktestSpreadPts : (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   g_btSlippagePts = InpBacktestSlippagePts;
   g_btCommissionPerLot = InpBacktestCommissionPerLot;
   g_auditRuntime = (InpAuditTradeCsv || InpAuditPositionProbe);
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   SanitizeHalfMode();
   BuildCombos();
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(!IsTesterMode())
   {
      RecalculateHistoricalStats();
      DrawDashboard();
      DrawHistoricalSignals();
      DrawLiveLevelsForPosition();
   }
   if(!IsTesterMode()) EventSetTimer(1);
   AuditWrite("ea_init", "init", 0, 0, 0, 0, 0,
      "build=" + (string)ERL_BUILD + " htf=" + TfLabel(g_htf) + " entry_tf=" + TfLabel(g_entryTf)
      + " swing=" + IntegerToString(g_swingLookback) + " target=" + TargetLabel(g_target) + " hc=" + HcLabel(g_hc)
      + " entry_model=" + EntryModelLabel(g_entryModel) + " stop_model=" + StopModelLabel(g_stopModel)
      + " target_model=" + TargetModelLabel(g_targetModel)
      + " strictness=" + StrictnessLabel(g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg));
   Print("ERL_IRL init build=", ERL_BUILD, " symbol=", _Symbol, " htf=", TfLabel(g_htf), " entry=", TfLabel(g_entryTf));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteByPrefix(PFX);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   ErlTesterAudit_WriteDeal(trans, request, result);
}

void OnTick()
{
   g_lastSpreadPts = CurrentSpreadPoints();
   TryOpenLatestSignal();
   ManagePositions();
   if(!IsTesterMode())DrawLiveLevelsForPosition();
}

void OnTimer()
{
   if(IsTesterMode()) return;
   g_lastSpreadPts = CurrentSpreadPoints();
   EnforceRiskBreach();
   TryOpenLatestSignal();
   ManagePositions();
   ProbePositions();
   ScanClosedHistory();
   if(!IsValidationTester())
   {
      BacktestStep();
      UpdateDashboard();
      DrawLiveLevelsForPosition();
      ChartRedraw(0);
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT) return;

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == PFX + "EDIT_BT_WEEKS")
      {
         int v = (int)StringToInteger(ObjectGetString(0, sparam, OBJPROP_TEXT));
         if(v > 0 && v <= 52) g_btWeeks = v;
         UpdateDashboard();
      }
      if(sparam == PFX + "EDIT_BT_SPREAD")
      {
         g_btSpreadPts = MathMax(0.0, StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT)));
         UpdateDashboard();
      }
      if(sparam == PFX + "EDIT_BT_SLIP")
      {
         g_btSlippagePts = MathMax(0.0, StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT)));
         UpdateDashboard();
      }
      if(sparam == PFX + "EDIT_BT_COMM")
      {
         g_btCommissionPerLot = MathMax(0.0, StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT)));
         UpdateDashboard();
      }
      if(sparam == PFX + "EDIT_SL_PCT")
      {
         g_slDistancePct = ClampSlDistancePct(StringToDouble(ObjectGetString(0, sparam, OBJPROP_TEXT)));
         RefreshAfterConfigChange();
      }
      return;
   }

   if(Clicked(sparam, "BTN_DASH_TOGGLE"))
   {
      g_dashboardCollapsed = !g_dashboardCollapsed;
      DrawDashboard();
      ChartRedraw(0);
      return;
   }

   if(Clicked(sparam, "BTN_HTF_H4")) { g_htf = PERIOD_H4; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HTF_D1")) { g_htf = PERIOD_D1; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ETF_M15")) { g_entryTf = PERIOD_M15; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ETF_M30")) { g_entryTf = PERIOD_M30; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ETF_H1")) { g_entryTf = PERIOD_H1; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SW_3")) { g_swingLookback = 3; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SW_5")) { g_swingLookback = 5; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SW_8")) { g_swingLookback = 8; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TP_1")) { g_target = ERL_RR_TP1; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TP_2")) { g_target = ERL_RR_TP2; SanitizeHalfMode(); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TP_3")) { g_target = ERL_RR_TP3; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TP_4")) { g_target = ERL_RR_TP4; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TP_5")) { g_target = ERL_RR_TP5; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TP_6")) { g_target = ERL_RR_TP6; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HC_OFF")) { g_hc = ERL_HC_OFF; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HC_TP1")) { if((int)g_target + 1 > 1) g_hc = ERL_HC_TP1; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HC_TP2")) { if((int)g_target + 1 > 2) g_hc = ERL_HC_TP2; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HC_TP3")) { if((int)g_target + 1 > 3) g_hc = ERL_HC_TP3; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HC_TP4")) { if((int)g_target + 1 > 4) g_hc = ERL_HC_TP4; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HC_TP5")) { if((int)g_target + 1 > 5) g_hc = ERL_HC_TP5; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_AUD_2W")) { g_histWeeks = 2; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_AUD_5W")) { g_histWeeks = 5; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_AUD_10W")) { g_histWeeks = 10; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_AUD_20W")) { g_histWeeks = 20; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SL_APPLY")) { g_slDistancePct = ClampSlDistancePct(StringToDouble(ObjectGetString(0, PFX + "EDIT_SL_PCT", OBJPROP_TEXT))); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_BIAS")) { g_weeklyBias = !g_weeklyBias; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ENTRY_PRO")) { g_entryModel = ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ENTRY_LEG")) { g_entryModel = ERL_ENTRY_LEGACY_HTF_FVG_TAP; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_STOP_FVG1")) { g_stopModel = ERL_STOP_FIRST_FVG_CANDLE; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_STOP_ZONE")) { g_stopModel = ERL_STOP_FVG_BOUNDARY; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TM_EXT")) { g_targetModel = ERL_TARGET_NEXT_EXTERNAL; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TM_AUTO")) { g_targetModel = ERL_TARGET_AUTO_STOP_SIZE; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TM_FIXED")) { g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_REQ_IRL")) { g_requireIrlTouch = !g_requireIrlTouch; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_REQ_SWEEP")) { g_requireEntrySweep = !g_requireEntrySweep; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_REQ_DISP")) { g_requireDisplacementFvg = !g_requireDisplacementFvg; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_EA")) { g_eaEnabled = !g_eaEnabled; UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_CLOSE")) { CloseOwnPositions(0); UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_AUDIT")) { g_auditRuntime = !g_auditRuntime; Print("ERL_IRL audit logging ", g_auditRuntime ? "enabled" : "disabled"); UpdateDashboard(); ChartRedraw(0); return; }

   if(Clicked(sparam, "BTN_FILL_SIGNAL")) { g_btFillMode = BT_FILL_SIGNAL_CLOSE; UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_FILL_NEXT")) { g_btFillMode = BT_FILL_NEXT_BAR_OPEN; UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_FILL_CONS")) { g_btFillMode = BT_FILL_CONSERVATIVE; UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_SAME_CONS")) { g_btSameBarPolicy = BT_SAMEBAR_CONSERVATIVE; UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_SAME_NEAR")) { g_btSameBarPolicy = BT_SAMEBAR_NEAREST_OPEN; UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_SAME_TP")) { g_btSameBarPolicy = BT_SAMEBAR_TP_FIRST; UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_SAME_SL")) { g_btSameBarPolicy = BT_SAMEBAR_SL_FIRST; UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_BT_RUN")) { StartBacktest(); UpdateDashboard(); return; }
   if(Clicked(sparam, "BTN_BT_STOP")) { StopBacktest(); UpdateDashboard(); return; }
}
