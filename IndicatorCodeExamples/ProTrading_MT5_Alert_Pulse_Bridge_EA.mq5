//+------------------------------------------------------------------+
//| ProTrading MT5 Alert Pulse Bridge EA                             |
//| Dedicated bridge for alert-style indicators with pulse buffers.  |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "SupplyDemand\\ZULU_Wave_ArrowsV3Alerts @FundedMillionAiress";
input string InpBuyPulseBuffersCsv = "2";
input string InpSellPulseBuffersCsv = "1";
input int    InpSignalShift = 0; // 0=current bar
input int    InpPollMilliseconds = 250;
input bool   InpEmitOnlyOnDirectionChange = true;
input bool   InpSendInitialSignalOnStart = true;
input bool   InpSendSignalClearOnNoPulse = true;
input int    InpRetryFailedSendEverySeconds = 2;
input bool   InpSendRegistrationOnInit = true;
input int    InpHeartbeatSeconds = 300;
input int    InpAmbiguousPolicy = 0; // 0=skip, 1=force BUY, 2=force SELL
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;
input int    InpStartupProbeMaxBuffer = 16;

input string InpApiBaseUrl = "http://127.0.0.1:8000";
input string InpApiPath = "/api/v1/mt5/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "supplydemand";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDebugPrint = true;

int      g_indicatorHandle = INVALID_HANDLE;
string   g_activeIndicatorName = "";
int      g_buyBuffers[];
int      g_sellBuffers[];
bool     g_prevBuyActive[];
bool     g_prevSellActive[];
datetime g_lastSentBar = 0;
int      g_lastSentDir = 0;
int      g_lastObservedDir = 0;
datetime g_lastFailedSendAt = 0;
datetime g_lastHeartbeatAt = 0;
bool     g_observedInitialized = false;

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

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

bool _is_digits_only(string s)
{
   int n = StringLen(s);
   if(n <= 0)
      return false;
   for(int i = 0; i < n; i++)
   {
      ushort ch = StringGetCharacter(s, i);
      if(ch < '0' || ch > '9')
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

int _create_indicator_handle_with_name(string indicatorName)
{
   string ind = _trim(indicatorName);
   if(StringLen(ind) <= 0)
      return INVALID_HANDLE;
   return iCustom(_Symbol, PERIOD_CURRENT, ind);
}

bool _ensure_indicator_handle()
{
   if(g_indicatorHandle != INVALID_HANDLE)
      return true;

   string primary = _trim(InpIndicatorName);
   string alias = _strip_trailing_instance_suffix(primary);
   bool hasAlias = (StringLen(alias) > 0 && alias != primary);

   g_indicatorHandle = _create_indicator_handle_with_name(primary);
   if(g_indicatorHandle != INVALID_HANDLE)
   {
      g_activeIndicatorName = primary;
      return true;
   }

   if(hasAlias)
   {
      g_indicatorHandle = _create_indicator_handle_with_name(alias);
      if(g_indicatorHandle != INVALID_HANDLE)
      {
         g_activeIndicatorName = alias;
         if(InpDebugPrint)
            Print("AlertPulseBridge fallback: using alias: ", alias, " (from ", primary, ")");
         return true;
      }
   }

   Print("AlertPulseBridge failed to create indicator handle for ", primary, " err=", GetLastError());
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

bool _parse_buffer_csv(string raw, int &outArr[])
{
   ArrayResize(outArr, 0);
   string src = _trim(raw);
   if(StringLen(src) <= 0)
      return false;
   StringReplace(src, ";", ",");
   StringReplace(src, "|", ",");
   string parts[];
   int n = StringSplit(src, ',', parts);
   if(n <= 0)
      return false;
   for(int i = 0; i < n; i++)
   {
      string tok = _trim(parts[i]);
      if(StringLen(tok) <= 0)
         continue;
      int idx = (int)StringToInteger(tok);
      if(idx < 0 || idx > 255)
         continue;
      int m = ArraySize(outArr);
      ArrayResize(outArr, m + 1);
      outArr[m] = idx;
   }
   return (ArraySize(outArr) > 0);
}

void _init_edge_state_arrays()
{
   ArrayResize(g_prevBuyActive, ArraySize(g_buyBuffers));
   for(int i = 0; i < ArraySize(g_prevBuyActive); i++)
      g_prevBuyActive[i] = false;
   ArrayResize(g_prevSellActive, ArraySize(g_sellBuffers));
   for(int i = 0; i < ArraySize(g_prevSellActive); i++)
      g_prevSellActive[i] = false;
}

bool _post_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime)
{
   string symbol = _Symbol;
   string timeframe = _tf_to_string((ENUM_TIMEFRAMES)_Period);
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string indicatorForEvent = (StringLen(g_activeIndicatorName) > 0) ? g_activeIndicatorName : InpIndicatorName;
   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string msg = "";
   if(StringLen(dir) > 0)
      msg = StringFormat("%s %s %s pulse=%g shift=%d", indicatorForEvent, symbol, dir, signalValue, InpSignalShift);
   else
      msg = StringFormat("MT5AlertPulseBridge %s %s | %s %s", eventKind, indicatorForEvent, symbol, timeframe);

   string body =
      "{"
      "\"indicator\":\"" + _json_escape(indicatorForEvent) + "\","
      "\"signal_hint\":\"" + _json_escape(dir) + "\","
      "\"symbol\":\"" + _json_escape(symbol) + "\","
      "\"timeframe\":\"" + _json_escape(timeframe) + "\","
      "\"signal_profile\":\"" + _json_escape(InpSignalProfile) + "\","
      "\"bridge_event_type\":\"" + _json_escape(eventKind) + "\","
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
         Print("AlertPulseBridge sent ", eventKind, " ", dir, " ", symbol, " ", timeframe,
               " bar=", TimeToString(signalBarTime, TIME_DATE | TIME_SECONDS),
               " endpoint=", endpoint, " response=", resultText);
      return true;
   }
   if(InpDebugPrint)
      Print("AlertPulseBridge POST failed code=", httpCode, " err=", err, " endpoint=", endpoint, " response=", resultText);
   return false;
}

void _debug_startup_snapshot()
{
   if(!InpDebugPrint)
      return;
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
   double buyVal = EMPTY_VALUE;
   double sellVal = EMPTY_VALUE;
   if(ArraySize(g_buyBuffers) > 0)
      buyVal = _buffer_value(g_buyBuffers[0], InpSignalShift);
   if(ArraySize(g_sellBuffers) > 0)
      sellVal = _buffer_value(g_sellBuffers[0], InpSignalShift);
   bool buySignal = InpAllowBuy && _is_signal_value(buyVal);
   bool sellSignal = InpAllowSell && _is_signal_value(sellVal);
   string stateText = "NONE";
   if(buySignal && sellSignal)
      stateText = "AMBIGUOUS";
   else if(buySignal)
      stateText = "BUY";
   else if(sellSignal)
      stateText = "SELL";

   Print("AlertPulseBridge startup snapshot: indicator=", InpIndicatorName,
         " shift=", IntegerToString(InpSignalShift),
         " bar=", TimeToString(barTime, TIME_DATE | TIME_SECONDS),
         " buy[", ((ArraySize(g_buyBuffers) > 0) ? IntegerToString(g_buyBuffers[0]) : "-"), "]=", DoubleToString(buyVal, 8),
         " sell[", ((ArraySize(g_sellBuffers) > 0) ? IntegerToString(g_sellBuffers[0]) : "-"), "]=", DoubleToString(sellVal, 8),
         " state=", stateText);

   int maxBuf = InpStartupProbeMaxBuffer;
   if(maxBuf < 0)
      maxBuf = 0;
   if(maxBuf > 64)
      maxBuf = 64;
   for(int i = 0; i < maxBuf; i++)
   {
      double v = _buffer_value(i, InpSignalShift);
      bool active = _is_signal_value(v);
      Print("AlertPulseBridge startup probe: buffer[", IntegerToString(i), "]=", DoubleToString(v, 8),
            " active=", (active ? "true" : "false"));
   }
}

void _check_and_send()
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
   if(barTime <= 0)
      return;

   bool buyPulse = false;
   bool sellPulse = false;
   double buyVal = 0.0;
   double sellVal = 0.0;

   for(int i = 0; i < ArraySize(g_buyBuffers); i++)
   {
      double v = _buffer_value(g_buyBuffers[i], InpSignalShift);
      bool active = InpAllowBuy && _is_signal_value(v);
      if(active && !g_prevBuyActive[i])
      {
         buyPulse = true;
         buyVal = v;
      }
      g_prevBuyActive[i] = active;
   }

   for(int j = 0; j < ArraySize(g_sellBuffers); j++)
   {
      double v2 = _buffer_value(g_sellBuffers[j], InpSignalShift);
      bool active2 = InpAllowSell && _is_signal_value(v2);
      if(active2 && !g_prevSellActive[j])
      {
         sellPulse = true;
         sellVal = v2;
      }
      g_prevSellActive[j] = active2;
   }

   if(!buyPulse && !sellPulse)
   {
      bool hadDirection = (g_lastObservedDir != 0);
      if(hadDirection && InpSendSignalClearOnNoPulse)
      {
         _post_bridge_event("signal_clear", "NONE", 0.0, barTime);
      }
      g_lastObservedDir = 0;
      g_observedInitialized = true;
      return;
   }

   if(buyPulse && sellPulse)
   {
      if(InpAmbiguousPolicy == 1)
         sellPulse = false;
      else if(InpAmbiguousPolicy == 2)
         buyPulse = false;
      else
      {
         if(InpDebugPrint)
            Print("AlertPulseBridge ambiguous pulse: both BUY/SELL fired same poll.");
         return;
      }
   }

   int direction = 0;
   string dirText = "";
   double signalPrice = 0.0;
   if(buyPulse)
   {
      direction = 1;
      dirText = "BUY";
      signalPrice = buyVal;
   }
   else if(sellPulse)
   {
      direction = -1;
      dirText = "SELL";
      signalPrice = sellVal;
   }
   else
   {
      return;
   }

   bool shouldSend = true;
   if(InpEmitOnlyOnDirectionChange)
   {
      if(!g_observedInitialized)
         shouldSend = InpSendInitialSignalOnStart;
      else
         shouldSend = (direction != g_lastObservedDir);
   }

   if(InpRetryFailedSendEverySeconds > 0 && g_lastFailedSendAt > 0 && g_lastSentDir != direction)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      if(nowTs > 0 && (nowTs - g_lastFailedSendAt) < InpRetryFailedSendEverySeconds)
         shouldSend = false;
   }

   g_lastObservedDir = direction;
   g_observedInitialized = true;
   if(!shouldSend)
      return;

   if(_post_bridge_event("signal", dirText, signalPrice, barTime))
   {
      g_lastSentDir = direction;
      g_lastSentBar = barTime;
      g_lastFailedSendAt = 0;
   }
   else
   {
      g_lastFailedSendAt = TimeCurrent();
      if(g_lastFailedSendAt <= 0)
         g_lastFailedSendAt = TimeLocal();
   }
}

int OnInit()
{
   bool okBuy = _parse_buffer_csv(InpBuyPulseBuffersCsv, g_buyBuffers);
   bool okSell = _parse_buffer_csv(InpSellPulseBuffersCsv, g_sellBuffers);
   if(!okBuy || !okSell)
   {
      Print("AlertPulseBridge invalid buffer CSV config. buy='", InpBuyPulseBuffersCsv, "' sell='", InpSellPulseBuffersCsv, "'");
      return INIT_PARAMETERS_INCORRECT;
   }
   _init_edge_state_arrays();
   if(!_ensure_indicator_handle())
      return INIT_FAILED;

   int ms = InpPollMilliseconds;
   if(ms < 100)
      ms = 100;
   EventSetMillisecondTimer(ms);

   if(InpDebugPrint)
   {
      Print("AlertPulseBridge initialized: ", InpIndicatorName, " | ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      Print("AlertPulseBridge endpoint(primary): ", _build_endpoint(InpApiBaseUrl, InpApiPath));
      Print("AlertPulseBridge buy buffers: ", InpBuyPulseBuffersCsv, " | sell buffers: ", InpSellPulseBuffersCsv);
      Print("AlertPulseBridge poll_ms: ", IntegerToString(ms), " | shift=", IntegerToString(InpSignalShift));
   }

   _debug_startup_snapshot();

   if(InpSendRegistrationOnInit)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      if(_post_bridge_event("register", "", 0.0, nowTs))
         g_lastHeartbeatAt = nowTs;
   }

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
         if(_post_bridge_event("heartbeat", "", 0.0, nowTs))
            g_lastHeartbeatAt = nowTs;
      }
   }
   _check_and_send();
}

