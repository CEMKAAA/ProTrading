//+------------------------------------------------------------------+
//| Atomic File Bridge MT5 Executor EA                               |
//| Reads MT4 AtomicBridge signals from Terminal Common\Files and     |
//| executes them on MT5 with duplicate guard, risk lot and audit.    |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

#define ATOMIC_FILE_BRIDGE_MT5_BUILD "2026-07-01.1030-oil-symbol-map"

input bool   InpExecutorEnabled = true;
input string InpBridgeLatestFile = "AtomicFileBridge_Latest.csv";
input bool   InpUseCommonFiles = true;
input int    InpPollMilliseconds = 250;
input int    InpMaxSignalAgeSeconds = 900;
input string InpSymbolMapCsv = ""; // Explicit overrides, example: BTCUSDm=BTCUSD,USTECm=USTEC
input bool   InpUseBuiltInOilSymbolMap = true;
input string InpBuiltInOilSymbolMapCsv = "UKOILm=XRBUSD,UKOIL=XRBUSD,USOILm=XTIUSD,USOIL=XTIUSD";
input bool   InpRequireMappedSymbolEqualsChart = true;
input string InpSourceTimeframeFilter = ""; // Empty=all, example M5
input string InpSourceFilter = ""; // Empty=all, example AtomicRegime
input bool   InpCloseReverse = true;
input bool   InpFailIfReverseCloseFails = true;
input bool   InpCloseReverseBridgeCommentPositions = true;
input long   InpMagic = 970102;
input int    InpDeviationPoints = 30;
input int    InpMaxSpreadPoints = 0;
input double InpManualLot = 0.10;
input bool   InpUseRiskLot = true;
input double InpRiskPerTradePct = 1.00;
input double InpMaxLot = 0.00; // 0=broker max
input double InpMaxMarginUsagePct = 40.0;
input bool   InpFailClosedOnRiskError = true;
input bool   InpBlockIfMinLotExceedsRisk = true;
input bool   InpManageHalfCloseBe = true;
input double InpHalfCloseFraction = 0.50;
input bool   InpAuditEnabled = true;
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
   return "AtomicFileBridgeMT5|" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + IntegerToString((int)InpMagic) + "|" + IntegerToString((int)HashString(eventId));
}

bool ClaimEvent(const string eventId)
{
   string key = EventKey(eventId);
   if(GlobalVariableCheck(key))
      return false;
   GlobalVariableSet(key, (double)TimeCurrent());
   return true;
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
   string explicitMap = MapSymbolFromCsv(src, InpSymbolMapCsv);
   if(explicitMap != "")
      return explicitMap;
   if(InpUseBuiltInOilSymbolMap)
   {
      string oilMap = MapSymbolFromCsv(src, InpBuiltInOilSymbolMapCsv);
      if(oilMap != "")
         return oilMap;
   }
   return Trim(src);
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
   DashboardSetRect("BG", x, y, 640, 216, C'17,24,34', C'80,160,220');
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

   int posCount = 0;
   double lots = 0.0;
   double pnl = 0.0;
   string posLines = "";
   OpenPositionStats(posCount, lots, pnl, posLines);
   color pnlColor = pnl >= 0.0 ? C'80,230,150' : C'255,90,110';
   DashboardSetLabel("POS", x + 14, y + 154,
      "Open AFB positions=" + IntegerToString(posCount) + " | lots=" + DoubleToString(lots, 2) + " | pnl=" + DoubleToString(pnl, 2), pnlColor, 8);
   DashboardSetLabel("POSLINES", x + 14, y + 172, posLines, C'220,226,235', 7);
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
bool SignalAcceptedForThisChart(const BridgeSignal &sig, string &reason)
{
   reason = "";
   if(!sig.valid)
   {
      reason = "invalid_signal";
      return false;
   }
   if(InpSourceTimeframeFilter != "" && sig.sourceTf != InpSourceTimeframeFilter)
   {
      reason = "tf_filter source_tf=" + sig.sourceTf;
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
   return NormalizeDouble(v, 2);
}

double ResolveLot(const BridgeSignal &sig, double entry, string &detail)
{
   detail = "manual_lot";
   if(!InpUseRiskLot)
      return NormalizeVolume(InpManualLot);
   double riskDist = MathAbs(entry - sig.sl);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(riskDist <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0)
   {
      detail = "risk_lot_unavailable riskDist=" + DoubleToString(riskDist, _Digits);
      return InpFailClosedOnRiskError ? 0.0 : NormalizeVolume(InpManualLot);
   }
   double effectiveRiskPct = (sig.riskPct > 0.0 ? sig.riskPct : InpRiskPerTradePct);
   double budget = AccountInfoDouble(ACCOUNT_EQUITY) * MathMax(0.0, effectiveRiskPct) / 100.0;
   double moneyPerLot = riskDist / tickSize * tickValue;
   if(moneyPerLot <= 0.0)
   {
      detail = "money_per_lot_invalid";
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
   double actualRisk = lot * moneyPerLot;
   if(InpBlockIfMinLotExceedsRisk && actualRisk > budget * 1.001)
   {
      detail = "normalized_lot_exceeds_risk budget=" + DoubleToString(budget, 2)
             + " risk_dist=" + DoubleToString(riskDist, _Digits)
             + " money_per_lot=" + DoubleToString(moneyPerLot, 2)
             + " raw_lot=" + DoubleToString(rawLot, 4)
             + " lot=" + DoubleToString(lot, 2)
             + " actual_risk=" + DoubleToString(actualRisk, 2);
      return 0.0;
   }

   if(InpMaxMarginUsagePct > 0.0)
   {
      double margin = 0.0;
      ENUM_ORDER_TYPE type = sig.direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcMargin(type, _Symbol, lot, entry, margin) && AccountInfoDouble(ACCOUNT_EQUITY) > 0.0)
      {
         double marginPct = (AccountInfoDouble(ACCOUNT_MARGIN) + margin) * 100.0 / AccountInfoDouble(ACCOUNT_EQUITY);
         if(marginPct > InpMaxMarginUsagePct)
         {
            detail = "margin_block raw_lot=" + DoubleToString(rawLot, 4) + " lot=" + DoubleToString(lot, 2) + " projected_margin_pct=" + DoubleToString(marginPct, 2);
            return 0.0;
         }
      }
   }

   detail = "risk_lot symbol=" + _Symbol
          + " risk_pct=" + DoubleToString(effectiveRiskPct, 3) + (sig.riskPct > 0.0 ? " source=bridge" : " source=local") + " budget=" + DoubleToString(budget, 2)
          + " tick_size=" + DoubleToString(tickSize, _Digits)
          + " tick_value=" + DoubleToString(tickValue, 4)
          + " vol_min=" + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 2)
          + " vol_step=" + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 2)
          + " risk_dist=" + DoubleToString(riskDist, _Digits)
          + " money_per_lot=" + DoubleToString(moneyPerLot, 2)
          + " raw_lot=" + DoubleToString(rawLot, 4)
          + " lot=" + DoubleToString(lot, 2)
          + " actual_risk=" + DoubleToString(actualRisk, 2);
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
   return "AtomicFileBridgeMT5|POS|" + IntegerToString((int)InpMagic) + "|" + IntegerToString((int)ticket) + "|" + kind;
}

void StoreHalfState(ulong ticket, const BridgeSignal &sig, double fill)
{
   if(ticket == 0 || sig.halfTrigger <= 0.0 || !InpManageHalfCloseBe)
      return;
   GlobalVariableSet(PosKey(ticket, "HC"), sig.halfTrigger);
   GlobalVariableSet(PosKey(ticket, "DONE"), 0.0);
   GlobalVariableSet(PosKey(ticket, "ENTRY"), fill);
}

void ManageHalfCloseBe()
{
   if(!InpManageHalfCloseBe)
      return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic)
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
      double closeVol = NormalizeVolume(vol * MathMax(0.0, MathMin(1.0, InpHalfCloseFraction)));
      if(closeVol > 0.0 && closeVol < vol)
         trade.PositionClosePartial(ticket, closeVol);
      trade.PositionModify(ticket, NormalizeDouble(entry, _Digits), PositionGetDouble(POSITION_TP));
      GlobalVariableSet(PosKey(ticket, "DONE"), 1.0);
   }
}

bool ExecuteSignal(const BridgeSignal &sig)
{
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
      ReleaseEvent(sig.eventId);
      Audit("skip_lot", sig, lotDetail);
      return false;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   string comment = "AFB|" + IntegerToString((int)HashString(sig.eventId));
   bool ok = sig.direction > 0
      ? trade.Buy(lot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), NormalizeDouble(sig.tp, _Digits), comment)
      : trade.Sell(lot, _Symbol, 0.0, NormalizeDouble(sig.sl, _Digits), NormalizeDouble(sig.tp, _Digits), comment);
   if(!ok)
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
   ulong posTicket = 0;
   if(PositionSelect(_Symbol) && (long)PositionGetInteger(POSITION_MAGIC) == InpMagic)
      posTicket = (ulong)PositionGetInteger(POSITION_TICKET);
   StoreHalfState(posTicket, sig, entry);
   Audit("order_sent", sig, "lot=" + DoubleToString(lot, 2) + " live_entry=" + PriceStr(entry) + " deal=" + IntegerToString((int)deal) + " order=" + IntegerToString((int)order) + " pos=" + IntegerToString((int)posTicket) + " " + lotDetail);
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
   if(g_lastPollHeartbeat == 0 || hbNow - g_lastPollHeartbeat >= 60)
   {
      g_lastPollHeartbeat = hbNow;
      AuditRaw("poll_heartbeat", "caller=" + caller + " " + readDetail + " last_seen=" + g_lastSeenEventId);
   }

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
   if(ExecuteSignal(sig))
      g_lastSeenEventId = sig.eventId;
}

void PollBridge()
{
   PollBridge("legacy");
}
int OnInit()
{
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
   AuditRaw("init", "file=" + InpBridgeLatestFile + " common=" + (InpUseCommonFiles ? "true" : "false") + " map=" + InpSymbolMapCsv + " builtin_oil_map=" + (InpUseBuiltInOilSymbolMap ? InpBuiltInOilSymbolMapCsv : "OFF") + " timer=" + (g_timerActive ? "true" : "false") + " timer_err=" + IntegerToString(timerErr) + " poll_ms=" + IntegerToString(InpPollMilliseconds));
   PollBridge("init");
   DrawDashboard(true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   AuditRaw("deinit", "reason=" + IntegerToString(reason));
   EventKillTimer();
   DashboardDelete();
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






















