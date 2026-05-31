//+------------------------------------------------------------------+
//| NAS Ultimate Algo | Remastered+ - MQ5 port                       |
//| Pine source: IndicatorCodeExamples/NasIndicator.pine             |
//| Buffers: 0 BUY, 1 SELL, 2 SuperTrend, 3 Entry, 4 SL, 5 TP1,       |
//|          6 TP2, 7 TP3                                            |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label1  "BUY"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2
#property indicator_label2  "SELL"

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_width3  2
#property indicator_label3  "SuperTrend"

#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGray
#property indicator_style4  STYLE_DOT
#property indicator_label4  "Entry"

#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_style5  STYLE_DOT
#property indicator_label5  "SL"

#property indicator_type6   DRAW_LINE
#property indicator_color6  clrLime
#property indicator_style6  STYLE_DASH
#property indicator_label6  "TP1"

#property indicator_type7   DRAW_LINE
#property indicator_color7  clrLime
#property indicator_style7  STYLE_DASH
#property indicator_label7  "TP2"

#property indicator_type8   DRAW_LINE
#property indicator_color8  clrLime
#property indicator_style8  STYLE_DASH
#property indicator_label8  "TP3"

input int  InpSensitivity = 4;  // Sensitivity
input int  InpRsiLength = 14;   // RSI Length
input int  InpAtrRisk = 1;      // Risk %
input int  InpAtrLen = 14;      // ATR Length for TP/SL
input bool InpShowLevels = true;

double BuyBuffer[], SellBuffer[], SuperTrendBuffer[], EntryBuffer[], SLBuffer[], TP1Buffer[], TP2Buffer[], TP3Buffer[];

double EmptyVal()
{
   return EMPTY_VALUE;
}

bool IsValid(const double v)
{
   return MathIsValidNumber(v) && v != EMPTY_VALUE;
}

double TR(const MqlRates &r[], const int i)
{
   if(i <= 0)
      return r[i].high - r[i].low;
   return MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - r[i - 1].close), MathAbs(r[i].low - r[i - 1].close)));
}

double SMA(const double &a[], const int i, const int len)
{
   if(i < len - 1)
      return EmptyVal();
   double s = 0.0;
   for(int k = i - len + 1; k <= i; k++)
      s += a[k];
   return s / (double)len;
}

void WilderATR(const MqlRates &r[], const int n, const int len, double &out[])
{
   ArrayResize(out, n);
   double tr[];
   ArrayResize(tr, n);
   for(int i = 0; i < n; i++)
   {
      tr[i] = TR(r, i);
      if(len <= 1)
         out[i] = tr[i];
      else if(i < len - 1)
         out[i] = EmptyVal();
      else if(i == len - 1)
      {
         double s = 0.0;
         for(int k = 0; k <= i; k++)
            s += tr[k];
         out[i] = s / (double)len;
      }
      else
         out[i] = (out[i - 1] * (len - 1) + tr[i]) / (double)len;
   }
}

int OnInit()
{
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, SuperTrendBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, EntryBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, SLBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, TP1Buffer, INDICATOR_DATA);
   SetIndexBuffer(6, TP2Buffer, INDICATOR_DATA);
   SetIndexBuffer(7, TP3Buffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   IndicatorSetString(INDICATOR_SHORTNAME, "NasIndicator");
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
   if(rates_total < 200)
      return 0;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, _Period, 0, rates_total, rates);
   if(copied <= 0)
      return prev_calculated;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   double closeArr[], sma8[], sma9[], sma13[], atr11[], atr14[], atr30[];
   ArrayResize(closeArr, copied);
   ArrayResize(sma8, copied);
   ArrayResize(sma9, copied);
   ArrayResize(sma13, copied);
   for(int i = 0; i < copied; i++)
      closeArr[i] = rates[i].close;
   WilderATR(rates, copied, 11, atr11);
   WilderATR(rates, copied, InpAtrLen, atr14);
   WilderATR(rates, copied, 30, atr30);

   double lowerBand[], upperBand[], st[], atrStop[];
   int dir[];
   ArrayResize(lowerBand, copied);
   ArrayResize(upperBand, copied);
   ArrayResize(st, copied);
   ArrayResize(atrStop, copied);
   ArrayResize(dir, copied);

   double lastEntry = EmptyVal();
   double lastStop = EmptyVal();
   int lastBull = -1, lastBear = -1;

   for(int i = 0; i < copied; i++)
   {
      BuyBuffer[i] = SellBuffer[i] = EmptyVal();
      SuperTrendBuffer[i] = EntryBuffer[i] = SLBuffer[i] = TP1Buffer[i] = TP2Buffer[i] = TP3Buffer[i] = EmptyVal();

      sma8[i] = SMA(closeArr, i, 8);
      sma9[i] = SMA(closeArr, i, 9);
      sma13[i] = SMA(closeArr, i, 13);

      double atr = IsValid(atr11[i]) ? atr11[i] : 0.0;
      double upperRaw = rates[i].close + InpSensitivity * atr;
      double lowerRaw = rates[i].close - InpSensitivity * atr;
      if(i == 0)
      {
         lowerBand[i] = lowerRaw;
         upperBand[i] = upperRaw;
         dir[i] = 1;
      }
      else
      {
         double prevLower = lowerBand[i - 1];
         double prevUpper = upperBand[i - 1];
         lowerBand[i] = (lowerRaw > prevLower || rates[i - 1].close < prevLower) ? lowerRaw : prevLower;
         upperBand[i] = (upperRaw < prevUpper || rates[i - 1].close > prevUpper) ? upperRaw : prevUpper;
         if(!IsValid(atr11[i - 1]))
            dir[i] = 1;
         else if(st[i - 1] == prevUpper)
            dir[i] = rates[i].close > upperBand[i] ? -1 : 1;
         else
            dir[i] = rates[i].close < lowerBand[i] ? 1 : -1;
      }
      st[i] = dir[i] == -1 ? lowerBand[i] : upperBand[i];
      SuperTrendBuffer[i] = st[i];

      bool bull = (i > 0 && rates[i].close > st[i] && rates[i - 1].close <= st[i - 1] && IsValid(sma13[i]) && rates[i].close >= sma13[i]);
      bool bear = (i > 0 && rates[i].close < st[i] && rates[i - 1].close >= st[i - 1] && IsValid(sma13[i]) && rates[i].close <= sma13[i]);

      int countBull = lastBull < 0 ? i : i - lastBull;
      int countBear = lastBear < 0 ? i : i - lastBear;
      int trigger = countBull < countBear ? 1 : 0;
      double atrBand = (IsValid(atr14[i]) ? atr14[i] : 0.0) * InpAtrRisk;
      atrStop[i] = trigger == 1 ? rates[i].low - atrBand : rates[i].high + atrBand;

      if(bull || bear)
      {
         lastEntry = rates[i].close;
         lastStop = atrStop[i];
      }
      if(bull)
      {
         lastBull = i;
         double y = rates[i].low - (IsValid(atr30[i]) ? atr30[i] * 2.0 : 0.0);
         BuyBuffer[i] = y;
      }
      if(bear)
      {
         lastBear = i;
         double y = rates[i].high + (IsValid(atr30[i]) ? atr30[i] * 2.0 : 0.0);
         SellBuffer[i] = y;
      }

      if(InpShowLevels && IsValid(lastEntry) && IsValid(lastStop))
      {
         EntryBuffer[i] = lastEntry;
         SLBuffer[i] = lastStop;
         TP1Buffer[i] = (lastEntry - lastStop) * 1.0 + lastEntry;
         TP2Buffer[i] = (lastEntry - lastStop) * 2.0 + lastEntry;
         TP3Buffer[i] = (lastEntry - lastStop) * 3.0 + lastEntry;
      }
   }

   return rates_total;
}
