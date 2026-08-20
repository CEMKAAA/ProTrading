//+------------------------------------------------------------------+
//| NAS Ultimate Algo EA with SATS risk engine                       |
//| Partial TP variant: TP legs remain, no automatic SL -> BE.       |
//| Signal source: IndicatorCodeExamples/NasIndicator.pine           |
//| Risk source: SuperTrend_SATS_EA TP/SL logic                      |
//+------------------------------------------------------------------+
#property strict
#property version "1.55"

#include <Trade/Trade.mqh>
#include "NasUltimate_Core.mqh"
#include "SuperTrend_SATS_Core.mqh"
#include "LiqNarrativeSol_RegimeV3.mqh"
#include "LiqNarrativeMacroRegime.mqh"

#ifndef SATS_CORE_HAS_SIGNAL_RISK_HELPER
   #error "NasUltimate_SATS_EA requires the updated SuperTrend_SATS_Core.mqh from IndicatorCodeExamples. Copy/compile the matching .mqh next to this EA."
#endif

enum NAS_SIGNAL_BAR_MODE
{
   NAS_SIGNAL_BAR_LIVE = 0,
   NAS_SIGNAL_BAR_CLOSED = 1
};

enum NAS_RISK_ENGINE
{
   NAS_RISK_SATS = 0,
   NAS_RISK_PINE = 1
};

enum NAS_EXECUTION_MODE
{
   NAS_EXEC_PARTIAL_NO_BE = 0,
   NAS_EXEC_FIXED_1_TO_3R = 1,
   NAS_EXEC_PARTIAL_BE_ORIGINAL = 2
};

enum NAS_TP_MANAGEMENT_MODE
{
   NAS_TP_LEGACY_THREE_LEG = 0,
   NAS_TP_FIXED_SELECTED_LEG = 1
};

enum NAS_RISK_GEOMETRY_MODE
{
   NAS_RISK_GEOMETRY_NORMAL = 0,
   NAS_RISK_GEOMETRY_SCALP = 1,
   NAS_RISK_GEOMETRY_PIP = 2,
   NAS_RISK_GEOMETRY_SIGNAL_OPEN = 3
};

input int    InpNasSensitivity = 4;
input int    InpNasRsiLength = 14;
input int    InpNasAtrRisk = 1;
input int    InpNasAtrLen = 14;
input double InpPineRiskDistanceMultiplier = 1.125;
input bool   InpUseStructuralSwingStop = true;
input int    InpSwingLookbackBars = 80;
input int    InpSwingLeftBars = 3;
input int    InpSwingRightBars = 2;
input int    InpSwingAtrPeriod = 14;
input double InpSwingMinProminenceAtr = 0.75;
input double InpSwingMinDepartureAtr = 1.00;
input double InpSwingBufferAtr = 0.20;
input bool   InpAdaptiveSlWidenEnabled = true;
input double InpSlWidenTightPct = 30.0;
input double InpSlWidenNormalPct = 25.0;
input double InpSlWidenWidePct = 20.0;
input double InpFinalRiskScalePct = 75.0; // 100=unchanged; 75 trims final SL/TP distance by 25%.
input NAS_SIGNAL_BAR_MODE InpSignalBarMode = NAS_SIGNAL_BAR_CLOSED;
input NAS_RISK_ENGINE InpRiskEngine = NAS_RISK_PINE;
input bool   InpBlockSameDirectionUntilReverse = true;
input bool   InpUseTradingTimeWindow = true;
input string InpTradeStartTime = "09:00";
input string InpTradeEndTime = "14:00";
input bool   InpWindowReverseExit = false; // Close only the opposite managed position on an out-of-window signal.
input bool   InpUseVolumeFilter = false;   // ORB parity: signal tick volume must meet the previous-20-bar average threshold.
input double InpVolumeMultiplier = 1.00;   // Required signal volume = previous-20-bar average x this multiplier.
input string InpTimedExitTime = "";        // Maximum holding duration HH:MM after entry. Empty disables it; 04:00 means four hours.
input bool   InpSpreadGovernorEnabled = true;
input double InpSpreadGoodPoints = 0.0;    // 0 = auto by symbol
input double InpSpreadNormalPoints = 0.0;  // 0 = auto by symbol
input double InpSpreadWidePoints = 0.0;    // 0 = auto by symbol, red/blocked above this
input bool   InpEaEnabled = true;
input int    InpDashboardAuditWeeks = 2; // 2,5,10,20,52,104,156,208,260. Also controls historical signal overlay window.
input bool   InpDashboardUseAcceptedSignalFilter = false; // false=DUP ON, true=DUP OFF accepted alternating signals.
input bool   InpNasRegimeFilterDefault = false; // Default-off: block only causal H1/H2 NEUTRAL_ROTATION after NAS signal generation.
input NAS_TP_MANAGEMENT_MODE InpTpManagementMode = NAS_TP_FIXED_SELECTED_LEG;
input int    InpSelectedTpLeg = 6; // 1..6, where TP6 = 3R. Used by FIXED_SELECTED_LEG mode.
input double InpSelectedTargetR = 0.0; // 0=legacy InpSelectedTpLeg; 0.05R steps through 1R, then 1.5/2/2.5/3R.
input int    InpHcBeTpLeg = 0; // 0=off, otherwise move SL->BE when selected leg is touched before final TP.
input bool   InpInvertTradeMode = false; // Reverse execution: BUY<->SELL, original TP becomes SL, original SL becomes TP.
input int    InpInvertHcBeProgressPct = 0; // 0/25/50/75. Invert-only SL->BE trigger as pct of final TP path.
input int    InpInvertReferenceTpLeg = 0; // 0=INV REF SWAP: normal selected TP becomes inverted SL without changing value; 1..6 overrides inverted SL reference leg.
input double InpInvertTargetR = 0.0; // 0=pure swap: normal TP becomes SL and normal SL becomes TP. >0 overrides invert TP distance in R.
input bool   InpDashboardFtmoMode = false;
input bool   InpDashboardRiskLotOnlyMode = false;
input NAS_RISK_GEOMETRY_MODE InpRiskGeometryMode = NAS_RISK_GEOMETRY_NORMAL;
input double InpPipSlDistance = 30.0; // PIP geometry: fixed SL distance in pips, TP legs become 1R/2R/3R.
input int    InpScalpAtrPeriod = 14;
input double InpScalpAtrMultiplier = 0.70;
input double InpScalpMinAtrMultiplier = 0.20; // SCALP floor: minimum SL distance as ATR fraction to avoid micro stops.
input double InpScalpMinSignalRangePct = 25.0; // SCALP floor: minimum SL distance as pct of signal candle range.
input double InpScalpMaxOriginalRiskPct = 35.0; // SCALP caps risk to this pct of normal SL distance when possible.

input SATS_PRESET InpRiskPreset = SATS_PRESET_AUTO;
input SATS_SOURCE InpRiskSource = SATS_SOURCE_CLOSE;
input int    InpRiskAtrLen = 13;
input double InpRiskBaseMult = 2.0;
input bool   InpRiskUseAdaptive = true;
input int    InpRiskErLen = 20;
input double InpRiskAdaptStrength = 0.5;
input int    InpRiskAtrBaselineLen = 100;
input bool   InpRiskUseTqi = true;
input double InpRiskQualityStrength = 0.4;
input double InpRiskQualityCurve = 1.5;
input bool   InpRiskSmoothMult = true;
input bool   InpRiskUseAsymBands = true;
input double InpRiskAsymStrength = 0.5;
input bool   InpRiskUseEffAtr = true;
input bool   InpRiskUseCharFlip = true;
input int    InpRiskCharFlipMinAge = 5;
input double InpRiskCharFlipHigh = 0.55;
input double InpRiskCharFlipLow = 0.25;
input double InpRiskTqiWeightEr = 0.35;
input double InpRiskTqiWeightVol = 0.20;
input double InpRiskTqiWeightStruct = 0.25;
input double InpRiskTqiWeightMom = 0.20;
input int    InpRiskTqiStructLen = 20;
input int    InpRiskTqiMomLen = 10;
input int    InpRiskPivotLen = 3;
input int    InpRiskRsiLen = 14;
input int    InpRiskVolLen = 20;
input double InpRiskSlAtrMult = 1.5;
input double InpTp1R = 1.0;
input double InpTp2R = 2.0;
input double InpTp3R = 3.0;

input double InpTotalLot = 0.03;
input NAS_EXECUTION_MODE InpExecutionMode = NAS_EXEC_PARTIAL_NO_BE;
input double InpFixedLot = 0.03;
input double InpFixedRR = 3.0;
input bool   InpAdvancedLotEngineEnabled = true;
input int    InpAdvancedLotDailyAtrPeriod = 14;
input bool   InpAdvancedAccountRiskEnabled = true;
input double InpAccountRiskPerTradePct = 1.00;
input double InpAccountRiskDailyAtrExposurePct = 2.00;
input double InpAccountRiskMaxPortfolioPct = 4.00;
input double InpAccountRiskDailyLossLimitPct = 0.00;
input double InpAccountRiskMaxDrawdownPct = 0.00;
input double InpDailyProfitTargetPct = 0.00; // 0=off. Locks native execution and bridge publishing for the GMT trading day.
input double InpDailyMaxLossPct = 0.00;      // 0=off. Uses this instance's closed + floating PnL.
input double InpAccountRiskMaxMarginUsagePct = 40.00;
input double InpAccountRiskInitialBalanceOverride = 0.00;
input int    InpAccountRiskDayResetHourGmt = 0;
input bool   InpAccountRiskLiquidateOnBreach = true;
input double InpAccountRiskSafetyBufferPct = 95.00;
input double InpAdvancedLotMax = 0.00; // 0=broker maximum only.
input bool   InpAccountRiskBlockUnprotectedPositions = true;
input bool   InpAccountRiskFailClosed = true;
input bool   InpAccountRiskAuditEnabled = true;
input int    InpAccountRiskAuditIntervalSeconds = 60;
input int    InpDeviationPoints = 30;
input bool   InpEnforceTpTouchClose = true; // Safety watchdog: close managed positions if live price touches broker TP.
input double InpTpTouchCloseTolerancePoints = 2.0;
input int    InpTpTouchWatchdogTimerMs = 100;
input int    InpTpTouchCloseRetryCount = 2;
input long   InpMagic = 27052712;
input int    InpHistoryBars = 60000;
input int    InpSignalCalcBars = 5000;
input bool   InpCloseExistingOnNewSignal = true;
input bool   InpDrawTradeLevels = true;
input bool   InpDrawExecutionArrows = true;
input bool   InpTradeLatestSignalOnAttach = false;
input bool   InpDrawLastSignalsOnStart = true;
input int    InpStartupSignalCount = 3;
input bool   InpReconcileLiveSignalsOnBarClose = true;
input bool   InpCloseVanishedLiveSignalPosition = true;
input bool   InpSignalParityAudit = false; // Compact audit default: disable high-volume signal parity Print logs; trade lifecycle/error logs remain.
input bool   InpAuditNoSignalEvaluations = false;
input bool   InpShowDashboard = true;

CTrade trade;
long     g_runtimeMagic = 0;
datetime g_lastBarTime = 0;
datetime g_lastSignalTime = 0;
int      g_lastSignalKeyDirection = 0;
datetime g_processedBuySignalBarTime = 0;
datetime g_processedSellSignalBarTime = 0;

int      g_lastExecutedDirection = 0;
bool     g_pendingAccountRiskLockRetry = false;
datetime g_pendingAccountRiskLockSignalTime = 0;
int      g_pendingAccountRiskLockDirection = 0;
uint     g_pendingAccountRiskLockRetryDueMs = 0;
int      g_pendingAccountRiskLockRetryCount = 0;
datetime g_activeTradingWindowSessionKey = 0;
datetime g_liveSignalBarTime = 0;
int      g_liveSignalDirection = 0;
datetime g_lastNoSignalAuditBarTime = 0;
int      g_lastDirection = 0;
double   g_lastEntry = 0.0;
double   g_lastSl = 0.0;
double   g_lastTp1 = 0.0;
double   g_lastTp2 = 0.0;
double   g_lastTp3 = 0.0;
double   g_lastTp4 = 0.0;
double   g_lastTp5 = 0.0;
double   g_lastTp6 = 0.0;
bool     g_beMoved = false;
bool     g_liveLevelObjectsActive = false;
double   g_equityPeak = 0.0;
double   g_maxDd = 0.0;
string   g_historySummary[3];
string   g_historyAuditSummary = "Audit: -";
string   g_historyAuditDetail = "W/L/WR/PnL waiting";
string   g_historyAuditRows[7];
int      g_nasWeekdayWins[7];
int      g_nasWeekdayLosses[7];
string   g_tradeStartTimeRuntime = "";
string   g_tradeEndTimeRuntime = "";
double   g_totalLotRuntime = 0.0;
double   g_fixedLotRuntime = 0.0;
bool     g_eaEnabledRuntime = true;
string   g_lastExecutionStatus = "READY";
string   g_lastExecutionBlockReason = "";
bool     g_lastSignalBridgePublished = false;
double   g_lastSpreadPoints = 0.0;
string   g_lastSpreadStatus = "UNKNOWN";
double   g_spreadMaxPointsRuntime = 0.0;
uint     g_lastTpTouchWatchdogMs = 0;

struct NasTpWatchdogRetryState
{
   ulong ticket;
   datetime nextRetry;
   uint lastRetcode;
};
NasTpWatchdogRetryState g_tpWatchdogRetryStates[];
bool     g_lastRiskUsedStructuralStop = false;
double   g_lastRiskBaseSl = 0.0;
double   g_lastRiskSwingPrice = 0.0;
double   g_lastRiskSwingAtr = 0.0;
double   g_lastRiskSwingProminence = 0.0;
int      g_lastRiskSwingAgeBars = -1;
double   g_lastRiskPreWidenSl = 0.0;
double   g_lastRiskWidenPct = 0.0;
double   g_lastRiskFinalScalePct = 100.0;
double   g_finalRiskScalePctRuntime = 100.0;
double   g_swingBufferAtrRuntime = 0.0;
int      g_auditWeeksRuntime = 2;
bool     g_historyUseAcceptedFilterRuntime = false;
bool     g_nasRegimeFilterRuntime = false;
bool     g_nasRegimeWarmupPending = false;
int      g_nasRegimeRejectedLive = 0;
int      g_nasRegimeUnclassifiedLive = 0;
string   g_nasRegimeLastRule = "-";
string   g_nasRegimeLastDetail = "-";
int      g_nasMacroLastBucket = -1;
string   g_nasMacroLastDetail = "-";
bool     g_historyAuditRunning = false;
double   g_historyAuditProgressPct = 0.0;
bool     g_historyCoverageBlocked = false;
string   g_historyCoverageDetail = "";

struct NasRegimeCloseRetryState
{
   bool     active;
   datetime signalTime;
   int      closeDirection;
   string   rule;
   bool     bridgeDone;
   bool     localDone;
   datetime nextRetryLocal;
   int      attempts;
};
NasRegimeCloseRetryState g_nasRegimeCloseRetry;

struct NasTimedExitCloseState
{
   bool     active;
   datetime deadline;
   int      closeDirection;
   bool     bridgeDone;
   bool     localDone;
   datetime nextRetryLocal;
   int      attempts;
};
NasTimedExitCloseState g_nasTimedExitClose;

int      g_selectedTpLegRuntime = 6;
double   g_selectedTargetRRuntime = 3.0;
int      g_hcBeTpLegRuntime = 0;
int      g_invertHcBeProgressPctRuntime = 0;
int      g_invertReferenceTpLegRuntime = 0;
double   g_invertTargetRRuntime = 0.0;
bool     g_invertTradeModeRuntime = false;
bool     g_windowReverseExitRuntime = false;
bool     g_volumeFilterRuntime = false;
double   g_volumeMultiplierRuntime = 1.0;
string   g_timedExitTimeRuntime = "";
uint     g_volumeApplyFeedbackUntilMs = 0;
uint     g_timedExitApplyFeedbackUntilMs = 0;
uint     g_lastTimedExitGuardMs = 0;
int      g_timedExitBridgePlanDirection = 0;
datetime g_timedExitBridgePlanSignalTime = 0;
double   g_lastInvertedFinalTp = 0.0;
NAS_TP_MANAGEMENT_MODE g_tpManagementModeRuntime = NAS_TP_FIXED_SELECTED_LEG;
bool     g_ftmoModeRuntime = false;
bool     g_riskLotOnlyRuntime = false;
NAS_RISK_GEOMETRY_MODE g_riskGeometryModeRuntime = NAS_RISK_GEOMETRY_NORMAL;
double   g_pipSlDistanceRuntime = 30.0;
double   g_accountRiskPerTradePctRuntime = 1.0;
uint     g_riskPctApplyFeedbackUntilMs = 0;
double   g_dailyProfitTargetPctRuntime = 0.0;
double   g_dailyMaxLossPctRuntime = 0.0;
uint     g_dailyGuardApplyFeedbackUntilMs = 0;
double   g_lastAdvancedLot = 0.0;
string   g_lastAdvancedLotDetail = "";
uint     g_lastAccountRiskGuardMs = 0;
uint     g_lastDailyPnlGuardMs = 0;
double   g_accountRiskLockValue = 0.0;
double   g_accountRiskDailyPnlPct = 0.0;
double   g_dailyGuardPnlMoney = 0.0;
double   g_dailyGuardPnlPct = 0.0;
double   g_dailyGuardClosedToday = 0.0;
double   g_dailyGuardFloating = 0.0;
uint     g_dailyGuardScopeCacheMs = 0;
datetime g_dailyGuardScopeCacheDay = 0;

string PREFIX = "NAS_SATS_NO_BE_EA_";
uint     g_dashboardDoorStartMs = 0;

#include "NasUltimate_ProfessionalPipeline.mqh"

bool IsTesterMode()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

string NasRiskPctRuntimeKey()
{
   string symbolToken = _Symbol;
   StringReplace(symbolToken, ".", "_");
   StringReplace(symbolToken, " ", "_");
   StringReplace(symbolToken, "|", "_");
   return "NAS_RISK_PCT_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
      + "_" + IntegerToString(InpMagic) + "_" + symbolToken + "_" + IntegerToString((int)_Period);
}

double LoadNasRiskPctRuntime()
{
   double configured = MathMax(0.0, InpAccountRiskPerTradePct);
   if(IsTesterMode())
      return configured;
   string key = NasRiskPctRuntimeKey();
   if(!GlobalVariableCheck(key))
      return configured;
   double saved = GlobalVariableGet(key);
   return (saved > 0.0 && saved <= 100.0) ? saved : configured;
}

bool PersistNasRiskPctRuntime()
{
   if(IsTesterMode())
      return true;
   return GlobalVariableSet(NasRiskPctRuntimeKey(), g_accountRiskPerTradePctRuntime) > 0;
}

string NasDailyGuardRuntimeKey(const string kind)
{
   string symbolToken = _Symbol;
   StringReplace(symbolToken, ".", "_");
   StringReplace(symbolToken, " ", "_");
   StringReplace(symbolToken, "|", "_");
   symbolToken = StringSubstr(symbolToken, 0, 12);
   return "NAS_DAY_" + kind + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
      + "_" + IntegerToString(InpMagic) + "_" + symbolToken + "_" + IntegerToString((int)_Period);
}

double LoadNasDailyGuardRuntime(const string kind, const double configured)
{
   double fallback = MathMax(0.0, MathMin(100.0, configured));
   if(IsTesterMode())
      return fallback;
   string key = NasDailyGuardRuntimeKey(kind);
   if(!GlobalVariableCheck(key))
      return fallback;
   double saved = GlobalVariableGet(key);
   return saved >= 0.0 && saved <= 100.0 ? saved : fallback;
}

bool PersistNasDailyGuardRuntime()
{
   if(IsTesterMode())
      return true;
   bool profitOk = GlobalVariableSet(NasDailyGuardRuntimeKey("P"), g_dailyProfitTargetPctRuntime) > 0;
   bool lossOk = GlobalVariableSet(NasDailyGuardRuntimeKey("L"), g_dailyMaxLossPctRuntime) > 0;
   if(profitOk && lossOk)
      GlobalVariablesFlush();
   return profitOk && lossOk;
}

string NasInstanceRuntimeKey(const string kind)
{
   long chartPart = (long)(ChartID() % 1000000);
   return "NAS_CFG_" + kind + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
      + "_" + IntegerToString(InpMagic) + "_" + IntegerToString(chartPart);
}

bool NormalizeOptionalDuration(const string value, string &normalized, int &minutes)
{
   string text = value;
   StringTrimLeft(text);
   StringTrimRight(text);
   normalized = "";
   minutes = -1;
   if(text == "")
      return true;
   if(StringLen(text) != 5 || StringSubstr(text, 2, 1) != ":")
      return false;
   int digitPositions[] = {0, 1, 3, 4};
   for(int i = 0; i < ArraySize(digitPositions); ++i)
   {
      ushort ch = StringGetCharacter(text, digitPositions[i]);
      if(ch < '0' || ch > '9')
         return false;
   }
   int hour = (int)StringToInteger(StringSubstr(text, 0, 2));
   int minute = (int)StringToInteger(StringSubstr(text, 3, 2));
   if(hour < 0 || hour > 99 || minute < 0 || minute > 59)
      return false;
   minutes = hour * 60 + minute;
   if(minutes <= 0)
      return false;
   normalized = StringFormat("%02d:%02d", hour, minute);
   return true;
}

double ClampNasVolumeMultiplier(const double value)
{
   return NormalizeDouble(MathMax(0.05, MathMin(20.0, value)), 4);
}

void LoadNasOperationalRuntime()
{
   g_volumeFilterRuntime = InpUseVolumeFilter;
   g_volumeMultiplierRuntime = ClampNasVolumeMultiplier(InpVolumeMultiplier);
   string normalized = "";
   int minutes = -1;
   if(NormalizeOptionalDuration(InpTimedExitTime, normalized, minutes))
      g_timedExitTimeRuntime = normalized;
   else
      g_timedExitTimeRuntime = "";
   if(IsTesterMode())
      return;

   string volEnabledKey = NasInstanceRuntimeKey("VE");
   string volMultiplierKey = NasInstanceRuntimeKey("VM");
   string timedExitKey = NasInstanceRuntimeKey("TE");
   if(GlobalVariableCheck(volEnabledKey))
      g_volumeFilterRuntime = GlobalVariableGet(volEnabledKey) > 0.5;
   if(GlobalVariableCheck(volMultiplierKey))
      g_volumeMultiplierRuntime = ClampNasVolumeMultiplier(GlobalVariableGet(volMultiplierKey));
   if(GlobalVariableCheck(timedExitKey))
   {
      int encoded = (int)MathRound(GlobalVariableGet(timedExitKey));
      if(encoded <= 0)
         g_timedExitTimeRuntime = "";
      else
      {
         int savedMinutes = MathMax(1, MathMin(5999, encoded - 1));
         g_timedExitTimeRuntime = StringFormat("%02d:%02d", savedMinutes / 60, savedMinutes % 60);
      }
   }
}

bool PersistNasVolumeRuntime()
{
   if(IsTesterMode())
      return true;
   bool enabledOk = GlobalVariableSet(NasInstanceRuntimeKey("VE"), g_volumeFilterRuntime ? 1.0 : 0.0) > 0;
   bool multiplierOk = GlobalVariableSet(NasInstanceRuntimeKey("VM"), g_volumeMultiplierRuntime) > 0;
   if(enabledOk && multiplierOk)
      GlobalVariablesFlush();
   return enabledOk && multiplierOk;
}

bool PersistNasTimedExitRuntime()
{
   if(IsTesterMode())
      return true;
   string normalized = "";
   int minutes = -1;
   if(!NormalizeOptionalDuration(g_timedExitTimeRuntime, normalized, minutes))
      return false;
   double encoded = minutes < 0 ? 0.0 : (double)(minutes + 1);
   bool ok = GlobalVariableSet(NasInstanceRuntimeKey("TE"), encoded) > 0;
   if(ok)
      GlobalVariablesFlush();
   return ok;
}

void LoadNasTimedExitBridgePlan()
{
   g_timedExitBridgePlanDirection = 0;
   g_timedExitBridgePlanSignalTime = 0;
   if(IsTesterMode())
      return;
   string directionKey = NasInstanceRuntimeKey("BD");
   string timeKey = NasInstanceRuntimeKey("BT");
   if(GlobalVariableCheck(directionKey))
      g_timedExitBridgePlanDirection = (int)MathRound(GlobalVariableGet(directionKey));
   if(GlobalVariableCheck(timeKey))
      g_timedExitBridgePlanSignalTime = (datetime)MathRound(GlobalVariableGet(timeKey));
   if(MathAbs(g_timedExitBridgePlanDirection) != 1 || g_timedExitBridgePlanSignalTime <= 0)
   {
      g_timedExitBridgePlanDirection = 0;
      g_timedExitBridgePlanSignalTime = 0;
   }
}

void RememberNasTimedExitBridgePlan(const int direction, const datetime signalTime)
{
   if(MathAbs(direction) != 1 || signalTime <= 0)
      return;
   g_timedExitBridgePlanDirection = direction;
   g_timedExitBridgePlanSignalTime = signalTime;
   if(IsTesterMode())
      return;
   bool directionOk = GlobalVariableSet(NasInstanceRuntimeKey("BD"), direction) > 0;
   bool timeOk = GlobalVariableSet(NasInstanceRuntimeKey("BT"), (double)signalTime) > 0;
   if(directionOk && timeOk)
      GlobalVariablesFlush();
}

void ClearNasTimedExitBridgePlan()
{
   g_timedExitBridgePlanDirection = 0;
   g_timedExitBridgePlanSignalTime = 0;
   if(IsTesterMode())
      return;
   GlobalVariableDel(NasInstanceRuntimeKey("BD"));
   GlobalVariableDel(NasInstanceRuntimeKey("BT"));
   GlobalVariablesFlush();
}

bool AccountRiskRuntimeEnabled()
{
   return (g_ftmoModeRuntime || g_riskLotOnlyRuntime);
}

double EffectiveDailyLossLimitPct()
{
   return g_ftmoModeRuntime ? MathMax(0.0, InpAccountRiskDailyLossLimitPct) : 0.0;
}

double EffectiveMaxDrawdownPct()
{
   return g_ftmoModeRuntime ? MathMax(0.0, InpAccountRiskMaxDrawdownPct) : 0.0;
}

double EffectiveDailyProfitTargetPct()
{
   return MathMax(0.0, g_dailyProfitTargetPctRuntime);
}

double EffectiveDailyMaxLossPct()
{
   return MathMax(0.0, g_dailyMaxLossPctRuntime);
}

bool DailyPnlGuardConfigured()
{
   return EffectiveDailyProfitTargetPct() > 0.0 || EffectiveDailyMaxLossPct() > 0.0;
}

bool UseSingleOrderTpMode()
{
   return g_invertTradeModeRuntime || InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R || g_tpManagementModeRuntime == NAS_TP_FIXED_SELECTED_LEG;
}

int ClampTpLeg(const int leg)
{
   return MathMax(1, MathMin(6, leg));
}

int ClampHcBeLeg(const int leg)
{
   return MathMax(0, MathMin(5, leg));
}

double RMultipleForLeg(const int leg)
{
   return 0.5 * (double)ClampTpLeg(leg);
}

double NormalizeTargetPresetR(const double value)
{
   double options[] = {0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
                       0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00,
                       1.50, 2.00, 2.50, 3.00};
   double requested = MathMax(0.05, MathMin(3.0, value));
   double best = options[0];
   double distance = MathAbs(requested - best);
   for(int i = 1; i < ArraySize(options); ++i)
   {
      double candidateDistance = MathAbs(requested - options[i]);
      if(candidateDistance < distance)
      {
         best = options[i];
         distance = candidateDistance;
      }
   }
   return NormalizeDouble(best, 2);
}

double NextTargetPresetR(const double current)
{
   double options[] = {0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
                       0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.00,
                       1.50, 2.00, 2.50, 3.00};
   double normalized = NormalizeTargetPresetR(current);
   for(int i = 0; i < ArraySize(options); ++i)
      if(MathAbs(normalized - options[i]) < 0.001)
         return options[(i + 1) % ArraySize(options)];
   return options[0];
}

int LegacyLegForTargetR(const double targetR)
{
   return ClampTpLeg((int)MathFloor(MathMax(0.05, targetR) * 2.0 + 0.0001));
}

double SelectedTargetR()
{
   return NormalizeTargetPresetR(g_selectedTargetRRuntime);
}

double EffectiveInversionReferenceR()
{
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      return 3.0;
   if(g_invertReferenceTpLegRuntime > 0)
      return RMultipleForLeg(g_invertReferenceTpLegRuntime);
   return SelectedTargetR();
}

double LocalTargetPriceForR(const double entry, const double sl, const int direction, const double targetR)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0 || direction == 0 || targetR <= 0.0)
      return 0.0;
   return NormalizeDouble(direction > 0 ? entry + risk * targetR : entry - risk * targetR, _Digits);
}

double CurrentSelectedFinalTp(const int direction)
{
   if(g_invertTradeModeRuntime && g_lastInvertedFinalTp > 0.0)
      return NormalizeDouble(g_lastInvertedFinalTp, _Digits);
   double targetR = g_invertTradeModeRuntime ? EffectiveInversionReferenceR() : SelectedTargetR();
   return LocalTargetPriceForR(g_lastEntry, g_lastSl, direction, targetR);
}

string TargetRText(const double targetR)
{
   double oneDecimal = NormalizeDouble(targetR, 1);
   return DoubleToString(targetR, MathAbs(targetR - oneDecimal) < 0.0001 ? 1 : 2) + "R";
}

double TpPriceForLeg(const int direction, const int leg)
{
   double risk = MathAbs(g_lastEntry - g_lastSl);
   if(risk <= 0.0 || direction == 0)
      return 0.0;
   double rr = RMultipleForLeg(leg);
   return NormalizeDouble(direction > 0 ? g_lastEntry + risk * rr : g_lastEntry - risk * rr, _Digits);
}

double LocalTpPriceForLeg(const double entry, const double sl, const int direction, const int leg)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0 || direction == 0)
      return 0.0;
   double rr = RMultipleForLeg(leg);
   return NormalizeDouble(direction > 0 ? entry + risk * rr : entry - risk * rr, _Digits);
}
int EffectiveInversionReferenceLeg()
{
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      return 6;
   int refLeg = g_invertReferenceTpLegRuntime > 0 ? g_invertReferenceTpLegRuntime : LegacyLegForTargetR(SelectedTargetR());
   return ClampTpLeg(refLeg);
}
bool InvertReferenceSwapEnabled()
{
   return g_invertReferenceTpLegRuntime <= 0;
}

string EffectiveInversionReferenceText()
{
   if(InvertReferenceSwapEnabled())
      return "INV REF SWAP";
   return "INV REF TP" + IntegerToString(EffectiveInversionReferenceLeg());
}

int EffectiveHcBeLeg()
{
   return g_invertTradeModeRuntime ? 0 : g_hcBeTpLegRuntime;
}

double ClampInvertTargetR(const double value)
{
   if(value <= 0.0)
      return 0.0;
   if(value < 0.10)
      return 0.10;
   if(value > 10.0)
      return 10.0;
   return NormalizeDouble(value, 2);
}

bool InvertHcBeEnabled()
{
   return g_invertTradeModeRuntime && g_invertHcBeProgressPctRuntime > 0;
}

bool AnyHcBeEnabled()
{
   return InvertHcBeEnabled() || EffectiveHcBeLeg() > 0;
}

string EffectiveHcBeText()
{
   if(g_invertTradeModeRuntime)
      return g_invertHcBeProgressPctRuntime > 0 ? "INV HC " + IntegerToString(g_invertHcBeProgressPctRuntime) + "%" : "INV HC OFF";
   return g_hcBeTpLegRuntime > 0 ? "HCBE TP" + IntegerToString(g_hcBeTpLegRuntime) : "HCBE OFF";
}

string EffectiveTpSelectorText()
{
   if(g_invertTradeModeRuntime)
      return EffectiveInversionReferenceText();
   return "TP " + TargetRText(SelectedTargetR());
}

bool InvertTargetOverrideEnabled()
{
   return g_invertTargetRRuntime > 0.0;
}

string EffectiveInvertTargetText()
{
   if(!InvertTargetOverrideEnabled())
      return "INV TP SWAP";
   return "INV TP " + DoubleToString(g_invertTargetRRuntime, 2) + "R";
}

double InvertTargetOverridePrice(const int direction, const double entry, const double sl)
{
   double risk = MathAbs(entry - sl);
   if(!InvertTargetOverrideEnabled() || direction == 0 || entry <= 0.0 || sl <= 0.0 || risk <= 0.0)
      return 0.0;
   double targetDistance = MathMax(risk * ClampInvertTargetR(g_invertTargetRRuntime), NasExecutionMinStop());
   return NormalizeDouble(direction > 0 ? entry + targetDistance : entry - targetDistance, _Digits);
}

double InvertHcBePrice(const int direction, const double entry, const double finalTp)
{
   if(!InvertHcBeEnabled() || direction == 0 || entry <= 0.0 || finalTp <= 0.0)
      return 0.0;
   double progress = (double)g_invertHcBeProgressPctRuntime / 100.0;
   return NormalizeDouble(entry + (finalTp - entry) * progress, _Digits);
}

double HistoricalHcBePrice(const double entry, const double sl, const int direction, const double finalTp, const int finalLeg)
{
   if(g_invertTradeModeRuntime)
      return InvertHcBePrice(direction, entry, finalTp);
   double targetR = NasTargetR(direction, entry, sl, finalTp);
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL && targetR > 1.0 + 0.0001)
      return LocalTpPriceForLeg(entry, sl, direction, 1);
   if(g_hcBeTpLegRuntime > 0 && RMultipleForLeg(g_hcBeTpLegRuntime) < (MathAbs(finalTp - entry) / MathMax(MathAbs(entry - sl), _Point)) - 0.0001)
      return LocalTpPriceForLeg(entry, sl, direction, g_hcBeTpLegRuntime);
   return 0.0;
}

double CurrentFinalTpForLeg(const int direction, const int leg)
{
   if(g_invertTradeModeRuntime && g_lastInvertedFinalTp > 0.0)
      return NormalizeDouble(g_lastInvertedFinalTp, _Digits);
   return TpPriceForLeg(direction, leg);
}

bool BuildInvertedNasGeometry(const int signalDirection,
                              const int tradeDirection,
                              const double executionEntry,
                              const double signalEntry,
                              const double originalSl,
                              const double originalFinalTp,
                              double &entry,
                              double &sl,
                              double &finalTp,
                              string &detail)
{
   detail = "";
   if(signalDirection == 0 || tradeDirection == 0 || signalDirection == tradeDirection)
      return false;
   if(executionEntry <= 0.0 || signalEntry <= 0.0 || originalSl <= 0.0 || originalFinalTp <= 0.0)
      return false;

   double originalStopDistance = MathAbs(signalEntry - originalSl);
   double originalTargetDistance = MathAbs(originalFinalTp - signalEntry);
   double minStop = NasExecutionMinStop();
   if(originalStopDistance <= 0.0 || originalTargetDistance <= 0.0)
      return false;

   entry = NormalizeDouble(executionEntry, _Digits);

   // Exact invert swap: use the already-computed normal geometry prices directly.
   // Normal TP becomes the inverted SL; normal SL becomes the inverted TP.
   // Do not re-anchor these levels around execution entry, because that is not a swap.
   sl = NormalizeDouble(originalFinalTp, _Digits);
   finalTp = NormalizeDouble(originalSl, _Digits);

   // Optional INV TP override changes only the profit target. SL remains the swapped normal TP.
   double overrideTp = InvertTargetOverridePrice(tradeDirection, entry, sl);
   if(overrideTp > 0.0)
      finalTp = overrideTp;

   bool slOnCorrectSide = tradeDirection > 0 ? sl < entry : sl > entry;
   bool tpOnCorrectSide = tradeDirection > 0 ? finalTp > entry : finalTp < entry;
   if(!slOnCorrectSide || !tpOnCorrectSide)
   {
      detail = "invalid_exact_swap_side entry=" + DoubleToString(entry, _Digits)
             + " swapped_sl=" + DoubleToString(sl, _Digits)
             + " swapped_tp=" + DoubleToString(finalTp, _Digits)
             + " normal_sl=" + DoubleToString(originalSl, _Digits)
             + " normal_tp=" + DoubleToString(originalFinalTp, _Digits);
      return false;
   }

   if(MathAbs(entry - sl) <= minStop * 0.25 || MathAbs(entry - finalTp) <= minStop * 0.25)
   {
      detail = "invalid_exact_swap_too_close entry=" + DoubleToString(entry, _Digits)
             + " swapped_sl=" + DoubleToString(sl, _Digits)
             + " swapped_tp=" + DoubleToString(finalTp, _Digits)
             + " min_stop=" + DoubleToString(minStop, _Digits);
      return false;
   }

   detail = "inverted_execution signal_dir=" + IntegerToString(signalDirection)
          + " trade_dir=" + IntegerToString(tradeDirection)
          + " signal_entry=" + DoubleToString(signalEntry, _Digits)
          + " exec_entry=" + DoubleToString(entry, _Digits)
          + " original_sl_as_tp=" + DoubleToString(originalSl, _Digits)
          + " original_tp_as_sl=" + DoubleToString(originalFinalTp, _Digits)
          + " invert_target_mode=" + string(InvertTargetOverrideEnabled() ? "override" : "pure_swap")
          + " invert_ref_mode=" + EffectiveInversionReferenceText()
          + " exact_line_swap=" + string((!InvertTargetOverrideEnabled() && InvertReferenceSwapEnabled()) ? "true" : "false")
          + " invert_target_r=" + DoubleToString(g_invertTargetRRuntime, 2)
          + " original_sl_distance=" + DoubleToString(originalStopDistance, _Digits)
          + " final_sl=" + DoubleToString(sl, _Digits)
          + " final_tp=" + DoubleToString(finalTp, _Digits)
          + " invert_hcbe_pct=" + IntegerToString(g_invertHcBeProgressPctRuntime);
   return true;
}

void RefreshDerivedTpLadder(const int direction)
{
   g_lastTp1 = TpPriceForLeg(direction, 1);
   g_lastTp2 = TpPriceForLeg(direction, 2);
   g_lastTp3 = TpPriceForLeg(direction, 3);
   g_lastTp4 = TpPriceForLeg(direction, 4);
   g_lastTp5 = TpPriceForLeg(direction, 5);
   g_lastTp6 = TpPriceForLeg(direction, 6);
}

string TpModeText()
{
   return g_tpManagementModeRuntime == NAS_TP_FIXED_SELECTED_LEG ? "FIXED TP" : "LEGACY 3LEG";
}

int EffectiveAuditTpLeg()
{
   double targetR = g_invertTradeModeRuntime ? EffectiveInversionReferenceR()
      : (InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? MathMax(0.1, InpFixedRR) : SelectedTargetR());
   return LegacyLegForTargetR(targetR);
}

double EffectiveAuditNormalTargetR()
{
   return InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? MathMax(0.1, InpFixedRR) : SelectedTargetR();
}
int ClampNasAuditWeeks(const int requested)
{
   int options[] = {2, 5, 10, 20, 52, 104, 156, 208, 260};
   int best = options[0];
   int distance = MathAbs(requested - best);
   for(int i = 1; i < ArraySize(options); ++i)
   {
      int candidateDistance = MathAbs(requested - options[i]);
      if(candidateDistance < distance)
      {
         best = options[i];
         distance = candidateDistance;
      }
   }
   return best;
}

string NasAuditWindowLabel()
{
   if(g_auditWeeksRuntime >= 52 && g_auditWeeksRuntime % 52 == 0)
      return IntegerToString(g_auditWeeksRuntime / 52) + "Y";
   return IntegerToString(g_auditWeeksRuntime) + "W";
}

void ResetNasWeekdayAuditStats()
{
   for(int dow = 0; dow < 7; ++dow)
   {
      g_nasWeekdayWins[dow] = 0;
      g_nasWeekdayLosses[dow] = 0;
   }
}

string NasWeekdayAuditText(const int dow, const string name)
{
   if(dow < 1 || dow > 5)
      return name + " 0W 0L WR 0.0%";
   int wins = g_nasWeekdayWins[dow];
   int losses = g_nasWeekdayLosses[dow];
   int resolved = wins + losses;
   double wr = resolved > 0 ? (double)wins * 100.0 / (double)resolved : 0.0;
   return name + " " + IntegerToString(wins) + "W " + IntegerToString(losses)
      + "L WR " + DoubleToString(wr, 1) + "%";
}

color NasWeekdayAuditColor(const int dow)
{
   if(dow < 1 || dow > 5)
      return C'184,196,210';
   int wins = g_nasWeekdayWins[dow];
   int losses = g_nasWeekdayLosses[dow];
   if(wins + losses <= 0)
      return C'145,160,180';
   if(wins > losses)
      return C'80,255,180';
   if(wins < losses)
      return C'255,95,140';
   return C'255,204,82';
}

int NextAuditWeeks(const int cur)
{
   int options[] = {2, 5, 10, 20, 52, 104, 156, 208, 260};
   int normalized = ClampNasAuditWeeks(cur);
   for(int i = 0; i < ArraySize(options); ++i)
      if(options[i] == normalized)
         return options[(i + 1) % ArraySize(options)];
   return options[0];
}
uint     g_historyRefreshDueMs = 0;
bool     g_historyRefreshPending = false;

struct NasHistorySimCacheEntry
{
   string key;
   int maxTp;
   string outcome;
   double pnlR;
   bool closed;
   bool won;
};
NasHistorySimCacheEntry g_historySimCache[];

string NasHistorySimKey(const datetime signalTime,
                        const int direction,
                        const double entry,
                        const double sl,
                        const double finalTp,
                        const double hcPrice,
                        const int finalLeg,
                        const datetime endTime)
{
   return _Symbol + "|" + EnumToString(_Period)
          + "|" + IntegerToString((int)signalTime)
          + "|" + IntegerToString(direction)
          + "|" + DoubleToString(entry, _Digits)
          + "|" + DoubleToString(sl, _Digits)
          + "|" + DoubleToString(finalTp, _Digits)
          + "|" + DoubleToString(hcPrice, _Digits)
          + "|" + IntegerToString(finalLeg)
          + "|" + IntegerToString((int)endTime)
          + "|dup=" + IntegerToString(g_historyUseAcceptedFilterRuntime ? 0 : 1)
          + "|win=" + (g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime)
          + "-" + (g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime)
          + "|inv=" + IntegerToString(g_invertTradeModeRuntime ? 1 : 0)
          + "|exec=" + IntegerToString((int)InpExecutionMode)
          + "|tpm=" + IntegerToString((int)g_tpManagementModeRuntime)
          + "|sigmode=" + IntegerToString((int)InpSignalBarMode)
          + "|reverse=" + IntegerToString(InpCloseExistingOnNewSignal ? 1 : 0)
          + "|winrev=" + IntegerToString(g_windowReverseExitRuntime ? 1 : 0)
          + "|spread=" + IntegerToString(InpSpreadGovernorEnabled ? 1 : 0)
          + ":" + DoubleToString(g_spreadMaxPointsRuntime, 1);
}

bool NasHistorySimCacheGet(const string key, int &maxTp, string &outcome, double &pnlR, bool &closed, bool &won)
{
   for(int i = ArraySize(g_historySimCache) - 1; i >= 0; i--)
   {
      if(g_historySimCache[i].key != key)
         continue;
      maxTp = g_historySimCache[i].maxTp;
      outcome = g_historySimCache[i].outcome;
      pnlR = g_historySimCache[i].pnlR;
      closed = g_historySimCache[i].closed;
      won = g_historySimCache[i].won;
      return true;
   }
   return false;
}

void NasHistorySimCachePut(const string key, const int maxTp, const string outcome, const double pnlR, const bool closed, const bool won)
{
   int n = ArraySize(g_historySimCache);
   if(n > 3000)
   {
      ArrayFree(g_historySimCache);
      n = 0;
   }
   ArrayResize(g_historySimCache, n + 1);
   g_historySimCache[n].key = key;
   g_historySimCache[n].maxTp = maxTp;
   g_historySimCache[n].outcome = outcome;
   g_historySimCache[n].pnlR = pnlR;
   g_historySimCache[n].closed = closed;
   g_historySimCache[n].won = won;
}

void RequestHistoryRefresh()
{
   if(IsTesterMode())
      return;
   g_historyRefreshPending = true;
   g_historyRefreshDueMs = GetTickCount() + 750;
   g_dashboardForceNextUpdate = true;
   EventSetMillisecondTimer(250);
}

void ProcessPendingHistoryRefresh()
{
   if(!g_historyRefreshPending)
      return;
   if(g_dashboardCollapsed)
      return;
   if((int)(GetTickCount() - g_historyRefreshDueMs) < 0)
      return;
   g_historyRefreshPending = false;
   DrawRecentSignalHistory();
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
   ChartRedraw(0);
}
bool     g_dashboardDoorFinished = false;
bool     g_dashboardCollapsed = false;
bool     g_dashboardOpening = false;
uint     g_lastDashboardUpdateMs = 0;
bool     g_dashboardForceNextUpdate = false;
uint     g_visualMetricsCacheMs = 0;
struct NasVisualMetrics
{
   bool ok;
   double price;
   double superTrend;
   double sma13;
   double buyPct;
   double sellPct;
   bool buyArmed;
   bool sellArmed;
   string status;
};

NasVisualMetrics g_visualMetricsCache;

long RuntimeMagic()
{
   if(g_runtimeMagic != 0)
      return g_runtimeMagic;
   ulong chartId = ChartID();
   long chartPart = (long)(chartId % 1000000);
   if(AccountRiskRuntimeEnabled())
   {
      long safeInput = InpMagic % 1000000000000;
      if(safeInput < 0)
         safeInput = -safeInput;
      long safeBase = safeInput * 1000000 + chartPart;
      g_runtimeMagic = 4000000000000000000 + safeBase;
   }
   else
      g_runtimeMagic = InpMagic * 1000000 + chartPart;
   return g_runtimeMagic;
}

long NormalRuntimeMagic()
{
   long chartPart = (long)(ChartID() % 1000000);
   return InpMagic * 1000000 + chartPart;
}

long FtmoRuntimeMagic()
{
   long chartPart = (long)(ChartID() % 1000000);
   long safeInput = InpMagic % 1000000000000;
   if(safeInput < 0)
      safeInput = -safeInput;
   return 4000000000000000000 + safeInput * 1000000 + chartPart;
}

bool RuntimeMagicOwned(const long magic)
{
   return magic == NormalRuntimeMagic() || magic == FtmoRuntimeMagic();
}

int SignalBarsToCopy()
{
   return MathMax(InpSignalCalcBars, 300);
}

int LoadNasRates(MqlRates &rates[], const int barsToCopy, const bool applyLiveTick)
{
   int copied = CopyRates(_Symbol, _Period, 0, barsToCopy, rates);
   if(copied <= 0)
      return copied;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   if(applyLiveTick && copied > 0)
   {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick))
      {
         double liveClose = tick.bid > 0.0 ? tick.bid : (tick.last > 0.0 ? tick.last : rates[copied - 1].close);
         if(liveClose > 0.0)
         {
            int i = copied - 1;
            rates[i].close = liveClose;
            rates[i].high = MathMax(rates[i].high, liveClose);
            rates[i].low = MathMin(rates[i].low, liveClose);
         }
      }
   }
   return copied;
}

bool WasDirectionProcessedOnBar(const datetime signalTime, const int direction)
{
   if(direction > 0)
      return g_processedBuySignalBarTime == signalTime;
   if(direction < 0)
      return g_processedSellSignalBarTime == signalTime;
   return false;
}

void MarkDirectionProcessedOnBar(const datetime signalTime, const int direction)
{
   if(direction > 0)
      g_processedBuySignalBarTime = signalTime;
   else if(direction < 0)
      g_processedSellSignalBarTime = signalTime;
}

void ArmAccountRiskLockRetry(const datetime signalTime, const int direction)
{
   g_pendingAccountRiskLockRetry = true;
   g_pendingAccountRiskLockSignalTime = signalTime;
   g_pendingAccountRiskLockDirection = direction;
   g_pendingAccountRiskLockRetryCount++;
   g_pendingAccountRiskLockRetryDueMs = GetTickCount() + 250;
}

void ClearAccountRiskLockRetry()
{
   g_pendingAccountRiskLockRetry = false;
   g_pendingAccountRiskLockSignalTime = 0;
   g_pendingAccountRiskLockDirection = 0;
   g_pendingAccountRiskLockRetryDueMs = 0;
   g_pendingAccountRiskLockRetryCount = 0;
}

bool AccountRiskLockRetryDue()
{
   return g_pendingAccountRiskLockRetry && (int)(GetTickCount() - g_pendingAccountRiskLockRetryDueMs) >= 0;
}

void ClearLiveSignalObjects(const datetime signalTime, const int direction)
{
   if(signalTime <= 0 || direction == 0)
      return;
   string side = direction > 0 ? "BUY" : "SELL";
   string stamp = IntegerToString((int)signalTime) + "_" + side;
   ObjectDelete(0, PREFIX + "LIVE_EXEC_" + stamp + "_ARW");
   ObjectDelete(0, PREFIX + "LIVE_EXEC_" + stamp + "_TXT");
}

void ClearTradeLevelObjects()
{
   g_liveLevelObjectsActive = false;
   ObjectDelete(0, PREFIX + "ENTRY");
   ObjectDelete(0, PREFIX + "ENTRY_SEG");
   ObjectDelete(0, PREFIX + "SL");
   ObjectDelete(0, PREFIX + "TP1");
   ObjectDelete(0, PREFIX + "TP2");
   ObjectDelete(0, PREFIX + "TP3");
   ObjectDelete(0, PREFIX + "TP4");
   ObjectDelete(0, PREFIX + "TP5");
   ObjectDelete(0, PREFIX + "TP6");
   ObjectDelete(0, PREFIX + "TP_SELECTED");
   ObjectDelete(0, PREFIX + "HCBE");
   ObjectDelete(0, PREFIX + "ENTRY_TXT");
   ObjectDelete(0, PREFIX + "SL_TXT");
   ObjectDelete(0, PREFIX + "TP1_TXT");
   ObjectDelete(0, PREFIX + "TP2_TXT");
   ObjectDelete(0, PREFIX + "TP3_TXT");
   ObjectDelete(0, PREFIX + "TP4_TXT");
   ObjectDelete(0, PREFIX + "TP5_TXT");
   ObjectDelete(0, PREFIX + "TP6_TXT");
   ObjectDelete(0, PREFIX + "TP_SELECTED_TXT");
   ObjectDelete(0, PREFIX + "HCBE_TXT");
}

void HydrateExecutedDirectionFromOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!RuntimeMagicOwned((long)PositionGetInteger(POSITION_MAGIC)))
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      g_lastExecutedDirection = type == POSITION_TYPE_BUY ? 1 : -1;
      Print("NAS SATS EA hydrated last executed direction from open position dir=",
            (g_lastExecutedDirection > 0 ? "BUY" : "SELL"),
            " ticket=", ticket);
      return;
   }
}

int ParseClockMinutes(const string value, const int fallbackMinutes)
{
   int colon = StringFind(value, ":");
   if(colon <= 0)
      return fallbackMinutes;
   int hour = (int)StringToInteger(StringSubstr(value, 0, colon));
   int minute = (int)StringToInteger(StringSubstr(value, colon + 1));
   if(hour == 24 && minute == 0)
      return 24 * 60;
   if(hour < 0 || hour > 23 || minute < 0 || minute > 59)
      return fallbackMinutes;
   return hour * 60 + minute;
}

bool NasTimedExitConfigured()
{
   string normalized = "";
   int minutes = -1;
   return NormalizeOptionalDuration(g_timedExitTimeRuntime, normalized, minutes) && minutes > 0;
}

int NasTimedExitMinutes()
{
   string normalized = "";
   int minutes = -1;
   return NormalizeOptionalDuration(g_timedExitTimeRuntime, normalized, minutes) ? minutes : -1;
}

datetime NasTimedExitDeadlineForEntry(const datetime entryServerTime)
{
   int holdMinutes = NasTimedExitMinutes();
   if(holdMinutes <= 0 || entryServerTime <= 0)
      return 0;
   return entryServerTime + (datetime)(holdMinutes * 60);
}

bool NasVolumeFilterAllows(const MqlRates &rates[], const int signalIndex,
                           string &reason, double &signalVolume, double &averageVolume)
{
   reason = "";
   signalVolume = 0.0;
   averageVolume = 0.0;
   if(!g_volumeFilterRuntime)
      return true;
   const int lookback = 20;
   if(signalIndex < lookback || signalIndex >= ArraySize(rates))
   {
      reason = "VOL_DATA_FAIL_OPEN";
      return true;
   }
   signalVolume = (double)rates[signalIndex].tick_volume;
   double sum = 0.0;
   for(int i = signalIndex - 1; i >= signalIndex - lookback; --i)
   {
      if(rates[i].tick_volume > 0)
         sum += (double)rates[i].tick_volume;
   }
   averageVolume = sum / (double)lookback;
   if(averageVolume <= 0.0)
   {
      reason = "VOL_DATA_FAIL_OPEN";
      return true;
   }
   double threshold = averageVolume * g_volumeMultiplierRuntime;
   if(signalVolume < threshold)
   {
      reason = "VOL_LOW " + DoubleToString(signalVolume, 0) + "<" + DoubleToString(threshold, 0);
      return false;
   }
   return true;
}

int ServerClockMinutes()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour * 60 + dt.min;
}

bool IsTradingTimeOpen()
{
   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   int startMin = ParseClockMinutes(startText, 0);
   int endMin = ParseClockMinutes(endText, 1439);
   if(startMin == endMin)
      return true;
   int nowMin = ServerClockMinutes();
   if(startMin < endMin)
      return nowMin >= startMin && nowMin <= endMin;
   return nowMin >= startMin || nowMin <= endMin;
}
bool IsTradingTimeOpenAt(const datetime serverTime)
{
   if(!InpUseTradingTimeWindow)
      return true;
   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   int startMin = ParseClockMinutes(startText, 0);
   int endMin = ParseClockMinutes(endText, 1439);
   if(startMin == endMin)
      return true;
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   int minute = dt.hour * 60 + dt.min;
   if(startMin < endMin)
      return minute >= startMin && minute <= endMin;
   return minute >= startMin || minute <= endMin;
}
datetime TradingWindowSessionKeyAt(const datetime serverTime)
{
   if(!InpUseTradingTimeWindow)
      return 0;

   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   int startMin = ParseClockMinutes(startText, 0);
   int endMin = ParseClockMinutes(endText, 1439);
   if(startMin == endMin)
      return 0;

   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   int minute = dt.hour * 60 + dt.min;
   if(startMin < endMin && (minute < startMin || minute > endMin))
      return 0;
   if(startMin > endMin && minute > endMin && minute < startMin)
      return 0;

   int sessionDayShift = (startMin > endMin && minute <= endMin) ? -86400 : 0;
   dt.hour = startMin / 60;
   dt.min = startMin % 60;
   dt.sec = 0;
   return StructToTime(dt) + sessionDayShift;
}

void RefreshTradingWindowSessionLock(const datetime serverTime, const bool resetOnNewSession)
{
   datetime sessionKey = TradingWindowSessionKeyAt(serverTime);
   if(sessionKey <= 0)
      return;

   if(g_activeTradingWindowSessionKey == 0)
   {
      g_activeTradingWindowSessionKey = sessionKey;
      return;
   }

   if(sessionKey != g_activeTradingWindowSessionKey)
   {
      int previousDirection = g_lastExecutedDirection;
      g_activeTradingWindowSessionKey = sessionKey;
      if(resetOnNewSession)
      {
         g_lastExecutedDirection = 0;
         g_processedBuySignalBarTime = 0;
         g_processedSellSignalBarTime = 0;
         Print("NAS SATS EA trading-window session reset same-direction lock session=",
               TimeToString(sessionKey, TIME_DATE|TIME_MINUTES),
               " previous_lock=", (previousDirection > 0 ? "BUY" : (previousDirection < 0 ? "SELL" : "NONE")));
      }
   }
}
string TradingTimeStateText()
{
   string startText = g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime;
   string endText = g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime;
   return string(IsTradingTimeOpen() ? "OPEN " : "CLOSED ")
          + startText + "-" + endText
          + " server=" + TimeToString(TimeCurrent(), TIME_MINUTES);
}

void AutoSpreadThresholds(double &goodPts, double &normalPts, double &widePts)
{
   string sym = _Symbol;
   StringToUpper(sym);

   goodPts = 100.0;
   normalPts = 300.0;
   widePts = 800.0;

   if(StringFind(sym, "USTEC") >= 0 || StringFind(sym, "NAS") >= 0 || StringFind(sym, "US100") >= 0 || StringFind(sym, "NDX") >= 0)
   {
      goodPts = 180.0;
      normalPts = 350.0;
      widePts = 800.0;
   }
   else if(StringFind(sym, "DE30") >= 0 || StringFind(sym, "GER40") >= 0 || StringFind(sym, "DAX") >= 0)
   {
      goodPts = 35.0;
      normalPts = 80.0;
      widePts = 200.0;
   }
   else if(StringFind(sym, "UK100") >= 0 || StringFind(sym, "FTSE") >= 0)
   {
      goodPts = 120.0;
      normalPts = 250.0;
      widePts = 500.0;
   }
   else if(StringFind(sym, "FR40") >= 0 || StringFind(sym, "CAC") >= 0)
   {
      goodPts = 180.0;
      normalPts = 450.0;
      widePts = 1000.0;
   }
   else if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      goodPts = 180.0;
      normalPts = 350.0;
      widePts = 800.0;
   }
   else if(StringFind(sym, "EUR") >= 0 || StringFind(sym, "GBP") >= 0 || StringFind(sym, "USD") >= 0 || StringFind(sym, "JPY") >= 0)
   {
      goodPts = 20.0;
      normalPts = 50.0;
      widePts = 120.0;
   }

   if(InpSpreadGoodPoints > 0.0)
      goodPts = InpSpreadGoodPoints;
   if(InpSpreadNormalPoints > 0.0)
      normalPts = InpSpreadNormalPoints;
   if(InpSpreadWidePoints > 0.0)
      widePts = InpSpreadWidePoints;

   if(g_spreadMaxPointsRuntime > 0.0)
      widePts = g_spreadMaxPointsRuntime;

   normalPts = MathMax(normalPts, goodPts);
   if(g_spreadMaxPointsRuntime > 0.0)
   {
      normalPts = MathMin(normalPts, widePts);
      goodPts = MathMin(goodPts, normalPts);
   }
   else
   {
      widePts = MathMax(widePts, normalPts);
   }
}

bool SpreadSnapshot(double &bid,
                    double &ask,
                    double &spreadPts,
                    string &status,
                    color &statusColor,
                    double &goodPts,
                    double &normalPts,
                    double &widePts)
{
   AutoSpreadThresholds(goodPts, normalPts, widePts);

   MqlTick tick;
   bool hasTick = SymbolInfoTick(_Symbol, tick);
   bid = hasTick && tick.bid > 0.0 ? tick.bid : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ask = hasTick && tick.ask > 0.0 ? tick.ask : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(bid <= 0.0 || ask <= 0.0 || point <= 0.0)
   {
      spreadPts = 0.0;
      status = "BLOCKED";
      statusColor = C'221,55,78';
      return false;
   }

   spreadPts = MathMax(0.0, (ask - bid) / point);
   if(spreadPts <= goodPts)
   {
      status = "GOOD";
      statusColor = C'80,255,180';
      return true;
   }
   if(spreadPts <= normalPts)
   {
      status = "NORMAL";
      statusColor = C'90,178,255';
      return true;
   }
   if(spreadPts <= widePts)
   {
      status = "WIDE";
      statusColor = C'255,204,82';
      return true;
   }

   if(g_spreadMaxPointsRuntime <= 0.0)
   {
      status = "NO-BLOCK";
      statusColor = C'255,204,82';
      return true;
   }

   status = "BLOCKED";
   statusColor = C'221,55,78';
   return false;
}

bool IsSpreadExecutionAllowed(string &reason)
{
   double bid, ask, spreadPts, goodPts, normalPts, widePts;
   string status;
   color statusColor;
   bool allowed = SpreadSnapshot(bid, ask, spreadPts, status, statusColor, goodPts, normalPts, widePts);
   g_lastSpreadPoints = spreadPts;
   g_lastSpreadStatus = status;

   if(!InpSpreadGovernorEnabled)
   {
      reason = "spread_governor_disabled";
      return true;
   }

   if(allowed)
   {
      reason = status + "_SPREAD";
      return true;
   }

   reason = "spread_blocked status=" + status
            + " spread_pts=" + DoubleToString(spreadPts, 0)
            + " good=" + DoubleToString(goodPts, 0)
            + " normal=" + DoubleToString(normalPts, 0)
            + " wide=" + DoubleToString(widePts, 0);
   return false;
}

NasSettings BuildNasSettings()
{
   NasSettings s;
   s.sensitivity = InpNasSensitivity;
   s.rsiLength = InpNasRsiLength;
   s.atrRisk = InpNasAtrRisk;
   s.atrLen = InpNasAtrLen;
   return s;
}

SATSSettings BuildRiskSettings()
{
   SATSSettings s;
   s.preset = InpRiskPreset;
   s.source = InpRiskSource;
   s.atrLen = InpRiskAtrLen;
   s.baseMult = InpRiskBaseMult;
   s.useAdaptive = InpRiskUseAdaptive;
   s.erLen = InpRiskErLen;
   s.adaptStrength = InpRiskAdaptStrength;
   s.atrBaselineLen = InpRiskAtrBaselineLen;
   s.useTqi = InpRiskUseTqi;
   s.qualityStrength = InpRiskQualityStrength;
   s.qualityCurve = InpRiskQualityCurve;
   s.smoothMult = InpRiskSmoothMult;
   s.useAsymBands = InpRiskUseAsymBands;
   s.asymStrength = InpRiskAsymStrength;
   s.useEffAtr = InpRiskUseEffAtr;
   s.useCharFlip = InpRiskUseCharFlip;
   s.charFlipMinAge = InpRiskCharFlipMinAge;
   s.charFlipHigh = InpRiskCharFlipHigh;
   s.charFlipLow = InpRiskCharFlipLow;
   s.tqiWeightEr = InpRiskTqiWeightEr;
   s.tqiWeightVol = InpRiskTqiWeightVol;
   s.tqiWeightStruct = InpRiskTqiWeightStruct;
   s.tqiWeightMom = InpRiskTqiWeightMom;
   s.tqiStructLen = InpRiskTqiStructLen;
   s.tqiMomLen = InpRiskTqiMomLen;
   s.pivotLen = InpRiskPivotLen;
   s.rsiLen = InpRiskRsiLen;
   s.volLen = InpRiskVolLen;
   s.slAtrMult = InpRiskSlAtrMult;
   s.tp1R = InpTp1R;
   s.tp2R = InpTp2R;
   s.tp3R = InpTp3R;
   s.tradeMaxAge = 100;
   s.useAutoCalib = false;
   s.calibWindow = 20;
   s.calibBadR = 0.0;
   s.calibGoodR = 0.7;
   s.calibStepQ = 0.05;
   s.calibCooldown = 5;
   s.calibMinQ = 0.1;
   s.calibMaxQ = 0.9;
   return s;
}

int OnInit()
{
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(InpExecutionMode != NAS_EXEC_FIXED_1_TO_3R && marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("NAS SATS initialization blocked: partial three-leg execution requires a hedging account. margin_mode=",
            EnumToString(marginMode));
      return INIT_PARAMETERS_INCORRECT;
   }
   g_tradeStartTimeRuntime = InpTradeStartTime;
   g_tradeEndTimeRuntime = InpTradeEndTime;
   g_windowReverseExitRuntime = InpWindowReverseExit;
   LoadNasOperationalRuntime();
   LoadNasTimedExitBridgePlan();
   g_totalLotRuntime = InpTotalLot;
   g_fixedLotRuntime = InpFixedLot;
   g_spreadMaxPointsRuntime = MathMax(0.0, InpSpreadWidePoints);
   g_eaEnabledRuntime = InpEaEnabled;
   g_finalRiskScalePctRuntime = MathMax(10.0, MathMin(500.0, InpFinalRiskScalePct));
   g_swingBufferAtrRuntime = MathMax(0.0, InpSwingBufferAtr);
   g_auditWeeksRuntime = ClampNasAuditWeeks(InpDashboardAuditWeeks);
   g_historyUseAcceptedFilterRuntime = InpDashboardUseAcceptedSignalFilter;
   g_nasRegimeFilterRuntime = InpNasRegimeFilterDefault;
   LiqMacroRegimeInit();
   g_selectedTpLegRuntime = ClampTpLeg(InpSelectedTpLeg);
   g_selectedTargetRRuntime = NormalizeTargetPresetR(InpSelectedTargetR > 0.0 ? InpSelectedTargetR : RMultipleForLeg(g_selectedTpLegRuntime));
   g_hcBeTpLegRuntime = ClampHcBeLeg(InpHcBeTpLeg);
   g_invertHcBeProgressPctRuntime = (InpInvertHcBeProgressPct == 25 || InpInvertHcBeProgressPct == 50 || InpInvertHcBeProgressPct == 75) ? InpInvertHcBeProgressPct : 0;
   g_invertReferenceTpLegRuntime = InpInvertReferenceTpLeg > 0 ? ClampTpLeg(InpInvertReferenceTpLeg) : 0;
   g_invertTargetRRuntime = ClampInvertTargetR(InpInvertTargetR);
   g_invertTradeModeRuntime = InpInvertTradeMode;
   g_tpManagementModeRuntime = InpTpManagementMode;
   bool explicitFtmoMode = InpDashboardFtmoMode;
   bool explicitRiskLotOnlyMode = InpDashboardRiskLotOnlyMode;
   if(explicitFtmoMode && !explicitRiskLotOnlyMode)
   {
      g_ftmoModeRuntime = true;
      g_riskLotOnlyRuntime = false;
   }
   else if(explicitRiskLotOnlyMode && !explicitFtmoMode)
   {
      g_ftmoModeRuntime = false;
      g_riskLotOnlyRuntime = true;
   }
   else if(explicitFtmoMode && explicitRiskLotOnlyMode)
   {
      // Presets should not enable both, but fail conservative if they do.
      g_ftmoModeRuntime = true;
      g_riskLotOnlyRuntime = false;
   }
   else
   {
      g_ftmoModeRuntime = InpAdvancedAccountRiskEnabled && (InpAccountRiskDailyLossLimitPct > 0.0 || InpAccountRiskMaxDrawdownPct > 0.0);
      g_riskLotOnlyRuntime = !g_ftmoModeRuntime && InpAdvancedAccountRiskEnabled;
   }
   g_riskGeometryModeRuntime = InpRiskGeometryMode;
   g_pipSlDistanceRuntime = MathMax(0.0, InpPipSlDistance);
   g_accountRiskPerTradePctRuntime = LoadNasRiskPctRuntime();
   g_dailyProfitTargetPctRuntime = LoadNasDailyGuardRuntime("P", InpDailyProfitTargetPct);
   g_dailyMaxLossPctRuntime = LoadNasDailyGuardRuntime("L", InpDailyMaxLossPct);
   g_runtimeMagic = 0;
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   HydrateExecutedDirectionFromOpenPosition();
   RefreshTradingWindowSessionLock(TimeCurrent(), false);
   PrintStartupDiagnostics();
   BaselineStartupSignal();
   NasProInit();
   if(DailyPnlGuardConfigured() && g_nasBridgeOnlyRuntime && !g_nasNativeWithBridgeOnlyRuntime)
      Print("NAS SATS DAILY PNL GUARD WARNING: bridge-only mode has no native MT5 PnL proxy; "
            "new-signal CSV blocking remains armed, but listener-account PnL cannot be measured by MT5.");
   if(g_nasRegimeFilterRuntime)
   {
      if(IsTesterMode())
      {
         RegimeV3Update(true);
         g_nasRegimeWarmupPending = false;
      }
      else
      {
         g_nasRegimeWarmupPending = true;
         g_regimeV3LastSourceOpen = 0;
         g_regimeV3LastAttemptLocal = 0;
      }
   }
   if(!IsTesterMode())
   {
      DrawDashboard();
      EventSetMillisecondTimer(250);
      if(InpDrawLastSignalsOnStart)
      {
         g_historyAuditRows[0] = "Audit loading...";
         g_historyAuditRows[1] = "Historical overlay deferred after attach";
         g_historyAuditRows[2] = "Dashboard is ready; heavy replay runs on timer";
         g_historyAuditRows[3] = "-";
         g_historyAuditRows[4] = "-";
         g_historyAuditRows[5] = "-";
         g_historyAuditRows[6] = "-";
         g_historyAuditSummary = "Audit loading";
         g_historyAuditDetail = "deferred history replay";
         UpdateDashboard();
         RequestHistoryRefresh();
         g_historyRefreshDueMs = GetTickCount() + 1500;
      }
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PREFIX);
}

void OnTimer()
{
   if(IsTesterMode())
      return;
   NasProTimer();
   NasRegimeRetryPendingClose();
   EnforceNasTimedExit();
   if(g_nasRegimeFilterRuntime)
   {
      bool wasWarmupPending = g_nasRegimeWarmupPending;
      RegimeV3Update(false);
      if(wasWarmupPending && g_regimeV3.valid && ArraySize(g_regimeV3Timeline) > 0)
      {
         g_nasRegimeWarmupPending = false;
         g_nasRegimeLastRule = "ARMED";
         g_nasRegimeLastDetail = "H1H2_NEUTRAL_ROTATION_READY";
         g_historyAuditRows[0] = "Audit loading after regime warmup...";
         g_historyAuditSummary = "Audit loading";
         g_historyAuditDetail = "deferred causal regime replay";
         RequestHistoryRefresh();
         g_dashboardForceNextUpdate = true;
      }
   }
   ProcessPendingHistoryRefresh();
   EnforceDailyPnlGuard();
   EnforceAccountRiskBreach();
   WriteAccountRiskAudit("snapshot", "periodic_health", true);
   EnforceManagedTpTouchClose(false);
   if(!g_dashboardDoorFinished || g_dashboardForceNextUpdate)
      UpdateDashboard();
}

void OnTick()
{
   EnforceNasTimedExit();
   EnforceDailyPnlGuard();
   EnforceAccountRiskBreach();
   ManageOpenPositions();
   NasProUpdateOpenPositions();
   ReconcileClosedManagedPositionVisuals();
   if(!IsTesterMode())
      UpdateDashboard();

   if(InpSignalBarMode == NAS_SIGNAL_BAR_LIVE)
   {
      datetime curBar = iTime(_Symbol, _Period, 0);
      if(curBar != 0 && curBar != g_lastBarTime)
      {
         if(g_lastBarTime != 0)
            ReconcileLiveSignalAfterBarClose();
         g_lastBarTime = curBar;
      }
      ProcessSignalBar();
      return;
   }

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == 0)
      return;
   if(curBar == g_lastBarTime)
   {
      if(AccountRiskLockRetryDue())
         ProcessSignalBar();
      return;
   }
   g_lastBarTime = curBar;
   ProcessSignalBar();
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   NasProOnTradeTransaction(trans, request, result);
}

void PrintStartupDiagnostics()
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double leg = LegVolume();

   Print("NAS SATS Partial-NoBE EA initialized symbol=", _Symbol,
         " timeframe=", EnumToString(_Period),
         " runtime_magic=", RuntimeMagic(),
         " chart_id=", (long)ChartID(),
         " execution_mode=", EnumToString(InpExecutionMode),
         " signal_bar_mode=", EnumToString(InpSignalBarMode),
         " ea_enabled=", InpEaEnabled);
   Print("NAS SATS config risk_engine=", EnumToString(InpRiskEngine),
         " risk_preset=", EnumToString(InpRiskPreset),
         " risk_source=", EnumToString(InpRiskSource),
         " history_bars=", InpHistoryBars,
         " signal_calc_bars=", SignalBarsToCopy(),
         " total_lot=", DoubleToString(InpTotalLot, 8),
         " fixed_lot=", DoubleToString(InpFixedLot, 8),
         " fixed_rr=", DoubleToString(InpFixedRR, 2),
         " same_direction_hard_safety=true");
   Print("NAS SATS structural_stop enabled=", InpUseStructuralSwingStop,
         " lookback=", InpSwingLookbackBars,
         " left=", InpSwingLeftBars,
         " right=", InpSwingRightBars,
         " atr_period=", InpSwingAtrPeriod,
         " min_prominence_atr=", DoubleToString(InpSwingMinProminenceAtr, 2),
         " min_departure_atr=", DoubleToString(InpSwingMinDepartureAtr, 2),
         " buffer_atr=", DoubleToString(InpSwingBufferAtr, 2),
         " adaptive_widen=", InpAdaptiveSlWidenEnabled,
         " widen_tight_pct=", DoubleToString(InpSlWidenTightPct, 1),
         " widen_normal_pct=", DoubleToString(InpSlWidenNormalPct, 1),
         " widen_wide_pct=", DoubleToString(InpSlWidenWidePct, 1),
         " final_scale_pct=", DoubleToString(InpFinalRiskScalePct, 1));
   Print("NAS SATS execution spread_governor_enabled=", InpSpreadGovernorEnabled,
         " spread_good_pts=", DoubleToString(InpSpreadGoodPoints, 1),
         " spread_normal_pts=", DoubleToString(InpSpreadNormalPoints, 1),
         " spread_wide_pts=", DoubleToString(InpSpreadWidePoints, 1),
         " enforce_tp_touch_close=", InpEnforceTpTouchClose,
         " tp_touch_tolerance_points=", DoubleToString(InpTpTouchCloseTolerancePoints, 1),
         " tp_touch_timer_ms=", InpTpTouchWatchdogTimerMs,
         " tp_touch_retries=", InpTpTouchCloseRetryCount,
         " daily_profit_target_pct=", DoubleToString(EffectiveDailyProfitTargetPct(), 3),
         " daily_max_loss_pct=", DoubleToString(EffectiveDailyMaxLossPct(), 3),
         " daily_reset_gmt=", InpAccountRiskDayResetHourGmt,
         " leg_lot=", DoubleToString(leg, 8),
         " volume_min=", DoubleToString(minLot, 8),
         " volume_max=", DoubleToString(maxLot, 8),
         " volume_step=", DoubleToString(step, 8));
   Print("NAS SATS operational filters volume_filter=", (g_volumeFilterRuntime ? "ON" : "OFF"),
         " volume_multiplier=", DoubleToString(g_volumeMultiplierRuntime, 4),
         " volume_rule=signal_tick_volume_vs_previous_20_bar_average",
         " max_hold=", (NasTimedExitConfigured() ? g_timedExitTimeRuntime : "OFF"),
         " max_hold_minutes=", NasTimedExitMinutes(),
         " max_hold_mode=elapsed_from_position_open",
         " timed_exit_bridge_plan=", (g_timedExitBridgePlanDirection > 0 ? "BUY" : (g_timedExitBridgePlanDirection < 0 ? "SELL" : "NONE")),
         " timed_exit_bridge_signal=", (g_timedExitBridgePlanSignalTime > 0
            ? TimeToString(g_timedExitBridgePlanSignalTime, TIME_DATE|TIME_SECONDS) : "NONE"));
   Print("NAS SATS account risk enabled=", AccountRiskRuntimeEnabled(),
         " advanced_lot=", InpAdvancedLotEngineEnabled,
         " scoped_magic=", RuntimeMagic(),
         " risk_per_trade_pct=", DoubleToString(InpAccountRiskPerTradePct, 3),
         " atr_exposure_pct=", DoubleToString(InpAccountRiskDailyAtrExposurePct, 3),
         " max_portfolio_pct=", DoubleToString(InpAccountRiskMaxPortfolioPct, 3),
         " daily_loss_limit_pct=", DoubleToString(InpAccountRiskDailyLossLimitPct, 3),
         " max_drawdown_pct=", DoubleToString(InpAccountRiskMaxDrawdownPct, 3),
         " max_margin_usage_pct=", DoubleToString(InpAccountRiskMaxMarginUsagePct, 3),
         " day_reset_hour_gmt=", MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt)),
         " d1_atr_period=", InpAdvancedLotDailyAtrPeriod,
         " max_lot=", DoubleToString(InpAdvancedLotMax, 2));

   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), InpSignalBarMode == NAS_SIGNAL_BAR_LIVE);
   if(copied < 200)
   {
      Print("NAS SATS EA startup probe skipped: insufficient bars copied=", copied);
      return;
   }

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   int scanFrom = LastSignalScanIndex(copied);
   for(int i = scanFrom; i >= 0; i--)
   {
      if(!p[i].buy && !p[i].sell)
         continue;
      int dir = p[i].buy ? 1 : -1;
      double atr = 0.0;
      if(CalculateRisk(rates, copied, i, dir, p[i], g_lastEntry, g_lastSl, g_lastTp1, g_lastTp2, g_lastTp3, atr))
      {
         Print("NAS SATS EA startup last_signal dir=", (dir > 0 ? "BUY" : "SELL"),
               " copied_bars=", copied,
               " mode=", EnumToString(InpSignalBarMode),
               " risk_engine=", EnumToString(InpRiskEngine),
               " label=", NasSignalText(p[i]),
               " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
               " nas_st=", DoubleToString(p[i].superTrend, _Digits),
               " entry=", DoubleToString(g_lastEntry, _Digits),
               " sl=", DoubleToString(g_lastSl, _Digits),
               " tp1=", DoubleToString(g_lastTp1, _Digits),
               " tp2=", DoubleToString(g_lastTp2, _Digits),
               " tp3=", DoubleToString(g_lastTp3, _Digits));
      }
      return;
   }
   Print("NAS SATS EA startup last_signal: none within copied bars=", copied);
}

void BaselineStartupSignal()
{
   if(InpTradeLatestSignalOnAttach)
   {
      Print("NAS SATS EA startup baseline disabled by input; latest closed signal may execute on attach.");
      return;
   }

   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), InpSignalBarMode == NAS_SIGNAL_BAR_LIVE);
   if(copied < 200)
      return;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   int scanFrom = LastSignalScanIndex(copied);
   for(int i = scanFrom; i >= 0; i--)
   {
      if(p[i].buy || p[i].sell)
      {
         g_lastSignalTime = rates[i].time;
         g_lastSignalKeyDirection = p[i].buy ? 1 : -1;
         if(g_lastExecutedDirection == 0)
            g_lastExecutedDirection = g_lastSignalKeyDirection;
         Print("NAS SATS EA startup baseline registered dir=", (p[i].buy ? "BUY" : "SELL"),
               " copied_bars=", copied,
               " mode=", EnumToString(InpSignalBarMode),
               " label=", NasSignalText(p[i]),
               " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
               " no historical execution emitted.");
         return;
      }
   }
}

int LastSignalScanIndex(const int copied)
{
   if(copied <= 0)
      return -1;
   if(InpSignalBarMode == NAS_SIGNAL_BAR_LIVE)
      return copied - 1;
   return copied - 2;
}

string NasSignalText(const NasPoint &p)
{
   if(p.buy)
      return p.sma8 >= p.sma9 ? "Buy" : "Strong Buy";
   if(p.sell)
      return p.sma8 <= p.sma9 ? "Sell" : "Strong Sell";
   return "-";
}

void PrintSignalParityAudit(const MqlRates &rates[],
                            const NasPoint &p[],
                            const int i,
                            const string stage)
{
   if(IsTesterMode())
      return;
   if(!InpSignalParityAudit || i < 1)
      return;
   double prevClose = rates[i - 1].close;
   double prevSt = p[i - 1].superTrend;
   bool crossUp = NAS_Crossover(rates[i].close, p[i].superTrend, prevClose, prevSt);
   bool crossDown = NAS_Crossunder(rates[i].close, p[i].superTrend, prevClose, prevSt);
   Print("NAS_SIGNAL_AUDIT stage=", stage,
         " mode=", EnumToString(InpSignalBarMode),
         " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
         " close=", DoubleToString(rates[i].close, _Digits),
         " prev_close=", DoubleToString(prevClose, _Digits),
         " st=", DoubleToString(p[i].superTrend, _Digits),
         " prev_st=", DoubleToString(prevSt, _Digits),
         " sma13=", DoubleToString(p[i].sma13, _Digits),
         " cross_up=", (crossUp ? "true" : "false"),
         " cross_down=", (crossDown ? "true" : "false"),
         " buy=", (p[i].buy ? "true" : "false"),
         " sell=", (p[i].sell ? "true" : "false"),
         " label=", NasSignalText(p[i]));
}

double SwingAtrAt(const MqlRates &rates[], const int index, const int period)
{
   int len = MathMax(2, period);
   int first = MathMax(0, index - len + 1);
   int count = index - first + 1;
   if(count < 2)
      return 0.0;
   double sum = 0.0;
   for(int i = first; i <= index; i++)
      sum += NAS_TrueRange(rates, i);
   return sum / (double)count;
}

bool FindStructuralSwingStop(const MqlRates &rates[],
                             const int copied,
                             const int signalIndex,
                             const int direction,
                             const double entry,
                             double &swingPrice,
                             double &structuralSl,
                             double &swingAtr,
                             double &prominenceAtr,
                             int &ageBars)
{
   swingPrice = 0.0;
   structuralSl = 0.0;
   swingAtr = 0.0;
   prominenceAtr = 0.0;
   ageBars = -1;
   if(!InpUseStructuralSwingStop || copied <= 0 || signalIndex < 2 || direction == 0)
      return false;

   int left = MathMax(2, InpSwingLeftBars);
   int right = MathMax(1, InpSwingRightBars);
   int newestCandidate = signalIndex - right;
   int oldestCandidate = MathMax(left, signalIndex - MathMax(left + right + 1, InpSwingLookbackBars));
   if(newestCandidate < oldestCandidate)
      return false;

   double minProminence = MathMax(0.0, InpSwingMinProminenceAtr);
   double minDeparture = MathMax(0.0, InpSwingMinDepartureAtr);
   for(int candidate = newestCandidate; candidate >= oldestCandidate; candidate--)
   {
      if(candidate - left < 0 || candidate + right > signalIndex)
         continue;
      double atr = SwingAtrAt(rates, candidate, InpSwingAtrPeriod);
      if(atr <= 0.0)
         continue;

      bool pivot = true;
      bool strictLeft = false;
      bool strictRight = false;
      double leftExtreme = direction > 0 ? -DBL_MAX : DBL_MAX;
      double rightExtreme = direction > 0 ? -DBL_MAX : DBL_MAX;
      double pivotPrice = direction > 0 ? rates[candidate].low : rates[candidate].high;

      for(int k = candidate - left; k < candidate; k++)
      {
         if(direction > 0)
         {
            if(rates[k].low < pivotPrice)
               pivot = false;
            if(rates[k].low > pivotPrice)
               strictLeft = true;
            leftExtreme = MathMax(leftExtreme, rates[k].high);
         }
         else
         {
            if(rates[k].high > pivotPrice)
               pivot = false;
            if(rates[k].high < pivotPrice)
               strictLeft = true;
            leftExtreme = MathMin(leftExtreme, rates[k].low);
         }
      }
      for(int k = candidate + 1; k <= candidate + right; k++)
      {
         if(direction > 0)
         {
            if(rates[k].low < pivotPrice)
               pivot = false;
            if(rates[k].low > pivotPrice)
               strictRight = true;
            rightExtreme = MathMax(rightExtreme, rates[k].high);
         }
         else
         {
            if(rates[k].high > pivotPrice)
               pivot = false;
            if(rates[k].high < pivotPrice)
               strictRight = true;
            rightExtreme = MathMin(rightExtreme, rates[k].low);
         }
      }
      if(!pivot || !strictLeft || !strictRight)
         continue;

      double leftProminence = direction > 0 ? leftExtreme - pivotPrice : pivotPrice - leftExtreme;
      double rightProminence = direction > 0 ? rightExtreme - pivotPrice : pivotPrice - rightExtreme;
      double prominence = MathMin(leftProminence, rightProminence) / atr;
      if(prominence < minProminence)
         continue;

      double postExtreme = direction > 0 ? -DBL_MAX : DBL_MAX;
      for(int k = candidate + 1; k <= signalIndex; k++)
      {
         if(direction > 0)
            postExtreme = MathMax(postExtreme, rates[k].high);
         else
            postExtreme = MathMin(postExtreme, rates[k].low);
      }
      double departure = direction > 0 ? postExtreme - pivotPrice : pivotPrice - postExtreme;
      double closeDeparture = direction > 0 ? rates[signalIndex].close - pivotPrice : pivotPrice - rates[signalIndex].close;
      if(departure < atr * minDeparture || closeDeparture < atr * minDeparture * 0.5)
         continue;

      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double buffer = MathMax(point * 5.0, atr * MathMax(0.0, g_swingBufferAtrRuntime));
      double candidateSl = direction > 0 ? pivotPrice - buffer : pivotPrice + buffer;
      if((direction > 0 && (candidateSl >= entry || pivotPrice >= entry))
         || (direction < 0 && (candidateSl <= entry || pivotPrice <= entry)))
         continue;

      swingPrice = pivotPrice;
      structuralSl = candidateSl;
      swingAtr = atr;
      prominenceAtr = prominence;
      ageBars = signalIndex - candidate;
      return true;
   }
   return false;
}

bool ApplyStructuralSwingStop(const MqlRates &rates[],
                              const int copied,
                              const int signalIndex,
                              const int direction,
                              const double entry,
                              double &sl,
                              double &tp1,
                              double &tp2,
                              double &tp3)
{
   g_lastRiskUsedStructuralStop = false;
   g_lastRiskBaseSl = sl;
   g_lastRiskSwingPrice = 0.0;
   g_lastRiskSwingAtr = 0.0;
   g_lastRiskSwingProminence = 0.0;
   g_lastRiskSwingAgeBars = -1;
   if(!InpUseStructuralSwingStop)
      return false;

   double baseRisk = MathAbs(entry - sl);
   if(baseRisk <= 0.0)
      return false;
   double r1 = MathAbs(tp1 - entry) / baseRisk;
   double r2 = MathAbs(tp2 - entry) / baseRisk;
   double r3 = MathAbs(tp3 - entry) / baseRisk;

   double swingPrice, structuralSl, swingAtr, prominenceAtr;
   int ageBars;
   if(!FindStructuralSwingStop(rates, copied, signalIndex, direction, entry,
                               swingPrice, structuralSl, swingAtr, prominenceAtr, ageBars))
      return false;
   double structuralRisk = MathAbs(entry - structuralSl);
   g_lastRiskSwingPrice = swingPrice;
   g_lastRiskSwingAtr = swingAtr;
   g_lastRiskSwingProminence = prominenceAtr;
   g_lastRiskSwingAgeBars = ageBars;
   if(structuralRisk <= baseRisk + SymbolInfoDouble(_Symbol, SYMBOL_POINT))
      return false;

   sl = structuralSl;
   tp1 = direction > 0 ? entry + structuralRisk * r1 : entry - structuralRisk * r1;
   tp2 = direction > 0 ? entry + structuralRisk * r2 : entry - structuralRisk * r2;
   tp3 = direction > 0 ? entry + structuralRisk * r3 : entry - structuralRisk * r3;
   g_lastRiskUsedStructuralStop = true;
   return true;
}

bool ApplyAdaptiveSlWiden(const int direction,
                          const double entry,
                          double &sl,
                          double &tp1,
                          double &tp2,
                          double &tp3)
{
   g_lastRiskPreWidenSl = sl;
   g_lastRiskWidenPct = 0.0;
   if(!InpAdaptiveSlWidenEnabled || direction == 0)
      return false;
   double rawRisk = MathAbs(entry - sl);
   double farTpDistance = MathMax(MathAbs(tp1 - entry), MathMax(MathAbs(tp2 - entry), MathAbs(tp3 - entry)));
   if(rawRisk <= 0.0 || farTpDistance <= 0.0)
      return false;

   double ratio = rawRisk / farTpDistance;
   double pct = ratio <= 0.20 ? InpSlWidenTightPct : (ratio <= 0.50 ? InpSlWidenNormalPct : InpSlWidenWidePct);
   pct = MathMax(0.0, MathMin(200.0, pct)) / 100.0;
   if(pct <= 0.0)
      return false;
   double widenedRisk = MathMin(farTpDistance, rawRisk * (1.0 + pct));
   if(widenedRisk <= rawRisk)
      return false;

   sl = direction > 0 ? entry - widenedRisk : entry + widenedRisk;
   g_lastRiskWidenPct = pct * 100.0;
   return true;
}

bool ApplyFinalRiskScale(const int direction,
                         const double entry,
                         double &sl,
                         double &tp1,
                         double &tp2,
                         double &tp3)
{
   g_lastRiskFinalScalePct = 100.0;
   if(direction == 0 || entry <= 0.0)
      return false;

   double pct = MathMax(10.0, MathMin(500.0, g_finalRiskScalePctRuntime));
   g_lastRiskFinalScalePct = pct;
   if(MathAbs(pct - 100.0) < 0.0001)
      return false;

   double rawRisk = MathAbs(entry - sl);
   if(rawRisk <= 0.0)
      return false;

   double r1 = MathAbs(tp1 - entry) / rawRisk;
   double r2 = MathAbs(tp2 - entry) / rawRisk;
   double r3 = MathAbs(tp3 - entry) / rawRisk;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = MathMax(point * 20.0, (double)stopLevelPoints * point * 1.5);
   double targetRisk = MathMax(minStop, rawRisk * pct / 100.0);
   if(MathAbs(targetRisk - rawRisk) <= point * 0.5)
      return false;

   sl = direction > 0 ? entry - targetRisk : entry + targetRisk;
   tp1 = direction > 0 ? entry + targetRisk * r1 : entry - targetRisk * r1;
   tp2 = direction > 0 ? entry + targetRisk * r2 : entry - targetRisk * r2;
   tp3 = direction > 0 ? entry + targetRisk * r3 : entry - targetRisk * r3;
   return true;
}

double NasAverageTrueRangeAt(const MqlRates &rates[], const int copied, const int signalIndex, const int period)
{
   int len = MathMax(2, period);
   if(signalIndex <= 0 || copied <= signalIndex)
      return 0.0;
   int start = MathMax(1, signalIndex - len + 1);
   double sum = 0.0;
   int count = 0;
   for(int i = start; i <= signalIndex; i++)
   {
      double hl = rates[i].high - rates[i].low;
      double hc = MathAbs(rates[i].high - rates[i - 1].close);
      double lc = MathAbs(rates[i].low - rates[i - 1].close);
      sum += MathMax(hl, MathMax(hc, lc));
      count++;
   }
   return count > 0 ? sum / (double)count : 0.0;
}

bool ApplyScalpRiskGeometry(const MqlRates &rates[],
                            const int copied,
                            const int signalIndex,
                            const int direction,
                            const double entry,
                            double &sl,
                            double &tp1,
                            double &tp2,
                            double &tp3,
                            double &effAtr)
{
   if(g_riskGeometryModeRuntime != NAS_RISK_GEOMETRY_SCALP || direction == 0 || entry <= 0.0)
      return false;

   double normalRisk = MathAbs(entry - sl);
   double atr = NasAverageTrueRangeAt(rates, copied, signalIndex, InpScalpAtrPeriod);
   if(atr <= 0.0 || normalRisk <= 0.0)
      return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double brokerMinStop = MathMax(point * 10.0, (double)stopLevelPoints * point * 1.2);
   double finalScale = MathMax(10.0, MathMin(500.0, g_finalRiskScalePctRuntime)) / 100.0;
   double atrRisk = atr * MathMax(0.05, InpScalpAtrMultiplier) * finalScale;
   double capRisk = normalRisk * MathMax(1.0, MathMin(100.0, InpScalpMaxOriginalRiskPct)) / 100.0;
   double baseRisk = MathMin(normalRisk, MathMin(atrRisk, capRisk));

   // Anti-micro floor: broker minimum alone can be too tight to be profitable on volatile symbols.
   // Keep scalp tight, but never let it collapse below a meaningful ATR/range fraction.
   double signalRange = MathMax(0.0, rates[signalIndex].high - rates[signalIndex].low);
   double atrFloor = atr * MathMax(0.0, InpScalpMinAtrMultiplier);
   double rangeFloor = signalRange * MathMax(0.0, InpScalpMinSignalRangePct) / 100.0;
   double minScalpRisk = MathMax(brokerMinStop, MathMax(atrFloor, rangeFloor));

   // Dashboard ATR buffer expands/contracts after the scalp base risk is selected.
   // SL% is applied directly to the ATR scalp leg, so it remains effective even when ATR is the tightest component.
   double bufferMult = 1.0 + MathMax(0.0, g_swingBufferAtrRuntime);
   double risk = MathMax(minScalpRisk, MathMin(normalRisk, baseRisk * bufferMult));
   if(risk <= 0.0)
      return false;

   sl = direction > 0 ? entry - risk : entry + risk;
   tp1 = direction > 0 ? entry + risk * 1.0 : entry - risk * 1.0;
   tp2 = direction > 0 ? entry + risk * 2.0 : entry - risk * 2.0;
   tp3 = direction > 0 ? entry + risk * 3.0 : entry - risk * 3.0;
   effAtr = atr;
   return true;
}

double NasPipSize()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;
   if(_Digits == 3 || _Digits == 5)
      return point * 10.0;
   return point;
}

bool ApplyPipRiskGeometry(const int direction,
                          const double entry,
                          double &sl,
                          double &tp1,
                          double &tp2,
                          double &tp3)
{
   if(g_riskGeometryModeRuntime != NAS_RISK_GEOMETRY_PIP || direction == 0 || entry <= 0.0)
      return false;

   double pipDistance = MathMax(0.0, g_pipSlDistanceRuntime);
   if(pipDistance <= 0.0)
      return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;
   long stopLevelPoints = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = MathMax(point * 10.0, (double)stopLevelPoints * point * 1.2);
   double risk = MathMax(minStop, pipDistance * NasPipSize());
   if(risk <= 0.0)
      return false;

   sl = NormalizeDouble(direction > 0 ? entry - risk : entry + risk, _Digits);
   tp1 = NormalizeDouble(direction > 0 ? entry + risk * 1.0 : entry - risk * 1.0, _Digits);
   tp2 = NormalizeDouble(direction > 0 ? entry + risk * 2.0 : entry - risk * 2.0, _Digits);
   tp3 = NormalizeDouble(direction > 0 ? entry + risk * 3.0 : entry - risk * 3.0, _Digits);
   return true;
}

bool ApplySignalOpenRiskGeometry(const int direction,
                                 const double signalBarOpen,
                                 double &entry,
                                 double &sl,
                                 double &tp1,
                                 double &tp2,
                                 double &tp3,
                                 string &detail)
{
   if(g_riskGeometryModeRuntime != NAS_RISK_GEOMETRY_SIGNAL_OPEN || direction == 0 || entry <= 0.0 || signalBarOpen <= 0.0)
      return false;

   double rawRisk = MathAbs(entry - signalBarOpen);
   double minStop = NasExecutionMinStop();
   double risk = MathMax(minStop, rawRisk);
   if(risk <= 0.0)
      return false;

   double oldSl = sl;
   double oldTp1 = tp1;
   sl = NormalizeDouble(direction > 0 ? entry - risk : entry + risk, _Digits);
   risk = MathAbs(entry - sl);
   if(risk <= minStop * 0.25)
      return false;

   tp1 = NormalizeDouble(direction > 0 ? entry + risk * 1.0 : entry - risk * 1.0, _Digits);
   tp2 = NormalizeDouble(direction > 0 ? entry + risk * 2.0 : entry - risk * 2.0, _Digits);
   tp3 = NormalizeDouble(direction > 0 ? entry + risk * 3.0 : entry - risk * 3.0, _Digits);

   string signalOpenDetail = "sigopen_sl entry=" + DoubleToString(entry, _Digits)
                           + " signal_bar_open=" + DoubleToString(signalBarOpen, _Digits)
                           + " raw_risk=" + DoubleToString(rawRisk, _Digits)
                           + " final_risk=" + DoubleToString(risk, _Digits)
                           + " old_sl=" + DoubleToString(oldSl, _Digits)
                           + " old_tp1=" + DoubleToString(oldTp1, _Digits)
                           + " new_sl=" + DoubleToString(sl, _Digits);
   detail = (detail == "" ? signalOpenDetail : detail + "+" + signalOpenDetail);
   return true;
}
string RiskGeometryModeText()
{
   if(g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_SCALP)
      return "SCALP";
   if(g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_PIP)
      return "PIP";
   if(g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_SIGNAL_OPEN)
      return "SIGOPEN";
   return "NORMAL";
}
bool CalculateRisk(const MqlRates &rates[],
                   const int copied,
                   const int signalIndex,
                   const int direction,
                   const NasPoint &signalPoint,
                   double &entry,
                   double &sl,
                   double &tp1,
                   double &tp2,
                   double &tp3,
                   double &effAtr)
{
   if(InpRiskEngine == NAS_RISK_PINE)
   {
      entry = signalPoint.nasEntry;
      sl = signalPoint.nasSl;
      tp1 = signalPoint.nasTp1;
      tp2 = signalPoint.nasTp2;
      tp3 = signalPoint.nasTp3;
      effAtr = 0.0;
      if(!NAS_IsValid(entry) || !NAS_IsValid(sl) || !NAS_IsValid(tp1) || !NAS_IsValid(tp2) || !NAS_IsValid(tp3))
         return false;

      double mult = MathMax(0.1, InpPineRiskDistanceMultiplier);
      if(MathAbs(mult - 1.0) > 1e-9)
      {
         double risk = MathAbs(entry - sl) * mult;
         sl = direction > 0 ? entry - risk : entry + risk;
         tp1 = direction > 0 ? entry + risk * 1.0 : entry - risk * 1.0;
         tp2 = direction > 0 ? entry + risk * 2.0 : entry - risk * 2.0;
         tp3 = direction > 0 ? entry + risk * 3.0 : entry - risk * 3.0;
      }
      ApplyStructuralSwingStop(rates, copied, signalIndex, direction, entry, sl, tp1, tp2, tp3);
      ApplyAdaptiveSlWiden(direction, entry, sl, tp1, tp2, tp3);
      ApplyFinalRiskScale(direction, entry, sl, tp1, tp2, tp3);
      ApplyScalpRiskGeometry(rates, copied, signalIndex, direction, entry, sl, tp1, tp2, tp3, effAtr);
      ApplyPipRiskGeometry(direction, entry, sl, tp1, tp2, tp3);
      return true;
   }

   bool calculated = SATS_CalculateRiskLevelsAtSignal(rates, copied, BuildRiskSettings(), signalIndex, direction,
                                                      entry, sl, tp1, tp2, tp3, effAtr);
   if(!calculated)
      return false;
   ApplyStructuralSwingStop(rates, copied, signalIndex, direction, entry, sl, tp1, tp2, tp3);
   ApplyAdaptiveSlWiden(direction, entry, sl, tp1, tp2, tp3);
   ApplyFinalRiskScale(direction, entry, sl, tp1, tp2, tp3);
   ApplyScalpRiskGeometry(rates, copied, signalIndex, direction, entry, sl, tp1, tp2, tp3, effAtr);
   ApplyPipRiskGeometry(direction, entry, sl, tp1, tp2, tp3);
   return true;
}

bool NasMacroRegimeRejectsAt(const datetime availableTime, string &rule, string &detail, int &bucket)
{
   rule = "";
   detail = "";
   bucket = -1;
   RegimeV3Snapshot state;
   bucket = LiqMacroRegimeBucketAt(availableTime, state);
   if(bucket < 0)
   {
      g_macroRegimeUnclassified++;
      detail = "macro_regime=UNKNOWN fail_open=1";
      return false;
   }
   rule = "MACRO_" + LiqMacroRegimeShortName(bucket);
   detail = "macro_regime=" + LiqMacroRegimeName(bucket)
      + " core=" + state.core
      + " transition=" + state.transitionStatus
      + " age=" + IntegerToString(state.effectiveAge)
      + " h1h2=" + state.h1h2Phase
      + " vol=" + state.volatilityDepth + "/" + state.volatilityImpulse
      + " allowed=" + (LiqMacroRegimeAllowed(bucket) ? "1" : "0");
   return !LiqMacroRegimeAllowed(bucket);
}
bool NasRegimeRejectsAt(const datetime availableTime, string &rule, string &detail)
{
   rule = "";
   detail = "filter_off";
   if(!g_nasRegimeFilterRuntime)
      return false;
   if(!InpRegimeV3Observer)
   {
      detail = "observer_off_fail_open";
      return false;
   }
   if(g_nasRegimeWarmupPending)
   {
      detail = "warmup_pending_fail_open";
      return false;
   }
   // Cheap when D1 is unchanged; essential in tester where OnTimer is intentionally disabled.
   if(!RegimeV3EnsureTimeline(false) && ArraySize(g_regimeV3Timeline) <= 0)
   {
      detail = "timeline_unavailable_fail_open:" + g_regimeV3.detail;
      return false;
   }

   RegimeV3Snapshot state;
   if(!RegimeV3SnapshotAt(availableTime, state))
   {
      detail = "snapshot_unavailable_fail_open";
      return false;
   }

   detail = "core=" + state.core
      + " age=" + state.ageBucket
      + " transition=" + state.transitionStatus
      + " macro=" + state.macroDirection
      + " h1h2=" + state.h1h2Phase
      + " vol=" + state.volatilityDepth;
   if(state.h1h2Phase != "NEUTRAL_ROTATION")
      return false;

   rule = "H1H2_NEUTRAL_ROTATION";
   return true;
}

void NasRegimeScheduleCloseRetry(const datetime signalTime,
                                 const int closeDirection,
                                 const string rule,
                                 const bool bridgeDone,
                                 const bool localDone)
{
   g_nasRegimeCloseRetry.active = !(bridgeDone && localDone);
   g_nasRegimeCloseRetry.signalTime = signalTime;
   g_nasRegimeCloseRetry.closeDirection = closeDirection;
   g_nasRegimeCloseRetry.rule = rule;
   g_nasRegimeCloseRetry.bridgeDone = bridgeDone;
   g_nasRegimeCloseRetry.localDone = localDone;
   g_nasRegimeCloseRetry.nextRetryLocal = TimeLocal() + 2;
   g_nasRegimeCloseRetry.attempts = 0;
}

void NasRegimeRetryPendingClose()
{
   if(!g_nasRegimeCloseRetry.active || TimeLocal() < g_nasRegimeCloseRetry.nextRetryLocal)
      return;

   g_nasRegimeCloseRetry.attempts++;
   if(!g_nasRegimeCloseRetry.bridgeDone)
      g_nasRegimeCloseRetry.bridgeDone = NasProPublishRegimeCloseOnly(
         g_nasRegimeCloseRetry.signalTime, g_nasRegimeCloseRetry.closeDirection, g_nasRegimeCloseRetry.rule);
   if(!g_nasRegimeCloseRetry.localDone)
      g_nasRegimeCloseRetry.localDone = CloseManagedPositionsDirection(g_nasRegimeCloseRetry.closeDirection);

   if(g_nasRegimeCloseRetry.bridgeDone && g_nasRegimeCloseRetry.localDone)
   {
      NasProAuditWrite("regime_filter_close_retry_ok",
         "nas|" + IntegerToString((long)g_nasRegimeCloseRetry.signalTime),
         -g_nasRegimeCloseRetry.closeDirection, 0.0, 0.0, 0.0, 0.0,
         "rule=" + g_nasRegimeCloseRetry.rule + " attempts=" + IntegerToString(g_nasRegimeCloseRetry.attempts));
      g_nasRegimeCloseRetry.active = false;
      return;
   }

   g_nasRegimeCloseRetry.nextRetryLocal = TimeLocal() + MathMin(30, 2 + g_nasRegimeCloseRetry.attempts * 2);
}

void HandleNasRegimeRejectedSignal(const MqlRates &signalBar,
                                   const int direction,
                                   const string label,
                                   const string rule,
                                   const string detail)
{
   bool reverseExitEnabled = InpCloseExistingOnNewSignal;
   int closeDirection = -direction;
   bool bridgeDone = true;
   bool localDone = true;
   if(reverseExitEnabled)
   {
      bridgeDone = NasProPublishRegimeCloseOnly(signalBar.time, closeDirection, rule);
      localDone = CloseManagedPositionsDirection(closeDirection);
      if(!bridgeDone || !localDone)
         NasRegimeScheduleCloseRetry(signalBar.time, closeDirection, rule, bridgeDone, localDone);
   }

   g_nasRegimeRejectedLive++;
   g_nasRegimeLastRule = rule;
   g_nasRegimeLastDetail = detail;
   g_lastSignalTime = signalBar.time;
   g_lastSignalKeyDirection = direction;
   g_lastExecutionStatus = (!bridgeDone || !localDone) ? "FILTER CLOSE RETRY" : "REGIME FILTERED";
   g_lastExecutionBlockReason = "regime_filter:" + rule;
   MarkDirectionProcessedOnBar(signalBar.time, direction);
   if(InpDrawExecutionArrows)
      DrawBlockedSignal(direction, signalBar.time, signalBar.high, signalBar.low, label, "REGIME");
   NasProAuditWrite("regime_filter_entry_rejected",
      "nas|" + IntegerToString((long)signalBar.time), direction, 0.0, 0.0, 0.0, 0.0,
      "rule=" + rule
      + " bridge_close=" + (bridgeDone ? "1" : "0")
      + " local_close=" + (localDone ? "1" : "0")
      + " reverse_exit=" + (reverseExitEnabled ? "1" : "0")
      + " " + detail);
   Print("NAS SATS EA regime filter rejected entry dir=", (direction > 0 ? "BUY" : "SELL"),
      " signal_bar=", TimeToString(signalBar.time, TIME_DATE|TIME_SECONDS),
      " rule=", rule, " bridge_close=", bridgeDone, " local_close=", localDone, " ", detail);
   RequestHistoryRefresh();
   UpdateDashboard();
}

void ProcessSignalBar()
{
   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), InpSignalBarMode == NAS_SIGNAL_BAR_LIVE);
   if(copied < 200)
      return;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);

   int i = LastSignalScanIndex(copied);
   if(i < 1)
      return;
   int direction = p[i].buy ? 1 : (p[i].sell ? -1 : 0);
   if(direction == 0)
   {
      if(g_pendingAccountRiskLockRetry && rates[i].time != g_pendingAccountRiskLockSignalTime)
      {
         Print("NAS SATS EA account risk lock retry expired without execution pending_bar=",
               TimeToString(g_pendingAccountRiskLockSignalTime, TIME_DATE|TIME_SECONDS),
               " latest_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
               " retries=", g_pendingAccountRiskLockRetryCount,
               " action=missed_after_lock_retry");
         ClearAccountRiskLockRetry();
      }
      if(InpAuditNoSignalEvaluations && rates[i].time != g_lastNoSignalAuditBarTime)
      {
         PrintSignalParityAudit(rates, p, i, "no_signal_eval");
         g_lastNoSignalAuditBarTime = rates[i].time;
      }
      return;
   }
   if(g_pendingAccountRiskLockRetry && rates[i].time != g_pendingAccountRiskLockSignalTime)
   {
      Print("NAS SATS EA account risk lock retry superseded pending_bar=",
            TimeToString(g_pendingAccountRiskLockSignalTime, TIME_DATE|TIME_SECONDS),
            " latest_signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " retries=", g_pendingAccountRiskLockRetryCount,
            " action=clear_pending_retry");
      ClearAccountRiskLockRetry();
   }
   PrintSignalParityAudit(rates, p, i, "signal_detected");
   if(rates[i].time == g_lastSignalTime && direction == g_lastSignalKeyDirection)
      return;
   if(WasDirectionProcessedOnBar(rates[i].time, direction))
   {
      Print("NAS SATS EA duplicate live signal ignored dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]));
      RequestHistoryRefresh();
      return;
   }


   int signalDirection = direction;
   if(g_invertTradeModeRuntime)
      direction = -direction;
   if(!g_eaEnabledRuntime)
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "global_ea_kill_switch_off";
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]), "EA OFF");
      RequestHistoryRefresh();
      Print("NAS SATS EA global kill switch blocked signal dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]));
      UpdateDashboard();
      return;
   }

   string dailyGuardReason = "";
   if(!DailyPnlGuardAllowsNewEntry(dailyGuardReason))
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      g_lastExecutionStatus = "DAY LOCK";
      g_lastExecutionBlockReason = dailyGuardReason;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low,
            NasSignalText(p[i]), dailyGuardReason == "daily_profit_target_hit" ? "DAY PROFIT" : "DAY LOSS");
      NasProAuditWrite("daily_pnl_guard_signal_block", "nas|" + IntegerToString((long)rates[i].time), direction,
         0.0, 0.0, 0.0, 0.0,
         "reason=" + dailyGuardReason
         + " instance_pnl=" + DoubleToString(g_dailyGuardPnlMoney, 2)
         + " daily_pnl_pct=" + DoubleToString(g_dailyGuardPnlPct, 3));
      RequestHistoryRefresh();
      UpdateDashboard();
      return;
   }

   bool tradingWindowOpen = IsTradingTimeOpen();
   if(!tradingWindowOpen)
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]), "WINDOW");
      if(g_windowReverseExitRuntime)
      {
         int closeDirection = -direction;
         string closeRule = "window_reverse_exit";
         bool bridgeDone = NasProPublishRegimeCloseOnly(rates[i].time, closeDirection, closeRule);
         bool localDone = CloseManagedPositionsDirection(closeDirection);
         if(!bridgeDone || !localDone)
            NasRegimeScheduleCloseRetry(rates[i].time, closeDirection, closeRule, bridgeDone, localDone);
         NasProAuditWrite("window_reverse_exit", "nas|" + IntegerToString((long)rates[i].time), direction,
            0.0, 0.0, 0.0, 0.0,
            "close_direction=" + (closeDirection > 0 ? "BUY" : "SELL")
            + " bridge_close=" + (bridgeDone ? "1" : "0")
            + " local_close=" + (localDone ? "1" : "0"));
         Print("NAS SATS EA out-of-window reverse exit processed signal_dir=",
                (direction > 0 ? "BUY" : "SELL"),
                " close_dir=", (closeDirection > 0 ? "BUY" : "SELL"),
                " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
                " trading_window=", TradingTimeStateText(),
                " bridge_close=", bridgeDone,
                " local_close=", localDone,
                " retry=", ((!bridgeDone || !localDone) ? "scheduled" : "none"),
                " no_new_entry=true");
      }
      else
      {
         Print("NAS SATS EA signal ignored outside trading window dir=",
               (direction > 0 ? "BUY" : "SELL"),
                " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
                " trading_window=", TradingTimeStateText(),
                " window_reverse_exit=OFF",
                " audit=window_before_same_direction_guard");
      }
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "trading_window_closed";
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      RequestHistoryRefresh();
      return;
   }

   RefreshTradingWindowSessionLock(TimeCurrent(), true);

   if(g_historyUseAcceptedFilterRuntime && direction == g_lastExecutedDirection)
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      Print("NAS SATS EA same-direction signal ignored dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]),
            " reason=already_executed_direction_waiting_for_opposite",
            " duplicate_mode=OFF",
            " input_block_same_direction=", (g_historyUseAcceptedFilterRuntime ? "true" : "false"));
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "same_direction_waiting_for_opposite";
      RequestHistoryRefresh();
      return;
   }

   string volumeReason = "";
   double signalVolume = 0.0;
   double averageVolume = 0.0;
   if(!NasVolumeFilterAllows(rates, i, volumeReason, signalVolume, averageVolume))
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      g_lastExecutionStatus = "VOL FILTERED";
      g_lastExecutionBlockReason = volumeReason;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low,
            NasSignalText(p[i]), "VOL");
      NasProAuditWrite("volume_filter_entry_rejected",
         "nas|" + IntegerToString((long)rates[i].time), direction,
         0.0, 0.0, 0.0, 0.0,
         "reason=" + volumeReason
         + " signal_volume=" + DoubleToString(signalVolume, 0)
         + " average20=" + DoubleToString(averageVolume, 2)
         + " multiplier=" + DoubleToString(g_volumeMultiplierRuntime, 4));
      Print("NAS SATS EA volume filter blocked signal dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " signal_volume=", DoubleToString(signalVolume, 0),
            " average20=", DoubleToString(averageVolume, 2),
            " multiplier=", DoubleToString(g_volumeMultiplierRuntime, 4),
            " reason=", volumeReason);
      RequestHistoryRefresh();
      UpdateDashboard();
      return;
   }

   datetime regimeAvailableTime = (InpSignalBarMode == NAS_SIGNAL_BAR_LIVE)
      ? TimeCurrent()
      : rates[i].time + MathMax(60, PeriodSeconds(_Period));
   string regimeRule = "";
   string regimeDetail = "";
   int macroBucket = -1;
   string macroRule = "";
   string macroDetail = "";
   if(NasMacroRegimeRejectsAt(regimeAvailableTime, macroRule, macroDetail, macroBucket))
   {
      g_nasMacroLastBucket = macroBucket;
      g_nasMacroLastDetail = macroDetail;
      g_macroRegimeRejected++;
      HandleNasRegimeRejectedSignal(rates[i], direction, NasSignalText(p[i]), macroRule, macroDetail);
      return;
   }
   g_nasMacroLastBucket = macroBucket;
   g_nasMacroLastDetail = macroDetail;
   if(g_nasRegimeFilterRuntime && NasRegimeRejectsAt(regimeAvailableTime, regimeRule, regimeDetail))
   {
      HandleNasRegimeRejectedSignal(rates[i], direction, NasSignalText(p[i]), regimeRule, regimeDetail);
      return;
   }
   if(g_nasRegimeFilterRuntime && StringFind(regimeDetail, "fail_open") >= 0)
   {
      g_nasRegimeUnclassifiedLive++;
      g_nasRegimeLastRule = "FAIL_OPEN";
      g_nasRegimeLastDetail = regimeDetail;
   }

   string spreadReason = "";
   if(!IsSpreadExecutionAllowed(spreadReason))
   {
      g_lastSignalTime = rates[i].time;
      g_lastSignalKeyDirection = direction;
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = spreadReason;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawExecutionArrows)
         DrawBlockedSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]), "SPREAD");
      Print("NAS SATS EA spread governor blocked signal dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[i]),
            " reason=", spreadReason);
      RequestHistoryRefresh();
      UpdateDashboard();
      return;
   }

   double effAtr = 0.0;
   if(!CalculateRisk(rates, copied, i, signalDirection, p[i], g_lastEntry, g_lastSl, g_lastTp1, g_lastTp2, g_lastTp3, effAtr))
   {
      Print("NAS SATS EA risk calculation failed signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " direction=", (direction > 0 ? "BUY" : "SELL"));
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "risk_calculation_failed";
      return;
   }

   datetime expectedClose = rates[i].time + PeriodSeconds(_Period);
   int signalDelaySec = (int)(TimeCurrent() - expectedClose);

   g_lastSignalTime = rates[i].time;
   g_lastSignalKeyDirection = direction;
   g_lastDirection = direction;
   string execGeometryDetail = "";
   double signalEntryBeforeExecution = g_lastEntry;
   double marketExecutionEntry = NasMarketExecutionEntry(direction);
   g_lastInvertedFinalTp = 0.0;
   if(g_invertTradeModeRuntime)
   {
      int inverseLeg = EffectiveInversionReferenceLeg();
      double originalSl = g_lastSl;
      double normalSwapEntry = signalEntryBeforeExecution;
      double normalSwapSl = originalSl;
      double originalFinalTp = LocalTargetPriceForR(signalEntryBeforeExecution, originalSl, signalDirection, EffectiveInversionReferenceR());
      string normalSwapDetail = "";
      double normalExecutionEntry = NasMarketExecutionEntry(signalDirection);
      double normalSwapFinalTp = 0.0;
      if(BuildNormalExecutableSwapReference(signalDirection, normalExecutionEntry, signalEntryBeforeExecution, originalSl, EffectiveInversionReferenceR(), normalSwapEntry, normalSwapSl, normalSwapFinalTp, normalSwapDetail))
      {
         originalSl = normalSwapSl;
         originalFinalTp = normalSwapFinalTp;
      }
      if(!BuildInvertedNasGeometry(signalDirection, direction, marketExecutionEntry, normalSwapEntry, originalSl, originalFinalTp, g_lastEntry, g_lastSl, g_lastInvertedFinalTp, execGeometryDetail))
      {
         g_lastExecutionStatus = "BLOCKED";
         g_lastExecutionBlockReason = "invalid_inverted_execution_geometry";
         Print("NAS SATS EA inverted execution geometry invalid signal_dir=", (signalDirection > 0 ? "BUY" : "SELL"),
               " trade_dir=", (direction > 0 ? "BUY" : "SELL"),
               " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
               " signal_entry=", DoubleToString(signalEntryBeforeExecution, _Digits),
               " market_entry=", DoubleToString(marketExecutionEntry, _Digits),
               " original_sl=", DoubleToString(originalSl, _Digits),
               " original_final_tp=", DoubleToString(originalFinalTp, _Digits));
         return;
      }
      g_lastTp1 = g_lastInvertedFinalTp;
      g_lastTp2 = g_lastInvertedFinalTp;
      g_lastTp3 = g_lastInvertedFinalTp;
      g_lastTp4 = g_lastInvertedFinalTp;
      g_lastTp5 = g_lastInvertedFinalTp;
      g_lastTp6 = g_lastInvertedFinalTp;
   }
   else if(!BuildExecutableNasGeometry(direction, marketExecutionEntry, g_lastEntry, g_lastSl, g_lastTp1, g_lastTp2, g_lastTp3, execGeometryDetail))
   {
      g_lastExecutionStatus = "BLOCKED";
      g_lastExecutionBlockReason = "invalid_execution_geometry";
      Print("NAS SATS EA execution geometry invalid dir=", (direction > 0 ? "BUY" : "SELL"),
            " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
            " signal_entry=", DoubleToString(signalEntryBeforeExecution, _Digits),
            " market_entry=", DoubleToString(marketExecutionEntry, _Digits),
            " sl=", DoubleToString(g_lastSl, _Digits));
      return;
   }
   if(!g_invertTradeModeRuntime)
      ApplySignalOpenRiskGeometry(direction, rates[i].open, g_lastEntry, g_lastSl, g_lastTp1, g_lastTp2, g_lastTp3, execGeometryDetail);
   g_lastEntry = NormalizeDouble(g_lastEntry, _Digits);
   g_lastSl = NormalizeDouble(g_lastSl, _Digits);
   g_lastTp1 = NormalizeDouble(g_lastTp1, _Digits);
   g_lastTp2 = NormalizeDouble(g_lastTp2, _Digits);
   g_lastTp3 = NormalizeDouble(g_lastTp3, _Digits);
   if(!g_invertTradeModeRuntime)
   {
      ApplyExecutionModeRisk(direction);
      if(g_tpManagementModeRuntime == NAS_TP_FIXED_SELECTED_LEG && InpExecutionMode != NAS_EXEC_FIXED_1_TO_3R)
         RefreshDerivedTpLadder(direction);
      else
      {
         g_lastTp4 = TpPriceForLeg(direction, 4);
         g_lastTp5 = TpPriceForLeg(direction, 5);
         g_lastTp6 = TpPriceForLeg(direction, 6);
      }
   }
   g_beMoved = false;
   g_lastExecutionStatus = "EXECUTING";
   g_lastExecutionBlockReason = "";

   double bridgeFinalTp = UseSingleOrderTpMode()
      ? (g_invertTradeModeRuntime && g_lastInvertedFinalTp > 0.0
         ? g_lastInvertedFinalTp
         : (InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? g_lastTp3 : CurrentSelectedFinalTp(direction)))
      : g_lastTp3;
   NasProAuditWrite("signal_ready", "nas|" + IntegerToString((long)rates[i].time), direction,
      g_lastEntry, g_lastSl, bridgeFinalTp, 0.0,
      "window=OPEN geometry=" + RiskGeometryModeText() + " pip_sl=" + DoubleToString(g_pipSlDistanceRuntime, 2));
   bool bridgeShapeSupported = !g_nasBridgeEnabledRuntime || UseSingleOrderTpMode();
   bool bridgePublishOk = bridgeShapeSupported && NasProPublishCurrentSignal(rates[i].time, direction);
   bool bridgePublished = g_nasBridgeEnabledRuntime && bridgePublishOk;
   if(bridgePublished)
      RememberNasTimedExitBridgePlan(direction, TimeCurrent());
   g_lastSignalBridgePublished = bridgePublished;
   if(!bridgeShapeSupported)
      NasProAuditWrite("bridge_shape_block", "nas|" + IntegerToString((long)rates[i].time), direction,
         g_lastEntry, g_lastSl, bridgeFinalTp, 0.0, "reason=unsupported_legacy_multi_order native_may_continue=1");
   if(g_nasBridgeOnlyRuntime && !g_nasNativeWithBridgeOnlyRuntime)
   {
      if(!bridgeShapeSupported)
      {
         g_lastSignalTime = rates[i].time;
         g_lastSignalKeyDirection = direction;
         g_lastExecutionStatus = "BLOCKED";
         g_lastExecutionBlockReason = "bridge_requires_single_order_mode";
         MarkDirectionProcessedOnBar(rates[i].time, direction);
         RequestHistoryRefresh();
         return;
      }
      if(!bridgePublishOk)
      {
         g_lastExecutionStatus = "BLOCKED";
         g_lastExecutionBlockReason = "bridge_only_publish_failed";
         g_lastSignalTime = 0;
         g_lastSignalKeyDirection = 0;
         NasProAuditWrite("bridge_only_failed", "nas|" + IntegerToString((long)rates[i].time), direction,
            g_lastEntry, g_lastSl, bridgeFinalTp, 0.0, "event_not_claimed_retry_allowed=1");
         return;
      }
      g_lastExecutedDirection = direction;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpDrawExecutionArrows)
         DrawExecutionSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]));
      RequestHistoryRefresh();
      g_lastExecutionStatus = "BRIDGE ONLY";
      g_lastExecutionBlockReason = "";
      NasProAuditWrite("bridge_published_only", "nas|" + IntegerToString((long)rates[i].time), direction,
         g_lastEntry, g_lastSl, bridgeFinalTp, 0.0, "native_open=0");
      return;
   }
   if(g_nasBridgeEnabledRuntime && !bridgePublished)
      NasProAuditWrite("bridge_publish_failed_native_continue", "nas|" + IntegerToString((long)rates[i].time), direction,
         g_lastEntry, g_lastSl, bridgeFinalTp, 0.0, "native_open=1");

   if(InpCloseExistingOnNewSignal)
      CloseManagedPositions();

   Print("NAS SATS EA executing signal dir=", (direction > 0 ? "BUY" : "SELL"),
         " copied_bars=", copied,
         " mode=", EnumToString(InpSignalBarMode),
         " execution_mode=", EnumToString(InpExecutionMode),
         " risk_engine=", EnumToString(InpRiskEngine),
         " label=", NasSignalText(p[i]),
         " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
         " expected_close=", TimeToString(expectedClose, TIME_DATE|TIME_SECONDS),
         " delay_sec=", signalDelaySec,
         " nas_st=", DoubleToString(p[i].superTrend, _Digits),
         " signal_entry=", DoubleToString(signalEntryBeforeExecution, _Digits),
         " execution_entry=", DoubleToString(g_lastEntry, _Digits),
         " execution_geometry=", execGeometryDetail,
         " sats_eff_atr=", DoubleToString(effAtr, _Digits),
         " base_sl=", DoubleToString(g_lastRiskBaseSl, _Digits),
         " structural_stop_used=", (g_lastRiskUsedStructuralStop ? "true" : "false"),
         " swing_price=", DoubleToString(g_lastRiskSwingPrice, _Digits),
         " swing_age_bars=", g_lastRiskSwingAgeBars,
         " swing_atr=", DoubleToString(g_lastRiskSwingAtr, _Digits),
         " swing_prominence_atr=", DoubleToString(g_lastRiskSwingProminence, 2),
         " pre_widen_sl=", DoubleToString(g_lastRiskPreWidenSl, _Digits),
         " sl_widen_pct=", DoubleToString(g_lastRiskWidenPct, 1),
         " sl=", DoubleToString(g_lastSl, _Digits),
         " tp1=", DoubleToString(g_lastTp1, _Digits),
         " tp2=", DoubleToString(g_lastTp2, _Digits),
         " tp3=", DoubleToString(g_lastTp3, _Digits));

   bool opened = OpenThreeLegs(direction);
   if(opened)
   {
      ClearAccountRiskLockRetry();
      g_lastExecutedDirection = direction;
      MarkDirectionProcessedOnBar(rates[i].time, direction);
      if(InpSignalBarMode == NAS_SIGNAL_BAR_LIVE)
      {
         g_liveSignalBarTime = rates[i].time;
         g_liveSignalDirection = direction;
      }
      int planLeg = g_invertTradeModeRuntime ? EffectiveInversionReferenceLeg()
         : (InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? 6 : LegacyLegForTargetR(SelectedTargetR()));
      double planTp = UseSingleOrderTpMode() ? bridgeFinalTp : g_lastTp3;
      double planHalf = UseSingleOrderTpMode() ? NasProBridgeHalfTrigger(direction, planLeg, planTp) : 0.0;
      NasProRegisterUntrackedPositions(rates[i].time, direction, g_lastEntry, g_lastSl, planTp, planHalf);
      NasProAuditWrite("order_opened", "nas|" + IntegerToString((long)rates[i].time), direction,
         g_lastEntry, g_lastSl, planTp, g_lastAdvancedLot, "bridge_published=" + (bridgePublished ? "1" : "0"));
      if(InpDrawTradeLevels)
         DrawTradeLevels(direction);
      if(InpDrawExecutionArrows)
         DrawExecutionSignal(direction, rates[i].time, rates[i].high, rates[i].low, NasSignalText(p[i]));
      RequestHistoryRefresh();
      g_lastExecutionStatus = "OPENED";
      g_lastExecutionBlockReason = "";
   }
   else
   {
      g_lastExecutionStatus = "BLOCKED";
      if(g_lastExecutionBlockReason == "")
         g_lastExecutionBlockReason = "broker_order_open_failed";
      NasProAuditWrite("order_failed", "nas|" + IntegerToString((long)rates[i].time), direction,
         g_lastEntry, g_lastSl, bridgeFinalTp, g_lastAdvancedLot, g_lastExecutionBlockReason);
      if(StringFind(g_lastExecutionBlockReason, "lock_busy") >= 0)
      {
         g_lastSignalTime = 0;
         g_lastSignalKeyDirection = 0;
         ArmAccountRiskLockRetry(rates[i].time, direction);
         Print("NAS SATS EA signal deferred for account risk lock retry dir=",
               (direction > 0 ? "BUY" : "SELL"),
               " signal_bar=", TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
               " retry_count=", g_pendingAccountRiskLockRetryCount,
               " next_retry_ms=250");
      }
      else
      {
         ClearAccountRiskLockRetry();
         RequestHistoryRefresh();
      }
   }
}

void ReconcileLiveSignalAfterBarClose()
{
   if(!InpReconcileLiveSignalsOnBarClose || g_liveSignalBarTime <= 0 || g_liveSignalDirection == 0)
      return;

   MqlRates rates[];
   int copied = LoadNasRates(rates, SignalBarsToCopy(), false);
   if(copied < 200)
      return;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);

   int closedIndex = -1;
   int scanStop = copied - 6;
   if(scanStop < 0)
      scanStop = 0;
   for(int i = copied - 2; i >= scanStop; i--)
   {
      if(rates[i].time == g_liveSignalBarTime)
      {
         closedIndex = i;
         break;
      }
   }

   if(closedIndex < 0)
   {
      Print("NAS SATS EA live reconcile skipped: signal bar not found bar=",
            TimeToString(g_liveSignalBarTime, TIME_DATE|TIME_SECONDS),
            " dir=", (g_liveSignalDirection > 0 ? "BUY" : "SELL"));
      return;
   }

   int confirmedDirection = p[closedIndex].buy ? 1 : (p[closedIndex].sell ? -1 : 0);
   if(g_invertTradeModeRuntime && confirmedDirection != 0)
      confirmedDirection = -confirmedDirection;
   PrintSignalParityAudit(rates, p, closedIndex, "live_reconcile_closed_bar");
   if(confirmedDirection == g_liveSignalDirection)
   {
      Print("NAS SATS EA live signal confirmed on bar close dir=",
            (g_liveSignalDirection > 0 ? "BUY" : "SELL"),
            " bar=", TimeToString(g_liveSignalBarTime, TIME_DATE|TIME_SECONDS),
            " label=", NasSignalText(p[closedIndex]));
      g_liveSignalBarTime = 0;
      g_liveSignalDirection = 0;
      return;
   }

   Print("NAS SATS EA live signal vanished on bar close dir=",
         (g_liveSignalDirection > 0 ? "BUY" : "SELL"),
         " bar=", TimeToString(g_liveSignalBarTime, TIME_DATE|TIME_SECONDS),
         " confirmed=", (confirmedDirection > 0 ? "BUY" : (confirmedDirection < 0 ? "SELL" : "NONE")),
         " action=cleanup",
         " close_position=", (InpCloseVanishedLiveSignalPosition ? "true" : "false"));

   if(InpCloseVanishedLiveSignalPosition && ManagedPositionDirection() == g_liveSignalDirection)
      CloseManagedPositions();

   ClearLiveSignalObjects(g_liveSignalBarTime, g_liveSignalDirection);
   if(ManagedPositionDirection() == 0)
   {
      ClearTradeLevelObjects();
      // Do not clear g_lastExecutedDirection here. Same-direction re-entry
      // must stay blocked until an opposite NAS signal is actually accepted.
   }
   if(g_lastSignalTime == g_liveSignalBarTime && g_lastSignalKeyDirection == g_liveSignalDirection)
   {
      g_lastSignalTime = 0;
      g_lastSignalKeyDirection = 0;
   }

   g_liveSignalBarTime = 0;
   g_liveSignalDirection = 0;
   UpdateDashboard();
   ChartRedraw(0);
}

bool HasTradeLevelObjects()
{
   return ObjectFind(0, PREFIX + "ENTRY") >= 0
          || ObjectFind(0, PREFIX + "ENTRY_SEG") >= 0
          || ObjectFind(0, PREFIX + "SL") >= 0
          || ObjectFind(0, PREFIX + "TP_SELECTED") >= 0
          || ObjectFind(0, PREFIX + "TP1") >= 0
          || ObjectFind(0, PREFIX + "HCBE") >= 0;
}
void ReconcileClosedManagedPositionVisuals()
{
   if(IsTesterMode())
      return;
   if(ManagedPositionDirection() != 0)
      return;
   bool liveObjectsPresent = g_liveLevelObjectsActive || HasTradeLevelObjects();
   if(!liveObjectsPresent && g_lastDirection == 0 && g_lastSignalTime == 0 && g_lastSignalKeyDirection == 0)
      return;

   if(liveObjectsPresent)
      ClearTradeLevelObjects();

   bool stateChanged = (g_lastDirection != 0 || g_lastSignalTime != 0 || g_lastSignalKeyDirection != 0 || g_beMoved);
   g_lastDirection = 0;
   g_lastSignalTime = 0;
   g_lastSignalKeyDirection = 0;
   g_beMoved = false;
   g_lastInvertedFinalTp = 0.0;

   if(stateChanged)
   {
      RequestHistoryRefresh();
      UpdateDashboard();
      ChartRedraw(0);
   }
}

double NasExitR(const int direction, const double entry, const double sl, const double exitPrice)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0 || direction == 0)
      return 0.0;
   return direction > 0 ? (exitPrice - entry) / risk : (entry - exitPrice) / risk;
}
double NasTargetR(const int direction, const double entry, const double sl, const double targetPrice)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0 || direction == 0 || targetPrice <= 0.0)
      return 0.0;
   double reward = direction > 0 ? targetPrice - entry : entry - targetPrice;
   return reward / risk;
}

string NasRiskRewardText(const double targetR)
{
   if(targetR <= 0.0)
      return "RR invalid";
   if(targetR >= 1.0)
      return "reward:risk " + DoubleToString(targetR, 2) + ":1";
   return "risk:reward " + DoubleToString(1.0 / targetR, 2) + ":1";
}
double NasExecutionMinStop()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(point * 10.0, (double)MathMax(stops, freeze) * point * 1.2);
}

double NasMarketExecutionEntry(const int direction)
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
   {
      if(direction > 0 && tick.ask > 0.0)
         return NormalizeDouble(tick.ask, _Digits);
      if(direction < 0 && tick.bid > 0.0)
         return NormalizeDouble(tick.bid, _Digits);
   }
   return NormalizeDouble(direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
}

bool BuildExecutableNasGeometry(const int direction,
                                const double executionEntry,
                                double &entry,
                                double &sl,
                                double &tp1,
                                double &tp2,
                                double &tp3,
                                string &detail)
{
   detail = "";
   if(direction == 0 || executionEntry <= 0.0 || sl <= 0.0)
      return false;

   double signalEntry = entry;
   double originalSl = sl;
   double minStop = NasExecutionMinStop();
   double scaledRisk = MathAbs(signalEntry - originalSl);
   if(scaledRisk <= 0.0)
      return false;

   entry = NormalizeDouble(executionEntry, _Digits);

   // Preserve the already-selected SL%/ATR/scalp risk distance, but anchor it
   // around the actual executable entry. This keeps dashboard SL% meaningful
   // after signal-entry -> execution-entry rebasing.
   double risk = MathMax(minStop, scaledRisk);
   sl = NormalizeDouble(direction > 0 ? entry - risk : entry + risk, _Digits);
   risk = MathAbs(entry - sl);
   if(risk <= minStop * 0.25)
      return false;

   tp1 = NormalizeDouble(direction > 0 ? entry + risk * 1.0 : entry - risk * 1.0, _Digits);
   tp2 = NormalizeDouble(direction > 0 ? entry + risk * 2.0 : entry - risk * 2.0, _Digits);
   tp3 = NormalizeDouble(direction > 0 ? entry + risk * 3.0 : entry - risk * 3.0, _Digits);

   if(MathAbs(signalEntry - entry) > MathMax(_Point * 2.0, risk * 0.02))
      detail = "rebased_to_execution_entry";
   if(MathAbs(originalSl - sl) > MathMax(_Point * 2.0, risk * 0.02))
      detail = (detail == "" ? "sl_reanchored_to_execution_entry" : detail + "+sl_reanchored_to_execution_entry");
   if(detail != "")
      detail += " signal_entry=" + DoubleToString(signalEntry, _Digits)
             + " exec_entry=" + DoubleToString(entry, _Digits)
             + " original_sl=" + DoubleToString(originalSl, _Digits)
             + " final_sl=" + DoubleToString(sl, _Digits)
             + " preserved_risk=" + DoubleToString(scaledRisk, _Digits);
   return true;
}


bool BuildNormalExecutableSwapReference(const int signalDirection,
                                        const double normalExecutionEntry,
                                        const double rawEntry,
                                        const double rawSl,
                                        const double finalTargetR,
                                        double &normalEntry,
                                        double &normalSl,
                                        double &normalFinalTp,
                                        string &detail)
{
   normalEntry = rawEntry;
   normalSl = rawSl;
   normalFinalTp = 0.0;
   double normalTp1 = 0.0;
   double normalTp2 = 0.0;
   double normalTp3 = 0.0;
   detail = "";
   if(!BuildExecutableNasGeometry(signalDirection, normalExecutionEntry, normalEntry, normalSl, normalTp1, normalTp2, normalTp3, detail))
      return false;
   normalFinalTp = LocalTargetPriceForR(normalEntry, normalSl, signalDirection, finalTargetR);
   return normalFinalTp > 0.0;
}
bool ResolveHistoricalExecutionEntry(const MqlRates &rates[],
                                     const int signalIndex,
                                     const int lastIndex,
                                     const int direction,
                                     double &executionEntry,
                                     string &source)
{
   executionEntry = 0.0;
   source = "none";
   if(signalIndex < 0 || signalIndex >= ArraySize(rates) || direction == 0)
      return false;

   // Closed-bar production execution starts on the next bar. MT5 bars are Bid bars,
   // therefore BUY entries must include the recorded spread while SELL entries use Bid.
   if(signalIndex + 1 <= lastIndex && signalIndex + 1 < ArraySize(rates))
   {
      int executionIndex = signalIndex + 1;
      double spread = MathMax(0.0, (double)rates[executionIndex].spread) * _Point;
      executionEntry = NormalizeDouble(rates[executionIndex].open + (direction > 0 ? spread : 0.0), _Digits);
      source = direction > 0 ? "next_bar_ask_open" : "next_bar_bid_open";
      return executionEntry > 0.0;
   }

   double fallbackSpread = MathMax(0.0, (double)rates[signalIndex].spread) * _Point;
   executionEntry = NormalizeDouble(rates[signalIndex].close + (direction > 0 ? fallbackSpread : 0.0), _Digits);
   source = direction > 0 ? "signal_ask_close_fallback" : "signal_bid_close_fallback";
   return executionEntry > 0.0;
}

int NasResolveSameBar(const MqlRates &bar, const int direction, const double openRef, const double tp, const double sl)
{
   bool tpHit = direction > 0 ? bar.high >= tp : bar.low <= tp;
   bool slHit = direction > 0 ? bar.low <= sl : bar.high >= sl;
   if(tpHit && !slHit) return 1;
   if(slHit && !tpHit) return -1;
   if(!tpHit && !slHit) return 0;

   // Match the production-proven Liq Narrative/ORB coarse-bar policy.
   // When both levels are touched and no lower-TF ordering exists, the level
   // nearest to the bar open is assumed first. This is deterministic and does
   // not introduce the systematic loss bias of a candle-colour path guess.
   double distTp = MathAbs(tp - openRef);
   double distSl = MathAbs(openRef - sl);
   return distTp < distSl ? 1 : -1;
}


int NasM1GuardResolveBefore(const datetime fromTime,
                            const datetime toTime,
                            const int direction,
                            const double entry,
                            const double tp,
                            const double sl)
{
   if(toTime <= fromTime || direction == 0 || tp <= 0.0 || sl <= 0.0)
      return 0;

   MqlRates m1[];
   int copied = CopyRates(_Symbol, PERIOD_M1, fromTime, toTime, m1);
   if(copied <= 0)
      return 0;
   if(m1[0].time > m1[copied - 1].time)
      ArrayReverse(m1, 0, WHOLE_ARRAY);

   for(int i = 0; i < copied; i++)
   {
      if(m1[i].time < fromTime || m1[i].time > toTime)
         continue;
      int res = NasResolveSameBar(m1[i], direction, (i == 0 ? entry : m1[i].open), tp, sl);
      if(res != 0)
         return res;
   }
   return 0;
}

bool SimulateHistoricalSignalByTicks(const MqlRates &rates[],
                                     const NasPoint &p[],
                                     const int &closeSignal[],
                                     const bool useTicks,
                                     const int signalIndex,
                                     const int direction,
                                     const int lastIndex,
                                     const double entry,
                                     const double sl,
                                     const double finalTp,
                                     const double hcPrice,
                                     const int finalLeg,
                                     int &maxTp,
                                     string &outcome,
                                     double &pnlR,
                                     bool &closed,
                                     bool &won)
{
   maxTp = 0;
   pnlR = 0.0;
   closed = false;
   won = false;
   outcome = "open";
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0 || direction == 0 || finalTp <= 0.0 || sl <= 0.0)
   {
      outcome = "invalid geometry";
      return false;
   }

   int periodSec = MathMax(60, PeriodSeconds(_Period));
   int executionIndex = signalIndex + 1;
   if(executionIndex > lastIndex || executionIndex >= ArraySize(rates))
      return false;
   // The next existing bar is the executable bar. Using signal time + period
   // is wrong across weekends and exchange session gaps.
   datetime startTime = rates[executionIndex].time;
   datetime endTime = rates[MathMin(lastIndex, ArraySize(rates) - 1)].time + periodSec;
   datetime reverseTime = 0;
   int closeEventDirection = 0;
   for(int j = signalIndex + 1; j <= lastIndex && j < ArraySize(rates); j++)
   {
      if(p[j].buy || p[j].sell)
      {
         if(j >= ArraySize(closeSignal) || closeSignal[j] <= 0)
            continue;
         int reverseSignalDirection = p[j].buy ? 1 : -1;
         int reverseTradeDirection = g_invertTradeModeRuntime ? -reverseSignalDirection : reverseSignalDirection;
         if(closeSignal[j] == 1 && reverseTradeDirection == direction)
            continue;
         closeEventDirection = reverseTradeDirection;
         reverseTime = (j + 1 <= lastIndex && j + 1 < ArraySize(rates))
            ? rates[j + 1].time
            : rates[j].time + periodSec;
         endTime = reverseTime;
         break;
      }
   }
   bool timedExitBoundary = false;
   datetime timedExitTime = NasTimedExitDeadlineForEntry(startTime);
   if(timedExitTime > 0 && timedExitTime <= endTime)
   {
      endTime = MathMax(startTime, timedExitTime);
      timedExitBoundary = true;
   }
   if(endTime <= startTime)
      return false;

   double finalTargetR = NasTargetR(direction, entry, sl, finalTp);
   bool halfEnabled = (hcPrice > 0.0 && (g_invertTradeModeRuntime
      || (g_hcBeTpLegRuntime > 0 && RMultipleForLeg(g_hcBeTpLegRuntime) < finalTargetR - 0.0001)));
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL && hcPrice > 0.0)
      halfEnabled = true;
   bool halfCloseEnabled = halfEnabled && InpExecutionMode != NAS_EXEC_PARTIAL_BE_ORIGINAL;
   bool halfDone = false;
   double activeSl = sl;
   double halfR = halfEnabled ? NasTargetR(direction, entry, sl, hcPrice) : 0.0;

   MqlTick ticks[];
   datetime replayEndTime = MathMin(endTime, TimeCurrent());
   ulong tickEndMs = (ulong)replayEndTime * 1000;
   if(reverseTime > 0 || timedExitBoundary)
      tickEndMs += 60000; // Include the first executable quote at/after the replacement boundary.
   int copied = useTicks
      ? CopyTicksRange(_Symbol, ticks, COPY_TICKS_ALL, (ulong)startTime * 1000, tickEndMs)
      : 0;
   bool anyTick = false;
   int firstValidTick = -1;
   int lastValidTick = -1;
   for(int k = 0; k < copied; ++k)
   {
      if(ticks[k].bid <= 0.0 || ticks[k].ask <= 0.0)
         continue;
      if(firstValidTick < 0)
         firstValidTick = k;
      lastValidTick = k;
   }
   bool tickCoverageComplete = firstValidTick >= 0 && lastValidTick >= firstValidTick;
   if(tickCoverageComplete)
   {
      ulong firstMs = ticks[firstValidTick].time_msc > 0 ? (ulong)ticks[firstValidTick].time_msc : (ulong)ticks[firstValidTick].time * 1000;
      ulong lastMs = ticks[lastValidTick].time_msc > 0 ? (ulong)ticks[lastValidTick].time_msc : (ulong)ticks[lastValidTick].time * 1000;
      bool endCovered = (reverseTime > 0 || timedExitBoundary)
         ? lastMs >= (ulong)reverseTime * 1000
         : lastMs + 60000 >= (ulong)replayEndTime * 1000;
      if(timedExitBoundary)
         endCovered = lastMs >= (ulong)endTime * 1000;
      tickCoverageComplete = firstMs <= (ulong)(startTime + 60) * 1000 && endCovered;
   }
   if(copied > 0 && tickCoverageComplete)
   {
      for(int k = 0; k < copied; k++)
      {
         if(ticks[k].bid <= 0.0 || ticks[k].ask <= 0.0)
            continue;
         anyTick = true;
         double closePx = direction > 0 ? ticks[k].bid : ticks[k].ask;
         ulong tickMs = ticks[k].time_msc > 0 ? (ulong)ticks[k].time_msc : (ulong)ticks[k].time * 1000;

         if((reverseTime > 0 || timedExitBoundary) && tickMs >= (ulong)endTime * 1000)
         {
            double exitR = NasExitR(direction, entry, sl, closePx);
            pnlR += (halfDone && halfCloseEnabled) ? exitR * 0.5 : exitR;
            outcome = timedExitBoundary
               ? "TIME_EXIT tick"
               : (closeEventDirection == direction ? "replace tick" : "reverse tick");
            closed = true;
            won = pnlR > 0.0;
            return true;
         }

         if(halfEnabled && !halfDone)
         {
            bool halfHit = direction > 0 ? closePx >= hcPrice : closePx <= hcPrice;
            if(halfHit)
            {
               if(halfCloseEnabled)
                  pnlR += halfR * 0.5;
               activeSl = entry;
               halfDone = true;
            }
         }

         for(int leg = 1; leg <= 6; leg++)
         {
            double legPx = LocalTpPriceForLeg(entry, sl, direction, leg);
            if(legPx <= 0.0)
               continue;
            bool legHit = direction > 0 ? closePx >= legPx : closePx <= legPx;
            if(legHit)
               maxTp = MathMax(maxTp, leg);
         }

         bool finalHit = direction > 0 ? closePx >= finalTp : closePx <= finalTp;
         if(finalHit)
         {
            double finalR = finalTargetR;
            pnlR += (halfDone && halfCloseEnabled) ? finalR * 0.5 : finalR;
            outcome = "TP " + TargetRText(finalR) + " tick";
            maxTp = MathMax(maxTp, finalLeg);
            closed = true;
            won = pnlR > 0.0;
            return true;
         }

         bool slHit = direction > 0 ? closePx <= activeSl : closePx >= activeSl;
         if(slHit)
         {
            if(halfDone)
            {
               outcome = "BE after HC tick";
               closed = true;
               won = pnlR > 0.0;
               return true;
            }
            pnlR = -1.0;
            outcome = "SL tick";
            closed = true;
            won = false;
            return true;
         }
      }
      if(anyTick)
      {
         double openPx = direction > 0 ? ticks[lastValidTick].bid : ticks[lastValidTick].ask;
         double liveR = NasExitR(direction, entry, sl, openPx);
         pnlR += (halfDone && halfCloseEnabled) ? liveR * 0.5 : liveR;
         outcome = "open " + (pnlR >= 0.0 ? "+" : "") + DoubleToString(pnlR, 2) + "R tick";
         won = pnlR > 0.0;
         return true;
      }
   }

   MqlRates m1[];
   datetime m1RequestEnd = (reverseTime > 0 || timedExitBoundary) ? endTime + 300 : replayEndTime;
   int m1Copied = CopyRates(_Symbol, PERIOD_M1, startTime, m1RequestEnd, m1);
   if(m1Copied > 0)
   {
      if(m1[0].time > m1[m1Copied - 1].time)
         ArrayReverse(m1, 0, WHOLE_ARRAY);

      bool m1StartCovered = m1[0].time <= startTime + 60;
      if(!m1StartCovered)
         return false;

      for(int i = 0; i < m1Copied; i++)
      {
      if(m1[i].time < startTime)
         continue;
      if((reverseTime > 0 || timedExitBoundary) && m1[i].time >= endTime)
      {
         double reverseSpread = MathMax(0.0, (double)m1[i].spread) * _Point;
         double exitPx = m1[i].open + (direction < 0 ? reverseSpread : 0.0);
         double exitR = NasExitR(direction, entry, sl, exitPx);
         pnlR += (halfDone && halfCloseEnabled) ? exitR * 0.5 : exitR;
         outcome = timedExitBoundary
            ? "TIME_EXIT m1"
            : (closeEventDirection == direction ? "replace m1" : "reverse m1");
         closed = true;
         won = pnlR > 0.0;
         return true;
      }

      if(halfEnabled && !halfDone)
      {
         bool halfHit = direction > 0 ? m1[i].high >= hcPrice : m1[i].low <= hcPrice;
         if(halfHit)
         {
            bool currentSlHit = direction > 0 ? m1[i].low <= activeSl : m1[i].high >= activeSl;
            if(currentSlHit && NasResolveSameBar(m1[i], direction, m1[i].open, hcPrice, activeSl) < 0)
            {
               pnlR = -1.0;
               outcome = "SL before HC m1";
               closed = true;
               won = false;
               return true;
            }
            if(halfCloseEnabled)
               pnlR += halfR * 0.5;
            activeSl = entry;
            halfDone = true;
         }
      }

      for(int leg = 1; leg <= 6; leg++)
      {
         double legPx = LocalTpPriceForLeg(entry, sl, direction, leg);
         if(legPx <= 0.0)
            continue;
         bool legHit = direction > 0 ? m1[i].high >= legPx : m1[i].low <= legPx;
         if(legHit)
            maxTp = MathMax(maxTp, leg);
      }

      int res = NasResolveSameBar(m1[i], direction, (i == 0 ? entry : m1[i].open), finalTp, activeSl);
      if(res > 0)
      {
         double finalR = finalTargetR;
         pnlR += (halfDone && halfCloseEnabled) ? finalR * 0.5 : finalR;
         outcome = "TP " + TargetRText(finalR) + " m1";
         maxTp = MathMax(maxTp, finalLeg);
         closed = true;
         won = pnlR > 0.0;
         return true;
      }
      if(res < 0)
      {
         if(halfDone)
         {
            outcome = "BE after HC m1";
            closed = true;
            won = pnlR > 0.0;
            return true;
         }
         pnlR = -1.0;
         outcome = "SL m1";
         closed = true;
         won = false;
         return true;
      }
      }

      if(reverseTime > 0 || timedExitBoundary)
         return false;

      int lastM1 = m1Copied - 1;
      if(m1[lastM1].time + 60 < replayEndTime)
         return false;
      double openSpread = MathMax(0.0, (double)m1[lastM1].spread) * _Point;
      double openPx = m1[lastM1].close + (direction < 0 ? openSpread : 0.0);
      double liveR = NasExitR(direction, entry, sl, openPx);
      pnlR += (halfDone && halfCloseEnabled) ? liveR * 0.5 : liveR;
      outcome = "open " + (pnlR >= 0.0 ? "+" : "") + DoubleToString(pnlR, 2) + "R m1";
      won = pnlR > 0.0;
      return true;
   }

   return false;
}
bool NasOutcomeHitTarget(const string outcome)
{
   return StringFind(outcome, "TP ") == 0;
}

bool NasOutcomeHitStop(const string outcome)
{
   return StringFind(outcome, "SL") >= 0;
}

bool NasOutcomeHitBreakeven(const string outcome)
{
   return StringFind(outcome, "BE after HC") >= 0;
}

color NasOutcomeColor(const double pnlR, const bool closed, const string outcome)
{
   if(NasOutcomeHitTarget(outcome))
      return C'80,255,180';
   if(NasOutcomeHitStop(outcome))
      return C'255,80,110';
   if(NasOutcomeHitBreakeven(outcome))
      return C'184,196,210';
   // O means neither the configured TP nor the original SL was hit. Its
   // floating/exit PnL must not promote it to W or demote it to L.
   if(!closed || StringFind(outcome, "open") >= 0 || StringFind(outcome, "reverse") >= 0 || StringFind(outcome, "replace") >= 0)
      return C'255,204,82';
   return C'184,196,210';
}

bool SimulateHistoricalSignal(const MqlRates &rates[],
                              const NasPoint &p[],
                              const int &closeSignal[],
                              const int signalIndex,
                              const int direction,
                              const int lastIndex,
                              const double entry,
                              const double sl,
                              const double finalTp,
                              const double hcPrice,
                              const int finalLeg,
                              int &maxTp,
                              string &outcome,
                              double &pnlR,
                              bool &closed,
                              bool &won)
{
   maxTp = 0;
   pnlR = 0.0;
   closed = false;
   won = false;
   outcome = "open";

   double risk = MathAbs(entry - sl);
   if(risk <= 0.0 || direction == 0 || finalTp <= 0.0 || sl <= 0.0)
   {
      outcome = "invalid geometry";
      return false;
   }

   double finalTargetR = NasTargetR(direction, entry, sl, finalTp);
   bool halfEnabled = (hcPrice > 0.0 && (g_invertTradeModeRuntime
      || (g_hcBeTpLegRuntime > 0 && RMultipleForLeg(g_hcBeTpLegRuntime) < finalTargetR - 0.0001)));
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL && hcPrice > 0.0)
      halfEnabled = true;
   bool halfCloseEnabled = halfEnabled && InpExecutionMode != NAS_EXEC_PARTIAL_BE_ORIGINAL;
   bool halfDone = false;
   double activeSl = sl;
   double halfR = halfEnabled ? NasTargetR(direction, entry, sl, hcPrice) : 0.0;
   int end = MathMin(lastIndex, ArraySize(rates) - 1);
   int executionIndex = signalIndex + 1;
   datetime timedExitDeadline = executionIndex <= end
      ? NasTimedExitDeadlineForEntry(rates[executionIndex].time)
      : 0;

   for(int j = signalIndex + 1; j <= end; j++)
   {
      if(timedExitDeadline > 0 && rates[j].time >= timedExitDeadline)
      {
         double timedExitSpread = MathMax(0.0, (double)rates[j].spread) * _Point;
         double timedExitPrice = rates[j].open + (direction < 0 ? timedExitSpread : 0.0);
         double exitR = NasExitR(direction, entry, sl, timedExitPrice);
         pnlR += (halfDone && halfCloseEnabled) ? exitR * 0.5 : exitR;
         outcome = "TIME_EXIT bar";
         closed = true;
         won = pnlR > 0.0;
         return true;
      }
      bool closeAtNextOpen = false;
      int closeEventDirection = 0;
      if(p[j].buy || p[j].sell)
      {
         if(j < ArraySize(closeSignal) && closeSignal[j] > 0)
         {
            int reverseSignalDirection = p[j].buy ? 1 : -1;
            int reverseTradeDirection = g_invertTradeModeRuntime ? -reverseSignalDirection : reverseSignalDirection;
            if(closeSignal[j] == 2 || reverseTradeDirection != direction)
            {
               closeAtNextOpen = true;
               closeEventDirection = reverseTradeDirection;
            }
         }
      }

      bool halfHit = halfEnabled && !halfDone && (direction > 0 ? rates[j].high >= hcPrice : rates[j].low <= hcPrice);
      bool finalHit = direction > 0 ? rates[j].high >= finalTp : rates[j].low <= finalTp;
      bool slHit = direction > 0 ? rates[j].low <= activeSl : rates[j].high >= activeSl;

      for(int leg = 1; leg <= 6; leg++)
      {
         double legPx = LocalTpPriceForLeg(entry, sl, direction, leg);
         if(legPx <= 0.0)
            continue;
         bool legHit = direction > 0 ? rates[j].high >= legPx : rates[j].low <= legPx;
         if(legHit)
            maxTp = MathMax(maxTp, leg);
      }

      if(halfHit)
      {
         if(slHit && NasResolveSameBar(rates[j], direction, rates[j].open, hcPrice, activeSl) < 0)
         {
            pnlR = -1.0;
            outcome = "SL before HC bar";
            closed = true;
            won = false;
            return true;
         }
         if(halfCloseEnabled)
            pnlR += halfR * 0.5;
         activeSl = entry;
         halfDone = true;
         slHit = direction > 0 ? rates[j].low <= activeSl : rates[j].high >= activeSl;
      }

      int finalVsSl = NasResolveSameBar(rates[j], direction, rates[j].open, finalTp, activeSl);
      if(finalHit && finalVsSl > 0)
      {
         double finalR = finalTargetR;
         pnlR += (halfDone && halfCloseEnabled) ? finalR * 0.5 : finalR;
         outcome = "TP " + TargetRText(finalR);
         maxTp = MathMax(maxTp, finalLeg);
         closed = true;
         won = (pnlR > 0.0);
         return true;
      }

      if(slHit && finalVsSl < 0)
      {
         if(halfDone)
         {
            outcome = "BE after HC";
            closed = true;
            won = (pnlR > 0.0);
            return true;
         }
         pnlR = -1.0;
         outcome = "SL";
         closed = true;
         won = false;
         return true;
      }

      // A CLOSED-mode signal is only available after this bar completes. Price
      // movement inside the signal bar must therefore be evaluated before the
      // managed position is replaced at the next executable quote.
      if(closeAtNextOpen)
      {
         double exitPx = 0.0;
         string exitSource = "";
         if(!ResolveHistoricalExecutionEntry(rates, j, end, -direction, exitPx, exitSource))
         {
            double closeSpread = MathMax(0.0, (double)rates[j].spread) * _Point;
            exitPx = rates[j].close + (direction < 0 ? closeSpread : 0.0);
         }
         double exitR = NasExitR(direction, entry, sl, exitPx);
         pnlR += (halfDone && halfCloseEnabled) ? exitR * 0.5 : exitR;
         outcome = (closeEventDirection == direction ? "replace " : "reverse ") + (p[j].buy ? "BUY" : "SELL");
         closed = true;
         won = (pnlR > 0.0);
         return true;
      }
   }

   if(end > signalIndex)
   {
      double liveR = NasExitR(direction, entry, sl, rates[end].close);
      pnlR += (halfDone && halfCloseEnabled) ? liveR * 0.5 : liveR;
      outcome = "open " + (pnlR >= 0.0 ? "+" : "") + DoubleToString(pnlR, 2) + "R";
   }
   won = (pnlR > 0.0);
   return true;
}
void SetNasHistoryAuditProgress(const string stage, const double pct)
{
   g_historyAuditRunning = pct < 100.0;
   g_historyAuditProgressPct = MathMax(0.0, MathMin(100.0, pct));
   g_historyAuditSummary = NasAuditWindowLabel() + " Audit | " + stage + " " + DoubleToString(g_historyAuditProgressPct, 1) + "%";
   g_historyAuditRows[0] = g_historyAuditSummary;
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
   ChartRedraw(0);
}

void BlockNasHistoryAudit(const string reason)
{
   g_historyAuditRunning = false;
   g_historyCoverageBlocked = true;
   g_historyAuditProgressPct = 0.0;
   g_historyCoverageDetail = reason;
   g_historyAuditSummary = NasAuditWindowLabel() + " HISTORY BLOCKED";
   g_historyAuditDetail = reason;
   g_historyAuditRows[0] = g_historyAuditSummary;
   g_historyAuditRows[1] = reason;
   Print("NAS SATS EA history audit blocked reason=", reason);
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
   ChartRedraw(0);
}

void DrawRecentSignalHistory()
{
   if(IsTesterMode())
      return;
   ObjectsDeleteAll(0, PREFIX + "HIST_");
   g_historyCoverageBlocked = false;
   g_historyCoverageDetail = "";
   SetNasHistoryAuditProgress("PREPARE", 1.0);

   if(InpSignalBarMode != NAS_SIGNAL_BAR_CLOSED)
   {
      BlockNasHistoryAudit("LIVE signal timing cannot be causally reconstructed; use CLOSED mode for audit");
      return;
   }
   bool legacyThreeLeg = !g_invertTradeModeRuntime
      && InpExecutionMode != NAS_EXEC_FIXED_1_TO_3R
      && g_tpManagementModeRuntime == NAS_TP_LEGACY_THREE_LEG;
   if(legacyThreeLeg)
   {
      BlockNasHistoryAudit("LEGACY 3LEG portfolio exits are not represented by single-order R audit; use FIXED TP");
      return;
   }

   int periodSec = MathMax(60, PeriodSeconds(_Period));
   int windowSeconds = MathMax(2, g_auditWeeksRuntime) * 7 * 86400;
   int neededBars = (int)MathCeil((double)windowSeconds / (double)periodSec) + 300;
   int barsToCopy = MathMax(MathMax(InpHistoryBars, 300), neededBars);
   datetime cutoff = TimeCurrent() - windowSeconds;

   MqlRates rates[];
   int copied = LoadNasRates(rates, barsToCopy, false);
   if(copied < 200)
   {
      g_historyAuditRunning = false;
      g_historyCoverageBlocked = true;
      g_historyAuditProgressPct = 0.0;
      g_historyCoverageDetail = "insufficient bars copied=" + IntegerToString(copied) + " need>=200";
      g_historyAuditSummary = NasAuditWindowLabel() + " HISTORY BLOCKED";
      g_historyAuditDetail = g_historyCoverageDetail;
      g_historyAuditRows[0] = g_historyAuditSummary;
      g_historyAuditRows[1] = g_historyCoverageDetail;
      Print("NAS SATS EA history overlay skipped: insufficient bars copied=", copied);
      g_dashboardForceNextUpdate = true;
      UpdateDashboard();
      ChartRedraw(0);
      return;
   }

   datetime requiredOldest = cutoff - periodSec * 300;
   if(rates[0].time > requiredOldest + periodSec * 2)
   {
      g_historyAuditRunning = false;
      g_historyCoverageBlocked = true;
      g_historyCoverageDetail = "need " + TimeToString(requiredOldest, TIME_DATE)
         + " got " + TimeToString(rates[0].time, TIME_DATE)
         + " | increase Tools>Options>Charts Max bars and reload history";
      g_historyAuditSummary = NasAuditWindowLabel() + " HISTORY BLOCKED";
      g_historyAuditDetail = g_historyCoverageDetail;
      g_historyAuditRows[0] = g_historyAuditSummary;
      g_historyAuditRows[1] = g_historyCoverageDetail;
      Print("NAS SATS EA history coverage blocked window=", NasAuditWindowLabel(),
            " requested_bars=", barsToCopy, " copied=", copied, " ", g_historyCoverageDetail);
      g_dashboardForceNextUpdate = true;
      UpdateDashboard();
      ChartRedraw(0);
      return;
   }
   SetNasHistoryAuditProgress("SIGNALS", 18.0);

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   SetNasHistoryAuditProgress("CLASSIFY", 32.0);

   bool acceptedSignal[];
   bool candidateSignal[];
   int closeSignal[];
   int macroBucketByIndex[];
   ArrayResize(acceptedSignal, copied);
   ArrayResize(candidateSignal, copied);
   ArrayResize(closeSignal, copied);
   ArrayResize(macroBucketByIndex, copied);
   ArrayInitialize(acceptedSignal, false);
   ArrayInitialize(candidateSignal, false);
   ArrayInitialize(closeSignal, 0);
   ArrayInitialize(macroBucketByIndex, -1);
   int historicalExecutedDirection = 0;

   datetime historicalWindowSessionKey = 0;
   int rawSignals = 0;
   int windowSkipped = 0;
   int sameDirectionSkipped = 0;
   int regimeSkipped = 0;
   int macroRegimeSkipped = 0;
   int regimeUnclassified = 0;
   int spreadSkipped = 0;
   int spreadUnknown = 0;
   int volumeSkipped = 0;
   int acceptedTotal = 0;
   RegimeV3EnsureTimeline(false);
   for(int ai = 0; ai <= copied - 2; ai++)
   {
      if(ai > 0 && ai % MathMax(1, copied / 8) == 0)
         SetNasHistoryAuditProgress("CLASSIFY", 32.0 + 16.0 * (double)ai / (double)MathMax(1, copied - 1));
      if(!p[ai].buy && !p[ai].sell)
         continue;
      bool inAuditWindow = (rates[ai].time >= cutoff);
      if(inAuditWindow)
         rawSignals++;
      int adir = p[ai].buy ? 1 : -1;
      // Match CLOSED-mode execution/filter timing to the next existing market
      // bar rather than a theoretical timestamp inside a session/weekend gap.
      datetime signalAvailableTime = rates[ai + 1].time;
      if(!IsTradingTimeOpenAt(signalAvailableTime))
      {
         if(g_windowReverseExitRuntime)
            closeSignal[ai] = 1; // Outside the window, production closes reverse direction only.
         if(inAuditWindow)
            windowSkipped++;
         continue;
      }
      datetime signalWindowSessionKey = TradingWindowSessionKeyAt(signalAvailableTime);
      if(signalWindowSessionKey != historicalWindowSessionKey)
      {
         historicalWindowSessionKey = signalWindowSessionKey;
         historicalExecutedDirection = 0;
      }
      if(g_historyUseAcceptedFilterRuntime && adir == historicalExecutedDirection)
      {
         if(inAuditWindow)
            sameDirectionSkipped++;
         continue;
      }

      candidateSignal[ai] = true;
      string historicalVolumeReason = "";
      double historicalSignalVolume = 0.0;
      double historicalAverageVolume = 0.0;
      if(!NasVolumeFilterAllows(rates, ai, historicalVolumeReason,
                                historicalSignalVolume, historicalAverageVolume))
      {
         if(inAuditWindow)
            volumeSkipped++;
         continue;
      }
      int executionIndex = ai + 1;
      if(InpSpreadGovernorEnabled && g_spreadMaxPointsRuntime > 0.0 && executionIndex < copied)
      {
         double historicalSpreadPoints = MathMax(0.0, (double)rates[executionIndex].spread);
         if(historicalSpreadPoints <= 0.0)
         {
            if(inAuditWindow) spreadUnknown++;
         }
         else if(historicalSpreadPoints > g_spreadMaxPointsRuntime)
         {
            if(inAuditWindow) spreadSkipped++;
            continue;
         }
      }
      RegimeV3Snapshot macroSnapshot;
      int macroBucket = LiqMacroRegimeBucketAt(signalAvailableTime, macroSnapshot);
      macroBucketByIndex[ai] = macroBucket;
      if(macroBucket < 0)
      {
         if(inAuditWindow) regimeUnclassified++;
      }
      else if(!LiqMacroRegimeAllowed(macroBucket))
      {
         if(InpCloseExistingOnNewSignal)
            closeSignal[ai] = 1; // Rejected regime signals only invalidate an opposite live position.
         if(inAuditWindow) macroRegimeSkipped++;
         continue;
      }

      string regimeRule = "";
      string regimeDetail = "";
      datetime regimeAvailableTime = signalAvailableTime;
      if(g_nasRegimeFilterRuntime && NasRegimeRejectsAt(regimeAvailableTime, regimeRule, regimeDetail))
      {
         if(InpCloseExistingOnNewSignal)
            closeSignal[ai] = 1;
         if(inAuditWindow)
            regimeSkipped++;
         continue;
      }
      if(g_nasRegimeFilterRuntime && StringFind(regimeDetail, "fail_open") >= 0 && inAuditWindow)
         regimeUnclassified++;

      acceptedSignal[ai] = true;
      if(InpCloseExistingOnNewSignal)
         closeSignal[ai] = 2; // Accepted entries replace any existing managed direction before opening.
      if(g_historyUseAcceptedFilterRuntime)
         historicalExecutedDirection = adir;
      if(inAuditWindow)
         acceptedTotal++;
   }
   for(int h = 0; h < 3; h++)
      g_historySummary[h] = "-";
   for(int r = 0; r < 7; r++)
      g_historyAuditRows[r] = "-";
   for(int mr = 0; mr < LIQ_MACRO_REGIME_COUNT; ++mr)
   {
      g_macroRegimeWins[mr] = 0;
      g_macroRegimeLosses[mr] = 0;
   }
   ResetNasWeekdayAuditStats();

   int drawn = 0;
   int windowDrawn = 0;
   int wins = 0;
   int losses = 0;
   int breakevens = 0;
   int openCount = 0;
   int otherWins = 0;
   int otherLosses = 0;
   int otherFlats = 0;
   int stillOpen = 0;
   double totalR = 0.0;
   double openFloatingR = 0.0;
   double otherClosedR = 0.0;
   double otherWonR = 0.0;
   double otherLostR = 0.0;
   double wonR = 0.0;
   double lostR = 0.0;
   double closedPnlNewestFirst[];
   ArrayResize(closedPnlNewestFirst, 0);
   int maxDraw = 250;
   int liveManagedDirection = ManagedPositionDirection();
   int progressCheckpoint = 0;
   for(int i = copied - 2; i >= 0; i--)
   {
      int processedPct = (int)MathFloor(100.0 * (double)(copied - 2 - i) / (double)MathMax(1, copied - 1));
      if(processedPct >= progressCheckpoint + 5)
      {
         progressCheckpoint = processedPct;
         SetNasHistoryAuditProgress("SIMULATE", 50.0 + 48.0 * (double)processedPct / 100.0);
      }
      if(rates[i].time < cutoff)
         break;
      if(!p[i].buy && !p[i].sell)
         continue;
      datetime signalAvailableTime = rates[i + 1].time;
      int signalDirection = p[i].buy ? 1 : -1;
      int direction = g_invertTradeModeRuntime ? -signalDirection : signalDirection;
      if(!IsTradingTimeOpenAt(signalAvailableTime))
      {
         if(windowDrawn < maxDraw)
            DrawHistoricalWindowSignal(direction, rates[i].time, rates[i].high, rates[i].low);
         windowDrawn++;
         continue;
      }
      if(i >= ArraySize(candidateSignal) || !candidateSignal[i])
         continue;
      bool executionAccepted = (i < ArraySize(acceptedSignal) && acceptedSignal[i]);
      if((liveManagedDirection != 0 || g_liveLevelObjectsActive) && g_lastSignalTime > 0 && rates[i].time == g_lastSignalTime)
      {
         bool sameLiveSignal = (g_invertTradeModeRuntime ? (-signalDirection == g_lastDirection) : (signalDirection == g_lastDirection));
         if(sameLiveSignal)
            continue; // Avoid double drawing current live signal: live level objects own that signal until cleanup.
      }
      double entry, sl, tp1, tp2, tp3, atr;
      if(!CalculateRisk(rates, copied, i, signalDirection, p[i], entry, sl, tp1, tp2, tp3, atr))
         continue;

      int finalLeg = g_invertTradeModeRuntime ? EffectiveInversionReferenceLeg() : EffectiveAuditTpLeg();
      double signalEntry = entry;
      double originalSl = sl;
      double originalFinalTp = LocalTargetPriceForR(signalEntry, originalSl, signalDirection, EffectiveInversionReferenceR());
      double normalSwapEntryHist = signalEntry;
      double normalSwapSlHist = originalSl;
      double normalSwapFinalTpHist = originalFinalTp;
      string normalSwapDetailHist = "";
      double executionEntry = 0.0;
      string executionSource = "";
      string geometryDetail = "";
      double finalTp = 0.0;
      if(g_invertTradeModeRuntime)
      {
         double normalExecutionEntryHist = 0.0;
         string normalExecutionSourceHist = "";
         if(ResolveHistoricalExecutionEntry(rates, i, copied - 2, signalDirection, normalExecutionEntryHist, normalExecutionSourceHist))
         {
            if(BuildNormalExecutableSwapReference(signalDirection, normalExecutionEntryHist, signalEntry, originalSl, EffectiveInversionReferenceR(), normalSwapEntryHist, normalSwapSlHist, normalSwapFinalTpHist, normalSwapDetailHist))
            {
               originalSl = normalSwapSlHist;
               originalFinalTp = normalSwapFinalTpHist;
            }
         }
      }

      if(ResolveHistoricalExecutionEntry(rates, i, copied - 2, direction, executionEntry, executionSource))
      {
         if(g_invertTradeModeRuntime)
         {
            if(!BuildInvertedNasGeometry(signalDirection, direction, executionEntry, normalSwapEntryHist, originalSl, originalFinalTp, entry, sl, finalTp, geometryDetail))
               continue;
            tp1 = tp2 = tp3 = finalTp;
         }
         else
         {
            if(!BuildExecutableNasGeometry(direction, executionEntry, entry, sl, tp1, tp2, tp3, geometryDetail))
               continue;
            ApplySignalOpenRiskGeometry(direction, rates[i].open, entry, sl, tp1, tp2, tp3, geometryDetail);
            finalTp = LocalTargetPriceForR(entry, sl, direction, EffectiveAuditNormalTargetR());
         }
      }
      else
      {
         if(g_invertTradeModeRuntime)
         {
            if(!BuildInvertedNasGeometry(signalDirection, direction, signalEntry, normalSwapEntryHist, originalSl, originalFinalTp, entry, sl, finalTp, geometryDetail))
               continue;
            tp1 = tp2 = tp3 = finalTp;
         }
         else
            finalTp = LocalTargetPriceForR(entry, sl, direction, EffectiveAuditNormalTargetR());
      }

      double hcPrice = HistoricalHcBePrice(entry, sl, direction, finalTp, finalLeg);

      string outcome = "";
      int maxTp = 0;
      double pnlR = 0.0;
      bool closed = false;
      bool won = false;
      datetime cacheEndTime = rates[MathMin(copied - 2, ArraySize(rates) - 1)].time;
      bool useTickReplay = g_auditWeeksRuntime <= 20;
       string simKey = NasHistorySimKey(rates[i].time, direction, entry, sl, finalTp, hcPrice, finalLeg, cacheEndTime)
          + "|fill=" + (useTickReplay ? "tick_m1_bar" : "m1_bar")
          + "|max_hold=" + (NasTimedExitConfigured() ? g_timedExitTimeRuntime : "OFF");
      if(!NasHistorySimCacheGet(simKey, maxTp, outcome, pnlR, closed, won))
      {
         bool simulated = SimulateHistoricalSignalByTicks(rates, p, closeSignal, useTickReplay, i, direction, copied - 2, entry, sl, finalTp, hcPrice, finalLeg, maxTp, outcome, pnlR, closed, won);
         if(!simulated)
         {
            // Long-window history frequently has no complete tick/M1 archive.
            // Fall back to the already loaded entry/chart timeframe exactly as
            // the Liq Narrative and ORB audit engines do for multi-year runs.
            if(!SimulateHistoricalSignal(rates, p, closeSignal, i, direction, copied - 2, entry, sl, finalTp, hcPrice, finalLeg, maxTp, outcome, pnlR, closed, won))
               continue;
            outcome += " bar";
         }
         NasHistorySimCachePut(simKey, maxTp, outcome, pnlR, closed, won);
      }

      int signalMacroBucket = i < ArraySize(macroBucketByIndex) ? macroBucketByIndex[i] : -1;
       if(signalMacroBucket >= 0 && signalMacroBucket < LIQ_MACRO_REGIME_COUNT)
       {
          if(NasOutcomeHitTarget(outcome)) g_macroRegimeWins[signalMacroBucket]++;
          else if(NasOutcomeHitStop(outcome)) g_macroRegimeLosses[signalMacroBucket]++;
       }
      if(!executionAccepted)
         continue;

       if(closed)
       {
          int closedPnlCount = ArraySize(closedPnlNewestFirst);
          ArrayResize(closedPnlNewestFirst, closedPnlCount + 1);
          closedPnlNewestFirst[closedPnlCount] = pnlR;
       }

       MqlDateTime executionDay;
       ZeroMemory(executionDay);
       TimeToStruct(signalAvailableTime, executionDay);

       if(NasOutcomeHitTarget(outcome))
       {
          wins++;
          wonR += pnlR;
          totalR += pnlR;
          if(executionDay.day_of_week >= 1 && executionDay.day_of_week <= 5)
             g_nasWeekdayWins[executionDay.day_of_week]++;
       }
       else if(NasOutcomeHitStop(outcome))
       {
          losses++;
          lostR += MathAbs(pnlR);
          totalR += pnlR;
          if(executionDay.day_of_week >= 1 && executionDay.day_of_week <= 5)
             g_nasWeekdayLosses[executionDay.day_of_week]++;
       }
       else if(NasOutcomeHitBreakeven(outcome))
       {
          breakevens++;
          totalR += pnlR;
       }
       else
       {
          openCount++;
          if(closed)
          {
             otherClosedR += pnlR;
             totalR += pnlR;
             if(pnlR > 0.00000001)
             {
                otherWins++;
                otherWonR += pnlR;
             }
             else if(pnlR < -0.00000001)
             {
                otherLosses++;
                otherLostR += MathAbs(pnlR);
             }
             else
                otherFlats++;
          }
          else
          {
             stillOpen++;
             openFloatingR += pnlR;
          }
       }

      if(drawn < maxDraw)
         DrawHistoricalSignal(drawn + 1, direction, rates[i].time, rates[i].high, rates[i].low, entry, sl, finalTp, hcPrice, finalLeg, maxTp, outcome, pnlR, closed);
      if(drawn < 4)
      {
         if(drawn < 3)
            g_historySummary[drawn] = "#" + IntegerToString(drawn + 1) + " " + (direction > 0 ? "BUY " : "SELL ")
                                     + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES)
                                     + " PnL " + (pnlR >= 0.0 ? "+" : "") + DoubleToString(pnlR, 2) + "R"
                                     + " max=" + (maxTp > 0 ? "TP" + IntegerToString(maxTp) : "none")
                                     + " " + outcome;
         g_historyAuditRows[drawn + 2] = "#" + IntegerToString(drawn + 1) + " " + (direction > 0 ? "BUY " : "SELL ")
                                    + (pnlR >= 0.0 ? "+" : "") + DoubleToString(pnlR, 2) + "R"
                                    + " | SigE " + DoubleToString(signalEntry, _Digits)
                                    + " | ExecE " + DoubleToString(entry, _Digits)
                                    + " | SL " + DoubleToString(sl, _Digits)
                                    + (g_invertTradeModeRuntime ? (" | " + EffectiveInvertTargetText() + " REF " + TargetRText(EffectiveInversionReferenceR()) + " " + DoubleToString(finalTp, _Digits))
                                                                : (" | TP " + TargetRText(NasTargetR(direction, entry, sl, finalTp)) + " " + DoubleToString(finalTp, _Digits)))
                                    + (hcPrice > 0.0 ? " | HC " + DoubleToString(hcPrice, _Digits) : "")
                                    + " | " + outcome;
      }
      if(InpSignalParityAudit)
      {
         Print("NAS SATS EA history signal#", drawn + 1,
               " window_weeks=", g_auditWeeksRuntime,
               " dir=", (direction > 0 ? "BUY" : "SELL"),
               " label=", NasSignalText(p[i]),
               " risk_engine=", EnumToString(InpRiskEngine),
               " bar=", TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
               " nas_st=", DoubleToString(p[i].superTrend, _Digits),
               " signal_entry=", DoubleToString(signalEntry, _Digits),
               " execution_entry=", DoubleToString(entry, _Digits),
               " execution_source=", executionSource,
               " execution_geometry=", geometryDetail,
               " sl=", DoubleToString(sl, _Digits),
               " final_tp=", DoubleToString(finalTp, _Digits),
               " hc=", DoubleToString(hcPrice, _Digits),
               " max_tp=", maxTp,
               " pnl_r=", DoubleToString(pnlR, 2),
               " outcome=", outcome);
      }
      drawn++;
   }

   double wr = (wins + losses) > 0 ? (double)wins * 100.0 / (double)(wins + losses) : 0.0;
   double profitFactor = lostR > 0.0 ? wonR / lostR : (wonR > 0.0 ? 99.0 : 0.0);
   int closedCount = wins + losses + breakevens + otherWins + otherLosses + otherFlats;
   double avgR = closedCount > 0 ? totalR / (double)closedCount : 0.0;
   double cumulativeClosedR = 0.0;
   double minCumulativeClosedR = 0.0;
   for(int curveIndex = ArraySize(closedPnlNewestFirst) - 1; curveIndex >= 0; --curveIndex)
   {
      cumulativeClosedR += closedPnlNewestFirst[curveIndex];
      if(cumulativeClosedR < minCumulativeClosedR)
         minCumulativeClosedR = cumulativeClosedR;
   }
   bool auditMoneyAvailable = AccountRiskRuntimeEnabled()
      && AccountRiskInitialBalance() > 0.0
      && g_accountRiskPerTradePctRuntime > 0.0;
   double minCumulativeClosedMoney = auditMoneyAvailable
      ? minCumulativeClosedR * AccountRiskInitialBalance() * g_accountRiskPerTradePctRuntime / 100.0
      : 0.0;
   g_historyAuditSummary = NasAuditWindowLabel() + " | Net R "
                           + (totalR >= 0.0 ? "+" : "") + DoubleToString(totalR, 2) + "R | "
                           + IntegerToString(drawn) + " sig | W " + IntegerToString(wins)
                            + " L " + IntegerToString(losses)
                            + " B " + IntegerToString(breakevens)
                            + " O " + IntegerToString(openCount)
                            + " [OW " + IntegerToString(otherWins)
                            + " OL " + IntegerToString(otherLosses)
                            + " OF " + IntegerToString(otherFlats)
                            + " OPEN " + IntegerToString(stillOpen) + "]"
                            + " | WR " + DoubleToString(wr, 1) + "%";
   int auditTpLeg = EffectiveAuditTpLeg();
   double auditLegR = g_invertTradeModeRuntime ? EffectiveInversionReferenceR() : EffectiveAuditNormalTargetR();
   double auditTargetR = g_invertTradeModeRuntime ? (InvertTargetOverrideEnabled() ? g_invertTargetRRuntime : 0.0) : auditLegR;
   string auditTpDescriptor = g_invertTradeModeRuntime ? (EffectiveInversionReferenceText() + " | " + EffectiveInvertTargetText()
                                                       + (InvertTargetOverrideEnabled() ? (" " + NasRiskRewardText(auditTargetR)) : " normal_SL_as_TP"))
                                                       : ("TP " + TargetRText(auditTargetR) + " " + NasRiskRewardText(auditTargetR));
   g_historyAuditDetail = auditTpDescriptor
                          + " | HCBE " + EffectiveHcBeText()
                          + " | VOL " + string(g_volumeFilterRuntime ? "ON x" + DoubleToString(g_volumeMultiplierRuntime, 2) : "OFF")
                          + " | HOLD " + (NasTimedExitConfigured() ? g_timedExitTimeRuntime : "OFF")
                          + " | ATRbuf " + DoubleToString(g_swingBufferAtrRuntime * 100.0, 0) + "%"
                          + " | SL% " + DoubleToString(g_finalRiskScalePctRuntime, 0)
                          + " | PipSL " + DoubleToString(g_pipSlDistanceRuntime, 1);

   g_historyAuditRows[0] = g_historyAuditSummary;
   g_historyAuditRows[1] = "Combo | " + g_historyAuditDetail + " | Mode " + TpModeText();
   g_historyAuditRows[2] = "SL/TP Geometry | " + RiskGeometryModeText() + " | ScalpATR " + IntegerToString(InpScalpAtrPeriod)
                           + " x" + DoubleToString(InpScalpAtrMultiplier, 2)
                           + " | floor ATRx" + DoubleToString(InpScalpMinAtrMultiplier, 2)
                           + " range" + DoubleToString(InpScalpMinSignalRangePct, 0) + "%"
                           + " | cap " + DoubleToString(InpScalpMaxOriginalRiskPct, 0) + "%";
   g_historyAuditRows[3] = "R totals | Net R " + (totalR >= 0.0 ? "+" : "") + DoubleToString(totalR, 2)
                             + "R | Won R +" + DoubleToString(wonR, 2) + "R | Lost R -" + DoubleToString(lostR, 2)
                             + "R | O-closed R " + (otherClosedR >= 0.0 ? "+" : "") + DoubleToString(otherClosedR, 2)
                             + "R (OW +" + DoubleToString(otherWonR, 2) + " / OL -" + DoubleToString(otherLostR, 2) + ")"
                             + " | O-open R " + (openFloatingR >= 0.0 ? "+" : "") + DoubleToString(openFloatingR, 2) + "R";
   g_historyAuditRows[4] = "Target stats | W " + IntegerToString(wins) + " / L " + IntegerToString(losses)
                             + " / B " + IntegerToString(breakevens) + " / O " + IntegerToString(openCount)
                             + " [OW " + IntegerToString(otherWins) + " OL " + IntegerToString(otherLosses)
                             + " OF " + IntegerToString(otherFlats) + " OPEN " + IntegerToString(stillOpen) + "] | WR " + DoubleToString(wr, 1)
                           + "% | PF " + DoubleToString(profitFactor, 2) + " | Avg R " + DoubleToString(avgR, 3) + "R/trade";
   g_historyAuditRows[5] = string(g_historyUseAcceptedFilterRuntime ? "DUP OFF | " : "DUP ON | ")
                           + "Regime " + string(g_nasRegimeFilterRuntime ? "ON" : "OFF")
                           + " | accepted " + IntegerToString(acceptedTotal) + "/" + IntegerToString(rawSignals)
                           + " | win " + IntegerToString(windowSkipped)
                           + " dup " + IntegerToString(sameDirectionSkipped)
                           + " vol " + IntegerToString(volumeSkipped)
                           + " macro " + IntegerToString(macroRegimeSkipped)
                           + " v3 " + IntegerToString(regimeSkipped)
                           + " spr " + IntegerToString(spreadSkipped)
                            + " spr? " + IntegerToString(spreadUnknown)
                            + " unknown " + IntegerToString(regimeUnclassified)
                             + ((EffectiveDailyProfitTargetPct() > 0.0 || EffectiveDailyMaxLossPct() > 0.0)
                               ? " | DayGuard NOT_SIM" : "");
   g_historyAuditRows[6] = "Max negative cumulative PnL | " + DoubleToString(minCumulativeClosedR, 2) + "R"
                           + (auditMoneyAvailable ? (" | est $" + DoubleToString(minCumulativeClosedMoney, 2)) : " | $ N/A (fixed/manual lot)")
                           + " | selected window " + NasAuditWindowLabel();

   g_historyAuditRunning = false;
   g_historyAuditProgressPct = 100.0;
   Print("NAS SATS EA history overlay drawn=", drawn,
         " window_weeks=", g_auditWeeksRuntime,
         " wins=", wins,
         " losses=", losses,
         " breakevens=", breakevens,
          " open=", openCount,
          " pnl_r=", DoubleToString(totalR, 2),
          " open_floating_r=", DoubleToString(openFloatingR, 2),
          " other_closed_r=", DoubleToString(otherClosedR, 2),
          " other_wins=", otherWins,
          " other_losses=", otherLosses,
          " other_flats=", otherFlats,
          " still_open=", stillOpen,
         " won_r=", DoubleToString(wonR, 2),
         " lost_r=", DoubleToString(lostR, 2),
         " profit_factor=", DoubleToString(profitFactor, 2),
         " avg_r=", DoubleToString(avgR, 3),
         " cutoff=", TimeToString(cutoff, TIME_DATE|TIME_MINUTES),
         " copied=", copied,
         " cap=", maxDraw,
         " raw_signals=", rawSignals,
         " accepted_signals=", acceptedTotal,
         " window_skipped=", windowSkipped,
         " same_direction_skipped=", sameDirectionSkipped,
         " volume_skipped=", volumeSkipped,
         " macro_regime_skipped=", macroRegimeSkipped,
         " spread_skipped=", spreadSkipped,
         " spread_unknown=", spreadUnknown,
         " v3_regime_skipped=", regimeSkipped);
}
double NormalizeVolume(const double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double v = MathFloor(volume / step) * step;
   v = MathMax(minLot, MathMin(maxLot, v));
   return NormalizeDouble(v, 8);
}
int VolumeDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 2;
   int digits = 0;
   while(digits < 8 && MathAbs(step - MathRound(step)) > 0.00000001)
   {
      step *= 10.0;
      digits++;
   }
   return digits;
}

double NormalizeVolumeDown(const double volume)
{
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double v = MathFloor(MathMin(volume, maxLot) / step + 0.0000001) * step;
   return NormalizeDouble(MathMax(0.0, v), VolumeDigits());
}

string AccountRiskKey(const string kind)
{
   return "PTS_FTMO_RISK_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + kind;
}

bool AccountRiskMagicScoped(const long magic)
{
   return magic >= 4000000000000000000 && magic < 5000000000000000000;
}

datetime AccountRiskGmtDayStart()
{
   datetime now = TimeGMT();
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   datetime shifted = now - resetHour * 3600;
   return shifted - (shifted % 86400) + resetHour * 3600;
}

datetime AccountRiskStartGmt()
{
   string key = AccountRiskKey("START_GMT");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, (double)TimeGMT());
   return (datetime)GlobalVariableGet(key);
}

void AccountRiskCacheInvalidate()
{
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   GlobalVariableSet(AccountRiskKey("METRICS_TS_H" + IntegerToString(resetHour)), 0.0);
}

void DailyPnlGuardCacheInvalidate()
{
   g_dailyGuardScopeCacheMs = 0;
   g_dailyGuardScopeCacheDay = 0;
}

double AccountRiskInitialBalance()
{
   if(InpAccountRiskInitialBalanceOverride > 0.0)
      return InpAccountRiskInitialBalanceOverride;
   string key = AccountRiskKey("INITIAL_BALANCE");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, MathMax(0.01, AccountInfoDouble(ACCOUNT_BALANCE)));
   return MathMax(0.01, GlobalVariableGet(key));
}

void AccountRiskScopePerformance(double &closedAll, double &closedToday, double &floating)
{
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   string cacheSuffix = "_H" + IntegerToString(resetHour);
   string cacheTsKey = AccountRiskKey("METRICS_TS" + cacheSuffix);
   string closedAllKey = AccountRiskKey("CLOSED_ALL" + cacheSuffix);
   string closedTodayKey = AccountRiskKey("CLOSED_TODAY" + cacheSuffix);
   string floatingKey = AccountRiskKey("FLOATING" + cacheSuffix);
   double nowLocal = (double)TimeLocal();
   if(GlobalVariableCheck(cacheTsKey)
      && nowLocal - GlobalVariableGet(cacheTsKey) < 1.0
      && GlobalVariableCheck(closedAllKey)
      && GlobalVariableCheck(closedTodayKey)
      && GlobalVariableCheck(floatingKey))
   {
      closedAll = GlobalVariableGet(closedAllKey);
      closedToday = GlobalVariableGet(closedTodayKey);
      floating = GlobalVariableGet(floatingKey);
      return;
   }
   closedAll = 0.0;
   closedToday = 0.0;
   floating = 0.0;
   datetime dayStartGmt = AccountRiskGmtDayStart();
   datetime startGmt = AccountRiskStartGmt();
   datetime serverNow = TimeTradeServer();
   datetime gmtNow = TimeGMT();
   datetime dayStartServer = dayStartGmt + (serverNow - gmtNow);
   datetime startServer = startGmt + (serverNow - gmtNow);
   datetime historyStartServer = MathMax(dayStartServer, startServer);
   if(HistorySelect(startServer, serverNow))
   {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;
         ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
            continue;
         if(!AccountRiskMagicScoped((long)HistoryDealGetInteger(ticket, DEAL_MAGIC)))
            continue;
         double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                    + HistoryDealGetDouble(ticket, DEAL_FEE);
         closedAll += pnl;
         if((datetime)HistoryDealGetInteger(ticket, DEAL_TIME) >= historyStartServer)
            closedToday += pnl;
      }
   }
   for(int j = PositionsTotal() - 1; j >= 0; j--)
   {
      ulong ticket = PositionGetTicket(j);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      floating += PositionGetDouble(POSITION_PROFIT)
                + PositionGetDouble(POSITION_SWAP);
   }
   GlobalVariableSet(closedAllKey, closedAll);
   GlobalVariableSet(closedTodayKey, closedToday);
   GlobalVariableSet(floatingKey, floating);
   GlobalVariableSet(cacheTsKey, nowLocal);
}

double AccountRiskDayStartScope(const double initial,
                                const double closedAll,
                                const double closedToday,
                                const double scopeEquity)
{
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   datetime dayStartGmt = AccountRiskGmtDayStart();
   string suffix = "_H" + IntegerToString(resetHour);
   string dayKey = AccountRiskKey("DAY_SCOPE_" + IntegerToString((int)dayStartGmt) + suffix);
   string lastEquityKey = AccountRiskKey("LAST_SCOPE_EQUITY" + suffix);
   string lastEquityTimeKey = AccountRiskKey("LAST_SCOPE_EQUITY_GMT" + suffix);
   if(!GlobalVariableCheck(dayKey))
   {
      double reconstructed = MathMax(0.01, initial + closedAll - closedToday);
      if(GlobalVariableCheck(lastEquityKey) && GlobalVariableCheck(lastEquityTimeKey))
      {
         datetime previousGmt = (datetime)GlobalVariableGet(lastEquityTimeKey);
         if(previousGmt <= dayStartGmt && dayStartGmt - previousGmt <= 300)
            reconstructed = MathMax(0.01, GlobalVariableGet(lastEquityKey));
      }
      GlobalVariableSet(dayKey, reconstructed);
   }
   double dayStartScope = MathMax(0.01, GlobalVariableGet(dayKey));
   GlobalVariableSet(lastEquityKey, scopeEquity);
   GlobalVariableSet(lastEquityTimeKey, (double)TimeGMT());
   return dayStartScope;
}

void AccountRiskMetrics(double &riskCapital, double &dailyLossPct, double &totalDdPct)
{
   double initial = AccountRiskInitialBalance();
   double closedAll, closedToday, floating;
   AccountRiskScopePerformance(closedAll, closedToday, floating);
   double scopeEquity = MathMax(0.01, initial + closedAll + floating);
   double dayStartScope = AccountRiskDayStartScope(initial, closedAll, closedToday, scopeEquity);
   riskCapital = MathMax(0.01, MathMin(AccountInfoDouble(ACCOUNT_EQUITY), scopeEquity));
   g_accountRiskDailyPnlPct = (scopeEquity - dayStartScope) / dayStartScope * 100.0;
   dailyLossPct = MathMax(0.0, -g_accountRiskDailyPnlPct);
   totalDdPct = MathMax(0.0, -(closedAll + floating) / initial * 100.0);
}

bool DailyPnlGuardMagicOwned(const long magic)
{
   return RuntimeMagicOwned(magic);
}

void DailyPnlGuardInstancePerformance(double &closedToday, double &floating)
{
   datetime dayStartGmt = AccountRiskGmtDayStart();
   uint nowMs = GetTickCount();
   if(g_dailyGuardScopeCacheDay == dayStartGmt
      && (uint)(nowMs - g_dailyGuardScopeCacheMs) < 1000)
   {
      closedToday = g_dailyGuardClosedToday;
      floating = g_dailyGuardFloating;
      return;
   }

   closedToday = 0.0;
   floating = 0.0;
   datetime startGmt = AccountRiskStartGmt();
   datetime serverNow = TimeTradeServer();
   datetime gmtNow = TimeGMT();
   datetime dayStartServer = dayStartGmt + (serverNow - gmtNow);
   datetime startServer = startGmt + (serverNow - gmtNow);
   datetime historyStartServer = MathMax(dayStartServer, startServer);
   if(HistorySelect(historyStartServer, serverNow))
   {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;
         ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
            continue;
         if(!DailyPnlGuardMagicOwned((long)HistoryDealGetInteger(ticket, DEAL_MAGIC))
            || HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
            continue;
         closedToday += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                      + HistoryDealGetDouble(ticket, DEAL_SWAP)
                      + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                      + HistoryDealGetDouble(ticket, DEAL_FEE);
      }
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!DailyPnlGuardMagicOwned((long)PositionGetInteger(POSITION_MAGIC))
         || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   g_dailyGuardClosedToday = closedToday;
   g_dailyGuardFloating = floating;
   g_dailyGuardScopeCacheDay = dayStartGmt;
   g_dailyGuardScopeCacheMs = nowMs;
}

void DailyPnlGuardInstanceMetrics()
{
   double instanceClosedToday, instanceFloating;
   DailyPnlGuardInstancePerformance(instanceClosedToday, instanceFloating);

   // Preserve the existing day-start capital policy; only the PnL numerator is instance-scoped.
   double initial = AccountRiskInitialBalance();
   double closedAll, closedToday, floating;
   AccountRiskScopePerformance(closedAll, closedToday, floating);
   double scopeEquity = MathMax(0.01, initial + closedAll + floating);
   double dayStartScope = AccountRiskDayStartScope(initial, closedAll, closedToday, scopeEquity);
   g_dailyGuardPnlMoney = instanceClosedToday + instanceFloating;
   g_dailyGuardPnlPct = g_dailyGuardPnlMoney / MathMax(0.01, dayStartScope) * 100.0;
}

string DailyPnlGuardInstanceKey(const string kind)
{
   // Keep the terminal global-variable key below MT5's 63-character limit.
   return "PTS_NDG_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))
      + "_" + IntegerToString(RuntimeMagic()) + "_" + kind;
}

string DailyPnlGuardDayKey()
{
   return DailyPnlGuardInstanceKey("L" + IntegerToString((long)AccountRiskGmtDayStart())
      + "H" + IntegerToString(MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt))));
}

string DailyPnlGuardPublishKey()
{
   return DailyPnlGuardInstanceKey("P" + IntegerToString((long)AccountRiskGmtDayStart()));
}

bool DailyPnlGuardLocked(string &reason)
{
   reason = "";
   if(!DailyPnlGuardConfigured())
      return false;
   string key = DailyPnlGuardDayKey();
   if(!GlobalVariableCheck(key))
      return false;
   double code = GlobalVariableGet(key);
   reason = code > 0.0 ? "daily_profit_target_hit" : "daily_max_loss_hit";
   return true;
}

bool DailyPnlGuardAllowsNewEntry(string &reason)
{
   if(!DailyPnlGuardConfigured())
   {
      reason = "";
      return true;
   }
   if(DailyPnlGuardLocked(reason))
      return false;

   DailyPnlGuardInstanceMetrics();
   bool profitHit = EffectiveDailyProfitTargetPct() > 0.0
      && g_dailyGuardPnlPct >= EffectiveDailyProfitTargetPct();
   bool lossHit = EffectiveDailyMaxLossPct() > 0.0
      && g_dailyGuardPnlPct <= -EffectiveDailyMaxLossPct();
   if(!profitHit && !lossHit)
   {
      reason = "";
      return true;
   }

   GlobalVariableSet(DailyPnlGuardDayKey(), profitHit ? 1.0 : -1.0);
   GlobalVariablesFlush();
   reason = profitHit ? "daily_profit_target_hit" : "daily_max_loss_hit";
   WriteAccountRiskAudit("daily_pnl_guard_locked",
      "reason=" + reason
      + " instance_pnl=" + DoubleToString(g_dailyGuardPnlMoney, 2)
      + " daily_pnl_pct=" + DoubleToString(g_dailyGuardPnlPct, 3)
      + " profit_target_pct=" + DoubleToString(EffectiveDailyProfitTargetPct(), 3)
      + " max_loss_pct=" + DoubleToString(EffectiveDailyMaxLossPct(), 3), false);
   return false;
}

int DailyPnlGuardBridgeDirection()
{
   if(g_lastExecutedDirection != 0)
      return g_lastExecutedDirection;
   int managedDirection = ManagedPositionDirection();
   if(managedDirection != 0)
      return managedDirection;
   if(g_lastSignalKeyDirection != 0)
      return g_lastSignalKeyDirection;
   return g_lastDirection;
}

void EnforceDailyPnlGuard()
{
   if(!DailyPnlGuardConfigured())
      return;
   uint nowMs = GetTickCount();
   if(nowMs - g_lastDailyPnlGuardMs < 100)
      return;
   g_lastDailyPnlGuardMs = nowMs;

   string reason = "";
   if(DailyPnlGuardAllowsNewEntry(reason))
      return;

   // Keep diagnostics current after a restart even when the persistent day lock already exists.
   DailyPnlGuardInstanceMetrics();

   g_lastExecutionStatus = "DAY LOCK";
   g_lastExecutionBlockReason = reason;

   int closeDirection = DailyPnlGuardBridgeDirection();
   if(g_nasBridgeEnabledRuntime && closeDirection != 0 && !GlobalVariableCheck(DailyPnlGuardPublishKey()))
   {
      bool bridgeOk = NasProPublishRegimeCloseOnly(TimeCurrent(), closeDirection,
         reason + "|instance_pnl=" + DoubleToString(g_dailyGuardPnlMoney, 2)
         + "|daily_pnl_pct=" + DoubleToString(g_dailyGuardPnlPct, 3));
      if(bridgeOk)
      {
         GlobalVariableSet(DailyPnlGuardPublishKey(), 1.0);
         GlobalVariablesFlush();
      }
   }

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)
         || !DailyPnlGuardMagicOwned((long)PositionGetInteger(POSITION_MAGIC))
         || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!trade.PositionClose(ticket))
         Print("NAS SATS daily PnL guard close failed ticket=", ticket,
               " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)
         || !DailyPnlGuardMagicOwned((long)OrderGetInteger(ORDER_MAGIC))
         || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(!trade.OrderDelete(ticket))
         Print("NAS SATS daily PnL guard order delete failed ticket=", ticket,
               " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   AccountRiskCacheInvalidate();
   DailyPnlGuardCacheInvalidate();
}

double ClosedDailyAtr(const string symbol, const int period)
{
   int handle = iATR(symbol, PERIOD_D1, MathMax(2, period));
   if(handle == INVALID_HANDLE)
      return 0.0;
   double values[];
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(handle, 0, 1, 1, values);
   IndicatorRelease(handle);
   if(copied != 1 || !MathIsValidNumber(values[0]) || values[0] <= 0.0)
      return 0.0;
   return values[0];
}

bool AccountOpenRisk(double &riskMoney, int &unprotectedCount)
{
   riskMoney = 0.0;
   unprotectedCount = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string symbol = PositionGetSymbol(i);
      if(symbol == "")
         continue;
      if(!AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
      {
         unprotectedCount++;
         continue;
      }
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      bool exposed = (posType == POSITION_TYPE_BUY && sl < entry)
                  || (posType == POSITION_TYPE_SELL && sl > entry);
      if(!exposed)
         continue;
      ENUM_ORDER_TYPE orderType = posType == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double result = 0.0;
      if(!OrderCalcProfit(orderType, symbol, volume, entry, sl, result))
      {
         unprotectedCount++;
         continue;
      }
      riskMoney += MathMax(0.0, -result);
   }
   return true;
}

bool AccountRiskLockAcquire()
{
   string key = AccountRiskKey("LOCK");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   for(int i = 0; i < 50; i++)
   {
      double observed = GlobalVariableGet(key);
      double now = (double)TimeLocal();
      double leaseUntil = MathFloor(observed);
      if(leaseUntil <= now)
      {
         long chartPart = (long)(ChartID() % 100000);
         double tokenFraction = (double)(chartPart * 10 + (GetTickCount() % 10) + 1) / 1000001.0;
         double candidate = MathFloor(now + 30.0) + tokenFraction;
         if(GlobalVariableSetOnCondition(key, candidate, observed))
         {
            g_accountRiskLockValue = candidate;
            return true;
         }
      }
      Sleep(5);
   }
   return false;
}

void AccountRiskLockRelease()
{
   if(g_accountRiskLockValue > 0.0)
      GlobalVariableSetOnCondition(AccountRiskKey("LOCK"), 0.0, g_accountRiskLockValue);
   g_accountRiskLockValue = 0.0;
}

bool AccountRiskAuditClaimSnapshot()
{
   int interval = MathMax(15, InpAccountRiskAuditIntervalSeconds);
   string key = AccountRiskKey("AUDIT_SNAPSHOT_GMT");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   double now = (double)TimeGMT();
   double observed = GlobalVariableGet(key);
   if(now - observed < interval)
      return false;
   return GlobalVariableSetOnCondition(key, now, observed);
}

bool AccountRiskAuditFileLock(double &token)
{
   token = 0.0;
   string key = AccountRiskKey("AUDIT_FILE_LOCK");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   uint started = GetTickCount();
   while((uint)(GetTickCount() - started) < 10)
   {
      double observed = GlobalVariableGet(key);
      double now = (double)TimeLocal();
      if(observed <= 0.0 || MathFloor(observed) <= now)
      {
         double candidate = MathFloor(now + 2.0) + (double)((ChartID() % 100000) + 1) / 100001.0;
         if(GlobalVariableSetOnCondition(key, candidate, observed))
         {
            token = candidate;
            return true;
         }
      }
      Sleep(1);
   }
   return false;
}

void AccountRiskAuditFileUnlock(const double token)
{
   if(token > 0.0)
      GlobalVariableSetOnCondition(AccountRiskKey("AUDIT_FILE_LOCK"), 0.0, token);
}

string AccountRiskPositionSummary(int &openCount, int &protectedCount, int &unprotectedCount, double &totalVolume, double &openRisk)
{
   openCount = 0;
   protectedCount = 0;
   unprotectedCount = 0;
   totalVolume = 0.0;
   openRisk = 0.0;
   string summary = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)
         || !AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      openCount++;
      totalVolume += volume;
      double risk = -1.0;
      bool exposed = (posType == POSITION_TYPE_BUY && sl > 0.0 && sl < entry)
                  || (posType == POSITION_TYPE_SELL && sl > entry);
      if(exposed)
      {
         double result = 0.0;
         ENUM_ORDER_TYPE orderType = posType == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(OrderCalcProfit(orderType, symbol, volume, entry, sl, result))
         {
            risk = MathMax(0.0, -result);
            openRisk += risk;
            protectedCount++;
         }
         else
            unprotectedCount++;
      }
      else
         unprotectedCount++;
      if(StringLen(summary) < 1800)
      {
         if(StringLen(summary) > 0)
            summary += "|";
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         summary += (string)ticket + ":" + symbol + ":" + (posType == POSITION_TYPE_BUY ? "BUY" : "SELL")
            + ":v=" + DoubleToString(volume, 4)
            + ":e=" + DoubleToString(entry, digits)
            + ":sl=" + DoubleToString(sl, digits)
            + ":risk=" + (risk >= 0.0 ? DoubleToString(risk, 2) : "UNPROTECTED");
      }
   }
   return summary;
}

void WriteAccountRiskAudit(const string eventName, const string detail, const bool periodic)
{
   if(IsTesterMode())
      return;
   if((!AccountRiskRuntimeEnabled() && !DailyPnlGuardConfigured()) || !InpAccountRiskAuditEnabled)
      return;
   // Compact audit: periodic health snapshots are telemetry and can grow to GBs.
   // Keep only lifecycle/risk decisions such as lot_selected, lot_blocked, liquidation events.
   if(periodic)
      return;
   double closedAll, closedToday, floating;
   AccountRiskScopePerformance(closedAll, closedToday, floating);
   double riskCapital, dailyLossPct, totalDdPct;
   AccountRiskMetrics(riskCapital, dailyLossPct, totalDdPct);
   double initial = AccountRiskInitialBalance();
   double scopeEquity = MathMax(0.01, initial + closedAll + floating);
   int openCount, protectedCount, unprotectedCount;
   double totalVolume, openRisk;
   string positions = AccountRiskPositionSummary(openCount, protectedCount, unprotectedCount, totalVolume, openRisk);
   double tradeBudget = riskCapital * MathMax(0.0, g_accountRiskPerTradePctRuntime) / 100.0;
   double atrBudget = riskCapital * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double portfolioBudget = riskCapital * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginUsagePct = riskCapital > 0.0 ? margin / riskCapital * 100.0 : 100.0;
   string fileName = "AccountRiskAudit_MT5_v2_" + NasAuditDate(TimeGMT()) + ".csv";
   double auditLock = 0.0;
   if(!AccountRiskAuditFileLock(auditLock))
      return;
   int h = FileOpen(fileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      AccountRiskAuditFileUnlock(auditLock);
      return;
   }
   bool empty = FileSize(h) <= 0;
   FileSeek(h, 0, SEEK_END);
   if(empty)
      FileWrite(h, "ts_gmt", "ts_server", "event", "build", "terminal", "account", "reporter", "symbol", "timeframe",
         "initial_balance", "account_balance", "account_equity", "scope_closed_all", "scope_closed_today", "scope_floating",
         "scope_equity", "risk_capital", "daily_pnl_pct", "daily_loss_pct", "daily_profit_target_pct", "daily_max_loss_pct",
         "daily_guard_locked", "total_dd_pct", "margin", "margin_usage_pct", "open_positions",
         "protected_positions", "unprotected_positions", "total_volume", "open_sl_risk", "trade_budget", "atr_budget",
         "portfolio_budget", "available_portfolio_risk", "safety_pct", "day_reset_gmt", "positions", "detail");
   FileWrite(h, TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS), TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName, "1.27", "MT5", (string)AccountInfoInteger(ACCOUNT_LOGIN), "NasUltimate", _Symbol, EnumToString(_Period),
      DoubleToString(initial, 2), DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2), DoubleToString(closedAll, 2),
      DoubleToString(closedToday, 2), DoubleToString(floating, 2), DoubleToString(scopeEquity, 2),
      DoubleToString(riskCapital, 2), DoubleToString(g_accountRiskDailyPnlPct, 3), DoubleToString(dailyLossPct, 3),
      DoubleToString(EffectiveDailyProfitTargetPct(), 3), DoubleToString(EffectiveDailyMaxLossPct(), 3),
      GlobalVariableCheck(DailyPnlGuardDayKey()) ? "1" : "0", DoubleToString(totalDdPct, 3),
      DoubleToString(margin, 2), DoubleToString(marginUsagePct, 3), IntegerToString(openCount),
      IntegerToString(protectedCount), IntegerToString(unprotectedCount), DoubleToString(totalVolume, 4),
      DoubleToString(openRisk, 2), DoubleToString(tradeBudget, 2), DoubleToString(atrBudget, 2),
      DoubleToString(portfolioBudget, 2), DoubleToString(MathMax(0.0, portfolioBudget - openRisk), 2),
      DoubleToString(InpAccountRiskSafetyBufferPct, 1),
      IntegerToString(MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt))), positions, detail);
   FileFlush(h);
   FileClose(h);
   AccountRiskAuditFileUnlock(auditLock);
}

void EnforceAccountRiskBreach()
{
   if(!g_ftmoModeRuntime || !InpAccountRiskLiquidateOnBreach)
      return;
   uint guardNow = GetTickCount();
   if(guardNow - g_lastAccountRiskGuardMs < 100)
      return;
   g_lastAccountRiskGuardMs = guardNow;
   double riskCapital, dailyPct, totalPct;
   AccountRiskMetrics(riskCapital, dailyPct, totalPct);
   double safety = MathMax(1.0, MathMin(100.0, InpAccountRiskSafetyBufferPct)) / 100.0;
   bool breached = (EffectiveDailyLossLimitPct() > 0.0 && dailyPct >= EffectiveDailyLossLimitPct() * safety)
      || (EffectiveMaxDrawdownPct() > 0.0 && totalPct >= EffectiveMaxDrawdownPct() * safety);
   if(!breached)
      return;
   string attemptKey = AccountRiskKey("BREACH_ATTEMPT");
   double now = (double)TimeLocal();
   if(GlobalVariableCheck(attemptKey) && now - GlobalVariableGet(attemptKey) < 2.0)
      return;
   GlobalVariableSet(attemptKey, now);
   if(!AccountRiskLockAcquire())
      return;
   AccountRiskCacheInvalidate();
   AccountRiskMetrics(riskCapital, dailyPct, totalPct);
   breached = (EffectiveDailyLossLimitPct() > 0.0 && dailyPct >= EffectiveDailyLossLimitPct() * safety)
      || (EffectiveMaxDrawdownPct() > 0.0 && totalPct >= EffectiveMaxDrawdownPct() * safety);
   if(!breached)
   {
      AccountRiskLockRelease();
      return;
   }
   Print("NAS SATS ACCOUNT RISK LIQUIDATION daily_loss_pct=", DoubleToString(dailyPct, 3),
         " total_dd_pct=", DoubleToString(totalPct, 3),
         " safety_pct=", DoubleToString(InpAccountRiskSafetyBufferPct, 1));
   WriteAccountRiskAudit("liquidation_triggered",
      "daily_loss_pct=" + DoubleToString(dailyPct, 3) + " total_dd_pct=" + DoubleToString(totalPct, 3), false);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)
         || !AccountRiskMagicScoped((long)PositionGetInteger(POSITION_MAGIC)))
         continue;
      if(!trade.PositionClose(ticket))
         Print("NAS SATS account risk close failed ticket=", ticket,
               " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)
         || !AccountRiskMagicScoped((long)OrderGetInteger(ORDER_MAGIC)))
         continue;
      if(!trade.OrderDelete(ticket))
         Print("NAS SATS account risk pending delete failed ticket=", ticket,
               " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   AccountRiskCacheInvalidate();
   WriteAccountRiskAudit("liquidation_complete", "scoped_positions_close_attempted", false);
   AccountRiskLockRelease();
}

double NormalizeRiskVolume(const double requested, const int divisor)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double configuredMax = InpAdvancedLotMax > 0.0 ? MathMin(maxLot, InpAdvancedLotMax) : maxLot;
   double capped = MathMin(requested, configuredMax);
   if(capped < minLot)
      return 0.0;
   long units = (long)MathFloor(capped / step + 0.0000001);
   int split = MathMax(1, divisor);
   long minUnits = (long)MathCeil(minLot / step - 0.0000001);
   long requiredUnits = minUnits * split;
   if(units < requiredUnits)
      return 0.0;
   units -= units % split;
   if(units < requiredUnits)
      return 0.0;
   double volume = NormalizeDouble((double)units * step, 8);
   if(volume < minLot || volume > configuredMax)
      return 0.0;
   return volume;
}

double ResolveAdvancedVolume(const int direction, const double entry, const double sl, string &detail)
{
   double fallback = UseSingleOrderTpMode() ? FixedVolume() : NormalizeVolume(g_totalLotRuntime > 0.0 ? g_totalLotRuntime : InpTotalLot);
   int divisor = UseSingleOrderTpMode() ? 1 : 3;
   if(!AccountRiskRuntimeEnabled())
   {
      double manualVolume = NormalizeRiskVolume(fallback, divisor);
      detail = "advanced_account_risk=off manual_volume=" + DoubleToString(manualVolume, 4);
      return manualVolume;
   }
   bool advancedLotEnabled = InpAdvancedLotEngineEnabled && AccountRiskRuntimeEnabled();

   double equity, dailyLossPct, totalDdPct;
   AccountRiskMetrics(equity, dailyLossPct, totalDdPct);
   double marginUsagePct = equity > 0.0 ? AccountInfoDouble(ACCOUNT_MARGIN) / equity * 100.0 : 100.0;
   double safety = MathMax(1.0, MathMin(100.0, InpAccountRiskSafetyBufferPct)) / 100.0;
   if(equity <= 0.0
      || (EffectiveDailyLossLimitPct() > 0.0 && dailyLossPct >= EffectiveDailyLossLimitPct() * safety)
      || (EffectiveMaxDrawdownPct() > 0.0 && totalDdPct >= EffectiveMaxDrawdownPct() * safety)
      || (InpAccountRiskMaxMarginUsagePct > 0.0 && marginUsagePct >= InpAccountRiskMaxMarginUsagePct))
   {
      detail = "account_risk_block equity=" + DoubleToString(equity, 2)
         + " daily_loss_pct=" + DoubleToString(dailyLossPct, 3)
         + " total_dd_pct=" + DoubleToString(totalDdPct, 3)
         + " margin_usage_pct=" + DoubleToString(marginUsagePct, 3);
      return 0.0;
   }

   double dailyAtr = ClosedDailyAtr(_Symbol, InpAdvancedLotDailyAtrPeriod);
   if(sl <= 0.0 || MathAbs(entry - sl) <= 0.0 || dailyAtr <= 0.0)
   {
      detail = "advanced_lot_invalid_inputs atr=" + DoubleToString(dailyAtr, _Digits)
         + " entry=" + DoubleToString(entry, _Digits)
         + " sl=" + DoubleToString(sl, _Digits);
      return InpAccountRiskFailClosed ? 0.0 : fallback;
   }

   ENUM_ORDER_TYPE orderType = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double slResult = 0.0;
   double atrResult = 0.0;
   double atrExit = direction > 0 ? entry - dailyAtr : entry + dailyAtr;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entry, sl, slResult)
      || !OrderCalcProfit(orderType, _Symbol, 1.0, entry, atrExit, atrResult))
   {
      detail = "advanced_lot_profit_calc_failed err=" + IntegerToString(GetLastError());
      return InpAccountRiskFailClosed ? 0.0 : fallback;
   }
   double slMoneyPerLot = MathAbs(slResult);
   double atrMoneyPerLot = MathAbs(atrResult);
   if(slMoneyPerLot <= 0.0 || atrMoneyPerLot <= 0.0)
   {
      detail = "advanced_lot_invalid_money_per_lot";
      return InpAccountRiskFailClosed ? 0.0 : fallback;
   }

   double openRisk = 0.0;
   int unprotectedCount = 0;
   AccountOpenRisk(openRisk, unprotectedCount);
   if(InpAccountRiskBlockUnprotectedPositions && unprotectedCount > 0)
   {
      detail = "account_risk_block unprotected_positions=" + IntegerToString(unprotectedCount);
      return 0.0;
   }

   double tradeBudget = equity * MathMax(0.0, g_accountRiskPerTradePctRuntime) / 100.0;
   bool strictRiskLotOnly = g_riskLotOnlyRuntime && !g_ftmoModeRuntime;
   double atrBudget = strictRiskLotOnly ? 1.0e100 : equity * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double portfolioBudget = strictRiskLotOnly ? 1.0e100 : equity * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double availablePortfolio = strictRiskLotOnly ? 1.0e100 : MathMax(0.0, portfolioBudget - openRisk);
   if(tradeBudget <= 0.0 || (!strictRiskLotOnly && (atrBudget <= 0.0 || availablePortfolio <= 0.0)))
   {
      detail = "account_risk_block exhausted_budget mode=" + (strictRiskLotOnly ? "risklot_only_strict" : "ftmo_guarded")
         + " open_risk=" + DoubleToString(openRisk, 2)
         + " portfolio_budget=" + (strictRiskLotOnly ? "DISABLED" : DoubleToString(portfolioBudget, 2));
      return 0.0;
   }

   double slVolume = tradeBudget / slMoneyPerLot;
   double atrVolume = strictRiskLotOnly ? slVolume : atrBudget / atrMoneyPerLot;
   double portfolioVolume = strictRiskLotOnly ? slVolume : availablePortfolio / slMoneyPerLot;
   double rawVolume = advancedLotEnabled ? (strictRiskLotOnly ? slVolume : MathMin(slVolume, MathMin(atrVolume, portfolioVolume))) : fallback;
   double volume = advancedLotEnabled ? NormalizeRiskVolume(rawVolume, divisor) : NormalizeRiskVolume(fallback, divisor);
   double projectedRisk = slMoneyPerLot * volume;
   double projectedAtr = atrMoneyPerLot * volume;
   if(volume <= 0.0
      || projectedRisk > tradeBudget + 0.01
      || (!strictRiskLotOnly && (projectedRisk > availablePortfolio + 0.01 || projectedAtr > atrBudget + 0.01)))
   {
      detail = "account_risk_block volume_below_min_or_budget mode=" + (strictRiskLotOnly ? "risklot_only_strict" : "ftmo_guarded")
         + " raw=" + DoubleToString(rawVolume, 4)
         + " projected_risk=" + DoubleToString(projectedRisk, 2)
         + " projected_atr=" + DoubleToString(projectedAtr, 2);
      return 0.0;
   }

   double requiredMargin = 0.0;
   bool marginCalculated = OrderCalcMargin(orderType, _Symbol, volume, entry, requiredMargin);
   double projectedMarginPct = equity > 0.0
      ? (AccountInfoDouble(ACCOUNT_MARGIN) + requiredMargin) / equity * 100.0
      : 100.0;
   if(!marginCalculated
      || requiredMargin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)
      || (InpAccountRiskMaxMarginUsagePct > 0.0 && projectedMarginPct > InpAccountRiskMaxMarginUsagePct))
   {
      detail = "account_risk_block insufficient_margin volume=" + DoubleToString(volume, 4)
         + " required=" + DoubleToString(requiredMargin, 2)
         + " projected_margin_pct=" + DoubleToString(projectedMarginPct, 3);
      return 0.0;
   }

   detail = (advancedLotEnabled ? "advanced_lot=account_risk" : "advanced_lot=off_risk_validated") + " risk_mode=" + (strictRiskLotOnly ? "risklot_only_strict" : "ftmo_guarded")
      + " equity=" + DoubleToString(equity, 2)
      + " daily_atr=" + DoubleToString(dailyAtr, _Digits)
      + " sl_money_per_lot=" + DoubleToString(slMoneyPerLot, 2)
      + " atr_money_per_lot=" + DoubleToString(atrMoneyPerLot, 2)
      + " open_risk=" + DoubleToString(openRisk, 2)
      + " trade_budget=" + DoubleToString(tradeBudget, 2)
      + " atr_budget=" + DoubleToString(atrBudget, 2)
      + " portfolio_budget=" + DoubleToString(portfolioBudget, 2)
      + " sl_volume=" + DoubleToString(slVolume, 4)
      + " atr_volume=" + DoubleToString(atrVolume, 4)
      + " portfolio_volume=" + DoubleToString(portfolioVolume, 4)
      + " final_volume=" + DoubleToString(volume, 4)
      + " projected_risk=" + DoubleToString(projectedRisk, 2)
      + " daily_loss_pct=" + DoubleToString(dailyLossPct, 3)
      + " total_dd_pct=" + DoubleToString(totalDdPct, 3);
   return volume;
}

double LegVolume()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double totalLot = g_totalLotRuntime > 0.0 ? g_totalLotRuntime : InpTotalLot;
   return NormalizeVolume(MathFloor((totalLot / 3.0) / step) * step);
}

double FixedVolume()
{
   double fixedLot = g_fixedLotRuntime > 0.0 ? g_fixedLotRuntime : InpFixedLot;
   return NormalizeVolume(fixedLot);
}

void ApplyExecutionModeRisk(const int direction)
{
   if(InpExecutionMode != NAS_EXEC_FIXED_1_TO_3R)
      return;
   double risk = MathAbs(g_lastEntry - g_lastSl);
   if(risk <= 0.0)
      return;
   double rr = MathMax(0.1, InpFixedRR);
   double tp = direction > 0 ? g_lastEntry + risk * rr : g_lastEntry - risk * rr;
   tp = NormalizeDouble(tp, _Digits);
   g_lastTp1 = tp;
   g_lastTp2 = tp;
   g_lastTp3 = tp;
}

bool OpenThreeLegs(const int direction)
{
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      return OpenFixedOneToThreeR(direction);
   if(g_tpManagementModeRuntime == NAS_TP_FIXED_SELECTED_LEG)
      return OpenSelectedTpOrder(direction);

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool riskLockHeld = false;
   if(AccountRiskRuntimeEnabled() && !AccountRiskLockAcquire())
   {
      g_lastAdvancedLotDetail = "account_risk_block lock_busy";
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      WriteAccountRiskAudit("lot_blocked", "mode=partial dir=" + IntegerToString(direction) + " " + g_lastAdvancedLotDetail, false);
      return false;
   }
   riskLockHeld = AccountRiskRuntimeEnabled();
   if(riskLockHeld)
      AccountRiskCacheInvalidate();
   g_lastAdvancedLotDetail = "";
   double totalVolume = ResolveAdvancedVolume(direction, price, g_lastSl, g_lastAdvancedLotDetail);
   string riskGeometry = "mode=partial dir=" + IntegerToString(direction)
      + " entry=" + DoubleToString(price, _Digits) + " sl=" + DoubleToString(g_lastSl, _Digits)
      + " base_sl=" + DoubleToString(g_lastRiskBaseSl, _Digits)
      + " structural_used=" + (g_lastRiskUsedStructuralStop ? "1" : "0")
      + " swing=" + DoubleToString(g_lastRiskSwingPrice, _Digits)
      + " swing_age=" + IntegerToString(g_lastRiskSwingAgeBars)
      + " swing_atr=" + DoubleToString(g_lastRiskSwingAtr, _Digits)
      + " prominence_atr=" + DoubleToString(g_lastRiskSwingProminence, 2)
      + " pre_widen_sl=" + DoubleToString(g_lastRiskPreWidenSl, _Digits)
      + " widen_pct=" + DoubleToString(g_lastRiskWidenPct, 2)
      + " final_scale_pct=" + DoubleToString(g_lastRiskFinalScalePct, 2)
      + " " + g_lastAdvancedLotDetail;
   g_lastAdvancedLot = totalVolume;
   if(totalVolume <= 0.0)
   {
      if(riskLockHeld)
         AccountRiskLockRelease();
      WriteAccountRiskAudit("lot_blocked", riskGeometry, false);
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      Print("NAS SATS Partial-NoBE EA: account risk blocked open reason=", g_lastAdvancedLotDetail);
      return false;
   }
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0)
      step = 0.01;
   double leg = NormalizeDouble(totalVolume / 3.0, 8);
   double legUnits = leg / step;
   bool exactLeg = MathAbs(legUnits - MathRound(legUnits)) <= 0.0000001;
   if(leg < minLot - 0.0000001 || !exactLeg)
   {
      if(riskLockHeld)
         AccountRiskLockRelease();
      g_lastExecutionBlockReason = "invalid_leg_after_advanced_lot " + g_lastAdvancedLotDetail;
      Print("NAS SATS Partial-NoBE EA: invalid leg volume from advanced total lot ", DoubleToString(totalVolume, 8));
      return false;
   }
   Print("NAS SATS advanced lot resolved mode=partial total=", DoubleToString(totalVolume, 8),
         " leg=", DoubleToString(leg, 8), " ", g_lastAdvancedLotDetail);
   double tps[3] = {g_lastTp1, g_lastTp2, g_lastTp3};
   string comments[3];
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
   {
      comments[0] = "NAS_ORIG_TP1_BE";
      comments[1] = "NAS_ORIG_TP2_BE";
      comments[2] = "NAS_ORIG_TP3_BE";
   }
   else
   {
      comments[0] = "NAS_NOBE_TP1";
      comments[1] = "NAS_NOBE_TP2";
      comments[2] = "NAS_NOBE_TP3";
   }
   ulong existingTickets[];
   int existingCount = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong existingTicket = PositionGetTicket(p);
      if(existingTicket == 0 || !PositionSelectByTicket(existingTicket) || !IsManagedPosition())
         continue;
      ArrayResize(existingTickets, existingCount + 1);
      existingTickets[existingCount++] = existingTicket;
   }
   int openedCount = 0;

   for(int i = 0; i < 3; i++)
   {
      bool requestOk = trade.PositionOpen(_Symbol, type, leg, price, g_lastSl, tps[i], comments[i]);
      uint retcode = trade.ResultRetcode();
      bool ok = requestOk && (retcode == TRADE_RETCODE_DONE
         || retcode == TRADE_RETCODE_DONE_PARTIAL
         || retcode == TRADE_RETCODE_PLACED);
      if(!ok)
         Print("NAS SATS Partial-NoBE EA open failed leg=", i + 1, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      else
         openedCount++;
   }
   if(openedCount != 3)
   {
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition())
            continue;
         bool existed = false;
         for(int e = 0; e < existingCount; e++)
         {
            if(existingTickets[e] == ticket)
            {
               existed = true;
               break;
            }
         }
         if(existed)
            continue;
         if(!trade.PositionClose(ticket))
            Print("NAS SATS partial batch rollback failed ticket=", ticket,
                  " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
      if(riskLockHeld)
         AccountRiskCacheInvalidate();
      if(riskLockHeld)
         AccountRiskLockRelease();
      g_lastExecutionBlockReason = "partial_batch_incomplete opened=" + IntegerToString(openedCount) + "/3";
      WriteAccountRiskAudit("lot_selected",
         riskGeometry + " opened_legs=" + IntegerToString(openedCount) + " execution=partial_batch_incomplete", false);
      return false;
   }
   if(riskLockHeld)
      AccountRiskCacheInvalidate();
   if(riskLockHeld)
      AccountRiskLockRelease();
   WriteAccountRiskAudit("lot_selected",
      riskGeometry + " opened_legs=" + IntegerToString(openedCount), false);
   return true;
}

bool OpenSelectedTpOrder(const int direction)
{
   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int tpLeg = g_invertTradeModeRuntime ? EffectiveInversionReferenceLeg() : LegacyLegForTargetR(SelectedTargetR());
   double finalTp = CurrentSelectedFinalTp(direction);
   if(finalTp <= 0.0)
   {
      g_lastExecutionBlockReason = "selected_tp_invalid";
      return false;
   }
   bool riskLockHeld = false;
   if(AccountRiskRuntimeEnabled() && !AccountRiskLockAcquire())
   {
      g_lastAdvancedLotDetail = "account_risk_block lock_busy";
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      WriteAccountRiskAudit("lot_blocked", "mode=selected_tp dir=" + IntegerToString(direction) + " " + g_lastAdvancedLotDetail, false);
      return false;
   }
   riskLockHeld = AccountRiskRuntimeEnabled();
   if(riskLockHeld)
      AccountRiskCacheInvalidate();
   g_lastAdvancedLotDetail = "";
   double lot = ResolveAdvancedVolume(direction, price, g_lastSl, g_lastAdvancedLotDetail);
   string geometry = "mode=selected_tp dir=" + IntegerToString(direction)
      + " tp_leg=" + IntegerToString(tpLeg)
      + " invert_target=" + (g_invertTradeModeRuntime ? EffectiveInvertTargetText() : "off")
      + " hcbe_leg=" + IntegerToString(EffectiveHcBeLeg())
      + " entry=" + DoubleToString(price, _Digits)
      + " sl=" + DoubleToString(g_lastSl, _Digits)
      + " tp=" + DoubleToString(finalTp, _Digits)
      + " final_scale_pct=" + DoubleToString(g_lastRiskFinalScalePct, 2)
      + " swing_buffer_atr=" + DoubleToString(g_swingBufferAtrRuntime, 2)
      + " " + g_lastAdvancedLotDetail;
   g_lastAdvancedLot = lot;
   if(lot <= 0.0)
   {
      if(riskLockHeld)
         AccountRiskLockRelease();
      WriteAccountRiskAudit("lot_blocked", geometry, false);
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      Print("NAS SATS selected TP open blocked reason=", g_lastAdvancedLotDetail);
      return false;
   }
   string hcSuffix = g_invertTradeModeRuntime ? (g_invertHcBeProgressPctRuntime > 0 ? "_INVHC" + IntegerToString(g_invertHcBeProgressPctRuntime) : "_NOHC")
                                               : (EffectiveHcBeLeg() > 0 ? "_HC" + IntegerToString(EffectiveHcBeLeg()) : "_NOHC");
   string invertSuffix = g_invertTradeModeRuntime ? (InvertTargetOverrideEnabled() ? ("_ITP" + DoubleToString(g_invertTargetRRuntime, 2)) : "_SWAP") : "";
   string comment = (g_invertTradeModeRuntime ? "NAS_INVERT_REF" : "NAS_FIXED_TP") + IntegerToString(tpLeg) + invertSuffix + hcSuffix;
   bool requestOk = trade.PositionOpen(_Symbol, type, lot, price, g_lastSl, finalTp, comment);
   uint retcode = trade.ResultRetcode();
   bool ok = requestOk && (retcode == TRADE_RETCODE_DONE
      || retcode == TRADE_RETCODE_DONE_PARTIAL
      || retcode == TRADE_RETCODE_PLACED);
   if(ok && riskLockHeld)
      AccountRiskCacheInvalidate();
   if(riskLockHeld)
      AccountRiskLockRelease();
   WriteAccountRiskAudit("lot_selected", geometry + " order_retcode=" + IntegerToString((int)retcode), false);
   if(!ok)
   {
      g_lastExecutionBlockReason = "selected_tp_order_failed ret=" + IntegerToString((int)retcode);
      Print("NAS SATS selected TP open failed ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription(),
            " lot=", DoubleToString(lot, 8),
            " sl=", DoubleToString(g_lastSl, _Digits),
            " tp=", DoubleToString(finalTp, _Digits));
      return false;
   }
   return true;
}
bool OpenFixedOneToThreeR(const int direction)
{
   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool riskLockHeld = false;
   if(AccountRiskRuntimeEnabled() && !AccountRiskLockAcquire())
   {
      g_lastAdvancedLotDetail = "account_risk_block lock_busy";
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      WriteAccountRiskAudit("lot_blocked", "mode=fixed dir=" + IntegerToString(direction) + " " + g_lastAdvancedLotDetail, false);
      return false;
   }
   riskLockHeld = AccountRiskRuntimeEnabled();
   if(riskLockHeld)
      AccountRiskCacheInvalidate();
   g_lastAdvancedLotDetail = "";
   double lot = ResolveAdvancedVolume(direction, price, g_lastSl, g_lastAdvancedLotDetail);
   string fixedRiskGeometry = "mode=fixed dir=" + IntegerToString(direction)
      + " entry=" + DoubleToString(price, _Digits) + " sl=" + DoubleToString(g_lastSl, _Digits)
      + " base_sl=" + DoubleToString(g_lastRiskBaseSl, _Digits)
      + " structural_used=" + (g_lastRiskUsedStructuralStop ? "1" : "0")
      + " swing=" + DoubleToString(g_lastRiskSwingPrice, _Digits)
      + " swing_age=" + IntegerToString(g_lastRiskSwingAgeBars)
      + " swing_atr=" + DoubleToString(g_lastRiskSwingAtr, _Digits)
      + " prominence_atr=" + DoubleToString(g_lastRiskSwingProminence, 2)
      + " pre_widen_sl=" + DoubleToString(g_lastRiskPreWidenSl, _Digits)
      + " widen_pct=" + DoubleToString(g_lastRiskWidenPct, 2)
      + " final_scale_pct=" + DoubleToString(g_lastRiskFinalScalePct, 2)
      + " " + g_lastAdvancedLotDetail;
   g_lastAdvancedLot = lot;
   if(lot <= 0.0)
   {
      if(riskLockHeld)
         AccountRiskLockRelease();
      WriteAccountRiskAudit("lot_blocked", fixedRiskGeometry, false);
      g_lastExecutionBlockReason = g_lastAdvancedLotDetail;
      Print("NAS SATS Fixed 1:3R EA: account risk blocked open reason=", g_lastAdvancedLotDetail);
      return false;
   }
   Print("NAS SATS advanced lot resolved mode=fixed lot=", DoubleToString(lot, 8),
         " ", g_lastAdvancedLotDetail);

   string comment = direction > 0 ? "NAS_FIXED_3R_BUY" : "NAS_FIXED_3R_SELL";
   bool requestOk = trade.PositionOpen(_Symbol, type, lot, price, g_lastSl, g_lastTp3, comment);
   uint retcode = trade.ResultRetcode();
   bool ok = requestOk && (retcode == TRADE_RETCODE_DONE
      || retcode == TRADE_RETCODE_DONE_PARTIAL
      || retcode == TRADE_RETCODE_PLACED);
   if(ok && riskLockHeld)
      AccountRiskCacheInvalidate();
   if(riskLockHeld)
      AccountRiskLockRelease();
   WriteAccountRiskAudit("lot_selected",
      fixedRiskGeometry + " order_retcode=" + IntegerToString((int)retcode), false);
   if(!ok)
   {
      Print("NAS SATS Fixed 1:3R open failed ret=", trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription(),
            " lot=", DoubleToString(lot, 8),
            " sl=", DoubleToString(g_lastSl, _Digits),
            " tp=", DoubleToString(g_lastTp3, _Digits));
      return false;
   }
   return true;
}

bool IsManagedPosition()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   return RuntimeMagicOwned((long)PositionGetInteger(POSITION_MAGIC));
}

int ManagedPositionDirection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      return type == POSITION_TYPE_BUY ? 1 : -1;
   }
   return 0;
}

int ManagedPositionCountDirection(const int direction)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      int positionDirection = type == POSITION_TYPE_BUY ? 1 : -1;
      if(direction == 0 || positionDirection == direction)
         count++;
   }
   return count;
}

bool CloseManagedPositionsDirection(const int direction)
{
   bool submitted = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      int positionDirection = type == POSITION_TYPE_BUY ? 1 : -1;
      if(direction != 0 && positionDirection != direction)
         continue;
      if(!trade.PositionClose(ticket))
         submitted = false;
   }
   return submitted && ManagedPositionCountDirection(direction) == 0;
}

void CloseManagedPositions()
{
   CloseManagedPositionsDirection(0);
}

bool NasTimedExitNativePlan(int &direction, datetime &entryTime)
{
   direction = 0;
   entryTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      int candidateDirection = type == POSITION_TYPE_BUY ? 1 : -1;
      datetime candidateTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(entryTime == 0 || candidateTime < entryTime)
      {
         direction = candidateDirection;
         entryTime = candidateTime;
      }
   }
   return direction != 0 && entryTime > 0;
}

bool DeleteManagedPendingOrders()
{
   bool submitted = true;
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol
         || !RuntimeMagicOwned((long)OrderGetInteger(ORDER_MAGIC)))
         continue;
      if(!trade.OrderDelete(ticket))
         submitted = false;
   }
   return submitted;
}

void ResetNasTimedExitCloseState()
{
   g_nasTimedExitClose.active = false;
   g_nasTimedExitClose.deadline = 0;
   g_nasTimedExitClose.closeDirection = 0;
   g_nasTimedExitClose.bridgeDone = false;
   g_nasTimedExitClose.localDone = false;
   g_nasTimedExitClose.nextRetryLocal = 0;
   g_nasTimedExitClose.attempts = 0;
}

void EnforceNasTimedExit()
{
   if(!NasTimedExitConfigured())
      return;
   uint nowMs = GetTickCount();
   if((uint)(nowMs - g_lastTimedExitGuardMs) < 200)
      return;
   g_lastTimedExitGuardMs = nowMs;

   datetime serverNow = TimeTradeServer();
   if(serverNow <= 0)
      serverNow = TimeCurrent();

   if(!g_nasTimedExitClose.active)
   {
      int nativeDirection = 0;
      datetime nativeEntryTime = 0;
      bool hasNative = NasTimedExitNativePlan(nativeDirection, nativeEntryTime);
      int closeDirection = hasNative ? nativeDirection : g_timedExitBridgePlanDirection;
      datetime referenceTime = hasNative ? nativeEntryTime : g_timedExitBridgePlanSignalTime;
      if(MathAbs(closeDirection) != 1 || referenceTime <= 0)
         return;
      datetime deadline = NasTimedExitDeadlineForEntry(referenceTime);
      if(deadline <= 0 || serverNow < deadline)
         return;

      g_nasTimedExitClose.active = true;
      g_nasTimedExitClose.deadline = deadline;
      g_nasTimedExitClose.closeDirection = closeDirection;
      g_nasTimedExitClose.bridgeDone = !g_nasBridgeEnabledRuntime || g_timedExitBridgePlanDirection == 0;
      g_nasTimedExitClose.localDone = !hasNative;
      g_nasTimedExitClose.nextRetryLocal = 0;
      g_nasTimedExitClose.attempts = 0;
   }

   if(g_nasTimedExitClose.nextRetryLocal > 0 && TimeLocal() < g_nasTimedExitClose.nextRetryLocal)
      return;
   g_nasTimedExitClose.attempts++;

   if(!g_nasTimedExitClose.bridgeDone)
      g_nasTimedExitClose.bridgeDone = NasProPublishRegimeCloseOnly(
         g_nasTimedExitClose.deadline,
         g_nasTimedExitClose.closeDirection,
         "max_hold_exit|duration=" + g_timedExitTimeRuntime);
   if(!g_nasTimedExitClose.localDone)
   {
      bool positionsDone = CloseManagedPositionsDirection(g_nasTimedExitClose.closeDirection);
      bool ordersDone = DeleteManagedPendingOrders();
      g_nasTimedExitClose.localDone = positionsDone && ordersDone;
   }

   if(g_nasTimedExitClose.bridgeDone && g_nasTimedExitClose.localDone)
   {
      g_lastExecutionStatus = "TIME EXIT";
      g_lastExecutionBlockReason = "max_hold_reached_" + g_timedExitTimeRuntime;
      NasProAuditWrite("timed_exit_closed",
         "nas|" + IntegerToString((long)g_nasTimedExitClose.deadline),
         -g_nasTimedExitClose.closeDirection, 0.0, 0.0, 0.0, 0.0,
         "duration=" + g_timedExitTimeRuntime
         + " close_direction=" + (g_nasTimedExitClose.closeDirection > 0 ? "BUY" : "SELL")
         + " attempts=" + IntegerToString(g_nasTimedExitClose.attempts));
      Print("NAS SATS EA max hold exit completed duration=", g_timedExitTimeRuntime,
            " deadline=", TimeToString(g_nasTimedExitClose.deadline, TIME_DATE|TIME_MINUTES),
            " close_direction=", (g_nasTimedExitClose.closeDirection > 0 ? "BUY" : "SELL"),
            " attempts=", g_nasTimedExitClose.attempts,
            " bridge_done=", g_nasTimedExitClose.bridgeDone,
            " local_done=", g_nasTimedExitClose.localDone);
      g_lastExecutedDirection = 0;
      ClearNasTimedExitBridgePlan();
      ResetNasTimedExitCloseState();
      AccountRiskCacheInvalidate();
      DailyPnlGuardCacheInvalidate();
      RequestHistoryRefresh();
      return;
   }

   g_lastExecutionStatus = "TIME EXIT RETRY";
   g_lastExecutionBlockReason = "timed_exit_close_retry";
   g_nasTimedExitClose.nextRetryLocal = TimeLocal() + MathMin(30, 2 + g_nasTimedExitClose.attempts * 2);
   Print("NAS SATS EA max hold exit retry duration=", g_timedExitTimeRuntime,
         " direction=", (g_nasTimedExitClose.closeDirection > 0 ? "BUY" : "SELL"),
         " attempts=", g_nasTimedExitClose.attempts,
         " bridge_done=", g_nasTimedExitClose.bridgeDone,
         " local_done=", g_nasTimedExitClose.localDone,
         " next_retry=", TimeToString(g_nasTimedExitClose.nextRetryLocal, TIME_SECONDS));
}

void CloseOneLeg()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPosition())
      {
         trade.PositionClose(ticket);
         return;
      }
   }
}


double NasProjectedProfit(const int direction, const double volume, const double entry, const double exitPrice, bool &ok)
{
   ok = false;
   if(volume <= 0.0 || entry <= 0.0 || exitPrice <= 0.0)
      return 0.0;
   double result = 0.0;
   ENUM_ORDER_TYPE orderType = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, _Symbol, volume, entry, exitPrice, result))
      return 0.0;
   ok = true;
   return result;
}

void WriteHcBeLifecycleAudit(const string eventName, const ulong ticket, const string detail)
{
   if(IsTesterMode() || !InpAccountRiskAuditEnabled)
      return;
   string fileName = "NasUltimate_HcBeLifecycle_" + NasAuditDate(TimeGMT()) + ".csv";
   int h = FileOpen(fileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      Print("NAS SATS HCBE lifecycle audit open failed err=", GetLastError(), " file=", fileName);
      return;
   }
   bool empty = FileSize(h) <= 0;
   FileSeek(h, 0, SEEK_END);
   if(empty)
      FileWrite(h, "ts_gmt", "ts_server", "event", "build", "account", "symbol", "timeframe", "magic", "ticket", "bid", "ask", "detail");
   FileWrite(h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName,
      "1.39",
      (string)AccountInfoInteger(ACCOUNT_LOGIN),
      _Symbol,
      EnumToString(_Period),
      (string)RuntimeMagic(),
      (string)ticket,
      DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits),
      DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits),
      detail);
   FileFlush(h);
   FileClose(h);
}

bool ClosePartialVolume(const ulong ticket, const int direction, const double closeVol, string &method)
{
   method = "PositionClosePartial";
   ResetLastError();
   bool ok = trade.PositionClosePartial(ticket, closeVol);
   if(ok)
      return true;

   long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return false;

   method = direction > 0 ? "netting_sell_reduce" : "netting_buy_reduce";
   ResetLastError();
   if(direction > 0)
      return trade.Sell(closeVol, _Symbol);
   return trade.Buy(closeVol, _Symbol);
}
void MoveRemainingToBE(const bool allowPartialClose=false)
{
   if(g_lastEntry <= 0.0)
      return;
   bool anyManaged = false;
   bool allOk = true;
   string modeText = InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL ? "partial_original" : (UseSingleOrderTpMode() ? "single_order" : "multi_order");
   bool partialMode = allowPartialClose && UseSingleOrderTpMode();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;
      anyManaged = true;
      long type = PositionGetInteger(POSITION_TYPE);
      int direction = type == POSITION_TYPE_BUY ? 1 : -1;
      double entry = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), _Digits);
      double currentSl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double volumeBefore = PositionGetDouble(POSITION_VOLUME);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0)
         step = 0.01;
      double triggerPx = direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool pnlOk = false;
      double expectedHalfPnl = NasProjectedProfit(direction, NormalizeVolumeDown(volumeBefore * 0.5), entry, triggerPx, pnlOk);
      bool partialDone = false;
      string partialDetail = "partial_not_requested";
      ulong positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(positionId == 0) positionId = ticket;
      bool halfDonePersisted = NasProGetPlan(positionId, "halfDone", 0.0) > 0.5;
      double tol = MathMax(_Point, SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      bool alreadyAtBe = currentSl > 0.0 && (direction > 0 ? currentSl >= entry - tol : currentSl <= entry + tol);
      if(alreadyAtBe)
      {
         if(partialMode) NasProSetPlan(positionId, "halfDone", 1.0);
         WriteHcBeLifecycleAudit("halfbe_sl_already_be", ticket,
            "mode=" + modeText
            + " partial_done=" + (halfDonePersisted ? "1" : "0")
            + " entry=" + DoubleToString(entry, _Digits)
            + " sl=" + DoubleToString(currentSl, _Digits)
            + " tp=" + DoubleToString(tp, _Digits)
            + " volume_before=" + DoubleToString(volumeBefore, 8));
         Print("NAS SATS EA: SL -> BE already protected ticket=", ticket,
               " mode=", modeText,
               " partial_done=", halfDonePersisted,
               " entry=", DoubleToString(entry, _Digits),
               " sl=", DoubleToString(currentSl, _Digits),
               " tp=", DoubleToString(tp, _Digits));
         continue;
      }

      if(partialMode && !halfDonePersisted)
      {
         double desiredClose = volumeBefore * 0.5;
         double closeVol = NormalizeVolumeDown(desiredClose);
         double remainingVol = NormalizeDouble(volumeBefore - closeVol, VolumeDigits());
         partialDetail = "desired_close=" + DoubleToString(desiredClose, 8)
            + " close_vol=" + DoubleToString(closeVol, 8)
            + " remaining_vol=" + DoubleToString(remainingVol, 8)
            + " min_vol=" + DoubleToString(minLot, 8)
            + " step=" + DoubleToString(step, 8)
            + " projected_half_pnl=" + (pnlOk ? DoubleToString(expectedHalfPnl, 2) : "NA");

         if(closeVol < minLot - 0.0000001 || remainingVol < minLot - 0.0000001)
         {
            WriteHcBeLifecycleAudit("halfbe_blocked_volume", ticket,
               "mode=" + modeText + " entry=" + DoubleToString(entry, _Digits)
               + " trigger=" + DoubleToString(triggerPx, _Digits)
               + " volume_before=" + DoubleToString(volumeBefore, 8)
               + " " + partialDetail);
         }
         else
         {
            string method = "";
            bool partialOk = ClosePartialVolume(ticket, direction, closeVol, method);
            uint partialRet = trade.ResultRetcode();
            string retText = trade.ResultRetcodeDescription();
            if(!partialOk)
            {
               allOk = false;
               WriteHcBeLifecycleAudit("halfbe_partial_close_failed", ticket,
                  "mode=" + modeText + " method=" + method
                  + " entry=" + DoubleToString(entry, _Digits)
                  + " trigger=" + DoubleToString(triggerPx, _Digits)
                  + " volume_before=" + DoubleToString(volumeBefore, 8)
                  + " " + partialDetail
                  + " ret=" + IntegerToString((int)partialRet)
                  + " ret_text=" + retText
                  + " err=" + IntegerToString(GetLastError()));
               Print("NAS SATS HCBE partial close failed ticket=", ticket,
                     " method=", method,
                     " close_vol=", DoubleToString(closeVol, 8),
                     " ret=", partialRet, " ", retText,
                     " err=", GetLastError());
               continue;
            }
            partialDone = true;
            halfDonePersisted = true;
            NasProSetPlan(positionId, "halfDone", 1.0);
            WriteHcBeLifecycleAudit("halfbe_partial_close_done", ticket,
               "mode=" + modeText + " method=" + method
               + " entry=" + DoubleToString(entry, _Digits)
               + " trigger=" + DoubleToString(triggerPx, _Digits)
               + " volume_before=" + DoubleToString(volumeBefore, 8)
               + " " + partialDetail
               + " ret=" + IntegerToString((int)partialRet)
               + " ret_text=" + retText);
            Print("NAS SATS HCBE partial close done ticket=", ticket,
                  " method=", method,
                  " close_vol=", DoubleToString(closeVol, 8),
                  " projected_half_pnl=", (pnlOk ? DoubleToString(expectedHalfPnl, 2) : "NA"));
         }

         if(!PositionSelectByTicket(ticket))
         {
            WriteHcBeLifecycleAudit("halfbe_position_closed_after_partial", ticket,
               "mode=" + modeText + " volume_before=" + DoubleToString(volumeBefore, 8)
               + " " + partialDetail);
            continue;
         }
         currentSl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
         entry = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), _Digits);
      }


      ResetLastError();
      bool ok = trade.PositionModify(ticket, entry, tp);
      if(ok)
      {
         WriteHcBeLifecycleAudit("halfbe_sl_to_be_done", ticket,
            "mode=" + modeText
            + " partial_done=" + (partialDone ? "1" : "0")
            + " entry=" + DoubleToString(entry, _Digits)
            + " old_sl=" + DoubleToString(currentSl, _Digits)
            + " new_sl=" + DoubleToString(entry, _Digits)
            + " tp=" + DoubleToString(tp, _Digits)
            + " volume_before=" + DoubleToString(volumeBefore, 8)
            + " ret=" + IntegerToString((int)trade.ResultRetcode())
            + " ret_text=" + trade.ResultRetcodeDescription());
         Print("NAS SATS EA: SL -> BE moved ticket=", ticket,
               " mode=", modeText,
               " partial_done=", partialDone,
               " old_sl=", DoubleToString(currentSl, _Digits),
               " new_sl=", DoubleToString(entry, _Digits),
               " tp=", DoubleToString(tp, _Digits),
               " ret=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription());
      }
      else
      {
         allOk = false;
         WriteHcBeLifecycleAudit("halfbe_sl_to_be_failed", ticket,
            "mode=" + modeText
            + " partial_done=" + (partialDone ? "1" : "0")
            + " entry=" + DoubleToString(entry, _Digits)
            + " old_sl=" + DoubleToString(currentSl, _Digits)
            + " new_sl=" + DoubleToString(entry, _Digits)
            + " tp=" + DoubleToString(tp, _Digits)
            + " volume_before=" + DoubleToString(volumeBefore, 8)
            + " ret=" + IntegerToString((int)trade.ResultRetcode())
            + " ret_text=" + trade.ResultRetcodeDescription()
            + " err=" + IntegerToString(GetLastError()));
         Print("NAS SATS EA: SL -> BE move failed ticket=", ticket,
               " mode=", modeText,
               " partial_done=", partialDone,
               " old_sl=", DoubleToString(currentSl, _Digits),
               " new_sl=", DoubleToString(entry, _Digits),
               " tp=", DoubleToString(tp, _Digits),
               " ret=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription(),
               " err=", GetLastError());
      }
   }
   if(anyManaged && allOk)
      g_beMoved = true;
}

string NasAuditDate(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
}

void WriteTpWatchdogAudit(const string eventName, const ulong ticket, const string dirText, const double vol, const double entry, const double tp, const double closePx, const string reason)
{
   if(IsTesterMode())
      return;
   string fileName = "NasUltimate_TpWatchdog_" + NasAuditDate(TimeGMT()) + ".csv";
   int h = FileOpen(fileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
   {
      Print("NAS SATS TP watchdog audit open failed err=", GetLastError(), " file=", fileName);
      return;
   }
   bool empty = FileSize(h) <= 0;
   FileSeek(h, 0, SEEK_END);
   if(empty)
      FileWrite(h, "ts_gmt", "ts_server", "event", "symbol", "timeframe", "magic", "ticket", "direction", "volume", "entry", "tp", "close_px", "bid", "ask", "tolerance_points", "reason");
   FileWrite(
      h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName,
      _Symbol,
      EnumToString(_Period),
      (string)RuntimeMagic(),
      (string)ticket,
      dirText,
      DoubleToString(vol, 8),
      DoubleToString(entry, _Digits),
      DoubleToString(tp, _Digits),
      DoubleToString(closePx, _Digits),
      DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits),
      DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits),
      DoubleToString(InpTpTouchCloseTolerancePoints, 1),
      reason
   );
   FileClose(h);
}

int FindTpWatchdogRetryState(const ulong ticket)
{
   for(int i = 0; i < ArraySize(g_tpWatchdogRetryStates); ++i)
      if(g_tpWatchdogRetryStates[i].ticket == ticket)
         return i;
   return -1;
}

bool TpWatchdogRetryAllowed(const ulong ticket)
{
   int idx = FindTpWatchdogRetryState(ticket);
   return idx < 0 || TimeCurrent() >= g_tpWatchdogRetryStates[idx].nextRetry;
}

void ScheduleTpWatchdogRetry(const ulong ticket, const uint retcode)
{
   int idx = FindTpWatchdogRetryState(ticket);
   if(idx < 0)
   {
      idx = ArraySize(g_tpWatchdogRetryStates);
      ArrayResize(g_tpWatchdogRetryStates, idx + 1);
      g_tpWatchdogRetryStates[idx].ticket = ticket;
   }
   int delaySec = retcode == TRADE_RETCODE_MARKET_CLOSED ? 60 : 5;
   g_tpWatchdogRetryStates[idx].nextRetry = TimeCurrent() + delaySec;
   g_tpWatchdogRetryStates[idx].lastRetcode = retcode;
}

void ClearTpWatchdogRetry(const ulong ticket)
{
   int idx = FindTpWatchdogRetryState(ticket);
   if(idx < 0)
      return;
   int last = ArraySize(g_tpWatchdogRetryStates) - 1;
   if(idx != last)
      g_tpWatchdogRetryStates[idx] = g_tpWatchdogRetryStates[last];
   ArrayResize(g_tpWatchdogRetryStates, last);
}

void EnforceManagedTpTouchClose(const bool force)
{
   if(!InpEnforceTpTouchClose)
      return;
   uint nowMs = GetTickCount();
   int minMs = MathMax(20, InpTpTouchWatchdogTimerMs);
   if(!force && g_lastTpTouchWatchdogMs > 0 && nowMs - g_lastTpTouchWatchdogMs < (uint)minMs)
      return;
   g_lastTpTouchWatchdogMs = nowMs;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;

      double tp = PositionGetDouble(POSITION_TP);
      if(tp <= 0.0)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      int direction = type == POSITION_TYPE_BUY ? 1 : -1;
      double closePx = direction > 0 ? bid : ask;
      double tol = MathMax(0.0, InpTpTouchCloseTolerancePoints) * _Point;
      bool touched = direction > 0 ? (bid + tol >= tp) : (ask - tol <= tp);
      if(!touched)
         continue;
      if(!TpWatchdogRetryAllowed(ticket))
         continue;

      string dirText = direction > 0 ? "BUY" : "SELL";
      double vol = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      bool ok = false;
      int attempts = MathMax(1, InpTpTouchCloseRetryCount);
      for(int attempt = 1; attempt <= attempts; attempt++)
      {
         ResetLastError();
         ok = trade.PositionClose(ticket);
         if(ok)
            break;
         uint retcode = trade.ResultRetcode();
         Print("NAS SATS TP watchdog close attempt failed ticket=", ticket,
               " attempt=", attempt,
               " ret=", retcode,
               " ", trade.ResultRetcodeDescription());
         if(retcode == TRADE_RETCODE_MARKET_CLOSED)
            break;
      }
      if(ok)
      {
         ClearTpWatchdogRetry(ticket);
         Print("NAS SATS TP watchdog closed ticket=", ticket,
               " dir=", dirText,
               " vol=", DoubleToString(vol, 8),
               " entry=", DoubleToString(entry, _Digits),
               " tp=", DoubleToString(tp, _Digits),
               " close_px=", DoubleToString(closePx, _Digits),
               " tolerance_pts=", DoubleToString(InpTpTouchCloseTolerancePoints, 1));
         WriteTpWatchdogAudit("tp_watchdog_closed", ticket, dirText, vol, entry, tp, closePx, "tp_touched");
      }
      else
      {
         ScheduleTpWatchdogRetry(ticket, trade.ResultRetcode());
         Print("NAS SATS TP watchdog close failed ticket=", ticket,
               " dir=", dirText,
               " tp=", DoubleToString(tp, _Digits),
               " close_px=", DoubleToString(closePx, _Digits),
               " ret=", trade.ResultRetcode(),
               " ", trade.ResultRetcodeDescription());
         WriteTpWatchdogAudit("tp_watchdog_close_failed", ticket, dirText, vol, entry, tp, closePx, "ret=" + (string)trade.ResultRetcode() + " " + trade.ResultRetcodeDescription());
      }
   }
}

void ManageOpenPositions()
{
   EnforceManagedTpTouchClose(true);

   if(g_lastDirection == 0 || g_beMoved)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
   {
      bool tp1Touched = g_lastDirection > 0 ? (bid >= g_lastTp1) : (ask <= g_lastTp1);
      if(tp1Touched)
         MoveRemainingToBE();
      return;
   }

   double hcPrice = 0.0;
   if(g_invertTradeModeRuntime)
   {
      int finalLeg = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? 6 : EffectiveInversionReferenceLeg();
      double finalTp = CurrentSelectedFinalTp(g_lastDirection);
      hcPrice = InvertHcBePrice(g_lastDirection, g_lastEntry, finalTp);
   }
   else
   {
      double activeFinalTp = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R
         ? g_lastTp3
         : CurrentSelectedFinalTp(g_lastDirection);
      double activeTargetR = NasTargetR(g_lastDirection, g_lastEntry, g_lastSl, activeFinalTp);
      if(EffectiveHcBeLeg() <= 0 || RMultipleForLeg(EffectiveHcBeLeg()) >= activeTargetR - 0.0001)
         return;
      hcPrice = CurrentFinalTpForLeg(g_lastDirection, EffectiveHcBeLeg());
   }
   if(hcPrice <= 0.0)
      return;
   bool hcTouched = g_lastDirection > 0 ? (bid >= hcPrice) : (ask <= hcPrice);
   if(hcTouched)
      MoveRemainingToBE(UseSingleOrderTpMode());
}

double ManagedOpenPnl()
{
   double pnl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManagedPosition())
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pnl;
}

double HistoryPnl(const datetime fromTime)
{
   double pnl = 0.0;
   if(!HistorySelect(fromTime, TimeCurrent()))
      return 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      if(!RuntimeMagicOwned((long)HistoryDealGetInteger(deal, DEAL_MAGIC)))
         continue;
      pnl += HistoryDealGetDouble(deal, DEAL_PROFIT);
      pnl += HistoryDealGetDouble(deal, DEAL_SWAP);
      pnl += HistoryDealGetDouble(deal, DEAL_COMMISSION);
   }
   return pnl;
}

datetime DayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

void DrawHLine(const string name, const double price, const color clr, const ENUM_LINE_STYLE style, const int width)
{
   if(IsTesterMode())
      return;
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
}

void DrawHistoricalArrow(const string name, const datetime t, const double price, const int arrowCode, const color clr)
{
   if(IsTesterMode())
      return;
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_ARROW, 0, t, price);
   ObjectMove(0, obj, 0, t, price);
   ObjectSetInteger(0, obj, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, 2);
}

void DrawExecutionSignal(const int direction,
                         const datetime signalTime,
                         const double signalHigh,
                         const double signalLow,
                         const string signalLabel)
{
   string side = direction > 0 ? "BUY" : "SELL";
   string stamp = IntegerToString((int)signalTime) + "_" + side;
   double pad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 30.0, MathAbs(signalHigh - signalLow) * 0.45);
   double arrowPrice = direction > 0 ? signalLow - pad : signalHigh + pad;
   double textPrice = direction > 0 ? arrowPrice - pad * 0.55 : arrowPrice + pad * 0.55;
   color clr = direction > 0 ? clrLime : clrTomato;
   int arrowCode = direction > 0 ? 233 : 234;
   string arrowName = "LIVE_EXEC_" + stamp + "_ARW";
   string textName = "LIVE_EXEC_" + stamp + "_TXT";
   DrawHistoricalArrow(arrowName, signalTime, arrowPrice, arrowCode, clr);
   DrawHistoricalText(textName,
                      "EXEC " + signalLabel + " E=" + DoubleToString(g_lastEntry, _Digits),
                      signalTime + PeriodSeconds(_Period),
                      textPrice,
                      clr);
}

void DrawBlockedSignal(const int direction,
                       const datetime signalTime,
                       const double signalHigh,
                       const double signalLow,
                       const string signalLabel,
                       const string reason)
{
   string side = direction > 0 ? "BUY" : "SELL";
   string stamp = IntegerToString((int)signalTime) + "_" + side + "_" + reason;
   double pad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 30.0, MathAbs(signalHigh - signalLow) * 0.45);
   double arrowPrice = direction > 0 ? signalLow - pad : signalHigh + pad;
   double textPrice = direction > 0 ? arrowPrice - pad * 0.55 : arrowPrice + pad * 0.55;
   color clr = direction > 0 ? C'92,174,255' : C'255,128,210';
   int arrowCode = direction > 0 ? 241 : 242;
   string arrowName = "BLOCKED_" + stamp + "_ARW";
   string textName = "BLOCKED_" + stamp + "_TXT";
   DrawHistoricalArrow(arrowName, signalTime, arrowPrice, arrowCode, clr);
   DrawHistoricalText(textName,
                      reason + " " + signalLabel + " signal",
                      signalTime + PeriodSeconds(_Period),
                      textPrice,
                      clr);
}

void DrawHistoricalText(const string name, const string text, const datetime t, const double price, const color clr)
{
   if(IsTesterMode())
      return;
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
   ObjectMove(0, obj, 0, t, price);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void DrawHistoricalSegment(const string name, const datetime t1, const datetime t2, const double price, const color clr, const ENUM_LINE_STYLE style)
{
   if(IsTesterMode() || price <= 0.0 || t2 <= t1)
      return;
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TREND, 0, t1, price, t2, price);
   ObjectMove(0, obj, 0, t1, price);
   ObjectMove(0, obj, 1, t2, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, obj, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

void DrawHistoricalWindowSignal(const int direction,
                                const datetime signalTime,
                                const double signalHigh,
                                const double signalLow)
{
   string side = direction > 0 ? "BUY" : "SELL";
   string base = "HIST_WINDOW_" + IntegerToString((long)signalTime) + "_" + side + "_";
   double pad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 20.0,
                        MathAbs(signalHigh - signalLow) * 0.35);
   double arrowPrice = direction > 0 ? signalLow - pad : signalHigh + pad;
   double labelPrice = direction > 0 ? arrowPrice - pad * 0.70 : arrowPrice + pad * 0.70;
   color windowColor = C'255,176,64';
   int arrowCode = direction > 0 ? 241 : 242;
   DrawHistoricalArrow(base + "ARW", signalTime, arrowPrice, arrowCode, windowColor);
   DrawHistoricalText(base + "TXT", "WINDOW " + side,
                      signalTime + PeriodSeconds(_Period), labelPrice, windowColor);
}

void DrawHistoricalSignal(const int idx,
                          const int direction,
                          const datetime signalTime,
                          const double signalHigh,
                          const double signalLow,
                          const double entry,
                          const double sl,
                          const double finalTp,
                          const double hcPrice,
                          const int finalLeg,
                          const int maxTp,
                          const string outcome,
                          const double pnlR,
                          const bool closed)
{
   string base = "HIST_" + IntegerToString(idx) + "_";
   double atrPad = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 20.0, MathAbs(signalHigh - signalLow) * 0.35);
   double arrowPrice = direction > 0 ? signalLow - atrPad : signalHigh + atrPad;
   double labelPrice = direction > 0 ? arrowPrice - atrPad * 0.75 : arrowPrice + atrPad * 0.75;
   color clr = NasOutcomeColor(pnlR, closed, outcome);
   int arrowCode = direction > 0 ? 233 : 234;
   string maxText = maxTp > 0 ? "TP" + IntegerToString(maxTp) : "none";
   string tpText = g_invertTradeModeRuntime
                   ? (EffectiveInvertTargetText() + " " + EffectiveInversionReferenceText() + " " + DoubleToString(finalTp, _Digits))
                   : ("TP " + TargetRText(NasTargetR(direction, entry, sl, finalTp)) + " " + DoubleToString(finalTp, _Digits));
   string txt = (direction > 0 ? "BUY" : "SELL") + " #" + IntegerToString(idx)
                + " " + (pnlR >= 0.0 ? "+" : "") + DoubleToString(pnlR, 2) + "R"
                + "\nE " + DoubleToString(entry, _Digits)
                + " SL " + DoubleToString(sl, _Digits)
                + "\n" + tpText
                + (hcPrice > 0.0 ? " HC " + DoubleToString(hcPrice, _Digits) : "")
                + "\nmax " + maxText + " | " + outcome;
   DrawHistoricalArrow(base + "ARW", signalTime, arrowPrice, arrowCode, clr);
   DrawHistoricalText(base + "TXT", txt, signalTime + PeriodSeconds(_Period) * 2, labelPrice, clr);

   datetime lineEnd = signalTime + PeriodSeconds(_Period) * 10;
   DrawHistoricalSegment(base + "ENTRY_SEG", signalTime, lineEnd, entry, clrWhite, STYLE_SOLID);
   DrawHistoricalSegment(base + "SL_SEG", signalTime, lineEnd, sl, C'255,80,110', STYLE_SOLID);
   DrawHistoricalSegment(base + "TP_SEG", signalTime, lineEnd, finalTp, C'80,255,180', STYLE_SOLID);
   if(hcPrice > 0.0)
      DrawHistoricalSegment(base + "HC_SEG", signalTime, lineEnd, hcPrice, C'255,204,82', STYLE_DOT);
}
void DrawTextLabel(const string name, const string text, const double price, const color clr)
{
   if(IsTesterMode())
      return;
   string obj = PREFIX + name;
   datetime t = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * 8;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
   ObjectMove(0, obj, 0, t, price);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
}

void DrawTradeLevels(const int direction)
{
   g_liveLevelObjectsActive = true;
   DrawHLine("ENTRY", g_lastEntry, clrWhite, STYLE_SOLID, 2);
   datetime liveLevelStart = g_lastSignalTime > 0 ? g_lastSignalTime : iTime(_Symbol, _Period, 0);
   datetime liveLevelEnd = liveLevelStart + PeriodSeconds(_Period) * 10;
   DrawHistoricalSegment("ENTRY_SEG", liveLevelStart, liveLevelEnd, g_lastEntry, clrWhite, STYLE_SOLID);
   DrawHLine("SL", g_lastSl, clrRed, STYLE_SOLID, 2);
   string d = direction > 0 ? "BUY" : "SELL";
   DrawTextLabel("ENTRY_TXT", d + " ENTRY " + DoubleToString(g_lastEntry, _Digits), g_lastEntry, clrWhite);
   DrawTextLabel("SL_TXT", "SL " + DoubleToString(g_lastSl, _Digits), g_lastSl, clrRed);

   if(UseSingleOrderTpMode())
   {
      int finalLeg = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? 6 : LegacyLegForTargetR(g_invertTradeModeRuntime ? EffectiveInversionReferenceR() : SelectedTargetR());
      double finalTp = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? g_lastTp3 : CurrentSelectedFinalTp(direction);
      DrawHLine("TP_SELECTED", finalTp, clrLime, STYLE_DASH, 2);
      double actualTargetR = NasTargetR(direction, g_lastEntry, g_lastSl, finalTp);
      string tpLabel = g_invertTradeModeRuntime
                       ? (EffectiveInvertTargetText() + " " + EffectiveInversionReferenceText()
                          + " +" + DoubleToString(actualTargetR, 2) + "R " + NasRiskRewardText(actualTargetR)
                          + " " + DoubleToString(finalTp, _Digits))
                       : ("TP " + TargetRText(actualTargetR)
                          + " +" + DoubleToString(actualTargetR, 2) + "R " + NasRiskRewardText(actualTargetR)
                          + " " + DoubleToString(finalTp, _Digits));
      DrawTextLabel("TP_SELECTED_TXT", tpLabel, finalTp, clrLime);
      double hc = 0.0;
      string hcLabel = "";
      if(g_invertTradeModeRuntime)
      {
         hc = InvertHcBePrice(direction, g_lastEntry, finalTp);
         if(hc > 0.0)
            hcLabel = "INV HC->BE " + IntegerToString(g_invertHcBeProgressPctRuntime) + "% " + DoubleToString(hc, _Digits);
      }
      else if(EffectiveHcBeLeg() > 0 && RMultipleForLeg(EffectiveHcBeLeg()) < actualTargetR - 0.0001)
      {
         hc = CurrentFinalTpForLeg(direction, EffectiveHcBeLeg());
         hcLabel = "HC->BE TP" + IntegerToString(EffectiveHcBeLeg()) + " " + DoubleToString(hc, _Digits);
      }
      if(hc > 0.0)
      {
         DrawHLine("HCBE", hc, clrOrange, STYLE_DOT, 2);
         DrawTextLabel("HCBE_TXT", hcLabel, hc, clrOrange);
      }
      else
      {
         ObjectDelete(0, PREFIX + "HCBE");
         ObjectDelete(0, PREFIX + "HCBE_TXT");
      }
      ObjectDelete(0, PREFIX + "TP1"); ObjectDelete(0, PREFIX + "TP2"); ObjectDelete(0, PREFIX + "TP3");
      ObjectDelete(0, PREFIX + "TP4"); ObjectDelete(0, PREFIX + "TP5"); ObjectDelete(0, PREFIX + "TP6");
      ObjectDelete(0, PREFIX + "TP1_TXT"); ObjectDelete(0, PREFIX + "TP2_TXT"); ObjectDelete(0, PREFIX + "TP3_TXT");
      ObjectDelete(0, PREFIX + "TP4_TXT"); ObjectDelete(0, PREFIX + "TP5_TXT"); ObjectDelete(0, PREFIX + "TP6_TXT");
      return;
   }

   DrawHLine("TP1", g_lastTp1, clrLime, STYLE_DASH, 1);
   DrawHLine("TP2", g_lastTp2, clrLime, STYLE_DASH, 1);
   DrawHLine("TP3", g_lastTp3, clrLime, STYLE_DASH, 2);
   DrawTextLabel("TP1_TXT", "TP1 " + DoubleToString(g_lastTp1, _Digits), g_lastTp1, clrLime);
   DrawTextLabel("TP2_TXT", "TP2 " + DoubleToString(g_lastTp2, _Digits), g_lastTp2, clrLime);
   DrawTextLabel("TP3_TXT", "TP3 " + DoubleToString(g_lastTp3, _Digits), g_lastTp3, clrLime);
   ObjectDelete(0, PREFIX + "TP_SELECTED");
   ObjectDelete(0, PREFIX + "TP_SELECTED_TXT");
   ObjectDelete(0, PREFIX + "HCBE");
   ObjectDelete(0, PREFIX + "HCBE_TXT");
}

double UiClamp(const double v, const double lo, const double hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

int UiClampInt(const int v, const int lo, const int hi)
{
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
}

string UiPctText(const double pct)
{
   return IntegerToString((int)MathRound(UiClamp(pct, 0.0, 100.0))) + "%";
}

string UiShort(const string text, const int maxLen)
{
   if(StringLen(text) <= maxLen)
      return text;
   return StringSubstr(text, 0, MathMax(0, maxLen - 3)) + "...";
}

double UiLivePrice(const int direction)
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
   {
      if(direction > 0 && tick.bid > 0.0)
         return tick.bid;
      if(direction < 0 && tick.ask > 0.0)
         return tick.ask;
      if(tick.last > 0.0)
         return tick.last;
   }
   return direction > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
}

void CreateRect(const string name, const int x, const int y, const int w, const int h, const color bg, const color border)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, (int)MathMax(1, w));
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, (int)MathMax(1, h));
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, border);
}

void CreateProgressBar(const string name,
                       const int x,
                       const int y,
                       const int w,
                       const int h,
                       const double pct,
                       const string text,
                       const color fill,
                       const color bg,
                       const color border)
{
   double clamped = UiClamp(pct, 0.0, 100.0);
   int fillW = UiClampInt((int)MathRound((double)w * clamped / 100.0), 1, w);
   CreateRect(name + "_BG", x, y, w, h, bg, border);
   CreateRect(name + "_FILL", x + 2, y + 2, MathMax(1, fillW - 4), MathMax(1, h - 4), fill, fill);
   CreateLabel(name + "_TXT", x + 10, y + 3, text, clrWhite, 8);
}

bool BuildNasVisualMetrics(NasVisualMetrics &m)
{
   m.ok = false;
   m.price = 0.0;
   m.superTrend = 0.0;
   m.sma13 = 0.0;
   m.buyPct = 0.0;
   m.sellPct = 0.0;
   m.buyArmed = false;
   m.sellArmed = false;
   m.status = "NAS SENSOR OFFLINE";

   MqlRates rates[];
   int bars = MathMax(300, MathMin(SignalBarsToCopy(), 800));
   int copied = LoadNasRates(rates, bars, true);
   if(copied < 20)
      return false;

   NasPoint p[];
   NAS_Calculate(rates, copied, BuildNasSettings(), p);
   int i = copied - 1;
   int prev = i - 1;
   if(i <= 0 || !NAS_IsValid(p[i].superTrend) || !NAS_IsValid(p[i].sma13) || !NAS_IsValid(p[prev].superTrend))
      return false;

   double price = rates[i].close;
   double st = p[i].superTrend;
   double sma13 = p[i].sma13;
   double prevClose = rates[prev].close;
   double prevSt = p[prev].superTrend;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double barRange = MathMax(rates[i].high - rates[i].low, point * 250.0);
   double scale = MathMax(barRange, MathMax(MathAbs(price - st), MathAbs(price - sma13)));
   if(scale <= 0.0)
      scale = point > 0.0 ? point * 250.0 : 1.0;

   double buySt = price >= st ? 100.0 : 100.0 - ((st - price) / scale) * 100.0;
   double buySma = price >= sma13 ? 100.0 : 100.0 - ((sma13 - price) / scale) * 100.0;
   double sellSt = price <= st ? 100.0 : 100.0 - ((price - st) / scale) * 100.0;
   double sellSma = price <= sma13 ? 100.0 : 100.0 - ((price - sma13) / scale) * 100.0;

   m.buyArmed = prevClose <= prevSt;
   m.sellArmed = prevClose >= prevSt;
   m.buyPct = UiClamp((UiClamp(buySt, 0.0, 100.0) * 0.65) + (UiClamp(buySma, 0.0, 100.0) * 0.35), 0.0, 100.0);
   m.sellPct = UiClamp((UiClamp(sellSt, 0.0, 100.0) * 0.65) + (UiClamp(sellSma, 0.0, 100.0) * 0.35), 0.0, 100.0);

   if(!m.buyArmed && !p[i].buy)
      m.buyPct *= 0.55;
   if(!m.sellArmed && !p[i].sell)
      m.sellPct *= 0.55;

   if(p[i].buy)
      m.buyPct = 100.0;
   if(p[i].sell)
      m.sellPct = 100.0;

   m.ok = true;
   m.price = price;
   m.superTrend = st;
   m.sma13 = sma13;
   if(p[i].buy)
      m.status = "BUY IGNITION";
   else if(p[i].sell)
      m.status = "SELL IGNITION";
   else if(m.buyPct > m.sellPct)
      m.status = m.buyArmed ? "BUY VECTOR ARMED" : "BUY VECTOR WATCH";
   else
      m.status = m.sellArmed ? "SELL VECTOR ARMED" : "SELL VECTOR WATCH";
   return true;
}

bool GetNasVisualMetrics(NasVisualMetrics &m)
{
   uint nowMs = GetTickCount();
   if(g_visualMetricsCache.ok && (nowMs - g_visualMetricsCacheMs) < 250)
   {
      m = g_visualMetricsCache;
      return true;
   }

   bool ok = BuildNasVisualMetrics(m);
   if(ok)
   {
      g_visualMetricsCache = m;
      g_visualMetricsCacheMs = nowMs;
   }
   return ok;
}

bool BuildTradeProgress(double &pct, string &label, color &fill)
{
   pct = 0.0;
   label = "NO LIVE TRADE VECTOR";
   fill = C'66,155,255';

   double totalVolume = 0.0;
   double weightedEntry = 0.0;
   double openPnl = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   int direction = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManagedPosition())
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      int posDir = type == POSITION_TYPE_BUY ? 1 : -1;
      if(direction == 0)
         direction = posDir;
      if(direction != posDir)
         continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSl = PositionGetDouble(POSITION_SL);
      double posTp = PositionGetDouble(POSITION_TP);
      totalVolume += vol;
      weightedEntry += entry * vol;
      openPnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(posSl > 0.0)
         sl = posSl;
      if(posTp > 0.0)
      {
         if(tp <= 0.0)
            tp = posTp;
         else if(direction > 0)
            tp = MathMax(tp, posTp);
         else
            tp = MathMin(tp, posTp);
      }
   }

   if(totalVolume <= 0.0 || direction == 0)
      return false;

   double entryAvg = weightedEntry / totalVolume;
   if(sl <= 0.0)
      sl = g_lastSl;
   if(tp <= 0.0)
      tp = g_lastTp3;
   double px = UiLivePrice(direction);
   if(px <= 0.0 || sl <= 0.0 || tp <= 0.0 || MathAbs(tp - sl) <= 0.0)
      return false;

   if(direction > 0)
      pct = ((px - sl) / (tp - sl)) * 100.0;
   else
      pct = ((sl - px) / (sl - tp)) * 100.0;
   pct = UiClamp(pct, 0.0, 100.0);

   string dirText = direction > 0 ? "BUY" : "SELL";
   fill = direction > 0 ? C'31,141,255' : C'225,49,76';
   label = "LIVE VECTOR " + dirText
           + " Px " + DoubleToString(px, _Digits)
           + " -> TP " + UiPctText(pct)
           + " | PnL " + DoubleToString(openPnl, 2)
           + " | Entry " + DoubleToString(entryAvg, _Digits);
   return true;
}

void CreateLabel(const string name, const int x, const int y, const string text, const color clr, const int size = 9)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 1);
}

void CreateEdit(const string name, const int x, const int y, const int w, const int h, const string text)
{
   string obj = PREFIX + name;
   bool created = false;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
      created = true;
   }
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   if(created)
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'35,43,58');
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C'90,178,255');
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void CreateButton(const string name, const int x, const int y, const int w, const int h, const string text, const color bg)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, obj, OBJPROP_ZORDER, 20);
}

void DeleteObjectIfExists(const string name)
{
   ObjectDelete(0, PREFIX + name);
}

void DeleteProgressBar(const string name)
{
   DeleteObjectIfExists(name + "_BG");
   DeleteObjectIfExists(name + "_FILL");
   DeleteObjectIfExists(name + "_TXT");
}

void ClearDashboardObjects()
{
   string names[] =
   {
      "DASH_BG", "DASH_HULL", "DASH_CORE", "DASH_ACTION_PANEL", "DASH_LOG_PANEL",
      "DASH_DOOR_L", "DASH_DOOR_R", "DASH_DOOR_TEXT",
      "DASH_DOCK_BG", "DASH_DOCK_STRIPE", "DASH_DOCK_TEXT", "DASH_DOCK_HINT",
      "DASH_COLLAPSED_HINT",
      "BTN_DASH_EXPAND", "BTN_DASH_COLLAPSE", "BTN_NAS_REGIME_FILTER", "BTN_WINDOW_REVERSE",
      "BTN_VOLUME_FILTER", "BTN_VOLUME_APPLY", "BTN_TIMED_EXIT_APPLY",
      "BTN_MACRO_REG_0", "BTN_MACRO_REG_1", "BTN_MACRO_REG_2", "BTN_MACRO_REG_3", "BTN_MACRO_REG_4", "BTN_MACRO_REG_5",
      "DASH_TITLE", "DASH_SUB", "DASH_1", "DASH_PRICE", "DASH_2", "DASH_3", "DASH_4", "DASH_5",
      "DASH_SENSOR", "DASH_SENSOR_HELP", "DASH_REGIME", "DASH_WIN", "DASH_WIN_STATE",
      "DASH_ACTIONS", "DASH_ACTION_HINT", "DASH_START_LBL", "DASH_END_LBL", "DASH_LOT_LBL",
      "DASH_SPREAD_MAX_LBL", "DASH_FINAL_SCALE_LBL", "DASH_ATR_BUFFER_LBL", "DASH_DAY_PROFIT_LBL", "DASH_DAY_LOSS_LBL", "DASH_VOL_MULT_LBL", "DASH_TIMED_EXIT_LBL", "DASH_TIMED_EXIT_STATE", "DASH_CFG_NOTE", "DASH_TP_CFG", "DASH_RISK_MODE", "DASH_AUDIT_PANEL", "DASH_AUDIT_TITLE", "DASH_AUDIT_SUMMARY", "DASH_AUDIT_DETAIL", "DASH_WD_MON", "DASH_WD_TUE", "DASH_WD_WED", "DASH_WD_THU", "DASH_WD_FRI", "DASH_AUDIT_R0", "DASH_AUDIT_R1", "DASH_AUDIT_R2", "DASH_AUDIT_R3", "DASH_AUDIT_R4", "DASH_AUDIT_R5", "DASH_AUDIT_R6", "DASH_H0", "DASH_H1", "DASH_H2", "DASH_H3",
      "BTN_CLOSE_ALL", "BTN_CLOSE_1_3", "BTN_BE", "BTN_APPLY_WINDOW", "BTN_FINAL_SCALE_APPLY", "BTN_EA_TOGGLE", "BTN_AUDIT_WIN", "BTN_NAS_BRIDGE_PUB", "BTN_NAS_BRIDGE_ONLY", "BTN_NAS_BRIDGE_NATIVE", "BTN_NAS_PRO_AUDIT", "BTN_ACCEPT_FILTER", "BTN_TP_MODE", "BTN_TP_LEG", "BTN_HCBE", "BTN_INV_TP", "BTN_INVERT", "BTN_FTMO", "BTN_RISKLOT", "BTN_RISK_GEOM", "BTN_ATRBUF_0", "BTN_ATRBUF_20", "BTN_ATRBUF_40", "BTN_ATRBUF_60", "BTN_ATRBUF_80", "BTN_ATRBUF_100", "BTN_ATRBUF_APPLY",
      "EDIT_START", "EDIT_END", "EDIT_LOT", "EDIT_RISK_PCT", "BTN_RISK_PCT_APPLY", "DASH_RISK_PCT_LBL", "EDIT_SPREAD_MAX", "EDIT_FINAL_SCALE", "EDIT_ATR_BUFFER", "EDIT_PIP_SL", "BTN_PIP_APPLY", "DASH_PIP_SL_LBL", "EDIT_DAY_PROFIT", "EDIT_DAY_LOSS", "BTN_DAY_GUARD_APPLY", "EDIT_VOL_MULT", "EDIT_TIMED_EXIT"
   };
   for(int i = 0; i < ArraySize(names); i++)
      DeleteObjectIfExists(names[i]);
   DeleteProgressBar("TRADE_VECTOR");
   DeleteProgressBar("BUY_FUEL");
   DeleteProgressBar("SELL_FUEL");
   DeleteProgressBar("AUDIT_SCAN");
}

void DrawCollapsedDashboardToggle()
{
   CreateRect("DASH_DOCK_BG", 10, 18, 940, 34, C'54,62,75', C'134,158,182');
   CreateRect("DASH_DOCK_STRIPE", 18, 25, 924, 4, C'90,178,255', C'90,178,255');
   CreateLabel("DASH_DOCK_TEXT", 28, 33, "NAS STARSHIP COCKPIT DOCKED", C'216,222,230', 9);
   CreateButton("BTN_DASH_EXPAND", 438, 58, 110, 24, "v EXPAND", C'38,101,176');
   CreateLabel("DASH_DOCK_HINT", 560, 62, "chart view clear", C'184,196,210', 8);
}

void SetDashboardCollapsed(const bool collapsed)
{
   ClearDashboardObjects();
   if(collapsed)
   {
      g_dashboardCollapsed = true;
      g_dashboardOpening = false;
      g_dashboardDoorFinished = true;
      g_dashboardDoorStartMs = 0;
      DrawCollapsedDashboardToggle();
   }
   else
   {
      g_dashboardCollapsed = false;
      g_dashboardOpening = false;
      g_dashboardDoorFinished = true;
      g_dashboardDoorStartMs = 0;
      g_dashboardForceNextUpdate = true;
      EventSetMillisecondTimer(250);
      DrawDashboard();
      RequestHistoryRefresh();
   }
   ChartRedraw(0);
}

void CreateButtons()
{
   CreateButton("BTN_DASH_COLLAPSE", 1024, 30, 24, 22, "^", C'90,178,255');
   CreateButton("BTN_EA_TOGGLE", 684, 58, 244, 24,
                g_eaEnabledRuntime ? "EA ON - CLICK TO KILL" : "EA OFF - CLICK TO ARM",
                g_eaEnabledRuntime ? C'30,150,95' : C'178,37,57');
   CreateButton("BTN_CLOSE_ALL", 684, 82, 118, 25, "CLOSE ALL", C'178,37,57');
   CreateButton("BTN_CLOSE_1_3", 810, 82, 118, 25,
                InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? "CLOSE ONE" : "CLOSE 1/3",
                C'38,101,176');
   if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
      CreateButton("BTN_BE", 684, 112, 118, 25, "SL -> BE", C'34,136,160');
   CreateButton("BTN_NAS_REGIME_FILTER", 810, 112, 118, 25,
                g_nasRegimeWarmupPending ? "REGIME LOAD" : (g_nasRegimeFilterRuntime ? "REGIME ON" : "REGIME OFF"),
                g_nasRegimeWarmupPending ? C'184,103,22' : (g_nasRegimeFilterRuntime ? C'30,150,95' : C'90,90,110'));
   CreateButton("BTN_WINDOW_REVERSE", 936, 112, 102, 25,
                g_windowReverseExitRuntime ? "WIN REV ON" : "WIN REV OFF",
                g_windowReverseExitRuntime ? C'178,78,42' : C'90,90,110');
   CreateButton("BTN_APPLY_WINDOW", 836, 220, 92, 24, "APPLY WIN", C'38,101,176');
   CreateButton("BTN_FINAL_SCALE_APPLY", 936, 220, 70, 24, "APPLY", C'38,101,176');
   CreateButton("BTN_AUDIT_WIN", 684, 250, 118, 24, NasAuditWindowLabel() + " WINDOW", C'38,101,176');
   CreateButton("BTN_ACCEPT_FILTER", 936, 250, 102, 24, g_historyUseAcceptedFilterRuntime ? "DUP OFF" : "DUP ON", g_historyUseAcceptedFilterRuntime ? C'90,90,110' : C'30,150,95');
   CreateButton("BTN_TP_MODE", 810, 250, 118, 24, TpModeText(), g_tpManagementModeRuntime == NAS_TP_FIXED_SELECTED_LEG ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_TP_LEG", 684, 278, 118, 24, EffectiveTpSelectorText(), C'38,101,176');
   CreateButton("BTN_HCBE", 810, 278, 118, 24, EffectiveHcBeText(), AnyHcBeEnabled() ? C'34,136,160' : C'90,90,110');
   CreateButton("BTN_INV_TP", 936, 278, 102, 24, g_invertTradeModeRuntime ? EffectiveInvertTargetText() : "INV TP --", g_invertTradeModeRuntime ? C'38,101,176' : C'90,90,110');
   CreateButton("BTN_INVERT", 936, 306, 102, 24, g_invertTradeModeRuntime ? "INVERT ON" : "INVERT OFF", g_invertTradeModeRuntime ? C'178,37,57' : C'90,90,110');
   CreateButton("BTN_FTMO", 684, 306, 118, 24, g_ftmoModeRuntime ? "FTMO ON" : "FTMO OFF", g_ftmoModeRuntime ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_RISKLOT", 810, 306, 118, 24, g_riskLotOnlyRuntime ? "RISKLOT ON" : "RISKLOT OFF", g_riskLotOnlyRuntime ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_RISK_GEOM", 684, 334, 112, 22, "SL " + RiskGeometryModeText(), g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_NORMAL ? C'90,90,110' : C'30,150,95');
   CreateButton("BTN_ATRBUF_0", 802, 334, 30, 22, "0", MathAbs(g_swingBufferAtrRuntime) < 0.001 ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_ATRBUF_20", 836, 334, 36, 22, "20", MathAbs(g_swingBufferAtrRuntime - 0.20) < 0.001 ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_ATRBUF_40", 876, 334, 36, 22, "40", MathAbs(g_swingBufferAtrRuntime - 0.40) < 0.001 ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_ATRBUF_60", 916, 334, 36, 22, "60", MathAbs(g_swingBufferAtrRuntime - 0.60) < 0.001 ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_ATRBUF_80", 956, 334, 36, 22, "80", MathAbs(g_swingBufferAtrRuntime - 0.80) < 0.001 ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_ATRBUF_100", 996, 334, 42, 22, "100", MathAbs(g_swingBufferAtrRuntime - 1.00) < 0.001 ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_NAS_BRIDGE_PUB", 684, 360, 82, 22, g_nasBridgeEnabledRuntime ? "PUB ON" : "PUB OFF", g_nasBridgeEnabledRuntime ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_NAS_BRIDGE_ONLY", 772, 360, 82, 22, g_nasBridgeOnlyRuntime ? "ONLY ON" : "ONLY OFF", g_nasBridgeOnlyRuntime ? C'120,88,25' : C'90,90,110');
   CreateButton("BTN_NAS_BRIDGE_NATIVE", 860, 360, 82, 22, g_nasNativeWithBridgeOnlyRuntime ? "NAT ON" : "NAT OFF", g_nasNativeWithBridgeOnlyRuntime ? C'184,103,22' : C'90,90,110');
   CreateButton("BTN_NAS_PRO_AUDIT", 948, 360, 90, 22, g_nasProAuditRuntime ? "AUDIT ON" : "AUDIT OFF", g_nasProAuditRuntime ? C'30,150,95' : C'90,90,110');
   bool dayAppliedFeedback = (int)(g_dailyGuardApplyFeedbackUntilMs - GetTickCount()) > 0;
   CreateButton("BTN_DAY_GUARD_APPLY", 846, 402, 92, 22,
                dayAppliedFeedback ? "APPLIED" : "APPLY DAY",
                dayAppliedFeedback ? C'30,150,95' : C'38,101,176');
   bool volumeAppliedFeedback = (int)(g_volumeApplyFeedbackUntilMs - GetTickCount()) > 0;
   CreateButton("BTN_VOLUME_FILTER", 684, 430, 82, 22,
                g_volumeFilterRuntime ? "VOL ON" : "VOL OFF",
                g_volumeFilterRuntime ? C'30,150,95' : C'90,90,110');
   CreateButton("BTN_VOLUME_APPLY", 870, 430, 84, 22,
                volumeAppliedFeedback ? "APPLIED" : "APPLY VOL",
                volumeAppliedFeedback ? C'30,150,95' : C'38,101,176');
   bool timedExitAppliedFeedback = (int)(g_timedExitApplyFeedbackUntilMs - GetTickCount()) > 0;
   CreateButton("BTN_TIMED_EXIT_APPLY", 826, 458, 92, 22,
                timedExitAppliedFeedback ? "APPLIED" : "APPLY HOLD",
                timedExitAppliedFeedback ? C'30,150,95' : C'38,101,176');
   int currentMacro = LiqMacroRegimeBucket(g_regimeV3);
   for(int ri = 0; ri < LIQ_MACRO_REGIME_COUNT; ++ri)
   {
      int col = ri % 3;
      int row = ri / 3;
      color bg = !g_macroRegimeAllowed[ri] ? C'58,62,72' : (ri == currentMacro ? C'38,101,176' : C'30,130,85');
      CreateButton("BTN_MACRO_REG_" + IntegerToString(ri), 38 + col * 200, 316 + row * 24, 190, 21,
                   LiqMacroRegimeStatsText(ri) + (g_macroRegimeAllowed[ri] ? "" : " BLOCK"), bg);
   }
}

bool ApplyTradingWindowFromDashboard(const string source)
{
   string startObj = PREFIX + "EDIT_START";
   string endObj = PREFIX + "EDIT_END";
   if(ObjectFind(0, startObj) < 0 || ObjectFind(0, endObj) < 0)
   {
      Print("NAS SATS EA trading window apply failed missing edit objects source=", source);
      return false;
   }

   string startText = ObjectGetString(0, startObj, OBJPROP_TEXT);
   string endText = ObjectGetString(0, endObj, OBJPROP_TEXT);
   StringTrimLeft(startText);
   StringTrimRight(startText);
   StringTrimLeft(endText);
   StringTrimRight(endText);

      if(startText == "" && endText == "")
   {
      startText = "00:00";
      endText = "00:00";
   }

   int startMin = ParseClockMinutes(startText, -1);
   int endMin = ParseClockMinutes(endText, -1);
   if(startMin < 0 || endMin < 0)
   {
      Print("NAS SATS EA trading window apply failed invalid time source=", source,
            " start=", startText,
            " end=", endText);
      return false;
   }

   g_tradeStartTimeRuntime = startText;
   g_tradeEndTimeRuntime = endText;
   ObjectSetString(0, startObj, OBJPROP_TEXT, g_tradeStartTimeRuntime);
   ObjectSetString(0, endObj, OBJPROP_TEXT, g_tradeEndTimeRuntime);
   Print("NAS SATS EA trading window updated source=", source,
         " start=", g_tradeStartTimeRuntime,
         " end=", g_tradeEndTimeRuntime,
         " state=", TradingTimeStateText());
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplyLotFromDashboard(const string source)
{
   string lotObj = PREFIX + "EDIT_LOT";
   if(ObjectFind(0, lotObj) < 0)
   {
      Print("NAS SATS EA lot apply failed missing edit object source=", source);
      return false;
   }

   string lotText = ObjectGetString(0, lotObj, OBJPROP_TEXT);
   StringTrimLeft(lotText);
   StringTrimRight(lotText);
   double requested = StringToDouble(lotText);
   if(requested <= 0.0)
   {
      Print("NAS SATS EA lot apply failed invalid lot source=", source, " lot=", lotText);
      return false;
   }

   double normalized = NormalizeVolume(requested);
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      g_fixedLotRuntime = normalized;
   else
      g_totalLotRuntime = normalized;

   ObjectSetString(0, lotObj, OBJPROP_TEXT, DoubleToString(normalized, 2));
   Print("NAS SATS EA lot updated source=", source,
         " mode=", EnumToString(InpExecutionMode),
         " lot=", DoubleToString(normalized, 8));
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplySpreadMaxFromDashboard(const string source)
{
   string spreadObj = PREFIX + "EDIT_SPREAD_MAX";
   if(ObjectFind(0, spreadObj) < 0)
   {
      Print("NAS SATS EA spread max apply failed missing edit object source=", source);
      return false;
   }

   string spreadText = ObjectGetString(0, spreadObj, OBJPROP_TEXT);
   StringTrimLeft(spreadText);
   StringTrimRight(spreadText);
   double requested = StringToDouble(spreadText);
   if(requested < 0.0)
   {
      Print("NAS SATS EA spread max apply failed invalid value source=", source, " max_spread_pts=", spreadText);
      return false;
   }

   g_spreadMaxPointsRuntime = requested;
   ArrayFree(g_historySimCache);
   ObjectSetString(0, spreadObj, OBJPROP_TEXT, DoubleToString(g_spreadMaxPointsRuntime, 0));
   Print("NAS SATS EA spread max updated source=", source,
         " max_spread_pts=", DoubleToString(g_spreadMaxPointsRuntime, 1),
         " note=", (g_spreadMaxPointsRuntime > 0.0 ? "manual_wide_threshold" : "spread_blocking_off"));
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplyFinalRiskScaleFromDashboard(const string source)
{
   string scaleObj = PREFIX + "EDIT_FINAL_SCALE";
   if(ObjectFind(0, scaleObj) < 0)
   {
      Print("NAS SATS EA final risk scale apply failed missing edit object source=", source);
      return false;
   }

   string scaleText = ObjectGetString(0, scaleObj, OBJPROP_TEXT);
   StringTrimLeft(scaleText);
   StringTrimRight(scaleText);
   double requested = StringToDouble(scaleText);
   if(requested <= 0.0)
   {
      Print("NAS SATS EA final risk scale apply failed invalid value source=", source, " scale_pct=", scaleText);
      return false;
   }

   g_finalRiskScalePctRuntime = MathMax(10.0, MathMin(500.0, requested));
   ObjectSetString(0, scaleObj, OBJPROP_TEXT, DoubleToString(g_finalRiskScalePctRuntime, 0));
   Print("NAS SATS EA final risk scale updated source=", source,
         " final_scale_pct=", DoubleToString(g_finalRiskScalePctRuntime, 2),
         " note=100_keeps_raw_sl_75_trims_distance_by_25pct_max500");
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool SetAtrBufferPct(const double pct, const string source)
{
   double clampedPct = MathMax(0.0, MathMin(300.0, pct));
   g_swingBufferAtrRuntime = clampedPct / 100.0;
   string atrObj = PREFIX + "EDIT_ATR_BUFFER";
   if(ObjectFind(0, atrObj) >= 0)
      ObjectSetString(0, atrObj, OBJPROP_TEXT, DoubleToString(clampedPct, 0));
   Print("NAS SATS EA ATR buffer updated source=", source,
         " swing_buffer_pct=", DoubleToString(clampedPct, 1),
         " swing_buffer_atr=", DoubleToString(g_swingBufferAtrRuntime, 4),
         " note=affects_sl_buffer_only_signal_math_unchanged");
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplyAtrBufferFromDashboard(const string source)
{
   string atrObj = PREFIX + "EDIT_ATR_BUFFER";
   if(ObjectFind(0, atrObj) < 0)
   {
      Print("NAS SATS EA ATR buffer apply failed missing edit object source=", source);
      return false;
   }

   string atrText = ObjectGetString(0, atrObj, OBJPROP_TEXT);
   StringTrimLeft(atrText);
   StringTrimRight(atrText);
   double requested = StringToDouble(atrText);
   if(requested < 0.0)
   {
      Print("NAS SATS EA ATR buffer apply failed invalid value source=", source, " atr_buffer=", atrText);
      return false;
   }

   double pct = requested;
   if(requested > 0.0 && requested <= 2.0 && StringFind(atrText, ".") >= 0)
      pct = requested * 100.0;
   return SetAtrBufferPct(pct, source);
}

bool ApplyRiskPctFromDashboard(const string source)
{
   string riskObj = PREFIX + "EDIT_RISK_PCT";
   if(ObjectFind(0, riskObj) < 0)
   {
      Print("NAS SATS EA risk pct apply failed missing edit object source=", source);
      return false;
   }

   string riskText = ObjectGetString(0, riskObj, OBJPROP_TEXT);
   StringTrimLeft(riskText);
   StringTrimRight(riskText);
   double requested = StringToDouble(riskText);
   if(requested <= 0.0 || requested > 100.0)
   {
      Print("NAS SATS EA risk pct apply failed invalid value source=", source, " risk_pct=", riskText);
      return false;
   }

   g_accountRiskPerTradePctRuntime = requested;
   if(!PersistNasRiskPctRuntime())
   {
      Print("NAS SATS EA risk pct apply failed persistence error source=", source,
            " risk_pct=", DoubleToString(g_accountRiskPerTradePctRuntime, 3),
            " err=", GetLastError());
      return false;
   }
   AccountRiskCacheInvalidate();
   if(g_nasBridgeEnabledRuntime)
      NasProBridgeWriteInitMarker();
   g_riskPctApplyFeedbackUntilMs = GetTickCount() + 1200;
   g_dashboardForceNextUpdate = true;
   Print("NAS SATS EA risk pct applied source=", source, " risk_pct=", DoubleToString(g_accountRiskPerTradePctRuntime, 3));
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ParseDashboardPercent(string text, double &value)
{
   StringTrimLeft(text);
   StringTrimRight(text);
   if(text == "")
      return false;
   StringReplace(text, ",", ".");
   int dots = 0;
   for(int i = 0; i < StringLen(text); ++i)
   {
      ushort ch = StringGetCharacter(text, i);
      if(ch == '.')
      {
         dots++;
         if(dots > 1)
            return false;
      }
      else if(ch < '0' || ch > '9')
         return false;
   }
   value = StringToDouble(text);
   return MathIsValidNumber(value) && value >= 0.0 && value <= 100.0;
}

bool ApplyDailyGuardFromDashboard(const string source)
{
   string profitObj = PREFIX + "EDIT_DAY_PROFIT";
   string lossObj = PREFIX + "EDIT_DAY_LOSS";
   if(ObjectFind(0, profitObj) < 0 || ObjectFind(0, lossObj) < 0)
   {
      Print("NAS SATS EA daily guard apply failed missing edit objects source=", source);
      return false;
   }

   double requestedProfit = 0.0;
   double requestedLoss = 0.0;
   string profitText = ObjectGetString(0, profitObj, OBJPROP_TEXT);
   string lossText = ObjectGetString(0, lossObj, OBJPROP_TEXT);
   if(!ParseDashboardPercent(profitText, requestedProfit)
      || !ParseDashboardPercent(lossText, requestedLoss))
   {
      Print("NAS SATS EA daily guard apply failed invalid percentage source=", source,
            " profit_pct=", profitText, " loss_pct=", lossText, " allowed=0..100");
      return false;
   }

   double oldProfit = g_dailyProfitTargetPctRuntime;
   double oldLoss = g_dailyMaxLossPctRuntime;
   g_dailyProfitTargetPctRuntime = requestedProfit;
   g_dailyMaxLossPctRuntime = requestedLoss;
   if(!PersistNasDailyGuardRuntime())
   {
      int persistError = GetLastError();
      g_dailyProfitTargetPctRuntime = oldProfit;
      g_dailyMaxLossPctRuntime = oldLoss;
      PersistNasDailyGuardRuntime();
      Print("NAS SATS EA daily guard apply failed persistence error source=", source,
            " err=", persistError);
      return false;
   }

   ObjectSetString(0, profitObj, OBJPROP_TEXT, DoubleToString(g_dailyProfitTargetPctRuntime, 2));
   ObjectSetString(0, lossObj, OBJPROP_TEXT, DoubleToString(g_dailyMaxLossPctRuntime, 2));
   g_dailyGuardApplyFeedbackUntilMs = GetTickCount() + 1200;
   g_dashboardForceNextUpdate = true;
   RequestHistoryRefresh();
   Print("NAS SATS EA daily guard applied source=", source,
         " profit_target_pct=", DoubleToString(g_dailyProfitTargetPctRuntime, 3),
         " max_loss_pct=", DoubleToString(g_dailyMaxLossPctRuntime, 3),
         " zero_means_off=true scope=account_magic_symbol_tf");
   EnforceDailyPnlGuard();
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

bool ApplyNasVolumeFromDashboard(const string source)
{
   string volumeObj = PREFIX + "EDIT_VOL_MULT";
   if(ObjectFind(0, volumeObj) < 0)
   {
      Print("NAS SATS EA volume multiplier apply failed missing edit object source=", source);
      return false;
   }

   string volumeText = ObjectGetString(0, volumeObj, OBJPROP_TEXT);
   StringTrimLeft(volumeText);
   StringTrimRight(volumeText);
   StringReplace(volumeText, ",", ".");
   double requested = StringToDouble(volumeText);
   if(!MathIsValidNumber(requested) || requested < 0.05 || requested > 20.0)
   {
      ObjectSetString(0, volumeObj, OBJPROP_TEXT, DoubleToString(g_volumeMultiplierRuntime, 2));
      g_lastExecutionStatus = "VOL INVALID";
      g_lastExecutionBlockReason = "volume_multiplier_allowed_0.05_to_20";
      Print("NAS SATS EA volume multiplier apply failed source=", source,
            " value=", volumeText, " allowed=0.05..20");
      UpdateDashboard();
      ChartRedraw(0);
      return false;
   }

   double oldMultiplier = g_volumeMultiplierRuntime;
   g_volumeMultiplierRuntime = ClampNasVolumeMultiplier(requested);
   if(!PersistNasVolumeRuntime())
   {
      int persistError = GetLastError();
      g_volumeMultiplierRuntime = oldMultiplier;
      PersistNasVolumeRuntime();
      ObjectSetString(0, volumeObj, OBJPROP_TEXT, DoubleToString(g_volumeMultiplierRuntime, 2));
      Print("NAS SATS EA volume multiplier apply failed persistence source=", source,
            " err=", persistError);
      return false;
   }

   ObjectSetString(0, volumeObj, OBJPROP_TEXT, DoubleToString(g_volumeMultiplierRuntime, 2));
   g_volumeApplyFeedbackUntilMs = GetTickCount() + 1200;
   g_lastExecutionStatus = "VOL APPLIED";
   g_lastExecutionBlockReason = "";
   ArrayFree(g_historySimCache);
   NasProAuditWrite("volume_multiplier_applied", "config", 0, 0.0, 0.0, 0.0, 0.0,
      "source=" + source + " multiplier=" + DoubleToString(g_volumeMultiplierRuntime, 4)
      + " enabled=" + (g_volumeFilterRuntime ? "1" : "0"));
   Print("NAS SATS EA volume multiplier applied source=", source,
         " multiplier=", DoubleToString(g_volumeMultiplierRuntime, 4),
         " filter=", (g_volumeFilterRuntime ? "ON" : "OFF"));
   RequestHistoryRefresh();
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

void ToggleNasVolumeFilter()
{
   bool oldEnabled = g_volumeFilterRuntime;
   g_volumeFilterRuntime = !g_volumeFilterRuntime;
   if(!PersistNasVolumeRuntime())
   {
      int persistError = GetLastError();
      g_volumeFilterRuntime = oldEnabled;
      PersistNasVolumeRuntime();
      Print("NAS SATS EA volume filter toggle failed persistence err=", persistError);
      return;
   }

   g_lastExecutionStatus = g_volumeFilterRuntime ? "VOL FILTER ON" : "VOL FILTER OFF";
   g_lastExecutionBlockReason = "";
   ArrayFree(g_historySimCache);
   NasProAuditWrite("volume_filter_toggled", "config", 0, 0.0, 0.0, 0.0, 0.0,
      "enabled=" + (g_volumeFilterRuntime ? "1" : "0")
      + " multiplier=" + DoubleToString(g_volumeMultiplierRuntime, 4));
   Print("NAS SATS EA volume filter toggled state=", (g_volumeFilterRuntime ? "ON" : "OFF"),
         " multiplier=", DoubleToString(g_volumeMultiplierRuntime, 4),
         " parity=signal_tick_volume_vs_previous_20_bar_average");
   RequestHistoryRefresh();
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
   ChartRedraw(0);
}

bool ApplyNasTimedExitFromDashboard(const string source)
{
   string exitObj = PREFIX + "EDIT_TIMED_EXIT";
   if(ObjectFind(0, exitObj) < 0)
   {
      Print("NAS SATS EA timed exit apply failed missing edit object source=", source);
      return false;
   }

   string requestedText = ObjectGetString(0, exitObj, OBJPROP_TEXT);
   string normalized = "";
   int minutes = -1;
   if(!NormalizeOptionalDuration(requestedText, normalized, minutes))
   {
      ObjectSetString(0, exitObj, OBJPROP_TEXT, g_timedExitTimeRuntime);
      g_lastExecutionStatus = "EXIT INVALID";
      g_lastExecutionBlockReason = "max_hold_requires_HH_MM_or_empty";
      Print("NAS SATS EA timed exit apply failed source=", source,
            " value=", requestedText, " required=HH:MM_duration_or_empty 00:00_is_invalid");
      UpdateDashboard();
      ChartRedraw(0);
      return false;
   }

   string oldExit = g_timedExitTimeRuntime;
   g_timedExitTimeRuntime = normalized;
   if(!PersistNasTimedExitRuntime())
   {
      int persistError = GetLastError();
      g_timedExitTimeRuntime = oldExit;
      PersistNasTimedExitRuntime();
      ObjectSetString(0, exitObj, OBJPROP_TEXT, g_timedExitTimeRuntime);
      Print("NAS SATS EA timed exit apply failed persistence source=", source,
            " err=", persistError);
      return false;
   }

   ObjectSetString(0, exitObj, OBJPROP_TEXT, g_timedExitTimeRuntime);
   ResetNasTimedExitCloseState();
   g_timedExitApplyFeedbackUntilMs = GetTickCount() + 1200;
   g_lastExecutionStatus = NasTimedExitConfigured() ? "HOLD APPLIED" : "HOLD OFF";
   g_lastExecutionBlockReason = "";
   ArrayFree(g_historySimCache);
   NasProAuditWrite("timed_exit_applied", "config", 0, 0.0, 0.0, 0.0, 0.0,
      "source=" + source + " duration=" + (NasTimedExitConfigured() ? g_timedExitTimeRuntime : "OFF")
      + " mode=elapsed_from_position_open");
   Print("NAS SATS EA timed exit applied source=", source,
         " duration=", (NasTimedExitConfigured() ? g_timedExitTimeRuntime : "OFF"),
         " minutes=", NasTimedExitMinutes(),
         " empty_disables=true mode=elapsed_from_position_open");
   RequestHistoryRefresh();
   g_dashboardForceNextUpdate = true;
   EnforceNasTimedExit();
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}

void ApplyDashboardSettings(const string source)
{
   ApplyTradingWindowFromDashboard(source);
   ApplyLotFromDashboard(source);
   ApplySpreadMaxFromDashboard(source);
   ApplyFinalRiskScaleFromDashboard(source);
   ApplyAtrBufferFromDashboard(source);
   ApplyRiskPctFromDashboard(source);
   ApplyDailyGuardFromDashboard(source);
   ApplyNasVolumeFromDashboard(source);
   ApplyNasTimedExitFromDashboard(source);
}

void RefreshRuntimeMagicAfterRiskModeChange()
{
   g_runtimeMagic = 0;
   trade.SetExpertMagicNumber(RuntimeMagic());
   AccountRiskCacheInvalidate();
}

void CycleAuditWindow()
{
   g_auditWeeksRuntime = NextAuditWeeks(g_auditWeeksRuntime);
   ArrayFree(g_historySimCache);
   Print("NAS SATS EA audit/history window changed weeks=", g_auditWeeksRuntime);
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}

void ToggleAcceptedSignalFilter()
{
   bool previous = g_historyUseAcceptedFilterRuntime;
   g_historyUseAcceptedFilterRuntime = !g_historyUseAcceptedFilterRuntime;
   ArrayFree(g_historySimCache);
   g_historyRefreshPending = false;
   g_historyRefreshDueMs = 0;
   Print("NAS SATS EA duplicate mode changed previous=", (previous ? "DUP_OFF" : "DUP_ON"),
         " mode=", (g_historyUseAcceptedFilterRuntime ? "DUP_OFF" : "DUP_ON"),
         " note=dup_on_allows_same_direction_signals_and_execution_dup_off_alternates_buy_sell immediate_redraw=true");
   g_historyAuditRows[0] = "Audit loading after duplicate-mode change...";
   g_historyAuditSummary = "Audit loading";
   g_historyAuditDetail = "deferred duplicate-mode replay";
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}
void ToggleNasMacroRegime(const int bucket)
{
   if(bucket < 0 || bucket >= LIQ_MACRO_REGIME_COUNT)
      return;
   g_macroRegimeAllowed[bucket] = !g_macroRegimeAllowed[bucket];
   g_lastExecutionStatus = g_macroRegimeAllowed[bucket]
      ? "REGIME ALLOWED " + LiqMacroRegimeShortName(bucket)
      : "REGIME BLOCKED " + LiqMacroRegimeShortName(bucket);
   ArrayFree(g_historySimCache);
   g_historyRefreshPending = false;
   g_historyRefreshDueMs = 0;
   Print("NAS SATS EA macro regime toggled bucket=", LiqMacroRegimeName(bucket),
         " allowed=", (g_macroRegimeAllowed[bucket] ? "true" : "false"),
         " mask=", LiqMacroRegimeMask(),
         " note=signal_math_unchanged_macro_allow_list_precedes_v3_rule");
   RequestHistoryRefresh();
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
   ChartRedraw(0);
}
void ToggleNasRegimeFilter()
{
   g_nasRegimeFilterRuntime = !g_nasRegimeFilterRuntime;
   if(g_nasRegimeFilterRuntime)
   {
      // Rebuild on the timer so the chart click is never blocked by the HTF timeline scan.
      g_nasRegimeWarmupPending = true;
      g_regimeV3LastSourceOpen = 0;
      g_regimeV3LastAttemptLocal = 0;
   }
   else
      g_nasRegimeWarmupPending = false;
   ArrayFree(g_historySimCache);
   g_historyRefreshPending = false;
   g_historyRefreshDueMs = 0;
   g_nasRegimeLastRule = g_nasRegimeFilterRuntime ? "WARMUP" : "OFF";
   g_nasRegimeLastDetail = g_nasRegimeFilterRuntime ? "ASYNC_H1H2_TIMELINE" : "filter_disabled";
   Print("NAS SATS EA regime filter toggled state=", (g_nasRegimeFilterRuntime ? "ON" : "OFF"),
         " rule=H1H2_NEUTRAL_ROTATION signal_math_unchanged=true fail_open=true");
   if(g_nasRegimeFilterRuntime)
   {
      g_historyAuditRows[0] = "Regime loading asynchronously...";
      g_historyAuditSummary = "Regime warmup";
      g_historyAuditDetail = "live execution is fail-open until ready";
   }
   else
   {
      g_historyAuditRows[0] = "Audit loading after regime-filter change...";
      g_historyAuditSummary = "Audit loading";
      g_historyAuditDetail = "deferred causal regime replay";
      RequestHistoryRefresh();
   }
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
   ChartRedraw(0);
}

void ToggleTpManagementMode()
{
   g_tpManagementModeRuntime = (g_tpManagementModeRuntime == NAS_TP_FIXED_SELECTED_LEG ? NAS_TP_LEGACY_THREE_LEG : NAS_TP_FIXED_SELECTED_LEG);
   Print("NAS SATS EA TP management mode changed mode=", TpModeText());
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}

void CycleSelectedTpLeg()
{
   if(g_invertTradeModeRuntime)
   {
      if(g_invertReferenceTpLegRuntime <= 0)
         g_invertReferenceTpLegRuntime = 1;
      else if(g_invertReferenceTpLegRuntime >= 6)
         g_invertReferenceTpLegRuntime = 0;
      else
         g_invertReferenceTpLegRuntime = ClampTpLeg(g_invertReferenceTpLegRuntime + 1);
      g_lastInvertedFinalTp = 0.0;
      ArrayFree(g_historySimCache);
      Print("NAS SATS EA invert reference TP leg changed inv_ref_tp=", g_invertReferenceTpLegRuntime,
            " invert_ref_mode=", EffectiveInversionReferenceText(),
            " note=signal_math_unchanged_normal_tp_selector_not_mutated");
   }
   else
   {
      g_selectedTargetRRuntime = NextTargetPresetR(SelectedTargetR());
      g_selectedTpLegRuntime = LegacyLegForTargetR(SelectedTargetR());
      if(g_hcBeTpLegRuntime > 0 && RMultipleForLeg(g_hcBeTpLegRuntime) >= SelectedTargetR() - 0.0001)
         g_hcBeTpLegRuntime = 0;
      g_tpManagementModeRuntime = NAS_TP_FIXED_SELECTED_LEG;
      Print("NAS SATS EA selected target changed target_r=", DoubleToString(SelectedTargetR(), 2),
            " legacy_ladder_leg=", g_selectedTpLegRuntime,
            " mode=", TpModeText(),
            " note=audit_native_bridge_and_live_geometry_use_exact_target_r");
   }
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}

void CycleHcBeLeg()
{
   if(g_invertTradeModeRuntime)
   {
      if(g_invertHcBeProgressPctRuntime <= 0)
         g_invertHcBeProgressPctRuntime = 25;
      else if(g_invertHcBeProgressPctRuntime == 25)
         g_invertHcBeProgressPctRuntime = 50;
      else if(g_invertHcBeProgressPctRuntime == 50)
         g_invertHcBeProgressPctRuntime = 75;
      else
         g_invertHcBeProgressPctRuntime = 0;
      Print("NAS SATS EA invert HCBE progress changed pct=", g_invertHcBeProgressPctRuntime);
   }
   else if(SelectedTargetR() <= 0.5 + 0.0001)
      g_hcBeTpLegRuntime = 0;
   else
   {
      g_hcBeTpLegRuntime++;
      if(RMultipleForLeg(g_hcBeTpLegRuntime) >= SelectedTargetR() - 0.0001)
         g_hcBeTpLegRuntime = 0;
      Print("NAS SATS EA HCBE leg changed hcbe_leg=", g_hcBeTpLegRuntime);
   }
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}

void ToggleInvertTradeMode()
{
   g_invertTradeModeRuntime = !g_invertTradeModeRuntime;
   if(g_invertTradeModeRuntime)
   {
      // Invert ON always starts as a pure line-color swap: normal TP price becomes red SL, normal SL price becomes green TP.
      // Advanced INV REF/INV TP overrides are opt-in after the switch is enabled.
      g_invertReferenceTpLegRuntime = 0;
      g_invertTargetRRuntime = 0.0;
      g_invertHcBeProgressPctRuntime = 0;
   }
   g_lastInvertedFinalTp = 0.0;
   ArrayFree(g_historySimCache);
   Print("NAS SATS EA invert trade mode changed state=", (g_invertTradeModeRuntime ? "ON" : "OFF"),
         " note=signal_math_unchanged_execution_direction_and_sl_tp_swapped invert_hcbe_uses_progress_pct");
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}

void CycleInvertTargetR()
{
   if(g_invertTargetRRuntime <= 0.0)
      g_invertTargetRRuntime = 0.50;
   else if(g_invertTargetRRuntime < 1.00)
      g_invertTargetRRuntime = 1.00;
   else if(g_invertTargetRRuntime < 1.50)
      g_invertTargetRRuntime = 1.50;
   else if(g_invertTargetRRuntime < 2.00)
      g_invertTargetRRuntime = 2.00;
   else if(g_invertTargetRRuntime < 3.00)
      g_invertTargetRRuntime = 3.00;
   else
      g_invertTargetRRuntime = 0.0;
   g_invertTargetRRuntime = ClampInvertTargetR(g_invertTargetRRuntime);
   g_lastInvertedFinalTp = 0.0;
   ArrayFree(g_historySimCache);
   Print("NAS SATS EA invert target R changed target_r=", DoubleToString(g_invertTargetRRuntime, 2),
         " note=signal_math_unchanged_invert_only_target_distance");
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}
void ToggleFtmoMode()
{
   g_ftmoModeRuntime = !g_ftmoModeRuntime;
   if(g_ftmoModeRuntime)
      g_riskLotOnlyRuntime = false;
   RefreshRuntimeMagicAfterRiskModeChange();
   Print("NAS SATS EA FTMO dashboard toggle state=", (g_ftmoModeRuntime ? "ON" : "OFF"),
         " risklot=", (g_riskLotOnlyRuntime ? "ON" : "OFF"),
         " magic=", RuntimeMagic());
   UpdateDashboard();
   ChartRedraw(0);
}

void ToggleRiskLotOnlyMode()
{
   g_riskLotOnlyRuntime = !g_riskLotOnlyRuntime;
   if(g_riskLotOnlyRuntime)
      g_ftmoModeRuntime = false;
   RefreshRuntimeMagicAfterRiskModeChange();
   Print("NAS SATS EA RiskLotOnly dashboard toggle state=", (g_riskLotOnlyRuntime ? "ON" : "OFF"),
         " ftmo=", (g_ftmoModeRuntime ? "ON" : "OFF"),
         " magic=", RuntimeMagic());
   UpdateDashboard();
   ChartRedraw(0);
}

bool ApplyPipSlDistanceFromDashboard(const string source)
{
   string pipObj = PREFIX + "EDIT_PIP_SL";
   if(ObjectFind(0, pipObj) < 0)
   {
      Print("NAS SATS EA pip SL apply failed missing edit object source=", source);
      return false;
   }

   string pipText = ObjectGetString(0, pipObj, OBJPROP_TEXT);
   StringTrimLeft(pipText);
   StringTrimRight(pipText);
   double requested = StringToDouble(pipText);
   if(requested <= 0.0)
   {
      Print("NAS SATS EA pip SL apply failed invalid value source=", source, " pips=", pipText);
      return false;
   }

   g_pipSlDistanceRuntime = MathMax(0.1, MathMin(100000.0, requested));
   ObjectSetString(0, pipObj, OBJPROP_TEXT, DoubleToString(g_pipSlDistanceRuntime, 1));
   Print("NAS SATS EA pip SL distance updated source=", source,
         " pips=", DoubleToString(g_pipSlDistanceRuntime, 2),
         " pip_size=", DoubleToString(NasPipSize(), _Digits),
         " note=signal_math_unchanged_only_sl_tp_geometry_changes");
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
   return true;
}
void ToggleRiskGeometryMode()
{
   if(g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_NORMAL)
      g_riskGeometryModeRuntime = NAS_RISK_GEOMETRY_SCALP;
   else if(g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_SCALP)
      g_riskGeometryModeRuntime = NAS_RISK_GEOMETRY_PIP;
   else if(g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_PIP)
      g_riskGeometryModeRuntime = NAS_RISK_GEOMETRY_SIGNAL_OPEN;
   else
      g_riskGeometryModeRuntime = NAS_RISK_GEOMETRY_NORMAL;
   Print("NAS SATS EA risk geometry mode changed mode=", RiskGeometryModeText(),
         " note=signal_math_unchanged_only_sl_tp_geometry_changes");
   RequestHistoryRefresh();
   UpdateDashboard();
   ChartRedraw(0);
}
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT)
      return;

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == PREFIX + "EDIT_START" || sparam == PREFIX + "EDIT_END")
         ApplyTradingWindowFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_LOT")
         ApplyLotFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_RISK_PCT")
         ApplyRiskPctFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_SPREAD_MAX")
         ApplySpreadMaxFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_FINAL_SCALE")
         ApplyFinalRiskScaleFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_ATR_BUFFER")
         ApplyAtrBufferFromDashboard("edit_end");
      else if(sparam == PREFIX + "EDIT_PIP_SL")
         ApplyPipSlDistanceFromDashboard("edit_end");
      return;
   }

   for(int ri = 0; ri < LIQ_MACRO_REGIME_COUNT; ++ri)
   {
      if(sparam == PREFIX + "BTN_MACRO_REG_" + IntegerToString(ri))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ToggleNasMacroRegime(ri);
         return;
      }
   }
   if(sparam == PREFIX + "BTN_DASH_COLLAPSE")
      SetDashboardCollapsed(true);
   else if(sparam == PREFIX + "BTN_DASH_EXPAND")
      SetDashboardCollapsed(false);
   else if(sparam == PREFIX + "BTN_EA_TOGGLE")
   {
      g_eaEnabledRuntime = !g_eaEnabledRuntime;
      g_lastExecutionStatus = g_eaEnabledRuntime ? "READY" : "BLOCKED";
      g_lastExecutionBlockReason = g_eaEnabledRuntime ? "" : "global_ea_kill_switch_off";
      Print("NAS SATS EA global kill switch toggled state=", (g_eaEnabledRuntime ? "ON" : "OFF"));
      UpdateDashboard();
      ChartRedraw(0);
   }
   else if(sparam == PREFIX + "BTN_CLOSE_ALL")
      CloseManagedPositions();
   else if(sparam == PREFIX + "BTN_BE")
      MoveRemainingToBE();
   else if(sparam == PREFIX + "BTN_CLOSE_1_3")
      CloseOneLeg();
   else if(sparam == PREFIX + "BTN_WINDOW_REVERSE")
   {
      g_windowReverseExitRuntime = !g_windowReverseExitRuntime;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ArrayFree(g_historySimCache);
      Print("NAS SATS EA window reverse exit toggled state=",
            (g_windowReverseExitRuntime ? "ON" : "OFF"),
            " behavior=out_of_window_opposite_positions_close_native_and_bridge");
      RequestHistoryRefresh();
      UpdateDashboard();
      ChartRedraw(0);
   }
   else if(sparam == PREFIX + "BTN_APPLY_WINDOW")
      ApplyTradingWindowFromDashboard("window_apply_button");
   else if(sparam == PREFIX + "BTN_FINAL_SCALE_APPLY")
      ApplyFinalRiskScaleFromDashboard("sl_apply_button");
   else if(sparam == PREFIX + "BTN_RISK_PCT_APPLY")
      ApplyRiskPctFromDashboard("risk_pct_apply_button");
   else if(sparam == PREFIX + "BTN_DAY_GUARD_APPLY")
      ApplyDailyGuardFromDashboard("daily_guard_apply_button");
   else if(sparam == PREFIX + "BTN_VOLUME_FILTER")
      ToggleNasVolumeFilter();
   else if(sparam == PREFIX + "BTN_VOLUME_APPLY")
      ApplyNasVolumeFromDashboard("volume_apply_button");
   else if(sparam == PREFIX + "BTN_TIMED_EXIT_APPLY")
      ApplyNasTimedExitFromDashboard("timed_exit_apply_button");
   else if(sparam == PREFIX + "BTN_AUDIT_WIN")
      CycleAuditWindow();
   else if(sparam == PREFIX + "BTN_NAS_BRIDGE_PUB")
   {
      NasProToggleBridgePublish();
      UpdateDashboard();
   }
   else if(sparam == PREFIX + "BTN_NAS_BRIDGE_ONLY")
   {
      NasProToggleBridgeOnly();
      UpdateDashboard();
   }
   else if(sparam == PREFIX + "BTN_NAS_BRIDGE_NATIVE")
   {
      NasProToggleNativeWithBridgeOnly();
      UpdateDashboard();
   }
   else if(sparam == PREFIX + "BTN_NAS_PRO_AUDIT")
   {
      NasProToggleAudit();
      UpdateDashboard();
   }
   else if(sparam == PREFIX + "BTN_ACCEPT_FILTER")
      ToggleAcceptedSignalFilter();
   else if(sparam == PREFIX + "BTN_NAS_REGIME_FILTER")
      ToggleNasRegimeFilter();
   else if(sparam == PREFIX + "BTN_TP_MODE")
      ToggleTpManagementMode();
   else if(sparam == PREFIX + "BTN_TP_LEG")
      CycleSelectedTpLeg();
   else if(sparam == PREFIX + "BTN_HCBE")
      CycleHcBeLeg();
   else if(sparam == PREFIX + "BTN_INV_TP")
      CycleInvertTargetR();
   else if(sparam == PREFIX + "BTN_INVERT")
      ToggleInvertTradeMode();
   else if(sparam == PREFIX + "BTN_FTMO")
      ToggleFtmoMode();
   else if(sparam == PREFIX + "BTN_RISKLOT")
      ToggleRiskLotOnlyMode();
   else if(sparam == PREFIX + "BTN_RISK_GEOM")
      ToggleRiskGeometryMode();
   else if(sparam == PREFIX + "BTN_ATRBUF_0")
      SetAtrBufferPct(0.0, "button_0");
   else if(sparam == PREFIX + "BTN_ATRBUF_20")
      SetAtrBufferPct(20.0, "button_20");
   else if(sparam == PREFIX + "BTN_ATRBUF_40")
      SetAtrBufferPct(40.0, "button_40");
   else if(sparam == PREFIX + "BTN_ATRBUF_60")
      SetAtrBufferPct(60.0, "button_60");
   else if(sparam == PREFIX + "BTN_ATRBUF_80")
      SetAtrBufferPct(80.0, "button_80");
   else if(sparam == PREFIX + "BTN_ATRBUF_100")
      SetAtrBufferPct(100.0, "button_100");
   else if(sparam == PREFIX + "BTN_ATRBUF_APPLY")
      ApplyAtrBufferFromDashboard("atr_apply_button");
   else if(sparam == PREFIX + "BTN_PIP_APPLY")
      ApplyPipSlDistanceFromDashboard("pip_apply_button");
}

void DrawDashboard()
{
   if(IsTesterMode())
      return;
   if(!InpShowDashboard)
      return;
   if(g_dashboardCollapsed)
   {
      DrawCollapsedDashboardToggle();
      return;
   }
   g_dashboardOpening = false;
   g_dashboardDoorFinished = true;
   g_dashboardDoorStartMs = 0;
   g_dashboardForceNextUpdate = true;
   UpdateDashboard();
}

void DrawDashboardShell(const int height)
{
   int h = UiClampInt(height, 34, 680);
   CreateRect("DASH_BG", 10, 18, 1080, h, C'24,30,42', C'134,158,182');
   CreateRect("DASH_HULL", 17, 25, 1066, MathMax(22, h - 14), C'40,48,62', C'90,178,255');
   CreateRect("DASH_DOCK_STRIPE", 18, 31, 1064, 4, C'90,178,255', C'90,178,255');
   if(h >= 98)
      CreateRect("DASH_CORE", 26, 56, 640, MathMax(20, h - 80), C'18,24,36', C'65,116,172');
   if(h >= 330)
      CreateRect("DASH_ACTION_PANEL", 676, 56, 382, 306, C'31,38,52', C'221,55,78');
   if(h >= 455)
      CreateRect("DASH_LOG_PANEL", 676, 390, 382, 260, C'31,38,52', C'90,178,255');
   if(h >= 590)
      CreateRect("DASH_AUDIT_PANEL", 38, 410, 606, 204, C'22,29,42', C'80,255,180');
}

void UpdateDoorAnimation()
{
   // Animation intentionally disabled: it was blocking expand/collapse and could leave deploy at 0%.
   g_dashboardDoorFinished = true;
   g_dashboardOpening = false;
   g_dashboardDoorStartMs = 0;
}

void UpdateDashboard()
{
   if(IsTesterMode())
      return;
   if(g_dashboardCollapsed)
      return;

   uint nowMs = GetTickCount();
   if(!g_dashboardForceNextUpdate && g_lastDashboardUpdateMs > 0 && (int)(nowMs - g_lastDashboardUpdateMs) < 500)
      return;
   g_lastDashboardUpdateMs = nowMs;
   g_dashboardForceNextUpdate = false; // dashboard_update_throttle

   if(!g_dashboardDoorFinished)
   {
      UpdateDoorAnimation();
      if(!g_dashboardDoorFinished)
      {
         ChartRedraw(0);
         return;
      }
   }

   DrawDashboardShell(680);
   CreateButtons();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_equityPeak <= 0.0 || equity > g_equityPeak)
      g_equityPeak = equity;
   double dd = g_equityPeak - equity;
   if(dd > g_maxDd)
      g_maxDd = dd;

   double totalPnl = HistoryPnl(0);
   double dailyPnl = HistoryPnl(DayStart());
   double openPnl = ManagedOpenPnl();

   string modeText = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R
                     ? "FIXED 1:" + DoubleToString(InpFixedRR, 1) + "R"
                     : (InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL ? "ORIGINAL PARTIAL BE" : "PARTIAL NO-BE");
   color titleColor = C'108,202,255';
   color accentBlue = C'90,178,255';
   color accentRed = C'221,55,78';
   color muted = C'184,196,210';
   color steel = C'216,222,230';
   double bid = 0.0;
   double ask = 0.0;
   double spreadPts = 0.0;
   double spreadGood = 0.0;
   double spreadNormal = 0.0;
   double spreadWide = 0.0;
   string spreadStatus = "";
   color spreadColor = C'184,196,210';
   bool spreadAllowed = SpreadSnapshot(bid, ask, spreadPts, spreadStatus, spreadColor, spreadGood, spreadNormal, spreadWide);
   g_lastSpreadPoints = spreadPts;
   g_lastSpreadStatus = spreadStatus;

   CreateLabel("DASH_TITLE", 34, 32, "AI STARSHIP NAS COCKPIT", steel, 12);
   CreateLabel("DASH_SUB", 356, 34, "AUTOPILOT " + modeText, titleColor, 9);
   CreateLabel("DASH_1", 38, 66, "Bridge: " + _Symbol + " " + EnumToString(_Period) + " | Magic " + IntegerToString(RuntimeMagic()), clrWhite);
   CreateLabel("DASH_PRICE", 38, 86, "Live price  BID " + DoubleToString(bid, _Digits) + " / ASK " + DoubleToString(ask, _Digits), titleColor);
   CreateLabel("DASH_SPREAD", 38, 106,
               "Live spread " + DoubleToString(spreadPts, 0) + " pt | " + spreadStatus
               + " | G/N/W " + DoubleToString(spreadGood, 0) + "/"
               + DoubleToString(spreadNormal, 0) + "/" + DoubleToString(spreadWide, 0)
               + (g_spreadMaxPointsRuntime > 0.0 ? " | max " + DoubleToString(g_spreadMaxPointsRuntime, 0) : " | max OFF")
               + (InpSpreadGovernorEnabled ? "" : " | governor OFF"),
               InpSpreadGovernorEnabled ? spreadColor : muted, 8);
   CreateLabel("DASH_STATUS", 38, 126,
               "EA " + string(g_eaEnabledRuntime ? "ON" : "OFF") + " | Trade status " + g_lastExecutionStatus
               + (g_lastExecutionBlockReason == "" ? "" : " | " + UiShort(g_lastExecutionBlockReason, 58)),
               (!g_eaEnabledRuntime || g_lastExecutionStatus == "BLOCKED" ? accentRed : (spreadAllowed ? C'80,255,180' : accentRed)), 8);
   CreateLabel("DASH_2", 38, 146, "Total PnL " + DoubleToString(totalPnl, 2) + "   Daily " + DoubleToString(dailyPnl, 2)
               + "   Open " + DoubleToString(openPnl, 2) + "   Max DD " + DoubleToString(g_maxDd, 2), muted);
   string dir = g_lastDirection > 0 ? "BUY" : (g_lastDirection < 0 ? "SELL" : "-");
   CreateLabel("DASH_4", 38, 166, "Last NAS " + dir + " | entry " + DoubleToString(g_lastEntry, _Digits)
               + " | SL " + DoubleToString(g_lastSl, _Digits)
               + " | TP3 " + DoubleToString(g_lastTp3, _Digits), clrWhite);
   if(InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R)
      CreateLabel("DASH_5", 38, 181, "FTMO risk " + string(AccountRiskRuntimeEnabled() ? "ON" : "OFF")
                  + " | lot " + string(InpAdvancedLotEngineEnabled && AccountRiskRuntimeEnabled() ? "AUTO" : "MANUAL")
                  + " | last lot=" + DoubleToString(g_lastAdvancedLot, 2)
                  + " | risk " + DoubleToString(g_accountRiskPerTradePctRuntime, 2) + "%"
                  + " | TP=" + DoubleToString(InpFixedRR, 1) + "R", accentBlue);
   else if(InpExecutionMode == NAS_EXEC_PARTIAL_BE_ORIGINAL)
      CreateLabel("DASH_5", 38, 181, "FTMO risk " + string(AccountRiskRuntimeEnabled() ? "ON" : "OFF")
                  + " | last total=" + DoubleToString(g_lastAdvancedLot, 2)
                  + " | portfolio " + DoubleToString(InpAccountRiskMaxPortfolioPct, 2) + "% | TP1 => SL->BE", accentBlue);
   else
      CreateLabel("DASH_5", 38, 181, "FTMO risk " + string(AccountRiskRuntimeEnabled() ? "ON" : "OFF")
                  + " | last total=" + DoubleToString(g_lastAdvancedLot, 2)
                  + " | portfolio " + DoubleToString(InpAccountRiskMaxPortfolioPct, 2) + "% | SL->BE OFF", accentBlue);

   double tradePct = 0.0;
   string tradeLabel = "";
   color tradeFill = accentBlue;
   if(BuildTradeProgress(tradePct, tradeLabel, tradeFill))
      CreateProgressBar("TRADE_VECTOR", 38, 193, 590, 24, tradePct, tradeLabel, tradeFill, C'42,51,68', C'134,158,182');
   else
      CreateProgressBar("TRADE_VECTOR", 38, 193, 590, 24, 0.0, "LIVE VECTOR STANDBY | no managed position", C'88,96,112', C'42,51,68', C'134,158,182');

   NasVisualMetrics visual;
   if(GetNasVisualMetrics(visual))
   {
      CreateLabel("DASH_SENSOR", 38, 226, "NAS SENSOR " + visual.status
                  + " | ST " + DoubleToString(visual.superTrend, _Digits)
                  + " | SMA13 " + DoubleToString(visual.sma13, _Digits), steel, 8);
      CreateLabel("DASH_SENSOR_HELP", 38, 246, "Fuel = live close proximity to SuperTrend cross + SMA13 filter; visual only, no trade logic mutation.", muted, 7);
      CreateProgressBar("BUY_FUEL", 38, 268, 285, 24, visual.buyPct,
                        "BUY ROCKET FUEL " + UiPctText(visual.buyPct), C'31,141,255', C'35,43,58', C'90,178,255');
      CreateProgressBar("SELL_FUEL", 343, 268, 285, 24, visual.sellPct,
                        "SELL ROCKET FUEL " + UiPctText(visual.sellPct), C'221,55,78', C'35,43,58', C'221,55,78');
   }
   else
   {
      CreateLabel("DASH_SENSOR", 38, 226, "NAS SENSOR awaiting enough live bars", accentRed, 8);
      CreateLabel("DASH_SENSOR_HELP", 38, 246, "Fuel = live close proximity to SuperTrend cross + SMA13 filter; visual only, no trade logic mutation.", muted, 7);
      CreateProgressBar("BUY_FUEL", 38, 268, 285, 24, 0.0, "BUY ROCKET FUEL --", C'31,141,255', C'35,43,58', C'90,178,255');
      CreateProgressBar("SELL_FUEL", 343, 268, 285, 24, 0.0, "SELL ROCKET FUEL --", C'221,55,78', C'35,43,58', C'221,55,78');
   }

   string regimeDash = "REGIME FILTER " + string(g_nasRegimeFilterRuntime ? "ON" : "OFF");
   color regimeColor = g_nasRegimeFilterRuntime ? C'80,255,180' : muted;
   if(g_nasRegimeFilterRuntime)
   {
      if(g_nasRegimeWarmupPending)
      {
         regimeDash += " | LOADING ASYNC | FAIL-OPEN";
         regimeColor = C'255,204,82';
      }
      else if(g_regimeV3.valid)
         regimeDash += " | " + g_regimeV3.core + " | " + g_regimeV3.h1h2Phase
                    + " | " + g_regimeV3.macroDirection + " | " + g_regimeV3.volatilityDepth;
      else
      {
         regimeDash += " | FAIL-OPEN " + g_regimeV3.detail;
         regimeColor = C'255,204,82';
      }
      regimeDash += " | rejected " + IntegerToString(g_nasRegimeRejectedLive);
   }
   CreateLabel("DASH_REGIME", 38, 299, UiShort(regimeDash, 94), regimeColor, 8);
   CreateLabel("DASH_WIN", 38, 368, "Trading window", titleColor, 9);
   CreateLabel("DASH_WIN_STATE", 38, 386,
               TradingTimeStateText()
               + " | reverse exit " + (g_windowReverseExitRuntime ? "ON" : "OFF")
               + " | volume " + (g_volumeFilterRuntime ? ("ON x" + DoubleToString(g_volumeMultiplierRuntime, 2)) : "OFF")
               + " | max hold " + (NasTimedExitConfigured() ? g_timedExitTimeRuntime : "OFF"),
               IsTradingTimeOpen() ? C'80,255,180' : C'255,95,140', 8);
   CreateLabel("DASH_AUDIT_TITLE", 52, 418, "AUDIT RESULTS - selected window / current combo", C'80,255,180', 9);
   CreateLabel("DASH_WD_MON", 52, 440, NasWeekdayAuditText(1, "MON"), NasWeekdayAuditColor(1), 7);
   CreateLabel("DASH_WD_TUE", 245, 440, NasWeekdayAuditText(2, "TUE"), NasWeekdayAuditColor(2), 7);
   CreateLabel("DASH_WD_WED", 438, 440, NasWeekdayAuditText(3, "WED"), NasWeekdayAuditColor(3), 7);
   CreateLabel("DASH_WD_THU", 150, 458, NasWeekdayAuditText(4, "THU"), NasWeekdayAuditColor(4), 7);
   CreateLabel("DASH_WD_FRI", 345, 458, NasWeekdayAuditText(5, "FRI"), NasWeekdayAuditColor(5), 7);
   CreateLabel("DASH_AUDIT_R0", 52, 478, UiShort(g_historyAuditRows[0], 82), C'216,222,230', 8);
   CreateLabel("DASH_AUDIT_R1", 52, 496, UiShort(g_historyAuditRows[1], 82), muted, 7);
   CreateLabel("DASH_AUDIT_R2", 52, 514, UiShort(g_historyAuditRows[2], 82), muted, 7);
   CreateLabel("DASH_AUDIT_R3", 52, 532, UiShort(g_historyAuditRows[3], 82), muted, 7);
   CreateLabel("DASH_AUDIT_R4", 52, 550, UiShort(g_historyAuditRows[4], 82), muted, 7);
   CreateLabel("DASH_AUDIT_R5", 52, 568, UiShort(g_historyAuditRows[5], 82), muted, 7);
   CreateLabel("DASH_AUDIT_R6", 52, 586, UiShort(g_historyAuditRows[6], 82), C'255,145,160', 7);
   color auditBarColor = g_historyCoverageBlocked ? C'255,80,110' : (g_historyAuditRunning ? C'38,140,220' : C'30,150,95');
   string auditBarText = g_historyCoverageBlocked ? "HISTORY BLOCKED"
      : (g_historyAuditRunning ? ("AUDIT " + DoubleToString(g_historyAuditProgressPct, 1) + "%") : (NasAuditWindowLabel() + " AUDIT READY"));
   CreateProgressBar("AUDIT_SCAN", 52, 608, 580, 16, g_historyCoverageBlocked ? 100.0 : g_historyAuditProgressPct,
                     auditBarText, auditBarColor, C'42,51,68', C'134,158,182');
   CreateLabel("DASH_ACTIONS", 696, 34, "AIRLOCK / CONFIG", steel, 9);
   CreateLabel("DASH_ACTION_HINT", 684, 116, "Manual", muted, 7);
   CreateLabel("DASH_START_LBL", 684, 140, "Start", muted, 8);
   CreateLabel("DASH_END_LBL", 760, 140, "End", muted, 8);
   CreateLabel("DASH_LOT_LBL", 836, 140, InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? "Fixed lot" : "Total lot", muted, 8);
   CreateEdit("EDIT_START", 684, 158, 68, 22, g_tradeStartTimeRuntime == "" ? InpTradeStartTime : g_tradeStartTimeRuntime);
   CreateEdit("EDIT_END", 760, 158, 68, 22, g_tradeEndTimeRuntime == "" ? InpTradeEndTime : g_tradeEndTimeRuntime);
   double shownLot = InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? FixedVolume() : (g_totalLotRuntime > 0.0 ? g_totalLotRuntime : InpTotalLot);
   CreateEdit("EDIT_LOT", 836, 158, 68, 22, DoubleToString(shownLot, 2));
   CreateLabel("DASH_RISK_PCT_LBL", 912, 140, "Risk%", muted, 8);
   CreateEdit("EDIT_RISK_PCT", 912, 158, 52, 22, DoubleToString(g_accountRiskPerTradePctRuntime, 2));
   bool riskAppliedFeedback = (int)(g_riskPctApplyFeedbackUntilMs - GetTickCount()) > 0;
   CreateButton("BTN_RISK_PCT_APPLY", 970, 158, 68, 22,
      riskAppliedFeedback ? "APPLIED" : "APPLY",
      riskAppliedFeedback ? C'30,150,95' : C'38,101,176');
   CreateLabel("DASH_SPREAD_MAX_LBL", 684, 190, "MaxSpr", muted, 8);
   CreateEdit("EDIT_SPREAD_MAX", 740, 186, 58, 22, DoubleToString(g_spreadMaxPointsRuntime, 0));
   CreateLabel("DASH_FINAL_SCALE_LBL", 806, 190, "SL%", muted, 8);
   CreateEdit("EDIT_FINAL_SCALE", 838, 186, 52, 22, DoubleToString(g_finalRiskScalePctRuntime, 0));
   CreateLabel("DASH_ATR_BUFFER_LBL", 896, 190, "ATR%", muted, 8);
   CreateEdit("EDIT_ATR_BUFFER", 928, 186, 42, 22, DoubleToString(g_swingBufferAtrRuntime * 100.0, 0));
   CreateButton("BTN_ATRBUF_APPLY", 974, 186, 66, 22, "ATR APPLY", C'38,101,176');
   if(g_riskGeometryModeRuntime == NAS_RISK_GEOMETRY_PIP)
   {
      CreateLabel("DASH_PIP_SL_LBL", 684, 218, "SL pips", muted, 8);
      CreateEdit("EDIT_PIP_SL", 740, 214, 58, 22, DoubleToString(g_pipSlDistanceRuntime, 1));
      CreateButton("BTN_PIP_APPLY", 806, 214, 86, 22, "PIP APPLY", C'38,101,176');
   }
   CreateLabel("DASH_DAY_PROFIT_LBL", 684, 388, "Day Profit %", muted, 8);
   CreateLabel("DASH_DAY_LOSS_LBL", 764, 388, "Day Loss %", muted, 8);
   CreateEdit("EDIT_DAY_PROFIT", 684, 402, 72, 22, DoubleToString(g_dailyProfitTargetPctRuntime, 2));
   CreateEdit("EDIT_DAY_LOSS", 764, 402, 72, 22, DoubleToString(g_dailyMaxLossPctRuntime, 2));
   CreateLabel("DASH_VOL_MULT_LBL", 772, 434, "VOL X", muted, 8);
   CreateEdit("EDIT_VOL_MULT", 812, 430, 52, 22, DoubleToString(g_volumeMultiplierRuntime, 2));
   CreateLabel("DASH_TIMED_EXIT_LBL", 684, 462, "Hold HH:MM", muted, 8);
   CreateEdit("EDIT_TIMED_EXIT", 758, 458, 62, 22, g_timedExitTimeRuntime);
   CreateLabel("DASH_TIMED_EXIT_STATE", 924, 462,
               NasTimedExitConfigured() ? "DURATION" : "OFF",
               NasTimedExitConfigured() ? C'255,204,82' : muted, 7);
   double dashLegR = SelectedTargetR();
   double dashTargetR = g_invertTradeModeRuntime ? (InvertTargetOverrideEnabled() ? g_invertTargetRRuntime : 0.0) : dashLegR;
   string dashTpText = g_invertTradeModeRuntime ? (EffectiveInversionReferenceText() + " | " + EffectiveInvertTargetText()
                                                + (InvertTargetOverrideEnabled() ? (" " + NasRiskRewardText(dashTargetR)) : " exact_SL_swap"))
                                                : ("final TP " + TargetRText(dashTargetR));
   CreateLabel("DASH_TP_CFG", 690, 490, "TP " + TpModeText() + " | " + dashTpText + " | " + EffectiveHcBeText()
               + " | Audit " + NasAuditWindowLabel()
               + " | Dup " + string(g_historyUseAcceptedFilterRuntime ? "OFF" : "ON") + " | Inv " + string(g_invertTradeModeRuntime ? "ON" : "OFF"), steel, 7);
   string dayGuardText = "DayGuard OFF";
   color dayGuardColor = muted;
   if(DailyPnlGuardConfigured())
   {
      DailyPnlGuardInstanceMetrics();
      string guardReason = "";
      bool guardLocked = DailyPnlGuardLocked(guardReason);
      dayGuardText = "Day " + DoubleToString(g_dailyGuardPnlPct, 2) + "%"
         + " T+" + DoubleToString(EffectiveDailyProfitTargetPct(), 2)
         + " L-" + DoubleToString(EffectiveDailyMaxLossPct(), 2)
         + " " + (guardLocked ? (guardReason == "daily_profit_target_hit" ? "PROFIT LOCK" : "LOSS LOCK") : "OPEN");
      if(g_nasBridgeOnlyRuntime && !g_nasNativeWithBridgeOnlyRuntime)
         dayGuardText += " MT5-PROXY";
      dayGuardColor = guardLocked ? C'221,55,78' : C'80,255,180';
   }
   CreateLabel("DASH_RISK_MODE", 690, 510, UiShort("Risk "
               + string(g_ftmoModeRuntime ? "FTMO" : (g_riskLotOnlyRuntime ? "RiskLotOnly" : "OFF"))
               + " | " + dayGuardText, 58), dayGuardColor, 7);

   CreateLabel("DASH_AUDIT_SUMMARY", 690, 532, UiShort(g_historyAuditSummary, 42), C'80,255,180', 8);
   CreateLabel("DASH_AUDIT_DETAIL", 690, 552, UiShort(g_historyAuditDetail, 42), muted, 7);
   CreateLabel("DASH_H0", 690, 574, "Recent NAS signals", titleColor, 8);
   CreateLabel("DASH_H1", 690, 592, UiShort(g_historySummary[0], 42), muted, 7);
   CreateLabel("DASH_H2", 690, 610, UiShort(g_historySummary[1], 42), muted, 7);
   CreateLabel("DASH_H3", 690, 628, UiShort(g_historySummary[2], 42), muted, 7);
   UpdateDoorAnimation();
}
