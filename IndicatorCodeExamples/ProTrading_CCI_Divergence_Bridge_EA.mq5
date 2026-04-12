//+------------------------------------------------------------------+
//| ProTrading CCI Divergence Bridge EA (MT5)                        |
//| Reads indicator Value buffer and emits BUY/SELL bridge signals.  |
//|                                                                  |
//| Rule:                                                            |
//| - SELL when ValueBuffer > PriceRef                               |
//| - BUY  when PriceRef > ValueBuffer                               |
//| - Direction must persist for InpConfirmSeconds before emit.      |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "CCI Divergence";
input int    InpValueBufferIndex = 4;        // Data Window "Value 4" => buffer index 4
input string InpICustomParamsCsv = "";       // Optional indicator inputs as CSV
input int    InpSignalShift = 0;             // 0=current bar, 1=closed bar
input int    InpPollSeconds = 1;             // timer cadence
input int    InpConfirmSeconds = 20;         // signal must persist this long
input int    InpPriceSource = 2;             // 0=Bid,1=Ask,2=Mid,3=Close(shift)
input double InpCompareEpsilonPoints = 0.0;  // comparison deadband in points

input bool   InpOneSignalPerBar = true;
input bool   InpEmitOnlyOnDirectionChange = true;
input bool   InpSendInitialSignalOnStart = true;
input bool   InpResetDirectionOnNoSignal = true;
input bool   InpInvertDirection = false;
input int    InpResendSameDirectionAfterSeconds = 0;
input int    InpRetryFailedSendEverySeconds = 2;
input bool   InpSendRegistrationOnInit = true;
input int    InpHeartbeatSeconds = 300;

input string InpApiBaseUrl = "http://127.0.0.1:8000";
input string InpApiPath = "/api/v1/mt5/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "cci_divergence";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDebugPrint = true;

int      g_pendingDir = 0;     // 1=BUY, -1=SELL, 0=none
datetime g_pendingSince = 0;
int      g_lastObservedDir = 0;
int      g_lastSentDir = 0;
datetime g_lastSentBar = 0;
datetime g_lastSentAt = 0;
int      g_lastFailedDir = 0;
datetime g_lastFailedAt = 0;
datetime g_lastHeartbeatAt = 0;

double   g_iCustomParams[];
int      g_iCustomParamCount = 0;
int      g_indicatorHandle = INVALID_HANDLE;

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string _tf_to_string(ENUM_TIMEFRAMES tf)
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
         Print("CCI Bridge invalid InpICustomParamsCsv token: ", token);
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
   Print("CCI Bridge too many iCustom params: ", c);
   return INVALID_HANDLE;
}

bool _ensure_indicator_handle()
{
   if(g_indicatorHandle != INVALID_HANDLE)
      return true;
   g_indicatorHandle = _create_indicator_handle();
   if(g_indicatorHandle == INVALID_HANDLE)
   {
      Print("CCI Bridge failed to create indicator handle: ", InpIndicatorName, " err=", GetLastError());
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

double _reference_price(int barShift)
{
   double bid = 0.0;
   double ask = 0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_BID, bid);
   SymbolInfoDouble(_Symbol, SYMBOL_ASK, ask);

   if(InpPriceSource == 0)
      return bid;
   if(InpPriceSource == 1)
      return ask;
   if(InpPriceSource == 2)
      return (bid + ask) * 0.5;
   return iClose(_Symbol, PERIOD_CURRENT, barShift);
}

bool _post_bridge_event(string eventType, string direction, double value4, double refPrice, datetime barTime)
{
   string symbol = _Symbol;
   string timeframe = _tf_to_string((ENUM_TIMEFRAMES)_Period);
   string endpointPrimary = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string endpointLocalhost = _build_endpoint("http://localhost:8000", InpApiPath);
   string endpointLoopback = _build_endpoint("http://127.0.0.1:8000", InpApiPath);

   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string msg = "";
   if(StringLen(dir) > 0)
      msg = StringFormat("%s %s %s | value4=%.6f ref=%.6f hold=%d", InpIndicatorName, symbol, dir, value4, refPrice, InpConfirmSeconds);
   else
      msg = StringFormat("CCI Bridge %s %s | %s %s", eventKind, InpIndicatorName, symbol, timeframe);

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
            Print("CCI Bridge sent ", dir, " ", symbol, " ", timeframe, " endpoint=", endpoint, " response=", resultText);
         return true;
      }
      if(InpDebugPrint)
         Print("CCI Bridge POST failed code=", httpCode, " err=", err, " endpoint=", endpoint, " response=", resultText);
   }
   return false;
}

bool _should_send(int dir, datetime barTime)
{
   datetime nowTs = TimeCurrent();
   if(dir == 0)
      return false;

   if(InpRetryFailedSendEverySeconds > 0 && g_lastFailedDir == dir && (nowTs - g_lastFailedAt) < InpRetryFailedSendEverySeconds)
      return false;

   if(InpOneSignalPerBar && g_lastSentDir == dir && g_lastSentBar == barTime)
      return false;

   if(g_lastSentAt == 0 && !InpSendInitialSignalOnStart)
   {
      g_lastSentDir = dir;
      g_lastSentBar = barTime;
      g_lastSentAt = nowTs;
      if(InpDebugPrint)
         Print("CCI Bridge initial signal suppressed on start.");
      return false;
   }

   if(InpEmitOnlyOnDirectionChange && g_lastSentDir == dir)
   {
      if(InpResendSameDirectionAfterSeconds > 0 && (nowTs - g_lastSentAt) >= InpResendSameDirectionAfterSeconds)
         return true;
      return false;
   }
   return true;
}

void _evaluate_signal()
{
   datetime nowTs = TimeCurrent();
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, InpSignalShift);
   if(barTime <= 0)
      barTime = nowTs;

   double value4 = _buffer_value(InpValueBufferIndex, InpSignalShift);
   double refPrice = _reference_price(InpSignalShift);
   if(!MathIsValidNumber(value4) || value4 == EMPTY_VALUE || !MathIsValidNumber(refPrice) || refPrice <= 0.0)
      return;

   double point = 0.0;
   SymbolInfoDouble(_Symbol, SYMBOL_POINT, point);
   if(point <= 0.0)
      point = 0.0001;
   double eps = MathMax(0.0, InpCompareEpsilonPoints) * point;

   int rawDir = 0;
   if(value4 > refPrice + eps)
      rawDir = -1; // SELL
   else if(refPrice > value4 + eps)
      rawDir = 1;  // BUY

   if(rawDir == 0)
   {
      g_pendingDir = 0;
      g_pendingSince = 0;
      if(InpResetDirectionOnNoSignal)
         g_lastObservedDir = 0;
      return;
   }

   int candidate = rawDir;
   if(InpInvertDirection)
      candidate = -candidate;

   if(candidate != g_pendingDir)
   {
      g_pendingDir = candidate;
      g_pendingSince = nowTs;
      if(InpDebugPrint)
         Print("CCI Bridge pending dir=", (candidate > 0 ? "BUY" : "SELL"), " started.");
      return;
   }

   if(g_pendingSince <= 0)
   {
      g_pendingSince = nowTs;
      return;
   }

   int confirmSec = MathMax(0, InpConfirmSeconds);
   if((nowTs - g_pendingSince) < confirmSec)
      return;

   g_lastObservedDir = candidate;
   if(!_should_send(candidate, barTime))
      return;

   string dirText = (candidate > 0 ? "BUY" : "SELL");
   bool ok = _post_bridge_event("signal", dirText, value4, refPrice, barTime);
   if(ok)
   {
      g_lastSentDir = candidate;
      g_lastSentBar = barTime;
      g_lastSentAt = nowTs;
      g_lastFailedDir = 0;
      g_lastFailedAt = 0;
   }
   else
   {
      g_lastFailedDir = candidate;
      g_lastFailedAt = nowTs;
   }
}

int OnInit()
{
   if(!_parse_iCustom_params())
      return(INIT_PARAMETERS_INCORRECT);
   if(!_ensure_indicator_handle())
      return(INIT_FAILED);

   int sec = InpPollSeconds;
   if(sec < 1)
      sec = 1;
   EventSetTimer(sec);

   if(InpDebugPrint)
   {
      Print("CCI Bridge initialized: ", InpIndicatorName, " | ", _Symbol, " ", _tf_to_string((ENUM_TIMEFRAMES)_Period));
      Print("CCI Bridge value buffer index: ", InpValueBufferIndex, " | confirm sec: ", InpConfirmSeconds);
      Print("CCI Bridge endpoint: ", _build_endpoint(InpApiBaseUrl, InpApiPath));
      Print("CCI Bridge reminder: add URL to MT5 WebRequest whitelist.");
   }

   if(InpSendRegistrationOnInit)
   {
      _post_bridge_event("register", "", 0.0, 0.0, TimeCurrent());
      g_lastHeartbeatAt = TimeCurrent();
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

void OnTick()
{
   // Timer-driven for deterministic cadence.
}

void OnTimer()
{
   _evaluate_signal();

   datetime nowTs = TimeCurrent();
   if(InpHeartbeatSeconds > 0 && (nowTs - g_lastHeartbeatAt) >= InpHeartbeatSeconds)
   {
      if(_post_bridge_event("heartbeat", "", 0.0, 0.0, nowTs))
         g_lastHeartbeatAt = nowTs;
   }
}
