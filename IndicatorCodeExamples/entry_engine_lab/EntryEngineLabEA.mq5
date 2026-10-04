//+------------------------------------------------------------------+
//| 15 Minute ORB MT5 EA – v3.1 (production)                         |
//| Interactive dashboard with toggleable filters + live sim stats.   |
//| All filters, signal TF, and confirmation delay dashboard-driven.  |
//| Session clock: NY → broker server via GMT offset.                 |
//+------------------------------------------------------------------+
#property strict
#property version "1.01"
#include <Trade/Trade.mqh>
#include "NativeRiskBalance.mqh"
#include "LiqNarrativeSol_RegimeV3.mqh"
#include "TradeDayCalendarPublisher.mqh"
#include "NasUltimate_Core.mqh"
#include "TradeCalendarMatrix.mqh"
#include "AuditTradeCsv.mqh"
#include "MaCrossSignalCore.mqh"
#include "MaCrossAuditCache.mqh"
#include "MaCrossOrderFlow.mqh"
#define ORB15_BUILD "EntryEngineLab-1.13-NativeRecovery"

enum ORB_SESSION_PROFILE
{
   ORB_SESSION_AUTO=0,
   ORB_SESSION_US=1,
   ORB_SESSION_EU_CET=2,
   ORB_SESSION_UK=3,
   ORB_SESSION_HK=4,
   ORB_SESSION_JP=5,
   ORB_SESSION_MANUAL_NY=6,
   ORB_SESSION_FX_SYDNEY=7,
   ORB_SESSION_FX_TOKYO=8,
   ORB_SESSION_FX_LONDON=9,
   ORB_SESSION_FX_NEW_YORK=10
};

enum ORB_RISK_CAPITAL_MODE
{
   ORB_RISK_CURRENT_EQUITY=0,
   ORB_RISK_FIXED_REFERENCE=1
};

//=== CORE INPUTS ========================================================
input bool            InpEaEnabled          = true;
input long            InpMagic              = 11026004;
input ENUM_TIMEFRAMES InpSignalTimeframe    = PERIOD_CURRENT;   // Signal timeframe for every MA mode.
input MA_CROSS_SIGNAL_MODE InpMaCrossMode   = MA_CROSS_ORIGINAL_MTF;
input MA_CROSS_PAIR InpMaCrossPair           = MA_CROSS_PAIR_FAST;
input group "MA independent native entries (hedging, fixed SL/TP only)"
input bool InpIndependentEntries=false;
input int InpMaxConsecutiveEntries=1; // 1..1000; total concurrently open instance-owned native positions
input int             InpMaFastLength       = 9;
input int             InpMaMediumLength     = 27;
input int             InpMaSlowLength       = 200;
input double          InpBrokerGmtOffsetHours = 0.0;
input bool            InpAutoSessionBySymbol = true;
input ORB_SESSION_PROFILE InpSessionProfile = ORB_SESSION_AUTO;
input bool            InpAutoNewYorkDst     = true;
input string          InpOrbStartNy         = "09:30";
input string          InpOrbEndNy           = "09:45";
input string          InpTradeEndNy         = "16:00";
input bool            InpUtcMidnightSessionDefault = false; // Explicit override; AUTO USDJPY defaults to the UTC00 lifecycle.
input string          InpUtcOrbStartGmt     = "00:00";
input string          InpUtcOrbEndGmt       = "00:15";
input string          InpUtcTradeEndGmt     = "23:59";
input bool            InpUseEntryTimeWindow = false; // Additional GMT entry gate; does not alter ORB construction.
input string          InpEntryWindowStartGmt= "00:00";
input string          InpEntryWindowEndGmt  = "00:00"; // Equal start/end means full day when enabled.
input bool            InpUseClosedBarBreakout = true;
input double          InpMinBreakoutPoints  = 0.0;
input double          InpSlBufferPoints     = 0.0;
input double          InpSlDistancePct      = 100.0; // 100 = raw ORB SL distance, 80 = tighter, 120 = wider.
input bool            InpPipSlModeDefault   = false;
input double          InpPipSlPips          = 500.0;
input bool            InpOneTradePerNyDay   = false;
input int             InpDeviationPoints    = 30;
input int             InpMaxSpreadPoints    = 0;

//=== BREAKOUT CONFIRMATION ==============================================
input int    InpBreakoutDelayMinutes = 5;    // Wait N min after ORB end before accepting signals
input int    InpConfirmBars          = 1;    // Breakout bar must hold N closed bars above/below ORB

//=== OPTIONAL NAS SIGNAL CONFIRMATION ===================================
// Uses the exact NasUltimate_Core signal formula. NAS risk/SL/TP geometry is
// deliberately not imported into ORB. ENTRY GATE keeps its bounded/future-wait
// behavior; STATE GATE is a separate latest-causal-state admission mode.
// Entry gates and NAS exit controls remain independent.
enum ORB_NAS_VISUAL_POLICY
{
   ORB_NAS_VIS_NONE=0,
   ORB_NAS_VIS_STATE=1,
   ORB_NAS_VIS_FLOW=2,
   ORB_NAS_VIS_BOTH=3
};
input bool            InpNasConfirmationDefault = false;
input bool            InpNasStateGateDefault = false; // Entry-only: latest causal NAS direction must match ORB; no age limit or future wait.
input int             InpNasSensitivity = 4;
input bool            InpNasUseVolumeFilter = false; // STATE GATE volume policy.
input double          InpNasVolumeMultiplier = 1.00; // STATE GATE: required volume = previous-20 average x multiplier.
input bool            InpNasFlowUseVolumeFilter = false; // ENTRY GATE + OPP EXIT + ADD EXIT volume policy.
input double          InpNasFlowVolumeMultiplier = 1.00; // ENTRY/EXIT events: previous-20 average x multiplier.
input int             InpNasRsiLength   = 14;
input int             InpNasAtrRisk     = 1;
input int             InpNasAtrLen      = 14;
input int             InpNasSignalCalcBars = 5000; // Main NAS EA parity: identical closed-bar warm-up depth.
input int             InpNasHistoryBars = 60000; // Main NAS history parity: identical raw-overlay calculation depth.
input int             InpNasActiveSignalLookbackMinutes = 120; // Accept the latest still-active NAS direction before ORB.
input bool            InpNasExitOnOppositeSignalDefault = false; // Explicit opt-in: close this instance's trade on opposite NAS.
input bool            InpNasAdditionalExitDefault = false; // Independent full-lifecycle opposite NAS exit; preserves legacy OPP EXIT results when OFF.
input string          InpNasOppositeExitWait = "00:00"; // Holding grace HH:MM; an opposite NAS state during grace exits when grace expires.

//=== EXECUTION MODE =====================================================
enum ORB_EXEC_MODE { ORB_EXEC_SINGLE=0, ORB_EXEC_PARTIAL_3LEG=1 };
enum ORB_TARGET_LEG
{
   // Historic IDs remain stable for existing .set files; declaration order controls the Inputs list.
   ORB_TARGET_R005=20, ORB_TARGET_R010=21, ORB_TARGET_R015=22,
   ORB_TARGET_R020=23, ORB_TARGET_R025=24, ORB_TARGET_R030=25,
   ORB_TARGET_R035=26, ORB_TARGET_R040=27, ORB_TARGET_R045=28,
   ORB_TARGET_R050=1,
   ORB_TARGET_R055=29, ORB_TARGET_R060=30, ORB_TARGET_R065=31,
   ORB_TARGET_R070=32, ORB_TARGET_R075=7, ORB_TARGET_R080=33,
   ORB_TARGET_R085=34, ORB_TARGET_R090=35, ORB_TARGET_R095=36,
   ORB_TARGET_R100=2, ORB_TARGET_R150=3, ORB_TARGET_R200=4,
   ORB_TARGET_R250=5, ORB_TARGET_R300=6, ORB_TARGET_R350=8,
   ORB_TARGET_R400=9, ORB_TARGET_R450=10, ORB_TARGET_R500=11,
   ORB_TARGET_CUSTOM=1000
};
enum ORB_HC_BE_MODE { ORB_HC_BE_OFF=0, ORB_HC_BE_TP1=1, ORB_HC_BE_TP2=2, ORB_HC_BE_TP3=3, ORB_HC_BE_TP4=4, ORB_HC_BE_TP5=5 };
enum ORB_FVG_MODE { ORB_FVG_OFF=0, ORB_FVG_OPTIONAL=1, ORB_FVG_REQUIRE=2 };
enum ORB_EXIT_ENGINE_MODE { ORB_EXIT_FIXED_TARGET=0, ORB_EXIT_EOD_ONLY=1, ORB_EXIT_ORB_MID_INVALIDATION=2, ORB_EXIT_ATR_TRAIL=3, ORB_EXIT_EMA_STOP=4, ORB_EXIT_VWAP_STOP=5, ORB_EXIT_BROKER_TIME=6 };
enum ORB_ENTRY_MODE { ORB_ENTRY_BREAKOUT=0, ORB_ENTRY_PULLBACK_RETEST=1, ORB_ENTRY_IMBALANCE_M1=2 };
enum ORB_TARGET_MODE { ORB_TARGET_R_LEG=0, ORB_TARGET_RANGE_HEIGHT=1, ORB_TARGET_EOD=2, ORB_TARGET_AUTO_STOP_SIZE=3 };
enum BT_FILL_MODE { BT_FILL_SIGNAL_CLOSE=0, BT_FILL_NEXT_BAR_OPEN=1, BT_FILL_CONSERVATIVE=2 };
enum BT_SAME_BAR_POLICY { BT_SAMEBAR_CONSERVATIVE=0, BT_SAMEBAR_NEAREST_OPEN=1, BT_SAMEBAR_TP_FIRST=2, BT_SAMEBAR_SL_FIRST=3 };
#include "OrbStrategyMLCore.mqh"
#define OrbStrategyPresetCount OrbBuiltinStrategyPresetCount
#define OrbStrategyPresetLoad OrbBuiltinStrategyPresetLoad
#include "OrbStrategyPresetLibrary.mqh"
#undef OrbStrategyPresetCount
#undef OrbStrategyPresetLoad
input ORB_EXEC_MODE InpExecutionMode = ORB_EXEC_SINGLE;
input ORB_TARGET_LEG InpTargetTpLeg = ORB_TARGET_R200;
input ORB_HC_BE_MODE InpHalfBeMode = ORB_HC_BE_OFF;
input ORB_EXIT_ENGINE_MODE InpExitEngineMode = ORB_EXIT_FIXED_TARGET;
input ORB_TARGET_MODE InpTargetMode = ORB_TARGET_R_LEG;
input double InpRangeTargetMultiplier = 1.0;
input double InpSmallStopThresholdPts = 30.0;
input double InpSmallStopTargetR = 2.0;
input double InpLargeStopTargetR = 1.0;
input ORB_ENTRY_MODE InpEntryMode = ORB_ENTRY_BREAKOUT;
input int    InpRetestMaxWaitMinutes = 90;
input double InpRetestTolerancePoints = 5.0;
input double InpRetestResumePoints = 0.0;
input int    InpM1ImbalanceMaxWaitMinutes = 60;
input double InpM1ImbalanceMinGapPoints = 0.0;
input bool   InpM1ImbalanceRequireDisplacement = false;
input bool   InpM1ImbalanceRequireCloseOutsideRange = true;
input int    InpBrokerTimeExitHour = 19;
input int    InpBrokerTimeExitMinute = 15;
input int    InpExitTrailStartLeg = 0;        // 0 = active immediately, 1..6 = after TP leg touched
input int    InpExitAtrPeriod = 14;
input double InpExitAtrMultiplier = 2.0;
input int    InpExitEmaPeriod = 50;
input int    InpExitGraceBars = 1;
input double InpTp1R      = 0.5;
input double InpTp075R    = 0.75; // Backward-compatible target choice between TP1 (0.5R) and TP2 (1R).
input double InpTp2R      = 1.0;
input double InpTp3R      = 1.5;
input double InpTp4R      = 2.0;
input double InpTp5R      = 2.5;
input double InpTp6R      = 3.0;
input double InpTp35R     = 3.5;
input double InpTp40R     = 4.0;
input double InpTp45R     = 4.5;
input double InpTp50R     = 5.0;
input double InpSingleTpR = 2.0;    // Legacy fallback; target leg is preferred.

//=== FILTERS (initial state – toggleable from dashboard) ================
input bool   InpMoveToBEOnTp1       = false; // Legacy; use InpHalfBeMode for new presets.
input double InpBEOffsetPoints      = 2.0;
input bool   InpUseAtrRangeFilter   = false;
input int    InpAtrPeriod           = 14;
input double InpMinRangeAtrPct      = 15.0;
input double InpMaxRangeAtrPct      = 80.0;
input bool   InpUseVolumeFilter     = false;
input double InpVolumeMultiplier    = 1.0;
input bool   InpUseDisplacementFilter = false;
input ORB_FVG_MODE InpFvgMode       = ORB_FVG_OFF;
input bool   InpFilteredWindowReverseExitDefault = false; // Opposite filtered signal closes the accepted trade.
input bool   InpExitOnPostTradeSameDirectionDispBlockDefault = false; // Same-direction DISP_BLOCK after entry closes trade.
input int    InpDisplacementLookback = 20;
input int    InpDisplacementPercentile = 70;
input double InpMaxOpposingWickRatio = 0.45;
input int    InpFvgLookback         = 20;
input int    InpFvgScanWindow       = 10;
input int    InpFvgForwardBars      = 1;
input double InpMinFvgGapPoints     = 0.0;
input bool   InpRequireUnfilledFvg  = false;
input bool   InpFvgRequireDisplacement = false;
input bool   InpUseTimeExit         = false;
input int    InpTimeExitMinutes     = 120;
input double InpTimeExitMinProgress = 0.5;
input bool   InpUseDayFilter        = false;
input bool   InpTradeMonday         = true;
input bool   InpTradeTuesday        = true;
input bool   InpTradeWednesday      = true;
input bool   InpTradeThursday       = true;
input bool   InpTradeFriday         = true;
input bool   InpEnforceTpTouchClose = true;
input double InpTpTouchTolerancePts = 2.0;

//=== LOT SIZING =========================================================
input bool   InpUseAutoRiskLot   = true;
input ORB_RISK_CAPITAL_MODE InpRiskCapitalMode = ORB_RISK_CURRENT_EQUITY;
input double InpFixedRiskReferenceCapital = 0.0; // Required when fixed-reference mode is selected.
input double InpFixedRiskMaxOvershootMoney = 1.0; // Post-fill absolute account-currency ceiling.
input double InpRiskPerTradePct  = 1.0;
input double InpFixedLot         = 0.10;
input double InpMaxLot           = 0.0;
input bool   InpUseChartScopedMagic = true;
input bool   InpAccountRiskEnabled  = true;
input bool   InpFtmoModeDefault     = false;
input bool   InpRiskLotOnlyModeDefault = false;
input bool   InpInvertModeDefault      = false;
input bool   InpAdvancedReverseDefault = false; // Spread-compensated broker SL/TP; MT5 native only.
input double InpAdvancedReverseMaxCostPctDefault = 10.0; // Max inverse quote gap as % of source TP distance; 100 disables.
input double InpAtrExposurePct      = 2.0;
input double InpMaxPortfolioPct     = 4.0;
input double InpDailyLossLimitPct   = 0.0;
input double InpMaxDrawdownPct      = 0.0;
input double InpMaxMarginUsagePct   = 40.0;
input double InpInitialBalanceOverride = 0.0;
input int    InpDayResetHourGmt    = 0;
input bool   InpLiquidateOnBreach  = true;
input double InpSafetyBufferPct    = 95.0;
input bool   InpBlockUnprotected   = true;
input bool   InpFailClosed         = true;

//=== DISPLAY & AUDIT ====================================================
input bool InpShowDashboard          = true;
input int  InpDashboardX             = 10;
input int  InpDashboardY             = 18;
input bool InpDrawHistoricalSignals  = true;
input bool InpDrawTradeLevelSegments = true;
input bool InpAuditHistoryAutoRetry  = true;
input int  InpAuditHistoryRetrySec   = 10;
input int  InpHistoricalDays         = 35;
input int  InpHistoricalWeeks        = 5;
input bool InpAuditCsv               = false;
input bool InpAuditHistoricalSimulationCsv = false;
input bool InpHistoricalAuditVerboseLog = false; // Detailed per-day/trade Journal output; OFF is materially faster on long windows.
input bool InpAdvancedAuditEngineDefault = false; // OFF preserves the former exact audit engine byte-for-byte.
input bool InpAdvancedAuditPersistIndex = true;   // Persist broker+symbol isolated exact bid/ask minute shards.
input bool InpAdvancedAuditShadowParity = false;  // Diagnostic: compare ADV with legacy and fail back on any mismatch.
input bool InpLogOnInit              = false;
input bool InpTesterTradeAuditCsv    = false;
input int  InpTesterTradeAuditMaxRows= 50000;
input string InpValidationJobId      = "";
input bool   InpFileBridgeEnabled       = false;
input bool   InpFileBridgeOnlyMode      = false;
input bool   InpNativeTradeWithBridgeOnlyDefault = false;
input bool   InpFileBridgeUseCommonFiles= true;
input string InpFileBridgeLatestFile    = "EntryEngineLabBridge_Latest.csv";
input string InpFileBridgeAuditPrefix   = "EntryEngineLabBridge_Audit_";
input int    InpBridgeChannel           = 1; // 1..9999; publisher/listener channels are fully isolated.
input bool InpRegimeTrendLowVolAllowed       = true;
input bool InpRegimeTrendHighVolAllowed      = true;
input bool InpRegimeRangeLowVolAllowed       = true;
input bool InpRegimeRangeHighVolAllowed      = true;
input bool InpRegimeTransitionPendingAllowed = true;
input bool InpRegimeTransitionFreshAllowed   = true;
// Experimental ORB transfer of the Liq Narrative RF family. The master is
// deliberately OFF by default; RF02+RF03+RF11 is only a 2Y research candidate.
input bool InpOrbRfFilterDefault = false;
input bool InpOrbRf01Blocked = false;
input bool InpOrbRf02Blocked = true;
input bool InpOrbRf03Blocked = true;
input bool InpOrbRf04Blocked = false;
input bool InpOrbRf05Blocked = false;
input bool InpOrbRf06Blocked = false;
input bool InpOrbRf07Blocked = false;
input bool InpOrbRf08Blocked = false;
input bool InpOrbRf09Blocked = false;
input bool InpOrbRf10Blocked = false;
input bool InpOrbRf11Blocked = true;
input bool InpOrbRf12Blocked = false;
input bool   InpTesterRegimeMatrix        = false; // Tester-only regime allow-list matrix export.
input int    InpTesterRegimeMatrixWeeks   = 82;
input datetime InpTesterRegimeMatrixAnchorTime = 0; // Tester-only: wait until this timestamp before exporting.
input BT_FILL_MODE InpBacktestFillMode = BT_FILL_NEXT_BAR_OPEN;
input BT_SAME_BAR_POLICY InpBacktestSameBarPolicy = BT_SAMEBAR_CONSERVATIVE;
input bool   InpBacktestUseTickReplay    = true;
input bool   InpBacktestNativeParity     = true;  // Tick replay, bid/ask fills, and fill-based SL/TP geometry.
input double InpBacktestSpreadPts       = 0.0;
input double InpBacktestSlippagePts     = 0.0;
input double InpBacktestCommissionPerLot= 0.0;

//--- Objects ------------------------------------------------------------
CTrade trade;
string PREFIX = "ENTRYLAB_";
string g_testerTradeAuditFile = "";
int    g_testerTradeAuditRows = 0;
long   DASH_Z = 1000000;

bool IsValidationTester()
{
   return (bool)MQLInfoInteger(MQL_TESTER) && StringLen(InpValidationJobId) > 0;
}
bool IsTesterMode()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

//--- Core state ---------------------------------------------------------
int      g_nyDayKey = 0;
bool     g_orbReady = false;
bool     g_tradeTaken = false;
double   g_orbHigh = 0, g_orbLow = 0, g_orbAvgVolume = 0;
datetime g_orbStartServer = 0, g_orbEndServer = 0, g_tradeEndServer = 0;
datetime g_instanceStartedAt = 0;
bool     g_startupOrbGuardPending = false;
bool     g_startupOrbDayLocked = false;
datetime g_startupOrbPriorSignalBar = 0;
string   g_startupOrbPriorSignalDir = "";
// MA signals are independent closed-bar events. Unlike an ORB breakout, an
// accepted MA event must not consume every later signal from the same day.
// Open-lifecycle and optional one-trade-per-day guards remain authoritative.
bool     g_orbOperationalCandidateConsumed = false;
datetime g_orbOperationalCandidateBar = 0;
string   g_orbOperationalCandidateDir = "";
datetime g_lastSignalBarTime = 0;
datetime g_lastCheckedSignalBarTime = 0;
bool     g_newDayReverseRetryPending = false;
string   g_newDayReverseRetryRawDir = "";
int      g_newDayReverseRetryExecDir = 0;
datetime g_newDayReverseRetrySignalBar = 0;
datetime g_newDayReverseRetryAvailable = 0;
double   g_newDayReverseRetrySignalClose = 0.0;
string   g_lastLiveWindowKey = "";
int      g_liveWindowDrawnDayKey = 0;
datetime g_lastHistBuild = 0;
bool     g_histNeedsRedraw = true;
bool     g_histRedrawQueued = false;
ulong    g_histRedrawNotBeforeMs = 0;
bool     g_histAuditRunning = false;
bool     g_histAuditCancelRequested = false;
int      g_histAuditPhase = 0; // 0 idle, 1 prep, 2 draw overlays, 3 calculate
int      g_histActiveGeneration = 0;
int      g_histBuildGeneration = 0;
int      g_histAuditTotalDays = 0;
int      g_histAuditProcessedDays = 0;
double   g_histAuditProgressPct = 0.0;
string   g_histAuditStage = "";
int      g_histAuditStageDone = 0;
int      g_histAuditStageTotal = 0;
ulong    g_histAuditStartedMs = 0;
ulong    g_histAuditRequestedMs = 0;
double   g_histAuditLastElapsedSec = 0.0;
double   g_histAuditLastWallSec = 0.0;
double   g_histAuditCoverageSec = 0.0;
double   g_histAuditNasSec = 0.0;
double   g_histAuditPrepSec = 0.0;
double   g_histAuditDrawSec = 0.0;
double   g_histAuditCalcSec = 0.0;
double   g_histAuditCommitSec = 0.0;
ulong    g_histAuditStageStartedMs = 0;
long     g_histTickBlocksSkipped = 0;
long     g_histTickTicksSkipped = 0;
long     g_histTickTicksVisited = 0;
ulong    g_histAuditLastUiMs = 0;
ulong    g_histTimerCoreLastMs = 0;
bool     g_histCoveragePending = false;
bool     g_histCoverageHardBlocked = false;
datetime g_histCoverageNextRetry = 0;
int      g_histCoverageAttempts = 0;
int      g_maCacheFailedAttempts = 0;
string   g_histCoverageStatus = "";
string   g_histCoverageDetail = "";

//--- Runtime toggles (mutable from dashboard) ---------------------------
bool            g_rtFilterAtr     = true;
bool            g_rtFilterVol     = true;
bool            g_rtFilterDay     = false;
bool            g_rtFilteredWindowReverseExit = false;
bool            g_rtPostTradeDispBlockExit = false;
bool            g_rtEntryWindow   = false;
int             g_rtEntryWindowStartMin = 0;
int             g_rtEntryWindowEndMin = 0;
bool            g_rtTimeExit      = false;
bool            g_rtDisplacement  = false;
ORB_FVG_MODE    g_rtFvgMode       = ORB_FVG_OFF;
ORB_EXIT_ENGINE_MODE g_rtExitMode = ORB_EXIT_FIXED_TARGET;
ORB_ENTRY_MODE  g_rtEntryMode     = ORB_ENTRY_BREAKOUT;
ORB_TARGET_MODE g_rtTargetMode    = ORB_TARGET_R_LEG;
bool            g_rtBEOnTp1       = true;
bool            g_rtEaEnabled     = true;
bool            g_ftmoMode        = false;
bool            g_riskLotOnlyMode = false;
bool            g_rtInvertMode    = false;
bool            g_rtAdvancedReverse = false;
double          g_rtAdvancedReverseMaxCostPct = 10.0;
bool            g_rtUtcMidnightSession = false;
bool            g_rtNasConfirmation = false;
bool            g_rtNasStateGate = false;
bool            g_rtNasExitOnOppositeSignal = false;
bool            g_rtNasAdditionalExit = false;
bool            g_rtAdvancedAuditEngine = false;
MA_CROSS_SIGNAL_MODE g_rtMaCrossMode = MA_CROSS_ORIGINAL_MTF;
MA_CROSS_PAIR g_rtMaCrossPair = MA_CROSS_PAIR_FAST;
int             g_rtNasSensitivity = 4;
bool            g_rtNasVolumeFilter = false;
double          g_rtNasVolumeMultiplier = 1.0;
bool            g_rtNasFlowVolumeFilter = false;
double          g_rtNasFlowVolumeMultiplier = 1.0;
int             g_rtNasActiveSignalLookbackMinutes = 120;
int             g_rtNasOppositeExitWaitMinutes = 0;
datetime        g_lastNasOverlayClosedBar = 0;
int             g_lastNasOverlaySignalCount = 0;
int             g_lastNasRawEventCount = 0;
int             g_lastNasAllowedEventCount = 0;
int             g_lastNasStateAllowedEventCount = 0;
int             g_lastNasFlowAllowedEventCount = 0;
int             g_lastNasVolumeMissingCount = 0;
int             g_lastNasOverlayCopiedBars = 0;
double          g_rtRiskPerTradePct = 1.0;
double          g_rtVolumeMultiplier = 1.0;
datetime        g_riskApplyFlashUntil = 0;
datetime        g_volApplyFlashUntil = 0;
datetime        g_entryWindowApplyFlashUntil = 0;
datetime        g_nasApplyFlashUntil = 0;
bool            g_auditRuntime    = false;
ENUM_TIMEFRAMES g_rtSignalTf      = PERIOD_M15;  // runtime signal timeframe
int             g_rtDelayMin      = 5;            // runtime confirmation delay
bool            g_rtUseDelay      = true;         // toggle for confirmation delay
int             g_rtTargetLeg     = 4;
double          g_rtCustomR       = 0.0;
int             g_rtHalfBeLeg     = 0;
int             g_rtExitTrailStartLeg = 0;
int             g_rtExitEmaPeriod = 50;
double          g_rtExitAtrMultiplier = 2.0;
int             g_rtHistoricalWeeks = 5;
double          g_rtSlDistancePct = 100.0;
bool            g_rtPipSlMode = false;
double          g_rtPipSlPips = 500.0;

// A filtered/accepted ORB candidate is persisted while waiting for a fresh,
// same-direction NAS event. No bridge publication occurs in this state.
bool     g_nasPending = false;
string   g_nasPendingDir = "";
datetime g_nasPendingSignalBar = 0;
datetime g_nasPendingAcceptedAt = 0;
datetime g_nasPendingExpire = 0;
double   g_nasPendingSignalClose = 0.0;

// Restart-safe lifecycle state for trades managed by NAS opposite exit. It is
// scoped by account + source symbol + source TF + bridge channel, so another
// ORB instance cannot close this instance's native or listener position.
bool     g_nasManagedLifecycle = false;
string   g_nasManagedRawDir = "";
int      g_nasManagedExecDir = 0;
datetime g_nasManagedStartAt = 0;
datetime g_nasManagedLastScanAt = 0;
bool     g_nasManagedBridgePublished = false;
bool     g_nasManagedClosePending = false;
datetime g_nasManagedOppositeAt = 0;

#define ORB_REGIME_COUNT 6
bool   g_regimeAllowed[ORB_REGIME_COUNT];
int    g_regimeWins[ORB_REGIME_COUNT];
int    g_regimeLosses[ORB_REGIME_COUNT];
int    g_lastSignalRegime = -1;
string g_lastSignalRegimeName = "UNKNOWN";

#define ORB_RF_COUNT 12
bool   g_orbRfEnabled = false;
bool   g_orbRfBlocked[ORB_RF_COUNT];
int    g_orbRfWins[ORB_RF_COUNT];
int    g_orbRfLosses[ORB_RF_COUNT];

// Strategy-library UI state. The applied strategy excludes risk, account
// guards, bridge publishing mode and bridge channel by design.
int    g_strategyPresetIndex = -1;
int    g_strategyCandidateIndex = -1;
string g_strategySearch = "";
bool   g_strategyPopupOpen = false;
bool   g_strategyPopupDrawn = false;
bool   g_strategyFavoritesOnly = false;
bool   g_strategyFavorites[];
int    g_strategySearchPage = 0;
int    g_strategyMatches[];
int    g_strategyVisible[5];
int    g_strategyVisibleCount = 0;
datetime g_strategyApplyFlashUntil = 0;
string g_strategyFilterNetText = "";
string g_strategyFilterPair = "";
string g_strategyFilterGeometryText = "";
bool   g_strategyFilterGeometryEnabled = false;
double g_strategyFilterGeometry = 0.0;
string g_strategyFilterWrText = "";
string g_strategyFilterMinCumText = "";
bool   g_strategyFilterNetEnabled = false;
bool   g_strategyFilterWrEnabled = false;
bool   g_strategyFilterMinCumEnabled = false;
double g_strategyFilterNet = 0.0;
double g_strategyFilterWr = 0.0;
double g_strategyFilterMinCum = 0.0;

//--- Trade management state ---------------------------------------------
int      g_tradeDir = 0;
double   g_tradeEntry = 0, g_tradeSl = 0, g_tradeRisk = 0;
double   g_tradeTp1 = 0, g_tradeTp2 = 0, g_tradeTp3 = 0, g_tradeTp4 = 0, g_tradeTp5 = 0, g_tradeTp6 = 0;
datetime g_tradeOpenTime = 0;
bool     g_beMoved = false;
bool     g_halfClosed = false;
double   g_tradeBestHigh = 0.0;
double   g_tradeBestLow = 0.0;
datetime g_tradeLastDynamicExitBar = 0;
bool     g_orbBridgePlanActive = false;
int      g_orbBridgePlanDir = 0;
datetime g_orbBridgePlanTime = 0;
double   g_orbBridgePlanEntry = 0.0;
double   g_orbBridgePlanSl = 0.0;
double   g_orbBridgePlanTp = 0.0;
double   g_orbBridgePlanHalf = 0.0;
string   g_lastFilterReason = "";
string   g_lastExecStatus = "READY";
long     g_runtimeMagic = 0;
uint     g_lastRiskGuardMs = 0;
datetime g_riskPerfCacheAt = 0;
double   g_riskPerfClosedAll = 0.0;
double   g_riskPerfClosedToday = 0.0;
double   g_riskPerfFloating = 0.0;

//--- Pullback/retest entry state ----------------------------------------
bool     g_retestPending = false;
bool     g_retestTouched = false;
string   g_retestDir = "";
datetime g_retestSignalBar = 0;
datetime g_retestExpire = 0;
double   g_retestLevel = 0.0;
double   g_retestBreakoutClose = 0.0;
string   g_retestContext = "";

//--- 1M imbalance entry state ------------------------------------------
bool     g_imbPending = false;
string   g_imbDir = "";
datetime g_imbSignalBar = 0;
datetime g_imbStart = 0;
datetime g_imbExpire = 0;
double   g_imbBreakoutClose = 0.0;
string   g_imbContext = "";

//--- Historical stats ---------------------------------------------------
int    g_histTotal = 0, g_histWins = 0, g_histLosses = 0;
int    g_histOpen = 0, g_histFlat = 0, g_histInvalid = 0;
int    g_histStopLossExits = 0, g_histNasOppositeExits = 0, g_histNewDayReverseExits = 0;
double g_histNetR = 0.0, g_histWonR = 0.0, g_histLostR = 0.0;
double g_histNetMoney = 0.0;
double g_histMinCumulativeR = 0.0;
double g_histMinCumulativeMoney = 0.0;
double g_histPeakCumulativeR = 0.0;
double g_histMaxPeakDrawdownR = 0.0;
double g_histMaxPeakDrawdownMoney = 0.0;
string g_histStatLine = "-";
string g_histFirstInvalidReason = "";
int    g_weekdayWins[7];
int    g_weekdayLosses[7];
//--- Audit engine state -------------------------------------------------
datetime g_auditLastProbeTime   = 0;
string   g_auditLastProbeHash   = "";
datetime g_auditLastHistTime    = 0;
ulong    g_auditLastHistTicket  = 0;
datetime g_auditLastHistScan    = 0;

//--- Brute-force backtest engine ----------------------------------------
struct OrbBtCombo { int tfIdx; int delayIdx; int exitMode; int entryMode; int targetMode; bool atr; bool vol; bool day; bool be; bool disp; bool fvgReq; };
struct OrbBtDayCache {
   double orbHi,orbLo,avgVol,dailyAtr;
   datetime orbStart,orbEnd,tradeEnd;
   int nyY,nyM,nyD,dow,used;
   bool valid;
};
struct OrbBtBreakout {
   bool found; string dir; datetime sigTime;
   double sigClose,sigH,sigL,sigVol,preAvgVol;
};
struct OrbBtStats { int total,wins,losses; double wonR,lostR,netR; };
struct OrbNasHistoricalEvent
{
   string dir;
   datetime barTime;
   datetime availableTime;
   double closePrice;
   double highPrice;
   double lowPrice;
   double signalVolume;
   double averageVolume;
};
OrbNasHistoricalEvent g_histNasEvents[];
bool g_histNasCacheActive=false;
int g_histNasCacheCopiedBars=0;
bool g_histNasCacheReady=false;
datetime g_histNasCacheFrom=0;
datetime g_histNasCacheEventFrom=0;
datetime g_histNasCacheClosedBar=0;
ENUM_TIMEFRAMES g_histNasCacheTf=PERIOD_CURRENT;
int g_histNasCacheSensitivity=0;
int g_histNasCacheRsiLength=0;
int g_histNasCacheAtrRisk=0;
int g_histNasCacheAtrLen=0;

bool     g_btRunning     = false;
int      g_btStep        = 0;
int      g_btTotal       = 0;
int      g_btWeeks       = 2;
string   g_btFileName    = "";
string   g_btLastResult  = "";
uint     g_btStartMs     = 0;
uint     g_btElapsedMs   = 0;
BT_FILL_MODE g_btFillMode = BT_FILL_NEXT_BAR_OPEN;
BT_SAME_BAR_POLICY g_btSameBarPolicy = BT_SAMEBAR_CONSERVATIVE;
bool     g_btNativeParity = true;
double   g_btSpreadPts = 0.0;
double   g_btSlippagePts = 0.0;
double   g_btCommissionPerLot = 0.0;
bool     g_testerRegimeMatrixDone = false;

OrbBtCombo g_btCombos[];
#define OBT_TF_COUNT    3
#define OBT_DELAY_COUNT 4
#define OBT_ENTRY_COUNT 3
#define OBT_TARGET_COUNT 4
ENUM_TIMEFRAMES g_btTFs[]  = {PERIOD_M1,PERIOD_M5,PERIOD_M15};
int             g_btDelays[]= {0,3,5,10};
OrbBtDayCache   g_btDays[];
int             g_btDayCount = 0;
// Flat [dayIdx * (tfCount*delayCount) + comboIdx] cache; MQL5 does not
// reliably support resizeable jagged arrays of structs.
OrbBtBreakout   g_btBreakouts[];

#include "OrbUltimate_ProfessionalPipeline.mqh"
#include "MaIndependentEntries.mqh"
#include "LabPolicyRuntime.mqh"
#include "MaExitPolicy.mqh"

//=========================================================================
//  UTILITY FUNCTIONS
//=========================================================================
int ParseClockMinutes(string v,int fb){StringTrimLeft(v);StringTrimRight(v);int p=StringFind(v,":");if(p<0)return fb;int h=(int)StringToInteger(StringSubstr(v,0,p));int m=(int)StringToInteger(StringSubstr(v,p+1));if(h<0||h>23||m<0||m>59)return fb;return h*60+m;}
bool ParseStrictClockMinutes(string value,int &minutes)
{
   StringTrimLeft(value);StringTrimRight(value);minutes=-1;
   if(StringLen(value)!=5||StringSubstr(value,2,1)!=":")return false;
   int positions[]={0,1,3,4};
   for(int i=0;i<ArraySize(positions);i++)
   {
      ushort ch=StringGetCharacter(value,positions[i]);
      if(ch<'0'||ch>'9')return false;
   }
   int hour=(int)StringToInteger(StringSubstr(value,0,2));
   int minute=(int)StringToInteger(StringSubstr(value,3,2));
   if(hour<0||hour>23||minute<0||minute>59)return false;
   minutes=hour*60+minute;return true;
}
bool ParseStrictDurationMinutes(string value,int &minutes)
{
   StringTrimLeft(value);StringTrimRight(value);minutes=-1;
   if(StringLen(value)!=5||StringSubstr(value,2,1)!=":")return false;
   int positions[]={0,1,3,4};
   for(int i=0;i<ArraySize(positions);i++)
   {
      ushort ch=StringGetCharacter(value,positions[i]);
      if(ch<'0'||ch>'9')return false;
   }
   int hour=(int)StringToInteger(StringSubstr(value,0,2));
   int minute=(int)StringToInteger(StringSubstr(value,3,2));
   if(hour<0||hour>99||minute<0||minute>59)return false;
   minutes=hour*60+minute;return true;
}
string DurationMinutesText(int minutes)
{
   int safe=MathMax(0,MathMin(5999,minutes));
   return StringFormat("%02d:%02d",safe/60,safe%60);
}
string ClockMinutesText(int minutes)
{
   int normalized=((minutes%1440)+1440)%1440;
   return StringFormat("%02d:%02d",normalized/60,normalized%60);
}
string RuntimeEntryWindowKey(string field)
{
   int inputStart=ParseClockMinutes(InpEntryWindowStartGmt,0);
   int inputEnd=ParseClockMinutes(InpEntryWindowEndGmt,0);
   return "ORB_EWIN."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +StringFormat("%I64d",ChartID())+".D"+(InpUseEntryTimeWindow?"1":"0")+"."
      +IntegerToString(inputStart)+"."+IntegerToString(inputEnd)+"."+field;
}
bool PersistRuntimeEntryWindow()
{
   bool a=GlobalVariableSet(RuntimeEntryWindowKey("ON"),g_rtEntryWindow?1.0:0.0)>0;
   bool b=GlobalVariableSet(RuntimeEntryWindowKey("START"),(double)g_rtEntryWindowStartMin)>0;
   bool c=GlobalVariableSet(RuntimeEntryWindowKey("END"),(double)g_rtEntryWindowEndMin)>0;
   if(a&&b&&c)GlobalVariablesFlush();
   return a&&b&&c;
}
bool LoadRuntimeEntryWindow()
{
   int startMin=-1,endMin=-1;
   if(!ParseStrictClockMinutes(InpEntryWindowStartGmt,startMin)||!ParseStrictClockMinutes(InpEntryWindowEndGmt,endMin))
      return false;
   g_rtEntryWindow=InpUseEntryTimeWindow;
   g_rtEntryWindowStartMin=startMin;g_rtEntryWindowEndMin=endMin;
   if(GlobalVariableCheck(RuntimeEntryWindowKey("ON")))g_rtEntryWindow=GlobalVariableGet(RuntimeEntryWindowKey("ON"))>0.5;
   if(GlobalVariableCheck(RuntimeEntryWindowKey("START")))g_rtEntryWindowStartMin=(int)MathRound(GlobalVariableGet(RuntimeEntryWindowKey("START")));
   if(GlobalVariableCheck(RuntimeEntryWindowKey("END")))g_rtEntryWindowEndMin=(int)MathRound(GlobalVariableGet(RuntimeEntryWindowKey("END")));
   g_rtEntryWindowStartMin=MathMax(0,MathMin(1439,g_rtEntryWindowStartMin));
   g_rtEntryWindowEndMin=MathMax(0,MathMin(1439,g_rtEntryWindowEndMin));
   return true;
}
bool SetRuntimeEntryWindow(bool enabled,int startMin,int endMin)
{
   if(startMin<0||startMin>1439||endMin<0||endMin>1439)return false;
   bool oldEnabled=g_rtEntryWindow;int oldStart=g_rtEntryWindowStartMin,oldEnd=g_rtEntryWindowEndMin;
   g_rtEntryWindow=enabled;g_rtEntryWindowStartMin=startMin;g_rtEntryWindowEndMin=endMin;
   if(PersistRuntimeEntryWindow())return true;
   g_rtEntryWindow=oldEnabled;g_rtEntryWindowStartMin=oldStart;g_rtEntryWindowEndMin=oldEnd;
   return false;
}
int GmtMinuteOfDay(datetime serverTime)
{
   datetime utc=serverTime-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
   MqlDateTime st;TimeToStruct(utc,st);return st.hour*60+st.min;
}
bool EntryWindowAllowsAt(datetime serverTime)
{
   if(!g_rtEntryWindow)return true;
   int minute=GmtMinuteOfDay(serverTime);
   if(g_rtEntryWindowStartMin==g_rtEntryWindowEndMin)return true;
   if(g_rtEntryWindowStartMin<g_rtEntryWindowEndMin)
      return minute>=g_rtEntryWindowStartMin&&minute<g_rtEntryWindowEndMin;
   return minute>=g_rtEntryWindowStartMin||minute<g_rtEntryWindowEndMin;
}
string EntryWindowLabel()
{
   return g_rtEntryWindow?("GMT "+ClockMinutesText(g_rtEntryWindowStartMin)+"-"+ClockMinutesText(g_rtEntryWindowEndMin)):"WIN OFF";
}
datetime MakeDateTime(int y,int mo,int d,int h,int mi,int s=0){MqlDateTime st;ZeroMemory(st);st.year=y;st.mon=mo;st.day=d;st.hour=h;st.min=mi;st.sec=s;return StructToTime(st);}
int DayOfWeekForDate(int y,int mo,int d){MqlDateTime st;TimeToStruct(MakeDateTime(y,mo,d,12,0,0),st);return st.day_of_week;}
int NthSunday(int y,int mo,int nth){int fd=DayOfWeekForDate(y,mo,1);int fs=1+((7-fd)%7);return fs+(nth-1)*7;}
int LastSunday(int y,int mo){int last=31;if(mo==4||mo==6||mo==9||mo==11)last=30;else if(mo==2)last=((y%4==0&&y%100!=0)||y%400==0)?29:28;for(int d=last;d>=last-6;d--)if(DayOfWeekForDate(y,mo,d)==0)return d;return last;}
bool IsNewYorkDstDate(int y,int mo,int d){if(!InpAutoNewYorkDst)return true;if(mo<3||mo>11)return false;if(mo>3&&mo<11)return true;if(mo==3)return d>=NthSunday(y,3,2);if(mo==11)return d<NthSunday(y,11,1);return false;}
int NyUtcOffsetSecondsForDate(int y,int mo,int d){return IsNewYorkDstDate(y,mo,d)?-4*3600:-5*3600;}
datetime NyLocalToServer(int y,int mo,int d,int minOfDay){int h=minOfDay/60;int mi=minOfDay%60;datetime ny=MakeDateTime(y,mo,d,h,mi,0);datetime utc=ny-NyUtcOffsetSecondsForDate(y,mo,d);return utc+(int)MathRound(InpBrokerGmtOffsetHours*3600.0);}
datetime ServerToNyLocal(datetime s){datetime utc=s-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);MqlDateTime u;TimeToStruct(utc,u);return utc+NyUtcOffsetSecondsForDate(u.year,u.mon,u.day);}
int CurrentNyDayKey(int &y,int &mo,int &d){datetime utc=TimeCurrent()-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);MqlDateTime u;TimeToStruct(utc,u);datetime ny=utc+NyUtcOffsetSecondsForDate(u.year,u.mon,u.day);MqlDateTime n;TimeToStruct(ny,n);y=n.year;mo=n.mon;d=n.day;return y*10000+mo*100+d;}
string UpperText(string s){StringToUpper(s);return s;}
bool IsForexCurrencyCode(const string code)
{
   return code=="USD"||code=="EUR"||code=="GBP"||code=="JPY"||code=="CHF"
      ||code=="CAD"||code=="AUD"||code=="NZD"||code=="SGD"||code=="HKD"
      ||code=="NOK"||code=="SEK"||code=="DKK"||code=="PLN"||code=="MXN"
      ||code=="ZAR"||code=="TRY"||code=="CNH";
}
bool ExtractForexPair(const string symbol,string &base,string &quote)
{
   string upper=UpperText(symbol);base="";quote="";
   int count=StringLen(upper);
   for(int i=0;i+6<=count;i++)
   {
      string candidateBase=StringSubstr(upper,i,3);
      string candidateQuote=StringSubstr(upper,i+3,3);
      if(candidateBase!=candidateQuote&&IsForexCurrencyCode(candidateBase)&&IsForexCurrencyCode(candidateQuote))
      {
         base=candidateBase;quote=candidateQuote;return true;
      }
   }
   return false;
}
ORB_SESSION_PROFILE ResolveForexSessionProfile(const string base,const string quote)
{
   // Use the first liquid regional session shared by either leg. This keeps
   // suffix/prefix broker symbols deterministic without classifying metals,
   // crypto or index CFDs as FX pairs.
   if(base=="JPY"||quote=="JPY"||base=="SGD"||quote=="SGD"||base=="HKD"||quote=="HKD")
      return ORB_SESSION_FX_TOKYO;
   if(base=="AUD"||quote=="AUD"||base=="NZD"||quote=="NZD")
      return ORB_SESSION_FX_SYDNEY;
   if(base=="EUR"||quote=="EUR"||base=="GBP"||quote=="GBP"||base=="CHF"||quote=="CHF"
      ||base=="NOK"||quote=="NOK"||base=="SEK"||quote=="SEK"||base=="DKK"||quote=="DKK"
      ||base=="PLN"||quote=="PLN")
      return ORB_SESSION_FX_LONDON;
   return ORB_SESSION_FX_NEW_YORK;
}
ORB_SESSION_PROFILE ResolveSessionProfile()
{
   if(!InpAutoSessionBySymbol)return ORB_SESSION_MANUAL_NY;
   if(InpSessionProfile!=ORB_SESSION_AUTO)return InpSessionProfile;
   string s=UpperText(_Symbol);
   if(StringFind(s,"HK50")>=0||StringFind(s,"HSI")>=0||StringFind(s,"HANG")>=0)return ORB_SESSION_HK;
   if(StringFind(s,"JP225")>=0||StringFind(s,"JPN225")>=0||StringFind(s,"NIKKEI")>=0||StringFind(s,"NI225")>=0)return ORB_SESSION_JP;
   if(StringFind(s,"FR40")>=0||StringFind(s,"FRA40")>=0||StringFind(s,"CAC")>=0||StringFind(s,"DE30")>=0||StringFind(s,"DE40")>=0||StringFind(s,"GER40")>=0||StringFind(s,"DAX")>=0)return ORB_SESSION_EU_CET;
   if(StringFind(s,"UK100")>=0||StringFind(s,"FTSE")>=0)return ORB_SESSION_UK;
   if(StringFind(s,"US30")>=0||StringFind(s,"USTEC")>=0||StringFind(s,"US100")>=0||StringFind(s,"NAS")>=0||StringFind(s,"US500")>=0||StringFind(s,"SPX")>=0||StringFind(s,"DJ")>=0)return ORB_SESSION_US;
   string fxBase="",fxQuote="";
   if(ExtractForexPair(s,fxBase,fxQuote))return ResolveForexSessionProfile(fxBase,fxQuote);
   return ORB_SESSION_MANUAL_NY;
}
string SessionProfileLabel(ORB_SESSION_PROFILE p)
{
   if(g_rtUtcMidnightSession)return "UTC00";
   if(p==ORB_SESSION_US)return "US/NY";
   if(p==ORB_SESSION_EU_CET)return "EU/CET";
   if(p==ORB_SESSION_UK)return "UK/LON";
   if(p==ORB_SESSION_HK)return "HK/HKT";
   if(p==ORB_SESSION_JP)return "JP/JST";
   if(p==ORB_SESSION_FX_SYDNEY)return "FX/SYD";
   if(p==ORB_SESSION_FX_TOKYO)return "FX/TYO";
   if(p==ORB_SESSION_FX_LONDON)return "FX/LON";
   if(p==ORB_SESSION_FX_NEW_YORK)return "FX/NY";
   if(p==ORB_SESSION_MANUAL_NY)return "MANUAL_NY";
   return "AUTO";
}
bool IsEuropeDstDate(int y,int mo,int d){if(mo<3||mo>10)return false;if(mo>3&&mo<10)return true;if(mo==3)return d>=LastSunday(y,3);if(mo==10)return d<LastSunday(y,10);return false;}
bool IsSydneyDstDate(int y,int mo,int d)
{
   if(mo>4&&mo<10)return false;
   if(mo>10||mo<4)return true;
   if(mo==10)return d>=1+((7-DayOfWeekForDate(y,10,1))%7);
   if(mo==4)return d<1+((7-DayOfWeekForDate(y,4,1))%7);
   return false;
}
int SessionUtcOffsetSecondsForDate(ORB_SESSION_PROFILE p,int y,int mo,int d)
{
   if(p==ORB_SESSION_US||p==ORB_SESSION_MANUAL_NY)return NyUtcOffsetSecondsForDate(y,mo,d);
   if(p==ORB_SESSION_EU_CET)return IsEuropeDstDate(y,mo,d)?2*3600:1*3600;
   if(p==ORB_SESSION_UK)return IsEuropeDstDate(y,mo,d)?1*3600:0;
   if(p==ORB_SESSION_HK)return 8*3600;
   if(p==ORB_SESSION_JP)return 9*3600;
   if(p==ORB_SESSION_FX_SYDNEY)return IsSydneyDstDate(y,mo,d)?11*3600:10*3600;
   if(p==ORB_SESSION_FX_TOKYO)return 9*3600;
   if(p==ORB_SESSION_FX_LONDON)return IsEuropeDstDate(y,mo,d)?1*3600:0;
   if(p==ORB_SESSION_FX_NEW_YORK)return NyUtcOffsetSecondsForDate(y,mo,d);
   return NyUtcOffsetSecondsForDate(y,mo,d);
}
datetime SessionLocalToServer(int y,int mo,int d,int minOfDay)
{
   if(g_rtUtcMidnightSession)
   {
      datetime utc=MakeDateTime(y,mo,d,minOfDay/60,minOfDay%60,0);
      return utc+(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
   }
   ORB_SESSION_PROFILE p=ResolveSessionProfile();
   if(p==ORB_SESSION_MANUAL_NY)return NyLocalToServer(y,mo,d,minOfDay);
   int h=minOfDay/60;int mi=minOfDay%60;
   datetime local=MakeDateTime(y,mo,d,h,mi,0);
   datetime utc=local-SessionUtcOffsetSecondsForDate(p,y,mo,d);
   return utc+(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
}
datetime ServerToSessionLocal(datetime s)
{
   if(g_rtUtcMidnightSession)
      return s-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
   ORB_SESSION_PROFILE p=ResolveSessionProfile();
   if(p==ORB_SESSION_MANUAL_NY)return ServerToNyLocal(s);
   datetime utc=s-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
   MqlDateTime u;TimeToStruct(utc,u);
   return utc+SessionUtcOffsetSecondsForDate(p,u.year,u.mon,u.day);
}
void SessionClockMinutes(int &sm,int &em,int &tem)
{
   if(g_rtUtcMidnightSession)
   {
      sm=ParseClockMinutes(InpUtcOrbStartGmt,0);
      em=ParseClockMinutes(InpUtcOrbEndGmt,15);
      tem=ParseClockMinutes(InpUtcTradeEndGmt,1439);
      return;
   }
   ORB_SESSION_PROFILE p=ResolveSessionProfile();
   if(p==ORB_SESSION_US||p==ORB_SESSION_MANUAL_NY){sm=ParseClockMinutes(InpOrbStartNy,570);em=ParseClockMinutes(InpOrbEndNy,585);tem=ParseClockMinutes(InpTradeEndNy,960);return;}
   if(p==ORB_SESSION_EU_CET){sm=9*60;em=9*60+15;tem=17*60+30;return;}
   if(p==ORB_SESSION_UK){sm=8*60;em=8*60+15;tem=16*60+30;return;}
   if(p==ORB_SESSION_HK){sm=9*60+30;em=9*60+45;tem=16*60;return;}
   if(p==ORB_SESSION_JP){sm=9*60;em=9*60+15;tem=15*60+30;return;}
   if(p==ORB_SESSION_FX_SYDNEY){sm=8*60;em=8*60+15;tem=23*60+59;return;}
   if(p==ORB_SESSION_FX_TOKYO){sm=9*60;em=9*60+15;tem=23*60+59;return;}
   if(p==ORB_SESSION_FX_LONDON){sm=8*60;em=8*60+15;tem=17*60;return;}
   if(p==ORB_SESSION_FX_NEW_YORK){sm=8*60;em=8*60+15;tem=17*60;return;}
   sm=ParseClockMinutes(InpOrbStartNy,570);em=ParseClockMinutes(InpOrbEndNy,585);tem=ParseClockMinutes(InpTradeEndNy,960);
}
bool ValidateUtcSessionInputs()
{
   int sm=-1,em=-1,tem=-1;
   if(!ParseStrictClockMinutes(InpUtcOrbStartGmt,sm)
      ||!ParseStrictClockMinutes(InpUtcOrbEndGmt,em)
      ||!ParseStrictClockMinutes(InpUtcTradeEndGmt,tem))return false;
   return sm<em&&em<=tem;
}
string SessionClockLabel()
{
   int sm,em,tem;SessionClockMinutes(sm,em,tem);
   return SessionProfileLabel(ResolveSessionProfile())+" "+StringFormat("%02d:%02d-%02d:%02d End %02d:%02d",sm/60,sm%60,em/60,em%60,tem/60,tem%60);
}
int CurrentSessionDayKey(int &y,int &mo,int &d){datetime loc=ServerToSessionLocal(TimeCurrent());MqlDateTime n;TimeToStruct(loc,n);y=n.year;mo=n.mon;d=n.day;return y*10000+mo*100+d;}
string FmtTime(datetime t){return t<=0?"-":TimeToString(t,TIME_DATE|TIME_SECONDS);}
string BoolText(bool v){return v?"true":"false";}
string EffectiveOrbDirection(string rawDir)
{
   if(!g_rtInvertMode)return rawDir;
   if(rawDir=="BUY")return "SELL";
   if(rawDir=="SELL")return "BUY";
   return rawDir;
}
string RuntimeInvertLabel(){return g_rtInvertMode?"INV ON":"INV OFF";}
bool IsAutoUsdJpyUtcSession()
{
   if(!InpAutoSessionBySymbol||InpSessionProfile!=ORB_SESSION_AUTO)return false;
   string base="",quote="";
   return ExtractForexPair(_Symbol,base,quote)&&base=="USD"&&quote=="JPY";
}
bool RuntimeUtcSessionDefaultValue()
{
   return InpUtcMidnightSessionDefault||IsAutoUsdJpyUtcSession();
}
string RuntimeUtcSessionKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   // USDJPY gets a fresh, symbol-specific namespace so an old generic OFF
   // value cannot silently override its new AUTO UTC00 default.
   string scope=IsAutoUsdJpyUtcSession()?"ORB_UJUTC1.":"ORB_UTC00.";
   return scope+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."
      +(RuntimeUtcSessionDefaultValue()?"1":"0");
}
void LoadRuntimeUtcSession()
{
   g_rtUtcMidnightSession=RuntimeUtcSessionDefaultValue();
   string key=RuntimeUtcSessionKey();
   if(GlobalVariableCheck(key))g_rtUtcMidnightSession=(GlobalVariableGet(key)>0.5);
}
bool SetRuntimeUtcSession(bool enabled)
{
   if(GlobalVariableSet(RuntimeUtcSessionKey(),enabled?1.0:0.0)<=0)return false;
   g_rtUtcMidnightSession=enabled;
   return true;
}
string RuntimeInvertKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_INV."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+(InpInvertModeDefault?"1":"0");
}
void LoadRuntimeInvertMode()
{
   g_rtInvertMode=InpInvertModeDefault;
   string key=RuntimeInvertKey();
   if(GlobalVariableCheck(key))g_rtInvertMode=(GlobalVariableGet(key)>0.5);
}
string RuntimeAdvancedReverseKey()
{
   return "ENTRYLAB_ADV_REV."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +StringFormat("%I64d",ChartID());
}
string RuntimeAdvancedReverseMaxCostKey(){return RuntimeAdvancedReverseKey()+".max_cost_pct";}
bool SetRuntimeAdvancedReverseMaxCostPct(double value)
{
   if(!MathIsValidNumber(value)||value<0.0||value>100.0)return false;
   if(GlobalVariableSet(RuntimeAdvancedReverseMaxCostKey(),value)<=0)return false;
   g_rtAdvancedReverseMaxCostPct=value;
   return true;
}
void LoadRuntimeAdvancedReverse()
{
   g_rtAdvancedReverse=InpAdvancedReverseDefault;
   g_rtAdvancedReverseMaxCostPct=InpAdvancedReverseMaxCostPctDefault;
   if(!MathIsValidNumber(g_rtAdvancedReverseMaxCostPct)||g_rtAdvancedReverseMaxCostPct<0.0
      ||g_rtAdvancedReverseMaxCostPct>100.0)g_rtAdvancedReverseMaxCostPct=100.0;
   string key=RuntimeAdvancedReverseKey();
   if(GlobalVariableCheck(key))g_rtAdvancedReverse=GlobalVariableGet(key)>0.5;
   key=RuntimeAdvancedReverseMaxCostKey();
   if(GlobalVariableCheck(key))
   {
      double saved=GlobalVariableGet(key);
      if(MathIsValidNumber(saved)&&saved>=0.0&&saved<=100.0)g_rtAdvancedReverseMaxCostPct=saved;
   }
   if(g_rtAdvancedReverse)g_rtInvertMode=true;
   g_rtAdvancedReverse=false; // Retired UI mode; inverse geometry is now unified.
}
bool AdvancedReverseShape(string &reason)
{
   reason="";
   if(InpExecutionMode!=ORB_EXEC_SINGLE||g_rtEntryMode!=ORB_ENTRY_BREAKOUT
      ||g_rtTargetMode!=ORB_TARGET_R_LEG
      ||!ExitModeUsesFixedTp(g_rtExitMode))reason="SINGLE_FIXED_R_REQUIRED";
   else if(g_maIndependent||g_maReverseExit||g_rtTimeExit||g_rtFilteredWindowReverseExit
      ||g_rtPostTradeDispBlockExit||RuntimeNasExitEnabled()||RuntimeHalfBeLeg()>0||g_rtBEOnTp1)
      reason="OTHER_POSITION_EXITS_ENABLED";
   else if(g_orbBridgeEnabled)reason="MT5_NATIVE_ONLY_PUB_OFF";
   return reason=="";
}
bool SetRuntimeInvertMode(bool enabled)
{
   if(GlobalVariableSet(RuntimeInvertKey(),enabled?1.0:0.0)<=0)return false;
   g_rtInvertMode=enabled;
   return true;
}
string RuntimeMaCrossModeKey()
{
   return "ENTRYLAB_MODE."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +StringFormat("%I64d",ChartID())+"."+(string)InpMaCrossMode;
}
void LoadRuntimeMaCrossMode()
{
   g_rtMaCrossMode=InpMaCrossMode;
   g_rtMaCrossPair=InpMaCrossPair;
   string key=RuntimeMaCrossModeKey();
   if(GlobalVariableCheck(key))
   {
      int value=(int)MathRound(GlobalVariableGet(key));
      if(value>=0&&value<=6)g_rtMaCrossMode=(MA_CROSS_SIGNAL_MODE)value;
   }
   string pairKey=RuntimeMaCrossPairKey();
   if(GlobalVariableCheck(pairKey))
   {
      int value=(int)MathRound(GlobalVariableGet(pairKey));
      if(value>=0&&value<=2)g_rtMaCrossPair=(MA_CROSS_PAIR)value;
   }
}
bool SetRuntimeMaCrossMode(MA_CROSS_SIGNAL_MODE mode)
{
   if(GlobalVariableSet(RuntimeMaCrossModeKey(),(double)mode)<=0)return false;
   g_rtMaCrossMode=mode;
   return true;
}
string RuntimeMaCrossPairKey()
{
   return "ENTRYLAB_PAIR."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +StringFormat("%I64d",ChartID())+"."+(string)InpMaCrossPair;
}
bool SetRuntimeMaCrossPair(MA_CROSS_PAIR pair)
{
   if(GlobalVariableSet(RuntimeMaCrossPairKey(),(double)pair)<=0)return false;
   g_rtMaCrossPair=pair;
   return true;
}
string RuntimeNasConfirmationKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASCF."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+(InpNasConfirmationDefault?"1":"0");
}
string RuntimeNasStateGateKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASSTATE."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+(InpNasStateGateDefault?"1":"0");
}
void LoadRuntimeNasConfirmation()
{
   g_rtNasConfirmation=InpNasConfirmationDefault;
   g_rtNasStateGate=InpNasStateGateDefault;
   string key=RuntimeNasConfirmationKey();
   if(GlobalVariableCheck(key))g_rtNasConfirmation=(GlobalVariableGet(key)>0.5);
   string stateKey=RuntimeNasStateGateKey();
   if(GlobalVariableCheck(stateKey))g_rtNasStateGate=(GlobalVariableGet(stateKey)>0.5);
   // Preserve the established ENTRY GATE if stale/corrupt persisted state
   // ever enables both mutually exclusive entry admission engines.
   if(g_rtNasConfirmation&&g_rtNasStateGate)
   {
      g_rtNasStateGate=false;
      GlobalVariableSet(stateKey,0.0);
   }
}
bool SetRuntimeNasEntryModes(bool confirmationEnabled,bool stateGateEnabled)
{
   if(confirmationEnabled&&stateGateEnabled)return false;
   bool confirmationSaved=false,stateSaved=false;
   if(confirmationEnabled)
   {
      stateSaved=GlobalVariableSet(RuntimeNasStateGateKey(),0.0)>0;
      confirmationSaved=stateSaved&&GlobalVariableSet(RuntimeNasConfirmationKey(),1.0)>0;
   }
   else if(stateGateEnabled)
   {
      confirmationSaved=GlobalVariableSet(RuntimeNasConfirmationKey(),0.0)>0;
      stateSaved=confirmationSaved&&GlobalVariableSet(RuntimeNasStateGateKey(),1.0)>0;
   }
   else
   {
      confirmationSaved=GlobalVariableSet(RuntimeNasConfirmationKey(),0.0)>0;
      stateSaved=GlobalVariableSet(RuntimeNasStateGateKey(),0.0)>0;
   }
   if(!confirmationSaved||!stateSaved)
   {
      g_rtNasConfirmation=GlobalVariableCheck(RuntimeNasConfirmationKey())&&GlobalVariableGet(RuntimeNasConfirmationKey())>0.5;
      g_rtNasStateGate=GlobalVariableCheck(RuntimeNasStateGateKey())&&GlobalVariableGet(RuntimeNasStateGateKey())>0.5;
      if(g_rtNasConfirmation&&g_rtNasStateGate)
      {g_rtNasStateGate=false;GlobalVariableSet(RuntimeNasStateGateKey(),0.0);}
      return false;
   }
   g_rtNasConfirmation=confirmationEnabled;
   g_rtNasStateGate=stateGateEnabled;
   return true;
}
bool SetRuntimeNasConfirmation(bool enabled){return SetRuntimeNasEntryModes(enabled,false);}
bool SetRuntimeNasStateGate(bool enabled){return SetRuntimeNasEntryModes(false,enabled);}
string RuntimeNasExitKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASEX."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+(InpNasExitOnOppositeSignalDefault?"1":"0");
}
string RuntimeNasLookbackKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASLB."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+IntegerToString(MathMax(0,InpNasActiveSignalLookbackMinutes));
}
string RuntimeNasExitWaitKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   int inputMinutes=0;ParseStrictDurationMinutes(InpNasOppositeExitWait,inputMinutes);
   return "ORB_NASEXWAIT."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+IntegerToString(MathMax(0,inputMinutes));
}
string RuntimeNasAdditionalExitKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASAX."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+(InpNasAdditionalExitDefault?"1":"0");
}
int ClampNasSensitivity(int value){return MathMax(1,MathMin(100,value));}
double ClampNasVolumeMultiplier(double value){return NormalizeDouble(MathMax(0.05,MathMin(200.0,value)),4);}
string RuntimeNasSensitivityKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASSENS."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+IntegerToString(ClampNasSensitivity(InpNasSensitivity));
}
string RuntimeNasVolumeEnabledKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASVE."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+(InpNasUseVolumeFilter?"1":"0");
}
string RuntimeNasVolumeMultiplierKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   int basis=(int)MathRound(ClampNasVolumeMultiplier(InpNasVolumeMultiplier)*10000.0);
   return "ORB_NASVM."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+IntegerToString(basis);
}
string RuntimeNasFlowVolumeEnabledKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASFVE."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+(InpNasFlowUseVolumeFilter?"1":"0");
}
string RuntimeNasFlowVolumeMultiplierKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   int basis=(int)MathRound(ClampNasVolumeMultiplier(InpNasFlowVolumeMultiplier)*10000.0);
   return "ORB_NASFVM."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+IntegerToString(basis);
}
void LoadRuntimeNasControls()
{
   int inputWaitMinutes=0;
   ParseStrictDurationMinutes(InpNasOppositeExitWait,inputWaitMinutes);
   g_rtNasExitOnOppositeSignal=InpNasExitOnOppositeSignalDefault;
   g_rtNasAdditionalExit=InpNasAdditionalExitDefault;
   g_rtNasSensitivity=ClampNasSensitivity(InpNasSensitivity);
   g_rtNasVolumeFilter=InpNasUseVolumeFilter;
   g_rtNasVolumeMultiplier=ClampNasVolumeMultiplier(InpNasVolumeMultiplier);
   g_rtNasFlowVolumeFilter=InpNasFlowUseVolumeFilter;
   g_rtNasFlowVolumeMultiplier=ClampNasVolumeMultiplier(InpNasFlowVolumeMultiplier);
   g_rtNasActiveSignalLookbackMinutes=MathMax(0,MathMin(1440,InpNasActiveSignalLookbackMinutes));
   g_rtNasOppositeExitWaitMinutes=MathMax(0,MathMin(5999,inputWaitMinutes));
   if(GlobalVariableCheck(RuntimeNasExitKey()))
      g_rtNasExitOnOppositeSignal=(GlobalVariableGet(RuntimeNasExitKey())>0.5);
   if(GlobalVariableCheck(RuntimeNasAdditionalExitKey()))
      g_rtNasAdditionalExit=(GlobalVariableGet(RuntimeNasAdditionalExitKey())>0.5);
   if(g_rtNasExitOnOppositeSignal&&g_rtNasAdditionalExit)
   {
      // Mutually exclusive radio modes. Preserve the pre-existing OPP mode
      // if stale/corrupt persisted state ever enables both.
      g_rtNasAdditionalExit=false;
      GlobalVariableSet(RuntimeNasAdditionalExitKey(),0.0);
   }
   if(GlobalVariableCheck(RuntimeNasLookbackKey()))
      g_rtNasActiveSignalLookbackMinutes=(int)MathRound(GlobalVariableGet(RuntimeNasLookbackKey()));
   if(GlobalVariableCheck(RuntimeNasExitWaitKey()))
      g_rtNasOppositeExitWaitMinutes=(int)MathRound(GlobalVariableGet(RuntimeNasExitWaitKey()));
   if(GlobalVariableCheck(RuntimeNasSensitivityKey()))
      g_rtNasSensitivity=ClampNasSensitivity((int)MathRound(GlobalVariableGet(RuntimeNasSensitivityKey())));
   if(GlobalVariableCheck(RuntimeNasVolumeEnabledKey()))
      g_rtNasVolumeFilter=(GlobalVariableGet(RuntimeNasVolumeEnabledKey())>0.5);
   if(GlobalVariableCheck(RuntimeNasVolumeMultiplierKey()))
      g_rtNasVolumeMultiplier=ClampNasVolumeMultiplier(GlobalVariableGet(RuntimeNasVolumeMultiplierKey()));
   bool flowEnabledStored=GlobalVariableCheck(RuntimeNasFlowVolumeEnabledKey());
   bool flowMultiplierStored=GlobalVariableCheck(RuntimeNasFlowVolumeMultiplierKey());
   if(flowEnabledStored)
      g_rtNasFlowVolumeFilter=(GlobalVariableGet(RuntimeNasFlowVolumeEnabledKey())>0.5);
   if(flowMultiplierStored)
      g_rtNasFlowVolumeMultiplier=ClampNasVolumeMultiplier(GlobalVariableGet(RuntimeNasFlowVolumeMultiplierKey()));
   // Backward-compatible, field-wise migration: before the split, the single
   // NAS volume policy controlled entry and exit events as well as state.
   if(!flowEnabledStored)
   {
      g_rtNasFlowVolumeFilter=g_rtNasVolumeFilter;
      GlobalVariableSet(RuntimeNasFlowVolumeEnabledKey(),g_rtNasFlowVolumeFilter?1.0:0.0);
   }
   if(!flowMultiplierStored)
   {
      g_rtNasFlowVolumeMultiplier=g_rtNasVolumeMultiplier;
      GlobalVariableSet(RuntimeNasFlowVolumeMultiplierKey(),g_rtNasFlowVolumeMultiplier);
   }
   g_rtNasActiveSignalLookbackMinutes=MathMax(0,MathMin(1440,g_rtNasActiveSignalLookbackMinutes));
   g_rtNasOppositeExitWaitMinutes=MathMax(0,MathMin(5999,g_rtNasOppositeExitWaitMinutes));
}
bool SetRuntimeNasExitModes(bool opEnabled,bool addEnabled)
{
   if(opEnabled&&addEnabled)return false;
   // Disable the competing mode first. A terminal interruption can therefore
   // leave both modes OFF, but can never leave both exit engines active.
   bool opSaved=false,addSaved=false;
   if(opEnabled)
   {
      addSaved=GlobalVariableSet(RuntimeNasAdditionalExitKey(),0.0)>0;
      opSaved=addSaved&&GlobalVariableSet(RuntimeNasExitKey(),1.0)>0;
   }
   else if(addEnabled)
   {
      opSaved=GlobalVariableSet(RuntimeNasExitKey(),0.0)>0;
      addSaved=opSaved&&GlobalVariableSet(RuntimeNasAdditionalExitKey(),1.0)>0;
   }
   else
   {
      opSaved=GlobalVariableSet(RuntimeNasExitKey(),0.0)>0;
      addSaved=GlobalVariableSet(RuntimeNasAdditionalExitKey(),0.0)>0;
   }
   if(!opSaved||!addSaved)
   {
      g_rtNasExitOnOppositeSignal=GlobalVariableCheck(RuntimeNasExitKey())&&GlobalVariableGet(RuntimeNasExitKey())>0.5;
      g_rtNasAdditionalExit=GlobalVariableCheck(RuntimeNasAdditionalExitKey())&&GlobalVariableGet(RuntimeNasAdditionalExitKey())>0.5;
      if(g_rtNasExitOnOppositeSignal&&g_rtNasAdditionalExit)
      {g_rtNasAdditionalExit=false;GlobalVariableSet(RuntimeNasAdditionalExitKey(),0.0);}
      return false;
   }
   g_rtNasExitOnOppositeSignal=opEnabled;
   g_rtNasAdditionalExit=addEnabled;
   return true;
}
bool SetRuntimeNasExit(bool enabled){return SetRuntimeNasExitModes(enabled,false);}
bool SetRuntimeNasLookback(int minutes)
{
   if(minutes<0||minutes>1440)return false;
   if(GlobalVariableSet(RuntimeNasLookbackKey(),(double)minutes)<=0)return false;
   g_rtNasActiveSignalLookbackMinutes=minutes;
   return true;
}
bool SetRuntimeNasExitWait(int minutes)
{
   if(minutes<0||minutes>5999)return false;
   if(GlobalVariableSet(RuntimeNasExitWaitKey(),(double)minutes)<=0)return false;
   g_rtNasOppositeExitWaitMinutes=minutes;
   return true;
}
bool SetRuntimeNasAdditionalExit(bool enabled)
{
   return SetRuntimeNasExitModes(false,enabled);
}
bool RuntimeNasExitEnabled(){return g_rtNasExitOnOppositeSignal||g_rtNasAdditionalExit;}
bool SetRuntimeNasSensitivity(int value)
{
   if(value<1||value>100)return false;
   if(GlobalVariableSet(RuntimeNasSensitivityKey(),(double)value)<=0)return false;
   g_rtNasSensitivity=value;
   return true;
}
bool SetRuntimeNasVolumeFilter(bool enabled)
{
   if(GlobalVariableSet(RuntimeNasVolumeEnabledKey(),enabled?1.0:0.0)<=0)return false;
   g_rtNasVolumeFilter=enabled;
   return true;
}
bool SetRuntimeNasVolumeMultiplier(double value)
{
   if(!MathIsValidNumber(value)||value<0.05||value>200.0)return false;
   double normalized=ClampNasVolumeMultiplier(value);
   if(GlobalVariableSet(RuntimeNasVolumeMultiplierKey(),normalized)<=0)return false;
   g_rtNasVolumeMultiplier=normalized;
   return true;
}
bool SetRuntimeNasFlowVolumeFilter(bool enabled)
{
   if(GlobalVariableSet(RuntimeNasFlowVolumeEnabledKey(),enabled?1.0:0.0)<=0)return false;
   g_rtNasFlowVolumeFilter=enabled;
   return true;
}
bool SetRuntimeNasFlowVolumeMultiplier(double value)
{
   if(!MathIsValidNumber(value)||value<0.05||value>200.0)return false;
   double normalized=ClampNasVolumeMultiplier(value);
   if(GlobalVariableSet(RuntimeNasFlowVolumeMultiplierKey(),normalized)<=0)return false;
   g_rtNasFlowVolumeMultiplier=normalized;
   return true;
}
string RuntimeNasModeLabel()
{
   if(g_rtNasStateGate&&RuntimeNasExitEnabled())return g_rtNasAdditionalExit?"STATE+ADD":"STATE+EXIT";
   if(g_rtNasStateGate)return "STATE GATE";
   if(g_rtNasConfirmation&&RuntimeNasExitEnabled())return g_rtNasAdditionalExit?"ENTRY+ADD":"ENTRY+EXIT";
   if(g_rtNasConfirmation)return "ENTRY ONLY";
   if(g_rtNasAdditionalExit)return "ADD EXIT";
   if(g_rtNasExitOnOppositeSignal)return "EXIT ONLY";
   return "OFF";
}
string NasPendingKey(string field)
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   return "ORB_NASP."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+field;
}
long NasPendingConfigSignature()
{
   long h=17;
   h=(h*131+(long)g_rtSignalTf)%9000000000000000;
   h=(h*131+(long)NasConfirmationTf())%9000000000000000;
   h=(h*131+(long)g_rtEntryMode)%9000000000000000;
   h=(h*131+(g_rtInvertMode?1:0))%9000000000000000;
   h=(h*131+(g_rtUtcMidnightSession?1:0))%9000000000000000;
   h=(h*131+(g_rtFilterAtr?1:0))%9000000000000000;
   h=(h*131+(g_rtFilterVol?1:0))%9000000000000000;
   h=(h*131+(g_rtFilterDay?1:0))%9000000000000000;
   h=(h*131+(g_rtDisplacement?1:0))%9000000000000000;
   h=(h*131+(long)g_rtFvgMode)%9000000000000000;
   h=(h*131+(long)g_rtTargetMode)%9000000000000000;
   h=(h*131+(long)RuntimeTargetLeg())%9000000000000000;
   h=(h*131+(long)g_orbBridgeChannel)%9000000000000000;
   h=(h*131+(long)MathRound(g_rtVolumeMultiplier*10000.0))%9000000000000000;
   h=(h*131+(long)g_rtNasSensitivity)%9000000000000000;
   h=(h*131+(g_rtNasFlowVolumeFilter?1:0))%9000000000000000;
   h=(h*131+(long)MathRound(g_rtNasFlowVolumeMultiplier*10000.0))%9000000000000000;
   h=(h*131+(long)MathMax(1,InpNasAtrRisk))%9000000000000000;
   h=(h*131+(long)MathMax(2,InpNasAtrLen))%9000000000000000;
   h=(h*131+(long)MathMax(0,g_rtNasActiveSignalLookbackMinutes))%9000000000000000;
   for(int i=0;i<ArraySize(g_regimeAllowed);i++)h=(h*131+(g_regimeAllowed[i]?1:0))%9000000000000000;
   h=(h*131+(g_orbRfEnabled?1:0))%9000000000000000;
   for(int i=0;i<ArraySize(g_orbRfBlocked);i++)h=(h*131+(g_orbRfBlocked[i]?1:0))%9000000000000000;
   string of=McOfIdentity();
   for(int i=0;i<StringLen(of);i++)h=(h*131+(long)StringGetCharacter(of,i))%9000000000000000;
   return h;
}
void PersistNasPending()
{
   // Commit marker is written last so a partial terminal write cannot restore
   // an incomplete candidate after restart.
   GlobalVariableSet(NasPendingKey("active"),0.0);
   if(!g_nasPending)return;
   GlobalVariableSet(NasPendingKey("dir"),g_nasPendingDir=="BUY"?1.0:-1.0);
   GlobalVariableSet(NasPendingKey("bar"),(double)g_nasPendingSignalBar);
   GlobalVariableSet(NasPendingKey("accepted"),(double)g_nasPendingAcceptedAt);
   GlobalVariableSet(NasPendingKey("expire"),(double)g_nasPendingExpire);
   GlobalVariableSet(NasPendingKey("close"),g_nasPendingSignalClose);
   GlobalVariableSet(NasPendingKey("cfg"),(double)NasPendingConfigSignature());
   GlobalVariableSet(NasPendingKey("active"),1.0);
}
void ClearNasPending(string reason="")
{
   bool wasPending=g_nasPending;
   string oldDir=g_nasPendingDir;
   GlobalVariableSet(NasPendingKey("active"),0.0);
   g_nasPending=false;g_nasPendingDir="";g_nasPendingSignalBar=0;
   g_nasPendingAcceptedAt=0;g_nasPendingExpire=0;g_nasPendingSignalClose=0.0;
   if(wasPending&&reason!="")
      Audit("nas_confirmation_cleared",oldDir,0,0,0,0,"reason="+reason);
}
bool RestoreNasPending()
{
   if(!g_rtNasConfirmation||!GlobalVariableCheck(NasPendingKey("active"))||GlobalVariableGet(NasPendingKey("active"))<0.5)
      return false;
   if(OwnPositionExists()||g_orbBridgePlanActive)
   {
      ClearNasPending("restore_position_or_bridge_active");
      return false;
   }
   int d=(int)MathRound(GlobalVariableGet(NasPendingKey("dir")));
   datetime bar=(datetime)(long)MathRound(GlobalVariableGet(NasPendingKey("bar")));
   datetime accepted=(datetime)(long)MathRound(GlobalVariableGet(NasPendingKey("accepted")));
   datetime expire=(datetime)(long)MathRound(GlobalVariableGet(NasPendingKey("expire")));
   double closePx=GlobalVariableGet(NasPendingKey("close"));
   long storedCfg=(long)MathRound(GlobalVariableGet(NasPendingKey("cfg")));
   if((d!=1&&d!=-1)||bar<=0||accepted<=0||expire<=accepted||TimeCurrent()>expire||closePx<=0.0
      ||storedCfg!=NasPendingConfigSignature()||expire!=g_tradeEndServer)
   {
      ClearNasPending("restore_invalid_or_expired");
      return false;
   }
   g_nasPending=true;g_nasPendingDir=d>0?"BUY":"SELL";
   g_nasPendingSignalBar=bar;g_nasPendingAcceptedAt=accepted;
   g_nasPendingExpire=expire;g_nasPendingSignalClose=closePx;
   g_lastExecStatus="NAS_WAIT_RESTORED";
   return true;
}
ENUM_TIMEFRAMES NasConfirmationTf()
{
   return (ENUM_TIMEFRAMES)_Period;
}
string NasTimeframeButtonLabel()
{
   return "TF CHART "+TfLabel(NasConfirmationTf());
}
NasSettings BuildOrbNasSettings()
{
   NasSettings s;
   s.sensitivity=ClampNasSensitivity(g_rtNasSensitivity);
   s.rsiLength=MathMax(2,InpNasRsiLength);
   s.atrRisk=MathMax(1,InpNasAtrRisk);
   s.atrLen=MathMax(2,InpNasAtrLen);
   return s;
}
void OrbNasVolumeStats(const MqlRates &rates[],const int signalIndex,
                       double &signalVolume,double &averageVolume)
{
   signalVolume=0.0;averageVolume=0.0;
   const int lookback=20;
   int count=ArraySize(rates);
   if(signalIndex<lookback||signalIndex<0||signalIndex>=count)return;
   signalVolume=(double)rates[signalIndex].tick_volume;
   double sum=0.0;
   int first=MathMax(0,signalIndex-lookback);
   int last=MathMin(count-1,signalIndex-1);
   int samples=0;
   for(int i=last;i>=first;i--)
   {
      if(i<0||i>=count)continue;
      if(rates[i].tick_volume>0)sum+=(double)rates[i].tick_volume;
      samples++;
   }
   if(samples>0)averageVolume=sum/(double)samples;
}
bool OrbNasVolumePolicyAllows(const MqlRates &rates[],const int signalIndex,
                              const bool enabled,const double multiplier,const string policy,
                              string &reason,double &signalVolume,double &averageVolume)
{
   reason="";
   OrbNasVolumeStats(rates,signalIndex,signalVolume,averageVolume);
   if(!enabled)return true;
   if(averageVolume<=0.0){reason=policy+"_VOL_DATA_FAIL_OPEN";return true;}
   double threshold=averageVolume*multiplier;
   if(signalVolume<threshold)
   {
      reason=policy+"_VOL_LOW "+DoubleToString(signalVolume,0)+"<"+DoubleToString(threshold,0);
      return false;
   }
   return true;
}
bool OrbNasStateVolumeFilterAllows(const MqlRates &rates[],const int signalIndex,
                                   string &reason,double &signalVolume,double &averageVolume)
{
   return OrbNasVolumePolicyAllows(rates,signalIndex,g_rtNasVolumeFilter,g_rtNasVolumeMultiplier,"STATE",
      reason,signalVolume,averageVolume);
}
bool OrbNasFlowVolumeFilterAllows(const MqlRates &rates[],const int signalIndex,
                                  string &reason,double &signalVolume,double &averageVolume)
{
   return OrbNasVolumePolicyAllows(rates,signalIndex,g_rtNasFlowVolumeFilter,g_rtNasFlowVolumeMultiplier,"FLOW",
      reason,signalVolume,averageVolume);
}
ORB_NAS_VISUAL_POLICY OrbNasVisualPolicy(const MqlRates &rates[],const int signalIndex,
                                         double &signalVolume,double &averageVolume)
{
   signalVolume=0.0;averageVolume=0.0;
   OrbNasVolumeStats(rates,signalIndex,signalVolume,averageVolume);
   bool stateActive=g_rtNasStateGate;
   bool flowActive=(g_rtNasConfirmation||RuntimeNasExitEnabled());
   if(!stateActive&&!flowActive)return ORB_NAS_VIS_NONE;
   bool statePass=stateActive&&(!g_rtNasVolumeFilter||averageVolume<=0.0
      ||signalVolume>=averageVolume*g_rtNasVolumeMultiplier);
   bool flowPass=flowActive&&(!g_rtNasFlowVolumeFilter||averageVolume<=0.0
      ||signalVolume>=averageVolume*g_rtNasFlowVolumeMultiplier);
   if(statePass&&flowPass)return ORB_NAS_VIS_BOTH;
   if(statePass)return ORB_NAS_VIS_STATE;
   if(flowPass)return ORB_NAS_VIS_FLOW;
   return ORB_NAS_VIS_NONE;
}
bool OrbNasOverlayVolumeFilterAllows(const MqlRates &rates[],const int signalIndex,
                                     string &reason,double &signalVolume,double &averageVolume)
{
   ORB_NAS_VISUAL_POLICY visual=OrbNasVisualPolicy(rates,signalIndex,signalVolume,averageVolume);
   reason=visual==ORB_NAS_VIS_BOTH?"BOTH":(visual==ORB_NAS_VIS_STATE?"STATE":(visual==ORB_NAS_VIS_FLOW?"FLOW":"BLOCKED"));
   return visual!=ORB_NAS_VIS_NONE;
}
bool HistoricalNasVolumePolicyAllows(const int index,const bool enabled,const double multiplier)
{
   if(index<0||index>=ArraySize(g_histNasEvents))return false;
   if(!enabled)return true;
   double averageVolume=g_histNasEvents[index].averageVolume;
   if(averageVolume<=0.0)return true;
   return g_histNasEvents[index].signalVolume>=averageVolume*multiplier;
}
bool HistoricalNasStateEventAllowed(const int index)
{
   return HistoricalNasVolumePolicyAllows(index,g_rtNasVolumeFilter,g_rtNasVolumeMultiplier);
}
bool HistoricalNasFlowEventAllowed(const int index)
{
   return HistoricalNasVolumePolicyAllows(index,g_rtNasFlowVolumeFilter,g_rtNasFlowVolumeMultiplier);
}
ORB_NAS_VISUAL_POLICY HistoricalNasVisualPolicy(const int index)
{
   if(index<0||index>=ArraySize(g_histNasEvents))return ORB_NAS_VIS_NONE;
   bool stateActive=g_rtNasStateGate;
   bool flowActive=(g_rtNasConfirmation||RuntimeNasExitEnabled());
   bool statePass=stateActive&&HistoricalNasStateEventAllowed(index);
   bool flowPass=flowActive&&HistoricalNasFlowEventAllowed(index);
   if(statePass&&flowPass)return ORB_NAS_VIS_BOTH;
   if(statePass)return ORB_NAS_VIS_STATE;
   if(flowPass)return ORB_NAS_VIS_FLOW;
   return ORB_NAS_VIS_NONE;
}
bool HistoricalNasOverlayEventAllowed(const int index)
{
   return HistoricalNasVisualPolicy(index)!=ORB_NAS_VIS_NONE;
}
void RefreshHistoricalNasFilterStats()
{
   g_lastNasRawEventCount=ArraySize(g_histNasEvents);
   g_lastNasAllowedEventCount=0;
   g_lastNasStateAllowedEventCount=0;
   g_lastNasFlowAllowedEventCount=0;
   g_lastNasVolumeMissingCount=0;
   for(int i=0;i<g_lastNasRawEventCount;i++)
   {
      if((g_rtNasVolumeFilter||g_rtNasFlowVolumeFilter)&&g_histNasEvents[i].averageVolume<=0.0)
         g_lastNasVolumeMissingCount++;
      if(HistoricalNasStateEventAllowed(i))g_lastNasStateAllowedEventCount++;
      if(HistoricalNasFlowEventAllowed(i))g_lastNasFlowAllowedEventCount++;
      if(HistoricalNasOverlayEventAllowed(i))g_lastNasAllowedEventCount++;
   }
}
int NasCalcWarmupBars(){return MathMax(300,MathMin(200000,InpNasSignalCalcBars));}
int NasHistoryBars(){return MathMax(300,InpNasHistoryBars);}
void NormalizeOrbNasRates(MqlRates &rates[],const int copied)
{
   if(copied>1&&rates[0].time>rates[copied-1].time)
      ArrayReverse(rates,0,WHOLE_ARRAY);
}
int LoadOrbNasRates(MqlRates &rates[],ENUM_TIMEFRAMES tf,const int barsToCopy)
{
   int copied=CopyRates(_Symbol,tf,0,MathMax(20,barsToCopy),rates);
   if(copied>0)NormalizeOrbNasRates(rates,copied);
   return copied;
}
int LoadOrbNasRatesThrough(MqlRates &rates[],ENUM_TIMEFRAMES tf,datetime throughTime,const int barsToCopy)
{
   if(throughTime<=0)return -1;
   int copied=CopyRates(_Symbol,tf,throughTime,MathMax(20,barsToCopy),rates);
   if(copied>0)NormalizeOrbNasRates(rates,copied);
   return copied;
}
datetime OrbNasSignalAvailableTime(const MqlRates &rates[],const int copied,const int index)
{
   // Match standalone CLOSED mode: the next existing market bar makes the signal causal.
   if(index<0||index+1>=copied)return 0;
   return rates[index+1].time;
}
bool BuildHistoricalNasEventCache(int days,datetime now,string &detail)
{
   detail="NAS_CACHE_OFF";
   if(!g_rtNasConfirmation&&!g_rtNasStateGate&&!RuntimeNasExitEnabled())
   {
      g_histNasCacheActive=true;
      return true;
   }
   ENUM_TIMEFRAMES tf=NasConfirmationTf();int sec=PeriodSeconds(tf);if(sec<=0)sec=60;
   datetime auditStart=now-(datetime)((long)MathMax(1,days)*86400);
   // STATE GATE has no age limit. Retain a causal seed window before the
   // oldest audited ORB so its latest prior NAS transition is not truncated.
   long seedSeconds=g_rtNasStateGate?(long)NasCalcWarmupBars()*sec:
      (long)MathMax(0,g_rtNasActiveSignalLookbackMinutes)*60;
   datetime cutoff=auditStart-(datetime)seedSeconds-sec*2;
   datetime closedBar=iTime(_Symbol,tf,1);
   NasSettings settings=BuildOrbNasSettings();
   bool reusable=g_histNasCacheReady
      &&g_histNasCacheTf==tf
      &&g_histNasCacheSensitivity==settings.sensitivity
      &&g_histNasCacheRsiLength==settings.rsiLength
      &&g_histNasCacheAtrRisk==settings.atrRisk
      &&g_histNasCacheAtrLen==settings.atrLen
      &&g_histNasCacheFrom>0&&g_histNasCacheFrom<=cutoff
      &&g_histNasCacheEventFrom>0&&g_histNasCacheEventFrom<=cutoff
      &&g_histNasCacheClosedBar>0&&g_histNasCacheClosedBar==closedBar;
   if(reusable)
   {
      g_histNasCacheActive=true;
      RefreshHistoricalNasFilterStats();
      detail="NAS_CACHE_REUSE bars="+IntegerToString(g_histNasCacheCopiedBars)
         +" event_from="+FmtTime(g_histNasCacheEventFrom)
         +" allowed_events="+IntegerToString(g_lastNasAllowedEventCount)
         +" state_allowed="+IntegerToString(g_lastNasStateAllowedEventCount)
         +" flow_allowed="+IntegerToString(g_lastNasFlowAllowedEventCount)
         +" raw_events="+IntegerToString(g_lastNasRawEventCount)
         +" vol_missing="+IntegerToString(g_lastNasVolumeMissingCount);
      return true;
   }
   g_histNasCacheReady=false;
   g_histNasCacheActive=false;
   g_histNasCacheEventFrom=0;
   ArrayResize(g_histNasEvents,0);
   g_histNasCacheCopiedBars=0;
   long windowBars=(long)MathCeil((double)MathMax(1,days)*86400.0/(double)sec);
   int requested=(int)MathMin((long)2147480000,
      MathMax((long)NasHistoryBars(),windowBars+(long)NasCalcWarmupBars()+300));
   MqlRates rates[];int copied=LoadOrbNasRates(rates,tf,requested);
   if(copied<20)
   {
      detail="NAS_CACHE_NO_DATA bars="+IntegerToString(copied);
      g_histNasCacheActive=false;
      return false;
   }
   if(rates[0].time>cutoff+3*86400)
   {
      detail="NAS_CACHE_PARTIAL first="+FmtTime(rates[0].time)+" required="+FmtTime(cutoff);
      g_histNasCacheActive=false;
      return false;
   }
   NasPoint points[];
   if(NAS_Calculate(rates,copied,settings,points)!=copied)
   {
      detail="NAS_CACHE_CALC_FAIL";
      g_histNasCacheActive=false;
      return false;
   }
   for(int i=1;i<=copied-2;i++)
   {
      bool buy=points[i].buy&&!points[i].sell;
      bool sell=points[i].sell&&!points[i].buy;
      if(!buy&&!sell)continue;
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(available<=0||available<cutoff||available>now)continue;
      double signalVolume=0.0,averageVolume=0.0;
      OrbNasVolumeStats(rates,i,signalVolume,averageVolume);
      int n=ArraySize(g_histNasEvents);ArrayResize(g_histNasEvents,n+1,1024);
      g_histNasEvents[n].dir=buy?"BUY":"SELL";
      g_histNasEvents[n].barTime=rates[i].time;
      g_histNasEvents[n].availableTime=available;
      g_histNasEvents[n].closePrice=rates[i].close;
      g_histNasEvents[n].highPrice=rates[i].high;
      g_histNasEvents[n].lowPrice=rates[i].low;
      g_histNasEvents[n].signalVolume=signalVolume;
      g_histNasEvents[n].averageVolume=averageVolume;
   }
   g_histNasCacheCopiedBars=copied;
   g_histNasCacheFrom=rates[0].time;
   g_histNasCacheEventFrom=cutoff;
   g_histNasCacheClosedBar=closedBar;
   g_histNasCacheTf=tf;
   g_histNasCacheSensitivity=settings.sensitivity;
   g_histNasCacheRsiLength=settings.rsiLength;
   g_histNasCacheAtrRisk=settings.atrRisk;
   g_histNasCacheAtrLen=settings.atrLen;
   g_histNasCacheReady=true;
   g_histNasCacheActive=true;
   RefreshHistoricalNasFilterStats();
   detail="NAS_CACHE_OK bars="+IntegerToString(copied)
      +" event_from="+FmtTime(g_histNasCacheEventFrom)
      +" allowed_events="+IntegerToString(g_lastNasAllowedEventCount)
      +" state_allowed="+IntegerToString(g_lastNasStateAllowedEventCount)
      +" flow_allowed="+IntegerToString(g_lastNasFlowAllowedEventCount)
      +" raw_events="+IntegerToString(g_lastNasRawEventCount)
      +" vol_missing="+IntegerToString(g_lastNasVolumeMissingCount);
   return true;
}
int FirstNasEventAtOrAfter(const datetime at)
{
   int lo=0,hi=ArraySize(g_histNasEvents);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if(g_histNasEvents[mid].availableTime<at)lo=mid+1;
      else hi=mid;
   }
   return lo;
}
int FirstNasEventAfter(const datetime at)
{
   int lo=0,hi=ArraySize(g_histNasEvents);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if(g_histNasEvents[mid].availableTime<=at)lo=mid+1;
      else hi=mid;
   }
   return lo;
}
int LastAllowedNasEventAtOrBefore(const datetime at)
{
   for(int i=FirstNasEventAfter(at)-1;i>=0;i--)
      if(HistoricalNasStateEventAllowed(i))return i;
   return -1;
}
bool FindNasStateGateCached(string dir,datetime orbAcceptedAt,
                            datetime &stateBar,datetime &stateAt,double &stateClose,
                            string &detail)
{
   stateBar=0;stateAt=0;stateClose=0.0;detail="";
   int index=LastAllowedNasEventAtOrBefore(orbAcceptedAt);
   if(index<0)
   {
      detail="NAS_STATE_NONE orb_at="+FmtTime(orbAcceptedAt);
      return false;
   }
   stateBar=g_histNasEvents[index].barTime;
   stateAt=g_histNasEvents[index].availableTime;
   stateClose=g_histNasEvents[index].closePrice;
   string stateDir=g_histNasEvents[index].dir;
   int ageMinutes=(int)MathMax(0,(orbAcceptedAt-stateAt)/60);
   detail="NAS_STATE_CACHE state="+stateDir+" required="+dir
      +" age_min="+IntegerToString(ageMinutes)+" event="+FmtTime(stateAt)
      +" orb_at="+FmtTime(orbAcceptedAt);
   return stateDir==dir;
}
bool FindNasStateGate(string dir,datetime orbAcceptedAt,
                      datetime &stateBar,datetime &stateAt,double &stateClose,
                      string &detail)
{
   stateBar=0;stateAt=0;stateClose=0.0;detail="";
   if((dir!="BUY"&&dir!="SELL")||orbAcceptedAt<=0)return false;
   ENUM_TIMEFRAMES tf=NasConfirmationTf();
   datetime closedBar=iTime(_Symbol,tf,1);
   int sec=PeriodSeconds(tf);if(sec<=0)sec=60;
   datetime requiredStateFrom=orbAcceptedAt-(datetime)((long)NasCalcWarmupBars()*sec);
   NasSettings settings=BuildOrbNasSettings();
   if((g_histNasCacheActive||g_histNasCacheReady)
      &&g_histNasCacheTf==tf
      &&g_histNasCacheSensitivity==settings.sensitivity
      &&g_histNasCacheRsiLength==settings.rsiLength
      &&g_histNasCacheAtrRisk==settings.atrRisk
      &&g_histNasCacheAtrLen==settings.atrLen
      &&g_histNasCacheEventFrom>0&&g_histNasCacheEventFrom<=requiredStateFrom
      &&g_histNasCacheClosedBar>0&&g_histNasCacheClosedBar==closedBar)
      return FindNasStateGateCached(dir,orbAcceptedAt,stateBar,stateAt,stateClose,detail);

   MqlRates rates[];
   int copied=LoadOrbNasRatesThrough(rates,tf,orbAcceptedAt,NasHistoryBars());
   if(copied<20)
   {detail="NAS_STATE_NO_DATA tf="+TfLabel(tf)+" bars="+IntegerToString(copied);return false;}
   NasPoint points[];
   if(NAS_Calculate(rates,copied,settings,points)!=copied)
   {detail="NAS_STATE_CALC_FAIL";return false;}
   string stateDir="";
   for(int i=1;i<=copied-2;i++)
   {
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(available<=0||available>orbAcceptedAt)continue;
      if(points[i].buy==points[i].sell)continue;
      string volumeReason="";double signalVolume=0.0,averageVolume=0.0;
      if(!OrbNasStateVolumeFilterAllows(rates,i,volumeReason,signalVolume,averageVolume))continue;
      stateDir=points[i].buy?"BUY":"SELL";
      stateBar=rates[i].time;stateAt=available;stateClose=rates[i].close;
   }
   if(stateDir=="")
   {detail="NAS_STATE_NONE tf="+TfLabel(tf)+" orb_at="+FmtTime(orbAcceptedAt);return false;}
   int ageMinutes=(int)MathMax(0,(orbAcceptedAt-stateAt)/60);
   detail="NAS_STATE state="+stateDir+" required="+dir
      +" age_min="+IntegerToString(ageMinutes)+" event="+FmtTime(stateAt)
      +" orb_at="+FmtTime(orbAcceptedAt);
   return stateDir==dir;
}
bool FindNasConfirmationCached(string dir,datetime orbAcceptedAt,datetime latestAvailable,
                               datetime &confirmBar,datetime &confirmAt,double &confirmClose,
                               bool &usedActiveSignal,string &detail)
{
   confirmBar=0;confirmAt=0;confirmClose=0.0;usedActiveSignal=false;detail="";
   int lookbackMinutes=MathMax(0,g_rtNasActiveSignalLookbackMinutes);
   datetime activeStart=orbAcceptedAt-(datetime)(lookbackMinutes*60);
   int latestState=-1;
   for(int i=FirstNasEventAtOrAfter(activeStart);i<ArraySize(g_histNasEvents);i++)
   {
      if(!HistoricalNasFlowEventAllowed(i))continue;
      datetime at=g_histNasEvents[i].availableTime;
      if(at<activeStart)continue;
      if(at>orbAcceptedAt)break;
      latestState=i;
   }
   if(lookbackMinutes>0&&latestState>=0&&g_histNasEvents[latestState].dir==dir)
   {
      confirmBar=g_histNasEvents[latestState].barTime;confirmAt=orbAcceptedAt;
      confirmClose=g_histNasEvents[latestState].closePrice;usedActiveSignal=true;
      detail="NAS_ACTIVE_CACHE_OK dir="+dir+" event="+FmtTime(g_histNasEvents[latestState].availableTime)
         +" orb_at="+FmtTime(orbAcceptedAt);
      return true;
   }
   for(int i=FirstNasEventAtOrAfter(orbAcceptedAt);i<ArraySize(g_histNasEvents);i++)
   {
      if(!HistoricalNasFlowEventAllowed(i))continue;
      datetime at=g_histNasEvents[i].availableTime;
      if(at<orbAcceptedAt)continue;
      if(at>latestAvailable)break;
      if(g_histNasEvents[i].dir!=dir)continue;
      confirmBar=g_histNasEvents[i].barTime;confirmAt=at;confirmClose=g_histNasEvents[i].closePrice;
      detail="NAS_CACHE_OK dir="+dir+" at="+FmtTime(at);
      return true;
   }
   detail="NAS_CACHE_WAIT dir="+dir+" orb_at="+FmtTime(orbAcceptedAt)+" until="+FmtTime(latestAvailable);
   return false;
}
bool FindNasConfirmation(string dir,datetime orbAcceptedAt,datetime latestAvailable,
                         datetime &confirmBar,datetime &confirmAt,double &confirmClose,
                         bool &usedActiveSignal,string &detail)
{
   confirmBar=0;confirmAt=0;confirmClose=0.0;usedActiveSignal=false;detail="";
   if((dir!="BUY"&&dir!="SELL")||orbAcceptedAt<=0||latestAvailable<orbAcceptedAt)return false;
   if(g_histNasCacheActive)
      return FindNasConfirmationCached(dir,orbAcceptedAt,latestAvailable,
         confirmBar,confirmAt,confirmClose,usedActiveSignal,detail);
   ENUM_TIMEFRAMES tf=NasConfirmationTf();
   int sec=PeriodSeconds(tf);if(sec<=0)sec=60;
   int lookbackMinutes=MathMax(0,g_rtNasActiveSignalLookbackMinutes);
   datetime activeStart=orbAcceptedAt-(datetime)(lookbackMinutes*60);
   MqlRates rates[];
   int copied=LoadOrbNasRatesThrough(rates,tf,latestAvailable,NasCalcWarmupBars());
   if(copied<20){detail="NAS_NO_DATA tf="+TfLabel(tf)+" bars="+IntegerToString(copied);return false;}
   NasPoint points[];
   if(NAS_Calculate(rates,copied,BuildOrbNasSettings(),points)!=copied)
   {detail="NAS_CALC_FAIL";return false;}

   // NAS signals are directional state transitions. The latest transition in
   // the lookback window is authoritative; an intervening opposite event
   // invalidates an older same-direction event.
   string activeDir="";datetime activeBar=0,activeAt=0;double activeClose=0.0;
   for(int i=1;i<=copied-2;i++)
   {
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(available<activeStart||available>orbAcceptedAt)continue;
      if(points[i].buy==points[i].sell)continue;
      string volumeReason="";double signalVolume=0.0,averageVolume=0.0;
      if(!OrbNasFlowVolumeFilterAllows(rates,i,volumeReason,signalVolume,averageVolume))continue;
      activeDir=points[i].buy?"BUY":"SELL";
      activeBar=rates[i].time;activeAt=available;activeClose=rates[i].close;
   }
   if(lookbackMinutes>0&&activeDir==dir)
   {
      confirmBar=activeBar;confirmAt=orbAcceptedAt;confirmClose=activeClose;usedActiveSignal=true;
      int ageMinutes=(int)MathMax(0,(orbAcceptedAt-activeAt)/60);
      detail="NAS_ACTIVE_OK tf="+TfLabel(tf)+" dir="+activeDir
         +" age_min="+IntegerToString(ageMinutes)+" event="+FmtTime(activeAt)
         +" orb_at="+FmtTime(orbAcceptedAt);
      return true;
   }

   // No valid active state existed when ORB was accepted. Preserve the prior
   // behavior and wait for the first fresh matching NAS transition.
   for(int i=1;i<=copied-2;i++)
   {
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(available<orbAcceptedAt||available>latestAvailable)continue;
      bool match=(dir=="BUY"?(points[i].buy&&!points[i].sell):(points[i].sell&&!points[i].buy));
      if(!match)continue;
      string volumeReason="";double signalVolume=0.0,averageVolume=0.0;
      if(!OrbNasFlowVolumeFilterAllows(rates,i,volumeReason,signalVolume,averageVolume))continue;
      confirmBar=rates[i].time;confirmAt=available;confirmClose=rates[i].close;
      detail="NAS_OK tf="+TfLabel(tf)+" bar="+FmtTime(confirmBar)+" at="+FmtTime(confirmAt);
      return true;
   }
   string activeState=(activeDir==""?"NONE":activeDir);
   detail="NAS_WAIT tf="+TfLabel(tf)+" active="+activeState+" orb_at="+FmtTime(orbAcceptedAt)
      +" until="+FmtTime(latestAvailable);
   return false;
}
void SetNasPending(string dir,datetime signalBar,double signalClose)
{
   g_nasPending=true;g_nasPendingDir=dir;g_nasPendingSignalBar=signalBar;
   g_nasPendingAcceptedAt=OrbSignalAvailableTime(signalBar);
   g_nasPendingExpire=g_tradeEndServer;g_nasPendingSignalClose=signalClose;
   PersistNasPending();
   g_lastExecStatus="NAS_WAIT_"+dir;
   Audit("nas_confirmation_pending",dir,0,signalClose,0,0,
      "accepted_at="+FmtTime(g_nasPendingAcceptedAt)+" expire="+FmtTime(g_nasPendingExpire)
      +" tf="+TfLabel(NasConfirmationTf())+" active_lookback_min="+IntegerToString(MathMax(0,g_rtNasActiveSignalLookbackMinutes)));
}
string NasLifecycleKey(string field)
{
   return "ORB_NASL."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +OrbProSafeToken(_Symbol)+"."+OrbProTf(g_rtSignalTf)+".C"+IntegerToString(g_orbBridgeChannel)+"."+field;
}
void PersistNasManagedLifecycle()
{
   GlobalVariableSet(NasLifecycleKey("active"),0.0);
   if(!g_nasManagedLifecycle)return;
   GlobalVariableSet(NasLifecycleKey("raw_dir"),g_nasManagedRawDir=="BUY"?1.0:-1.0);
   GlobalVariableSet(NasLifecycleKey("exec_dir"),(double)g_nasManagedExecDir);
   GlobalVariableSet(NasLifecycleKey("start"),(double)g_nasManagedStartAt);
   GlobalVariableSet(NasLifecycleKey("scan"),(double)g_nasManagedLastScanAt);
   GlobalVariableSet(NasLifecycleKey("bridge"),g_nasManagedBridgePublished?1.0:0.0);
   GlobalVariableSet(NasLifecycleKey("close_pending"),g_nasManagedClosePending?1.0:0.0);
   GlobalVariableSet(NasLifecycleKey("opposite_at"),(double)g_nasManagedOppositeAt);
   GlobalVariableSet(NasLifecycleKey("active"),1.0); // Commit marker last.
}
void ClearNasManagedLifecycle(string reason="")
{
   bool wasActive=g_nasManagedLifecycle;
   string rawDir=g_nasManagedRawDir;
   g_nasManagedLifecycle=false;g_nasManagedRawDir="";g_nasManagedExecDir=0;
   g_nasManagedStartAt=0;g_nasManagedLastScanAt=0;g_nasManagedBridgePublished=false;
   g_nasManagedClosePending=false;g_nasManagedOppositeAt=0;
   string fields[]={"active","raw_dir","exec_dir","start","scan","bridge","close_pending","opposite_at"};
   for(int i=0;i<ArraySize(fields);i++)GlobalVariableDel(NasLifecycleKey(fields[i]));
   if(wasActive&&reason!="")Audit("nas_lifecycle_cleared",rawDir,0,0,0,0,"reason="+reason);
}
void StartNasManagedLifecycle(string basisDir,int execDir,datetime startAt,bool bridgePublished)
{
   if((basisDir!="BUY"&&basisDir!="SELL")||(execDir!=1&&execDir!=-1)||startAt<=0)return;
   if(!g_nasManagedLifecycle)
   {
      g_nasManagedLifecycle=true;g_nasManagedRawDir=basisDir;g_nasManagedExecDir=execDir;
      g_nasManagedStartAt=startAt;g_nasManagedLastScanAt=startAt;
      g_nasManagedClosePending=false;g_nasManagedOppositeAt=0;
   }
   g_nasManagedBridgePublished=(g_nasManagedBridgePublished||bridgePublished);
   PersistNasManagedLifecycle();
}
void RestoreNasManagedLifecycle()
{
   if(!GlobalVariableCheck(NasLifecycleKey("active"))||GlobalVariableGet(NasLifecycleKey("active"))<0.5)return;
   int raw=(int)MathRound(GlobalVariableGet(NasLifecycleKey("raw_dir")));
   int exec=(int)MathRound(GlobalVariableGet(NasLifecycleKey("exec_dir")));
   datetime started=(datetime)(long)MathRound(GlobalVariableGet(NasLifecycleKey("start")));
   bool closePending=GlobalVariableCheck(NasLifecycleKey("close_pending"))&&GlobalVariableGet(NasLifecycleKey("close_pending"))>0.5;
   if((raw!=1&&raw!=-1)||(exec!=1&&exec!=-1)||started<=0)
   {ClearNasManagedLifecycle("restore_invalid");return;}
   if(!closePending&&!OwnPositionExists()&&!g_orbBridgePlanActive)
   {ClearNasManagedLifecycle("restore_no_lifecycle");return;}
   // Older builds persisted the raw ORB direction here. The execution
   // direction is authoritative for "opposite to the open trade" semantics.
   g_nasManagedLifecycle=true;g_nasManagedRawDir=exec>0?"BUY":"SELL";g_nasManagedExecDir=exec;
   g_nasManagedStartAt=started;
   g_nasManagedLastScanAt=GlobalVariableCheck(NasLifecycleKey("scan"))?(datetime)(long)MathRound(GlobalVariableGet(NasLifecycleKey("scan"))):started;
   g_nasManagedBridgePublished=GlobalVariableCheck(NasLifecycleKey("bridge"))&&GlobalVariableGet(NasLifecycleKey("bridge"))>0.5;
   g_nasManagedClosePending=closePending;
   g_nasManagedOppositeAt=GlobalVariableCheck(NasLifecycleKey("opposite_at"))?(datetime)(long)MathRound(GlobalVariableGet(NasLifecycleKey("opposite_at"))):0;
   // A persisted latch must be strictly newer than this trade. Older builds
   // could retain a pre-entry NAS state across a restart or wait edit.
   if(g_nasManagedOppositeAt>0&&g_nasManagedOppositeAt<=g_nasManagedStartAt)
   {
      g_nasManagedOppositeAt=0;g_nasManagedClosePending=false;
      if(g_nasManagedLastScanAt<g_nasManagedStartAt)g_nasManagedLastScanAt=g_nasManagedStartAt;
      PersistNasManagedLifecycle();
      Audit("nas_pre_entry_latch_discarded","",0,0,0,0,"source=restore trade_start="+FmtTime(g_nasManagedStartAt));
   }
}
bool FindNasTransitionAfter(string wantedDir,datetime afterExclusive,datetime latestAvailable,
                            datetime &eventBar,datetime &eventAt,double &eventClose,string &detail)
{
   eventBar=0;eventAt=0;eventClose=0.0;detail="";
   if((wantedDir!="BUY"&&wantedDir!="SELL")||afterExclusive<=0||latestAvailable<=afterExclusive)return false;
   if(g_histNasCacheActive)
   {
      for(int i=FirstNasEventAfter(afterExclusive);i<ArraySize(g_histNasEvents);i++)
      {
         if(!HistoricalNasFlowEventAllowed(i))continue;
         datetime at=g_histNasEvents[i].availableTime;
         if(at>latestAvailable)break;
         if(g_histNasEvents[i].dir!=wantedDir)continue;
         eventBar=g_histNasEvents[i].barTime;eventAt=at;eventClose=g_histNasEvents[i].closePrice;
         detail="NAS_OPPOSITE_CACHE dir="+wantedDir+" at="+FmtTime(at);
         return true;
      }
      return false;
   }
   ENUM_TIMEFRAMES tf=NasConfirmationTf();int sec=PeriodSeconds(tf);if(sec<=0)sec=60;
   MqlRates rates[];int copied=LoadOrbNasRatesThrough(rates,tf,latestAvailable,NasCalcWarmupBars());
   if(copied<20){detail="NAS_EXIT_NO_DATA bars="+IntegerToString(copied);return false;}
   NasPoint points[];
   if(NAS_Calculate(rates,copied,BuildOrbNasSettings(),points)!=copied){detail="NAS_EXIT_CALC_FAIL";return false;}
   for(int i=1;i<=copied-2;i++)
   {
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(available<=afterExclusive||available>latestAvailable)continue;
      bool match=wantedDir=="BUY"?(points[i].buy&&!points[i].sell):(points[i].sell&&!points[i].buy);
      if(!match)continue;
      string volumeReason="";double signalVolume=0.0,averageVolume=0.0;
      if(!OrbNasFlowVolumeFilterAllows(rates,i,volumeReason,signalVolume,averageVolume))continue;
      eventBar=rates[i].time;eventAt=available;eventClose=rates[i].close;
      detail="NAS_OPPOSITE tf="+TfLabel(tf)+" dir="+wantedDir+" bar="+FmtTime(eventBar)+" at="+FmtTime(eventAt);
      return true;
   }
   return false;
}
bool FindLatestNasSignalAfter(datetime afterExclusive,datetime latestAvailable,
                              string &eventDir,datetime &eventBar,datetime &eventAt,double &eventClose,string &detail)
{
   eventDir="";eventBar=0;eventAt=0;eventClose=0.0;detail="";
   if(afterExclusive<=0||latestAvailable<=afterExclusive)return false;
   if(g_histNasCacheActive)
   {
      int latest=-1;
      for(int i=FirstNasEventAfter(afterExclusive);i<ArraySize(g_histNasEvents);i++)
      {
         if(!HistoricalNasFlowEventAllowed(i))continue;
         datetime at=g_histNasEvents[i].availableTime;
         if(at>latestAvailable)break;
         latest=i;
      }
      if(latest<0)return false;
      eventDir=g_histNasEvents[latest].dir;eventBar=g_histNasEvents[latest].barTime;
      eventAt=g_histNasEvents[latest].availableTime;eventClose=g_histNasEvents[latest].closePrice;
      detail="NAS_STATE_CACHE dir="+eventDir+" at="+FmtTime(eventAt);
      return true;
   }
   ENUM_TIMEFRAMES tf=NasConfirmationTf();
   MqlRates rates[];int copied=LoadOrbNasRatesThrough(rates,tf,latestAvailable,NasCalcWarmupBars());
   if(copied<20){detail="NAS_STATE_NO_DATA bars="+IntegerToString(copied);return false;}
   NasPoint points[];
   if(NAS_Calculate(rates,copied,BuildOrbNasSettings(),points)!=copied){detail="NAS_STATE_CALC_FAIL";return false;}
   for(int i=1;i<=copied-2;i++)
   {
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(available<=afterExclusive||available>latestAvailable)continue;
      bool buy=(points[i].buy&&!points[i].sell),sell=(points[i].sell&&!points[i].buy);
      if(!buy&&!sell)continue;
      string volumeReason="";double signalVolume=0.0,averageVolume=0.0;
      if(!OrbNasFlowVolumeFilterAllows(rates,i,volumeReason,signalVolume,averageVolume))continue;
      eventDir=buy?"BUY":"SELL";eventBar=rates[i].time;eventAt=available;eventClose=rates[i].close;
   }
   if(eventAt<=0)return false;
   detail="NAS_STATE tf="+TfLabel(tf)+" dir="+eventDir+" bar="+FmtTime(eventBar)+" at="+FmtTime(eventAt);
   return true;
}
double ClampVolumeMultiplier(double value){return NormalizeDouble(MathMax(0.05,MathMin(20.0,value)),4);}
string RuntimeVolumeMultiplierKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   int inputBasis=(int)MathRound(ClampVolumeMultiplier(InpVolumeMultiplier)*10000.0);
   return "ORB_VOLX."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+IntegerToString(inputBasis);
}
void LoadRuntimeVolumeMultiplier()
{
   g_rtVolumeMultiplier=ClampVolumeMultiplier(InpVolumeMultiplier);
   string key=RuntimeVolumeMultiplierKey();
   if(GlobalVariableCheck(key))g_rtVolumeMultiplier=ClampVolumeMultiplier(GlobalVariableGet(key));
}
bool SetRuntimeVolumeMultiplier(double value)
{
   if(value<0.05||value>20.0)return false;
   double normalized=ClampVolumeMultiplier(value);
   if(GlobalVariableSet(RuntimeVolumeMultiplierKey(),normalized)<=0)return false;
   g_rtVolumeMultiplier=normalized;
   return true;
}
void ResetWeekdayAuditStats()
{
   for(int dow=0;dow<7;dow++){g_weekdayWins[dow]=0;g_weekdayLosses[dow]=0;}
}
string OrbWeekdayAuditText(int dow,string name)
{
   if(dow<1||dow>5)return name+" 0W 0L WR 0.0%";
   int w=g_weekdayWins[dow],l=g_weekdayLosses[dow],resolved=w+l;
   double wr=resolved>0?(double)w/(double)resolved*100.0:0.0;
   return name+" "+IntegerToString(w)+"W "+IntegerToString(l)+"L WR "+DoubleToString(wr,1)+"%";
}
color OrbWeekdayAuditColor(int dow)
{
   if(dow<1||dow>5)return C'184,196,210';
   int w=g_weekdayWins[dow],l=g_weekdayLosses[dow];
   if(w+l<=0)return C'145,160,180';
   if(w>l)return C'80,255,180';
   if(w<l)return C'255,95,140';
   return C'255,204,82';
}
double NormalizePrice(double p){return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}
double NormalizeVolume(double v){double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(mn<=0)mn=0.01;if(mx<=0)mx=100;if(InpMaxLot>0)mx=MathMin(mx,InpMaxLot);if(st<=0)st=mn;v=MathMax(mn,MathMin(mx,v));v=MathFloor(v/st+1e-7)*st;return NormalizeDouble(MathMax(mn,v),2);}
double TickSize(){double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(ts<=0)ts=SymbolInfoDouble(_Symbol,SYMBOL_POINT);return ts>0?ts:0.00001;}
double NormalizeTradePrice(double p){double ts=TickSize();return NormalizePrice(MathRound(p/ts)*ts);}
double MinStopDistance(){double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=TickSize();long st=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);long fr=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);return MathMax((double)MathMax(st,fr)*pt,TickSize());}
double ValuePerPriceUnitPerLot(){double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);if(ts<=0)ts=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(ts<=0||tv<=0)return 0;return tv/ts;}
bool ManagedRiskMode(){return g_ftmoMode||g_riskLotOnlyMode;}
string RuntimeRiskModeLabel(){if(FixedReferenceRiskMode())return "FIXED_REF";if(g_ftmoMode)return "FTMO";if(g_riskLotOnlyMode)return "RISKLOT";return "NORMAL";}
bool FixedReferenceRiskMode(){return InpRiskCapitalMode==ORB_RISK_FIXED_REFERENCE;}
double RiskSizingCapital(){return FixedReferenceRiskMode()?(InpFixedRiskReferenceCapital>0.0?InpFixedRiskReferenceCapital:0.0):MathMax(0.0,AccountInfoDouble(ACCOUNT_EQUITY));}
double RiskReferenceCapitalForBridge(){return FixedReferenceRiskMode()?MathMax(0.0,InpFixedRiskReferenceCapital):0.0;}
string RiskCapitalBasisCode(){return FixedReferenceRiskMode()?"FIXED_REFERENCE":"CURRENT_EQUITY";}
bool RiskEnabled(){return NativeBalanceEnabled()||InpAccountRiskEnabled||ManagedRiskMode()||FixedReferenceRiskMode();}
double ClampRiskPerTradePct(double value){return NormalizeDouble(MathMax(0.01,MathMin(100.0,value)),4);}
string RuntimeRiskPctKey()
{
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
   int inputBasis=(int)MathRound(ClampRiskPerTradePct(InpRiskPerTradePct)*10000.0);
   return "ORB_RISK."+StringFormat("%I64d",login)+"."+StringFormat("%I64d",ChartID())+"."+IntegerToString(inputBasis);
}
void LoadRuntimeRiskPct()
{
   g_rtRiskPerTradePct=ClampRiskPerTradePct(InpRiskPerTradePct);
   string key=RuntimeRiskPctKey();
   if(GlobalVariableCheck(key))
   {
      double saved=GlobalVariableGet(key);
      if(MathIsValidNumber(saved)&&saved>=0.01&&saved<=100.0)
         g_rtRiskPerTradePct=ClampRiskPerTradePct(saved);
   }
}
bool SetRuntimeRiskPct(double value)
{
   if(!MathIsValidNumber(value)||value<0.01||value>100.0)return false;
   g_rtRiskPerTradePct=ClampRiskPerTradePct(value);
   return GlobalVariableSet(RuntimeRiskPctKey(),g_rtRiskPerTradePct)>0;
}
double EffRiskPerTradePct(){return ClampRiskPerTradePct(g_rtRiskPerTradePct);}
double AccountRiskBudgetMoney(){double capital=RiskSizingCapital();return capital>0.0?capital*MathMax(0.01,EffRiskPerTradePct())/100.0:0.0;}
double RiskBudgetMoney(){return NativeBalanceEnabled()?NativeBalanceBudget(EffRiskPerTradePct()):AccountRiskBudgetMoney();}
double EffAtrExposurePct(){return ManagedRiskMode()?2.0:InpAtrExposurePct;}
double EffMaxPortfolioPct(){return g_ftmoMode?4.0:InpMaxPortfolioPct;}
double EffDailyLossLimitPct(){return g_ftmoMode?5.0:InpDailyLossLimitPct;}
double EffMaxDrawdownPct(){return g_ftmoMode?10.0:InpMaxDrawdownPct;}
double EffMaxMarginUsagePct(){return g_ftmoMode?40.0:InpMaxMarginUsagePct;}
double CalculateLot(double entry,double sl){if(!InpUseAutoRiskLot&&!ManagedRiskMode()&&!FixedReferenceRiskMode()&&!NativeBalanceEnabled())return NormalizeVolume(InpFixedLot);double rd=MathAbs(entry-sl);double vpu=ValuePerPriceUnitPerLot();double rm=RiskBudgetMoney();if(rd<=0||vpu<=0||rm<=0)return FixedReferenceRiskMode()?0.0:NormalizeVolume(InpFixedLot);return NormalizeVolume(rm/(rd*vpu));}
int CurrentSpreadPoints(){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return 0;double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)return 0;return(int)MathRound((t.ask-t.bid)/pt);}
bool SpreadAllowed(){if(InpMaxSpreadPoints<=0)return true;return CurrentSpreadPoints()<=InpMaxSpreadPoints;}
double NormalizeLegVolume(double total,int legs){double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);if(st<=0)st=0.01;if(mn<=0)mn=0.01;double leg=MathFloor(total/(double)legs/st+1e-7)*st;return NormalizeDouble(leg,8)<mn?0:NormalizeDouble(leg,8);}
string TfLabel(ENUM_TIMEFRAMES tf){if(tf==PERIOD_M1)return "M1";if(tf==PERIOD_M5)return "M5";if(tf==PERIOD_M15)return "M15";return EnumToString(tf);}
ENUM_TIMEFRAMES CycleTf(ENUM_TIMEFRAMES current){if(current==PERIOD_M1)return PERIOD_M5;if(current==PERIOD_M5)return PERIOD_M15;return PERIOD_M1;}
int ClampTargetLeg(int leg)
{
   if(leg==(int)ORB_TARGET_CUSTOM)return leg;
   if(leg==(int)ORB_TARGET_R075||(leg>=(int)ORB_TARGET_R350&&leg<=(int)ORB_TARGET_R500)
      ||(leg>=(int)ORB_TARGET_R005&&leg<=(int)ORB_TARGET_R095))return leg;
   return MathMax(1,MathMin(6,leg));
}
double LegR(int leg)
{
   if(leg==(int)ORB_TARGET_CUSTOM)return g_rtCustomR;
   if(leg>=(int)ORB_TARGET_R005&&leg<=(int)ORB_TARGET_R045)
      return 0.05*(double)(leg-(int)ORB_TARGET_R005+1);
   if(leg>=(int)ORB_TARGET_R055&&leg<=(int)ORB_TARGET_R070)
      return 0.55+0.05*(double)(leg-(int)ORB_TARGET_R055);
   if(leg>=(int)ORB_TARGET_R080&&leg<=(int)ORB_TARGET_R095)
      return 0.80+0.05*(double)(leg-(int)ORB_TARGET_R080);
   if(leg==(int)ORB_TARGET_R075)return MathMax(0.1,InpTp075R);
   if(leg<=1)return MathMax(0.1,InpTp1R);
   if(leg==2)return MathMax(0.1,InpTp2R);
   if(leg==3)return MathMax(0.1,InpTp3R);
   if(leg==4)return MathMax(0.1,InpTp4R);
   if(leg==5)return MathMax(0.1,InpTp5R);
   if(leg==6)return MathMax(0.1,InpTp6R);
   if(leg==(int)ORB_TARGET_R350)return MathMax(0.1,InpTp35R);
   if(leg==(int)ORB_TARGET_R400)return MathMax(0.1,InpTp40R);
   if(leg==(int)ORB_TARGET_R450)return MathMax(0.1,InpTp45R);
   return MathMax(0.1,InpTp50R);
}
int RuntimeTargetLeg(){return ClampTargetLeg(g_rtTargetLeg);}
double RuntimeTargetR(){return LegR(RuntimeTargetLeg());}
double RuntimeEffectiveTargetR()
{
   double sourceR=RuntimeTargetR();
   if(!g_rtInvertMode)return sourceR;
   if(g_rtTargetMode!=ORB_TARGET_R_LEG||sourceR<=0.0)return 0.0;
   return 1.0/sourceR;
}
int ClampHalfBeLeg(int leg,int target)
{
   int candidate=MathMax(0,MathMin(5,leg));
   if(candidate<=0)return 0;
   double targetR=LegR(ClampTargetLeg(target));
   if(g_rtInvertMode)
   {
      if(g_rtTargetMode!=ORB_TARGET_R_LEG||targetR<=0.0)return 0;
      targetR=1.0/targetR;
   }
   return LegR(candidate)<targetR-1e-8?candidate:0;
}
int RuntimeHalfBeLeg(){return ClampHalfBeLeg(g_rtHalfBeLeg,RuntimeTargetLeg());}
double PriceAtLeg(bool isBuy,double entry,double risk,int leg){return NormalizeTradePrice(isBuy?entry+risk*LegR(leg):entry-risk*LegR(leg));}
string TargetCode(int leg)
{
   if(leg==(int)ORB_TARGET_CUSTOM)return "R"+DoubleToString(g_rtCustomR,8);
   if(leg==(int)ORB_TARGET_R075||(leg>=(int)ORB_TARGET_R005&&leg<=(int)ORB_TARGET_R095))
      return "R"+DoubleToString(LegR(leg),2);
   if(leg>=(int)ORB_TARGET_R350)return "R"+DoubleToString(LegR(leg),1);
   return "TP"+IntegerToString(leg);
}
string TargetOutcomeLabel(int leg)
{
   if(leg==(int)ORB_TARGET_CUSTOM)return "TP_R"+DoubleToString(g_rtCustomR,8);
   if(leg==(int)ORB_TARGET_R075||(leg>=(int)ORB_TARGET_R005&&leg<=(int)ORB_TARGET_R095))
      return StringFormat("TP%03d",(int)MathRound(LegR(leg)*100.0));
   if(leg>=(int)ORB_TARGET_R350)return "TP"+IntegerToString((int)MathRound(LegR(leg)*100.0));
   return "TP"+IntegerToString(leg);
}
double SimMoneyPnl(double netR)
{
   if(NativeBalanceEnabled())return netR*RiskBudgetMoney();
   double base=FixedReferenceRiskMode()?MathMax(0.01,InpFixedRiskReferenceCapital):(InpInitialBalanceOverride>0?InpInitialBalanceOverride:MathMax(0.01,AccountInfoDouble(ACCOUNT_BALANCE)));
   return netR*base*MathMax(0,EffRiskPerTradePct())/100.0;
}
string TargetLabel()
{
   int leg=RuntimeTargetLeg();
   double sourceR=RuntimeTargetR();
   int sourceDigits=leg==(int)ORB_TARGET_CUSTOM?8:(MathAbs(sourceR-MathRound(sourceR*2.0)/2.0)<1e-8?1:2);
   string source=DoubleToString(sourceR,sourceDigits)+"R";
   if(!g_rtInvertMode)return source;
   double effective=RuntimeEffectiveTargetR();
   return effective>0.0?("INV LEVELS <-"+source):("INV "+source);
}
string HalfBeLabel(){int h=RuntimeHalfBeLeg();return h<=0?"HC:OFF":"HC:TP"+IntegerToString(h);}
string FvgModeLabel()
{
   if(g_rtFvgMode==ORB_FVG_REQUIRE)return "FVG:REQ";
   if(g_rtFvgMode==ORB_FVG_OPTIONAL)return "FVG:OPT";
   return "FVG:OFF";
}
string ExitModeLabel(ORB_EXIT_ENGINE_MODE mode)
{
   if(mode==ORB_EXIT_EOD_ONLY)return "EXIT:EOD";
   if(mode==ORB_EXIT_ORB_MID_INVALIDATION)return "EXIT:MID";
   if(mode==ORB_EXIT_ATR_TRAIL)return "EXIT:ATR";
   if(mode==ORB_EXIT_EMA_STOP)return "EXIT:EMA";
   if(mode==ORB_EXIT_VWAP_STOP)return "EXIT:VWAP";
   if(mode==ORB_EXIT_BROKER_TIME)return "EXIT:19:15";
   return "EXIT:FIXED";
}
string RuntimeExitLabel(){return ExitModeLabel(g_rtExitMode);}
string TargetModeLabel(ORB_TARGET_MODE mode)
{
   if(mode==ORB_TARGET_RANGE_HEIGHT)return "TPMODE:RANGE";
   if(mode==ORB_TARGET_EOD)return "TPMODE:EOD";
   if(mode==ORB_TARGET_AUTO_STOP_SIZE)return "TPMODE:AUTO";
   return "TPMODE:RLEG";
}
string RuntimeTargetModeLabel(){return TargetModeLabel(g_rtTargetMode);}
string EntryModeLabel(ORB_ENTRY_MODE mode)
{
   if(mode==ORB_ENTRY_IMBALANCE_M1)return "ENTRY:IMB1M";
   if(mode==ORB_ENTRY_PULLBACK_RETEST)return "ENTRY:RETEST";
   return "ENTRY:BREAK";
}
string RuntimeEntryLabel(){return EntryModeLabel(g_rtEntryMode);}
ENUM_TIMEFRAMES RuntimeEntryTf()
{
   return g_rtEntryMode==ORB_ENTRY_IMBALANCE_M1?PERIOD_M1:g_rtSignalTf;
}
void CycleFvgMode()
{
   if(g_rtFvgMode==ORB_FVG_OFF)g_rtFvgMode=ORB_FVG_OPTIONAL;
   else if(g_rtFvgMode==ORB_FVG_OPTIONAL)g_rtFvgMode=ORB_FVG_REQUIRE;
   else g_rtFvgMode=ORB_FVG_OFF;
}
void CycleExitMode()
{
   if(g_rtExitMode==ORB_EXIT_FIXED_TARGET)g_rtExitMode=ORB_EXIT_EOD_ONLY;
   else if(g_rtExitMode==ORB_EXIT_EOD_ONLY)g_rtExitMode=ORB_EXIT_ORB_MID_INVALIDATION;
   else if(g_rtExitMode==ORB_EXIT_ORB_MID_INVALIDATION)g_rtExitMode=ORB_EXIT_ATR_TRAIL;
   else if(g_rtExitMode==ORB_EXIT_ATR_TRAIL)g_rtExitMode=ORB_EXIT_EMA_STOP;
   else if(g_rtExitMode==ORB_EXIT_EMA_STOP)g_rtExitMode=ORB_EXIT_VWAP_STOP;
   else if(g_rtExitMode==ORB_EXIT_VWAP_STOP)g_rtExitMode=ORB_EXIT_BROKER_TIME;
   else g_rtExitMode=ORB_EXIT_FIXED_TARGET;
}
void CycleEntryMode()
{
   if(g_rtEntryMode==ORB_ENTRY_BREAKOUT)g_rtEntryMode=ORB_ENTRY_PULLBACK_RETEST;
   else if(g_rtEntryMode==ORB_ENTRY_PULLBACK_RETEST)g_rtEntryMode=ORB_ENTRY_IMBALANCE_M1;
   else g_rtEntryMode=ORB_ENTRY_BREAKOUT;
}
void CycleTargetMode()
{
   if(g_rtTargetMode==ORB_TARGET_R_LEG)g_rtTargetMode=ORB_TARGET_RANGE_HEIGHT;
   else if(g_rtTargetMode==ORB_TARGET_RANGE_HEIGHT)g_rtTargetMode=ORB_TARGET_AUTO_STOP_SIZE;
   else if(g_rtTargetMode==ORB_TARGET_AUTO_STOP_SIZE)g_rtTargetMode=ORB_TARGET_EOD;
   else g_rtTargetMode=ORB_TARGET_R_LEG;
}
int ClampExitTrailStartLeg(int leg){return MathMax(0,MathMin(6,leg));}
int ClampEmaPeriod(int period){return period<75?50:100;}
void CycleExitTrailStart(){g_rtExitTrailStartLeg=ClampExitTrailStartLeg(g_rtExitTrailStartLeg>=6?0:g_rtExitTrailStartLeg+1);}
void CycleExitEmaPeriod(){g_rtExitEmaPeriod=(g_rtExitEmaPeriod<75?100:50);}
void CycleExitAtrMultiplier(){if(g_rtExitAtrMultiplier<1.75)g_rtExitAtrMultiplier=2.0;else if(g_rtExitAtrMultiplier<2.25)g_rtExitAtrMultiplier=2.5;else if(g_rtExitAtrMultiplier<2.75)g_rtExitAtrMultiplier=3.0;else g_rtExitAtrMultiplier=1.5;}
string ExitDebugConfig()
{
   return RuntimeExitLabel()+" "+RuntimeTargetModeLabel()+" startLeg="+IntegerToString(g_rtExitTrailStartLeg)+" atrX="+DoubleToString(g_rtExitAtrMultiplier,1)+" ema="+IntegerToString(g_rtExitEmaPeriod);
}
void SetTargetLeg(int leg){g_rtTargetLeg=ClampTargetLeg(leg);g_rtHalfBeLeg=ClampHalfBeLeg(g_rtHalfBeLeg,g_rtTargetLeg);}
void ForceFixedRLegTarget(){g_rtExitMode=ORB_EXIT_FIXED_TARGET;g_rtTargetMode=ORB_TARGET_R_LEG;}
int NextTargetLeg(int current)
{
   if(current>=(int)ORB_TARGET_R005&&current<(int)ORB_TARGET_R045)return current+1;
   if(current==(int)ORB_TARGET_R045)return 1;
   if(current==1)return (int)ORB_TARGET_R055;
   if(current>=(int)ORB_TARGET_R055&&current<(int)ORB_TARGET_R070)return current+1;
   if(current==(int)ORB_TARGET_R070)return (int)ORB_TARGET_R075;
   if(current==(int)ORB_TARGET_R075)return (int)ORB_TARGET_R080;
   if(current>=(int)ORB_TARGET_R080&&current<(int)ORB_TARGET_R095)return current+1;
   if(current==(int)ORB_TARGET_R095)return 2;
   if(current>=2&&current<6)return current+1;
   if(current==6)return (int)ORB_TARGET_R350;
   if(current>=(int)ORB_TARGET_R350&&current<(int)ORB_TARGET_R500)return current+1;
   return (int)ORB_TARGET_R005;
}
void CycleTargetLeg(){ForceFixedRLegTarget();SetTargetLeg(NextTargetLeg(RuntimeTargetLeg()));}
void CycleHalfBeLeg(){ForceFixedRLegTarget();double targetR=RuntimeEffectiveTargetR();int current=RuntimeHalfBeLeg();for(int h=current+1;h<=5;h++){if(LegR(h)<targetR-1e-8){g_rtHalfBeLeg=h;return;}}g_rtHalfBeLeg=0;}
int ClampHistWeeks(int weeks)
{
   int options[]={2,5,10,20,52,104,156,208,260};
   int best=options[0],bestDistance=MathAbs(weeks-options[0]);
   for(int i=1;i<ArraySize(options);i++)
   {
      int distance=MathAbs(weeks-options[i]);
      if(distance<bestDistance){best=options[i];bestDistance=distance;}
   }
   return best;
}
string HistoricalWindowLabel()
{
   if(g_rtHistoricalWeeks>=52&&g_rtHistoricalWeeks%52==0)return IntegerToString(g_rtHistoricalWeeks/52)+"Y";
   return IntegerToString(g_rtHistoricalWeeks)+"W";
}
void SetHistoricalWeeks(int weeks)
{
   g_rtHistoricalWeeks=ClampHistWeeks(weeks);
   g_maCacheFailedAttempts=0;
   g_lastHistBuild=0;
   g_histNeedsRedraw=true;
   g_histCoveragePending=false;
   g_histCoverageHardBlocked=false;
   g_histCoverageNextRetry=0;
   g_histCoverageAttempts=0;
   g_histCoverageStatus="";
   g_histCoverageDetail="";
}
void QueueHistoricalRedraw(const uint debounceMs=120)
{
   AxAbort("CSV cancelled: settings changed");g_axReady=false;
   ulong queuedAtMs=GetTickCount64();
   g_histAuditRequestedMs=queuedAtMs;
   g_lastHistBuild=0;
   g_histNeedsRedraw=true;
   g_histRedrawQueued=true;
   g_histRedrawNotBeforeMs=queuedAtMs+(ulong)debounceMs;
   if(g_histAuditRunning)g_histAuditCancelRequested=true;
   g_histAuditStage="QUEUED";
   g_histAuditStageDone=0;
   g_histAuditStageTotal=0;
   g_histAuditProgressPct=0.0;
   if(!IsTesterMode())
   {
      EventKillTimer();
      EventSetMillisecondTimer(40);
   }
}
void ProcessQueuedHistoricalRedraw()
{
   if(g_histAuditRunning)
   {
      if(g_histAuditCancelRequested)CancelHistoricalAuditBuild();
      return;
   }
   if(!g_histRedrawQueued)return;
   if(GetTickCount64()<g_histRedrawNotBeforeMs)return;
   g_histRedrawQueued=false;
   DrawHistoricalSignals();
}
int RuntimeHistoricalDays(){return MathMax(1,ClampHistWeeks(g_rtHistoricalWeeks)*7);}
double ClampSlDistancePct(double pct){return MathMax(10.0,MathMin(300.0,pct));}
void SetSlDistancePct(double pct){g_rtSlDistancePct=ClampSlDistancePct(pct);}
double ScaleSlFromEntry(bool isBuy,double entry,double rawSl)
{
   double dist=MathAbs(entry-rawSl)*ClampSlDistancePct(g_rtSlDistancePct)/100.0;
   if(dist<=0)return rawSl;
   return NormalizeTradePrice(isBuy?entry-dist:entry+dist);
}

double ClampPipSlPips(double pips){return MathIsValidNumber(pips)?MathMax(0.1,pips):0.1;}
void SetPipSlPips(double pips){g_rtPipSlPips=ClampPipSlPips(pips);}
double OrbPipSize()
{
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)point=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return (digits==3||digits==5)?point*10.0:point;
}
double ApplyRuntimeSlFromEntry(bool isBuy,double entry,double rawSl)
{
   if(g_rtPipSlMode||LabPolicyEnabled())
   {
      double dist=ClampPipSlPips(g_rtPipSlPips)*OrbPipSize();
      if(dist>0.0)return NormalizeTradePrice(isBuy?entry-dist:entry+dist);
   }
   return ScaleSlFromEntry(isBuy,entry,rawSl);
}
string RuntimeSlEditValue(){return (g_rtPipSlMode||LabPolicyEnabled())?DoubleToString(g_rtPipSlPips,1):DoubleToString(g_rtSlDistancePct,0);}
string RuntimeSlModeLabel(){return (g_rtPipSlMode||LabPolicyEnabled())?("PIP "+DoubleToString(g_rtPipSlPips,1)):("SL% "+DoubleToString(g_rtSlDistancePct,0));}

string OrbRegimeName(int bucket)
{
   if(bucket==0)return "TREND LOW VOL";
   if(bucket==1)return "TREND HIGH VOL";
   if(bucket==2)return "RANGE LOW VOL";
   if(bucket==3)return "RANGE HIGH VOL";
   if(bucket==4)return "TRANSITION PENDING";
   if(bucket==5)return "TRANSITION FRESH";
   return "UNKNOWN";
}
string OrbRegimeShortName(int bucket)
{
   if(bucket==0)return "TLV";
   if(bucket==1)return "THV";
   if(bucket==2)return "RLV";
   if(bucket==3)return "RHV";
   if(bucket==4)return "TR PEND";
   if(bucket==5)return "TR FRESH";
   return "UNK";
}
int OrbRegimeBucket(const RegimeV3Snapshot &snapshot)
{
   if(!snapshot.valid)return -1;
   if(snapshot.transitionStatus=="WATCH"||snapshot.transitionStatus=="DEVELOPING")return 4;
   if(snapshot.transitionStatus=="FRESH_CONFIRMED")return 5;
   if(snapshot.core=="TREND_LOW_VOL")return 0;
   if(snapshot.core=="TREND_HIGH_VOL")return 1;
   if(snapshot.core=="RANGE_LOW_VOL")return 2;
   if(snapshot.core=="RANGE_HIGH_VOL")return 3;
   return -1;
}
int OrbRegimeBucketAt(datetime signalAvailable,RegimeV3Snapshot &snapshot)
{
   snapshot.valid=false;
   if(!InpRegimeV3Observer)return -1;
   RegimeV3EnsureTimeline(false);
   if(!RegimeV3SnapshotAt(signalAvailable,snapshot))return -1;
   return OrbRegimeBucket(snapshot);
}
bool OrbRegimeAllowed(int bucket){return bucket<0||bucket>=ORB_REGIME_COUNT?true:g_regimeAllowed[bucket];}
string OrbRegimeStatsText(int bucket)
{
   int w=g_regimeWins[bucket],l=g_regimeLosses[bucket],n=w+l;
   double wr=n>0?(double)w/(double)n*100.0:0.0;
   return OrbRegimeShortName(bucket)+" "+IntegerToString(w)+"W/"+IntegerToString(l)+"L "+DoubleToString(wr,1)+"%";
}
string OrbRegimeDetail(const RegimeV3Snapshot &snapshot,int bucket)
{
   if(bucket<0)return "regime=UNKNOWN";
   return "regime="+OrbRegimeName(bucket)
      +" core="+snapshot.core+" transition="+snapshot.transitionStatus
      +" age="+IntegerToString(snapshot.effectiveAge)+" macro="+snapshot.macroDirection
      +" h1h2="+snapshot.h1h2Phase+" vol="+snapshot.volatilityDepth+"/"+snapshot.volatilityImpulse;
}

string OrbRfRuleCode(int index)
{
   return index>=0&&index<ORB_RF_COUNT?StringFormat("RF%02d",index+1):"RF??";
}

int OrbRfRuleIndex(const string rule)
{
   if(StringLen(rule)<4||StringSubstr(rule,0,2)!="RF")return -1;
   int number=(int)StringToInteger(StringSubstr(rule,2,2));
   return number>=1&&number<=ORB_RF_COUNT?number-1:-1;
}

bool OrbMacroRoute(const string direction,const RegimeV3Snapshot &state,bool &continuation,string &label)
{
   continuation=false;label="UNKNOWN";
   if(state.macroDirection!="UP"&&state.macroDirection!="DOWN")return false;
   continuation=((direction=="BUY"&&state.macroDirection=="UP")
      ||(direction=="SELL"&&state.macroDirection=="DOWN"));
   label=continuation?"CONTINUATION":"REVERSAL";
   return true;
}

// Exact RF01-RF12 predicates from Liq Narrative. ORB has no Liq-specific
// continuation marker, so route-dependent rules use signal direction versus
// the causal macro direction and fail open when that direction is unknown.
bool OrbRfRule(const RegimeV3Snapshot &state,bool continuationRoute,bool routeKnown,string &rule)
{
   rule="";
   bool reversalRoute=routeKnown&&!continuationRoute;
   if(state.core=="RANGE_LOW_VOL"&&state.ageBucket=="MATURE"
      &&state.transitionStatus=="STABLE"&&routeKnown&&continuationRoute)
      rule="RF01_RLV_MATURE_STABLE_CONT";
   else if(state.core=="TREND_LOW_VOL"&&state.h1h2Phase=="NEUTRAL_ROTATION"
      &&state.macroDirection=="UP")
      rule="RF02_TLV_ROTATION_UP";
   else if(state.h1h2Phase=="ALIGNED_IMPULSE"&&state.macroDirection=="DOWN"
      &&routeKnown&&continuationRoute)
      rule="RF03_IMPULSE_DOWN_CONT";
   else if(state.core=="RANGE_HIGH_VOL"&&state.transitionStatus=="DEVELOPING")
      rule="RF04_RHV_DEVELOPING";
   else if(state.core=="RANGE_LOW_VOL"&&state.h1h2Phase=="DEEP_REBOUND"
      &&state.volatilityDepth=="NORMAL")
      rule="RF05_RLV_DEEP_REBOUND_NORMAL";
   else if(state.core=="RANGE_LOW_VOL"&&state.h1h2Phase=="SHALLOW_REBOUND")
      rule="RF06_RLV_SHALLOW_REBOUND";
   else if(state.h1h2Phase=="ALIGNED"&&state.ageBucket=="FRESH"
      &&state.transitionStatus=="STABLE")
      rule="RF07_ALIGNED_FRESH_STABLE";
   else if(state.h1h2Phase=="SHALLOW_PULLBACK"&&state.ageBucket=="MATURE"
      &&state.transitionStatus=="STABLE")
      rule="RF08_SHALLOW_PULLBACK_MATURE";
   else if(state.core=="RANGE_HIGH_VOL"&&state.h1h2Phase=="ALIGNED_IMPULSE")
      rule="RF09_RHV_ALIGNED_IMPULSE";
   else if(state.core=="RANGE_LOW_VOL"&&state.volatilityDepth=="COMPRESSED"
      &&state.macroDirection=="DOWN"&&reversalRoute)
      rule="RF10_RLV_COMPRESSED_DOWN_REV";
   else if(state.h1h2Phase=="ALIGNED_IMPULSE"&&state.volatilityDepth=="NORMAL"
      &&reversalRoute)
      rule="RF11_IMPULSE_NORMAL_REV";
   else if(state.h1h2Phase=="SHALLOW_PULLBACK"&&state.volatilityDepth=="NORMAL")
      rule="RF12_SHALLOW_PULLBACK_NORMAL";
   return rule!="";
}

string OrbRfStatsText(int index)
{
   int w=g_orbRfWins[index],l=g_orbRfLosses[index],n=w+l;
   double wr=n>0?(double)w/(double)n*100.0:0.0;
   return OrbRfRuleCode(index)+" "+IntegerToString(w)+"W/"+IntegerToString(l)+"L "+DoubleToString(wr,1)+"%";
}

bool OrbRfEvaluate(const string direction,const RegimeV3Snapshot &state,
   int &rfIndex,string &rule,string &detail)
{
   bool continuation=false;string routeLabel="";
   bool routeKnown=OrbMacroRoute(direction,state,continuation,routeLabel);
   bool matched=OrbRfRule(state,continuation,routeKnown,rule);
   rfIndex=matched?OrbRfRuleIndex(rule):-1;
   bool blocked=(g_orbRfEnabled&&rfIndex>=0&&rfIndex<ORB_RF_COUNT&&g_orbRfBlocked[rfIndex]);
   detail="rf="+(matched?OrbRfRuleCode(rfIndex):"NONE")
      +" route="+routeLabel+" rf_master="+(g_orbRfEnabled?"1":"0")
      +" rf_blocked="+(blocked?"1":"0");
   return !blocked;
}

bool OrbEntryRegimeFiltersAllowAt(const string direction,datetime signalTime,string &detail)
{
   RegimeV3Snapshot snapshot;
   int bucket=OrbRegimeBucketAt(signalTime,snapshot);
   string regimeDetail=OrbRegimeDetail(snapshot,bucket);
   if(!OrbRegimeAllowed(bucket))
   {
      detail=regimeDetail+" regime_allowed=0";
      return false;
   }
   int rfIndex=-1;string rule="",rfDetail="";
   bool rfAllowed=OrbRfEvaluate(direction,snapshot,rfIndex,rule,rfDetail);
   detail=regimeDetail+" regime_allowed=1 "+rfDetail;
   return rfAllowed;
}

//=========================================================================
//  SCREENSHOT STRATEGY LIBRARY
//=========================================================================
string OrbStrategyPresetSelectionKey()
{
   return "ENTRY_ENGINE_LAB_PRESET."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +StringFormat("%I64d",ChartID());
}

bool OrbStrategyPresetFamilyMatches(const int family)
{
   if(family==ORB_PRESET_FAMILY_ANY)return true;
   string symbol=UpperText(_Symbol);
   if(family==ORB_PRESET_FAMILY_JP225)
      return StringFind(symbol,"JP225")>=0||StringFind(symbol,"JPN225")>=0
         ||StringFind(symbol,"NIKKEI")>=0||StringFind(symbol,"NI225")>=0;
   if(family==ORB_PRESET_FAMILY_USTEC)
      return StringFind(symbol,"USTEC")>=0||StringFind(symbol,"US100")>=0
         ||StringFind(symbol,"NAS100")>=0||StringFind(symbol,"NASDAQ")>=0;
   if(family==ORB_PRESET_FAMILY_USDJPY)
   {
      string base="",quote="";
      return ExtractForexPair(symbol,base,quote)&&base=="USD"&&quote=="JPY";
   }
   return false;
}

string OrbStrategyPresetFamilyText(const int family)
{
   if(family==ORB_PRESET_FAMILY_JP225)return "JP225";
   if(family==ORB_PRESET_FAMILY_USDJPY)return "USDJPY";
   if(family==ORB_PRESET_FAMILY_USTEC)return "USTEC";
   return "ANY";
}

#include "OrbStrategyUserLibrary.mqh"

string OrbStrategyPresetPair(const OrbStrategyPreset &p)
{
   if(p.family!=ORB_PRESET_FAMILY_ANY)return OrbStrategyPresetFamilyText(p.family);
   if(OrbUserPreset(p))
   {
      int slot=OrbUserSlot(p.id);
      if(slot>=0)return g_userStrategies[slot].symbol;
   }
   return "ANY";
}

void OrbStrategyCyclePairFilter()
{
   string pairs[];int count=0;
   for(int i=0;i<OrbStrategyPresetCount();i++)
   {
      OrbStrategyPreset p;if(!OrbStrategyPresetLoad(i,p))continue;
      string pair=OrbStrategyPresetPair(p);
      if(pair=="ANY"||pair=="")continue;
      bool exists=false;
      for(int j=0;j<count;j++)if(pairs[j]==pair){exists=true;break;}
      if(exists)continue;
      ArrayResize(pairs,count+1);pairs[count++]=pair;
   }
   if(g_strategyFilterPair==""){g_strategyFilterPair=count>0?pairs[0]:"";return;}
   for(int i=0;i<count;i++)if(pairs[i]==g_strategyFilterPair)
   {g_strategyFilterPair=i+1<count?pairs[i+1]:"";return;}
   g_strategyFilterPair="";
}

bool OrbStrategyPresetValuesValid(const OrbStrategyPreset &p,string &reason)
{
   if(OrbUserPreset(p))return OrbUserValidate(p,reason);
   reason="";
   if(p.id==""||p.name==""){reason="EMPTY_PRESET";return false;}
   if(p.signalTf!=PERIOD_M1&&p.signalTf!=PERIOD_M5&&p.signalTf!=PERIOD_M15){reason="UNSUPPORTED_TF";return false;}
   if(p.delayMinutes<0||p.delayMinutes>1440){reason="INVALID_DELAY";return false;}
   if(p.pipSlMode&&(!MathIsValidNumber(p.pipSlPips)||p.pipSlPips<0.1))
      {reason="INVALID_PIP_SL";return false;}
   if(!MathIsValidNumber(p.volumeMultiplier)||p.volumeMultiplier<0.05||p.volumeMultiplier>20.0)
      {reason="INVALID_ORB_VOL_X";return false;}
   if(p.entryWindowStart<0||p.entryWindowStart>1439||p.entryWindowEnd<0||p.entryWindowEnd>1439)
      {reason="INVALID_WINDOW";return false;}
   if(p.nasEntryGate&&p.nasStateGate){reason="DUAL_NAS_ENTRY_GATE";return false;}
   if(p.nasOppositeExit&&p.nasAdditionalExit){reason="DUAL_NAS_EXIT_MODE";return false;}
   if(p.nasSensitivity<1||p.nasSensitivity>100||p.nasLookbackMinutes<0||p.nasLookbackMinutes>1440
      ||p.nasExitWaitMinutes<0||p.nasExitWaitMinutes>5999)
      {reason="INVALID_NAS_RANGE";return false;}
   if(!MathIsValidNumber(p.nasStateVolumeMultiplier)||p.nasStateVolumeMultiplier<0.05||p.nasStateVolumeMultiplier>200.0
      ||!MathIsValidNumber(p.nasFlowVolumeMultiplier)||p.nasFlowVolumeMultiplier<0.05||p.nasFlowVolumeMultiplier>200.0)
      {reason="INVALID_NAS_VOL_X";return false;}
   if(InpExecutionMode!=ORB_EXEC_SINGLE){reason="PRESET_REQUIRES_SINGLE_ORDER";return false;}
   if(p.exitMode!=ORB_EXIT_FIXED_TARGET||p.targetMode!=ORB_TARGET_R_LEG)
      {reason="PRESET_REQUIRES_FIXED_R";return false;}
   return true;
}

void OrbStrategyPresetSetEdit(const string name,const string value)
{
   string object=PREFIX+name;
   if(ObjectFind(0,object)>=0)ObjectSetString(0,object,OBJPROP_TEXT,value);
}

void OrbStrategyPresetSyncEdits()
{
   ObjectSetString(0,PREFIX+"EDIT_MA_MAX",OBJPROP_TEXT,(string)g_maMaxConsecutive);
   ObjectSetString(0,PREFIX+"EDIT_MA_REV_WAIT",OBJPROP_TEXT,DurationMinutesText(g_maReverseWait));
   // Only an explicit preset apply/restore replaces drafts; routine redraws preserve typing.
   OrbStrategyPresetSetEdit("EDIT_SL_VALUE",RuntimeSlEditValue());
   OrbStrategyPresetSetEdit("EDIT_VOL_MULT",DoubleToString(g_rtVolumeMultiplier,2));
   OrbStrategyPresetSetEdit("EDIT_ADV_COST",DoubleToString(g_rtAdvancedReverseMaxCostPct,2));
   OrbStrategyPresetSetEdit("EDIT_ENTRY_WIN_START",ClockMinutesText(g_rtEntryWindowStartMin));
   OrbStrategyPresetSetEdit("EDIT_ENTRY_WIN_END",ClockMinutesText(g_rtEntryWindowEndMin));
   OrbStrategyPresetSetEdit("EDIT_NAS_SENS",IntegerToString(g_rtNasSensitivity));
   OrbStrategyPresetSetEdit("EDIT_NAS_LOOKBACK",IntegerToString(g_rtNasActiveSignalLookbackMinutes));
   OrbStrategyPresetSetEdit("EDIT_NAS_EXIT_WAIT",DurationMinutesText(g_rtNasOppositeExitWaitMinutes));
   OrbStrategyPresetSetEdit("EDIT_NAS_VOL_X",DoubleToString(g_rtNasVolumeMultiplier,2));
   OrbStrategyPresetSetEdit("EDIT_NAS_FLOW_VOL_X",DoubleToString(g_rtNasFlowVolumeMultiplier,2));
}

bool OrbStrategyPresetApplyValues(const OrbStrategyPreset &p)
{
   if(OrbUserPreset(p))
   {
      if(!OrbUserApply(p))return false;
      OrbStrategyPresetSyncEdits();return true;
   }
   if(GlobalVariableSet(RuntimeAdvancedReverseKey(),0.0)<=0)return false;
   if(!SetRuntimeAdvancedReverseMaxCostPct(100.0))return false;
   if(!TCalStrategyApplyText(TCalStrategyOffText()))return false;
   g_rtCustomR=0.0;
   g_rtSignalTf=p.signalTf;g_rtDelayMin=p.delayMinutes;g_rtUseDelay=p.delayMinutes>0;
   g_rtTargetLeg=ClampTargetLeg(p.targetLeg);g_rtInvertMode=p.invertMode;g_rtAdvancedReverse=false;
   g_rtHalfBeLeg=ClampHalfBeLeg(p.halfBeLeg,g_rtTargetLeg);g_rtBEOnTp1=false;
   g_rtEntryMode=p.entryMode;g_rtExitMode=p.exitMode;g_rtTargetMode=p.targetMode;
   g_rtExitTrailStartLeg=0;
   g_rtPipSlMode=p.pipSlMode;g_rtPipSlPips=ClampPipSlPips(p.pipSlPips);
   g_rtFilterAtr=p.atrFilter;g_rtFilterVol=p.volumeFilter;g_rtVolumeMultiplier=p.volumeMultiplier;
   g_rtFilterDay=p.dayFilter;g_rtTimeExit=p.timeExit;g_rtDisplacement=p.displacementFilter;g_rtFvgMode=p.fvgMode;
   g_rtUtcMidnightSession=p.utc00Mode;
   g_rtEntryWindow=p.entryWindow;g_rtEntryWindowStartMin=p.entryWindowStart;g_rtEntryWindowEndMin=p.entryWindowEnd;
   g_rtFilteredWindowReverseExit=p.reverseWindowExit;g_rtPostTradeDispBlockExit=p.postTradeDispExit;
   for(int ri=0;ri<ORB_REGIME_COUNT;ri++)g_regimeAllowed[ri]=OrbPresetRegimeAllowed(p,ri);
   g_orbRfEnabled=p.rfMaster;
   for(int rf=0;rf<ORB_RF_COUNT;rf++)g_orbRfBlocked[rf]=OrbPresetRfBlocked(p,rf);
   g_rtNasConfirmation=p.nasEntryGate;g_rtNasStateGate=p.nasStateGate;
   g_rtNasExitOnOppositeSignal=p.nasOppositeExit;g_rtNasAdditionalExit=p.nasAdditionalExit;
   g_rtNasSensitivity=p.nasSensitivity;g_rtNasActiveSignalLookbackMinutes=p.nasLookbackMinutes;
   g_rtNasOppositeExitWaitMinutes=p.nasExitWaitMinutes;
   g_rtNasVolumeFilter=p.nasStateVolumeFilter;g_rtNasVolumeMultiplier=p.nasStateVolumeMultiplier;
   g_rtNasFlowVolumeFilter=p.nasFlowVolumeFilter;g_rtNasFlowVolumeMultiplier=p.nasFlowVolumeMultiplier;
   OrbStrategyPresetSyncEdits();
   return true;
}

bool OrbStrategyPresetMatchesRuntime(const OrbStrategyPreset &p)
{
   if(OrbUserPreset(p))return OrbUserMatches(p);
   if(g_rtAdvancedReverse)return false;
   if(MathAbs(g_rtAdvancedReverseMaxCostPct-100.0)>0.000001)return false;
   if(!TCalStrategyMatchesText(TCalStrategyOffText()))return false;
   if(g_rtSignalTf!=p.signalTf||g_rtDelayMin!=p.delayMinutes||g_rtUseDelay!=(p.delayMinutes>0))return false;
   if(RuntimeTargetLeg()!=ClampTargetLeg(p.targetLeg)||g_rtHalfBeLeg!=ClampHalfBeLeg(p.halfBeLeg,p.targetLeg)||g_rtBEOnTp1)return false;
   if(g_rtEntryMode!=p.entryMode||g_rtExitMode!=p.exitMode||g_rtTargetMode!=p.targetMode)return false;
   if(g_rtPipSlMode!=p.pipSlMode||MathAbs(g_rtPipSlPips-p.pipSlPips)>0.00005)return false;
   if(g_rtFilterAtr!=p.atrFilter||g_rtFilterVol!=p.volumeFilter||MathAbs(g_rtVolumeMultiplier-p.volumeMultiplier)>0.00005)return false;
   if(g_rtFilterDay!=p.dayFilter||g_rtTimeExit!=p.timeExit||g_rtDisplacement!=p.displacementFilter||g_rtFvgMode!=p.fvgMode)return false;
   if(g_rtInvertMode!=p.invertMode||g_rtUtcMidnightSession!=p.utc00Mode)return false;
   if(g_rtEntryWindow!=p.entryWindow||g_rtEntryWindowStartMin!=p.entryWindowStart||g_rtEntryWindowEndMin!=p.entryWindowEnd)return false;
   if(g_rtFilteredWindowReverseExit!=p.reverseWindowExit||g_rtPostTradeDispBlockExit!=p.postTradeDispExit)return false;
   for(int ri=0;ri<ORB_REGIME_COUNT;ri++)if(g_regimeAllowed[ri]!=OrbPresetRegimeAllowed(p,ri))return false;
   if(g_orbRfEnabled!=p.rfMaster)return false;
   for(int rf=0;rf<ORB_RF_COUNT;rf++)if(g_orbRfBlocked[rf]!=OrbPresetRfBlocked(p,rf))return false;
   if(g_rtNasConfirmation!=p.nasEntryGate||g_rtNasStateGate!=p.nasStateGate
      ||g_rtNasExitOnOppositeSignal!=p.nasOppositeExit||g_rtNasAdditionalExit!=p.nasAdditionalExit)return false;
   if(g_rtNasSensitivity!=p.nasSensitivity||g_rtNasActiveSignalLookbackMinutes!=p.nasLookbackMinutes
      ||g_rtNasOppositeExitWaitMinutes!=p.nasExitWaitMinutes)return false;
   if(g_rtNasVolumeFilter!=p.nasStateVolumeFilter||MathAbs(g_rtNasVolumeMultiplier-p.nasStateVolumeMultiplier)>0.00005)return false;
   if(g_rtNasFlowVolumeFilter!=p.nasFlowVolumeFilter||MathAbs(g_rtNasFlowVolumeMultiplier-p.nasFlowVolumeMultiplier)>0.00005)return false;
   return true;
}

void OrbStrategyPresetClearSelection()
{
   g_strategyPresetIndex=-1;
   GlobalVariableDel(OrbStrategyPresetSelectionKey());
}

void OrbStrategyPresetSyncSelection()
{
   if(g_strategyPresetIndex<0)return;
   OrbStrategyPreset p;
   if(!OrbStrategyPresetLoad(g_strategyPresetIndex,p)||!OrbStrategyPresetMatchesRuntime(p))
      OrbStrategyPresetClearSelection();
}

bool OrbStrategyPresetRestore()
{
   string key=OrbStrategyPresetSelectionKey();
   if(!GlobalVariableCheck(key))return false;
   int index=(int)MathRound(GlobalVariableGet(key));
   OrbStrategyPreset p;string reason="";
   if(!OrbStrategyPresetLoad(index,p)||!OrbStrategyPresetValuesValid(p,reason)||!OrbStrategyPresetFamilyMatches(p.family)||!OrbUserRemembered(p))
   {
      GlobalVariableDel(key);return false;
   }
   if(!OrbStrategyPresetApplyValues(p))return false;
   g_strategyPresetIndex=index;g_strategyCandidateIndex=index;g_tcalChanged=false;
   return true;
}

bool OrbStrategyPresetHasActiveLifecycle()
{
   return OwnPositionExists()||g_orbBridgePlanActive||g_nasManagedLifecycle||g_nasManagedClosePending;
}

bool OrbStrategyPresetApplyInteractive(const int index)
{
   OrbStrategyPreset p;string reason="";
   if(!OrbStrategyPresetLoad(index,p)){g_lastExecStatus="PRESET_NOT_FOUND";return false;}
   if(!OrbStrategyPresetValuesValid(p,reason)){g_lastExecStatus="PRESET_INVALID_"+reason;return false;}
   if(!OrbStrategyPresetFamilyMatches(p.family))
   {
      g_lastExecStatus="PRESET_SYMBOL_NEEDS_"+OrbStrategyPresetFamilyText(p.family);return false;
   }
   if(g_btRunning){g_lastExecStatus="PRESET_BLOCKED_BACKTEST_RUNNING";return false;}
   if(OrbStrategyPresetHasActiveLifecycle()){g_lastExecStatus="PRESET_BLOCKED_ACTIVE_TRADE";return false;}
   if(g_orbBridgeEnabled&&p.signalTf!=g_rtSignalTf)
   {
      g_lastExecStatus="PRESET_DISABLE_PUB_FOR_TF_CHANGE_"+TfLabel(p.signalTf);return false;
   }
   string key=OrbStrategyPresetSelectionKey();
   if(!OrbUserRemember(p)){g_lastExecStatus="PRESET_ID_SAVE_FAIL";return false;}
   if(GlobalVariableSet(key,(double)index)<=0){g_lastExecStatus="PRESET_SAVE_FAIL";return false;}

   if(!OrbStrategyPresetApplyValues(p)){g_lastExecStatus="PRESET_TIME_MATRIX_APPLY_FAIL";return false;}
   if(OrbUserPreset(p)&&!OrbUserMatches(p)){g_lastExecStatus="PRESET_APPLY_FAILED: "+g_lastExecStatus;return false;}
   ClearRetestState("strategy_preset_changed");ClearImbalanceState("strategy_preset_changed");
   ClearNasPending("strategy_preset_changed");ClearNewDayReverseRetry("strategy_preset_changed");
   g_lastNasOverlayClosedBar=0;DeleteLive();DeleteExecutionVisuals();
   g_instanceStartedAt=TimeCurrent();g_startupOrbGuardPending=!IsTesterMode();g_startupOrbDayLocked=false;
   g_nyDayKey=0;ResetForNewNyDay();
   g_strategyPresetIndex=index;g_strategyCandidateIndex=index;g_strategyApplyFlashUntil=TimeLocal()+2;
   g_lastExecStatus="PRESET_APPLIED_"+p.id;
   Audit("strategy_preset_applied","",0,0,0,0,"id="+p.id+" source="+p.sourceImage
      +" risk_channel_publish_preserved=1");
   if(g_orbBridgeEnabled)OrbProWriteInitMarker();
   QueueHistoricalRedraw(0);
   g_tcalChanged=false;
   if(OrbUserPreset(p)&&!p.metric1yReady)OrbUserEnsureMetrics();
   return true;
}

string OrbStrategyPresetLower(string value){StringToLower(value);return value;}

string OrbStrategyFavoriteFile(const OrbStrategyPreset &p)
{
   // Never share favorites with the production ORB strategy collection.
   return "EntryEngineLabStrategyLibraryFavorites\\"+p.id+".fav";
}

void OrbStrategyLoadFavorites()
{
   ArrayResize(g_strategyFavorites,OrbStrategyPresetCount());
   for(int i=0;i<ArraySize(g_strategyFavorites);i++)
   {
      OrbStrategyPreset p;
      g_strategyFavorites[i]=!IsTesterMode()&&OrbStrategyPresetLoad(i,p)
         &&FileIsExist(OrbStrategyFavoriteFile(p),FILE_COMMON);
   }
}

bool OrbStrategyIsFavorite(const int index)
{
   return index>=0&&index<ArraySize(g_strategyFavorites)&&g_strategyFavorites[index];
}

bool OrbStrategyToggleFavorite(const int index)
{
   OrbStrategyPreset p;
   if(IsTesterMode()||!OrbStrategyPresetLoad(index,p))return false;
   string path=OrbStrategyFavoriteFile(p);
   bool wasFavorite=FileIsExist(path,FILE_COMMON);
   ResetLastError();
   if(wasFavorite)
   {
      if(!FileDelete(path,FILE_COMMON)&&FileIsExist(path,FILE_COMMON))
      {g_lastExecStatus="FAVORITE_REMOVE_FAILED_"+IntegerToString(GetLastError());return false;}
   }
   else
   {
      // One marker per stable ID: independent charts never overwrite a list.
      int h=FileOpen(path,FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(h==INVALID_HANDLE)
      {g_lastExecStatus="FAVORITE_SAVE_FAILED_"+IntegerToString(GetLastError());return false;}
      FileClose(h);
   }
   OrbStrategyLoadFavorites();
   if(OrbStrategyIsFavorite(index)==wasFavorite)
   {g_lastExecStatus="FAVORITE_CHANGED_ELSEWHERE_RETRY";return false;}
   g_lastExecStatus=OrbStrategyIsFavorite(index)?"FAVORITE_ADDED":"FAVORITE_REMOVED";
   return true;
}

string OrbStrategyMetricSigned(const double value,const int digits=2)
{
   return (value>0.00000001?"+":"")+DoubleToString(value,digits);
}

string OrbStrategyPresetMetricCaption(const OrbStrategyPreset &p)
{
   if(!p.metric1yReady)return p.name+" | 1Y N/A";
   string suffix=" | R "+OrbStrategyMetricSigned(p.metric1yNetR,2)
      +" | MC "+OrbStrategyMetricSigned(p.metric1yMinCumR,2)
      +" | WR "+DoubleToString(p.metric1yWr,1)+"%";
   int maxChars=66;
   int nameChars=MathMax(8,maxChars-StringLen(suffix));
   string shortName=p.name;
   if(StringLen(shortName)>nameChars)shortName=StringSubstr(shortName,0,MathMax(5,nameChars-3))+"...";
   return shortName+suffix;
}

bool OrbStrategyPresetPassesMetricFilters(const OrbStrategyPreset &p)
{
   if(g_strategyFilterPair!=""&&OrbStrategyPresetPair(p)!=g_strategyFilterPair)return false;
   if(g_strategyFilterGeometryEnabled)
   {
      // Geometry, not realized net R; non-fixed targets have no single preset ratio.
      if(p.targetMode!=ORB_TARGET_R_LEG)return false;
      double r=p.targetLeg==(int)ORB_TARGET_CUSTOM?OrbUserCustomR(p):LegR(p.targetLeg);
      if(!MathIsValidNumber(r)||r<=0.0)return false;
      if(p.invertMode)r=1.0/r;
      if(MathAbs(r-g_strategyFilterGeometry)>0.000001)return false;
   }
   if(!g_strategyFilterNetEnabled&&!g_strategyFilterWrEnabled&&!g_strategyFilterMinCumEnabled)return true;
   if(!p.metric1yReady)return false;
   if(g_strategyFilterNetEnabled&&p.metric1yNetR<g_strategyFilterNet-0.00000001)return false;
   if(g_strategyFilterWrEnabled&&p.metric1yWr<g_strategyFilterWr-0.00000001)return false;
   if(g_strategyFilterMinCumEnabled&&p.metric1yMinCumR<g_strategyFilterMinCum-0.00000001)return false;
   return true;
}

bool OrbStrategyParseOptionalMetric(string raw,bool &enabled,double &value)
{
   StringTrimLeft(raw);StringTrimRight(raw);
   if(raw==""){enabled=false;value=0.0;return true;}
   StringReplace(raw,",",".");
   int dots=0,digits=0;
   for(int i=0;i<StringLen(raw);i++)
   {
      ushort ch=StringGetCharacter(raw,i);
      if(ch>=48&&ch<=57){digits++;continue;}
      if(ch==46&&dots==0){dots++;continue;}
      if((ch==43||ch==45)&&i==0)continue;
      return false;
   }
   if(digits==0)return false;
   double parsed=StringToDouble(raw);
   if(!MathIsValidNumber(parsed))return false;
   enabled=true;value=parsed;return true;
}

bool OrbStrategyApplyMetricFilters()
{
   string netText=ObjectGetString(0,PREFIX+"EDIT_PRESET_NET",OBJPROP_TEXT);
   string wrText=ObjectGetString(0,PREFIX+"EDIT_PRESET_WR",OBJPROP_TEXT);
   string mcText=ObjectGetString(0,PREFIX+"EDIT_PRESET_MC",OBJPROP_TEXT);
   string geometryText=ObjectGetString(0,PREFIX+"EDIT_PRESET_GEOMETRY",OBJPROP_TEXT);
   bool geometryEnabled=false;double geometry=0.0;
   bool netEnabled=false,wrEnabled=false,mcEnabled=false;
   double net=0.0,wr=0.0,mc=0.0;
   if(!OrbStrategyParseOptionalMetric(netText,netEnabled,net)
      ||!OrbStrategyParseOptionalMetric(wrText,wrEnabled,wr)
      ||!OrbStrategyParseOptionalMetric(mcText,mcEnabled,mc)
      ||!OrbStrategyParseOptionalMetric(geometryText,geometryEnabled,geometry)
      ||(geometryEnabled&&geometry<=0.0)
      ||(wrEnabled&&(wr<0.0||wr>100.0)))
      return false;
   g_strategyFilterNetText=netEnabled?DoubleToString(net,2):"";
   g_strategyFilterGeometryText=geometryEnabled?DoubleToString(geometry,8):"";
   while(StringFind(g_strategyFilterGeometryText,".")>=0&&StringSubstr(g_strategyFilterGeometryText,StringLen(g_strategyFilterGeometryText)-1)=="0")
      g_strategyFilterGeometryText=StringSubstr(g_strategyFilterGeometryText,0,StringLen(g_strategyFilterGeometryText)-1);
   if(StringLen(g_strategyFilterGeometryText)>0&&StringSubstr(g_strategyFilterGeometryText,StringLen(g_strategyFilterGeometryText)-1)==".")
      g_strategyFilterGeometryText=StringSubstr(g_strategyFilterGeometryText,0,StringLen(g_strategyFilterGeometryText)-1);
   g_strategyFilterGeometryEnabled=geometryEnabled;g_strategyFilterGeometry=geometry;
   g_strategyFilterWrText=wrEnabled?DoubleToString(wr,1):"";
   g_strategyFilterMinCumText=mcEnabled?DoubleToString(mc,2):"";
   g_strategyFilterNetEnabled=netEnabled;g_strategyFilterWrEnabled=wrEnabled;g_strategyFilterMinCumEnabled=mcEnabled;
   g_strategyFilterNet=net;g_strategyFilterWr=wr;g_strategyFilterMinCum=mc;
   return true;
}

void OrbStrategyPresetBuildMatches(const string query)
{
   OrbStrategyLoadFavorites();
   g_strategySearch=query;string needle=OrbStrategyPresetLower(query);
   StringTrimLeft(needle);StringTrimRight(needle);
   ArrayResize(g_strategyMatches,0);
   for(int i=0;i<OrbStrategyPresetCount();i++)
   {
      OrbStrategyPreset p;if(!OrbStrategyPresetLoad(i,p))continue;
      if(g_strategyFavoritesOnly&&!OrbStrategyIsFavorite(i))continue;
      string hay=OrbStrategyPresetLower(p.name+" "+p.id+" "+p.searchTerms+" "+p.sourceImage);
      if(needle!=""&&StringFind(hay,needle)<0)continue;
      if(!OrbStrategyPresetPassesMetricFilters(p))continue;
      int n=ArraySize(g_strategyMatches);ArrayResize(g_strategyMatches,n+1);g_strategyMatches[n]=i;
   }
   int maxPage=MathMax(0,(ArraySize(g_strategyMatches)-1)/5);
   g_strategySearchPage=MathMax(0,MathMin(maxPage,g_strategySearchPage));
}

void OrbStrategyPresetRefreshVisible()
{
   g_strategyVisibleCount=0;
   for(int i=0;i<5;i++)g_strategyVisible[i]=-1;
   if(!g_strategyPopupOpen)return;
   int start=g_strategySearchPage*5;
   for(int slot=0;slot<5;slot++)
   {
      int pos=start+slot;if(pos>=ArraySize(g_strategyMatches))break;
      g_strategyVisible[slot]=g_strategyMatches[pos];g_strategyVisibleCount++;
   }
}

string OrbStrategyPresetCurrentName()
{
   OrbStrategyPreset p;
   return g_strategyPresetIndex>=0&&OrbStrategyPresetLoad(g_strategyPresetIndex,p)?p.name:"CUSTOM";
}

string OrbStrategyPresetCandidateName()
{
   OrbStrategyPreset p;
   return g_strategyCandidateIndex>=0&&OrbStrategyPresetLoad(g_strategyCandidateIndex,p)?p.name:"SELECT A STRATEGY";
}

long RuntimeMagic()
{
   if(g_runtimeMagic!=0)return g_runtimeMagic;
   if(RiskEnabled())
   {
      long safe=InpMagic%1000000000000;if(safe<0)safe=-safe;
      g_runtimeMagic=4000000000000000000+safe*1000000+(long)(ChartID()%1000000);
   }
   else if(InpUseChartScopedMagic) g_runtimeMagic=InpMagic*1000000+(long)(ChartID()%1000000);
   else g_runtimeMagic=InpMagic;
   return g_runtimeMagic;
}
bool MagicScoped(long m){return m>=4000000000000000000&&m<5000000000000000000;}
bool MagicOwned(long m){return m==RuntimeMagic()||MaRecoveredMagicOwned(m)||(!RiskEnabled()&&m==InpMagic);}
string BtFillLabel(BT_FILL_MODE m){switch(m){case BT_FILL_SIGNAL_CLOSE:return"SIGNAL";case BT_FILL_NEXT_BAR_OPEN:return"NEXT";case BT_FILL_CONSERVATIVE:return"CONS";}return"SIGNAL";}
string BtSameBarLabel(BT_SAME_BAR_POLICY p){switch(p){case BT_SAMEBAR_CONSERVATIVE:return"CONS";case BT_SAMEBAR_NEAREST_OPEN:return"NEAR";case BT_SAMEBAR_TP_FIRST:return"TP1ST";case BT_SAMEBAR_SL_FIRST:return"SL1ST";}return"CONS";}
double BtCostRForSpread(double risk,double spreadPoints,bool includeSlippage=true)
{
   if(risk<=0)return 0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.00001;
   double pts=MathMax(0.0,spreadPoints);
   if(includeSlippage)pts+=MathMax(0,g_btSlippagePts);
   double cost=pts*pt/risk;
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(ts>0&&tv>0&&g_btCommissionPerLot>0)
   {
      double riskMoney=(risk/ts)*tv;
      if(riskMoney>0)cost+=g_btCommissionPerLot/riskMoney;
   }
   return cost;
}
double BtCostR(double risk,bool includeSpread=true,bool includeSlippage=true)
{
   return BtCostRForSpread(risk,includeSpread?g_btSpreadPts:0.0,includeSlippage);
}
bool BtTpFirst(bool isBuy,double openPx,double sl,double tp)
{
   // OHLC bars cannot reveal intrabar ordering. Apply the configured policy
   // identically to normal and inverted trades; never manufacture W/L parity.
   if(g_btSameBarPolicy==BT_SAMEBAR_TP_FIRST)return true;
   if(g_btSameBarPolicy==BT_SAMEBAR_SL_FIRST||g_btSameBarPolicy==BT_SAMEBAR_CONSERVATIVE)return false;
   double dTp=isBuy?(tp-openPx):(openPx-tp);
   double dSl=isBuy?(openPx-sl):(sl-openPx);
   return dTp<dSl;
}

bool BuildSimGeometry(bool isBuy,double fillEntry,double plannedSl,
                      double &simSl,double &risk,double &tp1,double &tp2,double &tp3,double &tp4,double &tp5,double &tp6,
                      double sourceReferenceEntry,string &geometryDetail)
{
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   bool sourceIsBuy=g_rtInvertMode?!isBuy:isBuy;
   double rawSl=plannedSl;
   if(g_orbHigh>g_orbLow)
   {
      double buffer=MathMax(0.0,InpSlBufferPoints)*pt;
      rawSl=sourceIsBuy?(g_orbLow-buffer):(g_orbHigh+buffer);
   }
   geometryDetail="";
   if(!ResolveExecutionStop(sourceIsBuy,isBuy,fillEntry,rawSl,simSl,risk,geometryDetail,sourceReferenceEntry))return false;
   tp1=NormalizePrice(PriceAtLeg(isBuy,fillEntry,risk,1));
   tp2=NormalizePrice(PriceAtLeg(isBuy,fillEntry,risk,2));
   tp3=NormalizePrice(PriceAtLeg(isBuy,fillEntry,risk,3));
   tp4=NormalizePrice(PriceAtLeg(isBuy,fillEntry,risk,4));
   tp5=NormalizePrice(PriceAtLeg(isBuy,fillEntry,risk,5));
   tp6=NormalizePrice(PriceAtLeg(isBuy,fillEntry,risk,6));
   return true;
}

double SimSignedR(bool isBuy,double entry,double exitPrice,double risk)
{
   if(risk<=0.0)return 0.0;
   return isBuy?(exitPrice-entry)/risk:(entry-exitPrice)/risk;
}

// Resolve a forced lifecycle exit at the event timestamp. Tick data is exact;
// M1 is the bounded fallback when a broker does not retain historical ticks.
bool ResolveHistoricalForcedExitPrice(datetime eventTime,bool isBuy,double fallbackOpen,double fallbackSpreadPts,
                                      double &exitPrice,datetime &resolvedTime)
{
   exitPrice=0.0;resolvedTime=eventTime;
   if(eventTime<=0)return false;
   MqlTick ticks[];
   int tickCount=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,
      (ulong)eventTime*1000,(ulong)(eventTime+300)*1000);
   for(int i=0;i<tickCount;i++)
   {
      double px=isBuy?ticks[i].bid:ticks[i].ask;
      if(px<=0.0)continue;
      exitPrice=NormalizeTradePrice(px);
      resolvedTime=(datetime)ticks[i].time;
      return true;
   }

   MqlRates m1[];
   int copied=CopyRates(_Symbol,PERIOD_M1,eventTime-60,eventTime+120,m1);
   int selected=-1;
   for(int i=0;i<copied;i++)
   {
      if(m1[i].time<=eventTime)selected=i;
      else if(selected<0){selected=i;break;}
   }
   if(selected>=0)
   {
      double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
      double spreadPts=m1[selected].spread>0?(double)m1[selected].spread:fallbackSpreadPts;
      exitPrice=NormalizeTradePrice(isBuy?m1[selected].open:m1[selected].open+MathMax(0.0,spreadPts)*pt);
      resolvedTime=eventTime;
      return exitPrice>0.0;
   }

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(point<=0.0)point=0.00001;
   exitPrice=NormalizeTradePrice(isBuy?fallbackOpen:fallbackOpen+MathMax(0.0,fallbackSpreadPts)*point);
   return exitPrice>0.0;
}

bool IsSimMarketExitOutcome(string outcome)
{
   return outcome=="MID_EXIT"||outcome=="VWAP_EXIT"||outcome=="EMA_EXIT"
      ||outcome=="EOD_EXIT"||outcome=="TIME_EXIT"||outcome=="BROKER_TIME_EXIT"
      ||outcome=="FILTER_REVERSE_EXIT"||outcome=="DISP_BLOCK_EXIT"
      ||outcome=="NAS_OPPOSITE_EXIT"||outcome=="NAS_ADDITIONAL_EXIT"||outcome=="MA_REVERSE_EXIT"
      ||outcome=="LAB_RULE_EXIT"||outcome=="LAB_TIME_EXIT";
}

bool ResolveSourceTargetPriceAndR(bool sourceIsBuy,double entry,double sourceRisk,double &targetPrice,double &targetR,string &detail)
{
   targetPrice=0.0;
   targetR=0.0;
   detail=RuntimeTargetModeLabel();
   if(sourceRisk<=0.0)return false;
   if(g_rtTargetMode==ORB_TARGET_EOD)
   {
      detail+=" no_fixed_tp";
      return true;
   }
   if(g_rtTargetMode==ORB_TARGET_RANGE_HEIGHT)
   {
      double range=MathAbs(g_orbHigh-g_orbLow);
      if(range<=0.0)return false;
      targetR=(range*MathMax(0.1,InpRangeTargetMultiplier))/sourceRisk;
      targetPrice=NormalizeTradePrice(sourceIsBuy?entry+sourceRisk*targetR:entry-sourceRisk*targetR);
      detail+=" range="+DoubleToString(range,_Digits)+" mult="+DoubleToString(InpRangeTargetMultiplier,2)+" r="+DoubleToString(targetR,2);
      return true;
   }
   if(g_rtTargetMode==ORB_TARGET_AUTO_STOP_SIZE)
   {
      double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
      double stopPts=sourceRisk/pt;
      targetR=stopPts<=MathMax(0.0,InpSmallStopThresholdPts)?MathMax(0.1,InpSmallStopTargetR):MathMax(0.1,InpLargeStopTargetR);
      targetPrice=NormalizeTradePrice(sourceIsBuy?entry+sourceRisk*targetR:entry-sourceRisk*targetR);
      detail+=" stopPts="+DoubleToString(stopPts,1)+" r="+DoubleToString(targetR,2);
      return true;
   }
   int targetLeg=RuntimeTargetLeg();
   targetR=LegR(targetLeg);
   targetPrice=PriceAtLeg(sourceIsBuy,entry,sourceRisk,targetLeg);
   if(targetLeg==(int)ORB_TARGET_CUSTOM
      && (sourceIsBuy?targetPrice-entry:entry-targetPrice)
         <= MathMax(TickSize()*0.5,MinStopDistance()*1.20))
   {detail="custom_target_below_tradable_distance";return false;}
   detail+=" target="+TargetCode(targetLeg)+" r="+DoubleToString(targetR,2);
   return true;
}

struct OrbPureSwapGeometry
{
   bool sourceIsBuy;
   bool execIsBuy;
   double sourceEntry;
   double execEntry;
   double sourceSl;
   double sourceTp;
   double sourceRisk;
   double sourceTargetR;
   double execSl;
   double execTp;
   double execRisk;
   double execTargetR;
};

bool ResolvePureSwapGeometry(bool sourceIsBuy,bool execIsBuy,double sourceEntry,double execEntry,double sourceRawSl,
                             OrbPureSwapGeometry &geometry,string &detail,bool enforceCost=false)
{
   detail="";
   geometry.sourceIsBuy=sourceIsBuy;geometry.execIsBuy=execIsBuy;
   geometry.sourceEntry=sourceEntry;geometry.execEntry=execEntry;
   geometry.sourceSl=0.0;geometry.sourceTp=0.0;geometry.sourceRisk=0.0;geometry.sourceTargetR=0.0;
   geometry.execSl=0.0;geometry.execTp=0.0;geometry.execRisk=0.0;geometry.execTargetR=0.0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double tolerance=MathMax(pt*0.51,TickSize()*0.51);
   if(sourceIsBuy==execIsBuy){detail="pure_swap_direction_not_inverted";return false;}

   geometry.sourceSl=ApplyRuntimeSlFromEntry(sourceIsBuy,sourceEntry,sourceRawSl);
   geometry.sourceRisk=MathAbs(sourceEntry-geometry.sourceSl);
   if(geometry.sourceRisk<=tolerance){detail="pure_swap_source_sl_invalid";return false;}
   string sourceDetail="";
   if(!ResolveSourceTargetPriceAndR(sourceIsBuy,sourceEntry,geometry.sourceRisk,
                                    geometry.sourceTp,geometry.sourceTargetR,sourceDetail)
      ||geometry.sourceTp<=0.0||geometry.sourceTargetR<=0.0)
   {detail="pure_swap_requires_fixed_target "+sourceDetail;return false;}

   if(enforceCost&&g_rtAdvancedReverseMaxCostPct<100.0)
   {
      double sourceTargetDistance=geometry.sourceRisk*geometry.sourceTargetR;
      double quoteGapPct=100.0*MathAbs(sourceEntry-execEntry)/sourceTargetDistance;
      if(quoteGapPct>g_rtAdvancedReverseMaxCostPct+1e-8)
      {
         detail="INVERSE_GAP_BLOCK quote_gap_pct="+DoubleToString(quoteGapPct,4)
            +" max_pct="+DoubleToString(g_rtAdvancedReverseMaxCostPct,4);
         return false;
      }
   }

   // Inverse SL keeps the source TP; inverse TP reserves the entry quote gap.
   geometry.execSl=geometry.sourceTp;
   geometry.execRisk=MathAbs(execEntry-geometry.execSl);
   if(geometry.execRisk<=tolerance){detail="pure_swap_execution_risk_invalid";return false;}
   // A reversed TP is closed on the opposite quote from the source SL.
   // Reserve the observed entry quote gap; replay and live orders use this
   // same executable price, while preflight without quotes remains unshifted.
   double askBuffer=enforceCost?MathAbs(sourceEntry-execEntry):0.0;
   geometry.execTp=NormalizeTradePrice(geometry.sourceSl+(execIsBuy?-askBuffer:askBuffer));
   double targetDistance=execIsBuy?(geometry.execTp-execEntry):(execEntry-geometry.execTp);
   if((execIsBuy&&geometry.execSl>=execEntry-tolerance)
      ||(!execIsBuy&&geometry.execSl<=execEntry+tolerance))
   {detail="pure_swap_stop_wrong_side";return false;}
   if(targetDistance<=tolerance){detail="pure_swap_target_wrong_side";return false;}
   if(enforceCost&&targetDistance<=MinStopDistance()+askBuffer)
   {detail="INVERSE_GAP_BLOCK broker_min_target";return false;}
   geometry.execTargetR=targetDistance/geometry.execRisk;
   // A 1R target must not silently become a tiny TP after quote conversion.
   if(enforceCost&&g_rtAdvancedReverseMaxCostPct<100.0
      &&MathAbs(geometry.sourceTargetR-1.0)<=0.01
      &&geometry.execTargetR+1e-6<1.0-g_rtAdvancedReverseMaxCostPct/100.0)
   {
      detail="INVERSE_GAP_BLOCK r_floor effective_r="+DoubleToString(geometry.execTargetR,4)
         +" min_r="+DoubleToString(1.0-g_rtAdvancedReverseMaxCostPct/100.0,4);
      return false;
   }

   detail="LEVEL_SWAP_INVERSE_OK source_entry="+DoubleToString(sourceEntry,_Digits)
      +" exec_entry="+DoubleToString(execEntry,_Digits)
      +" source_sl="+DoubleToString(geometry.sourceSl,_Digits)
      +" source_tp="+DoubleToString(geometry.sourceTp,_Digits)
      +" exec_sl="+DoubleToString(geometry.execSl,_Digits)
      +" exec_tp="+DoubleToString(geometry.execTp,_Digits)
      +" source_r="+DoubleToString(geometry.sourceTargetR,4)
      +" effective_r="+DoubleToString(geometry.execTargetR,4)
      +" ask_buffer="+DoubleToString(askBuffer,_Digits);
   return true;
}

bool ResolveExecutionStop(bool sourceIsBuy,bool execIsBuy,double entry,double sourceRawSl,
                          double &executionSl,double &executionRisk,string &detail,double sourceReferenceEntry=0.0)
{
   executionSl=0.0;executionRisk=0.0;detail="";
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double sourceEntry=sourceReferenceEntry>0.0?sourceReferenceEntry:entry;
   double sourceSl=ApplyRuntimeSlFromEntry(sourceIsBuy,sourceEntry,sourceRawSl);
   double sourceRisk=MathAbs(sourceEntry-sourceSl);
   if(sourceRisk<=pt){detail="source_sl_invalid";return false;}
   if(!g_rtInvertMode)
   {
      executionSl=sourceSl;executionRisk=sourceRisk;
      return true;
   }
   if(InpExecutionMode!=ORB_EXEC_SINGLE){detail="pure_swap_requires_single_order";return false;}
   OrbPureSwapGeometry geometry;
   if(!ResolvePureSwapGeometry(sourceIsBuy,execIsBuy,sourceEntry,entry,sourceRawSl,geometry,detail,sourceReferenceEntry>0.0))return false;
   executionSl=geometry.execSl;
   executionRisk=geometry.execRisk;
   return true;
}

bool ResolveTargetPriceAndR(bool isBuy,double entry,double risk,double &targetPrice,double &targetR,string &detail,double sourceReferenceEntry=0.0)
{
   if(!g_rtInvertMode)return ResolveSourceTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,detail);
   targetPrice=0.0;targetR=0.0;detail="";
   if(InpExecutionMode!=ORB_EXEC_SINGLE||risk<=0.0){detail="pure_swap_unsupported_mode";return false;}
   bool sourceIsBuy=!isBuy;
   double sourceEntry=sourceReferenceEntry>0.0?sourceReferenceEntry:entry;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double buffer=MathMax(0.0,InpSlBufferPoints)*pt;
   double sourceRawSl=sourceIsBuy?(g_orbLow-buffer):(g_orbHigh+buffer);
   OrbPureSwapGeometry geometry;
   if(!ResolvePureSwapGeometry(sourceIsBuy,isBuy,sourceEntry,entry,sourceRawSl,geometry,detail,sourceReferenceEntry>0.0))return false;
   double tolerance=MathMax(pt*0.51,TickSize()*0.51);
   if(MathAbs(risk-geometry.execRisk)>tolerance)
   {detail="pure_swap_risk_snapshot_mismatch "+detail;return false;}
   targetPrice=geometry.execTp;
   targetR=geometry.execTargetR;
   return targetR>0.0&&targetPrice>0.0;
}
datetime BrokerTimeExitFor(datetime openTime)
{
   MqlDateTime d;TimeToStruct(openTime,d);
   int hh=MathMax(0,MathMin(23,InpBrokerTimeExitHour));
   int mm=MathMax(0,MathMin(59,InpBrokerTimeExitMinute));
   datetime t=MakeDateTime(d.year,d.mon,d.day,hh,mm,0);
   if(t<=openTime)t+=86400;
   return t;
}

datetime BarCloseTime(ENUM_TIMEFRAMES tf, datetime barOpen)
{
   int sec = PeriodSeconds(tf);
   if(sec <= 0) sec = 60;
   return barOpen + sec;
}

int RuntimeBtTfIndex()
{
   for(int i = 0; i < OBT_TF_COUNT; i++)
      if(g_btTFs[i] == g_rtSignalTf)
         return i;
   return 2; // M15 default.
}

bool ValidateOpenStops(string dir,double entry,double sl,double tp,string &reason)
{
   double md=MinStopDistance();
   if(entry<=0||sl<=0){reason="zero_geometry";return false;}
   if(dir=="BUY")
   {
      if(sl>=entry-md){reason="buy_sl_inside_stop_level";return false;}
      if(tp>0&&tp<=entry+md){reason="buy_tp_inside_stop_level";return false;}
   }
   else
   {
      if(sl<=entry+md){reason="sell_sl_inside_stop_level";return false;}
      if(tp>0&&tp>=entry-md){reason="sell_tp_inside_stop_level";return false;}
   }
   return true;
}

void AdjustOpenStops(string dir,double entry,double &sl,double &tp,string &detail)
{
   double md=MinStopDistance()*1.20;
   double ts=TickSize();
   double oldSl=NormalizeTradePrice(sl),oldTp=NormalizeTradePrice(tp);
   sl=oldSl;tp=oldTp;
   if(dir=="BUY")
   {
      if(sl>=entry-md)sl=NormalizeTradePrice(entry-md);
      if(tp>0&&tp<=entry+md)tp=NormalizeTradePrice(entry+md);
   }
   else
   {
      if(sl<=entry+md)sl=NormalizeTradePrice(entry+md);
      if(tp>0&&tp>=entry-md)tp=NormalizeTradePrice(entry-md);
   }
   detail="";
   if(MathAbs(sl-oldSl)>ts*0.5||MathAbs(tp-oldTp)>ts*0.5)
      detail="stops_adjusted old_sl="+DoubleToString(oldSl,_Digits)+" old_tp="+DoubleToString(oldTp,_Digits)+" sl="+DoubleToString(sl,_Digits)+" tp="+DoubleToString(tp,_Digits)+" ";
}

ulong NewestOwnTicket()
{
   ulong best=0;
   datetime bestTime=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;
      datetime tm=(datetime)PositionGetInteger(POSITION_TIME);
      if(best==0||tm>=bestTime){best=t;bestTime=tm;}
   }
   return best;
}

ulong FilledOwnTicket(const ulong deal,const ulong order)
{
   ulong positionId=0;
   if(deal>0&&HistoryDealSelect(deal))positionId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   if(positionId==0)positionId=order;
   if(positionId==0)return 0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0&&PositionSelectByTicket(ticket)&&IsOwnPosition()
         &&(ulong)PositionGetInteger(POSITION_IDENTIFIER)==positionId)return ticket;
   }
   return 0;
}

bool SendOrbOrder(string dir,double lot,double entry,double sl,double tp,string comment,string &detail)
{
   // NAT controls new native entries independently of bridge routing.
   if(!g_orbNativeWithBridgeOnly){detail="native_off";return false;}
   ENUM_ORDER_TYPE type=dir=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   bool ok=trade.PositionOpen(_Symbol,type,lot,entry,sl,tp,comment);
   uint rc=trade.ResultRetcode();
   if(g_rtInvertMode&&rc==TRADE_RETCODE_PLACED)
   {
      ulong order=trade.ResultOrder();
      bool cancelled=order>0&&trade.OrderDelete(order);
      detail="advanced_reverse_order_not_filled order="+IntegerToString((long)order)+" cancel="+(cancelled?"1":"0");
      Audit("advanced_reverse_pending_rejected",dir,lot,entry,sl,tp,detail);
      return false;
   }
   if(ok&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED))
   {
      if(g_rtInvertMode)
      {
         ulong ticket=FilledOwnTicket(trade.ResultDeal(),trade.ResultOrder());
         bool selected=ticket>0&&PositionSelectByTicket(ticket);
         double actualEntry=selected?PositionGetDouble(POSITION_PRICE_OPEN):0.0;
         double actualSl=selected?PositionGetDouble(POSITION_SL):0.0;
         double actualTp=selected?PositionGetDouble(POSITION_TP):0.0;
         double tolerance=TickSize()*0.51;
         if(!selected||MathAbs(actualEntry-entry)>tolerance
            ||MathAbs(actualSl-sl)>tolerance||MathAbs(actualTp-tp)>tolerance)
         {
            bool closed=selected&&trade.PositionClose(ticket);
            detail="advanced_reverse_fill_mismatch ticket="+IntegerToString((long)ticket)
               +" entry="+DoubleToString(actualEntry,_Digits)+" sl="+DoubleToString(actualSl,_Digits)
               +" tp="+DoubleToString(actualTp,_Digits)+" emergency_close="+(closed?"1":"0");
            Audit("advanced_reverse_fill_mismatch",dir,lot,entry,sl,tp,detail);
            if(!closed)Print("CRITICAL: Advanced Reverse fill mismatch; emergency close failed. ",detail);
            return false;
         }
      }
      detail="order_ok ret="+IntegerToString((int)rc);
      return true;
   }
   if(rc!=TRADE_RETCODE_INVALID_STOPS && rc!=10016)
   {
      detail="order_failed ret="+IntegerToString((int)rc)+" "+trade.ResultRetcodeDescription();
      return false;
   }

    string firstFail="invalid_stops ret="+IntegerToString((int)rc)+" "+trade.ResultRetcodeDescription();
   if(g_rtInvertMode)
   {
      detail=firstFail+" advanced_reverse_unprotected_retry_blocked";
      return false;
   }
   if(!g_orbNativeWithBridgeOnly){detail=firstFail+" native_off_retry_blocked";return false;}
   bool naked=trade.PositionOpen(_Symbol,type,lot,entry,0,0,comment+"|naked");
   uint nakedRc=trade.ResultRetcode();
   if(!(naked&&(nakedRc==TRADE_RETCODE_DONE||nakedRc==TRADE_RETCODE_DONE_PARTIAL||nakedRc==TRADE_RETCODE_PLACED)))
   {
      detail=firstFail+" naked_failed ret="+IntegerToString((int)nakedRc)+" "+trade.ResultRetcodeDescription();
      return false;
   }
   ulong t=NewestOwnTicket();
   if(t>0&&PositionSelectByTicket(t))
   {
      bool mod=trade.PositionModify(t,sl,tp);
      uint modRc=trade.ResultRetcode();
      if(mod)
      {
         detail=firstFail+" naked_modify_ok ticket="+IntegerToString((long)t);
         return true;
      }
      bool closed=trade.PositionClose(t);
      detail=firstFail+" naked_modify_failed ret="+IntegerToString((int)modRc)+" "+trade.ResultRetcodeDescription()+" emergency_close="+(closed?"1":"0");
      return false;
   }
   detail=firstFail+" naked_opened_but_ticket_not_found";
   return false;
}

bool CanModifySlTo(double sl,int dir,string &reason)
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double md=MinStopDistance();
   if(bid<=0||ask<=0||sl<=0){reason="no_tick";return false;}
   if(dir>0&&sl>bid-md){reason="be_inside_buy_stop_level";return false;}
   if(dir<0&&sl<ask+md){reason="be_inside_sell_stop_level";return false;}
   return true;
}

//=========================================================================
//  AUDIT — Advanced Trade Lifecycle CSV (Signatics pattern)
//=========================================================================
string AuditDateStr(){MqlDateTime d;TimeToStruct(TimeGMT(),d);return StringFormat("%04d%02d%02d",d.year,d.mon,d.day);}
string AuditFileName(){return "ORB15_TradeAudit_"+AuditDateStr()+".csv";}
string AuditPx(double p){return p<=0?"0":DoubleToString(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}

void OBT_ProcessAudit(string ev,string detail)
{
   if(IsTesterMode() && !IsValidationTester()) return;
   if(!g_auditRuntime) return;
   string fileName="ORB15_BacktestProcess_"+AuditDateStr()+".csv";
   bool exists=FileIsExist(fileName);
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return;
   if(!exists||FileSize(h)==0)
      FileWrite(h,"gmt_time","server_time","event","build","symbol","chart_tf","result_file","weeks","requested_from","calendar_days","trading_days_cached","valid_orb_days","combos_total","step","elapsed_ms","detail");
   FileSeek(h,0,SEEK_END);
   int validDays=0;
   for(int i=0;i<g_btDayCount;i++)if(g_btDays[i].valid)validDays++;
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      ev,ORB15_BUILD,_Symbol,EnumToString(_Period),g_btFileName,
      IntegerToString(g_btWeeks),
      TimeToString(TimeCurrent()-g_btWeeks*7*86400,TIME_DATE|TIME_SECONDS),
      IntegerToString(g_btWeeks*7),IntegerToString(g_btDayCount),IntegerToString(validDays),
      IntegerToString(g_btTotal),IntegerToString(g_btStep),IntegerToString((int)g_btElapsedMs),detail);
   FileClose(h);
}

bool OrbAuditCritical(string ev)
{
   return StringFind(ev,"fail")>=0||StringFind(ev,"error")>=0||StringFind(ev,"block")>=0||
      StringFind(ev,"risk")>=0||StringFind(ev,"breach")>=0||StringFind(ev,"opened")>=0||
      StringFind(ev,"close")>=0||StringFind(ev,"half")>=0||StringFind(ev,"sl_to_be")>=0||
      StringFind(ev,"bridge")>=0||StringFind(ev,"order")>=0||StringFind(ev,"position_")>=0;
}

void Audit(string ev,string dir,double lot,double entry,double sl,double tp,string detail)
{
   if(IsTesterMode()) return;
   if(!g_auditRuntime&&!OrbAuditCritical(ev))return;
   string fileName=AuditFileName();
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return;
   bool empty=(FileSize(h)<=0);
   FileSeek(h,0,SEEK_END);
   if(empty)
      FileWrite(h,"ts_gmt","ts_server","ts_local","ms","event","build","symbol","timeframe",
         "signal_tf","delay","atr_f","vol_f","day_f","be","direction",
         "lot","entry","sl","tp","orb_h","orb_l","bid","ask","spread","sl_mode","pip_sl_pips","regime_id","regime_name","regime_allowed","detail");
   int ms=(int)(GetTickCount()%1000);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
      IntegerToString(ms),
      ev, ORB15_BUILD, _Symbol, EnumToString(_Period),
      TfLabel(g_rtSignalTf), IntegerToString(g_rtDelayMin),
      (g_rtFilterAtr?"1":"0"),(g_rtFilterVol?"1":"0"),(g_rtFilterDay?"1":"0"),(g_rtBEOnTp1?"1":"0"),
      dir, DoubleToString(lot,2), AuditPx(entry), AuditPx(sl), AuditPx(tp),
      AuditPx(g_orbHigh), AuditPx(g_orbLow), AuditPx(bid), AuditPx(ask),
      IntegerToString(CurrentSpreadPoints()),g_rtPipSlMode?"PIP":"PERCENT",DoubleToString(g_rtPipSlPips,1),
      IntegerToString(g_lastSignalRegime),g_lastSignalRegimeName,OrbRegimeAllowed(g_lastSignalRegime)?"1":"0",detail);
   FileClose(h);
}

string OrbTesterAudit_FileStamp()
{
   MqlDateTime d; TimeToStruct(TimeGMT(), d);
   return StringFormat("%04d%02d%02d_%02d%02d%02d", d.year, d.mon, d.day, d.hour, d.min, d.sec);
}

string OrbTesterAudit_DealEntryLabel(long entryType)
{
   if(entryType == DEAL_ENTRY_IN) return "IN";
   if(entryType == DEAL_ENTRY_OUT) return "OUT";
   if(entryType == DEAL_ENTRY_INOUT) return "INOUT";
   if(entryType == DEAL_ENTRY_OUT_BY) return "OUT_BY";
   return IntegerToString((int)entryType);
}

string OrbTesterAudit_DealTypeLabel(long dealType)
{
   if(dealType == DEAL_TYPE_BUY) return "BUY";
   if(dealType == DEAL_TYPE_SELL) return "SELL";
   if(dealType == DEAL_TYPE_BALANCE) return "BALANCE";
   if(dealType == DEAL_TYPE_CREDIT) return "CREDIT";
   return IntegerToString((int)dealType);
}

string OrbTesterAudit_DealReasonLabel(long reason)
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

void OrbTesterAudit_Init()
{
   g_testerTradeAuditRows = 0;
   g_testerTradeAuditFile = "ORB15_TesterTradeAudit_" + OrbTesterAudit_FileStamp() + ".csv";
}

void OrbTesterAudit_WriteDeal(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpTesterTradeAuditCsv || !MQLInfoInteger(MQL_TESTER)) return;
   if(InpTesterTradeAuditMaxRows > 0 && g_testerTradeAuditRows >= InpTesterTradeAuditMaxRows) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   long magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(!MagicOwned(magic)) return;

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
      InpValidationJobId, "mt5_strategy_tester_trade", "OrbUltimateEA", ORB15_BUILD, _Symbol, EnumToString(_Period),
      TimeToString((datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME), TIME_DATE|TIME_SECONDS),
      TimeToString(TimeGMT(), TIME_DATE|TIME_SECONDS),
      IntegerToString((long)trans.deal),
      IntegerToString((long)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID)),
      IntegerToString((long)HistoryDealGetInteger(trans.deal, DEAL_ORDER)),
      OrbTesterAudit_DealEntryLabel(HistoryDealGetInteger(trans.deal, DEAL_ENTRY)),
      OrbTesterAudit_DealTypeLabel(HistoryDealGetInteger(trans.deal, DEAL_TYPE)),
      OrbTesterAudit_DealReasonLabel(HistoryDealGetInteger(trans.deal, DEAL_REASON)),
      IntegerToString(magic),
      DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 4),
      AuditPx(HistoryDealGetDouble(trans.deal, DEAL_PRICE)),
      AuditPx(request.price), AuditPx(request.sl), AuditPx(request.tp),
      DoubleToString(profit, 2), DoubleToString(swap, 2), DoubleToString(commission, 2), DoubleToString(fee, 2),
      IntegerToString((int)result.retcode),
      HistoryDealGetString(trans.deal, DEAL_COMMENT));
   FileClose(h);
   g_testerTradeAuditRows++;
}

//=========================================================================
//  POSITION HELPERS
//=========================================================================
bool IsOwnPosition(){return PositionGetString(POSITION_SYMBOL)==_Symbol&&MagicOwned((long)PositionGetInteger(POSITION_MAGIC));}
bool OwnPositionExists(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(IsOwnPosition())return true;}return false;}
int OwnPositionCount(){int c=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(IsOwnPosition())c++;}return c;}
void CloseAllOwn(string reason="close_all")
{
   int publishDir=g_tradeDir;
   if(publishDir==0)
      for(int p=PositionsTotal()-1;p>=0;p--){ulong pt=PositionGetTicket(p);if(pt>0&&PositionSelectByTicket(pt)&&IsOwnPosition()){publishDir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;break;}}
   if(publishDir!=0)OrbProPublishCloseOnly(publishDir,reason);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;
      bool ok=trade.PositionClose(t);
      Audit(ok?"close":"close_failed","",PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),"reason="+reason+" ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   }
}

string RiskKey(const string keyName)
{
   return "ORB15_FTMO_"+IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+keyName;
}
datetime RiskDayStart()
{
   MqlDateTime g;TimeToStruct(TimeGMT(),g);
   int rh=MathMax(0,MathMin(23,InpDayResetHourGmt));
   datetime d=MakeDateTime(g.year,g.mon,g.day,rh,0,0);
   if(TimeGMT()<d)d-=86400;
   return d;
}
double RiskInitialBal(){if(InpInitialBalanceOverride>0)return InpInitialBalanceOverride;string k=RiskKey("INITIAL_BALANCE");if(!GlobalVariableCheck(k))GlobalVariableSet(k,MathMax(0.01,AccountInfoDouble(ACCOUNT_BALANCE)));return MathMax(0.01,GlobalVariableGet(k));}

void RiskScopePerf(double &closedAll,double &closedToday,double &floating)
{
   datetime now=TimeCurrent();
   if(g_riskPerfCacheAt==now)
   {
      closedAll=g_riskPerfClosedAll;
      closedToday=g_riskPerfClosedToday;
      floating=g_riskPerfFloating;
      return;
   }
   closedAll=0;closedToday=0;floating=0;
   datetime dayStart=RiskDayStart();
   HistorySelect(0,TimeCurrent());
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong tk=HistoryDealGetTicket(i);if(tk==0)continue;
      if(!MagicScoped((long)HistoryDealGetInteger(tk,DEAL_MAGIC)))continue;
      ENUM_DEAL_ENTRY de=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY);
      if(de!=DEAL_ENTRY_OUT&&de!=DEAL_ENTRY_INOUT)continue;
      double pnl=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION)+HistoryDealGetDouble(tk,DEAL_FEE);
      closedAll+=pnl;
      if((datetime)HistoryDealGetInteger(tk,DEAL_TIME)>=dayStart)closedToday+=pnl;
   }
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong t=PositionGetTicket(p);if(t==0||!PositionSelectByTicket(t))continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))continue;
      floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   g_riskPerfCacheAt=now;
   g_riskPerfClosedAll=closedAll;
   g_riskPerfClosedToday=closedToday;
   g_riskPerfFloating=floating;
}

void RiskMetrics(double &cap,double &dailyPct,double &totalPct)
{
   double init=RiskInitialBal(),ca,ct,fl;RiskScopePerf(ca,ct,fl);
   cap=MathMax(0.01,init+ca+fl);
   double dayBase=MathMax(0.01,init+ca-ct);
   dailyPct=MathMax(0.0,-(ct+fl)/dayBase*100.0);
   totalPct=MathMax(0.0,-(ca+fl)/init*100.0);
}

double OpenScopeRisk()
{
   double openRisk=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))continue;
      double sl=PositionGetDouble(POSITION_SL);if(sl<=0)continue;
      ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double r=0;
      if(OrderCalcProfit(pt==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,PositionGetString(POSITION_SYMBOL),PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),sl,r))
         openRisk+=MathMax(0,-r);
   }
   return openRisk;
}

double OwnFixedRiskMoney()
{
   double risk=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),volume=PositionGetDouble(POSITION_VOLUME),result=0.0;
      if(sl<=0.0||volume<=0.0)return -1.0;
      ENUM_ORDER_TYPE side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(!OrderCalcProfit(side,_Symbol,volume,entry,sl,result))return -1.0;
      risk+=MathAbs(result);
   }
   return risk;
}
bool ValidateFixedReferencePostFill(string &detail)
{
   if(!FixedReferenceRiskMode())return true;
   double budget=RiskBudgetMoney(),actual=OwnFixedRiskMoney(),maximum=budget+MathMax(0.0,InpFixedRiskMaxOvershootMoney);
   detail="fixed_reference_post_fill actual="+DoubleToString(actual,2)+" budget="+DoubleToString(budget,2)+" maximum="+DoubleToString(maximum,2);
   if(budget>0.0&&actual>=0.0&&actual<=maximum)return true;
   for(int i=PositionsTotal()-1;i>=0;i--){ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;trade.PositionClose(ticket);}
   return false;
}

double ClosedDailyAtr(){int h=iATR(_Symbol,PERIOD_D1,MathMax(2,InpAtrPeriod));if(h==INVALID_HANDLE)return 0;double v[];ArraySetAsSeries(v,true);int c=CopyBuffer(h,0,1,1,v);IndicatorRelease(h);return(c==1&&v[0]>0)?v[0]:0;}

double ResolveLot(string dir,double entry,double sl,string &detail)
{
   double fallback=CalculateLot(entry,sl);
   if(!RiskEnabled()){detail="risk_off";return fallback;}
   double cap,dp,tp;RiskMetrics(cap,dp,tp);
   double sf=MathMax(1,MathMin(100,InpSafetyBufferPct))/100.0;
   double mu=cap>0?AccountInfoDouble(ACCOUNT_MARGIN)/cap*100.0:100.0;
   if(cap<=0||(EffDailyLossLimitPct()>0&&dp>=EffDailyLossLimitPct()*sf)||(EffMaxDrawdownPct()>0&&tp>=EffMaxDrawdownPct()*sf)||(EffMaxMarginUsagePct()>0&&mu>=EffMaxMarginUsagePct()))
   {detail="risk_block cap="+DoubleToString(cap,2)+" daily="+DoubleToString(dp,2)+" dd="+DoubleToString(tp,2);return (NativeBalanceEnabled()||InpFailClosed)?0:fallback;}
   ENUM_ORDER_TYPE ot=dir=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   bool fixedReference=FixedReferenceRiskMode();
   double slRes=0,atrRes=0,atr=ClosedDailyAtr();
   double atrExit=dir=="BUY"?entry-atr:entry+atr;
   bool slCalcOk=OrderCalcProfit(ot,_Symbol,1.0,entry,sl,slRes);
   bool atrCalcOk=fixedReference||((atr>0.0)&&OrderCalcProfit(ot,_Symbol,1.0,entry,atrExit,atrRes));
   if(!slCalcOk||!atrCalcOk)
   {detail="risk_calc_fail";return (NativeBalanceEnabled()||InpFailClosed)?0:fallback;}
   double slMpl=MathAbs(slRes),atrMpl=fixedReference?MathAbs(slRes):MathAbs(atrRes);
   if(slMpl<=0||(!fixedReference&&atrMpl<=0)){detail="risk_zero_mpl";return (NativeBalanceEnabled()||InpFailClosed)?0:fallback;}
   double tradeBudget=RiskBudgetMoney();
   if(FixedReferenceRiskMode()&&tradeBudget<=0.0){detail="fixed_reference_capital_invalid";return 0;}
   double atrBudget=cap*MathMax(0,EffAtrExposurePct())/100.0;
   double portfolioBudget=cap*MathMax(0,EffMaxPortfolioPct())/100.0;
   double avail=MathMax(0,portfolioBudget-OpenScopeRisk());
   if(tradeBudget<=0||(!FixedReferenceRiskMode()&&(atrBudget<=0||avail<=0))){detail="budget_exhausted";return 0;}
   double raw=FixedReferenceRiskMode()?tradeBudget/slMpl:MathMin(tradeBudget/slMpl,MathMin(atrBudget/atrMpl,avail/slMpl));
   double vol=NormalizeVolume(raw);
   double projectedRisk=slMpl*vol;
   if(NativeBalanceEnabled()&&NativeBalanceOverBudget(projectedRisk,tradeBudget))
   {detail="reference_balance_min_volume_exceeds_budget";return 0;}
   if(FixedReferenceRiskMode()&&projectedRisk>tradeBudget+MathMax(0.0,InpFixedRiskMaxOvershootMoney))
   {detail="fixed_reference_min_volume_exceeds_budget projected="+DoubleToString(projectedRisk,2)+" budget="+DoubleToString(tradeBudget,2);return 0;}
   double margin=0;bool mc=OrderCalcMargin(ot,_Symbol,vol,entry,margin);
   double proj=cap>0?(AccountInfoDouble(ACCOUNT_MARGIN)+margin)/cap*100.0:100.0;
   if(vol<=0||!mc||margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)||(EffMaxMarginUsagePct()>0&&proj>EffMaxMarginUsagePct())){detail="margin_block";return 0;}
   detail="lot="+DoubleToString(vol,4)+" cap="+DoubleToString(cap,2)+" trade_budget="+DoubleToString(tradeBudget,2)+" open_risk="+DoubleToString(OpenScopeRisk(),2);
   return vol;
}

void EnforceRiskBreach()
{
   if(!RiskEnabled()||!InpLiquidateOnBreach)return;
   if(EffDailyLossLimitPct()<=0&&EffMaxDrawdownPct()<=0)return;
   uint now=GetTickCount();if(now-g_lastRiskGuardMs<250)return;g_lastRiskGuardMs=now;
   double cap,dp,tp;RiskMetrics(cap,dp,tp);
   double sf=MathMax(1,MathMin(100,InpSafetyBufferPct))/100.0;
   bool breach=(EffDailyLossLimitPct()>0&&dp>=EffDailyLossLimitPct()*sf)||(EffMaxDrawdownPct()>0&&tp>=EffMaxDrawdownPct()*sf);
   if(!breach)return;
   Audit("risk_liquidate","",0,0,0,0,"cap="+DoubleToString(cap,2)+" daily="+DoubleToString(dp,2)+" dd="+DoubleToString(tp,2));
   if(g_tradeDir!=0)OrbProPublishCloseOnly(g_tradeDir,"risk_liquidate");
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;
      if(!MagicScoped((long)PositionGetInteger(POSITION_MAGIC)))continue;
      trade.PositionClose(t);
   }
}

//=========================================================================
//  CHART OBJECTS
//=========================================================================
#include "MaHistoricalVisualCache.mqh"
bool g_maInitialHistoryCleared=false;
void DeleteByPrefix(const string pfx){ObjectsDeleteAll(0,pfx,0,-1);}
void DeleteLevels(){ObjectDelete(0,PREFIX+"ORB_HIGH");ObjectDelete(0,PREFIX+"ORB_LOW");ObjectDelete(0,PREFIX+"ORB_TXT");}
string HistoricalGenerationRoot(int generation)
{
   if(generation<=0)return PREFIX+"HIST_";
   return PREFIX+"HIST_G"+IntegerToString(generation)+"_";
}
string HistoricalObjectRoot()
{
   if(g_maPlotRoot!="")return g_maPlotRoot;
   int generation=g_histBuildGeneration>0?g_histBuildGeneration:g_histActiveGeneration;
   return HistoricalGenerationRoot(generation);
}
bool IsFreshHistoricalBuildObject(const string name)
{
   if(g_maPlotRoot!=""&&StringFind(name,g_maPlotRoot)==0)return true;
   return g_histBuildGeneration>0
      &&StringFind(name,HistoricalGenerationRoot(g_histBuildGeneration))==0;
}
void BeginHistoricalSnapshot()
{
   if(g_histActiveGeneration==0)
   {
      DeleteByPrefix(PREFIX+"HIST_");MaVisualReset();g_maInitialHistoryCleared=true;
   }
   g_histBuildGeneration=(g_histActiveGeneration==1?2:1);
   DeleteByPrefix(HistoricalGenerationRoot(g_histBuildGeneration));
}
void CommitHistoricalSnapshot()
{
   if(g_histBuildGeneration<=0)return;
   if(g_histActiveGeneration==0&&g_maInitialHistoryCleared)
   {g_histActiveGeneration=g_histBuildGeneration;g_histBuildGeneration=0;return;}
   if(g_histActiveGeneration>0&&g_histActiveGeneration!=g_histBuildGeneration)
   {
      // Both snapshots have known prefixes after the first commit. Avoid
      // enumerating tens of thousands of old and new chart objects by index.
      DeleteByPrefix(HistoricalGenerationRoot(g_histActiveGeneration));
      g_histActiveGeneration=g_histBuildGeneration;
      g_histBuildGeneration=0;
      return;
   }
   string histRoot=PREFIX+"HIST_";
   string keepRoot=HistoricalGenerationRoot(g_histBuildGeneration);
   string obsolete[];int total=ObjectsTotal(0,0,-1),count=0;
   ArrayResize(obsolete,total);
   // ObjectName is synchronous: collect first, then enqueue all deletions.
   // Interleaving it with ObjectDelete drains the chart queue once per object.
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,histRoot)==0&&StringFind(name,keepRoot)!=0
         &&(g_maVisualPrefix==""||StringFind(name,g_maVisualPrefix)!=0))obsolete[count++]=name;
   }
   for(int i=0;i<count;i++)ObjectDelete(0,obsolete[i]);
   g_histActiveGeneration=g_histBuildGeneration;
   g_histBuildGeneration=0;
}
void DeleteHist()
{
   DeleteByPrefix(PREFIX+"HIST_");
   MaVisualReset();g_maInitialHistoryCleared=false;
   g_histActiveGeneration=0;
   g_histBuildGeneration=0;
}
void SetHistoricalAuditProgress(const string stage,const double startPct,const double spanPct,
                                const int completed,const int total)
{
   g_histAuditStage=stage;
   g_histAuditStageDone=MathMax(0,completed);
   g_histAuditStageTotal=MathMax(0,total);
   double fraction=total>0?(double)MathMax(0,MathMin(total,completed))/(double)total:0.0;
   g_histAuditProgressPct=MathMax(0.0,MathMin(100.0,startPct+spanPct*fraction));
}
void RenderHistoricalAuditProgress(const bool force=false)
{
   if(IsTesterMode()||!InpShowDashboard)return;
   ulong nowMs=GetTickCount64();
   // Repainting a chart containing thousands of history objects is expensive.
   // Two real updates per second keeps progress readable while making UI cost
   // independent of the number of simulated days/ticks.
   if(!force&&g_histAuditLastUiMs>0&&nowMs-g_histAuditLastUiMs<500)return;
   g_histAuditLastUiMs=nowMs;
   // Keep the asynchronous redraw on the exact same objects and coordinates
   // as UpdateDashboard().  The MA controls extend the header by 22px; the
   // old ORB coordinate made the live progress painter overwrite a different
   // bar and visually left the visible audit bar at its stale value.
   int x=InpDashboardX;
   int y=InpDashboardY+290;
   int barW=496,barH=14;
   bool historySync=(g_histCoveragePending&&!g_histCoverageHardBlocked);
   bool auditPending=(g_histAuditRunning||g_histRedrawQueued||historySync);
   // MT5 exposes no byte-level history-download progress.  Do not invent a
   // percentage while it is synchronizing; reserve a one-percent marker for
   // that distinct state and show real percentage only for audit work.
   double barPct=g_histAuditRunning?g_histAuditProgressPct:(historySync?1.0:0.0);
   color barClr=C'38,140,220';
   CreateRect("DASH_WRBAR_BG",x+12,y+238,barW,barH,C'42,51,68',C'134,158,182');
   int fillW=(int)MathRound((double)barW*MathMax(0.0,MathMin(100.0,barPct))/100.0);
   if(fillW>2)CreateRect("DASH_WRBAR_FILL",x+13,y+239,fillW-2,barH-2,barClr,barClr);
   else ObjectDelete(0,PREFIX+"DASH_WRBAR_FILL");
   string progressText="";
   if(g_histAuditRunning)
   {
      progressText="AUD "+g_histAuditStage;
      if(g_histAuditStageTotal>0)
         progressText+=" "+IntegerToString(g_histAuditStageDone)+"/"+IntegerToString(g_histAuditStageTotal);
      progressText+=" "+DoubleToString(g_histAuditProgressPct,1)+"%";
      ulong elapsedBase=g_histAuditRequestedMs>0?g_histAuditRequestedMs:g_histAuditStartedMs;
      if(elapsedBase>0)progressText+=" | "+DoubleToString((double)(nowMs-elapsedBase)/1000.0,1)+"s";
   }
   else if(g_histRedrawQueued)progressText="AUD QUEUED 0.0%";
   else if(g_histCoveragePending)
      progressText=g_histCoverageHardBlocked?"HIST BLOCK":("HISTORY SYNC (attempt "+IntegerToString(g_histCoverageAttempts)+")");
   if(!auditPending&&progressText=="")ObjectDelete(0,PREFIX+"DASH_AUD_PROGRESS");
   else CreateLabel("DASH_AUD_PROGRESS",x+12,y+256,progressText,
       g_histCoverageHardBlocked?C'255,80,110':C'90,178,255',7);
   ChartRedraw(0);
}
void DeleteLive(){DeleteByPrefix(PREFIX+"LIVE_");}
void DeleteExecutionVisuals(){DeleteByPrefix(PREFIX+"EXEC_");}
void DeleteDash(){DeleteByPrefix(PREFIX+"DASH_");DeleteByPrefix(PREFIX+"BTN_");DeleteByPrefix(PREFIX+"EDIT_");}
void MarkOrbExecutionVisualResolved(datetime executedAt,int dir,bool won);

void DrawOrbHistoricalSegment(string id,datetime t1,datetime t2,double price,color clr,ENUM_LINE_STYLE style=STYLE_SOLID)
{
   if(IsTesterMode()||!InpDrawTradeLevelSegments||price<=0.0||t2<=t1)return;
   string name=HistoricalObjectRoot()+"LVL_"+id;
   bool fresh=IsFreshHistoricalBuildObject(name);
   if(fresh)
      ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   else
   {
      if(ObjectFind(0,name)>=0&&(ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_TREND)
         ObjectDelete(0,name);
      if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
      ObjectMove(0,name,0,t1,price);
      ObjectMove(0,name,1,t2,price);
   }
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

datetime NextOrbOpenOwnPositionTimeAfter(datetime t,datetime maxEnd)
{
   datetime best=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      datetime openedAt=(datetime)PositionGetInteger(POSITION_TIME);
      if(openedAt<=t||openedAt>=maxEnd)continue;
      if(best==0||openedAt<best)best=openedAt;
   }
   return best;
}

void DrawOrbLiveSegment(string id,datetime t1,datetime t2,double price,color clr,ENUM_LINE_STYLE style=STYLE_SOLID,int width=4)
{
   if(IsTesterMode()||!InpDrawTradeLevelSegments||price<=0.0||t2<=t1)return;
   string name=PREFIX+"LIVE_LVL_"+id;
   if(ObjectFind(0,name)>=0&&(ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_TREND)
      ObjectDelete(0,name);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectMove(0,name,0,t1,price);
   ObjectMove(0,name,1,t2,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,DASH_Z+1);
}

string OrbLiveLevelTicketToken(string name)
{
   string kinds[]={"ENTRY_","SL_","TP_","HC_"};
   for(int i=0;i<ArraySize(kinds);i++)
   {
      string p=PREFIX+"LIVE_LVL_"+kinds[i];
      if(StringFind(name,p)==0)return StringSubstr(name,StringLen(p));
   }
   return "";
}

void DeleteStaleOrbLiveLevelObjects(string activeTicketKeys)
{
   string pfx=PREFIX+"LIVE_LVL_";
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,pfx)!=0)continue;
      string token=OrbLiveLevelTicketToken(name);
      if(token==""||StringFind(activeTicketKeys,"|"+token+"|")<0)
         ObjectDelete(0,name);
   }
}

string OrbBridgePlanKey(string field)
{
   return "OBP."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."+
      OrbProSafeToken(_Symbol)+"."+OrbProTf(g_rtSignalTf)+".C"+IntegerToString(g_orbBridgeChannel)+"."+field;
}

void StoreOrbBridgePlan(int dir,datetime signalTime,double entry,double sl,double tp,double halfTrigger)
{
   g_orbBridgePlanActive=true;
   g_orbBridgePlanDir=dir;
   g_orbBridgePlanTime=signalTime>0?signalTime:TimeCurrent();
   g_orbBridgePlanEntry=entry;
   g_orbBridgePlanSl=sl;
   g_orbBridgePlanTp=tp;
   g_orbBridgePlanHalf=halfTrigger;
   GlobalVariableSet(OrbBridgePlanKey("active"),1.0);
   GlobalVariableSet(OrbBridgePlanKey("dir"),(double)dir);
   GlobalVariableSet(OrbBridgePlanKey("time"),(double)g_orbBridgePlanTime);
   GlobalVariableSet(OrbBridgePlanKey("entry"),entry);
   GlobalVariableSet(OrbBridgePlanKey("sl"),sl);
   GlobalVariableSet(OrbBridgePlanKey("tp"),tp);
   GlobalVariableSet(OrbBridgePlanKey("half"),halfTrigger);
}

void ClearOrbBridgePlan()
{
   g_orbBridgePlanActive=false;
   g_orbBridgePlanDir=0;
   g_orbBridgePlanTime=0;
   g_orbBridgePlanEntry=0.0;
   g_orbBridgePlanSl=0.0;
   g_orbBridgePlanTp=0.0;
   g_orbBridgePlanHalf=0.0;
   string fields[]={"active","dir","time","entry","sl","tp","half"};
   for(int i=0;i<ArraySize(fields);i++)GlobalVariableDel(OrbBridgePlanKey(fields[i]));
}

void RestoreOrbBridgePlan()
{
   if(!GlobalVariableCheck(OrbBridgePlanKey("active")))return;
   datetime signalTime=(datetime)GlobalVariableGet(OrbBridgePlanKey("time"));
   MqlDateTime planDay;TimeToStruct(ServerToSessionLocal(signalTime),planDay);
   int y,m,d;int currentKey=CurrentSessionDayKey(y,m,d);
   int planKey=planDay.year*10000+planDay.mon*100+planDay.day;
   if(signalTime<=0||planKey!=currentKey){ClearOrbBridgePlan();return;}
   g_orbBridgePlanActive=true;
   g_orbBridgePlanDir=(int)GlobalVariableGet(OrbBridgePlanKey("dir"));
   g_orbBridgePlanTime=signalTime;
   g_orbBridgePlanEntry=GlobalVariableGet(OrbBridgePlanKey("entry"));
   g_orbBridgePlanSl=GlobalVariableGet(OrbBridgePlanKey("sl"));
   g_orbBridgePlanTp=GlobalVariableGet(OrbBridgePlanKey("tp"));
   g_orbBridgePlanHalf=GlobalVariableGet(OrbBridgePlanKey("half"));
   if(g_orbBridgePlanEntry<=0.0)ClearOrbBridgePlan();
}

bool FinalizeOrbBridgePlanVisualIfResolved()
{
   if(IsTesterMode()||!g_orbBridgePlanActive||g_orbBridgePlanEntry<=0.0||OwnPositionExists())return false;
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return false;
   double closePx=g_orbBridgePlanDir>0?tick.bid:tick.ask;
   bool tpHit=g_orbBridgePlanTp>0.0&&(g_orbBridgePlanDir>0?closePx>=g_orbBridgePlanTp:closePx<=g_orbBridgePlanTp);
   bool slHit=g_orbBridgePlanSl>0.0&&(g_orbBridgePlanDir>0?closePx<=g_orbBridgePlanSl:closePx>=g_orbBridgePlanSl);
   if(!tpHit&&!slHit)return false;
   MarkOrbExecutionVisualResolved(g_orbBridgePlanTime,g_orbBridgePlanDir,tpHit);
   DeleteLive();
   ClearOrbBridgePlan();
   g_lastHistBuild=0;
   g_histNeedsRedraw=true;
   DrawHistoricalSignals();
   ChartRedraw(0);
   return true;
}

void DrawOrbLiveTradeLevels()
{
   if(IsTesterMode())return;
   FinalizeOrbBridgePlanVisualIfResolved();
   static bool independentLevelsReady=false;
   if(g_maIndependent)
   {
      if(!independentLevelsReady){DeleteByPrefix(PREFIX+"LIVE_LVL_");DeleteExecutionVisuals();independentLevelsReady=true;}
      LabNativeVisualRefreshOpen();
      return;
   }
   independentLevelsReady=false;
   // Keep one fixed ENTRY/SL/TP set; HC and ORB-range lines are intentionally hidden.
   DeleteByPrefix(PREFIX+"LIVE_LVL_HC_");
   if(!InpDrawTradeLevelSegments)
   {
      DeleteByPrefix(PREFIX+"LIVE_LVL_");
      return;
   }

   ulong newestTicket=0;
   datetime newestTime=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      datetime openedAt=(datetime)PositionGetInteger(POSITION_TIME);
      if(openedAt>=newestTime){newestTime=openedAt;newestTicket=ticket;}
   }

   string activeTicketKeys="|";
   if(newestTicket>0&&PositionSelectByTicket(newestTicket))
   {
      string token=StringFormat("%I64u",newestTicket);
      activeTicketKeys+=token+"|";
      ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(positionId==0)positionId=newestTicket;
      datetime openedAt=(datetime)PositionGetInteger(POSITION_TIME);
      double entry=OrbProGet(positionId,"entry",PositionGetDouble(POSITION_PRICE_OPEN));
      double sl=PositionGetDouble(POSITION_SL);
      if(sl<=0.0)sl=OrbProGet(positionId,"sl",0.0);
      double tp=PositionGetDouble(POSITION_TP);
      if(tp<=0.0)tp=OrbProGet(positionId,"tp",0.0);
      int segSec=MathMax(60,PeriodSeconds(RuntimeEntryTf()))*20;
      datetime liveEnd=openedAt+segSec;

      DrawOrbLiveSegment("ENTRY_"+token,openedAt,liveEnd,entry,C'245,245,255',STYLE_SOLID,4);
      if(sl>0.0)DrawOrbLiveSegment("SL_"+token,openedAt,liveEnd,sl,C'255,40,70',STYLE_SOLID,4);
      else ObjectDelete(0,PREFIX+"LIVE_LVL_SL_"+token);
      if(tp>0.0)DrawOrbLiveSegment("TP_"+token,openedAt,liveEnd,tp,C'20,255,160',STYLE_SOLID,4);
      else ObjectDelete(0,PREFIX+"LIVE_LVL_TP_"+token);
   }
   else if(g_orbBridgePlanActive&&g_orbBridgePlanEntry>0.0)
   {
      string token="BRIDGE_PLAN";
      activeTicketKeys+=token+"|";
      datetime openedAt=g_orbBridgePlanTime>0?g_orbBridgePlanTime:TimeCurrent();
      int segSec=MathMax(60,PeriodSeconds(RuntimeEntryTf()))*20;
      datetime liveEnd=openedAt+segSec;
      DrawOrbLiveSegment("ENTRY_"+token,openedAt,liveEnd,g_orbBridgePlanEntry,C'245,245,255',STYLE_SOLID,4);
      if(g_orbBridgePlanSl>0.0)DrawOrbLiveSegment("SL_"+token,openedAt,liveEnd,g_orbBridgePlanSl,C'255,40,70',STYLE_SOLID,4);
      else ObjectDelete(0,PREFIX+"LIVE_LVL_SL_"+token);
      if(g_orbBridgePlanTp>0.0)DrawOrbLiveSegment("TP_"+token,openedAt,liveEnd,g_orbBridgePlanTp,C'20,255,160',STYLE_SOLID,4);
      else ObjectDelete(0,PREFIX+"LIVE_LVL_TP_"+token);
   }
   DeleteStaleOrbLiveLevelObjects(activeTicketKeys);
}

void ClearRetestState(string reason="")
{
   if(g_retestPending && reason!="")
      Audit("retest_clear",g_retestDir,0,g_retestBreakoutClose,0,0,reason+" signal="+FmtTime(g_retestSignalBar));
   g_retestPending=false;
   g_retestTouched=false;
   g_retestDir="";
   g_retestSignalBar=0;
   g_retestExpire=0;
   g_retestLevel=0.0;
   g_retestBreakoutClose=0.0;
   g_retestContext="";
}

void ClearImbalanceState(string reason="")
{
   if(g_imbPending && reason!="")
      Audit("imbalance_clear",g_imbDir,0,g_imbBreakoutClose,0,0,reason+" signal="+FmtTime(g_imbSignalBar)+" start="+FmtTime(g_imbStart));
   g_imbPending=false;
   g_imbDir="";
   g_imbSignalBar=0;
   g_imbStart=0;
   g_imbExpire=0;
   g_imbBreakoutClose=0.0;
   g_imbContext="";
}

double g_libraryDashScale=1.0;
int g_libraryDashX=0,g_libraryDashY=0;

void OrbLibraryRefreshLayout()
{
   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(chartW<=0||chartH<=0)return;
   // Scale the two-column canvas once per dashboard refresh, never per object.
   g_libraryDashX=MathMax(0,MathMin(InpDashboardX,chartW/10));
   g_libraryDashY=MathMax(0,MathMin(InpDashboardY,chartH/10));
   g_libraryDashScale=MathMin(1.0,MathMin(
      (double)MathMax(1,chartW-g_libraryDashX-8)/1252.0,
      (double)MathMax(1,chartH-g_libraryDashY-8)/758.0));
}
int OrbLibraryX(int x){return g_libraryDashX+(int)MathRound((x-InpDashboardX)*g_libraryDashScale);}
int OrbLibraryY(int y){return g_libraryDashY+(int)MathRound((y-InpDashboardY)*g_libraryDashScale);}
int OrbLibrarySize(int value){return MathMax(1,(int)MathRound(value*g_libraryDashScale));}

bool OrbStrategyPopupContains(const long px,const double py)
{
   if(!g_strategyPopupOpen)return false;
   int left=OrbLibraryX(InpDashboardX+644),top=OrbLibraryY(InpDashboardY+142);
   return px>=left&&px<left+OrbLibrarySize(594)
      &&py>=top&&py<top+OrbLibrarySize(28+g_strategyVisibleCount*22);
}

bool OrbStrategyIsPopupControl(const string name)
{
   if(name==PREFIX+"BTN_PRESET_PREV"||name==PREFIX+"BTN_PRESET_NEXT"
      ||name==PREFIX+"BTN_PRESET_CLOSE")return true;
   for(int i=0;i<5;i++)
      if(name==PREFIX+"BTN_PRESET_RESULT_"+IntegerToString(i)
         ||name==PREFIX+"BTN_PRESET_STAR_"+IntegerToString(i))return true;
   return false;
}

void CreateRect(const string name,int x,int y,int w,int h,color bg,color brd)
{
   x=OrbLibraryX(x);y=OrbLibraryY(y);w=OrbLibrarySize(w);h=OrbLibrarySize(h);
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,MathMax(1,w));ObjectSetInteger(0,obj,OBJPROP_YSIZE,MathMax(1,h));
   ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,obj,OBJPROP_BORDER_COLOR,brd);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,obj,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,obj,OBJPROP_ZORDER,DASH_Z);
}
void CreateLabel(const string name,int x,int y,string text,color clr,int sz=9)
{
   x=OrbLibraryX(x);y=OrbLibraryY(y);sz=OrbLibrarySize(sz);
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);ObjectSetInteger(0,obj,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,sz);ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,obj,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);ObjectSetInteger(0,obj,OBJPROP_ZORDER,DASH_Z+1);
}
void CreateButton(const string name,int x,int y,int w,int h,string text,color bg)
{
   x=OrbLibraryX(x);y=OrbLibraryY(y);w=OrbLibrarySize(w);h=OrbLibrarySize(h);
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,OrbLibrarySize(8));
   ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,obj,OBJPROP_STATE,false);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);ObjectSetInteger(0,obj,OBJPROP_ZORDER,DASH_Z+2);
}
void CreateEdit(const string name,int x,int y,int w,int h,string text)
{
   x=OrbLibraryX(x);y=OrbLibraryY(y);w=OrbLibrarySize(w);h=OrbLibrarySize(h);
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)
   {
      ObjectCreate(0,obj,OBJ_EDIT,0,0,0);
      ObjectSetString(0,obj,OBJPROP_TEXT,text);
      ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,C'38,46,60');
      ObjectSetInteger(0,obj,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,obj,OBJPROP_BORDER_COLOR,C'80,100,130');
      ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,8);
      ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,obj,OBJPROP_ALIGN,ALIGN_CENTER);
      ObjectSetInteger(0,obj,OBJPROP_READONLY,false);
      ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,obj,OBJPROP_BACK,false);
      ObjectSetInteger(0,obj,OBJPROP_ZORDER,DASH_Z+3);
   }
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,obj,OBJPROP_ZORDER,DASH_Z+3);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,OrbLibrarySize(8));
}

//=========================================================================
//  SIGNAL ARROWS
//=========================================================================
void DrawSignalArrow(const string name,datetime t,double price,bool buy,bool hist)
{
   if(IsTesterMode()) return;
   if(IsFreshHistoricalBuildObject(name))ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   else if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   else ObjectMove(0,name,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,buy?233:234);
   ObjectSetInteger(0,name,OBJPROP_COLOR,buy?clrLime:clrTomato);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,hist?2:3);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}
void DrawSignalText(const string name,datetime t,double price,string text,color clr)
{
   if(IsTesterMode()) return;
   if(IsFreshHistoricalBuildObject(name))ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   else if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   else ObjectMove(0,name,0,t,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}

bool NasOverlayEnabled(){return !IsTesterMode()&&(g_rtNasConfirmation||g_rtNasStateGate||RuntimeNasExitEnabled());}

string NasVisualPolicyLabel(const ORB_NAS_VISUAL_POLICY policy)
{
   if(policy==ORB_NAS_VIS_STATE)return "STATE";
   if(policy==ORB_NAS_VIS_FLOW)return "FLOW";
   if(policy==ORB_NAS_VIS_BOTH)return "BOTH S+F";
   return "NONE";
}
color NasVisualPolicyColor(const ORB_NAS_VISUAL_POLICY policy)
{
   if(policy==ORB_NAS_VIS_STATE)return C'35,170,255';
   if(policy==ORB_NAS_VIS_FLOW)return C'255,158,46';
   if(policy==ORB_NAS_VIS_BOTH)return C'210,100,255';
   return C'145,160,180';
}
void DrawNasSignalMarker(const MqlRates &bar,const NasPoint &point,ENUM_TIMEFRAMES tf,
                         const ORB_NAS_VISUAL_POLICY policy)
{
   bool buy=point.buy&&!point.sell;
   bool sell=point.sell&&!point.buy;
   if((!buy&&!sell)||policy==ORB_NAS_VIS_NONE)return;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double pad=MathMax(MathMax(pt,bar.high-bar.low)*0.22,pt*24.0);
   double arrowPrice=NormalizePrice(buy?bar.low-pad:bar.high+pad);
   string dir=buy?"BUY":"SELL";
   string token=StringFormat("%I64d",(long)bar.time)+"_"+TfLabel(tf)+"_"+dir;
   string base=HistoricalObjectRoot()+"NAS_"+token+"_";
   color clr=NasVisualPolicyColor(policy);
   string arrowName=base+"ARW";
   if(IsFreshHistoricalBuildObject(arrowName))ObjectCreate(0,arrowName,OBJ_ARROW,0,bar.time,arrowPrice);
   else if(ObjectFind(0,arrowName)<0)ObjectCreate(0,arrowName,OBJ_ARROW,0,bar.time,arrowPrice);
   else ObjectMove(0,arrowName,0,bar.time,arrowPrice);
   ObjectSetInteger(0,arrowName,OBJPROP_ARROWCODE,buy?241:242);
   ObjectSetInteger(0,arrowName,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,policy==ORB_NAS_VIS_BOTH?3:2);
   ObjectSetInteger(0,arrowName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,arrowName,OBJPROP_HIDDEN,false);
   double textPrice=NormalizePrice(buy?arrowPrice-pad*0.55:arrowPrice+pad*0.55);
   DrawSignalText(base+"TXT",bar.time,textPrice,"WINDOW NAS "+dir+" ["+NasVisualPolicyLabel(policy)
      +" | "+TfLabel(tf)+" S"+IntegerToString(g_rtNasSensitivity)+"]",clr);
}

int DrawNasSignalOverlay(int days,datetime now)
{
   g_lastNasOverlaySignalCount=0;g_lastNasOverlayCopiedBars=0;
   if(!NasOverlayEnabled())return 0;
   if(g_histNasCacheActive)
   {
      datetime cutoff=now-(datetime)((long)MathMax(1,days)*86400);
      ENUM_TIMEFRAMES tf=NasConfirmationTf();int drawn=0;
      for(int i=0;i<ArraySize(g_histNasEvents);i++)
      {
         ORB_NAS_VISUAL_POLICY visual=HistoricalNasVisualPolicy(i);
         if(visual==ORB_NAS_VIS_NONE)continue;
         if(g_histNasEvents[i].availableTime<cutoff||g_histNasEvents[i].availableTime>now)continue;
         MqlRates bar;ZeroMemory(bar);
         bar.time=g_histNasEvents[i].barTime;bar.close=g_histNasEvents[i].closePrice;
         bar.high=g_histNasEvents[i].highPrice;bar.low=g_histNasEvents[i].lowPrice;
         NasPoint point;ZeroMemory(point);
         point.buy=(g_histNasEvents[i].dir=="BUY");point.sell=(g_histNasEvents[i].dir=="SELL");
         DrawNasSignalMarker(bar,point,tf,visual);drawn++;
      }
      g_lastNasOverlaySignalCount=drawn;g_lastNasOverlayCopiedBars=g_histNasCacheCopiedBars;
      g_lastNasOverlayClosedBar=iTime(_Symbol,tf,1);
      return drawn;
   }
   ENUM_TIMEFRAMES tf=NasConfirmationTf();int sec=PeriodSeconds(tf);if(sec<=0)sec=60;
   long requestedWindow=(long)MathCeil((double)MathMax(1,days)*86400.0/(double)sec);
   int neededBars=(int)MathMin((long)2147480000,requestedWindow+300);
   int requested=MathMax(NasHistoryBars(),neededBars);
   MqlRates rates[];int copied=LoadOrbNasRates(rates,tf,requested);
   if(copied<20)return 0;
   g_lastNasOverlayCopiedBars=copied;
   NasPoint points[];if(NAS_Calculate(rates,copied,BuildOrbNasSettings(),points)!=copied)return 0;
   datetime cutoff=now-(datetime)((long)MathMax(1,days)*86400);
   int drawn=0;
   for(int i=0;i<=copied-2;i++)
   {
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(rates[i].time<cutoff||available<=0||available>now)continue;
      if(points[i].buy==points[i].sell)continue;
      double signalVolume=0.0,averageVolume=0.0;
      ORB_NAS_VISUAL_POLICY visual=OrbNasVisualPolicy(rates,i,signalVolume,averageVolume);
      if(visual==ORB_NAS_VIS_NONE)continue;
      DrawNasSignalMarker(rates[i],points[i],tf,visual);drawn++;
   }
   g_lastNasOverlaySignalCount=drawn;
   g_lastNasOverlayClosedBar=iTime(_Symbol,tf,1);
   return drawn;
}

bool DrawCachedNasSignalOverlayEvent(const int index,const int days,const datetime now)
{
   if(!NasOverlayEnabled()||!g_histNasCacheActive)return false;
   if(index<0||index>=ArraySize(g_histNasEvents))return false;
   ORB_NAS_VISUAL_POLICY visual=HistoricalNasVisualPolicy(index);
   if(visual==ORB_NAS_VIS_NONE)return false;
   datetime cutoff=now-(datetime)((long)MathMax(1,days)*86400);
   if(g_histNasEvents[index].availableTime<cutoff||g_histNasEvents[index].availableTime>now)return false;
   MqlRates bar;ZeroMemory(bar);
   bar.time=g_histNasEvents[index].barTime;
   bar.close=g_histNasEvents[index].closePrice;
   bar.high=g_histNasEvents[index].highPrice;
   bar.low=g_histNasEvents[index].lowPrice;
   NasPoint point;ZeroMemory(point);
   point.buy=(g_histNasEvents[index].dir=="BUY");
   point.sell=(g_histNasEvents[index].dir=="SELL");
   DrawNasSignalMarker(bar,point,NasConfirmationTf(),visual);
   return true;
}

void RefreshNasSignalOverlay()
{
   if(!NasOverlayEnabled())return;
   ENUM_TIMEFRAMES tf=NasConfirmationTf();datetime closedBar=iTime(_Symbol,tf,1);
   if(closedBar<=0||closedBar==g_lastNasOverlayClosedBar)return;
   int requested=NasCalcWarmupBars();
   MqlRates rates[];int copied=LoadOrbNasRates(rates,tf,requested);
   if(copied<20)return;
   NasPoint points[];if(NAS_Calculate(rates,copied,BuildOrbNasSettings(),points)!=copied)return;
   datetime from=g_lastNasOverlayClosedBar>0?g_lastNasOverlayClosedBar:rates[MathMax(1,copied-10)].time;
   datetime now=TimeCurrent();
   for(int i=1;i<=copied-2;i++)
   {
      datetime available=OrbNasSignalAvailableTime(rates,copied,i);
      if(rates[i].time<from||available<=0||available>now)continue;
      if(points[i].buy==points[i].sell)continue;
      double signalVolume=0.0,averageVolume=0.0;
      ORB_NAS_VISUAL_POLICY visual=OrbNasVisualPolicy(rates,i,signalVolume,averageVolume);
      if(visual==ORB_NAS_VIS_NONE)continue;
      DrawNasSignalMarker(rates[i],points[i],tf,visual);
   }
   g_lastNasOverlayClosedBar=closedBar;
}

//=========================================================================
//  ORB LEVEL LINES
//=========================================================================
void DrawLevels()
{
   if(IsTesterMode()) return;
   // ORB range boundaries are execution internals, not trade levels.
   DeleteLevels();
}

//=========================================================================
//  ORB BUILDING — uses g_rtSignalTf (runtime TF)
//=========================================================================
bool BuildOrbForNyDate(int y,int m,int d,double &hi,double &lo,datetime &os,datetime &oe,datetime &te,int &used,double &avgV)
{
   int sm,em,tem;SessionClockMinutes(sm,em,tem);
   os=SessionLocalToServer(y,m,d,sm);oe=SessionLocalToServer(y,m,d,em);te=SessionLocalToServer(y,m,d,tem);
   hi=-DBL_MAX;lo=DBL_MAX;used=0;avgV=0;
   // Always build ORB from M1 data for precision (regardless of signal TF)
   MqlRates r[];int c=CopyRates(_Symbol,PERIOD_M1,os,oe,r);if(c<=0)return false;
   double tv=0;
   for(int i=0;i<c;i++){if(r[i].time<os||r[i].time>=oe)continue;hi=MathMax(hi,r[i].high);lo=MathMin(lo,r[i].low);tv+=(double)r[i].tick_volume;used++;}
   if(used<=0||hi<=lo||hi==-DBL_MAX||lo==DBL_MAX)return false;
   hi=NormalizePrice(hi);lo=NormalizePrice(lo);avgV=tv/(double)used;return true;
}
bool BuildOrb(){return true;} // MA kernels do not wait for an opening range.
void ConfigureMaSignalContext(datetime when,double high,double low,double priorVolume=0)
{
   g_orbHigh=high;g_orbLow=low;g_orbAvgVolume=priorVolume;g_orbReady=high>low;
   g_orbStartServer=when;g_orbEndServer=when;g_tradeEndServer=when+86400;
}
//=========================================================================
//  HISTORICAL ATR COMPUTATION (manual from D1 bars)
//=========================================================================
double HistDailyAtr(datetime beforeDate,int period)
{
   MqlRates d1[];ArraySetAsSeries(d1,true);
   int c=CopyRates(_Symbol,PERIOD_D1,beforeDate,period+2,d1);
   if(c<3)return 0;
   int n=MathMin(period,c-1);double s=0;
   for(int i=1;i<=n&&i+1<c;i++){double tr=d1[i].high-d1[i].low;tr=MathMax(tr,MathAbs(d1[i].high-d1[i+1].close));tr=MathMax(tr,MathAbs(d1[i].low-d1[i+1].close));s+=tr;}
   return n>0?s/(double)n:0;
}

//=========================================================================
//  HISTORICAL BREAKOUT FINDER — uses g_rtSignalTf, respects delay
//  Returns pre-breakout rolling avg volume for fair volume comparison
//=========================================================================
bool FindHistBreakoutAfterRates(const MqlRates &r[],int c,datetime from,datetime to,double hi,double lo,
                                datetime afterSignalTime,int &scanFromIndex,
                                string &dir,datetime &sigT,double &sigC,double &sigH,double &sigL,
                                double &sigVol,double &preBreakoutAvgVol)
{
   dir="";sigT=0;sigC=0;sigH=0;sigL=0;sigVol=0;preBreakoutAvgVol=0;
   // MA modes use the immutable, closed-bar cache. Its candidate timestamps
   // are the same timestamps used by the live kernel; ORB range arguments are
   // deliberately ignored only at signal-discovery time.
   datetime maFrom=from;
   if(g_rtUseDelay&&g_rtDelayMin>0)maFrom+=g_rtDelayMin*60;
   if(g_maCrossAuditReady)
   {
      // A MA event outside the optional entry window is not a terminal
      // condition. Continue through the immutable stream until a usable
      // event is found, exactly as the live closed-bar loop does.
      datetime searchAfter=afterSignalTime;
      datetime candidate=0;
      while(MaCrossAuditNext(maFrom,to,searchAfter,dir,candidate,sigC,sigH,sigL,sigVol,preBreakoutAvgVol))
      {
         searchAfter=candidate;
         if(!EntryWindowAllowsAt(BarCloseTime(g_rtSignalTf,candidate)))continue;
         sigT=candidate;scanFromIndex=MathMax(0,scanFromIndex+1);return true;
      }
      scanFromIndex=MathMax(0,c);return false;
   }
   // Missing MA data must never fall back to an unrelated ORB breakout.
   return false;
}

bool FindHistBreakoutAfter(datetime from,datetime to,double hi,double lo,datetime afterSignalTime,
                           string &dir,datetime &sigT,double &sigC,double &sigH,double &sigL,
                           double &sigVol,double &preBreakoutAvgVol)
{
   MqlRates r[];int c=CopyRates(_Symbol,g_rtSignalTf,from,to,r);
   int scanFromIndex=0;
   return FindHistBreakoutAfterRates(r,c,from,to,hi,lo,afterSignalTime,scanFromIndex,
      dir,sigT,sigC,sigH,sigL,sigVol,preBreakoutAvgVol);
}

string OrbExecutionVisualBase(datetime executedAt,int dir)
{
   return PREFIX+"EXEC_"+StringFormat("%I64d",(long)executedAt)+"_"+(dir>0?"BUY_":"SELL_");
}

// Keep signal markers adjacent to their generating candle, never to SL distance.
double MaCrossCandleArrowPrice(bool isBuy,double high,double low)
{
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)point=0.00001;
   double pad=MathMax((high-low)*0.20,point*4.0);
   return NormalizePrice(isBuy?low-pad:high+pad);
}

double MaCrossChartArrowPrice(datetime signalBar,bool isBuy,double fallback,double risk)
{
   int shift=iBarShift(_Symbol,g_rtSignalTf,signalBar,true);
   if(shift>=0)
   {
      double hi=iHigh(_Symbol,g_rtSignalTf,shift),lo=iLow(_Symbol,g_rtSignalTf,shift);
      if(hi>=lo&&lo>0.0)return MaCrossCandleArrowPrice(isBuy,hi,lo);
   }
   int i=MaCrossAuditFirstAfter(signalBar-1);
   if(g_maCrossAuditReady&&i<ArraySize(g_maCrossAuditEvents)
      &&g_maCrossAuditEvents[i].signalTime==signalBar)
      return MaCrossCandleArrowPrice(isBuy,g_maCrossAuditEvents[i].high,g_maCrossAuditEvents[i].low);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)point=0.00001;
   return NormalizePrice(fallback+(isBuy?-1.0:1.0)*point*4.0);
}

// A trade marker belongs to its fill candle on the displayed chart. Source
// signal candles can be a different timeframe and remain in the tooltip.
void MaCrossTradeMarker(datetime fillTime,bool isBuy,double fillPrice,
                       datetime &chartBar,double &arrowPrice,double &pad)
{
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)point=0.00001;
   chartBar=fillTime;pad=point*4.0;
   arrowPrice=NormalizePrice(fillPrice+(isBuy?-pad:pad));
   MqlRates bar[1];
   ENUM_TIMEFRAMES chartTf=(ENUM_TIMEFRAMES)_Period;
   int seconds=PeriodSeconds(chartTf);
   if(fillTime>0&&CopyRates(_Symbol,chartTf,fillTime,1,bar)==1
      &&bar[0].time<=fillTime&&seconds>0&&fillTime<bar[0].time+seconds
      &&bar[0].low>0.0&&bar[0].high>=bar[0].low)
   {
      chartBar=bar[0].time;
      pad=MathMax((bar[0].high-bar[0].low)*0.20,point*4.0);
      arrowPrice=MaCrossCandleArrowPrice(isBuy,bar[0].high,bar[0].low);
   }
}

string MaCrossTradeMarkerTooltip(datetime signalBar,datetime fillTime)
{
   return "Signal "+EnumToString(g_rtSignalTf)+" bar: "+FmtTime(signalBar)
      +" | closed: "+FmtTime(BarCloseTime(g_rtSignalTf,signalBar))
      +" | fill: "+(fillTime>0?FmtTime(fillTime):"unavailable")
      +" | marker candle: "+EnumToString((ENUM_TIMEFRAMES)_Period);
}

void DrawOrbExecutionVisual(string execDir,datetime executedAt,datetime signalBar,double entry,double sl,string entryDetail)
{
   if(IsTesterMode()||executedAt<=0||entry<=0.0||sl<=0.0)return;
   bool isBuy=(execDir=="BUY");
   int dir=isBuy?1:-1;
   datetime visualAt=0;double arrowPrice=0.0,pad=0.0;
   MaCrossTradeMarker(executedAt,isBuy,entry,visualAt,arrowPrice,pad);
   double textPrice=NormalizePrice(isBuy?arrowPrice-pad*0.65:arrowPrice+pad*0.65);
   string base=OrbExecutionVisualBase(executedAt,dir);
   DrawSignalArrow(base+"ARW",visualAt,arrowPrice,isBuy,false);
   ObjectSetInteger(0,base+"ARW",OBJPROP_WIDTH,4);
   ObjectSetInteger(0,base+"ARW",OBJPROP_ANCHOR,isBuy?ANCHOR_TOP:ANCHOR_BOTTOM);
   ObjectSetString(0,base+"ARW",OBJPROP_TOOLTIP,MaCrossTradeMarkerTooltip(signalBar,executedAt));
   string mode=(StringFind(entryDetail,"entry=imb1m")>=0)?"IMB1M":
      ((StringFind(entryDetail,"entry=retest")>=0)?"RETEST":"BREAK");
   DrawSignalText(base+"TXT",visualAt,textPrice,
      "EXECUTED "+MaCrossSignalText(g_rtMaCrossMode,dir)+" ["+mode+"] C"+IntegerToString(g_orbBridgeChannel),C'255,215,70');
}

void MarkOrbExecutionVisualResolved(datetime executedAt,int dir,bool won)
{
   if(IsTesterMode()||executedAt<=0||dir==0)return;
   string base=OrbExecutionVisualBase(executedAt,dir);
   color resultColor=won?clrLime:clrTomato;
   if(ObjectFind(0,base+"ARW")>=0)ObjectSetInteger(0,base+"ARW",OBJPROP_COLOR,resultColor);
   if(ObjectFind(0,base+"TXT")>=0)
   {
      string text=ObjectGetString(0,base+"TXT",OBJPROP_TEXT);
      if(StringFind(text," [TP]")<0&&StringFind(text," [SL]")<0)
         ObjectSetString(0,base+"TXT",OBJPROP_TEXT,text+(won?" [TP]":" [SL]"));
      ObjectSetInteger(0,base+"TXT",OBJPROP_COLOR,resultColor);
   }
}

#include "LabNativeTradeVisuals.mqh"

bool FindHistBreakout(datetime from,datetime to,double hi,double lo,
                      string &dir,datetime &sigT,double &sigC,double &sigH,double &sigL,
                      double &sigVol,double &preBreakoutAvgVol)
{
   return FindHistBreakoutAfter(from,to,hi,lo,0,dir,sigT,sigC,sigH,sigL,sigVol,preBreakoutAvgVol);
}

bool HasM1Displacement(const MqlRates &rates[],int idx,string dir)
{
   if(idx<0||idx>=ArraySize(rates))return false;
   int from=MathMax(0,idx-20);
   double avg=0.0;int n=0;
   for(int i=from;i<idx;i++)
   {
      double b=MathAbs(rates[i].close-rates[i].open);
      if(b<=0.0)continue;
      avg+=b;n++;
   }
   if(n<=0)return false;
   avg/=n;
   double body=(dir=="BUY")?(rates[idx].close-rates[idx].open):(rates[idx].open-rates[idx].close);
   if(body<=0.0)return false;
   return body>=avg*1.20;
}

bool IsM1ImbalanceAt(const MqlRates &rates[],int idx,string dir,double hi,double lo,
                     double &top,double &bottom,double &gap,string &reason)
{
   top=0.0;bottom=0.0;gap=0.0;reason="";
   if(idx<2||idx>=ArraySize(rates)){reason="imb_bad_idx";return false;}
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double minGap=MathMax(0.0,InpM1ImbalanceMinGapPoints)*pt;
   if(InpM1ImbalanceRequireDisplacement && !HasM1Displacement(rates,idx-1,dir))
   {
      reason="imb_no_displacement";
      return false;
   }
   if(InpM1ImbalanceRequireCloseOutsideRange)
   {
      if(dir=="BUY" && rates[idx].close<=hi){reason="imb_close_not_above_orh";return false;}
      if(dir=="SELL" && rates[idx].close>=lo){reason="imb_close_not_below_orl";return false;}
   }
   if(dir=="BUY")
   {
      gap=rates[idx].low-rates[idx-2].high;
      if(gap<=minGap){reason="imb_gap_too_small";return false;}
      top=rates[idx].low;bottom=rates[idx-2].high;
      return true;
   }
   gap=rates[idx-2].low-rates[idx].high;
   if(gap<=minGap){reason="imb_gap_too_small";return false;}
   top=rates[idx-2].low;bottom=rates[idx].high;
   return true;
}

bool FindM1ImbalanceEntry(string dir,datetime start,datetime tradeEnd,double hi,double lo,
                          datetime &entryT,double &entryPrice,string &detail)
{
   entryT=0;entryPrice=0.0;detail="";
   datetime limit=tradeEnd;
   if(InpM1ImbalanceMaxWaitMinutes>0)
      limit=MathMin(limit,start+InpM1ImbalanceMaxWaitMinutes*60);
   if(limit<=start){detail="IMB1M_NO_WINDOW start="+FmtTime(start);return false;}
   MqlRates r[];
   int c=CopyRates(_Symbol,PERIOD_M1,start,limit,r);
   if(c<3){detail="IMB1M_NO_DATA start="+FmtTime(start)+" limit="+FmtTime(limit)+" bars="+IntegerToString(c);return false;}
   for(int i=2;i<c;i++)
   {
      datetime closeTime=BarCloseTime(PERIOD_M1,r[i].time);
      if(closeTime<start||closeTime>limit)continue;
      double top,bottom,gap;string reason="";
      if(!IsM1ImbalanceAt(r,i,dir,hi,lo,top,bottom,gap,reason))continue;
      entryT=r[i].time;
      entryPrice=r[i].close;
      detail="IMB1M_OK start="+FmtTime(start)+" entry="+FmtTime(entryT)
         +" top="+DoubleToString(top,_Digits)+" bottom="+DoubleToString(bottom,_Digits)
         +" gap="+DoubleToString(gap,_Digits);
      return true;
   }
   detail="IMB1M_MISSED start="+FmtTime(start)+" until="+FmtTime(limit);
   return false;
}

bool ResolveHistoricalEntry(ORB_ENTRY_MODE mode,string dir,datetime breakoutT,double breakoutClose,
                            double hi,double lo,datetime tradeEnd,
                            datetime &entryT,double &entryPrice,string &detail)
{
   entryT=breakoutT;
   entryPrice=breakoutClose;
   detail=EntryModeLabel(mode);
   datetime gateAvailable=OrbSignalAvailableTime(breakoutT);
   if(g_rtNasStateGate)
   {
      datetime nasBar=0,nasAt=0;double nasClose=0.0;string nasDetail="";
      if(!FindNasStateGate(dir,gateAvailable,nasBar,nasAt,nasClose,nasDetail))
      {
         detail="NAS_STATE_REJECTED "+nasDetail;
         return false;
      }
      detail+=" "+nasDetail;
   }
   else if(g_rtNasConfirmation)
   {
      datetime nasBar=0,nasAt=0;double nasClose=0.0;bool nasWasActive=false;string nasDetail="";
      if(!FindNasConfirmation(dir,gateAvailable,tradeEnd,nasBar,nasAt,nasClose,nasWasActive,nasDetail))
      {
         detail="NAS_CONFIRM_MISSED "+nasDetail;
         return false;
      }
      // A still-active pre-ORB NAS direction confirms the original ORB fill;
      // only a genuinely later NAS transition delays and reprices the entry.
      if(!nasWasActive){entryT=nasBar;entryPrice=nasClose;}
      gateAvailable=nasAt;
      detail+=" "+nasDetail;
   }
   if(mode==ORB_ENTRY_BREAKOUT)
   {
      if(g_rtNasConfirmation)
      {
         int entrySec=PeriodSeconds(RuntimeEntryTf());if(entrySec<=0)entrySec=60;
         entryT=gateAvailable-entrySec; // Simulator fill becomes the NAS bar close.
      }
      return true;
   }
   if(mode==ORB_ENTRY_IMBALANCE_M1)
      return FindM1ImbalanceEntry(dir,gateAvailable,tradeEnd,hi,lo,entryT,entryPrice,detail);

   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double tol=MathMax(0.0,InpRetestTolerancePoints)*pt;
   double resume=MathMax(0.0,InpRetestResumePoints)*pt;
   double level=(dir=="BUY")?hi:lo;
   datetime start=gateAvailable;
   datetime limit=tradeEnd;
   if(InpRetestMaxWaitMinutes>0)
      limit=MathMin(limit,start+InpRetestMaxWaitMinutes*60);
   if(limit<=start)
   {
      detail="RETEST_NO_WINDOW level="+DoubleToString(level,_Digits);
      return false;
   }

   MqlRates r[];
   int c=CopyRates(_Symbol,g_rtSignalTf,start,limit,r);
   if(c<=0)
   {
      detail="RETEST_NO_DATA level="+DoubleToString(level,_Digits);
      return false;
   }

   bool touched=false;
   for(int i=0;i<c;i++)
   {
      if(r[i].time<start||r[i].time>limit)continue;
      if(!touched)
      {
         touched=(dir=="BUY")?(r[i].low<=level+tol):(r[i].high>=level-tol);
         if(!touched)continue;
      }
      bool resumed=(dir=="BUY")?(r[i].close>=level+resume):(r[i].close<=level-resume);
      if(resumed)
      {
         entryT=r[i].time;
         entryPrice=r[i].close;
         detail="RETEST_OK level="+DoubleToString(level,_Digits)+" breakout="+FmtTime(breakoutT)+" entry="+FmtTime(entryT);
         return true;
      }
   }

   detail="RETEST_MISSED level="+DoubleToString(level,_Digits)+" breakout="+FmtTime(breakoutT)+" until="+FmtTime(limit);
   return false;
}

double RateBody(const MqlRates &rates[],int idx)
{
   if(idx<0||idx>=ArraySize(rates))return 0.0;
   return MathAbs(rates[idx].close-rates[idx].open);
}

double BodyPercentileBefore(const MqlRates &rates[],int idx,int lookback,int percentile)
{
   int n=MathMax(5,lookback);
   double bodies[];
   ArrayResize(bodies,0);
   int from=MathMax(0,idx-n-3);
   int to=MathMax(0,idx-3);
   for(int i=from;i<=to&&i<ArraySize(rates);i++)
   {
      double b=RateBody(rates,i);
      if(b<=0.0)continue;
      int sz=ArraySize(bodies);
      ArrayResize(bodies,sz+1);
      bodies[sz]=b;
   }
   int count=ArraySize(bodies);
   if(count<=0)return 0.0;
   ArraySort(bodies);
   int p=MathMax(0,MathMin(100,percentile));
   int pi=(int)MathFloor((p/100.0)*(count-1));
   return bodies[pi];
}

bool HasDisplacementRates(const MqlRates &rates[],int idx,string dir)
{
   if(idx<0||idx>=ArraySize(rates))return false;
   double threshold=BodyPercentileBefore(rates,idx,InpDisplacementLookback,InpDisplacementPercentile);
   if(threshold<=0.0)return false;
   double open=rates[idx].open,close=rates[idx].close,high=rates[idx].high,low=rates[idx].low;
   double body=0.0,oppWick=0.0;
   if(dir=="BUY")
   {
      body=close-open;
      if(body<=0.0)return false;
      oppWick=high-close;
   }
   else
   {
      body=open-close;
      if(body<=0.0)return false;
      oppWick=close-low;
   }
   return body>=threshold && oppWick<=body*MathMax(0.0,InpMaxOpposingWickRatio);
}

bool FindFreshFvgRates(const MqlRates &rates[],int signalIdx,string dir,int maxForwardBars,double &top,double &bottom,double &size,datetime &fvgTime)
{
   top=0.0;bottom=0.0;size=0.0;fvgTime=0;
   int total=ArraySize(rates);
   if(signalIdx<2||total<3)return false;
   int scan=MathMin(MathMax(3,InpFvgScanWindow),MathMax(3,InpFvgLookback));
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.00001;
   double minGap=MathMax(0.0,InpMinFvgGapPoints)*pt;
   int safeForward=MathMax(0,maxForwardBars);
   int scanStart=MathMin(total-1,signalIdx+safeForward);
   int minC3=MathMax(2,signalIdx-scan+1);
   for(int c3=scanStart;c3>=minC3;c3--)
   {
      int c2=c3-1,c1=c3-2;
      if(c1<0)break;
      if(InpFvgRequireDisplacement && !HasDisplacementRates(rates,c2,dir))continue;
      double gap=0.0;
      if(dir=="BUY")
      {
         gap=rates[c3].low-rates[c1].high;
         if(gap<=minGap)continue;
         if(InpRequireUnfilledFvg)
         {
            bool filled=false;
            for(int sh=c3+1;sh<=signalIdx&&sh<total;sh++)
               if(rates[sh].low<rates[c1].high){filled=true;break;}
            if(filled)continue;
         }
         top=rates[c3].low;bottom=rates[c1].high;size=gap;fvgTime=rates[c2].time;return true;
      }
      else
      {
         gap=rates[c1].low-rates[c3].high;
         if(gap<=minGap)continue;
         if(InpRequireUnfilledFvg)
         {
            bool filled=false;
            for(int sh=c3+1;sh<=signalIdx&&sh<total;sh++)
               if(rates[sh].high>rates[c1].low){filled=true;break;}
            if(filled)continue;
         }
         top=rates[c1].low;bottom=rates[c3].high;size=gap;fvgTime=rates[c2].time;return true;
      }
   }
   return false;
}

bool AnalyzeModernSetup(datetime from,datetime to,ENUM_TIMEFRAMES tf,datetime sigT,string dir,
                        bool &hasDisp,bool &hasFvg,string &detail)
{
   hasDisp=false;hasFvg=false;detail="";
   MqlRates rates[];
   int sec=PeriodSeconds(tf);if(sec<=0)sec=60;
   int contextBars=MathMax(InpFvgLookback,InpDisplacementLookback)+8;
   datetime contextFrom=from-(datetime)(contextBars*sec);
   int c=CopyRates(_Symbol,tf,contextFrom,to,rates);
   if(c<=0){detail="modern_no_rates";return false;}
   int idx=-1;
   for(int i=0;i<c;i++)
   {
      if(rates[i].time==sigT){idx=i;break;}
   }
   if(idx<0)
   {
      for(int i=0;i<c;i++)
      {
         if(rates[i].time>=sigT){idx=i;break;}
      }
   }
   if(idx<0||idx>=c){detail="modern_signal_not_found";return false;}
   hasDisp=HasDisplacementRates(rates,idx,dir);
   double top,bottom,size;datetime ft;
   // FVG filter must be knowable at the signal bar. Forward bars are only valid for explicit wait-entry modes, not for historical filter scoring.
   int fvgForwardUsed=0;
   hasFvg=FindFreshFvgRates(rates,idx,dir,fvgForwardUsed,top,bottom,size,ft);
   detail="disp="+(hasDisp?"1":"0")+" fvg="+(hasFvg?"1":"0")+" idx="+IntegerToString(idx)+" bars="+IntegerToString(c)+" fw_used="+IntegerToString(fvgForwardUsed)+" fw_input="+IntegerToString(InpFvgForwardBars);
   if(hasFvg)detail+=" fvg_top="+DoubleToString(top,_Digits)+" fvg_bottom="+DoubleToString(bottom,_Digits)+" fvg_size="+DoubleToString(size,_Digits)+" fvg_time="+FmtTime(ft);
   return true;
}

bool ModernFilterAllows(datetime from,datetime to,ENUM_TIMEFRAMES tf,datetime sigT,string dir,
                        bool requireDisp,ORB_FVG_MODE fvgMode,string &reason,string &detail)
{
   reason="";detail="";
   // Select the source setup before inversion so its signal bar cannot change.
   string ofDetail="";
   if(!McOfFilter(_Symbol,tf,sigT,dir=="BUY"?1:-1,reason,ofDetail)){detail=ofDetail;return false;}
   if(!requireDisp&&fvgMode==ORB_FVG_OFF){detail=ofDetail;return true;}
   bool hasDisp=false,hasFvg=false;
   AnalyzeModernSetup(from,to,tf,sigT,dir,hasDisp,hasFvg,detail);
   if(ofDetail!="")detail+=" "+ofDetail;
   if(requireDisp&&!hasDisp){reason="DISP_BLOCK";return false;}
   if(fvgMode==ORB_FVG_REQUIRE&&!hasFvg){reason="FVG_BLOCK";return false;}
   return true;
}

//=========================================================================
//  HISTORICAL TRADE SIMULATION
//=========================================================================
struct HistResult
{
   int maxTp;       // 0..6
   string outcome;  // "TP1".."TP6","SL","BE","open","timeout"
   double netR;     // net R-multiple
   bool isWin;      // netR > 0 after configured target/HC/cost model
   double entrySpreadPoints; // observed entry quote, EMPTY_VALUE if unavailable
   double simEntry;  // actual simulated fill entry
   datetime entryTime; // first executable quote, separate from the source bar
   double simSl;     // simulated effective initial SL
   double simTarget; // selected final target price
   double costR;     // spread/slippage/commission cost in R
   int targetLeg;    // selected target leg
   int hcLeg;        // selected HC+BE leg
   string exitMode;   // exit mode label used for this simulation
   double exitPrice;  // dynamic/time exit price when applicable
   datetime exitTime; // first terminal event time
   bool valid;        // false means required market data/geometry was unavailable
   string invalidReason;
};

struct OrbWindowSignal
{
   datetime signalTime;
   datetime availableTime;
   string rawDirection;
   string executionDirection;
   string reason;
   double signalClose;
   double signalHigh;
   double signalLow;
   bool drawOnChart;
};

struct OrbHistoricalDaySnapshot
{
   bool known;
   bool valid;
   double hi;
   double lo;
   double avgVolume;
   datetime orbStart;
   datetime orbEnd;
   datetime tradeEnd;
   int usedBars;
   // PREP already scans the complete session in one CopyRates call. Cache its
   // first operational breakout so CALC never repeats the same candidate scan.
   bool operationalKnown;
   bool operationalFound;
   bool operationalHadRawCandidate;
   string operationalDirection;
   datetime operationalSignalTime;
   double operationalClose;
   double operationalHigh;
   double operationalLow;
   double operationalVolume;
   double operationalPreAverageVolume;
   string operationalLastReject;
   string operationalModernDetail;
};

OrbHistoricalDaySnapshot g_histDaySnapshots[];
OrbWindowSignal g_histWindowSignals[];
OrbWindowSignal g_histAcceptedSignals[];
// Diagnostic universe: identical entry gates except macro/RF allow-list switches.
// Never published or used by the executable portfolio lifecycle.
OrbWindowSignal g_regimeReferenceSignals[];
OrbWindowSignal g_regimeReferenceWindows[];
OrbWindowSignal g_histOperationalSignals[];
MqlTick g_histTickReplayCache[];
string g_histTickReplayCacheSymbol="";
ulong g_histTickReplayCacheFromMs=0;
ulong g_histTickReplayCacheToMs=0;
bool g_histTickCoverageKnown=false;
ulong g_histTickFirstAvailableMs=0;
#define ORB_HIST_TICK_BLOCK_SIZE 256
#define ORB_HIST_TICK_PREFETCH_MINUTES 15
struct OrbHistoricalTickBlock
{
   int first;
   int after;
   ulong firstMs;
   ulong lastMs;
   double minBid;
   double maxBid;
   double minAsk;
   double maxAsk;
   int validQuotes;
};
OrbHistoricalTickBlock g_histTickReplayBlocks[];
struct OrbHistoricalTickResumeState
{
   bool active;
   datetime signalTime;
   bool isBuy;
   int nextIndex;
   double entry;
   double sl;
   double risk;
   double tp1;
   double tp2;
   double tp3;
   double tp4;
   double tp5;
   double tp6;
   double targetPrice;
   double targetR;
   bool fixedTarget;
   int targetLeg;
   int hcLeg;
   int maxTp;
   double effectiveSl;
   bool beApplied;
   double tickEntrySpreadPoints;
   datetime fillTime;
   datetime brokerExitAt;
};
OrbHistoricalTickResumeState g_histTickResume;
bool g_histTickResumeAllowed=false;
datetime g_histRunNow=0;
datetime g_histRunNyMid=0;
int g_histRunDays=0;
int g_histPrepBack=-1;
int g_histCalcBack=-1;
int g_histNasOverlayIndex=0;
int g_histOverlayIndex=0;
int g_histRejectedWindowRaw=0;
int g_histDrawnWindowCount=0;
int g_histDrawnNasSignals=0;
int g_histChecked=0;
int g_histDrawn=0;
int g_histFiltered=0;
double g_histRunPoint=0.0;

#include "AuditTickReadGuard.mqh"
#include "OrbAdvancedAuditEngine.mqh"

void WriteInternalSimAudit(string source,datetime sigTime,datetime simEnd,string dir,double plannedEntry,double plannedSl,const HistResult &sim,string detail)
{
   if(!g_auditRuntime||!InpAuditHistoricalSimulationCsv) return;
   string fileName="ORB15_InternalSimAudit_v2_"+AuditDateStr()+".csv";
   bool exists=FileIsExist(fileName);
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return;
   if(!exists||FileSize(h)==0)
      FileWrite(h,"ts_gmt","ts_server","source","build","symbol","chart_tf","signal_tf","direction",
         "signal_time","sim_end","fill_mode","same_bar_policy","native_parity","exit_mode",
         "planned_entry","planned_sl","sim_entry","sim_sl","sim_target","target_leg","hc_leg",
         "max_tp","outcome","exit_time","exit_price","cost_r","net_r","is_win","valid","invalid_reason","detail");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      source,ORB15_BUILD,_Symbol,EnumToString(_Period),TfLabel(g_rtSignalTf),dir,
      TimeToString(sigTime,TIME_DATE|TIME_SECONDS),TimeToString(simEnd,TIME_DATE|TIME_SECONDS),
      BtFillLabel(g_btFillMode),BtSameBarLabel(g_btSameBarPolicy),(g_btNativeParity?"1":"0"),sim.exitMode,
      DoubleToString(plannedEntry,_Digits),DoubleToString(plannedSl,_Digits),
      DoubleToString(sim.simEntry,_Digits),DoubleToString(sim.simSl,_Digits),DoubleToString(sim.simTarget,_Digits),
      IntegerToString(sim.targetLeg),IntegerToString(sim.hcLeg),IntegerToString(sim.maxTp),sim.outcome,
      sim.exitTime>0?TimeToString(sim.exitTime,TIME_DATE|TIME_SECONDS):"",
      DoubleToString(sim.exitPrice,_Digits),DoubleToString(sim.costR,4),DoubleToString(sim.netR,4),(sim.isWin?"1":"0"),
      (sim.valid?"1":"0"),sim.invalidReason,detail);
   FileClose(h);
}

void ClearHistoricalTickReplayCache()
{
   ArrayResize(g_histTickReplayCache,0);
   ArrayResize(g_histTickReplayBlocks,0);
   g_histTickReplayCacheSymbol="";
   g_histTickReplayCacheFromMs=0;
   g_histTickReplayCacheToMs=0;
}

void ClearHistoricalTickResume()
{
   ZeroMemory(g_histTickResume);
   g_histTickResume.active=false;
}

void InitializeHistoricalTickReplayCoverage()
{
   g_histTickCoverageKnown=false;
   g_histTickFirstAvailableMs=0;
   if(g_histRunNow<=0||g_histRunDays<=0)return;
   datetime auditFrom=g_histRunNow-(datetime)((long)g_histRunDays*86400)-86400;
   if(auditFrom<1)auditFrom=1;
   MqlTick firstQuote[];
   ResetLastError();
   int copied=CopyTicks(_Symbol,firstQuote,COPY_TICKS_INFO,(ulong)auditFrom*1000,1);
   int copyError=GetLastError();
   if(copied<=0||ArraySize(firstQuote)<=0||firstQuote[0].time_msc<=0)
   {
      if(copied==0&&copyError==0){g_histTickCoverageKnown=true;g_histTickFirstAvailableMs=ULONG_MAX;}
      return;
   }
   g_histTickFirstAvailableMs=(ulong)firstQuote[0].time_msc;
   g_histTickCoverageKnown=true;
}

void BuildHistoricalTickReplayBlocks(const int rebuildFromTick=0)
{
   int tickCount=ArraySize(g_histTickReplayCache);
   int blockCount=(tickCount+ORB_HIST_TICK_BLOCK_SIZE-1)/ORB_HIST_TICK_BLOCK_SIZE;
   ArrayResize(g_histTickReplayBlocks,blockCount);
   // Appending ticks cannot change a completed earlier block. Rebuild only
   // the block containing the old tail and the newly appended blocks.
   int firstBlock=MathMax(0,MathMin(blockCount,rebuildFromTick/ORB_HIST_TICK_BLOCK_SIZE));
   for(int blockIndex=firstBlock;blockIndex<blockCount;blockIndex++)
   {
      int first=blockIndex*ORB_HIST_TICK_BLOCK_SIZE;
      int after=MathMin(tickCount,first+ORB_HIST_TICK_BLOCK_SIZE);
      OrbHistoricalTickBlock block;
      block.first=first;block.after=after;
      block.firstMs=after>first?(ulong)g_histTickReplayCache[first].time_msc:0;
      block.lastMs=after>first?(ulong)g_histTickReplayCache[after-1].time_msc:0;
      block.minBid=DBL_MAX;block.maxBid=-DBL_MAX;
      block.minAsk=DBL_MAX;block.maxAsk=-DBL_MAX;
      block.validQuotes=0;
      for(int i=first;i<after;i++)
      {
         double bid=g_histTickReplayCache[i].bid;
         double ask=g_histTickReplayCache[i].ask;
         if(bid<=0.0||ask<=0.0)continue;
         if(bid<block.minBid)block.minBid=bid;
         if(bid>block.maxBid)block.maxBid=bid;
         if(ask<block.minAsk)block.minAsk=ask;
         if(ask>block.maxAsk)block.maxAsk=ask;
         block.validQuotes++;
      }
      g_histTickReplayBlocks[blockIndex]=block;
   }
}

int HistoricalTickLowerBound(const ulong targetMs)
{
   int lo=0,hi=ArraySize(g_histTickReplayCache);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if((ulong)g_histTickReplayCache[mid].time_msc<targetMs)lo=mid+1;
      else hi=mid;
   }
   return lo;
}

int HistoricalTickUpperBound(const ulong targetMs)
{
   int lo=0,hi=ArraySize(g_histTickReplayCache);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if((ulong)g_histTickReplayCache[mid].time_msc<=targetMs)lo=mid+1;
      else hi=mid;
   }
   return lo;
}

// CALC walks from oldest to newest. Load a small exact-tick window and stop
// as soon as the trade resolves instead of paying for several unused days.
// No quote is aggregated or approximated; this only removes repeated terminal
// history I/O. The returned slice is the same MqlTick sequence a direct
// CopyTicksRange call provides for [fromMs,toMs].
bool PrepareHistoricalTickReplayRange(const ulong fromMs,const ulong toMs,int &first,int &after,
                                     const uint prefetchMinutes=ORB_HIST_TICK_PREFETCH_MINUTES)
{
   first=0;after=0;
   if(!g_histAuditRunning||fromMs>toMs)return false;
   bool covered=(g_histTickReplayCacheSymbol==_Symbol
      &&ArraySize(g_histTickReplayCache)>0
      &&fromMs>=g_histTickReplayCacheFromMs&&toMs<=g_histTickReplayCacheToMs);
   if(!covered)
   {
      const ulong prefetchMs=(ulong)prefetchMinutes*60*1000;
      ulong loadToMs=toMs;
      if(fromMs<=ULONG_MAX-prefetchMs)
         loadToMs=MathMax(loadToMs,fromMs+prefetchMs);
      ulong auditNowMs=g_histRunNow>0?(ulong)g_histRunNow*1000:toMs;
      if(loadToMs>auditNowMs)loadToMs=auditNowMs;
      if(loadToMs<toMs)loadToMs=toMs;
      bool canExtend=(g_histTickReplayCacheSymbol==_Symbol
         &&ArraySize(g_histTickReplayCache)>0
         &&fromMs>=g_histTickReplayCacheFromMs
         &&fromMs<=g_histTickReplayCacheToMs
         &&loadToMs>g_histTickReplayCacheToMs);
      // ADV batches sparse minute queries without an indefinitely growing window.
      // The original engine retains its existing extension policy.
      if(prefetchMinutes>ORB_HIST_TICK_PREFETCH_MINUTES
         &&(loadToMs-g_histTickReplayCacheFromMs>86400000
            ||(long)ArraySize(g_histTickReplayCache)*sizeof(MqlTick)>67108864))canExtend=false;
      int loaded=0,rebuildFromTick=0;
      if(canExtend)
      {
         MqlTick tail[];
         ulong tailFrom=g_histTickReplayCacheToMs<ULONG_MAX?g_histTickReplayCacheToMs+1:g_histTickReplayCacheToMs;
         // Audit decisions only consume Bid/Ask. Trade-only ticks carry no
         // additional executable price state and needlessly multiply replay I/O.
         loaded=AuditCopyTicksRange(_Symbol,tail,COPY_TICKS_INFO,tailFrom,loadToMs);
         if(loaded>0)
         {
            int oldCount=ArraySize(g_histTickReplayCache);
            rebuildFromTick=oldCount;
            ArrayResize(g_histTickReplayCache,oldCount+loaded);
            ArrayCopy(g_histTickReplayCache,tail,oldCount,0,loaded);
         }
      }
      else
      {
         ArrayResize(g_histTickReplayCache,0);
         loaded=AuditCopyTicksRange(_Symbol,g_histTickReplayCache,COPY_TICKS_INFO,fromMs,loadToMs);
         g_histTickReplayCacheFromMs=fromMs;
      }
      if(loaded<0){ClearHistoricalTickReplayCache();return false;}
      if(loaded<=0)
      {
         if(!canExtend)
         {
            ClearHistoricalTickReplayCache();
            return false;
         }
      }
      g_histTickReplayCacheSymbol=_Symbol;
      g_histTickReplayCacheToMs=loadToMs;
      if(loaded>0)BuildHistoricalTickReplayBlocks(rebuildFromTick);
   }
   first=HistoricalTickLowerBound(fromMs);
   after=HistoricalTickUpperBound(toMs);
   return after>first;
}

// Compatibility helper for diagnostics. The simulation hot path uses the
// indexed cache view directly and therefore does not allocate/copy per trade.
int CopyHistoricalTickReplaySlice(const ulong fromMs,const ulong toMs,MqlTick &ticks[])
{
   int first=0,after=0;
   if(!PrepareHistoricalTickReplayRange(fromMs,toMs,first,after))return 0;
   int count=after-first;
   ArrayResize(ticks,count);
   int copied=ArrayCopy(ticks,g_histTickReplayCache,0,first,count);
   return copied>0?copied:0;
}

bool HistoricalTickBlockCanSkip(const OrbHistoricalTickBlock &block,const bool isBuy,
                                const double entry,const double risk,const double effSl,
                                const double &tps[],const int maxTp,const bool fixedTarget,
                                const double targetPrice,const datetime fillTime,
                                const datetime tradeEnd,const bool scheduledEndReached,
                                const datetime brokerExitAt,const datetime forcedExitTime)
{
   if(block.validQuotes<=0)return true;
   datetime lastTime=(datetime)(block.lastMs/1000);

   // One-shot time events must resolve on the first valid quote at/after the
   // boundary, so a block touching one of them is never skipped.
   if(forcedExitTime>fillTime&&lastTime>=forcedExitTime)return false;
   if(scheduledEndReached&&(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)
      &&lastTime>=tradeEnd)return false;
   if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&lastTime>=brokerExitAt)return false;

   double minClose=isBuy?block.minBid:block.minAsk;
   double maxClose=isBuy?block.maxBid:block.maxAsk;
   if(isBuy?(minClose<=effSl):(maxClose>=effSl))return false;

   // maxTp is part of the final PnL for HC/partial/market exits. Inspect the
   // block if any still-unseen TP level can be touched, even when it is not
   // the selected fixed target.
   int firstUnseenLeg=maxTp;
   if(firstUnseenLeg<0)firstUnseenLeg=0;
   for(int k=firstUnseenLeg;k<6;k++)
      if(isBuy?(maxClose>=tps[k]):(minClose<=tps[k]))return false;
   if(fixedTarget&&(isBuy?(maxClose>=targetPrice):(minClose<=targetPrice)))return false;

   if(g_rtTimeExit&&InpTimeExitMinutes>0&&lastTime>=fillTime+InpTimeExitMinutes*60)
   {
      // TIME_EXIT is a post-deadline price threshold, not an unconditional
      // timer. A block is safe only when every quote remains above/below it.
      double threshold=isBuy?(entry+InpTimeExitMinProgress*risk)
                            :(entry-InpTimeExitMinProgress*risk);
      if(isBuy?(minClose<threshold):(maxClose>threshold))return false;
      // The first block crossing the deadline is safe under the same extrema
      // proof; no state is changed when progress remains sufficient.
   }
   return true;
}

bool SimulateTradeTicks(datetime sigTime,datetime tradeEnd,double entry,double sl,bool isBuy,
                        int halfBeLeg,bool scheduledEndReached,HistResult &res,
                        datetime forcedExitTime=0,string forcedExitOutcome="")
{
   if(!InpBacktestUseTickReplay || !g_btNativeParity) return false;
   if(g_rtExitMode!=ORB_EXIT_FIXED_TARGET&&g_rtExitMode!=ORB_EXIT_EOD_ONLY&&g_rtExitMode!=ORB_EXIT_BROKER_TIME) return false;
   ENUM_TIMEFRAMES entryTf=RuntimeEntryTf();
   datetime startTime=BarCloseTime(entryTf,sigTime);
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN)
   {
      int sec=PeriodSeconds(entryTf);
      if(sec<=0)sec=60;
      startTime=sigTime+sec;
   }
   else if(g_btFillMode==BT_FILL_CONSERVATIVE)
      startTime=BarCloseTime(entryTf,sigTime);
   if(tradeEnd<=startTime)return false;
   MqlTick ticks[];
   ulong fromMs=(ulong)startTime*1000;
   ulong toMs=(ulong)tradeEnd*1000;
   // Intervals before the broker's first available quote tick were always
   // resolved by the OHLC fallback. Detect that boundary once per audit and
   // avoid hundreds of futile history-sync calls on multi-year windows.
   if(g_histTickCoverageKnown&&fromMs<g_histTickFirstAvailableMs)return false;
   int scanFirst=0,scanAfter=0;
   bool useIndexedCache=PrepareHistoricalTickReplayRange(fromMs,toMs,scanFirst,scanAfter);
   if(!useIndexedCache)
   {
      int copied=AuditCopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,fromMs,toMs);
      if(copied<=0)return false;
      scanFirst=0;scanAfter=copied;
   }

   bool resume=(g_histTickResumeAllowed&&useIndexedCache&&g_histTickResume.active
      &&g_histTickResume.signalTime==sigTime&&g_histTickResume.isBuy==isBuy
      &&MathAbs(g_histTickResume.sl-sl)<=MathMax(_Point,0.00000001));
   if(g_histTickResumeAllowed&&g_histTickResume.active&&!resume)ClearHistoricalTickResume();

   int first=-1;
   double risk=0.0,tp1=0,tp2=0,tp3=0,tp4=0,tp5=0,tp6=0;
   double targetPrice=0.0,targetR=0.0;
   int targetLeg=0,hcLeg=0;
   bool fixedTarget=false,beApplied=false;
   double effSl=sl;
   datetime fillTime=0,brokerExitAt=0;
   if(resume)
   {
      first=MathMax(scanFirst,g_histTickResume.nextIndex);
      entry=g_histTickResume.entry;
      // A resumed fill must retain its executable stop, not the incoming plan.
      sl=g_histTickResume.sl;
      risk=g_histTickResume.risk;
      tp1=g_histTickResume.tp1;tp2=g_histTickResume.tp2;tp3=g_histTickResume.tp3;
      tp4=g_histTickResume.tp4;tp5=g_histTickResume.tp5;tp6=g_histTickResume.tp6;
      targetPrice=g_histTickResume.targetPrice;targetR=g_histTickResume.targetR;
      fixedTarget=g_histTickResume.fixedTarget;
      targetLeg=g_histTickResume.targetLeg;hcLeg=g_histTickResume.hcLeg;
      res.maxTp=g_histTickResume.maxTp;
      effSl=g_histTickResume.effectiveSl;beApplied=g_histTickResume.beApplied;
      fillTime=g_histTickResume.fillTime;brokerExitAt=g_histTickResume.brokerExitAt;
      res.entrySpreadPoints=g_histTickResume.tickEntrySpreadPoints;
   }
   else
   {
      MqlTick firstTick;
      ZeroMemory(firstTick);
      for(int i=scanFirst;i<scanAfter;i++)
      {
         MqlTick tick;
         if(useIndexedCache)tick=g_histTickReplayCache[i];else tick=ticks[i];
         double bid=tick.bid;
         double ask=tick.ask;
         if(bid>0.0 && ask>0.0){first=i;firstTick=tick;break;}
      }
      if(first<0)return false;

      double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      if(pt<=0.0)pt=0.00001;
      double slip=MathMax(0.0,g_btSlippagePts)*pt;
      entry=isBuy?(firstTick.ask+slip):(firstTick.bid-slip);
      entry=NormalizeTradePrice(entry);
      bool sourceIsBuy=g_rtInvertMode?!isBuy:isBuy;
      double sourceReferenceEntry=NormalizeTradePrice(sourceIsBuy?(firstTick.ask+slip):(firstTick.bid-slip));
      targetLeg=RuntimeTargetLeg();
      hcLeg=ClampHalfBeLeg(halfBeLeg,targetLeg);
      string geometryDetail="";
      if(!BuildSimGeometry(isBuy,entry,sl,sl,risk,tp1,tp2,tp3,tp4,tp5,tp6,sourceReferenceEntry,geometryDetail))
      {
         if(StringFind(geometryDetail,"INVERSE_GAP_BLOCK")==0)res.invalidReason="INVERSE_GAP_BLOCK";
         else if(LabPolicyEnabled())res.invalidReason="LAB_INVALID_GEOMETRY";
         return false;
      }
      string targetDetail="";
      if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail,sourceReferenceEntry)){if(LabPolicyEnabled())res.invalidReason="LAB_INVALID_TARGET";return false;}
      if(!LabPolicyQuoteAllows(isBuy,sl,targetPrice,firstTick.bid,firstTick.ask)){res.invalidReason="LAB_QUOTE_BLOCK";return false;}
      fixedTarget=ExitModeUsesFixedTp(g_rtExitMode)&&targetPrice>0.0;
      effSl=sl;
      beApplied=false;
      fillTime=(datetime)firstTick.time;
      res.entrySpreadPoints=(firstTick.ask-firstTick.bid)/pt;
      brokerExitAt=(g_rtExitMode==ORB_EXIT_BROKER_TIME?BrokerTimeExitFor(fillTime):0);
   }
   LabPolicyMergeTickExit(fillTime,isBuy?1:-1,tradeEnd,forcedExitTime,forcedExitOutcome);
   res.targetLeg=targetLeg;
   res.hcLeg=hcLeg;
   res.valid=true;
   res.invalidReason="";
   res.simEntry=entry;
   res.entryTime=fillTime;
   res.simSl=sl;
   res.simTarget=fixedTarget?targetPrice:0.0;
   double tps[6];tps[0]=tp1;tps[1]=tp2;tps[2]=tp3;tps[3]=tp4;tps[4]=tp5;tps[5]=tp6;
   for(int i=first;i<scanAfter;i++)
   {
      if(useIndexedCache&&i>first&&i%ORB_HIST_TICK_BLOCK_SIZE==0)
      {
         int blockIndex=i/ORB_HIST_TICK_BLOCK_SIZE;
         if(blockIndex>=0&&blockIndex<ArraySize(g_histTickReplayBlocks))
         {
            OrbHistoricalTickBlock block=g_histTickReplayBlocks[blockIndex];
            if(block.first==i&&block.after<=scanAfter
               &&HistoricalTickBlockCanSkip(block,isBuy,entry,risk,effSl,tps,res.maxTp,
                                             fixedTarget,targetPrice,fillTime,tradeEnd,
                                             scheduledEndReached,brokerExitAt,forcedExitTime))
            {
               g_histTickBlocksSkipped++;
               g_histTickTicksSkipped+=(long)(block.after-block.first);
               i=block.after-1;
               continue;
            }
         }
      }
      MqlTick tick;
      if(useIndexedCache)tick=g_histTickReplayCache[i];else tick=ticks[i];
      g_histTickTicksVisited++;
      double bid=tick.bid;
      double ask=tick.ask;
      if(bid<=0.0 || ask<=0.0)continue;
      double closePx=isBuy?bid:ask;

      if(forcedExitTime>fillTime && (datetime)tick.time>=forcedExitTime)
      {
         bool forcedSlHit=isBuy?(closePx<=effSl):(closePx>=effSl);
         bool forcedTargetHit=fixedTarget&&(isBuy?(closePx>=targetPrice):(closePx<=targetPrice));
         if(forcedSlHit)
         {
            res.outcome=beApplied?"BE":"SL";
            res.exitPrice=effSl;
         }
         else if(forcedTargetHit)
         {
            res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");
            res.exitPrice=targetPrice;
         }
         else
         {
            int forcedHitLeg=0;
            for(int k=0;k<6;k++)
               if(isBuy?(closePx>=tps[k]):(closePx<=tps[k]))forcedHitLeg=k+1;
            if(forcedHitLeg>res.maxTp)res.maxTp=forcedHitLeg;
            if(hcLeg>0&&res.maxTp>=hcLeg&&!beApplied){effSl=entry;beApplied=true;}
            res.outcome=forcedExitOutcome!=""?forcedExitOutcome:"FILTER_REVERSE_EXIT";
            res.exitPrice=closePx;
         }
         res.exitTime=(datetime)tick.time;
         break;
      }

      if(g_rtTimeExit && InpTimeExitMinutes>0 && (datetime)tick.time>=fillTime+InpTimeExitMinutes*60)
      {
         double progressR=SimSignedR(isBuy,entry,closePx,risk);
         if(progressR<InpTimeExitMinProgress)
         {
            res.outcome="TIME_EXIT";
            res.exitPrice=closePx;
            res.exitTime=(datetime)tick.time;
            break;
         }
      }

      if(scheduledEndReached&&(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)&&(datetime)tick.time>=tradeEnd)
      {
         res.outcome="EOD_EXIT";
         res.exitPrice=closePx;
         res.exitTime=(datetime)tick.time;
         break;
      }
      if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&(datetime)tick.time>=brokerExitAt)
      {
         res.outcome="BROKER_TIME_EXIT";
         res.exitPrice=closePx;
         res.exitTime=(datetime)tick.time;
         break;
      }

      bool slHit=isBuy?(closePx<=effSl):(closePx>=effSl);
      if(slHit)
      {
         res.exitPrice=effSl;
         res.outcome=beApplied?"BE":"SL";
         res.exitTime=(datetime)tick.time;
         break;
      }

      int hitLeg=0;
      for(int k=0;k<6;k++)
      {
         bool hit=isBuy?(closePx>=tps[k]):(closePx<=tps[k]);
         if(hit)hitLeg=k+1;
      }
      if(hitLeg>res.maxTp)res.maxTp=hitLeg;
      if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied)
      {
         effSl=entry;
         beApplied=true;
      }
      bool targetHit=fixedTarget&&(isBuy?(closePx>=targetPrice):(closePx<=targetPrice));
      if(targetHit)
      {
         res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");
         res.exitPrice=targetPrice;
         res.exitTime=(datetime)tick.time;
         break;
      }
   }

   if(g_histTickResumeAllowed&&useIndexedCache&&res.outcome=="open")
   {
      g_histTickResume.active=true;
      g_histTickResume.signalTime=sigTime;
      g_histTickResume.isBuy=isBuy;
      g_histTickResume.nextIndex=scanAfter;
      g_histTickResume.entry=entry;
      g_histTickResume.sl=sl;
      g_histTickResume.risk=risk;
      g_histTickResume.tp1=tp1;g_histTickResume.tp2=tp2;g_histTickResume.tp3=tp3;
      g_histTickResume.tp4=tp4;g_histTickResume.tp5=tp5;g_histTickResume.tp6=tp6;
      g_histTickResume.targetPrice=targetPrice;g_histTickResume.targetR=targetR;
      g_histTickResume.fixedTarget=fixedTarget;
      g_histTickResume.targetLeg=targetLeg;g_histTickResume.hcLeg=hcLeg;
      g_histTickResume.maxTp=res.maxTp;
      g_histTickResume.effectiveSl=effSl;g_histTickResume.beApplied=beApplied;
      g_histTickResume.fillTime=fillTime;g_histTickResume.brokerExitAt=brokerExitAt;
      g_histTickResume.tickEntrySpreadPoints=res.entrySpreadPoints;
   }
   else if(g_histTickResumeAllowed)
      ClearHistoricalTickResume();

   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      bool marketExit=IsSimMarketExitOutcome(res.outcome);
      double runnerR=marketExit?SimSignedR(isBuy,entry,res.exitPrice,risk):0.0;
      double leg1=res.maxTp>=1?LegR(1):(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0));
      double leg2=res.maxTp>=2?LegR(2):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      double leg3=res.maxTp>=3?LegR(3):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      if(res.outcome=="SL"&&res.maxTp==0){leg1=-1;leg2=-1;leg3=-1;}
      res.netR=(leg1+leg2+leg3)/3.0;
   }
   else
   {
      bool targetOutcome=(g_rtTargetMode==ORB_TARGET_R_LEG&&res.outcome==TargetOutcomeLabel(targetLeg))
         ||(g_rtTargetMode!=ORB_TARGET_R_LEG&&res.outcome=="TARGET");
      if(fixedTarget&&targetOutcome)
      {
         res.netR=hcLeg>0?0.5*LegR(hcLeg)+0.5*targetR:targetR;
      }
      else if(IsSimMarketExitOutcome(res.outcome))
      {
         double runnerR=SimSignedR(isBuy,entry,res.exitPrice,risk);
         res.netR=(hcLeg>0&&res.maxTp>=hcLeg)?0.5*LegR(hcLeg)+0.5*runnerR:runnerR;
      }
      else if((res.outcome=="BE"||res.outcome=="open"||res.outcome=="TP"+IntegerToString(res.maxTp))&&hcLeg>0&&res.maxTp>=hcLeg)
         res.netR=0.5*LegR(hcLeg);
      else if(res.outcome=="SL")res.netR=-1.0;
   }
   // Tick replay already embeds bid/ask spread and explicit entry slippage in the fill.
   // Only commission remains an extra R-cost here.
   res.costR=BtCostR(risk,false,false);
   res.netR-=res.costR;
   res.isWin=res.netR>0;
   return true;
}

HistResult SimulateTrade(datetime sigTime,datetime tradeEnd,double entry,double sl,bool isBuy,
                             double tp1,double tp2,double tp3,int halfBeLeg,bool scheduledEndReached=true,
                             datetime forcedExitTime=0,string forcedExitOutcome="")
{
   ulong tickReadFailures=g_auditTickReadFailures;
   HistResult res;
   res.maxTp=0;res.outcome="open";res.netR=0;res.isWin=false;
   res.simEntry=entry;res.entryTime=0;res.entrySpreadPoints=EMPTY_VALUE;res.simSl=sl;res.simTarget=0;res.costR=0;
   res.exitMode=RuntimeExitLabel();res.exitPrice=0;res.exitTime=0;
   res.valid=false;res.invalidReason="NO_MARKET_DATA";
   res.targetLeg=RuntimeTargetLeg();res.hcLeg=ClampHalfBeLeg(halfBeLeg,res.targetLeg);
   if(g_rtAdvancedAuditEngine&&!g_rtAdvancedReverse)
   {
      HistResult advanced=res;
      if(SimulateTradeTicksAdvanced(sigTime,tradeEnd,entry,sl,isBuy,halfBeLeg,scheduledEndReached,advanced,forcedExitTime,forcedExitOutcome))
      {
         if(InpAdvancedAuditShadowParity)
         {
            HistResult legacy=res;
            bool savedResumeAllowed=g_histTickResumeAllowed;
            g_histTickResumeAllowed=false;
            ClearHistoricalTickResume();
            bool legacyAvailable=SimulateTradeTicks(sigTime,tradeEnd,entry,sl,isBuy,halfBeLeg,scheduledEndReached,legacy,forcedExitTime,forcedExitOutcome);
            g_histTickResumeAllowed=savedResumeAllowed;
            ClearHistoricalTickResume();
            if(legacyAvailable)
            {
               g_orbAdvParityChecks++;
               string parityDetail="";
               if(!OrbAdvancedAuditEquivalent(advanced,legacy,parityDetail))
               {
                  g_orbAdvParityMismatches++;
                  Print("ORB15v3 ADV PARITY MISMATCH; legacy selected | ",parityDetail);
                  return legacy;
               }
            }
         }
         return advanced;
      }
   }
   if(SimulateTradeTicks(sigTime,tradeEnd,entry,sl,isBuy,halfBeLeg,scheduledEndReached,res,forcedExitTime,forcedExitOutcome))
      return res;
   if(res.invalidReason=="INVERSE_GAP_BLOCK")return res;
   if(g_auditTickReadFailures!=tickReadFailures){res.valid=false;res.invalidReason="TICK_HISTORY_PENDING";res.netR=0;res.isWin=false;return res;}
   if(g_rtInvertMode){res.valid=false;res.invalidReason="INVERSE_TICKS_REQUIRED";res.netR=0;res.isWin=false;return res;}
   // Preserve NO_MARKET_DATA so the existing lifecycle can extend across a
   // scheduled market break. Never invent a policy exit using an OHLC fill.
   if(LabPolicyEnabled())return res;
   ENUM_TIMEFRAMES entryTf=RuntimeEntryTf();
   ResetLastError();
   MqlRates r[];int c=CopyRates(_Symbol,entryTf,sigTime,tradeEnd,r);
   int ratesError=GetLastError();
   if(ratesError!=0){res.invalidReason="BAR_HISTORY_PENDING";return res;}
   if(c<=1)return res;
   int signalSeconds=PeriodSeconds(entryTf);if(signalSeconds<=0)signalSeconds=60;
   if(r[0].time>sigTime||r[0].time+signalSeconds<=sigTime){res.invalidReason="BAR_HISTORY_PREFIX_MISSING";return res;}
   int fillBarIndex=(g_btFillMode==BT_FILL_SIGNAL_CLOSE?0:1);
   double historicalSpreadPts=r[fillBarIndex].spread>0?(double)r[fillBarIndex].spread:g_btSpreadPts;
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN && c>1) entry=r[1].open;
   else if(g_btFillMode==BT_FILL_CONSERVATIVE && c>1)
   {
      double no=r[1].open;
      entry=isBuy?MathMax(entry,no):MathMin(entry,no);
   }
   entry=NormalizeTradePrice(entry);
   double risk=0.0;
   double gt1=0,gt2=0,gt3=0,gt4=0,gt5=0,gt6=0;
   string barGeometryDetail="";
   if(!BuildSimGeometry(isBuy,entry,sl,sl,risk,gt1,gt2,gt3,gt4,gt5,gt6,0.0,barGeometryDetail))
   {res.invalidReason="INVALID_GEOMETRY";return res;}

   int sec=PeriodSeconds(entryTf);if(sec<=0)sec=60;
   int ctxBars=MathMax(320,MathMax(MathMax(InpExitEmaPeriod*4,InpExitAtrPeriod*4),100));
   MqlRates ctx[];int ctxCount=CopyRates(_Symbol,entryTf,sigTime-(datetime)(ctxBars*sec),tradeEnd,ctx);

   int targetLeg=RuntimeTargetLeg();
   int hcLeg=ClampHalfBeLeg(halfBeLeg,targetLeg);
   res.targetLeg=targetLeg;
   res.hcLeg=hcLeg;
   double tps[6];
   tps[0]=gt1;tps[1]=gt2;tps[2]=gt3;tps[3]=gt4;tps[4]=gt5;tps[5]=gt6;
   double targetPrice=0.0,targetR=0.0;string targetDetail="";
   if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail)){res.invalidReason="INVALID_TARGET";return res;}
   res.valid=true;
   res.invalidReason="";
   bool fixedTarget=ExitModeUsesFixedTp(g_rtExitMode)&&targetPrice>0.0;
   res.simEntry=NormalizePrice(entry);
   res.entryTime=(g_btFillMode==BT_FILL_SIGNAL_CLOSE?BarCloseTime(entryTf,r[0].time):r[1].time);
   res.entrySpreadPoints=EMPTY_VALUE; // Bar fallback has no observed entry quote.
   res.simSl=NormalizePrice(sl);
   res.simTarget=fixedTarget?targetPrice:0.0;

   double effSl=sl;bool beApplied=false;
   double bestHigh=entry,bestLow=entry;
   datetime brokerExitAt=(g_rtExitMode==ORB_EXIT_BROKER_TIME?BrokerTimeExitFor(sigTime):0);
   for(int i=1;i<c;i++) // skip signal bar itself
   {
      if(r[i].time>tradeEnd)break;
      if(forcedExitTime>sigTime && r[i].time>=forcedExitTime)
      {
         double forcedPrice=0.0;datetime resolvedAt=forcedExitTime;
         ResolveHistoricalForcedExitPrice(forcedExitTime,isBuy,r[i].open,(double)r[i].spread,forcedPrice,resolvedAt);
         bool forcedSlHit=isBuy?(forcedPrice<=effSl):(forcedPrice>=effSl);
         bool forcedTargetHit=fixedTarget&&(isBuy?(forcedPrice>=targetPrice):(forcedPrice<=targetPrice));
         if(forcedSlHit)
         {
            res.outcome=beApplied?"BE":"SL";
            res.exitPrice=effSl;
         }
         else if(forcedTargetHit)
         {
            res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");
            res.exitPrice=targetPrice;
         }
         else
         {
            int forcedHitLeg=0;
            for(int k=0;k<6;k++)
               if(isBuy?(forcedPrice>=tps[k]):(forcedPrice<=tps[k]))forcedHitLeg=k+1;
            if(forcedHitLeg>res.maxTp)res.maxTp=forcedHitLeg;
            if(hcLeg>0&&res.maxTp>=hcLeg&&!beApplied){effSl=entry;beApplied=true;}
            res.outcome=forcedExitOutcome!=""?forcedExitOutcome:"FILTER_REVERSE_EXIT";
            res.exitPrice=forcedPrice;
         }
         res.exitTime=resolvedAt;
         break;
      }
      bool slHit=isBuy?(r[i].low<=effSl):(r[i].high>=effSl);

      int hitLeg=0;
      if(fixedTarget)
      {
         for(int k=0;k<6;k++)
         {
            bool hit=isBuy?(r[i].high>=tps[k]):(r[i].low<=tps[k]);
            if(hit)hitLeg=k+1;
         }
         bool customTargetHit=isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice);
         if(customTargetHit&&g_rtTargetMode!=ORB_TARGET_R_LEG)hitLeg=MathMax(hitLeg,MathMin(6,targetLeg));
      }

      // Resolve a same-bar SL/profit collision against the actual configured target.
      // The special 0.75R target is not a numbered TP milestone and must never index tps[].
      bool targetTouched=fixedTarget&&(isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice));
      if(slHit&&(hitLeg>0||targetTouched))
      {
         int compareLeg=MathMax(1,MathMin(6,hitLeg));
         double profitTouchPrice=targetTouched?targetPrice:tps[compareLeg-1];
         if(BtTpFirst(isBuy,r[i].open,effSl,profitTouchPrice))
         {
            res.maxTp=hitLeg;
            if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
            if(targetTouched){res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");res.exitPrice=targetPrice;res.exitTime=r[i].time;break;}
            // Profit milestone came first, then the same bar also crossed protection.
            res.outcome=beApplied?"BE":"SL";
            res.exitPrice=effSl;
            res.exitTime=r[i].time;
            break;
         }
         else{res.outcome=beApplied?"BE":"SL";res.exitPrice=effSl;res.exitTime=r[i].time;break;}
      }
      else
      {
         if(slHit){res.outcome=beApplied?"BE":"SL";res.exitPrice=effSl;res.exitTime=r[i].time;break;}
         if(hitLeg>res.maxTp)res.maxTp=hitLeg;
      }

      if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
      if(fixedTarget)
      {
         bool targetHit=isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice);
         if(targetHit){res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");res.exitPrice=targetPrice;res.exitTime=r[i].time;break;}
      }

      if(g_rtTimeExit && InpTimeExitMinutes>0 && r[i].time>=sigTime+InpTimeExitMinutes*60)
      {
         double progressR=SimSignedR(isBuy,entry,r[i].close,risk);
         if(progressR<InpTimeExitMinProgress)
         {
            res.outcome="TIME_EXIT";
            res.exitPrice=r[i].close;
            res.exitTime=r[i].time;
            break;
         }
      }

      if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&r[i].time>=brokerExitAt)
      {
         res.outcome="BROKER_TIME_EXIT";
         res.exitPrice=r[i].close;
         res.exitTime=r[i].time;
         break;
      }

      bestHigh=MathMax(bestHigh,r[i].high);
      bestLow=MathMin(bestLow,r[i].low);
      bool dynStart=(g_rtExitTrailStartLeg<=0||res.maxTp>=g_rtExitTrailStartLeg);
      int grace=MathMax(0,InpExitGraceBars);
      bool graceDone=(i>grace);
      if(res.outcome=="open"&&dynStart&&graceDone)
      {
         if(g_rtExitMode==ORB_EXIT_ORB_MID_INVALIDATION)
         {
            double mid=(g_orbHigh>g_orbLow?NormalizePrice((g_orbHigh+g_orbLow)/2.0):0.0);
            bool ex=mid>0.0&&(isBuy?(r[i].close<mid):(r[i].close>mid));
            if(ex){res.outcome="MID_EXIT";res.exitPrice=r[i].close;res.exitTime=r[i].time;break;}
         }
         else if(g_rtExitMode==ORB_EXIT_VWAP_STOP)
         {
            double vwap=SessionVwap(g_orbStartServer,r[i].time+sec,PERIOD_M1);
            bool ex=vwap>0.0&&(isBuy?(r[i].close<vwap):(r[i].close>vwap));
            if(ex){res.outcome="VWAP_EXIT";res.exitPrice=r[i].close;res.exitTime=r[i].time;break;}
         }
         else if(g_rtExitMode==ORB_EXIT_EMA_STOP&&ctxCount>0)
         {
            double alpha=2.0/(double)(ClampEmaPeriod(g_rtExitEmaPeriod)+1);
            double ema=0.0;bool found=false;
            for(int e=0;e<ctxCount;e++)
            {
               ema=(e==0?ctx[e].close:ema+alpha*(ctx[e].close-ema));
               if(ctx[e].time==r[i].time){found=true;break;}
            }
            bool ex=found&&ema>0.0&&(isBuy?(r[i].close<ema):(r[i].close>ema));
            if(ex){res.outcome="EMA_EXIT";res.exitPrice=r[i].close;res.exitTime=r[i].time;break;}
         }
      }
      if(res.outcome=="open"&&g_rtExitMode==ORB_EXIT_ATR_TRAIL&&dynStart&&ctxCount>0)
      {
         int ctxIdx=-1;for(int a=0;a<ctxCount;a++)if(ctx[a].time==r[i].time){ctxIdx=a;break;}
         if(ctxIdx>InpExitAtrPeriod+1)
         {
            double atr=0.0;int n=0;
            for(int a=ctxIdx-InpExitAtrPeriod+1;a<=ctxIdx&&a>0;a++)
            {
               double tr=ctx[a].high-ctx[a].low;
               tr=MathMax(tr,MathAbs(ctx[a].high-ctx[a-1].close));
               tr=MathMax(tr,MathAbs(ctx[a].low-ctx[a-1].close));
               atr+=tr;n++;
            }
            if(n>0)
            {
               atr/=n;
               double trail=isBuy?NormalizePrice(bestHigh-atr*g_rtExitAtrMultiplier):NormalizePrice(bestLow+atr*g_rtExitAtrMultiplier);
               if(isBuy&&trail>effSl&&trail<r[i].close)effSl=trail;
               if(!isBuy&&trail<effSl&&trail>r[i].close)effSl=trail;
            }
         }
      }
   }
   if(res.outcome=="open"&&scheduledEndReached&&(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)&&c>1){res.outcome="EOD_EXIT";res.exitPrice=r[c-1].close;res.exitTime=r[c-1].time;}
   else if(res.outcome=="open"&&g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&tradeEnd>=brokerExitAt&&c>1){res.outcome="BROKER_TIME_EXIT";res.exitPrice=r[c-1].close;res.exitTime=r[c-1].time;}

   // Net R calculation.
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      bool marketExit=IsSimMarketExitOutcome(res.outcome);
      double marketPx=res.exitPrice>0?res.exitPrice:(c>1?r[c-1].close:entry);
      double runnerR=marketExit?SimSignedR(isBuy,entry,marketPx,risk):0.0;
      double leg1=res.maxTp>=1?LegR(1):(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0));
      double leg2=res.maxTp>=2?LegR(2):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      double leg3=res.maxTp>=3?LegR(3):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      if(res.outcome=="SL"&&res.maxTp==0){leg1=-1;leg2=-1;leg3=-1;}
      res.netR=(leg1+leg2+leg3)/3.0;
   }
   else
   {
      if((g_rtTargetMode==ORB_TARGET_R_LEG&&res.outcome==TargetOutcomeLabel(targetLeg))||(g_rtTargetMode!=ORB_TARGET_R_LEG&&res.outcome=="TARGET"))
      {
         if(hcLeg>0)res.netR=0.5*LegR(hcLeg)+0.5*targetR;
         else res.netR=targetR;
      }
      else if(IsSimMarketExitOutcome(res.outcome))
      {
         double px=res.exitPrice>0?res.exitPrice:(c>1?r[c-1].close:entry);
         double runnerR=SimSignedR(isBuy,entry,px,risk);
         res.netR=(hcLeg>0&&res.maxTp>=hcLeg)?0.5*LegR(hcLeg)+0.5*runnerR:runnerR;
      }
      else if((res.outcome=="BE"||res.outcome=="open"||res.outcome=="TP"+IntegerToString(res.maxTp))&&hcLeg>0&&res.maxTp>=hcLeg)
         res.netR=0.5*LegR(hcLeg);
      else if(res.outcome=="SL")res.netR=-1.0;
   }
   // Tick history is not available for every historical interval. In OHLC
   // fallback use that entry bar's recorded spread, never today's snapshot.
   res.costR=BtCostRForSpread(risk,historicalSpreadPts);
   res.netR-=res.costR;
   res.isWin=res.netR>0;
   return res;
}


#include "AuditMemoIndex.mqh"
#include "OrbReplayMemoEpoch.mqh"
AuditMemoIndex g_orbReplayMemo;
HistResult g_orbReplayValues[];
datetime g_orbReplayEnds[];
long g_orbReplayMemoHits=0,g_orbReplayMemoMisses=0;

HistResult OrbMemoLifecycle(datetime entryTime,datetime sessionEnd,datetime now,double entry,double sl,bool isBuy,
   double tp1,double tp2,double tp3,int halfBeLeg,datetime &usedEnd,datetime forcedExitTime=0,string forcedExitOutcome="")
{
   string epoch=LabEngineIdentity()+OrbReplayDataEpoch();
   g_orbReplayMemo.Reset(epoch);
   string key=(string)entryTime+"|"+(string)sessionEnd+"|"+AuditMemoPrice(entry)+"|"+AuditMemoPrice(sl)
      +"|"+(string)isBuy+"|"+AuditMemoPrice(tp1)+"|"+AuditMemoPrice(tp2)+"|"+AuditMemoPrice(tp3)
      +"|"+(string)halfBeLeg+"|"+(string)forcedExitTime+"|"+forcedExitOutcome
      +"|"+AuditMemoPrice(g_orbHigh)+"|"+AuditMemoPrice(g_orbLow)
      +"|"+(string)g_orbStartServer+"|"+(string)g_orbEndServer+"|"+(string)g_tradeEndServer
      +"|"+AuditMemoPrice(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE))
      +"|"+AuditMemoPrice(g_btCommissionPerLot!=0?SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE):0);
   key+="|MAEXIT_FILTERED3="+(string)g_maReverseExit+","+(string)g_maReverseWait;
   key+="|g_rtFilterAtr="+(string)g_rtFilterAtr;
   key+=McOfIdentity();
   key+="|g_rtFilterVol="+(string)g_rtFilterVol;
   key+="|g_rtFilterDay="+(string)g_rtFilterDay;
   key+="|g_rtFilteredWindowReverseExit="+(string)g_rtFilteredWindowReverseExit;
   key+="|g_rtPostTradeDispBlockExit="+(string)g_rtPostTradeDispBlockExit;
   key+="|g_rtEntryWindow="+(string)g_rtEntryWindow;
   key+="|g_rtEntryWindowStartMin="+(string)g_rtEntryWindowStartMin;
   key+="|g_rtEntryWindowEndMin="+(string)g_rtEntryWindowEndMin;
   key+="|g_rtTimeExit="+(string)g_rtTimeExit;
   key+="|g_rtDisplacement="+(string)g_rtDisplacement;
   key+="|g_rtFvgMode="+(string)g_rtFvgMode;
   key+="|g_rtExitMode="+(string)g_rtExitMode;
   key+="|g_rtEntryMode="+(string)g_rtEntryMode;
   key+="|g_rtTargetMode="+(string)g_rtTargetMode;
   key+="|g_rtBEOnTp1="+(string)g_rtBEOnTp1;
   key+="|g_rtEaEnabled="+(string)g_rtEaEnabled;
   key+="|g_rtInvertMode="+(string)g_rtInvertMode;
   if(g_rtInvertMode)key+="|INV_LEVEL_SWAP_1";
   key+="|entryDirection="+(string)g_entryDirection+"|dailyLoss="+(string)g_dailyMaxLosses+"|dailyWin="+(string)g_dailyTargetWins+"|dailyStart="+(string)g_dailyStartMinute;
   key+="|g_rtAdvancedReverse="+(string)g_rtAdvancedReverse;
   key+="|g_rtAdvancedReverseMaxCostPct="+AuditMemoPrice(g_rtAdvancedReverseMaxCostPct);
   key+="|g_rtUtcMidnightSession="+(string)g_rtUtcMidnightSession;
   key+="|g_rtNasConfirmation="+(string)g_rtNasConfirmation;
   key+="|g_rtNasStateGate="+(string)g_rtNasStateGate;
   key+="|g_rtNasExitOnOppositeSignal="+(string)g_rtNasExitOnOppositeSignal;
   key+="|g_rtNasAdditionalExit="+(string)g_rtNasAdditionalExit;
   key+="|g_rtAdvancedAuditEngine="+(string)g_rtAdvancedAuditEngine;
   key+="|g_rtNasSensitivity="+(string)g_rtNasSensitivity;
   key+="|g_rtNasVolumeFilter="+(string)g_rtNasVolumeFilter;
   key+="|g_rtNasVolumeMultiplier="+AuditMemoPrice(g_rtNasVolumeMultiplier);
   key+="|g_rtNasFlowVolumeFilter="+(string)g_rtNasFlowVolumeFilter;
   key+="|g_rtNasFlowVolumeMultiplier="+AuditMemoPrice(g_rtNasFlowVolumeMultiplier);
   key+="|g_rtNasActiveSignalLookbackMinutes="+(string)g_rtNasActiveSignalLookbackMinutes;
   key+="|g_rtNasOppositeExitWaitMinutes="+(string)g_rtNasOppositeExitWaitMinutes;
   key+="|g_rtRiskPerTradePct="+AuditMemoPrice(g_rtRiskPerTradePct);
   key+="|g_rtVolumeMultiplier="+AuditMemoPrice(g_rtVolumeMultiplier);
   key+="|g_rtSignalTf="+(string)g_rtSignalTf;
   key+="|ma_audit_schema=events1|ma_kernel="+MC_KERNEL_REVISION+"|ma_h4seed="+(string)McHistorySeed(_Symbol,PERIOD_H4)+"|ma_seed="+(string)McHistorySeed(_Symbol,g_rtSignalTf)+"|ma_mode="+(string)g_rtMaCrossMode+"|ma_pair="+(string)g_rtMaCrossPair+"|ma_fast="+(string)InpMaFastLength+"|ma_medium="+(string)InpMaMediumLength+"|ma_slow="+(string)InpMaSlowLength;
   key+="|g_rtDelayMin="+(string)g_rtDelayMin;
   key+="|g_rtUseDelay="+(string)g_rtUseDelay;
   key+="|g_rtTargetLeg="+(string)g_rtTargetLeg;
   if(g_rtTargetLeg==(int)ORB_TARGET_CUSTOM)key+="|customR="+DoubleToString(g_rtCustomR,8);
   key+="|g_rtHalfBeLeg="+(string)g_rtHalfBeLeg;
   key+="|g_rtExitTrailStartLeg="+(string)g_rtExitTrailStartLeg;
   key+="|g_rtExitEmaPeriod="+(string)g_rtExitEmaPeriod;
   key+="|g_rtExitAtrMultiplier="+AuditMemoPrice(g_rtExitAtrMultiplier);
   key+="|g_rtSlDistancePct="+AuditMemoPrice(g_rtSlDistancePct);
   key+="|g_rtPipSlMode="+(string)g_rtPipSlMode;
   key+="|g_rtPipSlPips="+AuditMemoPrice(g_rtPipSlPips);
   key+="|g_btFillMode="+(string)g_btFillMode;
   key+="|g_btSameBarPolicy="+(string)g_btSameBarPolicy;
   key+="|g_btNativeParity="+(string)g_btNativeParity;
   key+="|g_btSpreadPts="+AuditMemoPrice(g_btSpreadPts);
   key+="|g_btSlippagePts="+AuditMemoPrice(g_btSlippagePts);
   key+="|g_btCommissionPerLot="+AuditMemoPrice(g_btCommissionPerLot);
   int cached=g_orbReplayMemo.Find(key);
   if(cached>=0&&g_orbReplayValues[cached].exitTime<=now)
   {usedEnd=g_orbReplayEnds[cached];g_orbReplayMemoHits++;return g_orbReplayValues[cached];}
   g_orbReplayMemoMisses++;
   HistResult result=g_rtAdvancedAuditEngine
      ?SimulateHistoricalLifecycleAdvanced(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,usedEnd,forcedExitTime,forcedExitOutcome)
      :SimulateHistoricalLifecycle(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,usedEnd,forcedExitTime,forcedExitOutcome);
   // Do not freeze OPEN, DATA, asynchronous tick requests or this forming minute.
   if(result.valid&&result.outcome!="open"&&result.invalidReason==""&&result.exitTime>0
      &&result.exitTime<=now&&result.exitTime<iTime(_Symbol,PERIOD_M1,0)&&epoch==LabEngineIdentity()+OrbReplayDataEpoch())
   {
      int slot=g_orbReplayMemo.Add(key);
      if(slot>=0)
      {
         if(ArraySize(g_orbReplayValues)<=slot)
         {ArrayResize(g_orbReplayValues,slot+1,512);ArrayResize(g_orbReplayEnds,slot+1,512);}
         g_orbReplayValues[slot]=result;g_orbReplayEnds[slot]=usedEnd;
      }
   }
   return result;
}

HistResult SimulateHistoricalLifecycle(datetime entryTime,datetime sessionEnd,datetime now,double entry,double sl,bool isBuy,
                                       double tp1,double tp2,double tp3,int halfBeLeg,datetime &usedEnd,
                                       datetime forcedExitTime=0,string forcedExitOutcome="")
{
   ClearHistoricalTickResume();
   g_histTickResumeAllowed=true;
   bool sessionBound=(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD);
   bool brokerBound=(g_rtExitMode==ORB_EXIT_BROKER_TIME);
   int sec=PeriodSeconds(RuntimeEntryTf());if(sec<=0)sec=60;
   datetime horizon=sessionEnd;
   if(sessionBound)
   {
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else if(brokerBound)
   {
      horizon=BrokerTimeExitFor(entryTime)+sec;
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else
   {
      // Fixed-target trades are not session-bound. Start with a compact exact
      // window; unresolved trades expand below without changing chronology.
      datetime firstEnd=entryTime+ORB_HIST_TICK_PREFETCH_MINUTES*60;
      horizon=firstEnd;
      if(forcedExitTime>entryTime&&forcedExitTime<horizon)horizon=forcedExitTime+sec;
      if(horizon>now)horizon=now;
   }
   if(horizon<=entryTime)horizon=now;

   bool scheduledEndReached=(!sessionBound||now>=sessionEnd);
   HistResult sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,scheduledEndReached,forcedExitTime,forcedExitOutcome);
   int expand=0;
   // 15-minute prefetch needs two additional doublings to preserve the old
   // one-hour/16-step maximum horizon. Twenty steps safely covers 5Y audits.
   // A short initial slice can contain only the signal candle before a
   // scheduled market break. Extend it instead of declaring missing history.
   while(((sim.valid&&sim.outcome=="open")||(!sim.valid&&sim.invalidReason=="NO_MARKET_DATA"))&&!sessionBound&&!brokerBound&&horizon<now&&expand<20)
   {
      long span=(long)(horizon-entryTime);
      if(span<ORB_HIST_TICK_PREFETCH_MINUTES*60)span=ORB_HIST_TICK_PREFETCH_MINUTES*60;
      long grown=span*2;
      datetime nextEnd=(datetime)((long)entryTime+grown);
      if(nextEnd>now)nextEnd=now;
      if(nextEnd<=horizon)break;
      horizon=nextEnd;
      sim=SimulateTrade(entryTime,horizon,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,true,forcedExitTime,forcedExitOutcome);
      expand++;
   }
   usedEnd=horizon;
   g_histTickResumeAllowed=false;
   ClearHistoricalTickResume();
   return sim;
}

datetime OrbSignalAvailableTime(datetime signalTime)
{
   if(!InpUseClosedBarBreakout)return signalTime;
   datetime available=BarCloseTime(g_rtSignalTf,signalTime);
   return available>0?available:signalTime;
}

double OrbHistoricalArrowPrice(bool isBuy,double entry,double risk)
{
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double pad=MathMax(MathMax(risk,pt)*0.18,pt*40.0);
   return NormalizePrice(isBuy?entry-pad:entry+pad);
}

//=========================================================================
//  HISTORICAL FILTER CHECKS (for simulation, using runtime toggles)
//=========================================================================
bool HistCheckAtr(double orbRange,datetime orbStart,string &reason)
{
   if(!g_rtFilterAtr)return true;
   double atr=HistDailyAtr(orbStart,InpAtrPeriod);
   if(atr<=0)return true;
   double pct=(orbRange/atr)*100.0;
   if(pct<InpMinRangeAtrPct){reason="ATR<"+DoubleToString(InpMinRangeAtrPct,0)+"%";return false;}
   if(pct>InpMaxRangeAtrPct){reason="ATR>"+DoubleToString(InpMaxRangeAtrPct,0)+"%";return false;}
   return true;
}
bool HistCheckVol(double sigVol,double avgVol,string &reason)
{
   if(!g_rtFilterVol)return true;
   if(avgVol<=0)return true;
   if(sigVol<avgVol*g_rtVolumeMultiplier){reason="VOL_LOW";return false;}
   return true;
}

// Return the first breakout that the live operational filters could accept.
// A raw breakout rejected by volume/displacement/FVG does not end the live
// session; the next closed bar is evaluated. Historical drawing must follow
// that same progression instead of discarding the entire day.
bool FindHistOperationalBreakout(datetime from,datetime to,double hi,double lo,
                                 string &dir,datetime &sigT,double &sigC,double &sigH,double &sigL,
                                 double &sigVol,double &preBreakoutAvgVol,
                                 bool &hadRawCandidate,string &lastReject,string &modernDetail,
                                 datetime initialAfterSignalTime=0)
{
   hadRawCandidate=false;lastReject="";modernDetail="";
   datetime afterSignalTime=initialAfterSignalTime;
   int sec=PeriodSeconds(g_rtSignalTf);if(sec<=0)sec=60;
   int maxAttempts=MathMax(1,(int)MathCeil((double)MathMax(0,to-from)/(double)sec)+2);
   for(int attempt=0;attempt<maxAttempts;attempt++)
   {
      if(!FindHistBreakoutAfter(from,to,hi,lo,afterSignalTime,
                                dir,sigT,sigC,sigH,sigL,sigVol,preBreakoutAvgVol))
         return false;
      hadRawCandidate=true;
      afterSignalTime=sigT;
      if(!EntryDirectionAllows(EffectiveOrbDirection(dir)=="BUY"?1:-1))
      {lastReject="ENTRY_DIRECTION";continue;}

      string reason="";
      if(!HistCheckVol(sigVol,preBreakoutAvgVol,reason))
      {
         lastReject=reason+" signal="+FmtTime(sigT)
            +" sigVol="+DoubleToString(sigVol,0)
            +" preAvg="+DoubleToString(preBreakoutAvgVol,0);
         continue;
      }

      string candidateModern="";
      if(!ModernFilterAllows(from,to,g_rtSignalTf,sigT,dir,g_rtDisplacement,g_rtFvgMode,reason,candidateModern))
      {
         lastReject=reason+" "+candidateModern+" signal="+FmtTime(sigT);
         continue;
      }
      modernDetail=candidateModern;
      return true;
   }
   lastReject="candidate_guard_exhausted";
   return false;
}
bool HistCheckDay(int dow,string &reason)
{
   if(!g_rtFilterDay)return true;
   bool ok=false;
   if(dow==1&&InpTradeMonday)ok=true;if(dow==2&&InpTradeTuesday)ok=true;
   if(dow==3&&InpTradeWednesday)ok=true;if(dow==4&&InpTradeThursday)ok=true;
   if(dow==5&&InpTradeFriday)ok=true;
   if(!ok){reason="DAY";return false;}
   return true;
}

void AppendOrbWindowSignal(OrbWindowSignal &signals[],datetime sigT,string rawDir,string reason,
                           double sigC,double sigH,double sigL)
{
   if(StringFind(reason,"OF_")==0)return;
   int n=ArraySize(signals);
   ArrayResize(signals,n+1,256);
   signals[n].signalTime=sigT;signals[n].availableTime=OrbSignalAvailableTime(sigT);
   signals[n].rawDirection=rawDir;signals[n].executionDirection=EffectiveOrbDirection(rawDir);
   signals[n].reason=reason;signals[n].signalClose=sigC;signals[n].signalHigh=sigH;signals[n].signalLow=sigL;
   signals[n].drawOnChart=false;
}

void AppendOrbAcceptedSignal(OrbWindowSignal &signals[],datetime sigT,datetime entryT,string rawDir,
                              double sigC,double sigH,double sigL)
{
   int n=ArraySize(signals);
   ArrayResize(signals,n+1,256);
   signals[n].signalTime=sigT;
   signals[n].availableTime=MathMax(OrbSignalAvailableTime(sigT),entryT);
   signals[n].rawDirection=rawDir;
   signals[n].executionDirection=EffectiveOrbDirection(rawDir);
   signals[n].reason="ACCEPTED";
   signals[n].signalClose=sigC;signals[n].signalHigh=sigH;signals[n].signalLow=sigL;
   signals[n].drawOnChart=false;
}

void AppendOrbOperationalSignal(OrbWindowSignal &signals[],datetime sigT,string rawDir,
                                double sigC,double sigH,double sigL)
{
   int n=ArraySize(signals);
   ArrayResize(signals,n+1,256);
   signals[n].signalTime=sigT;
   signals[n].availableTime=OrbSignalAvailableTime(sigT);
   signals[n].rawDirection=rawDir;
   signals[n].executionDirection=EffectiveOrbDirection(rawDir);
   signals[n].reason="OPERATIONAL";
   signals[n].signalClose=sigC;signals[n].signalHigh=sigH;signals[n].signalLow=sigL;
   signals[n].drawOnChart=false;
}

void DrawOrbWindowSignal(const OrbWindowSignal &signal,int index)
{
   if(IsTesterMode()||!signal.drawOnChart)return;
   bool isBuy=(signal.executionDirection=="BUY");
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double candleRange=MathMax(pt,MathAbs(signal.signalHigh-signal.signalLow));
   double pad=MathMax(candleRange*0.35,pt*40.0);
   double arrowPrice=NormalizePrice(isBuy?signal.signalLow-pad:signal.signalHigh+pad);
   string token=StringFormat("%I64d",(long)signal.signalTime)+"_"+IntegerToString(index)+"_"+signal.executionDirection;
   string base=HistoricalObjectRoot()+"WINDOW_"+token+"_";
   string arrowName=base+"ARW";
   if(IsFreshHistoricalBuildObject(arrowName))ObjectCreate(0,arrowName,OBJ_ARROW,0,signal.availableTime,arrowPrice);
   else if(ObjectFind(0,arrowName)<0)ObjectCreate(0,arrowName,OBJ_ARROW,0,signal.availableTime,arrowPrice);
   else ObjectMove(0,arrowName,0,signal.availableTime,arrowPrice);
   ObjectSetInteger(0,arrowName,OBJPROP_ARROWCODE,isBuy?241:242);
   ObjectSetInteger(0,arrowName,OBJPROP_COLOR,clrOrange);
   ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,arrowName,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,arrowName,OBJPROP_HIDDEN,false);
   double textPrice=NormalizePrice(isBuy?arrowPrice-pad*0.55:arrowPrice+pad*0.55);
   string text="WINDOW "+signal.executionDirection+" ["+signal.reason+"]";
   if(signal.rawDirection!=signal.executionDirection)text+=" raw="+signal.rawDirection;
   DrawSignalText(base+"TXT",signal.availableTime,textPrice,text,clrOrange);
}

// Build a visual/exit-only stream of raw ORB signals rejected by the active
// filters. This pass never changes the accepted signal set or its statistics.
int BuildHistoricalWindowSignals(int days,datetime nyMid,OrbWindowSignal &signals[],OrbWindowSignal &acceptedSignals[])
{
   ArrayResize(signals,0);
   ArrayResize(acceptedSignals,0);
   ArrayResize(g_histOperationalSignals,0);
   ArrayResize(g_histDaySnapshots,MathMax(0,days));
   for(int ci=0;ci<ArraySize(g_histDaySnapshots);ci++)
   {
      g_histDaySnapshots[ci].known=false;g_histDaySnapshots[ci].valid=false;
      g_histDaySnapshots[ci].hi=0.0;g_histDaySnapshots[ci].lo=0.0;g_histDaySnapshots[ci].avgVolume=0.0;
      g_histDaySnapshots[ci].orbStart=0;g_histDaySnapshots[ci].orbEnd=0;g_histDaySnapshots[ci].tradeEnd=0;
      g_histDaySnapshots[ci].usedBars=0;
      g_histDaySnapshots[ci].operationalKnown=false;g_histDaySnapshots[ci].operationalFound=false;
      g_histDaySnapshots[ci].operationalHadRawCandidate=false;g_histDaySnapshots[ci].operationalDirection="";
      g_histDaySnapshots[ci].operationalSignalTime=0;g_histDaySnapshots[ci].operationalClose=0.0;
      g_histDaySnapshots[ci].operationalHigh=0.0;g_histDaySnapshots[ci].operationalLow=0.0;
      g_histDaySnapshots[ci].operationalVolume=0.0;g_histDaySnapshots[ci].operationalPreAverageVolume=0.0;
      g_histDaySnapshots[ci].operationalLastReject="";g_histDaySnapshots[ci].operationalModernDetail="";
   }
   int rejectedRaw=0;
   ulong lastPrepUiMs=GetTickCount64();
   for(int back=days-1;back>=0;back--)
   {
      int prepDone=days-back;
      g_histAuditProcessedDays=prepDone;
      g_histAuditProgressPct=20.0*(double)prepDone/(double)MathMax(1,days);
      g_histAuditStage="PREP";
      ulong prepNowMs=GetTickCount64();
      if(prepNowMs-lastPrepUiMs>=250)
      {
         RenderHistoricalAuditProgress();
         lastPrepUiMs=prepNowMs;
      }
      datetime nyDay=nyMid-back*86400;MqlDateTime daySt;TimeToStruct(nyDay,daySt);
      if(daySt.day_of_week==0||daySt.day_of_week==6)continue;
      double hi=0.0,lo=0.0,avgV=0.0;datetime os=0,oe=0,te=0;int used=0;
      bool orbValid=BuildOrbForNyDate(daySt.year,daySt.mon,daySt.day,hi,lo,os,oe,te,used,avgV);
      if(back>=0&&back<ArraySize(g_histDaySnapshots))
      {
         g_histDaySnapshots[back].known=true;g_histDaySnapshots[back].valid=orbValid;
         if(orbValid)
         {
            g_histDaySnapshots[back].hi=hi;g_histDaySnapshots[back].lo=lo;g_histDaySnapshots[back].avgVolume=avgV;
            g_histDaySnapshots[back].orbStart=os;g_histDaySnapshots[back].orbEnd=oe;
            g_histDaySnapshots[back].tradeEnd=te;g_histDaySnapshots[back].usedBars=used;
         }
      }
      if(!orbValid)continue;
      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_orbHigh=hi;g_orbLow=lo;g_orbStartServer=os;g_orbEndServer=oe;g_tradeEndServer=te;

      string dayReason="",atrReason="";
      bool dayAllowed=HistCheckDay(daySt.day_of_week,dayReason);
      bool atrAllowed=HistCheckAtr(hi-lo,os,atrReason);
      datetime afterSignalTime=0;
      bool hasAccepted=false;
      datetime acceptedTime=0;
      string acceptedDir="",lastWindowKey="";
      int firstWindowIndex=-1,firstPostTradeReverseIndex=-1,firstPostTradeDispIndex=-1;
      int sec=PeriodSeconds(g_rtSignalTf);if(sec<=0)sec=60;
      int maxAttempts=MathMax(1,(int)MathCeil((double)MathMax(0,te-oe)/(double)sec)+2);
      MqlRates daySignalRates[];
      int daySignalCount=CopyRates(_Symbol,g_rtSignalTf,oe,te,daySignalRates);
      int scanFromIndex=0;
      for(int attempt=0;attempt<maxAttempts;attempt++)
      {
         string dir;datetime sigT;double sigC,sigH,sigL,sigVol,preAvgVol;
         if(!FindHistBreakoutAfterRates(daySignalRates,daySignalCount,oe,te,hi,lo,afterSignalTime,scanFromIndex,
                                       dir,sigT,sigC,sigH,sigL,sigVol,preAvgVol))break;
         afterSignalTime=sigT;
         string reason="",detail="";
         bool allowed=true;
         if(!dayAllowed){allowed=false;reason="DAY";}
         else if(!atrAllowed){allowed=false;reason=atrReason;}
         else if(!HistCheckVol(sigVol,preAvgVol,reason))allowed=false;
         else if(!ModernFilterAllows(oe,te,g_rtSignalTf,sigT,dir,g_rtDisplacement,g_rtFvgMode,reason,detail))allowed=false;

         datetime entryT=sigT;double entryPrice=sigC;string entryDetail="";
         if(allowed&&!ResolveHistoricalEntry(g_rtEntryMode,dir,sigT,sigC,hi,lo,te,entryT,entryPrice,entryDetail))
         {allowed=false;reason="ENTRY_"+EntryModeLabel(g_rtEntryMode);}

         RegimeV3Snapshot snapshot;int bucket=-1;
         if(allowed)
         {
            bucket=OrbRegimeBucketAt(sigT,snapshot);
            if(!OrbRegimeAllowed(bucket)){allowed=false;reason="REGIME_"+OrbRegimeShortName(bucket);}
         }
         if(allowed)
         {
            int rfIndex=-1;string rfRule="",rfDetail="";
            if(!OrbRfEvaluate(dir,snapshot,rfIndex,rfRule,rfDetail))
            {allowed=false;reason="RF_"+OrbRfRuleCode(rfIndex);}
         }
         if(allowed)
         {
            string execDir=EffectiveOrbDirection(dir);
            bool sourceIsBuy=(dir=="BUY"),isBuy=(execDir=="BUY");
            double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
            double rawSl=sourceIsBuy?(lo-MathMax(0.0,InpSlBufferPoints)*pt):(hi+MathMax(0.0,InpSlBufferPoints)*pt);
            double sl=0.0,risk=0.0;string geometryDetail="";
            if(!ResolveExecutionStop(sourceIsBuy,isBuy,entryPrice,rawSl,sl,risk,geometryDetail))
            {allowed=false;reason="GEOMETRY";}
         }

         string execDir=EffectiveOrbDirection(dir);
         if(allowed)
         {
            if(!hasAccepted)
            {
               hasAccepted=true;acceptedTime=OrbSignalAvailableTime(sigT);acceptedDir=execDir;
               AppendOrbAcceptedSignal(acceptedSignals,sigT,entryT,dir,sigC,sigH,sigL);
            }
            lastWindowKey="";
            continue;
         }
         rejectedRaw++;
         string windowKey=execDir+"|"+reason;
         if(windowKey==lastWindowKey)continue;
         AppendOrbWindowSignal(signals,sigT,dir,reason,sigC,sigH,sigL);
         int windowIndex=ArraySize(signals)-1;
         if(firstWindowIndex<0)firstWindowIndex=windowIndex;
         bool afterAccepted=(hasAccepted&&OrbSignalAvailableTime(sigT)>acceptedTime);
         if(afterAccepted&&execDir!=acceptedDir&&firstPostTradeReverseIndex<0)
            firstPostTradeReverseIndex=windowIndex;
         if(afterAccepted&&execDir==acceptedDir&&reason=="DISP_BLOCK"&&firstPostTradeDispIndex<0)
            firstPostTradeDispIndex=windowIndex;
         lastWindowKey=windowKey;
      }
      // ORB is one-trade-per-day. Therefore the visual window stream must
      // also contain at most one event per day, never one event per bar.
      // Keep the complete de-duplicated stream internally for lifecycle exits,
      // but draw at most one WINDOW per ORB day. With both exit toggles held,
      // never force a post-trade marker behind every accepted trade. If an exit
      // toggle is active, visualize the earliest event that actually exits.
      int drawIndex=firstWindowIndex;
      int reverseExitIndex=g_rtFilteredWindowReverseExit?firstPostTradeReverseIndex:-1;
      int dispExitIndex=g_rtPostTradeDispBlockExit?firstPostTradeDispIndex:-1;
      if(reverseExitIndex>=0&&dispExitIndex>=0)drawIndex=MathMin(reverseExitIndex,dispExitIndex);
      else if(reverseExitIndex>=0)drawIndex=reverseExitIndex;
      else if(dispExitIndex>=0)drawIndex=dispExitIndex;
      if(drawIndex>=0&&drawIndex<ArraySize(signals))signals[drawIndex].drawOnChart=true;
      g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
   }
   return rejectedRaw;
}

// Processes exactly one ORB day. Keeping this unit bounded lets OnTimer return
// between history chunks so chart clicks and live risk management stay active.
struct OrbPrepMemoValue
{
   OrbHistoricalDaySnapshot snapshot;
   int rejected;
   OrbWindowSignal a0[];
   OrbWindowSignal a1[];
   OrbWindowSignal a2[];
   OrbWindowSignal a3[];
   OrbWindowSignal a4[];
};
AuditMemoIndex g_orbPrepMemo;
OrbPrepMemoValue g_orbPrepMemoValues[];
long g_orbPrepMemoHits=0;

int ProcessHistoricalPrepDay(const int back)
{
   if(back<0||back>=ArraySize(g_histDaySnapshots))return ProcessHistoricalPrepDayUncached(back);
   string epoch=LabEngineIdentity()+OrbReplayDataEpoch()+"|"+(string)g_histNasCacheClosedBar+"|"+(string)g_histNasCacheFrom
      +"|"+(string)g_histNasCacheEventFrom+"|"+(string)SeriesInfoInteger(_Symbol,g_rtSignalTf,SERIES_BARS_COUNT)
      +"|"+(string)SeriesInfoInteger(_Symbol,g_rtSignalTf,SERIES_FIRSTDATE);
   g_orbPrepMemo.Reset(epoch);
   string key=(string)(g_histRunNyMid-back*86400)+"|"+(string)g_orbRfEnabled;
   key+="|MAEXIT_FILTERED3="+(string)g_maReverseExit+","+(string)g_maReverseWait;
   key+="|g_rtFilterAtr="+(string)g_rtFilterAtr;
   key+=McOfIdentity();
   key+="|g_rtFilterVol="+(string)g_rtFilterVol;
   key+="|g_rtFilterDay="+(string)g_rtFilterDay;
   key+="|g_rtFilteredWindowReverseExit="+(string)g_rtFilteredWindowReverseExit;
   key+="|g_rtPostTradeDispBlockExit="+(string)g_rtPostTradeDispBlockExit;
   key+="|g_rtEntryWindow="+(string)g_rtEntryWindow;
   key+="|g_rtEntryWindowStartMin="+(string)g_rtEntryWindowStartMin;
   key+="|g_rtEntryWindowEndMin="+(string)g_rtEntryWindowEndMin;
   key+="|g_rtTimeExit="+(string)g_rtTimeExit;
   key+="|g_rtDisplacement="+(string)g_rtDisplacement;
   key+="|g_rtFvgMode="+(string)g_rtFvgMode;
   key+="|g_rtExitMode="+(string)g_rtExitMode;
   key+="|g_rtEntryMode="+(string)g_rtEntryMode;
   key+="|g_rtTargetMode="+(string)g_rtTargetMode;
   key+="|g_rtBEOnTp1="+(string)g_rtBEOnTp1;
   key+="|g_rtEaEnabled="+(string)g_rtEaEnabled;
   key+="|g_rtInvertMode="+(string)g_rtInvertMode;
   if(g_rtInvertMode)key+="|INV_LEVEL_SWAP_1";
   key+="|entryDirection="+(string)g_entryDirection+"|dailyLoss="+(string)g_dailyMaxLosses+"|dailyWin="+(string)g_dailyTargetWins+"|dailyStart="+(string)g_dailyStartMinute;
   key+="|g_rtAdvancedReverse="+(string)g_rtAdvancedReverse;
   key+="|g_rtAdvancedReverseMaxCostPct="+AuditMemoPrice(g_rtAdvancedReverseMaxCostPct);
   key+="|g_rtUtcMidnightSession="+(string)g_rtUtcMidnightSession;
   key+="|g_rtNasConfirmation="+(string)g_rtNasConfirmation;
   key+="|g_rtNasStateGate="+(string)g_rtNasStateGate;
   key+="|g_rtNasExitOnOppositeSignal="+(string)g_rtNasExitOnOppositeSignal;
   key+="|g_rtNasAdditionalExit="+(string)g_rtNasAdditionalExit;
   key+="|g_rtAdvancedAuditEngine="+(string)g_rtAdvancedAuditEngine;
   key+="|g_rtNasSensitivity="+(string)g_rtNasSensitivity;
   key+="|g_rtNasVolumeFilter="+(string)g_rtNasVolumeFilter;
   key+="|g_rtNasVolumeMultiplier="+AuditMemoPrice(g_rtNasVolumeMultiplier);
   key+="|g_rtNasFlowVolumeFilter="+(string)g_rtNasFlowVolumeFilter;
   key+="|g_rtNasFlowVolumeMultiplier="+AuditMemoPrice(g_rtNasFlowVolumeMultiplier);
   key+="|g_rtNasActiveSignalLookbackMinutes="+(string)g_rtNasActiveSignalLookbackMinutes;
   key+="|g_rtNasOppositeExitWaitMinutes="+(string)g_rtNasOppositeExitWaitMinutes;
   key+="|g_rtRiskPerTradePct="+AuditMemoPrice(g_rtRiskPerTradePct);
   key+="|g_rtVolumeMultiplier="+AuditMemoPrice(g_rtVolumeMultiplier);
    key+="|g_rtSignalTf="+(string)g_rtSignalTf;
    // MA signal mode is part of the candidate stream itself.  Omitting these
    // fields lets a completed ORB-day memo from one kernel be replayed after
    // switching to another kernel, producing identical audit results.
    key+="|ma_audit_schema=events1|ma_kernel="+MC_KERNEL_REVISION+"|ma_h4seed="+(string)McHistorySeed(_Symbol,PERIOD_H4)+"|ma_seed="+(string)McHistorySeed(_Symbol,g_rtSignalTf)+"|ma_mode="+(string)g_rtMaCrossMode;
    key+="|ma_pair="+(string)g_rtMaCrossPair;
    key+="|ma_fast="+IntegerToString(MathMax(1,InpMaFastLength));
    key+="|ma_medium="+IntegerToString(MathMax(1,InpMaMediumLength));
    key+="|ma_slow="+IntegerToString(MathMax(2,InpMaSlowLength));
    key+="|g_rtDelayMin="+(string)g_rtDelayMin;
   key+="|g_rtUseDelay="+(string)g_rtUseDelay;
   key+="|g_rtTargetLeg="+(string)g_rtTargetLeg;
   if(g_rtTargetLeg==(int)ORB_TARGET_CUSTOM)key+="|customR="+DoubleToString(g_rtCustomR,8);
   key+="|g_rtHalfBeLeg="+(string)g_rtHalfBeLeg;
   key+="|g_rtExitTrailStartLeg="+(string)g_rtExitTrailStartLeg;
   key+="|g_rtExitEmaPeriod="+(string)g_rtExitEmaPeriod;
   key+="|g_rtExitAtrMultiplier="+AuditMemoPrice(g_rtExitAtrMultiplier);
   key+="|g_rtSlDistancePct="+AuditMemoPrice(g_rtSlDistancePct);
   key+="|g_rtPipSlMode="+(string)g_rtPipSlMode;
   key+="|g_rtPipSlPips="+AuditMemoPrice(g_rtPipSlPips);
   for(int r=0;r<ORB_REGIME_COUNT;r++)key+="|macro="+(string)g_regimeAllowed[r];
   for(int r=0;r<ORB_RF_COUNT;r++)key+="|rf="+(string)g_orbRfBlocked[r];
   int cached=g_mcOf.mode!=0?-1:g_orbPrepMemo.Find(key);
   if(cached>=0)
   {
      g_histDaySnapshots[back]=g_orbPrepMemoValues[cached].snapshot;
      int base0=ArraySize(g_histWindowSignals),count0=ArraySize(g_orbPrepMemoValues[cached].a0);
      ArrayResize(g_histWindowSignals,base0+count0,256);
      for(int j=0;j<count0;j++)g_histWindowSignals[base0+j]=g_orbPrepMemoValues[cached].a0[j];
      int base1=ArraySize(g_histAcceptedSignals),count1=ArraySize(g_orbPrepMemoValues[cached].a1);
      ArrayResize(g_histAcceptedSignals,base1+count1,256);
      for(int j=0;j<count1;j++)g_histAcceptedSignals[base1+j]=g_orbPrepMemoValues[cached].a1[j];
      int base2=ArraySize(g_histOperationalSignals),count2=ArraySize(g_orbPrepMemoValues[cached].a2);
      ArrayResize(g_histOperationalSignals,base2+count2,256);
      for(int j=0;j<count2;j++)g_histOperationalSignals[base2+j]=g_orbPrepMemoValues[cached].a2[j];
      int base3=ArraySize(g_regimeReferenceSignals),count3=ArraySize(g_orbPrepMemoValues[cached].a3);
      ArrayResize(g_regimeReferenceSignals,base3+count3,256);
      for(int j=0;j<count3;j++)g_regimeReferenceSignals[base3+j]=g_orbPrepMemoValues[cached].a3[j];
      int base4=ArraySize(g_regimeReferenceWindows),count4=ArraySize(g_orbPrepMemoValues[cached].a4);
      ArrayResize(g_regimeReferenceWindows,base4+count4,256);
      for(int j=0;j<count4;j++)g_regimeReferenceWindows[base4+j]=g_orbPrepMemoValues[cached].a4[j];
      g_orbPrepMemoHits++;return g_orbPrepMemoValues[cached].rejected;
   }
   int before0=ArraySize(g_histWindowSignals);
   int before1=ArraySize(g_histAcceptedSignals);
   int before2=ArraySize(g_histOperationalSignals);
   int before3=ArraySize(g_regimeReferenceSignals);
   int before4=ArraySize(g_regimeReferenceWindows);
   int rejected=ProcessHistoricalPrepDayUncached(back);
   OrbHistoricalDaySnapshot snapshot=g_histDaySnapshots[back];
   // Never cache a forming session or a missing-data/invalid day. No-signal
   // completed sessions are reusable, but their full prepared context is kept.
   if(g_mcOf.mode==0&&snapshot.known&&snapshot.valid&&snapshot.operationalKnown&&snapshot.tradeEnd>0
      &&snapshot.tradeEnd<iTime(_Symbol,PERIOD_M1,0)
      &&StringFind(epoch,LabEngineIdentity()+OrbReplayDataEpoch()+"|")==0)
   {
      int slot=g_orbPrepMemo.Add(key);
      if(slot>=0)
      {
         if(ArraySize(g_orbPrepMemoValues)<=slot)ArrayResize(g_orbPrepMemoValues,slot+1,64);
         g_orbPrepMemoValues[slot].snapshot=snapshot;g_orbPrepMemoValues[slot].rejected=rejected;
         ArrayResize(g_orbPrepMemoValues[slot].a0,ArraySize(g_histWindowSignals)-before0);
         for(int j=before0;j<ArraySize(g_histWindowSignals);j++)g_orbPrepMemoValues[slot].a0[j-before0]=g_histWindowSignals[j];
         ArrayResize(g_orbPrepMemoValues[slot].a1,ArraySize(g_histAcceptedSignals)-before1);
         for(int j=before1;j<ArraySize(g_histAcceptedSignals);j++)g_orbPrepMemoValues[slot].a1[j-before1]=g_histAcceptedSignals[j];
         ArrayResize(g_orbPrepMemoValues[slot].a2,ArraySize(g_histOperationalSignals)-before2);
         for(int j=before2;j<ArraySize(g_histOperationalSignals);j++)g_orbPrepMemoValues[slot].a2[j-before2]=g_histOperationalSignals[j];
         ArrayResize(g_orbPrepMemoValues[slot].a3,ArraySize(g_regimeReferenceSignals)-before3);
         for(int j=before3;j<ArraySize(g_regimeReferenceSignals);j++)g_orbPrepMemoValues[slot].a3[j-before3]=g_regimeReferenceSignals[j];
         ArrayResize(g_orbPrepMemoValues[slot].a4,ArraySize(g_regimeReferenceWindows)-before4);
         for(int j=before4;j<ArraySize(g_regimeReferenceWindows);j++)g_orbPrepMemoValues[slot].a4[j-before4]=g_regimeReferenceWindows[j];
      }
   }
   return rejected;
}

int ProcessHistoricalPrepDayUncached(const int back)
{
   datetime nyDay=g_histRunNyMid-back*86400;MqlDateTime daySt;TimeToStruct(nyDay,daySt);
   if(daySt.day_of_week==0||daySt.day_of_week==6)return 0;
   double hi,lo,avgV;datetime os,oe,te;int used;
   bool orbValid=BuildOrbForNyDate(daySt.year,daySt.mon,daySt.day,hi,lo,os,oe,te,used,avgV);
   if(back>=0&&back<ArraySize(g_histDaySnapshots))
   {
      g_histDaySnapshots[back].known=true;g_histDaySnapshots[back].valid=orbValid;
      if(orbValid)
      {
         g_histDaySnapshots[back].hi=hi;g_histDaySnapshots[back].lo=lo;g_histDaySnapshots[back].avgVolume=avgV;
         g_histDaySnapshots[back].orbStart=os;g_histDaySnapshots[back].orbEnd=oe;
         g_histDaySnapshots[back].tradeEnd=te;g_histDaySnapshots[back].usedBars=used;
      }
   }
   if(!orbValid)return 0;

   double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
   g_orbHigh=hi;g_orbLow=lo;g_orbStartServer=os;g_orbEndServer=oe;g_tradeEndServer=te;
   string dayReason="",atrReason="";
   bool dayAllowed=HistCheckDay(daySt.day_of_week,dayReason);
   bool atrAllowed=HistCheckAtr(hi-lo,os,atrReason);
   datetime afterSignalTime=0;
   bool hasAccepted=false;
   bool hasOperational=false;
   bool referenceAccepted=false;
   bool referenceReverseFound=false,referenceDispFound=false,executionPrepDone=false;
   datetime referenceTime=0;string referenceDir="";
   bool hadRawCandidate=false;
   string operationalLastReject="";
   datetime acceptedTime=0;
   string acceptedDir="",lastWindowKey="";
   int firstWindowIndex=-1,firstPostTradeReverseIndex=-1,firstPostTradeDispIndex=-1;
   int sec=PeriodSeconds(g_rtSignalTf);if(sec<=0)sec=60;
   int maxAttempts=MathMax(1,(int)MathCeil((double)MathMax(0,te-oe)/(double)sec)+2);
   MqlRates daySignalRates[];
   int daySignalCount=CopyRates(_Symbol,g_rtSignalTf,oe,te,daySignalRates);
   int scanFromIndex=0,rejectedRaw=0;
   for(int attempt=0;attempt<maxAttempts;attempt++)
   {
      string dir="";datetime sigT=0;double sigC=0.0,sigH=0.0,sigL=0.0,sigVol=0.0,preAvgVol=0.0;
      if(!FindHistBreakoutAfterRates(daySignalRates,daySignalCount,oe,te,hi,lo,afterSignalTime,scanFromIndex,
                                    dir,sigT,sigC,sigH,sigL,sigVol,preAvgVol))break;
      hadRawCandidate=true;
      afterSignalTime=sigT;
      string reason="",detail="";
      bool allowed=true;
      if(!dayAllowed){allowed=false;reason="DAY";}
      else if(!atrAllowed){allowed=false;reason=atrReason;}
      else if(!HistCheckVol(sigVol,preAvgVol,reason))allowed=false;
      else if(!ModernFilterAllows(oe,te,g_rtSignalTf,sigT,dir,g_rtDisplacement,g_rtFvgMode,reason,detail))allowed=false;

      // This is the exact universe used by FindNextHistoricalSignalAfter:
      // day/ATR/volume/modern accepted, before entry/regime/RF/geometry gates.
      if(allowed&&!hasOperational)
      {
         AppendOrbOperationalSignal(g_histOperationalSignals,sigT,dir,sigC,sigH,sigL);
         hasOperational=true;
         if(back>=0&&back<ArraySize(g_histDaySnapshots))
         {
            g_histDaySnapshots[back].operationalFound=true;
            g_histDaySnapshots[back].operationalDirection=dir;
            g_histDaySnapshots[back].operationalSignalTime=sigT;
            g_histDaySnapshots[back].operationalClose=sigC;
            g_histDaySnapshots[back].operationalHigh=sigH;
            g_histDaySnapshots[back].operationalLow=sigL;
            g_histDaySnapshots[back].operationalVolume=sigVol;
            g_histDaySnapshots[back].operationalPreAverageVolume=preAvgVol;
            g_histDaySnapshots[back].operationalModernDetail=detail;
         }
      }
      else if(!allowed&&!hasOperational)
         operationalLastReject=reason+" "+detail+" signal="+FmtTime(sigT);

      datetime entryT=sigT;double entryPrice=sigC;string entryDetail="";
      if(allowed&&!ResolveHistoricalEntry(g_rtEntryMode,dir,sigT,sigC,hi,lo,te,entryT,entryPrice,entryDetail))
      {allowed=false;reason="ENTRY_"+EntryModeLabel(g_rtEntryMode);}

      // Reference exits must not change when the macro/RF switches change.
      // Build the independent diagnostic stream before either allow-list.
      if(allowed&&!referenceAccepted)
      {
         bool sb=(dir=="BUY"),eb=(EffectiveOrbDirection(dir)=="BUY");
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
         double rs=sb?lo-MathMax(0.0,InpSlBufferPoints)*pt:hi+MathMax(0.0,InpSlBufferPoints)*pt;
         double ds=0.0,dr=0.0;string gd="";
         if(ResolveExecutionStop(sb,eb,entryPrice,rs,ds,dr,gd))
         {
            AppendOrbAcceptedSignal(g_regimeReferenceSignals,sigT,entryT,dir,sigC,sigH,sigL);
            referenceAccepted=true;
            referenceTime=OrbSignalAvailableTime(sigT);referenceDir=EffectiveOrbDirection(dir);
         }
      }
      if(!allowed&&referenceAccepted&&OrbSignalAvailableTime(sigT)>referenceTime)
      {
         bool rx=g_rtFilteredWindowReverseExit&&!referenceReverseFound&&EffectiveOrbDirection(dir)!=referenceDir;
         bool dx=g_rtPostTradeDispBlockExit&&!referenceDispFound&&EffectiveOrbDirection(dir)==referenceDir&&reason=="DISP_BLOCK";
         if(rx||dx)AppendOrbWindowSignal(g_regimeReferenceWindows,sigT,dir,reason,sigC,sigH,sigL);
         if(rx)referenceReverseFound=true;if(dx)referenceDispFound=true;
      }
      bool referenceDone=referenceAccepted&&(!g_rtFilteredWindowReverseExit||referenceReverseFound)&&(!g_rtPostTradeDispBlockExit||referenceDispFound);
      if(executionPrepDone){if(referenceDone)break;continue;}

      RegimeV3Snapshot snapshot;int bucket=-1;
      if(allowed)
      {
         bucket=OrbRegimeBucketAt(sigT,snapshot);
         if(!OrbRegimeAllowed(bucket)){allowed=false;reason="REGIME_"+OrbRegimeShortName(bucket);}
      }
      if(allowed)
      {
         int rfIndex=-1;string rfRule="",rfDetail="";
         if(!OrbRfEvaluate(dir,snapshot,rfIndex,rfRule,rfDetail))
         {allowed=false;reason="RF_"+OrbRfRuleCode(rfIndex);}
      }
      string execDir=EffectiveOrbDirection(dir);
      if(allowed)
      {
         bool sourceIsBuy=(dir=="BUY"),isBuy=(execDir=="BUY");
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
         double rawSl=sourceIsBuy?(lo-MathMax(0.0,InpSlBufferPoints)*pt):(hi+MathMax(0.0,InpSlBufferPoints)*pt);
         double sl=0.0,risk=0.0;string geometryDetail="";
         if(!ResolveExecutionStop(sourceIsBuy,isBuy,entryPrice,rawSl,sl,risk,geometryDetail))
         {allowed=false;reason="GEOMETRY";}
      }
      if(allowed)
      {
         if(!hasAccepted)
         {
            hasAccepted=true;acceptedTime=OrbSignalAvailableTime(sigT);acceptedDir=execDir;
            AppendOrbAcceptedSignal(g_histAcceptedSignals,sigT,entryT,dir,sigC,sigH,sigL);
         }
         // ORB owns at most one entry per day. Once the accepted entry exists,
         // later accepted candidates cannot alter either execution or audit.
         // Continue only when a filtered post-entry event is actually needed
         // by one of the optional exit engines.
         if(!g_rtFilteredWindowReverseExit&&!g_rtPostTradeDispBlockExit)break;
         lastWindowKey="";
         continue;
      }
      rejectedRaw++;
      bool afterAccepted=(hasAccepted&&OrbSignalAvailableTime(sigT)>acceptedTime);
      bool reverseCandidate=(afterAccepted&&g_rtFilteredWindowReverseExit
         &&execDir!=acceptedDir&&firstPostTradeReverseIndex<0);
      bool dispCandidate=(afterAccepted&&g_rtPostTradeDispBlockExit
         &&execDir==acceptedDir&&reason=="DISP_BLOCK"&&firstPostTradeDispIndex<0);
      bool visualCandidate=(!hasAccepted&&firstWindowIndex<0);
      if(visualCandidate||reverseCandidate||dispCandidate)
      {
         AppendOrbWindowSignal(g_histWindowSignals,sigT,dir,reason,sigC,sigH,sigL);
         int windowIndex=ArraySize(g_histWindowSignals)-1;
         if(visualCandidate)firstWindowIndex=windowIndex;
         if(reverseCandidate)firstPostTradeReverseIndex=windowIndex;
         if(dispCandidate)firstPostTradeDispIndex=windowIndex;
      }
      // After entry, stop as soon as every enabled filtered-exit engine has
      // found its first causal event. No later bar can win that race.
      if(hasAccepted
         &&(!g_rtFilteredWindowReverseExit||firstPostTradeReverseIndex>=0)
         &&(!g_rtPostTradeDispBlockExit||firstPostTradeDispIndex>=0))
      {if(referenceDone)break;executionPrepDone=true;}
   }
   int drawIndex=firstWindowIndex;
   int reverseExitIndex=g_rtFilteredWindowReverseExit?firstPostTradeReverseIndex:-1;
   int dispExitIndex=g_rtPostTradeDispBlockExit?firstPostTradeDispIndex:-1;
   if(reverseExitIndex>=0&&dispExitIndex>=0)drawIndex=MathMin(reverseExitIndex,dispExitIndex);
   else if(reverseExitIndex>=0)drawIndex=reverseExitIndex;
   else if(dispExitIndex>=0)drawIndex=dispExitIndex;
   if(drawIndex>=0&&drawIndex<ArraySize(g_histWindowSignals))g_histWindowSignals[drawIndex].drawOnChart=true;
   if(back>=0&&back<ArraySize(g_histDaySnapshots))
   {
      g_histDaySnapshots[back].operationalKnown=true;
      g_histDaySnapshots[back].operationalHadRawCandidate=hadRawCandidate;
      g_histDaySnapshots[back].operationalLastReject=operationalLastReject;
   }
   g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
   return rejectedRaw;
}

int FirstOrbSignalAfter(const OrbWindowSignal &signals[],const datetime afterTime)
{
   int lo=0,hi=ArraySize(signals);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if(signals[mid].availableTime<=afterTime)lo=mid+1;
      else hi=mid;
   }
   return lo;
}

bool FindNewDayAcceptedReverseExit(const OrbWindowSignal &signals[],datetime afterTime,string tradeDirection,
                                    datetime limitTime,datetime &exitTime,string &exitDetail)
{
   exitTime=0;exitDetail="";
   if(!g_maReverseExit)return false;
   if(g_maIndependent)
      exitTime=MaKernelExitAt(g_maCrossAuditEvents,OrbSignalAvailableTime(afterTime),tradeDirection=="BUY"?1:-1,
         limitTime,g_maReverseWait,PeriodSeconds(g_rtSignalTf),g_rtInvertMode);
   else
   {
      datetime opened=OrbSignalAvailableTime(afterTime),eligible=opened+(datetime)(g_maReverseWait*60);
      string opposite=tradeDirection=="BUY"?"SELL":"BUY",state="";
      for(int i=FirstOrbSignalAfter(signals,opened);i<ArraySize(signals);i++)
      {
         datetime at=signals[i].availableTime;if(at>limitTime)break;
         string dir=signals[i].executionDirection;
         if(at<=eligible){state=dir;continue;}
         if(state==opposite){exitTime=eligible;break;}
         if(dir==opposite){exitTime=at;break;}
         state=dir;
      }
      if(exitTime==0&&state==opposite&&eligible<=limitTime)exitTime=eligible;
   }
   if(exitTime>0)exitDetail="MA_REVERSE wait="+DurationMinutesText(g_maReverseWait);
   return exitTime>0;
}
bool FindFilteredWindowExit(const OrbWindowSignal &signals[],datetime afterTime,string tradeDirection,
                            bool allowReverse,bool allowSameDisp,
                            datetime &exitTime,string &exitReason,string &exitOutcome)
{
   exitTime=0;exitReason="";exitOutcome="";
   string opposite=(tradeDirection=="BUY"?"SELL":"BUY");
   for(int i=FirstOrbSignalAfter(signals,afterTime);i<ArraySize(signals);i++)
   {
      bool reverseMatch=(allowReverse&&signals[i].executionDirection==opposite);
      bool dispMatch=(allowSameDisp&&signals[i].executionDirection==tradeDirection&&signals[i].reason=="DISP_BLOCK");
      if(!reverseMatch&&!dispMatch)continue;
      exitTime=signals[i].availableTime;
      exitReason=signals[i].reason;
      exitOutcome=dispMatch?"DISP_BLOCK_EXIT":"FILTER_REVERSE_EXIT";
      return true;
   }
   return false;
}

bool FindNextHistoricalSignalAfter(datetime afterTime,datetime limitTime,datetime &nextSig)
{
   nextSig=0;
   if(limitTime<=afterTime)return false;
   int lo=0,hi=ArraySize(g_histOperationalSignals);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if(g_histOperationalSignals[mid].signalTime<=afterTime)lo=mid+1;
      else hi=mid;
   }
   if(lo<ArraySize(g_histOperationalSignals))
   {
      datetime candidate=g_histOperationalSignals[lo].signalTime;
      if(candidate>afterTime&&candidate<limitTime){nextSig=candidate;return true;}
   }
   return false;
}

//=========================================================================
//  HISTORICAL SIGNAL DRAWING WITH SIMULATION
//=========================================================================
int OrbAuditWarmupBars(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_D1)return MathMax(80,InpAtrPeriod+20);
   if(tf==PERIOD_H1||tf==PERIOD_H2||tf==PERIOD_H4)return 2500;
   if(tf==PERIOD_M1)return 200;
   return 500;
}

bool OrbAuditProbeSeries(ENUM_TIMEFRAMES tf,datetime cutoff,int warmupBars,string label,
                         string &detail,bool &maxBarsBlocked)
{
   int sec=PeriodSeconds(tf);if(sec<=0)sec=60;
   datetime now=TimeCurrent();
   datetime requiredFrom=cutoff-(datetime)((long)MathMax(0,warmupBars)*(long)sec);
   if(requiredFrom<1)requiredFrom=1;
   long span=(long)now-(long)requiredFrom;
   long requested=(span+(long)sec-1)/(long)sec+1;
   long maxBars=TerminalInfoInteger(TERMINAL_MAXBARS);
   long tolerance=(long)MathMax(7*86400,sec*10);

   // Fast path for every dashboard recalculation after terminal history has
   // already synchronized. SERIES_FIRSTDATE is O(1); the old Bars+CopyRates
   // probe could rescan millions of bars before the measured audit even began.
   bool synchronized=(bool)SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED);
   long seriesFirst=SeriesInfoInteger(_Symbol,tf,SERIES_FIRSTDATE);
   if(synchronized&&seriesFirst>0&&seriesFirst<=(long)requiredFrom+tolerance)
      return true;

   // Bars(from, now) can synchronously build millions of M1 candles. Request
   // only the old edge; SERIES_BARS_COUNT is sufficient for cap diagnostics.
   int available=(int)SeriesInfoInteger(_Symbol,tf,SERIES_BARS_COUNT);
   MqlRates probe[];
   datetime probeEnd=requiredFrom+(datetime)MathMax(7*86400,sec*10);
   Print("ORB15v3 HISTORY_PROBE_BEGIN tf=",label," need=",TimeToString(requiredFrom,TIME_DATE|TIME_MINUTES),
         " first=",seriesFirst>0?TimeToString((datetime)seriesFirst,TIME_DATE|TIME_MINUTES):"none",
         " bars=",available," max=",maxBars," attempt=",g_histCoverageAttempts);
   ResetLastError();
   int copied=CopyRates(_Symbol,tf,requiredFrom,probeEnd,probe);
   Print("ORB15v3 HISTORY_PROBE_END tf=",label," copied=",copied," error=",GetLastError());
   datetime oldest=0;
   for(int i=0;i<copied;i++)if(oldest==0||probe[i].time<oldest)oldest=probe[i].time;
   bool ready=(copied>0&&oldest>0&&(long)oldest<=(long)requiredFrom+tolerance);

   if(!ready)
   {
      if(detail!="")detail+=" | ";
      detail+=label+" need~"+StringFormat("%I64d",requested)
         +" max="+StringFormat("%I64d",maxBars)
         +" bars="+IntegerToString(MathMax(0,available))
         +" oldest="+(oldest>0?TimeToString(oldest,TIME_DATE):"syncing");
      long nearCap=(long)MathMax(1.0,(double)maxBars*0.90);
      if(maxBars>0&&requested>maxBars&&g_histCoverageAttempts>=3&&available>=nearCap)
         maxBarsBlocked=true;
   }
   return ready;
}

bool EnsureOrbAuditHistoryCoverage(int days,string &detail,bool &hardBlocked)
{
   detail="";hardBlocked=false;
   datetime cutoff=TimeCurrent()-(datetime)((long)MathMax(1,days)*(long)86400);
   ENUM_TIMEFRAMES frames[7];
   string labels[7];
   frames[0]=PERIOD_M1;labels[0]="M1";
   frames[1]=g_rtSignalTf;labels[1]="SIG";
   frames[2]=RuntimeEntryTf();labels[2]="ENTRY";
   frames[3]=PERIOD_D1;labels[3]="D1";
   frames[4]=PERIOD_H1;labels[4]="H1";
   frames[5]=PERIOD_H2;labels[5]="H2";
   frames[6]=PERIOD_H4;labels[6]="H4";

   bool ready=true;
   for(int i=0;i<ArraySize(frames);i++)
   {
      bool duplicate=false;
      for(int j=0;j<i;j++)if(frames[j]==frames[i]){duplicate=true;break;}
      if(duplicate)continue;
      bool maxBarsBlocked=false;
      if(!OrbAuditProbeSeries(frames[i],cutoff,OrbAuditWarmupBars(frames[i]),labels[i],detail,maxBarsBlocked))
      {
         ready=false;
         if(maxBarsBlocked)hardBlocked=true;
      }
   }
   if(!ready&&!hardBlocked&&g_histCoverageAttempts>=6)
   {
      hardBlocked=true;
      detail="Broker/terminal history did not reach the requested cutoff after "
         +IntegerToString(g_histCoverageAttempts)+" attempts | "+detail;
   }
   return ready;
}

void OrbResetHistoricalStats()
{
   AxReset();
   g_maHistSeriesDir=0;g_maHistSeriesCount=0;MaHistoricalCapacityReset();
   g_labHistLastClose=0;
   g_histAuditRunning=false;
   g_histAuditStage="";
   g_histAuditTotalDays=RuntimeHistoricalDays();
   g_histAuditProcessedDays=0;
   g_histAuditProgressPct=0.0;
   g_histTotal=0;g_histWins=0;g_histLosses=0;g_histOpen=0;g_histFlat=0;g_histInvalid=0;
   g_histFirstInvalidReason="";
   g_histStopLossExits=0;g_histNasOppositeExits=0;g_histNewDayReverseExits=0;
   g_histNetR=0.0;g_histWonR=0.0;g_histLostR=0.0;g_histNetMoney=0.0;
   g_histMinCumulativeR=0.0;g_histMinCumulativeMoney=0.0;
   g_histPeakCumulativeR=0.0;g_histMaxPeakDrawdownR=0.0;g_histMaxPeakDrawdownMoney=0.0;
   for(int ri=0;ri<ORB_REGIME_COUNT;ri++){g_regimeWins[ri]=0;g_regimeLosses[ri]=0;}
   for(int rf=0;rf<ORB_RF_COUNT;rf++){g_orbRfWins[rf]=0;g_orbRfLosses[rf]=0;}
   ResetWeekdayAuditStats();
   TCalReset();
}

#include "OrbStrategyMLPipeline.mqh"
#include "OrbStrategyUserMetrics.mqh"

#include "MaCrossEventAudit.mqh"
datetime MaLegacyAuditPositionUntil(const HistResult &sim,datetime runNow,
                                    datetime forcedAt,string forcedOutcome)
{
   if(!sim.valid||sim.outcome=="open")return runNow+1;
   // A reverse signal closes the previous position before its own entry.
   if(forcedAt>0&&sim.outcome==forcedOutcome)return forcedAt;
   return sim.exitTime>0?sim.exitTime:runNow+1;
}

void ProcessHistoricalCalcDay(const int back)
{
      if(back<0||back>=ArraySize(g_histDaySnapshots))return;
      if(LabPolicyEnabled())LabPolicyGeometryAt(g_histDaySnapshots[back].operationalSignalTime);
      MqlDateTime daySt;TimeToStruct(ServerToSessionLocal(g_histDaySnapshots[back].operationalSignalTime),daySt);
      double hi=0.0,lo=0.0,avgV=0.0;datetime os=0,oe=0,te=0;int used=0;
      g_histChecked++;
      bool orbValid=false;
      if(back>=0&&back<ArraySize(g_histDaySnapshots)&&g_histDaySnapshots[back].known)
      {
         orbValid=g_histDaySnapshots[back].valid;
         if(orbValid)
         {
            hi=g_histDaySnapshots[back].hi;lo=g_histDaySnapshots[back].lo;avgV=g_histDaySnapshots[back].avgVolume;
            os=g_histDaySnapshots[back].orbStart;oe=g_histDaySnapshots[back].orbEnd;
            te=g_histDaySnapshots[back].tradeEnd;used=g_histDaySnapshots[back].usedBars;
         }
      }
      else orbValid=BuildOrbForNyDate(daySt.year,daySt.mon,daySt.day,hi,lo,os,oe,te,used,avgV);
      if(!orbValid)
      {
         if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," ORB_FAIL no_data");
         return;
      }

      // Day filter
      string fr="";
      if(!HistCheckDay(daySt.day_of_week,fr)){g_histFiltered++;if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr);return;}
      // Find the first breakout that live processing could actually accept.
      // Rejected raw candidates do not consume the whole trading session.
      string dir="";datetime sigT=0;double sigC=0.0,sigH=0.0,sigL=0.0,sigVol=0.0,preAvgVol=0.0;
      bool hadRawCandidate=false;string operationalReject="",modernDetail="";
      bool operationalFound=false;
      if(back>=0&&back<ArraySize(g_histDaySnapshots)&&g_histDaySnapshots[back].operationalKnown)
      {
         operationalFound=g_histDaySnapshots[back].operationalFound;
         hadRawCandidate=g_histDaySnapshots[back].operationalHadRawCandidate;
         operationalReject=g_histDaySnapshots[back].operationalLastReject;
         if(operationalFound)
         {
            dir=g_histDaySnapshots[back].operationalDirection;
            sigT=g_histDaySnapshots[back].operationalSignalTime;
            sigC=g_histDaySnapshots[back].operationalClose;
            sigH=g_histDaySnapshots[back].operationalHigh;
            sigL=g_histDaySnapshots[back].operationalLow;
            sigVol=g_histDaySnapshots[back].operationalVolume;
            preAvgVol=g_histDaySnapshots[back].operationalPreAverageVolume;
            modernDetail=g_histDaySnapshots[back].operationalModernDetail;
         }
      }
      else
         operationalFound=FindHistOperationalBreakout(oe,te,hi,lo,dir,sigT,sigC,sigH,sigL,sigVol,preAvgVol,
                                      hadRawCandidate,operationalReject,modernDetail);
      if(!operationalFound)
      {
         if(hadRawCandidate)
         {
            g_histFiltered++;
            if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day,
                  " FILTERED_ALL_CANDIDATES ",operationalReject);
         }
         else
            if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," NO_BREAKOUT orbH=",DoubleToString(hi,_Digits)," orbL=",DoubleToString(lo,_Digits));
         return;
      }

      // Preserve raw signals for exits; reject entries when all concurrent slots are occupied.
      if(g_maIndependent&&!MaHistoricalCapacityAllows(OrbSignalAvailableTime(sigT)))
      {g_histFiltered++;return;}
      if(!EntryDirectionAllows(EffectiveOrbDirection(dir)=="BUY"?1:-1)){g_histFiltered++;return;}
      datetime entryT=sigT;
      double entryPrice=sigC;
      string entryDetail="";
      if(!ResolveHistoricalEntry(g_rtEntryMode,dir,sigT,sigC,hi,lo,te,entryT,entryPrice,entryDetail))
      {
         g_histFiltered++;
         if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",entryDetail);
         return;
      }

      if(!g_maIndependent&&OrbSignalAvailableTime(entryT)<g_maAuditPositionUntil)
      {
         g_maAuditHeldCandidates++;
         return;
      }
      if(!DailyQuotaAuditAllows(OrbSignalAvailableTime(entryT))){g_histFiltered++;return;}
      if(!LabHistoricalCooldownAllows(OrbSignalAvailableTime(entryT))){g_histFiltered++;return;}
      RegimeV3Snapshot regimeSnapshot;
      int regimeBucket=OrbRegimeBucketAt(sigT,regimeSnapshot);
      string regimeDetail=OrbRegimeDetail(regimeSnapshot,regimeBucket);
      int rfIndex=-1;string rfRule="",rfDetail="";
      bool rfAllowed=OrbRfEvaluate(dir,regimeSnapshot,rfIndex,rfRule,rfDetail);
      regimeDetail+=" "+rfDetail;

      // Filters classify the raw breakout. The accepted trade geometry uses
      // the effective direction so audit and production remain identical.
      string execDir=EffectiveOrbDirection(dir);
      string invertDetail="raw_dir="+dir+" exec_dir="+execDir+" invert="+(g_rtInvertMode?"1":"0");
      bool isBuy=(execDir=="BUY");
      bool sourceIsBuy=(dir=="BUY");
      double buffer=MathMax(0.0,InpSlBufferPoints)*g_histRunPoint;
      double entry=entryPrice;
      double rawSl=sourceIsBuy?(lo-buffer):(hi+buffer);
      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_orbHigh=hi;g_orbLow=lo;g_orbStartServer=os;g_orbEndServer=oe;g_tradeEndServer=te;
      double sl=0.0,risk=0.0;string geometryDetail="";
      if(!ResolveExecutionStop(sourceIsBuy,isBuy,entry,rawSl,sl,risk,geometryDetail))
      {
         g_histFiltered++;
         g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
         if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST geometry blocked ",geometryDetail," signal=",FmtTime(sigT));
         return;
      }
      invertDetail+=" "+geometryDetail;
      if(g_maIndependent&&OrbRegimeAllowed(regimeBucket)&&rfAllowed)
      {
         string independentReason="";
         if(!MaIndependentShape(independentReason)
            ||!MaHistoricalCapacityAllows(OrbSignalAvailableTime(entryT)))
         {
            g_lastExecStatus=independentReason;g_histFiltered++;
            g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
            return;
         }
      }
      double r1v=MathMax(0.1,InpTp1R),r2v=MathMax(0.1,InpTp2R),r3v=MathMax(0.1,InpTp3R);
      double tp1=NormalizePrice(isBuy?entry+risk*r1v:entry-risk*r1v);
      double tp2=NormalizePrice(isBuy?entry+risk*r2v:entry-risk*r2v);
      double tp3=NormalizePrice(isBuy?entry+risk*r3v:entry-risk*r3v);
      double tp4=NormalizePrice(isBuy?entry+risk*LegR(4):entry-risk*LegR(4));
      double tp5=NormalizePrice(isBuy?entry+risk*LegR(5):entry-risk*LegR(5));
      double tp6=NormalizePrice(isBuy?entry+risk*LegR(6):entry-risk*LegR(6));

      datetime simEnd=te;
      datetime filteredWindowExitAt=0;string filteredWindowExitReason="",filteredWindowExitOutcome="";
      if(g_rtFilteredWindowReverseExit||g_rtPostTradeDispBlockExit)
         FindFilteredWindowExit(g_histWindowSignals,entryT,execDir,g_rtFilteredWindowReverseExit,g_rtPostTradeDispBlockExit,
            filteredWindowExitAt,filteredWindowExitReason,filteredWindowExitOutcome);
      datetime nasOppositeExitAt=0,nasOppositeBar=0;double nasOppositeClose=0.0;string nasOppositeDetail="";
      bool anyNasExit=RuntimeNasExitEnabled();
      datetime nasSearchEnd=g_histRunNow;
      if(anyNasExit)
         FindNasOppositeExitWithGrace(execDir=="BUY"?1:-1,OrbSignalAvailableTime(entryT),nasSearchEnd,
            nasOppositeBar,nasOppositeExitAt,nasOppositeClose,nasOppositeDetail);
      datetime forcedExitAt=filteredWindowExitAt;string forcedExitOutcome=filteredWindowExitOutcome;
      if(nasOppositeExitAt>0&&(forcedExitAt<=0||nasOppositeExitAt<forcedExitAt))
      {
         forcedExitAt=nasOppositeExitAt;
         forcedExitOutcome=g_rtNasAdditionalExit?"NAS_ADDITIONAL_EXIT":"NAS_OPPOSITE_EXIT";
      }
      datetime newDayReverseExitAt=0;string newDayReverseDetail="";
      FindNewDayAcceptedReverseExit(g_histAcceptedSignals,entryT,execDir,g_histRunNow,newDayReverseExitAt,newDayReverseDetail);
      if(newDayReverseExitAt>0&&(forcedExitAt<=0||newDayReverseExitAt<forcedExitAt))
      {forcedExitAt=newDayReverseExitAt;forcedExitOutcome="MA_REVERSE_EXIT";}
      // Engine rule/holding exits are merged by tick replay after the actual
      // entry fill is known, not relative to the planned candle boundary.
   HistResult sim=OrbMemoLifecycle(entryT,te,g_histRunNow,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,RuntimeHalfBeLeg(),simEnd,
            forcedExitAt,forcedExitOutcome);
      if(!TCalAllows(ServerToSessionLocal(AxEntryAt(sim.entryTime,OrbSignalAvailableTime(entryT)))))
      {
         g_histFiltered++;
         g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
         return;
      }
   if(sim.invalidReason=="INVERSE_GAP_BLOCK"||sim.invalidReason=="LAB_QUOTE_BLOCK")
   {
      g_histFiltered++;
      g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
      return;
   }
#ifdef MA_EVENT_PROBE
      Print("REPLAY ",TimeToString(entryT)," valid=",sim.valid," outcome=",sim.outcome," reason=",sim.invalidReason," exit=",TimeToString(sim.exitTime)," forced=",TimeToString(forcedExitAt));
#endif
      datetime referenceExit=0;string referenceReason="",referenceOutcome="";
      if(g_rtFilteredWindowReverseExit||g_rtPostTradeDispBlockExit)
         FindFilteredWindowExit(g_regimeReferenceWindows,entryT,execDir,g_rtFilteredWindowReverseExit,g_rtPostTradeDispBlockExit,
            referenceExit,referenceReason,referenceOutcome);
      if(nasOppositeExitAt>0&&(referenceExit<=0||nasOppositeExitAt<referenceExit))
      {referenceExit=nasOppositeExitAt;referenceOutcome=g_rtNasAdditionalExit?"NAS_ADDITIONAL_EXIT":"NAS_OPPOSITE_EXIT";}
      datetime referenceReverse=0;string referenceDetail="";
      FindNewDayAcceptedReverseExit(g_regimeReferenceSignals,entryT,execDir,g_histRunNow,referenceReverse,referenceDetail);
      if(referenceReverse>0&&(referenceExit<=0||referenceReverse<referenceExit))
      {referenceExit=referenceReverse;referenceOutcome="MA_REVERSE_EXIT";}
      HistResult referenceSim=sim;
      if(referenceExit!=forcedExitAt||referenceOutcome!=forcedExitOutcome)
      {
         datetime referenceEnd=te;
         referenceSim=OrbMemoLifecycle(entryT,te,g_histRunNow,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,RuntimeHalfBeLeg(),referenceEnd,referenceExit,referenceOutcome);
      }
      g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
      WriteInternalSimAudit("dashboard_hist",entryT,simEnd,execDir,entry,NormalizePrice(sl),sim,modernDetail+" "+entryDetail+" "+regimeDetail+" "+invertDetail+" regime_allowed="+(OrbRegimeAllowed(regimeBucket)?"1":"0")
         +(filteredWindowExitAt>0?" filtered_window_exit_at="+FmtTime(filteredWindowExitAt)
            +" filtered_window_exit_reason="+filteredWindowExitReason+" filtered_window_exit_outcome="+filteredWindowExitOutcome:"")
         +(nasOppositeExitAt>0?" nas_opposite_exit_at="+FmtTime(nasOppositeExitAt)+" "+nasOppositeDetail:"")
         +(newDayReverseExitAt>0?" new_day_reverse_exit_at="+FmtTime(newDayReverseExitAt)+" "+newDayReverseDetail:""));
      bool finalOutcome=(sim.valid&&sim.outcome!="open");
      bool referenceFinal=referenceSim.valid&&referenceSim.outcome!="open";
      if(referenceFinal&&regimeBucket>=0&&regimeBucket<ORB_REGIME_COUNT)
      {
         if(referenceSim.netR>0)g_regimeWins[regimeBucket]++;
         else if(referenceSim.netR<0)g_regimeLosses[regimeBucket]++;
      }
      if(referenceFinal&&rfIndex>=0&&rfIndex<ORB_RF_COUNT)
      {
         if(referenceSim.netR>0)g_orbRfWins[rfIndex]++;
         else if(referenceSim.netR<0)g_orbRfLosses[rfIndex]++;
      }
      if(!OrbRegimeAllowed(regimeBucket))
      {
         g_histFiltered++;
         if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST regime blocked ",regimeDetail," signal=",FmtTime(sigT));
         return;
      }
      // Both diagnostic panels use the fixed pre-macro/RF universe above.
      if(!rfAllowed)
      {
         g_histFiltered++;
         if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST RF blocked ",rfRule," ",regimeDetail," signal=",FmtTime(sigT));
         return;
      }
      if(g_maIndependent)
      {
         // Missing exit evidence conservatively occupies a slot through the audit cutoff.
         MaHistoricalCapacityOccupy(sim.valid&&sim.outcome!="open"&&sim.exitTime>0?sim.exitTime:g_histRunNow+1);
      }
      if(!g_maIndependent)
         g_maAuditPositionUntil=MaLegacyAuditPositionUntil(sim,g_histRunNow,forcedExitAt,forcedExitOutcome);
      if(finalOutcome&&LabPolicyEnabled()&&!g_maIndependent)g_labHistLastClose=sim.exitTime;
      if(finalOutcome)
      {
         if(sim.outcome=="SL")g_histStopLossExits++;
         else if(sim.outcome=="NAS_OPPOSITE_EXIT"||sim.outcome=="NAS_ADDITIONAL_EXIT")g_histNasOppositeExits++;
         else if(sim.outcome=="MA_REVERSE_EXIT")g_histNewDayReverseExits++;
      }
      AxTrade csv;ZeroMemory(csv);
      csv.signalTime=sigT;csv.availableTime=OrbSignalAvailableTime(entryT);
      csv.entryTime=sim.entryTime;csv.entryClock=AxEntryClock(sim.entryTime,sim.entrySpreadPoints);
      csv.exitTime=sim.exitTime;csv.localTime=ServerToSessionLocal(csv.entryTime>0?csv.entryTime:csv.availableTime);
      csv.rawDirection=dir=="BUY"?1:-1;csv.direction=isBuy?1:-1;
      csv.valid=sim.valid;csv.closed=finalOutcome;csv.won=sim.netR>1e-8;
      csv.entrySpreadPoints=sim.entrySpreadPoints;csv.spreadBasis=sim.entrySpreadPoints!=EMPTY_VALUE?"ENTRY_BID_ASK_QUOTE":"NOT_CAPTURED_BAR_MODEL";
      csv.entry=sim.simEntry;csv.sl=sim.simSl;csv.tp=sim.simTarget;csv.exitPrice=sim.exitPrice;
      csv.netR=sim.netR;csv.costR=sim.costR;csv.outcome=sim.outcome;csv.reason=AxExitReason(sim.valid,finalOutcome,sim.invalidReason,sim.outcome);
      csv.plannedEntry=entry;csv.plannedSl=sl;csv.plannedTp=tp1;
      csv.regionHigh=hi;csv.regionLow=lo;csv.regime=regimeBucket;csv.rf=rfIndex;
      csv.context=modernDetail+" "+entryDetail+" "+regimeDetail+" "+invertDetail;
      AxCapture(csv);
      g_histTotal++;
      double statR=finalOutcome?sim.netR:0.0;
      if(finalOutcome){DailyQuotaSchedule(sim.exitTime,sim.netR>1e-8?1:(sim.netR<-1e-8?-1:0));TCalRecord(csv.localTime,sim.netR);}
      if(!sim.valid)
      {
         g_histInvalid++;
         if(g_histFirstInvalidReason=="")g_histFirstInvalidReason=sim.invalidReason;
      }
      else if(!finalOutcome)g_histOpen++;
      else if(sim.netR>1e-8)
      {
         g_histWins++;g_histWonR+=sim.netR;
         if(daySt.day_of_week>=1&&daySt.day_of_week<=5)g_weekdayWins[daySt.day_of_week]++;
      }
      else if(sim.netR<-1e-8)
      {
         g_histLosses++;g_histLostR+=MathAbs(sim.netR);DirectionRecordLoss(isBuy?1:-1);
         if(daySt.day_of_week>=1&&daySt.day_of_week<=5)g_weekdayLosses[daySt.day_of_week]++;
      }
      else g_histFlat++;
      g_histNetR+=statR;
      g_histNetMoney+=SimMoneyPnl(statR);
      if(g_histNetR<g_histMinCumulativeR)
      {
         g_histMinCumulativeR=g_histNetR;
         g_histMinCumulativeMoney=SimMoneyPnl(g_histNetR);
      }
      if(g_histNetR>g_histPeakCumulativeR)
         g_histPeakCumulativeR=g_histNetR;
      double peakDrawdownR=g_histNetR-g_histPeakCumulativeR;
      if(peakDrawdownR<g_histMaxPeakDrawdownR)
      {
         g_histMaxPeakDrawdownR=peakDrawdownR;
         g_histMaxPeakDrawdownMoney=SimMoneyPnl(peakDrawdownR);
      }

      // Debug audit
      if(InpHistoricalAuditVerboseLog)Print("ORB15v3 HIST #"+IntegerToString(g_histTotal)+" "+execDir+" raw="+dir,
            " date=",daySt.year,".",daySt.mon,".",daySt.day,
            " breakout=",FmtTime(sigT),
            " entryTime=",FmtTime(entryT),
            " entry=",DoubleToString(entry,_Digits),
            " sl=",DoubleToString(sl,_Digits),
            " tp1=",DoubleToString(tp1,_Digits),
            " tp2=",DoubleToString(tp2,_Digits),
            " tp3=",DoubleToString(tp3,_Digits),
            " tp4=",DoubleToString(tp4,_Digits),
            " tp5=",DoubleToString(tp5,_Digits),
            " tp6=",DoubleToString(tp6,_Digits),
            " risk=",DoubleToString(risk,_Digits),
            " outcome=",sim.outcome,
            " simEnd=",FmtTime(simEnd),
            " valid=",sim.valid?"1":"0",
            " invalid=",sim.invalidReason,
            " maxTp=",sim.maxTp,
            " modern=",modernDetail,
            " entryMode=",entryDetail,
            " targetLeg=",sim.targetLeg,
            " exitMode=",sim.exitMode,
            " exitPrice=",DoubleToString(sim.exitPrice,_Digits),
            " exitTime=",sim.exitTime>0?FmtTime(sim.exitTime):"-",
            " fill=",DoubleToString(sim.simEntry,_Digits),
            " simSl=",DoubleToString(sim.simSl,_Digits),
            " simTarget=",DoubleToString(sim.simTarget,_Digits),
            " costR=",DoubleToString(sim.costR,2),
            " netR=",DoubleToString(sim.netR,2),
            " statR=",DoubleToString(statR,2));

      // Draw arrow with outcome
      datetime fillAt=sim.entryTime>0?sim.entryTime:BarCloseTime(RuntimeEntryTf(),entryT);
      datetime visualT=0;
      double simRisk=MathAbs(sim.simEntry-sim.simSl);
      double pad=0.0,arwP=0.0;
      MaCrossTradeMarker(fillAt,isBuy,sim.simEntry,visualT,arwP,pad);
      string dateKey=(string)(long)sigT;
      datetime levelStart=fillAt;
      datetime levelEnd=LabNativeVisualBarCap(levelStart);
      datetime nextSig=0;
      FindNextHistoricalSignalAfter(sigT,levelEnd,nextSig);
      if(nextSig>levelStart&&nextSig<levelEnd)levelEnd=nextSig;
      if(filteredWindowExitAt>levelStart&&filteredWindowExitAt<levelEnd)levelEnd=filteredWindowExitAt;
      datetime liveCut=NextOrbOpenOwnPositionTimeAfter(levelStart,levelEnd);
      if(liveCut>levelStart&&liveCut<levelEnd)levelEnd=liveCut;
      // Keep the geometry readable for up to 20 entry-TF bars. A fast TP/SL
      // must not collapse the three reference lines to one or two candles;
      // later signal/lifecycle boundaries above still prevent overlap.
      string levelId=dateKey+"_"+execDir;
      color arwClr=!sim.valid?C'145,155,170':(!finalOutcome?clrGold:(sim.netR>1e-8?clrLime:(sim.netR<-1e-8?clrTomato:clrLightSteelBlue)));
      int arwCode=isBuy?233:234;

      // Result text with detail
      double simPnl=SimMoneyPnl(statR);
      double grossR=finalOutcome?sim.netR+sim.costR:0.0;
      string verdict=!sim.valid?"DATA":(!finalOutcome?"OPEN":(sim.netR>1e-8?"WIN":(sim.netR<-1e-8?"LOSS":"FLAT")));
      string txt=verdict+" "+MaCrossSignalText(g_rtMaCrossMode,dir=="BUY"?1:-1)+" "+sim.outcome
         +" hitTP"+IntegerToString(sim.maxTp)+"/T"+IntegerToString(sim.targetLeg)
         +(finalOutcome?" G="+DoubleToString(grossR,2)+"R C="+DoubleToString(sim.costR,2)+"R N="+DoubleToString(statR,2)+"R":"")+" "
         +(simPnl>=0?"+":"")+DoubleToString(simPnl,2)+"$"
         +" FILL="+DoubleToString(sim.simEntry,_Digits)
         +(sim.exitTime>0?" X="+FmtTime(sim.exitTime)+"@"+DoubleToString(sim.exitPrice,_Digits):"")+" "
         +sim.exitMode;
      if(modernDetail!="")txt+=" "+modernDetail;
      txt+=" "+EntryModeLabel(g_rtEntryMode);
      if(!sim.valid&&sim.invalidReason!="")txt+=" "+sim.invalidReason;
      color txtClr=!sim.valid?C'170,180,195':(!finalOutcome?clrKhaki:(sim.netR>1e-8?clrPaleGreen:(sim.netR<-1e-8?clrLightSalmon:clrLightSteelBlue)));
      double txtP=isBuy?arwP-pad*0.65:arwP+pad*0.65;

      string hcTxt=sim.hcLeg>0?DoubleToString(PriceAtLeg(isBuy,sim.simEntry,simRisk,sim.hcLeg),_Digits):"OFF";
      string lvlTxt="SL="+DoubleToString(sim.simSl,_Digits)
         +" TP="+DoubleToString(sim.simTarget,_Digits)
         +" HC="+hcTxt;
      double lvlP=isBuy?txtP-pad*0.55:txtP+pad*0.55;
      string markerTip=MaCrossTradeMarkerTooltip(sigT,sim.entryTime);
      bool showExit=finalOutcome&&sim.exitTime>0&&sim.exitPrice>0.0;
      bool levels=InpDrawTradeLevelSegments&&levelEnd>levelStart;
      string visualKey=(string)sigT+"|"+dir+"|"+execDir+"|"+(string)visualT+"|"+(string)levelStart+"|"+(string)levelEnd
         +"|"+AuditMemoPrice(arwP)+"|"+AuditMemoPrice(txtP)+"|"+AuditMemoPrice(lvlP)
         +"|"+AuditMemoPrice(sim.simEntry)+"|"+AuditMemoPrice(sim.simSl)+"|"+AuditMemoPrice(sim.simTarget)
         +"|"+(string)sim.exitTime+"|"+AuditMemoPrice(sim.exitPrice)+"|"+(string)showExit+"|"+(string)levels
         +"|"+(string)arwCode+"|"+(string)arwClr+"|"+(string)txtClr+"|"+sim.outcome+"|"+txt+"|"+lvlTxt+"|"+markerTip;
      bool reused=false;int visualSlot=MaVisualBeginPlot(visualKey,reused);
      if(reused){g_histDrawn++;return;}
      string base=MaHistoryEventBase(sigT,dir);
      DrawOrbHistoricalSegment(levelId+"_ENTRY",levelStart,levelEnd,sim.simEntry,C'230,230,230',STYLE_SOLID);
      ObjectSetString(0,HistoricalObjectRoot()+"LVL_"+levelId+"_ENTRY",OBJPROP_TOOLTIP,
         "SIMULATED FILL: "+DoubleToString(sim.simEntry,_Digits)+" | "+markerTip);
      DrawOrbHistoricalSegment(levelId+"_SL",levelStart,levelEnd,sim.simSl,C'255,80,110',STYLE_SOLID);
      if(sim.simTarget>0.0)
         DrawOrbHistoricalSegment(levelId+"_TP",levelStart,levelEnd,sim.simTarget,C'80,255,180',STYLE_SOLID);
      string arrowName=base+"ARW";
      if(IsFreshHistoricalBuildObject(arrowName))ObjectCreate(0,arrowName,OBJ_ARROW,0,visualT,arwP);
      else if(ObjectFind(0,arrowName)<0)ObjectCreate(0,arrowName,OBJ_ARROW,0,visualT,arwP);
      else ObjectMove(0,arrowName,0,visualT,arwP);
      ObjectSetInteger(0,arrowName,OBJPROP_ARROWCODE,arwCode);
      ObjectSetInteger(0,arrowName,OBJPROP_COLOR,arwClr);
      ObjectSetInteger(0,arrowName,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,arrowName,OBJPROP_ANCHOR,isBuy?ANCHOR_TOP:ANCHOR_BOTTOM);
      ObjectSetString(0,arrowName,OBJPROP_TOOLTIP,markerTip);
      ObjectSetInteger(0,arrowName,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,arrowName,OBJPROP_HIDDEN,false);
      if(showExit)DrawSignalText(base+"EXIT",sim.exitTime,sim.exitPrice,"X "+sim.outcome,arwClr);
      DrawSignalText(base+"TXT",visualT,txtP,txt,txtClr);
      DrawSignalText(base+"LVLTXT",visualT,lvlP,lvlTxt,txtClr);
      int levelMask=(sim.simEntry>0.0?1:0)|(sim.simSl>0.0?2:0)|(sim.simTarget>0.0?4:0);
      MaVisualEndPlot(visualSlot,"MA_"+dateKey+"_"+dir+"_",levelId,levels&&sim.simTarget>0.0,showExit,levels,levelMask);
      g_histDrawn++;
  
}

void CancelHistoricalAuditBuild()
{
   MaVisualAbort();
   AxAbort("CSV cancelled: audit restarted");g_axReady=false;
   if(g_histBuildGeneration>0)
      DeleteByPrefix(HistoricalGenerationRoot(g_histBuildGeneration));
   g_histBuildGeneration=0;
   g_histNasCacheActive=false;
   ArrayResize(g_histWindowSignals,0);
   ArrayResize(g_histAcceptedSignals,0);
   ArrayResize(g_regimeReferenceSignals,0);ArrayResize(g_regimeReferenceWindows,0);
   ArrayResize(g_histOperationalSignals,0);
   ArrayResize(g_histDaySnapshots,0);
   ClearHistoricalTickReplayCache();
   g_histAuditRunning=false;
   g_histAuditCancelRequested=false;
   g_histAuditPhase=0;
   g_histAuditStage="QUEUED";
   g_histAuditStageDone=0;
   g_histAuditStageTotal=0;
   g_histAuditProcessedDays=0;
   g_histAuditProgressPct=0.0;
}

void FinalizeHistoricalAudit()
{
   AxSealCurrent();
   g_histAuditProcessedDays=g_histRunDays;
   SetHistoricalAuditProgress("COMPLETE",100.0,0.0,1,1);
   ulong calcCompletedMs=GetTickCount64();
   if(g_histAuditStageStartedMs>0)
      g_histAuditCalcSec=(double)(calcCompletedMs-g_histAuditStageStartedMs)/1000.0;
   ulong commitStartedMs=GetTickCount64();
   MaVisualCommit();
   CommitHistoricalSnapshot();
   ulong completedMs=GetTickCount64();
   g_histAuditCommitSec=(double)(completedMs-commitStartedMs)/1000.0;
   g_histAuditLastElapsedSec=g_histAuditStartedMs>0?(double)(completedMs-g_histAuditStartedMs)/1000.0:0.0;
   ulong wallBase=g_histAuditRequestedMs>0?g_histAuditRequestedMs:g_histAuditStartedMs;
   g_histAuditLastWallSec=wallBase>0?(double)(completedMs-wallBase)/1000.0:g_histAuditLastElapsedSec;
   g_histNasCacheActive=false;
   ClearHistoricalTickReplayCache();
   g_histAuditRunning=false;g_histAuditCancelRequested=false;g_histAuditPhase=0;g_histAuditStage="";
   int resolved=g_histWins+g_histLosses;
   double wr=resolved>0?(double)g_histWins/(double)resolved*100.0:0;
   g_histStatLine=(g_mcOf.mode!=0&&g_mcOfDataIncomplete?"INCOMPLETE ORDER FLOW DATA | ":"")+IntegerToString(ArraySize(g_maCrossAuditEvents))+" raw / "+IntegerToString(g_histTotal)+" trades | "+IntegerToString(g_histWins)+"W "+IntegerToString(g_histLosses)+"L "+IntegerToString(g_histOpen)+"O "+IntegerToString(g_histFlat)+"F"+(g_histInvalid>0?" "+IntegerToString(g_histInvalid)+" DATA":"")+" | WR "+DoubleToString(wr,1)+"% | Exit SL="+IntegerToString(g_histStopLossExits)+" NAS-X="+IntegerToString(g_histNasOppositeExits)+" MA-REV="+IntegerToString(g_histNewDayReverseExits)+" | Net "+DoubleToString(g_histNetR,1)+"R | $ "+(g_histNetMoney>=0?"+":"")+DoubleToString(g_histNetMoney,2)+" | MinCum "+DoubleToString(g_histMinCumulativeR,2)+"R/$"+DoubleToString(g_histMinCumulativeMoney,2)+" | PeakDD "+DoubleToString(g_histMaxPeakDrawdownR,2)+"R/$"+DoubleToString(g_histMaxPeakDrawdownMoney,2);
   if(g_histFiltered>0)g_histStatLine+=" | "+IntegerToString(g_histFiltered)+" filt";
   if(g_histDrawnWindowCount>0)g_histStatLine+=" | "+IntegerToString(g_histDrawnWindowCount)+" window ("+IntegerToString(g_histRejectedWindowRaw)+" raw)";
   Print("ORB15v3 ======= HIST RESULT: ",g_histStatLine," checked=",g_histChecked," drawn=",g_histDrawn,
      " elapsed_sec=",DoubleToString(g_histAuditLastElapsedSec,3),
      " wall_sec=",DoubleToString(g_histAuditLastWallSec,3),
      " stages[COVERAGE=",DoubleToString(g_histAuditCoverageSec,3),
      " NAS=",DoubleToString(g_histAuditNasSec,3),
      " PREP=",DoubleToString(g_histAuditPrepSec,3),
      " DRAW=",DoubleToString(g_histAuditDrawSec,3),
      " CALC=",DoubleToString(g_histAuditCalcSec,3),
      " COMMIT=",DoubleToString(g_histAuditCommitSec,3),"] =======");
   Print("ORB15v3 HIST_TICK_INDEX visited=",g_histTickTicksVisited,
      " skipped_ticks=",g_histTickTicksSkipped,
      " skipped_blocks=",g_histTickBlocksSkipped);
   Print("MA_VISUAL_CACHE hits=",g_maVisualHits," misses=",g_maVisualMisses);
   if(g_rtAdvancedAuditEngine)
      Print("ORB15v3 ADV_EXACT_INDEX disk_hits=",g_orbAdvIndexDiskHits,
         " cold_builds=",g_orbAdvIndexColdBuilds," invalid=",g_orbAdvIndexInvalid,
         " tree_queries=",g_orbAdvTreeQueries," skipped_minutes=",g_orbAdvTreeNodesSkipped,
         " exact_minutes=",g_orbAdvExactMinutes," exact_ticks=",g_orbAdvExactTicks,
         " parity=",g_orbAdvParityChecks,"/",g_orbAdvParityMismatches,
         " index_io_sec=",DoubleToString(g_orbAdvIndexIoSec,3));
   Audit("hist_redraw","",0,0,0,0,g_histStatLine+" days="+IntegerToString(g_histRunDays)
      +" elapsed_sec="+DoubleToString(g_histAuditLastElapsedSec,3)
      +" wall_sec="+DoubleToString(g_histAuditLastWallSec,3));
   UpdateDashboard();
   ChartRedraw(0);
   g_histAuditRequestedMs=0;
   if(!IsTesterMode())EventSetTimer(5);
   MaPruneObservedSignals(g_histRunNow-PeriodSeconds(g_rtSignalTf));
   OrbUserAuditCompleted();
}

void ProcessHistoricalAuditStep()
{
   if(!g_histAuditRunning)return;
   if(g_histAuditCancelRequested)return;
   // Keep callbacks short enough for MT5 to dispatch chart clicks between
   // chunks. A single day remains the smallest indivisible simulation unit.
   // PREP/CALC are pure data work and can use most of the 40 ms timer slot.
   // DRAW retains a wider UI margin because ObjectCreate/ChartRedraw calls can
   // themselves consume several milliseconds on object-heavy charts.
   ulong budgetMs=(g_histAuditPhase==2?22:30);
   ulong started=GetTickCount64();
   int workUnits=0;
   while(g_histAuditRunning&&!g_histAuditCancelRequested)
   {
      if(g_histAuditPhase==1)
      {
         if(g_histPrepBack<ArraySize(g_maCrossAuditEvents))
         {
            MaCrossAuditEvent ofEvent=g_maCrossAuditEvents[g_histPrepBack];
            MqlDateTime ofDay;TimeToStruct(ServerToSessionLocal(ofEvent.signalTime),ofDay);
            string ofPreReason="";
            bool needsFlow=g_mcOf.mode!=0&&EntryWindowAllowsAt(OrbSignalAvailableTime(ofEvent.signalTime))
               &&HistCheckDay(ofDay.day_of_week,ofPreReason)&&HistCheckVol(ofEvent.volume,ofEvent.priorVolume,ofPreReason);
            if(needsFlow)
            {
               string error="";
               int ready=McOfPrepare(_Symbol,g_rtSignalTf,ofEvent.signalTime,true,error);
               if(ready!=1)
               {
                  g_mcOfStatus=error;g_histAuditStage="ORDER FLOW DATA";
                  if(ready<0)
                  {
                     g_mcOfDataIncomplete=true;CancelHistoricalAuditBuild();OrbResetHistoricalStats();
                     g_userCompletedReady=false;g_histStatLine="INCOMPLETE ORDER FLOW: "+error;
                     g_histNeedsRedraw=false;g_histCoveragePending=false;g_histCoverageHardBlocked=true;
                     UpdateDashboard();ChartRedraw(0);
                  }
                  return; // Keep this candidate; waiting is not a market rejection.
               }
            }
            g_mcOfAuditContext=true;
            g_histRejectedWindowRaw+=ProcessMaHistoricalPrepEvent(g_histPrepBack);
            g_mcOfAuditContext=false;
            g_histPrepBack++;
            int done=g_histPrepBack;
            g_histAuditProcessedDays=done;
            SetHistoricalAuditProgress("PREP",1.0,6.0,done,ArraySize(g_maCrossAuditEvents));
            workUnits++;
         }
         else
         {
            if(g_histAuditStageStartedMs>0)
               g_histAuditPrepSec=(double)(GetTickCount64()-g_histAuditStageStartedMs)/1000.0;
            g_histAuditPhase=2;
            g_histAuditStageStartedMs=GetTickCount64();
            g_histNasOverlayIndex=0;
            g_histOverlayIndex=0;
            int drawTotal=(g_histNasCacheActive&&NasOverlayEnabled()?ArraySize(g_histNasEvents):0)
               +ArraySize(g_histWindowSignals);
            SetHistoricalAuditProgress("DRAW",7.0,3.0,0,MathMax(1,drawTotal));
         }
      }
      else if(g_histAuditPhase==2)
      {
         int nasTotal=(g_histNasCacheActive&&NasOverlayEnabled()?ArraySize(g_histNasEvents):0);
         int windowTotal=ArraySize(g_histWindowSignals);
         int total=nasTotal+windowTotal;
         if(g_histNasOverlayIndex<nasTotal)
         {
            if(DrawCachedNasSignalOverlayEvent(g_histNasOverlayIndex,g_histRunDays,g_histRunNow))
               g_histDrawnNasSignals++;
            g_histNasOverlayIndex++;
            SetHistoricalAuditProgress("DRAW",7.0,3.0,
               g_histNasOverlayIndex+g_histOverlayIndex,MathMax(1,total));
            workUnits++;
         }
         else if(g_histOverlayIndex<windowTotal)
         {
            if(g_histWindowSignals[g_histOverlayIndex].drawOnChart)g_histDrawnWindowCount++;
            DrawOrbWindowSignal(g_histWindowSignals[g_histOverlayIndex],g_histOverlayIndex);
            g_histOverlayIndex++;
            SetHistoricalAuditProgress("DRAW",7.0,3.0,
               g_histNasOverlayIndex+g_histOverlayIndex,MathMax(1,total));
            workUnits++;
         }
         else
         {
            if(g_histAuditStageStartedMs>0)
               g_histAuditDrawSec=(double)(GetTickCount64()-g_histAuditStageStartedMs)/1000.0;
            g_histAuditPhase=3;g_histAuditStage="CALC";g_histCalcBack=0;
            g_histAuditStageStartedMs=GetTickCount64();
            g_lastNasOverlaySignalCount=g_histDrawnNasSignals;
            g_lastNasOverlayCopiedBars=g_histNasCacheCopiedBars;
            g_lastNasOverlayClosedBar=iTime(_Symbol,NasConfirmationTf(),1);
            SetHistoricalAuditProgress("CALC",10.0,90.0,0,ArraySize(g_maCrossAuditEvents));
            Print("ORB15v3 ======= HIST REDRAW START ======= TF=",TfLabel(g_rtSignalTf),
                  " Delay=",g_rtUseDelay?IntegerToString(g_rtDelayMin)+"min":"OFF",
                  " ATR=",g_rtFilterAtr?"ON":"OFF"," VOL=",g_rtFilterVol?"ON":"OFF",
                  " DAY=",g_rtFilterDay?"ON":"OFF"," ",HalfBeLabel(),
                  " ",TargetLabel()," ",RuntimeInvertLabel()," audit_weeks=",IntegerToString(g_rtHistoricalWeeks),
                  " nas_overlay=",IntegerToString(g_histDrawnNasSignals)," nas_history_bars=",g_lastNasOverlayCopiedBars,
                  " nas_tf=",TfLabel(NasConfirmationTf())," nas_sensitivity=",g_rtNasSensitivity,
                  " state_vol=",g_rtNasVolumeFilter?"ON":"OFF"," state_vol_x=",DoubleToString(g_rtNasVolumeMultiplier,2),
                  " flow_vol=",g_rtNasFlowVolumeFilter?"ON":"OFF"," flow_vol_x=",DoubleToString(g_rtNasFlowVolumeMultiplier,2));
         }
      }
      else if(g_histAuditPhase==3)
      {
         if(g_histCalcBack<ArraySize(g_maCrossAuditEvents))
         {
            ProcessHistoricalCalcDay(g_histCalcBack);
            g_histCalcBack++;
            int done=g_histCalcBack;
            g_histAuditProcessedDays=done;
            SetHistoricalAuditProgress("CALC",10.0,90.0,done,ArraySize(g_maCrossAuditEvents));
            workUnits++;
         }
         else
         {
            FinalizeHistoricalAudit();
            break;
         }
      }
      else
      {
         CancelHistoricalAuditBuild();
         break;
      }
      if(workUnits>0&&GetTickCount64()-started>=budgetMs)break;
   }
   if(g_histAuditRunning)RenderHistoricalAuditProgress();
}

void DrawHistoricalSignals()
{
   if(IsTesterMode()){CancelHistoricalAuditBuild();DeleteHist();g_histStatLine="tester_skip";return;}
   if(!InpDrawHistoricalSignals)
   {
      CancelHistoricalAuditBuild();DeleteHist();g_histStatLine="off";
      EventKillTimer();EventSetTimer(5);
      return;
   }
   datetime currentTime=TimeCurrent();
   if(!g_histNeedsRedraw&&g_lastHistBuild>0&&currentTime-g_lastHistBuild<300)return;
   int days=RuntimeHistoricalDays();
   string coverageDetail="";bool hardBlocked=false;
   ulong coverageStartedMs=GetTickCount64();
   if(g_histAuditRequestedMs==0)g_histAuditRequestedMs=coverageStartedMs;
   g_histCoverageAttempts++;
   if(!EnsureOrbAuditHistoryCoverage(days,coverageDetail,hardBlocked))
   {
      g_histAuditCoverageSec=(double)(GetTickCount64()-coverageStartedMs)/1000.0;
      OrbResetHistoricalStats();
      g_histCoveragePending=true;
      g_histCoverageHardBlocked=hardBlocked;
      g_histCoverageStatus=HistoricalWindowLabel()+(hardBlocked?" HISTORY BLOCKED":" HISTORY SYNC");
      g_histCoverageDetail=coverageDetail;
      g_histStatLine=g_histCoverageStatus+" | "+coverageDetail;
      g_histNeedsRedraw=!hardBlocked&&InpAuditHistoryAutoRetry;
      g_histCoverageNextRetry=TimeLocal()+MathMax(2,InpAuditHistoryRetrySec);
      Print("ORB15v3 ",g_histStatLine);
      UpdateDashboard();
      ChartRedraw(0);
      if(!IsTesterMode()){EventKillTimer();EventSetTimer(5);}
      return;
   }
   g_histAuditCoverageSec=(double)(GetTickCount64()-coverageStartedMs)/1000.0;
   g_histCoveragePending=false;g_histCoverageHardBlocked=false;g_histCoverageNextRetry=0;
   g_histCoverageAttempts=0;g_histCoverageStatus="";g_histCoverageDetail="";
   g_lastHistBuild=currentTime;g_histNeedsRedraw=false;
   BeginHistoricalSnapshot();
   MaVisualBeginAudit(PREFIX+"HIST_POOL_",OrbUserRuntimeMetricKey()+"|"+TCalStrategyText()
      +"|risk="+AuditMemoPrice(g_rtRiskPerTradePct)+"|money="+AuditMemoPrice(SimMoneyPnl(1.0)));

   datetime nyNow=ServerToSessionLocal(currentTime);MqlDateTime nySt;TimeToStruct(nyNow,nySt);
   g_histRunNyMid=MakeDateTime(nySt.year,nySt.mon,nySt.day,0,0,0);
   g_histRunNow=currentTime;g_histRunDays=days;
   datetime maAuditFrom=currentTime-(datetime)((long)days*86400L);
   Print("ORB15v3 MA_CACHE_BEGIN tf=",(int)g_rtSignalTf," from=",TimeToString(maAuditFrom,TIME_DATE|TIME_MINUTES),
         " seed=",TimeToString(McHistorySeed(_Symbol,g_rtSignalTf),TIME_DATE|TIME_MINUTES),
         " mode=",(int)g_rtMaCrossMode);
   if(!MaCrossAuditBuild(_Symbol,g_rtSignalTf,maAuditFrom,currentTime,g_rtMaCrossMode,g_rtMaCrossPair,
      MathMax(1,InpMaFastLength),MathMax(1,InpMaMediumLength),MathMax(2,InpMaSlowLength)))
   {
      MaVisualAbort();
      g_maCacheFailedAttempts++;
      g_histCoverageHardBlocked=(g_maCacheFailedAttempts>=3);
      g_histCoverageDetail=g_maCrossAuditFailure;
      g_histStatLine=(g_histCoverageHardBlocked?"MA HISTORY BLOCKED: ":"MA HISTORY WAIT: ")+g_histCoverageDetail;
      g_histNeedsRedraw=!g_histCoverageHardBlocked&&InpAuditHistoryAutoRetry;
      g_histCoveragePending=true;
      g_histCoverageStatus=g_histCoverageHardBlocked?"MA HISTORY BLOCKED":"MA SIGNAL HISTORY SYNC";
      g_histCoverageNextRetry=TimeLocal()+MathMax(2,InpAuditHistoryRetrySec);
      Print("ORB15v3 ",g_histStatLine);
      UpdateDashboard();ChartRedraw(0);return;
   }
   g_maCacheFailedAttempts=0;
   InitializeHistoricalTickReplayCoverage();
   if(LabPolicyEnabled()&&g_histTickCoverageKnown
      &&(g_histTickFirstAvailableMs==ULONG_MAX||g_histTickFirstAvailableMs>(ulong)(maAuditFrom+7*86400)*1000))
   {
      MaVisualAbort();OrbResetHistoricalStats();g_userCompletedReady=false;
      g_histCoveragePending=true;g_histCoverageHardBlocked=true;g_histNeedsRedraw=false;
      g_histCoverageStatus=HistoricalWindowLabel()+" TICK HISTORY UNAVAILABLE";
      g_histCoverageDetail=g_histTickFirstAvailableMs==ULONG_MAX?"Broker returned no quote ticks"
         :"First broker quote: "+TimeToString((datetime)(g_histTickFirstAvailableMs/1000),TIME_DATE|TIME_MINUTES);
      g_histCoverageDetail+=" | requested: "+TimeToString(maAuditFrom,TIME_DATE|TIME_MINUTES)+" | exact exits require ticks";
      g_histStatLine=g_histCoverageStatus+" | "+g_histCoverageDetail;
      Print("ENTRYLAB ",g_histStatLine);UpdateDashboard();ChartRedraw(0);return;
   }
   OrbUserAuditStarted();
   g_mcOfDataIncomplete=false;
   g_histRunPoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(g_histRunPoint<=0.0)g_histRunPoint=0.0001;
   g_histAuditRunning=true;g_histAuditCancelRequested=false;g_histAuditPhase=1;
   g_histAuditStartedMs=GetTickCount64();
   g_histAuditNasSec=0.0;g_histAuditPrepSec=0.0;g_histAuditDrawSec=0.0;g_histAuditCalcSec=0.0;g_histAuditCommitSec=0.0;
   g_histTickBlocksSkipped=0;g_histTickTicksSkipped=0;g_histTickTicksVisited=0;
   OrbAdvancedAuditResetRunStats();
   g_histAuditStageStartedMs=g_histAuditStartedMs;
   g_histAuditTotalDays=days;g_histAuditProcessedDays=0;
   SetHistoricalAuditProgress("NAS",0.0,1.0,0,1);
   g_histPrepBack=0;g_histCalcBack=0;g_maAuditPositionUntil=0;g_maAuditHeldCandidates=0;g_histNasOverlayIndex=0;g_histOverlayIndex=0;
   g_maHistSeriesDir=0;g_maHistSeriesCount=0;MaHistoricalCapacityReset();
   g_histRejectedWindowRaw=0;g_histDrawnWindowCount=0;g_histDrawnNasSignals=0;
   g_histChecked=0;g_histDrawn=0;g_histFiltered=0;
   OrbResetHistoricalStats();
   g_histAuditRunning=true;g_histAuditPhase=1;
   ArrayResize(g_histWindowSignals,0);ArrayResize(g_histAcceptedSignals,0);ArrayResize(g_histOperationalSignals,0);
   ArrayResize(g_regimeReferenceSignals,0);ArrayResize(g_regimeReferenceWindows,0);
   ClearHistoricalTickReplayCache();
   ArrayResize(g_histDaySnapshots,ArraySize(g_maCrossAuditEvents));
   for(int ci=0;ci<ArraySize(g_histDaySnapshots);ci++)
   {
      g_histDaySnapshots[ci].known=false;g_histDaySnapshots[ci].valid=false;
      g_histDaySnapshots[ci].hi=0.0;g_histDaySnapshots[ci].lo=0.0;g_histDaySnapshots[ci].avgVolume=0.0;
      g_histDaySnapshots[ci].orbStart=0;g_histDaySnapshots[ci].orbEnd=0;
      g_histDaySnapshots[ci].tradeEnd=0;g_histDaySnapshots[ci].usedBars=0;
      g_histDaySnapshots[ci].operationalKnown=false;g_histDaySnapshots[ci].operationalFound=false;
      g_histDaySnapshots[ci].operationalHadRawCandidate=false;g_histDaySnapshots[ci].operationalDirection="";
      g_histDaySnapshots[ci].operationalSignalTime=0;g_histDaySnapshots[ci].operationalClose=0.0;
      g_histDaySnapshots[ci].operationalHigh=0.0;g_histDaySnapshots[ci].operationalLow=0.0;
      g_histDaySnapshots[ci].operationalVolume=0.0;g_histDaySnapshots[ci].operationalPreAverageVolume=0.0;
      g_histDaySnapshots[ci].operationalLastReject="";g_histDaySnapshots[ci].operationalModernDetail="";
   }
   string nasCacheDetail="";
   RenderHistoricalAuditProgress(true);
   bool nasCacheOk=BuildHistoricalNasEventCache(days,currentTime,nasCacheDetail);
   g_histAuditNasSec=(double)(GetTickCount64()-g_histAuditStartedMs)/1000.0;
   g_histAuditStageStartedMs=GetTickCount64();
   Print("ORB15v3 ",nasCacheDetail);
   if(!nasCacheOk)
   {
      MaVisualAbort();
      if(g_histBuildGeneration>0)DeleteByPrefix(HistoricalGenerationRoot(g_histBuildGeneration));
      g_histBuildGeneration=0;
      g_histAuditRunning=false;g_histAuditPhase=0;g_histNasCacheActive=false;
      g_histCoveragePending=true;g_histCoverageHardBlocked=false;
      g_histCoverageStatus="NAS HISTORY WAIT";g_histCoverageDetail=nasCacheDetail;
      g_histStatLine=g_histCoverageStatus+" | "+nasCacheDetail;
      g_histNeedsRedraw=InpAuditHistoryAutoRetry;
      g_histCoverageNextRetry=TimeLocal()+MathMax(2,InpAuditHistoryRetrySec);
      UpdateDashboard();ChartRedraw(0);
      if(!IsTesterMode()){EventKillTimer();EventSetTimer(5);}
      return;
   }
   SetHistoricalAuditProgress("PREP",1.0,6.0,0,ArraySize(g_maCrossAuditEvents));
   RenderHistoricalAuditProgress(true);
}

//=========================================================================
//  AUDIT ENGINE — Position Probe + History Scan
//=========================================================================
void OrbAudit_PositionProbe()
{
   // Professional lifecycle keeps excursions in persistent state and writes only on lifecycle events.
   OrbProUpdateOpenPositions();
}

void OrbAudit_HistoryScan()
{
   OrbProRecoverClosedPlans(false);
}
//=========================================================================
//  BRUTE-FORCE BACKTEST ENGINE (async state machine)
//=========================================================================
void OBT_GenerateCombos()
{
   ArrayResize(g_btCombos,0);
   int selectedTfIdx = RuntimeBtTfIndex();
   for(int ti=0;ti<OBT_TF_COUNT;ti++)
   {
   if(ti != selectedTfIdx) continue;
   for(int di=0;di<OBT_DELAY_COUNT;di++)
   for(int xm=0;xm<7;xm++)
   for(int em=0;em<OBT_ENTRY_COUNT;em++)
   for(int tm=0;tm<OBT_TARGET_COUNT;tm++)
   for(int a=0;a<2;a++)for(int v=0;v<2;v++)for(int d=0;d<2;d++)for(int b=0;b<2;b++)for(int ds=0;ds<2;ds++)for(int f=0;f<2;f++)
   {
      OrbBtCombo c;c.tfIdx=ti;c.delayIdx=di;c.exitMode=xm;c.entryMode=em;c.targetMode=tm;c.atr=(a==1);c.vol=(v==1);c.day=(d==1);c.be=(b==1);c.disp=(ds==1);c.fvgReq=(f==1);
      int n=ArraySize(g_btCombos);ArrayResize(g_btCombos,n+1);g_btCombos[n]=c;
   }
   }
   g_btTotal=ArraySize(g_btCombos);
}

void OBT_PrecomputeDays()
{
   datetime now=TimeCurrent();
   datetime nyNow=ServerToSessionLocal(now);MqlDateTime nySt;TimeToStruct(nyNow,nySt);
   datetime nyMid=MakeDateTime(nySt.year,nySt.mon,nySt.day,0,0,0);
   int maxDays=g_btWeeks*7;
   ArrayResize(g_btDays,maxDays);
   g_btDayCount=0;
   for(int back=maxDays-1;back>=0;back--)
   {
      datetime nyDay=nyMid-back*86400;MqlDateTime daySt;TimeToStruct(nyDay,daySt);
      if(daySt.day_of_week==0||daySt.day_of_week==6)continue;
      OrbBtDayCache dc;
      dc.nyY=daySt.year;dc.nyM=daySt.mon;dc.nyD=daySt.day;dc.dow=daySt.day_of_week;
      double hi,lo,avgV;datetime os,oe,te;int used;
      dc.valid=BuildOrbForNyDate(dc.nyY,dc.nyM,dc.nyD,hi,lo,os,oe,te,used,avgV);
      if(!dc.valid){g_btDays[g_btDayCount]=dc;g_btDayCount++;continue;}
      dc.orbHi=hi;dc.orbLo=lo;dc.avgVol=avgV;dc.orbStart=os;dc.orbEnd=oe;dc.tradeEnd=te;dc.used=used;
      dc.dailyAtr=HistDailyAtr(os,InpAtrPeriod);
      g_btDays[g_btDayCount]=dc;g_btDayCount++;
   }
   // Precompute breakouts for each (day, tf, delay) — Layer 2
   int slots=OBT_TF_COUNT*OBT_DELAY_COUNT;
   ArrayResize(g_btBreakouts,g_btDayCount*slots);
   for(int di=0;di<g_btDayCount;di++)
   {
      if(!g_btDays[di].valid){for(int k=0;k<slots;k++){g_btBreakouts[di*slots+k].found=false;}continue;}
      for(int ti=0;ti<OBT_TF_COUNT;ti++)
      for(int dli=0;dli<OBT_DELAY_COUNT;dli++)
      {
         int bIdx=ti*OBT_DELAY_COUNT+dli;
         OrbBtBreakout ob;ob.found=false;
         // Temporarily set runtime vars for FindHistBreakout
         ENUM_TIMEFRAMES saveTf=g_rtSignalTf;bool saveDly=g_rtUseDelay;int saveDlyM=g_rtDelayMin;
         g_rtSignalTf=g_btTFs[ti];g_rtUseDelay=(g_btDelays[dli]>0);g_rtDelayMin=g_btDelays[dli];
         string dir;datetime sigT;double sigC,sigH,sigL,sigVol,preAvgVol;
         if(FindHistBreakout(g_btDays[di].orbEnd,g_btDays[di].tradeEnd,g_btDays[di].orbHi,g_btDays[di].orbLo,
            dir,sigT,sigC,sigH,sigL,sigVol,preAvgVol))
         {
            ob.found=true;ob.dir=dir;ob.sigTime=sigT;ob.sigClose=sigC;ob.sigH=sigH;ob.sigL=sigL;
            ob.sigVol=sigVol;ob.preAvgVol=preAvgVol;
         }
         g_btBreakouts[di*slots+bIdx]=ob;
         g_rtSignalTf=saveTf;g_rtUseDelay=saveDly;g_rtDelayMin=saveDlyM;
      }
   }
}

void OBT_Start()
{
   if(g_btRunning) return;
   g_btWeeks=MathMax(1,g_btWeeks);g_btStartMs=GetTickCount();g_btElapsedMs=0;
   string coverageDetail="";bool hardBlocked=false;
   g_histCoverageAttempts++;
   if(!EnsureOrbAuditHistoryCoverage(g_btWeeks*7,coverageDetail,hardBlocked))
   {
      g_btLastResult=(hardBlocked?"HISTORY BLOCKED: ":"HISTORY SYNC: ")+coverageDetail;
      Print("OBT: ",g_btLastResult);
      UpdateDashboard();ChartRedraw(0);
      return;
   }
   g_histCoverageAttempts=0;
   OBT_GenerateCombos();
   OBT_PrecomputeDays();
   MqlDateTime d;TimeToStruct(TimeGMT(),d);
   g_btFileName="ORB15_BruteBacktest_"+StringFormat("%04d%02d%02d_%02d%02d%02d",d.year,d.mon,d.day,d.hour,d.min,d.sec)+".csv";
   int h=FileOpen(g_btFileName,FILE_CSV|FILE_WRITE|FILE_SHARE_READ,',');
   if(h!=INVALID_HANDLE)
   {
      FileWrite(h,"timestamp","symbol","chart_tf","signal_tf","delay_min","exit_mode","entry_mode","target_mode","atr_filter","vol_filter","day_filter","be_on_tp1","displacement_filter","fvg_required",
         "target_leg","halfbe_leg","fill_mode","same_bar_policy","native_parity","spread_pts","slippage_pts","commission_per_lot",
         "weeks","requested_from","day_count","total_signals","wins","losses","win_rate","net_r","pf","avg_r_per_trade");
      FileClose(h);
   }
   g_btStep=0;g_btRunning=true;g_btLastResult="Starting...";
   OBT_ProcessAudit("start","ok");
   Print("OBT: started ",g_btTotal," combos, ",g_btWeeks," weeks, ",g_btDayCount," days signal_tf=",TfLabel(g_rtSignalTf));
}

void OBT_Tick()
{
   if(!g_btRunning||g_btStep>=g_btTotal) return;
   OrbBtCombo combo=g_btCombos[g_btStep];
   int bIdx=combo.tfIdx*OBT_DELAY_COUNT+combo.delayIdx;
   int slots=OBT_TF_COUNT*OBT_DELAY_COUNT;
   OrbBtStats st;st.total=0;st.wins=0;st.losses=0;st.wonR=0;st.lostR=0;st.netR=0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.0001;
   for(int di=0;di<g_btDayCount;di++)
   {
      if(!g_btDays[di].valid) continue;
      OrbBtBreakout ob=g_btBreakouts[di*slots+bIdx];
      if(!ob.found) continue;
      // Apply filters
      if(combo.atr && g_btDays[di].dailyAtr>0)
      {
         double pct=((g_btDays[di].orbHi-g_btDays[di].orbLo)/g_btDays[di].dailyAtr)*100;
         if(pct<InpMinRangeAtrPct||pct>InpMaxRangeAtrPct) continue;
      }
      if(combo.vol && ob.preAvgVol>0 && ob.sigVol<ob.preAvgVol*g_rtVolumeMultiplier) continue;
      if(combo.day)
      {
         int dow=g_btDays[di].dow;bool ok=false;
         if(dow==1&&InpTradeMonday)ok=true;if(dow==2&&InpTradeTuesday)ok=true;
         if(dow==3&&InpTradeWednesday)ok=true;if(dow==4&&InpTradeThursday)ok=true;
         if(dow==5&&InpTradeFriday)ok=true;
         if(!ok) continue;
      }
      string modernReason="",modernDetail="";
      if(!ModernFilterAllows(g_btDays[di].orbEnd,g_btDays[di].tradeEnd,g_btTFs[combo.tfIdx],ob.sigTime,ob.dir,combo.disp,combo.fvgReq?ORB_FVG_REQUIRE:ORB_FVG_OFF,modernReason,modernDetail))
         continue;
      // Resolve the raw setup first; invert only the accepted execution side.
      ENUM_TIMEFRAMES saveResolveTf=g_rtSignalTf;ORB_ENTRY_MODE saveResolveEntry=g_rtEntryMode;
      g_rtSignalTf=g_btTFs[combo.tfIdx];g_rtEntryMode=(ORB_ENTRY_MODE)combo.entryMode;
      datetime entryT=ob.sigTime;
      double entry=ob.sigClose;
      string entryDetail="";
      bool entryOk=ResolveHistoricalEntry((ORB_ENTRY_MODE)combo.entryMode,ob.dir,ob.sigTime,ob.sigClose,g_btDays[di].orbHi,g_btDays[di].orbLo,g_btDays[di].tradeEnd,entryT,entry,entryDetail);
      g_rtSignalTf=saveResolveTf;g_rtEntryMode=saveResolveEntry;
      if(!entryOk) continue;
      string execDir=EffectiveOrbDirection(ob.dir);
      bool isBuy=(execDir=="BUY");
      bool sourceIsBuy=(ob.dir=="BUY");
      // Invert SL depends on the selected target mode, so establish the full
      // combo context before resolving geometry.
      ENUM_TIMEFRAMES saveTf=g_rtSignalTf;ORB_EXIT_ENGINE_MODE saveExit=g_rtExitMode;ORB_TARGET_MODE saveTarget=g_rtTargetMode;ORB_ENTRY_MODE saveEntry=g_rtEntryMode;
      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_rtSignalTf=g_btTFs[combo.tfIdx];g_rtExitMode=(ORB_EXIT_ENGINE_MODE)combo.exitMode;
      g_rtTargetMode=(ORB_TARGET_MODE)combo.targetMode;
      g_rtEntryMode=(ORB_ENTRY_MODE)combo.entryMode;
      g_orbHigh=g_btDays[di].orbHi;g_orbLow=g_btDays[di].orbLo;g_orbStartServer=g_btDays[di].orbStart;g_orbEndServer=g_btDays[di].orbEnd;g_tradeEndServer=g_btDays[di].tradeEnd;
      double buffer=MathMax(0,InpSlBufferPoints)*pt;
      double rawSl=sourceIsBuy?(g_btDays[di].orbLo-buffer):(g_btDays[di].orbHi+buffer);
      double sl=0.0,risk=0.0;string geometryDetail="";
      if(!ResolveExecutionStop(sourceIsBuy,isBuy,entry,rawSl,sl,risk,geometryDetail))
      {
         g_rtSignalTf=saveTf;g_rtExitMode=saveExit;g_rtTargetMode=saveTarget;g_rtEntryMode=saveEntry;g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
         continue;
      }
      double r1v=MathMax(0.1,InpTp1R),r2v=MathMax(0.1,InpTp2R),r3v=MathMax(0.1,InpTp3R);
      double tp1=NormalizePrice(isBuy?entry+risk*r1v:entry-risk*r1v);
      double tp2=NormalizePrice(isBuy?entry+risk*r2v:entry-risk*r2v);
      double tp3=NormalizePrice(isBuy?entry+risk*r3v:entry-risk*r3v);
      datetime nasExitBar=0,nasExitAt=0;double nasExitClose=0.0;string nasExitDetail="";
      datetime nasSearchEnd=TimeCurrent();
      if(RuntimeNasExitEnabled())
         FindNasOppositeExitWithGrace(execDir=="BUY"?1:-1,OrbSignalAvailableTime(entryT),nasSearchEnd,
            nasExitBar,nasExitAt,nasExitClose,nasExitDetail);
      datetime simEnd=g_btDays[di].tradeEnd;
      string nasExitOutcome=nasExitAt>0?(g_rtNasAdditionalExit?"NAS_ADDITIONAL_EXIT":"NAS_OPPOSITE_EXIT"):"";
      HistResult sim;
      if(g_rtNasAdditionalExit)
         sim=g_rtAdvancedAuditEngine
            ?SimulateHistoricalLifecycleAdvanced(entryT,g_btDays[di].tradeEnd,TimeCurrent(),entry,NormalizePrice(sl),isBuy,
               tp1,tp2,tp3,combo.be?1:0,simEnd,nasExitAt,nasExitOutcome)
            :SimulateHistoricalLifecycle(entryT,g_btDays[di].tradeEnd,TimeCurrent(),entry,NormalizePrice(sl),isBuy,
               tp1,tp2,tp3,combo.be?1:0,simEnd,nasExitAt,nasExitOutcome);
      else
         sim=SimulateTrade(entryT,g_btDays[di].tradeEnd,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,
            combo.be?1:0,true,nasExitAt,nasExitOutcome);
      g_rtSignalTf=saveTf;g_rtExitMode=saveExit;g_rtTargetMode=saveTarget;g_rtEntryMode=saveEntry;g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;      WriteInternalSimAudit("brute_combo",entryT,simEnd,execDir,entry,NormalizePrice(sl),sim,
         "raw_dir="+ob.dir+" exec_dir="+execDir+" invert="+(g_rtInvertMode?"1":"0")
         +" combo_tf="+TfLabel(g_btTFs[combo.tfIdx])+" delay="+IntegerToString(g_btDelays[combo.delayIdx])+" exit="+ExitModeLabel((ORB_EXIT_ENGINE_MODE)combo.exitMode)+" target="+TargetModeLabel((ORB_TARGET_MODE)combo.targetMode)+" "+entryDetail);
      st.total++;st.netR+=sim.netR;
      if(sim.netR>0){st.wonR+=sim.netR;st.wins++;}
      else if(sim.netR<0){st.lostR+=MathAbs(sim.netR);st.losses++;}
   }
   // Write CSV row
   OBT_WriteRow(combo,st);
   int res=st.wins+st.losses;
   double wr=res>0?(double)st.wins/res*100:0;
   g_btLastResult=TfLabel(g_btTFs[combo.tfIdx])+" D="+(g_btDelays[combo.delayIdx]>0?IntegerToString(g_btDelays[combo.delayIdx])+"m":"OFF")
      +" "+ExitModeLabel((ORB_EXIT_ENGINE_MODE)combo.exitMode)
      +" "+EntryModeLabel((ORB_ENTRY_MODE)combo.entryMode)
      +" "+TargetModeLabel((ORB_TARGET_MODE)combo.targetMode)
      +(combo.atr?" ATR":"")+(combo.vol?" VOL":"")+(combo.day?" DAY":"")+(combo.be?" BE":"")+(combo.disp?" DISP":"")+(combo.fvgReq?" FVG":"")
      +" "+IntegerToString(st.wins)+"W "+IntegerToString(st.losses)+"L WR="+DoubleToString(wr,1)+"% Net="+DoubleToString(st.netR,1)+"R";
   g_btStep++;
   if(g_btStep>=g_btTotal) OBT_Finish();
   UpdateDashboard();ChartRedraw(0);
}

void OBT_WriteRow(const OrbBtCombo &c,const OrbBtStats &s)
{
   int h=FileOpen(g_btFileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   int res=s.wins+s.losses;
   double wr=res>0?(double)s.wins/res*100:0;
   double pf=s.lostR>0?s.wonR/s.lostR:(s.wonR>0?99.9:0);
   double avgR=s.total>0?s.netR/s.total:0;
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      _Symbol,EnumToString(_Period),
      TfLabel(g_btTFs[c.tfIdx]),IntegerToString(g_btDelays[c.delayIdx]),
      ExitModeLabel((ORB_EXIT_ENGINE_MODE)c.exitMode),
      EntryModeLabel((ORB_ENTRY_MODE)c.entryMode),
      TargetModeLabel((ORB_TARGET_MODE)c.targetMode),
      (c.atr?"1":"0"),(c.vol?"1":"0"),(c.day?"1":"0"),(c.be?"1":"0"),(c.disp?"1":"0"),(c.fvgReq?"1":"0"),
      IntegerToString(RuntimeTargetLeg()),IntegerToString(c.be?1:0),
      BtFillLabel(g_btFillMode),BtSameBarLabel(g_btSameBarPolicy),(g_btNativeParity?"1":"0"),
      DoubleToString(g_btSpreadPts,2),DoubleToString(g_btSlippagePts,2),DoubleToString(g_btCommissionPerLot,2),
      IntegerToString(g_btWeeks),TimeToString(TimeCurrent()-g_btWeeks*7*86400,TIME_DATE|TIME_SECONDS),IntegerToString(g_btDayCount),
      IntegerToString(s.total),IntegerToString(s.wins),IntegerToString(s.losses),
      DoubleToString(wr,2),DoubleToString(s.netR,2),DoubleToString(pf,2),DoubleToString(avgR,3));
   FileClose(h);
}

void OBT_Finish()
{
   g_btRunning=false;
   g_btElapsedMs=GetTickCount()-g_btStartMs;
   uint elapsed=g_btElapsedMs;
   Print("OBT: COMPLETE ",g_btTotal," combos in ",elapsed,"ms -> ",g_btFileName);
   g_btLastResult="DONE "+IntegerToString(g_btTotal)+" combos in "+DoubleToString(g_btElapsedMs/1000.0,1)+"s";
   OBT_ProcessAudit("finish","completed");
   ArrayFree(g_btDays);ArrayFree(g_btCombos);g_btDayCount=0;
   ArrayResize(g_btBreakouts,0);
}

void OBT_Stop()
{
   if(!g_btRunning) return;
   g_btRunning=false;
   g_btLastResult="STOPPED at "+IntegerToString(g_btStep)+"/"+IntegerToString(g_btTotal);
   ArrayFree(g_btDays);ArrayFree(g_btCombos);g_btDayCount=0;
   ArrayResize(g_btBreakouts,0);
   Print("OBT: stopped at step ",g_btStep);
}

#include "OrbUltimate_RegimeMatrix.mqh"

//=========================================================================
//  DASHBOARD (Nas-inspired design with toggle buttons + TF selector)
//=========================================================================
#include "MaOrderFlowLeaderboard.mqh"
#include "MaOrderFlowSettings.mqh"
#include "OrbCustomRPicker.mqh"
#include "ResearchFiveYearData.mqh"
string ResearchLaunchKey(){return PREFIX+"BTN_FY_RESEARCH";}
bool ResearchSavedMatrixEnabled(const ResearchFiveYearRow &r)
{
   int slot=OrbUserSlot(r.id);
   if(slot<0)return false;
   bool enabled=false;int hours[];
   if(!TCalStrategyRead(g_userStrategies[slot].timeMatrix,enabled,hours)||!enabled)return false;
   for(int day=0;day<7;day++)if(hours[day]!=0)return true;
   return false;
}
bool ResearchApplyStrategy(const ResearchFiveYearRow &r)
{
   if(r.symbol!=_Symbol)return false;
   for(int i=0;i<OrbStrategyPresetCount();i++)
   {
      OrbStrategyPreset p;
      if(!OrbStrategyPresetLoad(i,p)||p.id!=r.id)continue;
      return OrbStrategyPresetApplyInteractive(i);
   }
   return false;
}
#include "../ResearchFiveYearLeaderboard.mqh"
void DrawDashboard()
{
   if(g_maOfRankOpen)return;
   if(!InpShowDashboard){DeleteDash();return;}
   OrbLibraryRefreshLayout();
   string ofKeys[],ofValues[];
   if(g_mcOfUiOpen)
   {
      for(int i=0;i<ObjectsTotal(0);i++)
      {
         string key=ObjectName(0,i);
         if(StringFind(key,PREFIX+"OF_UI_E_")!=0)continue;
         int n=ArraySize(ofKeys);ArrayResize(ofKeys,n+1);ArrayResize(ofValues,n+1);
         ofKeys[n]=key;ofValues[n]=ObjectGetString(0,key,OBJPROP_TEXT);
      }
      DeleteByPrefix(PREFIX+"OF_UI_");
   }
   int x=InpDashboardX,y=InpDashboardY;
   int W=620,H=758;

   // Shell
   CreateRect("DASH_BG",x,y,W,H,C'24,30,42',C'90,178,255');
   CreateRect("DASH_LIBRARY_BG",x+632,y,W,670,C'24,30,42',C'90,178,255');
   DeleteByPrefix(PREFIX+"DASH_BT");DeleteByPrefix(PREFIX+"BTN_BT");DeleteByPrefix(PREFIX+"EDIT_BT");
   ObjectDelete(0,PREFIX+"DASH_SEP4");
   CreateRect("DASH_TOP",x,y,W,28,C'18,24,36',C'90,178,255');
   CreateRect("DASH_STRIPE",x+6,y+6,W-12,3,C'90,178,255',C'90,178,255');

   // Title
   CreateLabel("DASH_TITLE",x+12,y+10,"ENTRY ENGINE LAB // "+ORB15_BUILD,C'216,222,230',9);

   UpdateDashboard();
   for(int i=0;i<ArraySize(ofKeys);i++)
      if(ObjectFind(0,ofKeys[i])>=0)ObjectSetString(0,ofKeys[i],OBJPROP_TEXT,ofValues[i]);
}

#include "NativeMarginPreview.mqh"
void RenderNativeBalance()
{
   int x=InpDashboardX+644,y=InpDashboardY+530;
   CreateLabel("DASH_NATIVE_BALANCE",x,y+4,"BALANCE (0=ACCOUNT)",C'184,196,210',8);
   CreateEdit("EDIT_NATIVE_BALANCE",x+158,y,108,22,DoubleToString(g_nativeRiskBalance,2));
   CreateButton("BTN_NATIVE_BALANCE",x+274,y,98,22,"APPLY BAL",C'38,101,176');
   CreateLabel("DASH_NATIVE_BUDGET",x,y+29,"NATIVE 1R BUDGET: "+DoubleToString(RiskBudgetMoney(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+" | listener % unchanged",C'80,255,180',8);
   ObjectSetString(0,PREFIX+"EDIT_NATIVE_BALANCE",OBJPROP_TOOLTIP,"Native MT5 percentage-risk reference capital in account currency. 0 restores the existing account basis. MONEY mode takes priority. Future entries only; risk settings stay separate from strategies.");
}
void UpdateDashboard()
{
   if(g_maOfRankOpen)return;
   if(!InpShowDashboard)return;
   OrbLibraryRefreshLayout();
   int x=InpDashboardX+632,y=InpDashboardY;
   int W=620;
   color acB=C'90,178,255';color muted=C'184,196,210';color steel=C'216,222,230';

   CreateButton("BTN_OF_RESULTS",InpDashboardX+350,InpDashboardY+10,96,17,"OF RESULTS",C'38,101,176');
   CreateButton("BTN_ORDERFLOW",InpDashboardX+452,InpDashboardY+10,100,17,McOfModeName(),g_mcOf.mode==0?C'80,80,80':C'30,120,70');
   CreateButton("BTN_OF_SETTINGS",InpDashboardX+558,InpDashboardY+10,48,17,"OF SET",C'38,101,176');
   ObjectSetString(0,PREFIX+"BTN_ORDERFLOW",OBJPROP_TOOLTIP,"Cycle OFF / BREAKOUT / REJECTION / EITHER / PROFILE / ACTIVITY / DELTA. Quote-tick proxy, not exchange flow. "+g_mcOfStatus);
   OrbStrategyPresetSyncSelection();
   OrbUserDraw();RenderNativeBalance();RenderNativeMarginPreview(InpDashboardX+644,InpDashboardY+400,LabPolicyEnabled());
   CreateLabel("DASH_PRESET_TITLE",x+12,y+34,"STRATEGIES",C'255,187,92',8);
   CreateEdit("EDIT_PRESET_SEARCH",x+94,y+30,286,20,g_strategySearch);
   CreateButton("BTN_PRESET_SEARCH",x+386,y+30,76,20,"SEARCH",C'38,101,176');
   bool presetApplied=(g_strategyApplyFlashUntil>TimeLocal());
   CreateButton("BTN_PRESET_APPLY",x+468,y+30,138,20,presetApplied?"APPLIED":"APPLY STRATEGY",
      presetApplied?C'30,150,95':C'184,103,22');
   CreateLabel("DASH_PRESET_FILTER",x+12,y+59,"1Y FILTER",C'134,158,182',7);
   CreateLabel("DASH_PRESET_NET_L",x+74,y+59,"R >=",C'134,158,182',7);
   CreateEdit("EDIT_PRESET_NET",x+104,y+54,52,18,g_strategyFilterNetText);
   CreateLabel("DASH_PRESET_WR_L",x+164,y+59,"WR >=",C'134,158,182',7);
   CreateEdit("EDIT_PRESET_WR",x+202,y+54,48,18,g_strategyFilterWrText);
   CreateLabel("DASH_PRESET_MC_L",x+258,y+59,"MC >=",C'134,158,182',7);
   CreateEdit("EDIT_PRESET_MC",x+298,y+54,52,18,g_strategyFilterMinCumText);
   bool metricFilterActive=g_strategyFilterNetEnabled||g_strategyFilterWrEnabled||g_strategyFilterMinCumEnabled||g_strategyFilterGeometryEnabled||g_strategyFilterPair!="";
   CreateButton("BTN_PRESET_FILTER",x+358,y+54,92,18,"APPLY FILTER",metricFilterActive?C'30,150,95':C'38,101,176');
   CreateButton("BTN_PRESET_FILTER_CLEAR",x+456,y+54,62,18,"CLEAR",C'80,80,80');
   CreateLabel("DASH_PRESET_FILTER_COUNT",x+526,y+59,IntegerToString(ArraySize(g_strategyMatches))+"/"+IntegerToString(OrbStrategyPresetCount()),
      metricFilterActive?C'80,255,180':C'134,158,182',7);
   CreateButton("BTN_PRESET_FAVORITES",x+12,y+78,122,20,g_strategyFavoritesOnly?"FAVORITES ONLY":"ALL STRATEGIES",
      g_strategyFavoritesOnly?C'184,103,22':C'38,101,176');
   CreateLabel("DASH_PRESET_GEOMETRY_L",x+146,y+83,"TP/SL R =",C'134,158,182',7);
   CreateEdit("EDIT_PRESET_GEOMETRY",x+218,y+78,76,20,g_strategyFilterGeometryText);
   ObjectSetString(0,PREFIX+"EDIT_PRESET_GEOMETRY",OBJPROP_TOOLTIP,"Exact target/SL ratio after inversion; blank = all. Use APPLY FILTER.");
   CreateButton("BTN_PRESET_SYMBOL",x+304,y+78,140,20,"PAIR: "+(g_strategyFilterPair==""?"ALL":g_strategyFilterPair),
      g_strategyFilterPair==""?C'38,101,176':C'30,150,95');
   ObjectSetString(0,PREFIX+"BTN_PRESET_SYMBOL",OBJPROP_TOOLTIP,"Cycle ALL and every pair present in saved and built-in strategies. Library filter only.");
   CreateButton("BTN_FY_RESEARCH",x+454,y+78,152,20,"5Y LEADERBOARD",C'38,101,176');
   ObjectDelete(0,PREFIX+"DASH_PRESET_FAV_HINT");
   CreateLabel("DASH_PRESET_CURRENT",x+12,y+106,"CURRENT: "+OrbStrategyPresetCurrentName(),C'184,196,210',7);
   CreateLabel("DASH_PRESET_PICK",x+12,y+122,"PICK: "+OrbStrategyPresetCandidateName(),C'184,196,210',7);

   x=InpDashboardX;
   int rootY=InpDashboardY;
   RegimeV3Update(false);
   int currentRegime=OrbRegimeBucket(g_regimeV3);
   string regimeNow=currentRegime>=0?OrbRegimeName(currentRegime):"WAITING DATA";
   CreateLabel("DASH_REG_TITLE",x+12,rootY+34,"REGIME REF STATS // NOW: "+regimeNow,
      currentRegime>=0?RegimeV3CoreColor():C'145,160,180',8);
   int regW=194,regH=18,regGap=5;
   for(int ri=0;ri<ORB_REGIME_COUNT;ri++)
   {
      int col=ri%3,row=ri/3;
      string txt=(ri==currentRegime?"> ":"")+OrbRegimeStatsText(ri)+(g_regimeAllowed[ri]?"":" BLOCK");
      color bg=g_regimeAllowed[ri]?C'58,126,178':C'42,47,57';
      CreateButton("BTN_REG_"+IntegerToString(ri),x+12+col*(regW+regGap),rootY+48+row*22,regW,regH,txt,bg);
   }

   CreateLabel("DASH_RF_TITLE",x+12,rootY+92,"EXPERIMENTAL LIQ RF TRANSFER // STATS IGNORE TOGGLES",C'255,187,92',8);
   CreateButton("BTN_RF_MASTER",x+500,rootY+90,106,18,g_orbRfEnabled?"RF MASTER ON":"RF MASTER OFF",
      g_orbRfEnabled?C'184,103,22':C'80,80,80');
   int rfW=144,rfH=18,rfGap=5;
   for(int rf=0;rf<ORB_RF_COUNT;rf++)
   {
      int col=rf%4,row=rf/4;
      string txt=OrbRfStatsText(rf)+(g_orbRfBlocked[rf]?" BLOCK":" PASS");
      color bg=g_orbRfBlocked[rf]?C'42,47,57':C'58,126,178';
      CreateButton("BTN_RF_"+IntegerToString(rf),x+12+col*(rfW+rfGap),rootY+106+row*22,rfW,rfH,txt,bg);
   }
   // NAS controls are deliberately isolated from session and bridge controls.
   CreateRect("DASH_NAS_SEP",x+8,rootY+176,W-16,1,C'65,116,172',C'65,116,172');
   CreateLabel("DASH_NAS_TITLE",x+12,rootY+183,"NAS // "+RuntimeNasModeLabel(),C'90,178,255',8);
   CreateButton("BTN_NAS_CONFIRM",x+140,rootY+179,108,18,g_rtNasConfirmation?"ENTRY GATE ON":"ENTRY GATE OFF",
      g_rtNasConfirmation?C'30,150,95':C'80,80,80');
   CreateButton("BTN_NAS_EXIT",x+252,rootY+179,104,18,g_rtNasExitOnOppositeSignal?"OPP EXIT ON":"OPP EXIT OFF",
      g_rtNasExitOnOppositeSignal?C'184,103,22':C'80,80,80');
   CreateButton("BTN_NAS_ADD_EXIT",x+360,rootY+179,100,18,g_rtNasAdditionalExit?"ADD EXIT ON":"ADD EXIT OFF",
      g_rtNasAdditionalExit?C'202,126,38':C'80,80,80');
   CreateLabel("DASH_NAS_TF",x+464,rootY+183,NasTimeframeButtonLabel(),C'90,178,255',7);
   CreateLabel("DASH_NAS_SENS",x+526,rootY+183,"SENS",C'134,158,182',7);
   CreateEdit("EDIT_NAS_SENS",x+566,rootY+179,40,18,IntegerToString(g_rtNasSensitivity));
   CreateLabel("DASH_NAS_LB",x+12,rootY+205,"ACTIVE LOOKBACK MIN",C'134,158,182',7);
   CreateEdit("EDIT_NAS_LOOKBACK",x+130,rootY+201,52,18,IntegerToString(g_rtNasActiveSignalLookbackMinutes));
   CreateLabel("DASH_NAS_WAIT",x+188,rootY+205,"EXIT WAIT",C'134,158,182',7);
   CreateEdit("EDIT_NAS_EXIT_WAIT",x+252,rootY+201,52,18,DurationMinutesText(g_rtNasOppositeExitWaitMinutes));
   bool nasApplied=(g_nasApplyFlashUntil>TimeLocal());
   CreateButton("BTN_NAS_APPLY",x+310,rootY+201,86,18,nasApplied?"APPLIED":"APPLY NAS",
      nasApplied?C'30,150,95':C'38,101,176');
   datetime nasEligibleAt=NasOppositeExitEligibleAt(g_nasManagedStartAt);
   string nasState="IDLE";
   if(g_nasManagedClosePending)nasState="CLOSE PENDING";
   else if(g_nasManagedLifecycle&&nasEligibleAt>TimeCurrent())
      nasState="GRACE "+DurationMinutesText((int)MathCeil((double)(nasEligibleAt-TimeCurrent())/60.0));
   else if(g_nasManagedLifecycle)nasState="LIVE "+g_nasManagedRawDir;
   else if(g_nasPending)nasState="WAIT "+g_nasPendingDir;
   nasState+=" | S"+IntegerToString(g_rtNasSensitivity)
      +" | SV "+(g_rtNasVolumeFilter?("ONx"+DoubleToString(g_rtNasVolumeMultiplier,2)):"OFF")
      +" FV "+(g_rtNasFlowVolumeFilter?("ONx"+DoubleToString(g_rtNasFlowVolumeMultiplier,2)):"OFF")
      +" | EXIT "+(g_rtNasAdditionalExit?"ADD":(g_rtNasExitOnOppositeSignal?"OPP":"OFF"))
      +" | NAS S"+IntegerToString(g_lastNasStateAllowedEventCount)+" F"+IntegerToString(g_lastNasFlowAllowedEventCount)
      +"/"+IntegerToString(g_lastNasRawEventCount)
      +(g_lastNasVolumeMissingCount>0?(" M"+IntegerToString(g_lastNasVolumeMissingCount)):"");
   CreateLabel("DASH_NAS_STATE",x+402,rootY+205,nasState,
      g_nasManagedClosePending?C'255,95,140':(g_nasManagedLifecycle?C'80,255,180':C'184,196,210'),7);
   CreateButton("BTN_NAS_VOL",x+12,rootY+223,106,18,g_rtNasVolumeFilter?"STATE VOL ON":"STATE VOL OFF",
      g_rtNasVolumeFilter?C'30,150,95':C'80,80,80');
   CreateLabel("DASH_NAS_VOL_X",x+126,rootY+227,"STATE X",C'134,158,182',7);
   CreateEdit("EDIT_NAS_VOL_X",x+170,rootY+223,52,18,DoubleToString(g_rtNasVolumeMultiplier,2));
   CreateButton("BTN_NAS_STATE_GATE",x+230,rootY+223,116,18,g_rtNasStateGate?"STATE GATE ON":"STATE GATE OFF",
      g_rtNasStateGate?C'30,150,95':C'80,80,80');
   CreateLabel("DASH_NAS_VOL_RULE",x+354,rootY+227,"LATEST CAUSAL NAS; NO AGE LIMIT",C'134,158,182',7);
   CreateButton("BTN_NAS_FLOW_VOL",x+12,rootY+245,106,18,g_rtNasFlowVolumeFilter?"FLOW VOL ON":"FLOW VOL OFF",
      g_rtNasFlowVolumeFilter?C'30,150,95':C'80,80,80');
   CreateLabel("DASH_NAS_FLOW_VOL_X",x+126,rootY+249,"FLOW X",C'134,158,182',7);
   CreateEdit("EDIT_NAS_FLOW_VOL_X",x+170,rootY+245,52,18,DoubleToString(g_rtNasFlowVolumeMultiplier,2));
   CreateLabel("DASH_NAS_FLOW_RULE",x+230,rootY+249,"ENTRY GATE + OPP EXIT + ADD EXIT",C'134,158,182',7);
   CreateLabel("DASH_MA_MODE",x+12,rootY+271,"SIGNAL MODE / PAIR",C'90,178,255',8);
   CreateButton("BTN_LAB_ENGINES",x+100,rootY+267,330,18,"ENGINE: "+MaCrossModeText(g_rtMaCrossMode),C'38,101,176');
   CreateButton("BTN_LAB_BUILD",x+436,rootY+267,170,18,"ENTRY BUILDER",C'184,103,22');
   for(int pair=0;pair<=2;pair++)
   {
      MA_CROSS_PAIR candidate=(MA_CROSS_PAIR)pair;
      bool active=(candidate==g_rtMaCrossPair);
      CreateButton("BTN_MA_PAIR_"+IntegerToString(pair),x+100+pair*68,rootY+287,64,18,
         MaCrossPairText(candidate),active?C'38,101,176':C'80,80,80');
   }
   CreateButton("BTN_MA_INDEPENDENT",x+310,rootY+287,108,18,g_maIndependent?"INDEPENDENT":"LEGACY",g_maIndependent?C'38,101,176':C'80,80,80');
   CreateLabel("DASH_MA_MAX",x+424,rootY+291,"MAX SERIES",C'134,158,182',7);
   CreateEdit("EDIT_MA_MAX",x+493,rootY+287,40,18,IntegerToString(g_maMaxConsecutive));
   CreateButton("BTN_MA_MAX_APPLY",x+539,rootY+287,65,18,"APPLY",C'38,101,176');
   CreateButton("BTN_MA_REV_EXIT",x+12,rootY+309,140,18,g_maReverseExit?"MA REV EXIT ON":"MA REV EXIT OFF",g_maReverseExit?C'30,150,95':C'80,80,80');
   CreateLabel("DASH_MA_REV_WAIT",x+160,rootY+313,"WAIT HH:MM",C'134,158,182',7);
   CreateEdit("EDIT_MA_REV_WAIT",x+245,rootY+309,60,18,DurationMinutesText(g_maReverseWait));
   CreateButton("BTN_MA_REV_APPLY",x+313,rootY+309,90,18,"APPLY EXIT",C'38,101,176');
   MaRenderOpenCounter(true);
   y=rootY+312;

   // Status line
   string state=g_rtEaEnabled?"EA ON":"EA OFF";
   string orb=g_orbReady?"READY":"WAIT";
   string exec=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG?"3-LEG":"SINGLE "+TargetLabel()+" "+HalfBeLabel();
   CreateLabel("DASH_L1",x+12,y+34,state+" | MA "+MaCrossModeText(g_rtMaCrossMode)+"/"+MaCrossPairText(g_rtMaCrossPair)+" | MA candle context | "+exec+" | "+RuntimeEntryLabel()+" | Signal: "+TfLabel(g_rtSignalTf),
      g_rtEaEnabled?C'80,255,180':C'221,55,78',8);

   // ORB info
   string delayTxt=g_rtUseDelay?IntegerToString(g_rtDelayMin)+"m delay":"no delay";
   CreateLabel("DASH_L2",x+12,y+50,
      SessionClockLabel()+" | GMT+"+DoubleToString(InpBrokerGmtOffsetHours,1)
      +" | "+delayTxt+" | "+EntryWindowLabel()+" | Spread "+IntegerToString(CurrentSpreadPoints())+"pt",
      muted,8);
   CreateLabel("DASH_L3",x+12,y+66,
      "ORB H "+DoubleToString(g_orbHigh,_Digits)+" L "+DoubleToString(g_orbLow,_Digits)
      +" | Risk "+DoubleToString(EffRiskPerTradePct(),1)+"% | Mode "+RuntimeRiskModeLabel()+" | "+RuntimeInvertLabel()+" | "+(g_rtDisplacement?"DISP ON":"DISP OFF")+" | "+FvgModeLabel(),
      clrWhite,8);

   // Separator
   CreateRect("DASH_SEP1",x+8,y+82,W-16,1,C'65,116,172',C'65,116,172');

   // Row 1: Filter toggle buttons
   CreateLabel("DASH_FLBL",x+12,y+88,"FILTERS:",acB,8);
   int bx=x+80,by=y+86,bw=58,bh=18,gap=3;
   ObjectDelete(0,PREFIX+"BTN_ATR"); // ORB range/ATR is not a MA candidate filter.
   CreateButton("BTN_VOL",bx+bw+gap,by,bw,bh,g_rtFilterVol?"VOL:ON":"VOL:OFF",g_rtFilterVol?C'30,120,70':C'80,80,80');
   CreateButton("BTN_DAY",bx+2*(bw+gap),by,bw,bh,g_rtFilterDay?"DAY:ON":"DAY:OFF",g_rtFilterDay?C'30,120,70':C'80,80,80');
   CreateButton("BTN_TIME",bx+3*(bw+gap),by,bw,bh,g_rtTimeExit?"TIME":"TIME:OFF",g_rtTimeExit?C'30,120,70':C'80,80,80');
   CreateButton("BTN_DISP",bx+4*(bw+gap),by,bw+8,bh,g_rtDisplacement?"DISP:ON":"DISP:OFF",g_rtDisplacement?C'30,120,70':C'80,80,80');
   CreateButton("BTN_FVG",bx+5*(bw+gap)+8,by,bw+22,bh,FvgModeLabel(),g_rtFvgMode==ORB_FVG_REQUIRE?C'178,92,37':(g_rtFvgMode==ORB_FVG_OPTIONAL?C'38,101,176':C'80,80,80'));
   int xp=bx+5*(bw+gap)+8+(bw+22)+4;
   CreateButton("BTN_XSTART",xp,by,58,bh,g_rtExitTrailStartLeg<=0?"XS:NOW":"XS:TP"+IntegerToString(g_rtExitTrailStartLeg),g_rtExitTrailStartLeg>0?C'38,101,176':C'80,80,80');
   string xParam=g_rtExitMode==ORB_EXIT_EMA_STOP?("EMA"+IntegerToString(g_rtExitEmaPeriod)):("ATR"+DoubleToString(g_rtExitAtrMultiplier,1));
   CreateButton("BTN_XPARAM",xp+62,by,62,bh,xParam,C'38,101,176');

   // Row 2: Signal TF selector + Delay toggle + EA toggle + Close All
   int r2y=y+108;
   CreateLabel("DASH_TFLBL",x+12,r2y+2,"SIGNAL:",acB,8);
   CreateButton("BTN_TF",x+80,r2y,60,18,"TF:"+TfLabel(g_rtSignalTf),C'38,101,176');
   ObjectDelete(0,PREFIX+"BTN_DELAY"); // No opening-range delay in the MA stream.
   CreateButton("BTN_HC",x+228,r2y,70,18,HalfBeLabel(),RuntimeHalfBeLeg()>0?C'30,120,70':C'80,80,80');
   CreateButton("BTN_TP",x+302,r2y,82,18,"FIX "+TargetLabel(),C'38,101,176');
   CreateButton("BTN_TMODE",x+388,r2y,76,18,RuntimeTargetModeLabel(),g_rtTargetMode==ORB_TARGET_R_LEG?C'80,80,80':C'38,101,176');

   DirectionLauncher(PREFIX,x+12,y+330);
   LossHoursLauncher(PREFIX,OrbLibraryX(x+480),OrbLibraryY(y+330),g_libraryDashScale);
   DailyQuotaLauncher(PREFIX,OrbLibraryX(InpDashboardX+12),OrbLibraryY(InpDashboardY+728),g_libraryDashScale);
   CreateLabel("DASH_DIRECTION_LOSSES",x+134,y+334,"MinCum "+DoubleToString(g_histMinCumulativeR,2)+"R | "+DirectionLossText(),muted,8);
   CreateButton("BTN_EA",x+468,r2y,54,18,g_rtEaEnabled?"EA ON":"EA OFF",g_rtEaEnabled?C'30,150,95':C'178,37,57');
   CreateButton("BTN_FTMO",x+526,r2y,46,18,g_ftmoMode?"FTMO":"FTMO",g_ftmoMode?C'30,150,95':C'80,80,80');
   CreateButton("BTN_RISKLOT",x+576,r2y,42,18,g_riskLotOnlyMode?"RISK":"RISK",g_riskLotOnlyMode?C'30,150,95':C'80,80,80');
   int auditY=y;
   y-=140;
   CreateLabel("DASH_RISK_LABEL",x+12,y+494,"RISK %",acB,8);
   CreateEdit("EDIT_RISK_PCT",x+66,y+490,66,18,DoubleToString(EffRiskPerTradePct(),2));
   bool riskApplied=(g_riskApplyFlashUntil>TimeLocal());
   CreateButton("BTN_APPLY_RISK",x+138,y+490,92,18,riskApplied?"APPLIED":"APPLY RISK",riskApplied?C'30,150,95':C'38,101,176');
   CreateLabel("DASH_RISK_VALUE",x+236,y+494,DoubleToString(EffRiskPerTradePct(),2)+"%",riskApplied?C'80,255,180':muted,8);
   CreateButton("BTN_EXIT",x+326,y+490,94,18,RuntimeExitLabel(),g_rtExitMode==ORB_EXIT_FIXED_TARGET?C'80,80,80':C'38,101,176');
   bool volApplied=(g_volApplyFlashUntil>TimeLocal());
   CreateLabel("DASH_VOL_LABEL",x+12,y+517,"VOL X",acB,8);
   CreateEdit("EDIT_VOL_MULT",x+54,y+513,54,18,DoubleToString(g_rtVolumeMultiplier,2));
   CreateButton("BTN_APPLY_VOL",x+114,y+513,92,18,volApplied?"APPLIED":"APPLY VOL",volApplied?C'30,150,95':C'38,101,176');
   CreateButton("BTN_INVERT",x+222,y+513,98,18,g_rtInvertMode?"INV ON":"INV OFF",
      g_rtInvertMode?C'184,103,22':C'80,80,80');
   ObjectDelete(0,PREFIX+"BTN_ADV_REVERSE");
   CreateLabel("DASH_ADV_COST",x+326,y+517,"GAP%",acB,8);
   CreateEdit("EDIT_ADV_COST",x+360,y+513,42,18,DoubleToString(g_rtAdvancedReverseMaxCostPct,2));
   ObjectSetString(0,PREFIX+"EDIT_ADV_COST",OBJPROP_TOOLTIP,
      "Max inverse quote gap and 1R TP erosion in percent; 10 requires at least 0.90R gross TP. 100 disables.");
   CreateButton("BTN_APPLY_ADV_COST",x+406,y+513,41,18,"SET",C'38,101,176');
   CreateButton("BTN_CLOSEALL",x+454,y+513,76,18,"CLOSE ALL",C'178,37,57');
   CreateButton("BTN_BRIDGE_PUB",x+424,y+490,58,18,g_orbBridgeEnabled?"PUB ON":"PUB OFF",g_orbBridgeEnabled?C'30,150,95':C'80,80,80');
   CreateButton("BTN_BRIDGE_ONLY",x+486,y+490,62,18,g_orbBridgeOnly?"ONLY ON":"ONLY OFF",g_orbBridgeOnly?C'120,88,25':C'80,80,80');
   CreateButton("BTN_BRIDGE_NATIVE",x+552,y+490,52,18,g_orbNativeWithBridgeOnly?"NAT ON":"NAT OFF",g_orbNativeWithBridgeOnly?C'184,103,22':C'80,80,80');
   ObjectDelete(0,PREFIX+"BTN_UTC_SESSION");
   bool winApplied=(g_entryWindowApplyFlashUntil>TimeLocal());
   CreateButton("BTN_ENTRY_WINDOW",x+12,y+536,74,18,g_rtEntryWindow?"WIN ON":"WIN OFF",g_rtEntryWindow?C'30,150,95':C'80,80,80');
   CreateEdit("EDIT_ENTRY_WIN_START",x+92,y+536,52,18,ClockMinutesText(g_rtEntryWindowStartMin));
   CreateEdit("EDIT_ENTRY_WIN_END",x+150,y+536,52,18,ClockMinutesText(g_rtEntryWindowEndMin));
   CreateButton("BTN_ENTRY_WIN_APPLY",x+208,y+536,90,18,winApplied?"APPLIED":"APPLY GMT",winApplied?C'30,150,95':C'38,101,176');
   CreateButton("BTN_FILTER_REVERSE",x+304,y+536,52,18,
      g_rtFilteredWindowReverseExit?"REV EXIT":"REV HOLD",
      g_rtFilteredWindowReverseExit?C'184,103,22':C'80,80,80');
   CreateButton("BTN_DISP_BLOCK_EXIT",x+360,y+536,52,18,
      g_rtPostTradeDispBlockExit?"DSP EXIT":"DSP HOLD",
      g_rtPostTradeDispBlockExit?C'184,103,22':C'80,80,80');
   CreateLabel("DASH_BRIDGE_CH",x+424,y+540,"CH",C'134,158,182',8);
   CreateEdit("EDIT_BRIDGE_CH",x+448,y+536,42,18,IntegerToString(g_orbBridgeChannel));
   CreateButton("BTN_BRIDGE_CH_APPLY",x+494,y+536,88,18,"APPLY CH",C'38,101,176');
   y=auditY;

   // Separator
   CreateRect("DASH_SEP2",x+8,y+132,W-16,1,C'65,116,172',C'65,116,172');

   // Stats section
   int resolved=g_histWins+g_histLosses;
   double wr=resolved>0?(double)g_histWins/(double)resolved*100.0:0;
   color pnlClr=g_histNetMoney>1e-8?C'80,255,180':(g_histNetMoney<-1e-8?C'255,95,140':C'184,196,210');

   CreateLabel("DASH_STITLE",x+12,y+138,HistoricalWindowLabel()+" AUDIT+CHART ("+TfLabel(g_rtSignalTf)+")",acB,9);
   int awx=x+240,awy=y+138,awg=3;
   CreateButton("BTN_AUD_2W",awx,awy,34,18,"2W",g_rtHistoricalWeeks==2?C'38,101,176':C'80,80,80');awx+=34+awg;
   CreateButton("BTN_AUD_5W",awx,awy,34,18,"5W",g_rtHistoricalWeeks==5?C'38,101,176':C'80,80,80');awx+=34+awg;
   CreateButton("BTN_AUD_10W",awx,awy,38,18,"10W",g_rtHistoricalWeeks==10?C'38,101,176':C'80,80,80');awx+=38+awg;
   CreateButton("BTN_AUD_20W",awx,awy,38,18,"20W",g_rtHistoricalWeeks==20?C'38,101,176':C'80,80,80');awx+=38+awg;
   CreateButton("BTN_AUD_1Y",awx,awy,34,18,"1Y",g_rtHistoricalWeeks==52?C'38,101,176':C'80,80,80');awx+=34+awg;
   CreateButton("BTN_AUD_2Y",awx,awy,34,18,"2Y",g_rtHistoricalWeeks==104?C'38,101,176':C'80,80,80');awx+=34+awg;
   CreateButton("BTN_AUD_3Y",awx,awy,34,18,"3Y",g_rtHistoricalWeeks==156?C'38,101,176':C'80,80,80');awx+=34+awg;
   CreateButton("BTN_AUD_4Y",awx,awy,34,18,"4Y",g_rtHistoricalWeeks==208?C'38,101,176':C'80,80,80');awx+=34+awg;
   CreateButton("BTN_AUD_5Y",awx,awy,34,18,"5Y",g_rtHistoricalWeeks==260?C'38,101,176':C'80,80,80');
   CreateButton("BTN_ENTRY",x+412,y+160,102,18,RuntimeEntryLabel(),g_rtEntryMode==ORB_ENTRY_BREAKOUT?C'80,80,80':(g_rtEntryMode==ORB_ENTRY_IMBALANCE_M1?C'38,101,176':C'178,92,37'));
   CreateButton("BTN_AUDIT",x+522,y+160,86,18,g_auditRuntime?"AUDIT":"AUDIT OFF",g_auditRuntime?C'120,88,25':C'80,80,80');
   string auditStat1=IntegerToString(g_histTotal)+" signals | "+IntegerToString(g_histWins)+" W  "+IntegerToString(g_histLosses)+" L  "+IntegerToString(g_histOpen)+" O  "+IntegerToString(g_histFlat)+" F | WR "+DoubleToString(wr,1)+"% | SL "+IntegerToString(g_histStopLossExits)+"  NAS-X "+IntegerToString(g_histNasOppositeExits)+"  MA-REV "+IntegerToString(g_histNewDayReverseExits);
   double pf=g_histLostR>0.0?g_histWonR/g_histLostR:(g_histWonR>0.0?99.0:0.0);
   string auditStat2="Net R: "+DoubleToString(g_histNetR,1)+"R"
      +" | Net $: "+(g_histNetMoney>=0?"+":"")+DoubleToString(g_histNetMoney,2)
      +" | MinCum: "+DoubleToString(g_histMinCumulativeR,2)+"R/$"+DoubleToString(g_histMinCumulativeMoney,2)
      +" | PeakDD: "+DoubleToString(g_histMaxPeakDrawdownR,2)+"R/$"+DoubleToString(g_histMaxPeakDrawdownMoney,2)
      +" | Avg W/L: +"+DoubleToString(g_histWins>0?g_histWonR/(double)g_histWins:0,2)+"/-"+DoubleToString(g_histLosses>0?g_histLostR/(double)g_histLosses:0,2)+"R"
      +" | PF "+DoubleToString(pf,2)+(g_histInvalid>0?" | DATA "+IntegerToString(g_histInvalid):"")+(g_histFlat>0?" | FLAT "+IntegerToString(g_histFlat):"");
   color auditStatColor=pnlClr;
   if(g_histCoveragePending)
   {
      auditStat1=g_histCoverageStatus;
      auditStat2=g_histCoverageHardBlocked
         ?(StringFind(g_histCoverageStatus,"TICK HISTORY")>=0?g_histCoverageDetail:"Set Tools > Options > Charts > Max bars, restart MT5, then reselect audit window.")
         :"Downloading/building history; automatic retry is active.";
      auditStatColor=g_histCoverageHardBlocked?C'255,80,110':C'255,204,82';
   }
   else if(g_rtInvertMode&&g_histInvalid>0&&g_histWins+g_histLosses+g_histOpen+g_histFlat==0)
   {
      auditStat1="INVERSE AUDIT INCOMPLETE: TICK DATA";
      auditStat2="No W/L verdict | "+g_histFirstInvalidReason
         +" | source bars alone cannot prove the Bid/Ask exit order.";
      auditStatColor=C'255,204,82';
   }
   CreateLabel("DASH_STAT1",x+12,y+156,auditStat1,auditStatColor,9);
   auditStat2="RAW "+IntegerToString(ArraySize(g_maCrossAuditEvents))+" | HELD "+IntegerToString(g_maAuditHeldCandidates)+" | "+auditStat2;
   CreateLabel("DASH_STAT2",x+12,y+174,auditStat2,muted,8);

   // Weekday results use the same accepted-trade universe and net-R verdict
   // as the headline audit. Open, flat, invalid and filtered setups are excluded.
   CreateLabel("DASH_WD_MON",x+12,y+190,OrbWeekdayAuditText(1,"MON"),OrbWeekdayAuditColor(1),7);
   CreateLabel("DASH_WD_TUE",x+210,y+190,OrbWeekdayAuditText(2,"TUE"),OrbWeekdayAuditColor(2),7);
   CreateLabel("DASH_WD_WED",x+408,y+190,OrbWeekdayAuditText(3,"WED"),OrbWeekdayAuditColor(3),7);
   CreateLabel("DASH_WD_THU",x+110,y+206,OrbWeekdayAuditText(4,"THU"),OrbWeekdayAuditColor(4),7);
   CreateLabel("DASH_WD_FRI",x+310,y+206,OrbWeekdayAuditText(5,"FRI"),OrbWeekdayAuditColor(5),7);

   // TP config line
   string tpInfo=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG
      ?"TP1="+DoubleToString(InpTp1R,1)+"R TP2="+DoubleToString(InpTp2R,1)+"R TP3="+DoubleToString(InpTp3R,1)+"R"
      :TargetLabel()+" "+HalfBeLabel();
   CreateLabel("DASH_STAT3",x+12,y+222,tpInfo+" | "+RuntimeTargetModeLabel()+" | "+ExitDebugConfig()+" | "+RuntimeSlModeLabel()+" | AutoLot "+BoolText(InpUseAutoRiskLot),C'134,158,182',7);
   CreateButton("BTN_SL_MODE",x+330,y+220,66,18,(LabPolicyEnabled()||g_rtPipSlMode)?"PIP ON":"SL% MODE",LabPolicyEnabled()||g_rtPipSlMode?C'30,120,70':C'80,80,80');
   CreateEdit("EDIT_SL_VALUE",x+402,y+220,72,18,RuntimeSlEditValue());
   ObjectSetInteger(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_READONLY,false);
   ObjectSetString(0,PREFIX+"BTN_SL_MODE",OBJPROP_TOOLTIP,"Custom engines use classic PIP SL only. TP follows the selected dashboard R architecture; cooldown/time/rule exits remain active.");
   CreateButton("BTN_SL_APPLY",x+480,y+220,58,18,"APPLY",C'38,101,176');
   CreateButton("BTN_ADV_AUD",x+542,y+220,66,18,g_rtAdvancedAuditEngine?"ADV AUD":"LEGACY",
      g_rtAdvancedAuditEngine?C'30,150,95':C'80,80,80');

    // Win-rate bar doubles as an audit progress bar while a long rebuild is running.
    // A queued/synchronizing rebuild must never leave the prior audit's WR bar
    // on screen: that made mode changes look as though every kernel produced
    // the same result before the replacement audit had even started.
    int barW=496,barH=14;
    bool historySync=(g_histCoveragePending&&!g_histCoverageHardBlocked);
    bool auditPending=(g_histAuditRunning||g_histRedrawQueued||historySync);
    double barPct=g_histAuditRunning?g_histAuditProgressPct:(historySync?1.0:(g_histRedrawQueued?0.0:wr));
    color barClr=auditPending?C'38,140,220':pnlClr;
   CreateRect("DASH_WRBAR_BG",x+12,y+238,barW,barH,C'42,51,68',C'134,158,182');
   int fillW=(int)MathRound((double)barW*MathMax(0,MathMin(100,barPct))/100.0);
   if(fillW>2)CreateRect("DASH_WRBAR_FILL",x+13,y+239,fillW-2,barH-2,barClr,barClr);
   else ObjectDelete(0,PREFIX+"DASH_WRBAR_FILL");
   string progressText="";
   if(g_histAuditRunning)
   {
      progressText="AUD "+g_histAuditStage;
      if(g_histAuditStageTotal>0)
         progressText+=" "+IntegerToString(g_histAuditStageDone)+"/"+IntegerToString(g_histAuditStageTotal);
      progressText+=" "+DoubleToString(g_histAuditProgressPct,1)+"%";
      ulong elapsedBase=g_histAuditRequestedMs>0?g_histAuditRequestedMs:g_histAuditStartedMs;
      if(elapsedBase>0)progressText+=" | "+DoubleToString((double)(GetTickCount64()-elapsedBase)/1000.0,1)+"s";
      if(g_rtAdvancedAuditEngine)progressText+=" | "+g_orbAdvLastStatus;
   }
    else if(g_histRedrawQueued)progressText="AUD QUEUED";
    else if(g_histCoveragePending)
       progressText=g_histCoverageHardBlocked?"HIST BLOCK":("HISTORY SYNC (attempt "+IntegerToString(g_histCoverageAttempts)+")");
    CreateLabel("DASH_AUD_PROGRESS",x+12,y+256,progressText,
       g_histCoverageHardBlocked?C'255,80,110':C'90,178,255',7);

   // Separator
   CreateRect("DASH_SEP3",x+8,y+258,W-16,1,C'65,116,172',C'65,116,172');

   // Status line
   string sigTime=g_lastSignalBarTime>0?FmtTime(g_lastSignalBarTime):"-";
   CreateLabel("DASH_L4",x+12,y+264,
      "Signal "+sigTime+" | Taken "+BoolText(g_tradeTaken)+" | "+g_lastExecStatus,
      (g_lastExecStatus=="OPENED"||g_lastExecStatus=="READY")?C'80,255,180':C'255,204,82',8);
   if(g_lastFilterReason!="")
      CreateLabel("DASH_L5",x+12,y+280,"Filter: "+g_lastFilterReason,C'255,204,82',7);
   else
      CreateLabel("DASH_L5",x+12,y+280,"Chart TF can be any; EA reads "+TfLabel(g_rtSignalTf)+" data.",C'134,158,182',7);

   // Execution info
   CreateLabel("DASH_L6",x+12,y+296,tpInfo+" | Magic "+IntegerToString(RuntimeMagic()),C'134,158,182',7);

   // ORB range vs ATR context
   double atr=HistDailyAtr(TimeCurrent(),InpAtrPeriod);
   string atrCtx=atr>0?"ORB/ATR "+DoubleToString(g_orbReady?((g_orbHigh-g_orbLow)/atr)*100.0:0,1)+"%":"ATR --";
   CreateLabel("DASH_L7",x+12,y+312,atrCtx+" | Range "+DoubleToString(g_orbReady?g_orbHigh-g_orbLow:0,_Digits)+" | "+ExitDebugConfig(),C'134,158,182',7);

   x=InpDashboardX+632;

   // Search results are a temporary high-z popup; they never alter settings
   // until a row is selected and APPLY STRATEGY succeeds.
   OrbStrategyPresetRefreshVisible();
   if(!g_strategyPopupOpen&&g_strategyPopupDrawn)
   {
      for(int stale=0;stale<5;stale++)
      {
         ObjectDelete(0,PREFIX+"BTN_PRESET_RESULT_"+IntegerToString(stale));
         ObjectDelete(0,PREFIX+"BTN_PRESET_STAR_"+IntegerToString(stale));
      }
      ObjectDelete(0,PREFIX+"DASH_PRESET_POPUP");ObjectDelete(0,PREFIX+"BTN_PRESET_PREV");
      ObjectDelete(0,PREFIX+"BTN_PRESET_NEXT");ObjectDelete(0,PREFIX+"DASH_PRESET_PAGE");
      ObjectDelete(0,PREFIX+"BTN_PRESET_CLOSE");
      g_strategyPopupDrawn=false;
   }
   if(g_strategyPopupOpen)
   {
      // Keep active controls alive across tick/timer refreshes to prevent click-through gaps.
      g_strategyPopupDrawn=true;
      for(int stale=g_strategyVisibleCount;stale<5;stale++)
      {
         ObjectDelete(0,PREFIX+"BTN_PRESET_RESULT_"+IntegerToString(stale));
         ObjectDelete(0,PREFIX+"BTN_PRESET_STAR_"+IntegerToString(stale));
      }
      int popupY=InpDashboardY+142,popupH=28+g_strategyVisibleCount*22;
      CreateRect("DASH_PRESET_POPUP",x+12,popupY,594,popupH,C'20,27,39',C'90,178,255');
      ObjectSetInteger(0,PREFIX+"DASH_PRESET_POPUP",OBJPROP_ZORDER,DASH_Z+15);
      for(int slot=0;slot<g_strategyVisibleCount;slot++)
      {
         OrbStrategyPreset p;int presetIndex=g_strategyVisible[slot];
         if(!OrbStrategyPresetLoad(presetIndex,p))continue;
         string caption=OrbStrategyPresetMetricCaption(p);
         bool favorite=OrbStrategyIsFavorite(presetIndex);
         CreateButton("BTN_PRESET_STAR_"+IntegerToString(slot),x+18,popupY+24+slot*22,32,20,favorite?"*":"+",
            favorite?C'184,103,22':C'58,66,82');
         ObjectSetInteger(0,PREFIX+"BTN_PRESET_STAR_"+IntegerToString(slot),OBJPROP_ZORDER,DASH_Z+17);
         ObjectSetString(0,PREFIX+"BTN_PRESET_STAR_"+IntegerToString(slot),OBJPROP_TOOLTIP,
            (favorite?"Remove favorite: ":"Add favorite: ")+p.name);
         CreateButton("BTN_PRESET_RESULT_"+IntegerToString(slot),x+56,popupY+24+slot*22,538,20,caption,
            presetIndex==g_strategyCandidateIndex?C'184,103,22':C'38,101,176');
         ObjectSetInteger(0,PREFIX+"BTN_PRESET_RESULT_"+IntegerToString(slot),OBJPROP_ZORDER,DASH_Z+17);
      }
      int matchCount=ArraySize(g_strategyMatches),pageCount=MathMax(1,(matchCount+4)/5);
      CreateButton("BTN_PRESET_PREV",x+18,popupY+3,44,18,"<",C'80,80,80');
      CreateLabel("DASH_PRESET_PAGE",x+126,popupY+6,IntegerToString(matchCount)+" MATCH | PAGE "
         +IntegerToString(g_strategySearchPage+1)+"/"+IntegerToString(pageCount),clrWhite,7);
      CreateButton("BTN_PRESET_NEXT",x+68,popupY+3,44,18,">",C'80,80,80');
      CreateButton("BTN_PRESET_CLOSE",x+550,popupY+3,44,18,"X",C'178,37,57');
      ObjectSetInteger(0,PREFIX+"BTN_PRESET_PREV",OBJPROP_ZORDER,DASH_Z+17);
      ObjectSetInteger(0,PREFIX+"DASH_PRESET_PAGE",OBJPROP_ZORDER,DASH_Z+17);
      ObjectSetInteger(0,PREFIX+"BTN_PRESET_NEXT",OBJPROP_ZORDER,DASH_Z+17);
      ObjectSetInteger(0,PREFIX+"BTN_PRESET_CLOSE",OBJPROP_ZORDER,DASH_Z+17);
   }
   OrbRPickerDraw();
   McOfUiDraw();
   TCalLauncher(PREFIX,OrbLibraryX(InpDashboardX+644),OrbLibraryY(InpDashboardY+5),
      InpDashboardX+300,InpDashboardY+34,"SESSION LOCAL TIME");
   TCalCsvLauncher(PREFIX,OrbLibraryX(InpDashboardX+772),OrbLibraryY(InpDashboardY+5),g_libraryDashScale,DASH_Z+3);
}

//=========================================================================
//  DAY RESET
//=========================================================================
bool ResetForNewNyDay()
{
   int y,m,d;int key=CurrentSessionDayKey(y,m,d);if(key==g_nyDayKey)return false;
   g_nyDayKey=key;g_histNeedsRedraw=true;DeleteLevels();
   Audit("ma_calendar_day","",0,0,0,0,"key="+(string)key);
   return true;
}

bool BuildSimGeometry(bool isBuy,double fillEntry,double plannedSl,
                      double &simSl,double &risk,double &tp1,double &tp2,double &tp3,double &tp4,double &tp5,double &tp6,
                      double sourceReferenceEntry=0.0)
{
   string detail="";
   return BuildSimGeometry(isBuy,fillEntry,plannedSl,simSl,risk,tp1,tp2,tp3,tp4,tp5,tp6,sourceReferenceEntry,detail);
}
//=========================================================================
//  LIVE FILTERS — use g_rtSignalTf for all timeframe operations
//=========================================================================
bool CheckAtrFilter(string &r)
{
   if(!g_rtFilterAtr)return true;
   // HistDailyAtr is deliberately the sacred audit's manual closed-D1 ATR.
   // Sharing it prevents ATR ON from selecting a different live day universe.
   double atr=HistDailyAtr(g_orbStartServer,InpAtrPeriod);
   if(atr<=0.0)return true;
   double pct=((g_orbHigh-g_orbLow)/atr)*100;
   if(pct<InpMinRangeAtrPct){r="ATR_NARROW "+DoubleToString(pct,1)+"%";return false;}
   if(pct>InpMaxRangeAtrPct){r="ATR_WIDE "+DoubleToString(pct,1)+"%";return false;}
   return true;
}
bool CheckVolFilter(datetime signalBar,string &r)
{
   if(!g_rtFilterVol)return true;
   if(signalBar<=0)return true;
   int sh=iBarShift(_Symbol,g_rtSignalTf,signalBar,true);
   if(sh<0)return true;
   long bv=iVolume(_Symbol,g_rtSignalTf,sh);
   // Preserve the strategy-defining sacred history baseline exactly: only
   // completed post-ORB bars before this candidate participate, capped at 20.
   // Early candidates therefore use the same shorter sample in live and audit.
   MqlRates prior[];ArraySetAsSeries(prior,false);
   int copied=CopyRates(_Symbol,g_rtSignalTf,g_orbEndServer,signalBar-1,prior);
   int lookback=MathMin(20,MathMax(0,copied));
   double avgVol=0.0,vs=0.0;
   for(int i=copied-lookback;i<copied;i++)vs+=(double)prior[i].tick_volume;
   if(lookback>0)avgVol=vs/(double)lookback;
   if(avgVol<=0)return true;
   double threshold=avgVol*g_rtVolumeMultiplier;
   if((double)bv<threshold){r="VOL_LOW "+IntegerToString(bv)+"<"+DoubleToString(threshold,0);return false;}
   return true;
}
bool CheckDayFilter(string &r){if(!g_rtFilterDay)return true;int y,m,d;CurrentSessionDayKey(y,m,d);int dow=DayOfWeekForDate(y,m,d);bool ok=false;if(dow==1&&InpTradeMonday)ok=true;if(dow==2&&InpTradeTuesday)ok=true;if(dow==3&&InpTradeWednesday)ok=true;if(dow==4&&InpTradeThursday)ok=true;if(dow==5&&InpTradeFriday)ok=true;if(!ok){r="DAY_BLOCKED";return false;}return true;}

//========================================================================= 
//  SIGNAL COMPUTE — selected MA kernel, always evaluated on the last closed bar.
//  ORB's execution/risk/filter pipeline remains downstream of this adapter.
//========================================================================= 
bool ComputeSignal(string &dir,datetime &bt,double &sc)
{
   dir="";bt=0;sc=0;
   MaCrossSignal signal;
   if(!MaCrossComputeSignal(_Symbol,g_rtSignalTf,g_rtMaCrossMode,g_rtMaCrossPair,
      MathMax(1,InpMaFastLength),MathMax(1,InpMaMediumLength),MathMax(2,InpMaSlowLength),signal))
      return false;
   if(!signal.valid||signal.barTime<=0||signal.barTime==g_lastSignalBarTime)return false;
   if(g_maIndependent&&OrbSignalAvailableTime(signal.barTime)<=g_instanceStartedAt)return false;
   bt=signal.barTime;sc=signal.price;dir=signal.direction>0?"BUY":"SELL";
   return EntryWindowAllowsAt(OrbSignalAvailableTime(bt));
}

bool StartupOrbReplayGuardAllows()
{
   if(IsTesterMode())return true;
   if(g_startupOrbDayLocked)
   {
      g_lastExecStatus="STALE_ORB_DAY_LOCKED";
      return false;
   }
   if(!g_startupOrbGuardPending)return true;

   datetime effectiveStart=g_orbEndServer;
   if(g_rtUseDelay&&g_rtDelayMin>0)effectiveStart+=g_rtDelayMin*60;
   datetime startupCutoff=MathMin(g_instanceStartedAt,g_tradeEndServer);
   if(g_instanceStartedAt<=effectiveStart||startupCutoff<=effectiveStart)
   {
      g_startupOrbGuardPending=false;
      return true;
   }

   // Existing exposure must remain manageable after restart. It already owns
   // the setup, so the guard only blocks creation of a new late lifecycle.
   if(OwnPositionExists()||g_orbBridgePlanActive)
   {
      g_startupOrbGuardPending=false;
      return true;
   }

   MqlRates probe[];
   int copied=CopyRates(_Symbol,g_rtSignalTf,g_orbEndServer,startupCutoff,probe);
   if(copied<=0)
   {
      g_lastExecStatus="STARTUP_ORB_GUARD_WAIT_DATA";
      return false; // Fail closed until today's source bars are available.
   }

   string priorDir="";datetime priorBar=0;double priorClose=0.0,priorHigh=0.0,priorLow=0.0;
   double priorVolume=0.0,priorAverage=0.0;
   bool hadRawCandidate=false;string lastReject="",modernDetail="";
   // Replay the same sacred operational chain and the same entry-window rule.
   // A raw VOL/DISP/FVG rejection must not consume a day after restart.
   bool priorSignal=FindHistOperationalBreakout(g_orbEndServer,startupCutoff,g_orbHigh,g_orbLow,
      priorDir,priorBar,priorClose,priorHigh,priorLow,priorVolume,priorAverage,
      hadRawCandidate,lastReject,modernDetail);
   g_startupOrbGuardPending=false;
   if(!priorSignal)return true;

   g_startupOrbDayLocked=true;
   g_orbOperationalCandidateConsumed=true;
   g_orbOperationalCandidateBar=priorBar;
   g_orbOperationalCandidateDir=priorDir;
   g_startupOrbPriorSignalBar=priorBar;
   g_startupOrbPriorSignalDir=priorDir;
   g_lastSignalBarTime=priorBar;
   datetime latestClosed=iTime(_Symbol,g_rtSignalTf,1);
   if(latestClosed>0)g_lastCheckedSignalBarTime=latestClosed;
   ClearNasPending("startup_stale_orb_day");
   ClearRetestState("startup_stale_orb_day");
   ClearImbalanceState("startup_stale_orb_day");
   ClearNewDayReverseRetry("startup_stale_orb_day");
   g_lastFilterReason="STALE ORB "+priorDir+" "+FmtTime(priorBar);
   g_lastExecStatus="STALE_ORB_DAY_LOCKED";
   Audit("startup_stale_orb_locked",priorDir,0,priorClose,0,0,
      "started="+FmtTime(g_instanceStartedAt)+" prior_operational="+FmtTime(priorBar)
      +" next_orb_day_required=1 "+modernDetail);
   return false;
}

//=========================================================================
//  TRADE EXECUTION
//=========================================================================
bool ExecSingle(string dir,double &entry,double &sl,double &tp,double lot)
{
   entry=NormalizeTradePrice(entry);sl=NormalizeTradePrice(sl);tp=NormalizeTradePrice(tp);
   double requiredSl=sl,requiredTp=tp;
   string adj="";
   if(LabPolicyEnabled()){
      MqlTick quote;
      if(!SymbolInfoTick(_Symbol,quote)||!LabPolicyQuoteAllows(dir=="BUY",sl,tp,quote.bid,quote.ask,MinStopDistance()))
      {g_lastExecStatus="LAB QUOTE / BROKER STOP LIMIT: policy geometry cannot be placed";return false;}
   }
   else AdjustOpenStops(dir,entry,sl,tp,adj);
   if(g_rtInvertMode&&(MathAbs(sl-requiredSl)>TickSize()*0.5||MathAbs(tp-requiredTp)>TickSize()*0.5))
   {Audit("advanced_reverse_stops_adjustment_block",dir,lot,entry,sl,tp,adj);return false;}
   string vr="";if(!ValidateOpenStops(dir,entry,sl,tp,vr)){Audit("order_skip_stops",dir,lot,entry,sl,tp,vr);return false;}
   trade.SetExpertMagicNumber(RuntimeMagic());trade.SetDeviationInPoints(InpDeviationPoints);trade.SetTypeFillingBySymbol(_Symbol);
   string detail="";
   bool ok=SendOrbOrder(dir,lot,entry,sl,tp,"ORB15v3|"+dir,detail);
   if(!ok)Audit("order_fail",dir,lot,entry,sl,tp,adj+detail);
   else if(adj!="")Audit("order_adjusted",dir,lot,entry,sl,tp,adj+detail);
   return ok;
}
bool ExecThreeLegs(string dir,double &entry,double &sl,double &tp1,double &tp2,double &tp3,double totalLot)
{
   double leg=NormalizeLegVolume(totalLot,3);
   if(leg<=0)return ExecSingle(dir,entry,sl,tp2,NormalizeVolume(totalLot));
   trade.SetExpertMagicNumber(RuntimeMagic());trade.SetDeviationInPoints(InpDeviationPoints);trade.SetTypeFillingBySymbol(_Symbol);
   double price=NormalizeTradePrice(dir=="BUY"?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   entry=price;
   sl=NormalizeTradePrice(sl);tp1=NormalizeTradePrice(tp1);tp2=NormalizeTradePrice(tp2);tp3=NormalizeTradePrice(tp3);
   string adj1="",adj2="",adj3="";
   AdjustOpenStops(dir,price,sl,tp1,adj1);
   AdjustOpenStops(dir,price,sl,tp2,adj2);
   AdjustOpenStops(dir,price,sl,tp3,adj3);
   string vr="";
   if(!ValidateOpenStops(dir,price,sl,tp1,vr)){Audit("order_skip_stops",dir,leg,price,sl,tp1,"tp1 "+vr);return false;}
   if(!ValidateOpenStops(dir,price,sl,tp2,vr)){Audit("order_skip_stops",dir,leg,price,sl,tp2,"tp2 "+vr);return false;}
   if(!ValidateOpenStops(dir,price,sl,tp3,vr)){Audit("order_skip_stops",dir,leg,price,sl,tp3,"tp3 "+vr);return false;}
   double tps[3];tps[0]=tp1;tps[1]=tp2;tps[2]=tp3;
   string cm[3];cm[0]="ORB15v3_TP1|"+dir;cm[1]="ORB15v3_TP2|"+dir;cm[2]="ORB15v3_TP3|"+dir;
   ulong existing[];int ec=0;
   for(int p=PositionsTotal()-1;p>=0;p--){ulong t=PositionGetTicket(p);if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;ArrayResize(existing,ec+1);existing[ec++]=t;}
   int opened=0;
   for(int i=0;i<3;i++){string detail="";bool ok=SendOrbOrder(dir,leg,price,sl,tps[i],cm[i],detail);if(ok)opened++;else{Print("ORB15v3 leg",i+1," fail ",detail);Audit("leg_fail",dir,leg,price,sl,tps[i],"leg="+IntegerToString(i+1)+" "+detail);}}
   if(opened>0&&opened<3)
   {
      int remaining=0;
      for(int p=PositionsTotal()-1;p>=0;p--)
      {
         ulong t=PositionGetTicket(p);if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;
         bool ex=false;for(int e=0;e<ec;e++)if(existing[e]==t){ex=true;break;}
         if(!ex)
         {
            bool ck=trade.PositionClose(t);
            Audit(ck?"rollback_close":"rollback_close_failed","",PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),"ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
            if(!ck)remaining++;
         }
      }
      if(remaining>0)
      {
         Audit("rollback_orphan_managed",dir,leg,price,sl,tp3,"remaining="+IntegerToString(remaining));
         return true;
      }
      return false;
   }
   return opened==3;
}

bool CloseHalfOfPosition(ulong ticket)
{
   if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())return false;
   double vol=PositionGetDouble(POSITION_VOLUME);
   ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(positionId==0)positionId=ticket;
   double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double closeVol=NormalizeVolume(vol*0.5);
   double remain=vol-closeVol;
   if(closeVol<minv||remain<minv)
   {
      Audit("half_close_skip","",vol,PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),
         "volume_too_small min="+DoubleToString(minv,4)+" step="+DoubleToString(step,4));
      return false;
   }
   bool ok=trade.PositionClosePartial(ticket,closeVol);
   if(ok)OrbProSet(positionId,"halfDone",1);
   Audit(ok?"half_close":"half_close_failed",
      (long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL",
      closeVol,PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),
      "ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   return ok;
}

bool ExitModeUsesFixedTp(ORB_EXIT_ENGINE_MODE mode)
{
   return mode!=ORB_EXIT_EOD_ONLY && mode!=ORB_EXIT_BROKER_TIME && g_rtTargetMode!=ORB_TARGET_EOD;
}

bool ExitTrailStartReached()
{
   int leg=ClampExitTrailStartLeg(g_rtExitTrailStartLeg);
   if(leg<=0)return true;
   double px=g_tradeDir>0?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(px<=0||g_tradeRisk<=0)return false;
   double target=PriceAtLeg(g_tradeDir>0,g_tradeEntry,g_tradeRisk,leg);
   return g_tradeDir>0?(px>=target):(px<=target);
}

double SessionVwap(datetime from,datetime to,ENUM_TIMEFRAMES tf)
{
   MqlRates r[];int c=CopyRates(_Symbol,tf,from,to,r);
   if(c<=0)return 0.0;
   double pv=0.0,v=0.0;
   for(int i=0;i<c;i++)
   {
      double vol=(double)r[i].tick_volume;
      if(vol<=0.0)continue;
      double typical=(r[i].high+r[i].low+r[i].close)/3.0;
      pv+=typical*vol;v+=vol;
   }
   return v>0.0?NormalizePrice(pv/v):0.0;
}

bool CloseOwnForExit(string eventName,string detail)
{
   if(g_tradeDir!=0)OrbProPublishCloseOnly(g_tradeDir,eventName);
   bool any=false,allOk=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;
      string dir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL";
      double vol=PositionGetDouble(POSITION_VOLUME),entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      bool ok=trade.PositionClose(t);any=true;if(!ok)allOk=false;
      Audit(ok?eventName:eventName+"_failed",dir,vol,entry,sl,tp,detail+" ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   }
   if(any&&allOk){g_tradeDir=0;g_tradeOpenTime=0;g_beMoved=false;g_halfClosed=false;g_lastExecStatus=eventName;}
   return any&&allOk;
}
void ApplyAtrTrail(double bid,double ask)
{
   if(g_rtExitMode!=ORB_EXIT_ATR_TRAIL||!ExitTrailStartReached())return;
   int h=iATR(_Symbol,g_rtSignalTf,MathMax(2,InpExitAtrPeriod));
   if(h==INVALID_HANDLE)return;
   double atr[];ArraySetAsSeries(atr,true);
   int c=CopyBuffer(h,0,1,1,atr);IndicatorRelease(h);
   if(c!=1||atr[0]<=0.0)return;

   MqlRates r[];int rc=CopyRates(_Symbol,g_rtSignalTf,g_tradeOpenTime,TimeCurrent(),r);
   double bestHigh=g_tradeBestHigh>0?g_tradeBestHigh:g_tradeEntry;
   double bestLow=g_tradeBestLow>0?g_tradeBestLow:g_tradeEntry;
   for(int i=0;i<rc;i++){bestHigh=MathMax(bestHigh,r[i].high);bestLow=MathMin(bestLow,r[i].low);}
   bestHigh=MathMax(bestHigh,bid);bestLow=MathMin(bestLow,ask);
   g_tradeBestHigh=bestHigh;g_tradeBestLow=bestLow;

   double desired=g_tradeDir>0?NormalizeTradePrice(bestHigh-atr[0]*g_rtExitAtrMultiplier):NormalizeTradePrice(bestLow+atr[0]*g_rtExitAtrMultiplier);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;
      double oldSl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      bool improves=g_tradeDir>0?(desired>oldSl&&desired<bid):(desired<oldSl&&desired>ask);
      if(!improves)continue;
      string reason="";
      if(!CanModifySlTo(desired,g_tradeDir,reason)){Audit("atr_trail_deferred",g_tradeDir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),g_tradeEntry,desired,tp,reason+" "+ExitDebugConfig());continue;}
      bool ok=trade.PositionModify(t,desired,tp);
      Audit(ok?"atr_trail_update":"atr_trail_failed",g_tradeDir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),g_tradeEntry,desired,tp,
         "old_sl="+DoubleToString(oldSl,_Digits)+" bestH="+DoubleToString(bestHigh,_Digits)+" bestL="+DoubleToString(bestLow,_Digits)+" atr="+DoubleToString(atr[0],_Digits)+" "+ExitDebugConfig()+" ret="+IntegerToString((int)trade.ResultRetcode()));
      if(ok)g_tradeSl=desired;
   }
}

void ApplyCloseBasedExit(double bid,double ask)
{
   if(g_rtExitMode!=ORB_EXIT_ORB_MID_INVALIDATION&&g_rtExitMode!=ORB_EXIT_EMA_STOP&&g_rtExitMode!=ORB_EXIT_VWAP_STOP)return;
   if(!ExitTrailStartReached())return;
   datetime bt=iTime(_Symbol,g_rtSignalTf,1);
   if(bt<=0||bt==g_tradeLastDynamicExitBar)return;
   if(BarCloseTime(g_rtSignalTf,bt)<=g_tradeOpenTime+MathMax(0,InpExitGraceBars)*PeriodSeconds(g_rtSignalTf))return;
   double close=iClose(_Symbol,g_rtSignalTf,1);
   if(close<=0)return;
   bool exitNow=false;string ev="",detail="";
   if(g_rtExitMode==ORB_EXIT_ORB_MID_INVALIDATION)
   {
      double mid=NormalizePrice((g_orbHigh+g_orbLow)/2.0);
      exitNow=g_tradeDir>0?(close<mid):(close>mid);
      ev="orb_mid_exit";detail="close="+DoubleToString(close,_Digits)+" mid="+DoubleToString(mid,_Digits)+" bar="+FmtTime(bt)+" "+ExitDebugConfig();
   }
   else if(g_rtExitMode==ORB_EXIT_EMA_STOP)
   {
      int h=iMA(_Symbol,g_rtSignalTf,ClampEmaPeriod(g_rtExitEmaPeriod),0,MODE_EMA,PRICE_CLOSE);
      if(h==INVALID_HANDLE)return;
      double ema[];ArraySetAsSeries(ema,true);int c=CopyBuffer(h,0,1,1,ema);IndicatorRelease(h);
      if(c!=1||ema[0]<=0)return;
      exitNow=g_tradeDir>0?(close<ema[0]):(close>ema[0]);
      ev="ema_exit";detail="close="+DoubleToString(close,_Digits)+" ema="+DoubleToString(ema[0],_Digits)+" bar="+FmtTime(bt)+" "+ExitDebugConfig();
   }
   else if(g_rtExitMode==ORB_EXIT_VWAP_STOP)
   {
      double vwap=SessionVwap(g_orbStartServer,BarCloseTime(g_rtSignalTf,bt),PERIOD_M1);
      if(vwap<=0)return;
      exitNow=g_tradeDir>0?(close<vwap):(close>vwap);
      ev="vwap_exit";detail="close="+DoubleToString(close,_Digits)+" vwap="+DoubleToString(vwap,_Digits)+" bar="+FmtTime(bt)+" "+ExitDebugConfig();
   }
   g_tradeLastDynamicExitBar=bt;
   if(exitNow)CloseOwnForExit(ev,detail);
   else Audit("dynamic_exit_probe",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,g_tradeSl,0,detail+" pass=1");
}

//=========================================================================
//  TRADE MANAGEMENT
//=========================================================================
void ManagePositions()
{
   if(g_maIndependent)return; // Each independent position keeps its own broker SL/TP.
   if(g_rtAdvancedReverse)return; // ADV REV uses broker-native spread-adjusted SL/TP only.
   if(g_tradeDir==0||!OwnPositionExists())
   {
      if(g_tradeDir!=0){g_tradeDir=0;g_tradeOpenTime=0;g_beMoved=false;g_halfClosed=false;}
      return;
   }
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);if(bid<=0||ask<=0)return;

   if(g_rtExitMode==ORB_EXIT_EOD_ONLY&&g_tradeEndServer>0&&TimeCurrent()>=g_tradeEndServer)
   {
      CloseOwnForExit("eod_exit","server_now="+FmtTime(TimeCurrent())+" trade_end="+FmtTime(g_tradeEndServer)+" "+ExitDebugConfig());
      return;
   }
   if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&g_tradeOpenTime>0)
   {
      datetime closeAt=BrokerTimeExitFor(g_tradeOpenTime);
      if(TimeCurrent()>=closeAt)
      {
         CloseOwnForExit("broker_time_exit","server_now="+FmtTime(TimeCurrent())+" close_at="+FmtTime(closeAt)+" "+ExitDebugConfig());
         return;
      }
   }

   ApplyAtrTrail(bid,ask);
   ApplyCloseBasedExit(bid,ask);
   if(g_tradeDir==0||!OwnPositionExists())return;

   int hcLeg=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG?(g_rtBEOnTp1?1:0):RuntimeHalfBeLeg();
   double hcPrice=0;
   if(hcLeg==1)hcPrice=g_tradeTp1;
   else if(hcLeg==2)hcPrice=g_tradeTp2;
   else if(hcLeg==3)hcPrice=g_tradeTp3;
   else if(hcLeg==4)hcPrice=g_tradeTp4;
   else if(hcLeg==5)hcPrice=g_tradeTp5;

   // Optional half-close + SL to BE at selected TP leg. Default is OFF for clean 1:2R.
   if(hcLeg>0&&!g_beMoved&&hcPrice>0)
   {
      bool hcHit=g_tradeDir>0?(bid>=hcPrice):(ask<=hcPrice);
      if(hcHit)
      {
         if(InpExecutionMode==ORB_EXEC_SINGLE&&!g_halfClosed)
         {
            bool halfOk=false;
            for(int p=PositionsTotal()-1;p>=0;p--)
            {
               ulong ht=PositionGetTicket(p);if(ht==0||!PositionSelectByTicket(ht)||!IsOwnPosition())continue;
               halfOk=CloseHalfOfPosition(ht);
               break;
            }
            if(halfOk)g_halfClosed=true;
         }

         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
         double be=NormalizePrice(g_tradeEntry+(g_tradeDir>0?1:-1)*InpBEOffsetPoints*pt);
         int attempts=0,moved=0,deferred=0;
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;
            string br="";
            if(!CanModifySlTo(be,g_tradeDir,br))
            {
               deferred++;
               Audit("sl_to_be_deferred",g_tradeDir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),g_tradeEntry,be,PositionGetDouble(POSITION_TP),br);
               continue;
            }
            attempts++;
            bool mk=trade.PositionModify(t,be,PositionGetDouble(POSITION_TP));
            if(mk){moved++;OrbProMarkBeDone(t);}
            Audit(mk?"sl_to_be":"sl_to_be_failed",g_tradeDir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),g_tradeEntry,be,PositionGetDouble(POSITION_TP),"ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
         }
         if(moved>0)
         {
            g_beMoved=true;g_tradeSl=be;Audit("sl_to_be_done",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,be,0,"moved="+IntegerToString(moved)+" attempts="+IntegerToString(attempts)+" hc_leg="+IntegerToString(hcLeg));
         }
         else
            Audit("sl_to_be_pending",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,be,0,"attempts="+IntegerToString(attempts)+" deferred="+IntegerToString(deferred)+" hc_leg="+IntegerToString(hcLeg));
      }
   }
   // TP touch watchdog
   if(InpEnforceTpTouchClose&&ExitModeUsesFixedTp(g_rtExitMode))
   {
      for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;double tp=PositionGetDouble(POSITION_TP);if(tp<=0)continue;int dir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;double tol=MathMax(0,InpTpTouchTolerancePts)*_Point;bool touched=dir>0?(bid+tol>=tp):(ask-tol<=tp);if(touched){bool ck=trade.PositionClose(t);Audit(ck?"tp_touch_close":"tp_touch_close_failed",dir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),tp,"ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());}}
   }
   // Time exit
   if(g_rtTimeExit&&g_tradeOpenTime>0)
   {
      int elapsed=(int)(TimeCurrent()-g_tradeOpenTime);
      if(elapsed>=InpTimeExitMinutes*60)
      {
         double px=g_tradeDir>0?bid:ask;double prog=g_tradeDir>0?(px-g_tradeEntry):(g_tradeEntry-px);
         double progR=g_tradeRisk>0?prog/g_tradeRisk:0;
         if(progR<InpTimeExitMinProgress){Audit("time_exit",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,0,0,"R="+DoubleToString(progR,2));CloseAllOwn("time_exit");g_tradeDir=0;g_tradeOpenTime=0;g_lastExecStatus="TIME_EXIT";}
      }
   }
}

//=========================================================================
//  MAIN SIGNAL PIPELINE — uses g_rtSignalTf
//=========================================================================
void SetRetestPending(string dir,datetime bt,double breakoutClose,string context,datetime gateAvailable=0)
{
   ClearImbalanceState("retest_selected");
   g_retestPending=true;
   g_retestTouched=false;
   g_retestDir=dir;
   g_retestSignalBar=bt;
   g_retestBreakoutClose=breakoutClose;
   g_retestLevel=(dir=="BUY")?g_orbHigh:g_orbLow;
   datetime start=gateAvailable>0?gateAvailable:BarCloseTime(g_rtSignalTf,bt);
   g_retestExpire=g_tradeEndServer;
   if(InpRetestMaxWaitMinutes>0)g_retestExpire=MathMin(g_retestExpire,start+InpRetestMaxWaitMinutes*60);
   g_retestContext=context;
   g_lastExecStatus="RETEST_WAIT";
   Audit("retest_pending",dir,0,breakoutClose,g_retestLevel,0,
      "signal="+FmtTime(bt)+" expire="+FmtTime(g_retestExpire)+" level="+DoubleToString(g_retestLevel,_Digits)+" "+context);
}

void SetImbalancePending(string dir,datetime bt,double breakoutClose,string context,datetime gateAvailable=0)
{
   ClearRetestState("imbalance_selected");
   g_imbPending=true;
   g_imbDir=dir;
   g_imbSignalBar=bt;
   g_imbBreakoutClose=breakoutClose;
   g_imbStart=gateAvailable>0?gateAvailable:BarCloseTime(g_rtSignalTf,bt);
   g_imbExpire=g_tradeEndServer;
   if(InpM1ImbalanceMaxWaitMinutes>0)g_imbExpire=MathMin(g_imbExpire,g_imbStart+InpM1ImbalanceMaxWaitMinutes*60);
   g_imbContext=context;
   g_lastExecStatus="IMB1M_WAIT";
   Audit("imbalance_pending",dir,0,breakoutClose,0,0,
      "signal="+FmtTime(bt)+" start="+FmtTime(g_imbStart)+" expire="+FmtTime(g_imbExpire)+" "+context);
}

bool RetestReady(string &detail)
{
   detail="";
   if(!g_retestPending)return false;
   if(TimeCurrent()>g_retestExpire||TimeCurrent()>g_tradeEndServer)
   {
      detail="expired now="+FmtTime(TimeCurrent())+" expire="+FmtTime(g_retestExpire);
      ClearRetestState(detail);
      g_lastExecStatus="RETEST_EXPIRED";
      return false;
   }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)||tick.bid<=0.0||tick.ask<=tick.bid||tick.time_msc<=0)
   {
      g_lastExecStatus="INVALID_ENTRY_QUOTE";
      Audit("entry_quote_invalid",g_retestDir,0,0,0,0,"retest quote unavailable");
      return false;
   }
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double tol=MathMax(0.0,InpRetestTolerancePoints)*pt;
   double resume=MathMax(0.0,InpRetestResumePoints)*pt;
   if(!g_retestTouched)
   {
      g_retestTouched=(g_retestDir=="BUY")?(tick.bid<=g_retestLevel+tol):(tick.ask>=g_retestLevel-tol);
      if(g_retestTouched)
         Audit("retest_touched",g_retestDir,0,g_retestBreakoutClose,g_retestLevel,0,
            "bid="+DoubleToString(tick.bid,_Digits)+" ask="+DoubleToString(tick.ask,_Digits)+" level="+DoubleToString(g_retestLevel,_Digits));
      else return false;
   }
   bool resumed=(g_retestDir=="BUY")?(tick.ask>=g_retestLevel+resume):(tick.bid<=g_retestLevel-resume);
   if(!resumed)return false;
   detail="entry=retest signal="+FmtTime(g_retestSignalBar)+" level="+DoubleToString(g_retestLevel,_Digits)+" "+g_retestContext;
   return true;
}

bool ImbalanceReady(string &detail)
{
   detail="";
   if(!g_imbPending)return false;
   if(TimeCurrent()>g_imbExpire||TimeCurrent()>g_tradeEndServer)
   {
      detail="IMB1M_EXPIRED now="+FmtTime(TimeCurrent())+" expire="+FmtTime(g_imbExpire);
      ClearImbalanceState(detail);
      g_lastExecStatus="IMB1M_EXPIRED";
      return false;
   }
   datetime entryT=0;double entryPrice=0.0;string fd="";
   if(!FindM1ImbalanceEntry(g_imbDir,g_imbStart,MathMin(TimeCurrent(),g_imbExpire),g_orbHigh,g_orbLow,entryT,entryPrice,fd))
      return false;
   detail="entry=imb1m signal="+FmtTime(g_imbSignalBar)+" "+fd+" "+g_imbContext;
   Audit("imbalance_confirmed",g_imbDir,0,entryPrice,0,0,detail);
   return true;
}

void DrawAcceptedLiveSignal(string rawDir,datetime bt,double signalClose,string detail)
{
   string execDir=EffectiveOrbDirection(rawDir);
   bool isBuy=execDir=="BUY";double arwP=0.0,pad=0.0;datetime visualT=0;
   datetime availableAt=OrbSignalAvailableTime(bt);
   MaCrossTradeMarker(availableAt,isBuy,signalClose,visualT,arwP,pad);
   string arrowName=PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+execDir+"_ARW";
   DrawSignalArrow(arrowName,visualT,arwP,isBuy,false);
   ObjectSetInteger(0,arrowName,OBJPROP_ANCHOR,isBuy?ANCHOR_TOP:ANCHOR_BOTTOM);
   ObjectSetString(0,arrowName,OBJPROP_TOOLTIP,"Accepted setup at "+FmtTime(availableAt)+" | source bar "+FmtTime(bt));
   DrawSignalText(PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+execDir+"_TXT",visualT,
      isBuy?arwP-pad*0.6:arwP+pad*0.6,"MA LIVE "+MaCrossSignalText(g_rtMaCrossMode,rawDir=="BUY"?1:-1)+" "+detail,isBuy?clrLime:clrTomato);
   Audit("signal",execDir,0,signalClose,0,0,"bar="+FmtTime(bt)+" "+RuntimeEntryLabel()+" "+detail);
}

void DispatchAcceptedOrbSignal(string dir,datetime bt,double signalClose,string detail,datetime gateAvailable=0)
{
   if(g_labPreviewOnly)return;
   if(!EntryDirectionAllows(EffectiveOrbDirection(dir)=="BUY"?1:-1))
   {g_lastFilterReason="ENTRY DIRECTION";g_lastExecStatus="DIRECTION_BLOCKED";return;}
   if(g_rtAdvancedReverse)
   {
      string reason="";
      if(!AdvancedReverseShape(reason)||OwnPositionExists())
      {g_lastExecStatus="ADV_REV_SIGNAL_BLOCKED_"+(reason!=""?reason:"ACTIVE_POSITION");return;}
   }
   if(g_maIndependent&&!MaOpenCapacityAllows(MaNativeOpenCount(),g_maMaxConsecutive))
   {g_lastExecStatus="OPEN POSITION LIMIT";return;}
   if(!g_rtAdvancedReverse)DrawAcceptedLiveSignal(dir,bt,signalClose,detail);
   if(g_rtEntryMode==ORB_ENTRY_PULLBACK_RETEST)
   {
      SetRetestPending(dir,bt,signalClose,detail,gateAvailable);
      return;
   }
   if(g_rtEntryMode==ORB_ENTRY_IMBALANCE_M1)
   {
      SetImbalancePending(dir,bt,signalClose,detail,gateAvailable);
      return;
   }
   bool opened=ExecuteOrbEntry(dir,bt,signalClose,"entry=breakout "+detail);
   if(g_rtAdvancedReverse&&opened)DrawAcceptedLiveSignal(dir,bt,signalClose,detail);
}

bool ProcessNasPending()
{
   if(!g_nasPending)return false;
   if(!g_rtNasConfirmation){ClearNasPending("mode_off");return false;}
   if(TimeCurrent()>g_nasPendingExpire||TimeCurrent()>g_tradeEndServer)
   {
      g_lastExecStatus="NAS_CONFIRM_EXPIRED";
      ClearNasPending("expired");
      return false;
   }
   if(OwnPositionExists()||g_orbBridgePlanActive)
   {
      string reverseDetail="";
      string pendingExecDir=EffectiveOrbDirection(g_nasPendingDir);
      if(!IsAcceptedNewDayReverseCandidate(pendingExecDir,TimeCurrent(),reverseDetail))
      {
         ClearNasPending("position_or_bridge_active");
         return false;
      }
   }
   datetime nasBar=0,nasAt=0;double nasClose=0.0;bool nasWasActive=false;string nasDetail="";
   if(!FindNasConfirmation(g_nasPendingDir,g_nasPendingAcceptedAt,TimeCurrent(),nasBar,nasAt,nasClose,nasWasActive,nasDetail))
   {
      g_lastExecStatus="NAS_WAIT_"+g_nasPendingDir;
      return false;
   }
   string dir=g_nasPendingDir;datetime signalBar=g_nasPendingSignalBar;
   double signalClose=g_nasPendingSignalClose;
   ClearNasPending("");
   string detail="accepted_signal=1 accepted_bar="+StringFormat("%I64d",(long)signalBar)
      +" nas_confirmed=1 "+nasDetail;
   g_lastExecStatus="NAS_CONFIRMED_"+dir;
   Audit("nas_confirmation_matched",dir,0,nasClose,0,0,detail);
   DispatchAcceptedOrbSignal(dir,signalBar,signalClose,detail,nasAt);
   return true;
}

bool ExecuteOrbEntry(string dir,datetime signalBar,double signalClose,string entryDetail)
{
   if(g_labPreviewOnly)return false;
   if(!LabNativeEntryPolicy(signalBar))return false;
   if(g_rtAdvancedReverse&&OwnPositionExists())
   {g_lastExecStatus="ADV_REV_ACTIVE_POSITION";return false;}
   if(!g_orbNativeWithBridgeOnly&&!g_orbBridgeEnabled)
   {
      g_lastExecStatus="NATIVE_OFF_PUB_OFF";
      ClearRetestState("no_entry_destination");ClearImbalanceState("no_entry_destination");
      return false;
   }
   if(StringFind(entryDetail,"accepted_signal=1")<0)
   {
      g_lastFilterReason="ACCEPTANCE SEAL";g_lastExecStatus="EXECUTION_CONTEXT_BLOCKED";
      Audit("execution_context_block",dir,0,signalClose,0,0,"missing accepted_signal=1 "+entryDetail);
      ClearRetestState("missing_acceptance_seal");ClearImbalanceState("missing_acceptance_seal");
      return false;
   }
   if(!EntryWindowAllowsAt(TimeCurrent()))
   {
      g_lastFilterReason="ENTRY WINDOW";g_lastExecStatus="WINDOW_BLOCKED";
      Audit("entry_window_block",dir,0,signalClose,0,0,"window="+EntryWindowLabel()+" "+entryDetail);
      ClearRetestState("entry_window_closed");ClearImbalanceState("entry_window_closed");
      return false;
   }
   int dailyWins=0,dailyLosses=0;
   if(DailyQuotaEnabled()&&(!g_orbNativeWithBridgeOnly||!DailyQuotaLiveAllows(RuntimeMagic(),TimeCurrent(),dailyWins,dailyLosses)))
   {
      g_lastFilterReason="DAILY CLOSED LIMIT";g_lastExecStatus="DAILY_LIMIT_OR_NATIVE_DATA";
      ClearRetestState("daily_limit");ClearImbalanceState("daily_limit");return false;
   }
   if(!TCalAllows(ServerToSessionLocal(TimeCurrent())))
   {
      g_lastFilterReason="TIME MATRIX";g_lastExecStatus="TIME_MATRIX_BLOCKED";
      Audit("time_matrix_block",dir,0,signalClose,0,0,entryDetail);
      ClearRetestState("time_matrix_block");ClearImbalanceState("time_matrix_block");
      return false;
   }
   string rawDir=dir;
   string execDir=EffectiveOrbDirection(rawDir);
   if(!EntryDirectionAllows(execDir=="BUY"?1:-1))
   {
      g_lastFilterReason="ENTRY DIRECTION";g_lastExecStatus="DIRECTION_BLOCKED";
      ClearRetestState("direction_block");ClearImbalanceState("direction_block");return false;
   }
   bool nasExitLifecycle=RuntimeNasExitEnabled();
   // Re-check at the final execution boundary so a retest/imbalance pending
   // before a dashboard toggle cannot bypass the current macro/RF policy.
   string regimeGuardDetail="";
   if(!OrbEntryRegimeFiltersAllowAt(rawDir,signalBar,regimeGuardDetail))
   {
      bool macroBlocked=(StringFind(regimeGuardDetail,"regime_allowed=0")>=0);
      g_lastFilterReason=macroBlocked?"REGIME BLOCK":"RF BLOCK";
      g_lastExecStatus=macroBlocked?"REGIME_BLOCKED":"RF_BLOCKED";
      Audit(macroBlocked?"regime_block_execution":"rf_block_execution",rawDir,0,signalClose,0,0,regimeGuardDetail+" raw_dir="+rawDir+" invert="+(g_rtInvertMode?"1":"0")+" "+entryDetail);
      ClearRetestState("regime_filter_block");
      ClearImbalanceState("regime_filter_block");
      return false;
   }
   entryDetail+=(entryDetail==""?"":" ")+regimeGuardDetail;
   entryDetail+=(entryDetail==""?"":" ")+"raw_dir="+rawDir+" exec_dir="+execDir+" invert="+(g_rtInvertMode?"1":"0");
   if(!SpreadAllowed()){g_lastFilterReason="SPREAD";g_lastExecStatus="FILTERED";Audit("spread_block",execDir,0,signalClose,0,0,entryDetail);return false;}
   if(g_rtAdvancedReverse)
   {
      string advancedReason="";
      if(!AdvancedReverseShape(advancedReason))
      {
         g_lastExecStatus="ADV_REV_BLOCKED_"+advancedReason;
         Audit("advanced_reverse_shape_block",execDir,0,signalClose,0,0,advancedReason+" "+entryDetail);
         return false;
      }
   }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)||tick.bid<=0.0||tick.ask<=tick.bid||tick.time_msc<=0)
   {
      g_lastExecStatus="INVALID_ENTRY_QUOTE";
      Audit("entry_quote_invalid",execDir,0,0,0,0,entryDetail);
      return false;
   }
   bool isBuy=execDir=="BUY";
   bool sourceIsBuy=rawDir=="BUY";
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double buf=MathMax(0,InpSlBufferPoints)*pt;
   double entry=NormalizeTradePrice(isBuy?tick.ask:tick.bid);
   double sourceReferenceEntry=NormalizeTradePrice(sourceIsBuy?tick.ask:tick.bid);
   double rawSl=NormalizeTradePrice(sourceIsBuy?(g_orbLow-buf):(g_orbHigh+buf));
   double sl=0.0,risk=0.0;string geometryDetail="";
   if(!ResolveExecutionStop(sourceIsBuy,isBuy,entry,rawSl,sl,risk,geometryDetail,sourceReferenceEntry))
   {
      g_lastExecStatus=StringFind(geometryDetail,"INVERSE_GAP_BLOCK")==0?"INVERSE_GAP_BLOCK":"GEOMETRY_BLOCKED";
      g_lastFilterReason=geometryDetail;
      Audit("geometry_block",execDir,0,entry,0,0,geometryDetail+" "+entryDetail);
      return false;
   }
   entryDetail+=(entryDetail==""?"":" ")+geometryDetail;
   double tp1=PriceAtLeg(isBuy,entry,risk,1);
   double tp2=PriceAtLeg(isBuy,entry,risk,2);
   double tp3=PriceAtLeg(isBuy,entry,risk,3);
   double tp4=PriceAtLeg(isBuy,entry,risk,4);
   double tp5=PriceAtLeg(isBuy,entry,risk,5);
   double tp6=PriceAtLeg(isBuy,entry,risk,6);
   if(g_maIndependent)
   {
      double independentTp=0.0,independentR=0.0;string independentDetail="";
      if(!ResolveTargetPriceAndR(isBuy,entry,risk,independentTp,independentR,independentDetail,sourceReferenceEntry))return false;
      return MaIndependentOpen(execDir,signalBar,entry,sl,independentTp,entryDetail+" "+independentDetail);
   }
   if(g_orbBridgeOnly&&!ExitModeUsesFixedTp(g_rtExitMode))
   {
      g_lastExecStatus="BRIDGE_ONLY_UNSUPPORTED_EXIT";
      Audit("bridge_only_shape_block",execDir,0,entry,sl,0,"bridge-only requires a fixed TP because no native position exists to drive dynamic/time exits "+ExitDebugConfig());
      return false;
   }
   bool hasActiveLifecycle=(OwnPositionExists()||g_orbBridgePlanActive);
   if(hasActiveLifecycle)
   {
      datetime candidateAvailable=MathMax(OrbSignalAvailableTime(signalBar),TimeCurrent());
      string reverseDetail="";
      if(!IsAcceptedNewDayReverseCandidate(execDir,candidateAvailable,reverseDetail))
      {
         g_lastExecStatus="ACCEPTED_ALREADY_ACTIVE";
         Audit("accepted_signal_while_active",execDir,0,entry,sl,0,entryDetail);
         ClearRetestState("active_lifecycle");ClearImbalanceState("active_lifecycle");
         return false;
      }
      if(!CloseAcceptedNewDayReverseLifecycle(execDir,candidateAvailable,reverseDetail))
      {
         SetNewDayReverseRetry(rawDir,execDir,signalBar,candidateAvailable,signalClose);
         g_lastExecStatus="NEW_DAY_REVERSE_CLOSE_RETRY";
         Audit("new_day_reverse_close_retry",execDir,0,entry,sl,0,reverseDetail+" "+entryDetail);
         return false;
      }
      ClearNewDayReverseRetry("close_complete");
      entryDetail+=(entryDetail==""?"":" ")+"new_day_reverse=1 "+reverseDetail;
   }
   bool opened=false;
   double planTp=0.0,planHalf=0.0;
   string lotDetail="";
   double preflightLot=0.0;
   if(g_orbNativeWithBridgeOnly)
   {
      preflightLot=ResolveLot(execDir,entry,sl,lotDetail);
      if(preflightLot<=0.0)
      {g_lastExecStatus="FILTERED";Audit("risk_block",execDir,0,entry,sl,0,lotDetail+" "+entryDetail);return false;}
   }
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      if(g_rtTargetMode!=ORB_TARGET_R_LEG)
      {
         g_lastExecStatus="FILTERED";
         Audit("target_mode_block",execDir,0,entry,sl,0,"partial_3leg_requires_rleg "+RuntimeTargetModeLabel()+" "+entryDetail);
         return false;
      }
      if(!ExitModeUsesFixedTp(g_rtExitMode))
      {
         g_lastExecStatus="FILTERED";
         Audit("exit_mode_block",execDir,0,entry,sl,0,"partial_3leg_incompatible "+ExitDebugConfig()+" "+entryDetail);
         return false;
      }
      planTp=tp3;
      planHalf=g_rtBEOnTp1?tp1:0.0;
      // Live chart geometry belongs to the accepted signal, not to a later I/O or order result.
       datetime executedAt=TimeCurrent();
       StoreOrbBridgePlan(isBuy?1:-1,executedAt,entry,sl,planTp,planHalf);
       bool bridgeAccepted=!g_orbBridgeEnabled||OrbProPublishSignal(execDir,signalBar,entry,sl,planTp,planHalf,planHalf>0?"TP1":"OFF",entryDetail+" bridge_mode=3leg_collapsed");
      if(nasExitLifecycle&&g_orbBridgeEnabled&&bridgeAccepted)
         StartNasManagedLifecycle(execDir,isBuy?1:-1,executedAt,true);
      if(!g_orbNativeWithBridgeOnly)
      {
         if(!bridgeAccepted){g_lastExecStatus="BRIDGE_ONLY_FAIL";return false;}
          DrawOrbExecutionVisual(execDir,executedAt,signalBar,entry,sl,entryDetail);
          g_tradeTaken=true;g_lastExecStatus="BRIDGE_ONLY";ClearRetestState("");ClearImbalanceState("");return true;
      }
      if(g_orbBridgeOnly)
         Audit(bridgeAccepted?"bridge_published_native_continue":"bridge_native_continue_publish_failed",execDir,0,entry,sl,planTp,entryDetail);
      double lot=preflightLot;
      opened=ExecThreeLegs(execDir,entry,sl,tp1,tp2,tp3,lot);
      if(opened){g_tradeTp1=tp1;g_tradeTp2=tp2;g_tradeTp3=tp3;Audit("opened_3leg",execDir,lot,entry,sl,tp3,lotDetail+" "+entryDetail);}
   }
   else
   {
      double targetPrice=0.0,targetR=0.0;string targetDetail="";
      if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail,sourceReferenceEntry)){g_lastExecStatus="FILTERED";Audit("target_resolve_fail",execDir,0,entry,sl,0,entryDetail);return false;}
      double tp=ExitModeUsesFixedTp(g_rtExitMode)?targetPrice:0.0;
      planTp=tp;
      int bridgeHcLeg=RuntimeHalfBeLeg();
      if(bridgeHcLeg>0)planHalf=PriceAtLeg(isBuy,entry,risk,bridgeHcLeg);
      // Live chart geometry belongs to the accepted signal, not to a later I/O or order result.
       datetime executedAt=TimeCurrent();
       StoreOrbBridgePlan(isBuy?1:-1,executedAt,entry,sl,tp,planHalf);
       bool bridgeAccepted=!g_orbBridgeEnabled||OrbProPublishSignal(execDir,signalBar,entry,sl,tp,planHalf,bridgeHcLeg>0?("TP"+IntegerToString(bridgeHcLeg)):"OFF",entryDetail+" "+targetDetail);
      if(nasExitLifecycle&&g_orbBridgeEnabled&&bridgeAccepted)
         StartNasManagedLifecycle(execDir,isBuy?1:-1,executedAt,true);
      if(!g_orbNativeWithBridgeOnly)
      {
         if(!bridgeAccepted){g_lastExecStatus="BRIDGE_ONLY_FAIL";return false;}
          DrawOrbExecutionVisual(execDir,executedAt,signalBar,entry,sl,entryDetail);
          g_tradeTaken=true;g_lastExecStatus="BRIDGE_ONLY";ClearRetestState("");ClearImbalanceState("");return true;
      }
      if(g_orbBridgeOnly)
         Audit(bridgeAccepted?"bridge_published_native_continue":"bridge_native_continue_publish_failed",execDir,0,entry,sl,tp,entryDetail+" "+targetDetail);
      double lot=preflightLot;
      opened=ExecSingle(execDir,entry,sl,tp,lot);
      if(opened){g_tradeTp1=tp1;g_tradeTp2=tp2;g_tradeTp3=tp3;g_tradeTp4=tp4;g_tradeTp5=tp5;g_tradeTp6=tp6;Audit("opened",execDir,lot,entry,sl,tp,lotDetail+" "+targetDetail+" "+HalfBeLabel()+" "+ExitDebugConfig()+" "+entryDetail);}
   }
   if(opened&&FixedReferenceRiskMode())
   {
      string fixedRiskDetail="";
      if(!ValidateFixedReferencePostFill(fixedRiskDetail))
      {
         opened=false;g_lastExecStatus="FIXED_RISK_POST_FILL_BLOCK";
         Audit("fixed_risk_post_fill_block",execDir,0,entry,sl,planTp,fixedRiskDetail);
      }
      else Audit("fixed_risk_post_fill_ok",execDir,0,entry,sl,planTp,fixedRiskDetail);
   }
   if(opened)
   {
       DrawOrbExecutionVisual(execDir,TimeCurrent(),signalBar,entry,sl,entryDetail);
       g_tradeTaken=true;g_tradeDir=isBuy?1:-1;g_tradeEntry=entry;g_tradeSl=sl;g_tradeOpenTime=TimeCurrent();g_beMoved=false;g_halfClosed=false;g_tradeRisk=MathAbs(entry-sl);g_tradeBestHigh=entry;g_tradeBestLow=entry;g_tradeLastDynamicExitBar=0;g_lastExecStatus="OPENED";ClearOrbBridgePlan();
      if(nasExitLifecycle)
         StartNasManagedLifecycle(execDir,isBuy?1:-1,g_tradeOpenTime,g_nasManagedBridgePublished);
      OrbProStoreOpenPositions(g_tradeDir,entry,sl,planTp,planHalf,signalBar,g_lastSignalRegime);
      ClearRetestState("");
      ClearImbalanceState("");
      return true;
   }
    g_lastExecStatus=(g_rtAdvancedReverse&&OwnPositionExists())?"ADV_REV_CHECK_POSITION":"FAIL";
    Audit("order_fail",execDir,0,entry,sl,0,"ret="+IntegerToString((int)trade.ResultRetcode())+" "+entryDetail);
   return false;
}

int CurrentOrbLifecycleDirection()
{
   if(g_tradeDir!=0)return g_tradeDir;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      return (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
   }
   if(g_orbBridgePlanActive&&g_orbBridgePlanDir!=0)return g_orbBridgePlanDir;
   return 0;
}

datetime CurrentOrbLifecycleStartTime()
{
   if(g_tradeOpenTime>0)return g_tradeOpenTime;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      datetime openedAt=(datetime)PositionGetInteger(POSITION_TIME);
      if(openedAt>0)return openedAt;
   }
   if(g_orbBridgePlanActive&&g_orbBridgePlanTime>0)
      return OrbSignalAvailableTime(g_orbBridgePlanTime);
   return 0;
}

int OrbSessionDayKeyAt(datetime value)
{
   if(value<=0)return 0;
   MqlDateTime st;TimeToStruct(ServerToSessionLocal(value),st);
   return st.year*10000+st.mon*100+st.day;
}

bool IsAcceptedNewDayReverseCandidate(string execDir,datetime candidateAvailable,string &detail)
{
   detail="";
   if(g_maIndependent||!g_maReverseExit||g_maReverseWait>0)return false;
   int candidateDir=(execDir=="BUY"?1:(execDir=="SELL"?-1:0));
   int activeDir=CurrentOrbLifecycleDirection();
   datetime activeSince=CurrentOrbLifecycleStartTime();
   int activeDay=OrbSessionDayKeyAt(activeSince);
   int candidateDay=OrbSessionDayKeyAt(candidateAvailable);
   if(candidateDir==0||activeDir==0||activeSince<=0||activeDay<=0||candidateAvailable<=activeSince||candidateDir==activeDir)
      return false;
   detail="active_dir="+(activeDir>0?"BUY":"SELL")
      +" active_since="+FmtTime(activeSince)
      +" active_day="+IntegerToString(activeDay)
      +" candidate_dir="+execDir
      +" candidate_at="+FmtTime(candidateAvailable)
      +" candidate_day="+IntegerToString(candidateDay);
   return true;
}

bool CloseAcceptedNewDayReverseLifecycle(string execDir,datetime candidateAvailable,string &detail)
{
   string candidateDetail="";
   if(!IsAcceptedNewDayReverseCandidate(execDir,candidateAvailable,candidateDetail))
   {
      detail="not_new_day_reverse "+candidateDetail;
      return false;
   }
   int activeDir=CurrentOrbLifecycleDirection();
   bool bridgePublished=true;
   if(g_orbBridgeEnabled)
      bridgePublished=OrbProPublishCloseOnly(activeDir,"new_day_reverse_orb",true);

   bool nativeOk=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      double volume=PositionGetDouble(POSITION_VOLUME);
      double opened=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      bool closed=trade.PositionClose(ticket);
      if(!closed)nativeOk=false;
      Audit(closed?"new_day_reverse_native_close":"new_day_reverse_native_close_failed",
         activeDir>0?"BUY":"SELL",volume,opened,sl,tp,
         candidateDetail+" ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   }
   if(OwnPositionExists())nativeOk=false;
   if(!nativeOk)
   {
      detail=candidateDetail+" native_close=FAILED bridge_close="+(bridgePublished?"PUBLISHED":"FAILED");
      return false;
   }

   // A subsequent accepted OPEN also performs a scoped reverse close in every
   // production listener. The close-only event is an additional idempotent guard.
   ClearOrbBridgePlan();
   ClearNasManagedLifecycle("new_day_reverse_orb");
   g_tradeTaken=false;g_tradeDir=0;g_tradeEntry=0;g_tradeSl=0;g_tradeOpenTime=0;
   g_beMoved=false;g_halfClosed=false;g_tradeRisk=0;
   detail=candidateDetail+" native_close=OK bridge_close="+(bridgePublished?"PUBLISHED":"OPEN_REVERSE_FALLBACK");
   Audit("new_day_reverse_closed",execDir,0,0,0,0,detail);
   return true;
}

string NewDayReverseRetryKey(string field)
{
   return "ORB_NDR."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +OrbProSafeToken(_Symbol)+"."+OrbProTf(g_rtSignalTf)+".C"+IntegerToString(g_orbBridgeChannel)
      +".M"+StringFormat("%I64d",RuntimeMagic())+"."+field;
}

void PersistNewDayReverseRetry()
{
   if(!g_newDayReverseRetryPending)return;
   GlobalVariableSet(NewDayReverseRetryKey("PENDING"),1.0);
   GlobalVariableSet(NewDayReverseRetryKey("RAW"),g_newDayReverseRetryRawDir=="BUY"?1.0:-1.0);
   GlobalVariableSet(NewDayReverseRetryKey("EXEC"),(double)g_newDayReverseRetryExecDir);
   GlobalVariableSet(NewDayReverseRetryKey("BAR"),(double)g_newDayReverseRetrySignalBar);
   GlobalVariableSet(NewDayReverseRetryKey("AVAILABLE"),(double)g_newDayReverseRetryAvailable);
   GlobalVariableSet(NewDayReverseRetryKey("CLOSE"),g_newDayReverseRetrySignalClose);
}

void ClearNewDayReverseRetry(string reason="")
{
   if(g_newDayReverseRetryPending&&reason!="")
      Audit("new_day_reverse_retry_clear",g_newDayReverseRetryExecDir>0?"BUY":"SELL",0,
         g_newDayReverseRetrySignalClose,0,0,"reason="+reason);
   string fields[6]={"PENDING","RAW","EXEC","BAR","AVAILABLE","CLOSE"};
   for(int i=0;i<6;i++)GlobalVariableDel(NewDayReverseRetryKey(fields[i]));
   g_newDayReverseRetryPending=false;g_newDayReverseRetryRawDir="";g_newDayReverseRetryExecDir=0;
   g_newDayReverseRetrySignalBar=0;g_newDayReverseRetryAvailable=0;g_newDayReverseRetrySignalClose=0.0;
}

void SetNewDayReverseRetry(string rawDir,string execDir,datetime signalBar,datetime available,double signalClose)
{
   g_newDayReverseRetryPending=true;
   g_newDayReverseRetryRawDir=rawDir;
   g_newDayReverseRetryExecDir=(execDir=="BUY"?1:-1);
   g_newDayReverseRetrySignalBar=signalBar;
   g_newDayReverseRetryAvailable=available;
   g_newDayReverseRetrySignalClose=signalClose;
   PersistNewDayReverseRetry();
}

void RestoreNewDayReverseRetry()
{
   if(!GlobalVariableCheck(NewDayReverseRetryKey("PENDING"))
      ||GlobalVariableGet(NewDayReverseRetryKey("PENDING"))<0.5)return;
   g_newDayReverseRetryRawDir=GlobalVariableGet(NewDayReverseRetryKey("RAW"))>0?"BUY":"SELL";
   g_newDayReverseRetryExecDir=(int)MathRound(GlobalVariableGet(NewDayReverseRetryKey("EXEC")));
   g_newDayReverseRetrySignalBar=(datetime)GlobalVariableGet(NewDayReverseRetryKey("BAR"));
   g_newDayReverseRetryAvailable=(datetime)GlobalVariableGet(NewDayReverseRetryKey("AVAILABLE"));
   g_newDayReverseRetrySignalClose=GlobalVariableGet(NewDayReverseRetryKey("CLOSE"));
   g_newDayReverseRetryPending=(g_newDayReverseRetrySignalBar>0
      &&g_newDayReverseRetryAvailable>0
      &&(g_newDayReverseRetryExecDir==1||g_newDayReverseRetryExecDir==-1));
   if(!g_newDayReverseRetryPending)ClearNewDayReverseRetry("restore_invalid");
}

bool ProcessNewDayReverseRetry()
{
   if(!g_newDayReverseRetryPending)return false;
   string execDir=g_newDayReverseRetryExecDir>0?"BUY":"SELL";
   string reverseDetail="";
   if(!IsAcceptedNewDayReverseCandidate(execDir,g_newDayReverseRetryAvailable,reverseDetail))
   {
      if(!OwnPositionExists()&&!g_orbBridgePlanActive)ClearNewDayReverseRetry("exposure_resolved");
      else g_lastExecStatus="NEW_DAY_REVERSE_CLOSE_RETRY";
      return true;
   }
   if(!CloseAcceptedNewDayReverseLifecycle(execDir,g_newDayReverseRetryAvailable,reverseDetail))
   {
      g_lastExecStatus="NEW_DAY_REVERSE_CLOSE_RETRY";
      PersistNewDayReverseRetry();
      return true;
   }

   string rawDir=g_newDayReverseRetryRawDir;
   datetime signalBar=g_newDayReverseRetrySignalBar;
   double signalClose=g_newDayReverseRetrySignalClose;
   int frozenExecDir=g_newDayReverseRetryExecDir;
   ClearNewDayReverseRetry("close_complete");
   if(!EntryWindowAllowsAt(TimeCurrent()))
   {
      g_lastExecStatus="NEW_DAY_REVERSE_CLOSED_WINDOW_EXPIRED";
      Audit("new_day_reverse_reentry_window_expired",execDir,0,signalClose,0,0,reverseDetail);
      return true;
   }
   if((EffectiveOrbDirection(rawDir)=="BUY"?1:-1)!=frozenExecDir)
   {
      g_lastExecStatus="NEW_DAY_REVERSE_CLOSED_CONFIG_CHANGED";
      Audit("new_day_reverse_reentry_config_changed",execDir,0,signalClose,0,0,reverseDetail);
      return true;
   }
   ExecuteOrbEntry(rawDir,signalBar,signalClose,
      "entry=retry accepted_signal=1 accepted_bar="+StringFormat("%I64d",(long)signalBar)+" "+reverseDetail);
   return true;
}

void EnsureNasExitLifecycle()
{
   if(!RuntimeNasExitEnabled()||g_nasManagedLifecycle)return;
   int execDirection=CurrentOrbLifecycleDirection();
   datetime openedAt=CurrentOrbLifecycleStartTime();
   if((execDirection!=1&&execDirection!=-1)||openedAt<=0)return;
   StartNasManagedLifecycle(execDirection>0?"BUY":"SELL",execDirection,openedAt,g_orbBridgePlanActive);
   Audit("nas_exit_lifecycle_adopted",execDirection>0?"BUY":"SELL",0,g_tradeEntry,g_tradeSl,0,
      "mode="+RuntimeNasModeLabel()+" tf="+TfLabel(NasConfirmationTf())+" sensitivity="+IntegerToString(g_rtNasSensitivity)
      +" flow_vol="+(g_rtNasFlowVolumeFilter?"ON":"OFF")
      +" flow_vol_x="+DoubleToString(g_rtNasFlowVolumeMultiplier,2));
}

datetime NasOppositeExitEligibleAt(datetime openedAt)
{
   if(openedAt<=0)return 0;
   return openedAt+(datetime)(MathMax(0,g_rtNasOppositeExitWaitMinutes)*60);
}

datetime NasLegacyExitWindowEnd(datetime openedAt)
{
   if(openedAt<=0)return 0;
   datetime local=ServerToSessionLocal(openedAt);
   MqlDateTime st;TimeToStruct(local,st);
   int sm,em,tem;SessionClockMinutes(sm,em,tem);
   datetime windowEnd=SessionLocalToServer(st.year,st.mon,st.day,tem);
   return windowEnd>openedAt?windowEnd:openedAt;
}

datetime NasOppositeExitScanExclusive(datetime openedAt)
{
   datetime eligible=NasOppositeExitEligibleAt(openedAt);
   if(eligible<=openedAt)return openedAt;
   return eligible-1; // Include a closed NAS event exactly at the grace boundary.
}

bool FindNasOppositeExitWithGrace(int execDir,datetime openedAt,datetime latestAvailable,
                                  datetime &eventBar,datetime &eventAt,double &eventClose,string &detail)
{
   eventBar=0;eventAt=0;eventClose=0.0;detail="";
   if((execDir!=1&&execDir!=-1)||openedAt<=0||latestAvailable<=openedAt)return false;
   string tradeDir=execDir>0?"BUY":"SELL",opposite=execDir>0?"SELL":"BUY";
   datetime eligibleAt=NasOppositeExitEligibleAt(openedAt);
   if(eligibleAt<=openedAt)
      return FindNasTransitionAfter(opposite,openedAt,latestAvailable,eventBar,eventAt,eventClose,detail);

   // A NAS state reached during grace remains active until another NAS signal changes it.
   // If that state is opposite when grace expires, exit exactly at the grace boundary.
   datetime stateUntil=MathMin(eligibleAt,latestAvailable);
   string stateDir="",stateDetail="";datetime stateBar=0,stateAt=0;double stateClose=0.0;
   if(FindLatestNasSignalAfter(openedAt,stateUntil,stateDir,stateBar,stateAt,stateClose,stateDetail)
      &&stateDir==opposite&&eligibleAt<=latestAvailable)
   {
      eventBar=stateBar;eventAt=eligibleAt;eventClose=stateClose;
      detail="NAS_OPPOSITE_LATCHED trade_dir="+tradeDir+" signal_at="+FmtTime(stateAt)
         +" eligible_at="+FmtTime(eligibleAt)+" "+stateDetail;
      return true;
   }
   if(latestAvailable<eligibleAt)return false;
   return FindNasTransitionAfter(opposite,eligibleAt-1,latestAvailable,eventBar,eventAt,eventClose,detail);
}

bool CloseNasManagedLifecycle()
{
   if(!g_nasManagedLifecycle||!g_nasManagedClosePending)return false;
   string modeReason=g_rtNasAdditionalExit?"nas_additional_exit_":"nas_opposite_signal_";
   string reason=modeReason+(g_nasManagedRawDir=="BUY"?"sell":"buy");
   bool publishOk=!g_nasManagedBridgePublished;
   if(g_nasManagedBridgePublished)
      publishOk=OrbProPublishCloseOnly(g_nasManagedExecDir,reason,true);

   bool nativeOk=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      bool closed=trade.PositionClose(ticket);
      if(!closed)nativeOk=false;
      Audit(closed?"nas_opposite_native_close":"nas_opposite_native_close_failed",
         g_nasManagedExecDir>0?"BUY":"SELL",PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),
         PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),
         "opposite_at="+FmtTime(g_nasManagedOppositeAt)+" ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   }
   if(OwnPositionExists())nativeOk=false;
   if(!nativeOk||!publishOk)
   {
      g_lastExecStatus=!nativeOk?"NAS_EXIT_NATIVE_RETRY":"NAS_EXIT_PUBLISH_RETRY";
      PersistNasManagedLifecycle();
      return false;
   }
   ClearOrbBridgePlan();
   g_tradeDir=0;g_tradeOpenTime=0;g_beMoved=false;g_halfClosed=false;
   g_lastExecStatus=g_rtNasAdditionalExit?"NAS_ADDITIONAL_EXIT_CLOSED":"NAS_OPPOSITE_EXIT_CLOSED";
   Audit(g_rtNasAdditionalExit?"nas_additional_exit_closed":"nas_opposite_exit_closed",
      g_nasManagedExecDir>0?"BUY":"SELL",0,g_tradeEntry,g_tradeSl,0,
      "basis_dir="+g_nasManagedRawDir+" opposite_at="+FmtTime(g_nasManagedOppositeAt));
   ClearNasManagedLifecycle("opposite_exit_complete");
   return true;
}

bool ProcessNasOppositeExit()
{
   if(g_maIndependent)return false;
   if(!g_nasManagedLifecycle)return false;
   if(g_nasManagedOppositeAt>0&&g_nasManagedOppositeAt<=g_nasManagedStartAt)
   {
      datetime invalidAt=g_nasManagedOppositeAt;
      g_nasManagedOppositeAt=0;g_nasManagedClosePending=false;
      if(g_nasManagedLastScanAt<g_nasManagedStartAt)g_nasManagedLastScanAt=g_nasManagedStartAt;
      PersistNasManagedLifecycle();
      Audit("nas_pre_entry_latch_discarded","",0,0,0,0,
         "source=runtime opposite_at="+FmtTime(invalidAt)+" trade_start="+FmtTime(g_nasManagedStartAt));
   }
   if(g_nasManagedClosePending)return CloseNasManagedLifecycle();
   if(!OwnPositionExists()&&!g_orbBridgePlanActive)
   {ClearNasManagedLifecycle("position_resolved");return false;}
   if(!RuntimeNasExitEnabled())return false;

   ENUM_TIMEFRAMES tf=NasConfirmationTf();
   datetime closedBar=iTime(_Symbol,tf,1);
   if(closedBar<=0)return false;
   datetime latestClosedAt=BarCloseTime(tf,closedBar);
   datetime eligibleAt=NasOppositeExitEligibleAt(g_nasManagedStartAt);
   datetime scanAfter=MathMax(g_nasManagedStartAt,g_nasManagedLastScanAt);
   datetime legacyWindowEnd=0;
   if(g_rtNasExitOnOppositeSignal)
   {
      legacyWindowEnd=NasLegacyExitWindowEnd(g_nasManagedStartAt);
      if(eligibleAt>legacyWindowEnd)
      {
         // Legacy OPP EXIT only observes the accepted ORB session. ADD EXIT
         // is the explicit opt-in for post-window lifecycle monitoring.
         if(g_nasManagedOppositeAt>0)
         {
            g_nasManagedOppositeAt=0;
            PersistNasManagedLifecycle();
         }
         return false;
      }
      latestClosedAt=MathMin(latestClosedAt,legacyWindowEnd);
   }
   string opposite=g_nasManagedRawDir=="BUY"?"SELL":"BUY";
   if(latestClosedAt>scanAfter)
   {
      string stateDir="",detail="";datetime eventBar=0,eventAt=0;double eventClose=0.0;
      if(FindLatestNasSignalAfter(scanAfter,latestClosedAt,stateDir,eventBar,eventAt,eventClose,detail))
      {
         datetime previousOppositeAt=g_nasManagedOppositeAt;
         g_nasManagedOppositeAt=(stateDir==opposite?eventAt:0);
         if(stateDir==opposite&&previousOppositeAt!=g_nasManagedOppositeAt)
            Audit("nas_opposite_latched",opposite,0,eventClose,0,0,
               detail+" wait="+DurationMinutesText(g_rtNasOppositeExitWaitMinutes)+" eligible_at="+FmtTime(eligibleAt));
         else if(stateDir!=opposite&&previousOppositeAt>0)
            Audit("nas_opposite_latch_cleared",stateDir,0,eventClose,0,0,
               detail+" previous_opposite_at="+FmtTime(previousOppositeAt));
      }
      g_nasManagedLastScanAt=latestClosedAt;
      PersistNasManagedLifecycle();
   }
   if(eligibleAt>0&&TimeCurrent()<eligibleAt)return false;
   if(g_nasManagedOppositeAt<=0)return false;
   // Persist the close intent before touching native or listener positions.
   // A terminal restart therefore resumes the exact same scoped close.
   g_nasManagedClosePending=true;
   PersistNasManagedLifecycle();
   g_lastExecStatus=g_rtNasAdditionalExit?"NAS_ADDITIONAL_EXIT_PENDING":"NAS_OPPOSITE_EXIT_PENDING";
   Audit(g_rtNasAdditionalExit?"nas_additional_detected":"nas_opposite_detected",opposite,0,0,0,0,
      "latched_at="+FmtTime(g_nasManagedOppositeAt)+" managed_basis_dir="+g_nasManagedRawDir+" exec_dir="+(g_nasManagedExecDir>0?"BUY":"SELL")
      +" wait="+DurationMinutesText(g_rtNasOppositeExitWaitMinutes)+" eligible_at="+FmtTime(eligibleAt));
   return CloseNasManagedLifecycle();
}

void DrawLiveOrbWindowSignal(string rawDir,datetime signalTime,string reason)
{
   string execDir=EffectiveOrbDirection(rawDir);
   bool isBuy=(execDir=="BUY");
   int shift=iBarShift(_Symbol,g_rtSignalTf,signalTime,true);
   if(shift<0)shift=InpUseClosedBarBreakout?1:0;
   double high=iHigh(_Symbol,g_rtSignalTf,shift),low=iLow(_Symbol,g_rtSignalTf,shift);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double pad=MathMax(MathMax(pt,high-low)*0.35,pt*40.0);
   double arrowPrice=NormalizePrice(isBuy?low-pad:high+pad);
   datetime visualTime=signalTime;
   string token=StringFormat("%I64d",(long)signalTime)+"_"+execDir;
   string base=PREFIX+"LIVE_WINDOW_"+token+"_";
   if(ObjectFind(0,base+"ARW")<0)ObjectCreate(0,base+"ARW",OBJ_ARROW,0,visualTime,arrowPrice);
   else ObjectMove(0,base+"ARW",0,visualTime,arrowPrice);
   ObjectSetInteger(0,base+"ARW",OBJPROP_ARROWCODE,isBuy?241:242);
   ObjectSetInteger(0,base+"ARW",OBJPROP_COLOR,clrOrange);
   ObjectSetInteger(0,base+"ARW",OBJPROP_WIDTH,2);
   ObjectSetInteger(0,base+"ARW",OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,base+"ARW",OBJPROP_HIDDEN,false);
   double textPrice=NormalizePrice(isBuy?arrowPrice-pad*0.55:arrowPrice+pad*0.55);
   string label="WINDOW "+execDir+" ["+reason+"]";
   if(rawDir!=execDir)label+=" raw="+rawDir;
   DrawSignalText(base+"TXT",visualTime,textPrice,label,clrOrange);
}

void HandleFilteredWindowSignal(string rawDir,datetime signalTime,double signalClose,string reason,string detail="")
{
   if(StringFind(reason,"OF_")==0){g_lastFilterReason=reason;g_lastExecStatus=reason;Audit("orderflow_reject",rawDir,0,signalClose,0,0,detail);return;}
   string execDir=EffectiveOrbDirection(rawDir);
   string windowKey=execDir+"|"+reason;
   datetime localSignal=ServerToSessionLocal(signalTime);MqlDateTime localSt;TimeToStruct(localSignal,localSt);
   int signalDayKey=localSt.year*10000+localSt.mon*100+localSt.day;
   if(g_liveWindowDrawnDayKey!=0&&g_liveWindowDrawnDayKey!=signalDayKey)
   {g_liveWindowDrawnDayKey=0;g_lastLiveWindowKey="";}
   bool firstInRun=(windowKey!=g_lastLiveWindowKey);
   bool firstVisualOfDay=(g_liveWindowDrawnDayKey!=signalDayKey);
   int activeDir=CurrentOrbLifecycleDirection();
   int windowDir=(execDir=="BUY"?1:-1);
   datetime lifecycleStart=CurrentOrbLifecycleStartTime();
   datetime eventAvailable=OrbSignalAvailableTime(signalTime);
   bool afterActiveTrade=(activeDir!=0&&lifecycleStart>0&&eventAvailable>lifecycleStart);
   bool reverseExit=(afterActiveTrade&&g_rtFilteredWindowReverseExit&&windowDir!=activeDir);
   bool postTradeDispExit=(afterActiveTrade&&g_rtPostTradeDispBlockExit&&windowDir==activeDir&&reason=="DISP_BLOCK");
   bool lifecycleVisual=(reverseExit||postTradeDispExit);
   if(firstVisualOfDay||lifecycleVisual)
   {
      if(lifecycleVisual&&!firstVisualOfDay)DeleteByPrefix(PREFIX+"LIVE_WINDOW_");
      DrawLiveOrbWindowSignal(rawDir,signalTime,reason);
      g_liveWindowDrawnDayKey=signalDayKey;
   }
   g_lastLiveWindowKey=windowKey;
   g_lastFilterReason=reason;
   g_lastExecStatus="WINDOW_"+execDir;
   if(firstInRun)Audit("window_signal",execDir,0,signalClose,0,0,"raw_dir="+rawDir+" reason="+reason+" visual="+((firstVisualOfDay||lifecycleVisual)?"1":"0")+" "+detail);
   if(activeDir==0)return; // A pre-entry WINDOW can never trigger an exit.
   if(!afterActiveTrade)return;
   if(!reverseExit&&!postTradeDispExit)return;

   string closeReason=postTradeDispExit?"post_trade_same_direction_disp_block":"filtered_window_reverse_"+reason;
   bool hadNative=OwnPositionExists();
   if(hadNative)
   {
      CloseAllOwn(closeReason);
      if(OwnPositionExists())
      {
         g_lastExecStatus="WINDOW_EXIT_CLOSE_FAIL";
         Audit("window_exit_close_failed",execDir,0,signalClose,0,0,closeReason);
         return;
      }
   }
   else if(g_orbBridgePlanActive)
   {
      if(!OrbProPublishCloseOnly(activeDir,closeReason))
      {
         g_lastExecStatus="WINDOW_EXIT_PUBLISH_FAIL";
         return;
      }
      ClearOrbBridgePlan();
   }
   g_tradeDir=0;g_tradeOpenTime=0;g_beMoved=false;g_halfClosed=false;
   g_lastExecStatus=postTradeDispExit?"DISP_BLOCK_EXIT_CLOSED":"REVERSE_WINDOW_EXIT_CLOSED";
   Audit(postTradeDispExit?"disp_block_exit_closed":"window_reverse_closed",execDir,0,signalClose,0,0,
      "closed_dir="+(activeDir>0?"BUY":"SELL")+" "+closeReason);
}

void HandleNasStateGateRejection(string rawDir,datetime signalTime,double signalClose,string detail)
{
   // STATE GATE is deliberately entry-only. A mismatch can be visualized and
   // audited, but must never enter the filtered-window close lifecycle.
   DrawLiveOrbWindowSignal(rawDir,signalTime,"NAS STATE");
   g_lastFilterReason="NAS STATE";
   g_lastExecStatus="NAS_STATE_REJECTED";
   Audit("nas_state_gate_rejected",EffectiveOrbDirection(rawDir),0,signalClose,0,0,
      "raw_dir="+rawDir+" "+detail);
}

void TryOpenSignal()
{
   if(g_labPreviewOnly)return;
   if(g_maIndependent)
   {
      string reason="";
      if(!MaIndependentExecutionAllowed(reason)){g_lastExecStatus=reason;return;}
   }
   if(!g_rtEaEnabled)return;if(!BuildOrb())return;
   // A MA kernel reports only the current closed bar. The ORB-specific
   // restart guard would lock the whole remaining day for a stale one-shot
   // breakout that this EA never replays.
   if(!g_maIndependent&&ProcessNewDayReverseRetry())return;
   if(!EntryWindowAllowsAt(TimeCurrent()))
   {
      if(InpUseClosedBarBreakout)
      {
         datetime blockedBar=iTime(_Symbol,g_rtSignalTf,1);
         if(blockedBar>0)g_lastCheckedSignalBarTime=blockedBar;
      }
      if(g_retestPending)ClearRetestState("entry_window_closed");
      if(g_imbPending)ClearImbalanceState("entry_window_closed");
      if(g_nasPending)ClearNasPending("entry_window_closed");
      g_lastExecStatus="WINDOW_CLOSED";
      return;
   }
   if(g_nasPending)
   {
      ProcessNasPending();
      return;
   }
   if(g_imbPending)
   {
      string id="";
      if(ImbalanceReady(id))ExecuteOrbEntry(g_imbDir,g_imbSignalBar,g_imbBreakoutClose,id);
      return;
   }
   if(g_retestPending)
   {
      string rd="";
      if(RetestReady(rd))ExecuteOrbEntry(g_retestDir,g_retestSignalBar,g_retestBreakoutClose,rd);
      return;
   }
   string dir;datetime bt;double sc;if(!ComputeSignal(dir,bt,sc))return;
   if(g_mcOf.mode!=0)
   {
      string error="";int ready=McOfPrepare(_Symbol,g_rtSignalTf,bt,false,error);
      if(ready!=1)
      {
         g_lastExecStatus=error;
         if(ready<0){g_lastSignalBarTime=bt;Audit("orderflow_unavailable",dir,0,sc,0,0,error);}
         return; // Never consume a pending candle or resurrect it after the next close.
      }
   }
   int maShift=iBarShift(_Symbol,g_rtSignalTf,bt,true);if(maShift<0)return;
   ConfigureMaSignalContext(bt,iHigh(_Symbol,g_rtSignalTf,maShift),iLow(_Symbol,g_rtSignalTf,maShift));
   g_lastSignalBarTime=bt;
   string fr="";
   if(!CheckDayFilter(fr)||!CheckVolFilter(bt,fr))
   {HandleFilteredWindowSignal(dir,bt,sc,fr);return;}
   string modernDetail="";
   if(!ModernFilterAllows(g_orbEndServer,g_tradeEndServer,g_rtSignalTf,bt,dir,g_rtDisplacement,g_rtFvgMode,fr,modernDetail))
   {
      HandleFilteredWindowSignal(dir,bt,sc,fr,modernDetail);return;
   }
   // Keep the most recent MA candidate for diagnostics, but never consume the
   // day. Rejected filters, risk guards and entry states must not suppress a
   // later closed-bar MA signal.
   g_orbOperationalCandidateBar=bt;
   g_orbOperationalCandidateDir=dir;
   Audit("ma_operational_candidate",dir,0,sc,0,0,
      "candidate_bar="+StringFormat("%I64d",(long)bt)+" "+modernDetail);
   RegimeV3Snapshot liveRegimeSnapshot;
   int liveRegimeBucket=OrbRegimeBucketAt(bt,liveRegimeSnapshot);
   g_lastSignalRegime=liveRegimeBucket;
   g_lastSignalRegimeName=OrbRegimeName(liveRegimeBucket);
   string liveRegimeDetail=OrbRegimeDetail(liveRegimeSnapshot,liveRegimeBucket);
   if(!OrbRegimeAllowed(liveRegimeBucket))
   {
      g_lastFilterReason="REGIME BLOCK "+g_lastSignalRegimeName;
      g_lastExecStatus="REGIME_BLOCKED";
      Audit("regime_block",dir,0,sc,0,0,liveRegimeDetail);
      HandleFilteredWindowSignal(dir,bt,sc,"REGIME_"+OrbRegimeShortName(liveRegimeBucket),liveRegimeDetail);
      return;
   }
   int liveRfIndex=-1;string liveRfRule="",liveRfDetail="";
   if(!OrbRfEvaluate(dir,liveRegimeSnapshot,liveRfIndex,liveRfRule,liveRfDetail))
   {
      g_lastFilterReason="RF BLOCK "+OrbRfRuleCode(liveRfIndex);
      g_lastExecStatus="RF_BLOCKED";
      Audit("rf_block",dir,0,sc,0,0,liveRegimeDetail+" "+liveRfDetail+" rule="+liveRfRule);
      HandleFilteredWindowSignal(dir,bt,sc,"RF_"+OrbRfRuleCode(liveRfIndex),liveRegimeDetail+" "+liveRfDetail);
      return;
   }
   modernDetail+=(modernDetail==""?"":" ")+liveRegimeDetail+" "+liveRfDetail;
   modernDetail+=(modernDetail==""?"":" ")+"accepted_signal=1 accepted_bar="+StringFormat("%I64d",(long)bt);
   string execDir=EffectiveOrbDirection(dir);
   string invertDetail="raw_dir="+dir+" exec_dir="+execDir+" invert="+(g_rtInvertMode?"1":"0");
   modernDetail+=(modernDetail==""?"":" ")+invertDetail;
   g_lastFilterReason="";
   bool hasActiveLifecycle=!g_maIndependent&&(OwnPositionExists()||g_orbBridgePlanActive);
   string newDayReverseDetail="";
   bool newDayReverse=hasActiveLifecycle
      &&IsAcceptedNewDayReverseCandidate(execDir,OrbSignalAvailableTime(bt),newDayReverseDetail);
   if(hasActiveLifecycle&&!newDayReverse)
   {
      g_lastExecStatus="ACCEPTED_ALREADY_ACTIVE";
      Audit("accepted_signal_while_active",execDir,0,sc,0,0,modernDetail);
      return;
   }
   if(newDayReverse)
      modernDetail+=(modernDetail==""?"":" ")+"new_day_reverse_candidate=1 "+newDayReverseDetail;
   if(g_rtNasStateGate)
   {
      datetime nasBar=0,nasAt=0;double nasClose=0.0;string nasDetail="";
      datetime acceptedAt=OrbSignalAvailableTime(bt);
      if(!FindNasStateGate(dir,acceptedAt,nasBar,nasAt,nasClose,nasDetail))
      {
         HandleNasStateGateRejection(dir,bt,sc,nasDetail);
         return;
      }
      modernDetail+=(modernDetail==""?"":" ")+"nas_state_gate=1 "+nasDetail;
      g_lastExecStatus="NAS_STATE_MATCHED_"+dir;
      Audit("nas_state_gate_matched",dir,0,nasClose,0,0,nasDetail);
   }
   // A later accepted trade supersedes any earlier rejected candidate from
   // the same ORB day. Keep at most one live WINDOW visual per day, while
   // allowing its first later opposite filtered signal to become that visual.
   DeleteByPrefix(PREFIX+"LIVE_WINDOW_");
   g_lastLiveWindowKey="";g_liveWindowDrawnDayKey=0;
   if(g_rtNasConfirmation)
   {
      SetNasPending(dir,bt,sc);
      ProcessNasPending(); // Allows a simultaneous closed NAS event without one-tick delay.
      return;
   }
   DispatchAcceptedOrbSignal(dir,bt,sc,modernDetail);
}

//=========================================================================
//  EVENT HANDLERS
//=========================================================================
#include "LabEntryBuilder.mqh"
int OnInit()
{
   if(!TCalInit()){Print("Invalid or damaged entry time matrix settings");return INIT_PARAMETERS_INCORRECT;}
   if(!McOfInit())return INIT_PARAMETERS_INCORRECT;
   OrbTesterAudit_Init();
   // Runtime execution markers from an older attachment/configuration are not
   // comparable with the freshly rebuilt historical audit.
   if(!IsTesterMode())DeleteExecutionVisuals();
   g_instanceStartedAt=TimeCurrent();
   g_startupOrbGuardPending=!IsTesterMode();
   g_startupOrbDayLocked=false;g_startupOrbPriorSignalBar=0;g_startupOrbPriorSignalDir="";
   g_orbOperationalCandidateConsumed=false;g_orbOperationalCandidateBar=0;g_orbOperationalCandidateDir="";
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      ENUM_ACCOUNT_MARGIN_MODE mm=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){Print("ORB15v3: 3-leg needs hedging. mode=",EnumToString(mm));return INIT_PARAMETERS_INCORRECT;}
   }
   trade.SetExpertMagicNumber(RuntimeMagic());trade.SetDeviationInPoints(InpDeviationPoints);
   // Initialize runtime toggles from inputs
   g_rtFilterAtr=InpUseAtrRangeFilter;g_rtFilterVol=InpUseVolumeFilter;g_rtFilterDay=InpUseDayFilter;
   g_rtFilteredWindowReverseExit=InpFilteredWindowReverseExitDefault;
   g_rtPostTradeDispBlockExit=InpExitOnPostTradeSameDirectionDispBlockDefault;
   g_ftmoMode=InpFtmoModeDefault;g_riskLotOnlyMode=(!g_ftmoMode&&InpRiskLotOnlyModeDefault);g_runtimeMagic=0;
   LoadRuntimeRiskPct();NativeBalanceLoad("entry_engine_lab");
   LoadRuntimeInvertMode();
   LoadRuntimeAdvancedReverse();
   LoadRuntimeMaCrossMode();LabRestoreActive();
   LoadRuntimeUtcSession();
   g_rtSignalTf=InpSignalTimeframe==PERIOD_CURRENT?(ENUM_TIMEFRAMES)_Period:InpSignalTimeframe; // NAS CURRENT must resolve against this instance's configured signal TF.
   int inputNasExitWaitMinutes=0;
   if(!ParseStrictDurationMinutes(InpNasOppositeExitWait,inputNasExitWaitMinutes))
   {
      Print("ORB15v3 invalid NAS opposite-exit wait; require duration HH:MM from 00:00 to 99:59");
      return INIT_PARAMETERS_INCORRECT;
   }
   LoadRuntimeNasConfirmation();
   LoadRuntimeNasControls();
   OrbAdvancedAuditLoadRuntime();
   if(g_rtUtcMidnightSession&&!ValidateUtcSessionInputs())
   {
      Print("ORB15v3 invalid UTC00 session; require HH:MM and start < ORB end <= trade end");
      return INIT_PARAMETERS_INCORRECT;
   }
   LoadRuntimeVolumeMultiplier();
   if(!LoadRuntimeEntryWindow())
   {
      Print("ORB15v3 invalid entry window; required HH:MM start/end GMT");
      return INIT_PARAMETERS_INCORRECT;
   }
   g_rtTimeExit=InpUseTimeExit;g_rtDisplacement=InpUseDisplacementFilter;g_rtFvgMode=InpFvgMode;g_rtBEOnTp1=InpMoveToBEOnTp1;g_rtEaEnabled=InpEaEnabled;
   g_rtExitMode=InpExitEngineMode;
   g_rtTargetMode=InpTargetMode;
   g_rtEntryMode=InpEntryMode;
   g_rtExitTrailStartLeg=ClampExitTrailStartLeg(InpExitTrailStartLeg);
   g_rtExitEmaPeriod=ClampEmaPeriod(InpExitEmaPeriod);
   g_rtExitAtrMultiplier=MathMax(0.5,MathMin(10.0,InpExitAtrMultiplier));
   g_rtCustomR=0.0;g_rtTargetLeg=(int)InpTargetTpLeg;SetTargetLeg(g_rtTargetLeg);
   g_rtHalfBeLeg=ClampHalfBeLeg((int)InpHalfBeMode,g_rtTargetLeg);
   g_rtHistoricalWeeks=ClampHistWeeks(InpHistoricalWeeks>0?InpHistoricalWeeks:(int)MathCeil((double)MathMax(1,InpHistoricalDays)/7.0));
   g_rtSlDistancePct=ClampSlDistancePct(InpSlDistancePct);
   g_rtPipSlMode=InpPipSlModeDefault;
   g_rtPipSlPips=ClampPipSlPips(InpPipSlPips);
   g_regimeAllowed[0]=InpRegimeTrendLowVolAllowed;
   g_regimeAllowed[1]=InpRegimeTrendHighVolAllowed;
   g_regimeAllowed[2]=InpRegimeRangeLowVolAllowed;
   g_regimeAllowed[3]=InpRegimeRangeHighVolAllowed;
   g_regimeAllowed[4]=InpRegimeTransitionPendingAllowed;
   g_regimeAllowed[5]=InpRegimeTransitionFreshAllowed;
   for(int ri=0;ri<ORB_REGIME_COUNT;ri++){g_regimeWins[ri]=0;g_regimeLosses[ri]=0;}
   g_orbRfEnabled=InpOrbRfFilterDefault;
   g_orbRfBlocked[0]=InpOrbRf01Blocked;
   g_orbRfBlocked[1]=InpOrbRf02Blocked;
   g_orbRfBlocked[2]=InpOrbRf03Blocked;
   g_orbRfBlocked[3]=InpOrbRf04Blocked;
   g_orbRfBlocked[4]=InpOrbRf05Blocked;
   g_orbRfBlocked[5]=InpOrbRf06Blocked;
   g_orbRfBlocked[6]=InpOrbRf07Blocked;
   g_orbRfBlocked[7]=InpOrbRf08Blocked;
   g_orbRfBlocked[8]=InpOrbRf09Blocked;
   g_orbRfBlocked[9]=InpOrbRf10Blocked;
   g_orbRfBlocked[10]=InpOrbRf11Blocked;
   g_orbRfBlocked[11]=InpOrbRf12Blocked;
   for(int rf=0;rf<ORB_RF_COUNT;rf++){g_orbRfWins[rf]=0;g_orbRfLosses[rf]=0;}
   ResetWeekdayAuditStats();
   g_rtSignalTf=InpSignalTimeframe==PERIOD_CURRENT?(ENUM_TIMEFRAMES)_Period:InpSignalTimeframe;
   g_rtDelayMin=InpBreakoutDelayMinutes;
   g_rtUseDelay=InpBreakoutDelayMinutes>0;
   g_auditRuntime=(InpAuditCsv || InpLogOnInit);
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;g_btNativeParity=InpBacktestNativeParity;
   g_btSpreadPts=InpBacktestSpreadPts>0?InpBacktestSpreadPts:(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   MaExitLoad();if(LabPolicyEnabled()&&!LabConfigurePolicySelection())return INIT_PARAMETERS_INCORRECT;
   g_maRestoringPreset=true;OrbStrategyPresetRestore();g_maRestoringPreset=false;
   OrbStrategyPresetBuildMatches("");
   g_lastHistBuild=0;g_histNeedsRedraw=true;
   ResetForNewNyDay();
   RegimeV3Update(true);
   OrbProInit();
   if(!MaIndependentInit())return INIT_PARAMETERS_INCORRECT;
   if(g_maRecoveredMagic>0)OrbProRestoreRuntimeState();
   if(!IsTesterMode())LabNativeVisualRestore();
   if(!g_maPresetModeRestored&&!GlobalVariableCheck(MaExitSettingsKey()+".ON"))g_maReverseExit=!g_maIndependent;
   RestoreOrbBridgePlan();
   RestoreNasManagedLifecycle();
   RestoreNasPending();
   if(g_maReverseExit&&!g_maIndependent&&g_maReverseWait==0)RestoreNewDayReverseRetry();
   else ClearNewDayReverseRetry("ma_reverse_disabled");
   EnsureNasExitLifecycle();
   // Refresh compliance news before a multi-year history scan can occupy OnInit.
   if(!IsTesterMode())TradeDayCalendarPublisherTick();
   if(!IsTesterMode())EventSetTimer(5);
   if(!IsTesterMode())
   {
      MaVisualTrackDeletes();
      Print("ORB15v3 INIT_UI_BEGIN tf=",(int)g_rtSignalTf," weeks=",g_rtHistoricalWeeks);
      DrawDashboard();QueueHistoricalRedraw(800);DrawOrbLiveTradeLevels();
      Print("ORB15v3 INIT_UI_END");
   }
   if(g_auditRuntime && InpLogOnInit)Print("ORB15v3.1 init ",_Symbol," build=",ORB15_BUILD," tf=",TfLabel(g_rtSignalTf)," exec=",EnumToString(InpExecutionMode)," magic=",RuntimeMagic(),
                         " tp=",DoubleToString(InpTp1R,1),"/",DoubleToString(InpTp2R,1),"/",DoubleToString(InpTp3R,1),"/",DoubleToString(InpTp4R,1),"/",DoubleToString(InpTp5R,1),"/",DoubleToString(InpTp6R,1),
                         " delay=",g_rtDelayMin,"min confirm=",InpConfirmBars,"bars invert=",g_rtInvertMode?"ON":"OFF",
                         " utc00=",g_rtUtcMidnightSession?"ON":"OFF"," nas_confirm=",g_rtNasConfirmation?"ON":"OFF",
                         " nas_state_gate=",g_rtNasStateGate?"ON":"OFF",
                         " nas_opp_exit=",g_rtNasExitOnOppositeSignal?"ON":"OFF",
                         " nas_add_exit=",g_rtNasAdditionalExit?"ON":"OFF"," nas_mode=",RuntimeNasModeLabel(),
                         " nas_tf=",TfLabel(NasConfirmationTf())," nas_sensitivity=",g_rtNasSensitivity,
                         " state_vol=",g_rtNasVolumeFilter?"ON":"OFF"," state_vol_x=",DoubleToString(g_rtNasVolumeMultiplier,2),
                         " flow_vol=",g_rtNasFlowVolumeFilter?"ON":"OFF"," flow_vol_x=",DoubleToString(g_rtNasFlowVolumeMultiplier,2),
                         " nas_calc_bars=",NasCalcWarmupBars()," nas_lookback_min=",g_rtNasActiveSignalLookbackMinutes,
                         " nas_exit_wait=",DurationMinutesText(g_rtNasOppositeExitWaitMinutes),
                         " channel=",g_orbBridgeChannel," entry_window=",EntryWindowLabel());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   MaVisualStopTrackingDeletes();
   AxAbort("EA detached");
   ResearchLbShutdown();
   ObjectsDeleteAll(0,MaOfRankPrefix());
   TCalDestroy();
   McOfRelease();
   MaIndependentRelease();
   MaRecoveryRelease();
   EventKillTimer();
   if(reason==REASON_REMOVE||reason==REASON_PROGRAM){DeleteLevels();DeleteDash();DeleteHist();DeleteLive();DeleteExecutionVisuals();DeleteByPrefix(PREFIX+"NATIVE_");DeleteByPrefix(PREFIX+"MA_OBS_");}
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   OrbTesterAudit_WriteDeal(trans, request, result);
   LabNativeVisualTransaction(trans);
   OrbProOnTradeTransaction(trans);
   MaRenderOpenCounter();
   if(IsTesterMode()||trans.type!=TRADE_TRANSACTION_DEAL_ADD||trans.deal==0||!HistoryDealSelect(trans.deal))return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol||!MagicOwned((long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)))return;
   ENUM_DEAL_ENTRY dealEntry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(dealEntry==DEAL_ENTRY_OUT||dealEntry==DEAL_ENTRY_OUT_BY||dealEntry==DEAL_ENTRY_INOUT)
   {g_labNativeLastClose=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);g_labNativeHistoryBar=0;}
   if((dealEntry==DEAL_ENTRY_OUT||dealEntry==DEAL_ENTRY_INOUT)&&!OwnPositionExists())
   {
      DeleteLive();
      ClearOrbBridgePlan();
      QueueHistoricalRedraw(0);
      DrawOrbLiveTradeLevels();
      ChartRedraw(0);
   }
}

void OnTimer()
{
   AxTimer();
   ulong nowMs=GetTickCount64();
   bool coreDue=(g_histTimerCoreLastMs==0||nowMs-g_histTimerCoreLastMs>=200);
   bool dc=false;
   if(coreDue)
   {
      g_histTimerCoreLastMs=nowMs;
      MaRecoveryRetry();
      TradeDayCalendarPublisherTick();
      EnforceRiskBreach();
      dc=ResetForNewNyDay();BuildOrb();
      RegimeV3Update(false);
      if(dc&&!IsTesterMode())QueueHistoricalRedraw(0);
      else if(!IsTesterMode()&&g_histCoveragePending&&!g_histCoverageHardBlocked
              &&InpAuditHistoryAutoRetry&&TimeLocal()>=g_histCoverageNextRetry)
         QueueHistoricalRedraw(0);
      MaObserveClosedSignal();if(!MaProcessExitManagement())TryOpenSignal();ManagePositions();
   }
   if(!IsTesterMode())
   {
      if(coreDue)
      {
         OrbProTimer();
         LabNativeVisualTimer();
         OrbAudit_HistoryScan();
         OBT_Tick();
         if(!g_histAuditRunning&&!g_histRedrawQueued)RefreshNasSignalOverlay();
         DrawOrbLiveTradeLevels();
      }
      if(coreDue)MaRenderOpenCounter();
      ProcessQueuedHistoricalRedraw();
      ProcessHistoricalAuditStep();
      if(g_histAuditRunning||g_histRedrawQueued)RenderHistoricalAuditProgress();
      else if(coreDue)UpdateDashboard();
   }
}

void OnTick()
{
   if(IsTesterMode()&&InpTesterRegimeMatrix)
   {
      if(InpTesterRegimeMatrixAnchorTime>0 && TimeCurrent()<InpTesterRegimeMatrixAnchorTime)
         return;
      OBT_RunRegimeMatrix();
      return;
   }
   MaRecoveryRetry();EnforceRiskBreach();
   ResetForNewNyDay();MaObserveClosedSignal();if(!MaProcessExitManagement())TryOpenSignal();ManagePositions();
   if(!IsTesterMode())
   {
      OrbProUpdateOpenPositions();
      // Keep risk/position management tick-driven; expensive UI work is timer-driven.
   }
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_DELETE){MaVisualObjectDeleted(sparam);return;}
   if(LabUiEvent(id,lparam,dparam,sparam))return;
   if(AxEvent(id,lparam))return;
   if(ResearchLbEvent(id,lparam,dparam,sparam))return;
   if(LossHoursEvent(id,sparam))return;
   if(TCalEvent(id,lparam,dparam,sparam))
   {
      if(g_tcalCsvRequested){g_tcalCsvRequested=false;AxStart();}
      if(g_tcalChanged)
      {g_tcalChanged=false;CancelHistoricalAuditBuild();QueueHistoricalRedraw(0);UpdateDashboard();}
      return;
   }
   if(OrbRPickerEvent(id,sparam))return;
   if(McOfUiEvent(id,sparam,lparam,dparam))return;
   if(MaOfRankEvent(id,lparam,dparam,sparam))return;
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      DrawDashboard();ChartRedraw(0);return;
   }
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      bool popupControl=OrbStrategyIsPopupControl(sparam);
      if(popupControl&&!g_strategyPopupOpen)return;
      // Consume clicks in the overlay even if MT5 reports a covered object.
      if(OrbStrategyPopupContains(lparam,dparam)&&!popupControl)
      {
         if(ObjectFind(0,sparam)>=0&&ObjectGetInteger(0,sparam,OBJPROP_TYPE)==OBJ_BUTTON)
            ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         return;
      }
   }
   if(id==CHARTEVENT_OBJECT_CLICK&&sparam==PREFIX+"BTN_PRESET_CLOSE")
   {
      g_strategyPopupOpen=false;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }
   if(id==CHARTEVENT_OBJECT_ENDEDIT&&sparam==PREFIX+"EDIT_PRESET_SEARCH")
   {
      g_strategySearchPage=0;
      OrbStrategyPresetBuildMatches(ObjectGetString(0,sparam,OBJPROP_TEXT));
      g_strategyPopupOpen=true;
      UpdateDashboard();ChartRedraw(0);return;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK)return;
   if(sparam==PREFIX+"BTN_NATIVE_BALANCE")
   {
      bool applied=NativeBalanceApply(ObjectGetString(0,PREFIX+"EDIT_NATIVE_BALANCE",OBJPROP_TEXT));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(applied){g_lastExecStatus="NATIVE_BALANCE_APPLIED";CancelHistoricalAuditBuild();QueueHistoricalRedraw(0);}
      else g_lastExecStatus="BALANCE_INVALID_OR_SAVE_FAILED";
      UpdateDashboard();ChartRedraw(0);return;
   }
   if(sparam==PREFIX+"BTN_ATR"||sparam==PREFIX+"BTN_DELAY"||sparam==PREFIX+"BTN_UTC_SESSION")return;

   if(sparam==PREFIX+"BTN_MA_REV_EXIT"||sparam==PREFIX+"BTN_MA_REV_APPLY")
   {
      if(g_newDayReverseRetryPending||g_nasManagedClosePending)
      {
         g_lastExecStatus="EXIT CHANGE BLOCKED: close retry pending";
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
      }
      int minutes=0;
      if(!ParseStrictDurationMinutes(ObjectGetString(0,PREFIX+"EDIT_MA_REV_WAIT",OBJPROP_TEXT),minutes))
         g_lastExecStatus="MA EXIT WAIT: HH:MM (00:00..99:59)";
      else
      {
         if(sparam==PREFIX+"BTN_MA_REV_EXIT")g_maReverseExit=!g_maReverseExit;
         g_maReverseWait=minutes;MaExitSave();
         CancelHistoricalAuditBuild();g_histNeedsRedraw=true;QueueHistoricalRedraw(0);
         g_lastExecStatus=g_maReverseExit?"MA_REVERSE_EXIT_ON":"MA_REVERSE_EXIT_OFF";
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   if(sparam==PREFIX+"BTN_ORDERFLOW")
   {
      ClearNasPending("orderflow_changed");ClearRetestState("orderflow_changed");ClearImbalanceState("orderflow_changed");
      g_mcOf.mode=(g_mcOf.mode+1)%7;McOfReset(false);CancelHistoricalAuditBuild();
      g_histNeedsRedraw=true;QueueHistoricalRedraw(0);
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   bool needRedraw=false;
   if(sparam==PREFIX+"BTN_MA_INDEPENDENT"||sparam==PREFIX+"BTN_MA_MAX_APPLY")
   {
      int maximum=0;
      bool enabled=sparam==PREFIX+"BTN_MA_INDEPENDENT"?!g_maIndependent:g_maIndependent;
      if(!MaParseSeriesLimit(ObjectGetString(0,PREFIX+"EDIT_MA_MAX",OBJPROP_TEXT),maximum))
         g_lastExecStatus="MAX SERIES: enter integer 1..1000";
      else if(MaIndependentApply(enabled,maximum))
      {
         CancelHistoricalAuditBuild();g_histNeedsRedraw=true;QueueHistoricalRedraw(0);
         ObjectSetString(0,PREFIX+"EDIT_MA_MAX",OBJPROP_TEXT,(string)g_maMaxConsecutive);
   ObjectSetString(0,PREFIX+"EDIT_MA_REV_WAIT",OBJPROP_TEXT,DurationMinutesText(g_maReverseWait));
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   for(int ma=0;ma<=5;ma++)
   {
      if(sparam==PREFIX+"BTN_MA_MODE_"+IntegerToString(ma))
      {
         if(!SetRuntimeMaCrossMode((MA_CROSS_SIGNAL_MODE)ma))
         {
            g_lastExecStatus="MA_MODE_SAVE_FAIL";
            UpdateDashboard();ChartRedraw(0);return;
         }
         DeleteByPrefix(PREFIX+"MA_OBS_");g_maLastObservedKey="";
         MaCrossAuditInvalidate();
         g_lastSignalBarTime=0;
         g_lastCheckedSignalBarTime=0;
         g_histNeedsRedraw=true;
         QueueHistoricalRedraw(0);
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         UpdateDashboard();ChartRedraw(0);return;
      }
   }
   for(int pair=0;pair<=2;pair++)
   {
      if(sparam==PREFIX+"BTN_MA_PAIR_"+IntegerToString(pair))
      {
         if(!SetRuntimeMaCrossPair((MA_CROSS_PAIR)pair))
         {
            g_lastExecStatus="MA_PAIR_SAVE_FAIL";
            UpdateDashboard();ChartRedraw(0);return;
         }
         DeleteByPrefix(PREFIX+"MA_OBS_");g_maLastObservedKey="";
         MaCrossAuditInvalidate();
         g_lastSignalBarTime=0;g_lastCheckedSignalBarTime=0;
         g_histNeedsRedraw=true;QueueHistoricalRedraw(0);
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         UpdateDashboard();ChartRedraw(0);return;
      }
   }
   if(sparam==PREFIX+"BTN_USER_SAVE")
   {
      OrbUserSave(ObjectGetString(0,PREFIX+"EDIT_USER_NAME",OBJPROP_TEXT));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }

   if(sparam==PREFIX+"BTN_PRESET_SYMBOL")
   {
      OrbStrategyCyclePairFilter();
      g_strategySearchPage=0;
      OrbStrategyPresetBuildMatches(ObjectGetString(0,PREFIX+"EDIT_PRESET_SEARCH",OBJPROP_TEXT));
      g_strategyPopupOpen=true;g_lastExecStatus="PRESET_SYMBOL_FILTER_CHANGED";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }
   if(sparam==PREFIX+"BTN_PRESET_FAVORITES")
   {
      g_strategyFavoritesOnly=!g_strategyFavoritesOnly;
      g_strategySearchPage=0;
      ObjectSetString(0,PREFIX+"EDIT_PRESET_SEARCH",OBJPROP_TEXT,"");
      OrbStrategyPresetBuildMatches("");
      g_strategyPopupOpen=true;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }

   if(sparam==PREFIX+"BTN_PRESET_FILTER")
   {
      if(!OrbStrategyApplyMetricFilters())
      {
         g_lastExecStatus="PRESET_FILTER_INVALID";
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         UpdateDashboard();ChartRedraw(0);return;
      }
      ObjectSetString(0,PREFIX+"EDIT_PRESET_NET",OBJPROP_TEXT,g_strategyFilterNetText);
      ObjectSetString(0,PREFIX+"EDIT_PRESET_WR",OBJPROP_TEXT,g_strategyFilterWrText);
      ObjectSetString(0,PREFIX+"EDIT_PRESET_MC",OBJPROP_TEXT,g_strategyFilterMinCumText);
      ObjectSetString(0,PREFIX+"EDIT_PRESET_GEOMETRY",OBJPROP_TEXT,g_strategyFilterGeometryText);
      g_strategySearchPage=0;
      OrbStrategyPresetBuildMatches(ObjectGetString(0,PREFIX+"EDIT_PRESET_SEARCH",OBJPROP_TEXT));
      g_strategyPopupOpen=true;
      g_lastExecStatus="PRESET_FILTER_APPLIED";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }
   if(sparam==PREFIX+"BTN_PRESET_FILTER_CLEAR")
   {
      g_strategyFilterPair="";
      g_strategyFilterNetText="";g_strategyFilterWrText="";g_strategyFilterMinCumText="";
      g_strategyFilterGeometryText="";g_strategyFilterGeometryEnabled=false;g_strategyFilterGeometry=0.0;
      g_strategyFilterNetEnabled=false;g_strategyFilterWrEnabled=false;g_strategyFilterMinCumEnabled=false;
      g_strategyFilterNet=0.0;g_strategyFilterWr=0.0;g_strategyFilterMinCum=0.0;
      ObjectSetString(0,PREFIX+"EDIT_PRESET_NET",OBJPROP_TEXT,"");
      ObjectSetString(0,PREFIX+"EDIT_PRESET_WR",OBJPROP_TEXT,"");
      ObjectSetString(0,PREFIX+"EDIT_PRESET_MC",OBJPROP_TEXT,"");
      ObjectSetString(0,PREFIX+"EDIT_PRESET_GEOMETRY",OBJPROP_TEXT,"");
      g_strategySearchPage=0;
      OrbStrategyPresetBuildMatches(ObjectGetString(0,PREFIX+"EDIT_PRESET_SEARCH",OBJPROP_TEXT));
      g_strategyPopupOpen=true;
      g_lastExecStatus="PRESET_FILTER_CLEARED";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }

   if(sparam==PREFIX+"BTN_PRESET_SEARCH")
   {
      OrbUserReload(true);
      g_strategySearchPage=0;
      OrbStrategyPresetBuildMatches(ObjectGetString(0,PREFIX+"EDIT_PRESET_SEARCH",OBJPROP_TEXT));
      g_strategyPopupOpen=true;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }
   if(sparam==PREFIX+"BTN_PRESET_PREV"||sparam==PREFIX+"BTN_PRESET_NEXT")
   {
      int pageCount=MathMax(1,(ArraySize(g_strategyMatches)+4)/5);
      if(sparam==PREFIX+"BTN_PRESET_PREV")g_strategySearchPage=MathMax(0,g_strategySearchPage-1);
      else g_strategySearchPage=MathMin(pageCount-1,g_strategySearchPage+1);
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }
   for(int presetSlot=0;presetSlot<5;presetSlot++)
   {
      if(sparam==PREFIX+"BTN_PRESET_STAR_"+IntegerToString(presetSlot))
      {
         if(presetSlot<g_strategyVisibleCount&&g_strategyVisible[presetSlot]>=0)
         {
            if(OrbStrategyToggleFavorite(g_strategyVisible[presetSlot]))
               OrbStrategyPresetBuildMatches(g_strategySearch);
         }
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         UpdateDashboard();ChartRedraw(0);return;
      }
      if(sparam!=PREFIX+"BTN_PRESET_RESULT_"+IntegerToString(presetSlot))continue;
      if(presetSlot<g_strategyVisibleCount&&g_strategyVisible[presetSlot]>=0)
      {
         OrbStrategyPreset p;
         g_strategyCandidateIndex=g_strategyVisible[presetSlot];
         if(OrbStrategyPresetLoad(g_strategyCandidateIndex,p))
         {
            g_strategySearch=p.name;
            ObjectSetString(0,PREFIX+"EDIT_PRESET_SEARCH",OBJPROP_TEXT,g_strategySearch);
            g_lastExecStatus="PRESET_SELECTED_"+p.id;
         }
      }
      g_strategyPopupOpen=false;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }
   if(sparam==PREFIX+"BTN_PRESET_APPLY")
   {
      if(g_strategyCandidateIndex<0)g_lastExecStatus="PRESET_SELECT_FIRST";
      else OrbStrategyPresetApplyInteractive(g_strategyCandidateIndex);
      g_strategyPopupOpen=false;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateDashboard();ChartRedraw(0);return;
   }

   for(int ri=0;ri<ORB_REGIME_COUNT;ri++)
   {
      if(sparam==PREFIX+"BTN_REG_"+IntegerToString(ri))
      {
         g_regimeAllowed[ri]=!g_regimeAllowed[ri];
         g_lastExecStatus=g_regimeAllowed[ri]?("REGIME_ALLOWED "+OrbRegimeShortName(ri)):("REGIME_BLOCKED "+OrbRegimeShortName(ri));
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
      }
   }

   if(sparam==PREFIX+"BTN_RF_MASTER")
   {
      g_orbRfEnabled=!g_orbRfEnabled;
      g_lastExecStatus=g_orbRfEnabled?"RF_MASTER_ON":"RF_MASTER_OFF";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   for(int rf=0;rf<ORB_RF_COUNT;rf++)
   {
      if(sparam==PREFIX+"BTN_RF_"+IntegerToString(rf))
      {
         g_orbRfBlocked[rf]=!g_orbRfBlocked[rf];
         g_lastExecStatus=OrbRfRuleCode(rf)+(g_orbRfBlocked[rf]?"_BLOCKED":"_PASSED");
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
      }
   }

   if(sparam==PREFIX+"BTN_ATR"){g_rtFilterAtr=!g_rtFilterAtr;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_VOL"){g_rtFilterVol=!g_rtFilterVol;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_APPLY_VOL")
   {
      string raw=ObjectGetString(0,PREFIX+"EDIT_VOL_MULT",OBJPROP_TEXT);
      double requested=StringToDouble(raw);
      if(!SetRuntimeVolumeMultiplier(requested))
      {
         g_lastExecStatus="VOL_INVALID_0.05_TO_20";
         ObjectSetString(0,PREFIX+"EDIT_VOL_MULT",OBJPROP_TEXT,DoubleToString(g_rtVolumeMultiplier,2));
      }
      else
      {
         g_volApplyFlashUntil=TimeLocal()+2;
         g_lastExecStatus="VOL_APPLIED_X"+DoubleToString(g_rtVolumeMultiplier,2);
         ObjectSetString(0,PREFIX+"EDIT_VOL_MULT",OBJPROP_TEXT,DoubleToString(g_rtVolumeMultiplier,2));
         Audit("volume_multiplier_applied","",0,0,0,0,"vol_x="+DoubleToString(g_rtVolumeMultiplier,4));
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_DAY"){g_rtFilterDay=!g_rtFilterDay;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_FILTER_REVERSE")
   {
      g_rtFilteredWindowReverseExit=!g_rtFilteredWindowReverseExit;
      g_lastExecStatus=g_rtFilteredWindowReverseExit?"FILTER_REVERSE_ON":"FILTER_REVERSE_OFF";
      Audit("filtered_window_reverse_toggle","",0,0,0,0,"enabled="+(g_rtFilteredWindowReverseExit?"1":"0"));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_DISP_BLOCK_EXIT")
   {
      g_rtPostTradeDispBlockExit=!g_rtPostTradeDispBlockExit;
      g_lastExecStatus=g_rtPostTradeDispBlockExit?"POST_TRADE_DISP_EXIT_ON":"POST_TRADE_DISP_EXIT_OFF";
      Audit("post_trade_disp_block_exit_toggle","",0,0,0,0,"enabled="+(g_rtPostTradeDispBlockExit?"1":"0"));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_ENTRY_WINDOW")
   {
      if(SetRuntimeEntryWindow(!g_rtEntryWindow,g_rtEntryWindowStartMin,g_rtEntryWindowEndMin))
      {
         g_lastExecStatus=g_rtEntryWindow?"ENTRY_WINDOW_ON":"ENTRY_WINDOW_OFF";
         ClearRetestState("entry_window_toggled");ClearImbalanceState("entry_window_toggled");
      }
      else g_lastExecStatus="ENTRY_WINDOW_SAVE_FAIL";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_ENTRY_WIN_APPLY")
   {
      int startMin=-1,endMin=-1;
      string startText=ObjectGetString(0,PREFIX+"EDIT_ENTRY_WIN_START",OBJPROP_TEXT);
      string endText=ObjectGetString(0,PREFIX+"EDIT_ENTRY_WIN_END",OBJPROP_TEXT);
      if(!ParseStrictClockMinutes(startText,startMin)||!ParseStrictClockMinutes(endText,endMin)
         ||!SetRuntimeEntryWindow(g_rtEntryWindow,startMin,endMin))
      {
         g_lastExecStatus="ENTRY_WINDOW_INVALID_HH_MM";
      }
      else
      {
         g_entryWindowApplyFlashUntil=TimeLocal()+2;
         g_lastExecStatus="ENTRY_WINDOW_APPLIED";
         ClearRetestState("entry_window_changed");ClearImbalanceState("entry_window_changed");
         Audit("entry_window_applied","",0,0,0,0,"window="+EntryWindowLabel());
      }
      ObjectSetString(0,PREFIX+"EDIT_ENTRY_WIN_START",OBJPROP_TEXT,ClockMinutesText(g_rtEntryWindowStartMin));
      ObjectSetString(0,PREFIX+"EDIT_ENTRY_WIN_END",OBJPROP_TEXT,ClockMinutesText(g_rtEntryWindowEndMin));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_TIME"){g_rtTimeExit=!g_rtTimeExit;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_DISP"){g_rtDisplacement=!g_rtDisplacement;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_FVG"){CycleFvgMode();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_EXIT"){CycleExitMode();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_ENTRY"){CycleEntryMode();ClearRetestState("entry_mode_changed");ClearImbalanceState("entry_mode_changed");ClearNasPending("entry_mode_changed");needRedraw=true;}
   else if(sparam==PREFIX+"BTN_XSTART"){CycleExitTrailStart();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_XPARAM"){if(g_rtExitMode==ORB_EXIT_EMA_STOP)CycleExitEmaPeriod();else CycleExitAtrMultiplier();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BE"){g_rtBEOnTp1=!g_rtBEOnTp1;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_TP"){CycleTargetLeg();g_lastExecStatus="FIXED_TP_"+TargetLabel();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_TMODE"){CycleTargetMode();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_HC"){CycleHalfBeLeg();g_lastExecStatus="FIXED_HC_"+HalfBeLabel();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_2W"){SetHistoricalWeeks(2);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_5W"){SetHistoricalWeeks(5);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_10W"){SetHistoricalWeeks(10);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_20W"){SetHistoricalWeeks(20);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_1Y"){SetHistoricalWeeks(52);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_2Y"){SetHistoricalWeeks(104);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_3Y"){SetHistoricalWeeks(156);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_4Y"){SetHistoricalWeeks(208);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_5Y"){SetHistoricalWeeks(260);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_SL_MODE")
   {
      if(LabPolicyEnabled())
      {
         g_rtPipSlMode=true;g_lastExecStatus="CUSTOM_ENGINE_PIP_ONLY";
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();return;
      }
      else {
      g_rtPipSlMode=!g_rtPipSlMode;
      ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,g_rtPipSlMode?DoubleToString(g_rtPipSlPips,1):DoubleToString(g_rtSlDistancePct,0));
      g_lastExecStatus=g_rtPipSlMode?"PIP_SL_ON":"PERCENT_SL_ON";
      needRedraw=true;
      }
   }
   else if(sparam==PREFIX+"BTN_SL_APPLY")
   {
      if(LabPolicyEnabled())
      {
         double requested=0;
         if(!NativeBalanceParse(ObjectGetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT),requested,DBL_MAX)
            ||!LabPolicySetPip(true,requested))
         {g_lastExecStatus="ENGINE_PIP_INVALID_MIN_0.1_OR_SAVE_FAILED";ObjectSetInteger(0,sparam,OBJPROP_STATE,false);return;}
         ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,DoubleToString(g_labEngine.pipSlPips,1));
         MaCrossAuditInvalidate();CancelHistoricalAuditBuild();
         g_lastExecStatus="PIP_APPLIED_"+DoubleToString(g_rtPipSlPips,1);needRedraw=true;
      }
      else {
      string valueTxt=ObjectGetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT);
      if(g_rtPipSlMode)SetPipSlPips(StringToDouble(valueTxt));
      else SetSlDistancePct(StringToDouble(valueTxt));
      ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,g_rtPipSlMode?DoubleToString(g_rtPipSlPips,1):DoubleToString(g_rtSlDistancePct,0));
      g_lastExecStatus=g_rtPipSlMode?("PIP_SL_"+DoubleToString(g_rtPipSlPips,1)):("SL_PCT_"+DoubleToString(g_rtSlDistancePct,0));
      needRedraw=true;
      }
   }
   else if(sparam==PREFIX+"BTN_AUDIT")
   {
      g_auditRuntime=!g_auditRuntime;
      Print("ORB15v3 audit logging ",g_auditRuntime?"enabled":"disabled");
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_ADV_AUD")
   {
      bool requested=!g_rtAdvancedAuditEngine;
      if(!OrbAdvancedAuditSetRuntime(requested))g_lastExecStatus="ADV_AUD_SAVE_FAILED";
      else
      {
         g_lastExecStatus=requested?"ADV_AUD_ON":"LEGACY_AUD_ON";
         QueueHistoricalRedraw(0);
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_TF")
   {
      ClearNasPending("signal_tf_changed");
      // Cycle through M1 → M5 → M15 → M1...
      g_rtSignalTf=CycleTf(g_rtSignalTf); DeleteByPrefix(PREFIX+"MA_OBS_");g_maLastObservedKey="";
      needRedraw=true;
      Print("ORB15v3 Signal TF changed to ",TfLabel(g_rtSignalTf));
   }
   else if(sparam==PREFIX+"BTN_DELAY")
   {
      // Cycle: OFF → 3m → 5m → 10m → OFF
      if(!g_rtUseDelay){g_rtUseDelay=true;g_rtDelayMin=3;}
      else if(g_rtDelayMin<=3){g_rtDelayMin=5;}
      else if(g_rtDelayMin<=5){g_rtDelayMin=10;}
      else{g_rtUseDelay=false;g_rtDelayMin=0;}
      needRedraw=true;
      Print("ORB15v3 Delay changed to ",g_rtUseDelay?IntegerToString(g_rtDelayMin)+"min":"OFF");
   }
   else if(sparam==PREFIX+"BTN_EA")
   {
      g_rtEaEnabled=!g_rtEaEnabled;g_lastExecStatus=g_rtEaEnabled?"READY":"EA_OFF";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_FTMO")
   {
      g_ftmoMode=!g_ftmoMode;if(g_ftmoMode)g_riskLotOnlyMode=false;g_runtimeMagic=0;g_riskPerfCacheAt=0;g_lastExecStatus=g_ftmoMode?"FTMO_ON":"FTMO_OFF";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_RISKLOT")
   {
      g_riskLotOnlyMode=!g_riskLotOnlyMode;if(g_riskLotOnlyMode)g_ftmoMode=false;g_runtimeMagic=0;g_riskPerfCacheAt=0;g_lastExecStatus=g_riskLotOnlyMode?"RISKLOT_ON":"RISKLOT_OFF";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_APPLY_RISK")
   {
      string raw=ObjectGetString(0,PREFIX+"EDIT_RISK_PCT",OBJPROP_TEXT);
      double requested=StringToDouble(raw);
      if(!SetRuntimeRiskPct(requested))
      {
         g_lastExecStatus="RISK_INVALID_0.01_TO_100";
         ObjectSetString(0,PREFIX+"EDIT_RISK_PCT",OBJPROP_TEXT,DoubleToString(EffRiskPerTradePct(),2));
      }
      else
      {
         g_riskPerfCacheAt=0;
         g_riskApplyFlashUntil=TimeLocal()+2;
         g_lastExecStatus="RISK_APPLIED_"+DoubleToString(EffRiskPerTradePct(),2)+"%";
         ObjectSetString(0,PREFIX+"EDIT_RISK_PCT",OBJPROP_TEXT,DoubleToString(EffRiskPerTradePct(),2));
         Print("ORB15v3 dashboard risk applied pct=",DoubleToString(EffRiskPerTradePct(),4)," key=",RuntimeRiskPctKey());
         Audit("risk_pct_applied","",0,0,0,0,"risk_pct="+DoubleToString(EffRiskPerTradePct(),4));
         if(g_orbBridgeEnabled)OrbProWriteInitMarker();
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_INVERT")
   {
      if(g_rtAdvancedReverse&&(OwnPositionExists()||g_orbBridgePlanActive))
      {g_lastExecStatus="INVERT_BLOCKED_ACTIVE_TRADE";ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();return;}
      bool requested=!g_rtInvertMode;
      if(requested&&(InpExecutionMode!=ORB_EXEC_SINGLE||!ExitModeUsesFixedTp(g_rtExitMode)))
      {
         g_lastExecStatus="INVERT_NEEDS_SINGLE_FIXED_TP";
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
      }
      if(!SetRuntimeInvertMode(requested))
      {
         g_lastExecStatus="INVERT_SAVE_FAIL";
      }
      else if(g_rtAdvancedReverse&&GlobalVariableSet(RuntimeAdvancedReverseKey(),0.0)<=0)
      {
         SetRuntimeInvertMode(true);
         g_lastExecStatus="ADV_REV_SAVE_FAIL";
      }
      else
      {
          g_rtAdvancedReverse=false;
         // Pending confirmations belong to the direction policy active when
         // they were created. Discard them instead of mutating them in flight.
         ClearRetestState("invert_changed");
         ClearImbalanceState("invert_changed");
         ClearNasPending("invert_changed");
         DeleteLive();
         DrawOrbLiveTradeLevels();
         g_lastExecStatus=g_rtInvertMode?"INVERT_ON":"INVERT_OFF";
         Audit("invert_mode_changed","",0,0,0,0,
            "invert="+(g_rtInvertMode?"1":"0")+" level_swap_inverse=1 existing_positions_unchanged=1 pending_cleared=1");
         Print("ORB15v3 dashboard invert mode=",g_rtInvertMode?"ON":"OFF"," key=",RuntimeInvertKey(),
            " existing positions remain under original geometry");
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_ADV_REVERSE")
   {
      // Ignore stale chart-object clicks from builds with a second reverse mode.
      ObjectDelete(0,sparam);return;
   }
   else if(sparam==PREFIX+"BTN_APPLY_ADV_COST")
   {
      string raw=ObjectGetString(0,PREFIX+"EDIT_ADV_COST",OBJPROP_TEXT);
      double requested=0.0;
      if(!OrbMlNumber(raw,requested)||!SetRuntimeAdvancedReverseMaxCostPct(requested))
         g_lastExecStatus="ADV_COST_INVALID_0_TO_100";
      else
      {
         g_lastExecStatus="INVERSE_MAX_GAP_"+DoubleToString(requested,2)+"PCT";
         Audit("inverse_max_quote_gap_changed","",0,0,0,0,"max_gap_pct="+DoubleToString(requested,4));
         QueueHistoricalRedraw();
      }
      ObjectSetString(0,PREFIX+"EDIT_ADV_COST",OBJPROP_TEXT,DoubleToString(g_rtAdvancedReverseMaxCostPct,2));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_UTC_SESSION")
   {
      bool requested=!g_rtUtcMidnightSession;
      if(requested&&!ValidateUtcSessionInputs())
         g_lastExecStatus="UTC00_INVALID_HH_MM_ORDER";
      else if(OwnPositionExists())
         g_lastExecStatus="UTC00_BLOCKED_NATIVE_POSITION";
      else if(g_orbBridgePlanActive)
         g_lastExecStatus="UTC00_BLOCKED_BRIDGE_POSITION";
      else if(!SetRuntimeUtcSession(requested))
         g_lastExecStatus="UTC00_SAVE_FAIL";
      else
      {
         // Pending candidates carry geometry from the old session and are safe
         // to discard. Only actual native/bridge exposure blocks a mode switch.
         ClearRetestState("session_changed");
         ClearImbalanceState("session_changed");
         ClearNasPending("session_changed");
         ClearNasManagedLifecycle("session_changed");
         DeleteLive();DeleteExecutionVisuals();
         g_nyDayKey=0;
         ResetForNewNyDay();
         g_lastExecStatus=g_rtUtcMidnightSession?"UTC00_SESSION_ON":"AUTO_SESSION_ON";
         Audit("session_mode_changed","",0,0,0,0,"utc00="+(g_rtUtcMidnightSession?"1":"0")+" session="+SessionClockLabel());
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_NAS_CONFIRM")
   {
      if(!SetRuntimeNasConfirmation(!g_rtNasConfirmation))
         g_lastExecStatus="NAS_CONFIRM_SAVE_FAIL";
      else
      {
         ClearNasPending("mode_toggled");
         ClearRetestState("nas_mode_toggled");ClearImbalanceState("nas_mode_toggled");
         g_lastExecStatus=g_rtNasConfirmation?"NAS_CONFIRM_ON":"NAS_CONFIRM_OFF";
         Audit("nas_confirmation_toggle","",0,0,0,0,
            "enabled="+(g_rtNasConfirmation?"1":"0")+" tf="+TfLabel(NasConfirmationTf()));
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_NAS_STATE_GATE")
   {
      if(!SetRuntimeNasStateGate(!g_rtNasStateGate))
         g_lastExecStatus="NAS_STATE_SAVE_FAIL";
      else
      {
         ClearNasPending("state_gate_toggled");
         ClearRetestState("nas_state_gate_toggled");ClearImbalanceState("nas_state_gate_toggled");
         g_lastExecStatus=g_rtNasStateGate?"NAS_STATE_GATE_ON":"NAS_STATE_GATE_OFF";
         Audit("nas_state_gate_toggle","",0,0,0,0,
            "enabled="+(g_rtNasStateGate?"1":"0")+" tf="+TfLabel(NasConfirmationTf())
            +" no_age_limit=1 future_wait=0");
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_NAS_EXIT")
   {
      if(g_nasManagedClosePending)
         g_lastExecStatus="NAS_EXIT_MODE_BLOCKED_CLOSE_PENDING";
      else if(!SetRuntimeNasExit(!g_rtNasExitOnOppositeSignal))
         g_lastExecStatus="NAS_EXIT_SAVE_FAIL";
      else
      {
         if(g_rtNasExitOnOppositeSignal)
         {
            EnsureNasExitLifecycle();
            if(g_nasManagedLifecycle)
            {
               // Manual enable starts monitoring from now. Restart recovery,
               // in contrast, retains the persisted scan cursor.
               g_nasManagedOppositeAt=0;
               g_nasManagedLastScanAt=TimeCurrent();
               PersistNasManagedLifecycle();
            }
         }
         else if(!RuntimeNasExitEnabled())ClearNasManagedLifecycle("exit_disabled");
         g_lastExecStatus=g_rtNasExitOnOppositeSignal?"NAS_OPPOSITE_EXIT_ON":"NAS_OPPOSITE_EXIT_OFF";
         Audit("nas_opposite_exit_toggle","",0,0,0,0,"enabled="+(g_rtNasExitOnOppositeSignal?"1":"0")+" mode="+RuntimeNasModeLabel());
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_NAS_ADD_EXIT")
   {
      if(g_nasManagedClosePending)
         g_lastExecStatus="NAS_EXIT_MODE_BLOCKED_CLOSE_PENDING";
      else if(!SetRuntimeNasAdditionalExit(!g_rtNasAdditionalExit))
         g_lastExecStatus="NAS_ADD_EXIT_SAVE_FAIL";
      else
      {
         if(g_rtNasAdditionalExit)
         {
            EnsureNasExitLifecycle();
            if(g_nasManagedLifecycle)
            {
               // A manual mode switch is forward-only for a live position;
               // historical audit is recomputed from the original entry.
               g_nasManagedOppositeAt=0;
               g_nasManagedLastScanAt=TimeCurrent();
               PersistNasManagedLifecycle();
            }
         }
         else if(!RuntimeNasExitEnabled())ClearNasManagedLifecycle("additional_exit_disabled");
         g_lastExecStatus=g_rtNasAdditionalExit?"NAS_ADDITIONAL_EXIT_ON":"NAS_ADDITIONAL_EXIT_OFF";
         Audit("nas_additional_exit_toggle","",0,0,0,0,
            "enabled="+(g_rtNasAdditionalExit?"1":"0")+" mode="+RuntimeNasModeLabel());
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_NAS_VOL")
   {
      if(!SetRuntimeNasVolumeFilter(!g_rtNasVolumeFilter))
         g_lastExecStatus="NAS_STATE_VOL_SAVE_FAIL";
      else
      {
         g_lastExecStatus=g_rtNasVolumeFilter?"NAS_STATE_VOL_ON":"NAS_STATE_VOL_OFF";
         g_lastNasOverlayClosedBar=0;
         Audit("nas_state_volume_filter_toggled","",0,0,0,0,"enabled="+(g_rtNasVolumeFilter?"1":"0")
            +" multiplier="+DoubleToString(g_rtNasVolumeMultiplier,4));
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_NAS_FLOW_VOL")
   {
      if(g_nasManagedClosePending)
         g_lastExecStatus="NAS_FLOW_VOL_BLOCKED_CLOSE_PENDING";
      else if(!SetRuntimeNasFlowVolumeFilter(!g_rtNasFlowVolumeFilter))
         g_lastExecStatus="NAS_FLOW_VOL_SAVE_FAIL";
      else
      {
         // Pending ENTRY GATE and managed exit scans must adopt one coherent
         // flow policy from this point forward.
         ClearNasPending("nas_flow_volume_toggled");
         if(g_nasManagedLifecycle)
         {
            g_nasManagedOppositeAt=0;
            g_nasManagedLastScanAt=TimeCurrent();
            PersistNasManagedLifecycle();
         }
         g_lastExecStatus=g_rtNasFlowVolumeFilter?"NAS_FLOW_VOL_ON":"NAS_FLOW_VOL_OFF";
         g_lastNasOverlayClosedBar=0;
         Audit("nas_flow_volume_filter_toggled","",0,0,0,0,"enabled="+(g_rtNasFlowVolumeFilter?"1":"0")
            +" multiplier="+DoubleToString(g_rtNasFlowVolumeMultiplier,4));
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_NAS_APPLY")
   {
      int requested=(int)StringToInteger(ObjectGetString(0,PREFIX+"EDIT_NAS_LOOKBACK",OBJPROP_TEXT));
      int requestedSensitivity=(int)StringToInteger(ObjectGetString(0,PREFIX+"EDIT_NAS_SENS",OBJPROP_TEXT));
      string requestedVolText=ObjectGetString(0,PREFIX+"EDIT_NAS_VOL_X",OBJPROP_TEXT);
      StringTrimLeft(requestedVolText);StringTrimRight(requestedVolText);StringReplace(requestedVolText,",",".");
      double requestedNasVolX=StringToDouble(requestedVolText);
      string requestedFlowVolText=ObjectGetString(0,PREFIX+"EDIT_NAS_FLOW_VOL_X",OBJPROP_TEXT);
      StringTrimLeft(requestedFlowVolText);StringTrimRight(requestedFlowVolText);StringReplace(requestedFlowVolText,",",".");
      double requestedNasFlowVolX=StringToDouble(requestedFlowVolText);
      int requestedWait=-1;
      bool waitValid=ParseStrictDurationMinutes(ObjectGetString(0,PREFIX+"EDIT_NAS_EXIT_WAIT",OBJPROP_TEXT),requestedWait);
      bool coreSignalSettingsChanged=(requested!=g_rtNasActiveSignalLookbackMinutes
         ||requestedSensitivity!=g_rtNasSensitivity);
      bool stateVolumeSettingsChanged=(MathAbs(requestedNasVolX-g_rtNasVolumeMultiplier)>0.00005);
      bool flowVolumeSettingsChanged=(MathAbs(requestedNasFlowVolX-g_rtNasFlowVolumeMultiplier)>0.00005);
      bool signalSettingsChanged=(coreSignalSettingsChanged||stateVolumeSettingsChanged||flowVolumeSettingsChanged);
      bool waitChanged=(waitValid&&requestedWait!=g_rtNasOppositeExitWaitMinutes);
      if(requested<0||requested>1440||requestedSensitivity<1||requestedSensitivity>100
              ||!MathIsValidNumber(requestedNasVolX)||requestedNasVolX<0.05||requestedNasVolX>200.0
              ||!MathIsValidNumber(requestedNasFlowVolX)||requestedNasFlowVolX<0.05||requestedNasFlowVolX>200.0||!waitValid)
         g_lastExecStatus="NAS_INVALID_S1_100_LB0_1440_STATE_FLOW_X0.05_200_WAIT";
      else
      {
         int oldLookback=g_rtNasActiveSignalLookbackMinutes,oldWait=g_rtNasOppositeExitWaitMinutes;
         int oldSensitivity=g_rtNasSensitivity;double oldNasVolX=g_rtNasVolumeMultiplier;
         double oldNasFlowVolX=g_rtNasFlowVolumeMultiplier;
         bool saved=SetRuntimeNasSensitivity(requestedSensitivity)
            &&SetRuntimeNasVolumeMultiplier(requestedNasVolX)
            &&SetRuntimeNasFlowVolumeMultiplier(requestedNasFlowVolX)
            &&SetRuntimeNasLookback(requested)
            &&SetRuntimeNasExitWait(requestedWait);
         if(!saved)
         {
            SetRuntimeNasSensitivity(oldSensitivity);SetRuntimeNasVolumeMultiplier(oldNasVolX);
            SetRuntimeNasFlowVolumeMultiplier(oldNasFlowVolX);
            SetRuntimeNasLookback(oldLookback);SetRuntimeNasExitWait(oldWait);
            g_lastExecStatus="NAS_RUNTIME_SAVE_FAIL_ROLLED_BACK";
         }
         else
         {
            g_nasApplyFlashUntil=TimeLocal()+2;
            g_lastExecStatus="NAS_APPLIED_S"+IntegerToString(g_rtNasSensitivity)
               +"_SVX"+DoubleToString(g_rtNasVolumeMultiplier,2)+"_FVX"+DoubleToString(g_rtNasFlowVolumeMultiplier,2)
               +"_LB"+IntegerToString(g_rtNasActiveSignalLookbackMinutes)+"_WAIT"+DurationMinutesText(g_rtNasOppositeExitWaitMinutes);
            if(coreSignalSettingsChanged||flowVolumeSettingsChanged)
            {
               ClearNasPending("nas_runtime_changed");
               if(g_nasManagedLifecycle)
               {
                  // A live lifecycle adopts the new NAS policy from this
                  // point forward; historical audit restarts from entry with
                  // one coherent snapshot of all newly applied values.
                  g_nasManagedOppositeAt=0;
                  g_nasManagedLastScanAt=TimeCurrent();
                  PersistNasManagedLifecycle();
               }
            }
            if(signalSettingsChanged)g_lastNasOverlayClosedBar=0;
            Audit("nas_runtime_applied","",0,0,0,0,"sensitivity="+IntegerToString(g_rtNasSensitivity)
               +" state_vol="+(g_rtNasVolumeFilter?"1":"0")+" state_vol_x="+DoubleToString(g_rtNasVolumeMultiplier,4)
               +" flow_vol="+(g_rtNasFlowVolumeFilter?"1":"0")+" flow_vol_x="+DoubleToString(g_rtNasFlowVolumeMultiplier,4)
               +" lookback_minutes="+IntegerToString(g_rtNasActiveSignalLookbackMinutes)
               +" exit_wait="+DurationMinutesText(g_rtNasOppositeExitWaitMinutes)+" tf="+TfLabel(NasConfirmationTf()));
            if(waitChanged&&g_nasManagedLifecycle)
            {
               // Re-evaluate from the original entry time. A shorter grace
               // may close immediately; preserve any opposite state already
               // latched during grace so the configured exit cannot be lost.
               PersistNasManagedLifecycle();
            }
         }
      }
      ObjectSetString(0,PREFIX+"EDIT_NAS_SENS",OBJPROP_TEXT,IntegerToString(g_rtNasSensitivity));
      ObjectSetString(0,PREFIX+"EDIT_NAS_VOL_X",OBJPROP_TEXT,DoubleToString(g_rtNasVolumeMultiplier,2));
      ObjectSetString(0,PREFIX+"EDIT_NAS_FLOW_VOL_X",OBJPROP_TEXT,DoubleToString(g_rtNasFlowVolumeMultiplier,2));
      ObjectSetString(0,PREFIX+"EDIT_NAS_LOOKBACK",OBJPROP_TEXT,IntegerToString(g_rtNasActiveSignalLookbackMinutes));
      ObjectSetString(0,PREFIX+"EDIT_NAS_EXIT_WAIT",OBJPROP_TEXT,DurationMinutesText(g_rtNasOppositeExitWaitMinutes));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw(0);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_CLOSEALL")
   {
      CloseAllOwn("manual_close");g_tradeDir=0;g_tradeOpenTime=0;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_BRIDGE_PUB")
   {
      g_orbBridgeEnabled=!g_orbBridgeEnabled;
      if(!g_orbBridgeEnabled){g_orbBridgeOnly=false;g_orbBridgeStatus="BRIDGE OFF";}else OrbProWriteInitMarker();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_BRIDGE_ONLY")
   {
      g_orbBridgeOnly=!g_orbBridgeOnly;if(g_orbBridgeOnly)g_orbBridgeEnabled=true;
      if(g_orbBridgeEnabled)OrbProWriteInitMarker();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_BRIDGE_NATIVE")
   {
      g_orbNativeWithBridgeOnly=!g_orbNativeWithBridgeOnly;
      Print("ORB native_entry_toggle chart=",ChartID()," magic=",RuntimeMagic()," nat=",g_orbNativeWithBridgeOnly," pub=",g_orbBridgeEnabled," only=",g_orbBridgeOnly);
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_BRIDGE_CH_APPLY")
   {
      int requested=(int)StringToInteger(ObjectGetString(0,PREFIX+"EDIT_BRIDGE_CH",OBJPROP_TEXT));
      requested=OrbProClampChannel(requested);
      if(requested!=g_orbBridgeChannel&&(OwnPositionExists()||g_orbBridgePlanActive||g_retestPending||g_imbPending||g_nasPending))
         g_lastExecStatus="CHANNEL_BLOCKED_ACTIVE_LIFECYCLE";
      else
      {
         OrbProApplyChannel(requested);
         g_lastExecStatus="CHANNEL_APPLIED_C"+IntegerToString(g_orbBridgeChannel);
      }
      ObjectSetString(0,PREFIX+"EDIT_BRIDGE_CH",OBJPROP_TEXT,IntegerToString(g_orbBridgeChannel));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_BTF_SIGNAL"){g_btFillMode=BT_FILL_SIGNAL_CLOSE;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTF_NEXT"){g_btFillMode=BT_FILL_NEXT_BAR_OPEN;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTF_CONS"){g_btFillMode=BT_FILL_CONSERVATIVE;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_CONS"){g_btSameBarPolicy=BT_SAMEBAR_CONSERVATIVE;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_NEAR"){g_btSameBarPolicy=BT_SAMEBAR_NEAREST_OPEN;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_TP"){g_btSameBarPolicy=BT_SAMEBAR_TP_FIRST;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_SL"){g_btSameBarPolicy=BT_SAMEBAR_SL_FIRST;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTPARITY"){g_btNativeParity=!g_btNativeParity;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BT_RUN")
   {
      if(!g_btRunning)
      {
         string wkTxt=ObjectGetString(0,PREFIX+"EDIT_BT_WEEKS",OBJPROP_TEXT);
         g_btWeeks=MathMax(1,(int)StringToInteger(wkTxt));
         g_btSpreadPts=StringToDouble(ObjectGetString(0,PREFIX+"EDIT_BT_SPREAD",OBJPROP_TEXT));
         if(g_btSpreadPts<=0) g_btSpreadPts=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
         g_btSlippagePts=MathMax(0,StringToDouble(ObjectGetString(0,PREFIX+"EDIT_BT_SLIP",OBJPROP_TEXT)));
         g_btCommissionPerLot=MathMax(0,StringToDouble(ObjectGetString(0,PREFIX+"EDIT_BT_COMM",OBJPROP_TEXT)));
         OBT_Start();
      }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_BT_STOP")
   {
      OBT_Stop();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }

   if(needRedraw)
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      QueueHistoricalRedraw();
      UpdateDashboard();
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+

#include "AuditTradeCsvAdapter.mqh"
