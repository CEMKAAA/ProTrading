//+------------------------------------------------------------------+
//|                                              H1_RSI_Line_Cem.mq5 |
//|                                  Copyright 2026, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property indicator_separate_window

//--- Plot / Buffer ayarlari
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrAqua
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label1  "H1 RSI"

//--- Seviye ayarlari
#property indicator_level1 30.0
#property indicator_level2 47.0
#property indicator_level3 52.0
#property indicator_level4 70.0
#property indicator_levelcolor clrSilver
#property indicator_levelstyle STYLE_DOT

//--- Girdi parametresi
input int RSI_Period = 14;

//--- Buffer ve handle
double H1RSILine[];
int    g_rsi_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, H1RSILine, INDICATOR_DATA);
   PlotIndexSetString(0, PLOT_LABEL, "H1 RSI (" + IntegerToString(RSI_Period) + ")");
   IndicatorSetDouble(INDICATOR_MINIMUM, 0.0);
   IndicatorSetDouble(INDICATOR_MAXIMUM, 100.0);

   g_rsi_handle = iRSI(_Symbol, PERIOD_H1, RSI_Period, PRICE_CLOSE);
   if(g_rsi_handle == INVALID_HANDLE)
     {
      Print("H1_RSI_Line_Cem.mq5: iRSI handle olusturulamadi. err=", GetLastError());
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_rsi_handle != INVALID_HANDLE)
     {
      IndicatorRelease(g_rsi_handle);
      g_rsi_handle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
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
   if(rates_total <= 0 || g_rsi_handle == INVALID_HANDLE)
      return(0);

   int bars_ready = BarsCalculated(g_rsi_handle);
   if(bars_ready <= 0)
      return(prev_calculated);

   int h1_bars = Bars(_Symbol, PERIOD_H1);
   if(h1_bars <= 0)
      return(prev_calculated);

   static double rsi_vals[];
   ArrayResize(rsi_vals, h1_bars);
   ArraySetAsSeries(rsi_vals, true);

   int copied = CopyBuffer(g_rsi_handle, 0, 0, h1_bars, rsi_vals);
   if(copied <= 0)
      return(prev_calculated);

   int start = 0;
   if(prev_calculated > 0)
      start = prev_calculated - 1;
   if(start < 0)
      start = 0;

   for(int i = start; i < rates_total; i++)
     {
      int h1_shift = iBarShift(_Symbol, PERIOD_H1, time[i], false);
      if(h1_shift < 0 || h1_shift >= copied)
         H1RSILine[i] = EMPTY_VALUE;
      else
         H1RSILine[i] = rsi_vals[h1_shift];
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+

