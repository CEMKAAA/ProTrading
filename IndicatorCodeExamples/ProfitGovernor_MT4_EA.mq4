//+------------------------------------------------------------------+
//| ProfitGovernor MT4 EA                                            |
//| Manual close buttons + TF magic-group profit governor for MT4.    |
//+------------------------------------------------------------------+
#property strict

enum TfProfitAction
{
   TF_PROFIT_CLOSE_ALL = 0,
   TF_PROFIT_CLOSE_HALF = 1
};

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
input TfProfitAction InpTfProfitAction = TF_PROFIT_CLOSE_HALF; // Secure half and leave runners by default.
input double InpTfPartialClosePct = 50.0;
input bool InpTfPartialMoveSlToBreakEven = true;
input bool InpTfPartialCloseRunnerIfBeFails = true;
input bool InpAuditCsvEnabled = true;
input bool InpAuditUseCommonFiles = true;
input string InpAuditCsvFileName = "ProfitGovernor_Audit_MT4.csv";
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
string PANEL_BG = "PT4_PROFIT_GOV_PANEL_BG";
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
double g_tf_sig_m1 = 0.0;
double g_tf_sig_m5 = 0.0;
double g_tf_sig_m15 = 0.0;
double g_tf_sig_m30 = 0.0;
double g_tf_sig_h1 = 0.0;
string g_tf_status = "TF governor initialized";
bool g_tf_armed_m1 = true;
bool g_tf_armed_m5 = true;
bool g_tf_armed_m15 = true;
bool g_tf_armed_m30 = true;
bool g_tf_armed_h1 = true;
bool g_last_partial_unsecured_runner = false;

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

string TfArmedKey(const string tf)
{
   return SettingsKey("ARMED_" + tf);
}

bool LoadTfArmedValue(const string tf, const bool fallback)
{
   string key = TfArmedKey(tf);
   if(!GlobalVariableCheck(key)) return fallback;
   return (GlobalVariableGet(key) > 0.5);
}

void LoadTfArmedState()
{
   g_tf_armed_m1 = LoadTfArmedValue("M1", true);
   g_tf_armed_m5 = LoadTfArmedValue("M5", true);
   g_tf_armed_m15 = LoadTfArmedValue("M15", true);
   g_tf_armed_m30 = LoadTfArmedValue("M30", true);
   g_tf_armed_h1 = LoadTfArmedValue("H1", true);
}

void SaveTfArmedState(const string tf, const bool armed)
{
   GlobalVariableSet(TfArmedKey(tf), armed ? 1.0 : 0.0);
}

string AuditFileName()
{
   string name = InpAuditCsvFileName;
   if(StringLen(name) <= 0) name = "ProfitGovernor_Audit_MT4.csv";
   return name;
}

void AuditWrite(const string event_name,
                const string tf,
                const int ticket,
                const string symbol,
                const int magic,
                const double volume,
                const double pnl,
                const double target,
                const string result,
                const string reason,
                const string detail)
{
   if(!InpAuditCsvEnabled) return;

   ResetLastError();
   int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpAuditUseCommonFiles)
      flags = flags | FILE_COMMON;
   int h = FileOpen(AuditFileName(), flags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ProfitGovernorMT4: audit csv open failed file=", AuditFileName(), " err=", GetLastError());
      return;
   }

   bool writeHeader = (FileSize(h) == 0);
   FileSeek(h, 0, SEEK_END);
   if(writeHeader)
   {
      FileWrite(h,
                "ts",
                "account",
                "terminal",
                "event",
                "tf",
                "ticket",
                "symbol",
                "magic",
                "volume",
                "pnl",
                "target",
                "result",
                "reason",
                "detail");
   }

   FileWrite(h,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             IntegerToString(AccountNumber()),
             "MT4",
             event_name,
             tf,
             IntegerToString(ticket),
             symbol,
             IntegerToString(magic),
             DoubleToString(volume, 2),
             DoubleToString(pnl, 2),
             DoubleToString(target, 2),
             result,
             reason,
             detail);
   FileClose(h);
}

string TfDisarmSigKey(const string tf)
{
   return SettingsKey("DISARM_SIG_" + tf);
}

double TfCurrentSignature(const string tf)
{
   if(tf == "M1") return g_tf_sig_m1;
   if(tf == "M5") return g_tf_sig_m5;
   if(tf == "M15") return g_tf_sig_m15;
   if(tf == "M30") return g_tf_sig_m30;
   if(tf == "H1") return g_tf_sig_h1;
   return 0.0;
}

double LoadTfDisarmSignature(const string tf)
{
   string key = TfDisarmSigKey(tf);
   if(!GlobalVariableCheck(key)) return 0.0;
   return GlobalVariableGet(key);
}

void SaveTfDisarmSignature(const string tf, const bool armed)
{
   GlobalVariableSet(TfDisarmSigKey(tf), armed ? 0.0 : TfCurrentSignature(tf));
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
   g_tf_sig_m1 = 0.0;
   g_tf_sig_m5 = 0.0;
   g_tf_sig_m15 = 0.0;
   g_tf_sig_m30 = 0.0;
   g_tf_sig_h1 = 0.0;
}

double TicketSignatureValue(const int ticket)
{
   return (double)ticket;
}

void AddTfPnl(const int magic, const double pnl, const int ticket)
{
   double sig = TicketSignatureValue(ticket);
   if(MagicBelongsToTf("M1", magic)) { g_tf_pnl_m1 += pnl; g_tf_count_m1++; g_tf_sig_m1 += sig; return; }
   if(MagicBelongsToTf("M5", magic)) { g_tf_pnl_m5 += pnl; g_tf_count_m5++; g_tf_sig_m5 += sig; return; }
   if(MagicBelongsToTf("M15", magic)) { g_tf_pnl_m15 += pnl; g_tf_count_m15++; g_tf_sig_m15 += sig; return; }
   if(MagicBelongsToTf("M30", magic)) { g_tf_pnl_m30 += pnl; g_tf_count_m30++; g_tf_sig_m30 += sig; return; }
   if(MagicBelongsToTf("H1", magic)) { g_tf_pnl_h1 += pnl; g_tf_count_h1++; g_tf_sig_h1 += sig; return; }
}

void RefreshTfGroupPnl()
{
   ResetTfPnl();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!OrderAllowedForTfGovernor()) continue;
      AddTfPnl(OrderMagicNumber(), OrderProfit() + OrderSwap() + OrderCommission(), OrderTicket());
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
   string symbol = OrderSymbol();
   double lots = OrderLots();
   RefreshRates();
   double price = (type == OP_BUY) ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);
   ResetLastError();
   bool ok = OrderClose(ticket, lots, price, InpSlippagePoints, clrSilver);
   if(!ok)
      Print("ProfitGovernorMT4: close failed ticket=", ticket, " symbol=", symbol, " reason=", reason, " err=", GetLastError());
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

double TfPartialClosePct()
{
   if(InpTfPartialClosePct <= 0.0) return 50.0;
   return MathMin(100.0, InpTfPartialClosePct);
}

bool OrderSlAtOrBetterBreakEven(const int type, const double sl, const double be)
{
   if(sl <= 0.0) return false;
   if(type == OP_BUY) return (sl + 1e-8 >= be);
   if(type == OP_SELL) return (sl - 1e-8 <= be);
   return false;
}

bool BreakEvenStopAllowedNow(const string symbol, const int type, const double be)
{
   double point = MarketInfo(symbol, MODE_POINT);
   if(point <= 0.0) point = 0.00001;
   double minDistance = MarketInfo(symbol, MODE_STOPLEVEL) * point;
   double bid = MarketInfo(symbol, MODE_BID);
   double ask = MarketInfo(symbol, MODE_ASK);

   if(type == OP_BUY) return (bid <= 0.0 || be <= bid - minDistance + 1e-8);
   if(type == OP_SELL) return (ask <= 0.0 || be >= ask + minDistance - 1e-8);
   return false;
}

bool MoveSelectedOrderStopToBreakEven(const string reason)
{
   int type = OrderType();
   if(type != OP_BUY && type != OP_SELL) return false;

   string symbol = OrderSymbol();
   int ticket = OrderTicket();
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   double be = NormalizeDouble(OrderOpenPrice(), digits);
   double sl = OrderStopLoss();
   double tp = OrderTakeProfit();

   if(OrderSlAtOrBetterBreakEven(type, sl, be)) return true;

   if(!BreakEvenStopAllowedNow(symbol, type, be))
   {
      Print("ProfitGovernorMT4: SL->BE skipped stop-level ticket=", ticket,
            " symbol=", symbol,
            " be=", DoubleToString(be, digits),
            " reason=", reason);
      AuditWrite("sl_be_skipped_stop_level", "", ticket, symbol, OrderMagicNumber(), OrderLots(), OrderProfit() + OrderSwap() + OrderCommission(), 0.0, "skipped", reason, "be=" + DoubleToString(be, digits));
      return false;
   }

   ResetLastError();
   bool ok = OrderModify(ticket, OrderOpenPrice(), be, tp, 0, clrDodgerBlue);
   if(ok)
   {
      AuditWrite("sl_be_success", "", ticket, symbol, OrderMagicNumber(), OrderLots(), OrderProfit() + OrderSwap() + OrderCommission(), 0.0, "ok", reason, "be=" + DoubleToString(be, digits));
      return true;
   }

   Print("ProfitGovernorMT4: SL->BE failed ticket=", ticket,
         " symbol=", symbol,
         " be=", DoubleToString(be, digits),
         " reason=", reason,
         " err=", GetLastError());
   AuditWrite("sl_be_failed", "", ticket, symbol, OrderMagicNumber(), OrderLots(), OrderProfit() + OrderSwap() + OrderCommission(), 0.0, "failed", reason, "be=" + DoubleToString(be, digits) + " err=" + IntegerToString(GetLastError()));
   return false;
}

bool MoveRemainingOrderStopToBreakEven(const int originalTicket,
                                       const string symbol,
                                       const int type,
                                       const int magic,
                                       const double expectedRemaining,
                                       const string reason)
{
   RefreshRates();
   if(OrderSelect(originalTicket, SELECT_BY_TICKET, MODE_TRADES))
      return MoveSelectedOrderStopToBreakEven(reason);

   double tolerance = MathMax(SymbolLotStep(symbol), 0.00001) + 1e-8;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != symbol || OrderType() != type || OrderMagicNumber() != magic) continue;
      if(MathAbs(OrderLots() - expectedRemaining) > tolerance) continue;
      return MoveSelectedOrderStopToBreakEven(reason);
   }
   Print("ProfitGovernorMT4: SL->BE skipped remaining order not found ticket=", originalTicket,
         " symbol=", symbol,
         " reason=", reason);
   return false;
}

bool CloseRemainingOrderAfterBreakEvenFailure(const int originalTicket,
                                              const string symbol,
                                              const int type,
                                              const int magic,
                                              const double expectedRemaining,
                                              const string reason)
{
   int maxPasses = MathMax(1, InpMaxClosePasses);
   for(int pass = 0; pass < maxPasses; pass++)
   {
      RefreshRates();
      if(OrderSelect(originalTicket, SELECT_BY_TICKET, MODE_TRADES))
      {
         double pnl = OrderProfit() + OrderSwap() + OrderCommission();
         double lots = OrderLots();
         bool closed = CloseSelectedOrder(reason);
         if(closed)
         {
            Print("ProfitGovernorMT4: runner closed because SL->BE failed ticket=", originalTicket,
                  " symbol=", symbol,
                  " reason=", reason,
                  " pass=", pass + 1);
            AuditWrite("runner_close_after_be_failed", "", originalTicket, symbol, magic, lots, pnl, 0.0, "ok", reason, "pass=" + IntegerToString(pass + 1));
            return true;
         }
         AuditWrite("runner_close_after_be_failed", "", originalTicket, symbol, magic, lots, pnl, 0.0, "failed", reason, "pass=" + IntegerToString(pass + 1) + " err=" + IntegerToString(GetLastError()));
      }
      else
      {
         double tolerance = MathMax(SymbolLotStep(symbol), 0.00001) + 1e-8;
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
            if(OrderSymbol() != symbol || OrderType() != type || OrderMagicNumber() != magic) continue;
            if(MathAbs(OrderLots() - expectedRemaining) > tolerance) continue;

            int ticket = OrderTicket();
            double pnl = OrderProfit() + OrderSwap() + OrderCommission();
            double lots = OrderLots();
            bool closed = CloseSelectedOrder(reason);
            if(closed)
            {
               Print("ProfitGovernorMT4: runner closed because SL->BE failed ticket=", ticket,
                     " symbol=", symbol,
                     " reason=", reason,
                     " pass=", pass + 1);
               AuditWrite("runner_close_after_be_failed", "", ticket, symbol, magic, lots, pnl, 0.0, "ok", reason, "pass=" + IntegerToString(pass + 1));
               return true;
            }
            AuditWrite("runner_close_after_be_failed", "", ticket, symbol, magic, lots, pnl, 0.0, "failed", reason, "pass=" + IntegerToString(pass + 1) + " err=" + IntegerToString(GetLastError()));
            break;
         }
      }
      Sleep(250);
   }

   Print("ProfitGovernorMT4: runner close after SL->BE failure failed/skipped ticket=", originalTicket,
         " symbol=", symbol,
         " reason=", reason);
   AuditWrite("runner_close_after_be_failed", "", originalTicket, symbol, magic, expectedRemaining, 0.0, 0.0, "failed_or_not_found", reason, "expectedRemaining=" + DoubleToString(expectedRemaining, 2));
   return false;
}

int PartialCloseTfGroupOrders(const string tf, const string reason, const double pct)
{
   int targetMagic = TfMagicByName(tf);
   if(targetMagic < 0) return 0;

   int affected = 0;
   int maxPasses = 1; // Partial profit securing must happen once per armed TF cycle.
   g_last_partial_unsecured_runner = false;
   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!OrderAllowedForTfGovernor() || !MagicBelongsToTf(tf, OrderMagicNumber())) continue;

         string symbol = OrderSymbol();
         int type = OrderType();
         int ticket = OrderTicket();
         int magic = OrderMagicNumber();
         double volume = OrderLots();
         double orderPnl = OrderProfit() + OrderSwap() + OrderCommission();
         double minLot = SymbolMinLot(symbol);
         double closeLots = NormalizeLot(symbol, volume * pct / 100.0);
         double remaining = NormalizeDouble(volume - closeLots, 8);

         if(closeLots + 1e-8 < minLot || remaining + 1e-8 < minLot)
         {
            Print("ProfitGovernorMT4: TF partial skipped unsplittable tf=", tf,
                  " ticket=", ticket,
                  " symbol=", symbol,
                  " volume=", DoubleToString(volume, 2),
                  " closeLots=", DoubleToString(closeLots, 2),
                  " minLot=", DoubleToString(minLot, 2),
                  " action=full_close");
            AuditWrite("partial_unsplittable_full_close", tf, ticket, symbol, magic, volume, orderPnl, 0.0, "attempt", reason, "closeLots=" + DoubleToString(closeLots, 2) + " remaining=" + DoubleToString(remaining, 2) + " minLot=" + DoubleToString(minLot, 2));
            bool closedUnsplittable = CloseRemainingOrderAfterBreakEvenFailure(ticket, symbol, type, magic, volume, "tf_partial_unsplittable_full_close");
            if(closedUnsplittable)
            {
               affected++;
               changedThisPass++;
            }
            else
               g_last_partial_unsecured_runner = true;
            continue;
         }

         RefreshRates();
         double price = (type == OP_BUY) ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);
         ResetLastError();
         bool ok = OrderClose(ticket, closeLots, price, InpSlippagePoints, clrDodgerBlue);
         if(ok)
         {
            AuditWrite("partial_close_success", tf, ticket, symbol, magic, closeLots, orderPnl, 0.0, "ok", reason, "beforeVolume=" + DoubleToString(volume, 2) + " remaining=" + DoubleToString(remaining, 2));
            if(InpTfPartialMoveSlToBreakEven)
            {
               Sleep(100);
               bool beOk = MoveRemainingOrderStopToBreakEven(ticket, symbol, type, magic, remaining, "tf_partial_profit_target");
               if(!beOk && InpTfPartialCloseRunnerIfBeFails)
               {
                  bool closedUnsafeRunner = CloseRemainingOrderAfterBreakEvenFailure(ticket, symbol, type, magic, remaining, "tf_partial_be_failed");
                  if(!closedUnsafeRunner)
                     g_last_partial_unsecured_runner = true;
               }
            }
            affected++;
            changedThisPass++;
         }
         else
         {
            Print("ProfitGovernorMT4: TF partial close failed tf=", tf,
                  " ticket=", ticket,
                  " symbol=", symbol,
                  " closeLots=", DoubleToString(closeLots, 2),
                  " reason=", reason,
                  " err=", GetLastError());
            AuditWrite("partial_close_failed", tf, ticket, symbol, magic, closeLots, orderPnl, 0.0, "failed", reason, "beforeVolume=" + DoubleToString(volume, 2) + " remaining=" + DoubleToString(remaining, 2) + " err=" + IntegerToString(GetLastError()));
         }
      }
      if(changedThisPass <= 0) break;
      Sleep(250);
      RefreshRates();
   }
   Print("ProfitGovernorMT4: TF partial close completed tf=", tf,
         " reason=", reason,
         " pct=", DoubleToString(pct, 1),
         " affected=", affected);
   string unsecured = g_last_partial_unsecured_runner ? "1" : "0";
   AuditWrite("tf_partial_complete", tf, 0, "", 0, 0.0, 0.0, 0.0, "complete", reason, "pct=" + DoubleToString(pct, 1) + " affected=" + IntegerToString(affected) + " unsecured=" + unsecured);
   return affected;
}

bool TfGroupArmed(const string tf)
{
   if(tf == "M1") return g_tf_armed_m1;
   if(tf == "M5") return g_tf_armed_m5;
   if(tf == "M15") return g_tf_armed_m15;
   if(tf == "M30") return g_tf_armed_m30;
   if(tf == "H1") return g_tf_armed_h1;
   return false;
}

void SetTfGroupArmed(const string tf, const bool armed)
{
   if(tf == "M1") { g_tf_armed_m1 = armed; SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "M5") { g_tf_armed_m5 = armed; SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "M15") { g_tf_armed_m15 = armed; SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "M30") { g_tf_armed_m30 = armed; SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "H1") { g_tf_armed_h1 = armed; SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
}

void RearmFlatTfGroups()
{
   if(!g_tf_armed_m1 && (g_tf_count_m1 <= 0 || MathAbs(LoadTfDisarmSignature("M1") - g_tf_sig_m1) > 0.5)) { SetTfGroupArmed("M1", true); AuditWrite("tf_rearmed", "M1", 0, "", 0, 0.0, g_tf_pnl_m1, g_tf_target_m1, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m1)); }
   if(!g_tf_armed_m5 && (g_tf_count_m5 <= 0 || MathAbs(LoadTfDisarmSignature("M5") - g_tf_sig_m5) > 0.5)) { SetTfGroupArmed("M5", true); AuditWrite("tf_rearmed", "M5", 0, "", 0, 0.0, g_tf_pnl_m5, g_tf_target_m5, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m5)); }
   if(!g_tf_armed_m15 && (g_tf_count_m15 <= 0 || MathAbs(LoadTfDisarmSignature("M15") - g_tf_sig_m15) > 0.5)) { SetTfGroupArmed("M15", true); AuditWrite("tf_rearmed", "M15", 0, "", 0, 0.0, g_tf_pnl_m15, g_tf_target_m15, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m15)); }
   if(!g_tf_armed_m30 && (g_tf_count_m30 <= 0 || MathAbs(LoadTfDisarmSignature("M30") - g_tf_sig_m30) > 0.5)) { SetTfGroupArmed("M30", true); AuditWrite("tf_rearmed", "M30", 0, "", 0, 0.0, g_tf_pnl_m30, g_tf_target_m30, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m30)); }
   if(!g_tf_armed_h1 && (g_tf_count_h1 <= 0 || MathAbs(LoadTfDisarmSignature("H1") - g_tf_sig_h1) > 0.5)) { SetTfGroupArmed("H1", true); AuditWrite("tf_rearmed", "H1", 0, "", 0, 0.0, g_tf_pnl_h1, g_tf_target_h1, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_h1)); }
}

int ApplyTfProfitAction(const string tf, const string reason)
{
   int affected = 0;
   g_last_partial_unsecured_runner = false;
   if(InpTfProfitAction == TF_PROFIT_CLOSE_ALL)
      affected = CloseTfGroupOrders(tf, reason);
   else
      affected = PartialCloseTfGroupOrders(tf, reason, TfPartialClosePct());

   if(affected > 0 && !g_last_partial_unsecured_runner)
   {
      RefreshTfGroupPnl();
      SetTfGroupArmed(tf, false);
      AuditWrite("tf_disarmed_after_action", tf, 0, "", 0, 0.0, 0.0, 0.0, "disarmed", reason, "affected=" + IntegerToString(affected) + " sig=" + DoubleToString(TfCurrentSignature(tf), 0));
   }
   else if(affected > 0)
   {
      RefreshTfGroupPnl();
      g_tf_status = tf + " unsafe runner close failed; governor remains armed";
      AuditWrite("tf_remains_armed_after_unsafe_runner", tf, 0, "", 0, 0.0, 0.0, 0.0, "armed", reason, "affected=" + IntegerToString(affected));
   }
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

bool TfTargetReady(const string tf, const double pnl, const int count, const double target)
{
   return (TfTargetHit(pnl, count, target) && TfGroupArmed(tf));
}

void CheckTfGroupProfitTargets()
{
   if(!InpTfGroupProfitEnabled || g_auto_close_in_progress) return;
   datetime nowTs = TimeCurrent();
   if(nowTs <= 0) nowTs = TimeLocal();
   int cooldown = MathMax(1, InpAutoCloseCooldownSeconds);
   if(g_last_auto_close_at > 0 && (nowTs - g_last_auto_close_at) < cooldown) return;

   RefreshTfGroupPnl();
   RearmFlatTfGroups();
   bool anyHit = false;
   if(TfTargetReady("M1", g_tf_pnl_m1, g_tf_count_m1, g_tf_target_m1)) anyHit = true;
   if(TfTargetReady("M5", g_tf_pnl_m5, g_tf_count_m5, g_tf_target_m5)) anyHit = true;
   if(TfTargetReady("M15", g_tf_pnl_m15, g_tf_count_m15, g_tf_target_m15)) anyHit = true;
   if(TfTargetReady("M30", g_tf_pnl_m30, g_tf_count_m30, g_tf_target_m30)) anyHit = true;
   if(TfTargetReady("H1", g_tf_pnl_h1, g_tf_count_h1, g_tf_target_h1)) anyHit = true;
   if(!anyHit) return;

   g_auto_close_in_progress = true;
   int affected = 0;
   if(TfTargetReady("M1", g_tf_pnl_m1, g_tf_count_m1, g_tf_target_m1))
   {
      g_tf_status = "Hit M1 pnl=" + DoubleToString(g_tf_pnl_m1, 2) + " target=" + DoubleToString(g_tf_target_m1, 2);
      AuditWrite("tf_target_hit", "M1", 0, "", 0, 0.0, g_tf_pnl_m1, g_tf_target_m1, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m1) + " sig=" + DoubleToString(g_tf_sig_m1, 0));
      affected = ApplyTfProfitAction("M1", "tf_profit_target");
      g_tf_status = "M1 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("M5", g_tf_pnl_m5, g_tf_count_m5, g_tf_target_m5))
   {
      g_tf_status = "Hit M5 pnl=" + DoubleToString(g_tf_pnl_m5, 2) + " target=" + DoubleToString(g_tf_target_m5, 2);
      AuditWrite("tf_target_hit", "M5", 0, "", 0, 0.0, g_tf_pnl_m5, g_tf_target_m5, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m5) + " sig=" + DoubleToString(g_tf_sig_m5, 0));
      affected = ApplyTfProfitAction("M5", "tf_profit_target");
      g_tf_status = "M5 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("M15", g_tf_pnl_m15, g_tf_count_m15, g_tf_target_m15))
   {
      g_tf_status = "Hit M15 pnl=" + DoubleToString(g_tf_pnl_m15, 2) + " target=" + DoubleToString(g_tf_target_m15, 2);
      AuditWrite("tf_target_hit", "M15", 0, "", 0, 0.0, g_tf_pnl_m15, g_tf_target_m15, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m15) + " sig=" + DoubleToString(g_tf_sig_m15, 0));
      affected = ApplyTfProfitAction("M15", "tf_profit_target");
      g_tf_status = "M15 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("M30", g_tf_pnl_m30, g_tf_count_m30, g_tf_target_m30))
   {
      g_tf_status = "Hit M30 pnl=" + DoubleToString(g_tf_pnl_m30, 2) + " target=" + DoubleToString(g_tf_target_m30, 2);
      AuditWrite("tf_target_hit", "M30", 0, "", 0, 0.0, g_tf_pnl_m30, g_tf_target_m30, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m30) + " sig=" + DoubleToString(g_tf_sig_m30, 0));
      affected = ApplyTfProfitAction("M30", "tf_profit_target");
      g_tf_status = "M30 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("H1", g_tf_pnl_h1, g_tf_count_h1, g_tf_target_h1))
   {
      g_tf_status = "Hit H1 pnl=" + DoubleToString(g_tf_pnl_h1, 2) + " target=" + DoubleToString(g_tf_target_h1, 2);
      AuditWrite("tf_target_hit", "H1", 0, "", 0, 0.0, g_tf_pnl_h1, g_tf_target_h1, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_h1) + " sig=" + DoubleToString(g_tf_sig_h1, 0));
      affected = ApplyTfProfitAction("H1", "tf_profit_target");
      g_tf_status = "H1 target action affected=" + IntegerToString(affected);
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

void CreatePanelBackground(const int x, const int y, const int w, const int h)
{
   if(ObjectFind(0, PANEL_BG) >= 0) ObjectDelete(0, PANEL_BG);
   ObjectCreate(0, PANEL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_HIDDEN, true);
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
   CreateLabel(LBL_TF_TITLE, "TF Profit Governor MT4 | Target | Live PnL", x, y, 340, rowH, clrNavy);
   int y0 = y + rowH;

   CreateLabel(LBL_TF_M1, "M1", x, y0, 34, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M1, DoubleToString(g_tf_target_m1, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M1 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_M5, "M5", x, y0, 34, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M5, DoubleToString(g_tf_target_m5, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M5 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_M15, "M15", x, y0, 34, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M15, DoubleToString(g_tf_target_m15, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M15 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_M30, "M30", x, y0, 34, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M30, DoubleToString(g_tf_target_m30, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_M30 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_H1, "H1", x, y0, 34, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_H1, DoubleToString(g_tf_target_h1, 2), x + 36, y0 - 4, 58, 22);
   CreateLabel(LBL_TF_H1 + "_PNL", "pnl=0.00 count=0", x + 104, y0, 160, rowH, clrBlack);

   y0 += rowH + 2;
   CreateButtonSized(BTN_TF_SAVE, "Save TF TP", x, y0, 112, clrDarkSlateGray);
   CreateLabel(LBL_TF_STATUS, g_tf_status, x + 124, y0 + 4, 280, rowH, clrDimGray);

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
   ObjectDelete(0, PANEL_BG);
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
   LoadTfArmedState();
   SetLot(InpInitialLot);
   CreatePanelBackground(x - 8, y - 8, 430, 292);
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
