//+------------------------------------------------------------------+
//| Atomic Bridge MT4 EA                                             |
//| Reads Atomic chart objects and logs latest direction/entry/SL/TPs |
//| for ProTrade integration mapping.                                |
//+------------------------------------------------------------------+
#property strict

#define ATOMIC_BRIDGE_BUILD "2026-06-25.0330-atomic-r-geometry"

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
input int    InpDirectMt4Slippage = 30;
input int    InpDirectMt4MaxSpreadPoints = 0;
input string InpDirectMt4AllowedTradeWindowsGmt = "";
input string InpDirectMt4NoTradeWindowsGmt = "21:55-22:10";
input bool   InpDirectMt4CloseReverse = true;
input int    InpDirectMt4TpIndex = 5;
input bool   InpAtomicDirectRiskGeometryEnabled = false; // false=indicator SL; true=derive SL from selected TP leg and target R.
input double InpAtomicDirectTargetR = 2.0; // Supported dashboard choices: 0.5, 1.0, 2.0, 3.0.
input double InpDirectMt4HalfBeR = 2.0;
input int    InpDirectMt4HalfBeTpIndex = 2;
input double InpRegimeDirectMt4HalfBeR = 0.0; // 0=disabled by design; AtomicRegime exits fully at InpRegimeRR
input bool   InpDirectMt4AuditCsv = true;
input int    InpDirectMt4HistoryAuditSeconds = 2;
input bool   InpDirectMt4PositionProbeAudit = true;
input int    InpDirectMt4PositionProbeIntervalSeconds = 30;
input bool   InpDirectMt4PositionProbeWriteOnChange = true;
input bool   InpRegimeSignalProbeAudit = true;
input int    InpRegimeSignalProbeIntervalSeconds = 30;
input bool   InpRegimeSignalProbeWriteOnChange = true;
input int    InpRegimeSignalProbeMaxShift = 20;
input bool   InpShowAtomicRegimeTradeLevels = true;
input int    InpAtomicRegimeTradeLevelLabelBars = 8;
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
input double InpRegimeFinalRiskScalePct = 75.0; // 100=unchanged; 75 trims final AtomicRegime SL/TP distance by 25%.
input bool   InpRegimeUseTrendSignalBuffers = true;
input int    InpRegimeUpTrendSignalBuffer = 2;
input int    InpRegimeDnTrendSignalBuffer = 3;
input bool   InpRegimeUseTrendStopBuffers = false;
input int    InpRegimeUpTrendStopBuffer = 0;
input int    InpRegimeDnTrendStopBuffer = 1;
input bool   InpRegimeUseAtomicSignalAsTieBreak = true;
input bool   InpRegimeUseClosedBar = true;
input int    InpRegimeBufferLookbackBars = 200;
input bool   InpRegimeDelayValidationMode = false; // false=direct shift-1 execution; true=live delay + vanish validation.
input int    InpRegimeConfirmDelaySeconds = 300; // 0=confirm immediately; -1=use legacy stable seconds.
input int    InpRegimeConfirmStableSeconds = 5;
input int    InpRegimeMaxConfirmShift = 1;
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
string   g_lastRegimeDelayOpenedEventId = "";
datetime g_lastRegimeDelayOpenedSignalTime = 0;
string   g_lastRegimeDelayOpenedDirection = "";
string   g_pendingRegimeWindowEventId = "";
string   g_pendingRegimeWindowDirection = "";
datetime g_pendingRegimeWindowSignalTime = 0;
datetime g_pendingRegimeWindowFirstSeen = 0;
double   g_pendingRegimeWindowSl = 0.0;
double   g_pendingRegimeWindowTp = 0.0;
string   g_pendingRegimeWindowHalfLabel = "";
string   g_lastDirectMt4EventId = "";
bool     g_proTradePostEnabledRuntime = true;
bool     g_directMt4EnabledRuntime = false;
bool     g_directMt4PriorityDirectFirst = true;
bool     g_atomicModeEnabledRuntime = true;
bool     g_atomicRegimeModeEnabledRuntime = true;
double   g_directMt4LotRuntime = 0.0;
int      g_directMt4MaxSpreadRuntime = 0;
int      g_directMt4TpIndexRuntime = 5;
bool     g_atomicDirectRiskGeometryRuntime = false;
double   g_atomicDirectTargetRRuntime = 2.0;
double   g_directMt4HalfBeRRuntime = 0.0;
int      g_directMt4HalfBeTpIndexRuntime = 2;
double   g_regimeDirectMt4HalfBeRRuntime = 0.0;
double   g_regimeRRRuntime = 0.0;
double   g_regimeFinalRiskScalePctRuntime = 100.0;
bool     g_regimeUseClosedBarRuntime = true;
bool     g_regimeDelayValidationRuntime = false;
int      g_regimeConfirmDelaySecondsRuntime = 300;
bool     g_regimeOpenPreWindowSignalRuntime = false;
string   g_directMt4AllowedWindowsRuntime = "";
string   g_directMt4NoTradeWindowsRuntime = "";
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
datetime g_lastTickLocal = 0;
string   DASH_PREFIX = "ATOMIC_BRIDGE_DASH_";
string   REGIME_LEVEL_PREFIX = "ATOMIC_REGIME_TRADE_LEVEL_";
uint     g_lastAccountRiskGuardMs = 0;
double   g_accountRiskLockValue = 0.0;

bool _account_risk_enabled_runtime()
{
   return (g_ftmoModeRuntime || g_riskLotOnlyRuntime);
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
   g_pendingRegimeWindowHalfLabel = "";
}

void _regime_window_pending_store(string eventId, string direction, datetime signalTime, double sl, double tp, string halfLabel)
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
   if(!_direct_in_allowed_trade_window_gmt() || _direct_in_no_trade_window_gmt())
      return;

   string currentDir = "";
   string currentSource = "";
   int currentShift = -1;
   datetime currentTime = 0;
   double currentEntry = 0.0;
   bool stillValid = _find_current_atomic_regime_from_buffers("", currentDir, currentShift, currentTime, currentEntry, currentSource);
   if(!stillValid || currentDir != g_pendingRegimeWindowDirection || currentTime != g_pendingRegimeWindowSignalTime)
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
         "current_dir=" + currentDir + " current_time=" + _fmt_time(currentTime)
      );
      _regime_window_pending_clear();
      return;
   }

   string eventId = g_pendingRegimeWindowEventId;
   string dir = g_pendingRegimeWindowDirection;
   double sl = g_pendingRegimeWindowSl;
   double tp = g_pendingRegimeWindowTp;
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
   _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, 0.0, halfLabel, signalTime);
}

string _direct_trade_window_status()
{
   if(!_direct_in_allowed_trade_window_gmt())
      return "BLOCK allowed_window";
   if(_direct_in_no_trade_window_gmt())
      return "BLOCK no_trade_window";
   return "WINDOW OK";
}

string _direct_spread_status(int spread)
{
   if(g_directMt4MaxSpreadRuntime <= 0)
      return "SPREAD GOV OFF";
   if(spread > g_directMt4MaxSpreadRuntime)
      return "SPREAD BLOCK " + IntegerToString(spread) + "/" + IntegerToString(g_directMt4MaxSpreadRuntime);
   return "SPREAD OK " + IntegerToString(spread) + "/" + IntegerToString(g_directMt4MaxSpreadRuntime);
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

string _direct_event_global_key(string eventId)
{
   return "AtomicBridgeMT4|EVT|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + _tf_to_string(Period()) + "|" + IntegerToString(_direct_event_hash(eventId));
}

bool _direct_event_claim(string eventId)
{
   string key = _direct_event_global_key(eventId);
   double now = (double)TimeLocal();
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   double observed = GlobalVariableGet(key);
   if(observed > 0.0 && now - observed < 86400.0)
      return false;
   return GlobalVariableSetOnCondition(key, now, observed);
}

void _direct_event_release(string eventId)
{
   GlobalVariableSet(_direct_event_global_key(eventId), 0.0);
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
      if(direction != "" && openDir != direction)
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

bool _direct_order_owned_by_instance(int ticket, string source, bool inheritPartial)
{
   double owner = _direct_state_get("OWNER", ticket);
   if(owner > 0.0)
      return (int)owner == Period();
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
   _direct_state_set("OWNER", ticket, parentOwner);
   return (int)parentOwner == Period();
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
   return magic >= 1000000000 && magic < 2000000000;
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
   if(periodic && !_account_risk_audit_claim_snapshot())
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
   double tradeBudget = riskCapital * MathMax(0.0, InpAccountRiskPerTradePct) / 100.0;
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
   double tradeRiskBudget = equity * MathMax(0.0, InpAccountRiskPerTradePct) / 100.0;
   double dailyAtrBudget = equity * MathMax(0.0, InpAccountRiskDailyAtrExposurePct) / 100.0;
   double portfolioBudget = equity * MathMax(0.0, InpAccountRiskMaxPortfolioPct) / 100.0;
   double availablePortfolioRisk = MathMax(0.0, portfolioBudget - openRiskMoney);
   if(tradeRiskBudget <= 0.0 || dailyAtrBudget <= 0.0 || availablePortfolioRisk <= 0.0)
   {
      detail = "account_risk_block exhausted_budget"
         + " open_risk=" + DoubleToString(openRiskMoney, 2)
         + " portfolio_budget=" + DoubleToString(portfolioBudget, 2);
      return 0.0;
   }
   double slLot = tradeRiskBudget / slMoneyPerLot;
   double atrLot = dailyAtrBudget / dailyMoneyPerLot;
   double portfolioLot = availablePortfolioRisk / slMoneyPerLot;
   double rawLot = autoLotEnabled ? MathMin(slLot, MathMin(atrLot, portfolioLot)) : fallbackLot;
   double finalLot = autoLotEnabled ? _direct_normalize_order_lot(rawLot, requireHalfSplit) : fallbackLot;
   double projectedRisk = slMoneyPerLot * finalLot;
   double projectedAtrExposure = dailyMoneyPerLot * finalLot;
   if(finalLot <= 0.0
      || projectedRisk > tradeRiskBudget + 0.01
      || projectedRisk > availablePortfolioRisk + 0.01
      || projectedAtrExposure > dailyAtrBudget + 0.01)
   {
      detail = "account_risk_block volume_below_min_or_budget"
         + " raw_lot=" + DoubleToString(rawLot, 4)
         + " projected_risk=" + DoubleToString(projectedRisk, 2)
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
      + " equity=" + DoubleToString(equity, 2)
      + " risk_pct=" + DoubleToString(InpAccountRiskPerTradePct, 3)
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
   if(!g_directMt4EnabledRuntime)
   {
      g_lastDirectMt4EventId = eventId;
      _direct_audit_write("direct_signal_received", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "confirmed_signal", 0.0, "direct_disabled_path half_trigger=" + _fmt_price(halfTriggerPrice));
      _direct_audit_write("direct_skip_disabled", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "direct_off", 0.0, "");
      return true;
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
         _regime_window_pending_store(eventId, dir, sourceSignalTime, sl, tp, halfTriggerLabel);
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
      _direct_audit_write("direct_skip_spread", source, eventId, 0, dir, g_directMt4LotRuntime, signalPx, sl, tp, "spread=" + IntegerToString(spread) + " max=" + IntegerToString(g_directMt4MaxSpreadRuntime), 0.0, "");
      return false;
   }
   if(sourceIsRegime)
      _direct_close_reverse_positions(dir);
   RefreshRates();
   int type = (dir == "BUY") ? OP_BUY : OP_SELL;
   double price = (type == OP_BUY) ? Ask : Bid;
   string atomicGeometryDetail = "";
   if(!sourceIsRegime && g_atomicDirectRiskGeometryRuntime)
   {
      double geometrySl = sl;
      if(!_atomic_r_geometry_sl(dir, price, tp, g_atomicDirectTargetRRuntime, geometrySl, atomicGeometryDetail))
      {
         g_lastDirectMt4EventId = eventId;
         Print("AtomicBridge direct_mt4 skipped reason=atomic_r_geometry_invalid event=", eventId, " dir=", dir, " detail=", atomicGeometryDetail);
         _direct_audit_write("direct_skip_atomic_geometry", source, eventId, 0, dir, g_directMt4LotRuntime, price, sl, tp, atomicGeometryDetail, 0.0, "");
         return false;
      }
      sl = geometrySl;
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
      ? (g_regimeDirectMt4HalfBeRRuntime > 0.0)
      : (g_directMt4HalfBeTpIndexRuntime > 0 || g_directMt4HalfBeRRuntime > 0.0);
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
   if(!_direct_event_claim(eventId))
   {
      if(riskLockHeld)
         _account_risk_lock_release();
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 duplicate suppressed event=", eventId, " dir=", dir);
      _direct_audit_write("direct_duplicate_suppressed", source, eventId, 0, dir, lot, price, stopLoss, takeProfit, "terminal_global_event_lock", 0.0, lotDetail);
      return true;
   }
   string comment = "AtomicBridgeMT4|" + source;
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
      double initialRisk = (actualSl > 0.0 ? MathAbs(fillPrice - actualSl) : 0.0);
      if(initialRisk > Point)
         _direct_state_set("IRISK", ticket, initialRisk);
      _direct_state_set("OWNER", ticket, Period());
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
   _direct_event_release(eventId);
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

void _direct_audit_write(string eventName, string source, string eventId, int ticket, string direction, double lot, double price, double sl, double tp, string reason, double pnl, string extra)
{
   if(!_audit_enabled_runtime() || !InpDirectMt4AuditCsv)
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
   if(!g_regimeDelayValidationRuntime || g_lastRegimeDelayOpenedEventId == "")
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
      double barExtreme = 0.0;
      bool barTouched = _direct_history_trigger_touched(OrderType(), OrderOpenTime(), ct, triggerPrice, barExtreme);
      string lifecycle = "initial_risk=" + DoubleToString(initialRisk, Digits)
         + " trigger=" + _fmt_price(triggerPrice)
         + " trigger_seen=" + (triggerSeen ? "1" : "0")
         + " bar_touch_estimate=" + (barTouched ? "1" : "0")
         + " bar_extreme=" + _fmt_price(barExtreme)
         + " max_r=" + DoubleToString(maxR, 3)
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
      "\"regime_halfbe_r\":" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2) + ",";
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
   double directTp = _select_direct_tp(tp1, tp2, tp3, tp4, tp5);
   double atomicExecutionSl = sl;
   string atomicGeometryDetail = "indicator_sl";
   if(g_atomicDirectRiskGeometryRuntime && (dir == "BUY" || dir == "SELL"))
      _atomic_r_geometry_sl(dir, entryPrice, directTp, g_atomicDirectTargetRRuntime, atomicExecutionSl, atomicGeometryDetail);
   int halfTpIndex = MathMax(1, MathMin(5, g_directMt4HalfBeTpIndexRuntime));
   bool atomicHalfEnabled = (halfTpIndex < g_directMt4TpIndexRuntime);
   double directHalfTrigger = atomicHalfEnabled ? _direct_tp_by_index(halfTpIndex, tp1, tp2, tp3, tp4, tp5) : 0.0;
   string directHalfLabel = atomicHalfEnabled ? ("tp" + IntegerToString(halfTpIndex)) : "disabled_at_or_after_final_tp";
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
      if(StringFind(obj, REGIME_LEVEL_PREFIX) == 0)
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
   datetime labelTime = Time[0] + secondsPerBar * MathMax(1, InpAtomicRegimeTradeLevelLabelBars);
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

void _draw_atomic_regime_trade_levels()
{
   if(!InpShowAtomicRegimeTradeLevels)
   {
      _delete_regime_trade_levels();
      return;
   }
   string activeTickets = "|";
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
      bool isRegime = _contains_ci(source, "AtomicRegime");
      if(!isRegime && g_directMt4HalfBeTpIndexRuntime >= g_directMt4TpIndexRuntime)
         continue;
      double halfR = (isRegime ? g_regimeDirectMt4HalfBeRRuntime : g_directMt4HalfBeRRuntime);
      double storedTrigger = _direct_get_half_trigger_price(ticket);
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
      double currentR = (dir > 0) ? ((px - entry) / initialRisk) : ((entry - px) / initialRisk);
      double maxR = _direct_state_get("MAXR", ticket);
      if(currentR > maxR)
      {
         maxR = currentR;
         _direct_state_set("MAXR", ticket, maxR);
      }
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
   _dash_rect("BG", 10, 18, 1010, 374, C'24,30,42', C'134,158,182');
   _dash_rect("HULL", 17, 25, 996, 360, C'40,48,62', C'90,178,255');
   _dash_rect("DOCK_STRIPE", 18, 31, 994, 4, C'90,178,255', C'90,178,255');
   _dash_rect("CORE", 26, 56, 664, 316, C'18,24,36', C'65,116,172');
   _dash_rect("ACTION_PANEL", 704, 56, 286, 316, C'31,38,52', C'221,55,78');
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
   _dash_label("L_LOT", 38, 66, "Lot", C'184,196,210', 8);
   _dash_edit("EDIT_LOT", 70, 62, 70, 22, DoubleToString(g_directMt4LotRuntime, 2));
   _dash_label("L_SPREAD", 158, 66, "Max spread pts", C'184,196,210', 8);
   _dash_edit("EDIT_SPREAD", 260, 62, 70, 22, IntegerToString(g_directMt4MaxSpreadRuntime));
   _dash_label("L_RR", 342, 66, "Regime TP R", C'184,196,210', 8);
   _dash_edit("EDIT_RR", 420, 62, 48, 22, DoubleToString(g_regimeRRRuntime, 1));
   _dash_label("L_REG_HB", 482, 66, "Regime HC/BE R", C'184,196,210', 8);
   _dash_edit("EDIT_REGIME_HALFBE", 590, 62, 48, 22, DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1));
   _dash_label("L_ATOMIC_TP", 38, 88, "Atomic HC/BE TP leg", C'184,196,210', 8);
   _dash_edit("EDIT_ATOMIC_HALFBE_TP", 172, 84, 42, 22, IntegerToString(g_directMt4HalfBeTpIndexRuntime));
   _dash_label("L_ATOMIC_FALLBACK", 226, 88, "Atomic fallback HC/BE R", C'184,196,210', 8);
   _dash_edit("EDIT_HALFBE", 382, 84, 48, 22, DoubleToString(g_directMt4HalfBeRRuntime, 1));
   _dash_label("L_REG_DELAY", 446, 88, "Reg delay sec", C'184,196,210', 8);
   _dash_edit("EDIT_REGIME_DELAY", 538, 84, 56, 22, IntegerToString(g_regimeConfirmDelaySecondsRuntime));
   _dash_label("L_REG_SCALE", 608, 88, "Reg SL %", C'184,196,210', 8);
   _dash_edit("EDIT_REGIME_SCALE", 650, 84, 34, 22, DoubleToString(g_regimeFinalRiskScalePctRuntime, 0));
   _dash_label("L_ALLOWED", 38, 246, "Allowed GMT", C'184,196,210', 8);
   _dash_edit("EDIT_ALLOWED", 126, 242, 180, 22, g_directMt4AllowedWindowsRuntime);
   _dash_label("L_NOTRADE", 324, 246, "Block GMT", C'184,196,210', 8);
   _dash_edit("EDIT_NOTRADE", 396, 242, 180, 22, g_directMt4NoTradeWindowsRuntime);
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   RefreshRates();
   _dash_label("STATE", 38, 112, StringFormat("Live BID %s / ASK %s | %s | %s",
              _fmt_price(Bid), _fmt_price(Ask), _direct_spread_status(spread), _direct_trade_window_status()), clrWhite, 8);
   _dash_label("MODES", 38, 134, StringFormat("Modes: Atomic=%s | Regime=%s | RegExec=%s | ProTrade=%s | Risk=%s %.2f%%/%.2f%% | Audit=%s | Shift=%s",
              (g_atomicModeEnabledRuntime ? "ON" : "OFF"), (g_atomicRegimeModeEnabledRuntime ? "ON" : "OFF"),
              (g_regimeDelayValidationRuntime ? "DELAY" : "DIRECT"), (g_proTradePostEnabledRuntime ? "ON" : "OFF"),
              (_account_risk_enabled_runtime() ? (g_ftmoModeRuntime ? "FTMO" : "RISKLOT") : "OFF"), InpAccountRiskPerTradePct, InpAccountRiskMaxPortfolioPct,
              (g_auditEnabledRuntime ? "ON" : "OFF"), (g_regimeUseClosedBarRuntime ? "1" : "0")), C'90,178,255', 8);
   _dash_label("REGWIN", 38, 228, "AtomicRegime pre-window execution: " + (g_regimeOpenPreWindowSignalRuntime ? "ON" : "OFF") + " | pending=" + (g_pendingRegimeWindowEventId == "" ? "none" : g_pendingRegimeWindowDirection + " " + _fmt_time(g_pendingRegimeWindowSignalTime)), C'184,196,210', 8);
   _dash_label("LAST_A", 38, 154, "Last Atomic: " + (g_lastObservedSignalDirection == "" ? "NONE" : g_lastObservedSignalDirection) + " | " + _fmt_time(g_lastObservedSignalTime), C'184,196,210', 8);
   _dash_label("LAST_R", 38, 172, "Last Regime: " + (g_lastRegimeObservedSignalDirection == "" ? "NONE" : g_lastRegimeObservedSignalDirection) + " | " + _fmt_time(g_lastRegimeObservedSignalTime), C'184,196,210', 8);
   _dash_label("TPHC_A", 38, 192, "Atomic: TP leg=" + IntegerToString(g_directMt4TpIndexRuntime) + " | HC/BE TP leg=" + IntegerToString(g_directMt4HalfBeTpIndexRuntime) + " | SL=" + (g_atomicDirectRiskGeometryRuntime ? DoubleToString(g_atomicDirectTargetRRuntime, 1) + "R geometry" : "indicator"), C'184,196,210', 8);
   _dash_label("TPHC_R", 38, 210, "AtomicRegime: TP R=" + DoubleToString(g_regimeRRRuntime, 1) + " | HC/BE R=" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1) + " | SL scale=" + DoubleToString(g_regimeFinalRiskScalePctRuntime, 0) + "%", C'184,196,210', 8);
   double pct; string label; color fill;
   if(_direct_open_progress(pct, label, fill))
      _dash_progress("TRADE", 38, 274, 620, 24, pct, label, fill);
   else
      _dash_progress("TRADE", 38, 274, 620, 24, 0.0, "DIRECT MT4 POSITION: none | dashboard does not mutate signal math", C'88,96,112');
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
   obj = DASH_PREFIX + "EDIT_ALLOWED";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4AllowedWindowsRuntime = _trim(ObjectGetString(0, obj, OBJPROP_TEXT));
   obj = DASH_PREFIX + "EDIT_NOTRADE";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4NoTradeWindowsRuntime = _trim(ObjectGetString(0, obj, OBJPROP_TEXT));
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
      g_regimeFinalRiskScalePctRuntime = MathMax(10.0, MathMin(200.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT))));
   Print("AtomicBridge dashboard applied direct=", (g_directMt4EnabledRuntime ? "true" : "false"),
         " protrade_post=", (g_proTradePostEnabledRuntime ? "true" : "false"),
         " priority=", (g_directMt4PriorityDirectFirst ? "direct_first" : "post_first"),
         " lot=", DoubleToString(g_directMt4LotRuntime, 2),
         " max_spread=", g_directMt4MaxSpreadRuntime,
         " allowed_gmt='", g_directMt4AllowedWindowsRuntime, "'",
         " block_gmt='", g_directMt4NoTradeWindowsRuntime, "'",
         " regime_rr=", DoubleToString(g_regimeRRRuntime, 2),
         " atomic_tp=", g_directMt4TpIndexRuntime,
         " atomic_sl_mode=", (g_atomicDirectRiskGeometryRuntime ? "r_geometry" : "indicator"),
         " atomic_target_r=", DoubleToString(g_atomicDirectTargetRRuntime, 2),
         " atomic_halfbe_tp=", g_directMt4HalfBeTpIndexRuntime,
         " atomic_fallback_halfbe_r=", DoubleToString(g_directMt4HalfBeRRuntime, 2),
         " regime_halfbe_r=", DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2),
         " regime_exec_mode=", (g_regimeDelayValidationRuntime ? "delay_validate" : "direct"),
         " regime_confirm_delay_sec=", g_regimeConfirmDelaySecondsRuntime,
         " regime_final_scale_pct=", DoubleToString(g_regimeFinalRiskScalePctRuntime, 2),
         " regime_closed_bar=", (g_regimeUseClosedBarRuntime ? "true" : "false"),
         " regime_pre_window=", (g_regimeOpenPreWindowSignalRuntime ? "true" : "false"),
         " risk_mode=", (g_ftmoModeRuntime ? "FTMO" : (g_riskLotOnlyRuntime ? "RISKLOT_ONLY" : "OFF")),
         " audit=", (g_auditEnabledRuntime ? "true" : "false"));
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

   double pct = MathMax(10.0, MathMin(200.0, g_regimeFinalRiskScalePctRuntime));
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
   if(directFirst)
      _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, 0.0, "r" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1), signalTime);
   if(!g_proTradePostEnabledRuntime)
   {
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, 0.0, "r" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1), signalTime);
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
      "\"atomic_regime_final_risk_scale_pct\":" + DoubleToString(MathMax(10.0, MathMin(200.0, g_regimeFinalRiskScalePctRuntime)), 2) + ","
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
         _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, 0.0, "r" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1), signalTime);
      return true;
   }

   Print("AtomicBridge regime POST failed code=", code, " err=", GetLastError(), " event=", eventKind, " dir=", dir, " endpoint=", endpoint, " response=", response);
   if(eventKind == "confirmed_signal" && !directFirst)
      _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName, 0.0, "r" + DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 1), signalTime);
   return false;
}

void _handle_regime_event(string reason, string direction, int signalIndex, datetime signalTime, double entryPrice, string trendName, string atomicDirection, double atomicEntry, double atomicSl)
{
   if(!InpEnableRegimeChangePost || StringLen(direction) <= 0)
      return;

   double regimeSl, regimeTp;
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
   string widenReason = "";
   if(_regime_apply_sl_widen(direction, entryPrice, regimeSl, regimeTp, widenReason))
      trendName = trendName + "|" + widenReason;
   string scaleReason = "";
   if(_regime_apply_final_risk_scale(direction, entryPrice, regimeSl, regimeTp, scaleReason))
      trendName = trendName + "|" + scaleReason;

   // Shift is not a stable identity during delayed confirmation: a fresh shift=1
   // signal naturally becomes shift=2/3/... while the 300s timer is running.
   string regimeEventId = _regime_event_id(direction, signalTime);
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
         _regime_mark_delay_opened_if_needed(regimeEventId, direction, signalTime);
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
      _regime_mark_delay_opened_if_needed(regimeEventId, direction, signalTime);
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
      _regime_mark_delay_opened_if_needed(regimeEventId, direction, signalTime);
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
      _regime_mark_delay_opened_if_needed(regimeEventId, direction, signalTime);
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
   if(!hasBufferRegime)
      _regime_cancel_pending_delay("signal_missing_before_open", hasBufferRegime, regimeDirection, regimeSignalIndex, regimeSignalTime);

   double sl, tp1, tp2, tp3, tp4, tp5;
   _find_atomic_levels(direction, signalIndex, sl, tp1, tp2, tp3, tp4, tp5);

   string eventId = StringFormat("%s|%s|%d|%I64d", Symbol(), direction, signalIndex, (long)signalTime);
   bool firstObservation = (StringLen(g_lastEventId) <= 0 || g_lastSignalTime <= 0);
   double atomicGeometrySl = sl;
   string atomicGeometryBuild = "indicator_sl";
   if(g_atomicDirectRiskGeometryRuntime)
      _atomic_r_geometry_sl(direction, entryPrice, _select_direct_tp(tp1, tp2, tp3, tp4, tp5), g_atomicDirectTargetRRuntime, atomicGeometrySl, atomicGeometryBuild);
   string geometryReason = "";
   bool geometryOk = _atomic_signal_geometry_valid(direction, entryPrice, atomicGeometrySl, tp1, tp2, tp3, tp4, tp5, geometryReason);
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
   g_proTradePostEnabledRuntime = InpEnableProTradePost;
   g_atomicModeEnabledRuntime = InpEnableAtomicMode;
   g_atomicRegimeModeEnabledRuntime = InpEnableAtomicRegimeMode;
   string priority = _lower_copy(_trim(InpDirectMt4Priority));
   g_directMt4PriorityDirectFirst = (priority != "post_first" && priority != "quantdesk_first");
   g_directMt4LotRuntime = MathMax(0.01, InpDirectMt4Lot);
   g_directMt4MaxSpreadRuntime = MathMax(0, InpDirectMt4MaxSpreadPoints);
   g_directMt4TpIndexRuntime = MathMax(1, MathMin(5, InpDirectMt4TpIndex));
   g_atomicDirectRiskGeometryRuntime = InpAtomicDirectRiskGeometryEnabled;
   g_atomicDirectTargetRRuntime = _atomic_supported_target_r(InpAtomicDirectTargetR);
   g_directMt4HalfBeRRuntime = MathMax(0.0, InpDirectMt4HalfBeR);
   g_directMt4HalfBeTpIndexRuntime = MathMax(1, MathMin(5, InpDirectMt4HalfBeTpIndex));
   g_regimeDirectMt4HalfBeRRuntime = MathMax(0.0, InpRegimeDirectMt4HalfBeR);
   g_regimeRRRuntime = MathMax(0.1, InpRegimeRR);
   g_regimeFinalRiskScalePctRuntime = MathMax(10.0, MathMin(200.0, InpRegimeFinalRiskScalePct));
   g_regimeUseClosedBarRuntime = InpRegimeUseClosedBar;
   g_regimeDelayValidationRuntime = InpRegimeDelayValidationMode;
   g_regimeConfirmDelaySecondsRuntime = MathMax(-1, InpRegimeConfirmDelaySeconds);
   g_regimeOpenPreWindowSignalRuntime = InpRegimeOpenPreWindowSignal;
   g_directMt4AllowedWindowsRuntime = _trim(InpDirectMt4AllowedTradeWindowsGmt);
   g_directMt4NoTradeWindowsRuntime = _trim(InpDirectMt4NoTradeWindowsGmt);
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
      " regimeExecMode=", (g_regimeDelayValidationRuntime ? "delay_validate" : "direct"),
      " confirmDelaySec=", g_regimeConfirmDelaySecondsRuntime,
      " stableSec=", InpRegimeConfirmStableSeconds,
      " maxConfirmShift=", InpRegimeMaxConfirmShift,
      " atomicTpIndex=", g_directMt4TpIndexRuntime,
      " atomicSlMode=", (g_atomicDirectRiskGeometryRuntime ? "r_geometry" : "indicator"),
      " atomicTargetR=", DoubleToString(g_atomicDirectTargetRRuntime, 2),
      " atomicHalfTpIndex=", g_directMt4HalfBeTpIndexRuntime,
      " atomicFallbackHalfR=", DoubleToString(g_directMt4HalfBeRRuntime, 2),
      " regimeHalfR=", DoubleToString(g_regimeDirectMt4HalfBeRRuntime, 2),
      " autoLot=", (InpDirectMt4AutoLotEnabled ? "true" : "false"),
      " autoLotDailyAtrPeriod=", InpDirectMt4AutoLotDailyAtrPeriod,
      " autoLotMax=", DoubleToString(InpDirectMt4AutoLotMax, 2),
      " regimeMinRiskPct=", DoubleToString(InpRegimeMinRiskPricePct, 5),
      " regimeMaxRiskPct=", DoubleToString(InpRegimeMaxRiskPricePct, 5),
      " regimeSlWiden=", (InpRegimeSlWidenEnabled ? "true" : "false"),
      " regimeSlWidenPct=", DoubleToString(InpRegimeSlWidenPct, 1),
      " regimeFinalRiskScalePct=", DoubleToString(g_regimeFinalRiskScalePctRuntime, 1),
      " positionProbe=", (InpDirectMt4PositionProbeAudit ? "true" : "false"),
      " probeSec=", InpDirectMt4PositionProbeIntervalSeconds
   );
   Print(
      "AtomicBridge account_risk mode=", (g_ftmoModeRuntime ? "FTMO" : (g_riskLotOnlyRuntime ? "RISKLOT_ONLY" : "OFF")),
      " effectiveMagic=", _direct_magic(),
      " riskPerTradePct=", DoubleToString(InpAccountRiskPerTradePct, 3),
      " atrExposurePct=", DoubleToString(InpAccountRiskDailyAtrExposurePct, 3),
      " maxPortfolioPct=", DoubleToString(InpAccountRiskMaxPortfolioPct, 3),
      " dailyLossLimitPct=", DoubleToString(_effective_daily_loss_limit_pct(), 3),
      " maxDrawdownPct=", DoubleToString(_effective_max_drawdown_pct(), 3),
      " maxMarginUsagePct=", DoubleToString(InpAccountRiskMaxMarginUsagePct, 3),
      " initialBalanceOverride=", DoubleToString(InpAccountRiskInitialBalanceOverride, 2),
      " dayResetHourGmt=", MathMax(0, MathMin(23, InpAccountRiskDayResetHourGmt))
   );
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
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_MODE")
   {
      g_atomicRegimeModeEnabledRuntime = !g_atomicRegimeModeEnabledRuntime;
      Print("AtomicBridge dashboard AtomicRegime mode=", (g_atomicRegimeModeEnabledRuntime ? "ON" : "OFF"));
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
      Print("AtomicBridge dashboard AtomicRegime execution mode=", (g_regimeDelayValidationRuntime ? "delay_validate" : "direct"));
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
   else if(sparam == DASH_PREFIX + "BTN_AUDIT")
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
