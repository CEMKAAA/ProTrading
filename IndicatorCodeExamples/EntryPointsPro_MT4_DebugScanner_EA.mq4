//+------------------------------------------------------------------+
//| Entry Points Pro MT4 Debug Scanner EA                                   |
//| Diagnostic only: scans Entry Points Pro chart objects and iCustom buffers|
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "Entry Points Pro IND_fix";
input string InpICustomParamsCsv = "";
input int    InpScanBufferMax = 128;
input int    InpScanShiftMax = 80;
input double InpSignalAbsMin = 0.0000001;
input string InpIgnoreNamePatterns = "autotrade,->";
input string InpButtonName = "BTN_SCAN_ENTRYPOINTS";
input int    InpButtonX = 20;
input int    InpButtonY = 130;
input bool   InpLogAllObjects = true;
input int    InpObjectPrintLimit = 500;
input bool   InpLogOnlyFilteredObjects = false;
input string InpObjectNameFilterCsv = "entry,points,pro,signal,buy,sell,long,short,arrow,entry,tp,sl,stop,target,take,profit";
input bool   InpPrintSignalCandidates = true;
input int    InpCandidateLookbackSeconds = 172800;
input bool   InpPrintLatestSetupNeighborhood = true;
input int    InpNeighborhoodBars = 10;
input int    InpNeighborhoodMaxRows = 180;
input bool   InpPrintBufferCandidates = true;
input int    InpBufferCandidateShiftMax = 100;
input int    InpBufferCandidatePrintLimit = 48;
input double InpPriceMinFactor = 0.20;
input double InpPriceMaxFactor = 5.00;

double g_params[];
int g_paramCount = 0;

string _trim(string s){ StringTrimLeft(s); StringTrimRight(s); return s; }

bool _is_signal_value(double v)
{
   return MathIsValidNumber(v) && v != EMPTY_VALUE && MathAbs(v) >= InpSignalAbsMin;
}

bool _contains_ci(string h,string n)
{
   StringToLower(h);
   StringToLower(n);
   return StringLen(n)>0 && StringFind(h,n)>=0;
}

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

string _fmt_price(double p)
{
   return (MathIsValidNumber(p) && p != 0.0 && p != EMPTY_VALUE ? DoubleToString(p,Digits) : "-");
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
      string tl=t;
      StringToLower(tl);
      ArrayResize(g_params,g_paramCount+1);
      if(tl=="true")
         g_params[g_paramCount++]=1.0;
      else if(tl=="false")
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

double _ref_price()
{
   double bid=MarketInfo(Symbol(),MODE_BID);
   if(bid<=0.0)
      bid=Close[0];
   return bid;
}

bool _valid_price_like(double v)
{
   if(!MathIsValidNumber(v) || v == EMPTY_VALUE || v == 2147483647.0 || v <= 0.0)
      return false;
   double p=_ref_price();
   if(p<=0.0)
      return true;
   return (v > p * MathMax(0.01,InpPriceMinFactor) && v < p * MathMax(0.02,InpPriceMaxFactor));
}

string _buffer_short_row(int bufferIndex,int maxShift,bool priceOnly)
{
   string row="";
   int n=MathMax(1,MathMin(30,maxShift));
   for(int sh=0; sh<n; sh++)
   {
      double v=_buffer_value(bufferIndex,sh);
      bool active=(priceOnly ? _valid_price_like(v) : _is_signal_value(v));
      row += StringFormat(" sh%d=%s%s",sh,DoubleToString(v,Digits),(active?"*":""));
   }
   return row;
}

string _object_blob(string name)
{
   string text=ObjectGetString(0,name,OBJPROP_TEXT);
   string tip=ObjectGetString(0,name,OBJPROP_TOOLTIP);
   string out=name+" "+text+" "+tip;
   return out;
}

bool _is_directional_object(string name,string &dir)
{
   dir="";
   string blob=_object_blob(name);
   string lc=blob;
   StringToLower(lc);
   bool buy=(StringFind(lc,"buy")>=0 || StringFind(lc,"long")>=0);
   bool sell=(StringFind(lc,"sell")>=0 || StringFind(lc,"short")>=0);
   if(buy && !sell){ dir="BUY"; return true; }
   if(sell && !buy){ dir="SELL"; return true; }

   int type=(int)ObjectGetInteger(0,name,OBJPROP_TYPE);
   long code=ObjectGetInteger(0,name,OBJPROP_ARROWCODE);
   color c=(color)ObjectGetInteger(0,name,OBJPROP_COLOR);
   string hex=_color_hex(c);
   StringToLower(hex);
   if(type==OBJ_ARROW)
   {
      if(code==233 || code==241){ dir="BUY"; return true; }
      if(code==234 || code==242){ dir="SELL"; return true; }
   }
   if(hex=="#00ff00" || hex=="#32cd32" || hex=="#008000" || hex=="#00fa9a"){ dir="BUY_COLOR_GUESS"; return true; }
   if(hex=="#ff0000" || hex=="#dc143c" || hex=="#ff6347" || hex=="#b22222"){ dir="SELL_COLOR_GUESS"; return true; }
   return false;
}

bool _is_signal_candidate_object(string name)
{
   string blob=_object_blob(name);
   if(_csv_name_hit(InpObjectNameFilterCsv,blob))
      return true;
   string dir;
   if(_is_directional_object(name,dir))
      return true;
   return false;
}

bool _find_latest_directional_object(string &direction,datetime &signalTime,double &entryPrice,string &objName)
{
   direction="";
   signalTime=0;
   entryPrice=0.0;
   objName="";
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(name==InpButtonName || _csv_name_hit(InpIgnoreNamePatterns,name))
         continue;
      string dir;
      if(!_is_directional_object(name,dir))
         continue;
      datetime t0=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      double p0=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
      if(t0<=0)
         continue;
      if(t0>signalTime)
      {
         direction=dir;
         signalTime=t0;
         entryPrice=p0;
         objName=name;
      }
   }
   return signalTime>0 && StringLen(direction)>0;
}

void PrintLatestSetupNeighborhood()
{
   if(!InpPrintLatestSetupNeighborhood)
      return;
   string dir,name;
   datetime signalTime;
   double entryPrice;
   if(!_find_latest_directional_object(dir,signalTime,entryPrice,name))
   {
      Print("ENTRYPOINTS_NEAR_SETUP none: latest directional object not found");
      return;
   }
   int secPerBar=Period()*60;
   if(secPerBar<=0)
      secPerBar=60;
   int radiusSec=MathMax(secPerBar,MathMax(1,InpNeighborhoodBars)*secPerBar);
   datetime tMin=signalTime-radiusSec;
   datetime tMax=signalTime+radiusSec;
   PrintFormat(
      "ENTRYPOINTS_NEAR_SETUP anchor dir=%s time=%s price=%s name='%s' radius_bars=%d",
      dir,_fmt_time(signalTime),_fmt_price(entryPrice),name,MathMax(1,InpNeighborhoodBars)
   );

   int total=ObjectsTotal(0,-1,-1);
   int printed=0;
   for(int i=total-1;i>=0;i--)
   {
      string oname=ObjectName(0,i,-1,-1);
      if(oname==InpButtonName || _csv_name_hit(InpIgnoreNamePatterns,oname))
         continue;
      datetime t0=(datetime)ObjectGetInteger(0,oname,OBJPROP_TIME,0);
      if(t0<tMin || t0>tMax)
         continue;
      int type=(int)ObjectGetInteger(0,oname,OBJPROP_TYPE);
      datetime t1=(datetime)ObjectGetInteger(0,oname,OBJPROP_TIME,1);
      double p0=ObjectGetDouble(0,oname,OBJPROP_PRICE,0);
      double p1=ObjectGetDouble(0,oname,OBJPROP_PRICE,1);
      long code=ObjectGetInteger(0,oname,OBJPROP_ARROWCODE);
      color c=(color)ObjectGetInteger(0,oname,OBJPROP_COLOR);
      string text=ObjectGetString(0,oname,OBJPROP_TEXT);
      string tip=ObjectGetString(0,oname,OBJPROP_TOOLTIP);
      PrintFormat(
         "ENTRYPOINTS_NEAR_SETUP row=%03d type=%d name='%s' time0=%s price0=%s time1=%s price1=%s code=%d color=%s text='%s' tip='%s'",
         i,type,oname,_fmt_time(t0),_fmt_price(p0),_fmt_time(t1),_fmt_price(p1),(int)code,_color_hex(c),text,tip
      );
      if(++printed>=MathMax(20,InpNeighborhoodMaxRows))
         break;
   }
   Print("ENTRYPOINTS_NEAR_SETUP summary printed=",printed);
}

void PrintBufferCandidates()
{
   if(!InpPrintBufferCandidates)
      return;
   int maxB=MathMax(1,MathMin(512,InpScanBufferMax));
   int maxS=MathMax(5,MathMin(300,InpBufferCandidateShiftMax));
   double ref=_ref_price();
   int printed=0;

   for(int b=0;b<maxB;b++)
   {
      int priceCount=0;
      int sparseSignals=0;
      int transitions=0;
      int lastActive=-1;
      double first=0.0,last=0.0,minV=0.0,maxV=0.0;
      for(int sh=0;sh<maxS;sh++)
      {
         double v=_buffer_value(b,sh);
         bool active=_valid_price_like(v);
         if(active)
         {
            if(priceCount==0)
            {
               first=v;
               minV=v;
               maxV=v;
            }
            last=v;
            if(v<minV) minV=v;
            if(v>maxV) maxV=v;
            priceCount++;
         }
         else if(_is_signal_value(v))
         {
            sparseSignals++;
         }
         int cur=active ? 1 : 0;
         if(lastActive>=0 && cur!=lastActive)
            transitions++;
         lastActive=cur;
      }
      if(priceCount<=0 && sparseSignals<=0)
         continue;
      double coverage=100.0*priceCount/maxS;
      string quality="signal_or_sparse";
      if(coverage>=80.0) quality="continuous_price_level";
      else if(coverage>=25.0) quality="segmented_price_level";
      PrintFormat(
         "ENTRYPOINTS_BUFFER_CANDIDATE buffer=%d price_valid=%d/%d coverage=%.1f%% sparse_signal_values=%d transitions=%d quality=%s first=%s last=%s min=%s max=%s row=%s",
         b,priceCount,maxS,coverage,sparseSignals,transitions,quality,
         DoubleToString(first,Digits),DoubleToString(last,Digits),DoubleToString(minV,Digits),DoubleToString(maxV,Digits),
         _buffer_short_row(b,MathMin(20,maxS),priceCount>0)
      );
      if(++printed>=MathMax(8,InpBufferCandidatePrintLimit))
         break;
   }
   Print("ENTRYPOINTS_BUFFER_CANDIDATE summary printed=",printed," buffers_scanned=",maxB," shifts=",maxS," ref=",DoubleToString(ref,Digits));
}

void CreateButton()
{
   ObjectDelete(0,InpButtonName);
   ObjectCreate(0,InpButtonName,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,InpButtonName,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,InpButtonName,OBJPROP_XDISTANCE,InpButtonX);
   ObjectSetInteger(0,InpButtonName,OBJPROP_YDISTANCE,InpButtonY);
   ObjectSetInteger(0,InpButtonName,OBJPROP_XSIZE,190);
   ObjectSetInteger(0,InpButtonName,OBJPROP_YSIZE,30);
   ObjectSetString(0,InpButtonName,OBJPROP_TEXT,"SCAN ENTRY POINTS");
   ObjectSetInteger(0,InpButtonName,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,InpButtonName,OBJPROP_BGCOLOR,C'30,90,180');
   ObjectSetInteger(0,InpButtonName,OBJPROP_HIDDEN,true);
   ChartRedraw(0);
}

void RunScan()
{
   int total=ObjectsTotal(0,-1,-1);
   Print("------------------------------------------------------------");
   Print("EntryPointsProScanner MT4 | chart=",Symbol()," tf=",Period()," objects=",total," indicator=",InpIndicatorName);

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
      if(InpLogOnlyFilteredObjects && hasNameFilter && !_csv_name_hit(InpObjectNameFilterCsv,_object_blob(name)))
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
         "ENTRYPOINTS_OBJ row=%03d type=%d name='%s' time0=%s price0=%s time1=%s price1=%s code=%d color=%s text='%s' tip='%s'",
         i,type,name,_fmt_time(t0),_fmt_price(p0),_fmt_time(t1),_fmt_price(p1),(int)code,_color_hex(c),text,tip
      );
      if(++printed>=MathMax(20,InpObjectPrintLimit))
         break;
   }
   Print("ENTRYPOINTS_OBJ summary printed=",printed," ignored_name=",ignored," total=",total);

   string typeSummary="";
   for(int tc=0;tc<64;tc++)
      if(typeCounts[tc]>0)
         typeSummary += StringFormat(" type%d=%d",tc,typeCounts[tc]);
   Print("ENTRYPOINTS_OBJ type_summary",typeSummary);

   if(InpPrintSignalCandidates)
   {
      datetime minTime=TimeCurrent()-MathMax(60,InpCandidateLookbackSeconds);
      int cprinted=0;
      for(int j=total-1;j>=0;j--)
      {
         string cname=ObjectName(0,j,-1,-1);
         if(cname==InpButtonName || _csv_name_hit(InpIgnoreNamePatterns,cname))
            continue;
         datetime ct0=(datetime)ObjectGetInteger(0,cname,OBJPROP_TIME,0);
         if(ct0<=0 || ct0<minTime)
            continue;
         if(!_is_signal_candidate_object(cname))
            continue;
         int ctype=(int)ObjectGetInteger(0,cname,OBJPROP_TYPE);
         double cp0=ObjectGetDouble(0,cname,OBJPROP_PRICE,0);
         datetime ct1=(datetime)ObjectGetInteger(0,cname,OBJPROP_TIME,1);
         double cp1=ObjectGetDouble(0,cname,OBJPROP_PRICE,1);
         long ccode=ObjectGetInteger(0,cname,OBJPROP_ARROWCODE);
         color cc=(color)ObjectGetInteger(0,cname,OBJPROP_COLOR);
         string ctext=ObjectGetString(0,cname,OBJPROP_TEXT);
         string ctip=ObjectGetString(0,cname,OBJPROP_TOOLTIP);
         string dir="";
         _is_directional_object(cname,dir);
         PrintFormat(
            "ENTRYPOINTS_SIGNAL_CANDIDATE row=%03d dir=%s type=%d name='%s' time0=%s price0=%s time1=%s price1=%s code=%d color=%s text='%s' tip='%s'",
            j,dir,ctype,cname,_fmt_time(ct0),_fmt_price(cp0),_fmt_time(ct1),_fmt_price(cp1),(int)ccode,_color_hex(cc),ctext,ctip
         );
         if(++cprinted>=MathMax(20,InpObjectPrintLimit))
            break;
      }
      Print("ENTRYPOINTS_SIGNAL_CANDIDATE summary printed=",cprinted," lookback_sec=",MathMax(60,InpCandidateLookbackSeconds));
   }

   PrintLatestSetupNeighborhood();
   PrintBufferCandidates();

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
         row += StringFormat(" sh%d=%s%s",sh,DoubleToString(v,Digits),(a?"*":""));
      }
      if(active)
         Print("ENTRYPOINTS_BUFFER[",b,"]",row);
   }

   Print("------------------------------------------------------------");
}

int OnInit()
{
   _parse_params();
   CreateButton();
   Print("EntryPointsProScanner loaded. Attach Entry Points Pro first if it draws chart objects, then press SCAN ENTRY POINTS.");
   Print("Default indicator name: ",InpIndicatorName);
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

