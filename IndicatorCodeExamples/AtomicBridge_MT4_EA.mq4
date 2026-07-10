//+------------------------------------------------------------------+
//| Atomic Bridge MT4 EA                                             |
//| Reads Atomic chart objects and logs latest direction/entry/SL/TPs |
//| for ProTrade integration mapping.                                |
//+------------------------------------------------------------------+
#property strict

#define ATOMIC_BRIDGE_BUILD "2026-07-10.risk-apply-publish"

input string InpIndicatorName = "Atomic";
input int    InpPollSeconds = 1;
input bool   InpLogOnInit = true;
input bool   InpLogOnlyOnChange = true;
input bool   InpDebugObjects = false;
input bool   InpLogPostResponses = false;
input bool   InpLogHandshakeResponses = true;
input bool   InpLogNoneSignals = false;
input bool   InpLogRegimeBuffer = false;
input bool   InpShowDashboard = true;
input bool   InpEnableAtomicMode = true;
input bool   InpEnableAtomicRegimeMode = true;
input int    InpInitialSetupRetrySeconds = 30;
input string InpIgnoreNamePatterns = "autotrade,->";
input bool   InpEnableProTradePost = false;
input bool   InpSendUnregisterOnDeinit = true;
input bool   InpSendInitialConfirmedOnStart = false;
input int    InpResolvedHeartbeatSeconds = 300;
input int    InpRegisterHeartbeatSeconds = 900;
input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "atomic";
input int    InpHttpTimeoutMs = 5000;
input bool   InpFileBridgeMt5Enabled = false; // Writes confirmed Atomic/AtomicRegime signals to Terminal Common\Files for MT5 execution.
input string InpFileBridgeLatestFile = "AtomicFileBridge_Latest.csv";
input string InpFileBridgeAuditPrefix = "AtomicFileBridge_Audit_";
input bool   InpFileBridgeUseCommonFiles = true;
input bool   InpGannFollowModeEnabled = false; // If true, Atomic/Regime trades only in same direction as latest GannMadeEasy state for this symbol+selected TF.
input string InpGannFollowStatePrefix = "GannMadeEasy_ActiveSignal_";
input bool   InpGannFollowUseCommonFiles = true;
input bool   InpGannFollowFailClosed = true;
input int    InpGannFollowTimeframe = 0; // 0=current chart TF, otherwise MT4 period minutes: 1,5,15,30,60,240,1440.
input bool   InpDirectMt4ExecutionEnabled = true;
input string InpDirectMt4Priority = "post_first"; // direct_first | post_first
input double InpDirectMt4Lot = 0.10; // Manual fallback when automatic risk sizing is unavailable.
input bool   InpDirectMt4AutoLotEnabled = true;
input int    InpDirectMt4AutoLotDailyAtrPeriod = 14;
input double InpDirectMt4AutoLotMax = 0.00; // 0=broker maximum only.
input bool   InpAdvancedAccountRiskEnabled = true;
input double InpAccountRiskPerTradePct = 1.00;
input double InpAccountRiskDailyAtrExposurePct = 2.00;
input double InpAccountRiskMaxPortfolioPct = 4.00;
input double InpAccountRiskDailyLossLimitPct = 0.00;
input double InpAccountRiskMaxDrawdownPct = 0.00;
input double InpAccountRiskMaxMarginUsagePct = 40.00;
input double InpAccountRiskInitialBalanceOverride = 0.00;
input int    InpAccountRiskDayResetHourGmt = 0;
input bool   InpAccountRiskLiquidateOnBreach = true;
input double InpAccountRiskSafetyBufferPct = 95.00;
input bool   InpAccountRiskBlockUnprotectedPositions = true;
input bool   InpAccountRiskFailClosed = true;
input bool   InpAccountRiskAuditEnabled = true;
input int    InpAccountRiskAuditIntervalSeconds = 60;
input int    InpDirectMt4Magic = 970101;
input string InpDirectMt4InstanceTag = ""; // Optional manual instance key. Blank=auto key from current strategy variant.
input int    InpDirectMt4Slippage = 30;
input int    InpDirectMt4MaxSpreadPoints = 0;
input double InpDirectMt4MaxSpreadToSlPct = 20.0; // Blocks MT4+MT5 file bridge when spread exceeds this % of entry-to-SL distance. 0=off.
input double InpDirectMt4DailyProfitTarget = 0.0; // Chart-symbol realized AtomicBridge profit target for today. 0=off; blocks this chart's MT4 execution and MT5 CSV signals until next reset day.
input double InpDirectMt4DailyLossTarget = 0.0; // Chart-symbol realized AtomicBridge loss limit for today. 0=off; blocks this chart's MT4 execution and MT5 CSV signals until next reset day.
input string InpDirectMt4AllowedTradeWindowsGmt = "";
input string InpDirectMt4NoTradeWindowsGmt = "21:55-22:10";
input string InpDirectMt4UtcEventBlockTimesGmt = ""; // HH:MM[,HH:MM...] UTC centers. Blocks new entries +/- InpDirectMt4UtcEventBlockRadiusMinutes; latest valid signal is retried after block.
input int    InpDirectMt4UtcEventBlockRadiusMinutes = 5;
input bool   InpDirectMt4CloseReverse = true;
input int    InpDirectMt4TpIndex = 5;
input bool   InpAtomicDirectRiskGeometryEnabled = false; // false=indicator SL; true=derive SL from selected TP leg and target R.
input double InpAtomicDirectTargetR = 2.0; // Supported dashboard choices: 0.5, 1.0, 2.0, 3.0.
input bool   InpAtomicInvertTradeMode = false; // Normal Atomic only. BUY<->SELL and exact SL/TP line-color swap; signal detection math is unchanged.
input int    InpAtomicInvertHcBeProgressPct = 0; // 0/25/50/75. Invert-only HC/BE trigger as % of inverted TP path.
input double InpAtomicInvertTargetR = 0.0; // 0=pure swap: normal SL becomes inverted TP. >0 overrides inverted TP distance in R; SL remains swapped normal TP.
input double InpDirectMt4HalfBeR = 2.0;
input int    InpDirectMt4HalfBeTpIndex = 2;
input double InpRegimeDirectMt4HalfBeR = 0.0; // 0=disabled by design; AtomicRegime exits fully at InpRegimeRR
input bool   InpDirectMt4AuditCsv = true;
input int    InpDirectMt4HistoryAuditSeconds = 2;
input bool   InpDirectMt4PositionProbeAudit = false; // Compact audit default: disable high-frequency position telemetry; lifecycle/errors still write.
input int    InpDirectMt4PositionProbeIntervalSeconds = 30;
input bool   InpDirectMt4PositionProbeWriteOnChange = true;
input bool   InpRegimeSignalProbeAudit = false; // Compact audit default: disable high-frequency regime probe telemetry; lifecycle/errors still write.
input int    InpRegimeSignalProbeIntervalSeconds = 30;
input bool   InpRegimeSignalProbeWriteOnChange = true;
input int    InpRegimeSignalProbeMaxShift = 20;
input bool   InpShowAtomicRegimeTradeLevels = true;
input bool   InpShowLatestAtomicRegimeSignalLevels = true;
input int    InpAtomicRegimeTradeLevelLabelBars = 8;
input int    InpAtomicRegimeHistoricalLevelBars = 24; // Historical Regime entry/SL/TP/HCBE segments length in chart bars.
input int    InpAtomicRegimeHistoricalMaxSignals = 160; // Caps visual overlay cost; signal math is untouched.
input bool   InpEnableRegimeChangePost = true;
input bool   InpSendInitialRegimeConfirmedOnStart = false;
input string InpRegimeSignalProfile = "atomic_regime";
input string InpRegimeIndicatorName = "AtomicRegime";
input int    InpRegimeAtrPeriod = 14;
input double InpRegimeAtrMultiplier = 3.0;
input double InpRegimeRR = 2.0;
input double InpRegimeMinRiskPricePct = 0.00100;
input double InpRegimeMaxRiskPricePct = 0.00300;
input double InpRegimeMaxRiskMoneyPerLot = 0.0;
input double InpRegimeMinRiskPoints = 0.0;
input bool   InpRegimeClampSlToAtomicSignalSl = true;
input bool   InpRegimeSlWidenEnabled = true;
input double InpRegimeSlWidenPct = 25.0;
input double InpRegimeFinalRiskScalePct = 75.0; // 100=unchanged; dashboard accepts 1..200 for fine Regime SL/TP scaling.
input bool   InpRegimePipSlModeEnabled = false; // If true, AtomicRegime SL distance is fixed by InpRegimePipSlPips; TP/HCBE still use R values.
input double InpRegimePipSlPips = 100.0;
input bool   InpRegimeStructuralSwingSlModeEnabled = false; // NAS-style local min/peak + ATR buffer SL. Signal math is unchanged.
input bool   InpRegimeSignalOpenSlModeEnabled = false; // If true, Regime SL distance = abs(execution entry - open of the signal bar). Signal math is unchanged.
input int    InpRegimeSwingLookbackBars = 200;
input int    InpRegimeSwingLeftBars = 3;
input int    InpRegimeSwingRightBars = 2;
input int    InpRegimeSwingAtrPeriod = 14;
input double InpRegimeSwingMinProminenceAtr = 0.75;
input double InpRegimeSwingMinDepartureAtr = 1.00;
input int    InpRegimeSwingMaxAgeBars = 60; // 0=off. Prevents old major highs/lows from being treated as the local structural stop.
input double InpRegimeSwingMaxRiskAtr = 4.00; // 0=off. Rejects pivots whose entry-to-SL risk is too large versus local ATR.
input double InpRegimeSwingBufferAtr = 0.20;
input bool   InpRegimeSwingPreferStrongest = false; // false=nearest local pivot; true=best nearby pivot after age/risk filters.
input bool   InpRegimeSwingFallbackToExtreme = true; // If no strict pivot passes, use window local low/high with same buffer.
input bool   InpRegimeUseTrendSignalBuffers = true;
input int    InpRegimeUpTrendSignalBuffer = 2;
input int    InpRegimeDnTrendSignalBuffer = 3;
input bool   InpRegimeUseTrendStopBuffers = false;
input int    InpRegimeUpTrendStopBuffer = 0;
input int    InpRegimeDnTrendStopBuffer = 1;
input bool   InpRegimeUseAtomicSignalAsTieBreak = true;
input bool   InpRegimeUseClosedBar = true;
input int    InpRegimeBufferLookbackBars = 200;
input bool   InpRegimeDelayValidationMode = false; // false=direct shift-1 execution; true=live delay confirmation.
input bool   InpRegimeCloseIfSignalVanishesAfterOpen = false; // false=do not auto-close a filled Regime trade just because the indicator repaints/shift-stales after fill.
input int    InpRegimeConfirmDelaySeconds = 300; // 0=confirm immediately; -1=use legacy stable seconds.
input int    InpRegimeConfirmStableSeconds = 5;
input int    InpRegimeMaxConfirmShift = 1;
input int    InpRegimeAtomicCompanionSyncSeconds = 0; // 0=disabled. Optional wait for Atomic object SL/TP when Atomic+Regime fire on the same bar.
input bool   InpRegimeOpenPreWindowSignal = false; // If true, AtomicRegime signals seen before allowed window can execute when the window opens if still valid.

string   g_lastEventId = "";
datetime g_lastSignalTime = 0;
string   g_lastConfirmedEventId = "";
string   g_lastObservedSignalDirection = "";
datetime g_lastObservedSignalTime = 0;
double   g_lastObservedSignalValue = 0.0;
datetime g_lastResolvedPostTime = 0;
datetime g_lastRegisterPostTime = 0;
datetime g_initialSetupRetryUntil = 0;
string   g_lastRegimeDirection = "";
string   g_lastRegimeEventId = "";
string   g_lastRegimeConfirmedEventId = "";
datetime g_lastRegimeResolvedPostTime = 0;
int      g_lastRegimeSignalIndex = -1;
datetime g_lastRegimeSignalTime = 0;
string   g_lastRegimeConfirmedDirection = "";
datetime g_lastRegimeConfirmedSignalTime = 0;
string   g_lastRegimeObservedSignalDirection = "";
datetime g_lastRegimeObservedSignalTime = 0;
double   g_lastRegimeObservedSignalValue = 0.0;
string   g_pendingRegimeEventId = "";
string   g_pendingRegimeDirection = "";
datetime g_pendingRegimeFirstSeen = 0;
datetime g_pendingRegimeSignalTime = 0;
int      g_pendingRegimeSignalIndex = -1;
string   g_lastRegimeLifecycleSignalEventId = "";
string   g_lastRegimeLifecycleDelayStartEventId = "";
string   g_lastRegimeLifecycleDelayFinishEventId = "";
string   g_lastRegimeCompanionSyncEventId = "";
datetime g_lastRegimeCompanionSyncFirstSeen = 0;
string   g_lastRegimeCompanionSyncedEventId = "";
string   g_lastRegimeDelayOpenedEventId = "";
datetime g_lastRegimeDelayOpenedSignalTime = 0;
string   g_lastRegimeDelayOpenedDirection = "";
string   g_lastRegimeDirectSh0EventId = "";
datetime g_lastRegimeDirectSh0SignalTime = 0;
string   g_lastRegimeDirectSh0Direction = "";
bool     g_lastRegimeDirectSh0PendingValidation = false;
string   g_pendingRegimeWindowEventId = "";
string   g_pendingRegimeWindowDirection = "";
datetime g_pendingRegimeWindowSignalTime = 0;
datetime g_pendingRegimeWindowFirstSeen = 0;
double   g_pendingRegimeWindowSl = 0.0;
double   g_pendingRegimeWindowTp = 0.0;
double   g_pendingRegimeWindowHalfTrigger = 0.0;
string   g_pendingRegimeWindowHalfLabel = "";
string   g_pendingDirectEventBlockEventId = "";
string   g_pendingDirectEventBlockDirection = "";
string   g_pendingDirectEventBlockSource = "";
datetime g_pendingDirectEventBlockSignalTime = 0;
datetime g_pendingDirectEventBlockFirstSeen = 0;
double   g_pendingDirectEventBlockSl = 0.0;
double   g_pendingDirectEventBlockTp = 0.0;
double   g_pendingDirectEventBlockHalfTrigger = 0.0;
string   g_pendingDirectEventBlockHalfLabel = "";
string   g_lastDirectMt4EventId = "";
bool     g_fileBridgeMt5EnabledRuntime = false;
bool     g_proTradePostEnabledRuntime = true;
bool     g_directMt4EnabledRuntime = false;
bool     g_directMt4PriorityDirectFirst = true;
bool     g_atomicModeEnabledRuntime = true;
bool     g_atomicRegimeModeEnabledRuntime = true;
double   g_directMt4LotRuntime = 0.0;
int      g_directMt4MaxSpreadRuntime = 0;
double   g_directMt4MaxSpreadToSlPctRuntime = 20.0;
double   g_directMt4DailyProfitTargetRuntime = 0.0;
double   g_directMt4DailyLossTargetRuntime = 0.0;
int      g_directMt4TpIndexRuntime = 5;
bool     g_atomicDirectRiskGeometryRuntime = false;
double   g_atomicDirectTargetRRuntime = 2.0;
bool     g_atomicInvertTradeModeRuntime = false;
int      g_atomicInvertHcBeProgressPctRuntime = 0;
double   g_atomicInvertTargetRRuntime = 0.0;
double   g_directMt4HalfBeRRuntime = 0.0;
int      g_directMt4HalfBeTpIndexRuntime = 2;
double   g_regimeDirectMt4HalfBeRRuntime = 0.0;
double   g_regimeRRRuntime = 0.0;
double   g_regimeFinalRiskScalePctRuntime = 100.0;
bool     g_regimePipSlModeRuntime = false;
double   g_regimePipSlPipsRuntime = 100.0;
bool     g_regimeStructuralSwingSlModeRuntime = false;
bool     g_regimeSignalOpenSlModeRuntime = false;
string   g_latestRegimeLevelDirection = "";
double   g_latestRegimeLevelEntry = 0.0;
double   g_latestRegimeLevelSl = 0.0;
double   g_latestRegimeLevelTp = 0.0;
double   g_latestRegimeLevelHalf = 0.0;
datetime g_latestRegimeLevelSignalTime = 0;
string   g_latestRegimeLevelEventId = "";
string   g_latestAtomicLevelDirection = "";
double   g_latestAtomicLevelEntry = 0.0;
double   g_latestAtomicLevelSl = 0.0;
double   g_latestAtomicLevelTp = 0.0;
double   g_latestAtomicLevelHalf = 0.0;
datetime g_latestAtomicLevelSignalTime = 0;
string   g_latestAtomicLevelMode = "";
bool     g_regimeUseClosedBarRuntime = true;
bool     g_regimeDelayValidationRuntime = false;
bool     g_regimeCloseIfVanishesRuntime = false;
int      g_regimeConfirmDelaySecondsRuntime = 300;
bool     g_regimeOpenPreWindowSignalRuntime = false;
string   g_directMt4AllowedWindowsRuntime = "";
string   g_directMt4NoTradeWindowsRuntime = "";
string   g_directMt4UtcEventBlockTimesRuntime = "";
int      g_directMt4UtcEventBlockRadiusRuntime = 5;
bool     g_gannFollowModeRuntime = false;
int      g_gannFollowTfRuntime = 0;
string   g_gannFollowLastDirection = "";
string   g_gannFollowLastDetail = "not_read";
datetime g_gannFollowLastSignalTime = 0;
datetime g_gannFollowLastReadGmt = 0;
bool     g_ftmoModeRuntime = false;
bool     g_riskLotOnlyRuntime = false;
bool     g_auditEnabledRuntime = true;
bool     g_dashboardCollapsed = false;
uint     g_lastDashClickMs = 0;
string   g_lastDashClickObject = "";
uint     g_lastPostDisabledMs = 0;
datetime g_directMt4LastHistoryAuditScan = 0;
datetime g_directMt4LastHistoryAuditTime = 0;
int      g_directMt4LastHistoryAuditTicket = 0;
datetime g_directMt4LastPositionProbe = 0;
string   g_directMt4LastPositionProbeHash = "";
datetime g_lastRegimeSignalProbe = 0;
string   g_lastRegimeSignalProbeHash = "";
string   g_regimeHistoryLevelsHash = "";
datetime g_lastTickLocal = 0;
string   DASH_PREFIX = "ATOMIC_BRIDGE_DASH_";
string   REGIME_LEVEL_PREFIX = "ATOMIC_REGIME_TRADE_LEVEL_";
string   REGIME_HIST_LEVEL_PREFIX = "ATOMIC_REGIME_HIST_LEVEL_";
string   ATOMIC_LEVEL_PREFIX = "ATOMIC_SIGNAL_LEVEL_";
uint     g_lastAccountRiskGuardMs = 0;
double   g_accountRiskLockValue = 0.0;
double   g_accountRiskPerTradePctRuntime = 1.0;
uint     g_riskApplyFeedbackUntilMs = 0;

bool _account_risk_enabled_runtime()
{
   return (g_ftmoModeRuntime || g_riskLotOnlyRuntime);
}

double _account_risk_per_trade_pct()
{
   return MathMax(0.0, g_accountRiskPerTradePctRuntime);
}

double _effective_daily_loss_limit_pct()
{
   if(!g_ftmoModeRuntime)
      return 0.0;
   return (InpAccountRiskDailyLossLimitPct > 0.0 ? InpAccountRiskDailyLossLimitPct : 5.0);
}

double _effective_max_drawdown_pct()
{
   if(!g_ftmoModeRuntime)
      return 0.0;
   return (InpAccountRiskMaxDrawdownPct > 0.0 ? InpAccountRiskMaxDrawdownPct : 10.0);
}

bool _effective_liquidate_on_breach()
{
   return (g_ftmoModeRuntime && InpAccountRiskLiquidateOnBreach);
}

bool _audit_enabled_runtime()
{
   return g_auditEnabledRuntime;
}

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string _compact_bridge_response(string response)
{
   string out = _trim(response);
   StringReplace(out, "\r", " ");
   StringReplace(out, "\n", " ");
   if(StringLen(out) > 500)
      out = StringSubstr(out, 0, 500) + "...";
   return out;
}

bool _should_log_handshake_response(string eventKind, string reason)
{
   if(!InpLogHandshakeResponses)
      return false;
   string evt = _trim(eventKind);
   string why = _trim(reason);
   if(evt == "unregister")
      return true;
   if(evt == "register")
      return (why == "init" || why == "init_retry");
   return (why == "init" || why == "init_retry");
}

string _lower_copy(string s)
{
   string out = s;
   StringToLower(out);
   return out;
}

bool _contains_ci(string h, string n)
{
   StringToLower(h);
   StringToLower(n);
   return StringLen(n) > 0 && StringFind(h, n) >= 0;
}

int _direct_minutes_from_hhmm(string value)
{
   string s = _trim(value);
   int pos = StringFind(s, ":");
   if(pos <= 0)
      return -1;
   int hh = StrToInteger(StringSubstr(s, 0, pos));
   int mm = StrToInteger(StringSubstr(s, pos + 1));
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return -1;
   return hh * 60 + mm;
}

bool _direct_minute_in_range(int minuteOfDay, string rangeText)
{
   string s = _trim(rangeText);
   int sep = StringFind(s, "-");
   if(sep <= 0)
      return false;
   int start = _direct_minutes_from_hhmm(StringSubstr(s, 0, sep));
   int stop = _direct_minutes_from_hhmm(StringSubstr(s, sep + 1));
   if(start < 0 || stop < 0)
      return false;
   int cur = MathMax(0, MathMin(1439, minuteOfDay));
   if(start == stop)
      return true;
   if(start < stop)
      return (cur >= start && cur < stop);
   return (cur >= start || cur < stop);
}

bool _direct_in_no_trade_window_gmt()
{
   string raw = _trim(g_directMt4NoTradeWindowsRuntime);
   if(StringLen(raw) <= 0)
      return false;
   datetime nowGmt = TimeGMT();
   int minute = TimeHour(nowGmt) * 60 + TimeMinute(nowGmt);
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   string parts[];
   int n = StringSplit(raw, 44, parts);
   for(int i = 0; i < n; i++)
   {
      if(_direct_minute_in_range(minute, parts[i]))
         return true;
   }
   return false;
}

bool _direct_in_allowed_trade_window_gmt()
{
   string raw = _trim(g_directMt4AllowedWindowsRuntime);
   if(StringLen(raw) <= 0)
      return true;
   datetime nowGmt = TimeGMT();
   int minute = TimeHour(nowGmt) * 60 + TimeMinute(nowGmt);
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   string parts[];
   int n = StringSplit(raw, 44, parts);
   for(int i = 0; i < n; i++)
   {
      if(_direct_minute_in_range(minute, parts[i]))
         return true;
   }
   return false;
}

bool _direct_in_utc_event_block_gmt()
{
   string raw = _trim(g_directMt4UtcEventBlockTimesRuntime);
   int radius = MathMax(0, MathMin(60, g_directMt4UtcEventBlockRadiusRuntime));
   if(StringLen(raw) <= 0 || radius <= 0)
      return false;
   datetime nowGmt = TimeGMT();
   int minute = TimeHour(nowGmt) * 60 + TimeMinute(nowGmt);
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   string parts[];
   int n = StringSplit(raw, 44, parts);
   for(int i = 0; i < n; i++)
   {
      int center = _direct_minutes_from_hhmm(parts[i]);
      if(center < 0) continue;
      int diff = (int)MathAbs(minute - center);
      diff = MathMin(diff, 1440 - diff);
      if(diff <= radius)
         return true;
   }
   return false;
}

string _direct_utc_event_block_status()
{
   return "utc_event_block='" + g_directMt4UtcEventBlockTimesRuntime + "' radius_min=" + IntegerToString(g_directMt4UtcEventBlockRadiusRuntime)
      + " now=" + TimeToString(TimeGMT(), TIME_MINUTES);
}

int _regime_base_shift()
{
   if(g_regimeDelayValidationRuntime)
      return 0;
   return (g_regimeUseClosedBarRuntime ? 1 : 0);
}

int _regime_effective_delay_seconds()
{
   if(!g_regimeDelayValidationRuntime)
      return 0;
   return (g_regimeConfirmDelaySecondsRuntime >= 0 ? MathMax(0, g_regimeConfirmDelaySecondsRuntime) : MathMax(0, InpRegimeConfirmStableSeconds));
}


bool _regime_window_pending_is_active()
{
   return (g_pendingRegimeWindowEventId != "" && g_pendingRegimeWindowDirection != "" && g_pendingRegimeWindowSignalTime > 0);
}

void _regime_window_pending_clear()
{
   g_pendingRegimeWindowEventId = "";
   g_pendingRegimeWindowDirection = "";
   g_pendingRegimeWindowSignalTime = 0;
   g_pendingRegimeWindowFirstSeen = 0;
   g_pendingRegimeWindowSl = 0.0;
   g_pendingRegimeWindowTp = 0.0;
   g_pendingRegimeWindowHalfTrigger = 0.0;
   g_pendingRegimeWindowHalfLabel = "";
}

void _regime_window_pending_store(string eventId, string direction, datetime signalTime, double sl, double tp, double halfTriggerPrice, string halfLabel)
{
   if(!g_regimeOpenPreWindowSignalRuntime || eventId == "" || signalTime <= 0)
      return;
   if(g_pendingRegimeWindowEventId == eventId)
      return;
   g_pendingRegimeWindowEventId = eventId;
   g_pendingRegimeWindowDirection = _trim(direction);
   g_pendingRegimeWindowSignalTime = signalTime;
   g_pendingRegimeWindowFirstSeen = _timer_now();
   g_pendingRegimeWindowSl = sl;
   g_pendingRegimeWindowTp = tp;
   g_pendingRegimeWindowHalfTrigger = halfTriggerPrice;
   g_pendingRegimeWindowHalfLabel = halfLabel;
   _regime_lifecycle_audit(
      "regime_deferred_until_window",
      eventId,
      g_pendingRegimeWindowDirection,
      -1,
      signalTime,
      0.0,
      sl,
      tp,
      "outside_allowed_window",
      g_pendingRegimeWindowFirstSeen,
      0,
      0,
      0,
      "allowed_gmt='" + g_directMt4AllowedWindowsRuntime + "'"
   );
}

void _regime_window_pending_try(string reason)
{
   if(!g_regimeOpenPreWindowSignalRuntime || !_regime_window_pending_is_active())
      return;
   if(!_direct_in_allowed_trade_window_gmt() || _direct_in_no_trade_window_gmt() || _direct_in_utc_event_block_gmt())
      return;

   string currentDir = "";
   string currentSource = "";
   int currentShift = -1;
   datetime currentTime = 0;
   double currentEntry = 0.0;
   bool stillValid = _find_current_atomic_regime_from_buffers("", currentDir, currentShift, currentTime, currentEntry, currentSource);
   string expectedCurrentDir = g_pendingRegimeWindowDirection;
   if(g_atomicInvertTradeModeRuntime)
      expectedCurrentDir = (g_pendingRegimeWindowDirection == "BUY" ? "SELL" : "BUY");
   if(!stillValid || currentDir != expectedCurrentDir || currentTime != g_pendingRegimeWindowSignalTime)
   {
      _regime_lifecycle_audit(
         "regime_deferred_window_cancelled",
         g_pendingRegimeWindowEventId,
         g_pendingRegimeWindowDirection,
         currentShift,
         g_pendingRegimeWindowSignalTime,
         currentEntry,
         g_pendingRegimeWindowSl,
         g_pendingRegimeWindowTp,
         "signal_changed_or_missing_before_window_open",
         g_pendingRegimeWindowFirstSeen,
         _timer_now(),
         0,
         (g_pendingRegimeWindowFirstSeen > 0 ? (int)(_timer_now() - g_pendingRegimeWindowFirstSeen) : -1),
         "current_dir=" + currentDir + " expected_dir=" + expectedCurrentDir + " current_time=" + _fmt_time(currentTime)
      );
      _regime_window_pending_clear();
      return;
   }

   string eventId = g_pendingRegimeWindowEventId;
   string dir = g_pendingRegimeWindowDirection;
   double sl = g_pendingRegimeWindowSl;
   double tp = g_pendingRegimeWindowTp;
   double halfTrigger = g_pendingRegimeWindowHalfTrigger;
   string halfLabel = g_pendingRegimeWindowHalfLabel;
   datetime signalTime = g_pendingRegimeWindowSignalTime;
   int age = (g_pendingRegimeWindowFirstSeen > 0 ? (int)(_timer_now() - g_pendingRegimeWindowFirstSeen) : -1);
   _regime_lifecycle_audit(
      "regime_deferred_window_open_execute",
      eventId,
      dir,
      currentShift,
      signalTime,
      currentEntry,
      sl,
      tp,
      reason,
      g_pendingRegimeWindowFirstSeen,
      _timer_now(),
      0,
      age,
      "current_shift=" + IntegerToString(currentShift)
   );
   _regime_window_pending_clear();
   _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, halfTrigger, halfLabel, signalTime);
}

bool _direct_event_block_pending_is_active()
{
   return (g_pendingDirectEventBlockEventId != "" && g_pendingDirectEventBlockDirection != "");
}

void _direct_event_block_pending_clear()
{
   g_pendingDirectEventBlockEventId = "";
   g_pendingDirectEventBlockDirection = "";
   g_pendingDirectEventBlockSource = "";
   g_pendingDirectEventBlockSignalTime = 0;
   g_pendingDirectEventBlockFirstSeen = 0;
   g_pendingDirectEventBlockSl = 0.0;
   g_pendingDirectEventBlockTp = 0.0;
   g_pendingDirectEventBlockHalfTrigger = 0.0;
   g_pendingDirectEventBlockHalfLabel = "";
}

void _direct_event_block_pending_store(string eventId, string direction, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   if(eventId == "" || direction == "") return;
   if(g_pendingDirectEventBlockEventId == eventId) return;
   g_pendingDirectEventBlockEventId = eventId;
   g_pendingDirectEventBlockDirection = _trim(direction);
   g_pendingDirectEventBlockSource = source;
   g_pendingDirectEventBlockSignalTime = sourceSignalTime;
   g_pendingDirectEventBlockFirstSeen = _timer_now();
   g_pendingDirectEventBlockSl = sl;
   g_pendingDirectEventBlockTp = tp;
   g_pendingDirectEventBlockHalfTrigger = halfTriggerPrice;
   g_pendingDirectEventBlockHalfLabel = halfTriggerLabel;
   _direct_audit_write("direct_defer_utc_event_block", source, eventId, 0, g_pendingDirectEventBlockDirection, g_directMt4LotRuntime,
      (g_pendingDirectEventBlockDirection == "BUY" ? Ask : Bid), sl, tp, _direct_utc_event_block_status(), 0.0,
      "will_retry_after_event_block_if_signal_still_current");
}

void _direct_event_block_pending_try(string reason)
{
   if(!_direct_event_block_pending_is_active()) return;
   if(!_direct_in_allowed_trade_window_gmt() || _direct_in_no_trade_window_gmt() || _direct_in_utc_event_block_gmt())
      return;

   bool sourceIsRegime = _contains_ci(g_pendingDirectEventBlockSource, "AtomicRegime");
   if(sourceIsRegime)
   {
      string currentDir = "";
      string currentSource = "";
      int currentShift = -1;
      datetime currentTime = 0;
      double currentEntry = 0.0;
      bool stillValid = _find_current_atomic_regime_from_buffers("", currentDir, currentShift, currentTime, currentEntry, currentSource);
      string expectedCurrentDir = g_pendingDirectEventBlockDirection;
      if(g_atomicInvertTradeModeRuntime)
         expectedCurrentDir = (g_pendingDirectEventBlockDirection == "BUY" ? "SELL" : "BUY");
      if(!stillValid || currentDir != expectedCurrentDir || (g_pendingDirectEventBlockSignalTime > 0 && currentTime != g_pendingDirectEventBlockSignalTime))
      {
         _direct_audit_write("direct_deferred_utc_event_block_cancelled", g_pendingDirectEventBlockSource, g_pendingDirectEventBlockEventId, 0,
            g_pendingDirectEventBlockDirection, g_directMt4LotRuntime, currentEntry, g_pendingDirectEventBlockSl, g_pendingDirectEventBlockTp,
            reason, 0.0, "current_dir=" + currentDir + " expected_dir=" + expectedCurrentDir + " current_time=" + _fmt_time(currentTime));
         _direct_event_block_pending_clear();
         return;
      }
   }

   string eventId = g_pendingDirectEventBlockEventId;
   string dir = g_pendingDirectEventBlockDirection;
   string source = g_pendingDirectEventBlockSource;
   double sl = g_pendingDirectEventBlockSl;
   double tp = g_pendingDirectEventBlockTp;
   double halfTrigger = g_pendingDirectEventBlockHalfTrigger;
   string halfLabel = g_pendingDirectEventBlockHalfLabel;
   datetime signalTime = g_pendingDirectEventBlockSignalTime;
   int age = (g_pendingDirectEventBlockFirstSeen > 0 ? (int)(_timer_now() - g_pendingDirectEventBlockFirstSeen) : -1);
   _direct_audit_write("direct_deferred_utc_event_block_release", source, eventId, 0, dir, g_directMt4LotRuntime,
      (dir == "BUY" ? Ask : Bid), sl, tp, reason, 0.0, "age_sec=" + IntegerToString(age));
   _direct_event_block_pending_clear();
   _direct_mt4_execute(eventId, dir, sl, tp, source, halfTrigger, halfLabel, signalTime);
}

string _direct_trade_window_status()
{
   if(!_direct_in_allowed_trade_window_gmt())
      return "BLOCK allowed_window";
   if(_direct_in_no_trade_window_gmt())
      return "BLOCK no_trade_window";
   if(_direct_in_utc_event_block_gmt())
      return "BLOCK utc_event";
   return "WINDOW OK";
}

string _direct_spread_status(int spread)
{
   string pointStatus = "pts OFF";
   if(g_directMt4MaxSpreadRuntime > 0)
      pointStatus = (spread > g_directMt4MaxSpreadRuntime)
         ? ("pts BLOCK " + IntegerToString(spread) + "/" + IntegerToString(g_directMt4MaxSpreadRuntime))
         : ("pts OK " + IntegerToString(spread) + "/" + IntegerToString(g_directMt4MaxSpreadRuntime));
   string pctStatus = (g_directMt4MaxSpreadToSlPctRuntime > 0.0)
      ? ("sl% max " + DoubleToString(g_directMt4MaxSpreadToSlPctRuntime, 1))
      : "sl% OFF";
   return "SPREAD " + pointStatus + " | " + pctStatus;
}

bool _direct_spread_to_sl_allowed(string direction, double entry, double sl, string &detail)
{
   detail = "";
   double maxPct = MathMax(0.0, g_directMt4MaxSpreadToSlPctRuntime);
   if(maxPct <= 0.0)
      return true;
   string dir = _trim(direction);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0 || sl <= 0.0)
   {
      detail = "spread_sl_pct_unavailable max_pct=" + DoubleToString(maxPct, 2) + " entry=" + _fmt_price(entry) + " sl=" + _fmt_price(sl);
      return true;
   }
   double riskDistance = MathAbs(entry - sl);
   double spreadPrice = MathMax(0.0, Ask - Bid);
   if(riskDistance <= Point || spreadPrice <= 0.0)
   {
      detail = "spread_sl_pct_unavailable max_pct=" + DoubleToString(maxPct, 2) + " spread_price=" + DoubleToString(spreadPrice, Digits) + " risk_distance=" + DoubleToString(riskDistance, Digits);
      return true;
   }
   double pct = (spreadPrice / riskDistance) * 100.0;
   detail = "spread_sl_pct=" + DoubleToString(pct, 2)
      + " max=" + DoubleToString(maxPct, 2)
      + " spread_price=" + DoubleToString(spreadPrice, Digits)
      + " risk_distance=" + DoubleToString(riskDistance, Digits)
      + " entry=" + _fmt_price(entry)
      + " sl=" + _fmt_price(sl);
   return (pct <= maxPct + 0.0001);
}

bool _direct_priority_direct_first()
{
   return g_directMt4PriorityDirectFirst;
}

int _direct_event_hash(string text)
{
   int h = 5381;
   for(int i = 0; i < StringLen(text); i++)
      h = ((h << 5) + h) + StringGetChar(text, i);
   if(h < 0)
      h = -h;
   return h;
}

string _direct_source_family(string source)
{
   return _contains_ci(source, "AtomicRegime") ? "AtomicRegime" : "Atomic";
}

string _direct_instance_signature(string source)
{
   string family = _direct_source_family(source);
   string tag = _trim(InpDirectMt4InstanceTag);
   string sig = family
      + "|acct=" + IntegerToString(AccountNumber())
      + "|sym=" + Symbol()
      + "|tf=" + _tf_to_string(Period())
      + "|magic=" + IntegerToString(InpDirectMt4Magic);
   if(tag != "")
      sig += "|tag=" + tag;
   if(family == "AtomicRegime")
   {
      string slMode = "scale";
      if(g_regimeSignalOpenSlModeRuntime) slMode = "sigopen";
      else if(g_regimePipSlModeRuntime) slMode = "pip";
      else if(g_regimeStructuralSwingSlModeRuntime) slMode = "swing";
      sig += "|rr=" + DoubleToString(g_regimeRRRuntime, 4)
         + "|hc=" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 4)
         + "|slmode=" + slMode
         + "|scale=" + DoubleToString(g_regimeFinalRiskScalePctRuntime, 2)
         + "|pips=" + DoubleToString(g_regimePipSlPipsRuntime, 2)
         + "|swing=" + IntegerToString(InpRegimeSwingLookbackBars) + ":" + IntegerToString(InpRegimeSwingLeftBars) + ":" + IntegerToString(InpRegimeSwingRightBars)
         + ":" + DoubleToString(InpRegimeSwingBufferAtr, 3) + ":" + DoubleToString(InpRegimeSwingMaxRiskAtr, 3)
         + "|shift=" + (g_regimeUseClosedBarRuntime ? "1" : "0")
         + "|delay=" + (g_regimeDelayValidationRuntime ? IntegerToString(g_regimeConfirmDelaySecondsRuntime) : "direct");
   }
   else
   {
      sig += "|tp=" + IntegerToString(g_directMt4TpIndexRuntime)
         + "|slmode=" + (g_atomicDirectRiskGeometryRuntime ? "geom" : "indic")
         + "|target=" + DoubleToString(g_atomicDirectTargetRRuntime, 4)
         + "|hcleg=" + IntegerToString(g_directMt4HalfBeTpIndexRuntime)
         + "|hcr=" + DoubleToString(g_directMt4HalfBeRRuntime, 4)
         + "|invert=" + (g_atomicInvertTradeModeRuntime ? "1" : "0")
         + "|invtp=" + DoubleToString(g_atomicInvertTargetRRuntime, 4)
         + "|invhc=" + IntegerToString(g_atomicInvertHcBeProgressPctRuntime);
   }
   return sig;
}

int _direct_instance_hash(string source)
{
   return _direct_event_hash(_direct_instance_signature(source));
}

string _direct_instance_token(string source)
{
   return "V" + IntegerToString(_direct_instance_hash(source));
}

bool _direct_comment_has_current_variant(string comment)
{
   int pos = StringFind(comment, "|V");
   if(pos < 0)
      return false;
   string family = _contains_ci(comment, "AtomicRegime") ? "AtomicRegime" : "Atomic";
   string expected = "|" + _direct_instance_token(family);
   return StringFind(comment, expected) >= 0;
}

string _direct_event_global_key(string eventId, string source)
{
   string variant = _direct_instance_signature(source);
   return "AtomicBridgeMT4|EVT|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + _tf_to_string(Period()) + "|" + IntegerToString(_direct_event_hash(eventId + "|" + variant));
}

bool _direct_event_claim(string eventId, string source)
{
   string key = _direct_event_global_key(eventId, source);
   double now = (double)TimeLocal();
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   double observed = GlobalVariableGet(key);
   if(observed > 0.0 && now - observed < 86400.0)
      return false;
   return GlobalVariableSetOnCondition(key, now, observed);
}

void _direct_event_release(string eventId, string source)
{
   GlobalVariableSet(_direct_event_global_key(eventId, source), 0.0);
}

bool _direct_close_reverse_positions(string direction)
{
   if(!InpDirectMt4CloseReverse)
      return true;
   int targetType = (direction == "BUY") ? OP_SELL : OP_BUY;
   bool ok = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()) || OrderType() != targetType)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;
      RefreshRates();
      int ticket = OrderTicket();
      string closedDirection = (OrderType() == OP_BUY) ? "BUY" : "SELL";
      double lots = OrderLots();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      string source = OrderComment();
      double closePx = (targetType == OP_BUY) ? Bid : Ask;
      if(!OrderClose(ticket, lots, closePx, InpDirectMt4Slippage, clrSilver))
      {
         int err = GetLastError();
         _direct_audit_write("direct_reverse_close_failed", source, "", ticket, closedDirection, lots, closePx, sl, tp, "err=" + IntegerToString(err), 0.0, "before_new_direction=" + direction);
         Print("AtomicBridge direct_mt4 reverse close failed ticket=", ticket, " err=", err);
         ok = false;
      }
      else
      {
         _direct_audit_write("direct_reverse_close_sent", source, "", ticket, closedDirection, lots, closePx, sl, tp, "before_new_direction=" + direction, 0.0, "");
      }
   }
   return ok;
}

bool _regime_close_delay_validation_positions(string eventId, string direction, string reason, int signalIndex, datetime signalTime)
{
   bool ok = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;
      if(!_contains_ci(OrderComment(), "AtomicRegime"))
         continue;
      string openDir = (OrderType() == OP_BUY) ? "BUY" : (OrderType() == OP_SELL ? "SELL" : "");
      if(openDir == "")
         continue;
      if(direction != "" && openDir != direction && !g_atomicInvertTradeModeRuntime)
         continue;
      RefreshRates();
      int ticket = OrderTicket();
      double lots = OrderLots();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      double closePx = (OrderType() == OP_BUY) ? Bid : Ask;
      string extra = "event_id=" + eventId
         + " signal_shift=" + IntegerToString(signalIndex)
         + " signal_time=" + _fmt_time(signalTime)
         + " signal_hms=" + _fmt_hms(signalTime);
      if(!OrderClose(ticket, lots, closePx, InpDirectMt4Slippage, clrTomato))
      {
         int err = GetLastError();
         _direct_audit_write("regime_signal_vanished_close_failed", OrderComment(), eventId, ticket, openDir, lots, closePx, sl, tp, "err=" + IntegerToString(err) + " " + reason, 0.0, extra);
         ok = false;
      }
      else
      {
         _direct_audit_write("regime_signal_vanished_close_sent", OrderComment(), eventId, ticket, openDir, lots, closePx, sl, tp, reason, 0.0, extra);
      }
   }
   return ok;
}

double _select_direct_tp(double tp1, double tp2, double tp3, double tp4, double tp5)
{
   int idx = MathMax(1, MathMin(5, g_directMt4TpIndexRuntime));
   if(idx == 1 && tp1 > 0.0) return tp1;
   if(idx == 2 && tp2 > 0.0) return tp2;
   if(idx == 3 && tp3 > 0.0) return tp3;
   if(idx == 4 && tp4 > 0.0) return tp4;
   if(idx == 5 && tp5 > 0.0) return tp5;
   if(tp5 > 0.0) return tp5;
   if(tp4 > 0.0) return tp4;
   if(tp3 > 0.0) return tp3;
   if(tp2 > 0.0) return tp2;
   return tp1;
}

double _direct_tp_by_index(int index, double tp1, double tp2, double tp3, double tp4, double tp5)
{
   int idx = MathMax(1, MathMin(5, index));
   if(idx == 1) return tp1;
   if(idx == 2) return tp2;
   if(idx == 3) return tp3;
   if(idx == 4) return tp4;
   return tp5;
}

double _atomic_supported_target_r(double value)
{
   double choices[4] = {0.5, 1.0, 2.0, 3.0};
   int best = 0;
   double bestDiff = MathAbs(value - choices[0]);
   for(int i = 1; i < 4; i++)
   {
      double diff = MathAbs(value - choices[i]);
      if(diff < bestDiff)
      {
         best = i;
         bestDiff = diff;
      }
   }
   return choices[best];
}

double _atomic_next_target_r(double value)
{
   double current = _atomic_supported_target_r(value);
   if(current < 0.75) return 1.0;
   if(current < 1.50) return 2.0;
   if(current < 2.50) return 3.0;
   return 0.5;
}

bool _atomic_r_geometry_sl(string direction, double entry, double targetTp, double targetR, double &sl, string &detail)
{
   detail = "";
   if(direction != "BUY" && direction != "SELL")
   {
      detail = "invalid_direction";
      return false;
   }
   double rr = _atomic_supported_target_r(targetR);
   double reward = (direction == "BUY") ? (targetTp - entry) : (entry - targetTp);
   if(entry <= 0.0 || targetTp <= 0.0 || reward <= Point * 2.0 || rr <= 0.0)
   {
      detail = "invalid_entry_or_selected_tp";
      return false;
   }
   double risk = reward / rr;
   double brokerMin = (MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL), MarketInfo(Symbol(), MODE_FREEZELEVEL)) + 2.0) * Point;
   if(risk < brokerMin)
      risk = brokerMin;
   sl = NormalizeDouble(direction == "BUY" ? entry - risk : entry + risk, Digits);
   double achievedR = (risk > Point ? reward / risk : 0.0);
   detail = "atomic_r_geometry target_r=" + DoubleToString(rr, 2)
      + " achieved_r=" + DoubleToString(achievedR, 3)
      + " reward=" + DoubleToString(reward, Digits)
      + " risk=" + DoubleToString(risk, Digits)
      + " broker_min=" + DoubleToString(brokerMin, Digits);
   return true;
}
bool _atomic_effective_sl_for_mode(string direction, double entry, double indicatorSl, double selectedTp, double &effectiveSl, string &detail)
{
   effectiveSl = indicatorSl;
   detail = "atomic_indicator_sl";
   if(!g_atomicDirectRiskGeometryRuntime)
      return (effectiveSl > 0.0);

   effectiveSl = indicatorSl;
   bool ok = _atomic_r_geometry_sl(direction, entry, selectedTp, g_atomicDirectTargetRRuntime, effectiveSl, detail);
   if(!ok)
      effectiveSl = 0.0;
   return ok;
}
bool _atomic_invert_enabled_for_event(string eventKind, string direction)
{
   string kind = _trim(eventKind);
   string dir = _trim(direction);
   return g_atomicInvertTradeModeRuntime && (dir == "BUY" || dir == "SELL") && (kind == "confirmed_signal" || kind == "resolved_state");
}

double _atomic_clamp_invert_target_r(double value)
{
   if(value <= 0.0)
      return 0.0;
   if(value < 0.10)
      return 0.10;
   if(value > 10.0)
      return 10.0;
   return NormalizeDouble(value, 2);
}

bool _atomic_invert_target_override_enabled()
{
   return g_atomicInvertTargetRRuntime > 0.0;
}

string _atomic_invert_target_text()
{
   if(!_atomic_invert_target_override_enabled())
      return "INV TP SWAP";
   return "INV TP " + DoubleToString(g_atomicInvertTargetRRuntime, 2) + "R";
}

double _atomic_invert_target_override_price(string tradeDirection, double entry, double sl)
{
   string dir = _trim(tradeDirection);
   double risk = MathAbs(entry - sl);
   if(!_atomic_invert_target_override_enabled() || (dir != "BUY" && dir != "SELL") || entry <= 0.0 || sl <= 0.0 || risk <= 0.0)
      return 0.0;
   double brokerMin = (MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL), MarketInfo(Symbol(), MODE_FREEZELEVEL)) + 2.0) * Point;
   double targetDistance = MathMax(risk * _atomic_clamp_invert_target_r(g_atomicInvertTargetRRuntime), brokerMin);
   return NormalizeDouble(dir == "BUY" ? entry + targetDistance : entry - targetDistance, Digits);
}

double _atomic_invert_hcbe_price(string tradeDirection, double entry, double finalTp)
{
   string dir = _trim(tradeDirection);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0 || finalTp <= 0.0)
      return 0.0;
   int pct = g_atomicInvertHcBeProgressPctRuntime;
   if(pct != 25 && pct != 50 && pct != 75)
      return 0.0;
   return NormalizeDouble(entry + (finalTp - entry) * ((double)pct / 100.0), Digits);
}

bool _atomic_build_inverted_geometry(string signalDirection, double signalEntry, double originalSl, double originalFinalTp, string &tradeDirection, double &sl, double &tp, string &detail)
{
   detail = "";
   string sigDir = _trim(signalDirection);
   if(sigDir != "BUY" && sigDir != "SELL")
   {
      detail = "invalid_signal_direction";
      return false;
   }
   if(signalEntry <= 0.0 || originalSl <= 0.0 || originalFinalTp <= 0.0)
   {
      detail = "missing_original_geometry entry=" + _fmt_price(signalEntry) + " sl=" + _fmt_price(originalSl) + " tp=" + _fmt_price(originalFinalTp);
      return false;
   }

   tradeDirection = (sigDir == "BUY") ? "SELL" : "BUY";
   sl = NormalizeDouble(originalFinalTp, Digits);
   tp = NormalizeDouble(originalSl, Digits);

   double overrideTp = _atomic_invert_target_override_price(tradeDirection, signalEntry, sl);
   if(overrideTp > 0.0)
      tp = overrideTp;

   double liveEntry = (tradeDirection == "BUY") ? MarketInfo(Symbol(), MODE_ASK) : MarketInfo(Symbol(), MODE_BID);
   if(liveEntry <= 0.0)
      liveEntry = signalEntry;
   double point = MarketInfo(Symbol(), MODE_POINT);
   if(point <= 0.0)
      point = Point;
   double minGap = MathMax(point * 2.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * point);
   bool slOk = (tradeDirection == "BUY") ? (sl < liveEntry - minGap) : (sl > liveEntry + minGap);
   bool tpOk = (tradeDirection == "BUY") ? (tp > liveEntry + minGap) : (tp < liveEntry - minGap);
   if(!slOk || !tpOk)
   {
      detail = "invalid_invert_side signal_dir=" + sigDir
         + " trade_dir=" + tradeDirection
         + " signal_entry=" + _fmt_price(signalEntry)
         + " live_entry=" + _fmt_price(liveEntry)
         + " swapped_sl=" + _fmt_price(sl)
         + " swapped_tp=" + _fmt_price(tp)
         + " min_gap=" + DoubleToString(minGap, Digits);
      return false;
   }

   detail = "atomic_inverted_execution signal_dir=" + sigDir
      + " trade_dir=" + tradeDirection
      + " signal_entry=" + _fmt_price(signalEntry)
      + " normal_sl_as_tp=" + _fmt_price(originalSl)
      + " normal_tp_as_sl=" + _fmt_price(originalFinalTp)
      + " invert_target=" + _atomic_invert_target_text()
      + " invert_hcbe_pct=" + IntegerToString(g_atomicInvertHcBeProgressPctRuntime)
      + " exact_line_swap=" + (_atomic_invert_target_override_enabled() ? "false" : "true");
   return true;
}

bool _atomic_build_inverted_geometry_for_levels(string signalDirection, double signalEntry, double originalSl, double originalFinalTp, string &tradeDirection, double &sl, double &tp, string &detail)
{
   detail = "";
   string sigDir = _trim(signalDirection);
   if(sigDir != "BUY" && sigDir != "SELL")
   {
      detail = "invalid_signal_direction";
      return false;
   }
   if(signalEntry <= 0.0 || originalSl <= 0.0 || originalFinalTp <= 0.0)
   {
      detail = "missing_original_geometry entry=" + _fmt_price(signalEntry) + " sl=" + _fmt_price(originalSl) + " tp=" + _fmt_price(originalFinalTp);
      return false;
   }
   tradeDirection = (sigDir == "BUY") ? "SELL" : "BUY";
   sl = NormalizeDouble(originalFinalTp, Digits);
   tp = NormalizeDouble(originalSl, Digits);
   double overrideTp = _atomic_invert_target_override_price(tradeDirection, signalEntry, sl);
   if(overrideTp > 0.0)
      tp = overrideTp;
   double point = MarketInfo(Symbol(), MODE_POINT);
   if(point <= 0.0)
      point = Point;
   double minGap = MathMax(point * 2.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * point);
   bool slOk = (tradeDirection == "BUY") ? (sl < signalEntry - minGap) : (sl > signalEntry + minGap);
   bool tpOk = (tradeDirection == "BUY") ? (tp > signalEntry + minGap) : (tp < signalEntry - minGap);
   if(!slOk || !tpOk)
   {
      detail = "invalid_invert_level_side signal_dir=" + sigDir
         + " trade_dir=" + tradeDirection
         + " signal_entry=" + _fmt_price(signalEntry)
         + " swapped_sl=" + _fmt_price(sl)
         + " swapped_tp=" + _fmt_price(tp)
         + " min_gap=" + DoubleToString(minGap, Digits);
      return false;
   }
   detail = "inverted_level_geometry signal_dir=" + sigDir
      + " trade_dir=" + tradeDirection
      + " normal_sl_as_tp=" + _fmt_price(originalSl)
      + " normal_tp_as_sl=" + _fmt_price(originalFinalTp)
      + " invert_target=" + _atomic_invert_target_text();
   return true;
}

bool _atomic_apply_invert_to_geometry_for_levels(string signalDirection, double signalEntry, double &sl, double &tp, double &hc, string &direction, string &detail)
{
   detail = "invert_off";
   if(!g_atomicInvertTradeModeRuntime)
      return false;
   string invDir = "";
   double invSl = 0.0;
   double invTp = 0.0;
   string invDetail = "";
   if(!_atomic_build_inverted_geometry_for_levels(signalDirection, signalEntry, sl, tp, invDir, invSl, invTp, invDetail))
   {
      detail = invDetail;
      return false;
   }
   direction = invDir;
   sl = invSl;
   tp = invTp;
   hc = _atomic_invert_hcbe_price(invDir, signalEntry, invTp);
   detail = invDetail;
   return true;
}
bool _regime_reanchor_pip_geometry(string tradeDirection, double liveEntry, bool invertGeometry, double &sl, double &tp, double &halfTriggerPrice, string &detail)
{
   detail = "";
   if(!_regime_pip_sl_enabled())
      return false;
   string dir = _trim(tradeDirection);
   double entry = _valid_price_or_zero(liveEntry);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0)
   {
      detail = "regime_pip_reanchor_invalid_entry";
      return false;
   }

   double pipSize = _symbol_pip_size();
   double requestedRisk = MathMax(0.0, g_regimePipSlPipsRuntime) * pipSize;
   double minStop = MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   double normalRisk = MathMax(requestedRisk, minStop);
   double rr = MathMax(0.1, g_regimeRRRuntime);
   double slDistance = invertGeometry ? normalRisk * rr : normalRisk;
   double tpDistance = invertGeometry ? normalRisk : normalRisk * rr;

   double oldSl = sl;
   double oldTp = tp;
   if(dir == "BUY")
   {
      sl = NormalizeDouble(entry - slDistance, Digits);
      tp = NormalizeDouble(entry + tpDistance, Digits);
   }
   else
   {
      sl = NormalizeDouble(entry + slDistance, Digits);
      tp = NormalizeDouble(entry - tpDistance, Digits);
   }

   if(invertGeometry)
   {
      double overrideTp = _atomic_invert_target_override_price(dir, entry, sl);
      if(overrideTp > 0.0)
         tp = overrideTp;
      bool halfRebased = false;
      string halfReason = "";
      halfTriggerPrice = _direct_normalize_half_trigger(dir, entry, sl, tp, 0.0, g_regimeDirectMt4HalfBeRRuntime, halfRebased, halfReason);
   }

   detail = (invertGeometry ? "regime_invert_pip_reanchored" : "regime_pip_reanchored")
      + " live_entry=" + _fmt_price(entry)
      + " pips=" + DoubleToString(g_regimePipSlPipsRuntime, 2)
      + " pip_size=" + DoubleToString(pipSize, Digits + 2)
      + " normal_risk=" + DoubleToString(normalRisk, Digits)
      + " rr=" + DoubleToString(rr, 2)
      + " sl_distance=" + DoubleToString(slDistance, Digits)
      + " tp_distance=" + DoubleToString(tpDistance, Digits)
      + " old_sl=" + _fmt_price(oldSl)
      + " new_sl=" + _fmt_price(sl)
      + " old_tp=" + _fmt_price(oldTp)
      + " new_tp=" + _fmt_price(tp)
      + " half=" + _fmt_price(halfTriggerPrice);
   return (sl > 0.0 && tp > 0.0);
}

bool _regime_reanchor_inverted_pip_geometry(string tradeDirection, double liveEntry, double &sl, double &tp, double &halfTriggerPrice, string &detail)
{
   if(!g_atomicInvertTradeModeRuntime)
      return false;
   return _regime_reanchor_pip_geometry(tradeDirection, liveEntry, true, sl, tp, halfTriggerPrice, detail);
}

bool _regime_reanchor_normal_pip_geometry(string tradeDirection, double liveEntry, double &sl, double &tp, double &halfTriggerPrice, string &detail)
{
   return _regime_reanchor_pip_geometry(tradeDirection, liveEntry, false, sl, tp, halfTriggerPrice, detail);
}
bool _direct_trigger_price_valid(string direction, double entry, double triggerPrice)
{
   if(triggerPrice <= 0.0 || entry <= 0.0)
      return false;
   double tol = MathMax(Point * 2.0, 0.00000001);
   if(direction == "BUY")
      return triggerPrice > entry + tol;
   if(direction == "SELL")
      return triggerPrice < entry - tol;
   return false;
}

double _direct_normalize_half_trigger(
   string direction,
   double entry,
   double sl,
   double tp,
   double requested,
   double halfR,
   bool &rebased,
   string &reason
)
{
   rebased = false;
   reason = "kept";
   if(!_direct_trigger_price_valid(direction, entry, requested))
   {
      rebased = true;
      reason = "wrong_side_of_fill";
      if(requested <= 0.0 && halfR <= 0.0)
      {
         reason = reason + "|disabled_by_config";
         return 0.0;
      }
   }
   else
   {
      bool beforeTp = (tp <= 0.0)
         || (direction == "BUY" && requested < tp - Point)
         || (direction == "SELL" && requested > tp + Point);
      if(beforeTp)
         return NormalizeDouble(requested, Digits);
      rebased = true;
      reason = "at_or_beyond_final_tp";
   }

   double risk = (sl > 0.0 ? MathAbs(entry - sl) : 0.0);
   double remaining = 0.0;
   if(tp > 0.0)
      remaining = (direction == "BUY") ? (tp - entry) : (entry - tp);
   double minDistance = MathMax(Point * 4.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point);
   if(risk <= Point || remaining <= minDistance)
   {
      reason = reason + "|disabled_no_profitable_room";
      return 0.0;
   }

   double desiredDistance = risk * MathMax(0.1, halfR);
   double safeDistance = MathMin(desiredDistance, remaining * 0.50);
   if(safeDistance < minDistance)
      safeDistance = remaining * 0.50;
   if(safeDistance < minDistance || safeDistance >= remaining - Point)
   {
      reason = reason + "|disabled_no_safe_trigger";
      return 0.0;
   }
   reason = reason + "|rebased_between_fill_and_tp";
   return NormalizeDouble(
      direction == "BUY" ? entry + safeDistance : entry - safeDistance,
      Digits
   );
}

bool _direct_be_price_legal(int orderType, double entry)
{
   RefreshRates();
   double brokerDistance = (
      MathMax(
         MarketInfo(Symbol(), MODE_STOPLEVEL),
         MarketInfo(Symbol(), MODE_FREEZELEVEL)
      ) + 2.0
   ) * Point;
   if(orderType == OP_BUY)
      return entry <= Bid - brokerDistance;
   if(orderType == OP_SELL)
      return entry >= Ask + brokerDistance;
   return false;
}

string _direct_trigger_gv_key(int ticket)
{
   return _direct_audit_gv_key("HTP", ticket);
}

double _direct_get_half_trigger_price(int ticket)
{
   string key = _direct_trigger_gv_key(ticket);
   if(!GlobalVariableCheck(key))
      return 0.0;
   return GlobalVariableGet(key);
}

void _direct_set_half_trigger_price(int ticket, double triggerPrice)
{
   if(ticket <= 0 || triggerPrice <= 0.0)
      return;
   GlobalVariableSet(_direct_trigger_gv_key(ticket), triggerPrice);
}

double _direct_state_get(string kind, int ticket)
{
   string key = _direct_audit_gv_key(kind, ticket);
   if(!GlobalVariableCheck(key))
      return 0.0;
   return GlobalVariableGet(key);
}

bool _direct_state_has(string kind, int ticket)
{
   if(ticket <= 0)
      return false;
   return GlobalVariableCheck(_direct_audit_gv_key(kind, ticket));
}

void _direct_state_set(string kind, int ticket, double value)
{
   if(ticket <= 0)
      return;
   GlobalVariableSet(_direct_audit_gv_key(kind, ticket), value);
}

void _direct_state_copy(string kind, int fromTicket, int toTicket)
{
   double value = _direct_state_get(kind, fromTicket);
   if(value > 0.0)
      _direct_state_set(kind, toTicket, value);
}

void _direct_state_copy_any(string kind, int fromTicket, int toTicket)
{
   if(_direct_state_has(kind, fromTicket))
      _direct_state_set(kind, toTicket, _direct_state_get(kind, fromTicket));
}

void _direct_update_excursion(int ticket, double px, double currentR)
{
   if(ticket <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET))
      return;
   double pnl = OrderProfit() + OrderSwap() + OrderCommission();
   double mfe = _direct_state_get("MFE", ticket);
   double mae = _direct_state_get("MAE", ticket);
   if(!_direct_state_has("MFE", ticket) || pnl > mfe)
   {
      _direct_state_set("MFE", ticket, pnl);
      _direct_state_set("MFE_PX", ticket, px);
   }
   if(!_direct_state_has("MAE", ticket) || pnl < mae)
   {
      _direct_state_set("MAE", ticket, pnl);
      _direct_state_set("MAE_PX", ticket, px);
   }
   double minR = _direct_state_get("MINR", ticket);
   if(!_direct_state_has("MINR", ticket) || currentR < minR)
      _direct_state_set("MINR", ticket, currentR);
}

int _direct_parent_ticket_from_comment(string source)
{
   int pos = StringFind(source, "from #");
   if(pos < 0)
      return 0;
   string tail = StringSubstr(source, pos + 6);
   string digits = "";
   for(int i = 0; i < StringLen(tail); i++)
   {
      int ch = StringGetCharacter(tail, i);
      if(ch < '0' || ch > '9')
         break;
      digits += StringSubstr(tail, i, 1);
   }
   return StrToInteger(digits);
}

bool _direct_legacy_comment_owned_by_chart(string source)
{
   if(StringFind(source, "|V") >= 0)
      return false;
   if(StringFind(source, "AtomicBridgeMT4|") < 0 && StringFind(source, "AtomicBridge|") < 0)
      return false;
   string tfToken = "|" + _tf_to_string(Period());
   return StringFind(source, tfToken) >= 0;
}
bool _direct_order_owned_by_instance(int ticket, string source, bool inheritPartial)
{
   double owner = _direct_state_get("OWNER", ticket);
   double variantOwner = _direct_state_get("VOWN", ticket);
   double expectedVariant = (double)_direct_instance_hash(source);
   if(owner > 0.0)
   {
      if((int)owner != Period())
         return false;
      if(variantOwner > 0.0)
         return (int)variantOwner == (int)expectedVariant;
      if(_direct_comment_has_current_variant(source))
         return true;
      return StringFind(source, "|V") < 0;
   }
   if(_direct_comment_has_current_variant(source))
      return true;
   if(_direct_legacy_comment_owned_by_chart(source))
      return true;
   if(!inheritPartial)
      return false;
   int parentTicket = _direct_parent_ticket_from_comment(source);
   if(parentTicket <= 0)
      return false;
   double parentOwner = _direct_state_get("OWNER", parentTicket);
   if(parentOwner <= 0.0)
      return false;
   _direct_state_copy("IRISK", parentTicket, ticket);
   _direct_state_copy("HTP", parentTicket, ticket);
   _direct_state_copy("TP1", parentTicket, ticket);
   _direct_state_copy("BE", parentTicket, ticket);
   _direct_state_copy("HALF", parentTicket, ticket);
   _direct_state_copy("SEEN", parentTicket, ticket);
   _direct_state_copy("MAXR", parentTicket, ticket);
   _direct_state_copy_any("MINR", parentTicket, ticket);
   _direct_state_copy_any("MFE", parentTicket, ticket);
   _direct_state_copy_any("MAE", parentTicket, ticket);
   _direct_state_copy_any("MFE_PX", parentTicket, ticket);
   _direct_state_copy_any("MAE_PX", parentTicket, ticket);
   _direct_state_copy("VOWN", parentTicket, ticket);
   _direct_state_set("OWNER", ticket, parentOwner);
   if((int)parentOwner != Period())
      return false;
   double copiedVariant = _direct_state_get("VOWN", ticket);
   return (copiedVariant <= 0.0 || (int)copiedVariant == (int)expectedVariant);
}

bool _direct_failure_log_due(string kind, int ticket, int seconds)
{
   datetime now = TimeCurrent();
   double last = _direct_state_get(kind, ticket);
   if(last > 0.0 && now - (datetime)last < MathMax(1, seconds))
      return false;
   _direct_state_set(kind, ticket, now);
   return true;
}

int _direct_lot_digits(double step)
{
   int digits = 0;
   double scaled = step;
   while(digits < 8 && MathAbs(scaled - MathRound(scaled)) > 0.00000001)
   {
      scaled *= 10.0;
      digits++;
   }
   return digits;
}

double _direct_normalize_order_lot(double requestedLot, bool requireHalfSplit=false)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if(step <= 0.0) step = 0.01;
   if(minLot <= 0.0) minLot = step;
   if(maxLot <= 0.0) maxLot = 100.0;
   double configuredCap = (InpDirectMt4AutoLotMax > 0.0)
      ? MathMin(maxLot, MathMax(minLot, InpDirectMt4AutoLotMax))
      : maxLot;
   double capped = MathMin(MathMax(requestedLot, minLot), configuredCap);
   double units = MathFloor((capped / step) + 0.0000001);
   double minUnits = MathCeil((minLot / step) - 0.0000001);
   if(requireHalfSplit)
   {
      double requiredUnits = MathMax(2.0, 2.0 * minUnits);
      if(units < requiredUnits)
         return 0.0;
      if(((int)units % 2) != 0)
         units -= 1.0;
      if(units < requiredUnits)
         return 0.0;
   }
   double lot = NormalizeDouble(units * step, _direct_lot_digits(step));
   if(!requireHalfSplit && lot < minLot)
      lot = NormalizeDouble(minLot, _direct_lot_digits(step));
   return lot;
}

double _direct_closed_daily_atr(string symbol, int period)
{
   int atrPeriod = MathMax(2, period);
   double atr = iATR(symbol, PERIOD_D1, atrPeriod, 1);
   return (MathIsValidNumber(atr) && atr > 0.0) ? atr : 0.0;
}

string _account_risk_key(string kind)
{
   return "PTS_FTMO_RISK_" + IntegerToString(AccountNumber()) + "_" + kind;
}

bool _account_risk_magic_scoped(int magic)
{
   // Scope liquidation/risk budget to AtomicBridge-owned magic only.
   // Other governed EAs also use 1B+ magic ranges; broad range checks can cross-close them.
   return _direct_magic_owned(magic);
}

int _direct_magic()
{
   if(!_account_risk_enabled_runtime())
      return InpDirectMt4Magic;
   long baseMagic = InpDirectMt4Magic;
   if(baseMagic < 0)
      baseMagic = -baseMagic;
   baseMagic %= 1000000000;
   return (int)(1000000000 + baseMagic);
}

int _direct_ftmo_magic()
{
   long baseMagic = InpDirectMt4Magic;
   if(baseMagic < 0)
      baseMagic = -baseMagic;
   baseMagic %= 1000000000;
   return (int)(1000000000 + baseMagic);
}

bool _direct_magic_owned(int magic)
{
   return magic == InpDirectMt4Magic || magic == _direct_ftmo_magic();
}

bool _direct_history_order_owned_by_bridge()
{
   if(_direct_magic_owned(OrderMagicNumber()))
      return true;
   string comment = OrderComment();
   return (StringFind(comment, "AtomicBridgeMT4") >= 0 || StringFind(comment, "AtomicBridge") >= 0 || StringFind(comment, "AB|Atomic") >= 0);
}

bool _direct_history_order_owned_by_chart()
{
   if(OrderSymbol() != Symbol())
      return false;
   if(!_direct_history_order_owned_by_bridge())
      return false;
   string comment = OrderComment();
   double variantOwner = _direct_state_get("VOWN", OrderTicket());
   if(variantOwner > 0.0)
   {
      string family = _contains_ci(comment, "AtomicRegime") ? "AtomicRegime" : "Atomic";
      return (int)variantOwner == _direct_instance_hash(family);
   }
   if(_direct_comment_has_current_variant(comment))
      return true;
   if(StringFind(comment, "|V") >= 0)
      return false;
   string tfToken = "|" + _tf_to_string(Period());
   if(StringFind(comment, "AtomicBridgeMT4|") >= 0 && StringFind(comment, "|M") >= 0)
      return (StringFind(comment, tfToken) >= 0);
   return true;
}

double _direct_daily_closed_profit_today()
{
   datetime dayStartGmt = _account_risk_gmt_day_start();
   datetime serverNow = TimeCurrent();
   datetime gmtNow = TimeGMT();
   int serverGmtOffset = (int)(serverNow - gmtNow);
   datetime dayStartServer = dayStartGmt + serverGmtOffset;
   double pnl = 0.0;
   int total = OrdersHistoryTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;
      if(OrderCloseTime() < dayStartServer)
         continue;
      if(!_direct_history_order_owned_by_chart())
         continue;
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return pnl;
}

bool _direct_daily_profit_target_reached(string &detail)
{
   detail = "daily_profit_target_off";
   double target = MathMax(0.0, g_directMt4DailyProfitTargetRuntime);
   if(target <= 0.0)
      return false;
   double pnl = _direct_daily_closed_profit_today();
   detail = "chart_daily_profit=" + DoubleToString(pnl, 2)
          + " symbol=" + Symbol()
          + " tf=" + _tf_to_string(Period())
          + " target=" + DoubleToString(target, 2)
          + " reset_hour_gmt=" + IntegerToString(MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt)));
   return (pnl >= target - 0.0001);
}

bool _direct_daily_loss_target_reached(string &detail)
{
   detail = "daily_loss_target_off";
   double target = MathMax(0.0, g_directMt4DailyLossTargetRuntime);
   if(target <= 0.0)
      return false;
   double pnl = _direct_daily_closed_profit_today();
   double loss = MathMax(0.0, -pnl);
   detail = "chart_daily_pnl=" + DoubleToString(pnl, 2)
          + " symbol=" + Symbol()
          + " tf=" + _tf_to_string(Period())
          + " loss=" + DoubleToString(loss, 2)
          + " target=" + DoubleToString(target, 2)
          + " reset_hour_gmt=" + IntegerToString(MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt)));
   return (loss >= target - 0.0001);
}

bool _direct_daily_profit_loss_guard_reached(string &reason, string &detail)
{
   reason = "";
   detail = "daily_guard_off";
   if(_direct_daily_profit_target_reached(detail))
   {
      reason = "daily_profit_target_reached";
      return true;
   }
   if(_direct_daily_loss_target_reached(detail))
   {
      reason = "daily_loss_target_reached";
      return true;
   }
   return false;
}
datetime _account_risk_gmt_day_start()
{
   datetime now = TimeGMT();
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   datetime shifted = now - resetHour * 3600;
   return shifted - (shifted % 86400) + resetHour * 3600;
}

datetime _account_risk_start_gmt()
{
   string key = _account_risk_key("START_GMT");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, (double)TimeGMT());
   return (datetime)GlobalVariableGet(key);
}

void _account_risk_cache_invalidate()
{
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   GlobalVariableSet(_account_risk_key("METRICS_TS_H" + IntegerToString(resetHour)), 0.0);
}

void _account_risk_scope_performance(double &closedAll, double &closedToday, double &floating)
{
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   string cacheSuffix = "_H" + IntegerToString(resetHour);
   string cacheTsKey = _account_risk_key("METRICS_TS" + cacheSuffix);
   string closedAllKey = _account_risk_key("CLOSED_ALL" + cacheSuffix);
   string closedTodayKey = _account_risk_key("CLOSED_TODAY" + cacheSuffix);
   string floatingKey = _account_risk_key("FLOATING" + cacheSuffix);
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
   datetime dayStartGmt = _account_risk_gmt_day_start();
   datetime startGmt = _account_risk_start_gmt();
   datetime serverNow = TimeCurrent();
   datetime gmtNow = TimeGMT();
   datetime dayStartServer = dayStartGmt + (serverNow - gmtNow);
   datetime startServer = startGmt + (serverNow - gmtNow);
   datetime historyStartServer = MathMax(dayStartServer, startServer);
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(!_account_risk_magic_scoped(OrderMagicNumber()))
         continue;
      if(OrderCloseTime() < startServer)
         continue;
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      closedAll += pnl;
      if(OrderCloseTime() >= historyStartServer)
         closedToday += pnl;
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(!_account_risk_magic_scoped(OrderMagicNumber()))
         continue;
      floating += OrderProfit() + OrderSwap() + OrderCommission();
   }
   GlobalVariableSet(closedAllKey, closedAll);
   GlobalVariableSet(closedTodayKey, closedToday);
   GlobalVariableSet(floatingKey, floating);
   GlobalVariableSet(cacheTsKey, nowLocal);
}

void _account_risk_metrics(double &riskCapital, double &dailyLossPct, double &totalDdPct)
{
   double initial = _account_risk_initial_balance();
   double closedAll, closedToday, floating;
   _account_risk_scope_performance(closedAll, closedToday, floating);
   double scopeEquity = MathMax(0.01, initial + closedAll + floating);
   int resetHour = MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt));
   datetime dayStartGmt = _account_risk_gmt_day_start();
   string suffix = "_H" + IntegerToString(resetHour);
   string dayKey = _account_risk_key("DAY_SCOPE_" + IntegerToString((int)dayStartGmt) + suffix);
   string lastEquityKey = _account_risk_key("LAST_SCOPE_EQUITY" + suffix);
   string lastEquityTimeKey = _account_risk_key("LAST_SCOPE_EQUITY_GMT" + suffix);
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
   riskCapital = MathMax(0.01, MathMin(AccountEquity(), scopeEquity));
   dailyLossPct = MathMax(0.0, (dayStartScope - scopeEquity) / dayStartScope * 100.0);
   totalDdPct = MathMax(0.0, -(closedAll + floating) / initial * 100.0);
}

double _account_risk_initial_balance()
{
   if(InpAccountRiskInitialBalanceOverride > 0.0)
      return InpAccountRiskInitialBalanceOverride;
   string key = _account_risk_key("INITIAL_BALANCE");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, MathMax(0.01, AccountBalance()));
   return MathMax(0.01, GlobalVariableGet(key));
}

bool _account_open_risk(double &riskMoney, int &unprotectedCount)
{
   riskMoney = 0.0;
   unprotectedCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(!_account_risk_magic_scoped(OrderMagicNumber()))
         continue;
      double sl = OrderStopLoss();
      if(sl <= 0.0)
      {
         unprotectedCount++;
         continue;
      }
      double adverseDistance = (OrderType() == OP_BUY)
         ? MathMax(0.0, OrderOpenPrice() - sl)
         : MathMax(0.0, sl - OrderOpenPrice());
      if(adverseDistance <= 0.0)
         continue;
      double tickSize = MarketInfo(OrderSymbol(), MODE_TICKSIZE);
      double tickValue = MarketInfo(OrderSymbol(), MODE_TICKVALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
      {
         unprotectedCount++;
         continue;
      }
      riskMoney += (adverseDistance / tickSize) * tickValue * OrderLots();
   }
   return true;
}

bool _account_risk_lock_acquire()
{
   string key = _account_risk_key("LOCK");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   for(int i = 0; i < 50; i++)
   {
      double observed = GlobalVariableGet(key);
      double now = (double)TimeLocal();
      double leaseUntil = MathFloor(observed);
      if(leaseUntil <= now)
      {
         long chartPart = ChartID() % 100000;
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

void _account_risk_lock_release()
{
   if(g_accountRiskLockValue > 0.0)
      GlobalVariableSetOnCondition(_account_risk_key("LOCK"), 0.0, g_accountRiskLockValue);
   g_accountRiskLockValue = 0.0;
}

bool _account_risk_audit_claim_snapshot()
{
   int interval = MathMax(15, InpAccountRiskAuditIntervalSeconds);
   string key = _account_risk_key("AUDIT_SNAPSHOT_GMT");
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   double now = (double)TimeGMT();
   double observed = GlobalVariableGet(key);
   if(now - observed < interval)
      return false;
   return GlobalVariableSetOnCondition(key, now, observed);
}

bool _account_risk_audit_file_lock(double &token)
{
   token = 0.0;
   string key = _account_risk_key("AUDIT_FILE_LOCK");
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

void _account_risk_audit_file_unlock(double token)
{
   if(token > 0.0)
      GlobalVariableSetOnCondition(_account_risk_key("AUDIT_FILE_LOCK"), 0.0, token);
}

string _account_risk_position_summary(int &openCount, int &protectedCount, int &unprotectedCount, double &totalVolume, double &openRisk)
{
   openCount = 0;
   protectedCount = 0;
   unprotectedCount = 0;
   totalVolume = 0.0;
   openRisk = 0.0;
   string summary = "";
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      int type = OrderType();
      if((type != OP_BUY && type != OP_SELL) || !_account_risk_magic_scoped(OrderMagicNumber()))
         continue;
      openCount++;
      totalVolume += OrderLots();
      double risk = -1.0;
      double sl = OrderStopLoss();
      double adverseDistance = type == OP_BUY
         ? MathMax(0.0, OrderOpenPrice() - sl)
         : MathMax(0.0, sl - OrderOpenPrice());
      double tickSize = MarketInfo(OrderSymbol(), MODE_TICKSIZE);
      double tickValue = MarketInfo(OrderSymbol(), MODE_TICKVALUE);
      if(sl > 0.0 && adverseDistance > 0.0 && tickSize > 0.0 && tickValue > 0.0)
      {
         risk = (adverseDistance / tickSize) * tickValue * OrderLots();
         openRisk += risk;
         protectedCount++;
      }
      else
         unprotectedCount++;
      if(StringLen(summary) < 1800)
      {
         if(StringLen(summary) > 0)
            summary += "|";
         summary += IntegerToString(OrderTicket()) + ":" + OrderSymbol() + ":" + (type == OP_BUY ? "BUY" : "SELL")
            + ":v=" + DoubleToString(OrderLots(), 3)
            + ":e=" + DoubleToString(OrderOpenPrice(), (int)MarketInfo(OrderSymbol(), MODE_DIGITS))
            + ":sl=" + DoubleToString(sl, (int)MarketInfo(OrderSymbol(), MODE_DIGITS))
            + ":risk=" + (risk >= 0.0 ? DoubleToString(risk, 2) : "UNPROTECTED");
      }
   }
   return summary;
}

void _account_risk_audit_write(string eventName, string detail, bool periodic)
{
   if(!_account_risk_enabled_runtime() || !_audit_enabled_runtime() || !InpAccountRiskAuditEnabled)
      return;
   // Compact audit: periodic health snapshots are telemetry and can grow to GBs.
   // Keep only lifecycle/risk decisions such as lot_selected, lot_blocked, liquidation events.
   if(periodic)
      return;

   double closedAll, closedToday, floating;
   _account_risk_scope_performance(closedAll, closedToday, floating);
   double riskCapital, dailyLossPct, totalDdPct;
   _account_risk_metrics(riskCapital, dailyLossPct, totalDdPct);
   double initial = _account_risk_initial_balance();
   double scopeEquity = MathMax(0.01, initial + closedAll + floating);
   int openCount, protectedCount, unprotectedCount;
   double totalVolume, openRisk;
   string positions = _account_risk_position_summary(openCount, protectedCount, unprotectedCount, totalVolume, openRisk);
   double tradeBudget = riskCapital * _account_risk_per_trade_pct() / 100.0;
   double atrBudget = riskCapital * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double portfolioBudget = riskCapital * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double marginUsagePct = riskCapital > 0.0 ? AccountMargin() / riskCapital * 100.0 : 100.0;
   string fileName = "AccountRiskAudit_MT4_" + _direct_audit_date(TimeGMT()) + ".csv";
   double auditLock = 0.0;
   if(!_account_risk_audit_file_lock(auditLock))
      return;
   int h = FileOpen(fileName, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      _account_risk_audit_file_unlock(auditLock);
      return;
   }
   bool empty = FileSize(h) <= 0;
   FileSeek(h, 0, SEEK_END);
   if(empty)
      FileWrite(h, "ts_gmt", "ts_server", "event", "build", "terminal", "account", "reporter", "symbol", "timeframe",
         "initial_balance", "account_balance", "account_equity", "scope_closed_all", "scope_closed_today", "scope_floating",
         "scope_equity", "risk_capital", "daily_loss_pct", "total_dd_pct", "margin", "margin_usage_pct", "open_positions",
         "protected_positions", "unprotected_positions", "total_volume", "open_sl_risk", "trade_budget", "atr_budget",
         "portfolio_budget", "available_portfolio_risk", "safety_pct", "day_reset_gmt", "positions", "detail");
   FileWrite(h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS), TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName, ATOMIC_BRIDGE_BUILD, "MT4", IntegerToString(AccountNumber()), "AtomicBridge", Symbol(), _tf_to_string(Period()),
      DoubleToString(initial, 2), DoubleToString(AccountBalance(), 2), DoubleToString(AccountEquity(), 2),
      DoubleToString(closedAll, 2), DoubleToString(closedToday, 2), DoubleToString(floating, 2),
      DoubleToString(scopeEquity, 2), DoubleToString(riskCapital, 2), DoubleToString(dailyLossPct, 3),
      DoubleToString(totalDdPct, 3), DoubleToString(AccountMargin(), 2), DoubleToString(marginUsagePct, 3),
      IntegerToString(openCount), IntegerToString(protectedCount), IntegerToString(unprotectedCount),
      DoubleToString(totalVolume, 3), DoubleToString(openRisk, 2), DoubleToString(tradeBudget, 2),
      DoubleToString(atrBudget, 2), DoubleToString(portfolioBudget, 2),
      DoubleToString(MathMax(0.0, portfolioBudget - openRisk), 2), DoubleToString(InpAccountRiskSafetyBufferPct, 1),
      IntegerToString(MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt))), positions, detail);
   FileFlush(h);
   FileClose(h);
   _account_risk_audit_file_unlock(auditLock);
}

void _account_risk_enforce_breach()
{
   if(!_account_risk_enabled_runtime() || !_effective_liquidate_on_breach())
      return;
   uint guardNow = GetTickCount();
   if(guardNow - g_lastAccountRiskGuardMs < 100)
      return;
   g_lastAccountRiskGuardMs = guardNow;
   double riskCapital, dailyPct, totalPct;
   _account_risk_metrics(riskCapital, dailyPct, totalPct);
   double safety = MathMax(1.0, MathMin(100.0, InpAccountRiskSafetyBufferPct)) / 100.0;
   bool breached = (_effective_daily_loss_limit_pct() > 0.0 && dailyPct >= _effective_daily_loss_limit_pct() * safety)
      || (_effective_max_drawdown_pct() > 0.0 && totalPct >= _effective_max_drawdown_pct() * safety);
   if(!breached)
      return;
   string attemptKey = _account_risk_key("BREACH_ATTEMPT");
   double now = (double)TimeLocal();
   if(GlobalVariableCheck(attemptKey) && now - GlobalVariableGet(attemptKey) < 2.0)
      return;
   GlobalVariableSet(attemptKey, now);
   if(!_account_risk_lock_acquire())
      return;
   _account_risk_cache_invalidate();
   _account_risk_metrics(riskCapital, dailyPct, totalPct);
   breached = (_effective_daily_loss_limit_pct() > 0.0 && dailyPct >= _effective_daily_loss_limit_pct() * safety)
      || (_effective_max_drawdown_pct() > 0.0 && totalPct >= _effective_max_drawdown_pct() * safety);
   if(!breached)
   {
      _account_risk_lock_release();
      return;
   }
   Print("AtomicBridge ACCOUNT RISK LIQUIDATION daily_loss_pct=", DoubleToString(dailyPct, 3),
      " total_dd_pct=", DoubleToString(totalPct, 3), " safety_pct=", DoubleToString(InpAccountRiskSafetyBufferPct, 1));
   _account_risk_audit_write("liquidation_triggered",
      "daily_loss_pct=" + DoubleToString(dailyPct, 3) + " total_dd_pct=" + DoubleToString(totalPct, 3), false);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(!_account_risk_magic_scoped(OrderMagicNumber()))
         continue;
      int type = OrderType();
      bool ok = false;
      if(type == OP_BUY || type == OP_SELL)
      {
         RefreshRates();
         double px = MarketInfo(OrderSymbol(), type == OP_BUY ? MODE_BID : MODE_ASK);
         ok = OrderClose(OrderTicket(), OrderLots(), px, InpDirectMt4Slippage, clrRed);
      }
      else
         ok = OrderDelete(OrderTicket(), clrRed);
      if(!ok)
         Print("AtomicBridge account risk liquidation failed ticket=", OrderTicket(), " err=", GetLastError());
   }
   _account_risk_cache_invalidate();
   _account_risk_audit_write("liquidation_complete", "scoped_positions_close_attempted", false);
   _account_risk_lock_release();
}

double _direct_resolve_order_lot(double entry, double sl, int orderType, bool requireHalfSplit, string &detail)
{
   double fallbackLot = _direct_normalize_order_lot(g_directMt4LotRuntime, requireHalfSplit);
   if(!_account_risk_enabled_runtime())
   {
      detail = "advanced_account_risk=off manual_lot=" + DoubleToString(fallbackLot, 3);
      return fallbackLot;
   }
   bool autoLotEnabled = InpDirectMt4AutoLotEnabled;
   double equity, dailyLossPct, totalDdPct;
   _account_risk_metrics(equity, dailyLossPct, totalDdPct);
   double marginUsagePct = (equity > 0.0 ? AccountMargin() / equity * 100.0 : 100.0);
   double safety = MathMax(1.0, MathMin(100.0, InpAccountRiskSafetyBufferPct)) / 100.0;
   if(equity <= 0.0
      || (_effective_daily_loss_limit_pct() > 0.0 && dailyLossPct >= _effective_daily_loss_limit_pct() * safety)
      || (_effective_max_drawdown_pct() > 0.0 && totalDdPct >= _effective_max_drawdown_pct() * safety)
      || (InpAccountRiskMaxMarginUsagePct > 0.0 && marginUsagePct >= InpAccountRiskMaxMarginUsagePct))
   {
      detail = "account_risk_block"
         + " equity=" + DoubleToString(equity, 2)
         + " daily_loss_pct=" + DoubleToString(dailyLossPct, 3)
         + " total_dd_pct=" + DoubleToString(totalDdPct, 3)
         + " margin_usage_pct=" + DoubleToString(marginUsagePct, 3);
      return 0.0;
   }
   double riskDistance = MathAbs(entry - sl);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double symbolAtr = _direct_closed_daily_atr(Symbol(), InpDirectMt4AutoLotDailyAtrPeriod);
   if(sl <= 0.0 || riskDistance <= 0.0 || symbolAtr <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
   {
      detail = "auto_lot=invalid_inputs fallback_lot=" + DoubleToString(fallbackLot, 3)
         + " symbol_daily_atr=" + DoubleToString(symbolAtr, Digits)
         + " risk_distance=" + DoubleToString(riskDistance, Digits)
         + " tick_size=" + DoubleToString(tickSize, 8)
         + " tick_value=" + DoubleToString(tickValue, 5);
      return InpAccountRiskFailClosed ? 0.0 : fallbackLot;
   }
   double dailyMoneyPerLot = (symbolAtr / tickSize) * tickValue;
   double slMoneyPerLot = (riskDistance / tickSize) * tickValue;
   if(dailyMoneyPerLot <= 0.0 || slMoneyPerLot <= 0.0)
   {
      detail = "auto_lot=invalid_money_per_lot";
      return InpAccountRiskFailClosed ? 0.0 : fallbackLot;
   }
   double openRiskMoney = 0.0;
   int unprotectedCount = 0;
   _account_open_risk(openRiskMoney, unprotectedCount);
   if(InpAccountRiskBlockUnprotectedPositions && unprotectedCount > 0)
   {
      detail = "account_risk_block unprotected_positions=" + IntegerToString(unprotectedCount);
      return 0.0;
   }
   bool pureRiskLotOnly = (g_riskLotOnlyRuntime && !g_ftmoModeRuntime);
   double tradeRiskBudget = equity * _account_risk_per_trade_pct() / 100.0;
   double dailyAtrBudget = equity * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double portfolioBudget = equity * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double availablePortfolioRisk = MathMax(0.0, portfolioBudget - openRiskMoney);
   if(tradeRiskBudget <= 0.0 || (!pureRiskLotOnly && (dailyAtrBudget <= 0.0 || availablePortfolioRisk <= 0.0)))
   {
      detail = "account_risk_block exhausted_budget"
         + " mode=" + (pureRiskLotOnly ? "RISKLOT_ONLY_PURE" : "FTMO_GOVERNED")
         + " trade_budget=" + DoubleToString(tradeRiskBudget, 2)
         + " atr_budget=" + DoubleToString(dailyAtrBudget, 2)
         + " open_risk=" + DoubleToString(openRiskMoney, 2)
         + " portfolio_budget=" + DoubleToString(portfolioBudget, 2);
      return 0.0;
   }
   double slLot = tradeRiskBudget / slMoneyPerLot;
   double atrLot = dailyAtrBudget / dailyMoneyPerLot;
   double portfolioLot = availablePortfolioRisk / slMoneyPerLot;
   double rawLot = autoLotEnabled ? (pureRiskLotOnly ? slLot : MathMin(slLot, MathMin(atrLot, portfolioLot))) : fallbackLot;
   double finalLot = autoLotEnabled ? _direct_normalize_order_lot(rawLot, requireHalfSplit) : fallbackLot;
   double projectedRisk = slMoneyPerLot * finalLot;
   double projectedAtrExposure = dailyMoneyPerLot * finalLot;
   if(finalLot <= 0.0
      || projectedRisk > tradeRiskBudget + 0.01
      || (!pureRiskLotOnly && projectedRisk > availablePortfolioRisk + 0.01)
      || (!pureRiskLotOnly && projectedAtrExposure > dailyAtrBudget + 0.01))
   {
      detail = "account_risk_block volume_below_min_or_budget"
         + " mode=" + (pureRiskLotOnly ? "RISKLOT_ONLY_PURE" : "FTMO_GOVERNED")
         + " raw_lot=" + DoubleToString(rawLot, 4)
         + " projected_risk=" + DoubleToString(projectedRisk, 2)
         + " trade_budget=" + DoubleToString(tradeRiskBudget, 2)
         + " available_risk=" + DoubleToString(availablePortfolioRisk, 2)
         + " projected_atr_exposure=" + DoubleToString(projectedAtrExposure, 2);
      return 0.0;
   }
   ResetLastError();
   double freeAfter = AccountFreeMarginCheck(Symbol(), orderType, finalLot);
   double addedMargin = MathMax(0.0, AccountFreeMargin() - freeAfter);
   double projectedMarginPct = (equity > 0.0 ? (AccountMargin() + addedMargin) / equity * 100.0 : 100.0);
   if(freeAfter <= 0.0
      || (InpAccountRiskMaxMarginUsagePct > 0.0 && projectedMarginPct > InpAccountRiskMaxMarginUsagePct))
   {
      detail = "account_risk_block insufficient_margin lot=" + DoubleToString(finalLot, 3)
         + " projected_margin_pct=" + DoubleToString(projectedMarginPct, 3)
         + " err=" + IntegerToString(GetLastError());
      return 0.0;
   }
   detail = (autoLotEnabled ? "auto_lot=account_risk" : "auto_lot=off_risk_validated")
      + " risk_mode=" + (pureRiskLotOnly ? "RISKLOT_ONLY_PURE_SL" : "FTMO_GOVERNED")
      + " equity=" + DoubleToString(equity, 2)
      + " risk_pct=" + DoubleToString(_account_risk_per_trade_pct(), 3)
      + " atr_exposure_pct=" + DoubleToString(InpAccountRiskDailyAtrExposurePct, 3)
      + " open_risk=" + DoubleToString(openRiskMoney, 2)
      + " portfolio_budget=" + DoubleToString(portfolioBudget, 2)
      + " symbol_daily_atr=" + DoubleToString(symbolAtr, Digits)
      + " daily_money_per_lot=" + DoubleToString(dailyMoneyPerLot, 2)
      + " atr_lot=" + DoubleToString(atrLot, 4)
      + " risk_distance=" + DoubleToString(riskDistance, Digits)
      + " sl_money_per_lot=" + DoubleToString(slMoneyPerLot, 2)
      + " sl_lot=" + DoubleToString(slLot, 4)
      + " portfolio_lot=" + DoubleToString(portfolioLot, 4)
      + " raw_lot=" + DoubleToString(rawLot, 4)
      + " final_lot=" + DoubleToString(finalLot, 3)
      + " projected_risk=" + DoubleToString(projectedRisk, 2)
      + " daily_loss_pct=" + DoubleToString(dailyLossPct, 3)
      + " total_dd_pct=" + DoubleToString(totalDdPct, 3);
   return finalLot;
}

string _file_bridge_time(datetime t)
{
   return (t > 0 ? TimeToString(t, TIME_DATE | TIME_SECONDS) : "");
}

int _file_bridge_flags(int baseFlags)
{
   baseFlags |= FILE_ANSI;
   if(InpFileBridgeUseCommonFiles)
      baseFlags |= FILE_COMMON;
   return baseFlags;
}

void _file_bridge_write_header(int h)
{
   FileWrite(h,
      "version", "written_gmt", "source_login", "source_symbol", "source_tf", "event_id", "source", "direction",
      "signal_time", "bridge_entry", "sl", "tp", "half_trigger", "half_label", "source_build", "source_bid", "source_ask", "risk_pct"
   );
}

void _file_bridge_write_row(int h, string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   RefreshRates();
   FileWrite(h,
      "1",
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      IntegerToString(AccountNumber()),
      Symbol(),
      _tf_to_string(Period()),
      eventId,
      source,
      dir,
      _file_bridge_time(sourceSignalTime),
      DoubleToString(bridgeEntry, Digits),
      DoubleToString(sl, Digits),
      DoubleToString(tp, Digits),
      DoubleToString(halfTriggerPrice, Digits),
      halfTriggerLabel,
      ATOMIC_BRIDGE_BUILD,
      DoubleToString(Bid, Digits),
      DoubleToString(Ask, Digits),
      DoubleToString(_account_risk_per_trade_pct(), 3)
   );
}

void _file_bridge_write_init_marker()
{
   if(!g_fileBridgeMt5EnabledRuntime)
      return;
   RefreshRates();
   string eventId = "bridge_init|" + Symbol() + "|" + _tf_to_string(Period()) + "|" + TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS);
   int latestFlags = _file_bridge_flags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(InpFileBridgeLatestFile, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("AtomicBridge file_bridge init latest open failed err=", GetLastError(), " file=", InpFileBridgeLatestFile);
      return;
   }
   _file_bridge_write_header(h);
   _file_bridge_write_row(h, eventId, "INIT", Bid, 0.0, 0.0, "bridge_initiated", 0.0, "init", TimeGMT());
   FileClose(h);

   string auditFile = InpFileBridgeAuditPrefix + _direct_audit_date(TimeGMT()) + ".csv";
   int auditFlags = _file_bridge_flags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int a = FileOpen(auditFile, auditFlags, ',');
   if(a == INVALID_HANDLE)
   {
      Print("AtomicBridge file_bridge init audit open failed err=", GetLastError(), " file=", auditFile);
      return;
   }
   bool needHeader = (FileSize(a) == 0);
   FileSeek(a, 0, SEEK_END);
   if(needHeader)
      _file_bridge_write_header(a);
   _file_bridge_write_row(a, eventId, "INIT", Bid, 0.0, 0.0, "bridge_initiated", 0.0, "init", TimeGMT());
   FileClose(a);
   Print("AtomicBridge file_bridge init marker wrote event=", eventId, " file=", InpFileBridgeLatestFile);
}
void _file_bridge_write_signal(string eventId, string dir, double bridgeEntry, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   if(!g_fileBridgeMt5EnabledRuntime)
      return;
   string dailyGuardReason = "";
   string dailyGuardDetail = "";
   if(_direct_daily_profit_loss_guard_reached(dailyGuardReason, dailyGuardDetail))
   {
      Print("AtomicBridge file_bridge skipped reason=", dailyGuardReason, " event=", eventId, " ", dailyGuardDetail);
      return;
   }
   int latestFlags = _file_bridge_flags(FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int h = FileOpen(InpFileBridgeLatestFile, latestFlags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("AtomicBridge file_bridge latest open failed err=", GetLastError(), " file=", InpFileBridgeLatestFile);
      return;
   }
   _file_bridge_write_header(h);
   _file_bridge_write_row(h, eventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
   FileClose(h);

   string auditFile = InpFileBridgeAuditPrefix + _direct_audit_date(TimeGMT()) + ".csv";
   int auditFlags = _file_bridge_flags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE);
   int a = FileOpen(auditFile, auditFlags, ',');
   if(a == INVALID_HANDLE)
   {
      Print("AtomicBridge file_bridge audit open failed err=", GetLastError(), " file=", auditFile);
      return;
   }
   bool needHeader = (FileSize(a) == 0);
   FileSeek(a, 0, SEEK_END);
   if(needHeader)
      _file_bridge_write_header(a);
   _file_bridge_write_row(a, eventId, dir, bridgeEntry, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
   FileClose(a);
   Print("AtomicBridge file_bridge wrote event=", eventId, " dir=", dir, " source=", source, " file=", InpFileBridgeLatestFile);
}
string _safe_file_token(string s)
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

int _gann_follow_effective_tf()
{
   return (g_gannFollowTfRuntime > 0 ? g_gannFollowTfRuntime : Period());
}

int _gann_follow_sanitize_tf(int tf)
{
   if(tf == 0 || tf == PERIOD_M1 || tf == PERIOD_M5 || tf == PERIOD_M15 || tf == PERIOD_M30 ||
      tf == PERIOD_H1 || tf == PERIOD_H4 || tf == PERIOD_D1)
      return tf;
   return 0;
}

string _gann_follow_tf_text()
{
   if(g_gannFollowTfRuntime <= 0)
      return "CUR " + _tf_to_string(Period());
   return _tf_to_string(g_gannFollowTfRuntime);
}

void _gann_follow_cycle_tf()
{
   int current = _gann_follow_sanitize_tf(g_gannFollowTfRuntime);
   if(current == 0) g_gannFollowTfRuntime = PERIOD_M1;
   else if(current == PERIOD_M1) g_gannFollowTfRuntime = PERIOD_M5;
   else if(current == PERIOD_M5) g_gannFollowTfRuntime = PERIOD_M15;
   else if(current == PERIOD_M15) g_gannFollowTfRuntime = PERIOD_M30;
   else if(current == PERIOD_M30) g_gannFollowTfRuntime = PERIOD_H1;
   else if(current == PERIOD_H1) g_gannFollowTfRuntime = PERIOD_H4;
   else if(current == PERIOD_H4) g_gannFollowTfRuntime = PERIOD_D1;
   else g_gannFollowTfRuntime = 0;
}

string _gann_follow_state_file_name()
{
   int tf = _gann_follow_effective_tf();
   return InpGannFollowStatePrefix + _safe_file_token(Symbol()) + "_" + IntegerToString(tf) + ".csv";
}

int _gann_follow_file_flags(int baseFlags)
{
   int flags = baseFlags | FILE_ANSI;
   if(InpGannFollowUseCommonFiles)
      flags |= FILE_COMMON;
   return flags;
}

bool _gann_follow_read_state(string &dir, datetime &signalTime, string &detail)
{
   dir = "";
   signalTime = 0;
   string fileName = _gann_follow_state_file_name();
   int h = FileOpen(fileName, _gann_follow_file_flags(FILE_CSV | FILE_READ | FILE_SHARE_READ | FILE_SHARE_WRITE), ',');
   if(h == INVALID_HANDLE)
   {
      detail = "file_open_failed err=" + IntegerToString(GetLastError()) + " file=" + fileName;
      return false;
   }
   string header[11];
   string fields[11];
   for(int i = 0; i < 11 && !FileIsEnding(h); i++)
      header[i] = FileReadString(h);
   for(int j = 0; j < 11 && !FileIsEnding(h); j++)
      fields[j] = FileReadString(h);
   FileClose(h);
   string sym = fields[3];
   int tf = (int)StringToInteger(fields[4]);
   string d = fields[5];
   StringToUpper(d);
   int selectedTf = _gann_follow_effective_tf();
   if(sym == Symbol() && tf == selectedTf && (d == "BUY" || d == "SELL"))
   {
      dir = d;
      signalTime = StringToTime(fields[6]);
      detail = "state_ok file=" + fileName + " filter_tf=" + _tf_to_string(selectedTf) + " dir=" + dir + " signal_time=" + fields[6] + " event=" + fields[7] + " build=" + fields[9];
      return true;
   }
   detail = "state_not_found file=" + fileName + " filter_tf=" + _tf_to_string(selectedTf) + " sym=" + sym + " tf=" + fields[4] + " dir=" + d;
   return false;
}
bool _gann_follow_allows(string tradeDir, string eventId, string source, double price, double sl, double tp)
{
   if(!g_gannFollowModeRuntime)
      return true;
   string gDir, detail;
   datetime sigTime = 0;
   bool ok = _gann_follow_read_state(gDir, sigTime, detail);
   g_gannFollowLastDirection = ok ? gDir : "NONE";
   g_gannFollowLastSignalTime = sigTime;
   g_gannFollowLastReadGmt = TimeGMT();
   g_gannFollowLastDetail = detail;
   if(!ok)
   {
      _direct_audit_write("direct_gann_follow_state_missing", source, eventId, 0, tradeDir, g_directMt4LotRuntime, price, sl, tp, "gann_follow", 0.0, detail + " fail_closed=" + (InpGannFollowFailClosed ? "true" : "false"));
      return !InpGannFollowFailClosed;
   }
   if(gDir != tradeDir)
   {
      _direct_audit_write("direct_gann_follow_blocked", source, eventId, 0, tradeDir, g_directMt4LotRuntime, price, sl, tp, "gann_follow", 0.0, "gann_dir=" + gDir + " trade_dir=" + tradeDir + " " + detail);
      return false;
   }
   _direct_audit_write("direct_gann_follow_allowed", source, eventId, 0, tradeDir, g_directMt4LotRuntime, price, sl, tp, "gann_follow", 0.0, detail);
   return true;
}
bool _direct_mt4_execute(string eventId, string direction, double sl, double tp, string source, double halfTriggerPrice, string halfTriggerLabel, datetime sourceSignalTime)
{
   string dir = _trim(direction);
   if(dir != "BUY" && dir != "SELL")
      return false;
   if(eventId == g_lastDirectMt4EventId)
      return true;
   RefreshRates();
   double signalPx = (dir == "BUY") ? Ask : Bid;
   bool sourceIsRegime = _contains_ci(source, "AtomicRegime");
   string dailyGuardReason = "";
   string dailyGuardDetail = "";
   if(_direct_daily_profit_loss_guard_reached(dailyGuardReason, dailyGuardDetail))
   {
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 skipped reason=", dailyGuardReason, " event=", eventId, " dir=", dir, " ", dailyGuardDetail);
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, dailyGuardReason + "_path file_bridge_not_written=1 half_trigger=" + _fmt_price(halfTriggerPrice));
      _direct_audit_write("direct_skip_daily_profit_loss_target", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, dailyGuardDetail, 0.0, dailyGuardReason + " file_bridge_not_written=1");
      return false;
   }
   // A confirmed normal Atomic reversal always terminates the opposite Atomic-owned
   // position first, even if the replacement order is later blocked by a guard.
   if(!sourceIsRegime)
      _direct_close_reverse_positions(dir);

   if(!_direct_in_allowed_trade_window_gmt())
   {
      Print("AtomicBridge direct_mt4 skipped reason=outside_allowed_trade_window event=", eventId, " dir=", dir);
      string windowExtra = "outside_allowed_window_path half_trigger=" + _fmt_price(halfTriggerPrice);
      if(sourceIsRegime && g_regimeOpenPreWindowSignalRuntime && sourceSignalTime > 0)
      {
         _regime_window_pending_store(eventId, dir, sourceSignalTime, sl, tp, halfTriggerPrice, halfTriggerLabel);
         windowExtra = windowExtra + " deferred_until_allowed_window=1";
         _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, windowExtra);
         _direct_audit_write("direct_defer_allowed_window", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, g_directMt4AllowedWindowsRuntime, 0.0, "regime_pre_window_toggle=on");
         return false;
      }
      g_lastDirectMt4EventId = eventId;
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, windowExtra);
      _direct_audit_write("direct_skip_allowed_window", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, g_directMt4AllowedWindowsRuntime, 0.0, "");
      return false;
   }
   if(_direct_in_utc_event_block_gmt())
   {
      Print("AtomicBridge direct_mt4 deferred reason=utc_event_block event=", eventId, " dir=", dir, " ", _direct_utc_event_block_status());
      _direct_event_block_pending_store(eventId, dir, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, "utc_event_block_path half_trigger=" + _fmt_price(halfTriggerPrice));
      return false;
   }
   if(_direct_in_no_trade_window_gmt())
   {
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 skipped reason=no_trade_window_gmt event=", eventId, " dir=", dir);
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, "no_trade_window_path half_trigger=" + _fmt_price(halfTriggerPrice));
      _direct_audit_write("direct_skip_no_trade_window", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, g_directMt4NoTradeWindowsRuntime, 0.0, "");
      return false;
   }
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   if(g_directMt4MaxSpreadRuntime > 0 && spread > g_directMt4MaxSpreadRuntime)
   {
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 skipped reason=spread_too_wide spread=", spread, " max=", g_directMt4MaxSpreadRuntime, " event=", eventId);
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, "spread_skip_path half_trigger=" + _fmt_price(halfTriggerPrice));
      _direct_audit_write("direct_skip_spread", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "spread=" + IntegerToString(spread) + " max=" + IntegerToString(g_directMt4MaxSpreadRuntime), 0.0, "file_bridge_not_written=1");
      return false;
   }
   string regimeReanchorDetail = "";
   if(sourceIsRegime && _regime_pip_sl_enabled())
   {
      RefreshRates();
      signalPx = (dir == "BUY") ? Ask : Bid;
      bool invertReanchor = g_atomicInvertTradeModeRuntime;
      if(_regime_reanchor_pip_geometry(dir, signalPx, invertReanchor, sl, tp, halfTriggerPrice, regimeReanchorDetail))
      {
         Print("AtomicBridge regime pip geometry reanchored event=", eventId, " dir=", dir, " invert=", (invertReanchor ? "true" : "false"), " ", regimeReanchorDetail);
         _direct_audit_write(invertReanchor ? "direct_regime_invert_pip_reanchored" : "direct_regime_pip_reanchored", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "before_file_bridge_and_order", 0.0, regimeReanchorDetail);
      }
      else if(regimeReanchorDetail != "")
      {
         Print("AtomicBridge regime pip reanchor skipped event=", eventId, " dir=", dir, " reason=", regimeReanchorDetail);
      }
   }

   string spreadSlDetail = "";
   if(!_direct_spread_to_sl_allowed(dir, signalPx, sl, spreadSlDetail))
   {
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 skipped reason=spread_sl_pct_too_wide ", spreadSlDetail, " event=", eventId);
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, "spread_sl_pct_skip_path half_trigger=" + _fmt_price(halfTriggerPrice));
      _direct_audit_write("direct_skip_spread_sl_pct", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, spreadSlDetail, 0.0, "file_bridge_not_written=1");
      return false;
   }
   if(!_gann_follow_allows(dir, eventId, source, signalPx, sl, tp))
   {
      Print("AtomicBridge direct_mt4 skipped reason=gann_follow_filter event=", eventId, " dir=", dir, " ", g_gannFollowLastDetail);
      return false;
   }

   double outboundHalfR = (sourceIsRegime ? g_regimeDirectMt4HalfBeRRuntime : (g_directMt4HalfBeTpIndexRuntime < g_directMt4TpIndexRuntime ? g_directMt4HalfBeRRuntime : 0.0));
   if(!_direct_trigger_price_valid(dir, signalPx, halfTriggerPrice) && outboundHalfR > 0.0)
   {
      bool outboundHalfRebased = false;
      string outboundHalfReason = "";
      double outboundHalf = _direct_normalize_half_trigger(dir, signalPx, sl, tp, halfTriggerPrice, outboundHalfR, outboundHalfRebased, outboundHalfReason);
      if(_direct_trigger_price_valid(dir, signalPx, outboundHalf))
      {
         halfTriggerPrice = outboundHalf;
         if(sourceIsRegime)
            halfTriggerLabel = "r" + DoubleToString(outboundHalfR, 2);
         else if(_trim(halfTriggerLabel) == "" || _contains_ci(halfTriggerLabel, "off"))
            halfTriggerLabel = "r" + DoubleToString(outboundHalfR, 2);
         _direct_audit_write("direct_file_bridge_halfbe_rebased", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, outboundHalfReason, 0.0, "half_trigger=" + _fmt_price(halfTriggerPrice) + " label=" + halfTriggerLabel);
      }
   }
   _file_bridge_write_signal(eventId, dir, signalPx, sl, tp, source, halfTriggerPrice, halfTriggerLabel, sourceSignalTime);
   if(!g_directMt4EnabledRuntime)
   {
      g_lastDirectMt4EventId = eventId;
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, "direct_disabled_path file_bridge_written=1 half_trigger=" + _fmt_price(halfTriggerPrice));
      _direct_audit_write("direct_skip_disabled", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "direct_off", 0.0, "file_bridge_written=1");
      return true;
   }
   if(sourceIsRegime)
      _direct_close_reverse_positions(dir);
   RefreshRates();
   int type = (dir == "BUY") ? OP_BUY : OP_SELL;
   double price = (type == OP_BUY) ? Ask : Bid;
   string atomicGeometryDetail = (!sourceIsRegime && g_atomicDirectRiskGeometryRuntime) ? "atomic_r_geometry_precomputed" : "";
   if(sourceIsRegime && _regime_pip_sl_enabled())
   {
      string orderReanchorDetail = "";
      bool invertOrderReanchor = g_atomicInvertTradeModeRuntime;
      if(_regime_reanchor_pip_geometry(dir, price, invertOrderReanchor, sl, tp, halfTriggerPrice, orderReanchorDetail))
         atomicGeometryDetail = orderReanchorDetail;
   }
   double stopLoss = (sl > 0.0 ? NormalizeDouble(sl, Digits) : 0.0);
   double takeProfit = (tp > 0.0 ? NormalizeDouble(tp, Digits) : 0.0);
   bool riskLockHeld = false;
   if(_account_risk_enabled_runtime() && !_account_risk_lock_acquire())
   {
      string lockDetail = "account_risk_block lock_busy";
      Print("AtomicBridge direct_mt4 deferred by account risk lock event=", eventId);
      _account_risk_audit_write("lot_blocked", "event=" + eventId + " dir=" + dir + " " + lockDetail, false);
      _direct_audit_write("direct_skip_account_risk", source, eventId, 0, dir, 0.0, price, stopLoss, takeProfit, "risk_lock_busy", 0.0, lockDetail);
      return false;
   }
   riskLockHeld = _account_risk_enabled_runtime();
   if(riskLockHeld)
      _account_risk_cache_invalidate();
   string lotDetail = "";
   bool requireHalfSplit = _contains_ci(source, "AtomicRegime")
      ? (g_regimeDirectMt4HalfBeRRuntime > 0.0 || _direct_trigger_price_valid(dir, price, halfTriggerPrice))
      : (g_directMt4HalfBeTpIndexRuntime > 0 || g_directMt4HalfBeRRuntime > 0.0 || _direct_trigger_price_valid(dir, price, halfTriggerPrice));
   double lot = _direct_resolve_order_lot(price, stopLoss, type, requireHalfSplit, lotDetail);
   if(StringLen(atomicGeometryDetail) > 0)
      lotDetail = atomicGeometryDetail + " " + lotDetail;
   if(lot <= 0.0)
   {
      if(riskLockHeld)
         _account_risk_lock_release();
      _account_risk_audit_write("lot_blocked",
         "event=" + eventId + " source=" + source + " dir=" + dir
         + " entry=" + _fmt_price(price) + " sl=" + _fmt_price(stopLoss) + " tp=" + _fmt_price(takeProfit)
         + " " + lotDetail, false);
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 blocked by account risk engine event=", eventId, " ", lotDetail);
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, 0.0, signalPx, sl, tp, "confirmed_signal", 0.0, lotDetail);
      _direct_audit_write("direct_skip_account_risk", source, eventId, 0, dir, 0.0, price, stopLoss, takeProfit, "account_risk_block", 0.0, lotDetail);
      return false;
   }
   if(!_direct_event_claim(eventId, source))
   {
      if(riskLockHeld)
         _account_risk_lock_release();
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 duplicate suppressed event=", eventId, " dir=", dir);
      _direct_audit_write("direct_duplicate_suppressed", source, eventId, 0, dir, lot, price, stopLoss, takeProfit, "terminal_global_event_lock", 0.0, lotDetail);
      return true;
   }
   string comment = "AB|" + _direct_source_family(source) + "|" + _direct_instance_token(source);
   if(StringLen(comment) > 31)
      comment = StringSubstr(comment, 0, 31);
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lot, NormalizeDouble(price, Digits), InpDirectMt4Slippage, stopLoss, takeProfit, comment, _direct_magic(), 0, (type == OP_BUY ? clrLime : clrTomato));
   if(ticket > 0 && riskLockHeld)
      _account_risk_cache_invalidate();
   if(riskLockHeld)
      _account_risk_lock_release();
   _account_risk_audit_write("lot_selected",
      "event=" + eventId + " source=" + source + " dir=" + dir
      + " entry=" + _fmt_price(price) + " sl=" + _fmt_price(stopLoss) + " tp=" + _fmt_price(takeProfit)
      + " order_ticket=" + IntegerToString(ticket) + " " + lotDetail, false);
   g_lastDirectMt4EventId = eventId;
   if(ticket > 0)
   {
      double fillPrice = price;
      double actualSl = stopLoss;
      double actualTp = takeProfit;
      if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      {
         fillPrice = OrderOpenPrice();
         actualSl = OrderStopLoss();
         actualTp = OrderTakeProfit();
      }
      if(sourceIsRegime && _regime_pip_sl_enabled() && fillPrice > 0.0)
      {
         double fillAnchoredSl = actualSl;
         double fillAnchoredTp = actualTp;
         double fillAnchoredHalf = halfTriggerPrice;
         string fillAnchorDetail = "";
         bool fillInvert = g_atomicInvertTradeModeRuntime;
         if(_regime_reanchor_pip_geometry(dir, fillPrice, fillInvert, fillAnchoredSl, fillAnchoredTp, fillAnchoredHalf, fillAnchorDetail))
         {
            fillAnchoredSl = NormalizeDouble(fillAnchoredSl, Digits);
            fillAnchoredTp = NormalizeDouble(fillAnchoredTp, Digits);
            bool needsModify = (MathAbs(fillAnchoredSl - actualSl) > Point * 0.5 || MathAbs(fillAnchoredTp - actualTp) > Point * 0.5);
            if(needsModify)
            {
               ResetLastError();
               bool modOk = OrderModify(ticket, fillPrice, fillAnchoredSl, fillAnchoredTp, 0, clrNONE);
               if(modOk && OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
               {
                  actualSl = OrderStopLoss();
                  actualTp = OrderTakeProfit();
                  halfTriggerPrice = fillAnchoredHalf;
                  _direct_audit_write("direct_regime_pip_fill_reanchored", source, eventId, ticket, dir, lot, fillPrice, actualSl, actualTp, "order_modify_ok", 0.0, fillAnchorDetail);
               }
               else
               {
                  int modErr = GetLastError();
                  _direct_audit_write("direct_regime_pip_fill_reanchor_failed", source, eventId, ticket, dir, lot, fillPrice, actualSl, actualTp, "order_modify_err=" + IntegerToString(modErr), 0.0, fillAnchorDetail);
               }
            }
            else
            {
               halfTriggerPrice = fillAnchoredHalf;
            }
         }
      }
      double initialRisk = (actualSl > 0.0 ? MathAbs(fillPrice - actualSl) : 0.0);
      if(initialRisk > Point)
         _direct_state_set("IRISK", ticket, initialRisk);
      _direct_state_set("OWNER", ticket, Period());
      _direct_state_set("VOWN", ticket, _direct_instance_hash(source));
      _direct_state_set("MFE", ticket, 0.0);
      _direct_state_set("MAE", ticket, 0.0);
      _direct_state_set("MFE_PX", ticket, fillPrice);
      _direct_state_set("MAE_PX", ticket, fillPrice);
      _direct_state_set("MINR", ticket, 0.0);
      double activeHalfR = (_contains_ci(source, "AtomicRegime") ? g_regimeDirectMt4HalfBeRRuntime : (g_directMt4HalfBeTpIndexRuntime < g_directMt4TpIndexRuntime ? g_directMt4HalfBeRRuntime : 0.0));
      bool triggerRebased = false;
      string triggerGeometry = "";
      halfTriggerPrice = _direct_normalize_half_trigger(
         dir, fillPrice, actualSl, actualTp, halfTriggerPrice, activeHalfR,
         triggerRebased, triggerGeometry
      );
      if(_direct_trigger_price_valid(dir, fillPrice, halfTriggerPrice))
         _direct_set_half_trigger_price(ticket, NormalizeDouble(halfTriggerPrice, Digits));
      else
         halfTriggerPrice = 0.0;
      string halfExtra = "half_trigger_label=" + _trim(halfTriggerLabel)
         + " half_trigger=" + _fmt_price(halfTriggerPrice)
         + " initial_risk=" + DoubleToString(initialRisk, Digits)
         + " requested_price=" + _fmt_price(price)
         + " actual_fill=" + _fmt_price(fillPrice)
         + " trigger_geometry=" + triggerGeometry
         + " trigger_rebased=" + (triggerRebased ? "1" : "0")
         + " " + lotDetail;
      Print("AtomicBridge direct_mt4 order_sent ticket=", ticket, " dir=", dir, " lot=", DoubleToString(lot, 2), " price=", _fmt_price(fillPrice), " sl=", _fmt_price(actualSl), " tp=", _fmt_price(actualTp), " event=", eventId);
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, lot, signalPx, sl, tp, "confirmed_signal", 0.0, "written_after_order_send_to_avoid_latency " + halfExtra);
      _direct_audit_write("direct_order_sent", source, eventId, ticket, dir, lot, fillPrice, actualSl, actualTp, "order_send_ok", 0.0, comment + " " + halfExtra);
      if(triggerRebased)
         _direct_audit_write("direct_halfbe_fill_geometry_rebased", source, eventId, ticket, dir, lot, fillPrice, actualSl, actualTp, triggerGeometry, 0.0, halfExtra);
      return true;
   }
   int err = GetLastError();
   _direct_event_release(eventId, source);
   Print("AtomicBridge direct_mt4 order_failed err=", err, " dir=", dir, " lot=", DoubleToString(lot, 2), " price=", _fmt_price(price), " sl=", _fmt_price(stopLoss), " tp=", _fmt_price(takeProfit), " event=", eventId);
   _direct_audit_write("direct_signal_received", source, eventId, 0, dir, lot, signalPx, sl, tp, "confirmed_signal", 0.0, "written_after_order_send_to_avoid_latency half_trigger=" + _fmt_price(halfTriggerPrice));
   _direct_audit_write("direct_order_failed", source, eventId, 0, dir, lot, price, stopLoss, takeProfit, "err=" + IntegerToString(err), 0.0, comment);
   return false;
}

bool _csv_name_hit(string csv, string name)
{
   string raw = _trim(csv);
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   string parts[];
   int n = StringSplit(raw, 44, parts);
   for(int i = 0; i < n; i++)
   {
      string t = _trim(parts[i]);
      if(StringLen(t) > 0 && _contains_ci(name, t))
         return true;
   }
   return false;
}

string _tf_to_string(int tf)
{
   if(tf == PERIOD_M1)  return "M1";
   if(tf == PERIOD_M5)  return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1)  return "H1";
   if(tf == PERIOD_H4)  return "H4";
   if(tf == PERIOD_D1)  return "D1";
   if(tf == PERIOD_W1)  return "W1";
   if(tf == PERIOD_MN1) return "MN1";
   return IntegerToString(tf);
}

string _fmt_time(datetime t)
{
   return (t > 0 ? TimeToString(t, TIME_DATE | TIME_SECONDS) : "-");
}

string _fmt_price(double p)
{
   if(!MathIsValidNumber(p) || p == EMPTY_VALUE || p == 2147483647.0 || p == 0.0)
      return "-";
   return DoubleToString(p, Digits);
}

string _direct_audit_date(datetime t)
{
   return StringFormat("%04d%02d%02d", TimeYear(t), TimeMonth(t), TimeDay(t));
}

string _direct_audit_file_name()
{
   return "AtomicBridge_DirectAudit_" + _direct_audit_date(TimeGMT()) + ".csv";
}

string _direct_audit_gv_key(string kind, int ticket)
{
   int magic = _direct_magic();
   if(ticket > 0 && OrderSelect(ticket, SELECT_BY_TICKET))
      magic = OrderMagicNumber();
   return "AtomicBridgeMT4|" + Symbol() + "|" + IntegerToString(magic) + "|" + kind + "|" + IntegerToString(ticket);
}

bool _direct_audit_marked(string kind, int ticket)
{
   return GlobalVariableCheck(_direct_audit_gv_key(kind, ticket));
}

void _direct_audit_mark(string kind, int ticket)
{
   GlobalVariableSet(_direct_audit_gv_key(kind, ticket), TimeCurrent());
}

string _direct_audit_lock_key(string lane)
{
   return "AtomicBridgeMT4|AUDIT_LOCK|" + lane;
}

bool _direct_audit_lock_acquire(string lane, int maxWaitMs)
{
   string key = _direct_audit_lock_key(lane);
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   uint started = GetTickCount();
   int waitMs = MathMax(1, maxWaitMs);
   while((uint)(GetTickCount() - started) < (uint)waitMs)
   {
      double current = GlobalVariableGet(key);
      double now = (double)TimeLocal();
      if(current <= 0.0 || current < now)
      {
         if(GlobalVariableSetOnCondition(key, now + 2.0, current))
            return true;
      }
      Sleep(1);
   }
   return false;
}

void _direct_audit_lock_release_lane(string lane)
{
   GlobalVariableSet(_direct_audit_lock_key(lane), 0.0);
}

bool _direct_compact_audit_event_allowed(string eventName)
{
   string e = _lower_copy(_trim(eventName));
   if(e == "direct_signal_received")
      return false;
   if(StringFind(e, "probe") >= 0 || StringFind(e, "heartbeat") >= 0 || StringFind(e, "snapshot") >= 0)
      return false;
   if(StringFind(e, "order_sent") >= 0 || StringFind(e, "order_failed") >= 0)
      return true;
   if(StringFind(e, "closed") >= 0 || StringFind(e, "sl_hit") >= 0 || StringFind(e, "tp_hit") >= 0)
      return true;
   if(StringFind(e, "close_sent") >= 0 || StringFind(e, "close_failed") >= 0)
      return true;
   if(StringFind(e, "half") >= 0 || StringFind(e, "be") >= 0)
      return true;
   if(StringFind(e, "failed") >= 0 || StringFind(e, "blocked") >= 0 || StringFind(e, "skip") >= 0)
      return true;
   if(StringFind(e, "duplicate") >= 0 || StringFind(e, "defer") >= 0 || StringFind(e, "cancel") >= 0)
      return true;
   if(StringFind(e, "liquidation") >= 0 || StringFind(e, "risk") >= 0)
      return true;
   return false;
}

void _direct_audit_write(string eventName, string source, string eventId, int ticket, string direction, double lot, double price, double sl, double tp, string reason, double pnl, string extra)
{
   if(!_audit_enabled_runtime() || !InpDirectMt4AuditCsv)
      return;
   if(!_direct_compact_audit_event_allowed(eventName))
      return;
   if(!_direct_audit_lock_acquire("DIRECT", 75))
   {
      Print("AtomicBridge direct_mt4 audit lock timeout event=", eventName, " ticket=", ticket);
      return;
   }
   int h = FileOpen(_direct_audit_file_name(), FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      Print("AtomicBridge direct_mt4 audit open failed err=", GetLastError(), " file=", _direct_audit_file_name());
      _direct_audit_lock_release_lane("DIRECT");
      return;
   }
   bool empty = (FileSize(h) <= 0);
   FileSeek(h, 0, SEEK_END);
   if(empty)
   {
      FileWrite(h, "ts_gmt", "ts_server", "ts_local", "ms", "event", "build", "indicator", "symbol", "timeframe", "source", "event_id", "ticket", "direction", "lot", "price", "sl", "tp", "bid", "ask", "spread", "reason", "pnl", "extra");
   }
   RefreshRates();
   int ms = (int)(GetTickCount() % 1000);
   FileWrite(
      h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
      IntegerToString(ms),
      eventName,
      ATOMIC_BRIDGE_BUILD,
      InpIndicatorName,
      Symbol(),
      _tf_to_string(Period()),
      source,
      eventId,
      IntegerToString(ticket),
      direction,
      DoubleToString(lot, 2),
      _fmt_price(price),
      _fmt_price(sl),
      _fmt_price(tp),
      _fmt_price(Bid),
      _fmt_price(Ask),
      IntegerToString((int)MarketInfo(Symbol(), MODE_SPREAD)),
      reason,
      DoubleToString(pnl, 2),
      extra
   );
   FileFlush(h);
   FileClose(h);
   _direct_audit_lock_release_lane("DIRECT");
}

string _fmt_hms(datetime t)
{
   if(t <= 0)
      return "-";
   return StringFormat("%02d:%02d:%02d", TimeHour(t), TimeMinute(t), TimeSeconds(t));
}

void _regime_lifecycle_audit(string eventName, string eventId, string direction, int signalIndex, datetime signalTime, double entryPrice, double sl, double tp, string reason, datetime delayStart, datetime delayEnd, int delaySeconds, int ageSeconds, string extra)
{
   string detail = "signal_shift=" + IntegerToString(signalIndex)
      + " signal_time=" + _fmt_time(signalTime)
      + " signal_hms=" + _fmt_hms(signalTime)
      + " delay_start=" + _fmt_time(delayStart)
      + " delay_start_hms=" + _fmt_hms(delayStart)
      + " delay_end=" + _fmt_time(delayEnd)
      + " delay_end_hms=" + _fmt_hms(delayEnd)
      + " delay_sec=" + IntegerToString(delaySeconds)
      + " age_sec=" + IntegerToString(ageSeconds);
   if(StringLen(extra) > 0)
      detail = detail + " " + extra;
   _direct_audit_write(eventName, InpRegimeIndicatorName, eventId, 0, direction, 0.0, entryPrice, sl, tp, reason, 0.0, detail);
}

string _regime_event_id(string direction, datetime signalTime)
{
   if(direction == "" || signalTime <= 0)
      return "";
   return StringFormat("%s|%s|%I64d", Symbol(), direction, (long)signalTime);
}

void _regime_mark_delay_opened_if_needed(string eventId, string direction, datetime signalTime)
{
   if(!g_regimeDelayValidationRuntime || eventId == "")
      return;
   g_lastRegimeDelayOpenedEventId = eventId;
   g_lastRegimeDelayOpenedDirection = direction;
   g_lastRegimeDelayOpenedSignalTime = signalTime;
}

void _regime_clear_pending_state()
{
   g_pendingRegimeEventId = "";
   g_pendingRegimeDirection = "";
   g_pendingRegimeFirstSeen = 0;
   g_pendingRegimeSignalTime = 0;
   g_pendingRegimeSignalIndex = -1;
}

void _regime_validate_delayed_open_trade(bool hasRegime, string direction, int signalIndex, datetime signalTime)
{
   if(!g_regimeDelayValidationRuntime || !g_regimeCloseIfVanishesRuntime || g_lastRegimeDelayOpenedEventId == "")
      return;
   string currentEventId = (hasRegime ? _regime_event_id(direction, signalTime) : "");
   bool stillFresh = (
      currentEventId == g_lastRegimeDelayOpenedEventId
      && direction == g_lastRegimeDelayOpenedDirection
      && (InpRegimeMaxConfirmShift < 0 || signalIndex <= InpRegimeMaxConfirmShift)
   );
   if(stillFresh)
      return;

   string reason = "delay_validation_signal_vanished";
   if(currentEventId != g_lastRegimeDelayOpenedEventId)
      reason = "delay_validation_signal_replaced_or_missing";
   else if(InpRegimeMaxConfirmShift >= 0 && signalIndex > InpRegimeMaxConfirmShift)
      reason = "delay_validation_signal_not_on_confirm_shift";

   _regime_close_delay_validation_positions(
      g_lastRegimeDelayOpenedEventId,
      g_lastRegimeDelayOpenedDirection,
      reason,
      signalIndex,
      signalTime
   );
   g_lastRegimeDelayOpenedEventId = "";
   g_lastRegimeDelayOpenedDirection = "";
   g_lastRegimeDelayOpenedSignalTime = 0;
}

void _regime_mark_opened_for_validation(string eventId, string direction, datetime signalTime, int signalIndex)
{
   if(eventId == "" || direction == "" || signalTime <= 0)
      return;

   if(g_regimeDelayValidationRuntime)
   {
      g_lastRegimeDelayOpenedEventId = eventId;
      g_lastRegimeDelayOpenedDirection = direction;
      g_lastRegimeDelayOpenedSignalTime = signalTime;
      return;
   }

   // Direct SH0 is intentionally fast, but the first closed bar must confirm it.
   // If the live-bar signal disappears when that bar becomes shift=1, the trade
   // was opened from an unstable/repainting live signal and must be terminated.
   if(!g_regimeUseClosedBarRuntime && signalIndex == 0)
   {
      g_lastRegimeDirectSh0EventId = eventId;
      g_lastRegimeDirectSh0Direction = direction;
      g_lastRegimeDirectSh0SignalTime = signalTime;
      g_lastRegimeDirectSh0PendingValidation = true;
      _regime_lifecycle_audit(
         "regime_direct_sh0_validation_started",
         eventId,
         direction,
         signalIndex,
         signalTime,
         0.0,
         0.0,
         0.0,
         "opened_on_live_shift0",
         _timer_now(),
         0,
         0,
         0,
         "await_shift1_confirmation=1"
      );
   }
}

void _regime_validate_direct_sh0_open_trade(bool hasRegime, string direction, int signalIndex, datetime signalTime)
{
   if(!g_lastRegimeDirectSh0PendingValidation || g_lastRegimeDirectSh0EventId == "")
      return;
   if(g_regimeDelayValidationRuntime || g_regimeUseClosedBarRuntime)
      return;
   if(g_lastRegimeDirectSh0SignalTime <= 0)
      return;

   // Wait until the original live signal bar is no longer the active bar.
   if(Time[0] <= g_lastRegimeDirectSh0SignalTime)
      return;

   string currentEventId = (hasRegime ? _regime_event_id(direction, signalTime) : "");
   bool confirmed = (
      currentEventId == g_lastRegimeDirectSh0EventId
      && direction == g_lastRegimeDirectSh0Direction
      && signalTime == g_lastRegimeDirectSh0SignalTime
      && signalIndex >= 1
   );

   if(confirmed)
   {
      _regime_lifecycle_audit(
         "regime_direct_sh0_validated",
         g_lastRegimeDirectSh0EventId,
         g_lastRegimeDirectSh0Direction,
         signalIndex,
         signalTime,
         0.0,
         0.0,
         0.0,
         "signal_persisted_after_bar_close",
         0,
         _timer_now(),
         0,
         -1,
         "confirmed_shift=" + IntegerToString(signalIndex)
      );
      g_lastRegimeDirectSh0EventId = "";
      g_lastRegimeDirectSh0Direction = "";
      g_lastRegimeDirectSh0SignalTime = 0;
      g_lastRegimeDirectSh0PendingValidation = false;
      return;
   }

   string reason = "direct_sh0_signal_vanished_on_shift1";
   if(currentEventId != "" && currentEventId != g_lastRegimeDirectSh0EventId)
      reason = "direct_sh0_signal_replaced_on_shift1";

   double closeSignalPx = (g_lastRegimeDirectSh0Direction == "BUY") ? MarketInfo(Symbol(), MODE_BID) : MarketInfo(Symbol(), MODE_ASK);
   _file_bridge_write_signal(
      g_lastRegimeDirectSh0EventId + "|invalidate_close",
      g_lastRegimeDirectSh0Direction,
      closeSignalPx,
      0.0,
      0.0,
      "AtomicRegimeCloseOnly",
      0.0,
      reason,
      g_lastRegimeDirectSh0SignalTime
   );
   _regime_close_delay_validation_positions(
      g_lastRegimeDirectSh0EventId,
      g_lastRegimeDirectSh0Direction,
      reason,
      signalIndex,
      signalTime
   );
   _regime_lifecycle_audit(
      "regime_direct_sh0_invalidated",
      g_lastRegimeDirectSh0EventId,
      g_lastRegimeDirectSh0Direction,
      signalIndex,
      signalTime,
      0.0,
      0.0,
      0.0,
      reason,
      0,
      _timer_now(),
      0,
      -1,
      "current_event=" + currentEventId
   );
   g_lastRegimeDirectSh0EventId = "";
   g_lastRegimeDirectSh0Direction = "";
   g_lastRegimeDirectSh0SignalTime = 0;
   g_lastRegimeDirectSh0PendingValidation = false;
}
void _regime_cancel_pending_delay(string reason, bool hasRegime, string direction, int signalIndex, datetime signalTime)
{
   if(!g_regimeDelayValidationRuntime || g_pendingRegimeEventId == "")
      return;
   _regime_lifecycle_audit(
      "regime_delay_cancelled",
      g_pendingRegimeEventId,
      g_pendingRegimeDirection,
      signalIndex,
      signalTime,
      0.0,
      0.0,
      0.0,
      reason,
      g_pendingRegimeFirstSeen,
      _timer_now(),
      _regime_effective_delay_seconds(),
      (g_pendingRegimeFirstSeen > 0 ? (int)(_timer_now() - g_pendingRegimeFirstSeen) : -1),
      "pending_signal_time=" + _fmt_time(g_pendingRegimeSignalTime)
         + " pending_signal_hms=" + _fmt_hms(g_pendingRegimeSignalTime)
         + " pending_started_shift=" + IntegerToString(g_pendingRegimeSignalIndex)
         + " current_has_regime=" + (hasRegime ? "1" : "0")
         + " current_dir=" + direction
   );
   _regime_clear_pending_state();
}

string _direct_position_probe_file_name()
{
   return "AtomicBridge_PositionProbe_" + _direct_audit_date(TimeGMT()) + ".csv";
}

string _regime_signal_probe_file_name()
{
   return "AtomicBridge_RegimeSignalProbe_" + _direct_audit_date(TimeGMT()) + ".csv";
}

void _regime_signal_probe_write(
   string eventName,
   string reason,
   string selectedDirection,
   int selectedShift,
   datetime selectedTime,
   double selectedEntry,
   int upShift,
   datetime upTime,
   double upValue,
   int dnShift,
   datetime dnTime,
   double dnValue,
   string sourceName,
   string extra
)
{
   if(!_audit_enabled_runtime() || !InpRegimeSignalProbeAudit)
      return;
   if(!_direct_audit_lock_acquire("REGIME_SIGNAL", 25))
   {
      Print("AtomicBridge regime_signal_probe lock timeout event=", eventName);
      return;
   }
   int h = FileOpen(_regime_signal_probe_file_name(), FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      Print("AtomicBridge regime_signal_probe open failed err=", GetLastError(), " file=", _regime_signal_probe_file_name());
      _direct_audit_lock_release_lane("REGIME_SIGNAL");
      return;
   }
   bool empty = (FileSize(h) <= 0);
   FileSeek(h, 0, SEEK_END);
   if(empty)
   {
      FileWrite(
         h,
         "ts_gmt", "ts_server", "ts_local", "ms", "event", "reason", "build", "indicator",
         "symbol", "timeframe", "mode_enabled", "closed_bar", "base_shift", "max_shift",
         "up_buffer", "dn_buffer", "up_shift", "up_time", "up_value", "dn_shift", "dn_time",
         "dn_value", "selected_direction", "selected_shift", "selected_time", "selected_entry",
         "last_seen_event_id", "last_confirmed_event_id", "last_direction", "pending_event_id",
         "pending_direction", "pending_age_sec", "confirm_delay_sec", "max_confirm_shift",
         "bid", "ask", "spread", "source", "extra"
      );
   }
   RefreshRates();
   int ms = (int)(GetTickCount() % 1000);
   int baseShift = _regime_base_shift();
   int pendingAge = (g_pendingRegimeFirstSeen > 0 ? (int)(_timer_now() - g_pendingRegimeFirstSeen) : -1);
   FileWrite(
      h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
      IntegerToString(ms),
      eventName,
      reason,
      ATOMIC_BRIDGE_BUILD,
      InpIndicatorName,
      Symbol(),
      _tf_to_string(Period()),
      (g_atomicRegimeModeEnabledRuntime ? "1" : "0"),
      (g_regimeUseClosedBarRuntime ? "1" : "0"),
      IntegerToString(baseShift),
      IntegerToString(MathMax(0, InpRegimeSignalProbeMaxShift)),
      IntegerToString(MathMax(0, InpRegimeUpTrendSignalBuffer)),
      IntegerToString(MathMax(0, InpRegimeDnTrendSignalBuffer)),
      IntegerToString(upShift),
      _fmt_time(upTime),
      _fmt_price(upValue),
      IntegerToString(dnShift),
      _fmt_time(dnTime),
      _fmt_price(dnValue),
      selectedDirection,
      IntegerToString(selectedShift),
      _fmt_time(selectedTime),
      _fmt_price(selectedEntry),
      g_lastRegimeEventId,
      g_lastRegimeConfirmedEventId,
      g_lastRegimeDirection,
      g_pendingRegimeEventId,
      g_pendingRegimeDirection,
      IntegerToString(pendingAge),
      IntegerToString(g_regimeConfirmDelaySecondsRuntime),
      IntegerToString(InpRegimeMaxConfirmShift),
      _fmt_price(Bid),
      _fmt_price(Ask),
      IntegerToString((int)MarketInfo(Symbol(), MODE_SPREAD)),
      sourceName,
      extra
   );
   FileFlush(h);
   FileClose(h);
   _direct_audit_lock_release_lane("REGIME_SIGNAL");
}

void _regime_signal_probe_scan(string reason, bool hasRegime, string selectedDirection, int selectedShift, datetime selectedTime, double selectedEntry, string sourceName)
{
   if(!_audit_enabled_runtime() || !InpRegimeSignalProbeAudit)
      return;
   int baseShift = _regime_base_shift();
   if(Bars <= baseShift)
      return;
   int maxShift = MathMax(baseShift, MathMin(Bars - 1, MathMax(baseShift, InpRegimeSignalProbeMaxShift)));
   int upShift = -1;
   int dnShift = -1;
   datetime upTime = 0;
   datetime dnTime = 0;
   double upValue = 0.0;
   double dnValue = 0.0;
   bool hasUp = _find_latest_regime_signal_buffer(MathMax(0, InpRegimeUpTrendSignalBuffer), baseShift, maxShift, upShift, upTime, upValue);
   bool hasDn = _find_latest_regime_signal_buffer(MathMax(0, InpRegimeDnTrendSignalBuffer), baseShift, maxShift, dnShift, dnTime, dnValue);
   string eventId = "";
   if(hasRegime && selectedDirection != "" && selectedTime > 0)
      eventId = _regime_event_id(selectedDirection, selectedTime);
   string hash = StringFormat(
      "%s|%d|%I64d|%s|%d|%d|%d|%d|%s|%s|%s|%s",
      selectedDirection,
      selectedShift,
      (long)selectedTime,
      eventId,
      upShift,
      dnShift,
      (hasUp ? 1 : 0),
      (hasDn ? 1 : 0),
      g_lastRegimeEventId,
      g_lastRegimeConfirmedEventId,
      g_pendingRegimeEventId,
      g_lastRegimeDirection
   );
   datetime now = TimeLocal();
   bool changed = (hash != g_lastRegimeSignalProbeHash);
   int interval = MathMax(1, InpRegimeSignalProbeIntervalSeconds);
   if(!changed && InpRegimeSignalProbeWriteOnChange && g_lastRegimeSignalProbe > 0 && now - g_lastRegimeSignalProbe < interval)
      return;
   if(!InpRegimeSignalProbeWriteOnChange && g_lastRegimeSignalProbe > 0 && now - g_lastRegimeSignalProbe < interval)
      return;
   string eventName = hasRegime ? "regime_signal_seen" : "regime_signal_none";
   string extra = "event_id=" + eventId
      + " has_up=" + (hasUp ? "1" : "0")
      + " has_dn=" + (hasDn ? "1" : "0")
      + " changed=" + (changed ? "1" : "0");
   _regime_signal_probe_write(eventName, reason, selectedDirection, selectedShift, selectedTime, selectedEntry, upShift, upTime, upValue, dnShift, dnTime, dnValue, sourceName, extra);
   g_lastRegimeSignalProbe = now;
   g_lastRegimeSignalProbeHash = hash;
}

void _direct_position_probe_write(
   string eventName,
   int ticket,
   string direction,
   string source,
   double lots,
   double entry,
   double sl,
   double tp,
   double px,
   double risk,
   double finalRr,
   double currentR,
   double triggerPrice,
   string triggerLabel,
   bool reached,
   bool alreadyBe,
   bool halfMarked,
   bool beMarked,
   double pnl,
   string extra
)
{
   if(!_audit_enabled_runtime() || !InpDirectMt4PositionProbeAudit)
      return;
   if(!_direct_audit_lock_acquire("POSITION", 5))
   {
      Print("AtomicBridge position_probe audit lock timeout ticket=", ticket);
      return;
   }
   int h = FileOpen(_direct_position_probe_file_name(), FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE)
   {
      Print("AtomicBridge position_probe open failed err=", GetLastError(), " file=", _direct_position_probe_file_name());
      _direct_audit_lock_release_lane("POSITION");
      return;
   }
   bool empty = (FileSize(h) <= 0);
   FileSeek(h, 0, SEEK_END);
   if(empty)
   {
      FileWrite(
         h,
         "ts_gmt", "ts_server", "ts_local", "ms", "event", "build", "indicator", "symbol", "timeframe",
         "ticket", "direction", "source", "lots", "entry", "sl", "tp", "px", "bid", "ask", "spread",
         "risk", "final_rr", "current_r", "half_trigger", "half_trigger_label", "reached_half",
         "already_be", "half_marked", "be_marked", "pnl", "extra"
      );
   }
   int ms = (int)(GetTickCount() % 1000);
   FileWrite(
      h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
      IntegerToString(ms),
      eventName,
      ATOMIC_BRIDGE_BUILD,
      InpIndicatorName,
      Symbol(),
      _tf_to_string(Period()),
      IntegerToString(ticket),
      direction,
      source,
      DoubleToString(lots, 2),
      _fmt_price(entry),
      _fmt_price(sl),
      _fmt_price(tp),
      _fmt_price(px),
      _fmt_price(Bid),
      _fmt_price(Ask),
      IntegerToString((int)MarketInfo(Symbol(), MODE_SPREAD)),
      DoubleToString(risk, Digits),
      DoubleToString(finalRr, 3),
      DoubleToString(currentR, 3),
      _fmt_price(triggerPrice),
      triggerLabel,
      (reached ? "1" : "0"),
      (alreadyBe ? "1" : "0"),
      (halfMarked ? "1" : "0"),
      (beMarked ? "1" : "0"),
      DoubleToString(pnl, 2),
      extra
   );
   FileClose(h);
   _direct_audit_lock_release_lane("POSITION");
}

void _direct_position_probe_scan()
{
   if(!_audit_enabled_runtime() || !InpDirectMt4PositionProbeAudit)
      return;
   int interval = MathMax(1, InpDirectMt4PositionProbeIntervalSeconds);
   datetime now = TimeLocal();
   int scheduleGap = (g_directMt4LastPositionProbe > 0 ? (int)(now - g_directMt4LastPositionProbe) : 0);
   if(g_directMt4LastPositionProbe > 0 && now - g_directMt4LastPositionProbe < interval)
      return;
   g_directMt4LastPositionProbe = now;

   RefreshRates();
   string hash = "";
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;

      int ticket = OrderTicket();
      if(!_direct_order_owned_by_instance(ticket, OrderComment(), true))
         continue;
      int dir = OrderType() == OP_BUY ? 1 : -1;
      string direction = (dir > 0 ? "BUY" : "SELL");
      string source = OrderComment();
      bool isRegime = _contains_ci(source, "AtomicRegime");
      double activeHalfR = (isRegime ? g_regimeDirectMt4HalfBeRRuntime : (g_directMt4HalfBeTpIndexRuntime < g_directMt4TpIndexRuntime ? g_directMt4HalfBeRRuntime : 0.0));
      double entry = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      double px = (dir > 0 ? Bid : Ask);
      double risk = _direct_state_get("IRISK", ticket);
      if(risk <= Point)
         risk = (sl > 0.0 ? MathAbs(entry - sl) : 0.0);
      double finalRr = 0.0;
      double currentR = 0.0;
      if(risk > Point)
      {
         finalRr = (dir > 0) ? ((tp - entry) / risk) : ((entry - tp) / risk);
         currentR = (dir > 0) ? ((px - entry) / risk) : ((entry - px) / risk);
      }
      double storedTrigger = _direct_get_half_trigger_price(ticket);
      bool triggerRebased = false;
      string triggerGeometry = "";
      double triggerPrice = _direct_normalize_half_trigger(
         direction, entry, sl, tp, storedTrigger, activeHalfR,
         triggerRebased, triggerGeometry
      );
      string triggerLabel = "r" + DoubleToString(activeHalfR, 2);
      if(_direct_trigger_price_valid(direction, entry, triggerPrice))
      {
         triggerLabel = isRegime ? ("stored_r" + DoubleToString(activeHalfR, 2)) : ("stored_tp" + IntegerToString(MathMax(1, MathMin(5, g_directMt4HalfBeTpIndexRuntime))));
      }
      bool reached = (triggerPrice > 0.0 && currentR > 0.0) ? ((dir > 0) ? (px >= triggerPrice) : (px <= triggerPrice)) : false;
      bool alreadyBe = (sl > 0.0) ? ((dir > 0) ? (sl >= entry - Point) : (sl <= entry + Point)) : false;
      bool halfMarked = _direct_audit_marked("HALF", ticket);
      bool beMarked = _direct_audit_marked("BE", ticket);
      bool triggerSeen = _direct_state_get("SEEN", ticket) > 0.0;
      double maxR = _direct_state_get("MAXR", ticket);
      double minR = _direct_state_get("MINR", ticket);
      double mfe = _direct_state_get("MFE", ticket);
      double mae = _direct_state_get("MAE", ticket);
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      count++;
      hash = hash + IntegerToString(ticket) + ":" + DoubleToString(OrderLots(), 2) + ":" + _fmt_price(sl) + ":" + _fmt_price(tp) + ":" + DoubleToString(currentR, 2) + ";";
      _direct_position_probe_write(
         "position_probe",
         ticket,
         direction,
         source,
         OrderLots(),
         entry,
         sl,
         tp,
         px,
         risk,
         finalRr,
         currentR,
         triggerPrice,
         triggerLabel,
         reached,
         alreadyBe,
         halfMarked,
         beMarked,
         pnl,
         "trigger_seen=" + (triggerSeen ? "1" : "0")
         + " max_r=" + DoubleToString(maxR, 3)
         + " min_r=" + DoubleToString(minR, 3)
         + " mfe=" + DoubleToString(mfe, 2)
         + " mae=" + DoubleToString(mae, 2)
         + " initial_risk=" + DoubleToString(risk, Digits)
         + " schedule_gap_sec=" + IntegerToString(scheduleGap)
         + " tick_age_sec=" + IntegerToString(g_lastTickLocal > 0 ? (int)MathMax(0, now - g_lastTickLocal) : -1)
         + " connected=" + (IsConnected() ? "1" : "0")
         + " trigger_geometry=" + triggerGeometry
      );
   }

   if(count <= 0)
      hash = "flat";
   if(count <= 0 && (!InpDirectMt4PositionProbeWriteOnChange || hash != g_directMt4LastPositionProbeHash))
   {
      _direct_position_probe_write("position_probe_flat", 0, "", "", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", false, false, false, false, 0.0, "no_managed_positions");
   }
   g_directMt4LastPositionProbeHash = hash;
}

double _direct_lot_down(double lots)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   if(minLot <= 0.0)
      minLot = 0.01;
   double units = MathFloor((lots / step) + 0.0000001);
   double out = NormalizeDouble(units * step, _direct_lot_digits(step));
   if(out < minLot)
      return 0.0;
   return out;
}

int _direct_find_remainder_ticket(int oldTicket, int orderType, double entry, string source, double expectedLots)
{
   int bestTicket = 0;
   double bestScore = 1.0e100;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderTicket() == oldTicket)
         return oldTicket;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()) || OrderType() != orderType)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;
      if(source != "" && OrderComment() != source)
         continue;
      double entryGap = MathAbs(OrderOpenPrice() - entry);
      double lotGap = MathAbs(OrderLots() - expectedLots);
      double score = entryGap + lotGap * MathMax(Point, 1.0);
      if(score < bestScore)
      {
         bestScore = score;
         bestTicket = OrderTicket();
      }
   }
   return bestTicket;
}

void _direct_transfer_ticket_state(int oldTicket, int newTicket)
{
   if(oldTicket <= 0 || newTicket <= 0 || oldTicket == newTicket)
      return;
   _direct_state_copy("IRISK", oldTicket, newTicket);
   _direct_state_copy("HTP", oldTicket, newTicket);
   _direct_state_copy("TP1", oldTicket, newTicket);
   _direct_state_copy("BE", oldTicket, newTicket);
   _direct_state_copy("HALF", oldTicket, newTicket);
   _direct_state_copy("SEEN", oldTicket, newTicket);
   _direct_state_copy("MAXR", oldTicket, newTicket);
   _direct_state_copy_any("MINR", oldTicket, newTicket);
   _direct_state_copy_any("MFE", oldTicket, newTicket);
   _direct_state_copy_any("MAE", oldTicket, newTicket);
   _direct_state_copy_any("MFE_PX", oldTicket, newTicket);
   _direct_state_copy_any("MAE_PX", oldTicket, newTicket);
   _direct_state_copy("VOWN", oldTicket, newTicket);
   _direct_state_copy("OWNER", oldTicket, newTicket);
}

void _direct_history_cursor_init()
{
   datetime newestTime = 0;
   int newestTicket = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      datetime ct = OrderCloseTime();
      int tk = OrderTicket();
      if(!_direct_order_owned_by_instance(tk, OrderComment(), true))
         continue;
      if(ct > newestTime || (ct == newestTime && tk > newestTicket))
      {
         newestTime = ct;
         newestTicket = tk;
      }
   }
   g_directMt4LastHistoryAuditTime = newestTime;
   g_directMt4LastHistoryAuditTicket = newestTicket;
}

bool _direct_history_trigger_touched(int orderType, datetime openTime, datetime closeTime, double triggerPrice, double &extremePrice)
{
   extremePrice = 0.0;
   if(triggerPrice <= 0.0 || openTime <= 0 || closeTime <= 0)
      return false;
   int openShift = iBarShift(NULL, 0, openTime, false);
   int closeShift = iBarShift(NULL, 0, closeTime, false);
   if(openShift < 0 || closeShift < 0)
      return false;
   int start = MathMin(openShift, closeShift);
   int count = MathMin(5000, MathAbs(openShift - closeShift) + 1);
   if(count <= 0)
      return false;
   if(orderType == OP_BUY)
   {
      int highShift = iHighest(NULL, 0, MODE_HIGH, count, start);
      if(highShift < 0)
         return false;
      extremePrice = iHigh(NULL, 0, highShift);
      return extremePrice >= triggerPrice;
   }
   int lowShift = iLowest(NULL, 0, MODE_LOW, count, start);
   if(lowShift < 0)
      return false;
   // MT4 chart lows are Bid-based, while SELL positions close at Ask.
   // Historical tick spread is unavailable here, so use the current spread
   // as a conservative executable-price estimate and label it as suspected.
   double spreadEstimate = MathMax(0.0, MarketInfo(Symbol(), MODE_SPREAD) * Point);
   extremePrice = iLow(NULL, 0, lowShift) + spreadEstimate;
   return extremePrice <= triggerPrice;
}

void _direct_history_audit_scan()
{
   int interval = MathMax(1, InpDirectMt4HistoryAuditSeconds);
   datetime now = TimeCurrent();
   if(g_directMt4LastHistoryAuditScan > 0 && now - g_directMt4LastHistoryAuditScan < interval)
      return;
   g_directMt4LastHistoryAuditScan = now;

   datetime newestTime = g_directMt4LastHistoryAuditTime;
   int newestTicket = g_directMt4LastHistoryAuditTicket;
   int scanned = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0 && scanned < 120; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      scanned++;
      datetime ct = OrderCloseTime();
      int tk = OrderTicket();
      if(!_direct_order_owned_by_instance(tk, OrderComment(), true))
         continue;
      if(ct <= 0)
         continue;
      if(ct < g_directMt4LastHistoryAuditTime || (ct == g_directMt4LastHistoryAuditTime && tk <= g_directMt4LastHistoryAuditTicket))
         continue;
      if(_direct_audit_marked("HIST", tk))
      {
         if(ct > newestTime || (ct == newestTime && tk > newestTicket))
         {
            newestTime = ct;
            newestTicket = tk;
         }
         continue;
      }
      _direct_audit_mark("HIST", tk);
      string dir = (OrderType() == OP_BUY ? "BUY" : "SELL");
      double closePx = OrderClosePrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      double tol = MathMax(Point * 8.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point);
      string eventName = "direct_closed";
      if(sl > 0.0 && MathAbs(closePx - sl) <= tol)
         eventName = "direct_sl_hit";
      else if(tp > 0.0 && MathAbs(closePx - tp) <= tol)
         eventName = "direct_tp_hit";
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      double initialRisk = _direct_state_get("IRISK", tk);
      double triggerPrice = _direct_state_get("HTP", tk);
      double maxR = _direct_state_get("MAXR", tk);
      bool triggerSeen = _direct_state_get("SEEN", tk) > 0.0;
      bool halfMarked = _direct_audit_marked("HALF", tk);
      bool beMarked = _direct_audit_marked("BE", tk);
      double minR = _direct_state_get("MINR", tk);
      double mfe = _direct_state_get("MFE", tk);
      double mae = _direct_state_get("MAE", tk);
      double mfePx = _direct_state_get("MFE_PX", tk);
      double maePx = _direct_state_get("MAE_PX", tk);
      double barExtreme = 0.0;
      bool barTouched = _direct_history_trigger_touched(OrderType(), OrderOpenTime(), ct, triggerPrice, barExtreme);
      string lifecycle = "initial_risk=" + DoubleToString(initialRisk, Digits)
         + " trigger=" + _fmt_price(triggerPrice)
         + " trigger_seen=" + (triggerSeen ? "1" : "0")
         + " bar_touch_estimate=" + (barTouched ? "1" : "0")
         + " bar_extreme=" + _fmt_price(barExtreme)
         + " max_r=" + DoubleToString(maxR, 3)
         + " min_r=" + DoubleToString(minR, 3)
         + " mfe=" + DoubleToString(mfe, 2)
         + " mae=" + DoubleToString(mae, 2)
         + " mfe_px=" + _fmt_price(mfePx)
         + " mae_px=" + _fmt_price(maePx)
         + " be_marked=" + (beMarked ? "1" : "0")
         + " half_marked=" + (halfMarked ? "1" : "0");
      _direct_audit_write(eventName, OrderComment(), "", tk, dir, OrderLots(), closePx, sl, tp, "history_close", pnl, lifecycle);
      if(triggerSeen && (!beMarked || !halfMarked))
      {
         string missing = (!beMarked && !halfMarked) ? "be_and_half" : (!beMarked ? "be" : "half");
         _direct_audit_write("direct_halfbe_missed_detected", OrderComment(), "", tk, dir, OrderLots(), closePx, sl, tp, "missing=" + missing, pnl, lifecycle);
      }
      else if(barTouched && (!beMarked || !halfMarked))
      {
         string missing = (!beMarked && !halfMarked) ? "be_and_half" : (!beMarked ? "be" : "half");
         _direct_audit_write("direct_halfbe_missed_suspected", OrderComment(), "", tk, dir, OrderLots(), closePx, sl, tp, "missing=" + missing + " bid_ask_history_estimate", pnl, lifecycle);
      }
      if(ct > newestTime || (ct == newestTime && tk > newestTicket))
      {
         newestTime = ct;
         newestTicket = tk;
      }
   }
   g_directMt4LastHistoryAuditTime = newestTime;
   g_directMt4LastHistoryAuditTicket = newestTicket;
}

string _json_escape(string s)
{
   string out = s;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   StringReplace(out, "\r\n", "\\n");
   StringReplace(out, "\n", "\\n");
   StringReplace(out, "\r", "\\n");
   return out;
}

string _normalize_base_url(string baseUrl)
{
   string b = _trim(baseUrl);
   if(StringLen(b) == 0)
      b = "http://127.0.0.1";
   if(StringSubstr(b, 0, 7) != "http://" && StringSubstr(b, 0, 8) != "https://")
      b = "http://" + b;
   while(StringLen(b) > 0 && StringSubstr(b, StringLen(b) - 1, 1) == "/")
      b = StringSubstr(b, 0, StringLen(b) - 1);
   return b;
}

string _normalize_path(string apiPath)
{
   string p = _trim(apiPath);
   if(StringLen(p) == 0)
      p = "/api/v1/mt4/bridge/signal";
   if(StringSubstr(p, 0, 1) != "/")
      p = "/" + p;
   return p;
}

string _build_endpoint(string baseUrl, string apiPath)
{
   return _normalize_base_url(baseUrl) + _normalize_path(apiPath);
}

string _event_ts_now()
{
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   return TimeToString(nowTs, TIME_DATE | TIME_SECONDS);
}

string _bridge_runtime_telemetry_json()
{
   RefreshRates();
   datetime serverTs = _timer_now();
   datetime gmtTs = TimeGMT();
   datetime localTs = TimeLocal();
   double bid = MarketInfo(Symbol(), MODE_BID);
   double ask = MarketInfo(Symbol(), MODE_ASK);
   double point = MarketInfo(Symbol(), MODE_POINT);
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   return
      "\"mt4_server_time\":\"" + _json_escape(TimeToString(serverTs, TIME_DATE | TIME_SECONDS)) + "\","
      "\"mt4_server_unix\":" + IntegerToString((int)serverTs) + ","
      "\"mt4_gmt_time\":\"" + _json_escape(TimeToString(gmtTs, TIME_DATE | TIME_SECONDS)) + "\","
      "\"mt4_gmt_unix\":" + IntegerToString((int)gmtTs) + ","
      "\"mt4_local_time\":\"" + _json_escape(TimeToString(localTs, TIME_DATE | TIME_SECONDS)) + "\","
      "\"mt4_local_unix\":" + IntegerToString((int)localTs) + ","
      "\"mt4_bid\":" + DoubleToString(bid, Digits) + ","
      "\"mt4_ask\":" + DoubleToString(ask, Digits) + ","
      "\"mt4_point\":" + DoubleToString(point, Digits + 2) + ","
      "\"mt4_spread_points\":" + IntegerToString(spread) + ","
      "\"atomic_tp_index\":" + IntegerToString(g_directMt4TpIndexRuntime) + ","
      "\"atomic_sl_geometry_enabled\":" + (g_atomicDirectRiskGeometryRuntime ? "true" : "false") + ","
      "\"atomic_target_r\":" + DoubleToString(g_atomicDirectTargetRRuntime, 2) + ","
      "\"atomic_halfbe_tp_index\":" + IntegerToString(g_directMt4HalfBeTpIndexRuntime) + ","
      "\"atomic_fallback_halfbe_r\":" + DoubleToString(g_directMt4HalfBeRRuntime, 2) + ","
      "\"regime_halfbe_r\":" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2) + ","
      "\"regime_pip_sl_mode\":" + (g_regimePipSlModeRuntime ? "true" : "false") + ","
      "\"regime_pip_sl_pips\":" + DoubleToString(g_regimePipSlPipsRuntime, 2) + ","
      "\"regime_signal_open_sl_mode\":" + (g_regimeSignalOpenSlModeRuntime ? "true" : "false") + ",";
}

datetime _timer_now()
{
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   return nowTs;
}

bool _heartbeat_due(datetime lastPostTime)
{
   int sec = MathMax(0, InpResolvedHeartbeatSeconds);
   if(sec <= 0)
      return false;
   datetime nowTs = _timer_now();
   if(lastPostTime <= 0)
      return true;
   return (nowTs - lastPostTime) >= sec;
}

bool _register_heartbeat_due()
{
   int sec = MathMax(0, InpRegisterHeartbeatSeconds);
   if(sec <= 0)
      return false;
   datetime nowTs = _timer_now();
   if(g_lastRegisterPostTime <= 0)
      return true;
   return (nowTs - g_lastRegisterPostTime) >= sec;
}

void MaybePostRegisterHeartbeat(string reason)
{
   if(!g_proTradePostEnabledRuntime || !_register_heartbeat_due())
      return;
   _post_atomic_bridge_event("register", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", reason);
   g_lastRegisterPostTime = _timer_now();
}

bool _parse_atomic_object_name(string name, string &direction, string &kind, int &tpIndex, int &signalIndex)
{
   direction = "";
   kind = "";
   tpIndex = -1;
   signalIndex = -1;

   string clean = _trim(name);
   int nums[];
   int count = 0;
   ArrayResize(nums, 0);

   string cur = "";
   int len = StringLen(clean);
   for(int i = 0; i < len; i++)
   {
      int ch = StringGetChar(clean, i);
      if(ch >= '0' && ch <= '9')
      {
         cur += StringSubstr(clean, i, 1);
      }
      else
      {
         if(StringLen(cur) > 0)
         {
            ArrayResize(nums, count + 1);
            nums[count++] = (int)StrToInteger(cur);
            cur = "";
         }
      }
   }
   if(StringLen(cur) > 0)
   {
      ArrayResize(nums, count + 1);
      nums[count++] = (int)StrToInteger(cur);
   }

   if(count <= 0)
      return false;

   string lc = _lower_copy(clean);

   if(StringFind(lc, "buytrend") >= 0 || StringFind(lc, "selltrend") >= 0)
   {
      direction = (StringFind(lc, "buytrend") >= 0 ? "BUY" : "SELL");
      kind = "TREND";
      signalIndex = nums[count - 1];
      return signalIndex >= 0;
   }

   if(StringFind(lc, "buytxtsloss") >= 0 || StringFind(lc, "selltxtsloss") >= 0)
   {
      direction = (StringFind(lc, "buytxtsloss") >= 0 ? "BUY" : "SELL");
      kind = "SL";
      signalIndex = nums[count - 1];
      return signalIndex >= 0;
   }

   if(StringFind(lc, "buytxttp") >= 0 || StringFind(lc, "selltxttp") >= 0)
   {
      if(count < 2)
         return false;
      direction = (StringFind(lc, "buytxttp") >= 0 ? "BUY" : "SELL");
      kind = "TP";
      tpIndex = nums[count - 2];
      signalIndex = nums[count - 1];
      return tpIndex >= 0 && signalIndex >= 0;
   }

   return false;
}

double _object_price0(string name)
{
   double p = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   if(MathIsValidNumber(p) && p != EMPTY_VALUE && p != 2147483647.0 && p != 0.0)
      return p;
   return 0.0;
}

datetime _object_time0(string name)
{
   return (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
}

bool _find_latest_atomic_signal(string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &trendName, bool logOnNone = true)
{
   direction = "";
   signalIndex = -1;
   signalTime = 0;
   entryPrice = 0.0;
   trendName = "";

   int total = ObjectsTotal(0, -1, -1);
   int parsed = 0;
   int trends = 0;
   int levels = 0;
   int atomicLike = 0;

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(_csv_name_hit(InpIgnoreNamePatterns, name))
         continue;

      string lname = _lower_copy(name);
      if(StringFind(lname, "buy") >= 0 || StringFind(lname, "sell") >= 0 || StringFind(lname, "atomic") >= 0 || StringFind(lname, "buffer=") >= 0)
         atomicLike++;

      string dir, kind;
      int tpIdx, sigIdx;
      if(!_parse_atomic_object_name(name, dir, kind, tpIdx, sigIdx))
         continue;
      parsed++;
      if(kind != "TREND")
      {
         levels++;
         continue;
      }
      trends++;

      datetime t = _object_time0(name);
      double p = _object_price0(name);
      if(t <= 0 || p <= 0.0)
         continue;

      if(t > signalTime)
      {
         direction = dir;
         signalIndex = sigIdx;
         signalTime = t;
         entryPrice = p;
         trendName = name;
      }
   }

   if(signalTime > 0 && signalIndex >= 0 && StringLen(direction) > 0)
      return true;

   // Fallback: some Atomic builds can omit/rename Trend objects while still drawing SL/TP labels.
   // This is less ideal for entry, but it proves object parsing and keeps diagnostics useful.
   for(int j = total - 1; j >= 0; j--)
   {
      string fallbackName = ObjectName(0, j, -1, -1);
      if(_csv_name_hit(InpIgnoreNamePatterns, fallbackName))
         continue;

      string fDir, fKind;
      int fTpIdx, fSigIdx;
      if(!_parse_atomic_object_name(fallbackName, fDir, fKind, fTpIdx, fSigIdx))
         continue;
      if(fKind != "SL" && fKind != "TP")
         continue;

      datetime ft = _object_time0(fallbackName);
      double fp = _object_price0(fallbackName);
      if(ft <= 0 || fp <= 0.0)
         continue;

      if(ft > signalTime)
      {
         direction = fDir;
         signalIndex = fSigIdx;
         signalTime = ft;
         entryPrice = fp;
         trendName = fallbackName + " [fallback-level-object]";
      }
   }

   if(InpDebugObjects || (logOnNone && signalTime <= 0))
   {
      PrintFormat(
         "AtomicBridge scan_stats total=%d atomic_like=%d parsed=%d trends=%d levels=%d selected_time=%s selected_dir=%s selected_idx=%d",
         total, atomicLike, parsed, trends, levels, _fmt_time(signalTime), direction, signalIndex
      );
   }

   return signalTime > 0 && signalIndex >= 0 && StringLen(direction) > 0;
}

void _find_atomic_levels(string direction, int signalIndex, double &sl, double &tp1, double &tp2, double &tp3, double &tp4, double &tp5)
{
   sl = 0.0;
   tp1 = 0.0;
   tp2 = 0.0;
   tp3 = 0.0;
   tp4 = 0.0;
   tp5 = 0.0;

   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(_csv_name_hit(InpIgnoreNamePatterns, name))
         continue;

      string dir, kind;
      int tpIdx, sigIdx;
      if(!_parse_atomic_object_name(name, dir, kind, tpIdx, sigIdx))
         continue;
      if(dir != direction || sigIdx != signalIndex)
         continue;

      double p = _object_price0(name);
      if(p <= 0.0)
         continue;

      if(kind == "SL")
         sl = p;
      else if(kind == "TP")
      {
         if(tpIdx == 0) tp1 = p;
         if(tpIdx == 1) tp2 = p;
         if(tpIdx == 2) tp3 = p;
         if(tpIdx == 3) tp4 = p;
         if(tpIdx == 4) tp5 = p;
      }
   }
}


bool _find_atomic_levels_for_signal_time(string direction, datetime signalTime, double &entryPrice, int &signalIndex, double &sl, double &tp1, double &tp2, double &tp3, double &tp4, double &tp5, string &trendName)
{
   entryPrice = 0.0;
   signalIndex = -1;
   sl = 0.0;
   tp1 = 0.0;
   tp2 = 0.0;
   tp3 = 0.0;
   tp4 = 0.0;
   tp5 = 0.0;
   trendName = "";

   string wantedDir = _trim(direction);
   if((wantedDir != "BUY" && wantedDir != "SELL") || signalTime <= 0)
      return false;

   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(_csv_name_hit(InpIgnoreNamePatterns, name))
         continue;

      string dir, kind;
      int tpIdx, sigIdx;
      if(!_parse_atomic_object_name(name, dir, kind, tpIdx, sigIdx))
         continue;
      if(dir != wantedDir || _object_time0(name) != signalTime)
         continue;

      double p = _object_price0(name);
      if(p <= 0.0)
         continue;

      if(signalIndex < 0 && sigIdx >= 0)
         signalIndex = sigIdx;
      if(kind == "TREND")
      {
         entryPrice = p;
         trendName = name;
         signalIndex = sigIdx;
      }
      else if(kind == "SL")
      {
         sl = p;
      }
      else if(kind == "TP")
      {
         if(tpIdx == 0) tp1 = p;
         if(tpIdx == 1) tp2 = p;
         if(tpIdx == 2) tp3 = p;
         if(tpIdx == 3) tp4 = p;
         if(tpIdx == 4) tp5 = p;
      }
   }

   return (entryPrice > 0.0 && signalIndex >= 0 && sl > 0.0 && tp1 > 0.0);
}
double _atomic_final_tp(double tp1, double tp2, double tp3, double tp4, double tp5)
{
   if(tp5 > 0.0) return tp5;
   if(tp4 > 0.0) return tp4;
   if(tp3 > 0.0) return tp3;
   if(tp2 > 0.0) return tp2;
   if(tp1 > 0.0) return tp1;
   return 0.0;
}

bool _atomic_signal_geometry_valid(
   string direction,
   double signalEntry,
   double sl,
   double tp1,
   double tp2,
   double tp3,
   double tp4,
   double tp5,
   string &reason
)
{
   reason = "";
   string dir = _trim(direction);
   double finalTp = g_atomicDirectRiskGeometryRuntime ? _select_direct_tp(tp1, tp2, tp3, tp4, tp5) : _atomic_final_tp(tp1, tp2, tp3, tp4, tp5);
   double point = MarketInfo(Symbol(), MODE_POINT);
   if(point <= 0.0)
      point = Point;
   double minGap = MathMax(point * 2.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * point);
   double livePx = 0.0;

   if(dir == "BUY")
      livePx = MarketInfo(Symbol(), MODE_ASK);
   else if(dir == "SELL")
      livePx = MarketInfo(Symbol(), MODE_BID);
   else
   {
      reason = "invalid_direction";
      return false;
   }

   if(signalEntry <= 0.0 || sl <= 0.0 || finalTp <= 0.0)
   {
      reason = "missing_entry_sl_tp";
      return false;
   }

   if(dir == "BUY")
   {
      if(sl >= signalEntry - minGap)
      {
         reason = "buy_sl_not_below_signal_entry";
         return false;
      }
      if(finalTp <= signalEntry + minGap)
      {
         reason = "buy_tp_not_above_signal_entry";
         return false;
      }
      if(livePx > 0.0 && finalTp <= livePx + minGap)
      {
         reason = "buy_tp_already_passed_live_price";
         return false;
      }
   }
   else
   {
      if(sl <= signalEntry + minGap)
      {
         reason = "sell_sl_not_above_signal_entry";
         return false;
      }
      if(finalTp >= signalEntry - minGap)
      {
         reason = "sell_tp_not_below_signal_entry";
         return false;
      }
      if(livePx > 0.0 && finalTp >= livePx - minGap)
      {
         reason = "sell_tp_already_passed_live_price";
         return false;
      }
   }

   return true;
}

void _debug_print_atomic_objects()
{
   if(!InpDebugObjects)
      return;

   int total = ObjectsTotal(0, -1, -1);
   int printed = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      string dir, kind;
      int tpIdx, sigIdx;
      if(!_parse_atomic_object_name(name, dir, kind, tpIdx, sigIdx))
         continue;

      PrintFormat(
         "AtomicBridge object dir=%s kind=%s tp=%d idx=%d time=%s price=%s name='%s'",
         dir, kind, tpIdx, sigIdx, _fmt_time(_object_time0(name)), _fmt_price(_object_price0(name)), name
      );

      if(++printed >= 40)
         break;
   }
}

bool _post_atomic_bridge_event(
   string eventType,
   string direction,
   int signalIndex,
   datetime signalTime,
   double entryPrice,
   double sl,
   double tp1,
   double tp2,
   double tp3,
   double tp4,
   double tp5,
   string trendName,
   string reason
)
{
   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string eventId = StringFormat(
      "atomic|%s|%s|%s|%d|%I64d|%s",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      (long)signalTime,
      eventKind
   );
   bool directFirst = (eventKind == "confirmed_signal" && _direct_priority_direct_first());
   string signalDir = dir;
   double directTp = _select_direct_tp(tp1, tp2, tp3, tp4, tp5);
   double atomicExecutionSl = sl;
   string atomicGeometryDetail = "atomic_indicator_sl";
   if(!_atomic_effective_sl_for_mode(dir, entryPrice, sl, directTp, atomicExecutionSl, atomicGeometryDetail))
      atomicExecutionSl = 0.0;
   if((dir == "BUY" || dir == "SELL") && atomicExecutionSl <= 0.0)
   {
      Print("AtomicBridge skipped reason=atomic_effective_sl_invalid event=", eventId,
            " dir=", dir,
            " mode=", (g_atomicDirectRiskGeometryRuntime ? "r_geometry" : "indicator"),
            " detail=", atomicGeometryDetail,
            " indicator_sl=", _fmt_price(sl),
            " selected_tp=", _fmt_price(directTp));
      return false;
   }
   if(_atomic_invert_enabled_for_event(eventKind, dir))
   {
      string invertedDir = "";
      double invertedSl = 0.0;
      double invertedTp = 0.0;
      string invertDetail = "";
      if(!_atomic_build_inverted_geometry(dir, entryPrice, atomicExecutionSl, directTp, invertedDir, invertedSl, invertedTp, invertDetail))
      {
         Print("AtomicBridge skipped reason=atomic_invert_geometry_invalid event=", eventId,
               " dir=", dir,
               " detail=", invertDetail);
         return false;
      }
      dir = invertedDir;
      atomicExecutionSl = invertedSl;
      directTp = invertedTp;
      tp1 = directTp;
      tp2 = directTp;
      tp3 = directTp;
      tp4 = directTp;
      tp5 = directTp;
      atomicGeometryDetail = invertDetail;
      if(eventKind == "confirmed_signal")
         eventId = eventId + "|invert";
   }
   int halfTpIndex = MathMax(1, MathMin(5, g_directMt4HalfBeTpIndexRuntime));
   bool atomicHalfEnabled = (halfTpIndex < g_directMt4TpIndexRuntime);
   double directHalfTrigger = 0.0;
   string directHalfLabel = "disabled_at_or_after_final_tp";
   if(g_atomicInvertTradeModeRuntime && (dir == "BUY" || dir == "SELL"))
   {
      directHalfTrigger = _atomic_invert_hcbe_price(dir, entryPrice, directTp);
      directHalfLabel = directHalfTrigger > 0.0 ? ("inv_" + IntegerToString(g_atomicInvertHcBeProgressPctRuntime) + "pct") : "invert_hcbe_off";
   }
   else
   {
      directHalfTrigger = atomicHalfEnabled ? _direct_tp_by_index(halfTpIndex, tp1, tp2, tp3, tp4, tp5) : 0.0;
      directHalfLabel = atomicHalfEnabled ? ("tp" + IntegerToString(halfTpIndex)) : "disabled_at_or_after_final_tp";
   }
   string dailyGuardReason = "";
   string dailyGuardDetail = "";
   if(eventKind == "confirmed_signal" && _direct_daily_profit_loss_guard_reached(dailyGuardReason, dailyGuardDetail))
   {
      Print("AtomicBridge outgoing signal skipped reason=", dailyGuardReason, " event=", eventId, " dir=", dir, " ", dailyGuardDetail);
      _direct_audit_write("direct_signal_received", InpIndicatorName, eventId, 0, dir, g_directMt4LotRuntime, entryPrice, atomicExecutionSl, directTp, "confirmed_signal", 0.0, dailyGuardReason + "_path outgoing_post_and_file_bridge_not_written=1 half_trigger=" + _fmt_price(directHalfTrigger));
      _direct_audit_write("direct_skip_daily_profit_loss_target", InpIndicatorName, eventId, 0, dir, g_directMt4LotRuntime, entryPrice, atomicExecutionSl, directTp, dailyGuardDetail, 0.0, dailyGuardReason + " outgoing_post_and_file_bridge_not_written=1");
      return false;
   }
   if(directFirst)
      _direct_mt4_execute(eventId, dir, atomicExecutionSl, directTp, InpIndicatorName, directHalfTrigger, directHalfLabel, signalTime);
   if(!g_proTradePostEnabledRuntime)
   {
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, atomicExecutionSl, directTp, InpIndicatorName, directHalfTrigger, directHalfLabel, signalTime);
      return true;
   }
   string msg = StringFormat(
      "Atomic %s %s %s idx=%d entry=%s sl=%s tp1=%s tp2=%s tp3=%s tp4=%s tp5=%s",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      _fmt_price(entryPrice),
      _fmt_price(atomicExecutionSl),
      _fmt_price(tp1),
      _fmt_price(tp2),
      _fmt_price(tp3),
      _fmt_price(tp4),
      _fmt_price(tp5)
   );

   string resolved = (dir == "BUY" || dir == "SELL") ? dir : "NONE";
   if((eventKind == "confirmed_signal" || eventKind == "resolved_state") && (dir == "BUY" || dir == "SELL") && signalTime > 0)
   {
      g_lastObservedSignalDirection = dir;
      g_lastObservedSignalTime = signalTime;
      g_lastObservedSignalValue = entryPrice;
   }
   string lastSignalDirection = g_lastObservedSignalDirection;
   datetime lastSignalTime = g_lastObservedSignalTime;
   double lastSignalValue = g_lastObservedSignalValue;
   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpIndicatorName) + "\","
      "\"signal_hint\":\"" + _json_escape(dir) + "\","
      "\"resolved_signal\":\"" + _json_escape(resolved) + "\","
      "\"confirmed_direction\":\"" + _json_escape((eventKind == "confirmed_signal") ? dir : "") + "\","
      "\"bridge_version\":\"v2\","
      "\"symbol\":\"" + _json_escape(Symbol()) + "\","
      "\"timeframe\":\"" + _json_escape(_tf_to_string(Period())) + "\","
      "\"signal_profile\":\"" + _json_escape(InpSignalProfile) + "\","
      "\"bridge_event_type\":\"" + _json_escape(eventKind) + "\","
      "\"event_id\":\"" + _json_escape(eventId) + "\","
      "\"event_ts\":\"" + _json_escape(_event_ts_now()) + "\"," +
      _bridge_runtime_telemetry_json() +
      "\"resolved_signal_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\","
      "\"resolved_signal_bar_unix\":" + IntegerToString((int)signalTime) + ","
      "\"last_signal_direction\":\"" + _json_escape(lastSignalDirection) + "\","
      "\"last_signal_bar_time\":\"" + _json_escape(_fmt_time(lastSignalTime)) + "\","
      "\"last_signal_bar_unix\":" + IntegerToString((int)lastSignalTime) + ","
      "\"last_signal_value\":" + DoubleToString(lastSignalValue, Digits) + ","
      "\"secondary_enabled\":true,"
      "\"secondary_indicator\":\"AtomicLevels\","
      "\"secondary_signal\":\"" + _json_escape(dir) + "\","
      "\"secondary_resolved_signal\":\"" + _json_escape(dir) + "\","
      "\"secondary_signal_shift\":-1,"
      "\"secondary_resolved_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\","
      "\"secondary_entry_enabled\":true,"
      "\"secondary_entry\":" + DoubleToString(entryPrice, Digits) + ","
      "\"secondary_sl_enabled\":true,"
      "\"secondary_stop_loss\":" + DoubleToString(atomicExecutionSl, Digits) + ","
      "\"secondary_tp_enabled\":true,"
      "\"secondary_tp1\":" + DoubleToString(tp1, Digits) + ","
      "\"secondary_tp2\":" + DoubleToString(tp2, Digits) + ","
      "\"secondary_tp3\":" + DoubleToString(tp3, Digits) + ","
      "\"secondary_tp4\":" + DoubleToString(tp4, Digits) + ","
      "\"secondary_tp5\":" + DoubleToString(tp5, Digits) + ","
      "\"message\":\"" + _json_escape(msg) + "\","
      "\"atomic_signal_index\":" + IntegerToString(signalIndex) + ","
      "\"atomic_original_signal_direction\":\"" + _json_escape(signalDir) + "\","
      "\"atomic_invert_mode\":" + (g_atomicInvertTradeModeRuntime ? "true" : "false") + ","
      "\"atomic_geometry_detail\":\"" + _json_escape(atomicGeometryDetail) + "\","
      "\"atomic_trend_object\":\"" + _json_escape(trendName) + "\","
      "\"atomic_reason\":\"" + _json_escape(reason) + "\","
      "\"bridge_token\":\"" + _json_escape(InpBridgeToken) + "\""
      "}";

   char post[];
   StringToCharArray(body, post, 0, StringLen(body));
   char result[];
   string responseHeaders = "";
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(InpBridgeToken) > 0)
      headers = headers + "X-MT4-Bridge-Token: " + InpBridgeToken + "\r\n";

   ResetLastError();
   int code = WebRequest("POST", endpoint, headers, MathMax(1000, InpHttpTimeoutMs), post, result, responseHeaders);
   string response = CharArrayToString(result, 0, -1);
   if(code >= 200 && code < 300)
   {
      if(InpLogPostResponses || _should_log_handshake_response(eventKind, reason))
      {
         Print("AtomicBridge handshake sent ", eventKind, " ", dir, " reason=", reason, " response=", _compact_bridge_response(response));
      }
      else if(eventKind == "confirmed_signal")
      {
         Print("AtomicBridge sent ", eventKind, " ", dir);
      }
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, atomicExecutionSl, directTp, InpIndicatorName, directHalfTrigger, directHalfLabel, signalTime);
      return true;
   }

   Print("AtomicBridge POST failed code=", code, " err=", GetLastError(), " event=", eventKind, " dir=", dir, " endpoint=", endpoint, " response=", response);
   if(eventKind == "confirmed_signal" && !directFirst)
      _direct_mt4_execute(eventId, dir, atomicExecutionSl, directTp, InpIndicatorName, directHalfTrigger, directHalfLabel, signalTime);
   return false;
}


bool _regime_wait_or_sync_atomic_companion(string regimeEventId, string direction, int signalIndex, datetime signalTime, double entryPrice, double regimeSl, double regimeTp, string reason)
{
   if(!g_atomicModeEnabledRuntime || InpRegimeAtomicCompanionSyncSeconds <= 0)
      return false;
   if(g_lastRegimeCompanionSyncedEventId == regimeEventId)
      return false;
   if(_regime_effective_delay_seconds() > 0)
      return false;

   double atomicEntry, atomicSl, tp1, tp2, tp3, tp4, tp5;
   int atomicIndex;
   string atomicTrend;
   bool atomicReady = _find_atomic_levels_for_signal_time(direction, signalTime, atomicEntry, atomicIndex, atomicSl, tp1, tp2, tp3, tp4, tp5, atomicTrend);
   if(atomicReady)
   {
      string atomicRootEventId = StringFormat("%s|%s|%d|%I64d", Symbol(), direction, atomicIndex, (long)signalTime);
      if(atomicRootEventId != g_lastConfirmedEventId && regimeEventId != g_lastRegimeCompanionSyncedEventId)
      {
         double atomicCompanionTp = _select_direct_tp(tp1, tp2, tp3, tp4, tp5);
         double atomicGeometrySl = atomicSl;
         string atomicGeometryBuild = "atomic_indicator_sl";
         bool atomicSlOk = _atomic_effective_sl_for_mode(direction, atomicEntry, atomicSl, atomicCompanionTp, atomicGeometrySl, atomicGeometryBuild);
         string geometryReason = "";
         bool geometryOk = atomicSlOk && _atomic_signal_geometry_valid(direction, atomicEntry, atomicGeometrySl, tp1, tp2, tp3, tp4, tp5, geometryReason);
         if(geometryOk)
         {
            if(_post_atomic_bridge_event("resolved_state", direction, atomicIndex, signalTime, atomicEntry, atomicSl, tp1, tp2, tp3, tp4, tp5, atomicTrend, "regime_companion_sync"))
               g_lastResolvedPostTime = _timer_now();
            _post_atomic_bridge_event("confirmed_signal", direction, atomicIndex, signalTime, atomicEntry, atomicSl, tp1, tp2, tp3, tp4, tp5, atomicTrend, "regime_companion_sync");
            g_lastConfirmedEventId = atomicRootEventId;
            g_lastRegimeCompanionSyncedEventId = regimeEventId;
            _regime_lifecycle_audit(
               "regime_atomic_companion_synced",
               regimeEventId,
               direction,
               signalIndex,
               signalTime,
               entryPrice,
               regimeSl,
               regimeTp,
               reason,
               g_lastRegimeCompanionSyncFirstSeen,
               _timer_now(),
               InpRegimeAtomicCompanionSyncSeconds,
               (g_lastRegimeCompanionSyncFirstSeen > 0 ? (int)(_timer_now() - g_lastRegimeCompanionSyncFirstSeen) : 0),
               "atomic_idx=" + IntegerToString(atomicIndex) + " atomic_entry=" + _fmt_price(atomicEntry) + " atomic_sl=" + _fmt_price(atomicSl) + " atomic_tp=" + _fmt_price(_select_direct_tp(tp1, tp2, tp3, tp4, tp5))
            );
         }
         else
         {
            _regime_lifecycle_audit(
               "regime_atomic_companion_invalid",
               regimeEventId,
               direction,
               signalIndex,
               signalTime,
               entryPrice,
               regimeSl,
               regimeTp,
               geometryReason,
               0,
               _timer_now(),
               InpRegimeAtomicCompanionSyncSeconds,
               0,
               "atomic_idx=" + IntegerToString(atomicIndex) + " atomic_entry=" + _fmt_price(atomicEntry) + " atomic_sl=" + _fmt_price(atomicSl)
            );
         }
      }
      if(g_lastRegimeCompanionSyncEventId == regimeEventId)
      {
         g_lastRegimeCompanionSyncEventId = "";
         g_lastRegimeCompanionSyncFirstSeen = 0;
      }
      return false;
   }

   datetime nowTs = _timer_now();
   if(g_lastRegimeCompanionSyncEventId != regimeEventId)
   {
      g_lastRegimeCompanionSyncEventId = regimeEventId;
      g_lastRegimeCompanionSyncFirstSeen = nowTs;
      _regime_lifecycle_audit(
         "regime_atomic_companion_wait_started",
         regimeEventId,
         direction,
         signalIndex,
         signalTime,
         entryPrice,
         regimeSl,
         regimeTp,
         reason,
         nowTs,
         0,
         InpRegimeAtomicCompanionSyncSeconds,
         0,
         "waiting_for_atomic_objects same_bar_companion=1"
      );
      return true;
   }

   int age = (int)(nowTs - g_lastRegimeCompanionSyncFirstSeen);
   if(age < InpRegimeAtomicCompanionSyncSeconds)
      return true;

   _regime_lifecycle_audit(
      "regime_atomic_companion_wait_timeout",
      regimeEventId,
      direction,
      signalIndex,
      signalTime,
      entryPrice,
      regimeSl,
      regimeTp,
      reason,
      g_lastRegimeCompanionSyncFirstSeen,
      nowTs,
      InpRegimeAtomicCompanionSyncSeconds,
      age,
      "atomic_objects_missing_after_sync_window proceed_regime_only=1"
   );
   g_lastRegimeCompanionSyncEventId = "";
   g_lastRegimeCompanionSyncFirstSeen = 0;
   g_lastRegimeCompanionSyncedEventId = regimeEventId;
   return false;
}
double _valid_price_or_zero(double value)
{
   if(!MathIsValidNumber(value) || value == EMPTY_VALUE || value == 2147483647.0 || value <= 0.0)
      return 0.0;
   return value;
}

double _clamp_double(double value, double lo, double hi)
{
   return MathMax(lo, MathMin(hi, value));
}

void _dash_rect(string name, int x, int y, int w, int h, color bg, color border)
{
   string obj = DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, border);
}

void _dash_label(string name, int x, int y, string text, color clr, int size = 8)
{
   string obj = DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void _dash_button(string name, int x, int y, int w, int h, string text, color bg)
{
   string obj = DASH_PREFIX + name;
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
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, obj, OBJPROP_STATE, false);
}

void _dash_edit(string name, int x, int y, int w, int h, string text)
{
   string obj = DASH_PREFIX + name;
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
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void _dash_progress(string name, int x, int y, int w, int h, double pct, string text, color fill)
{
   pct = _clamp_double(pct, 0.0, 100.0);
   _dash_rect(name + "_BG", x, y, w, h, C'35,43,58', C'134,158,182');
   _dash_rect(name + "_FILL", x, y, (int)MathRound(w * pct / 100.0), h, fill, fill);
   _dash_label(name + "_TXT", x + 8, y + 4, text, clrWhite, 8);
}

void _delete_dash()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, -1, -1);
      if(StringFind(obj, DASH_PREFIX) == 0)
         ObjectDelete(0, obj);
   }
}

void _delete_regime_trade_levels()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, -1, -1);
      if(StringFind(obj, REGIME_LEVEL_PREFIX) == 0 || StringFind(obj, ATOMIC_LEVEL_PREFIX) == 0)
         ObjectDelete(0, obj);
   }
}

void _delete_atomic_trade_levels()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, -1, -1);
      if(StringFind(obj, ATOMIC_LEVEL_PREFIX) == 0)
         ObjectDelete(0, obj);
   }
}

bool _regime_level_ticket_is_active(string obj, string activeTickets)
{
   if(StringFind(obj, REGIME_LEVEL_PREFIX) != 0)
      return true;
   int start = StringLen(REGIME_LEVEL_PREFIX);
   int sep = StringFind(obj, "_", start);
   if(sep <= start)
      return false;
   string ticket = StringSubstr(obj, start, sep - start);
   return StringFind(activeTickets, "|" + ticket + "|") >= 0;
}

void _cleanup_stale_regime_trade_levels(string activeTickets)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, -1, -1);
      if(StringFind(obj, REGIME_LEVEL_PREFIX) == 0 && !_regime_level_ticket_is_active(obj, activeTickets))
         ObjectDelete(0, obj);
   }
}

bool _atomic_level_ticket_is_active(string obj, string activeTickets)
{
   if(StringFind(obj, ATOMIC_LEVEL_PREFIX) != 0)
      return true;
   int start = StringLen(ATOMIC_LEVEL_PREFIX);
   int sep = StringFind(obj, "_", start);
   if(sep <= start)
      return false;
   string ticket = StringSubstr(obj, start, sep - start);
   return StringFind(activeTickets, "|" + ticket + "|") >= 0;
}

void _cleanup_stale_atomic_trade_levels(string activeTickets)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, -1, -1);
      if(StringFind(obj, ATOMIC_LEVEL_PREFIX) == 0 && !_atomic_level_ticket_is_active(obj, activeTickets))
         ObjectDelete(0, obj);
   }
}

int _level_label_slot(string kind)
{
   string k = _lower_copy(kind);
   if(StringFind(k, "entry") >= 0) return 0;
   if(StringFind(k, "sl") >= 0) return 2;
   if(StringFind(k, "hc") >= 0 || StringFind(k, "be") >= 0) return 4;
   if(StringFind(k, "tp") >= 0) return 6;
   return 8;
}

void _draw_atomic_level_line(string key, string kind, double price, string direction, color clr, int style, int width)
{
   if(price <= 0.0 || !MathIsValidNumber(price))
      return;
   string base = ATOMIC_LEVEL_PREFIX + key + "_" + kind;
   if(ObjectFind(0, base) < 0)
      ObjectCreate(0, base, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, base, OBJPROP_PRICE1, NormalizeDouble(price, Digits));
   ObjectSetInteger(0, base, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, base, OBJPROP_STYLE, style);
   ObjectSetInteger(0, base, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, base, OBJPROP_BACK, false);
   ObjectSetInteger(0, base, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, base, OBJPROP_HIDDEN, true);

   string label = base + "_TXT";
   int secondsPerBar = MathMax(60, Period() * 60);
   int labelSlot = _level_label_slot(kind);
   datetime labelTime = Time[0] + secondsPerBar * (MathMax(1, InpAtomicRegimeTradeLevelLabelBars - 5) + labelSlot);
   if(ObjectFind(0, label) < 0)
      ObjectCreate(0, label, OBJ_TEXT, 0, labelTime, price);
   else
      ObjectMove(0, label, 0, labelTime, price);
   ObjectSetString(0, label, OBJPROP_TEXT, "Atomic " + direction + " " + kind + " " + _fmt_price(price));
   ObjectSetInteger(0, label, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, label, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, label, OBJPROP_BACK, false);
   ObjectSetInteger(0, label, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, label, OBJPROP_HIDDEN, true);
}

void _draw_atomic_trade_levels_when_regime_off()
{
   string activeTickets = "|";
   if(g_atomicModeEnabledRuntime && g_latestAtomicLevelEntry > 0.0 && g_latestAtomicLevelSl > 0.0 && g_latestAtomicLevelTp > 0.0)
   {
      activeTickets += "SIGNAL|";
      string sigDir = (g_latestAtomicLevelDirection == "SELL" ? "SELL" : "BUY");
      _draw_atomic_level_line("SIGNAL", "ENTRY_" + g_latestAtomicLevelMode, g_latestAtomicLevelEntry, sigDir, C'90,178,255', STYLE_DOT, 1);
      _draw_atomic_level_line("SIGNAL", "SL_" + g_latestAtomicLevelMode, g_latestAtomicLevelSl, sigDir, C'255,70,90', STYLE_DOT, 2);
      _draw_atomic_level_line("SIGNAL", "TP", g_latestAtomicLevelTp, sigDir, C'39,220,124', STYLE_DOT, 2);
      if(_direct_trigger_price_valid(sigDir, g_latestAtomicLevelEntry, g_latestAtomicLevelHalf))
         _draw_atomic_level_line("SIGNAL", "HC_BE", g_latestAtomicLevelHalf, sigDir, C'255,174,66', STYLE_DASH, 2);
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;
      if(_contains_ci(OrderComment(), "AtomicRegime"))
         continue;

      string key = IntegerToString(OrderTicket());
      string direction = (OrderType() == OP_BUY ? "BUY" : "SELL");
      activeTickets += key + "|";
      _draw_atomic_level_line(key, "ENTRY", OrderOpenPrice(), direction, C'90,178,255', STYLE_SOLID, 1);
      _draw_atomic_level_line(key, "SL", OrderStopLoss(), direction, C'255,70,90', STYLE_SOLID, 2);
      _draw_atomic_level_line(key, "TP", OrderTakeProfit(), direction, C'39,220,124', STYLE_SOLID, 2);
      double halfTrigger = _direct_get_half_trigger_price(OrderTicket());
      if(_direct_trigger_price_valid(direction, OrderOpenPrice(), halfTrigger))
         _draw_atomic_level_line(key, "HC_BE", halfTrigger, direction, C'255,174,66', STYLE_DASH, 2);
   }
   _cleanup_stale_atomic_trade_levels(activeTickets);
}

void _draw_regime_level_line(int ticket, string kind, double price, string direction, color clr, int style, int width)
{
   if(price <= 0.0 || !MathIsValidNumber(price))
      return;
   string base = REGIME_LEVEL_PREFIX + IntegerToString(ticket) + "_" + kind;
   if(ObjectFind(0, base) < 0)
      ObjectCreate(0, base, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, base, OBJPROP_PRICE1, NormalizeDouble(price, Digits));
   ObjectSetInteger(0, base, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, base, OBJPROP_STYLE, style);
   ObjectSetInteger(0, base, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, base, OBJPROP_BACK, false);
   ObjectSetInteger(0, base, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, base, OBJPROP_HIDDEN, true);

   string label = base + "_TXT";
   int secondsPerBar = MathMax(60, Period() * 60);
   int labelSlot = _level_label_slot(kind) + 10 + (ticket > 0 ? ((ticket % 4) * 2) : 0);
   datetime labelTime = Time[0] + secondsPerBar * (MathMax(1, InpAtomicRegimeTradeLevelLabelBars - 5) + labelSlot);
   if(ObjectFind(0, label) < 0)
      ObjectCreate(0, label, OBJ_TEXT, 0, labelTime, price);
   else
      ObjectMove(0, label, 0, labelTime, price);
   ObjectSetString(0, label, OBJPROP_TEXT, "AtomicRegime " + direction + " #" + IntegerToString(ticket) + " " + kind + " " + _fmt_price(price));
   ObjectSetInteger(0, label, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, label, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, label, OBJPROP_BACK, false);
   ObjectSetInteger(0, label, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, label, OBJPROP_HIDDEN, true);
}

void _delete_regime_level_line(int ticket, string kind)
{
   string base = REGIME_LEVEL_PREFIX + IntegerToString(ticket) + "_" + kind;
   string label = base + "_TXT";
   if(ObjectFind(0, base) >= 0)
      ObjectDelete(0, base);
   if(ObjectFind(0, label) >= 0)
      ObjectDelete(0, label);
}
void _delete_regime_historical_levels()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, -1, -1);
      if(StringFind(obj, REGIME_HIST_LEVEL_PREFIX) == 0)
         ObjectDelete(0, obj);
   }
}

void _draw_regime_historical_segment(string name, datetime t1, datetime t2, double price, color clr, int style, int width)
{
   if(price <= 0.0 || !MathIsValidNumber(price) || t1 <= 0 || t2 <= t1)
      return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
   {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t2, price);
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE1, NormalizeDouble(price, Digits));
   ObjectSetDouble(0, name, OBJPROP_PRICE2, NormalizeDouble(price, Digits));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSet(name, OBJPROP_RAY, false);
}

void _draw_regime_historical_label(string name, datetime t, double price, string text, color clr)
{
   if(price <= 0.0 || !MathIsValidNumber(price) || t <= 0)
      return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   else
      ObjectMove(0, name, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

bool _open_regime_order_levels_for_signal(string direction, datetime signalTime, datetime lineEnd, double &entry, double &sl, double &tp, double &hc)
{
   string dir = _trim(direction);
   if((dir != "BUY" && dir != "SELL") || signalTime <= 0)
      return false;
   int wantedType = (dir == "BUY" ? OP_BUY : OP_SELL);
   int bestTicket = -1;
   datetime bestOpen = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != wantedType)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;
      if(!_contains_ci(OrderComment(), "AtomicRegime"))
         continue;
      datetime openTime = OrderOpenTime();
      int secondsPerBar = MathMax(60, Period() * 60);
      datetime maxOpenTime = (lineEnd > signalTime ? lineEnd : signalTime + secondsPerBar * MathMax(1, InpAtomicRegimeHistoricalLevelBars));
      if(openTime < signalTime || openTime > maxOpenTime)
         continue;
      if(bestTicket < 0 || openTime < bestOpen)
      {
         bestTicket = OrderTicket();
         bestOpen = openTime;
      }
   }
   if(bestTicket < 0 || !OrderSelect(bestTicket, SELECT_BY_TICKET, MODE_TRADES))
      return false;
   entry = OrderOpenPrice();
   sl = OrderStopLoss();
   tp = OrderTakeProfit();
   hc = _direct_get_half_trigger_price(bestTicket);
   if(!_direct_trigger_price_valid(dir, entry, hc))
   {
      bool rebased = false;
      string reason = "";
      hc = _direct_normalize_half_trigger(dir, entry, sl, tp, hc, g_regimeDirectMt4HalfBeRRuntime, rebased, reason);
      if(!_direct_trigger_price_valid(dir, entry, hc))
         hc = 0.0;
   }
   return (entry > 0.0 && sl > 0.0 && tp > 0.0);
}
bool _regime_historical_levels_for_signal(string direction, int signalShift, datetime signalTime, double entry, double &sl, double &tp, double &hc)
{
   sl = 0.0;
   tp = 0.0;
   hc = 0.0;
   string dir = _trim(direction);
   if((dir != "BUY" && dir != "SELL") || signalShift < 0 || signalTime <= 0 || entry <= 0.0)
      return false;

   if(_regime_pip_sl_enabled())
   {
      string pipReason = "";
      if(!_regime_apply_pip_sl(dir, entry, sl, tp, pipReason))
         return false;
   }
   else if(_regime_signal_open_sl_enabled())
   {
      string sigOpenReason = "";
      if(!_regime_apply_signal_open_sl(dir, signalShift, entry, sl, tp, sigOpenReason))
         return false;
   }
   else
   {
      bool structuralApplied = false;
      if(_regime_structural_sl_enabled())
      {
         string structReason = "";
         structuralApplied = _regime_apply_structural_swing_sl(dir, signalShift, entry, sl, tp, structReason);
      }

      if(!structuralApplied)
      {
         _compute_regime_levels(dir, signalTime, entry, sl, tp);
         if(sl <= 0.0 || tp <= 0.0)
            return false;

         double atomicEntry = 0.0;
         double atomicSl = 0.0;
         double tp1 = 0.0, tp2 = 0.0, tp3 = 0.0, tp4 = 0.0, tp5 = 0.0;
         int atomicIndex = -1;
         string atomicTrend = "";
         if(_find_atomic_levels_for_signal_time(dir, signalTime, atomicEntry, atomicIndex, atomicSl, tp1, tp2, tp3, tp4, tp5, atomicTrend))
         {
            string clampReason = "";
            _regime_apply_atomic_sl_clamp(dir, entry, atomicEntry, atomicSl, sl, tp, clampReason);
         }
      }

      string widenReason = "";
      _regime_apply_sl_widen(dir, entry, sl, tp, widenReason);
      string scaleReason = "";
      _regime_apply_final_risk_scale(dir, entry, sl, tp, scaleReason);
   }

   bool halfRebased = false;
   string halfReason = "";
   hc = _direct_normalize_half_trigger(dir, entry, sl, tp, 0.0, g_regimeDirectMt4HalfBeRRuntime, halfRebased, halfReason);
   if(!_direct_trigger_price_valid(dir, entry, hc))
      hc = 0.0;
   return (sl > 0.0 && tp > 0.0);
}

void _draw_atomic_regime_historical_levels()
{
   if(!InpShowAtomicRegimeTradeLevels || !g_atomicRegimeModeEnabledRuntime)
   {
      _delete_regime_historical_levels();
      g_regimeHistoryLevelsHash = "";
      return;
   }
   if(Bars < 20 || !InpRegimeUseTrendSignalBuffers)
   {
      _delete_regime_historical_levels();
      g_regimeHistoryLevelsHash = "";
      return;
   }

   int baseShift = MathMax(1, _regime_base_shift() + 1);
   int maxLookback = MathMin(Bars - 1, MathMax(baseShift, InpRegimeBufferLookbackBars));
   int maxSignals = MathMax(1, InpAtomicRegimeHistoricalMaxSignals);
   int segmentBars = MathMax(1, InpAtomicRegimeHistoricalLevelBars);
   string hash = StringFormat("%I64d|%d|%d|%.2f|%.2f|%.2f|%d|%.2f|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.2f|%.2f|%d|%.2f|%.2f|%d|%d",
      (long)Time[baseShift], maxLookback, maxSignals,
      g_regimeRRRuntime, g_regimeDirectMt4HalfBeRRuntime, g_regimeFinalRiskScalePctRuntime,
      g_regimePipSlModeRuntime ? 1 : 0, g_regimePipSlPipsRuntime,
      g_regimeSignalOpenSlModeRuntime ? 1 : 0,
      InpRegimeUpTrendSignalBuffer, InpRegimeDnTrendSignalBuffer, InpRegimeUseTrendSignalBuffers ? 1 : 0, segmentBars,
      g_regimeStructuralSwingSlModeRuntime ? 1 : 0, InpRegimeSwingLookbackBars, InpRegimeSwingLeftBars, InpRegimeSwingRightBars,
      InpRegimeSwingMinProminenceAtr, InpRegimeSwingMinDepartureAtr, InpRegimeSwingMaxAgeBars, InpRegimeSwingMaxRiskAtr, InpRegimeSwingBufferAtr,
      InpRegimeSwingPreferStrongest ? 1 : 0, InpRegimeSwingFallbackToExtreme ? 1 : 0);
   if(hash == g_regimeHistoryLevelsHash)
      return;
   g_regimeHistoryLevelsHash = hash;
   _delete_regime_historical_levels();

   int drawn = 0;
   string lastKey = "";
   int secondsPerBar = MathMax(60, Period() * 60);
   for(int sh = maxLookback; sh >= baseShift && drawn < maxSignals; sh--)
   {
      double upValue = _regime_buffer_value(MathMax(0, InpRegimeUpTrendSignalBuffer), sh);
      double dnValue = _regime_buffer_value(MathMax(0, InpRegimeDnTrendSignalBuffer), sh);
      bool hasUp = _valid_atomic_buffer_price(upValue);
      bool hasDn = _valid_atomic_buffer_price(dnValue);
      if(!hasUp && !hasDn)
         continue;

      string dir = "";
      if(hasUp && !hasDn)
         dir = "BUY";
      else if(hasDn && !hasUp)
         dir = "SELL";
      else
      {
         double closePx = Close[sh];
         dir = (MathAbs(closePx - upValue) <= MathAbs(closePx - dnValue) ? "BUY" : "SELL");
      }
      datetime signalTime = Time[sh];
      string eventKey = dir + "|" + IntegerToString((int)signalTime);
      if(eventKey == lastKey)
         continue;
      lastKey = eventKey;

      double entry = NormalizeDouble(Close[sh], Digits);
      double sl = 0.0, tp = 0.0, hc = 0.0;
      if(!_regime_historical_levels_for_signal(dir, sh, signalTime, entry, sl, tp, hc))
         continue;
      string drawDir = dir;
      string histInvertDetail = "";
      _atomic_apply_invert_to_geometry_for_levels(dir, entry, sl, tp, hc, drawDir, histInvertDetail);
      datetime lineEnd = signalTime + secondsPerBar * segmentBars;
      double liveEntry = entry, liveSl = sl, liveTp = tp, liveHc = hc;
      if(_open_regime_order_levels_for_signal(drawDir, signalTime, lineEnd, liveEntry, liveSl, liveTp, liveHc))
         continue; // Active trades are represented by long live HLINEs, not short historical segments.
      string base = REGIME_HIST_LEVEL_PREFIX + IntegerToString((int)signalTime) + "_" + drawDir + "_";
      _draw_regime_historical_segment(base + "ENTRY", signalTime, lineEnd, entry, C'230,230,230', STYLE_SOLID, 1);
      _draw_regime_historical_segment(base + "SL", signalTime, lineEnd, sl, C'255,70,90', STYLE_SOLID, 2);
      _draw_regime_historical_segment(base + "TP", signalTime, lineEnd, tp, C'39,220,124', STYLE_SOLID, 2);
      _draw_regime_historical_label(base + "LBL", lineEnd, entry, "Reg " + drawDir + " E " + _fmt_price(entry) + " SL " + _fmt_price(sl) + " TP " + _fmt_price(tp) + (hc > 0.0 ? " HC " + _fmt_price(hc) : ""), C'184,196,210');
      if(hc > 0.0)
         _draw_regime_historical_segment(base + "HCBE", signalTime, lineEnd, hc, C'255,174,66', STYLE_DOT, 2);
      drawn++;
   }
}
bool _has_open_regime_trade_for_chart()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;
      if(_contains_ci(OrderComment(), "AtomicRegime"))
         return true;
   }
   return false;
}

void _draw_atomic_regime_trade_levels()
{
   if(!InpShowAtomicRegimeTradeLevels)
   {
      _delete_regime_trade_levels();
      _delete_regime_historical_levels();
      g_regimeHistoryLevelsHash = "";
      return;
   }
   _delete_regime_trade_levels(); // Rebuild live HLINE set from current open positions only; prevents stale active direction lines.
   _draw_atomic_trade_levels_when_regime_off();
   string activeTickets = "|";
   bool hasOpenRegimeTrade = _has_open_regime_trade_for_chart();
   if(!g_atomicRegimeModeEnabledRuntime)
   {
      _delete_regime_historical_levels();
      g_regimeHistoryLevelsHash = "";
      _cleanup_stale_regime_trade_levels(activeTickets);
      return;
   }
   _draw_atomic_regime_historical_levels();
      if(!hasOpenRegimeTrade && InpShowLatestAtomicRegimeSignalLevels && g_latestRegimeLevelEntry > 0.0 && g_latestRegimeLevelSl > 0.0 && g_latestRegimeLevelTp > 0.0)
      {
         activeTickets += "0|";
         string sigDir = (g_latestRegimeLevelDirection == "SELL" ? "SELL" : "BUY");
         _draw_regime_level_line(0, "SIGNAL_ENTRY", g_latestRegimeLevelEntry, sigDir, C'90,178,255', STYLE_DOT, 1);
         _draw_regime_level_line(0, "SIGNAL_SL", g_latestRegimeLevelSl, sigDir, C'255,70,90', STYLE_DOT, 2);
         _draw_regime_level_line(0, "SIGNAL_TP", g_latestRegimeLevelTp, sigDir, C'39,220,124', STYLE_DOT, 2);
         bool sigHalfRebased = false;
         string sigHalfReason = "";
         double sigHalfTrigger = g_latestRegimeLevelHalf;
         if(!_direct_trigger_price_valid(sigDir, g_latestRegimeLevelEntry, sigHalfTrigger))
         {
            sigHalfTrigger = _direct_normalize_half_trigger(
               sigDir,
               g_latestRegimeLevelEntry,
               g_latestRegimeLevelSl,
               g_latestRegimeLevelTp,
               0.0,
               g_regimeDirectMt4HalfBeRRuntime,
               sigHalfRebased,
               sigHalfReason
            );
         }
         if(_direct_trigger_price_valid(sigDir, g_latestRegimeLevelEntry, sigHalfTrigger))
            _draw_regime_level_line(0, "SIGNAL_HC_BE", sigHalfTrigger, sigDir, C'255,174,66', STYLE_DASH, 2);
         else
            _delete_regime_level_line(0, "SIGNAL_HC_BE");
      }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(), OrderComment(), true))
         continue;
      if(!_contains_ci(OrderComment(), "AtomicRegime"))
         continue;

      int ticket = OrderTicket();
      string direction = (OrderType() == OP_BUY ? "BUY" : "SELL");
      activeTickets += IntegerToString(ticket) + "|";
      _draw_regime_level_line(ticket, "ENTRY", OrderOpenPrice(), direction, C'90,178,255', STYLE_SOLID, 1);
      _draw_regime_level_line(ticket, "SL", OrderStopLoss(), direction, C'255,70,90', STYLE_SOLID, 2);
      _draw_regime_level_line(ticket, "TP", OrderTakeProfit(), direction, C'39,220,124', STYLE_SOLID, 2);

      double halfTrigger = _direct_get_half_trigger_price(ticket);
      bool triggerRebased = false;
      string triggerReason = "";
      halfTrigger = _direct_normalize_half_trigger(
         direction,
         OrderOpenPrice(),
         OrderStopLoss(),
         OrderTakeProfit(),
         halfTrigger,
         g_regimeDirectMt4HalfBeRRuntime,
         triggerRebased,
         triggerReason
      );
      if(_direct_trigger_price_valid(direction, OrderOpenPrice(), halfTrigger))
      {
         if(triggerRebased)
            _direct_set_half_trigger_price(ticket, halfTrigger);
         _draw_regime_level_line(ticket, "HC_BE", halfTrigger, direction, C'255,174,66', STYLE_DASH, 2);
      }
      else
      {
         _delete_regime_level_line(ticket, "HC_BE");
         static datetime lastRegimeHcbeSkipLog = 0;
         if(g_regimeDirectMt4HalfBeRRuntime > 0.0 && TimeCurrent() - lastRegimeHcbeSkipLog >= 30)
         {
            lastRegimeHcbeSkipLog = TimeCurrent();
            Print("AtomicBridge Regime HC/BE level skipped ticket=", ticket,
                  " reason=", triggerReason,
                  " halfR=", DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2),
                  " entry=", _fmt_price(OrderOpenPrice()),
                  " sl=", _fmt_price(OrderStopLoss()),
                  " tp=", _fmt_price(OrderTakeProfit()));
         }
      }
   }
   _cleanup_stale_regime_trade_levels(activeTickets);
}

void _draw_collapsed_dashboard()
{
   _dash_rect("DOCK_BG", 10, 18, 940, 34, C'54,62,75', C'134,158,182');
   _dash_rect("DOCK_STRIPE", 18, 25, 924, 4, C'90,178,255', C'90,178,255');
   _dash_label("DOCK_TEXT", 28, 33, "ATOMIC BRIDGE STARSHIP COCKPIT DOCKED", C'216,222,230', 9);
   _dash_button("BTN_DASH_EXPAND", 438, 58, 110, 24, "v EXPAND", C'38,101,176');
   _dash_label("DOCK_HINT", 560, 62, Symbol() + " " + _tf_to_string(Period()) + " | chart view clear", C'184,196,210', 8);
}

void _set_dashboard_collapsed(bool collapsed)
{
   g_dashboardCollapsed = collapsed;
   _delete_dash();
   if(g_dashboardCollapsed)
      _draw_collapsed_dashboard();
   else
      _draw_dashboard();
   ChartRedraw(0);
}

bool _direct_open_progress(double &pct, string &label, color &fill)
{
   pct = 0.0;
   label = "DIRECT MT4 POSITION: none";
   fill = C'88,96,112';
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      double entry = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      int dir = OrderType() == OP_BUY ? 1 : -1;
      RefreshRates();
      double px = dir > 0 ? Bid : Ask;
      if(sl <= 0.0 || tp <= 0.0 || MathAbs(tp - sl) <= 0.0)
         continue;
      if(dir > 0)
         pct = ((px - sl) / (tp - sl)) * 100.0;
      else
         pct = ((sl - px) / (sl - tp)) * 100.0;
      pct = _clamp_double(pct, 0.0, 100.0);
      fill = dir > 0 ? C'31,141,255' : C'221,55,78';
      label = StringFormat("%s ticket=%d Px=%s SL=%s TP=%s %.0f%%",
                           (dir > 0 ? "BUY" : "SELL"),
                           OrderTicket(),
                           _fmt_price(px),
                           _fmt_price(sl),
                           _fmt_price(tp),
                           pct);
      return true;
   }
   return false;
}

void _manage_direct_mt4_positions()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || !_direct_magic_owned(OrderMagicNumber()))
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      double entry = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      if(sl <= 0.0 || tp <= 0.0)
         continue;
      int orderType = OrderType();
      int dir = orderType == OP_BUY ? 1 : -1;
      int ticket = OrderTicket();
      if(!_direct_order_owned_by_instance(ticket, OrderComment(), true))
         continue;
      string direction = (dir > 0 ? "BUY" : "SELL");
      string source = OrderComment();
      double initialRisk = _direct_state_get("IRISK", ticket);
      if(initialRisk <= Point)
      {
         initialRisk = MathAbs(entry - sl);
         if(initialRisk > Point)
            _direct_state_set("IRISK", ticket, initialRisk);
      }
      if(initialRisk <= Point)
         continue;
      RefreshRates();
      double px = dir > 0 ? Bid : Ask;
      double currentR = (dir > 0) ? ((px - entry) / initialRisk) : ((entry - px) / initialRisk);
      double maxR = _direct_state_get("MAXR", ticket);
      if(currentR > maxR)
      {
         maxR = currentR;
         _direct_state_set("MAXR", ticket, maxR);
      }
      _direct_update_excursion(ticket, px, currentR);
      bool isRegime = _contains_ci(source, "AtomicRegime");
      double storedTrigger = _direct_get_half_trigger_price(ticket);
      if(!isRegime && g_directMt4HalfBeTpIndexRuntime >= g_directMt4TpIndexRuntime && storedTrigger <= 0.0)
         continue;
      double halfR = (isRegime ? g_regimeDirectMt4HalfBeRRuntime : g_directMt4HalfBeRRuntime);
      bool triggerRebased = false;
      string triggerGeometry = "";
      double triggerPrice = _direct_normalize_half_trigger(
         direction, entry, sl, tp, storedTrigger, halfR,
         triggerRebased, triggerGeometry
      );
      string triggerLabel = "r" + DoubleToString(halfR, 2);
      if(_direct_trigger_price_valid(direction, entry, triggerPrice))
      {
         triggerLabel = isRegime ? ("stored_r" + DoubleToString(halfR, 2)) : ("stored_tp" + IntegerToString(MathMax(1, MathMin(5, g_directMt4HalfBeTpIndexRuntime))));
      }
      if(triggerRebased && triggerPrice > 0.0)
      {
         _direct_set_half_trigger_price(ticket, triggerPrice);
         triggerLabel = "fill_rebased";
         if(!_direct_audit_marked("HTFIX", ticket))
         {
            _direct_audit_mark("HTFIX", ticket);
            _direct_audit_write("direct_halfbe_fill_geometry_repaired", source, "", ticket, direction, OrderLots(), entry, sl, tp, triggerGeometry, 0.0, "old_trigger=" + _fmt_price(storedTrigger) + " new_trigger=" + _fmt_price(triggerPrice));
         }
      }
      if(!_direct_trigger_price_valid(direction, entry, triggerPrice))
         continue;
      bool reached = currentR > 0.0 && ((dir > 0) ? (px >= triggerPrice) : (px <= triggerPrice));
      bool alreadyBe = (dir > 0) ? (sl >= entry - Point) : (sl <= entry + Point);
      if(!reached)
         continue;
      _direct_state_set("SEEN", ticket, TimeCurrent());
      string thresholdReason = "trigger=" + triggerLabel + " trigger_price=" + _fmt_price(triggerPrice) + " halfR=" + DoubleToString(halfR, 2) + " initial_risk=" + DoubleToString(initialRisk, Digits) + " current_r=" + DoubleToString(currentR, 3) + " max_r=" + DoubleToString(maxR, 3);
      if(!_direct_audit_marked("TP1", ticket))
      {
         _direct_audit_mark("TP1", ticket);
         _direct_audit_write("direct_halfbe_trigger_seen", source, "", ticket, direction, OrderLots(), px, sl, tp, thresholdReason, 0.0, "");
      }

      // Protect the surviving position before partial close. Some MT4 brokers
      // replace the ticket after a partial close.
      if(!alreadyBe)
      {
         if(!_direct_be_price_legal(orderType, entry))
         {
            if(_direct_failure_log_due("BEWAITLOG", ticket, 5))
               _direct_audit_write("direct_sl_to_be_waiting_broker_distance", source, "", ticket, direction, OrderLots(), px, sl, tp, thresholdReason, 0.0, "stop_or_freeze_level_not_clear");
            continue;
         }
         ResetLastError();
         if(OrderModify(ticket, entry, NormalizeDouble(entry, Digits), tp, 0, clrDodgerBlue))
         {
            _direct_audit_mark("BE", ticket);
            sl = NormalizeDouble(entry, Digits);
            alreadyBe = true;
            _direct_audit_write("direct_sl_to_be_sent", source, "", ticket, direction, OrderLots(), px, sl, tp, thresholdReason, 0.0, "before_half_close");
            Print("AtomicBridge direct_mt4 SL moved to BE before half-close ticket=", ticket, " trigger=", triggerLabel);
         }
         else
         {
            int beErr = GetLastError();
            if(_direct_failure_log_due("BEFAILLOG", ticket, 5))
            {
               _direct_audit_write("direct_sl_to_be_failed", source, "", ticket, direction, OrderLots(), px, sl, tp, "err=" + IntegerToString(beErr) + " " + thresholdReason, 0.0, "half_close_deferred");
               Print("AtomicBridge direct_mt4 SL->BE failed; half-close deferred ticket=", ticket, " err=", beErr);
            }
            continue;
         }
      }
      else if(!_direct_audit_marked("BE", ticket))
      {
         _direct_audit_mark("BE", ticket);
         _direct_audit_write("direct_sl_already_at_be", source, "", ticket, direction, OrderLots(), px, sl, tp, thresholdReason, 0.0, "");
      }

      if(!_direct_audit_marked("HALF", ticket))
      {
         double currentLots = OrderLots();
         double minLot = MarketInfo(Symbol(), MODE_MINLOT);
         if(minLot <= 0.0)
            minLot = 0.01;
         double closeLot = _direct_lot_down(currentLots * 0.5);
         if(closeLot > 0.0 && currentLots - closeLot >= minLot - 0.0000001)
         {
            double closePx = (dir > 0) ? Bid : Ask;
            double expectedLots = _direct_lot_down(currentLots - closeLot);
            ResetLastError();
            if(OrderClose(ticket, closeLot, closePx, InpDirectMt4Slippage, clrDeepSkyBlue))
            {
               _direct_audit_mark("HALF", ticket);
               _direct_audit_write("direct_half_close_sent", source, "", ticket, direction, closeLot, closePx, sl, tp, thresholdReason, 0.0, "be_confirmed_before_half=1");
               int remainderTicket = _direct_find_remainder_ticket(ticket, orderType, entry, source, expectedLots);
               if(remainderTicket > 0)
               {
                  _direct_transfer_ticket_state(ticket, remainderTicket);
                  if(remainderTicket != ticket)
                     _direct_audit_write("direct_partial_remainder_linked", source, "", remainderTicket, direction, expectedLots, closePx, entry, tp, "old_ticket=" + IntegerToString(ticket), 0.0, "state_transferred");
               }
               else
               {
                  _direct_audit_write("direct_partial_remainder_not_found", source, "", ticket, direction, expectedLots, closePx, entry, tp, thresholdReason, 0.0, "verify_terminal_position");
               }
               _direct_audit_write("direct_halfbe_complete", source, "", (remainderTicket > 0 ? remainderTicket : ticket), direction, expectedLots, closePx, entry, tp, thresholdReason, 0.0, "be=1 half=1 original_ticket=" + IntegerToString(ticket));
            }
            else
            {
               int halfErr = GetLastError();
               if(halfErr == 131)
               {
                  double brokerMinLot = MarketInfo(Symbol(), MODE_MINLOT);
                  double brokerLotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
                  _direct_audit_mark("HALF", ticket);
                  _direct_audit_write(
                     "direct_half_close_skipped_invalid_volume",
                     source, "", ticket, direction, closeLot, closePx, sl, tp,
                     "err=131 " + thresholdReason,
                     0.0,
                     "be_already_confirmed=1 current_lots=" + DoubleToString(currentLots, 2)
                     + " requested_close=" + DoubleToString(closeLot, 2)
                     + " reported_min_lot=" + DoubleToString(brokerMinLot, 2)
                     + " reported_lot_step=" + DoubleToString(brokerLotStep, 2)
                  );
                  Print("AtomicBridge direct_mt4 half_close skipped: broker rejected split volume ticket=", ticket, " close_lot=", DoubleToString(closeLot, 2));
                  continue;
               }
               if(_direct_failure_log_due("HALFFAILLOG", ticket, 5))
               {
                  _direct_audit_write("direct_half_close_failed", source, "", ticket, direction, closeLot, closePx, sl, tp, "err=" + IntegerToString(halfErr) + " " + thresholdReason, 0.0, "be_already_confirmed=1");
                  Print("AtomicBridge direct_mt4 half_close failed ticket=", ticket, " err=", halfErr);
               }
            }
         }
         else
         {
            _direct_audit_mark("HALF", ticket);
            _direct_audit_write("direct_half_close_skipped_min_lot", source, "", ticket, direction, currentLots, px, sl, tp, "min_lot_or_step " + thresholdReason, 0.0, "");
         }
      }
   }
   _direct_position_probe_scan();
   _direct_history_audit_scan();
}

void _draw_dashboard()
{
   if(!InpShowDashboard)
      return;
   if(g_dashboardCollapsed)
   {
      _draw_collapsed_dashboard();
      return;
   }
   _dash_rect("BG", 10, 18, 1010, 540, C'24,30,42', C'134,158,182');
   _dash_rect("HULL", 17, 25, 996, 526, C'40,48,62', C'90,178,255');
   _dash_rect("DOCK_STRIPE", 18, 31, 994, 4, C'90,178,255', C'90,178,255');
   _dash_rect("CORE", 26, 56, 664, 482, C'18,24,36', C'65,116,172');
   _dash_rect("ACTION_PANEL", 704, 56, 286, 482, C'31,38,52', C'221,55,78');
   _dash_button("BTN_DASH_COLLAPSE", 966, 30, 24, 22, "^", C'90,178,255');
   _dash_label("TITLE", 34, 32, "AI STARSHIP ATOMIC BRIDGE", C'216,222,230', 12);
   _dash_label("SUB", 356, 34, Symbol() + " " + _tf_to_string(Period()) + " | " + ATOMIC_BRIDGE_BUILD, C'90,178,255', 8);
   _dash_label("ACTIONS", 724, 64, "AIRLOCK / CONFIG", C'216,222,230', 9);
   _dash_button("BTN_DIRECT", 718, 88, 118, 24, g_directMt4EnabledRuntime ? "DIRECT ON" : "DIRECT OFF", g_directMt4EnabledRuntime ? C'32,150,96' : C'178,37,57');
   _dash_button("BTN_POST", 844, 88, 118, 24, g_proTradePostEnabledRuntime ? "POST ON" : "POST OFF", g_proTradePostEnabledRuntime ? C'32,150,96' : C'178,37,57');
   _dash_button("BTN_PRIORITY", 718, 116, 118, 24, g_directMt4PriorityDirectFirst ? "DIRECT FIRST" : "POST FIRST", C'38,101,176');
   _dash_button("BTN_HALFBE", 844, 116, 118, 24, "ATOMIC HC TP" + IntegerToString(g_directMt4HalfBeTpIndexRuntime), C'34,136,160');
   _dash_button("BTN_ATOMIC_MODE", 718, 144, 118, 24, g_atomicModeEnabledRuntime ? "[x] ATOMIC" : "[ ] ATOMIC", g_atomicModeEnabledRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_REGIME_MODE", 844, 144, 118, 24, g_atomicRegimeModeEnabledRuntime ? "[x] REGIME" : "[ ] REGIME", g_atomicRegimeModeEnabledRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_REGIME_SHIFT", 718, 172, 118, 24, g_regimeUseClosedBarRuntime ? "REGIME SH1" : "REGIME SH0", g_regimeUseClosedBarRuntime ? C'34,136,160' : C'178,37,57');
   _dash_button("BTN_APPLY", 844, 172, 118, 24, "APPLY CFG", C'38,101,176');
   _dash_button("BTN_REGIME_DELAY_MODE", 718, 200, 244, 24, g_regimeDelayValidationRuntime ? "REG DELAY VALIDATE" : "REG DIRECT", g_regimeDelayValidationRuntime ? C'221,145,45' : C'32,150,96');
   _dash_button("BTN_FTMO", 718, 228, 118, 24, g_ftmoModeRuntime ? "FTMO ON" : "FTMO OFF", g_ftmoModeRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_RISKLOT", 844, 228, 118, 24, g_riskLotOnlyRuntime ? "RISKLOT ON" : "RISKLOT OFF", g_riskLotOnlyRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_AUDIT", 718, 256, 118, 24, g_auditEnabledRuntime ? "AUDIT ON" : "AUDIT OFF", g_auditEnabledRuntime ? C'34,136,160' : C'88,96,112');
   _dash_button("BTN_REGIME_PREWIN", 844, 256, 118, 24, g_regimeOpenPreWindowSignalRuntime ? "REG WIN ON" : "REG WIN OFF", g_regimeOpenPreWindowSignalRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_ATOMIC_TP", 718, 284, 118, 24, "ATOMIC TP" + IntegerToString(g_directMt4TpIndexRuntime), C'34,136,160');
   _dash_button("BTN_ATOMIC_SL_MODE", 844, 284, 118, 24, g_atomicDirectRiskGeometryRuntime ? "AT SL R-GEOM" : "AT SL INDIC", g_atomicDirectRiskGeometryRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_ATOMIC_RR", 718, 312, 244, 24, "ATOMIC TARGET " + DoubleToString(g_atomicDirectTargetRRuntime, 1) + "R", C'38,101,176');
   _dash_label("L_RISK_PCT", 724, 346, "Risk %", C'184,196,210', 8);
   _dash_edit("EDIT_RISK_PCT", 778, 340, 56, 22, DoubleToString(_account_risk_per_trade_pct(), 2));
   bool riskAppliedPulse = (g_riskApplyFeedbackUntilMs > 0 && GetTickCount() < g_riskApplyFeedbackUntilMs);
   _dash_button("BTN_RISK_APPLY", 844, 340, 118, 24, riskAppliedPulse ? "APPLIED" : "APPLY RISK", riskAppliedPulse ? C'32,150,96' : C'38,101,176');
   _dash_label("L_REG_PIP_SL", 724, 374, "Reg pip SL", C'184,196,210', 8);
   _dash_edit("EDIT_REGIME_PIP_SL", 800, 368, 50, 22, DoubleToString(g_regimePipSlPipsRuntime, 1));
   _dash_button("BTN_REGIME_PIP_SL", 858, 368, 104, 24, g_regimePipSlModeRuntime ? "PIP SL ON" : "PIP SL OFF", g_regimePipSlModeRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_REGIME_STRUCT_SL", 718, 396, 118, 24, g_regimeStructuralSwingSlModeRuntime ? "SWING SL ON" : "SWING SL OFF", g_regimeStructuralSwingSlModeRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_REGIME_SIGOPEN_SL", 844, 396, 118, 24, g_regimeSignalOpenSlModeRuntime ? "SIGOPEN ON" : "SIGOPEN OFF", g_regimeSignalOpenSlModeRuntime ? C'32,150,96' : C'88,96,112');
   _dash_label("L_DAILY_PROFIT", 724, 430, "Day +", C'184,196,210', 8);
   _dash_edit("EDIT_DAILY_PROFIT", 768, 424, 42, 22, DoubleToString(g_directMt4DailyProfitTargetRuntime, 0));
   _dash_label("L_DAILY_LOSS", 816, 430, "Day -", C'184,196,210', 8);
   _dash_edit("EDIT_DAILY_LOSS", 858, 424, 42, 22, DoubleToString(g_directMt4DailyLossTargetRuntime, 0));
   _dash_button("BTN_DAILY_PROFIT", 908, 424, 54, 24, "APPLY", C'38,101,176');
   _dash_button("BTN_ATOMIC_INVERT", 718, 456, 78, 24, g_atomicInvertTradeModeRuntime ? "INV ON" : "INV OFF", g_atomicInvertTradeModeRuntime ? C'178,37,57' : C'88,96,112');
   _dash_button("BTN_ATOMIC_INV_TP", 800, 456, 78, 24, g_atomicInvertTradeModeRuntime ? _atomic_invert_target_text() : "INV TP--", g_atomicInvertTradeModeRuntime ? C'38,101,176' : C'88,96,112');
   _dash_button("BTN_ATOMIC_INV_HC", 884, 456, 78, 24, g_atomicInvertTradeModeRuntime ? (g_atomicInvertHcBeProgressPctRuntime > 0 ? "IHC " + IntegerToString(g_atomicInvertHcBeProgressPctRuntime) + "%" : "IHC OFF") : "IHC --", g_atomicInvertTradeModeRuntime ? C'34,136,160' : C'88,96,112');
   if(g_gannFollowModeRuntime && (TimeGMT() - g_gannFollowLastReadGmt >= 2 || g_gannFollowLastDirection == ""))
   {
      string dashGd, dashDet;
      datetime dashGt = 0;
      if(_gann_follow_read_state(dashGd, dashGt, dashDet))
      {
         g_gannFollowLastDirection = dashGd;
         g_gannFollowLastSignalTime = dashGt;
      }
      else
         g_gannFollowLastDirection = "NONE";
      g_gannFollowLastReadGmt = TimeGMT();
      g_gannFollowLastDetail = dashDet;
   }
   _dash_button("BTN_GANN_FOLLOW", 718, 492, 78, 24, g_gannFollowModeRuntime ? "GANN ON" : "GANN OFF", g_gannFollowModeRuntime ? C'32,150,96' : C'88,96,112');
   _dash_button("BTN_GANN_TF", 802, 492, 62, 24, "TF " + _gann_follow_tf_text(), C'38,101,176');
   _dash_button("BTN_MT5_PUB", 870, 492, 92, 24, g_fileBridgeMt5EnabledRuntime ? "MT5 PUB ON" : "MT5 PUB OFF", g_fileBridgeMt5EnabledRuntime ? C'32,150,96' : C'88,96,112');
   color gannColor = (g_gannFollowLastDirection == "BUY" ? C'32,180,96' : (g_gannFollowLastDirection == "SELL" ? C'235,70,86' : C'184,196,210'));
   _dash_label("GANN_STATE", 724, 520, "GANN " + _gann_follow_tf_text() + " " + (g_gannFollowLastDirection == "" ? "NONE" : g_gannFollowLastDirection), gannColor, 10);
   _dash_label("L_LOT", 38, 66, "Lot", C'184,196,210', 8);
   _dash_edit("EDIT_LOT", 70, 62, 70, 22, DoubleToString(g_directMt4LotRuntime, 2));
   _dash_label("L_SPREAD", 158, 66, "Max spread pts", C'184,196,210', 8);
   _dash_edit("EDIT_SPREAD", 260, 62, 70, 22, IntegerToString(g_directMt4MaxSpreadRuntime));
   _dash_label("L_SPREAD_SL", 342, 66, "Max spr/SL %", C'184,196,210', 8);
   _dash_edit("EDIT_SPREAD_SL_PCT", 438, 62, 44, 22, DoubleToString(g_directMt4MaxSpreadToSlPctRuntime, 0));
   _dash_label("L_RR", 494, 66, "Regime TP R", C'184,196,210', 8);
   _dash_edit("EDIT_RR", 572, 62, 42, 22, DoubleToString(g_regimeRRRuntime, 1));
   _dash_label("L_REG_HB", 38, 110, "Regime HC/BE R", C'184,196,210', 8);
   _dash_edit("EDIT_REGIME_HALFBE", 146, 106, 48, 22, DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1));
   _dash_label("L_ATOMIC_TP", 38, 88, "Atomic HC/BE TP leg", C'184,196,210', 8);
   _dash_edit("EDIT_ATOMIC_HALFBE_TP", 172, 84, 42, 22, IntegerToString(g_directMt4HalfBeTpIndexRuntime));
   _dash_label("L_ATOMIC_FALLBACK", 226, 88, "Atomic fallback HC/BE R", C'184,196,210', 8);
   _dash_edit("EDIT_HALFBE", 382, 84, 48, 22, DoubleToString(g_directMt4HalfBeRRuntime, 1));
   _dash_label("L_REG_DELAY", 446, 88, "Reg delay sec", C'184,196,210', 8);
   _dash_edit("EDIT_REGIME_DELAY", 538, 84, 56, 22, IntegerToString(g_regimeConfirmDelaySecondsRuntime));
   _dash_label("L_REG_SCALE", 608, 88, "Reg SL %", C'184,196,210', 8);
   _dash_edit("EDIT_REGIME_SCALE", 650, 84, 34, 22, DoubleToString(g_regimeFinalRiskScalePctRuntime, 0));
   _dash_label("L_ALLOWED", 38, 266, "Allowed GMT", C'184,196,210', 8);
   _dash_edit("EDIT_ALLOWED", 126, 262, 180, 22, g_directMt4AllowedWindowsRuntime);
   _dash_label("L_NOTRADE", 324, 266, "Block GMT", C'184,196,210', 8);
   _dash_edit("EDIT_NOTRADE", 396, 262, 164, 22, g_directMt4NoTradeWindowsRuntime);
   _dash_label("L_UTC_EVENT", 574, 266, "UTC Block", C'184,196,210', 8);
   _dash_edit("EDIT_UTC_EVENT", 644, 262, 64, 22, g_directMt4UtcEventBlockTimesRuntime);
   _dash_button("BTN_UTC_EVENT_APPLY", 716, 262, 82, 24, "APPLY E", C'38,101,176');
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   RefreshRates();
   _dash_label("STATE", 38, 132, StringFormat("Live BID %s / ASK %s | %s | %s",
              _fmt_price(Bid), _fmt_price(Ask), _direct_spread_status(spread), _direct_trade_window_status()), clrWhite, 8);
   _dash_label("MODES", 38, 154, StringFormat("Modes: Atomic=%s | Regime=%s | RegExec=%s | ProTrade=%s | Risk=%s %.2f%%/%.2f%% | Audit=%s | Shift=%s",
              (g_atomicModeEnabledRuntime ? "ON" : "OFF"), (g_atomicRegimeModeEnabledRuntime ? "ON" : "OFF"),
              (g_regimeDelayValidationRuntime ? "DELAY" : "DIRECT"), (g_proTradePostEnabledRuntime ? "ON" : "OFF"),
              (_account_risk_enabled_runtime() ? (g_ftmoModeRuntime ? "FTMO" : "RISKLOT") : "OFF"), _account_risk_per_trade_pct(), InpAccountRiskMaxPortfolioPct,
              (g_auditEnabledRuntime ? "ON" : "OFF"), (g_regimeUseClosedBarRuntime ? "1" : "0")), C'90,178,255', 8);
   _dash_label("REGWIN", 38, 248, "AtomicRegime pre-window execution: " + (g_regimeOpenPreWindowSignalRuntime ? "ON" : "OFF") + " | pending=" + (g_pendingRegimeWindowEventId == "" ? "none" : g_pendingRegimeWindowDirection + " " + _fmt_time(g_pendingRegimeWindowSignalTime)), C'184,196,210', 8);
   string dailyGuardReason = "";
   string dailyGuardDetail = "";
   bool dailyGuardBlocked = _direct_daily_profit_loss_guard_reached(dailyGuardReason, dailyGuardDetail);
   _dash_label("DAYPROFIT", 38, 282, "Daily guard: " + dailyGuardDetail + (dailyGuardBlocked ? (" | BLOCKED " + dailyGuardReason) : ""), dailyGuardBlocked ? C'255,90,110' : C'184,196,210', 8);
   _dash_label("LAST_A", 38, 174, "Last Atomic: " + (g_lastObservedSignalDirection == "" ? "NONE" : g_lastObservedSignalDirection) + " | " + _fmt_time(g_lastObservedSignalTime), C'184,196,210', 8);
   _dash_label("LAST_R", 38, 192, "Last Regime: " + (g_lastRegimeObservedSignalDirection == "" ? "NONE" : g_lastRegimeObservedSignalDirection) + " | " + _fmt_time(g_lastRegimeObservedSignalTime), C'184,196,210', 8);
   _dash_label("TPHC_A", 38, 212, "Atomic: TP leg=" + IntegerToString(g_directMt4TpIndexRuntime) + " | HC/BE TP leg=" + IntegerToString(g_directMt4HalfBeTpIndexRuntime) + " | SL=" + (g_atomicDirectRiskGeometryRuntime ? DoubleToString(g_atomicDirectTargetRRuntime, 1) + "R geometry" : "indicator"), C'184,196,210', 8);
   string regimeSlLabel = (g_regimePipSlModeRuntime ? "SL=" + DoubleToString(g_regimePipSlPipsRuntime, 1) + " pip" : (g_regimeSignalOpenSlModeRuntime ? "SL=signal bar open" : (g_regimeStructuralSwingSlModeRuntime ? "SL=local swing+buf" : "SL scale=" + DoubleToString(g_regimeFinalRiskScalePctRuntime, 0) + "%")));
   _dash_label("TPHC_R", 38, 230, "AtomicRegime: TP R=" + DoubleToString(g_regimeRRRuntime, 1) + " | HC/BE R=" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1) + " | " + regimeSlLabel, C'184,196,210', 8);
   _dash_label("GANN_FOLLOW", 38, 404, "Gann filter: " + (g_gannFollowModeRuntime ? "ON" : "OFF") + " | tf=" + _gann_follow_tf_text() + " | dir=" + (g_gannFollowLastDirection == "" ? "NONE" : g_gannFollowLastDirection) + " | " + g_gannFollowLastDetail, (g_gannFollowModeRuntime ? C'255,205,90' : C'184,196,210'), 8);
   double pct; string label; color fill;
   if(_direct_open_progress(pct, label, fill))
      _dash_progress("TRADE", 38, 318, 620, 24, pct, label, fill);
   else
      _dash_progress("TRADE", 38, 318, 620, 24, 0.0, "DIRECT MT4 POSITION: none | dashboard does not mutate signal math", C'88,96,112');

   double dayPnl = _direct_daily_closed_profit_today();
   double profitTarget = MathMax(0.0, g_directMt4DailyProfitTargetRuntime);
   double lossTarget = MathMax(0.0, g_directMt4DailyLossTargetRuntime);
   double profitPct = (profitTarget > 0.0 && dayPnl > 0.0) ? MathMin(1.0, dayPnl / profitTarget) : 0.0;
   double lossValue = MathMax(0.0, -dayPnl);
   double lossPct = (lossTarget > 0.0 && lossValue > 0.0) ? MathMin(1.0, lossValue / lossTarget) : 0.0;
   string profitText = profitTarget > 0.0
      ? ("DAY PROFIT " + DoubleToString(MathMax(0.0, dayPnl), 2) + "/" + DoubleToString(profitTarget, 2))
      : "DAY PROFIT TARGET OFF";
   string lossText = lossTarget > 0.0
      ? ("DAY LOSS " + DoubleToString(lossValue, 2) + "/" + DoubleToString(lossTarget, 2))
      : "DAY LOSS TARGET OFF";
   _dash_progress("DAY_PROFIT", 38, 350, 620, 20, profitPct, profitText, C'38,101,176');
   _dash_progress("DAY_LOSS", 38, 376, 620, 20, lossPct, lossText, C'178,37,57');
}

void _apply_dashboard()
{
   string obj;
   obj = DASH_PREFIX + "EDIT_LOT";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4LotRuntime = MathMax(0.01, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_SPREAD";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4MaxSpreadRuntime = MathMax(0, StrToInteger(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_SPREAD_SL_PCT";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4MaxSpreadToSlPctRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_ALLOWED";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4AllowedWindowsRuntime = _trim(ObjectGetString(0, obj, OBJPROP_TEXT));
   obj = DASH_PREFIX + "EDIT_NOTRADE";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4NoTradeWindowsRuntime = _trim(ObjectGetString(0, obj, OBJPROP_TEXT));
   obj = DASH_PREFIX + "EDIT_UTC_EVENT";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4UtcEventBlockTimesRuntime = _trim(ObjectGetString(0, obj, OBJPROP_TEXT));
   obj = DASH_PREFIX + "EDIT_RR";
   if(ObjectFind(0, obj) >= 0)
      g_regimeRRRuntime = MathMax(0.1, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_REGIME_HALFBE";
   if(ObjectFind(0, obj) >= 0)
      g_regimeDirectMt4HalfBeRRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_ATOMIC_HALFBE_TP";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4HalfBeTpIndexRuntime = MathMax(1, MathMin(5, StrToInteger(ObjectGetString(0, obj, OBJPROP_TEXT))));
   obj = DASH_PREFIX + "EDIT_HALFBE";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4HalfBeRRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_REGIME_DELAY";
   if(ObjectFind(0, obj) >= 0)
      g_regimeConfirmDelaySecondsRuntime = MathMax(-1, StrToInteger(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_REGIME_SCALE";
   if(ObjectFind(0, obj) >= 0)
      g_regimeFinalRiskScalePctRuntime = MathMax(1.0, MathMin(200.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT))));
   obj = DASH_PREFIX + "EDIT_REGIME_PIP_SL";
   if(ObjectFind(0, obj) >= 0)
      g_regimePipSlPipsRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_RISK_PCT";
   if(ObjectFind(0, obj) >= 0)
      g_accountRiskPerTradePctRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_DAILY_PROFIT";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4DailyProfitTargetRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_DAILY_LOSS";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4DailyLossTargetRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   g_regimeHistoryLevelsHash = "";
   string dashboardLog = "AtomicBridge dashboard applied direct=" + (g_directMt4EnabledRuntime ? "true" : "false")
      + " protrade_post=" + (g_proTradePostEnabledRuntime ? "true" : "false")
      + " priority=" + (g_directMt4PriorityDirectFirst ? "direct_first" : "post_first")
      + " lot=" + DoubleToString(g_directMt4LotRuntime, 2)
      + " risk_pct=" + DoubleToString(_account_risk_per_trade_pct(), 3)
      + " max_spread=" + IntegerToString(g_directMt4MaxSpreadRuntime)
      + " max_spread_sl_pct=" + DoubleToString(g_directMt4MaxSpreadToSlPctRuntime, 2)
      + " allowed_gmt='" + g_directMt4AllowedWindowsRuntime + "'"
      + " block_gmt='" + g_directMt4NoTradeWindowsRuntime + "'"
      + " utc_event_block='" + g_directMt4UtcEventBlockTimesRuntime + "'"
      + " regime_rr=" + DoubleToString(g_regimeRRRuntime, 2)
      + " atomic_tp=" + IntegerToString(g_directMt4TpIndexRuntime)
      + " atomic_sl_mode=" + (g_atomicDirectRiskGeometryRuntime ? "r_geometry" : "indicator")
      + " atomic_target_r=" + DoubleToString(g_atomicDirectTargetRRuntime, 2)
      + " atomic_halfbe_tp=" + IntegerToString(g_directMt4HalfBeTpIndexRuntime)
      + " atomic_fallback_halfbe_r=" + DoubleToString(g_directMt4HalfBeRRuntime, 2)
      + " regime_halfbe_r=" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2)
      + " regime_exec_mode=" + (g_regimeDelayValidationRuntime ? "delay_validate" : "direct")
      + " regime_confirm_delay_sec=" + IntegerToString(g_regimeConfirmDelaySecondsRuntime)
      + " regime_final_scale_pct=" + DoubleToString(g_regimeFinalRiskScalePctRuntime, 2)
      + " regime_pip_sl_mode=" + (g_regimePipSlModeRuntime ? "true" : "false")
      + " regime_pip_sl_pips=" + DoubleToString(g_regimePipSlPipsRuntime, 2)
      + " daily_profit_target=" + DoubleToString(g_directMt4DailyProfitTargetRuntime, 2)
      + " daily_loss_target=" + DoubleToString(g_directMt4DailyLossTargetRuntime, 2)
      + " atomic_invert=" + (g_atomicInvertTradeModeRuntime ? "true" : "false")
      + " atomic_invert_target=" + _atomic_invert_target_text()
      + " atomic_invert_hcbe_pct=" + IntegerToString(g_atomicInvertHcBeProgressPctRuntime)
      + " regime_closed_bar=" + (g_regimeUseClosedBarRuntime ? "true" : "false")
      + " regime_pre_window=" + (g_regimeOpenPreWindowSignalRuntime ? "true" : "false")
      + " risk_mode=" + (g_ftmoModeRuntime ? "FTMO" : (g_riskLotOnlyRuntime ? "RISKLOT_ONLY" : "OFF"))
      + " audit=" + (g_auditEnabledRuntime ? "true" : "false");
   Print(dashboardLog);
   _draw_dashboard();
   ChartRedraw(0);
}

double _value_per_price_unit_per_lot()
{
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickSize <= 0.0)
      tickSize = Point;
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   return tickValue / tickSize;
}

bool _valid_atomic_buffer_price(double value)
{
   if(_valid_price_or_zero(value) <= 0.0)
      return false;
   double bid = MarketInfo(Symbol(), MODE_BID);
   if(bid <= 0.0)
      bid = Close[0];
   if(bid <= 0.0)
      return true;
   return (value > bid * 0.20 && value < bid * 5.00);
}

double _atomic_buffer_value(int bufferIndex, int shift)
{
   return iCustom(NULL, 0, InpIndicatorName, bufferIndex, shift);
}

double _regime_buffer_value(int bufferIndex, int shift)
{
   // AtomicRegime is a logical strategy label. The regime signal buffers are
   // exposed by the Atomic indicator itself; there is no AtomicRegime.ex4.
   return _atomic_buffer_value(bufferIndex, shift);
}

string _regime_buffer_state_at_shift(int shift, double &upValue, double &dnValue)
{
   upValue = _regime_buffer_value(MathMax(0, InpRegimeUpTrendStopBuffer), shift);
   dnValue = _regime_buffer_value(MathMax(0, InpRegimeDnTrendStopBuffer), shift);
   bool upActive = _valid_atomic_buffer_price(upValue);
   bool dnActive = _valid_atomic_buffer_price(dnValue);
   if(upActive && !dnActive)
      return "BUY";
   if(dnActive && !upActive)
      return "SELL";
   if(upActive && dnActive)
   {
      double c = Close[MathMax(0, shift)];
      if(c > 0.0)
      {
         double upDist = MathAbs(c - upValue);
         double dnDist = MathAbs(c - dnValue);
         return (upDist <= dnDist ? "BUY" : "SELL");
      }
   }
   return "";
}

bool _find_latest_regime_signal_buffer(
   int bufferIndex,
   int startShift,
   int maxLookback,
   int &foundShift,
   datetime &foundTime,
   double &foundValue
)
{
   foundShift = -1;
   foundTime = 0;
   foundValue = 0.0;
   int buf = MathMax(0, bufferIndex);
   for(int sh = startShift; sh <= maxLookback; sh++)
   {
      double v = _regime_buffer_value(buf, sh);
      if(!_valid_atomic_buffer_price(v))
         continue;
      foundShift = sh;
      foundTime = Time[sh];
      foundValue = v;
      return foundTime > 0;
   }
   return false;
}

bool _find_current_atomic_regime_from_signal_buffers(string directionHint, string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &sourceName)
{
   direction = "";
   signalIndex = -1;
   signalTime = 0;
   entryPrice = 0.0;
   sourceName = "";

   if(!InpRegimeUseTrendSignalBuffers)
      return false;

   int shift = _regime_base_shift();
   if(Bars <= shift)
      return false;

   int maxLookback = MathMax(shift, MathMin(Bars - 1, InpRegimeBufferLookbackBars));
   int upShift = -1;
   int dnShift = -1;
   datetime upTime = 0;
   datetime dnTime = 0;
   double upValue = 0.0;
   double dnValue = 0.0;
   bool hasUp = _find_latest_regime_signal_buffer(
      InpRegimeUpTrendSignalBuffer,
      shift,
      maxLookback,
      upShift,
      upTime,
      upValue
   );
   bool hasDn = _find_latest_regime_signal_buffer(
      InpRegimeDnTrendSignalBuffer,
      shift,
      maxLookback,
      dnShift,
      dnTime,
      dnValue
   );

   string state = "";
   int selectedShift = -1;
   double selectedValue = 0.0;
   if(hasUp && (!hasDn || upShift < dnShift))
   {
      state = "BUY";
      selectedShift = upShift;
      signalTime = upTime;
      selectedValue = upValue;
   }
   else if(hasDn && (!hasUp || dnShift < upShift))
   {
      state = "SELL";
      selectedShift = dnShift;
      signalTime = dnTime;
      selectedValue = dnValue;
   }
   else if(hasUp && hasDn && upShift == dnShift)
   {
      string hint = _trim(directionHint);
      StringToUpper(hint);
      if(InpRegimeUseAtomicSignalAsTieBreak && (hint == "BUY" || hint == "SELL"))
      {
         state = hint;
         selectedShift = upShift;
         signalTime = (hint == "BUY" ? upTime : dnTime);
         selectedValue = (hint == "BUY" ? upValue : dnValue);
         if(InpLogRegimeBuffer)
         {
            PrintFormat(
               "AtomicBridge regime_signal ambiguous tie_break=%s symbol=%s tf=%s up_buf=%d dn_buf=%d shift=%d up=%s dn=%s",
               hint,
               Symbol(),
               _tf_to_string(Period()),
               MathMax(0, InpRegimeUpTrendSignalBuffer),
               MathMax(0, InpRegimeDnTrendSignalBuffer),
               upShift,
               _fmt_price(upValue),
               _fmt_price(dnValue)
            );
         }
      }
      else
      {
         if(InpLogRegimeBuffer)
         {
            PrintFormat(
               "AtomicBridge regime_signal ambiguous symbol=%s tf=%s up_buf=%d dn_buf=%d shift=%d up=%s dn=%s",
               Symbol(),
               _tf_to_string(Period()),
               MathMax(0, InpRegimeUpTrendSignalBuffer),
               MathMax(0, InpRegimeDnTrendSignalBuffer),
               upShift,
               _fmt_price(upValue),
               _fmt_price(dnValue)
            );
         }
         return false;
      }
   }

   if(state != "BUY" && state != "SELL")
      return false;

   signalIndex = selectedShift;
   double entry = 0.0;
   if(shift == 0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   if(entry <= 0.0)
      entry = Close[MathMax(0, selectedShift)];
   if(entry <= 0.0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   entryPrice = NormalizeDouble(entry, Digits);
   direction = state;
   sourceName = StringFormat(
      "AtomicRegimeSignalBuffer up=%d dn=%d shift=%d selected_shift=%d up_shift=%d dn_shift=%d up=%s dn=%s selected=%s",
      MathMax(0, InpRegimeUpTrendSignalBuffer),
      MathMax(0, InpRegimeDnTrendSignalBuffer),
      shift,
      selectedShift,
      upShift,
      dnShift,
      _fmt_price(upValue),
      _fmt_price(dnValue),
      _fmt_price(selectedValue)
   );
   return entryPrice > 0.0 && signalTime > 0;
}

bool _find_current_atomic_regime_from_stop_buffers(string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &sourceName)
{
   direction = "";
   signalIndex = -1;
   signalTime = 0;
   entryPrice = 0.0;
   sourceName = "";

   if(!InpRegimeUseTrendStopBuffers)
      return false;

   int shift = _regime_base_shift();
   if(Bars <= shift)
      return false;

   double upNow, dnNow;
   string state = _regime_buffer_state_at_shift(shift, upNow, dnNow);
   if(state != "BUY" && state != "SELL")
      return false;

   int startShift = shift;
   if(state == g_lastRegimeDirection && g_lastRegimeSignalTime > 0 && g_lastRegimeSignalIndex >= 0)
   {
      signalTime = g_lastRegimeSignalTime;
      startShift = iBarShift(NULL, 0, signalTime, true);
      if(startShift < 0)
         startShift = g_lastRegimeSignalIndex;
   }
   else
   {
      int maxLookback = MathMax(shift + 1, MathMin(Bars - 1, InpRegimeBufferLookbackBars));
      for(int sh = shift + 1; sh <= maxLookback; sh++)
      {
         double upPrev, dnPrev;
         string prevState = _regime_buffer_state_at_shift(sh, upPrev, dnPrev);
         if(prevState != state)
            break;
         startShift = sh;
      }
      signalTime = Time[startShift];
   }

   signalIndex = startShift;
   double entry = 0.0;
   if(shift == 0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   if(entry <= 0.0)
      entry = Close[shift];
   if(entry <= 0.0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   entryPrice = NormalizeDouble(entry, Digits);
   direction = state;
   sourceName = StringFormat(
      "AtomicRegimeStopBuffer up=%d dn=%d shift=%d start_shift=%d up=%s dn=%s",
      MathMax(0, InpRegimeUpTrendStopBuffer),
      MathMax(0, InpRegimeDnTrendStopBuffer),
      shift,
      startShift,
      _fmt_price(upNow),
      _fmt_price(dnNow)
   );
   return entryPrice > 0.0 && signalTime > 0;
}

bool _find_current_atomic_regime_from_buffers(string directionHint, string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &sourceName)
{
   if(_find_current_atomic_regime_from_signal_buffers(directionHint, direction, signalIndex, signalTime, entryPrice, sourceName))
      return true;
   return _find_current_atomic_regime_from_stop_buffers(direction, signalIndex, signalTime, entryPrice, sourceName);
}

double _regime_atr_for_signal(datetime signalTime)
{
   int period = MathMax(1, InpRegimeAtrPeriod);
   int shift = iBarShift(NULL, 0, signalTime, true);
   if(shift < 0)
      shift = 0;

   double atr = iATR(NULL, 0, period, shift);
   atr = _valid_price_or_zero(atr);
   if(atr > 0.0)
      return atr;

   double fallback = MathAbs(High[shift] - Low[shift]);
   fallback = _valid_price_or_zero(fallback);
   if(fallback > 0.0)
      return fallback;

   return MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point);
}


double _symbol_pip_size()
{
   double point = MarketInfo(Symbol(), MODE_POINT);
   if(point <= 0.0)
      point = Point;
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
}

bool _regime_pip_sl_enabled()
{
   return (g_regimePipSlModeRuntime && g_regimePipSlPipsRuntime > 0.0);
}

bool _regime_structural_sl_enabled()
{
   return g_regimeStructuralSwingSlModeRuntime;
}

bool _regime_signal_open_sl_enabled()
{
   return g_regimeSignalOpenSlModeRuntime;
}

double _regime_swing_atr_at_shift(int shift, int period)
{
   int p = MathMax(2, period);
   int bars = Bars;
   if(shift < 0 || bars <= shift + 1)
      return 0.0;
   double atr = iATR(NULL, 0, p, shift);
   atr = _valid_price_or_zero(atr);
   if(atr > 0.0)
      return atr;

   int last = MathMin(bars - 1, shift + p - 1);
   int count = 0;
   double sum = 0.0;
   for(int i = shift; i <= last; i++)
   {
      double prevClose = (i + 1 < bars) ? Close[i + 1] : Close[i];
      double tr = MathMax(High[i] - Low[i], MathMax(MathAbs(High[i] - prevClose), MathAbs(Low[i] - prevClose)));
      if(tr > 0.0)
      {
         sum += tr;
         count++;
      }
   }
   return count > 0 ? sum / count : 0.0;
}

bool _regime_find_structural_swing_stop(string direction,
                                        int signalShift,
                                        double entryPrice,
                                        double &swingPrice,
                                        double &structuralSl,
                                        double &swingAtr,
                                        double &prominenceAtr,
                                        int &ageBars,
                                        string &detail)
{
   swingPrice = 0.0;
   structuralSl = 0.0;
   swingAtr = 0.0;
   prominenceAtr = 0.0;
   ageBars = -1;
   detail = "";

   string dir = _trim(direction);
   double entry = _valid_price_or_zero(entryPrice);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0)
   {
      detail = "invalid_direction_or_entry";
      return false;
   }

   int bars = Bars;
   int sig = MathMax(0, signalShift);
   int left = MathMax(2, InpRegimeSwingLeftBars);
   int right = MathMax(1, InpRegimeSwingRightBars);
   int lookback = MathMax(left + right + 1, InpRegimeSwingLookbackBars);
   int maxAge = MathMax(0, InpRegimeSwingMaxAgeBars);
   int effectiveLookback = (maxAge > 0 ? MathMin(lookback, MathMax(left + right + 1, maxAge)) : lookback);
   int newestCandidate = sig + right;
   int oldestCandidate = MathMin(bars - left - 1, sig + effectiveLookback);
   if(newestCandidate > oldestCandidate || bars <= left + right + sig + 2)
   {
      detail = "insufficient_bars sig=" + IntegerToString(sig) + " bars=" + IntegerToString(bars);
      return false;
   }

   double minProminence = MathMax(0.0, InpRegimeSwingMinProminenceAtr);
   double minDeparture = MathMax(0.0, InpRegimeSwingMinDepartureAtr);
   double maxRiskAtr = MathMax(0.0, InpRegimeSwingMaxRiskAtr);
   bool foundBest = false;
   double bestSwingPrice = 0.0;
   double bestStructuralSl = 0.0;
   double bestSwingAtr = 0.0;
   double bestProminence = 0.0;
   int bestAgeBars = -1;
   double bestScore = -DBL_MAX;
   string bestDetail = "";
   double fallbackExtreme = (dir == "BUY") ? DBL_MAX : -DBL_MAX;
   int fallbackAge = -1;
   double fallbackAtr = 0.0;

   for(int candidate = newestCandidate; candidate <= oldestCandidate; candidate++)
   {
      if(candidate - right < sig || candidate + left >= bars)
         continue;

      double atr = _regime_swing_atr_at_shift(candidate, InpRegimeSwingAtrPeriod);
      if(atr <= 0.0)
         continue;

      double rawExtreme = (dir == "BUY") ? Low[candidate] : High[candidate];
      if((dir == "BUY" && rawExtreme < fallbackExtreme && rawExtreme < entry)
         || (dir == "SELL" && rawExtreme > fallbackExtreme && rawExtreme > entry))
      {
         fallbackExtreme = rawExtreme;
         fallbackAge = candidate - sig;
         fallbackAtr = atr;
      }

      bool pivot = true;
      bool strictLeft = false;
      bool strictRight = false;
      double leftExtreme = (dir == "BUY") ? -DBL_MAX : DBL_MAX;
      double rightExtreme = (dir == "BUY") ? -DBL_MAX : DBL_MAX;
      double pivotPrice = (dir == "BUY") ? Low[candidate] : High[candidate];

      // Older side of the pivot: larger MT4 shifts.
      for(int k = candidate + 1; k <= candidate + left; k++)
      {
         if(dir == "BUY")
         {
            if(Low[k] < pivotPrice)
               pivot = false;
            if(Low[k] > pivotPrice)
               strictLeft = true;
            leftExtreme = MathMax(leftExtreme, High[k]);
         }
         else
         {
            if(High[k] > pivotPrice)
               pivot = false;
            if(High[k] < pivotPrice)
               strictLeft = true;
            leftExtreme = MathMin(leftExtreme, Low[k]);
         }
      }

      // Newer side of the pivot, toward the signal bar: smaller MT4 shifts.
      for(int k = candidate - 1; k >= candidate - right; k--)
      {
         if(dir == "BUY")
         {
            if(Low[k] < pivotPrice)
               pivot = false;
            if(Low[k] > pivotPrice)
               strictRight = true;
            rightExtreme = MathMax(rightExtreme, High[k]);
         }
         else
         {
            if(High[k] > pivotPrice)
               pivot = false;
            if(High[k] < pivotPrice)
               strictRight = true;
            rightExtreme = MathMin(rightExtreme, Low[k]);
         }
      }
      if(!pivot || !strictLeft || !strictRight)
         continue;

      double leftProminence = (dir == "BUY") ? leftExtreme - pivotPrice : pivotPrice - leftExtreme;
      double rightProminence = (dir == "BUY") ? rightExtreme - pivotPrice : pivotPrice - rightExtreme;
      double prominence = MathMin(leftProminence, rightProminence) / atr;
      if(prominence < minProminence)
         continue;

      double postExtreme = (dir == "BUY") ? -DBL_MAX : DBL_MAX;
      for(int k = candidate - 1; k >= sig; k--)
      {
         if(dir == "BUY")
            postExtreme = MathMax(postExtreme, High[k]);
         else
            postExtreme = MathMin(postExtreme, Low[k]);
      }
      double signalClose = Close[sig];
      double departure = (dir == "BUY") ? postExtreme - pivotPrice : pivotPrice - postExtreme;
      double closeDeparture = (dir == "BUY") ? signalClose - pivotPrice : pivotPrice - signalClose;
      if(departure < atr * minDeparture || closeDeparture < atr * minDeparture * 0.5)
         continue;

      double buffer = MathMax(Point * 5.0, atr * MathMax(0.0, InpRegimeSwingBufferAtr));
      double candidateSl = (dir == "BUY") ? pivotPrice - buffer : pivotPrice + buffer;
      double candidateRiskAtr = MathAbs(entry - candidateSl) / atr;
      if(maxRiskAtr > 0.0 && candidateRiskAtr > maxRiskAtr)
         continue;
      if((dir == "BUY" && (candidateSl >= entry || pivotPrice >= entry))
         || (dir == "SELL" && (candidateSl <= entry || pivotPrice <= entry)))
         continue;

      int candidateAge = candidate - sig;
      double score = prominence * 100.0 - candidateAge * 3.0 - candidateRiskAtr * 50.0;
      string candidateDetail = "structural_sl swing=" + _fmt_price(pivotPrice)
         + " sl=" + _fmt_price(NormalizeDouble(candidateSl, Digits))
         + " age=" + IntegerToString(candidateAge)
         + " atr=" + DoubleToString(atr, Digits)
         + " prominence_atr=" + DoubleToString(prominence, 2)
         + " buffer_atr=" + DoubleToString(MathMax(0.0, InpRegimeSwingBufferAtr), 2)
         + " risk_atr=" + DoubleToString(candidateRiskAtr, 2)
         + " max_age=" + IntegerToString(maxAge)
         + " max_risk_atr=" + DoubleToString(maxRiskAtr, 2)
         + " selection=" + (InpRegimeSwingPreferStrongest ? "best_nearby" : "nearest");

      if(!InpRegimeSwingPreferStrongest)
      {
         swingPrice = pivotPrice;
         structuralSl = NormalizeDouble(candidateSl, Digits);
         swingAtr = atr;
         prominenceAtr = prominence;
         ageBars = candidateAge;
         detail = candidateDetail;
         return true;
      }

      if(!foundBest || score > bestScore)
      {
         foundBest = true;
         bestScore = score;
         bestSwingPrice = pivotPrice;
         bestStructuralSl = NormalizeDouble(candidateSl, Digits);
         bestSwingAtr = atr;
         bestProminence = prominence;
         bestAgeBars = candidateAge;
         bestDetail = candidateDetail;
      }
   }

   if(foundBest)
   {
      swingPrice = bestSwingPrice;
      structuralSl = bestStructuralSl;
      swingAtr = bestSwingAtr;
      prominenceAtr = bestProminence;
      ageBars = bestAgeBars;
      detail = bestDetail;
      return true;
   }

   if(InpRegimeSwingFallbackToExtreme && fallbackAge >= 0 && fallbackAtr > 0.0)
   {
      double buffer = MathMax(Point * 5.0, fallbackAtr * MathMax(0.0, InpRegimeSwingBufferAtr));
      double candidateSl = (dir == "BUY") ? fallbackExtreme - buffer : fallbackExtreme + buffer;
      double fallbackRiskAtr = MathAbs(entry - candidateSl) / fallbackAtr;
      if((maxRiskAtr <= 0.0 || fallbackRiskAtr <= maxRiskAtr) && ((dir == "BUY" && candidateSl < entry) || (dir == "SELL" && candidateSl > entry)))
      {
         swingPrice = fallbackExtreme;
         structuralSl = NormalizeDouble(candidateSl, Digits);
         swingAtr = fallbackAtr;
         prominenceAtr = 0.0;
         ageBars = fallbackAge;
         detail = "structural_sl_fallback_extreme swing=" + _fmt_price(swingPrice)
            + " sl=" + _fmt_price(structuralSl)
            + " age=" + IntegerToString(ageBars)
            + " atr=" + DoubleToString(swingAtr, Digits)
            + " buffer_atr=" + DoubleToString(MathMax(0.0, InpRegimeSwingBufferAtr), 2)
            + " lookback=" + IntegerToString(effectiveLookback)
            + " max_age=" + IntegerToString(maxAge)
            + " max_risk_atr=" + DoubleToString(maxRiskAtr, 2)
            + " risk_atr=" + DoubleToString(fallbackRiskAtr, 2);
         return true;
      }
   }

   detail = "structural_swing_not_found sig=" + IntegerToString(sig)
      + " lookback=" + IntegerToString(effectiveLookback)
      + " max_age=" + IntegerToString(maxAge)
      + " max_risk_atr=" + DoubleToString(maxRiskAtr, 2)
      + " left=" + IntegerToString(left)
      + " right=" + IntegerToString(right)
      + " fallback_age=" + IntegerToString(fallbackAge);
   return false;
}

bool _regime_apply_structural_swing_sl(string direction, int signalShift, double entryPrice, double &regimeSl, double &regimeTp, string &structReason)
{
   structReason = "";
   if(!_regime_structural_sl_enabled())
      return false;
   string dir = _trim(direction);
   double entry = _valid_price_or_zero(entryPrice);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0)
   {
      structReason = "structural_sl_invalid_geometry";
      return false;
   }

   double swingPrice, structuralSl, swingAtr, prominenceAtr;
   int ageBars;
   string detail;
   if(!_regime_find_structural_swing_stop(dir, signalShift, entry, swingPrice, structuralSl, swingAtr, prominenceAtr, ageBars, detail))
   {
      structReason = detail;
      return false;
   }

   double risk = MathAbs(entry - structuralSl);
   double minStop = MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   if(risk < minStop)
   {
      double oldRisk = risk;
      risk = minStop;
      structuralSl = NormalizeDouble((dir == "BUY") ? entry - risk : entry + risk, Digits);
      detail = detail + " min_stop_floor old_risk=" + DoubleToString(oldRisk, Digits) + " min_stop=" + DoubleToString(minStop, Digits);
   }
   double rr = MathMax(0.1, g_regimeRRRuntime);
   regimeSl = structuralSl;
   regimeTp = NormalizeDouble((dir == "BUY") ? entry + risk * rr : entry - risk * rr, Digits);
   structReason = "regime_structural_swing_sl " + detail + " rr=" + DoubleToString(rr, 2) + " tp=" + _fmt_price(regimeTp);
   return (regimeSl > 0.0 && regimeTp > 0.0);
}
bool _regime_apply_signal_open_sl(string direction, int signalShift, double entryPrice, double &regimeSl, double &regimeTp, string &sigOpenReason)
{
   sigOpenReason = "";
   if(!_regime_signal_open_sl_enabled())
      return false;
   string dir = _trim(direction);
   double entry = _valid_price_or_zero(entryPrice);
   int sh = MathMax(0, signalShift);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0 || Bars <= sh)
   {
      sigOpenReason = "regime_sigopen_sl_invalid_geometry shift=" + IntegerToString(signalShift) + " bars=" + IntegerToString(Bars);
      return false;
   }

   double signalOpen = _valid_price_or_zero(Open[sh]);
   if(signalOpen <= 0.0)
   {
      sigOpenReason = "regime_sigopen_sl_invalid_open shift=" + IntegerToString(sh);
      return false;
   }

   double requestedRisk = MathAbs(entry - signalOpen);
   double minStop = MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   double risk = MathMax(requestedRisk, minStop);
   if(risk <= 0.0)
   {
      sigOpenReason = "regime_sigopen_sl_zero_risk entry=" + _fmt_price(entry) + " signal_open=" + _fmt_price(signalOpen);
      return false;
   }

   double rr = MathMax(0.1, g_regimeRRRuntime);
   double oldSl = regimeSl;
   double oldTp = regimeTp;
   regimeSl = NormalizeDouble((dir == "BUY") ? entry - risk : entry + risk, Digits);
   regimeTp = NormalizeDouble((dir == "BUY") ? entry + risk * rr : entry - risk * rr, Digits);
   sigOpenReason = "regime_sigopen_sl shift=" + IntegerToString(sh)
      + " signal_bar_open=" + _fmt_price(signalOpen)
      + " entry=" + _fmt_price(entry)
      + " requested_risk=" + DoubleToString(requestedRisk, Digits)
      + " applied_risk=" + DoubleToString(risk, Digits)
      + " min_stop=" + DoubleToString(minStop, Digits)
      + " rr=" + DoubleToString(rr, 2)
      + " old_sl=" + _fmt_price(oldSl)
      + " new_sl=" + _fmt_price(regimeSl)
      + " old_tp=" + _fmt_price(oldTp)
      + " new_tp=" + _fmt_price(regimeTp);
   return (regimeSl > 0.0 && regimeTp > 0.0);
}

bool _regime_apply_pip_sl(string direction, double entryPrice, double &regimeSl, double &regimeTp, string &pipReason)
{
   pipReason = "";
   if(!_regime_pip_sl_enabled())
      return false;
   string dir = _trim(direction);
   double entry = _valid_price_or_zero(entryPrice);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0)
   {
      pipReason = "regime_pip_sl_invalid_geometry";
      return false;
   }
   double pipSize = _symbol_pip_size();
   double requestedRisk = MathMax(0.0, g_regimePipSlPipsRuntime) * pipSize;
   double minStop = MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   double risk = MathMax(requestedRisk, minStop);
   double rr = MathMax(0.1, g_regimeRRRuntime);
   double oldSl = regimeSl;
   double oldTp = regimeTp;
   regimeSl = NormalizeDouble((dir == "BUY") ? entry - risk : entry + risk, Digits);
   regimeTp = NormalizeDouble((dir == "BUY") ? entry + risk * rr : entry - risk * rr, Digits);
   pipReason = "regime_pip_sl_mode pips=" + DoubleToString(g_regimePipSlPipsRuntime, 2)
      + " pip_size=" + DoubleToString(pipSize, Digits + 2)
      + " requested_risk=" + DoubleToString(requestedRisk, Digits)
      + " applied_risk=" + DoubleToString(risk, Digits)
      + " min_stop=" + DoubleToString(minStop, Digits)
      + " rr=" + DoubleToString(rr, 2)
      + " old_sl=" + _fmt_price(oldSl)
      + " new_sl=" + _fmt_price(regimeSl)
      + " old_tp=" + _fmt_price(oldTp)
      + " new_tp=" + _fmt_price(regimeTp);
   return (regimeSl > 0.0 && regimeTp > 0.0);
}
void _compute_regime_levels(string direction, datetime signalTime, double entryPrice, double &sl, double &tp)
{
   sl = 0.0;
   tp = 0.0;
   double entry = _valid_price_or_zero(entryPrice);
   if(entry <= 0.0)
      return;

   double atr = _regime_atr_for_signal(signalTime);
   double minStop = MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   double atrRisk = atr * MathMax(0.1, InpRegimeAtrMultiplier);
   double pctRisk = entry * MathMax(0.0, InpRegimeMinRiskPricePct);
   double pctCap = entry * MathMax(0.0, InpRegimeMaxRiskPricePct);
   double moneyCap = 0.0;
   double valuePerUnit = _value_per_price_unit_per_lot();
   if(InpRegimeMaxRiskMoneyPerLot > 0.0 && valuePerUnit > 0.0)
      moneyCap = InpRegimeMaxRiskMoneyPerLot / valuePerUnit;
   double absoluteRisk = _valid_price_or_zero(InpRegimeMinRiskPoints);
   double risk = MathMax(MathMax(atrRisk, pctRisk), MathMax(minStop, absoluteRisk));
   double hardFloor = MathMax(minStop, absoluteRisk);
   double riskCap = 0.0;
   if(pctCap > hardFloor)
      riskCap = pctCap;
   if(moneyCap > hardFloor)
      riskCap = (riskCap > 0.0 ? MathMin(riskCap, moneyCap) : moneyCap);
   if(riskCap > hardFloor && risk > riskCap)
      risk = riskCap;
   if(risk < hardFloor)
      risk = hardFloor;
   if(InpLogRegimeBuffer)
   {
      PrintFormat(
         "AtomicBridge regime risk model dir=%s entry=%s atr=%s atr_mult=%.2f atr_risk=%s pct_floor=%.5f pct_risk=%s pct_cap=%.5f pct_cap_risk=%s money_cap_per_lot=%s money_cap_risk=%s abs_floor=%s min_stop=%s final_risk=%s rr=%.2f",
         direction,
         _fmt_price(entry),
         _fmt_price(atr),
         MathMax(0.1, InpRegimeAtrMultiplier),
         _fmt_price(atrRisk),
         MathMax(0.0, InpRegimeMinRiskPricePct),
         _fmt_price(pctRisk),
         MathMax(0.0, InpRegimeMaxRiskPricePct),
         _fmt_price(pctCap),
         _fmt_price(InpRegimeMaxRiskMoneyPerLot),
         _fmt_price(moneyCap),
         _fmt_price(absoluteRisk),
         _fmt_price(minStop),
         _fmt_price(risk),
         MathMax(0.1, InpRegimeRR)
      );
   }
   double rr = MathMax(0.1, g_regimeRRRuntime);

   if(direction == "BUY")
   {
      sl = NormalizeDouble(entry - risk, Digits);
      tp = NormalizeDouble(entry + (risk * rr), Digits);
   }
   else if(direction == "SELL")
   {
      sl = NormalizeDouble(entry + risk, Digits);
      tp = NormalizeDouble(entry - (risk * rr), Digits);
   }
}
bool _regime_apply_atomic_sl_clamp(string direction, double entryPrice, double atomicEntry, double atomicSl, double &regimeSl, double &regimeTp, string &clampReason)
{
   clampReason = "";
   if(!InpRegimeClampSlToAtomicSignalSl)
      return false;
   string dir = _trim(direction);
   if(dir != "BUY" && dir != "SELL")
      return false;
   double entry = _valid_price_or_zero(entryPrice);
   double aEntry = _valid_price_or_zero(atomicEntry);
   double aSl = _valid_price_or_zero(atomicSl);
   if(entry <= 0.0 || aEntry <= 0.0 || aSl <= 0.0 || regimeSl <= 0.0 || regimeTp <= 0.0)
      return false;

   double atomicRisk = MathAbs(aEntry - aSl);
   double regimeRisk = MathAbs(entry - regimeSl);
   if(atomicRisk <= Point || regimeRisk + Point >= atomicRisk)
      return false;

   double oldSl = regimeSl;
   double oldTp = regimeTp;
   double rr = MathMax(0.1, g_regimeRRRuntime);
   regimeSl = NormalizeDouble((dir == "BUY") ? (entry - atomicRisk) : (entry + atomicRisk), Digits);
   regimeTp = NormalizeDouble((dir == "BUY") ? (entry + atomicRisk * rr) : (entry - atomicRisk * rr), Digits);
   clampReason = "atomic_companion_min_risk atomic_risk=" + DoubleToString(atomicRisk, Digits) + " old_regime_risk=" + DoubleToString(regimeRisk, Digits) + " old_sl=" + _fmt_price(oldSl) + " new_sl=" + _fmt_price(regimeSl) + " old_tp=" + _fmt_price(oldTp) + " new_tp=" + _fmt_price(regimeTp) + " rr=" + DoubleToString(rr, 2);
   return true;
}

bool _regime_apply_sl_widen(string direction, double entryPrice, double &regimeSl, double &regimeTp, string &widenReason)
{
   widenReason = "";
   if(!InpRegimeSlWidenEnabled)
      return false;
   string dir = _trim(direction);
   double entry = _valid_price_or_zero(entryPrice);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0 || regimeSl <= 0.0 || regimeTp <= 0.0)
      return false;
   double rawRisk = MathAbs(entry - regimeSl);
   if(rawRisk <= Point)
      return false;
   double pct = MathMax(0.0, MathMin(200.0, InpRegimeSlWidenPct)) / 100.0;
   if(pct <= 0.0)
      return false;
   double oldSl = regimeSl;
   double oldTp = regimeTp;
   double widenedRisk = rawRisk * (1.0 + pct);
   double rr = MathMax(0.1, g_regimeRRRuntime);
   regimeSl = NormalizeDouble((dir == "BUY") ? entry - widenedRisk : entry + widenedRisk, Digits);
   regimeTp = NormalizeDouble((dir == "BUY") ? entry + widenedRisk * rr : entry - widenedRisk * rr, Digits);
   widenReason = "regime_sl_widen pct=" + DoubleToString(pct * 100.0, 1)
      + " raw_risk=" + DoubleToString(rawRisk, Digits)
      + " widened_risk=" + DoubleToString(widenedRisk, Digits)
      + " old_sl=" + _fmt_price(oldSl)
      + " new_sl=" + _fmt_price(regimeSl)
      + " old_tp=" + _fmt_price(oldTp)
      + " new_tp=" + _fmt_price(regimeTp);
   return true;
}

bool _regime_apply_final_risk_scale(string direction, double entryPrice, double &regimeSl, double &regimeTp, string &scaleReason)
{
   scaleReason = "";
   string dir = _trim(direction);
   double entry = _valid_price_or_zero(entryPrice);
   if((dir != "BUY" && dir != "SELL") || entry <= 0.0 || regimeSl <= 0.0 || regimeTp <= 0.0)
      return false;

   double pct = MathMax(1.0, MathMin(200.0, g_regimeFinalRiskScalePctRuntime));
   if(MathAbs(pct - 100.0) < 0.0001)
      return false;

   double rawRisk = MathAbs(entry - regimeSl);
   if(rawRisk <= Point)
      return false;

   double minStop = MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   double targetRisk = MathMax(minStop, rawRisk * pct / 100.0);
   if(MathAbs(targetRisk - rawRisk) <= Point * 0.5)
      return false;

   double oldSl = regimeSl;
   double oldTp = regimeTp;
   double rr = MathMax(0.1, g_regimeRRRuntime);
   regimeSl = NormalizeDouble((dir == "BUY") ? entry - targetRisk : entry + targetRisk, Digits);
   regimeTp = NormalizeDouble((dir == "BUY") ? entry + targetRisk * rr : entry - targetRisk * rr, Digits);
   scaleReason = "regime_final_risk_scale pct=" + DoubleToString(pct, 1)
      + " raw_risk=" + DoubleToString(rawRisk, Digits)
      + " target_risk=" + DoubleToString(targetRisk, Digits)
      + " min_stop=" + DoubleToString(minStop, Digits)
      + " old_sl=" + _fmt_price(oldSl)
      + " new_sl=" + _fmt_price(regimeSl)
      + " old_tp=" + _fmt_price(oldTp)
      + " new_tp=" + _fmt_price(regimeTp);
   return true;
}
bool _post_atomic_regime_event(
   string eventType,
   string direction,
   int signalIndex,
   datetime signalTime,
   double entryPrice,
   double sl,
   double tp,
   string trendName,
   string reason
)
{
   if(!InpEnableRegimeChangePost)
      return true;

   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   int regimePeriod = MathMax(1, InpRegimeAtrPeriod);
   string eventId = StringFormat(
      "atomic_regime|%s|%s|%s|%d|%I64d|%s",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      (long)signalTime,
      eventKind
   );
   bool directFirst = (eventKind == "confirmed_signal" && _direct_priority_direct_first());
   double regimeHalfTrigger = 0.0;
   string regimeHalfLabel = "r" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1);
   string regimeInvertDetail = "";
   if(_atomic_invert_enabled_for_event(eventKind, dir))
   {
      string invertedDir = "";
      double invertedSl = 0.0;
      double invertedTp = 0.0;
      if(!_atomic_build_inverted_geometry(dir, entryPrice, sl, tp, invertedDir, invertedSl, invertedTp, regimeInvertDetail))
      {
         Print("AtomicBridge regime skipped reason=regime_invert_geometry_invalid event=", eventId, " dir=", dir, " detail=", regimeInvertDetail);
         return false;
      }
      dir = invertedDir;
      sl = invertedSl;
      tp = invertedTp;
      bool regimeInvertHalfRebased = false;
      string regimeInvertHalfReason = "";
      regimeHalfTrigger = _direct_normalize_half_trigger(dir, entryPrice, sl, tp, 0.0, g_regimeDirectMt4HalfBeRRuntime, regimeInvertHalfRebased, regimeInvertHalfReason);
      regimeHalfLabel = regimeHalfTrigger > 0.0 ? ("r" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2)) : "regime_hcbe_off";
      regimeInvertDetail = regimeInvertDetail + "|regime_hcbe=" + regimeHalfLabel + "|" + regimeInvertHalfReason;
      trendName = trendName + "|" + regimeInvertDetail;
      if(eventKind == "confirmed_signal")
         eventId = eventId + "|invert";
   }
   if(directFirst)
      _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, regimeHalfTrigger, regimeHalfLabel, signalTime);
   if(!g_proTradePostEnabledRuntime)
   {
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, regimeHalfTrigger, regimeHalfLabel, signalTime);
      return true;
   }
   string msg = StringFormat(
      "AtomicRegime %s %s %s idx=%d entry=%s sl=%s tp=%s atr_period=%d atr_mult=%.2f rr=%.2f min_pct=%.5f max_pct=%.5f",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      _fmt_price(entryPrice),
      _fmt_price(sl),
      _fmt_price(tp),
      regimePeriod,
      MathMax(0.1, InpRegimeAtrMultiplier),
      MathMax(0.1, g_regimeRRRuntime),
      MathMax(0.0, InpRegimeMinRiskPricePct),
      MathMax(0.0, InpRegimeMaxRiskPricePct)
   );

   string resolved = (dir == "BUY" || dir == "SELL") ? dir : "NONE";
   if((eventKind == "confirmed_signal" || eventKind == "resolved_state") && (dir == "BUY" || dir == "SELL") && signalTime > 0)
   {
      g_lastRegimeObservedSignalDirection = dir;
      g_lastRegimeObservedSignalTime = signalTime;
      g_lastRegimeObservedSignalValue = entryPrice;
   }
   string lastRegimeSignalDirection = g_lastRegimeObservedSignalDirection;
   datetime lastRegimeSignalTime = g_lastRegimeObservedSignalTime;
   double lastRegimeSignalValue = g_lastRegimeObservedSignalValue;
   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpRegimeIndicatorName) + "\"," 
      "\"signal_hint\":\"" + _json_escape(dir) + "\"," 
      "\"resolved_signal\":\"" + _json_escape(resolved) + "\"," 
      "\"confirmed_direction\":\"" + _json_escape((eventKind == "confirmed_signal") ? dir : "") + "\"," 
      "\"bridge_version\":\"v2\"," 
      "\"symbol\":\"" + _json_escape(Symbol()) + "\"," 
      "\"timeframe\":\"" + _json_escape(_tf_to_string(Period())) + "\"," 
      "\"signal_profile\":\"" + _json_escape(InpRegimeSignalProfile) + "\"," 
      "\"bridge_event_type\":\"" + _json_escape(eventKind) + "\"," 
      "\"event_id\":\"" + _json_escape(eventId) + "\"," 
      "\"event_ts\":\"" + _json_escape(_event_ts_now()) + "\"," +
      _bridge_runtime_telemetry_json() +
      "\"resolved_signal_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\"," 
      "\"resolved_signal_bar_unix\":" + IntegerToString((int)signalTime) + "," 
      "\"last_signal_direction\":\"" + _json_escape(lastRegimeSignalDirection) + "\","
      "\"last_signal_bar_time\":\"" + _json_escape(_fmt_time(lastRegimeSignalTime)) + "\","
      "\"last_signal_bar_unix\":" + IntegerToString((int)lastRegimeSignalTime) + ","
      "\"last_signal_value\":" + DoubleToString(lastRegimeSignalValue, Digits) + ","
      "\"secondary_enabled\":true," 
      "\"secondary_indicator\":\"AtomicRegimeAtr3R\"," 
      "\"secondary_signal\":\"" + _json_escape(dir) + "\"," 
      "\"secondary_resolved_signal\":\"" + _json_escape(dir) + "\"," 
      "\"secondary_signal_shift\":-1," 
      "\"secondary_resolved_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\"," 
      "\"secondary_entry_enabled\":true," 
      "\"secondary_entry\":" + DoubleToString(entryPrice, Digits) + "," 
      "\"secondary_sl_enabled\":true," 
      "\"secondary_stop_loss\":" + DoubleToString(sl, Digits) + "," 
      "\"secondary_tp_enabled\":true," 
      "\"secondary_tp1\":" + DoubleToString(tp, Digits) + "," 
      "\"atomic_regime_atr_period\":" + IntegerToString(regimePeriod) + ","
      "\"atomic_regime_atr_multiplier\":" + DoubleToString(MathMax(0.1, InpRegimeAtrMultiplier), 2) + ","
      "\"atomic_regime_rr\":" + DoubleToString(MathMax(0.1, g_regimeRRRuntime), 2) + ","
      "\"atomic_regime_min_risk_price_pct\":" + DoubleToString(MathMax(0.0, InpRegimeMinRiskPricePct), 6) + ","
      "\"atomic_regime_max_risk_price_pct\":" + DoubleToString(MathMax(0.0, InpRegimeMaxRiskPricePct), 6) + ","
      "\"atomic_regime_max_risk_money_per_lot\":" + DoubleToString(MathMax(0.0, InpRegimeMaxRiskMoneyPerLot), 2) + ","
      "\"atomic_regime_sl_widen_enabled\":" + (InpRegimeSlWidenEnabled ? "true" : "false") + ","
      "\"atomic_regime_sl_widen_pct\":" + DoubleToString(MathMax(0.0, InpRegimeSlWidenPct), 2) + ","
      "\"atomic_regime_final_risk_scale_pct\":" + DoubleToString(MathMax(1.0, MathMin(200.0, g_regimeFinalRiskScalePctRuntime)), 2) + ","
      "\"atomic_regime_pip_sl_mode\":" + (g_regimePipSlModeRuntime ? "true" : "false") + ","
      "\"atomic_regime_pip_sl_pips\":" + DoubleToString(g_regimePipSlPipsRuntime, 2) + ","
      "\"atomic_regime_signal_open_sl_mode\":" + (g_regimeSignalOpenSlModeRuntime ? "true" : "false") + ","
      "\"message\":\"" + _json_escape(msg) + "\"," 
      "\"atomic_signal_index\":" + IntegerToString(signalIndex) + "," 
      "\"atomic_trend_object\":\"" + _json_escape(trendName) + "\"," 
      "\"atomic_regime_reason\":\"" + _json_escape(reason) + "\"," 
      "\"bridge_token\":\"" + _json_escape(InpBridgeToken) + "\"" 
      "}";

   char post[];
   StringToCharArray(body, post, 0, StringLen(body));
   char result[];
   string responseHeaders = "";
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(InpBridgeToken) > 0)
      headers = headers + "X-MT4-Bridge-Token: " + InpBridgeToken + "\r\n";

   ResetLastError();
   int code = WebRequest("POST", endpoint, headers, MathMax(1000, InpHttpTimeoutMs), post, result, responseHeaders);
   string response = CharArrayToString(result, 0, -1);
   if(code >= 200 && code < 300)
   {
      if(InpLogPostResponses || _should_log_handshake_response(eventKind, reason))
      {
         Print("AtomicBridge regime handshake sent ", eventKind, " ", dir, " reason=", reason, " response=", _compact_bridge_response(response));
      }
      else if(eventKind == "confirmed_signal")
      {
         Print("AtomicBridge regime sent ", eventKind, " ", dir);
      }
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, regimeHalfTrigger, regimeHalfLabel, signalTime);
      return true;
   }

   Print("AtomicBridge regime POST failed code=", code, " err=", GetLastError(), " event=", eventKind, " dir=", dir, " endpoint=", endpoint, " response=", response);
   if(eventKind == "confirmed_signal" && !directFirst)
      _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, regimeHalfTrigger, regimeHalfLabel, signalTime);
   return false;
}

void _handle_regime_event(string reason, string direction, int signalIndex, datetime signalTime, double entryPrice, string trendName, string atomicDirection, double atomicEntry, double atomicSl)
{
   if(!InpEnableRegimeChangePost || StringLen(direction) <= 0)
      return;

   double regimeSl = 0.0;
   double regimeTp = 0.0;
   if(_regime_pip_sl_enabled())
   {
      string pipReason = "";
      if(!_regime_apply_pip_sl(direction, entryPrice, regimeSl, regimeTp, pipReason))
      {
         Print("AtomicBridge regime warning: invalid pip SL geometry for dir=", direction, " entry=", _fmt_price(entryPrice), " reason=", pipReason);
         return;
      }
      trendName = trendName + "|" + pipReason;
   }
   else if(_regime_signal_open_sl_enabled())
   {
      string sigOpenReason = "";
      if(!_regime_apply_signal_open_sl(direction, signalIndex, entryPrice, regimeSl, regimeTp, sigOpenReason))
      {
         Print("AtomicBridge regime warning: invalid signal-open SL geometry for dir=", direction, " entry=", _fmt_price(entryPrice), " shift=", signalIndex, " reason=", sigOpenReason);
         return;
      }
      trendName = trendName + "|" + sigOpenReason;
   }
   else
   {
      bool structuralApplied = false;
      if(_regime_structural_sl_enabled())
      {
         string structReason = "";
         structuralApplied = _regime_apply_structural_swing_sl(direction, signalIndex, entryPrice, regimeSl, regimeTp, structReason);
         if(structuralApplied)
            trendName = trendName + "|" + structReason;
         else
            trendName = trendName + "|structural_sl_not_found_fallback_atr " + structReason;
      }

      if(!structuralApplied)
      {
         _compute_regime_levels(direction, signalTime, entryPrice, regimeSl, regimeTp);
         if(regimeSl <= 0.0 || regimeTp <= 0.0)
         {
            Print("AtomicBridge regime warning: invalid ATR SL/TP for dir=", direction, " entry=", _fmt_price(entryPrice));
            return;
         }
         if(_trim(direction) == _trim(atomicDirection))
         {
            string clampReason = "";
            if(_regime_apply_atomic_sl_clamp(direction, entryPrice, atomicEntry, atomicSl, regimeSl, regimeTp, clampReason))
               trendName = trendName + "|" + clampReason;
         }
      }

      string widenReason = "";
      if(_regime_apply_sl_widen(direction, entryPrice, regimeSl, regimeTp, widenReason))
         trendName = trendName + "|" + widenReason;
      string scaleReason = "";
      if(_regime_apply_final_risk_scale(direction, entryPrice, regimeSl, regimeTp, scaleReason))
         trendName = trendName + "|" + scaleReason;
   }
   // Shift is not a stable identity during delayed confirmation: a fresh shift=1
   // signal naturally becomes shift=2/3/... while the 300s timer is running.
   string regimeEventId = _regime_event_id(direction, signalTime);
   string displayDirection = _trim(direction);
   double displaySl = regimeSl;
   double displayTp = regimeTp;
   double displayHc = 0.0;
   string displayInvertDetail = "";
   _atomic_apply_invert_to_geometry_for_levels(direction, entryPrice, displaySl, displayTp, displayHc, displayDirection, displayInvertDetail);
   bool freezeLiveSignalLevels = (!g_regimeUseClosedBarRuntime && !g_regimeDelayValidationRuntime
      && g_latestRegimeLevelEventId == regimeEventId
      && g_latestRegimeLevelEntry > 0.0 && g_latestRegimeLevelSl > 0.0 && g_latestRegimeLevelTp > 0.0);
   if(!freezeLiveSignalLevels)
   {
      g_latestRegimeLevelDirection = displayDirection;
      g_latestRegimeLevelEntry = entryPrice;
      g_latestRegimeLevelSl = displaySl;
      g_latestRegimeLevelTp = displayTp;
      g_latestRegimeLevelHalf = displayHc;
      g_latestRegimeLevelSignalTime = signalTime;
      g_latestRegimeLevelEventId = regimeEventId;
   }
   bool directionChanged = (StringLen(g_lastRegimeDirection) > 0 && direction != g_lastRegimeDirection);
   bool regimeEventChanged = (StringLen(g_lastRegimeEventId) <= 0 || regimeEventId != g_lastRegimeEventId);

   if(reason == "init" || reason == "init_retry")
   {
      g_lastRegimeDirection = direction;
      g_lastRegimeEventId = regimeEventId;
      g_lastRegimeSignalIndex = signalIndex;
      g_lastRegimeSignalTime = signalTime;
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
         g_lastRegimeResolvedPostTime = _timer_now();
      if(reason == "init" && InpSendInitialRegimeConfirmedOnStart)
      {
         _post_atomic_regime_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason);
         _regime_mark_opened_for_validation(regimeEventId, direction, signalTime, signalIndex);
         g_lastRegimeConfirmedEventId = regimeEventId;
         g_lastRegimeConfirmedDirection = direction;
         g_lastRegimeConfirmedSignalTime = signalTime;
      }
      return;
   }

   g_lastRegimeEventId = regimeEventId;
   if(g_lastRegimeLifecycleSignalEventId != regimeEventId)
   {
      bool freshForConfirm = (InpRegimeMaxConfirmShift < 0 || signalIndex <= InpRegimeMaxConfirmShift);
      _regime_lifecycle_audit(
         "regime_signal_seen",
         regimeEventId,
         direction,
         signalIndex,
         signalTime,
         entryPrice,
         regimeSl,
         regimeTp,
         reason,
         0,
         0,
         _regime_effective_delay_seconds(),
         -1,
         "fresh_for_confirm=" + (freshForConfirm ? "1" : "0") + " max_confirm_shift=" + IntegerToString(InpRegimeMaxConfirmShift)
      );
      g_lastRegimeLifecycleSignalEventId = regimeEventId;
   }

   if(_regime_wait_or_sync_atomic_companion(regimeEventId, direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, reason))
      return;

   datetime nowPending = _timer_now();
   int pendingStableSeconds = _regime_effective_delay_seconds();
   bool pendingSameSignal = (
      StringLen(g_pendingRegimeEventId) > 0
      && g_pendingRegimeEventId == regimeEventId
      && g_pendingRegimeDirection == direction
      && g_pendingRegimeSignalTime == signalTime
   );
   if(pendingSameSignal)
   {
      int pendingAge = (int)(nowPending - g_pendingRegimeFirstSeen);
      bool signalClosedToConfirmBar = (g_regimeDelayValidationRuntime && g_pendingRegimeSignalIndex == 0 && signalIndex == 1);
      bool signalTooStale = (InpRegimeMaxConfirmShift >= 0 && signalIndex > InpRegimeMaxConfirmShift);
      if(signalTooStale)
      {
         _regime_cancel_pending_delay("signal_too_stale_before_open", true, direction, signalIndex, signalTime);
         return;
      }
      if(pendingStableSeconds > 0 && pendingAge < pendingStableSeconds && !signalClosedToConfirmBar)
      {
         if(InpLogRegimeBuffer)
            Print("AtomicBridge regime_signal pending delay dir=", direction, " age=", IntegerToString(pendingAge), " delay_sec=", IntegerToString(pendingStableSeconds), " event=", regimeEventId);
         return;
      }
      if(g_lastRegimeLifecycleDelayFinishEventId != regimeEventId)
      {
         _regime_lifecycle_audit(
            "regime_delay_finished",
            regimeEventId,
            direction,
            signalIndex,
            signalTime,
            entryPrice,
            regimeSl,
            regimeTp,
            signalClosedToConfirmBar ? "signal_bar_closed_confirm_now" : "timer_elapsed",
            g_pendingRegimeFirstSeen,
            nowPending,
            pendingStableSeconds,
            pendingAge,
            "pending_started_shift=" + IntegerToString(g_pendingRegimeSignalIndex)
         );
         g_lastRegimeLifecycleDelayFinishEventId = regimeEventId;
      }
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
         g_lastRegimeResolvedPostTime = nowPending;
      _post_atomic_regime_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason);
      _regime_mark_opened_for_validation(regimeEventId, direction, signalTime, signalIndex);
      g_lastRegimeDirection = direction;
      g_lastRegimeConfirmedEventId = regimeEventId;
      g_lastRegimeSignalIndex = signalIndex;
      g_lastRegimeSignalTime = signalTime;
      g_lastRegimeConfirmedDirection = direction;
      g_lastRegimeConfirmedSignalTime = signalTime;
      _regime_clear_pending_state();
      return;
   }

   if(StringLen(g_lastRegimeDirection) <= 0)
   {
      if(InpRegimeMaxConfirmShift >= 0 && signalIndex > InpRegimeMaxConfirmShift)
      {
         g_lastRegimeDirection = direction;
         g_lastRegimeSignalIndex = signalIndex;
         g_lastRegimeSignalTime = signalTime;
         if(_heartbeat_due(g_lastRegimeResolvedPostTime))
         {
            if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, "initial_stale_heartbeat"))
               g_lastRegimeResolvedPostTime = _timer_now();
         }
         return;
      }

      datetime initialNowStable = _timer_now();
      int initialStableSeconds = _regime_effective_delay_seconds();
      if(g_pendingRegimeEventId != regimeEventId)
      {
         g_pendingRegimeEventId = regimeEventId;
         g_pendingRegimeDirection = direction;
         g_pendingRegimeFirstSeen = initialNowStable;
         g_pendingRegimeSignalTime = signalTime;
         g_pendingRegimeSignalIndex = signalIndex;
         if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
            g_lastRegimeResolvedPostTime = initialNowStable;
         if(initialStableSeconds > 0)
         {
            if(g_lastRegimeLifecycleDelayStartEventId != regimeEventId)
            {
               _regime_lifecycle_audit(
                  "regime_delay_started",
                  regimeEventId,
                  direction,
                  signalIndex,
                  signalTime,
                  entryPrice,
                  regimeSl,
                  regimeTp,
                  reason,
                  initialNowStable,
                  0,
                  initialStableSeconds,
                  0,
                  "start_shift=" + IntegerToString(signalIndex)
               );
               g_lastRegimeLifecycleDelayStartEventId = regimeEventId;
            }
            if(InpLogRegimeBuffer)
               Print("AtomicBridge regime_signal initial delay_started dir=", direction, " delay_sec=", IntegerToString(initialStableSeconds), " event=", regimeEventId);
            return;
         }
      }
      if(initialStableSeconds > 0 && (initialNowStable - g_pendingRegimeFirstSeen) < initialStableSeconds)
      {
         if(InpLogRegimeBuffer)
            Print("AtomicBridge regime_signal initial pending delay dir=", direction, " age=", IntegerToString((int)(initialNowStable - g_pendingRegimeFirstSeen)), " delay_sec=", IntegerToString(initialStableSeconds), " event=", regimeEventId);
         return;
      }
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
         g_lastRegimeResolvedPostTime = _timer_now();
      _post_atomic_regime_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason);
      _regime_mark_opened_for_validation(regimeEventId, direction, signalTime, signalIndex);
      g_lastRegimeDirection = direction;
      g_lastRegimeConfirmedEventId = regimeEventId;
      g_lastRegimeSignalIndex = signalIndex;
      g_lastRegimeSignalTime = signalTime;
      g_lastRegimeConfirmedDirection = direction;
      g_lastRegimeConfirmedSignalTime = signalTime;
      _regime_clear_pending_state();
      return;
   }

   if(regimeEventChanged && regimeEventId != g_lastRegimeConfirmedEventId)
   {
      if(InpRegimeMaxConfirmShift >= 0 && signalIndex > InpRegimeMaxConfirmShift)
      {
         if(_heartbeat_due(g_lastRegimeResolvedPostTime))
         {
            if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, "heartbeat"))
               g_lastRegimeResolvedPostTime = _timer_now();
         }
         return;
      }
      if(directionChanged && g_lastRegimeConfirmedSignalTime > 0 && signalTime == g_lastRegimeConfirmedSignalTime && direction != g_lastRegimeConfirmedDirection)
      {
         if(InpLogRegimeBuffer)
            Print("AtomicBridge regime_signal suppressed same_bar_flip dir=", direction, " bar=", _fmt_time(signalTime), " last=", g_lastRegimeConfirmedDirection);
         return;
      }
      datetime nowStable = _timer_now();
      int stableSeconds = _regime_effective_delay_seconds();
      if(g_pendingRegimeEventId != regimeEventId)
      {
         g_pendingRegimeEventId = regimeEventId;
         g_pendingRegimeDirection = direction;
         g_pendingRegimeFirstSeen = nowStable;
         g_pendingRegimeSignalTime = signalTime;
         g_pendingRegimeSignalIndex = signalIndex;
         if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
            g_lastRegimeResolvedPostTime = nowStable;
         if(stableSeconds > 0)
         {
            if(g_lastRegimeLifecycleDelayStartEventId != regimeEventId)
            {
               _regime_lifecycle_audit(
                  "regime_delay_started",
                  regimeEventId,
                  direction,
                  signalIndex,
                  signalTime,
                  entryPrice,
                  regimeSl,
                  regimeTp,
                  reason,
                  nowStable,
                  0,
                  stableSeconds,
                  0,
                  "start_shift=" + IntegerToString(signalIndex)
               );
               g_lastRegimeLifecycleDelayStartEventId = regimeEventId;
            }
            if(InpLogRegimeBuffer)
               Print("AtomicBridge regime_signal delay_started dir=", direction, " delay_sec=", IntegerToString(stableSeconds), " event=", regimeEventId);
            return;
         }
      }
      if(stableSeconds > 0 && (nowStable - g_pendingRegimeFirstSeen) < stableSeconds)
      {
         if(InpLogRegimeBuffer)
            Print("AtomicBridge regime_signal pending delay dir=", direction, " age=", IntegerToString((int)(nowStable - g_pendingRegimeFirstSeen)), " delay_sec=", IntegerToString(stableSeconds), " event=", regimeEventId);
         return;
      }
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
         g_lastRegimeResolvedPostTime = _timer_now();
      _post_atomic_regime_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason);
      _regime_mark_opened_for_validation(regimeEventId, direction, signalTime, signalIndex);
      g_lastRegimeDirection = direction;
      g_lastRegimeConfirmedEventId = regimeEventId;
      g_lastRegimeSignalIndex = signalIndex;
      g_lastRegimeSignalTime = signalTime;
      g_lastRegimeConfirmedDirection = direction;
      g_lastRegimeConfirmedSignalTime = signalTime;
      _regime_clear_pending_state();
   }
   else if(_heartbeat_due(g_lastRegimeResolvedPostTime))
   {
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, "heartbeat"))
         g_lastRegimeResolvedPostTime = _timer_now();
   }
}

void ScanAndLogLatest(string reason)
{
   string direction, trendName;
   int signalIndex;
   datetime signalTime;
   double entryPrice;
   string regimeDirection = "";
   string regimeSourceName = "";
   int regimeSignalIndex = -1;
   datetime regimeSignalTime = 0;
   double regimeEntryPrice = 0.0;
   bool hasBufferRegime = _find_current_atomic_regime_from_buffers(
      "",
      regimeDirection,
      regimeSignalIndex,
      regimeSignalTime,
      regimeEntryPrice,
      regimeSourceName
   );

   if(!_find_latest_atomic_signal(direction, signalIndex, signalTime, entryPrice, trendName))
   {
      if(InpLogNoneSignals)
         Print("AtomicBridge latest_signal NONE reason=", reason, " symbol=", Symbol(), " tf=", _tf_to_string(Period()));
      _debug_print_atomic_objects();
      _regime_signal_probe_scan(reason, hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
      _regime_validate_delayed_open_trade(hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);
      _regime_validate_direct_sh0_open_trade(hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);
      if(!hasBufferRegime)
         _regime_cancel_pending_delay("signal_missing_before_open", hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);
      if(hasBufferRegime && g_atomicRegimeModeEnabledRuntime)
      {
         if(InpLogRegimeBuffer)
         {
            PrintFormat(
               "AtomicBridge regime_signal reason=%s symbol=%s tf=%s dir=%s start_bar=%s entry=%s source='%s'",
               reason,
               Symbol(),
               _tf_to_string(Period()),
               regimeDirection,
               _fmt_time(regimeSignalTime),
               _fmt_price(regimeEntryPrice),
               regimeSourceName
            );
         }
         _handle_regime_event(reason, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName, "", 0.0, 0.0);
      }
      return;
   }

   if(!hasBufferRegime && InpRegimeUseAtomicSignalAsTieBreak && StringLen(direction) > 0)
   {
      hasBufferRegime = _find_current_atomic_regime_from_buffers(
         direction,
         regimeDirection,
         regimeSignalIndex,
         regimeSignalTime,
         regimeEntryPrice,
         regimeSourceName
      );
   }
   _regime_validate_delayed_open_trade(hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);
      _regime_validate_direct_sh0_open_trade(hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);
   if(!hasBufferRegime)
      _regime_cancel_pending_delay("signal_missing_before_open", hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);

   double sl, tp1, tp2, tp3, tp4, tp5;
   _find_atomic_levels(direction, signalIndex, sl, tp1, tp2, tp3, tp4, tp5);

   string eventId = StringFormat("%s|%s|%d|%I64d", Symbol(), direction, signalIndex, (long)signalTime);
   bool firstObservation = (StringLen(g_lastEventId) <= 0 || g_lastSignalTime <= 0);
   double latestAtomicTp = _select_direct_tp(tp1, tp2, tp3, tp4, tp5);
   double atomicGeometrySl = sl;
   string atomicGeometryBuild = "atomic_indicator_sl";
   bool atomicSlOk = _atomic_effective_sl_for_mode(direction, entryPrice, sl, latestAtomicTp, atomicGeometrySl, atomicGeometryBuild);
   string geometryReason = "";
   bool geometryOk = atomicSlOk && _atomic_signal_geometry_valid(direction, entryPrice, atomicGeometrySl, tp1, tp2, tp3, tp4, tp5, geometryReason);
   int latestHalfTpIndex = MathMax(1, MathMin(5, g_directMt4HalfBeTpIndexRuntime));
   bool latestAtomicHalfEnabled = (latestHalfTpIndex < g_directMt4TpIndexRuntime);
   double latestAtomicHalf = latestAtomicHalfEnabled ? _direct_tp_by_index(latestHalfTpIndex, tp1, tp2, tp3, tp4, tp5) : 0.0;

   string visualDirection = direction;
   double visualSl = atomicGeometrySl;
   double visualTp = latestAtomicTp;
   double visualHalf = latestAtomicHalf;
   string visualMode = (g_atomicDirectRiskGeometryRuntime ? "RGEOM" : "INDIC");
   if(g_atomicInvertTradeModeRuntime && (direction == "BUY" || direction == "SELL") && entryPrice > 0.0 && atomicGeometrySl > 0.0 && latestAtomicTp > 0.0)
   {
      string invDir = "";
      double invSl = 0.0;
      double invTp = 0.0;
      string invDetail = "";
      if(_atomic_build_inverted_geometry(direction, entryPrice, atomicGeometrySl, latestAtomicTp, invDir, invSl, invTp, invDetail))
      {
         visualDirection = invDir;
         visualSl = invSl;
         visualTp = invTp;
         visualHalf = _atomic_invert_hcbe_price(invDir, entryPrice, invTp);
         visualMode = visualMode + "_INV";
      }
   }

   if(StringLen(visualDirection) > 0 && entryPrice > 0.0 && visualSl > 0.0 && visualTp > 0.0)
   {
      g_latestAtomicLevelDirection = visualDirection;
      g_latestAtomicLevelEntry = entryPrice;
      g_latestAtomicLevelSl = visualSl;
      g_latestAtomicLevelTp = visualTp;
      g_latestAtomicLevelHalf = visualHalf;
      g_latestAtomicLevelSignalTime = signalTime;
      g_latestAtomicLevelMode = visualMode;
   }
   if(InpLogOnlyOnChange && eventId == g_lastEventId)
   {
      if(g_atomicModeEnabledRuntime && StringLen(direction) > 0 && atomicGeometrySl > 0.0 && tp1 > 0.0 && geometryOk && _heartbeat_due(g_lastResolvedPostTime))
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, "heartbeat"))
            g_lastResolvedPostTime = _timer_now();
      }
      _regime_signal_probe_scan("heartbeat", hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
      if(!hasBufferRegime)
         _regime_cancel_pending_delay("signal_missing_before_open", hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);
      if(hasBufferRegime && g_atomicRegimeModeEnabledRuntime)
         _handle_regime_event("heartbeat", regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName, direction, entryPrice, sl);
      return;
   }

   g_lastEventId = eventId;
   g_lastSignalTime = signalTime;

   PrintFormat(
      "AtomicBridge latest_signal reason=%s symbol=%s tf=%s dir=%s idx=%d bar=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s tp4=%s tp5=%s trend='%s'",
      reason,
      Symbol(),
      _tf_to_string(Period()),
      direction,
      signalIndex,
      _fmt_time(signalTime),
      _fmt_price(entryPrice),
      _fmt_price(sl),
      _fmt_price(tp1),
      _fmt_price(tp2),
      _fmt_price(tp3),
      _fmt_price(tp4),
      _fmt_price(tp5),
      trendName
   );

   if(atomicGeometrySl <= 0.0 || tp1 <= 0.0)
      Print("AtomicBridge warning: missing SL/TP data for latest signal. Check object naming/scan timing.");
   else if(!geometryOk)
   {
      double livePx = (direction == "BUY" ? MarketInfo(Symbol(), MODE_ASK) : MarketInfo(Symbol(), MODE_BID));
      PrintFormat(
         "AtomicBridge warning: invalid signal geometry; not posting reason=%s dir=%s signal_entry=%s live_px=%s sl=%s final_tp=%s",
         geometryReason,
         direction,
         _fmt_price(entryPrice),
         _fmt_price(livePx),
         _fmt_price(sl),
         _fmt_price(_atomic_final_tp(tp1, tp2, tp3, tp4, tp5))
      );
   }

   if(g_atomicModeEnabledRuntime && StringLen(direction) > 0 && atomicGeometrySl > 0.0 && tp1 > 0.0 && geometryOk)
   {
      if(reason == "init" || reason == "init_retry" || firstObservation)
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason))
            g_lastResolvedPostTime = _timer_now();
         if((reason == "init" || reason == "init_retry") && InpSendInitialConfirmedOnStart)
         {
            _post_atomic_bridge_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason);
            g_lastConfirmedEventId = eventId;
         }
         else if(firstObservation && reason != "init" && reason != "init_retry")
         {
            Print("AtomicBridge first_observation resolved only; confirmed_signal suppressed reason=", reason, " event=", eventId);
         }
      }
      else if(eventId != g_lastConfirmedEventId)
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason))
            g_lastResolvedPostTime = _timer_now();
         _post_atomic_bridge_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason);
         g_lastConfirmedEventId = eventId;
      }
   }

   if(hasBufferRegime && g_atomicRegimeModeEnabledRuntime)
   {
      _regime_signal_probe_scan(reason, hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
      if(InpLogRegimeBuffer)
      {
         PrintFormat(
            "AtomicBridge regime_signal reason=%s symbol=%s tf=%s dir=%s start_bar=%s entry=%s source='%s'",
            reason,
            Symbol(),
            _tf_to_string(Period()),
            regimeDirection,
            _fmt_time(regimeSignalTime),
            _fmt_price(regimeEntryPrice),
            regimeSourceName
         );
      }
      _handle_regime_event(reason, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName, direction, entryPrice, sl);
   }
   else
   {
      _regime_signal_probe_scan(reason, hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
   }
}

int OnInit()
{
   int poll = MathMax(1, InpPollSeconds);
   EventSetTimer(poll);
   g_lastTickLocal = TimeLocal();
   g_directMt4EnabledRuntime = InpDirectMt4ExecutionEnabled;
   g_fileBridgeMt5EnabledRuntime = InpFileBridgeMt5Enabled;
   g_proTradePostEnabledRuntime = InpEnableProTradePost;
   g_atomicModeEnabledRuntime = InpEnableAtomicMode;
   g_atomicRegimeModeEnabledRuntime = InpEnableAtomicRegimeMode;
   string priority = _lower_copy(_trim(InpDirectMt4Priority));
   g_directMt4PriorityDirectFirst = (priority != "post_first" && priority != "quantdesk_first");
   g_directMt4LotRuntime = MathMax(0.01, InpDirectMt4Lot);
   g_accountRiskPerTradePctRuntime = MathMax(0.0, InpAccountRiskPerTradePct);
   g_directMt4MaxSpreadRuntime = MathMax(0, InpDirectMt4MaxSpreadPoints);
   g_directMt4MaxSpreadToSlPctRuntime = MathMax(0.0, InpDirectMt4MaxSpreadToSlPct);
   g_directMt4DailyProfitTargetRuntime = MathMax(0.0, InpDirectMt4DailyProfitTarget);
   g_directMt4DailyLossTargetRuntime = MathMax(0.0, InpDirectMt4DailyLossTarget);
   g_directMt4TpIndexRuntime = MathMax(1, MathMin(5, InpDirectMt4TpIndex));
   g_atomicDirectRiskGeometryRuntime = InpAtomicDirectRiskGeometryEnabled;
   g_atomicDirectTargetRRuntime = _atomic_supported_target_r(InpAtomicDirectTargetR);
   g_atomicInvertTradeModeRuntime = InpAtomicInvertTradeMode;
   g_atomicInvertHcBeProgressPctRuntime = (InpAtomicInvertHcBeProgressPct == 25 || InpAtomicInvertHcBeProgressPct == 50 || InpAtomicInvertHcBeProgressPct == 75) ? InpAtomicInvertHcBeProgressPct : 0;
   g_atomicInvertTargetRRuntime = _atomic_clamp_invert_target_r(InpAtomicInvertTargetR);
   g_directMt4HalfBeRRuntime = MathMax(0.0, InpDirectMt4HalfBeR);
   g_directMt4HalfBeTpIndexRuntime = MathMax(1, MathMin(5, InpDirectMt4HalfBeTpIndex));
   g_regimeDirectMt4HalfBeRRuntime = MathMax(0.0, InpRegimeDirectMt4HalfBeR);
   g_regimeRRRuntime = MathMax(0.1, InpRegimeRR);
   g_regimeFinalRiskScalePctRuntime = MathMax(1.0, MathMin(200.0, InpRegimeFinalRiskScalePct));
   g_regimePipSlModeRuntime = InpRegimePipSlModeEnabled;
   g_regimePipSlPipsRuntime = MathMax(0.0, InpRegimePipSlPips);
   g_regimeStructuralSwingSlModeRuntime = InpRegimeStructuralSwingSlModeEnabled;
   g_regimeSignalOpenSlModeRuntime = InpRegimeSignalOpenSlModeEnabled;
   if(g_regimeSignalOpenSlModeRuntime)
   {
      g_regimePipSlModeRuntime = false;
      g_regimeStructuralSwingSlModeRuntime = false;
   }
   else if(g_regimeStructuralSwingSlModeRuntime)
      g_regimePipSlModeRuntime = false;
   g_regimeUseClosedBarRuntime = InpRegimeUseClosedBar;
   g_regimeDelayValidationRuntime = InpRegimeDelayValidationMode;
   g_regimeCloseIfVanishesRuntime = InpRegimeCloseIfSignalVanishesAfterOpen;
   g_regimeConfirmDelaySecondsRuntime = MathMax(-1, InpRegimeConfirmDelaySeconds);
   g_regimeOpenPreWindowSignalRuntime = InpRegimeOpenPreWindowSignal;
   g_directMt4AllowedWindowsRuntime = _trim(InpDirectMt4AllowedTradeWindowsGmt);
   g_directMt4NoTradeWindowsRuntime = _trim(InpDirectMt4NoTradeWindowsGmt);
   g_directMt4UtcEventBlockTimesRuntime = _trim(InpDirectMt4UtcEventBlockTimesGmt);
   g_directMt4UtcEventBlockRadiusRuntime = MathMax(0, MathMin(60, InpDirectMt4UtcEventBlockRadiusMinutes));
   g_gannFollowModeRuntime = InpGannFollowModeEnabled;
   g_gannFollowTfRuntime = _gann_follow_sanitize_tf(InpGannFollowTimeframe);
   g_ftmoModeRuntime = (InpAdvancedAccountRiskEnabled && (InpAccountRiskDailyLossLimitPct > 0.0 || InpAccountRiskMaxDrawdownPct > 0.0));
   g_riskLotOnlyRuntime = (InpAdvancedAccountRiskEnabled && !g_ftmoModeRuntime);
   g_auditEnabledRuntime = (InpDirectMt4AuditCsv || InpDirectMt4PositionProbeAudit || InpRegimeSignalProbeAudit || InpAccountRiskAuditEnabled);
   _direct_history_cursor_init();
   Print(
      "AtomicBridge BUILD=", ATOMIC_BRIDGE_BUILD,
      " indicator=", InpIndicatorName,
      " regimeLabel=", InpRegimeIndicatorName,
      " regimeBufferSource=", InpIndicatorName,
      " symbol=", Symbol(),
      " tf=", _tf_to_string(Period()),
      " poll=", poll,
      " logPost=", InpLogPostResponses,
      " regimeSignalBuffers=", (InpRegimeUseTrendSignalBuffers ? "true" : "false"),
      " upSignal=", InpRegimeUpTrendSignalBuffer,
      " dnSignal=", InpRegimeDnTrendSignalBuffer,
      " stopFallback=", (InpRegimeUseTrendStopBuffers ? "true" : "false"),
      " regimeExecMode=" + (g_regimeDelayValidationRuntime ? "delay_validate" : "direct") + " closeIfVanish=" + (g_regimeCloseIfVanishesRuntime ? "true" : "false"),
      " confirmDelaySec=", g_regimeConfirmDelaySecondsRuntime,
      " stableSec=", InpRegimeConfirmStableSeconds,
      " maxConfirmShift=", InpRegimeMaxConfirmShift,
      " atomicTpIndex=", g_directMt4TpIndexRuntime,
      " atomicSlMode=", (g_atomicDirectRiskGeometryRuntime ? "r_geometry" : "indicator"),
      " atomicTargetR=", DoubleToString(g_atomicDirectTargetRRuntime, 2),
      " atomicHalfTpIndex=", g_directMt4HalfBeTpIndexRuntime,
      " atomicFallbackHalfR=", DoubleToString(g_directMt4HalfBeRRuntime, 2),
      " regimeHalfR=", DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2),
      " gannFollowTf=", _gann_follow_tf_text()
   );
   Print(
      "AtomicBridge BUILD riskcfg autoLot=", (InpDirectMt4AutoLotEnabled ? "true" : "false"),
      " autoLotDailyAtrPeriod=", InpDirectMt4AutoLotDailyAtrPeriod,
      " autoLotMax=", DoubleToString(InpDirectMt4AutoLotMax, 2),
      " regimeMinRiskPct=", DoubleToString(InpRegimeMinRiskPricePct, 5),
      " regimeMaxRiskPct=", DoubleToString(InpRegimeMaxRiskPricePct, 5),
      " regimeSlWiden=", (InpRegimeSlWidenEnabled ? "true" : "false"),
      " regimeSlWidenPct=", DoubleToString(InpRegimeSlWidenPct, 1),
      " regimeFinalRiskScalePct=", DoubleToString(g_regimeFinalRiskScalePctRuntime, 1),
      " regimePipSlMode=", (g_regimePipSlModeRuntime ? "true" : "false"),
      " regimePipSlPips=", DoubleToString(g_regimePipSlPipsRuntime, 1),
      " regimeSignalOpenSlMode=", (g_regimeSignalOpenSlModeRuntime ? "true" : "false"),
      " dailyProfitTarget=", DoubleToString(g_directMt4DailyProfitTargetRuntime, 2),
      " dailyLossTarget=", DoubleToString(g_directMt4DailyLossTargetRuntime, 2),
      " atomicInvert=", (g_atomicInvertTradeModeRuntime ? "true" : "false"),
      " atomicInvertTarget=", _atomic_invert_target_text(),
      " atomicInvertHcbePct=", g_atomicInvertHcBeProgressPctRuntime,
      " positionProbe=", (InpDirectMt4PositionProbeAudit ? "true" : "false"),
      " probeSec=", InpDirectMt4PositionProbeIntervalSeconds
   );
   Print(
      "AtomicBridge account_risk mode=", (g_ftmoModeRuntime ? "FTMO" : (g_riskLotOnlyRuntime ? "RISKLOT_ONLY" : "OFF")),
      " effectiveMagic=", _direct_magic(),
      " riskPerTradePct=", DoubleToString(_account_risk_per_trade_pct(), 3),
      " atrExposurePct=", DoubleToString(InpAccountRiskDailyAtrExposurePct, 3),
      " maxPortfolioPct=", DoubleToString(InpAccountRiskMaxPortfolioPct, 3),
      " dailyLossLimitPct=", DoubleToString(_effective_daily_loss_limit_pct(), 3),
      " maxDrawdownPct=", DoubleToString(_effective_max_drawdown_pct(), 3),
      " maxMarginUsagePct=", DoubleToString(InpAccountRiskMaxMarginUsagePct, 3),
      " initialBalanceOverride=", DoubleToString(InpAccountRiskInitialBalanceOverride, 2),
      " dayResetHourGmt=", MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt))
   );
   _file_bridge_write_init_marker();
   if(g_proTradePostEnabledRuntime)
   {
      _post_atomic_bridge_event("register", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", "init");
      g_lastRegisterPostTime = _timer_now();
   }
   g_initialSetupRetryUntil = _timer_now() + MathMax(0, InpInitialSetupRetrySeconds);
   if(InpLogOnInit)
      ScanAndLogLatest("init");
   _draw_dashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpSendUnregisterOnDeinit && g_proTradePostEnabledRuntime)
   {
      string why = "deinit_" + IntegerToString(reason);
      _post_atomic_bridge_event("unregister", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", why);
      if(InpEnableRegimeChangePost)
         _post_atomic_regime_event("unregister", "", -1, 0, 0.0, 0.0, 0.0, "", why);
   }
   if(InpLogPostResponses || InpLogNoneSignals || InpLogRegimeBuffer)
      Print("AtomicBridge uninit reason=", reason);
   _delete_dash();
   _delete_regime_trade_levels();
}

void OnTimer()
{
   _account_risk_enforce_breach();
   _account_risk_audit_write("snapshot", "periodic_health", true);
   _manage_direct_mt4_positions();
   _direct_event_block_pending_try("timer_utc_event_block_open_check");
   _regime_window_pending_try("timer_window_open_check");
   MaybePostRegisterHeartbeat("heartbeat");
   if(InpLogOnInit && StringLen(g_lastEventId) <= 0 && _timer_now() <= g_initialSetupRetryUntil)
   {
      ScanAndLogLatest("init_retry");
      return;
   }
   ScanAndLogLatest("timer");
   _draw_atomic_regime_trade_levels();
   _draw_dashboard();
}

void OnTick()
{
   _account_risk_enforce_breach();
   g_lastTickLocal = TimeLocal();
   _manage_direct_mt4_positions();
   _direct_event_block_pending_try("tick_utc_event_block_open_check");
   _regime_window_pending_try("tick_window_open_check");
   _draw_atomic_regime_trade_levels();
   _draw_dashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT)
      return;
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(StringFind(sparam, DASH_PREFIX + "EDIT_") == 0)
         _apply_dashboard();
      return;
   }
   uint clickNow = GetTickCount();
   if(sparam == g_lastDashClickObject && clickNow - g_lastDashClickMs < 800)
      return;
   g_lastDashClickObject = sparam;
   g_lastDashClickMs = clickNow;
   if(ObjectFind(0, sparam) >= 0)
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   if(sparam == DASH_PREFIX + "BTN_DASH_COLLAPSE")
      _set_dashboard_collapsed(true);
   else if(sparam == DASH_PREFIX + "BTN_DASH_EXPAND")
      _set_dashboard_collapsed(false);
   else if(sparam == DASH_PREFIX + "BTN_DIRECT")
   {
      g_directMt4EnabledRuntime = !g_directMt4EnabledRuntime;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_POST")
   {
   if(g_proTradePostEnabledRuntime)
      {
         _post_atomic_bridge_event("unregister", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", "dashboard_post_off");
         _post_atomic_regime_event("unregister", "", -1, 0, 0.0, 0.0, 0.0, "", "dashboard_post_off");
         g_proTradePostEnabledRuntime = false;
         g_lastPostDisabledMs = clickNow;
         Print("AtomicBridge dashboard ProTrade POST disabled");
      }
      else
      {
         if(g_lastPostDisabledMs > 0 && clickNow - g_lastPostDisabledMs < 10000)
         {
            Print("AtomicBridge dashboard ProTrade POST enable ignored reason=recent_disable_guard");
            _draw_dashboard();
            ChartRedraw(0);
            return;
         }
         g_proTradePostEnabledRuntime = true;
         _post_atomic_bridge_event("register", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", "dashboard_post_on");
         _post_atomic_regime_event("register", "", -1, 0, 0.0, 0.0, 0.0, "", "dashboard_post_on");
         g_lastRegisterPostTime = _timer_now();
         Print("AtomicBridge dashboard ProTrade POST enabled");
      }
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_PRIORITY")
   {
      g_directMt4PriorityDirectFirst = !g_directMt4PriorityDirectFirst;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_HALFBE")
   {
      g_directMt4HalfBeTpIndexRuntime++;
      if(g_directMt4HalfBeTpIndexRuntime > 5)
         g_directMt4HalfBeTpIndexRuntime = 1;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_ATOMIC_MODE")
   {
      g_atomicModeEnabledRuntime = !g_atomicModeEnabledRuntime;
      Print("AtomicBridge dashboard Atomic mode=", (g_atomicModeEnabledRuntime ? "ON" : "OFF"));
      _draw_atomic_regime_trade_levels();
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_MODE")
   {
      g_atomicRegimeModeEnabledRuntime = !g_atomicRegimeModeEnabledRuntime;
      Print("AtomicBridge dashboard AtomicRegime mode=", (g_atomicRegimeModeEnabledRuntime ? "ON" : "OFF"));
      _draw_atomic_regime_trade_levels();
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_SHIFT")
   {
      g_regimeUseClosedBarRuntime = !g_regimeUseClosedBarRuntime;
      Print("AtomicBridge dashboard regime closed-bar mode=", (g_regimeUseClosedBarRuntime ? "shift_1_closed_bar" : "shift_0_live_bar"));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_DELAY_MODE")
   {
      g_regimeDelayValidationRuntime = !g_regimeDelayValidationRuntime;
      _regime_clear_pending_state();
      g_lastRegimeDelayOpenedEventId = "";
      g_lastRegimeDelayOpenedDirection = "";
      g_lastRegimeDelayOpenedSignalTime = 0;
      Print("AtomicBridge dashboard AtomicRegime execution mode=", (g_regimeDelayValidationRuntime ? "delay_validate" : "direct"), " close_if_vanish=", (g_regimeCloseIfVanishesRuntime ? "true" : "false"));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_ATOMIC_TP")
   {
      g_directMt4TpIndexRuntime++;
      if(g_directMt4TpIndexRuntime > 5)
         g_directMt4TpIndexRuntime = 1;
      Print("AtomicBridge dashboard Atomic final TP leg=", g_directMt4TpIndexRuntime);
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_ATOMIC_SL_MODE")
   {
      g_atomicDirectRiskGeometryRuntime = !g_atomicDirectRiskGeometryRuntime;
      Print("AtomicBridge dashboard Atomic SL mode=", (g_atomicDirectRiskGeometryRuntime ? "r_geometry" : "indicator"));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_ATOMIC_RR")
   {
      g_atomicDirectTargetRRuntime = _atomic_next_target_r(g_atomicDirectTargetRRuntime);
      Print("AtomicBridge dashboard Atomic target R=", DoubleToString(g_atomicDirectTargetRRuntime, 1));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_ATOMIC_INVERT")
   {
      g_atomicInvertTradeModeRuntime = !g_atomicInvertTradeModeRuntime;
      if(g_atomicInvertTradeModeRuntime)
      {
         g_atomicInvertTargetRRuntime = 0.0;
         g_atomicInvertHcBeProgressPctRuntime = 0;
      }
      Print("AtomicBridge dashboard Atomic invert mode=", (g_atomicInvertTradeModeRuntime ? "ON" : "OFF"),
            " note=signal_math_unchanged_direction_and_sl_tp_swapped");
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_ATOMIC_INV_TP")
   {
      if(g_atomicInvertTradeModeRuntime)
      {
         if(g_atomicInvertTargetRRuntime <= 0.0)
            g_atomicInvertTargetRRuntime = 0.50;
         else if(g_atomicInvertTargetRRuntime < 1.00)
            g_atomicInvertTargetRRuntime = 1.00;
         else if(g_atomicInvertTargetRRuntime < 1.50)
            g_atomicInvertTargetRRuntime = 1.50;
         else if(g_atomicInvertTargetRRuntime < 2.00)
            g_atomicInvertTargetRRuntime = 2.00;
         else if(g_atomicInvertTargetRRuntime < 3.00)
            g_atomicInvertTargetRRuntime = 3.00;
         else
            g_atomicInvertTargetRRuntime = 0.0;
         g_atomicInvertTargetRRuntime = _atomic_clamp_invert_target_r(g_atomicInvertTargetRRuntime);
         Print("AtomicBridge dashboard Atomic invert target=", _atomic_invert_target_text());
      }
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_ATOMIC_INV_HC")
   {
      if(g_atomicInvertTradeModeRuntime)
      {
         if(g_atomicInvertHcBeProgressPctRuntime <= 0)
            g_atomicInvertHcBeProgressPctRuntime = 25;
         else if(g_atomicInvertHcBeProgressPctRuntime == 25)
            g_atomicInvertHcBeProgressPctRuntime = 50;
         else if(g_atomicInvertHcBeProgressPctRuntime == 50)
            g_atomicInvertHcBeProgressPctRuntime = 75;
         else
            g_atomicInvertHcBeProgressPctRuntime = 0;
         Print("AtomicBridge dashboard Atomic invert HCBE pct=", g_atomicInvertHcBeProgressPctRuntime);
      }
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_FTMO")
   {
      g_ftmoModeRuntime = !g_ftmoModeRuntime;
      if(g_ftmoModeRuntime)
         g_riskLotOnlyRuntime = false;
      _account_risk_cache_invalidate();
      Print("AtomicBridge dashboard risk mode=", (g_ftmoModeRuntime ? "FTMO" : (g_riskLotOnlyRuntime ? "RISKLOT_ONLY" : "OFF")));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_RISKLOT")
   {
      g_riskLotOnlyRuntime = !g_riskLotOnlyRuntime;
      if(g_riskLotOnlyRuntime)
         g_ftmoModeRuntime = false;
      _account_risk_cache_invalidate();
      Print("AtomicBridge dashboard risk mode=", (g_ftmoModeRuntime ? "FTMO" : (g_riskLotOnlyRuntime ? "RISKLOT_ONLY" : "OFF")));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_RISK_APPLY")
   {
      g_riskApplyFeedbackUntilMs = GetTickCount() + 1200;
      _apply_dashboard();
      _file_bridge_write_init_marker();
      Print("AtomicBridge risk apply republished bridge init risk_pct=", DoubleToString(_account_risk_per_trade_pct(), 3), " bridge_enabled=", g_fileBridgeMt5EnabledRuntime ? "true" : "false");
   }
   else if(sparam == DASH_PREFIX + "BTN_DAILY_PROFIT")
   {
      _apply_dashboard();
   }
   else if(sparam == DASH_PREFIX + "BTN_UTC_EVENT_APPLY")
   {
      _apply_dashboard();
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_PIP_SL")
   {
      _apply_dashboard();
      g_regimePipSlModeRuntime = !g_regimePipSlModeRuntime;
      if(g_regimePipSlModeRuntime)
      {
         g_regimeStructuralSwingSlModeRuntime = false;
         g_regimeSignalOpenSlModeRuntime = false;
      }
      g_regimeHistoryLevelsHash = "";
      Print("AtomicBridge dashboard AtomicRegime pip SL mode=", (g_regimePipSlModeRuntime ? "ON" : "OFF"), " pips=", DoubleToString(g_regimePipSlPipsRuntime, 2));
      _draw_atomic_regime_trade_levels();
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_STRUCT_SL")
   {
      _apply_dashboard();
      g_regimeStructuralSwingSlModeRuntime = !g_regimeStructuralSwingSlModeRuntime;
      if(g_regimeStructuralSwingSlModeRuntime)
      {
         g_regimePipSlModeRuntime = false;
         g_regimeSignalOpenSlModeRuntime = false;
      }
      g_regimeHistoryLevelsHash = "";
      Print("AtomicBridge dashboard AtomicRegime structural swing SL mode=", (g_regimeStructuralSwingSlModeRuntime ? "ON" : "OFF"),
            " lookback=", InpRegimeSwingLookbackBars,
            " left=", InpRegimeSwingLeftBars,
            " right=", InpRegimeSwingRightBars,
            " max_age=", InpRegimeSwingMaxAgeBars,
            " max_risk_atr=", DoubleToString(InpRegimeSwingMaxRiskAtr, 2),
            " buffer_atr=", DoubleToString(InpRegimeSwingBufferAtr, 2),
            " prefer_strongest=", (InpRegimeSwingPreferStrongest ? "true" : "false"),
            " fallback_extreme=", (InpRegimeSwingFallbackToExtreme ? "true" : "false"));
      _draw_atomic_regime_trade_levels();
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_SIGOPEN_SL")
   {
      _apply_dashboard();
      g_regimeSignalOpenSlModeRuntime = !g_regimeSignalOpenSlModeRuntime;
      if(g_regimeSignalOpenSlModeRuntime)
      {
         g_regimePipSlModeRuntime = false;
         g_regimeStructuralSwingSlModeRuntime = false;
      }
      g_regimeHistoryLevelsHash = "";
      Print("AtomicBridge dashboard AtomicRegime signal-open SL mode=", (g_regimeSignalOpenSlModeRuntime ? "ON" : "OFF"),
            " note=signal_math_unchanged_only_sl_tp_geometry_changes");
      _draw_atomic_regime_trade_levels();
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_MT5_PUB")
   {
      g_fileBridgeMt5EnabledRuntime = !g_fileBridgeMt5EnabledRuntime;
      Print("AtomicBridge dashboard MT5 file bridge=", (g_fileBridgeMt5EnabledRuntime ? "ON" : "OFF"));
      if(g_fileBridgeMt5EnabledRuntime)
         _file_bridge_write_init_marker();
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_GANN_FOLLOW")
   {
      g_gannFollowModeRuntime = !g_gannFollowModeRuntime;
      string gd, det;
      datetime gt = 0;
      if(_gann_follow_read_state(gd, gt, det))
      {
         g_gannFollowLastDirection = gd;
         g_gannFollowLastSignalTime = gt;
      }
      else
         g_gannFollowLastDirection = "NONE";
      g_gannFollowLastDetail = det;
      Print("AtomicBridge dashboard Gann follow mode=", (g_gannFollowModeRuntime ? "ON" : "OFF"), " ", det);
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_GANN_TF")
   {
      _gann_follow_cycle_tf();
      string gd, det;
      datetime gt = 0;
      if(_gann_follow_read_state(gd, gt, det))
      {
         g_gannFollowLastDirection = gd;
         g_gannFollowLastSignalTime = gt;
      }
      else
         g_gannFollowLastDirection = "NONE";
      g_gannFollowLastReadGmt = TimeGMT();
      g_gannFollowLastDetail = det;
      Print("AtomicBridge dashboard Gann follow TF=", _gann_follow_tf_text(), " ", det);
      _draw_dashboard();
      ChartRedraw(0);
   }   else if(sparam == DASH_PREFIX + "BTN_AUDIT")
   {
      g_auditEnabledRuntime = !g_auditEnabledRuntime;
      Print("AtomicBridge dashboard audit=", (g_auditEnabledRuntime ? "ON" : "OFF"));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_PREWIN")
   {
      g_regimeOpenPreWindowSignalRuntime = !g_regimeOpenPreWindowSignalRuntime;
      if(!g_regimeOpenPreWindowSignalRuntime)
         _regime_window_pending_clear();
      Print("AtomicBridge dashboard AtomicRegime pre-window execution=", (g_regimeOpenPreWindowSignalRuntime ? "ON" : "OFF"));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_APPLY")
      _apply_dashboard();
}
