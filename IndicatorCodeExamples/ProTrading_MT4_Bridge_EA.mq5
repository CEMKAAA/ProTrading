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
input int    InpPollSeconds = 1;     // timer interval
input bool   InpOneSignalPerBar = true;
input bool   InpEmitOnlyOnDirectionChange = true;
input bool   InpSendInitialSignalOnStart = true;
input bool   InpResetDirectionOnNoSignal = true;
input int    InpResendSameDirectionAfterSeconds = 0;
input int    InpRetryFailedSendEverySeconds = 2;
input bool   InpInvertDirection = false;
input bool   InpSendRegistrationOnInit = true;
input bool   InpStartupProbeOnInit = true; // print initial buffer snapshot for fast BUY/SELL map check
input int    InpStartupProbeMaxBuffer = 8; // probe [0..N-1] on init when debug is enabled
input int    InpHeartbeatSeconds = 300; // keepalive every 5 minutes
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;
input int    InpAmbiguousPolicy = 0; // 0=skip, 1=force BUY, 2=force SELL

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
   double buyVal = _buffer_value(InpBuyBufferIndex, InpSignalShift);
   double sellVal = _buffer_value(InpSellBufferIndex, InpSignalShift);
   bool buySignal = InpAllowBuy && _is_signal_value(buyVal);
   bool sellSignal = InpAllowSell && _is_signal_value(sellVal);
   string stateText = _signal_state_text(buySignal, sellSignal);
   string indicatorForLog = (StringLen(g_activeIndicatorName) > 0) ? g_activeIndicatorName : InpIndicatorName;

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
      msg = StringFormat("%s %s %s buffer=%g shift=%d", indicatorForEvent, symbol, dir, signalValue, InpSignalShift);
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
               " endpoint=", endpoint, " response=", resultText);
      return true;
   }

   if(InpDebugPrint)
      Print("MT5Bridge POST failed code=", httpCode, " err=", err, " endpoint=", endpoint, " response=", resultText);
   return false;
}

void _check_and_send()
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
   if(barTime <= 0)
      return;

   double buyVal = _buffer_value(InpBuyBufferIndex, InpSignalShift);
   double sellVal = _buffer_value(InpSellBufferIndex, InpSignalShift);

   bool buySignal = InpAllowBuy && _is_signal_value(buyVal);
   bool sellSignal = InpAllowSell && _is_signal_value(sellVal);

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
         _post_bridge_event("signal_clear", "NONE", 0.0, barTime);
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

   if(_post_bridge_event("signal", dirText, signalPrice, barTime))
   {
      g_lastSentBar = barTime;
      g_lastSentDir = direction;
      g_lastSentAt = TimeCurrent();
      if(g_lastSentAt <= 0)
         g_lastSentAt = TimeLocal();
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
   if(!_parse_iCustom_params())
      return INIT_PARAMETERS_INCORRECT;

   if(!_ensure_indicator_handle())
      return INIT_FAILED;

   EventSetTimer((InpPollSeconds < 1) ? 1 : InpPollSeconds);
   if(InpDebugPrint)
   {
      string indDbg = (StringLen(g_activeIndicatorName) > 0) ? g_activeIndicatorName : InpIndicatorName;
      Print("MT5Bridge initialized: ", indDbg, " | ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
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
      if(_post_bridge_event("register", "", 0.0, nowTs))
         g_lastHeartbeatAt = nowTs;
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
         if(_post_bridge_event("heartbeat", "", 0.0, nowTs))
            g_lastHeartbeatAt = nowTs;
      }
   }
   _check_and_send();
}
