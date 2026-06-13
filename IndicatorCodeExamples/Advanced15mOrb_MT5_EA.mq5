//+------------------------------------------------------------------+
//| Advanced 15 Minute ORB MT5 EA                                    |
//| ORB + bias/confluence + FVG/displacement filters.                 |
//| Session clock is NY time mapped to broker server time via GMT     |
//| offset input. Default broker offset is GMT+0.                     |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

input bool            InpEaEnabled = true;
input long            InpMagic = 15101502;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M1;
input double          InpBrokerGmtOffsetHours = 0.0;
input bool            InpAutoNewYorkDst = true;
input string          InpOrbStartNy = "09:30";
input string          InpOrbEndNy = "09:45";
input string          InpTradeStartNy = "09:45";
input string          InpTradeEndNy = "10:30";
input string          InpAsianStartNy = "20:00";
input string          InpAsianEndNy = "02:00";
input string          InpLondonStartNy = "03:00";
input string          InpLondonEndNy = "12:00";
input bool            InpUseClosedBarBreakout = true;
input int             InpBiasMinStrength = 30;
input int             InpBiasMaxStrength = 100;
input double          InpMinOrbRangeDaily = 0.03;
input double          InpMaxOrbRangeDaily = 0.70;
input int             InpDailyAtrPeriod = 5;
input double          InpMinBreakoutDistanceAtr = 0.0;
input double          InpMinBreakoutBodyAtr = 0.0;
input bool            InpRequireFvg = true;
input double          InpMinFvgGapPoints = 0.0;
input double          InpMinFvgSizeAtr = 0.0;
input int             InpFvgLookback = 20;
input int             InpFvgScanWindow = 10;
input bool            InpRequireUnfilledFvg = true;
input int             InpDisplacementLookback = 20;
input int             InpDisplacementPercentile = 80;
input double          InpMaxOpposingWickRatio = 0.32;
input int             InpFvgOptionalBiasThreshold = 70;
input double          InpFvgOptionalSlBufferAtr = 0.15;
input double          InpRrTightSlTarget = 2.0;
input double          InpRrWideSlTarget = 1.5;
input double          InpMinRrTarget = 1.5;
input double          InpRrTightSlThreshold = 30.0;
input int             InpBiasStrongThreshold = 70;
input double          InpRrBiasBonus = 0.0;
input double          InpMaxSpreadToSlRatio = 0.30;
input bool            InpOneTradePerNyDay = true;
input bool            InpUseAutoRiskLot = true;
input double          InpRiskPerTradePct = 1.0;
input double          InpFixedLot = 0.10;
input double          InpMaxLot = 0.0;          // 0 = broker maximum only
input int             InpDeviationPoints = 30;
input int             InpMaxSpreadPoints = 0;   // 0 = off
input bool            InpDrawOrbLevels = true;
input bool            InpAuditCsv = true;
input bool            InpLogOnInit = true;

CTrade trade;

string   PREFIX = "ADV_ORB15_MT5_";
int      g_nyDayKey = 0;
bool     g_orbReady = false;
bool     g_contextReady = false;
bool     g_contextBlocked = false;
bool     g_tradeTaken = false;
double   g_orbHigh = 0.0;
double   g_orbLow = 0.0;
double   g_asianHigh = 0.0;
double   g_asianLow = 0.0;
double   g_londonHigh = 0.0;
double   g_londonLow = 0.0;
double   g_prevDayHigh = 0.0;
double   g_prevDayLow = 0.0;
double   g_dailyAtr = 0.0;
string   g_bias = "neutral";
int      g_biasStrength = 0;
datetime g_orbStartServer = 0;
datetime g_orbEndServer = 0;
datetime g_tradeStartServer = 0;
datetime g_tradeEndServer = 0;
datetime g_asianStartServer = 0;
datetime g_asianEndServer = 0;
datetime g_londonStartServer = 0;
datetime g_londonEndServer = 0;
datetime g_prevDayStartServer = 0;
datetime g_prevDayEndServer = 0;
datetime g_lastSignalBarTime = 0;

int ParseClockMinutes(string value, int fallback)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   int p = StringFind(value, ":");
   if(p < 0)
      return fallback;
   int h = (int)StringToInteger(StringSubstr(value, 0, p));
   int m = (int)StringToInteger(StringSubstr(value, p + 1));
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return fallback;
   return h * 60 + m;
}

datetime MakeDateTime(const int year, const int mon, const int day, const int hour, const int minute, const int second = 0)
{
   MqlDateTime st;
   ZeroMemory(st);
   st.year = year;
   st.mon = mon;
   st.day = day;
   st.hour = hour;
   st.min = minute;
   st.sec = second;
   return StructToTime(st);
}

int DayOfWeekForDate(const int year, const int mon, const int day)
{
   MqlDateTime st;
   TimeToStruct(MakeDateTime(year, mon, day, 12, 0, 0), st);
   return st.day_of_week;
}

int NthSunday(const int year, const int mon, const int nth)
{
   int firstDow = DayOfWeekForDate(year, mon, 1);
   int firstSunday = 1 + ((7 - firstDow) % 7);
   return firstSunday + (nth - 1) * 7;
}

bool IsNewYorkDstDate(const int year, const int mon, const int day)
{
   if(!InpAutoNewYorkDst)
      return true;
   if(mon < 3 || mon > 11)
      return false;
   if(mon > 3 && mon < 11)
      return true;
   if(mon == 3)
      return day >= NthSunday(year, 3, 2);
   if(mon == 11)
      return day < NthSunday(year, 11, 1);
   return false;
}

int NyUtcOffsetSecondsForDate(const int year, const int mon, const int day)
{
   return IsNewYorkDstDate(year, mon, day) ? -4 * 3600 : -5 * 3600;
}

datetime NyLocalToServer(const int year, const int mon, const int day, const int minutesOfDay)
{
   int hour = minutesOfDay / 60;
   int minute = minutesOfDay % 60;
   datetime nyLocal = MakeDateTime(year, mon, day, hour, minute, 0);
   datetime utc = nyLocal - NyUtcOffsetSecondsForDate(year, mon, day);
   return utc + (int)MathRound(InpBrokerGmtOffsetHours * 3600.0);
}

void ShiftYmd(const int year, const int mon, const int day, const int deltaDays, int &outYear, int &outMon, int &outDay)
{
   datetime t = MakeDateTime(year, mon, day, 12, 0, 0) + deltaDays * 86400;
   MqlDateTime st;
   TimeToStruct(t, st);
   outYear = st.year;
   outMon = st.mon;
   outDay = st.day;
}

datetime NyLocalToServerShifted(const int year, const int mon, const int day, const int deltaDays, const int minutesOfDay)
{
   int y, m, d;
   ShiftYmd(year, mon, day, deltaDays, y, m, d);
   return NyLocalToServer(y, m, d, minutesOfDay);
}

int CurrentNyDayKey(int &year, int &mon, int &day)
{
   datetime utcNow = TimeCurrent() - (int)MathRound(InpBrokerGmtOffsetHours * 3600.0);
   MqlDateTime utcSt;
   TimeToStruct(utcNow, utcSt);
   int offset = NyUtcOffsetSecondsForDate(utcSt.year, utcSt.mon, utcSt.day);
   datetime nyNow = utcNow + offset;
   MqlDateTime nySt;
   TimeToStruct(nyNow, nySt);
   year = nySt.year;
   mon = nySt.mon;
   day = nySt.day;
   return year * 10000 + mon * 100 + day;
}

string FmtTime(datetime t)
{
   if(t <= 0)
      return "-";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

double NormalizeVolume(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0.0)
      minLot = 0.01;
   if(maxLot <= 0.0)
      maxLot = 100.0;
   if(InpMaxLot > 0.0)
      maxLot = MathMin(maxLot, InpMaxLot);
   if(step <= 0.0)
      step = minLot;
   volume = MathMax(minLot, MathMin(maxLot, volume));
   volume = MathFloor(volume / step + 0.0000001) * step;
   return NormalizeDouble(MathMax(minLot, volume), 2);
}

double ValuePerPriceUnitPerLot()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;
   return tickValue / tickSize;
}

double CalculateLot(double entry, double sl)
{
   if(!InpUseAutoRiskLot)
      return NormalizeVolume(InpFixedLot);
   double riskDistance = MathAbs(entry - sl);
   double valuePerUnit = ValuePerPriceUnitPerLot();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * MathMax(0.01, InpRiskPerTradePct) / 100.0;
   if(riskDistance <= 0.0 || valuePerUnit <= 0.0 || riskMoney <= 0.0)
      return NormalizeVolume(InpFixedLot);
   return NormalizeVolume(riskMoney / (riskDistance * valuePerUnit));
}

int CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0;
   return (int)MathRound((tick.ask - tick.bid) / point);
}

bool SpreadAllowed()
{
   if(InpMaxSpreadPoints <= 0)
      return true;
   return CurrentSpreadPoints() <= InpMaxSpreadPoints;
}

string AuditFileName()
{
   int y, m, d;
   int key = CurrentNyDayKey(y, m, d);
   return StringFormat("Advanced15mOrb_MT5_Audit_%d.csv", key);
}

void Audit(string eventName, string direction, double lot, double entry, double sl, double tp, string detail)
{
   if(!InpAuditCsv)
      return;
   string fileName = AuditFileName();
   int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
   {
      Print("Advanced15mOrb audit open failed file=", fileName, " err=", GetLastError());
      return;
   }
   if(FileSize(handle) == 0)
      FileWrite(handle, "server_time", "gmt_time", "symbol", "tf", "event", "direction", "lot", "entry", "sl", "tp", "orb_high", "orb_low", "bias", "bias_strength", "daily_atr", "spread_pts", "detail");
   FileSeek(handle, 0, SEEK_END);
   datetime gmt = TimeGMT();
   FileWrite(handle,
             FmtTime(TimeCurrent()),
             FmtTime(gmt),
             _Symbol,
             EnumToString(InpSignalTimeframe),
             eventName,
             direction,
             DoubleToString(lot, 2),
             DoubleToString(entry, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(g_orbHigh, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             DoubleToString(g_orbLow, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             g_bias,
             IntegerToString(g_biasStrength),
             DoubleToString(g_dailyAtr, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
             IntegerToString(CurrentSpreadPoints()),
             detail);
   FileClose(handle);
}

bool RangeHighLow(datetime startServer, datetime endServer, double &hi, double &lo, int &used)
{
   hi = -DBL_MAX;
   lo = DBL_MAX;
   used = 0;
   if(endServer <= startServer)
      return false;
   MqlRates rates[];
   int copied = CopyRates(_Symbol, InpSignalTimeframe, startServer, endServer, rates);
   if(copied <= 0)
      return false;
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < startServer || rates[i].time >= endServer)
         continue;
      hi = MathMax(hi, rates[i].high);
      lo = MathMin(lo, rates[i].low);
      used++;
   }
   return used > 0 && hi > lo && hi != -DBL_MAX && lo != DBL_MAX;
}

double CalculateDailyAtr(int period)
{
   int p = MathMax(2, period);
   MqlRates d1[];
   int copied = CopyRates(_Symbol, PERIOD_D1, 1, p + 2, d1);
   if(copied < p)
      return 0.0;
   ArraySetAsSeries(d1, true);
   double sum = 0.0;
   int used = 0;
   for(int i = 0; i < copied - 1 && used < p; i++)
   {
      double prevClose = d1[i + 1].close;
      double tr = MathMax(d1[i].high - d1[i].low,
                  MathMax(MathAbs(d1[i].high - prevClose), MathAbs(d1[i].low - prevClose)));
      if(tr > 0.0)
      {
         sum += tr;
         used++;
      }
   }
   return used > 0 ? sum / used : 0.0;
}

void CalculateBias(double currentPrice)
{
   int bullish = 0;
   int bearish = 0;
   double atr = g_dailyAtr > 0.0 ? g_dailyAtr : MathMax(g_orbHigh - g_orbLow, SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100.0);

   if(g_orbHigh > 0.0 && g_orbLow > 0.0)
   {
      if(currentPrice > g_orbHigh)
         bullish += MathMin(30, (int)(15 + ((currentPrice - g_orbHigh) / atr) * 15.0));
      else if(currentPrice < g_orbLow)
         bearish += MathMin(30, (int)(15 + ((g_orbLow - currentPrice) / atr) * 15.0));
   }
   if(g_asianHigh > 0.0 && g_asianLow > 0.0)
   {
      if(currentPrice > g_asianHigh)
         bullish += MathMin(25, (int)(12 + ((currentPrice - g_asianHigh) / atr) * 13.0));
      else if(currentPrice < g_asianLow)
         bearish += MathMin(25, (int)(12 + ((g_asianLow - currentPrice) / atr) * 13.0));
   }
   if(g_prevDayHigh > 0.0 && g_prevDayLow > 0.0)
   {
      if(currentPrice > g_prevDayHigh)
         bullish += MathMin(25, (int)(12 + ((currentPrice - g_prevDayHigh) / atr) * 13.0));
      else if(currentPrice < g_prevDayLow)
         bearish += MathMin(25, (int)(12 + ((g_prevDayLow - currentPrice) / atr) * 13.0));
   }
   if(g_londonHigh > 0.0 && g_londonLow > 0.0)
   {
      double mid = (g_londonHigh + g_londonLow) * 0.5;
      if(currentPrice > g_londonHigh)
         bullish += 15;
      else if(currentPrice > mid)
         bullish += 8;
      else if(currentPrice < g_londonLow)
         bearish += 15;
      else if(currentPrice < mid)
         bearish += 8;
   }

   if(bullish > bearish)
   {
      g_bias = "bullish";
      g_biasStrength = MathMin(100, bullish);
   }
   else if(bearish > bullish)
   {
      g_bias = "bearish";
      g_biasStrength = MathMin(100, bearish);
   }
   else
   {
      g_bias = "neutral";
      g_biasStrength = 0;
   }
}

double BodyAtShift(int shift)
{
   return MathAbs(iClose(_Symbol, InpSignalTimeframe, shift) - iOpen(_Symbol, InpSignalTimeframe, shift));
}

double PercentileBodyThreshold(int startShift, int lookback, int percentile)
{
   int n = MathMax(3, lookback);
   double bodies[];
   ArrayResize(bodies, 0);
   for(int sh = startShift; sh < startShift + n && sh < Bars(_Symbol, InpSignalTimeframe); sh++)
   {
      double b = BodyAtShift(sh);
      if(b <= 0.0)
         continue;
      int sz = ArraySize(bodies);
      ArrayResize(bodies, sz + 1);
      bodies[sz] = b;
   }
   int count = ArraySize(bodies);
   if(count <= 0)
      return 0.0;
   ArraySort(bodies);
   int idx = (int)MathFloor((MathMax(0, MathMin(100, percentile)) / 100.0) * (count - 1));
   return bodies[idx];
}

bool HasDisplacement(int candleShift, string direction)
{
   if(candleShift < 0)
      return false;
   int lookback = MathMax(5, InpDisplacementLookback);
   if(Bars(_Symbol, InpSignalTimeframe) < candleShift + lookback + 5)
      return false;
   double threshold = PercentileBodyThreshold(candleShift + 3, lookback, InpDisplacementPercentile);
   if(threshold <= 0.0)
      return false;
   double open = iOpen(_Symbol, InpSignalTimeframe, candleShift);
   double close = iClose(_Symbol, InpSignalTimeframe, candleShift);
   double high = iHigh(_Symbol, InpSignalTimeframe, candleShift);
   double low = iLow(_Symbol, InpSignalTimeframe, candleShift);
   double body = 0.0;
   double opposingWick = 0.0;
   if(direction == "BUY")
   {
      body = close - open;
      if(body <= 0.0)
         return false;
      opposingWick = high - close;
   }
   else
   {
      body = open - close;
      if(body <= 0.0)
         return false;
      opposingWick = close - low;
   }
   return body >= threshold && opposingWick < body * MathMax(0.0, InpMaxOpposingWickRatio);
}

bool FindFreshFvg(string direction, double &top, double &bottom, double &size, datetime &fvgTime)
{
   top = 0.0;
   bottom = 0.0;
   size = 0.0;
   fvgTime = 0;
   int scan = MathMin(MathMax(3, InpFvgScanWindow), MathMax(3, InpFvgLookback));
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minGap = MathMax(0.0, InpMinFvgGapPoints) * point;
   int bars = Bars(_Symbol, InpSignalTimeframe);
   for(int offset = 0; offset < scan; offset++)
   {
      int c3 = 1 + offset;
      int c2 = c3 + 1;
      int c1 = c3 + 2;
      if(c1 + InpDisplacementLookback + 3 >= bars)
         break;
      double c1High = iHigh(_Symbol, InpSignalTimeframe, c1);
      double c1Low = iLow(_Symbol, InpSignalTimeframe, c1);
      double c3High = iHigh(_Symbol, InpSignalTimeframe, c3);
      double c3Low = iLow(_Symbol, InpSignalTimeframe, c3);
      if(direction == "BUY")
      {
         double gap = c3Low - c1High;
         if(gap <= minGap || !HasDisplacement(c2, direction))
            continue;
         if(InpRequireUnfilledFvg)
         {
            bool filled = false;
            for(int sh = 1; sh < c3; sh++)
            {
               if(iLow(_Symbol, InpSignalTimeframe, sh) < c1High)
               {
                  filled = true;
                  break;
               }
            }
            if(filled)
               continue;
         }
         top = c3Low;
         bottom = c1High;
         size = gap;
         fvgTime = iTime(_Symbol, InpSignalTimeframe, c2);
         return true;
      }
      else
      {
         double gap = c1Low - c3High;
         if(gap <= minGap || !HasDisplacement(c2, direction))
            continue;
         if(InpRequireUnfilledFvg)
         {
            bool filled = false;
            for(int sh = 1; sh < c3; sh++)
            {
               if(iHigh(_Symbol, InpSignalTimeframe, sh) > c1Low)
               {
                  filled = true;
                  break;
               }
            }
            if(filled)
               continue;
         }
         top = c1Low;
         bottom = c3High;
         size = gap;
         fvgTime = iTime(_Symbol, InpSignalTimeframe, c2);
         return true;
      }
   }
   return false;
}

double PlanRr(double slDistance)
{
   double rr = slDistance < MathMax(0.0, InpRrTightSlThreshold) ? InpRrTightSlTarget : InpRrWideSlTarget;
   if(g_biasStrength >= InpBiasStrongThreshold)
      rr += InpRrBiasBonus;
   return MathMax(InpMinRrTarget, rr);
}

bool SpreadEfficiencyAllowed(double slDistance)
{
   if(InpMaxSpreadToSlRatio <= 0.0 || slDistance <= 0.0)
      return true;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return true;
   double spreadPrice = MathMax(0.0, tick.ask - tick.bid);
   return (spreadPrice / slDistance) <= InpMaxSpreadToSlRatio;
}

bool OwnPositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

void DeleteLevelObjects()
{
   ObjectDelete(0, PREFIX + "ORB_HIGH");
   ObjectDelete(0, PREFIX + "ORB_LOW");
   ObjectDelete(0, PREFIX + "ORB_TXT");
}

void DrawLevels()
{
   if(!InpDrawOrbLevels || !g_orbReady)
      return;
   if(ObjectFind(0, PREFIX + "ORB_HIGH") < 0)
      ObjectCreate(0, PREFIX + "ORB_HIGH", OBJ_HLINE, 0, 0, g_orbHigh);
   ObjectSetDouble(0, PREFIX + "ORB_HIGH", OBJPROP_PRICE, NormalizePrice(g_orbHigh));
   ObjectSetInteger(0, PREFIX + "ORB_HIGH", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, PREFIX + "ORB_HIGH", OBJPROP_WIDTH, 2);

   if(ObjectFind(0, PREFIX + "ORB_LOW") < 0)
      ObjectCreate(0, PREFIX + "ORB_LOW", OBJ_HLINE, 0, 0, g_orbLow);
   ObjectSetDouble(0, PREFIX + "ORB_LOW", OBJPROP_PRICE, NormalizePrice(g_orbLow));
   ObjectSetInteger(0, PREFIX + "ORB_LOW", OBJPROP_COLOR, clrTomato);
   ObjectSetInteger(0, PREFIX + "ORB_LOW", OBJPROP_WIDTH, 2);

   datetime labelTime = TimeCurrent() + PeriodSeconds(InpSignalTimeframe) * 8;
   double labelPrice = (g_orbHigh + g_orbLow) * 0.5;
   if(ObjectFind(0, PREFIX + "ORB_TXT") < 0)
      ObjectCreate(0, PREFIX + "ORB_TXT", OBJ_TEXT, 0, labelTime, labelPrice);
   else
      ObjectMove(0, PREFIX + "ORB_TXT", 0, labelTime, labelPrice);
   ObjectSetString(0, PREFIX + "ORB_TXT", OBJPROP_TEXT, "Advanced 15m ORB NY " + InpOrbStartNy + "-" + InpOrbEndNy + " H=" + DoubleToString(g_orbHigh, _Digits) + " L=" + DoubleToString(g_orbLow, _Digits) + " bias=" + g_bias + " " + IntegerToString(g_biasStrength));
   ObjectSetInteger(0, PREFIX + "ORB_TXT", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PREFIX + "ORB_TXT", OBJPROP_FONTSIZE, 8);
}

void ResetForNewNyDay()
{
   int y, m, d;
   int key = CurrentNyDayKey(y, m, d);
   if(key == g_nyDayKey)
      return;
   g_nyDayKey = key;
   g_orbReady = false;
   g_contextReady = false;
   g_contextBlocked = false;
   g_tradeTaken = false;
   g_orbHigh = 0.0;
   g_orbLow = 0.0;
   g_asianHigh = 0.0;
   g_asianLow = 0.0;
   g_londonHigh = 0.0;
   g_londonLow = 0.0;
   g_prevDayHigh = 0.0;
   g_prevDayLow = 0.0;
   g_dailyAtr = 0.0;
   g_bias = "neutral";
   g_biasStrength = 0;
   g_lastSignalBarTime = 0;
   int startMin = ParseClockMinutes(InpOrbStartNy, 9 * 60 + 30);
   int endMin = ParseClockMinutes(InpOrbEndNy, 9 * 60 + 45);
   int tradeStartMin = ParseClockMinutes(InpTradeStartNy, endMin);
   int tradeEndMin = ParseClockMinutes(InpTradeEndNy, 16 * 60);
   int asianStartMin = ParseClockMinutes(InpAsianStartNy, 20 * 60);
   int asianEndMin = ParseClockMinutes(InpAsianEndNy, 2 * 60);
   int londonStartMin = ParseClockMinutes(InpLondonStartNy, 3 * 60);
   int londonEndMin = ParseClockMinutes(InpLondonEndNy, 12 * 60);
   g_orbStartServer = NyLocalToServer(y, m, d, startMin);
   g_orbEndServer = NyLocalToServer(y, m, d, endMin);
   g_tradeStartServer = NyLocalToServer(y, m, d, tradeStartMin);
   g_tradeEndServer = NyLocalToServer(y, m, d, tradeEndMin);
   g_asianStartServer = NyLocalToServerShifted(y, m, d, asianStartMin > asianEndMin ? -1 : 0, asianStartMin);
   g_asianEndServer = NyLocalToServer(y, m, d, asianEndMin);
   g_londonStartServer = NyLocalToServer(y, m, d, londonStartMin);
   g_londonEndServer = NyLocalToServer(y, m, d, londonEndMin);
   g_prevDayStartServer = NyLocalToServerShifted(y, m, d, -1, 0);
   g_prevDayEndServer = NyLocalToServer(y, m, d, 0);
   DeleteLevelObjects();
   Audit("new_ny_day", "", 0, 0, 0, 0,
         "ny_day=" + IntegerToString(g_nyDayKey)
         + " orb_start_server=" + FmtTime(g_orbStartServer)
         + " orb_end_server=" + FmtTime(g_orbEndServer)
         + " trade_start_server=" + FmtTime(g_tradeStartServer)
         + " trade_end_server=" + FmtTime(g_tradeEndServer)
         + " broker_gmt_offset_h=" + DoubleToString(InpBrokerGmtOffsetHours, 2));
}

bool BuildContext()
{
   if(g_contextReady)
      return true;
   if(g_contextBlocked)
      return false;
   if(TimeCurrent() < g_orbEndServer)
      return false;

   double hi, lo;
   int used = 0;
   if(!RangeHighLow(g_orbStartServer, g_orbEndServer, hi, lo, used))
   {
      Audit("orb_build_failed", "", 0, 0, 0, 0, "invalid_or_empty_orb_range err=" + IntegerToString(GetLastError()));
      return false;
   }
   g_orbHigh = NormalizePrice(hi);
   g_orbLow = NormalizePrice(lo);
   g_orbReady = true;

   int asianUsed = 0;
   RangeHighLow(g_asianStartServer, g_asianEndServer, g_asianHigh, g_asianLow, asianUsed);
   int londonUsed = 0;
   RangeHighLow(g_londonStartServer, g_londonEndServer, g_londonHigh, g_londonLow, londonUsed);
   int pdUsed = 0;
   RangeHighLow(g_prevDayStartServer, g_prevDayEndServer, g_prevDayHigh, g_prevDayLow, pdUsed);
   g_dailyAtr = CalculateDailyAtr(InpDailyAtrPeriod);
   MqlTick tick;
   double current = 0.0;
   if(SymbolInfoTick(_Symbol, tick))
      current = (tick.bid + tick.ask) * 0.5;
   if(current <= 0.0)
      current = iClose(_Symbol, InpSignalTimeframe, 1);
   CalculateBias(current);

   double orbRange = MathAbs(g_orbHigh - g_orbLow);
   double atr = g_dailyAtr > 0.0 ? g_dailyAtr : orbRange;
   double ratio = atr > 0.0 ? orbRange / atr : 0.0;
   if(atr > 0.0 && (ratio < InpMinOrbRangeDaily || ratio > InpMaxOrbRangeDaily))
   {
      Audit("orb_quality_blocked", "", 0, 0, 0, 0,
            "orb_range=" + DoubleToString(orbRange, _Digits)
            + " daily_atr=" + DoubleToString(atr, _Digits)
            + " ratio=" + DoubleToString(ratio, 4)
            + " min=" + DoubleToString(InpMinOrbRangeDaily, 4)
            + " max=" + DoubleToString(InpMaxOrbRangeDaily, 4));
      g_contextReady = false;
      g_contextBlocked = true;
      DrawLevels();
      return false;
   }

   g_contextReady = true;
   Audit("context_ready", "", 0, 0, 0, 0,
         "orb_bars=" + IntegerToString(used)
         + " asian_bars=" + IntegerToString(asianUsed)
         + " london_bars=" + IntegerToString(londonUsed)
         + " pd_bars=" + IntegerToString(pdUsed)
         + " orb_range=" + DoubleToString(orbRange, _Digits)
         + " daily_atr=" + DoubleToString(g_dailyAtr, _Digits)
         + " orb_atr_ratio=" + DoubleToString(ratio, 4));
   DrawLevels();
   return true;
}

bool BuildOrb()
{
   return BuildContext();
}

bool ComputeSignal(string &direction, datetime &barTime, double &signalClose, double &plannedSl, double &plannedRr, string &setupType, string &detail)
{
   direction = "";
   barTime = 0;
   signalClose = 0.0;
   plannedSl = 0.0;
   plannedRr = 0.0;
   setupType = "";
   detail = "";
   if(!g_contextReady)
      return false;
   if(TimeCurrent() < g_tradeStartServer || TimeCurrent() > g_tradeEndServer)
      return false;
   int shift = InpUseClosedBarBreakout ? 1 : 0;
   barTime = iTime(_Symbol, InpSignalTimeframe, shift);
   if(barTime <= 0 || barTime == g_lastSignalBarTime)
      return false;
   signalClose = iClose(_Symbol, InpSignalTimeframe, shift);
   if(signalClose <= 0.0)
      return false;
   if(g_biasStrength < InpBiasMinStrength || g_biasStrength > InpBiasMaxStrength || g_bias == "neutral")
   {
      Audit("signal_blocked_bias", "", 0, signalClose, 0, 0,
            "signal_bar=" + FmtTime(barTime)
            + " bias=" + g_bias
            + " strength=" + IntegerToString(g_biasStrength));
      g_lastSignalBarTime = barTime;
      return false;
   }

   double atr = g_dailyAtr > 0.0 ? g_dailyAtr : MathMax(MathAbs(g_orbHigh - g_orbLow), SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100.0);
   double minBreakout = MathMax(0.0, InpMinBreakoutDistanceAtr) * atr;
   if(g_bias == "bullish" && signalClose > g_orbHigh + minBreakout)
      direction = "BUY";
   else if(g_bias == "bearish" && signalClose < g_orbLow - minBreakout)
      direction = "SELL";
   if(direction == "")
      return false;

   double body = BodyAtShift(shift);
   if(InpMinBreakoutBodyAtr > 0.0 && atr > 0.0 && body / atr < InpMinBreakoutBodyAtr)
   {
      Audit("signal_blocked_body", direction, 0, signalClose, 0, 0,
            "signal_bar=" + FmtTime(barTime)
            + " body_atr=" + DoubleToString(body / atr, 5)
            + " min=" + DoubleToString(InpMinBreakoutBodyAtr, 5));
      g_lastSignalBarTime = barTime;
      return false;
   }

   double fvgTop, fvgBottom, fvgSize;
   datetime fvgTime;
   bool hasFvg = FindFreshFvg(direction, fvgTop, fvgBottom, fvgSize, fvgTime);
   if(hasFvg && InpMinFvgSizeAtr > 0.0 && atr > 0.0 && fvgSize / atr < InpMinFvgSizeAtr)
      hasFvg = false;

   if(hasFvg)
   {
      plannedSl = direction == "BUY" ? fvgBottom : fvgTop;
      setupType = direction == "BUY" ? "Bullish ORB Breakout + FVG" : "Bearish ORB Breakout + FVG";
      detail = "fvg_time=" + FmtTime(fvgTime)
         + " fvg_top=" + DoubleToString(fvgTop, _Digits)
         + " fvg_bottom=" + DoubleToString(fvgBottom, _Digits)
         + " fvg_size=" + DoubleToString(fvgSize, _Digits);
   }
   else if(!InpRequireFvg && InpFvgOptionalBiasThreshold > 0 && g_biasStrength >= InpFvgOptionalBiasThreshold && HasDisplacement(shift, direction))
   {
      double buffer = atr * MathMax(0.0, InpFvgOptionalSlBufferAtr);
      plannedSl = direction == "BUY" ? (g_orbHigh - buffer) : (g_orbLow + buffer);
      setupType = direction == "BUY" ? "Bullish ORB Breakout + Displacement" : "Bearish ORB Breakout + Displacement";
      detail = "fvg_optional_displacement=1 buffer_atr=" + DoubleToString(InpFvgOptionalSlBufferAtr, 3);
   }
   else
   {
      Audit("signal_blocked_fvg", direction, 0, signalClose, 0, 0,
            "signal_bar=" + FmtTime(barTime)
            + " require_fvg=" + (InpRequireFvg ? "true" : "false")
            + " bias_strength=" + IntegerToString(g_biasStrength));
      g_lastSignalBarTime = barTime;
      return false;
   }

   double slDistance = MathAbs(signalClose - plannedSl);
   if(slDistance <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
   {
      Audit("signal_blocked_geometry", direction, 0, signalClose, plannedSl, 0, "planned_sl_invalid " + detail);
      g_lastSignalBarTime = barTime;
      return false;
   }
   if(!SpreadEfficiencyAllowed(slDistance))
   {
      Audit("signal_blocked_spread_efficiency", direction, 0, signalClose, plannedSl, 0, "sl_distance=" + DoubleToString(slDistance, _Digits));
      g_lastSignalBarTime = barTime;
      return false;
   }
   plannedRr = PlanRr(slDistance);
   return true;
}

void TryOpenSignal()
{
   if(!InpEaEnabled)
      return;
   if(!BuildContext())
      return;
   if(InpOneTradePerNyDay && g_tradeTaken)
      return;
   if(OwnPositionExists())
      return;

   string dir;
   datetime barTime;
   double signalClose;
   double plannedSl;
   double plannedRr;
   string setupType;
   string signalDetail;
   if(!ComputeSignal(dir, barTime, signalClose, plannedSl, plannedRr, setupType, signalDetail))
      return;
   g_lastSignalBarTime = barTime;

   if(!SpreadAllowed())
   {
      Audit("signal_blocked_spread", dir, 0, signalClose, 0, 0, "signal_bar=" + FmtTime(barTime));
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Audit("signal_blocked_tick", dir, 0, signalClose, 0, 0, "no_tick");
      return;
   }

   double entry = (dir == "BUY") ? tick.ask : tick.bid;
   double sl = plannedSl;
   double risk = MathAbs(entry - sl);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(risk <= point)
   {
      Audit("signal_blocked_geometry", dir, 0, entry, sl, 0, "risk_too_small signal_bar=" + FmtTime(barTime));
      return;
   }
   double rr = MathMax(0.1, plannedRr);
   double tp = (dir == "BUY") ? (entry + risk * rr) : (entry - risk * rr);
   entry = NormalizePrice(entry);
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   double lot = CalculateLot(entry, sl);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   string comment = "ADV_ORB15|" + dir + "|" + IntegerToString(g_nyDayKey);
   ResetLastError();
   bool ok = false;
   if(dir == "BUY")
      ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, comment);
   else
      ok = trade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(ok)
   {
      g_tradeTaken = true;
      Audit("order_opened", dir, lot, entry, sl, tp,
            "signal_bar=" + FmtTime(barTime)
            + " signal_close=" + DoubleToString(signalClose, _Digits)
            + " rr=" + DoubleToString(rr, 2)
            + " setup=" + setupType
            + " " + signalDetail
            + " retcode=" + IntegerToString((int)trade.ResultRetcode())
            + " deal=" + IntegerToString((int)trade.ResultDeal())
            + " order=" + IntegerToString((int)trade.ResultOrder()));
   }
   else
   {
      Audit("order_failed", dir, lot, entry, sl, tp,
            "signal_bar=" + FmtTime(barTime)
            + " retcode=" + IntegerToString((int)trade.ResultRetcode())
            + " err=" + IntegerToString(GetLastError())
            + " setup=" + setupType
            + " " + signalDetail
            + " comment=" + trade.ResultComment());
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   ResetForNewNyDay();
   EventSetTimer(1);
   if(InpLogOnInit)
   {
      Print("Advanced15mOrb MT5 EA initialized symbol=", _Symbol,
            " tf=", EnumToString(InpSignalTimeframe),
            " magic=", InpMagic,
            " broker_gmt_offset_h=", DoubleToString(InpBrokerGmtOffsetHours, 2),
            " orb_ny=", InpOrbStartNy, "-", InpOrbEndNy,
            " trade_end_ny=", InpTradeEndNy,
            " bias_min=", InpBiasMinStrength,
            " require_fvg=", (InpRequireFvg ? "true" : "false"),
            " rr_min=", DoubleToString(InpMinRrTarget, 2),
            " risk_pct=", DoubleToString(InpRiskPerTradePct, 2),
            " auto_lot=", (InpUseAutoRiskLot ? "true" : "false"));
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteLevelObjects();
}

void OnTimer()
{
   ResetForNewNyDay();
   BuildOrb();
   TryOpenSignal();
}

void OnTick()
{
   ResetForNewNyDay();
   TryOpenSignal();
}
