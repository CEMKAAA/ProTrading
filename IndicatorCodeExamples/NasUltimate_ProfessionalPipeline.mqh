#ifndef NAS_ULTIMATE_PROFESSIONAL_PIPELINE_MQH
#define NAS_ULTIMATE_PROFESSIONAL_PIPELINE_MQH

#define NAS_PRO_PIPELINE_BUILD "2026-07-27.nas-professional-pipeline-v6-risk-apply-scope"

input group "NAS Professional Audit / cTrader Bridge"
input bool   InpNasProAuditEnabled = false;
input bool   InpNasAuditPositionProbe = false;
input int    InpNasAuditProbeSec = 30;
input bool   InpNasAuditProbeOnChangeOnly = true;
input int    InpNasAuditHistoryScanSec = 3;
input bool   InpNasTesterTradeAuditCsv = false;
input int    InpNasTesterTradeAuditMaxRows = 50000;
input bool   InpNasBridgeEnabled = false;
input bool   InpNasBridgeOnlyMode = false;
input bool   InpNasNativeTradeWithBridgeOnly = false;
input bool   InpNasBridgeUseCommonFiles = true;
input string InpNasBridgeLatestFile = "NasUltimateBridge_Latest.csv";
input string InpNasBridgeAuditPrefix = "NasUltimateBridge_Audit_";

struct NasProBridgePendingEvent
{
   string eventId;
   string dir;
   double entry;
   double sl;
   double tp;
   string source;
   double halfTrigger;
   string halfLabel;
   datetime signalTime;
   double riskPct;
   int attempts;
   datetime nextRetryLocal;
};

NasProBridgePendingEvent g_nasProBridgePending[];
bool g_nasProAuditRuntime = false;
bool g_nasBridgeEnabledRuntime = false;
bool g_nasBridgeOnlyRuntime = false;
bool g_nasNativeWithBridgeOnlyRuntime = false;
string g_nasBridgeStatus = "BRIDGE OFF";
datetime g_nasProLastProbe = 0;
datetime g_nasProLastHistoryScan = 0;
ulong g_nasProLastHistoryDeal = 0;
string g_nasProLastProbeHash = "";
string g_nasTesterAuditFile = "";
int g_nasTesterAuditRows = 0;

string NasProU64(const ulong value)
{
   return StringFormat("%I64u", value);
}

string NasProI64(const long value)
{
   return StringFormat("%I64d", value);
}
string NasProTf(const ENUM_TIMEFRAMES tf)
{
   int sec = PeriodSeconds(tf);
   if(sec > 0) return IntegerToString(sec / 60);
   return EnumToString(tf);
}

string NasProTime(const datetime t)
{
   if(t <= 0) return "";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

string NasProDate(const datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return StringFormat("%04d%02d%02d", d.year, d.mon, d.day);
}

string NasProSafeToken(string value)
{
   StringReplace(value, "/", "_");
   StringReplace(value, ":", "_");
   StringReplace(value, "*", "_");
   StringReplace(value, "?", "_");
   StringReplace(value, "<", "_");
   StringReplace(value, ">", "_");
   StringReplace(value, "|", "_");
   StringReplace(value, " ", "_");
   return value;
}

string NasProDir(const int dir)
{
   return dir > 0 ? "BUY" : (dir < 0 ? "SELL" : "NONE");
}

bool NasProCriticalAuditEvent(const string eventName)
{
   if(StringFind(eventName, "order_") == 0) return true;
   if(StringFind(eventName, "risk_") == 0) return true;
   if(StringFind(eventName, "close_") == 0) return true;
   if(StringFind(eventName, "half_") == 0) return true;
   if(StringFind(eventName, "sl_to_be_") == 0) return true;
   if(StringFind(eventName, "position_") == 0) return true;
   if(StringFind(eventName, "bridge_") == 0) return true;
   return false;
}

void NasProAuditWrite(const string eventName,
                      const string id,
                      const int dir,
                      const double entry,
                      const double sl,
                      const double tp,
                      const double lot,
                      const string detail)
{
   if(!g_nasProAuditRuntime && !NasProCriticalAuditEvent(eventName)) return;
   if(IsTesterMode()) return;
   string fileName = "NasUltimate_TradeAudit_" + NasProDate(TimeGMT()) + ".csv";
   for(int attempt = 0; attempt < 3; ++attempt)
   {
      ResetLastError();
      int h = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
      if(h != INVALID_HANDLE)
      {
         bool header = FileSize(h) == 0;
         FileSeek(h, 0, SEEK_END);
         if(header)
            FileWrite(h, "server_time", "gmt_time", "symbol", "tf", "event", "id", "dir", "entry", "sl", "tp", "lot", "spread_pts", "status", "detail");
         FileWrite(h, NasProTime(TimeCurrent()), NasProTime(TimeGMT()), _Symbol, NasProTf(_Period), eventName, id,
            NasProDir(dir), DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits),
            DoubleToString(lot, 4), DoubleToString(g_lastSpreadPoints, 1), g_lastExecutionStatus, detail);
         FileFlush(h);
         FileClose(h);
         return;
      }
      if(attempt < 2) Sleep(10);
   }
   Print("NAS professional audit write failed err=", GetLastError(), " file=", fileName, " event=", eventName);
}

int NasProBridgeFlags(int flags)
{
   if(InpNasBridgeUseCommonFiles) flags |= FILE_COMMON;
   return flags;
}

int NasProBridgeCommonFlag()
{
   return InpNasBridgeUseCommonFiles ? FILE_COMMON : 0;
}

string NasProBridgeScopedLatestFile()
{
   return "NasUltimateBridge_Latest_" + NasProSafeToken(_Symbol) + "_" + NasProTf(_Period) + ".csv";
}

string NasProBridgeOutboxFile()
{
   return "NasUltimateBridge_Outbox_" + NasProSafeToken(_Symbol) + "_" + NasProTf(_Period) + ".csv";
}

string NasProBridgeTempFile(const string target, const int attempt)
{
   return target + ".tmp." + IntegerToString((int)ChartID()) + "." + IntegerToString((int)GetTickCount()) + "." + IntegerToString(attempt);
}

void NasProBridgeWriteHeader(const int h)
{
   FileWrite(h, "version", "written_gmt", "source_login", "symbol", "tf", "event_id", "source", "dir",
      "signal_time", "bridge_entry", "sl", "tp", "half_trigger", "half_label", "source_build", "source_bid", "source_ask", "risk_pct");
}

void NasProBridgeWriteRow(const int h,
                          const string eventId,
                          const string dir,
                          const double entry,
                          const double sl,
                          const double tp,
                          const string source,
                          const double halfTrigger,
                          const string halfLabel,
                          const datetime signalTime,
                          const double riskPct)
{
   MqlTick tick;
   ZeroMemory(tick);
   SymbolInfoTick(_Symbol, tick);
   FileWrite(h, "1", NasProTime(TimeGMT()), NasProI64(AccountInfoInteger(ACCOUNT_LOGIN)), _Symbol,
      NasProTf(_Period), eventId, source, dir, NasProTime(signalTime), DoubleToString(entry, _Digits),
      DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), DoubleToString(halfTrigger, _Digits), halfLabel,
      NAS_PRO_PIPELINE_BUILD, DoubleToString(tick.bid, _Digits), DoubleToString(tick.ask, _Digits), DoubleToString(riskPct, 4));
}

bool NasProBridgePromote(const string tempName, const string target)
{
   int common = NasProBridgeCommonFlag();
   ResetLastError();
   if(FileMove(tempName, common, target, common | FILE_REWRITE)) return true;
   int err = GetLastError();
   FileDelete(tempName, common);
   Print("NAS bridge atomic promote failed err=", err, " temp=", tempName, " target=", target);
   return false;
}

bool NasProBridgeWriteLatest(const string target,
                             const string eventId,
                             const string dir,
                             const double entry,
                             const double sl,
                             const double tp,
                             const string source,
                             const double halfTrigger,
                             const string halfLabel,
                             const datetime signalTime,
                             const double riskPct)
{
   for(int attempt = 0; attempt < 3; ++attempt)
   {
      string tempName = NasProBridgeTempFile(target, attempt);
      FileDelete(tempName, NasProBridgeCommonFlag());
      ResetLastError();
      int h = FileOpen(tempName, NasProBridgeFlags(FILE_CSV | FILE_WRITE | FILE_ANSI), ',');
      if(h != INVALID_HANDLE)
      {
         NasProBridgeWriteHeader(h);
         NasProBridgeWriteRow(h, eventId, dir, entry, sl, tp, source, halfTrigger, halfLabel, signalTime, riskPct);
         FileFlush(h);
         FileClose(h);
         if(NasProBridgePromote(tempName, target)) return true;
      }
      else
         Print("NAS bridge temp open failed err=", GetLastError(), " file=", tempName);
      FileDelete(tempName, NasProBridgeCommonFlag());
      if(attempt < 2) Sleep(20);
   }
   return false;
}

bool NasProBridgePersistPending()
{
   string target = NasProBridgeOutboxFile();
   string tempName = NasProBridgeTempFile(target, 0);
   FileDelete(tempName, NasProBridgeCommonFlag());
   int h = FileOpen(tempName, NasProBridgeFlags(FILE_CSV | FILE_WRITE | FILE_ANSI), ',');
   if(h == INVALID_HANDLE) return false;
   for(int i = 0; i < ArraySize(g_nasProBridgePending); ++i)
      FileWrite(h, g_nasProBridgePending[i].eventId, g_nasProBridgePending[i].dir,
         DoubleToString(g_nasProBridgePending[i].entry, _Digits), DoubleToString(g_nasProBridgePending[i].sl, _Digits),
         DoubleToString(g_nasProBridgePending[i].tp, _Digits), g_nasProBridgePending[i].source,
         DoubleToString(g_nasProBridgePending[i].halfTrigger, _Digits), g_nasProBridgePending[i].halfLabel,
         IntegerToString((long)g_nasProBridgePending[i].signalTime), DoubleToString(g_nasProBridgePending[i].riskPct, 4),
         IntegerToString(g_nasProBridgePending[i].attempts));
   FileFlush(h);
   FileClose(h);
   return NasProBridgePromote(tempName, target);
}

void NasProBridgeLoadPending()
{
   ArrayResize(g_nasProBridgePending, 0);
   int h = FileOpen(NasProBridgeOutboxFile(), NasProBridgeFlags(FILE_CSV | FILE_READ | FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_ANSI), ',');
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h) && ArraySize(g_nasProBridgePending) < 128)
   {
      NasProBridgePendingEvent item;
      item.eventId = FileReadString(h);
      if(item.eventId == "" && FileIsEnding(h)) break;
      item.dir = FileReadString(h);
      item.entry = StringToDouble(FileReadString(h));
      item.sl = StringToDouble(FileReadString(h));
      item.tp = StringToDouble(FileReadString(h));
      item.source = FileReadString(h);
      item.halfTrigger = StringToDouble(FileReadString(h));
      item.halfLabel = FileReadString(h);
      item.signalTime = (datetime)StringToInteger(FileReadString(h));
      item.riskPct = StringToDouble(FileReadString(h));
      item.attempts = (int)StringToInteger(FileReadString(h));
      item.nextRetryLocal = 0;
      if(item.eventId == "") continue;
      int n = ArraySize(g_nasProBridgePending);
      ArrayResize(g_nasProBridgePending, n + 1);
      g_nasProBridgePending[n] = item;
   }
   FileClose(h);
}

bool NasProBridgeQueue(const string eventId,
                       const string dir,
                       const double entry,
                       const double sl,
                       const double tp,
                       const string source,
                       const double halfTrigger,
                       const string halfLabel,
                       const datetime signalTime,
                       const double riskPct)
{
   int index = -1;
   for(int i = 0; i < ArraySize(g_nasProBridgePending); ++i)
      if(g_nasProBridgePending[i].eventId == eventId) { index = i; break; }
   if(index < 0)
   {
      int n = ArraySize(g_nasProBridgePending);
      if(n >= 128) return false;
      ArrayResize(g_nasProBridgePending, n + 1);
      index = n;
      g_nasProBridgePending[index].attempts = 0;
   }
   g_nasProBridgePending[index].eventId = eventId;
   g_nasProBridgePending[index].dir = dir;
   g_nasProBridgePending[index].entry = entry;
   g_nasProBridgePending[index].sl = sl;
   g_nasProBridgePending[index].tp = tp;
   g_nasProBridgePending[index].source = source;
   g_nasProBridgePending[index].halfTrigger = halfTrigger;
   g_nasProBridgePending[index].halfLabel = halfLabel;
   g_nasProBridgePending[index].signalTime = signalTime;
   g_nasProBridgePending[index].riskPct = riskPct;
   g_nasProBridgePending[index].nextRetryLocal = TimeLocal() + 2;
   return NasProBridgePersistPending();
}

void NasProBridgeRemovePending(const int index)
{
   int n = ArraySize(g_nasProBridgePending);
   if(index < 0 || index >= n) return;
   for(int i = index; i < n - 1; ++i) g_nasProBridgePending[i] = g_nasProBridgePending[i + 1];
   ArrayResize(g_nasProBridgePending, n - 1);
}

void NasProBridgeRetryPending()
{
   if(!g_nasBridgeEnabledRuntime || IsTesterMode() || ArraySize(g_nasProBridgePending) <= 0) return;
   if(g_nasProBridgePending[0].nextRetryLocal > TimeLocal()) return;
   NasProBridgePendingEvent item = g_nasProBridgePending[0];
   if(!NasProBridgeWriteLatest(NasProBridgeScopedLatestFile(), item.eventId, item.dir, item.entry, item.sl, item.tp,
      item.source, item.halfTrigger, item.halfLabel, item.signalTime, item.riskPct))
   {
      g_nasProBridgePending[0].attempts++;
      g_nasProBridgePending[0].nextRetryLocal = TimeLocal() + MathMin(30, 2 + g_nasProBridgePending[0].attempts * 2);
      NasProBridgePersistPending();
      return;
   }
   NasProAuditWrite("bridge_outbox_delivered", item.eventId, item.dir == "BUY" ? 1 : -1, item.entry, item.sl, item.tp, 0.0, "durable_retry_success");
   NasProBridgeRemovePending(0);
   NasProBridgePersistPending();
}

bool NasProBridgeWriteInitMarker()
{
   if(!g_nasBridgeEnabledRuntime || IsTesterMode()) return false;
   string eventId = "nas_bridge_init|" + _Symbol + "|" + NasProTf(_Period) + "|" + NasProTime(TimeGMT());
   bool genericOk = NasProBridgeWriteLatest(InpNasBridgeLatestFile, eventId, "INIT", 0, 0, 0, "bridge_initiated", 0, "init", TimeGMT(), g_accountRiskPerTradePctRuntime);
   bool scopedOk = NasProBridgeWriteLatest(NasProBridgeScopedLatestFile(), eventId, "INIT", 0, 0, 0, "bridge_initiated", 0, "init", TimeGMT(), g_accountRiskPerTradePctRuntime);
   g_nasBridgeStatus = scopedOk ? "INIT WROTE" : "INIT FAIL";
   if(!genericOk) Print("NAS bridge generic init write failed file=", InpNasBridgeLatestFile);
   return scopedOk;
}

bool NasProBridgeWriteEvent(const string eventId,
                            const int direction,
                            const double entry,
                            const double sl,
                            const double tp,
                            const string source,
                            const double halfTrigger,
                            const string halfLabel,
                            const datetime signalTime,
                            const double riskPct)
{
   if(!g_nasBridgeEnabledRuntime || IsTesterMode()) return false;
   string dir = NasProDir(direction);
   bool genericOk = NasProBridgeWriteLatest(InpNasBridgeLatestFile, eventId, dir, entry, sl, tp, source, halfTrigger, halfLabel, signalTime, riskPct);
   bool scopedOk = NasProBridgeWriteLatest(NasProBridgeScopedLatestFile(), eventId, dir, entry, sl, tp, source, halfTrigger, halfLabel, signalTime, riskPct);
   bool accepted = scopedOk;
   if(!scopedOk)
      accepted = NasProBridgeQueue(eventId, dir, entry, sl, tp, source, halfTrigger, halfLabel, signalTime, riskPct);

   string auditFile = InpNasBridgeAuditPrefix + NasProDate(TimeGMT()) + ".csv";
   int h = FileOpen(auditFile, NasProBridgeFlags(FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_ANSI), ',');
   if(h != INVALID_HANDLE)
   {
      bool header = FileSize(h) == 0;
      FileSeek(h, 0, SEEK_END);
      if(header) NasProBridgeWriteHeader(h);
      NasProBridgeWriteRow(h, eventId, dir, entry, sl, tp, source, halfTrigger, halfLabel, signalTime, riskPct);
      FileFlush(h);
      FileClose(h);
   }
   g_nasBridgeStatus = scopedOk ? ("WROTE " + dir) : (accepted ? ("QUEUED " + dir) : ("FAIL " + dir));
   NasProAuditWrite(accepted ? "bridge_published" : "bridge_publish_failed", eventId, direction, entry, sl, tp, 0.0,
      "scoped=" + (scopedOk ? "1" : "0") + " generic=" + (genericOk ? "1" : "0") + " risk_pct=" + DoubleToString(riskPct, 4));
   return accepted;
}

string NasProPlanKey(const ulong positionId, const string field)
{
   return "NASPRO|" + NasProI64(AccountInfoInteger(ACCOUNT_LOGIN)) + "|" + NasProI64(RuntimeMagic()) + "|" + NasProU64(positionId) + "|" + field;
}

void NasProSetPlan(const ulong positionId, const string field, const double value)
{
   if(positionId > 0) GlobalVariableSet(NasProPlanKey(positionId, field), value);
}

double NasProGetPlan(const ulong positionId, const string field, const double fallback = 0.0)
{
   if(positionId == 0) return fallback;
   string key = NasProPlanKey(positionId, field);
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback;
}

void NasProStoreSelectedPositionPlan(const ulong ticket,
                                     const datetime signalTime,
                                     const int direction,
                                     const double requestedEntry,
                                     const double requestedSl,
                                     const double requestedTp,
                                     const double halfTrigger)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition()) return;
   ulong positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(positionId == 0) positionId = ticket;
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   if(sl <= 0.0) sl = requestedSl;
   if(tp <= 0.0) tp = requestedTp;
   double pip = NasPipSize();
   NasProSetPlan(positionId, "entry", entry > 0 ? entry : requestedEntry);
   NasProSetPlan(positionId, "sl", sl);
   NasProSetPlan(positionId, "tp", tp);
   NasProSetPlan(positionId, "half", halfTrigger);
   NasProSetPlan(positionId, "openTs", (double)(datetime)PositionGetInteger(POSITION_TIME));
   NasProSetPlan(positionId, "signalTs", (double)signalTime);
   NasProSetPlan(positionId, "dir", (double)direction);
   NasProSetPlan(positionId, "targetPips", pip > 0 ? MathAbs(tp - entry) / pip : 0.0);
   NasProSetPlan(positionId, "lossPips", pip > 0 ? MathAbs(entry - sl) / pip : 0.0);
   NasProSetPlan(positionId, "mfePips", 0.0);
   NasProSetPlan(positionId, "maePips", 0.0);
   NasProSetPlan(positionId, "mfeMoney", 0.0);
   NasProSetPlan(positionId, "maeMoney", 0.0);
   NasProSetPlan(positionId, "mfePx", entry);
   NasProSetPlan(positionId, "maePx", entry);
   NasProSetPlan(positionId, "mfeTs", 0.0);
   NasProSetPlan(positionId, "maeTs", 0.0);
   NasProSetPlan(positionId, "firstTargetTs", 0.0);
   NasProSetPlan(positionId, "firstLossTs", 0.0);
   NasProSetPlan(positionId, "halfDone", 0.0);
   NasProSetPlan(positionId, "riskPct", g_accountRiskPerTradePctRuntime);
   NasProSetPlan(positionId, "spreadPts", g_lastSpreadPoints);
   double riskPips = pip > 0 ? MathAbs(entry - sl) / pip : 0.0;
   double targetPips = pip > 0 ? MathAbs(tp - entry) / pip : 0.0;
   NasProSetPlan(positionId, "targetR", riskPips > 0.0 ? targetPips / riskPips : 0.0);
   NasProSetPlan(positionId, "invert", g_invertTradeModeRuntime ? 1.0 : 0.0);
   NasProSetPlan(positionId, "execMode", (double)InpExecutionMode);
   NasProSetPlan(positionId, "regimeBucket", (double)g_nasMacroLastBucket);
   NasProSetPlan(positionId, "bridgePublished", g_lastSignalBridgePublished ? 1.0 : 0.0);
   double initialRiskMoney = 0.0;
   ENUM_ORDER_TYPE riskOrderType = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double positionVolume = PositionGetDouble(POSITION_VOLUME);
   if(entry > 0.0 && sl > 0.0 && positionVolume > 0.0
      && OrderCalcProfit(riskOrderType, _Symbol, positionVolume, entry, sl, initialRiskMoney))
      initialRiskMoney = MathAbs(initialRiskMoney);
   NasProSetPlan(positionId, "initialRiskMoney", initialRiskMoney);
}

void NasProRegisterUntrackedPositions(const datetime signalTime,
                                      const int direction,
                                      const double entry,
                                      const double sl,
                                      const double fallbackTp,
                                      const double halfTrigger)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition()) continue;
      ulong positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(positionId == 0) positionId = ticket;
      if(NasProGetPlan(positionId, "openTs", 0.0) > 0.0) continue;
      double tp = PositionGetDouble(POSITION_TP);
      if(tp <= 0.0) tp = fallbackTp;
      NasProStoreSelectedPositionPlan(ticket, signalTime, direction, entry, sl, tp, halfTrigger);
      NasProAuditWrite("position_plan_stored", NasProU64(positionId), direction, entry, sl, tp,
         PositionGetDouble(POSITION_VOLUME), "signal_time=" + NasProTime(signalTime));
   }
}

void NasProUpdatePositionLifecycle(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition()) return;
   ulong positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(positionId == 0) positionId = ticket;
   int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   double entry = NasProGetPlan(positionId, "entry", PositionGetDouble(POSITION_PRICE_OPEN));
   if(NasProGetPlan(positionId, "openTs", 0.0) <= 0.0)
      NasProStoreSelectedPositionPlan(ticket, (datetime)PositionGetInteger(POSITION_TIME), dir, entry,
         PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP), 0.0);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double pip = NasPipSize();
   if(pip <= 0.0) return;
   double px = dir > 0 ? tick.bid : tick.ask;
   double signedPips = dir > 0 ? (px - entry) / pip : (entry - px) / pip;
   double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   datetime now = TimeCurrent();
   double mfeTs = NasProGetPlan(positionId, "mfeTs", 0.0);
   double maeTs = NasProGetPlan(positionId, "maeTs", 0.0);
   double oldMfe = NasProGetPlan(positionId, "mfePips", 0.0);
   double oldMae = NasProGetPlan(positionId, "maePips", 0.0);
   if(signedPips > 0.0 && (mfeTs <= 0.0 || signedPips > oldMfe))
   {
      NasProSetPlan(positionId, "mfePips", signedPips);
      NasProSetPlan(positionId, "mfeMoney", pnl);
      NasProSetPlan(positionId, "mfePx", px);
      NasProSetPlan(positionId, "mfeTs", (double)now);
   }
   if(signedPips < 0.0 && (maeTs <= 0.0 || signedPips < oldMae))
   {
      NasProSetPlan(positionId, "maePips", signedPips);
      NasProSetPlan(positionId, "maeMoney", pnl);
      NasProSetPlan(positionId, "maePx", px);
      NasProSetPlan(positionId, "maeTs", (double)now);
   }
   double targetPips = NasProGetPlan(positionId, "targetPips", 0.0);
   double lossPips = NasProGetPlan(positionId, "lossPips", 0.0);
   if(targetPips > 0 && NasProGetPlan(positionId, "firstTargetTs", 0.0) <= 0 && signedPips >= targetPips)
      NasProSetPlan(positionId, "firstTargetTs", (double)now);
   if(lossPips > 0 && NasProGetPlan(positionId, "firstLossTs", 0.0) <= 0 && signedPips <= -lossPips)
      NasProSetPlan(positionId, "firstLossTs", (double)now);
}

void NasProUpdateOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0) NasProUpdatePositionLifecycle(ticket);
   }
}

string NasProLifecycleDetail(const ulong positionId, const string closeReason, const double closePnl)
{
   if(positionId == 0) return "ml_state=missing_position_id";
   double openTs = NasProGetPlan(positionId, "openTs", 0.0);
   double targetTs = NasProGetPlan(positionId, "firstTargetTs", 0.0);
   double lossTs = NasProGetPlan(positionId, "firstLossTs", 0.0);
   string first = "none";
   if(targetTs > 0 && lossTs > 0) first = targetTs <= lossTs ? "target" : "loss";
   else if(targetTs > 0) first = "target";
   else if(lossTs > 0) first = "loss";
   return "ml=1 close_reason=" + closeReason
      + " position_id=" + NasProU64(positionId)
      + " duration_sec=" + DoubleToString(openTs > 0 ? MathMax(0.0, (double)(TimeCurrent() - (datetime)openTs)) : 0.0, 0)
      + " close_pnl=" + DoubleToString(closePnl, 2)
      + " target_pips=" + DoubleToString(NasProGetPlan(positionId, "targetPips", 0.0), 2)
      + " max_loss_pips=" + DoubleToString(NasProGetPlan(positionId, "lossPips", 0.0), 2)
      + " mfe_pips=" + DoubleToString(MathMax(0.0, NasProGetPlan(positionId, "mfePips", 0.0)), 2)
      + " mae_pips=" + DoubleToString(MathMax(0.0, -NasProGetPlan(positionId, "maePips", 0.0)), 2)
      + " mfe_money=" + DoubleToString(NasProGetPlan(positionId, "mfeMoney", 0.0), 2)
      + " mae_money=" + DoubleToString(NasProGetPlan(positionId, "maeMoney", 0.0), 2)
      + " mfe_price=" + DoubleToString(NasProGetPlan(positionId, "mfePx", 0.0), _Digits)
      + " mae_price=" + DoubleToString(NasProGetPlan(positionId, "maePx", 0.0), _Digits)
      + " first_target_hit=" + (targetTs > 0 ? "1" : "0")
      + " first_loss_hit=" + (lossTs > 0 ? "1" : "0")
      + " first_hit=" + first
      + " target_hit_time=" + NasProTime((datetime)targetTs)
      + " loss_hit_time=" + NasProTime((datetime)lossTs)
      + " mfe_time=" + NasProTime((datetime)NasProGetPlan(positionId, "mfeTs", 0.0))
      + " mae_time=" + NasProTime((datetime)NasProGetPlan(positionId, "maeTs", 0.0))
      + " target_r=" + DoubleToString(NasProGetPlan(positionId, "targetR", 0.0), 3)
      + " regime_bucket=" + IntegerToString((int)NasProGetPlan(positionId, "regimeBucket", -1.0))
      + " bridge_published=" + IntegerToString((int)NasProGetPlan(positionId, "bridgePublished", 0.0));
}

bool NasProPositionIdentifierOpen(const ulong positionId)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId) return true;
   }
   return false;
}

string NasProMlWrittenKey(const ulong positionId)
{
   return "NASPRO_ML_WRITTEN|" + NasProI64(AccountInfoInteger(ACCOUNT_LOGIN)) + "|"
      + NasProI64(RuntimeMagic()) + "|" + NasProU64(positionId);
}

string NasProSessionBucket(const datetime gmtTime)
{
   MqlDateTime d;
   TimeToStruct(gmtTime, d);
   if(d.hour < 7) return "ASIA";
   if(d.hour < 13) return "LONDON";
   if(d.hour < 22) return "NEW_YORK";
   return "ROLLOVER";
}

bool NasProWriteFinalLifecycle(const ulong positionId, const string exitReason)
{
   if(positionId == 0 || NasProPositionIdentifierOpen(positionId)) return false;
   string writtenKey = NasProMlWrittenKey(positionId);
   if(GlobalVariableCheck(writtenKey)) return true;
   if(!HistorySelectByPosition(positionId)) return false;

   double totalPnl = 0.0;
   double totalOutVolume = 0.0;
   double weightedClose = 0.0;
   datetime closeTs = 0;
   ulong finalDeal = 0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; ++i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if(!RuntimeMagicOwned((long)HistoryDealGetInteger(deal, DEAL_MAGIC))) continue;
      long entryType = HistoryDealGetInteger(deal, DEAL_ENTRY);
      totalPnl += HistoryDealGetDouble(deal, DEAL_PROFIT)
         + HistoryDealGetDouble(deal, DEAL_SWAP)
         + HistoryDealGetDouble(deal, DEAL_COMMISSION)
         + HistoryDealGetDouble(deal, DEAL_FEE);
      if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT || entryType == DEAL_ENTRY_OUT_BY)
      {
         double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
         totalOutVolume += volume;
         weightedClose += HistoryDealGetDouble(deal, DEAL_PRICE) * volume;
         datetime dealTs = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
         if(dealTs >= closeTs)
         {
            closeTs = dealTs;
            finalDeal = deal;
         }
      }
   }
   if(finalDeal == 0 || closeTs <= 0) return false;

   double entry = NasProGetPlan(positionId, "entry", 0.0);
   double sl = NasProGetPlan(positionId, "sl", 0.0);
   double tp = NasProGetPlan(positionId, "tp", 0.0);
   double closePrice = totalOutVolume > 0.0 ? weightedClose / totalOutVolume : HistoryDealGetDouble(finalDeal, DEAL_PRICE);
   int direction = (int)NasProGetPlan(positionId, "dir", 0.0);
   double pip = NasPipSize();
   double slPips = NasProGetPlan(positionId, "lossPips", pip > 0.0 ? MathAbs(entry - sl) / pip : 0.0);
   double tpPips = NasProGetPlan(positionId, "targetPips", pip > 0.0 ? MathAbs(tp - entry) / pip : 0.0);
   double pnlPips = pip > 0.0 && direction != 0 ? (direction > 0 ? closePrice - entry : entry - closePrice) / pip : 0.0;
   double initialRiskMoney = NasProGetPlan(positionId, "initialRiskMoney", 0.0);
   double pnlR = initialRiskMoney > 0.0 ? totalPnl / initialRiskMoney : (slPips > 0.0 ? pnlPips / slPips : 0.0);
   double mfePips = MathMax(0.0, NasProGetPlan(positionId, "mfePips", 0.0));
   double maePips = MathMax(0.0, -NasProGetPlan(positionId, "maePips", 0.0));
   datetime openTs = (datetime)NasProGetPlan(positionId, "openTs", 0.0);
   datetime signalTs = (datetime)NasProGetPlan(positionId, "signalTs", openTs);
   datetime mfeTs = (datetime)NasProGetPlan(positionId, "mfeTs", 0.0);
   datetime maeTs = (datetime)NasProGetPlan(positionId, "maeTs", 0.0);
   int periodSec = MathMax(60, PeriodSeconds(_Period));
   int barsToMfe = openTs > 0 && mfeTs >= openTs ? (int)((mfeTs - openTs) / periodSec) : -1;
   int barsToMae = openTs > 0 && maeTs >= openTs ? (int)((maeTs - openTs) / periodSec) : -1;
   int barsToExit = openTs > 0 && closeTs >= openTs ? (int)((closeTs - openTs) / periodSec) : -1;
   string firstExcursion = "NONE";
   if(mfeTs > 0 && maeTs > 0) firstExcursion = mfeTs <= maeTs ? "MFE" : "MAE";
   else if(mfeTs > 0) firstExcursion = "MFE";
   else if(maeTs > 0) firstExcursion = "MAE";
   datetime firstTargetTs = (datetime)NasProGetPlan(positionId, "firstTargetTs", 0.0);
   datetime firstLossTs = (datetime)NasProGetPlan(positionId, "firstLossTs", 0.0);
   if(firstTargetTs <= 0 && exitReason == "closed_by_broker_tp") firstTargetTs = closeTs;
   if(firstLossTs <= 0 && exitReason == "closed_by_broker_sl") firstLossTs = closeTs;
   string firstBoundaryHit = "NONE";
   if(firstTargetTs > 0 && firstLossTs > 0) firstBoundaryHit = firstTargetTs <= firstLossTs ? "TARGET" : "LOSS";
   else if(firstTargetTs > 0) firstBoundaryHit = "TARGET";
   else if(firstLossTs > 0) firstBoundaryHit = "LOSS";

   long serverGmtOffset = (long)(TimeCurrent() - TimeGMT());
   datetime signalGmt = signalTs > 0 ? (datetime)((long)signalTs - serverGmtOffset) : (datetime)0;
   MqlDateTime brokerParts, gmtParts;
   ZeroMemory(brokerParts);
   ZeroMemory(gmtParts);
   if(signalTs > 0) TimeToStruct(signalTs, brokerParts);
   if(signalGmt > 0) TimeToStruct(signalGmt, gmtParts);
   int regimeBucket = (int)NasProGetPlan(positionId, "regimeBucket", -1.0);
   string fileName = "NasUltimate_MLTradeAudit_v2_" + StringSubstr(NasProDate(TimeGMT()), 0, 6) + ".csv";
   int h = INVALID_HANDLE;
   for(int attempt = 0; attempt < 3 && h == INVALID_HANDLE; ++attempt)
   {
      ResetLastError();
      h = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
      if(h == INVALID_HANDLE && attempt < 2) Sleep(10);
   }
   if(h == INVALID_HANDLE)
   {
      Print("NAS ML lifecycle write deferred err=", GetLastError(), " position_id=", positionId);
      return false;
   }
   bool header = FileSize(h) == 0;
   FileSeek(h, 0, SEEK_END);
   if(header)
      FileWrite(h, "position_id", "symbol", "tf", "signal_server", "signal_gmt", "open_server", "close_server",
         "gmt_weekday", "broker_weekday", "hour_gmt", "hour_broker", "session_bucket", "dir",
         "entry", "sl", "tp", "close", "sl_pips", "tp_pips", "rr", "pnl_money", "pnl_pips", "pnl_r",
         "mfe_pips", "mae_pips", "mfe_before_mae", "bars_to_mfe", "bars_to_mae", "bars_to_exit", "exit_reason",
         "invert_on", "exec_mode", "regime_bucket", "regime_name", "bridge_published", "risk_pct", "entry_spread_points",
         "half_trigger", "half_done", "first_target_hit", "first_loss_hit", "first_boundary_hit",
         "target_hit_time", "loss_hit_time", "mfe_money", "mae_money", "mfe_price", "mae_price", "source_build");
   FileWrite(h, NasProU64(positionId), _Symbol, NasProTf(_Period), NasProTime(signalTs), NasProTime(signalGmt),
      NasProTime(openTs), NasProTime(closeTs), IntegerToString(gmtParts.day_of_week), IntegerToString(brokerParts.day_of_week),
      IntegerToString(gmtParts.hour), IntegerToString(brokerParts.hour), NasProSessionBucket(signalGmt), NasProDir(direction),
      DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), DoubleToString(closePrice, _Digits),
      DoubleToString(slPips, 2), DoubleToString(tpPips, 2), DoubleToString(slPips > 0.0 ? tpPips / slPips : 0.0, 3),
      DoubleToString(totalPnl, 2), DoubleToString(pnlPips, 2), DoubleToString(pnlR, 4), DoubleToString(mfePips, 2),
      DoubleToString(maePips, 2), firstExcursion, IntegerToString(barsToMfe), IntegerToString(barsToMae), IntegerToString(barsToExit),
      exitReason, IntegerToString((int)NasProGetPlan(positionId, "invert", 0.0)),
      IntegerToString((int)NasProGetPlan(positionId, "execMode", 0.0)), IntegerToString(regimeBucket),
      regimeBucket >= 0 && regimeBucket < LIQ_MACRO_REGIME_COUNT ? LiqMacroRegimeName(regimeBucket) : "UNKNOWN",
      IntegerToString((int)NasProGetPlan(positionId, "bridgePublished", 0.0)),
      DoubleToString(NasProGetPlan(positionId, "riskPct", 0.0), 4),
      DoubleToString(NasProGetPlan(positionId, "spreadPts", 0.0), 1),
      DoubleToString(NasProGetPlan(positionId, "half", 0.0), _Digits),
      IntegerToString((int)NasProGetPlan(positionId, "halfDone", 0.0)),
      firstTargetTs > 0 ? "1" : "0", firstLossTs > 0 ? "1" : "0", firstBoundaryHit,
      NasProTime(firstTargetTs), NasProTime(firstLossTs),
      DoubleToString(NasProGetPlan(positionId, "mfeMoney", 0.0), 2),
      DoubleToString(NasProGetPlan(positionId, "maeMoney", 0.0), 2),
      DoubleToString(NasProGetPlan(positionId, "mfePx", 0.0), _Digits),
      DoubleToString(NasProGetPlan(positionId, "maePx", 0.0), _Digits), NAS_PRO_PIPELINE_BUILD);
   FileFlush(h);
   FileClose(h);
   GlobalVariableSet(writtenKey, (double)finalDeal);
   return true;
}
void NasProProbePositions()
{
   if(!g_nasProAuditRuntime || !InpNasAuditPositionProbe || IsTesterMode()) return;
   datetime now = TimeCurrent();
   if(now - g_nasProLastProbe < MathMax(1, InpNasAuditProbeSec)) return;
   g_nasProLastProbe = now;
   string hash = "";
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition()) continue;
      hash += NasProU64(ticket) + ":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + ";";
   }
   if(InpNasAuditProbeOnChangeOnly && hash == g_nasProLastProbeHash) return;
   g_nasProLastProbeHash = hash;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPosition()) continue;
      NasProAuditWrite("position_probe", NasProU64(ticket),
         PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1,
         PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP),
         PositionGetDouble(POSITION_VOLUME), "floating_pnl=" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2));
   }
}

string NasProLastDealKey()
{
   return "NASPRO_LAST_DEAL|" + NasProI64(AccountInfoInteger(ACCOUNT_LOGIN)) + "|"
      + NasProI64(RuntimeMagic()) + "|" + NasProSafeToken(_Symbol) + "|" + NasProTf(_Period);
}

void NasProInitializeHistoryCursor()
{
   string key = NasProLastDealKey();
   if(GlobalVariableCheck(key))
   {
      g_nasProLastHistoryDeal = (ulong)GlobalVariableGet(key);
      return;
   }
   datetime now = TimeCurrent();
   if(HistorySelect(now - 86400 * 30, now))
   {
      for(int i = 0; i < HistoryDealsTotal(); ++i)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         if(!RuntimeMagicOwned((long)HistoryDealGetInteger(deal, DEAL_MAGIC))) continue;
         if(deal > g_nasProLastHistoryDeal) g_nasProLastHistoryDeal = deal;
      }
   }
   GlobalVariableSet(key, (double)g_nasProLastHistoryDeal);
}

void NasProScanClosedHistory()
{
   if(!g_nasProAuditRuntime || IsTesterMode()) return;
   datetime now = TimeCurrent();
   if(now - g_nasProLastHistoryScan < MathMax(1, InpNasAuditHistoryScanSec)) return;
   g_nasProLastHistoryScan = now;
   if(!HistorySelect(now - 86400 * 14, now)) return;
   int total = HistoryDealsTotal();
   for(int i = MathMax(0, total - 160); i < total; ++i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || deal <= g_nasProLastHistoryDeal) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if(!RuntimeMagicOwned((long)HistoryDealGetInteger(deal, DEAL_MAGIC))) continue;
      long entryType = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT && entryType != DEAL_ENTRY_OUT_BY) continue;
      g_nasProLastHistoryDeal = deal;
      GlobalVariableSet(NasProLastDealKey(), (double)g_nasProLastHistoryDeal);
      long why = HistoryDealGetInteger(deal, DEAL_REASON);
      string reason = "closed_by_unknown";
      if(why == DEAL_REASON_SL) reason = "closed_by_broker_sl";
      else if(why == DEAL_REASON_TP) reason = "closed_by_broker_tp";
      else if(why == DEAL_REASON_EXPERT) reason = "closed_by_expert";
      else if(why == DEAL_REASON_CLIENT || why == DEAL_REASON_MOBILE || why == DEAL_REASON_WEB) reason = "closed_manual";
      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP)
         + HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      NasProAuditWrite(reason, NasProU64(deal), 0, HistoryDealGetDouble(deal, DEAL_PRICE), 0, 0,
         HistoryDealGetDouble(deal, DEAL_VOLUME), "profit=" + DoubleToString(pnl, 2) + " " + NasProLifecycleDetail(positionId, reason, pnl));
      NasProWriteFinalLifecycle(positionId, reason);
      HistorySelect(now - 86400 * 14, now);
   }
   // Retry final lifecycle rows independently of the deal cursor. A temporary
   // file lock must not permanently consume the only final-close notification.
   if(HistorySelect(now - 86400 * 14, now))
   {
      int retryTotal = HistoryDealsTotal();
      for(int ri = MathMax(0, retryTotal - 160); ri < retryTotal; ++ri)
      {
         ulong retryDeal = HistoryDealGetTicket(ri);
         if(retryDeal == 0 || HistoryDealGetString(retryDeal, DEAL_SYMBOL) != _Symbol) continue;
         if(!RuntimeMagicOwned((long)HistoryDealGetInteger(retryDeal, DEAL_MAGIC))) continue;
         long retryEntry = HistoryDealGetInteger(retryDeal, DEAL_ENTRY);
         if(retryEntry != DEAL_ENTRY_OUT && retryEntry != DEAL_ENTRY_INOUT && retryEntry != DEAL_ENTRY_OUT_BY) continue;
         ulong retryPositionId = (ulong)HistoryDealGetInteger(retryDeal, DEAL_POSITION_ID);
         long retryWhy = HistoryDealGetInteger(retryDeal, DEAL_REASON);
         string retryReason = "closed_by_unknown";
         if(retryWhy == DEAL_REASON_SL) retryReason = "closed_by_broker_sl";
         else if(retryWhy == DEAL_REASON_TP) retryReason = "closed_by_broker_tp";
         else if(retryWhy == DEAL_REASON_EXPERT) retryReason = "closed_by_expert";
         else if(retryWhy == DEAL_REASON_CLIENT || retryWhy == DEAL_REASON_MOBILE || retryWhy == DEAL_REASON_WEB) retryReason = "closed_manual";
         NasProWriteFinalLifecycle(retryPositionId, retryReason);
         HistorySelect(now - 86400 * 14, now);
      }
   }
}

string NasProTesterStamp()
{
   MqlDateTime d;
   TimeToStruct(TimeGMT(), d);
   return StringFormat("%04d%02d%02d_%02d%02d%02d", d.year, d.mon, d.day, d.hour, d.min, d.sec);
}

void NasProTesterInit()
{
   g_nasTesterAuditRows = 0;
   g_nasTesterAuditFile = "NasUltimate_TesterTradeAudit_" + NasProTesterStamp() + ".csv";
}

void NasProOnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
   {
      if(HistoryDealSelect(trans.deal) && HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol
         && RuntimeMagicOwned((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC)))
      {
         long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         string eventName = (entryType == DEAL_ENTRY_IN ? "order_deal_in" : "close_deal_out");
         double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
            + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) + HistoryDealGetDouble(trans.deal, DEAL_FEE);
         NasProAuditWrite(eventName, NasProU64(trans.deal),
            HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? 1 : -1,
            HistoryDealGetDouble(trans.deal, DEAL_PRICE), request.sl, request.tp, HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
            "retcode=" + IntegerToString((int)result.retcode) + " pnl=" + DoubleToString(pnl, 2));
      }
   }

   if(!InpNasTesterTradeAuditCsv || !MQLInfoInteger(MQL_TESTER)) return;
   if(InpNasTesterTradeAuditMaxRows > 0 && g_nasTesterAuditRows >= InpNasTesterTradeAuditMaxRows) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(!RuntimeMagicOwned((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC))) return;
   int h = FileOpen(g_nasTesterAuditFile, FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(h == INVALID_HANDLE) return;
   bool header = FileSize(h) == 0;
   FileSeek(h, 0, SEEK_END);
   if(header)
      FileWrite(h, "server_time", "gmt_time", "symbol", "tf", "deal", "position_id", "entry_type", "deal_type", "reason", "price", "volume", "request_sl", "request_tp", "profit", "swap", "commission", "fee", "retcode", "comment");
   FileWrite(h, NasProTime(TimeCurrent()), NasProTime(TimeGMT()), _Symbol, NasProTf(_Period), NasProU64(trans.deal),
      NasProI64(HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID)), IntegerToString((int)HistoryDealGetInteger(trans.deal, DEAL_ENTRY)),
      IntegerToString((int)HistoryDealGetInteger(trans.deal, DEAL_TYPE)), IntegerToString((int)HistoryDealGetInteger(trans.deal, DEAL_REASON)),
      DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits), DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 4),
      DoubleToString(request.sl, _Digits), DoubleToString(request.tp, _Digits), DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PROFIT), 2),
      DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_SWAP), 2), DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_COMMISSION), 2),
      DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_FEE), 2), IntegerToString((int)result.retcode), HistoryDealGetString(trans.deal, DEAL_COMMENT));
   FileFlush(h);
   FileClose(h);
   g_nasTesterAuditRows++;
}

void NasProInit()
{
   g_nasProAuditRuntime = InpNasProAuditEnabled;
   g_nasBridgeEnabledRuntime = InpNasBridgeEnabled;
   g_nasBridgeOnlyRuntime = InpNasBridgeOnlyMode;
   g_nasNativeWithBridgeOnlyRuntime = InpNasNativeTradeWithBridgeOnly;
   // Bridge-only execution is invalid without a publisher. Normalize presets
   // here as well as in the dashboard toggle path so an event cannot be consumed
   // without first being persisted for the listener.
   if(g_nasBridgeOnlyRuntime)
      g_nasBridgeEnabledRuntime = true;
   NasProTesterInit();
   NasProInitializeHistoryCursor();
   NasProBridgeLoadPending();
   if(g_nasBridgeEnabledRuntime) NasProBridgeWriteInitMarker();
   NasProAuditWrite("ea_init", "init", 0, 0, 0, 0, 0,
      "build=" + (string)NAS_PRO_PIPELINE_BUILD + " bridge=" + (g_nasBridgeEnabledRuntime ? "1" : "0")
      + " only=" + (g_nasBridgeOnlyRuntime ? "1" : "0") + " native=" + (g_nasNativeWithBridgeOnlyRuntime ? "1" : "0"));
}

void NasProTimer()
{
   NasProBridgeRetryPending();
   NasProUpdateOpenPositions();
   NasProProbePositions();
   NasProScanClosedHistory();
}

string NasProBridgeSource()
{
   return "NasUltimate|" + RiskGeometryModeText()
      + "|" + TpModeText()
      + "|" + EnumToString(InpExecutionMode)
      + "|invert=" + (g_invertTradeModeRuntime ? "1" : "0")
      + "|pip=" + DoubleToString(g_pipSlDistanceRuntime, 2)
      + "|target_r=" + DoubleToString(SelectedTargetR(), 2);
}

double NasProBridgeHalfTrigger(const int direction, const int finalLeg, const double finalTp)
{
   if(g_invertTradeModeRuntime)
      return InvertHcBeEnabled() ? InvertHcBePrice(direction, g_lastEntry, finalTp) : 0.0;
   int hcLeg = EffectiveHcBeLeg();
   double activeTargetR = NasTargetR(direction, g_lastEntry, g_lastSl, finalTp);
   if(hcLeg > 0 && RMultipleForLeg(hcLeg) < activeTargetR - 0.0001)
      return TpPriceForLeg(direction, hcLeg);
   return 0.0;
}

bool NasProPublishCurrentSignal(const datetime signalTime, const int direction)
{
   if(!g_nasBridgeEnabledRuntime) return true;
   if(!UseSingleOrderTpMode())
   {
      g_nasBridgeStatus = "BLOCKED LEGACY MULTI-ORDER";
      NasProAuditWrite("bridge_shape_block", "nas|" + IntegerToString((long)signalTime), direction,
         g_lastEntry, g_lastSl, 0.0, 0.0, "reason=unsupported_legacy_multi_order single_order_required=1");
      return false;
   }
   if(!IsTradingTimeOpen() || !IsTradingTimeOpenAt(signalTime))
   {
      NasProAuditWrite("bridge_window_block", "nas|" + IntegerToString((long)signalTime), direction,
         g_lastEntry, g_lastSl, 0.0, 0.0, "window=" + TradingTimeStateText());
      return false;
   }

   int finalLeg = g_invertTradeModeRuntime ? EffectiveInversionReferenceLeg()
      : (InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? 6 : LegacyLegForTargetR(SelectedTargetR()));
   double finalTp = g_invertTradeModeRuntime && g_lastInvertedFinalTp > 0.0
      ? g_lastInvertedFinalTp
      : (InpExecutionMode == NAS_EXEC_FIXED_1_TO_3R ? g_lastTp3 : CurrentSelectedFinalTp(direction));
   finalTp = NormalizeDouble(finalTp, _Digits);
   if(finalTp <= 0.0)
   {
      NasProAuditWrite("bridge_geometry_invalid", "nas|" + IntegerToString((long)signalTime), direction,
         g_lastEntry, g_lastSl, finalTp, 0.0, "leg=" + IntegerToString(finalLeg));
      return false;
   }

   double half = UseSingleOrderTpMode() ? NasProBridgeHalfTrigger(direction, finalLeg, finalTp) : 0.0;
   string halfLabel = half > 0.0 ? EffectiveHcBeText() : "off";
   double effectiveTargetR = NasTargetR(direction, g_lastEntry, g_lastSl, finalTp);
   string eventId = "nas|" + _Symbol + "|" + NasProTf(_Period) + "|" + IntegerToString((long)signalTime)
      + "|" + NasProDir(direction) + "|R" + DoubleToString(effectiveTargetR, 2);
   string source = NasProBridgeSource() + "|shape=single_order|effective_target_r=" + DoubleToString(effectiveTargetR, 3);
   return NasProBridgeWriteEvent(eventId, direction, g_lastEntry, g_lastSl, finalTp, source,
      half, halfLabel, signalTime, MathMax(0.0, g_accountRiskPerTradePctRuntime));
}

bool NasProPublishRegimeCloseOnly(const datetime signalTime, const int closeDirection, const string rule)
{
   if(!g_nasBridgeEnabledRuntime)
      return true;
   string eventId = "nas|" + _Symbol + "|" + NasProTf(_Period) + "|"
      + IntegerToString((long)signalTime) + "|regime_filter_close|" + NasProDir(closeDirection);
   string source = NasProBridgeSource() + "|RegimeFilterCloseOnly|" + rule + "|shape=single_order";
   return NasProBridgeWriteEvent(eventId, closeDirection, 0.0, 0.0, 0.0, source,
      0.0, "off", signalTime, MathMax(0.0, g_accountRiskPerTradePctRuntime));
}

void NasProToggleBridgePublish()
{
   g_nasBridgeEnabledRuntime = !g_nasBridgeEnabledRuntime;
   if(!g_nasBridgeEnabledRuntime)
   {
      g_nasBridgeOnlyRuntime = false;
      g_nasBridgeStatus = "BRIDGE OFF";
   }
   else
      NasProBridgeWriteInitMarker();
}

void NasProToggleBridgeOnly()
{
   g_nasBridgeOnlyRuntime = !g_nasBridgeOnlyRuntime;
   if(g_nasBridgeOnlyRuntime && !g_nasBridgeEnabledRuntime) g_nasBridgeEnabledRuntime = true;
   if(g_nasBridgeEnabledRuntime) NasProBridgeWriteInitMarker();
}

void NasProToggleNativeWithBridgeOnly()
{
   g_nasNativeWithBridgeOnlyRuntime = !g_nasNativeWithBridgeOnlyRuntime;
}

void NasProToggleAudit()
{
   g_nasProAuditRuntime = !g_nasProAuditRuntime;
   NasProAuditWrite("audit_toggle", "dashboard", 0, 0, 0, 0, 0, g_nasProAuditRuntime ? "ON" : "OFF");
}
#endif
