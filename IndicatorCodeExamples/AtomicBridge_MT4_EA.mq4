//+------------------------------------------------------------------+
//| Atomic Bridge MT4 EA                                             |
//| Reads Atomic chart objects and logs latest direction/entry/SL/TPs |
//| for ProTrade integration mapping.                                |
//+------------------------------------------------------------------+
#property strict

#define ATOMIC_BRIDGE_BUILD "2026-06-05.0100-direct-defaults"

input string InpIndicatorName = "Atomic";
input int    InpPollSeconds = 1;
input bool   InpLogOnInit = true;
input bool   InpLogOnlyOnChange = true;
input bool   InpDebugObjects = false;
input bool   InpLogPostResponses = false;
input bool   InpLogHandshakeResponses = true;
input bool   InpLogNoneSignals = false;
input bool   InpLogRegimeBuffer = false;
input bool   InpShowDashboard = true;
input int    InpInitialSetupRetrySeconds = 30;
input string InpIgnoreNamePatterns = "autotrade,->";
input bool   InpEnableProTradePost = true;
input bool   InpSendUnregisterOnDeinit = true;
input bool   InpSendInitialConfirmedOnStart = false;
input int    InpResolvedHeartbeatSeconds = 300;
input int    InpRegisterHeartbeatSeconds = 120;
input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "atomic";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDirectMt4ExecutionEnabled = true;
input string InpDirectMt4Priority = "post_first"; // direct_first | post_first
input double InpDirectMt4Lot = 1.00;
input int    InpDirectMt4Magic = 970101;
input int    InpDirectMt4Slippage = 30;
input int    InpDirectMt4MaxSpreadPoints = 0;
input string InpDirectMt4NoTradeWindowsGmt = "19:30-20:30";
input bool   InpDirectMt4CloseReverse = false;
input int    InpDirectMt4TpIndex = 5;
input double InpDirectMt4HalfBeR = 2.0;
input bool   InpEnableRegimeChangePost = true;
input bool   InpSendInitialRegimeConfirmedOnStart = false;
input string InpRegimeSignalProfile = "atomic_regime";
input string InpRegimeIndicatorName = "AtomicRegime";
input int    InpRegimeAtrPeriod = 14;
input double InpRegimeAtrMultiplier = 3.0;
input double InpRegimeRR = 3.0;
input double InpRegimeMinRiskPricePct = 0.00075;
input double InpRegimeMaxRiskPricePct = 0.00150;
input double InpRegimeMaxRiskMoneyPerLot = 0.0;
input double InpRegimeMinRiskPoints = 0.0;
input bool   InpRegimeUseTrendSignalBuffers = true;
input int    InpRegimeUpTrendSignalBuffer = 2;
input int    InpRegimeDnTrendSignalBuffer = 3;
input bool   InpRegimeUseTrendStopBuffers = false;
input int    InpRegimeUpTrendStopBuffer = 0;
input int    InpRegimeDnTrendStopBuffer = 1;
input bool   InpRegimeUseAtomicSignalAsTieBreak = true;
input bool   InpRegimeUseClosedBar = true;
input int    InpRegimeBufferLookbackBars = 200;
input int    InpRegimeConfirmStableSeconds = 5;
input int    InpRegimeMaxConfirmShift = 1;

string   g_lastEventId = "";
datetime g_lastSignalTime = 0;
string   g_lastConfirmedEventId = "";
datetime g_lastResolvedPostTime = 0;
datetime g_lastRegisterPostTime = 0;
datetime g_initialSetupRetryUntil = 0;
string   g_lastRegimeDirection = "";
string   g_lastRegimeEventId = "";
string   g_lastRegimeConfirmedEventId = "";
datetime g_lastRegimeResolvedPostTime = 0;
int      g_lastRegimeSignalIndex = -1;
datetime g_lastRegimeSignalTime = 0;
string   g_lastRegimeConfirmedDirection = "";
datetime g_lastRegimeConfirmedSignalTime = 0;
string   g_pendingRegimeEventId = "";
string   g_pendingRegimeDirection = "";
datetime g_pendingRegimeFirstSeen = 0;
string   g_lastDirectMt4EventId = "";
bool     g_directMt4EnabledRuntime = false;
bool     g_directMt4PriorityDirectFirst = true;
double   g_directMt4LotRuntime = 0.0;
int      g_directMt4MaxSpreadRuntime = 0;
double   g_directMt4HalfBeRRuntime = 0.0;
double   g_regimeRRRuntime = 0.0;
bool     g_regimeUseClosedBarRuntime = true;
string   DASH_PREFIX = "ATOMIC_BRIDGE_DASH_";

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string _compact_bridge_response(string response)
{
   string out = _trim(response);
   StringReplace(out, "\r", " ");
   StringReplace(out, "\n", " ");
   if(StringLen(out) > 500)
      out = StringSubstr(out, 0, 500) + "...";
   return out;
}

bool _should_log_handshake_response(string eventKind, string reason)
{
   if(!InpLogHandshakeResponses)
      return false;
   string evt = _trim(eventKind);
   string why = _trim(reason);
   if(evt == "unregister")
      return true;
   if(evt == "register")
      return (why == "init" || why == "init_retry");
   return (why == "init" || why == "init_retry");
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

int _direct_minutes_from_hhmm(string value)
{
   string s = _trim(value);
   int pos = StringFind(s, ":");
   if(pos <= 0)
      return -1;
   int hh = StrToInteger(StringSubstr(s, 0, pos));
   int mm = StrToInteger(StringSubstr(s, pos + 1));
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return -1;
   return hh * 60 + mm;
}

bool _direct_minute_in_range(int minuteOfDay, string rangeText)
{
   string s = _trim(rangeText);
   int sep = StringFind(s, "-");
   if(sep <= 0)
      return false;
   int start = _direct_minutes_from_hhmm(StringSubstr(s, 0, sep));
   int stop = _direct_minutes_from_hhmm(StringSubstr(s, sep + 1));
   if(start < 0 || stop < 0)
      return false;
   int cur = MathMax(0, MathMin(1439, minuteOfDay));
   if(start == stop)
      return true;
   if(start < stop)
      return (cur >= start && cur < stop);
   return (cur >= start || cur < stop);
}

bool _direct_in_no_trade_window_gmt()
{
   string raw = _trim(InpDirectMt4NoTradeWindowsGmt);
   if(StringLen(raw) <= 0)
      return false;
   datetime nowGmt = TimeGMT();
   int minute = TimeHour(nowGmt) * 60 + TimeMinute(nowGmt);
   StringReplace(raw, ";", ",");
   StringReplace(raw, "|", ",");
   string parts[];
   int n = StringSplit(raw, 44, parts);
   for(int i = 0; i < n; i++)
   {
      if(_direct_minute_in_range(minute, parts[i]))
         return true;
   }
   return false;
}

bool _direct_priority_direct_first()
{
   return g_directMt4PriorityDirectFirst;
}

bool _direct_close_reverse_positions(string direction)
{
   if(!InpDirectMt4CloseReverse)
      return true;
   int targetType = (direction == "BUY") ? OP_SELL : OP_BUY;
   bool ok = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpDirectMt4Magic || OrderType() != targetType)
         continue;
      RefreshRates();
      double closePx = (targetType == OP_BUY) ? Bid : Ask;
      if(!OrderClose(OrderTicket(), OrderLots(), closePx, InpDirectMt4Slippage, clrSilver))
      {
         Print("AtomicBridge direct_mt4 reverse close failed ticket=", OrderTicket(), " err=", GetLastError());
         ok = false;
      }
   }
   return ok;
}

double _select_direct_tp(double tp1, double tp2, double tp3, double tp4, double tp5)
{
   int idx = MathMax(1, MathMin(5, InpDirectMt4TpIndex));
   if(idx == 1 && tp1 > 0.0) return tp1;
   if(idx == 2 && tp2 > 0.0) return tp2;
   if(idx == 3 && tp3 > 0.0) return tp3;
   if(idx == 4 && tp4 > 0.0) return tp4;
   if(idx == 5 && tp5 > 0.0) return tp5;
   if(tp5 > 0.0) return tp5;
   if(tp4 > 0.0) return tp4;
   if(tp3 > 0.0) return tp3;
   if(tp2 > 0.0) return tp2;
   return tp1;
}

bool _direct_mt4_execute(string eventId, string direction, double sl, double tp, string source)
{
   if(!g_directMt4EnabledRuntime)
      return true;
   string dir = _trim(direction);
   if(dir != "BUY" && dir != "SELL")
      return false;
   if(eventId == g_lastDirectMt4EventId)
      return true;
   if(_direct_in_no_trade_window_gmt())
   {
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 skipped reason=no_trade_window_gmt event=", eventId, " dir=", dir);
      return false;
   }
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   if(g_directMt4MaxSpreadRuntime > 0 && spread > g_directMt4MaxSpreadRuntime)
   {
      g_lastDirectMt4EventId = eventId;
      Print("AtomicBridge direct_mt4 skipped reason=spread_too_wide spread=", spread, " max=", g_directMt4MaxSpreadRuntime, " event=", eventId);
      return false;
   }
   _direct_close_reverse_positions(dir);
   RefreshRates();
   int type = (dir == "BUY") ? OP_BUY : OP_SELL;
   double price = (type == OP_BUY) ? Ask : Bid;
   double stopLoss = (sl > 0.0 ? NormalizeDouble(sl, Digits) : 0.0);
   double takeProfit = (tp > 0.0 ? NormalizeDouble(tp, Digits) : 0.0);
   double lot = MathMax(0.01, g_directMt4LotRuntime);
   string comment = "AtomicBridgeMT4|" + source;
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lot, NormalizeDouble(price, Digits), InpDirectMt4Slippage, stopLoss, takeProfit, comment, InpDirectMt4Magic, 0, (type == OP_BUY ? clrLime : clrTomato));
   g_lastDirectMt4EventId = eventId;
   if(ticket > 0)
   {
      Print("AtomicBridge direct_mt4 order_sent ticket=", ticket, " dir=", dir, " lot=", DoubleToString(lot, 2), " price=", _fmt_price(price), " sl=", _fmt_price(stopLoss), " tp=", _fmt_price(takeProfit), " event=", eventId);
      return true;
   }
   Print("AtomicBridge direct_mt4 order_failed err=", GetLastError(), " dir=", dir, " lot=", DoubleToString(lot, 2), " price=", _fmt_price(price), " sl=", _fmt_price(stopLoss), " tp=", _fmt_price(takeProfit), " event=", eventId);
   return false;
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

string _bridge_runtime_telemetry_json()
{
   RefreshRates();
   datetime serverTs = _timer_now();
   datetime gmtTs = TimeGMT();
   datetime localTs = TimeLocal();
   double bid = MarketInfo(Symbol(), MODE_BID);
   double ask = MarketInfo(Symbol(), MODE_ASK);
   double point = MarketInfo(Symbol(), MODE_POINT);
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   return
      "\"mt4_server_time\":\"" + _json_escape(TimeToString(serverTs, TIME_DATE | TIME_SECONDS)) + "\","
      "\"mt4_server_unix\":" + IntegerToString((int)serverTs) + ","
      "\"mt4_gmt_time\":\"" + _json_escape(TimeToString(gmtTs, TIME_DATE | TIME_SECONDS)) + "\","
      "\"mt4_gmt_unix\":" + IntegerToString((int)gmtTs) + ","
      "\"mt4_local_time\":\"" + _json_escape(TimeToString(localTs, TIME_DATE | TIME_SECONDS)) + "\","
      "\"mt4_local_unix\":" + IntegerToString((int)localTs) + ","
      "\"mt4_bid\":" + DoubleToString(bid, Digits) + ","
      "\"mt4_ask\":" + DoubleToString(ask, Digits) + ","
      "\"mt4_point\":" + DoubleToString(point, Digits + 2) + ","
      "\"mt4_spread_points\":" + IntegerToString(spread) + ",";
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

bool _register_heartbeat_due()
{
   int sec = MathMax(0, InpRegisterHeartbeatSeconds);
   if(sec <= 0)
      return false;
   datetime nowTs = _timer_now();
   if(g_lastRegisterPostTime <= 0)
      return true;
   return (nowTs - g_lastRegisterPostTime) >= sec;
}

void MaybePostRegisterHeartbeat(string reason)
{
   if(!InpEnableProTradePost || !_register_heartbeat_due())
      return;
   _post_atomic_bridge_event("register", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", reason);
   g_lastRegisterPostTime = _timer_now();
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

bool _find_latest_atomic_signal(string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &trendName, bool logOnNone = true)
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

   if(InpDebugObjects || (logOnNone && signalTime <= 0))
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

double _atomic_final_tp(double tp1, double tp2, double tp3, double tp4, double tp5)
{
   if(tp5 > 0.0) return tp5;
   if(tp4 > 0.0) return tp4;
   if(tp3 > 0.0) return tp3;
   if(tp2 > 0.0) return tp2;
   if(tp1 > 0.0) return tp1;
   return 0.0;
}

bool _atomic_signal_geometry_valid(
   string direction,
   double signalEntry,
   double sl,
   double tp1,
   double tp2,
   double tp3,
   double tp4,
   double tp5,
   string &reason
)
{
   reason = "";
   string dir = _trim(direction);
   double finalTp = _atomic_final_tp(tp1, tp2, tp3, tp4, tp5);
   double point = MarketInfo(Symbol(), MODE_POINT);
   if(point <= 0.0)
      point = Point;
   double minGap = MathMax(point * 2.0, MarketInfo(Symbol(), MODE_STOPLEVEL) * point);
   double livePx = 0.0;

   if(dir == "BUY")
      livePx = MarketInfo(Symbol(), MODE_ASK);
   else if(dir == "SELL")
      livePx = MarketInfo(Symbol(), MODE_BID);
   else
   {
      reason = "invalid_direction";
      return false;
   }

   if(signalEntry <= 0.0 || sl <= 0.0 || finalTp <= 0.0)
   {
      reason = "missing_entry_sl_tp";
      return false;
   }

   if(dir == "BUY")
   {
      if(sl >= signalEntry - minGap)
      {
         reason = "buy_sl_not_below_signal_entry";
         return false;
      }
      if(finalTp <= signalEntry + minGap)
      {
         reason = "buy_tp_not_above_signal_entry";
         return false;
      }
      if(livePx > 0.0 && finalTp <= livePx + minGap)
      {
         reason = "buy_tp_already_passed_live_price";
         return false;
      }
   }
   else
   {
      if(sl <= signalEntry + minGap)
      {
         reason = "sell_sl_not_above_signal_entry";
         return false;
      }
      if(finalTp >= signalEntry - minGap)
      {
         reason = "sell_tp_not_below_signal_entry";
         return false;
      }
      if(livePx > 0.0 && finalTp >= livePx - minGap)
      {
         reason = "sell_tp_already_passed_live_price";
         return false;
      }
   }

   return true;
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
   bool directFirst = (eventKind == "confirmed_signal" && _direct_priority_direct_first());
   if(directFirst)
      _direct_mt4_execute(eventId, dir, sl, _select_direct_tp(tp1, tp2, tp3, tp4, tp5), InpIndicatorName);
   if(!InpEnableProTradePost)
   {
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, sl, _select_direct_tp(tp1, tp2, tp3, tp4, tp5), InpIndicatorName);
      return true;
   }
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
      "\"event_ts\":\"" + _json_escape(_event_ts_now()) + "\"," +
      _bridge_runtime_telemetry_json() +
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
      if(InpLogPostResponses || _should_log_handshake_response(eventKind, reason))
      {
         Print("AtomicBridge handshake sent ", eventKind, " ", dir, " reason=", reason, " response=", _compact_bridge_response(response));
      }
      else if(eventKind == "confirmed_signal")
      {
         Print("AtomicBridge sent ", eventKind, " ", dir);
      }
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, sl, _select_direct_tp(tp1, tp2, tp3, tp4, tp5), InpIndicatorName);
      return true;
   }

   Print("AtomicBridge POST failed code=", code, " err=", GetLastError(), " event=", eventKind, " dir=", dir, " endpoint=", endpoint, " response=", response);
   if(eventKind == "confirmed_signal" && !directFirst)
      _direct_mt4_execute(eventId, dir, sl, _select_direct_tp(tp1, tp2, tp3, tp4, tp5), InpIndicatorName);
   return false;
}

double _valid_price_or_zero(double value)
{
   if(!MathIsValidNumber(value) || value == EMPTY_VALUE || value == 2147483647.0 || value <= 0.0)
      return 0.0;
   return value;
}

double _clamp_double(double value, double lo, double hi)
{
   return MathMax(lo, MathMin(hi, value));
}

void _dash_rect(string name, int x, int y, int w, int h, color bg, color border)
{
   string obj = DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, border);
}

void _dash_label(string name, int x, int y, string text, color clr, int size = 8)
{
   string obj = DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void _dash_button(string name, int x, int y, int w, int h, string text, color bg)
{
   string obj = DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
}

void _dash_edit(string name, int x, int y, int w, int h, string text)
{
   string obj = DASH_PREFIX + name;
   bool created = false;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
      created = true;
   }
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   if(created)
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'35,43,58');
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C'90,178,255');
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
}

void _dash_progress(string name, int x, int y, int w, int h, double pct, string text, color fill)
{
   pct = _clamp_double(pct, 0.0, 100.0);
   _dash_rect(name + "_BG", x, y, w, h, C'35,43,58', C'134,158,182');
   _dash_rect(name + "_FILL", x, y, (int)MathRound(w * pct / 100.0), h, fill, fill);
   _dash_label(name + "_TXT", x + 8, y + 4, text, clrWhite, 8);
}

void _delete_dash()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, -1, -1);
      if(StringFind(obj, DASH_PREFIX) == 0)
         ObjectDelete(0, obj);
   }
}

bool _direct_open_progress(double &pct, string &label, color &fill)
{
   pct = 0.0;
   label = "DIRECT MT4 POSITION: none";
   fill = C'88,96,112';
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpDirectMt4Magic)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      double entry = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      int dir = OrderType() == OP_BUY ? 1 : -1;
      RefreshRates();
      double px = dir > 0 ? Bid : Ask;
      if(sl <= 0.0 || tp <= 0.0 || MathAbs(tp - sl) <= 0.0)
         continue;
      if(dir > 0)
         pct = ((px - sl) / (tp - sl)) * 100.0;
      else
         pct = ((sl - px) / (sl - tp)) * 100.0;
      pct = _clamp_double(pct, 0.0, 100.0);
      fill = dir > 0 ? C'31,141,255' : C'221,55,78';
      label = StringFormat("%s ticket=%d Px=%s SL=%s TP=%s %.0f%%",
                           (dir > 0 ? "BUY" : "SELL"),
                           OrderTicket(),
                           _fmt_price(px),
                           _fmt_price(sl),
                           _fmt_price(tp),
                           pct);
      return true;
   }
   return false;
}

void _manage_direct_mt4_positions()
{
   double halfR = g_directMt4HalfBeRRuntime;
   if(halfR <= 0.0)
      return;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpDirectMt4Magic)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      double entry = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      if(sl <= 0.0 || tp <= 0.0)
         continue;
      int dir = OrderType() == OP_BUY ? 1 : -1;
      double risk = MathAbs(entry - sl);
      if(risk <= Point)
         continue;
      RefreshRates();
      double px = dir > 0 ? Bid : Ask;
      bool reached = (dir > 0) ? (px >= entry + risk * halfR) : (px <= entry - risk * halfR);
      bool alreadyBe = (dir > 0) ? (sl >= entry - Point) : (sl <= entry + Point);
      if(!reached || alreadyBe)
         continue;
      if(OrderModify(OrderTicket(), entry, NormalizeDouble(entry, Digits), tp, 0, clrDodgerBlue))
         Print("AtomicBridge direct_mt4 half_be moved ticket=", OrderTicket(), " halfR=", DoubleToString(halfR, 1));
      else
         Print("AtomicBridge direct_mt4 half_be failed ticket=", OrderTicket(), " err=", GetLastError());
   }
}

void _draw_dashboard()
{
   if(!InpShowDashboard)
      return;
   _dash_rect("BG", 10, 20, 760, 210, C'24,30,42', C'134,158,182');
   _dash_rect("CORE", 18, 28, 744, 194, C'35,43,58', C'90,178,255');
   _dash_label("TITLE", 28, 34, "ATOMIC BRIDGE DIRECT COCKPIT", C'216,222,230', 10);
   _dash_label("SUB", 330, 36, Symbol() + " " + _tf_to_string(Period()) + " | " + ATOMIC_BRIDGE_BUILD, C'90,178,255', 8);
   _dash_button("BTN_DIRECT", 28, 62, 120, 24, g_directMt4EnabledRuntime ? "DIRECT ON" : "DIRECT OFF", g_directMt4EnabledRuntime ? C'32,150,96' : C'178,37,57');
   _dash_button("BTN_PRIORITY", 156, 62, 135, 24, g_directMt4PriorityDirectFirst ? "DIRECT FIRST" : "POST FIRST", C'38,101,176');
   _dash_button("BTN_HALFBE", 300, 62, 110, 24, "HALFBE " + DoubleToString(g_directMt4HalfBeRRuntime, 1) + "R", C'34,136,160');
   _dash_button("BTN_REGIME_SHIFT", 418, 62, 118, 24, g_regimeUseClosedBarRuntime ? "REGIME SH1" : "REGIME SH0", g_regimeUseClosedBarRuntime ? C'34,136,160' : C'178,37,57');
   _dash_button("BTN_APPLY", 544, 62, 90, 24, "APPLY", C'38,101,176');
   _dash_label("L_LOT", 28, 100, "Lot", C'184,196,210', 8);
   _dash_edit("EDIT_LOT", 70, 96, 70, 22, DoubleToString(g_directMt4LotRuntime, 2));
   _dash_label("L_SPREAD", 156, 100, "Max spread pts", C'184,196,210', 8);
   _dash_edit("EDIT_SPREAD", 260, 96, 70, 22, IntegerToString(g_directMt4MaxSpreadRuntime));
   _dash_label("L_RR", 348, 100, "Regime TP R", C'184,196,210', 8);
   _dash_edit("EDIT_RR", 438, 96, 54, 22, DoubleToString(g_regimeRRRuntime, 1));
   _dash_label("L_HB", 510, 100, "BE at R", C'184,196,210', 8);
   _dash_edit("EDIT_HALFBE", 570, 96, 54, 22, DoubleToString(g_directMt4HalfBeRRuntime, 1));
   int spread = (int)MarketInfo(Symbol(), MODE_SPREAD);
   RefreshRates();
   _dash_label("STATE", 28, 132, StringFormat("Bid %s Ask %s Spread %d | Regime closed-bar shift=%s",
              _fmt_price(Bid), _fmt_price(Ask), spread, (g_regimeUseClosedBarRuntime ? "1" : "0")), clrWhite, 8);
   double pct; string label; color fill;
   if(_direct_open_progress(pct, label, fill))
      _dash_progress("TRADE", 28, 158, 700, 24, pct, label, fill);
   else
      _dash_progress("TRADE", 28, 158, 700, 24, 0.0, "DIRECT MT4 POSITION: none | dashboard does not mutate signal math", C'88,96,112');
}

void _apply_dashboard()
{
   string obj;
   obj = DASH_PREFIX + "EDIT_LOT";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4LotRuntime = MathMax(0.01, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_SPREAD";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4MaxSpreadRuntime = MathMax(0, StrToInteger(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_RR";
   if(ObjectFind(0, obj) >= 0)
      g_regimeRRRuntime = MathMax(0.1, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   obj = DASH_PREFIX + "EDIT_HALFBE";
   if(ObjectFind(0, obj) >= 0)
      g_directMt4HalfBeRRuntime = MathMax(0.0, StrToDouble(ObjectGetString(0, obj, OBJPROP_TEXT)));
   Print("AtomicBridge dashboard applied direct=", (g_directMt4EnabledRuntime ? "true" : "false"),
         " priority=", (g_directMt4PriorityDirectFirst ? "direct_first" : "post_first"),
         " lot=", DoubleToString(g_directMt4LotRuntime, 2),
         " max_spread=", g_directMt4MaxSpreadRuntime,
         " regime_rr=", DoubleToString(g_regimeRRRuntime, 2),
         " halfbe_r=", DoubleToString(g_directMt4HalfBeRRuntime, 2),
         " regime_closed_bar=", (g_regimeUseClosedBarRuntime ? "true" : "false"));
   _draw_dashboard();
   ChartRedraw(0);
}

double _value_per_price_unit_per_lot()
{
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickSize <= 0.0)
      tickSize = Point;
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   return tickValue / tickSize;
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

double _regime_buffer_value(int bufferIndex, int shift)
{
   // AtomicRegime is a logical strategy label. The regime signal buffers are
   // exposed by the Atomic indicator itself; there is no AtomicRegime.ex4.
   return _atomic_buffer_value(bufferIndex, shift);
}

string _regime_buffer_state_at_shift(int shift, double &upValue, double &dnValue)
{
   upValue = _regime_buffer_value(MathMax(0, InpRegimeUpTrendStopBuffer), shift);
   dnValue = _regime_buffer_value(MathMax(0, InpRegimeDnTrendStopBuffer), shift);
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

bool _find_latest_regime_signal_buffer(
   int bufferIndex,
   int startShift,
   int maxLookback,
   int &foundShift,
   datetime &foundTime,
   double &foundValue
)
{
   foundShift = -1;
   foundTime = 0;
   foundValue = 0.0;
   int buf = MathMax(0, bufferIndex);
   for(int sh = startShift; sh <= maxLookback; sh++)
   {
      double v = _regime_buffer_value(buf, sh);
      if(!_valid_atomic_buffer_price(v))
         continue;
      foundShift = sh;
      foundTime = Time[sh];
      foundValue = v;
      return foundTime > 0;
   }
   return false;
}

bool _find_current_atomic_regime_from_signal_buffers(string directionHint, string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &sourceName)
{
   direction = "";
   signalIndex = -1;
   signalTime = 0;
   entryPrice = 0.0;
   sourceName = "";

   if(!InpRegimeUseTrendSignalBuffers)
      return false;

   int shift = (g_regimeUseClosedBarRuntime ? 1 : 0);
   if(Bars <= shift)
      return false;

   int maxLookback = MathMax(shift, MathMin(Bars - 1, InpRegimeBufferLookbackBars));
   int upShift = -1;
   int dnShift = -1;
   datetime upTime = 0;
   datetime dnTime = 0;
   double upValue = 0.0;
   double dnValue = 0.0;
   bool hasUp = _find_latest_regime_signal_buffer(
      InpRegimeUpTrendSignalBuffer,
      shift,
      maxLookback,
      upShift,
      upTime,
      upValue
   );
   bool hasDn = _find_latest_regime_signal_buffer(
      InpRegimeDnTrendSignalBuffer,
      shift,
      maxLookback,
      dnShift,
      dnTime,
      dnValue
   );

   string state = "";
   int selectedShift = -1;
   double selectedValue = 0.0;
   if(hasUp && (!hasDn || upShift < dnShift))
   {
      state = "BUY";
      selectedShift = upShift;
      signalTime = upTime;
      selectedValue = upValue;
   }
   else if(hasDn && (!hasUp || dnShift < upShift))
   {
      state = "SELL";
      selectedShift = dnShift;
      signalTime = dnTime;
      selectedValue = dnValue;
   }
   else if(hasUp && hasDn && upShift == dnShift)
   {
      string hint = _trim(directionHint);
      StringToUpper(hint);
      if(InpRegimeUseAtomicSignalAsTieBreak && (hint == "BUY" || hint == "SELL"))
      {
         state = hint;
         selectedShift = upShift;
         signalTime = (hint == "BUY" ? upTime : dnTime);
         selectedValue = (hint == "BUY" ? upValue : dnValue);
         if(InpLogRegimeBuffer)
         {
            PrintFormat(
               "AtomicBridge regime_signal ambiguous tie_break=%s symbol=%s tf=%s up_buf=%d dn_buf=%d shift=%d up=%s dn=%s",
               hint,
               Symbol(),
               _tf_to_string(Period()),
               MathMax(0, InpRegimeUpTrendSignalBuffer),
               MathMax(0, InpRegimeDnTrendSignalBuffer),
               upShift,
               _fmt_price(upValue),
               _fmt_price(dnValue)
            );
         }
      }
      else
      {
         if(InpLogRegimeBuffer)
         {
            PrintFormat(
               "AtomicBridge regime_signal ambiguous symbol=%s tf=%s up_buf=%d dn_buf=%d shift=%d up=%s dn=%s",
               Symbol(),
               _tf_to_string(Period()),
               MathMax(0, InpRegimeUpTrendSignalBuffer),
               MathMax(0, InpRegimeDnTrendSignalBuffer),
               upShift,
               _fmt_price(upValue),
               _fmt_price(dnValue)
            );
         }
         return false;
      }
   }

   if(state != "BUY" && state != "SELL")
      return false;

   signalIndex = selectedShift;
   double entry = 0.0;
   if(shift == 0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   if(entry <= 0.0)
      entry = Close[MathMax(0, selectedShift)];
   if(entry <= 0.0)
      entry = MarketInfo(Symbol(), (state == "BUY" ? MODE_ASK : MODE_BID));
   entryPrice = NormalizeDouble(entry, Digits);
   direction = state;
   sourceName = StringFormat(
      "AtomicRegimeSignalBuffer up=%d dn=%d shift=%d selected_shift=%d up_shift=%d dn_shift=%d up=%s dn=%s selected=%s",
      MathMax(0, InpRegimeUpTrendSignalBuffer),
      MathMax(0, InpRegimeDnTrendSignalBuffer),
      shift,
      selectedShift,
      upShift,
      dnShift,
      _fmt_price(upValue),
      _fmt_price(dnValue),
      _fmt_price(selectedValue)
   );
   return entryPrice > 0.0 && signalTime > 0;
}

bool _find_current_atomic_regime_from_stop_buffers(string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &sourceName)
{
   direction = "";
   signalIndex = -1;
   signalTime = 0;
   entryPrice = 0.0;
   sourceName = "";

   if(!InpRegimeUseTrendStopBuffers)
      return false;

   int shift = (g_regimeUseClosedBarRuntime ? 1 : 0);
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
      "AtomicRegimeStopBuffer up=%d dn=%d shift=%d start_shift=%d up=%s dn=%s",
      MathMax(0, InpRegimeUpTrendStopBuffer),
      MathMax(0, InpRegimeDnTrendStopBuffer),
      shift,
      startShift,
      _fmt_price(upNow),
      _fmt_price(dnNow)
   );
   return entryPrice > 0.0 && signalTime > 0;
}

bool _find_current_atomic_regime_from_buffers(string directionHint, string &direction, int &signalIndex, datetime &signalTime, double &entryPrice, string &sourceName)
{
   if(_find_current_atomic_regime_from_signal_buffers(directionHint, direction, signalIndex, signalTime, entryPrice, sourceName))
      return true;
   return _find_current_atomic_regime_from_stop_buffers(direction, signalIndex, signalTime, entryPrice, sourceName);
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
   double atrRisk = atr * MathMax(0.1, InpRegimeAtrMultiplier);
   double pctRisk = entry * MathMax(0.0, InpRegimeMinRiskPricePct);
   double pctCap = entry * MathMax(0.0, InpRegimeMaxRiskPricePct);
   double moneyCap = 0.0;
   double valuePerUnit = _value_per_price_unit_per_lot();
   if(InpRegimeMaxRiskMoneyPerLot > 0.0 && valuePerUnit > 0.0)
      moneyCap = InpRegimeMaxRiskMoneyPerLot / valuePerUnit;
   double absoluteRisk = _valid_price_or_zero(InpRegimeMinRiskPoints);
   double risk = MathMax(MathMax(atrRisk, pctRisk), MathMax(minStop, absoluteRisk));
   double hardFloor = MathMax(minStop, absoluteRisk);
   double riskCap = 0.0;
   if(pctCap > hardFloor)
      riskCap = pctCap;
   if(moneyCap > hardFloor)
      riskCap = (riskCap > 0.0 ? MathMin(riskCap, moneyCap) : moneyCap);
   if(riskCap > hardFloor && risk > riskCap)
      risk = riskCap;
   if(risk < hardFloor)
      risk = hardFloor;
   if(InpLogRegimeBuffer)
   {
      PrintFormat(
         "AtomicBridge regime risk model dir=%s entry=%s atr=%s atr_mult=%.2f atr_risk=%s pct_floor=%.5f pct_risk=%s pct_cap=%.5f pct_cap_risk=%s money_cap_per_lot=%s money_cap_risk=%s abs_floor=%s min_stop=%s final_risk=%s rr=%.2f",
         direction,
         _fmt_price(entry),
         _fmt_price(atr),
         MathMax(0.1, InpRegimeAtrMultiplier),
         _fmt_price(atrRisk),
         MathMax(0.0, InpRegimeMinRiskPricePct),
         _fmt_price(pctRisk),
         MathMax(0.0, InpRegimeMaxRiskPricePct),
         _fmt_price(pctCap),
         _fmt_price(InpRegimeMaxRiskMoneyPerLot),
         _fmt_price(moneyCap),
         _fmt_price(absoluteRisk),
         _fmt_price(minStop),
         _fmt_price(risk),
         MathMax(0.1, InpRegimeRR)
      );
   }
   double rr = MathMax(0.1, g_regimeRRRuntime);

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
   if(!InpEnableRegimeChangePost)
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
   bool directFirst = (eventKind == "confirmed_signal" && _direct_priority_direct_first());
   if(directFirst)
      _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName);
   if(!InpEnableProTradePost)
   {
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName);
      return true;
   }
   string msg = StringFormat(
      "AtomicRegime %s %s %s idx=%d entry=%s sl=%s tp=%s atr_period=%d atr_mult=%.2f rr=%.2f min_pct=%.5f max_pct=%.5f",
      Symbol(),
      _tf_to_string(Period()),
      dir,
      signalIndex,
      _fmt_price(entryPrice),
      _fmt_price(sl),
      _fmt_price(tp),
      regimePeriod,
      MathMax(0.1, InpRegimeAtrMultiplier),
      MathMax(0.1, g_regimeRRRuntime),
      MathMax(0.0, InpRegimeMinRiskPricePct),
      MathMax(0.0, InpRegimeMaxRiskPricePct)
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
      "\"event_ts\":\"" + _json_escape(_event_ts_now()) + "\"," +
      _bridge_runtime_telemetry_json() +
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
      "\"atomic_regime_atr_period\":" + IntegerToString(regimePeriod) + ","
      "\"atomic_regime_atr_multiplier\":" + DoubleToString(MathMax(0.1, InpRegimeAtrMultiplier), 2) + ","
      "\"atomic_regime_rr\":" + DoubleToString(MathMax(0.1, g_regimeRRRuntime), 2) + ","
      "\"atomic_regime_min_risk_price_pct\":" + DoubleToString(MathMax(0.0, InpRegimeMinRiskPricePct), 6) + ","
      "\"atomic_regime_max_risk_price_pct\":" + DoubleToString(MathMax(0.0, InpRegimeMaxRiskPricePct), 6) + ","
      "\"atomic_regime_max_risk_money_per_lot\":" + DoubleToString(MathMax(0.0, InpRegimeMaxRiskMoneyPerLot), 2) + ","
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
      if(InpLogPostResponses || _should_log_handshake_response(eventKind, reason))
      {
         Print("AtomicBridge regime handshake sent ", eventKind, " ", dir, " reason=", reason, " response=", _compact_bridge_response(response));
      }
      else if(eventKind == "confirmed_signal")
      {
         Print("AtomicBridge regime sent ", eventKind, " ", dir);
      }
      if(eventKind == "confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName);
      return true;
   }

   Print("AtomicBridge regime POST failed code=", code, " err=", GetLastError(), " event=", eventKind, " dir=", dir, " endpoint=", endpoint, " response=", response);
   if(eventKind == "confirmed_signal" && !directFirst)
      _direct_mt4_execute(eventId, dir, sl, tp, InpRegimeIndicatorName);
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
         g_lastRegimeConfirmedDirection = direction;
         g_lastRegimeConfirmedSignalTime = signalTime;
      }
      return;
   }

   g_lastRegimeEventId = regimeEventId;
   if(directionChanged && regimeEventId != g_lastRegimeConfirmedEventId)
   {
      if(InpRegimeMaxConfirmShift >= 0 && signalIndex > InpRegimeMaxConfirmShift)
      {
         if(_heartbeat_due(g_lastRegimeResolvedPostTime))
         {
            if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, "heartbeat"))
               g_lastRegimeResolvedPostTime = _timer_now();
         }
         return;
      }
      if(g_lastRegimeConfirmedSignalTime > 0 && signalTime == g_lastRegimeConfirmedSignalTime && direction != g_lastRegimeConfirmedDirection)
      {
         if(InpLogRegimeBuffer)
            Print("AtomicBridge regime_signal suppressed same_bar_flip dir=", direction, " bar=", _fmt_time(signalTime), " last=", g_lastRegimeConfirmedDirection);
         return;
      }
      datetime nowStable = _timer_now();
      int stableSeconds = MathMax(0, InpRegimeConfirmStableSeconds);
      if(g_pendingRegimeEventId != regimeEventId)
      {
         g_pendingRegimeEventId = regimeEventId;
         g_pendingRegimeDirection = direction;
         g_pendingRegimeFirstSeen = nowStable;
         if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
            g_lastRegimeResolvedPostTime = nowStable;
         if(stableSeconds > 0)
            return;
      }
      if(stableSeconds > 0 && (nowStable - g_pendingRegimeFirstSeen) < stableSeconds)
      {
         if(InpLogRegimeBuffer)
            Print("AtomicBridge regime_signal pending stable dir=", direction, " age=", IntegerToString((int)(nowStable - g_pendingRegimeFirstSeen)), " event=", regimeEventId);
         return;
      }
      if(_post_atomic_regime_event("resolved_state", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason))
         g_lastRegimeResolvedPostTime = _timer_now();
      _post_atomic_regime_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, regimeSl, regimeTp, trendName, reason);
      g_lastRegimeDirection = direction;
      g_lastRegimeConfirmedEventId = regimeEventId;
      g_lastRegimeSignalIndex = signalIndex;
      g_lastRegimeSignalTime = signalTime;
      g_lastRegimeConfirmedDirection = direction;
      g_lastRegimeConfirmedSignalTime = signalTime;
      g_pendingRegimeEventId = "";
      g_pendingRegimeDirection = "";
      g_pendingRegimeFirstSeen = 0;
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
      "",
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
               "AtomicBridge regime_signal reason=%s symbol=%s tf=%s dir=%s start_bar=%s entry=%s source='%s'",
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

   if(!hasBufferRegime && InpRegimeUseAtomicSignalAsTieBreak && StringLen(direction) > 0)
   {
      hasBufferRegime = _find_current_atomic_regime_from_buffers(
         direction,
         regimeDirection,
         regimeSignalIndex,
         regimeSignalTime,
         regimeEntryPrice,
         regimeSourceName
      );
   }

   double sl, tp1, tp2, tp3, tp4, tp5;
   _find_atomic_levels(direction, signalIndex, sl, tp1, tp2, tp3, tp4, tp5);

   string eventId = StringFormat("%s|%s|%d|%I64d", Symbol(), direction, signalIndex, (long)signalTime);
   bool firstObservation = (StringLen(g_lastEventId) <= 0 || g_lastSignalTime <= 0);
   string geometryReason = "";
   bool geometryOk = _atomic_signal_geometry_valid(direction, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, geometryReason);
   if(InpLogOnlyOnChange && eventId == g_lastEventId)
   {
      if(StringLen(direction) > 0 && sl > 0.0 && tp1 > 0.0 && geometryOk && _heartbeat_due(g_lastResolvedPostTime))
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, "heartbeat"))
            g_lastResolvedPostTime = _timer_now();
      }
      if(hasBufferRegime)
         _handle_regime_event("heartbeat", regimeDirection, regimeSignalIndex, regimeSignalTime, regimeEntryPrice, regimeSourceName);
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
   else if(!geometryOk)
   {
      double livePx = (direction == "BUY" ? MarketInfo(Symbol(), MODE_ASK) : MarketInfo(Symbol(), MODE_BID));
      PrintFormat(
         "AtomicBridge warning: invalid signal geometry; not posting reason=%s dir=%s signal_entry=%s live_px=%s sl=%s final_tp=%s",
         geometryReason,
         direction,
         _fmt_price(entryPrice),
         _fmt_price(livePx),
         _fmt_price(sl),
         _fmt_price(_atomic_final_tp(tp1, tp2, tp3, tp4, tp5))
      );
   }

   if(StringLen(direction) > 0 && sl > 0.0 && tp1 > 0.0 && geometryOk)
   {
      if(reason == "init" || reason == "init_retry" || firstObservation)
      {
         if(_post_atomic_bridge_event("resolved_state", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason))
            g_lastResolvedPostTime = _timer_now();
         if((reason == "init" || reason == "init_retry") && InpSendInitialConfirmedOnStart)
         {
            _post_atomic_bridge_event("confirmed_signal", direction, signalIndex, signalTime, entryPrice, sl, tp1, tp2, tp3, tp4, tp5, trendName, reason);
            g_lastConfirmedEventId = eventId;
         }
         else if(firstObservation && reason != "init" && reason != "init_retry")
         {
            Print("AtomicBridge first_observation resolved only; confirmed_signal suppressed reason=", reason, " event=", eventId);
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
            "AtomicBridge regime_signal reason=%s symbol=%s tf=%s dir=%s start_bar=%s entry=%s source='%s'",
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
}

int OnInit()
{
   int poll = MathMax(1, InpPollSeconds);
   EventSetTimer(poll);
   g_directMt4EnabledRuntime = InpDirectMt4ExecutionEnabled;
   string priority = _lower_copy(_trim(InpDirectMt4Priority));
   g_directMt4PriorityDirectFirst = (priority != "post_first" && priority != "quantdesk_first");
   g_directMt4LotRuntime = MathMax(0.01, InpDirectMt4Lot);
   g_directMt4MaxSpreadRuntime = MathMax(0, InpDirectMt4MaxSpreadPoints);
   g_directMt4HalfBeRRuntime = MathMax(0.0, InpDirectMt4HalfBeR);
   g_regimeRRRuntime = MathMax(0.1, InpRegimeRR);
   g_regimeUseClosedBarRuntime = InpRegimeUseClosedBar;
   Print(
      "AtomicBridge BUILD=", ATOMIC_BRIDGE_BUILD,
      " indicator=", InpIndicatorName,
      " regimeLabel=", InpRegimeIndicatorName,
      " regimeBufferSource=", InpIndicatorName,
      " symbol=", Symbol(),
      " tf=", _tf_to_string(Period()),
      " poll=", poll,
      " logPost=", InpLogPostResponses,
      " regimeSignalBuffers=", (InpRegimeUseTrendSignalBuffers ? "true" : "false"),
      " upSignal=", InpRegimeUpTrendSignalBuffer,
      " dnSignal=", InpRegimeDnTrendSignalBuffer,
      " stopFallback=", (InpRegimeUseTrendStopBuffers ? "true" : "false"),
      " stableSec=", InpRegimeConfirmStableSeconds,
      " maxConfirmShift=", InpRegimeMaxConfirmShift
   );
   if(InpEnableProTradePost)
   {
      _post_atomic_bridge_event("register", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", "init");
      g_lastRegisterPostTime = _timer_now();
   }
   g_initialSetupRetryUntil = _timer_now() + MathMax(0, InpInitialSetupRetrySeconds);
   if(InpLogOnInit)
      ScanAndLogLatest("init");
   _draw_dashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpSendUnregisterOnDeinit && InpEnableProTradePost)
   {
      string why = "deinit_" + IntegerToString(reason);
      _post_atomic_bridge_event("unregister", "", -1, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, "", why);
      if(InpEnableRegimeChangePost)
         _post_atomic_regime_event("unregister", "", -1, 0, 0.0, 0.0, 0.0, "", why);
   }
   if(InpLogPostResponses || InpLogNoneSignals || InpLogRegimeBuffer)
      Print("AtomicBridge uninit reason=", reason);
   _delete_dash();
}

void OnTimer()
{
   _manage_direct_mt4_positions();
   MaybePostRegisterHeartbeat("heartbeat");
   if(InpLogOnInit && StringLen(g_lastEventId) <= 0 && _timer_now() <= g_initialSetupRetryUntil)
   {
      ScanAndLogLatest("init_retry");
      return;
   }
   ScanAndLogLatest("timer");
   _draw_dashboard();
}

void OnTick()
{
   _manage_direct_mt4_positions();
   _draw_dashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT)
      return;
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(StringFind(sparam, DASH_PREFIX + "EDIT_") == 0)
         _apply_dashboard();
      return;
   }
   if(sparam == DASH_PREFIX + "BTN_DIRECT")
   {
      g_directMt4EnabledRuntime = !g_directMt4EnabledRuntime;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_PRIORITY")
   {
      g_directMt4PriorityDirectFirst = !g_directMt4PriorityDirectFirst;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_HALFBE")
   {
      if(g_directMt4HalfBeRRuntime <= 0.0)
         g_directMt4HalfBeRRuntime = 1.0;
      else if(g_directMt4HalfBeRRuntime < 2.0)
         g_directMt4HalfBeRRuntime = 2.0;
      else if(g_directMt4HalfBeRRuntime < 3.0)
         g_directMt4HalfBeRRuntime = 3.0;
      else
         g_directMt4HalfBeRRuntime = 0.0;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_REGIME_SHIFT")
   {
      g_regimeUseClosedBarRuntime = !g_regimeUseClosedBarRuntime;
      Print("AtomicBridge dashboard regime closed-bar mode=", (g_regimeUseClosedBarRuntime ? "shift_1_closed_bar" : "shift_0_live_bar"));
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam == DASH_PREFIX + "BTN_APPLY")
      _apply_dashboard();
}
