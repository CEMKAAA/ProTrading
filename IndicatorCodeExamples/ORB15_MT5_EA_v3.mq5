//+------------------------------------------------------------------+
//| 15 Minute ORB MT5 EA – v3.1 (production)                         |
//| Interactive dashboard with toggleable filters + live sim stats.   |
//| All filters, signal TF, and confirmation delay dashboard-driven.  |
//| Session clock: NY → broker server via GMT offset.                 |
//+------------------------------------------------------------------+
#property strict
#property version "3.10"
#include <Trade/Trade.mqh>
#define ORB15_BUILD "2026-06-14.v3.1-prod"

//=== CORE INPUTS ========================================================
input bool            InpEaEnabled          = true;
input long            InpMagic              = 15091503;
input ENUM_TIMEFRAMES InpSignalTimeframe    = PERIOD_M15;   // M15 default — M1 too noisy for ORB
input double          InpBrokerGmtOffsetHours = 0.0;
input bool            InpAutoNewYorkDst     = true;
input string          InpOrbStartNy         = "09:30";
input string          InpOrbEndNy           = "09:45";
input string          InpTradeEndNy         = "16:00";
input bool            InpUseClosedBarBreakout = true;
input double          InpMinBreakoutPoints  = 0.0;
input double          InpSlBufferPoints     = 0.0;
input bool            InpOneTradePerNyDay   = true;
input int             InpDeviationPoints    = 30;
input int             InpMaxSpreadPoints    = 0;

//=== BREAKOUT CONFIRMATION ==============================================
input int    InpBreakoutDelayMinutes = 5;    // Wait N min after ORB end before accepting signals
input int    InpConfirmBars          = 1;    // Breakout bar must hold N closed bars above/below ORB

//=== EXECUTION MODE =====================================================
enum ORB_EXEC_MODE { ORB_EXEC_SINGLE=0, ORB_EXEC_PARTIAL_3LEG=1 };
input ORB_EXEC_MODE InpExecutionMode = ORB_EXEC_PARTIAL_3LEG;
input double InpTp1R      = 0.5;    // Conservative: half ORB range as TP1
input double InpTp2R      = 1.0;    // 1:1 as TP2
input double InpTp3R      = 1.5;    // Runner at 1.5R
input double InpSingleTpR = 1.0;

//=== FILTERS (initial state – toggleable from dashboard) ================
input bool   InpMoveToBEOnTp1       = true;
input double InpBEOffsetPoints      = 2.0;
input bool   InpUseAtrRangeFilter   = true;
input int    InpAtrPeriod           = 14;
input double InpMinRangeAtrPct      = 15.0;
input double InpMaxRangeAtrPct      = 80.0;
input bool   InpUseVolumeFilter     = true;
input double InpVolumeMultiplier    = 1.0;
input bool   InpUseTimeExit         = true;
input int    InpTimeExitMinutes     = 120;
input double InpTimeExitMinProgress = 0.5;
input bool   InpUseDayFilter        = false;
input bool   InpTradeMonday         = true;
input bool   InpTradeTuesday        = true;
input bool   InpTradeWednesday      = true;
input bool   InpTradeThursday       = true;
input bool   InpTradeFriday         = true;
input bool   InpEnforceTpTouchClose = true;
input double InpTpTouchTolerancePts = 2.0;

//=== LOT SIZING =========================================================
input bool   InpUseAutoRiskLot   = true;
input double InpRiskPerTradePct  = 1.0;
input double InpFixedLot         = 0.10;
input double InpMaxLot           = 0.0;

//=== DISPLAY & AUDIT ====================================================
input bool InpShowDashboard          = true;
input int  InpDashboardX             = 10;
input int  InpDashboardY             = 18;
input bool InpDrawHistoricalSignals  = true;
input int  InpHistoricalDays         = 14;
input bool InpAuditCsv               = true;
input bool InpLogOnInit              = true;

//--- Objects ------------------------------------------------------------
CTrade trade;
string PREFIX = "ORB15v3_";

//--- Core state ---------------------------------------------------------
int      g_nyDayKey = 0;
bool     g_orbReady = false;
bool     g_tradeTaken = false;
double   g_orbHigh = 0, g_orbLow = 0, g_orbAvgVolume = 0;
datetime g_orbStartServer = 0, g_orbEndServer = 0, g_tradeEndServer = 0;
datetime g_lastSignalBarTime = 0;
datetime g_lastHistBuild = 0;
bool     g_histNeedsRedraw = true;

//--- Runtime toggles (mutable from dashboard) ---------------------------
bool            g_rtFilterAtr     = true;
bool            g_rtFilterVol     = true;
bool            g_rtFilterDay     = false;
bool            g_rtTimeExit      = true;
bool            g_rtBEOnTp1       = true;
bool            g_rtEaEnabled     = true;
ENUM_TIMEFRAMES g_rtSignalTf      = PERIOD_M15;  // runtime signal timeframe
int             g_rtDelayMin      = 5;            // runtime confirmation delay
bool            g_rtUseDelay      = true;         // toggle for confirmation delay

//--- Trade management state ---------------------------------------------
int      g_tradeDir = 0;
double   g_tradeEntry = 0, g_tradeSl = 0, g_tradeRisk = 0;
double   g_tradeTp1 = 0, g_tradeTp2 = 0, g_tradeTp3 = 0;
datetime g_tradeOpenTime = 0;
bool     g_beMoved = false;
string   g_lastFilterReason = "";
string   g_lastExecStatus = "READY";

//--- Historical stats ---------------------------------------------------
int    g_histTotal = 0, g_histWins = 0, g_histLosses = 0;
double g_histNetR = 0.0;
string g_histStatLine = "-";

//=========================================================================
//  UTILITY FUNCTIONS
//=========================================================================
int ParseClockMinutes(string v,int fb){StringTrimLeft(v);StringTrimRight(v);int p=StringFind(v,":");if(p<0)return fb;int h=(int)StringToInteger(StringSubstr(v,0,p));int m=(int)StringToInteger(StringSubstr(v,p+1));if(h<0||h>23||m<0||m>59)return fb;return h*60+m;}
datetime MakeDateTime(int y,int mo,int d,int h,int mi,int s=0){MqlDateTime st;ZeroMemory(st);st.year=y;st.mon=mo;st.day=d;st.hour=h;st.min=mi;st.sec=s;return StructToTime(st);}
int DayOfWeekForDate(int y,int mo,int d){MqlDateTime st;TimeToStruct(MakeDateTime(y,mo,d,12,0,0),st);return st.day_of_week;}
int NthSunday(int y,int mo,int nth){int fd=DayOfWeekForDate(y,mo,1);int fs=1+((7-fd)%7);return fs+(nth-1)*7;}
bool IsNewYorkDstDate(int y,int mo,int d){if(!InpAutoNewYorkDst)return true;if(mo<3||mo>11)return false;if(mo>3&&mo<11)return true;if(mo==3)return d>=NthSunday(y,3,2);if(mo==11)return d<NthSunday(y,11,1);return false;}
int NyUtcOffsetSecondsForDate(int y,int mo,int d){return IsNewYorkDstDate(y,mo,d)?-4*3600:-5*3600;}
datetime NyLocalToServer(int y,int mo,int d,int minOfDay){int h=minOfDay/60;int mi=minOfDay%60;datetime ny=MakeDateTime(y,mo,d,h,mi,0);datetime utc=ny-NyUtcOffsetSecondsForDate(y,mo,d);return utc+(int)MathRound(InpBrokerGmtOffsetHours*3600.0);}
datetime ServerToNyLocal(datetime s){datetime utc=s-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);MqlDateTime u;TimeToStruct(utc,u);return utc+NyUtcOffsetSecondsForDate(u.year,u.mon,u.day);}
int CurrentNyDayKey(int &y,int &mo,int &d){datetime utc=TimeCurrent()-(int)MathRound(InpBrokerGmtOffsetHours*3600.0);MqlDateTime u;TimeToStruct(utc,u);datetime ny=utc+NyUtcOffsetSecondsForDate(u.year,u.mon,u.day);MqlDateTime n;TimeToStruct(ny,n);y=n.year;mo=n.mon;d=n.day;return y*10000+mo*100+d;}
string FmtTime(datetime t){return t<=0?"-":TimeToString(t,TIME_DATE|TIME_SECONDS);}
string BoolText(bool v){return v?"true":"false";}
double NormalizePrice(double p){return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}
double NormalizeVolume(double v){double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(mn<=0)mn=0.01;if(mx<=0)mx=100;if(InpMaxLot>0)mx=MathMin(mx,InpMaxLot);if(st<=0)st=mn;v=MathMax(mn,MathMin(mx,v));v=MathFloor(v/st+1e-7)*st;return NormalizeDouble(MathMax(mn,v),2);}
double ValuePerPriceUnitPerLot(){double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);if(ts<=0)ts=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(ts<=0||tv<=0)return 0;return tv/ts;}
double CalculateLot(double entry,double sl){if(!InpUseAutoRiskLot)return NormalizeVolume(InpFixedLot);double rd=MathAbs(entry-sl);double vpu=ValuePerPriceUnitPerLot();double eq=AccountInfoDouble(ACCOUNT_EQUITY);double rm=eq*MathMax(0.01,InpRiskPerTradePct)/100.0;if(rd<=0||vpu<=0||rm<=0)return NormalizeVolume(InpFixedLot);return NormalizeVolume(rm/(rd*vpu));}
int CurrentSpreadPoints(){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return 0;double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)return 0;return(int)MathRound((t.ask-t.bid)/pt);}
bool SpreadAllowed(){if(InpMaxSpreadPoints<=0)return true;return CurrentSpreadPoints()<=InpMaxSpreadPoints;}
double NormalizeLegVolume(double total,int legs){double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);if(st<=0)st=0.01;if(mn<=0)mn=0.01;double leg=MathFloor(total/(double)legs/st+1e-7)*st;return NormalizeDouble(leg,8)<mn?0:NormalizeDouble(leg,8);}
string TfLabel(ENUM_TIMEFRAMES tf){if(tf==PERIOD_M1)return "M1";if(tf==PERIOD_M5)return "M5";if(tf==PERIOD_M15)return "M15";return EnumToString(tf);}
ENUM_TIMEFRAMES CycleTf(ENUM_TIMEFRAMES current){if(current==PERIOD_M1)return PERIOD_M5;if(current==PERIOD_M5)return PERIOD_M15;return PERIOD_M1;}

//=========================================================================
//  AUDIT
//=========================================================================
string AuditFileName(){int y,m,d;CurrentNyDayKey(y,m,d);return StringFormat("ORB15v3_Audit_%d%02d%02d.csv",y,m,d);}
void Audit(string ev,string dir,double lot,double entry,double sl,double tp,string detail)
{
   if(!InpAuditCsv)return;
   int h=FileOpen(AuditFileName(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ);
   if(h==INVALID_HANDLE)return;
   if(FileSize(h)==0)FileWrite(h,"time","symbol","tf","event","dir","lot","entry","sl","tp","orb_h","orb_l","spread","detail");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,FmtTime(TimeCurrent()),_Symbol,TfLabel(g_rtSignalTf),ev,dir,DoubleToString(lot,2),DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),DoubleToString(g_orbHigh,_Digits),DoubleToString(g_orbLow,_Digits),IntegerToString(CurrentSpreadPoints()),detail);
   FileClose(h);
}

//=========================================================================
//  POSITION HELPERS
//=========================================================================
bool OwnPositionExists(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;if((long)PositionGetInteger(POSITION_MAGIC)==InpMagic)return true;}return false;}
int OwnPositionCount(){int c=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;if((long)PositionGetInteger(POSITION_MAGIC)==InpMagic)c++;}return c;}
void CloseAllOwn(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol)continue;if((long)PositionGetInteger(POSITION_MAGIC)==InpMagic)trade.PositionClose(t);}}

//=========================================================================
//  CHART OBJECTS
//=========================================================================
void DeleteByPrefix(const string pfx){for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--){string n=ObjectName(0,i,0,-1);if(StringFind(n,pfx)==0)ObjectDelete(0,n);}}
void DeleteLevels(){ObjectDelete(0,PREFIX+"ORB_HIGH");ObjectDelete(0,PREFIX+"ORB_LOW");ObjectDelete(0,PREFIX+"ORB_TXT");}
void DeleteHist(){DeleteByPrefix(PREFIX+"HIST_");}
void DeleteLive(){DeleteByPrefix(PREFIX+"LIVE_");}
void DeleteDash(){DeleteByPrefix(PREFIX+"DASH_");DeleteByPrefix(PREFIX+"BTN_");}

void CreateRect(const string name,int x,int y,int w,int h,color bg,color brd)
{
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,MathMax(1,w));ObjectSetInteger(0,obj,OBJPROP_YSIZE,MathMax(1,h));
   ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,obj,OBJPROP_BORDER_COLOR,brd);
   ObjectSetInteger(0,obj,OBJPROP_BACK,false);ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,obj,OBJPROP_HIDDEN,true);
}
void CreateLabel(const string name,int x,int y,string text,color clr,int sz=9)
{
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);ObjectSetInteger(0,obj,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,sz);ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,obj,OBJPROP_HIDDEN,true);
}
void CreateButton(const string name,int x,int y,int w,int h,string text,color bg)
{
   string obj=PREFIX+name;
   if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");ObjectSetInteger(0,obj,OBJPROP_STATE,false);
}

//=========================================================================
//  SIGNAL ARROWS
//=========================================================================
void DrawSignalArrow(const string name,datetime t,double price,bool buy,bool hist)
{
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   else ObjectMove(0,name,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,buy?233:234);
   ObjectSetInteger(0,name,OBJPROP_COLOR,buy?clrLime:clrTomato);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,hist?2:3);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}
void DrawSignalText(const string name,datetime t,double price,string text,color clr)
{
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   else ObjectMove(0,name,0,t,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}

//=========================================================================
//  ORB LEVEL LINES
//=========================================================================
void DrawLevels()
{
   if(!g_orbReady)return;
   if(ObjectFind(0,PREFIX+"ORB_HIGH")<0)ObjectCreate(0,PREFIX+"ORB_HIGH",OBJ_HLINE,0,0,g_orbHigh);
   ObjectSetDouble(0,PREFIX+"ORB_HIGH",OBJPROP_PRICE,NormalizePrice(g_orbHigh));
   ObjectSetInteger(0,PREFIX+"ORB_HIGH",OBJPROP_COLOR,clrDodgerBlue);ObjectSetInteger(0,PREFIX+"ORB_HIGH",OBJPROP_WIDTH,2);
   if(ObjectFind(0,PREFIX+"ORB_LOW")<0)ObjectCreate(0,PREFIX+"ORB_LOW",OBJ_HLINE,0,0,g_orbLow);
   ObjectSetDouble(0,PREFIX+"ORB_LOW",OBJPROP_PRICE,NormalizePrice(g_orbLow));
   ObjectSetInteger(0,PREFIX+"ORB_LOW",OBJPROP_COLOR,clrTomato);ObjectSetInteger(0,PREFIX+"ORB_LOW",OBJPROP_WIDTH,2);
}

//=========================================================================
//  ORB BUILDING — uses g_rtSignalTf (runtime TF)
//=========================================================================
bool BuildOrbForNyDate(int y,int m,int d,double &hi,double &lo,datetime &os,datetime &oe,datetime &te,int &used,double &avgV)
{
   int sm=ParseClockMinutes(InpOrbStartNy,570);int em=ParseClockMinutes(InpOrbEndNy,585);int tem=ParseClockMinutes(InpTradeEndNy,960);
   os=NyLocalToServer(y,m,d,sm);oe=NyLocalToServer(y,m,d,em);te=NyLocalToServer(y,m,d,tem);
   hi=-DBL_MAX;lo=DBL_MAX;used=0;avgV=0;
   // Always build ORB from M1 data for precision (regardless of signal TF)
   MqlRates r[];int c=CopyRates(_Symbol,PERIOD_M1,os,oe,r);if(c<=0)return false;
   double tv=0;
   for(int i=0;i<c;i++){if(r[i].time<os||r[i].time>=oe)continue;hi=MathMax(hi,r[i].high);lo=MathMin(lo,r[i].low);tv+=(double)r[i].tick_volume;used++;}
   if(used<=0||hi<=lo||hi==-DBL_MAX||lo==DBL_MAX)return false;
   hi=NormalizePrice(hi);lo=NormalizePrice(lo);avgV=tv/(double)used;return true;
}
bool BuildOrb()
{
   if(g_orbReady)return true;if(TimeCurrent()<g_orbEndServer)return false;
   MqlRates r[];int c=CopyRates(_Symbol,PERIOD_M1,g_orbStartServer,g_orbEndServer,r);
   if(c<=0){Audit("orb_fail","",0,0,0,0,"no_data");return false;}
   double hi=-DBL_MAX,lo=DBL_MAX,tv=0;int used=0;
   for(int i=0;i<c;i++){if(r[i].time<g_orbStartServer||r[i].time>=g_orbEndServer)continue;hi=MathMax(hi,r[i].high);lo=MathMin(lo,r[i].low);tv+=(double)r[i].tick_volume;used++;}
   if(used<=0||hi<=lo){Audit("orb_fail","",0,0,0,0,"invalid used="+IntegerToString(used));return false;}
   g_orbHigh=NormalizePrice(hi);g_orbLow=NormalizePrice(lo);g_orbAvgVolume=tv/(double)used;g_orbReady=true;
   Audit("orb_ready","",0,0,0,0,"bars="+IntegerToString(used)+" range="+DoubleToString(hi-lo,_Digits));DrawLevels();return true;
}

//=========================================================================
//  HISTORICAL ATR COMPUTATION (manual from D1 bars)
//=========================================================================
double HistDailyAtr(datetime beforeDate,int period)
{
   MqlRates d1[];ArraySetAsSeries(d1,true);
   int c=CopyRates(_Symbol,PERIOD_D1,beforeDate,period+2,d1);
   if(c<3)return 0;
   int n=MathMin(period,c-1);double s=0;
   for(int i=1;i<=n&&i+1<c;i++){double tr=d1[i].high-d1[i].low;tr=MathMax(tr,MathAbs(d1[i].high-d1[i+1].close));tr=MathMax(tr,MathAbs(d1[i].low-d1[i+1].close));s+=tr;}
   return n>0?s/(double)n:0;
}

//=========================================================================
//  HISTORICAL BREAKOUT FINDER — uses g_rtSignalTf, respects delay
//  Returns pre-breakout rolling avg volume for fair volume comparison
//=========================================================================
bool FindHistBreakout(datetime from,datetime to,double hi,double lo,
                      string &dir,datetime &sigT,double &sigC,double &sigH,double &sigL,
                      double &sigVol,double &preBreakoutAvgVol)
{
   dir="";sigT=0;sigC=0;sigH=0;sigL=0;sigVol=0;preBreakoutAvgVol=0;
   // Apply confirmation delay
   datetime effectiveFrom = from;
   if(g_rtUseDelay && g_rtDelayMin > 0)
      effectiveFrom = from + g_rtDelayMin * 60;
   if(effectiveFrom >= to) return false;

   MqlRates r[];int c=CopyRates(_Symbol,g_rtSignalTf,effectiveFrom,to,r);if(c<=0)return false;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double mb=MathMax(0.0,InpMinBreakoutPoints)*pt;
   int bi=-1;string bd="";
   for(int i=0;i<c;i++)
   {
      if(r[i].time<effectiveFrom||r[i].time>to)continue;
      string d="";
      if(r[i].close>hi+mb)d="BUY";
      else if(r[i].close<lo-mb)d="SELL";
      if(d=="")continue;
      // Confirmation: check that the next N bars also confirm the breakout
      if(InpConfirmBars > 1 && i + InpConfirmBars - 1 < c)
      {
         bool confirmed = true;
         for(int cb = 1; cb < InpConfirmBars && i+cb < c; cb++)
         {
            if(d=="BUY" && r[i+cb].close <= hi) { confirmed = false; break; }
            if(d=="SELL" && r[i+cb].close >= lo) { confirmed = false; break; }
         }
         if(!confirmed) continue;
      }
      bi=i;bd=d;break; // first valid breakout
   }
   if(bi<0)return false;
   dir=bd;sigT=r[bi].time;sigC=r[bi].close;sigH=r[bi].high;sigL=r[bi].low;sigVol=(double)r[bi].tick_volume;
   // Calculate pre-breakout rolling average volume (20 bars before breakout)
   int lookback=MathMin(20,bi);
   if(lookback>0){double vs=0;for(int j=bi-lookback;j<bi;j++)vs+=(double)r[j].tick_volume;preBreakoutAvgVol=vs/(double)lookback;}
   return true;
}

//=========================================================================
//  HISTORICAL TRADE SIMULATION
//=========================================================================
struct HistResult
{
   int maxTp;       // 0,1,2,3
   string outcome;  // "TP1","TP2","TP3","SL","BE","open","timeout"
   double netR;     // net R-multiple
   bool isWin;      // maxTp >= 1
};

HistResult SimulateTrade(datetime sigTime,datetime tradeEnd,double entry,double sl,bool isBuy,
                         double tp1,double tp2,double tp3,bool useBE)
{
   HistResult res;res.maxTp=0;res.outcome="open";res.netR=0;res.isWin=false;
   MqlRates r[];int c=CopyRates(_Symbol,g_rtSignalTf,sigTime,tradeEnd,r);
   if(c<=1)return res;
   double effSl=sl;bool beApplied=false;
   for(int i=1;i<c;i++) // skip signal bar itself
   {
      if(r[i].time>tradeEnd)break;
      bool slHit=isBuy?(r[i].low<=effSl):(r[i].high>=effSl);
      bool t1Hit=isBuy?(r[i].high>=tp1):(r[i].low<=tp1);
      bool t2Hit=isBuy?(r[i].high>=tp2):(r[i].low<=tp2);
      bool t3Hit=isBuy?(r[i].high>=tp3):(r[i].low<=tp3);
      // Same-bar conflict: use bar open proximity to decide which hit first
      if(slHit&&t1Hit&&res.maxTp==0)
      {
         double distToTp1=isBuy?(tp1-r[i].open):(r[i].open-tp1);
         double distToSl=isBuy?(r[i].open-effSl):(effSl-r[i].open);
         if(distToTp1<distToSl){res.maxTp=1;if(useBE&&!beApplied){effSl=entry;beApplied=true;}res.outcome="BE";break;}
         else{res.outcome="SL";break;}
      }
      if(slHit&&res.maxTp==0){res.outcome="SL";break;}
      if(t1Hit&&res.maxTp<1){res.maxTp=1;if(useBE&&!beApplied){effSl=entry;beApplied=true;}}
      if(t2Hit&&res.maxTp<2)res.maxTp=2;
      if(t3Hit&&res.maxTp<3){res.maxTp=3;res.outcome="TP3";break;}
      if(slHit&&res.maxTp>0){res.outcome="BE";break;}
      if(i-1>=200){res.outcome="timeout";break;}
   }
   if(res.outcome=="open"&&res.maxTp>0)res.outcome="TP"+IntegerToString(res.maxTp);
   // Net R calculation
   double r1=MathMax(0.1,InpTp1R),r2=MathMax(0.1,InpTp2R),r3=MathMax(0.1,InpTp3R);
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      double leg1=res.maxTp>=1?r1:(res.outcome=="SL"?-1.0:0);
      double leg2=res.maxTp>=2?r2:(res.maxTp>=1&&useBE?0:-1.0);
      double leg3=res.maxTp>=3?r3:(res.maxTp>=1&&useBE?0:-1.0);
      if(res.outcome=="SL"&&res.maxTp==0){leg1=-1;leg2=-1;leg3=-1;}
      res.netR=(leg1+leg2+leg3)/3.0;
   }
   else
   {
      if(res.maxTp>=1)res.netR=MathMax(0.1,InpSingleTpR);
      else if(res.outcome=="SL")res.netR=-1.0;
   }
   res.isWin=res.maxTp>=1;
   return res;
}

//=========================================================================
//  HISTORICAL FILTER CHECKS (for simulation, using runtime toggles)
//=========================================================================
bool HistCheckAtr(double orbRange,datetime orbStart,string &reason)
{
   if(!g_rtFilterAtr)return true;
   double atr=HistDailyAtr(orbStart,InpAtrPeriod);
   if(atr<=0)return true;
   double pct=(orbRange/atr)*100.0;
   if(pct<InpMinRangeAtrPct){reason="ATR<"+DoubleToString(InpMinRangeAtrPct,0)+"%";return false;}
   if(pct>InpMaxRangeAtrPct){reason="ATR>"+DoubleToString(InpMaxRangeAtrPct,0)+"%";return false;}
   return true;
}
bool HistCheckVol(double sigVol,double avgVol,string &reason)
{
   if(!g_rtFilterVol)return true;
   if(avgVol<=0)return true;
   if(sigVol<avgVol*InpVolumeMultiplier){reason="VOL_LOW";return false;}
   return true;
}
bool HistCheckDay(int dow,string &reason)
{
   if(!g_rtFilterDay)return true;
   bool ok=false;
   if(dow==1&&InpTradeMonday)ok=true;if(dow==2&&InpTradeTuesday)ok=true;
   if(dow==3&&InpTradeWednesday)ok=true;if(dow==4&&InpTradeThursday)ok=true;
   if(dow==5&&InpTradeFriday)ok=true;
   if(!ok){reason="DAY";return false;}
   return true;
}

//=========================================================================
//  HISTORICAL SIGNAL DRAWING WITH SIMULATION
//=========================================================================
void DrawHistoricalSignals()
{
   if(!InpDrawHistoricalSignals){DeleteHist();g_histStatLine="off";return;}
   datetime now=TimeCurrent();
   if(!g_histNeedsRedraw&&g_lastHistBuild>0&&now-g_lastHistBuild<300)return;
   g_lastHistBuild=now;g_histNeedsRedraw=false;
   DeleteHist();

   datetime nyNow=ServerToNyLocal(now);MqlDateTime nySt;TimeToStruct(nyNow,nySt);
   datetime nyMid=MakeDateTime(nySt.year,nySt.mon,nySt.day,0,0,0);
   int days=MathMax(1,MathMin(30,InpHistoricalDays));
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(pt<=0)pt=0.0001;

   g_histTotal=0;g_histWins=0;g_histLosses=0;g_histNetR=0;
   int checked=0,drawn=0,filtered=0;

   Print("ORB15v3 ======= HIST REDRAW START ======= TF=",TfLabel(g_rtSignalTf),
         " Delay=",g_rtUseDelay?IntegerToString(g_rtDelayMin)+"min":"OFF",
         " ATR=",g_rtFilterAtr?"ON":"OFF"," VOL=",g_rtFilterVol?"ON":"OFF",
         " DAY=",g_rtFilterDay?"ON":"OFF"," BE=",g_rtBEOnTp1?"ON":"OFF",
         " TP=",DoubleToString(InpTp1R,1),"/",DoubleToString(InpTp2R,1),"/",DoubleToString(InpTp3R,1));

   for(int back=days-1;back>=0;back--)
   {
      datetime nyDay=nyMid-back*86400;MqlDateTime daySt;TimeToStruct(nyDay,daySt);
      if(daySt.day_of_week==0||daySt.day_of_week==6)continue;

      double hi,lo,avgV;datetime os,oe,te;int used;
      checked++;
      if(!BuildOrbForNyDate(daySt.year,daySt.mon,daySt.day,hi,lo,os,oe,te,used,avgV))
      {
         Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," ORB_FAIL no_data");
         continue;
      }

      // Day filter
      string fr="";
      if(!HistCheckDay(daySt.day_of_week,fr)){filtered++;Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr);continue;}
      // ATR filter
      if(!HistCheckAtr(hi-lo,os,fr)){filtered++;Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr," orbRange=",DoubleToString(hi-lo,_Digits));continue;}

      // Find breakout (uses g_rtSignalTf + delay)
      string dir;datetime sigT;double sigC,sigH,sigL,sigVol,preAvgVol;
      if(!FindHistBreakout(oe,te,hi,lo,dir,sigT,sigC,sigH,sigL,sigVol,preAvgVol))
      {
         Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," NO_BREAKOUT orbH=",DoubleToString(hi,_Digits)," orbL=",DoubleToString(lo,_Digits));
         continue;
      }

      // Volume filter: compare breakout bar to pre-breakout local average
      if(!HistCheckVol(sigVol,preAvgVol,fr)){filtered++;Print("ORB15v3 HIST day ",daySt.year,".",daySt.mon,".",daySt.day," FILTERED ",fr," sigVol=",DoubleToString(sigVol,0)," preAvg=",DoubleToString(preAvgVol,0));continue;}

      g_histTotal++;

      // Simulate trade
      bool isBuy=(dir=="BUY");
      double buffer=MathMax(0.0,InpSlBufferPoints)*pt;
      double entry=sigC;
      double sl=isBuy?(lo-buffer):(hi+buffer);
      double risk=MathAbs(entry-sl);if(risk<=pt)continue;
      double r1v=MathMax(0.1,InpTp1R),r2v=MathMax(0.1,InpTp2R),r3v=MathMax(0.1,InpTp3R);
      double tp1=NormalizePrice(isBuy?entry+risk*r1v:entry-risk*r1v);
      double tp2=NormalizePrice(isBuy?entry+risk*r2v:entry-risk*r2v);
      double tp3=NormalizePrice(isBuy?entry+risk*r3v:entry-risk*r3v);

      HistResult sim=SimulateTrade(sigT,te,entry,NormalizePrice(sl),isBuy,tp1,tp2,tp3,g_rtBEOnTp1);
      if(sim.isWin)g_histWins++;
      else if(sim.outcome=="SL")g_histLosses++;
      g_histNetR+=sim.netR;

      // Debug audit
      Print("ORB15v3 HIST #",g_histTotal," ",dir,
            " date=",daySt.year,".",daySt.mon,".",daySt.day,
            " entry=",DoubleToString(entry,_Digits),
            " sl=",DoubleToString(sl,_Digits),
            " tp1=",DoubleToString(tp1,_Digits),
            " tp2=",DoubleToString(tp2,_Digits),
            " tp3=",DoubleToString(tp3,_Digits),
            " risk=",DoubleToString(risk,_Digits),
            " outcome=",sim.outcome,
            " maxTp=",sim.maxTp,
            " netR=",DoubleToString(sim.netR,2));

      // Draw arrow with outcome
      double pad=MathMax((hi-lo)*0.12,pt*40.0);
      double arwP=isBuy?(sigL-pad):(sigH+pad);
      string dateKey=IntegerToString(daySt.year)+StringFormat("%02d%02d",daySt.mon,daySt.day);
      string base=PREFIX+"HIST_"+dateKey+"_"+dir+"_";

      color arwClr=sim.isWin?clrLime:(sim.outcome=="SL"?clrTomato:clrGold);
      int arwCode=isBuy?233:234;
      if(ObjectFind(0,base+"ARW")<0)ObjectCreate(0,base+"ARW",OBJ_ARROW,0,sigT,arwP);
      else ObjectMove(0,base+"ARW",0,sigT,arwP);
      ObjectSetInteger(0,base+"ARW",OBJPROP_ARROWCODE,arwCode);
      ObjectSetInteger(0,base+"ARW",OBJPROP_COLOR,arwClr);
      ObjectSetInteger(0,base+"ARW",OBJPROP_WIDTH,2);
      ObjectSetInteger(0,base+"ARW",OBJPROP_SELECTABLE,false);ObjectSetInteger(0,base+"ARW",OBJPROP_HIDDEN,false);

      // Result text with detail
      string txt=dir+" "+sim.outcome+" "+DoubleToString(sim.netR,1)+"R E="+DoubleToString(entry,_Digits);
      color txtClr=sim.isWin?clrPaleGreen:(sim.outcome=="SL"?clrLightSalmon:clrKhaki);
      double txtP=isBuy?arwP-pad*0.6:arwP+pad*0.6;
      DrawSignalText(base+"TXT",sigT,txtP,txt,txtClr);
      drawn++;
   }

   double wr=g_histTotal>0?(double)g_histWins/(double)g_histTotal*100.0:0;
   g_histStatLine=IntegerToString(g_histTotal)+" sig | "+IntegerToString(g_histWins)+"W "+IntegerToString(g_histLosses)+"L | WR "+DoubleToString(wr,1)+"% | Net "+DoubleToString(g_histNetR,1)+"R";
   if(filtered>0)g_histStatLine+=" | "+IntegerToString(filtered)+" filt";
   Print("ORB15v3 ======= HIST RESULT: ",g_histStatLine," checked=",checked," drawn=",drawn," =======");
   Audit("hist_redraw","",0,0,0,0,g_histStatLine+" days="+IntegerToString(days));
}

//=========================================================================
//  DASHBOARD (Nas-inspired design with toggle buttons + TF selector)
//=========================================================================
void DrawDashboard()
{
   if(!InpShowDashboard){DeleteDash();return;}
   int x=InpDashboardX,y=InpDashboardY;
   int W=520,H=310;

   // Shell
   CreateRect("DASH_BG",x,y,W,H,C'24,30,42',C'90,178,255');
   CreateRect("DASH_TOP",x,y,W,28,C'18,24,36',C'90,178,255');
   CreateRect("DASH_STRIPE",x+6,y+6,W-12,3,C'90,178,255',C'90,178,255');

   // Title
   CreateLabel("DASH_TITLE",x+12,y+10,"ORB15 COCKPIT v3.1 // "+ORB15_BUILD,C'216,222,230',9);

   UpdateDashboard();
}

void UpdateDashboard()
{
   if(!InpShowDashboard)return;
   int x=InpDashboardX,y=InpDashboardY;
   color acB=C'90,178,255';color muted=C'184,196,210';color steel=C'216,222,230';

   // Status line
   string state=g_rtEaEnabled?"EA ON":"EA OFF";
   string orb=g_orbReady?"READY":"WAIT";
   string exec=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG?"3-LEG":"SINGLE";
   CreateLabel("DASH_L1",x+12,y+34,state+" | ORB "+orb+" | "+exec+" | Signal: "+TfLabel(g_rtSignalTf),
      g_rtEaEnabled?C'80,255,180':C'221,55,78',8);

   // ORB info
   string delayTxt=g_rtUseDelay?IntegerToString(g_rtDelayMin)+"m delay":"no delay";
   CreateLabel("DASH_L2",x+12,y+50,
      "NY "+InpOrbStartNy+"-"+InpOrbEndNy+" | End "+InpTradeEndNy+" | GMT+"+DoubleToString(InpBrokerGmtOffsetHours,1)
      +" | "+delayTxt+" | Spread "+IntegerToString(CurrentSpreadPoints())+"pt",
      muted,8);
   CreateLabel("DASH_L3",x+12,y+66,
      "ORB H "+DoubleToString(g_orbHigh,_Digits)+" L "+DoubleToString(g_orbLow,_Digits)
      +" | Risk "+DoubleToString(InpRiskPerTradePct,1)+"% | Legs "+IntegerToString(OwnPositionCount()),
      clrWhite,8);

   // Separator
   CreateRect("DASH_SEP1",x+8,y+82,504,1,C'65,116,172',C'65,116,172');

   // Row 1: Filter toggle buttons
   CreateLabel("DASH_FLBL",x+12,y+88,"FILTERS:",acB,8);
   int bx=x+80,by=y+86,bw=72,bh=18,gap=3;
   CreateButton("BTN_ATR",bx,by,bw,bh,g_rtFilterAtr?"ATR:ON":"ATR:OFF",g_rtFilterAtr?C'30,120,70':C'80,80,80');
   CreateButton("BTN_VOL",bx+bw+gap,by,bw,bh,g_rtFilterVol?"VOL:ON":"VOL:OFF",g_rtFilterVol?C'30,120,70':C'80,80,80');
   CreateButton("BTN_DAY",bx+2*(bw+gap),by,bw,bh,g_rtFilterDay?"DAY:ON":"DAY:OFF",g_rtFilterDay?C'30,120,70':C'80,80,80');
   CreateButton("BTN_TIME",bx+3*(bw+gap),by,bw+4,bh,g_rtTimeExit?"TIME:ON":"TIME:OFF",g_rtTimeExit?C'30,120,70':C'80,80,80');
   CreateButton("BTN_BE",bx+4*(bw+gap)+4,by,bw-8,bh,g_rtBEOnTp1?"BE:ON":"BE:OFF",g_rtBEOnTp1?C'30,120,70':C'80,80,80');

   // Row 2: Signal TF selector + Delay toggle + EA toggle + Close All
   int r2y=y+108;
   CreateLabel("DASH_TFLBL",x+12,r2y+2,"SIGNAL:",acB,8);
   CreateButton("BTN_TF",x+80,r2y,60,18,"TF:"+TfLabel(g_rtSignalTf),C'38,101,176');
   CreateButton("BTN_DELAY",x+144,r2y,80,18,g_rtUseDelay?"DLY:"+IntegerToString(g_rtDelayMin)+"m":"DLY:OFF",g_rtUseDelay?C'30,120,70':C'80,80,80');

   CreateButton("BTN_EA",x+420,r2y,90,18,g_rtEaEnabled?"EA: ON":"EA: OFF",g_rtEaEnabled?C'30,150,95':C'178,37,57');
   CreateButton("BTN_CLOSEALL",x+330,r2y,86,18,"CLOSE ALL",C'178,37,57');

   // Separator
   CreateRect("DASH_SEP2",x+8,y+132,504,1,C'65,116,172',C'65,116,172');

   // Stats section
   double wr=g_histTotal>0?(double)g_histWins/(double)g_histTotal*100.0:0;
   color wrClr=wr>=50?C'80,255,180':C'255,95,140';

   CreateLabel("DASH_STITLE",x+12,y+138,IntegerToString(InpHistoricalDays)+"D BACKTEST ("+TfLabel(g_rtSignalTf)+")",acB,9);
   CreateLabel("DASH_STAT1",x+12,y+156,
      IntegerToString(g_histTotal)+" signals | "+IntegerToString(g_histWins)+" W  "+IntegerToString(g_histLosses)+" L | WR "+DoubleToString(wr,1)+"%",
      wrClr,9);
   CreateLabel("DASH_STAT2",x+12,y+174,
      "Net R: "+DoubleToString(g_histNetR,1)+"R"
      +" | Avg W: "+DoubleToString(g_histWins>0?g_histNetR/(double)g_histWins:0,1)+"R"
      +" | "+IntegerToString(g_histTotal-g_histWins-g_histLosses)+" open/timeout",
      muted,8);

   // TP config line
   string tpInfo=InpExecutionMode==ORB_EXEC_PARTIAL_3LEG
      ?"TP1="+DoubleToString(InpTp1R,1)+"R TP2="+DoubleToString(InpTp2R,1)+"R TP3="+DoubleToString(InpTp3R,1)+"R"
      :"TP="+DoubleToString(InpSingleTpR,1)+"R";
   CreateLabel("DASH_STAT3",x+12,y+190,tpInfo+" | Confirm="+IntegerToString(InpConfirmBars)+" bars | AutoLot "+BoolText(InpUseAutoRiskLot),C'134,158,182',7);

   // Win rate bar
   int barW=496,barH=14;
   CreateRect("DASH_WRBAR_BG",x+12,y+206,barW,barH,C'42,51,68',C'134,158,182');
   int fillW=(int)MathRound((double)barW*MathMax(0,MathMin(100,wr))/100.0);
   if(fillW>2)CreateRect("DASH_WRBAR_FILL",x+13,y+207,fillW-2,barH-2,wrClr,wrClr);

   // Separator
   CreateRect("DASH_SEP3",x+8,y+226,504,1,C'65,116,172',C'65,116,172');

   // Status line
   string sigTime=g_lastSignalBarTime>0?FmtTime(g_lastSignalBarTime):"-";
   CreateLabel("DASH_L4",x+12,y+232,
      "Signal "+sigTime+" | Taken "+BoolText(g_tradeTaken)+" | "+g_lastExecStatus,
      (g_lastExecStatus=="OPENED"||g_lastExecStatus=="READY")?C'80,255,180':C'255,204,82',8);
   if(g_lastFilterReason!="")
      CreateLabel("DASH_L5",x+12,y+248,"Filter: "+g_lastFilterReason,C'255,204,82',7);
   else
      CreateLabel("DASH_L5",x+12,y+248,"Chart TF can be any; EA reads "+TfLabel(g_rtSignalTf)+" data.",C'134,158,182',7);

   // Execution info
   CreateLabel("DASH_L6",x+12,y+264,tpInfo+" | Magic "+IntegerToString(InpMagic),C'134,158,182',7);

   // ORB range vs ATR context
   double atr=HistDailyAtr(TimeCurrent(),InpAtrPeriod);
   string atrCtx=atr>0?"ORB/ATR "+DoubleToString(g_orbReady?((g_orbHigh-g_orbLow)/atr)*100.0:0,1)+"%":"ATR --";
   CreateLabel("DASH_L7",x+12,y+280,atrCtx+" | Range "+DoubleToString(g_orbReady?g_orbHigh-g_orbLow:0,_Digits),C'134,158,182',7);
}

//=========================================================================
//  DAY RESET
//=========================================================================
bool ResetForNewNyDay()
{
   int y,m,d;int key=CurrentNyDayKey(y,m,d);if(key==g_nyDayKey)return false;
   g_nyDayKey=key;g_orbReady=false;g_tradeTaken=false;g_orbHigh=0;g_orbLow=0;g_orbAvgVolume=0;
   g_lastSignalBarTime=0;g_tradeDir=0;g_tradeEntry=0;g_tradeSl=0;g_tradeOpenTime=0;g_beMoved=false;
   g_tradeRisk=0;g_lastFilterReason="";g_lastExecStatus="READY";
   int sm=ParseClockMinutes(InpOrbStartNy,570);int em=ParseClockMinutes(InpOrbEndNy,585);int tem=ParseClockMinutes(InpTradeEndNy,960);
   g_orbStartServer=NyLocalToServer(y,m,d,sm);g_orbEndServer=NyLocalToServer(y,m,d,em);g_tradeEndServer=NyLocalToServer(y,m,d,tem);
   DeleteLevels();g_histNeedsRedraw=true;
   Audit("new_day","",0,0,0,0,"key="+IntegerToString(key));return true;
}

//=========================================================================
//  LIVE FILTERS — use g_rtSignalTf for all timeframe operations
//=========================================================================
bool CheckAtrFilter(string &r)
{
   if(!g_rtFilterAtr)return true;
   int h=iATR(_Symbol,PERIOD_D1,InpAtrPeriod);if(h==INVALID_HANDLE)return true;
   double v[];ArraySetAsSeries(v,true);int c=CopyBuffer(h,0,1,1,v);IndicatorRelease(h);
   if(c!=1||v[0]<=0)return true;
   double pct=((g_orbHigh-g_orbLow)/v[0])*100;
   if(pct<InpMinRangeAtrPct){r="ATR_NARROW "+DoubleToString(pct,1)+"%";return false;}
   if(pct>InpMaxRangeAtrPct){r="ATR_WIDE "+DoubleToString(pct,1)+"%";return false;}
   return true;
}
bool CheckVolFilter(string &r)
{
   if(!g_rtFilterVol)return true;
   int sh=InpUseClosedBarBreakout?1:0;
   long bv=iVolume(_Symbol,g_rtSignalTf,sh);
   // Rolling average of 20 bars before signal bar (fair baseline)
   double avgVol=0;int lookback=20;double vs=0;
   for(int i=sh+1;i<=sh+lookback;i++){long v=iVolume(_Symbol,g_rtSignalTf,i);if(v>0)vs+=(double)v;}
   avgVol=vs/(double)lookback;
   if(avgVol<=0)return true;
   double threshold=avgVol*InpVolumeMultiplier;
   if((double)bv<threshold){r="VOL_LOW "+IntegerToString(bv)+"<"+DoubleToString(threshold,0);return false;}
   return true;
}
bool CheckDayFilter(string &r){if(!g_rtFilterDay)return true;int y,m,d;CurrentNyDayKey(y,m,d);int dow=DayOfWeekForDate(y,m,d);bool ok=false;if(dow==1&&InpTradeMonday)ok=true;if(dow==2&&InpTradeTuesday)ok=true;if(dow==3&&InpTradeWednesday)ok=true;if(dow==4&&InpTradeThursday)ok=true;if(dow==5&&InpTradeFriday)ok=true;if(!ok){r="DAY_BLOCKED";return false;}return true;}

//=========================================================================
//  SIGNAL COMPUTE — uses g_rtSignalTf + confirmation delay
//=========================================================================
bool ComputeSignal(string &dir,datetime &bt,double &sc)
{
   dir="";bt=0;sc=0;if(!g_orbReady)return false;
   // Apply confirmation delay: don't accept signals until delay after ORB end
   datetime effectiveStart = g_orbEndServer;
   if(g_rtUseDelay && g_rtDelayMin > 0)
      effectiveStart = g_orbEndServer + g_rtDelayMin * 60;
   if(TimeCurrent()<effectiveStart||TimeCurrent()>g_tradeEndServer)return false;
   int sh=InpUseClosedBarBreakout?1:0;
   bt=iTime(_Symbol,g_rtSignalTf,sh);
   if(bt<=0||bt==g_lastSignalBarTime)return false;
   if(bt<effectiveStart)return false; // bar is from before delay window
   sc=iClose(_Symbol,g_rtSignalTf,sh);if(sc<=0)return false;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double mb=MathMax(0.0,InpMinBreakoutPoints)*pt;
   if(sc>g_orbHigh+mb)dir="BUY";else if(sc<g_orbLow-mb)dir="SELL";
   return dir!="";
}

//=========================================================================
//  TRADE EXECUTION
//=========================================================================
bool ExecSingle(string dir,double entry,double sl,double tp,double lot)
{
   trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(InpDeviationPoints);trade.SetTypeFillingBySymbol(_Symbol);
   return dir=="BUY"?trade.Buy(lot,_Symbol,0,sl,tp,"ORB15v3|"+dir):trade.Sell(lot,_Symbol,0,sl,tp,"ORB15v3|"+dir);
}
bool ExecThreeLegs(string dir,double entry,double sl,double tp1,double tp2,double tp3,double totalLot)
{
   double leg=NormalizeLegVolume(totalLot,3);
   if(leg<=0)return ExecSingle(dir,entry,sl,tp2,NormalizeVolume(totalLot));
   trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(InpDeviationPoints);trade.SetTypeFillingBySymbol(_Symbol);
   ENUM_ORDER_TYPE type=dir=="BUY"?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double price=dir=="BUY"?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double tps[3];tps[0]=tp1;tps[1]=tp2;tps[2]=tp3;
   string cm[3];cm[0]="ORB15v3_TP1|"+dir;cm[1]="ORB15v3_TP2|"+dir;cm[2]="ORB15v3_TP3|"+dir;
   ulong existing[];int ec=0;
   for(int p=PositionsTotal()-1;p>=0;p--){ulong t=PositionGetTicket(p);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;ArrayResize(existing,ec+1);existing[ec++]=t;}
   int opened=0;
   for(int i=0;i<3;i++){bool ok=trade.PositionOpen(_Symbol,type,leg,price,sl,tps[i],cm[i]);uint rc=trade.ResultRetcode();if(ok&&(rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED))opened++;else Print("ORB15v3 leg",i+1," fail ret=",rc);}
   if(opened>0&&opened<3){for(int p=PositionsTotal()-1;p>=0;p--){ulong t=PositionGetTicket(p);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;bool ex=false;for(int e=0;e<ec;e++)if(existing[e]==t){ex=true;break;}if(!ex)trade.PositionClose(t);}return false;}
   return opened==3;
}

//=========================================================================
//  TRADE MANAGEMENT
//=========================================================================
void ManagePositions()
{
   if(g_tradeDir==0||!OwnPositionExists()){if(g_tradeDir!=0){g_tradeDir=0;g_tradeOpenTime=0;g_beMoved=false;}return;}
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);if(bid<=0||ask<=0)return;
   // SL → BE
   if(g_rtBEOnTp1&&!g_beMoved&&g_tradeTp1>0)
   {
      bool tp1Hit=g_tradeDir>0?(bid>=g_tradeTp1):(ask<=g_tradeTp1);
      if(tp1Hit)
      {
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
         double be=NormalizePrice(g_tradeEntry+(g_tradeDir>0?1:-1)*InpBEOffsetPoints*pt);
         for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;trade.PositionModify(t,be,PositionGetDouble(POSITION_TP));}
         g_beMoved=true;g_tradeSl=be;Audit("sl_to_be",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,be,0,"tp1_hit");
      }
   }
   // TP touch watchdog
   if(InpEnforceTpTouchClose)
   {
      for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;double tp=PositionGetDouble(POSITION_TP);if(tp<=0)continue;int dir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;double tol=MathMax(0,InpTpTouchTolerancePts)*_Point;bool touched=dir>0?(bid+tol>=tp):(ask-tol<=tp);if(touched)trade.PositionClose(t);}
   }
   // Time exit
   if(g_rtTimeExit&&g_tradeOpenTime>0)
   {
      int elapsed=(int)(TimeCurrent()-g_tradeOpenTime);
      if(elapsed>=InpTimeExitMinutes*60)
      {
         double px=g_tradeDir>0?bid:ask;double prog=g_tradeDir>0?(px-g_tradeEntry):(g_tradeEntry-px);
         double progR=g_tradeRisk>0?prog/g_tradeRisk:0;
         if(progR<InpTimeExitMinProgress){Audit("time_exit",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,0,0,"R="+DoubleToString(progR,2));CloseAllOwn();g_tradeDir=0;g_tradeOpenTime=0;g_lastExecStatus="TIME_EXIT";}
      }
   }
}

//=========================================================================
//  MAIN SIGNAL PIPELINE — uses g_rtSignalTf
//=========================================================================
void TryOpenSignal()
{
   if(!g_rtEaEnabled)return;if(!BuildOrb())return;
   if(InpOneTradePerNyDay&&g_tradeTaken)return;if(OwnPositionExists())return;
   string dir;datetime bt;double sc;if(!ComputeSignal(dir,bt,sc))return;
   g_lastSignalBarTime=bt;
   string fr="";
   if(!CheckDayFilter(fr)||!CheckAtrFilter(fr)||!CheckVolFilter(fr)){g_lastFilterReason=fr;g_lastExecStatus="FILTERED";Audit("filtered",dir,0,sc,0,0,fr);return;}
   if(!SpreadAllowed()){g_lastFilterReason="SPREAD";g_lastExecStatus="FILTERED";return;}
   g_lastFilterReason="";
   // Draw arrows
   int sh=InpUseClosedBarBreakout?1:0;double sH=iHigh(_Symbol,g_rtSignalTf,sh),sL=iLow(_Symbol,g_rtSignalTf,sh);
   double pad=MathMax(MathAbs(g_orbHigh-g_orbLow)*0.12,SymbolInfoDouble(_Symbol,SYMBOL_POINT)*40.0);
   bool isBuy=dir=="BUY";double arwP=isBuy?(sL-pad):(sH+pad);
   DrawSignalArrow(PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+dir+"_ARW",bt,arwP,isBuy,false);
   DrawSignalText(PREFIX+"LIVE_"+IntegerToString((int)bt)+"_"+dir+"_TXT",bt,isBuy?arwP-pad*0.6:arwP+pad*0.6,"ORB LIVE "+dir,isBuy?clrLime:clrTomato);
   Audit("signal",dir,0,sc,0,0,"bar="+FmtTime(bt));
   // Tick & geometry
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;
   double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT);double buf=MathMax(0,InpSlBufferPoints)*pt;
   double entry=isBuy?tick.ask:tick.bid;double sl=isBuy?(g_orbLow-buf):(g_orbHigh+buf);
   double risk=MathAbs(entry-sl);if(risk<=pt)return;
   entry=NormalizePrice(entry);sl=NormalizePrice(sl);
   bool opened=false;
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      double tp1=NormalizePrice(isBuy?entry+risk*MathMax(.1,InpTp1R):entry-risk*MathMax(.1,InpTp1R));
      double tp2=NormalizePrice(isBuy?entry+risk*MathMax(.1,InpTp2R):entry-risk*MathMax(.1,InpTp2R));
      double tp3=NormalizePrice(isBuy?entry+risk*MathMax(.1,InpTp3R):entry-risk*MathMax(.1,InpTp3R));
      double lot=CalculateLot(entry,sl);opened=ExecThreeLegs(dir,entry,sl,tp1,tp2,tp3,lot);
      if(opened){g_tradeTp1=tp1;g_tradeTp2=tp2;g_tradeTp3=tp3;Audit("opened_3leg",dir,lot,entry,sl,tp3,"");}
   }
   else
   {
      double tp=NormalizePrice(isBuy?entry+risk*MathMax(.1,InpSingleTpR):entry-risk*MathMax(.1,InpSingleTpR));
      double lot=CalculateLot(entry,sl);opened=ExecSingle(dir,entry,sl,tp,lot);
      if(opened){g_tradeTp1=tp;g_tradeTp2=tp;g_tradeTp3=tp;Audit("opened",dir,lot,entry,sl,tp,"");}
   }
   if(opened){g_tradeTaken=true;g_tradeDir=isBuy?1:-1;g_tradeEntry=entry;g_tradeSl=sl;g_tradeOpenTime=TimeCurrent();g_beMoved=false;g_tradeRisk=risk;g_lastExecStatus="OPENED";}
   else{g_lastExecStatus="FAIL";Audit("order_fail",dir,0,entry,sl,0,"ret="+IntegerToString((int)trade.ResultRetcode()));}
}

//=========================================================================
//  EVENT HANDLERS
//=========================================================================
int OnInit()
{
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      ENUM_ACCOUNT_MARGIN_MODE mm=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING){Print("ORB15v3: 3-leg needs hedging. mode=",EnumToString(mm));return INIT_PARAMETERS_INCORRECT;}
   }
   trade.SetExpertMagicNumber(InpMagic);trade.SetDeviationInPoints(InpDeviationPoints);
   // Initialize runtime toggles from inputs
   g_rtFilterAtr=InpUseAtrRangeFilter;g_rtFilterVol=InpUseVolumeFilter;g_rtFilterDay=InpUseDayFilter;
   g_rtTimeExit=InpUseTimeExit;g_rtBEOnTp1=InpMoveToBEOnTp1;g_rtEaEnabled=InpEaEnabled;
   g_rtSignalTf=InpSignalTimeframe;
   g_rtDelayMin=InpBreakoutDelayMinutes;
   g_rtUseDelay=InpBreakoutDelayMinutes>0;
   g_lastHistBuild=0;g_histNeedsRedraw=true;
   ResetForNewNyDay();EventSetTimer(5);DrawDashboard();DrawHistoricalSignals();
   if(InpLogOnInit)Print("ORB15v3.1 init ",_Symbol," build=",ORB15_BUILD," tf=",TfLabel(g_rtSignalTf)," exec=",EnumToString(InpExecutionMode)," magic=",InpMagic,
                         " tp=",DoubleToString(InpTp1R,1),"/",DoubleToString(InpTp2R,1),"/",DoubleToString(InpTp3R,1),
                         " delay=",g_rtDelayMin,"min confirm=",InpConfirmBars,"bars");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(reason==REASON_REMOVE||reason==REASON_PROGRAM){DeleteLevels();DeleteDash();DeleteHist();DeleteLive();}
}

void OnTimer()
{
   bool dc=ResetForNewNyDay();BuildOrb();
   if(dc)DrawHistoricalSignals();
   TryOpenSignal();ManagePositions();UpdateDashboard();
}

void OnTick()
{
   ResetForNewNyDay();TryOpenSignal();ManagePositions();UpdateDashboard();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK)return;

   bool needRedraw=false;

   if(sparam==PREFIX+"BTN_ATR"){g_rtFilterAtr=!g_rtFilterAtr;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_VOL"){g_rtFilterVol=!g_rtFilterVol;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_DAY"){g_rtFilterDay=!g_rtFilterDay;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_TIME"){g_rtTimeExit=!g_rtTimeExit;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_BE"){g_rtBEOnTp1=!g_rtBEOnTp1;needRedraw=true;}
   else if(sparam==PREFIX+"BTN_TF")
   {
      // Cycle through M1 → M5 → M15 → M1...
      g_rtSignalTf=CycleTf(g_rtSignalTf);
      needRedraw=true;
      Print("ORB15v3 Signal TF changed to ",TfLabel(g_rtSignalTf));
   }
   else if(sparam==PREFIX+"BTN_DELAY")
   {
      // Cycle: OFF → 3m → 5m → 10m → OFF
      if(!g_rtUseDelay){g_rtUseDelay=true;g_rtDelayMin=3;}
      else if(g_rtDelayMin<=3){g_rtDelayMin=5;}
      else if(g_rtDelayMin<=5){g_rtDelayMin=10;}
      else{g_rtUseDelay=false;g_rtDelayMin=0;}
      needRedraw=true;
      Print("ORB15v3 Delay changed to ",g_rtUseDelay?IntegerToString(g_rtDelayMin)+"min":"OFF");
   }
   else if(sparam==PREFIX+"BTN_EA")
   {
      g_rtEaEnabled=!g_rtEaEnabled;g_lastExecStatus=g_rtEaEnabled?"READY":"EA_OFF";
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }
   else if(sparam==PREFIX+"BTN_CLOSEALL")
   {
      CloseAllOwn();g_tradeDir=0;g_tradeOpenTime=0;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;
   }

   if(needRedraw)
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      g_histNeedsRedraw=true;
      DrawHistoricalSignals();
      UpdateDashboard();
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+
