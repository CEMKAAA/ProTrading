#property strict
#property version "1.00"

#define BUILD_TAG "2026-06-20.0100-gann-ftmo-risklot-toggle"
#define EMPTY_SENTINEL 2147483647.0

input string InpIndicatorName = "Asiller\\Gann Made Easy\\GannMadeEasy @PaidCrackedEA"; // informational; EA trades chart objects.
input int    InpBuyBuffer = 4;  // unused in object mode
input int    InpSellBuffer = 1; // unused in object mode
input int    InpSignalLookbackBars = 8;
input bool   InpScanOnTick = true;
input int    InpPollSeconds = 1;
input bool   InpTradeLatestSignalOnAttach = false;
input string InpBuySignalObjectName = "GANN-UP";
input string InpSellSignalObjectName = "GANN-DN";
input string InpSignalLevelObjectName = "GANN-SIGNAL LEVEL";
input string InpStopLevelObjectName = "GANN-STOP LEVEL";
input string InpTargetLevel1ObjectName = "GANN-TARGET LEVEL 1";
input string InpTargetLevel2ObjectName = "GANN-TARGET LEVEL 2";
input string InpTargetLevel3ObjectName = "GANN-TARGET LEVEL 3";
input int    InpMaxSignalAgeBars = 500;
input bool   InpAllowCalculatedFallbackLevels = true;
input bool   InpEnrichFallbackTradeWithObjectLevels = true;
input bool   InpReanchorObjectLevelsToFill = true; // Preserve object distances but anchor them to real market fill/entry.

input int    InpIndP1 = 60;
input int    InpIndP2 = 5;
input int    InpIndP3 = 3;
input int    InpIndP4 = 7;
input double InpIndP5 = 0.0;
input double InpIndP6 = 70.0;
input double InpIndP7 = 30.0;
input int    InpIndP8 = 10;
input int    InpIndP9 = 0;
input int    InpIndP10 = 0;
input int    InpIndP11 = 15;
input int    InpIndP12 = 0;
input int    InpIndP13 = 0;
input int    InpIndP14 = 0;
input bool   InpIndP15 = true;
input bool   InpIndP16 = true;
input bool   InpIndP17 = true;
input int    InpIndP18 = 50;

input bool   InpDirectEnabled = true;
input double InpManualLot = 1.0;
input int    InpMagic = 42061301;
input bool   InpUseSymbolTimeframeMagic = true;
input int    InpSlippage = 30;
input int    InpMaxMarketEntryDriftPoints = 50; // If market is worse than arrow by more than this, place limit at arrow price. 0=always market.
// New name intentionally avoids old .set files that may still contain InpUsePendingAtSignalOnDrift=true.
input bool   InpPendingOnDriftStartup = false;
input int    InpPendingExpiryMinutes = 30;
input int    InpBrokerStopSafetyPoints = 3;
input int    InpMaxSpreadPoints = 0;      // 0=off
input string InpAllowedWindowsGmt = "";   // empty=24/7, HH:MM-HH:MM,...
input string InpNoTradeWindowsGmt = "21:55-22:10";
input bool   InpCloseOppositeOnSignal = true;
input bool   InpBlockSameDirectionOpen = true;

input int    InpRiskAtrPeriod = 14; // unused in Gann object-level mode
input double InpRiskAtrMult = 1.50;
input bool   InpUseStructuralSwingStop = true;
input int    InpSwingLookbackBars = 80;
input int    InpSwingLeftBars = 3;
input int    InpSwingRightBars = 2;
input int    InpSwingAtrPeriod = 14;
input double InpSwingMinProminenceAtr = 0.75;
input double InpSwingMinDepartureAtr = 1.00;
input double InpSwingBufferAtr = 0.20;
input double InpFinalRiskScalePct = 100.0; // Applies only to calculated fallback levels; object SL/TP levels are never scaled.
input int    InpTargetTpIndex = 2;        // 0=broker TP off, 1..3 full close target leg
input int    InpHalfBeTpIndex = 0;        // 0=off, 1..3 half close + SL->BE leg

input bool   InpShowDashboard = true;
input int    InpDashboardX = 18;
input int    InpDashboardY = 28;

input bool   InpAdvancedAccountRiskEnabled = true;
input bool   InpFtmoModeDefault = false;
input bool   InpRiskLotOnlyModeDefault = false;
input bool   InpAutoLotByRisk = true;
input double InpAccountRiskPerTradePct = 1.0;
input int    InpAccountRiskDailyAtrPeriod = 14;
input double InpAccountRiskDailyAtrExposurePct = 2.0; // Caps one trade's expected D1 ATR move, equalizing SOL/DOGE/ETH-style symbols.
input double InpMaxPortfolioRiskPct = 4.0;
input double InpDailyLossLimitPct = 0.0;  // 0=off
input double InpMaxDrawdownPct = 0.0;     // 0=off
input double InpMaxMarginUsagePct = 40.0;
input int    InpMinConcurrentTradeSlots = 5; // 0=off. Caps one trade's incremental margin so the account can still run multiple setups.
input double InpMaxSingleTradeMarginPct = 0.0; // 0=auto from slots. Example: 20 means one new trade may consume at most 20% equity margin.
input double InpInitialBalanceOverride = 10000.0;
input int    InpDayResetHourGmt = 0;
input bool   InpRiskScopeByMagic = true;
input bool   InpLiquidateOnBreach = false;
input int    InpRiskAuditSeconds = 60;

input bool   InpEnableAudit = false;
input int    InpPositionProbeSeconds = 30;
input int    InpLifecycleAuditSeconds = 10;

string   g_prefix;
bool     g_eaEnabled;
bool     g_collapsed = false;
double   g_lotRuntime;
int      g_maxSpreadRuntime;
double   g_finalScaleRuntime;
int      g_targetTpRuntime;
int      g_halfTpRuntime;
bool     g_pendingOnDriftRuntime;
bool     g_auditRuntime;
bool     g_ftmoMode;
bool     g_riskLotOnlyMode;
string   g_allowedWindowsRuntime;
string   g_noTradeWindowsRuntime;
string   g_lastEventId = "";
string   g_lastSignalDir = "-";
datetime g_lastSignalTime = 0;
double   g_lastSignalPrice = 0.0;
datetime g_lastScanTs = 0;
datetime g_lastRiskAuditTs = 0;
datetime g_lastProbeTs = 0;
datetime g_lastLifecycleAuditTs = 0;
bool     g_lastGeometryUsedFallback = false;

int OnInit()
{
   g_prefix = "GANN_" + IntegerToString((int)ChartID()) + "_";
   g_eaEnabled = InpDirectEnabled;
   g_lotRuntime = InpManualLot;
   g_maxSpreadRuntime = InpMaxSpreadPoints;
   g_finalScaleRuntime = MathMax(10.0, MathMin(200.0, InpFinalRiskScalePct));
   g_targetTpRuntime = MathMax(0, MathMin(3, InpTargetTpIndex));
   g_halfTpRuntime = MathMax(0, MathMin(3, InpHalfBeTpIndex));
   g_pendingOnDriftRuntime = InpPendingOnDriftStartup;
   g_auditRuntime = InpEnableAudit;
   g_ftmoMode = InpFtmoModeDefault;
   g_riskLotOnlyMode = (!g_ftmoMode && InpRiskLotOnlyModeDefault);
   g_allowedWindowsRuntime = InpAllowedWindowsGmt;
   g_noTradeWindowsRuntime = InpNoTradeWindowsGmt;
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   EventSetTimer(MathMax(1, InpPollSeconds));

   if(InpShowDashboard) DashboardCreate();
   Audit("init", "", 0, "", 0, 0, 0, 0, "build=" + BUILD_TAG + " indicator=" + InpIndicatorName + " pending_on_drift=" + (g_pendingOnDriftRuntime ? "true" : "false"), 0, "");
   RiskAudit("init", "build=" + BUILD_TAG + " pending_on_drift=" + (g_pendingOnDriftRuntime ? "true" : "false"));

   if(!InpTradeLatestSignalOnAttach)
   {
      string dir, eid; int sh, buf; double px; datetime bt;
      if(FindLatestSignal(dir, sh, buf, px, bt, eid))
      {
         g_lastEventId = eid;
         g_lastSignalDir = dir;
         g_lastSignalTime = bt;
         g_lastSignalPrice = px;
         Audit("startup_baseline", eid, 0, dir, 0, px, 0, 0, "shift=" + IntegerToString(sh) + " buffer=" + IntegerToString(buf), 0, "old signal ignored on attach");
      }
   }
   Print("GannMadeEasyBridge BUILD=", BUILD_TAG, " indicator=", InpIndicatorName, " buyBuffer=", InpBuyBuffer, " sellBuffer=", InpSellBuffer, " pendingOnDrift=", (g_pendingOnDriftRuntime ? "true" : "false"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
   DeleteTradeLevels();
   Audit("deinit", "", 0, "", 0, 0, 0, 0, "reason=" + IntegerToString(reason), 0, "");
}

void OnTick()
{
   if(InpScanOnTick) ProcessSignals("tick");
   ManagePositions();
   MaybeLifecycleAudit();
   if(InpShowDashboard) DashboardUpdate();
}

void OnTimer()
{
   ProcessSignals("timer");
   ManagePositions();
   MaybeLifecycleAudit();
   MaybeProbe();
   MaybeRiskAudit();
   if(InpShowDashboard) DashboardUpdate();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DRAG)
   {
      string uname = StringUpperCopy(sparam);
      if(StringFind(uname, StringUpperCopy(InpBuySignalObjectName)) >= 0 || StringFind(uname, StringUpperCopy(InpSellSignalObjectName)) >= 0)
         ProcessSignals("object_event");
      return;
   }
   if(id != CHARTEVENT_OBJECT_CLICK && id != CHARTEVENT_OBJECT_ENDEDIT) return;
   if(sparam == Obj("toggle"))
   {
      g_eaEnabled = !g_eaEnabled;
      Audit("dashboard_toggle", "", 0, "", 0, 0, 0, 0, g_eaEnabled ? "enabled" : "disabled", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("collapse"))
   {
      g_collapsed = !g_collapsed;
      DashboardCreate();
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("drift"))
   {
      g_pendingOnDriftRuntime = !g_pendingOnDriftRuntime;
      Audit("dashboard_drift_toggle", "", 0, "", 0, 0, 0, 0, g_pendingOnDriftRuntime ? "pending_on_drift=true" : "pending_on_drift=false", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("audit"))
   {
      g_auditRuntime = !g_auditRuntime;
      Print("GannMadeEasyBridge audit logging ", g_auditRuntime ? "enabled" : "disabled");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("ftmo"))
   {
      g_ftmoMode = !g_ftmoMode;
      if(g_ftmoMode) g_riskLotOnlyMode = false;
      Audit("dashboard_ftmo_toggle", "", 0, "", 0, 0, 0, 0, g_ftmoMode ? "FTMO_ON" : "FTMO_OFF", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("risklot"))
   {
      g_riskLotOnlyMode = !g_riskLotOnlyMode;
      if(g_riskLotOnlyMode) g_ftmoMode = false;
      Audit("dashboard_risklot_toggle", "", 0, "", 0, 0, 0, 0, g_riskLotOnlyMode ? "RISKLOT_ON" : "RISKLOT_OFF", 0, "");
      DashboardUpdate();
      return;
   }
   if(sparam == Obj("apply") || id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      ApplyDashboardInputs();
      DashboardUpdate();
   }
}

string Obj(string name) { return g_prefix + name; }

void ProcessSignals(string reason)
{
   datetime now = TimeCurrent();
   if(reason == "timer" && now == g_lastScanTs) return;
   g_lastScanTs = now;

   string dir, eid; int sh, buf; double sigPx; datetime barTime;
   if(!FindLatestSignal(dir, sh, buf, sigPx, barTime, eid)) return;

   g_lastSignalDir = dir;
   g_lastSignalTime = barTime;
   g_lastSignalPrice = sigPx;
   if(eid == g_lastEventId) return;
   g_lastEventId = eid;

   RefreshRates();
   double liveBid = Bid;
   double liveAsk = Ask;
   int spreadNow = CurrentSpreadPoints();
   Audit("signal_detected", eid, 0, dir, 0, sigPx, 0, 0, "reason=" + reason + " shift=" + IntegerToString(sh) + " buffer=" + IntegerToString(buf) + " bar=" + TimeToString(barTime, TIME_DATE|TIME_SECONDS) + " bid=" + PriceText(liveBid) + " ask=" + PriceText(liveAsk) + " spread_points=" + IntegerToString(spreadNow), 0, "");
   ExecuteSignal(dir, eid, sigPx, sh, buf);
}

bool FindLatestSignal(string &dir, int &shift, int &buffer, double &price, datetime &barTime, string &eventId)
{
   bool found = false;
   datetime bestTime = 0;
   string bestDir = "";
   double bestPrice = 0.0;
   string bestName = "";

   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, -1, -1);
      string up = StringUpperCopy(InpBuySignalObjectName);
      string dn = StringUpperCopy(InpSellSignalObjectName);
      string uname = StringUpperCopy(name);
      string d = "";
      if(StringFind(uname, up) >= 0) d = "BUY";
      if(StringFind(uname, dn) >= 0) d = "SELL";
      if(d == "") continue;

      int type = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(type != OBJ_ARROW && type != OBJ_TEXT && type != OBJ_LABEL) continue;
      datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME1);
      double p = ObjectGetDouble(0, name, OBJPROP_PRICE1);
      if(t <= 0 || p <= 0.0) continue;
      if(iBarShift(Symbol(), Period(), t, false) > InpMaxSignalAgeBars) continue;
      if(!found || t > bestTime)
      {
         found = true;
         bestTime = t;
         bestDir = d;
         bestPrice = p;
         bestName = name;
      }
   }

   if(!found) return false;
   dir = bestDir;
   barTime = bestTime;
   price = bestPrice;
   shift = MathMax(0, iBarShift(Symbol(), Period(), barTime, false));
   buffer = 0;
   eventId = Symbol() + "|" + IntegerToString(Period()) + "|gann_object|" + dir + "|" + IntegerToString((int)barTime) + "|" + bestName + "|" + DoubleToString(price, Digits);
   return true;
}

double ReadBuffer(int buffer, int shift)
{
   ResetLastError();
   return iCustom(Symbol(), Period(), InpIndicatorName,
                  InpIndP1, InpIndP2, InpIndP3, InpIndP4, InpIndP5, InpIndP6, InpIndP7, InpIndP8, InpIndP9,
                  InpIndP10, InpIndP11, InpIndP12, InpIndP13, InpIndP14, InpIndP15, InpIndP16, InpIndP17, InpIndP18,
                  buffer, shift);
}

bool IsSignalValue(double v)
{
   if(v == EMPTY_VALUE) return false;
   if(MathAbs(v - EMPTY_SENTINEL) < 0.1) return false;
   if(MathAbs(v) < Point * 0.5) return false;
   if(v < 0 || v > 100000000.0) return false;
   return true;
}

string StringUpperCopy(string s)
{
   string out = s;
   StringToUpper(out);
   return out;
}

bool FindLevelPrice(string wantedName, double &price, string &detail)
{
   price = 0.0;
   detail = "";
   if(ObjectFind(0, wantedName) >= 0)
   {
      double p = ObjectGetDouble(0, wantedName, OBJPROP_PRICE1);
      if(p > 0.0)
      {
         price = p;
         detail = wantedName + ":" + PriceText(p);
         return true;
      }
   }

   string wanted = StringUpperCopy(wantedName);
   string fallbackName = "";
   double fallbackPrice = 0.0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, -1, -1);
      string uname = StringUpperCopy(name);
      if(StringFind(uname, wanted) < 0) continue;
      double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE1);
      if(p2 <= 0.0) continue;
      int type = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(type == OBJ_TREND || type == OBJ_HLINE)
      {
         price = p2;
         detail = name + ":" + PriceText(p2);
         return true;
      }
      if(fallbackPrice <= 0.0)
      {
         fallbackName = name;
         fallbackPrice = p2;
      }
   }
   if(fallbackPrice > 0.0)
   {
      price = fallbackPrice;
      detail = fallbackName + ":" + PriceText(fallbackPrice);
      return true;
   }
   return false;
}

double TickSizePrice()
{
   double tick = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tick <= 0.0) tick = Point;
   if(tick < Point * 0.5) tick = Point;
   return tick;
}

double NormalizePriceToTick(double price)
{
   if(price <= 0.0) return 0.0;
   double tick = TickSizePrice();
   if(tick <= 0.0) tick = Point;
   return NormalizeDouble(MathRound(price / tick) * tick, Digits);
}

double BrokerMinStopDistance()
{
   double stop = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double freeze = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double safety = MathMax(0, InpBrokerStopSafetyPoints) * Point;
   return MathMax(MathMax(stop, freeze) + safety, MathMax(Point, TickSizePrice()));
}

bool ValidateDirectionLevels(int logicalType, double entry, double sl, double tp, string &detail)
{
   if(logicalType == OP_BUY)
   {
      if(sl > 0.0 && sl >= entry)
      {
         detail = "buy_sl_not_below_entry entry=" + PriceText(entry) + " sl=" + PriceText(sl);
         return false;
      }
      if(tp > 0.0 && tp <= entry)
      {
         detail = "buy_tp_not_above_entry entry=" + PriceText(entry) + " tp=" + PriceText(tp);
         return false;
      }
   }
   else
   {
      if(sl > 0.0 && sl <= entry)
      {
         detail = "sell_sl_not_above_entry entry=" + PriceText(entry) + " sl=" + PriceText(sl);
         return false;
      }
      if(tp > 0.0 && tp >= entry)
      {
         detail = "sell_tp_not_below_entry entry=" + PriceText(entry) + " tp=" + PriceText(tp);
         return false;
      }
   }
   return true;
}

bool PrepareBrokerOrderLevels(int sendType, int logicalType, double &entry, double &sl, double &tp, string &detail)
{
   RefreshRates();
   double minDist = BrokerMinStopDistance();
   double rawEntry = entry, rawSl = sl, rawTp = tp;
   double bid = Bid, ask = Ask;

   if(sendType == OP_BUY)
   {
      entry = ask;
      if(sl > 0.0 && sl > bid - minDist) sl = bid - minDist;
      if(tp > 0.0 && tp < bid + minDist) tp = bid + minDist;
   }
   else if(sendType == OP_SELL)
   {
      entry = bid;
      if(sl > 0.0 && sl < ask + minDist) sl = ask + minDist;
      if(tp > 0.0 && tp > ask - minDist) tp = ask - minDist;
   }
   else if(sendType == OP_BUYLIMIT)
   {
      if(entry > ask - minDist) entry = ask - minDist;
      if(sl > 0.0 && sl > entry - minDist) sl = entry - minDist;
      if(tp > 0.0 && tp < entry + minDist) tp = entry + minDist;
   }
   else if(sendType == OP_SELLLIMIT)
   {
      if(entry < bid + minDist) entry = bid + minDist;
      if(sl > 0.0 && sl < entry + minDist) sl = entry + minDist;
      if(tp > 0.0 && tp > entry - minDist) tp = entry - minDist;
   }

   entry = NormalizePriceToTick(entry);
   sl = NormalizePriceToTick(sl);
   tp = NormalizePriceToTick(tp);

   if(sl <= 0.0)
   {
      detail = "missing_stop_after_broker_guard";
      return false;
   }
   string dirDetail;
   if(!ValidateDirectionLevels(logicalType, entry, sl, tp, dirDetail))
   {
      detail = dirDetail + " raw_entry=" + PriceText(rawEntry) + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) + " min_dist=" + PriceText(minDist);
      return false;
   }

   bool changed = (MathAbs(entry - rawEntry) > Point * 0.5 || MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(tp - rawTp) > Point * 0.5);
   detail = "broker_stop_guard changed=" + (changed ? "true" : "false") +
            " raw_entry=" + PriceText(rawEntry) + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) +
            " final_entry=" + PriceText(entry) + " final_sl=" + PriceText(sl) + " final_tp=" + PriceText(tp) +
            " bid=" + PriceText(bid) + " ask=" + PriceText(ask) +
            " stop_points=" + DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL), 0) +
            " freeze_points=" + DoubleToString(MarketInfo(Symbol(), MODE_FREEZELEVEL), 0) +
            " safety_points=" + IntegerToString(MathMax(0, InpBrokerStopSafetyPoints)) +
            " tick=" + PriceText(TickSizePrice());
   return true;
}

bool PrepareBrokerModifyStops(int logicalType, double openPrice, double &sl, double &tp, string &detail)
{
   RefreshRates();
   double minDist = BrokerMinStopDistance();
   double rawSl = sl, rawTp = tp;
   double bid = Bid, ask = Ask;

   if(logicalType == OP_BUY)
   {
      if(sl > 0.0 && sl > bid - minDist) sl = bid - minDist;
      if(tp > 0.0 && tp < bid + minDist) tp = bid + minDist;
   }
   else
   {
      if(sl > 0.0 && sl < ask + minDist) sl = ask + minDist;
      if(tp > 0.0 && tp > ask - minDist) tp = ask - minDist;
   }

   sl = NormalizePriceToTick(sl);
   tp = NormalizePriceToTick(tp);

   string dirDetail;
   if(!ValidateDirectionLevels(logicalType, openPrice, sl, tp, dirDetail))
   {
      detail = dirDetail + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) + " min_dist=" + PriceText(minDist);
      return false;
   }
   bool changed = (MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(tp - rawTp) > Point * 0.5);
   detail = "broker_modify_guard changed=" + (changed ? "true" : "false") +
            " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTp) +
            " final_sl=" + PriceText(sl) + " final_tp=" + PriceText(tp) +
            " bid=" + PriceText(bid) + " ask=" + PriceText(ask) +
            " min_dist=" + PriceText(minDist);
   return true;
}

void ExecuteSignal(string dir, string eventId, double signalPx, int shift, int buffer)
{
   RefreshRates();
   int type = (dir == "BUY") ? OP_BUY : OP_SELL;
   double liveBid = Bid;
   double liveAsk = Ask;
   int spreadNow = CurrentSpreadPoints();
   double marketEntry = (type == OP_BUY) ? liveAsk : liveBid;
   double entry = marketEntry;
   bool worseThanSignal = (type == OP_BUY && marketEntry > signalPx) || (type == OP_SELL && marketEntry < signalPx);
   double driftPoints = (signalPx > 0.0) ? MathAbs(marketEntry - signalPx) / Point : 0.0;
   bool usePending = (g_pendingOnDriftRuntime && InpMaxMarketEntryDriftPoints > 0 && worseThanSignal && driftPoints > InpMaxMarketEntryDriftPoints);
   if(usePending) entry = signalPx;
   double sl, tp1, tp2, tp3;
   string geom;
   if(!BuildGeometry(type, entry, signalPx, shift, sl, tp1, tp2, tp3, geom))
   {
      Audit("trade_blocked_geometry", eventId, 0, dir, 0, entry, sl, 0, geom, 0, "");
      return;
   }
   double target = TpByIndex(g_targetTpRuntime, tp1, tp2, tp3);
   double half = TpByIndex(g_halfTpRuntime, tp1, tp2, tp3);

   int sendType = type;
   datetime expiry = 0;
   if(usePending)
   {
      sendType = (type == OP_BUY) ? OP_BUYLIMIT : OP_SELLLIMIT;
      expiry = TimeCurrent() + MathMax(1, InpPendingExpiryMinutes) * 60;
   }

   double rawPlannedEntry = entry, rawSl = sl, rawTarget = target;
   string brokerGuard;
   if(!PrepareBrokerOrderLevels(sendType, type, entry, sl, target, brokerGuard))
   {
      Audit("trade_blocked_broker_stops", eventId, 0, dir, 0, rawPlannedEntry, rawSl, rawTarget, brokerGuard + " " + geom, 0, "");
      return;
   }
   if(MathAbs(entry - rawPlannedEntry) > Point * 0.5 || MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(target - rawTarget) > Point * 0.5)
   {
      if(g_targetTpRuntime == 1) tp1 = target;
      if(g_targetTpRuntime == 2) tp2 = target;
      if(g_targetTpRuntime == 3) tp3 = target;
      if(g_halfTpRuntime == g_targetTpRuntime) half = target;
      Audit("broker_stop_adjusted", eventId, 0, dir, 0, entry, sl, target, brokerGuard, 0, "raw_entry=" + PriceText(rawPlannedEntry) + " raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTarget));
   }

   Audit("signal_received", eventId, 0, dir, g_lotRuntime, signalPx, sl, target, "source=chart_object shift=" + IntegerToString(shift) + " bid=" + PriceText(liveBid) + " ask=" + PriceText(liveAsk) + " spread_points=" + IntegerToString(spreadNow) + " market_entry=" + PriceText(marketEntry) + " planned_entry=" + PriceText(entry) + " drift_points=" + DoubleToString(driftPoints, 1) + " pending_at_signal=" + (usePending ? "true" : "false") + " " + geom + " " + brokerGuard + " half_trigger=" + PriceText(half), 0, "");

   if(!g_eaEnabled) { Audit("trade_blocked_disabled", eventId, 0, dir, 0, entry, sl, target, "ea_disabled", 0, ""); return; }
   if(!IsInAllowedWindow(TimeGMT(), g_allowedWindowsRuntime) || IsInNoTradeWindow(TimeGMT(), g_noTradeWindowsRuntime))
   {
      Audit("trade_blocked_window", eventId, 0, dir, 0, entry, sl, target, "allowed='" + g_allowedWindowsRuntime + "' no_trade='" + g_noTradeWindowsRuntime + "'", 0, "");
      return;
   }
   int spread = CurrentSpreadPoints();
   if(g_maxSpreadRuntime > 0 && spread > g_maxSpreadRuntime)
   {
      Audit("trade_blocked_spread", eventId, 0, dir, 0, entry, sl, target, "spread=" + IntegerToString(spread) + " max=" + IntegerToString(g_maxSpreadRuntime), 0, "");
      return;
   }
   if(InpBlockSameDirectionOpen && HasOpenDirection(type))
   {
      Audit("trade_blocked_same_direction", eventId, 0, dir, 0, entry, sl, target, "existing same direction order", 0, "");
      return;
   }
   if(InpCloseOppositeOnSignal) CloseOpposite(type, eventId);

   string lotDetail;
   double lot = ResolveLot(entry, sl, type, g_halfTpRuntime > 0, lotDetail);
   if(lot <= 0)
   {
      RiskAudit("lot_blocked", "event=" + eventId + " " + lotDetail);
      Audit("trade_blocked_risk", eventId, 0, dir, 0, entry, sl, target, lotDetail, 0, "");
      return;
   }

   int ticket = OrderSend(Symbol(), sendType, lot, NormalizePriceToTick(entry), InpSlippage, NormalizePriceToTick(sl), NormalizePriceToTick(target), "GannBridge " + dir, EffectiveMagic(), expiry, (type == OP_BUY ? clrLime : clrTomato));
   int err = GetLastError();
   if(ticket > 0)
   {
      if(OrderSelect(ticket, SELECT_BY_TICKET)) entry = OrderOpenPrice();
      StoreTicket(ticket, tp1, tp2, tp3, half, g_halfTpRuntime, g_targetTpRuntime, g_lastGeometryUsedFallback);
      Audit(usePending ? "pending_order_sent" : "order_sent", eventId, ticket, dir, lot, entry, sl, target, "ticket=" + IntegerToString(ticket) + " type=" + (usePending ? "limit_at_signal" : "market") + " market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail + " levels=" + (g_lastGeometryUsedFallback ? "fallback_calculated" : "object") + " tp1=" + PriceText(tp1) + " tp2=" + PriceText(tp2) + " tp3=" + PriceText(tp3), 0, "");
      RiskAudit("lot_selected", "event=" + eventId + " ticket=" + IntegerToString(ticket) + " lot=" + DoubleToString(lot, 3) + " " + lotDetail);
      if(g_lastGeometryUsedFallback) DrawCalculatedFallbackLevels(ticket, sl, tp1, tp2, tp3);
      DrawTradeLevels();
   }
   else
   {
      if(err == 130 && TrySecondLevelStopGuardOpen(eventId, dir, sendType, type, lot, entry, sl, target, tp1, tp2, tp3, half, marketEntry, driftPoints, lotDetail, usePending))
         return;
      Audit(usePending ? "pending_order_failed" : "order_failed", eventId, 0, dir, lot, entry, sl, target, "err=" + IntegerToString(err) + " market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail, 0, "");
   }
}

bool TrySecondLevelStopGuardOpen(string eventId, string dir, int sendType, int type, double lot, double entry, double sl, double target,
                                 double tp1, double tp2, double tp3, double half, double marketEntry, double driftPoints,
                                 string lotDetail, bool usePending)
{
   if(sendType != OP_BUY && sendType != OP_SELL)
   {
      Audit(usePending ? "pending_order_failed" : "order_failed", eventId, 0, dir, lot, entry, sl, target,
            "err=130 second_level_skipped_non_market market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail, 0, "");
      return false;
   }

   RefreshRates();
   double nakedEntry = (type == OP_BUY) ? Ask : Bid;
   int ticket = OrderSend(Symbol(), type, lot, NormalizePriceToTick(nakedEntry), InpSlippage, 0, 0,
                          "GannBridge " + dir + " guarded", EffectiveMagic(), 0, (type == OP_BUY ? clrLime : clrTomato));
   int openErr = GetLastError();
   if(ticket <= 0)
   {
      Audit("order_failed_stopguard_open", eventId, 0, dir, lot, nakedEntry, sl, target,
            "initial_err=130 fallback_err=" + IntegerToString(openErr) + " market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail, 0, "");
      return false;
   }

   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Audit("order_sent_stopguard_select_failed", eventId, ticket, dir, lot, nakedEntry, sl, target,
            "initial_err=130 ticket_opened_but_select_failed", 0, "");
      return true;
   }

   double openPrice = OrderOpenPrice();
   StoreTicket(ticket, tp1, tp2, tp3, half, g_halfTpRuntime, g_targetTpRuntime, g_lastGeometryUsedFallback);
   Audit("order_sent_stopguard_unprotected", eventId, ticket, dir, lot, openPrice, 0, 0,
         "initial_err=130 naked_market_opened; attempting immediate protective_modify market_entry=" + PriceText(marketEntry) + " drift_points=" + DoubleToString(driftPoints, 1) + " " + lotDetail,
         OrderProfit(), "raw_sl=" + PriceText(sl) + " raw_tp=" + PriceText(target));

   double modSl = sl;
   double modTp = target;
   string modifyGuard;
   bool canModify = PrepareBrokerModifyStops(type, openPrice, modSl, modTp, modifyGuard);
   if(canModify)
   {
      bool modOk = OrderModify(ticket, openPrice, NormalizePriceToTick(modSl), NormalizePriceToTick(modTp), 0, clrDodgerBlue);
      int modErr = GetLastError();
      if(modOk)
      {
         if(g_targetTpRuntime == 1) tp1 = modTp;
         if(g_targetTpRuntime == 2) tp2 = modTp;
         if(g_targetTpRuntime == 3) tp3 = modTp;
         if(g_halfTpRuntime == g_targetTpRuntime) half = modTp;
         StoreTicket(ticket, tp1, tp2, tp3, half, g_halfTpRuntime, g_targetTpRuntime, g_lastGeometryUsedFallback);
         Audit("order_stopguard_modify_done", eventId, ticket, dir, lot, openPrice, modSl, modTp,
               modifyGuard + " protective_stops_attached " + lotDetail, OrderProfit(), "initial_order_err=130");
         RiskAudit("lot_selected", "event=" + eventId + " ticket=" + IntegerToString(ticket) + " lot=" + DoubleToString(lot, 3) + " stopguard=true " + lotDetail);
         if(g_lastGeometryUsedFallback) DrawCalculatedFallbackLevels(ticket, modSl, tp1, tp2, tp3);
         DrawTradeLevels();
         return true;
      }
      Audit("order_stopguard_modify_failed", eventId, ticket, dir, lot, openPrice, modSl, modTp,
            "err=" + IntegerToString(modErr) + " " + modifyGuard, OrderProfit(), "emergency_close_next");
   }
   else
   {
      Audit("order_stopguard_modify_blocked", eventId, ticket, dir, lot, openPrice, modSl, modTp,
            modifyGuard, OrderProfit(), "emergency_close_next");
   }

   RefreshRates();
   double closePx = (type == OP_BUY) ? Bid : Ask;
   bool closeOk = OrderClose(ticket, OrderLots(), closePx, InpSlippage, clrRed);
   int closeErr = GetLastError();
   if(closeOk)
   {
      TicketGVSet(ticket, "CLOSED", 1.0);
      Audit("order_stopguard_emergency_close_done", eventId, ticket, dir, lot, closePx, 0, 0,
            "protective_modify_failed_or_blocked; unprotected_position_closed", OrderProfit(), "");
   }
   else
   {
      Audit("order_stopguard_emergency_close_failed", eventId, ticket, dir, lot, closePx, 0, 0,
            "CRITICAL_UNPROTECTED err=" + IntegerToString(closeErr) + " protective_modify_failed_or_blocked", OrderProfit(), "");
   }
   return true;
}

bool BuildGeometry(int type, double entry, double signalPx, int signalShift, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   g_lastGeometryUsedFallback = false;
   string objectDetail = "";
   if(BuildObjectGeometry(type, entry, signalPx, sl, tp1, tp2, tp3, objectDetail))
   {
      detail = objectDetail;
      return true;
   }
   if(!InpAllowCalculatedFallbackLevels)
   {
      detail = objectDetail;
      return false;
   }
   string fallbackDetail = "";
   if(BuildCalculatedFallbackGeometry(type, entry, signalShift, sl, tp1, tp2, tp3, fallbackDetail))
   {
      g_lastGeometryUsedFallback = true;
      detail = "fallback_calculated reason='" + objectDetail + "' " + fallbackDetail;
      return true;
   }
   detail = "object_failed='" + objectDetail + "' fallback_failed='" + fallbackDetail + "'";
   return false;
}

bool BuildObjectGeometry(int type, double entry, double signalPx, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   string d0, d1, d2, d3;
   if(!FindLevelPrice(InpStopLevelObjectName, sl, d0))
   {
      detail = "missing_stop_level object='" + InpStopLevelObjectName + "'";
      return false;
   }
   if(!FindLevelPrice(InpTargetLevel1ObjectName, tp1, d1))
   {
      detail = "missing_tp1_level object='" + InpTargetLevel1ObjectName + "'";
      return false;
   }
   if(!FindLevelPrice(InpTargetLevel2ObjectName, tp2, d2)) tp2 = 0.0;
   if(!FindLevelPrice(InpTargetLevel3ObjectName, tp3, d3)) tp3 = 0.0;

   double anchor = (signalPx > 0.0) ? signalPx : entry;
   if(type == OP_BUY)
   {
      if(!(sl < anchor && tp1 > anchor))
      {
         detail = "invalid_buy_object_geometry anchor=" + PriceText(anchor) + " entry=" + PriceText(entry) + " sl=" + PriceText(sl) + " tp1=" + PriceText(tp1);
         return false;
      }
   }
   else
   {
      if(!(sl > anchor && tp1 < anchor))
      {
         detail = "invalid_sell_object_geometry anchor=" + PriceText(anchor) + " entry=" + PriceText(entry) + " sl=" + PriceText(sl) + " tp1=" + PriceText(tp1);
         return false;
      }
   }

   // If TP2/TP3 are absent or malformed, keep TP1 as safe fallback for those legs.
   if(tp2 <= 0.0 || (type == OP_BUY && tp2 <= anchor) || (type == OP_SELL && tp2 >= anchor)) tp2 = tp1;
   if(tp3 <= 0.0 || (type == OP_BUY && tp3 <= anchor) || (type == OP_SELL && tp3 >= anchor)) tp3 = tp2;

   double rawSl = sl, rawTp1 = tp1, rawTp2 = tp2, rawTp3 = tp3;
   bool reanchored = false;
   if(InpReanchorObjectLevelsToFill && MathAbs(entry - anchor) > Point * 0.5)
   {
      if(type == OP_BUY)
      {
         sl = entry - MathAbs(anchor - rawSl);
         tp1 = entry + MathAbs(rawTp1 - anchor);
         tp2 = entry + MathAbs(rawTp2 - anchor);
         tp3 = entry + MathAbs(rawTp3 - anchor);
      }
      else
      {
         sl = entry + MathAbs(rawSl - anchor);
         tp1 = entry - MathAbs(anchor - rawTp1);
         tp2 = entry - MathAbs(anchor - rawTp2);
         tp3 = entry - MathAbs(anchor - rawTp3);
      }
      reanchored = true;
   }

   if(type == OP_BUY && !(sl < entry && tp1 > entry))
   {
      detail = "invalid_buy_object_reanchored anchor=" + PriceText(anchor) + " entry=" + PriceText(entry) + " sl=" + PriceText(sl) + " tp1=" + PriceText(tp1);
      return false;
   }
   if(type == OP_SELL && !(sl > entry && tp1 < entry))
   {
      detail = "invalid_sell_object_reanchored anchor=" + PriceText(anchor) + " entry=" + PriceText(entry) + " sl=" + PriceText(sl) + " tp1=" + PriceText(tp1);
      return false;
   }

   sl = NormalizeDouble(sl, Digits);
   tp1 = NormalizeDouble(tp1, Digits);
   tp2 = NormalizeDouble(tp2, Digits);
   tp3 = NormalizeDouble(tp3, Digits);
   detail = "object_levels anchor=" + PriceText(anchor) + " raw_stop=" + PriceText(rawSl) + " raw_tp1=" + PriceText(rawTp1) + " raw_tp2=" + PriceText(rawTp2) + " raw_tp3=" + PriceText(rawTp3) + " reanchored=" + (reanchored ? "true" : "false") + " stop=" + d0 + " tp1=" + d1 + " tp2=" + d2 + " tp3=" + d3;
   return true;
}

bool BuildCalculatedFallbackGeometry(int type, double entry, int signalShift, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   int atrShift = MathMax(1, signalShift);
   double atr = iATR(Symbol(), Period(), InpRiskAtrPeriod, atrShift);
   if(atr <= Point * 2.0) atr = iATR(Symbol(), Period(), InpRiskAtrPeriod, 1);
   if(atr <= Point * 2.0)
   {
      detail = "atr_unavailable";
      return false;
   }

   double risk = MathMax(Point * 10.0, atr * MathMax(0.1, InpRiskAtrMult));
   sl = (type == OP_BUY) ? entry - risk : entry + risk;
   detail = "base_atr=" + DoubleToString(atr, Digits) + " atr_mult=" + DoubleToString(InpRiskAtrMult, 2);

   if(InpUseStructuralSwingStop)
   {
      double swingSl, swingRisk;
      string swingDetail;
      if(FindStructuralSwingStop(type, signalShift, entry, swingSl, swingRisk, swingDetail))
      {
         if(swingRisk > risk)
         {
            risk = swingRisk;
            sl = swingSl;
            detail += " structural=wider " + swingDetail;
         }
         else detail += " structural=ignored_narrower " + swingDetail;
      }
      else detail += " structural=none " + swingDetail;
   }

   double scale = MathMax(10.0, MathMin(200.0, g_finalScaleRuntime)) / 100.0;
   risk = MathAbs(entry - sl) * scale;
   if(type == OP_BUY)
   {
      sl = entry - risk;
      tp1 = entry + risk;
      tp2 = entry + 2.0 * risk;
      tp3 = entry + 3.0 * risk;
   }
   else
   {
      sl = entry + risk;
      tp1 = entry - risk;
      tp2 = entry - 2.0 * risk;
      tp3 = entry - 3.0 * risk;
   }

   if(type == OP_BUY && !(sl < entry && tp1 > entry)) return false;
   if(type == OP_SELL && !(sl > entry && tp1 < entry)) return false;
   sl = NormalizeDouble(sl, Digits);
   tp1 = NormalizeDouble(tp1, Digits);
   tp2 = NormalizeDouble(tp2, Digits);
   tp3 = NormalizeDouble(tp3, Digits);
   detail += " final_scale_pct=" + DoubleToString(g_finalScaleRuntime, 1) + " final_risk=" + DoubleToString(risk, Digits);
   return true;
}

bool FindStructuralSwingStop(int type, int signalShift, double entry, double &outSl, double &outRisk, string &detail)
{
   int left = MathMax(2, InpSwingLeftBars);
   int right = MathMax(1, InpSwingRightBars);
   int start = MathMax(right + 1, signalShift + right);
   int end = MathMin(Bars - left - 2, signalShift + MathMax(left + right + 5, InpSwingLookbackBars));
   double bestRisk = 0, bestSl = 0; int bestShift = -1;

   for(int s = start; s <= end; s++)
   {
      double atr = iATR(Symbol(), Period(), InpSwingAtrPeriod, s);
      if(atr <= Point * 2) continue;
      bool pivot = true;
      if(type == OP_BUY)
      {
         double low = Low[s];
         for(int a = 1; a <= left; a++) if(Low[s + a] <= low) { pivot = false; break; }
         if(!pivot) continue;
         for(int b = 1; b <= right; b++) if(Low[s - b] < low) { pivot = false; break; }
         if(!pivot) continue;
         double prom = MathMin(HighestHighOlder(s, left) - low, HighestHighRecent(s, right) - low);
         if(prom < atr * InpSwingMinProminenceAtr) continue;
         if(entry - low < atr * InpSwingMinDepartureAtr) continue;
         double candidate = low - atr * MathMax(0.0, InpSwingBufferAtr);
         double r = entry - candidate;
         if(r > bestRisk) { bestRisk = r; bestSl = candidate; bestShift = s; }
      }
      else
      {
         double high = High[s];
         for(int c = 1; c <= left; c++) if(High[s + c] >= high) { pivot = false; break; }
         if(!pivot) continue;
         for(int d = 1; d <= right; d++) if(High[s - d] > high) { pivot = false; break; }
         if(!pivot) continue;
         double prom2 = MathMin(high - LowestLowOlder(s, left), high - LowestLowRecent(s, right));
         if(prom2 < atr * InpSwingMinProminenceAtr) continue;
         if(high - entry < atr * InpSwingMinDepartureAtr) continue;
         double candidate2 = high + atr * MathMax(0.0, InpSwingBufferAtr);
         double r2 = candidate2 - entry;
         if(r2 > bestRisk) { bestRisk = r2; bestSl = candidate2; bestShift = s; }
      }
   }
   if(bestShift < 0) { detail = "no_structural_pivot"; return false; }
   outSl = bestSl; outRisk = bestRisk;
   detail = "swing_shift=" + IntegerToString(bestShift) + " swing_sl=" + PriceText(bestSl) + " swing_risk=" + DoubleToString(bestRisk, Digits);
   return true;
}

double HighestHighOlder(int shift, int bars) { double v = High[shift]; for(int i=1; i<=bars && shift+i<Bars; i++) v = MathMax(v, High[shift+i]); return v; }
double HighestHighRecent(int shift, int bars) { double v = High[shift]; for(int i=1; i<=bars && shift-i>=0; i++) v = MathMax(v, High[shift-i]); return v; }
double LowestLowOlder(int shift, int bars) { double v = Low[shift]; for(int i=1; i<=bars && shift+i<Bars; i++) v = MathMin(v, Low[shift+i]); return v; }
double LowestLowRecent(int shift, int bars) { double v = Low[shift]; for(int i=1; i<=bars && shift-i>=0; i++) v = MathMin(v, Low[shift-i]); return v; }
double TpByIndex(int idx, double tp1, double tp2, double tp3) { if(idx==1) return tp1; if(idx==2) return tp2; if(idx==3) return tp3; return 0; }

void ManagePositions()
{
   RefreshRates();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      int ticket = OrderTicket();
      TryEnrichFallbackTrade(ticket, type);
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) continue;
      string dir = (type == OP_BUY) ? "BUY" : "SELL";
      double px = (type == OP_BUY) ? Bid : Ask;
      int halfIdx = (int)TicketGV(ticket, "HIDX", 0);
      double half = TicketGV(ticket, "HTP", 0);
      bool halfDone = (TicketGV(ticket, "HDONE", 0) > 0.5);
      if(halfIdx > 0 && !halfDone && half > 0 && PriceReached(type, px, half))
      {
         double closeLots = NormalizeCloseLots(OrderLots() / 2.0);
         if(closeLots > 0 && closeLots < OrderLots())
         {
            bool ok = OrderClose(ticket, closeLots, px, InpSlippage, clrAqua);
            int err = GetLastError();
            if(ok)
            {
               TicketGVSet(ticket, "HDONE", 1);
               Audit("half_close_done", TicketEvent(ticket), ticket, dir, closeLots, px, OrderStopLoss(), OrderTakeProfit(), "trigger=" + PriceText(half), OrderProfit(), "");
               if(OrderSelect(ticket, SELECT_BY_TICKET)) MoveSlToBE(ticket, type);
            }
            else Audit("half_close_failed", TicketEvent(ticket), ticket, dir, closeLots, px, OrderStopLoss(), OrderTakeProfit(), "err=" + IntegerToString(err), 0, "");
         }
      }
      double target = OrderTakeProfit();
      if(target > 0 && PriceReached(type, px, target))
      {
         double lots = OrderLots();
         bool ok2 = OrderClose(ticket, lots, px, InpSlippage, clrGold);
         int err2 = GetLastError();
         if(ok2)
         {
            TicketGVSet(ticket, "CLOSED", 1.0);
            Audit("full_tp_close_done", TicketEvent(ticket), ticket, dir, lots, px, OrderStopLoss(), target, "manual_guard_tp_reached", OrderProfit(), "");
         }
         else Audit("full_tp_close_failed", TicketEvent(ticket), ticket, dir, lots, px, OrderStopLoss(), target, "err=" + IntegerToString(err2), 0, "broker_tp_may_handle_it");
      }
   }
   DrawTradeLevels();
}

bool PriceReached(int type, double price, double level) { if(level <= 0) return false; return (type == OP_BUY) ? (price >= level) : (price <= level); }

void TryEnrichFallbackTrade(int ticket, int type)
{
   if(!InpEnrichFallbackTradeWithObjectLevels) return;
   if(TicketGV(ticket, "FB", 0.0) < 0.5) return;
   if(TicketGV(ticket, "ENRICH", 0.0) > 0.5) return;
   if(TicketGV(ticket, "HDONE", 0.0) > 0.5)
   {
      TicketGVSet(ticket, "ENRICH", 1.0);
      Audit("object_enrich_skipped_half_done", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), OrderStopLoss(), OrderTakeProfit(), "fallback trade already half-managed; object override skipped", OrderProfit(), "");
      return;
   }

   double sl, tp1, tp2, tp3;
   string detail;
   double anchor = OrderOpenPrice();
   string anchorDetail;
   FindLevelPrice(InpSignalLevelObjectName, anchor, anchorDetail);
   if(!BuildObjectGeometry(type, OrderOpenPrice(), anchor, sl, tp1, tp2, tp3, detail)) return;

   int targetIdx = (int)TicketGV(ticket, "TIDX", g_targetTpRuntime);
   int halfIdx = (int)TicketGV(ticket, "HIDX", g_halfTpRuntime);
   double newTarget = TpByIndex(targetIdx, tp1, tp2, tp3);
   double newHalf = TpByIndex(halfIdx, tp1, tp2, tp3);

   double rawSl = sl, rawTarget = newTarget;
   string brokerGuard;
   if(!PrepareBrokerModifyStops(type, OrderOpenPrice(), sl, newTarget, brokerGuard))
   {
      Audit("object_enrich_blocked_broker_stops", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), rawSl, rawTarget, brokerGuard + " " + detail, OrderProfit(), "");
      return;
   }
   if(MathAbs(sl - rawSl) > Point * 0.5 || MathAbs(newTarget - rawTarget) > Point * 0.5)
   {
      if(targetIdx == 1) tp1 = newTarget;
      if(targetIdx == 2) tp2 = newTarget;
      if(targetIdx == 3) tp3 = newTarget;
      if(halfIdx == targetIdx) newHalf = newTarget;
      Audit("object_enrich_broker_stop_adjusted", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, brokerGuard, OrderProfit(), "raw_sl=" + PriceText(rawSl) + " raw_tp=" + PriceText(rawTarget));
   }

   bool changed = (MathAbs(OrderStopLoss() - sl) > Point || MathAbs(OrderTakeProfit() - newTarget) > Point);
   if(!changed)
   {
      TicketGVSet(ticket, "FB", 0.0);
      TicketGVSet(ticket, "ENRICH", 1.0);
      TicketGVSet(ticket, "TP1", tp1); TicketGVSet(ticket, "TP2", tp2); TicketGVSet(ticket, "TP3", tp3); TicketGVSet(ticket, "HTP", newHalf);
      Audit("object_enrich_no_change", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, detail, OrderProfit(), "");
      return;
   }

   bool ok = OrderModify(ticket, OrderOpenPrice(), NormalizePriceToTick(sl), NormalizePriceToTick(newTarget), 0, clrDodgerBlue);
   int err = GetLastError();
   if(ok)
   {
      TicketGVSet(ticket, "FB", 0.0);
      TicketGVSet(ticket, "ENRICH", 1.0);
      TicketGVSet(ticket, "TP1", tp1); TicketGVSet(ticket, "TP2", tp2); TicketGVSet(ticket, "TP3", tp3); TicketGVSet(ticket, "HTP", newHalf);
      DeleteCalculatedFallbackLevels(ticket);
      Audit("object_enrich_modify_done", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, detail + " new_half=" + PriceText(newHalf), OrderProfit(), "fallback levels overwritten by Gann objects");
      DrawTradeLevels();
   }
   else
   {
      Audit("object_enrich_modify_failed", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), OrderOpenPrice(), sl, newTarget, "err=" + IntegerToString(err) + " " + detail, OrderProfit(), "");
   }
}

void MoveSlToBE(int ticket, int type)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   double be = NormalizeDouble(OrderOpenPrice(), Digits);
   double sl = OrderStopLoss();
   bool improve = (type == OP_BUY && (sl <= 0 || be > sl + Point)) || (type == OP_SELL && (sl <= 0 || be < sl - Point));
   if(!improve) return;

   RefreshRates();
   double minDist = BrokerMinStopDistance();
   if(type == OP_BUY && be > Bid - minDist)
   {
      Audit("sl_to_be_wait_stop_level", TicketEvent(ticket), ticket, "BUY", OrderLots(), be, sl, OrderTakeProfit(), "bid=" + PriceText(Bid) + " min_dist=" + PriceText(minDist), OrderProfit(), "");
      return;
   }
   if(type == OP_SELL && be < Ask + minDist)
   {
      Audit("sl_to_be_wait_stop_level", TicketEvent(ticket), ticket, "SELL", OrderLots(), be, sl, OrderTakeProfit(), "ask=" + PriceText(Ask) + " min_dist=" + PriceText(minDist), OrderProfit(), "");
      return;
   }

   bool ok = OrderModify(ticket, OrderOpenPrice(), NormalizePriceToTick(be), OrderTakeProfit(), 0, clrAqua);
   int err = GetLastError();
   Audit(ok ? "sl_to_be_done" : "sl_to_be_failed", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), be, sl, OrderTakeProfit(), ok ? "" : "err=" + IntegerToString(err), OrderProfit(), "");
}

void CloseOpposite(int newType, string eventId)
{
   int opposite = (newType == OP_BUY) ? OP_SELL : OP_BUY;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber()) || OrderType() != opposite) continue;
      RefreshRates();
      double px = (opposite == OP_BUY) ? Bid : Ask;
      int ticket = OrderTicket();
      bool ok = OrderClose(ticket, OrderLots(), px, InpSlippage, clrSilver);
      int err = GetLastError();
      if(ok) TicketGVSet(ticket, "CLOSED", 1.0);
      Audit(ok ? "reverse_close_done" : "reverse_close_failed", eventId, ticket, (opposite == OP_BUY ? "BUY" : "SELL"), OrderLots(), px, OrderStopLoss(), OrderTakeProfit(), ok ? "before_new_signal" : "err=" + IntegerToString(err), OrderProfit(), "");
   }
}

bool HasOpenDirection(int type)
{
   int pendingLimit = (type == OP_BUY) ? OP_BUYLIMIT : OP_SELLLIMIT;
   int pendingStop = (type == OP_BUY) ? OP_BUYSTOP : OP_SELLSTOP;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsCurrentInstanceMagic(OrderMagicNumber())) continue;
      int ot = OrderType();
      if(ot == type || ot == pendingLimit || ot == pendingStop) return true;
   }
   return false;
}

bool ManagedRiskMode(){ return g_ftmoMode || g_riskLotOnlyMode; }
bool EffectiveRiskEnabled(){ return InpAdvancedAccountRiskEnabled || ManagedRiskMode(); }
string RuntimeRiskModeLabel(){ if(g_ftmoMode) return "FTMO"; if(g_riskLotOnlyMode) return "RISKLOT"; return "NORMAL"; }
double EffAccountRiskPerTradePct(){ return ManagedRiskMode() ? 1.0 : InpAccountRiskPerTradePct; }
double EffAccountRiskDailyAtrExposurePct(){ return ManagedRiskMode() ? 2.0 : InpAccountRiskDailyAtrExposurePct; }
double EffMaxPortfolioRiskPct(){ return g_ftmoMode ? 4.0 : InpMaxPortfolioRiskPct; }
double EffDailyLossLimitPct(){ return g_ftmoMode ? 5.0 : InpDailyLossLimitPct; }
double EffMaxDrawdownPct(){ return g_ftmoMode ? 10.0 : InpMaxDrawdownPct; }
double EffMaxMarginUsagePct(){ return g_ftmoMode ? 40.0 : InpMaxMarginUsagePct; }

int LegacyEffectiveMagic() { if(EffectiveRiskEnabled()) return 1000000000 + MathAbs(InpMagic % 900000000); return InpMagic; }

int StableHash(string s)
{
   int h = 216613626;
   for(int i = 0; i < StringLen(s); i++)
   {
      h = h ^ StringGetCharacter(s, i);
      h = h * 16777619;
   }
   if(h < 0) h = -h;
   return h;
}

int EffectiveMagic()
{
   if(!EffectiveRiskEnabled()) return InpMagic;
   if(!InpUseSymbolTimeframeMagic) return LegacyEffectiveMagic();
   int h = StableHash(Symbol() + "|" + IntegerToString(Period()));
   return 1000000000 + MathAbs((MathAbs(InpMagic % 100000000) * 31 + h) % 900000000);
}

bool IsCurrentInstanceMagic(int magic) { return magic == InpMagic || magic == EffectiveMagic(); }
bool IsOurMagic(int magic) { return IsCurrentInstanceMagic(magic) || magic == LegacyEffectiveMagic(); }

double ResolveLot(double entry, double sl, int type, bool requireHalfSplit, string &detail)
{
   double fallback = NormalizeOrderLot(g_lotRuntime, requireHalfSplit);
   if(!EffectiveRiskEnabled()) { detail = "risk_engine=off lot=" + DoubleToString(fallback, 3); return fallback; }
   double cap, daily, dd;
   AccountRiskMetrics(cap, daily, dd);
   if(EffDailyLossLimitPct() > 0 && daily >= EffDailyLossLimitPct()) { if(InpLiquidateOnBreach) LiquidateScoped("daily_loss_breach"); detail = "risk_block daily_loss_pct=" + DoubleToString(daily,2); return 0; }
   if(EffMaxDrawdownPct() > 0 && dd >= EffMaxDrawdownPct()) { if(InpLiquidateOnBreach) LiquidateScoped("max_drawdown_breach"); detail = "risk_block total_dd_pct=" + DoubleToString(dd,2); return 0; }
   double riskPerLot = MoneyRiskPerLot(entry, sl);
   if(riskPerLot <= 0) { detail = "risk_block invalid_risk_per_lot"; return 0; }
   double tradeBudget = cap * MathMax(0.0, EffAccountRiskPerTradePct()) / 100.0;
   double atrBudget = cap * MathMax(0.0, EffAccountRiskDailyAtrExposurePct()) / 100.0;
   double openRisk = CurrentOpenRisk();
   double portfolioBudget = cap * MathMax(0.0, EffMaxPortfolioRiskPct()) / 100.0 - openRisk;
   double budget = (EffMaxPortfolioRiskPct() > 0) ? MathMin(tradeBudget, portfolioBudget) : tradeBudget;
   if(budget <= 0) { detail = "risk_block exhausted_budget open_risk=" + DoubleToString(openRisk,2); return 0; }
   double dailyAtr = ClosedDailyAtr(Symbol(), InpAccountRiskDailyAtrPeriod);
   double dailyMoneyPerLot = MoneyMovePerLot(dailyAtr);
   double slLot = budget / riskPerLot;
   double atrLot = 0.0;
   bool atrCapActive = (EffAccountRiskDailyAtrExposurePct() > 0.0 && atrBudget > 0.0 && dailyAtr > 0.0 && dailyMoneyPerLot > 0.0);
   if(atrCapActive) atrLot = atrBudget / dailyMoneyPerLot;
   double rawLot = (InpAutoLotByRisk || ManagedRiskMode()) ? slLot : fallback;
   if((InpAutoLotByRisk || ManagedRiskMode()) && atrCapActive) rawLot = MathMin(rawLot, atrLot);
   double lot = NormalizeOrderLot(rawLot, requireHalfSplit);
   if(lot <= 0) { detail = "risk_block lot_below_min raw=" + DoubleToString(rawLot,4); return 0; }
   double freeAfter = AccountFreeMarginCheck(Symbol(), type, lot);
   double marginUsedPct = (AccountEquity() > 0) ? (AccountEquity() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   double incrementalMarginPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   double singleMarginLimitPct = SingleTradeMarginLimitPct();
   string clampDetail = "";
   if(freeAfter <= 0 || (EffMaxMarginUsagePct() > 0 && marginUsedPct > EffMaxMarginUsagePct()) || (singleMarginLimitPct > 0.0 && incrementalMarginPct > singleMarginLimitPct))
   {
      double clamped = ClampLotToMargin(lot, type, requireHalfSplit, clampDetail);
      if(clamped <= 0) { detail = "risk_block margin lot=" + DoubleToString(lot,3) + " " + clampDetail; return 0; }
      lot = clamped;
      freeAfter = AccountFreeMarginCheck(Symbol(), type, lot);
      marginUsedPct = (AccountEquity() > 0) ? (AccountEquity() - freeAfter) / AccountEquity() * 100.0 : 0.0;
      incrementalMarginPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   }
   double projectedRisk = riskPerLot * lot;
   double projectedAtrExposure = dailyMoneyPerLot * lot;
   detail = "risk_engine=on lot=" + DoubleToString(lot,3)
      + " risk_capital=" + DoubleToString(cap,2)
      + " budget=" + DoubleToString(budget,2)
      + " risk_per_lot=" + DoubleToString(riskPerLot,2)
      + " sl_lot=" + DoubleToString(slLot,3)
      + " atr_cap_active=" + (atrCapActive ? "true" : "false")
      + " daily_atr=" + DoubleToString(dailyAtr,Digits)
      + " daily_money_per_lot=" + DoubleToString(dailyMoneyPerLot,2)
      + " atr_budget=" + DoubleToString(atrBudget,2)
      + " atr_lot=" + DoubleToString(atrLot,3)
      + " projected_risk=" + DoubleToString(projectedRisk,2)
      + " projected_atr_exposure=" + DoubleToString(projectedAtrExposure,2)
      + " open_risk=" + DoubleToString(openRisk,2)
      + " margin_pct=" + DoubleToString(marginUsedPct,2)
      + " incremental_margin_pct=" + DoubleToString(incrementalMarginPct,2)
      + " single_margin_limit_pct=" + DoubleToString(singleMarginLimitPct,2)
      + " daily_loss_pct=" + DoubleToString(daily,2)
      + " total_dd_pct=" + DoubleToString(dd,2)
      + (clampDetail == "" ? "" : " " + clampDetail);
   return lot;
}

double SingleTradeMarginLimitPct()
{
   double limit = InpMaxSingleTradeMarginPct;
   if(limit <= 0.0 && InpMinConcurrentTradeSlots > 0)
      limit = 100.0 / MathMax(1, InpMinConcurrentTradeSlots);
   if(limit <= 0.0) return 0.0;
   return MathMax(0.1, MathMin(100.0, limit));
}

bool IsMarginAcceptable(double lot, int type, double &freeAfter, double &marginUsedPct)
{
   ResetLastError();
   double freeBefore = AccountFreeMargin();
   freeAfter = AccountFreeMarginCheck(Symbol(), type, lot);
   marginUsedPct = (AccountEquity() > 0) ? (AccountEquity() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   if(freeAfter <= 0) return false;
   if(EffMaxMarginUsagePct() > 0 && marginUsedPct > EffMaxMarginUsagePct()) return false;
   double singleLimit = SingleTradeMarginLimitPct();
   if(singleLimit > 0.0 && AccountEquity() > 0.0)
   {
      double incrementalPct = MathMax(0.0, freeBefore - freeAfter) / AccountEquity() * 100.0;
      if(incrementalPct > singleLimit) return false;
   }
   return true;
}

double ClampLotToMargin(double requestedLot, int type, bool requireHalfSplit, string &detail)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;

   double freeAfter, marginPct;
   if(IsMarginAcceptable(requestedLot, type, freeAfter, marginPct))
   {
      double incPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
      detail = "margin_ok requested=" + DoubleToString(requestedLot, 3) + " margin_pct=" + DoubleToString(marginPct, 2) + " incremental_margin_pct=" + DoubleToString(incPct, 2) + " single_margin_limit_pct=" + DoubleToString(SingleTradeMarginLimitPct(), 2);
      return requestedLot;
   }

   double lo = minLot;
   double hi = requestedLot;
   double best = 0.0;
   double bestMargin = 0.0;
   for(int i = 0; i < 32; i++)
   {
      double mid = NormalizeOrderLot((lo + hi) / 2.0, requireHalfSplit);
      if(mid < minLot || mid <= 0) { hi = (lo + hi) / 2.0; continue; }
      if(IsMarginAcceptable(mid, type, freeAfter, marginPct))
      {
         best = mid;
         bestMargin = marginPct;
         lo = mid + step;
      }
      else hi = mid - step;
   }

   best = NormalizeOrderLot(best, requireHalfSplit);
   if(best > 0 && IsMarginAcceptable(best, type, freeAfter, marginPct))
   {
      double incPct = (AccountEquity() > 0.0) ? MathMax(0.0, AccountFreeMargin() - freeAfter) / AccountEquity() * 100.0 : 0.0;
      detail = "margin_clamped requested=" + DoubleToString(requestedLot, 3) + " final=" + DoubleToString(best, 3) + " margin_pct=" + DoubleToString(marginPct, 2) + " incremental_margin_pct=" + DoubleToString(incPct, 2) + " single_margin_limit_pct=" + DoubleToString(SingleTradeMarginLimitPct(), 2);
      return best;
   }

   detail = "margin_unavailable requested=" + DoubleToString(requestedLot, 3) + " min_lot=" + DoubleToString(minLot, 3) + " last_margin_pct=" + DoubleToString(bestMargin, 2);
   return 0.0;
}

double MoneyRiskPerLot(double entry, double sl)
{
   return MoneyRiskPerLotForSymbol(Symbol(), entry, sl);
}

double MoneyRiskPerLotForSymbol(string symbol, double entry, double sl)
{
   return MoneyMovePerLotForSymbol(symbol, MathAbs(entry - sl));
}

double MoneyMovePerLot(double priceMove)
{
   return MoneyMovePerLotForSymbol(Symbol(), priceMove);
}

double MoneyMovePerLotForSymbol(string symbol, double priceMove)
{
   double tickSize = MarketInfo(symbol, MODE_TICKSIZE), tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   if(priceMove <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0) return 0.0;
   return priceMove / tickSize * tickValue;
}

double ClosedDailyAtr(string symbol, int period)
{
   int atrPeriod = MathMax(2, period);
   double atr = iATR(symbol, PERIOD_D1, atrPeriod, 1);
   return (MathIsValidNumber(atr) && atr > 0.0) ? atr : 0.0;
}

double NormalizeOrderLot(double lot, bool requireHalfSplit)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT), maxLot = MarketInfo(Symbol(), MODE_MAXLOT), step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / step + 0.0000001) * step;
   if(requireHalfSplit)
   {
      double half = MathFloor((lot / 2.0) / step + 0.0000001) * step;
      if(half < minLot) return 0;
   }
   return NormalizeDouble(lot, 2);
}

double NormalizeCloseLots(double lot)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT), step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0) step = 0.01;
   lot = MathFloor(lot / step + 0.0000001) * step;
   if(lot < minLot) return 0;
   return NormalizeDouble(lot, 2);
}

string RiskKey(string kind) { return "GannMadeEasyBridgeRisk|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + IntegerToString(Period()) + "|" + IntegerToString(EffectiveMagic()) + "|" + kind; }

double InitialBalance()
{
   if(InpInitialBalanceOverride > 0) return InpInitialBalanceOverride;
   string key = RiskKey("INITIAL_BALANCE");
   if(!GlobalVariableCheck(key) || GlobalVariableGet(key) <= 0) GlobalVariableSet(key, AccountBalance());
   return GlobalVariableGet(key);
}

datetime GmtDayStart()
{
   datetime now = TimeGMT();
   datetime today0 = now - TimeHour(now) * 3600 - TimeMinute(now) * 60 - TimeSeconds(now);
   datetime reset = today0 + MathMax(0, MathMin(23, InpDayResetHourGmt)) * 3600;
   if(now < reset) reset -= 86400;
   return reset;
}

void AccountRiskMetrics(double &riskCapital, double &dailyLossPct, double &totalDdPct)
{
   double initial = MathMax(1, InitialBalance());
   double closedAll = 0, closedToday = 0, floating = 0;
   datetime dayStart = GmtDayStart();
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      closedAll += pnl;
      if(OrderCloseTime() >= dayStart) closedToday += pnl;
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      floating += OrderProfit() + OrderSwap() + OrderCommission();
   }
   riskCapital = MathMax(1, initial + closedAll + floating);
   dailyLossPct = MathMax(0, -(closedToday + floating) / initial * 100.0);
   totalDdPct = MathMax(0, -(closedAll + floating) / initial * 100.0);
}

bool RiskOrderInScope(string sym, int magic)
{
   if(!InpRiskScopeByMagic) return true;
   if(IsOurMagic(magic)) return true;
   string comment = OrderComment();
   if(StringFind(comment, "GannBridge") == 0) return true;
   return false;
}

double CurrentOpenRisk()
{
   double total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      int ot = OrderType();
      if(ot != OP_BUY && ot != OP_SELL && ot != OP_BUYLIMIT && ot != OP_SELLLIMIT && ot != OP_BUYSTOP && ot != OP_SELLSTOP) continue;
      if(OrderStopLoss() <= 0) continue;
      total += MoneyRiskPerLotForSymbol(OrderSymbol(), OrderOpenPrice(), OrderStopLoss()) * OrderLots();
   }
   return total;
}

void LiquidateScoped(string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      string osym = OrderSymbol();
      double px = (type == OP_BUY) ? MarketInfo(osym, MODE_BID) : MarketInfo(osym, MODE_ASK);
      if(px <= 0.0) continue;
      int ticket = OrderTicket();
      bool ok = OrderClose(OrderTicket(), OrderLots(), px, InpSlippage, clrRed);
      if(ok) TicketGVSet(ticket, "CLOSED", 1.0);
      Audit(ok ? "risk_liquidation_close_done" : "risk_liquidation_close_failed", TicketEvent(ticket), ticket, (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), px, OrderStopLoss(), OrderTakeProfit(), reason, OrderProfit(), "");
   }
}

int CurrentSpreadPoints() { RefreshRates(); return (int)MathRound((Ask - Bid) / Point); }

bool IsInAllowedWindow(datetime t, string windows) { string w = Trim(windows); if(w == "") return true; return IsInWindowList(t, w); }
bool IsInNoTradeWindow(datetime t, string windows) { string w = Trim(windows); if(w == "") return false; return IsInWindowList(t, w); }

bool IsInWindowList(datetime t, string windows)
{
   string parts[];
   int n = StringSplit(windows, ',', parts);
   int cur = TimeHour(t) * 60 + TimeMinute(t);
   for(int i = 0; i < n; i++)
   {
      string p = Trim(parts[i]);
      int dash = StringFind(p, "-");
      if(dash <= 0) continue;
      int a = ParseHHMM(StringSubstr(p, 0, dash));
      int b = ParseHHMM(StringSubstr(p, dash + 1));
      if(a < 0 || b < 0) continue;
      if(a <= b) { if(cur >= a && cur <= b) return true; }
      else { if(cur >= a || cur <= b) return true; }
   }
   return false;
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

string Trim(string s) { StringTrimLeft(s); StringTrimRight(s); return s; }

void StoreTicket(int ticket, double tp1, double tp2, double tp3, double half, int halfIdx, int targetIdx, bool fallbackLevels)
{
   TicketGVSet(ticket, "TP1", tp1); TicketGVSet(ticket, "TP2", tp2); TicketGVSet(ticket, "TP3", tp3);
   TicketGVSet(ticket, "HTP", half); TicketGVSet(ticket, "HIDX", halfIdx); TicketGVSet(ticket, "TIDX", targetIdx); TicketGVSet(ticket, "HDONE", 0);
   TicketGVSet(ticket, "FB", fallbackLevels ? 1.0 : 0.0);
   TicketGVSet(ticket, "ENRICH", 0.0);
   TicketGVSet(ticket, "OPENED", 1.0);
}

string TicketKey(int ticket, string field) { return "GannBridge|" + IntegerToString(AccountNumber()) + "|" + IntegerToString(ticket) + "|" + field; }
double TicketGV(int ticket, string field, double def) { string key = TicketKey(ticket, field); if(!GlobalVariableCheck(key)) return def; return GlobalVariableGet(key); }
void TicketGVSet(int ticket, string field, double value) { GlobalVariableSet(TicketKey(ticket, field), value); }
string TicketEvent(int ticket) { return "ticket=" + IntegerToString(ticket); }

void MaybeRiskAudit()
{
   if(!g_auditRuntime || !EffectiveRiskEnabled() || InpRiskAuditSeconds <= 0) return;
   datetime now = TimeGMT();
   if(now - g_lastRiskAuditTs < InpRiskAuditSeconds) return;
   g_lastRiskAuditTs = now;
   RiskAudit("snapshot", "periodic");
}

void MaybeProbe()
{
   if(!g_auditRuntime || InpPositionProbeSeconds <= 0) return;
   datetime now = TimeGMT();
   if(now - g_lastProbeTs < InpPositionProbeSeconds) return;
   g_lastProbeTs = now;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      double live = (type == OP_BUY) ? Bid : Ask;
      double risk = MathAbs(OrderOpenPrice() - OrderStopLoss());
      double r = (risk > 0) ? ((type == OP_BUY ? live - OrderOpenPrice() : OrderOpenPrice() - live) / risk) : 0;
      Audit("position_probe", TicketEvent(OrderTicket()), OrderTicket(), (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), live, OrderStopLoss(), OrderTakeProfit(), "r=" + DoubleToString(r, 3) + " spread=" + IntegerToString(CurrentSpreadPoints()), OrderProfit(), "");
   }
}

void MaybeLifecycleAudit()
{
   if(!g_auditRuntime || InpLifecycleAuditSeconds <= 0) return;
   datetime now = TimeGMT();
   if(now - g_lastLifecycleAuditTs < InpLifecycleAuditSeconds) return;
   g_lastLifecycleAuditTs = now;
   AuditClosedHistoryTickets();
}

void AuditClosedHistoryTickets()
{
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      int ticket = OrderTicket();
      if(TicketGV(ticket, "CLOSED", 0.0) > 0.5) continue;
      bool tracked = (TicketGV(ticket, "OPENED", 0.0) > 0.5 || StringFind(OrderComment(), "GannBridge") == 0);
      if(!tracked) continue;

      string eventName = ClassifyClosedOrder(type, OrderClosePrice(), OrderStopLoss(), OrderTakeProfit());
      string dir = (type == OP_BUY ? "BUY" : "SELL");
      double pnl = OrderProfit() + OrderSwap() + OrderCommission();
      string detail = "open_time=" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_SECONDS)
                    + " close_time=" + TimeToString(OrderCloseTime(), TIME_DATE|TIME_SECONDS)
                    + " open_price=" + PriceText(OrderOpenPrice())
                    + " close_price=" + PriceText(OrderClosePrice())
                    + " comment='" + OrderComment() + "'";
      Audit(eventName, TicketEvent(ticket), ticket, dir, OrderLots(), OrderClosePrice(), OrderStopLoss(), OrderTakeProfit(), detail, pnl, "history_lifecycle_tracker");
      TicketGVSet(ticket, "CLOSED", 1.0);
   }
}

string ClassifyClosedOrder(int type, double closePrice, double sl, double tp)
{
   double tol = MathMax(TickSizePrice() * 2.0, Point * 2.0);
   if(type == OP_BUY)
   {
      if(sl > 0.0 && closePrice <= sl + tol) return "closed_by_broker_sl";
      if(tp > 0.0 && closePrice >= tp - tol) return "closed_by_broker_tp";
   }
   else
   {
      if(sl > 0.0 && closePrice >= sl - tol) return "closed_by_broker_sl";
      if(tp > 0.0 && closePrice <= tp + tol) return "closed_by_broker_tp";
   }
   return "closed_by_unknown_manual";
}

void RiskAudit(string eventName, string detail)
{
   if(!g_auditRuntime) return;
   double cap, daily, dd;
   AccountRiskMetrics(cap, daily, dd);
   int h = FileOpen("GannMadeEasyBridge_AccountRiskAudit_" + DateStamp(TimeGMT()) + ".csv", FILE_CSV|FILE_READ|FILE_WRITE, ';');
   if(h == INVALID_HANDLE) return;
   bool header = (FileSize(h) == 0);
   FileSeek(h, 0, SEEK_END);
   if(header) FileWrite(h, "gmt", "broker", "account", "symbol", "tf", "event", "risk_capital", "open_risk", "daily_loss_pct", "total_dd_pct", "enabled", "detail");
   FileWrite(h, TimeToString(TimeGMT(), TIME_DATE|TIME_SECONDS), TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), AccountNumber(), Symbol(), Period(), eventName, DoubleToString(cap, 2), DoubleToString(CurrentOpenRisk(), 2), DoubleToString(daily, 3), DoubleToString(dd, 3), EffectiveRiskEnabled() ? "true" : "false", detail);
   FileClose(h);
}

void Audit(string eventName, string eventId, int ticket, string dir, double lot, double price, double sl, double tp, string detail, double pnl, string extra)
{
   if(!g_auditRuntime) return;
   int h = FileOpen("GannMadeEasyBridge_DirectAudit_" + DateStamp(TimeGMT()) + ".csv", FILE_CSV|FILE_READ|FILE_WRITE, ';');
   if(h == INVALID_HANDLE) return;
   bool header = (FileSize(h) == 0);
   FileSeek(h, 0, SEEK_END);
   if(header) FileWrite(h, "gmt", "broker", "account", "symbol", "tf", "event", "event_id", "ticket", "dir", "lot", "price", "sl", "tp", "spread_points", "pnl", "detail", "extra");
   FileWrite(h, TimeToString(TimeGMT(), TIME_DATE|TIME_SECONDS), TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), AccountNumber(), Symbol(), Period(), eventName, eventId, ticket, dir, DoubleToString(lot, 3), PriceText(price), PriceText(sl), PriceText(tp), CurrentSpreadPoints(), DoubleToString(pnl, 2), detail, extra);
   FileClose(h);
}

string DateStamp(datetime t) { return StringSubstr(TimeToString(t, TIME_DATE),0,4) + StringSubstr(TimeToString(t, TIME_DATE),5,2) + StringSubstr(TimeToString(t, TIME_DATE),8,2); }
string PriceText(double v) { if(v <= 0) return "-"; return DoubleToString(v, Digits); }

void DashboardCreate()
{
   DeleteDashboard();
   if(!InpShowDashboard) return;
   int x = InpDashboardX, y = InpDashboardY, w = 480, h = g_collapsed ? 34 : 280;
   Rect(Obj("bg"), x, y, w, h, clrDimGray, clrBlack);
   Label(Obj("title"), x+12, y+8, "GANN MADE EASY // " + BUILD_TAG, clrAliceBlue, 9);
   Button(Obj("collapse"), x+w-32, y+6, 24, 20, g_collapsed ? "v" : "^", clrSlateGray, clrWhite);
   if(g_collapsed) return;
   Button(Obj("toggle"), x+12, y+34, 68, 24, g_eaEnabled ? "EA ON" : "EA OFF", g_eaEnabled ? clrDarkGreen : clrMaroon, clrWhite);
   Button(Obj("drift"), x+86, y+34, 86, 24, g_pendingOnDriftRuntime ? "DRIFT LIM" : "DRIFT MKT", g_pendingOnDriftRuntime ? clrSaddleBrown : clrDarkSlateGray, clrWhite);
   Button(Obj("ftmo"), x+178, y+34, 62, 24, g_ftmoMode ? "FTMO" : "FTMO", g_ftmoMode ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Button(Obj("risklot"), x+246, y+34, 66, 24, g_riskLotOnlyMode ? "RISK" : "RISK", g_riskLotOnlyMode ? clrDarkGreen : clrDarkSlateGray, clrWhite);
   Button(Obj("audit"), x+318, y+34, 78, 24, g_auditRuntime ? "AUDIT" : "AUDIT", g_auditRuntime ? clrSaddleBrown : clrDarkSlateGray, clrWhite);
   Button(Obj("apply"), x+402, y+34, 62, 24, "APPLY", clrSteelBlue, clrWhite);
   Label(Obj("l_lot"), x+12, y+68, "Lot", clrLightSteelBlue, 8); Edit(Obj("e_lot"), x+86, y+64, 58, 20, DoubleToString(g_lotRuntime, 2));
   Label(Obj("l_spread"), x+152, y+68, "MaxSpr", clrLightSteelBlue, 8); Edit(Obj("e_spread"), x+210, y+64, 50, 20, IntegerToString(g_maxSpreadRuntime));
   Label(Obj("l_scale"), x+270, y+68, "CalcSL%", clrLightSteelBlue, 8); Edit(Obj("e_scale"), x+318, y+64, 56, 20, DoubleToString(g_finalScaleRuntime, 1));
   Label(Obj("l_tp"), x+12, y+94, "TP leg", clrLightSteelBlue, 8); Edit(Obj("e_tp"), x+86, y+90, 58, 20, IntegerToString(g_targetTpRuntime));
   Label(Obj("l_half"), x+152, y+94, "HalfBE", clrLightSteelBlue, 8); Edit(Obj("e_half"), x+210, y+90, 50, 20, IntegerToString(g_halfTpRuntime));
   Label(Obj("l_windows"), x+12, y+120, "Window", clrLightSteelBlue, 8); Edit(Obj("e_allowed"), x+86, y+116, 132, 20, g_allowedWindowsRuntime);
   Label(Obj("l_no"), x+224, y+120, "NoTrade", clrLightSteelBlue, 8); Edit(Obj("e_no"), x+286, y+116, 88, 20, g_noTradeWindowsRuntime);
   Label(Obj("status"), x+12, y+148, "status", clrWhite, 8);
   Label(Obj("signal"), x+12, y+170, "signal", clrWhite, 8);
   Label(Obj("risk"), x+12, y+192, "risk", clrWhite, 8);
   Label(Obj("open"), x+12, y+214, "open", clrWhite, 8);
   Rect(Obj("prog_bg"), x+12, y+242, 362, 16, clrBlack, clrSlateGray);
   Rect(Obj("prog_fill"), x+13, y+243, 1, 14, clrDodgerBlue, clrDodgerBlue);
}

void DashboardUpdate()
{
   if(!InpShowDashboard) return;
   if(ObjectFind(0, Obj("bg")) < 0) DashboardCreate();
   ObjectSetString(0, Obj("toggle"), OBJPROP_TEXT, g_eaEnabled ? "EA ON" : "EA OFF");
   ObjectSetInteger(0, Obj("toggle"), OBJPROP_BGCOLOR, g_eaEnabled ? clrDarkGreen : clrMaroon);
   ObjectSetString(0, Obj("drift"), OBJPROP_TEXT, g_pendingOnDriftRuntime ? "DRIFT LIMIT" : "DRIFT MKT");
   ObjectSetInteger(0, Obj("drift"), OBJPROP_BGCOLOR, g_pendingOnDriftRuntime ? clrSaddleBrown : clrDarkSlateGray);
   ObjectSetString(0, Obj("audit"), OBJPROP_TEXT, g_auditRuntime ? "AUDIT" : "AUDIT");
   ObjectSetInteger(0, Obj("audit"), OBJPROP_BGCOLOR, g_auditRuntime ? clrSaddleBrown : clrDarkSlateGray);
   ObjectSetString(0, Obj("ftmo"), OBJPROP_TEXT, g_ftmoMode ? "FTMO" : "FTMO");
   ObjectSetInteger(0, Obj("ftmo"), OBJPROP_BGCOLOR, g_ftmoMode ? clrDarkGreen : clrDarkSlateGray);
   ObjectSetString(0, Obj("risklot"), OBJPROP_TEXT, g_riskLotOnlyMode ? "RISK" : "RISK");
   ObjectSetInteger(0, Obj("risklot"), OBJPROP_BGCOLOR, g_riskLotOnlyMode ? clrDarkGreen : clrDarkSlateGray);
   if(g_collapsed) return;
   string sigTime = (g_lastSignalTime > 0) ? TimeToString(g_lastSignalTime, TIME_DATE|TIME_MINUTES) : "-";
   ObjectSetString(0, Obj("status"), OBJPROP_TEXT, "Spread " + IntegerToString(CurrentSpreadPoints()) + " pt | Mode " + RuntimeRiskModeLabel() + " | Risk " + (EffectiveRiskEnabled() ? "ON" : "OFF") + " | Audit " + (g_auditRuntime ? "ON" : "OFF") + " | Magic " + IntegerToString(EffectiveMagic()));
   ObjectSetString(0, Obj("signal"), OBJPROP_TEXT, "Latest signal: " + g_lastSignalDir + " @ " + sigTime + " px " + PriceText(g_lastSignalPrice));
   double cap, daily, dd; AccountRiskMetrics(cap, daily, dd);
   ObjectSetString(0, Obj("risk"), OBJPROP_TEXT, "RiskCap " + DoubleToString(cap,2) + " | OpenRisk " + DoubleToString(CurrentOpenRisk(),2) + " | D " + DoubleToString(daily,2) + "% / DD " + DoubleToString(dd,2) + "%");
   UpdateOpenLine();
}

void UpdateOpenLine()
{
   string txt = "Open: none";
   double rLast = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int type = OrderType(); if(type != OP_BUY && type != OP_SELL) continue;
      double live = (type == OP_BUY) ? Bid : Ask;
      double risk = MathAbs(OrderOpenPrice() - OrderStopLoss());
      rLast = (risk > 0) ? ((type == OP_BUY ? live - OrderOpenPrice() : OrderOpenPrice() - live) / risk) : 0;
      txt = "Open #" + IntegerToString(OrderTicket()) + " " + (type == OP_BUY ? "BUY" : "SELL") + " R=" + DoubleToString(rLast,2) + " PnL=" + DoubleToString(OrderProfit(),2) + " SL=" + PriceText(OrderStopLoss()) + " TP=" + PriceText(OrderTakeProfit());
      break;
   }
   ObjectSetString(0, Obj("open"), OBJPROP_TEXT, txt);
   int fill = (int)MathRound(MathMax(0.0, MathMin(1.0, (rLast + 1.0) / 4.0)) * 360.0);
   ObjectSetInteger(0, Obj("prog_fill"), OBJPROP_XSIZE, MathMax(1, fill));
   ObjectSetInteger(0, Obj("prog_fill"), OBJPROP_BGCOLOR, rLast >= 0 ? clrDodgerBlue : clrTomato);
}

void ApplyDashboardInputs()
{
   g_lotRuntime = MathMax(0, StringToDouble(ObjectGetString(0, Obj("e_lot"), OBJPROP_TEXT)));
   g_maxSpreadRuntime = MathMax(0, (int)StringToInteger(ObjectGetString(0, Obj("e_spread"), OBJPROP_TEXT)));
   g_finalScaleRuntime = MathMax(10, MathMin(200, StringToDouble(ObjectGetString(0, Obj("e_scale"), OBJPROP_TEXT))));
   g_targetTpRuntime = MathMax(0, MathMin(3, (int)StringToInteger(ObjectGetString(0, Obj("e_tp"), OBJPROP_TEXT))));
   g_halfTpRuntime = MathMax(0, MathMin(3, (int)StringToInteger(ObjectGetString(0, Obj("e_half"), OBJPROP_TEXT))));
   g_allowedWindowsRuntime = ObjectGetString(0, Obj("e_allowed"), OBJPROP_TEXT);
   g_noTradeWindowsRuntime = ObjectGetString(0, Obj("e_no"), OBJPROP_TEXT);
   Audit("dashboard_apply", "", 0, "", g_lotRuntime, 0, 0, 0, "max_spread=" + IntegerToString(g_maxSpreadRuntime) + " scale=" + DoubleToString(g_finalScaleRuntime,1) + " tp=" + IntegerToString(g_targetTpRuntime) + " half=" + IntegerToString(g_halfTpRuntime) + " pending_on_drift=" + (g_pendingOnDriftRuntime ? "true" : "false"), 0, "");
}

void Rect(string name, int x, int y, int w, int h, color bg, color border)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false); ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void Label(string name, int x, int y, string text, color clr, int size)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size); ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void Button(string name, int x, int y, int w, int h, string text, color bg, color fg)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg); ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}

void Edit(string name, int x, int y, int w, int h, string text)
{
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text); ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBlack); ObjectSetInteger(0, name, OBJPROP_COLOR, clrAqua);
}

void DeleteDashboard()
{
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, g_prefix) == 0) ObjectDelete(0, name);
   }
}

void DrawTradeLevels()
{
   DeleteTradeLevels();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || !IsOurMagic(OrderMagicNumber())) continue;
      int t = OrderTicket();
      HLine("GANN_LVL_" + IntegerToString(t) + "_ENTRY", OrderOpenPrice(), clrWhite, STYLE_DOT);
      HLine("GANN_LVL_" + IntegerToString(t) + "_SL", OrderStopLoss(), clrTomato, STYLE_SOLID);
      HLine("GANN_LVL_" + IntegerToString(t) + "_TP", OrderTakeProfit(), clrDodgerBlue, STYLE_SOLID);
      HLine("GANN_LVL_" + IntegerToString(t) + "_TP1", TicketGV(t, "TP1", 0), clrDeepSkyBlue, STYLE_DOT);
      HLine("GANN_LVL_" + IntegerToString(t) + "_TP2", TicketGV(t, "TP2", 0), clrRoyalBlue, STYLE_DOT);
      HLine("GANN_LVL_" + IntegerToString(t) + "_TP3", TicketGV(t, "TP3", 0), clrBlue, STYLE_DOT);
   }
}

void DrawCalculatedFallbackLevels(int ticket, double sl, double tp1, double tp2, double tp3)
{
   DeleteCalculatedFallbackLevels(ticket);
   CalcHLine("GANN_CALC_" + IntegerToString(ticket) + "_SL", sl, clrOrangeRed, STYLE_DASHDOT, "CALC SL");
   CalcHLine("GANN_CALC_" + IntegerToString(ticket) + "_TP1", tp1, clrAqua, STYLE_DASHDOT, "CALC TP1");
   CalcHLine("GANN_CALC_" + IntegerToString(ticket) + "_TP2", tp2, clrDeepSkyBlue, STYLE_DASHDOT, "CALC TP2");
   CalcHLine("GANN_CALC_" + IntegerToString(ticket) + "_TP3", tp3, clrDodgerBlue, STYLE_DASHDOT, "CALC TP3");
}

void CalcHLine(string name, double price, color clr, int style, string text)
{
   if(price <= 0.0) return;
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text + " " + PriceText(price));
}

void DeleteCalculatedFallbackLevels(int ticket)
{
   string prefix = "GANN_CALC_" + IntegerToString(ticket) + "_";
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0) ObjectDelete(0, name);
   }
}

void HLine(string name, double price, color clr, int style)
{
   if(price <= 0) return;
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr); ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DeleteTradeLevels()
{
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, "GANN_LVL_") == 0) ObjectDelete(0, name);
   }
}
