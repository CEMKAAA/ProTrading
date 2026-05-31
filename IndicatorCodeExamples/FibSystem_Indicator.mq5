//+------------------------------------------------------------------+
//| FibSystem indicator                                               |
//| Source parity target: IndicatorCodeExamples/FibSystem.pine        |
//| Buffer 0 = raw PPO BUY triangle, Buffer 1 = raw PPO SELL triangle |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots   12
#property indicator_buffers 12
#property version "1.01"

#property indicator_label1  "Raw PPO BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  1

#property indicator_label2  "Raw PPO SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  1

#property indicator_label3  "Bullish Divergence"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  C'199,82,255'
#property indicator_width3  1

#property indicator_label4  "Bearish Divergence"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrOrange
#property indicator_width4  1

#property indicator_label5  "Minor term avg"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrMaroon
#property indicator_width5  1

#property indicator_label6  "Ch+1"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrRed
#property indicator_width6  1

#property indicator_label7  "Ch-1"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrGreen
#property indicator_width7  1

#property indicator_label8  "Ch+2"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrRed
#property indicator_width8  1

#property indicator_label9  "Ch-2"
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrGreen
#property indicator_width9  1

#property indicator_label10 "Ch+3"
#property indicator_type10  DRAW_LINE
#property indicator_color10 clrRed
#property indicator_width10 1

#property indicator_label11 "Ch-3"
#property indicator_type11  DRAW_LINE
#property indicator_color11 clrGreen
#property indicator_width11 1

#property indicator_label12 "Linear Regression Curve"
#property indicator_type12  DRAW_LINE
#property indicator_color12 clrRed
#property indicator_width12 2

input bool InpShowPpoHighLowTriangles = true; // Show PPO high/low triangles?
input bool InpDrawActionableSignalBars = true; // Draw PPO arrows on actionable decision bars, not Pine backplot bars
input bool InpUseLongTermDivergences = true; // Use long term divergences?
input int  InpDivergenceLookbackPeriod = 55; // Lookback Period
input int  InpFastLength = 12;               // PPO Fast
input int  InpSlowLength = 26;               // PPO Slow
input int  InpSignalLength = 9;              // PPO Signal (kept for Pine input parity; Pine does not use it)
input int  InpSmoother = 2;                  // PPO Smooth
input int  InpFibPeriod = 200;               // Fib Period
input int  InpTmcLength = 41;                // TMC length
input bool InpShowPriceTracker = false;      // TMC trackprice input parity
input int  InpLinearRegressionLength = 25;   // Linear Regression Length
input bool InpDrawFibLevels = true;
input bool InpDrawDivergenceText = true;
input int  InpMaxDivergenceTextObjects = 300;

double BuyBuffer[];
double SellBuffer[];
double BullDivBuffer[];
double BearDivBuffer[];
double BasisBuffer[];
double ChP1Buffer[];
double ChM1Buffer[];
double ChP2Buffer[];
double ChM2Buffer[];
double ChP3Buffer[];
double ChM3Buffer[];
double LrcBuffer[];

string PREFIX = "FIBSYS_IND_";

bool IsValidNumber(const double value)
{
   return value != EMPTY_VALUE && MathIsValidNumber(value) && value < DBL_MAX / 2.0 && value > -DBL_MAX / 2.0;
}

double ArrowPad(const MqlRates &rates[], const int shift)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double range = MathAbs(rates[shift].high - rates[shift].low);
   return MathMax(point * 35.0, range * 0.50);
}

double LowestRatesLow(const MqlRates &rates[], const int bars, const int shift, const int length)
{
   if(shift < 0 || shift + length - 1 >= bars)
      return EMPTY_VALUE;
   double value = rates[shift].low;
   for(int k = 1; k < length; k++)
      value = MathMin(value, rates[shift + k].low);
   return value;
}

double HighestRatesHigh(const MqlRates &rates[], const int bars, const int shift, const int length)
{
   if(shift < 0 || shift + length - 1 >= bars)
      return EMPTY_VALUE;
   double value = rates[shift].high;
   for(int k = 1; k < length; k++)
      value = MathMax(value, rates[shift + k].high);
   return value;
}

double LowestArray(const double &values[], const int bars, const int shift, const int length)
{
   if(shift < 0 || shift + length - 1 >= bars)
      return EMPTY_VALUE;
   double result = EMPTY_VALUE;
   for(int k = 0; k < length; k++)
   {
      double value = values[shift + k];
      if(!IsValidNumber(value))
         continue;
      result = !IsValidNumber(result) ? value : MathMin(result, value);
   }
   return result;
}

double HighestArray(const double &values[], const int bars, const int shift, const int length)
{
   if(shift < 0 || shift + length - 1 >= bars)
      return EMPTY_VALUE;
   double result = EMPTY_VALUE;
   for(int k = 0; k < length; k++)
   {
      double value = values[shift + k];
      if(!IsValidNumber(value))
         continue;
      result = !IsValidNumber(result) ? value : MathMax(result, value);
   }
   return result;
}

int BarsSince(const bool &condition[], const int bars, const int shift)
{
   for(int j = shift; j < bars; j++)
   {
      if(condition[j])
         return j - shift;
   }
   return 1000000;
}

double ValueWhen(const bool &condition[], const double &expression[], const int bars, const int shift, const int occurrence)
{
   int seen = 0;
   for(int j = shift; j < bars; j++)
   {
      if(!condition[j])
         continue;
      if(seen == occurrence)
         return expression[j];
      seen++;
   }
   return EMPTY_VALUE;
}

double SmaClose(const MqlRates &rates[], const int bars, const int shift, const int length)
{
   if(length <= 0 || shift + length - 1 >= bars)
      return EMPTY_VALUE;
   double sum = 0.0;
   for(int k = 0; k < length; k++)
      sum += rates[shift + k].close;
   return sum / length;
}

double SmaArray(const double &values[], const int bars, const int shift, const int length)
{
   if(length <= 0 || shift + length - 1 >= bars)
      return EMPTY_VALUE;
   double sum = 0.0;
   for(int k = 0; k < length; k++)
   {
      if(!IsValidNumber(values[shift + k]))
         return EMPTY_VALUE;
      sum += values[shift + k];
   }
   return sum / length;
}

double LinRegClose(const MqlRates &rates[], const int bars, const int shift, const int length)
{
   if(length <= 1 || shift + length - 1 >= bars)
      return EMPTY_VALUE;

   // Pine linreg(src, len, 0): value at the newest sample in the regression window.
   double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
   for(int k = 0; k < length; k++)
   {
      double x = (double)k;
      double y = rates[shift + length - 1 - k].close; // oldest=0, newest=len-1
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
   }
   double n = (double)length;
   double denom = n * sumX2 - sumX * sumX;
   if(MathAbs(denom) <= 1e-12)
      return EMPTY_VALUE;
   double slope = (n * sumXY - sumX * sumY) / denom;
   double intercept = (sumY - slope * sumX) / n;
   return intercept + slope * (length - 1);
}

bool CalculatePpo(const MqlRates &rates[], const int bars, double &ppoSmooth[])
{
   if(bars < InpSlowLength + InpSmoother + 5)
      return false;

   double fast[], slow[], macdPct[];
   ArrayResize(fast, bars);
   ArrayResize(slow, bars);
   ArrayResize(macdPct, bars);
   ArrayResize(ppoSmooth, bars);
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(macdPct, true);
   ArraySetAsSeries(ppoSmooth, true);

   double fastAlpha = 2.0 / (MathMax(1, InpFastLength) + 1.0);
   double slowAlpha = 2.0 / (MathMax(1, InpSlowLength) + 1.0);

   for(int i = bars - 1; i >= 0; i--)
   {
      double closePrice = rates[i].close;
      if(i == bars - 1)
      {
         fast[i] = closePrice;
         slow[i] = closePrice;
      }
      else
      {
         fast[i] = fastAlpha * closePrice + (1.0 - fastAlpha) * fast[i + 1];
         slow[i] = slowAlpha * closePrice + (1.0 - slowAlpha) * slow[i + 1];
      }

      macdPct[i] = MathAbs(slow[i]) <= 1e-12 ? EMPTY_VALUE : ((fast[i] - slow[i]) / slow[i]) * 100.0;
   }

   int smoother = MathMax(1, InpSmoother);
   for(int i = bars - 1; i >= 0; i--)
      ppoSmooth[i] = SmaArray(macdPct, bars, i, smoother);

   return true;
}

bool PriceMinAtShift(const MqlRates &rates[], const int bars, const int shift)
{
   if(shift + 5 >= bars)
      return false;
   double low0 = rates[shift].low;
   double low1 = rates[shift + 1].low;
   double low2 = rates[shift + 2].low;
   double low3 = rates[shift + 3].low;
   double low4 = rates[shift + 4].low;
   double low5 = rates[shift + 5].low;
   return (low0 > low1 && low1 < low2)
          || (low1 == low2 && low1 < low0 && low1 < low3)
          || (low1 == low2 && low1 == low3 && low1 < low0 && low1 < low4)
          || (low1 == low2 && low1 == low3 && low1 != 0.0 && low1 == low4 && low1 < low0 && low1 < low5);
}

bool PriceMaxAtShift(const MqlRates &rates[], const int bars, const int shift)
{
   if(shift + 5 >= bars)
      return false;
   double high0 = rates[shift].high;
   double high1 = rates[shift + 1].high;
   double high2 = rates[shift + 2].high;
   double high3 = rates[shift + 3].high;
   double high4 = rates[shift + 4].high;
   double high5 = rates[shift + 5].high;
   return (high0 < high1 && high1 > high2)
          || (high1 == high2 && high1 > high0 && high1 > high3)
          || (high1 == high2 && high1 == high3 && high1 > high0 && high1 > high4)
          || (high1 == high2 && high1 == high3 && high1 != 0.0 && high1 == high4 && high1 > high0 && high1 > high5);
}

bool OscMinAtShift(const double &d[], const int bars, const int shift)
{
   if(shift + 2 >= bars)
      return false;
   if(!IsValidNumber(d[shift]) || !IsValidNumber(d[shift + 1]) || !IsValidNumber(d[shift + 2]))
      return false;
   return d[shift] > d[shift + 1] && d[shift + 1] < d[shift + 2];
}

bool OscMaxAtShift(const double &d[], const int bars, const int shift)
{
   if(shift + 2 >= bars)
      return false;
   if(!IsValidNumber(d[shift]) || !IsValidNumber(d[shift + 1]) || !IsValidNumber(d[shift + 2]))
      return false;
   return d[shift] < d[shift + 1] && d[shift + 1] > d[shift + 2];
}

void ClearBuffers(const int bars)
{
   for(int i = 0; i < bars; i++)
   {
      BuyBuffer[i] = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;
      BullDivBuffer[i] = EMPTY_VALUE;
      BearDivBuffer[i] = EMPTY_VALUE;
      BasisBuffer[i] = EMPTY_VALUE;
      ChP1Buffer[i] = EMPTY_VALUE;
      ChM1Buffer[i] = EMPTY_VALUE;
      ChP2Buffer[i] = EMPTY_VALUE;
      ChM2Buffer[i] = EMPTY_VALUE;
      ChP3Buffer[i] = EMPTY_VALUE;
      ChM3Buffer[i] = EMPTY_VALUE;
      LrcBuffer[i] = EMPTY_VALUE;
   }
}

void DeleteObjectsByPrefix(const string prefix)
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DrawText(const string tag, const datetime time, const double price, const string text, const color clr)
{
   string name = PREFIX + tag + "_" + IntegerToString((int)time);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
   ObjectMove(0, name, 0, time, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
}

void DrawHLine(const string tag, const string label, const double price, const color clr, const int width)
{
   if(!IsValidNumber(price))
      return;
   string name = PREFIX + "FIB_" + tag;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
}

void DrawFibLevels(const MqlRates &rates[], const int bars)
{
   if(!InpDrawFibLevels || bars < 10)
   {
      DeleteObjectsByPrefix(PREFIX + "FIB_");
      return;
   }

   double fractalTop[];
   double fractalBottom[];
   ArrayResize(fractalTop, bars);
   ArrayResize(fractalBottom, bars);
   ArraySetAsSeries(fractalTop, true);
   ArraySetAsSeries(fractalBottom, true);

   for(int i = bars - 1; i >= 0; i--)
   {
      if(i == bars - 1)
      {
         fractalTop[i] = 0.0;
         fractalBottom[i] = 0.0;
      }
      else
      {
         fractalTop[i] = fractalTop[i + 1];
         fractalBottom[i] = fractalBottom[i + 1];
      }

      if(i + 4 < bars)
      {
         if(rates[i].high < rates[i + 2].high && rates[i + 1].high < rates[i + 2].high
            && rates[i + 3].high < rates[i + 2].high && rates[i + 4].high < rates[i + 2].high)
            fractalTop[i] = rates[i + 2].high;

         if(rates[i].low > rates[i + 2].low && rates[i + 1].low > rates[i + 2].low
            && rates[i + 3].low > rates[i + 2].low && rates[i + 4].low > rates[i + 2].low)
            fractalBottom[i] = rates[i + 2].low;
      }
   }

   double srcHigh = HighestArray(fractalTop, bars, 0, MathMin(InpFibPeriod, bars));
   double srcLow = LowestArray(fractalBottom, bars, 0, MathMin(InpFibPeriod, bars));
   if(!IsValidNumber(srcHigh) || !IsValidNumber(srcLow))
      return;

   double diff = srcHigh - srcLow;
   DrawHLine("0000", "0.000", srcLow, C'46,154,254', 4);
   DrawHLine("0236", "0.236", srcLow + diff * 0.236, C'46,154,254', 2);
   DrawHLine("0382", "0.382", srcLow + diff * 0.382, C'46,154,254', 2);
   DrawHLine("0500", "0.500", srcLow + diff * 0.500, C'46,154,254', 2);
   DrawHLine("0618", "0.618", srcLow + diff * 0.618, C'46,154,254', 2);
   DrawHLine("0786", "0.786", srcLow + diff * 0.786, C'46,154,254', 2);
   DrawHLine("1000", "1.000", srcHigh, C'46,154,254', 4);
   DrawHLine("1272", "1.272", srcLow + diff * 1.272, clrGreen, 2);
   DrawHLine("1414", "1.414", srcLow + diff * 1.414, clrGreen, 2);
   DrawHLine("1618", "1.618", srcLow + diff * 1.618, clrGreen, 2);
   DrawHLine("2000", "2.000", srcLow + diff * 2.000, clrGreen, 2);
   DrawHLine("2272", "2.272", srcLow + diff * 2.272, clrGreen, 2);
   DrawHLine("1272_2", "-0.272", srcHigh - diff * 1.272, clrRed, 2);
   DrawHLine("1414_2", "-0.414", srcHigh - diff * 1.414, clrRed, 2);
   DrawHLine("1618_2", "-0.618", srcHigh - diff * 1.618, clrRed, 2);
   DrawHLine("2000_2", "-1.000", srcHigh - diff * 2.000, clrRed, 2);
   DrawHLine("2272_2", "-1.272", srcHigh - diff * 2.272, clrRed, 2);
}

void CalculateTmcAndLrc(const MqlRates &rates[], const int bars)
{
   int length = MathMax(1, InpTmcLength);
   int halfLength = (int)MathFloor(length / 2.0);

   double basis[];
   double yom[];
   double varyom[];
   double som[];
   double sigom[];
   ArrayResize(basis, bars);
   ArrayResize(yom, bars);
   ArrayResize(varyom, bars);
   ArrayResize(som, bars);
   ArrayResize(sigom, bars);
   ArraySetAsSeries(basis, true);
   ArraySetAsSeries(yom, true);
   ArraySetAsSeries(varyom, true);
   ArraySetAsSeries(som, true);
   ArraySetAsSeries(sigom, true);

   for(int i = bars - 1; i >= 0; i--)
   {
      basis[i] = SmaClose(rates, bars, i, length);
      if(IsValidNumber(basis[i]) && i + halfLength < bars && IsValidNumber(basis[i + halfLength]) && MathAbs(basis[i + halfLength]) > 1e-12)
         yom[i] = 100.0 * (rates[i].close - basis[i + halfLength]) / basis[i + halfLength];
      else
         yom[i] = EMPTY_VALUE;
   }

   int longLen = 2 * length;
   double yomSq[];
   ArrayResize(yomSq, bars);
   ArraySetAsSeries(yomSq, true);
   for(int i = bars - 1; i >= 0; i--)
      yomSq[i] = IsValidNumber(yom[i]) ? yom[i] * yom[i] : EMPTY_VALUE;

   for(int i = bars - 1; i >= 0; i--)
   {
      double avyom = SmaArray(yom, bars, i, longLen);
      double y2 = SmaArray(yomSq, bars, i, longLen);
      varyom[i] = IsValidNumber(avyom) && IsValidNumber(y2) ? y2 - avyom * avyom : EMPTY_VALUE;
      if(IsValidNumber(varyom[i]) && i + halfLength < bars)
         som[i] = IsValidNumber(varyom[i + halfLength]) && varyom[i + halfLength] >= 0.0 ? MathSqrt(varyom[i + halfLength]) : EMPTY_VALUE;
      else
         som[i] = EMPTY_VALUE;
   }

   for(int i = bars - 1; i >= 0; i--)
   {
      sigom[i] = SmaArray(som, bars, i, length);
      BasisBuffer[i] = basis[i];
      if(IsValidNumber(basis[i]) && IsValidNumber(sigom[i]))
      {
         ChP1Buffer[i] = basis[i] * (1.0 + 0.01 * sigom[i]);
         ChM1Buffer[i] = basis[i] * (1.0 - 0.01 * sigom[i]);
         ChP2Buffer[i] = basis[i] * (1.0 + 0.02 * sigom[i]);
         ChM2Buffer[i] = basis[i] * (1.0 - 0.02 * sigom[i]);
         ChP3Buffer[i] = basis[i] * (1.0 + 0.03 * sigom[i]);
         ChM3Buffer[i] = basis[i] * (1.0 - 0.03 * sigom[i]);
      }
      LrcBuffer[i] = LinRegClose(rates, bars, i, MathMax(1, InpLinearRegressionLength));
   }
}

void CalculateSignals(const MqlRates &rates[], const int bars, const double &d[])
{
   bool priceMins[], priceMax[], oscMins[], oscMax[];
   double currenttrough4[], currenttrough5[], currenttrough6[], currenttrough7[];
   double dPrev[], lowPrev[], highPrev[], lowestExpr[], highestExpr[];
   double delayedlow[], delayedhigh[], filter[], filter2[];

   ArrayResize(priceMins, bars);
   ArrayResize(priceMax, bars);
   ArrayResize(oscMins, bars);
   ArrayResize(oscMax, bars);
   ArrayResize(currenttrough4, bars);
   ArrayResize(currenttrough5, bars);
   ArrayResize(currenttrough6, bars);
   ArrayResize(currenttrough7, bars);
   ArrayResize(dPrev, bars);
   ArrayResize(lowPrev, bars);
   ArrayResize(highPrev, bars);
   ArrayResize(lowestExpr, bars);
   ArrayResize(highestExpr, bars);
   ArrayResize(delayedlow, bars);
   ArrayResize(delayedhigh, bars);
   ArrayResize(filter, bars);
   ArrayResize(filter2, bars);
   ArraySetAsSeries(priceMins, true);
   ArraySetAsSeries(priceMax, true);
   ArraySetAsSeries(oscMins, true);
   ArraySetAsSeries(oscMax, true);
   ArraySetAsSeries(currenttrough4, true);
   ArraySetAsSeries(currenttrough5, true);
   ArraySetAsSeries(currenttrough6, true);
   ArraySetAsSeries(currenttrough7, true);
   ArraySetAsSeries(dPrev, true);
   ArraySetAsSeries(lowPrev, true);
   ArraySetAsSeries(highPrev, true);
   ArraySetAsSeries(lowestExpr, true);
   ArraySetAsSeries(highestExpr, true);
   ArraySetAsSeries(delayedlow, true);
   ArraySetAsSeries(delayedhigh, true);
   ArraySetAsSeries(filter, true);
   ArraySetAsSeries(filter2, true);

   for(int i = bars - 1; i >= 0; i--)
   {
      priceMins[i] = PriceMinAtShift(rates, bars, i);
      priceMax[i] = PriceMaxAtShift(rates, bars, i);
      oscMins[i] = OscMinAtShift(d, bars, i);
      oscMax[i] = OscMaxAtShift(d, bars, i);
      dPrev[i] = i + 1 < bars ? d[i + 1] : EMPTY_VALUE;
      lowPrev[i] = i + 1 < bars ? rates[i + 1].low : EMPTY_VALUE;
      highPrev[i] = i + 1 < bars ? rates[i + 1].high : EMPTY_VALUE;
      lowestExpr[i] = LowestRatesLow(rates, bars, i, MathMax(1, InpDivergenceLookbackPeriod));
      highestExpr[i] = HighestRatesHigh(rates, bars, i, MathMax(1, InpDivergenceLookbackPeriod));
   }

   for(int i = bars - 1; i >= 0; i--)
   {
      currenttrough4[i] = ValueWhen(oscMins, dPrev, bars, i, 0);
      currenttrough5[i] = ValueWhen(oscMax, dPrev, bars, i, 0);
      currenttrough6[i] = ValueWhen(priceMins, lowPrev, bars, i, 0);
      currenttrough7[i] = ValueWhen(priceMax, highPrev, bars, i, 0);

      delayedlow[i] = priceMins[i] && BarsSince(oscMins, bars, i) < 3 && i + 1 < bars ? rates[i + 1].low : EMPTY_VALUE;
      delayedhigh[i] = priceMax[i] && BarsSince(oscMax, bars, i) < 3 && i + 1 < bars ? rates[i + 1].high : EMPTY_VALUE;
      filter[i] = BarsSince(priceMins, bars, i) < 5 ? LowestArray(currenttrough6, bars, i, 4) : EMPTY_VALUE;
      filter2[i] = BarsSince(priceMax, bars, i) < 5 ? HighestArray(currenttrough7, bars, i, 4) : EMPTY_VALUE;
   }

   int textCount = 0;
   if(InpDrawDivergenceText)
      DeleteObjectsByPrefix(PREFIX + "TXT_");

   // Iterate newest -> older so optional text labels are capped to the most recent signals.
   for(int i = 0; i <= bars - 3; i++)
   {
      if(InpShowPpoHighLowTriangles && oscMins[i])
      {
         int plotShift = InpDrawActionableSignalBars ? i : i + 1;
         if(plotShift < bars)
            BuyBuffer[plotShift] = rates[plotShift].low - ArrowPad(rates, plotShift);
      }
      if(InpShowPpoHighLowTriangles && oscMax[i])
      {
         int plotShift = InpDrawActionableSignalBars ? i : i + 1;
         if(plotShift < bars)
            SellBuffer[plotShift] = rates[plotShift].high + ArrowPad(rates, plotShift);
      }

      double y2 = ValueWhen(oscMax, filter2, bars, i, 1);
      double y6 = ValueWhen(oscMins, filter, bars, i, 1);
      double longTermBullFilt = ValueWhen(priceMins, lowestExpr, bars, i, 1);
      double longTermBearFilt = ValueWhen(priceMax, highestExpr, bars, i, 1);

      double y3 = ValueWhen(oscMax, currenttrough5, bars, i, 0);
      double y4 = ValueWhen(oscMax, currenttrough5, bars, i, 1);
      double y7 = ValueWhen(oscMins, currenttrough4, bars, i, 0);
      double y8 = ValueWhen(oscMins, currenttrough4, bars, i, 1);
      double y9 = ValueWhen(oscMins, currenttrough6, bars, i, 0);
      double y10 = ValueWhen(oscMax, currenttrough7, bars, i, 0);

      double highestD = HighestArray(d, bars, i, MathMax(1, InpDivergenceLookbackPeriod));
      double lowestD = LowestArray(d, bars, i, MathMax(1, InpDivergenceLookbackPeriod));

      bool iBearOsc = IsValidNumber(currenttrough5[i]) && IsValidNumber(highestD) && currenttrough5[i] < highestD;
      bool iBearTop = IsValidNumber(y10) && IsValidNumber(longTermBearFilt) && y10 > longTermBearFilt;
      bool iBearDelayed = IsValidNumber(delayedhigh[i]) && IsValidNumber(longTermBearFilt) && delayedhigh[i] > longTermBearFilt;
      bool iBullOsc = IsValidNumber(currenttrough4[i]) && IsValidNumber(lowestD) && currenttrough4[i] > lowestD;
      bool iBullBottom = IsValidNumber(y9) && IsValidNumber(longTermBullFilt) && y9 < longTermBullFilt;
      bool iBullDelayed = IsValidNumber(delayedlow[i]) && IsValidNumber(longTermBullFilt) && delayedlow[i] < longTermBullFilt;

      bool bearishdiv1 = IsValidNumber(y10) && IsValidNumber(y2) && IsValidNumber(y3) && IsValidNumber(y4) && y10 > y2 && oscMax[i] && y3 < y4;
      bool bearishdiv2 = IsValidNumber(delayedhigh[i]) && IsValidNumber(y2) && IsValidNumber(y3) && IsValidNumber(y4) && delayedhigh[i] > y2 && y3 < y4;
      bool bearishdiv3 = InpUseLongTermDivergences && oscMax[i] && iBearOsc && iBearTop;
      bool bearishdiv4 = InpUseLongTermDivergences && iBearOsc && iBearDelayed;

      bool bullishdiv1 = IsValidNumber(y9) && IsValidNumber(y6) && IsValidNumber(y7) && IsValidNumber(y8) && y9 < y6 && oscMins[i] && y7 > y8;
      bool bullishdiv2 = IsValidNumber(delayedlow[i]) && IsValidNumber(y6) && IsValidNumber(y7) && IsValidNumber(y8) && delayedlow[i] < y6 && y7 > y8;
      bool bullishdiv3 = InpUseLongTermDivergences && oscMins[i] && iBullOsc && iBullBottom;
      bool bullishdiv4 = InpUseLongTermDivergences && iBullOsc && iBullDelayed;

      bool bearish = bearishdiv1 || bearishdiv2 || bearishdiv3 || bearishdiv4;
      bool bullish = bullishdiv1 || bullishdiv2 || bullishdiv3 || bullishdiv4;

      if(bearish)
      {
         BearDivBuffer[i] = rates[i].high + ArrowPad(rates, i);
         if(InpDrawDivergenceText && textCount < InpMaxDivergenceTextObjects)
         {
            DrawText("TXT_BEAR_P", rates[i].time, BearDivBuffer[i] + ArrowPad(rates, i) * 0.55, "P", clrOrange);
            textCount++;
         }
      }
      if(bullish)
      {
         BullDivBuffer[i] = rates[i].low - ArrowPad(rates, i);
         if(InpDrawDivergenceText && textCount < InpMaxDivergenceTextObjects)
         {
            DrawText("TXT_BULL_P", rates[i].time, BullDivBuffer[i] - ArrowPad(rates, i) * 0.55, "P", C'199,82,255');
            textCount++;
         }
      }
   }
}

int OnInit()
{
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, BullDivBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, BearDivBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, BasisBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, ChP1Buffer, INDICATOR_DATA);
   SetIndexBuffer(6, ChM1Buffer, INDICATOR_DATA);
   SetIndexBuffer(7, ChP2Buffer, INDICATOR_DATA);
   SetIndexBuffer(8, ChM2Buffer, INDICATOR_DATA);
   SetIndexBuffer(9, ChP3Buffer, INDICATOR_DATA);
   SetIndexBuffer(10, ChM3Buffer, INDICATOR_DATA);
   SetIndexBuffer(11, LrcBuffer, INDICATOR_DATA);

   ArraySetAsSeries(BuyBuffer, true);
   ArraySetAsSeries(SellBuffer, true);
   ArraySetAsSeries(BullDivBuffer, true);
   ArraySetAsSeries(BearDivBuffer, true);
   ArraySetAsSeries(BasisBuffer, true);
   ArraySetAsSeries(ChP1Buffer, true);
   ArraySetAsSeries(ChM1Buffer, true);
   ArraySetAsSeries(ChP2Buffer, true);
   ArraySetAsSeries(ChM2Buffer, true);
   ArraySetAsSeries(ChP3Buffer, true);
   ArraySetAsSeries(ChM3Buffer, true);
   ArraySetAsSeries(LrcBuffer, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   for(int i = 0; i < 12; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, InpDrawActionableSignalBars ? "FibSystem Actionable Signals" : "FibSystem Pine-Backplot Signals");
   Print("FibSystem_Indicator initialized. Buffers: 0=BUY, 1=SELL actionable_signals=", (InpDrawActionableSignalBars ? "true" : "false"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(PREFIX);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < MathMax(InpSlowLength + InpSmoother + 10, 100))
      return 0;

   MqlRates rates[];
   int bars = CopyRates(_Symbol, _Period, 0, rates_total, rates);
   if(bars <= 0)
      return prev_calculated;
   ArraySetAsSeries(rates, true);

   ClearBuffers(bars);

   double ppoSmooth[];
   if(!CalculatePpo(rates, bars, ppoSmooth))
      return prev_calculated;

   CalculateSignals(rates, bars, ppoSmooth);
   CalculateTmcAndLrc(rates, bars);
   DrawFibLevels(rates, bars);

   return rates_total;
}
