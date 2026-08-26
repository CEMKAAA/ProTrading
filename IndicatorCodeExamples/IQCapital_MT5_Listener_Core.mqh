// Shared IQ Capital MT5 executor core. The thin .mq5 wrappers define
// pipeline-specific file, source, timeframe, magic and audit defaults.
#ifndef IQC_LISTENER_BUILD
   #error "IQC_LISTENER_BUILD must be defined by the wrapper EA"
#endif
#ifndef IQC_PIPELINE_ID
   #error "IQC_PIPELINE_ID must be defined by the wrapper EA"
#endif
#ifndef IQC_DEFAULT_FILE
   #error "IQC_DEFAULT_FILE must be defined by the wrapper EA"
#endif
#ifndef IQC_DEFAULT_SOURCE_FILTER
   #error "IQC_DEFAULT_SOURCE_FILTER must be defined by the wrapper EA"
#endif
#ifndef IQC_DEFAULT_SOURCE_TF
   #error "IQC_DEFAULT_SOURCE_TF must be defined by the wrapper EA"
#endif
#ifndef IQC_DEFAULT_MAGIC
   #error "IQC_DEFAULT_MAGIC must be defined by the wrapper EA"
#endif
#ifndef IQC_DEFAULT_RISK_PCT
   #error "IQC_DEFAULT_RISK_PCT must be defined by the wrapper EA"
#endif
#ifndef IQC_DEFAULT_AUDIT_PREFIX
   #error "IQC_DEFAULT_AUDIT_PREFIX must be defined by the wrapper EA"
#endif
#ifndef IQC_DASH_PREFIX
   #error "IQC_DASH_PREFIX must be defined by the wrapper EA"
#endif
#ifndef IQC_DEFAULT_PREFER_SCOPED_LATEST
   #define IQC_DEFAULT_PREFER_SCOPED_LATEST false
#endif
#ifndef IQC_DEFAULT_FAIL_IF_SCOPED_MISSING
   #define IQC_DEFAULT_FAIL_IF_SCOPED_MISSING false
#endif
#ifndef IQC_DEFAULT_SOURCE_SYMBOL_ALIASES
   #define IQC_DEFAULT_SOURCE_SYMBOL_ALIASES ""
#endif


#include <Trade/Trade.mqh>

#define ATOMIC_FILE_BRIDGE_MT5_BUILD IQC_LISTENER_BUILD

input bool   InpExecutorEnabled = true;
input string InpBridgeLatestFile = IQC_DEFAULT_FILE;
input bool   InpUseCommonFiles = true;
input bool   InpPreferScopedLatest = IQC_DEFAULT_PREFER_SCOPED_LATEST;
input bool   InpFailIfScopedLatestMissing = IQC_DEFAULT_FAIL_IF_SCOPED_MISSING;
input string InpSourceSymbolAliasesCsv = IQC_DEFAULT_SOURCE_SYMBOL_ALIASES; // Optional source-side aliases; auto aliases are also derived from the chart and symbol map.
input int    InpPollMilliseconds = 250;
input int    InpMaxSignalAgeSeconds = 900;
input bool   InpIgnoreExistingSignalOnInit = true; // Prevent attach/restart from trading the already-published Latest.csv event.
input long   InpSourceLoginFilter = 260460316; // DEMOMT5 source account. 0 disables this fail-closed identity guard.
input string InpSymbolMapCsv = "JP225m=JPN225,JP225=JPN225,JPN225m=JPN225,JPN225=JPN225,DE30m=GER40,DE30=GER40,GER30m=GER40,GER30=GER40,GER40m=GER40,GER40=GER40,DAX40m=GER40,DAX40=GER40";
input bool   InpUseBuiltInOilSymbolMap = false;
input string InpBuiltInOilSymbolMapCsv = "UKOILm=XBRUSD,UKOIL=XBRUSD,USOILm=XTIUSD,USOIL=XTIUSD";
input bool   InpRebaseMappedLevelsToLiveEntry = true; // Preserve source distances around the IQ Capital fill.
input bool   InpRebaseOnlyWhenSourceDiffers = true;
input bool   InpRequireMappedSymbolEqualsChart = true;
input string InpSourceTimeframeFilter = IQC_DEFAULT_SOURCE_TF;
input bool   InpDefaultSourceTfToChartPeriod = false;
input string InpSourceFilter = IQC_DEFAULT_SOURCE_FILTER;
input bool   InpCloseReverse = true;
input bool   InpCloseReverseAcrossSourceTf = false; // OFF=M1 signals cannot close M5 positions from the bridge.
input bool   InpFailIfReverseCloseFails = true;
input bool   InpCloseReverseBridgeCommentPositions = false;
input bool   InpRequireHedgingAccount = true; // Multiple same-symbol pipelines are unsafe on a netting account.
input string InpDestinationServerFilter = "BeyondIQCapital"; // Empty disables the destination-server guard.
input long   InpMagic = IQC_DEFAULT_MAGIC;
input int    InpDeviationPoints = 30;
input int    InpMaxSpreadPoints = 0;
input double InpManualLot = 0.10;
input bool   InpUseRiskLot = true;
input double InpRiskPerTradePct = IQC_DEFAULT_RISK_PCT;
input bool   InpUseBridgeRiskBasis = true;
input bool   InpForceFixedReferenceRisk = false;
input double InpFixedRiskReferenceCapital = 0.0;
input double InpFixedRiskMaxOvershootMoney = 1.0;
input double InpMaxLot = 0.00; // 0=broker max
input bool   InpUseMarginShrinkGuard = true; // OFF=do not shrink risk lot for margin usage; broker may still reject if margin is insufficient.
input double InpMaxMarginUsagePct = 40.0;
input bool   InpFailClosedOnRiskError = true;
input bool   InpPostFillRiskGuard = true;
input bool   InpBlockIfMinLotExceedsRisk = true;
input bool   InpManageHalfCloseBe = true;
input bool   InpFailIfExactProtectionFails = true;
input int    InpProtectionRetrySeconds = 2;
input double InpHalfCloseFraction = 0.50;
input bool   InpAuditEnabled = true;
input int    InpPollHeartbeatSeconds = 300; // Low-value health heartbeat. Signal/order/error audit remains immediate.
input string InpAuditFilePrefix = IQC_DEFAULT_AUDIT_PREFIX;
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
string g_lastBridgeReadFile = "";
string g_lastAction = "boot";
string g_lastActionDetail = "";
string g_lastSignalSummary = "none";
bool g_marginShrinkGuardRuntime = false;
string AFB_DASH_PREFIX = IQC_DASH_PREFIX;

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
   string riskBasis;
   double riskReferenceCapital;
   double riskBudgetMoney;
   string tradeMode;
   double basketTargetPips;
   double basketTargetPct;
   double basketMaxLossPips;
   double basketCatastrophicSlPips;
   bool basketCloseOnReverse;
   bool basketCloseSessionEnd;
   string basketSessionEndTime;
   string basketDayKey;
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
   return IQC_PIPELINE_ID + "|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + IntegerToString((int)HashString(eventId));
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
   DashboardSetLabel("TITLE", x + 14, y + 18, IQC_PIPELINE_ID + " MT5 LISTENER", C'230,236,245', 10);
   DashboardSetLabel("BUILD", x + 300, y + 20, ATOMIC_FILE_BRIDGE_MT5_BUILD, C'90,178,255', 7);

   color statusColor = InpExecutorEnabled ? C'80,230,150' : C'255,90,110';
   DashboardSetLabel("STATUS", x + 14, y + 42,
      "Executor=" + (InpExecutorEnabled ? "ON" : "OFF")
      + " | Timer=" + (g_timerActive ? "ON" : "OFF")
      + " | Poll=" + IntegerToString(InpPollMilliseconds) + "ms"
      + " | Audit=" + (InpAuditEnabled ? "ON" : "OFF"), statusColor, 8);

   DashboardSetLabel("FILE", x + 14, y + 60,
      "File=" + (g_lastBridgeReadFile != "" ? g_lastBridgeReadFile : InpBridgeLatestFile) + " | Common=" + (InpUseCommonFiles ? "YES" : "NO")
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
      Print("IQC_PIPELINE_ID audit open failed err=", GetLastError(), " file=", fileName);
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
      Print("IQC_PIPELINE_ID audit raw open failed err=", GetLastError(), " file=", fileName, " detail=", detail);
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
bool ReadSignalFile(const string fileName, BridgeSignal &sig, string &detail)
{
   sig.valid = false;
   detail = "";
   int flags = FILE_CSV | FILE_ANSI | FILE_READ | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpUseCommonFiles)
      flags |= FILE_COMMON;
   ResetLastError();
   int h = FileOpen(fileName, flags, ',');
   if(h == INVALID_HANDLE)
   {
      detail = "file_open_failed err=" + IntegerToString(GetLastError()) + " file=" + fileName + " common=" + (InpUseCommonFiles ? "true" : "false");
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
   bool headerHasTradeMode = false;
   bool headerHasChannel = false;
   if(fields[0] == "version")
   {
      offset = 17;
      if(count > 18 && fields[18] == "trade_mode")
      {
         headerHasTradeMode = true;
         offset = 27;
      }
      else if(count > 17 && fields[17] == "risk_pct")
         offset = 18;
      if(!headerHasTradeMode && count > 18 && fields[18] == "bridge_channel")
      {
         headerHasChannel = true;
         offset = 19;
      }
      if(headerHasChannel && count > 19 && fields[19] == "risk_basis") offset = 22;
      else if(!headerHasTradeMode && !headerHasChannel && count > 18 && fields[18] == "risk_basis") offset = 21;
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
   sig.riskBasis = "";
   sig.riskReferenceCapital = 0.0;
   sig.riskBudgetMoney = 0.0;
   sig.tradeMode = "traditional";
   sig.basketTargetPips = 0.0;
   sig.basketTargetPct = 0.0;
   sig.basketMaxLossPips = 0.0;
   sig.basketCatastrophicSlPips = 0.0;
   sig.basketCloseOnReverse = true;
   sig.basketCloseSessionEnd = false;
   sig.basketSessionEndTime = "";
   sig.basketDayKey = "";
   if(count > offset + 17)
      sig.riskPct = StringToDouble(Trim(fields[offset + 17]));
   if(headerHasTradeMode && count > offset + 18)
      sig.tradeMode = Trim(fields[offset + 18]);
   if(headerHasTradeMode && count > offset + 19)
      sig.basketTargetPips = StringToDouble(Trim(fields[offset + 19]));
   if(headerHasTradeMode && count > offset + 20)
      sig.basketTargetPct = StringToDouble(Trim(fields[offset + 20]));
   if(headerHasTradeMode && count > offset + 21)
      sig.basketMaxLossPips = StringToDouble(Trim(fields[offset + 21]));
   if(headerHasTradeMode && count > offset + 22)
      sig.basketCatastrophicSlPips = StringToDouble(Trim(fields[offset + 22]));
   if(headerHasTradeMode && count > offset + 23)
      sig.basketCloseOnReverse = SameTextCi(Trim(fields[offset + 23]), "true") || Trim(fields[offset + 23]) == "1";
   if(headerHasTradeMode && count > offset + 24)
      sig.basketCloseSessionEnd = SameTextCi(Trim(fields[offset + 24]), "true") || Trim(fields[offset + 24]) == "1";
   if(headerHasTradeMode && count > offset + 25)
      sig.basketSessionEndTime = Trim(fields[offset + 25]);
   if(headerHasTradeMode && count > offset + 26)
      sig.basketDayKey = Trim(fields[offset + 26]);
   if(!headerHasTradeMode)
   {
      int riskMetaIndex = offset + (headerHasChannel ? 19 : 18);
      if(count > riskMetaIndex) sig.riskBasis = Trim(fields[riskMetaIndex]);
      if(count > riskMetaIndex + 1) sig.riskReferenceCapital = StringToDouble(Trim(fields[riskMetaIndex + 1]));
      if(count > riskMetaIndex + 2) sig.riskBudgetMoney = StringToDouble(Trim(fields[riskMetaIndex + 2]));
   }
   if(sig.tradeMode == "") sig.tradeMode = "traditional";
   sig.valid = (sig.eventId != "" && sig.direction != 0);
   detail = "read_ok file=" + fileName + " fields=" + IntegerToString(count) + " offset=" + IntegerToString(offset) + " event=" + sig.eventId + " source_symbol=" + sig.sourceSymbol + " source_tf=" + sig.sourceTf + " dir=" + dir + " risk_pct=" + DoubleToString(sig.riskPct, 3) + " trade_mode=" + sig.tradeMode;
   if(!sig.valid)
   {
      bool initMarker = (sig.source == "bridge_initiated" || dir == "INIT");
      detail = (initMarker ? "bridge_init_marker " : "invalid_parsed_signal ") + detail;
   }
   return sig.valid;
}

void AddUniqueToken(string &items[], string value)
{
   value = Trim(value);
   if(value == "") return;
   for(int i = 0; i < ArraySize(items); i++)
      if(SameTextCi(items[i], value)) return;
   int n = ArraySize(items);
   ArrayResize(items, n + 1);
   items[n] = value;
}

string SafeFileToken(string value)
{
   value = Trim(value);
   StringReplace(value, "\\", "_");
   StringReplace(value, "/", "_");
   StringReplace(value, ":", "_");
   StringReplace(value, "*", "_");
   StringReplace(value, "?", "_");
   StringReplace(value, "\"", "_");
   StringReplace(value, "<", "_");
   StringReplace(value, ">", "_");
   StringReplace(value, "|", "_");
   StringReplace(value, " ", "_");
   return value;
}

void AddCsvTokens(const string csvValue, string &items[])
{
   string csv = csvValue;
   StringReplace(csv, ";", ",");
   string parts[];
   int count = StringSplit(csv, ',', parts);
   for(int i = 0; i < count; i++) AddUniqueToken(items, parts[i]);
}

void AddReverseMappedAliases(string csv, const string destinationSymbol, string &items[])
{
   StringReplace(csv, ";", ",");
   string parts[];
   int count = StringSplit(csv, ',', parts);
   for(int i = 0; i < count; i++)
   {
      string kv[];
      if(StringSplit(Trim(parts[i]), '=', kv) != 2) continue;
      if(SameTextCi(Trim(kv[1]), destinationSymbol)) AddUniqueToken(items, Trim(kv[0]));
   }
}

bool IsGenericLatestFile(const string fileName)
{
   string lower = fileName;
   StringToLower(lower);
   string suffix = "_latest.csv";
   int start = StringLen(lower) - StringLen(suffix);
   return start >= 0 && StringSubstr(lower, start) == suffix;
}

string ScopedLatestName(const string genericFile, const string sourceAlias, const string sourceTf)
{
   int len = StringLen(genericFile);
   string stem = genericFile;
   if(len >= 4)
   {
      string extension = StringSubstr(genericFile, len - 4);
      StringToLower(extension);
      if(extension == ".csv") stem = StringSubstr(genericFile, 0, len - 4);
   }
   return stem + "_" + SafeFileToken(sourceAlias) + "_" + SafeFileToken(sourceTf) + ".csv";
}

void CollectScopedSourceAliases(string &aliases[])
{
   ArrayResize(aliases, 0);
   AddCsvTokens(InpSourceSymbolAliasesCsv, aliases);
   AddUniqueToken(aliases, _Symbol);

   int symbolLen = StringLen(_Symbol);
   if(symbolLen > 1)
   {
      string tail = StringSubstr(_Symbol, symbolLen - 1, 1);
      if(tail == "m" || tail == "M") AddUniqueToken(aliases, StringSubstr(_Symbol, 0, symbolLen - 1));
      else AddUniqueToken(aliases, _Symbol + "m");
   }
   AddReverseMappedAliases(InpSymbolMapCsv, _Symbol, aliases);
   if(InpUseBuiltInOilSymbolMap) AddReverseMappedAliases(InpBuiltInOilSymbolMapCsv, _Symbol, aliases);
}

bool ReadLatestSignal(BridgeSignal &sig, string &detail)
{
   g_lastBridgeReadFile = "";
   if(!InpPreferScopedLatest || !IsGenericLatestFile(InpBridgeLatestFile))
   {
      bool directOk = ReadSignalFile(InpBridgeLatestFile, sig, detail);
      if(directOk) g_lastBridgeReadFile = InpBridgeLatestFile;
      return directOk;
   }

   string sourceTf = Trim(InpSourceTimeframeFilter);
   if(sourceTf == "" && InpDefaultSourceTfToChartPeriod) sourceTf = ChartSourceTfString();
   if(sourceTf == "")
   {
      detail = "scoped_latest_requires_source_tf file=" + InpBridgeLatestFile;
      return false;
   }

   string aliases[];
   CollectScopedSourceAliases(aliases);
   bool found = false;
   bool markerFound = false;
   datetime newestWritten = 0;
   datetime newestMarkerWritten = 0;
   BridgeSignal markerSig;
   string markerDetail = "";
   string markerFile = "";
   string attempts = "";
   for(int i = 0; i < ArraySize(aliases); i++)
   {
      string candidate = ScopedLatestName(InpBridgeLatestFile, aliases[i], sourceTf);
      BridgeSignal candidateSig;
      string candidateDetail = "";
      if(!ReadSignalFile(candidate, candidateSig, candidateDetail))
      {
         bool initMarker = StringFind(candidateDetail, "bridge_init_marker") >= 0;
         string markerIdentityReason = "";
         if(initMarker && SignalMetadataMatchesThisChart(candidateSig, markerIdentityReason))
         {
            if(!markerFound || candidateSig.writtenGmt > newestMarkerWritten)
            {
               markerFound = true;
               newestMarkerWritten = candidateSig.writtenGmt;
               markerSig = candidateSig;
               markerDetail = candidateDetail;
               markerFile = candidate;
            }
            continue;
         }
         if(StringLen(attempts) < 260) attempts += (attempts == "" ? "" : ";") + candidate;
         continue;
      }
      string identityReason = "";
      if(!SignalIdentityMatchesThisChart(candidateSig, identityReason))
      {
         if(StringLen(attempts) < 260) attempts += (attempts == "" ? "" : ";") + candidate + "[" + identityReason + "]";
         continue;
      }
      if(!found || candidateSig.writtenGmt > newestWritten)
      {
         found = true;
         newestWritten = candidateSig.writtenGmt;
         sig = candidateSig;
         detail = candidateDetail + " scoped=true";
         g_lastBridgeReadFile = candidate;
      }
   }
   if(found) return true;
   if(markerFound)
   {
      sig = markerSig;
      detail = markerDetail + " scoped=true";
      g_lastBridgeReadFile = markerFile;
      return false;
   }

   if(InpFailIfScopedLatestMissing)
   {
      detail = "scoped_latest_not_found base=" + InpBridgeLatestFile + " tf=" + sourceTf + " tried=" + attempts;
      return false;
   }

   bool fallbackOk = ReadSignalFile(InpBridgeLatestFile, sig, detail);
   detail += " scoped_fallback=true";
   if(fallbackOk) g_lastBridgeReadFile = InpBridgeLatestFile;
   return fallbackOk;
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

bool SignalMetadataMatchesThisChart(const BridgeSignal &sig, string &reason)
{
   reason = "";
   if(InpSourceLoginFilter > 0 && sig.sourceLogin != InpSourceLoginFilter)
   {
      reason = "source_login_filter source=" + IntegerToString((int)sig.sourceLogin) + " expected=" + IntegerToString((int)InpSourceLoginFilter);
      return false;
   }
   string effectiveTfFilter = Trim(InpSourceTimeframeFilter);
   if(effectiveTfFilter == "" && InpDefaultSourceTfToChartPeriod)
      effectiveTfFilter = ChartSourceTfString();
   if(effectiveTfFilter != "" && sig.sourceTf != effectiveTfFilter)
   {
      reason = "tf_filter source_tf=" + sig.sourceTf + " expected=" + effectiveTfFilter;
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

bool SignalIdentityMatchesThisChart(const BridgeSignal &sig, string &reason)
{
   if(!sig.valid)
   {
      reason = "invalid_signal";
      return false;
   }
   return SignalMetadataMatchesThisChart(sig, reason);
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

bool TradeCallAccepted(bool callOk)
{
   if(!callOk) return false;
   long ret = trade.ResultRetcode();
   return ret == TRADE_RETCODE_DONE
       || ret == TRADE_RETCODE_DONE_PARTIAL
       || ret == TRADE_RETCODE_PLACED
       || ret == TRADE_RETCODE_NO_CHANGES;
}

bool ProtectionMatches(ulong ticket, double expectedSl, double expectedTp, string &detail)
{
   detail = "";
   if(ticket == 0 || !PositionSelectByTicket(ticket))
   {
      detail = "position_not_found ticket=" + IntegerToString((int)ticket);
      return false;
   }
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0) tickSize = point;
   double tolerance = MathMax(point * 0.1, tickSize * 0.51);
   double actualSl = PositionGetDouble(POSITION_SL);
   double actualTp = PositionGetDouble(POSITION_TP);
   bool slOk = expectedSl <= 0.0 ? actualSl <= tolerance : MathAbs(actualSl - expectedSl) <= tolerance;
   bool tpOk = expectedTp <= 0.0 ? actualTp <= tolerance : MathAbs(actualTp - expectedTp) <= tolerance;
   detail = "ticket=" + IntegerToString((int)ticket)
      + " expected_sl=" + PriceStr(expectedSl) + " actual_sl=" + PriceStr(actualSl)
      + " expected_tp=" + PriceStr(expectedTp) + " actual_tp=" + PriceStr(actualTp)
      + " tolerance=" + DoubleToString(tolerance, _Digits);
   return slOk && tpOk;
}

void ClearProtectionFailureState(ulong ticket)
{
   GlobalVariableDel(PosKey(ticket, "PFAIL"));
   GlobalVariableDel(PosKey(ticket, "PSL"));
   GlobalVariableDel(PosKey(ticket, "PTP"));
   GlobalVariableDel(PosKey(ticket, "PNEXT"));
}

bool EnsureExactProtection(ulong ticket, const BridgeSignal &sig, string &detail)
{
   detail = "";
   if(ticket == 0)
   {
      detail = "post_fill_position_ticket_missing";
      return false;
   }
   double expectedSl = NormalizeDouble(sig.sl, _Digits);
   double expectedTp = NormalizeDouble(sig.tp, _Digits);
   string verify = "";
   if(ProtectionMatches(ticket, expectedSl, expectedTp, verify))
   {
      detail = "verified_initial " + verify;
      return true;
   }

   ResetLastError();
   bool modifyCall = trade.PositionModify(ticket, expectedSl, expectedTp);
   bool modifyOk = TradeCallAccepted(modifyCall);
   long modifyRet = trade.ResultRetcode();
   int modifyErr = GetLastError();
   string afterModify = "";
   if(modifyOk && ProtectionMatches(ticket, expectedSl, expectedTp, afterModify))
   {
      detail = "repaired " + afterModify + " ret=" + IntegerToString((int)modifyRet);
      return true;
   }

   detail = "protection_failed initial=" + verify
      + " modify_ok=" + (modifyOk ? "true" : "false")
      + " modify_ret=" + IntegerToString((int)modifyRet)
      + " modify_err=" + IntegerToString(modifyErr)
      + " after=" + afterModify;
   if(!InpFailIfExactProtectionFails)
      return true;

   GlobalVariableSet(PosKey(ticket, "PFAIL"), 1.0);
   GlobalVariableSet(PosKey(ticket, "PSL"), expectedSl);
   GlobalVariableSet(PosKey(ticket, "PTP"), expectedTp);
   GlobalVariableSet(PosKey(ticket, "PNEXT"), 0.0);

   ResetLastError();
   bool closeCall = trade.PositionClose(ticket);
   bool closeOk = TradeCallAccepted(closeCall);
   detail += " emergency_close_ok=" + (closeOk ? "true" : "false")
      + " close_ret=" + IntegerToString((int)trade.ResultRetcode())
      + " close_err=" + IntegerToString(GetLastError());
   if(closeOk || !PositionSelectByTicket(ticket))
      ClearProtectionFailureState(ticket);
   return false;
}

void ManageProtectionFailures()
{
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(!GlobalVariableCheck(PosKey(ticket, "PFAIL"))) continue;
      datetime nextTry = (datetime)GlobalVariableGet(PosKey(ticket, "PNEXT"));
      if(nextTry > now) continue;
      double expectedSl = GlobalVariableGet(PosKey(ticket, "PSL"));
      double expectedTp = GlobalVariableGet(PosKey(ticket, "PTP"));
      string verify = "";
      ResetLastError();
      bool modifyCall = trade.PositionModify(ticket, expectedSl, expectedTp);
      bool repaired = TradeCallAccepted(modifyCall) && ProtectionMatches(ticket, expectedSl, expectedTp, verify);
      if(repaired)
      {
         AuditRaw("protection_retry_repaired", verify);
         ClearProtectionFailureState(ticket);
         continue;
      }
      ResetLastError();
      bool closeCall = trade.PositionClose(ticket);
      bool closeOk = TradeCallAccepted(closeCall);
      string d = "ticket=" + IntegerToString((int)ticket)
         + " modify_ret=" + IntegerToString((int)trade.ResultRetcode())
         + " close_ok=" + (closeOk ? "true" : "false")
         + " verify=" + verify;
      if(closeOk || !PositionSelectByTicket(ticket))
      {
         AuditRaw("protection_retry_closed", d);
         ClearProtectionFailureState(ticket);
      }
      else
      {
         GlobalVariableSet(PosKey(ticket, "PNEXT"), (double)(now + MathMax(1, InpProtectionRetrySeconds)));
         AuditRaw("protection_retry_pending", d);
      }
   }
}
bool PermanentOrderFailure(long retcode)
{
   return (retcode == 10016  // TRADE_RETCODE_INVALID_STOPS
        || retcode == 10014  // TRADE_RETCODE_INVALID_VOLUME
        || retcode == 10015  // TRADE_RETCODE_INVALID_PRICE
        || retcode == 10018  // TRADE_RETCODE_MARKET_CLOSED; consume stale signal, do not retry spam.
        || retcode == 10017  // TRADE_RETCODE_TRADE_DISABLED
        || retcode == 10019  // TRADE_RETCODE_NO_MONEY
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

bool ResolveRiskBudget(const BridgeSignal &sig, double &riskPct, double &capital, double &budget, bool &fixedReference, string &detail)
{
   riskPct = sig.riskPct > 0.0 ? sig.riskPct : InpRiskPerTradePct;
   fixedReference = InpForceFixedReferenceRisk || (InpUseBridgeRiskBasis && sig.riskBasis == "FIXED_REFERENCE");
   capital = fixedReference
      ? (InpFixedRiskReferenceCapital > 0.0 ? InpFixedRiskReferenceCapital : sig.riskReferenceCapital)
      : AccountInfoDouble(ACCOUNT_EQUITY);
   budget = capital * MathMax(0.0, riskPct) / 100.0;
   if(fixedReference && InpFixedRiskReferenceCapital <= 0.0 && sig.riskBudgetMoney > 0.0
      && MathAbs(sig.riskBudgetMoney - budget) > MathMax(1.0, InpFixedRiskMaxOvershootMoney))
   {
      detail = "fixed_reference_contract_mismatch calculated=" + DoubleToString(budget, 2) + " bridge=" + DoubleToString(sig.riskBudgetMoney, 2);
      return false;
   }
   if(riskPct <= 0.0 || capital <= 0.0 || budget <= 0.0)
   {
      detail = "risk_budget_invalid fixed=" + (fixedReference ? "1" : "0") + " capital=" + DoubleToString(capital, 2) + " pct=" + DoubleToString(riskPct, 4);
      return false;
   }
   detail = "risk_basis=" + (fixedReference ? "FIXED_REFERENCE" : "CURRENT_EQUITY");
   return true;
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
   double effectiveRiskPct=0.0,capital=0.0,budget=0.0; bool fixedReference=false; string budgetDetail="";
   if(!ResolveRiskBudget(sig,effectiveRiskPct,capital,budget,fixedReference,budgetDetail)) { detail=budgetDetail; return 0.0; }
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
      double sizingTolerance = fixedReference ? MathMax(0.0, InpFixedRiskMaxOvershootMoney) : budget * 0.001;
      if(rawLot < minVol && minLotRisk > budget + sizingTolerance)
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
   double sizingTolerance = fixedReference ? MathMax(0.0, InpFixedRiskMaxOvershootMoney) : budget * 0.001;
   if(InpBlockIfMinLotExceedsRisk && actualRisk > budget + sizingTolerance)
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
   detail += " fixed_reference=" + (fixedReference ? "1" : "0") + " " + budgetDetail;
   return lot;
}

bool EnforcePostFillRisk(ulong ticket, const BridgeSignal &sig, string &detail)
{
   detail = "";
   if(!InpUseRiskLot || !InpPostFillRiskGuard) return true;
   if(ticket == 0 || !PositionSelectByTicket(ticket))
   {
      detail = "post_fill_position_not_found";
      return false;
   }
   double fill = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double effectiveRiskPct=0.0,capital=0.0,budget=0.0; bool fixedReference=false; string budgetDetail="";
   if(!ResolveRiskBudget(sig,effectiveRiskPct,capital,budget,fixedReference,budgetDetail)) { detail=budgetDetail; return false; }
   string calcDetail = "";
   double moneyPerLot = MoneyRiskPerLotByOrderCalc(sig.direction, fill, sig.sl, calcDetail);
   if(moneyPerLot <= 0.0 || budget <= 0.0)
   {
      detail = "post_fill_risk_calc_failed budget=" + DoubleToString(budget, 2) + " " + calcDetail;
      if(!InpFailClosedOnRiskError) return true;
      ResetLastError();
      bool closeCall = trade.PositionClose(ticket);
      bool closeOk = TradeCallAccepted(closeCall);
      detail += " emergency_close=" + (closeOk ? "true" : "false") + " ret=" + IntegerToString((int)trade.ResultRetcode());
      return false;
   }
   double actualRisk = volume * moneyPerLot;
   double toleratedBudget = fixedReference ? budget + MathMax(0.0, InpFixedRiskMaxOvershootMoney) : budget * 1.001;
   if(actualRisk <= toleratedBudget)
   {
      detail = "post_fill_risk_ok budget=" + DoubleToString(budget, 2)
         + " actual=" + DoubleToString(actualRisk, 2)
         + " volume=" + DoubleToString(volume, VolumeDigits());
      return true;
   }

   if(fixedReference)
   {
      ResetLastError();
      bool closeCall = trade.PositionClose(ticket);
      bool closeOk = TradeCallAccepted(closeCall);
      detail = "fixed_reference_post_fill_exceeded budget=" + DoubleToString(budget, 2)
         + " actual=" + DoubleToString(actualRisk, 2) + " max=" + DoubleToString(toleratedBudget, 2)
         + " emergency_close=" + (closeOk ? "true" : "false") + " ret=" + IntegerToString((int)trade.ResultRetcode());
      return false;
   }

   double allowedVolume = NormalizeVolumeDown(budget / moneyPerLot);
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   if(allowedVolume < minVolume - 0.000000001)
   {
      ResetLastError();
      bool closeCall = trade.PositionClose(ticket);
      bool closeOk = TradeCallAccepted(closeCall);
      detail = "post_fill_min_volume_exceeds_risk budget=" + DoubleToString(budget, 2)
         + " actual=" + DoubleToString(actualRisk, 2)
         + " allowed=" + DoubleToString(allowedVolume, VolumeDigits())
         + " emergency_close=" + (closeOk ? "true" : "false")
         + " ret=" + IntegerToString((int)trade.ResultRetcode());
      return false;
   }

   double closeVolume = NormalizeVolumeDown(volume - allowedVolume);
   if(closeVolume <= 0.0 || closeVolume >= volume)
   {
      ResetLastError();
      bool closeCall = trade.PositionClose(ticket);
      bool closeOk = TradeCallAccepted(closeCall);
      detail = "post_fill_shrink_invalid current=" + DoubleToString(volume, VolumeDigits())
         + " allowed=" + DoubleToString(allowedVolume, VolumeDigits())
         + " emergency_close=" + (closeOk ? "true" : "false")
         + " ret=" + IntegerToString((int)trade.ResultRetcode());
      return false;
   }

   ResetLastError();
   bool partialCall = trade.PositionClosePartial(ticket, closeVolume);
   bool partialOk = TradeCallAccepted(partialCall);
   long partialRet = trade.ResultRetcode();
   if(partialOk && PositionSelectByTicket(ticket))
   {
      double remaining = PositionGetDouble(POSITION_VOLUME);
      double remainingRisk = remaining * moneyPerLot;
      if(remaining <= allowedVolume + step * 0.5 && remainingRisk <= budget * 1.001)
      {
         detail = "post_fill_risk_shrunk from=" + DoubleToString(volume, VolumeDigits())
            + " to=" + DoubleToString(remaining, VolumeDigits())
            + " budget=" + DoubleToString(budget, 2)
            + " risk=" + DoubleToString(remainingRisk, 2)
            + " ret=" + IntegerToString((int)partialRet);
         return true;
      }
   }

   ResetLastError();
   bool closeCall = trade.PositionClose(ticket);
   bool closeOk = TradeCallAccepted(closeCall);
   detail = "post_fill_risk_shrink_failed current=" + DoubleToString(volume, VolumeDigits())
      + " allowed=" + DoubleToString(allowedVolume, VolumeDigits())
      + " partial_ret=" + IntegerToString((int)partialRet)
      + " emergency_close=" + (closeOk ? "true" : "false")
      + " close_ret=" + IntegerToString((int)trade.ResultRetcode());
   return false;
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
   return IQC_PIPELINE_ID + "|POS|" + IntegerToString((int)InpMagic) + "|" + IntegerToString((int)ticket) + "|" + kind;
}

int SourceTfToInt(string tf)
{
   string clean = Trim(tf);
   if(clean == "")
      return 0;
   return (int)StringToInteger(clean);
}

int PositionSourceTfFromComment()
{
   string comment = PositionGetString(POSITION_COMMENT);
   long magic = (long)PositionGetInteger(POSITION_MAGIC);
   int start = 0;
   if(StringFind(comment, "AFB|T") == 0)
      start = 5;
   else if(StringFind(comment, "AFBB|T") == 0)
      start = 6;
   else if(magic == InpMagic && StringFind(comment, "GFB|T") == 0)   // legacy Atomic builds only
      start = 5;
   else if(magic == InpMagic && StringFind(comment, "GFBB|T") == 0)  // legacy Atomic basket builds only
      start = 6;
   else
      return 0;
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
      ok = TradeCallAccepted(ok);
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
         ok = TradeCallAccepted(ok);
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
      if(posComment != comment)
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
bool PositionHasExitDeal(ulong positionId)
{
   if(positionId == 0 || !HistorySelectByPosition(positionId)) return false;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY) continue;
      if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}
void RepairLegacyPositionMetadata(const BridgeSignal &sig)
{
   int sourceTf = SourceTfToInt(sig.sourceTf);
   if(sourceTf <= 0)
      return;

   string eventHash = IntegerToString((int)HashString(sig.eventId));
   string legacyComment = "AFB|" + eventHash;
   string modernComment = "AFB|T" + sig.sourceTf + "|" + eventHash;
   string oldLegacyComment = "GFB|" + eventHash;
   string oldModernComment = "GFB|T" + sig.sourceTf + "|" + eventHash;
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
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      string comment = PositionGetString(POSITION_COMMENT);
      if(comment != legacyComment && comment != modernComment && comment != oldLegacyComment && comment != oldModernComment)
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
         double openEntry = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSl = PositionGetDouble(POSITION_SL);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize <= 0.0) tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         bool beAlready = currentSl > 0.0 && MathAbs(currentSl - openEntry) <= tickSize * 0.51;
         bool partialExit = PositionHasExitDeal(ticket);
         GlobalVariableSet(hcKey, sig.halfTrigger);
         GlobalVariableSet(PosKey(ticket, "DONE"), beAlready ? 1.0 : (partialExit ? 3.0 : 0.0));
         GlobalVariableSet(PosKey(ticket, "ENTRY"), openEntry);
         GlobalVariableSet(PosKey(ticket, "INITVOL"), PositionGetDouble(POSITION_VOLUME));
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
   if(PositionSelectByTicket(ticket))
      GlobalVariableSet(PosKey(ticket, "INITVOL"), PositionGetDouble(POSITION_VOLUME));

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
   auditSig.source = IQC_PIPELINE_ID;
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
      if(PositionIsBasketBridge())
         continue;
      int posTf = PositionSourceTf(ticket);
      if(managerTf > 0 && posTf > 0 && managerTf != posTf)
         continue;
      string hcKey = PosKey(ticket, "HC");
      if(!GlobalVariableCheck(hcKey))
         continue;
      string doneKey = PosKey(ticket, "DONE");
      double doneState = GlobalVariableCheck(doneKey) ? GlobalVariableGet(doneKey) : 0.0;
      double hc = GlobalVariableGet(hcKey);
      double entry = GlobalVariableCheck(PosKey(ticket, "ENTRY")) ? GlobalVariableGet(PosKey(ticket, "ENTRY")) : PositionGetDouble(POSITION_PRICE_OPEN);
      long type = PositionGetInteger(POSITION_TYPE);

      // State 2 means a partial-close request was in flight when execution stopped.
      // Reconstruct conservatively: never issue a second half close when uncertain.
      if(doneState > 1.5 && doneState < 2.5)
      {
         double initVol = GlobalVariableCheck(PosKey(ticket, "INITVOL")) ? GlobalVariableGet(PosKey(ticket, "INITVOL")) : 0.0;
         double currentVol = PositionGetDouble(POSITION_VOLUME);
         if(initVol > 0.0 && currentVol >= initVol - step * 0.5)
            GlobalVariableSet(doneKey, 0.0);
         else
            GlobalVariableSet(doneKey, 3.0);
         doneState = GlobalVariableGet(doneKey);
      }

      // State 3 means half-close succeeded and only the BE modification remains.
      if(doneState > 2.5)
      {
         datetime nextBeTry = GlobalVariableCheck(PosKey(ticket, "BENEXT")) ? (datetime)GlobalVariableGet(PosKey(ticket, "BENEXT")) : 0;
         if(nextBeTry > TimeCurrent()) continue;
         double currentTp = PositionGetDouble(POSITION_TP);
         ResetLastError();
         bool beCall = trade.PositionModify(ticket, NormalizeDouble(entry, _Digits), currentTp);
         bool beOk = TradeCallAccepted(beCall);
         string verify = "";
         if(beOk && ProtectionMatches(ticket, NormalizeDouble(entry, _Digits), currentTp, verify))
         {
            GlobalVariableSet(doneKey, 1.0);
            GlobalVariableDel(PosKey(ticket, "BENEXT"));
            AuditRaw("halfbe_be_retry_done", "ticket=" + IntegerToString((int)ticket) + " " + verify);
         }
         else
         {
            GlobalVariableSet(PosKey(ticket, "BENEXT"), (double)(TimeCurrent() + 2));
            AuditRaw("halfbe_be_retry_pending", "ticket=" + IntegerToString((int)ticket) + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " " + verify);
         }
         continue;
      }
      if(doneState > 0.5)
         continue;
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

      if(!GlobalVariableSetOnCondition(doneKey, 2.0, 0.0))
      {
         Audit("halfbe_skip_lock_taken", auditSig, baseDetail + " done=" + (GlobalVariableCheck(doneKey) ? DoubleToString(GlobalVariableGet(doneKey), 1) : "missing"));
         continue;
      }
      ResetLastError();
      bool partialCall = trade.PositionClosePartial(ticket, closeVol);
      bool partialOk = TradeCallAccepted(partialCall);
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

      GlobalVariableSet(PosKey(ticket, "DONE"), 3.0); // Half is complete; BE may be retried without another partial close.
      double currentTp = PositionGetDouble(POSITION_TP);
      ResetLastError();
      bool modifyCall = trade.PositionModify(ticket, NormalizeDouble(entry, _Digits), currentTp);
      bool modifyOk = TradeCallAccepted(modifyCall);
      string beVerify = "";
      if(modifyOk) modifyOk = ProtectionMatches(ticket, NormalizeDouble(entry, _Digits), currentTp, beVerify);
      long modifyRet = trade.ResultRetcode();
      int modifyErr = GetLastError();
      string modifyDetail = partialDetail
         + " modify_ok=" + (modifyOk ? "true" : "false")
         + " modify_retcode=" + IntegerToString((int)modifyRet)
         + " modify_err=" + IntegerToString(modifyErr)
         + " be_sl=" + PriceStr(NormalizeDouble(entry, _Digits))
         + " remaining_after=" + DoubleToString(PositionGetDouble(POSITION_VOLUME), VolumeDigits())
         + " verify=" + beVerify;

      if(!modifyOk)
      {
         GlobalVariableSet(PosKey(ticket, "DONE"), 3.0);
         GlobalVariableSet(PosKey(ticket, "BENEXT"), (double)(TimeCurrent() + 2));
         Audit("halfbe_sl_to_be_failed_after_partial", auditSig, modifyDetail + " half_done=1 be_retry_pending=1");
         continue;
      }

      GlobalVariableSet(PosKey(ticket, "DONE"), 1.0);
      Audit("halfbe_done", auditSig, modifyDetail);
   }
}

bool IsBasketSignal(const BridgeSignal &sig)
{
   return SameTextCi(sig.tradeMode, "basket_daily_target");
}

double SymbolPipSize()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
}

bool BasketStopValid(const int direction, double entry, double sl, string &reason)
{
   reason = "";
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStop = MathMax(point * 2.0, (double)stopLevel * point);
   if(entry <= 0.0 || sl <= 0.0)
   {
      reason = "missing_entry_or_catastrophic_sl";
      return false;
   }
   if(direction > 0)
   {
      if(sl >= entry) { reason = "bad_buy_catastrophic_sl"; return false; }
      if(entry - sl < minStop) { reason = "buy_cat_sl_stop_level min=" + DoubleToString(minStop, _Digits); return false; }
   }
   else
   {
      if(sl <= entry) { reason = "bad_sell_catastrophic_sl"; return false; }
      if(sl - entry < minStop) { reason = "sell_cat_sl_stop_level min=" + DoubleToString(minStop, _Digits); return false; }
   }
   return true;
}

bool ShouldRebaseBasketLevels(const BridgeSignal &sig)
{
   if(!InpRebaseMappedLevelsToLiveEntry)
      return false;
   if(sig.bridgeEntry <= 0.0 || sig.sl <= 0.0)
      return false;
   string mapped = MapSymbol(sig.sourceSymbol);
   if(!SameTextCi(mapped, _Symbol))
      return false;
   if(InpRebaseOnlyWhenSourceDiffers && SameTextCi(sig.sourceSymbol, _Symbol))
      return false;
   return true;
}

void RebaseBasketSlToLiveEntry(BridgeSignal &sig, double liveEntry, string &detail)
{
   detail = "";
   double srcEntry = sig.bridgeEntry;
   double oldSl = sig.sl;
   if(srcEntry <= 0.0 || oldSl <= 0.0 || liveEntry <= 0.0)
      return;
   double risk = MathAbs(srcEntry - oldSl);
   if(risk <= 0.0)
      return;
   sig.sl = sig.direction > 0 ? liveEntry - risk : liveEntry + risk;
   sig.sl = NormalizeDouble(sig.sl, _Digits);
   detail = "basket_rebase source_entry=" + DoubleToString(srcEntry, _Digits)
          + " live_entry=" + DoubleToString(liveEntry, _Digits)
          + " old_sl=" + DoubleToString(oldSl, _Digits)
          + " new_sl=" + DoubleToString(sig.sl, _Digits)
          + " risk_dist=" + DoubleToString(risk, _Digits)
          + " mapped=" + MapSymbol(sig.sourceSymbol);
}

string BasketDayKeyNow()
{
   return DateKey(TimeGMT());
}

string BasketStateKey(string field)
{
   return IQC_PIPELINE_ID + "|BASKET|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + _Symbol + "|" + IntegerToString((int)InpMagic) + "|" + BasketDayKeyNow() + "|" + field;
}

bool PositionIsBasketBridge()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
      return false;
   string comment = PositionGetString(POSITION_COMMENT);
   return StringFind(comment, "AFBB|") == 0 || StringFind(comment, "GFBB|") == 0;
}

double BasketScopedPnlToday(bool includeFloating)
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);
   double pnl = 0.0;
   if(HistorySelect(dayStart, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;
         string comment = HistoryDealGetString(deal, DEAL_COMMENT);
         if(StringFind(comment, "AFBB|") != 0 && StringFind(comment, "GFBB|") != 0) continue;
         pnl += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION);
      }
   }
   if(includeFloating)
   {
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         ulong ticket = PositionGetTicket(j);
         if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
         if(!PositionIsBasketBridge()) continue;
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }
   return pnl;
}

double BasketTargetMoney(const BridgeSignal &sig)
{
   return AccountInfoDouble(ACCOUNT_EQUITY) * MathMax(0.0, sig.basketTargetPct) / 100.0;
}

double BasketMaxLossMoney(const BridgeSignal &sig)
{
   if(sig.basketTargetPips <= 0.0)
      return 0.0;
   return BasketTargetMoney(sig) * MathMax(0.0, sig.basketMaxLossPips) / sig.basketTargetPips;
}

void BasketSetDayDone(string reason)
{
   GlobalVariableSet(BasketStateKey("DONE"), 1.0);
   GlobalVariableSet(BasketStateKey("DONE_TS"), TimeGMT());
   GlobalVariableSet(BasketStateKey("DONE_REASON_HASH"), (double)HashString(reason));
}

bool BasketDayDone(string &detail)
{
   if(!GlobalVariableCheck(BasketStateKey("DONE")) || GlobalVariableGet(BasketStateKey("DONE")) < 0.5)
      return false;
   detail = "basket_day_done day=" + BasketDayKeyNow() + " pnl=" + DoubleToString(BasketScopedPnlToday(true), 2);
   return true;
}

int ParseHHMM(string s)
{
   s = Trim(s);
   int colon = StringFind(s, ":");
   if(colon < 0) return -1;
   int h = (int)StringToInteger(StringSubstr(s, 0, colon));
   int m = (int)StringToInteger(StringSubstr(s, colon + 1));
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
}

bool BasketSessionEndReached(const BridgeSignal &sig, string &detail)
{
   detail = "";
   if(!sig.basketCloseSessionEnd) return false;
   string raw = Trim(sig.basketSessionEndTime);
   if(raw == "") return false;
   int endMin = ParseHHMM(raw);
   if(endMin < 0)
   {
      detail = "invalid_basket_session_end_time='" + raw + "'";
      return false;
   }
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int curMin = dt.hour * 60 + dt.min;
   if(curMin >= endMin)
   {
      detail = "basket_session_end_reached now=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " end=" + raw;
      return true;
   }
   return false;
}

bool BasketGuardReached(const BridgeSignal &sig, string &reason, string &detail)
{
   reason = "";
   detail = "basket_guard_ok";
   if(BasketDayDone(detail))
   {
      reason = "basket_blocked_day_done";
      return true;
   }
   if(BasketSessionEndReached(sig, detail))
   {
      reason = "basket_session_close";
      BasketSetDayDone(reason);
      return true;
   }
   double pnl = BasketScopedPnlToday(true);
   double target = BasketTargetMoney(sig);
   double maxLoss = BasketMaxLossMoney(sig);
   if(target > 0.0 && pnl >= target - 0.0001)
   {
      reason = "basket_target_hit_close";
      detail = "basket_pnl=" + DoubleToString(pnl, 2) + " target_money=" + DoubleToString(target, 2) + " target_pips=" + DoubleToString(sig.basketTargetPips, 1) + " target_pct=" + DoubleToString(sig.basketTargetPct, 3);
      BasketSetDayDone(reason);
      return true;
   }
   if(maxLoss > 0.0 && pnl <= -maxLoss + 0.0001)
   {
      reason = "basket_loss_hit_close";
      detail = "basket_pnl=" + DoubleToString(pnl, 2) + " max_loss_money=" + DoubleToString(maxLoss, 2) + " max_loss_pips=" + DoubleToString(sig.basketMaxLossPips, 1);
      BasketSetDayDone(reason);
      return true;
   }
   detail = "basket_pnl=" + DoubleToString(pnl, 2) + " target_money=" + DoubleToString(target, 2) + " max_loss_money=" + DoubleToString(maxLoss, 2);
   return false;
}

bool CloseBasketPositions(const BridgeSignal &sig, string eventName, string reason)
{
   bool allOk = true;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!PositionIsBasketBridge()) continue;
      int posTf = PositionSourceTf(ticket);
      int sigTf = SourceTfToInt(sig.sourceTf);
      if(!InpCloseReverseAcrossSourceTf && sigTf > 0 && posTf > 0 && sigTf != posTf) continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      string lifecycle = BasketLifecycleDetail(ticket, eventName, pnl, false);
      bool ok = trade.PositionClose(ticket);
      long ret = trade.ResultRetcode();
      ok = TradeCallAccepted(ok);
      if(ok)
         Audit(eventName, sig, "ticket=" + IntegerToString((int)ticket) + " vol=" + DoubleToString(vol, VolumeDigits()) + " pnl=" + DoubleToString(pnl, 2) + " reason=" + reason + " ret=" + IntegerToString((int)ret) + " " + lifecycle);
      else
      {
         allOk = false;
         Audit(eventName + "_failed", sig, "ticket=" + IntegerToString((int)ticket) + " vol=" + DoubleToString(vol, VolumeDigits()) + " pnl=" + DoubleToString(pnl, 2) + " reason=" + reason + " ret=" + IntegerToString((int)ret) + " err=" + IntegerToString(GetLastError()) + " " + lifecycle);
      }
   }
   return allOk;
}

bool CloseReverseBasketPositions(const BridgeSignal &sig, string &detail)
{
   if(!InpCloseReverse || !sig.basketCloseOnReverse)
   {
      detail = "basket_reverse_close_disabled";
      return true;
   }
   int found = 0;
   int closed = 0;
   int failed = 0;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!PositionIsBasketBridge()) continue;
      string scopeDetail = "";
      if(!ReverseScopeAllows(ticket, sig, scopeDetail)) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      bool opposite = (sig.direction > 0 && type == POSITION_TYPE_SELL) || (sig.direction < 0 && type == POSITION_TYPE_BUY);
      if(!opposite) continue;
      found++;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      string lifecycle = BasketLifecycleDetail(ticket, "basket_reverse_close", pnl, true);
      if(trade.PositionClose(ticket))
      {
         closed++;
         Audit("basket_reverse_close", sig, "ticket=" + IntegerToString((int)ticket) + " vol=" + DoubleToString(vol, VolumeDigits()) + " pnl=" + DoubleToString(pnl, 2) + " " + lifecycle);
      }
      else
      {
         failed++;
         Audit("basket_reverse_close_failed", sig, "ticket=" + IntegerToString((int)ticket) + " vol=" + DoubleToString(vol, VolumeDigits()) + " pnl=" + DoubleToString(pnl, 2) + " ret=" + IntegerToString((int)trade.ResultRetcode()) + " err=" + IntegerToString(GetLastError()) + " " + lifecycle);
      }
   }
   detail = "basket_reverse_found=" + IntegerToString(found) + " closed=" + IntegerToString(closed) + " failed=" + IntegerToString(failed);
   return failed == 0;
}

double ResolveBasketLot(const BridgeSignal &sig, double entry, string &detail)
{
   double pipSize = SymbolPipSize();
   double targetMove = MathMax(0.0, sig.basketTargetPips) * pipSize;
   if(targetMove <= 0.0 || sig.basketTargetPct <= 0.0)
   {
      detail = "basket_lot_invalid target_pips=" + DoubleToString(sig.basketTargetPips, 1) + " target_pct=" + DoubleToString(sig.basketTargetPct, 3);
      return 0.0;
   }
   double targetPrice = sig.direction > 0 ? entry + targetMove : entry - targetMove;
   string calcDetail = "";
   double moneyPerLot = MoneyRiskPerLotByOrderCalc(sig.direction, entry, targetPrice, calcDetail);
   double targetMoney = BasketTargetMoney(sig);
   if(moneyPerLot <= 0.0 || targetMoney <= 0.0)
   {
      detail = "basket_lot_money_invalid target_money=" + DoubleToString(targetMoney, 2) + " money_per_lot=" + DoubleToString(moneyPerLot, 2) + " " + calcDetail;
      return 0.0;
   }
   double rawLot = targetMoney / moneyPerLot;
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(InpBlockIfMinLotExceedsRisk && minVol > 0.0)
   {
      double minLotTargetMoney = minVol * moneyPerLot;
      if(rawLot < minVol && minLotTargetMoney > targetMoney * 1.001)
      {
         detail = "basket_min_lot_exceeds_target_money target_money=" + DoubleToString(targetMoney, 2) + " money_per_lot=" + DoubleToString(moneyPerLot, 2) + " raw_lot=" + DoubleToString(rawLot, 4) + " min_lot=" + DoubleToString(minVol, VolumeDigits());
         return 0.0;
      }
   }
   double lot = NormalizeVolume(rawLot);
   string marginDetail = "";
   if(g_marginShrinkGuardRuntime && InpMaxMarginUsagePct > 0.0)
   {
      double requested = lot;
      lot = ShrinkLotToMarginLimit(sig.direction, lot, entry, InpMaxMarginUsagePct, marginDetail);
      if(lot <= 0.0)
      {
         detail = "basket_margin_block " + marginDetail;
         return 0.0;
      }
      if(lot < requested - 0.0000001)
         marginDetail = " " + marginDetail;
   }
   string catRiskDetail = "";
   double catRiskPerLot = MoneyRiskPerLotByOrderCalc(sig.direction, entry, sig.sl, catRiskDetail);
   double actualTarget = moneyPerLot * lot;
   double actualCatRisk = catRiskPerLot * lot;
   detail = "basket_lot risk_calc=ordercalcprofit target_pips=" + DoubleToString(sig.basketTargetPips, 1)
      + " target_pct=" + DoubleToString(sig.basketTargetPct, 3)
      + " target_money=" + DoubleToString(targetMoney, 2)
      + " money_per_lot_at_target=" + DoubleToString(moneyPerLot, 2)
      + " raw_lot=" + DoubleToString(rawLot, 4)
      + " lot=" + DoubleToString(lot, VolumeDigits())
      + " actual_target_money=" + DoubleToString(actualTarget, 2)
      + " actual_risk_to_cat_sl=" + DoubleToString(actualCatRisk, 2)
      + " cat_risk_per_lot=" + DoubleToString(catRiskPerLot, 2)
      + " " + calcDetail + " " + catRiskDetail + marginDetail;
   return lot;
}

void StoreBasketState(ulong ticket, const BridgeSignal &sig, double fill)
{
   if(ticket == 0) return;
   int sourceTf = SourceTfToInt(sig.sourceTf);
   if(sourceTf > 0)
      GlobalVariableSet(PosKey(ticket, "STF"), sourceTf);
   GlobalVariableSet(PosKey(ticket, "ENTRY"), fill);
   if(PositionSelectByTicket(ticket))
      GlobalVariableSet(PosKey(ticket, "INITVOL"), PositionGetDouble(POSITION_VOLUME));
   GlobalVariableSet(PosKey(ticket, "BASKET"), 1.0);
   GlobalVariableSet(PosKey(ticket, "BTPIPS"), sig.basketTargetPips);
   GlobalVariableSet(PosKey(ticket, "BTPCT"), sig.basketTargetPct);
   GlobalVariableSet(PosKey(ticket, "BLPIPS"), sig.basketMaxLossPips);
   GlobalVariableSet(PosKey(ticket, "BCAT"), sig.basketCatastrophicSlPips);
   GlobalVariableSet(PosKey(ticket, "BREV"), sig.basketCloseOnReverse ? 1.0 : 0.0);
   GlobalVariableSet(PosKey(ticket, "BSESS"), sig.basketCloseSessionEnd ? 1.0 : 0.0);
   GlobalVariableSet(PosKey(ticket, "BSESSMIN"), (double)ParseHHMM(sig.basketSessionEndTime));
   GlobalVariableSet(PosKey(ticket, "OPEN_TS"), (double)TimeCurrent());
   GlobalVariableSet(PosKey(ticket, "DIR"), (double)sig.direction);
   GlobalVariableSet(PosKey(ticket, "MFE_PIPS"), 0.0);
   GlobalVariableSet(PosKey(ticket, "MAE_PIPS"), 0.0);
   GlobalVariableSet(PosKey(ticket, "MFE_MONEY"), 0.0);
   GlobalVariableSet(PosKey(ticket, "MAE_MONEY"), 0.0);
   GlobalVariableSet(PosKey(ticket, "MFE_TS"), (double)TimeCurrent());
   GlobalVariableSet(PosKey(ticket, "MAE_TS"), (double)TimeCurrent());
   GlobalVariableSet(PosKey(ticket, "MFE_PX"), fill);
   GlobalVariableSet(PosKey(ticket, "MAE_PX"), fill);
   GlobalVariableSet(PosKey(ticket, "FTARGET_TS"), 0.0);
   GlobalVariableSet(PosKey(ticket, "FLOSS_TS"), 0.0);
   GlobalVariableSet(PosKey(ticket, "REVCOUNT"), 0.0);
   UpdateBasketLifecycleState(ticket);
}


string MlTimeText(datetime t)
{
   if(t <= 0) return "";
   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

double BasketPosGv(ulong ticket, string kind, double fallback)
{
   string key = PosKey(ticket, kind);
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback;
}

void BasketPosSet(ulong ticket, string kind, double value)
{
   GlobalVariableSet(PosKey(ticket, kind), value);
}

void UpdateBasketLifecycleState(ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;
   if(!PositionIsBasketBridge()) return;
   double pipSize = SymbolPipSize();
   if(pipSize <= 0.0) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   long type = PositionGetInteger(POSITION_TYPE);
   int dir = (type == POSITION_TYPE_BUY ? 1 : -1);
   double entry = BasketPosGv(ticket, "ENTRY", PositionGetDouble(POSITION_PRICE_OPEN));
   if(entry <= 0.0) return;
   if(!GlobalVariableCheck(PosKey(ticket, "OPEN_TS")))
      BasketPosSet(ticket, "OPEN_TS", (double)(datetime)PositionGetInteger(POSITION_TIME));
   if(!GlobalVariableCheck(PosKey(ticket, "DIR")))
      BasketPosSet(ticket, "DIR", (double)dir);
   double closePx = dir > 0 ? tick.bid : tick.ask;
   double signedPips = dir > 0 ? (closePx - entry) / pipSize : (entry - closePx) / pipSize;
   double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   datetime now = TimeCurrent();

   bool mfeInit = !GlobalVariableCheck(PosKey(ticket, "MFE_TS"));
   bool maeInit = !GlobalVariableCheck(PosKey(ticket, "MAE_TS"));
   double oldMfe = BasketPosGv(ticket, "MFE_PIPS", signedPips);
   double oldMae = BasketPosGv(ticket, "MAE_PIPS", signedPips);
   if(mfeInit || signedPips > oldMfe)
   {
      BasketPosSet(ticket, "MFE_PIPS", signedPips);
      BasketPosSet(ticket, "MFE_MONEY", pnl);
      BasketPosSet(ticket, "MFE_TS", (double)now);
      BasketPosSet(ticket, "MFE_PX", closePx);
   }
   if(maeInit || signedPips < oldMae)
   {
      BasketPosSet(ticket, "MAE_PIPS", signedPips);
      BasketPosSet(ticket, "MAE_MONEY", pnl);
      BasketPosSet(ticket, "MAE_TS", (double)now);
      BasketPosSet(ticket, "MAE_PX", closePx);
   }
   double targetPips = BasketPosGv(ticket, "BTPIPS", 0.0);
   double lossPips = BasketPosGv(ticket, "BLPIPS", 0.0);
   if(targetPips > 0.0 && BasketPosGv(ticket, "FTARGET_TS", 0.0) <= 0.0 && signedPips >= targetPips)
      BasketPosSet(ticket, "FTARGET_TS", (double)now);
   if(lossPips > 0.0 && BasketPosGv(ticket, "FLOSS_TS", 0.0) <= 0.0 && signedPips <= -lossPips)
      BasketPosSet(ticket, "FLOSS_TS", (double)now);
}

void UpdateOpenBasketLifecycleStates()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!PositionIsBasketBridge()) continue;
      UpdateBasketLifecycleState(ticket);
   }
}

string BasketLifecycleDetail(ulong ticket, string closeReason, double closePnl, bool countReverseSignal)
{
   if(ticket == 0) return "ml_state=missing_ticket";
   UpdateBasketLifecycleState(ticket);
   if(countReverseSignal)
      BasketPosSet(ticket, "REVCOUNT", BasketPosGv(ticket, "REVCOUNT", 0.0) + 1.0);
   double entry = BasketPosGv(ticket, "ENTRY", 0.0);
   double dir = BasketPosGv(ticket, "DIR", 0.0);
   double openTs = BasketPosGv(ticket, "OPEN_TS", 0.0);
   double mfe = BasketPosGv(ticket, "MFE_PIPS", 0.0);
   double mae = BasketPosGv(ticket, "MAE_PIPS", 0.0);
   double mfeFav = MathMax(0.0, mfe);
   double maeAdv = MathMax(0.0, -mae);
   double mfeMoney = BasketPosGv(ticket, "MFE_MONEY", 0.0);
   double maeMoney = BasketPosGv(ticket, "MAE_MONEY", 0.0);
   double mfePx = BasketPosGv(ticket, "MFE_PX", 0.0);
   double maePx = BasketPosGv(ticket, "MAE_PX", 0.0);
   double targetPips = BasketPosGv(ticket, "BTPIPS", 0.0);
   double lossPips = BasketPosGv(ticket, "BLPIPS", 0.0);
   double catPips = BasketPosGv(ticket, "BCAT", 0.0);
   double targetTs = BasketPosGv(ticket, "FTARGET_TS", 0.0);
   double lossTs = BasketPosGv(ticket, "FLOSS_TS", 0.0);
   string first = "none";
   if(targetTs > 0.0 && lossTs > 0.0) first = (targetTs <= lossTs ? "target" : "loss");
   else if(targetTs > 0.0) first = "target";
   else if(lossTs > 0.0) first = "loss";
   double duration = openTs > 0.0 ? MathMax(0.0, (double)(TimeCurrent() - (datetime)openTs)) : 0.0;
   return "ml=1 close_reason=" + closeReason
      + " ticket=" + IntegerToString((int)ticket)
      + " entry=" + DoubleToString(entry, _Digits)
      + " dir=" + DoubleToString(dir, 0)
      + " duration_sec=" + DoubleToString(duration, 0)
      + " close_pnl=" + DoubleToString(closePnl, 2)
      + " target_pips=" + DoubleToString(targetPips, 2)
      + " max_loss_pips=" + DoubleToString(lossPips, 2)
      + " cat_sl_pips=" + DoubleToString(catPips, 2)
      + " mfe_pips=" + DoubleToString(mfeFav, 2)
      + " mae_pips=" + DoubleToString(maeAdv, 2)
      + " mfe_signed_pips=" + DoubleToString(mfe, 2)
      + " mae_signed_pips=" + DoubleToString(mae, 2)
      + " mfe_money=" + DoubleToString(mfeMoney, 2)
      + " mae_money=" + DoubleToString(maeMoney, 2)
      + " mfe_price=" + DoubleToString(mfePx, _Digits)
      + " mae_price=" + DoubleToString(maePx, _Digits)
      + " first_target_hit=" + (targetTs > 0.0 ? "1" : "0")
      + " first_loss_hit=" + (lossTs > 0.0 ? "1" : "0")
      + " first_hit=" + first
      + " target_hit_time=" + MlTimeText((datetime)targetTs)
      + " loss_hit_time=" + MlTimeText((datetime)lossTs)
      + " mfe_time=" + MlTimeText((datetime)BasketPosGv(ticket, "MFE_TS", 0.0))
      + " mae_time=" + MlTimeText((datetime)BasketPosGv(ticket, "MAE_TS", 0.0))
      + " reverse_signal_count=" + DoubleToString(BasketPosGv(ticket, "REVCOUNT", 0.0), 0);
}

bool BuildRuntimeBasketSignal(BridgeSignal &sig)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!PositionIsBasketBridge()) continue;
      sig.valid = true;
      sig.version = "runtime";
      sig.writtenGmt = TimeGMT();
      sig.sourceLogin = 0;
      sig.sourceSymbol = _Symbol;
      sig.sourceTf = IntegerToString(PositionSourceTf(ticket));
      sig.eventId = "basket_runtime_guard";
      sig.source = IQC_PIPELINE_ID + "|basket_runtime";
      sig.direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      sig.signalTime = 0;
      sig.bridgeEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      sig.sl = PositionGetDouble(POSITION_SL);
      sig.tp = 0.0;
      sig.halfTrigger = 0.0;
      sig.halfLabel = "basket_off";
      sig.sourceBuild = ATOMIC_FILE_BRIDGE_MT5_BUILD;
      sig.sourceBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sig.sourceAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sig.riskPct = InpRiskPerTradePct;
      sig.tradeMode = "basket_daily_target";
      sig.basketTargetPips = GlobalVariableCheck(PosKey(ticket, "BTPIPS")) ? GlobalVariableGet(PosKey(ticket, "BTPIPS")) : 0.0;
      sig.basketTargetPct = GlobalVariableCheck(PosKey(ticket, "BTPCT")) ? GlobalVariableGet(PosKey(ticket, "BTPCT")) : InpRiskPerTradePct;
      sig.basketMaxLossPips = GlobalVariableCheck(PosKey(ticket, "BLPIPS")) ? GlobalVariableGet(PosKey(ticket, "BLPIPS")) : 0.0;
      sig.basketCatastrophicSlPips = GlobalVariableCheck(PosKey(ticket, "BCAT")) ? GlobalVariableGet(PosKey(ticket, "BCAT")) : 0.0;
      sig.basketCloseOnReverse = GlobalVariableCheck(PosKey(ticket, "BREV")) ? (GlobalVariableGet(PosKey(ticket, "BREV")) > 0.5) : true;
      sig.basketCloseSessionEnd = GlobalVariableCheck(PosKey(ticket, "BSESS")) ? (GlobalVariableGet(PosKey(ticket, "BSESS")) > 0.5) : false;
      int sessMin = GlobalVariableCheck(PosKey(ticket, "BSESSMIN")) ? (int)MathRound(GlobalVariableGet(PosKey(ticket, "BSESSMIN"))) : -1;
      sig.basketSessionEndTime = sessMin >= 0 ? StringFormat("%02d:%02d", sessMin / 60, sessMin % 60) : "";
      sig.basketDayKey = BasketDayKeyNow();
      return true;
   }
   return false;
}

void ManageBasketRuntimeGuards()
{
   UpdateOpenBasketLifecycleStates();
   BridgeSignal sig;
   if(!BuildRuntimeBasketSignal(sig))
      return;
   string reason = "", detail = "";
   if(!BasketGuardReached(sig, reason, detail))
      return;
   bool ok = CloseBasketPositions(sig, reason, detail);
   Audit(reason, sig, detail + " close_ok=" + (ok ? "true" : "false") + " runtime_guard=1");
}
bool ExecuteBasketSignal(const BridgeSignal &sourceSig)
{
   BridgeSignal sig = sourceSig;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Audit("basket_skip_no_tick", sig, "");
      return false;
   }
   string reason = "";
   if(!SpreadAllowed(reason))
   {
      Audit("basket_skip_spread", sig, reason);
      return false;
   }
   double entry = sig.direction > 0 ? tick.ask : tick.bid;
   string rebaseDetail = "";
   if(ShouldRebaseBasketLevels(sig))
   {
      RebaseBasketSlToLiveEntry(sig, entry, rebaseDetail);
      if(rebaseDetail != "") Audit("basket_levels_rebased", sig, rebaseDetail);
   }
   if(!BasketStopValid(sig.direction, entry, sig.sl, reason))
   {
      g_lastRejectedEventId = sig.eventId;
      Audit("basket_skip_geometry", sig, reason + StopContext(entry, sig.sl, 0.0));
      return false;
   }
   string guardReason = "", guardDetail = "";
   if(BasketGuardReached(sig, guardReason, guardDetail))
   {
      CloseBasketPositions(sig, guardReason, guardDetail);
      Audit("basket_skip_day_done", sig, guardReason + " " + guardDetail);
      return true;
   }
   if(!ClaimEvent(sig.eventId))
   {
      Audit("basket_skip_duplicate", sig, "event_global_claim_exists");
      return true;
   }
   string reverseDetail = "";
   if(!CloseReverseBasketPositions(sig, reverseDetail))
   {
      ReleaseEvent(sig.eventId);
      Audit("basket_skip_reverse_close_failed", sig, reverseDetail);
      if(InpFailIfReverseCloseFails) return false;
   }
   string lotDetail = "";
   double lot = ResolveBasketLot(sig, entry, lotDetail);
   if(lot <= 0.0)
   {
      g_lastRejectedEventId = sig.eventId;
      ReleaseEvent(sig.eventId);
      Audit("basket_skip_lot", sig, lotDetail);
      return false;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   string comment = "AFBB|T" + sig.sourceTf + "|" + IntegerToString((int)HashString(sig.eventId));
   bool ok = sig.direction > 0
      ? trade.Buy(lot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), 0.0, comment)
      : trade.Sell(lot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), 0.0, comment);
   if(!TradeCallAccepted(ok))
   {
      long ret = trade.ResultRetcode();
      ReleaseEvent(sig.eventId);
      if(PermanentOrderFailure(ret)) g_lastRejectedEventId = sig.eventId;
      Audit("basket_order_failed", sig, "retcode=" + IntegerToString((int)ret) + StopContext(entry, sig.sl, 0.0) + " " + lotDetail);
      return false;
   }
   ulong posTicket = FindOpenedPositionTicket(sig, comment);
   ulong resultDeal = trade.ResultDeal();
   if(posTicket == 0 && resultDeal > 0 && HistoryDealSelect(resultDeal))
   {
      ulong positionId = (ulong)HistoryDealGetInteger(resultDeal, DEAL_POSITION_ID);
      if(positionId > 0 && PositionSelectByTicket(positionId)) posTicket = positionId;
   }
   BridgeSignal fillSig = sourceSig;
   double actualFill = (posTicket > 0 && PositionSelectByTicket(posTicket)) ? PositionGetDouble(POSITION_PRICE_OPEN) : entry;
   string postFillRebase = "";
   if(ShouldRebaseBasketLevels(fillSig)) RebaseBasketSlToLiveEntry(fillSig, actualFill, postFillRebase);
   else fillSig = sig;
   string protectionDetail = "";
   if(!EnsureExactProtection(posTicket, fillSig, protectionDetail))
   {
      Audit("basket_post_fill_protection_failed", fillSig, protectionDetail + " post_fill_rebase=" + postFillRebase);
      return false;
   }
   string postFillRiskDetail = "";
   if(!EnforcePostFillRisk(posTicket, fillSig, postFillRiskDetail))
   {
      Audit("basket_post_fill_risk_guard_failed", fillSig, postFillRiskDetail);
      return false;
   }
   StoreBasketState(posTicket, fillSig, actualFill);
   Audit("basket_order_sent", sig, "lot=" + DoubleToString(lot, VolumeDigits()) + " live_entry=" + PriceStr(entry) + " pos=" + IntegerToString((int)posTicket) + (rebaseDetail != "" ? " rebase=" + rebaseDetail : "") + " " + lotDetail);
   return true;
}
bool ExecuteSignal(const BridgeSignal &sourceSig)
{
   BridgeSignal sig = sourceSig;
   if(IsBasketSignal(sig))
      return ExecuteBasketSignal(sig);
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
   RepairLegacyPositionMetadata(sig);
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
   if(!TradeCallAccepted(ok))
   {
      long ret = trade.ResultRetcode();
      ReleaseEvent(sig.eventId);
      string permanent = PermanentOrderFailure(ret) ? " permanent_reject=1" : " permanent_reject=0";
      if(PermanentOrderFailure(ret))
         g_lastRejectedEventId = sig.eventId;
      Audit("order_failed", sig, "retcode=" + IntegerToString((int)ret) + permanent + StopContext(entry, sig.sl, sig.tp) + " " + lotDetail);
      return false;
   }
   ulong deal = trade.ResultDeal();
   ulong order = trade.ResultOrder();
   ulong posTicket = FindOpenedPositionTicket(sig, comment);
   if(posTicket == 0 && deal > 0 && HistoryDealSelect(deal))
   {
      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(positionId > 0 && PositionSelectByTicket(positionId)) posTicket = positionId;
   }
   BridgeSignal fillSig = sourceSig;
   double actualFill = (posTicket > 0 && PositionSelectByTicket(posTicket)) ? PositionGetDouble(POSITION_PRICE_OPEN) : entry;
   string postFillRebase = "";
   if(ShouldRebaseLevels(fillSig)) RebaseLevelsToLiveEntry(fillSig, actualFill, postFillRebase);
   else fillSig = sig;
   string protectionDetail = "";
   if(!EnsureExactProtection(posTicket, fillSig, protectionDetail))
   {
      Audit("post_fill_protection_failed", fillSig, protectionDetail + " post_fill_rebase=" + postFillRebase);
      return false;
   }
   string postFillRiskDetail = "";
   if(!EnforcePostFillRisk(posTicket, fillSig, postFillRiskDetail))
   {
      Audit("post_fill_risk_guard_failed", fillSig, postFillRiskDetail);
      return false;
   }
   StoreHalfState(posTicket, fillSig, actualFill);
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
            Print("IQC_PIPELINE_ID bridge_initiated_seen caller=", caller, " ", readDetail);
         }
         else
         {
            AuditRaw("read_failed", "caller=" + caller + " " + readDetail);
            Print("IQC_PIPELINE_ID read_failed caller=", caller, " ", readDetail);
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
   if(InpRequireHedgingAccount && AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print(IQC_PIPELINE_ID, " init blocked: destination account is not hedging");
      return INIT_FAILED;
   }
   string destinationServer = AccountInfoString(ACCOUNT_SERVER);
   if(InpDestinationServerFilter != "" && !ContainsCi(destinationServer, InpDestinationServerFilter))
   {
      Print(IQC_PIPELINE_ID, " init blocked: destination server=", destinationServer, " expected contains=", InpDestinationServerFilter);
      return INIT_FAILED;
   }
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
   Print(IQC_PIPELINE_ID, " MT5 Listener BUILD=", ATOMIC_FILE_BRIDGE_MT5_BUILD,
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
   ManageProtectionFailures();
   ManageBasketRuntimeGuards();
   PollBridge("timer");
   DrawDashboard();
}

void OnTick()
{
   ManageProtectionFailures();
   ManageBasketRuntimeGuards();
   ManageHalfCloseBe();
   uint now = GetTickCount();
   if(now - g_lastPollMs >= (uint)MathMax(100, InpPollMilliseconds))
   {
      g_lastPollMs = now;
      PollBridge("tick");
   }
   DrawDashboard();
}
