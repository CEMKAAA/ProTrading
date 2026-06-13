#property strict
#property version "1.00"

#define BUILD_TAG "2026-06-13.1800-breakout-buffer-nas-risk"
#define EMPTY_SENTINEL 2147483647.0

input string InpIndicatorName = "Asiller\\SuperSignal\\Breakout signal";
input int    InpBuyBuffer = 4;
input int    InpSellBuffer = 1;
input int    InpSignalLookbackBars = 8;
input bool   InpScanOnTick = true;
input int    InpPollSeconds = 1;
input bool   InpTradeLatestSignalOnAttach = false;

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
input int    InpMagic = 41061301;
input int    InpSlippage = 30;
input int    InpMaxSpreadPoints = 0;      // 0=off
input string InpAllowedWindowsGmt = "";   // empty=24/7, HH:MM-HH:MM,...
input string InpNoTradeWindowsGmt = "21:55-22:10";
input bool   InpCloseOppositeOnSignal = true;
input bool   InpBlockSameDirectionOpen = true;

input int    InpRiskAtrPeriod = 14;
input double InpRiskAtrMult = 1.50;
input bool   InpUseStructuralSwingStop = true;
input int    InpSwingLookbackBars = 80;
input int    InpSwingLeftBars = 3;
input int    InpSwingRightBars = 2;
input int    InpSwingAtrPeriod = 14;
input double InpSwingMinProminenceAtr = 0.75;
input double InpSwingMinDepartureAtr = 1.00;
input double InpSwingBufferAtr = 0.20;
input double InpFinalRiskScalePct = 75.0; // 100=unchanged; 75 trims final SL/TP distance by 25%.
input int    InpTargetTpIndex = 2;        // 0=broker TP off, 1..3 full close target leg
input int    InpHalfBeTpIndex = 0;        // 0=off, 1..3 half close + SL->BE leg

input bool   InpShowDashboard = true;
input int    InpDashboardX = 18;
input int    InpDashboardY = 28;

input bool   InpAdvancedAccountRiskEnabled = false;
input bool   InpAutoLotByRisk = true;
input double InpAccountRiskPerTradePct = 1.0;
input double InpMaxPortfolioRiskPct = 4.0;
input double InpDailyLossLimitPct = 0.0;  // 0=off
input double InpMaxDrawdownPct = 0.0;     // 0=off
input double InpMaxMarginUsagePct = 40.0;
input double InpInitialBalanceOverride = 0.0;
input int    InpDayResetHourGmt = 0;
input bool   InpRiskScopeByMagic = true;
input bool   InpLiquidateOnBreach = false;
input int    InpRiskAuditSeconds = 60;

input bool   InpEnableAudit = true;
input int    InpPositionProbeSeconds = 30;

string   g_prefix;
bool     g_eaEnabled;
bool     g_collapsed = false;
double   g_lotRuntime;
int      g_maxSpreadRuntime;
double   g_finalScaleRuntime;
int      g_targetTpRuntime;
int      g_halfTpRuntime;
string   g_allowedWindowsRuntime;
string   g_noTradeWindowsRuntime;
string   g_lastEventId = "";
string   g_lastSignalDir = "-";
datetime g_lastSignalTime = 0;
double   g_lastSignalPrice = 0.0;
datetime g_lastScanTs = 0;
datetime g_lastRiskAuditTs = 0;
datetime g_lastProbeTs = 0;

int OnInit()
{
   g_prefix = "BRK_" + IntegerToString((int)ChartID()) + "_";
   g_eaEnabled = InpDirectEnabled;
   g_lotRuntime = InpManualLot;
   g_maxSpreadRuntime = InpMaxSpreadPoints;
   g_finalScaleRuntime = MathMax(10.0, MathMin(200.0, InpFinalRiskScalePct));
   g_targetTpRuntime = MathMax(0, MathMin(3, InpTargetTpIndex));
   g_halfTpRuntime = MathMax(0, MathMin(3, InpHalfBeTpIndex));
   g_allowedWindowsRuntime = InpAllowedWindowsGmt;
   g_noTradeWindowsRuntime = InpNoTradeWindowsGmt;
   EventSetTimer(MathMax(1, InpPollSeconds));

   if(InpShowDashboard) DashboardCreate();
   Audit("init", "", 0, "", 0, 0, 0, 0, "build=" + BUILD_TAG + " indicator=" + InpIndicatorName, 0, "");
   RiskAudit("init", "build=" + BUILD_TAG);

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
   Print("BreakoutSignalBridge BUILD=", BUILD_TAG, " indicator=", InpIndicatorName, " buyBuffer=", InpBuyBuffer, " sellBuffer=", InpSellBuffer);
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
   if(InpShowDashboard) DashboardUpdate();
}

void OnTimer()
{
   ProcessSignals("timer");
   ManagePositions();
   MaybeProbe();
   MaybeRiskAudit();
   if(InpShowDashboard) DashboardUpdate();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
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

   Audit("signal_detected", eid, 0, dir, 0, sigPx, 0, 0, "reason=" + reason + " shift=" + IntegerToString(sh) + " buffer=" + IntegerToString(buf) + " bar=" + TimeToString(barTime, TIME_DATE|TIME_SECONDS), 0, "");
   ExecuteSignal(dir, eid, sigPx, sh, buf);
}

bool FindLatestSignal(string &dir, int &shift, int &buffer, double &price, datetime &barTime, string &eventId)
{
   bool found = false;
   int bestShift = 1000000;
   string bestDir = "";
   int bestBuffer = -1;
   double bestPrice = 0.0;
   for(int s = 0; s <= MathMax(0, InpSignalLookbackBars); s++)
   {
      double b = ReadBuffer(InpBuyBuffer, s);
      double se = ReadBuffer(InpSellBuffer, s);
      if(IsSignalValue(b) && s < bestShift) { found = true; bestShift = s; bestDir = "BUY"; bestBuffer = InpBuyBuffer; bestPrice = b; }
      if(IsSignalValue(se) && s < bestShift) { found = true; bestShift = s; bestDir = "SELL"; bestBuffer = InpSellBuffer; bestPrice = se; }
   }
   if(!found || bestShift >= Bars) return false;
   dir = bestDir;
   shift = bestShift;
   buffer = bestBuffer;
   price = bestPrice;
   barTime = Time[bestShift];
   eventId = Symbol() + "|" + IntegerToString(Period()) + "|breakout|" + dir + "|" + IntegerToString((int)barTime) + "|" + IntegerToString(buffer) + "|" + IntegerToString(shift) + "|" + DoubleToString(price, Digits);
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

void ExecuteSignal(string dir, string eventId, double signalPx, int shift, int buffer)
{
   RefreshRates();
   int type = (dir == "BUY") ? OP_BUY : OP_SELL;
   double entry = (type == OP_BUY) ? Ask : Bid;
   double sl, tp1, tp2, tp3;
   string geom;
   if(!BuildGeometry(type, entry, shift, sl, tp1, tp2, tp3, geom))
   {
      Audit("trade_blocked_geometry", eventId, 0, dir, 0, entry, sl, 0, geom, 0, "");
      return;
   }
   double target = TpByIndex(g_targetTpRuntime, tp1, tp2, tp3);
   double half = TpByIndex(g_halfTpRuntime, tp1, tp2, tp3);
   Audit("signal_received", eventId, 0, dir, g_lotRuntime, signalPx, sl, target, "source_buffer=" + IntegerToString(buffer) + " shift=" + IntegerToString(shift) + " " + geom + " half_trigger=" + PriceText(half), 0, "");

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

   int ticket = OrderSend(Symbol(), type, lot, NormalizeDouble(entry, Digits), InpSlippage, NormalizeDouble(sl, Digits), NormalizeDouble(target, Digits), "BreakoutBridge " + dir, EffectiveMagic(), 0, (type == OP_BUY ? clrLime : clrTomato));
   int err = GetLastError();
   if(ticket > 0)
   {
      if(OrderSelect(ticket, SELECT_BY_TICKET)) entry = OrderOpenPrice();
      StoreTicket(ticket, tp1, tp2, tp3, half, g_halfTpRuntime, g_targetTpRuntime);
      Audit("order_sent", eventId, ticket, dir, lot, entry, sl, target, "ticket=" + IntegerToString(ticket) + " " + lotDetail + " tp1=" + PriceText(tp1) + " tp2=" + PriceText(tp2) + " tp3=" + PriceText(tp3), 0, "");
      RiskAudit("lot_selected", "event=" + eventId + " ticket=" + IntegerToString(ticket) + " lot=" + DoubleToString(lot, 3) + " " + lotDetail);
      DrawTradeLevels();
   }
   else Audit("order_failed", eventId, 0, dir, lot, entry, sl, target, "err=" + IntegerToString(err) + " " + lotDetail, 0, "");
}

bool BuildGeometry(int type, double entry, int signalShift, double &sl, double &tp1, double &tp2, double &tp3, string &detail)
{
   int atrShift = MathMax(1, signalShift);
   double atr = iATR(Symbol(), Period(), InpRiskAtrPeriod, atrShift);
   if(atr <= Point * 2) atr = iATR(Symbol(), Period(), InpRiskAtrPeriod, 1);
   if(atr <= Point * 2) { detail = "atr_unavailable"; return false; }

   double risk = MathMax(Point * 10, atr * MathMax(0.1, InpRiskAtrMult));
   sl = (type == OP_BUY) ? entry - risk : entry + risk;
   detail = "base_atr=" + DoubleToString(atr, Digits) + " atr_mult=" + DoubleToString(InpRiskAtrMult, 2);

   if(InpUseStructuralSwingStop)
   {
      double swingSl, swingRisk; string swingDetail;
      if(FindStructuralSwingStop(type, signalShift, entry, swingSl, swingRisk, swingDetail))
      {
         if(swingRisk > risk) { risk = swingRisk; sl = swingSl; detail += " structural=wider " + swingDetail; }
         else detail += " structural=ignored_narrower " + swingDetail;
      }
      else detail += " structural=none " + swingDetail;
   }

   risk = MathAbs(entry - sl) * MathMax(10.0, MathMin(200.0, g_finalScaleRuntime)) / 100.0;
   if(type == OP_BUY) { sl = entry - risk; tp1 = entry + risk; tp2 = entry + 2 * risk; tp3 = entry + 3 * risk; }
   else { sl = entry + risk; tp1 = entry - risk; tp2 = entry - 2 * risk; tp3 = entry - 3 * risk; }
   detail += " final_scale_pct=" + DoubleToString(g_finalScaleRuntime, 1) + " final_risk=" + DoubleToString(risk, Digits);
   if(type == OP_BUY && !(sl < entry && tp1 > entry)) return false;
   if(type == OP_SELL && !(sl > entry && tp1 < entry)) return false;
   sl = NormalizeDouble(sl, Digits); tp1 = NormalizeDouble(tp1, Digits); tp2 = NormalizeDouble(tp2, Digits); tp3 = NormalizeDouble(tp3, Digits);
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
         if(ok2) Audit("full_tp_close_done", TicketEvent(ticket), ticket, dir, lots, px, OrderStopLoss(), target, "manual_guard_tp_reached", OrderProfit(), "");
         else Audit("full_tp_close_failed", TicketEvent(ticket), ticket, dir, lots, px, OrderStopLoss(), target, "err=" + IntegerToString(err2), 0, "broker_tp_may_handle_it");
      }
   }
   DrawTradeLevels();
}

bool PriceReached(int type, double price, double level) { if(level <= 0) return false; return (type == OP_BUY) ? (price >= level) : (price <= level); }

void MoveSlToBE(int ticket, int type)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   double be = NormalizeDouble(OrderOpenPrice(), Digits);
   double sl = OrderStopLoss();
   bool improve = (type == OP_BUY && (sl <= 0 || be > sl + Point)) || (type == OP_SELL && (sl <= 0 || be < sl - Point));
   if(!improve) return;
   bool ok = OrderModify(ticket, OrderOpenPrice(), be, OrderTakeProfit(), 0, clrAqua);
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
      Audit(ok ? "reverse_close_done" : "reverse_close_failed", eventId, ticket, (opposite == OP_BUY ? "BUY" : "SELL"), OrderLots(), px, OrderStopLoss(), OrderTakeProfit(), ok ? "before_new_signal" : "err=" + IntegerToString(err), OrderProfit(), "");
   }
}

bool HasOpenDirection(int type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderSymbol() == Symbol() && IsOurMagic(OrderMagicNumber()) && OrderType() == type) return true;
   return false;
}

int EffectiveMagic() { if(InpAdvancedAccountRiskEnabled) return 1000000000 + MathAbs(InpMagic % 900000000); return InpMagic; }
bool IsOurMagic(int magic) { return magic == InpMagic || magic == EffectiveMagic(); }

double ResolveLot(double entry, double sl, int type, bool requireHalfSplit, string &detail)
{
   double fallback = NormalizeOrderLot(g_lotRuntime, requireHalfSplit);
   if(!InpAdvancedAccountRiskEnabled) { detail = "risk_engine=off lot=" + DoubleToString(fallback, 3); return fallback; }
   double cap, daily, dd;
   AccountRiskMetrics(cap, daily, dd);
   if(InpDailyLossLimitPct > 0 && daily >= InpDailyLossLimitPct) { if(InpLiquidateOnBreach) LiquidateScoped("daily_loss_breach"); detail = "risk_block daily_loss_pct=" + DoubleToString(daily,2); return 0; }
   if(InpMaxDrawdownPct > 0 && dd >= InpMaxDrawdownPct) { if(InpLiquidateOnBreach) LiquidateScoped("max_drawdown_breach"); detail = "risk_block total_dd_pct=" + DoubleToString(dd,2); return 0; }
   double riskPerLot = MoneyRiskPerLot(entry, sl);
   if(riskPerLot <= 0) { detail = "risk_block invalid_risk_per_lot"; return 0; }
   double tradeBudget = cap * MathMax(0.0, InpAccountRiskPerTradePct) / 100.0;
   double openRisk = CurrentOpenRisk();
   double portfolioBudget = cap * MathMax(0.0, InpMaxPortfolioRiskPct) / 100.0 - openRisk;
   double budget = (InpMaxPortfolioRiskPct > 0) ? MathMin(tradeBudget, portfolioBudget) : tradeBudget;
   if(budget <= 0) { detail = "risk_block exhausted_budget open_risk=" + DoubleToString(openRisk,2); return 0; }
   double rawLot = InpAutoLotByRisk ? budget / riskPerLot : fallback;
   double lot = NormalizeOrderLot(rawLot, requireHalfSplit);
   if(lot <= 0) { detail = "risk_block lot_below_min raw=" + DoubleToString(rawLot,4); return 0; }
   double freeAfter = AccountFreeMarginCheck(Symbol(), type, lot);
   double marginUsedPct = (AccountEquity() > 0) ? (AccountEquity() - freeAfter) / AccountEquity() * 100.0 : 0.0;
   if(freeAfter <= 0 || (InpMaxMarginUsagePct > 0 && marginUsedPct > InpMaxMarginUsagePct)) { detail = "risk_block margin lot=" + DoubleToString(lot,3); return 0; }
   detail = "risk_engine=on lot=" + DoubleToString(lot,3) + " risk_capital=" + DoubleToString(cap,2) + " budget=" + DoubleToString(budget,2) + " risk_per_lot=" + DoubleToString(riskPerLot,2) + " open_risk=" + DoubleToString(openRisk,2) + " daily_loss_pct=" + DoubleToString(daily,2) + " total_dd_pct=" + DoubleToString(dd,2);
   return lot;
}

double MoneyRiskPerLot(double entry, double sl)
{
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE), tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   if(tickSize <= 0 || tickValue <= 0) return 0;
   return MathAbs(entry - sl) / tickSize * tickValue;
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

string RiskKey(string kind) { return "BreakoutBridgeRisk|" + IntegerToString(AccountNumber()) + "|" + Symbol() + "|" + IntegerToString(Period()) + "|" + IntegerToString(EffectiveMagic()) + "|" + kind; }

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
   if(sym != Symbol()) return false;
   if(!InpRiskScopeByMagic) return true;
   return IsOurMagic(magic);
}

double CurrentOpenRisk()
{
   double total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!RiskOrderInScope(OrderSymbol(), OrderMagicNumber())) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderStopLoss() <= 0) continue;
      total += MoneyRiskPerLot(OrderOpenPrice(), OrderStopLoss()) * OrderLots();
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
      RefreshRates();
      double px = (type == OP_BUY) ? Bid : Ask;
      bool ok = OrderClose(OrderTicket(), OrderLots(), px, InpSlippage, clrRed);
      Audit(ok ? "risk_liquidation_close_done" : "risk_liquidation_close_failed", TicketEvent(OrderTicket()), OrderTicket(), (type == OP_BUY ? "BUY" : "SELL"), OrderLots(), px, OrderStopLoss(), OrderTakeProfit(), reason, OrderProfit(), "");
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

void StoreTicket(int ticket, double tp1, double tp2, double tp3, double half, int halfIdx, int targetIdx)
{
   TicketGVSet(ticket, "TP1", tp1); TicketGVSet(ticket, "TP2", tp2); TicketGVSet(ticket, "TP3", tp3);
   TicketGVSet(ticket, "HTP", half); TicketGVSet(ticket, "HIDX", halfIdx); TicketGVSet(ticket, "TIDX", targetIdx); TicketGVSet(ticket, "HDONE", 0);
}

string TicketKey(int ticket, string field) { return "BreakoutBridge|" + IntegerToString(AccountNumber()) + "|" + IntegerToString(ticket) + "|" + field; }
double TicketGV(int ticket, string field, double def) { string key = TicketKey(ticket, field); if(!GlobalVariableCheck(key)) return def; return GlobalVariableGet(key); }
void TicketGVSet(int ticket, string field, double value) { GlobalVariableSet(TicketKey(ticket, field), value); }
string TicketEvent(int ticket) { return "ticket=" + IntegerToString(ticket); }

void MaybeRiskAudit()
{
   if(!InpAdvancedAccountRiskEnabled || InpRiskAuditSeconds <= 0) return;
   datetime now = TimeGMT();
   if(now - g_lastRiskAuditTs < InpRiskAuditSeconds) return;
   g_lastRiskAuditTs = now;
   RiskAudit("snapshot", "periodic");
}

void MaybeProbe()
{
   if(InpPositionProbeSeconds <= 0) return;
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

void RiskAudit(string eventName, string detail)
{
   if(!InpEnableAudit) return;
   double cap, daily, dd;
   AccountRiskMetrics(cap, daily, dd);
   int h = FileOpen("BreakoutBridge_AccountRiskAudit_" + DateStamp(TimeGMT()) + ".csv", FILE_CSV|FILE_READ|FILE_WRITE, ';');
   if(h == INVALID_HANDLE) return;
   bool header = (FileSize(h) == 0);
   FileSeek(h, 0, SEEK_END);
   if(header) FileWrite(h, "gmt", "broker", "account", "symbol", "tf", "event", "risk_capital", "open_risk", "daily_loss_pct", "total_dd_pct", "enabled", "detail");
   FileWrite(h, TimeToString(TimeGMT(), TIME_DATE|TIME_SECONDS), TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), AccountNumber(), Symbol(), Period(), eventName, DoubleToString(cap, 2), DoubleToString(CurrentOpenRisk(), 2), DoubleToString(daily, 3), DoubleToString(dd, 3), InpAdvancedAccountRiskEnabled ? "true" : "false", detail);
   FileClose(h);
}

void Audit(string eventName, string eventId, int ticket, string dir, double lot, double price, double sl, double tp, string detail, double pnl, string extra)
{
   if(!InpEnableAudit) return;
   int h = FileOpen("BreakoutSignalBridge_DirectAudit_" + DateStamp(TimeGMT()) + ".csv", FILE_CSV|FILE_READ|FILE_WRITE, ';');
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
   int x = InpDashboardX, y = InpDashboardY, w = 390, h = g_collapsed ? 34 : 280;
   Rect(Obj("bg"), x, y, w, h, clrDimGray, clrBlack);
   Label(Obj("title"), x+12, y+8, "BREAKOUT BRIDGE // " + BUILD_TAG, clrAliceBlue, 9);
   Button(Obj("collapse"), x+w-32, y+6, 24, 20, g_collapsed ? "v" : "^", clrSlateGray, clrWhite);
   if(g_collapsed) return;
   Button(Obj("toggle"), x+12, y+34, 78, 24, g_eaEnabled ? "EA ON" : "EA OFF", g_eaEnabled ? clrDarkGreen : clrMaroon, clrWhite);
   Button(Obj("apply"), x+302, y+34, 72, 24, "APPLY", clrSteelBlue, clrWhite);
   Label(Obj("l_lot"), x+12, y+68, "Lot", clrLightSteelBlue, 8); Edit(Obj("e_lot"), x+86, y+64, 58, 20, DoubleToString(g_lotRuntime, 2));
   Label(Obj("l_spread"), x+152, y+68, "MaxSpr", clrLightSteelBlue, 8); Edit(Obj("e_spread"), x+210, y+64, 50, 20, IntegerToString(g_maxSpreadRuntime));
   Label(Obj("l_scale"), x+270, y+68, "SL%", clrLightSteelBlue, 8); Edit(Obj("e_scale"), x+318, y+64, 56, 20, DoubleToString(g_finalScaleRuntime, 1));
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
   if(g_collapsed) return;
   string sigTime = (g_lastSignalTime > 0) ? TimeToString(g_lastSignalTime, TIME_DATE|TIME_MINUTES) : "-";
   ObjectSetString(0, Obj("status"), OBJPROP_TEXT, "Spread " + IntegerToString(CurrentSpreadPoints()) + " pt | " + (InpAdvancedAccountRiskEnabled ? "RISK ON" : "RISK OFF") + " | Magic " + IntegerToString(EffectiveMagic()));
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
   Audit("dashboard_apply", "", 0, "", g_lotRuntime, 0, 0, 0, "max_spread=" + IntegerToString(g_maxSpreadRuntime) + " scale=" + DoubleToString(g_finalScaleRuntime,1) + " tp=" + IntegerToString(g_targetTpRuntime) + " half=" + IntegerToString(g_halfTpRuntime), 0, "");
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
      HLine("BRK_LVL_" + IntegerToString(t) + "_ENTRY", OrderOpenPrice(), clrWhite, STYLE_DOT);
      HLine("BRK_LVL_" + IntegerToString(t) + "_SL", OrderStopLoss(), clrTomato, STYLE_SOLID);
      HLine("BRK_LVL_" + IntegerToString(t) + "_TP", OrderTakeProfit(), clrDodgerBlue, STYLE_SOLID);
      HLine("BRK_LVL_" + IntegerToString(t) + "_TP1", TicketGV(t, "TP1", 0), clrDeepSkyBlue, STYLE_DOT);
      HLine("BRK_LVL_" + IntegerToString(t) + "_TP2", TicketGV(t, "TP2", 0), clrRoyalBlue, STYLE_DOT);
      HLine("BRK_LVL_" + IntegerToString(t) + "_TP3", TicketGV(t, "TP3", 0), clrBlue, STYLE_DOT);
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
      if(StringFind(name, "BRK_LVL_") == 0) ObjectDelete(0, name);
   }
}
