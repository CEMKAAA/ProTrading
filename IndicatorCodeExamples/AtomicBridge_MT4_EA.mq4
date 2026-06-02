//+------------------------------------------------------------------+
//| Atomic Bridge MT4 EA                                             |
//| Reads Atomic chart objects and logs latest direction/entry/SL/TPs |
//| for ProTrade integration mapping.                                |
//+------------------------------------------------------------------+
#property strict

#define ATOMIC_BRIDGE_BUILD "2026-06-02.1825-light-init-retry"

input string InpIndicatorName = "Atomic";
input int    InpPollSeconds = 1;
input bool   InpLogOnInit = true;
input bool   InpLogOnlyOnChange = true;
input bool   InpDebugObjects = false;
input bool   InpLogPostResponses = false;
input bool   InpLogNoneSignals = false;
input bool   InpLogRegimeBuffer = false;
input int    InpInitialSetupRetrySeconds = 30;
input string InpIgnoreNamePatterns = "autotrade,->";
input bool   InpEnableProTradePost = true;
input bool   InpSendInitialConfirmedOnStart = false;
input int    InpResolvedHeartbeatSeconds = 300;
input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "atomic";
input int    InpHttpTimeoutMs = 5000;
input bool   InpEnableRegimeChangePost = true;
input bool   InpSendInitialRegimeConfirmedOnStart = false;
input string InpRegimeSignalProfile = "atomic_regime";
input string InpRegimeIndicatorName = "AtomicRegime";
input int    InpRegimeAtrPeriod = 14;
input double InpRegimeAtrMultiplier = 1.5;
input double InpRegimeRR = 3.0;
input bool   InpRegimeUseTrendStopBuffers = true;
input int    InpRegimeUpTrendStopBuffer = 0;
input int    InpRegimeDnTrendStopBuffer = 1;
input bool   InpRegimeUseClosedBar = false;
input int    InpRegimeBufferLookbackBars = 200;

string   g_lastEventId = "";
datetime g_lastSignalTime = 0;
string   g_lastConfirmedEventId = "";
datetime g_lastResolvedPostTime = 0;
datetime g_initialSetupRetryUntil = 0;
string   g_lastRegimeDirection = "";
string   g_lastRegimeEventId = "";
string   g_lastRegimeConfirmedEventId = "";
datetime g_lastRegimeResolvedPostTime = 0;
int      g_lastRegimeSignalIndex = -1;
datetime g_lastRegimeSignalTime = 0;

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string _lower_copy(string s)
{
   string out = s;
   StringToLower(out);
   return out;
}

bool _contains_ci(string h, string n)
{
   StringToLower(h);
   StringToLower(n);
   return StringLen(n) > 0 && StringFind(h, n) >= 0;
}

bool _csv_name_hit(string csv, string name)
{
   string raw = _trim(csv);
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   string parts[];
   int n = StringSplit(raw, 44, parts);
   for(int i = 0; i < n; i++)
   {
      string t = _trim(parts[i]);
      if(StringLen(t) > 0 && _contains_ci(name, t))
         return true;
   }
   return false;
}

string _tf_to_string(int tf)
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
   return IntegerToString(tf);
}

string _fmt_time(datetime t)
{
   return (t > 0 ? TimeToString(t, TIME_DATE | TIME_SECONDS) : "-");
}

string _fmt_price(double p)
{
   if(!MathIsValidNumber(p) || p == EMPTY_VALUE || p == 2147483647.0 || p == 0.0)
      return "-";
   return DoubleToString(p, Digits);
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

string _event_ts_now()
{
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   return TimeToString(nowTs, TIME_DATE | TIME_SECONDS);
}

datetime _timer_now()
{
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   return nowTs;
}

bool _heartbeat_due(datetime lastPostTime)
{
   int sec = MathMax(0, InpResolvedHeartbeatSeconds);
   if(sec <= 0)
      return false;
   datetime nowTs = _timer_now();
   if(lastPostTime <= 0)
      return true;
   return (nowTs - lastPostTime) >= sec;
}

bool _parse_atomic_object_name(string name, string &direction, string &kind, int &tpIndex, int &signalIndex)
{
   direction = "";
   kind = "";
   tpIndex = -1;
   signalIndex = -1;

   string clean = _trim(name);
   int nums[];
   int count = 0;
   ArrayResize(nums, 0);

   string cur = "";
   int len = StringLen(clean);
   for(int i = 0; i < len; i++)
   {
      int ch = StringGetChar(clean, i);
      if(ch >= '0' && ch <= '9')
      {
         cur += StringSubstr(clean, i, 1);
      }
      else
      {
         if(StringLen(cur) > 0)
         {
            ArrayResize(nums, count + 1);
            nums[count++] = (int)StrToInteger(cur);
            cur = "";
         }
      }
   }
   if(StringLen(cur) > 0)
   {
      ArrayResize(nums, count + 1);
      nums[count++] = (int)StrToInteger(cur);
   }

   if(count <= 0)
      return false;

   string lc = _lower_copy(clean);

   if(StringFind(lc, "buytrend") >= 0 || StringFind(lc, "selltrend") >= 0)
   {
      direction = (StringFind(lc, "buytrend") >= 0 ? "BUY" : "SELL");
      kind = "TREND";
      signalIndex = nums[count - 1];
      return signalIndex >= 0;
   }

   if(StringFind(lc, "buytxtsloss") >= 0 || StringFind(lc, "selltxtsloss") >= 0)
   {
      direction = (StringFind(lc, "buytxtsloss") >= 0 ? "BUY" : "SELL");
      kind = "SL";
      signalIndex = nums[count - 1];
      return signalIndex >= 0;
   }

   if(StringFind(lc, "buytxttp") >= 0 || StringFind(lc, "selltxttp") >= 0)
   {
      if(count < 2)
         return false;
      direction = (StringFind(lc, "buytxttp") >= 0 ? "BUY" : "SELL");
      kind = "TP";
      tpIndex = nums[count - 2];
      signalIndex = nums[count - 1];
      return tpIndex >= 0 && signalIndex >= 0;
   }

   return false;
}

double _object_price0(string name)
{
   double p = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   if(MathIsValidNumber(p) && p != EMPTY_VALUE && p != 2147483647.0 && p != 0.0)
      return p;
   return 0.0;
}

datetime _object_time0(string name)
{
   return (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
}

bool _find_latest_atomic_signal(string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &trendName)
{
   direction = "";
   signalIndex = -1;
   signalTime = 0;
   entryPrice = 0.0;
   trendName = "";

   int total = ObjectsTotal(0, -1, -1);
   int parsed = 0;
   int trends = 0;
   int levels = 0;
   int atomicLike = 0;

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(_csv_name_hit(InpIgnoreNamePatterns, name))
         continue;

      string lname = _lower_copy(name);
      if(StringFind(lname, "buy") >= 0 || StringFind(lname, "sell") >= 0 || StringFind(lname, "atomic") >= 0 || StringFind(lname, "buffer=") >= 0)
         atomicLike++;

      string dir, kind;
      int tpIdx, sigIdx;
      if(!_parse_atomic_object_name(name, dir, kind, tpIdx, sigIdx))
         continue;
      parsed++;
      if(kind != "TREND")
      {
         levels++;
         continue;
      }
      trends++;

      datetime t = _object_time0(name);
      double p = _object_price0(name);
      if(t <= 0 || p <= 0.0)
         continue;

      if(t > signalTime)
      {
         direction = dir;
         signalIndex = sigIdx;
         signalTime = t;
         entryPrice = p;
         trendName = name;
      }
   }

   if(signalTime > 0 && signalIndex >= 0 && StringLen(direction) > 0)
      return true;

   // Fallback: some Atomic builds can omit/rename Trend objects while still drawing SL/TP labels.
   // This is less ideal for entry, but it proves object parsing and keeps diagnostics useful.
   for(int j = total - 1; j >= 0; j--)
   {
      string fallbackName = ObjectName(0, j, -1, -1);
      if(_csv_name_hit(InpIgnoreNamePatterns, fallbackName))
         continue;

      string fDir, fKind;
      int fTpIdx, fSigIdx;
      if(!_parse_atomic_object_name(fallbackName, fDir, fKind, fTpIdx, fSigIdx))
         continue;
      if(fKind != "SL" && fKind != "TP")
         continue;

      datetime ft = _object_time0(fallbackName);
      double fp = _object_price0(fallbackName);
      if(ft <= 0 || fp <= 0.0)
         continue;

      if(ft > signalTime)
      {
         direction = fDir;
         signalIndex = fSigIdx;
         signalTime = ft;
         entryPrice = fp;
         trendName = fallbackName + " [fallback-level-object]";
      }
   }

   if(InpDebugObjects || signalTime <= 0)
   {
      PrintFormat(
         "AtomicBridge scan_stats total=%d atomic_like=%d parsed=%d trends=%d levels=%d selected_time=%s selected_dir=%s selected_idx=%d",
         total, atomicLike, parsed, trends, levels, _fmt_time(signalTime), direction, signalIndex
      );
   }

   return signalTime > 0 && signalIndex >= 0 && StringLen(direction) > 0;
}

void _find_atomic_levels(string direction, int signalIndex, double &sl, double &tp1, double &tp2, double &tp3, double &tp4, double &tp5)
{
   sl = 0.0;
   tp1 = 0.0;
   tp2 = 0.0;
   tp3 = 0.0;
   tp4 = 0.0;
   tp5 = 0.0;

   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(_csv_name_hit(InpIgnoreNamePatterns, name))
         continue;

      string dir, kind;
      int tpIdx, sigIdx;
      if(!_parse_atomic_object_name(name, dir, kind, tpIdx, sigIdx))
         continue;
      if(dir != direction || sigIdx != signalIndex)
         continue;

      double p = _object_price0(name);
      if(p <= 0.0)
         continue;

      if(kind == "SL")
         sl = p;
      else if(kind == "TP")
      {
         if(tpIdx == 0) tp1 = p;
         if(tpIdx == 1) tp2 = p;
         if(tpIdx == 2) tp3 = p;
         if(tpIdx == 3) tp4 = p;
         if(tpIdx == 4) tp5 = p;
      }
   }
}

void _debug_print_atomic_objects()
{
   if(!InpDebugObjects)
      return;

   int total = ObjectsTotal(0, -1, -1);
   int printed = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      string dir, kind;
      int tpIdx, sigIdx;
      if(!_parse_atomic_object_name(name, dir, kind, tpIdx, sigIdx))
         continue;

      PrintFormat(
         "AtomicBridge object dir=%s kind=%s tp=%d idx=%d time=%s price=%s name='%s'",
         dir, kind, tpIdx, sigIdx, _fmt_time(_object_time0(name)), _fmt_price(_object_price0(name)), name
      );

      if(++printed >= 40)
         break;
   }
}

bool _post_atomic_bridge_event(
   string eventType,
   string direction,
   int signalIndex,
   datetime signalTime,
   double entryPrice,
   double sl,
   double tp1,
   double tp2,
   double tp3,
   double tp4,
   double tp5,
   string trendName,
   string reason
)
{
   if(!InpEnableProTradePost)
      return true;

   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   string eventId = StringFormat(
      "atomic|%s|%s|%s|%d|%I64d|%s",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      (long)signalTime,
      eventKind
   );
   string msg = StringFormat(
      "Atomic %s %s %s idx=%d entry=%s sl=%s tp1=%s tp2=%s tp3=%s tp4=%s tp5=%s",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      _fmt_price(entryPrice),
      _fmt_price(sl),
      _fmt_price(tp1),
      _fmt_price(tp2),
      _fmt_price(tp3),
      _fmt_price(tp4),
      _fmt_price(tp5)
   );

   string resolved = (dir == "BUY" || dir == "SELL") ? dir : "NONE";
   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpIndicatorName) + "\","
      "\"signal_hint\":\"" + _json_escape(dir) + "\","
      "\"resolved_signal\":\"" + _json_escape(resolved) + "\","
      "\"confirmed_direction\":\"" + _json_escape((eventKind == "confirmed_signal") ? dir : "") + "\","
      "\"bridge_version\":\"v2\","
      "\"symbol\":\"" + _json_escape(Symbol()) + "\","
      "\"timeframe\":\"" + _json_escape(_tf_to_string(Period())) + "\","
      "\"signal_profile\":\"" + _json_escape(InpSignalProfile) + "\","
      "\"bridge_event_type\":\"" + _json_escape(eventKind) + "\","
      "\"event_id\":\"" + _json_escape(eventId) + "\","
      "\"event_ts\":\"" + _json_escape(_event_ts_now()) + "\","
      "\"resolved_signal_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\","
      "\"resolved_signal_bar_unix\":" + IntegerToString((int)signalTime) + ","
      "\"last_signal_direction\":\"" + _json_escape(dir) + "\","
      "\"last_signal_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\","
      "\"last_signal_bar_unix\":" + IntegerToString((int)signalTime) + ","
      "\"last_signal_value\":" + DoubleToString(entryPrice, Digits) + ","
      "\"secondary_enabled\":true,"
      "\"secondary_indicator\":\"AtomicLevels\","
      "\"secondary_signal\":\"" + _json_escape(dir) + "\","
      "\"secondary_resolved_signal\":\"" + _json_escape(dir) + "\","
      "\"secondary_signal_shift\":-1,"
      "\"secondary_resolved_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\","
      "\"secondary_entry_enabled\":true,"
      "\"secondary_entry\":" + DoubleToString(entryPrice, Digits) + ","
      "\"secondary_sl_enabled\":true,"
      "\"secondary_stop_loss\":" + DoubleToString(sl, Digits) + ","
      "\"secondary_tp_enabled\":true,"
      "\"secondary_tp1\":" + DoubleToString(tp1, Digits) + ","
      "\"secondary_tp2\":" + DoubleToString(tp2, Digits) + ","
      "\"secondary_tp3\":" + DoubleToString(tp3, Digits) + ","
      "\"secondary_tp4\":" + DoubleToString(tp4, Digits) + ","
      "\"secondary_tp5\":" + DoubleToString(tp5, Digits) + ","
      "\"message\":\"" + _json_escape(msg) + "\","
      "\"atomic_signal_index\":" + IntegerToString(signalIndex) + ","
      "\"atomic_trend_object\":\"" + _json_escape(trendName) + "\","
      "\"atomic_reason\":\"" + _json_escape(reason) + "\","
      "\"bridge_token\":\"" + _json_escape(InpBridgeToken) + "\""
      "}";

   char post[];
   StringToCharArray(body, post, 0, StringLen(body));
   char result[];
   string responseHeaders = "";
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(InpBridgeToken) > 0)
      headers = headers + "X-MT4-Bridge-Token: " + InpBridgeToken + "\r\n";

   ResetLastError();
   int code = WebRequest("POST", endpoint, headers, MathMax(1000, InpHttpTimeoutMs), post, result, responseHeaders);
   string response = CharArrayToString(result, 0, -1);
   if(code >= 200 && code < 300)
   {
      if(InpLogPostResponses || eventKind == "confirmed_signal")
      {
         if(InpLogPostResponses)
            Print("AtomicBridge sent ", eventKind, " ", dir, " response=", response);
         else
            Print("AtomicBridge sent ", eventKind, " ", dir);
      }
      return true;
   }

   Print("AtomicBridge POST failed code=", code, " err=", GetLastError(), " event=", eventKind, " dir=", dir, " endpoint=", endpoint, " response=", response);
   return false;
}

double _valid_price_or_zero(double value)
{
   if(!MathIsValidNumber(value) || value == EMPTY_VALUE || value == 2147483647.0 || value <= 0.0)
      return 0.0;
   return value;
}

bool _valid_atomic_buffer_price(double value)
{
   if(_valid_price_or_zero(value) <= 0.0)
      return false;
   double bid = MarketInfo(Symbol(), MODE_BID);
   if(bid <= 0.0)
      bid = Close[0];
   if(bid <= 0.0)
      return true;
   return (value > bid * 0.20 && value < bid * 5.00);
}

double _atomic_buffer_value(int bufferIndex, int shift)
{
   return iCustom(NULL, 0, InpIndicatorName, bufferIndex, shift);
}

string _regime_buffer_state_at_shift(int shift, double &upValue, double &dnValue)
{
   upValue = _atomic_buffer_value(MathMax(0, InpRegimeUpTrendStopBuffer), shift);
   dnValue = _atomic_buffer_value(MathMax(0, InpRegimeDnTrendStopBuffer), shift);
   bool upActive = _valid_atomic_buffer_price(upValue);
   bool dnActive = _valid_atomic_buffer_price(dnValue);
   if(upActive && !dnActive)
      return "BUY";
   if(dnActive && !upActive)
      return "SELL";
   if(upActive && dnActive)
   {
      double c = Close[MathMax(0, shift)];
      if(c > 0.0)
      {
         double upDist = MathAbs(c - upValue);
         double dnDist = MathAbs(c - dnValue);
         return (upDist <= dnDist ? "BUY" : "SELL");
      }
   }
   return "";
}

bool _find_current_atomic_regime_from_buffers(string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &sourceName)
{
   direction = "";
   signalIndex = -1;
   signalTime = 0;
   entryPrice = 0.0;
   sourceName = "";

   if(!InpRegimeUseTrendStopBuffers)
      return false;

   int shift = (InpRegimeUseClosedBar ? 1 : 0);
   if(Bars <= shift)
      return false;

   double upNow, dnNow;
   string state = _regime_buffer_state_at_shift(shift, upNow, dnNow);
   if(state != "BUY" && state != "SELL")
      return false;

   int startShift = shift;
   if(state == g_lastRegimeDirection && g_lastRegimeSignalTime > 0 && g_lastRegimeSignalIndex >= 0)
   {
      signalTime = g_lastRegimeSignalTime;
      startShift = iBarShift(NULL, 0, signalTime, true);
      if(startShift < 0)
         startShift = g_lastRegimeSignalIndex;
   }
   else
   {
      int maxLookback = MathMax(shift + 1, MathMin(Bars - 1, InpRegimeBufferLookbackBars));
      for(int sh = shift + 1; sh <= maxLookback; sh++)
      {
         double upPrev, dnPrev;
         string prevState = _regime_buffer_state_at_shift(sh, upPrev, dnPrev);
         if(prevState != state)
            break;
         startShift = sh;
      }
      signalTime = Time[startShift];
   }

   signalIndex = startShift;
   double entry = 0.0;
   if(shift == 0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   if(entry <= 0.0)
      entry = Close[shift];
   if(entry <= 0.0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   entryPrice = NormalizeDouble(entry, Digits);
   direction = state;
   sourceName = StringFormat(
      "AtomicRegimeBuffer up=%d dn=%d shift=%d start_shift=%d up=%s dn=%s",
      MathMax(0, InpRegimeUpTrendStopBuffer),
      MathMax(0, InpRegimeDnTrendStopBuffer),
      shift,
      startShift,
      _fmt_price(upNow),
      _fmt_price(dnNow)
   );
   return entryPrice > 0.0 && signalTime > 0;
}

double _regime_atr_for_signal(datetime signalTime)
{
   int period = MathMax(1, InpRegimeAtrPeriod);
   int shift = iBarShift(NULL, 0, signalTime, true);
   if(shift < 0)
      shift = 0;

   double atr = iATR(NULL, 0, period, shift);
   atr = _valid_price_or_zero(atr);
   if(atr > 0.0)
      return atr;

   double fallback = MathAbs(High[shift] - Low[shift]);
   fallback = _valid_price_or_zero(fallback);
   if(fallback > 0.0)
      return fallback;

   return MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point);
}

void _compute_regime_levels(string direction, datetime signalTime, double entryPrice, double &sl, double &tp)
{
   sl = 0.0;
   tp = 0.0;
   double entry = _valid_price_or_zero(entryPrice);
   if(entry <= 0.0)
      return;

   double atr = _regime_atr_for_signal(signalTime);
   double minStop = MathMax(Point * 20.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5);
   double risk = MathMax(atr * MathMax(0.1, InpRegimeAtrMultiplier), minStop);
   double rr = MathMax(0.1, InpRegimeRR);

   if(direction == "BUY")
   {
      sl = NormalizeDouble(entry - risk, Digits);
      tp = NormalizeDouble(entry + (risk * rr), Digits);
   }
   else if(direction == "SELL")
   {
      sl = NormalizeDouble(entry + risk, Digits);
      tp = NormalizeDouble(entry - (risk * rr), Digits);
   }
}

bool _post_atomic_regime_event(
   string eventType,
   string direction,
   int signalIndex,
   datetime signalTime,
   double entryPrice,
   double sl,
   double tp,
   string trendName,
   string reason
)
{
   if(!InpEnableProTradePost || !InpEnableRegimeChangePost)
      return true;

   string eventKind = _trim(eventType);
   string dir = _trim(direction);
   string endpoint = _build_endpoint(InpApiBaseUrl, InpApiPath);
   int regimePeriod = MathMax(1, InpRegimeAtrPeriod);
   string eventId = StringFormat(
      "atomic_regime|%s|%s|%s|%d|%I64d|%s",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      (long)signalTime,
      eventKind
   );
   string msg = StringFormat(
      "AtomicRegime %s %s %s idx=%d entry=%s sl=%s tp=%s atr_period=%d atr_mult=%.2f rr=%.2f",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      _fmt_price(entryPrice),
      _fmt_price(sl),
      _fmt_price(tp),
      regimePeriod,
      MathMax(0.1, InpRegimeAtrMultiplier),
      MathMax(0.1, InpRegimeRR)
   );

   string resolved = (dir == "BUY" || dir == "SELL") ? dir : "NONE";
   string body =
      "{"
      "\"indicator\":\"" + _json_escape(InpRegimeIndicatorName) + "\"," 
      "\"signal_hint\":\"" + _json_escape(dir) + "\"," 
      "\"resolved_signal\":\"" + _json_escape(resolved) + "\"," 
      "\"confirmed_direction\":\"" + _json_escape((eventKind == "confirmed_signal") ? dir : "") + "\"," 
      "\"bridge_version\":\"v2\"," 
      "\"symbol\":\"" + _json_escape(Symbol()) + "\"," 
      "\"timeframe\":\"" + _json_escape(_tf_to_string(Period())) + "\"," 
      "\"signal_profile\":\"" + _json_escape(InpRegimeSignalProfile) + "\"," 
      "\"bridge_event_type\":\"" + _json_escape(eventKind) + "\"," 
      "\"event_id\":\"" + _json_escape(eventId) + "\"," 
      "\"event_ts\":\"" + _json_escape(_event_ts_now()) + "\"," 
      "\"resolved_signal_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\"," 
      "\"resolved_signal_bar_unix\":" + IntegerToString((int)signalTime) + "," 
      "\"last_signal_direction\":\"" + _json_escape(dir) + "\"," 
      "\"last_signal_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\"," 
      "\"last_signal_bar_unix\":" + IntegerToString((int)signalTime) + "," 
      "\"last_signal_value\":" + DoubleToString(entryPrice, Digits) + "," 
      "\"secondary_enabled\":true," 
      "\"secondary_indicator\":\"AtomicRegimeAtr3R\"," 
      "\"secondary_signal\":\"" + _json_escape(dir) + "\"," 
      "\"secondary_resolved_signal\":\"" + _json_escape(dir) + "\"," 
      "\"secondary_signal_shift\":-1," 
      "\"secondary_resolved_bar_time\":\"" + _json_escape(_fmt_time(signalTime)) + "\"," 
      "\"secondary_entry_enabled\":true," 
      "\"secondary_entry\":" + DoubleToString(entryPrice, Digits) + "," 
      "\"secondary_sl_enabled\":true," 
      "\"secondary_stop_loss\":" + DoubleToString(sl, Digits) + "," 
      "\"secondary_tp_enabled\":true," 
      "\"secondary_tp1\":" + DoubleToString(tp, Digits) + "," 
      "\"message\":\"" + _json_escape(msg) + "\"," 
      "\"atomic_signal_index\":" + IntegerToString(signalIndex) + "," 
      "\"atomic_trend_object\":\"" + _json_escape(trendName) + "\"," 
      "\"atomic_regime_reason\":\"" + _json_escape(reason) + "\"," 
      "\"bridge_token\":\"" + _json_escape(InpBridgeToken) + "\"" 
      "}";

   char post[];
   StringToCharArray(body, post, 0, StringLen(body));
   char result[];
   string responseHeaders = "";
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(InpBridgeToken) > 0)
      headers = headers + "X-MT4-Bridge-Token: " + InpBridgeToken + "\r\n";

   ResetLastError();
   int code = WebRequest("POST", endpoint, headers, MathMax(1000, InpHttpTimeoutMs), post, result, responseHeaders);
   string response = CharArrayToString(result, 0, -1);
   if(code >= 200 && code < 300)
   {
      if(InpLogPostResponses || eventKind == "confirmed_signal")
      {
         if(InpLogPostResponses)
            Print("AtomicBridge regime sent ", eventKind, " ", dir, " response=", response);
         else
            Print("AtomicBridge regime sent ", eventKind, " ", dir);
      }
      return true;
   }

   Print("AtomicBridge regime POST failed code=", code, " err=", GetLastError(), " event=", eventKind, " dir=", dir, " endpoint=", endpoint, " response=", response);
   return false;
}

void _handle_regime_event(string reason, string direction, int signalIndex, datetime signalTime, double entryPrice, string trendName)
{
   if(!InpEnableRegimeChangePost || StringLen(direction) <= 0)
      return;

   double regimeSl, regimeTp;
   _compute_regime_levels(direction, signalTime, entryPrice, regimeSl, regimeTp);
   if(regimeSl <= 0.0 || regimeTp <= 0.0)
   {
      Print("AtomicBridge regime warning: invalid ATR SL/TP for dir=", direction, " entry=", _fmt_price(entryPrice));
      return;
   }

   string regimeEventId = StringFormat("%s|%s|%d|%I64d", Symbol(), direction, signalIndex, (long)signalTime);
   bool directionChanged = (StringLen(g_lastRegimeDirection) > 0 && direction != g_lastRegimeDirection);

   if(reason == "init" || StringLen(g_lastRegimeDirection) <= 0)
   {
      g_lastRegimeDirection = direction;
      g_lastRegimeEventId = regimeEventId;
      g_lastRegimeSignalIndex = signalIndex;
      g_lastRegimeSignalTime = signalTime;
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
         g_lastRegimeResolvedPostTime = _timer_now();
      if(reason == "init" && InpSendInitialRegimeConfirmedOnStart)
      {
         _post_atomic_regime_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason);
         g_lastRegimeConfirmedEventId = regimeEventId;
      }
      return;
   }

   g_lastRegimeEventId = regimeEventId;
   if(directionChanged && regimeEventId != g_lastRegimeConfirmedEventId)
   {
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
         g_lastRegimeResolvedPostTime = _timer_now();
      _post_atomic_regime_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason);
      g_lastRegimeDirection = direction;
      g_lastRegimeConfirmedEventId = regimeEventId;
      g_lastRegimeSignalIndex = signalIndex;
      g_lastRegimeSignalTime = signalTime;
   }
   else if(_heartbeat_due(g_lastRegimeResolvedPostTime))
   {
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, "heartbeat"))
         g_lastRegimeResolvedPostTime = _timer_now();
   }
}

void ScanAndLogLatest(string reason)
{
   string direction, trendName;
   int signalIndex;
   datetime signalTime;
   double entryPrice;
   string regimeDirection = "";
   string regimeSourceName = "";
   int regimeSignalIndex = -1;
   datetime regimeSignalTime = 0;
   double regimeEntryPrice = 0.0;
   bool hasBufferRegime = _find_current_atomic_regime_from_buffers(
      regimeDirection,
      regimeSignalIndex,
      regimeSignalTime,
      regimeEntryPrice,
      regimeSourceName
   );

   if(!_find_latest_atomic_signal(direction, signalIndex, signalTime, entryPrice, trendName))
   {
      if(InpLogNoneSignals)
         Print("AtomicBridge latest_signal NONE reason=", reason, " symbol=", Symbol(), " tf=", _tf_to_string(Period()));
      _debug_print_atomic_objects();
      if(hasBufferRegime)
      {
         if(InpLogRegimeBuffer)
         {
            PrintFormat(
               "AtomicBridge regime_buffer reason=%s symbol=%s tf=%s dir=%s start_bar=%s entry=%s source='%s'",
               reason,
               Symbol(),
               _tf_to_string(Period()),
               regimeDirection,
               _fmt_time(regimeSignalTime),
               _fmt_price(regimeEntryPrice),
               regimeSourceName
            );
         }
         _handle_regime_event(reason, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
      }
      return;
   }

   double sl, tp1, tp2, tp3, tp4, tp5;
   _find_atomic_levels(direction, signalIndex, sl, tp1, tp2, tp3, tp4, tp5);

   string eventId = StringFormat("%s|%s|%d|%I64d", Symbol(), direction, signalIndex, (long)signalTime);
   if(InpLogOnlyOnChange && eventId == g_lastEventId)
   {
      if(StringLen(direction) > 0 && sl > 0.0 && tp1 > 0.0 && _heartbeat_due(g_lastResolvedPostTime))
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, "heartbeat"))
            g_lastResolvedPostTime = _timer_now();
      }
      if(hasBufferRegime)
         _handle_regime_event("heartbeat", regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
      else
         _handle_regime_event("heartbeat", direction, signalIndex, signalTime, entryPrice, trendName);
      return;
   }

   g_lastEventId = eventId;
   g_lastSignalTime = signalTime;

   PrintFormat(
      "AtomicBridge latest_signal reason=%s symbol=%s tf=%s dir=%s idx=%d bar=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s tp4=%s tp5=%s trend='%s'",
      reason,
      Symbol(),
      _tf_to_string(Period()),
      direction,
      signalIndex,
      _fmt_time(signalTime),
      _fmt_price(entryPrice),
      _fmt_price(sl),
      _fmt_price(tp1),
      _fmt_price(tp2),
      _fmt_price(tp3),
      _fmt_price(tp4),
      _fmt_price(tp5),
      trendName
   );

   if(sl <= 0.0 || tp1 <= 0.0)
      Print("AtomicBridge warning: missing SL/TP data for latest signal. Check object naming/scan timing.");

   if(StringLen(direction) > 0 && sl > 0.0 && tp1 > 0.0)
   {
      if(reason == "init" || reason == "init_retry")
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason))
            g_lastResolvedPostTime = _timer_now();
         if(InpSendInitialConfirmedOnStart)
         {
            _post_atomic_bridge_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason);
            g_lastConfirmedEventId = eventId;
         }
      }
      else if(eventId != g_lastConfirmedEventId)
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason))
            g_lastResolvedPostTime = _timer_now();
         _post_atomic_bridge_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason);
         g_lastConfirmedEventId = eventId;
      }
   }

   if(hasBufferRegime)
   {
      if(InpLogRegimeBuffer)
      {
         PrintFormat(
            "AtomicBridge regime_buffer reason=%s symbol=%s tf=%s dir=%s start_bar=%s entry=%s source='%s'",
            reason,
            Symbol(),
            _tf_to_string(Period()),
            regimeDirection,
            _fmt_time(regimeSignalTime),
            _fmt_price(regimeEntryPrice),
            regimeSourceName
         );
      }
      _handle_regime_event(reason, regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
   }
   else
   {
      _handle_regime_event(reason, direction, signalIndex, signalTime, entryPrice, trendName);
   }
}

int OnInit()
{
   int poll = MathMax(1, InpPollSeconds);
   EventSetTimer(poll);
   Print("AtomicBridge BUILD=", ATOMIC_BRIDGE_BUILD, " indicator=", InpIndicatorName, " symbol=", Symbol(), " tf=", _tf_to_string(Period()), " poll=", poll, " logPost=", InpLogPostResponses);
   if(InpEnableProTradePost)
      _post_atomic_bridge_event("register", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", "init");
   g_initialSetupRetryUntil = _timer_now() + MathMax(0, InpInitialSetupRetrySeconds);
   if(InpLogOnInit)
      ScanAndLogLatest("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpLogPostResponses || InpLogNoneSignals || InpLogRegimeBuffer)
      Print("AtomicBridge uninit reason=", reason);
}

void OnTimer()
{
   if(InpLogOnInit && StringLen(g_lastEventId) <= 0 && _timer_now() <= g_initialSetupRetryUntil)
   {
      ScanAndLogLatest("init_retry");
      return;
   }
   ScanAndLogLatest("timer");
}

void OnTick()
{
}
