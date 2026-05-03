//+------------------------------------------------------------------+
//| ProfitGovernor MT4 EA                                            |
//| Manual close buttons + TF magic-group profit governor for MT4.    |
//+------------------------------------------------------------------+
#property strict

input bool InpOnlyCurrentSymbol = false;       // false = whole MT4 terminal/account
input int  InpMagicNumberFilter = -1;          // -1 = all magic numbers
input bool InpClosePendingOrders = false;      // true = also delete pending orders
input int  InpSlippagePoints = 50;
input int  InpMaxClosePasses = 5;
input int  InpButtonX = 12;
input int  InpButtonY = 24;
input int  InpButtonWidth = 112;
input int  InpButtonHeight = 28;
input int  InpButtonGap = 8;
input double InpInitialLot = 0.10;
input double InpLotStep = 0.01;
input int InpOpenMagicNumber = 0;
input string InpOpenComment = "manual_button";

input bool InpAutoCloseProfitEnabled = false;         // Legacy chart-scope target. Keep false when using TF group governor.
input double InpAutoCloseProfitTargetUsd = 50.0;      // Account currency target, e.g. 50 USD
input bool InpTfGroupProfitEnabled = true;            // Auto-close TF magic groups by their own targets
input double InpTfTargetM1 = 20.0;
input double InpTfTargetM5 = 40.0;
input double InpTfTargetM15 = 100.0;
input double InpTfTargetM30 = 0.0;                    // 0 disables that TF target
input double InpTfTargetH1 = 0.0;
input bool InpAutoCloseUseHjfxTfMagic = true;         // true = chart TF maps to HJFX magic below
input int InpAutoCloseMagicOverride = -1;             // >=0 overrides HJFX TF magic for auto-close only
input bool InpAutoCloseRequireMagic = true;           // true = never auto-close orders outside selected magic
input int InpHjfxMagicM1 = 658701;
input int InpHjfxMagicM5 = 658705;
input int InpHjfxMagicM15 = 658715;
input int InpHjfxMagicM30 = 658730;
input int InpHjfxMagicH1 = 658760;
input bool InpIncludeIndicatorV2Magic = true;         // ProTrading Indicator Automation V2 backend magics.
input int InpIndicatorV2MagicM1 = 970101;
input int InpIndicatorV2MagicM5 = 970105;
input int InpIndicatorV2MagicM15 = 970115;
input int InpIndicatorV2MagicM30 = 970130;
input int InpIndicatorV2MagicH1 = 970160;
input bool InpIncludeTmaProMagic = false;             // Optional: standalone TMA_MACD_PRO TF-offset magics.
input string InpTmaMagicBasesCsv = "860500,860600,860700,860800";
input int InpTmaMagicOffsetM1 = 10000;
input int InpTmaMagicOffsetM5 = 20000;
input int InpTmaMagicOffsetM15 = 30000;
input int InpTmaMagicOffsetM30 = 40000;
input int InpTmaMagicOffsetH1 = 50000;
input string InpExtraMagicM1Csv = "";                  // Optional legacy/current open magics to force into M1 group.
input string InpExtraMagicM5Csv = "";
input string InpExtraMagicM15Csv = "";
input string InpExtraMagicM30Csv = "";
input string InpExtraMagicH1Csv = "";
input int InpAutoCloseCheckSeconds = 1;
input int InpAutoCloseCooldownSeconds = 10;

string BTN_CLOSE_BUY = "PT4_MANUAL_CLOSE_BUY";
string BTN_CLOSE_SELL = "PT4_MANUAL_CLOSE_SELL";
string BTN_CLOSE_ALL = "PT4_MANUAL_CLOSE_ALL";
string BTN_LOT_DOWN = "PT4_MANUAL_LOT_DOWN";
string BTN_LOT_EDIT = "PT4_MANUAL_LOT_EDIT";
string BTN_LOT_UP = "PT4_MANUAL_LOT_UP";
string BTN_OPEN_BUY = "PT4_MANUAL_OPEN_BUY";
string BTN_OPEN_SELL = "PT4_MANUAL_OPEN_SELL";
string BTN_TF_SAVE = "PT4_TF_SAVE";
string BTN_TF_CLOSE_M1 = "PT4_TF_CLOSE_M1";
string BTN_TF_CLOSE_M5 = "PT4_TF_CLOSE_M5";
string BTN_TF_CLOSE_M15 = "PT4_TF_CLOSE_M15";
string BTN_TF_CLOSE_M30 = "PT4_TF_CLOSE_M30";
string BTN_TF_CLOSE_H1 = "PT4_TF_CLOSE_H1";
string BTN_TF_EDIT_M1 = "PT4_TF_EDIT_M1";
string BTN_TF_EDIT_M5 = "PT4_TF_EDIT_M5";
string BTN_TF_EDIT_M15 = "PT4_TF_EDIT_M15";
string BTN_TF_EDIT_M30 = "PT4_TF_EDIT_M30";
string BTN_TF_EDIT_H1 = "PT4_TF_EDIT_H1";
string LBL_TF_TITLE = "PT4_TF_TITLE";
string LBL_TF_M1 = "PT4_TF_LBL_M1";
string LBL_TF_M5 = "PT4_TF_LBL_M5";
string LBL_TF_M15 = "PT4_TF_LBL_M15";
string LBL_TF_M30 = "PT4_TF_LBL_M30";
string LBL_TF_H1 = "PT4_TF_LBL_H1";
string LBL_TF_STATUS = "PT4_TF_STATUS";

double g_lot = 0.10;
bool g_auto_close_in_progress = false;
datetime g_last_auto_close_at = 0;
double g_tf_target_m1 = 0.0;
double g_tf_target_m5 = 0.0;
double g_tf_target_m15 = 0.0;
double g_tf_target_m30 = 0.0;
double g_tf_target_h1 = 0.0;
double g_tf_pnl_m1 = 0.0;
double g_tf_pnl_m5 = 0.0;
double g_tf_pnl_m15 = 0.0;
double g_tf_pnl_m30 = 0.0;
double g_tf_pnl_h1 = 0.0;
int g_tf_count_m1 = 0;
int g_tf_count_m5 = 0;
int g_tf_count_m15 = 0;
int g_tf_count_m30 = 0;
int g_tf_count_h1 = 0;
string g_tf_status = "TF governor initialized";

string ChartTimeframeText()
{
   int tf = Period();
   if(tf == PERIOD_M1) return "M1";
   if(tf == PERIOD_M5) return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1) return "H1";
   if(tf == PERIOD_H4) return "H4";
   if(tf == PERIOD_D1) return "D1";
   if(tf == PERIOD_W1) return "W1";
   if(tf == PERIOD_MN1) return "MN1";
   return IntegerToString(tf);
}

bool SymbolAllowed(const string symbol)
{
   if(!InpOnlyCurrentSymbol) return true;
   return (StringCompare(symbol, Symbol(), false) == 0);
}

bool MagicAllowed(const int magic)
{
   if(InpMagicNumberFilter < 0) return true;
   return (magic == InpMagicNumberFilter);
}

int ChartHjfxMagic()
{
   int tf = Period();
   if(tf == PERIOD_M1) return InpHjfxMagicM1;
   if(tf == PERIOD_M5) return InpHjfxMagicM5;
   if(tf == PERIOD_M15) return InpHjfxMagicM15;
   if(tf == PERIOD_M30) return InpHjfxMagicM30;
   if(tf == PERIOD_H1) return InpHjfxMagicH1;
   return -1;
}

string SettingsKey(const string suffix)
{
   string scope = InpOnlyCurrentSymbol ? Symbol() : "ALL";
   return "PT4_PROFIT_GOV_" + IntegerToString(AccountNumber()) + "_" + scope + "_" + suffix;
}

void LoadTfTargets()
{
   g_tf_target_m1 = InpTfTargetM1;
   g_tf_target_m5 = InpTfTargetM5;
   g_tf_target_m15 = InpTfTargetM15;
   g_tf_target_m30 = InpTfTargetM30;
   g_tf_target_h1 = InpTfTargetH1;

   if(GlobalVariableCheck(SettingsKey("M1"))) g_tf_target_m1 = GlobalVariableGet(SettingsKey("M1"));
   if(GlobalVariableCheck(SettingsKey("M5"))) g_tf_target_m5 = GlobalVariableGet(SettingsKey("M5"));
   if(GlobalVariableCheck(SettingsKey("M15"))) g_tf_target_m15 = GlobalVariableGet(SettingsKey("M15"));
   if(GlobalVariableCheck(SettingsKey("M30"))) g_tf_target_m30 = GlobalVariableGet(SettingsKey("M30"));
   if(GlobalVariableCheck(SettingsKey("H1"))) g_tf_target_h1 = GlobalVariableGet(SettingsKey("H1"));
}

void SaveTfTargets()
{
   GlobalVariableSet(SettingsKey("M1"), g_tf_target_m1);
   GlobalVariableSet(SettingsKey("M5"), g_tf_target_m5);
   GlobalVariableSet(SettingsKey("M15"), g_tf_target_m15);
   GlobalVariableSet(SettingsKey("M30"), g_tf_target_m30);
   GlobalVariableSet(SettingsKey("H1"), g_tf_target_h1);
}

double ParseEditDouble(const string objectName, const double fallback)
{
   if(ObjectFind(0, objectName) < 0) return fallback;
   string raw = ObjectGetString(0, objectName, OBJPROP_TEXT);
   StringReplace(raw, ",", ".");
   double value = StringToDouble(raw);
   if(value < 0.0) value = 0.0;
   return value;
}

int TfMagicByName(const string tf)
{
   if(tf == "M1") return InpHjfxMagicM1;
   if(tf == "M5") return InpHjfxMagicM5;
   if(tf == "M15") return InpHjfxMagicM15;
   if(tf == "M30") return InpHjfxMagicM30;
   if(tf == "H1") return InpHjfxMagicH1;
   return -1;
}

bool MagicBelongsToTf(const string tf, const int magic);

bool IsTfMagic(const int magic)
{
   return (
      MagicBelongsToTf("M1", magic) ||
      MagicBelongsToTf("M5", magic) ||
      MagicBelongsToTf("M15", magic) ||
      MagicBelongsToTf("M30", magic) ||
      MagicBelongsToTf("H1", magic)
   );
}

int TmaOffsetByTf(const string tf)
{
   if(tf == "M1") return InpTmaMagicOffsetM1;
   if(tf == "M5") return InpTmaMagicOffsetM5;
   if(tf == "M15") return InpTmaMagicOffsetM15;
   if(tf == "M30") return InpTmaMagicOffsetM30;
   if(tf == "H1") return InpTmaMagicOffsetH1;
   return 0;
}

bool TmaMagicMatchesTf(const string tf, const int magic)
{
   if(!InpIncludeTmaProMagic) return false;
   int offset = TmaOffsetByTf(tf);
   if(offset <= 0) return false;

   string csv = InpTmaMagicBasesCsv;
   int start = 0;
   while(start < StringLen(csv))
   {
      int comma = StringFind(csv, ",", start);
      string part = (comma < 0) ? StringSubstr(csv, start) : StringSubstr(csv, start, comma - start);
      int base = (int)StringToInteger(part);
      if(base > 0 && (magic == base + offset + 1 || magic == base + offset + 2))
         return true;
      if(comma < 0) break;
      start = comma + 1;
   }
   return false;
}

string ExtraMagicCsvByTf(const string tf)
{
   if(tf == "M1") return InpExtraMagicM1Csv;
   if(tf == "M5") return InpExtraMagicM5Csv;
   if(tf == "M15") return InpExtraMagicM15Csv;
   if(tf == "M30") return InpExtraMagicM30Csv;
   if(tf == "H1") return InpExtraMagicH1Csv;
   return "";
}

bool CsvContainsMagic(string csv, const int magic)
{
   int start = 0;
   while(start < StringLen(csv))
   {
      int comma = StringFind(csv, ",", start);
      string part = (comma < 0) ? StringSubstr(csv, start) : StringSubstr(csv, start, comma - start);
      int value = (int)StringToInteger(part);
      if(value == magic) return true;
      if(comma < 0) break;
      start = comma + 1;
   }
   return false;
}

bool MagicBelongsToTf(const string tf, const int magic)
{
   int hjfx = TfMagicByName(tf);
   if(hjfx >= 0 && magic == hjfx) return true;
   if(InpIncludeIndicatorV2Magic)
   {
      if(tf == "M1" && magic == InpIndicatorV2MagicM1) return true;
      if(tf == "M5" && magic == InpIndicatorV2MagicM5) return true;
      if(tf == "M15" && magic == InpIndicatorV2MagicM15) return true;
      if(tf == "M30" && magic == InpIndicatorV2MagicM30) return true;
      if(tf == "H1" && magic == InpIndicatorV2MagicH1) return true;
   }
   if(CsvContainsMagic(ExtraMagicCsvByTf(tf), magic)) return true;
   return TmaMagicMatchesTf(tf, magic);
}

bool OrderAllowedForTfGovernor()
{
   if(OrderType() != OP_BUY && OrderType() != OP_SELL) return false;
   if(InpOnlyCurrentSymbol && StringCompare(OrderSymbol(), Symbol(), false) != 0) return false;
   if(InpAutoCloseRequireMagic && !IsTfMagic(OrderMagicNumber())) return false;
   return IsTfMagic(OrderMagicNumber());
}

int AutoCloseMagicFilter()
{
   if(InpAutoCloseMagicOverride >= 0) return InpAutoCloseMagicOverride;
   if(InpAutoCloseUseHjfxTfMagic) return ChartHjfxMagic();
   return InpMagicNumberFilter;
}

bool AutoCloseOrderAllowed()
{
   if(OrderType() != OP_BUY && OrderType() != OP_SELL) return false;
   if(StringCompare(OrderSymbol(), Symbol(), false) != 0) return false;

   int selectedMagic = AutoCloseMagicFilter();
   if(selectedMagic >= 0)
      return (OrderMagicNumber() == selectedMagic);
   if(InpAutoCloseRequireMagic)
      return false;
   return true;
}

void ResetTfPnl()
{
   g_tf_pnl_m1 = 0.0; g_tf_count_m1 = 0;
   g_tf_pnl_m5 = 0.0; g_tf_count_m5 = 0;
   g_tf_pnl_m15 = 0.0; g_tf_count_m15 = 0;
   g_tf_pnl_m30 = 0.0; g_tf_count_m30 = 0;
   g_tf_pnl_h1 = 0.0; g_tf_count_h1 = 0;
}

void AddTfPnl(const int magic, const double pnl)
{
   if(MagicBelongsToTf("M1", magic)) { g_tf_pnl_m1 += pnl; g_tf_count_m1++; return; }
   if(MagicBelongsToTf("M5", magic)) { g_tf_pnl_m5 += pnl; g_tf_count_m5++; return; }
   if(MagicBelongsToTf("M15", magic)) { g_tf_pnl_m15 += pnl; g_tf_count_m15++; return; }
   if(MagicBelongsToTf("M30", magic)) { g_tf_pnl_m30 += pnl; g_tf_count_m30++; return; }
   if(MagicBelongsToTf("H1", magic)) { g_tf_pnl_h1 += pnl; g_tf_count_h1++; return; }
}

void RefreshTfGroupPnl()
{
   ResetTfPnl();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!OrderAllowedForTfGovernor()) continue;
      AddTfPnl(OrderMagicNumber(), OrderProfit() + OrderSwap() + OrderCommission());
   }
}

double SymbolMinLot(const string symbol)
{
   double v = MarketInfo(symbol, MODE_MINLOT);
   if(v <= 0.0) v = 0.01;
   return v;
}

double SymbolMaxLot(const string symbol)
{
   double v = MarketInfo(symbol, MODE_MAXLOT);
   if(v <= 0.0) v = 100.0;
   return v;
}

double SymbolLotStep(const string symbol)
{
   double v = MarketInfo(symbol, MODE_LOTSTEP);
   if(v <= 0.0) v = InpLotStep;
   if(v <= 0.0) v = 0.01;
   return v;
}

double NormalizeLot(const string symbol, const double lot)
{
   double minLot = SymbolMinLot(symbol);
   double maxLot = SymbolMaxLot(symbol);
   double step = SymbolLotStep(symbol);
   double v = MathMax(minLot, MathMin(maxLot, lot));
   v = MathFloor((v / step) + 1e-9) * step;
   v = MathMax(minLot, MathMin(maxLot, v));
   int digits = 2;
   if(step < 0.01) digits = 3;
   if(step < 0.001) digits = 4;
   return NormalizeDouble(v, digits);
}

string LotText(const double lot)
{
   return DoubleToString(NormalizeLot(Symbol(), lot), 2);
}

void SetObjectText(const string name, const string text)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void UpdateLotEdit()
{
   SetObjectText(BTN_LOT_EDIT, LotText(g_lot));
}

void SetLot(const double lot)
{
   g_lot = NormalizeLot(Symbol(), lot);
   UpdateLotEdit();
}

void NudgeLot(const int dir)
{
   double step = SymbolLotStep(Symbol());
   if(InpLotStep > 0.0) step = InpLotStep;
   SetLot(g_lot + (double)dir * step);
}

void ReadLotFromEdit()
{
   if(ObjectFind(0, BTN_LOT_EDIT) < 0) return;
   string raw = ObjectGetString(0, BTN_LOT_EDIT, OBJPROP_TEXT);
   StringReplace(raw, ",", ".");
   double v = StringToDouble(raw);
   if(v <= 0.0) v = g_lot;
   SetLot(v);
}

bool PendingTypeMatches(const int type, string side)
{
   StringToUpper(side);
   if(side == "BUY") return (type == OP_BUYLIMIT || type == OP_BUYSTOP);
   if(side == "SELL") return (type == OP_SELLLIMIT || type == OP_SELLSTOP);
   if(side == "ALL") return (type == OP_BUYLIMIT || type == OP_BUYSTOP || type == OP_SELLLIMIT || type == OP_SELLSTOP);
   return false;
}

bool OrderTypeMatches(const int type, string side)
{
   StringToUpper(side);
   if(side == "BUY") return (type == OP_BUY);
   if(side == "SELL") return (type == OP_SELL);
   if(side == "ALL") return (type == OP_BUY || type == OP_SELL);
   return false;
}

bool CloseSelectedOrder(const string reason)
{
   int type = OrderType();
   int ticket = OrderTicket();
   double lots = OrderLots();
   RefreshRates();
   double price = (type == OP_BUY) ? Bid : Ask;
   ResetLastError();
   bool ok = OrderClose(ticket, lots, price, InpSlippagePoints, clrSilver);
   if(!ok)
      Print("ProfitGovernorMT4: close failed ticket=", ticket, " symbol=", OrderSymbol(), " reason=", reason, " err=", GetLastError());
   return ok;
}

int CloseSide(string side)
{
   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         int type = OrderType();
         if(type == OP_BUY || type == OP_SELL)
         {
            if(!SymbolAllowed(OrderSymbol()) || !MagicAllowed(OrderMagicNumber()) || !OrderTypeMatches(type, side)) continue;
            if(CloseSelectedOrder(side))
            {
               affected++;
               changedThisPass++;
            }
         }
         else if(InpClosePendingOrders && PendingTypeMatches(type, side))
         {
            if(!SymbolAllowed(OrderSymbol()) || !MagicAllowed(OrderMagicNumber())) continue;
            ResetLastError();
            if(OrderDelete(OrderTicket()))
            {
               affected++;
               changedThisPass++;
            }
            else
               Print("ProfitGovernorMT4: pending delete failed ticket=", OrderTicket(), " err=", GetLastError());
         }
      }
      if(changedThisPass <= 0) break;
      Sleep(250);
      RefreshRates();
   }
   Print("ProfitGovernorMT4: ", side, " close completed affected=", affected);
   return affected;
}

bool OpenMarketPosition(string side)
{
   StringToUpper(side);
   if(side != "BUY" && side != "SELL") return false;
   ReadLotFromEdit();
   double lot = NormalizeLot(Symbol(), g_lot);
   if(lot <= 0.0) return false;

   RefreshRates();
   int type = (side == "BUY") ? OP_BUY : OP_SELL;
   double price = (type == OP_BUY) ? Ask : Bid;
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lot, price, InpSlippagePoints, 0.0, 0.0, InpOpenComment, InpOpenMagicNumber, 0, (type == OP_BUY ? clrGreen : clrRed));
   if(ticket <= 0)
   {
      Print("ProfitGovernorMT4: open ", side, " failed symbol=", Symbol(), " lot=", DoubleToString(lot, 2), " err=", GetLastError());
      return false;
   }
   Print("ProfitGovernorMT4: opened ", side, " ticket=", ticket, " lot=", DoubleToString(lot, 2));
   return true;
}

double CurrentChartScopeFloatingPnl(int &orderCount)
{
   double total = 0.0;
   orderCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!AutoCloseOrderAllowed()) continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
      orderCount++;
   }
   return total;
}

int CloseChartScopeOrders(const string reason)
{
   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!AutoCloseOrderAllowed()) continue;
         if(CloseSelectedOrder(reason))
         {
            affected++;
            changedThisPass++;
         }
      }
      if(changedThisPass <= 0) break;
      Sleep(250);
      RefreshRates();
   }
   Print("ProfitGovernorMT4: chart-scope profit close completed reason=", reason, " affected=", affected);
   return affected;
}

int CloseTfGroupOrders(const string tf, const string reason)
{
   int targetMagic = TfMagicByName(tf);
   if(targetMagic < 0) return 0;

   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!OrderAllowedForTfGovernor() || !MagicBelongsToTf(tf, OrderMagicNumber())) continue;
         if(CloseSelectedOrder(reason + "_" + tf))
         {
            affected++;
            changedThisPass++;
         }
      }
      if(changedThisPass <= 0) break;
      Sleep(250);
      RefreshRates();
   }
   Print("ProfitGovernorMT4: TF profit close completed tf=", tf, " reason=", reason, " affected=", affected);
   return affected;
}

void CheckAutoCloseProfitTarget()
{
   if(!InpAutoCloseProfitEnabled || InpAutoCloseProfitTargetUsd <= 0.0 || g_auto_close_in_progress) return;
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0) nowTs = TimeLocal();
   int cooldown = MathMax(1, InpAutoCloseCooldownSeconds);
   if(g_last_auto_close_at > 0 && (nowTs - g_last_auto_close_at) < cooldown) return;

   int count = 0;
   double pnl = CurrentChartScopeFloatingPnl(count);
   if(count <= 0 || pnl + 1e-8 < InpAutoCloseProfitTargetUsd) return;

   g_auto_close_in_progress = true;
   Print("ProfitGovernorMT4: auto profit target reached symbol=", Symbol(), " tf=", ChartTimeframeText(), " orders=", count, " pnl=", DoubleToString(pnl, 2), " target=", DoubleToString(InpAutoCloseProfitTargetUsd, 2));
   CloseChartScopeOrders("profit_target");
   g_last_auto_close_at = nowTs;
   g_auto_close_in_progress = false;
}

bool TfTargetHit(const double pnl, const int count, const double target)
{
   if(target <= 0.0 || count <= 0) return false;
   return (pnl + 1e-8 >= target);
}

void CheckTfGroupProfitTargets()
{
   if(!InpTfGroupProfitEnabled || g_auto_close_in_progress) return;
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0) nowTs = TimeLocal();
   int cooldown = MathMax(1, InpAutoCloseCooldownSeconds);
   if(g_last_auto_close_at > 0 && (nowTs - g_last_auto_close_at) < cooldown) return;

   RefreshTfGroupPnl();
   bool anyHit = false;
   if(TfTargetHit(g_tf_pnl_m1, g_tf_count_m1, g_tf_target_m1)) anyHit = true;
   if(TfTargetHit(g_tf_pnl_m5, g_tf_count_m5, g_tf_target_m5)) anyHit = true;
   if(TfTargetHit(g_tf_pnl_m15, g_tf_count_m15, g_tf_target_m15)) anyHit = true;
   if(TfTargetHit(g_tf_pnl_m30, g_tf_count_m30, g_tf_target_m30)) anyHit = true;
   if(TfTargetHit(g_tf_pnl_h1, g_tf_count_h1, g_tf_target_h1)) anyHit = true;
   if(!anyHit) return;

   g_auto_close_in_progress = true;
   if(TfTargetHit(g_tf_pnl_m1, g_tf_count_m1, g_tf_target_m1))
   {
      g_tf_status = "Hit M1 pnl=" + DoubleToString(g_tf_pnl_m1, 2) + " target=" + DoubleToString(g_tf_target_m1, 2);
      CloseTfGroupOrders("M1", "tf_profit_target");
   }
   if(TfTargetHit(g_tf_pnl_m5, g_tf_count_m5, g_tf_target_m5))
   {
      g_tf_status = "Hit M5 pnl=" + DoubleToString(g_tf_pnl_m5, 2) + " target=" + DoubleToString(g_tf_target_m5, 2);
      CloseTfGroupOrders("M5", "tf_profit_target");
   }
   if(TfTargetHit(g_tf_pnl_m15, g_tf_count_m15, g_tf_target_m15))
   {
      g_tf_status = "Hit M15 pnl=" + DoubleToString(g_tf_pnl_m15, 2) + " target=" + DoubleToString(g_tf_target_m15, 2);
      CloseTfGroupOrders("M15", "tf_profit_target");
   }
   if(TfTargetHit(g_tf_pnl_m30, g_tf_count_m30, g_tf_target_m30))
   {
      g_tf_status = "Hit M30 pnl=" + DoubleToString(g_tf_pnl_m30, 2) + " target=" + DoubleToString(g_tf_target_m30, 2);
      CloseTfGroupOrders("M30", "tf_profit_target");
   }
   if(TfTargetHit(g_tf_pnl_h1, g_tf_count_h1, g_tf_target_h1))
   {
      g_tf_status = "Hit H1 pnl=" + DoubleToString(g_tf_pnl_h1, 2) + " target=" + DoubleToString(g_tf_target_h1, 2);
      CloseTfGroupOrders("H1", "tf_profit_target");
   }
   g_last_auto_close_at = nowTs;
   g_auto_close_in_progress = false;
   RefreshTfGroupPnl();
}

void CreateButtonSized(const string name, const string text, const int x, const int y, const int w, const color bg)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, InpButtonHeight);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateButton(const string name, const string text, const int x, const int y, const color bg)
{
   CreateButtonSized(name, text, x, y, InpButtonWidth, bg);
}

void CreateEditBox(const string name, const string text, const int x, const int y, const int w, const int h)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateLotEdit(const int x, const int y, const int w)
{
   CreateEditBox(BTN_LOT_EDIT, LotText(g_lot), x, y, w, InpButtonHeight);
}

void CreateLabel(const string name, const string text, const int x, const int y, const int w, const int h, const color fg)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateTfGovernorDashboard(const int x, const int y)
{
   int rowH = 22;
   CreateLabel(LBL_TF_TITLE, "TF Profit Governor MT4 | Target | Live PnL", x, y, 340, rowH, clrGold);
   int y0 = y + rowH;

   CreateLabel(LBL_TF_M1, "M1", x, y0, 34, rowH, clrWhite);
   CreateEditBox(BTN_TF_EDIT_M1, DoubleToString(g_tf_target_m1, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M1 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrWhite);

   y0 += rowH;
   CreateLabel(LBL_TF_M5, "M5", x, y0, 34, rowH, clrWhite);
   CreateEditBox(BTN_TF_EDIT_M5, DoubleToString(g_tf_target_m5, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M5 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrWhite);

   y0 += rowH;
   CreateLabel(LBL_TF_M15, "M15", x, y0, 34, rowH, clrWhite);
   CreateEditBox(BTN_TF_EDIT_M15, DoubleToString(g_tf_target_m15, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M15 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrWhite);

   y0 += rowH;
   CreateLabel(LBL_TF_M30, "M30", x, y0, 34, rowH, clrWhite);
   CreateEditBox(BTN_TF_EDIT_M30, DoubleToString(g_tf_target_m30, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M30 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrWhite);

   y0 += rowH;
   CreateLabel(LBL_TF_H1, "H1", x, y0, 34, rowH, clrWhite);
   CreateEditBox(BTN_TF_EDIT_H1, DoubleToString(g_tf_target_h1, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_H1 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrWhite);

   y0 += rowH + 2;
   CreateButtonSized(BTN_TF_SAVE, "Save TF TP", x, y0, 112, clrDarkSlateGray);
   CreateLabel(LBL_TF_STATUS, g_tf_status, x + 124, y0 + 4, 280, rowH, clrSilver);

   y0 += InpButtonHeight + 6;
   int closeW = 70;
   CreateButtonSized(BTN_TF_CLOSE_M1, "Close M1", x, y0, closeW, clrMaroon);
   CreateButtonSized(BTN_TF_CLOSE_M5, "Close M5", x + closeW + 6, y0, closeW, clrMaroon);
   CreateButtonSized(BTN_TF_CLOSE_M15, "Close M15", x + (closeW + 6) * 2, y0, closeW, clrMaroon);
   CreateButtonSized(BTN_TF_CLOSE_M30, "Close M30", x + (closeW + 6) * 3, y0, closeW, clrMaroon);
   CreateButtonSized(BTN_TF_CLOSE_H1, "Close H1", x + (closeW + 6) * 4, y0, closeW, clrMaroon);
}

void UpdateTfGovernorDashboard()
{
   RefreshTfGroupPnl();
   SetObjectText(LBL_TF_M1 + "_PNL", "pnl=" + DoubleToString(g_tf_pnl_m1, 2) + " count=" + IntegerToString(g_tf_count_m1));
   SetObjectText(LBL_TF_M5 + "_PNL", "pnl=" + DoubleToString(g_tf_pnl_m5, 2) + " count=" + IntegerToString(g_tf_count_m5));
   SetObjectText(LBL_TF_M15 + "_PNL", "pnl=" + DoubleToString(g_tf_pnl_m15, 2) + " count=" + IntegerToString(g_tf_count_m15));
   SetObjectText(LBL_TF_M30 + "_PNL", "pnl=" + DoubleToString(g_tf_pnl_m30, 2) + " count=" + IntegerToString(g_tf_count_m30));
   SetObjectText(LBL_TF_H1 + "_PNL", "pnl=" + DoubleToString(g_tf_pnl_h1, 2) + " count=" + IntegerToString(g_tf_count_h1));
   SetObjectText(LBL_TF_STATUS, g_tf_status);
}

void ReadAndSaveTfTargets()
{
   g_tf_target_m1 = ParseEditDouble(BTN_TF_EDIT_M1, g_tf_target_m1);
   g_tf_target_m5 = ParseEditDouble(BTN_TF_EDIT_M5, g_tf_target_m5);
   g_tf_target_m15 = ParseEditDouble(BTN_TF_EDIT_M15, g_tf_target_m15);
   g_tf_target_m30 = ParseEditDouble(BTN_TF_EDIT_M30, g_tf_target_m30);
   g_tf_target_h1 = ParseEditDouble(BTN_TF_EDIT_H1, g_tf_target_h1);
   SaveTfTargets();
   SetObjectText(BTN_TF_EDIT_M1, DoubleToString(g_tf_target_m1, 2));
   SetObjectText(BTN_TF_EDIT_M5, DoubleToString(g_tf_target_m5, 2));
   SetObjectText(BTN_TF_EDIT_M15, DoubleToString(g_tf_target_m15, 2));
   SetObjectText(BTN_TF_EDIT_M30, DoubleToString(g_tf_target_m30, 2));
   SetObjectText(BTN_TF_EDIT_H1, DoubleToString(g_tf_target_h1, 2));
   g_tf_status = "Saved TF targets";
   UpdateTfGovernorDashboard();
}

void ManualCloseTfGroup(const string tf)
{
   int affected = CloseTfGroupOrders(tf, "manual_tf_close_button");
   g_tf_status = "Manual close " + tf + " affected=" + IntegerToString(affected);
   RefreshTfGroupPnl();
   UpdateTfGovernorDashboard();
}

void DeleteButtons()
{
   string names[30];
   names[0] = BTN_CLOSE_BUY; names[1] = BTN_CLOSE_SELL; names[2] = BTN_CLOSE_ALL;
   names[3] = BTN_LOT_DOWN; names[4] = BTN_LOT_EDIT; names[5] = BTN_LOT_UP;
   names[6] = BTN_OPEN_BUY; names[7] = BTN_OPEN_SELL; names[8] = BTN_TF_SAVE;
   names[9] = BTN_TF_EDIT_M1; names[10] = BTN_TF_EDIT_M5; names[11] = BTN_TF_EDIT_M15; names[12] = BTN_TF_EDIT_M30; names[13] = BTN_TF_EDIT_H1;
   names[14] = LBL_TF_TITLE; names[15] = LBL_TF_M1; names[16] = LBL_TF_M5; names[17] = LBL_TF_M15; names[18] = LBL_TF_M30; names[19] = LBL_TF_H1;
   names[20] = LBL_TF_M1 + "_PNL"; names[21] = LBL_TF_M5 + "_PNL"; names[22] = LBL_TF_M15 + "_PNL"; names[23] = LBL_TF_M30 + "_PNL"; names[24] = LBL_TF_H1 + "_PNL";
   names[25] = BTN_TF_CLOSE_M1; names[26] = BTN_TF_CLOSE_M5; names[27] = BTN_TF_CLOSE_M15; names[28] = BTN_TF_CLOSE_M30; names[29] = BTN_TF_CLOSE_H1;
   for(int i = 0; i < 30; i++) ObjectDelete(0, names[i]);
   ObjectDelete(0, LBL_TF_STATUS);
}

int OnInit()
{
   int x = InpButtonX;
   int y = InpButtonY;
   LoadTfTargets();
   SetLot(InpInitialLot);
   CreateButton(BTN_CLOSE_BUY, "Close Buy", x, y, clrSeaGreen);
   CreateButton(BTN_CLOSE_SELL, "Close Sell", x + InpButtonWidth + InpButtonGap, y, clrFireBrick);
   CreateButton(BTN_CLOSE_ALL, "Close All", x + (InpButtonWidth + InpButtonGap) * 2, y, clrDimGray);

   int y2 = y + InpButtonHeight + InpButtonGap;
   int smallW = 32;
   int editW = 82;
   int tradeW = 78;
   int cx = x;
   CreateButtonSized(BTN_LOT_DOWN, "-", cx, y2, smallW, clrGray);
   cx += smallW + InpButtonGap;
   CreateLotEdit(cx, y2, editW);
   cx += editW + InpButtonGap;
   CreateButtonSized(BTN_LOT_UP, "+", cx, y2, smallW, clrGray);
   cx += smallW + InpButtonGap;
   CreateButtonSized(BTN_OPEN_BUY, "Buy", cx, y2, tradeW, clrGreen);
   cx += tradeW + InpButtonGap;
   CreateButtonSized(BTN_OPEN_SELL, "Sell", cx, y2, tradeW, clrRed);
   CreateTfGovernorDashboard(x, y2 + InpButtonHeight + InpButtonGap + 8);
   UpdateTfGovernorDashboard();

   if(InpAutoCloseProfitEnabled || InpTfGroupProfitEnabled)
      EventSetTimer(MathMax(1, InpAutoCloseCheckSeconds));

   ChartRedraw();
   Print("ProfitGovernorMT4 initialized. OnlyCurrentSymbol=", InpOnlyCurrentSymbol,
         " MagicFilter=", InpMagicNumberFilter,
         " TfGovernor=", (InpTfGroupProfitEnabled ? "true" : "false"),
         " ChartScope=", Symbol(), " ", ChartTimeframeText(),
         " AutoMagic=", AutoCloseMagicFilter());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteButtons();
   ChartRedraw();
}

void OnTick()
{
   CheckTfGroupProfitTargets();
   CheckAutoCloseProfitTarget();
   UpdateTfGovernorDashboard();
}

void OnTimer()
{
   CheckTfGroupProfitTargets();
   CheckAutoCloseProfitTarget();
   UpdateTfGovernorDashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == BTN_LOT_EDIT)
   {
      ReadLotFromEdit();
      ChartRedraw();
      return;
   }
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == BTN_TF_EDIT_M1 || sparam == BTN_TF_EDIT_M5 || sparam == BTN_TF_EDIT_M15 || sparam == BTN_TF_EDIT_M30 || sparam == BTN_TF_EDIT_H1)
      {
         g_tf_status = "Edited target - press Save TF TP";
         UpdateTfGovernorDashboard();
         ChartRedraw();
         return;
      }
   }

   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == BTN_CLOSE_BUY)
   {
      ObjectSetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE, false);
      CloseSide("BUY");
   }
   else if(sparam == BTN_CLOSE_SELL)
   {
      ObjectSetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE, false);
      CloseSide("SELL");
   }
   else if(sparam == BTN_CLOSE_ALL)
   {
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE, false);
      CloseSide("ALL");
   }
   else if(sparam == BTN_LOT_DOWN)
   {
      ObjectSetInteger(0, BTN_LOT_DOWN, OBJPROP_STATE, false);
      NudgeLot(-1);
   }
   else if(sparam == BTN_LOT_UP)
   {
      ObjectSetInteger(0, BTN_LOT_UP, OBJPROP_STATE, false);
      NudgeLot(1);
   }
   else if(sparam == BTN_OPEN_BUY)
   {
      ObjectSetInteger(0, BTN_OPEN_BUY, OBJPROP_STATE, false);
      OpenMarketPosition("BUY");
   }
   else if(sparam == BTN_OPEN_SELL)
   {
      ObjectSetInteger(0, BTN_OPEN_SELL, OBJPROP_STATE, false);
      OpenMarketPosition("SELL");
   }
   else if(sparam == BTN_TF_SAVE)
   {
      ObjectSetInteger(0, BTN_TF_SAVE, OBJPROP_STATE, false);
      ReadAndSaveTfTargets();
   }
   else if(sparam == BTN_TF_CLOSE_M1)
   {
      ObjectSetInteger(0, BTN_TF_CLOSE_M1, OBJPROP_STATE, false);
      ManualCloseTfGroup("M1");
   }
   else if(sparam == BTN_TF_CLOSE_M5)
   {
      ObjectSetInteger(0, BTN_TF_CLOSE_M5, OBJPROP_STATE, false);
      ManualCloseTfGroup("M5");
   }
   else if(sparam == BTN_TF_CLOSE_M15)
   {
      ObjectSetInteger(0, BTN_TF_CLOSE_M15, OBJPROP_STATE, false);
      ManualCloseTfGroup("M15");
   }
   else if(sparam == BTN_TF_CLOSE_M30)
   {
      ObjectSetInteger(0, BTN_TF_CLOSE_M30, OBJPROP_STATE, false);
      ManualCloseTfGroup("M30");
   }
   else if(sparam == BTN_TF_CLOSE_H1)
   {
      ObjectSetInteger(0, BTN_TF_CLOSE_H1, OBJPROP_STATE, false);
      ManualCloseTfGroup("H1");
   }

   UpdateTfGovernorDashboard();
   ChartRedraw();
}
