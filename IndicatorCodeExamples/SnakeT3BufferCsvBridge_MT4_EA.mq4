//+------------------------------------------------------------------+
//| Snake + T3 Clean Buffer CSV Bridge (MT4)                         |
//| Fast local recorder for live iCustom buffer telemetry.           |
//+------------------------------------------------------------------+
#property strict

input string InpSnakeIndicatorName = "snake";
input int    InpSnakePeriod = 5;
input int    InpSnakeBufferIndex = 0;

input string InpT3IndicatorName = "t3_clean";
input int    InpT3Period = 14;
input int    InpT3Price = 0;
input double InpT3Hot = 0.618;
input string InpT3TimeFrame = "current time frame";
input int    InpT3BufferIndex = 0;

input int    InpValueShift = 0;          // 0 = live/open bar, 1 = last closed bar
input bool   InpSampleOnTick = true;     // fastest on active symbols
input bool   InpSampleOnTimer = true;    // keeps sampling during quiet tick periods
input int    InpTimerMilliseconds = 250; // MT4 millisecond timer cadence
input int    InpMinWriteIntervalMs = 0;  // 0 = write every tick/timer sample
input bool   InpWriteOnlyOnChange = false;
input double InpMinDelta = 0.0;

input string InpInstanceLabel = "";      // optional label added to file name and rows
input string InpCsvFileName = "";        // empty = snake_t3_stream_SYMBOL_TF.csv
input bool   InpUseCommonFiles = true;   // true = Terminal/Common/Files
input int    InpFlushEveryRows = 25;
input bool   InpDebugPrint = true;

input bool   InpSendBridgeEvents = false;
input string InpBridgeIndicatorName = "SnakeT3State";
input string InpBridgeEndpoint = "http://127.0.0.1/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "snake_t3_state";
input int    InpBridgeResolvedEverySeconds = 1;
input int    InpBridgeHttpTimeoutMs = 700;
input bool   InpBridgePrintSuccess = false;
input bool   InpSendRegistrationOnInit = true;

input int    InpAtrPeriod = 14;
input int    InpRsiPeriod = 14;
input int    InpFastMaPeriod = 20;
input int    InpSlowMaPeriod = 50;
input int    InpAdxPeriod = 14;
input int    InpMacdFast = 12;
input int    InpMacdSlow = 26;
input int    InpMacdSignal = 9;
input int    InpStochK = 5;
input int    InpStochD = 3;
input int    InpStochSlowing = 3;
input int    InpCciPeriod = 14;
input int    InpMomentumPeriod = 14;
input double InpDatasetLotSize = 1.0;    // hypothetical PnL lot for ML labels

int      g_file = INVALID_HANDLE;
string   g_file_name = "";
int      g_rows_since_flush = 0;
uint     g_last_write_tick = 0;
double   g_last_snake = 0.0;
double   g_last_t3 = 0.0;
bool     g_has_last = false;
string   g_instance_id = "";
string   g_last_state = "";
double   g_state_entry_price = 0.0;
datetime g_state_entry_time = 0;
datetime g_last_bridge_sent_at = 0;
string   g_last_bridge_state = "";

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

string _trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

string _safe_file_part(string s)
{
   string out = _trim(s);
   StringReplace(out, "\\", "_");
   StringReplace(out, "/", "_");
   StringReplace(out, ":", "_");
   StringReplace(out, "*", "_");
   StringReplace(out, "?", "_");
   StringReplace(out, "\"", "_");
   StringReplace(out, "<", "_");
   StringReplace(out, ">", "_");
   StringReplace(out, "|", "_");
   StringReplace(out, " ", "_");
   return out;
}

string _chart_id_string()
{
   return DoubleToString((double)ChartID(), 0);
}

string _build_instance_id()
{
   string label = _safe_file_part(InpInstanceLabel);
   if(StringLen(label) > 0)
      label = label + "_";
   string ts = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
   StringReplace(ts, ".", "");
   StringReplace(ts, ":", "");
   StringReplace(ts, " ", "_");
   return label + "acct" + IntegerToString(AccountNumber()) + "_chart" + _chart_id_string() + "_init" + ts;
}

string _default_file_name()
{
   return "snake_t3_ml_stream_" + _safe_file_part(Symbol()) + "_" + _tf_to_string(Period()) + "_" + _safe_file_part(g_instance_id) + ".csv";
}

bool _valid_value(double v)
{
   if(!MathIsValidNumber(v))
      return false;
   if(v == EMPTY_VALUE)
      return false;
   if(MathAbs(v) >= 2147480000.0)
      return false;
   return true;
}

string _snake_t3_state(double snake_val, bool snake_valid, double t3_val, bool t3_valid)
{
   if(!snake_valid || !t3_valid)
      return "NONE";
   if(t3_val < snake_val)
      return "BUY";
   if(t3_val > snake_val)
      return "SELL";
   return "FLAT";
}

double _money_pnl_for_state(string state, double entry_price, double exit_price)
{
   double tick_size = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   double lot = InpDatasetLotSize;
   if(tick_size <= 0.0 || tick_value == 0.0 || lot <= 0.0)
      return 0.0;
   double price_delta = 0.0;
   if(state == "BUY")
      price_delta = exit_price - entry_price;
   else if(state == "SELL")
      price_delta = entry_price - exit_price;
   else
      return 0.0;
   return (price_delta / tick_size) * tick_value * lot;
}

double _points_pnl_for_state(string state, double entry_price, double exit_price)
{
   if(Point <= 0.0)
      return 0.0;
   if(state == "BUY")
      return (exit_price - entry_price) / Point;
   if(state == "SELL")
      return (entry_price - exit_price) / Point;
   return 0.0;
}

string _num(double v, int precision)
{
   if(!_valid_value(v))
      return "";
   return DoubleToString(v, precision);
}

string _int_text(int v)
{
   return IntegerToString(v);
}

string _csv_escape(string s)
{
   string out = s;
   StringReplace(out, "\"", "\"\"");
   bool must_quote = (StringFind(out, ",") >= 0 || StringFind(out, "\"") >= 0 || StringFind(out, "\r") >= 0 || StringFind(out, "\n") >= 0);
   if(must_quote)
      out = "\"" + out + "\"";
   return out;
}

string _json_escape(string s)
{
   string out = s;
   StringReplace(out, "\\", "\\\\");
   StringReplace(out, "\"", "\\\"");
   StringReplace(out, "\r", "\\r");
   StringReplace(out, "\n", "\\n");
   StringReplace(out, "\t", "\\t");
   return out;
}

void _json_add_str(string &json, string key, string value)
{
   if(StringLen(json) > 1)
      json = json + ",";
   json = json + "\"" + _json_escape(key) + "\":\"" + _json_escape(value) + "\"";
}

void _json_add_num(string &json, string key, string value)
{
   if(StringLen(json) > 1)
      json = json + ",";
   if(StringLen(_trim(value)) <= 0)
      json = json + "\"" + _json_escape(key) + "\":null";
   else
      json = json + "\"" + _json_escape(key) + "\":" + value;
}

string _iso_utc(datetime ts)
{
   return TimeToString(ts, TIME_DATE | TIME_SECONDS);
}

void _csv_add(string &line, string value, bool text_value=false)
{
   if(StringLen(line) > 0)
      line = line + ",";
   if(text_value)
      line = line + _csv_escape(value);
   else
      line = line + value;
}

void _write_csv_line(string line)
{
   FileWriteString(g_file, line + "\r\n");
}

double _snake_value(int shift)
{
   return iCustom(NULL, 0, InpSnakeIndicatorName, InpSnakePeriod, InpSnakeBufferIndex, shift);
}

double _t3_value(int shift)
{
   return iCustom(NULL, 0, InpT3IndicatorName, InpT3Period, InpT3Price, InpT3Hot, InpT3TimeFrame, InpT3BufferIndex, shift);
}

bool _bridge_due(string state, datetime now_time)
{
   if(!InpSendBridgeEvents)
      return false;
   if(g_last_bridge_state != state)
      return true;
   int every = InpBridgeResolvedEverySeconds;
   if(every < 1)
      every = 1;
   if(g_last_bridge_sent_at <= 0)
      return true;
   return (now_time - g_last_bridge_sent_at) >= every;
}

bool _bridge_post(string event_type, string state, int shift, datetime bar_time, double snake_val, bool snake_valid, double t3_val, bool t3_valid, double mid)
{
   if(!InpSendBridgeEvents)
      return false;

   datetime now_time = TimeCurrent();
   if(now_time <= 0)
      now_time = TimeLocal();

   string indicator_name = _trim(InpBridgeIndicatorName);
   if(StringLen(indicator_name) <= 0)
      indicator_name = "SnakeT3State";

   string json = "{";
   _json_add_str(json, "terminal_family", "mt4");
   _json_add_str(json, "indicator", indicator_name);
   _json_add_str(json, "signal_profile", _trim(InpSignalProfile));
   _json_add_str(json, "symbol", Symbol());
   _json_add_str(json, "timeframe", _tf_to_string(Period()));
   _json_add_str(json, "bridge_version", "v2");
   _json_add_str(json, "ingest_source", "bridge");
   _json_add_str(json, "bridge_event_type", event_type);
   _json_add_str(json, "event_ts", _iso_utc(now_time));
   _json_add_str(json, "event_id", event_type + "|" + state + "|" + Symbol() + "|" + _tf_to_string(Period()) + "|" + indicator_name + "|" + IntegerToString((int)now_time));
   string signal_hint = (event_type == "register") ? "NONE" : state;
   _json_add_str(json, "message", "snake_t3_state " + state);
   _json_add_str(json, "signal_hint", signal_hint);
   _json_add_str(json, "resolved_signal", state);
   _json_add_str(json, "last_signal_direction", state);
   _json_add_str(json, "resolved_signal_bar_time", TimeToString(bar_time, TIME_DATE | TIME_SECONDS));
   _json_add_num(json, "resolved_signal_bar_unix", IntegerToString((int)bar_time));
   _json_add_num(json, "resolved_signal_shift", IntegerToString(shift));
   _json_add_num(json, "resolved_raw_buy", state == "BUY" ? "1" : "0");
   _json_add_num(json, "resolved_raw_sell", state == "SELL" ? "1" : "0");
   _json_add_num(json, "signal_value", _num(mid, Digits));
   _json_add_num(json, "snake_value", _num(snake_val, 10));
   _json_add_num(json, "t3_value", _num(t3_val, 10));
   _json_add_num(json, "snake_valid", snake_valid ? "1" : "0");
   _json_add_num(json, "t3_valid", t3_valid ? "1" : "0");
   _json_add_str(json, "instance_id", g_instance_id);
   json = json + "}";

   string headers = "Content-Type: application/json\r\n";
   if(StringLen(_trim(InpBridgeToken)) > 0)
      headers = headers + "Authorization: Bearer " + _trim(InpBridgeToken) + "\r\n";

   char data[];
   char result[];
   string response_headers = "";
   StringToCharArray(json, data, 0, StringLen(json), CP_UTF8);

   ResetLastError();
   int code = WebRequest("POST", _trim(InpBridgeEndpoint), headers, InpBridgeHttpTimeoutMs, data, result, response_headers);
   string response = CharArrayToString(result, 0, -1, CP_UTF8);
   if(code < 200 || code >= 300)
   {
      if(InpDebugPrint)
         Print("SnakeT3CsvBridge bridge POST failed code=", code, " err=", GetLastError(), " event=", event_type, " state=", state, " response=", response);
      return false;
   }
   if(InpDebugPrint && InpBridgePrintSuccess)
      Print("SnakeT3CsvBridge bridge sent ", event_type, " ", state, " response=", response);
   return true;
}

void _bridge_maybe_send_state(string state, int shift, datetime bar_time, double snake_val, bool snake_valid, double t3_val, bool t3_valid, double mid)
{
   datetime now_time = TimeCurrent();
   if(now_time <= 0)
      now_time = TimeLocal();
   if(!_bridge_due(state, now_time))
      return;
   if(_bridge_post("resolved_state", state, shift, bar_time, snake_val, snake_valid, t3_val, t3_valid, mid))
   {
      g_last_bridge_sent_at = now_time;
      g_last_bridge_state = state;
   }
}

bool _open_csv()
{
   g_file_name = _trim(InpCsvFileName);
   if(StringLen(g_file_name) <= 0)
      g_file_name = _default_file_name();

   int flags = FILE_TXT | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpUseCommonFiles)
      flags = flags | FILE_COMMON;

   ResetLastError();
   g_file = FileOpen(g_file_name, flags, ',');
   if(g_file == INVALID_HANDLE)
   {
      Print("SnakeT3CsvBridge FileOpen failed file=", g_file_name, " err=", GetLastError());
      return false;
   }

   if(FileSize(g_file) <= 0)
   {
      _write_csv_line(
         "server_time,local_time,server_year,server_month,server_day,server_day_of_week,server_hour,server_minute,server_second,local_tick_ms,"
         "account,chart_id,instance_id,sample_source,symbol,timeframe,bar_time,bar_shift,bar_age_sec,"
         "bid,ask,mid,spread,spread_points,point,digits,"
         "bar_open,bar_high,bar_low,bar_close,tick_volume,prev_close,close_delta,close_return_pct,bar_range,bar_body,upper_wick,lower_wick,"
         "atr,atr_points,rsi,ema_fast,ema_slow,ema_diff,adx,plus_di,minus_di,macd_main,macd_signal,macd_hist,stoch_k,stoch_d,cci,momentum,"
         "snake_t3_state,prev_snake_t3_state,state_changed,state_transition,state_entry_time,state_entry_price,cross_price,closed_state_pnl_price,closed_state_pnl_points,closed_state_pnl_money,dataset_lot_size,"
         "snake_indicator,snake_period,snake_buffer,snake_value,snake_valid,t3_indicator,t3_period,t3_price,t3_hot,t3_timeframe_input,t3_buffer,t3_value,t3_valid"
      );
      FileFlush(g_file);
   }
   FileSeek(g_file, 0, SEEK_END);
   return true;
}

string _files_scope_label()
{
   return InpUseCommonFiles ? "COMMON_FILES" : "TERMINAL_FILES";
}

void _close_csv()
{
   if(g_file != INVALID_HANDLE)
   {
      FileFlush(g_file);
      FileClose(g_file);
      g_file = INVALID_HANDLE;
   }
}

bool _changed_enough(double snake_val, double t3_val)
{
   if(!g_has_last)
      return true;
   if(!InpWriteOnlyOnChange)
      return true;
   double d1 = MathAbs(snake_val - g_last_snake);
   double d2 = MathAbs(t3_val - g_last_t3);
   return (d1 >= InpMinDelta || d2 >= InpMinDelta);
}

void _capture(string source)
{
   if(g_file == INVALID_HANDLE)
      return;

   uint now_tick = GetTickCount();
   if(InpMinWriteIntervalMs > 0 && g_last_write_tick > 0)
   {
      uint elapsed = now_tick - g_last_write_tick;
      if(elapsed < (uint)InpMinWriteIntervalMs)
         return;
   }

   int shift = InpValueShift;
   if(shift < 0)
      shift = 0;
   datetime bar_time = iTime(NULL, 0, shift);
   if(bar_time <= 0)
      return;

   double snake_val = _snake_value(shift);
   double t3_val = _t3_value(shift);
   bool snake_valid = _valid_value(snake_val);
   bool t3_valid = _valid_value(t3_val);
   string state = _snake_t3_state(snake_val, snake_valid, t3_val, t3_valid);
   if(!_changed_enough(snake_val, t3_val))
      return;

   datetime server_now = TimeCurrent();
   if(server_now <= 0)
      server_now = TimeLocal();
   datetime local_now = TimeLocal();

   MqlDateTime dt;
   TimeToStruct(server_now, dt);

   double bid = Bid;
   double ask = Ask;
   double mid = (bid + ask) / 2.0;
   double spread = ask - bid;
   double spread_points = (Point > 0.0 ? spread / Point : 0.0);

   double bar_open = iOpen(NULL, 0, shift);
   double bar_high = iHigh(NULL, 0, shift);
   double bar_low = iLow(NULL, 0, shift);
   double bar_close = iClose(NULL, 0, shift);
   double prev_close = iClose(NULL, 0, shift + 1);
   double close_delta = bar_close - prev_close;
   double close_return_pct = (prev_close != 0.0 ? (close_delta / prev_close) * 100.0 : 0.0);
   double bar_range = bar_high - bar_low;
   double bar_body = MathAbs(bar_close - bar_open);
   double upper_wick = bar_high - MathMax(bar_open, bar_close);
   double lower_wick = MathMin(bar_open, bar_close) - bar_low;
   double tick_volume = (double)iVolume(NULL, 0, shift);

   double atr = iATR(NULL, 0, InpAtrPeriod, shift);
   double atr_points = (Point > 0.0 ? atr / Point : 0.0);
   double rsi = iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, shift);
   double ema_fast = iMA(NULL, 0, InpFastMaPeriod, 0, MODE_EMA, PRICE_CLOSE, shift);
   double ema_slow = iMA(NULL, 0, InpSlowMaPeriod, 0, MODE_EMA, PRICE_CLOSE, shift);
   double ema_diff = ema_fast - ema_slow;
   double adx = iADX(NULL, 0, InpAdxPeriod, PRICE_CLOSE, MODE_MAIN, shift);
   double plus_di = iADX(NULL, 0, InpAdxPeriod, PRICE_CLOSE, MODE_PLUSDI, shift);
   double minus_di = iADX(NULL, 0, InpAdxPeriod, PRICE_CLOSE, MODE_MINUSDI, shift);
   double macd_main = iMACD(NULL, 0, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE, MODE_MAIN, shift);
   double macd_signal = iMACD(NULL, 0, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE, MODE_SIGNAL, shift);
   double macd_hist = macd_main - macd_signal;
   double stoch_k = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, 0, MODE_MAIN, shift);
   double stoch_d = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, 0, MODE_SIGNAL, shift);
   double cci = iCCI(NULL, 0, InpCciPeriod, PRICE_TYPICAL, shift);
   double momentum = iMomentum(NULL, 0, InpMomentumPeriod, PRICE_CLOSE, shift);

   string prev_state = g_last_state;
   bool state_changed = false;
   string transition = "";
   double closed_pnl_price = 0.0;
   double closed_pnl_points = 0.0;
   double closed_pnl_money = 0.0;
   datetime prior_entry_time = g_state_entry_time;
   double prior_entry_price = g_state_entry_price;

   if(prev_state == "")
   {
      if(state == "BUY" || state == "SELL")
      {
         g_last_state = state;
         g_state_entry_price = mid;
         g_state_entry_time = server_now;
      }
      prev_state = "";
      prior_entry_time = g_state_entry_time;
      prior_entry_price = g_state_entry_price;
   }
   else if(state != prev_state && (state == "BUY" || state == "SELL"))
   {
      state_changed = true;
      transition = prev_state + "_TO_" + state;
      if((prev_state == "BUY" || prev_state == "SELL") && g_state_entry_price > 0.0)
      {
         closed_pnl_price = (prev_state == "BUY") ? (mid - g_state_entry_price) : (g_state_entry_price - mid);
         closed_pnl_points = _points_pnl_for_state(prev_state, g_state_entry_price, mid);
         closed_pnl_money = _money_pnl_for_state(prev_state, g_state_entry_price, mid);
      }
      prior_entry_time = g_state_entry_time;
      prior_entry_price = g_state_entry_price;
      g_last_state = state;
      g_state_entry_price = mid;
      g_state_entry_time = server_now;
   }

   string line = "";
   _csv_add(line, TimeToString(server_now, TIME_DATE | TIME_SECONDS), true);
   _csv_add(line, TimeToString(local_now, TIME_DATE | TIME_SECONDS), true);
   _csv_add(line, _int_text(dt.year));
   _csv_add(line, _int_text(dt.mon));
   _csv_add(line, _int_text(dt.day));
   _csv_add(line, _int_text(dt.day_of_week));
   _csv_add(line, _int_text(dt.hour));
   _csv_add(line, _int_text(dt.min));
   _csv_add(line, _int_text(dt.sec));
   _csv_add(line, IntegerToString((int)now_tick));
   _csv_add(line, IntegerToString(AccountNumber()));
   _csv_add(line, _chart_id_string(), true);
   _csv_add(line, g_instance_id, true);
   _csv_add(line, source, true);
   _csv_add(line, Symbol(), true);
   _csv_add(line, _tf_to_string(Period()), true);
   _csv_add(line, TimeToString(bar_time, TIME_DATE | TIME_SECONDS), true);
   _csv_add(line, _int_text(shift));
   _csv_add(line, _int_text((int)(server_now - bar_time)));
   _csv_add(line, _num(bid, Digits));
   _csv_add(line, _num(ask, Digits));
   _csv_add(line, _num(mid, Digits));
   _csv_add(line, _num(spread, Digits));
   _csv_add(line, _num(spread_points, 2));
   _csv_add(line, _num(Point, 10));
   _csv_add(line, _int_text(Digits));
   _csv_add(line, _num(bar_open, Digits));
   _csv_add(line, _num(bar_high, Digits));
   _csv_add(line, _num(bar_low, Digits));
   _csv_add(line, _num(bar_close, Digits));
   _csv_add(line, _num(tick_volume, 0));
   _csv_add(line, _num(prev_close, Digits));
   _csv_add(line, _num(close_delta, Digits));
   _csv_add(line, _num(close_return_pct, 8));
   _csv_add(line, _num(bar_range, Digits));
   _csv_add(line, _num(bar_body, Digits));
   _csv_add(line, _num(upper_wick, Digits));
   _csv_add(line, _num(lower_wick, Digits));
   _csv_add(line, _num(atr, Digits));
   _csv_add(line, _num(atr_points, 2));
   _csv_add(line, _num(rsi, 6));
   _csv_add(line, _num(ema_fast, Digits));
   _csv_add(line, _num(ema_slow, Digits));
   _csv_add(line, _num(ema_diff, Digits));
   _csv_add(line, _num(adx, 6));
   _csv_add(line, _num(plus_di, 6));
   _csv_add(line, _num(minus_di, 6));
   _csv_add(line, _num(macd_main, Digits));
   _csv_add(line, _num(macd_signal, Digits));
   _csv_add(line, _num(macd_hist, Digits));
   _csv_add(line, _num(stoch_k, 6));
   _csv_add(line, _num(stoch_d, 6));
   _csv_add(line, _num(cci, 6));
   _csv_add(line, _num(momentum, 6));
   _csv_add(line, state, true);
   _csv_add(line, prev_state, true);
   _csv_add(line, (state_changed ? "1" : "0"));
   _csv_add(line, transition, true);
   _csv_add(line, prior_entry_time > 0 ? TimeToString(prior_entry_time, TIME_DATE | TIME_SECONDS) : "", true);
   _csv_add(line, prior_entry_price > 0.0 ? _num(prior_entry_price, Digits) : "");
   _csv_add(line, _num(mid, Digits));
   _csv_add(line, state_changed ? _num(closed_pnl_price, Digits) : "");
   _csv_add(line, state_changed ? _num(closed_pnl_points, 2) : "");
   _csv_add(line, state_changed ? _num(closed_pnl_money, 2) : "");
   _csv_add(line, _num(InpDatasetLotSize, 2));
   _csv_add(line, InpSnakeIndicatorName, true);
   _csv_add(line, _int_text(InpSnakePeriod));
   _csv_add(line, _int_text(InpSnakeBufferIndex));
   _csv_add(line, _num(snake_val, 10));
   _csv_add(line, (snake_valid ? "1" : "0"));
   _csv_add(line, InpT3IndicatorName, true);
   _csv_add(line, _int_text(InpT3Period));
   _csv_add(line, _int_text(InpT3Price));
   _csv_add(line, _num(InpT3Hot, 6));
   _csv_add(line, InpT3TimeFrame, true);
   _csv_add(line, _int_text(InpT3BufferIndex));
   _csv_add(line, _num(t3_val, 10));
   _csv_add(line, (t3_valid ? "1" : "0"));
   _write_csv_line(line);

   g_last_snake = snake_val;
   g_last_t3 = t3_val;
   g_has_last = true;
   g_last_write_tick = now_tick;
   g_rows_since_flush++;

   if(InpFlushEveryRows <= 1 || g_rows_since_flush >= InpFlushEveryRows)
   {
      FileFlush(g_file);
      g_rows_since_flush = 0;
   }

   _bridge_maybe_send_state(state, shift, bar_time, snake_val, snake_valid, t3_val, t3_valid, mid);
}

void _print_startup_probe(string probe_source)
{
   int shift = InpValueShift;
   if(shift < 0)
      shift = 0;
   datetime bar_time = iTime(NULL, 0, shift);
   double snake_val = _snake_value(shift);
   double t3_val = _t3_value(shift);
   Print(
      "SnakeT3CsvBridge startup probe source=",
      probe_source,
      " symbol=", Symbol(),
      " tf=", _tf_to_string(Period()),
      " shift=", IntegerToString(shift),
      " bar=", TimeToString(bar_time, TIME_DATE | TIME_SECONDS),
      " snake[", IntegerToString(InpSnakeBufferIndex), "]=", DoubleToString(snake_val, 10),
      " valid=", (_valid_value(snake_val) ? "true" : "false"),
      " t3[", IntegerToString(InpT3BufferIndex), "]=", DoubleToString(t3_val, 10),
      " valid=", (_valid_value(t3_val) ? "true" : "false")
   );
}

int OnInit()
{
   g_instance_id = _build_instance_id();
   if(!_open_csv())
      return INIT_FAILED;

   if(InpSampleOnTimer)
   {
      int ms = InpTimerMilliseconds;
      if(ms < 50)
         ms = 50;
      EventSetMillisecondTimer(ms);
   }

   Print("SnakeT3CsvBridge initialized: ", Symbol(), " ", _tf_to_string(Period()), " file=", g_file_name, " scope=", _files_scope_label());
   Print("SnakeT3CsvBridge snake=", InpSnakeIndicatorName, "(", InpSnakePeriod, ") buffer=", InpSnakeBufferIndex);
   Print("SnakeT3CsvBridge t3=", InpT3IndicatorName, "(", InpT3Period, ",", InpT3Price, ",", DoubleToString(InpT3Hot, 6), ",", InpT3TimeFrame, ") buffer=", InpT3BufferIndex);
   _print_startup_probe("init");

   if(InpSendBridgeEvents && InpSendRegistrationOnInit)
   {
      int shift = InpValueShift;
      if(shift < 0)
         shift = 0;
      datetime bar_time = iTime(NULL, 0, shift);
      double snake_val = _snake_value(shift);
      double t3_val = _t3_value(shift);
      bool snake_valid = _valid_value(snake_val);
      bool t3_valid = _valid_value(t3_val);
      string state = _snake_t3_state(snake_val, snake_valid, t3_val, t3_valid);
      double bid = Bid;
      double ask = Ask;
      double mid = (bid + ask) / 2.0;
      _bridge_post("register", state, shift, bar_time, snake_val, snake_valid, t3_val, t3_valid, mid);
   }

   _capture("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   _close_csv();
}

void OnTick()
{
   if(InpSampleOnTick)
      _capture("tick");
}

void OnTimer()
{
   if(InpSampleOnTimer)
      _capture("timer");
}
