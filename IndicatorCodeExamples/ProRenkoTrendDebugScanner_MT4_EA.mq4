#property strict
#property version "1.00"

#define BUILD_TAG "2026-07-06.0015-prorenko-trend-debug"
#define EMPTY_SENTINEL 2147483647.0

input string InpTrendIndicatorName = "Asiller\\Pro Renko  System\\RenkoBlastTrend";
input int    InpMaxBuffers = 12;
input int    InpMaxShift = 80;
input int    InpPollSeconds = 2;
input bool   InpPrintOnTimer = true;
input bool   InpPrintOnlyOnChange = true;
input bool   InpShowDashboard = true;
input int    InpDashboardX = 20;
input int    InpDashboardY = 30;
input int    InpCandidateBuyBuffer = 2;
input int    InpCandidateSellBuffer = 3;

string g_prefix;
string g_lastSignature = "";

double ReadBuf(int buffer, int shift)
{
   ResetLastError();
   return iCustom(Symbol(), Period(), InpTrendIndicatorName, buffer, shift);
}

bool IsUsable(double v)
{
   if(v == EMPTY_VALUE) return false;
   if(MathAbs(v - EMPTY_SENTINEL) < 0.1) return false;
   if(MathAbs(v) < 0.0000001) return false;
   if(v < -100000000.0 || v > 100000000.0) return false;
   return true;
}

string Px(double v)
{
   if(v == EMPTY_VALUE) return "EMPTY_VALUE";
   if(MathAbs(v - EMPTY_SENTINEL) < 0.1) return "EMPTY_SENTINEL";
   return DoubleToString(v, Digits);
}

string Obj(string name) { return g_prefix + name; }

void Rect(string name, int x, int y, int w, int h, color bg, color border)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void Label(string name, int x, int y, string text, color clr, int size)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void DeleteDashboard()
{
   for(int i=ObjectsTotal(0,-1,-1)-1; i>=0; i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,g_prefix)==0) ObjectDelete(0,name);
   }
}

string ShiftRow(int buffer, int maxSh)
{
   string s = "buf" + IntegerToString(buffer) + ":";
   for(int sh=0; sh<=maxSh; sh++)
      s += " sh" + IntegerToString(sh) + "=" + Px(ReadBuf(buffer, sh));
   return s;
}

string BufferSummary(int buffer)
{
   int valid=0;
   int first=-1, last=-1;
   double firstVal=0, lastVal=0, minv=0, maxv=0;
   string latest = "-";
   for(int sh=0; sh<=MathMin(InpMaxShift, Bars-1); sh++)
   {
      double v=ReadBuf(buffer, sh);
      if(!IsUsable(v)) continue;
      valid++;
      if(first<0)
      {
         first=sh; firstVal=v; minv=v; maxv=v;
         latest="sh"+IntegerToString(sh)+" "+TimeToString(Time[sh], TIME_DATE|TIME_MINUTES)+" "+Px(v);
      }
      last=sh; lastVal=v;
      if(v<minv) minv=v;
      if(v>maxv) maxv=v;
   }
   return "buf"+IntegerToString(buffer)+" valid="+IntegerToString(valid)+" first="+IntegerToString(first)+" last="+IntegerToString(last)+" latest="+latest+" min="+Px(minv)+" max="+Px(maxv)+" firstVal="+Px(firstVal)+" lastVal="+Px(lastVal);
}

string CandidateStateLine()
{
   double b0=ReadBuf(InpCandidateBuyBuffer,0), s0=ReadBuf(InpCandidateSellBuffer,0);
   double b1=ReadBuf(InpCandidateBuyBuffer,1), s1=ReadBuf(InpCandidateSellBuffer,1);
   bool b0a=IsUsable(b0), s0a=IsUsable(s0), b1a=IsUsable(b1), s1a=IsUsable(s1);
   string st0=(b0a&&!s0a)?"BUY":((!b0a&&s0a)?"SELL":((b0a&&s0a)?"MIXED":"NONE"));
   string st1=(b1a&&!s1a)?"BUY":((!b1a&&s1a)?"SELL":((b1a&&s1a)?"MIXED":"NONE"));
   return "candidate b"+IntegerToString(InpCandidateBuyBuffer)+"/s"+IntegerToString(InpCandidateSellBuffer)+" sh0="+st0+" b="+Px(b0)+" s="+Px(s0)+" | sh1="+st1+" b="+Px(b1)+" s="+Px(s1);
}

string Signature()
{
   string s = CandidateStateLine();
   for(int b=0; b<MathMin(InpMaxBuffers, 16); b++)
      s += "|" + BufferSummary(b);
   return s;
}

void PrintScan(string reason)
{
   string sig = Signature();
   if(InpPrintOnlyOnChange && sig == g_lastSignature) return;
   g_lastSignature = sig;

   Print("PRORENKO_TREND_DEBUG BUILD=", BUILD_TAG, " reason=", reason, " symbol=", Symbol(), " tf=", Period(), " indicator='", InpTrendIndicatorName, "' bars=", Bars);
   Print("PRORENKO_TREND_DEBUG ", CandidateStateLine());
   for(int b=0; b<MathMin(InpMaxBuffers, 16); b++)
      Print("PRORENKO_TREND_DEBUG ", BufferSummary(b), " row=", ShiftRow(b, 12));
}

void DashboardCreate()
{
   DeleteDashboard();
   if(!InpShowDashboard) return;
   int x=InpDashboardX, y=InpDashboardY;
   Rect(Obj("bg"), x, y, 860, 310, clrBlack, clrDimGray);
   Label(Obj("title"), x+10, y+8, "ProRenko Trend Debug // " + BUILD_TAG, clrAliceBlue, 9);
   for(int i=0;i<12;i++) Label(Obj("l"+IntegerToString(i)), x+10, y+34+i*22, "-", clrWhite, 8);
}

void DashboardUpdate()
{
   if(!InpShowDashboard) return;
   if(ObjectFind(0, Obj("bg"))<0) DashboardCreate();
   ObjectSetString(0, Obj("l0"), OBJPROP_TEXT, "indicator='"+InpTrendIndicatorName+"' symbol="+Symbol()+" tf="+IntegerToString(Period())+" bars="+IntegerToString(Bars));
   ObjectSetString(0, Obj("l1"), OBJPROP_TEXT, CandidateStateLine());
   for(int i=0;i<10;i++) ObjectSetString(0, Obj("l"+IntegerToString(i+2)), OBJPROP_TEXT, BufferSummary(i));
}

int OnInit()
{
   g_prefix="PRTDBG_"+IntegerToString((int)ChartID())+"_";
   EventSetTimer(MathMax(1, InpPollSeconds));
   DashboardCreate();
   PrintScan("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteDashboard();
}

void OnTick()
{
   DashboardUpdate();
}

void OnTimer()
{
   DashboardUpdate();
   if(InpPrintOnTimer) PrintScan("timer");
}