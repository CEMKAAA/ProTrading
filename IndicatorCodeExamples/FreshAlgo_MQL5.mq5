//+------------------------------------------------------------------+
//| FreshAlgo_MQL5.mq5                                               |
//| Port of IndicatorCodeExamples/FreshAlgo.pine                     |
//| Signal math is intentionally kept aligned with the Pine source.   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 8
#property indicator_buffers 8

#property indicator_label1  "Fresh Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  2

#property indicator_label2  "Fresh Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrSilver
#property indicator_width2  2

#property indicator_label3  "Entry"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrOrange
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

#property indicator_label4  "Stop Loss"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrSilver
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "TP1"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDeepSkyBlue
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

#property indicator_label6  "TP2"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrDeepSkyBlue
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

#property indicator_label7  "TP3"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrDeepSkyBlue
#property indicator_style7  STYLE_DOT
#property indicator_width7  1

#property indicator_label8  "SuperTrend"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrSlateGray
#property indicator_style8  STYLE_SOLID
#property indicator_width8  1

enum FRESH_FILTER_STYLE
{
   FRESH_TRENDING_SIGNALS = 0,
   FRESH_CONTRARIAN_SIGNALS = 1,
   FRESH_HIGH_VOLUME_FILTER = 2,
   FRESH_STRONG_FILTER = 3,
   FRESH_SWING_CLOUD_FILTER = 4,
   FRESH_SMOOTH_CLOUD_FILTER = 5,
   FRESH_SCALPING_CLOUD_FILTER = 6,
   FRESH_SCALPING_PLUS_CLOUD_FILTER = 7
};

input bool   InpShowSignals = true;
input double InpSensitivity = 2.4;
input int    InpSTuner = 10;
input FRESH_FILTER_STYLE InpFilterStyle = FRESH_TRENDING_SIGNALS;
input bool   InpUsePercSL = false;
input double InpPercTrailingSL = 1.0;
input bool   InpUseTP1 = true;
input double InpMultTP1 = 1.0;
input bool   InpUseTP2 = true;
input double InpMultTP2 = 2.0;
input bool   InpUseTP3 = true;
input double InpMultTP3 = 3.0;
input bool   InpShowTpSlAreas = true;
input bool   InpClosedBarOnly = false;

double BuyBuffer[];
double SellBuffer[];
double EntryBuffer[];
double StopBuffer[];
double Tp1Buffer[];
double Tp2Buffer[];
double Tp3Buffer[];
double SuperTrendBuffer[];

double Empty()
{
   return EMPTY_VALUE;
}

bool Valid(const double v)
{
   return MathIsValidNumber(v) && v != EMPTY_VALUE;
}

double Nz(const double v, const double fallback = 0.0)
{
   return Valid(v) ? v : fallback;
}

double TrueRangeAt(const double &h[], const double &l[], const double &c[], const int i)
{
   if(i <= 0)
      return h[i] - l[i];
   double hl = h[i] - l[i];
   double hc = MathAbs(h[i] - c[i - 1]);
   double lc = MathAbs(l[i] - c[i - 1]);
   return MathMax(hl, MathMax(hc, lc));
}

void SMA(const double &src[], const int n, const int len, double &out[])
{
   ArrayResize(out, n);
   double sum = 0.0;
   for(int i = 0; i < n; i++)
   {
      sum += src[i];
      if(i >= len)
         sum -= src[i - len];
      out[i] = (i >= len - 1 ? sum / (double)len : Empty());
   }
}

void EMA(const double &src[], const int n, const int len, double &out[])
{
   ArrayResize(out, n);
   double alpha = 2.0 / ((double)len + 1.0);
   for(int i = 0; i < n; i++)
   {
      if(!Valid(src[i]))
      {
         out[i] = Empty();
         continue;
      }
      if(i == 0 || !Valid(out[i - 1]))
         out[i] = src[i];
      else
         out[i] = alpha * src[i] + (1.0 - alpha) * out[i - 1];
   }
}

void RMA(const double &src[], const int n, const int len, double &out[])
{
   ArrayResize(out, n);
   double sum = 0.0;
   for(int i = 0; i < n; i++)
   {
      out[i] = Empty();
      if(!Valid(src[i]))
      {
         sum = 0.0;
         continue;
      }
      if(i < len)
      {
         sum += src[i];
         if(i == len - 1)
            out[i] = sum / (double)len;
      }
      else
         out[i] = (out[i - 1] * (len - 1) + src[i]) / (double)len;
   }
}

void ATR(const double &h[], const double &l[], const double &c[], const int n, const int len, double &out[])
{
   double tr[];
   ArrayResize(tr, n);
   for(int i = 0; i < n; i++)
      tr[i] = TrueRangeAt(h, l, c, i);
   RMA(tr, n, len, out);
}

void RSI(const double &src[], const int n, const int len, double &out[])
{
   ArrayResize(out, n);
   double up[], down[], upRma[], downRma[];
   ArrayResize(up, n);
   ArrayResize(down, n);
   for(int i = 0; i < n; i++)
   {
      double ch = (i == 0 ? 0.0 : src[i] - src[i - 1]);
      up[i] = MathMax(ch, 0.0);
      down[i] = MathMax(-ch, 0.0);
   }
   RMA(up, n, len, upRma);
   RMA(down, n, len, downRma);
   for(int i = 0; i < n; i++)
   {
      if(!Valid(upRma[i]) || !Valid(downRma[i]))
         out[i] = Empty();
      else if(downRma[i] == 0.0)
         out[i] = 100.0;
      else if(upRma[i] == 0.0)
         out[i] = 0.0;
      else
         out[i] = 100.0 - 100.0 / (1.0 + upRma[i] / downRma[i]);
   }
}

void MACD(const double &src[], const int n, const int fast, const int slow, const int sig, double &macd[], double &signal[], double &hist[])
{
   double ef[], es[];
   EMA(src, n, fast, ef);
   EMA(src, n, slow, es);
   ArrayResize(macd, n);
   for(int i = 0; i < n; i++)
      macd[i] = (Valid(ef[i]) && Valid(es[i])) ? ef[i] - es[i] : Empty();
   EMA(macd, n, sig, signal);
   ArrayResize(hist, n);
   for(int i = 0; i < n; i++)
      hist[i] = (Valid(macd[i]) && Valid(signal[i])) ? macd[i] - signal[i] : Empty();
}

double WMAAt(const double &src[], const int i, const int len)
{
   if(i < len - 1)
      return Empty();
   double num = 0.0, den = 0.0;
   for(int k = 0; k < len; k++)
   {
      int w = len - k;
      double v = src[i - k];
      if(!Valid(v))
         return Empty();
      num += v * (double)w;
      den += (double)w;
   }
   return den == 0.0 ? Empty() : num / den;
}

void HMA(const double &src[], const int n, const int len, double &out[])
{
   ArrayResize(out, n);
   double tmp[];
   ArrayResize(tmp, n);
   int half = MathMax(1, len / 2);
   int root = MathMax(1, (int)MathSqrt((double)len));
   for(int i = 0; i < n; i++)
   {
      double w1 = WMAAt(src, i, half);
      double w2 = WMAAt(src, i, len);
      tmp[i] = (Valid(w1) && Valid(w2)) ? 2.0 * w1 - w2 : Empty();
      out[i] = WMAAt(tmp, i, root);
   }
}

bool Crossover(const double a, const double b, const double pa, const double pb)
{
   return Valid(a) && Valid(b) && Valid(pa) && Valid(pb) && a > b && pa <= pb;
}

bool Crossunder(const double a, const double b, const double pa, const double pb)
{
   return Valid(a) && Valid(b) && Valid(pa) && Valid(pb) && a < b && pa >= pb;
}

void SuperTrend(const double &src[], const double &closeArr[], const double &h[], const double &l[], const int n, const double factor, const int len, double &out[], int &dir[])
{
   double atr[], upper[], lower[];
   ATR(h, l, closeArr, n, len, atr);
   ArrayResize(out, n);
   ArrayResize(dir, n);
   ArrayResize(upper, n);
   ArrayResize(lower, n);

   for(int i = 0; i < n; i++)
   {
      if(!Valid(atr[i]))
      {
         upper[i] = lower[i] = out[i] = Empty();
         dir[i] = 0;
         continue;
      }

      double upperRaw = src[i] + factor * atr[i];
      double lowerRaw = src[i] - factor * atr[i];
      double prevLower = (i > 0 ? Nz(lower[i - 1]) : 0.0);
      double prevUpper = (i > 0 ? Nz(upper[i - 1]) : 0.0);
      lower[i] = (lowerRaw > prevLower || (i > 0 && closeArr[i - 1] < prevLower)) ? lowerRaw : prevLower;
      upper[i] = (upperRaw < prevUpper || (i > 0 && closeArr[i - 1] > prevUpper)) ? upperRaw : prevUpper;

      double prevSuperTrend = (i > 0 ? out[i - 1] : Empty());
      if(Valid(prevSuperTrend) && prevSuperTrend == prevUpper)
         dir[i] = closeArr[i] > upper[i] ? 1 : -1;
      else
         dir[i] = closeArr[i] < lower[i] ? -1 : 1;

      out[i] = dir[i] == 1 ? lower[i] : upper[i];
   }
}

void DMI(const double &h[], const double &l[], const double &c[], const int n, const int diLen, const int adxLen, double &plusDi[], double &minusDi[], double &adx[])
{
   double tr[], pdm[], mdm[], trR[], pdmR[], mdmR[], dx[];
   ArrayResize(tr, n);
   ArrayResize(pdm, n);
   ArrayResize(mdm, n);
   ArrayResize(dx, n);
   ArrayResize(plusDi, n);
   ArrayResize(minusDi, n);
   for(int i = 0; i < n; i++)
   {
      tr[i] = TrueRangeAt(h, l, c, i);
      if(i == 0)
      {
         pdm[i] = 0.0;
         mdm[i] = 0.0;
      }
      else
      {
         double up = h[i] - h[i - 1];
         double dn = l[i - 1] - l[i];
         pdm[i] = (up > dn && up > 0.0) ? up : 0.0;
         mdm[i] = (dn > up && dn > 0.0) ? dn : 0.0;
      }
   }
   RMA(tr, n, diLen, trR);
   RMA(pdm, n, diLen, pdmR);
   RMA(mdm, n, diLen, mdmR);
   for(int i = 0; i < n; i++)
   {
      plusDi[i] = (Valid(trR[i]) && trR[i] != 0.0) ? 100.0 * pdmR[i] / trR[i] : Empty();
      minusDi[i] = (Valid(trR[i]) && trR[i] != 0.0) ? 100.0 * mdmR[i] / trR[i] : Empty();
      double sum = (Valid(plusDi[i]) && Valid(minusDi[i])) ? plusDi[i] + minusDi[i] : 0.0;
      dx[i] = sum != 0.0 ? 100.0 * MathAbs(plusDi[i] - minusDi[i]) / sum : Empty();
   }
   RMA(dx, n, adxLen, adx);
}

int Barssince(const bool &cond[], const int i)
{
   for(int j = i; j >= 0; j--)
      if(cond[j])
         return i - j;
   return i;
}

int OnInit()
{
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, EntryBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, StopBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, Tp1Buffer, INDICATOR_DATA);
   SetIndexBuffer(5, Tp2Buffer, INDICATOR_DATA);
   SetIndexBuffer(6, Tp3Buffer, INDICATOR_DATA);
   SetIndexBuffer(7, SuperTrendBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   for(int p = 0; p < 8; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "FreshAlgo MQL5");
   return INIT_SUCCEEDED;
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
   if(rates_total < 300)
      return 0;

   int n = rates_total;
   double o[], h[], l[], c[], hlc3[], ohlc4[], vol[];
   ArrayResize(o, n);
   ArrayResize(h, n);
   ArrayResize(l, n);
   ArrayResize(c, n);
   ArrayResize(hlc3, n);
   ArrayResize(ohlc4, n);
   ArrayResize(vol, n);

   for(int i = 0; i < n; i++)
   {
      int m = n - 1 - i;
      o[i] = open[m];
      h[i] = high[m];
      l[i] = low[m];
      c[i] = close[m];
      hlc3[i] = (h[i] + l[i] + c[i]) / 3.0;
      ohlc4[i] = (o[i] + h[i] + l[i] + c[i]) / 4.0;
      vol[i] = (double)(volume[m] > 0 ? volume[m] : tick_volume[m]);
   }

   double ema150[], ema250[], ema200[], emaVol15[], emaVol20[], emaVol25[];
   EMA(c, n, 150, ema150);
   EMA(c, n, 250, ema250);
   EMA(c, n, 200, ema200);
   EMA(vol, n, 15, emaVol15);
   EMA(vol, n, 20, emaVol20);
   EMA(vol, n, 25, emaVol25);

   double rsi50[], rsii[], trRsi[], wwma[], atrRsi[], tsFast[];
   RSI(c, n, 50, rsi50);
   EMA(rsi50, n, 30, rsii);
   EMA(rsi50, n, 30, tsFast);
   ArrayResize(trRsi, n);
   ArrayResize(wwma, n);
   ArrayResize(atrRsi, n);
   double wwalpha = 1.0 / 50.0;
   for(int i = 0; i < n; i++)
   {
      trRsi[i] = (i > 0 && Valid(rsii[i]) && Valid(rsii[i - 1])) ? MathAbs(rsii[i] - rsii[i - 1]) : Empty();
      wwma[i] = Valid(trRsi[i]) ? wwalpha * trRsi[i] + (1.0 - wwalpha) * (i > 0 ? Nz(wwma[i - 1]) : 0.0) : Empty();
      atrRsi[i] = Valid(wwma[i]) ? wwalpha * wwma[i] + (1.0 - wwalpha) * (i > 0 ? Nz(atrRsi[i - 1]) : 0.0) : Empty();
   }

   double tsSlow[];
   ArrayResize(tsSlow, n);
   for(int i = 0; i < n; i++)
   {
      if(!Valid(tsFast[i]) || !Valid(atrRsi[i]))
      {
         tsSlow[i] = Empty();
         continue;
      }
      double tsUp = tsFast[i] + atrRsi[i] * 4.236;
      double tsDn = tsFast[i] - atrRsi[i] * 4.236;
      double prev = i > 0 ? Nz(tsSlow[i - 1]) : 0.0;
      double prevFast = i > 0 ? Nz(tsFast[i - 1]) : 0.0;
      tsSlow[i] = tsUp < prev ? tsUp
                  : (tsFast[i] > prev && prevFast < prev) ? tsDn
                  : tsDn > prev ? tsDn
                  : (tsFast[i] < prev && prevFast > prev) ? tsUp
                  : prev;
   }

   double st[], trendCloud[], hma55[], macd[], macdSig[], macdHist[], pdi[], mdi[], adx[], atr14[];
   int stDir[], cloudDir[];
   SuperTrend(c, c, h, l, n, InpSensitivity, InpSTuner, st, stDir);
   SuperTrend(ohlc4, c, h, l, n, (InpFilterStyle == FRESH_SWING_CLOUD_FILTER ? 7.0 : 4.0), 10, trendCloud, cloudDir);
   HMA(c, n, 55, hma55);
   MACD(c, n, 12, 26, 9, macd, macdSig, macdHist);
   DMI(h, l, c, n, 14, 14, pdi, mdi, adx);
   ATR(h, l, c, n, 14, atr14);

   bool bull[], bear[];
   ArrayResize(bull, n);
   ArrayResize(bear, n);
   double lastEntry = Empty();
   double lastStop = Empty();

   for(int i = 0; i < n; i++)
   {
      bool strongSignalsOnly = InpFilterStyle == FRESH_STRONG_FILTER;
      bool highVolSignals = InpFilterStyle == FRESH_HIGH_VOLUME_FILTER;
      bool signalsTrendCloud = InpFilterStyle == FRESH_SMOOTH_CLOUD_FILTER
                               || InpFilterStyle == FRESH_SCALPING_CLOUD_FILTER
                               || InpFilterStyle == FRESH_SCALPING_PLUS_CLOUD_FILTER
                               || InpFilterStyle == FRESH_SWING_CLOUD_FILTER;
      bool contrarianOnly = InpFilterStyle == FRESH_CONTRARIAN_SIGNALS;
      bool consSignalsFilter = InpFilterStyle == FRESH_TRENDING_SIGNALS;

      bool consFilter = Valid(adx[i]) && adx[i] > 20.0;
      bool contBull = Valid(tsFast[i]) && tsFast[i] < 35.0;
      bool contBear = Valid(tsFast[i]) && tsFast[i] > 65.0;
      bool volFilter = Valid(emaVol15[i]) && Valid(emaVol20[i]) && Valid(emaVol25[i]) && emaVol25[i] != 0.0
                       && ((emaVol15[i] - emaVol20[i]) / emaVol25[i] > 0.0);

      bool baseBull = i > 0 && Crossover(c[i], st[i], c[i - 1], st[i - 1]);
      bool baseBear = i > 0 && Crossunder(c[i], st[i], c[i - 1], st[i - 1]);

      bool trendCloudBull = false;
      bool trendCloudBear = false;
      if(InpFilterStyle == FRESH_SMOOTH_CLOUD_FILTER)
      {
         trendCloudBull = Valid(ema150[i]) && Valid(ema250[i]) && ema150[i] > ema250[i];
         trendCloudBear = Valid(ema150[i]) && Valid(ema250[i]) && ema150[i] < ema250[i];
      }
      else
      {
         trendCloudBull = Valid(trendCloud[i]) && c[i] > trendCloud[i];
         trendCloudBear = Valid(trendCloud[i]) && c[i] < trendCloud[i];
      }

      bull[i] = baseBull
                && (!strongSignalsOnly || (Valid(ema200[i]) && c[i] > ema200[i]))
                && (!contrarianOnly || contBull)
                && (!consSignalsFilter || consFilter)
                && (!highVolSignals || volFilter)
                && (!signalsTrendCloud || trendCloudBull);

      bear[i] = baseBear
                && (!strongSignalsOnly || (Valid(ema200[i]) && c[i] < ema200[i]))
                && (!contrarianOnly || contBear)
                && (!consSignalsFilter || consFilter)
                && (!highVolSignals || volFilter)
                && (!signalsTrendCloud || trendCloudBear);

      int countBull = Barssince(bull, i);
      int countBear = Barssince(bear, i);
      bool trigger = countBull < countBear;
      double atrBand = Empty();
      if(InpUsePercSL)
         atrBand = (trigger ? l[i] : h[i]) * (InpPercTrailingSL / 100.0);
      else if(Valid(atr14[i]))
         atrBand = atr14[i] * 2.2;
      double atrStop = Valid(atrBand) ? (trigger ? l[i] - atrBand : h[i] + atrBand) : Empty();

      if(bull[i] || bear[i])
      {
         lastEntry = c[i];
         lastStop = atrStop;
      }

      int m = n - 1 - i;
      BuyBuffer[m] = Empty();
      SellBuffer[m] = Empty();
      EntryBuffer[m] = Empty();
      StopBuffer[m] = Empty();
      Tp1Buffer[m] = Empty();
      Tp2Buffer[m] = Empty();
      Tp3Buffer[m] = Empty();
      SuperTrendBuffer[m] = Valid(st[i]) ? st[i] : Empty();

      bool hiddenCurrentLive = InpClosedBarOnly && m == 0;
      if(InpShowSignals && !hiddenCurrentLive)
      {
         if(bull[i])
            BuyBuffer[m] = l[i];
         if(bear[i])
            SellBuffer[m] = h[i];
      }

      if(InpShowTpSlAreas && Valid(lastEntry) && Valid(lastStop))
      {
         EntryBuffer[m] = lastEntry;
         StopBuffer[m] = lastStop;
         if(InpUseTP1 && InpMultTP1 != 0.0)
            Tp1Buffer[m] = (lastEntry - lastStop) * InpMultTP1 + lastEntry;
         if(InpUseTP2 && InpMultTP2 != 0.0)
            Tp2Buffer[m] = (lastEntry - lastStop) * InpMultTP2 + lastEntry;
         if(InpUseTP3 && InpMultTP3 != 0.0)
            Tp3Buffer[m] = (lastEntry - lastStop) * InpMultTP3 + lastEntry;
      }
   }

   return rates_total;
}
