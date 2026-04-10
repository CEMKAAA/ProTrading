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
input int    InpHeartbeatSeconds = 60;
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;

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
         val = StrToDouble(token);

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

int _create_indicator_handle()
{
   int c = g_iCustomParamCount;
   if(c <= 0)  return iCustom(_Symbol, PERIOD_CURRENT, InpIndicatorName);
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

   Print("MT5Bridge too many InpICustomParamsCsv values: ", c, " (max supported: 10)");
   return INVALID_HANDLE;
}

bool _ensure_indicator_handle()
{
   if(g_indicatorHandle != INVALID_HANDLE)
      return true;
   g_indicatorHandle = _create_indicator_handle();
   if(g_indicatorHandle == INVALID_HANDLE)
   {
      Print("MT5Bridge failed to create indicator handle for ", InpIndicatorName, " last_error=", GetLastError());
      return false;
   }
   return true;
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

bool _post_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime)
{
   string symbol = _Symbol;
   string timeframe = _tf_to_string((ENUM_TIMEFRAMES)_Period);
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string msg = "";
   if(StringLen(dir) > 0)
      msg = StringFormat("%s %s %s buffer=%g shift=%d", InpIndicatorName, symbol, dir, signalValue, InpSignalShift);
   else
      msg = StringFormat("MT5Bridge %s %s | %s %s", eventKind, InpIndicatorName, symbol, timeframe);

   string body =
      "{" 
      "\"indicator\":\"" + _json_escape(InpIndicatorName) + "\"," 
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
      if(InpDebugPrint)
         Print("MT5Bridge ambiguous signal (both BUY/SELL active): ", InpIndicatorName, " ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      return;
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
      if(InpResetDirectionOnNoSignal)
         g_lastObservedDir = 0;
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
      Print("MT5Bridge initialized: ", InpIndicatorName, " | ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      Print("MT5Bridge terminal data path: ", TerminalInfoString(TERMINAL_DATA_PATH));
      Print("MT5Bridge iCustom params count: ", IntegerToString(g_iCustomParamCount), " | raw='", InpICustomParamsCsv, "'");
      Print("MT5Bridge endpoint(primary): ", _build_endpoint(InpApiBaseUrl, InpApiPath));
      Print("MT5Bridge reminder: add URL to MT5 WebRequest whitelist.");
   }
   if(InpSendRegistrationOnInit)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      if(_post_bridge_event("register", "", 0.0, nowTs))
         g_lastHeartbeatAt = nowTs;
   }
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
