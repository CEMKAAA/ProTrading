//+------------------------------------------------------------------+
//| CatchingWhereToStop.mq4                                          |
//| MT4 port of "%R Trend Exhaustion [upslidedown]".                 |
//| Automation buffers: Buffer 0 = LONG(1.0), Buffer 1 = SHORT(1.0). |
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_minimum -115
#property indicator_maximum 15
#property indicator_level1 0
#property indicator_level2 -20
#property indicator_level3 -50
#property indicator_level4 -80
#property indicator_level5 -100
#property indicator_color1 clrNONE
#property indicator_color2 clrNONE
#property indicator_color3 clrDodgerBlue
#property indicator_color4 clrRed
#property indicator_color5 clrSilver
#property indicator_color6 clrLightSteelBlue
#property indicator_color7 clrGold
#property indicator_color8 clrGray
#property indicator_width3 1
#property indicator_width4 1
#property indicator_width5 1
#property indicator_width6 1
#property indicator_width7 1
#property indicator_width8 1

enum RteSource
{
   SourceClose = 0,
   SourceOpen = 1,
   SourceHigh = 2,
   SourceLow = 3,
   SourceHL2 = 4,
   SourceHLC3 = 5,
   SourceOHLC4 = 6
};

enum RteFormula
{
   FormulaStandard = 0,
   FormulaAverage = 1
};

enum RteSmoothingType
{
   SmoothSMA = 0,
   SmoothEMA = 1,
   SmoothHMA = 2,
   SmoothRMA = 3,
   SmoothWMA = 4,
   SmoothVWMA = 5,
   SmoothSWMA = 6,
   SmoothHighLow = 7,
   SmoothLinReg = 8,
   SmoothMedian = 9,
   SmoothMomentum = 10,
   SmoothPercentRank = 11
};

enum RteStrategyEntry
{
   StrategyTrendFollowingAtSquare = 0,
   StrategyReversalAtSquare = 1,
   StrategyReversalTradeAtTriangle = 2,
   StrategyReEnterTrendTradeAtTriangle = 3,
   StrategyPings = 4,
   StrategyZeroLineCross = 5
};

input RteSource        InpSource = SourceClose;
input int              InpThreshold = 20;
input RteFormula       InpFormula = FormulaStandard;
input RteSmoothingType InpSmoothingType = SmoothEMA;
input int              InpAverageMa = 3;
input int              InpFastLength = 21;
input int              InpFastSmoothingLength = 7;
input int              InpSlowLength = 112;
input int              InpSlowSmoothingLength = 3;
input RteStrategyEntry InpStrategyEntry = StrategyReversalTradeAtTriangle;
input bool             InpLongDealsEnabled = true;
input bool             InpShortDealsEnabled = true;
input bool             InpShowStrategyArrows = true;
input bool             InpShowPercentR = true;
input bool             InpShowAverage = true;
input bool             InpShowDebugEvents = false;

double LongSignalBuffer[];
double ShortSignalBuffer[];
double LongArrowBuffer[];
double ShortArrowBuffer[];
double FastRBuffer[];
double SlowRBuffer[];
double AvgRBuffer[];
double DebugEventBuffer[];

double g_src[];
double g_fastRaw[];
double g_slowRaw[];
double g_avgRaw[];
double g_fastR[];
double g_slowR[];
double g_avgR[];
double g_temp1[];
double g_temp2[];

bool _valid(double v)
{
   if(v == EMPTY_VALUE)
      return false;
   if(v != v)
      return false;
   return true;
}

double _source_price(
   int i,
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[]
)
{
   if(InpSource == SourceOpen)
      return open[i];
   if(InpSource == SourceHigh)
      return high[i];
   if(InpSource == SourceLow)
      return low[i];
   if(InpSource == SourceHL2)
      return (high[i] + low[i]) / 2.0;
   if(InpSource == SourceHLC3)
      return (high[i] + low[i] + close[i]) / 3.0;
   if(InpSource == SourceOHLC4)
      return (open[i] + high[i] + low[i] + close[i]) / 4.0;
   return close[i];
}

void _resize_arrays(int total)
{
   ArrayResize(g_src, total);
   ArrayResize(g_fastRaw, total);
   ArrayResize(g_slowRaw, total);
   ArrayResize(g_avgRaw, total);
   ArrayResize(g_fastR, total);
   ArrayResize(g_slowR, total);
   ArrayResize(g_avgR, total);
   ArrayResize(g_temp1, total);
   ArrayResize(g_temp2, total);

   ArraySetAsSeries(g_src, true);
   ArraySetAsSeries(g_fastRaw, true);
   ArraySetAsSeries(g_slowRaw, true);
   ArraySetAsSeries(g_avgRaw, true);
   ArraySetAsSeries(g_fastR, true);
   ArraySetAsSeries(g_slowR, true);
   ArraySetAsSeries(g_avgR, true);
   ArraySetAsSeries(g_temp1, true);
   ArraySetAsSeries(g_temp2, true);
}

double _highest_src(int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   double highest = g_src[i];
   for(int j = i + 1; j <= last; j++)
      if(g_src[j] > highest)
         highest = g_src[j];
   return highest;
}

double _lowest_src(int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   double lowest = g_src[i];
   for(int j = i + 1; j <= last; j++)
      if(g_src[j] < lowest)
         lowest = g_src[j];
   return lowest;
}

double _percent_r(int i, int total, int length)
{
   double highest = _highest_src(i, total, length);
   double lowest = _lowest_src(i, total, length);
   double range = highest - lowest;
   if(MathAbs(range) < 0.0000000001)
      return EMPTY_VALUE;
   return 100.0 * (g_src[i] - highest) / range;
}

double _sma_value(const double &src[], int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   double sum = 0.0;
   int count = 0;
   for(int j = i; j <= last; j++)
   {
      if(!_valid(src[j]))
         continue;
      sum += src[j];
      count++;
   }
   if(count <= 0)
      return EMPTY_VALUE;
   return sum / count;
}

double _wma_value(const double &src[], int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   double sum = 0.0;
   double weightSum = 0.0;
   for(int j = i; j <= last; j++)
   {
      if(!_valid(src[j]))
         continue;
      double w = p - (j - i);
      sum += src[j] * w;
      weightSum += w;
   }
   if(weightSum <= 0.0)
      return EMPTY_VALUE;
   return sum / weightSum;
}

double _vwma_value(const double &src[], const long &tick_volume[], int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   double sum = 0.0;
   double volumeSum = 0.0;
   for(int j = i; j <= last; j++)
   {
      if(!_valid(src[j]))
         continue;
      double volume = (double)tick_volume[j];
      sum += src[j] * volume;
      volumeSum += volume;
   }
   if(volumeSum <= 0.0)
      return EMPTY_VALUE;
   return sum / volumeSum;
}

double _swma_value(const double &src[], int i, int total)
{
   if(i + 3 >= total)
      return EMPTY_VALUE;
   if(!_valid(src[i]) || !_valid(src[i + 1]) || !_valid(src[i + 2]) || !_valid(src[i + 3]))
      return EMPTY_VALUE;
   return (src[i] + 2.0 * src[i + 1] + 2.0 * src[i + 2] + src[i + 3]) / 6.0;
}

double _highlow_value(const double &src[], int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   bool has = false;
   double highest = 0.0;
   double lowest = 0.0;
   for(int j = i; j <= last; j++)
   {
      if(!_valid(src[j]))
         continue;
      if(!has)
      {
         highest = src[j];
         lowest = src[j];
         has = true;
      }
      else
      {
         if(src[j] > highest)
            highest = src[j];
         if(src[j] < lowest)
            lowest = src[j];
      }
   }
   if(!has)
      return EMPTY_VALUE;
   return (highest + lowest) / 2.0;
}

double _linreg_value(const double &src[], int i, int total, int length)
{
   int p = MathMax(1, length);
   if(i + p - 1 >= total)
      return EMPTY_VALUE;
   double sumX = 0.0;
   double sumY = 0.0;
   double sumXY = 0.0;
   double sumX2 = 0.0;
   int count = 0;
   for(int k = 0; k < p; k++)
   {
      int j = i + p - 1 - k;
      if(!_valid(src[j]))
         return EMPTY_VALUE;
      double x = k;
      double y = src[j];
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
      count++;
   }
   double denom = count * sumX2 - sumX * sumX;
   if(MathAbs(denom) < 0.0000000001)
      return src[i];
   double slope = (count * sumXY - sumX * sumY) / denom;
   double intercept = (sumY - slope * sumX) / count;
   return intercept + slope * (p - 1);
}

double _median_value(const double &src[], int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   double vals[];
   ArrayResize(vals, p);
   int count = 0;
   for(int j = i; j <= last; j++)
   {
      if(!_valid(src[j]))
         continue;
      vals[count] = src[j];
      count++;
   }
   if(count <= 0)
      return EMPTY_VALUE;
   ArrayResize(vals, count);
   ArraySort(vals, WHOLE_ARRAY, 0, MODE_ASCEND);
   int mid = count / 2;
   if((count % 2) == 1)
      return vals[mid];
   return (vals[mid - 1] + vals[mid]) / 2.0;
}

double _momentum_value(const double &src[], int i, int total, int length)
{
   int p = MathMax(1, length);
   if(i + p >= total || !_valid(src[i]) || !_valid(src[i + p]))
      return EMPTY_VALUE;
   return src[i] - src[i + p];
}

double _percentrank_value(const double &src[], int i, int total, int length)
{
   int p = MathMax(1, length);
   int last = MathMin(total - 1, i + p - 1);
   if(!_valid(src[i]))
      return EMPTY_VALUE;
   int count = 0;
   int ranked = 0;
   for(int j = i; j <= last; j++)
   {
      if(!_valid(src[j]))
         continue;
      count++;
      if(src[j] <= src[i])
         ranked++;
   }
   if(count <= 0)
      return EMPTY_VALUE;
   return 100.0 * ranked / count;
}

void _ema_series(const double &src[], double &dst[], int total, int length)
{
   int p = MathMax(1, length);
   double alpha = 2.0 / (p + 1.0);
   double prev = EMPTY_VALUE;
   for(int i = total - 1; i >= 0; i--)
   {
      if(!_valid(src[i]))
      {
         dst[i] = EMPTY_VALUE;
         continue;
      }
      if(!_valid(prev))
         dst[i] = src[i];
      else
         dst[i] = alpha * src[i] + (1.0 - alpha) * prev;
      prev = dst[i];
   }
}

void _rma_series(const double &src[], double &dst[], int total, int length)
{
   int p = MathMax(1, length);
   double prev = EMPTY_VALUE;
   for(int i = total - 1; i >= 0; i--)
   {
      if(!_valid(src[i]))
      {
         dst[i] = EMPTY_VALUE;
         continue;
      }
      if(!_valid(prev))
         dst[i] = _sma_value(src, i, total, p);
      else
         dst[i] = (prev * (p - 1) + src[i]) / p;
      prev = dst[i];
   }
}

void _basic_ma_series(
   const double &src[],
   double &dst[],
   int total,
   int length,
   RteSmoothingType smoothType,
   const long &tick_volume[]
)
{
   for(int i = total - 1; i >= 0; i--)
   {
      if(smoothType == SmoothSMA)
         dst[i] = _sma_value(src, i, total, length);
      else if(smoothType == SmoothWMA)
         dst[i] = _wma_value(src, i, total, length);
      else if(smoothType == SmoothVWMA)
         dst[i] = _vwma_value(src, tick_volume, i, total, length);
      else if(smoothType == SmoothSWMA)
         dst[i] = _swma_value(src, i, total);
      else if(smoothType == SmoothHighLow)
         dst[i] = _highlow_value(src, i, total, length);
      else if(smoothType == SmoothLinReg)
         dst[i] = _linreg_value(src, i, total, length);
      else if(smoothType == SmoothMedian)
         dst[i] = _median_value(src, i, total, length);
      else if(smoothType == SmoothMomentum)
         dst[i] = _momentum_value(src, i, total, length);
      else if(smoothType == SmoothPercentRank)
         dst[i] = _percentrank_value(src, i, total, length);
      else
         dst[i] = src[i];
   }
}

void _ma_series(
   const double &src[],
   double &dst[],
   int total,
   int length,
   RteSmoothingType smoothType,
   const long &tick_volume[]
)
{
   int p = MathMax(1, length);
   if(p <= 1)
   {
      for(int i = total - 1; i >= 0; i--)
         dst[i] = src[i];
      return;
   }

   if(smoothType == SmoothEMA)
   {
      _ema_series(src, dst, total, p);
      return;
   }
   if(smoothType == SmoothRMA)
   {
      _rma_series(src, dst, total, p);
      return;
   }
   if(smoothType == SmoothHMA)
   {
      int half = MathMax(1, p / 2);
      int root = MathMax(1, (int)MathRound(MathSqrt(p)));
      _basic_ma_series(src, g_temp1, total, half, SmoothWMA, tick_volume);
      _basic_ma_series(src, g_temp2, total, p, SmoothWMA, tick_volume);
      for(int h = total - 1; h >= 0; h--)
      {
         if(_valid(g_temp1[h]) && _valid(g_temp2[h]))
            g_temp1[h] = 2.0 * g_temp1[h] - g_temp2[h];
         else
            g_temp1[h] = EMPTY_VALUE;
      }
      _basic_ma_series(g_temp1, dst, total, root, SmoothWMA, tick_volume);
      return;
   }

   _basic_ma_series(src, dst, total, p, smoothType, tick_volume);
}

bool _cross_over(double currentA, double currentB, double prevA, double prevB)
{
   if(!_valid(currentA) || !_valid(currentB) || !_valid(prevA) || !_valid(prevB))
      return false;
   return currentA > currentB && prevA <= prevB;
}

bool _cross_under(double currentA, double currentB, double prevA, double prevB)
{
   if(!_valid(currentA) || !_valid(currentB) || !_valid(prevA) || !_valid(prevB))
      return false;
   return currentA < currentB && prevA >= prevB;
}

int OnInit()
{
   IndicatorShortName("CatchingWhereToStop - %R Trend Exhaustion");

   SetIndexBuffer(0, LongSignalBuffer);
   SetIndexBuffer(1, ShortSignalBuffer);
   SetIndexBuffer(2, LongArrowBuffer);
   SetIndexBuffer(3, ShortArrowBuffer);
   SetIndexBuffer(4, FastRBuffer);
   SetIndexBuffer(5, SlowRBuffer);
   SetIndexBuffer(6, AvgRBuffer);
   SetIndexBuffer(7, DebugEventBuffer);

   ArraySetAsSeries(LongSignalBuffer, true);
   ArraySetAsSeries(ShortSignalBuffer, true);
   ArraySetAsSeries(LongArrowBuffer, true);
   ArraySetAsSeries(ShortArrowBuffer, true);
   ArraySetAsSeries(FastRBuffer, true);
   ArraySetAsSeries(SlowRBuffer, true);
   ArraySetAsSeries(AvgRBuffer, true);
   ArraySetAsSeries(DebugEventBuffer, true);

   SetIndexStyle(0, DRAW_NONE);
   SetIndexStyle(1, DRAW_NONE);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 1, clrDodgerBlue);
   SetIndexArrow(2, 233);
   SetIndexStyle(3, DRAW_ARROW, STYLE_SOLID, 1, clrRed);
   SetIndexArrow(3, 234);
   SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, 1, clrSilver);
   SetIndexStyle(5, DRAW_LINE, STYLE_SOLID, 1, clrLightSteelBlue);
   SetIndexStyle(6, DRAW_LINE, STYLE_SOLID, 1, clrGold);
   SetIndexStyle(7, DRAW_HISTOGRAM, STYLE_SOLID, 1, clrGray);

   SetIndexLabel(0, "LONG_SIGNAL");
   SetIndexLabel(1, "SHORT_SIGNAL");
   SetIndexLabel(2, "Long Arrow");
   SetIndexLabel(3, "Short Arrow");
   SetIndexLabel(4, "Fast Period %R");
   SetIndexLabel(5, "Slow Period %R");
   SetIndexLabel(6, "Average Formula %R");
   SetIndexLabel(7, "Debug Event");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);
   SetIndexEmptyValue(4, EMPTY_VALUE);
   SetIndexEmptyValue(5, EMPTY_VALUE);
   SetIndexEmptyValue(6, EMPTY_VALUE);
   SetIndexEmptyValue(7, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
}

int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
)
{
   int total = rates_total;
   if(total <= 0)
      return 0;

   _resize_arrays(total);

   for(int i = total - 1; i >= 0; i--)
   {
      LongSignalBuffer[i] = EMPTY_VALUE;
      ShortSignalBuffer[i] = EMPTY_VALUE;
      LongArrowBuffer[i] = EMPTY_VALUE;
      ShortArrowBuffer[i] = EMPTY_VALUE;
      FastRBuffer[i] = EMPTY_VALUE;
      SlowRBuffer[i] = EMPTY_VALUE;
      AvgRBuffer[i] = EMPTY_VALUE;
      DebugEventBuffer[i] = EMPTY_VALUE;

      g_src[i] = _source_price(i, open, high, low, close);
      g_fastRaw[i] = _percent_r(i, total, InpFastLength);
      g_slowRaw[i] = _percent_r(i, total, InpSlowLength);
      if(_valid(g_fastRaw[i]) && _valid(g_slowRaw[i]))
         g_avgRaw[i] = (g_fastRaw[i] + g_slowRaw[i]) / 2.0;
      else
         g_avgRaw[i] = EMPTY_VALUE;
   }

   if(InpFastSmoothingLength > 1)
      _ma_series(g_fastRaw, g_fastR, total, InpFastSmoothingLength, InpSmoothingType, tick_volume);
   else
      for(int fs = total - 1; fs >= 0; fs--)
         g_fastR[fs] = g_fastRaw[fs];

   if(InpSlowSmoothingLength > 1)
      _ma_series(g_slowRaw, g_slowR, total, InpSlowSmoothingLength, InpSmoothingType, tick_volume);
   else
      for(int ls = total - 1; ls >= 0; ls--)
         g_slowR[ls] = g_slowRaw[ls];

   if(InpAverageMa > 1)
      _ma_series(g_avgRaw, g_avgR, total, InpAverageMa, InpSmoothingType, tick_volume);
   else
      for(int av = total - 1; av >= 0; av--)
         g_avgR[av] = g_avgRaw[av];

   int threshold = MathMax(1, MathMin(50, InpThreshold));
   bool useAverage = (InpFormula == FormulaAverage);

   for(int b = total - 1; b >= 0; b--)
   {
      int prev = b + 1;
      bool hasPrev = (prev < total);

      bool overbought = false;
      bool oversold = false;
      bool prevOverbought = false;
      bool prevOversold = false;

      if(useAverage)
      {
         overbought = _valid(g_avgR[b]) && g_avgR[b] >= -threshold;
         oversold = _valid(g_avgR[b]) && g_avgR[b] <= -100 + threshold;
         prevOverbought = hasPrev && _valid(g_avgR[prev]) && g_avgR[prev] >= -threshold;
         prevOversold = hasPrev && _valid(g_avgR[prev]) && g_avgR[prev] <= -100 + threshold;
      }
      else
      {
         overbought = _valid(g_fastR[b]) && _valid(g_slowR[b]) && g_fastR[b] >= -threshold && g_slowR[b] >= -threshold;
         oversold = _valid(g_fastR[b]) && _valid(g_slowR[b]) && g_fastR[b] <= -100 + threshold && g_slowR[b] <= -100 + threshold;
         prevOverbought = hasPrev && _valid(g_fastR[prev]) && _valid(g_slowR[prev]) && g_fastR[prev] >= -threshold && g_slowR[prev] >= -threshold;
         prevOversold = hasPrev && _valid(g_fastR[prev]) && _valid(g_slowR[prev]) && g_fastR[prev] <= -100 + threshold && g_slowR[prev] <= -100 + threshold;
      }

      bool obReversal = (!overbought && prevOverbought);
      bool osReversal = (!oversold && prevOversold);
      bool obTrendStart = (overbought && !prevOverbought);
      bool osTrendStart = (oversold && !prevOversold);

      bool crossZeroLong = false;
      bool crossZeroShort = false;
      bool crossBull = false;
      bool crossBear = false;
      if(hasPrev)
      {
         bool boolCrossLong1 = _cross_over(g_fastR[b], -50.0, g_fastR[prev], -50.0);
         bool boolCrossLong2 = _cross_over(g_slowR[b], -50.0, g_slowR[prev], -50.0);
         bool boolCrossShort1 = _cross_under(g_fastR[b], -50.0, g_fastR[prev], -50.0);
         bool boolCrossShort2 = _cross_under(g_slowR[b], -50.0, g_slowR[prev], -50.0);
         crossZeroLong = (boolCrossLong1 || boolCrossLong2);
         crossZeroShort = (boolCrossShort1 || boolCrossShort2);
         crossBull = _cross_under(g_slowR[b], g_fastR[b], g_slowR[prev], g_fastR[prev]);
         crossBear = _cross_over(g_slowR[b], g_fastR[b], g_slowR[prev], g_fastR[prev]);
      }

      bool zeroLong = _valid(g_fastR[b]) && _valid(g_slowR[b]) && g_fastR[b] > -50.0 && g_slowR[b] > -50.0 && crossZeroLong;
      bool zeroShort = _valid(g_fastR[b]) && _valid(g_slowR[b]) && g_fastR[b] < -50.0 && g_slowR[b] < -50.0 && crossZeroShort;

      bool startLongDeal = false;
      bool startShortDeal = false;

      if(InpStrategyEntry == StrategyTrendFollowingAtSquare)
      {
         if(obTrendStart && InpLongDealsEnabled)
            startLongDeal = true;
         else if(osTrendStart && InpShortDealsEnabled)
            startShortDeal = true;
      }
      else if(InpStrategyEntry == StrategyReversalAtSquare)
      {
         if(osTrendStart && InpLongDealsEnabled)
            startLongDeal = true;
         else if(obTrendStart && InpShortDealsEnabled)
            startShortDeal = true;
      }
      else if(InpStrategyEntry == StrategyReversalTradeAtTriangle)
      {
         if(obReversal && InpShortDealsEnabled)
            startShortDeal = true;
         else if(osReversal && InpLongDealsEnabled)
            startLongDeal = true;
      }
      else if(InpStrategyEntry == StrategyReEnterTrendTradeAtTriangle)
      {
         if(osReversal && InpShortDealsEnabled)
            startShortDeal = true;
         else if(obReversal && InpLongDealsEnabled)
            startLongDeal = true;
      }
      else if(InpStrategyEntry == StrategyPings)
      {
         if(crossBull && InpLongDealsEnabled)
            startLongDeal = true;
         else if(crossBear && InpShortDealsEnabled)
            startShortDeal = true;
      }
      else if(InpStrategyEntry == StrategyZeroLineCross)
      {
         if(zeroLong && InpLongDealsEnabled)
            startLongDeal = true;
         else if(zeroShort && InpShortDealsEnabled)
            startShortDeal = true;
      }

      if(startLongDeal)
      {
         LongSignalBuffer[b] = 1.0;
         if(InpShowStrategyArrows)
            LongArrowBuffer[b] = -107.0;
      }
      if(startShortDeal)
      {
         ShortSignalBuffer[b] = 1.0;
         if(InpShowStrategyArrows)
            ShortArrowBuffer[b] = 5.0;
      }

      if(InpShowPercentR && !useAverage)
      {
         FastRBuffer[b] = g_fastR[b];
         SlowRBuffer[b] = g_slowR[b];
      }
      if(InpShowAverage && useAverage)
         AvgRBuffer[b] = g_avgR[b];

      if(InpShowDebugEvents)
      {
         if(obTrendStart)
            DebugEventBuffer[b] = 0.0;
         else if(osTrendStart)
            DebugEventBuffer[b] = -100.0;
         else if(obReversal)
            DebugEventBuffer[b] = 5.0;
         else if(osReversal)
            DebugEventBuffer[b] = -107.0;
      }
   }

   return rates_total;
}
