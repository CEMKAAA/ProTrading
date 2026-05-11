//+------------------------------------------------------------------+
//| VeryPromisingIndicator_HistorySafe.mq4                           |
//| MT4 port of the supplied TradingView Pine Q-Trend indicator.     |
//| Automation buffers: Buffer 0 = BUY(1.0), Buffer 1 = SELL(1.0).   |
//| This test build keeps the same signal logic but limits plotting  |
//| to a fixed visible window after a hidden warmup window.           |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1  clrNONE
#property indicator_color2  clrNONE
#property indicator_color3  clrLime
#property indicator_color4  clrRed
#property indicator_color5  clrLime
#property indicator_color6  clrRed
#property indicator_width3  2
#property indicator_width4  2
#property indicator_width5  3
#property indicator_width6  3

enum QTrendSource
{
   SourceClose = 0,
   SourceOpen = 1,
   SourceHigh = 2,
   SourceLow = 3,
   SourceHL2 = 4,
   SourceHLC3 = 5,
   SourceOHLC4 = 6
};

enum QTrendSignalMode
{
   Type_A = 0,
   Type_B = 1
};

input QTrendSource     InpSource = SourceClose;
input int              InpTrendPeriod = 200;
input int              InpAtrPeriod = 14;
input double           InpAtrMultiplier = 1.0;
input QTrendSignalMode InpSignalMode = Type_A;
input bool             InpUseEmaSmoother = false;
input int              InpEmaSmootherPeriod = 3;
input bool             InpShowTrendLine = true;
input bool             InpShowSignals = true;
input double           InpArrowAtrOffset = 0.35;
input int              InpVisibleBars = 7200;     // M1: 5 days
input int              InpWarmupBars = 12000;     // hidden state warmup before the visible window

double BuySignalBuffer[];
double SellSignalBuffer[];
double BuyArrowBuffer[];
double SellArrowBuffer[];
double TrendBuyBuffer[];
double TrendSellBuffer[];

double g_src[];
double g_atr[];
double g_baseM[];
double g_m[];
double g_highestSrc[];
double g_lowestSrc[];
int    g_lastSignal[];

double _max3(double a, double b, double c)
{
   return MathMax(a, MathMax(b, c));
}

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

void _resize_work_arrays(int total)
{
   ArrayResize(g_src, total);
   ArrayResize(g_atr, total);
   ArrayResize(g_baseM, total);
   ArrayResize(g_m, total);
   ArrayResize(g_highestSrc, total);
   ArrayResize(g_lowestSrc, total);
   ArrayResize(g_lastSignal, total);

   ArraySetAsSeries(g_src, true);
   ArraySetAsSeries(g_atr, true);
   ArraySetAsSeries(g_baseM, true);
   ArraySetAsSeries(g_m, true);
   ArraySetAsSeries(g_highestSrc, true);
   ArraySetAsSeries(g_lowestSrc, true);
   ArraySetAsSeries(g_lastSignal, true);
}

void _clear_buffers_and_work_arrays(int total)
{
   for(int i = total - 1; i >= 0; i--)
   {
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      BuyArrowBuffer[i] = EMPTY_VALUE;
      SellArrowBuffer[i] = EMPTY_VALUE;
      TrendBuyBuffer[i] = EMPTY_VALUE;
      TrendSellBuffer[i] = EMPTY_VALUE;

      g_src[i] = EMPTY_VALUE;
      g_atr[i] = EMPTY_VALUE;
      g_baseM[i] = EMPTY_VALUE;
      g_m[i] = EMPTY_VALUE;
      g_highestSrc[i] = EMPTY_VALUE;
      g_lowestSrc[i] = EMPTY_VALUE;
      g_lastSignal[i] = 0;
   }
}

void _compute_source_window(
   int total,
   int oldest,
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[]
)
{
   if(oldest < 0 || oldest >= total)
      return;

   int emaPeriod = MathMax(1, InpEmaSmootherPeriod);
   double alpha = 2.0 / (emaPeriod + 1.0);

   for(int i = oldest; i >= 0; i--)
   {
      double raw = _source_price(i, open, high, low, close);
      if(!InpUseEmaSmoother)
      {
         g_src[i] = raw;
         continue;
      }

      if(i == oldest)
         g_src[i] = raw;
      else
         g_src[i] = alpha * raw + (1.0 - alpha) * g_src[i + 1];
   }
}

void _compute_atr_like_pine_window(
   int total,
   int oldest,
   const double &high[],
   const double &low[],
   const double &close[]
)
{
   if(oldest < 0 || oldest >= total)
      return;

   int period = MathMax(1, InpAtrPeriod);
   double sumTr = 0.0;

   for(int i = oldest; i >= 0; i--)
   {
      int barIndex = oldest - i;
      double prevClose = (i < oldest) ? close[i + 1] : close[i];
      double tr = _max3(high[i] - low[i], MathAbs(high[i] - prevClose), MathAbs(low[i] - prevClose));

      if(barIndex < period - 1)
      {
         sumTr += tr;
         g_atr[i] = EMPTY_VALUE;
      }
      else if(barIndex == period - 1)
      {
         sumTr += tr;
         g_atr[i] = sumTr / period;
      }
      else
      {
         g_atr[i] = (g_atr[i + 1] * (period - 1) + tr) / period;
      }
   }
}

void _compute_highest_lowest_src_window(int total, int oldest, int period)
{
   if(oldest < 0 || oldest >= total)
      return;

   int p = MathMax(1, period);
   int maxDeque[];
   int minDeque[];
   ArrayResize(maxDeque, total);
   ArrayResize(minDeque, total);

   int maxHead = 0;
   int maxTail = -1;
   int minHead = 0;
   int minTail = -1;

   for(int i = oldest; i >= 0; i--)
   {
      int oldestAllowed = MathMin(oldest, i + p - 1);

      while(maxHead <= maxTail && maxDeque[maxHead] > oldestAllowed)
         maxHead++;
      while(minHead <= minTail && minDeque[minHead] > oldestAllowed)
         minHead++;

      while(maxHead <= maxTail && g_src[maxDeque[maxTail]] <= g_src[i])
         maxTail--;
      maxTail++;
      maxDeque[maxTail] = i;

      while(minHead <= minTail && g_src[minDeque[minTail]] >= g_src[i])
         minTail--;
      minTail++;
      minDeque[minTail] = i;

      g_highestSrc[i] = g_src[maxDeque[maxHead]];
      g_lowestSrc[i] = g_src[minDeque[minHead]];
   }
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

bool _cross_any(double currentA, double currentB, double prevA, double prevB)
{
   return _cross_over(currentA, currentB, prevA, prevB) || _cross_under(currentA, currentB, prevA, prevB);
}

int OnInit()
{
   IndicatorShortName("VeryPromisingIndicator HistorySafe Q-Trend");

   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexBuffer(2, BuyArrowBuffer);
   SetIndexBuffer(3, SellArrowBuffer);
   SetIndexBuffer(4, TrendBuyBuffer);
   SetIndexBuffer(5, TrendSellBuffer);

   ArraySetAsSeries(BuySignalBuffer, true);
   ArraySetAsSeries(SellSignalBuffer, true);
   ArraySetAsSeries(BuyArrowBuffer, true);
   ArraySetAsSeries(SellArrowBuffer, true);
   ArraySetAsSeries(TrendBuyBuffer, true);
   ArraySetAsSeries(TrendSellBuffer, true);

   SetIndexStyle(0, DRAW_NONE);
   SetIndexStyle(1, DRAW_NONE);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 2, clrLime);
   SetIndexStyle(3, DRAW_ARROW, STYLE_SOLID, 2, clrRed);
   SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, 3, clrLime);
   SetIndexStyle(5, DRAW_LINE, STYLE_SOLID, 3, clrRed);

   SetIndexArrow(2, 233);
   SetIndexArrow(3, 234);

   SetIndexLabel(0, "BUY_SIGNAL");
   SetIndexLabel(1, "SELL_SIGNAL");
   SetIndexLabel(2, "BUY");
   SetIndexLabel(3, "SELL");
   SetIndexLabel(4, "Q-Trend BUY Line");
   SetIndexLabel(5, "Q-Trend SELL Line");

   for(int i = 0; i < 6; i++)
      SetIndexEmptyValue(i, EMPTY_VALUE);

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
   if(rates_total < 2)
      return 0;

   int trendPeriod = MathMax(1, InpTrendPeriod);
   int visibleBars = MathMax(100, InpVisibleBars);
   int minimumWarmup = trendPeriod + MathMax(1, InpAtrPeriod) + MathMax(10, InpEmaSmootherPeriod) + 50;
   int warmupBars = MathMax(minimumWarmup, InpWarmupBars);
   int visibleOldest = MathMin(rates_total - 1, visibleBars);
   int calcOldest = MathMin(rates_total - 1, visibleBars + warmupBars);

   _resize_work_arrays(rates_total);
   _clear_buffers_and_work_arrays(rates_total);
   _compute_source_window(rates_total, calcOldest, open, high, low, close);
   _compute_atr_like_pine_window(rates_total, calcOldest, high, low, close);
   _compute_highest_lowest_src_window(rates_total, calcOldest, trendPeriod);

   for(int i = calcOldest; i >= 0; i--)
   {
      double h = g_highestSrc[i];
      double l = g_lowestSrc[i];
      double d = h - l;
      double mid = (h + l) / 2.0;

      int barIndex = calcOldest - i;
      double prevM = (i < calcOldest) ? g_m[i + 1] : EMPTY_VALUE;
      int prevSignal = (i < calcOldest) ? g_lastSignal[i + 1] : 0;

      double baseM = (barIndex > trendPeriod && _valid(prevM)) ? prevM : mid;
      g_baseM[i] = baseM;

      double atrShifted = (i < calcOldest) ? g_atr[i + 1] : EMPTY_VALUE;
      bool hasEpsilon = _valid(atrShifted);
      double epsilon = hasEpsilon ? InpAtrMultiplier * atrShifted : EMPTY_VALUE;

      double upper = hasEpsilon ? baseM + epsilon : EMPTY_VALUE;
      double lower = hasEpsilon ? baseM - epsilon : EMPTY_VALUE;

      double prevSrc = (i < calcOldest) ? g_src[i + 1] : EMPTY_VALUE;
      double prevBaseM = (i < calcOldest) ? g_baseM[i + 1] : EMPTY_VALUE;
      double prevAtrShifted = (i + 2 <= calcOldest) ? g_atr[i + 2] : EMPTY_VALUE;
      double prevUpper = (_valid(prevBaseM) && _valid(prevAtrShifted)) ? prevBaseM + InpAtrMultiplier * prevAtrShifted : EMPTY_VALUE;
      double prevLower = (_valid(prevBaseM) && _valid(prevAtrShifted)) ? prevBaseM - InpAtrMultiplier * prevAtrShifted : EMPTY_VALUE;

      bool typeBCrossUp = _cross_any(g_src[i], upper, prevSrc, prevUpper);
      bool typeBCrossDown = _cross_any(g_src[i], lower, prevSrc, prevLower);
      bool typeACrossUp = _cross_over(g_src[i], upper, prevSrc, prevUpper);
      bool typeACrossDown = _cross_under(g_src[i], lower, prevSrc, prevLower);

      bool changeUp = hasEpsilon && (((InpSignalMode == Type_B) ? typeBCrossUp : typeACrossUp) || g_src[i] > upper);
      bool changeDown = hasEpsilon && (((InpSignalMode == Type_B) ? typeBCrossDown : typeACrossDown) || g_src[i] < lower);

      bool sb = (open[i] < l + d / 8.0) && (open[i] >= l);
      bool ss = (open[i] > h - d / 8.0) && (open[i] <= h);
      bool strongBuy = sb;
      bool strongSell = ss;
      for(int k = 1; k <= 4; k++)
      {
         if(i + k > calcOldest)
            break;
         double hk = g_highestSrc[i + k];
         double lk = g_lowestSrc[i + k];
         double dk = hk - lk;
         if((open[i + k] < lk + dk / 8.0) && (open[i + k] >= lk))
            strongBuy = true;
         if((open[i + k] > hk - dk / 8.0) && (open[i + k] <= hk))
            strongSell = true;
      }

      double nextM = EMPTY_VALUE;
      if((changeUp || changeDown) && _valid(prevM) && baseM != prevM)
         nextM = baseM;
      else if(changeUp)
         nextM = baseM + epsilon;
      else if(changeDown)
         nextM = baseM - epsilon;
      else
         nextM = _valid(prevM) ? prevM : baseM;

      int lastSignal = changeUp ? 1 : (changeDown ? -1 : prevSignal);
      g_m[i] = nextM;
      g_lastSignal[i] = lastSignal;

      bool visible = (i <= visibleOldest);

      if(visible && InpShowTrendLine && _valid(nextM))
      {
         if(lastSignal == 1)
            TrendBuyBuffer[i] = nextM;
         else
            TrendSellBuffer[i] = nextM;
      }

      bool buySignal = changeUp && prevSignal != 1;
      bool sellSignal = changeDown && prevSignal != -1;
      if(visible && buySignal)
      {
         BuySignalBuffer[i] = 1.0;
         if(InpShowSignals)
         {
            double buyGap = MathMax(Point * 10.0, (hasEpsilon ? atrShifted * InpArrowAtrOffset : Point * 10.0));
            BuyArrowBuffer[i] = low[i] - buyGap;
         }
      }
      if(visible && sellSignal)
      {
         SellSignalBuffer[i] = 1.0;
         if(InpShowSignals)
         {
            double sellGap = MathMax(Point * 10.0, (hasEpsilon ? atrShifted * InpArrowAtrOffset : Point * 10.0));
            SellArrowBuffer[i] = high[i] + sellGap;
         }
      }

      // Strong BUY/SELL are intentionally not separate automation states.
      // Pine only changes the plotted label text; alert direction stays BUY/SELL.
      if(strongBuy || strongSell)
      {
      }
   }

   return rates_total;
}
