#ifndef __TRADEDAY_CALENDAR_PUBLISHER_MQH__
#define __TRADEDAY_CALENDAR_PUBLISHER_MQH__

input group "TradeDay Calendar Publisher"
input bool   InpTdCalendarPublisherEnabled       = true;
input string InpTdCalendarFile                   = "TradeDay_Tier1_News_GMT.csv";
input int    InpTdCalendarLookaheadDays          = 0; // 0 = all future events currently available from MQL5.
input bool   InpTdCalendarIncludeJapanMediumHigh = true;
input bool   InpTdCalendarIncludeJapanLow        = false;

#define TD_CALENDAR_BUILD "2026-07-27.mql5-calendar-v1"

struct TdCalendarRow
{
   datetime event_gmt;
   string   scope;
   string   label;
};

datetime g_tdCalendarNextAttemptLocal = 0;
double   g_tdCalendarLockToken = 0.0;
bool     g_tdCalendarStateLoaded = false;
int      g_tdCalendarPublishedDay = 0;
int      g_tdCalendarPublishedOffsetSec = 999999;

string TdCalendarGvPrefix()
{
   return "TD_CAL_PUB_V1_";
}

int TdCalendarUtcDay(datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

string TdCalendarFormatGmt(datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

int TdCalendarServerOffsetSeconds()
{
   datetime server_now = TimeTradeServer();
   datetime gmt_now = TimeGMT();
   if(server_now <= 0 || gmt_now <= 0)
      return 999999;

   // The clocks can be sampled a fraction of a second apart. Calendar offsets
   // are timezone offsets, so normalize sampling noise to complete minutes.
   double raw_minutes = (double)(server_now - gmt_now) / 60.0;
   return (int)MathRound(raw_minutes) * 60;
}

void TdCalendarLoadState()
{
   if(g_tdCalendarStateLoaded)
      return;

   string day_key = TdCalendarGvPrefix() + "DAY";
   string offset_key = TdCalendarGvPrefix() + "OFFSET";
   g_tdCalendarPublishedDay = GlobalVariableCheck(day_key) ? (int)GlobalVariableGet(day_key) : 0;
   g_tdCalendarPublishedOffsetSec = GlobalVariableCheck(offset_key) ? (int)GlobalVariableGet(offset_key) : 999999;
   g_tdCalendarStateLoaded = true;
}

void TdCalendarSaveState(int utc_day, int offset_seconds)
{
   g_tdCalendarPublishedDay = utc_day;
   g_tdCalendarPublishedOffsetSec = offset_seconds;
   GlobalVariableSet(TdCalendarGvPrefix() + "DAY", (double)utc_day);
   GlobalVariableSet(TdCalendarGvPrefix() + "OFFSET", (double)offset_seconds);
}

bool TdCalendarAcquireLock()
{
   string key = TdCalendarGvPrefix() + "LOCK";
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);

   double now_local = (double)TimeLocal();
   for(int attempt = 0; attempt < 5; ++attempt)
   {
      double observed = GlobalVariableGet(key);
      if(observed > now_local && observed <= now_local + 600.0)
         return false;

      double token = now_local + 300.0 + (double)((ChartID() % 997) + 1) / 1000.0;
      if(GlobalVariableSetOnCondition(key, token, observed))
      {
         g_tdCalendarLockToken = token;
         return true;
      }
      Sleep(10);
   }
   return false;
}

void TdCalendarReleaseLock()
{
   if(g_tdCalendarLockToken <= 0.0)
      return;
   GlobalVariableSetOnCondition(TdCalendarGvPrefix() + "LOCK", 0.0, g_tdCalendarLockToken);
   g_tdCalendarLockToken = 0.0;
}

string TdCalendarLower(string value)
{
   StringToLower(value);
   return value;
}

bool TdCalendarContains(string value, string token)
{
   return StringFind(value, token) >= 0;
}

string TdCalendarSafeLabel(string prefix, string event_name)
{
   string text = event_name;
   StringTrimLeft(text);
   StringTrimRight(text);
   StringReplace(text, ",", " ");
   StringReplace(text, ";", " ");
   StringReplace(text, "\r", " ");
   StringReplace(text, "\n", " ");
   while(StringFind(text, "  ") >= 0)
      StringReplace(text, "  ", " ");
   StringReplace(text, " ", "_");
   StringToUpper(text);
   return prefix + text;
}

bool TdCalendarClassifyTradeDayUs(string event_name, string &scope, string &label_prefix)
{
   string name = TdCalendarLower(event_name);
   bool fomc = TdCalendarContains(name, "fomc");

   if(fomc && TdCalendarContains(name, "minute"))
   {
      scope = "ALL";
      label_prefix = "TD_FOMC_MINUTES_";
      return true;
   }
   if((fomc && (TdCalendarContains(name, "statement") || TdCalendarContains(name, "interest rate") || TdCalendarContains(name, "rate decision")))
      || TdCalendarContains(name, "federal funds rate")
      || TdCalendarContains(name, "fed interest rate decision"))
   {
      scope = "ALL";
      label_prefix = "TD_FOMC_RATE_";
      return true;
   }
   if(TdCalendarContains(name, "consumer price index") || TdCalendarContains(name, " cpi") || StringFind(name, "cpi") == 0)
   {
      scope = "ALL";
      label_prefix = "TD_US_CPI_";
      return true;
   }
   if(TdCalendarContains(name, "nonfarm payroll") || TdCalendarContains(name, "non-farm payroll") || TdCalendarContains(name, "nonfarm employment"))
   {
      scope = "ALL";
      label_prefix = "TD_US_NFP_";
      return true;
   }
   if((TdCalendarContains(name, "eia") && TdCalendarContains(name, "crude"))
      || TdCalendarContains(name, "crude oil inventories")
      || TdCalendarContains(name, "crude oil stocks"))
   {
      scope = "OIL";
      label_prefix = "TD_EIA_CRUDE_";
      return true;
   }
   if((TdCalendarContains(name, "eia") && TdCalendarContains(name, "natural gas"))
      || TdCalendarContains(name, "natural gas storage")
      || TdCalendarContains(name, "natural gas inventories"))
   {
      scope = "GAS";
      label_prefix = "TD_EIA_GAS_";
      return true;
   }
   if(TdCalendarContains(name, "crop production") || TdCalendarContains(name, "wasde"))
   {
      scope = "AGS";
      label_prefix = "TD_USDA_CROP_";
      return true;
   }
   return false;
}

bool TdCalendarAddRow(TdCalendarRow &rows[], datetime event_gmt, string scope, string label)
{
   if(event_gmt <= 0 || scope == "" || label == "")
      return false;

   int count = ArraySize(rows);
   for(int i = 0; i < count; ++i)
   {
      if(rows[i].event_gmt == event_gmt && rows[i].scope == scope && rows[i].label == label)
         return false;
   }

   if(ArrayResize(rows, count + 1) != count + 1)
      return false;
   rows[count].event_gmt = event_gmt;
   rows[count].scope = scope;
   rows[count].label = label;
   return true;
}

void TdCalendarSortRows(TdCalendarRow &rows[])
{
   int count = ArraySize(rows);
   for(int i = 1; i < count; ++i)
   {
      TdCalendarRow current = rows[i];
      int j = i - 1;
      while(j >= 0 && (rows[j].event_gmt > current.event_gmt
         || (rows[j].event_gmt == current.event_gmt && rows[j].scope > current.scope)))
      {
         rows[j + 1] = rows[j];
         --j;
      }
      rows[j + 1] = current;
   }
}

bool TdCalendarLoadCountry(string country, string currency, datetime from_server, datetime to_server,
                           int server_offset_seconds, bool japan_mode, TdCalendarRow &rows[],
                           int &source_count, datetime &max_relevant_gmt)
{
   MqlCalendarValue values[];
   ResetLastError();
   int count = CalendarValueHistory(values, from_server, to_server, country, currency);
   if(count < 0)
   {
      Print("TradeDay calendar query failed country=", country, " err=", GetLastError());
      return false;
   }

   source_count += count;
   int detail_failures = 0;
   for(int i = 0; i < count; ++i)
   {
      if(values[i].time <= 0 || values[i].event_id == 0)
         continue;

      MqlCalendarEvent event_info;
      ResetLastError();
      if(!CalendarEventById(values[i].event_id, event_info))
      {
         ++detail_failures;
         continue;
      }

      datetime event_gmt = values[i].time - server_offset_seconds;
      if(japan_mode)
      {
         bool accepted = false;
         string prefix = "";
         if(InpTdCalendarIncludeJapanMediumHigh && event_info.importance == CALENDAR_IMPORTANCE_MODERATE)
         {
            accepted = true;
            prefix = "JP_MEDIUM_";
         }
         else if(InpTdCalendarIncludeJapanMediumHigh && event_info.importance == CALENDAR_IMPORTANCE_HIGH)
         {
            accepted = true;
            prefix = "JP_HIGH_";
         }
         else if(InpTdCalendarIncludeJapanLow && event_info.importance == CALENDAR_IMPORTANCE_LOW)
         {
            accepted = true;
            prefix = "JP_LOW_";
         }

         if(accepted && TdCalendarAddRow(rows, event_gmt, "NKD", TdCalendarSafeLabel(prefix, event_info.name)))
            if(event_gmt > max_relevant_gmt) max_relevant_gmt = event_gmt;
      }
      else
      {
         string scope = "";
         string prefix = "";
         if(TdCalendarClassifyTradeDayUs(event_info.name, scope, prefix)
            && TdCalendarAddRow(rows, event_gmt, scope, TdCalendarSafeLabel(prefix, event_info.name)))
            if(event_gmt > max_relevant_gmt) max_relevant_gmt = event_gmt;
      }
   }
   if(detail_failures > 0)
   {
      Print("TradeDay calendar event detail lookup failed country=", country, " failures=", detail_failures);
      return false;
   }
   return true;
}

string TdCalendarTempFileName(string target_file)
{
   return target_file + ".tmp." + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))
      + "." + IntegerToString((int)(ChartID() % 2147483647))
      + "." + IntegerToString((int)GetTickCount());
}

bool TdCalendarWriteAtomic(string target_file, TdCalendarRow &rows[], int server_offset_seconds,
                           int source_count, datetime max_relevant_gmt)
{
   string temp_file = TdCalendarTempFileName(target_file);
   FileDelete(temp_file, FILE_COMMON);
   ResetLastError();
   int handle = FileOpen(temp_file, FILE_CSV | FILE_WRITE | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("TradeDay calendar temp open failed err=", GetLastError(), " file=", temp_file);
      return false;
   }

   datetime generated_gmt = TimeGMT();
   FileWrite(handle, "# generated_gmt=" + TdCalendarFormatGmt(generated_gmt)
      + ";build=" + TD_CALENDAR_BUILD
      + ";server_offset_seconds=" + IntegerToString(server_offset_seconds)
      + ";source_rows=" + IntegerToString(source_count)
      + ";published_rows=" + IntegerToString(ArraySize(rows))
      + ";max_relevant_gmt=" + (max_relevant_gmt > 0 ? TdCalendarFormatGmt(max_relevant_gmt) : "none"));
   FileWrite(handle, "event_gmt", "scope", "label");
   for(int i = 0; i < ArraySize(rows); ++i)
      FileWrite(handle, TdCalendarFormatGmt(rows[i].event_gmt), rows[i].scope, rows[i].label);
   FileFlush(handle);
   FileClose(handle);

   ResetLastError();
   if(FileMove(temp_file, FILE_COMMON, target_file, FILE_COMMON | FILE_REWRITE))
      return true;

   int err = GetLastError();
   FileDelete(temp_file, FILE_COMMON);
   Print("TradeDay calendar atomic promote failed err=", err, " file=", target_file);
   return false;
}

bool TdCalendarRefresh(int server_offset_seconds)
{
   datetime server_now = TimeTradeServer();
   if(server_now <= 0)
      return false;

   datetime from_server = server_now - 86400;
   datetime to_server = 0; // Zero asks MQL5 for every future event currently available.
   if(InpTdCalendarLookaheadDays > 0)
   {
      int lookahead_days = MathMax(30, MathMin(730, InpTdCalendarLookaheadDays));
      to_server = server_now + (datetime)((long)lookahead_days * 86400);
   }
   TdCalendarRow rows[];
   int source_count = 0;
   datetime max_relevant_gmt = 0;

   bool jp_ok = TdCalendarLoadCountry("JP", "JPY", from_server, to_server, server_offset_seconds,
      true, rows, source_count, max_relevant_gmt);
   bool us_ok = TdCalendarLoadCountry("US", "USD", from_server, to_server, server_offset_seconds,
      false, rows, source_count, max_relevant_gmt);

   // Never replace a valid last-known-good file with a partial API response.
   if(!jp_ok || !us_ok)
      return false;

   TdCalendarSortRows(rows);
   if(!TdCalendarWriteAtomic(InpTdCalendarFile, rows, server_offset_seconds, source_count, max_relevant_gmt))
      return false;

   Print("TradeDay calendar published build=", TD_CALENDAR_BUILD,
      " file=", InpTdCalendarFile,
      " rows=", ArraySize(rows),
      " source_rows=", source_count,
      " server_utc_offset_sec=", server_offset_seconds,
      " through_gmt=", (max_relevant_gmt > 0 ? TdCalendarFormatGmt(max_relevant_gmt) : "none"));
   return true;
}

void TradeDayCalendarPublisherTick()
{
   if(!InpTdCalendarPublisherEnabled || (bool)MQLInfoInteger(MQL_TESTER))
      return;

   datetime now_local = TimeLocal();
   if(now_local < g_tdCalendarNextAttemptLocal)
      return;

   datetime now_gmt = TimeGMT();
   int server_offset_seconds = TdCalendarServerOffsetSeconds();
   if(now_gmt <= 0 || server_offset_seconds == 999999)
   {
      g_tdCalendarNextAttemptLocal = now_local + 900;
      return;
   }

   TdCalendarLoadState();
   int utc_day = TdCalendarUtcDay(now_gmt);
   bool target_exists = FileIsExist(InpTdCalendarFile, FILE_COMMON);
   bool refresh_needed = !target_exists
      || g_tdCalendarPublishedDay != utc_day
      || g_tdCalendarPublishedOffsetSec != server_offset_seconds;
   if(!refresh_needed)
   {
      g_tdCalendarNextAttemptLocal = now_local + 60;
      return;
   }

   if(!TdCalendarAcquireLock())
   {
      g_tdCalendarNextAttemptLocal = now_local + 30;
      return;
   }

   // Another chart may have completed the same daily refresh while this chart
   // was waiting for the terminal-wide lock.
   g_tdCalendarStateLoaded = false;
   TdCalendarLoadState();
   target_exists = FileIsExist(InpTdCalendarFile, FILE_COMMON);
   refresh_needed = !target_exists
      || g_tdCalendarPublishedDay != utc_day
      || g_tdCalendarPublishedOffsetSec != server_offset_seconds;

   bool ok = true;
   if(refresh_needed)
   {
      ok = TdCalendarRefresh(server_offset_seconds);
      if(ok)
         TdCalendarSaveState(utc_day, server_offset_seconds);
   }
   TdCalendarReleaseLock();
   g_tdCalendarNextAttemptLocal = now_local + (ok ? 60 : 900);
}

#endif
