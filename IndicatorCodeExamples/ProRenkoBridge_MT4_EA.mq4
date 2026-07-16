#property strict
#property version "1.00"

#define BUILD_TAG "2026-07-16.ml-audit-context"
#define EMPTY_SENTINEL 2147483647.0

input string InpTrendIndicatorName = "Asiller\\Pro Renko  System\\RenkoBlastTrend";
input int    InpTrendStateBuffer = 11; // RenkoBlastTrend direction state: debug shows +1/-1 here.
input bool   InpTrendPositiveIsBuy = true; // true: +1=BUY, -1=SELL; false reverses it.
input int    InpSignalLookbackBars = 8;
input bool   InpScanOnTick = true;
input int    InpPollSeconds = 1;
input bool   InpTradeLatestSignalOnAttach = false;
input int    InpTrendExecutionMode = 0; // 0=SH0 instant live, 1=SH1 closed signal bar, 2=SH2 delay-or-bar-close.
input int    InpTrendExecutionDelaySeconds = 3; // Used only by SH2. If signal bar closes first, execution happens immediately.
input string InpBuySignalObjectName = "PRORENKO-UP";   // compatibility only; ProRenko mode reads buffers, not objects.
input string InpSellSignalObjectName = "PRORENKO-DN";  // compatibility only; ProRenko mode reads buffers, not objects.
input string InpSignalLevelObjectName = "PRORENKO-SIGNAL LEVEL"; // unused in ProRenko buffer mode.
input string InpStopLevelObjectName = "PRORENKO-STOP LEVEL";     // unused in ProRenko buffer mode.
input string InpTargetLevel1ObjectName = "PRORENKO-TARGET LEVEL 1"; // unused in ProRenko buffer mode.
input string InpTargetLevel2ObjectName = "PRORENKO-TARGET LEVEL 2"; // unused in ProRenko buffer mode.
input string InpTargetLevel3ObjectName = "PRORENKO-TARGET LEVEL 3"; // unused in ProRenko buffer mode.
input int    InpMaxSignalAgeBars = 500;
input bool   InpAllowCalculatedFallbackLevels = true;
input bool   InpEnrichFallbackTradeWithObjectLevels = false; // ProRenko indicators do not publish SL/TP objects; keep disabled.
input bool   InpReanchorObjectLevelsToFill = false; // Object levels are unused in ProRenko buffer mode.
input bool   InpPipSlModeEnabled = false; // If true, ignore object/fallback SL geometry and build SL/TP from fixed pip risk off signal-close/entry.
input double InpPipSlPips = 100.0;
input bool   InpSymmetricRTargetsEnabled = false; // If true, keep SL distance from indicator/fallback geometry and rebuild TP1/TP2/TP3 as 1R/2R/3R.

input bool   InpDirectEnabled = true;
input bool   InpFileBridgeMt5Enabled = false; // Writes confirmed PRORENKO signals to Terminal Common\\Files for MT5 execution.
input bool   InpNativeIgnoreWindowsDefault = false; // ML shadow mode: local MT4 trades ignore Window/NoTrade/UTC event blocks. Bridge publishing still respects those guards.
input string InpFileBridgeLatestFile = "PRORENKOFileBridge_Latest.csv";
input string InpFileBridgeAuditPrefix = "PRORENKOFileBridge_Audit_";
input bool   InpFileBridgeUseCommonFiles = true;
input bool   InpActiveSignalStateEnabled = true; // Writes latest PRORENKO BUY/SELL state per symbol+TF for Atomic confluence filter.
input string InpActiveSignalStatePrefix = "ProRenko_ActiveSignal_";
input bool   InpActiveSignalUseCommonFiles = true;
input bool   InpInvertTradeMode = false; // BUY<->SELL, exact SL/TP swap after PRORENKO object/fallback geometry. Signal detection math is unchanged.
input double InpManualLot = 1.0;
input int    InpMagic = 42070519;
input bool   InpUseSymbolTimeframeMagic = true;
input int    InpSlippage = 30;
input int    InpMaxMarketEntryDriftPoints = 50; // If market is worse than trend signal close by more than this, place limit at signal price. 0=always market.
// New name intentionally avoids old .set files that may still contain InpUsePendingAtSignalOnDrift=true.
input bool   InpPendingOnDriftStartup = false;
input int    InpPendingExpiryMinutes = 30;
input int    InpBrokerStopSafetyPoints = 3;
input int    InpMaxSpreadPoints = 0;      // 0=off
input string InpAllowedWindowsGmt = "";   // empty=24/7, HH:MM-HH:MM,...
input string InpNoTradeWindowsGmt = "21:55-22:10";
input string InpUtcEventBlockTimesGmt = ""; // HH:MM[,HH:MM...] UTC centers. Blocks new entries +/- InpUtcEventBlockRadiusMinutes; latest valid signal is retried after block.
input int    InpUtcEventBlockRadiusMinutes = 5;
input int    InpTradeDisabledRetrySeconds = 30; // Recheck disabled symbols without consuming the signal event.
input bool   InpCloseOppositeOnSignal = true;
input bool   InpBlockSameDirectionOpen = true;

input int    InpRiskAtrPeriod = 14;
input double InpRiskAtrMult = 1.50;
input bool   InpUseStructuralSwingStop = true;
input int    InpSwingLookbackBars = 80;
input int    InpSwingLeftBars = 3;
input int    InpSwingRightBars = 2;
input int    InpSwingAtrPeriod = 14;
input double InpSwingMinProminenceAtr = 0.75;
input double InpSwingMinDepartureAtr = 1.00;
input double InpSwingBufferAtr = 0.20;
input double InpFinalRiskScalePct = 100.0; // Applies to both object levels and calculated fallback levels.
input int    InpTargetTpIndex = 2;        // 0=broker TP off, 1..3 full close target leg
input int    InpHalfBeTpIndex = 0;        // 0=off, 1..3 half close + SL->BE leg

input bool   InpShowDashboard = true;
input bool   InpShowLatestSignalLevels = true;
input bool   InpShowHistoricalSignalLevels = true;
input int    InpSignalLevelBars = 20;
input int    InpDashboardX = 18;
input int    InpDashboardY = 28;
input double InpDailyProfitTargetMoney = 0.0; // Chart-symbol realized PRORENKO profit target for today. 0=off; blocks MT4 execution and MT5 CSV signals until next reset day.
input double InpDailyLossTargetMoney = 0.0;   // Chart-symbol realized PRORENKO loss limit for today. 0=off; blocks MT4 execution and MT5 CSV signals until next reset day.
// === Experimental Basket Daily Target Mode ===
input bool   InpBasketModeDefault = false; // OFF=traditional SL/TP/HCBE. ON=basket daily target mode.
input double InpBasketTargetPips = 500.0; // Daily favorable pip target used for position sizing.
input double InpBasketTargetAccountPct = 0.30; // Account percent equivalent of BasketTargetPips.
input double InpBasketMaxLossPips = 1000.0; // Daily adverse pip budget. Converted to money by target ratio.
input double InpBasketCatastrophicSlPips = 2500.0; // Broker protection SL only, not normal strategy SL.
input bool   InpBasketCloseOnReverse = true;
input bool   InpBasketCloseAtSessionEnd = false; // Deprecated/ignored. Use normal trade Window/NoTrade instead.
input string InpBasketSessionEndTime = ""; // Deprecated/ignored. Basket session-end is controlled by Window/NoTrade.

input bool   InpAdvancedAccountRiskEnabled = true;
input bool   InpFtmoModeDefault = false;
input bool   InpRiskLotOnlyModeDefault = false;
input bool   InpAutoLotByRisk = true;
input double InpAccountRiskPerTradePct = 1.0;
input int    InpAccountRiskDailyAtrPeriod = 14;
input double InpAccountRiskDailyAtrExposurePct = 2.0; // Caps one trade's expected D1 ATR move, equalizing SOL/DOGE/ETH-style symbols.
input double InpMaxPortfolioRiskPct = 4.0;
input double InpDailyLossLimitPct = 0.0;  // 0=off
input double InpMaxDrawdownPct = 0.0;     // 0=off
input double InpMaxMarginUsagePct = 40.0;
input int    InpMinConcurrentTradeSlots = 5; // 0=off. Caps one trade's incremental margin so the account can still run multiple setups.
input double InpMaxSingleTradeMarginPct = 0.0; // 0=auto from slots. Example: 20 means one new trade may consume at most 20% equity margin.
input double InpInitialBalanceOverride = 10000.0;
input int    InpDayResetHourGmt = 0;
input bool   InpRiskScopeByMagic = true;
input bool   InpLiquidateOnBreach = false;
input int    InpRiskAuditSeconds = 0; // 0=off. Periodic risk snapshots are telemetry; trade events still audit when enabled.

input bool   InpEnableAudit = false;
input int    InpPositionProbeSeconds = 0; // 0=off. Keep audit compact; closed-trade lifecycle rows carry MFE/MAE.
input int    InpLifecycleAuditSeconds = 10;

string   g_prefix;
bool     g_eaEnabled;
bool     g_collapsed = false;
double   g_lotRuntime;
int      g_maxSpreadRuntime;
double   g_finalScaleRuntime;
int      g_targetTpRuntime;
int      g_halfTpRuntime;
double   g_targetRRuntime;
double   g_halfRRuntime;
bool     g_pendingOnDriftRuntime;
bool     g_fileBridgeMt5Runtime;
bool     g_nativeIgnoreWindowsRuntime;
bool     g_pipSlModeRuntime;
double   g_pipSlPipsRuntime;
bool     g_symmetricRTargetsRuntime;
double   g_dailyProfitTargetRuntime;
double   g_dailyLossTargetRuntime;
double   g_riskPctRuntime;
bool     g_auditRuntime;
bool     g_ftmoMode;
bool     g_riskLotOnlyMode;
bool     g_invertMode;
bool     g_basketModeRuntime;
double   g_basketTargetPipsRuntime;
double   g_basketTargetPctRuntime;
double   g_basketMaxLossPipsRuntime;
double   g_basketCatastrophicSlPipsRuntime;
bool     g_basketCloseOnReverseRuntime;
bool     g_basketCloseAtSessionEndRuntime;
string   g_basketSessionEndTimeRuntime;
bool     g_trendTradeRuntime;
string   g_lastTrendEventId = "";
string   g_allowedWindowsRuntime;
string   g_noTradeWindowsRuntime;
string   g_utcEventBlockTimesRuntime;
int      g_utcEventBlockRadiusRuntime;
string   g_lastEventId = "";
string   g_lastSignalDir = "-";
datetime g_lastSignalTime = 0;
double   g_lastSignalPrice = 0.0;
datetime g_lastScanTs = 0;
int      g_trendExecModeRuntime;
int      g_trendExecDelayRuntime;
string   g_pendingTrendEventId = "";
datetime g_pendingTrendFirstSeen = 0;
datetime g_pendingTrendBarTime = 0;
datetime g_trendExecutedBarTime = 0;
string   g_trendExecutedBarEventId = "";
string   g_loggedSh1WaitEventId = "";
string   g_loggedSh2WaitEventId = "";
datetime g_lastRiskAuditTs = 0;
datetime g_lastProbeTs = 0;
datetime g_lastLifecycleAuditTs = 0;
string   g_mlPreviousSignalDir = "-";
datetime g_mlPreviousSignalTime = 0;
string   g_mlTradeIndexDayKey = "";
int      g_mlTradeIndexOfDay = 0;
datetime g_mlFlipTimes[128];
int      g_mlFlipWriteIdx = 0;
datetime g_nextTradeDisabledRetryTs = 0;
bool     g_lastGeometryUsedFallback = false;
bool     g_basketWindowStateInitialized = false;
bool     g_basketWindowEligibleLast = false;
string   g_lastNativeShadowBootstrapEventId = "";
string   g_eventBlockPendingEventId = "";
string   g_eventBlockPendingDir = "";
datetime g_eventBlockPendingSignalTime = 0;
datetime g_eventBlockPendingFirstSeen = 0;
double   g_eventBlockPendingSignalPrice = 0.0;
int      g_eventBlockPendingShift = -1;
int      g_eventBlockPendingBuffer = -1;

int OnInit()
{
   g_prefix = "PRORENKO_" + IntegerToString((int)ChartID()) + "_";
   g_eaEnabled = InpDirectEnabled;
   g_lotRuntime = InpManualLot;
   g_maxSpreadRuntime = InpMaxSpreadPoints;
   g_finalScaleRuntime = MathMax(10.0, MathMin(200.0, InpFinalRiskScalePct));
   g_targetTpRuntime = MathMax(0, MathMin(3, InpTargetTpIndex));
   g_halfTpRuntime = MathMax(0, MathMin(3, InpHalfBeTpIndex));
   g_targetRRuntime = NormalizeDouble(MathMax(0.1, InpTargetTpIndex), 1);
   g_halfRRuntime = NormalizeDouble(MathMax(0.0, InpHalfBeTpIndex), 1);
   g_pendingOnDriftRuntime = InpPendingOnDriftStartup;
   g_fileBridgeMt5Runtime = InpFileBridgeMt5Enabled;
   g_nativeIgnoreWindowsRuntime = InpNativeIgnoreWindowsDefault;
   g_pipSlModeRuntime = InpPipSlModeEnabled;
   g_pipSlPipsRuntime = MathMax(0.0, InpPipSlPips);
   g_symmetricRTargetsRuntime = InpSymmetricRTargetsEnabled;
   g_dailyProfitTargetRuntime = MathMax(0.0, InpDailyProfitTargetMoney);
   g_dailyLossTargetRuntime = MathMax(0.0, InpDailyLossTargetMoney);
   g_riskPctRuntime = MathMax(0.0, InpAccountRiskPerTradePct);
   g_invertMode = InpInvertTradeMode;
   g_basketModeRuntime = InpBasketModeDefault;
   g_basketTargetPipsRuntime = MathMax(0.0, InpBasketTargetPips);
   g_basketTargetPctRuntime = MathMax(0.0, InpBasketTargetAccountPct);
   g_basketMaxLossPipsRuntime = MathMax(0.0, InpBasketMaxLossPips);
   g_basketCatastrophicSlPipsRuntime = MathMax(0.0, InpBasketCatastrophicSlPips);
   g_basketCloseOnReverseRuntime = InpBasketCloseOnReverse;
   g_basketCloseAtSessionEndRuntime = false;
   g_basketSessionEndTimeRuntime = "";
   g_trendTradeRuntime = true;
   g_trendExecModeRuntime = MathMax(0, MathMin(2, InpTrendExecutionMode));
   g_trendExecDelayRuntime = MathMax(0, InpTrendExecutionDelaySeconds);
   g_auditRuntime = InpEnableAudit;
   g_ftmoMode = InpFtmoModeDefault;
   g_riskLotOnlyMode = (!g_ftmoMode && InpRiskLotOnlyModeDefault);
   g_allowedWindowsRuntime = InpAllowedWindowsGmt;
   g_noTradeWindowsRuntime = InpNoTradeWindowsGmt;
   g_utcEventBlockTimesRuntime = InpUtcEventBlockTimesGmt;
   g_utcEventBlockRadiusRuntime = MathMax(0, MathMin(60, InpUtcEventBlockRadiusMinutes));
   g_basketWindowEligibleLast = BasketWindowEligibleNow();
   g_basketWindowStateInitialized = true;
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   EventSetTimer(MathMax(1, InpPollSeconds));

   CleanupLegacyInfiniteLevelLines();
   if(InpShowDashboard) DashboardCreate();
   Audit("init", "", 0, "", 0, 0, 0, 0, "build=" + BUILD_TAG + " trend_indicator=" + InpTrendIndicatorName + " trend_state_buffer=" + IntegerToString(InpTrendStateBuffer) + " positive_is_buy=" + (InpTrendPositiveIsBuy ? "true" : "false") + " mt5_bridge=" + (g_fileBridgeMt5Runtime ? "true" : "false") + " native_ignore_windows=" + (g_nativeIgnoreWindowsRuntime ? "true" : "false") + " risk_pct=" + DoubleToString(g_riskPctRuntime,2) + " invert=" + (g_invertMode ? "true" : "false") + " pip_sl=" + (g_pipSlModeRuntime ? "true" : "false") + " pip_sl_pips=" + DoubleToString(g_pipSlPipsRuntime, 2) + " sym_r=" + (g_symmetricRTargetsRuntime ? "true" : "false") + " exec_mode_startup=" + TrendExecModeLabel() + " exec_delay_sec=" + IntegerToString(g_trendExecDelayRuntime) + " daily_profit_target=" + DoubleToString(g_dailyProfitTargetRuntime, 2) + " daily_loss_target=" + DoubleToString(g_dailyLossTargetRuntime, 2) + " basket_mode=" + (g_basketModeRuntime ? "true" : "false") + " basket_target_pips=" + DoubleToString(g_basketTargetPipsRuntime, 1) + " basket_target_pct=" + DoubleToString(g_basketTargetPctRuntime, 2) + " basket_max_loss_pips=" + DoubleToString(g_basketMaxLossPipsRuntime, 1) + " basket_cat_sl_pips=" + DoubleToString(g_basketCatastrophicSlPipsRuntime, 1) + " utc_event_block='" + g_utcEventBlockTimesRuntime + "' radius_min=" + IntegerToString(g_utcEventBlockRadiusRuntime), 0, "");
   RiskAudit("init", "build=" + BUILD_TAG + " pending_on_drift=" + (g_pendingOnDriftRuntime ? "true" : "false"));
   FileBridgeWriteInitMarker();

   if(!InpTradeLatestSignalOnAttach)
   {
      string dir, eid; int sh, buf; double px; datetime bt;
      if(FindLatestTrendSignal(dir, sh, buf, px, bt, eid))
      {
         g_lastEventId = eid;
         g_lastTrendEventId = eid;
         Audit("startup_baseline_trend", eid, 0, dir, 0, px, 0, 0, "shift=" + IntegerToString(sh) + " buffer=" + IntegerToString(buf), 0, "old trend signal ignored on attach");
         if(g_eaEnabled && InpCloseOppositeOnSignal && (dir == "BUY" || dir == "SELL"))
         {
            int baselineType = (dir == "BUY") ? OP_BUY : OP_SELL;
            CloseOpposite(baselineType, eid + "|attach_reconcile");
         }
      }
   }
   DrawHistoricalSignalLevels("init");
   Print("ProRenkoBridge BUILD=", BUILD_TAG, " trend=", InpTrendIndicatorName, " trendStateBuffer=", InpTrendStateBuffer, " positiveIsBuy=", (InpTrendPositiveIsBuy ? "true" : "false"), " pendingOnDrift=", (g_pendingOnDriftRuntime ? "true" : "false"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   DeleteTradeLevels();
   DeleteLatestSignalLevels();
   DeleteHistoricalSignalLevels();
   DeleteAllCalculatedFallbackLevels();
   Audit("deinit", "", 0, "", 0, 0, 0, 0, "reason=" + IntegerToString(reason), 0, "");
}

void OnTick()
{
   if(InpScanOnTick) ProcessSignals("tick");
   ManagePositions();
   MaybeLifecycleAudit();
   if(InpShowDashboard) DashboardUpdate();
}

void OnTimer()
{
   ProcessSignals("timer");
   ManagePositions();
   MaybeLifecycleAudit();
   MaybeProbe();
   MaybeRiskAudit();
   if(InpShowDashboard) DashboardUpdate();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DRAG)
   {
      string uname = StringUpperCopy(sparam);
      if(StringFind(uname, StringUpperCopy(InpBuySignalObjectName)) >= 0 || StringFind(uname, StringUpperCopy(InpSellSignalObjectName)) >= 0)
         ProcessSignals("object_event");
      return;
   }
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT) return;
   if(sparam == Obj("toggle"))
   {
      g_eaEnabled = !g_eaEnabled;
      Audit("dashboard_toggle", "", 0, "", 0, 0, 0, 0, g_eaEnabled ? "enabled" : "disabled", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("collapse"))
   {
      g_collapsed = !g_collapsed;
      DashboardCreate();
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("drift"))
   {
      g_pendingOnDriftRuntime = !g_pendingOnDriftRuntime;
      Audit("dashboard_drift_toggle", "", 0, "", 0, 0, 0, 0, g_pendingOnDriftRuntime ? "pending_on_drift=true" : "pending_on_drift=false", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("mt5pub"))
   {
      g_fileBridgeMt5Runtime = !g_fileBridgeMt5Runtime;
      Print("ProRenkoBridge MT5 file bridge ", g_fileBridgeMt5Runtime ? "enabled" : "disabled");
      if(g_fileBridgeMt5Runtime)
         FileBridgeWriteInitMarker();
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("native24"))
   {
      g_nativeIgnoreWindowsRuntime = !g_nativeIgnoreWindowsRuntime;
      Audit("dashboard_native_window_toggle", "", 0, "", 0, 0, 0, 0, g_nativeIgnoreWindowsRuntime ? "NATIVE_ML_24_7_ON" : "NATIVE_ML_24_7_OFF", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("audit"))
   {
      g_auditRuntime = !g_auditRuntime;
      Print("ProRenkoBridge audit logging ", g_auditRuntime ? "enabled" : "disabled");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("ftmo"))
   {
      g_ftmoMode = !g_ftmoMode;
      if(g_ftmoMode) g_riskLotOnlyMode = false;
      Audit("dashboard_ftmo_toggle", "", 0, "", 0, 0, 0, 0, g_ftmoMode ? "FTMO_ON" : "FTMO_OFF", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("risklot"))
   {
      g_riskLotOnlyMode = !g_riskLotOnlyMode;
      if(g_riskLotOnlyMode) g_ftmoMode = false;
      Audit("dashboard_risklot_toggle", "", 0, "", 0, 0, 0, 0, g_riskLotOnlyMode ? "RISKLOT_ON" : "RISKLOT_OFF", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("invert"))
   {
      g_invertMode = !g_invertMode;
      Audit("dashboard_invert_toggle", "", 0, "", 0, 0, 0, 0, g_invertMode ? "INVERT_ON" : "INVERT_OFF", 0, "");
      DrawLatestSignalLevels("invert_toggle");
      DrawHistoricalSignalLevels("invert_toggle");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("trendmode"))
   {
      g_trendTradeRuntime = !g_trendTradeRuntime;
      Audit("dashboard_trend_mode_toggle", "", 0, "", 0, 0, 0, 0, g_trendTradeRuntime ? "TREND_MODE_ON" : "TREND_MODE_OFF", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("execmode"))
   {
      g_trendExecModeRuntime = (MathMax(0, MathMin(2, g_trendExecModeRuntime)) + 1) % 3;
      g_pendingTrendEventId = "";
      g_pendingTrendFirstSeen = 0;
      g_pendingTrendBarTime = 0;
      g_trendExecutedBarTime = 0;
      g_trendExecutedBarEventId = "";
      Audit("dashboard_exec_mode_toggle", "", 0, "", 0, 0, 0, 0, "trend_exec_mode=" + TrendExecModeLabel() + " delay_sec=" + IntegerToString(g_trendExecDelayRuntime), 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("basketmode"))
   {
      g_basketModeRuntime = !g_basketModeRuntime;
      // Enabling basket mode while already inside the window is an operational
      // window entry: bootstrap the current trend on the next scan.
      if(g_basketModeRuntime)
      {
         g_basketWindowEligibleLast = false;
         g_basketWindowStateInitialized = true;
      }
      Audit("dashboard_basket_mode_toggle", "", 0, "", 0, 0, 0, 0, g_basketModeRuntime ? "BASKET_ON" : "BASKET_OFF", 0, "");
      DrawLatestSignalLevels("basket_mode_toggle");
      DrawHistoricalSignalLevels("basket_mode_toggle");
      DrawTradeLevels();
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("basketrev"))
   {
      g_basketCloseOnReverseRuntime = !g_basketCloseOnReverseRuntime;
      Audit("dashboard_basket_reverse_toggle", "", 0, "", 0, 0, 0, 0, g_basketCloseOnReverseRuntime ? "BASKET_REVERSE_ON" : "BASKET_REVERSE_OFF", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("pipmode"))
   {
      g_pipSlModeRuntime = !g_pipSlModeRuntime;
      if(g_pipSlModeRuntime) g_symmetricRTargetsRuntime = false;
      Print("ProRenkoBridge pip SL mode ", g_pipSlModeRuntime ? "enabled" : "disabled", " pips=", DoubleToString(g_pipSlPipsRuntime, 2));
      DrawLatestSignalLevels("pip_sl_toggle");
      DrawHistoricalSignalLevels("pip_sl_toggle");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("riskapply"))
   {
      ApplyRiskInputAndPublish();
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("symr"))
   {
      g_symmetricRTargetsRuntime = !g_symmetricRTargetsRuntime;
      if(g_symmetricRTargetsRuntime) g_pipSlModeRuntime = false;
      Audit("dashboard_symr_toggle", "", 0, "", 0, 0, 0, 0, g_symmetricRTargetsRuntime ? "SYM_R_ON" : "SYM_R_OFF", 0, "");
      DrawLatestSignalLevels("sym_r_toggle");
      DrawHistoricalSignalLevels("sym_r_toggle");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("apply") || sparam == Obj("basketapply") || sparam == Obj("eventapply") || id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      ApplyDashboardInputs();
      DashboardUpdate();
   }
}

string Obj(string name) { return g_prefix + name; }

void ProcessSignals(string reason)
{
   datetime now = TimeCurrent();
   if(reason == "timer" && now == g_lastScanTs) return;
   g_lastScanTs = now;

   if(MaybeExecuteEventBlockPending(reason))
      return;
   MaybeBootstrapBasketWindow(reason);
   MaybeBootstrapBasketNativeShadow(reason);

   string dir, eid; int sh, buf; double sigPx; datetime barTime;
   if(g_trendTradeRuntime && FindLatestTrendSignal(dir, sh, buf, sigPx, barTime, eid))
      ProcessSignalCandidate("trend", dir, eid, sh, buf, sigPx, barTime, g_lastTrendEventId, reason);
}

bool BasketWindowEligibleNow()
{
   datetime now = TimeGMT();
   return IsInAllowedWindow(now, g_allowedWindowsRuntime)
       && !IsInNoTradeWindow(now, g_noTradeWindowsRuntime)
       && !IsInUtcEventBlock(now, g_utcEventBlockTimesRuntime, g_utcEventBlockRadiusRuntime);
}

bool EventBlockTradeWindowEligibleNow()
{
   datetime now = TimeGMT();
   return IsInAllowedWindow(now, g_allowedWindowsRuntime)
       && !IsInNoTradeWindow(now, g_noTradeWindowsRuntime)
       && !IsInUtcEventBlock(now, g_utcEventBlockTimesRuntime, g_utcEventBlockRadiusRuntime);
}

void StoreEventBlockPending(string eventId, string dir, double signalPx, int shift, int buffer, datetime signalTime, string reason)
{
   if(eventId == "" || dir == "") return;
   if(g_eventBlockPendingEventId == eventId) return;
   g_eventBlockPendingEventId = eventId;
   g_eventBlockPendingDir = dir;
   g_eventBlockPendingSignalTime = signalTime > 0 ? signalTime : g_lastSignalTime;
   g_eventBlockPendingFirstSeen = TimeCurrent();
   g_eventBlockPendingSignalPrice = signalPx;
   g_eventBlockPendingShift = shift;
   g_eventBlockPendingBuffer = buffer;
   Audit("utc_event_block_deferred", eventId, 0, dir, 0, signalPx, 0, 0,
         "reason=" + reason + " utc_event_block='" + g_utcEventBlockTimesRuntime + "' radius_min=" + IntegerToString(g_utcEventBlockRadiusRuntime),
         0, "will_retry_after_event_block_if_signal_still_current");
}

void ClearEventBlockPending()
{
   g_eventBlockPendingEventId = "";
   g_eventBlockPendingDir = "";
   g_eventBlockPendingSignalTime = 0;
   g_eventBlockPendingFirstSeen = 0;
   g_eventBlockPendingSignalPrice = 0.0;
   g_eventBlockPendingShift = -1;
   g_eventBlockPendingBuffer = -1;
}

bool MaybeExecuteEventBlockPending(string reason)
{
   if(g_eventBlockPendingEventId == "") return false;
   if(!EventBlockTradeWindowEligibleNow()) return false;

   string curDir = "", curEid = "";
   int curShift = -1, curBuffer = -1;
   double curPrice = 0.0;
   datetime curBarTime = 0;
   bool stillCurrent = FindLatestTrendSignal(curDir, curShift, curBuffer, curPrice, curBarTime, curEid);
   if(!stillCurrent || curDir != g_eventBlockPendingDir || curEid != g_eventBlockPendingEventId)
   {
      Audit("utc_event_block_deferred_cancelled", g_eventBlockPendingEventId, 0, g_eventBlockPendingDir, 0, g_eventBlockPendingSignalPrice, 0, 0,
            "reason=" + reason + " current_dir=" + curDir + " current_event=" + curEid,
            0, "signal_changed_or_missing_before_event_block_ended");
      ClearEventBlockPending();
      return false;
   }

   RefreshRates();
   double liveEntry = (g_eventBlockPendingDir == "BUY") ? Ask : Bid;
   if(liveEntry <= 0.0)
      liveEntry = g_eventBlockPendingSignalPrice;
   string releaseEventId = g_eventBlockPendingEventId + "|utc_release|" + IntegerToString((int)(TimeGMT() - (TimeGMT() % 60)));
   string dir = g_eventBlockPendingDir;
   int buffer = curBuffer;
   datetime sigTime = g_eventBlockPendingSignalTime;
   int age = (g_eventBlockPendingFirstSeen > 0 ? (int)(TimeCurrent() - g_eventBlockPendingFirstSeen) : -1);

   MlRegisterSignal(dir, sigTime > 0 ? sigTime : curBarTime);
   g_lastSignalDir = dir;
   g_lastSignalTime = sigTime > 0 ? sigTime : curBarTime;
   g_lastSignalPrice = NormalizeDouble(liveEntry, Digits);
   g_lastEventId = releaseEventId;
   ActiveSignalStateWrite(dir, releaseEventId, g_lastSignalPrice, g_lastSignalTime, reason + "_utc_event_release");
   Audit("utc_event_block_release_execute", releaseEventId, 0, dir, 0, g_lastSignalPrice, 0, 0,
         "source_event=" + g_eventBlockPendingEventId + " age_sec=" + IntegerToString(age) + " reason=" + reason,
         0, "event_block_ended_current_signal_opened_at_live_price");
   ClearEventBlockPending();
   ExecuteSignal(dir, releaseEventId, g_lastSignalPrice, 0, buffer);
   return true;
}

void MaybeBootstrapBasketWindow(string reason)
{
   bool eligible = BasketWindowEligibleNow();
   if(!g_basketWindowStateInitialized)
   {
      g_basketWindowEligibleLast = eligible;
      g_basketWindowStateInitialized = true;
      return;
   }

   bool entered = (eligible && !g_basketWindowEligibleLast);
   g_basketWindowEligibleLast = eligible;
   if(!entered || !g_basketModeRuntime || !g_trendTradeRuntime)
      return;

   string dir = "";
   double raw = 0.0;
   int buffer = -1;
   if(!TrendStateAt(0, dir, raw, buffer))
   {
      Audit("basket_window_bootstrap_no_state", "", 0, "", 0, 0, 0, 0,
            "reason=" + reason + " allowed='" + g_allowedWindowsRuntime + "' no_trade='" + g_noTradeWindowsRuntime + "'",
            0, "window_entered_but_current_trend_unavailable");
      return;
   }

   RefreshRates();
   double liveEntry = (dir == "BUY") ? Ask : Bid;
   if(liveEntry <= 0.0)
   {
      Audit("basket_window_bootstrap_no_price", "", 0, dir, 0, 0, 0, 0,
            "reason=" + reason + " buffer=" + IntegerToString(buffer),
            0, "window_entered_but_live_price_unavailable");
      return;
   }

   datetime nowGmt = TimeGMT();
   datetime windowMinute = nowGmt - (nowGmt % 60);
   datetime barTime = iTime(Symbol(), Period(), 0);
   string eventId = Symbol() + "|" + IntegerToString(Period()) + "|prorenko_basket_window|" + dir + "|"
                  + IntegerToString((int)windowMinute) + "|buf=" + IntegerToString(buffer);

   MlRegisterSignal(dir, (barTime > 0) ? barTime : TimeCurrent());
   g_lastSignalDir = dir;
   g_lastSignalTime = (barTime > 0) ? barTime : TimeCurrent();
   g_lastSignalPrice = NormalizeDouble(liveEntry, Digits);
   g_lastEventId = eventId;
   ActiveSignalStateWrite(dir, eventId, g_lastSignalPrice, g_lastSignalTime, reason + "_basket_window_bootstrap");
   Audit("basket_window_bootstrap", eventId, 0, dir, 0, g_lastSignalPrice, 0, 0,
         "reason=" + reason + " buffer=" + IntegerToString(buffer)
         + " raw=" + DoubleToString(raw, 2)
         + " allowed='" + g_allowedWindowsRuntime + "' no_trade='" + g_noTradeWindowsRuntime + "'",
         0, "current_trend_opened_without_waiting_for_new_flip");

   // Use live price intentionally: an older trend state must not create a
   // pending-at-historical-price order when the trading window opens.
   ExecuteSignal(dir, eventId, g_lastSignalPrice, 0, buffer);
}

void MaybeBootstrapBasketNativeShadow(string reason)
{
   if(!BasketNativeSignalShadowMode() || !g_trendTradeRuntime)
      return;

   string dir = "";
   double raw = 0.0;
   int buffer = -1;
   if(!TrendStateAt(0, dir, raw, buffer))
      return;

   string effectiveDir = dir;
   if(g_invertMode)
      effectiveDir = (effectiveDir == "BUY") ? "SELL" : "BUY";
   int effectiveType = (effectiveDir == "BUY") ? OP_BUY : OP_SELL;
   if(HasOpenBasketDirection(effectiveType))
      return;

   datetime nowGmt = TimeGMT();
   datetime minute = nowGmt - (nowGmt % 60);
   string eventId = Symbol() + "|" + IntegerToString(Period()) + "|prorenko_nat24_shadow|" + dir + "|"
                  + IntegerToString((int)minute) + "|buf=" + IntegerToString(buffer);
   if(eventId == g_lastNativeShadowBootstrapEventId)
      return;

   RefreshRates();
   double liveEntry = (dir == "BUY") ? Ask : Bid;
   if(liveEntry <= 0.0)
      return;

   datetime barTime = iTime(Symbol(), Period(), 0);
   MlRegisterSignal(dir, (barTime > 0) ? barTime : TimeCurrent());
   g_lastSignalDir = dir;
   g_lastSignalTime = (barTime > 0) ? barTime : TimeCurrent();
   g_lastSignalPrice = NormalizeDouble(liveEntry, Digits);
   g_lastEventId = eventId;
   g_lastNativeShadowBootstrapEventId = eventId;
   ActiveSignalStateWrite(dir, eventId, g_lastSignalPrice, g_lastSignalTime, reason + "_nat24_shadow_bootstrap");
   Audit("basket_nat24_shadow_bootstrap", eventId, 0, dir, 0, g_lastSignalPrice, 0, 0,
         "reason=" + reason + " effective_dir=" + effectiveDir + " buffer=" + IntegerToString(buffer)
         + " raw=" + DoubleToString(raw, 2),
         0, "current_trend_signal_to_signal_native");

   ExecuteSignal(dir, eventId, g_lastSignalPrice, 0, buffer);
}
void ProcessSignalCandidate(string source, string dir, string eid, int sh, int buf, double sigPx, datetime barTime, string &lastSourceEventId, string reason)
{
   if(eid == lastSourceEventId)
      return;

   string waitDetail = "";
   if(!CanExecuteTrendSignalNow(source, eid, sh, barTime, dir, sigPx, reason, waitDetail))
      return;

   MlRegisterSignal(dir, barTime);
   g_lastSignalDir = dir;
   g_lastSignalTime = barTime;
   g_lastSignalPrice = sigPx;
   ActiveSignalStateWrite(dir, eid, sigPx, barTime, reason + "_" + source);
   DrawLatestSignalLevels(reason + "_" + source);
   DrawHistoricalSignalLevels(reason + "_" + source);
   lastSourceEventId = eid;
   g_lastEventId = eid;
   if(source == "trend")
   {
      if(MathMax(0, MathMin(2, g_trendExecModeRuntime)) == 2)
      {
         g_trendExecutedBarTime = barTime;
         g_trendExecutedBarEventId = eid;
      }
      g_pendingTrendEventId = "";
      g_pendingTrendFirstSeen = 0;
      g_pendingTrendBarTime = 0;
   }

   RefreshRates();
   double liveBid = Bid;
   double liveAsk = Ask;
   int spreadNow = CurrentSpreadPoints();
   Audit("signal_detected", eid, 0, dir, 0, sigPx, 0, 0,
         "source=" + source + " reason=" + reason + " shift=" + IntegerToString(sh) + " buffer=" + IntegerToString(buf) +
         " bar=" + TimeToString(barTime, TIME_DATE|TIME_SECONDS) + " bid=" + PriceText(liveBid) + " ask=" + PriceText(liveAsk) +
         " spread_points=" + IntegerToString(spreadNow) + " exec_mode=" + TrendExecModeLabel() + waitDetail, 0, "");
   ExecuteSignal(dir, eid, sigPx, sh, buf);
}

bool CanExecuteTrendSignalNow(string source, string eid, int sh, datetime barTime, string dir, double sigPx, string reason, string &detail)
{
   detail = "";
   if(source != "trend") return true;

   int mode = MathMax(0, MathMin(2, g_trendExecModeRuntime));
   if(mode == 0)
   {
      g_pendingTrendEventId = "";
      g_pendingTrendFirstSeen = 0;
      g_pendingTrendBarTime = 0;
      detail = " exec=SH0";
      return true;
   }

   if(sh > 0)
   {
      bool wasPending = (eid == g_pendingTrendEventId || barTime == g_pendingTrendBarTime);
      detail = " exec=" + TrendExecModeLabel() + " closed_bar=1 pending=" + (wasPending ? "true" : "false") + " live_lock_bypass=1";
      return true;
   }

   if(mode == 2 && g_trendExecutedBarTime == barTime && eid != g_trendExecutedBarEventId)
   {
      Audit("signal_blocked_sh2_bar_lock", eid, 0, dir, 0, sigPx, 0, 0,
            "source=" + source + " reason=" + reason + " shift=" + IntegerToString(sh) + " bar=" + TimeToString(barTime, TIME_DATE|TIME_SECONDS) +
            " already_executed_event=" + g_trendExecutedBarEventId, 0, "one_sh2_execution_per_live_bar");
      return false;
   }

   datetime now = TimeCurrent();
   if(eid != g_pendingTrendEventId)
   {
      g_pendingTrendEventId = eid;
      g_pendingTrendFirstSeen = now;
      g_pendingTrendBarTime = barTime;
      g_loggedSh1WaitEventId = "";
      g_loggedSh2WaitEventId = "";
      Audit(mode == 1 ? "signal_pending_sh1_close" : "signal_pending_sh2_delay", eid, 0, dir, 0, sigPx, 0, 0,
            "source=" + source + " reason=" + reason + " shift=0 bar=" + TimeToString(barTime, TIME_DATE|TIME_SECONDS) +
            " exec_mode=" + TrendExecModeLabel() + " delay_sec=" + IntegerToString(g_trendExecDelayRuntime), 0, "live_signal_seen_no_trade_yet");
      return false;
   }

   if(mode == 1)
   {
      if(g_loggedSh1WaitEventId != eid)
      {
         g_loggedSh1WaitEventId = eid;
         Audit("signal_waiting_sh1_close", eid, 0, dir, 0, sigPx, 0, 0,
               "source=" + source + " reason=" + reason + " shift=0 bar=" + TimeToString(barTime, TIME_DATE|TIME_SECONDS), 0, "wait_bar_close_once");
      }
      return false;
   }

   int stableFor = (int)(now - g_pendingTrendFirstSeen);
   if(stableFor < g_trendExecDelayRuntime)
   {
      if(g_loggedSh2WaitEventId != eid)
      {
         g_loggedSh2WaitEventId = eid;
         Audit("signal_waiting_sh2_delay", eid, 0, dir, 0, sigPx, 0, 0,
               "source=" + source + " stable_for=" + IntegerToString(stableFor) + " required=" + IntegerToString(g_trendExecDelayRuntime) +
               " bar=" + TimeToString(barTime, TIME_DATE|TIME_SECONDS), 0, "wait_delay_or_bar_close_once");
      }
      return false;
   }

   detail = " exec=SH2 delay_done stable_for=" + IntegerToString(stableFor);
   return true;
}

string TrendExecModeLabel()
{
   int mode = MathMax(0, MathMin(2, g_trendExecModeRuntime));
   if(mode == 1) return "SH1";
   if(mode == 2) return "SH2";
   return "SH0";
}
color TrendExecModeColor()
{
   int mode = MathMax(0, MathMin(2, g_trendExecModeRuntime));
   if(mode == 1) return clrSaddleBrown;
   if(mode == 2) return clrSteelBlue;
   return clrDarkGreen;
}

bool TrendStateAt(int shift, string &dir, double &raw, int &buffer)
{
   dir = "";
   raw = 0.0;
   buffer = InpTrendStateBuffer;
   double state = ReadTrendBuffer(InpTrendStateBuffer, shift);
   if(!IsSignalValue(state)) return false;
   raw = state;
   if(state > 0.0)
      dir = InpTrendPositiveIsBuy ? "BUY" : "SELL";
   else if(state < 0.0)
      dir = InpTrendPositiveIsBuy ? "SELL" : "BUY";
   else
      return false;
   return true;
}

bool FindLatestTrendSignal(string &dir, int &shift, int &buffer, double &price, datetime &barTime, string &eventId)
{
   bool found = false;
   datetime bestTime = 0;
   string bestDir = "";
   double bestRaw = 0.0;
   int bestShift = -1;
   int bestBuffer = -1;

   int maxBars = MathMin(InpMaxSignalAgeBars, Bars - 3);
   for(int sh = 0; sh <= maxBars; sh++)
   {
      string curDir, prevDir;
      double curRaw = 0.0, prevRaw = 0.0;
      int curBuf = -1, prevBuf = -1;
      if(!TrendStateAt(sh, curDir, curRaw, curBuf)) continue;
      bool prevState = TrendStateAt(sh + 1, prevDir, prevRaw, prevBuf);
      if(prevState && prevDir == curDir) continue; // continuous trend line, not a new signal
      datetime t = Time[sh];
      if(t <= 0) continue;
      if(!found || t > bestTime)
      {
         found = true;
         bestTime = t;
         bestDir = curDir;
         bestRaw = curRaw;
         bestShift = sh;
         bestBuffer = curBuf;
      }
   }

   if(!found) return false;
   dir = bestDir;
   shift = bestShift;
   buffer = bestBuffer;
   barTime = bestTime;
   price = SignalEntryPrice(bestDir, bestShift, bestRaw);
   eventId = Symbol() + "|" + IntegerToString(Period()) + "|prorenko_trend|" + dir + "|" + IntegerToString((int)barTime) +
             "|buf=" + IntegerToString(buffer) + "|raw=" + DoubleToString(bestRaw, Digits);
   return true;
}
double SignalEntryPrice(string dir, int shift, double rawValue)
{
   int sh = MathMax(0, MathMin(shift, Bars - 1));
   if(sh == 0)
   {
      RefreshRates();
      double px = (dir == "BUY") ? Ask : Bid;
      if(px > 0.0) return NormalizeDouble(px, Digits);
   }

   double c = iClose(Symbol(), Period(), sh);
   if(c > 0.0) return NormalizeDouble(c, Digits);
   if(rawValue > 0.0 && rawValue < EMPTY_SENTINEL - 1.0) return NormalizeDouble(rawValue, Digits);
   RefreshRates();
   return NormalizeDouble((dir == "BUY") ? Ask : Bid, Digits);
}

double ReadTrendBuffer(int buffer, int shift)
{
   ResetLastError();
   return iCustom(Symbol(), Period(), InpTrendIndicatorName, buffer, shift);
}
bool IsSignalValue(double v)
{
   if(v == EMPTY_VALUE) return false;
   if(MathAbs(v - EMPTY_SENTINEL) < 0.1) return false;
   if(MathAbs(v) < 0.0000001) return false;
   if(v < -100000000.0 || v > 100000000.0) return false;
   return true;
}

string StringUpperCopy(string s)
{
   string out = s;
   StringToUpper(out);
   return out;
}

bool FindLevelPrice(string wantedName, double &price, string &detail)
{
   price = 0.0;
   detail = "";
   if(ObjectFind(0, wantedName) >= 0)
   {
      double p = ObjectGetDouble(0, wantedName, OBJPROP_PRICE1);
      if(p > 0.0)
      {
         price = p;
         detail = wantedName + ":" + PriceText(p);
         return true;
      }
   }

   string wanted = StringUpperCopy(wantedName);
   string fallbackName = "";
   double fallbackPrice = 0.0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, -1, -1);
      string uname = StringUpperCopy(name);
      if(StringFind(uname, wanted) < 0) continue;
      double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE1);
      if(p2 <= 0.0) continue;
      int type = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(type == OBJ_TREND || type == OBJ_HLINE)
      {
         price = p2;
         detail = name + ":" + PriceText(p2);
         return true;
      }
      if(fallbackPrice <= 0.0)
      {
         fallbackName = name;
         fallbackPrice = p2;
      }
   }
   if(fallbackPrice > 0.0)
   {
      price = fallbackPrice;
      detail = fallbackName + ":" + PriceText(fallbackPrice);
      return true;
   }
   return false;
}

double TickSizePrice()
{
   double tick = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tick <= 0.0) tick = Point;
   if(tick < Point * 0.5) tick = Point;
   return tick;
}

double NormalizePriceToTick(double price)
{
   if(price <= 0.0) return 0.0;
   double tick = TickSizePrice();
   if(tick <= 0.0) tick = Point;
   return NormalizeDouble(MathRound(price / tick) * tick, Digits);
}

double BrokerMinStopDistance()
{
   double stop = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double safety = MathMax(0, InpBrokerStopSafetyPoints) * Point;
   return MathMax(MathMax(stop, freeze) + safety, MathMax(Point, TickSizePrice()));
}

bool ValidateDirectionLevels(int logicalType, double entry, double sl, double tp, string &detail)
{
   if(logicalType == OP_BUY)
   {
      if(sl > 0.0 && sl >= entry)
      {
         detail = "buy_sl_not_below_entry entry=" + PriceText(entry) + " sl=" + PriceText(sl);
         return false;
      }
      if(tp > 0.0 && tp <= entry)
      {
         detail = "buy_tp_not_above_entry entry=" + PriceText(entry) + " tp=" + PriceText(tp);
         return false;
      }
   }
   else
   {
      if(sl > 0.0 && sl <= entry)
      {
         detail = "sell_sl_not_above_entry entry=" + PriceText(entry) + " sl=" + PriceText(sl);
         return false;
      }
      if(tp > 0.0 && tp >= entry)
      {
         detail = "sell_tp_not_below_entry entry=" + PriceText(entry) + " tp=" + PriceText(tp);
         return false;
      }
   }
   return true;
}

bool PrepareBrokerOrderLevels(int sendType, int logicalType, double &entry, double &sl, double &tp, string &detail)
{
   RefreshRates();
   double minDist = BrokerMinStopDistance();
   double rawEntry = entry, rawSl = sl, rawTp = tp;
   double bid = Bid, ask = Ask;

   if(sendType == OP_BUY)
   {
      entry = ask;
      if(sl > 0.0 && sl > bid - minDist) sl = bid - minDist;
      if(tp > 0.0 && tp < bid + minDist) tp = bid + minDist;
   }
   else if(sendType == OP_SELL)
   {
      entry = bid;
      if(sl > 0.0 && sl < ask + minDist) sl = ask + minDist;
      if(tp > 0.0 && tp > ask - minDist) tp = ask - minDist;
   }
   else if(sendType == OP_BUYLIMIT)
   {
      if(entry > ask - minDist) entry = ask - minDist;
      if(sl > 0.0 && sl > entry - minDist) sl = entry - minDist;
      if(tp > 0.0 && tp < entry + minDist) tp = entry + minDist;
   }
   else if(sendType == OP_SELLLIMIT)
   {
      if(entry < bid + minDist) entry = bid + minDist;
      if(sl > 0.0 && sl < entry + minDist) sl = entry + minDist;
      if(tp > 0.0 && tp > entry - minDist) tp = entry - minDist;
   }

   entry = NormalizePriceToTick(entry);
   sl = NormalizePriceToTick(sl);
   tp = NormalizePriceToTick(tp);

   if(sl <= 0.0)
   {
      detail = "missing_stop_after_broker_guard";
      return false;
   }
   string dirDetail;
   if(!ValidateDirectionLevels(logicalType, entry, sl, tp, dirDetail))
   {
      detail = dirDetail + " raw_entry=" + PriceText(rawEntry) + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) + " min_dist=" + PriceText(minDist);
      return false;
   }

   bool changed = (MathAbs(entry - rawEntry) > Point * 0.5 || MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(tp - rawTp) > Point * 0.5);
   detail = "broker_stop_guard changed=" + (changed ? "true" : "false") +
            " raw_entry=" + PriceText(rawEntry) + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) +
            " final_entry=" + PriceText(entry) + " final_sl=" + PriceText(sl) + " final_tp=" + PriceText(tp) +
            " bid=" + PriceText(bid) + " ask=" + PriceText(ask) +
            " stop_points=" + DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL), 0) +
            " freeze_points=" + DoubleToString(MarketInfo(Symbol(), MODE_FREEZELEVEL), 0) +
            " safety_points=" + IntegerToString(MathMax(0, InpBrokerStopSafetyPoints)) +
            " tick=" + PriceText(TickSizePrice());
   return true;
}

bool PrepareBrokerModifyStops(int logicalType, double openPrice, double &sl, double &tp, string &detail)
{
   RefreshRates();
   double minDist = BrokerMinStopDistance();
   double rawSl = sl, rawTp = tp;
   double bid = Bid, ask = Ask;

   if(logicalType == OP_BUY)
   {
      if(sl > 0.0 && sl > bid - minDist) sl = bid - minDist;
      if(tp > 0.0 && tp < bid + minDist) tp = bid + minDist;
   }
   else
   {
      if(sl > 0.0 && sl < ask + minDist) sl = ask + minDist;
      if(tp > 0.0 && tp > ask - minDist) tp = ask - minDist;
   }

   sl = NormalizePriceToTick(sl);
   tp = NormalizePriceToTick(tp);

   string dirDetail;
   if(!ValidateDirectionLevels(logicalType, openPrice, sl, tp, dirDetail))
   {
      detail = dirDetail + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) + " min_dist=" + PriceText(minDist);
      return false;
   }
   bool changed = (MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(tp - rawTp) > Point * 0.5);
   detail = "broker_modify_guard changed=" + (changed ? "true" : "false") +
            " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) +
            " final_sl=" + PriceText(sl) + " final_tp=" + PriceText(tp) +
            " bid=" + PriceText(bid) + " ask=" + PriceText(ask) +
            " min_dist=" + PriceText(minDist);
   return true;
}

bool ApplyInvertGeometry(string originalDir, double entry, double srcSl, double srcTp1, double srcTp2, double srcTp3,
                         string &dir, int &type, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   if(!g_invertMode)
   {
      detail = "invert=off";
      return true;
   }
   if(originalDir != "BUY" && originalDir != "SELL")
   {
      detail = "invert_invalid_dir original=" + originalDir;
      return false;
   }
   dir = (originalDir == "BUY") ? "SELL" : "BUY";
   type = (dir == "BUY") ? OP_BUY : OP_SELL;
   double risk = MathAbs(entry - srcSl);
   double d1 = MathAbs(srcTp1 - entry);
   double d2 = MathAbs(srcTp2 - entry);
   double d3 = MathAbs(srcTp3 - entry);
   if(risk <= Point || d1 <= Point)
   {
      detail = "invert_invalid_distances entry=" + PriceText(entry) + " src_sl=" + PriceText(srcSl) + " src_tp1=" + PriceText(srcTp1);
      return false;
   }
   if(type == OP_BUY)
   {
      sl = entry - d1;
      tp1 = entry + risk;
      tp2 = entry + MathMax(risk, d2);
      tp3 = entry + MathMax(MathMax(risk, d2), d3);
   }
   else
   {
      sl = entry + d1;
      tp1 = entry - risk;
      tp2 = entry - MathMax(risk, d2);
      tp3 = entry - MathMax(MathMax(risk, d2), d3);
   }
   sl = NormalizeDouble(sl, Digits);
   tp1 = NormalizeDouble(tp1, Digits);
   tp2 = NormalizeDouble(tp2, Digits);
   tp3 = NormalizeDouble(tp3, Digits);
   string dirDetail;
   if(!ValidateDirectionLevels(type, entry, sl, tp1, dirDetail))
   {
      detail = "invert_invalid_geometry " + dirDetail;
      return false;
   }
   detail = "invert=on original_dir=" + originalDir + " execution_dir=" + dir
      + " src_sl=" + PriceText(srcSl) + " src_tp1=" + PriceText(srcTp1) + " src_tp2=" + PriceText(srcTp2) + " src_tp3=" + PriceText(srcTp3)
      + " inv_sl=" + PriceText(sl) + " inv_tp1=" + PriceText(tp1) + " inv_tp2=" + PriceText(tp2) + " inv_tp3=" + PriceText(tp3);
   return true;
}
string SignalSourceFromEvent(string eventId)
{
   if(StringFind(eventId, "|prorenko_trend|") >= 0) return "trend";
   return "unknown";
}

bool OrderMatchesSignalSource(string eventId)
{
   string src = SignalSourceFromEvent(eventId);
   if(src == "unknown") return true;
   string c = OrderComment();
   return (StringFind(c, "ProRenkoBridge " + src + " ") == 0);
}
string BasketDayKey()
{
   return DateStamp(GmtDayStart());
}

string BasketStateKey(string field)
{
   return "ProRenkoBasket|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + IntegerToString(Period()) + "|" + IntegerToString(EffectiveMagic()) + "|" + BasketDayKey() + "|" + field;
}

bool SelectedOrderIsBasketScoped()
{
   if(OrderSymbol() != Symbol() || !IsCurrentInstanceMagic(OrderMagicNumber())) return false;
   if(TicketGV(OrderTicket(), "BASKET", 0.0) > 0.5) return true;
   return (StringFind(OrderComment(), "ProRenkoBridge basket ") == 0);
}

bool HasOpenBasketPositions()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL && type != OP_BUYLIMIT && type != OP_SELLLIMIT && type != OP_BUYSTOP && type != OP_SELLSTOP) continue;
      if(SelectedOrderIsBasketScoped()) return true;
   }
   return false;
}

double BasketScopedPnlToday(bool includeFloating)
{
   datetime dayStart = GmtDayStart();
   double pnl = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      if(OrderCloseTime() < dayStart) continue;
      if(!SelectedOrderIsBasketScoped()) continue;
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }
   if(includeFloating)
   {
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
         int ot = OrderType();
         if(ot != OP_BUY && ot != OP_SELL) continue;
         if(!SelectedOrderIsBasketScoped()) continue;
         pnl += OrderProfit() + OrderSwap() + OrderCommission();
      }
   }
   return pnl;
}

void BasketSetDayDone(string reason)
{
   GlobalVariableSet(BasketStateKey("DONE"), 1.0);
   GlobalVariableSet(BasketStateKey("DONE_TS"), TimeGMT());
   GlobalVariableSet(BasketStateKey("DONE_REASON_HASH"), StableHash(reason));
}

bool BasketDayDone(string &detail)
{
   if(!GlobalVariableCheck(BasketStateKey("DONE")) || GlobalVariableGet(BasketStateKey("DONE")) < 0.5)
      return false;
   detail = "basket_day_done day=" + BasketDayKey() + " pnl=" + DoubleToString(BasketScopedPnlToday(true), 2);
   return true;
}



bool BasketNativeSignalShadowMode()
{
   return (g_basketModeRuntime && g_nativeIgnoreWindowsRuntime);
}

bool BasketGuardReached(string &reason, string &detail)
{
   reason = "";
   detail = "basket_guard_ok";
   if(BasketDayDone(detail))
   {
      reason = "basket_blocked_day_done";
      return true;
   }


   double pnl = BasketScopedPnlToday(true);
   double targetMoney = BasketTargetMoneyPreview();
   double maxLossMoney = BasketMaxLossMoneyPreview();
   if(targetMoney > 0.0 && pnl >= targetMoney - 0.0001)
   {
      reason = "basket_target_hit_close";
      detail = "basket_pnl=" + DoubleToString(pnl, 2) + " target_money=" + DoubleToString(targetMoney, 2) + " target_pips=" + DoubleToString(g_basketTargetPipsRuntime, 1) + " target_pct=" + DoubleToString(g_basketTargetPctRuntime, 2);
      BasketSetDayDone(reason);
      return true;
   }
   if(maxLossMoney > 0.0 && pnl <= -maxLossMoney + 0.0001)
   {
      reason = "basket_loss_hit_close";
      detail = "basket_pnl=" + DoubleToString(pnl, 2) + " max_loss_money=" + DoubleToString(maxLossMoney, 2) + " max_loss_pips=" + DoubleToString(g_basketMaxLossPipsRuntime, 1);
      BasketSetDayDone(reason);
      return true;
   }
   detail = "basket_pnl=" + DoubleToString(pnl, 2) + " target_money=" + DoubleToString(targetMoney, 2) + " max_loss_money=" + DoubleToString(maxLossMoney, 2);
   return false;
}

bool CloseBasketScopedPositions(string eventName, string reason)
{
   bool allOk = true;
   for(int pass = 0; pass < 3; pass++)
   {
      bool found = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!SelectedOrderIsBasketScoped()) continue;
         int type = OrderType();
         if(type != OP_BUY && type != OP_SELL && type != OP_BUYLIMIT && type != OP_SELLLIMIT && type != OP_BUYSTOP && type != OP_SELLSTOP) continue;
         found = true;
         int ticket = OrderTicket();
         double lots = OrderLots();
         double sl = OrderStopLoss();
         double tp = OrderTakeProfit();
         double pnlBefore = OrderProfit() + OrderSwap() + OrderCommission();
         string dir = (type == OP_BUY || type == OP_BUYLIMIT || type == OP_BUYSTOP) ? "BUY" : "SELL";
         RefreshRates();
         if(type == OP_BUY || type == OP_SELL)
         {
            double px = (type == OP_BUY) ? Bid : Ask;
            bool ok = OrderClose(ticket, lots, px, InpSlippage, clrOrange);
            int err = GetLastError();
            if(ok)
            {
               TicketGVSet(ticket, "CLOSED", 1.0);
               Audit(eventName, TicketEvent(ticket), ticket, dir, lots, px, sl, tp, reason + " pass=" + IntegerToString(pass), pnlBefore, "basket_close");
            }
            else
            {
               allOk = false;
               Audit(eventName + "_failed", TicketEvent(ticket), ticket, dir, lots, px, sl, tp, reason + " err=" + IntegerToString(err), pnlBefore, "basket_close_failed");
            }
         }
         else
         {
            bool delOk = OrderDelete(ticket, clrOrange);
            int delErr = GetLastError();
            if(delOk)
            {
               TicketGVSet(ticket, "CLOSED", 1.0);
               Audit(eventName, TicketEvent(ticket), ticket, dir, lots, OrderOpenPrice(), sl, tp, reason + " delete_pending pass=" + IntegerToString(pass), pnlBefore, "basket_delete");
            }
            else
            {
               allOk = false;
               Audit(eventName + "_failed", TicketEvent(ticket), ticket, dir, lots, OrderOpenPrice(), sl, tp, reason + " delete_err=" + IntegerToString(delErr), pnlBefore, "basket_delete_failed");
            }
         }
      }
      if(!found) break;
      Sleep(150);
   }
   return allOk;
}

bool ManageBasketDailyGuards()
{
   // NAT24 is a local MT4 signal-shadow mode. In basket mode it must keep a
   // naked position from signal to reverse signal; prop risk guards belong to
   // the cTrader/listener execution side.
   if(BasketNativeSignalShadowMode())
      return false;

   bool hadOpenBasket = HasOpenBasketPositions();
   if(!g_basketModeRuntime && !hadOpenBasket) return false;
   string reason = "", detail = "";
   if(!BasketGuardReached(reason, detail)) return false;
   // A completed basket day remains blocked, but must not emit one audit row
   // per tick after there is nothing left to close.
   if(!hadOpenBasket) return true;
   bool ok = CloseBasketScopedPositions(reason, detail);
   Audit(reason, "", 0, "", 0, 0, 0, 0, detail + " close_ok=" + (ok ? "true" : "false"), BasketScopedPnlToday(true), "basket_daily_guard");
   return ok;
}

bool CloseOppositeBasket(int newType, string eventId)
{
   int opposite = (newType == OP_BUY) ? OP_SELL : OP_BUY;
   int oppositeLimit = (newType == OP_BUY) ? OP_SELLLIMIT : OP_BUYLIMIT;
   int oppositeStop = (newType == OP_BUY) ? OP_SELLSTOP : OP_BUYSTOP;
   bool allOk = true;
   for(int pass = 0; pass < 3; pass++)
   {
      bool found = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!SelectedOrderIsBasketScoped()) continue;
         int type = OrderType();
         if(type != opposite && type != oppositeLimit && type != oppositeStop) continue;
         found = true;
         int ticket = OrderTicket();
         double lots = OrderLots();
         double sl = OrderStopLoss();
         double tp = OrderTakeProfit();
         double pnlBefore = OrderProfit() + OrderSwap() + OrderCommission();
         string dir = (type == OP_BUY || type == OP_BUYLIMIT || type == OP_BUYSTOP) ? "BUY" : "SELL";
         RefreshRates();
         if(type == OP_BUY || type == OP_SELL)
         {
            double px = (type == OP_BUY) ? Bid : Ask;
            bool ok = OrderClose(ticket, lots, px, InpSlippage, clrSilver);
            int err = GetLastError();
            if(ok)
            {
               TicketGVSet(ticket, "CLOSED", 1.0);
               Audit("basket_reverse_close", eventId, ticket, dir, lots, px, sl, tp, "before_new_basket_signal pass=" + IntegerToString(pass), pnlBefore, "");
            }
            else
            {
               allOk = false;
               Audit("basket_reverse_close_failed", eventId, ticket, dir, lots, px, sl, tp, "err=" + IntegerToString(err) + " pass=" + IntegerToString(pass), pnlBefore, "");
            }
         }
         else
         {
            bool delOk = OrderDelete(ticket, clrSilver);
            int delErr = GetLastError();
            if(delOk)
            {
               TicketGVSet(ticket, "CLOSED", 1.0);
               Audit("basket_reverse_delete", eventId, ticket, dir, lots, OrderOpenPrice(), sl, tp, "delete_opposite_pending pass=" + IntegerToString(pass), pnlBefore, "");
            }
            else
            {
               allOk = false;
               Audit("basket_reverse_delete_failed", eventId, ticket, dir, lots, OrderOpenPrice(), sl, tp, "err=" + IntegerToString(delErr) + " pass=" + IntegerToString(pass), pnlBefore, "");
            }
         }
      }
      if(!found) break;
      Sleep(150);
   }
   return allOk;
}

bool HasOpenBasketDirection(int type)
{
   int pendingLimit = (type == OP_BUY) ? OP_BUYLIMIT : OP_SELLLIMIT;
   int pendingStop = (type == OP_BUY) ? OP_BUYSTOP : OP_SELLSTOP;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!SelectedOrderIsBasketScoped()) continue;
      int ot = OrderType();
      if(ot == type || ot == pendingLimit || ot == pendingStop) return true;
   }
   return false;
}

bool BuildBasketGeometry(int type, double entry, double &sl, string &detail)
{
   double pipSize = SymbolPipSize();
   double dist = MathMax(0.0, g_basketCatastrophicSlPipsRuntime) * pipSize;
   double minStop = MathMax(Point * 10.0, BrokerMinStopDistance());
   dist = MathMax(dist, minStop);
   if(entry <= 0.0 || dist <= Point)
   {
      detail = "basket_geometry_invalid entry=" + PriceText(entry) + " dist=" + DoubleToString(dist, Digits);
      return false;
   }
   sl = (type == OP_BUY) ? entry - dist : entry + dist;
   sl = NormalizeDouble(sl, Digits);
   string dirDetail = "";
   if(!ValidateDirectionLevels(type, entry, sl, 0.0, dirDetail))
   {
      detail = "basket_geometry_invalid_direction " + dirDetail;
      return false;
   }
   detail = "basket_cat_sl pips=" + DoubleToString(g_basketCatastrophicSlPipsRuntime, 1) + " pip_size=" + DoubleToString(pipSize, Digits + 2) + " dist=" + DoubleToString(dist, Digits) + " sl=" + PriceText(sl);
   return true;
}

double ResolveBasketLot(int type, string &detail)
{
   double pipSize = SymbolPipSize();
   double targetPips = MathMax(0.0, g_basketTargetPipsRuntime);
   double targetMove = targetPips * pipSize;
   double moneyPerLot = MoneyMovePerLot(targetMove);
   double targetMoney = BasketTargetMoneyPreview();
   if(targetPips <= 0.0 || targetMove <= 0.0 || moneyPerLot <= 0.0 || targetMoney <= 0.0)
   {
      detail = "basket_lot_block invalid target_pips=" + DoubleToString(targetPips, 1) + " target_money=" + DoubleToString(targetMoney, 2) + " money_per_lot=" + DoubleToString(moneyPerLot, 2);
      return 0.0;
   }
   double rawLot = targetMoney / moneyPerLot;
   double lot = NormalizeOrderLot(rawLot, false);
   if(lot <= 0.0)
   {
      detail = "basket_lot_block lot_below_min raw=" + DoubleToString(rawLot, 4) + " target_money=" + DoubleToString(targetMoney, 2) + " money_per_lot=" + DoubleToString(moneyPerLot, 2);
      return 0.0;
   }
   string marginDetail = "";
   double clamped = ClampLotToMargin(lot, type, false, marginDetail);
   if(clamped <= 0.0)
   {
      detail = "basket_lot_block margin raw=" + DoubleToString(rawLot, 4) + " lot=" + DoubleToString(lot, 3) + " " + marginDetail;
      return 0.0;
   }
   double actualTargetMoney = moneyPerLot * clamped;
   detail = "basket_lot target_pips=" + DoubleToString(targetPips, 1)
      + " target_pct=" + DoubleToString(g_basketTargetPctRuntime, 2)
      + " target_money=" + DoubleToString(targetMoney, 2)
      + " money_per_lot_at_target=" + DoubleToString(moneyPerLot, 2)
      + " raw_lot=" + DoubleToString(rawLot, 4)
      + " lot=" + DoubleToString(clamped, 3)
      + " actual_target_money=" + DoubleToString(actualTargetMoney, 2)
      + " " + marginDetail;
   return clamped;
}

void ExecuteBasketSignal(string dir, string eventId, double signalPx, int shift, int buffer, int type, double entry, double marketEntry, double driftPoints, bool usePending, double liveBid, double liveAsk, int spreadNow)
{
   string originalDir = dir;
   if(g_invertMode)
   {
      dir = (dir == "BUY") ? "SELL" : "BUY";
      type = (dir == "BUY") ? OP_BUY : OP_SELL;
      eventId = eventId + "|invert";
   }

   int sendType = type;
   datetime expiry = 0;
   if(usePending)
   {
      sendType = (type == OP_BUY) ? OP_BUYLIMIT : OP_SELLLIMIT;
      expiry = TimeCurrent() + MathMax(1, InpPendingExpiryMinutes) * 60;
   }

   double sl = 0.0;
   string geom = "";
   if(!BuildBasketGeometry(type, entry, sl, geom))
   {
      Audit("trade_blocked_geometry", eventId, 0, dir, 0, entry, sl, 0, geom, 0, "basket");
      return;
   }

   double target = 0.0;
   double rawEntry = entry, rawSl = sl;
   string brokerGuard = "";
   if(!PrepareBrokerOrderLevels(sendType, type, entry, sl, target, brokerGuard))
   {
      Audit("trade_blocked_broker_stops", eventId, 0, dir, 0, rawEntry, rawSl, 0, brokerGuard + " " + geom, 0, "basket");
      return;
   }

   Audit("basket_signal_received", eventId, 0, dir, 0, signalPx, sl, 0,
         "original_dir=" + originalDir + " shift=" + IntegerToString(shift) + " buffer=" + IntegerToString(buffer) +
         " bid=" + PriceText(liveBid) + " ask=" + PriceText(liveAsk) + " spread_points=" + IntegerToString(spreadNow) +
         " market_entry=" + PriceText(marketEntry) + " planned_entry=" + PriceText(entry) + " drift_points=" + DoubleToString(driftPoints, 1) +
         " pending_at_signal=" + (usePending ? "true" : "false") + " " + geom + " " + brokerGuard, 0, "basket_daily_target");

   if(!g_eaEnabled)
   {
      Audit("trade_blocked_disabled", eventId, 0, dir, 0, entry, sl, 0, "ea_disabled basket_no_csv", 0, "basket");
      return;
   }
   bool utcBlocked = IsInUtcEventBlock(TimeGMT(), g_utcEventBlockTimesRuntime, g_utcEventBlockRadiusRuntime);
   bool windowAllowed = IsInAllowedWindow(TimeGMT(), g_allowedWindowsRuntime) && !IsInNoTradeWindow(TimeGMT(), g_noTradeWindowsRuntime);
   bool bridgeWindowAllowed = (!utcBlocked && windowAllowed);
   if(utcBlocked)
   {
      if(!g_nativeIgnoreWindowsRuntime)
      {
         StoreEventBlockPending(eventId, dir, signalPx, shift, buffer, g_lastSignalTime, "basket_entry_guard");
         Audit("trade_deferred_utc_event_block", eventId, 0, dir, 0, entry, sl, 0, UtcEventBlockStatus(TimeGMT()), 0, "basket_no_new_entry_until_block_ends");
         return;
      }
      Audit("native_window_bypass_utc_event", eventId, 0, dir, 0, entry, sl, 0, UtcEventBlockStatus(TimeGMT()), 0, "basket bridge_csv_not_written_unless_window_valid");
   }
   if(!windowAllowed)
   {
      if(!g_nativeIgnoreWindowsRuntime)
      {
         Audit("trade_blocked_window", eventId, 0, dir, 0, entry, sl, 0, "allowed='" + g_allowedWindowsRuntime + "' no_trade='" + g_noTradeWindowsRuntime + "'", 0, "basket");
         return;
      }
      Audit("native_window_bypass", eventId, 0, dir, 0, entry, sl, 0, "allowed='" + g_allowedWindowsRuntime + "' no_trade='" + g_noTradeWindowsRuntime + "'", 0, "basket bridge_csv_not_written");
   }
   int spread = CurrentSpreadPoints();
   if(g_maxSpreadRuntime > 0 && spread > g_maxSpreadRuntime)
   {
      Audit("trade_blocked_spread", eventId, 0, dir, 0, entry, sl, 0, "spread=" + IntegerToString(spread) + " max=" + IntegerToString(g_maxSpreadRuntime), 0, "basket");
      return;
   }

   string bridgeSource = "ProRenko|" + SignalSourceFromEvent(eventId) + "|basket";
   if(g_invertMode) bridgeSource += "|invert";
   bool bridgePublishAllowed = (StringFind(eventId, "prorenko_nat24_shadow") < 0);
   if(bridgeWindowAllowed && bridgePublishAllowed)
      FileBridgeWriteBasketSignal(eventId, dir, entry, sl, bridgeSource, g_lastSignalTime);
   else if(bridgeWindowAllowed && !bridgePublishAllowed)
      Audit("bridge_skipped_nat24_shadow", eventId, 0, dir, 0, entry, sl, 0, "nat24_shadow_is_mt4_native_only", 0, "bridge_csv_not_written");
   else
      Audit("bridge_skipped_native_window_bypass", eventId, 0, dir, 0, entry, sl, 0, "basket native_ignore_windows=true", 0, "bridge_csv_not_written");

   string tradeState = "";
   if(!CanAttemptTradeNow(tradeState))
   {
      if(TimeCurrent() >= g_nextTradeDisabledRetryTs)
      {
         Audit("trade_blocked_trade_disabled", eventId, 0, dir, 0, entry, sl, 0, tradeState + " retry_seconds=" + IntegerToString(MathMax(1, InpTradeDisabledRetrySeconds)) + " bridge_csv_written=1", 0, "basket");
         g_nextTradeDisabledRetryTs = TimeCurrent() + MathMax(1, InpTradeDisabledRetrySeconds);
      }
      ReleaseEventForRetry(eventId);
      return;
   }

   if(g_basketCloseOnReverseRuntime && !CloseOppositeBasket(type, eventId))
   {
      Audit("trade_blocked_reverse_close_failed", eventId, 0, dir, 0, entry, sl, 0, "basket opposite position or pending could not be closed bridge_csv_written=1", 0, "retry_signal");
      ReleaseEventForRetry(eventId);
      return;
   }

   if(InpBlockSameDirectionOpen && HasOpenBasketDirection(type))
   {
      Audit("trade_blocked_same_direction", eventId, 0, dir, 0, entry, sl, 0, "existing same direction basket order bridge_csv_written=1", 0, "basket");
      return;
   }

   if(!BasketNativeSignalShadowMode())
   {
      string dailyGuardReason = "", dailyGuardDetail = "";
      if(DailyProfitLossGuardReached(dailyGuardReason, dailyGuardDetail))
      {
         Audit("trade_blocked_daily_profit_loss_target", eventId, 0, dir, 0, entry, sl, 0, dailyGuardDetail + " bridge_csv_written=1", 0, dailyGuardReason);
         return;
      }

      string basketReason = "", basketDetail = "";
      if(BasketGuardReached(basketReason, basketDetail))
      {
         CloseBasketScopedPositions(basketReason, basketDetail);
         Audit("basket_blocked_day_done", eventId, 0, dir, 0, entry, sl, 0, basketDetail + " bridge_csv_written=1", BasketScopedPnlToday(true), basketReason);
         return;
      }
   }
   else
   {
      Audit("basket_native_shadow_guard_bypass", eventId, 0, dir, 0, entry, sl, 0, "nat24_shadow=true daily_and_basket_guards_bypassed_for_mt4_native", BasketScopedPnlToday(true), "signal_to_signal_native");
   }

   string lotDetail = "";
   double lot = ResolveBasketLot(type, lotDetail);
   if(lot <= 0.0)
   {
      RiskAudit("basket_lot_blocked", "event=" + eventId + " " + lotDetail);
      Audit("trade_blocked_risk", eventId, 0, dir, 0, entry, sl, 0, lotDetail, 0, "basket");
      return;
   }

   double nativeOrderSl = BasketNativeSignalShadowMode() ? 0.0 : sl;
   int ticket = OrderSend(Symbol(), sendType, lot, NormalizePriceToTick(entry), InpSlippage, NormalizePriceToTick(nativeOrderSl), 0,
                          "ProRenkoBridge basket " + SignalSourceFromEvent(eventId) + " " + dir, EffectiveMagic(), expiry, (type == OP_BUY ? clrLime : clrTomato));
   int err = GetLastError();
   if(ticket > 0)
   {
      if(OrderSelect(ticket, SELECT_BY_TICKET)) entry = OrderOpenPrice();
      StoreTicket(ticket, 0, 0, 0, 0, 0, 0, false);
      TicketGVSet(ticket, "BASKET", 1.0);
      TicketGVSet(ticket, "BTPIPS", g_basketTargetPipsRuntime);
      TicketGVSet(ticket, "BTPCT", g_basketTargetPctRuntime);
      TicketGVSet(ticket, "BLPIPS", g_basketMaxLossPipsRuntime);
      TicketGVSet(ticket, "BCAT", g_basketCatastrophicSlPipsRuntime);
      TicketGVSet(ticket, "NATSHADOW", BasketNativeSignalShadowMode() ? 1.0 : 0.0);
      Audit("basket_order_sent", eventId, ticket, dir, lot, entry, sl, 0,
            "ticket=" + IntegerToString(ticket) + " type=" + (usePending ? "limit_at_signal" : "market") + " native_sl=" + PriceText(nativeOrderSl) + " nat24_shadow=" + (BasketNativeSignalShadowMode() ? "true" : "false") + " " + lotDetail + " " + geom,
            OrderProfit(), "basket_daily_target");
      RiskAudit("basket_lot_selected", "event=" + eventId + " ticket=" + IntegerToString(ticket) + " lot=" + DoubleToString(lot, 3) + " " + lotDetail);
      DrawTradeLevels();
   }
   else
   {
      if(RetryableTradeSendError(err))
      {
         ReleaseEventForRetry(eventId);
         g_nextTradeDisabledRetryTs = TimeCurrent() + MathMax(1, InpTradeDisabledRetrySeconds);
      }
      Audit("basket_order_failed", eventId, 0, dir, lot, entry, sl, 0, "err=" + IntegerToString(err) + " " + lotDetail + " " + geom, 0, "basket_daily_target");
   }
}
void ExecuteSignal(string dir, string eventId, double signalPx, int shift, int buffer)
{
   RefreshRates();
   int type = (dir == "BUY") ? OP_BUY : OP_SELL;
   double liveBid = Bid;
   double liveAsk = Ask;
   int spreadNow = CurrentSpreadPoints();
   double marketEntry = (type == OP_BUY) ? liveAsk : liveBid;
   double entry = marketEntry;
   bool worseThanSignal = (type == OP_BUY && marketEntry > signalPx) || (type == OP_SELL && marketEntry < signalPx);
   double driftPoints = (signalPx > 0.0) ? MathAbs(marketEntry - signalPx) / Point : 0.0;
   bool usePending = (g_pendingOnDriftRuntime && InpMaxMarketEntryDriftPoints > 0 && worseThanSignal && driftPoints > InpMaxMarketEntryDriftPoints);
   if(usePending) entry = signalPx;
   if(g_basketModeRuntime)
   {
      ExecuteBasketSignal(dir, eventId, signalPx, shift, buffer, type, entry, marketEntry, driftPoints, usePending, liveBid, liveAsk, spreadNow);
      return;
   }   string originalDir = dir;
   string sourceEventId = eventId;
   double sl, tp1, tp2, tp3;
   string geom;
   if(!BuildGeometry(type, entry, signalPx, shift, sl, tp1, tp2, tp3, geom))
   {
      Audit("trade_blocked_geometry", eventId, 0, dir, 0, entry, sl, 0, geom, 0, "");
      return;
   }
   if(g_invertMode)
   {
      double srcSl = sl, srcTp1 = tp1, srcTp2 = tp2, srcTp3 = tp3;
      string invertDetail = "";
      if(!ApplyInvertGeometry(originalDir, entry, srcSl, srcTp1, srcTp2, srcTp3, dir, type, sl, tp1, tp2, tp3, invertDetail))
      {
         Audit("trade_blocked_invert_geometry", eventId, 0, originalDir, 0, entry, srcSl, srcTp1, invertDetail + " " + geom, 0, "");
         return;
      }
      eventId = eventId + "|invert";
      geom = geom + " " + invertDetail;
   }
   double target = TpByR(type, entry, sl, g_targetRRuntime);
   double half = TpByR(type, entry, sl, g_halfRRuntime);

   int sendType = type;
   datetime expiry = 0;
   if(usePending)
   {
      sendType = (type == OP_BUY) ? OP_BUYLIMIT : OP_SELLLIMIT;
      expiry = TimeCurrent() + MathMax(1, InpPendingExpiryMinutes) * 60;
   }

   double rawPlannedEntry = entry, rawSl = sl, rawTarget = target;
   string brokerGuard;
   if(!PrepareBrokerOrderLevels(sendType, type, entry, sl, target, brokerGuard))
   {
      Audit("trade_blocked_broker_stops", eventId, 0, dir, 0, rawPlannedEntry, rawSl, rawTarget, brokerGuard + " " + geom, 0, "");
      return;
   }
   if(MathAbs(entry - rawPlannedEntry) > Point * 0.5 || MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(target - rawTarget) > Point * 0.5)
   {
      if(g_targetTpRuntime == 1) tp1 = target;
      if(g_targetTpRuntime == 2) tp2 = target;
      if(g_targetTpRuntime == 3) tp3 = target;
      if(g_halfRRuntime > 0.0 && MathAbs(g_halfRRuntime - g_targetRRuntime) <= 0.0001) half = target;
      Audit("broker_stop_adjusted", eventId, 0, dir, 0, entry, sl, target, brokerGuard, 0, "raw_entry=" + PriceText(rawPlannedEntry) + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTarget));
   }

   Audit("signal_received", eventId, 0, dir, g_lotRuntime, signalPx, sl, target, "source=chart_object shift=" + IntegerToString(shift) + " bid=" + PriceText(liveBid) + " ask=" + PriceText(liveAsk) + " spread_points=" + IntegerToString(spreadNow) + " market_entry=" + PriceText(marketEntry) + " planned_entry=" + PriceText(entry) + " drift_points=" + DoubleToString(driftPoints, 1) + " pending_at_signal=" + (usePending ? "true" : "false") + " " + geom + " " + brokerGuard + " half_trigger=" + PriceText(half), 0, "");
   if(!g_eaEnabled)
   {
      Audit("trade_blocked_disabled", eventId, 0, dir, 0, entry, sl, target, "ea_disabled_mt4_direct_after_file_bridge", 0, "");
      return;
   }
   string tradeState;
   if(!CanAttemptTradeNow(tradeState))
   {
      if(TimeCurrent() >= g_nextTradeDisabledRetryTs)
      {
         Audit("trade_blocked_trade_disabled", eventId, 0, dir, 0, entry, sl, target,
               tradeState + " retry_seconds=" + IntegerToString(MathMax(1, InpTradeDisabledRetrySeconds)), 0, "");
         g_nextTradeDisabledRetryTs = TimeCurrent() + MathMax(1, InpTradeDisabledRetrySeconds);
      }
      ReleaseEventForRetry(eventId);
      return;
   }

   // Reversal systems must flatten the previous opposite leg before any new-entry guard can block the replacement.
   if(InpCloseOppositeOnSignal && !CloseOpposite(type, eventId))
   {
      Audit("trade_blocked_reverse_close_failed", eventId, 0, dir, 0, entry, sl, target, "opposite_position_or_pending_could_not_be_closed", 0, "retry_signal");
      ReleaseEventForRetry(eventId);
      return;
   }

   bool utcBlocked = IsInUtcEventBlock(TimeGMT(), g_utcEventBlockTimesRuntime, g_utcEventBlockRadiusRuntime);
   bool windowAllowed = IsInAllowedWindow(TimeGMT(), g_allowedWindowsRuntime) && !IsInNoTradeWindow(TimeGMT(), g_noTradeWindowsRuntime);
   bool bridgeWindowAllowed = (!utcBlocked && windowAllowed);
   if(utcBlocked)
   {
      if(!g_nativeIgnoreWindowsRuntime)
      {
         StoreEventBlockPending(sourceEventId, originalDir, signalPx, shift, buffer, g_lastSignalTime, "traditional_entry_guard");
         Audit("trade_deferred_utc_event_block", eventId, 0, dir, 0, entry, sl, target, UtcEventBlockStatus(TimeGMT()), 0, "no_new_entry_until_block_ends");
         return;
      }
      Audit("native_window_bypass_utc_event", eventId, 0, dir, 0, entry, sl, target, UtcEventBlockStatus(TimeGMT()), 0, "traditional bridge_csv_not_written_unless_window_valid");
   }
   if(!windowAllowed)
   {
      if(!g_nativeIgnoreWindowsRuntime)
      {
         Audit("trade_blocked_window", eventId, 0, dir, 0, entry, sl, target, "allowed='" + g_allowedWindowsRuntime + "' no_trade='" + g_noTradeWindowsRuntime + "'", 0, "");
         return;
      }
      Audit("native_window_bypass", eventId, 0, dir, 0, entry, sl, target, "allowed='" + g_allowedWindowsRuntime + "' no_trade='" + g_noTradeWindowsRuntime + "'", 0, "traditional bridge_csv_not_written");
   }
   int spread = CurrentSpreadPoints();
   if(g_maxSpreadRuntime > 0 && spread > g_maxSpreadRuntime)
   {
      Audit("trade_blocked_spread", eventId, 0, dir, 0, entry, sl, target, "spread=" + IntegerToString(spread) + " max=" + IntegerToString(g_maxSpreadRuntime), 0, "");
      return;
   }
   if(InpBlockSameDirectionOpen && HasOpenDirection(type, eventId))
   {
      Audit("trade_blocked_same_direction", eventId, 0, dir, 0, entry, sl, target, "existing same direction order", 0, "");
      return;
   }

   string dailyGuardReason = "";
   string dailyGuardDetail = "";
   if(DailyProfitLossGuardReached(dailyGuardReason, dailyGuardDetail))
   {
      Audit("trade_blocked_daily_profit_loss_target", eventId, 0, dir, 0, entry, sl, target, dailyGuardDetail, 0, dailyGuardReason + " file_bridge_not_written=1");
      return;
   }

   string bridgeSource = "ProRenko|" + SignalSourceFromEvent(eventId);
   if(g_invertMode) bridgeSource += "|invert";
   if(SymmetricRTargetsEnabled()) bridgeSource += "|symR";
   if(bridgeWindowAllowed)
      FileBridgeWriteSignal(eventId, dir, entry, sl, target, bridgeSource, half, g_halfRRuntime > 0.0 ? ("r" + DoubleToString(g_halfRRuntime, 1)) : "off", g_lastSignalTime);
   else
      Audit("bridge_skipped_native_window_bypass", eventId, 0, dir, 0, entry, sl, target, "traditional native_ignore_windows=true", 0, "bridge_csv_not_written");


   string lotDetail;
   double lot = ResolveLot(entry, sl, type, g_halfRRuntime > 0.0, lotDetail);
   if(lot <= 0)
   {
      RiskAudit("lot_blocked", "event=" + eventId + " " + lotDetail);
      Audit("trade_blocked_risk", eventId, 0, dir, 0, entry, sl, target, lotDetail, 0, "");
      return;
   }

   int ticket = OrderSend(Symbol(), sendType, lot, NormalizePriceToTick(entry), InpSlippage, NormalizePriceToTick(sl), NormalizePriceToTick(target), "ProRenkoBridge " + SignalSourceFromEvent(eventId) + " " + dir, EffectiveMagic(), expiry, (type == OP_BUY ? clrLime : clrTomato));
   int err = GetLastError();
   if(ticket > 0)
   {
      if(OrderSelect(ticket, SELECT_BY_TICKET)) entry = OrderOpenPrice();
      StoreTicket(ticket, tp1, tp2, tp3, half, (g_halfRRuntime > 0.0 ? 1 : 0), RToLegacyIndex(g_targetRRuntime), g_lastGeometryUsedFallback);
      Audit(usePending ? "pending_order_sent" : "order_sent", eventId, ticket, dir, lot, entry, sl, target, "ticket=" + IntegerToString(ticket) + " type=" + (usePending ? "limit_at_signal" : "market") + " market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail + " levels=" + (g_lastGeometryUsedFallback ? "fallback_calculated" : "object") + " tp1=" + PriceText(tp1) + " tp2=" + PriceText(tp2) + " tp3=" + PriceText(tp3), 0, "");
      RiskAudit("lot_selected", "event=" + eventId + " ticket=" + IntegerToString(ticket) + " lot=" + DoubleToString(lot, 3) + " " + lotDetail);
      if(g_lastGeometryUsedFallback) DrawCalculatedFallbackLevels(ticket, sl, tp1, tp2, tp3);
      DrawTradeLevels();
   }
   else
   {
      if(err == 130 && TrySecondLevelStopGuardOpen(eventId, dir, sendType, type, lot, entry, sl, target, tp1, tp2, tp3, half, marketEntry, driftPoints, lotDetail, usePending))
         return;
      if(RetryableTradeSendError(err))
      {
         ReleaseEventForRetry(eventId);
         g_nextTradeDisabledRetryTs = TimeCurrent() + MathMax(1, InpTradeDisabledRetrySeconds);
      }
      Audit(usePending ? "pending_order_failed" : "order_failed", eventId, 0, dir, lot, entry, sl, target, "err=" + IntegerToString(err) + " market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail, 0, "");
   }
}

bool TrySecondLevelStopGuardOpen(string eventId, string dir, int sendType, int type, double lot, double entry, double sl, double target,
                                 double tp1, double tp2, double tp3, double half, double marketEntry, double driftPoints,
                                 string lotDetail, bool usePending)
{
   if(sendType != OP_BUY && sendType != OP_SELL)
   {
      Audit(usePending ? "pending_order_failed" : "order_failed", eventId, 0, dir, lot, entry, sl, target,
            "err=130 second_level_skipped_non_market market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail, 0, "");
      return false;
   }

   RefreshRates();
   double nakedEntry = (type == OP_BUY) ? Ask : Bid;
   int ticket = OrderSend(Symbol(), type, lot, NormalizePriceToTick(nakedEntry), InpSlippage, 0, 0,
                          "ProRenkoBridge " + SignalSourceFromEvent(eventId) + " " + dir + " guarded", EffectiveMagic(), 0, (type == OP_BUY ? clrLime : clrTomato));
   int openErr = GetLastError();
   if(ticket <= 0)
   {
      Audit("order_failed_stopguard_open", eventId, 0, dir, lot, nakedEntry, sl, target,
            "initial_err=130 fallback_err=" + IntegerToString(openErr) + " market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail, 0, "");
      return false;
   }

   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Audit("order_sent_stopguard_select_failed", eventId, ticket, dir, lot, nakedEntry, sl, target,
            "initial_err=130 ticket_opened_but_select_failed", 0, "");
      return true;
   }

   double openPrice = OrderOpenPrice();
   StoreTicket(ticket, tp1, tp2, tp3, half, (g_halfRRuntime > 0.0 ? 1 : 0), RToLegacyIndex(g_targetRRuntime), g_lastGeometryUsedFallback);
   Audit("order_sent_stopguard_unprotected", eventId, ticket, dir, lot, openPrice, 0, 0,
         "initial_err=130 naked_market_opened; attempting immediate protective_modify market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail,
         OrderProfit(), "raw_sl=" + PriceText(sl) + " raw_tp=" + PriceText(target));

   double modSl = sl;
   double modTp = target;
   string modifyGuard;
   bool canModify = PrepareBrokerModifyStops(type, openPrice, modSl, modTp, modifyGuard);
   if(canModify)
   {
      bool modOk = OrderModify(ticket, openPrice, NormalizePriceToTick(modSl), NormalizePriceToTick(modTp), 0, clrDodgerBlue);
      int modErr = GetLastError();
      if(modOk)
      {
         if(g_targetTpRuntime == 1) tp1 = modTp;
         if(g_targetTpRuntime == 2) tp2 = modTp;
         if(g_targetTpRuntime == 3) tp3 = modTp;
         if(g_halfRRuntime > 0.0 && MathAbs(g_halfRRuntime - g_targetRRuntime) <= 0.0001) half = modTp;
         StoreTicket(ticket, tp1, tp2, tp3, half, (g_halfRRuntime > 0.0 ? 1 : 0), RToLegacyIndex(g_targetRRuntime), g_lastGeometryUsedFallback);
         Audit("order_stopguard_modify_done", eventId, ticket, dir, lot, openPrice, modSl, modTp,
               modifyGuard + " protective_stops_attached " + lotDetail, OrderProfit(), "initial_order_err=130");
         RiskAudit("lot_selected", "event=" + eventId + " ticket=" + IntegerToString(ticket) + " lot=" + DoubleToString(lot, 3) + " stopguard=true " + lotDetail);
         if(g_lastGeometryUsedFallback) DrawCalculatedFallbackLevels(ticket, modSl, tp1, tp2, tp3);
         DrawTradeLevels();
         return true;
      }
      Audit("order_stopguard_modify_failed", eventId, ticket, dir, lot, openPrice, modSl, modTp,
            "err=" + IntegerToString(modErr) + " " + modifyGuard, OrderProfit(), "emergency_close_next");
   }
   else
   {
      Audit("order_stopguard_modify_blocked", eventId, ticket, dir, lot, openPrice, modSl, modTp,
            modifyGuard, OrderProfit(), "emergency_close_next");
   }

   RefreshRates();
   double closePx = (type == OP_BUY) ? Bid : Ask;
   bool closeOk = OrderClose(ticket, OrderLots(), closePx, InpSlippage, clrRed);
   int closeErr = GetLastError();
   if(closeOk)
   {
      TicketGVSet(ticket, "CLOSED", 1.0);
      Audit("order_stopguard_emergency_close_done", eventId, ticket, dir, lot, closePx, 0, 0,
            "protective_modify_failed_or_blocked; unprotected_position_closed", OrderProfit(), "");
   }
   else
   {
      Audit("order_stopguard_emergency_close_failed", eventId, ticket, dir, lot, closePx, 0, 0,
            "CRITICAL_UNPROTECTED err=" + IntegerToString(closeErr) + " protective_modify_failed_or_blocked", OrderProfit(), "");
   }
   return true;
}


double SymbolPipSize()
{
   double point = MarketInfo(Symbol(), MODE_POINT);
   if(point <= 0.0) point = Point;
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
}

bool PipSlModeEnabled()
{
   return (g_pipSlModeRuntime && g_pipSlPipsRuntime > 0.0);
}

bool SymmetricRTargetsEnabled()
{
   return (g_symmetricRTargetsRuntime && !PipSlModeEnabled());
}

bool ApplySymmetricRTargets(int type, double entry, double sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   double risk = MathAbs(entry - sl);
   if(entry <= 0.0 || sl <= 0.0 || risk <= Point)
   {
      detail += " symmetric_r_failed entry=" + PriceText(entry) + " sl=" + PriceText(sl);
      return false;
   }
   if(type == OP_BUY)
   {
      tp1 = entry + risk;
      tp2 = entry + 2.0 * risk;
      tp3 = entry + 3.0 * risk;
   }
   else
   {
      tp1 = entry - risk;
      tp2 = entry - 2.0 * risk;
      tp3 = entry - 3.0 * risk;
   }
   tp1 = NormalizeDouble(tp1, Digits);
   tp2 = NormalizeDouble(tp2, Digits);
   tp3 = NormalizeDouble(tp3, Digits);
   string dirDetail = "";
   if(!ValidateDirectionLevels(type, entry, sl, tp1, dirDetail))
   {
      detail += " symmetric_r_invalid_direction " + dirDetail;
      return false;
   }
   detail += " symmetric_r_targets=on risk=" + DoubleToString(risk, Digits) + " tp_legs=1R_2R_3R";
   return true;
}

bool BuildPipSlGeometry(int type, double entry, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   double pipSize = SymbolPipSize();
   double requestedRisk = MathMax(0.0, g_pipSlPipsRuntime) * pipSize;
   double minStop = MathMax(Point * 10.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   double risk = MathMax(requestedRisk, minStop);
   if(entry <= 0.0 || risk <= Point)
   {
      detail = "pip_sl_invalid entry=" + PriceText(entry) + " risk=" + DoubleToString(risk, Digits);
      return false;
   }
   if(type == OP_BUY)
   {
      sl = entry - risk;
      tp1 = entry + risk;
      tp2 = entry + 2.0 * risk;
      tp3 = entry + 3.0 * risk;
   }
   else
   {
      sl = entry + risk;
      tp1 = entry - risk;
      tp2 = entry - 2.0 * risk;
      tp3 = entry - 3.0 * risk;
   }
   sl = NormalizeDouble(sl, Digits);
   tp1 = NormalizeDouble(tp1, Digits);
   tp2 = NormalizeDouble(tp2, Digits);
   tp3 = NormalizeDouble(tp3, Digits);
   string dirDetail = "";
   if(!ValidateDirectionLevels(type, entry, sl, tp1, dirDetail))
   {
      detail = "pip_sl_invalid_direction " + dirDetail;
      return false;
   }
   detail = "pip_sl_mode entry=" + PriceText(entry)
      + " pips=" + DoubleToString(g_pipSlPipsRuntime, 2)
      + " pip_size=" + DoubleToString(pipSize, Digits + 2)
      + " requested_risk=" + DoubleToString(requestedRisk, Digits)
      + " applied_risk=" + DoubleToString(risk, Digits)
      + " min_stop=" + DoubleToString(minStop, Digits)
      + " tp_legs=1R_2R_3R";
   return true;
}

bool BuildGeometry(int type, double entry, double signalPx, int signalShift, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   g_lastGeometryUsedFallback = false;
   if(PipSlModeEnabled())
   {
      if(BuildPipSlGeometry(type, entry, sl, tp1, tp2, tp3, detail))
         return true;
      return false;
   }
   string objectDetail = "";
   if(BuildObjectGeometry(type, entry, signalPx, sl, tp1, tp2, tp3, objectDetail))
   {
      detail = objectDetail;
      if(SymmetricRTargetsEnabled())
      {
         if(!ApplySymmetricRTargets(type, entry, sl, tp1, tp2, tp3, detail)) return false;
      }
      return true;
   }
   if(!InpAllowCalculatedFallbackLevels)
   {
      detail = objectDetail;
      return false;
   }
   string fallbackDetail = "";
   if(BuildCalculatedFallbackGeometry(type, entry, signalShift, sl, tp1, tp2, tp3, fallbackDetail))
   {
      g_lastGeometryUsedFallback = true;
      detail = "fallback_calculated reason='" + objectDetail + "' " + fallbackDetail;
      if(SymmetricRTargetsEnabled())
      {
         if(!ApplySymmetricRTargets(type, entry, sl, tp1, tp2, tp3, detail)) return false;
      }
      return true;
   }
   detail = "object_failed='" + objectDetail + "' fallback_failed='" + fallbackDetail + "'";
   return false;
}

bool BuildObjectGeometry(int type, double entry, double signalPx, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   detail = "object_levels_unused_prorenko_buffer_mode";
   return false;
}

bool BuildCalculatedFallbackGeometry(int type, double entry, int signalShift, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   int atrShift = MathMax(1, signalShift);
   double atr = iATR(Symbol(), Period(), InpRiskAtrPeriod, atrShift);
   if(atr <= Point * 2.0) atr = iATR(Symbol(), Period(), InpRiskAtrPeriod, 1);
   if(atr <= Point * 2.0)
   {
      detail = "atr_unavailable";
      return false;
   }

   double risk = MathMax(Point * 10.0, atr * MathMax(0.1, InpRiskAtrMult));
   sl = (type == OP_BUY) ? entry - risk : entry + risk;
   detail = "base_atr=" + DoubleToString(atr, Digits) + " atr_mult=" + DoubleToString(InpRiskAtrMult, 2);

   if(InpUseStructuralSwingStop)
   {
      double swingSl, swingRisk;
      string swingDetail;
      if(FindStructuralSwingStop(type, signalShift, entry, swingSl, swingRisk, swingDetail))
      {
         if(swingRisk > risk)
         {
            risk = swingRisk;
            sl = swingSl;
            detail += " structural=wider " + swingDetail;
         }
         else detail += " structural=ignored_narrower " + swingDetail;
      }
      else detail += " structural=none " + swingDetail;
   }

   double scale = MathMax(10.0, MathMin(200.0, g_finalScaleRuntime)) / 100.0;
   risk = MathAbs(entry - sl) * scale;
   if(type == OP_BUY)
   {
      sl = entry - risk;
      tp1 = entry + risk;
      tp2 = entry + 2.0 * risk;
      tp3 = entry + 3.0 * risk;
   }
   else
   {
      sl = entry + risk;
      tp1 = entry - risk;
      tp2 = entry - 2.0 * risk;
      tp3 = entry - 3.0 * risk;
   }

   if(type == OP_BUY && !(sl < entry && tp1 > entry)) return false;
   if(type == OP_SELL && !(sl > entry && tp1 < entry)) return false;
   sl = NormalizeDouble(sl, Digits);
   tp1 = NormalizeDouble(tp1, Digits);
   tp2 = NormalizeDouble(tp2, Digits);
   tp3 = NormalizeDouble(tp3, Digits);
   detail += " final_scale_pct=" + DoubleToString(g_finalScaleRuntime, 1) + " final_risk=" + DoubleToString(risk, Digits);
   return true;
}

bool FindStructuralSwingStop(int type, int signalShift, double entry, double &outSl, double &outRisk, string &detail)
{
   int left = MathMax(2, InpSwingLeftBars);
   int right = MathMax(1, InpSwingRightBars);
   int start = MathMax(right + 1, signalShift + right);
   int end = MathMin(Bars - left - 2, signalShift + MathMax(left + right + 5, InpSwingLookbackBars));
   double bestRisk = 0, bestSl = 0; int bestShift = -1;

   for(int s = start; s <= end; s++)
   {
      double atr = iATR(Symbol(), Period(), InpSwingAtrPeriod, s);
      if(atr <= Point * 2) continue;
      bool pivot = true;
      if(type == OP_BUY)
      {
         double low = Low[s];
         for(int a = 1; a <= left; a++) if(Low[s + a] <= low) { pivot = false; break; }
         if(!pivot) continue;
         for(int b = 1; b <= right; b++) if(Low[s - b] < low) { pivot = false; break; }
         if(!pivot) continue;
         double prom = MathMin(HighestHighOlder(s, left) - low, HighestHighRecent(s, right) - low);
         if(prom < atr * InpSwingMinProminenceAtr) continue;
         if(entry - low < atr * InpSwingMinDepartureAtr) continue;
         double candidate = low - atr * MathMax(0.0, InpSwingBufferAtr);
         double r = entry - candidate;
         if(r > bestRisk) { bestRisk = r; bestSl = candidate; bestShift = s; }
      }
      else
      {
         double high = High[s];
         for(int c = 1; c <= left; c++) if(High[s + c] >= high) { pivot = false; break; }
         if(!pivot) continue;
         for(int d = 1; d <= right; d++) if(High[s - d] > high) { pivot = false; break; }
         if(!pivot) continue;
         double prom2 = MathMin(high - LowestLowOlder(s, left), high - LowestLowRecent(s, right));
         if(prom2 < atr * InpSwingMinProminenceAtr) continue;
         if(high - entry < atr * InpSwingMinDepartureAtr) continue;
         double candidate2 = high + atr * MathMax(0.0, InpSwingBufferAtr);
         double r2 = candidate2 - entry;
         if(r2 > bestRisk) { bestRisk = r2; bestSl = candidate2; bestShift = s; }
      }
   }
   if(bestShift < 0) { detail = "no_structural_pivot"; return false; }
   outSl = bestSl; outRisk = bestRisk;
   detail = "swing_shift=" + IntegerToString(bestShift) + " swing_sl=" + PriceText(bestSl) + " swing_risk=" + DoubleToString(bestRisk, Digits);
   return true;
}

double HighestHighOlder(int shift, int bars) { double v = High[shift]; for(int i=1; i<=bars && shift+i<Bars; i++) v = MathMax(v, High[shift+i]); return v; }
double HighestHighRecent(int shift, int bars) { double v = High[shift]; for(int i=1; i<=bars && shift-i>=0; i++) v = MathMax(v, High[shift-i]); return v; }
double LowestLowOlder(int shift, int bars) { double v = Low[shift]; for(int i=1; i<=bars && shift+i<Bars; i++) v = MathMin(v, Low[shift+i]); return v; }
double LowestLowRecent(int shift, int bars) { double v = Low[shift]; for(int i=1; i<=bars && shift-i>=0; i++) v = MathMin(v, Low[shift-i]); return v; }
double TpByIndex(int idx, double tp1, double tp2, double tp3) { if(idx==1) return tp1; if(idx==2) return tp2; if(idx==3) return tp3; return 0; }

double ParseDashboardR(string raw, double fallback, double minValue, double maxValue)
{
   string s = Trim(raw);
   StringReplace(s, ",", ".");
   double value = (StringLen(s) > 0 ? StringToDouble(s) : fallback);
   value = MathMax(minValue, MathMin(maxValue, value));
   return NormalizeDouble(value, 1);
}

int RToLegacyIndex(double r)
{
   double rounded = MathRound(r);
   if(MathAbs(r - rounded) <= 0.0001 && rounded >= 0 && rounded <= 3)
      return (int)rounded;
   return 0;
}

string RLabel(double r)
{
   return DoubleToString(NormalizeDouble(r, 1), 1) + "R";
}

double TpByR(int type, double entry, double sl, double r)
{
   if(r <= 0.0 || entry <= 0.0 || sl <= 0.0)
      return 0.0;
   double risk = MathAbs(entry - sl);
   if(risk <= Point * 0.5)
      return 0.0;
   double target = (type == OP_BUY) ? entry + risk * r : entry - risk * r;
   return NormalizeDouble(target, Digits);
}

void ManagePositions()
{
   RefreshRates();
   if(ManageBasketDailyGuards())
   {
      DrawTradeLevels();
      return;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      int ticket = OrderTicket();
      if(SelectedOrderIsBasketScoped())
      {
         double basketPx = (type == OP_BUY) ? Bid : Ask;
         UpdateTicketExcursion(ticket, basketPx);
         continue;
      }
      TryEnrichFallbackTrade(ticket, type);
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      string dir = (type == OP_BUY) ? "BUY" : "SELL";
      double px = (type == OP_BUY) ? Bid : Ask;
      UpdateTicketExcursion(ticket, px);
      int halfIdx = (int)TicketGV(ticket, "HIDX", 0);
      double half = TicketGV(ticket, "HTP", 0);
      bool halfDone = (TicketGV(ticket, "HDONE", 0) > 0.5);
      if(halfIdx > 0 && !halfDone && half > 0 && PriceReached(type, px, half))
      {
         double closeLots = NormalizeCloseLots(OrderLots() / 2.0);
         if(closeLots > 0 && closeLots < OrderLots())
         {
            double oldOpen = OrderOpenPrice();
            double oldLots = OrderLots();
            double oldSl = OrderStopLoss();
            double oldTp = OrderTakeProfit();
            bool ok = OrderClose(ticket, closeLots, px, InpSlippage, clrAqua);
            int err = GetLastError();
            if(ok)
            {
               double expectedLots = NormalizeCloseLots(oldLots - closeLots);
               int remainderTicket = FindPartialCloseRemainderTicket(ticket, type, oldOpen, expectedLots);
               TicketGVSet(ticket, "HDONE", 1);
               Audit("half_close_done", TicketEvent(ticket), ticket, dir, closeLots, px, oldSl, oldTp, "trigger=" + PriceText(half) + " expected_remainder_lots=" + DoubleToString(expectedLots, 2) + " remainder_ticket=" + IntegerToString(remainderTicket), OrderProfit(), "");
               if(remainderTicket > 0)
               {
                  TransferTicketState(ticket, remainderTicket, "partial_half_close");
                  MoveSlToBE(remainderTicket, type);
               }
               else
               {
                  Audit("half_close_remainder_not_found", TicketEvent(ticket), ticket, dir, expectedLots, oldOpen, oldSl, oldTp, "partial close succeeded but new remainder ticket was not found; BE modify deferred", OrderProfit(), "");
               }
            }
            else Audit("half_close_failed", TicketEvent(ticket), ticket, dir, closeLots, px, OrderStopLoss(), OrderTakeProfit(), "err=" + IntegerToString(err), 0, "");
         }
      }
      double target = OrderTakeProfit();
      if(target > 0 && PriceReached(type, px, target))
      {
         double lots = OrderLots();
         bool ok2 = OrderClose(ticket, lots, px, InpSlippage, clrGold);
         int err2 = GetLastError();
         if(ok2)
         {
            TicketGVSet(ticket, "CLOSED", 1.0);
            Audit("full_tp_close_done", TicketEvent(ticket), ticket, dir, lots, px, OrderStopLoss(), target, "manual_guard_tp_reached", OrderProfit(), "");
         }
         else Audit("full_tp_close_failed", TicketEvent(ticket), ticket, dir, lots, px, OrderStopLoss(), target, "err=" + IntegerToString(err2), 0, "broker_tp_may_handle_it");
      }
   }
   DrawTradeLevels();
}

bool PriceReached(int type, double price, double level) { if(level <= 0) return false; return (type == OP_BUY) ? (price >= level) : (price <= level); }

bool RetryableTradeSendError(int err)
{
   return err == 133   // ERR_TRADE_DISABLED
          || err == 146 // ERR_TRADE_CONTEXT_BUSY
          || err == 136 // ERR_OFF_QUOTES
          || err == 137 // ERR_BROKER_BUSY
          || err == 4109; // ERR_TRADE_NOT_ALLOWED
}

void ReleaseEventForRetry(string eventId)
{
   if(g_lastEventId == eventId)
      g_lastEventId = "";
   if(g_lastTrendEventId == eventId)
      g_lastTrendEventId = "";
}

bool CanAttemptTradeNow(string &detail)
{
   bool symbolTradeAllowed = (MarketInfo(Symbol(), MODE_TRADEALLOWED) > 0.5);
   bool terminalTradeAllowed = IsTradeAllowed();
   bool contextBusy = IsTradeContextBusy();
   detail = "symbol_trade_allowed=" + (symbolTradeAllowed ? "true" : "false")
            + " terminal_trade_allowed=" + (terminalTradeAllowed ? "true" : "false")
            + " context_busy=" + (contextBusy ? "true" : "false")
            + " bid=" + PriceText(Bid)
            + " ask=" + PriceText(Ask);
   return symbolTradeAllowed && terminalTradeAllowed && !contextBusy;
}

void TryEnrichFallbackTrade(int ticket, int type)
{
   if(!InpEnrichFallbackTradeWithObjectLevels) return;
   if(TicketGV(ticket, "FB", 0.0) < 0.5) return;
   if(TicketGV(ticket, "ENRICH", 0.0) > 0.5) return;
   if(TicketGV(ticket, "HDONE", 0.0) > 0.5)
   {
      TicketGVSet(ticket, "ENRICH", 1.0);
      Audit("object_enrich_skipped_half_done", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), OrderStopLoss(), OrderTakeProfit(), "fallback trade already half-managed; object override skipped", OrderProfit(), "");
      return;
   }

   double sl, tp1, tp2, tp3;
   string detail;
   double anchor = OrderOpenPrice();
   string anchorDetail;
   FindLevelPrice(InpSignalLevelObjectName, anchor, anchorDetail);
   if(!BuildObjectGeometry(type, OrderOpenPrice(), anchor, sl, tp1, tp2, tp3, detail)) return;
   if(SymmetricRTargetsEnabled())
   {
      if(!ApplySymmetricRTargets(type, OrderOpenPrice(), sl, tp1, tp2, tp3, detail)) return;
   }

   double targetR = TicketGV(ticket, "TR", g_targetRRuntime);
   double halfR = TicketGV(ticket, "HBR", g_halfRRuntime);
   int targetIdx = RToLegacyIndex(targetR);
   int halfIdx = (halfR > 0.0 ? 1 : 0);
   double newTarget = TpByR(type, OrderOpenPrice(), sl, targetR);
   double newHalf = TpByR(type, OrderOpenPrice(), sl, halfR);

   double rawSl = sl, rawTarget = newTarget;
   string brokerGuard;
   if(!PrepareBrokerModifyStops(type, OrderOpenPrice(), sl, newTarget, brokerGuard))
   {
      Audit("object_enrich_blocked_broker_stops", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), rawSl, rawTarget, brokerGuard + " " + detail, OrderProfit(), "");
      return;
   }
   if(MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(newTarget - rawTarget) > Point * 0.5)
   {
      if(targetIdx == 1) tp1 = newTarget;
      if(targetIdx == 2) tp2 = newTarget;
      if(targetIdx == 3) tp3 = newTarget;
      if(halfR > 0.0 && MathAbs(halfR - targetR) <= 0.0001) newHalf = newTarget;
      Audit("object_enrich_broker_stop_adjusted", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, brokerGuard, OrderProfit(), "raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTarget));
   }

   bool changed = (MathAbs(OrderStopLoss() - sl) > Point || MathAbs(OrderTakeProfit() - newTarget) > Point);
   if(!changed)
   {
      TicketGVSet(ticket, "FB", 0.0);
      TicketGVSet(ticket, "ENRICH", 1.0);
      TicketGVSet(ticket, "TP1", tp1); TicketGVSet(ticket, "TP2", tp2); TicketGVSet(ticket, "TP3", tp3); TicketGVSet(ticket, "HTP", newHalf);
      Audit("object_enrich_no_change", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, detail, OrderProfit(), "");
      return;
   }

   bool ok = OrderModify(ticket, OrderOpenPrice(), NormalizePriceToTick(sl), NormalizePriceToTick(newTarget), 0, clrDodgerBlue);
   int err = GetLastError();
   if(ok)
   {
      TicketGVSet(ticket, "FB", 0.0);
      TicketGVSet(ticket, "ENRICH", 1.0);
      TicketGVSet(ticket, "TP1", tp1); TicketGVSet(ticket, "TP2", tp2); TicketGVSet(ticket, "TP3", tp3); TicketGVSet(ticket, "HTP", newHalf);
      DeleteCalculatedFallbackLevels(ticket);
      Audit("object_enrich_modify_done", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, detail + " new_half=" + PriceText(newHalf), OrderProfit(), "fallback levels overwritten by PRORENKO objects");
      DrawTradeLevels();
   }
   else
   {
      Audit("object_enrich_modify_failed", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, "err=" + IntegerToString(err) + " " + detail, OrderProfit(), "");
   }
}

void MoveSlToBE(int ticket, int type)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   double be = NormalizeDouble(OrderOpenPrice(), Digits);
   double sl = OrderStopLoss();
   bool improve = (type == OP_BUY && (sl <= 0 || be > sl + Point)) || (type == OP_SELL && (sl <= 0 || be < sl - Point));
   if(!improve) return;

   RefreshRates();
   double minDist = BrokerMinStopDistance();
   if(type == OP_BUY && be > Bid - minDist)
   {
      Audit("sl_to_be_wait_stop_level", TicketEvent(ticket), ticket, "BUY", OrderLots(), be, sl, OrderTakeProfit(), "bid=" + PriceText(Bid) + " min_dist=" + PriceText(minDist), OrderProfit(), "");
      return;
   }
   if(type == OP_SELL && be < Ask + minDist)
   {
      Audit("sl_to_be_wait_stop_level", TicketEvent(ticket), ticket, "SELL", OrderLots(), be, sl, OrderTakeProfit(), "ask=" + PriceText(Ask) + " min_dist=" + PriceText(minDist), OrderProfit(), "");
      return;
   }

   bool ok = OrderModify(ticket, OrderOpenPrice(), NormalizePriceToTick(be), OrderTakeProfit(), 0, clrAqua);
   int err = GetLastError();
   Audit(ok ? "sl_to_be_done" : "sl_to_be_failed", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), be, sl, OrderTakeProfit(), ok ? "" : "err=" + IntegerToString(err), OrderProfit(), "");
}

bool CloseOpposite(int newType, string eventId)
{
   int opposite = (newType == OP_BUY) ? OP_SELL : OP_BUY;
   int oppositeLimit = (newType == OP_BUY) ? OP_SELLLIMIT : OP_BUYLIMIT;
   int oppositeStop = (newType == OP_BUY) ? OP_SELLSTOP : OP_BUYSTOP;
   string src = SignalSourceFromEvent(eventId);
   bool allOk = true;

   for(int pass = 0; pass < 3; pass++)
   {
      bool foundThisPass = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
         int ot = OrderType();
         if(ot != opposite && ot != oppositeLimit && ot != oppositeStop) continue;

         foundThisPass = true;
         int ticket = OrderTicket();
         double lots = OrderLots();
         double openPrice = OrderOpenPrice();
         double sl = OrderStopLoss();
         double tp = OrderTakeProfit();
         double pnlBefore = OrderProfit() + OrderSwap() + OrderCommission();
         string dir = (ot == OP_BUY || ot == OP_BUYLIMIT || ot == OP_BUYSTOP) ? "BUY" : "SELL";
         RefreshRates();

         if(ot == OP_BUY || ot == OP_SELL)
         {
            double px = (ot == OP_BUY) ? Bid : Ask;
            bool ok = OrderClose(ticket, lots, px, InpSlippage, clrSilver);
            int err = GetLastError();
            if(ok)
            {
               TicketGVSet(ticket, "CLOSED", 1.0);
               Audit("reverse_close_done", eventId, ticket, dir, lots, px, sl, tp, "before_new_signal source=" + src + " pass=" + IntegerToString(pass), pnlBefore, "");
            }
            else
            {
               allOk = false;
               Audit("reverse_close_failed", eventId, ticket, dir, lots, px, sl, tp, "err=" + IntegerToString(err) + " source=" + src + " pass=" + IntegerToString(pass), pnlBefore, "");
            }
         }
         else
         {
            bool delOk = OrderDelete(ticket, clrSilver);
            int delErr = GetLastError();
            if(delOk)
            {
               TicketGVSet(ticket, "CLOSED", 1.0);
               Audit("reverse_delete_done", eventId, ticket, dir, lots, openPrice, sl, tp, "delete_opposite_pending source=" + src + " pass=" + IntegerToString(pass), pnlBefore, "");
            }
            else
            {
               allOk = false;
               Audit("reverse_delete_failed", eventId, ticket, dir, lots, openPrice, sl, tp, "err=" + IntegerToString(delErr) + " source=" + src + " pass=" + IntegerToString(pass), pnlBefore, "");
            }
         }
      }
      if(!foundThisPass) break;
      Sleep(150);
   }

   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int remainingType = OrderType();
      if(remainingType == opposite || remainingType == oppositeLimit || remainingType == oppositeStop)
      {
         allOk = false;
         Audit("reverse_close_remaining", eventId, OrderTicket(), (opposite == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), OrderStopLoss(), OrderTakeProfit(), "opposite_still_open_after_retries source=" + src, OrderProfit(), "");
      }
   }
   return allOk;
}
bool HasOpenDirection(int type, string eventId)
{
   int pendingLimit = (type == OP_BUY) ? OP_BUYLIMIT : OP_SELLLIMIT;
   int pendingStop = (type == OP_BUY) ? OP_BUYSTOP : OP_SELLSTOP;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsCurrentInstanceMagic(OrderMagicNumber())) continue;
      if(!OrderMatchesSignalSource(eventId)) continue;
      int ot = OrderType();
      if(ot == type || ot == pendingLimit || ot == pendingStop) return true;
   }
   return false;
}
bool ManagedRiskMode(){ return g_ftmoMode || g_riskLotOnlyMode; }
bool EffectiveRiskEnabled(){ return InpAdvancedAccountRiskEnabled || ManagedRiskMode(); }
string RuntimeRiskModeLabel(){ if(g_ftmoMode) return "FTMO"; if(g_riskLotOnlyMode) return "RISKLOT"; return "NORMAL"; }
double EffAccountRiskPerTradePct(){ return MathMax(0.0, g_riskPctRuntime); }
double EffAccountRiskDailyAtrExposurePct(){ return g_ftmoMode ? 2.0 : (g_riskLotOnlyMode ? 0.0 : InpAccountRiskDailyAtrExposurePct); }
double EffMaxPortfolioRiskPct(){ return g_ftmoMode ? 4.0 : (g_riskLotOnlyMode ? 0.0 : InpMaxPortfolioRiskPct); }
double EffDailyLossLimitPct(){ return g_ftmoMode ? 5.0 : InpDailyLossLimitPct; }
double EffMaxDrawdownPct(){ return g_ftmoMode ? 10.0 : InpMaxDrawdownPct; }
double EffMaxMarginUsagePct(){ return g_ftmoMode ? 40.0 : InpMaxMarginUsagePct; }

int LegacyEffectiveMagic() { if(EffectiveRiskEnabled()) return 1000000000 + MathAbs(InpMagic % 900000000); return InpMagic; }

int StableHash(string s)
{
   int h = 216613626;
   for(int i = 0; i < StringLen(s); i++)
   {
      h = h ^ StringGetCharacter(s, i);
      h = h * 16777619;
   }
   if(h < 0) h = -h;
   return h;
}

int EffectiveMagic()
{
   if(!EffectiveRiskEnabled()) return InpMagic;
   if(!InpUseSymbolTimeframeMagic) return LegacyEffectiveMagic();
   int h = StableHash(Symbol() + "|" + IntegerToString(Period()));
   return 1000000000 + MathAbs((MathAbs(InpMagic % 100000000) * 31 + h) % 900000000);
}

bool IsCurrentInstanceMagic(int magic) { return magic == InpMagic || magic == EffectiveMagic(); }
bool IsOurMagic(int magic) { return IsCurrentInstanceMagic(magic) || magic == LegacyEffectiveMagic(); }

double ResolveLot(double entry, double sl, int type, bool requireHalfSplit, string &detail)
{
   double fallback = NormalizeOrderLot(g_lotRuntime, requireHalfSplit);
   if(!EffectiveRiskEnabled()) { detail = "risk_engine=off lot=" + DoubleToString(fallback, 3); return fallback; }
   double cap, daily, dd;
   AccountRiskMetrics(cap, daily, dd);
   if(EffDailyLossLimitPct() > 0 && daily >= EffDailyLossLimitPct()) { if(InpLiquidateOnBreach) LiquidateScoped("daily_loss_breach"); detail = "risk_block daily_loss_pct=" + DoubleToString(daily,2); return 0; }
   if(EffMaxDrawdownPct() > 0 && dd >= EffMaxDrawdownPct()) { if(InpLiquidateOnBreach) LiquidateScoped("max_drawdown_breach"); detail = "risk_block total_dd_pct=" + DoubleToString(dd,2); return 0; }
   double riskPerLot = MoneyRiskPerLot(entry, sl);
   if(riskPerLot <= 0) { detail = "risk_block invalid_risk_per_lot"; return 0; }
   double tradeBudget = cap * MathMax(0.0, EffAccountRiskPerTradePct()) / 100.0;
   double atrBudget = cap * MathMax(0.0, EffAccountRiskDailyAtrExposurePct()) / 100.0;
   double openRisk = CurrentOpenRisk();
   double portfolioBudget = cap * MathMax(0.0, EffMaxPortfolioRiskPct()) / 100.0 - openRisk;
   double budget = (EffMaxPortfolioRiskPct() > 0) ? MathMin(tradeBudget, portfolioBudget) : tradeBudget;
   if(budget <= 0) { detail = "risk_block exhausted_budget open_risk=" + DoubleToString(openRisk,2); return 0; }
   double dailyAtr = ClosedDailyAtr(Symbol(), InpAccountRiskDailyAtrPeriod);
   double dailyMoneyPerLot = MoneyMovePerLot(dailyAtr);
   double slLot = budget / riskPerLot;
   double atrLot = 0.0;
   bool atrCapActive = (EffAccountRiskDailyAtrExposurePct() > 0.0 && atrBudget > 0.0 && dailyAtr > 0.0 && dailyMoneyPerLot > 0.0);
   if(atrCapActive) atrLot = atrBudget / dailyMoneyPerLot;
   double rawLot = (InpAutoLotByRisk || ManagedRiskMode()) ? slLot : fallback;
   if((InpAutoLotByRisk || ManagedRiskMode()) && atrCapActive) rawLot = MathMin(rawLot, atrLot);
   double lot = NormalizeOrderLot(rawLot, requireHalfSplit);
   if(lot <= 0) { detail = "risk_block lot_below_min raw=" + DoubleToString(rawLot,4); return 0; }
   double freeAfter = AccountFreeMarginCheck(Symbol(), type, lot);
   double marginUsedPct = (AccountEquity() > 0) ? (AccountEquity() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   double incrementalMarginPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   double singleMarginLimitPct = SingleTradeMarginLimitPct();
   string clampDetail = "";
   if(freeAfter <= 0 || (EffMaxMarginUsagePct() > 0 && marginUsedPct > EffMaxMarginUsagePct()) || (singleMarginLimitPct > 0.0 && incrementalMarginPct > singleMarginLimitPct))
   {
      double clamped = ClampLotToMargin(lot, type, requireHalfSplit, clampDetail);
      if(clamped <= 0) { detail = "risk_block margin lot=" + DoubleToString(lot,3) + " " + clampDetail; return 0; }
      lot = clamped;
      freeAfter = AccountFreeMarginCheck(Symbol(), type, lot);
      marginUsedPct = (AccountEquity() > 0) ? (AccountEquity() - freeAfter) / AccountEquity() * 100.0 : 0.0;
      incrementalMarginPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   }
   double projectedRisk = riskPerLot * lot;
   double projectedAtrExposure = dailyMoneyPerLot * lot;
   detail = "risk_engine=on lot=" + DoubleToString(lot,3)
      + " risk_capital=" + DoubleToString(cap,2)
      + " budget=" + DoubleToString(budget,2)
      + " risk_per_lot=" + DoubleToString(riskPerLot,2)
      + " sl_lot=" + DoubleToString(slLot,3)
      + " atr_cap_active=" + (atrCapActive ? "true" : "false")
      + " daily_atr=" + DoubleToString(dailyAtr,Digits)
      + " daily_money_per_lot=" + DoubleToString(dailyMoneyPerLot,2)
      + " atr_budget=" + DoubleToString(atrBudget,2)
      + " atr_lot=" + DoubleToString(atrLot,3)
      + " projected_risk=" + DoubleToString(projectedRisk,2)
      + " projected_atr_exposure=" + DoubleToString(projectedAtrExposure,2)
      + " open_risk=" + DoubleToString(openRisk,2)
      + " margin_pct=" + DoubleToString(marginUsedPct,2)
      + " incremental_margin_pct=" + DoubleToString(incrementalMarginPct,2)
      + " single_margin_limit_pct=" + DoubleToString(singleMarginLimitPct,2)
      + " daily_loss_pct=" + DoubleToString(daily,2)
      + " total_dd_pct=" + DoubleToString(dd,2)
      + (clampDetail == "" ? "" : " " + clampDetail);
   return lot;
}

double SingleTradeMarginLimitPct()
{
   double limit = InpMaxSingleTradeMarginPct;
   if(limit <= 0.0 && InpMinConcurrentTradeSlots > 0)
      limit = 100.0 / MathMax(1, InpMinConcurrentTradeSlots);
   if(limit <= 0.0) return 0.0;
   return MathMax(0.1, MathMin(100.0, limit));
}

bool IsMarginAcceptable(double lot, int type, double &freeAfter, double &marginUsedPct)
{
   ResetLastError();
   double freeBefore = AccountFreeMargin();
   freeAfter = AccountFreeMarginCheck(Symbol(), type, lot);
   marginUsedPct = (AccountEquity() > 0) ? (AccountEquity() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   if(freeAfter <= 0) return false;
   if(EffMaxMarginUsagePct() > 0 && marginUsedPct > EffMaxMarginUsagePct()) return false;
   double singleLimit = SingleTradeMarginLimitPct();
   if(singleLimit > 0.0 && AccountEquity() > 0.0)
   {
      double incrementalPct = MathMax(0.0, freeBefore - freeAfter) / AccountEquity() * 100.0;
      if(incrementalPct > singleLimit) return false;
   }
   return true;
}

double ClampLotToMargin(double requestedLot, int type, bool requireHalfSplit, string &detail)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;

   double freeAfter, marginPct;
   if(IsMarginAcceptable(requestedLot, type, freeAfter, marginPct))
   {
      double incPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
      detail = "margin_ok requested=" + DoubleToString(requestedLot, 3) + " margin_pct=" + DoubleToString(marginPct, 2) + " incremental_margin_pct=" + DoubleToString(incPct, 2) + " single_margin_limit_pct=" + DoubleToString(SingleTradeMarginLimitPct(), 2);
      return requestedLot;
   }

   double lo = minLot;
   double hi = requestedLot;
   double best = 0.0;
   double bestMargin = 0.0;
   for(int i = 0; i < 32; i++)
   {
      double mid = NormalizeOrderLot((lo + hi) / 2.0, requireHalfSplit);
      if(mid < minLot || mid <= 0) { hi = (lo + hi) / 2.0; continue; }
      if(IsMarginAcceptable(mid, type, freeAfter, marginPct))
      {
         best = mid;
         bestMargin = marginPct;
         lo = mid + step;
      }
      else hi = mid - step;
   }

   best = NormalizeOrderLot(best, requireHalfSplit);
   if(best > 0 && IsMarginAcceptable(best, type, freeAfter, marginPct))
   {
      double incPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
      detail = "margin_clamped requested=" + DoubleToString(requestedLot, 3) + " final=" + DoubleToString(best, 3) + " margin_pct=" + DoubleToString(marginPct, 2) + " incremental_margin_pct=" + DoubleToString(incPct, 2) + " single_margin_limit_pct=" + DoubleToString(SingleTradeMarginLimitPct(), 2);
      return best;
   }

   detail = "margin_unavailable requested=" + DoubleToString(requestedLot, 3) + " min_lot=" + DoubleToString(minLot, 3) + " last_margin_pct=" + DoubleToString(bestMargin, 2);
   return 0.0;
}

double MoneyRiskPerLot(double entry, double sl)
{
   return MoneyRiskPerLotForSymbol(Symbol(), entry, sl);
}

double MoneyRiskPerLotForSymbol(string symbol, double entry, double sl)
{
   return MoneyMovePerLotForSymbol(symbol, MathAbs(entry - sl));
}

double MoneyMovePerLot(double priceMove)
{
   return MoneyMovePerLotForSymbol(Symbol(), priceMove);
}

double MoneyMovePerLotForSymbol(string symbol, double priceMove)
{
   double tickSize = MarketInfo(symbol, MODE_TICKSIZE), tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   if(priceMove <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0) return 0.0;
   return priceMove / tickSize * tickValue;
}

double ClosedDailyAtr(string symbol, int period)
{
   int atrPeriod = MathMax(2, period);
   double atr = iATR(symbol, PERIOD_D1, atrPeriod, 1);
   return (MathIsValidNumber(atr) && atr > 0.0) ? atr : 0.0;
}

double NormalizeOrderLot(double lot, bool requireHalfSplit)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT), maxLot = MarketInfo(Symbol(), MODE_MAXLOT), step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / step + 0.0000001) * step;
   if(requireHalfSplit)
   {
      double half = MathFloor((lot / 2.0) / step + 0.0000001) * step;
      if(half < minLot) return 0;
   }
   return NormalizeDouble(lot, 2);
}

double NormalizeCloseLots(double lot)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT), step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;
   lot = MathFloor(lot / step + 0.0000001) * step;
   if(lot < minLot) return 0;
   return NormalizeDouble(lot, 2);
}

string RiskKey(string kind) { return "ProRenkoBridgeRisk|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + IntegerToString(Period()) + "|" + IntegerToString(EffectiveMagic()) + "|" + kind; }

double InitialBalance()
{
   if(InpInitialBalanceOverride > 0) return InpInitialBalanceOverride;
   string key = RiskKey("INITIAL_BALANCE");
   if(!GlobalVariableCheck(key) || GlobalVariableGet(key) <= 0) GlobalVariableSet(key, AccountBalance());
   return GlobalVariableGet(key);
}

datetime GmtDayStart()
{
   datetime now = TimeGMT();
   datetime today0 = now - TimeHour(now) * 3600 - TimeMinute(now) * 60 - TimeSeconds(now);
   datetime reset = today0 + MathMax(0, MathMin(23, InpDayResetHourGmt)) * 3600;
   if(now < reset) reset -= 86400;
   return reset;
}

double ChartClosedPnlToday()
{
   datetime dayStart = GmtDayStart();
   double pnl = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      if(OrderCloseTime() < dayStart) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return pnl;
}

bool DailyProfitLossGuardReached(string &reason, string &detail)
{
   reason = "";
   detail = "daily_guard_off";
   double pnl = ChartClosedPnlToday();
   double profitTarget = MathMax(0.0, g_dailyProfitTargetRuntime);
   double lossTarget = MathMax(0.0, g_dailyLossTargetRuntime);
   if(profitTarget > 0.0 && pnl >= profitTarget - 0.0001)
   {
      reason = "daily_profit_target_reached";
      detail = "chart_daily_profit=" + DoubleToString(pnl, 2)
             + " target=" + DoubleToString(profitTarget, 2)
             + " symbol=" + Symbol()
             + " tf=" + IntegerToString(Period())
             + " reset_hour_gmt=" + IntegerToString(MathMax(0, MathMin(23, InpDayResetHourGmt)));
      return true;
   }
   double loss = MathMax(0.0, -pnl);
   if(lossTarget > 0.0 && loss >= lossTarget - 0.0001)
   {
      reason = "daily_loss_target_reached";
      detail = "chart_daily_pnl=" + DoubleToString(pnl, 2)
             + " loss=" + DoubleToString(loss, 2)
             + " target=" + DoubleToString(lossTarget, 2)
             + " symbol=" + Symbol()
             + " tf=" + IntegerToString(Period())
             + " reset_hour_gmt=" + IntegerToString(MathMax(0, MathMin(23, InpDayResetHourGmt)));
      return true;
   }
   detail = "chart_daily_pnl=" + DoubleToString(pnl, 2)
          + " profit_target=" + (profitTarget > 0.0 ? DoubleToString(profitTarget, 2) : "off")
          + " loss_target=" + (lossTarget > 0.0 ? DoubleToString(lossTarget, 2) : "off");
   return false;
}
void AccountRiskMetrics(double &riskCapital, double &dailyLossPct, double &totalDdPct)
{
   double initial = MathMax(1, InitialBalance());
   double closedAll = 0, closedToday = 0, floating = 0;
   datetime dayStart = GmtDayStart();
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      closedAll += pnl;
      if(OrderCloseTime() >= dayStart) closedToday += pnl;
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      floating += OrderProfit() + OrderSwap() + OrderCommission();
   }
   riskCapital = MathMax(1, initial + closedAll + floating);
   dailyLossPct = MathMax(0, -(closedToday + floating) / initial * 100.0);
   totalDdPct = MathMax(0, -(closedAll + floating) / initial * 100.0);
}

bool RiskOrderInScope(string sym, int magic)
{
   if(!InpRiskScopeByMagic) return true;
   if(IsOurMagic(magic)) return true;
   string comment = OrderComment();
   if(StringFind(comment, "ProRenkoBridge") == 0) return true;
   return false;
}

double CurrentOpenRisk()
{
   double total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      int ot = OrderType();
      if(ot != OP_BUY && ot != OP_SELL && ot != OP_BUYLIMIT && ot != OP_SELLLIMIT && ot != OP_BUYSTOP && ot != OP_SELLSTOP) continue;
      if(OrderStopLoss() <= 0) continue;
      total += MoneyRiskPerLotForSymbol(OrderSymbol(), OrderOpenPrice(), OrderStopLoss()) * OrderLots();
   }
   return total;
}

void LiquidateScoped(string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      string osym = OrderSymbol();
      double px = (type == OP_BUY) ? MarketInfo(osym, MODE_BID) : MarketInfo(osym, MODE_ASK);
      if(px <= 0.0) continue;
      int ticket = OrderTicket();
      bool ok = OrderClose(OrderTicket(), OrderLots(), px, InpSlippage, clrRed);
      if(ok) TicketGVSet(ticket, "CLOSED", 1.0);
      Audit(ok ? "risk_liquidation_close_done" : "risk_liquidation_close_failed", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), px, OrderStopLoss(), OrderTakeProfit(), reason, OrderProfit(), "");
   }
}

int CurrentSpreadPoints() { RefreshRates(); return (int)MathRound((Ask - Bid) / Point); }

bool IsInAllowedWindow(datetime t, string windows) { string w = Trim(windows); if(w == "") return true; return IsInWindowList(t, w); }
bool IsInNoTradeWindow(datetime t, string windows) { string w = Trim(windows); if(w == "") return false; return IsInWindowList(t, w); }

bool IsInUtcEventBlock(datetime t, string times, int radiusMinutes)
{
   string raw = Trim(times);
   if(raw == "" || radiusMinutes <= 0) return false;
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   int cur = TimeHour(t) * 60 + TimeMinute(t);
   string parts[];
   int n = StringSplit(raw, ',', parts);
   for(int i = 0; i < n; i++)
   {
      int center = ParseHHMM(parts[i]);
      if(center < 0) continue;
      int diff = (int)MathAbs(cur - center);
      diff = MathMin(diff, 1440 - diff);
      if(diff <= radiusMinutes) return true;
   }
   return false;
}

string UtcEventBlockStatus(datetime t)
{
   return "utc_event_block='" + g_utcEventBlockTimesRuntime + "' radius_min=" + IntegerToString(g_utcEventBlockRadiusRuntime) + " now=" + TimeToString(t, TIME_MINUTES);
}

bool IsInWindowList(datetime t, string windows)
{
   string parts[];
   int n = StringSplit(windows, ',', parts);
   int cur = TimeHour(t) * 60 + TimeMinute(t);
   for(int i = 0; i < n; i++)
   {
      string p = Trim(parts[i]);
      int dash = StringFind(p, "-");
      if(dash <= 0) continue;
      int a = ParseHHMM(StringSubstr(p, 0, dash));
      int b = ParseHHMM(StringSubstr(p, dash + 1));
      if(a < 0 || b < 0) continue;
      if(a <= b) { if(cur >= a && cur <= b) return true; }
      else { if(cur >= a || cur <= b) return true; }
   }
   return false;
}

int ParseHHMM(string s)
{
   s = Trim(s);
   int colon = StringFind(s, ":");
   if(colon < 0) return -1;
   int h = (int)StringToInteger(StringSubstr(s, 0, colon));
   int m = (int)StringToInteger(StringSubstr(s, colon + 1));
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
}

string Trim(string s) { StringTrimLeft(s); StringTrimRight(s); return s; }

void StoreTicket(int ticket, double tp1, double tp2, double tp3, double half, int halfIdx, int targetIdx, bool fallbackLevels)
{
   TicketGVSet(ticket, "TP1", tp1); TicketGVSet(ticket, "TP2", tp2); TicketGVSet(ticket, "TP3", tp3);
   TicketGVSet(ticket, "HTP", half); TicketGVSet(ticket, "HIDX", halfIdx); TicketGVSet(ticket, "TIDX", targetIdx); TicketGVSet(ticket, "HDONE", 0);
   TicketGVSet(ticket, "HBR", g_halfRRuntime);
   TicketGVSet(ticket, "TR", g_targetRRuntime);
   TicketGVSet(ticket, "FB", fallbackLevels ? 1.0 : 0.0);
   TicketGVSet(ticket, "ENRICH", 0.0);
   TicketGVSet(ticket, "OPENED", 1.0);
   double openPx = 0.0;
   if(OrderSelect(ticket, SELECT_BY_TICKET))
      openPx = OrderOpenPrice();
   TicketGVSet(ticket, "MFE", 0.0);
   TicketGVSet(ticket, "MAE", 0.0);
   TicketGVSet(ticket, "MFE_PX", openPx);
   TicketGVSet(ticket, "MAE_PX", openPx);
   TicketGVSet(ticket, "MFE_TS", TimeCurrent());
   TicketGVSet(ticket, "MAE_TS", TimeCurrent());
}
int FindPartialCloseRemainderTicket(int oldTicket, int type, double oldOpenPrice, double expectedLots)
{
   RefreshRates();
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep <= 0.0) lotStep = 0.01;
   double lotTolerance = MathMax(lotStep * 1.5, 0.0000001);
   double priceTolerance = MathMax(TickSizePrice() * 4.0, Point * 4.0);

   for(int pass = 0; pass < 8; pass++)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderTicket() == oldTicket) continue;
         if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
         if(OrderType() != type) continue;
         if(expectedLots > 0.0 && MathAbs(OrderLots() - expectedLots) > lotTolerance) continue;
         if(MathAbs(OrderOpenPrice() - oldOpenPrice) > priceTolerance) continue;
         return OrderTicket();
      }
      Sleep(100);
      RefreshRates();
   }
   return -1;
}

void TransferTicketState(int oldTicket, int newTicket, string reason)
{
   if(newTicket <= 0 || newTicket == oldTicket) return;
   string fields[17] = {"TP1", "TP2", "TP3", "HTP", "HIDX", "TIDX", "HBR", "TR", "HDONE", "FB", "ENRICH", "MFE", "MAE", "MFE_PX", "MAE_PX", "MFE_TS", "MAE_TS"};
   for(int i = 0; i < 17; i++)
      TicketGVSet(newTicket, fields[i], TicketGV(oldTicket, fields[i], 0.0));
   TicketGVSet(newTicket, "OPENED", 1.0);
   TicketGVSet(oldTicket, "CLOSED", 1.0);
   Audit("ticket_state_transferred", TicketEvent(oldTicket), newTicket, "", OrderLots(), OrderOpenPrice(), OrderStopLoss(), OrderTakeProfit(), "old_ticket=" + IntegerToString(oldTicket) + " new_ticket=" + IntegerToString(newTicket) + " reason=" + reason, OrderProfit(), "partial_close_remainder_tracking");
}

string TicketKey(int ticket, string field) { return "ProRenkoBridge|" + IntegerToString(AccountNumber()) + "|" + IntegerToString(ticket) + "|" + field; }
double TicketGV(int ticket, string field, double def) { string key = TicketKey(ticket, field); if(!GlobalVariableCheck(key)) return def; return GlobalVariableGet(key); }
void TicketGVSet(int ticket, string field, double value) { GlobalVariableSet(TicketKey(ticket, field), value); }
string TicketEvent(int ticket) { return "ticket=" + IntegerToString(ticket); }

void UpdateTicketExcursion(int ticket, double px)
{
   if(ticket <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET))
      return;
   double pnl = OrderProfit() + OrderSwap() + OrderCommission();
   double mfe = TicketGV(ticket, "MFE", 0.0);
   double mae = TicketGV(ticket, "MAE", 0.0);
   if(pnl > mfe)
   {
      TicketGVSet(ticket, "MFE", pnl);
      TicketGVSet(ticket, "MFE_PX", px);
      TicketGVSet(ticket, "MFE_TS", TimeCurrent());
   }
   if(pnl < mae)
   {
      TicketGVSet(ticket, "MAE", pnl);
      TicketGVSet(ticket, "MAE_PX", px);
      TicketGVSet(ticket, "MAE_TS", TimeCurrent());
   }
}

string TicketExcursionDetail(int ticket)
{
   return " mfe=" + DoubleToString(TicketGV(ticket, "MFE", 0.0), 2)
      + " mae=" + DoubleToString(TicketGV(ticket, "MAE", 0.0), 2)
      + " mfe_px=" + PriceText(TicketGV(ticket, "MFE_PX", 0.0))
      + " mae_px=" + PriceText(TicketGV(ticket, "MAE_PX", 0.0))
      + " mfe_time=" + TimeToString((datetime)TicketGV(ticket, "MFE_TS", 0.0), TIME_DATE|TIME_SECONDS)
      + " mae_time=" + TimeToString((datetime)TicketGV(ticket, "MAE_TS", 0.0), TIME_DATE|TIME_SECONDS);
}

void MaybeRiskAudit()
{
   if(!g_auditRuntime || !EffectiveRiskEnabled() || InpRiskAuditSeconds <= 0) return;
   datetime now = TimeGMT();
   if(now - g_lastRiskAuditTs < InpRiskAuditSeconds) return;
   g_lastRiskAuditTs = now;
   RiskAudit("snapshot", "periodic");
}

void MaybeProbe()
{
   if(!g_auditRuntime || InpPositionProbeSeconds <= 0) return;
   datetime now = TimeGMT();
   if(now - g_lastProbeTs < InpPositionProbeSeconds) return;
   g_lastProbeTs = now;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      double live = (type == OP_BUY) ? Bid : Ask;
      double risk = MathAbs(OrderOpenPrice() - OrderStopLoss());
      double r = (risk > 0) ? ((type == OP_BUY ? live - OrderOpenPrice() : OrderOpenPrice() - live) / risk) : 0;
      Audit("position_probe", TicketEvent(OrderTicket()), OrderTicket(), (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), live, OrderStopLoss(), OrderTakeProfit(), "r=" + DoubleToString(r, 3) + " spread=" + IntegerToString(CurrentSpreadPoints()), OrderProfit(), "");
   }
}

void MaybeLifecycleAudit()
{
   if(!g_auditRuntime || InpLifecycleAuditSeconds <= 0) return;
   datetime now = TimeGMT();
   if(now - g_lastLifecycleAuditTs < InpLifecycleAuditSeconds) return;
   g_lastLifecycleAuditTs = now;
   AuditClosedHistoryTickets();
}

void AuditClosedHistoryTickets()
{
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      int ticket = OrderTicket();
      if(TicketGV(ticket, "CLOSED", 0.0) > 0.5) continue;
      bool tracked = (TicketGV(ticket, "OPENED", 0.0) > 0.5 || StringFind(OrderComment(), "ProRenkoBridge") == 0);
      if(!tracked) continue;

      string eventName = ClassifyClosedOrder(type, OrderClosePrice(), OrderStopLoss(), OrderTakeProfit());
      string dir = (type == OP_BUY ? "BUY" : "SELL");
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      string detail = "open_time=" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_SECONDS)
                    + " close_time=" + TimeToString(OrderCloseTime(), TIME_DATE|TIME_SECONDS)
                    + " open_price=" + PriceText(OrderOpenPrice())
                    + " close_price=" + PriceText(OrderClosePrice())
                    + " comment='" + OrderComment() + "'"
                    + TicketExcursionDetail(ticket);
      Audit(eventName, TicketEvent(ticket), ticket, dir, OrderLots(), OrderClosePrice(), OrderStopLoss(), OrderTakeProfit(), detail, pnl, "history_lifecycle_tracker");
      TicketGVSet(ticket, "CLOSED", 1.0);
   }
}

string ClassifyClosedOrder(int type, double closePrice, double sl, double tp)
{
   double tol = MathMax(TickSizePrice() * 2.0, Point * 2.0);
   if(type == OP_BUY)
   {
      if(sl > 0.0 && closePrice <= sl + tol) return "closed_by_broker_sl";
      if(tp > 0.0 && closePrice >= tp - tol) return "closed_by_broker_tp";
   }
   else
   {
      if(sl > 0.0 && closePrice >= sl - tol) return "closed_by_broker_sl";
      if(tp > 0.0 && closePrice <= tp + tol) return "closed_by_broker_tp";
   }
   return "closed_by_unknown_manual";
}

void RiskAudit(string eventName, string detail)
{
   if(!g_auditRuntime) return;
   double cap, daily, dd;
   AccountRiskMetrics(cap, daily, dd);
   int h = FileOpen("ProRenkoBridge_AccountRiskAudit_" + DateStamp(TimeGMT()) + ".csv", FILE_CSV|FILE_READ|FILE_WRITE, ';');
   if(h == INVALID_HANDLE) return;
   bool header = (FileSize(h) == 0);
   FileSeek(h, 0, SEEK_END);
   if(header) FileWrite(h, "gmt", "broker", "account", "symbol", "tf", "event", "risk_capital", "open_risk", "daily_loss_pct", "total_dd_pct", "enabled", "detail");
   FileWrite(h, TimeToString(TimeGMT(), TIME_DATE|TIME_SECONDS), TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), AccountNumber(), Symbol(), Period(), eventName, DoubleToString(cap, 2), DoubleToString(CurrentOpenRisk(), 2), DoubleToString(daily, 3), DoubleToString(dd, 3), EffectiveRiskEnabled() ? "true" : "false", detail);
   FileClose(h);
}

bool IsCriticalAuditEvent(string eventName)
{
   return StringFind(eventName, "order_failed") >= 0
          || StringFind(eventName, "trade_blocked_trade_disabled") >= 0
          || StringFind(eventName, "trade_blocked_broker_stops") >= 0
          || StringFind(eventName, "trade_blocked_geometry") >= 0
          || StringFind(eventName, "trade_blocked_risk") >= 0
          || StringFind(eventName, "trade_blocked_window") >= 0
          || StringFind(eventName, "trade_blocked_spread") >= 0
          || StringFind(eventName, "trade_blocked_same_direction") >= 0
          || StringFind(eventName, "trade_blocked_disabled") >= 0
          || StringFind(eventName, "trade_blocked_daily_profit_loss_target") >= 0
          || StringFind(eventName, "trade_blocked_reverse_close_failed") >= 0
          || StringFind(eventName, "reverse_close_failed") >= 0
          || StringFind(eventName, "reverse_delete_failed") >= 0
          || StringFind(eventName, "broker_stop_adjusted") >= 0
          || StringFind(eventName, "stopguard") >= 0
          || StringFind(eventName, "basket_order_failed") >= 0
          || StringFind(eventName, "basket_reverse_close_failed") >= 0
          || StringFind(eventName, "basket_reverse_delete_failed") >= 0
          || StringFind(eventName, "basket_target_hit_close") >= 0
          || StringFind(eventName, "basket_loss_hit_close") >= 0
          || StringFind(eventName, "basket_session_close") >= 0
          || StringFind(eventName, "basket_blocked_day_done") >= 0;
}

string WeekdayName(datetime t)
{
   int d = TimeDayOfWeek(t);
   if(d == 0) return "Sunday";
   if(d == 1) return "Monday";
   if(d == 2) return "Tuesday";
   if(d == 3) return "Wednesday";
   if(d == 4) return "Thursday";
   if(d == 5) return "Friday";
   if(d == 6) return "Saturday";
   return "";
}

string SessionBucket(datetime gmt)
{
   int m = TimeHour(gmt) * 60 + TimeMinute(gmt);
   if(m >= 0 && m < 420) return "asia";
   if(m >= 420 && m < 720) return "london";
   if(m >= 720 && m < 900) return "london_ny_overlap";
   if(m >= 900 && m < 1260) return "ny";
   return "rollover";
}

string MlDayKey(datetime t)
{
   return DateStamp(t);
}

void MlRegisterSignal(string dir, datetime signalTime)
{
   datetime t = signalTime > 0 ? signalTime : TimeGMT();
   string day = MlDayKey(t);
   if(g_mlTradeIndexDayKey != day)
   {
      g_mlTradeIndexDayKey = day;
      g_mlTradeIndexOfDay = 0;
   }
   g_mlPreviousSignalDir = g_lastSignalDir;
   g_mlPreviousSignalTime = g_lastSignalTime;
   if((g_lastSignalDir == "BUY" || g_lastSignalDir == "SELL") && (dir == "BUY" || dir == "SELL") && g_lastSignalDir != dir)
   {
      g_mlFlipTimes[g_mlFlipWriteIdx % 128] = TimeGMT();
      g_mlFlipWriteIdx++;
   }
   if(dir == "BUY" || dir == "SELL")
      g_mlTradeIndexOfDay++;
}

int MlFlipCountLastHour()
{
   datetime cutoff = TimeGMT() - 3600;
   int n = 0;
   for(int i = 0; i < 128; i++)
      if(g_mlFlipTimes[i] > cutoff) n++;
   return n;
}

string MlBool(bool v) { return v ? "1" : "0"; }

string MlTfLabel(int tf)
{
   if(tf == 0) tf = Period();
   if(tf == PERIOD_M1) return "M1";
   if(tf == PERIOD_M5) return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1) return "H1";
   if(tf == PERIOD_H4) return "H4";
   if(tf == PERIOD_D1) return "D1";
   if(tf == PERIOD_W1) return "W1";
   if(tf == PERIOD_MN1) return "MN1";
   return IntegerToString(tf);
}

double MlAtrPips(int tf, int period)
{
   double pip = SymbolPipSize();
   int p = MathMax(2, period);
   double atr = iATR(Symbol(), tf, p, 1);
   if(!MathIsValidNumber(atr) || atr <= 0.0 || pip <= 0.0) return 0.0;
   return atr / pip;
}

double MlRsi14()
{
   double rsi = iRSI(Symbol(), Period(), 14, PRICE_CLOSE, 1);
   if(!MathIsValidNumber(rsi) || rsi < 0.0 || rsi > 100.0) return 0.0;
   return rsi;
}

double MlPipsBetween(double a, double b)
{
   double pip = SymbolPipSize();
   if(pip <= 0.0 || a <= 0.0 || b <= 0.0) return 0.0;
   return MathAbs(a - b) / pip;
}

double MlSignedPips(string dir, double entry, double exitPx)
{
   double pip = SymbolPipSize();
   if(pip <= 0.0 || entry <= 0.0 || exitPx <= 0.0) return 0.0;
   if(dir == "BUY") return (exitPx - entry) / pip;
   if(dir == "SELL") return (entry - exitPx) / pip;
   return 0.0;
}

string MlRejectReason(string eventName, string detail, string extra)
{
   string src = eventName + " " + detail + " " + extra;
   string u = StringUpperCopy(src);
   if(StringFind(u, "MARKET") >= 0 && StringFind(u, "CLOSED") >= 0) return "market_closed";
   if(StringFind(u, "NOT ENOUGH") >= 0 || StringFind(u, "NO_MONEY") >= 0 || StringFind(u, "MONEY") >= 0) return "not_enough_money";
   if(StringFind(u, "SPREAD") >= 0) return "spread";
   if(StringFind(u, "WINDOW") >= 0) return "time_window";
   if(StringFind(u, "RISK") >= 0 || StringFind(u, "LOT") >= 0) return "risk_lot";
   if(StringFind(u, "BROKER_STOPS") >= 0 || StringFind(u, "STOP") >= 0 || StringFind(u, "130") >= 0) return "broker_stops";
   if(StringFind(u, "GEOMETRY") >= 0) return "geometry";
   if(StringFind(u, "REVERSE_CLOSE") >= 0) return "reverse_close";
   if(StringFind(eventName, "failed") >= 0 || StringFind(eventName, "blocked") >= 0) return eventName;
   return "";
}

string MlExitReason(string eventName, string extra)
{
   if(extra != "") return extra;
   if(StringFind(eventName, "tp") >= 0 || StringFind(eventName, "target") >= 0) return "target";
   if(StringFind(eventName, "sl") >= 0 || StringFind(eventName, "loss") >= 0) return "loss";
   if(StringFind(eventName, "reverse") >= 0) return "reverse";
   if(StringFind(eventName, "manual") >= 0 || StringFind(eventName, "unknown") >= 0) return "manual_or_unknown";
   return eventName;
}

int MlBarsBetween(datetime a, datetime b)
{
   if(a <= 0 || b <= 0 || b < a) return 0;
   int sec = Period() * 60;
   if(sec <= 0) sec = 60;
   return (int)MathFloor((b - a) / sec);
}

void MlTicketMetrics(int ticket, string dir, double price, double sl, double tp, double &entry, double &slPips, double &tpPips, double &rr, double &pnlPips, double &pnlR, double &mfePips, double &maePips, string &mfeBeforeMae, int &barsToMfe, int &barsToMae, int &barsToExit)
{
   entry = price;
   datetime openTime = 0;
   if(ticket > 0)
   {
      if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES) || OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
      {
         entry = OrderOpenPrice();
         openTime = OrderOpenTime();
      }
   }
   slPips = MlPipsBetween(entry, sl);
   tpPips = MlPipsBetween(entry, tp);
   rr = slPips > 0.0 && tpPips > 0.0 ? tpPips / slPips : 0.0;
   pnlPips = MlSignedPips(dir, entry, price);
   pnlR = slPips > 0.0 ? pnlPips / slPips : 0.0;

   double mfePx = ticket > 0 ? TicketGV(ticket, "MFE_PX", 0.0) : 0.0;
   double maePx = ticket > 0 ? TicketGV(ticket, "MAE_PX", 0.0) : 0.0;
   mfePips = MathMax(0.0, MlSignedPips(dir, entry, mfePx));
   maePips = MathMax(0.0, -MlSignedPips(dir, entry, maePx));
   datetime mfeTs = ticket > 0 ? (datetime)TicketGV(ticket, "MFE_TS", 0.0) : 0;
   datetime maeTs = ticket > 0 ? (datetime)TicketGV(ticket, "MAE_TS", 0.0) : 0;
   if(mfeTs > 0 && maeTs > 0) mfeBeforeMae = (mfeTs <= maeTs ? "1" : "0");
   else mfeBeforeMae = "";
   barsToMfe = MlBarsBetween(openTime, mfeTs);
   barsToMae = MlBarsBetween(openTime, maeTs);
   barsToExit = MlBarsBetween(openTime, TimeCurrent());
}

void Audit(string eventName, string eventId, int ticket, string dir, double lot, double price, double sl, double tp, string detail, double pnl, string extra)
{
   if(!g_auditRuntime && !IsCriticalAuditEvent(eventName)) return;
   datetime gmt = TimeGMT();
   datetime broker = TimeCurrent();
   double mlEntry, slPips, tpPips, rr, pnlPips, pnlR, mfePips, maePips;
   string mfeBeforeMae;
   int barsToMfe, barsToMae, barsToExit;
   MlTicketMetrics(ticket, dir, price, sl, tp, mlEntry, slPips, tpPips, rr, pnlPips, pnlR, mfePips, maePips, mfeBeforeMae, barsToMfe, barsToMae, barsToExit);
   double prevAgeMin = (g_mlPreviousSignalTime > 0 ? MathMax(0.0, (double)(gmt - g_mlPreviousSignalTime) / 60.0) : 0.0);
   double atrPips = MlAtrPips(Period(), InpRiskAtrPeriod);
   double dailyAtrPips = MlAtrPips(PERIOD_D1, InpAccountRiskDailyAtrPeriod);
   double slAtrRatio = atrPips > 0.0 && slPips > 0.0 ? slPips / atrPips : 0.0;
   double tpAtrRatio = atrPips > 0.0 && tpPips > 0.0 ? tpPips / atrPips : 0.0;
   double basketTargetAtrRatio = atrPips > 0.0 && g_basketTargetPipsRuntime > 0.0 ? g_basketTargetPipsRuntime / atrPips : 0.0;
   double spreadPips = SymbolPipSize() > 0.0 ? (CurrentSpreadPoints() * Point / SymbolPipSize()) : 0.0;
   double spreadToSlRatio = slPips > 0.0 ? spreadPips / slPips : 0.0;
   int h = FileOpen("ProRenkoBridge_DirectAudit_" + DateStamp(gmt) + ".csv", FILE_CSV|FILE_READ|FILE_WRITE, ';');
   if(h == INVALID_HANDLE) return;
   bool header = (FileSize(h) == 0);
   FileSeek(h, 0, SEEK_END);
   if(header) FileWrite(h, "gmt", "broker", "account", "symbol", "tf", "event", "event_id", "ticket", "dir", "lot", "price", "sl", "tp", "spread_points", "pnl", "detail", "extra", "gmt_weekday", "broker_weekday", "hour_gmt", "hour_broker", "session_bucket", "trade_index_of_day", "previous_signal_dir", "previous_signal_age_min", "flip_count_last_1h", "sl_pips", "tp_pips", "rr", "pnl_pips", "pnl_r", "mfe_pips", "mae_pips", "mfe_before_mae", "bars_to_mfe", "bars_to_mae", "bars_to_exit", "exit_reason", "invert_on", "exec_mode_sh0_sh1_sh2", "basket_target_pips", "native_ignore_windows_on", "bridge_published", "listener_result", "reject_reason_normalized", "atr_pips", "atr_period", "atr_tf", "daily_atr_pips", "sl_atr_ratio", "tp_atr_ratio", "basket_target_atr_ratio", "rsi14", "spread_to_sl_ratio");
   FileWrite(h, TimeToString(gmt, TIME_DATE|TIME_SECONDS), TimeToString(broker, TIME_DATE|TIME_SECONDS), AccountNumber(), Symbol(), Period(), eventName, eventId, ticket, dir, DoubleToString(lot, 3), PriceText(price), PriceText(sl), PriceText(tp), CurrentSpreadPoints(), DoubleToString(pnl, 2), detail, extra,
      WeekdayName(gmt), WeekdayName(broker), TimeHour(gmt), TimeHour(broker), SessionBucket(gmt), g_mlTradeIndexOfDay, g_mlPreviousSignalDir, DoubleToString(prevAgeMin, 2), MlFlipCountLastHour(),
      DoubleToString(slPips, 2), DoubleToString(tpPips, 2), DoubleToString(rr, 3), DoubleToString(pnlPips, 2), DoubleToString(pnlR, 3), DoubleToString(mfePips, 2), DoubleToString(maePips, 2), mfeBeforeMae,
      barsToMfe, barsToMae, barsToExit, MlExitReason(eventName, extra), MlBool(g_invertMode), TrendExecModeLabel(), DoubleToString(g_basketTargetPipsRuntime, 2), MlBool(g_nativeIgnoreWindowsRuntime), (StringFind(detail, "bridge_csv_written=1") >= 0 ? "1" : "0"), eventName, MlRejectReason(eventName, detail, extra),
      DoubleToString(atrPips, 2), InpRiskAtrPeriod, MlTfLabel(Period()), DoubleToString(dailyAtrPips, 2), DoubleToString(slAtrRatio, 3), DoubleToString(tpAtrRatio, 3), DoubleToString(basketTargetAtrRatio, 3), DoubleToString(MlRsi14(), 2), DoubleToString(spreadToSlRatio, 4));
   FileClose(h);
}

string DateStamp(datetime t) { return StringSubstr(TimeToString(t, TIME_DATE),0,4) + StringSubstr(TimeToString(t, TIME_DATE),5,2) + StringSubstr(TimeToString(t, TIME_DATE),8,2); }
string PriceText(double v) { if(v <= 0) return "-"; return DoubleToString(v, Digits); }

string SafeFileToken(string s)
{
   string out = s;
   StringReplace(out, "\\", "_");
   StringReplace(out, "/", "_");
   StringReplace(out, ":", "_");
   StringReplace(out, "*", "_");
   StringReplace(out, "?", "_");
   StringReplace(out, "\"", "_");
   StringReplace(out, "<", "_");
   StringReplace(out, ">", "_");
   StringReplace(out, "|", "_");
   StringReplace(out, " ", "_");
   return out;
}

string ActiveSignalStateFileName()
{
   return InpActiveSignalStatePrefix + SafeFileToken(Symbol()) + "_" + IntegerToString(Period()) + ".csv";
}

string FileBridgeScopedLatestFileName()
{
   return "PRORENKOFileBridge_Latest_" + SafeFileToken(Symbol()) + "_" + IntegerToString(Period()) + ".csv";
}
int ActiveSignalStateFlags(int baseFlags)
{
   int flags = baseFlags | FILE_ANSI;
   if(InpActiveSignalUseCommonFiles)
      flags |= FILE_COMMON;
   return flags;
}

void ActiveSignalStateWrite(string dir, string eventId, double price, datetime signalTime, string reason)
{
   if(!InpActiveSignalStateEnabled || (dir != "BUY" && dir != "SELL"))
      return;
   string fileName = ActiveSignalStateFileName();
   int flags = ActiveSignalStateFlags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(fileName, flags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProRenkoBridge active_state open failed err=", GetLastError(), " file=", fileName);
      return;
   }
   FileWrite(h, "version", "written_gmt", "source_login", "symbol", "tf", "direction", "signal_time", "event_id", "price", "build", "reason");
   FileWrite(h,
      "1",
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      IntegerToString(AccountNumber()),
      Symbol(),
      IntegerToString(Period()),
      dir,
      TimeToString(signalTime, TIME_DATE | TIME_SECONDS),
      eventId,
      PriceText(price),
      BUILD_TAG,
      reason
   );
   FileClose(h);
}
string FileBridgeTime(datetime t)
{
   return (t > 0 ? TimeToString(t, TIME_DATE | TIME_SECONDS) : "");
}

int FileBridgeFlags(int baseFlags)
{
   int flags = baseFlags | FILE_ANSI;
   if(InpFileBridgeUseCommonFiles)
      flags |= FILE_COMMON;
   return flags;
}

void FileBridgeWriteHeader(int h)
{
   FileWrite(h,
      "version", "written_gmt", "source_login", "source_symbol", "source_tf", "event_id", "source", "direction",
      "signal_time", "bridge_entry", "sl", "tp", "half_trigger", "half_label", "source_build", "source_bid", "source_ask", "risk_pct", "trade_mode", "basket_target_pips", "basket_target_pct", "basket_max_loss_pips", "basket_catastrophic_sl_pips", "basket_close_on_reverse", "basket_close_session_end", "basket_session_end_time", "basket_day_key"
   );
}

void FileBridgeWriteRow(int h, string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   FileWrite(h,
      "1",
      FileBridgeTime(TimeGMT()),
      IntegerToString(AccountNumber()),
      Symbol(),
      IntegerToString(Period()),
      eventId,
      source,
      dir,
      FileBridgeTime(sourceSignalTime),
      PriceText(bridgeEntry),
      PriceText(sl),
      PriceText(tp),
      PriceText(halfTriggerPrice),
      halfTriggerLabel,
      BUILD_TAG,
      PriceText(Bid),
      PriceText(Ask),
      DoubleToString(EffAccountRiskPerTradePct(), 4),
      "traditional",
      "", "", "", "", "", "", "", ""
   );
}

void FileBridgeWriteInitMarker()
{
   if(!g_fileBridgeMt5Runtime)
      return;
   string eventId = "PRORENKO_init|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + IntegerToString(Period()) + "|" + IntegerToString((int)TimeGMT());
   int latestFlags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(InpFileBridgeLatestFile, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProRenkoBridge file_bridge init latest open failed err=", GetLastError(), " file=", InpFileBridgeLatestFile);
      return;
   }
   FileBridgeWriteHeader(h);
   FileBridgeWriteRow(h, eventId, "INIT", Bid, 0.0, 0.0, "bridge_initiated", 0.0, "init", TimeGMT());
   FileClose(h);
   FileBridgeWriteLatestTraditionalFile(FileBridgeScopedLatestFileName(), eventId, "INIT", Bid, 0.0, 0.0, "bridge_initiated", 0.0, "init", TimeGMT());

   string auditFile = InpFileBridgeAuditPrefix + DateStamp(TimeGMT()) + ".csv";
   int auditFlags = FileBridgeFlags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int a = FileOpen(auditFile, auditFlags, ',');
   if(a == INVALID_HANDLE)
   {
      Print("ProRenkoBridge file_bridge init audit open failed err=", GetLastError(), " file=", auditFile);
      return;
   }
   bool header = (FileSize(a) == 0);
   FileSeek(a, 0, SEEK_END);
   if(header) FileBridgeWriteHeader(a);
   FileBridgeWriteRow(a, eventId, "INIT", Bid, 0.0, 0.0, "bridge_initiated", 0.0, "init", TimeGMT());
   FileClose(a);
   Print("ProRenkoBridge file_bridge init marker wrote event=", eventId, " file=", InpFileBridgeLatestFile);
}

void FileBridgeWriteSignal(string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   if(!g_fileBridgeMt5Runtime)
      return;
   int latestFlags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(InpFileBridgeLatestFile, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProRenkoBridge file_bridge latest open failed err=", GetLastError(), " file=", InpFileBridgeLatestFile);
      return;
   }
   FileBridgeWriteHeader(h);
   FileBridgeWriteRow(h, eventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
   FileClose(h);
   FileBridgeWriteLatestTraditionalFile(FileBridgeScopedLatestFileName(), eventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);

   string auditFile = InpFileBridgeAuditPrefix + DateStamp(TimeGMT()) + ".csv";
   int auditFlags = FileBridgeFlags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int a = FileOpen(auditFile, auditFlags, ',');
   if(a == INVALID_HANDLE)
   {
      Print("ProRenkoBridge file_bridge audit open failed err=", GetLastError(), " file=", auditFile);
      return;
   }
   bool header = (FileSize(a) == 0);
   FileSeek(a, 0, SEEK_END);
   if(header) FileBridgeWriteHeader(a);
   FileBridgeWriteRow(a, eventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
   FileClose(a);
   Print("ProRenkoBridge file_bridge wrote event=", eventId, " dir=", dir, " source=", source, " file=", InpFileBridgeLatestFile);
}

void FileBridgeWriteBasketRow(int h, string eventId, string dir, double bridgeEntry, double catastrophicSl, string source, datetime sourceSignalTime)
{
   FileWrite(h,
      "1",
      FileBridgeTime(TimeGMT()),
      IntegerToString(AccountNumber()),
      Symbol(),
      IntegerToString(Period()),
      eventId,
      source,
      dir,
      FileBridgeTime(sourceSignalTime),
      PriceText(bridgeEntry),
      PriceText(catastrophicSl),
      "0",
      "0",
      "basket_off",
      BUILD_TAG,
      PriceText(Bid),
      PriceText(Ask),
      DoubleToString(EffAccountRiskPerTradePct(), 4),
      "basket_daily_target",
      DoubleToString(g_basketTargetPipsRuntime, 2),
      DoubleToString(g_basketTargetPctRuntime, 4),
      DoubleToString(g_basketMaxLossPipsRuntime, 2),
      DoubleToString(g_basketCatastrophicSlPipsRuntime, 2),
      g_basketCloseOnReverseRuntime ? "true" : "false",
      "false",
      "",
      BasketDayKey()
   );
}

bool FileBridgeWriteLatestTraditionalFile(string fileName, string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   int latestFlags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(fileName, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProRenkoBridge scoped latest open failed err=", GetLastError(), " file=", fileName);
      return(false);
   }
   FileBridgeWriteHeader(h);
   FileBridgeWriteRow(h, eventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
   FileClose(h);
   return(true);
}

bool FileBridgeWriteLatestBasketFile(string fileName, string eventId, string dir, double bridgeEntry, double catastrophicSl, string source, datetime sourceSignalTime)
{
   int latestFlags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(fileName, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProRenkoBridge basket scoped latest open failed err=", GetLastError(), " file=", fileName);
      return(false);
   }
   FileBridgeWriteHeader(h);
   FileBridgeWriteBasketRow(h, eventId, dir, bridgeEntry, catastrophicSl, source, sourceSignalTime);
   FileClose(h);
   return(true);
}
void FileBridgeWriteBasketSignal(string eventId, string dir, double bridgeEntry, double catastrophicSl, string source, datetime sourceSignalTime)
{
   if(!g_fileBridgeMt5Runtime)
      return;
   int latestFlags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(InpFileBridgeLatestFile, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProRenkoBridge basket file_bridge latest open failed err=", GetLastError(), " file=", InpFileBridgeLatestFile);
      return;
   }
   FileBridgeWriteHeader(h);
   FileBridgeWriteBasketRow(h, eventId, dir, bridgeEntry, catastrophicSl, source, sourceSignalTime);
   FileClose(h);
   FileBridgeWriteLatestBasketFile(FileBridgeScopedLatestFileName(), eventId, dir, bridgeEntry, catastrophicSl, source, sourceSignalTime);

   string auditFile = InpFileBridgeAuditPrefix + DateStamp(TimeGMT()) + ".csv";
   int auditFlags = FileBridgeFlags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int a = FileOpen(auditFile, auditFlags, ',');
   if(a == INVALID_HANDLE)
   {
      Print("ProRenkoBridge basket file_bridge audit open failed err=", GetLastError(), " file=", auditFile);
      return;
   }
   bool header = (FileSize(a) == 0);
   FileSeek(a, 0, SEEK_END);
   if(header) FileBridgeWriteHeader(a);
   FileBridgeWriteBasketRow(a, eventId, dir, bridgeEntry, catastrophicSl, source, sourceSignalTime);
   FileClose(a);
   Print("ProRenkoBridge basket file_bridge wrote event=", eventId, " dir=", dir, " source=", source, " file=", InpFileBridgeLatestFile);
}

void FileBridgeWriteBasketConfigMarker(string reason)
{
   if(!g_fileBridgeMt5Runtime)
      return;

   if(g_basketModeRuntime && g_lastSignalTime > 0 && (g_lastSignalDir == "BUY" || g_lastSignalDir == "SELL") && g_lastSignalPrice > 0.0)
   {
      if(!IsInUtcEventBlock(TimeGMT(), g_utcEventBlockTimesRuntime, g_utcEventBlockRadiusRuntime)
         && IsInAllowedWindow(TimeGMT(), g_allowedWindowsRuntime)
         && !IsInNoTradeWindow(TimeGMT(), g_noTradeWindowsRuntime)
         && (g_maxSpreadRuntime <= 0 || CurrentSpreadPoints() <= g_maxSpreadRuntime))
      {
         string dir = g_lastSignalDir;
         string eventId = (g_lastEventId != "") ? g_lastEventId : (Symbol() + "|" + IntegerToString(Period()) + "|prorenko_basket_config|" + dir + "|" + IntegerToString((int)g_lastSignalTime));
         if(g_invertMode)
         {
            dir = (dir == "BUY") ? "SELL" : "BUY";
            eventId = eventId + "|invert";
         }
         int type = (dir == "BUY") ? OP_BUY : OP_SELL;
         double entry = g_lastSignalPrice;
         double sl = 0.0;
         string geom = "";
         if(BuildBasketGeometry(type, entry, sl, geom))
         {
            double target = 0.0;
            string brokerGuard = "";
            double rawEntry = entry, rawSl = sl;
            if(PrepareBrokerOrderLevels(type, type, entry, sl, target, brokerGuard))
            {
               string source = "ProRenko|" + SignalSourceFromEvent(eventId) + "|basket|" + reason;
               if(g_invertMode) source += "|invert";
               FileBridgeWriteBasketSignal(eventId, dir, entry, sl, source, g_lastSignalTime);
               Print("ProRenkoBridge basket active config republished event=", eventId, " dir=", dir, " reason=", reason, " file=", InpFileBridgeLatestFile);
               return;
            }
            Print("ProRenkoBridge basket active config republish broker guard failed raw_entry=", DoubleToString(rawEntry, Digits), " raw_sl=", DoubleToString(rawSl, Digits), " detail=", brokerGuard);
         }
         else
         {
            Print("ProRenkoBridge basket active config republish geometry failed dir=", dir, " entry=", DoubleToString(entry, Digits), " detail=", geom);
         }
      }
   }

   string eventId = "PRORENKO_config|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + IntegerToString(Period()) + "|" + IntegerToString((int)TimeGMT());
   int latestFlags = FileBridgeFlags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(InpFileBridgeLatestFile, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProRenkoBridge basket config latest open failed err=", GetLastError(), " file=", InpFileBridgeLatestFile);
      return;
   }
   FileBridgeWriteHeader(h);
   FileBridgeWriteBasketRow(h, eventId, "INIT", Bid, 0.0, "bridge_config|" + reason, TimeGMT());
   FileClose(h);
   FileBridgeWriteLatestBasketFile(FileBridgeScopedLatestFileName(), eventId, "INIT", Bid, 0.0, "bridge_config|" + reason, TimeGMT());

   string auditFile = InpFileBridgeAuditPrefix + DateStamp(TimeGMT()) + ".csv";
   int auditFlags = FileBridgeFlags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int a = FileOpen(auditFile, auditFlags, ',');
   if(a != INVALID_HANDLE)
   {
      bool header = (FileSize(a) == 0);
      FileSeek(a, 0, SEEK_END);
      if(header) FileBridgeWriteHeader(a);
      FileBridgeWriteBasketRow(a, eventId, "INIT", Bid, 0.0, "bridge_config|" + reason, TimeGMT());
      FileClose(a);
   }

   Print("ProRenkoBridge basket config marker wrote target_pips=", DoubleToString(g_basketTargetPipsRuntime, 2),
      " target_pct=", DoubleToString(g_basketTargetPctRuntime, 4),
      " loss_pips=", DoubleToString(g_basketMaxLossPipsRuntime, 2),
      " cat_sl=", DoubleToString(g_basketCatastrophicSlPipsRuntime, 2),
      " file=", InpFileBridgeLatestFile);
}
string BufferHitSummary(string dir, int sh, int buf, double raw, datetime t)
{
   if(dir == "" || t <= 0)
      return "-";
   return dir + " sh=" + IntegerToString(sh) + " buf=" + IntegerToString(buf) + " raw=" + DoubleToString(raw, Digits) + " @ " + TimeToString(t, TIME_DATE|TIME_MINUTES);
}

void ConsiderBufferDebugHit(string dir, int sh, int buf, double raw, datetime t,
                            string &latestDir, int &latestShift, int &latestBuffer, double &latestRaw, datetime &latestTime,
                            string &prevDir, int &prevShift, int &prevBuffer, double &prevRaw, datetime &prevTime)
{
   if(dir == "" || t <= 0)
      return;
   if(latestTime > 0 && t == latestTime && dir == latestDir && buf == latestBuffer)
      return;
   if(prevTime > 0 && t == prevTime && dir == prevDir && buf == prevBuffer)
      return;

   if(latestTime <= 0 || t > latestTime)
   {
      prevDir = latestDir;
      prevShift = latestShift;
      prevBuffer = latestBuffer;
      prevRaw = latestRaw;
      prevTime = latestTime;

      latestDir = dir;
      latestShift = sh;
      latestBuffer = buf;
      latestRaw = raw;
      latestTime = t;
      return;
   }

   if(prevTime <= 0 || t > prevTime)
   {
      prevDir = dir;
      prevShift = sh;
      prevBuffer = buf;
      prevRaw = raw;
      prevTime = t;
   }
}

string TrendBufferDebugLine()
{
   string latestDir = "", prevDir = "";
   int latestShift = -1, latestBuffer = -1, prevShift = -1, prevBuffer = -1;
   double latestRaw = 0.0, previousRaw = 0.0;
   datetime latestTime = 0, prevTime = 0;

   int maxBars = MathMin(InpMaxSignalAgeBars, Bars - 3);
   for(int sh = 0; sh <= maxBars; sh++)
   {
      datetime t = Time[sh];
      if(t <= 0)
         continue;
      string curDir, oldDir;
      double curRaw = 0.0, oldRaw = 0.0;
      int curBuf = -1, oldBuf = -1;
      if(!TrendStateAt(sh, curDir, curRaw, curBuf))
         continue;
      bool hadPreviousState = TrendStateAt(sh + 1, oldDir, oldRaw, oldBuf);
      if(hadPreviousState && oldDir == curDir)
         continue;
      ConsiderBufferDebugHit(curDir, sh, curBuf, curRaw, t, latestDir, latestShift, latestBuffer, latestRaw, latestTime, prevDir, prevShift, prevBuffer, previousRaw, prevTime);
   }

   string stateDir = "";
   double stateRaw = 0.0;
   int stateBuf = -1;
   string state = TrendStateAt(0, stateDir, stateRaw, stateBuf)
                  ? (stateDir + " sh0 buf=" + IntegerToString(stateBuf) + " raw=" + DoubleToString(stateRaw, Digits))
                  : "NONE sh0";
   return "TREND STATE " + state + " | FLIP latest " + BufferHitSummary(latestDir, latestShift, latestBuffer, latestRaw, latestTime) + " | prev " + BufferHitSummary(prevDir, prevShift, prevBuffer, previousRaw, prevTime);
}
string TrendRawStateLine()
{
   double s0 = ReadTrendBuffer(InpTrendStateBuffer, 0);
   double s1 = ReadTrendBuffer(InpTrendStateBuffer, 1);
   string d0="", d1="";
   double r0=0.0, r1=0.0;
   int b0=-1, b1=-1;
   bool ok0 = TrendStateAt(0, d0, r0, b0);
   bool ok1 = TrendStateAt(1, d1, r1, b1);
   return "TREND NOW stateBuf=" + IntegerToString(InpTrendStateBuffer) +
          " sh0=" + (ok0 ? d0 : "NONE") + " raw=" + DoubleToString(s0, 5) +
          " | sh1=" + (ok1 ? d1 : "NONE") + " raw=" + DoubleToString(s1, 5) +
          " | +isBuy=" + (InpTrendPositiveIsBuy ? "true" : "false");
}
void DashboardCreate()
{
   DeleteDashboard();
   if(!InpShowDashboard) return;
   int x = InpDashboardX, y = InpDashboardY, w = 940, h = g_collapsed ? 34 : 520;
   Rect(Obj("bg"), x, y, w, h, clrDimGray, clrBlack);
   Label(Obj("title"), x+12, y+8, "Pro Renko System // " + BUILD_TAG, clrAliceBlue, 9);
   Button(Obj("collapse"), x+w-32, y+6, 24, 20, g_collapsed ? "v" : "^", clrSlateGray, clrWhite);
   if(g_collapsed) return;
   Button(Obj("toggle"), x+12, y+34, 68, 24, g_eaEnabled ? "EA ON" : "EA OFF", g_eaEnabled ? clrDarkGreen : clrMaroon, clrWhite);
   Button(Obj("drift"), x+86, y+34, 86, 24, g_pendingOnDriftRuntime ? "DRIFT LIM" : "DRIFT MKT", g_pendingOnDriftRuntime ? clrSaddleBrown : clrDarkSlateGray, clrWhite);
   Button(Obj("ftmo"), x+178, y+34, 62, 24, g_ftmoMode ? "FTMO" : "FTMO", g_ftmoMode ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Button(Obj("risklot"), x+246, y+34, 66, 24, g_riskLotOnlyMode ? "RISK" : "RISK", g_riskLotOnlyMode ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Button(Obj("invert"), x+318, y+34, 58, 24, g_invertMode ? "INV" : "INV", g_invertMode ? clrMaroon : clrDarkSlateGray, clrWhite);
   Button(Obj("audit"), x+382, y+34, 72, 24, g_auditRuntime ? "AUDIT" : "AUDIT", g_auditRuntime ? clrSaddleBrown : clrDarkSlateGray, clrWhite);
   Button(Obj("mt5pub"), x+460, y+34, 72, 24, g_fileBridgeMt5Runtime ? "MT5 ON" : "MT5 OFF", g_fileBridgeMt5Runtime ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Button(Obj("native24"), x+538, y+34, 82, 24, g_nativeIgnoreWindowsRuntime ? "NAT 24" : "NAT WIN", g_nativeIgnoreWindowsRuntime ? clrDarkOrange : clrDarkSlateGray, clrWhite);
   Button(Obj("apply"), x+626, y+34, 82, 24, "APPLY", clrSteelBlue, clrWhite);
   Label(Obj("l_lot"), x+12, y+68, "Lot", clrLightSteelBlue, 8); Edit(Obj("e_lot"), x+86, y+64, 58, 20, DoubleToString(g_lotRuntime, 2));
   Label(Obj("l_spread"), x+152, y+68, "MaxSpr", clrLightSteelBlue, 8); Edit(Obj("e_spread"), x+210, y+64, 50, 20, IntegerToString(g_maxSpreadRuntime));
   Label(Obj("l_scale"), x+270, y+68, "CalcSL%", clrLightSteelBlue, 8); Edit(Obj("e_scale"), x+318, y+64, 56, 20, DoubleToString(g_finalScaleRuntime, 1));
   Label(Obj("l_tp"), x+12, y+94, "TP R", clrLightSteelBlue, 8); Edit(Obj("e_tp"), x+86, y+90, 58, 20, DoubleToString(g_targetRRuntime, 1));
   Label(Obj("l_half"), x+152, y+94, "HCBE R", clrLightSteelBlue, 8); Edit(Obj("e_half"), x+210, y+90, 50, 20, DoubleToString(g_halfRRuntime, 1));
   Label(Obj("l_windows"), x+12, y+120, "Window", clrLightSteelBlue, 8); Edit(Obj("e_allowed"), x+86, y+116, 132, 20, g_allowedWindowsRuntime);
   Label(Obj("l_no"), x+224, y+120, "NoTrade", clrLightSteelBlue, 8); Edit(Obj("e_no"), x+286, y+116, 88, 20, g_noTradeWindowsRuntime);
   Label(Obj("l_riskpct"), x+384, y+120, "Risk%", clrLightSteelBlue, 8); Edit(Obj("e_riskpct"), x+432, y+116, 58, 20, DoubleToString(g_riskPctRuntime, 2));
   Button(Obj("riskapply"), x+494, y+116, 64, 20, "APPLY R", clrSteelBlue, clrWhite);
   Label(Obj("l_pips"), x+566, y+120, "Pips", clrLightSteelBlue, 8); Edit(Obj("e_pips"), x+602, y+116, 48, 20, DoubleToString(g_pipSlPipsRuntime, 1));
   Button(Obj("pipmode"), x+656, y+116, 50, 20, g_pipSlModeRuntime ? "PIP" : "OFF", g_pipSlModeRuntime ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Label(Obj("l_evt"), x+714, y+120, "UTCBlk", clrLightSteelBlue, 8); Edit(Obj("e_evt"), x+766, y+116, 54, 20, g_utcEventBlockTimesRuntime);
   Button(Obj("eventapply"), x+826, y+116, 70, 20, "APPLY E", clrSteelBlue, clrWhite);
   Button(Obj("symr"), x+384, y+142, 82, 20, g_symmetricRTargetsRuntime ? "SYM R" : "SYM OFF", g_symmetricRTargetsRuntime ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Button(Obj("trendmode"), x+472, y+142, 92, 20, g_trendTradeRuntime ? "TREND ON" : "TREND OFF", g_trendTradeRuntime ? clrDarkGreen : clrMaroon, clrWhite);
   Button(Obj("execmode"), x+570, y+142, 54, 20, TrendExecModeLabel(), TrendExecModeColor(), clrWhite);
   Label(Obj("l_execdelay"), x+630, y+146, "Dly", clrLightSteelBlue, 8); Edit(Obj("e_execdelay"), x+660, y+142, 42, 20, IntegerToString(g_trendExecDelayRuntime));
   Label(Obj("l_dayp"), x+12, y+146, "Day Profit", clrLightSteelBlue, 8); Edit(Obj("e_dayp"), x+86, y+142, 58, 20, DoubleToString(g_dailyProfitTargetRuntime, 0));
   Label(Obj("l_dayl"), x+152, y+146, "Day Loss", clrLightSteelBlue, 8); Edit(Obj("e_dayl"), x+210, y+142, 50, 20, DoubleToString(g_dailyLossTargetRuntime, 0));
   Label(Obj("basket_head"), x+548, y+174, "Basket Daily Target", clrOrange, 8);
   Button(Obj("basketmode"), x+548, y+196, 74, 20, g_basketModeRuntime ? "BASKET" : "TRAD", g_basketModeRuntime ? clrDarkOrange : clrDarkSlateGray, clrWhite);
   Button(Obj("basketrev"), x+628, y+196, 74, 20, g_basketCloseOnReverseRuntime ? "REV ON" : "REV OFF", g_basketCloseOnReverseRuntime ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Label(Obj("l_btpips"), x+548, y+222, "TgtPips", clrLightSteelBlue, 8); Edit(Obj("e_btpips"), x+604, y+218, 58, 20, DoubleToString(g_basketTargetPipsRuntime, 1));
   Label(Obj("l_btpct"), x+668, y+222, "Tgt%", clrLightSteelBlue, 8); Edit(Obj("e_btpct"), x+710, y+218, 50, 20, DoubleToString(g_basketTargetPctRuntime, 2));
   Label(Obj("l_blpips"), x+548, y+248, "LossP", clrLightSteelBlue, 8); Edit(Obj("e_blpips"), x+604, y+244, 58, 20, DoubleToString(g_basketMaxLossPipsRuntime, 1));
   Label(Obj("l_bcat"), x+668, y+248, "CatSL", clrLightSteelBlue, 8); Edit(Obj("e_bcat"), x+710, y+244, 58, 20, DoubleToString(g_basketCatastrophicSlPipsRuntime, 1));
   Button(Obj("basketapply"), x+548, y+270, 78, 20, "APPLY B", clrSteelBlue, clrWhite);
   Label(Obj("basket_info"), x+548, y+302, "basket preview", clrMoccasin, 8);
   Label(Obj("status"), x+12, y+174, "status", clrWhite, 8);
   Label(Obj("signal"), x+12, y+196, "signal", clrWhite, 8);
   Label(Obj("trend_dbg"), x+12, y+218, "trend buffer", clrGold, 8);
   Label(Obj("trend_now"), x+12, y+240, "trend now", clrKhaki, 8);
   Label(Obj("risk"), x+12, y+262, "risk", clrWhite, 8);
   Label(Obj("risk_preview"), x+12, y+284, "risk preview", clrLightCyan, 8);
   Label(Obj("open"), x+12, y+306, "open", clrWhite, 8);
   Rect(Obj("prog_bg"), x+12, y+334, 520, 16, clrBlack, clrSlateGray);
   Rect(Obj("prog_fill"), x+13, y+335, 1, 14, clrDodgerBlue, clrDodgerBlue);
   Rect(Obj("dayp_bg"), x+12, y+362, 520, 18, clrBlack, clrSlateGray);
   Rect(Obj("dayp_fill"), x+13, y+363, 1, 16, clrDodgerBlue, clrDodgerBlue);
   Label(Obj("dayp_txt"), x+20, y+365, "DAY PROFIT TARGET OFF", clrWhite, 8);
   Rect(Obj("dayl_bg"), x+12, y+388, 520, 18, clrBlack, clrSlateGray);
   Rect(Obj("dayl_fill"), x+13, y+389, 1, 16, clrTomato, clrTomato);
   Label(Obj("dayl_txt"), x+20, y+391, "DAY LOSS TARGET OFF", clrWhite, 8);
}

void DashboardUpdate()
{
   if(!InpShowDashboard) return;
   if(ObjectFind(0, Obj("bg")) < 0) DashboardCreate();
   ObjectSetString(0, Obj("toggle"), OBJPROP_TEXT, g_eaEnabled ? "EA ON" : "EA OFF");
   ObjectSetInteger(0, Obj("toggle"), OBJPROP_BGCOLOR, g_eaEnabled ? clrDarkGreen : clrMaroon);
   ObjectSetString(0, Obj("drift"), OBJPROP_TEXT, g_pendingOnDriftRuntime ? "DRIFT LIMIT" : "DRIFT MKT");
   ObjectSetInteger(0, Obj("drift"), OBJPROP_BGCOLOR, g_pendingOnDriftRuntime ? clrSaddleBrown : clrDarkSlateGray);
   ObjectSetString(0, Obj("audit"), OBJPROP_TEXT, g_auditRuntime ? "AUDIT" : "AUDIT");
   ObjectSetInteger(0, Obj("audit"), OBJPROP_BGCOLOR, g_auditRuntime ? clrSaddleBrown : clrDarkSlateGray);
   ObjectSetString(0, Obj("mt5pub"), OBJPROP_TEXT, g_fileBridgeMt5Runtime ? "MT5 ON" : "MT5 OFF");
   ObjectSetInteger(0, Obj("mt5pub"), OBJPROP_BGCOLOR, g_fileBridgeMt5Runtime ? clrDarkGreen : clrDarkSlateGray);
   ObjectSetString(0, Obj("native24"), OBJPROP_TEXT, g_nativeIgnoreWindowsRuntime ? "NAT 24" : "NAT WIN");
   ObjectSetInteger(0, Obj("native24"), OBJPROP_BGCOLOR, g_nativeIgnoreWindowsRuntime ? clrDarkOrange : clrDarkSlateGray);
   ObjectSetString(0, Obj("ftmo"), OBJPROP_TEXT, g_ftmoMode ? "FTMO" : "FTMO");
   ObjectSetInteger(0, Obj("ftmo"), OBJPROP_BGCOLOR, g_ftmoMode ? clrDarkGreen : clrDarkSlateGray);
   ObjectSetString(0, Obj("risklot"), OBJPROP_TEXT, g_riskLotOnlyMode ? "RISK" : "RISK");
   ObjectSetInteger(0, Obj("risklot"), OBJPROP_BGCOLOR, g_riskLotOnlyMode ? clrDarkGreen : clrDarkSlateGray);
   ObjectSetString(0, Obj("invert"), OBJPROP_TEXT, g_invertMode ? "INV ON" : "INV");
   ObjectSetInteger(0, Obj("invert"), OBJPROP_BGCOLOR, g_invertMode ? clrMaroon : clrDarkSlateGray);
   ObjectSetString(0, Obj("pipmode"), OBJPROP_TEXT, g_pipSlModeRuntime ? "PIP" : "OFF");
   ObjectSetInteger(0, Obj("pipmode"), OBJPROP_BGCOLOR, g_pipSlModeRuntime ? clrDarkGreen : clrDarkSlateGray);
   ObjectSetString(0, Obj("symr"), OBJPROP_TEXT, g_symmetricRTargetsRuntime ? "SYM R" : "SYM OFF");
   ObjectSetInteger(0, Obj("symr"), OBJPROP_BGCOLOR, g_symmetricRTargetsRuntime ? clrDarkGreen : clrDarkSlateGray);
   ObjectSetString(0, Obj("trendmode"), OBJPROP_TEXT, g_trendTradeRuntime ? "TREND ON" : "TREND OFF");
   ObjectSetInteger(0, Obj("trendmode"), OBJPROP_BGCOLOR, g_trendTradeRuntime ? clrDarkGreen : clrMaroon);
   ObjectSetString(0, Obj("execmode"), OBJPROP_TEXT, TrendExecModeLabel());
   ObjectSetInteger(0, Obj("execmode"), OBJPROP_BGCOLOR, TrendExecModeColor());
   ObjectSetString(0, Obj("basketmode"), OBJPROP_TEXT, g_basketModeRuntime ? "BASKET" : "TRAD");
   ObjectSetInteger(0, Obj("basketmode"), OBJPROP_BGCOLOR, g_basketModeRuntime ? clrDarkOrange : clrDarkSlateGray);
   ObjectSetString(0, Obj("basketrev"), OBJPROP_TEXT, g_basketCloseOnReverseRuntime ? "REV ON" : "REV OFF");
   ObjectSetInteger(0, Obj("basketrev"), OBJPROP_BGCOLOR, g_basketCloseOnReverseRuntime ? clrDarkGreen : clrDarkSlateGray);
   if(g_collapsed) return;
   string sigTime = (g_lastSignalTime > 0) ? TimeToString(g_lastSignalTime, TIME_DATE|TIME_MINUTES) : "-";
   ObjectSetString(0, Obj("status"), OBJPROP_TEXT, "Spread " + IntegerToString(CurrentSpreadPoints()) + " pt | Mode " + RuntimeRiskModeLabel() + " | Risk% " + DoubleToString(EffAccountRiskPerTradePct(),2) + " | INV " + (g_invertMode ? "ON" : "OFF") + " | SYM " + (g_symmetricRTargetsRuntime ? "ON" : "OFF") + " | EXEC " + TrendExecModeLabel() + " Dly " + IntegerToString(g_trendExecDelayRuntime) + "s | TREND STATE buf" + IntegerToString(InpTrendStateBuffer) + " | MODE " + (g_basketModeRuntime ? "BASKET" : "TRAD") + " | MT5 " + (g_fileBridgeMt5Runtime ? "ON" : "OFF") + " | NAT " + (g_nativeIgnoreWindowsRuntime ? "24/7" : "WIN") + " | Magic " + IntegerToString(EffectiveMagic()));
   ObjectSetString(0, Obj("signal"), OBJPROP_TEXT, "Latest trade signal: " + g_lastSignalDir + " @ " + sigTime + " px " + PriceText(g_lastSignalPrice));
   ObjectSetString(0, Obj("trend_dbg"), OBJPROP_TEXT, TrendBufferDebugLine());
   ObjectSetString(0, Obj("trend_now"), OBJPROP_TEXT, TrendRawStateLine());
   double cap, daily, dd; AccountRiskMetrics(cap, daily, dd);
   ObjectSetString(0, Obj("risk"), OBJPROP_TEXT, "RiskCap " + DoubleToString(cap,2) + " | OpenRisk " + DoubleToString(CurrentOpenRisk(),2) + " | D " + DoubleToString(daily,2) + "% / DD " + DoubleToString(dd,2) + "%");
   ObjectSetString(0, Obj("risk_preview"), OBJPROP_TEXT, RiskLotPreviewLine());
   ObjectSetString(0, Obj("basket_info"), OBJPROP_TEXT, BasketPreviewLine());
   UpdateOpenLine();
   UpdateDailyGuardBars();
}

void UpdateDailyGuardBars()
{
   double dayPnl = ChartClosedPnlToday();
   double profitTarget = MathMax(0.0, g_dailyProfitTargetRuntime);
   double lossTarget = MathMax(0.0, g_dailyLossTargetRuntime);
   double profitValue = MathMax(0.0, dayPnl);
   double lossValue = MathMax(0.0, -dayPnl);
   double profitPct = (profitTarget > 0.0 ? MathMin(1.0, profitValue / profitTarget) : 0.0);
   double lossPct = (lossTarget > 0.0 ? MathMin(1.0, lossValue / lossTarget) : 0.0);
   ObjectSetInteger(0, Obj("dayp_fill"), OBJPROP_XSIZE, MathMax(1, (int)MathRound(518.0 * profitPct)));
   ObjectSetInteger(0, Obj("dayl_fill"), OBJPROP_XSIZE, MathMax(1, (int)MathRound(518.0 * lossPct)));
   ObjectSetInteger(0, Obj("dayp_fill"), OBJPROP_BGCOLOR, clrDodgerBlue);
   ObjectSetInteger(0, Obj("dayl_fill"), OBJPROP_BGCOLOR, clrTomato);
   string profitText = profitTarget > 0.0 ? ("DAY PROFIT " + DoubleToString(profitValue, 2) + "/" + DoubleToString(profitTarget, 2)) : "DAY PROFIT TARGET OFF";
   string lossText = lossTarget > 0.0 ? ("DAY LOSS " + DoubleToString(lossValue, 2) + "/" + DoubleToString(lossTarget, 2)) : "DAY LOSS TARGET OFF";
   ObjectSetString(0, Obj("dayp_txt"), OBJPROP_TEXT, profitText);
   ObjectSetString(0, Obj("dayl_txt"), OBJPROP_TEXT, lossText);
}

double BasketTargetMoneyPreview()
{
   double cap = 0.0, daily = 0.0, dd = 0.0;
   AccountRiskMetrics(cap, daily, dd);
   return cap * MathMax(0.0, g_basketTargetPctRuntime) / 100.0;
}

double BasketMaxLossMoneyPreview()
{
   double targetPips = MathMax(0.0, g_basketTargetPipsRuntime);
   if(targetPips <= 0.0) return 0.0;
   return BasketTargetMoneyPreview() * MathMax(0.0, g_basketMaxLossPipsRuntime) / targetPips;
}

string BasketPreviewLine()
{
   double targetMoney = BasketTargetMoneyPreview();
   double maxLossMoney = BasketMaxLossMoneyPreview();
   string mode = g_basketModeRuntime ? "ON" : "OFF";
   return "Basket " + mode
      + " | target " + DoubleToString(g_basketTargetPipsRuntime, 1) + "p=" + DoubleToString(g_basketTargetPctRuntime, 2) + "% ($" + DoubleToString(targetMoney, 2) + ")"
      + " | maxLoss " + DoubleToString(g_basketMaxLossPipsRuntime, 1) + "p ($" + DoubleToString(maxLossMoney, 2) + ")"
      + " | catSL " + DoubleToString(g_basketCatastrophicSlPipsRuntime, 1) + "p"
      + " | rev " + (g_basketCloseOnReverseRuntime ? "ON" : "OFF")
      ;
}
string RiskLotPreviewLine()
{
   RefreshRates();
   double cap = 0.0, daily = 0.0, dd = 0.0;
   AccountRiskMetrics(cap, daily, dd);
   double riskPct = EffAccountRiskPerTradePct();
   double riskMoney = cap * riskPct / 100.0;
   bool requireHalf = (g_halfRRuntime > 0.0);
   int type = (g_lastSignalDir == "SELL") ? OP_SELL : OP_BUY;
   double entry = (type == OP_BUY) ? Ask : Bid;
   double sl = 0.0, tp1 = 0.0, tp2 = 0.0, tp3 = 0.0;
   double slDistance = 0.0;
   string mode = "";
   string geom = "";

   if(PipSlModeEnabled())
   {
      double pipSizeNow = SymbolPipSize();
      double requestedRisk = MathMax(0.0, g_pipSlPipsRuntime) * pipSizeNow;
      double minStop = MathMax(Point * 10.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
      slDistance = MathMax(requestedRisk, minStop);
      mode = "PIP " + DoubleToString(g_pipSlPipsRuntime, 1) + "p";
   }
   else
   {
      if(g_lastSignalTime <= 0 || (g_lastSignalDir != "BUY" && g_lastSignalDir != "SELL") || g_lastSignalPrice <= 0.0)
         return "RiskPreview: enable PIP SL or wait latest signal";
      type = (g_lastSignalDir == "BUY") ? OP_BUY : OP_SELL;
      entry = g_lastSignalPrice;
      int shift = MathMax(0, iBarShift(Symbol(), Period(), g_lastSignalTime, false));
      bool oldFallback = g_lastGeometryUsedFallback;
      bool ok = BuildGeometry(type, entry, g_lastSignalPrice, shift, sl, tp1, tp2, tp3, geom);
      g_lastGeometryUsedFallback = oldFallback;
      if(!ok)
         return "RiskPreview: geometry unavailable " + geom;
      if(g_invertMode)
      {
         string drawDir = g_lastSignalDir;
         int execType = type;
         string invDetail = "";
         double srcSl = sl, srcTp1 = tp1, srcTp2 = tp2, srcTp3 = tp3;
         if(!ApplyInvertGeometry(g_lastSignalDir, entry, srcSl, srcTp1, srcTp2, srcTp3, drawDir, execType, sl, tp1, tp2, tp3, invDetail))
            return "RiskPreview: invert geometry unavailable";
         type = execType;
         mode = "GEOM INV " + drawDir;
      }
      else mode = "GEOM " + g_lastSignalDir;
      slDistance = MathAbs(entry - sl);
   }

   double pipSize = SymbolPipSize();
   double pips = (pipSize > 0.0) ? slDistance / pipSize : 0.0;
   double riskPerLot = MoneyMovePerLot(slDistance);
   if(cap <= 0.0 || riskPct <= 0.0 || riskMoney <= 0.0 || riskPerLot <= 0.0 || slDistance <= 0.0)
      return "RiskPreview: invalid cap/risk/sl cap=" + DoubleToString(cap,2) + " risk%=" + DoubleToString(riskPct,2) + " SLp=" + DoubleToString(pips,1);

   double rawLot = riskMoney / riskPerLot;
   double normLot = NormalizeOrderLot(rawLot, requireHalf);
   if(normLot <= 0.0)
      return "RiskPreview " + mode + " | Risk " + DoubleToString(riskPct,2) + "%=$" + DoubleToString(riskMoney,2) + " | SL " + DoubleToString(pips,1) + "p | lot below min";

   string marginDetail = "";
   double finalLot = ClampLotToMargin(normLot, type, requireHalf, marginDetail);
   bool clamped = false;
   if(finalLot <= 0.0)
   {
      finalLot = normLot;
      marginDetail = "margin_preview_block " + marginDetail;
   }
   else if(MathAbs(finalLot - normLot) > 0.0000001)
      clamped = true;

   double finalRisk = riskPerLot * finalLot;
   return "RiskPreview " + mode
      + " | Risk " + DoubleToString(riskPct,2) + "%=$" + DoubleToString(riskMoney,2)
      + " | SL " + DoubleToString(pips,1) + "p"
      + " | $/lot " + DoubleToString(riskPerLot,2)
      + " | lot " + DoubleToString(finalLot,2)
      + " | estRisk $" + DoubleToString(finalRisk,2)
      + (clamped ? " clamped" : "");
}
void UpdateOpenLine()
{
   string txt = "Open: none";
   double rLast = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType(); if(type != OP_BUY && type != OP_SELL) continue;
      double live = (type == OP_BUY) ? Bid : Ask;
      double risk = MathAbs(OrderOpenPrice() - OrderStopLoss());
      rLast = (risk > 0) ? ((type == OP_BUY ? live - OrderOpenPrice() : OrderOpenPrice() - live) / risk) : 0;
      txt = "Open #" + IntegerToString(OrderTicket()) + " " + (type == OP_BUY ? "BUY" : "SELL") + " R=" + DoubleToString(rLast,2) + " PnL=" + DoubleToString(OrderProfit(),2) + " SL=" + PriceText(OrderStopLoss()) + " TP=" + PriceText(OrderTakeProfit());
      break;
   }
   ObjectSetString(0, Obj("open"), OBJPROP_TEXT, txt);
   int fill = (int)MathRound(MathMax(0.0, MathMin(1.0, (rLast + 1.0) / 4.0)) * 518.0);
   ObjectSetInteger(0, Obj("prog_fill"), OBJPROP_XSIZE, MathMax(1, fill));
   ObjectSetInteger(0, Obj("prog_fill"), OBJPROP_BGCOLOR, rLast >= 0 ? clrDodgerBlue : clrTomato);
}

void ApplyRiskInputAndPublish()
{
   double newRisk = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_riskpct"), OBJPROP_TEXT)));
   g_riskPctRuntime = newRisk;
   ObjectSetString(0, Obj("e_riskpct"), OBJPROP_TEXT, DoubleToString(g_riskPctRuntime, 2));
   FileBridgeWriteInitMarker();
   Audit("dashboard_risk_apply", "", 0, "", 0, 0, 0, 0, "risk_pct=" + DoubleToString(g_riskPctRuntime, 4) + " bridge_init_republished=" + (g_fileBridgeMt5Runtime ? "true" : "false"), 0, "");
   Print("ProRenkoBridge risk apply risk_pct=", DoubleToString(g_riskPctRuntime, 4), " bridge_init_republished=", g_fileBridgeMt5Runtime ? "true" : "false");
}

void ApplyDashboardInputs()
{
   g_lotRuntime = MathMax(0, StringToDouble(ObjectGetString(0, Obj("e_lot"), OBJPROP_TEXT)));
   g_maxSpreadRuntime = MathMax(0, (int)StringToInteger(ObjectGetString(0, Obj("e_spread"), OBJPROP_TEXT)));
   g_finalScaleRuntime = MathMax(10, MathMin(200, StringToDouble(ObjectGetString(0, Obj("e_scale"), OBJPROP_TEXT))));
   g_targetRRuntime = ParseDashboardR(ObjectGetString(0, Obj("e_tp"), OBJPROP_TEXT), g_targetRRuntime, 0.1, 10.0);
   g_halfRRuntime = ParseDashboardR(ObjectGetString(0, Obj("e_half"), OBJPROP_TEXT), g_halfRRuntime, 0.0, 10.0);
   g_targetTpRuntime = RToLegacyIndex(g_targetRRuntime);
   g_halfTpRuntime = (g_halfRRuntime > 0.0 ? 1 : 0);
   g_allowedWindowsRuntime = ObjectGetString(0, Obj("e_allowed"), OBJPROP_TEXT);
   g_noTradeWindowsRuntime = ObjectGetString(0, Obj("e_no"), OBJPROP_TEXT);
   // Applying a basket window while currently inside it behaves like entering
   // that window. Existing same-direction and daily guards prevent duplicates.
   if(g_basketModeRuntime)
   {
      g_basketWindowEligibleLast = false;
      g_basketWindowStateInitialized = true;
   }
   g_riskPctRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_riskpct"), OBJPROP_TEXT)));
   g_pipSlPipsRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_pips"), OBJPROP_TEXT)));
   g_dailyProfitTargetRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_dayp"), OBJPROP_TEXT)));
   g_dailyLossTargetRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_dayl"), OBJPROP_TEXT)));
   g_trendExecDelayRuntime = MathMax(0, (int)StringToInteger(ObjectGetString(0, Obj("e_execdelay"), OBJPROP_TEXT)));
   g_trendExecModeRuntime = MathMax(0, MathMin(2, g_trendExecModeRuntime));
   if(ObjectFind(0, Obj("e_btpips")) >= 0) g_basketTargetPipsRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_btpips"), OBJPROP_TEXT)));
   if(ObjectFind(0, Obj("e_btpct")) >= 0) g_basketTargetPctRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_btpct"), OBJPROP_TEXT)));
   if(ObjectFind(0, Obj("e_blpips")) >= 0) g_basketMaxLossPipsRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_blpips"), OBJPROP_TEXT)));
   if(ObjectFind(0, Obj("e_bcat")) >= 0) g_basketCatastrophicSlPipsRuntime = MathMax(0.0, StringToDouble(ObjectGetString(0, Obj("e_bcat"), OBJPROP_TEXT)));
   if(ObjectFind(0, Obj("e_evt")) >= 0) g_utcEventBlockTimesRuntime = Trim(ObjectGetString(0, Obj("e_evt"), OBJPROP_TEXT));
   FileBridgeWriteBasketConfigMarker("dashboard_apply");
   g_utcEventBlockRadiusRuntime = MathMax(0, MathMin(60, g_utcEventBlockRadiusRuntime));
   g_basketCloseAtSessionEndRuntime = false;
   g_basketSessionEndTimeRuntime = "";
   DrawLatestSignalLevels("dashboard_apply");
   DrawHistoricalSignalLevels("dashboard_apply");
   Audit("dashboard_apply", "", 0, "", g_lotRuntime, 0, 0, 0, "max_spread=" + IntegerToString(g_maxSpreadRuntime) + " scale=" + DoubleToString(g_finalScaleRuntime,1) + " tp_r=" + DoubleToString(g_targetRRuntime,1) + " half_r=" + DoubleToString(g_halfRRuntime,1) + " pending_on_drift=" + (g_pendingOnDriftRuntime ? "true" : "false") + " mt5_bridge=" + (g_fileBridgeMt5Runtime ? "true" : "false") + " native_ignore_windows=" + (g_nativeIgnoreWindowsRuntime ? "true" : "false") + " risk_pct=" + DoubleToString(g_riskPctRuntime,2) + " invert=" + (g_invertMode ? "true" : "false") + " pip_sl=" + (g_pipSlModeRuntime ? "true" : "false") + " pip_sl_pips=" + DoubleToString(g_pipSlPipsRuntime, 2) + " sym_r=" + (g_symmetricRTargetsRuntime ? "true" : "false") + " trend_only=true trend_state_buffer=" + IntegerToString(InpTrendStateBuffer) + " positive_is_buy=" + (InpTrendPositiveIsBuy ? "true" : "false") + " exec_mode=" + TrendExecModeLabel() + " exec_delay_sec=" + IntegerToString(g_trendExecDelayRuntime) + " daily_profit_target=" + DoubleToString(g_dailyProfitTargetRuntime, 2) + " daily_loss_target=" + DoubleToString(g_dailyLossTargetRuntime, 2) + " basket_mode=" + (g_basketModeRuntime ? "true" : "false") + " basket_target_pips=" + DoubleToString(g_basketTargetPipsRuntime, 1) + " basket_target_pct=" + DoubleToString(g_basketTargetPctRuntime, 2) + " basket_max_loss_pips=" + DoubleToString(g_basketMaxLossPipsRuntime, 1) + " basket_cat_sl_pips=" + DoubleToString(g_basketCatastrophicSlPipsRuntime, 1) + " utc_event_block='" + g_utcEventBlockTimesRuntime + "' radius_min=" + IntegerToString(g_utcEventBlockRadiusRuntime), 0, "");
}

void Rect(string name, int x, int y, int w, int h, color bg, color border)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false); ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void Label(string name, int x, int y, string text, color clr, int size)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size); ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void Button(string name, int x, int y, int w, int h, string text, color bg, color fg)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}

void Edit(string name, int x, int y, int w, int h, string text)
{
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBlack); ObjectSetInteger(0, name, OBJPROP_COLOR, clrAqua);
}

void DeleteDashboard()
{
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, g_prefix) == 0) ObjectDelete(0, name);
   }
}

string SignalLevelPrefix()
{
   return "PRORENKO_SIGLVL_" + IntegerToString((int)ChartID()) + "_";
}

string HistoricalSignalLevelPrefix()
{
   return "PRORENKO_HISTSIG_" + IntegerToString((int)ChartID()) + "_";
}

void DeleteLatestSignalLevels()
{
   string prefix = SignalLevelPrefix();
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DeleteHistoricalSignalLevels()
{
   string prefix = HistoricalSignalLevelPrefix();
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void SegmentLevelWithPrefix(string prefix, string key, datetime t0, datetime t1, double price, color clr, int style, string label, int width)
{
   if(price <= 0.0 || t0 <= 0 || t1 <= t0)
      return;
   string lineName = prefix + key;
   string textName = prefix + key + "_TXT";
   ObjectCreate(0, lineName, OBJ_TREND, 0, t0, price, t1, price);
   ObjectSetInteger(0, lineName, OBJPROP_RAY, false);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, style);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   ObjectCreate(0, textName, OBJ_TEXT, 0, t1, price);
   ObjectSetString(0, textName, OBJPROP_TEXT, label + " " + PriceText(price));
   ObjectSetString(0, textName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, textName, OBJPROP_BACK, false);
   ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
}

void SegmentLevel(string key, datetime t0, datetime t1, double price, color clr, int style, string label)
{
   SegmentLevelWithPrefix(SignalLevelPrefix(), key, t0, t1, price, clr, style, label, 2);
}

bool HasOpenManagedTradeLevels()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int ot = OrderType();
      if(ot == OP_BUY || ot == OP_SELL || ot == OP_BUYLIMIT || ot == OP_SELLLIMIT || ot == OP_BUYSTOP || ot == OP_SELLSTOP)
         return true;
   }
   return false;
}

void DrawLatestSignalLevels(string reason)
{
   DeleteLatestSignalLevels();
   if(!InpShowLatestSignalLevels)
      return;
   if(g_basketModeRuntime)
      return;
   if(HasOpenManagedTradeLevels())
      return;
   if(g_lastSignalTime <= 0 || (g_lastSignalDir != "BUY" && g_lastSignalDir != "SELL") || g_lastSignalPrice <= 0.0)
      return;
   int type = (g_lastSignalDir == "BUY") ? OP_BUY : OP_SELL;
   string drawDir = g_lastSignalDir;
   double entry = g_lastSignalPrice;
   int shift = MathMax(0, iBarShift(Symbol(), Period(), g_lastSignalTime, false));
   double sl = 0.0, tp1 = 0.0, tp2 = 0.0, tp3 = 0.0;
   string geom = "";
   bool oldFallbackFlag = g_lastGeometryUsedFallback;
   bool ok = BuildGeometry(type, entry, g_lastSignalPrice, shift, sl, tp1, tp2, tp3, geom);
   g_lastGeometryUsedFallback = oldFallbackFlag;
   if(!ok)
   {
      Audit("signal_level_draw_failed", g_lastEventId, 0, g_lastSignalDir, 0, entry, sl, 0, geom + " reason=" + reason, 0, "");
      return;
   }
   if(g_invertMode)
   {
      string invDetail = "";
      if(!ApplyInvertGeometry(g_lastSignalDir, entry, sl, tp1, tp2, tp3, drawDir, type, sl, tp1, tp2, tp3, invDetail))
      {
         Audit("signal_level_draw_invert_failed", g_lastEventId, 0, g_lastSignalDir, 0, entry, sl, tp1, invDetail + " reason=" + reason, 0, "");
         return;
      }
      geom += " " + invDetail;
   }
   double target = TpByR(type, entry, sl, g_targetRRuntime);
   double half = TpByR(type, entry, sl, g_halfRRuntime);
   int seconds = MathMax(60, Period() * 60);
   datetime t0 = g_lastSignalTime;
   datetime t1 = t0 + MathMax(1, InpSignalLevelBars) * seconds;
   string mode = (g_invertMode ? " INV" : "") + " " + drawDir;
   SegmentLevel("ENTRY", t0, t1, entry, clrWhite, STYLE_DOT, "PRORENKO" + mode + " ENTRY");
   SegmentLevel("SL", t0, t1, sl, clrTomato, STYLE_SOLID, "PRORENKO" + mode + " SL");
   SegmentLevel("TP", t0, t1, target, clrLimeGreen, STYLE_SOLID, "PRORENKO" + mode + " TP " + RLabel(g_targetRRuntime));
   if(g_halfRRuntime > 0.0 && half > 0.0)
      SegmentLevel("HCBE", t0, t1, half, clrGold, STYLE_DASH, "PRORENKO" + mode + " HCBE " + RLabel(g_halfRRuntime));
}

bool DrawHistoricalSignalLevelAtShift(int sh, int drawn, string prefix, int seconds, int barsForward)
{
   string dir, prevDir;
   double raw = 0.0, prevRaw = 0.0;
   int buf = -1, prevBuf = -1;
   if(!TrendStateAt(sh, dir, raw, buf)) return false;
   bool prevState = TrendStateAt(sh + 1, prevDir, prevRaw, prevBuf);
   if(prevState && prevDir == dir) return false;

   datetime t0 = Time[sh];
   if(t0 <= 0) return false;
   if(g_lastSignalTime > 0 && t0 == g_lastSignalTime)
      return false;
   double entry = SignalEntryPrice(dir, sh, raw);
   int type = (dir == "BUY") ? OP_BUY : OP_SELL;
   string drawDir = dir;
   double sl = 0.0, tp1 = 0.0, tp2 = 0.0, tp3 = 0.0;
   string geom = "";
   bool oldFallbackFlag = g_lastGeometryUsedFallback;
   bool ok = BuildGeometry(type, entry, entry, sh, sl, tp1, tp2, tp3, geom);
   g_lastGeometryUsedFallback = oldFallbackFlag;
   if(!ok) return false;
   if(g_invertMode)
   {
      string invDetail = "";
      if(!ApplyInvertGeometry(dir, entry, sl, tp1, tp2, tp3, drawDir, type, sl, tp1, tp2, tp3, invDetail))
         return false;
   }

   double target = TpByR(type, entry, sl, g_targetRRuntime);
   double half = TpByR(type, entry, sl, g_halfRRuntime);
   datetime t1 = t0 + barsForward * seconds;
   datetime nextT = NextHistoricalSignalTimeAfter(sh);
   if(nextT > t0 && nextT < t1)
      t1 = MathMax(t0 + 1, nextT - 1);
   string base = IntegerToString((int)t0) + "_" + IntegerToString(drawn) + "_";
   string mode = (g_invertMode ? " INV" : "") + " " + drawDir;
   SegmentLevelWithPrefix(prefix, base + "ENTRY", t0, t1, entry, clrWhite, STYLE_DOT, "PR" + mode + " ENTRY", 1);
   SegmentLevelWithPrefix(prefix, base + "SL", t0, t1, sl, clrTomato, STYLE_SOLID, "PR" + mode + " SL", 1);
   SegmentLevelWithPrefix(prefix, base + "TP", t0, t1, target, clrLimeGreen, STYLE_SOLID, "PR" + mode + " TP " + RLabel(g_targetRRuntime), 1);
   if(g_halfRRuntime > 0.0 && half > 0.0)
      SegmentLevelWithPrefix(prefix, base + "HCBE", t0, t1, half, clrGold, STYLE_DASH, "PR" + mode + " HCBE " + RLabel(g_halfRRuntime), 1);
   return true;
}

void DrawHistoricalSignalLevels(string reason)
{
   DeleteHistoricalSignalLevels();
   if(!InpShowHistoricalSignalLevels)
      return;
   if(g_basketModeRuntime)
      return;
   int maxBars = MathMin(InpMaxSignalAgeBars, Bars - 3);
   if(maxBars < 1) return;
   int seconds = MathMax(60, Period() * 60);
   int barsForward = MathMax(1, InpSignalLevelBars);
   string prefix = HistoricalSignalLevelPrefix();

   int drawn = 0;
   for(int sh = maxBars; sh >= 1; sh--)
   {
      if(DrawHistoricalSignalLevelAtShift(sh, drawn, prefix, seconds, barsForward))
         drawn++;
   }

   // If the performance-limited recent window has no transition, draw the nearest older one.
   // This keeps context visible without rendering the entire chart history.
   if(drawn == 0)
   {
      int hardMax = Bars - 3;
      for(int shOld = maxBars + 1; shOld <= hardMax; shOld++)
      {
         if(DrawHistoricalSignalLevelAtShift(shOld, drawn, prefix, seconds, barsForward))
         {
            Audit("historical_level_fallback_drawn", "", 0, "", 0, 0, 0, 0, "reason=" + reason + " shift=" + IntegerToString(shOld) + " max_recent=" + IntegerToString(maxBars), 0, "");
            break;
         }
      }
   }
}

datetime NextHistoricalSignalTimeAfter(int currentShift)
{
   for(int sh = currentShift - 1; sh >= 1; sh--)
   {
      string dir, prevDir;
      double raw = 0.0, prevRaw = 0.0;
      int buf = -1, prevBuf = -1;
      if(!TrendStateAt(sh, dir, raw, buf)) continue;
      bool prevState = TrendStateAt(sh + 1, prevDir, prevRaw, prevBuf);
      if(prevState && prevDir == dir) continue;
      return Time[sh];
   }
   return 0;
}

void DrawTradeLevels()
{
   DeleteTradeLevels();
   if(HasOpenManagedTradeLevels())
      DeleteLatestSignalLevels();
   if(g_basketModeRuntime)
      return;
   int seconds = MathMax(60, Period() * 60);
   int barsForward = MathMax(1, InpSignalLevelBars);
   datetime nowT = Time[0] > 0 ? Time[0] : TimeCurrent();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int t = OrderTicket();
      datetime t0 = OrderOpenTime() > 0 ? OrderOpenTime() : nowT;
      datetime t1 = MathMax(nowT + barsForward * seconds, t0 + barsForward * seconds);
      TradeLevelSegment("PRORENKO_LVL_" + IntegerToString(t) + "_ENTRY", t0, t1, OrderOpenPrice(), clrWhite, STYLE_DOT, "LIVE ENTRY");
      TradeLevelSegment("PRORENKO_LVL_" + IntegerToString(t) + "_SL", t0, t1, OrderStopLoss(), clrTomato, STYLE_SOLID, "LIVE SL");
      TradeLevelSegment("PRORENKO_LVL_" + IntegerToString(t) + "_TP", t0, t1, OrderTakeProfit(), clrLimeGreen, STYLE_SOLID, "LIVE TP");
      double half = TicketGV(t, "HTP", 0);
      int halfIdx = (int)TicketGV(t, "HIDX", 0);
      if(halfIdx > 0 && half > 0.0)
         TradeLevelSegment("PRORENKO_LVL_" + IntegerToString(t) + "_HCBE", t0, t1, half, clrGold, STYLE_DASH, "LIVE HCBE " + RLabel(TicketGV(t, "HBR", halfIdx)));
   }
}

void DrawCalculatedFallbackLevels(int ticket, double sl, double tp1, double tp2, double tp3)
{
   DeleteCalculatedFallbackLevels(ticket);
   datetime t0 = Time[0] > 0 ? Time[0] : TimeCurrent();
   datetime t1 = t0 + MathMax(1, InpSignalLevelBars) * MathMax(60, Period() * 60);
   double entryForCalc = 0.0;
   int typeForCalc = OP_BUY;
   if(OrderSelect(ticket, SELECT_BY_TICKET))
   {
      entryForCalc = OrderOpenPrice();
      typeForCalc = OrderType();
   }
   double target = (entryForCalc > 0.0 ? TpByR(typeForCalc, entryForCalc, sl, g_targetRRuntime) : TpByIndex(g_targetTpRuntime, tp1, tp2, tp3));
   double half = (entryForCalc > 0.0 ? TpByR(typeForCalc, entryForCalc, sl, g_halfRRuntime) : TpByIndex(g_halfTpRuntime, tp1, tp2, tp3));
   CalcSegment("PRORENKO_CALC_" + IntegerToString(ticket) + "_SL", t0, t1, sl, clrOrangeRed, STYLE_DASHDOT, "CALC SL");
   CalcSegment("PRORENKO_CALC_" + IntegerToString(ticket) + "_TP", t0, t1, target, clrLimeGreen, STYLE_DASHDOT, "CALC TP " + RLabel(g_targetRRuntime));
   if(g_halfRRuntime > 0.0 && half > 0.0)
      CalcSegment("PRORENKO_CALC_" + IntegerToString(ticket) + "_HCBE", t0, t1, half, clrGold, STYLE_DASHDOT, "CALC HCBE " + RLabel(g_halfRRuntime));
}

void CalcSegment(string name, datetime t0, datetime t1, double price, color clr, int style, string text)
{
   if(price <= 0.0 || t0 <= 0 || t1 <= t0) return;
   ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price);
   ObjectSetInteger(0, name, OBJPROP_RAY, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text + " " + PriceText(price));
}

void DeleteCalculatedFallbackLevels(int ticket)
{
   string prefix = "PRORENKO_CALC_" + IntegerToString(ticket) + "_";
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0) ObjectDelete(0, name);
   }
}

void DeleteAllCalculatedFallbackLevels()
{
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "PRORENKO_CALC_") == 0) ObjectDelete(0, name);
   }
}

void TradeLevelSegment(string name, datetime t0, datetime t1, double price, color clr, int style, string text)
{
   if(price <= 0.0 || t0 <= 0 || t1 <= t0) return;
   ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price);
   ObjectSetInteger(0, name, OBJPROP_RAY, false);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text + " " + PriceText(price));
}

void CleanupLegacyInfiniteLevelLines()
{
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "PRORENKO_LVL_") == 0 || StringFind(name, "PRORENKO_CALC_") == 0)
         ObjectDelete(0, name);
   }
}

void DeleteTradeLevels()
{
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "PRORENKO_LVL_") == 0) ObjectDelete(0, name);
   }
}

