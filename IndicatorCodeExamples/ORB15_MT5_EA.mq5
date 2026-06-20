//+------------------------------------------------------------------+
//| 15 Minute ORB MT5 EA – v3.1 (production)                         |
//| Interactive dashboard with toggleable filters + live sim stats.   |
//| All filters, signal TF, and confirmation delay dashboard-driven.  |
//| Session clock: NY → broker server via GMT offset.                 |
//+------------------------------------------------------------------+
#property strict
#property version "3.21"
#include <Trade/Trade.mqh>
#define ORB15_BUILD "2026-06-19.v4.3-phase1-exit-engine"

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
enum ORB_EXIT_ENGINE_MODE { ORB_EXIT_FIXED_TARGET=0, ORB_EXIT_EOD_ONLY=1, ORB_EXIT_ORB_MID_INVALIDATION=2, ORB_EXIT_ATR_TRAIL=3, ORB_EXIT_EMA_STOP=4, ORB_EXIT_VWAP_STOP=5 };
enum BT_FILL_MODE { BT_FILL_SIGNAL_CLOSE=0, BT_FILL_NEXT_BAR_OPEN=1, BT_FILL_CONSERVATIVE=2 };
enum BT_SAME_BAR_POLICY { BT_SAMEBAR_CONSERVATIVE=0, BT_SAMEBAR_NEAREST_OPEN=1, BT_SAMEBAR_TP_FIRST=2, BT_SAMEBAR_SL_FIRST=3 };
input ORB_EXEC_MODE InpExecutionMode = ORB_EXEC_SINGLE;
input ORB_TARGET_LEG InpTargetTpLeg = ORB_TARGET_TP4;
input ORB_HC_BE_MODE InpHalfBeMode = ORB_HC_BE_OFF;
input ORB_EXIT_ENGINE_MODE InpExitEngineMode = ORB_EXIT_FIXED_TARGET;
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
input bool   InpUseVolumeFilter     = true;
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
input int  InpHistoricalDays         = 35;
input int  InpHistoricalWeeks        = 5;
input bool InpAuditCsv               = false;
input bool InpLogOnInit              = false;
input bool InpTesterTradeAuditCsv    = false;
input int  InpTesterTradeAuditMaxRows= 50000;
input string InpValidationJobId      = "";
input BT_FILL_MODE InpBacktestFillMode = BT_FILL_NEXT_BAR_OPEN;
input BT_SAME_BAR_POLICY InpBacktestSameBarPolicy = BT_SAMEBAR_CONSERVATIVE;
input bool   InpBacktestUseTickReplay    = true;
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

//--- Runtime toggles (mutable from dashboard) ---------------------------
bool            g_rtFilterAtr     = true;
bool            g_rtFilterVol     = true;
bool            g_rtFilterDay     = false;
bool            g_rtTimeExit      = true;
bool            g_rtDisplacement  = false;
ORB_FVG_MODE    g_rtFvgMode       = ORB_FVG_OFF;
ORB_EXIT_ENGINE_MODE g_rtExitMode = ORB_EXIT_FIXED_TARGET;
bool            g_rtBEOnTp1       = true;
bool            g_rtEaEnabled     = true;
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
struct OrbBtCombo { int tfIdx; int delayIdx; int exitMode; bool atr; bool vol; bool day; bool be; bool disp; bool fvgReq; };
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
double   g_btSpreadPts = 0.0;
double   g_btSlippagePts = 0.0;
double   g_btCommissionPerLot = 0.0;

OrbBtCombo g_btCombos[];
#define OBT_TF_COUNT    3
#define OBT_DELAY_COUNT 4
#define OBT_MAX_DAYS    60
ENUM_TIMEFRAMES g_btTFs[]  = {PERIOD_M1,PERIOD_M5,PERIOD_M15};
int             g_btDelays[]= {0,3,5,10};
OrbBtDayCache   g_btDays[];
int             g_btDayCount = 0;
// Flat [dayIdx * (tfCount*delayCount) + comboIdx] cache; MQL5 does not
// reliably support resizeable jagged arrays of structs.
OrbBtBreakout   g_btBreakouts[];

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
double CalculateLot(double entry,double sl){if(!InpUseAutoRiskLot)return NormalizeVolume(InpFixedLot);double rd=MathAbs(entry-sl);double vpu=ValuePerPriceUnitPerLot();double eq=AccountInfoDouble(ACCOUNT_EQUITY);double rm=eq*MathMax(0.01,InpRiskPerTradePct)/100.0;if(rd<=0||vpu<=0||rm<=0)return NormalizeVolume(InpFixedLot);return NormalizeVolume(rm/(rd*vpu));}
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
   return netR*base*MathMax(0,InpRiskPerTradePct)/100.0;
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
   return "EXIT:FIXED";
}
string RuntimeExitLabel(){return ExitModeLabel(g_rtExitMode);}
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
   else g_rtExitMode=ORB_EXIT_FIXED_TARGET;
}
int ClampExitTrailStartLeg(int leg){return MathMax(0,MathMin(6,leg));}
int ClampEmaPeriod(int period){return period<75?50:100;}
void CycleExitTrailStart(){g_rtExitTrailStartLeg=ClampExitTrailStartLeg(g_rtExitTrailStartLeg>=6?0:g_rtExitTrailStartLeg+1);}
void CycleExitEmaPeriod(){g_rtExitEmaPeriod=(g_rtExitEmaPeriod<75?100:50);}
void CycleExitAtrMultiplier(){if(g_rtExitAtrMultiplier<1.75)g_rtExitAtrMultiplier=2.0;else if(g_rtExitAtrMultiplier<2.25)g_rtExitAtrMultiplier=2.5;else if(g_rtExitAtrMultiplier<2.75)g_rtExitAtrMultiplier=3.0;else g_rtExitAtrMultiplier=1.5;}
string ExitDebugConfig()
{
   return RuntimeExitLabel()+" startLeg="+IntegerToString(g_rtExitTrailStartLeg)+" atrX="+DoubleToString(g_rtExitAtrMultiplier,1)+" ema="+IntegerToString(g_rtExitEmaPeriod);
}
void SetTargetLeg(int leg){g_rtTargetLeg=ClampTargetLeg(leg);g_rtHalfBeLeg=ClampHalfBeLeg(g_rtHalfBeLeg,g_rtTargetLeg);}
void CycleTargetLeg(){SetTargetLeg(RuntimeTargetLeg()>=6?1:RuntimeTargetLeg()+1);}
void CycleHalfBeLeg(){int target=RuntimeTargetLeg();if(target<=1){g_rtHalfBeLeg=0;return;}int h=RuntimeHalfBeLeg()+1;if(h>=target)h=0;g_rtHalfBeLeg=h;}
int ClampHistWeeks(int weeks){if(weeks<=2)return 2;if(weeks<=5)return 5;if(weeks<=10)return 10;return 20;}
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

long RuntimeMagic()
{
   if(g_runtimeMagic!=0)return g_runtimeMagic;
   if(InpAccountRiskEnabled)
   {
      long safe=InpMagic%1000000000000;if(safe<0)safe=-safe;
      g_runtimeMagic=4000000000000000000+safe*1000000+(long)(ChartID()%1000000);
   }
   else if(InpUseChartScopedMagic) g_runtimeMagic=InpMagic*1000000+(long)(ChartID()%1000000);
   else g_runtimeMagic=InpMagic;
   return g_runtimeMagic;
}
bool MagicScoped(long m){return m>=4000000000000000000&&m<5000000000000000000;}
bool MagicOwned(long m){return m==RuntimeMagic()||(!InpAccountRiskEnabled&&m==InpMagic);}
string BtFillLabel(BT_FILL_MODE m){switch(m){case BT_FILL_SIGNAL_CLOSE:return"SIGNAL";case BT_FILL_NEXT_BAR_OPEN:return"NEXT";case BT_FILL_CONSERVATIVE:return"CONS";}return"SIGNAL";}
string BtSameBarLabel(BT_SAME_BAR_POLICY p){switch(p){case BT_SAMEBAR_CONSERVATIVE:return"CONS";case BT_SAMEBAR_NEAREST_OPEN:return"NEAR";case BT_SAMEBAR_TP_FIRST:return"TP1ST";case BT_SAMEBAR_SL_FIRST:return"SL1ST";}return"CONS";}
double BtCostR(double risk)
{
   if(risk<=0)return 0;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.00001;
   double cost=(MathMax(0,g_btSpreadPts)+MathMax(0,g_btSlippagePts))*pt/risk;
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

void Audit(string ev,string dir,double lot,double entry,double sl,double tp,string detail)
{
   if(IsTesterMode()) return;
   if(!g_auditRuntime)return;
   string fileName=AuditFileName();
   int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)return;
   bool empty=(FileSize(h)<=0);
   FileSeek(h,0,SEEK_END);
   if(empty)
      FileWrite(h,"ts_gmt","ts_server","ts_local","ms","event","build","symbol","timeframe",
         "signal_tf","delay","atr_f","vol_f","day_f","be","direction",
         "lot","entry","sl","tp","orb_h","orb_l","bid","ask","spread","detail");
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
      IntegerToString(CurrentSpreadPoints()), detail);
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
void CloseAllOwn(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(!IsOwnPosition())continue;bool ok=trade.PositionClose(t);Audit(ok?"close":"close_failed","",PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),"ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());}}

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
   if(!InpAccountRiskEnabled){detail="risk_off";return fallback;}
   double cap,dp,tp;RiskMetrics(cap,dp,tp);
   double sf=MathMax(1,MathMin(100,InpSafetyBufferPct))/100.0;
   double mu=cap>0?AccountInfoDouble(ACCOUNT_MARGIN)/cap*100.0:100.0;
   if(cap<=0||(InpDailyLossLimitPct>0&&dp>=InpDailyLossLimitPct*sf)||(InpMaxDrawdownPct>0&&tp>=InpMaxDrawdownPct*sf)||(InpMaxMarginUsagePct>0&&mu>=InpMaxMarginUsagePct))
   {detail="risk_block cap="+DoubleToString(cap,2)+" daily="+DoubleToString(dp,2)+" dd="+DoubleToString(tp,2);return InpFailClosed?0:fallback;}
   ENUM_ORDER_TYPE ot=dir=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double slRes=0,atrRes=0,atr=ClosedDailyAtr();
   double atrExit=dir=="BUY"?entry-atr:entry+atr;
   if(atr<=0||!OrderCalcProfit(ot,_Symbol,1.0,entry,sl,slRes)||!OrderCalcProfit(ot,_Symbol,1.0,entry,atrExit,atrRes))
   {detail="risk_calc_fail";return InpFailClosed?0:fallback;}
   double slMpl=MathAbs(slRes),atrMpl=MathAbs(atrRes);
   if(slMpl<=0||atrMpl<=0){detail="risk_zero_mpl";return InpFailClosed?0:fallback;}
   double tradeBudget=cap*MathMax(0,InpRiskPerTradePct)/100.0;
   double atrBudget=cap*MathMax(0,InpAtrExposurePct)/100.0;
   double portfolioBudget=cap*MathMax(0,InpMaxPortfolioPct)/100.0;
   double avail=MathMax(0,portfolioBudget-OpenScopeRisk());
   if(tradeBudget<=0||atrBudget<=0||avail<=0){detail="budget_exhausted";return 0;}
   double raw=MathMin(tradeBudget/slMpl,MathMin(atrBudget/atrMpl,avail/slMpl));
   double vol=NormalizeVolume(raw);
   double margin=0;bool mc=OrderCalcMargin(ot,_Symbol,vol,entry,margin);
   double proj=cap>0?(AccountInfoDouble(ACCOUNT_MARGIN)+margin)/cap*100.0:100.0;
   if(vol<=0||!mc||margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)||(InpMaxMarginUsagePct>0&&proj>InpMaxMarginUsagePct)){detail="margin_block";return 0;}
   detail="lot="+DoubleToString(vol,4)+" cap="+DoubleToString(cap,2)+" trade_budget="+DoubleToString(tradeBudget,2)+" open_risk="+DoubleToString(OpenScopeRisk(),2);
   return vol;
}

void EnforceRiskBreach()
{
   if(!InpAccountRiskEnabled||!InpLiquidateOnBreach)return;
   if(InpDailyLossLimitPct<=0&&InpMaxDrawdownPct<=0)return;
   uint now=GetTickCount();if(now-g_lastRiskGuardMs<250)return;g_lastRiskGuardMs=now;
   double cap,dp,tp;RiskMetrics(cap,dp,tp);
   double sf=MathMax(1,MathMin(100,InpSafetyBufferPct))/100.0;
   bool breach=(InpDailyLossLimitPct>0&&dp>=InpDailyLossLimitPct*sf)||(InpMaxDrawdownPct>0&&tp>=InpMaxDrawdownPct*sf);
   if(!breach)return;
   Audit("risk_liquidate","",0,0,0,0,"cap="+DoubleToString(cap,2)+" daily="+DoubleToString(dp,2)+" dd="+DoubleToString(tp,2));
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

bool FindFreshFvgRates(const MqlRates &rates[],int signalIdx,string dir,double &top,double &bottom,double &size,datetime &fvgTime)
{
   top=0.0;bottom=0.0;size=0.0;fvgTime=0;
   int total=ArraySize(rates);
   if(signalIdx<2||total<3)return false;
   int scan=MathMin(MathMax(3,InpFvgScanWindow),MathMax(3,InpFvgLookback));
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.00001;
   double minGap=MathMax(0.0,InpMinFvgGapPoints)*pt;
   int scanStart=MathMin(total-1,signalIdx+MathMax(0,InpFvgForwardBars));
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
   hasFvg=FindFreshFvgRates(rates,idx,dir,top,bottom,size,ft);
   detail="disp="+(hasDisp?"1":"0")+" fvg="+(hasFvg?"1":"0")+" idx="+IntegerToString(idx)+" bars="+IntegerToString(c)+" fw="+IntegerToString(InpFvgForwardBars);
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

bool SimulateTradeTicks(datetime sigTime,datetime tradeEnd,double entry,double sl,bool isBuy,
                        int halfBeLeg,HistResult &res)
{
   if(!InpBacktestUseTickReplay) return false;
   if(g_rtExitMode!=ORB_EXIT_FIXED_TARGET) return false;
   datetime startTime=BarCloseTime(g_rtSignalTf,sigTime);
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN)
   {
      int sec=PeriodSeconds(g_rtSignalTf);
      if(sec<=0)sec=60;
      startTime=sigTime+sec;
   }
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
   entry=NormalizePrice(entry);
   double risk=MathAbs(entry-sl);
   if(risk<=0.0)return false;

   int targetLeg=RuntimeTargetLeg();
   int hcLeg=ClampHalfBeLeg(halfBeLeg,targetLeg);
   res.targetLeg=targetLeg;
   res.hcLeg=hcLeg;
   double tps[6];
   for(int k=0;k<6;k++)
      tps[k]=NormalizePrice(isBuy?entry+risk*LegR(k+1):entry-risk*LegR(k+1));
   res.simEntry=entry;
   res.simSl=sl;
   res.simTarget=tps[targetLeg-1];

   double effSl=sl;
   bool beApplied=false;
   for(int i=first;i<copied;i++)
   {
      double bid=ticks[i].bid;
      double ask=ticks[i].ask;
      if(bid<=0.0 || ask<=0.0)continue;
      double closePx=isBuy?bid:ask;

      bool slHit=isBuy?(closePx<=effSl):(closePx>=effSl);
      if(slHit)
      {
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
      if(res.maxTp>=targetLeg)
      {
         res.outcome="TP"+IntegerToString(targetLeg);
         break;
      }
   }
   if(res.outcome=="open"&&res.maxTp>0)res.outcome="TP"+IntegerToString(res.maxTp);

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
      if(res.maxTp>=targetLeg)
      {
         double targetR=LegR(targetLeg);
         res.netR=hcLeg>0?0.5*LegR(hcLeg)+0.5*targetR:targetR;
      }
      else if((res.outcome=="BE"||res.outcome=="open"||res.outcome=="TP"+IntegerToString(res.maxTp))&&hcLeg>0&&res.maxTp>=hcLeg)
         res.netR=0.5*LegR(hcLeg);
      else if(res.outcome=="SL")res.netR=-1.0;
   }
   res.costR=BtCostR(risk);
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
   MqlRates r[];int c=CopyRates(_Symbol,g_rtSignalTf,sigTime,tradeEnd,r);
   if(c<=1)return res;
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN && c>1) entry=r[1].open;
   else if(g_btFillMode==BT_FILL_CONSERVATIVE && c>1)
   {
      double no=r[1].open;
      entry=isBuy?MathMax(entry,no):MathMin(entry,no);
   }
   double risk=MathAbs(entry-sl);
   if(risk<=0)return res;

   int sec=PeriodSeconds(g_rtSignalTf);if(sec<=0)sec=60;
   int ctxBars=MathMax(320,MathMax(MathMax(InpExitEmaPeriod*4,InpExitAtrPeriod*4),100));
   MqlRates ctx[];int ctxCount=CopyRates(_Symbol,g_rtSignalTf,sigTime-(datetime)(ctxBars*sec),tradeEnd,ctx);

   int targetLeg=RuntimeTargetLeg();
   int hcLeg=ClampHalfBeLeg(halfBeLeg,targetLeg);
   res.targetLeg=targetLeg;
   res.hcLeg=hcLeg;
   double tps[6];
   for(int k=0;k<6;k++)
   {
      double rr=LegR(k+1);
      tps[k]=NormalizePrice(isBuy?entry+risk*rr:entry-risk*rr);
   }
   res.simEntry=NormalizePrice(entry);
   res.simSl=NormalizePrice(sl);
   res.simTarget=ExitModeUsesFixedTp(g_rtExitMode)?tps[targetLeg-1]:0.0;

   double effSl=sl;bool beApplied=false;
   double bestHigh=entry,bestLow=entry;
   for(int i=1;i<c;i++) // skip signal bar itself
   {
      if(r[i].time>tradeEnd)break;
      bool slHit=isBuy?(r[i].low<=effSl):(r[i].high>=effSl);

      int hitLeg=0;
      if(ExitModeUsesFixedTp(g_rtExitMode))
      {
         for(int k=0;k<6;k++)
         {
            bool hit=isBuy?(r[i].high>=tps[k]):(r[i].low<=tps[k]);
            if(hit)hitLeg=k+1;
         }
      }

      // Same-bar first-touch approximation only matters before any profit leg has been reached.
      if(slHit&&hitLeg>0&&res.maxTp==0)
      {
         if(BtTpFirst(isBuy,r[i].open,effSl,tps[0]))
         {
            res.maxTp=hitLeg;
            if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
            if(res.maxTp>=targetLeg){res.outcome="TP"+IntegerToString(targetLeg);break;}
         }
         else{res.outcome="SL";break;}
      }
      else
      {
         if(slHit){res.outcome=beApplied?"BE":"SL";break;}
         if(hitLeg>res.maxTp)res.maxTp=hitLeg;
      }

      if(hcLeg>0 && res.maxTp>=hcLeg && !beApplied){effSl=entry;beApplied=true;}
      if(res.maxTp>=targetLeg){res.outcome="TP"+IntegerToString(targetLeg);break;}

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
   if(res.outcome=="open"&&g_rtExitMode==ORB_EXIT_EOD_ONLY&&c>1){res.outcome="EOD_EXIT";res.exitPrice=r[c-1].close;}
   else if(res.outcome=="open"&&res.maxTp>0)res.outcome="TP"+IntegerToString(res.maxTp);

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
      if(res.maxTp>=targetLeg)
      {
         double targetR=LegR(targetLeg);
         if(hcLeg>0)res.netR=0.5*LegR(hcLeg)+0.5*targetR;
         else res.netR=targetR;
      }
      else if(res.outcome=="MID_EXIT"||res.outcome=="VWAP_EXIT"||res.outcome=="EMA_EXIT"||res.outcome=="EOD_EXIT")
      {
         double px=res.exitPrice>0?res.exitPrice:(c>1?r[c-1].close:entry);
         res.netR=(isBuy?(px-entry):(entry-px))/risk;
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
   if(IsTesterMode()){DeleteHist();g_histStatLine="tester_skip";return;}
   if(!InpDrawHistoricalSignals){DeleteHist();g_histStatLine="off";return;}
   datetime now=TimeCurrent();
   if(!g_histNeedsRedraw&&g_lastHistBuild>0&&now-g_lastHistBuild<300)return;
   g_lastHistBuild=now;g_histNeedsRedraw=false;
   DeleteHist();

   datetime nyNow=ServerToSessionLocal(now);MqlDateTime nySt;TimeToStruct(nyNow,nySt);
   datetime nyMid=MakeDateTime(nySt.year,nySt.mon,nySt.day,0,0,0);
   int days=RuntimeHistoricalDays();
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.0001;

   g_histTotal=0;g_histWins=0;g_histLosses=0;g_histNetR=0;g_histNetMoney=0;
   int checked=0,drawn=0,filtered=0;

   Print("ORB15v3 ======= HIST REDRAW START ======= TF=",TfLabel(g_rtSignalTf),
         " Delay=",g_rtUseDelay?IntegerToString(g_rtDelayMin)+"min":"OFF",
         " ATR=",g_rtFilterAtr?"ON":"OFF"," VOL=",g_rtFilterVol?"ON":"OFF",
         " DAY=",g_rtFilterDay?"ON":"OFF"," ",HalfBeLabel(),
         " ",TargetLabel()," audit_weeks=",IntegerToString(g_rtHistoricalWeeks));

   for(int back=days-1;back>=0;back--)
   {
      datetime nyDay=nyMid-back*86400;MqlDateTime daySt;TimeToStruct(nyDay,daySt);
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

      g_histTotal++;

      // Simulate trade
      bool isBuy=(dir=="BUY");
      double buffer=MathMax(0.0,InpSlBufferPoints)*pt;
      double entry=sigC;
      double rawSl=isBuy?(lo-buffer):(hi+buffer);
      double sl=ScaleSlFromEntry(isBuy,entry,rawSl);
      double risk=MathAbs(entry-sl);if(risk<=pt)continue;
      double r1v=MathMax(0.1,InpTp1R),r2v=MathMax(0.1,InpTp2R),r3v=MathMax(0.1,InpTp3R);
      double tp1=NormalizePrice(isBuy?entry+risk*r1v:entry-risk*r1v);
      double tp2=NormalizePrice(isBuy?entry+risk*r2v:entry-risk*r2v);
      double tp3=NormalizePrice(isBuy?entry+risk*r3v:entry-risk*r3v);
      double tp4=NormalizePrice(isBuy?entry+risk*LegR(4):entry-risk*LegR(4));
      double tp5=NormalizePrice(isBuy?entry+risk*LegR(5):entry-risk*LegR(5));
      double tp6=NormalizePrice(isBuy?entry+risk*LegR(6):entry-risk*LegR(6));

      datetime simEnd=now;
      datetime nextSig=0;
      if(FindNextHistoricalSignalAfter(sigT,now,nextSig))
         simEnd=nextSig;
      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_orbHigh=hi;g_orbLow=lo;g_orbStartServer=os;g_orbEndServer=oe;g_tradeEndServer=te;
      HistResult sim=SimulateTrade(sigT,simEnd,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,RuntimeHalfBeLeg());
      g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
      bool finalOutcome=(sim.outcome!="open");
      double statR=finalOutcome?sim.netR:0.0;
      if(finalOutcome&&sim.netR>0)g_histWins++;
      else if(finalOutcome&&sim.netR<0)g_histLosses++;
      g_histNetR+=statR;
      g_histNetMoney+=SimMoneyPnl(statR);

      // Debug audit
      Print("ORB15v3 HIST #",g_histTotal," ",dir,
            " date=",daySt.year,".",daySt.mon,".",daySt.day,
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
      double arwP=isBuy?(sigL-pad):(sigH+pad);
      string dateKey=IntegerToString(daySt.year)+StringFormat("%02d%02d",daySt.mon,daySt.day);
      string base=PREFIX+"HIST_"+dateKey+"_"+dir+"_";

      color arwClr=sim.isWin?clrLime:(sim.outcome=="SL"?clrTomato:clrGold);
      int arwCode=isBuy?233:234;
      if(ObjectFind(0,base+"ARW")<0)ObjectCreate(0,base+"ARW",OBJ_ARROW,0,sigT,arwP);
      else ObjectMove(0,base+"ARW",0,sigT,arwP);
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
      color txtClr=!finalOutcome?clrKhaki:(sim.isWin?clrPaleGreen:(sim.outcome=="SL"?clrLightSalmon:clrKhaki));
      double txtP=isBuy?arwP-pad*0.6:arwP+pad*0.6;
      DrawSignalText(base+"TXT",sigT,txtP,txt,txtClr);

      double simRisk=MathAbs(sim.simEntry-sim.simSl);
      string hcTxt=sim.hcLeg>0?DoubleToString(PriceAtLeg(isBuy,sim.simEntry,simRisk,sim.hcLeg),_Digits):"OFF";
      string lvlTxt="SL="+DoubleToString(sim.simSl,_Digits)
         +" TP="+DoubleToString(sim.simTarget,_Digits)
         +" HC="+hcTxt;
      double lvlP=isBuy?txtP-pad*0.55:txtP+pad*0.55;
      DrawSignalText(base+"LVLTXT",sigT,lvlP,lvlTxt,sim.isWin?clrLightCyan:clrMistyRose);
      drawn++;
   }

   double wr=g_histTotal>0?(double)g_histWins/(double)g_histTotal*100.0:0;
   g_histStatLine=IntegerToString(g_histTotal)+" sig | "+IntegerToString(g_histWins)+"W "+IntegerToString(g_histLosses)+"L | WR "+DoubleToString(wr,1)+"% | Net "+DoubleToString(g_histNetR,1)+"R | $ "+(g_histNetMoney>=0?"+":"")+DoubleToString(g_histNetMoney,2);
   if(filtered>0)g_histStatLine+=" | "+IntegerToString(filtered)+" filt";
   Print("ORB15v3 ======= HIST RESULT: ",g_histStatLine," checked=",checked," drawn=",drawn," =======");
   Audit("hist_redraw","",0,0,0,0,g_histStatLine+" days="+IntegerToString(days));
}

//=========================================================================
//  AUDIT ENGINE — Position Probe + History Scan
//=========================================================================
void OrbAudit_PositionProbe()
{
   if(!g_auditRuntime) return;
   datetime now=TimeCurrent();
   if(g_auditLastProbeTime>0 && now-g_auditLastProbeTime<30) return;
   g_auditLastProbeTime=now;
   string fileName="ORB15_PositionProbe_"+AuditDateStr()+".csv";
   string hash="";
   int count=0;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;
      if(!IsOwnPosition())continue;
      int d=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      double lots=PositionGetDouble(POSITION_VOLUME),px=d>0?bid:ask;
      double risk=MathAbs(entry-sl),currentR=risk>_Point?(d>0?(px-entry)/risk:(entry-px)/risk):0;
      double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      count++;
      hash+=IntegerToString((int)t)+":"+DoubleToString(currentR,2)+";";
      int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
      if(h==INVALID_HANDLE) continue;
      bool empty=(FileSize(h)<=0);FileSeek(h,0,SEEK_END);
      if(empty)FileWrite(h,"ts_gmt","ts_server","ms","event","build","symbol","ticket","direction","lots","entry","sl","tp","px","risk","current_r","pnl");
      FileWrite(h,TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         IntegerToString((int)(GetTickCount()%1000)),"position_probe",ORB15_BUILD,_Symbol,
         IntegerToString((int)t),d>0?"BUY":"SELL",DoubleToString(lots,4),AuditPx(entry),AuditPx(sl),AuditPx(tp),AuditPx(px),
         DoubleToString(risk,_Digits),DoubleToString(currentR,3),DoubleToString(pnl,2));
      FileClose(h);
   }
   if(count<=0 && hash!= g_auditLastProbeHash)
   {
      int h=FileOpen(fileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
      if(h!=INVALID_HANDLE){bool empty=(FileSize(h)<=0);FileSeek(h,0,SEEK_END);
         if(empty)FileWrite(h,"ts_gmt","ts_server","ms","event","build","symbol","ticket","direction","lots","entry","sl","tp","px","risk","current_r","pnl");
         FileWrite(h,TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
            IntegerToString((int)(GetTickCount()%1000)),"position_probe_flat",ORB15_BUILD,_Symbol,"0","","0","0","0","0","0","0","0","0");
         FileClose(h);}
      hash="flat";
   }
   g_auditLastProbeHash=hash;
}

void OrbAudit_HistoryScan()
{
   if(!g_auditRuntime) return;
   datetime now=TimeCurrent();
   if(g_auditLastHistScan>0 && now-g_auditLastHistScan<2) return;
   g_auditLastHistScan=now;
   datetime newestTime=g_auditLastHistTime;ulong newestTicket=g_auditLastHistTicket;
   if(!HistorySelect(now-86400*3,now)) return;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong dt=HistoryDealGetTicket(i);if(dt==0)continue;
      ENUM_DEAL_TYPE dtp=(ENUM_DEAL_TYPE)HistoryDealGetInteger(dt,DEAL_TYPE);
      if(dtp!=DEAL_TYPE_BUY&&dtp!=DEAL_TYPE_SELL)continue;
      ENUM_DEAL_ENTRY de=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt,DEAL_ENTRY);
      if(de!=DEAL_ENTRY_OUT&&de!=DEAL_ENTRY_INOUT)continue;
      if(HistoryDealGetString(dt,DEAL_SYMBOL)!=_Symbol)continue;
      if(!MagicOwned((long)HistoryDealGetInteger(dt,DEAL_MAGIC)))continue;
      datetime ct=(datetime)HistoryDealGetInteger(dt,DEAL_TIME);
      if(ct<g_auditLastHistTime||(ct==g_auditLastHistTime&&dt<=g_auditLastHistTicket))continue;
      double pnl=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_SWAP)+HistoryDealGetDouble(dt,DEAL_COMMISSION)+HistoryDealGetDouble(dt,DEAL_FEE);
      string dir=dtp==DEAL_TYPE_BUY?"SELL":"BUY";
      Audit("history_close",dir,HistoryDealGetDouble(dt,DEAL_VOLUME),HistoryDealGetDouble(dt,DEAL_PRICE),0,0,
         "pnl="+DoubleToString(pnl,2)+" deal="+IntegerToString((int)dt));
      if(ct>newestTime||(ct==newestTime&&dt>newestTicket)){newestTime=ct;newestTicket=dt;}
   }
   g_auditLastHistTime=newestTime;g_auditLastHistTicket=newestTicket;
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
   for(int xm=0;xm<6;xm++)
   for(int a=0;a<2;a++)for(int v=0;v<2;v++)for(int d=0;d<2;d++)for(int b=0;b<2;b++)for(int ds=0;ds<2;ds++)for(int f=0;f<2;f++)
   {
      OrbBtCombo c;c.tfIdx=ti;c.delayIdx=di;c.exitMode=xm;c.atr=(a==1);c.vol=(v==1);c.day=(d==1);c.be=(b==1);c.disp=(ds==1);c.fvgReq=(f==1);
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
      FileWrite(h,"timestamp","symbol","chart_tf","signal_tf","delay_min","exit_mode","atr_filter","vol_filter","day_filter","be_on_tp1","displacement_filter","fvg_required",
         "fill_mode","same_bar_policy","spread_pts","slippage_pts","commission_per_lot",
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
      double buffer=MathMax(0,InpSlBufferPoints)*pt;
      double entry=ob.sigClose;
      double rawSl=isBuy?(g_btDays[di].orbLo-buffer):(g_btDays[di].orbHi+buffer);
      double sl=ScaleSlFromEntry(isBuy,entry,rawSl);
      double risk=MathAbs(entry-sl);if(risk<=pt) continue;
      double r1v=MathMax(0.1,InpTp1R),r2v=MathMax(0.1,InpTp2R),r3v=MathMax(0.1,InpTp3R);
      double tp1=NormalizePrice(isBuy?entry+risk*r1v:entry-risk*r1v);
      double tp2=NormalizePrice(isBuy?entry+risk*r2v:entry-risk*r2v);
      double tp3=NormalizePrice(isBuy?entry+risk*r3v:entry-risk*r3v);
      // Use the correct TF/exit/orb context for simulation.
      ENUM_TIMEFRAMES saveTf=g_rtSignalTf;ORB_EXIT_ENGINE_MODE saveExit=g_rtExitMode;
      double saveOrbH=g_orbHigh,saveOrbL=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_rtSignalTf=g_btTFs[combo.tfIdx];g_rtExitMode=(ORB_EXIT_ENGINE_MODE)combo.exitMode;
      g_orbHigh=g_btDays[di].orbHi;g_orbLow=g_btDays[di].orbLo;g_orbStartServer=g_btDays[di].orbStart;g_orbEndServer=g_btDays[di].orbEnd;g_tradeEndServer=g_btDays[di].tradeEnd;
      HistResult sim=SimulateTrade(ob.sigTime,g_btDays[di].tradeEnd,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,combo.be?1:0);
      g_rtSignalTf=saveTf;g_rtExitMode=saveExit;g_orbHigh=saveOrbH;g_orbLow=saveOrbL;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
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
      (c.atr?"1":"0"),(c.vol?"1":"0"),(c.day?"1":"0"),(c.be?"1":"0"),(c.disp?"1":"0"),(c.fvgReq?"1":"0"),
      BtFillLabel(g_btFillMode),BtSameBarLabel(g_btSameBarPolicy),
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

//=========================================================================
//  DASHBOARD (Nas-inspired design with toggle buttons + TF selector)
//=========================================================================
void DrawDashboard()
{
   if(!InpShowDashboard){DeleteDash();return;}
   int x=InpDashboardX,y=InpDashboardY;
   int W=620,H=500;

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

   // Status line
   string state=g_rtEaEnabled?"EA ON":"EA OFF";
   string orb=g_orbReady?"READY":"WAIT";
   string exec=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG?"3-LEG":"SINGLE "+TargetLabel()+" "+HalfBeLabel();
   CreateLabel("DASH_L1",x+12,y+34,state+" | ORB "+orb+" | "+exec+" | Signal: "+TfLabel(g_rtSignalTf),
      g_rtEaEnabled?C'80,255,180':C'221,55,78',8);

   // ORB info
   string delayTxt=g_rtUseDelay?IntegerToString(g_rtDelayMin)+"m delay":"no delay";
   CreateLabel("DASH_L2",x+12,y+50,
      SessionClockLabel()+" | GMT+"+DoubleToString(InpBrokerGmtOffsetHours,1)
      +" | "+delayTxt+" | Spread "+IntegerToString(CurrentSpreadPoints())+"pt",
      muted,8);
   CreateLabel("DASH_L3",x+12,y+66,
      "ORB H "+DoubleToString(g_orbHigh,_Digits)+" L "+DoubleToString(g_orbLow,_Digits)
      +" | Risk "+DoubleToString(InpRiskPerTradePct,1)+"% | "+(g_rtDisplacement?"DISP ON":"DISP OFF")+" | "+FvgModeLabel(),
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
   CreateButton("BTN_HC",x+228,r2y,74,18,HalfBeLabel(),RuntimeHalfBeLeg()>0?C'30,120,70':C'80,80,80');
   CreateButton("BTN_TP",x+306,r2y,76,18,TargetLabel(),C'38,101,176');
   CreateButton("BTN_AUDIT",x+386,r2y,66,18,g_auditRuntime?"AUDIT":"AUDIT OFF",g_auditRuntime?C'120,88,25':C'80,80,80');

   CreateButton("BTN_EA",x+456,r2y,54,18,g_rtEaEnabled?"EA ON":"EA OFF",g_rtEaEnabled?C'30,150,95':C'178,37,57');
   CreateButton("BTN_EXIT",x+514,r2y,94,18,RuntimeExitLabel(),g_rtExitMode==ORB_EXIT_FIXED_TARGET?C'80,80,80':C'38,101,176');
   CreateButton("BTN_CLOSEALL",x+326,y+475,86,18,"CLOSE ALL",C'178,37,57');

   // Separator
   CreateRect("DASH_SEP2",x+8,y+132,W-16,1,C'65,116,172',C'65,116,172');

   // Stats section
   double wr=g_histTotal>0?(double)g_histWins/(double)g_histTotal*100.0:0;
   color wrClr=wr>=50?C'80,255,180':C'255,95,140';

   CreateLabel("DASH_STITLE",x+12,y+138,IntegerToString(g_rtHistoricalWeeks)+"W AUDIT+CHART ("+TfLabel(g_rtSignalTf)+")",acB,9);
   CreateButton("BTN_AUD_2W",x+310,y+138,44,18,"2W",g_rtHistoricalWeeks==2?C'38,101,176':C'80,80,80');
   CreateButton("BTN_AUD_5W",x+358,y+138,44,18,"5W",g_rtHistoricalWeeks==5?C'38,101,176':C'80,80,80');
   CreateButton("BTN_AUD_10W",x+406,y+138,48,18,"10W",g_rtHistoricalWeeks==10?C'38,101,176':C'80,80,80');
   CreateButton("BTN_AUD_20W",x+458,y+138,50,18,"20W",g_rtHistoricalWeeks==20?C'38,101,176':C'80,80,80');
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
   CreateLabel("DASH_STAT3",x+12,y+190,tpInfo+" | "+ExitDebugConfig()+" | SL% "+DoubleToString(g_rtSlDistancePct,0)+" | AutoLot "+BoolText(InpUseAutoRiskLot),C'134,158,182',7);
   CreateLabel("DASH_SL_L",x+330,y+190,"SL%:",C'134,158,182',7);
   CreateEdit("EDIT_SL_PCT",x+362,y+188,48,18,DoubleToString(g_rtSlDistancePct,0));
   CreateButton("BTN_SL_APPLY",x+416,y+188,58,18,"APPLY",C'38,101,176');

   // Win rate bar
   int barW=496,barH=14;
   CreateRect("DASH_WRBAR_BG",x+12,y+206,barW,barH,C'42,51,68',C'134,158,182');
   int fillW=(int)MathRound((double)barW*MathMax(0,MathMin(100,wr))/100.0);
   if(fillW>2)CreateRect("DASH_WRBAR_FILL",x+13,y+207,fillW-2,barH-2,wrClr,wrClr);

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
   CreateLabel("DASH_BTCNT",x+286,btY+2,IntegerToString(g_btRunning?g_btTotal:1536)+" combos",C'134,158,182',7);

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

   int costY=optY+22;
   CreateLabel("DASH_BTSP_L",x+12,costY+2,"Spr:",C'134,158,182',7);
   CreateEdit("EDIT_BT_SPREAD",x+42,costY,45,18,DoubleToString(g_btSpreadPts,1));
   CreateLabel("DASH_BTSL_L",x+94,costY+2,"Slip:",C'134,158,182',7);
   CreateEdit("EDIT_BT_SLIP",x+130,costY,45,18,DoubleToString(g_btSlippagePts,1));
   CreateLabel("DASH_BTCM_L",x+184,costY+2,"Comm/Lot:",C'134,158,182',7);
   CreateEdit("EDIT_BT_COMM",x+252,costY,58,18,DoubleToString(g_btCommissionPerLot,2));
   CreateLabel("DASH_BTDEF",x+320,costY+2,"0 spread = live spread",C'100,112,130',7);

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
   if(InpUseClosedBarBreakout)g_lastCheckedSignalBarTime=bt;
   sc=iClose(_Symbol,g_rtSignalTf,sh);if(sc<=0)return false;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double mb=MathMax(0.0,InpMinBreakoutPoints)*pt;
   if(sc>g_orbHigh+mb)dir="BUY";else if(sc<g_orbLow-mb)dir="SELL";
   return dir!="";
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
   Audit(ok?"half_close":"half_close_failed",
      (long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL",
      closeVol,PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),
      "ret="+IntegerToString((int)trade.ResultRetcode())+" "+trade.ResultRetcodeDescription());
   return ok;
}

bool ExitModeUsesFixedTp(ORB_EXIT_ENGINE_MODE mode)
{
   return mode!=ORB_EXIT_EOD_ONLY;
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
   bool any=false,allOk=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0||!PositionSelectByTicket(t)||!IsOwnPosition())continue;
      string dir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL";
      double vol=PositionGetDouble(POSITION_VOLUME);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      bool ok=trade.PositionClose(t);
      any=true;if(!ok)allOk=false;
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
            if(mk)moved++;
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
         if(progR<InpTimeExitMinProgress){Audit("time_exit",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,0,0,"R="+DoubleToString(progR,2));CloseAllOwn();g_tradeDir=0;g_tradeOpenTime=0;g_lastExecStatus="TIME_EXIT";}
      }
   }
}

//=========================================================================
//  MAIN SIGNAL PIPELINE — uses g_rtSignalTf
//=========================================================================
void TryOpenSignal()
{
   if(!g_rtEaEnabled)return;if(!BuildOrb())return;
   if(InpOneTradePerNyDay&&g_tradeTaken)return;if(OwnPositionExists())return;
   string dir;datetime bt;double sc;if(!ComputeSignal(dir,bt,sc))return;
   g_lastSignalBarTime=bt;
   string fr="";
   if(!CheckDayFilter(fr)||!CheckAtrFilter(fr)||!CheckVolFilter(fr)){g_lastFilterReason=fr;g_lastExecStatus="FILTERED";Audit("filtered",dir,0,sc,0,0,fr);return;}
   string modernDetail="";
   if(!ModernFilterAllows(g_orbEndServer,g_tradeEndServer,g_rtSignalTf,bt,dir,g_rtDisplacement,g_rtFvgMode,fr,modernDetail))
   {
      g_lastFilterReason=fr;g_lastExecStatus="FILTERED";Audit("filtered",dir,0,sc,0,0,fr+" "+modernDetail);return;
   }
   if(!SpreadAllowed()){g_lastFilterReason="SPREAD";g_lastExecStatus="FILTERED";return;}
   g_lastFilterReason="";
   // Draw arrows
   int sh=InpUseClosedBarBreakout?1:0;double sH=iHigh(_Symbol,g_rtSignalTf,sh),sL=iLow(_Symbol,g_rtSignalTf,sh);
   double pad=MathMax(MathAbs(g_orbHigh-g_orbLow)*0.12,SymbolInfoDouble(_Symbol,SYMBOL_POINT)*40.0);
   bool isBuy=dir=="BUY";double arwP=isBuy?(sL-pad):(sH+pad);
   DrawSignalArrow(PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+dir+"_ARW",bt,arwP,isBuy,false);
   DrawSignalText(PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+dir+"_TXT",bt,isBuy?arwP-pad*0.6:arwP+pad*0.6,"ORB LIVE "+dir+" "+modernDetail,isBuy?clrLime:clrTomato);
   Audit("signal",dir,0,sc,0,0,"bar="+FmtTime(bt)+" "+modernDetail);
   // Tick & geometry
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double buf=MathMax(0,InpSlBufferPoints)*pt;
   double entry=NormalizeTradePrice(isBuy?tick.ask:tick.bid);
   double rawSl=NormalizeTradePrice(isBuy?(g_orbLow-buf):(g_orbHigh+buf));
   double sl=ScaleSlFromEntry(isBuy,entry,rawSl);
   double risk=MathAbs(entry-sl);if(risk<=pt)return;
   double tp1=PriceAtLeg(isBuy,entry,risk,1);
   double tp2=PriceAtLeg(isBuy,entry,risk,2);
   double tp3=PriceAtLeg(isBuy,entry,risk,3);
   double tp4=PriceAtLeg(isBuy,entry,risk,4);
   double tp5=PriceAtLeg(isBuy,entry,risk,5);
   double tp6=PriceAtLeg(isBuy,entry,risk,6);
   bool opened=false;
   string lotDetail="";
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      if(!ExitModeUsesFixedTp(g_rtExitMode))
      {
         g_lastExecStatus="FILTERED";
         Audit("exit_mode_block",dir,0,entry,sl,0,"partial_3leg_incompatible "+ExitDebugConfig());
         return;
      }
      double lot=ResolveLot(dir,entry,sl,lotDetail);
      if(lot<=0){g_lastExecStatus="FILTERED";Audit("risk_block",dir,0,entry,sl,tp3,lotDetail);return;}
      opened=ExecThreeLegs(dir,entry,sl,tp1,tp2,tp3,lot);
      if(opened){g_tradeTp1=tp1;g_tradeTp2=tp2;g_tradeTp3=tp3;Audit("opened_3leg",dir,lot,entry,sl,tp3,lotDetail);}
   }
   else
   {
      int targetLeg=RuntimeTargetLeg();
      double fixedTp=targetLeg==1?tp1:(targetLeg==2?tp2:(targetLeg==3?tp3:(targetLeg==4?tp4:(targetLeg==5?tp5:tp6))));
      double tp=ExitModeUsesFixedTp(g_rtExitMode)?fixedTp:0.0;
      double lot=ResolveLot(dir,entry,sl,lotDetail);
      if(lot<=0){g_lastExecStatus="FILTERED";Audit("risk_block",dir,0,entry,sl,tp,lotDetail);return;}
      opened=ExecSingle(dir,entry,sl,tp,lot);
      if(opened){g_tradeTp1=tp1;g_tradeTp2=tp2;g_tradeTp3=tp3;g_tradeTp4=tp4;g_tradeTp5=tp5;g_tradeTp6=tp6;Audit("opened",dir,lot,entry,sl,tp,lotDetail+" "+TargetLabel()+" "+HalfBeLabel()+" "+ExitDebugConfig());}
   }
   if(opened){g_tradeTaken=true;g_tradeDir=isBuy?1:-1;g_tradeEntry=entry;g_tradeSl=sl;g_tradeOpenTime=TimeCurrent();g_beMoved=false;g_halfClosed=false;g_tradeRisk=MathAbs(entry-sl);g_tradeBestHigh=entry;g_tradeBestLow=entry;g_tradeLastDynamicExitBar=0;g_lastExecStatus="OPENED";}
   else{g_lastExecStatus="FAIL";Audit("order_fail",dir,0,entry,sl,0,"ret="+IntegerToString((int)trade.ResultRetcode()));}
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
   g_rtTimeExit=InpUseTimeExit;g_rtDisplacement=InpUseDisplacementFilter;g_rtFvgMode=InpFvgMode;g_rtBEOnTp1=InpMoveToBEOnTp1;g_rtEaEnabled=InpEaEnabled;
   g_rtExitMode=InpExitEngineMode;
   g_rtExitTrailStartLeg=ClampExitTrailStartLeg(InpExitTrailStartLeg);
   g_rtExitEmaPeriod=ClampEmaPeriod(InpExitEmaPeriod);
   g_rtExitAtrMultiplier=MathMax(0.5,MathMin(10.0,InpExitAtrMultiplier));
   g_rtTargetLeg=(int)InpTargetTpLeg;SetTargetLeg(g_rtTargetLeg);
   g_rtHalfBeLeg=ClampHalfBeLeg((int)InpHalfBeMode,g_rtTargetLeg);
   g_rtHistoricalWeeks=ClampHistWeeks(InpHistoricalWeeks>0?InpHistoricalWeeks:(int)MathCeil((double)MathMax(1,InpHistoricalDays)/7.0));
   g_rtSlDistancePct=ClampSlDistancePct(InpSlDistancePct);
   g_rtSignalTf=InpSignalTimeframe;
   g_rtDelayMin=InpBreakoutDelayMinutes;
   g_rtUseDelay=InpBreakoutDelayMinutes>0;
   g_auditRuntime=(InpAuditCsv || InpLogOnInit);
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;
   g_btSpreadPts=InpBacktestSpreadPts>0?InpBacktestSpreadPts:(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   g_lastHistBuild=0;g_histNeedsRedraw=true;
   ResetForNewNyDay();
   if(!IsTesterMode())EventSetTimer(5);
   if(!IsTesterMode()){DrawDashboard();DrawHistoricalSignals();}
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
}

void OnTimer()
{
   EnforceRiskBreach();
   bool dc=ResetForNewNyDay();BuildOrb();
   if(dc&&!IsTesterMode())DrawHistoricalSignals();
   TryOpenSignal();ManagePositions();
   if(!IsTesterMode())
   {
      OrbAudit_PositionProbe();
      OrbAudit_HistoryScan();
      OBT_Tick();
      UpdateDashboard();
   }
}

void OnTick()
{
   EnforceRiskBreach();
   ResetForNewNyDay();TryOpenSignal();ManagePositions();
   if(!IsTesterMode())UpdateDashboard();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK)return;

   bool needRedraw=false;

   if(sparam==PREFIX+"BTN_ATR"){g_rtFilterAtr=!g_rtFilterAtr;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_VOL"){g_rtFilterVol=!g_rtFilterVol;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_DAY"){g_rtFilterDay=!g_rtFilterDay;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_TIME"){g_rtTimeExit=!g_rtTimeExit;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_DISP"){g_rtDisplacement=!g_rtDisplacement;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_FVG"){CycleFvgMode();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_EXIT"){CycleExitMode();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_XSTART"){CycleExitTrailStart();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_XPARAM"){if(g_rtExitMode==ORB_EXIT_EMA_STOP)CycleExitEmaPeriod();else CycleExitAtrMultiplier();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BE"){g_rtBEOnTp1=!g_rtBEOnTp1;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_TP"){CycleTargetLeg();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_HC"){CycleHalfBeLeg();needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_2W"){SetHistoricalWeeks(2);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_5W"){SetHistoricalWeeks(5);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_10W"){SetHistoricalWeeks(10);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_AUD_20W"){SetHistoricalWeeks(20);needRedraw=true;}
   else if(sparam==PREFIX+"BTN_SL_APPLY")
   {
      string pctTxt=ObjectGetString(0,PREFIX+"EDIT_SL_PCT",OBJPROP_TEXT);
      SetSlDistancePct(StringToDouble(pctTxt));
      ObjectSetString(0,PREFIX+"EDIT_SL_PCT",OBJPROP_TEXT,DoubleToString(g_rtSlDistancePct,0));
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
   else if(sparam==PREFIX+"BTN_CLOSEALL")
   {
      CloseAllOwn();g_tradeDir=0;g_tradeOpenTime=0;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_BTF_SIGNAL"){g_btFillMode=BT_FILL_SIGNAL_CLOSE;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTF_NEXT"){g_btFillMode=BT_FILL_NEXT_BAR_OPEN;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTF_CONS"){g_btFillMode=BT_FILL_CONSERVATIVE;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_CONS"){g_btSameBarPolicy=BT_SAMEBAR_CONSERVATIVE;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_NEAR"){g_btSameBarPolicy=BT_SAMEBAR_NEAREST_OPEN;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_TP"){g_btSameBarPolicy=BT_SAMEBAR_TP_FIRST;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BTSB_SL"){g_btSameBarPolicy=BT_SAMEBAR_SL_FIRST;needRedraw=true;}
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
