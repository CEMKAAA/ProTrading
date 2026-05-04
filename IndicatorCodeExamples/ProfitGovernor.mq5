//+------------------------------------------------------------------+
//| Manual Close Buttons MT5 EA                                      |
//| Adds Close Buy / Close Sell / Close All buttons to the chart.    |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

enum TfProfitAction
{
   TF_PROFIT_CLOSE_ALL = 0,
   TF_PROFIT_CLOSE_HALF = 1
};

input bool InpOnlyCurrentSymbol = false;       // false = whole MT5 terminal/account
input long InpMagicNumberFilter = -1;          // -1 = all magic numbers
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
input long InpOpenMagicNumber = 0;
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
input string InpAuditCsvFileName = "ProfitGovernor_Audit_MT5.csv";
input double InpTfTargetM1 = 20.0;
input double InpTfTargetM5 = 40.0;
input double InpTfTargetM15 = 100.0;
input double InpTfTargetM30 = 0.0;                    // 0 disables that TF target
input double InpTfTargetH1 = 0.0;
input bool InpAutoCloseUseHjfxTfMagic = true;         // true = chart TF maps to HJFX magic below
input long InpAutoCloseMagicOverride = -1;            // >=0 overrides HJFX TF magic for auto-close only
input bool InpAutoCloseRequireMagic = true;           // true = never auto-close positions outside selected magic
input long InpHjfxMagicM1 = 658701;
input long InpHjfxMagicM5 = 658705;
input long InpHjfxMagicM15 = 658715;
input long InpHjfxMagicM30 = 658730;
input long InpHjfxMagicH1 = 658760;
input bool InpIncludeIndicatorV2Magic = true;         // ProTrading Indicator Automation V2 backend magics.
input long InpIndicatorV2MagicM1 = 970101;
input long InpIndicatorV2MagicM5 = 970105;
input long InpIndicatorV2MagicM15 = 970115;
input long InpIndicatorV2MagicM30 = 970130;
input long InpIndicatorV2MagicH1 = 970160;
input bool InpIncludeTmaProMagic = false;             // Optional: standalone TMA_MACD_PRO TF-offset magics.
input string InpTmaMagicBasesCsv = "860500,860600,860700,860800";
input long InpTmaMagicOffsetM1 = 10000;
input long InpTmaMagicOffsetM5 = 20000;
input long InpTmaMagicOffsetM15 = 30000;
input long InpTmaMagicOffsetM30 = 40000;
input long InpTmaMagicOffsetH1 = 50000;
input string InpExtraMagicM1Csv = "";                  // Optional legacy/current open magics to force into M1 group.
input string InpExtraMagicM5Csv = "";
input string InpExtraMagicM15Csv = "";
input string InpExtraMagicM30Csv = "";
input string InpExtraMagicH1Csv = "";
input int InpAutoCloseCheckSeconds = 1;
input int InpAutoCloseCooldownSeconds = 10;

CTrade trade;

string BTN_CLOSE_BUY = "PT_MANUAL_CLOSE_BUY";
string BTN_CLOSE_SELL = "PT_MANUAL_CLOSE_SELL";
string BTN_CLOSE_ALL = "PT_MANUAL_CLOSE_ALL";
string BTN_LOT_DOWN = "PT_MANUAL_LOT_DOWN";
string BTN_LOT_EDIT = "PT_MANUAL_LOT_EDIT";
string BTN_LOT_UP = "PT_MANUAL_LOT_UP";
string BTN_OPEN_BUY = "PT_MANUAL_OPEN_BUY";
string BTN_OPEN_SELL = "PT_MANUAL_OPEN_SELL";
string BTN_TF_SAVE = "PT_TF_SAVE";
string BTN_TF_CLOSE_M1 = "PT_TF_CLOSE_M1";
string BTN_TF_CLOSE_M5 = "PT_TF_CLOSE_M5";
string BTN_TF_CLOSE_M15 = "PT_TF_CLOSE_M15";
string BTN_TF_CLOSE_M30 = "PT_TF_CLOSE_M30";
string BTN_TF_CLOSE_H1 = "PT_TF_CLOSE_H1";
string BTN_TF_EDIT_M1 = "PT_TF_EDIT_M1";
string BTN_TF_EDIT_M5 = "PT_TF_EDIT_M5";
string BTN_TF_EDIT_M15 = "PT_TF_EDIT_M15";
string BTN_TF_EDIT_M30 = "PT_TF_EDIT_M30";
string BTN_TF_EDIT_H1 = "PT_TF_EDIT_H1";
string PANEL_BG = "PT_PROFIT_GOV_PANEL_BG";
string LBL_TF_TITLE = "PT_TF_TITLE";
string LBL_TF_M1 = "PT_TF_LBL_M1";
string LBL_TF_M5 = "PT_TF_LBL_M5";
string LBL_TF_M15 = "PT_TF_LBL_M15";
string LBL_TF_M30 = "PT_TF_LBL_M30";
string LBL_TF_H1 = "PT_TF_LBL_H1";
string LBL_TF_STATUS = "PT_TF_STATUS";

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
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf == PERIOD_M1)   return "M1";
   if(tf == PERIOD_M2)   return "M2";
   if(tf == PERIOD_M3)   return "M3";
   if(tf == PERIOD_M4)   return "M4";
   if(tf == PERIOD_M5)   return "M5";
   if(tf == PERIOD_M6)   return "M6";
   if(tf == PERIOD_M10)  return "M10";
   if(tf == PERIOD_M12)  return "M12";
   if(tf == PERIOD_M15)  return "M15";
   if(tf == PERIOD_M20)  return "M20";
   if(tf == PERIOD_M30)  return "M30";
   if(tf == PERIOD_H1)   return "H1";
   if(tf == PERIOD_H2)   return "H2";
   if(tf == PERIOD_H3)   return "H3";
   if(tf == PERIOD_H4)   return "H4";
   if(tf == PERIOD_H6)   return "H6";
   if(tf == PERIOD_H8)   return "H8";
   if(tf == PERIOD_H12)  return "H12";
   if(tf == PERIOD_D1)   return "D1";
   if(tf == PERIOD_W1)   return "W1";
   if(tf == PERIOD_MN1)  return "MN1";
   return IntegerToString((int)_Period);
}

bool SymbolAllowed(const string symbol)
{
   if(!InpOnlyCurrentSymbol)
      return true;
   return (StringCompare(symbol, _Symbol, false) == 0);
}

bool MagicAllowed(const long magic)
{
   if(InpMagicNumberFilter < 0)
      return true;
   return (magic == InpMagicNumberFilter);
}

long ChartHjfxMagic()
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;
   if(tf == PERIOD_M1)   return InpHjfxMagicM1;
   if(tf == PERIOD_M5)   return InpHjfxMagicM5;
   if(tf == PERIOD_M15)  return InpHjfxMagicM15;
   if(tf == PERIOD_M30)  return InpHjfxMagicM30;
   if(tf == PERIOD_H1)   return InpHjfxMagicH1;
   return -1;
}

string SettingsKey(const string suffix)
{
   string scope = InpOnlyCurrentSymbol ? _Symbol : "ALL";
   return "PT_PROFIT_GOV_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + scope + "_" + suffix;
}

void LoadTfTargets()
{
   g_tf_target_m1 = InpTfTargetM1;
   g_tf_target_m5 = InpTfTargetM5;
   g_tf_target_m15 = InpTfTargetM15;
   g_tf_target_m30 = InpTfTargetM30;
   g_tf_target_h1 = InpTfTargetH1;

   if(GlobalVariableCheck(SettingsKey("M1")))  g_tf_target_m1 = GlobalVariableGet(SettingsKey("M1"));
   if(GlobalVariableCheck(SettingsKey("M5")))  g_tf_target_m5 = GlobalVariableGet(SettingsKey("M5"));
   if(GlobalVariableCheck(SettingsKey("M15"))) g_tf_target_m15 = GlobalVariableGet(SettingsKey("M15"));
   if(GlobalVariableCheck(SettingsKey("M30"))) g_tf_target_m30 = GlobalVariableGet(SettingsKey("M30"));
   if(GlobalVariableCheck(SettingsKey("H1")))  g_tf_target_h1 = GlobalVariableGet(SettingsKey("H1"));
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
   if(!GlobalVariableCheck(key))
      return fallback;
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
   if(StringLen(name) <= 0)
      name = "ProfitGovernor_Audit_MT5.csv";
   return name;
}

void AuditWrite(const string event_name,
                const string tf,
                const ulong ticket,
                const string symbol,
                const long magic,
                const double volume,
                const double pnl,
                const double target,
                const string result,
                const string reason,
                const string detail)
{
   if(!InpAuditCsvEnabled)
      return;

   ResetLastError();
   int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
   if(InpAuditUseCommonFiles)
      flags = flags | FILE_COMMON;
   int h = FileOpen(AuditFileName(), flags, ',');
   if(h == INVALID_HANDLE)
   {
      Print("ManualCloseButtons: audit csv open failed file=", AuditFileName(), " err=", GetLastError());
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
             IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)),
             "MT5",
             event_name,
             tf,
             IntegerToString((long)ticket),
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
   if(tf == "M1")  return g_tf_sig_m1;
   if(tf == "M5")  return g_tf_sig_m5;
   if(tf == "M15") return g_tf_sig_m15;
   if(tf == "M30") return g_tf_sig_m30;
   if(tf == "H1")  return g_tf_sig_h1;
   return 0.0;
}

double LoadTfDisarmSignature(const string tf)
{
   string key = TfDisarmSigKey(tf);
   if(!GlobalVariableCheck(key))
      return 0.0;
   return GlobalVariableGet(key);
}

void SaveTfDisarmSignature(const string tf, const bool armed)
{
   GlobalVariableSet(TfDisarmSigKey(tf), armed ? 0.0 : TfCurrentSignature(tf));
}

double ParseEditDouble(const string objectName, const double fallback)
{
   if(ObjectFind(0, objectName) < 0)
      return fallback;
   string raw = ObjectGetString(0, objectName, OBJPROP_TEXT);
   StringReplace(raw, ",", ".");
   double value = StringToDouble(raw);
   if(value < 0.0)
      value = 0.0;
   return value;
}

long TfMagicByName(const string tf)
{
   if(tf == "M1")  return InpHjfxMagicM1;
   if(tf == "M5")  return InpHjfxMagicM5;
   if(tf == "M15") return InpHjfxMagicM15;
   if(tf == "M30") return InpHjfxMagicM30;
   if(tf == "H1")  return InpHjfxMagicH1;
   return -1;
}

bool MagicBelongsToTf(const string tf, const long magic);

long TmaOffsetByTf(const string tf)
{
   if(tf == "M1")  return InpTmaMagicOffsetM1;
   if(tf == "M5")  return InpTmaMagicOffsetM5;
   if(tf == "M15") return InpTmaMagicOffsetM15;
   if(tf == "M30") return InpTmaMagicOffsetM30;
   if(tf == "H1")  return InpTmaMagicOffsetH1;
   return 0;
}

bool TmaMagicMatchesTf(const string tf, const long magic)
{
   if(!InpIncludeTmaProMagic)
      return false;
   long offset = TmaOffsetByTf(tf);
   if(offset <= 0)
      return false;

   string parts[];
   int n = StringSplit(InpTmaMagicBasesCsv, ',', parts);
   for(int i = 0; i < n; i++)
   {
      long base = (long)StringToInteger(parts[i]);
      if(base > 0 && (magic == base + offset + 1 || magic == base + offset + 2))
         return true;
   }
   return false;
}

string ExtraMagicCsvByTf(const string tf)
{
   if(tf == "M1")  return InpExtraMagicM1Csv;
   if(tf == "M5")  return InpExtraMagicM5Csv;
   if(tf == "M15") return InpExtraMagicM15Csv;
   if(tf == "M30") return InpExtraMagicM30Csv;
   if(tf == "H1")  return InpExtraMagicH1Csv;
   return "";
}

bool CsvContainsMagic(const string csv, const long magic)
{
   if(csv == "")
      return false;
   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
   {
      long value = (long)StringToInteger(parts[i]);
      if(value == magic)
         return true;
   }
   return false;
}

bool MagicBelongsToTf(const string tf, const long magic)
{
   long hjfx = TfMagicByName(tf);
   if(hjfx >= 0 && magic == hjfx)
      return true;
   if(InpIncludeIndicatorV2Magic)
   {
      if(tf == "M1" && magic == InpIndicatorV2MagicM1) return true;
      if(tf == "M5" && magic == InpIndicatorV2MagicM5) return true;
      if(tf == "M15" && magic == InpIndicatorV2MagicM15) return true;
      if(tf == "M30" && magic == InpIndicatorV2MagicM30) return true;
      if(tf == "H1" && magic == InpIndicatorV2MagicH1) return true;
   }
   if(CsvContainsMagic(ExtraMagicCsvByTf(tf), magic))
      return true;
   return TmaMagicMatchesTf(tf, magic);
}

bool PositionAllowedForTfGovernor(const string symbol, const long magic)
{
   if(InpOnlyCurrentSymbol && StringCompare(symbol, _Symbol, false) != 0)
      return false;
   if(InpAutoCloseRequireMagic && magic < 0)
      return false;
   return (
      MagicBelongsToTf("M1", magic) ||
      MagicBelongsToTf("M5", magic) ||
      MagicBelongsToTf("M15", magic) ||
      MagicBelongsToTf("M30", magic) ||
      MagicBelongsToTf("H1", magic)
   );
}

long AutoCloseMagicFilter()
{
   if(InpAutoCloseMagicOverride >= 0)
      return InpAutoCloseMagicOverride;
   if(InpAutoCloseUseHjfxTfMagic)
      return ChartHjfxMagic();
   return InpMagicNumberFilter;
}

bool AutoClosePositionAllowed(const string symbol, const long magic, const string comment)
{
   // Profit target automation is intentionally scoped to the chart symbol.
   if(StringCompare(symbol, _Symbol, false) != 0)
      return false;

   long selectedMagic = AutoCloseMagicFilter();
   if(selectedMagic >= 0)
   {
      if(magic != selectedMagic)
         return false;
   }
   else if(InpAutoCloseRequireMagic)
      return false;

   return true;
}

void ResetTfPnl()
{
   g_tf_pnl_m1 = 0.0;  g_tf_count_m1 = 0;
   g_tf_pnl_m5 = 0.0;  g_tf_count_m5 = 0;
   g_tf_pnl_m15 = 0.0; g_tf_count_m15 = 0;
   g_tf_pnl_m30 = 0.0; g_tf_count_m30 = 0;
   g_tf_pnl_h1 = 0.0;  g_tf_count_h1 = 0;
   g_tf_sig_m1 = 0.0;
   g_tf_sig_m5 = 0.0;
   g_tf_sig_m15 = 0.0;
   g_tf_sig_m30 = 0.0;
   g_tf_sig_h1 = 0.0;
}

double TicketSignatureValue(const ulong ticket)
{
   return (double)(long)ticket;
}

void AddTfPnl(const long magic, const double pnl, const ulong ticket)
{
   double sig = TicketSignatureValue(ticket);
   if(MagicBelongsToTf("M1", magic))  { g_tf_pnl_m1 += pnl;  g_tf_count_m1++;  g_tf_sig_m1 += sig;  return; }
   if(MagicBelongsToTf("M5", magic))  { g_tf_pnl_m5 += pnl;  g_tf_count_m5++;  g_tf_sig_m5 += sig;  return; }
   if(MagicBelongsToTf("M15", magic)) { g_tf_pnl_m15 += pnl; g_tf_count_m15++; g_tf_sig_m15 += sig; return; }
   if(MagicBelongsToTf("M30", magic)) { g_tf_pnl_m30 += pnl; g_tf_count_m30++; g_tf_sig_m30 += sig; return; }
   if(MagicBelongsToTf("H1", magic))  { g_tf_pnl_h1 += pnl;  g_tf_count_h1++;  g_tf_sig_h1 += sig;  return; }
}

void RefreshTfGroupPnl()
{
   ResetTfPnl();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!PositionAllowedForTfGovernor(symbol, magic))
         continue;

      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      AddTfPnl(magic, pnl, ticket);
   }
}

int CloseTfGroupPositions(const string tf, const string reason)
{
   long targetMagic = TfMagicByName(tf);
   if(targetMagic < 0)
      return 0;

   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   trade.SetDeviationInPoints(InpSlippagePoints);

   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!PositionAllowedForTfGovernor(symbol, magic) || !MagicBelongsToTf(tf, magic))
            continue;

         ResetLastError();
         if(trade.PositionClose(ticket))
         {
            affected++;
            changedThisPass++;
         }
         else
         {
            Print("ManualCloseButtons: TF profit close failed tf=", tf,
                  " ticket=", ticket,
                  " symbol=", symbol,
                  " reason=", reason,
                  " retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription(),
                  " err=", GetLastError());
         }
      }

      if(changedThisPass <= 0)
         break;
      Sleep(250);
   }

   Print("ManualCloseButtons: TF profit close completed tf=", tf, " reason=", reason, " affected=", affected);
   return affected;
}

double TfPartialClosePct()
{
   if(InpTfPartialClosePct <= 0.0)
      return 50.0;
   return MathMin(100.0, InpTfPartialClosePct);
}

bool PositionSlAtOrBetterBreakEven(const ENUM_POSITION_TYPE type, const double sl, const double be)
{
   if(sl <= 0.0)
      return false;
   if(type == POSITION_TYPE_BUY)
      return (sl + 1e-8 >= be);
   if(type == POSITION_TYPE_SELL)
      return (sl - 1e-8 <= be);
   return false;
}

bool BreakEvenStopAllowedNow(const string symbol, const ENUM_POSITION_TYPE type, const double be)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.00001;
   long stopLevelPoints = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopLevelPoints < 0)
      stopLevelPoints = 0;
   double minDistance = (double)stopLevelPoints * point;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

   if(type == POSITION_TYPE_BUY)
      return (bid <= 0.0 || be <= bid - minDistance + 1e-8);
   if(type == POSITION_TYPE_SELL)
      return (ask <= 0.0 || be >= ask + minDistance - 1e-8);
   return false;
}

bool MovePositionStopToBreakEven(const ulong ticket, const string reason)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double be = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), digits);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);

   if(PositionSlAtOrBetterBreakEven(type, sl, be))
      return true;

   if(!BreakEvenStopAllowedNow(symbol, type, be))
   {
      Print("ManualCloseButtons: SL->BE skipped stop-level tf partial ticket=", ticket,
            " symbol=", symbol,
            " be=", DoubleToString(be, digits),
            " reason=", reason);
      AuditWrite("sl_be_skipped_stop_level", "", ticket, symbol, PositionGetInteger(POSITION_MAGIC), PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PROFIT), 0.0, "skipped", reason, "be=" + DoubleToString(be, digits));
      return false;
   }

   ResetLastError();
   if(trade.PositionModify(ticket, be, tp))
   {
      AuditWrite("sl_be_success", "", ticket, symbol, PositionGetInteger(POSITION_MAGIC), PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PROFIT), 0.0, "ok", reason, "be=" + DoubleToString(be, digits));
      return true;
   }

   Print("ManualCloseButtons: SL->BE failed ticket=", ticket,
         " symbol=", symbol,
         " be=", DoubleToString(be, digits),
         " reason=", reason,
         " retcode=", trade.ResultRetcode(),
         " desc=", trade.ResultRetcodeDescription(),
         " err=", GetLastError());
   AuditWrite("sl_be_failed", "", ticket, symbol, PositionGetInteger(POSITION_MAGIC), PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PROFIT), 0.0, "failed", reason, "be=" + DoubleToString(be, digits) + " retcode=" + IntegerToString((int)trade.ResultRetcode()) + " err=" + IntegerToString(GetLastError()));
   return false;
}

bool ClosePositionAfterBreakEvenFailure(const ulong ticket, const string reason)
{
   int maxPasses = MathMax(1, InpMaxClosePasses);
   for(int pass = 0; pass < maxPasses; pass++)
   {
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         return true;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      ResetLastError();
      if(trade.PositionClose(ticket))
      {
         Print("ManualCloseButtons: runner closed because SL->BE failed ticket=", ticket,
               " symbol=", symbol,
               " reason=", reason,
               " pass=", pass + 1);
         AuditWrite("runner_close_after_be_failed", "", ticket, symbol, magic, volume, pnl, 0.0, "ok", reason, "pass=" + IntegerToString(pass + 1));
         return true;
      }

      Print("ManualCloseButtons: runner close after SL->BE failure failed ticket=", ticket,
            " symbol=", symbol,
            " reason=", reason,
            " pass=", pass + 1,
            " retcode=", trade.ResultRetcode(),
            " desc=", trade.ResultRetcodeDescription(),
            " err=", GetLastError());
      AuditWrite("runner_close_after_be_failed", "", ticket, symbol, magic, volume, pnl, 0.0, "failed", reason, "pass=" + IntegerToString(pass + 1) + " retcode=" + IntegerToString((int)trade.ResultRetcode()) + " err=" + IntegerToString(GetLastError()));
      Sleep(250);
   }
   return false;
}

int PartialCloseTfGroupPositions(const string tf, const string reason, const double pct)
{
   long targetMagic = TfMagicByName(tf);
   if(targetMagic < 0)
      return 0;

   int affected = 0;
   int maxPasses = 1; // Partial profit securing must happen once per armed TF cycle.
   trade.SetDeviationInPoints(InpSlippagePoints);
   g_last_partial_unsecured_runner = false;

   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!PositionAllowedForTfGovernor(symbol, magic) || !MagicBelongsToTf(tf, magic))
            continue;

         double volume = PositionGetDouble(POSITION_VOLUME);
         double positionPnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         double minLot = SymbolMinLot(symbol);
         double closeLots = NormalizeLot(symbol, volume * pct / 100.0);
         double remaining = NormalizeDouble(volume - closeLots, 8);

         if(closeLots + 1e-8 < minLot || remaining + 1e-8 < minLot)
         {
            Print("ManualCloseButtons: TF partial skipped unsplittable tf=", tf,
                  " ticket=", ticket,
                  " symbol=", symbol,
                  " volume=", DoubleToString(volume, 2),
                  " closeLots=", DoubleToString(closeLots, 2),
                  " minLot=", DoubleToString(minLot, 2),
                  " action=full_close");
            AuditWrite("partial_unsplittable_full_close", tf, ticket, symbol, magic, volume, positionPnl, 0.0, "attempt", reason, "closeLots=" + DoubleToString(closeLots, 2) + " remaining=" + DoubleToString(remaining, 2) + " minLot=" + DoubleToString(minLot, 2));
            bool closedUnsplittable = ClosePositionAfterBreakEvenFailure(ticket, "tf_partial_unsplittable_full_close");
            if(closedUnsplittable)
            {
               affected++;
               changedThisPass++;
            }
            else
               g_last_partial_unsecured_runner = true;
            continue;
         }

         ResetLastError();
         if(trade.PositionClosePartial(ticket, closeLots))
         {
            AuditWrite("partial_close_success", tf, ticket, symbol, magic, closeLots, positionPnl, 0.0, "ok", reason, "beforeVolume=" + DoubleToString(volume, 2) + " remaining=" + DoubleToString(remaining, 2));
            if(InpTfPartialMoveSlToBreakEven)
            {
               Sleep(100);
               bool beOk = MovePositionStopToBreakEven(ticket, "tf_partial_profit_target");
               if(!beOk && InpTfPartialCloseRunnerIfBeFails)
               {
                  bool closedUnsafeRunner = ClosePositionAfterBreakEvenFailure(ticket, "tf_partial_be_failed");
                  if(!closedUnsafeRunner)
                     g_last_partial_unsecured_runner = true;
               }
            }
            affected++;
            changedThisPass++;
         }
         else
         {
            Print("ManualCloseButtons: TF partial close failed tf=", tf,
                  " ticket=", ticket,
                  " symbol=", symbol,
                  " closeLots=", DoubleToString(closeLots, 2),
                  " reason=", reason,
                  " retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription(),
                  " err=", GetLastError());
            AuditWrite("partial_close_failed", tf, ticket, symbol, magic, closeLots, positionPnl, 0.0, "failed", reason, "beforeVolume=" + DoubleToString(volume, 2) + " remaining=" + DoubleToString(remaining, 2) + " retcode=" + IntegerToString((int)trade.ResultRetcode()) + " err=" + IntegerToString(GetLastError()));
         }
      }

      if(changedThisPass <= 0)
         break;
      Sleep(250);
   }

   Print("ManualCloseButtons: TF partial close completed tf=", tf,
         " reason=", reason,
         " pct=", DoubleToString(pct, 1),
         " affected=", affected);
   string unsecured = g_last_partial_unsecured_runner ? "1" : "0";
   AuditWrite("tf_partial_complete", tf, 0, "", 0, 0.0, 0.0, 0.0, "complete", reason, "pct=" + DoubleToString(pct, 1) + " affected=" + IntegerToString(affected) + " unsecured=" + unsecured);
   return affected;
}

bool TfGroupArmed(const string tf)
{
   if(tf == "M1")  return g_tf_armed_m1;
   if(tf == "M5")  return g_tf_armed_m5;
   if(tf == "M15") return g_tf_armed_m15;
   if(tf == "M30") return g_tf_armed_m30;
   if(tf == "H1")  return g_tf_armed_h1;
   return false;
}

void SetTfGroupArmed(const string tf, const bool armed)
{
   if(tf == "M1")  { g_tf_armed_m1 = armed;  SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "M5")  { g_tf_armed_m5 = armed;  SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "M15") { g_tf_armed_m15 = armed; SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "M30") { g_tf_armed_m30 = armed; SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
   if(tf == "H1")  { g_tf_armed_h1 = armed;  SaveTfArmedState(tf, armed); SaveTfDisarmSignature(tf, armed); return; }
}

void RearmFlatTfGroups()
{
   if(!g_tf_armed_m1 && (g_tf_count_m1 <= 0 || MathAbs(LoadTfDisarmSignature("M1") - g_tf_sig_m1) > 0.5))       { SetTfGroupArmed("M1", true); AuditWrite("tf_rearmed", "M1", 0, "", 0, 0.0, g_tf_pnl_m1, g_tf_target_m1, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m1)); }
   if(!g_tf_armed_m5 && (g_tf_count_m5 <= 0 || MathAbs(LoadTfDisarmSignature("M5") - g_tf_sig_m5) > 0.5))       { SetTfGroupArmed("M5", true); AuditWrite("tf_rearmed", "M5", 0, "", 0, 0.0, g_tf_pnl_m5, g_tf_target_m5, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m5)); }
   if(!g_tf_armed_m15 && (g_tf_count_m15 <= 0 || MathAbs(LoadTfDisarmSignature("M15") - g_tf_sig_m15) > 0.5))  { SetTfGroupArmed("M15", true); AuditWrite("tf_rearmed", "M15", 0, "", 0, 0.0, g_tf_pnl_m15, g_tf_target_m15, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m15)); }
   if(!g_tf_armed_m30 && (g_tf_count_m30 <= 0 || MathAbs(LoadTfDisarmSignature("M30") - g_tf_sig_m30) > 0.5))  { SetTfGroupArmed("M30", true); AuditWrite("tf_rearmed", "M30", 0, "", 0, 0.0, g_tf_pnl_m30, g_tf_target_m30, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_m30)); }
   if(!g_tf_armed_h1 && (g_tf_count_h1 <= 0 || MathAbs(LoadTfDisarmSignature("H1") - g_tf_sig_h1) > 0.5))       { SetTfGroupArmed("H1", true); AuditWrite("tf_rearmed", "H1", 0, "", 0, 0.0, g_tf_pnl_h1, g_tf_target_h1, "armed", "flat_or_signature_changed", "count=" + IntegerToString(g_tf_count_h1)); }
}

int ApplyTfProfitAction(const string tf, const string reason)
{
   int affected = 0;
   g_last_partial_unsecured_runner = false;
   if(InpTfProfitAction == TF_PROFIT_CLOSE_ALL)
      affected = CloseTfGroupPositions(tf, reason);
   else
      affected = PartialCloseTfGroupPositions(tf, reason, TfPartialClosePct());

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

bool PositionTypeMatches(const ENUM_POSITION_TYPE type, string side)
{
   StringToUpper(side);
   if(side == "BUY")
      return (type == POSITION_TYPE_BUY);
   if(side == "SELL")
      return (type == POSITION_TYPE_SELL);
   if(side == "ALL")
      return (type == POSITION_TYPE_BUY || type == POSITION_TYPE_SELL);
   return false;
}

bool PendingTypeMatches(const ENUM_ORDER_TYPE type, string side)
{
   StringToUpper(side);
   if(side == "BUY")
      return (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT);
   if(side == "SELL")
      return (type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT);
   if(side == "ALL")
      return (
         type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT ||
         type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT
      );
   return false;
}

double SymbolMinLot(const string symbol)
{
   double v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(v <= 0.0)
      v = 0.01;
   return v;
}

double SymbolMaxLot(const string symbol)
{
   double v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(v <= 0.0)
      v = 100.0;
   return v;
}

double SymbolLotStep(const string symbol)
{
   double v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(v <= 0.0)
      v = InpLotStep;
   if(v <= 0.0)
      v = 0.01;
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
   return NormalizeDouble(v, 2);
}

string LotText(const double lot)
{
   return DoubleToString(NormalizeLot(_Symbol, lot), 2);
}

void UpdateLotEdit()
{
   if(ObjectFind(0, BTN_LOT_EDIT) >= 0)
      ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_TEXT, LotText(g_lot));
}

void SetLot(const double lot)
{
   g_lot = NormalizeLot(_Symbol, lot);
   UpdateLotEdit();
}

void NudgeLot(const int dir)
{
   double step = SymbolLotStep(_Symbol);
   if(InpLotStep > 0.0)
      step = InpLotStep;
   SetLot(g_lot + (double)dir * step);
}

void ReadLotFromEdit()
{
   if(ObjectFind(0, BTN_LOT_EDIT) < 0)
      return;
   string raw = ObjectGetString(0, BTN_LOT_EDIT, OBJPROP_TEXT);
   StringReplace(raw, ",", ".");
   double v = StringToDouble(raw);
   if(v <= 0.0)
      v = g_lot;
   SetLot(v);
}

bool OpenMarketPosition(string side)
{
   StringToUpper(side);
   if(side != "BUY" && side != "SELL")
      return false;

   ReadLotFromEdit();
   double lot = NormalizeLot(_Symbol, g_lot);
   if(lot <= 0.0)
      return false;

   trade.SetDeviationInPoints(InpSlippagePoints);
   if(InpOpenMagicNumber >= 0)
      trade.SetExpertMagicNumber((ulong)InpOpenMagicNumber);

   ResetLastError();
   bool ok = false;
   if(side == "BUY")
      ok = trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, InpOpenComment);
   else
      ok = trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, InpOpenComment);

   if(!ok)
   {
      Print("ManualCloseButtons: open ", side, " failed symbol=", _Symbol,
            " lot=", DoubleToString(lot, 2),
            " retcode=", trade.ResultRetcode(),
            " desc=", trade.ResultRetcodeDescription(),
            " err=", GetLastError());
      return false;
   }

   Print("ManualCloseButtons: opened ", side, " symbol=", _Symbol, " lot=", DoubleToString(lot, 2));
   return true;
}

int CloseSide(string side)
{
   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   trade.SetDeviationInPoints(InpSlippagePoints);

   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         if(!SymbolAllowed(symbol) || !MagicAllowed(magic) || !PositionTypeMatches(type, side))
            continue;

         ResetLastError();
         if(trade.PositionClose(ticket))
         {
            affected++;
            changedThisPass++;
         }
         else
         {
            Print("ManualCloseButtons: position close failed ticket=", ticket,
                  " symbol=", symbol,
                  " retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription(),
                  " err=", GetLastError());
         }
      }

      if(InpClosePendingOrders)
      {
         for(int j = OrdersTotal() - 1; j >= 0; j--)
         {
            ulong ticket = OrderGetTicket(j);
            if(ticket == 0 || !OrderSelect(ticket))
               continue;

            string symbol = OrderGetString(ORDER_SYMBOL);
            long magic = OrderGetInteger(ORDER_MAGIC);
            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

            if(!SymbolAllowed(symbol) || !MagicAllowed(magic) || !PendingTypeMatches(type, side))
               continue;

            ResetLastError();
            if(trade.OrderDelete(ticket))
            {
               affected++;
               changedThisPass++;
            }
            else
            {
               Print("ManualCloseButtons: pending delete failed ticket=", ticket,
                     " symbol=", symbol,
                     " retcode=", trade.ResultRetcode(),
                     " desc=", trade.ResultRetcodeDescription(),
                     " err=", GetLastError());
            }
         }
      }

      if(changedThisPass <= 0)
         break;

      Sleep(250);
   }

   Print("ManualCloseButtons: ", side, " close action completed. affected=", affected);
   return affected;
}

double CurrentChartScopeFloatingPnl(int &positionCount)
{
   double total = 0.0;
   positionCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);
      string comment = PositionGetString(POSITION_COMMENT);
      if(!AutoClosePositionAllowed(symbol, magic, comment))
         continue;

      total += PositionGetDouble(POSITION_PROFIT);
      total += PositionGetDouble(POSITION_SWAP);
      positionCount++;
   }

   return total;
}

int CloseChartScopePositions(const string reason)
{
   int affected = 0;
   int maxPasses = MathMax(1, InpMaxClosePasses);
   trade.SetDeviationInPoints(InpSlippagePoints);

   for(int pass = 0; pass < maxPasses; pass++)
   {
      int changedThisPass = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         string comment = PositionGetString(POSITION_COMMENT);
         if(!AutoClosePositionAllowed(symbol, magic, comment))
            continue;

         ResetLastError();
         if(trade.PositionClose(ticket))
         {
            affected++;
            changedThisPass++;
         }
         else
         {
            Print("ManualCloseButtons: auto profit close failed ticket=", ticket,
                  " symbol=", symbol,
                  " reason=", reason,
                  " retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription(),
                  " err=", GetLastError());
         }
      }

      if(changedThisPass <= 0)
         break;

      Sleep(250);
   }

   Print("ManualCloseButtons: auto profit close completed reason=", reason, " affected=", affected);
   return affected;
}

void CheckAutoCloseProfitTarget()
{
   if(!InpAutoCloseProfitEnabled)
      return;
   if(InpAutoCloseProfitTargetUsd <= 0.0)
      return;
   if(g_auto_close_in_progress)
      return;

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   int cooldown = MathMax(1, InpAutoCloseCooldownSeconds);
   if(g_last_auto_close_at > 0 && nowTs > 0 && (nowTs - g_last_auto_close_at) < cooldown)
      return;

   int count = 0;
   double pnl = CurrentChartScopeFloatingPnl(count);
   if(count <= 0)
      return;

   if(pnl + 1e-8 < InpAutoCloseProfitTargetUsd)
      return;

   g_auto_close_in_progress = true;
   Print("ManualCloseButtons: auto profit target reached symbol=", _Symbol,
         " tf=", ChartTimeframeText(),
         " positions=", count,
         " pnl=", DoubleToString(pnl, 2),
         " target=", DoubleToString(InpAutoCloseProfitTargetUsd, 2));
   CloseChartScopePositions("profit_target");
   g_last_auto_close_at = nowTs;
   g_auto_close_in_progress = false;
}

bool TfTargetHit(const double pnl, const int count, const double target)
{
   if(target <= 0.0)
      return false;
   if(count <= 0)
      return false;
   return (pnl + 1e-8 >= target);
}

bool TfTargetReady(const string tf, const double pnl, const int count, const double target)
{
   return (TfTargetHit(pnl, count, target) && TfGroupArmed(tf));
}

void CheckTfGroupProfitTargets()
{
   if(!InpTfGroupProfitEnabled)
      return;
   if(g_auto_close_in_progress)
      return;

   datetime nowTs = TimeCurrent();
   if(nowTs <= 0)
      nowTs = TimeLocal();
   int cooldown = MathMax(1, InpAutoCloseCooldownSeconds);
   if(g_last_auto_close_at > 0 && nowTs > 0 && (nowTs - g_last_auto_close_at) < cooldown)
      return;

   RefreshTfGroupPnl();
   RearmFlatTfGroups();

   bool anyHit = false;
   if(TfTargetReady("M1", g_tf_pnl_m1, g_tf_count_m1, g_tf_target_m1)) anyHit = true;
   if(TfTargetReady("M5", g_tf_pnl_m5, g_tf_count_m5, g_tf_target_m5)) anyHit = true;
   if(TfTargetReady("M15", g_tf_pnl_m15, g_tf_count_m15, g_tf_target_m15)) anyHit = true;
   if(TfTargetReady("M30", g_tf_pnl_m30, g_tf_count_m30, g_tf_target_m30)) anyHit = true;
   if(TfTargetReady("H1", g_tf_pnl_h1, g_tf_count_h1, g_tf_target_h1)) anyHit = true;
   if(!anyHit)
      return;

   g_auto_close_in_progress = true;
   int affected = 0;
   if(TfTargetReady("M1", g_tf_pnl_m1, g_tf_count_m1, g_tf_target_m1))
   {
      g_tf_status = "Hit M1 pnl=" + DoubleToString(g_tf_pnl_m1, 2) + " target=" + DoubleToString(g_tf_target_m1, 2);
      Print("ManualCloseButtons: TF profit target reached tf=M1 positions=", g_tf_count_m1, " pnl=", DoubleToString(g_tf_pnl_m1, 2), " target=", DoubleToString(g_tf_target_m1, 2));
      AuditWrite("tf_target_hit", "M1", 0, "", 0, 0.0, g_tf_pnl_m1, g_tf_target_m1, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m1) + " sig=" + DoubleToString(g_tf_sig_m1, 0));
      affected = ApplyTfProfitAction("M1", "tf_profit_target");
      g_tf_status = "M1 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("M5", g_tf_pnl_m5, g_tf_count_m5, g_tf_target_m5))
   {
      g_tf_status = "Hit M5 pnl=" + DoubleToString(g_tf_pnl_m5, 2) + " target=" + DoubleToString(g_tf_target_m5, 2);
      Print("ManualCloseButtons: TF profit target reached tf=M5 positions=", g_tf_count_m5, " pnl=", DoubleToString(g_tf_pnl_m5, 2), " target=", DoubleToString(g_tf_target_m5, 2));
      AuditWrite("tf_target_hit", "M5", 0, "", 0, 0.0, g_tf_pnl_m5, g_tf_target_m5, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m5) + " sig=" + DoubleToString(g_tf_sig_m5, 0));
      affected = ApplyTfProfitAction("M5", "tf_profit_target");
      g_tf_status = "M5 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("M15", g_tf_pnl_m15, g_tf_count_m15, g_tf_target_m15))
   {
      g_tf_status = "Hit M15 pnl=" + DoubleToString(g_tf_pnl_m15, 2) + " target=" + DoubleToString(g_tf_target_m15, 2);
      Print("ManualCloseButtons: TF profit target reached tf=M15 positions=", g_tf_count_m15, " pnl=", DoubleToString(g_tf_pnl_m15, 2), " target=", DoubleToString(g_tf_target_m15, 2));
      AuditWrite("tf_target_hit", "M15", 0, "", 0, 0.0, g_tf_pnl_m15, g_tf_target_m15, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m15) + " sig=" + DoubleToString(g_tf_sig_m15, 0));
      affected = ApplyTfProfitAction("M15", "tf_profit_target");
      g_tf_status = "M15 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("M30", g_tf_pnl_m30, g_tf_count_m30, g_tf_target_m30))
   {
      g_tf_status = "Hit M30 pnl=" + DoubleToString(g_tf_pnl_m30, 2) + " target=" + DoubleToString(g_tf_target_m30, 2);
      Print("ManualCloseButtons: TF profit target reached tf=M30 positions=", g_tf_count_m30, " pnl=", DoubleToString(g_tf_pnl_m30, 2), " target=", DoubleToString(g_tf_target_m30, 2));
      AuditWrite("tf_target_hit", "M30", 0, "", 0, 0.0, g_tf_pnl_m30, g_tf_target_m30, "hit", "tf_profit_target", "count=" + IntegerToString(g_tf_count_m30) + " sig=" + DoubleToString(g_tf_sig_m30, 0));
      affected = ApplyTfProfitAction("M30", "tf_profit_target");
      g_tf_status = "M30 target action affected=" + IntegerToString(affected);
   }
   if(TfTargetReady("H1", g_tf_pnl_h1, g_tf_count_h1, g_tf_target_h1))
   {
      g_tf_status = "Hit H1 pnl=" + DoubleToString(g_tf_pnl_h1, 2) + " target=" + DoubleToString(g_tf_target_h1, 2);
      Print("ManualCloseButtons: TF profit target reached tf=H1 positions=", g_tf_count_h1, " pnl=", DoubleToString(g_tf_pnl_h1, 2), " target=", DoubleToString(g_tf_target_h1, 2));
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
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

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
   if(ObjectFind(0, PANEL_BG) >= 0)
      ObjectDelete(0, PANEL_BG);

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

void CreateLotEdit(const int x, const int y, const int w)
{
   if(ObjectFind(0, BTN_LOT_EDIT) >= 0)
      ObjectDelete(0, BTN_LOT_EDIT);

   ObjectCreate(0, BTN_LOT_EDIT, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_YSIZE, InpButtonHeight);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, BTN_LOT_EDIT, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_FONT, "Arial");
   ObjectSetString(0, BTN_LOT_EDIT, OBJPROP_TEXT, LotText(g_lot));
}

void CreateEditBox(const string name, const string text, const int x, const int y, const int w, const int h)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

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

void CreateLabel(const string name, const string text, const int x, const int y, const int w, const int h, const color fg)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

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

void SetObjectText(const string name, const string text)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void CreateTfGovernorDashboard(const int x, const int y)
{
   int labelW = 34;
   int editW = 58;
   int pnlW = 142;
   int rowH = 22;
   CreateLabel(LBL_TF_TITLE, "TF Profit Governor | Target | Live PnL", x, y, 320, rowH, clrNavy);
   int y0 = y + rowH;

   CreateLabel(LBL_TF_M1, "M1", x, y0, labelW, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M1, DoubleToString(g_tf_target_m1, 2), x + 36, y0 - 4, editW, 22);
   CreateLabel(LBL_TF_M1 + "_PNL", "pnl=0.00 count=0", x + 104, y0, pnlW, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_M5, "M5", x, y0, labelW, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M5, DoubleToString(g_tf_target_m5, 2), x + 36, y0 - 4, editW, 22);
   CreateLabel(LBL_TF_M5 + "_PNL", "pnl=0.00 count=0", x + 104, y0, pnlW, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_M15, "M15", x, y0, labelW, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M15, DoubleToString(g_tf_target_m15, 2), x + 36, y0 - 4, editW, 22);
   CreateLabel(LBL_TF_M15 + "_PNL", "pnl=0.00 count=0", x + 104, y0, pnlW, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_M30, "M30", x, y0, labelW, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_M30, DoubleToString(g_tf_target_m30, 2), x + 36, y0 - 4, editW, 22);
   CreateLabel(LBL_TF_M30 + "_PNL", "pnl=0.00 count=0", x + 104, y0, pnlW, rowH, clrBlack);

   y0 += rowH;
   CreateLabel(LBL_TF_H1, "H1", x, y0, labelW, rowH, clrBlack);
   CreateEditBox(BTN_TF_EDIT_H1, DoubleToString(g_tf_target_h1, 2), x + 36, y0 - 4, editW, 22);
   CreateLabel(LBL_TF_H1 + "_PNL", "pnl=0.00 count=0", x + 104, y0, pnlW, rowH, clrBlack);

   y0 += rowH + 2;
   CreateButtonSized(BTN_TF_SAVE, "Save TF TP", x, y0, 112, clrDarkSlateGray);
   CreateLabel(LBL_TF_STATUS, g_tf_status, x + 124, y0 + 4, 260, rowH, clrDimGray);

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
   int affected = CloseTfGroupPositions(tf, "manual_tf_close_button");
   g_tf_status = "Manual close " + tf + " affected=" + IntegerToString(affected);
   RefreshTfGroupPnl();
   UpdateTfGovernorDashboard();
}

void DeleteButtons()
{
   ObjectDelete(0, PANEL_BG);
   ObjectDelete(0, BTN_CLOSE_BUY);
   ObjectDelete(0, BTN_CLOSE_SELL);
   ObjectDelete(0, BTN_CLOSE_ALL);
   ObjectDelete(0, BTN_LOT_DOWN);
   ObjectDelete(0, BTN_LOT_EDIT);
   ObjectDelete(0, BTN_LOT_UP);
   ObjectDelete(0, BTN_OPEN_BUY);
   ObjectDelete(0, BTN_OPEN_SELL);
   ObjectDelete(0, BTN_TF_SAVE);
   ObjectDelete(0, BTN_TF_CLOSE_M1);
   ObjectDelete(0, BTN_TF_CLOSE_M5);
   ObjectDelete(0, BTN_TF_CLOSE_M15);
   ObjectDelete(0, BTN_TF_CLOSE_M30);
   ObjectDelete(0, BTN_TF_CLOSE_H1);
   ObjectDelete(0, BTN_TF_EDIT_M1);
   ObjectDelete(0, BTN_TF_EDIT_M5);
   ObjectDelete(0, BTN_TF_EDIT_M15);
   ObjectDelete(0, BTN_TF_EDIT_M30);
   ObjectDelete(0, BTN_TF_EDIT_H1);
   ObjectDelete(0, LBL_TF_TITLE);
   ObjectDelete(0, LBL_TF_M1);
   ObjectDelete(0, LBL_TF_M5);
   ObjectDelete(0, LBL_TF_M15);
   ObjectDelete(0, LBL_TF_M30);
   ObjectDelete(0, LBL_TF_H1);
   ObjectDelete(0, LBL_TF_M1 + "_PNL");
   ObjectDelete(0, LBL_TF_M5 + "_PNL");
   ObjectDelete(0, LBL_TF_M15 + "_PNL");
   ObjectDelete(0, LBL_TF_M30 + "_PNL");
   ObjectDelete(0, LBL_TF_H1 + "_PNL");
   ObjectDelete(0, LBL_TF_STATUS);
}

int OnInit()
{
   int x = InpButtonX;
   int y = InpButtonY;
   LoadTfTargets();
   LoadTfArmedState();
   SetLot(InpInitialLot);
   CreatePanelBackground(x - 8, y - 8, 420, 292);
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
   Print("ManualCloseButtons initialized. OnlyCurrentSymbol=", InpOnlyCurrentSymbol,
         " MagicFilter=", InpMagicNumberFilter,
         " AutoCloseProfit=", (InpAutoCloseProfitEnabled ? "true" : "false"),
         " AutoTarget=", DoubleToString(InpAutoCloseProfitTargetUsd, 2),
         " ChartScope=", _Symbol, " ", ChartTimeframeText(),
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

   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

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

   ChartRedraw();
}
