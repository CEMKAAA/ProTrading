//+------------------------------------------------------------------+
//| ProTrading MT5 Buffer Bridge EA V2                               |
//| Stabilizes indicator BUY/SELL state before backend execution.    |
//|                                                                  |
//| Setup notes:                                                     |
//| 1) Attach this EA to the same chart where your indicator runs.   |
//| 2) Set indicator name + BUY/SELL buffer indexes.                 |
//| 3) MT5 -> Tools -> Options -> Expert Advisors ->                 |
//|    "Allow WebRequest for listed URL": add http://127.0.0.1       |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "IntrepidIndicator\\Intrepid Trend Direction";
input int    InpBuyBufferIndex = 0;
input int    InpSellBufferIndex = 1;
input string InpICustomParamsCsv = ""; // Optional indicator Inputs as CSV: e.g. "14,0,1"
input int    InpSignalShift = 0;     // 0=current bar, 1=closed bar
input int    InpSignalCompareMode = 0; // 0=buffer active, 1=BUY when buyBuffer < sellBuffer, 2=BUY when buyBuffer > sellBuffer
input double InpSignalCompareMinDiff = 0.0;
input bool   InpArrowStreakConfirmAfterBlank = false; // Arrow indicators: latest arrow becomes tradable only after next closed blank candle
input int    InpArrowResolvedLookbackBars = 300;
input int    InpPollSeconds = 1;     // V2 state machine poll cadence
input bool   InpPollOnTick = false;  // Lower-latency mode: also evaluate buffers on every chart tick
input int    InpConfirmSeconds = 20; // resolved direction must stay stable this long
input int    InpConfirmBars = 0;     // 0 = use InpConfirmSeconds; >0 requires this many chart bars
input bool   InpLatchSignalUntilConfirm = false; // Pulse indicators: keep first detected signal pending until confirm timeout
input bool   InpConfirmPendingOnClosedBar = false; // Live-bar mode: if pending bar closes with same signal, confirm immediately.
input bool   InpEmitResolvedStateOnChange = false; // Publish resolved_state immediately when pending direction changes
input bool   InpSendInitialConfirmedOnStart = false; // false prevents startup duplicate entries
input int    InpResolvedStateSeconds = 30; // periodic state reconciliation event
input int    InpRetryFailedSendEverySeconds = 2; // throttle retries after failed POST
input int    InpMaxPendingEvents = 200;
input bool   InpInvertDirection = false; // quick fix for indicators with reversed buffers
input bool   InpSendRegistrationOnInit = true;
input bool   InpStartupProbeOnInit = true; // print initial buffer snapshot for fast BUY/SELL map check
input int    InpStartupProbeMaxBuffer = 8; // probe [0..N-1] on init when debug is enabled
input bool   InpStartupRecentSignalDebug = true; // scan recent bars on init and print latest resolved signal
input int    InpStartupRecentSignalLookbackBars = 30; // recent bars to scan for latest BUY/SELL debug snapshot
input bool   InpPublishLastSignalState = false; // telemetry only: publish latest historical BUY/SELL without making it executable
input bool   InpEmitOnlyOnDirectionChange = false; // State/line indicators: only emit when BUY/SELL direction changes
input int    InpHeartbeatSeconds = 300; // registration keepalive only
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;

input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt5/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "intrepid";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDebugPrint = true;
input bool   InpRequireChartIndicator = false; // Verify the visual indicator is also attached to this chart.
input string InpChartIndicatorMatch = "";      // Empty = match by InpIndicatorName basename.
input bool   InpDeleteChartIndicatorOnDeinit = false; // Remove matched visual indicator when this EA is removed.
input bool   InpApplyTemplateIfChartIndicatorMissing = false; // MT5-safe fallback; template must already exist.
input string InpChartTemplateIfChartIndicatorMissing = "";
input int    InpChartIndicatorAuditSeconds = 30; // Periodically verify visual indicator is still attached.
input int    InpChartTemplateRefreshSeconds = 0; // 0=off; >0 periodic template guard.
input int    InpChartTemplateRefreshMode = 0; // 0=apply only when missing, 1=force re-apply template on cadence.
input int    InpChartTemplateApplyMinGapSeconds = 10; // Guard against template reinit loops.

datetime g_lastConfirmedBar = 0;
int      g_confirmedDir = 0; // 1=BUY, -1=SELL, 0=none
int      g_pendingDir = 0; // direction currently under stability confirmation
datetime g_pendingStartedAt = 0;
datetime g_pendingBar = 0;
double   g_pendingSignalValue = 0.0;
datetime g_lastConfirmedSentAt = 0;
datetime g_lastFailedSendAt = 0;
datetime g_lastHeartbeatAt = 0;
datetime g_lastResolvedStateAt = 0;
bool     g_initializedState = false;
datetime g_lastChartIndicatorAuditAt = 0;
datetime g_lastChartTemplateRefreshAt = 0;
double   g_iCustomParams[];
string   g_iCustomParamStrings[];
int      g_iCustomParamTypes[]; // 0=numeric/bool, 1=string
int      g_iCustomParamCount = 0;
int      g_indicatorHandle = INVALID_HANDLE;
int      g_arrowBaseDir = 0;
datetime g_arrowBaseBarTime = 0;
double   g_arrowBaseValue = 0.0;
int      g_arrowResolvedDir = 0;
datetime g_arrowResolvedBarTime = 0;
double   g_arrowResolvedValue = 0.0;
bool     g_chartIndicatorWasPresent = false;

struct PendingBridgeEvent
{
   string eventType;
   string direction;
   double signalValue;
   datetime signalBarTime;
   string eventId;
   int attempts;
   datetime lastAttemptAt;
};

PendingBridgeEvent g_pendingEvents[];

string _tf_to_string(int tf)
{
   if(tf == PERIOD_M1)   return "M1";
   if(tf == PERIOD_M5)   return "M5";
   if(tf == PERIOD_M15)  return "M15";
   if(tf == PERIOD_M30)  return "M30";
   if(tf == PERIOD_H1)   return "H1";
   if(tf == PERIOD_H4)   return "H4";
   if(tf == PERIOD_D1)   return "D1";
   if(tf == PERIOD_W1)   return "W1";
   if(tf == PERIOD_MN1)  return "MN1";
   return IntegerToString(tf);
}

int _tf_seconds(int tf)
{
   if(tf == PERIOD_M1)   return 60;
   if(tf == PERIOD_M5)   return 300;
   if(tf == PERIOD_M15)  return 900;
   if(tf == PERIOD_M30)  return 1800;
   if(tf == PERIOD_H1)   return 3600;
   if(tf == PERIOD_H4)   return 14400;
   if(tf == PERIOD_D1)   return 86400;
   if(tf == PERIOD_W1)   return 604800;
   if(tf == PERIOD_MN1)  return 2592000;
   return MathMax(60, tf * 60);
}

int _effective_confirm_seconds()
{
   int bars = InpConfirmBars;
   if(bars > 0)
      return MathMax(0, _tf_seconds((int)_Period) * bars);
   return MathMax(0, InpConfirmSeconds);
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

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string _lower_copy(string s)
{
   StringToLower(s);
   return s;
}

string _indicator_basename(string name)
{
   string s = _trim(name);
   StringReplace(s, "/", "\\");
   int last = -1;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
   {
      if(StringSubstr(s, i, 1) == "\\")
         last = i;
   }
   if(last >= 0 && last < len - 1)
      return StringSubstr(s, last + 1);
   return s;
}

string _chart_indicator_match_text()
{
   string m = _trim(InpChartIndicatorMatch);
   if(StringLen(m) > 0)
      return m;
   return _indicator_basename(InpIndicatorName);
}

bool _chart_indicator_name_matches(string chartIndicatorName)
{
   string hay = _lower_copy(_trim(chartIndicatorName));
   string needle = _lower_copy(_chart_indicator_match_text());
   string baseNeedle = _lower_copy(_indicator_basename(InpIndicatorName));
   if(StringLen(needle) > 0 && StringFind(hay, needle) >= 0)
      return true;
   if(StringLen(baseNeedle) > 0 && StringFind(hay, baseNeedle) >= 0)
      return true;
   return false;
}

bool _find_chart_indicator(string &foundName, int &foundWindow)
{
   foundName = "";
   foundWindow = -1;

   int windows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
   if(windows <= 0)
      windows = 1;

   for(int w = 0; w < windows; w++)
   {
      int total = ChartIndicatorsTotal(0, w);
      for(int i = 0; i < total; i++)
      {
         string name = ChartIndicatorName(0, w, i);
         if(_chart_indicator_name_matches(name))
         {
            foundName = name;
            foundWindow = w;
            return true;
         }
      }
   }
   return false;
}

string _chart_template_guard_key()
{
   string key = StringFormat("PT_SoloBridge_tpl_%I64d_%s", (long)ChartID(), _chart_indicator_match_text());
   StringReplace(key, " ", "_");
   StringReplace(key, "\\", "_");
   StringReplace(key, "/", "_");
   StringReplace(key, ".", "_");
   return key;
}

bool _apply_chart_template_guarded(string reason)
{
   string tpl = _trim(InpChartTemplateIfChartIndicatorMissing);
   if(StringLen(tpl) <= 0)
      return false;

   int minGap = InpChartTemplateApplyMinGapSeconds;
   if(minGap < 1)
      minGap = 1;

   datetime nowTs = TimeLocal();
   string key = _chart_template_guard_key();
   if(GlobalVariableCheck(key))
   {
      datetime lastApply = (datetime)GlobalVariableGet(key);
      if(lastApply > 0 && nowTs > 0 && (nowTs - lastApply) < minGap)
      {
         if(InpDebugPrint)
            Print("MT5Bridge chart template apply skipped by guard: template=", tpl,
                  " reason=", reason,
                  " remaining_sec=", IntegerToString(minGap - (int)(nowTs - lastApply)));
         return false;
      }
   }

   GlobalVariableSet(key, nowTs);
   bool ok = ChartApplyTemplate(0, tpl);
   Print("MT5Bridge chart template apply requested: template=", tpl,
         " reason=", reason,
         " result=", (ok ? "true" : "false"),
         " | warning: MT5 template application can reinitialize/remove chart objects/EAs.");
   return ok;
}

void _ensure_chart_indicator_on_chart()
{
   if(!InpRequireChartIndicator && !InpDeleteChartIndicatorOnDeinit)
      return;

   string found = "";
   int foundWindow = -1;
   g_chartIndicatorWasPresent = _find_chart_indicator(found, foundWindow);
   if(g_chartIndicatorWasPresent)
   {
      if(InpDebugPrint)
         Print("MT5Bridge chart indicator found: match=", _chart_indicator_match_text(),
               " name=", found, " window=", IntegerToString(foundWindow));
      return;
   }

   if(InpRequireChartIndicator)
   {
      Print("MT5Bridge chart indicator missing: match=", _chart_indicator_match_text(),
            " chart=", _Symbol, " ", _tf_to_string((int)_Period),
            " | iCustom will still be probed, but attach the visual indicator too if this indicator requires chart state.");
   }

   if(InpApplyTemplateIfChartIndicatorMissing)
      _apply_chart_template_guarded("missing_on_init");
}

void _chart_indicator_periodic_guard()
{
   if(!InpRequireChartIndicator && !InpApplyTemplateIfChartIndicatorMissing)
      return;

   datetime nowTs = TimeLocal();
   if(nowTs <= 0)
      return;

   int auditSec = InpChartIndicatorAuditSeconds;
   if(auditSec < 1)
      auditSec = 1;

   bool auditDue = (g_lastChartIndicatorAuditAt <= 0 || (nowTs - g_lastChartIndicatorAuditAt) >= auditSec);
   bool refreshDue = false;
   int refreshSec = InpChartTemplateRefreshSeconds;
   if(refreshSec > 0)
      refreshDue = (g_lastChartTemplateRefreshAt <= 0 || (nowTs - g_lastChartTemplateRefreshAt) >= refreshSec);

   if(!auditDue && !refreshDue)
      return;

   string found = "";
   int foundWindow = -1;
   bool present = _find_chart_indicator(found, foundWindow);
   if(auditDue)
   {
      g_lastChartIndicatorAuditAt = nowTs;
      if(InpDebugPrint)
      {
         if(present)
            Print("MT5Bridge chart indicator audit ok: match=", _chart_indicator_match_text(),
                  " name=", found,
                  " window=", IntegerToString(foundWindow));
         else
            Print("MT5Bridge chart indicator audit missing: match=", _chart_indicator_match_text(),
                  " chart=", _Symbol, " ", _tf_to_string((int)_Period));
      }
   }

   if(refreshDue)
   {
      g_lastChartTemplateRefreshAt = nowTs;
      if(InpChartTemplateRefreshMode == 1)
      {
         _apply_chart_template_guarded("periodic_force_refresh");
         return;
      }
      if(!present && InpApplyTemplateIfChartIndicatorMissing)
         _apply_chart_template_guarded("periodic_missing_refresh");
   }
}

void _delete_chart_indicator_on_deinit()
{
   if(!InpDeleteChartIndicatorOnDeinit)
      return;

   string found = "";
   int foundWindow = -1;
   if(!_find_chart_indicator(found, foundWindow))
   {
      if(InpDebugPrint)
         Print("MT5Bridge chart indicator cleanup skipped: not found match=", _chart_indicator_match_text());
      return;
   }

   bool ok = ChartIndicatorDelete(0, foundWindow, found);
   Print("MT5Bridge chart indicator cleanup: name=", found,
         " window=", IntegerToString(foundWindow),
         " result=", (ok ? "true" : "false"));
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
      p = "/api/v1/mt5/bridge/signal";
   if(StringSubstr(p, 0, 1) != "/")
      p = "/" + p;
   return p;
}

string _build_endpoint(string baseUrl, string apiPath)
{
   return _normalize_base_url(baseUrl) + _normalize_path(apiPath);
}

string _build_event_id(string eventType, string direction, datetime signalBarTime)
{
   string seed = StringFormat(
      "%s|%s|%s|%s|%s|%s|%I64d",
      _trim(eventType),
      _trim(direction),
      _Symbol,
      _tf_to_string((int)_Period),
      _trim(InpSignalProfile),
      InpIndicatorName,
      (long)signalBarTime
   );
   return seed;
}

int _find_pending_event_by_id(string eventId)
{
   string eid = _trim(eventId);
   if(StringLen(eid) <= 0)
      return -1;
   int n = ArraySize(g_pendingEvents);
   for(int i = 0; i < n; i++)
   {
      if(g_pendingEvents[i].eventId == eid)
         return i;
   }
   return -1;
}

void _remove_pending_event_at(int idx)
{
   int n = ArraySize(g_pendingEvents);
   if(idx < 0 || idx >= n)
      return;
   for(int i = idx; i < n - 1; i++)
      g_pendingEvents[i] = g_pendingEvents[i + 1];
   ArrayResize(g_pendingEvents, n - 1);
}

void _mark_send_success(string eventType, string direction, datetime signalBarTime)
{
   string evt = _trim(eventType);
   string dir = _trim(direction);
   if(evt == "confirmed_signal")
   {
      int d = 0;
      if(dir == "BUY")
         d = 1;
      else if(dir == "SELL")
         d = -1;
      if(d != 0)
      {
         g_lastConfirmedBar = signalBarTime;
         g_confirmedDir = d;
         g_lastConfirmedSentAt = TimeCurrent();
         if(g_lastConfirmedSentAt <= 0)
            g_lastConfirmedSentAt = TimeLocal();
         g_lastFailedSendAt = 0;
      }
   }
   else if(evt == "heartbeat" || evt == "register")
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      g_lastHeartbeatAt = nowTs;
   }
   else if(evt == "resolved_state")
   {
      datetime nowResolvedTs = TimeCurrent();
      if(nowResolvedTs <= 0)
         nowResolvedTs = TimeLocal();
      g_lastResolvedStateAt = nowResolvedTs;
   }
}

void _queue_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime, string eventId)
{
   string eid = _trim(eventId);
   if(StringLen(eid) <= 0)
      eid = _build_event_id(eventType, direction, signalBarTime);

   int existing = _find_pending_event_by_id(eid);
   if(existing >= 0)
   {
      g_pendingEvents[existing].eventType = _trim(eventType);
      g_pendingEvents[existing].direction = _trim(direction);
      g_pendingEvents[existing].signalValue = signalValue;
      g_pendingEvents[existing].signalBarTime = signalBarTime;
      return;
   }

   int n = ArraySize(g_pendingEvents);
   int maxN = InpMaxPendingEvents;
   if(maxN < 10)
      maxN = 10;
   if(maxN > 2000)
      maxN = 2000;
   if(n >= maxN)
   {
      _remove_pending_event_at(0);
      n = ArraySize(g_pendingEvents);
   }

   ArrayResize(g_pendingEvents, n + 1);
   g_pendingEvents[n].eventType = _trim(eventType);
   g_pendingEvents[n].direction = _trim(direction);
   g_pendingEvents[n].signalValue = signalValue;
   g_pendingEvents[n].signalBarTime = signalBarTime;
   g_pendingEvents[n].eventId = eid;
   g_pendingEvents[n].attempts = 0;
   g_pendingEvents[n].lastAttemptAt = 0;
}

bool _flush_pending_events()
{
   int n = ArraySize(g_pendingEvents);
   if(n <= 0)
      return true;

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   int retrySec = InpRetryFailedSendEverySeconds;
   if(retrySec < 1)
      retrySec = 1;

   for(int i = 0; i < ArraySize(g_pendingEvents); i++)
   {
      PendingBridgeEvent ev = g_pendingEvents[i];
      if(ev.attempts > 0 && ev.lastAttemptAt > 0 && nowTs > 0 && (nowTs - ev.lastAttemptAt) < retrySec)
         continue;
      int nextAttempt = ev.attempts + 1;
      bool ok = _post_bridge_event(ev.eventType, ev.direction, ev.signalValue, ev.signalBarTime, ev.eventId, nextAttempt);
      if(ok)
      {
         _mark_send_success(ev.eventType, ev.direction, ev.signalBarTime);
         _remove_pending_event_at(i);
         i--;
         continue;
      }
      g_pendingEvents[i].attempts = nextAttempt;
      g_pendingEvents[i].lastAttemptAt = nowTs;
      return false;
   }
   return (ArraySize(g_pendingEvents) == 0);
}

bool _send_or_queue_event(string eventType, string direction, double signalValue, datetime signalBarTime)
{
   string eid = _build_event_id(eventType, direction, signalBarTime);
   bool ok = _post_bridge_event(eventType, direction, signalValue, signalBarTime, eid, 1);
   if(ok)
   {
      _mark_send_success(eventType, direction, signalBarTime);
      _flush_pending_events();
      return true;
   }
   _queue_bridge_event(eventType, direction, signalValue, signalBarTime, eid);
   _flush_pending_events();
   return false;
}

void _clear_pending_state(string reason, datetime signalBarTime)
{
   if(g_pendingDir == 0)
      return;

   string pendingText = _direction_to_text(g_pendingDir);
   int pendingAge = 0;
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   if(g_pendingStartedAt > 0 && nowTs > 0)
      pendingAge = (int)(nowTs - g_pendingStartedAt);

   g_pendingDir = 0;
   g_pendingStartedAt = 0;
   g_pendingBar = 0;
   g_pendingSignalValue = 0.0;
   g_lastFailedSendAt = 0;

   if(signalBarTime <= 0)
      signalBarTime = nowTs;

   if(InpDebugPrint)
      Print("MT5BridgeV2 pending cleared reason=", reason,
            " previous_direction=", pendingText,
            " age_sec=", IntegerToString(pendingAge));

   _send_or_queue_event("signal_clear", "NONE", 0.0, signalBarTime);
}

bool _is_supported_webrequest_endpoint(string endpoint, string &reason)
{
   reason = "";
   string e = _trim(endpoint);
   int schemePos = StringFind(e, "://");
   if(schemePos <= 0)
   {
      reason = "invalid_url_no_scheme";
      return false;
   }

   string scheme = StringSubstr(e, 0, schemePos);
   StringToLower(scheme);
   if(scheme != "http" && scheme != "https")
   {
      reason = "unsupported_scheme";
      return false;
   }

   // MT5 WebRequest supports explicit ports as long as the exact URL is whitelisted.
   return true;
}

bool _is_signal_value(double v)
{
   if(!MathIsValidNumber(v))
      return false;
   if(v == EMPTY_VALUE)
      return false;
   if(MathAbs(v) < InpSignalAbsMin)
      return false;
   return true;
}

string _signal_state_text(bool buySignal, bool sellSignal)
{
   if(buySignal && sellSignal)
      return "AMBIGUOUS";
   if(buySignal)
      return "BUY";
   if(sellSignal)
      return "SELL";
   return "NONE";
}

int _compare_signal_direction(double buyVal, double sellVal)
{
   int mode = InpSignalCompareMode;
   if(mode != 1 && mode != 2)
      return 0;
   if(!_is_signal_value(buyVal) || !_is_signal_value(sellVal))
      return 0;
   double diff = buyVal - sellVal;
   double minDiff = MathAbs(InpSignalCompareMinDiff);
   if(MathAbs(diff) <= minDiff)
      return 0;
   int direction = 0;
   if(mode == 1)
      direction = (buyVal < sellVal) ? 1 : -1;
   else
      direction = (buyVal > sellVal) ? 1 : -1;
   if(direction > 0 && !InpAllowBuy)
      return 0;
   if(direction < 0 && !InpAllowSell)
      return 0;
   if(InpInvertDirection)
      direction = -direction;
   return direction;
}

bool _parse_iCustom_params()
{
   ArrayResize(g_iCustomParams, 0);
   ArrayResize(g_iCustomParamStrings, 0);
   ArrayResize(g_iCustomParamTypes, 0);
   g_iCustomParamCount = 0;

   string raw = _trim(InpICustomParamsCsv);
   if(StringLen(raw) == 0)
      return true;

   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");

   string tokens[];
   int n = StringSplit(raw, 44, tokens); // ','
   if(n <= 0)
      return true;

   for(int i = 0; i < n; i++)
   {
      string token = _trim(tokens[i]);
      if(StringLen(token) == 0)
         continue;

      string lower = token;
      StringToLower(lower);
      double val = 0.0;
      int paramType = 0;
      string strVal = "";

      if(lower == "true")
         val = 1.0;
      else if(lower == "false")
         val = 0.0;
      else
      {
         val = StringToDouble(token);
         if(val == 0.0 && token != "0" && token != "0.0")
         {
            paramType = 1;
            strVal = token;
            int len = StringLen(strVal);
            if(len >= 2)
            {
               string first = StringSubstr(strVal, 0, 1);
               string last = StringSubstr(strVal, len - 1, 1);
               if((first == "\"" && last == "\"") || (first == "'" && last == "'"))
                  strVal = StringSubstr(strVal, 1, len - 2);
            }
         }
      }

      int newCount = g_iCustomParamCount + 1;
      ArrayResize(g_iCustomParams, newCount);
      ArrayResize(g_iCustomParamStrings, newCount);
      ArrayResize(g_iCustomParamTypes, newCount);
      g_iCustomParams[g_iCustomParamCount] = val;
      g_iCustomParamStrings[g_iCustomParamCount] = strVal;
      g_iCustomParamTypes[g_iCustomParamCount] = paramType;
      g_iCustomParamCount = newCount;
   }

   return true;
}

bool _param_is_string(int idx)
{
   if(idx < 0 || idx >= g_iCustomParamCount)
      return false;
   return (g_iCustomParamTypes[idx] == 1);
}

int _create_indicator_handle()
{
   int c = g_iCustomParamCount;
   ResetLastError();

   if(c <= 0)
      return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName);

   // Mixed string/numeric adapter used by indicators such as UniCross:
   // false,false,true,alert.wav,14,0,0.618,5,0,0,0
   if(c == 11 && _param_is_string(3))
      return iCustom(
         _Symbol, PERIOD_CURRENT, InpIndicatorName,
         (g_iCustomParams[0] != 0.0),
         (g_iCustomParams[1] != 0.0),
         (g_iCustomParams[2] != 0.0),
         g_iCustomParamStrings[3],
         (int)g_iCustomParams[4],
         (int)g_iCustomParams[5],
         g_iCustomParams[6],
         (int)g_iCustomParams[7],
         (int)g_iCustomParams[8],
         (int)g_iCustomParams[9],
         (int)g_iCustomParams[10]
      );

   for(int si = 0; si < c; si++)
   {
      if(_param_is_string(si))
      {
         Print("MT5Bridge unsupported string InpICustomParamsCsv layout at index ", si,
               ". Add an adapter branch for this indicator input signature.");
         return INVALID_HANDLE;
      }
   }

   if(c == 1)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0]);
   if(c == 2)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1]);
   if(c == 3)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2]);
   if(c == 4)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3]);
   if(c == 5)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4]);
   if(c == 6)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5]);
   if(c == 7)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6]);
   if(c == 8)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7]);
   if(c == 9)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8]);
   if(c == 10) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9]);
   if(c == 11) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10]);
   if(c == 12) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11]);
   if(c == 13) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12]);
   if(c == 14) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13]);
   if(c == 15) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14]);
   if(c == 16) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15]);
   if(c == 17) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16]);
   if(c == 18) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16], g_iCustomParams[17]);
   if(c == 19) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16], g_iCustomParams[17], g_iCustomParams[18]);
   if(c == 20) return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16], g_iCustomParams[17], g_iCustomParams[18], g_iCustomParams[19]);

   Print("MT5Bridge too many InpICustomParamsCsv values: ", c, " (max supported: 20)");
   return INVALID_HANDLE;
}

bool _ensure_indicator_handle()
{
   if(g_indicatorHandle != INVALID_HANDLE)
      return true;

   g_indicatorHandle = _create_indicator_handle();
   if(g_indicatorHandle == INVALID_HANDLE)
   {
      int err = GetLastError();
      if(InpDebugPrint)
         Print("MT5Bridge indicator handle creation failed indicator=", InpIndicatorName, " err=", IntegerToString(err));
      return false;
   }
   return true;
}

double _icustom_value(int bufferIndex, int barShift)
{
   if(!_ensure_indicator_handle())
      return EMPTY_VALUE;

   double values[];
   ArraySetAsSeries(values, true);
   ResetLastError();
   int copied = CopyBuffer(g_indicatorHandle, bufferIndex, barShift, 1, values);
   if(copied < 1)
   {
      if(InpDebugPrint)
         Print("MT5Bridge CopyBuffer failed indicator=", InpIndicatorName,
               " buffer=", IntegerToString(bufferIndex),
               " shift=", IntegerToString(barShift),
               " err=", IntegerToString(GetLastError()));
      return EMPTY_VALUE;
   }
   return values[0];
}

void _debug_startup_snapshot()
{
   if(!InpDebugPrint || !InpStartupProbeOnInit)
      return;

   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
   double buyVal = _icustom_value(InpBuyBufferIndex, InpSignalShift);
   double sellVal = _icustom_value(InpSellBufferIndex, InpSignalShift);
   string stateText = "NONE";
   int compareDir = _compare_signal_direction(buyVal, sellVal);
   if(InpSignalCompareMode == 1 || InpSignalCompareMode == 2)
   {
      stateText = _direction_to_text(compareDir);
   }
   else
   {
      bool buySignal = InpAllowBuy && _is_signal_value(buyVal);
      bool sellSignal = InpAllowSell && _is_signal_value(sellVal);
      stateText = _signal_state_text(buySignal, sellSignal);

      if(InpInvertDirection)
      {
         if(stateText == "BUY")
            stateText = "SELL";
         else if(stateText == "SELL")
            stateText = "BUY";
      }
   }

   Print("MT5Bridge startup snapshot: indicator=", InpIndicatorName,
         " shift=", IntegerToString(InpSignalShift),
         " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
         " buy[", IntegerToString(InpBuyBufferIndex), "]=", DoubleToString(buyVal, 8),
         " sell[", IntegerToString(InpSellBufferIndex), "]=", DoubleToString(sellVal, 8),
         " state=", stateText,
         " compare_mode=", IntegerToString(InpSignalCompareMode),
         " invert=", (InpInvertDirection ? "true" : "false"));

   int maxBuf = InpStartupProbeMaxBuffer;
   if(maxBuf < 0)
      maxBuf = 0;
   if(maxBuf > 32)
      maxBuf = 32;
   for(int i = 0; i < maxBuf; i++)
   {
      double v = _icustom_value(i, InpSignalShift);
      bool active = _is_signal_value(v);
      Print("MT5Bridge startup probe: buffer[", IntegerToString(i), "]=",
            DoubleToString(v, 8), " active=", (active ? "true" : "false"));
   }
}

void _debug_recent_signal_snapshot()
{
   if(!InpDebugPrint || !InpStartupRecentSignalDebug)
      return;

   int lookback = InpStartupRecentSignalLookbackBars;
   if(lookback < 1)
      return;

   int availableBars = Bars(_Symbol, PERIOD_CURRENT);
   if(lookback > availableBars)
      lookback = availableBars;

   int fromShift = MathMax(0, InpSignalShift);
   int toShift = MathMin(availableBars - 1, fromShift + lookback - 1);
   for(int shift = fromShift; shift <= toShift; shift++)
   {
      datetime barTime = iTime(_Symbol, PERIOD_CURRENT, shift);
      if(barTime <= 0)
         continue;

      double buyVal = _icustom_value(InpBuyBufferIndex, shift);
      double sellVal = _icustom_value(InpSellBufferIndex, shift);
      string resolved = "NONE";
      if(InpSignalCompareMode == 1 || InpSignalCompareMode == 2)
      {
         int compareDir = _compare_signal_direction(buyVal, sellVal);
         resolved = _direction_to_text(compareDir);
         if(compareDir == 0)
            continue;
      }
      else
      {
         bool buySignal = _is_signal_value(buyVal);
         bool sellSignal = _is_signal_value(sellVal);

         if(buySignal && sellSignal)
         {
            Print("MT5Bridge startup recent scan ambiguous bar: shift=", IntegerToString(shift),
                  " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
                  " buy[", IntegerToString(InpBuyBufferIndex), "]=", DoubleToString(buyVal, 8),
                  " sell[", IntegerToString(InpSellBufferIndex), "]=", DoubleToString(sellVal, 8));
            continue;
         }

         if(!buySignal && !sellSignal)
            continue;

         resolved = buySignal ? "BUY" : "SELL";
         if(InpInvertDirection)
         {
            if(resolved == "BUY")
               resolved = "SELL";
            else
               resolved = "BUY";
         }
      }

      Print("MT5Bridge startup recent last signal: lookback=", IntegerToString(lookback),
            " shift=", IntegerToString(shift),
            " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
            " raw_buy[", IntegerToString(InpBuyBufferIndex), "]=", DoubleToString(buyVal, 8),
            " raw_sell[", IntegerToString(InpSellBufferIndex), "]=", DoubleToString(sellVal, 8),
            " resolved=", resolved,
            " compare_mode=", IntegerToString(InpSignalCompareMode),
            " invert=", (InpInvertDirection ? "true" : "false"));
      return;
   }

   Print("MT5Bridge startup recent last signal: NONE within lookback=",
         IntegerToString(lookback));
}

bool _find_recent_raw_signal(int startShift, int lookback, int &direction, string &dirText, double &signalValue, datetime &barTime, double &rawBuy, double &rawSell)
{
   direction = 0;
   dirText = "NONE";
   signalValue = 0.0;
   barTime = 0;
   rawBuy = EMPTY_VALUE;
   rawSell = EMPTY_VALUE;

   if(lookback < 1)
      return false;
   int availableBars = Bars(_Symbol, PERIOD_CURRENT);
   if(lookback > availableBars)
      lookback = availableBars;

   int fromShift = MathMax(0, startShift);
   int toShift = MathMin(availableBars - 1, fromShift + lookback - 1);
   for(int shift = fromShift; shift <= toShift; shift++)
   {
      datetime bt = iTime(_Symbol, PERIOD_CURRENT, shift);
      if(bt <= 0)
         continue;

      double buyVal = _icustom_value(InpBuyBufferIndex, shift);
      double sellVal = _icustom_value(InpSellBufferIndex, shift);
      int d = 0;
      string txt = "NONE";
      double val = 0.0;

      if(InpSignalCompareMode == 1 || InpSignalCompareMode == 2)
      {
         d = _compare_signal_direction(buyVal, sellVal);
         if(d == 0)
            continue;
         txt = _direction_to_text(d);
         val = (d == 1) ? buyVal : sellVal;
      }
      else
      {
         bool buySignal = _is_signal_value(buyVal);
         bool sellSignal = _is_signal_value(sellVal);
         if(buySignal && sellSignal)
            continue;
         if(!buySignal && !sellSignal)
            continue;
         d = buySignal ? 1 : -1;
         txt = _direction_to_text(d);
         val = buySignal ? buyVal : sellVal;
      }

      if(InpInvertDirection)
      {
         d = -d;
         txt = _direction_to_text(d);
      }

      direction = d;
      dirText = txt;
      signalValue = val;
      barTime = bt;
      rawBuy = buyVal;
      rawSell = sellVal;
      return true;
   }
   return false;
}

int _direction_from_text(string direction)
{
   string d = _trim(direction);
   StringToUpper(d);
   if(d == "BUY")
      return 1;
   if(d == "SELL")
      return -1;
   return 0;
}

string _direction_to_text(int direction)
{
   if(direction > 0)
      return "BUY";
   if(direction < 0)
      return "SELL";
   return "NONE";
}

bool _read_raw_signal_at(int barShift, int &direction, string &dirText, double &signalValue, datetime &barTime, double &rawBuy, double &rawSell)
{
   direction = 0;
   dirText = "NONE";
   signalValue = 0.0;
   rawBuy = EMPTY_VALUE;
   rawSell = EMPTY_VALUE;
   barTime = iTime(_Symbol, PERIOD_CURRENT, barShift);
   if(barTime <= 0)
      return false;

   rawBuy = _icustom_value(InpBuyBufferIndex, barShift);
   rawSell = _icustom_value(InpSellBufferIndex, barShift);

   int compareDir = _compare_signal_direction(rawBuy, rawSell);
   if(InpSignalCompareMode == 1 || InpSignalCompareMode == 2)
   {
      if(compareDir == 0)
         return false;
      direction = compareDir;
      dirText = _direction_to_text(direction);
      signalValue = rawBuy;
      return true;
   }

   bool buySignal = InpAllowBuy && _is_signal_value(rawBuy);
   bool sellSignal = InpAllowSell && _is_signal_value(rawSell);

   if(buySignal && sellSignal)
   {
      direction = 0;
      dirText = "AMBIGUOUS";
      return false;
   }
   if(!buySignal && !sellSignal)
      return false;

   direction = buySignal ? 1 : -1;
   if(InpInvertDirection)
      direction = -direction;
   dirText = _direction_to_text(direction);
   signalValue = (buySignal ? rawBuy : rawSell);
   return true;
}

bool _resolve_arrow_streak_latest(int startShift)
{
   int lookback = InpArrowResolvedLookbackBars;
   if(lookback < 1)
      lookback = 300;
   int availableBars = Bars(_Symbol, PERIOD_CURRENT);
   if(lookback > availableBars)
      lookback = availableBars;

   // Active candle arrow is not tradable yet. It becomes a candidate only after
   // the candle closes and the following candle closes blank.
   int activeDir = 0;
   string activeTxt = "NONE";
   double activeVal = 0.0;
   datetime activeBt = 0;
   double activeRb = EMPTY_VALUE;
   double activeRs = EMPTY_VALUE;
   bool activeHas = _read_raw_signal_at(0, activeDir, activeTxt, activeVal, activeBt, activeRb, activeRs);
   if(activeTxt == "AMBIGUOUS")
      return false;
   if(activeHas && activeDir != 0)
   {
      g_arrowBaseDir = activeDir;
      g_arrowBaseBarTime = activeBt;
      g_arrowBaseValue = activeVal;
      g_arrowResolvedDir = 0;
      g_arrowResolvedBarTime = 0;
      g_arrowResolvedValue = 0.0;
      if(InpDebugPrint)
         Print("MT5BridgeV2 arrow streak active arrow waiting close direction=", _direction_to_text(activeDir),
               " bar=", TimeToString(activeBt, TIME_DATE|TIME_SECONDS));
      return false;
   }

   // Last closed candle arrow is still a base. We need the current candle to
   // close blank before resolving it.
   int lastClosedDir = 0;
   string lastClosedTxt = "NONE";
   double lastClosedVal = 0.0;
   datetime lastClosedBt = 0;
   double lastClosedRb = EMPTY_VALUE;
   double lastClosedRs = EMPTY_VALUE;
   bool lastClosedHas = _read_raw_signal_at(1, lastClosedDir, lastClosedTxt, lastClosedVal, lastClosedBt, lastClosedRb, lastClosedRs);
   if(lastClosedTxt == "AMBIGUOUS")
      return false;
   if(lastClosedHas && lastClosedDir != 0)
   {
      g_arrowBaseDir = lastClosedDir;
      g_arrowBaseBarTime = lastClosedBt;
      g_arrowBaseValue = lastClosedVal;
      g_arrowResolvedDir = 0;
      g_arrowResolvedBarTime = 0;
      g_arrowResolvedValue = 0.0;
      if(InpDebugPrint)
         Print("MT5BridgeV2 arrow streak latest closed arrow pending direction=", _direction_to_text(lastClosedDir),
               " base_bar=", TimeToString(lastClosedBt, TIME_DATE|TIME_SECONDS));
      return false;
   }

   // If neither active nor last closed candle has an arrow, the latest older
   // arrow already has a closed blank candle after it, so it is resolved.
   for(int shift = 2; shift < lookback; shift++)
   {
      int d = 0;
      string txt = "NONE";
      double val = 0.0;
      datetime bt = 0;
      double rb = EMPTY_VALUE;
      double rs = EMPTY_VALUE;
      bool has = _read_raw_signal_at(shift, d, txt, val, bt, rb, rs);
      if(txt == "AMBIGUOUS")
         continue;
      if(has && d != 0)
      {
         g_arrowResolvedDir = d;
         g_arrowResolvedBarTime = bt;
         g_arrowResolvedValue = val;
         g_arrowBaseDir = 0;
         g_arrowBaseBarTime = 0;
         g_arrowBaseValue = 0.0;
         if(InpDebugPrint)
            Print("MT5BridgeV2 arrow streak resolved from history direction=", _direction_to_text(d),
                  " base_bar=", TimeToString(bt, TIME_DATE|TIME_SECONDS),
                  " lookback_shift=", IntegerToString(shift));
         return true;
      }
   }
   return false;
}

bool _read_resolved_signal(int barShift, int &direction, string &dirText, double &signalValue, datetime &barTime, double &rawBuy, double &rawSell)
{
   if(!InpArrowStreakConfirmAfterBlank)
      return _read_raw_signal_at(barShift, direction, dirText, signalValue, barTime, rawBuy, rawSell);

   int rawDir = 0;
   string rawText = "NONE";
   double rawValue = 0.0;
   bool hasRaw = _read_raw_signal_at(barShift, rawDir, rawText, rawValue, barTime, rawBuy, rawSell);
   if(rawText == "AMBIGUOUS")
   {
      direction = 0;
      dirText = "AMBIGUOUS";
      signalValue = 0.0;
      return false;
   }

   _resolve_arrow_streak_latest(MathMax(1, barShift));

   direction = g_arrowResolvedDir;
   dirText = _direction_to_text(direction);
   signalValue = g_arrowResolvedValue;
   if(direction == 0)
      return false;
   if(g_arrowResolvedBarTime <= 0)
      return false;
   barTime = g_arrowResolvedBarTime;
   return true;
}

bool _post_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime, string eventId = "", int eventAttempt = 1)
{
   string symbol = _Symbol;
   string timeframe = _tf_to_string((int)_Period);
   string endpointPrimary = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string endpointLocalhost = _build_endpoint("http://localhost", InpApiPath);
   string endpointLoopback = _build_endpoint("http://127.0.0.1", InpApiPath);

   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   int dirInt = _direction_from_text(dir);
   string msg = "";
   if(StringLen(dir) > 0)
      msg = StringFormat("%s %s %s buffer=%g shift=%d", InpIndicatorName, symbol, dir, signalValue, InpSignalShift);
   else
      msg = StringFormat("MT5Bridge %s %s | %s %s", eventKind, InpIndicatorName, symbol, timeframe);

   string pendingText = _direction_to_text(g_pendingDir);
   string confirmedText = _direction_to_text(g_confirmedDir);
   int pendingAge = 0;
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   if(g_pendingDir != 0 && g_pendingStartedAt > 0 && nowTs > 0)
      pendingAge = (int)(nowTs - g_pendingStartedAt);
   int confirmSec = _effective_confirm_seconds();
   int lastSignalDir = 0;
   string lastSignalText = "";
   double lastSignalValue = 0.0;
   datetime lastSignalBar = 0;
   double lastSignalRawBuy = EMPTY_VALUE;
   double lastSignalRawSell = EMPTY_VALUE;
   if(InpPublishLastSignalState)
   {
      int startShift = MathMax(0, InpSignalShift);
      int lookback = MathMax(1, InpStartupRecentSignalLookbackBars);
      _find_recent_raw_signal(startShift, lookback, lastSignalDir, lastSignalText, lastSignalValue, lastSignalBar, lastSignalRawBuy, lastSignalRawSell);
   }

   string resolvedPayloadText = confirmedText;
   if(eventKind == "resolved_state" || eventKind == "signal_clear")
      resolvedPayloadText = (StringLen(dir) > 0 ? dir : "NONE");
   else if(dirInt != 0)
      resolvedPayloadText = _direction_to_text(dirInt);

   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpIndicatorName) + "\","
      "\"signal_hint\":\"" + _json_escape(dir) + "\"," 
      "\"resolved_signal\":\"" + _json_escape(resolvedPayloadText) + "\","
      "\"confirmed_direction\":\"" + _json_escape(confirmedText) + "\","
      "\"pending_direction\":\"" + _json_escape((g_pendingDir != 0) ? pendingText : "") + "\","
      "\"pending_age_sec\":" + IntegerToString(pendingAge) + ","
      "\"confirm_seconds\":" + IntegerToString(confirmSec) + ","
      "\"confirm_bars\":" + IntegerToString(MathMax(0, InpConfirmBars)) + ","
      "\"bridge_version\":\"v2\","
      "\"symbol\":\"" + _json_escape(symbol) + "\","
      "\"timeframe\":\"" + _json_escape(timeframe) + "\","
      "\"signal_profile\":\"" + _json_escape(InpSignalProfile) + "\","
      "\"bridge_event_type\":\"" + _json_escape(eventKind) + "\"," 
      "\"event_id\":\"" + _json_escape(_trim(eventId)) + "\"," 
      "\"event_attempt\":" + IntegerToString((eventAttempt < 1) ? 1 : eventAttempt) + ","
      "\"signal_value\":" + DoubleToString(signalValue, 8) + ","
      "\"resolved_signal_shift\":" + IntegerToString(InpSignalShift) + ","
      "\"resolved_signal_bar_time\":\"" + _json_escape(signalBarTime > 0 ? TimeToString(signalBarTime, TIME_DATE|TIME_SECONDS) : "") + "\","
      "\"resolved_signal_bar_unix\":" + IntegerToString((int)signalBarTime) + ","
      "\"bridge_local_time\":\"" + _json_escape(nowTs > 0 ? TimeToString(nowTs, TIME_DATE|TIME_SECONDS) : "") + "\","
      "\"bridge_local_unix\":" + IntegerToString((int)nowTs) + ","
      "\"last_signal_direction\":\"" + _json_escape(lastSignalText) + "\"," 
      "\"last_signal_bar_time\":\"" + _json_escape(lastSignalBar > 0 ? TimeToString(lastSignalBar, TIME_DATE|TIME_SECONDS) : "") + "\"," 
      "\"last_signal_bar_unix\":" + IntegerToString((int)lastSignalBar) + ","
      "\"last_signal_value\":" + DoubleToString(lastSignalValue, 8) + ","
      "\"last_signal_raw_buy\":" + DoubleToString(lastSignalRawBuy, 8) + ","
      "\"last_signal_raw_sell\":" + DoubleToString(lastSignalRawSell, 8) + ","
      "\"message\":\"" + _json_escape(msg) + "\","
      "\"bridge_token\":\"" + _json_escape(InpBridgeToken) + "\""
      "}";

   string headers = "Content-Type: application/json\r\n";
   if(StringLen(InpBridgeToken) > 0)
      headers = headers + "X-MT4-Bridge-Token: " + InpBridgeToken + "\r\n";

   char postData[];
   char resultData[];
   string resultHeaders = "";
   StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);

   string endpoints[3];
   endpoints[0] = endpointPrimary;
   endpoints[1] = endpointLocalhost;
   endpoints[2] = endpointLoopback;

   for(int i = 0; i < 3; i++)
   {
      string endpoint = endpoints[i];
      if(StringLen(endpoint) == 0)
         continue;

      // Skip exact duplicates to keep logs clean.
      if(i > 0 && endpoint == endpoints[i - 1])
         continue;

      ArrayResize(resultData, 0);
      resultHeaders = "";
      ResetLastError();
      int httpCode = WebRequest("POST", endpoint, headers, InpHttpTimeoutMs, postData, resultData, resultHeaders);
      int err = GetLastError();
      string resultText = CharArrayToString(resultData, 0, -1, CP_UTF8);

      if(httpCode >= 200 && httpCode < 300)
      {
         if(InpDebugPrint)
            Print("MT5Bridge sent ", eventKind, " ", dir, " ", symbol, " ", timeframe,
                  " bar=", TimeToString(signalBarTime, TIME_DATE|TIME_SECONDS),
                  " event_id=", _trim(eventId),
                  " attempt=", IntegerToString((eventAttempt < 1) ? 1 : eventAttempt),
                  " endpoint=", endpoint, " response=", resultText);
         return true;
      }

      if(InpDebugPrint)
         Print("MT5Bridge POST failed code=", httpCode, " err=", err,
               " event=", eventKind, " dir=", dir,
               " event_id=", _trim(eventId),
               " attempt=", IntegerToString((eventAttempt < 1) ? 1 : eventAttempt),
               " endpoint=", endpoint, " response=", resultText);
   }

   return false;
}

bool _confirm_pending_from_closed_bar(datetime nowTs)
{
   if(!InpConfirmPendingOnClosedBar)
      return false;
   if(InpSignalShift != 0 || g_pendingDir == 0 || g_pendingBar <= 0)
      return false;

   int closedDir = 0;
   string closedText = "";
   double closedValue = 0.0;
   datetime closedBar = 0;
   double closedRawBuy = EMPTY_VALUE;
   double closedRawSell = EMPTY_VALUE;
   bool closedResolved = _read_resolved_signal(1, closedDir, closedText, closedValue, closedBar, closedRawBuy, closedRawSell);

   if(!closedResolved || closedDir != g_pendingDir || closedBar != g_pendingBar)
      return false;

   if(g_confirmedDir == closedDir && g_lastConfirmedBar == closedBar)
   {
      g_pendingDir = 0;
      g_pendingStartedAt = 0;
      g_pendingBar = 0;
      g_pendingSignalValue = 0.0;
      return true;
   }

   if(InpRetryFailedSendEverySeconds > 0 && g_lastFailedSendAt > 0 && nowTs > 0 && (nowTs - g_lastFailedSendAt) < InpRetryFailedSendEverySeconds)
      return true;

   if(_send_or_queue_event("confirmed_signal", closedText, closedValue, closedBar))
   {
      g_pendingDir = 0;
      g_pendingStartedAt = 0;
      g_pendingBar = 0;
      g_pendingSignalValue = 0.0;
      g_confirmedDir = closedDir;
      g_lastConfirmedBar = closedBar;
      if(InpDebugPrint)
         Print("MT5BridgeV2 confirmed pending from closed bar direction=", closedText, " bar=", TimeToString(closedBar, TIME_DATE|TIME_SECONDS));
   }
   else
   {
      g_lastFailedSendAt = nowTs;
   }

   return true;
}

bool _confirm_fresh_closed_bar_signal(datetime nowTs)
{
   if(!InpConfirmPendingOnClosedBar)
      return false;
   if(InpSignalShift != 0 || g_pendingDir != 0)
      return false;
   if(!g_initializedState || g_confirmedDir == 0 || g_lastConfirmedBar <= 0)
      return false;

   int closedDir = 0;
   string closedText = "";
   double closedValue = 0.0;
   datetime closedBar = 0;
   double closedRawBuy = EMPTY_VALUE;
   double closedRawSell = EMPTY_VALUE;
   bool closedResolved = _read_resolved_signal(1, closedDir, closedText, closedValue, closedBar, closedRawBuy, closedRawSell);

   if(!closedResolved || closedDir == 0 || closedBar <= 0)
      return false;
   if(closedBar <= g_lastConfirmedBar)
      return false;
   if(closedDir == g_confirmedDir && closedBar == g_lastConfirmedBar)
      return true;

   if(InpRetryFailedSendEverySeconds > 0 && g_lastFailedSendAt > 0 && nowTs > 0 && (nowTs - g_lastFailedSendAt) < InpRetryFailedSendEverySeconds)
      return true;

   if(_send_or_queue_event("confirmed_signal", closedText, closedValue, closedBar))
   {
      g_confirmedDir = closedDir;
      g_lastConfirmedBar = closedBar;
      if(InpDebugPrint)
         Print("MT5BridgeV2 confirmed fresh closed-bar signal direction=", closedText, " bar=", TimeToString(closedBar, TIME_DATE|TIME_SECONDS));
   }
   else
   {
      g_lastFailedSendAt = nowTs;
   }

   return true;
}

void _check_and_send()
{
   int direction = 0;
   string dirText = "";
   double signalPrice = 0.0;
   datetime barTime = 0;
   double rawBuy = EMPTY_VALUE;
   double rawSell = EMPTY_VALUE;
   bool hasResolved = _read_resolved_signal(InpSignalShift, direction, dirText, signalPrice, barTime, rawBuy, rawSell);

   if(!hasResolved)
   {
      if(dirText == "AMBIGUOUS" && InpDebugPrint)
      {
         Print("MT5BridgeV2 ambiguous signal (both BUY/SELL active): ", InpIndicatorName, " ", _Symbol, " ", _tf_to_string((int)_Period));
      }
      if(g_pendingDir != 0)
      {
         datetime noSignalNowTs = TimeCurrent();
         if(noSignalNowTs <= 0)
            noSignalNowTs = TimeLocal();
         if(_confirm_pending_from_closed_bar(noSignalNowTs))
            return;

         if(InpLatchSignalUntilConfirm && dirText != "AMBIGUOUS")
         {
            datetime latchNowTs = noSignalNowTs;
            int latchConfirmSec = _effective_confirm_seconds();

            if(latchConfirmSec > 0 && latchNowTs > 0 && g_pendingStartedAt > 0 && (latchNowTs - g_pendingStartedAt) < latchConfirmSec)
               return;

            if(InpRetryFailedSendEverySeconds > 0 && g_lastFailedSendAt > 0 && latchNowTs > 0 && (latchNowTs - g_lastFailedSendAt) < InpRetryFailedSendEverySeconds)
               return;

            string pendingDirText = _direction_to_text(g_pendingDir);
            if(_send_or_queue_event("confirmed_signal", pendingDirText, g_pendingSignalValue, g_pendingBar))
            {
               g_pendingDir = 0;
               g_pendingStartedAt = 0;
               g_pendingBar = 0;
               g_pendingSignalValue = 0.0;
               if(InpDebugPrint)
                  Print("MT5BridgeV2 confirmed latched signal sent direction=", pendingDirText);
            }
            else
            {
               g_lastFailedSendAt = latchNowTs;
            }
         }
         else
         {
            _clear_pending_state((dirText == "AMBIGUOUS") ? "ambiguous_signal" : "signal_disappeared", barTime);
         }
      }
      else
      {
         datetime freshClosedNowTs = TimeCurrent();
         if(freshClosedNowTs <= 0)
            freshClosedNowTs = TimeLocal();
         if(_confirm_fresh_closed_bar_signal(freshClosedNowTs))
            return;
      }
      // Starting in a blank state is still an initialized baseline. Otherwise
      // the first later signal is incorrectly consumed as startup state.
      if(!g_initializedState)
         g_initializedState = true;
      return;
   }

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   int confirmSec = _effective_confirm_seconds();

   if(!g_initializedState)
   {
      g_initializedState = true;
      if(InpSendInitialConfirmedOnStart)
      {
         g_pendingDir = direction;
         g_pendingStartedAt = nowTs;
         g_pendingBar = barTime;
         g_pendingSignalValue = signalPrice;
      }
      else
      {
         g_confirmedDir = direction;
         g_lastConfirmedBar = barTime;
         if(InpDebugPrint)
            Print("MT5BridgeV2 startup baseline confirmed=", dirText, " no execution emitted.");
         return;
      }
   }

   if(InpEmitOnlyOnDirectionChange && direction == g_confirmedDir && g_pendingDir == 0)
      return;

   if(direction == g_confirmedDir && barTime == g_lastConfirmedBar && g_pendingDir == 0)
      return;

   if(g_pendingDir != 0 && g_pendingBar != barTime && _confirm_pending_from_closed_bar(nowTs))
      return;

   if(g_pendingDir != direction || g_pendingBar != barTime)
   {
      g_pendingDir = direction;
      g_pendingStartedAt = nowTs;
      g_pendingBar = barTime;
      g_pendingSignalValue = signalPrice;
      g_lastFailedSendAt = 0;
      if(InpEmitResolvedStateOnChange)
         _send_or_queue_event("resolved_state", dirText, signalPrice, barTime);
      if(InpDebugPrint)
         Print("MT5BridgeV2 pending started direction=", dirText, " confirm_sec=", IntegerToString(confirmSec));
      if(confirmSec > 0 || InpConfirmBars > 0)
         return;
   }

   if(confirmSec > 0 && nowTs > 0 && g_pendingStartedAt > 0 && (nowTs - g_pendingStartedAt) < confirmSec)
      return;

   if(InpEmitOnlyOnDirectionChange && direction == g_confirmedDir)
   {
      g_pendingDir = 0;
      g_pendingStartedAt = 0;
      g_pendingBar = 0;
      g_pendingSignalValue = 0.0;
      return;
   }

   if(direction == g_confirmedDir && barTime == g_lastConfirmedBar)
   {
      g_pendingDir = 0;
      g_pendingStartedAt = 0;
      g_pendingBar = 0;
      g_pendingSignalValue = 0.0;
      return;
   }

   if(InpRetryFailedSendEverySeconds > 0 && g_lastFailedSendAt > 0 && nowTs > 0 && (nowTs - g_lastFailedSendAt) < InpRetryFailedSendEverySeconds)
      return;

   if(_send_or_queue_event("confirmed_signal", dirText, signalPrice, barTime))
   {
      g_pendingDir = 0;
      g_pendingStartedAt = 0;
      g_pendingBar = 0;
      g_pendingSignalValue = 0.0;
      if(InpDebugPrint)
         Print("MT5BridgeV2 confirmed signal sent direction=", dirText);
   }
   else
   {
      g_lastFailedSendAt = nowTs;
   }
}

int OnInit()
{
   if(!_parse_iCustom_params())
      return(INIT_PARAMETERS_INCORRECT);

   _ensure_chart_indicator_on_chart();

   string endpointPrimary = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string reason = "";
   if(!_is_supported_webrequest_endpoint(endpointPrimary, reason))
   {
      Print("MT5Bridge config warning: endpoint may fail in MQL5 WebRequest. endpoint=", endpointPrimary, " reason=", reason);
      Print("MT5Bridge note: add the exact base URL to the MT5 WebRequest whitelist.");
   }

   int sec = InpPollSeconds;
   if(sec < 1)
      sec = 1;
   EventSetTimer(sec);
   if(InpDebugPrint)
   {
      Print("MT5Bridge initialized: ", InpIndicatorName, " | ", _Symbol, " ", _tf_to_string((int)_Period));
      Print("MT5Bridge terminal data path: ", TerminalInfoString(TERMINAL_DATA_PATH));
      Print("MT5Bridge iCustom params count: ", IntegerToString(g_iCustomParamCount), " | raw='", InpICustomParamsCsv, "'");
      Print("MT5Bridge endpoint(primary): ", endpointPrimary);
      Print("MT5Bridge endpoint(fallback1): ", _build_endpoint("http://localhost", InpApiPath));
      Print("MT5Bridge endpoint(fallback2): ", _build_endpoint("http://127.0.0.1", InpApiPath));
      Print("MT5Bridge reminder: add URL to MT5 WebRequest whitelist.");
   }
   _debug_startup_snapshot();
   _debug_recent_signal_snapshot();
   if(InpSendRegistrationOnInit)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      _send_or_queue_event("register", "", 0.0, nowTs);
   }
   // Try one immediate read/send at startup so current direction is visible without waiting for timer.
   _check_and_send();
   if(!g_initializedState)
   {
      g_initializedState = true;
      if(InpDebugPrint)
         Print("MT5BridgeV2 startup baseline confirmed=NONE no execution emitted.");
   }
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   _delete_chart_indicator_on_deinit();
   if(g_indicatorHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_indicatorHandle);
      g_indicatorHandle = INVALID_HANDLE;
   }
}

void OnTick()
{
   if(!InpPollOnTick)
      return;
   // Latency critical path: detect/send confirmed_signal before retrying
   // telemetry/heartbeat events that can block on WebRequest.
   _check_and_send();
   _flush_pending_events();
}

void OnTimer()
{
   _chart_indicator_periodic_guard();
   // Timer can land exactly on a new candle. Prioritize actionable signals
   // before periodic resolved_state/heartbeat telemetry.
   _check_and_send();
   _flush_pending_events();

   if(InpResolvedStateSeconds > 0)
   {
      datetime nowResolvedTs = TimeCurrent();
      if(nowResolvedTs <= 0)
         nowResolvedTs = TimeLocal();
      if(nowResolvedTs > 0 && (g_lastResolvedStateAt <= 0 || (nowResolvedTs - g_lastResolvedStateAt) >= InpResolvedStateSeconds))
      {
         string resolvedText = "NONE";
         double stateValue = 0.0;
         datetime stateBar = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
         int rawDir = 0;
         string rawText = "";
         double rawBuy = EMPTY_VALUE;
         double rawSell = EMPTY_VALUE;
         _read_resolved_signal(InpSignalShift, rawDir, rawText, stateValue, stateBar, rawBuy, rawSell);
         if(rawDir != 0)
            resolvedText = _direction_to_text(rawDir);
         _send_or_queue_event("resolved_state", resolvedText, stateValue, (stateBar > 0 ? stateBar : nowResolvedTs));
      }
   }

   if(InpHeartbeatSeconds > 0)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      if(nowTs > 0 && (g_lastHeartbeatAt <= 0 || (nowTs - g_lastHeartbeatAt) >= InpHeartbeatSeconds))
      {
         _send_or_queue_event("heartbeat", "", 0.0, nowTs);
      }
   }
   _flush_pending_events();
}

