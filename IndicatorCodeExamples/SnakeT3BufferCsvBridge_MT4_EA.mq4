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

input string InpCsvFileName = "";        // empty = snake_t3_stream_SYMBOL_TF.csv
input bool   InpUseCommonFiles = true;   // true = Terminal/Common/Files
input int    InpFlushEveryRows = 25;
input bool   InpDebugPrint = true;

int      g_file = INVALID_HANDLE;
string   g_file_name = "";
int      g_rows_since_flush = 0;
uint     g_last_write_tick = 0;
double   g_last_snake = 0.0;
double   g_last_t3 = 0.0;
bool     g_has_last = false;

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

string _default_file_name()
{
   return "snake_t3_stream_" + _safe_file_part(Symbol()) + "_" + _tf_to_string(Period()) + ".csv";
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

double _snake_value(int shift)
{
   return iCustom(NULL, 0, InpSnakeIndicatorName, InpSnakePeriod, InpSnakeBufferIndex, shift);
}

double _t3_value(int shift)
{
   return iCustom(NULL, 0, InpT3IndicatorName, InpT3Period, InpT3Price, InpT3Hot, InpT3TimeFrame, InpT3BufferIndex, shift);
}

bool _open_csv()
{
   g_file_name = _trim(InpCsvFileName);
   if(StringLen(g_file_name) <= 0)
      g_file_name = _default_file_name();

   int flags = FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE;
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
      FileWrite(
         g_file,
         "server_time",
         "local_time",
         "local_tick_ms",
         "symbol",
         "timeframe",
         "bar_time",
         "bar_shift",
         "bid",
         "ask",
         "snake_indicator",
         "snake_period",
         "snake_buffer",
         "snake_value",
         "snake_valid",
         "t3_indicator",
         "t3_period",
         "t3_price",
         "t3_hot",
         "t3_timeframe_input",
         "t3_buffer",
         "t3_value",
         "t3_valid"
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
   if(!_changed_enough(snake_val, t3_val))
      return;

   datetime server_now = TimeCurrent();
   if(server_now <= 0)
      server_now = TimeLocal();

   FileWrite(
      g_file,
      TimeToString(server_now, TIME_DATE | TIME_SECONDS),
      TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS),
      IntegerToString((int)now_tick),
      Symbol(),
      _tf_to_string(Period()),
      TimeToString(bar_time, TIME_DATE | TIME_SECONDS),
      IntegerToString(shift),
      DoubleToString(Bid, Digits),
      DoubleToString(Ask, Digits),
      InpSnakeIndicatorName,
      IntegerToString(InpSnakePeriod),
      IntegerToString(InpSnakeBufferIndex),
      DoubleToString(snake_val, 10),
      (snake_valid ? "1" : "0"),
      InpT3IndicatorName,
      IntegerToString(InpT3Period),
      IntegerToString(InpT3Price),
      DoubleToString(InpT3Hot, 6),
      InpT3TimeFrame,
      IntegerToString(InpT3BufferIndex),
      DoubleToString(t3_val, 10),
      (t3_valid ? "1" : "0")
   );

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
