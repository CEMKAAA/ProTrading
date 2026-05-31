//+------------------------------------------------------------------+
//| Atomic MT4 Debug Scanner EA                                      |
//| Diagnostic only: scans Atomic chart objects and iCustom buffers.  |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "Atomic";
input string InpICustomParamsCsv = "";
input int    InpSignalShift = 0;
input int    InpScanBufferMax = 128;
input int    InpScanShiftMax = 30;
input double InpSignalAbsMin = 0.0000001;
input string InpIgnoreNamePatterns = "autotrade,->";
input string InpButtonName = "BTN_SCAN_ATOMIC";
input int    InpButtonX = 20;
input int    InpButtonY = 90;
input bool   InpLogAllObjects = true;
input int    InpObjectPrintLimit = 300;
input bool   InpLogOnlyFilteredObjects = false;
input string InpObjectNameFilterCsv = "circle,dot,setup,signal,buy,sell,entry";
input bool   InpPrintSignalCandidates = true;
input int    InpCandidateLookbackSeconds = 86400;
input bool   InpPrintLatestSignalNeighborhood = true;
input int    InpNeighborhoodBars = 3;
input int    InpNeighborhoodMaxRows = 160;

double g_params[];
int g_paramCount = 0;

string _trim(string s){ StringTrimLeft(s); StringTrimRight(s); return s; }
bool _is_signal_value(double v){ return MathIsValidNumber(v) && v != EMPTY_VALUE && MathAbs(v) >= InpSignalAbsMin; }
bool _contains_ci(string h,string n){ StringToLower(h); StringToLower(n); return StringLen(n)>0 && StringFind(h,n)>=0; }

bool _csv_name_hit(string csv,string name)
{
   string raw=_trim(csv);
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string parts[];
   int n=StringSplit(raw,44,parts);
   for(int i=0;i<n;i++)
   {
      string t=_trim(parts[i]);
      if(StringLen(t)>0 && _contains_ci(name,t))
         return true;
   }
   return false;
}

bool _csv_has_tokens(string csv)
{
   string raw=_trim(csv);
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string parts[];
   int n=StringSplit(raw,44,parts);
   for(int i=0;i<n;i++)
      if(StringLen(_trim(parts[i]))>0)
         return true;
   return false;
}

string _color_hex(color c)
{
   int r=((int)c)&0xFF,g=(((int)c)>>8)&0xFF,b=(((int)c)>>16)&0xFF;
   return StringFormat("#%02X%02X%02X",r,g,b);
}

string _fmt_time(datetime t){ return (t>0?TimeToString(t,TIME_DATE|TIME_SECONDS):"-"); }
string _fmt_price(double p){ return (MathIsValidNumber(p) && p != 0.0 ? DoubleToString(p,Digits) : "-"); }

bool _parse_atomic_object_name(string name,string &direction,string &kind,int &tpIndex,int &signalIndex)
{
   direction="";
   kind="";
   tpIndex=-1;
   signalIndex=-1;

   string clean=_trim(name);
   int nums[];
   int count=0;
   ArrayResize(nums,0);
   string cur="";
   int len=StringLen(clean);
   for(int i=0;i<len;i++)
   {
      int ch=StringGetChar(clean,i);
      if(ch>='0' && ch<='9')
         cur+=StringSubstr(clean,i,1);
      else if(StringLen(cur)>0)
      {
         ArrayResize(nums,count+1);
         nums[count++]=(int)StrToInteger(cur);
         cur="";
      }
   }
   if(StringLen(cur)>0)
   {
      ArrayResize(nums,count+1);
      nums[count++]=(int)StrToInteger(cur);
   }
   if(count<=0)
      return false;

   string lc=clean;
   StringToLower(lc);
   if(StringFind(lc,"buytrend")>=0 || StringFind(lc,"selltrend")>=0)
   {
      direction=(StringFind(lc,"buytrend")>=0 ? "BUY" : "SELL");
      kind="TREND";
      signalIndex=nums[count-1];
      return signalIndex>=0;
   }
   if(StringFind(lc,"buytxtsloss")>=0 || StringFind(lc,"selltxtsloss")>=0 || StringFind(lc,"buylevsloss")>=0 || StringFind(lc,"selllevsloss")>=0)
   {
      direction=(StringFind(lc,"buy")>=0 ? "BUY" : "SELL");
      kind="SL";
      signalIndex=nums[count-1];
      return signalIndex>=0;
   }
   if(StringFind(lc,"buytxttp")>=0 || StringFind(lc,"selltxttp")>=0 || StringFind(lc,"buyfibtp")>=0 || StringFind(lc,"sellfibtp")>=0 || StringFind(lc,"buylevtp")>=0 || StringFind(lc,"selllevtp")>=0)
   {
      if(count<2)
         return false;
      direction=(StringFind(lc,"buy")>=0 ? "BUY" : "SELL");
      kind="TP";
      tpIndex=nums[count-2];
      signalIndex=nums[count-1];
      return signalIndex>=0;
   }
   return false;
}

bool _find_latest_trend_object(string &direction,int &signalIndex,datetime &signalTime,double &entryPrice,string &trendName)
{
   direction="";
   signalIndex=-1;
   signalTime=0;
   entryPrice=0.0;
   trendName="";
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(_csv_name_hit(InpIgnoreNamePatterns,name))
         continue;
      string dir,kind;
      int tpIdx,sigIdx;
      if(!_parse_atomic_object_name(name,dir,kind,tpIdx,sigIdx) || kind!="TREND")
         continue;
      datetime t=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      double p=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
      if(t<=0 || !MathIsValidNumber(p) || p<=0.0)
         continue;
      if(t>signalTime)
      {
         direction=dir;
         signalIndex=sigIdx;
         signalTime=t;
         entryPrice=p;
         trendName=name;
      }
   }
   return signalTime>0 && signalIndex>=0 && StringLen(direction)>0;
}

bool _is_known_atomic_level_object(string name)
{
   string lc=name;
   StringToLower(lc);
   return (
      StringFind(lc,"txttp")>=0 ||
      StringFind(lc,"txtsloss")>=0 ||
      StringFind(lc,"fibtp")>=0 ||
      StringFind(lc,"levtp")>=0 ||
      StringFind(lc,"levsloss")>=0 ||
      StringFind(lc,"trend")>=0
   );
}

void PrintLatestSignalNeighborhood()
{
   if(!InpPrintLatestSignalNeighborhood)
      return;
   string dir,trendName;
   int sigIdx;
   datetime signalTime;
   double entryPrice;
   if(!_find_latest_trend_object(dir,sigIdx,signalTime,entryPrice,trendName))
   {
      Print("ATOMIC_NEAR_SIGNAL none: latest trend object not found");
      return;
   }
   int secPerBar=Period()*60;
   if(secPerBar<=0)
      secPerBar=60;
   int radiusSec=MathMax(secPerBar,MathMax(1,InpNeighborhoodBars)*secPerBar);
   datetime tMin=signalTime-radiusSec;
   datetime tMax=signalTime+radiusSec;
   PrintFormat(
      "ATOMIC_NEAR_SIGNAL anchor dir=%s idx=%d time=%s entry=%s trend='%s' radius_bars=%d",
      dir,sigIdx,_fmt_time(signalTime),_fmt_price(entryPrice),trendName,MathMax(1,InpNeighborhoodBars)
   );
   int total=ObjectsTotal(0,-1,-1);
   int printed=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(name==InpButtonName || _csv_name_hit(InpIgnoreNamePatterns,name))
         continue;
      datetime t0=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      if(t0<tMin || t0>tMax)
         continue;
      if(_is_known_atomic_level_object(name))
         continue;
      int type=(int)ObjectGetInteger(0,name,OBJPROP_TYPE);
      double p0=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
      long code=ObjectGetInteger(0,name,OBJPROP_ARROWCODE);
      color c=(color)ObjectGetInteger(0,name,OBJPROP_COLOR);
      string text=ObjectGetString(0,name,OBJPROP_TEXT);
      string tip=ObjectGetString(0,name,OBJPROP_TOOLTIP);
      PrintFormat(
         "ATOMIC_NEAR_SIGNAL row=%03d type=%d name='%s' time0=%s price0=%s code=%d color=%s text='%s' tip='%s'",
         i,type,name,_fmt_time(t0),_fmt_price(p0),(int)code,_color_hex(c),text,tip
      );
      if(++printed>=MathMax(20,InpNeighborhoodMaxRows))
         break;
   }
   Print("ATOMIC_NEAR_SIGNAL summary printed=",printed);
}

bool _parse_params()
{
   ArrayResize(g_params,0);
   g_paramCount=0;
   string raw=_trim(InpICustomParamsCsv);
   if(StringLen(raw)==0)
      return true;
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string toks[];
   int n=StringSplit(raw,44,toks);
   for(int i=0;i<n;i++)
   {
      string t=_trim(toks[i]);
      if(StringLen(t)<=0)
         continue;
      StringToLower(t);
      ArrayResize(g_params,g_paramCount+1);
      if(t=="true")
         g_params[g_paramCount++]=1.0;
      else if(t=="false")
         g_params[g_paramCount++]=0.0;
      else
         g_params[g_paramCount++]=StrToDouble(t);
   }
   return true;
}

double _buffer_value(int b,int sh)
{
   int c=g_paramCount;
   if(c<=0) return iCustom(NULL,0,InpIndicatorName,b,sh);
   if(c==1) return iCustom(NULL,0,InpIndicatorName,g_params[0],b,sh);
   if(c==2) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],b,sh);
   if(c==3) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],b,sh);
   if(c==4) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],g_params[3],b,sh);
   if(c==5) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],b,sh);
   if(c==6) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],b,sh);
   if(c==7) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],b,sh);
   if(c==8) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],b,sh);
   return iCustom(NULL,0,InpIndicatorName,b,sh);
}

void CreateButton()
{
   ObjectDelete(0,InpButtonName);
   ObjectCreate(0,InpButtonName,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,InpButtonName,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,InpButtonName,OBJPROP_XDISTANCE,InpButtonX);
   ObjectSetInteger(0,InpButtonName,OBJPROP_YDISTANCE,InpButtonY);
   ObjectSetInteger(0,InpButtonName,OBJPROP_XSIZE,170);
   ObjectSetInteger(0,InpButtonName,OBJPROP_YSIZE,30);
   ObjectSetString(0,InpButtonName,OBJPROP_TEXT,"SCAN ATOMIC");
   ObjectSetInteger(0,InpButtonName,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,InpButtonName,OBJPROP_BGCOLOR,C'30,90,180');
   ObjectSetInteger(0,InpButtonName,OBJPROP_HIDDEN,true);
   ChartRedraw(0);
}

void RunScan()
{
   int total=ObjectsTotal(0,-1,-1);
   Print("------------------------------------------------------------");
   Print("AtomicScanner MT4 | chart=",Symbol()," tf=",Period()," objects=",total," indicator=",InpIndicatorName);

   int printed=0,ignored=0;
   int typeCounts[64];
   ArrayInitialize(typeCounts,0);
   bool hasNameFilter=_csv_has_tokens(InpObjectNameFilterCsv);
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(name==InpButtonName)
         continue;
      if(_csv_name_hit(InpIgnoreNamePatterns,name))
      {
         ignored++;
         continue;
      }

      int type=(int)ObjectGetInteger(0,name,OBJPROP_TYPE);
      if(type>=0 && type<64)
         typeCounts[type]++;
      if(!InpLogAllObjects && type!=OBJ_ARROW)
         continue;
      if(InpLogOnlyFilteredObjects && hasNameFilter && !_csv_name_hit(InpObjectNameFilterCsv,name))
         continue;

      datetime t0=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      datetime t1=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,1);
      double p0=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
      double p1=ObjectGetDouble(0,name,OBJPROP_PRICE,1);
      long code=ObjectGetInteger(0,name,OBJPROP_ARROWCODE);
      color c=(color)ObjectGetInteger(0,name,OBJPROP_COLOR);
      string text=ObjectGetString(0,name,OBJPROP_TEXT);
      string tip=ObjectGetString(0,name,OBJPROP_TOOLTIP);

      PrintFormat(
         "ATOMIC_OBJ row=%03d type=%d name='%s' time0=%s price0=%s time1=%s price1=%s code=%d color=%s text='%s' tip='%s'",
         i,type,name,_fmt_time(t0),_fmt_price(p0),_fmt_time(t1),_fmt_price(p1),(int)code,_color_hex(c),text,tip
      );

      if(++printed>=MathMax(20,InpObjectPrintLimit))
         break;
   }
   Print("ATOMIC_OBJ summary printed=",printed," ignored_name=",ignored," total=",total);
   string typeSummary="";
   for(int tc=0;tc<64;tc++)
   {
      if(typeCounts[tc]>0)
         typeSummary += StringFormat(" type%d=%d",tc,typeCounts[tc]);
   }
   Print("ATOMIC_OBJ type_summary",typeSummary);

   if(InpPrintSignalCandidates)
   {
      datetime minTime=TimeCurrent()-MathMax(60,InpCandidateLookbackSeconds);
      int cprinted=0;
      for(int j=total-1;j>=0;j--)
      {
         string cname=ObjectName(0,j,-1,-1);
         if(cname==InpButtonName || _csv_name_hit(InpIgnoreNamePatterns,cname))
            continue;
         int ctype=(int)ObjectGetInteger(0,cname,OBJPROP_TYPE);
         datetime ct0=(datetime)ObjectGetInteger(0,cname,OBJPROP_TIME,0);
         if(ct0<=0 || ct0<minTime)
            continue;
         string lc=cname;
         StringToLower(lc);
         if(_is_known_atomic_level_object(cname))
            continue;
         double cp0=ObjectGetDouble(0,cname,OBJPROP_PRICE,0);
         long ccode=ObjectGetInteger(0,cname,OBJPROP_ARROWCODE);
         color cc=(color)ObjectGetInteger(0,cname,OBJPROP_COLOR);
         string ctext=ObjectGetString(0,cname,OBJPROP_TEXT);
         string ctip=ObjectGetString(0,cname,OBJPROP_TOOLTIP);
         PrintFormat(
            "ATOMIC_SIGNAL_CANDIDATE row=%03d type=%d name='%s' time0=%s price0=%s code=%d color=%s text='%s' tip='%s'",
            j,ctype,cname,_fmt_time(ct0),_fmt_price(cp0),(int)ccode,_color_hex(cc),ctext,ctip
         );
         if(++cprinted>=MathMax(20,InpObjectPrintLimit))
            break;
      }
      Print("ATOMIC_SIGNAL_CANDIDATE summary printed=",cprinted," lookback_sec=",MathMax(60,InpCandidateLookbackSeconds));
   }

   PrintLatestSignalNeighborhood();

   int maxB=MathMax(1,MathMin(512,InpScanBufferMax));
   int maxS=MathMax(1,MathMin(300,InpScanShiftMax));
   for(int b=0;b<maxB;b++)
   {
      string row="";
      bool active=false;
      for(int sh=0;sh<maxS;sh++)
      {
         double v=_buffer_value(b,sh);
         bool a=_is_signal_value(v);
         if(a) active=true;
         row+=StringFormat(" sh%d=%s%s",sh,DoubleToString(v,Digits),(a?"*":""));
      }
      if(active)
         Print("ATOMIC_BUFFER[",b,"]",row);
   }

   Print("------------------------------------------------------------");
}

int OnInit()
{
   _parse_params();
   CreateButton();
   Print("AtomicScanner loaded. Attach Atomic first if it draws chart objects, then press SCAN ATOMIC.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ ObjectDelete(0,InpButtonName); }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==InpButtonName)
   {
      ObjectSetInteger(0,InpButtonName,OBJPROP_STATE,false);
      RunScan();
   }
}

void OnTick(){}
