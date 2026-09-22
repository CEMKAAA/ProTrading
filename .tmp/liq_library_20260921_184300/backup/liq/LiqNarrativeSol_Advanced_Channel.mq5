//+------------------------------------------------------------------+
//| Liquidity Narrative SMT/FVG Model EA                       |
//| Session liquidity draw -> SMT/stop-hunt -> delivery shift -> FVG tap.           |
//| Dashboard, historical audit, brute-force backtest, risk engine.   |
//+------------------------------------------------------------------+
#property strict
#property version "1.13"

#include <Trade/Trade.mqh>
#include "LiqNarrativeSol_RegimeV3.mqh"
#include "LiqNarrativeMacroRegime.mqh"
#include "TradeDayCalendarPublisher.mqh"

#define LN_BUILD "2026-08-15.sol-advanced-hk50-audit-v2-channel"
#define LN_PREFIX "LIQNARRSOL_"
#define LN_PERIOD_H90 ((ENUM_TIMEFRAMES)90)
#define LN_H90_SECONDS 5400

//=====================================================================
//  ENUMS
//=====================================================================
#include "LiqROptions.mqh"

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
   ERL_TARGET_AUTO_STOP_SIZE = 2,
   ERL_TARGET_OPPOSITE_SIGNAL = 3
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
input long            InpMagic                  = 31061503;
input int             InpDeviationPoints        = 30;
input bool            InpCloseOnReverse         = true;
input bool            InpBlockSameDirection     = true;
input bool            InpAllowDuplicateEntriesDefault = true;
input bool            InpInvertModeDefault      = false;

input ENUM_TIMEFRAMES InpDefaultHtf             = PERIOD_H2;
input ENUM_TIMEFRAMES InpDefaultEntryTf         = PERIOD_H1;
input int             InpDefaultSwingLookback   = 5;
input ERL_RR_MODE     InpDefaultTarget          = ERL_RR_TP4;
input ERL_HC_MODE     InpDefaultHalfBe          = ERL_HC_OFF;
input bool            InpDefaultWeeklyBias      = false;
input ERL_ENTRY_MODEL InpDefaultEntryModel      = ERL_ENTRY_LEGACY_HTF_FVG_TAP;
input ERL_STOP_MODEL  InpDefaultStopModel       = ERL_STOP_FIRST_FVG_CANDLE;
input ERL_TARGET_MODEL InpDefaultTargetModel    = ERL_TARGET_FIXED_R;
input bool            InpDefaultRequireIrlTouch = false;
input bool            InpDefaultRequireEntrySweep = false;
input bool            InpDefaultRequireDisplacementFvg = false;
input bool            InpDefaultRequireAsiaLiquidityDraw = false;
input bool            InpDefaultUseAsiaLiquidityTarget = true;
input bool            InpDefaultRequireSmt = false;

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
input bool            InpPipSlModeDefault       = true;
input double          InpPipSlPips              = 4000.0;
input double          InpSmallStopThresholdPts  = 30.0;
input ERL_RR_MODE     InpSmallStopTarget        = ERL_RR_TP4;
input ERL_RR_MODE     InpLargeStopTarget        = ERL_RR_TP2;
input int             InpAsiaStartHourGmt       = 0;
input int             InpAsiaEndHourGmt         = 6;
input bool            InpSolSessionRouterEnabled = true;
input int             InpSolBrokerUtcOffsetMin  = 0;
input int             InpSolContinuationStartGmt = 14;
input int             InpSolContinuationEndGmt  = 23;
input double          InpSolContinuationQualityLow = 2.17;
input double          InpSolContinuationQualityHigh = 3.14;
input bool            InpSolRegimeFilterDefault = false;
input bool            InpSolRegimeRf01Blocked = true; // RLV mature stable continuation
input bool            InpSolRegimeRf02Blocked = true; // TLV neutral rotation up
input bool            InpSolRegimeRf03Blocked = true; // aligned impulse down continuation
input bool            InpSolRegimeRf04Blocked = true; // RHV developing
input bool            InpSolRegimeRf05Blocked = true; // RLV deep rebound normal
input bool            InpSolRegimeRf06Blocked = true; // RLV shallow rebound
input bool            InpSolRegimeRf07Blocked = true; // aligned fresh stable
input bool            InpSolRegimeRf08Blocked = true; // shallow pullback mature
input bool            InpSolRegimeRf09Blocked = true; // RHV aligned impulse
input bool            InpSolRegimeRf10Blocked = true; // RLV compressed down reversal
input bool            InpSolRegimeRf11Blocked = true; // impulse normal reversal
input bool            InpSolRegimeRf12Blocked = true; // shallow pullback normal
input string          InpSmtSymbol              = "US500m";
input int             InpSmtLookbackBars        = 8;
input int             InpHistoricalDays         = 14;
input int             InpHistoricalWeeks        = 2;
input bool            InpDrawHistoricalSignals  = true;
input bool            InpDrawFvgZones           = true;
input bool            InpDrawLiveLevels         = true;

input bool            InpFileBridgeEnabled      = false;
input bool            InpFileBridgeOnlyMode     = false;
input bool            InpNativeTradeWithBridgeOnlyDefault = false; // ML shadow mode: when cTrader bridge-only is enabled, also open/manage native MT5 trades.
input bool            InpFileBridgeUseCommonFiles = true;
input string          InpFileBridgeLatestFile   = "LiqNarrativeSolAdvancedBridge_Latest.csv";
input string          InpFileBridgeAuditPrefix  = "LiqNarrativeSolAdvancedBridge_Audit_";
input int             InpBridgeChannel          = 1;

input bool            InpShowDashboard          = true;
input int             InpDashboardX             = 10;
input int             InpDashboardY             = 18;

input bool            InpAccountRiskEnabled     = true;
input bool            InpFtmoModeDefault        = false;
input bool            InpRiskLotOnlyModeDefault = false;
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
input bool            InpValidationInternalAudit = false;
input int             InpValidationInternalAuditWeeks = 52;
input bool            InpValidationInternalAuditRows = false;

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
   datetime confirmedTime;
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
   double   quality;
   datetime invalidatedTime;
};

struct ErlSignal
{
   bool     valid;
   int      dir;
   datetime htfTime;
   datetime entryTime;       // setup bar open time
   datetime availableTime;   // first time the closed-bar setup was knowable live
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
   bool     invertedGeometry;
   double   targetOverride;
   string   reason;
   string   id;
};

struct BridgePendingEvent
{
   string   eventId;
   string   dir;
   double   entry;
   double   sl;
   double   tp;
   string   source;
   double   halfTrigger;
   string   halfLabel;
   datetime signalTime;
   datetime nextRetryLocal;
   int      attempts;
};

struct SimStats
{
   int      total;
   int      wins;
   int      losses;
   int      open;
   int      invalid;
   double   wonR;
   double   lostR;
   double   netR;
   double   pf;
};

struct SimCacheEntry
{
   string   key;
   double   r;
   bool     closed;
   bool     won;
   bool     valid;
   int      traceDir;
   double   traceEntry,traceSl,traceTp,traceHalf;
   datetime traceExitTime;
   string   traceExitReason;
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
   bool     requireAsiaLiquidityDraw;
   bool     useAsiaLiquidityTarget;
   bool     requireSmt;
};

//=====================================================================
//  GLOBAL STATE
//=====================================================================
CTrade trade;
string PFX = LN_PREFIX;
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
bool             g_requireAsiaLiquidityDraw = true;
bool             g_useAsiaLiquidityTarget = true;
bool             g_requireSmt = false;
bool             g_solRegimeFilterEnabled = false;
int              g_solRegimeFilterRejected = 0;
int              g_solRegimeFilterUnclassified = 0;
#define SOL_ADV_RF_COUNT 12
bool             g_solRegimeRuleBlocked[SOL_ADV_RF_COUNT];
int              g_solRegimeRuleWins[SOL_ADV_RF_COUNT];
int              g_solRegimeRuleLosses[SOL_ADV_RF_COUNT];
bool             g_auditRuntime = false;
bool             g_ftmoMode = false;
bool             g_riskLotOnlyMode = false;
bool             g_dashboardCollapsed = false;

SimStats         g_hist;
ErlSignal        g_histSignals[];
ErlSignal        g_histRawCache[];
string           g_histRawCacheSignature = "";
int              g_histRawCacheWeeks = 0;
double           g_histSignalR[];
bool             g_histSignalClosed[];
bool             g_histSignalWon[];
bool             g_histSignalValid[];
string           g_histSignalInvalidReason[];
int              g_histSignalExecDir[];
double           g_histSignalExecEntry[];
double           g_histSignalExecSl[];
double           g_histSignalExecTp[];
double           g_histSignalExecHalf[];
datetime         g_histSignalExitTime[];
string           g_histSignalExitReason[];
SimCacheEntry    g_simCache[];
MqlRates         g_simRates[];
ENUM_TIMEFRAMES  g_simRatesTf = PERIOD_CURRENT;
datetime         g_simRatesLatestBar = 0;
datetime         g_simRatesOldestBar = 0;
bool             g_configRefreshPending = false;
bool             g_configRefreshRebuildSignals = false;
datetime         g_configRefreshDue = 0;
string           g_liveLevelsSignature = "";
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
string           g_lastBridgeStatus = "BRIDGE OFF";
BridgePendingEvent g_bridgePending[];
bool             g_fileBridgeEnabled = false;
int              g_bridgeChannel = 1;
bool             g_fileBridgeOnlyMode = false;
bool             g_nativeTradeWithBridgeOnly = false;
bool             g_allowDuplicateEntries = false;
bool             g_invertMode = false;
double           g_riskPerTradePct = 1.0;

datetime         g_lastAuditProbe = 0;
string           g_lastProbeHash = "";
datetime         g_lastHistoryScan = 0;
ulong            g_lastHistoryTicket = 0;
double           g_equityPeak = 0.0;
datetime         g_lastLiveScanBar = 0;
datetime         g_lastLiveScanAttempt = 0;
datetime         g_lastHistLifecycleRefresh = 0;
string           g_lastSimInvalidReason = "";
int              g_lastSimExecDir = 0;
double           g_lastSimExecEntry = 0.0;
double           g_lastSimExecSl = 0.0;
double           g_lastSimExecTp = 0.0;
double           g_lastSimExecHalf = 0.0;
datetime         g_lastSimExitTime = 0;
string           g_lastSimExitReason = "";

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
double           g_slBufferAtrPct = 10.0;
bool             g_pipSlMode = false;
double           g_pipSlPips = 100.0;
int              g_histWeeks = 2;
bool             g_histAuditRunning = false;
double           g_histAuditProgressPct = 0.0;
string           g_histAuditStage = "READY";
uint             g_histAuditLastUiMs = 0;
long             DASH_Z = 1000000;

//=====================================================================
//  BASIC UTILITY
//=====================================================================
string TfLabel(ENUM_TIMEFRAMES tf)
{
   if(tf == LN_PERIOD_H90) return "H1.5";
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
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

int EffectiveTradeDir(int sourceDir)
{
   return g_invertMode ? -sourceDir : sourceDir;
}

string RuntimeInvertLabel()
{
   return g_invertMode ? "FULL INV ON" : "FULL INV OFF";
}

string RuntimeInvertKey()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   return "LIQN_SOL_ADV_INV|" + IntegerToString((int)login)
      + "|" + IntegerToString((int)ChartID())
      + "|" + (InpInvertModeDefault ? "1" : "0");
}

void LoadRuntimeInvertMode()
{
   g_invertMode = InpInvertModeDefault;
   string key = RuntimeInvertKey();
   if(GlobalVariableCheck(key))
      g_invertMode = GlobalVariableGet(key) > 0.5;
   if(g_invertMode && g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL)
      g_invertMode = false;
}

bool SetRuntimeInvertMode(bool enabled)
{
   if(enabled && g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL) return false;
   if(GlobalVariableSet(RuntimeInvertKey(), enabled ? 1.0 : 0.0) <= 0.0) return false;
   g_invertMode = enabled;
   return true;
}

string TargetLabel(ERL_RR_MODE rr)
{
   if((int)rr>=101) return DoubleToString(TargetR(rr),2)+"R";
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
   if(model == ERL_TARGET_OPPOSITE_SIGNAL) return "REV";
   return "FIXED";
}

string StrictnessLabel(bool irlTouch, bool entrySweep, bool displacementFvg)
{
   return "IRL" + (irlTouch ? "1" : "0") + "-SWP" + (entrySweep ? "1" : "0") + "-DSP" + (displacementFvg ? "1" : "0");
}

string NarrativeLabel(bool asiaDraw, bool asiaTarget, bool smt)
{
   return "ASIA" + (asiaDraw ? "1" : "0") + "-TGT" + (asiaTarget ? "1" : "0") + "-SMT" + (smt ? "1" : "0");
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
   if((int)rr>=101 && (int)rr<=200) return ((int)rr-100)*0.05;
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

double ClampSlBufferAtrPct(double pct)
{
   return MathMax(0.0, MathMin(200.0, pct));
}

double ApplySlDistancePct(int dir, double entry, double rawSl)
{
   double dist = MathAbs(entry - rawSl) * ClampSlDistancePct(g_slDistancePct) / 100.0;
   if(dist <= 0.0) return rawSl;
   return NormTradePrice(dir > 0 ? entry - dist : entry + dist);
}

double ClampPipSlPips(double pips)
{
   return MathMax(0.0, MathMin(1000000.0, pips));
}

double PipSize()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = TickSize();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
}

double ApplyRuntimeSlDistance(int dir, double entry, double rawSl)
{
   if(g_pipSlMode)
   {
      double dist = ClampPipSlPips(g_pipSlPips) * PipSize();
      if(dist > TickSize() * 0.5)
         return NormTradePrice(dir > 0 ? entry - dist : entry + dist);
   }
   return ApplySlDistancePct(dir, entry, rawSl);
}
double DirectionalStopGuard(int dir, double entry, double rawSl, double fallbackLow, double fallbackHigh, double buffer, double atr)
{
   double tick = TickSize();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = tick;
   double minDist = MathMax(tick * 10.0, atr * 0.05);
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopLevel > 0) minDist = MathMax(minDist, stopLevel * point);

   double sl = rawSl;
   bool validSide = dir > 0 ? sl < entry - tick : sl > entry + tick;
   if(!validSide)
      sl = dir > 0 ? fallbackLow - buffer : fallbackHigh + buffer;

   sl = ApplyRuntimeSlDistance(dir, entry, sl);

   validSide = dir > 0 ? sl < entry - tick : sl > entry + tick;
   if(!validSide)
      sl = dir > 0 ? entry - minDist : entry + minDist;
   return NormTradePrice(sl);
}

double ClampRiskPerTradePct(double pct) { return MathMax(0.0, MathMin(10.0, pct)); }
bool ManagedRiskMode() { return g_ftmoMode || g_riskLotOnlyMode; }
string RuntimeRiskModeLabel() { if(g_ftmoMode) return "FTMO"; if(g_riskLotOnlyMode) return "RISKLOT"; return "NORMAL"; }
bool RiskEnabled() { return InpAccountRiskEnabled || ManagedRiskMode(); }
double RiskPerTradePct()
{
   double pct = ClampRiskPerTradePct(g_riskPerTradePct);
   if(g_ftmoMode) return MathMin(1.0, pct);
   return pct;
}
double MaxPortfolioRiskPct() { return g_ftmoMode ? 4.0 : InpMaxPortfolioRiskPct; }
double DailyLossLimitPct() { return g_ftmoMode ? 5.0 : InpDailyLossLimitPct; }
double MaxDrawdownPct() { return g_ftmoMode ? 10.0 : InpMaxDrawdownPct; }

double ApproxMoneyFromR(double r)
{
   double base = InpInitialBalanceOverride > 0.0 ? InpInitialBalanceOverride : MathMax(0.01, AccountInfoDouble(ACCOUNT_BALANCE));
   return r * base * MathMax(0.0, RiskPerTradePct()) / 100.0;
}

int ClampHistWeeks(int weeks)
{
   if(weeks <= 2) return 2;
   if(weeks <= 5) return 5;
   if(weeks <= 10) return 10;
   if(weeks <= 20) return 20;
   if(weeks <= 52) return 52;
   return MathMin(520, weeks);
}

string HistWindowLabel()
{
   int weeks = ClampHistWeeks(g_histWeeks);
   if(weeks == 52) return "1Y";
   if(weeks > 52 && weeks % 52 == 0) return IntegerToString(weeks / 52) + "Y";
   return IntegerToString(weeks) + "W";
}

int HistDays()
{
   return ClampHistWeeks(g_histWeeks) * 7;
}

void UpdateHistoricalAuditProgressUi()
{
   if(IsTesterMode() || !InpShowDashboard || g_dashboardCollapsed) return;
   if(ObjectFind(0, PFX + "DASH_BG") < 0) return;

   int x = InpDashboardX;
   int y = InpDashboardY;
   int sec1 = y + 164;
   int sec2 = sec1 + 236;
   double pct = MathMax(0.0, MathMin(100.0, g_histAuditProgressPct));
   int fill = (int)MathRound(638.0 * pct / 100.0);

   RectObj("DASH_WR_BG", x + 16, sec2 + 82, 640, 14, C'38,46,60', C'60,80,110');
   if(fill > 2)
      RectObj("DASH_WR_FG", x + 17, sec2 + 83, fill, 12, C'38,140,220', C'38,140,220');
   else
      ObjectDelete(0, PFX + "DASH_WR_FG");
   LabelObj("DASH_AUD_PROGRESS", x + 664, sec2 + 82,
      g_histAuditStage + " " + DoubleToString(pct, 1) + "%", C'90,178,255', 7);
}

void SetHistoricalAuditProgress(string stage, double pct, bool force = false)
{
   if(!g_histAuditRunning || IsTesterMode()) return;
   g_histAuditStage = stage;
   g_histAuditProgressPct = MathMax(0.0, MathMin(100.0, pct));
   uint now = GetTickCount();
   if(!force && now - g_histAuditLastUiMs < 125) return;
   g_histAuditLastUiMs = now;
   if(ObjectFind(0, PFX + "DASH_BG") >= 0)
   {
      // Historical scans can emit thousands of progress updates. Updating only
      // the three progress objects keeps MT5's chart-object queue responsive.
      UpdateHistoricalAuditProgressUi();
      ChartRedraw(0);
   }
}

void BeginHistoricalAuditProgress()
{
   g_histAuditRunning = !IsTesterMode();
   g_histAuditProgressPct = 0.0;
   g_histAuditStage = "LOAD";
   g_histAuditLastUiMs = 0;
   SetHistoricalAuditProgress("LOAD", 1.0, true);
}

void EndHistoricalAuditProgress()
{
   SetHistoricalAuditProgress("DONE", 100.0, true);
   g_histAuditRunning = false;
   g_histAuditStage = "READY";
   if(!IsTesterMode() && InpShowDashboard)
   {
      // Rebuild once after the synchronous audit so every control is restored
      // even if the terminal deferred object paints while the scan was running.
      DrawDashboard();
      ChartRedraw(0);
   }
}

string HistRawSignature()
{
   return _Symbol + "|" + TfLabel(g_htf) + "|" + TfLabel(g_entryTf)
      + "|SW" + IntegerToString(g_swingLookback)
      + "|BIAS" + (g_weeklyBias ? "1" : "0")
      + "|" + EntryModelLabel(g_entryModel)
      + "|" + StopModelLabel(g_stopModel)
      + "|" + StrictnessLabel(g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg)
      + "|" + NarrativeLabel(g_requireAsiaLiquidityDraw, g_useAsiaLiquidityTarget, g_requireSmt)
      + "|ASIA" + IntegerToString(InpAsiaStartHourGmt) + "-" + IntegerToString(InpAsiaEndHourGmt)
      + "|SMT" + InpSmtSymbol + "-" + IntegerToString(InpSmtLookbackBars)
      + "|SLPCT" + DoubleToString(g_slDistancePct, 2)
      + "|PIPSL" + (g_pipSlMode ? "1" : "0")
      + "|PIPS" + DoubleToString(g_pipSlPips, 2)
      + "|ATRBUF" + DoubleToString(g_slBufferAtrPct, 2)
      + "|" + SolModelLabel();
}

string SimCacheKey(const ErlSignal &sig, ERL_RR_MODE target, ERL_HC_MODE hc, ERL_TARGET_MODEL targetModel, ENUM_TIMEFRAMES entryTf, datetime maxTime)
{
   return sig.id
      + "|ENTRY" + DoubleToString(sig.entry, _Digits)
      + "|SL" + DoubleToString(sig.sl, _Digits)
      + "|EXT" + DoubleToString(sig.externalTarget, _Digits)
      + "|TP" + IntegerToString((int)target)
      + "|HC" + IntegerToString((int)hc)
      + "|TM" + IntegerToString((int)targetModel)
      + "|ETF" + TfLabel(entryTf)
      + "|MX" + IntegerToString((int)maxTime)
      + "|F" + IntegerToString((int)g_btFillMode)
      + "|SB" + IntegerToString((int)g_btSameBarPolicy)
      + "|TR" + (InpBacktestUseTickReplay ? "1" : "0")
      + "|SP" + DoubleToString(g_btSpreadPts, 2)
      + "|SLIP" + DoubleToString(g_btSlippagePts, 2)
      + "|COMM" + DoubleToString(g_btCommissionPerLot, 4)
      + "|INV" + (g_invertMode ? "1" : "0");
}

bool SimCacheGet(const string key, double &r, bool &closed, bool &won, bool &valid)
{
   for(int i = 0; i < ArraySize(g_simCache); ++i)
   {
      if(g_simCache[i].key == key)
      {
         r = g_simCache[i].r;
         closed = g_simCache[i].closed;
         won = g_simCache[i].won;
         valid = g_simCache[i].valid;
         g_lastSimInvalidReason = "";
         g_lastSimExecDir = g_simCache[i].traceDir;
         g_lastSimExecEntry = g_simCache[i].traceEntry;
         g_lastSimExecSl = g_simCache[i].traceSl;
         g_lastSimExecTp = g_simCache[i].traceTp;
         g_lastSimExecHalf = g_simCache[i].traceHalf;
         g_lastSimExitTime = g_simCache[i].traceExitTime;
         g_lastSimExitReason = g_simCache[i].traceExitReason;
         return true;
      }
   }
   return false;
}

void SimCachePut(const string key, double r, bool closed, bool won, bool valid)
{
   int n = ArraySize(g_simCache);
   ArrayResize(g_simCache, n + 1);
   g_simCache[n].key = key;
   g_simCache[n].r = r;
   g_simCache[n].closed = closed;
   g_simCache[n].won = won;
   g_simCache[n].valid = valid;
   g_simCache[n].traceDir = g_lastSimExecDir;
   g_simCache[n].traceEntry = g_lastSimExecEntry;
   g_simCache[n].traceSl = g_lastSimExecSl;
   g_simCache[n].traceTp = g_lastSimExecTp;
   g_simCache[n].traceHalf = g_lastSimExecHalf;
   g_simCache[n].traceExitTime = g_lastSimExitTime;
   g_simCache[n].traceExitReason = g_lastSimExitReason;
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

int LiqPeriodSeconds(ENUM_TIMEFRAMES tf)
{
   if(tf == LN_PERIOD_H90) return LN_H90_SECONDS;
   return PeriodSeconds(tf);
}

bool CopySyntheticH90(int bars, MqlRates &rates[])
{
   ArrayFree(rates);
   int requested = MathMax(21, bars);
   int sourceBars = requested * 3 + 12;
   MqlRates source[];
   int copied = CopyRates(_Symbol, PERIOD_M30, 0, sourceBars, source);
   if(copied <= 20) return false;
   ArraySetAsSeries(source, false);

   MqlRates aggregated[];
   ArrayResize(aggregated, copied);
   int count = 0;
   datetime activeBucket = 0;
   for(int i = 0; i < copied; ++i)
   {
      if(source[i].time <= 0) continue;
      datetime bucket = (datetime)(((long)source[i].time / LN_H90_SECONDS) * LN_H90_SECONDS);
      if(count == 0 || bucket != activeBucket)
      {
         activeBucket = bucket;
         aggregated[count] = source[i];
         aggregated[count].time = bucket;
         count++;
         continue;
      }

      int j = count - 1;
      aggregated[j].high = MathMax(aggregated[j].high, source[i].high);
      aggregated[j].low = MathMin(aggregated[j].low, source[i].low);
      aggregated[j].close = source[i].close;
      aggregated[j].tick_volume += source[i].tick_volume;
      aggregated[j].real_volume += source[i].real_volume;
      if(source[i].spread > aggregated[j].spread)
         aggregated[j].spread = source[i].spread;
   }

   int take = MathMin(requested, count);
   if(take <= 20) return false;
   ArrayResize(rates, take);
   int first = count - take;
   for(int i = 0; i < take; ++i)
      rates[i] = aggregated[first + i];
   ArraySetAsSeries(rates, true);
   return true;
}

bool CopySeries(ENUM_TIMEFRAMES tf, int bars, MqlRates &rates[])
{
   if(tf == LN_PERIOD_H90)
      return CopySyntheticH90(bars, rates);
   ArrayFree(rates);
   int copied = CopyRates(_Symbol, tf, 0, bars, rates);
   if(copied <= 20) return false;
   ArraySetAsSeries(rates, true);
   return true;
}

bool EnsureSimulationSeries(ENUM_TIMEFRAMES tf, datetime requiredCutoff)
{
   datetime latestBar = iTime(_Symbol, tf, 0);
   if(latestBar <= 0 || requiredCutoff <= 0) return false;
   int cached = ArraySize(g_simRates);
   if(cached > 20 && g_simRatesTf == tf && g_simRatesLatestBar == latestBar
      && g_simRatesOldestBar > 0 && g_simRatesOldestBar <= requiredCutoff)
      return true;

   int requested = MathMax(InpCalcEntryBars, RequiredBarsForWindow(tf, requiredCutoff, 500));
   if(!CopySeries(tf, requested, g_simRates))
   {
      ArrayFree(g_simRates);
      g_simRatesLatestBar = 0;
      g_simRatesOldestBar = 0;
      return false;
   }
   g_simRatesTf = tf;
   g_simRatesLatestBar = g_simRates[0].time;
   g_simRatesOldestBar = g_simRates[ArraySize(g_simRates) - 1].time;
   return g_simRatesOldestBar > 0 && g_simRatesOldestBar <= requiredCutoff;
}

datetime ClosedBarAvailabilityTime(const MqlRates &rates[], int index)
{
   int total = ArraySize(rates);
   if(index < 1 || index >= total) return 0;
   // Series arrays: index-1 is the next chronological bar. Its open is the
   // exact close/availability time of the setup bar at index.
   return rates[index - 1].time;
}

int RequiredBarsForWindow(ENUM_TIMEFRAMES tf, datetime cutoff, int warmupBars)
{
   if(cutoff <= 0) return 0;
   int sec = LiqPeriodSeconds(tf);
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

datetime DayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

bool GetAsiaRangeFromRates(const MqlRates &rates[], datetime referenceTime, double &asiaHigh, double &asiaLow,
   datetime &asiaStart, datetime &asiaEnd)
{
   int sh = MathMax(0, MathMin(23, InpAsiaStartHourGmt));
   int eh = MathMax(0, MathMin(23, InpAsiaEndHourGmt));
   datetime day = DayStart(referenceTime);
   asiaStart = day + sh * 3600;
   asiaEnd = day + eh * 3600;
   if(asiaEnd <= asiaStart) asiaEnd += 86400;
   if(referenceTime <= asiaEnd)
   {
      asiaStart -= 86400;
      asiaEnd -= 86400;
   }

   bool found = false;
   asiaHigh = -DBL_MAX;
   asiaLow = DBL_MAX;
   for(int i = 0; i < ArraySize(rates); ++i)
   {
      datetime t = rates[i].time;
      if(t < asiaStart || t >= asiaEnd) continue;
      asiaHigh = MathMax(asiaHigh, rates[i].high);
      asiaLow = MathMin(asiaLow, rates[i].low);
      found = true;
   }
   return found && asiaHigh > asiaLow && asiaLow < DBL_MAX && asiaHigh > -DBL_MAX;
}

string SolModelLabel()
{
   if(!InpSolSessionRouterEnabled) return "ROUTER-OFF";
   return "ROUTER-" + IntegerToString(InpSolContinuationStartGmt) + "-" + IntegerToString(InpSolContinuationEndGmt)
      + "-Q" + DoubleToString(InpSolContinuationQualityLow, 2) + "-" + DoubleToString(InpSolContinuationQualityHigh, 2)
      + "-TZ" + IntegerToString(InpSolBrokerUtcOffsetMin);
}

bool AsiaLiquidityDrawAllows(const MqlRates &rates[], int dir, datetime entryTime, double asiaHigh, double asiaLow,
   datetime asiaEnd)
{
   bool swept = false;
   for(int i = 0; i < ArraySize(rates); ++i)
   {
      datetime t = rates[i].time;
      if(t <= asiaEnd || t > entryTime) continue;
      if(dir < 0 && rates[i].high > asiaHigh)
      {
         swept = true;
         break;
      }
      if(dir > 0 && rates[i].low < asiaLow)
      {
         swept = true;
         break;
      }
   }
   return swept;
}

void ApplyAsiaLiquidityTarget(ErlSignal &sig, const MqlRates &rates[])
{
   double asiaHigh = 0.0, asiaLow = 0.0;
   datetime asiaStart = 0, asiaEnd = 0;
   if(!GetAsiaRangeFromRates(rates, sig.entryTime, asiaHigh, asiaLow, asiaStart, asiaEnd)) return;
   double target = sig.dir < 0 ? asiaLow : asiaHigh;
   bool validSide = sig.dir < 0 ? target < sig.entry - TickSize() : target > sig.entry + TickSize();
   if(!validSide) return;
   sig.externalTarget = NormTradePrice(target);
   sig.externalTime = asiaEnd;
}

bool SmtAllows(const MqlRates &entryRates[], ENUM_TIMEFRAMES entryTf, int dir, datetime entryTime)
{
   if(StringLen(InpSmtSymbol) <= 0 || InpSmtSymbol == _Symbol) return true;
   if(!SymbolSelect(InpSmtSymbol, true)) return false;
   int idx = -1;
   for(int i = 0; i < ArraySize(entryRates); ++i)
   {
      if(entryRates[i].time == entryTime)
      {
         idx = i;
         break;
      }
   }
   if(idx < 1) return false;
   int lookback = MathMax(2, InpSmtLookbackBars);
   if(idx + lookback >= ArraySize(entryRates)) return false;

   MqlRates other[];
   int need = MathMax(InpCalcEntryBars, idx + lookback + 50);
   int copied = CopyRates(InpSmtSymbol, entryTf, 0, need, other);
   if(copied <= idx + lookback) return false;
   ArraySetAsSeries(other, true);
   int oidx = iBarShift(InpSmtSymbol, entryTf, entryTime, false);
   if(oidx < 1 || oidx + lookback >= ArraySize(other)) return false;

   double priorPrimaryHigh = -DBL_MAX, priorOtherHigh = -DBL_MAX;
   double priorPrimaryLow = DBL_MAX, priorOtherLow = DBL_MAX;
   for(int k = 1; k <= lookback; ++k)
   {
      priorPrimaryHigh = MathMax(priorPrimaryHigh, entryRates[idx + k].high);
      priorOtherHigh = MathMax(priorOtherHigh, other[oidx + k].high);
      priorPrimaryLow = MathMin(priorPrimaryLow, entryRates[idx + k].low);
      priorOtherLow = MathMin(priorOtherLow, other[oidx + k].low);
   }

   if(dir < 0)
   {
      bool primaryTookHigh = entryRates[idx].high > priorPrimaryHigh;
      bool otherFailedHigh = other[oidx].high <= priorOtherHigh;
      return primaryTookHigh && otherFailedHigh;
   }
   if(dir > 0)
   {
      bool primaryTookLow = entryRates[idx].low < priorPrimaryLow;
      bool otherFailedLow = other[oidx].low >= priorOtherLow;
      return primaryTookLow && otherFailedLow;
   }
   return false;
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

int CollectSwings(const MqlRates &rates[], int lookback, SwingLevel &swings[], int maxLevels = 0)
{
   ArrayFree(swings);
   int total = ArraySize(rates);
   int found = 0;
   int cap = maxLevels > 0 ? maxLevels : InpMaxSwings * 2;
   cap = MathMax(1, MathMin(50000, cap));
   for(int i = lookback + 2; i < total - lookback && found < cap; ++i)
   {
      if(IsSwingHigh(rates, i, lookback))
      {
         int n = ArraySize(swings);
         ArrayResize(swings, n + 1);
         swings[n].time = rates[i].time;
         // A symmetric swing is known only after all newer confirmation bars
         // have closed. The next bar open is its first causal availability.
         swings[n].confirmedTime = rates[i - lookback - 1].time;
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
         swings[n].confirmedTime = rates[i - lookback - 1].time;
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
   // A three-candle FVG is actionable only after its third candle closes.
   // midIndex >= 2 in all callers, so the next newer bar marks that close.
   zone.time = rates[midIndex - 2].time;
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
   // Keep historical reconstruction causal: do not expose the FVG while its
   // confirming third candle is still open.
   zone.time = rates[midIndex - 2].time;
   zone.low = newerHigh;
   zone.high = olderLow;
   zone.anchor = rates[midIndex].high;
   zone.firstLow = rates[midIndex + 1].low;
   zone.firstHigh = rates[midIndex + 1].high;
   return true;
}

double FrontierDisplacementScore(const MqlRates &rates[], int midIndex, int dir, const FvgZone &zone)
{
   if(midIndex - 1 < 0 || midIndex + 1 >= ArraySize(rates)) return 0.0;
   double atr = AtrFromRates(rates, MathMax(1, midIndex), InpAtrPeriod);
   if(atr <= TickSize()) return 0.0;

   double body = MathAbs(rates[midIndex].close - rates[midIndex].open);
   double range = MathMax(TickSize(), rates[midIndex].high - rates[midIndex].low);
   double impulse = dir > 0
      ? rates[midIndex - 1].close - rates[midIndex + 1].open
      : rates[midIndex + 1].open - rates[midIndex - 1].close;
   double closeLocation = dir > 0
      ? (rates[midIndex].close - rates[midIndex].low) / range
      : (rates[midIndex].high - rates[midIndex].close) / range;
   double gap = MathMax(0.0, zone.high - zone.low);
   return gap / atr + body / atr + MathMax(0.0, impulse) / atr + MathMax(0.0, MathMin(1.0, closeLocation));
}

bool FrontierDisplacementAllows(const MqlRates &rates[], int midIndex, int dir, FvgZone &zone)
{
   if(midIndex - 1 < 0 || midIndex + 1 >= ArraySize(rates)) return false;
   double atr = AtrFromRates(rates, MathMax(1, midIndex), InpAtrPeriod);
   if(atr <= TickSize()) return false;

   double directionalBody = dir > 0
      ? rates[midIndex].close - rates[midIndex].open
      : rates[midIndex].open - rates[midIndex].close;
   double impulse = dir > 0
      ? rates[midIndex - 1].close - rates[midIndex + 1].open
      : rates[midIndex + 1].open - rates[midIndex - 1].close;
   zone.quality = FrontierDisplacementScore(rates, midIndex, dir, zone);

   // Keep this permissive: the ATR-normalized FVG is primary evidence and
   // only a directly contradictory impulse is rejected.
   return directionalBody > 0.0 || impulse >= atr * 0.60;
}

bool FrontierZoneInvalidatedOnClose(const FvgZone &zone, const MqlRates &bar)
{
   double tolerance = TickSize() * 0.25;
   double boundary = zone.dir > 0
      ? (zone.firstLow > 0.0 ? zone.firstLow : zone.low)
      : (zone.firstHigh > 0.0 ? zone.firstHigh : zone.high);
   if(zone.dir > 0) return bar.close < boundary - tolerance;
   return bar.close > boundary + tolerance;
}

bool FrontierZoneTouched(const FvgZone &zone, const MqlRates &bar)
{
   return bar.low <= zone.high && bar.high >= zone.low;
}

// Causal multi-zone state machine. HTF closes govern zone invalidation, while
// the configured entry timeframe identifies the first live pullback and the
// spatially nearest active IRL without waiting for the HTF candle to close.
bool FindFrontierIrlAfterReclaim(const MqlRates &htfRates[], const MqlRates &entryRates[], int dir, int reclaimIndex,
   bool requireTouch, FvgZone &selected, datetime &readyTime)
{
   ZeroMemory(selected);
   readyTime = 0;
   int htfTotal = ArraySize(htfRates);
   int entryTotal = ArraySize(entryRates);
   if(reclaimIndex < 3 || reclaimIndex >= htfTotal || entryTotal < 3) return false;

   FvgZone candidates[];
   int maxFormationBars = MathMax(3, InpMaxFvgSearchBars);
   int scanned = 0;
   for(int midIndex = reclaimIndex - 1; midIndex >= 2 && scanned < maxFormationBars; --midIndex, ++scanned)
   {
      double atr = AtrFromRates(htfRates, MathMax(1, midIndex), InpAtrPeriod);
      double minSize = atr * MathMax(0.0, InpMinFvgAtrPct) / 100.0;
      FvgZone candidate;
      ZeroMemory(candidate);
      bool isFvg = dir > 0
         ? IsBullishFvg(htfRates, midIndex, minSize, candidate)
         : IsBearishFvg(htfRates, midIndex, minSize, candidate);
      if(!isFvg || !FrontierDisplacementAllows(htfRates, midIndex, dir, candidate)) continue;

      // The zone is valid until a completed HTF candle closes through the
      // first FVG candle extreme. Store that future availability timestamp, but only
      // apply it once entry-time replay reaches that timestamp.
      for(int hbar = midIndex - 2; hbar >= 1; --hbar)
      {
         if(htfRates[hbar].time < candidate.time) continue;
         if(!FrontierZoneInvalidatedOnClose(candidate, htfRates[hbar])) continue;
         candidate.invalidatedTime = ClosedBarAvailabilityTime(htfRates, hbar);
         break;
      }
      int n = ArraySize(candidates);
      ArrayResize(candidates, n + 1);
      candidates[n] = candidate;
   }
   if(ArraySize(candidates) <= 0) return false;
   if(!requireTouch)
   {
      selected = candidates[0];
      readyTime = selected.time;
      return true;
   }

   datetime earliestFormation = candidates[0].time;
   for(int c = 1; c < ArraySize(candidates); ++c)
      if(candidates[c].time < earliestFormation) earliestFormation = candidates[c].time;

   for(int bar = entryTotal - 2; bar >= 1; --bar)
   {
      if(entryRates[bar].time < earliestFormation) continue;
      bool hasBest = false;
      FvgZone bestZone;
      ZeroMemory(bestZone);
      double bestDistance = DBL_MAX;
      double bestQuality = -DBL_MAX;
      for(int c = 0; c < ArraySize(candidates); ++c)
      {
         if(entryRates[bar].time < candidates[c].time) continue;
         if(candidates[c].invalidatedTime > 0 && entryRates[bar].time >= candidates[c].invalidatedTime) continue;
         if(!FrontierZoneTouched(candidates[c], entryRates[bar])) continue;
         double midpoint = (candidates[c].low + candidates[c].high) * 0.5;
         double distance = MathAbs(entryRates[bar].close - midpoint);
         if(distance < bestDistance - TickSize()
            || (MathAbs(distance - bestDistance) <= TickSize() && candidates[c].quality > bestQuality))
         {
            hasBest = true;
            bestZone = candidates[c];
            bestDistance = distance;
            bestQuality = candidates[c].quality;
         }
      }
      if(hasBest)
      {
         selected = bestZone;
         readyTime = entryRates[bar].time;
         return true;
      }
   }
   return false;
}
bool DetectSweepReclaim(const MqlRates &rates[], const SwingLevel &swing, int &reclaimIndex)
{
   reclaimIndex = -1;
   // Series arrays: lower index is newer. Scan from just after swing toward latest.
   for(int j = swing.index - 1; j >= 1; --j)
   {
      // Do not let the historical engine sweep a pivot before that pivot was
      // observable in live execution.
      if(rates[j].time < swing.confirmedTime) continue;
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
      if(ok && FrontierDisplacementAllows(rates, i, dir, z))
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
   for(int i = total - 2; i >= 1; --i)
   {
      if(entryRates[i].time < zone.time) continue;
      if(FrontierZoneInvalidatedOnClose(zone, entryRates[i])) return false;
      bool tapped = FrontierZoneTouched(zone, entryRates[i]);
      if(!tapped) continue;
      double atr = AtrFromRates(entryRates, i, InpAtrPeriod);
      if(atr <= 0.0) continue;
      double buffer = atr * ClampSlBufferAtrPct(g_slBufferAtrPct) / 100.0;
      double entry = entryRates[i].close;
      double rawStop = (stopModel == ERL_STOP_FIRST_FVG_CANDLE && zone.firstLow > 0.0 && zone.firstHigh > 0.0)
         ? (dir > 0 ? zone.firstLow : zone.firstHigh)
         : (dir > 0 ? zone.low : zone.high);
      double sl = dir > 0 ? rawStop - buffer : rawStop + buffer;
      sl = DirectionalStopGuard(dir, entry, sl, entryRates[i].low, entryRates[i].high, buffer, atr);
      double risk = MathAbs(entry - sl);
      if(risk <= TickSize()) continue;
      sig.valid = true;
      sig.dir = dir;
      sig.entryTime = entryRates[i].time;
      sig.availableTime = ClosedBarAvailabilityTime(entryRates, i);
      if(sig.availableTime <= 0) continue;
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

void SolRebuildSignalDirection(ErlSignal &sig, int newDir)
{
   if(newDir == 0 || newDir == sig.dir) return;
   double mirroredRawStop = 2.0 * sig.entry - sig.sl;
   sig.dir = newDir;
   sig.sl = ApplyRuntimeSlDistance(newDir, sig.entry, mirroredRawStop);
   sig.risk = MathAbs(sig.entry - sig.sl);
   sig.tp1 = NormTradePrice(sig.entry + newDir * sig.risk * 0.5);
   sig.tp2 = NormTradePrice(sig.entry + newDir * sig.risk * 1.0);
   sig.tp3 = NormTradePrice(sig.entry + newDir * sig.risk * 1.5);
   sig.tp4 = NormTradePrice(sig.entry + newDir * sig.risk * 2.0);
   sig.tp5 = NormTradePrice(sig.entry + newDir * sig.risk * 2.5);
   sig.tp6 = NormTradePrice(sig.entry + newDir * sig.risk * 3.0);
   sig.reason += "|sol_direction_flip";
}
bool SolSessionRouterFlips(datetime brokerTime, double displacementQuality)
{
   if(!InpSolSessionRouterEnabled) return false;
   datetime gmtTime = brokerTime - InpSolBrokerUtcOffsetMin * 60;
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);

   int startHour = MathMax(0, MathMin(23, InpSolContinuationStartGmt));
   int endHour = MathMax(1, MathMin(24, InpSolContinuationEndGmt));
   bool continuationSession = startHour < endHour
      ? (dt.hour >= startHour && dt.hour < endHour)
      : (dt.hour >= startHour || dt.hour < endHour);
   bool mondayThroughThursday = dt.day_of_week >= 1 && dt.day_of_week <= 4;
   if(continuationSession) return mondayThroughThursday;

   double qualityLow = MathMax(0.0, InpSolContinuationQualityLow);
   double qualityHigh = MathMax(qualityLow, InpSolContinuationQualityHigh);
   return displacementQuality > qualityLow && displacementQuality <= qualityHigh;
}








bool SolRegimeFilterRejects(const RegimeV3Snapshot &state, bool continuationRoute, string &rule)
{
   rule = "";
   bool reversalRoute = !continuationRoute;

   if(state.core == "RANGE_LOW_VOL" && state.ageBucket == "MATURE"
      && state.transitionStatus == "STABLE" && continuationRoute)
      rule = "RF01_RLV_MATURE_STABLE_CONT";
   else if(state.core == "TREND_LOW_VOL" && state.h1h2Phase == "NEUTRAL_ROTATION"
      && state.macroDirection == "UP")
      rule = "RF02_TLV_ROTATION_UP";
   else if(state.h1h2Phase == "ALIGNED_IMPULSE" && state.macroDirection == "DOWN"
      && continuationRoute)
      rule = "RF03_IMPULSE_DOWN_CONT";
   else if(state.core == "RANGE_HIGH_VOL" && state.transitionStatus == "DEVELOPING")
      rule = "RF04_RHV_DEVELOPING";
   else if(state.core == "RANGE_LOW_VOL" && state.h1h2Phase == "DEEP_REBOUND"
      && state.volatilityDepth == "NORMAL")
      rule = "RF05_RLV_DEEP_REBOUND_NORMAL";
   else if(state.core == "RANGE_LOW_VOL" && state.h1h2Phase == "SHALLOW_REBOUND")
      rule = "RF06_RLV_SHALLOW_REBOUND";
   else if(state.h1h2Phase == "ALIGNED" && state.ageBucket == "FRESH"
      && state.transitionStatus == "STABLE")
      rule = "RF07_ALIGNED_FRESH_STABLE";
   else if(state.h1h2Phase == "SHALLOW_PULLBACK" && state.ageBucket == "MATURE"
      && state.transitionStatus == "STABLE")
      rule = "RF08_SHALLOW_PULLBACK_MATURE";
   else if(state.core == "RANGE_HIGH_VOL" && state.h1h2Phase == "ALIGNED_IMPULSE")
      rule = "RF09_RHV_ALIGNED_IMPULSE";
   else if(state.core == "RANGE_LOW_VOL" && state.volatilityDepth == "COMPRESSED"
      && state.macroDirection == "DOWN" && reversalRoute)
      rule = "RF10_RLV_COMPRESSED_DOWN_REV";
   else if(state.h1h2Phase == "ALIGNED_IMPULSE" && state.volatilityDepth == "NORMAL"
      && reversalRoute)
      rule = "RF11_IMPULSE_NORMAL_REV";
   else if(state.h1h2Phase == "SHALLOW_PULLBACK" && state.volatilityDepth == "NORMAL")
      rule = "RF12_SHALLOW_PULLBACK_NORMAL";

   return rule != "";
}

int SolRegimeRuleIndex(const string rule)
{
   if(StringLen(rule) < 4 || StringSubstr(rule, 0, 2) != "RF") return -1;
   int number = (int)StringToInteger(StringSubstr(rule, 2, 2));
   return number >= 1 && number <= SOL_ADV_RF_COUNT ? number - 1 : -1;
}

string SolRegimeRuleCode(int index)
{
   return index >= 0 && index < SOL_ADV_RF_COUNT ? StringFormat("RF%02d", index + 1) : "RF??";
}

bool SolRegimeRuleBlocks(const string rule)
{
   int index = SolRegimeRuleIndex(rule);
   return index >= 0 && index < SOL_ADV_RF_COUNT ? g_solRegimeRuleBlocked[index] : true;
}

string SolRegimeRuleStatsText(int index)
{
   int wins = g_solRegimeRuleWins[index];
   int losses = g_solRegimeRuleLosses[index];
   int resolved = wins + losses;
   double wr = resolved > 0 ? (double)wins / (double)resolved * 100.0 : 0.0;
   return SolRegimeRuleCode(index) + " " + IntegerToString(wins) + "W/"
      + IntegerToString(losses) + "L " + DoubleToString(wr, 1) + "%";
}

string SolRegimeRuleMask()
{
   string mask = "";
   for(int i = 0; i < SOL_ADV_RF_COUNT; ++i)
      mask += (i > 0 ? "," : "") + SolRegimeRuleCode(i) + "=" + (g_solRegimeRuleBlocked[i] ? "BLOCK" : "ALLOW");
   return mask;
}

int ApplySolRegimeFilter(ErlSignal &signals[])
{
   g_solRegimeFilterRejected = 0;
   g_solRegimeFilterUnclassified = 0;
   if(!g_solRegimeFilterEnabled || ArraySize(signals) <= 0) return ArraySize(signals);

   // Fail open when regime history is unavailable. The status counters expose
   // this explicitly; execution must never pretend an unknown state was tested.
   if(ArraySize(g_regimeV3Timeline) <= 0 && !RegimeV3EnsureTimeline(true))
   {
      g_solRegimeFilterUnclassified = ArraySize(signals);
      return ArraySize(signals);
   }

   ErlSignal filtered[];
   for(int i = 0; i < ArraySize(signals); ++i)
   {
      RegimeV3Snapshot state;
      if(!RegimeV3SnapshotAt(signals[i].availableTime, state))
      {
         int keepUnknown = ArraySize(filtered);
         ArrayResize(filtered, keepUnknown + 1);
         filtered[keepUnknown] = signals[i];
         g_solRegimeFilterUnclassified++;
         continue;
      }

      bool continuationRoute = StringFind(signals[i].reason, "|sol_session_continuation") >= 0;
      string rule = "";
      if(SolRegimeFilterRejects(state, continuationRoute, rule) && SolRegimeRuleBlocks(rule))
      {
         g_solRegimeFilterRejected++;
         continue;
      }

      int keep = ArraySize(filtered);
      ArrayResize(filtered, keep + 1);
      filtered[keep] = signals[i];
   }

   ArrayFree(signals);
   ArrayResize(signals, ArraySize(filtered));
   for(int i = 0; i < ArraySize(filtered); ++i) signals[i] = filtered[i];
   return ArraySize(signals);
}


bool SolRegimeFilterDecision(const ErlSignal &sig, bool &rejected, string &rule)
{
   rejected = false;
   rule = "";
   if(!g_solRegimeFilterEnabled) return true;
   if(ArraySize(g_regimeV3Timeline) <= 0 && !RegimeV3EnsureTimeline(true)) return false;

   RegimeV3Snapshot state;
   if(!RegimeV3SnapshotAt(sig.availableTime, state)) return false;
   bool continuationRoute = StringFind(sig.reason, "|sol_session_continuation") >= 0;
   bool matched = SolRegimeFilterRejects(state, continuationRoute, rule);
   rejected = matched && SolRegimeRuleBlocks(rule);
   return true;
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
         if(entrySwings[s].confirmedTime > entryRates[i].time) continue;
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
      if(ok && FrontierDisplacementAllows(entryRates, i, dir, z))
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
      if(FrontierZoneInvalidatedOnClose(zone, rates[i])) return false;
      bool touched = FrontierZoneTouched(zone, rates[i]);
      if(!touched) continue;
      touchTime = ClosedBarAvailabilityTime(rates, i);
      return touchTime > 0;
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
   int scanned = 0;
   for(int i = total - 2; i >= 1 && scanned < MathMax(3, maxTapBars); --i)
   {
      if(entryRates[i].time < zone.time) continue;
      scanned++;
      if(FrontierZoneInvalidatedOnClose(zone, entryRates[i])) return false;
      bool tapped = FrontierZoneTouched(zone, entryRates[i]);
      if(!tapped) continue;
      double atr = AtrFromRates(entryRates, i, InpAtrPeriod);
      if(atr <= 0.0) continue;
      double buffer = atr * ClampSlBufferAtrPct(g_slBufferAtrPct) / 100.0;
      double entry = entryRates[i].close;
      double rawStop = (stopModel == ERL_STOP_FIRST_FVG_CANDLE && zone.firstLow > 0.0 && zone.firstHigh > 0.0)
         ? (dir > 0 ? zone.firstLow : zone.firstHigh)
         : (dir > 0 ? zone.low : zone.high);
      double sl = dir > 0 ? rawStop - buffer : rawStop + buffer;
      sl = DirectionalStopGuard(dir, entry, sl, entryRates[i].low, entryRates[i].high, buffer, atr);
      double risk = MathAbs(entry - sl);
      if(risk <= TickSize()) continue;
      sig.valid = true;
      sig.dir = dir;
      sig.entryTime = entryRates[i].time;
      sig.availableTime = ClosedBarAvailabilityTime(entryRates, i);
      if(sig.availableTime <= 0) continue;
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
   double buffer = atr * ClampSlBufferAtrPct(g_slBufferAtrPct) / 100.0;
   double entry = entryRates[barIndex].close;
   double rawStop = (stopModel == ERL_STOP_FIRST_FVG_CANDLE && zone.firstLow > 0.0 && zone.firstHigh > 0.0)
      ? (dir > 0 ? zone.firstLow : zone.firstHigh)
      : (dir > 0 ? zone.low : zone.high);
   double sl = dir > 0 ? rawStop - buffer : rawStop + buffer;
   sl = DirectionalStopGuard(dir, entry, sl, entryRates[barIndex].low, entryRates[barIndex].high, buffer, atr);
   double risk = MathAbs(entry - sl);
   if(risk <= TickSize()) return false;
   sig.valid = true;
   sig.dir = dir;
   sig.entryTime = entryRates[barIndex].time;
   sig.availableTime = ClosedBarAvailabilityTime(entryRates, barIndex);
   if(sig.availableTime <= 0) return false;
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
   return "SOL|" + _Symbol + "|" + TfLabel(htf) + "|" + TfLabel(entryTf) + "|SW" + IntegerToString(swingLookback)
      + "|" + EntryModelLabel(g_entryModel) + "|" + StopModelLabel(g_stopModel) + "|" + TargetModelLabel(g_targetModel)
      + "|" + StrictnessLabel(g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg)
      + "|" + NarrativeLabel(g_requireAsiaLiquidityDraw, g_useAsiaLiquidityTarget, g_requireSmt)
      + "|" + SolModelLabel() + "|" + (bias ? "B1" : "B0") + "|" + DirLabel(sig.dir) + "|" + IntegerToString((int)sig.availableTime);
}

void AssignExternalTarget(ErlSignal &sig, const SwingLevel &swings[])
{
   sig.externalTarget = 0.0;
   sig.externalTime = 0;
   double bestDist = DBL_MAX;
   for(int i = 0; i < ArraySize(swings); ++i)
   {
      if(swings[i].time > sig.availableTime) continue;
      if(swings[i].confirmedTime > sig.availableTime) continue;
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
   bool requireIrlTouch, bool requireEntrySweep, bool requireDisplacementFvg,
   bool requireAsiaLiquidityDraw, bool useAsiaLiquidityTarget, bool requireSmt)
{
   return "SOL|" + _Symbol + "|" + TfLabel(htf) + "|" + TfLabel(entryTf) + "|SW" + IntegerToString(swingLookback)
      + "|" + EntryModelLabel(entryModel) + "|" + StopModelLabel(stopModel) + "|" + TargetModelLabel(targetModel)
      + "|" + StrictnessLabel(requireIrlTouch, requireEntrySweep, requireDisplacementFvg)
      + "|" + NarrativeLabel(requireAsiaLiquidityDraw, useAsiaLiquidityTarget, requireSmt)
      + "|" + SolModelLabel() + "|" + (bias ? "B1" : "B0") + "|" + DirLabel(sig.dir) + "|" + IntegerToString((int)sig.availableTime);
}

int BuildSignals(ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES entryTf, int swingLookback, bool useBias,
   ERL_ENTRY_MODEL entryModel, ERL_STOP_MODEL stopModel, ERL_TARGET_MODEL targetModel,
   bool requireIrlTouch, bool requireEntrySweep, bool requireDisplacementFvg,
   bool requireAsiaLiquidityDraw, bool useAsiaLiquidityTarget, bool requireSmt,
   datetime cutoff, ErlSignal &signals[])
{
   ArrayFree(signals);
   MqlRates htfRates[], entryRates[];
   int htfBars = MathMax(InpCalcHtfBars, RequiredBarsForWindow(htf, cutoff, 250));
   int entryBars = MathMax(InpCalcEntryBars, RequiredBarsForWindow(entryTf, cutoff, 500));
   if(!CopySeries(htf, htfBars, htfRates)) return 0;
   if(!CopySeries(entryTf, entryBars, entryRates)) return 0;

   SwingLevel swings[];
   int dynamicSwingCap = MathMax(InpMaxSwings * 2, RequiredBarsForWindow(htf, cutoff, 250));
   dynamicSwingCap = MathMin(50000, MathMax(1, dynamicSwingCap));
   int swCount = CollectSwings(htfRates, swingLookback, swings, dynamicSwingCap);
   if(swCount <= 0) return 0;

   for(int s = 0; s < swCount; ++s)
   {
      if(g_histAuditRunning)
         SetHistoricalAuditProgress("SIGNALS", 5.0 + 50.0 * (double)(s + 1) / (double)MathMax(1, swCount));
      int dir = swings[s].dir < 0 ? 1 : -1; // sweep low -> buy, sweep high -> sell
      int reclaimIndex = -1;
      if(!DetectSweepReclaim(htfRates, swings[s], reclaimIndex)) continue;
      if(useBias && !PreviousWeekBiasAllowsAt(dir, htfRates[reclaimIndex].time)) continue;
      FvgZone zone;
      ZeroMemory(zone);
      datetime irlReadyTime = 0;
      bool frontierPrequalifiesTouch = (entryModel == ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG && requireIrlTouch);
      if(!FindFrontierIrlAfterReclaim(htfRates, entryRates, dir, reclaimIndex,
         frontierPrequalifiesTouch, zone, irlReadyTime)) continue;
      ErlSignal sig;
      ZeroMemory(sig);
      bool entryOk = false;
      if(entryModel == ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG)
         entryOk = ProEntrySweepReclaimFvg(entryRates, zone, dir, irlReadyTime, stopModel,
            false, requireEntrySweep, requireDisplacementFvg, sig);
      else
         entryOk = EntryTapFromFvg(entryRates, zone, dir, stopModel, sig);
      if(!entryOk) continue;
      bool solRouterFlip = SolSessionRouterFlips(sig.availableTime, zone.quality);
      if(solRouterFlip)
      {
         sig.reason += "|sol_session_continuation";
         SolRebuildSignalDirection(sig, -sig.dir);
      }
      else
         sig.reason += "|sol_session_reversal";
      // A valid IRL touch cannot authorize a later LTF setup after the HTF
      // narrative has already closed through its displacement origin.
      if(zone.invalidatedTime > 0 && sig.availableTime >= zone.invalidatedTime) continue;
      sig.reason += "|sol_frontier_q=" + DoubleToString(zone.quality, 2);
      // Final causal invariant: a historical signal must not exist before the
      // setup bar has closed or before its defining HTF FVG became available.
      if(sig.availableTime <= sig.entryTime) continue;
      if(sig.availableTime < zone.time) continue;
      if(cutoff > 0 && sig.availableTime < cutoff) continue;
      if(requireAsiaLiquidityDraw)
      {
         double asiaHigh = 0.0, asiaLow = 0.0;
         datetime asiaStart = 0, asiaEnd = 0;
         if(!GetAsiaRangeFromRates(entryRates, sig.entryTime, asiaHigh, asiaLow, asiaStart, asiaEnd)) continue;
         if(!AsiaLiquidityDrawAllows(entryRates, sig.dir, sig.entryTime, asiaHigh, asiaLow, asiaEnd)) continue;
      }
      if(requireSmt && !SmtAllows(entryRates, entryTf, sig.dir, sig.entryTime)) continue;
      sig.htfTime = htfRates[reclaimIndex].time;
      if(sig.sweepLevel <= 0.0) sig.sweepLevel = swings[s].price;
      AssignExternalTarget(sig, swings);
      if(useAsiaLiquidityTarget) ApplyAsiaLiquidityTarget(sig, entryRates);
      sig.id = SignalId(sig, htf, entryTf, swingLookback, useBias, entryModel, stopModel, targetModel,
         requireIrlTouch, requireEntrySweep, requireDisplacementFvg,
         requireAsiaLiquidityDraw, useAsiaLiquidityTarget, requireSmt);
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
         if(signals[i].availableTime > signals[j].availableTime)
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
   if((int)target>=101 && (int)target<=200) return NormTradePrice(sig.entry+sig.dir*sig.risk*TargetR(target));
   if(target == ERL_RR_TP1) return sig.tp1;
   if(target == ERL_RR_TP2) return sig.tp2;
   if(target == ERL_RR_TP3) return sig.tp3;
   if(target == ERL_RR_TP4) return sig.tp4;
   if(target == ERL_RR_TP5) return sig.tp5;
   return sig.tp6;
}

double SelectedTarget(const ErlSignal &sig, ERL_RR_MODE target, ERL_TARGET_MODEL targetModel)
{
   if(sig.targetOverride > 0.0) return sig.targetOverride;
   if(targetModel == ERL_TARGET_OPPOSITE_SIGNAL) return 0.0;
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

void SetSignalTargetLadder(ErlSignal &sig)
{
   sig.tp1 = NormTradePrice(sig.entry + sig.dir * sig.risk * 0.5);
   sig.tp2 = NormTradePrice(sig.entry + sig.dir * sig.risk * 1.0);
   sig.tp3 = NormTradePrice(sig.entry + sig.dir * sig.risk * 1.5);
   sig.tp4 = NormTradePrice(sig.entry + sig.dir * sig.risk * 2.0);
   sig.tp5 = NormTradePrice(sig.entry + sig.dir * sig.risk * 2.5);
   sig.tp6 = NormTradePrice(sig.entry + sig.dir * sig.risk * 3.0);
}

bool ApplyFullInversionGeometry(const ErlSignal &source, ERL_RR_MODE target, ERL_TARGET_MODEL targetModel,
   ErlSignal &inverted, string &detail)
{
   detail = "";
   if(targetModel == ERL_TARGET_OPPOSITE_SIGNAL)
   {
      detail = "full_invert_unsupported_reverse_target";
      return false;
   }
   double sourceRisk = MathAbs(source.entry - source.sl);
   double sourceTarget = SelectedTarget(source, target, targetModel);
   double sourceTargetDistance = MathAbs(sourceTarget - source.entry);
   if(sourceRisk <= TickSize() || sourceTarget <= 0.0 || sourceTargetDistance <= TickSize())
   {
      detail = "full_invert_invalid_source_geometry";
      return false;
   }

   inverted = source;
   inverted.invertedGeometry = true;
   inverted.dir = -source.dir;
   inverted.sl = NormTradePrice(sourceTarget);
   inverted.risk = MathAbs(inverted.entry - inverted.sl);
   inverted.targetOverride = NormTradePrice(source.sl);
   inverted.externalTarget = 0.0;
   inverted.externalTime = 0;
   if(inverted.risk <= TickSize())
   {
      detail = "full_invert_invalid_swapped_risk";
      return false;
   }
   bool slSideOk = inverted.dir > 0 ? inverted.sl < inverted.entry : inverted.sl > inverted.entry;
   bool tpSideOk = inverted.dir > 0 ? inverted.targetOverride > inverted.entry : inverted.targetOverride < inverted.entry;
   if(!slSideOk || !tpSideOk)
   {
      detail = "full_invert_invalid_swapped_sides";
      return false;
   }
   SetSignalTargetLadder(inverted);
   double effectiveR = MathAbs(inverted.targetOverride - inverted.entry) / inverted.risk;
   detail = "pure_swap=1 source_dir=" + DirLabel(source.dir)
      + " exec_dir=" + DirLabel(inverted.dir)
      + " source_sl=" + DoubleToString(source.sl, _Digits)
      + " source_tp=" + DoubleToString(sourceTarget, _Digits)
      + " inv_sl=" + DoubleToString(inverted.sl, _Digits)
      + " inv_tp=" + DoubleToString(inverted.targetOverride, _Digits)
      + " effective_r=" + DoubleToString(effectiveR, 4);
   return true;
}

ERL_HC_MODE EffectiveHalfModeForSignal(const ErlSignal &sig, ERL_HC_MODE requested,
   ERL_RR_MODE target, ERL_TARGET_MODEL targetModel)
{
   if(requested == ERL_HC_OFF || targetModel == ERL_TARGET_OPPOSITE_SIGNAL) return ERL_HC_OFF;
   double finalTarget = SelectedTarget(sig, target, targetModel);
   double trigger = HalfTrigger(sig, requested);
   double finalDistance = MathAbs(finalTarget - sig.entry);
   double triggerDistance = MathAbs(trigger - sig.entry);
   if(finalTarget <= 0.0 || trigger <= 0.0 || finalDistance <= TickSize()) return ERL_HC_OFF;
   if(triggerDistance >= finalDistance - TickSize() * 0.5) return ERL_HC_OFF;
   return requested;
}

void SanitizeHalfMode()
{
   if(g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL)
   {
      g_hc = ERL_HC_OFF;
      return;
   }
   // In full inversion the effective target multiple is the reciprocal of
   // the source geometry. Per-signal validation below disables only HC
   // triggers that are not strictly before that effective target.
   if(g_invertMode) return;
   int targetLeg = (int)MathCeil(TargetR(g_target)*2.0-1e-9);
   int hcLeg = (int)g_hc;
   if(targetLeg <= 1) g_hc = ERL_HC_OFF;
   else if(hcLeg >= targetLeg) g_hc = (ERL_HC_MODE)MathMin(5,targetLeg - 1);
}

//=====================================================================
//  SIMULATION AND HISTORICAL AUDIT
//=====================================================================
int FindEntryBarIndex(const MqlRates &rates[], datetime t)
{
   int total = ArraySize(rates);
   for(int i = 0; i < total; ++i)
      if(rates[i].time == t) return i;

   // Broker timestamps can differ by a few seconds. Resolve the containing
   // closed bar without ever moving the signal into a future bar.
   for(int i = 1; i < total; ++i)
      if(rates[i].time <= t && t < rates[i - 1].time) return i;
   return -1;
}

int ResolveSameBar(const MqlRates &bar, int dir, double openPx, double tp, double sl)
{
   bool hitTp = tp > 0.0 && (dir > 0 ? bar.high >= tp : bar.low <= tp);
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

double ApplyForcedSignalExit(int dir, double exitPx, double simEntry, double simRisk, bool halfDone, ERL_HC_MODE hc, double pnlR, double commissionR)
{
   if(exitPx <= 0.0 || simRisk <= TickSize()) return pnlR;
   double exitR = (dir > 0 ? (exitPx - simEntry) : (simEntry - exitPx)) / simRisk;
   pnlR += (halfDone && hc != ERL_HC_OFF) ? exitR * 0.5 : exitR;
   pnlR -= commissionR;
   return pnlR;
}

double TargetPriceForSimulation(const ErlSignal &sig, ERL_RR_MODE target, ERL_TARGET_MODEL targetModel, double simEntry, double simRisk)
{
   if(targetModel == ERL_TARGET_OPPOSITE_SIGNAL) return 0.0;
   if(targetModel == ERL_TARGET_NEXT_EXTERNAL && sig.externalTarget > 0.0)
   {
      bool validSide = sig.dir > 0 ? sig.externalTarget > simEntry + TickSize() : sig.externalTarget < simEntry - TickSize();
      if(validSide) return NormTradePrice(sig.externalTarget);
   }
   ERL_RR_MODE effective = EffectiveTargetModeByRisk(simRisk, target, targetModel);
   return NormTradePrice(simEntry + sig.dir * simRisk * TargetR(effective));
}

bool ConfigureSimulationLevels(const ErlSignal &sig, ERL_RR_MODE target, ERL_HC_MODE requestedHc,
   ERL_TARGET_MODEL targetModel, double simEntry, bool reverseExitMode, int &simDir,
   double &activeSl, double &tp, double &half, double &simRisk, ERL_HC_MODE &activeHc,
   double &commissionR, string &detail)
{
   detail = "";
   ErlSignal source = sig;
   source.entry = NormTradePrice(simEntry);
   // Match BuildExecutableSignal: fixed-pip and percentage SL geometry is
   // anchored to the actual simulated fill, not the earlier signal price.
   source.sl = ApplyRuntimeSlDistance(source.dir, source.entry, source.sl);
   source.targetOverride = 0.0;
   source.invertedGeometry = false;
   source.risk = MathAbs(source.entry - source.sl);
   if(source.risk <= TickSize())
   {
      detail = "simulation_source_risk_invalid";
      return false;
   }
   SetSignalTargetLadder(source);

   ErlSignal tradeSig = source;
   if(g_invertMode)
   {
      if(reverseExitMode)
      {
         detail = "full_invert_unsupported_reverse_target";
         return false;
      }
      if(!ApplyFullInversionGeometry(source, target, targetModel, tradeSig, detail))
         return false;
   }

   simDir = tradeSig.dir;
   activeSl = reverseExitMode ? 0.0 : tradeSig.sl;
   tp = reverseExitMode ? 0.0 : SelectedTarget(tradeSig, target, targetModel);
   simRisk = reverseExitMode ? source.risk : MathAbs(tradeSig.entry - activeSl);
   if(simRisk <= TickSize())
   {
      detail = "simulation_effective_risk_invalid";
      return false;
   }

   activeHc = reverseExitMode ? ERL_HC_OFF : EffectiveHalfModeForSignal(tradeSig, requestedHc, target, targetModel);
   half = activeHc == ERL_HC_OFF ? 0.0 : HalfTrigger(tradeSig, activeHc);
   commissionR = 0.0;
   double valuePerUnit = ValuePerPriceUnitPerLot();
   if(g_btCommissionPerLot > 0.0 && valuePerUnit > 0.0)
      commissionR = g_btCommissionPerLot / (simRisk * valuePerUnit);
   return true;
}

void ResetLastSimulationTrace()
{
   g_lastSimExecDir = 0;
   g_lastSimExecEntry = 0.0;
   g_lastSimExecSl = 0.0;
   g_lastSimExecTp = 0.0;
   g_lastSimExecHalf = 0.0;
   g_lastSimExitTime = 0;
   g_lastSimExitReason = "";
}

void CaptureLastSimulationGeometry(int dir, double entry, double sl, double tp, double half)
{
   g_lastSimExecDir = dir;
   g_lastSimExecEntry = entry;
   g_lastSimExecSl = sl;
   g_lastSimExecTp = tp;
   g_lastSimExecHalf = half;
}

void CaptureLastSimulationExit(string reason, datetime exitTime)
{
   g_lastSimExitReason = reason;
   g_lastSimExitTime = exitTime;
}

double SimulateSignal(const ErlSignal &sig, ERL_RR_MODE target, ERL_HC_MODE hc, ERL_TARGET_MODEL targetModel,
   ENUM_TIMEFRAMES entryTf, datetime maxTime, bool &closed, bool &won, bool &valid)
{
   bool reverseExitMode = (targetModel == ERL_TARGET_OPPOSITE_SIGNAL);
   if(reverseExitMode) hc = ERL_HC_OFF;
   closed = false;
   won = false;
   valid = false;
   g_lastSimInvalidReason = "";
   ResetLastSimulationTrace();
   if(g_invertMode && reverseExitMode)
   {
      g_lastSimInvalidReason = "INV_REVERSE";
      return 0.0;
   }

   int tfSeconds = PeriodSeconds(entryTf);
   if(tfSeconds <= 0) tfSeconds = 60;
   datetime requiredCutoff = sig.entryTime - tfSeconds * 4;
   if(g_btCutoff > 0 && g_btCutoff < requiredCutoff) requiredCutoff = g_btCutoff;
   if(!EnsureSimulationSeries(entryTf, requiredCutoff))
   {
      g_lastSimInvalidReason = "SERIES";
      return 0.0;
   }
   int setupIdx = FindEntryBarIndex(g_simRates, sig.entryTime);
   if(setupIdx < 1)
   {
      g_lastSimInvalidReason = "ENTRY_BAR";
      return 0.0;
   }
   if(sig.availableTime <= 0)
   {
      g_lastSimInvalidReason = "AVAIL_TIME";
      return 0.0;
   }
   int entryIdx = setupIdx - 1;
   int pricingDir = EffectiveTradeDir(sig.dir);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) point = TickSize();
   double rawEntry = sig.entry;
   if(g_btFillMode == BT_FILL_NEXT_BAR_OPEN)
      rawEntry = g_simRates[entryIdx].open;
   else if(g_btFillMode == BT_FILL_CONSERVATIVE)
      rawEntry = pricingDir > 0 ? g_simRates[entryIdx].high : g_simRates[entryIdx].low;

   // With zero configured spread use the spread recorded on the historical
   // entry bar. Reusing today's live/weekend spread across years distorts
   // index audits, especially when spread is a material fraction of the SL.
   double effectiveSpreadPts = g_btSpreadPts;
   if(effectiveSpreadPts <= 0.0 && entryIdx >= 0 && entryIdx < ArraySize(g_simRates)
      && g_simRates[entryIdx].spread > 0)
      effectiveSpreadPts = (double)g_simRates[entryIdx].spread;
   double executionCost = MathMax(0.0, effectiveSpreadPts + g_btSlippagePts) * point;
   double simEntry = NormTradePrice(rawEntry + pricingDir * executionCost);
   double barSimEntry = simEntry;
   int simDir = pricingDir;
   double activeSl = 0.0, tp = 0.0, half = 0.0, simRisk = 0.0, commissionR = 0.0;
   ERL_HC_MODE activeHc = ERL_HC_OFF;
   string geometryDetail = "";
   if(!ConfigureSimulationLevels(sig, target, hc, targetModel, simEntry, reverseExitMode, simDir,
      activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail))
   {
      g_lastSimInvalidReason = "GEOMETRY";
      return 0.0;
   }

   valid = true;
   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);
   bool halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);
   double pnlR = 0.0;

   if(InpBacktestUseTickReplay)
   {
      datetime tickStart = sig.availableTime;
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
               if(ticks[k].bid > 0.0 && ticks[k].ask > 0.0) { first = k; break; }
            }
            int last = -1;
            for(int k = copied - 1; k >= 0; --k)
            {
               if(ticks[k].bid > 0.0 && ticks[k].ask > 0.0) { last = k; break; }
            }
            bool entryTickCoverage = (first >= 0 && last >= first
               && (datetime)ticks[first].time <= tickStart + tfSeconds);
            bool completeTickWindow = (entryTickCoverage
               && (maxTime <= 0 || (datetime)ticks[last].time >= maxTime));
            // A terminal TP/SL observed in an early tick chunk is final. Do
            // not discard that causal ordering merely because ticks after
            // the exit do not cover the later reverse-signal boundary.
            if(entryTickCoverage)
            {
               double slip = MathMax(0.0, g_btSlippagePts) * point;
               simEntry = NormTradePrice(simDir > 0 ? ticks[first].ask + slip : ticks[first].bid - slip);
                if(ConfigureSimulationLevels(sig, target, hc, targetModel, simEntry, reverseExitMode, simDir,
                   activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail))
                {
                   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);
                  halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);
                  pnlR = 0.0;
                  for(int k = first; k < copied; ++k)
                  {
                     double bid = ticks[k].bid;
                     double ask = ticks[k].ask;
                     if(bid <= 0.0 || ask <= 0.0) continue;
                     double closePx = simDir > 0 ? bid : ask;

                     if(!reverseExitMode && !halfDone)
                     {
                        bool hitHalf = simDir > 0 ? closePx >= half : closePx <= half;
                        if(hitHalf)
                        {
                           double halfR = MathAbs(half - simEntry) / simRisk;
                           pnlR += halfR * 0.5;
                           activeSl = simEntry;
                           halfDone = true;
                        }
                     }

                     bool hitSl = !reverseExitMode && (simDir > 0 ? closePx <= activeSl : closePx >= activeSl);
                     if(hitSl)
                     {
                        double slR = MathAbs(simEntry - activeSl) / simRisk;
                        pnlR -= halfDone && activeHc != ERL_HC_OFF ? slR * 0.5 : slR;
                        pnlR -= commissionR;
                        closed = true;
                        won = pnlR > 0.0;
                        CaptureLastSimulationExit("TICK_SL", (datetime)ticks[k].time);
                        return pnlR;
                     }

                     bool hitTp = !reverseExitMode && tp > 0.0 && (simDir > 0 ? closePx >= tp : closePx <= tp);
                     if(hitTp)
                     {
                        double targetR = MathAbs(tp - simEntry) / simRisk;
                        pnlR += halfDone && activeHc != ERL_HC_OFF ? targetR * 0.5 : targetR;
                        pnlR -= commissionR;
                        closed = true;
                        won = pnlR > 0.0;
                        CaptureLastSimulationExit("TICK_TP", (datetime)ticks[k].time);
                        return pnlR;
                     }
                  }

                  if(maxTime > 0 && completeTickWindow)
                  {
                     for(int k = last; k >= first; --k)
                     {
                        if(ticks[k].bid <= 0.0 || ticks[k].ask <= 0.0) continue;
                        if((datetime)ticks[k].time < maxTime) break;
                        double exitPx = simDir > 0 ? ticks[k].bid : ticks[k].ask;
                        pnlR = ApplyForcedSignalExit(simDir, exitPx, simEntry, simRisk, halfDone, activeHc, pnlR, commissionR);
                        closed = true;
                        won = pnlR > 0.0;
                        CaptureLastSimulationExit("TICK_REVERSE_EXIT", maxTime);
                        return pnlR;
                     }
                  }
                  else if(maxTime <= 0 && (datetime)ticks[last].time >= tickEnd - tfSeconds)
                  {
                     CaptureLastSimulationExit("TICK_OPEN", (datetime)ticks[last].time);
                     return pnlR;
                  }
                }
            }
         }
      }
   }

   // Tick coverage was unavailable/incomplete and no terminal event was
   // observed. Restart the deterministic OHLC fallback from its own entry
   // geometry; never carry a partial tick HC/BE state into the bar replay.
   simEntry = barSimEntry;
   if(!ConfigureSimulationLevels(sig, target, hc, targetModel, simEntry, reverseExitMode, simDir,
      activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail))
   {
      valid = false;
      g_lastSimInvalidReason = "GEOMETRY_FALLBACK";
      return 0.0;
   }
   CaptureLastSimulationGeometry(simDir, simEntry, activeSl, tp, half);
   halfDone = (activeHc == ERL_HC_OFF || half <= 0.0);
   pnlR = 0.0;

   for(int i = entryIdx; i >= 0; --i)
   {
      if(maxTime > 0 && g_simRates[i].time >= maxTime)
      {
         pnlR = ApplyForcedSignalExit(simDir, g_simRates[i].open, simEntry, simRisk, halfDone, activeHc, pnlR, commissionR);
         closed = true;
         won = pnlR > 0.0;
         CaptureLastSimulationExit("BAR_REVERSE_EXIT", maxTime);
         return pnlR;
      }
      if(!reverseExitMode && !halfDone)
      {
         bool hitHalf = simDir > 0 ? g_simRates[i].high >= half : g_simRates[i].low <= half;
         if(hitHalf)
         {
            double halfR = MathAbs(half - simEntry) / simRisk;
            pnlR += halfR * 0.5;
            activeSl = simEntry;
            halfDone = true;
         }
      }

      double openRef = (i == entryIdx ? simEntry : g_simRates[i].open);
      bool barHitTp = !reverseExitMode && tp > 0.0 && (simDir > 0 ? g_simRates[i].high >= tp : g_simRates[i].low <= tp);
      bool barHitSl = !reverseExitMode && (simDir > 0 ? g_simRates[i].low <= activeSl : g_simRates[i].high >= activeSl);
      int res = reverseExitMode ? 0 : ResolveSameBar(g_simRates[i], simDir, openRef, tp, activeSl);
      if(res > 0)
      {
         double targetR = MathAbs(tp - simEntry) / simRisk;
         pnlR += halfDone && activeHc != ERL_HC_OFF ? targetR * 0.5 : targetR;
         pnlR -= commissionR;
         closed = true;
         won = pnlR > 0.0;
         CaptureLastSimulationExit(barHitTp && barHitSl ? "BAR_BOTH_TP_POLICY" : "BAR_TP", g_simRates[i].time);
         return pnlR;
      }
      if(res < 0)
      {
         double slR = MathAbs(simEntry - activeSl) / simRisk;
         pnlR -= halfDone && activeHc != ERL_HC_OFF ? slR * 0.5 : slR;
         pnlR -= commissionR;
         closed = true;
         won = pnlR > 0.0;
         CaptureLastSimulationExit(barHitTp && barHitSl ? "BAR_BOTH_SL_POLICY" : "BAR_SL", g_simRates[i].time);
         return pnlR;
      }
   }
   CaptureLastSimulationExit("BAR_OPEN", g_simRates[0].time);
   return pnlR;
}
datetime NextSignalTime(const ErlSignal &signals[], int index)
{
   datetime current = signals[index].availableTime;
   int dir = signals[index].dir;
   for(int i = index + 1; i < ArraySize(signals); ++i)
   {
      if(signals[i].availableTime > current && signals[i].dir != dir) return signals[i].availableTime;
   }
   return 0;
}

datetime NextOppositeSignalTime(const ErlSignal &signals[], datetime current, int dir)
{
   for(int i = 0; i < ArraySize(signals); ++i)
   {
      if(signals[i].availableTime > current && signals[i].dir != dir) return signals[i].availableTime;
   }
   return 0;
}

void CopySignalArray(const ErlSignal &source[], ErlSignal &destination[])
{
   ArrayFree(destination);
   ArrayResize(destination, ArraySize(source));
   for(int i = 0; i < ArraySize(source); ++i) destination[i] = source[i];
}

void FilterAlternatingSignals(ErlSignal &signals[])
{
   ErlSignal filtered[];
   int lastDir = 0;
   for(int i = 0; i < ArraySize(signals); ++i)
   {
      if(lastDir != 0 && signals[i].dir == lastDir) continue;
      int n = ArraySize(filtered);
      ArrayResize(filtered, n + 1);
      filtered[n] = signals[i];
      lastDir = signals[i].dir;
   }
   ArrayFree(signals);
   ArrayResize(signals, ArraySize(filtered));
   for(int i = 0; i < ArraySize(filtered); ++i) signals[i] = filtered[i];
}

SimStats CalculateStats(ErlSignal &signals[], const ErlSignal &exitSignals[], ERL_RR_MODE target, ERL_HC_MODE hc, ERL_TARGET_MODEL targetModel, ENUM_TIMEFRAMES entryTf)
{
   SimStats st;
   ZeroMemory(st);
   if(!g_allowDuplicateEntries) FilterAlternatingSignals(signals);
   for(int i = 0; i < ArraySize(signals); ++i)
   {
      bool closed = false, won = false, valid = false;
      datetime nextSignalTime = NextOppositeSignalTime(exitSignals, signals[i].availableTime, signals[i].dir);
      double r = SimulateSignal(signals[i], target, hc, targetModel, entryTf, nextSignalTime, closed, won, valid);
      st.total++;
      if(!valid)
      {
         st.invalid++;
         continue;
      }
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

void CalculateSolRegimeRuleStats(ErlSignal &signals[], const ErlSignal &exitSignals[])
{
   for(int i = 0; i < SOL_ADV_RF_COUNT; ++i)
   {
      g_solRegimeRuleWins[i] = 0;
      g_solRegimeRuleLosses[i] = 0;
   }
   if(ArraySize(signals) <= 0) return;
   if(ArraySize(g_regimeV3Timeline) <= 0 && !RegimeV3EnsureTimeline(true)) return;
   if(!g_allowDuplicateEntries) FilterAlternatingSignals(signals);

   for(int i = 0; i < ArraySize(signals); ++i)
   {
      RegimeV3Snapshot state;
      if(!RegimeV3SnapshotAt(signals[i].availableTime, state)) continue;
      bool continuationRoute = StringFind(signals[i].reason, "|sol_session_continuation") >= 0;
      string rule = "";
      if(!SolRegimeFilterRejects(state, continuationRoute, rule)) continue;
      int ruleIndex = SolRegimeRuleIndex(rule);
      if(ruleIndex < 0 || ruleIndex >= SOL_ADV_RF_COUNT) continue;

      bool closed = false, won = false, valid = false;
      datetime nextSignalTime = NextOppositeSignalTime(exitSignals, signals[i].availableTime, signals[i].dir);
      string simKey = SimCacheKey(signals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime);
      double r = 0.0;
      if(!SimCacheGet(simKey, r, closed, won, valid))
      {
         r = SimulateSignal(signals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime, closed, won, valid);
         if(valid && closed) SimCachePut(simKey, r, closed, won, valid);
      }
      if(!valid || !closed) continue;
      if(won) g_solRegimeRuleWins[ruleIndex]++;
      else g_solRegimeRuleLosses[ruleIndex]++;
   }
}

#include "LiqNarrativeMacroRegimeFilter.mqh"

void RecalculateHistoricalStats(bool rebuildSignals = true)
{
   BeginHistoricalAuditProgress();
   datetime cutoff = TimeCurrent() - HistDays() * 86400;
   string rawSig = HistRawSignature();
   int weeks = ClampHistWeeks(g_histWeeks);
   bool cacheUsable = (!rebuildSignals
      && g_histRawCacheSignature == rawSig
      && g_histRawCacheWeeks >= weeks
      && ArraySize(g_histRawCache) > 0);

   if(cacheUsable)
   {
      ArrayFree(g_histSignals);
      for(int i = 0; i < ArraySize(g_histRawCache); ++i)
      {
         if(g_histRawCache[i].availableTime < cutoff) continue;
         int n = ArraySize(g_histSignals);
         ArrayResize(g_histSignals, n + 1);
         g_histSignals[n] = g_histRawCache[i];
      }
   }
   else
   {
      BuildSignals(g_htf, g_entryTf, g_swingLookback, g_weeklyBias, g_entryModel, g_stopModel, g_targetModel,
         g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg, g_requireAsiaLiquidityDraw,
         g_useAsiaLiquidityTarget, g_requireSmt, cutoff, g_histSignals);
      ArrayFree(g_histRawCache);
      ArrayResize(g_histRawCache, ArraySize(g_histSignals));
      for(int i = 0; i < ArraySize(g_histSignals); ++i) g_histRawCache[i] = g_histSignals[i];
      g_histRawCacheSignature = rawSig;
      g_histRawCacheWeeks = weeks;
      ArrayFree(g_simCache);
   }

   // A rejected setup cannot open a new position, but its opposite direction
   // still closes an existing position. Keep the raw causal stream for exits.
   ErlSignal exitSignals[];
   CopySignalArray(g_histSignals, exitSignals);
   ErlSignal macroRegimeStatsSignals[];
   CopySignalArray(g_histSignals, macroRegimeStatsSignals);
   SetHistoricalAuditProgress("REGIMES", 56.0, true);
   CalculateLiqMacroRegimeStats(macroRegimeStatsSignals, exitSignals);

   // Filter precedence is intentional: macro allow-list first, RF01-RF12 second.
   ApplyLiqMacroRegimeFilter(g_histSignals);
   ErlSignal regimeRuleStatsSignals[];
   CopySignalArray(g_histSignals, regimeRuleStatsSignals);
   CalculateSolRegimeRuleStats(regimeRuleStatsSignals, exitSignals);
   ApplySolRegimeFilter(g_histSignals);
   if(!g_allowDuplicateEntries) FilterAlternatingSignals(g_histSignals);
   ArrayResize(g_histSignalR, ArraySize(g_histSignals));
   ArrayResize(g_histSignalClosed, ArraySize(g_histSignals));
   ArrayResize(g_histSignalWon, ArraySize(g_histSignals));
   ArrayResize(g_histSignalValid, ArraySize(g_histSignals));
   ArrayResize(g_histSignalInvalidReason, ArraySize(g_histSignals));
   ArrayResize(g_histSignalExecDir, ArraySize(g_histSignals));
   ArrayResize(g_histSignalExecEntry, ArraySize(g_histSignals));
   ArrayResize(g_histSignalExecSl, ArraySize(g_histSignals));
   ArrayResize(g_histSignalExecTp, ArraySize(g_histSignals));
   ArrayResize(g_histSignalExecHalf, ArraySize(g_histSignals));
   ArrayResize(g_histSignalExitTime, ArraySize(g_histSignals));
   ArrayResize(g_histSignalExitReason, ArraySize(g_histSignals));

   ZeroMemory(g_hist);
   for(int i = 0; i < ArraySize(g_histSignals); ++i)
   {
      if(g_histAuditRunning)
         SetHistoricalAuditProgress("OUTCOMES", 78.0 + 21.0 * (double)(i + 1) / (double)MathMax(1, ArraySize(g_histSignals)));
      bool closed = false, won = false, valid = false;
      datetime nextSignalTime = NextOppositeSignalTime(exitSignals, g_histSignals[i].availableTime, g_histSignals[i].dir);
      // Restore the full trace with terminal outcomes; never freeze DATA/OPEN.
      string simKey = SimCacheKey(g_histSignals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime);
      double r = 0.0;
      if(!SimCacheGet(simKey, r, closed, won, valid))
      {
         r = SimulateSignal(g_histSignals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime, closed, won, valid);
         if(valid && closed) SimCachePut(simKey, r, closed, won, valid);
      }
      g_histSignalR[i] = r;
      g_histSignalClosed[i] = closed;
      g_histSignalWon[i] = won;
      g_histSignalValid[i] = valid;
      g_histSignalInvalidReason[i] = valid ? "" : g_lastSimInvalidReason;
      g_histSignalExecDir[i] = g_lastSimExecDir;
      g_histSignalExecEntry[i] = g_lastSimExecEntry;
      g_histSignalExecSl[i] = g_lastSimExecSl;
      g_histSignalExecTp[i] = g_lastSimExecTp;
      g_histSignalExecHalf[i] = g_lastSimExecHalf;
      g_histSignalExitTime[i] = g_lastSimExitTime;
      g_histSignalExitReason[i] = g_lastSimExitReason;
      g_hist.total++;
      if(!valid) { g_hist.invalid++; continue; }
      g_hist.netR += r;
      if(!closed) { g_hist.open++; continue; }
      if(won) { g_hist.wins++; g_hist.wonR += MathMax(0.0, r); }
      else { g_hist.losses++; g_hist.lostR += MathAbs(MathMin(0.0, r)); }
   }
   g_hist.pf = g_hist.lostR > 0.0 ? g_hist.wonR / g_hist.lostR : (g_hist.wonR > 0.0 ? 99.0 : 0.0);
   EndHistoricalAuditProgress();
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

   if(RiskEnabled())
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double base = BaseCapital();
      if(g_equityPeak <= 0.0) g_equityPeak = equity;
      g_equityPeak = MathMax(g_equityPeak, equity);

      double dailyPnl = DailyClosedPnl();
      double ddFromPeak = g_equityPeak - equity;
      if(DailyLossLimitPct() > 0.0 && dailyPnl <= -base * DailyLossLimitPct() / 100.0)
      {
         reason = "daily_loss_limit";
         return false;
      }
      if(MaxDrawdownPct() > 0.0 && ddFromPeak >= base * MaxDrawdownPct() / 100.0)
      {
         reason = "max_drawdown_limit";
         return false;
      }

      double riskMoney = equity * MathMax(0.01, RiskPerTradePct()) / 100.0;
      lot = NormalizeVolume(riskMoney / (riskDistance * valuePerUnit));
      double actualRiskMoney = RiskMoneyForLot(lot, sl < entry ? 1 : -1, entry, sl);
      double portfolioCap = equity * MathMax(0.01, MaxPortfolioRiskPct()) / 100.0;
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
bool IsCriticalAuditEvent(string eventName)
{
   if(StringFind(eventName, "order_") == 0) return true;
   if(StringFind(eventName, "risk_block") == 0) return true;
   if(StringFind(eventName, "close_") == 0) return true;
   if(StringFind(eventName, "half_close_") == 0) return true;
   if(StringFind(eventName, "sl_to_be_") == 0) return true;
   if(StringFind(eventName, "position_level_") == 0) return true;
   if(StringFind(eventName, "bridge_") == 0) return true;
   if(StringFind(eventName, "invert_") == 0) return true;
   return false;
}

void AuditWrite(string eventName, string id, int dir, double entry, double sl, double tp, double lot, string detail)
{
   if(!g_auditRuntime && !IsCriticalAuditEvent(eventName)) return;
   if(IsTesterMode()) return;
   string file = "LiqNarrativeSol_TradeAudit_" + FileDate(TimeCurrent()) + ".csv";
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


string FileBridgeTime(datetime t)
{
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

int FileBridgeFlags(int baseFlags)
{
   if(InpFileBridgeUseCommonFiles)
      baseFlags |= FILE_COMMON;
   return baseFlags;
}

string FileBridgeTfString(ENUM_TIMEFRAMES tf)
{
   int sec = LiqPeriodSeconds(tf);
   if(sec > 0) return IntegerToString(sec / 60);
   return TfLabel(tf);
}

string FileBridgeDate(datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return StringFormat("%04d%02d%02d", d.year, d.mon, d.day);
}

string FileBridgeSafeFileToken(string s)
{
   string out = s;
   StringReplace(out, "/", "_");
   StringReplace(out, ":", "_");
   StringReplace(out, "*", "_");
   StringReplace(out, "?", "_");
   StringReplace(out, "<", "_");
   StringReplace(out, ">", "_");
   StringReplace(out, "|", "_");
   StringReplace(out, " ", "_");
   return out;
}

int ClampBridgeChannel(int value) { return MathMax(1, MathMin(9999, value)); }
string FileBridgeChannelTag() { return "C" + IntegerToString(g_bridgeChannel); }
string BridgeChannelStateKey() { return "LNCH.ADV." + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "." + (string)ChartID(); }
string FileBridgeChannelEventId(string eventId)
{
   string prefix = "CH" + IntegerToString(g_bridgeChannel) + "|";
   return StringFind(eventId, prefix) == 0 ? eventId : prefix + eventId;
}
string FileBridgeChannelFile(string configured)
{
   int dot = StringFind(configured, ".csv");
   string suffix = "_" + FileBridgeChannelTag();
   if(dot < 0) return configured + suffix;
   return StringSubstr(configured, 0, dot) + suffix + StringSubstr(configured, dot);
}

string FileBridgeGenericLatestFileName()
{
   string configured = InpFileBridgeLatestFile;
   StringTrimLeft(configured);
   StringTrimRight(configured);
   if(configured == "" || configured == "LiqNarrativeSolBridge_Latest.csv")
      configured = "LiqNarrativeSolAdvancedBridge_Latest.csv";
   return FileBridgeChannelFile(configured);
}

string FileBridgeEffectiveAuditPrefix()
{
   string configured = InpFileBridgeAuditPrefix;
   StringTrimLeft(configured);
   StringTrimRight(configured);
   if(configured == "" || configured == "LiqNarrativeSolBridge_Audit_")
      configured = "LiqNarrativeSolAdvancedBridge_Audit_";
   return configured + FileBridgeChannelTag() + "_";
}

void ApplyBridgeChannel(int value)
{
   int next = ClampBridgeChannel(value);
   if(next == g_bridgeChannel) return;
   ArrayResize(g_bridgePending, 0);
   BridgePersistPending();
   if(g_fileBridgeEnabled)
   {
      string detached = "channel_detached|" + _Symbol + "|" + FileBridgeTfString(g_entryTf) + "|" + FileBridgeTime(TimeGMT());
      FileBridgeWriteLatestFile(FileBridgeGenericLatestFileName(), detached, "INIT", 0, 0, 0, "bridge_channel_detached|CH" + IntegerToString(g_bridgeChannel), 0, "detached", TimeGMT());
      FileBridgeWriteLatestFile(FileBridgeScopedLatestFileName(), detached, "INIT", 0, 0, 0, "bridge_channel_detached|CH" + IntegerToString(g_bridgeChannel), 0, "detached", TimeGMT());
   }
   g_bridgeChannel = next;
   GlobalVariableSet(BridgeChannelStateKey(), g_bridgeChannel);
   ArrayResize(g_bridgePending, 0);
   BridgePersistPending();
   g_lastBridgeStatus = "CHANNEL " + IntegerToString(g_bridgeChannel);
   if(g_fileBridgeEnabled) FileBridgeWriteInitMarker();
}

string FileBridgeScopedLatestFileName()
{
   return "LiqNarrativeSolAdvancedBridge_Latest_" + FileBridgeChannelTag() + "_" + FileBridgeSafeFileToken(_Symbol) + "_" + FileBridgeTfString(g_entryTf) + ".csv";
}
string FileBridgeSource()
{
   string src = "LiqNarrativeSolAdvanced|" + EntryModelLabel(g_entryModel) + "|" + StopModelLabel(g_stopModel) + "|" + TargetModelLabel(g_targetModel);
   if(g_pipSlMode) src += "|pipSL";
   if(g_invertMode) src += "|fullINV|pureSwap";
   src += "|CH" + IntegerToString(g_bridgeChannel);
   return src;
}

void FileBridgeWriteHeader(int h)
{
   FileWrite(h,
      "version", "written_gmt", "source_login", "symbol", "tf", "event_id", "source", "dir",
      "signal_time", "bridge_entry", "sl", "tp", "half_trigger", "half_label", "source_build", "source_bid", "source_ask", "risk_pct", "bridge_channel"
   );
}

void FileBridgeWriteRow(int h, string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   FileWrite(h,
      "1",
      FileBridgeTime(TimeGMT()),
      IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)),
      _Symbol,
      FileBridgeTfString(g_entryTf),
      FileBridgeChannelEventId(eventId),
      source,
      dir,
      FileBridgeTime(sourceSignalTime),
      DoubleToString(bridgeEntry, _Digits),
      DoubleToString(sl, _Digits),
      DoubleToString(tp, _Digits),
      DoubleToString(halfTriggerPrice, _Digits),
      halfTriggerLabel,
      LN_BUILD,
      DoubleToString(tick.bid, _Digits),
      DoubleToString(tick.ask, _Digits),
      DoubleToString(RiskPerTradePct(), 4),
      IntegerToString(g_bridgeChannel)
   );
}

int FileBridgeCommonFlag()
{
   return InpFileBridgeUseCommonFiles ? FILE_COMMON : 0;
}

string FileBridgeTempFileName(string fileName, int attempt)
{
   return fileName + ".tmp." + IntegerToString((int)ChartID()) + "." + IntegerToString((int)GetTickCount()) + "." + IntegerToString(attempt);
}

bool FileBridgePromoteTemp(string tempName, string fileName)
{
   int common = FileBridgeCommonFlag();
   ResetLastError();
   if(FileMove(tempName, common, fileName, common | FILE_REWRITE))
      return true;
   int err = GetLastError();
   FileDelete(tempName, common);
   Print("LiqNarrativeSol atomic latest promote failed err=", err, " temp=", tempName, " file=", fileName);
   return false;
}

bool FileBridgeWriteLatestFile(string fileName, string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   int tempFlags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_ANSI);
   for(int attempt = 0; attempt < 3; attempt++)
   {
      string tempName = FileBridgeTempFileName(fileName, attempt);
      FileDelete(tempName, FileBridgeCommonFlag());
      ResetLastError();
      int h = FileOpen(tempName, tempFlags, ',');
      if(h != INVALID_HANDLE)
      {
         FileBridgeWriteHeader(h);
         FileBridgeWriteRow(h, eventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
         FileFlush(h);
         FileClose(h);
         if(FileBridgePromoteTemp(tempName, fileName))
            return true;
      }
      else
         Print("LiqNarrativeSol atomic latest temp open failed err=", GetLastError(), " temp=", tempName);
      FileDelete(tempName, FileBridgeCommonFlag());
      if(attempt < 2) Sleep(20);
   }
   Print("LiqNarrativeSol atomic latest write failed file=", fileName);
   return false;
}

string FileBridgeOutboxFileName()
{
   return "LiqNarrativeSolAdvancedBridge_Outbox_" + FileBridgeChannelTag() + "_" + FileBridgeSafeFileToken(_Symbol) + "_" + FileBridgeTfString(g_entryTf) + ".csv";
}

bool BridgePersistPending()
{
   string fileName = FileBridgeOutboxFileName();
   string tempName = FileBridgeTempFileName(fileName, 0);
   int flags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_ANSI);
   FileDelete(tempName, FileBridgeCommonFlag());
   ResetLastError();
   int h = FileOpen(tempName, flags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("LiqNarrativeSol bridge outbox temp open failed err=", GetLastError(), " temp=", tempName);
      return false;
   }
   for(int i = 0; i < ArraySize(g_bridgePending); i++)
   {
      FileWrite(h, g_bridgePending[i].eventId, g_bridgePending[i].dir,
         DoubleToString(g_bridgePending[i].entry, _Digits), DoubleToString(g_bridgePending[i].sl, _Digits),
         DoubleToString(g_bridgePending[i].tp, _Digits), g_bridgePending[i].source,
         DoubleToString(g_bridgePending[i].halfTrigger, _Digits), g_bridgePending[i].halfLabel,
         IntegerToString((long)g_bridgePending[i].signalTime), IntegerToString(g_bridgePending[i].attempts));
   }
   FileFlush(h);
   FileClose(h);
   if(FileBridgePromoteTemp(tempName, fileName))
      return true;
   return false;
}

void BridgeLoadPending()
{
   ArrayResize(g_bridgePending, 0);
   int flags = FileBridgeFlags(FILE_CSV | FILE_READ | FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_ANSI);
   ResetLastError();
   int h = FileOpen(FileBridgeOutboxFileName(), flags, ',');
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h) && ArraySize(g_bridgePending) < 128)
   {
      string eventId = FileReadString(h);
      if(eventId == "" && FileIsEnding(h)) break;
      BridgePendingEvent item;
      item.eventId = eventId;
      item.dir = FileReadString(h);
      item.entry = StringToDouble(FileReadString(h));
      item.sl = StringToDouble(FileReadString(h));
      item.tp = StringToDouble(FileReadString(h));
      item.source = FileReadString(h);
      item.halfTrigger = StringToDouble(FileReadString(h));
      item.halfLabel = FileReadString(h);
      item.signalTime = (datetime)StringToInteger(FileReadString(h));
      item.attempts = (int)StringToInteger(FileReadString(h));
      item.nextRetryLocal = 0;
      if(item.eventId == "") continue;
      int n = ArraySize(g_bridgePending);
      ArrayResize(g_bridgePending, n + 1);
      g_bridgePending[n] = item;
   }
   FileClose(h);
   if(ArraySize(g_bridgePending) > 0)
      Print("LiqNarrativeSol bridge outbox loaded pending=", ArraySize(g_bridgePending));
}

bool BridgeQueuePending(string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   int n = ArraySize(g_bridgePending);
   int index = -1;
   for(int i = 0; i < n; i++)
      if(g_bridgePending[i].eventId == eventId) { index = i; break; }
   if(index < 0)
   {
      if(n >= 128)
      {
         Print("LiqNarrativeSol bridge outbox full; event remains unaccepted id=", eventId);
         return false;
      }
      ArrayResize(g_bridgePending, n + 1);
      index = n;
      g_bridgePending[index].attempts = 0;
   }
   g_bridgePending[index].eventId = eventId;
   g_bridgePending[index].dir = dir;
   g_bridgePending[index].entry = bridgeEntry;
   g_bridgePending[index].sl = sl;
   g_bridgePending[index].tp = tp;
   g_bridgePending[index].source = source;
   g_bridgePending[index].halfTrigger = halfTriggerPrice;
   g_bridgePending[index].halfLabel = halfTriggerLabel;
   g_bridgePending[index].signalTime = sourceSignalTime;
   g_bridgePending[index].nextRetryLocal = TimeLocal() + 2;
   bool persisted = BridgePersistPending();
   if(persisted)
      Print("LiqNarrativeSol bridge event durably queued id=", eventId, " pending=", ArraySize(g_bridgePending));
   return persisted;
}

void BridgeRemovePending(int index)
{
   int n = ArraySize(g_bridgePending);
   if(index < 0 || index >= n) return;
   for(int i = index; i < n - 1; i++) g_bridgePending[i] = g_bridgePending[i + 1];
   ArrayResize(g_bridgePending, n - 1);
}

void BridgeRetryPending()
{
   if(!g_fileBridgeEnabled || IsTesterMode() || ArraySize(g_bridgePending) <= 0) return;
   int processed = 0;
   while(ArraySize(g_bridgePending) > 0 && processed < 1)
   {
      if(g_bridgePending[0].nextRetryLocal > TimeLocal()) break;
      BridgePendingEvent item = g_bridgePending[0];
      if(!FileBridgeWriteLatestFile(FileBridgeScopedLatestFileName(), item.eventId, item.dir, item.entry, item.sl, item.tp, item.source, item.halfTrigger, item.halfLabel, item.signalTime))
      {
         g_bridgePending[0].attempts++;
         g_bridgePending[0].nextRetryLocal = TimeLocal() + MathMin(30, 2 + g_bridgePending[0].attempts * 2);
         BridgePersistPending();
         break;
      }
      Print("LiqNarrativeSol bridge outbox delivered id=", item.eventId);
      BridgeRemovePending(0);
      BridgePersistPending();
      processed++;
   }
}

bool FileBridgeWriteInitMarker()
{
   if(!g_fileBridgeEnabled || IsTesterMode()) return false;
   string eventId = "liq_sol_advanced_bridge_init|" + _Symbol + "|" + FileBridgeTfString(g_entryTf) + "|" + FileBridgeTime(TimeGMT());
   bool genericOk = FileBridgeWriteLatestFile(FileBridgeGenericLatestFileName(), eventId, "INIT", 0.0, 0.0, 0.0, "bridge_initiated", 0.0, "init", TimeGMT());
   bool scopedOk = FileBridgeWriteLatestFile(FileBridgeScopedLatestFileName(), eventId, "INIT", 0.0, 0.0, 0.0, "bridge_initiated", 0.0, "init", TimeGMT());
   g_lastBridgeStatus = scopedOk ? "INIT WROTE" : "INIT SCOPED FAIL";
   if(!genericOk)
      Print("LiqNarrativeSol file_bridge init generic atomic write failed file=", FileBridgeGenericLatestFileName());
   return scopedOk;
}

bool FileBridgeWriteEvent(string eventId, string dir, datetime signalTime, double bridgeEntry, double sl, double tp,
   double halfTriggerPrice, string halfTriggerLabel, string source)
{
   if(!g_fileBridgeEnabled || IsTesterMode()) return false;
   // Keep the strategy signal id intact while isolating cTrader event ownership from SolVersion.
   string bridgeEventId = "SOLADVBRIDGE|" + eventId;
   bool genericOk = FileBridgeWriteLatestFile(FileBridgeGenericLatestFileName(), bridgeEventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, signalTime);
   if(!genericOk)
      Print("LiqNarrativeSol file_bridge generic atomic write failed file=", FileBridgeGenericLatestFileName());

   bool scopedOk = FileBridgeWriteLatestFile(FileBridgeScopedLatestFileName(), bridgeEventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, signalTime);
   bool accepted = scopedOk;
   if(!scopedOk)
      accepted = BridgeQueuePending(bridgeEventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, signalTime);

   string auditFile = FileBridgeEffectiveAuditPrefix() + FileBridgeDate(TimeGMT()) + ".csv";
   int auditFlags = FileBridgeFlags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_ANSI);
   ResetLastError();
   int a = FileOpen(auditFile, auditFlags, ',');
   if(a != INVALID_HANDLE)
   {
      bool header = (FileSize(a) == 0);
      FileSeek(a, 0, SEEK_END);
      if(header) FileBridgeWriteHeader(a);
      FileBridgeWriteRow(a, bridgeEventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, signalTime);
      FileClose(a);
   }
   else
      Print("LiqNarrativeSol file_bridge audit open failed err=", GetLastError(), " file=", auditFile);

   if(scopedOk)
      g_lastBridgeStatus = "WROTE " + dir + " " + FileBridgeTfString(g_entryTf);
   else if(accepted)
      g_lastBridgeStatus = "QUEUED " + dir + " " + FileBridgeTfString(g_entryTf);
   else
      g_lastBridgeStatus = "PUBLISH FAIL " + dir;
   Print("LiqNarrativeSol file_bridge event=", eventId, " dir=", dir, " scoped=", (scopedOk ? "1" : "0"), " queued=", ((!scopedOk && accepted) ? "1" : "0"), " generic=", (genericOk ? "1" : "0"), " risk_pct=", DoubleToString(RiskPerTradePct(), 4));
   return accepted;
}

bool FileBridgeWriteSignal(const ErlSignal &sig, double bridgeEntry, double sl, double tp, double halfTriggerPrice, string halfTriggerLabel)
{
   return FileBridgeWriteEvent(sig.id, DirLabel(sig.dir), sig.availableTime, bridgeEntry, sl, tp,
      halfTriggerPrice, halfTriggerLabel, FileBridgeSource());
}

bool FileBridgeWriteRegimeCloseOnly(const ErlSignal &sig, string rule)
{
   string eventId = sig.id + "|regime_filter_close";
   string source = FileBridgeSource() + "|RegimeFilterCloseOnly|" + rule;
   int closeDir = -EffectiveTradeDir(sig.dir);
   return FileBridgeWriteEvent(eventId, DirLabel(closeDir), sig.availableTime, sig.entry, 0.0, 0.0,
      0.0, "off", source);
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
   g_testerTradeAuditFile = "LiqNarrativeSol_TesterTradeAudit_" + ErlTesterAudit_FileStamp() + ".csv";
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
      InpValidationJobId, "mt5_strategy_tester_trade", "LiqNarrativeSolVersion", LN_BUILD, _Symbol, TfLabel(_Period),
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
   int copied = CopySeries(tf, requestedBars, rates) ? ArraySize(rates) : 0;
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
   BtAppendCoverage(PERIOD_H1, InpCalcHtfBars, g_btCutoff, "htf_h1", detail);
   BtAppendCoverage(LN_PERIOD_H90, InpCalcHtfBars, g_btCutoff, "htf_h1_5", detail);
   BtAppendCoverage(PERIOD_H2, InpCalcHtfBars, g_btCutoff, "htf_h2", detail);
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
   string file = "LiqNarrativeSol_BacktestProcess_" + FileDate(TimeGMT()) + ".csv";
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
      eventName, LN_BUILD, _Symbol, TfLabel(_Period), g_btFileName,
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

   string file = "LiqNarrativeSol_PositionProbe_" + FileDate(now) + ".csv";
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
      ulong posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      string lifecycle = PositionLifecycleDetail(posId, reason, profit, false);
      AuditWrite(reason, IntegerToString((int)deal), 0, HistoryDealGetDouble(deal, DEAL_PRICE), 0, 0,
         HistoryDealGetDouble(deal, DEAL_VOLUME), "profit=" + DoubleToString(profit, 2) + " " + lifecycle);
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
void DeleteDashboardObjects()
{
   // A visual rebuild must recreate every dashboard object in drawing order.
   // Keeping old buttons/edits lets newly-created rectangle backgrounds cover them.
   DeleteByPrefix(PFX + "DASH_");
   DeleteByPrefix(PFX + "BTN_");
   DeleteByPrefix(PFX + "EDIT_");
}

void DeleteAllLiqNarrativeLiveObjects()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, LN_PREFIX) == 0 && StringFind(name, "_LV_") >= 0)
         ObjectDelete(0, name);
   }
}

#define LIQ_DASH_LOGICAL_HEIGHT 1090
#include "LiqDashboardFit.mqh"
void RectObj(string id, int x, int y, int w, int h, color bg, color border)
{
   LiqFitBox(x,y,w,h);
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
   LiqFitPoint(x,y);fontSize=LiqFitFont(fontSize);
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
   LiqFitBox(x,y,w,h);
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
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, LiqFitFont(8));
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, DASH_Z + 2);
}

void EditObj(string id, int x, int y, int w, int h, string text)
{
   LiqFitBox(x,y,w,h);
   if(IsTesterMode()) return;
   string name = PFX + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'38,46,60');
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'90,178,255');
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, LiqFitFont(9));
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
   double pad = MathMax(MathMax(risk, TickSize()) * 0.18, TickSize() * 40.0);
   // Historical arrows must not use the final high/low of the bar that had
   // only just opened when the signal became available.
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

void DrawHistoricalSegment(string id, datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE style = STYLE_SOLID)
{
   if(IsTesterMode() || price <= 0.0 || t2 <= t1) return;
   string name = PFX + "HISTLVL_" + id;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectMove(0, name, 0, t1, price);
   ObjectMove(0, name, 1, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}
datetime NextOpenOwnPositionTimeAfter(datetime t, datetime maxEnd)
{
   datetime best = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      datetime openedAt = (datetime)PositionGetInteger(POSITION_TIME);
      if(openedAt <= t || openedAt >= maxEnd) continue;
      if(best == 0 || openedAt < best) best = openedAt;
   }
   return best;
}

void DrawLiveLevelSegment(string id, datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE style = STYLE_DASH, int width = 3)
{
   if(IsTesterMode() || price <= 0.0 || t2 <= t1) return;
   string name = PFX + id;
   if(ObjectFind(0, name) >= 0 && (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_TREND)
      ObjectDelete(0, name);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   ObjectMove(0, name, 0, t1, price);
   ObjectMove(0, name, 1, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, DASH_Z + 1);
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

void DrawHistoricalSignals(bool resetObjects = true)
{
   if(resetObjects)
   {
      DeleteByPrefix(PFX + "HIST_");
      DeleteByPrefix(PFX + "HISTTXT_");
      DeleteByPrefix(PFX + "HISTLVL_");
      DeleteByPrefix(PFX + "FVG_");
   }
   if(IsTesterMode()) return;
   if(!InpDrawHistoricalSignals) return;
   int count = ArraySize(g_histSignals);
   for(int i = 0; i < count; ++i)
   {
      ErlSignal displaySig = g_histSignals[i];
      string invertDetail = "";
      bool geometryOk = true;
      bool hasExecutionGeometry = g_histSignalValid[i]
         && i < ArraySize(g_histSignalExecEntry)
         && g_histSignalExecDir[i] != 0
         && g_histSignalExecEntry[i] > 0.0
         && g_histSignalExecSl[i] > 0.0;
      if(hasExecutionGeometry)
      {
         // Draw the exact bid/ask, spread and fill-adjusted geometry used by
         // SimulateSignal. Rebuilding it from the source signal can disagree
         // with the audited result on wide-spread symbols such as HK50.
         displaySig.dir = g_histSignalExecDir[i];
         displaySig.entry = g_histSignalExecEntry[i];
         displaySig.sl = g_histSignalExecSl[i];
         displaySig.risk = MathAbs(displaySig.entry - displaySig.sl);
         displaySig.targetOverride = g_histSignalExecTp[i];
         SetSignalTargetLadder(displaySig);
      }
      else if(g_invertMode)
         geometryOk = ApplyFullInversionGeometry(g_histSignals[i], g_target, g_targetModel, displaySig, invertDetail);

      string id = IntegerToString(i) + "_" + IntegerToString((int)g_histSignals[i].availableTime);
      bool closed = g_histSignalClosed[i];
      bool won = g_histSignalWon[i];
      bool valid = g_histSignalValid[i] && geometryOk;
      double r = g_histSignalR[i];
      color clr = !valid ? C'145,155,170' : (won ? C'60,220,140' : (closed ? C'255,80,110' : C'255,204,82'));
      double arrowPrice = SignalArrowPrice(displaySig.availableTime, displaySig.dir, displaySig.entry, displaySig.risk);
      DrawArrow(id, displaySig.availableTime, arrowPrice, displaySig.dir, clr);
      double pad = MathMax(MathAbs(displaySig.entry - displaySig.sl) * 0.25, TickSize() * 30.0);
      double targetPrice = hasExecutionGeometry ? g_histSignalExecTp[i] : SelectedTarget(displaySig, g_target, g_targetModel);
      ERL_HC_MODE displayHc = EffectiveHalfModeForSignal(displaySig, g_hc, g_target, g_targetModel);
      double hcPrice = hasExecutionGeometry ? g_histSignalExecHalf[i] : HalfTrigger(displaySig, displayHc);
      if(hasExecutionGeometry && hcPrice <= 0.0) displayHc = ERL_HC_OFF;
      datetime lineEnd = displaySig.availableTime + PeriodSeconds(g_entryTf) * 20;
      if(i + 1 < count && g_histSignals[i + 1].availableTime > displaySig.availableTime && g_histSignals[i + 1].availableTime < lineEnd)
         lineEnd = g_histSignals[i + 1].availableTime;
      datetime liveCut = NextOpenOwnPositionTimeAfter(displaySig.availableTime, lineEnd);
      if(liveCut > displaySig.availableTime && liveCut < lineEnd)
         lineEnd = liveCut;
      DrawHistoricalSegment(id + "_ENTRY", displaySig.availableTime, lineEnd, displaySig.entry, C'230,230,230', STYLE_SOLID);
      if(g_targetModel != ERL_TARGET_OPPOSITE_SIGNAL && geometryOk)
      {
         DrawHistoricalSegment(id + "_SL", displaySig.availableTime, lineEnd, displaySig.sl, C'255,80,110', STYLE_SOLID);
         if(targetPrice > 0.0)
            DrawHistoricalSegment(id + "_TP", displaySig.availableTime, lineEnd, targetPrice, C'80,255,180', STYLE_SOLID);
         if(displayHc != ERL_HC_OFF && hcPrice > 0.0)
            DrawHistoricalSegment(id + "_HC", displaySig.availableTime, lineEnd, hcPrice, C'255,204,82', STYLE_DOT);
      }
      string txt = DirLabel(displaySig.dir) + (g_invertMode ? " FULL INV" : "");
      if(!valid)
         txt += " DATA " + (geometryOk ? (g_histSignalInvalidReason[i] == "" ? "UNKNOWN" : g_histSignalInvalidReason[i]) : "INV_GEOMETRY");
      else
         txt += " " + (r >= 0 ? "+" : "") + DoubleToString(r, 2) + "R $"
            + (ApproxMoneyFromR(r) >= 0 ? "+" : "") + DoubleToString(ApproxMoneyFromR(r), 2);
      if(g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL)
      {
         txt += "\nREV EXIT: next opposite";
      }
      else if(geometryOk)
      {
         txt += "\nSL " + DoubleToString(displaySig.sl, _Digits);
         if(targetPrice > 0.0)
         {
            double effectiveR = MathAbs(targetPrice - displaySig.entry) / MathMax(TickSize(), MathAbs(displaySig.entry - displaySig.sl));
            txt += "\nTP " + DoubleToString(targetPrice, _Digits) + " (" + DoubleToString(effectiveR, 2) + "R)";
         }
         if(displayHc != ERL_HC_OFF && hcPrice > 0.0) txt += "\n" + HcLabel(displayHc) + " " + DoubleToString(hcPrice, _Digits);
      }
      if(i < ArraySize(g_histSignalExitReason) && g_histSignalExitReason[i] != "")
      {
         txt += "\nEXIT " + g_histSignalExitReason[i];
         if(i < ArraySize(g_histSignalExitTime) && g_histSignalExitTime[i] > 0)
            txt += " " + TimeToString(g_histSignalExitTime[i], TIME_DATE | TIME_MINUTES);
      }
      DrawChartText(id, displaySig.availableTime, displaySig.dir > 0 ? arrowPrice - pad : arrowPrice + pad, txt, clr);
      DrawFvgBox(id, g_histSignals[i].htfTime, displaySig.availableTime + PeriodSeconds(g_entryTf) * 4,
         g_histSignals[i].fvgLow, g_histSignals[i].fvgHigh, clr);
   }
}

void DrawLivePositionMarker(ulong ticket, datetime t, double open, double sl, double tp, int dir)
{
   if(IsTesterMode()) return;
   double risk = (sl > 0.0 ? MathAbs(open - sl) : TickSize() * 80.0);
   double arrowPrice = SignalArrowPrice(t, dir, open, risk);
   double pad = MathMax(MathMax(risk, TickSize() * 30.0) * 0.25, TickSize() * 35.0);
   color clr = dir > 0 ? C'60,220,140' : C'255,80,110';
   string id = IntegerToString((int)ticket);
   string arrowName = PFX + "LV_ARROW_" + id;
   if(ObjectFind(0, arrowName) < 0)
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, t, arrowPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_TIME, t);
   ObjectSetDouble(0, arrowName, OBJPROP_PRICE, arrowPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, dir > 0 ? 233 : 234);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arrowName, OBJPROP_ZORDER, DASH_Z + 2);

   string txtName = PFX + "LV_TXT_" + id;
   double txtPrice = dir > 0 ? arrowPrice - pad : arrowPrice + pad;
   if(ObjectFind(0, txtName) < 0)
      ObjectCreate(0, txtName, OBJ_TEXT, 0, t, txtPrice);
   ObjectSetInteger(0, txtName, OBJPROP_TIME, t);
   ObjectSetDouble(0, txtName, OBJPROP_PRICE, txtPrice);
   string txt = "LIVE " + DirLabel(dir) + " #" + id + "\nEntry " + DoubleToString(open, _Digits);
   if(sl > 0.0) txt += "\nSL " + DoubleToString(sl, _Digits);
   if(tp > 0.0) txt += "\nTP " + DoubleToString(tp, _Digits);
   ObjectSetString(0, txtName, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, txtName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, txtName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, txtName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, txtName, OBJPROP_ZORDER, DASH_Z + 2);
}

string LiveObjectTicketToken(string name)
{
   string p;
   p = PFX + "LV_ENTRY_";
   if(StringFind(name, p) == 0) return StringSubstr(name, StringLen(p));
   p = PFX + "LV_SL_";
   if(StringFind(name, p) == 0) return StringSubstr(name, StringLen(p));
   p = PFX + "LV_TP_";
   if(StringFind(name, p) == 0) return StringSubstr(name, StringLen(p));
   p = PFX + "LV_ARROW_";
   if(StringFind(name, p) == 0) return StringSubstr(name, StringLen(p));
   p = PFX + "LV_TXT_";
   if(StringFind(name, p) == 0) return StringSubstr(name, StringLen(p));
   return "";
}

void DeleteStaleLiveLevelObjects(string activeTicketKeys)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PFX + "LV_") != 0) continue;
      string token = LiveObjectTicketToken(name);
      if(token == "" || StringFind(activeTicketKeys, "|" + token + "|") < 0)
         ObjectDelete(0, name);
   }
}

void DrawLiveLevelsForPosition()
{
   if(IsTesterMode()) return;
   if(!InpDrawLiveLevels)
   {
      DeleteByPrefix(PFX + "LV_");
      g_liveLevelsSignature = "";
      return;
   }

   ulong newestTicket = 0;
   datetime newestTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      datetime openedAt = (datetime)PositionGetInteger(POSITION_TIME);
      if(openedAt >= newestTime)
      {
         newestTime = openedAt;
         newestTicket = ticket;
      }
   }

   string activeTicketKeys = "|";
   if(newestTicket > 0 && PositionSelectByTicket(newestTicket))
   {
      string ticketText = IntegerToString((int)newestTicket);
      activeTicketKeys += ticketText + "|";
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      datetime openedAt = (datetime)PositionGetInteger(POSITION_TIME);
      int segSec = MathMax(60, PeriodSeconds(g_entryTf)) * 20;
      datetime liveEnd = TimeCurrent() + segSec;
      if(liveEnd <= openedAt) liveEnd = openedAt + segSec;
      DrawLiveLevelSegment("LV_ENTRY_" + ticketText, openedAt, liveEnd, open, C'245,245,255', STYLE_SOLID, 4);
      if(sl > 0)
         DrawLiveLevelSegment("LV_SL_" + ticketText, openedAt, liveEnd, sl, C'255,40,70', STYLE_SOLID, 4);
      else
         ObjectDelete(0, PFX + "LV_SL_" + ticketText);
      if(tp > 0)
         DrawLiveLevelSegment("LV_TP_" + ticketText, openedAt, liveEnd, tp, C'20,255,160', STYLE_SOLID, 4);
      else
         ObjectDelete(0, PFX + "LV_TP_" + ticketText);
      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      DrawLivePositionMarker(newestTicket, openedAt, open, sl, tp, dir);
   }
   DeleteStaleLiveLevelObjects(activeTicketKeys);
   g_liveLevelsSignature = activeTicketKeys;
}

//=====================================================================
//  LIVE EXECUTION AND POSITION MANAGEMENT
//=====================================================================
string TicketKey(ulong ticket, string field)
{
   return "LIQNARR|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + IntegerToString((int)ticket) + "|" + field;
}

void CopyPlanField(ulong fromTicket, ulong toTicket, string field)
{
   string fromKey = TicketKey(fromTicket, field);
   if(GlobalVariableCheck(fromKey))
      GlobalVariableSet(TicketKey(toTicket, field), GlobalVariableGet(fromKey));
}

void CopyPlanState(ulong fromTicket, ulong toTicket)
{
   if(fromTicket == 0 || toTicket == 0 || fromTicket == toTicket) return;
   string fields[] = {"entry","sl","tp1","tp2","tp3","tp4","tp5","tp6","hc","halfDone","openTs","dir","target","targetPips","lossPips","mfePips","maePips","mfeMoney","maeMoney","mfePx","maePx","mfeTs","maeTs","firstTargetTs","firstLossTs","reverseCount"};
   for(int i = 0; i < ArraySize(fields); ++i)
      CopyPlanField(fromTicket, toTicket, fields[i]);
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
   GlobalVariableSet(TicketKey(ticket, "openTs"), (double)TimeCurrent());
   GlobalVariableSet(TicketKey(ticket, "dir"), (double)sig.dir);
   double selectedTp = SelectedTarget(sig, g_target);
   double pip = PipSize();
   double targetPips = pip > 0.0 ? MathAbs(selectedTp - sig.entry) / pip : 0.0;
   double lossPips = pip > 0.0 ? MathAbs(sig.entry - sig.sl) / pip : 0.0;
   GlobalVariableSet(TicketKey(ticket, "target"), selectedTp);
   GlobalVariableSet(TicketKey(ticket, "targetPips"), targetPips);
   GlobalVariableSet(TicketKey(ticket, "lossPips"), lossPips);
   GlobalVariableSet(TicketKey(ticket, "mfePips"), 0.0);
   GlobalVariableSet(TicketKey(ticket, "maePips"), 0.0);
   GlobalVariableSet(TicketKey(ticket, "mfeMoney"), 0.0);
   GlobalVariableSet(TicketKey(ticket, "maeMoney"), 0.0);
   GlobalVariableSet(TicketKey(ticket, "mfePx"), sig.entry);
   GlobalVariableSet(TicketKey(ticket, "maePx"), sig.entry);
   GlobalVariableSet(TicketKey(ticket, "mfeTs"), (double)TimeCurrent());
   GlobalVariableSet(TicketKey(ticket, "maeTs"), (double)TimeCurrent());
   GlobalVariableSet(TicketKey(ticket, "firstTargetTs"), 0.0);
   GlobalVariableSet(TicketKey(ticket, "firstLossTs"), 0.0);
   GlobalVariableSet(TicketKey(ticket, "reverseCount"), 0.0);
   UpdatePositionLifecycle(ticket);
   if(PositionSelectByTicket(ticket))
   {
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(posId > 0 && posId != ticket)
         CopyPlanState(ticket, posId);
   }
}

double GetPlan(ulong ticket, string field, double fallback = 0.0)
{
   string key = TicketKey(ticket, field);
   if(!GlobalVariableCheck(key)) return fallback;
   return GlobalVariableGet(key);
}


void SetPlan(ulong ticket, string field, double value)
{
   GlobalVariableSet(TicketKey(ticket, field), value);
}

string MlTime(datetime t)
{
   if(t <= 0) return "";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

void UpdatePositionLifecycle(ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return;
   if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double pip = PipSize();
   if(pip <= 0.0) return;
   int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   double entry = GetPlan(ticket, "entry", PositionGetDouble(POSITION_PRICE_OPEN));
   if(entry <= 0.0) entry = PositionGetDouble(POSITION_PRICE_OPEN);
   if(GetPlan(ticket, "openTs", 0.0) <= 0.0) SetPlan(ticket, "openTs", (double)(datetime)PositionGetInteger(POSITION_TIME));
   if(GetPlan(ticket, "dir", 0.0) == 0.0) SetPlan(ticket, "dir", (double)dir);
   double px = dir > 0 ? tick.bid : tick.ask;
   double signedPips = dir > 0 ? (px - entry) / pip : (entry - px) / pip;
   double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   datetime now = TimeCurrent();
   bool mfeInit = GetPlan(ticket, "mfeTs", 0.0) <= 0.0;
   bool maeInit = GetPlan(ticket, "maeTs", 0.0) <= 0.0;
   double oldMfe = GetPlan(ticket, "mfePips", signedPips);
   double oldMae = GetPlan(ticket, "maePips", signedPips);
   if(mfeInit || signedPips > oldMfe)
   {
      SetPlan(ticket, "mfePips", signedPips);
      SetPlan(ticket, "mfeMoney", pnl);
      SetPlan(ticket, "mfePx", px);
      SetPlan(ticket, "mfeTs", (double)now);
   }
   if(maeInit || signedPips < oldMae)
   {
      SetPlan(ticket, "maePips", signedPips);
      SetPlan(ticket, "maeMoney", pnl);
      SetPlan(ticket, "maePx", px);
      SetPlan(ticket, "maeTs", (double)now);
   }
   double targetPips = GetPlan(ticket, "targetPips", 0.0);
   double lossPips = GetPlan(ticket, "lossPips", 0.0);
   if(targetPips > 0.0 && GetPlan(ticket, "firstTargetTs", 0.0) <= 0.0 && signedPips >= targetPips)
      SetPlan(ticket, "firstTargetTs", (double)now);
   if(lossPips > 0.0 && GetPlan(ticket, "firstLossTs", 0.0) <= 0.0 && signedPips <= -lossPips)
      SetPlan(ticket, "firstLossTs", (double)now);
   ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(posId > 0 && posId != ticket)
      CopyPlanState(ticket, posId);
}

void UpdateOpenPositionLifecycleStates()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      UpdatePositionLifecycle(ticket);
   }
}

string PositionLifecycleDetail(ulong ticket, string closeReason, double closePnl, bool countReverse)
{
   if(ticket == 0) return "ml_state=missing_ticket";
   if(PositionSelectByTicket(ticket)) UpdatePositionLifecycle(ticket);
   if(countReverse) SetPlan(ticket, "reverseCount", GetPlan(ticket, "reverseCount", 0.0) + 1.0);
   double openTs = GetPlan(ticket, "openTs", 0.0);
   double duration = openTs > 0.0 ? MathMax(0.0, (double)(TimeCurrent() - (datetime)openTs)) : 0.0;
   double mfe = GetPlan(ticket, "mfePips", 0.0);
   double mae = GetPlan(ticket, "maePips", 0.0);
   double targetTs = GetPlan(ticket, "firstTargetTs", 0.0);
   double lossTs = GetPlan(ticket, "firstLossTs", 0.0);
   string first = "none";
   if(targetTs > 0.0 && lossTs > 0.0) first = targetTs <= lossTs ? "target" : "loss";
   else if(targetTs > 0.0) first = "target";
   else if(lossTs > 0.0) first = "loss";
   return "ml=1 close_reason=" + closeReason
      + " position_id=" + IntegerToString((int)ticket)
      + " entry=" + DoubleToString(GetPlan(ticket, "entry", 0.0), _Digits)
      + " dir=" + DoubleToString(GetPlan(ticket, "dir", 0.0), 0)
      + " duration_sec=" + DoubleToString(duration, 0)
      + " close_pnl=" + DoubleToString(closePnl, 2)
      + " target_pips=" + DoubleToString(GetPlan(ticket, "targetPips", 0.0), 2)
      + " max_loss_pips=" + DoubleToString(GetPlan(ticket, "lossPips", 0.0), 2)
      + " mfe_pips=" + DoubleToString(MathMax(0.0, mfe), 2)
      + " mae_pips=" + DoubleToString(MathMax(0.0, -mae), 2)
      + " mfe_signed_pips=" + DoubleToString(mfe, 2)
      + " mae_signed_pips=" + DoubleToString(mae, 2)
      + " mfe_money=" + DoubleToString(GetPlan(ticket, "mfeMoney", 0.0), 2)
      + " mae_money=" + DoubleToString(GetPlan(ticket, "maeMoney", 0.0), 2)
      + " mfe_price=" + DoubleToString(GetPlan(ticket, "mfePx", 0.0), _Digits)
      + " mae_price=" + DoubleToString(GetPlan(ticket, "maePx", 0.0), _Digits)
      + " first_target_hit=" + (targetTs > 0.0 ? "1" : "0")
      + " first_loss_hit=" + (lossTs > 0.0 ? "1" : "0")
      + " first_hit=" + first
      + " target_hit_time=" + MlTime((datetime)targetTs)
      + " loss_hit_time=" + MlTime((datetime)lossTs)
      + " mfe_time=" + MlTime((datetime)GetPlan(ticket, "mfeTs", 0.0))
      + " mae_time=" + MlTime((datetime)GetPlan(ticket, "maeTs", 0.0))
      + " reverse_signal_count=" + DoubleToString(GetPlan(ticket, "reverseCount", 0.0), 0);
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

bool CloseOwnPositions(int dirFilter = 0)
{
   bool allClosed = true;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))) continue;
      int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      if(dirFilter != 0 && dirFilter != dir) continue;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      string lifecycle = PositionLifecycleDetail(ticket, "manual_or_reverse", PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP), dirFilter != 0);
      bool closed = trade.PositionClose(ticket);
      allClosed = allClosed && closed;
      AuditWrite(closed ? "close_request" : "close_failed", IntegerToString((int)ticket), dir,
         open, sl, tp, volume, "manual_or_reverse " + lifecycle);
   }
   return allClosed;
}

void AppendDetail(string &detail, string part)
{
   if(part == "") return;
   if(detail != "") detail += " | ";
   detail += part;
}

string ExecutionGeometryDetail(const ErlSignal &sig, double orderSl, double orderTp)
{
   double pip = PipSize();
   double slPips = (pip > 0.0 && orderSl > 0.0) ? MathAbs(sig.entry - orderSl) / pip : 0.0;
   double tpPips = (pip > 0.0 && orderTp > 0.0) ? MathAbs(orderTp - sig.entry) / pip : 0.0;
   double rr = (slPips > 0.0 && tpPips > 0.0) ? tpPips / slPips : 0.0;
   return "target_model=" + TargetModelLabel(g_targetModel)
      + " target=" + TargetLabel(g_target)
      + " invert=" + (g_invertMode ? "ON" : "OFF")
      + " pure_swap=" + (sig.invertedGeometry ? "1" : "0")
      + " pip_sl=" + (g_pipSlMode ? "ON" : "OFF")
      + " pip_sl_pips=" + DoubleToString(g_pipSlPips, 2)
      + " pip_size=" + DoubleToString(pip, _Digits)
      + " sl_pips=" + DoubleToString(slPips, 2)
      + " tp_pips=" + DoubleToString(tpPips, 2)
      + " rr=" + DoubleToString(rr, 2);
}
bool BuildExecutableSignal(const ErlSignal &raw, double liveEntry, ErlSignal &execSig, string &detail)
{
   execSig = raw;
   detail = "";
   double minStop = MinStopDistance() * 1.20;
   execSig.entry = NormTradePrice(liveEntry);
   execSig.sl = NormTradePrice(raw.sl);
   execSig.targetOverride = 0.0;
   execSig.invertedGeometry = false;
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

   execSig.sl = ApplyRuntimeSlDistance(execSig.dir, execSig.entry, execSig.sl);
   execSig.risk = MathAbs(execSig.entry - execSig.sl);
   if(execSig.risk <= TickSize())
   {
      detail = "source_risk_invalid";
      return false;
   }
   SetSignalTargetLadder(execSig);

   if(MathAbs(originalSl - execSig.sl) > TickSize() * 0.5)
      AppendDetail(detail, "broker_stop_adjusted original_sl=" + DoubleToString(originalSl, _Digits)
         + " adjusted_sl=" + DoubleToString(execSig.sl, _Digits));

   if(g_invertMode)
   {
      ErlSignal inverted;
      string invertDetail = "";
      if(!ApplyFullInversionGeometry(execSig, g_target, g_targetModel, inverted, invertDetail))
      {
         AppendDetail(detail, invertDetail);
         return false;
      }
      double invStopDistance = MathAbs(inverted.entry - inverted.sl);
      double invTargetDistance = MathAbs(inverted.targetOverride - inverted.entry);
      if(invStopDistance < minStop || invTargetDistance < MinStopDistance())
      {
         AppendDetail(detail, "full_invert_broker_min_distance_fail"
            + " sl_dist=" + DoubleToString(invStopDistance, _Digits)
            + " tp_dist=" + DoubleToString(invTargetDistance, _Digits)
            + " min=" + DoubleToString(MinStopDistance(), _Digits));
         return false;
      }
      execSig = inverted;
      AppendDetail(detail, invertDetail);
   }
   return true;
}
uint SignalEventHash(string value)
{
   uint h = 2166136261;
   for(int i = 0; i < StringLen(value); ++i)
   {
      h ^= (uint)StringGetCharacter(value, i);
      h *= 16777619;
   }
   return h;
}

string SignalClaimKey(const string eventId)
{
   // Advanced regime decisions must not claim the base SolVersion event.
   return "LIQN_SOL_ADV_EVT|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))
      + "|" + IntegerToString((int)InpMagic)
      + "|" + _Symbol
      + "|" + IntegerToString((int)SignalEventHash(eventId));
}

bool IsSignalEventClaimed(const string eventId)
{
   return GlobalVariableCheck(SignalClaimKey(eventId));
}

void MarkSignalEventClaimed(const string eventId)
{
   if(eventId == "") return;
   GlobalVariableSet(SignalClaimKey(eventId), (double)TimeCurrent());
}

void RememberSignalSeen(const ErlSignal &sig)
{
   g_lastSignalId = sig.id;
   g_lastSignalTime = sig.availableTime;
   g_lastSignalDir = EffectiveTradeDir(sig.dir);
}

void MergeLatestSignalIntoHistoricalCache(const ErlSignal &sig)
{
   if(!sig.valid || sig.id == "") return;
   for(int i = 0; i < ArraySize(g_histRawCache); ++i)
   {
      if(g_histRawCache[i].id != sig.id) continue;
      g_histRawCache[i] = sig;
      return;
   }

   int n = ArraySize(g_histRawCache);
   ArrayResize(g_histRawCache, n + 1);
   g_histRawCache[n] = sig;
}

void RefreshHistoricalLifecycleFromLiveScan(const ErlSignal &rawSignals[])
{
   int count = ArraySize(rawSignals);
   if(count > 0) MergeLatestSignalIntoHistoricalCache(rawSignals[count - 1]);

   // Closed simulations remain cached; only DATA/OPEN rows are replayed.
   // This keeps a live signal moving DATA/O -> W/L without rebuilding 1Y.
   RecalculateHistoricalStats(false);
   g_lastHistLifecycleRefresh = TimeCurrent();
   if(!IsTesterMode()) DrawHistoricalSignals(false);
}

void RefreshUnresolvedHistoricalLifecycle()
{
   int count = ArraySize(g_histSignals);
   if(count <= 0) return;
   int last = count - 1;
   if(g_histSignalValid[last] && g_histSignalClosed[last]) return;
   if(g_histSignals[last].availableTime < TimeCurrent() - 7 * 86400) return;
   if(TimeCurrent() - g_lastHistLifecycleRefresh < 60) return;

   RecalculateHistoricalStats(false);
   g_lastHistLifecycleRefresh = TimeCurrent();
   if(!IsTesterMode()) DrawHistoricalSignals(false);
}

bool HandleRegimeRejectedSignal(const ErlSignal &sig, string rule)
{
   if(sig.id == "") return false;
   if(sig.id == g_lastSignalId || IsSignalEventClaimed(sig.id))
   {
      RememberSignalSeen(sig);
      return true;
   }

   bool reverseExitEnabled = InpCloseOnReverse || g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL;
   int rejectedExecDir = EffectiveTradeDir(sig.dir);
   int closeDir = -rejectedExecDir;
   bool bridgeOk = true;
   if(reverseExitEnabled && g_fileBridgeEnabled)
      bridgeOk = FileBridgeWriteRegimeCloseOnly(sig, rule);

   bool localOk = true;
   if(reverseExitEnabled && OwnPositionCount(closeDir) > 0)
      localOk = CloseOwnPositions(closeDir) && OwnPositionCount(closeDir) == 0;

   string regimeDecisionDetail = "state=UNAVAILABLE";
   RegimeV3Snapshot decisionState;
   if(RegimeV3SnapshotAt(sig.availableTime, decisionState))
      regimeDecisionDetail = "state=" + decisionState.core + "/" + decisionState.h1h2Phase + "/"
         + decisionState.macroDirection + "/" + decisionState.transitionStatus
         + " state_available=" + TimeToString(decisionState.availableTime, TIME_DATE|TIME_MINUTES);
   string detail = "rule=" + rule + " " + regimeDecisionDetail
      + " bridge_close=" + (bridgeOk ? "1" : "0")
      + " local_close=" + (localOk ? "1" : "0")
      + " reverse_exit=" + (reverseExitEnabled ? "1" : "0")
      + " raw_dir=" + DirLabel(sig.dir)
      + " exec_dir=" + DirLabel(rejectedExecDir)
      + " invert=" + (g_invertMode ? "1" : "0");
   if(!bridgeOk || !localOk)
   {
      g_lastStatus = "FILTER CLOSE RETRY";
      g_lastBlock = !bridgeOk ? "regime_close_publish_failed" : "regime_close_local_failed";
      AuditWrite("regime_filter_close_failed", sig.id, sig.dir, sig.entry, 0.0, 0.0, 0.0, detail);
      return false;
   }

   MarkSignalEventClaimed(sig.id);
   RememberSignalSeen(sig);
   g_lastStatus = "FILTERED " + rule;
   g_lastBlock = "regime_filter";
   AuditWrite("regime_filter_entry_rejected", sig.id, sig.dir, sig.entry, 0.0, 0.0, 0.0, detail);
   Print("LiqNarrativeSol regime_filter rejected id=", sig.id, " dir=", DirLabel(sig.dir), " ", detail);
   return true;
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
   if(IsSignalEventClaimed(sig.id))
   {
      RememberSignalSeen(sig);
      g_lastBlock = "claimed_signal";
      AuditWrite("claimed_signal_skip", sig.id, EffectiveTradeDir(sig.dir), sig.entry, sig.sl,
         SelectedTarget(sig, g_target), 0.0, "event_already_claimed_after_restart");
      return false;
   }
   bool reverseExitMode = (g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL);
   if(g_invertMode && reverseExitMode)
   {
      g_lastBlock = "full_invert_unsupported_reverse_target";
      AuditWrite("invert_geometry_block", sig.id, EffectiveTradeDir(sig.dir), sig.entry, 0.0, 0.0, 0.0, g_lastBlock);
      return false;
   }

   int requestedDir = EffectiveTradeDir(sig.dir);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   g_lastSpreadPts = CurrentSpreadPoints();
   double liveEntry = requestedDir > 0 ? tick.ask : tick.bid;
   ErlSignal execSig;
   string execDetail = "";
   if(!BuildExecutableSignal(sig, liveEntry, execSig, execDetail))
   {
      g_lastStatus = "INV GEOMETRY BLOCK";
      g_lastBlock = execDetail;
      AuditWrite("execution_geometry_block", sig.id, requestedDir, liveEntry, 0.0, 0.0, 0.0,
         "raw_dir=" + DirLabel(sig.dir) + " exec_dir=" + DirLabel(requestedDir) + " " + execDetail);
      return false;
   }

   double tp = SelectedTarget(execSig, g_target);
   double orderSl = reverseExitMode ? 0.0 : execSig.sl;
   double orderTp = reverseExitMode ? 0.0 : tp;
   ERL_HC_MODE effectiveHc = reverseExitMode ? ERL_HC_OFF : EffectiveHalfModeForSignal(execSig, g_hc, g_target, g_targetModel);
   double bridgeHalf = effectiveHc == ERL_HC_OFF ? 0.0 : HalfTrigger(execSig, effectiveHc);
   string bridgeHalfLabel = (effectiveHc == ERL_HC_OFF || bridgeHalf <= 0.0) ? "off" : HcLabel(effectiveHc);
   bool bridgeWritten = false;
   if(g_fileBridgeEnabled)
   {
      bridgeWritten = FileBridgeWriteSignal(execSig, execSig.entry, orderSl, orderTp, bridgeHalf, bridgeHalfLabel);
      if(bridgeWritten) MarkSignalEventClaimed(sig.id);
   }
   if(g_fileBridgeOnlyMode)
   {
      if(!g_nativeTradeWithBridgeOnly)
      {
         if(!g_fileBridgeEnabled || !bridgeWritten)
         {
            g_lastBlock = "file_bridge_write_failed";
            AuditWrite("bridge_only_failed", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, 0.0, execDetail);
            return false;
         }
         RememberSignalSeen(sig);
         g_lastEntry = execSig.entry;
         g_lastSl = orderSl;
         g_lastTp = orderTp;
         g_lastStatus = "BRIDGE_PUBLISHED";
         g_lastBlock = "";
         AuditWrite("bridge_published_only", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, 0.0, execDetail);
         return true;
      }
      if(!g_fileBridgeEnabled || !bridgeWritten)
         AuditWrite("bridge_only_native_continue_bridge_failed", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, 0.0, execDetail);
      else
         AuditWrite("bridge_published_native_continue", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, 0.0, execDetail);
   }

   if(!g_allowDuplicateEntries && InpBlockSameDirection && OwnPositionCount(execSig.dir) > 0)
   {
      g_lastBlock = "same_direction_position";
      AuditWrite("local_same_direction_after_bridge", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, 0.0,
         execDetail + " bridge_written=" + (bridgeWritten ? "1" : "0"));
      return false;
   }
   if((InpCloseOnReverse || reverseExitMode) && OwnPositionCount(-execSig.dir) > 0)
   {
      if(!CloseOwnPositions(-execSig.dir) || OwnPositionCount(-execSig.dir) > 0)
      {
         g_lastBlock = "reverse_close_failed";
         AuditWrite("local_reverse_close_failed_after_bridge", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, 0.0,
            execDetail + " bridge_written=" + (bridgeWritten ? "1" : "0"));
         Print("LiqNarrativeSol reverse_close_failed dir=", DirLabel(execSig.dir), " id=", sig.id,
            " bridge_written=", (bridgeWritten ? "1" : "0"));
         return false;
      }
   }

   double lot = 0.0;
   string riskReason = "";
   if(!RiskGateAllows(execSig.entry, execSig.sl, lot, riskReason))
   {
      g_lastBlock = riskReason;
      AuditWrite("risk_block", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, lot, riskReason + " " + execDetail);
      Print("LiqNarrativeSol risk_block id=", sig.id, " dir=", DirLabel(execSig.dir),
         " entry=", DoubleToString(execSig.entry, _Digits), " sl=", DoubleToString(execSig.sl, _Digits),
         " reason=", riskReason);
      return false;
   }
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = trade.PositionOpen(_Symbol, execSig.dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot,
      execSig.entry, orderSl, orderTp, "LiqNarrativeSol " + DirLabel(execSig.dir));
   if(!ok)
   {
      string detail = "ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription();
      g_lastStatus = "ORDER_FAILED";
      g_lastBlock = detail;
      AuditWrite("order_failed", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, lot, detail + " " + execDetail);
      Print("LiqNarrativeSol order_failed id=", sig.id, " dir=", DirLabel(execSig.dir),
         " ret=", IntegerToString((int)trade.ResultRetcode()), " ", trade.ResultRetcodeDescription());
      return false;
   }

   ulong posTicket = FindNewestOwnPosition();
   if(posTicket > 0)
   {
      if(!reverseExitMode && PositionSelectByTicket(posTicket))
      {
         double brokerSl = PositionGetDouble(POSITION_SL);
         double brokerTp = PositionGetDouble(POSITION_TP);
         double tickSize = TickSize();
         bool slMismatch = (orderSl > 0.0 && MathAbs(brokerSl - orderSl) > tickSize * 0.5);
         bool tpMismatch = (orderTp > 0.0 && MathAbs(brokerTp - orderTp) > tickSize * 0.5);
         if(slMismatch || tpMismatch)
         {
            bool modOk = trade.PositionModify(posTicket, orderSl, orderTp);
            AuditWrite(modOk ? "position_level_sync_done" : "position_level_sync_failed", sig.id, execSig.dir,
               execSig.entry, orderSl, orderTp, lot,
               "broker_sl=" + DoubleToString(brokerSl, _Digits) + " broker_tp=" + DoubleToString(brokerTp, _Digits)
               + " requested_sl=" + DoubleToString(orderSl, _Digits) + " requested_tp=" + DoubleToString(orderTp, _Digits)
               + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription()
               + " " + ExecutionGeometryDetail(execSig, orderSl, orderTp));
         }
      }
      StorePositionPlan(posTicket, execSig, effectiveHc);
   }
   MarkSignalEventClaimed(sig.id);
   RememberSignalSeen(sig);
   g_lastEntry = execSig.entry;
   g_lastSl = orderSl;
   g_lastTp = orderTp;
   g_lastStatus = "OPENED";
   g_lastBlock = "";
   AuditWrite("order_opened", sig.id, execSig.dir, execSig.entry, orderSl, orderTp, lot,
      "raw_dir=" + DirLabel(sig.dir) + " exec_dir=" + DirLabel(execSig.dir)
      + " signal_entry=" + DoubleToString(sig.entry, _Digits)
      + " ticket=" + IntegerToString((int)posTicket)
      + " risk_ref_sl=" + DoubleToString(execSig.sl, _Digits)
      + " " + ExecutionGeometryDetail(execSig, orderSl, orderTp) + " " + execDetail);
   Print("LiqNarrativeSol order_opened id=", sig.id,
      " raw_dir=", DirLabel(sig.dir), " exec_dir=", DirLabel(execSig.dir),
      " ticket=", IntegerToString((int)posTicket), " entry=", DoubleToString(execSig.entry, _Digits),
      " sl=", DoubleToString(orderSl, _Digits), " tp=", DoubleToString(orderTp, _Digits),
      " lot=", DoubleToString(lot, 4));
   return true;
}
void TryOpenLatestSignal()
{
   datetime closedBarTime = iTime(_Symbol, g_entryTf, 1);
   if(closedBarTime <= 0) return;
   datetime now = TimeCurrent();
   bool firstAttemptForBar = (closedBarTime != g_lastLiveScanBar);
   int entrySec = MathMax(60, PeriodSeconds(g_entryTf));
   datetime retryUntil = closedBarTime + entrySec + 90;
   if(!firstAttemptForBar)
   {
      // MT5 can briefly expose the new bar before every dependent timeframe is
      // synchronized. Retry the just-closed entry bar without rescanning it for
      // the full candle duration.
      if(now > retryUntil) return;
      if(now - g_lastLiveScanAttempt < 5) return;
   }
   g_lastLiveScanBar = closedBarTime;
   g_lastLiveScanAttempt = now;

   datetime cutoff = now - 7 * 86400;
   ErlSignal signals[];
   int count = BuildSignals(g_htf, g_entryTf, g_swingLookback, g_weeklyBias, g_entryModel, g_stopModel, g_targetModel, g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg, g_requireAsiaLiquidityDraw, g_useAsiaLiquidityTarget, g_requireSmt, cutoff, signals);
   if(firstAttemptForBar)
      RefreshHistoricalLifecycleFromLiveScan(signals);

   ErlSignal rawLatest;
   bool hasRawLatest = ArraySize(signals) > 0;
   if(hasRawLatest) rawLatest = signals[ArraySize(signals) - 1];
   bool macroRejected = false;
   string macroRule = "";
   bool macroClassified = hasRawLatest && LiqMacroRegimeDecision(rawLatest, macroRejected, macroRule);

   // A signal blocked by the primary macro regime never enters RF01-RF12.
   ApplyLiqMacroRegimeFilter(signals);
   if(macroClassified && macroRejected)
   {
      int freshSec = MathMax(entrySec * 2, 180);
      if(now - rawLatest.availableTime <= freshSec)
         HandleRegimeRejectedSignal(rawLatest, macroRule);
      else
         RememberSignalSeen(rawLatest);
      return;
   }

   bool latestRejected = false;
   string latestRejectRule = "";
   bool latestClassified = hasRawLatest && SolRegimeFilterDecision(rawLatest, latestRejected, latestRejectRule);
   ApplySolRegimeFilter(signals);
   if(latestClassified && latestRejected)
   {
      int freshSec = MathMax(entrySec * 2, 180);
      if(now - rawLatest.availableTime <= freshSec)
         HandleRegimeRejectedSignal(rawLatest, latestRejectRule);
      else
         RememberSignalSeen(rawLatest);
      return;
   }
   if(!g_allowDuplicateEntries) FilterAlternatingSignals(signals);
   count = ArraySize(signals);
   if(count <= 0)
   {
      g_lastStatus = "NO_SIGNAL";
      return;
   }
   ErlSignal latest = signals[count - 1];
   if(latest.availableTime <= g_lastSignalTime && latest.id == g_lastSignalId) return;
   // Only live-trade fresh signals; historical chart load must not open old setups.
   int freshSec = MathMax(entrySec * 2, 180);
   if(now - latest.availableTime > freshSec)
   {
      g_lastStatus = "LATEST_OLD";
      g_lastSignalTime = MathMax(g_lastSignalTime, latest.availableTime);
      g_lastSignalId = latest.id;
      return;
   }
   Print("LiqNarrativeSol signal_candidate id=", latest.id, " dir=", DirLabel(latest.dir),
      " setup_bar=", TimeToString(latest.entryTime, TIME_DATE | TIME_SECONDS),
      " available=", TimeToString(latest.availableTime, TIME_DATE | TIME_SECONDS),
      " detected=", TimeToString(now, TIME_DATE | TIME_SECONDS));
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

      UpdatePositionLifecycle(ticket);
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
   ENUM_TIMEFRAMES htfs[] = { PERIOD_H1, LN_PERIOD_H90, PERIOD_H2, PERIOD_H4, PERIOD_D1 };
   ENUM_TIMEFRAMES etfs[] = { PERIOD_M15, PERIOD_M30, PERIOD_H1 };
   int swings[] = { 3, 5, 8 };
   bool biases[] = { false, true };
   ERL_ENTRY_MODEL entryModels[] = { ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG, ERL_ENTRY_LEGACY_HTF_FVG_TAP };
   ERL_STOP_MODEL stopModels[] = { ERL_STOP_FIRST_FVG_CANDLE, ERL_STOP_FVG_BOUNDARY };
   ERL_TARGET_MODEL targetModels[] = { ERL_TARGET_NEXT_EXTERNAL, ERL_TARGET_AUTO_STOP_SIZE, ERL_TARGET_FIXED_R, ERL_TARGET_OPPOSITE_SIGNAL };
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
                           int maxHc = targetModels[tm] == ERL_TARGET_OPPOSITE_SIGNAL ? 0 : (rr == 0 ? 0 : rr);
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
                              g_btCombos[n].requireAsiaLiquidityDraw = g_requireAsiaLiquidityDraw;
                              g_btCombos[n].useAsiaLiquidityTarget = g_useAsiaLiquidityTarget;
                              g_btCombos[n].requireSmt = g_requireSmt;
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
   return FileWrite(h, "timestamp", "symbol", "htf", "entry_tf", "swing", "entry_model", "stop_model", "target_model", "strictness", "narrative",
      "full_invert", "target", "hc_be", "weekly_bias", "weeks",
      "total", "wins", "losses", "open", "data_gaps", "win_rate", "net_r", "won_r", "lost_r", "pf", "avg_r") > 0;
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
      g_btSpreadPts = MathMax(0.0, StringToDouble(ObjectGetString(0, spreadEdit, OBJPROP_TEXT)));
   if(ObjectFind(0, slipEdit) >= 0) g_btSlippagePts = MathMax(0.0, StringToDouble(ObjectGetString(0, slipEdit, OBJPROP_TEXT)));
   if(ObjectFind(0, commEdit) >= 0) g_btCommissionPerLot = MathMax(0.0, StringToDouble(ObjectGetString(0, commEdit, OBJPROP_TEXT)));
   BuildCombos();
   g_btStep = 0;
   g_btRunning = true;
   g_btStartMs = GetTickCount();
   g_btElapsedMs = 0;
   g_btCutoff = TimeCurrent() - g_btWeeks * 7 * 86400;
   g_btLastResult = "Starting";
   g_btFileName = "LiqNarrativeSol_BruteBacktest_" + FileStamp(TimeCurrent()) + ".csv";
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
      BuildSignals(c.htf, c.entryTf, c.swing, c.bias, c.entryModel, c.stopModel, c.targetModel, c.requireIrlTouch, c.requireEntrySweep, c.requireDisplacementFvg, c.requireAsiaLiquidityDraw, c.useAsiaLiquidityTarget, c.requireSmt, cutoff, signals);
      ErlSignal exitSignals[];
      CopySignalArray(signals, exitSignals);
      ApplyLiqMacroRegimeFilter(signals);
      ApplySolRegimeFilter(signals);
      SimStats st = CalculateStats(signals, exitSignals, c.target, c.hc, c.targetModel, c.entryTf);
      double resolved = st.wins + st.losses;
      double wr = resolved > 0 ? (double)st.wins / resolved * 100.0 : 0.0;
      double avg = (st.total - st.invalid) > 0 ? st.netR / (st.total - st.invalid) : 0.0;
      FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), _Symbol, TfLabel(c.htf), TfLabel(c.entryTf),
         IntegerToString(c.swing), EntryModelLabel(c.entryModel), StopModelLabel(c.stopModel), TargetModelLabel(c.targetModel),
         StrictnessLabel(c.requireIrlTouch, c.requireEntrySweep, c.requireDisplacementFvg),
         NarrativeLabel(c.requireAsiaLiquidityDraw, c.useAsiaLiquidityTarget, c.requireSmt),
          g_invertMode ? "ON" : "OFF", TargetLabel(c.target), HcLabel(c.hc), c.bias ? "ON" : "OFF", IntegerToString(g_btWeeks),
         IntegerToString(st.total), IntegerToString(st.wins), IntegerToString(st.losses), IntegerToString(st.open), IntegerToString(st.invalid),
         DoubleToString(wr, 2), DoubleToString(st.netR, 2), DoubleToString(st.wonR, 2), DoubleToString(st.lostR, 2),
         DoubleToString(st.pf, 2), DoubleToString(avg, 3));
      g_btLastResult = TfLabel(c.htf) + " " + TfLabel(c.entryTf) + " SW" + IntegerToString(c.swing) + " "
         + EntryModelLabel(c.entryModel) + " " + StopModelLabel(c.stopModel) + " " + TargetModelLabel(c.targetModel)
         + " " + StrictnessLabel(c.requireIrlTouch, c.requireEntrySweep, c.requireDisplacementFvg)
         + " " + NarrativeLabel(c.requireAsiaLiquidityDraw, c.useAsiaLiquidityTarget, c.requireSmt)
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
      DeleteDashboardObjects();
      return;
   }
   DeleteDashboardObjects();
   int x = InpDashboardX;
   int y = InpDashboardY;
   if(g_dashboardCollapsed)
   {
      RectObj("DASH_MIN_BG", x, y, 760, 34, C'15,20,31', C'90,178,255');
      LabelObj("DASH_MIN_TITLE", x + 14, y + 10,
         "LIQ NARRATIVE // " + (g_eaEnabled ? "EA ON" : "EA OFF") + " | " + _Symbol
         + " | " + TfLabel(g_htf) + "->" + TfLabel(g_entryTf)
         + " | " + EntryModelLabel(g_entryModel) + "/" + StopModelLabel(g_stopModel) + "/" + TargetModelLabel(g_targetModel)
         + " | " + RuntimeInvertLabel()
         + " | " + NarrativeLabel(g_requireAsiaLiquidityDraw, g_useAsiaLiquidityTarget, g_requireSmt),
         g_eaEnabled ? C'80,255,180' : C'255,95,140', 9);
      ButtonObj("BTN_DASH_TOGGLE", x + 674, y + 7, 72, 20, "EXPAND", C'38,101,176');
      return;
   }
   int W = 760;
   int H = 1090;
   RectObj("DASH_BG", x, y, W, H, C'15,20,31', C'90,178,255');
   RectObj("DASH_TOP", x, y, W, 32, C'10,15,26', C'90,178,255');
   RectObj("DASH_STRIPE", x + 8, y + 7, W - 16, 3, C'90,178,255', C'90,178,255');
   LabelObj("DASH_TITLE", x + 14, y + 12, "LIQUIDITY NARRATIVE SOL // " + LN_BUILD, C'225,232,242', 10);
   ButtonObj("BTN_DASH_TOGGLE", x + 674, y + 7, 72, 20, "HIDE", C'70,72,82');
   UpdateDashboard();
}

void UpdateDashboard()
{
   if(LiqLibraryDashboard()) return;
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
      + " | " + NarrativeLabel(g_requireAsiaLiquidityDraw, g_useAsiaLiquidityTarget, g_requireSmt)
      + " | " + TargetLabel(g_target) + " | " + HcLabel(g_hc) + " | " + RuntimeInvertLabel(),
      g_eaEnabled ? C'80,255,180' : C'255,95,140', 8);

   int regY = y + 62;
   RectObj("DASH_REGIME_BG", x + 8, regY, 744, 238, C'18,27,39', C'60,110,170');
   LabelObj("DASH_REGIME_T", x + 16, regY + 7, "MARKET REGIME V3", C'90,178,255', 9);
   ButtonObj("BTN_REG_FILTER", x + 642, regY + 5, 98, bh,
      g_solRegimeFilterEnabled ? "FILTER ON" : "FILTER OFF",
      g_solRegimeFilterEnabled ? C'184,103,22' : off);
   if(!g_regimeV3.valid)
   {
      LabelObj("DASH_REGIME_CORE", x + 148, regY + 7,
         InpRegimeV3Observer ? ("CALCULATING // " + g_regimeV3.detail) : "OBSERVER OFF",
         C'255,204,82', 9);
      LabelObj("DASH_REGIME_DETAIL", x + 16, regY + 34,
         "Completed-bar observer only; execution and signal math are isolated.", muted, 8);
   }
   else
   {
      string transitionText = g_regimeV3.transitionStatus;
      if(g_regimeV3.transitionCandidate != "")
         transitionText += " -> " + g_regimeV3.transitionCandidate + " "
            + IntegerToString(g_regimeV3.transitionPending) + "/" + IntegerToString(g_regimeV3.transitionRequired);
      LabelObj("DASH_REGIME_CORE", x + 148, regY + 7,
         g_regimeV3.core + "  //  " + g_regimeV3.macroDirection,
         RegimeV3CoreColor(), 10);
      LabelObj("DASH_REGIME_TRANS", x + 470, regY + 8, transitionText, RegimeV3TransitionColor(), 8);
      LabelObj("DASH_REGIME_DETAIL", x + 16, regY + 33,
         "AGE " + g_regimeV3.ageBucket + " " + IntegerToString(g_regimeV3.effectiveAge)
         + "s | H1/H2 " + g_regimeV3.h1h2Phase
         + " | VOL " + g_regimeV3.volatilityDepth + "/" + g_regimeV3.volatilityImpulse,
         g_regimeV3.h1h2Phase == "REVERSAL_PRESSURE" ? C'255,95,140' : C'225,232,242', 8);
      LabelObj("DASH_REGIME_HINT", x + 16, regY + 52,
         "HINT " + g_regimeV3.structuralHint
         + " | T " + DoubleToString(g_regimeV3.trendDepthScore, 2)
         + " V " + DoubleToString(g_regimeV3.volatilityDepthScore, 2)
         + " | " + TimeToString(g_regimeV3.availableTime, TIME_DATE),
         RegimeV3HintColor(), 8);
   }

   LabelObj("DASH_REGIME_RF_HINT", x + 16, regY + 70,
      "RF RULES // bright = ALLOW, dark = BLOCK // W/L/WR uses the selected audit window and ignores toggle state",
      C'255,204,82', 8);
   int rfW = 236;
   for(int ri = 0; ri < SOL_ADV_RF_COUNT; ++ri)
   {
      int col = ri % 3;
      int rfRow = ri / 3;
      string text = SolRegimeRuleStatsText(ri) + (g_solRegimeRuleBlocked[ri] ? " BLOCK" : " ALLOW");
      color bg = g_solRegimeRuleBlocked[ri] ? C'42,47,57' : C'58,126,178';
      ButtonObj("BTN_REG_RF_" + IntegerToString(ri), x + 16 + col * 242, regY + 86 + rfRow * 22,
         rfW, bh, text, bg);
   }

   int currentMacroRegime = LiqMacroRegimeBucket(g_regimeV3);
   LabelObj("DASH_MACRO_HINT", x + 16, regY + 178,
      "MACRO REGIMES // exhaustive ORB buckets // independent from RF01-RF12", C'90,178,255', 8);
   int macroW = 236;
   for(int mi = 0; mi < LIQ_MACRO_REGIME_COUNT; ++mi)
   {
      int col = mi % 3;
      int macroRow = mi / 3;
      string text = (mi == currentMacroRegime ? "> " : "") + LiqMacroRegimeStatsText(mi)
         + (g_macroRegimeAllowed[mi] ? " ALLOW" : " BLOCK");
      color bg = g_macroRegimeAllowed[mi] ? C'58,126,178' : C'42,47,57';
      ButtonObj("BTN_MACRO_REG_" + IntegerToString(mi), x + 16 + col * 242, regY + 194 + macroRow * 22,
         macroW, bh, text, bg);
   }

   int sec1 = y + 308;
   RectObj("DASH_SEC1", x + 8, sec1, 744, 228, C'24,31,45', C'60,110,170');
   LabelObj("DASH_SEC1_T", x + 16, sec1 + 7, "CONTROLS", ac, 9);
   int row = sec1 + 30;
   LabelObj("DASH_HTF_L", x + 16, row + 4, "HTF:", muted, 8);
   ButtonObj("BTN_HTF_H1", x + 58, row, 40, bh, "H1", g_htf == PERIOD_H1 ? on : off);
   ButtonObj("BTN_HTF_H90", x + 102, row, 48, bh, "H1.5", g_htf == LN_PERIOD_H90 ? on : off);
   ButtonObj("BTN_HTF_H2", x + 154, row, 40, bh, "H2", g_htf == PERIOD_H2 ? on : off);
   ButtonObj("BTN_HTF_H4", x + 198, row, 40, bh, "H4", g_htf == PERIOD_H4 ? on : off);
   ButtonObj("BTN_HTF_D1", x + 242, row, 40, bh, "D1", g_htf == PERIOD_D1 ? on : off);
   LabelObj("DASH_ETF_L", x + 282, row + 4, "ENTRY:", muted, 8);
   ButtonObj("BTN_ETF_M15", x + 342, row, 58, bh, "M15", g_entryTf == PERIOD_M15 ? on : off);
   ButtonObj("BTN_ETF_M30", x + 406, row, 58, bh, "M30", g_entryTf == PERIOD_M30 ? on : off);
   ButtonObj("BTN_ETF_H1", x + 470, row, 52, bh, "H1", g_entryTf == PERIOD_H1 ? on : off);
   ButtonObj("BTN_EA", x + 530, row, 76, bh, g_eaEnabled ? "EA: ON" : "EA: OFF", g_eaEnabled ? on : C'170,45,62');
   ButtonObj("BTN_FTMO", x + 610, row, 62, bh, g_ftmoMode ? "FTMO" : "FTMO", g_ftmoMode ? on : off);
   ButtonObj("BTN_RISKLOT", x + 676, row, 68, bh, g_riskLotOnlyMode ? "RISK" : "RISK", g_riskLotOnlyMode ? on : off);

   row += 28;
   LabelObj("DASH_SW_L", x + 16, row + 4, "SWING:", muted, 8);
   ButtonObj("BTN_SW_3", x + 76, row, 44, bh, "3", g_swingLookback == 3 ? on : off);
   ButtonObj("BTN_SW_5", x + 126, row, 44, bh, "5", g_swingLookback == 5 ? on : off);
   ButtonObj("BTN_SW_8", x + 176, row, 44, bh, "8", g_swingLookback == 8 ? on : off);
   LabelObj("DASH_TP_L", x + 246, row + 4, "TARGET:", muted, 8);
   ButtonObj("BTN_R_SELECT", x + 318, row, 332, bh, "TARGET " + DoubleToString(TargetR(g_target),2) + "R  [0.05 - 5.00]", on);
   ButtonObj("BTN_CLOSE", x + 660, row, 84, bh, "CLOSE ALL", C'170,45,62');

   row += 28;
   LabelObj("DASH_HC_L", x + 16, row + 4, "HC+BE:", muted, 8);
   ButtonObj("BTN_HC_OFF", x + 76, row, 52, bh, "OFF", g_hc == ERL_HC_OFF ? on : off);
   ButtonObj("BTN_HC_TP1", x + 132, row, 54, bh, "TP1", g_hc == ERL_HC_TP1 ? on : (g_invertMode || TargetR(g_target)*2.0 > 1 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP2", x + 190, row, 54, bh, "TP2", g_hc == ERL_HC_TP2 ? on : (g_invertMode || TargetR(g_target)*2.0 > 2 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP3", x + 248, row, 54, bh, "TP3", g_hc == ERL_HC_TP3 ? on : (g_invertMode || TargetR(g_target)*2.0 > 3 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP4", x + 306, row, 54, bh, "TP4", g_hc == ERL_HC_TP4 ? on : (g_invertMode || TargetR(g_target)*2.0 > 4 ? off : C'35,37,44'));
   ButtonObj("BTN_HC_TP5", x + 364, row, 54, bh, "TP5", g_hc == ERL_HC_TP5 ? on : (g_invertMode || TargetR(g_target)*2.0 > 5 ? off : C'35,37,44'));
   LabelObj("DASH_BIAS_L", x + 430, row + 4, "WEEKLY:", muted, 8);
   ButtonObj("BTN_BIAS", x + 490, row, 68, bh, g_weeklyBias ? "ON" : "OFF", g_weeklyBias ? on : off);
   ButtonObj("BTN_DUP_ENTRY", x + 566, row, 88, bh, g_allowDuplicateEntries ? "DUP ON" : "DUP OFF", g_allowDuplicateEntries ? C'184,103,22' : off);
   ButtonObj("BTN_AUDIT", x + 660, row, 84, bh, g_auditRuntime ? "AUDIT ON" : "AUDIT OFF", g_auditRuntime ? C'120,88,25' : off);

   row += 28;
   LabelObj("DASH_EM_L", x + 16, row + 4, "ENTRY MODEL:", muted, 8);
   ButtonObj("BTN_ENTRY_PRO", x + 112, row, 62, bh, "PRO", g_entryModel == ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG ? on : off);
   ButtonObj("BTN_ENTRY_LEG", x + 180, row, 78, bh, "LEGACY", g_entryModel == ERL_ENTRY_LEGACY_HTF_FVG_TAP ? on : off);
   LabelObj("DASH_SM_L", x + 276, row + 4, "STOP:", muted, 8);
   ButtonObj("BTN_STOP_FVG1", x + 326, row, 62, bh, "FVG1", g_stopModel == ERL_STOP_FIRST_FVG_CANDLE ? on : off);
   ButtonObj("BTN_STOP_ZONE", x + 394, row, 62, bh, "ZONE", g_stopModel == ERL_STOP_FVG_BOUNDARY ? on : off);
   LabelObj("DASH_TM_L", x + 474, row + 4, "TARGET:", muted, 8);
   ButtonObj("BTN_TM_EXT", x + 528, row, 48, bh, "EXT", g_targetModel == ERL_TARGET_NEXT_EXTERNAL ? on : off);
   ButtonObj("BTN_TM_AUTO", x + 580, row, 50, bh, "AUTO", g_targetModel == ERL_TARGET_AUTO_STOP_SIZE ? on : off);
   ButtonObj("BTN_TM_FIXED", x + 634, row, 52, bh, "FIX", g_targetModel == ERL_TARGET_FIXED_R ? on : off);
   ButtonObj("BTN_TM_REV", x + 690, row, 54, bh, "REV", g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL ? on : (g_invertMode ? C'35,37,44' : off));

   row += 28;
   LabelObj("DASH_STRICT_L", x + 16, row + 4, "STRICT FILTERS:", muted, 8);
   ButtonObj("BTN_REQ_IRL", x + 130, row, 94, bh, g_requireIrlTouch ? "IRL: ON" : "IRL: OFF", g_requireIrlTouch ? on : off);
   ButtonObj("BTN_REQ_SWEEP", x + 232, row, 104, bh, g_requireEntrySweep ? "SWEEP: ON" : "SWEEP: OFF", g_requireEntrySweep ? on : off);
   ButtonObj("BTN_REQ_DISP", x + 344, row, 96, bh, g_requireDisplacementFvg ? "DISP: ON" : "DISP: OFF", g_requireDisplacementFvg ? on : off);
   LabelObj("DASH_STRICT_HINT", x + 456, row + 4, "OFF = more signals, less strict pro confirmation", C'255,204,82', 8);

   row += 28;
   LabelObj("DASH_NARR_L", x + 16, row + 4, "NARRATIVE:", muted, 8);
   ButtonObj("BTN_REQ_ASIA", x + 112, row, 96, bh, g_requireAsiaLiquidityDraw ? "ASIA: ON" : "ASIA: OFF", g_requireAsiaLiquidityDraw ? on : off);
   ButtonObj("BTN_ASIA_TGT", x + 216, row, 96, bh, g_useAsiaLiquidityTarget ? "TGT: ON" : "TGT: OFF", g_useAsiaLiquidityTarget ? on : off);
   ButtonObj("BTN_REQ_SMT", x + 320, row, 88, bh, g_requireSmt ? "SMT: ON" : "SMT: OFF", g_requireSmt ? on : off);
   LabelObj("DASH_NARR_HINT", x + 424, row + 4, "Narrative gates", C'255,204,82', 8);
   ButtonObj("BTN_INV", x + 640, row, 104, bh, g_invertMode ? "FULL INV ON" : "FULL INV OFF", g_invertMode ? C'184,103,22' : off);

   row += 28;
   LabelObj("DASH_ATRBUF_L", x + 16, row + 4, "ATR BUF%:", muted, 8);
   ButtonObj("BTN_ATRBUF_0", x + 88, row, 36, bh, "0", MathAbs(g_slBufferAtrPct) < 0.1 ? on : off);
   ButtonObj("BTN_ATRBUF_20", x + 128, row, 40, bh, "20", MathAbs(g_slBufferAtrPct - 20.0) < 0.1 ? on : off);
   ButtonObj("BTN_ATRBUF_40", x + 172, row, 40, bh, "40", MathAbs(g_slBufferAtrPct - 40.0) < 0.1 ? on : off);
   ButtonObj("BTN_ATRBUF_60", x + 216, row, 40, bh, "60", MathAbs(g_slBufferAtrPct - 60.0) < 0.1 ? on : off);
   ButtonObj("BTN_ATRBUF_80", x + 260, row, 40, bh, "80", MathAbs(g_slBufferAtrPct - 80.0) < 0.1 ? on : off);
   ButtonObj("BTN_ATRBUF_100", x + 304, row, 46, bh, "100", MathAbs(g_slBufferAtrPct - 100.0) < 0.1 ? on : off);
   LabelObj("DASH_ATRBUF_MAN_L", x + 372, row + 4, "CUSTOM:", muted, 8);
   EditObj("EDIT_ATRBUF_PCT", x + 434, row, 58, bh, DoubleToString(g_slBufferAtrPct, 0));
   ButtonObj("BTN_ATRBUF_APPLY", x + 498, row, 80, bh, "APPLY", C'38,101,176');
   LabelObj("DASH_ATRBUF_HINT", x + 592, row + 4, "0 = no ATR buffer", C'255,204,82', 8);

   int sec2 = sec1 + 236;
   RectObj("DASH_SEC2", x + 8, sec2, 744, 132, C'24,31,45', C'60,110,170');
   LabelObj("DASH_SEC2_T", x + 16, sec2 + 7, "SIGNAL AUDIT", ac, 9);
   double resolved = g_hist.wins + g_hist.losses;
   double wr = resolved > 0.0 ? (double)g_hist.wins / resolved * 100.0 : 0.0;
   LabelObj("DASH_AUD1", x + 16, sec2 + 30,
      HistWindowLabel() + ": " + IntegerToString(g_hist.total) + " sig | "
      + IntegerToString(g_hist.wins) + "W " + IntegerToString(g_hist.losses) + "L " + IntegerToString(g_hist.open)
      + "O" + (g_hist.invalid > 0 ? " DATA " + IntegerToString(g_hist.invalid) : "") + " | WR " + DoubleToString(wr, 1) + "% | Net " + DoubleToString(g_hist.netR, 2) + "R | $ "
      + (ApproxMoneyFromR(g_hist.netR) >= 0 ? "+" : "") + DoubleToString(ApproxMoneyFromR(g_hist.netR), 2),
      g_hist.netR >= 0 ? C'80,255,180' : C'255,95,140', 9);
   int awx = x + 16;
   int awy = sec2 + 54;
   ButtonObj("BTN_AUD_2W", awx, awy, 40, bh, "2W", g_histWeeks == 2 ? C'38,101,176' : off); awx += 44;
   ButtonObj("BTN_AUD_5W", awx, awy, 40, bh, "5W", g_histWeeks == 5 ? C'38,101,176' : off); awx += 44;
   ButtonObj("BTN_AUD_10W", awx, awy, 44, bh, "10W", g_histWeeks == 10 ? C'38,101,176' : off); awx += 48;
   ButtonObj("BTN_AUD_20W", awx, awy, 44, bh, "20W", g_histWeeks == 20 ? C'38,101,176' : off); awx += 48;
   ButtonObj("BTN_AUD_1Y", awx, awy, 40, bh, "1Y", g_histWeeks == 52 ? C'38,101,176' : off); awx += 44;
   ButtonObj("BTN_AUD_2Y", awx, awy, 40, bh, "2Y", g_histWeeks == 104 ? C'38,101,176' : off); awx += 44;
   ButtonObj("BTN_AUD_3Y", awx, awy, 40, bh, "3Y", g_histWeeks == 156 ? C'38,101,176' : off); awx += 44;
   ButtonObj("BTN_AUD_4Y", awx, awy, 40, bh, "4Y", g_histWeeks == 208 ? C'38,101,176' : off); awx += 44;
   ButtonObj("BTN_AUD_5Y", awx, awy, 40, bh, "5Y", g_histWeeks == 260 ? C'38,101,176' : off);

   double auditBarPct = g_histAuditRunning ? g_histAuditProgressPct : wr;
   color auditBarColor = g_histAuditRunning ? C'38,140,220' : (wr >= 50 ? C'80,220,140' : C'255,95,140');
   RectObj("DASH_WR_BG", x + 16, sec2 + 82, 640, 14, C'38,46,60', C'60,80,110');
   int fill = (int)MathRound(638.0 * MathMax(0.0, MathMin(100.0, auditBarPct)) / 100.0);
   if(fill > 2) RectObj("DASH_WR_FG", x + 17, sec2 + 83, fill, 12, auditBarColor, auditBarColor);
   else ObjectDelete(0, PFX + "DASH_WR_FG");
   LabelObj("DASH_AUD_PROGRESS", x + 664, sec2 + 82,
      g_histAuditRunning ? (g_histAuditStage + " " + DoubleToString(g_histAuditProgressPct, 1) + "%") : "",
      C'90,178,255', 7);
   LabelObj("DASH_AUD2", x + 16, sec2 + 106,
      "Won +" + DoubleToString(g_hist.wonR, 2) + "R | Lost -" + DoubleToString(g_hist.lostR, 2) + "R | Avg "
      + DoubleToString((g_hist.total - g_hist.invalid) > 0 ? g_hist.netR / (g_hist.total - g_hist.invalid) : 0.0, 3) + "R/trade", muted, 8);

   int sec3 = sec2 + 140;
   RectObj("DASH_SEC3", x + 8, sec3, 744, 152, C'24,31,45', C'60,110,170');
   LabelObj("DASH_SEC3_T", x + 16, sec3 + 7, "EXECUTION", ac, 9);
   LabelObj("DASH_EX1", x + 16, sec3 + 30,
      "Status: " + g_lastStatus + " | Block: " + (g_lastBlock == "" ? "-" : g_lastBlock)
      + " | Spread " + DoubleToString(g_lastSpreadPts, 0) + " pts | Positions " + IntegerToString(OwnPositionCount())
      + " | DUP " + (g_allowDuplicateEntries ? "ON" : "OFF")
      + " | " + RuntimeInvertLabel()
      + " | CT " + (g_fileBridgeEnabled ? (g_fileBridgeOnlyMode ? "ONLY" : "PUB") : "OFF") + " " + g_lastBridgeStatus,
      g_lastBlock == "" ? C'80,255,180' : C'255,204,82', 8);
   LabelObj("DASH_EX2", x + 16, sec3 + 52,
      "Last: " + DirLabel(g_lastSignalDir) + " " + FmtTime(g_lastSignalTime)
      + " | Entry " + DoubleToString(g_lastEntry, _Digits) + " SL " + DoubleToString(g_lastSl, _Digits)
      + " TP " + DoubleToString(g_lastTp, _Digits), muted, 8);
   LabelObj("DASH_EX3", x + 16, sec3 + 74,
      "Risk: " + (RiskEnabled() ? "ON" : "OFF") + " " + DoubleToString(RiskPerTradePct(), 2)
      + "% | Mode " + RuntimeRiskModeLabel() + " | SL " + (g_pipSlMode ? ("PIP " + DoubleToString(g_pipSlPips, 1)) : ("%" + DoubleToString(g_slDistancePct, 0)))
      + " | ATRbuf " + DoubleToString(g_slBufferAtrPct, 0) + "% | Magic " + IntegerToString((int)RuntimeMagic()), muted, 8);
   LabelObj("DASH_SL_L", x + 510, sec3 + 74, "SL%:", muted, 8);
   EditObj("EDIT_SL_PCT", x + 550, sec3 + 72, 56, bh, DoubleToString(g_slDistancePct, 0));
   ButtonObj("BTN_SL_APPLY", x + 612, sec3 + 72, 70, bh, "APPLY", C'38,101,176');
   LabelObj("DASH_PIPSL_L", x + 510, sec3 + 100, "PIP SL:", muted, 8);
   ButtonObj("BTN_PIPSL_TOGGLE", x + 564, sec3 + 98, 68, bh, g_pipSlMode ? "PIP ON" : "PIP OFF", g_pipSlMode ? on : off);
   EditObj("EDIT_PIPSL_PIPS", x + 638, sec3 + 98, 56, bh, DoubleToString(g_pipSlPips, 1));
   ButtonObj("BTN_PIPSL_APPLY", x + 700, sec3 + 98, 44, bh, "OK", C'38,101,176');
   LabelObj("DASH_CT_L", x + 16, sec3 + 126, "cTRADER:", muted, 8);
   ButtonObj("BTN_BRIDGE_PUB", x + 84, sec3 + 124, 76, bh, g_fileBridgeEnabled ? "PUB ON" : "PUB OFF", g_fileBridgeEnabled ? on : off);
   ButtonObj("BTN_BRIDGE_ONLY", x + 166, sec3 + 124, 78, bh, g_fileBridgeOnlyMode ? "ONLY ON" : "ONLY OFF", g_fileBridgeOnlyMode ? C'120,88,25' : off);
   ButtonObj("BTN_BRIDGE_NATIVE", x + 250, sec3 + 124, 68, bh, g_nativeTradeWithBridgeOnly ? "NAT ON" : "NAT OFF", g_nativeTradeWithBridgeOnly ? C'184,103,22' : off);
   LabelObj("DASH_RISK_L", x + 326, sec3 + 126, "RISK%:", muted, 8);
   EditObj("EDIT_RISK_PCT", x + 384, sec3 + 124, 58, bh, DoubleToString(g_riskPerTradePct, 2));
   ButtonObj("BTN_RISK_APPLY", x + 448, sec3 + 124, 88, bh, "APPLY R", C'38,101,176');
   LabelObj("DASH_CH_L", x + 544, sec3 + 126, "CH:", muted, 8);
   EditObj("EDIT_BRIDGE_CH", x + 570, sec3 + 124, 42, bh, IntegerToString(g_bridgeChannel));
   ButtonObj("BTN_BRIDGE_CH_APPLY", x + 618, sec3 + 124, 96, bh, "APPLY CH", C'38,101,176');

   int sec4 = sec3 + 160;
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
   if(!RiskEnabled() || !InpLiquidateOnBreach) return;
   if(DailyLossLimitPct() <= 0.0 && MaxDrawdownPct() <= 0.0) return;
   double base = BaseCapital();
   if(base <= 0.0) return;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equityPeak <= 0.0) g_equityPeak = equity;
   g_equityPeak = MathMax(g_equityPeak, equity);
   double dailyPnl = DailyClosedPnl();
   double dd = g_equityPeak - equity;
   bool breach = false;
   string why = "";
   if(DailyLossLimitPct() > 0.0 && dailyPnl <= -base * DailyLossLimitPct() / 100.0)
   {
      breach = true;
      why = "daily_loss_breach";
   }
   if(MaxDrawdownPct() > 0.0 && dd >= base * MaxDrawdownPct() / 100.0)
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

void NormalizeEntryModelStrictness()
{
   bool anyStrict = (g_requireIrlTouch || g_requireEntrySweep || g_requireDisplacementFvg);
   if(anyStrict && g_entryModel != ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG)
      g_entryModel = ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG;
}

void SelectLegacyEntryModel()
{
   g_entryModel = ERL_ENTRY_LEGACY_HTF_FVG_TAP;
   g_requireIrlTouch = false;
   g_requireEntrySweep = false;
   g_requireDisplacementFvg = false;
}
void RefreshAfterConfigChange(bool rebuildSignals = true)
{
   NormalizeEntryModelStrictness();
   SanitizeHalfMode();
   // Coalesce rapid UI clicks; heavy signal generation runs once after input settles.
   g_configRefreshPending = true;
   g_configRefreshRebuildSignals = (g_configRefreshRebuildSignals || rebuildSignals);
   g_configRefreshDue = TimeLocal() + 1;
   g_lastStatus = "CONFIG UPDATE QUEUED";
   UpdateDashboard();
   ChartRedraw(0);
}

void ProcessPendingConfigRefresh()
{
   if(!g_configRefreshPending || TimeLocal() < g_configRefreshDue) return;
   g_configRefreshPending = false;
   g_lastLiveScanBar = 0;
   bool rebuildSignals = g_configRefreshRebuildSignals;
   g_configRefreshRebuildSignals = false;
   RecalculateHistoricalStats(rebuildSignals);
   // A filter/config change can remove signals. Full reset prevents stale arrows from contradicting execution.
   if(!IsTesterMode()) DrawHistoricalSignals(true);
   g_lastStatus = "CONFIG " + StrictnessLabel(g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg)
      + " " + EntryModelLabel(g_entryModel) + " SIG=" + IntegerToString(g_hist.total);
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
void RunValidationInternalAudit()
{
   if(!InpValidationInternalAudit || !IsTesterMode()) return;
   g_histWeeks = ClampHistWeeks(InpValidationInternalAuditWeeks);
   RecalculateHistoricalStats(true);
   int resolved = g_hist.wins + g_hist.losses;
   double wr = resolved > 0 ? 100.0 * (double)g_hist.wins / (double)resolved : 0.0;
   Print("SOL_INTERNAL_AUDIT build=", LN_BUILD,
      " window=", HistWindowLabel(),
      " full_invert=", (g_invertMode ? "ON" : "OFF"),
      " reg_filter=", (g_solRegimeFilterEnabled ? "ON" : "OFF"),
      " regime_rejected=", IntegerToString(g_solRegimeFilterRejected),
      " regime_unclassified=", IntegerToString(g_solRegimeFilterUnclassified),
      " rf_mask=", SolRegimeRuleMask(),
      " total=", IntegerToString(g_hist.total),
      " wins=", IntegerToString(g_hist.wins),
      " losses=", IntegerToString(g_hist.losses),
      " open=", IntegerToString(g_hist.open),
      " invalid=", IntegerToString(g_hist.invalid),
      " wr=", DoubleToString(wr, 4),
      " netR=", DoubleToString(g_hist.netR, 6));
   if(!InpValidationInternalAuditRows) return;
   for(int i = 0; i < ArraySize(g_histSignals); ++i)
   {
      string result = !g_histSignalValid[i] ? "INVALID" : (!g_histSignalClosed[i] ? "OPEN" : (g_histSignalWon[i] ? "WIN" : "LOSS"));
      ErlSignal auditSig = g_histSignals[i];
      string invertDetail = "";
      bool hasExecutionGeometry = g_histSignalValid[i]
         && i < ArraySize(g_histSignalExecEntry)
         && g_histSignalExecDir[i] != 0
         && g_histSignalExecEntry[i] > 0.0
         && g_histSignalExecSl[i] > 0.0;
      bool geometryOk = true;
      if(hasExecutionGeometry)
      {
         auditSig.dir = g_histSignalExecDir[i];
         auditSig.entry = g_histSignalExecEntry[i];
         auditSig.sl = g_histSignalExecSl[i];
         auditSig.risk = MathAbs(auditSig.entry - auditSig.sl);
         auditSig.targetOverride = g_histSignalExecTp[i];
         SetSignalTargetLadder(auditSig);
      }
      else if(g_invertMode)
         geometryOk = ApplyFullInversionGeometry(g_histSignals[i], g_target, g_targetModel, auditSig, invertDetail);
      Print("SOL_INTERNAL_AUDIT_ROW index=", IntegerToString(i),
         " available=", TimeToString(g_histSignals[i].availableTime, TIME_DATE|TIME_MINUTES),
         " raw_dir=", DirLabel(g_histSignals[i].dir),
         " exec_dir=", DirLabel(auditSig.dir),
         " full_invert=", (g_invertMode ? "ON" : "OFF"),
         " geometry_ok=", (geometryOk ? "1" : "0"),
         " result=", result,
         " r=", DoubleToString(g_histSignalR[i], 6),
         " entry=", DoubleToString(auditSig.entry, _Digits),
         " sl=", DoubleToString(auditSig.sl, _Digits),
         " tp=", DoubleToString(SelectedTarget(auditSig, g_target, g_targetModel), _Digits),
         " exit_time=", (i < ArraySize(g_histSignalExitTime) && g_histSignalExitTime[i] > 0
            ? TimeToString(g_histSignalExitTime[i], TIME_DATE|TIME_MINUTES) : "-"),
         " exit_reason=", (i < ArraySize(g_histSignalExitReason) ? g_histSignalExitReason[i] : ""),
         " reason=", g_histSignals[i].reason,
         " id=", g_histSignals[i].id);
   }
}

int OnInit()
{
   g_bridgeChannel = GlobalVariableCheck(BridgeChannelStateKey())
      ? ClampBridgeChannel((int)GlobalVariableGet(BridgeChannelStateKey()))
      : ClampBridgeChannel(InpBridgeChannel);
   GlobalVariableSet(BridgeChannelStateKey(), g_bridgeChannel);
   ErlTesterAudit_Init();
   PFX = LN_PREFIX + IntegerToString((int)ChartID()) + "_";
   DeleteAllLiqNarrativeLiveObjects();
   g_eaEnabled = InpEaEnabled;
   g_ftmoMode = InpFtmoModeDefault;
   g_riskLotOnlyMode = (!g_ftmoMode && InpRiskLotOnlyModeDefault);
   g_htf = InpDefaultHtf;
   g_entryTf = InpDefaultEntryTf;
   g_swingLookback = InpDefaultSwingLookback;
   g_target = InpDefaultTarget;
   g_hc = InpDefaultHalfBe;
   g_weeklyBias = InpDefaultWeeklyBias;
   g_entryModel = InpDefaultEntryModel;
   g_stopModel = InpDefaultStopModel;
   g_targetModel = InpDefaultTargetModel;
   LoadRuntimeInvertMode();
   g_requireIrlTouch = InpDefaultRequireIrlTouch;
   g_requireEntrySweep = InpDefaultRequireEntrySweep;
   g_requireDisplacementFvg = InpDefaultRequireDisplacementFvg;
   g_requireAsiaLiquidityDraw = InpDefaultRequireAsiaLiquidityDraw;
   g_useAsiaLiquidityTarget = InpDefaultUseAsiaLiquidityTarget;
   g_requireSmt = InpDefaultRequireSmt;
   LiqMacroRegimeInit();
   g_solRegimeFilterEnabled = InpSolRegimeFilterDefault;
   g_solRegimeRuleBlocked[0] = InpSolRegimeRf01Blocked;
   g_solRegimeRuleBlocked[1] = InpSolRegimeRf02Blocked;
   g_solRegimeRuleBlocked[2] = InpSolRegimeRf03Blocked;
   g_solRegimeRuleBlocked[3] = InpSolRegimeRf04Blocked;
   g_solRegimeRuleBlocked[4] = InpSolRegimeRf05Blocked;
   g_solRegimeRuleBlocked[5] = InpSolRegimeRf06Blocked;
   g_solRegimeRuleBlocked[6] = InpSolRegimeRf07Blocked;
   g_solRegimeRuleBlocked[7] = InpSolRegimeRf08Blocked;
   g_solRegimeRuleBlocked[8] = InpSolRegimeRf09Blocked;
   g_solRegimeRuleBlocked[9] = InpSolRegimeRf10Blocked;
   g_solRegimeRuleBlocked[10] = InpSolRegimeRf11Blocked;
   g_solRegimeRuleBlocked[11] = InpSolRegimeRf12Blocked;
   for(int ri = 0; ri < SOL_ADV_RF_COUNT; ++ri)
   {
      g_solRegimeRuleWins[ri] = 0;
      g_solRegimeRuleLosses[ri] = 0;
   }
   NormalizeEntryModelStrictness();
   g_slDistancePct = ClampSlDistancePct(InpSlDistancePct);
   g_slBufferAtrPct = ClampSlBufferAtrPct(InpSlBufferAtrPct);
   g_pipSlMode = InpPipSlModeDefault;
   g_pipSlPips = ClampPipSlPips(InpPipSlPips);
   g_fileBridgeEnabled = InpFileBridgeEnabled;
   g_fileBridgeOnlyMode = InpFileBridgeOnlyMode;
   g_nativeTradeWithBridgeOnly = InpNativeTradeWithBridgeOnlyDefault;
   g_allowDuplicateEntries = InpAllowDuplicateEntriesDefault;
   g_riskPerTradePct = ClampRiskPerTradePct(InpRiskPerTradePct);
   g_histWeeks = ClampHistWeeks(InpHistoricalWeeks > 0 ? InpHistoricalWeeks : (int)MathCeil((double)MathMax(1, InpHistoricalDays) / 7.0));
   g_btWeeks = InpBacktestWeeks;
   g_btFillMode = InpBacktestFillMode;
   g_btSameBarPolicy = InpBacktestSameBarPolicy;
   // Zero is an explicit auto mode: use each historical entry bar's spread.
   // Do not replace it with today's live/weekend spread during initialization.
   g_btSpreadPts = MathMax(0.0, InpBacktestSpreadPts);
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
      RegimeV3Update(true);
      DrawDashboard();
      RecalculateHistoricalStats();
      BridgeLoadPending();
      FileBridgeWriteInitMarker();
      BridgeRetryPending();
      DrawDashboard();
      DrawHistoricalSignals();
      DrawLiveLevelsForPosition();
   }
   if(!IsTesterMode()) EventSetTimer(1);
   AuditWrite("ea_init", "init", 0, 0, 0, 0, 0,
      "build=" + (string)LN_BUILD + " htf=" + TfLabel(g_htf) + " entry_tf=" + TfLabel(g_entryTf)
      + " swing=" + IntegerToString(g_swingLookback) + " target=" + TargetLabel(g_target) + " hc=" + HcLabel(g_hc)
      + " entry_model=" + EntryModelLabel(g_entryModel) + " stop_model=" + StopModelLabel(g_stopModel)
      + " target_model=" + TargetModelLabel(g_targetModel)
      + " full_invert=" + (g_invertMode ? "ON" : "OFF") + " pure_swap=1"
      + " strictness=" + StrictnessLabel(g_requireIrlTouch, g_requireEntrySweep, g_requireDisplacementFvg)
      + " narrative=" + NarrativeLabel(g_requireAsiaLiquidityDraw, g_useAsiaLiquidityTarget, g_requireSmt)
      + " regime_filter=" + (g_solRegimeFilterEnabled ? "ON" : "OFF"));
   Print("LiqNarrativeSol init build=", LN_BUILD, " symbol=", _Symbol, " htf=", TfLabel(g_htf), " entry=", TfLabel(g_entryTf),
      " regime_filter=", (g_solRegimeFilterEnabled ? "ON" : "OFF"),
      " full_invert=", (g_invertMode ? "ON" : "OFF"),
      " rf_mask=", SolRegimeRuleMask(),
      " macro_mask=", LiqMacroRegimeMask());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   RunValidationInternalAudit();
   EventKillTimer();
   DeleteByPrefix(PFX);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   ErlTesterAudit_WriteDeal(trans, request, result);
}

void OnTick()
{
   // Validation jobs compute the complete causal audit once in OnDeinit.
   // Live execution scans on ticks; replaying that path in the tester only
   // repeats the same historical build thousands of times.
   if(IsValidationTester()) return;
   g_lastSpreadPts = CurrentSpreadPoints();
   TryOpenLatestSignal();
   ManagePositions();
   if(!IsTesterMode())DrawLiveLevelsForPosition();
}

void OnTimer()
{
   if(IsTesterMode()) return;
   TradeDayCalendarPublisherTick();
   g_lastSpreadPts = CurrentSpreadPoints();
   RegimeV3Update(false);
   BridgeRetryPending();
   EnforceRiskBreach();
   TryOpenLatestSignal();
   ManagePositions();
   ProbePositions();
   ScanClosedHistory();
   ProcessPendingConfigRefresh();
   RefreshUnresolvedHistoricalLifecycle();
   if(!IsValidationTester())
   {
      if(g_btRunning) BacktestStep();
      UpdateDashboard();
      DrawLiveLevelsForPosition();
      if(g_btRunning) ChartRedraw(0);
   }
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(LiqLibraryEvent(id,sparam,lparam,dparam)) return;
   if(id==CHARTEVENT_CHART_CHANGE){DrawDashboard();ChartRedraw(0);return;}
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
      if(sparam == PFX + "EDIT_ATRBUF_PCT")
      {
         // Do not apply custom ATR buffer while typing; BTN_ATRBUF_APPLY commits it.
         UpdateDashboard();
      }
      if(sparam == PFX + "EDIT_PIPSL_PIPS")
      {
         // Do not apply custom pip SL while typing; BTN_PIPSL_APPLY commits it.
         UpdateDashboard();
      }
      if(sparam == PFX + "EDIT_RISK_PCT")
      {
         // Do not apply risk while typing; BTN_RISK_APPLY commits and republishes init marker.
         UpdateDashboard();
      }
      if(sparam == PFX + "EDIT_BRIDGE_CH")
         UpdateDashboard();
      return;
   }

   if(Clicked(sparam, "BTN_DASH_TOGGLE"))
   {
      g_dashboardCollapsed = !g_dashboardCollapsed;
      DrawDashboard();
      ChartRedraw(0);
      return;
   }

   for(int ri = 0; ri < SOL_ADV_RF_COUNT; ++ri)
   {
      if(Clicked(sparam, "BTN_REG_RF_" + IntegerToString(ri)))
      {
         g_solRegimeRuleBlocked[ri] = !g_solRegimeRuleBlocked[ri];
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         g_lastStatus = SolRegimeRuleCode(ri) + (g_solRegimeRuleBlocked[ri] ? " BLOCKED" : " ALLOWED");
         RefreshAfterConfigChange(false);
         return;
      }
   }

   if(Clicked(sparam, "BTN_REG_FILTER"))
   {
      g_solRegimeFilterEnabled = !g_solRegimeFilterEnabled;
      if(g_solRegimeFilterEnabled) RegimeV3EnsureTimeline(true);
      RefreshAfterConfigChange();
      return;
   }
   for(int mi = 0; mi < LIQ_MACRO_REGIME_COUNT; ++mi)
   {
      if(Clicked(sparam, "BTN_MACRO_REG_" + IntegerToString(mi)))
      {
         g_macroRegimeAllowed[mi] = !g_macroRegimeAllowed[mi];
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         g_lastStatus = LiqMacroRegimeShortName(mi) + (g_macroRegimeAllowed[mi] ? " ALLOWED" : " BLOCKED");
         RefreshAfterConfigChange(false);
         return;
      }
   }

   if(Clicked(sparam, "BTN_HTF_H1")) { g_htf = PERIOD_H1; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HTF_H90")) { g_htf = LN_PERIOD_H90; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HTF_H2")) { g_htf = PERIOD_H2; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HTF_H4")) { g_htf = PERIOD_H4; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_HTF_D1")) { g_htf = PERIOD_D1; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ETF_M15")) { g_entryTf = PERIOD_M15; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ETF_M30")) { g_entryTf = PERIOD_M30; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ETF_H1")) { g_entryTf = PERIOD_H1; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SW_3")) { g_swingLookback = 3; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SW_5")) { g_swingLookback = 5; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SW_8")) { g_swingLookback = 8; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TP_1")) { g_target = ERL_RR_TP1; g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TP_2")) { g_target = ERL_RR_TP2; g_targetModel = ERL_TARGET_FIXED_R; SanitizeHalfMode(); RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TP_3")) { g_target = ERL_RR_TP3; g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TP_4")) { g_target = ERL_RR_TP4; g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TP_5")) { g_target = ERL_RR_TP5; g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TP_6")) { g_target = ERL_RR_TP6; g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_HC_OFF")) { g_hc = ERL_HC_OFF; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_HC_TP1")) { if(g_invertMode || TargetR(g_target)*2.0 > 1) g_hc = ERL_HC_TP1; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_HC_TP2")) { if(g_invertMode || TargetR(g_target)*2.0 > 2) g_hc = ERL_HC_TP2; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_HC_TP3")) { if(g_invertMode || TargetR(g_target)*2.0 > 3) g_hc = ERL_HC_TP3; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_HC_TP4")) { if(g_invertMode || TargetR(g_target)*2.0 > 4) g_hc = ERL_HC_TP4; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_HC_TP5")) { if(g_invertMode || TargetR(g_target)*2.0 > 5) g_hc = ERL_HC_TP5; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_2W")) { g_histWeeks = 2; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_5W")) { g_histWeeks = 5; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_10W")) { g_histWeeks = 10; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_20W")) { g_histWeeks = 20; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_1Y")) { g_histWeeks = 52; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_2Y")) { g_histWeeks = 104; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_3Y")) { g_histWeeks = 156; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_4Y")) { g_histWeeks = 208; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_AUD_5Y")) { g_histWeeks = 260; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_ATRBUF_0")) { g_slBufferAtrPct = 0.0; ObjectSetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT, "0"); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ATRBUF_20")) { g_slBufferAtrPct = 20.0; ObjectSetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT, "20"); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ATRBUF_40")) { g_slBufferAtrPct = 40.0; ObjectSetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT, "40"); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ATRBUF_60")) { g_slBufferAtrPct = 60.0; ObjectSetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT, "60"); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ATRBUF_80")) { g_slBufferAtrPct = 80.0; ObjectSetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT, "80"); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ATRBUF_100")) { g_slBufferAtrPct = 100.0; ObjectSetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT, "100"); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ATRBUF_APPLY")) { g_slBufferAtrPct = ClampSlBufferAtrPct(StringToDouble(ObjectGetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT))); ObjectSetString(0, PFX + "EDIT_ATRBUF_PCT", OBJPROP_TEXT, DoubleToString(g_slBufferAtrPct, 0)); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_SL_APPLY")) { g_slDistancePct = ClampSlDistancePct(StringToDouble(ObjectGetString(0, PFX + "EDIT_SL_PCT", OBJPROP_TEXT))); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_PIPSL_TOGGLE")) { g_pipSlMode = !g_pipSlMode; if(g_pipSlMode) g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_PIPSL_APPLY")) { g_pipSlPips = ClampPipSlPips(StringToDouble(ObjectGetString(0, PFX + "EDIT_PIPSL_PIPS", OBJPROP_TEXT))); ObjectSetString(0, PFX + "EDIT_PIPSL_PIPS", OBJPROP_TEXT, DoubleToString(g_pipSlPips, 1)); if(g_pipSlMode) g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_BRIDGE_PUB")) { g_fileBridgeEnabled = !g_fileBridgeEnabled; if(!g_fileBridgeEnabled) { g_fileBridgeOnlyMode = false; g_lastBridgeStatus = "BRIDGE OFF"; } else { FileBridgeWriteInitMarker(); } UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_BRIDGE_ONLY")) { g_fileBridgeOnlyMode = !g_fileBridgeOnlyMode; if(g_fileBridgeOnlyMode && !g_fileBridgeEnabled) g_fileBridgeEnabled = true; if(g_fileBridgeEnabled) FileBridgeWriteInitMarker(); UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_BRIDGE_NATIVE")) { g_nativeTradeWithBridgeOnly = !g_nativeTradeWithBridgeOnly; UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_RISK_APPLY")) { g_riskPerTradePct = ClampRiskPerTradePct(StringToDouble(ObjectGetString(0, PFX + "EDIT_RISK_PCT", OBJPROP_TEXT))); ObjectSetString(0, PFX + "EDIT_RISK_PCT", OBJPROP_TEXT, DoubleToString(g_riskPerTradePct, 2)); if(g_fileBridgeEnabled) FileBridgeWriteInitMarker(); UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_BRIDGE_CH_APPLY")) { ApplyBridgeChannel((int)StringToInteger(ObjectGetString(0, PFX + "EDIT_BRIDGE_CH", OBJPROP_TEXT))); ObjectSetString(0, PFX + "EDIT_BRIDGE_CH", OBJPROP_TEXT, IntegerToString(g_bridgeChannel)); UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_INV"))
   {
      bool requested = !g_invertMode;
      if(!SetRuntimeInvertMode(requested))
      {
         g_lastStatus = "FULL INV BLOCKED";
         g_lastBlock = g_targetModel == ERL_TARGET_OPPOSITE_SIGNAL ? "full_invert_unsupported_reverse_target" : "full_invert_state_persist_failed";
         AuditWrite("invert_mode_change_failed", "dashboard", 0, 0, 0, 0, 0, g_lastBlock);
         UpdateDashboard();
         ChartRedraw(0);
         return;
      }
      if(g_lastSignalDir != 0) g_lastSignalDir = -g_lastSignalDir;
      ArrayFree(g_simCache);
      g_lastStatus = RuntimeInvertLabel();
      g_lastBlock = "";
      AuditWrite("invert_mode_changed", "dashboard", 0, 0, 0, 0, 0,
         "enabled=" + (g_invertMode ? "1" : "0") + " pure_swap=1 existing_positions_unchanged=1");
      if(g_fileBridgeEnabled) FileBridgeWriteInitMarker();
      RefreshAfterConfigChange(false);
      return;
   }
   if(Clicked(sparam, "BTN_DUP_ENTRY")) { g_allowDuplicateEntries = !g_allowDuplicateEntries; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_BIAS")) { g_weeklyBias = !g_weeklyBias; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ENTRY_PRO")) { g_entryModel = ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ENTRY_LEG")) { SelectLegacyEntryModel(); RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_STOP_FVG1")) { g_stopModel = ERL_STOP_FIRST_FVG_CANDLE; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_STOP_ZONE")) { g_stopModel = ERL_STOP_FVG_BOUNDARY; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_TM_EXT")) { g_targetModel = ERL_TARGET_NEXT_EXTERNAL; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TM_AUTO")) { g_targetModel = ERL_TARGET_AUTO_STOP_SIZE; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TM_FIXED")) { g_targetModel = ERL_TARGET_FIXED_R; RefreshAfterConfigChange(false); return; }
   if(Clicked(sparam, "BTN_TM_REV"))
   {
      if(g_invertMode)
      {
         g_lastStatus = "REV BLOCKED";
         g_lastBlock = "full_invert_unsupported_reverse_target";
         AuditWrite("target_model_change_blocked", "dashboard", 0, 0, 0, 0, 0, g_lastBlock);
         UpdateDashboard();
         ChartRedraw(0);
         return;
      }
      g_targetModel = ERL_TARGET_OPPOSITE_SIGNAL;
      g_hc = ERL_HC_OFF;
      RefreshAfterConfigChange(false);
      return;
   }
   if(Clicked(sparam, "BTN_REQ_IRL")) { g_entryModel = ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG; g_requireIrlTouch = !g_requireIrlTouch; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_REQ_SWEEP")) { g_entryModel = ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG; g_requireEntrySweep = !g_requireEntrySweep; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_REQ_DISP")) { g_entryModel = ERL_ENTRY_PRO_SWEEP_RECLAIM_FVG; g_requireDisplacementFvg = !g_requireDisplacementFvg; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_REQ_ASIA")) { g_requireAsiaLiquidityDraw = !g_requireAsiaLiquidityDraw; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_ASIA_TGT")) { g_useAsiaLiquidityTarget = !g_useAsiaLiquidityTarget; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_REQ_SMT")) { g_requireSmt = !g_requireSmt; RefreshAfterConfigChange(); return; }
   if(Clicked(sparam, "BTN_EA")) { g_eaEnabled = !g_eaEnabled; UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_FTMO")) { g_ftmoMode = !g_ftmoMode; if(g_ftmoMode) g_riskLotOnlyMode = false; UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_RISKLOT")) { g_riskLotOnlyMode = !g_riskLotOnlyMode; if(g_riskLotOnlyMode) g_ftmoMode = false; UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_CLOSE")) { CloseOwnPositions(0); UpdateDashboard(); ChartRedraw(0); return; }
   if(Clicked(sparam, "BTN_AUDIT"))
   {
      g_auditRuntime = !g_auditRuntime;
      Print("LiqNarrativeSol audit logging ", g_auditRuntime ? "enabled" : "disabled");
      if(g_auditRuntime)
         AuditWrite("audit_toggle", "dashboard", 0, 0, 0, 0, 0, "AUDIT_ON build=" + (string)LN_BUILD);
      UpdateDashboard();
      ChartRedraw(0);
      return;
   }

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

// Strategy snapshots exclude account risk, transport, channel and live lifecycle state.
string LiqLibraryFamily(){return "LiqNarrativeSol_Advanced_Channel";}
string LiqLibraryInputContract(){string s="V1";
s+="|InpEaEnabled="+(string)InpEaEnabled;
s+="|InpMagic="+(string)InpMagic;
s+="|InpDeviationPoints="+(string)InpDeviationPoints;
s+="|InpCloseOnReverse="+(string)InpCloseOnReverse;
s+="|InpBlockSameDirection="+(string)InpBlockSameDirection;
s+="|InpAllowDuplicateEntriesDefault="+(string)InpAllowDuplicateEntriesDefault;
s+="|InpInvertModeDefault="+(string)InpInvertModeDefault;
s+="|InpDefaultHtf="+(string)InpDefaultHtf;
s+="|InpDefaultEntryTf="+(string)InpDefaultEntryTf;
s+="|InpDefaultSwingLookback="+(string)InpDefaultSwingLookback;
s+="|InpDefaultTarget="+(string)InpDefaultTarget;
s+="|InpDefaultHalfBe="+(string)InpDefaultHalfBe;
s+="|InpDefaultWeeklyBias="+(string)InpDefaultWeeklyBias;
s+="|InpDefaultEntryModel="+(string)InpDefaultEntryModel;
s+="|InpDefaultStopModel="+(string)InpDefaultStopModel;
s+="|InpDefaultTargetModel="+(string)InpDefaultTargetModel;
s+="|InpDefaultRequireIrlTouch="+(string)InpDefaultRequireIrlTouch;
s+="|InpDefaultRequireEntrySweep="+(string)InpDefaultRequireEntrySweep;
s+="|InpDefaultRequireDisplacementFvg="+(string)InpDefaultRequireDisplacementFvg;
s+="|InpDefaultRequireAsiaLiquidityDraw="+(string)InpDefaultRequireAsiaLiquidityDraw;
s+="|InpDefaultUseAsiaLiquidityTarget="+(string)InpDefaultUseAsiaLiquidityTarget;
s+="|InpDefaultRequireSmt="+(string)InpDefaultRequireSmt;
s+="|InpCalcHtfBars="+(string)InpCalcHtfBars;
s+="|InpCalcEntryBars="+(string)InpCalcEntryBars;
s+="|InpMaxSwings="+(string)InpMaxSwings;
s+="|InpMaxFvgSearchBars="+(string)InpMaxFvgSearchBars;
s+="|InpEntrySweepLookback="+(string)InpEntrySweepLookback;
s+="|InpEntrySweepMaxBars="+(string)InpEntrySweepMaxBars;
s+="|InpEntryFvgMaxWaitBars="+(string)InpEntryFvgMaxWaitBars;
s+="|InpEntryFvgTapMaxBars="+(string)InpEntryFvgTapMaxBars;
s+="|InpAtrPeriod="+(string)InpAtrPeriod;
s+="|InpMinFvgAtrPct="+(string)InpMinFvgAtrPct;
s+="|InpSlBufferAtrPct="+(string)InpSlBufferAtrPct;
s+="|InpSlDistancePct="+(string)InpSlDistancePct;
s+="|InpPipSlModeDefault="+(string)InpPipSlModeDefault;
s+="|InpPipSlPips="+(string)InpPipSlPips;
s+="|InpSmallStopThresholdPts="+(string)InpSmallStopThresholdPts;
s+="|InpSmallStopTarget="+(string)InpSmallStopTarget;
s+="|InpLargeStopTarget="+(string)InpLargeStopTarget;
s+="|InpAsiaStartHourGmt="+(string)InpAsiaStartHourGmt;
s+="|InpAsiaEndHourGmt="+(string)InpAsiaEndHourGmt;
s+="|InpSolSessionRouterEnabled="+(string)InpSolSessionRouterEnabled;
s+="|InpSolBrokerUtcOffsetMin="+(string)InpSolBrokerUtcOffsetMin;
s+="|InpSolContinuationStartGmt="+(string)InpSolContinuationStartGmt;
s+="|InpSolContinuationEndGmt="+(string)InpSolContinuationEndGmt;
s+="|InpSolContinuationQualityLow="+(string)InpSolContinuationQualityLow;
s+="|InpSolContinuationQualityHigh="+(string)InpSolContinuationQualityHigh;
s+="|InpSolRegimeFilterDefault="+(string)InpSolRegimeFilterDefault;
s+="|InpSolRegimeRf01Blocked="+(string)InpSolRegimeRf01Blocked;
s+="|InpSolRegimeRf02Blocked="+(string)InpSolRegimeRf02Blocked;
s+="|InpSolRegimeRf03Blocked="+(string)InpSolRegimeRf03Blocked;
s+="|InpSolRegimeRf04Blocked="+(string)InpSolRegimeRf04Blocked;
s+="|InpSolRegimeRf05Blocked="+(string)InpSolRegimeRf05Blocked;
s+="|InpSolRegimeRf06Blocked="+(string)InpSolRegimeRf06Blocked;
s+="|InpSolRegimeRf07Blocked="+(string)InpSolRegimeRf07Blocked;
s+="|InpSolRegimeRf08Blocked="+(string)InpSolRegimeRf08Blocked;
s+="|InpSolRegimeRf09Blocked="+(string)InpSolRegimeRf09Blocked;
s+="|InpSolRegimeRf10Blocked="+(string)InpSolRegimeRf10Blocked;
s+="|InpSolRegimeRf11Blocked="+(string)InpSolRegimeRf11Blocked;
s+="|InpSolRegimeRf12Blocked="+(string)InpSolRegimeRf12Blocked;
s+="|InpSmtSymbol="+(string)InpSmtSymbol;
s+="|InpSmtLookbackBars="+(string)InpSmtLookbackBars;
s+="|InpHistoricalDays="+(string)InpHistoricalDays;
s+="|InpHistoricalWeeks="+(string)InpHistoricalWeeks;
s+="|InpDrawHistoricalSignals="+(string)InpDrawHistoricalSignals;
s+="|InpDrawFvgZones="+(string)InpDrawFvgZones;
s+="|InpDrawLiveLevels="+(string)InpDrawLiveLevels;
s+="|InpFileBridgeEnabled="+(string)InpFileBridgeEnabled;
s+="|InpFileBridgeOnlyMode="+(string)InpFileBridgeOnlyMode;
s+="|InpNativeTradeWithBridgeOnlyDefault="+(string)InpNativeTradeWithBridgeOnlyDefault;
s+="|InpFileBridgeUseCommonFiles="+(string)InpFileBridgeUseCommonFiles;
s+="|InpFileBridgeLatestFile="+(string)InpFileBridgeLatestFile;
s+="|InpFileBridgeAuditPrefix="+(string)InpFileBridgeAuditPrefix;
s+="|InpBridgeChannel="+(string)InpBridgeChannel;
s+="|InpShowDashboard="+(string)InpShowDashboard;
s+="|InpDashboardX="+(string)InpDashboardX;
s+="|InpDashboardY="+(string)InpDashboardY;
s+="|InpAccountRiskEnabled="+(string)InpAccountRiskEnabled;
s+="|InpFtmoModeDefault="+(string)InpFtmoModeDefault;
s+="|InpRiskLotOnlyModeDefault="+(string)InpRiskLotOnlyModeDefault;
s+="|InpRiskPerTradePct="+(string)InpRiskPerTradePct;
s+="|InpMaxPortfolioRiskPct="+(string)InpMaxPortfolioRiskPct;
s+="|InpDailyLossLimitPct="+(string)InpDailyLossLimitPct;
s+="|InpMaxDrawdownPct="+(string)InpMaxDrawdownPct;
s+="|InpInitialBalanceOverride="+(string)InpInitialBalanceOverride;
s+="|InpFixedLot="+(string)InpFixedLot;
s+="|InpMaxLot="+(string)InpMaxLot;
s+="|InpDayResetHourGmt="+(string)InpDayResetHourGmt;
s+="|InpLiquidateOnBreach="+(string)InpLiquidateOnBreach;
s+="|InpAuditTradeCsv="+(string)InpAuditTradeCsv;
s+="|InpAuditPositionProbe="+(string)InpAuditPositionProbe;
s+="|InpAuditProbeSec="+(string)InpAuditProbeSec;
s+="|InpAuditProbeOnChangeOnly="+(string)InpAuditProbeOnChangeOnly;
s+="|InpAuditHistoryScanSec="+(string)InpAuditHistoryScanSec;
s+="|InpTesterTradeAuditCsv="+(string)InpTesterTradeAuditCsv;
s+="|InpTesterTradeAuditMaxRows="+(string)InpTesterTradeAuditMaxRows;
s+="|InpValidationJobId="+(string)InpValidationJobId;
s+="|InpValidationInternalAudit="+(string)InpValidationInternalAudit;
s+="|InpValidationInternalAuditWeeks="+(string)InpValidationInternalAuditWeeks;
s+="|InpValidationInternalAuditRows="+(string)InpValidationInternalAuditRows;
s+="|InpBacktestWeeks="+(string)InpBacktestWeeks;
s+="|InpBacktestFillMode="+(string)InpBacktestFillMode;
s+="|InpBacktestSameBarPolicy="+(string)InpBacktestSameBarPolicy;
s+="|InpBacktestUseTickReplay="+(string)InpBacktestUseTickReplay;
s+="|InpBacktestSpreadPts="+(string)InpBacktestSpreadPts;
s+="|InpBacktestSlippagePts="+(string)InpBacktestSlippagePts;
s+="|InpBacktestCommissionPerLot="+(string)InpBacktestCommissionPerLot;
return s;}
int LiqLibraryCapture(double &v[]){ArrayResize(v,41);
v[0]=(double)g_htf;
v[1]=(double)g_entryTf;
v[2]=(double)g_swingLookback;
v[3]=(double)g_target;
v[4]=(double)g_hc;
v[5]=(double)g_weeklyBias;
v[6]=(double)g_entryModel;
v[7]=(double)g_stopModel;
v[8]=(double)g_targetModel;
v[9]=(double)g_requireIrlTouch;
v[10]=(double)g_requireEntrySweep;
v[11]=(double)g_requireDisplacementFvg;
v[12]=(double)g_requireAsiaLiquidityDraw;
v[13]=(double)g_useAsiaLiquidityTarget;
v[14]=(double)g_requireSmt;
v[15]=(double)g_allowDuplicateEntries;
v[16]=(double)g_invertMode;
v[17]=(double)g_slDistancePct;
v[18]=(double)g_slBufferAtrPct;
v[19]=(double)g_pipSlMode;
v[20]=(double)g_pipSlPips;
v[21]=(double)g_histWeeks;
v[22]=(double)g_solRegimeFilterEnabled;
v[23]=(double)g_macroRegimeAllowed[0];
v[24]=(double)g_macroRegimeAllowed[1];
v[25]=(double)g_macroRegimeAllowed[2];
v[26]=(double)g_macroRegimeAllowed[3];
v[27]=(double)g_macroRegimeAllowed[4];
v[28]=(double)g_macroRegimeAllowed[5];
v[29]=(double)g_solRegimeRuleBlocked[0];
v[30]=(double)g_solRegimeRuleBlocked[1];
v[31]=(double)g_solRegimeRuleBlocked[2];
v[32]=(double)g_solRegimeRuleBlocked[3];
v[33]=(double)g_solRegimeRuleBlocked[4];
v[34]=(double)g_solRegimeRuleBlocked[5];
v[35]=(double)g_solRegimeRuleBlocked[6];
v[36]=(double)g_solRegimeRuleBlocked[7];
v[37]=(double)g_solRegimeRuleBlocked[8];
v[38]=(double)g_solRegimeRuleBlocked[9];
v[39]=(double)g_solRegimeRuleBlocked[10];
v[40]=(double)g_solRegimeRuleBlocked[11];
return ArraySize(v);}
void LiqLibraryAssign(const double &v[]){
g_htf=(ENUM_TIMEFRAMES)v[0];
g_entryTf=(ENUM_TIMEFRAMES)v[1];
g_swingLookback=(int)v[2];
g_target=(ERL_RR_MODE)v[3];
g_hc=(ERL_HC_MODE)v[4];
g_weeklyBias=(bool)v[5];
g_entryModel=(ERL_ENTRY_MODEL)v[6];
g_stopModel=(ERL_STOP_MODEL)v[7];
g_targetModel=(ERL_TARGET_MODEL)v[8];
g_requireIrlTouch=(bool)v[9];
g_requireEntrySweep=(bool)v[10];
g_requireDisplacementFvg=(bool)v[11];
g_requireAsiaLiquidityDraw=(bool)v[12];
g_useAsiaLiquidityTarget=(bool)v[13];
g_requireSmt=(bool)v[14];
g_allowDuplicateEntries=(bool)v[15];
g_invertMode=(bool)v[16];
g_slDistancePct=(double)v[17];
g_slBufferAtrPct=(double)v[18];
g_pipSlMode=(bool)v[19];
g_pipSlPips=(double)v[20];
g_histWeeks=(int)v[21];
g_solRegimeFilterEnabled=(bool)v[22];
g_macroRegimeAllowed[0]=(bool)v[23];
g_macroRegimeAllowed[1]=(bool)v[24];
g_macroRegimeAllowed[2]=(bool)v[25];
g_macroRegimeAllowed[3]=(bool)v[26];
g_macroRegimeAllowed[4]=(bool)v[27];
g_macroRegimeAllowed[5]=(bool)v[28];
g_solRegimeRuleBlocked[0]=(bool)v[29];
g_solRegimeRuleBlocked[1]=(bool)v[30];
g_solRegimeRuleBlocked[2]=(bool)v[31];
g_solRegimeRuleBlocked[3]=(bool)v[32];
g_solRegimeRuleBlocked[4]=(bool)v[33];
g_solRegimeRuleBlocked[5]=(bool)v[34];
g_solRegimeRuleBlocked[6]=(bool)v[35];
g_solRegimeRuleBlocked[7]=(bool)v[36];
g_solRegimeRuleBlocked[8]=(bool)v[37];
g_solRegimeRuleBlocked[9]=(bool)v[38];
g_solRegimeRuleBlocked[10]=(bool)v[39];
g_solRegimeRuleBlocked[11]=(bool)v[40];
}
#include "LiqStrategyLibrary.mqh"
