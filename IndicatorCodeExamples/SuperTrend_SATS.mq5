//+------------------------------------------------------------------+
//| Self-Aware Trend System [WillyAlgoTrader] - MQ5 indicator port   |
//| Pine source: IndicatorCodeExamples/SuperTrend.pine               |
//| Buffers: 0 BUY, 1 SELL, 2 SuperTrend, 3 Entry, 4 SL, 5 TP1,       |
//|          6 TP2, 7 TP3, 8 Trend                                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   9

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label1  "BUY"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2
#property indicator_label2  "SELL"

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDeepSkyBlue
#property indicator_width3  2
#property indicator_label3  "SuperTrend"

#property indicator_type4   DRAW_LINE
#property indicator_color4  clrSilver
#property indicator_width4  1
#property indicator_label4  "Entry"

#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_width5  2
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

#property indicator_type9   DRAW_NONE
#property indicator_label9  "Trend"

#include "SuperTrend_SATS_Core.mqh"

input SATS_PRESET InpPreset = SATS_PRESET_AUTO;
input SATS_SOURCE InpSource = SATS_SOURCE_CLOSE;
input int    InpAtrLen = 13;
input double InpBaseMult = 2.0;
input bool   InpUseAdaptive = true;
input int    InpErLen = 20;
input double InpAdaptStrength = 0.5;
input int    InpAtrBaselineLen = 100;
input bool   InpUseTqi = true;
input double InpQualityStrength = 0.4;
input double InpQualityCurve = 1.5;
input bool   InpSmoothMult = true;
input bool   InpUseAsymBands = true;
input double InpAsymStrength = 0.5;
input bool   InpUseEffAtr = true;
input bool   InpUseCharFlip = true;
input int    InpCharFlipMinAge = 5;
input double InpCharFlipHigh = 0.55;
input double InpCharFlipLow = 0.25;
input double InpTqiWeightEr = 0.35;
input double InpTqiWeightVol = 0.20;
input double InpTqiWeightStruct = 0.25;
input double InpTqiWeightMom = 0.20;
input int    InpTqiStructLen = 20;
input int    InpTqiMomLen = 10;
input int    InpPivotLen = 3;
input int    InpRsiLen = 14;
input int    InpVolLen = 20;
input double InpSlAtrMult = 1.5;
input double InpTp1R = 1.0;
input double InpTp2R = 2.0;
input double InpTp3R = 3.0;

double BuyBuffer[], SellBuffer[], STBuffer[], EntryBuffer[], SLBuffer[], TP1Buffer[], TP2Buffer[], TP3Buffer[], TrendBuffer[];

SATSSettings BuildSettings()
{
   SATSSettings s;
   s.preset = InpPreset;
   s.source = InpSource;
   s.atrLen = InpAtrLen;
   s.baseMult = InpBaseMult;
   s.useAdaptive = InpUseAdaptive;
   s.erLen = InpErLen;
   s.adaptStrength = InpAdaptStrength;
   s.atrBaselineLen = InpAtrBaselineLen;
   s.useTqi = InpUseTqi;
   s.qualityStrength = InpQualityStrength;
   s.qualityCurve = InpQualityCurve;
   s.smoothMult = InpSmoothMult;
   s.useAsymBands = InpUseAsymBands;
   s.asymStrength = InpAsymStrength;
   s.useEffAtr = InpUseEffAtr;
   s.useCharFlip = InpUseCharFlip;
   s.charFlipMinAge = InpCharFlipMinAge;
   s.charFlipHigh = InpCharFlipHigh;
   s.charFlipLow = InpCharFlipLow;
   s.tqiWeightEr = InpTqiWeightEr;
   s.tqiWeightVol = InpTqiWeightVol;
   s.tqiWeightStruct = InpTqiWeightStruct;
   s.tqiWeightMom = InpTqiWeightMom;
   s.tqiStructLen = InpTqiStructLen;
   s.tqiMomLen = InpTqiMomLen;
   s.pivotLen = InpPivotLen;
   s.rsiLen = InpRsiLen;
   s.volLen = InpVolLen;
   s.slAtrMult = InpSlAtrMult;
   s.tp1R = InpTp1R;
   s.tp2R = InpTp2R;
   s.tp3R = InpTp3R;
   s.tradeMaxAge = 100;
   s.useAutoCalib = false;
   s.calibWindow = 20;
   s.calibBadR = 0.0;
   s.calibGoodR = 0.7;
   s.calibStepQ = 0.05;
   s.calibCooldown = 5;
   s.calibMinQ = 0.1;
   s.calibMaxQ = 0.9;
   return s;
}

int OnInit()
{
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, STBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, EntryBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, SLBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, TP1Buffer, INDICATOR_DATA);
   SetIndexBuffer(6, TP2Buffer, INDICATOR_DATA);
   SetIndexBuffer(7, TP3Buffer, INDICATOR_DATA);
   SetIndexBuffer(8, TrendBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   IndicatorSetString(INDICATOR_SHORTNAME, "SuperTrend_SATS");
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
   if(rates_total < 150)
      return 0;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, _Period, 0, rates_total, rates);
   if(copied <= 0)
      return prev_calculated;
   if(rates[0].time > rates[copied - 1].time)
      ArrayReverse(rates, 0, WHOLE_ARRAY);

   SATSPoint p[];
   SATSSettings s = BuildSettings();
   SATS_Calculate(rates, copied, s, p);

   for(int i = 0; i < copied; i++)
   {
      BuyBuffer[i] = p[i].buy ? rates[i].low : EMPTY_VALUE;
      SellBuffer[i] = p[i].sell ? rates[i].high : EMPTY_VALUE;
      STBuffer[i] = p[i].stLine;
      EntryBuffer[i] = p[i].entry;
      SLBuffer[i] = p[i].sl;
      TP1Buffer[i] = p[i].tp1;
      TP2Buffer[i] = p[i].tp2;
      TP3Buffer[i] = p[i].tp3;
      TrendBuffer[i] = (double)p[i].trend;
   }

   return rates_total;
}
