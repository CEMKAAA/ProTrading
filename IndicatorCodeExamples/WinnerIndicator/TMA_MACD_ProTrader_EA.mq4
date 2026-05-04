//+------------------------------------------------------------------+
//| TMA MACD ProTrader EA                                            |
//| Standalone execution wrapper for tma-macd-indicator.mq4.          |
//|                                                                  |
//| Design rule: the signal math is not reimplemented here. The EA    |
//| reads the original indicator buffers through iCustom so the       |
//| indicator signal logic stays identical to the source indicator.   |
//+------------------------------------------------------------------+
#property strict

enum SignalMode
{
   SIGNAL_STATE_BUFFERS = 0,      // Existing bridge style: Uptrend/Dntrend state buffers.
   SIGNAL_TREND_EVENTS = 1,       // Production event style: trend buffer 444/888/-444/-888.
   SIGNAL_EVENTS_THEN_STATE = 2,  // Prefer event signals; fallback to state buffers.
   SIGNAL_CHART_CLOSED_BAR_ARROWS = 3 // Trade only the chart arrow object on a closed bar.
};

enum StopMode
{
   STOP_ATR = 0,
   STOP_FIXED_POINTS = 1,
   STOP_NONE = 2
};

//----------------------------- Indicator -----------------------------//
input string InpIndicatorName = "tma-macd-indicator";
input int    InpHistory = 1800;
input int    InpIndicatorTimeFrame = PERIOD_CURRENT;
input int    InpTimeFrameAuto = 1;       // Original TFauto: 0=OFF, 1=TF1, 2=TF2, 3=TF3.
input int    InpFastHalfLength = 3;
input int    InpSlowHalfLength = 12;
input int    InpPrice = PRICE_CLOSE;
input int    InpDisplay = 1;             // Original LNtype: 0=LINE, 1=HISTO, 2=TAPE.
input double InpHotLevel = 0.075;
input color  InpLevelColor = C'80,60,210';
input int    InpShowArrows = 3;          // Original showAR: 0=Hide, 1=inside, 2=center, 3=outside.
input int    InpArrowBar = 0;
input string InpArrowsIdentifier = "";
input color  InpArrowUpColor = clrWhite;
input color  InpArrowDownColor = clrRed;
input int    InpArrowGap = 3;
input int    InpArrowCodeUp = 233;
input int    InpArrowCodeDown = 234;
input int    InpArrowSize = 1;
input bool   InpAlertsHotLevel = true;   // Must stay true for 444/-444 event values.
input bool   InpAlertsTmaColor = true;   // Must stay true for 888/-888 event values.
input int    InpIndicatorSignalBar = 1;  // Original indicator SIGNALBAR input.
input bool   InpIndicatorAlertsMessage = false;
input bool   InpIndicatorAlertsSound = false;
input bool   InpIndicatorAlertsEmail = false;
input bool   InpIndicatorAlertsMobile = false;
input string InpSoundFile = "expert.wav";

//------------------------------- Signal ------------------------------//
input SignalMode InpSignalMode = SIGNAL_STATE_BUFFERS;
input int        InpBuyBufferIndex = 1;     // Uptrend.
input int        InpSellBufferIndex = 2;    // Dntrend.
input int        InpTrendBufferIndex = 5;   // Internal trend buffer: 444/888 BUY, -444/-888 SELL.
input int        InpSignalShift = 1;        // 1 = closed bar. Recommended default.
input int        InpPollSeconds = 1;
input int        InpConfirmSeconds = 60;    // Existing winner bridge behavior.
input int        InpStateConfirmBars = 2;   // Color-following mode: require N closed bars with same green/red state.
input bool       InpRequireClosedBar = true; // Prevent live-bar repaint flips from becoming trades.
input bool       InpBlockSameBarReverse = true;
input int        InpMinSecondsBetweenSignals = 60;
input bool       InpInvertDirection = false;
input bool       InpSendInitialSignalOnStart = false;
input bool       InpSyncExistingOrdersOnStart = true;
input double     InpSignalAbsMin = 0.0000001;

//------------------------------ Trading ------------------------------//
input bool   InpTradingEnabled = true;
input bool   InpAllowBuy = true;
input bool   InpAllowSell = true;
input bool   InpEnableNormalMode = true;
input bool   InpEnableAdvancedMode = false;
input double InpLot = 0.10;
input int    InpSlippage = 30;
input int    InpMagicBase = 860500;
input bool   InpUseTfMagicOffset = true;   // Required for ProfitGovernor TF grouping; keeps each chart TF isolated.
input bool   InpManageLegacyMagic = true;  // Also manage old InpMagicBase+1/+2 orders after enabling TF offset.
input int    InpMagicOffsetM1 = 10000;
input int    InpMagicOffsetM5 = 20000;
input int    InpMagicOffsetM15 = 30000;
input int    InpMagicOffsetM30 = 40000;
input int    InpMagicOffsetH1 = 50000;
input string InpOrderCommentPrefix = "TMA_MACD_PRO";
input bool   InpCloseOppositeOnSignal = true;
input bool   InpOneTradePerMode = true;
input bool   InpBlockReentryAfterFlatClose = true; // If a trade is closed manually/SL/TP while signal remains same, wait for reverse/fresh regime.
input int    InpMaxSpreadPoints = 0;       // 0 = disabled. Blocks new entries during spread spikes.

//------------------------------- Risk --------------------------------//
input StopMode InpStopMode = STOP_NONE;    // Default: reversal signal is the stop. Use fixed/ATR only as catastrophe stop.
input int      InpAtrPeriod = 14;
input double   InpSlAtr = 2.2;
input double   InpNormalTpAtr = 0.0;       // 0 = no fixed normal TP; close by reverse.
input int      InpFixedSlPoints = 2500;
input int      InpFixedTpPoints = 0;
input bool     InpMoveSlToBEAfterTp1 = true;
input int      InpBEOffsetPoints = 0;

// Advanced partial TP: R multiples based on initial risk distance.
input double InpAdvTp1R = 0.60;
input double InpAdvTp2R = 1.00;
input double InpAdvTp3R = 1.60;
input double InpAdvTp4R = 2.40;
input double InpAdvTp5R = 3.40;
input double InpAdvClosePct1 = 40.0;
input double InpAdvClosePct2 = 25.0;
input double InpAdvClosePct3 = 15.0;
input double InpAdvClosePct4 = 10.0;
input double InpAdvClosePct5 = 100.0;      // Final stage closes remaining lot.

// Daily account guard. Values are account currency.
input bool   InpDailyGuardEnabled = true;
input double InpDailyProfitTarget = 0.0;    // 0 disables profit target.
input double InpDailyLossLimit = 0.0;       // Positive number, 0 disables loss guard.
input bool   InpCloseAllOnDailyLimit = true;
input bool   InpIncludeOpenPnlInDailyGuard = true;

//------------------------------ Dashboard ----------------------------//
input bool   InpShowDashboard = true;
input int    InpDashCorner = 0;
input int    InpDashX = 12;
input int    InpDashY = 18;
input color  InpDashBg = clrBlack;
input color  InpDashText = clrWhite;
input color  InpDashGood = clrLimeGreen;
input color  InpDashBad = clrTomato;
input color  InpDashWarn = clrGold;
input bool   InpDebugPrint = true;

string   g_prefix = "TMA_MACD_PRO_";
bool     g_runtimePaused = false;
bool     g_runtimeNormal = true;
bool     g_runtimeAdvanced = true;
int      g_runtimeConfirmSeconds = 0;
int      g_runtimeStateConfirmBars = 1;
double   g_runtimeLot = 0.10;
bool     g_dailyHardStop = false;
int      g_confirmedDir = 0;
int      g_pendingDir = 0;
datetime g_pendingStartedAt = 0;
datetime g_pendingBarTime = 0;
datetime g_lastSignalBar = 0;
datetime g_lastExecutionAt = 0;
datetime g_dayStart = 0;
datetime g_lastDashAt = 0;
bool     g_startupBaselineChecked = false;
int      g_lastReadDir = 0;
datetime g_lastReadAt = 0;
datetime g_lastReadBar = 0;
string   g_lastAction = "initialized";
string   g_lastBlock = "-";
double   g_lastBuyBuffer = 0.0;
double   g_lastSellBuffer = 0.0;
double   g_lastTrendBuffer = 0.0;
int      g_normalDisarmedDir = 0;
int      g_advancedDisarmedDir = 0;
bool     g_normalHadBuy = false;
bool     g_normalHadSell = false;
bool     g_advancedHadBuy = false;
bool     g_advancedHadSell = false;

//------------------------------- Utils --------------------------------//
string TfToString(int tf)
{
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

datetime DayStart(datetime t)
{
   MqlDateTime s;
   TimeToStruct(t, s);
   s.hour = 0;
   s.min = 0;
   s.sec = 0;
   return StructToTime(s);
}

int TfMagicOffset()
{
   if(!InpUseTfMagicOffset) return 0;
   int tf = Period();
   if(tf == PERIOD_M1) return InpMagicOffsetM1;
   if(tf == PERIOD_M5) return InpMagicOffsetM5;
   if(tf == PERIOD_M15) return InpMagicOffsetM15;
   if(tf == PERIOD_M30) return InpMagicOffsetM30;
   if(tf == PERIOD_H1) return InpMagicOffsetH1;
   return 0;
}

int EffectiveMagicBase() { return InpMagicBase + TfMagicOffset(); }
int NormalMagic() { return EffectiveMagicBase() + 1; }
int AdvancedMagic() { return EffectiveMagicBase() + 2; }
int LegacyNormalMagic() { return InpMagicBase + 1; }
int LegacyAdvancedMagic() { return InpMagicBase + 2; }

int EffectiveSignalShift()
{
   if(InpSignalMode == SIGNAL_CHART_CLOSED_BAR_ARROWS && InpSignalShift < 1)
      return 1;
   if(InpRequireClosedBar && InpSignalShift < 1)
      return 1;
   if(InpSignalShift < 0)
      return 0;
   return InpSignalShift;
}

int NextHigherTF(int tf)
{
   if(tf == 0) tf = Period();
   if(tf == PERIOD_M1) return PERIOD_M5;
   if(tf == PERIOD_M5) return PERIOD_M15;
   if(tf == PERIOD_M15) return PERIOD_M30;
   if(tf == PERIOD_M30) return PERIOD_H1;
   if(tf == PERIOD_H1) return PERIOD_H4;
   if(tf == PERIOD_H4) return PERIOD_D1;
   if(tf == PERIOD_D1) return PERIOD_W1;
   if(tf == PERIOD_W1) return PERIOD_MN1;
   if(tf == PERIOD_MN1) return PERIOD_MN1;
   return Period();
}

int EffectiveIndicatorTimeframe()
{
   int tf = InpIndicatorTimeFrame;
   if(tf > Period()) return tf;
   if(InpTimeFrameAuto == 1) return NextHigherTF(Period());
   if(InpTimeFrameAuto == 2) return NextHigherTF(NextHigherTF(Period()));
   if(InpTimeFrameAuto == 3) return NextHigherTF(NextHigherTF(NextHigherTF(Period())));
   return Period();
}

string ArrowObjectPrefix()
{
   if(InpArrowsIdentifier != "") return InpArrowsIdentifier;
   return TfToString(EffectiveIndicatorTimeframe()) + ": TMA MACD [" + IntegerToString(InpFastHalfLength) + "-" + IntegerToString(InpSlowHalfLength) + "]_";
}

int ClampInt(int value, int minValue, int maxValue)
{
   if(value < minValue) return minValue;
   if(value > maxValue) return maxValue;
   return value;
}

string SettingsPrefix()
{
   return g_prefix + Symbol() + "_" + IntegerToString(EffectiveMagicBase()) + "_settings_";
}

void LoadRuntimeSettings()
{
   g_runtimeConfirmSeconds = ClampInt(InpConfirmSeconds, 0, 86400);
   g_runtimeStateConfirmBars = ClampInt(InpStateConfirmBars, 1, 100);
   g_runtimeLot = NormalizeLots(InpLot);

   string confirmKey = SettingsPrefix() + "confirm_seconds";
   string barsKey = SettingsPrefix() + "state_confirm_bars";
   string lotKey = SettingsPrefix() + "lot";
   if(GlobalVariableCheck(confirmKey))
      g_runtimeConfirmSeconds = ClampInt((int)GlobalVariableGet(confirmKey), 0, 86400);
   if(GlobalVariableCheck(barsKey))
      g_runtimeStateConfirmBars = ClampInt((int)GlobalVariableGet(barsKey), 1, 100);
   if(GlobalVariableCheck(lotKey))
      g_runtimeLot = NormalizeLots(GlobalVariableGet(lotKey));
}

void SaveRuntimeSettings()
{
   GlobalVariableSet(SettingsPrefix() + "confirm_seconds", g_runtimeConfirmSeconds);
   GlobalVariableSet(SettingsPrefix() + "state_confirm_bars", g_runtimeStateConfirmBars);
   GlobalVariableSet(SettingsPrefix() + "lot", g_runtimeLot);
}

double ParseEditDouble(string name, double fallback)
{
   string raw = EditText(name);
   if(raw == "") return fallback;
   StringReplace(raw, ",", ".");
   double value = StringToDouble(raw);
   if(value <= 0.0) return fallback;
   return value;
}

double NormalizeLots(double lots)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0) step = 0.01;
   double out = MathFloor(lots / step + 0.0000001) * step;
   out = MathMax(minLot, MathMin(maxLot, out));
   int lotDigits = 2;
   if(step < 0.01) lotDigits = 3;
   if(step < 0.001) lotDigits = 4;
   return NormalizeDouble(out, lotDigits);
}

bool IsSignalValue(double v)
{
   if(v == EMPTY_VALUE) return false;
   if(v != v) return false;
   if(MathAbs(v) > 1.0e100) return false;
   if(MathAbs(v) >= 2147483000.0) return false;
   if(MathAbs(v) <= InpSignalAbsMin) return false;
   return true;
}

double ICustomValue(int bufferIndex, int shift)
{
   return iCustom(
      NULL,
      0,
      InpIndicatorName,
      InpHistory,
      InpIndicatorTimeFrame,
      InpTimeFrameAuto,
      InpFastHalfLength,
      InpSlowHalfLength,
      InpPrice,
      InpDisplay,
      InpHotLevel,
      InpLevelColor,
      InpShowArrows,
      InpArrowBar,
      InpArrowsIdentifier,
      InpArrowUpColor,
      InpArrowDownColor,
      InpArrowGap,
      InpArrowCodeUp,
      InpArrowCodeDown,
      InpArrowSize,
      InpAlertsHotLevel,
      InpAlertsTmaColor,
      InpIndicatorSignalBar,
      InpIndicatorAlertsMessage,
      InpIndicatorAlertsSound,
      InpIndicatorAlertsEmail,
      InpIndicatorAlertsMobile,
      InpSoundFile,
      bufferIndex,
      shift
   );
}

int DirectionFromEventBuffer(int shift)
{
   double tv = ICustomValue(InpTrendBufferIndex, shift);
   int rounded = (int)MathRound(tv);
   if(rounded == 444 || rounded == 888) return 1;
   if(rounded == -444 || rounded == -888) return -1;
   return 0;
}

int DirectionFromStateBuffersRaw(int shift)
{
   double buyVal = ICustomValue(InpBuyBufferIndex, shift);
   double sellVal = ICustomValue(InpSellBufferIndex, shift);
   bool buy = IsSignalValue(buyVal);
   bool sell = IsSignalValue(sellVal);
   if(buy && !sell) return 1;
   if(sell && !buy) return -1;
   if(buy && sell && InpDebugPrint)
      Print("TMA MACD EA ambiguous state buffers: buy=", DoubleToString(buyVal, 8), " sell=", DoubleToString(sellVal, 8));
   return 0;
}

int DirectionFromStateBuffers(int shift)
{
   int dir = DirectionFromStateBuffersRaw(shift);
   if(dir == 0) return 0;

   int bars = MathMax(1, g_runtimeStateConfirmBars);
   for(int i = 1; i < bars; i++)
   {
      int older = DirectionFromStateBuffersRaw(shift + i);
      if(older != dir)
      {
         if(InpDebugPrint)
         Print("TMA MACD EA color confirmation waiting dir=", DirText(dir), " confirmBars=", bars, " failedAtShift=", shift + i);
         return 0;
      }
   }
   return dir;
}

int DirectionFromArrowObjectNameText(const string name)
{
   string upper = name;
   StringToUpper(upper);
   if(StringFind(upper, "BUY") >= 0) return 1;
   if(StringFind(upper, "SELL") >= 0) return -1;

   string text = "";
   if(ObjectFind(0, name) >= 0)
      text = ObjectGetString(0, name, OBJPROP_TEXT);
   if(text == "")
      text = ObjectDescription(name);
   StringToUpper(text);
   if(StringFind(text, "BUY") >= 0) return 1;
   if(StringFind(text, "SELL") >= 0) return -1;
   return 0;
}

int DirectionFromClosedBarArrowObjectAtTime(datetime targetTime, int calcShift, string context)
{
   if(targetTime <= 0) return 0;

   // Force the hidden iCustom indicator instance to calculate/draw before scanning objects.
   g_lastTrendBuffer = ICustomValue(InpTrendBufferIndex, MathMax(1, calcShift));

   string prefix = ArrowObjectPrefix();
   int buyCount = 0;
   int sellCount = 0;
   string matched = "";

   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringSubstr(name, 0, StringLen(prefix)) != prefix) continue;
      if(ObjectType(name) != OBJ_ARROW) continue;

      datetime objTime = (datetime)ObjectGet(name, OBJPROP_TIME1);
      if(objTime != targetTime) continue;

      int dir = 0;
      int arrowCode = (int)ObjectGet(name, OBJPROP_ARROWCODE);
      if(arrowCode == InpArrowCodeUp) dir = 1;
      else if(arrowCode == InpArrowCodeDown) dir = -1;
      else dir = DirectionFromArrowObjectNameText(name);

      if(dir > 0) buyCount++;
      if(dir < 0) sellCount++;
      if(matched == "") matched = name;
      else matched = matched + "," + name;
   }

   if(buyCount > 0 && sellCount == 0)
   {
      if(InpDebugPrint)
         Print("TMA MACD EA closed-bar arrow BUY context=", context, " bar=", TimeToString(targetTime, TIME_DATE|TIME_SECONDS), " objects=", matched);
      return 1;
   }
   if(sellCount > 0 && buyCount == 0)
   {
      if(InpDebugPrint)
         Print("TMA MACD EA closed-bar arrow SELL context=", context, " bar=", TimeToString(targetTime, TIME_DATE|TIME_SECONDS), " objects=", matched);
      return -1;
   }
   if(buyCount > 0 && sellCount > 0)
   {
      if(InpDebugPrint)
         Print("TMA MACD EA closed-bar arrow ambiguous context=", context, " bar=", TimeToString(targetTime, TIME_DATE|TIME_SECONDS), " buy=", buyCount, " sell=", sellCount, " objects=", matched);
      return 0;
   }

   if(InpDebugPrint)
      Print("TMA MACD EA closed-bar arrow none context=", context, " bar=", TimeToString(targetTime, TIME_DATE|TIME_SECONDS), " prefix=", prefix);
   return 0;
}

int DirectionFromClosedBarArrowObject(int shift)
{
   int closedShift = MathMax(1, shift);
   datetime targetTime = iTime(NULL, 0, closedShift);
   return DirectionFromClosedBarArrowObjectAtTime(targetTime, closedShift, "current");
}

int ReadDirection()
{
   int dir = 0;
   int shift = EffectiveSignalShift();
   g_lastBuyBuffer = ICustomValue(InpBuyBufferIndex, shift);
   g_lastSellBuffer = ICustomValue(InpSellBufferIndex, shift);
   g_lastTrendBuffer = ICustomValue(InpTrendBufferIndex, shift);
   g_lastReadAt = TimeCurrent();
   g_lastReadBar = iTime(NULL, 0, shift);

   if(InpSignalMode == SIGNAL_CHART_CLOSED_BAR_ARROWS)
      dir = DirectionFromClosedBarArrowObject(shift);
   else if(InpSignalMode == SIGNAL_TREND_EVENTS)
      dir = DirectionFromEventBuffer(shift);
   else if(InpSignalMode == SIGNAL_EVENTS_THEN_STATE)
   {
      dir = DirectionFromEventBuffer(shift);
      if(dir == 0) dir = DirectionFromStateBuffers(shift);
   }
   else
      dir = DirectionFromStateBuffers(shift);

   if(InpInvertDirection)
      dir = -dir;
   if(dir > 0 && !InpAllowBuy) return 0;
   if(dir < 0 && !InpAllowSell) return 0;
   g_lastReadDir = dir;
   return dir;
}

string DirText(int dir)
{
   if(dir > 0) return "BUY";
   if(dir < 0) return "SELL";
   return "NONE";
}

void SetAction(string text)
{
   g_lastAction = text;
   g_lastDashAt = 0;
}

void SetBlock(string text)
{
   g_lastBlock = text;
   g_lastDashAt = 0;
}

string ShortTime(datetime t)
{
   if(t <= 0) return "-";
   return TimeToString(t, TIME_SECONDS);
}

string ShortDateTime(datetime t)
{
   if(t <= 0) return "-";
   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

bool IsOurOrder()
{
   if(OrderSymbol() != Symbol()) return false;
   int m = OrderMagicNumber();
   return (m == NormalMagic() || m == AdvancedMagic());
}

bool IsModeOrder(int magic)
{
   return (OrderSymbol() == Symbol() && OrderMagicNumber() == magic);
}

bool IsMagicOrLegacyModeOrder(int magic)
{
   if(OrderSymbol() != Symbol()) return false;
   int m = OrderMagicNumber();
   if(m == magic) return true;
   if(!InpManageLegacyMagic) return false;
   if(magic == NormalMagic() && m == LegacyNormalMagic()) return true;
   if(magic == AdvancedMagic() && m == LegacyAdvancedMagic()) return true;
   return false;
}

int OrderDirection()
{
   if(OrderType() == OP_BUY) return 1;
   if(OrderType() == OP_SELL) return -1;
   return 0;
}

double AtrValue()
{
   double atr = iATR(NULL, 0, InpAtrPeriod, 1);
   if(atr <= 0.0 || atr != atr || MathAbs(atr) > 1.0e100)
      atr = MarketInfo(Symbol(), MODE_POINT) * 1000.0;
   return atr;
}

double StopDistance()
{
   if(InpStopMode == STOP_NONE) return 0.0;
   double minStop = MathMax(MarketInfo(Symbol(), MODE_STOPLEVEL) * Point * 1.5, Point * 10.0);
   if(InpStopMode == STOP_FIXED_POINTS)
      return MathMax(Point * InpFixedSlPoints, minStop);
   return MathMax(AtrValue() * InpSlAtr, minStop);
}

double NormalTpDistance()
{
   if(InpStopMode == STOP_FIXED_POINTS && InpFixedTpPoints > 0)
      return MathMax(Point * InpFixedTpPoints, Point * 10.0);
   if(InpNormalTpAtr > 0.0)
      return MathMax(AtrValue() * InpNormalTpAtr, Point * 10.0);
   return 0.0;
}

bool SpreadOkForEntry()
{
   if(InpMaxSpreadPoints <= 0) return true;
   double spreadPoints = MarketInfo(Symbol(), MODE_SPREAD);
   if(spreadPoints <= InpMaxSpreadPoints) return true;
   if(InpDebugPrint)
      Print("TMA MACD EA entry blocked by spread spread=", DoubleToString(spreadPoints, 1), " max=", InpMaxSpreadPoints);
   SetBlock("spread blocked " + DoubleToString(spreadPoints, 1));
   return false;
}

string GvPrefix(int ticket)
{
   return g_prefix + Symbol() + "_" + IntegerToString(ticket) + "_";
}

void SetTicketStage(int ticket, int stage)
{
   GlobalVariableSet(GvPrefix(ticket) + "stage", stage);
}

int GetTicketStage(int ticket)
{
   string k = GvPrefix(ticket) + "stage";
   if(!GlobalVariableCheck(k)) return 0;
   return (int)GlobalVariableGet(k);
}

void SetTicketRisk(int ticket, double risk)
{
   GlobalVariableSet(GvPrefix(ticket) + "risk", risk);
}

double GetTicketRisk(int ticket)
{
   string k = GvPrefix(ticket) + "risk";
   if(!GlobalVariableCheck(k)) return StopDistance();
   double r = GlobalVariableGet(k);
   if(r <= 0.0 || r != r || MathAbs(r) > 1.0e100) return StopDistance();
   return r;
}

void DeleteTicketState(int ticket)
{
   GlobalVariableDel(GvPrefix(ticket) + "stage");
   GlobalVariableDel(GvPrefix(ticket) + "risk");
}

//------------------------------ PnL Guard -----------------------------//
double OpenPnl()
{
   double sum = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsOurOrder()) continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return sum;
}

double DailyClosedPnl()
{
   double sum = 0.0;
   datetime start = DayStart(TimeCurrent());
   int total = OrdersHistoryTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderCloseTime() < start) continue;
      if(!IsOurOrder()) continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return sum;
}

double DailyGuardPnl()
{
   double p = DailyClosedPnl();
   if(InpIncludeOpenPnlInDailyGuard)
      p += OpenPnl();
   return p;
}

void CloseAllOurOrders(string reason)
{
   RefreshRates();
   for(int pass = 0; pass < 3; pass++)
   {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!IsOurOrder()) continue;
         int ticket = OrderTicket();
         int type = OrderType();
         double lots = OrderLots();
         double price = (type == OP_BUY) ? Bid : Ask;
         bool ok = OrderClose(ticket, lots, price, InpSlippage, clrSilver);
         if(ok)
         {
            DeleteTicketState(ticket);
            if(InpDebugPrint) Print("TMA MACD EA closed ticket=", ticket, " reason=", reason);
         }
         else if(InpDebugPrint)
            Print("TMA MACD EA close failed ticket=", ticket, " err=", GetLastError(), " reason=", reason);
      }
      Sleep(100);
      RefreshRates();
   }
}

void CheckDailyGuard()
{
   datetime nowDay = DayStart(TimeCurrent());
   if(g_dayStart == 0 || nowDay != g_dayStart)
   {
      g_dayStart = nowDay;
      g_dailyHardStop = false;
   }
   if(!InpDailyGuardEnabled || g_dailyHardStop) return;

   double pnl = DailyGuardPnl();
   bool hitProfit = (InpDailyProfitTarget > 0.0 && pnl >= InpDailyProfitTarget);
   bool hitLoss = (InpDailyLossLimit > 0.0 && pnl <= -MathAbs(InpDailyLossLimit));
   if(hitProfit || hitLoss)
   {
      g_dailyHardStop = true;
      if(InpDebugPrint)
         Print("TMA MACD EA daily guard hit pnl=", DoubleToString(pnl, 2), " profitTarget=", DoubleToString(InpDailyProfitTarget, 2), " lossLimit=", DoubleToString(InpDailyLossLimit, 2));
      if(InpCloseAllOnDailyLimit)
         CloseAllOurOrders(hitProfit ? "daily_profit_target" : "daily_loss_limit");
   }
}

//------------------------------ Execution -----------------------------//
bool HasSameDirectionOrder(int magic, int dir)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsMagicOrLegacyModeOrder(magic)) continue;
      if(OrderDirection() == dir) return true;
   }
   return false;
}

bool HasOppositeDirectionOrder(int magic, int dir)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsMagicOrLegacyModeOrder(magic)) continue;
      if(OrderDirection() == -dir) return true;
   }
   return false;
}

bool IsModeDisarmed(int magic, int dir)
{
   if(!InpBlockReentryAfterFlatClose) return false;
   if(magic == NormalMagic()) return (g_normalDisarmedDir == dir);
   if(magic == AdvancedMagic()) return (g_advancedDisarmedDir == dir);
   return false;
}

void SetModeDisarmed(int magic, int dir)
{
   if(magic == NormalMagic()) g_normalDisarmedDir = dir;
   else if(magic == AdvancedMagic()) g_advancedDisarmedDir = dir;
}

void ClearModeDisarmed(int magic)
{
   if(magic == NormalMagic()) g_normalDisarmedDir = 0;
   else if(magic == AdvancedMagic()) g_advancedDisarmedDir = 0;
}

void ClearDisarmedForDirection(int dir)
{
   if(g_normalDisarmedDir == dir) g_normalDisarmedDir = 0;
   if(g_advancedDisarmedDir == dir) g_advancedDisarmedDir = 0;
}

void RefreshOrderPresence()
{
   g_normalHadBuy = HasSameDirectionOrder(NormalMagic(), 1);
   g_normalHadSell = HasSameDirectionOrder(NormalMagic(), -1);
   g_advancedHadBuy = HasSameDirectionOrder(AdvancedMagic(), 1);
   g_advancedHadSell = HasSameDirectionOrder(AdvancedMagic(), -1);
}

void MonitorExternalFlatCloses()
{
   if(!InpBlockReentryAfterFlatClose)
   {
      RefreshOrderPresence();
      return;
   }

   int dir = ReadDirection();
   bool normalBuy = HasSameDirectionOrder(NormalMagic(), 1);
   bool normalSell = HasSameDirectionOrder(NormalMagic(), -1);
   bool advancedBuy = HasSameDirectionOrder(AdvancedMagic(), 1);
   bool advancedSell = HasSameDirectionOrder(AdvancedMagic(), -1);

   if(dir == 0)
   {
      g_normalDisarmedDir = 0;
      g_advancedDisarmedDir = 0;
   }
   else
   {
      if(g_normalDisarmedDir != 0 && g_normalDisarmedDir != dir) g_normalDisarmedDir = 0;
      if(g_advancedDisarmedDir != 0 && g_advancedDisarmedDir != dir) g_advancedDisarmedDir = 0;

      if(g_normalHadBuy && !normalBuy && dir == 1)
      {
         g_normalDisarmedDir = 1;
         SetBlock("normal BUY reentry locked after flat close");
      }
      if(g_normalHadSell && !normalSell && dir == -1)
      {
         g_normalDisarmedDir = -1;
         SetBlock("normal SELL reentry locked after flat close");
      }
      if(g_advancedHadBuy && !advancedBuy && dir == 1)
      {
         g_advancedDisarmedDir = 1;
         SetBlock("advanced BUY reentry locked after flat close");
      }
      if(g_advancedHadSell && !advancedSell && dir == -1)
      {
         g_advancedDisarmedDir = -1;
         SetBlock("advanced SELL reentry locked after flat close");
      }
   }

   g_normalHadBuy = normalBuy;
   g_normalHadSell = normalSell;
   g_advancedHadBuy = advancedBuy;
   g_advancedHadSell = advancedSell;
}

void CloseOppositeModeOrders(int magic, int dir)
{
   if(!InpCloseOppositeOnSignal) return;
   RefreshRates();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsMagicOrLegacyModeOrder(magic)) continue;
      if(OrderDirection() != -dir) continue;
      int ticket = OrderTicket();
      double lots = OrderLots();
      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      bool ok = OrderClose(ticket, lots, price, InpSlippage, clrOrange);
      if(ok)
      {
         DeleteTicketState(ticket);
         SetAction("reverse closed #" + IntegerToString(ticket));
         if(InpDebugPrint) Print("TMA MACD EA reverse closed ticket=", ticket);
      }
      else if(InpDebugPrint)
      {
         SetBlock("reverse close failed #" + IntegerToString(ticket));
         Print("TMA MACD EA reverse close failed ticket=", ticket, " err=", GetLastError());
      }
   }
}

int OpenModeOrder(int dir, int magic, string mode)
{
   if(!InpTradingEnabled || g_runtimePaused || g_dailyHardStop) return -1;
   if(IsModeDisarmed(magic, dir))
   {
      SetBlock(mode + " " + DirText(dir) + " reentry locked until reverse/NONE");
      if(InpDebugPrint)
         Print("TMA MACD EA blocked same-regime reentry mode=", mode, " dir=", DirText(dir));
      return -1;
   }
   if(InpOneTradePerMode && HasSameDirectionOrder(magic, dir)) return -1;
   if(InpOneTradePerMode && HasOppositeDirectionOrder(magic, dir))
   {
      if(InpDebugPrint)
         Print("TMA MACD EA blocked open because opposite order still exists mode=", mode, " dir=", DirText(dir));
      SetBlock("opposite order still open " + mode);
      return -1;
   }
   if(!SpreadOkForEntry()) return -1;

   RefreshRates();
   double lots = NormalizeLots(g_runtimeLot);
   int type = (dir > 0) ? OP_BUY : OP_SELL;
   double price = (dir > 0) ? Ask : Bid;
   double risk = StopDistance();
   double tpDist = (mode == "normal") ? NormalTpDistance() : 0.0;
   double sl = 0.0;
   double tp = 0.0;

   if(risk > 0.0)
      sl = (dir > 0) ? price - risk : price + risk;
   if(tpDist > 0.0)
      tp = (dir > 0) ? price + tpDist : price - tpDist;

   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(sl > 0.0) sl = NormalizeDouble(sl, digits);
   if(tp > 0.0) tp = NormalizeDouble(tp, digits);
   price = NormalizeDouble(price, digits);

   string comment = InpOrderCommentPrefix + "_" + mode + "_" + DirText(dir);
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, price, InpSlippage, sl, tp, comment, magic, 0, (dir > 0 ? clrLime : clrTomato));
   if(ticket <= 0)
   {
      int firstErr = GetLastError();
      if(firstErr == 130)
      {
         ResetLastError();
         ticket = OrderSend(Symbol(), type, lots, price, InpSlippage, 0.0, 0.0, comment, magic, 0, (dir > 0 ? clrLime : clrTomato));
         if(ticket > 0 && (sl > 0.0 || tp > 0.0))
         {
            if(OrderSelect(ticket, SELECT_BY_TICKET))
            {
               bool modOk = OrderModify(ticket, OrderOpenPrice(), sl, tp, 0, clrGold);
               if(!modOk && InpDebugPrint)
                  Print("TMA MACD EA post-open SL/TP modify failed ticket=", ticket, " err=", GetLastError());
            }
         }
      }
   }
   if(ticket > 0)
   {
      SetTicketStage(ticket, 0);
      SetTicketRisk(ticket, risk);
      ClearModeDisarmed(magic);
      RefreshOrderPresence();
      SetAction("opened " + mode + " " + DirText(dir) + " #" + IntegerToString(ticket));
      SetBlock("-");
      if(InpDebugPrint)
         Print("TMA MACD EA opened ", mode, " ", DirText(dir), " ticket=", ticket, " lots=", DoubleToString(lots, 2), " risk=", DoubleToString(risk, Digits));
   }
   else if(InpDebugPrint)
   {
      SetBlock("open failed " + mode + " " + DirText(dir));
      Print("TMA MACD EA open failed mode=", mode, " dir=", DirText(dir), " err=", GetLastError());
   }
   return ticket;
}

void ExecuteSignal(int dir)
{
   if(dir == 0) return;
   if(!InpTradingEnabled || g_runtimePaused || g_dailyHardStop) return;

   ClearDisarmedForDirection(dir);

   if(g_runtimeNormal)
   {
      CloseOppositeModeOrders(NormalMagic(), dir);
      OpenModeOrder(dir, NormalMagic(), "normal");
   }
   if(g_runtimeAdvanced)
   {
      CloseOppositeModeOrders(AdvancedMagic(), dir);
      OpenModeOrder(dir, AdvancedMagic(), "advanced");
   }
   RefreshOrderPresence();
}

//-------------------------- Advanced Manager --------------------------//
double StageR(int stage)
{
   if(stage == 1) return InpAdvTp1R;
   if(stage == 2) return InpAdvTp2R;
   if(stage == 3) return InpAdvTp3R;
   if(stage == 4) return InpAdvTp4R;
   return InpAdvTp5R;
}

double StagePct(int stage)
{
   if(stage == 1) return InpAdvClosePct1;
   if(stage == 2) return InpAdvClosePct2;
   if(stage == 3) return InpAdvClosePct3;
   if(stage == 4) return InpAdvClosePct4;
   return InpAdvClosePct5;
}

bool MoveSlToBE(int ticket, int dir)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
   double open = OrderOpenPrice();
   double offset = MathAbs(InpBEOffsetPoints) * Point;
   double newSl = (dir > 0) ? open + offset : open - offset;
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   newSl = NormalizeDouble(newSl, digits);
   double oldSl = OrderStopLoss();
   if(oldSl > 0.0)
   {
      if(dir > 0 && oldSl >= newSl) return true;
      if(dir < 0 && oldSl <= newSl) return true;
   }
   bool ok = OrderModify(ticket, OrderOpenPrice(), newSl, OrderTakeProfit(), 0, clrGold);
   if(!ok && InpDebugPrint)
      Print("TMA MACD EA BE modify failed ticket=", ticket, " err=", GetLastError());
   return ok;
}

void ManageAdvancedOrders()
{
   RefreshRates();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsMagicOrLegacyModeOrder(AdvancedMagic())) continue;
      int ticket = OrderTicket();
      int dir = OrderDirection();
      if(dir == 0) continue;
      int stageDone = GetTicketStage(ticket);
      if(stageDone >= 5) continue;

      double risk = GetTicketRisk(ticket);
      if(risk <= 0.0) continue;
      double open = OrderOpenPrice();
      double px = (dir > 0) ? Bid : Ask;
      int nextStage = stageDone + 1;
      double target = (dir > 0) ? open + risk * StageR(nextStage) : open - risk * StageR(nextStage);
      bool hit = (dir > 0) ? (px >= target) : (px <= target);
      if(!hit) continue;

      double pct = MathMax(0.0, MathMin(100.0, StagePct(nextStage)));
      double closeLots = OrderLots();
      if(nextStage < 5)
         closeLots = NormalizeLots(OrderLots() * pct / 100.0);
      closeLots = MathMin(closeLots, OrderLots());

      double minLot = MarketInfo(Symbol(), MODE_MINLOT);
      if(OrderLots() - closeLots < minLot && nextStage < 5)
         closeLots = OrderLots();
      double closePrice = (dir > 0) ? Bid : Ask;
      bool ok = OrderClose(ticket, closeLots, closePrice, InpSlippage, clrDodgerBlue);
      if(ok)
      {
         if(closeLots >= OrderLots() - 0.0000001)
            DeleteTicketState(ticket);
         else
            SetTicketStage(ticket, nextStage);
         if(InpDebugPrint)
            Print("TMA MACD EA advanced TP", nextStage, " closed ticket=", ticket, " lots=", DoubleToString(closeLots, 2));
         if(nextStage == 1 && InpMoveSlToBEAfterTp1 && closeLots < OrderLots() - 0.0000001)
            MoveSlToBE(ticket, dir);
      }
      else if(InpDebugPrint)
         Print("TMA MACD EA advanced partial failed ticket=", ticket, " stage=", nextStage, " err=", GetLastError());
   }
}

//----------------------------- Signal FSM -----------------------------//
void PrimeStartupBaseline()
{
   g_startupBaselineChecked = true;
   if(InpSendInitialSignalOnStart) return;

   int shift = EffectiveSignalShift();
   int dir = ReadDirection();
   datetime barTime = iTime(NULL, 0, shift);
   if(dir == 0) return;

   g_confirmedDir = dir;
   g_lastSignalBar = barTime;
   bool syncNeeded = false;
   if(InpSyncExistingOrdersOnStart)
   {
      if(g_runtimeNormal && HasOppositeDirectionOrder(NormalMagic(), dir)) syncNeeded = true;
      if(g_runtimeAdvanced && HasOppositeDirectionOrder(AdvancedMagic(), dir)) syncNeeded = true;
   }
   if(InpDebugPrint)
      Print("TMA MACD EA startup primed baseline=", DirText(dir), syncNeeded ? " sync_required " : " ", "bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS));
      if(syncNeeded)
      {
         if(InpDebugPrint)
            Print("TMA MACD EA startup sync: existing opposite order found, executing current direction=", DirText(dir));
         SetAction("startup sync " + DirText(dir));
         g_lastExecutionAt = TimeCurrent();
         ExecuteSignal(dir);
      }
}

void ProcessSignal()
{
   int shift = EffectiveSignalShift();
   int dir = ReadDirection();
   datetime barTime = iTime(NULL, 0, shift);

   if(InpSignalMode == SIGNAL_CHART_CLOSED_BAR_ARROWS && g_pendingDir != 0 && g_pendingBarTime > 0)
   {
      int pendingDir = DirectionFromClosedBarArrowObjectAtTime(g_pendingBarTime, shift, "pending");
      if(pendingDir == g_pendingDir && (dir == 0 || dir == g_pendingDir))
      {
         dir = pendingDir;
         barTime = g_pendingBarTime;
      }
   }

   if(dir == 0)
   {
      if(g_pendingDir != 0)
      {
         if(InpDebugPrint)
            Print("TMA MACD EA pending cleared because signal disappeared pending=", DirText(g_pendingDir));
         SetBlock("pending cleared: signal disappeared");
         g_pendingDir = 0;
         g_pendingStartedAt = 0;
         g_pendingBarTime = 0;
      }
      return;
   }

   // Event mode should be one-shot per signal bar. State mode still benefits from it
   // because the EA only trades changes, not repeated same-direction states.
   if(barTime > 0 && barTime == g_lastSignalBar && dir == g_confirmedDir)
      return;

   if(dir == g_confirmedDir && g_pendingDir == 0)
      return;

   datetime now = TimeCurrent();
   if(g_pendingDir != dir)
   {
      if(InpBlockSameBarReverse && g_lastSignalBar > 0 && barTime == g_lastSignalBar && dir == -g_confirmedDir)
      {
         if(InpDebugPrint)
            Print("TMA MACD EA blocked same-bar reverse dir=", DirText(dir), " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS));
         SetBlock("same-bar reverse blocked " + DirText(dir));
         return;
      }
      if(InpMinSecondsBetweenSignals > 0 && g_lastExecutionAt > 0 && (now - g_lastExecutionAt) < InpMinSecondsBetweenSignals && dir == -g_confirmedDir)
      {
         if(InpDebugPrint)
            Print("TMA MACD EA blocked fast reverse dir=", DirText(dir), " elapsed=", (now - g_lastExecutionAt), " min=", InpMinSecondsBetweenSignals);
         SetBlock("fast reverse blocked " + DirText(dir));
         return;
      }
      g_pendingDir = dir;
      g_pendingStartedAt = now;
      g_pendingBarTime = barTime;
      SetAction("pending " + DirText(dir));
      if(InpDebugPrint)
         Print("TMA MACD EA pending started dir=", DirText(dir), " confirm_sec=", g_runtimeConfirmSeconds, " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS));
      if(g_runtimeConfirmSeconds > 0)
         return;
   }

   if(g_runtimeConfirmSeconds > 0 && (now - g_pendingStartedAt) < g_runtimeConfirmSeconds)
      return;

   g_confirmedDir = dir;
   g_pendingDir = 0;
   g_pendingStartedAt = 0;
   g_lastSignalBar = barTime;
   g_lastExecutionAt = now;
   SetAction("confirmed " + DirText(dir));
   SetBlock("-");
   if(InpDebugPrint)
      Print("TMA MACD EA confirmed dir=", DirText(dir), " bar=", TimeToString(barTime, TIME_DATE|TIME_SECONDS));
   ExecuteSignal(dir);
}

//------------------------------ Dashboard -----------------------------//
void ObjLabel(string name, int x, int y, string text, color c, int size = 9)
{
   string n = g_prefix + name;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, InpDashCorner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
}

void ObjPanel(string name, int x, int y, int w, int h, color bg)
{
   string n = g_prefix + name;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, InpDashCorner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrDimGray);
}

void ObjButton(string name, int x, int y, int w, int h, string text, color bg)
{
   string n = g_prefix + name;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, InpDashCorner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
}

void ObjEdit(string name, int x, int y, int w, int h, string text)
{
   string n = g_prefix + name;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, InpDashCorner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, n, OBJPROP_TEXT, text);
   }
}

string EditText(string name)
{
   string n = g_prefix + name;
   if(ObjectFind(0, n) < 0) return "";
   return ObjectGetString(0, n, OBJPROP_TEXT);
}

void SetEditText(string name, string text)
{
   string n = g_prefix + name;
   if(ObjectFind(0, n) >= 0)
      ObjectSetString(0, n, OBJPROP_TEXT, text);
}

string ModeName()
{
   if(InpSignalMode == SIGNAL_TREND_EVENTS) return "EVENT";
   if(InpSignalMode == SIGNAL_EVENTS_THEN_STATE) return "EVENT+STATE";
   if(InpSignalMode == SIGNAL_CHART_CLOSED_BAR_ARROWS) return "CLOSED_ARROW";
   return "STATE";
}

void DrawDashboard()
{
   if(!InpShowDashboard) return;
   datetime now = TimeCurrent();
   if(g_lastDashAt > 0 && now == g_lastDashAt) return;
   g_lastDashAt = now;

   int x = InpDashX;
   int y = InpDashY;
   double closed = DailyClosedPnl();
   double open = OpenPnl();
   double guard = DailyGuardPnl();
   color guardColor = guard >= 0.0 ? InpDashGood : InpDashBad;
   string status = g_dailyHardStop ? "DAILY HARD STOP" : (g_runtimePaused ? "PAUSED" : "RUNNING");
   color statusColor = g_dailyHardStop ? InpDashBad : (g_runtimePaused ? InpDashWarn : InpDashGood);

   ObjPanel("panel", x - 8, y - 8, 390, 272, InpDashBg);
   ObjLabel("title", x, y, "TMA MACD PROTRADER  " + Symbol() + " " + TfToString(Period()), InpDashWarn, 10);
   ObjLabel("status", x, y + 18, "Status: " + status + " | Signal: " + ModeName() + " shift=" + IntegerToString(EffectiveSignalShift()) + " bars=" + IntegerToString(g_runtimeStateConfirmBars) + " confirm=" + IntegerToString(g_runtimeConfirmSeconds) + "s", statusColor, 9);
   ObjLabel("pnl1", x, y + 36, "Daily closed: " + DoubleToString(closed, 2) + " | Open: " + DoubleToString(open, 2) + " | Guard: " + DoubleToString(guard, 2), guardColor, 9);
   ObjLabel("pnl2", x, y + 54, "Limits profit=" + DoubleToString(InpDailyProfitTarget, 2) + " loss=" + DoubleToString(InpDailyLossLimit, 2), InpDashText, 9);
   ObjLabel("sig", x, y + 72, "Confirmed=" + DirText(g_confirmedDir) + " Pending=" + DirText(g_pendingDir) + " since=" + (g_pendingStartedAt > 0 ? TimeToString(g_pendingStartedAt, TIME_SECONDS) : "-"), InpDashText, 9);
   ObjLabel("live1", x, y + 90, "Read=" + DirText(g_lastReadDir) + " at=" + ShortTime(g_lastReadAt) + " bar=" + ShortDateTime(g_lastReadBar), InpDashText, 8);
   ObjLabel("live2", x, y + 106, "Buffers buy=" + DoubleToString(g_lastBuyBuffer, 5) + " sell=" + DoubleToString(g_lastSellBuffer, 5) + " trend=" + DoubleToString(g_lastTrendBuffer, 0), InpDashText, 8);
   ObjLabel("lock", x, y + 122, "Reentry locks normal=" + DirText(g_normalDisarmedDir) + " advanced=" + DirText(g_advancedDisarmedDir), (g_normalDisarmedDir != 0 || g_advancedDisarmedDir != 0) ? InpDashWarn : InpDashText, 8);
   ObjLabel("live3", x, y + 138, "Action: " + g_lastAction, InpDashGood, 8);
   ObjLabel("live4", x, y + 154, "Block: " + g_lastBlock, g_lastBlock == "-" ? InpDashText : InpDashBad, 8);
   ObjLabel("cfg1", x, y + 174, "Pending sec", InpDashText, 8);
   ObjEdit("edit_confirm_sec", x + 82, y + 170, 52, 18, IntegerToString(g_runtimeConfirmSeconds));
   ObjLabel("cfg2", x + 145, y + 174, "Bars", InpDashText, 8);
   ObjEdit("edit_confirm_bars", x + 182, y + 170, 38, 18, IntegerToString(g_runtimeStateConfirmBars));
   ObjButton("btn_save_cfg", x + 230, y + 170, 74, 18, "SAVE CFG", clrDarkSlateGray);

   ObjLabel("cfg3", x, y + 194, "Lot", InpDashText, 8);
   ObjEdit("edit_lot", x + 36, y + 190, 58, 18, DoubleToString(g_runtimeLot, 2));
   ObjLabel("cfg4", x + 104, y + 194, "applies to next opened trades", InpDashText, 8);

   ObjButton("btn_pause", x, y + 230, 78, 20, g_runtimePaused ? "RESUME" : "PAUSE", g_runtimePaused ? clrDarkGreen : clrFireBrick);
   ObjButton("btn_normal", x + 84, y + 230, 86, 20, g_runtimeNormal ? "NORMAL ON" : "NORMAL OFF", g_runtimeNormal ? clrDarkGreen : clrDimGray);
   ObjButton("btn_adv", x + 176, y + 230, 86, 20, g_runtimeAdvanced ? "ADV ON" : "ADV OFF", g_runtimeAdvanced ? clrDarkGreen : clrDimGray);
   ObjButton("btn_close", x + 268, y + 230, 76, 20, "CLOSE ALL", clrMaroon);
}

void DeleteDashboard()
{
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
   {
      string name = ObjectName(i);
      if(StringSubstr(name, 0, StringLen(g_prefix)) == g_prefix)
         ObjectDelete(0, name);
   }
}

//------------------------------- Events -------------------------------//
int OnInit()
{
   g_runtimeNormal = InpEnableNormalMode;
   g_runtimeAdvanced = InpEnableAdvancedMode;
   LoadRuntimeSettings();
   g_dayStart = DayStart(TimeCurrent());
   EventSetTimer(MathMax(1, InpPollSeconds));
   if(InpDebugPrint)
   {
      Print("TMA MACD ProTrader initialized indicator=", InpIndicatorName, " mode=", ModeName(), " shift=", InpSignalShift, " stateConfirmBars=", g_runtimeStateConfirmBars, " confirm=", g_runtimeConfirmSeconds);
      if(InpRequireClosedBar && InpSignalShift < 1)
         Print("TMA MACD EA safety: InpSignalShift=0 requested, but InpRequireClosedBar=true so effective shift=1");
      if(InpSignalMode == SIGNAL_CHART_CLOSED_BAR_ARROWS)
      {
         Print("TMA MACD EA closed-arrow mode: trades only OBJ_ARROW objects on a closed candle. prefix=", ArrowObjectPrefix());
         if(InpShowArrows == 0)
            Print("TMA MACD EA closed-arrow warning: InpShowArrows=0, so no chart arrow objects can be detected.");
      }
   }
   PrimeStartupBaseline();
   RefreshOrderPresence();
   DrawDashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
}

void OnTick()
{
   CheckDailyGuard();
   ManageAdvancedOrders();
   MonitorExternalFlatCloses();
   DrawDashboard();
}

void OnTimer()
{
   CheckDailyGuard();
   ManageAdvancedOrders();
   MonitorExternalFlatCloses();
   ProcessSignal();
   DrawDashboard();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == g_prefix + "btn_pause")
      g_runtimePaused = !g_runtimePaused;
   else if(sparam == g_prefix + "btn_normal")
      g_runtimeNormal = !g_runtimeNormal;
   else if(sparam == g_prefix + "btn_adv")
      g_runtimeAdvanced = !g_runtimeAdvanced;
   else if(sparam == g_prefix + "btn_close")
      CloseAllOurOrders("dashboard_close_all");
   else if(sparam == g_prefix + "btn_save_cfg")
   {
      int newConfirm = ClampInt((int)StringToInteger(EditText("edit_confirm_sec")), 0, 86400);
      int newBars = ClampInt((int)StringToInteger(EditText("edit_confirm_bars")), 1, 100);
      double newLot = NormalizeLots(ParseEditDouble("edit_lot", g_runtimeLot));
      g_runtimeConfirmSeconds = newConfirm;
      g_runtimeStateConfirmBars = newBars;
      g_runtimeLot = newLot;
      SaveRuntimeSettings();
      SetEditText("edit_confirm_sec", IntegerToString(g_runtimeConfirmSeconds));
      SetEditText("edit_confirm_bars", IntegerToString(g_runtimeStateConfirmBars));
      SetEditText("edit_lot", DoubleToString(g_runtimeLot, 2));
      SetAction("config saved sec=" + IntegerToString(g_runtimeConfirmSeconds) + " bars=" + IntegerToString(g_runtimeStateConfirmBars) + " lot=" + DoubleToString(g_runtimeLot, 2));
      SetBlock("-");
      if(InpDebugPrint)
         Print("TMA MACD EA config saved confirm_sec=", g_runtimeConfirmSeconds, " state_confirm_bars=", g_runtimeStateConfirmBars, " lot=", DoubleToString(g_runtimeLot, 2));
   }
   g_lastDashAt = 0;
   DrawDashboard();
}
