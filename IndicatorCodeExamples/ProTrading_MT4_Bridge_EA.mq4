//+------------------------------------------------------------------+
//| ProTrading MT4 Bridge EA                                         |
//| Sends indicator BUY/SELL signals directly to ProTrading backend. |
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
input int    InpPollSeconds = 1;     // timer interval
input bool   InpOneSignalPerBar = true;
input bool   InpEmitOnlyOnDirectionChange = true; // true => emit only BUY<->SELL flips
input bool   InpSendInitialSignalOnStart = true;  // true => first observed direction is emitted
input bool   InpResetDirectionOnNoSignal = true;  // true => NONE resets direction state
input int    InpResendSameDirectionAfterSeconds = 0; // 0 disables periodic resend
input int    InpRetryFailedSendEverySeconds = 2; // throttle retries after failed POST
input bool   InpInvertDirection = false; // quick fix for indicators with reversed buffers
input bool   InpSendRegistrationOnInit = true;
input int    InpHeartbeatSeconds = 300; // keepalive every 5 minutes
input double InpSignalAbsMin = 0.0000001;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;

input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "intrepid";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDebugPrint = true;

datetime g_lastSentBar = 0;
int      g_lastSentDir = 0; // 1=BUY, -1=SELL
int      g_lastObservedDir = 0; // 1=BUY, -1=SELL, 0=none
datetime g_lastSentAt = 0;
datetime g_lastFailedSendAt = 0;
datetime g_lastHeartbeatAt = 0;
bool     g_observedInitialized = false;
double   g_iCustomParams[];
int      g_iCustomParamCount = 0;

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

   // Safety cap for generic adapter.
   Print("MT4Bridge too many InpICustomParamsCsv values: ", c, " (max supported: 10)");
   return EMPTY_VALUE;
}

bool _post_bridge_event(string eventType, string direction, double signalValue, datetime signalBarTime)
{
   string symbol = Symbol();
   string timeframe = _tf_to_string(Period());
   string endpointPrimary = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string endpointLocalhost = _build_endpoint("http://localhost", InpApiPath);
   string endpointLoopback = _build_endpoint("http://127.0.0.1", InpApiPath);

   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string msg = "";
   if(StringLen(dir) > 0)
      msg = StringFormat("%s %s %s buffer=%g shift=%d", InpIndicatorName, symbol, dir, signalValue, InpSignalShift);
   else
      msg = StringFormat("MT4Bridge %s %s | %s %s", eventKind, InpIndicatorName, symbol, timeframe);
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
                  " endpoint=", endpoint, " response=", resultText);
         return true;
      }

      if(InpDebugPrint)
         Print("MT4Bridge POST failed code=", httpCode, " err=", err, " endpoint=", endpoint, " response=", resultText);
   }

   return false;
}

void _check_and_send()
{
   datetime barTime = iTime(NULL, 0, InpSignalShift);
   if(barTime <= 0)
      return;

   double buyVal  = _icustom_value(InpBuyBufferIndex, InpSignalShift);
   double sellVal = _icustom_value(InpSellBufferIndex, InpSignalShift);

   bool buySignal = InpAllowBuy && _is_signal_value(buyVal);
   bool sellSignal = InpAllowSell && _is_signal_value(sellVal);

   // Ambiguous chart state: both buffers active on same bar.
   if(buySignal && sellSignal)
   {
      if(InpDebugPrint)
         Print("MT4Bridge ambiguous signal (both BUY/SELL active): ", InpIndicatorName, " ", Symbol(), " ", _tf_to_string(Period()));
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
            // Baseline current direction without emitting startup noise.
            g_lastSentDir = direction;
            g_lastSentBar = barTime;
         }
      }
      else if(direction == g_lastObservedDir)
      {
         shouldSend = false;
         if(g_lastSentDir != direction)
            shouldSend = true; // keep retrying until a change signal is delivered
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
   if(InpSendRegistrationOnInit)
   {
      datetime nowTs = TimeCurrent();
      if(nowTs <= 0)
         nowTs = TimeLocal();
      if(_post_bridge_event("register", "", 0.0, nowTs))
         g_lastHeartbeatAt = nowTs;
   }
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
