//+------------------------------------------------------------------+
//| ProTrading MT4 Buffer Bridge EA V2                              |
//| Stabilizes indicator BUY/SELL state before backend execution.    |
//|                                                                  |
//| Setup notes:                                                     |
//| 1) Attach this EA to the same chart where your indicator runs.   |
//| 2) Set indicator name + BUY/SELL buffer indexes.                 |
//| 3) MT4 -> Tools -> Options -> Expert Advisors ->                 |
//|    "Allow WebRequest for listed URL": add http://127.0.0.1      |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "IntrepidIndicator\\Intrepid Trend Direction";
input int    InpBuyBufferIndex = 0;
input int    InpSellBufferIndex = 1;
input string InpICustomParamsCsv = ""; // Optional indicator Inputs as CSV: e.g. "14,0,1"
input int    InpSignalShift = 0;     // 0=current bar, 1=closed bar
input int    InpPollSeconds = 1;     // V2 state machine poll cadence
input int    InpConfirmSeconds = 20; // resolved direction must stay stable this long
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
input int    InpHeartbeatSeconds = 300; // registration keepalive only
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;

input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "intrepid";
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
   bool buySignal = InpAllowBuy && _is_signal_value(buyVal);
   bool sellSignal = InpAllowSell && _is_signal_value(sellVal);
   string stateText = _signal_state_text(buySignal, sellSignal);

   if(InpInvertDirection)
   {
      if(stateText == "BUY")
         stateText = "SELL";
      else if(stateText == "SELL")
         stateText = "BUY";
   }

   Print("MT4Bridge startup snapshot: indicator=", InpIndicatorName,
         " shift=", IntegerToString(InpSignalShift),
         " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
         " buy[", IntegerToString(InpBuyBufferIndex), "]=", DoubleToString(buyVal, 8),
         " sell[", IntegerToString(InpSellBufferIndex), "]=", DoubleToString(sellVal, 8),
         " state=", stateText,
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

      string resolved = buySignal ? "BUY" : "SELL";
      if(InpInvertDirection)
      {
         if(resolved == "BUY")
            resolved = "SELL";
         else
            resolved = "BUY";
      }

      Print("MT4Bridge startup recent last signal: lookback=", IntegerToString(lookback),
            " shift=", IntegerToString(shift),
            " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
            " raw_buy[", IntegerToString(InpBuyBufferIndex), "]=", DoubleToString(buyVal, 8),
            " raw_sell[", IntegerToString(InpSellBufferIndex), "]=", DoubleToString(sellVal, 8),
            " resolved=", resolved,
            " invert=", (InpInvertDirection ? "true" : "false"));
      return;
   }

   Print("MT4Bridge startup recent last signal: NONE within lookback=",
         IntegerToString(lookback));
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

bool _read_resolved_signal(int barShift, int &direction, string &dirText, double &signalValue, datetime &barTime, double &rawBuy, double &rawSell)
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
   int confirmSec = InpConfirmSeconds;
   if(confirmSec < 0)
      confirmSec = 0;

   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpIndicatorName) + "\","
      "\"signal_hint\":\"" + _json_escape(dir) + "\","
      "\"resolved_signal\":\"" + _json_escape((dirInt != 0) ? _direction_to_text(dirInt) : confirmedText) + "\","
      "\"confirmed_direction\":\"" + _json_escape(confirmedText) + "\","
      "\"pending_direction\":\"" + _json_escape((g_pendingDir != 0) ? pendingText : "") + "\","
      "\"pending_age_sec\":" + IntegerToString(pendingAge) + ","
      "\"confirm_seconds\":" + IntegerToString(confirmSec) + ","
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
      return;
   }

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   int confirmSec = InpConfirmSeconds;
   if(confirmSec < 0)
      confirmSec = 0;

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
   _check_and_send();
   _flush_pending_events();
}

