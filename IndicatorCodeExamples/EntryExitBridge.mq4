//+------------------------------------------------------------------+
//| ProTrading MT4 Entry/Exit Buffer Bridge EA V2                   |
//| Stabilizes entry buffers and sends directional exit buffers.      |
//|                                                                  |
//| Setup notes:                                                     |
//| 1) Attach this EA to the same chart where your indicator runs.   |
//| 2) Set indicator name + BUY/SELL buffer indexes.                 |
//| 3) MT4 -> Tools -> Options -> Expert Advisors ->                 |
//|    "Allow WebRequest for listed URL": add http://127.0.0.1      |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "The Royal Entry _VW First Only";
input int    InpBuyBufferIndex = 2;
input int    InpSellBufferIndex = 3;
input int    InpBuyExitBufferIndex = 5;
input int    InpSellExitBufferIndex = 4;
input string InpICustomParamsCsv = ""; // Optional indicator Inputs as CSV: e.g. "14,0,1"
input int    InpSignalShift = 1;     // 0=current bar, 1=closed bar
input int    InpSignalCompareMode = 0; // 0=buffer active, 1=BUY when buyBuffer < sellBuffer, 2=BUY when buyBuffer > sellBuffer
input double InpSignalCompareMinDiff = 0.0;
input bool   InpArrowStreakConfirmAfterBlank = true; // Arrow indicators: latest arrow becomes tradable only after next closed blank candle
input int    InpArrowResolvedLookbackBars = 300;
input int    InpPollSeconds = 1;     // V2 state machine poll cadence
input int    InpConfirmSeconds = 0; // resolved direction must stay stable this long
input int    InpConfirmBars = 0;     // 0 = use InpConfirmSeconds; >0 requires this many chart bars
input bool   InpSendInitialConfirmedOnStart = true; // entry/exit bridge should act on the current resolved entry state
input int    InpResolvedStateSeconds = 30; // periodic state reconciliation event
input int    InpRetryFailedSendEverySeconds = 2; // throttle retries after failed POST
input int    InpMaxPendingEvents = 200;
input bool   InpInvertDirection = false; // quick fix for indicators with reversed buffers
input bool   InpSendRegistrationOnInit = true;
input bool   InpStartupProbeOnInit = true; // print initial buffer snapshot for fast BUY/SELL map check
input int    InpStartupProbeMaxBuffer = 64; // probe [0..N-1] on init when debug is enabled
input bool   InpStartupRecentSignalDebug = false; // scan recent bars on init and print latest resolved signal
input int    InpStartupRecentSignalLookbackBars = 500; // recent bars to scan for latest BUY/SELL debug snapshot
input int    InpStartupRecentSamplesPerBuffer = 8; // entry-exit scanner prints this many active samples per buffer
input bool   InpStartupObjectScanOnInit = false;
input int    InpStartupObjectLookbackBars = 500;
input int    InpStartupObjectMaxPrint = 120;
input int    InpHeartbeatSeconds = 300; // registration keepalive only
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;
input bool   InpEnableExitSignals = true;
input int    InpExitSignalShift = 1; // usually closed bar
input int    InpExitResolvedLookbackBars = 300;
input bool   InpExitStreakConfirmAfterBlank = true;
input bool   InpExitDebugLastTwo = false;
input bool   InpSendInitialExitOnStart = false; // false prevents startup closes from historical exit buffers

input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "entryexit";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDebugPrint = true;

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
double   g_iCustomParams[];
int      g_iCustomParamCount = 0;
int      g_arrowBaseDir = 0;
datetime g_arrowBaseBarTime = 0;
double   g_arrowBaseValue = 0.0;
int      g_arrowResolvedDir = 0;
datetime g_arrowResolvedBarTime = 0;
double   g_arrowResolvedValue = 0.0;
datetime g_lastBuyExitSentBar = 0;
datetime g_lastSellExitSentBar = 0;
string   g_exitBaseDirection = "";
datetime g_exitBaseBarTime = 0;
double   g_exitBaseValue = 0.0;
bool     g_exitWaitForBlankRuntime = true;

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
      return MathMax(0, _tf_seconds(Period()) * bars);
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

bool _json_bool_field(string text, string key, bool fallback)
{
   string needle = "\"" + key + "\":";
   int pos = StringFind(text, needle);
   if(pos < 0)
      return fallback;
   int start = pos + StringLen(needle);
   int len = StringLen(text);
   while(start < len)
   {
      int ch = StringGetChar(text, start);
      if(ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n' && ch != '"')
         break;
      start++;
   }
   string tail = StringSubstr(text, start, 5);
   StringToLower(tail);
   if(StringSubstr(tail, 0, 4) == "true")
      return true;
   if(StringSubstr(tail, 0, 5) == "false")
      return false;
   if(StringSubstr(tail, 0, 1) == "1")
      return true;
   if(StringSubstr(tail, 0, 1) == "0")
      return false;
   return fallback;
}

void _apply_runtime_response_config(string responseText)
{
   bool nextExitWait = _json_bool_field(responseText, "entry_exit_exit_wait_for_blank", g_exitWaitForBlankRuntime);
   if(nextExitWait != g_exitWaitForBlankRuntime)
   {
      g_exitWaitForBlankRuntime = nextExitWait;
      if(InpDebugPrint)
         Print("MT4Bridge entry-exit runtime config updated exit_wait_for_blank=", (g_exitWaitForBlankRuntime ? "true" : "false"));
   }
}

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
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

string _build_event_id(string eventType, string direction, datetime signalBarTime)
{
   string seed = StringFormat(
      "%s|%s|%s|%s|%s|%I64d",
      _trim(eventType),
      _trim(direction),
      Symbol(),
      _tf_to_string(Period()),
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
      Print("MT4BridgeV2 pending cleared reason=", reason,
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
   int hostStart = schemePos + 3;
   int pathPos = StringFind(e, "/", hostStart);
   string hostPort = (pathPos >= 0) ? StringSubstr(e, hostStart, pathPos - hostStart) : StringSubstr(e, hostStart);
   int colonPos = StringFind(hostPort, ":");
   int port = 0;

   if(colonPos >= 0)
   {
      string portStr = StringSubstr(hostPort, colonPos + 1);
      port = (int)StrToInteger(portStr);
      if(port <= 0)
      {
         reason = "invalid_port";
         return false;
      }
   }
   else
   {
      port = (scheme == "https") ? 443 : 80;
   }

   if(scheme == "http" && port != 80)
   {
      reason = "http_only_port80_supported";
      return false;
   }
   if(scheme == "https" && port != 443)
   {
      reason = "https_only_port443_supported";
      return false;
   }

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

      if(lower == "true")
         val = 1.0;
      else if(lower == "false")
         val = 0.0;
      else
         val = StrToDouble(token);

      if(val == 0.0 && token != "0" && token != "0.0" && lower != "false")
      {
         Print("MT4Bridge invalid InpICustomParamsCsv token: ", token,
               " | Only numeric/bool tokens are supported.");
         return false;
      }

      int newCount = g_iCustomParamCount + 1;
      ArrayResize(g_iCustomParams, newCount);
      g_iCustomParams[g_iCustomParamCount] = val;
      g_iCustomParamCount = newCount;
   }

   return true;
}

double _icustom_value(int bufferIndex, int barShift)
{
   int c = g_iCustomParamCount;
   if(c <= 0)  return iCustom(NULL, 0, InpIndicatorName, bufferIndex, barShift);
   if(c == 1)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], bufferIndex, barShift);
   if(c == 2)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], bufferIndex, barShift);
   if(c == 3)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], bufferIndex, barShift);
   if(c == 4)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], bufferIndex, barShift);
   if(c == 5)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], bufferIndex, barShift);
   if(c == 6)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], bufferIndex, barShift);
   if(c == 7)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], bufferIndex, barShift);
   if(c == 8)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], bufferIndex, barShift);
   if(c == 9)  return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], bufferIndex, barShift);
   if(c == 10) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], bufferIndex, barShift);
   if(c == 11) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], bufferIndex, barShift);
   if(c == 12) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], bufferIndex, barShift);
   if(c == 13) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], bufferIndex, barShift);
   if(c == 14) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], bufferIndex, barShift);
   if(c == 15) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], bufferIndex, barShift);
   if(c == 16) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], bufferIndex, barShift);
   if(c == 17) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16], bufferIndex, barShift);
   if(c == 18) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16], g_iCustomParams[17], bufferIndex, barShift);
   if(c == 19) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16], g_iCustomParams[17], g_iCustomParams[18], bufferIndex, barShift);
   if(c == 20) return iCustom(NULL, 0, InpIndicatorName, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9], g_iCustomParams[10], g_iCustomParams[11], g_iCustomParams[12], g_iCustomParams[13], g_iCustomParams[14], g_iCustomParams[15], g_iCustomParams[16], g_iCustomParams[17], g_iCustomParams[18], g_iCustomParams[19], bufferIndex, barShift);

   // Safety cap for generic adapter.
   Print("MT4Bridge too many InpICustomParamsCsv values: ", c, " (max supported: 20)");
   return EMPTY_VALUE;
}

void _debug_startup_snapshot()
{
   if(!InpDebugPrint || !InpStartupProbeOnInit)
      return;

   datetime barTime = iTime(NULL, 0, InpSignalShift);
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

   Print("MT4Bridge startup snapshot: indicator=", InpIndicatorName,
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
      Print("MT4Bridge startup probe: buffer[", IntegerToString(i), "]=",
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

   if(lookback > Bars)
      lookback = Bars;

   for(int shift = 0; shift < lookback; shift++)
   {
      datetime barTime = iTime(NULL, 0, shift);
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
            Print("MT4Bridge startup recent scan ambiguous bar: shift=", IntegerToString(shift),
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

      Print("MT4Bridge startup recent last signal: lookback=", IntegerToString(lookback),
            " shift=", IntegerToString(shift),
            " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
            " raw_buy[", IntegerToString(InpBuyBufferIndex), "]=", DoubleToString(buyVal, 8),
            " raw_sell[", IntegerToString(InpSellBufferIndex), "]=", DoubleToString(sellVal, 8),
            " resolved=", resolved,
            " compare_mode=", IntegerToString(InpSignalCompareMode),
            " invert=", (InpInvertDirection ? "true" : "false"));
      return;
   }

   Print("MT4Bridge startup recent last signal: NONE within lookback=",
         IntegerToString(lookback));
}

void _debug_recent_buffer_matrix()
{
   if(!InpDebugPrint || !InpStartupRecentSignalDebug)
      return;

   int maxBuf = InpStartupProbeMaxBuffer;
   if(maxBuf < 0)
      maxBuf = 0;
   if(maxBuf > 32)
      maxBuf = 32;

   int lookback = InpStartupRecentSignalLookbackBars;
   if(lookback < 1)
      return;
   if(lookback > Bars)
      lookback = Bars;

   for(int buffer = 0; buffer < maxBuf; buffer++)
   {
      int found = 0;
      int maxSamples = InpStartupRecentSamplesPerBuffer;
      if(maxSamples < 1)
         maxSamples = 1;
      if(maxSamples > 20)
         maxSamples = 20;

      for(int shift = 0; shift < lookback; shift++)
      {
         double v = _icustom_value(buffer, shift);
         if(!_is_signal_value(v))
            continue;
         datetime bt = iTime(NULL, 0, shift);
         Print("MT4Bridge entry-exit recent active buffer[", IntegerToString(buffer),
               "] shift=", IntegerToString(shift),
               " bar=", TimeToString(bt, TIME_DATE|TIME_SECONDS),
               " value=", DoubleToString(v, 8));
         found++;
         if(found >= maxSamples)
            break;
      }
      if(found > 0)
         Print("MT4Bridge entry-exit buffer summary buffer[", IntegerToString(buffer),
               "] samples=", IntegerToString(found),
               " lookback=", IntegerToString(lookback));
   }
}

string _object_type_text(int type)
{
   if(type == OBJ_VLINE) return "OBJ_VLINE";
   if(type == OBJ_HLINE) return "OBJ_HLINE";
   if(type == OBJ_TREND) return "OBJ_TREND";
   if(type == OBJ_TRENDBYANGLE) return "OBJ_TRENDBYANGLE";
   if(type == OBJ_CYCLES) return "OBJ_CYCLES";
   if(type == OBJ_CHANNEL) return "OBJ_CHANNEL";
   if(type == OBJ_STDDEVCHANNEL) return "OBJ_STDDEVCHANNEL";
   if(type == OBJ_REGRESSION) return "OBJ_REGRESSION";
   if(type == OBJ_PITCHFORK) return "OBJ_PITCHFORK";
   if(type == OBJ_GANNLINE) return "OBJ_GANNLINE";
   if(type == OBJ_GANNFAN) return "OBJ_GANNFAN";
   if(type == OBJ_GANNGRID) return "OBJ_GANNGRID";
   if(type == OBJ_FIBO) return "OBJ_FIBO";
   if(type == OBJ_FIBOTIMES) return "OBJ_FIBOTIMES";
   if(type == OBJ_FIBOFAN) return "OBJ_FIBOFAN";
   if(type == OBJ_FIBOARC) return "OBJ_FIBOARC";
   if(type == OBJ_EXPANSION) return "OBJ_EXPANSION";
   if(type == OBJ_FIBOCHANNEL) return "OBJ_FIBOCHANNEL";
   if(type == OBJ_RECTANGLE) return "OBJ_RECTANGLE";
   if(type == OBJ_TRIANGLE) return "OBJ_TRIANGLE";
   if(type == OBJ_ELLIPSE) return "OBJ_ELLIPSE";
   if(type == OBJ_ARROW_THUMB_UP) return "OBJ_ARROW_THUMB_UP";
   if(type == OBJ_ARROW_THUMB_DOWN) return "OBJ_ARROW_THUMB_DOWN";
   if(type == OBJ_ARROW_UP) return "OBJ_ARROW_UP";
   if(type == OBJ_ARROW_DOWN) return "OBJ_ARROW_DOWN";
   if(type == OBJ_ARROW_STOP) return "OBJ_ARROW_STOP";
   if(type == OBJ_ARROW_CHECK) return "OBJ_ARROW_CHECK";
   if(type == OBJ_ARROW_LEFT_PRICE) return "OBJ_ARROW_LEFT_PRICE";
   if(type == OBJ_ARROW_RIGHT_PRICE) return "OBJ_ARROW_RIGHT_PRICE";
   if(type == OBJ_ARROW_BUY) return "OBJ_ARROW_BUY";
   if(type == OBJ_ARROW_SELL) return "OBJ_ARROW_SELL";
   if(type == OBJ_ARROW) return "OBJ_ARROW";
   if(type == OBJ_TEXT) return "OBJ_TEXT";
   if(type == OBJ_LABEL) return "OBJ_LABEL";
   if(type == OBJ_BUTTON) return "OBJ_BUTTON";
   if(type == OBJ_BITMAP) return "OBJ_BITMAP";
   if(type == OBJ_BITMAP_LABEL) return "OBJ_BITMAP_LABEL";
   if(type == OBJ_EDIT) return "OBJ_EDIT";
   if(type == OBJ_EVENT) return "OBJ_EVENT";
   if(type == OBJ_RECTANGLE_LABEL) return "OBJ_RECTANGLE_LABEL";
   return "OBJ_" + IntegerToString(type);
}

void _debug_recent_objects()
{
   if(!InpDebugPrint || !InpStartupObjectScanOnInit)
      return;

   int lookback = InpStartupObjectLookbackBars;
   if(lookback < 1)
      lookback = 500;
   if(lookback > Bars)
      lookback = Bars;

   datetime oldest = iTime(NULL, 0, lookback - 1);
   datetime newest = TimeCurrent();
   if(newest <= 0)
      newest = TimeLocal();

   int maxPrint = InpStartupObjectMaxPrint;
   if(maxPrint < 1)
      maxPrint = 120;
   if(maxPrint > 1000)
      maxPrint = 1000;

   int total = ObjectsTotal();
   int printed = 0;
   Print("MT4Bridge entry-exit object scan start total=", IntegerToString(total),
         " lookback=", IntegerToString(lookback),
         " oldest=", TimeToString(oldest, TIME_DATE|TIME_SECONDS));

   for(int i = total - 1; i >= 0; i--)
   {
      string objName = ObjectName(i);
      if(StringLen(objName) <= 0)
         continue;

      int type = ObjectType(objName);
      datetime t1 = (datetime)ObjectGet(objName, OBJPROP_TIME1);
      datetime t2 = (datetime)ObjectGet(objName, OBJPROP_TIME2);
      datetime objTime = (t1 > 0) ? t1 : t2;
      if(objTime <= 0)
         continue;
      if(oldest > 0 && objTime < oldest)
         continue;
      if(newest > 0 && objTime > newest + _tf_seconds(Period()))
         continue;

      double price1 = ObjectGet(objName, OBJPROP_PRICE1);
      double price2 = ObjectGet(objName, OBJPROP_PRICE2);
      string text = ObjectDescription(objName);
      int objColor = (int)ObjectGet(objName, OBJPROP_COLOR);
      int arrowCode = (int)ObjectGet(objName, OBJPROP_ARROWCODE);
      int shift = iBarShift(NULL, 0, objTime, false);

      Print("MT4Bridge entry-exit object recent name=", objName,
            " type=", _object_type_text(type),
            " shift=", IntegerToString(shift),
            " time=", TimeToString(objTime, TIME_DATE|TIME_SECONDS),
            " price1=", DoubleToString(price1, Digits),
            " price2=", DoubleToString(price2, Digits),
            " color=", IntegerToString(objColor),
            " arrow_code=", IntegerToString(arrowCode),
            " text='", text, "'");
      printed++;
      if(printed >= maxPrint)
         break;
   }
   Print("MT4Bridge entry-exit object scan complete printed=", IntegerToString(printed),
         " total=", IntegerToString(total));
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
   barTime = iTime(NULL, 0, barShift);
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
   if(lookback > Bars)
      lookback = Bars;

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
         Print("MT4BridgeV2 arrow streak active arrow waiting close direction=", _direction_to_text(activeDir),
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
         Print("MT4BridgeV2 arrow streak latest closed arrow pending direction=", _direction_to_text(lastClosedDir),
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
            Print("MT4BridgeV2 arrow streak resolved from history direction=", _direction_to_text(d),
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
   return true;
}

bool _post_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime, string eventId = "", int eventAttempt = 1)
{
   string symbol = Symbol();
   string timeframe = _tf_to_string(Period());
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
      msg = StringFormat("MT4Bridge %s %s | %s %s", eventKind, InpIndicatorName, symbol, timeframe);

   string pendingText = _direction_to_text(g_pendingDir);
   string confirmedText = _direction_to_text(g_confirmedDir);
   int pendingAge = 0;
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   if(g_pendingDir != 0 && g_pendingStartedAt > 0 && nowTs > 0)
      pendingAge = (int)(nowTs - g_pendingStartedAt);
   int confirmSec = _effective_confirm_seconds();
   string exitDirectionPayload = "";
   if(dir == "BUY_EXIT")
      exitDirectionPayload = "BUY";
   else if(dir == "SELL_EXIT")
      exitDirectionPayload = "SELL";

   string entryResolvedText = (dirInt != 0) ? _direction_to_text(dirInt) : confirmedText;
   string exitResolvedText = exitDirectionPayload;
   string exitResolvedKind = "";
   if(exitResolvedText == "BUY")
      exitResolvedKind = "BUY_STOP";
   else if(exitResolvedText == "SELL")
      exitResolvedKind = "SELL_STOP";
   double exitResolvedValue = signalValue;
   datetime exitResolvedBar = signalBarTime;
   if(StringLen(exitResolvedText) == 0 && InpEnableExitSignals)
   {
      string latestExitDirection = "";
      double latestExitValue = 0.0;
      datetime latestExitBar = 0;
      if(_find_latest_exit_signal(latestExitDirection, latestExitValue, latestExitBar))
      {
         exitResolvedText = latestExitDirection;
         if(exitResolvedText == "BUY")
            exitResolvedKind = "BUY_STOP";
         else if(exitResolvedText == "SELL")
            exitResolvedKind = "SELL_STOP";
         exitResolvedValue = latestExitValue;
         exitResolvedBar = latestExitBar;
      }
   }
   string exitResolvedBarText = "";
   if(exitResolvedBar > 0)
      exitResolvedBarText = TimeToString(exitResolvedBar, TIME_DATE|TIME_SECONDS);

   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpIndicatorName) + "\","
      "\"signal_hint\":\"" + _json_escape(dir) + "\","
      "\"entry_exit_enabled\":" + (InpEnableExitSignals ? "true" : "false") + ","
      "\"entry_exit_exit_wait_for_blank\":" + (g_exitWaitForBlankRuntime ? "true" : "false") + ","
      "\"entry_resolved_signal\":\"" + _json_escape(entryResolvedText) + "\","
      "\"exit_direction\":\"" + _json_escape(exitDirectionPayload) + "\","
      "\"exit_resolved_signal\":\"" + _json_escape(exitResolvedText) + "\","
      "\"exit_resolved_kind\":\"" + _json_escape(exitResolvedKind) + "\","
      "\"exit_resolved_bar_time\":\"" + _json_escape(exitResolvedBarText) + "\","
      "\"exit_signal_value\":" + DoubleToString(exitResolvedValue, 8) + ","
      "\"buy_exit_buffer\":" + IntegerToString(InpBuyExitBufferIndex) + ","
      "\"sell_exit_buffer\":" + IntegerToString(InpSellExitBufferIndex) + ","
      "\"resolved_signal\":\"" + _json_escape(entryResolvedText) + "\","
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
         _apply_runtime_response_config(resultText);
         if(InpDebugPrint)
            Print("MT4Bridge sent ", eventKind, " ", dir, " ", symbol, " ", timeframe,
                  " bar=", TimeToString(signalBarTime, TIME_DATE|TIME_SECONDS),
                  " event_id=", _trim(eventId),
                  " attempt=", IntegerToString((eventAttempt < 1) ? 1 : eventAttempt),
                  " endpoint=", endpoint, " response=", resultText);
         return true;
      }

      if(InpDebugPrint)
         Print("MT4Bridge POST failed code=", httpCode, " err=", err,
               " event=", eventKind, " dir=", dir,
               " event_id=", _trim(eventId),
               " attempt=", IntegerToString((eventAttempt < 1) ? 1 : eventAttempt),
               " endpoint=", endpoint, " response=", resultText);
   }

   return false;
}

bool _read_exit_signal_at(int barShift, string &exitDirection, double &signalValue, datetime &barTime, double &rawBuyExit, double &rawSellExit)
{
   exitDirection = "";
   signalValue = 0.0;
   rawBuyExit = EMPTY_VALUE;
   rawSellExit = EMPTY_VALUE;
   barTime = iTime(NULL, 0, barShift);
   if(barTime <= 0)
      return false;

   rawBuyExit = _icustom_value(InpBuyExitBufferIndex, barShift);
   rawSellExit = _icustom_value(InpSellExitBufferIndex, barShift);
   bool buyExit = InpEnableExitSignals && InpBuyExitBufferIndex >= 0 && _is_signal_value(rawBuyExit);
   bool sellExit = InpEnableExitSignals && InpSellExitBufferIndex >= 0 && _is_signal_value(rawSellExit);
   if(buyExit && sellExit)
   {
      if(InpDebugPrint)
         Print("MT4Bridge entry-exit ambiguous exit buffers buy_exit=", DoubleToString(rawBuyExit, 8),
               " sell_exit=", DoubleToString(rawSellExit, 8),
               " shift=", IntegerToString(barShift));
      return false;
   }
   if(!buyExit && !sellExit)
      return false;

   exitDirection = buyExit ? "BUY" : "SELL";
   signalValue = buyExit ? rawBuyExit : rawSellExit;
   return true;
}

void _debug_last_two_exit_signals(int lookback)
{
   if(!InpDebugPrint || !InpExitDebugLastTwo)
      return;
   if(lookback < 1)
      return;
   if(lookback > Bars)
      lookback = Bars;

   int found = 0;
   for(int shift = 0; shift < lookback; shift++)
   {
      string dir = "";
      double val = 0.0;
      datetime bt = 0;
      double rawBuyExit = EMPTY_VALUE;
      double rawSellExit = EMPTY_VALUE;
      if(!_read_exit_signal_at(shift, dir, val, bt, rawBuyExit, rawSellExit))
         continue;

      string bufferName = (dir == "BUY") ? "buy_exit" : "sell_exit";
      int bufferIndex = (dir == "BUY") ? InpBuyExitBufferIndex : InpSellExitBufferIndex;
      Print("MT4Bridge entry-exit recent exit#", IntegerToString(found + 1),
            " direction=", dir,
            " buffer=", bufferName,
            " buffer_index=", IntegerToString(bufferIndex),
            " shift=", IntegerToString(shift),
            " bar=", TimeToString(bt, TIME_DATE|TIME_SECONDS),
            " value=", DoubleToString(val, 8),
            " raw_buy_exit[", IntegerToString(InpBuyExitBufferIndex), "]=", DoubleToString(rawBuyExit, 8),
            " raw_sell_exit[", IntegerToString(InpSellExitBufferIndex), "]=", DoubleToString(rawSellExit, 8));
      found++;
      if(found >= 2)
         break;
   }

   if(found <= 0)
      Print("MT4Bridge entry-exit recent exit: none within lookback=", IntegerToString(lookback));
}

bool _find_latest_exit_signal(string &exitDirection, double &signalValue, datetime &barTime)
{
   int lookback = InpExitResolvedLookbackBars;
   if(lookback < 1)
      lookback = 300;
   if(lookback > Bars)
      lookback = Bars;
   _debug_last_two_exit_signals(lookback);

   if(g_exitWaitForBlankRuntime)
   {
      string activeDir = "";
      double activeValue = 0.0;
      datetime activeBar = 0;
      double activeBuyExit = EMPTY_VALUE;
      double activeSellExit = EMPTY_VALUE;
      if(_read_exit_signal_at(0, activeDir, activeValue, activeBar, activeBuyExit, activeSellExit))
      {
         g_exitBaseDirection = activeDir;
         g_exitBaseBarTime = activeBar;
         g_exitBaseValue = activeValue;
         if(InpDebugPrint)
            Print("MT4Bridge entry-exit active exit waiting close direction=", activeDir,
                  " bar=", TimeToString(activeBar, TIME_DATE|TIME_SECONDS));
         return false;
      }

      string lastClosedDir = "";
      double lastClosedValue = 0.0;
      datetime lastClosedBar = 0;
      double lastClosedBuyExit = EMPTY_VALUE;
      double lastClosedSellExit = EMPTY_VALUE;
      if(_read_exit_signal_at(1, lastClosedDir, lastClosedValue, lastClosedBar, lastClosedBuyExit, lastClosedSellExit))
      {
         g_exitBaseDirection = lastClosedDir;
         g_exitBaseBarTime = lastClosedBar;
         g_exitBaseValue = lastClosedValue;
         if(InpDebugPrint)
            Print("MT4Bridge entry-exit latest closed exit pending direction=", lastClosedDir,
                  " base_bar=", TimeToString(lastClosedBar, TIME_DATE|TIME_SECONDS));
         return false;
      }

      for(int shift = 2; shift < lookback; shift++)
      {
         double rawBuyExit = EMPTY_VALUE;
         double rawSellExit = EMPTY_VALUE;
         if(_read_exit_signal_at(shift, exitDirection, signalValue, barTime, rawBuyExit, rawSellExit))
         {
            g_exitBaseDirection = "";
            g_exitBaseBarTime = 0;
            g_exitBaseValue = 0.0;
            if(InpDebugPrint)
               Print("MT4Bridge entry-exit resolved from history direction=", exitDirection,
                     " base_bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
                     " lookback_shift=", IntegerToString(shift));
            return true;
         }
      }
      return false;
   }

   int fromShift = MathMax(1, InpExitSignalShift);
   for(int shift = fromShift; shift < lookback; shift++)
   {
      double rawBuyExit = EMPTY_VALUE;
      double rawSellExit = EMPTY_VALUE;
      if(_read_exit_signal_at(shift, exitDirection, signalValue, barTime, rawBuyExit, rawSellExit))
         return true;
   }
   return false;
}

void _check_exit_and_send()
{
   if(!InpEnableExitSignals)
      return;

   string exitDirection = "";
   double signalValue = 0.0;
   datetime barTime = 0;
   if(!_find_latest_exit_signal(exitDirection, signalValue, barTime))
      return;

   if(exitDirection == "BUY")
   {
      if(g_lastBuyExitSentBar == barTime)
         return;
      if(_send_or_queue_event("entry_exit_signal", "BUY_EXIT", signalValue, barTime))
         g_lastBuyExitSentBar = barTime;
      return;
   }

   if(exitDirection == "SELL")
   {
      if(g_lastSellExitSentBar == barTime)
         return;
      if(_send_or_queue_event("entry_exit_signal", "SELL_EXIT", signalValue, barTime))
         g_lastSellExitSentBar = barTime;
      return;
   }
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
         Print("MT4BridgeV2 ambiguous signal (both BUY/SELL active): ", InpIndicatorName, " ", Symbol(), " ", _tf_to_string(Period()));
      }
      if(g_pendingDir != 0)
         _clear_pending_state((dirText == "AMBIGUOUS") ? "ambiguous_signal" : "signal_disappeared", barTime);
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
            Print("MT4BridgeV2 startup baseline confirmed=", dirText, " no execution emitted.");
         return;
      }
   }

   if(direction == g_confirmedDir && g_pendingDir == 0)
      return;

   if(g_pendingDir != direction)
   {
      g_pendingDir = direction;
      g_pendingStartedAt = nowTs;
      g_pendingBar = barTime;
      g_pendingSignalValue = signalPrice;
      g_lastFailedSendAt = 0;
      if(InpDebugPrint)
         Print("MT4BridgeV2 pending started direction=", dirText, " confirm_sec=", IntegerToString(confirmSec));
      return;
   }

   if(confirmSec > 0 && nowTs > 0 && g_pendingStartedAt > 0 && (nowTs - g_pendingStartedAt) < confirmSec)
      return;

   if(direction == g_confirmedDir)
   {
      g_pendingDir = 0;
      g_pendingStartedAt = 0;
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
         Print("MT4BridgeV2 confirmed signal sent direction=", dirText);
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
   g_exitWaitForBlankRuntime = InpExitStreakConfirmAfterBlank;

   string endpointPrimary = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string reason = "";
   if(!_is_supported_webrequest_endpoint(endpointPrimary, reason))
   {
      Print("MT4Bridge config warning: endpoint may fail in MQL4 WebRequest. endpoint=", endpointPrimary, " reason=", reason);
      Print("MT4Bridge note: MQL4 WebRequest supports only http:80 or https:443.");
   }

   int sec = InpPollSeconds;
   if(sec < 1)
      sec = 1;
   EventSetTimer(sec);
   if(InpDebugPrint)
   {
      Print("MT4Bridge initialized: ", InpIndicatorName, " | ", Symbol(), " ", _tf_to_string(Period()));
      Print("MT4Bridge terminal data path: ", TerminalInfoString(TERMINAL_DATA_PATH));
      Print("MT4Bridge iCustom params count: ", IntegerToString(g_iCustomParamCount), " | raw='", InpICustomParamsCsv, "'");
      Print("MT4Bridge endpoint(primary): ", endpointPrimary);
      Print("MT4Bridge endpoint(fallback1): ", _build_endpoint("http://localhost", InpApiPath));
      Print("MT4Bridge endpoint(fallback2): ", _build_endpoint("http://127.0.0.1", InpApiPath));
      Print("MT4Bridge reminder: add URL to MT4 WebRequest whitelist.");
   }
   _debug_startup_snapshot();
   _debug_recent_signal_snapshot();
   _debug_recent_buffer_matrix();
   _debug_recent_objects();
   if(!InpSendInitialExitOnStart)
   {
      string exitDirection = "";
      double exitValue = 0.0;
      datetime exitBar = 0;
      if(_find_latest_exit_signal(exitDirection, exitValue, exitBar))
      {
         if(exitDirection == "BUY")
            g_lastBuyExitSentBar = exitBar;
         else if(exitDirection == "SELL")
            g_lastSellExitSentBar = exitBar;
         if(InpDebugPrint)
            Print("MT4Bridge entry-exit startup baseline exit=", exitDirection,
                  " bar=", TimeToString(exitBar, TIME_DATE|TIME_SECONDS),
                  " no close emitted.");
      }
   }
   if(InpSendRegistrationOnInit)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      _send_or_queue_event("register", "", 0.0, nowTs);
   }
   // Try one immediate read/send at startup so current direction is visible without waiting for timer.
   _check_and_send();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTick()
{
   // Keep empty; timer drives polling with deterministic cadence.
}

void OnTimer()
{
   if(InpResolvedStateSeconds > 0)
   {
      datetime nowResolvedTs = TimeCurrent();
      if(nowResolvedTs <= 0)
         nowResolvedTs = TimeLocal();
      if(nowResolvedTs > 0 && (g_lastResolvedStateAt <= 0 || (nowResolvedTs - g_lastResolvedStateAt) >= InpResolvedStateSeconds))
      {
         string resolvedText = _direction_to_text(g_confirmedDir);
         double stateValue = 0.0;
         datetime stateBar = iTime(NULL, 0, InpSignalShift);
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
   _check_exit_and_send();
   _check_and_send();
   _flush_pending_events();
}

