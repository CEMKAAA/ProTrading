//+------------------------------------------------------------------+
//| 15 Minute ORB MT5 EA – v3.1 (production)                         |
//| Interactive dashboard with toggleable filters + live sim stats.   |
//| All filters, signal TF, and confirmation delay dashboard-driven.  |
//| Session clock: NY → broker server via GMT offset.                 |
//+------------------------------------------------------------------+
#property strict
#property version "3.30"
#include <Trade/Trade.mqh>
#include "LiqNarrativeSol_RegimeV3.mqh"
#define ORB15_BUILD "2026-07-23.v6.2-liq-level-segments"

enum ORB_SESSION_PROFILE
{
   ORB_SESSION_AUTO=0,
   ORB_SESSION_US=1,
   ORB_SESSION_EU_CET=2,
   ORB_SESSION_UK=3,
   ORB_SESSION_HK=4,
   ORB_SESSION_JP=5,
   ORB_SESSION_MANUAL_NY=6
};

//=== CORE INPUTS ========================================================
input bool            InpEaEnabled          = true;
input long            InpMagic              = 15091503;
input ENUM_TIMEFRAMES InpSignalTimeframe    = PERIOD_M15;   // M15 default — M1 too noisy for ORB
input double          InpBrokerGmtOffsetHours = 0.0;
input bool            InpAutoSessionBySymbol = true;
input ORB_SESSION_PROFILE InpSessionProfile = ORB_SESSION_AUTO;
input bool            InpAutoNewYorkDst     = true;
input string          InpOrbStartNy         = "09:30";
input string          InpOrbEndNy           = "09:45";
input string          InpTradeEndNy         = "16:00";
input bool            InpUseClosedBarBreakout = true;
input double          InpMinBreakoutPoints  = 0.0;
input double          InpSlBufferPoints     = 0.0;
input double          InpSlDistancePct      = 100.0; // 100 = raw ORB SL distance, 80 = tighter, 120 = wider.
input bool            InpPipSlModeDefault   = false;
input double          InpPipSlPips          = 500.0;
input bool            InpOneTradePerNyDay   = true;
input int             InpDeviationPoints    = 30;
input int             InpMaxSpreadPoints    = 0;

//=== BREAKOUT CONFIRMATION ==============================================
input int    InpBreakoutDelayMinutes = 5;    // Wait N min after ORB end before accepting signals
input int    InpConfirmBars          = 1;    // Breakout bar must hold N closed bars above/below ORB

//=== EXECUTION MODE =====================================================
enum ORB_EXEC_MODE { ORB_EXEC_SINGLE=0, ORB_EXEC_PARTIAL_3LEG=1 };
enum ORB_TARGET_LEG { ORB_TARGET_TP1=1, ORB_TARGET_TP2=2, ORB_TARGET_TP3=3, ORB_TARGET_TP4=4, ORB_TARGET_TP5=5, ORB_TARGET_TP6=6 };
enum ORB_HC_BE_MODE { ORB_HC_BE_OFF=0, ORB_HC_BE_TP1=1, ORB_HC_BE_TP2=2, ORB_HC_BE_TP3=3, ORB_HC_BE_TP4=4, ORB_HC_BE_TP5=5 };
enum ORB_FVG_MODE { ORB_FVG_OFF=0, ORB_FVG_OPTIONAL=1, ORB_FVG_REQUIRE=2 };
enum ORB_EXIT_ENGINE_MODE { ORB_EXIT_FIXED_TARGET=0, ORB_EXIT_EOD_ONLY=1, ORB_EXIT_ORB_MID_INVALIDATION=2, ORB_EXIT_ATR_TRAIL=3, ORB_EXIT_EMA_STOP=4, ORB_EXIT_VWAP_STOP=5, ORB_EXIT_BROKER_TIME=6 };
enum ORB_ENTRY_MODE { ORB_ENTRY_BREAKOUT=0, ORB_ENTRY_PULLBACK_RETEST=1, ORB_ENTRY_IMBALANCE_M1=2 };
enum ORB_TARGET_MODE { ORB_TARGET_R_LEG=0, ORB_TARGET_RANGE_HEIGHT=1, ORB_TARGET_EOD=2, ORB_TARGET_AUTO_STOP_SIZE=3 };
enum BT_FILL_MODE { BT_FILL_SIGNAL_CLOSE=0, BT_FILL_NEXT_BAR_OPEN=1, BT_FILL_CONSERVATIVE=2 };
enum BT_SAME_BAR_POLICY { BT_SAMEBAR_CONSERVATIVE=0, BT_SAMEBAR_NEAREST_OPEN=1, BT_SAMEBAR_TP_FIRST=2, BT_SAMEBAR_SL_FIRST=3 };
input ORB_EXEC_MODE InpExecutionMode = ORB_EXEC_SINGLE;
input ORB_TARGET_LEG InpTargetTpLeg = ORB_TARGET_TP4;
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
input double InpTp2R      = 1.0;
input double InpTp3R      = 1.5;
input double InpTp4R      = 2.0;
input double InpTp5R      = 2.5;
input double InpTp6R      = 3.0;
input double InpSingleTpR = 2.0;    // Legacy fallback; target leg is preferred.

//=== FILTERS (initial state – toggleable from dashboard) ================
input bool   InpMoveToBEOnTp1       = false; // Legacy; use InpHalfBeMode for new presets.
input double InpBEOffsetPoints      = 2.0;
input bool   InpUseAtrRangeFilter   = true;
input int    InpAtrPeriod           = 14;
input double InpMinRangeAtrPct      = 15.0;
input double InpMaxRangeAtrPct      = 80.0;
input bool   InpUseVolumeFilter     = false;
input double InpVolumeMultiplier    = 1.0;
input bool   InpUseDisplacementFilter = false;
input ORB_FVG_MODE InpFvgMode       = ORB_FVG_OFF;
input int    InpDisplacementLookback = 20;
input int    InpDisplacementPercentile = 70;
input double InpMaxOpposingWickRatio = 0.45;
input int    InpFvgLookback         = 20;
input int    InpFvgScanWindow       = 10;
input int    InpFvgForwardBars      = 1;
input double InpMinFvgGapPoints     = 0.0;
input bool   InpRequireUnfilledFvg  = false;
input bool   InpFvgRequireDisplacement = false;
input bool   InpUseTimeExit         = true;
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
input double InpRiskPerTradePct  = 1.0;
input double InpFixedLot         = 0.10;
input double InpMaxLot           = 0.0;
input bool   InpUseChartScopedMagic = true;
input bool   InpAccountRiskEnabled  = true;
input bool   InpFtmoModeDefault     = false;
input bool   InpRiskLotOnlyModeDefault = false;
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
input int  InpHistoricalDays         = 35;
input int  InpHistoricalWeeks        = 5;
input bool InpAuditCsv               = false;
input bool InpAuditHistoricalSimulationCsv = false;
input bool InpLogOnInit              = false;
input bool InpTesterTradeAuditCsv    = false;
input int  InpTesterTradeAuditMaxRows= 50000;
input string InpValidationJobId      = "";
input bool   InpFileBridgeEnabled       = false;
input bool   InpFileBridgeOnlyMode      = false;
input bool   InpFileBridgeUseCommonFiles= true;
input string InpFileBridgeLatestFile    = "OrbUltimateBridge_Latest.csv";
input string InpFileBridgeAuditPrefix   = "OrbUltimateBridge_Audit_";
input bool InpRegimeTrendLowVolAllowed       = true;
input bool InpRegimeTrendHighVolAllowed      = true;
input bool InpRegimeRangeLowVolAllowed       = true;
input bool InpRegimeRangeHighVolAllowed      = true;
input bool InpRegimeTransitionPendingAllowed = true;
input bool InpRegimeTransitionFreshAllowed   = true;
input bool   InpTesterRegimeMatrix        = false; // Tester-only regime allow-list matrix export.
input int    InpTesterRegimeMatrixWeeks   = 82;
input BT_FILL_MODE InpBacktestFillMode = BT_FILL_NEXT_BAR_OPEN;
input BT_SAME_BAR_POLICY InpBacktestSameBarPolicy = BT_SAMEBAR_CONSERVATIVE;
input bool   InpBacktestUseTickReplay    = true;
input bool   InpBacktestNativeParity     = true;  // Tick replay, bid/ask fills, and fill-based SL/TP geometry.
input double InpBacktestSpreadPts       = 0.0;
input double InpBacktestSlippagePts     = 0.0;
input double InpBacktestCommissionPerLot= 0.0;

//--- Objects ------------------------------------------------------------
CTrade trade;
string PREFIX = "ORB15v3_";
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
datetime g_lastSignalBarTime = 0;
datetime g_lastCheckedSignalBarTime = 0;
datetime g_lastHistBuild = 0;
bool     g_histNeedsRedraw = true;
bool     g_histAuditRunning = false;
int      g_histAuditTotalDays = 0;
int      g_histAuditProcessedDays = 0;
double   g_histAuditProgressPct = 0.0;

//--- Runtime toggles (mutable from dashboard) ---------------------------
bool            g_rtFilterAtr     = true;
bool            g_rtFilterVol     = true;
bool            g_rtFilterDay     = false;
bool            g_rtTimeExit      = true;
bool            g_rtDisplacement  = false;
ORB_FVG_MODE    g_rtFvgMode       = ORB_FVG_OFF;
ORB_EXIT_ENGINE_MODE g_rtExitMode = ORB_EXIT_FIXED_TARGET;
ORB_ENTRY_MODE  g_rtEntryMode     = ORB_ENTRY_BREAKOUT;
ORB_TARGET_MODE g_rtTargetMode    = ORB_TARGET_R_LEG;
bool            g_rtBEOnTp1       = true;
bool            g_rtEaEnabled     = true;
bool            g_ftmoMode        = false;
bool            g_riskLotOnlyMode = false;
bool            g_auditRuntime    = false;
ENUM_TIMEFRAMES g_rtSignalTf      = PERIOD_M15;  // runtime signal timeframe
int             g_rtDelayMin      = 5;            // runtime confirmation delay
bool            g_rtUseDelay      = true;         // toggle for confirmation delay
int             g_rtTargetLeg     = 4;
int             g_rtHalfBeLeg     = 0;
int             g_rtExitTrailStartLeg = 0;
int             g_rtExitEmaPeriod = 50;
double          g_rtExitAtrMultiplier = 2.0;
int             g_rtHistoricalWeeks = 5;
double          g_rtSlDistancePct = 100.0;
bool            g_rtPipSlMode = false;
double          g_rtPipSlPips = 500.0;

#define ORB_REGIME_COUNT 6
bool   g_regimeAllowed[ORB_REGIME_COUNT];
int    g_regimeWins[ORB_REGIME_COUNT];
int    g_regimeLosses[ORB_REGIME_COUNT];
int    g_lastSignalRegime = -1;
string g_lastSignalRegimeName = "UNKNOWN";

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
double g_histNetR = 0.0;
double g_histNetMoney = 0.0;
string g_histStatLine = "-";

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
#define OBT_MAX_DAYS    60
ENUM_TIMEFRAMES g_btTFs[]  = {PERIOD_M1,PERIOD_M5,PERIOD_M15};
int             g_btDelays[]= {0,3,5,10};
OrbBtDayCache   g_btDays[];
int             g_btDayCount = 0;
// Flat [dayIdx * (tfCount*delayCount) + comboIdx] cache; MQL5 does not
// reliably support resizeable jagged arrays of structs.
OrbBtBreakout   g_btBreakouts[];

#include "OrbUltimate_ProfessionalPipeline.mqh"

//=========================================================================
//  UTILITY FUNCTIONS
//=========================================================================
int ParseClockMinutes(string v,int fb){StringTrimLeft(v);StringTrimRight(v);int p=StringFind(v,":");if(p<0)return fb;int h=(int)StringToInteger(StringSubstr(v,0,p));int m=(int)StringToInteger(StringSubstr(v,p+1));if(h<0||h>23||m<0||m>59)return fb;return h*60+m;}
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
   return ORB_SESSION_MANUAL_NY;
}
string SessionProfileLabel(ORB_SESSION_PROFILE p)
{
   if(p==ORB_SESSION_US)return "US/NY";
   if(p==ORB_SESSION_EU_CET)return "EU/CET";
   if(p==ORB_SESSION_UK)return "UK/LON";
   if(p==ORB_SESSION_HK)return "HK/HKT";
   if(p==ORB_SESSION_JP)return "JP/JST";
   if(p==ORB_SESSION_MANUAL_NY)return "MANUAL_NY";
   return "AUTO";
}
bool IsEuropeDstDate(int y,int mo,int d){if(mo<3||mo>10)return false;if(mo>3&&mo<10)return true;if(mo==3)return d>=LastSunday(y,3);if(mo==10)return d<LastSunday(y,10);return false;}
int SessionUtcOffsetSecondsForDate(ORB_SESSION_PROFILE p,int y,int mo,int d)
{
   if(p==ORB_SESSION_US||p==ORB_SESSION_MANUAL_NY)return NyUtcOffsetSecondsForDate(y,mo,d);
   if(p==ORB_SESSION_EU_CET)return IsEuropeDstDate(y,mo,d)?2*3600:1*3600;
   if(p==ORB_SESSION_UK)return IsEuropeDstDate(y,mo,d)?1*3600:0;
   if(p==ORB_SESSION_HK)return 8*3600;
   if(p==ORB_SESSION_JP)return 9*3600;
   return NyUtcOffsetSecondsForDate(y,mo,d);
}
datetime SessionLocalToServer(int y,int mo,int d,int minOfDay)
{
   ORB_SESSION_PROFILE p=ResolveSessionProfile();
   if(p==ORB_SESSION_MANUAL_NY)return NyLocalToServer(y,mo,d,minOfDay);
   int h=minOfDay/60;int mi=minOfDay%60;
   datetime local=MakeDateTime(y,mo,d,h,mi,0);
   datetime utc=local-SessionUtcOffsetSecondsForDate(p,y,mo,d);
   return utc+(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
}
datetime ServerToSessionLocal(datetime s)
{
   ORB_SESSION_PROFILE p=ResolveSessionProfile();
   if(p==ORB_SESSION_MANUAL_NY)return ServerToNyLocal(s);
   datetime utc=s-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);
   MqlDateTime u;TimeToStruct(utc,u);
   return utc+SessionUtcOffsetSecondsForDate(p,u.year,u.mon,u.day);
}
void SessionClockMinutes(int &sm,int &em,int &tem)
{
   ORB_SESSION_PROFILE p=ResolveSessionProfile();
   if(p==ORB_SESSION_US||p==ORB_SESSION_MANUAL_NY){sm=ParseClockMinutes(InpOrbStartNy,570);em=ParseClockMinutes(InpOrbEndNy,585);tem=ParseClockMinutes(InpTradeEndNy,960);return;}
   if(p==ORB_SESSION_EU_CET){sm=9*60;em=9*60+15;tem=17*60+30;return;}
   if(p==ORB_SESSION_UK){sm=8*60;em=8*60+15;tem=16*60+30;return;}
   if(p==ORB_SESSION_HK){sm=9*60+30;em=9*60+45;tem=16*60;return;}
   if(p==ORB_SESSION_JP){sm=9*60;em=9*60+15;tem=15*60+30;return;}
   sm=ParseClockMinutes(InpOrbStartNy,570);em=ParseClockMinutes(InpOrbEndNy,585);tem=ParseClockMinutes(InpTradeEndNy,960);
}
string SessionClockLabel()
{
   int sm,em,tem;SessionClockMinutes(sm,em,tem);
   return SessionProfileLabel(ResolveSessionProfile())+" "+StringFormat("%02d:%02d-%02d:%02d End %02d:%02d",sm/60,sm%60,em/60,em%60,tem/60,tem%60);
}
int CurrentSessionDayKey(int &y,int &mo,int &d){datetime loc=ServerToSessionLocal(TimeCurrent());MqlDateTime n;TimeToStruct(loc,n);y=n.year;mo=n.mon;d=n.day;return y*10000+mo*100+d;}
string FmtTime(datetime t){return t<=0?"-":TimeToString(t,TIME_DATE|TIME_SECONDS);}
string BoolText(bool v){return v?"true":"false";}
double NormalizePrice(double p){return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}
double NormalizeVolume(double v){double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(mn<=0)mn=0.01;if(mx<=0)mx=100;if(InpMaxLot>0)mx=MathMin(mx,InpMaxLot);if(st<=0)st=mn;v=MathMax(mn,MathMin(mx,v));v=MathFloor(v/st+1e-7)*st;return NormalizeDouble(MathMax(mn,v),2);}
double TickSize(){double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(ts<=0)ts=SymbolInfoDouble(_Symbol,SYMBOL_POINT);return ts>0?ts:0.00001;}
double NormalizeTradePrice(double p){double ts=TickSize();return NormalizePrice(MathRound(p/ts)*ts);}
double MinStopDistance(){double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=TickSize();long st=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);long fr=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);return MathMax((double)MathMax(st,fr)*pt,TickSize());}
double ValuePerPriceUnitPerLot(){double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);if(ts<=0)ts=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(ts<=0||tv<=0)return 0;return tv/ts;}
bool ManagedRiskMode(){return g_ftmoMode||g_riskLotOnlyMode;}
string RuntimeRiskModeLabel(){if(g_ftmoMode)return "FTMO";if(g_riskLotOnlyMode)return "RISKLOT";return "NORMAL";}
bool RiskEnabled(){return InpAccountRiskEnabled||ManagedRiskMode();}
double EffRiskPerTradePct(){return ManagedRiskMode()?1.0:InpRiskPerTradePct;}
double EffAtrExposurePct(){return ManagedRiskMode()?2.0:InpAtrExposurePct;}
double EffMaxPortfolioPct(){return g_ftmoMode?4.0:InpMaxPortfolioPct;}
double EffDailyLossLimitPct(){return g_ftmoMode?5.0:InpDailyLossLimitPct;}
double EffMaxDrawdownPct(){return g_ftmoMode?10.0:InpMaxDrawdownPct;}
double EffMaxMarginUsagePct(){return g_ftmoMode?40.0:InpMaxMarginUsagePct;}
double CalculateLot(double entry,double sl){if(!InpUseAutoRiskLot&&!ManagedRiskMode())return NormalizeVolume(InpFixedLot);double rd=MathAbs(entry-sl);double vpu=ValuePerPriceUnitPerLot();double eq=AccountInfoDouble(ACCOUNT_EQUITY);double rm=eq*MathMax(0.01,EffRiskPerTradePct())/100.0;if(rd<=0||vpu<=0||rm<=0)return NormalizeVolume(InpFixedLot);return NormalizeVolume(rm/(rd*vpu));}
int CurrentSpreadPoints(){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return 0;double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)return 0;return(int)MathRound((t.ask-t.bid)/pt);}
bool SpreadAllowed(){if(InpMaxSpreadPoints<=0)return true;return CurrentSpreadPoints()<=InpMaxSpreadPoints;}
double NormalizeLegVolume(double total,int legs){double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);if(st<=0)st=0.01;if(mn<=0)mn=0.01;double leg=MathFloor(total/(double)legs/st+1e-7)*st;return NormalizeDouble(leg,8)<mn?0:NormalizeDouble(leg,8);}
string TfLabel(ENUM_TIMEFRAMES tf){if(tf==PERIOD_M1)return "M1";if(tf==PERIOD_M5)return "M5";if(tf==PERIOD_M15)return "M15";return EnumToString(tf);}
ENUM_TIMEFRAMES CycleTf(ENUM_TIMEFRAMES current){if(current==PERIOD_M1)return PERIOD_M5;if(current==PERIOD_M5)return PERIOD_M15;return PERIOD_M1;}
int ClampTargetLeg(int leg){return MathMax(1,MathMin(6,leg));}
int ClampHalfBeLeg(int leg,int target){if(target<=1)return 0;return MathMax(0,MathMin(target-1,leg));}
int RuntimeTargetLeg(){return ClampTargetLeg(g_rtTargetLeg);}
int RuntimeHalfBeLeg(){return ClampHalfBeLeg(g_rtHalfBeLeg,RuntimeTargetLeg());}
double LegR(int leg)
{
   if(leg<=1)return MathMax(0.1,InpTp1R);
   if(leg==2)return MathMax(0.1,InpTp2R);
   if(leg==3)return MathMax(0.1,InpTp3R);
   if(leg==4)return MathMax(0.1,InpTp4R);
   if(leg==5)return MathMax(0.1,InpTp5R);
   return MathMax(0.1,InpTp6R);
}
double RuntimeTargetR(){return LegR(RuntimeTargetLeg());}
double PriceAtLeg(bool isBuy,double entry,double risk,int leg){return NormalizeTradePrice(isBuy?entry+risk*LegR(leg):entry-risk*LegR(leg));}
double SimMoneyPnl(double netR)
{
   double base=InpInitialBalanceOverride>0?InpInitialBalanceOverride:MathMax(0.01,AccountInfoDouble(ACCOUNT_BALANCE));
   return netR*base*MathMax(0,EffRiskPerTradePct())/100.0;
}
string TargetLabel(){return "TP"+IntegerToString(RuntimeTargetLeg())+"="+DoubleToString(RuntimeTargetR(),1)+"R";}
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
void CycleTargetLeg(){ForceFixedRLegTarget();SetTargetLeg(RuntimeTargetLeg()>=6?1:RuntimeTargetLeg()+1);}
void CycleHalfBeLeg(){ForceFixedRLegTarget();int target=RuntimeTargetLeg();if(target<=1){g_rtHalfBeLeg=0;return;}int h=RuntimeHalfBeLeg()+1;if(h>=target)h=0;g_rtHalfBeLeg=h;}
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
   g_lastHistBuild=0;
   g_histNeedsRedraw=true;
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

double ClampPipSlPips(double pips){return MathMax(0.1,MathMin(1000000.0,pips));}
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
   if(g_rtPipSlMode)
   {
      double dist=ClampPipSlPips(g_rtPipSlPips)*OrbPipSize();
      if(dist>0.0)return NormalizeTradePrice(isBuy?entry-dist:entry+dist);
   }
   return ScaleSlFromEntry(isBuy,entry,rawSl);
}
string RuntimeSlModeLabel(){return g_rtPipSlMode?("PIP "+DoubleToString(g_rtPipSlPips,1)):("SL% "+DoubleToString(g_rtSlDistancePct,0));}

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
bool MagicOwned(long m){return m==RuntimeMagic()||(!RiskEnabled()&&m==InpMagic);}
string BtFillLabel(BT_FILL_MODE m){switch(m){case BT_FILL_SIGNAL_CLOSE:return"SIGNAL";case BT_FILL_NEXT_BAR_OPEN:return"NEXT";case BT_FILL_CONSERVATIVE:return"CONS";}return"SIGNAL";}
string BtSameBarLabel(BT_SAME_BAR_POLICY p){switch(p){case BT_SAMEBAR_CONSERVATIVE:return"CONS";case BT_SAMEBAR_NEAREST_OPEN:return"NEAR";case BT_SAMEBAR_TP_FIRST:return"TP1ST";case BT_SAMEBAR_SL_FIRST:return"SL1ST";}return"CONS";}
double BtCostR(double risk,bool includeSpread=true,bool includeSlippage=true)
{
   if(risk<=0)return 0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.00001;
   double pts=0.0;
   if(includeSpread)pts+=MathMax(0,g_btSpreadPts);
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
bool BtTpFirst(bool isBuy,double openPx,double sl,double tp)
{
   if(g_btSameBarPolicy==BT_SAMEBAR_TP_FIRST)return true;
   if(g_btSameBarPolicy==BT_SAMEBAR_SL_FIRST||g_btSameBarPolicy==BT_SAMEBAR_CONSERVATIVE)return false;
   double dTp=isBuy?(tp-openPx):(openPx-tp);
   double dSl=isBuy?(openPx-sl):(sl-openPx);
   return dTp<dSl;
}

bool BuildSimGeometry(bool isBuy,double fillEntry,double plannedSl,
                      double &simSl,double &risk,double &tp1,double &tp2,double &tp3,double &tp4,double &tp5,double &tp6)
{
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double rawSl=plannedSl;
   if(g_orbHigh>g_orbLow)
   {
      double buffer=MathMax(0.0,InpSlBufferPoints)*pt;
      rawSl=isBuy?(g_orbLow-buffer):(g_orbHigh+buffer);
   }
   simSl=ApplyRuntimeSlFromEntry(isBuy,fillEntry,rawSl);
   risk=MathAbs(fillEntry-simSl);
   if(risk<=pt)return false;
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

bool ResolveTargetPriceAndR(bool isBuy,double entry,double risk,double &targetPrice,double &targetR,string &detail)
{
   targetPrice=0.0;
   targetR=0.0;
   detail=RuntimeTargetModeLabel();
   if(risk<=0.0)return false;
   if(g_rtTargetMode==ORB_TARGET_EOD)
   {
      detail+=" no_fixed_tp";
      return true;
   }
   if(g_rtTargetMode==ORB_TARGET_RANGE_HEIGHT)
   {
      double range=MathAbs(g_orbHigh-g_orbLow);
      if(range<=0.0)return false;
      targetR=(range*MathMax(0.1,InpRangeTargetMultiplier))/risk;
      targetPrice=NormalizeTradePrice(isBuy?entry+risk*targetR:entry-risk*targetR);
      detail+=" range="+DoubleToString(range,_Digits)+" mult="+DoubleToString(InpRangeTargetMultiplier,2)+" r="+DoubleToString(targetR,2);
      return true;
   }
   if(g_rtTargetMode==ORB_TARGET_AUTO_STOP_SIZE)
   {
      double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
      double stopPts=risk/pt;
      targetR=stopPts<=MathMax(0.0,InpSmallStopThresholdPts)?MathMax(0.1,InpSmallStopTargetR):MathMax(0.1,InpLargeStopTargetR);
      targetPrice=NormalizeTradePrice(isBuy?entry+risk*targetR:entry-risk*targetR);
      detail+=" stopPts="+DoubleToString(stopPts,1)+" r="+DoubleToString(targetR,2);
      return true;
   }
   targetR=LegR(RuntimeTargetLeg());
   targetPrice=PriceAtLeg(isBuy,entry,risk,RuntimeTargetLeg());
   detail+=" leg=TP"+IntegerToString(RuntimeTargetLeg())+" r="+DoubleToString(targetR,2);
   return true;
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

bool SendOrbOrder(string dir,double lot,double entry,double sl,double tp,string comment,string &detail)
{
   ENUM_ORDER_TYPE type=dir=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   bool ok=trade.PositionOpen(_Symbol,type,lot,entry,sl,tp,comment);
   uint rc=trade.ResultRetcode();
   if(ok&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED))
   {
      detail="order_ok ret="+IntegerToString((int)rc);
      return true;
   }
   if(rc!=TRADE_RETCODE_INVALID_STOPS && rc!=10016)
   {
      detail="order_failed ret="+IntegerToString((int)rc)+" "+trade.ResultRetcodeDescription();
      return false;
   }

   string firstFail="invalid_stops ret="+IntegerToString((int)rc)+" "+trade.ResultRetcodeDescription();
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

double ClosedDailyAtr(){int h=iATR(_Symbol,PERIOD_D1,MathMax(2,InpAtrPeriod));if(h==INVALID_HANDLE)return 0;double v[];ArraySetAsSeries(v,true);int c=CopyBuffer(h,0,1,1,v);IndicatorRelease(h);return(c==1&&v[0]>0)?v[0]:0;}

double ResolveLot(string dir,double entry,double sl,string &detail)
{
   double fallback=CalculateLot(entry,sl);
   if(!RiskEnabled()){detail="risk_off";return fallback;}
   double cap,dp,tp;RiskMetrics(cap,dp,tp);
   double sf=MathMax(1,MathMin(100,InpSafetyBufferPct))/100.0;
   double mu=cap>0?AccountInfoDouble(ACCOUNT_MARGIN)/cap*100.0:100.0;
   if(cap<=0||(EffDailyLossLimitPct()>0&&dp>=EffDailyLossLimitPct()*sf)||(EffMaxDrawdownPct()>0&&tp>=EffMaxDrawdownPct()*sf)||(EffMaxMarginUsagePct()>0&&mu>=EffMaxMarginUsagePct()))
   {detail="risk_block cap="+DoubleToString(cap,2)+" daily="+DoubleToString(dp,2)+" dd="+DoubleToString(tp,2);return InpFailClosed?0:fallback;}
   ENUM_ORDER_TYPE ot=dir=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double slRes=0,atrRes=0,atr=ClosedDailyAtr();
   double atrExit=dir=="BUY"?entry-atr:entry+atr;
   if(atr<=0||!OrderCalcProfit(ot,_Symbol,1.0,entry,sl,slRes)||!OrderCalcProfit(ot,_Symbol,1.0,entry,atrExit,atrRes))
   {detail="risk_calc_fail";return InpFailClosed?0:fallback;}
   double slMpl=MathAbs(slRes),atrMpl=MathAbs(atrRes);
   if(slMpl<=0||atrMpl<=0){detail="risk_zero_mpl";return InpFailClosed?0:fallback;}
   double tradeBudget=cap*MathMax(0,EffRiskPerTradePct())/100.0;
   double atrBudget=cap*MathMax(0,EffAtrExposurePct())/100.0;
   double portfolioBudget=cap*MathMax(0,EffMaxPortfolioPct())/100.0;
   double avail=MathMax(0,portfolioBudget-OpenScopeRisk());
   if(tradeBudget<=0||atrBudget<=0||avail<=0){detail="budget_exhausted";return 0;}
   double raw=MathMin(tradeBudget/slMpl,MathMin(atrBudget/atrMpl,avail/slMpl));
   double vol=NormalizeVolume(raw);
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
void DeleteByPrefix(const string pfx){for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--){string n=ObjectName(0,i,0,-1);if(StringFind(n,pfx)==0)ObjectDelete(0,n);}}
void DeleteLevels(){ObjectDelete(0,PREFIX+"ORB_HIGH");ObjectDelete(0,PREFIX+"ORB_LOW");ObjectDelete(0,PREFIX+"ORB_TXT");}
void DeleteHist(){DeleteByPrefix(PREFIX+"HIST_");}
void DeleteLive(){DeleteByPrefix(PREFIX+"LIVE_");}
void DeleteDash(){DeleteByPrefix(PREFIX+"DASH_");DeleteByPrefix(PREFIX+"BTN_");DeleteByPrefix(PREFIX+"EDIT_");}

void DrawOrbHistoricalSegment(string id,datetime t1,datetime t2,double price,color clr,ENUM_LINE_STYLE style=STYLE_SOLID)
{
   if(IsTesterMode()||!InpDrawTradeLevelSegments||price<=0.0||t2<=t1)return;
   string name=PREFIX+"HIST_LVL_"+id;
   if(ObjectFind(0,name)>=0&&(ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_TREND)
      ObjectDelete(0,name);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectMove(0,name,0,t1,price);
   ObjectMove(0,name,1,t2,price);
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

void DrawOrbLiveTradeLevels()
{
   if(IsTesterMode())return;
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
      double hc=OrbProGet(positionId,"half",0.0);
      int segSec=MathMax(60,PeriodSeconds(RuntimeEntryTf()))*20;
      datetime liveEnd=TimeCurrent()+segSec;
      if(liveEnd<=openedAt)liveEnd=openedAt+segSec;

      DrawOrbLiveSegment("ENTRY_"+token,openedAt,liveEnd,entry,C'245,245,255',STYLE_SOLID,4);
      if(sl>0.0)DrawOrbLiveSegment("SL_"+token,openedAt,liveEnd,sl,C'255,40,70',STYLE_SOLID,4);
      else ObjectDelete(0,PREFIX+"LIVE_LVL_SL_"+token);
      if(tp>0.0)DrawOrbLiveSegment("TP_"+token,openedAt,liveEnd,tp,C'20,255,160',STYLE_SOLID,4);
      else ObjectDelete(0,PREFIX+"LIVE_LVL_TP_"+token);
      if(hc>0.0)DrawOrbLiveSegment("HC_"+token,openedAt,liveEnd,hc,C'255,204,82',STYLE_SOLID,4);
      else ObjectDelete(0,PREFIX+"LIVE_LVL_HC_"+token);
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

void CreateRect(const string name,int x,int y,int w,int h,color bg,color brd)
{
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
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,obj,OBJPROP_STATE,false);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);ObjectSetInteger(0,obj,OBJPROP_ZORDER,DASH_Z+2);
}
void CreateEdit(const string name,int x,int y,int w,int h,string text)
{
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
}

//=========================================================================
//  SIGNAL ARROWS
//=========================================================================
void DrawSignalArrow(const string name,datetime t,double price,bool buy,bool hist)
{
   if(IsTesterMode()) return;
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   else ObjectMove(0,name,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,buy?233:234);
   ObjectSetInteger(0,name,OBJPROP_COLOR,buy?clrLime:clrTomato);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,hist?2:3);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}
void DrawSignalText(const string name,datetime t,double price,string text,color clr)
{
   if(IsTesterMode()) return;
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   else ObjectMove(0,name,0,t,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}

//=========================================================================
//  ORB LEVEL LINES
//=========================================================================
void DrawLevels()
{
   if(IsTesterMode()) return;
   if(!g_orbReady)return;
   if(ObjectFind(0,PREFIX+"ORB_HIGH")<0)ObjectCreate(0,PREFIX+"ORB_HIGH",OBJ_HLINE,0,0,g_orbHigh);
   ObjectSetDouble(0,PREFIX+"ORB_HIGH",OBJPROP_PRICE,NormalizePrice(g_orbHigh));
   ObjectSetInteger(0,PREFIX+"ORB_HIGH",OBJPROP_COLOR,clrDodgerBlue);ObjectSetInteger(0,PREFIX+"ORB_HIGH",OBJPROP_WIDTH,2);
   if(ObjectFind(0,PREFIX+"ORB_LOW")<0)ObjectCreate(0,PREFIX+"ORB_LOW",OBJ_HLINE,0,0,g_orbLow);
   ObjectSetDouble(0,PREFIX+"ORB_LOW",OBJPROP_PRICE,NormalizePrice(g_orbLow));
   ObjectSetInteger(0,PREFIX+"ORB_LOW",OBJPROP_COLOR,clrTomato);ObjectSetInteger(0,PREFIX+"ORB_LOW",OBJPROP_WIDTH,2);
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
bool BuildOrb()
{
   if(g_orbReady)return true;if(TimeCurrent()<g_orbEndServer)return false;
   MqlRates r[];int c=CopyRates(_Symbol,PERIOD_M1,g_orbStartServer,g_orbEndServer,r);
   if(c<=0){Audit("orb_fail","",0,0,0,0,"no_data");return false;}
   double hi=-DBL_MAX,lo=DBL_MAX,tv=0;int used=0;
   for(int i=0;i<c;i++){if(r[i].time<g_orbStartServer||r[i].time>=g_orbEndServer)continue;hi=MathMax(hi,r[i].high);lo=MathMin(lo,r[i].low);tv+=(double)r[i].tick_volume;used++;}
   if(used<=0||hi<=lo){Audit("orb_fail","",0,0,0,0,"invalid used="+IntegerToString(used));return false;}
   g_orbHigh=NormalizePrice(hi);g_orbLow=NormalizePrice(lo);g_orbAvgVolume=tv/(double)used;g_orbReady=true;
   Audit("orb_ready","",0,0,0,0,"session="+SessionClockLabel()+" bars="+IntegerToString(used)+" range="+DoubleToString(hi-lo,_Digits));DrawLevels();return true;
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
bool FindHistBreakout(datetime from,datetime to,double hi,double lo,
                      string &dir,datetime &sigT,double &sigC,double &sigH,double &sigL,
                      double &sigVol,double &preBreakoutAvgVol)
{
   dir="";sigT=0;sigC=0;sigH=0;sigL=0;sigVol=0;preBreakoutAvgVol=0;
   // Apply confirmation delay
   datetime effectiveFrom = from;
   if(g_rtUseDelay && g_rtDelayMin > 0)
      effectiveFrom = from + g_rtDelayMin * 60;
   if(effectiveFrom >= to) return false;

   MqlRates r[];int c=CopyRates(_Symbol,g_rtSignalTf,from,to,r);if(c<=0)return false;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double mb=MathMax(0.0,InpMinBreakoutPoints)*pt;
   int bi=-1;string bd="";
   for(int i=0;i<c;i++)
   {
      datetime closeTime = BarCloseTime(g_rtSignalTf, r[i].time);
      if(closeTime<effectiveFrom||closeTime>to)continue;
      string d="";
      if(r[i].close>hi+mb)d="BUY";
      else if(r[i].close<lo-mb)d="SELL";
      if(d=="")continue;
      // Confirmation: check that the next N bars also confirm the breakout
      int confirmIdx = i;
      if(InpConfirmBars > 1)
      {
         bool confirmed = true;
         if(i + InpConfirmBars - 1 >= c)
            confirmed = false;
         for(int cb = 1; cb < InpConfirmBars && i+cb < c; cb++)
         {
            if(d=="BUY" && r[i+cb].close <= hi) { confirmed = false; break; }
            if(d=="SELL" && r[i+cb].close >= lo) { confirmed = false; break; }
         }
         if(confirmed)
         {
            confirmIdx = i + InpConfirmBars - 1;
            if(BarCloseTime(g_rtSignalTf, r[confirmIdx].time) > to)
               confirmed = false;
         }
         if(!confirmed) continue;
      }
      bi=confirmIdx;bd=d;break; // first valid confirmed breakout
   }
   if(bi<0)return false;
   dir=bd;sigT=r[bi].time;sigC=r[bi].close;sigH=r[bi].high;sigL=r[bi].low;sigVol=(double)r[bi].tick_volume;
   // Calculate pre-breakout rolling average volume (20 bars before breakout)
   int lookback=MathMin(20,bi);
   if(lookback>0){double vs=0;for(int j=bi-lookback;j<bi;j++)vs+=(double)r[j].tick_volume;preBreakoutAvgVol=vs/(double)lookback;}
   return true;
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
   if(mode==ORB_ENTRY_BREAKOUT)return true;
   if(mode==ORB_ENTRY_IMBALANCE_M1)
      return FindM1ImbalanceEntry(dir,BarCloseTime(g_rtSignalTf,breakoutT),tradeEnd,hi,lo,entryT,entryPrice,detail);

   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0.0)pt=0.00001;
   double tol=MathMax(0.0,InpRetestTolerancePoints)*pt;
   double resume=MathMax(0.0,InpRetestResumePoints)*pt;
   double level=(dir=="BUY")?hi:lo;
   datetime start=BarCloseTime(g_rtSignalTf,breakoutT);
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
   if(!requireDisp&&fvgMode==ORB_FVG_OFF)return true;
   bool hasDisp=false,hasFvg=false;
   AnalyzeModernSetup(from,to,tf,sigT,dir,hasDisp,hasFvg,detail);
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
   double simEntry;  // actual simulated fill entry
   double simSl;     // simulated effective initial SL
   double simTarget; // selected final target price
   double costR;     // spread/slippage/commission cost in R
   int targetLeg;    // selected target leg
   int hcLeg;        // selected HC+BE leg
   string exitMode;   // exit mode label used for this simulation
   double exitPrice;  // dynamic/time exit price when applicable
};

void WriteInternalSimAudit(string source,datetime sigTime,datetime simEnd,string dir,double plannedEntry,double plannedSl,const HistResult &sim,string detail)
{
   if(!g_auditRuntime||!InpAuditHistoricalSimulationCsv) return;
   string fileName="ORB15_InternalSimAudit_"+AuditDateStr()+".csv";
   bool exists=FileIsExist(fileName);
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return;
   if(!exists||FileSize(h)==0)
      FileWrite(h,"ts_gmt","ts_server","source","build","symbol","chart_tf","signal_tf","direction",
         "signal_time","sim_end","fill_mode","same_bar_policy","native_parity","exit_mode",
         "planned_entry","planned_sl","sim_entry","sim_sl","sim_target","target_leg","hc_leg",
         "max_tp","outcome","exit_price","cost_r","net_r","is_win","detail");
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
      DoubleToString(sim.exitPrice,_Digits),DoubleToString(sim.costR,4),DoubleToString(sim.netR,4),(sim.isWin?"1":"0"),detail);
   FileClose(h);
}

bool SimulateTradeTicks(datetime sigTime,datetime tradeEnd,double entry,double sl,bool isBuy,
                        int halfBeLeg,HistResult &res)
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
   int copied=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,fromMs,toMs);
   if(copied<=0)return false;

   int first=-1;
   for(int i=0;i<copied;i++)
   {
      double bid=ticks[i].bid;
      double ask=ticks[i].ask;
      if(bid>0.0 && ask>0.0){first=i;break;}
   }
   if(first<0)return false;

   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(pt<=0.0)pt=0.00001;
   double slip=MathMax(0.0,g_btSlippagePts)*pt;
   entry=isBuy?(ticks[first].ask+slip):(ticks[first].bid-slip);
   entry=NormalizeTradePrice(entry);

   int targetLeg=RuntimeTargetLeg();
   int hcLeg=ClampHalfBeLeg(halfBeLeg,targetLeg);
   res.targetLeg=targetLeg;
   res.hcLeg=hcLeg;
   double risk=0.0,tp1=0,tp2=0,tp3=0,tp4=0,tp5=0,tp6=0;
   if(!BuildSimGeometry(isBuy,entry,sl,sl,risk,tp1,tp2,tp3,tp4,tp5,tp6))return false;
   double tps[6];tps[0]=tp1;tps[1]=tp2;tps[2]=tp3;tps[3]=tp4;tps[4]=tp5;tps[5]=tp6;
   double targetPrice=0.0,targetR=0.0;string targetDetail="";
   if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail))return false;
   bool fixedTarget=ExitModeUsesFixedTp(g_rtExitMode)&&targetPrice>0.0;
   res.simEntry=entry;
   res.simSl=sl;
   res.simTarget=fixedTarget?targetPrice:0.0;

   double effSl=sl;
   bool beApplied=false;
   datetime fillTime=(datetime)ticks[first].time;
   datetime brokerExitAt=(g_rtExitMode==ORB_EXIT_BROKER_TIME?BrokerTimeExitFor(fillTime):0);
   for(int i=first;i<copied;i++)
   {
      double bid=ticks[i].bid;
      double ask=ticks[i].ask;
      if(bid<=0.0 || ask<=0.0)continue;
      double closePx=isBuy?bid:ask;

      if(g_rtTimeExit && InpTimeExitMinutes>0 && (datetime)ticks[i].time>=fillTime+InpTimeExitMinutes*60)
      {
         double progressR=SimSignedR(isBuy,entry,closePx,risk);
         if(progressR<InpTimeExitMinProgress)
         {
            res.outcome="TIME_EXIT";
            res.exitPrice=closePx;
            break;
         }
      }

      if((g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)&&(datetime)ticks[i].time>=tradeEnd)
      {
         res.outcome="EOD_EXIT";
         res.exitPrice=closePx;
         break;
      }
      if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&(datetime)ticks[i].time>=brokerExitAt)
      {
         res.outcome="BROKER_TIME_EXIT";
         res.exitPrice=closePx;
         break;
      }

      bool slHit=isBuy?(closePx<=effSl):(closePx>=effSl);
      if(slHit)
      {
         res.exitPrice=effSl;
         res.outcome=beApplied?"BE":"SL";
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
         res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?"TP"+IntegerToString(targetLeg):"TARGET");
         res.exitPrice=targetPrice;
         break;
      }
   }

   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      double leg1=res.maxTp>=1?LegR(1):(res.outcome=="SL"?-1.0:0);
      double leg2=res.maxTp>=2?LegR(2):(res.maxTp>=1&&hcLeg>0?0:-1.0);
      double leg3=res.maxTp>=3?LegR(3):(res.maxTp>=1&&hcLeg>0?0:-1.0);
      if(res.outcome=="SL"&&res.maxTp==0){leg1=-1;leg2=-1;leg3=-1;}
      res.netR=(leg1+leg2+leg3)/3.0;
   }
   else
   {
      if(fixedTarget&&res.exitPrice==targetPrice)
      {
         res.netR=hcLeg>0?0.5*LegR(hcLeg)+0.5*targetR:targetR;
      }
      else if(res.outcome=="TIME_EXIT")
      {
         double runnerR=SimSignedR(isBuy,entry,res.exitPrice,risk);
         res.netR=(hcLeg>0&&res.maxTp>=hcLeg)?0.5*LegR(hcLeg)+0.5*runnerR:runnerR;
      }
      else if(res.outcome=="EOD_EXIT"||res.outcome=="BROKER_TIME_EXIT")
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
                         double tp1,double tp2,double tp3,int halfBeLeg)
{
   HistResult res;
   res.maxTp=0;res.outcome="open";res.netR=0;res.isWin=false;
   res.simEntry=entry;res.simSl=sl;res.simTarget=0;res.costR=0;
   res.exitMode=RuntimeExitLabel();res.exitPrice=0;
   res.targetLeg=RuntimeTargetLeg();res.hcLeg=ClampHalfBeLeg(halfBeLeg,res.targetLeg);
   if(SimulateTradeTicks(sigTime,tradeEnd,entry,sl,isBuy,halfBeLeg,res))
      return res;
   ENUM_TIMEFRAMES entryTf=RuntimeEntryTf();
   MqlRates r[];int c=CopyRates(_Symbol,entryTf,sigTime,tradeEnd,r);
   if(c<=1)return res;
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN && c>1) entry=r[1].open;
   else if(g_btFillMode==BT_FILL_CONSERVATIVE && c>1)
   {
      double no=r[1].open;
      entry=isBuy?MathMax(entry,no):MathMin(entry,no);
   }
   entry=NormalizeTradePrice(entry);
   double risk=0.0;
   double gt1=0,gt2=0,gt3=0,gt4=0,gt5=0,gt6=0;
   if(!BuildSimGeometry(isBuy,entry,sl,sl,risk,gt1,gt2,gt3,gt4,gt5,gt6))return res;

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
   if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail))return res;
   bool fixedTarget=ExitModeUsesFixedTp(g_rtExitMode)&&targetPrice>0.0;
   res.simEntry=NormalizePrice(entry);
   res.simSl=NormalizePrice(sl);
   res.simTarget=fixedTarget?targetPrice:0.0;

   double effSl=sl;bool beApplied=false;
   double bestHigh=entry,bestLow=entry;
   datetime brokerExitAt=(g_rtExitMode==ORB_EXIT_BROKER_TIME?BrokerTimeExitFor(sigTime):0);
   for(int i=1;i<c;i++) // skip signal bar itself
   {
      if(r[i].time>tradeEnd)break;
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
         if(customTargetHit&&g_rtTargetMode!=ORB_TARGET_R_LEG)hitLeg=MathMax(hitLeg,targetLeg);
      }

      // Same-bar first-touch approximation only matters before any profit leg has been reached.
      if(slHit&&hitLeg>0&&res.maxTp==0)
      {
         int compareLeg=MathMax(1,MathMin(targetLeg,hitLeg));
         if(BtTpFirst(isBuy,r[i].open,effSl,tps[compareLeg-1]))
         {
            res.maxTp=hitLeg;
            if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
            bool targetTouched=fixedTarget&&(isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice));
            bool targetDone=fixedTarget&&(g_rtTargetMode!=ORB_TARGET_R_LEG?targetTouched:(res.maxTp>=targetLeg));
            if(targetDone){res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?"TP"+IntegerToString(targetLeg):"TARGET");res.exitPrice=targetPrice;break;}
         }
         else{res.outcome="SL";break;}
      }
      else
      {
         if(slHit){res.outcome=beApplied?"BE":"SL";break;}
         if(hitLeg>res.maxTp)res.maxTp=hitLeg;
      }

      if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
      if(fixedTarget)
      {
         bool targetHit=isBuy?(r[i].high>=targetPrice):(r[i].low<=targetPrice);
         if(targetHit){res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?"TP"+IntegerToString(targetLeg):"TARGET");res.exitPrice=targetPrice;break;}
      }

      if(g_rtTimeExit && InpTimeExitMinutes>0 && r[i].time>=sigTime+InpTimeExitMinutes*60)
      {
         double progressR=SimSignedR(isBuy,entry,r[i].close,risk);
         if(progressR<InpTimeExitMinProgress)
         {
            res.outcome="TIME_EXIT";
            res.exitPrice=r[i].close;
            break;
         }
      }

      if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&r[i].time>=brokerExitAt)
      {
         res.outcome="BROKER_TIME_EXIT";
         res.exitPrice=r[i].close;
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
            if(ex){res.outcome="MID_EXIT";res.exitPrice=r[i].close;break;}
         }
         else if(g_rtExitMode==ORB_EXIT_VWAP_STOP)
         {
            double vwap=SessionVwap(g_orbStartServer,r[i].time+sec,PERIOD_M1);
            bool ex=vwap>0.0&&(isBuy?(r[i].close<vwap):(r[i].close>vwap));
            if(ex){res.outcome="VWAP_EXIT";res.exitPrice=r[i].close;break;}
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
            if(ex){res.outcome="EMA_EXIT";res.exitPrice=r[i].close;break;}
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
   if(res.outcome=="open"&&(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)&&c>1){res.outcome="EOD_EXIT";res.exitPrice=r[c-1].close;}
   else if(res.outcome=="open"&&g_rtExitMode==ORB_EXIT_BROKER_TIME&&c>1){res.outcome="BROKER_TIME_EXIT";res.exitPrice=r[c-1].close;}

   // Net R calculation.
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      double leg1=res.maxTp>=1?LegR(1):(res.outcome=="SL"?-1.0:0);
      double leg2=res.maxTp>=2?LegR(2):(res.maxTp>=1&&hcLeg>0?0:-1.0);
      double leg3=res.maxTp>=3?LegR(3):(res.maxTp>=1&&hcLeg>0?0:-1.0);
      if(res.outcome=="SL"&&res.maxTp==0){leg1=-1;leg2=-1;leg3=-1;}
      res.netR=(leg1+leg2+leg3)/3.0;
   }
   else
   {
      if((g_rtTargetMode==ORB_TARGET_R_LEG&&res.maxTp>=targetLeg)||(g_rtTargetMode!=ORB_TARGET_R_LEG&&res.outcome=="TARGET"))
      {
         if(hcLeg>0)res.netR=0.5*LegR(hcLeg)+0.5*targetR;
         else res.netR=targetR;
      }
      else if(res.outcome=="MID_EXIT"||res.outcome=="VWAP_EXIT"||res.outcome=="EMA_EXIT"||res.outcome=="EOD_EXIT"||res.outcome=="TIME_EXIT"||res.outcome=="BROKER_TIME_EXIT")
      {
         double px=res.exitPrice>0?res.exitPrice:(c>1?r[c-1].close:entry);
         double runnerR=SimSignedR(isBuy,entry,px,risk);
         res.netR=(hcLeg>0&&res.maxTp>=hcLeg)?0.5*LegR(hcLeg)+0.5*runnerR:runnerR;
      }
      else if((res.outcome=="BE"||res.outcome=="open"||res.outcome=="TP"+IntegerToString(res.maxTp))&&hcLeg>0&&res.maxTp>=hcLeg)
         res.netR=0.5*LegR(hcLeg);
      else if(res.outcome=="SL")res.netR=-1.0;
   }
   res.costR=BtCostR(risk);
   res.netR-=res.costR;
   res.isWin=res.netR>0;
   return res;
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
   if(sigVol<avgVol*InpVolumeMultiplier){reason="VOL_LOW";return false;}
   return true;
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

bool FindNextHistoricalSignalAfter(datetime afterTime,datetime limitTime,datetime &nextSig)
{
   nextSig=0;
   if(limitTime<=afterTime)return false;
   datetime nyAfter=ServerToSessionLocal(afterTime);
   datetime nyLimit=ServerToSessionLocal(limitTime);
   MqlDateTime a,l;TimeToStruct(nyAfter,a);TimeToStruct(nyLimit,l);
   datetime nyDay=MakeDateTime(a.year,a.mon,a.day,0,0,0);
   datetime nyLast=MakeDateTime(l.year,l.mon,l.day,0,0,0);
   for(datetime d=nyDay;d<=nyLast;d+=86400)
   {
      MqlDateTime daySt;TimeToStruct(d,daySt);
      if(daySt.day_of_week==0||daySt.day_of_week==6)continue;

      double hi,lo,avgV;datetime os,oe,te;int used;
      if(!BuildOrbForNyDate(daySt.year,daySt.mon,daySt.day,hi,lo,os,oe,te,used,avgV))continue;

      string fr="";
      if(!HistCheckDay(daySt.day_of_week,fr))continue;
      if(!HistCheckAtr(hi-lo,os,fr))continue;

      string dir;datetime sigT;double sigC,sigH,sigL,sigVol,preAvgVol;
      if(!FindHistBreakout(oe,te,hi,lo,dir,sigT,sigC,sigH,sigL,sigVol,preAvgVol))continue;
      if(sigT<=afterTime)continue;
      if(!HistCheckVol(sigVol,preAvgVol,fr))continue;

      string modernDetail="";
      if(!ModernFilterAllows(oe,te,g_rtSignalTf,sigT,dir,g_rtDisplacement,g_rtFvgMode,fr,modernDetail))continue;

      nextSig=sigT;
      return true;
   }
   return false;
}

//=========================================================================
//  HISTORICAL SIGNAL DRAWING WITH SIMULATION
//=========================================================================
void DrawHistoricalSignals()
{
   if(IsTesterMode()){g_histAuditRunning=false;DeleteHist();g_histStatLine="tester_skip";return;}
   if(!InpDrawHistoricalSignals){g_histAuditRunning=false;DeleteHist();g_histStatLine="off";return;}
   datetime now=TimeCurrent();
   if(!g_histNeedsRedraw&&g_lastHistBuild>0&&now-g_lastHistBuild<300)return;
   g_lastHistBuild=now;g_histNeedsRedraw=false;
   DeleteHist();

   datetime nyNow=ServerToSessionLocal(now);MqlDateTime nySt;TimeToStruct(nyNow,nySt);
   datetime nyMid=MakeDateTime(nySt.year,nySt.mon,nySt.day,0,0,0);
   int days=RuntimeHistoricalDays();
   g_histAuditRunning=true;g_histAuditTotalDays=days;g_histAuditProcessedDays=0;g_histAuditProgressPct=0.0;
   UpdateDashboard();ChartRedraw(0);
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.0001;

   g_histTotal=0;g_histWins=0;g_histLosses=0;g_histNetR=0;g_histNetMoney=0;
   for(int ri=0;ri<ORB_REGIME_COUNT;ri++){g_regimeWins[ri]=0;g_regimeLosses[ri]=0;}
   int checked=0,drawn=0,filtered=0;

   Print("ORB15v3 ======= HIST REDRAW START ======= TF=",TfLabel(g_rtSignalTf),
         " Delay=",g_rtUseDelay?IntegerToString(g_rtDelayMin)+"min":"OFF",
         " ATR=",g_rtFilterAtr?"ON":"OFF"," VOL=",g_rtFilterVol?"ON":"OFF",
         " DAY=",g_rtFilterDay?"ON":"OFF"," ",HalfBeLabel(),
         " ",TargetLabel()," audit_weeks=",IntegerToString(g_rtHistoricalWeeks));

   for(int back=days-1;back>=0;back--)
   {
      datetime nyDay=nyMid-back*86400;MqlDateTime daySt;TimeToStruct(nyDay,daySt);
      g_histAuditProcessedDays=days-back;
      g_histAuditProgressPct=100.0*(double)g_histAuditProcessedDays/(double)MathMax(1,g_histAuditTotalDays);
      if((g_histAuditProcessedDays%20)==0){UpdateDashboard();ChartRedraw(0);}
      if(daySt.day_of_week==0||daySt.day_of_week==6)continue;

      double hi,lo,avgV;datetime os,oe,te;int used;
      checked++;
      if(!BuildOrbForNyDate(daySt.year,daySt.mon,daySt.day,hi,lo,os,oe,te,used,avgV))
      {
         Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," ORB_FAIL no_data");
         continue;
      }

      // Day filter
      string fr="";
      if(!HistCheckDay(daySt.day_of_week,fr)){filtered++;Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr);continue;}
      // ATR filter
      if(!HistCheckAtr(hi-lo,os,fr)){filtered++;Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr," orbRange=",DoubleToString(hi-lo,_Digits));continue;}

      // Find breakout (uses g_rtSignalTf + delay)
      string dir;datetime sigT;double sigC,sigH,sigL,sigVol,preAvgVol;
      if(!FindHistBreakout(oe,te,hi,lo,dir,sigT,sigC,sigH,sigL,sigVol,preAvgVol))
      {
         Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," NO_BREAKOUT orbH=",DoubleToString(hi,_Digits)," orbL=",DoubleToString(lo,_Digits));
         continue;
      }

      // Volume filter: compare breakout bar to pre-breakout local average
      if(!HistCheckVol(sigVol,preAvgVol,fr)){filtered++;Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr," sigVol=",DoubleToString(sigVol,0)," preAvg=",DoubleToString(preAvgVol,0));continue;}
      string modernDetail="";
      if(!ModernFilterAllows(oe,te,g_rtSignalTf,sigT,dir,g_rtDisplacement,g_rtFvgMode,fr,modernDetail))
      {
         filtered++;
         Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr," ",modernDetail);
         continue;
      }

      datetime entryT=sigT;
      double entryPrice=sigC;
      string entryDetail="";
      if(!ResolveHistoricalEntry(g_rtEntryMode,dir,sigT,sigC,hi,lo,te,entryT,entryPrice,entryDetail))
      {
         filtered++;
         Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",entryDetail);
         continue;
      }

      RegimeV3Snapshot regimeSnapshot;
      int regimeBucket=OrbRegimeBucketAt(sigT,regimeSnapshot);
      string regimeDetail=OrbRegimeDetail(regimeSnapshot,regimeBucket);

      // Simulate trade
      bool isBuy=(dir=="BUY");
      double buffer=MathMax(0.0,InpSlBufferPoints)*pt;
      double entry=entryPrice;
      double rawSl=isBuy?(lo-buffer):(hi+buffer);
      double sl=ApplyRuntimeSlFromEntry(isBuy,entry,rawSl);
      double risk=MathAbs(entry-sl);if(risk<=pt)continue;
      double r1v=MathMax(0.1,InpTp1R),r2v=MathMax(0.1,InpTp2R),r3v=MathMax(0.1,InpTp3R);
      double tp1=NormalizePrice(isBuy?entry+risk*r1v:entry-risk*r1v);
      double tp2=NormalizePrice(isBuy?entry+risk*r2v:entry-risk*r2v);
      double tp3=NormalizePrice(isBuy?entry+risk*r3v:entry-risk*r3v);
      double tp4=NormalizePrice(isBuy?entry+risk*LegR(4):entry-risk*LegR(4));
      double tp5=NormalizePrice(isBuy?entry+risk*LegR(5):entry-risk*LegR(5));
      double tp6=NormalizePrice(isBuy?entry+risk*LegR(6):entry-risk*LegR(6));

      datetime simEnd=te;
      if(simEnd<=0||simEnd>now)simEnd=now;
      datetime nextSig=0;
      if(FindNextHistoricalSignalAfter(sigT,simEnd,nextSig))
         simEnd=nextSig;
      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_orbHigh=hi;g_orbLow=lo;g_orbStartServer=os;g_orbEndServer=oe;g_tradeEndServer=te;
      HistResult sim=SimulateTrade(entryT,simEnd,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,RuntimeHalfBeLeg());
      g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
      WriteInternalSimAudit("dashboard_hist",entryT,simEnd,dir,entry,NormalizePrice(sl),sim,modernDetail+" "+entryDetail+" "+regimeDetail+" regime_allowed="+(OrbRegimeAllowed(regimeBucket)?"1":"0"));
      bool finalOutcome=(sim.outcome!="open");
      if(finalOutcome&&regimeBucket>=0&&regimeBucket<ORB_REGIME_COUNT)
      {
         if(sim.netR>0)g_regimeWins[regimeBucket]++;
         else if(sim.netR<0)g_regimeLosses[regimeBucket]++;
      }
      if(!OrbRegimeAllowed(regimeBucket))
      {
         filtered++;
         Print("ORB15v3 HIST regime blocked ",regimeDetail," signal=",FmtTime(sigT));
         continue;
      }
      g_histTotal++;
      double statR=finalOutcome?sim.netR:0.0;
      if(finalOutcome&&sim.netR>0)g_histWins++;
      else if(finalOutcome&&sim.netR<0)g_histLosses++;
      g_histNetR+=statR;
      g_histNetMoney+=SimMoneyPnl(statR);

      // Debug audit
      Print("ORB15v3 HIST #",g_histTotal," ",dir,
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
            " nextSig=",FmtTime(nextSig),
            " maxTp=",sim.maxTp,
            " modern=",modernDetail,
            " entryMode=",entryDetail,
            " targetLeg=",sim.targetLeg,
            " exitMode=",sim.exitMode,
            " exitPrice=",DoubleToString(sim.exitPrice,_Digits),
            " fill=",DoubleToString(sim.simEntry,_Digits),
            " simSl=",DoubleToString(sim.simSl,_Digits),
            " simTarget=",DoubleToString(sim.simTarget,_Digits),
            " costR=",DoubleToString(sim.costR,2),
            " netR=",DoubleToString(sim.netR,2),
            " statR=",DoubleToString(statR,2));

      // Draw arrow with outcome
      double pad=MathMax((hi-lo)*0.12,pt*40.0);
      double arwP=isBuy?(entry-pad):(entry+pad);
      string dateKey=IntegerToString(daySt.year)+StringFormat("%02d%02d",daySt.mon,daySt.day);
      string base=PREFIX+"HIST_"+dateKey+"_"+dir+"_";
      double simRisk=MathAbs(sim.simEntry-sim.simSl);
      datetime levelEnd=entryT+MathMax(60,PeriodSeconds(RuntimeEntryTf()))*20;
      if(nextSig>entryT&&nextSig<levelEnd)levelEnd=nextSig;
      datetime liveCut=NextOrbOpenOwnPositionTimeAfter(entryT,levelEnd);
      if(liveCut>entryT&&liveCut<levelEnd)levelEnd=liveCut;
      string levelId=dateKey+"_"+dir;
      DrawOrbHistoricalSegment(levelId+"_ENTRY",entryT,levelEnd,sim.simEntry,C'230,230,230',STYLE_SOLID);
      DrawOrbHistoricalSegment(levelId+"_SL",entryT,levelEnd,sim.simSl,C'255,80,110',STYLE_SOLID);
      if(sim.simTarget>0.0)
         DrawOrbHistoricalSegment(levelId+"_TP",entryT,levelEnd,sim.simTarget,C'80,255,180',STYLE_SOLID);
      if(sim.hcLeg>0&&simRisk>0.0)
         DrawOrbHistoricalSegment(levelId+"_HC",entryT,levelEnd,PriceAtLeg(isBuy,sim.simEntry,simRisk,sim.hcLeg),C'255,204,82',STYLE_DOT);

      color arwClr=sim.isWin?clrLime:(sim.outcome=="SL"?clrTomato:clrGold);
      int arwCode=isBuy?233:234;
      if(ObjectFind(0,base+"ARW")<0)ObjectCreate(0,base+"ARW",OBJ_ARROW,0,entryT,arwP);
      else ObjectMove(0,base+"ARW",0,entryT,arwP);
      ObjectSetInteger(0,base+"ARW",OBJPROP_ARROWCODE,arwCode);
      ObjectSetInteger(0,base+"ARW",OBJPROP_COLOR,arwClr);
      ObjectSetInteger(0,base+"ARW",OBJPROP_WIDTH,2);
      ObjectSetInteger(0,base+"ARW",OBJPROP_SELECTABLE,false);ObjectSetInteger(0,base+"ARW",OBJPROP_HIDDEN,false);

      // Result text with detail
      double simPnl=SimMoneyPnl(statR);
      string verdict=!finalOutcome?"OPEN":(sim.netR>0.0?"WIN":(sim.netR<0.0?"LOSS":"FLAT"));
      string txt=verdict+" "+dir+" "+sim.outcome
         +" hitTP"+IntegerToString(sim.maxTp)+"/T"+IntegerToString(sim.targetLeg)
         +" "+DoubleToString(statR,1)+"R "
         +(simPnl>=0?"+":"")+DoubleToString(simPnl,2)+"$"
         +" F="+DoubleToString(sim.simEntry,_Digits)
         +" C="+DoubleToString(sim.costR,1)+"R "
         +sim.exitMode;
      if(modernDetail!="")txt+=" "+modernDetail;
      txt+=" "+EntryModeLabel(g_rtEntryMode);
      color txtClr=!finalOutcome?clrKhaki:(sim.isWin?clrPaleGreen:(sim.outcome=="SL"?clrLightSalmon:clrKhaki));
      double txtP=isBuy?arwP-pad*0.6:arwP+pad*0.6;
      DrawSignalText(base+"TXT",entryT,txtP,txt,txtClr);

      string hcTxt=sim.hcLeg>0?DoubleToString(PriceAtLeg(isBuy,sim.simEntry,simRisk,sim.hcLeg),_Digits):"OFF";
      string lvlTxt="SL="+DoubleToString(sim.simSl,_Digits)
         +" TP="+DoubleToString(sim.simTarget,_Digits)
         +" HC="+hcTxt;
      double lvlP=isBuy?txtP-pad*0.55:txtP+pad*0.55;
      DrawSignalText(base+"LVLTXT",entryT,lvlP,lvlTxt,sim.isWin?clrLightCyan:clrMistyRose);
      drawn++;
   }

   g_histAuditProcessedDays=days;g_histAuditProgressPct=100.0;g_histAuditRunning=false;
   double wr=g_histTotal>0?(double)g_histWins/(double)g_histTotal*100.0:0;
   g_histStatLine=IntegerToString(g_histTotal)+" sig | "+IntegerToString(g_histWins)+"W "+IntegerToString(g_histLosses)+"L | WR "+DoubleToString(wr,1)+"% | Net "+DoubleToString(g_histNetR,1)+"R | $ "+(g_histNetMoney>=0?"+":"")+DoubleToString(g_histNetMoney,2);
   if(filtered>0)g_histStatLine+=" | "+IntegerToString(filtered)+" filt";
   Print("ORB15v3 ======= HIST RESULT: ",g_histStatLine," checked=",checked," drawn=",drawn," =======");
   Audit("hist_redraw","",0,0,0,0,g_histStatLine+" days="+IntegerToString(days));
   UpdateDashboard();ChartRedraw(0);
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
      if(combo.vol && ob.preAvgVol>0 && ob.sigVol<ob.preAvgVol*InpVolumeMultiplier) continue;
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
      // Simulate
      bool isBuy=(ob.dir=="BUY");
      ENUM_TIMEFRAMES saveResolveTf=g_rtSignalTf;ORB_ENTRY_MODE saveResolveEntry=g_rtEntryMode;
      g_rtSignalTf=g_btTFs[combo.tfIdx];g_rtEntryMode=(ORB_ENTRY_MODE)combo.entryMode;
      datetime entryT=ob.sigTime;
      double entry=ob.sigClose;
      string entryDetail="";
      bool entryOk=ResolveHistoricalEntry((ORB_ENTRY_MODE)combo.entryMode,ob.dir,ob.sigTime,ob.sigClose,g_btDays[di].orbHi,g_btDays[di].orbLo,g_btDays[di].tradeEnd,entryT,entry,entryDetail);
      g_rtSignalTf=saveResolveTf;g_rtEntryMode=saveResolveEntry;
      if(!entryOk) continue;
      double buffer=MathMax(0,InpSlBufferPoints)*pt;
      double rawSl=isBuy?(g_btDays[di].orbLo-buffer):(g_btDays[di].orbHi+buffer);
      double sl=ApplyRuntimeSlFromEntry(isBuy,entry,rawSl);
      double risk=MathAbs(entry-sl);if(risk<=pt) continue;
      double r1v=MathMax(0.1,InpTp1R),r2v=MathMax(0.1,InpTp2R),r3v=MathMax(0.1,InpTp3R);
      double tp1=NormalizePrice(isBuy?entry+risk*r1v:entry-risk*r1v);
      double tp2=NormalizePrice(isBuy?entry+risk*r2v:entry-risk*r2v);
      double tp3=NormalizePrice(isBuy?entry+risk*r3v:entry-risk*r3v);
      // Use the correct TF/exit/orb context for simulation.
      ENUM_TIMEFRAMES saveTf=g_rtSignalTf;ORB_EXIT_ENGINE_MODE saveExit=g_rtExitMode;ORB_TARGET_MODE saveTarget=g_rtTargetMode;ORB_ENTRY_MODE saveEntry=g_rtEntryMode;
      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_rtSignalTf=g_btTFs[combo.tfIdx];g_rtExitMode=(ORB_EXIT_ENGINE_MODE)combo.exitMode;
      g_rtTargetMode=(ORB_TARGET_MODE)combo.targetMode;
      g_rtEntryMode=(ORB_ENTRY_MODE)combo.entryMode;
      g_orbHigh=g_btDays[di].orbHi;g_orbLow=g_btDays[di].orbLo;g_orbStartServer=g_btDays[di].orbStart;g_orbEndServer=g_btDays[di].orbEnd;g_tradeEndServer=g_btDays[di].tradeEnd;
      HistResult sim=SimulateTrade(entryT,g_btDays[di].tradeEnd,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,combo.be?1:0);
      g_rtSignalTf=saveTf;g_rtExitMode=saveExit;g_rtTargetMode=saveTarget;g_rtEntryMode=saveEntry;g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
      WriteInternalSimAudit("brute_combo",entryT,g_btDays[di].tradeEnd,ob.dir,entry,NormalizePrice(sl),sim,
         "combo_tf="+TfLabel(g_btTFs[combo.tfIdx])+" delay="+IntegerToString(g_btDelays[combo.delayIdx])+" exit="+ExitModeLabel((ORB_EXIT_ENGINE_MODE)combo.exitMode)+" target="+TargetModeLabel((ORB_TARGET_MODE)combo.targetMode)+" "+entryDetail);
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
void DrawDashboard()
{
   if(!InpShowDashboard){DeleteDash();return;}
   int x=InpDashboardX,y=InpDashboardY;
   int W=620,H=592;

   // Shell
   CreateRect("DASH_BG",x,y,W,H,C'24,30,42',C'90,178,255');
   CreateRect("DASH_TOP",x,y,W,28,C'18,24,36',C'90,178,255');
   CreateRect("DASH_STRIPE",x+6,y+6,W-12,3,C'90,178,255',C'90,178,255');

   // Title
   CreateLabel("DASH_TITLE",x+12,y+10,"ORB15 COCKPIT // "+ORB15_BUILD,C'216,222,230',9);

   UpdateDashboard();
}

void UpdateDashboard()
{
   if(!InpShowDashboard)return;
   int x=InpDashboardX,y=InpDashboardY;
   int W=620;
   color acB=C'90,178,255';color muted=C'184,196,210';color steel=C'216,222,230';

   int rootY=y;
   RegimeV3Update(false);
   int currentRegime=OrbRegimeBucket(g_regimeV3);
   string regimeNow=currentRegime>=0?OrbRegimeName(currentRegime):"WAITING DATA";
   CreateLabel("DASH_REG_TITLE",x+12,rootY+34,"JP225 REGIME // NOW: "+regimeNow,
      currentRegime>=0?RegimeV3CoreColor():C'145,160,180',8);
   int regW=194,regH=18,regGap=5;
   for(int ri=0;ri<ORB_REGIME_COUNT;ri++)
   {
      int col=ri%3,row=ri/3;
      string txt=(ri==currentRegime?"> ":"")+OrbRegimeStatsText(ri)+(g_regimeAllowed[ri]?"":" BLOCK");
      color bg=g_regimeAllowed[ri]?C'58,126,178':C'42,47,57';
      CreateButton("BTN_REG_"+IntegerToString(ri),x+12+col*(regW+regGap),rootY+48+row*22,regW,regH,txt,bg);
   }
   y=rootY+92;

   // Status line
   string state=g_rtEaEnabled?"EA ON":"EA OFF";
   string orb=g_orbReady?"READY":"WAIT";
   string exec=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG?"3-LEG":"SINGLE "+TargetLabel()+" "+HalfBeLabel();
   CreateLabel("DASH_L1",x+12,y+34,state+" | ORB "+orb+" | "+exec+" | "+RuntimeEntryLabel()+" | Signal: "+TfLabel(g_rtSignalTf),
      g_rtEaEnabled?C'80,255,180':C'221,55,78',8);

   // ORB info
   string delayTxt=g_rtUseDelay?IntegerToString(g_rtDelayMin)+"m delay":"no delay";
   CreateLabel("DASH_L2",x+12,y+50,
      SessionClockLabel()+" | GMT+"+DoubleToString(InpBrokerGmtOffsetHours,1)
      +" | "+delayTxt+" | Spread "+IntegerToString(CurrentSpreadPoints())+"pt",
      muted,8);
   CreateLabel("DASH_L3",x+12,y+66,
      "ORB H "+DoubleToString(g_orbHigh,_Digits)+" L "+DoubleToString(g_orbLow,_Digits)
      +" | Risk "+DoubleToString(EffRiskPerTradePct(),1)+"% | Mode "+RuntimeRiskModeLabel()+" | "+(g_rtDisplacement?"DISP ON":"DISP OFF")+" | "+FvgModeLabel(),
      clrWhite,8);

   // Separator
   CreateRect("DASH_SEP1",x+8,y+82,W-16,1,C'65,116,172',C'65,116,172');

   // Row 1: Filter toggle buttons
   CreateLabel("DASH_FLBL",x+12,y+88,"FILTERS:",acB,8);
   int bx=x+80,by=y+86,bw=58,bh=18,gap=3;
   CreateButton("BTN_ATR",bx,by,bw,bh,g_rtFilterAtr?"ATR:ON":"ATR:OFF",g_rtFilterAtr?C'30,120,70':C'80,80,80');
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
   CreateButton("BTN_DELAY",x+144,r2y,80,18,g_rtUseDelay?"DLY:"+IntegerToString(g_rtDelayMin)+"m":"DLY:OFF",g_rtUseDelay?C'30,120,70':C'80,80,80');
   CreateButton("BTN_HC",x+228,r2y,70,18,HalfBeLabel(),RuntimeHalfBeLeg()>0?C'30,120,70':C'80,80,80');
   CreateButton("BTN_TP",x+302,r2y,82,18,"FIX "+TargetLabel(),C'38,101,176');
   CreateButton("BTN_TMODE",x+388,r2y,76,18,RuntimeTargetModeLabel(),g_rtTargetMode==ORB_TARGET_R_LEG?C'80,80,80':C'38,101,176');

   CreateButton("BTN_EA",x+468,r2y,54,18,g_rtEaEnabled?"EA ON":"EA OFF",g_rtEaEnabled?C'30,150,95':C'178,37,57');
   CreateButton("BTN_FTMO",x+526,r2y,46,18,g_ftmoMode?"FTMO":"FTMO",g_ftmoMode?C'30,150,95':C'80,80,80');
   CreateButton("BTN_RISKLOT",x+576,r2y,42,18,g_riskLotOnlyMode?"RISK":"RISK",g_riskLotOnlyMode?C'30,150,95':C'80,80,80');
   CreateButton("BTN_EXIT",x+326,y+452,94,18,RuntimeExitLabel(),g_rtExitMode==ORB_EXIT_FIXED_TARGET?C'80,80,80':C'38,101,176');
   CreateButton("BTN_CLOSEALL",x+326,y+475,86,18,"CLOSE ALL",C'178,37,57');
   CreateButton("BTN_BRIDGE_PUB",x+424,y+452,82,18,g_orbBridgeEnabled?"PUB ON":"PUB OFF",g_orbBridgeEnabled?C'30,150,95':C'80,80,80');
   CreateButton("BTN_BRIDGE_ONLY",x+512,y+452,92,18,g_orbBridgeOnly?"ONLY ON":"ONLY OFF",g_orbBridgeOnly?C'120,88,25':C'80,80,80');
   CreateLabel("DASH_BRIDGE",x+424,y+478,"CT "+g_orbBridgeStatus,C'134,158,182',7);

   // Separator
   CreateRect("DASH_SEP2",x+8,y+132,W-16,1,C'65,116,172',C'65,116,172');

   // Stats section
   double wr=g_histTotal>0?(double)g_histWins/(double)g_histTotal*100.0:0;
   color wrClr=wr>=50?C'80,255,180':C'255,95,140';

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
   CreateLabel("DASH_STAT1",x+12,y+156,
      IntegerToString(g_histTotal)+" signals | "+IntegerToString(g_histWins)+" W  "+IntegerToString(g_histLosses)+" L | WR "+DoubleToString(wr,1)+"%",
      wrClr,9);
   CreateLabel("DASH_STAT2",x+12,y+174,
      "Net R: "+DoubleToString(g_histNetR,1)+"R"
      +" | Net $: "+(g_histNetMoney>=0?"+":"")+DoubleToString(g_histNetMoney,2)
      +" | Avg W: "+DoubleToString(g_histWins>0?g_histNetR/(double)g_histWins:0,1)+"R"
      +" | "+IntegerToString(g_histTotal-g_histWins-g_histLosses)+" open/timeout",
      muted,8);

   // TP config line
   string tpInfo=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG
      ?"TP1="+DoubleToString(InpTp1R,1)+"R TP2="+DoubleToString(InpTp2R,1)+"R TP3="+DoubleToString(InpTp3R,1)+"R"
      :TargetLabel()+" "+HalfBeLabel();
   CreateLabel("DASH_STAT3",x+12,y+190,tpInfo+" | "+RuntimeTargetModeLabel()+" | "+ExitDebugConfig()+" | "+RuntimeSlModeLabel()+" | AutoLot "+BoolText(InpUseAutoRiskLot),C'134,158,182',7);
   CreateButton("BTN_SL_MODE",x+330,y+188,66,18,g_rtPipSlMode?"PIP ON":"SL% MODE",g_rtPipSlMode?C'30,120,70':C'80,80,80');
   CreateEdit("EDIT_SL_VALUE",x+402,y+188,72,18,g_rtPipSlMode?DoubleToString(g_rtPipSlPips,1):DoubleToString(g_rtSlDistancePct,0));
   CreateButton("BTN_SL_APPLY",x+480,y+188,58,18,"APPLY",C'38,101,176');

   // Win-rate bar doubles as an audit progress bar while a long rebuild is running.
   int barW=496,barH=14;
   double barPct=g_histAuditRunning?g_histAuditProgressPct:wr;
   color barClr=g_histAuditRunning?C'38,140,220':wrClr;
   CreateRect("DASH_WRBAR_BG",x+12,y+206,barW,barH,C'42,51,68',C'134,158,182');
   int fillW=(int)MathRound((double)barW*MathMax(0,MathMin(100,barPct))/100.0);
   if(fillW>2)CreateRect("DASH_WRBAR_FILL",x+13,y+207,fillW-2,barH-2,barClr,barClr);
   else ObjectDelete(0,PREFIX+"DASH_WRBAR_FILL");
   CreateLabel("DASH_AUD_PROGRESS",x+514,y+206,g_histAuditRunning?("AUD "+DoubleToString(g_histAuditProgressPct,1)+"%"):
      "",C'90,178,255',7);

   // Separator
   CreateRect("DASH_SEP3",x+8,y+226,W-16,1,C'65,116,172',C'65,116,172');

   // Status line
   string sigTime=g_lastSignalBarTime>0?FmtTime(g_lastSignalBarTime):"-";
   CreateLabel("DASH_L4",x+12,y+232,
      "Signal "+sigTime+" | Taken "+BoolText(g_tradeTaken)+" | "+g_lastExecStatus,
      (g_lastExecStatus=="OPENED"||g_lastExecStatus=="READY")?C'80,255,180':C'255,204,82',8);
   if(g_lastFilterReason!="")
      CreateLabel("DASH_L5",x+12,y+248,"Filter: "+g_lastFilterReason,C'255,204,82',7);
   else
      CreateLabel("DASH_L5",x+12,y+248,"Chart TF can be any; EA reads "+TfLabel(g_rtSignalTf)+" data.",C'134,158,182',7);

   // Execution info
   CreateLabel("DASH_L6",x+12,y+264,tpInfo+" | Magic "+IntegerToString(RuntimeMagic()),C'134,158,182',7);

   // ORB range vs ATR context
   double atr=HistDailyAtr(TimeCurrent(),InpAtrPeriod);
   string atrCtx=atr>0?"ORB/ATR "+DoubleToString(g_orbReady?((g_orbHigh-g_orbLow)/atr)*100.0:0,1)+"%":"ATR --";
   CreateLabel("DASH_L7",x+12,y+280,atrCtx+" | Range "+DoubleToString(g_orbReady?g_orbHigh-g_orbLow:0,_Digits)+" | "+ExitDebugConfig(),C'134,158,182',7);

   // ─── SECTION: BACKTEST ENGINE ───
   CreateRect("DASH_SEP4",x+8,y+296,W-16,1,C'65,116,172',C'65,116,172');
   CreateLabel("DASH_BTITLE",x+12,y+302,"BACKTEST ENGINE",acB,9);

   int btY=y+318;
   CreateLabel("DASH_BTWLBL",x+12,btY+2,"Weeks:",C'134,158,182',7);
   string editName=PREFIX+"EDIT_BT_WEEKS";
   if(ObjectFind(0,editName)<0)
   {
      ObjectCreate(0,editName,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,editName,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetString(0,editName,OBJPROP_TEXT,IntegerToString(g_btWeeks));
      ObjectSetInteger(0,editName,OBJPROP_BGCOLOR,C'38,46,60');
      ObjectSetInteger(0,editName,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,editName,OBJPROP_BORDER_COLOR,C'80,100,130');
      ObjectSetInteger(0,editName,OBJPROP_FONTSIZE,9);
      ObjectSetString(0,editName,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,editName,OBJPROP_ALIGN,ALIGN_CENTER);
      ObjectSetInteger(0,editName,OBJPROP_READONLY,false);
      ObjectSetInteger(0,editName,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,editName,OBJPROP_BACK,false);
      ObjectSetInteger(0,editName,OBJPROP_ZORDER,DASH_Z+3);
   }
   ObjectSetInteger(0,editName,OBJPROP_XDISTANCE,x+52);
   ObjectSetInteger(0,editName,OBJPROP_YDISTANCE,btY);
   ObjectSetInteger(0,editName,OBJPROP_XSIZE,38);
   ObjectSetInteger(0,editName,OBJPROP_YSIZE,18);
   ObjectSetInteger(0,editName,OBJPROP_ZORDER,DASH_Z+3);

   color runBg=g_btRunning?C'80,80,80':C'30,120,70';
   CreateButton("BTN_BT_RUN",x+96,btY,120,18,g_btRunning?"RUNNING...":"RUN BACKTEST",runBg);
   CreateButton("BTN_BT_STOP",x+220,btY,60,18,"STOP",g_btRunning?C'178,37,57':C'60,60,68');
   CreateLabel("DASH_BTCNT",x+286,btY+2,IntegerToString(g_btRunning?g_btTotal:21504)+" combos",C'134,158,182',7);

   int optY=btY+22;
   CreateLabel("DASH_BTFILL_L",x+12,optY+2,"Fill:",C'134,158,182',7);
   CreateButton("BTN_BTF_SIGNAL",x+50,optY,58,18,"SIGNAL",g_btFillMode==BT_FILL_SIGNAL_CLOSE?C'38,101,176':C'80,80,80');
   CreateButton("BTN_BTF_NEXT",x+112,optY,50,18,"NEXT",g_btFillMode==BT_FILL_NEXT_BAR_OPEN?C'38,101,176':C'80,80,80');
   CreateButton("BTN_BTF_CONS",x+166,optY,50,18,"CONS",g_btFillMode==BT_FILL_CONSERVATIVE?C'38,101,176':C'80,80,80');
   CreateLabel("DASH_BTSAME_L",x+224,optY+2,"Same:",C'134,158,182',7);
   CreateButton("BTN_BTSB_CONS",x+264,optY,50,18,"CONS",g_btSameBarPolicy==BT_SAMEBAR_CONSERVATIVE?C'38,101,176':C'80,80,80');
   CreateButton("BTN_BTSB_NEAR",x+318,optY,50,18,"NEAR",g_btSameBarPolicy==BT_SAMEBAR_NEAREST_OPEN?C'38,101,176':C'80,80,80');
   CreateButton("BTN_BTSB_TP",x+372,optY,52,18,"TP1ST",g_btSameBarPolicy==BT_SAMEBAR_TP_FIRST?C'38,101,176':C'80,80,80');
   CreateButton("BTN_BTSB_SL",x+428,optY,52,18,"SL1ST",g_btSameBarPolicy==BT_SAMEBAR_SL_FIRST?C'38,101,176':C'80,80,80');
   CreateButton("BTN_BTPARITY",x+486,optY,78,18,g_btNativeParity?"PARITY ON":"PARITY",g_btNativeParity?C'30,120,70':C'80,80,80');

   int costY=optY+22;
   CreateLabel("DASH_BTSP_L",x+12,costY+2,"Spr:",C'134,158,182',7);
   CreateEdit("EDIT_BT_SPREAD",x+42,costY,45,18,DoubleToString(g_btSpreadPts,1));
   CreateLabel("DASH_BTSL_L",x+94,costY+2,"Slip:",C'134,158,182',7);
   CreateEdit("EDIT_BT_SLIP",x+130,costY,45,18,DoubleToString(g_btSlippagePts,1));
   CreateLabel("DASH_BTCM_L",x+184,costY+2,"Comm/Lot:",C'134,158,182',7);
   CreateEdit("EDIT_BT_COMM",x+252,costY,58,18,DoubleToString(g_btCommissionPerLot,2));
   CreateLabel("DASH_BTDEF",x+320,costY+2,g_btNativeParity?"tick replay: bid/ask costs embedded":"0 spread = live spread",C'100,112,130',7);

   // Progress bar
   int pbY=costY+22;
   int pbW=W-24,pbH=14;
   CreateRect("DASH_BTPB_BG",x+12,pbY,pbW,pbH,C'38,46,60',C'60,80,110');
   if(g_btRunning||g_btStep>0)
   {
      double pct=g_btTotal>0?(double)g_btStep/(double)g_btTotal:0;
      int fw=(int)MathRound(pbW*MathMax(0,MathMin(1,pct)));
      if(fw>2) CreateRect("DASH_BTPB_FG",x+13,pbY+1,fw-2,pbH-2,C'60,200,120',C'60,200,120');
      else CreateRect("DASH_BTPB_FG",x+13,pbY+1,1,pbH-2,C'38,46,60',C'38,46,60');
      uint elapsed=g_btRunning?(GetTickCount()-g_btStartMs):g_btElapsedMs;
      string pTxt=IntegerToString(g_btStep)+"/"+IntegerToString(g_btTotal)
         +" ("+IntegerToString((int)(pct*100))+"%) "
         +DoubleToString(elapsed/1000.0,1)+"s";
      CreateLabel("DASH_BTPROG",x+16,pbY+1,pTxt,clrWhite,8);
   }
   else
   {
      CreateRect("DASH_BTPB_FG",x+13,pbY+1,1,pbH-2,C'38,46,60',C'38,46,60');
      CreateLabel("DASH_BTPROG",x+16,pbY+1,g_btLastResult!=""?g_btLastResult:"Ready",C'134,158,182',8);
   }
   // Last result
   int lrY=pbY+18;
   if(g_btLastResult!="")
      CreateLabel("DASH_BTLAST",x+12,lrY,g_btLastResult,g_btRunning?C'150,200,170':C'134,158,182',7);
   else
      CreateLabel("DASH_BTLAST",x+12,lrY,"",C'134,158,182',7);
}

//=========================================================================
//  DAY RESET
//=========================================================================
bool ResetForNewNyDay()
{
   int y,m,d;int key=CurrentSessionDayKey(y,m,d);if(key==g_nyDayKey)return false;
   g_nyDayKey=key;g_orbReady=false;g_tradeTaken=false;g_orbHigh=0;g_orbLow=0;g_orbAvgVolume=0;
   g_lastSignalBarTime=0;g_lastCheckedSignalBarTime=0;g_tradeDir=0;g_tradeEntry=0;g_tradeSl=0;g_tradeOpenTime=0;g_beMoved=false;
   g_tradeRisk=0;g_lastFilterReason="";g_lastExecStatus="READY";
   g_tradeBestHigh=0;g_tradeBestLow=0;g_tradeLastDynamicExitBar=0;
   ClearRetestState("new_day");
   ClearImbalanceState("new_day");
   int sm,em,tem;SessionClockMinutes(sm,em,tem);
   g_orbStartServer=SessionLocalToServer(y,m,d,sm);g_orbEndServer=SessionLocalToServer(y,m,d,em);g_tradeEndServer=SessionLocalToServer(y,m,d,tem);
   DeleteLevels();g_histNeedsRedraw=true;
   Audit("new_day","",0,0,0,0,"key="+IntegerToString(key)+" session="+SessionClockLabel());return true;
}

//=========================================================================
//  LIVE FILTERS — use g_rtSignalTf for all timeframe operations
//=========================================================================
bool CheckAtrFilter(string &r)
{
   if(!g_rtFilterAtr)return true;
   int h=iATR(_Symbol,PERIOD_D1,InpAtrPeriod);if(h==INVALID_HANDLE)return true;
   double v[];ArraySetAsSeries(v,true);int c=CopyBuffer(h,0,1,1,v);IndicatorRelease(h);
   if(c!=1||v[0]<=0)return true;
   double pct=((g_orbHigh-g_orbLow)/v[0])*100;
   if(pct<InpMinRangeAtrPct){r="ATR_NARROW "+DoubleToString(pct,1)+"%";return false;}
   if(pct>InpMaxRangeAtrPct){r="ATR_WIDE "+DoubleToString(pct,1)+"%";return false;}
   return true;
}
bool CheckVolFilter(string &r)
{
   if(!g_rtFilterVol)return true;
   int sh=InpUseClosedBarBreakout?1:0;
   long bv=iVolume(_Symbol,g_rtSignalTf,sh);
   // Rolling average of 20 bars before signal bar (fair baseline)
   double avgVol=0;int lookback=20;double vs=0;
   for(int i=sh+1;i<=sh+lookback;i++){long v=iVolume(_Symbol,g_rtSignalTf,i);if(v>0)vs+=(double)v;}
   avgVol=vs/(double)lookback;
   if(avgVol<=0)return true;
   double threshold=avgVol*InpVolumeMultiplier;
   if((double)bv<threshold){r="VOL_LOW "+IntegerToString(bv)+"<"+DoubleToString(threshold,0);return false;}
   return true;
}
bool CheckDayFilter(string &r){if(!g_rtFilterDay)return true;int y,m,d;CurrentSessionDayKey(y,m,d);int dow=DayOfWeekForDate(y,m,d);bool ok=false;if(dow==1&&InpTradeMonday)ok=true;if(dow==2&&InpTradeTuesday)ok=true;if(dow==3&&InpTradeWednesday)ok=true;if(dow==4&&InpTradeThursday)ok=true;if(dow==5&&InpTradeFriday)ok=true;if(!ok){r="DAY_BLOCKED";return false;}return true;}

//=========================================================================
//  SIGNAL COMPUTE — uses g_rtSignalTf + confirmation delay
//=========================================================================
bool ComputeSignal(string &dir,datetime &bt,double &sc)
{
   dir="";bt=0;sc=0;if(!g_orbReady)return false;
   // Apply confirmation delay: don't accept signals until delay after ORB end
   datetime effectiveStart = g_orbEndServer;
   if(g_rtUseDelay && g_rtDelayMin > 0)
      effectiveStart = g_orbEndServer + g_rtDelayMin * 60;
   if(TimeCurrent()<effectiveStart||TimeCurrent()>g_tradeEndServer)return false;
   int sh=InpUseClosedBarBreakout?1:0;
   bt=iTime(_Symbol,g_rtSignalTf,sh);
   if(bt<=0||bt==g_lastSignalBarTime)return false;
   if(InpUseClosedBarBreakout&&bt==g_lastCheckedSignalBarTime)return false;
   if(BarCloseTime(g_rtSignalTf, bt)<effectiveStart)return false; // signal is only known after bar close
   sc=iClose(_Symbol,g_rtSignalTf,sh);if(sc<=0)return false;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double mb=MathMax(0.0,InpMinBreakoutPoints)*pt;
   if(sc>g_orbHigh+mb)dir="BUY";else if(sc<g_orbLow-mb)dir="SELL";
   if(dir=="")
   {
      if(InpUseClosedBarBreakout)g_lastCheckedSignalBarTime=bt;
      return false;
   }

   // Match historical confirmation semantics: the current closed bar is the confirm bar,
   // and the previous N-1 closed bars must already be beyond the same ORB side.
   int confirms=MathMax(1,InpConfirmBars);
   for(int k=sh;k<sh+confirms;k++)
   {
      double cc=iClose(_Symbol,g_rtSignalTf,k);
      datetime kt=iTime(_Symbol,g_rtSignalTf,k);
      if(cc<=0||kt<=0||BarCloseTime(g_rtSignalTf,kt)<effectiveStart)
      {
         if(InpUseClosedBarBreakout)g_lastCheckedSignalBarTime=bt;
         return false;
      }
      if(dir=="BUY" && cc<=g_orbHigh+mb)
      {
         if(InpUseClosedBarBreakout)g_lastCheckedSignalBarTime=bt;
         return false;
      }
      if(dir=="SELL" && cc>=g_orbLow-mb)
      {
         if(InpUseClosedBarBreakout)g_lastCheckedSignalBarTime=bt;
         return false;
      }
   }
   if(InpUseClosedBarBreakout)g_lastCheckedSignalBarTime=bt;
   return true;
}

//=========================================================================
//  TRADE EXECUTION
//=========================================================================
bool ExecSingle(string dir,double &entry,double &sl,double &tp,double lot)
{
   entry=NormalizeTradePrice(entry);sl=NormalizeTradePrice(sl);tp=NormalizeTradePrice(tp);
   string adj="";AdjustOpenStops(dir,entry,sl,tp,adj);
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
void SetRetestPending(string dir,datetime bt,double breakoutClose,string context)
{
   ClearImbalanceState("retest_selected");
   g_retestPending=true;
   g_retestTouched=false;
   g_retestDir=dir;
   g_retestSignalBar=bt;
   g_retestBreakoutClose=breakoutClose;
   g_retestLevel=(dir=="BUY")?g_orbHigh:g_orbLow;
   datetime start=BarCloseTime(g_rtSignalTf,bt);
   g_retestExpire=g_tradeEndServer;
   if(InpRetestMaxWaitMinutes>0)g_retestExpire=MathMin(g_retestExpire,start+InpRetestMaxWaitMinutes*60);
   g_retestContext=context;
   g_lastExecStatus="RETEST_WAIT";
   Audit("retest_pending",dir,0,breakoutClose,g_retestLevel,0,
      "signal="+FmtTime(bt)+" expire="+FmtTime(g_retestExpire)+" level="+DoubleToString(g_retestLevel,_Digits)+" "+context);
}

void SetImbalancePending(string dir,datetime bt,double breakoutClose,string context)
{
   ClearRetestState("imbalance_selected");
   g_imbPending=true;
   g_imbDir=dir;
   g_imbSignalBar=bt;
   g_imbBreakoutClose=breakoutClose;
   g_imbStart=BarCloseTime(g_rtSignalTf,bt);
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
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return false;
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

bool ExecuteOrbEntry(string dir,datetime signalBar,double signalClose,string entryDetail)
{
   if(!SpreadAllowed()){g_lastFilterReason="SPREAD";g_lastExecStatus="FILTERED";Audit("spread_block",dir,0,signalClose,0,0,entryDetail);return false;}
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return false;
   bool isBuy=dir=="BUY";
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double buf=MathMax(0,InpSlBufferPoints)*pt;
   double entry=NormalizeTradePrice(isBuy?tick.ask:tick.bid);
   double rawSl=NormalizeTradePrice(isBuy?(g_orbLow-buf):(g_orbHigh+buf));
   double sl=ApplyRuntimeSlFromEntry(isBuy,entry,rawSl);
   double risk=MathAbs(entry-sl);if(risk<=pt)return false;
   double tp1=PriceAtLeg(isBuy,entry,risk,1);
   double tp2=PriceAtLeg(isBuy,entry,risk,2);
   double tp3=PriceAtLeg(isBuy,entry,risk,3);
   double tp4=PriceAtLeg(isBuy,entry,risk,4);
   double tp5=PriceAtLeg(isBuy,entry,risk,5);
   double tp6=PriceAtLeg(isBuy,entry,risk,6);
   if(g_orbBridgeOnly&&!ExitModeUsesFixedTp(g_rtExitMode))
   {
      g_lastExecStatus="BRIDGE_ONLY_UNSUPPORTED_EXIT";
      Audit("bridge_only_shape_block",dir,0,entry,sl,0,"bridge-only requires a fixed TP because no native position exists to drive dynamic/time exits "+ExitDebugConfig());
      return false;
   }
   bool opened=false;
   double planTp=0.0,planHalf=0.0;
   string lotDetail="";
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      if(g_rtTargetMode!=ORB_TARGET_R_LEG)
      {
         g_lastExecStatus="FILTERED";
         Audit("target_mode_block",dir,0,entry,sl,0,"partial_3leg_requires_rleg "+RuntimeTargetModeLabel()+" "+entryDetail);
         return false;
      }
      if(!ExitModeUsesFixedTp(g_rtExitMode))
      {
         g_lastExecStatus="FILTERED";
         Audit("exit_mode_block",dir,0,entry,sl,0,"partial_3leg_incompatible "+ExitDebugConfig()+" "+entryDetail);
         return false;
      }
      planTp=tp3;
      planHalf=g_rtBEOnTp1?tp1:0.0;
      bool bridgeAccepted=!g_orbBridgeEnabled||OrbProPublishSignal(dir,signalBar,entry,sl,planTp,planHalf,planHalf>0?"TP1":"OFF",entryDetail+" bridge_mode=3leg_collapsed");
      if(g_orbBridgeOnly)
      {
         if(!bridgeAccepted){g_lastExecStatus="BRIDGE_ONLY_FAIL";return false;}
         g_tradeTaken=true;g_lastExecStatus="BRIDGE_ONLY";ClearRetestState("");ClearImbalanceState("");return true;
      }
      double lot=ResolveLot(dir,entry,sl,lotDetail);
      if(lot<=0){g_lastExecStatus="FILTERED";Audit("risk_block",dir,0,entry,sl,tp3,lotDetail+" "+entryDetail);return false;}
      opened=ExecThreeLegs(dir,entry,sl,tp1,tp2,tp3,lot);
      if(opened){g_tradeTp1=tp1;g_tradeTp2=tp2;g_tradeTp3=tp3;Audit("opened_3leg",dir,lot,entry,sl,tp3,lotDetail+" "+entryDetail);}
   }
   else
   {
      double targetPrice=0.0,targetR=0.0;string targetDetail="";
      if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail)){g_lastExecStatus="FILTERED";Audit("target_resolve_fail",dir,0,entry,sl,0,entryDetail);return false;}
      double tp=ExitModeUsesFixedTp(g_rtExitMode)?targetPrice:0.0;
      planTp=tp;
      int bridgeHcLeg=RuntimeHalfBeLeg();
      if(bridgeHcLeg>0)planHalf=PriceAtLeg(isBuy,entry,risk,bridgeHcLeg);
      bool bridgeAccepted=!g_orbBridgeEnabled||OrbProPublishSignal(dir,signalBar,entry,sl,tp,planHalf,bridgeHcLeg>0?("TP"+IntegerToString(bridgeHcLeg)):"OFF",entryDetail+" "+targetDetail);
      if(g_orbBridgeOnly)
      {
         if(!bridgeAccepted){g_lastExecStatus="BRIDGE_ONLY_FAIL";return false;}
         g_tradeTaken=true;g_lastExecStatus="BRIDGE_ONLY";ClearRetestState("");ClearImbalanceState("");return true;
      }
      double lot=ResolveLot(dir,entry,sl,lotDetail);
      if(lot<=0){g_lastExecStatus="FILTERED";Audit("risk_block",dir,0,entry,sl,tp,lotDetail+" "+entryDetail);return false;}
      opened=ExecSingle(dir,entry,sl,tp,lot);
      if(opened){g_tradeTp1=tp1;g_tradeTp2=tp2;g_tradeTp3=tp3;g_tradeTp4=tp4;g_tradeTp5=tp5;g_tradeTp6=tp6;Audit("opened",dir,lot,entry,sl,tp,lotDetail+" "+targetDetail+" "+HalfBeLabel()+" "+ExitDebugConfig()+" "+entryDetail);}
   }
   if(opened)
   {
      g_tradeTaken=true;g_tradeDir=isBuy?1:-1;g_tradeEntry=entry;g_tradeSl=sl;g_tradeOpenTime=TimeCurrent();g_beMoved=false;g_halfClosed=false;g_tradeRisk=MathAbs(entry-sl);g_tradeBestHigh=entry;g_tradeBestLow=entry;g_tradeLastDynamicExitBar=0;g_lastExecStatus="OPENED";
      OrbProStoreOpenPositions(g_tradeDir,entry,sl,planTp,planHalf,signalBar,g_lastSignalRegime);
      ClearRetestState("");
      ClearImbalanceState("");
      return true;
   }
   g_lastExecStatus="FAIL";Audit("order_fail",dir,0,entry,sl,0,"ret="+IntegerToString((int)trade.ResultRetcode())+" "+entryDetail);
   return false;
}

void TryOpenSignal()
{
   if(!g_rtEaEnabled)return;if(!BuildOrb())return;
   if(InpOneTradePerNyDay&&g_tradeTaken)return;if(OwnPositionExists())return;
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
   g_lastSignalBarTime=bt;
   string fr="";
   if(!CheckDayFilter(fr)||!CheckAtrFilter(fr)||!CheckVolFilter(fr)){g_lastFilterReason=fr;g_lastExecStatus="FILTERED";Audit("filtered",dir,0,sc,0,0,fr);return;}
   string modernDetail="";
   if(!ModernFilterAllows(g_orbEndServer,g_tradeEndServer,g_rtSignalTf,bt,dir,g_rtDisplacement,g_rtFvgMode,fr,modernDetail))
   {
      g_lastFilterReason=fr;g_lastExecStatus="FILTERED";Audit("filtered",dir,0,sc,0,0,fr+" "+modernDetail);return;
   }
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
      return;
   }
   modernDetail+=(modernDetail==""?"":" ")+liveRegimeDetail;
   g_lastFilterReason="";
   // Draw arrows
   int sh=InpUseClosedBarBreakout?1:0;double sH=iHigh(_Symbol,g_rtSignalTf,sh),sL=iLow(_Symbol,g_rtSignalTf,sh);
   double pad=MathMax(MathAbs(g_orbHigh-g_orbLow)*0.12,SymbolInfoDouble(_Symbol,SYMBOL_POINT)*40.0);
   bool isBuy=dir=="BUY";double arwP=isBuy?(sL-pad):(sH+pad);
   DrawSignalArrow(PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+dir+"_ARW",bt,arwP,isBuy,false);
   DrawSignalText(PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+dir+"_TXT",bt,isBuy?arwP-pad*0.6:arwP+pad*0.6,"ORB LIVE "+dir+" "+modernDetail,isBuy?clrLime:clrTomato);
   Audit("signal",dir,0,sc,0,0,"bar="+FmtTime(bt)+" "+RuntimeEntryLabel()+" "+modernDetail);
   if(g_rtEntryMode==ORB_ENTRY_PULLBACK_RETEST)
   {
      SetRetestPending(dir,bt,sc,modernDetail);
      return;
   }
   if(g_rtEntryMode==ORB_ENTRY_IMBALANCE_M1)
   {
      SetImbalancePending(dir,bt,sc,modernDetail);
      return;
   }
   ExecuteOrbEntry(dir,bt,sc,"entry=breakout "+modernDetail);
}

//=========================================================================
//  EVENT HANDLERS
//=========================================================================
int OnInit()
{
   OrbTesterAudit_Init();
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      ENUM_ACCOUNT_MARGIN_MODE mm=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){Print("ORB15v3: 3-leg needs hedging. mode=",EnumToString(mm));return INIT_PARAMETERS_INCORRECT;}
   }
   trade.SetExpertMagicNumber(RuntimeMagic());trade.SetDeviationInPoints(InpDeviationPoints);
   // Initialize runtime toggles from inputs
   g_rtFilterAtr=InpUseAtrRangeFilter;g_rtFilterVol=InpUseVolumeFilter;g_rtFilterDay=InpUseDayFilter;
   g_ftmoMode=InpFtmoModeDefault;g_riskLotOnlyMode=(!g_ftmoMode&&InpRiskLotOnlyModeDefault);g_runtimeMagic=0;
   g_rtTimeExit=InpUseTimeExit;g_rtDisplacement=InpUseDisplacementFilter;g_rtFvgMode=InpFvgMode;g_rtBEOnTp1=InpMoveToBEOnTp1;g_rtEaEnabled=InpEaEnabled;
   g_rtExitMode=InpExitEngineMode;
   g_rtTargetMode=InpTargetMode;
   g_rtEntryMode=InpEntryMode;
   g_rtExitTrailStartLeg=ClampExitTrailStartLeg(InpExitTrailStartLeg);
   g_rtExitEmaPeriod=ClampEmaPeriod(InpExitEmaPeriod);
   g_rtExitAtrMultiplier=MathMax(0.5,MathMin(10.0,InpExitAtrMultiplier));
   g_rtTargetLeg=(int)InpTargetTpLeg;SetTargetLeg(g_rtTargetLeg);
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
   g_rtSignalTf=InpSignalTimeframe;
   g_rtDelayMin=InpBreakoutDelayMinutes;
   g_rtUseDelay=InpBreakoutDelayMinutes>0;
   g_auditRuntime=(InpAuditCsv || InpLogOnInit);
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;g_btNativeParity=InpBacktestNativeParity;
   g_btSpreadPts=InpBacktestSpreadPts>0?InpBacktestSpreadPts:(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   g_lastHistBuild=0;g_histNeedsRedraw=true;
   ResetForNewNyDay();
   RegimeV3Update(true);
   OrbProInit();
   if(!IsTesterMode())EventSetTimer(5);
   if(!IsTesterMode()){DrawDashboard();DrawHistoricalSignals();DrawOrbLiveTradeLevels();}
   if(g_auditRuntime && InpLogOnInit)Print("ORB15v3.1 init ",_Symbol," build=",ORB15_BUILD," tf=",TfLabel(g_rtSignalTf)," exec=",EnumToString(InpExecutionMode)," magic=",RuntimeMagic(),
                         " tp=",DoubleToString(InpTp1R,1),"/",DoubleToString(InpTp2R,1),"/",DoubleToString(InpTp3R,1),"/",DoubleToString(InpTp4R,1),"/",DoubleToString(InpTp5R,1),"/",DoubleToString(InpTp6R,1),
                         " delay=",g_rtDelayMin,"min confirm=",InpConfirmBars,"bars");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(reason==REASON_REMOVE||reason==REASON_PROGRAM){DeleteLevels();DeleteDash();DeleteHist();DeleteLive();}
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   OrbTesterAudit_WriteDeal(trans, request, result);
   OrbProOnTradeTransaction(trans);
}

void OnTimer()
{
   EnforceRiskBreach();
   bool dc=ResetForNewNyDay();BuildOrb();
   RegimeV3Update(false);
   if(dc&&!IsTesterMode())DrawHistoricalSignals();
   TryOpenSignal();ManagePositions();
   if(!IsTesterMode())
   {
      OrbProTimer();
      OrbAudit_HistoryScan();
      OBT_Tick();
      DrawOrbLiveTradeLevels();
      UpdateDashboard();
   }
}

void OnTick()
{
   if(IsTesterMode()&&InpTesterRegimeMatrix)
   {
      OBT_RunRegimeMatrix();
      return;
   }
   EnforceRiskBreach();
   ResetForNewNyDay();TryOpenSignal();ManagePositions();
   if(!IsTesterMode()){OrbProUpdateOpenPositions();DrawOrbLiveTradeLevels();UpdateDashboard();}
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK)return;

   bool needRedraw=false;

   for(int ri=0;ri<ORB_REGIME_COUNT;ri++)
   {
      if(sparam==PREFIX+"BTN_REG_"+IntegerToString(ri))
      {
         g_regimeAllowed[ri]=!g_regimeAllowed[ri];
         g_lastExecStatus=g_regimeAllowed[ri]?("REGIME_ALLOWED "+OrbRegimeShortName(ri)):("REGIME_BLOCKED "+OrbRegimeShortName(ri));
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         g_histNeedsRedraw=true;DrawHistoricalSignals();UpdateDashboard();ChartRedraw(0);return;
      }
   }

   if(sparam==PREFIX+"BTN_ATR"){g_rtFilterAtr=!g_rtFilterAtr;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_VOL"){g_rtFilterVol=!g_rtFilterVol;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_DAY"){g_rtFilterDay=!g_rtFilterDay;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_TIME"){g_rtTimeExit=!g_rtTimeExit;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_DISP"){g_rtDisplacement=!g_rtDisplacement;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_FVG"){CycleFvgMode();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_EXIT"){CycleExitMode();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_ENTRY"){CycleEntryMode();ClearRetestState("entry_mode_changed");ClearImbalanceState("entry_mode_changed");needRedraw=true;}
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
      g_rtPipSlMode=!g_rtPipSlMode;
      ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,g_rtPipSlMode?DoubleToString(g_rtPipSlPips,1):DoubleToString(g_rtSlDistancePct,0));
      g_lastExecStatus=g_rtPipSlMode?"PIP_SL_ON":"PERCENT_SL_ON";
      needRedraw=true;
   }
   else if(sparam==PREFIX+"BTN_SL_APPLY")
   {
      string valueTxt=ObjectGetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT);
      if(g_rtPipSlMode)SetPipSlPips(StringToDouble(valueTxt));
      else SetSlDistancePct(StringToDouble(valueTxt));
      ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,g_rtPipSlMode?DoubleToString(g_rtPipSlPips,1):DoubleToString(g_rtSlDistancePct,0));
      g_lastExecStatus=g_rtPipSlMode?("PIP_SL_"+DoubleToString(g_rtPipSlPips,1)):("SL_PCT_"+DoubleToString(g_rtSlDistancePct,0));
      needRedraw=true;
   }
   else if(sparam==PREFIX+"BTN_AUDIT")
   {
      g_auditRuntime=!g_auditRuntime;
      Print("ORB15v3 audit logging ",g_auditRuntime?"enabled":"disabled");
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_TF")
   {
      // Cycle through M1 → M5 → M15 → M1...
      g_rtSignalTf=CycleTf(g_rtSignalTf);
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
      g_histNeedsRedraw=true;
      DrawHistoricalSignals();
      UpdateDashboard();
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+


