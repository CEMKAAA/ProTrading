//+------------------------------------------------------------------+
//| ProTrading RSI Telemetry Bridge EA (MT5)                         |
//| Sends RSI line values to backend as rsi_telemetry events.        |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "H1_RSI_Line_Cem";
input int    InpRsiBufferIndex = 0;
input int    InpValueShift = 0;        // 0=current bar, 1=closed bar
input string InpICustomParamsCsv = ""; // Optional indicator inputs as CSV
input string InpRsiIndicatorTf = "H1"; // metadata only
input int    InpRsiPeriod = 14;        // metadata only

input int    InpPollSeconds = 1;
input int    InpTelemetryEverySeconds = 1;
input bool   InpSendOnChangeOnly = true;
input double InpMinDelta = 0.05;
input bool   InpSendRegistrationOnInit = true;
input int    InpHeartbeatSeconds = 300;

input string InpApiBaseUrl = "http://127.0.0.1:8000";
input string InpApiPath = "/api/v1/mt5/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "rsi_telemetry";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDebugPrint = true;

double   g_iCustomParams[];
int      g_iCustomParamCount = 0;
double   g_lastRsi = 0.0;
bool     g_hasLastRsi = false;
datetime g_lastSentAt = 0;
datetime g_lastHeartbeatAt = 0;
int      g_indicatorHandle = INVALID_HANDLE;

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
         Print("RSIBridge invalid InpICustomParamsCsv token: ", token);
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
   string ind = _trim(InpIndicatorName);
   int c = g_iCustomParamCount;
   if(c <= 0)  return iCustom(_Symbol, PERIOD_CURRENT, ind);
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
   return INVALID_HANDLE;
}

bool _ensure_handle()
{
   if(g_indicatorHandle != INVALID_HANDLE)
      return true;
   g_indicatorHandle = _create_indicator_handle();
   if(g_indicatorHandle == INVALID_HANDLE)
   {
      Print("RSIBridge failed to create indicator handle for ", InpIndicatorName, " err=", GetLastError());
      return false;
   }
   return true;
}

double _read_rsi_value(int bufferIndex, int shift)
{
   if(!_ensure_handle())
      return EMPTY_VALUE;
   double values[];
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(g_indicatorHandle, bufferIndex, shift, 1, values);
   if(copied < 1)
      return EMPTY_VALUE;
   return values[0];
}

bool _post_rsi_event(string eventType, double rsiValue, datetime barTime)
{
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string symbol = _Symbol;
   string timeframe = _tf_to_string((ENUM_TIMEFRAMES)_Period);
   string eventKind = _trim(eventType);
   string msg = StringFormat("%s %s %s RSI=%s shift=%d", InpIndicatorName, symbol, timeframe, DoubleToString(rsiValue, 8), InpValueShift);
   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpIndicatorName) + "\","
      "\"signal_hint\":\"\","
      "\"symbol\":\"" + _json_escape(symbol) + "\","
      "\"timeframe\":\"" + _json_escape(timeframe) + "\","
      "\"signal_profile\":\"" + _json_escape(InpSignalProfile) + "\","
      "\"bridge_event_type\":\"" + _json_escape(eventKind) + "\","
      "\"rsi_value\":" + DoubleToString(rsiValue, 8) + ","
      "\"indicator_tf\":\"" + _json_escape(InpRsiIndicatorTf) + "\","
      "\"rsi_period\":" + IntegerToString(InpRsiPeriod) + ","
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
         Print("RSIBridge sent ", eventKind, " ", symbol, " ", timeframe, " rsi=", DoubleToString(rsiValue, 4), " response=", resultText);
      return true;
   }
   if(InpDebugPrint)
      Print("RSIBridge POST failed code=", httpCode, " err=", err, " endpoint=", endpoint, " response=", resultText);
   return false;
}

void _check_and_send()
{
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpValueShift);
   if(barTime <= 0)
      return;
   double rsiVal = _read_rsi_value(InpRsiBufferIndex, InpValueShift);
   if(!MathIsValidNumber(rsiVal) || rsiVal == EMPTY_VALUE)
      return;

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   if(nowTs <= 0)
      return;

   bool changed = (!g_hasLastRsi) || (MathAbs(rsiVal - g_lastRsi) >= InpMinDelta);
   bool dueByInterval = (InpTelemetryEverySeconds <= 0) || (g_lastSentAt <= 0) || ((nowTs - g_lastSentAt) >= InpTelemetryEverySeconds);

   bool shouldSend = false;
   if(!g_hasLastRsi)
      shouldSend = true;
   else if(InpSendOnChangeOnly)
      shouldSend = (changed || dueByInterval);
   else
      shouldSend = dueByInterval;

   g_lastRsi = rsiVal;
   g_hasLastRsi = true;

   if(!shouldSend)
      return;

   if(_post_rsi_event("rsi_telemetry", rsiVal, barTime))
      g_lastSentAt = nowTs;
}

int OnInit()
{
   if(!_parse_iCustom_params())
      return(INIT_PARAMETERS_INCORRECT);
   if(!_ensure_handle())
      return(INIT_FAILED);

   int sec = InpPollSeconds;
   if(sec < 1)
      sec = 1;
   EventSetTimer(sec);

   if(InpDebugPrint)
   {
      Print("RSIBridge initialized: ", InpIndicatorName, " | ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      Print("RSIBridge endpoint: ", _build_endpoint(InpApiBaseUrl, InpApiPath));
   }
   if(InpSendRegistrationOnInit)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      if(_post_rsi_event("register", 0.0, nowTs))
         g_lastHeartbeatAt = nowTs;
   }

   return(INIT_SUCCEEDED);
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

void OnTick() {}

void OnTimer()
{
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   if(InpHeartbeatSeconds > 0 && nowTs > 0 && (g_lastHeartbeatAt <= 0 || (nowTs - g_lastHeartbeatAt) >= InpHeartbeatSeconds))
   {
      if(_post_rsi_event("heartbeat", g_lastRsi, nowTs))
         g_lastHeartbeatAt = nowTs;
   }
   _check_and_send();
}

