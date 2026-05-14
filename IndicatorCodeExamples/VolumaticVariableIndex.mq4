//+------------------------------------------------------------------+
//| VolumaticVariableIndex.mq4                                       |
//| MT4 port of BigBeluga Volumatic VIDYA trend signal logic.        |
//| Automation buffers: Buffer 0 = BUY(1.0), Buffer 1 = SELL(1.0).   |
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
#property indicator_width5  2
#property indicator_width6  2

enum VVIDSource
{
   SourceClose = 0,
   SourceOpen = 1,
   SourceHigh = 2,
   SourceLow = 3,
   SourceHL2 = 4,
   SourceHLC3 = 5,
   SourceOHLC4 = 6
};

input int        InpVidyaLength = 10;
input int        InpVidyaMomentum = 20;
input double     InpBandDistance = 2.0;
input VVIDSource InpSource = SourceClose;
input bool       InpShowTrendLine = true;
input bool       InpShowSignals = true;
input double     InpArrowAtrOffset = 0.20;

double BuySignalBuffer[];
double SellSignalBuffer[];
double BuyArrowBuffer[];
double SellArrowBuffer[];
double TrendUpBuffer[];
double TrendDownBuffer[];

double g_src[];
double g_momentum[];
double g_vidyaRaw[];
double g_vidyaSma[];
double g_atr[];
double g_upperBand[];
double g_lowerBand[];
double g_smoothed[];
int    g_trendUp[];
int    g_trendCrossUp[];
int    g_trendCrossDown[];

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
   ArrayResize(g_momentum, total);
   ArrayResize(g_vidyaRaw, total);
   ArrayResize(g_vidyaSma, total);
   ArrayResize(g_atr, total);
   ArrayResize(g_upperBand, total);
   ArrayResize(g_lowerBand, total);
   ArrayResize(g_smoothed, total);
   ArrayResize(g_trendUp, total);
   ArrayResize(g_trendCrossUp, total);
   ArrayResize(g_trendCrossDown, total);

   ArraySetAsSeries(g_src, true);
   ArraySetAsSeries(g_momentum, true);
   ArraySetAsSeries(g_vidyaRaw, true);
   ArraySetAsSeries(g_vidyaSma, true);
   ArraySetAsSeries(g_atr, true);
   ArraySetAsSeries(g_upperBand, true);
   ArraySetAsSeries(g_lowerBand, true);
   ArraySetAsSeries(g_smoothed, true);
   ArraySetAsSeries(g_trendUp, true);
   ArraySetAsSeries(g_trendCrossUp, true);
   ArraySetAsSeries(g_trendCrossDown, true);
}

void _compute_source(
   int total,
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[]
)
{
   for(int i = total - 1; i >= 0; i--)
      g_src[i] = _source_price(i, open, high, low, close);
}

void _compute_atr_like_pine(
   int total,
   const double &high[],
   const double &low[],
   const double &close[]
)
{
   const int period = 200;
   double sumTr = 0.0;

   for(int i = total - 1; i >= 0; i--)
   {
      int barIndex = total - 1 - i;
      double prevClose = (i < total - 1) ? close[i + 1] : close[i];
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

void _compute_vidya(int total)
{
   int vidyaLength = MathMax(1, InpVidyaLength);
   int momentumLength = MathMax(1, InpVidyaMomentum);
   double alpha = 2.0 / (vidyaLength + 1.0);

   for(int i = total - 1; i >= 0; i--)
   {
      g_momentum[i] = (i < total - 1) ? (g_src[i] - g_src[i + 1]) : 0.0;

      double sumPos = 0.0;
      double sumNeg = 0.0;
      for(int k = 0; k < momentumLength; k++)
      {
         int idx = i + k;
         if(idx >= total)
            break;
         double mom = g_momentum[idx];
         if(mom >= 0.0)
            sumPos += mom;
         else
            sumNeg += -mom;
      }

      double denom = sumPos + sumNeg;
      double absCmo = (denom > 0.0) ? MathAbs(100.0 * (sumPos - sumNeg) / denom) : 0.0;
      double factor = alpha * absCmo / 100.0;
      double prevVidya = (i < total - 1 && _valid(g_vidyaRaw[i + 1])) ? g_vidyaRaw[i + 1] : 0.0;
      g_vidyaRaw[i] = factor * g_src[i] + (1.0 - factor) * prevVidya;

      if(i + 14 >= total)
      {
         g_vidyaSma[i] = EMPTY_VALUE;
      }
      else
      {
         double sum = 0.0;
         for(int j = 0; j < 15; j++)
            sum += g_vidyaRaw[i + j];
         g_vidyaSma[i] = sum / 15.0;
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

int OnInit()
{
   IndicatorShortName("VolumaticVariableIndex VIDYA");

   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexBuffer(2, BuyArrowBuffer);
   SetIndexBuffer(3, SellArrowBuffer);
   SetIndexBuffer(4, TrendUpBuffer);
   SetIndexBuffer(5, TrendDownBuffer);

   ArraySetAsSeries(BuySignalBuffer, true);
   ArraySetAsSeries(SellSignalBuffer, true);
   ArraySetAsSeries(BuyArrowBuffer, true);
   ArraySetAsSeries(SellArrowBuffer, true);
   ArraySetAsSeries(TrendUpBuffer, true);
   ArraySetAsSeries(TrendDownBuffer, true);

   SetIndexStyle(0, DRAW_NONE);
   SetIndexStyle(1, DRAW_NONE);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 2, clrLime);
   SetIndexStyle(3, DRAW_ARROW, STYLE_SOLID, 2, clrRed);
   SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, 2, clrLime);
   SetIndexStyle(5, DRAW_LINE, STYLE_SOLID, 2, clrRed);

   SetIndexArrow(2, 233);
   SetIndexArrow(3, 234);

   SetIndexLabel(0, "BUY_SIGNAL");
   SetIndexLabel(1, "SELL_SIGNAL");
   SetIndexLabel(2, "Trend Up");
   SetIndexLabel(3, "Trend Down");
   SetIndexLabel(4, "VIDYA Up Trend");
   SetIndexLabel(5, "VIDYA Down Trend");

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
   if(rates_total < 220)
      return 0;

   _resize_work_arrays(rates_total);
   _compute_source(rates_total, open, high, low, close);
   _compute_atr_like_pine(rates_total, high, low, close);
   _compute_vidya(rates_total);

   for(int i = rates_total - 1; i >= 0; i--)
   {
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      BuyArrowBuffer[i] = EMPTY_VALUE;
      SellArrowBuffer[i] = EMPTY_VALUE;
      TrendUpBuffer[i] = EMPTY_VALUE;
      TrendDownBuffer[i] = EMPTY_VALUE;
      g_upperBand[i] = EMPTY_VALUE;
      g_lowerBand[i] = EMPTY_VALUE;
      g_smoothed[i] = EMPTY_VALUE;
      g_trendUp[i] = 0;
      g_trendCrossUp[i] = 0;
      g_trendCrossDown[i] = 0;

      if(!_valid(g_vidyaSma[i]) || !_valid(g_atr[i]))
         continue;

      g_upperBand[i] = g_vidyaSma[i] + g_atr[i] * InpBandDistance;
      g_lowerBand[i] = g_vidyaSma[i] - g_atr[i] * InpBandDistance;

      int prevTrend = (i < rates_total - 1) ? g_trendUp[i + 1] : 0;
      double prevSrc = (i < rates_total - 1) ? g_src[i + 1] : EMPTY_VALUE;
      double prevUpper = (i < rates_total - 1) ? g_upperBand[i + 1] : EMPTY_VALUE;
      double prevLower = (i < rates_total - 1) ? g_lowerBand[i + 1] : EMPTY_VALUE;

      bool crossUp = _cross_over(g_src[i], g_upperBand[i], prevSrc, prevUpper);
      bool crossDown = _cross_under(g_src[i], g_lowerBand[i], prevSrc, prevLower);

      int trend = prevTrend;
      if(crossUp)
         trend = 1;
      if(crossDown)
         trend = 0;
      g_trendUp[i] = trend;

      bool changed = (i < rates_total - 1 && trend != prevTrend);
      if(trend == 1)
         g_smoothed[i] = g_lowerBand[i];
      else
         g_smoothed[i] = g_upperBand[i];
      if(changed)
         g_smoothed[i] = EMPTY_VALUE;

      g_trendCrossUp[i] = (prevTrend == 0 && trend == 1) ? 1 : 0;
      g_trendCrossDown[i] = (trend == 0 && prevTrend == 1) ? 1 : 0;

      if(InpShowTrendLine && _valid(g_smoothed[i]))
      {
         if(trend == 1)
            TrendUpBuffer[i] = g_smoothed[i];
         else
            TrendDownBuffer[i] = g_smoothed[i];
      }
   }

   for(int s = rates_total - 1; s >= 0; s--)
   {
      if(s + 1 >= rates_total)
         continue;
      if(!_valid(g_smoothed[s]))
         continue;

      double atrOffset = _valid(g_atr[s]) ? g_atr[s] * InpArrowAtrOffset : 0.0;
      if(g_trendCrossUp[s + 1] == 1)
      {
         BuySignalBuffer[s] = 1.0;
         if(InpShowSignals)
            BuyArrowBuffer[s] = g_smoothed[s] - atrOffset;
      }
      if(g_trendCrossDown[s + 1] == 1)
      {
         SellSignalBuffer[s] = 1.0;
         if(InpShowSignals)
            SellArrowBuffer[s] = g_smoothed[s] + atrOffset;
      }
   }

   return rates_total;
}
