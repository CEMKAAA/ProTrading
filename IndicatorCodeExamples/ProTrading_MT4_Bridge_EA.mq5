//+------------------------------------------------------------------+
//| ProTrading MT5 Bridge EA                                         |
//| Sends indicator BUY/SELL signals directly to ProTrading backend. |
//| File name intentionally matches existing MT4 bridge naming.      |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "IntrepidIndicator\\Intrepid Trend Direction";
input int    InpBuyBufferIndex = 0;
input int    InpSellBufferIndex = 1;
input string InpICustomParamsCsv = ""; // Optional indicator Inputs as CSV: e.g. "14,0,1"
input int    InpSignalShift = 0;     // 0=current bar, 1=closed bar
input int    InpPollSeconds = 3;     // timer interval (default 3s, min 1s)
input bool   InpOneSignalPerBar = true;
input bool   InpEmitOnlyOnDirectionChange = true;
input bool   InpSendInitialSignalOnStart = true;
input bool   InpResetDirectionOnNoSignal = true;
input int    InpResendSameDirectionAfterSeconds = 0;
input int    InpRetryFailedSendEverySeconds = 2;
input int    InpMaxPendingEvents = 200;
input bool   InpInvertDirection = false;
input bool   InpSendRegistrationOnInit = true;
input bool   InpStartupProbeOnInit = true; // print initial buffer snapshot for fast BUY/SELL map check
input int    InpStartupProbeMaxBuffer = 8; // probe [0..N-1] on init when debug is enabled
input int    InpHeartbeatSeconds = 300; // keepalive every 5 minutes
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;
input int    InpAmbiguousPolicy = 0; // 0=skip, 1=force BUY, 2=force SELL
input int    InpSignalSourceMode = 0; // 0=buffers, 1=chart objects
input string InpObjectBuyNamePattern = "buy";
input string InpObjectSellNamePattern = "sell";
input string InpObjectBuyArrowCodesCsv = "233,241,217,225";
input string InpObjectSellArrowCodesCsv = "234,242,218,226";
input int    InpObjectLookbackSeconds = 180;
input bool   InpObjectUsePriceHeuristic = true;

input string InpApiBaseUrl = "http://127.0.0.1:8000";
input string InpApiPath = "/api/v1/mt5/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "intrepid";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDebugPrint = true;

datetime g_lastSentBar = 0;
int      g_lastSentDir = 0;
int      g_lastObservedDir = 0;
datetime g_lastSentAt = 0;
datetime g_lastFailedSendAt = 0;
datetime g_lastHeartbeatAt = 0;
bool     g_observedInitialized = false;
string   g_activeIndicatorName = "";
double   g_iCustomParams[];
int      g_iCustomParamCount = 0;
int      g_indicatorHandle = INVALID_HANDLE;

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
datetime g_lastObjectProcessedAt = 0;

string _tf_to_string(ENUM_TIMEFRAMES tf)
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
   return IntegerToString((int)tf);
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
      b = "http://127.0.0.1:8000";
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
   string ind = (StringLen(g_activeIndicatorName) > 0) ? g_activeIndicatorName : InpIndicatorName;
   string seed = StringFormat(
      "%s|%s|%s|%s|%s|%I64d",
      _trim(eventType),
      _trim(direction),
      _Symbol,
      _tf_to_string((ENUM_TIMEFRAMES)_Period),
      ind,
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
   if(evt == "signal")
   {
      int d = 0;
      if(dir == "BUY")
         d = 1;
      else if(dir == "SELL")
         d = -1;
      if(d != 0)
      {
         g_lastSentBar = signalBarTime;
         g_lastSentDir = d;
         g_lastSentAt = TimeCurrent();
         if(g_lastSentAt <= 0)
            g_lastSentAt = TimeLocal();
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
}

void _queue_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime, string eventId)
{
   string eid = _trim(eventId);
   if(StringLen(eid) <= 0)
      eid = _build_event_id(eventType, direction, signalBarTime);

   int existing = _find_pending_event_by_id(eid);
   if(existing >= 0)
   {
      // Refresh payload in-place; keep attempts so retry pacing is preserved.
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
      _remove_pending_event_at(0); // drop oldest to keep queue bounded
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
      return false; // keep order: stop after first unsent event
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
      // Drain any older failed events opportunistically.
      _flush_pending_events();
      return true;
   }

   _queue_bridge_event(eventType, direction, signalValue, signalBarTime, eid);
   _flush_pending_events();
   return false;
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

bool _contains_ci(string haystack, string needle)
{
   string h = haystack;
   string n = needle;
   StringToLower(h);
   StringToLower(n);
   if(StringLen(n) <= 0)
      return false;
   return (StringFind(h, n) >= 0);
}

int _direction_from_object_name(string objName)
{
   bool buyHit = _contains_ci(objName, InpObjectBuyNamePattern);
   bool sellHit = _contains_ci(objName, InpObjectSellNamePattern);
   if(buyHit && (!sellHit))
      return 1;
   if(sellHit && (!buyHit))
      return -1;
   return 0;
}

bool _csv_has_int_code(string csv, long code)
{
   string raw = _trim(csv);
   if(StringLen(raw) <= 0)
      return false;
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   StringReplace(raw, " ", ",");

   string parts[];
   int n = StringSplit(raw, ',', parts);
   if(n <= 0)
      return false;
   for(int i = 0; i < n; i++)
   {
      string t = _trim(parts[i]);
      if(StringLen(t) <= 0)
         continue;
      long v = (long)StringToInteger(t);
      if(v == code)
         return true;
   }
   return false;
}

int _direction_from_object_arrowcode(string objName)
{
   long code = (long)ObjectGetInteger(0, objName, OBJPROP_ARROWCODE, 0);
   if(code <= 0)
      code = (long)ObjectGetInteger(0, objName, OBJPROP_ARROWCODE);
   if(code <= 0)
      return 0;

   if(_csv_has_int_code(InpObjectBuyArrowCodesCsv, code))
      return 1;
   if(_csv_has_int_code(InpObjectSellArrowCodesCsv, code))
      return -1;
   return 0;
}

int _direction_from_object_price(datetime objTime, double objPrice)
{
   if(!InpObjectUsePriceHeuristic)
      return 0;
   if(!_is_signal_value(objPrice))
      return 0;
   int shift = iBarShift(_Symbol, PERIOD_CURRENT, objTime, false);
   if(shift < 0)
      return 0;
   double h = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double l = iLow(_Symbol, PERIOD_CURRENT, shift);
   double p = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(p <= 0.0)
      p = 0.0001;
   double tol = p * 2.0;
   if(objPrice >= (h + tol))
      return -1;
   if(objPrice <= (l - tol))
      return 1;
   return 0;
}

bool _detect_object_signal(int &direction, double &signalPrice, datetime &signalTime, string &objectName)
{
   direction = 0;
   signalPrice = 0.0;
   signalTime = 0;
   objectName = "";

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   int lookback = InpObjectLookbackSeconds;
   if(lookback < 5)
      lookback = 5;
   if(lookback > 86400)
      lookback = 86400;
   datetime minTs = (nowTs > 0) ? (nowTs - lookback) : 0;

   datetime bestTs = 0;
   int bestDir = 0;
   double bestPx = 0.0;
   string bestName = "";

   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringLen(nm) <= 0)
         continue;

      datetime ot = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
      if(ot <= 0)
         ot = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME);
      if(ot <= 0)
         continue;
      if(ot <= g_lastObjectProcessedAt)
         continue;
      if(minTs > 0 && ot < minTs)
         continue;

      double op = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
      if(!_is_signal_value(op))
         op = ObjectGetDouble(0, nm, OBJPROP_PRICE);

      int dir = _direction_from_object_name(nm);
      if(dir == 0)
         dir = _direction_from_object_arrowcode(nm);
      if(dir == 0)
         dir = _direction_from_object_price(ot, op);
      if(dir == 0)
         continue;

      if((dir > 0 && (!InpAllowBuy)) || (dir < 0 && (!InpAllowSell)))
         continue;

      if(bestTs <= 0 || ot > bestTs)
      {
         bestTs = ot;
         bestDir = dir;
         bestPx = op;
         bestName = nm;
      }
   }

   if(bestDir == 0 || bestTs <= 0)
      return false;

   direction = bestDir;
   signalPrice = bestPx;
   signalTime = bestTs;
   objectName = bestName;
   return true;
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
   int n = StringSplit(raw, ',', tokens);
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
         val = StringToDouble(token);

      if(val == 0.0 && token != "0" && token != "0.0" && lower != "false")
      {
         Print("MT5Bridge invalid InpICustomParamsCsv token: ", token,
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

bool _is_digits_only(string s)
{
   int n = StringLen(s);
   if(n <= 0)
      return false;
   for(int i = 0; i < n; i++)
   {
      int ch = StringGetCharacter(s, i);
      if(ch < 48 || ch > 57)
         return false;
   }
   return true;
}

string _strip_trailing_instance_suffix(string name)
{
   string raw = _trim(name);
   int n = StringLen(raw);
   if(n < 5)
      return raw;
   if(StringSubstr(raw, n - 1, 1) != ")")
      return raw;

   int pos = -1;
   int probe = StringFind(raw, " (");
   while(probe >= 0)
   {
      pos = probe;
      probe = StringFind(raw, " (", probe + 1);
   }
   if(pos <= 0)
      return raw;

   string inside = StringSubstr(raw, pos + 2, n - pos - 3);
   if(!_is_digits_only(inside))
      return raw;

   string base = _trim(StringSubstr(raw, 0, pos));
   if(StringLen(base) <= 0)
      return raw;
   return base;
}

int _create_indicator_handle_with_name(string indicatorName, bool useParams)
{
   string ind = _trim(indicatorName);
   if(StringLen(ind) <= 0)
      return INVALID_HANDLE;
   int c = g_iCustomParamCount;
   if(!useParams || c <= 0)  return iCustom(_Symbol, PERIOD_CURRENT, ind);
   if(c == 1)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0]);
   if(c == 2)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1]);
   if(c == 3)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2]);
   if(c == 4)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3]);
   if(c == 5)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4]);
   if(c == 6)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5]);
   if(c == 7)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6]);
   if(c == 8)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7]);
   if(c == 9)  return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8]);
   if(c == 10) return iCustom(_Symbol, PERIOD_CURRENT, ind, g_iCustomParams[0], g_iCustomParams[1], g_iCustomParams[2], g_iCustomParams[3], g_iCustomParams[4], g_iCustomParams[5], g_iCustomParams[6], g_iCustomParams[7], g_iCustomParams[8], g_iCustomParams[9]);

   Print("MT5Bridge too many InpICustomParamsCsv values: ", c, " (max supported: 10)");
   return INVALID_HANDLE;
}

bool _ensure_indicator_handle()
{
   if(g_indicatorHandle != INVALID_HANDLE)
      return true;

   string primary = _trim(InpIndicatorName);
   string alias = _strip_trailing_instance_suffix(primary);
   bool hasAlias = (StringLen(alias) > 0 && alias != primary);

   g_indicatorHandle = _create_indicator_handle_with_name(primary, true);
   if(g_indicatorHandle != INVALID_HANDLE)
   {
      g_activeIndicatorName = primary;
      return true;
   }
   int err1 = GetLastError();

   if(hasAlias)
   {
      g_indicatorHandle = _create_indicator_handle_with_name(alias, true);
      if(g_indicatorHandle != INVALID_HANDLE)
      {
         g_activeIndicatorName = alias;
         if(InpDebugPrint)
            Print("MT5Bridge indicator fallback: using alias with params: ", alias, " (from ", primary, ")");
         return true;
      }
   }

   if(g_iCustomParamCount > 0)
   {
      g_indicatorHandle = _create_indicator_handle_with_name(primary, false);
      if(g_indicatorHandle != INVALID_HANDLE)
      {
         g_activeIndicatorName = primary;
         if(InpDebugPrint)
            Print("MT5Bridge indicator fallback: using no iCustom params for ", primary);
         return true;
      }
      if(hasAlias)
      {
         g_indicatorHandle = _create_indicator_handle_with_name(alias, false);
         if(g_indicatorHandle != INVALID_HANDLE)
         {
            g_activeIndicatorName = alias;
            if(InpDebugPrint)
               Print("MT5Bridge indicator fallback: using alias without params: ", alias, " (from ", primary, ")");
            return true;
         }
      }
   }

   Print("MT5Bridge failed to create indicator handle for ", primary, " last_error=", GetLastError(), " first_error=", err1);
   return false;
}

double _buffer_value(int bufferIndex, int barShift)
{
   if(!_ensure_indicator_handle())
      return EMPTY_VALUE;
   double values[];
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(g_indicatorHandle, bufferIndex, barShift, 1, values);
   if(copied < 1)
      return EMPTY_VALUE;
   return values[0];
}

void _debug_startup_snapshot()
{
   if(!InpDebugPrint || !InpStartupProbeOnInit)
      return;

   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
   string indicatorForLog = (StringLen(g_activeIndicatorName) > 0) ? g_activeIndicatorName : InpIndicatorName;
   int sourceMode = InpSignalSourceMode;
   if(sourceMode != 1)
      sourceMode = 0;

   double buyVal = EMPTY_VALUE;
   double sellVal = EMPTY_VALUE;
   bool buySignal = false;
   bool sellSignal = false;
   string stateText = "NONE";

   if(sourceMode == 1)
   {
      int objDir = 0;
      double objPx = 0.0;
      datetime objTs = 0;
      string objName = "";
      if(_detect_object_signal(objDir, objPx, objTs, objName))
      {
         if(objDir > 0)
         {
            buySignal = true;
            buyVal = objPx;
         }
         else if(objDir < 0)
         {
            sellSignal = true;
            sellVal = objPx;
         }
         if(objTs > 0)
            barTime = objTs;
      }
      stateText = _signal_state_text(buySignal, sellSignal);
      Print("MT5Bridge startup snapshot(object): indicator=", indicatorForLog,
            " mode=objects",
            " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
            " state=", stateText,
            " buy=", DoubleToString(buyVal, 8),
            " sell=", DoubleToString(sellVal, 8),
            " pattern_buy='", InpObjectBuyNamePattern, "'",
            " pattern_sell='", InpObjectSellNamePattern, "'",
            " buy_codes='", InpObjectBuyArrowCodesCsv, "'",
            " sell_codes='", InpObjectSellArrowCodesCsv, "'");
      return;
   }

   buyVal = _buffer_value(InpBuyBufferIndex, InpSignalShift);
   sellVal = _buffer_value(InpSellBufferIndex, InpSignalShift);
   buySignal = InpAllowBuy && _is_signal_value(buyVal);
   sellSignal = InpAllowSell && _is_signal_value(sellVal);
   stateText = _signal_state_text(buySignal, sellSignal);

   if(InpInvertDirection)
   {
      if(stateText == "BUY")
         stateText = "SELL";
      else if(stateText == "SELL")
         stateText = "BUY";
   }

   Print("MT5Bridge startup snapshot: indicator=", indicatorForLog,
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
      double v = _buffer_value(i, InpSignalShift);
      bool active = _is_signal_value(v);
      Print("MT5Bridge startup probe: buffer[", IntegerToString(i), "]=",
            DoubleToString(v, 8), " active=", (active ? "true" : "false"));
   }
}

bool _post_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime, string eventId = "", int eventAttempt = 1)
{
   string symbol = _Symbol;
   string timeframe = _tf_to_string((ENUM_TIMEFRAMES)_Period);
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string indicatorForEvent = (StringLen(g_activeIndicatorName) > 0) ? g_activeIndicatorName : InpIndicatorName;
   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string msg = "";
   if(StringLen(dir) > 0)
      msg = StringFormat("%s %s %s value=%g shift=%d mode=%s", indicatorForEvent, symbol, dir, signalValue, InpSignalShift, (InpSignalSourceMode == 1 ? "objects" : "buffers"));
   else
      msg = StringFormat("MT5Bridge %s %s | %s %s", eventKind, indicatorForEvent, symbol, timeframe);

   string body =
      "{" 
      "\"indicator\":\"" + _json_escape(indicatorForEvent) + "\"," 
      "\"signal_hint\":\"" + _json_escape(dir) + "\"," 
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
      headers = headers + "X-MT5-Bridge-Token: " + InpBridgeToken + "\r\n";

   char postData[];
   char resultData[];
   string resultHeaders = "";
   StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);

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
   return false;
}

void _check_and_send()
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
   if(barTime <= 0)
      return;

   int sourceMode = InpSignalSourceMode;
   if(sourceMode != 1)
      sourceMode = 0;

   double buyVal = EMPTY_VALUE;
   double sellVal = EMPTY_VALUE;
   bool buySignal = false;
   bool sellSignal = false;

   if(sourceMode == 1)
   {
      int objDir = 0;
      double objPx = 0.0;
      datetime objTs = 0;
      string objName = "";
      bool found = _detect_object_signal(objDir, objPx, objTs, objName);
      if(found)
      {
         if(objTs > 0)
            barTime = objTs;
         if(objDir > 0)
         {
            buySignal = true;
            buyVal = objPx;
         }
         else if(objDir < 0)
         {
            sellSignal = true;
            sellVal = objPx;
         }
         if(barTime > g_lastObjectProcessedAt)
            g_lastObjectProcessedAt = barTime;
         if(InpDebugPrint)
            Print("MT5Bridge object signal: name=", objName,
                  " dir=", (objDir > 0 ? "BUY" : "SELL"),
                  " time=", TimeToString(barTime, TIME_DATE|TIME_SECONDS),
                  " price=", DoubleToString(objPx, 8));
      }
   }
   else
   {
      buyVal = _buffer_value(InpBuyBufferIndex, InpSignalShift);
      sellVal = _buffer_value(InpSellBufferIndex, InpSignalShift);
      buySignal = InpAllowBuy && _is_signal_value(buyVal);
      sellSignal = InpAllowSell && _is_signal_value(sellVal);
   }

   if(buySignal && sellSignal)
   {
      if(InpAmbiguousPolicy == 1)
      {
         sellSignal = false;
         if(InpDebugPrint)
            Print("MT5Bridge ambiguous resolved as BUY by policy for ", InpIndicatorName, " ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      }
      else if(InpAmbiguousPolicy == 2)
      {
         buySignal = false;
         if(InpDebugPrint)
            Print("MT5Bridge ambiguous resolved as SELL by policy for ", InpIndicatorName, " ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      }
      else
      {
         if(InpDebugPrint)
            Print("MT5Bridge ambiguous signal (both BUY/SELL active): ", InpIndicatorName, " ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
         return;
      }
   }

   int direction = 0;
   double signalPrice = 0.0;
   string dirText = "";

   if(buySignal)
   {
      direction = 1;
      signalPrice = buyVal;
      dirText = "BUY";
   }
   else if(sellSignal)
   {
      direction = -1;
      signalPrice = sellVal;
      dirText = "SELL";
   }
   else
   {
      bool hadDirection = (g_lastObservedDir != 0);
      if(InpResetDirectionOnNoSignal)
         g_lastObservedDir = 0;
      if(hadDirection)
      {
         _send_or_queue_event("signal_clear", "NONE", 0.0, barTime);
      }
      g_observedInitialized = true;
      return;
   }

   if(InpInvertDirection)
   {
      direction = -direction;
      dirText = (direction > 0) ? "BUY" : "SELL";
      signalPrice = (direction > 0) ? buyVal : sellVal;
   }

   bool shouldSend = true;
   bool directionChanged = g_observedInitialized && (direction != g_lastObservedDir);
   if(directionChanged)
      g_lastFailedSendAt = 0;

   if(InpEmitOnlyOnDirectionChange)
   {
      if(!g_observedInitialized)
      {
         shouldSend = InpSendInitialSignalOnStart;
         if(!shouldSend)
         {
            g_lastSentDir = direction;
            g_lastSentBar = barTime;
         }
      }
      else if(direction == g_lastObservedDir)
      {
         shouldSend = false;
         if(g_lastSentDir != direction)
            shouldSend = true;
         if(InpResendSameDirectionAfterSeconds > 0 && g_lastSentAt > 0 && direction == g_lastSentDir)
         {
            datetime nowTs = TimeCurrent();
            if(nowTs <= 0)
               nowTs = TimeLocal();
            if(nowTs > 0 && (nowTs - g_lastSentAt) >= InpResendSameDirectionAfterSeconds)
               shouldSend = true;
         }
      }
   }

   if(InpOneSignalPerBar && g_lastSentBar == barTime && g_lastSentDir == direction)
      shouldSend = false;

   if(shouldSend && InpRetryFailedSendEverySeconds > 0 && g_lastFailedSendAt > 0 && g_lastSentDir != direction)
   {
      datetime nowRetryTs = TimeCurrent();
      if(nowRetryTs <= 0)
         nowRetryTs = TimeLocal();
      if(nowRetryTs > 0 && (nowRetryTs - g_lastFailedSendAt) < InpRetryFailedSendEverySeconds)
         shouldSend = false;
   }

   g_lastObservedDir = direction;
   g_observedInitialized = true;

   if(!shouldSend)
      return;

   if(!_send_or_queue_event("signal", dirText, signalPrice, barTime))
   {
      g_lastFailedSendAt = TimeCurrent();
      if(g_lastFailedSendAt <= 0)
         g_lastFailedSendAt = TimeLocal();
   }
}

int OnInit()
{
   if(!_parse_iCustom_params())
      return INIT_PARAMETERS_INCORRECT;

   int sourceMode = InpSignalSourceMode;
   if(sourceMode != 1)
      sourceMode = 0;
   if(sourceMode == 0)
   {
      if(!_ensure_indicator_handle())
         return INIT_FAILED;
   }

   EventSetTimer((InpPollSeconds < 1) ? 1 : InpPollSeconds);
   if(InpDebugPrint)
   {
      string indDbg = (StringLen(g_activeIndicatorName) > 0) ? g_activeIndicatorName : InpIndicatorName;
      Print("MT5Bridge initialized: ", indDbg, " | ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      Print("MT5Bridge signal source mode: ", (InpSignalSourceMode == 1 ? "objects" : "buffers"));
      Print("MT5Bridge terminal data path: ", TerminalInfoString(TERMINAL_DATA_PATH));
      Print("MT5Bridge iCustom params count: ", IntegerToString(g_iCustomParamCount), " | raw='", InpICustomParamsCsv, "'");
      Print("MT5Bridge endpoint(primary): ", _build_endpoint(InpApiBaseUrl, InpApiPath));
      Print("MT5Bridge reminder: add URL to MT5 WebRequest whitelist.");
   }
   _debug_startup_snapshot();
   if(InpSendRegistrationOnInit)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      _send_or_queue_event("register", "", 0.0, nowTs);
   }
   // Try one immediate read/send at startup so current direction is visible without waiting for timer.
   _check_and_send();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_indicatorHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_indicatorHandle);
      g_indicatorHandle = INVALID_HANDLE;
   }
}

void OnTick()
{
}

void OnTimer()
{
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
