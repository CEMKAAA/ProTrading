//+------------------------------------------------------------------+
//| Atomic File Bridge MT5 Executor EA                               |
//| Reads MT4 AtomicBridge signals from Terminal Common\Files and     |
//| executes them on MT5 with duplicate guard, risk lot and audit.    |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

#define ATOMIC_FILE_BRIDGE_MT5_BUILD "2026-07-08.1515-ordercalcprofit-risk-final"

input bool   InpExecutorEnabled = true;
input string InpBridgeLatestFile = "AtomicFileBridge_Latest.csv";
input bool   InpUseCommonFiles = true;
input int    InpPollMilliseconds = 250;
input int    InpMaxSignalAgeSeconds = 900;
input bool   InpIgnoreExistingSignalOnInit = true; // Prevent attach/restart from trading the already-published Latest.csv event.
input string InpSymbolMapCsv = ""; // Explicit overrides, example: BTCUSDm=BTCUSD,USTECm=USTEC
input bool   InpUseBuiltInOilSymbolMap = true;
input string InpBuiltInOilSymbolMapCsv = "UKOILm=XBRUSD,UKOIL=XBRUSD,USOILm=XTIUSD,USOIL=XTIUSD";
input bool   InpRebaseMappedLevelsToLiveEntry = false; // OFF=use exact MT4 SL/TP/HCBE prices; ON=preserve distances from MT5 live entry.
input bool   InpRebaseOnlyWhenSourceDiffers = true;
input bool   InpRequireMappedSymbolEqualsChart = true;
input string InpSourceTimeframeFilter = ""; // Empty=all, example M5
input bool   InpDefaultSourceTfToChartPeriod = true;
input string InpSourceFilter = ""; // Empty=all, example AtomicRegime
input bool   InpCloseReverse = true;
input bool   InpCloseReverseAcrossSourceTf = false; // OFF=M1 signals cannot close/manage M5 bridge positions.
input bool   InpFailIfReverseCloseFails = true;
input bool   InpCloseReverseBridgeCommentPositions = true;
input long   InpMagic = 970102;
input int    InpDeviationPoints = 30;
input int    InpMaxSpreadPoints = 0;
input double InpManualLot = 0.10;
input bool   InpUseRiskLot = true;
input double InpRiskPerTradePct = 1.00;
input double InpMaxLot = 0.00; // 0=broker max
input bool   InpUseMarginShrinkGuard = true; // OFF=do not shrink risk lot for margin usage; broker may still reject if margin is insufficient.
input double InpMaxMarginUsagePct = 40.0;
input bool   InpFailClosedOnRiskError = true;
input bool   InpBlockIfMinLotExceedsRisk = true;
input bool   InpManageHalfCloseBe = true;
input double InpHalfCloseFraction = 0.50;
input bool   InpAuditEnabled = true;
input int    InpPollHeartbeatSeconds = 300; // Low-value health heartbeat. Signal/order/error audit remains immediate.
input string InpAuditFilePrefix = "AtomicFileBridge_MT5_Audit_";
input bool   InpShowDashboard = true;
input int    InpDashboardX = 12;
input int    InpDashboardY = 28;

CTrade trade;
string g_lastSeenEventId = "";
string g_lastRejectedEventId = "";
uint g_lastPollMs = 0;
datetime g_lastReadFailAudit = 0;
datetime g_lastPollHeartbeat = 0;
bool g_timerActive = false;
datetime g_lastDashboardDraw = 0;
datetime g_lastPollTime = 0;
string g_lastReadDetail = "";
string g_lastAction = "boot";
string g_lastActionDetail = "";
string g_lastSignalSummary = "none";
bool g_marginShrinkGuardRuntime = false;
string AFB_DASH_PREFIX = "AFB_MT5_DASH_";

struct BridgeSignal
{
   bool valid;
   string version;
   datetime writtenGmt;
   long sourceLogin;
   string sourceSymbol;
   string sourceTf;
   string eventId;
   string source;
   int direction;
   datetime signalTime;
   double bridgeEntry;
   double sl;
   double tp;
   double halfTrigger;
   string halfLabel;
   string sourceBuild;
   double sourceBid;
   double sourceAsk;
   double riskPct;
};

string Trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

bool ContainsCi(string haystack, string needle)
{
   string h = haystack;
   string n = needle;
   StringToLower(h);
   StringToLower(n);
   return StringFind(h, n) >= 0;
}

string DateKey(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
}

uint HashString(string s)
{
   uint h = 2166136261u;
   for(int i = 0; i < StringLen(s); i++)
   {
      h ^= (uint)StringGetCharacter(s, i);
      h *= 16777619u;
   }
   return h;
}

string EventKey(const string eventId)
{
   // Account-wide event lock: multiple listener charts must not execute the same bridge event twice.
   return "AtomicFileBridgeMT5|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + IntegerToString((int)HashString(eventId));
}

bool ClaimEvent(const string eventId)
{
   string key = EventKey(eventId);
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, 0.0);
   ResetLastError();
   return GlobalVariableSetOnCondition(key, (double)TimeCurrent(), 0.0);
}

void ReleaseEvent(const string eventId)
{
   string key = EventKey(eventId);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
}

string MapSymbolFromCsv(string src, string csv)
{
   string source = Trim(src);
   string sourceLower = source;
   StringToLower(sourceLower);
   StringReplace(csv, ";", ",");
   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string p = Trim(parts[i]);
      if(p == "")
         continue;
      string kv[];
      if(StringSplit(p, '=', kv) != 2)
         continue;
      string lhsLower = Trim(kv[0]);
      StringToLower(lhsLower);
      if(lhsLower == sourceLower)
         return Trim(kv[1]);
   }
   return "";
}

string MapSymbol(string src)
{
   string source = Trim(src);
   string explicitMap = MapSymbolFromCsv(source, InpSymbolMapCsv);
   if(explicitMap != "")
      return explicitMap;
   if(InpUseBuiltInOilSymbolMap)
   {
      string oilMap = MapSymbolFromCsv(source, InpBuiltInOilSymbolMapCsv);
      if(oilMap != "")
         return oilMap;
   }

   // Common broker suffix case: MT4 source XAUUSDm, MT5 chart XAUUSD.
   // Explicit mappings still win; this only strips trailing m when it exactly matches the chart symbol.
   int len = StringLen(source);
   if(len > 1)
   {
      string last = StringSubstr(source, len - 1, 1);
      if(last == "m" || last == "M")
      {
         string stripped = StringSubstr(source, 0, len - 1);
         if(SameTextCi(stripped, _Symbol))
            return _Symbol;
      }
   }
   return source;
}

bool SameTextCi(string a, string b)
{
   StringToLower(a);
   StringToLower(b);
   return a == b;
}

bool ShouldRebaseLevels(const BridgeSignal &sig)
{
   if(!InpRebaseMappedLevelsToLiveEntry)
      return false;
   if(sig.bridgeEntry <= 0.0 || sig.sl <= 0.0 || sig.tp <= 0.0)
      return false;
   string mapped = MapSymbol(sig.sourceSymbol);
   if(!SameTextCi(mapped, _Symbol))
      return false;
   if(InpRebaseOnlyWhenSourceDiffers && SameTextCi(sig.sourceSymbol, _Symbol))
      return false;
   return true;
}

void RebaseLevelsToLiveEntry(BridgeSignal &sig, double liveEntry, string &detail)
{
   detail = "";
   double srcEntry = sig.bridgeEntry;
   if(srcEntry <= 0.0 || liveEntry <= 0.0)
      return;

   double oldSl = sig.sl;
   double oldTp = sig.tp;
   double oldHalf = sig.halfTrigger;
   double risk = 0.0;
   double reward = 0.0;
   double halfDist = 0.0;

   if(sig.direction > 0)
   {
      risk = srcEntry - oldSl;
      reward = oldTp - srcEntry;
      if(risk > 0.0)
         sig.sl = liveEntry - risk;
      if(reward > 0.0)
         sig.tp = liveEntry + reward;
      if(oldHalf > 0.0)
      {
         halfDist = oldHalf - srcEntry;
         if(halfDist > 0.0)
            sig.halfTrigger = liveEntry + halfDist;
      }
   }
   else if(sig.direction < 0)
   {
      risk = oldSl - srcEntry;
      reward = srcEntry - oldTp;
      if(risk > 0.0)
         sig.sl = liveEntry + risk;
      if(reward > 0.0)
         sig.tp = liveEntry - reward;
      if(oldHalf > 0.0)
      {
         halfDist = srcEntry - oldHalf;
         if(halfDist > 0.0)
            sig.halfTrigger = liveEntry - halfDist;
      }
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sig.sl = NormalizeDouble(sig.sl, digits);
   sig.tp = NormalizeDouble(sig.tp, digits);
   if(sig.halfTrigger > 0.0)
      sig.halfTrigger = NormalizeDouble(sig.halfTrigger, digits);

   detail = "source_entry=" + DoubleToString(srcEntry, digits)
          + " live_entry=" + DoubleToString(liveEntry, digits)
          + " old_sl=" + DoubleToString(oldSl, digits)
          + " old_tp=" + DoubleToString(oldTp, digits)
          + " old_half=" + DoubleToString(oldHalf, digits)
          + " new_sl=" + DoubleToString(sig.sl, digits)
          + " new_tp=" + DoubleToString(sig.tp, digits)
          + " new_half=" + DoubleToString(sig.halfTrigger, digits)
          + " risk_dist=" + DoubleToString(risk, digits)
          + " reward_dist=" + DoubleToString(reward, digits)
          + " mapped=" + MapSymbol(sig.sourceSymbol);
}
string PriceStr(double v)
{
   if(v <= 0.0 || !MathIsValidNumber(v))
      return "-";
   return DoubleToString(v, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

void DashboardSetLabel(string name, int x, int y, string text, color clr, int fontSize=8)
{
   string obj = AFB_DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

void DashboardSetRect(string name, int x, int y, int w, int h, color bg, color border)
{
   string obj = AFB_DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

void DashboardSetButton(string name, int x, int y, int w, int h, string text, color bg, color fg)
{
   string obj = AFB_DASH_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C'90,130,170');
   ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}
void DashboardDelete()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string obj = ObjectName(0, i, 0, -1);
      if(StringFind(obj, AFB_DASH_PREFIX) == 0)
         ObjectDelete(0, obj);
   }
}

string ShortEvent(string eventId)
{
   if(StringLen(eventId) <= 42)
      return eventId;
   return StringSubstr(eventId, 0, 24) + "..." + StringSubstr(eventId, StringLen(eventId) - 14);
}

void OpenPositionStats(int &count, double &lots, double &pnl, string &lines)
{
   count = 0;
   lots = 0.0;
   pnl = 0.0;
   lines = "";
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double posPnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      lots += vol;
      pnl += posPnl;
      string dir = ((long)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL");
      if(count <= 3)
      {
         lines += "#" + IntegerToString((int)ticket) + " " + dir + " " + DoubleToString(vol, 2)
               + " open=" + PriceStr(PositionGetDouble(POSITION_PRICE_OPEN))
               + " pnl=" + DoubleToString(posPnl, 2) + "\n";
      }
   }
   if(count > 3)
      lines += "+" + IntegerToString(count - 3) + " more positions\n";
   if(lines == "")
      lines = "none";
}

void DrawDashboard(bool force=false)
{
   if(!InpShowDashboard)
   {
      DashboardDelete();
      return;
   }
   datetime now = TimeCurrent();
   if(!force && g_lastDashboardDraw > 0 && now - g_lastDashboardDraw < 1)
      return;
   g_lastDashboardDraw = now;

   int x = InpDashboardX;
   int y = InpDashboardY;
   DashboardSetRect("BG", x, y, 640, 232, C'17,24,34', C'80,160,220');
   DashboardSetRect("STRIPE", x + 8, y + 8, 624, 3, C'60,180,255', C'60,180,255');
   DashboardSetLabel("TITLE", x + 14, y + 18, "ATOMIC FILE BRIDGE MT5 LISTENER", C'230,236,245', 10);
   DashboardSetLabel("BUILD", x + 300, y + 20, ATOMIC_FILE_BRIDGE_MT5_BUILD, C'90,178,255', 7);

   color statusColor = InpExecutorEnabled ? C'80,230,150' : C'255,90,110';
   DashboardSetLabel("STATUS", x + 14, y + 42,
      "Executor=" + (InpExecutorEnabled ? "ON" : "OFF")
      + " | Timer=" + (g_timerActive ? "ON" : "OFF")
      + " | Poll=" + IntegerToString(InpPollMilliseconds) + "ms"
      + " | Audit=" + (InpAuditEnabled ? "ON" : "OFF"), statusColor, 8);

   DashboardSetLabel("FILE", x + 14, y + 60,
      "File=" + InpBridgeLatestFile + " | Common=" + (InpUseCommonFiles ? "YES" : "NO")
      + " | Chart=" + _Symbol + " | Magic=" + IntegerToString((int)InpMagic), C'190,205,220', 8);
   DashboardSetLabel("MAP", x + 14, y + 78,
      "Map=" + (InpUseBuiltInOilSymbolMap ? "builtin-oil ON" : "builtin-oil OFF") + " | " + InpBuiltInOilSymbolMapCsv, C'150,190,230', 7);

   DashboardSetLabel("LAST", x + 14, y + 96,
      "Last action=" + g_lastAction + " | " + g_lastActionDetail, C'255,204,82', 8);
   DashboardSetLabel("SIG", x + 14, y + 114,
      "Last signal=" + g_lastSignalSummary, C'190,205,220', 8);
   DashboardSetLabel("READ", x + 14, y + 132,
      "Read=" + g_lastReadDetail, C'150,165,185', 7);
   DashboardSetLabel("RISK", x + 14, y + 146,
      "Levels=" + (InpRebaseMappedLevelsToLiveEntry ? "REBASE" : "ABS")
      + " | MarginGuard=" + (g_marginShrinkGuardRuntime ? ("ON max=" + DoubleToString(InpMaxMarginUsagePct, 1) + "%") : "OFF")
      + " | RiskLot=" + (InpUseRiskLot ? "ON" : "OFF"), C'170,210,245', 7);
   DashboardSetButton("BTN_MARGIN", x + 506, y + 140, 112, 22,
      g_marginShrinkGuardRuntime ? "MG ON" : "MG OFF",
      g_marginShrinkGuardRuntime ? C'28,95,72' : C'104,44,48', C'240,245,250');

   int posCount = 0;
   double lots = 0.0;
   double pnl = 0.0;
   string posLines = "";
   OpenPositionStats(posCount, lots, pnl, posLines);
   color pnlColor = pnl >= 0.0 ? C'80,230,150' : C'255,90,110';
   DashboardSetLabel("POS", x + 14, y + 164,
      "Open AFB positions=" + IntegerToString(posCount) + " | lots=" + DoubleToString(lots, 2) + " | pnl=" + DoubleToString(pnl, 2), pnlColor, 8);
   DashboardSetLabel("POSLINES", x + 14, y + 182, posLines, C'220,226,235', 7);
}
void Audit(string eventName, const BridgeSignal &sig, string detail)
{
   g_lastAction = eventName;
   g_lastActionDetail = detail;
   g_lastSignalSummary = sig.sourceSymbol + " " + sig.sourceTf + " "
      + (sig.direction > 0 ? "BUY" : (sig.direction < 0 ? "SELL" : "-"))
      + " " + ShortEvent(sig.eventId);
   if(!InpAuditEnabled)
      return;
   int flags = FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpUseCommonFiles)
      flags |= FILE_COMMON;
   string fileName = InpAuditFilePrefix + DateKey(TimeGMT()) + ".csv";
   int h = FileOpen(fileName, flags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("AtomicFileBridgeMT5 audit open failed err=", GetLastError(), " file=", fileName);
      return;
   }
   bool header = FileSize(h) == 0;
   FileSeek(h, 0, SEEK_END);
   if(header)
      FileWrite(h, "time_gmt", "build", "event", "account", "chart_symbol", "source_symbol", "source_tf", "event_id", "source", "dir", "entry", "sl", "tp", "half", "detail");
   FileWrite(h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      ATOMIC_FILE_BRIDGE_MT5_BUILD,
      eventName,
      IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)),
      _Symbol,
      sig.sourceSymbol,
      sig.sourceTf,
      sig.eventId,
      sig.source,
      sig.direction > 0 ? "BUY" : (sig.direction < 0 ? "SELL" : "-"),
      PriceStr(sig.bridgeEntry),
      PriceStr(sig.sl),
      PriceStr(sig.tp),
      PriceStr(sig.halfTrigger),
      detail
   );
   FileClose(h);
}

void AuditRaw(string eventName, string detail)
{
   g_lastAction = eventName;
   g_lastActionDetail = detail;
   if(!InpAuditEnabled)
      return;
   int flags = FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpUseCommonFiles)
      flags |= FILE_COMMON;
   string fileName = InpAuditFilePrefix + DateKey(TimeGMT()) + ".csv";
   int h = FileOpen(fileName, flags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("AtomicFileBridgeMT5 audit raw open failed err=", GetLastError(), " file=", fileName, " detail=", detail);
      return;
   }
   bool header = FileSize(h) == 0;
   FileSeek(h, 0, SEEK_END);
   if(header)
      FileWrite(h, "time_gmt", "build", "event", "account", "chart_symbol", "source_symbol", "source_tf", "event_id", "source", "dir", "entry", "sl", "tp", "half", "detail");
   FileWrite(h,
      TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
      ATOMIC_FILE_BRIDGE_MT5_BUILD,
      eventName,
      IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)),
      _Symbol,
      "", "", "", "", "-", "-", "-", "-", "-",
      detail
   );
   FileClose(h);
}
bool ReadLatestSignal(BridgeSignal &sig, string &detail)
{
   sig.valid = false;
   detail = "";
   int flags = FILE_CSV | FILE_ANSI | FILE_READ | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpUseCommonFiles)
      flags |= FILE_COMMON;
   ResetLastError();
   int h = FileOpen(InpBridgeLatestFile, flags, ',');
   if(h == INVALID_HANDLE)
   {
      detail = "file_open_failed err=" + IntegerToString(GetLastError()) + " file=" + InpBridgeLatestFile + " common=" + (InpUseCommonFiles ? "true" : "false");
      return false;
   }

   string fields[];
   ArrayResize(fields, 0);
   while(!FileIsEnding(h))
   {
      ResetLastError();
      string v = FileReadString(h);
      int err = GetLastError();
      if(err != 0)
      {
         ResetLastError();
         if(FileIsEnding(h))
            break;
      }
      int n = ArraySize(fields);
      ArrayResize(fields, n + 1);
      fields[n] = Trim(v);
   }
   FileClose(h);

   int count = ArraySize(fields);
   if(count < 17)
   {
      detail = "not_enough_fields count=" + IntegerToString(count);
      return false;
   }
   int offset = 0;
   if(fields[0] == "version")
   {
      offset = 17;
      if(count > 17 && fields[17] == "risk_pct")
         offset = 18;
   }
   if(count < offset + 17)
   {
      detail = "not_enough_data_fields count=" + IntegerToString(count) + " offset=" + IntegerToString(offset);
      return false;
   }

   sig.version = Trim(fields[offset + 0]);
   sig.writtenGmt = StringToTime(Trim(fields[offset + 1]));
   sig.sourceLogin = (long)StringToInteger(Trim(fields[offset + 2]));
   sig.sourceSymbol = Trim(fields[offset + 3]);
   sig.sourceTf = Trim(fields[offset + 4]);
   sig.eventId = Trim(fields[offset + 5]);
   sig.source = Trim(fields[offset + 6]);
   string dir = Trim(fields[offset + 7]);
   sig.direction = dir == "BUY" ? 1 : (dir == "SELL" ? -1 : 0);
   sig.signalTime = StringToTime(Trim(fields[offset + 8]));
   sig.bridgeEntry = StringToDouble(Trim(fields[offset + 9]));
   sig.sl = StringToDouble(Trim(fields[offset + 10]));
   sig.tp = StringToDouble(Trim(fields[offset + 11]));
   sig.halfTrigger = StringToDouble(Trim(fields[offset + 12]));
   sig.halfLabel = Trim(fields[offset + 13]);
   sig.sourceBuild = Trim(fields[offset + 14]);
   sig.sourceBid = StringToDouble(Trim(fields[offset + 15]));
   sig.sourceAsk = StringToDouble(Trim(fields[offset + 16]));
   sig.riskPct = 0.0;
   if(count > offset + 17)
      sig.riskPct = StringToDouble(Trim(fields[offset + 17]));
   sig.valid = (sig.eventId != "" && sig.direction != 0);
   detail = "read_ok fields=" + IntegerToString(count) + " offset=" + IntegerToString(offset) + " event=" + sig.eventId + " source_symbol=" + sig.sourceSymbol + " source_tf=" + sig.sourceTf + " dir=" + dir + " risk_pct=" + DoubleToString(sig.riskPct, 3);
   if(!sig.valid)
   {
      bool initMarker = (sig.source == "bridge_initiated" || dir == "INIT");
      detail = (initMarker ? "bridge_init_marker " : "invalid_parsed_signal ") + detail;
   }
   return sig.valid;
}
string ChartSourceTfString()
{
   switch(_Period)
   {
      case PERIOD_M1: return "1";
      case PERIOD_M5: return "5";
      case PERIOD_M15: return "15";
      case PERIOD_M30: return "30";
      case PERIOD_H1: return "60";
      case PERIOD_H4: return "240";
      case PERIOD_D1: return "1440";
      case PERIOD_W1: return "10080";
      case PERIOD_MN1: return "43200";
   }
   return IntegerToString((int)_Period);
}

int SourceTfToInt(string tf);

bool SameSourceTf(string lhs, string rhs)
{
   string a = Trim(lhs);
   string b = Trim(rhs);
   int ai = SourceTfToInt(a);
   int bi = SourceTfToInt(b);
   if(ai > 0 && bi > 0)
      return ai == bi;
   return SameTextCi(a, b);
}
bool SignalIdentityMatchesThisChart(const BridgeSignal &sig, string &reason)
{
   reason = "";
   if(!sig.valid)
   {
      reason = "invalid_signal";
      return false;
   }
   string effectiveTfFilter = Trim(InpSourceTimeframeFilter);
   if(effectiveTfFilter == "" && InpDefaultSourceTfToChartPeriod)
      effectiveTfFilter = ChartSourceTfString();
   if(effectiveTfFilter != "" && !SameSourceTf(sig.sourceTf, effectiveTfFilter))
   {
      reason = "tf_filter source_tf=" + sig.sourceTf + " expected=" + effectiveTfFilter + " source_tf_i=" + IntegerToString(SourceTfToInt(sig.sourceTf)) + " expected_i=" + IntegerToString(SourceTfToInt(effectiveTfFilter));
      return false;
   }
   if(InpSourceFilter != "" && !ContainsCi(sig.source, InpSourceFilter))
   {
      reason = "source_filter source=" + sig.source;
      return false;
   }
   string mapped = MapSymbol(sig.sourceSymbol);
   if(InpRequireMappedSymbolEqualsChart && mapped != _Symbol)
   {
      reason = "symbol_filter source=" + sig.sourceSymbol + " mapped=" + mapped + " chart=" + _Symbol;
      return false;
   }
   return true;
}

bool SignalAcceptedForThisChart(const BridgeSignal &sig, string &reason)
{
   if(!SignalIdentityMatchesThisChart(sig, reason))
      return false;
   if(InpMaxSignalAgeSeconds > 0 && sig.writtenGmt > 0)
   {
      int age = (int)(TimeGMT() - sig.writtenGmt);
      if(age > InpMaxSignalAgeSeconds)
      {
         reason = "stale age=" + IntegerToString(age);
         return false;
      }
   }
   return true;
}

bool StopsValid(const int direction, double entry, double sl, double tp, string &reason)
{
   reason = "";
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = MathMax(point * 2.0, (double)stopLevel * point);
   if(entry <= 0.0 || sl <= 0.0 || tp <= 0.0)
   {
      reason = "missing_entry_sl_tp";
      return false;
   }
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   if(direction > 0)
   {
      if(!(sl < entry && tp > entry))
      {
         reason = "bad_buy_geometry";
         return false;
      }
      if(entry - sl < minStop || tp - entry < minStop)
      {
         reason = "buy_stop_level min=" + DoubleToString(minStop, digits);
         return false;
      }
   }
   else
   {
      if(!(sl > entry && tp < entry))
      {
         reason = "bad_sell_geometry";
         return false;
      }
      if(sl - entry < minStop || entry - tp < minStop)
      {
         reason = "sell_stop_level min=" + DoubleToString(minStop, digits);
         return false;
      }
   }
   return true;
}

string StopContext(double entry, double sl, double tp)
{
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double spreadPts = point > 0.0 ? (tick.ask - tick.bid) / point : 0.0;
   return " live_bid=" + PriceStr(tick.bid)
        + " live_ask=" + PriceStr(tick.ask)
        + " entry=" + PriceStr(entry)
        + " sl_dist=" + DoubleToString(MathAbs(entry - sl), _Digits)
        + " tp_dist=" + DoubleToString(MathAbs(entry - tp), _Digits)
        + " spread_pts=" + DoubleToString(spreadPts, 1)
        + " stop_level_pts=" + IntegerToString((int)stopLevel)
        + " freeze_level_pts=" + IntegerToString((int)freezeLevel);
}

bool PermanentOrderFailure(long retcode)
{
   return (retcode == 10016  // TRADE_RETCODE_INVALID_STOPS
        || retcode == 10014  // TRADE_RETCODE_INVALID_VOLUME
        || retcode == 10015  // TRADE_RETCODE_INVALID_PRICE
        || retcode == 10030);// TRADE_RETCODE_INVALID_FILL
}

bool SpreadAllowed(string &reason)
{
   reason = "";
   if(InpMaxSpreadPoints <= 0)
      return true;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      reason = "no_tick";
      return false;
   }
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int spread = point > 0.0 ? (int)MathRound((tick.ask - tick.bid) / point) : 0;
   if(spread > InpMaxSpreadPoints)
   {
      reason = "spread=" + IntegerToString(spread) + " max=" + IntegerToString(InpMaxSpreadPoints);
      return false;
   }
   return true;
}

int VolumeDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   for(int d = 0; d <= 8; d++)
   {
      if(MathAbs(step - NormalizeDouble(step, d)) < 0.000000001)
         return d;
   }
   return 2;
}

double NormalizeVolume(double lot)
{
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(InpMaxLot > 0.0)
      maxVol = MathMin(maxVol, InpMaxLot);
   if(step <= 0.0)
      step = 0.01;
   double v = MathFloor(lot / step) * step;
   v = MathMax(minVol, MathMin(maxVol, v));
   return NormalizeDouble(v, VolumeDigits());
}

double NormalizeVolumeDown(double lot)
{
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(InpMaxLot > 0.0)
      maxVol = MathMin(maxVol, InpMaxLot);
   if(step <= 0.0)
      step = 0.01;
   double v = MathFloor(lot / step) * step;
   if(v < minVol - 0.000000001)
      return 0.0;
   v = MathMin(maxVol, v);
   return NormalizeDouble(v, VolumeDigits());
}

bool ProjectedMarginPctForLot(const int direction, double lot, double entry, double &projectedPct, double &orderMargin)
{
   projectedPct = 0.0;
   orderMargin = 0.0;
   if(lot <= 0.0 || entry <= 0.0)
      return false;
   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(type, _Symbol, lot, entry, orderMargin))
      return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return false;
   projectedPct = (AccountInfoDouble(ACCOUNT_MARGIN) + orderMargin) * 100.0 / equity;
   return true;
}

double ShrinkLotToMarginLimit(const int direction, double requestedLot, double entry, double maxMarginPct, string &detail)
{
   detail = "";
   if(maxMarginPct <= 0.0)
      return requestedLot;

   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   double minPct = 0.0;
   double minMargin = 0.0;
   if(!ProjectedMarginPctForLot(direction, minVol, entry, minPct, minMargin))
   {
      detail = "margin_calc_failed_min_lot min_lot=" + DoubleToString(minVol, 2);
      return 0.0;
   }
   if(minPct > maxMarginPct)
   {
      detail = "min_lot_margin_exceeds_limit min_lot=" + DoubleToString(minVol, 2)
             + " projected_margin_pct=" + DoubleToString(minPct, 2)
             + " max_margin_pct=" + DoubleToString(maxMarginPct, 2);
      return 0.0;
   }

   double reqPct = 0.0;
   double reqMargin = 0.0;
   if(ProjectedMarginPctForLot(direction, requestedLot, entry, reqPct, reqMargin) && reqPct <= maxMarginPct)
      return requestedLot;

   double lo = minVol;
   double hi = requestedLot;
   double best = minVol;
   for(int i = 0; i < 32; i++)
   {
      double mid = (lo + hi) * 0.5;
      double candidate = NormalizeVolume(mid);
      if(candidate < minVol)
         candidate = minVol;
      double pct = 0.0;
      double margin = 0.0;
      if(!ProjectedMarginPctForLot(direction, candidate, entry, pct, margin))
      {
         hi = mid;
         continue;
      }
      if(pct <= maxMarginPct)
      {
         best = candidate;
         lo = mid;
      }
      else
      {
         hi = mid;
      }
   }

   best = NormalizeVolume(best);
   double bestPct = 0.0;
   double bestMargin = 0.0;
   while(best >= minVol && ProjectedMarginPctForLot(direction, best, entry, bestPct, bestMargin) && bestPct > maxMarginPct)
      best = NormalizeDouble(best - step, 2);

   if(best < minVol)
   {
      detail = "margin_shrink_no_valid_lot requested_lot=" + DoubleToString(requestedLot, 2)
             + " max_margin_pct=" + DoubleToString(maxMarginPct, 2);
      return 0.0;
   }

   ProjectedMarginPctForLot(direction, best, entry, bestPct, bestMargin);
   detail = "margin_shrink requested_lot=" + DoubleToString(requestedLot, 2)
          + " shrunk_lot=" + DoubleToString(best, 2)
          + " projected_margin_pct=" + DoubleToString(bestPct, 2)
          + " max_margin_pct=" + DoubleToString(maxMarginPct, 2);
   return best;
}
double ShrinkLotToFreeMargin(const int direction, double requestedLot, double entry, string &detail)
{
   detail = "";
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0)
   {
      detail = "free_margin_unavailable free_margin=" + DoubleToString(freeMargin, 2);
      return 0.0;
   }

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double minMargin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, minVol, entry, minMargin))
   {
      detail = "free_margin_calc_failed_min_lot min_lot=" + DoubleToString(minVol, 2);
      return 0.0;
   }
   double safeFree = freeMargin * 0.98;
   if(minMargin > safeFree)
   {
      detail = "min_lot_exceeds_free_margin min_lot=" + DoubleToString(minVol, 2)
             + " min_margin=" + DoubleToString(minMargin, 2)
             + " free_margin=" + DoubleToString(freeMargin, 2);
      return 0.0;
   }

   double reqMargin = 0.0;
   if(OrderCalcMargin(type, _Symbol, requestedLot, entry, reqMargin) && reqMargin <= safeFree)
   {
      detail = "free_margin_retry_no_shrink requested_lot=" + DoubleToString(requestedLot, 2)
             + " required_margin=" + DoubleToString(reqMargin, 2)
             + " free_margin=" + DoubleToString(freeMargin, 2);
      return requestedLot;
   }

   double lo = minVol;
   double hi = requestedLot;
   double best = minVol;
   for(int i = 0; i < 32; i++)
   {
      double mid = (lo + hi) * 0.5;
      double candidate = NormalizeVolumeDown(mid);
      if(candidate < minVol)
         candidate = minVol;
      double margin = 0.0;
      if(!OrderCalcMargin(type, _Symbol, candidate, entry, margin))
      {
         hi = mid;
         continue;
      }
      if(margin <= safeFree)
      {
         best = candidate;
         lo = mid;
      }
      else hi = mid;
   }

   best = NormalizeVolumeDown(best);
   double bestMargin = 0.0;
   while(best >= minVol && OrderCalcMargin(type, _Symbol, best, entry, bestMargin) && bestMargin > safeFree)
      best = NormalizeDouble(best - step, VolumeDigits());

   if(best < minVol)
   {
      detail = "free_margin_retry_no_valid_lot requested_lot=" + DoubleToString(requestedLot, 2)
             + " free_margin=" + DoubleToString(freeMargin, 2);
      return 0.0;
   }
   if(!OrderCalcMargin(type, _Symbol, best, entry, bestMargin))
   {
      detail = "free_margin_retry_final_margin_calc_failed requested_lot=" + DoubleToString(requestedLot, 2)
             + " shrunk_lot=" + DoubleToString(best, 2);
      return 0.0;
   }
   detail = "free_margin_retry requested_lot=" + DoubleToString(requestedLot, 2)
          + " shrunk_lot=" + DoubleToString(best, 2)
          + " required_margin=" + DoubleToString(bestMargin, 2)
          + " free_margin=" + DoubleToString(freeMargin, 2);
   return best;
}
double MoneyRiskPerLotByOrderCalc(const int direction, double entry, double sl, string &detail)
{
   detail = "";
   double riskDist = MathAbs(entry - sl);
   if(riskDist <= 0.0)
   {
      detail = "risk_dist_invalid risk_dist=" + DoubleToString(riskDist, _Digits);
      return 0.0;
   }

   ENUM_ORDER_TYPE type = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double profit = 0.0;
   ResetLastError();
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, profit))
   {
      int err = GetLastError();
      detail = "order_calc_profit_failed err=" + IntegerToString(err)
             + " entry=" + DoubleToString(entry, _Digits)
             + " sl=" + DoubleToString(sl, _Digits);
      return 0.0;
   }

   double moneyPerLot = MathAbs(profit);
   if(moneyPerLot <= 0.0)
   {
      detail = "order_calc_profit_zero profit=" + DoubleToString(profit, 2)
             + " entry=" + DoubleToString(entry, _Digits)
             + " sl=" + DoubleToString(sl, _Digits);
      return 0.0;
   }
   detail = "ordercalc_profit_1lot=" + DoubleToString(profit, 2);
   return moneyPerLot;
}
double ResolveLot(const BridgeSignal &sig, double entry, string &detail)
{
   detail = "manual_lot";
   if(!InpUseRiskLot)
      return NormalizeVolume(InpManualLot);
   double riskDist = MathAbs(entry - sig.sl);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(riskDist <= 0.0)
   {
      detail = "risk_lot_unavailable riskDist=" + DoubleToString(riskDist, _Digits);
      return InpFailClosedOnRiskError ? 0.0 : NormalizeVolume(InpManualLot);
   }
   double effectiveRiskPct = (sig.riskPct > 0.0 ? sig.riskPct : InpRiskPerTradePct);
   double budget = AccountInfoDouble(ACCOUNT_EQUITY) * MathMax(0.0, effectiveRiskPct) / 100.0;
   string riskCalcDetail = "";
   double moneyPerLot = MoneyRiskPerLotByOrderCalc(sig.direction, entry, sig.sl, riskCalcDetail);
   if(moneyPerLot <= 0.0)
   {
      detail = "money_per_lot_invalid " + riskCalcDetail;
      return InpFailClosedOnRiskError ? 0.0 : NormalizeVolume(InpManualLot);
   }
   double rawLot = budget / moneyPerLot;
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(InpBlockIfMinLotExceedsRisk && minVol > 0.0)
   {
      double minLotRisk = minVol * moneyPerLot;
      if(rawLot < minVol && minLotRisk > budget * 1.001)
      {
         detail = "min_lot_exceeds_risk budget=" + DoubleToString(budget, 2)
                + " risk_dist=" + DoubleToString(riskDist, _Digits)
                + " money_per_lot=" + DoubleToString(moneyPerLot, 2)
                + " raw_lot=" + DoubleToString(rawLot, 4)
                + " min_lot=" + DoubleToString(minVol, 2)
                + " min_lot_risk=" + DoubleToString(minLotRisk, 2);
         return 0.0;
      }
   }
   double lot = NormalizeVolume(rawLot);
   string marginDetail = "";
   double actualRisk = lot * moneyPerLot;
   if(InpBlockIfMinLotExceedsRisk && actualRisk > budget * 1.001)
   {
      detail = "normalized_lot_exceeds_risk budget=" + DoubleToString(budget, 2)
             + " risk_dist=" + DoubleToString(riskDist, _Digits)
             + " money_per_lot=" + DoubleToString(moneyPerLot, 2)
             + " raw_lot=" + DoubleToString(rawLot, 4)
             + " lot=" + DoubleToString(lot, 2)
             + " actual_risk=" + DoubleToString(actualRisk, 2) + (marginDetail != "" ? " " + marginDetail : "");
      return 0.0;
   }
   if(g_marginShrinkGuardRuntime && InpMaxMarginUsagePct > 0.0)
   {
      double requestedLot = lot;
      lot = ShrinkLotToMarginLimit(sig.direction, lot, entry, InpMaxMarginUsagePct, marginDetail);
      if(lot <= 0.0)
      {
         detail = marginDetail;
         return 0.0;
      }
      if(lot < requestedLot - 0.0000001)
         actualRisk = lot * moneyPerLot;
   }

   detail = "risk_lot symbol=" + _Symbol
          + " risk_pct=" + DoubleToString(effectiveRiskPct, 3) + (sig.riskPct > 0.0 ? " source=bridge" : " source=local") + " budget=" + DoubleToString(budget, 2)
          + " risk_calc=ordercalcprofit"
          + " " + riskCalcDetail
          + " tick_size=" + DoubleToString(tickSize, _Digits)
          + " tick_value=" + DoubleToString(tickValue, 4)
          + " vol_min=" + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 2)
          + " vol_step=" + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 2)
          + " risk_dist=" + DoubleToString(riskDist, _Digits)
          + " money_per_lot=" + DoubleToString(moneyPerLot, 2)
          + " raw_lot=" + DoubleToString(rawLot, 4)
          + " lot=" + DoubleToString(lot, 2)
          + " actual_risk=" + DoubleToString(actualRisk, 2) + (marginDetail != "" ? " " + marginDetail : "");
   return lot;
}

bool IsManagedBridgePosition()
{
   long magic = (long)PositionGetInteger(POSITION_MAGIC);
   if(magic == InpMagic)
      return true;
   if(InpCloseReverseBridgeCommentPositions)
   {
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "AFB|") == 0)
         return true;
   }
   return false;
}


string BridgePosKey(ulong ticket, string kind)
{
   return "AtomicFileBridgeMT5|POS|" + IntegerToString((int)InpMagic) + "|" + IntegerToString((int)ticket) + "|" + kind;
}

int SourceTfToInt(string tf)
{
   string clean = Trim(tf);
   if(clean == "")
      return 0;

   string upper = clean;
   StringToUpper(upper);
   StringReplace(upper, "PERIOD_", "");
   StringReplace(upper, "TIMEFRAME_", "");
   StringReplace(upper, "MIN", "M");

   if(upper == "M1" || upper == "1") return 1;
   if(upper == "M2" || upper == "2") return 2;
   if(upper == "M3" || upper == "3") return 3;
   if(upper == "M4" || upper == "4") return 4;
   if(upper == "M5" || upper == "5") return 5;
   if(upper == "M6" || upper == "6") return 6;
   if(upper == "M10" || upper == "10") return 10;
   if(upper == "M12" || upper == "12") return 12;
   if(upper == "M15" || upper == "15") return 15;
   if(upper == "M20" || upper == "20") return 20;
   if(upper == "M30" || upper == "30") return 30;
   if(upper == "H1" || upper == "60") return 60;
   if(upper == "H2" || upper == "120") return 120;
   if(upper == "H3" || upper == "180") return 180;
   if(upper == "H4" || upper == "240") return 240;
   if(upper == "H6" || upper == "360") return 360;
   if(upper == "H8" || upper == "480") return 480;
   if(upper == "H12" || upper == "720") return 720;
   if(upper == "D1" || upper == "1440") return 1440;
   if(upper == "W1" || upper == "10080") return 10080;
   if(upper == "MN1" || upper == "43200") return 43200;

   return (int)StringToInteger(clean);
}

int PositionSourceTfFromComment()
{
   string comment = PositionGetString(POSITION_COMMENT);
   if(StringFind(comment, "AFB|T") != 0)
      return 0;
   int start = 5;
   int stop = StringFind(comment, "|", start);
   if(stop <= start)
      return 0;
   return SourceTfToInt(StringSubstr(comment, start, stop - start));
}

int PositionSourceTf(ulong ticket)
{
   string key = BridgePosKey(ticket, "STF");
   if(GlobalVariableCheck(key))
      return (int)MathRound(GlobalVariableGet(key));
   return PositionSourceTfFromComment();
}

bool ReverseScopeAllows(ulong ticket, const BridgeSignal &sig, string &detail)
{
   if(InpCloseReverseAcrossSourceTf)
   {
      detail = "reverse_scope=all_source_tf";
      return true;
   }
   int sigTf = SourceTfToInt(sig.sourceTf);
   int posTf = PositionSourceTf(ticket);
   detail = "reverse_scope=same_source_tf signal_tf=" + IntegerToString(sigTf) + " position_tf=" + IntegerToString(posTf);
   if(sigTf <= 0 || posTf <= 0)
      return true;
   return sigTf == posTf;
}
bool IsCloseOnlySignal(const BridgeSignal &sig)
{
   return (StringFind(sig.source, "CloseOnly") >= 0 || StringFind(sig.eventId, "invalidate_close") >= 0);
}

bool CloseSameDirectionPositions(const BridgeSignal &sig, string &detail)
{
   int found = 0;
   int closed = 0;
   int failed = 0;
   string errors = "";
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!IsManagedBridgePosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      bool sameDirection = (sig.direction > 0 && type == POSITION_TYPE_BUY) || (sig.direction < 0 && type == POSITION_TYPE_SELL);
      if(!sameDirection)
         continue;
      found++;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      string dir = (type == POSITION_TYPE_BUY ? "BUY" : "SELL");
      ResetLastError();
      bool ok = trade.PositionClose(ticket);
      long ret = trade.ResultRetcode();
      if(ok)
      {
         closed++;
         Audit("close_only_sent", sig, "ticket=" + IntegerToString((int)ticket) + " dir=" + dir + " vol=" + DoubleToString(vol, 2) + " pnl=" + DoubleToString(pnl, 2) + " retcode=" + IntegerToString((int)ret));
      }
      else
      {
         failed++;
         int err = GetLastError();
         string e = "ticket=" + IntegerToString((int)ticket) + " dir=" + dir + " vol=" + DoubleToString(vol, 2) + " retcode=" + IntegerToString((int)ret) + " err=" + IntegerToString(err);
         errors += (errors == "" ? "" : "; ") + e;
         Audit("close_only_failed", sig, e);
      }
   }
   detail = "close_only_found=" + IntegerToString(found) + " closed=" + IntegerToString(closed) + " failed=" + IntegerToString(failed);
   if(errors != "")
      detail += " errors=" + errors;
   if(found == 0)
      Audit("close_only_none", sig, detail);
   return failed == 0;
}
bool CloseReversePositions(const BridgeSignal &sig, string &detail)
{
   if(!InpCloseReverse)
   {
      detail = "reverse_close_disabled";
      return true;
   }
   int found = 0;
   int closed = 0;
   int failed = 0;
   string errors = "";
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(!IsManagedBridgePosition())
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      bool opposite = (sig.direction > 0 && type == POSITION_TYPE_SELL) || (sig.direction < 0 && type == POSITION_TYPE_BUY);
      if(opposite)
      {
         string scopeDetail = "";
         if(!ReverseScopeAllows(ticket, sig, scopeDetail))
         {
            Audit("reverse_close_skip_scope", sig, "ticket=" + IntegerToString((int)ticket) + " " + scopeDetail);
            continue;
         }
         found++;
         double vol = PositionGetDouble(POSITION_VOLUME);
         double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         string dir = (type == POSITION_TYPE_BUY ? "BUY" : "SELL");
         ResetLastError();
         bool ok = trade.PositionClose(ticket);
         long ret = trade.ResultRetcode();
         if(ok)
         {
            closed++;
            Audit("reverse_close_sent", sig, "ticket=" + IntegerToString((int)ticket) + " dir=" + dir + " vol=" + DoubleToString(vol, 2) + " pnl=" + DoubleToString(pnl, 2) + " retcode=" + IntegerToString((int)ret));
         }
         else
         {
            failed++;
            int err = GetLastError();
            string e = "ticket=" + IntegerToString((int)ticket) + " dir=" + dir + " vol=" + DoubleToString(vol, 2) + " retcode=" + IntegerToString((int)ret) + " err=" + IntegerToString(err);
            errors += (errors == "" ? "" : "; ") + e;
            Audit("reverse_close_failed", sig, e);
         }
      }
   }
   detail = "reverse_found=" + IntegerToString(found) + " closed=" + IntegerToString(closed) + " failed=" + IntegerToString(failed);
   if(errors != "")
      detail += " errors=" + errors;
   if(found == 0)
      Audit("reverse_close_none", sig, detail);
   return failed == 0;
}

string PosKey(ulong ticket, string kind)
{
   return BridgePosKey(ticket, kind);
}

ulong FindOpenedPositionTicket(const BridgeSignal &sig, string comment)
{
   ulong bestTicket = 0;
   long bestTimeMsc = -1;
   long expectedType = (sig.direction > 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_TYPE) != expectedType)
         continue;

      string posComment = PositionGetString(POSITION_COMMENT);
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(posComment != comment && magic != InpMagic)
         continue;

      long timeMsc = (long)PositionGetInteger(POSITION_TIME_MSC);
      if(timeMsc >= bestTimeMsc)
      {
         bestTimeMsc = timeMsc;
         bestTicket = ticket;
      }
   }
   return bestTicket;
}

void RepairLegacyPositionMetadata(const BridgeSignal &sig)
{
   int sourceTf = SourceTfToInt(sig.sourceTf);
   if(sourceTf <= 0)
      return;

   string eventHash = IntegerToString((int)HashString(sig.eventId));
   string legacyComment = "AFB|" + eventHash;
   string modernComment = "AFB|T" + sig.sourceTf + "|" + eventHash;
   long expectedType = (sig.direction > 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_TYPE) != expectedType)
         continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(comment != legacyComment && comment != modernComment)
         continue;

      string key = PosKey(ticket, "STF");
      bool repaired = false;
      if(!GlobalVariableCheck(key) || (int)MathRound(GlobalVariableGet(key)) != sourceTf)
      {
         GlobalVariableSet(key, sourceTf);
         repaired = true;
      }

      string hcKey = PosKey(ticket, "HC");
      if(InpManageHalfCloseBe && sig.halfTrigger > 0.0 && !GlobalVariableCheck(hcKey))
      {
         GlobalVariableSet(hcKey, sig.halfTrigger);
         GlobalVariableSet(PosKey(ticket, "DONE"), 0.0);
         GlobalVariableSet(PosKey(ticket, "ENTRY"), PositionGetDouble(POSITION_PRICE_OPEN));
         repaired = true;
      }

      if(repaired)
      {
         Audit("position_state_repaired", sig,
            "ticket=" + IntegerToString((int)ticket)
            + " source_tf=" + IntegerToString(sourceTf)
            + " hc=" + PriceStr(sig.halfTrigger)
            + " entry=" + PriceStr(PositionGetDouble(POSITION_PRICE_OPEN))
            + " comment=" + comment);
      }
   }
}
void StoreHalfState(ulong ticket, const BridgeSignal &sig, double fill)
{
   if(ticket == 0)
      return;

   int sourceTf = SourceTfToInt(sig.sourceTf);
   if(sourceTf > 0)
      GlobalVariableSet(PosKey(ticket, "STF"), sourceTf);
   GlobalVariableSet(PosKey(ticket, "ENTRY"), fill);

   if(sig.halfTrigger <= 0.0 || !InpManageHalfCloseBe)
      return;
   GlobalVariableSet(PosKey(ticket, "HC"), sig.halfTrigger);
   GlobalVariableSet(PosKey(ticket, "DONE"), 0.0);
}

void ManageHalfCloseBe()
{
   if(!InpManageHalfCloseBe)
      return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   BridgeSignal auditSig;
   auditSig.valid = true;
   auditSig.version = "";
   auditSig.writtenGmt = 0;
   auditSig.sourceLogin = 0;
   auditSig.sourceSymbol = _Symbol;
   auditSig.sourceTf = InpSourceTimeframeFilter;
   auditSig.eventId = "halfbe_runtime";
   auditSig.source = "AtomicFileBridgeMT5";
   auditSig.signalTime = 0;
   auditSig.bridgeEntry = 0.0;
   auditSig.sl = 0.0;
   auditSig.tp = 0.0;
   auditSig.halfTrigger = 0.0;
   auditSig.halfLabel = "";
   auditSig.sourceBuild = ATOMIC_FILE_BRIDGE_MT5_BUILD;
   auditSig.sourceBid = tick.bid;
   auditSig.sourceAsk = tick.ask;
   auditSig.riskPct = InpRiskPerTradePct;

   string managerTfStr = Trim(InpSourceTimeframeFilter);
   if(managerTfStr == "" && InpDefaultSourceTfToChartPeriod)
      managerTfStr = ChartSourceTfString();
   int managerTf = SourceTfToInt(managerTfStr);
   auditSig.sourceTf = managerTfStr;

   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      int posTf = PositionSourceTf(ticket);
      if(managerTf > 0 && posTf > 0 && managerTf != posTf)
         continue;
      string hcKey = PosKey(ticket, "HC");
      if(!GlobalVariableCheck(hcKey) || GlobalVariableGet(PosKey(ticket, "DONE")) > 0.5)
         continue;
      double hc = GlobalVariableGet(hcKey);
      double entry = GlobalVariableCheck(PosKey(ticket, "ENTRY")) ? GlobalVariableGet(PosKey(ticket, "ENTRY")) : PositionGetDouble(POSITION_PRICE_OPEN);
      long type = PositionGetInteger(POSITION_TYPE);
      bool hit = (type == POSITION_TYPE_BUY) ? (tick.bid >= hc) : (tick.ask <= hc);
      if(!hit)
         continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double desiredClose = vol * MathMax(0.0, MathMin(1.0, InpHalfCloseFraction));
      double closeVol = NormalizeVolumeDown(desiredClose);
      double remainingVol = NormalizeDouble(vol - closeVol, VolumeDigits());
      if(closeVol <= 0.0 || closeVol >= vol || remainingVol < minVol - 0.000000001)
      {
         double maxClosable = NormalizeVolumeDown(vol - minVol);
         if(maxClosable > 0.0 && maxClosable < vol)
         {
            closeVol = maxClosable;
            remainingVol = NormalizeDouble(vol - closeVol, VolumeDigits());
         }
      }

      auditSig.direction = (type == POSITION_TYPE_BUY ? 1 : -1);
      auditSig.bridgeEntry = entry;
      auditSig.halfTrigger = hc;
      auditSig.sl = PositionGetDouble(POSITION_SL);
      auditSig.tp = PositionGetDouble(POSITION_TP);

      double triggerPx = (type == POSITION_TYPE_BUY ? tick.bid : tick.ask);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double riskDist = MathAbs(entry - sl);
      double hcDist = MathAbs(hc - entry);
      double expectedFullRiskMoney = 0.0;
      double expectedHalfPnlAtHc = 0.0;
      double hcR = 0.0;
      double projectedPnl = 0.0;
      if(tickSize > 0.0 && tickValue > 0.0 && closeVol > 0.0)
      {
         double signedMove = (type == POSITION_TYPE_BUY ? triggerPx - entry : entry - triggerPx);
         projectedPnl = signedMove / tickSize * tickValue * closeVol;
         if(riskDist > 0.0)
         {
            hcR = hcDist / riskDist;
            expectedFullRiskMoney = riskDist / tickSize * tickValue * vol;
            expectedHalfPnlAtHc = hcDist / tickSize * tickValue * closeVol;
         }
      }

      string baseDetail = "ticket=" + IntegerToString((int)ticket)
         + " type=" + (type == POSITION_TYPE_BUY ? "BUY" : "SELL")
         + " entry=" + PriceStr(entry)
         + " hc=" + PriceStr(hc)
         + " trigger_px=" + PriceStr(triggerPx)
         + " vol=" + DoubleToString(vol, VolumeDigits())
         + " desired_close=" + DoubleToString(desiredClose, VolumeDigits())
         + " close_vol=" + DoubleToString(closeVol, VolumeDigits())
         + " remaining_vol=" + DoubleToString(remainingVol, VolumeDigits())
         + " min_vol=" + DoubleToString(minVol, VolumeDigits())
         + " step=" + DoubleToString(step, VolumeDigits())
         + " fraction=" + DoubleToString(InpHalfCloseFraction, 2)
         + " sl=" + PriceStr(sl)
         + " tp=" + PriceStr(tp)
         + " risk_dist=" + DoubleToString(riskDist, _Digits)
         + " hc_dist=" + DoubleToString(hcDist, _Digits)
         + " hc_r=" + DoubleToString(hcR, 3)
         + " tick_size=" + DoubleToString(tickSize, _Digits)
         + " tick_value=" + DoubleToString(tickValue, 4)
         + " expected_full_risk_money=" + DoubleToString(expectedFullRiskMoney, 2)
         + " expected_half_pnl_at_hc=" + DoubleToString(expectedHalfPnlAtHc, 2)
         + " projected_pnl=" + DoubleToString(projectedPnl, 2);

      if(closeVol <= 0.0 || closeVol >= vol || remainingVol < minVol - 0.000000001)
      {
         Audit("halfbe_blocked_volume", auditSig, baseDetail + " reason=partial_close_impossible_for_broker_volume");
         continue;
      }

      string doneKey = PosKey(ticket, "DONE");
      if(!GlobalVariableSetOnCondition(doneKey, 2.0, 0.0))
      {
         Audit("halfbe_skip_lock_taken", auditSig, baseDetail + " done=" + (GlobalVariableCheck(doneKey) ? DoubleToString(GlobalVariableGet(doneKey), 1) : "missing"));
         continue;
      }
      ResetLastError();
      bool partialOk = trade.PositionClosePartial(ticket, closeVol);
      long partialRet = trade.ResultRetcode();
      int partialErr = GetLastError();
      string partialDetail = baseDetail
         + " partial_ok=" + (partialOk ? "true" : "false")
         + " partial_retcode=" + IntegerToString((int)partialRet)
         + " partial_err=" + IntegerToString(partialErr)
         + " partial_deal=" + IntegerToString((int)trade.ResultDeal())
         + " partial_order=" + IntegerToString((int)trade.ResultOrder())
         + " partial_comment=" + trade.ResultComment();

      if(!partialOk)
      {
         GlobalVariableSet(PosKey(ticket, "DONE"), 0.0);
         Audit("halfbe_partial_close_failed", auditSig, partialDetail);
         continue;
      }

      bool stillOpen = PositionSelectByTicket(ticket);
      if(!stillOpen)
      {
         GlobalVariableSet(PosKey(ticket, "DONE"), 1.0);
         Audit("halfbe_partial_close_success_position_closed", auditSig, partialDetail);
         continue;
      }

      double currentTp = PositionGetDouble(POSITION_TP);
      ResetLastError();
      bool modifyOk = trade.PositionModify(ticket, NormalizeDouble(entry, _Digits), currentTp);
      long modifyRet = trade.ResultRetcode();
      int modifyErr = GetLastError();
      string modifyDetail = partialDetail
         + " modify_ok=" + (modifyOk ? "true" : "false")
         + " modify_retcode=" + IntegerToString((int)modifyRet)
         + " modify_err=" + IntegerToString(modifyErr)
         + " be_sl=" + PriceStr(NormalizeDouble(entry, _Digits))
         + " remaining_after=" + DoubleToString(PositionGetDouble(POSITION_VOLUME), VolumeDigits());

      if(!modifyOk)
      {
         GlobalVariableSet(PosKey(ticket, "DONE"), 1.0);
         Audit("halfbe_sl_to_be_failed_after_partial", auditSig, modifyDetail + " half_done_locked_after_partial=1");
         continue;
      }

      GlobalVariableSet(PosKey(ticket, "DONE"), 1.0);
      Audit("halfbe_done", auditSig, modifyDetail);
   }
}

bool ExecuteSignal(const BridgeSignal &sourceSig)
{
   BridgeSignal sig = sourceSig;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Audit("skip_no_tick", sig, "");
      return false;
   }
   string reason = "";
   if(!SpreadAllowed(reason))
   {
      Audit("skip_spread", sig, reason);
      return false;
   }
   double entry = sig.direction > 0 ? tick.ask : tick.bid;
   string rebaseDetail = "";
   if(ShouldRebaseLevels(sig))
   {
      RebaseLevelsToLiveEntry(sig, entry, rebaseDetail);
      if(rebaseDetail != "")
         Audit("levels_rebased", sig, rebaseDetail);
   }
   if(!StopsValid(sig.direction, entry, sig.sl, sig.tp, reason))
   {
      g_lastRejectedEventId = sig.eventId;
      Audit("skip_geometry", sig, reason + StopContext(entry, sig.sl, sig.tp));
      return false;
   }
   if(!ClaimEvent(sig.eventId))
   {
      string duplicateReverseDetail = "";
      CloseReversePositions(sig, duplicateReverseDetail);
      Audit("skip_duplicate", sig, "event_global_claim_exists " + duplicateReverseDetail);
      return true;
   }
   string reverseDetail = "";
   if(!CloseReversePositions(sig, reverseDetail))
   {
      ReleaseEvent(sig.eventId);
      Audit("skip_reverse_close_failed", sig, reverseDetail);
      if(InpFailIfReverseCloseFails)
         return false;
   }
   string lotDetail = "";
   double lot = ResolveLot(sig, entry, lotDetail);
   if(lot <= 0.0)
   {
      g_lastRejectedEventId = sig.eventId;
      ReleaseEvent(sig.eventId);
      Audit("skip_lot", sig, lotDetail);
      return false;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   string comment = "AFB|T" + sig.sourceTf + "|" + IntegerToString((int)HashString(sig.eventId));
   bool ok = sig.direction > 0
      ? trade.Buy(lot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), NormalizeDouble(sig.tp, _Digits), comment)
      : trade.Sell(lot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), NormalizeDouble(sig.tp, _Digits), comment);
   if(!ok)
   {
      long ret = trade.ResultRetcode();
      int err = GetLastError();
      if(ret == 10019) // TRADE_RETCODE_NO_MONEY
      {
         string retryDetail = "";
         double retryLot = ShrinkLotToFreeMargin(sig.direction, lot, entry, retryDetail);
         if(retryLot > 0.0 && retryLot < lot - 0.000000001)
         {
            ResetLastError();
            bool retryOk = sig.direction > 0
               ? trade.Buy(retryLot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), NormalizeDouble(sig.tp, _Digits), comment)
               : trade.Sell(retryLot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), NormalizeDouble(sig.tp, _Digits), comment);
            long retryRet = trade.ResultRetcode();
            int retryErr = GetLastError();
            if(retryOk)
            {
               ulong retryDeal = trade.ResultDeal();
               ulong retryOrder = trade.ResultOrder();
               ulong retryPosTicket = FindOpenedPositionTicket(sig, comment);
               StoreHalfState(retryPosTicket, sig, entry);
               Audit("order_sent_no_money_retry", sig,
                     "original_retcode=" + IntegerToString((int)ret)
                     + " original_err=" + IntegerToString(err)
                     + " original_lot=" + DoubleToString(lot, 2)
                     + " retry_lot=" + DoubleToString(retryLot, 2)
                     + " live_entry=" + PriceStr(entry)
                     + " deal=" + IntegerToString((int)retryDeal)
                     + " order=" + IntegerToString((int)retryOrder)
                     + " pos=" + IntegerToString((int)retryPosTicket)
                     + (rebaseDetail != "" ? " rebase=" + rebaseDetail : "")
                     + " " + retryDetail + " " + lotDetail);
               return true;
            }
            Audit("order_failed_no_money_retry", sig,
                  "original_retcode=" + IntegerToString((int)ret)
                  + " original_err=" + IntegerToString(err)
                  + " retry_retcode=" + IntegerToString((int)retryRet)
                  + " retry_err=" + IntegerToString(retryErr)
                  + " original_lot=" + DoubleToString(lot, 2)
                  + " retry_lot=" + DoubleToString(retryLot, 2)
                  + StopContext(entry, sig.sl, sig.tp)
                  + " " + retryDetail + " " + lotDetail);
         }
         else
         {
            Audit("order_failed_no_money_no_retry_lot", sig,
                  "retcode=" + IntegerToString((int)ret)
                  + " err=" + IntegerToString(err)
                  + " original_lot=" + DoubleToString(lot, 2)
                  + StopContext(entry, sig.sl, sig.tp)
                  + " " + retryDetail + " " + lotDetail);
         }
      }
      ReleaseEvent(sig.eventId);
      string permanent = PermanentOrderFailure(ret) ? " permanent_reject=1" : " permanent_reject=0";
      if(PermanentOrderFailure(ret))
         g_lastRejectedEventId = sig.eventId;
      Audit("order_failed", sig, "retcode=" + IntegerToString((int)ret) + " err=" + IntegerToString(err) + permanent + StopContext(entry, sig.sl, sig.tp) + " " + lotDetail);
      return false;
   }
   ulong deal = trade.ResultDeal();
   ulong order = trade.ResultOrder();
   ulong posTicket = FindOpenedPositionTicket(sig, comment);
   StoreHalfState(posTicket, sig, entry);
   Audit("order_sent", sig, "lot=" + DoubleToString(lot, 2) + " live_entry=" + PriceStr(entry) + " deal=" + IntegerToString((int)deal) + " order=" + IntegerToString((int)order) + " pos=" + IntegerToString((int)posTicket) + (rebaseDetail != "" ? " rebase=" + rebaseDetail : "") + " " + lotDetail);
   return true;
}

void PollBridge(string caller)
{
   BridgeSignal sig;
   string readDetail = "";
   g_lastPollTime = TimeGMT();
   if(!ReadLatestSignal(sig, readDetail))
   {
      g_lastReadDetail = readDetail;
      datetime now = TimeGMT();
      bool initMarker = (StringFind(readDetail, "bridge_init_marker") >= 0 || StringFind(readDetail, "source=bridge_initiated") >= 0 || StringFind(readDetail, "dir=INIT") >= 0);
      int failAuditSeconds = initMarker ? 60 : 10;
      if(g_lastReadFailAudit == 0 || now - g_lastReadFailAudit >= failAuditSeconds)
      {
         g_lastReadFailAudit = now;
         if(initMarker)
         {
            AuditRaw("bridge_initiated_seen", "caller=" + caller + " " + readDetail);
            Print("AtomicFileBridgeMT5 bridge_initiated_seen caller=", caller, " ", readDetail);
         }
         else
         {
            AuditRaw("read_failed", "caller=" + caller + " " + readDetail);
            Print("AtomicFileBridgeMT5 read_failed caller=", caller, " ", readDetail);
         }
      }
      return;
   }
   g_lastReadDetail = readDetail;

   datetime hbNow = TimeGMT();
   if(g_lastPollHeartbeat == 0 || hbNow - g_lastPollHeartbeat >= MathMax(30, InpPollHeartbeatSeconds))
   {
      g_lastPollHeartbeat = hbNow;
      AuditRaw("poll_heartbeat", "caller=" + caller + " " + readDetail + " last_seen=" + g_lastSeenEventId);
   }

   string identityReason = "";
   if(SignalIdentityMatchesThisChart(sig, identityReason))
      RepairLegacyPositionMetadata(sig);

   if(sig.eventId == g_lastSeenEventId || sig.eventId == g_lastRejectedEventId)
      return;

   string reason = "";
   if(!SignalAcceptedForThisChart(sig, reason))
   {
      g_lastRejectedEventId = sig.eventId;
      Audit("skip_filter", sig, "caller=" + caller + " " + reason + " " + readDetail);
      return;
   }
   Audit("signal_received", sig, "caller=" + caller + " mapped_symbol=" + MapSymbol(sig.sourceSymbol) + " " + readDetail);
   if(!InpExecutorEnabled)
   {
      g_lastSeenEventId = sig.eventId;
      Audit("skip_disabled", sig, "executor_off caller=" + caller);
      return;
   }
   if(IsCloseOnlySignal(sig))
   {
      string closeOnlyDetail = "";
      if(CloseSameDirectionPositions(sig, closeOnlyDetail))
         g_lastSeenEventId = sig.eventId;
      Audit("close_only_processed", sig, "caller=" + caller + " " + closeOnlyDetail);
      return;
   }
   if(ExecuteSignal(sig))
      g_lastSeenEventId = sig.eventId;
}

void PollBridge()
{
   PollBridge("legacy");
}
void BaselineExistingSignalOnInit()
{
   if(!InpIgnoreExistingSignalOnInit)
      return;

   BridgeSignal sig;
   string readDetail = "";
   if(!ReadLatestSignal(sig, readDetail))
   {
      AuditRaw("init_baseline_empty", readDetail);
      return;
   }

   string identityReason = "";
   if(!SignalIdentityMatchesThisChart(sig, identityReason))
   {
      Audit("init_baseline_ignored", sig, "identity_mismatch " + identityReason + " " + readDetail);
      return;
   }

   g_lastSeenEventId = sig.eventId;
   g_lastReadDetail = readDetail;
   Audit("init_baseline_existing_signal", sig, "seeded_last_seen=1 no_trade_on_attach " + readDetail);
}

int OnInit()
{
      g_marginShrinkGuardRuntime = InpUseMarginShrinkGuard;
trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   ResetLastError();
   g_timerActive = EventSetMillisecondTimer(MathMax(100, InpPollMilliseconds));
   int timerErr = GetLastError();
   if(!g_timerActive)
   {
      ResetLastError();
      g_timerActive = EventSetTimer(1);
      timerErr = GetLastError();
   }
   Print("AtomicFileBridge MT5 Executor BUILD=", ATOMIC_FILE_BRIDGE_MT5_BUILD,
         " file=", InpBridgeLatestFile,
         " common=", (InpUseCommonFiles ? "true" : "false"),
         " chart=", _Symbol,
         " map=", InpSymbolMapCsv,
         " builtinOilMap=", (InpUseBuiltInOilSymbolMap ? InpBuiltInOilSymbolMapCsv : "OFF"),
         " magic=", InpMagic,
         " timer=", (g_timerActive ? "true" : "false"),
         " timer_err=", timerErr,
         " poll_ms=", InpPollMilliseconds);
   AuditRaw("init", "file=" + InpBridgeLatestFile + " common=" + (InpUseCommonFiles ? "true" : "false") + " map=" + InpSymbolMapCsv + " builtin_oil_map=" + (InpUseBuiltInOilSymbolMap ? InpBuiltInOilSymbolMapCsv : "OFF") + " timer=" + (g_timerActive ? "true" : "false") + " timer_err=" + IntegerToString(timerErr) + " poll_ms=" + IntegerToString(InpPollMilliseconds) + " ignore_existing_on_init=" + (InpIgnoreExistingSignalOnInit ? "true" : "false"));
   BaselineExistingSignalOnInit();
   DrawDashboard(true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   AuditRaw("deinit", "reason=" + IntegerToString(reason));
   EventKillTimer();
   DashboardDelete();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(sparam == AFB_DASH_PREFIX + "BTN_MARGIN")
   {
      g_marginShrinkGuardRuntime = !g_marginShrinkGuardRuntime;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      AuditRaw("dashboard_margin_guard_toggle", "margin_guard=" + (g_marginShrinkGuardRuntime ? "ON" : "OFF") + " max_margin_pct=" + DoubleToString(InpMaxMarginUsagePct, 1));
      DrawDashboard(true);
      ChartRedraw(0);
   }
}
void OnTimer()
{
   PollBridge("timer");
   DrawDashboard();
}

void OnTick()
{
   ManageHalfCloseBe();
   uint now = GetTickCount();
   if(now - g_lastPollMs >= (uint)MathMax(100, InpPollMilliseconds))
   {
      g_lastPollMs = now;
      PollBridge("tick");
   }
   DrawDashboard();
}

