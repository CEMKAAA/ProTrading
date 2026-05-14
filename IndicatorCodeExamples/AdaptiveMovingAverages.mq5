//+------------------------------------------------------------------+
//| AdaptiveMovingAverages.mq5                                      |
//| MT5 port of Zeiierman Adaptive Moving Average signal logic.      |
//| Automation buffers: Buffer 0 = BUY(1.0), Buffer 1 = SELL(1.0).   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 5
#property indicator_buffers 5
#property indicator_color1 clrNONE
#property indicator_color2 clrNONE
#property indicator_color3 clrLime
#property indicator_color4 clrRed
#property indicator_color5 clrDodgerBlue
#property indicator_width3 2
#property indicator_width4 2
#property indicator_width5 2

input int    InpERPeriod = 15;
input int    InpFastEMALength = 5;
input int    InpSlowEMALength = 50;
input double InpSignalGamma = 0.15;
input bool   InpSignalWithCandleTrend = true;
input bool   InpAMACandles = false;
input int    InpSlopeLength = 3;
input double InpScoreThreshold = 0.60;
input bool   InpShowAMA = true;
input bool   InpShowSignals = true;
input double InpArrowAtrOffset = 0.60;

double BuySignalBuffer[];
double SellSignalBuffer[];
double BuyArrowBuffer[];
double SellArrowBuffer[];
double AmaBuffer[];

double g_er[];
double g_sc[];
double g_ama[];
double g_sigma[];
double g_filter[];
double g_up[];
double g_dn[];
double g_hCandleRaw[];
double g_hCandleEma[];
double g_hInitial[];
double g_signState[];
double g_atr14[];
int    g_longCond[];
int    g_shortCond[];
int    g_signalUp[];
int    g_signalDn[];

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

void _resize_work_arrays(int total)
{
   ArrayResize(g_er, total);
   ArrayResize(g_sc, total);
   ArrayResize(g_ama, total);
   ArrayResize(g_sigma, total);
   ArrayResize(g_filter, total);
   ArrayResize(g_up, total);
   ArrayResize(g_dn, total);
   ArrayResize(g_hCandleRaw, total);
   ArrayResize(g_hCandleEma, total);
   ArrayResize(g_hInitial, total);
   ArrayResize(g_signState, total);
   ArrayResize(g_atr14, total);
   ArrayResize(g_longCond, total);
   ArrayResize(g_shortCond, total);
   ArrayResize(g_signalUp, total);
   ArrayResize(g_signalDn, total);

   ArraySetAsSeries(g_er, true);
   ArraySetAsSeries(g_sc, true);
   ArraySetAsSeries(g_ama, true);
   ArraySetAsSeries(g_sigma, true);
   ArraySetAsSeries(g_filter, true);
   ArraySetAsSeries(g_up, true);
   ArraySetAsSeries(g_dn, true);
   ArraySetAsSeries(g_hCandleRaw, true);
   ArraySetAsSeries(g_hCandleEma, true);
   ArraySetAsSeries(g_hInitial, true);
   ArraySetAsSeries(g_signState, true);
   ArraySetAsSeries(g_atr14, true);
   ArraySetAsSeries(g_longCond, true);
   ArraySetAsSeries(g_shortCond, true);
   ArraySetAsSeries(g_signalUp, true);
   ArraySetAsSeries(g_signalDn, true);
}

double _highest_array(const double &arr[], int total, int shift, int length)
{
   if(shift + length - 1 >= total)
      return EMPTY_VALUE;
   double v = arr[shift];
   if(!_valid(v))
      return EMPTY_VALUE;
   for(int k = 1; k < length; k++)
   {
      if(!_valid(arr[shift + k]))
         return EMPTY_VALUE;
      v = MathMax(v, arr[shift + k]);
   }
   return v;
}

double _lowest_array(const double &arr[], int total, int shift, int length)
{
   if(shift + length - 1 >= total)
      return EMPTY_VALUE;
   double v = arr[shift];
   if(!_valid(v))
      return EMPTY_VALUE;
   for(int k = 1; k < length; k++)
   {
      if(!_valid(arr[shift + k]))
         return EMPTY_VALUE;
      v = MathMin(v, arr[shift + k]);
   }
   return v;
}

double _stdev_population(const double &arr[], int total, int shift, int length)
{
   if(shift + length - 1 >= total)
      return EMPTY_VALUE;

   double sum = 0.0;
   for(int k = 0; k < length; k++)
   {
      if(!_valid(arr[shift + k]))
         return EMPTY_VALUE;
      sum += arr[shift + k];
   }
   double mean = sum / length;
   double var = 0.0;
   for(int j = 0; j < length; j++)
   {
      double d = arr[shift + j] - mean;
      var += d * d;
   }
   return MathSqrt(var / length);
}

void _compute_atr14(
   int total,
   const double &high[],
   const double &low[],
   const double &close[]
)
{
   const int period = 14;
   double sumTr = 0.0;
   for(int i = total - 1; i >= 0; i--)
   {
      int barIndex = total - 1 - i;
      double prevClose = (i < total - 1) ? close[i + 1] : close[i];
      double tr = _max3(high[i] - low[i], MathAbs(high[i] - prevClose), MathAbs(low[i] - prevClose));
      if(barIndex < period - 1)
      {
         sumTr += tr;
         g_atr14[i] = EMPTY_VALUE;
      }
      else if(barIndex == period - 1)
      {
         sumTr += tr;
         g_atr14[i] = sumTr / period;
      }
      else
      {
         g_atr14[i] = (g_atr14[i + 1] * (period - 1) + tr) / period;
      }
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

bool _condition_loop(const int &cond[], int total, int shift)
{
   for(int i = 1; i <= 20; i++)
   {
      int idx = shift + i;
      if(idx < total && cond[idx] != 0)
         return false;
   }
   return true;
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "AdaptiveMovingAverages AMA Signals");

   SetIndexBuffer(0, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, BuyArrowBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, SellArrowBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, AmaBuffer, INDICATOR_DATA);

   ArraySetAsSeries(BuySignalBuffer, true);
   ArraySetAsSeries(SellSignalBuffer, true);
   ArraySetAsSeries(BuyArrowBuffer, true);
   ArraySetAsSeries(SellArrowBuffer, true);
   ArraySetAsSeries(AmaBuffer, true);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_LINE);

   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, clrLime);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, clrDodgerBlue);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, 2);
   PlotIndexSetInteger(3, PLOT_LINE_WIDTH, 2);
   PlotIndexSetInteger(4, PLOT_LINE_WIDTH, 2);

   PlotIndexSetString(0, PLOT_LABEL, "BUY_SIGNAL");
   PlotIndexSetString(1, PLOT_LABEL, "SELL_SIGNAL");
   PlotIndexSetString(2, PLOT_LABEL, "Buy Signal");
   PlotIndexSetString(3, PLOT_LABEL, "Sell Signal");
   PlotIndexSetString(4, PLOT_LABEL, "AMA");

   for(int i = 0; i < 5; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

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
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int n = MathMax(1, InpERPeriod);
   int fastLen = MathMax(1, InpFastEMALength);
   int slowLen = MathMax(1, InpSlowEMALength);
   int slopeLen = MathMax(1, InpSlopeLength);
   int minBars = MathMax(MathMax(n + 25, 80), slopeLen + 25);
   if(rates_total < minBars)
      return 0;

   _resize_work_arrays(rates_total);
   _compute_atr14(rates_total, high, low, close);

   double fastest = 2.0 / (fastLen + 1.0);
   double slowest = 2.0 / (slowLen + 1.0);
   double emaAlpha2 = 2.0 / 3.0;
   int candleLength = 50;

   for(int i = rates_total - 1; i >= 0; i--)
   {
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      BuyArrowBuffer[i] = EMPTY_VALUE;
      SellArrowBuffer[i] = EMPTY_VALUE;
      AmaBuffer[i] = EMPTY_VALUE;

      g_er[i] = EMPTY_VALUE;
      g_sc[i] = EMPTY_VALUE;
      g_ama[i] = EMPTY_VALUE;
      g_sigma[i] = EMPTY_VALUE;
      g_filter[i] = EMPTY_VALUE;
      g_up[i] = EMPTY_VALUE;
      g_dn[i] = EMPTY_VALUE;
      g_hCandleRaw[i] = EMPTY_VALUE;
      g_hCandleEma[i] = EMPTY_VALUE;
      g_hInitial[i] = EMPTY_VALUE;
      g_longCond[i] = 0;
      g_shortCond[i] = 0;
      g_signalUp[i] = 0;
      g_signalDn[i] = 0;

      if(i + n >= rates_total)
      {
         g_er[i] = 0.0;
      }
      else
      {
         double change = MathAbs(close[i] - close[i + n]);
         double volatility = 0.0;
         for(int k = 0; k < n; k++)
            volatility += MathAbs(close[i + k] - close[i + k + 1]);
         g_er[i] = (volatility != 0.0) ? change / volatility : 0.0;
      }

      g_sc[i] = MathPow(g_er[i] * (fastest - slowest) + slowest, 2.0);
      if(i == rates_total - 1 || !_valid(g_ama[i + 1]))
         g_ama[i] = close[i];
      else
         g_ama[i] = g_ama[i + 1] + g_sc[i] * (close[i] - g_ama[i + 1]);

      g_sigma[i] = _stdev_population(g_ama, rates_total, i, n);
      if(_valid(g_sigma[i]))
         g_filter[i] = InpSignalGamma * g_sigma[i];

      if(InpShowAMA)
         AmaBuffer[i] = g_ama[i];

      if(_valid(g_sigma[i]))
      {
         double hs[5];
         double ls[5];
         bool ok5 = true;
         for(int q = 0; q < 5; q++)
         {
            int idx = i + q;
            if(idx >= rates_total || !_valid(g_sigma[idx]))
            {
               ok5 = false;
               break;
            }
            hs[q] = high[idx] + g_sigma[idx];
            ls[q] = low[idx] - g_sigma[idx];
         }
         if(ok5)
         {
            g_up[i] = hs[0];
            g_dn[i] = ls[0];
            for(int qh = 1; qh < 5; qh++)
            {
               g_up[i] = MathMax(g_up[i], hs[qh]);
               g_dn[i] = MathMin(g_dn[i], ls[qh]);
            }
         }
      }

      if(InpAMACandles && _valid(g_up[i]) && _valid(g_dn[i]) && i + candleLength - 1 < rates_total)
      {
         double donHigh = _highest_array(g_up, rates_total, i, candleLength);
         double donLow = _lowest_array(g_dn, rates_total, i, candleLength);
         double range = donHigh - donLow;
         double norm = (range != 0.0) ? (close[i] - donLow) / range : 0.0;
         double prevInitial = (i < rates_total - 1 && _valid(g_hInitial[i + 1])) ? g_hInitial[i + 1] : close[i];

         g_hInitial[i] = norm * close[i] + (1.0 - norm * 2.0) * prevInitial;
         double factor = (1.0 - norm / 2.0) * prevInitial;
         g_hCandleRaw[i] = norm * high[i] + factor;
         if(i == rates_total - 1 || !_valid(g_hCandleEma[i + 1]))
            g_hCandleEma[i] = g_hCandleRaw[i];
         else
            g_hCandleEma[i] = emaAlpha2 * g_hCandleRaw[i] + (1.0 - emaAlpha2) * g_hCandleEma[i + 1];
      }

      bool baseBull = false;
      if(InpAMACandles && _valid(g_hCandleEma[i]))
         baseBull = (g_hCandleEma[i] > open[i]) || (g_hCandleEma[i] > high[i]) || (g_hCandleEma[i] > low[i]) || (g_hCandleEma[i] > close[i]);
      bool baseBear = !baseBull;

      double amaSlope = (i + slopeLen < rates_total && _valid(g_ama[i + slopeLen])) ? (g_ama[i] - g_ama[i + slopeLen]) : 0.0;
      double safeSigma = MathMax(_valid(g_sigma[i]) ? g_sigma[i] : 0.0, 0.000001);
      double slopeNorm = MathMin(MathAbs(amaSlope) / safeSigma, 1.0);
      double distNorm = MathMin(MathAbs(close[i] - g_ama[i]) / safeSigma, 1.0);
      double erNorm = MathMin(MathMax(_valid(g_er[i]) ? g_er[i] : 0.0, 0.0), 1.0);

      double bullScore = ((amaSlope > 0.0) ? slopeNorm * 0.55 : 0.0)
         + ((close[i] > g_ama[i]) ? ((distNorm * 0.6 + erNorm * 0.4) * 0.30) : 0.0)
         + (baseBull ? 0.15 : 0.0);
      double bearScore = ((amaSlope < 0.0) ? slopeNorm * 0.55 : 0.0)
         + ((close[i] < g_ama[i]) ? ((distNorm * 0.6 + erNorm * 0.4) * 0.30) : 0.0)
         + (baseBear ? 0.15 : 0.0);

      double prevSign = (i < rates_total - 1 && _valid(g_signState[i + 1])) ? g_signState[i + 1] : 0.0;
      if(bullScore >= InpScoreThreshold && bullScore > bearScore)
         g_signState[i] = 1.0;
      else if(bearScore >= InpScoreThreshold && bearScore > bullScore)
         g_signState[i] = -1.0;
      else
         g_signState[i] = prevSign;
   }

   for(int s = rates_total - 2; s >= 0; s--)
   {
      if(!_valid(g_ama[s]) || !_valid(g_ama[s + 1]) || !_valid(g_filter[s]))
         continue;

      double longLineNow = g_ama[s + 1] - g_filter[s];
      double shortLineNow = g_ama[s + 1] + g_filter[s];
      double longLinePrev = (s + 2 < rates_total && _valid(g_filter[s + 1])) ? (g_ama[s + 2] - g_filter[s + 1]) : EMPTY_VALUE;
      double shortLinePrev = (s + 2 < rates_total && _valid(g_filter[s + 1])) ? (g_ama[s + 2] + g_filter[s + 1]) : EMPTY_VALUE;

      g_longCond[s] = _cross_over(g_ama[s], longLineNow, g_ama[s + 1], longLinePrev) ? 1 : 0;
      g_shortCond[s] = _cross_under(g_ama[s], shortLineNow, g_ama[s + 1], shortLinePrev) ? 1 : 0;
   }

   for(int s2 = rates_total - 2; s2 >= 0; s2--)
   {
      bool longFilterOk = _condition_loop(g_longCond, rates_total, s2);
      bool shortFilterOk = _condition_loop(g_shortCond, rates_total, s2);

      g_signalUp[s2] = (g_longCond[s2] != 0 && longFilterOk) ? 1 : 0;
      g_signalDn[s2] = (g_shortCond[s2] != 0 && shortFilterOk) ? 1 : 0;

      bool candleTrendBull = (g_signState[s2] == 1.0);
      bool candleTrendBear = (g_signState[s2] == -1.0);
      bool displaySignalUp = (g_signalUp[s2] != 0) && (!InpSignalWithCandleTrend || candleTrendBull);
      bool displaySignalDn = (g_signalDn[s2] != 0) && (!InpSignalWithCandleTrend || candleTrendBear);

      double atr = _valid(g_atr14[s2]) ? g_atr14[s2] : 0.0;
      if(displaySignalUp)
      {
         BuySignalBuffer[s2] = 1.0;
         if(InpShowSignals)
            BuyArrowBuffer[s2] = low[s2] - atr * InpArrowAtrOffset;
      }
      if(displaySignalDn)
      {
         SellSignalBuffer[s2] = 1.0;
         if(InpShowSignals)
            SellArrowBuffer[s2] = high[s2] + atr * InpArrowAtrOffset;
      }
   }

   return rates_total;
}
