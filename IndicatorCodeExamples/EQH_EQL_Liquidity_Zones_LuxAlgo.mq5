//+------------------------------------------------------------------+
//|                        EQH_EQL_Liquidity_Zones_LuxAlgo.mq5       |
//|            MT5 port of "EQH/EQL Liquidity Zones [LuxAlgo]"      |
//| Join our channel for more free tools: https://t.me/FundedMillionAiress |
//| This work follows the original script licensing/comments.       |
//+------------------------------------------------------------------+
#property copyright "LuxAlgo / Port for MT5"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
#property indicator_label1  "EQH/EQL Liquidity Zones [LuxAlgo]"

const int   MAX_PIVOTS_PER_SIDE = 50;
const int   MAX_RENDER_ZONES = 500;
const int   CIRCLE_ARROW_CODE = 108;
const string DASHBOARD_TEXT = "Join Telegram For Premium Indicators @FundedMillionAiress ";

input group "Liquidity Detection"
input int    leftLenInput   = 10;    // Pivot Left Length
input int    rightLenInput  = 2;     // Pivot Right Length
input double thresholdPct   = 0.03;  // Equality Threshold (%)
input int    maxZones       = 60;    // Max Active Zones

input group "Visuals"
input color  bullColor      = C'8,153,129';           // Bullish Zone Color
input color  bearColor      = C'242,54,69';          // Bearish Zone Color
input int    zoneTransp     = 85;                     // Zone Transparency
input bool   showMidline    = false;                  // Show Midline
input color  midlineColor   = C'120,123,134';         // Midline Color
input bool   showVolume     = true;                   // Show Volume
input bool   deleteOnSweep  = false;                  // Delete on Sweep

double g_dummyBuffer[];
string g_prefix = "";
color  g_chartFg = clrSilver;

struct PivotPoint
  {
   double price;
   int    bar;
   long   vol;
  };

struct LiquidityZone
  {
   int    zoneId;
   int    leftBar;
   int    rightBar;
   int    pivot1Bar;
   int    pivot2Bar;
   double pivot1Price;
   double pivot2Price;
   double top;
   double bottom;
   double mid;
   double sweepLevel;
   double totalVol;
   int    createdBar;
   bool   isHigh;
   bool   isSwept;
   string labelText;
  };

color ApplyTransparency(const color base,const int transp)
  {
   int clamped = MathMax(0,MathMin(100,transp));
   int alpha = (int)MathRound(255.0 * (100.0 - (double)clamped) / 100.0);
   return((color)ColorToARGB(base,alpha));
  }

string FormatVol(const double value)
  {
   if(value >= 1000000.0)
      return(StringFormat("%.1fM",value / 1000000.0));
   if(value >= 1000.0)
      return(StringFormat("%.1fK",value / 1000.0));
   return(DoubleToString(value,0));
  }

string ZoneObjectName(const int zoneId,const string suffix)
  {
   return(g_prefix + IntegerToString(zoneId) + "_" + suffix);
  }

void PushZone(LiquidityZone &arr[],const LiquidityZone &zone)
  {
   int sz = ArraySize(arr);
   ArrayResize(arr,sz + 1);
   arr[sz] = zone;
  }

void RemoveZoneAt(LiquidityZone &arr[],const int idx)
  {
   int sz = ArraySize(arr);
   if(idx < 0 || idx >= sz)
      return;
   for(int i = idx; i < sz - 1; ++i)
      arr[i] = arr[i + 1];
   ArrayResize(arr,sz - 1);
  }

void UnshiftPivot(PivotPoint &arr[],const double price,const int bar,const long vol)
  {
   int sz = ArraySize(arr);
   ArrayResize(arr,sz + 1);
   for(int i = sz; i > 0; --i)
      arr[i] = arr[i - 1];
   arr[0].price = price;
   arr[0].bar = bar;
   arr[0].vol = vol;
   if(ArraySize(arr) > MAX_PIVOTS_PER_SIDE)
      ArrayResize(arr,MAX_PIVOTS_PER_SIDE);
  }

bool IsPivotHigh(const double &highs[],const int bars,const int center)
  {
   if(center < leftLenInput || center + rightLenInput >= bars)
      return(false);
   double pivot = highs[center];
   for(int i = 1; i <= leftLenInput; ++i)
     {
      if(pivot < highs[center - i])
         return(false);
     }
   for(int i = 1; i <= rightLenInput; ++i)
     {
      if(pivot <= highs[center + i])
         return(false);
     }
   return(true);
  }

bool IsPivotLow(const double &lows[],const int bars,const int center)
  {
   if(center < leftLenInput || center + rightLenInput >= bars)
      return(false);
   double pivot = lows[center];
   for(int i = 1; i <= leftLenInput; ++i)
     {
      if(pivot > lows[center - i])
         return(false);
     }
   for(int i = 1; i <= rightLenInput; ++i)
     {
      if(pivot >= lows[center + i])
         return(false);
     }
   return(true);
  }

void ConsolidateLabels(LiquidityZone &zones[])
  {
   int sz = ArraySize(zones);
   if(sz <= 0)
      return;

   for(int i = 0; i < sz; ++i)
     {
      if(!zones[i].isSwept)
         zones[i].labelText = "";
     }

   bool processed[];
   ArrayResize(processed,sz);
   ArrayInitialize(processed,false);

   for(int i = 0; i < sz; ++i)
     {
      if(processed[i] || zones[i].isSwept)
         continue;

      LiquidityZone base = zones[i];
      processed[i] = true;
      double clusterVol = base.totalVol;
      int clusterCount = 1;

      for(int j = i + 1; j < sz; ++j)
        {
         if(processed[j] || zones[j].isSwept)
            continue;
         LiquidityZone comp = zones[j];
         if(base.isHigh != comp.isHigh)
            continue;
         if(base.sweepLevel == 0.0)
            continue;
         double diffPct = MathAbs(base.sweepLevel - comp.sweepLevel) / base.sweepLevel * 100.0;
         if(diffPct <= thresholdPct * 3.0)
           {
            clusterVol += comp.totalVol;
            clusterCount++;
            processed[j] = true;
           }
        }

      string typeStr = base.isHigh ? "EQH" : "EQL";
      string countStr = clusterCount > 1 ? IntegerToString(clusterCount) + "x " : "";
      string volStr = showVolume ? " (" + FormatVol(clusterVol) + ")" : "";
      base.labelText = countStr + typeStr + volStr;
      zones[i] = base;
     }
  }

void DeleteOwnedObjects()
  {
   int total = ObjectsTotal(0,-1,-1);
   for(int i = total - 1; i >= 0; --i)
     {
      string name = ObjectName(0,i,-1,-1);
      if(StringFind(name,g_prefix) == 0)
         ObjectDelete(0,name);
     }
  }

void SetupObjectCommon(const string name)
  {
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
  }

void DrawZoneRectangle(const LiquidityZone &zone,const datetime &times[])
  {
   string name = ZoneObjectName(zone.zoneId,"box");
   if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,times[zone.leftBar],zone.top,times[zone.rightBar],zone.bottom))
      return;

   color base = zone.isHigh ? bearColor : bullColor;
   color fill = zone.isSwept ? ApplyTransparency(g_chartFg,95) : ApplyTransparency(base,zoneTransp);
   ObjectSetInteger(0,name,OBJPROP_COLOR,(long)fill);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   SetupObjectCommon(name);
  }

void DrawZoneMidline(const LiquidityZone &zone,const datetime &times[])
  {
   if(!showMidline)
      return;
   string name = ZoneObjectName(zone.zoneId,"mid");
   if(!ObjectCreate(0,name,OBJ_TREND,0,times[zone.leftBar],zone.mid,times[zone.rightBar],zone.mid))
      return;

   color lineClr = zone.isSwept ? ApplyTransparency(g_chartFg,80) : midlineColor;
   ObjectSetInteger(0,name,OBJPROP_COLOR,(long)lineClr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   SetupObjectCommon(name);
  }

void DrawTextLabel(const string name,const datetime when,const double price,const string text,const color clr,const ENUM_ANCHOR_POINT anchor,const int fontSize)
  {
   if(StringLen(text) <= 0)
      return;
   if(!ObjectCreate(0,name,OBJ_TEXT,0,when,price))
      return;

   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,(long)clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   SetupObjectCommon(name);
  }

void DrawCircleMarker(const string name,const datetime when,const double price,const color clr)
  {
   if(!ObjectCreate(0,name,OBJ_ARROW,0,when,price))
      return;

   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,CIRCLE_ARROW_CODE);
   ObjectSetInteger(0,name,OBJPROP_COLOR,(long)clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_CENTER);
   SetupObjectCommon(name);
  }

void DrawZone(const LiquidityZone &zone,const datetime &times[])
  {
   DrawZoneRectangle(zone,times);
   DrawZoneMidline(zone,times);

   color base = zone.isHigh ? bearColor : bullColor;
   color labelClr = zone.isSwept ? ApplyTransparency(g_chartFg,75) : base;
   color circleClr = zone.isSwept ? ApplyTransparency(g_chartFg,85) : base;

   string mainText = zone.labelText;
   if(zone.isSwept)
     {
      string volStr = showVolume ? " (" + FormatVol(zone.totalVol) + ")" : "";
      mainText = "Swept " + (zone.isHigh ? "EQH" : "EQL") + volStr;
     }

   DrawTextLabel(ZoneObjectName(zone.zoneId,"lbl"),times[zone.rightBar],zone.mid,mainText,labelClr,ANCHOR_LEFT,8);
   DrawCircleMarker(ZoneObjectName(zone.zoneId,"b1"),times[zone.pivot1Bar],zone.pivot1Price,circleClr);
   DrawCircleMarker(ZoneObjectName(zone.zoneId,"b2"),times[zone.pivot2Bar],zone.pivot2Price,circleClr);

  }

void DrawVolumeLabels(const LiquidityZone &zone,const datetime &times[],const long vol1,const long vol2)
  {
   if(!showVolume || zone.isSwept)
      return;
   color base = zone.isHigh ? bearColor : bullColor;
   ENUM_ANCHOR_POINT anchor = zone.isHigh ? ANCHOR_LOWER : ANCHOR_UPPER;
   DrawTextLabel(ZoneObjectName(zone.zoneId,"v1"),times[zone.pivot1Bar],zone.pivot1Price,FormatVol((double)vol1),base,anchor,7);
   DrawTextLabel(ZoneObjectName(zone.zoneId,"v2"),times[zone.pivot2Bar],zone.pivot2Price,FormatVol((double)vol2),base,anchor,7);
  }

void DrawDashboard()
  {
   string bg = g_prefix + "dashboard_bg";
   string txt = g_prefix + "dashboard_txt";
   int chartWidth = (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int panelWidth = 540;
   int panelHeight = 24;
   int x = MathMax(8,(chartWidth - panelWidth) / 2);
   int y = 8;

   if(ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0))
     {
      ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,panelWidth);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,panelHeight);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlue);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,clrBlack);
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      SetupObjectCommon(bg);
     }

   if(ObjectCreate(0,txt,OBJ_LABEL,0,0,0))
     {
      ObjectSetInteger(0,txt,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,txt,OBJPROP_XDISTANCE,x + 8);
      ObjectSetInteger(0,txt,OBJPROP_YDISTANCE,y + 4);
      ObjectSetString(0,txt,OBJPROP_TEXT,DASHBOARD_TEXT);
      ObjectSetString(0,txt,OBJPROP_FONT,"Arial");
      ObjectSetInteger(0,txt,OBJPROP_FONTSIZE,11);
      ObjectSetInteger(0,txt,OBJPROP_COLOR,clrWhite);
      SetupObjectCommon(txt);
     }
  }

int OnInit()
  {
   SetIndexBuffer(0,g_dummyBuffer,INDICATOR_DATA);
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_NONE);
   IndicatorSetString(INDICATOR_SHORTNAME,"EQH/EQL Liquidity Zones [LuxAlgo]");
   ArraySetAsSeries(g_dummyBuffer,true);
   g_prefix = "EQHEQL_LUX_" + StringFormat("%I64d",(long)ChartID()) + "_";
   g_chartFg = (color)ChartGetInteger(0,CHART_COLOR_FOREGROUND,0);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   DeleteOwnedObjects();
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
   if(rates_total <= leftLenInput + rightLenInput + 2)
      return(0);

   for(int i = 0; i < rates_total; ++i)
      g_dummyBuffer[i] = EMPTY_VALUE;

   g_chartFg = (color)ChartGetInteger(0,CHART_COLOR_FOREGROUND,0);

   datetime timesChrono[];
   double highsChrono[];
   double lowsChrono[];
   long volsChrono[];
   ArrayResize(timesChrono,rates_total);
   ArrayResize(highsChrono,rates_total);
   ArrayResize(lowsChrono,rates_total);
   ArrayResize(volsChrono,rates_total);

   for(int bar = 0; bar < rates_total; ++bar)
     {
      int shift = rates_total - 1 - bar;
      timesChrono[bar] = time[shift];
      highsChrono[bar] = high[shift];
      lowsChrono[bar] = low[shift];
      volsChrono[bar] = (volume[shift] > 0 ? volume[shift] : tick_volume[shift]);
     }

   PivotPoint historicalHighs[];
   PivotPoint historicalLows[];
   LiquidityZone activeZones[];
   LiquidityZone renderedZones[];
   int nextZoneId = 1;

   for(int bar = 0; bar < rates_total; ++bar)
     {
      int pivotBar = bar - rightLenInput;
      if(pivotBar >= leftLenInput)
        {
         if(IsPivotHigh(highsChrono,rates_total,pivotBar))
           {
            double pH = highsChrono[pivotBar];
            long currentVol = volsChrono[pivotBar];
            int histCount = ArraySize(historicalHighs);
            for(int i = 0; i < histCount; ++i)
              {
               PivotPoint prev = historicalHighs[i];
               if(prev.price == 0.0)
                  continue;
               double diffPct = MathAbs(pH - prev.price) / prev.price * 100.0;
               if(diffPct <= thresholdPct)
                 {
                  LiquidityZone zone;
                  zone.zoneId = nextZoneId++;
                  zone.leftBar = prev.bar;
                  zone.rightBar = bar;
                  zone.pivot1Bar = prev.bar;
                  zone.pivot2Bar = pivotBar;
                  zone.pivot1Price = prev.price;
                  zone.pivot2Price = pH;
                  zone.top = MathMax(pH,prev.price);
                  zone.bottom = MathMin(pH,prev.price);
                  zone.mid = (zone.top + zone.bottom) / 2.0;
                  zone.sweepLevel = zone.top;
                  zone.totalVol = (double)prev.vol + (double)currentVol;
                  zone.createdBar = bar;
                  zone.isHigh = true;
                  zone.isSwept = false;
                  zone.labelText = "";
                  PushZone(activeZones,zone);
                  break;
                 }
              }
            UnshiftPivot(historicalHighs,pH,pivotBar,currentVol);
           }

         if(IsPivotLow(lowsChrono,rates_total,pivotBar))
           {
            double pL = lowsChrono[pivotBar];
            long currentVol = volsChrono[pivotBar];
            int histCount = ArraySize(historicalLows);
            for(int i = 0; i < histCount; ++i)
              {
               PivotPoint prev = historicalLows[i];
               if(prev.price == 0.0)
                  continue;
               double diffPct = MathAbs(pL - prev.price) / prev.price * 100.0;
               if(diffPct <= thresholdPct)
                 {
                  LiquidityZone zone;
                  zone.zoneId = nextZoneId++;
                  zone.leftBar = prev.bar;
                  zone.rightBar = bar;
                  zone.pivot1Bar = prev.bar;
                  zone.pivot2Bar = pivotBar;
                  zone.pivot1Price = prev.price;
                  zone.pivot2Price = pL;
                  zone.top = MathMax(pL,prev.price);
                  zone.bottom = MathMin(pL,prev.price);
                  zone.mid = (zone.top + zone.bottom) / 2.0;
                  zone.sweepLevel = zone.bottom;
                  zone.totalVol = (double)prev.vol + (double)currentVol;
                  zone.createdBar = bar;
                  zone.isHigh = false;
                  zone.isSwept = false;
                  zone.labelText = "";
                  PushZone(activeZones,zone);
                  break;
                 }
              }
            UnshiftPivot(historicalLows,pL,pivotBar,currentVol);
           }
        }

      for(int i = ArraySize(activeZones) - 1; i >= 0; --i)
        {
         LiquidityZone zone = activeZones[i];
         zone.rightBar = bar;
         bool swept = false;
         if(bar > zone.createdBar)
            swept = zone.isHigh ? (highsChrono[bar] > zone.sweepLevel) : (lowsChrono[bar] < zone.sweepLevel);

         if(swept)
           {
            if(!deleteOnSweep)
              {
               zone.isSwept = true;
               zone.rightBar = bar;
               string volStr = showVolume ? " (" + FormatVol(zone.totalVol) + ")" : "";
               zone.labelText = "Swept " + (zone.isHigh ? "EQH" : "EQL") + volStr;
               PushZone(renderedZones,zone);
              }
            RemoveZoneAt(activeZones,i);
           }
         else
            activeZones[i] = zone;
        }

      while(ArraySize(activeZones) > maxZones)
        {
         LiquidityZone oldest = activeZones[0];
         oldest.rightBar = bar;
         PushZone(renderedZones,oldest);
         RemoveZoneAt(activeZones,0);
        }

      if(ArraySize(activeZones) > 0)
         ConsolidateLabels(activeZones);
     }

   LiquidityZone zonesToDraw[];
   int renderedCount = ArraySize(renderedZones);
   for(int i = 0; i < renderedCount; ++i)
      PushZone(zonesToDraw,renderedZones[i]);
   int activeCount = ArraySize(activeZones);
   for(int i = 0; i < activeCount; ++i)
      PushZone(zonesToDraw,activeZones[i]);

   while(ArraySize(zonesToDraw) > MAX_RENDER_ZONES)
      RemoveZoneAt(zonesToDraw,0);

   DeleteOwnedObjects();

   for(int i = 0; i < ArraySize(zonesToDraw); ++i)
     {
      LiquidityZone zone = zonesToDraw[i];
      DrawZone(zone,timesChrono);
      DrawVolumeLabels(zone,timesChrono,volsChrono[zone.pivot1Bar],volsChrono[zone.pivot2Bar]);
     }

   DrawDashboard();
   return(rates_total);
  }
//+------------------------------------------------------------------+
