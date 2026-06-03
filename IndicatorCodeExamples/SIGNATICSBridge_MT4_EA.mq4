//+------------------------------------------------------------------+
//| SIGNATICS Bridge MT4 EA                                          |
//| Reads SIGNATICS-ALGO V2 chart objects and posts V2 bridge events.|
//+------------------------------------------------------------------+
#property strict

#define SIGNATICS_BRIDGE_BUILD "2026-06-03.1145-chartobject-atomic-grade-strict-groups"

input string InpIndicatorName = "SIGNATICS-ALGO V2 (2)";
input int    InpPollSeconds = 1;
input bool   InpLogOnInit = true;
input bool   InpLogInitialSetup = true;
input bool   InpLogOnlyOnChange = true;
input bool   InpDebugObjects = false;
input bool   InpDebugDiscoveryOnNone = false;
input int    InpNoneDiscoveryIntervalSeconds = 10;
input int    InpNoneLogIntervalSeconds = 300;
input int    InpInitialSetupRetrySeconds = 30;
input bool   InpLogInitialDiscoverySummary = true;
input string InpIgnoreNamePatterns = "autotrade,->";
input bool   InpEnableProTradePost = true;
input bool   InpSendUnregisterOnDeinit = true;
input bool   InpSendInitialConfirmedOnStart = false;
input bool   InpSendResolvedStateEvents = true;
input int    InpResolvedHeartbeatSeconds = 900;
input int    InpRegisterHeartbeatSeconds = 120;
input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "signatics";
input string InpBridgeSignalMode = "buffer"; // buffer | chart_object
input int    InpHttpTimeoutMs = 5000;
input bool   InpPreferGroupedSetup = true;
input bool   InpAllowDashboardFallback = false;
input bool   InpRejectInvalidGeometry = true;
input int    InpMaxGroupCandidates = 300;
input bool   InpAllowLevelObjectFallback = false;
input bool   InpLogOnlyTradeSignals = true;
input bool   InpLogPostResponses = false;
input bool   InpLogHandshakeResponses = true;
input bool   InpLogRejectedGeometry = false;
input int    InpMaxConfirmedBarAgeSeconds = 180;
input bool   InpEnableFastSignalBuffers = true;
input int    InpFastBuyBufferIndex = 0;
input int    InpFastSellBufferIndex = 1;
input int    InpFastSignalLookbackBars = 2;
input int    InpFastSignalHistoryLookbackBars = 1000;
input bool   InpSendBufferHistoryResolvedOnInit = true;
input bool   InpLogFastBufferSignals = true;
input bool   InpScanFastBuffersOnTick = true;
input int    InpBufferHistoryNoneLogSeconds = 300;
input bool   InpAllowObjectConfirmedFallback = false;
input bool   InpChartObjectStrictGroups = true;
input bool   InpChartObjectRequireAllTps = true;
input int    InpChartObjectMaxSlotTimeSkewSeconds = 5;
input int    InpChartObjectStableSeconds = 1;
input bool   InpChartObjectRequireFreshConfirmed = true;

string   g_lastEventId = "";
string   g_lastConfirmedEventId = "";
datetime g_lastResolvedPostTime = 0;
datetime g_lastRegisterPostTime = 0;
datetime g_lastNoneDiscoveryTime = 0;
datetime g_lastNoneLogTime = 0;
datetime g_initialSetupRetryUntil = 0;
bool     g_baselineSetupSeen = false;
datetime g_initialDiscoveryLastPrint = 0;
int      g_initialDiscoveryPrints = 0;
string   g_lastFastBufferEventId = "";
string   g_lastFastConfirmedDirection = "";
datetime g_lastFastConfirmedSignalTime = 0;
datetime g_lastBufferHistoryNoneLogTime = 0;
string   g_pendingObjectEventId = "";
datetime g_pendingObjectFirstSeen = 0;

string _trim(string s){ StringTrimLeft(s); StringTrimRight(s); return s; }

string _compact_bridge_response(string response)
{
   string out=_trim(response);
   StringReplace(out,"\r"," ");
   StringReplace(out,"\n"," ");
   if(StringLen(out)>500)
      out=StringSubstr(out,0,500)+"...";
   return out;
}

bool _should_log_handshake_response(string eventKind,string reason)
{
   if(!InpLogHandshakeResponses)
      return false;
   string evt=_trim(eventKind);
   string why=_trim(reason);
   if(evt=="unregister")
      return true;
   if(evt=="register")
      return (why=="init" || why=="init_retry");
   return (why=="init" || why=="init_retry");
}

string _lower_copy(string s)
{
   string out=s;
   StringToLower(out);
   return out;
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

string _tf_to_string(int tf)
{
   if(tf==PERIOD_M1) return "M1";
   if(tf==PERIOD_M5) return "M5";
   if(tf==PERIOD_M15) return "M15";
   if(tf==PERIOD_M30) return "M30";
   if(tf==PERIOD_H1) return "H1";
   if(tf==PERIOD_H4) return "H4";
   if(tf==PERIOD_D1) return "D1";
   if(tf==PERIOD_W1) return "W1";
   if(tf==PERIOD_MN1) return "MN1";
   return IntegerToString(tf);
}

string _fmt_time(datetime t){ return (t>0?TimeToString(t,TIME_DATE|TIME_SECONDS):"-"); }

string _fmt_price(double p)
{
   if(!MathIsValidNumber(p) || p==EMPTY_VALUE || p==2147483647.0 || p<=0.0)
      return "-";
   return DoubleToString(p,Digits);
}

string _json_escape(string s)
{
   string out=s;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"\"","\\\"");
   StringReplace(out,"\r\n","\\n");
   StringReplace(out,"\n","\\n");
   StringReplace(out,"\r","\\n");
   return out;
}

string _normalize_base_url(string baseUrl)
{
   string b=_trim(baseUrl);
   if(StringLen(b)==0)
      b="http://127.0.0.1";
   if(StringSubstr(b,0,7)!="http://" && StringSubstr(b,0,8)!="https://")
      b="http://"+b;
   while(StringLen(b)>0 && StringSubstr(b,StringLen(b)-1,1)=="/")
      b=StringSubstr(b,0,StringLen(b)-1);
   return b;
}

string _normalize_path(string apiPath)
{
   string p=_trim(apiPath);
   if(StringLen(p)==0)
      p="/api/v1/mt4/bridge/signal";
   if(StringSubstr(p,0,1)!="/")
      p="/"+p;
   return p;
}

string _build_endpoint(string baseUrl,string apiPath)
{
   return _normalize_base_url(baseUrl)+_normalize_path(apiPath);
}

datetime _timer_now()
{
   datetime nowTs=TimeCurrent();
   if(nowTs<=0)
      nowTs=TimeLocal();
   return nowTs;
}

string _event_ts_now(){ return TimeToString(_timer_now(),TIME_DATE|TIME_SECONDS); }

string _setup_event_id(string direction,datetime signalTime,double entry,double sl,double tp1,double tp2,double tp3)
{
   return StringFormat(
      "%s|%s|%s|%I64d|%s|%s|%s|%s|%s",
      Symbol(),
      _bridge_signal_mode(),
      direction,
      (long)signalTime,
      DoubleToString(entry,Digits),
      DoubleToString(sl,Digits),
      DoubleToString(tp1,Digits),
      DoubleToString(tp2,Digits),
      DoubleToString(tp3,Digits)
   );
}

string _bridge_signal_mode()
{
   string mode=_lower_copy(_trim(InpBridgeSignalMode));
   StringReplace(mode,"-","_");
   StringReplace(mode," ","_");
   if(mode=="chart" || mode=="object" || mode=="chartobject" || mode=="chart_objects" || mode=="chart_object")
      return "chart_object";
   return "buffer";
}

bool _is_buffer_mode()
{
   return _bridge_signal_mode()=="buffer";
}

bool _is_chart_object_mode()
{
   return _bridge_signal_mode()=="chart_object";
}

bool _fast_buffers_active()
{
   return _is_buffer_mode() && InpEnableFastSignalBuffers;
}

bool _object_confirm_active()
{
   return _is_chart_object_mode() || (!_fast_buffers_active()) || InpAllowObjectConfirmedFallback;
}

string _bridge_indicator_label()
{
   string base=_trim(InpIndicatorName);
   if(StringLen(base)<=0)
      base="SIGNATICS";
   if(_is_chart_object_mode())
      return base+" [ChartObject]";
   return base+" [Buffer]";
}

string _fast_buffer_event_id(string direction,datetime signalTime,double entry,int bufferIndex,int shift)
{
   return StringFormat(
      "%s|%s|%s|fastbuf|%s|%I64d|%d|%d|%s",
      Symbol(),_tf_to_string(Period()),_bridge_signal_mode(),direction,(long)signalTime,bufferIndex,shift,DoubleToString(entry,Digits)
   );
}

bool _valid_signal_buffer_value(double value)
{
   if(!MathIsValidNumber(value))
      return false;
   if(value==EMPTY_VALUE || value==2147483647.0 || value<=0.0)
      return false;
   return true;
}

bool _read_signal_buffer(int bufferIndex,int shift,double &value)
{
   ResetLastError();
   value=iCustom(Symbol(),Period(),InpIndicatorName,bufferIndex,shift);
   if(GetLastError()!=0)
      ResetLastError();
   return _valid_signal_buffer_value(value);
}

void _insert_buffer_candidate(string candDir,datetime candTime,double candEntry,int candBuffer,int candShift,
                              string &bestDir,datetime &bestTime,double &bestEntry,int &bestBuffer,int &bestShift,
                              string &secondDir,datetime &secondTime,double &secondEntry,int &secondBuffer,int &secondShift)
{
   if((candDir!="BUY" && candDir!="SELL") || candTime<=0 || !_valid_signal_buffer_value(candEntry))
      return;
   if(candTime>bestTime)
   {
      secondDir=bestDir;
      secondTime=bestTime;
      secondEntry=bestEntry;
      secondBuffer=bestBuffer;
      secondShift=bestShift;
      bestDir=candDir;
      bestTime=candTime;
      bestEntry=candEntry;
      bestBuffer=candBuffer;
      bestShift=candShift;
      return;
   }
   if(candTime==bestTime)
      return;
   if(candTime>secondTime)
   {
      secondDir=candDir;
      secondTime=candTime;
      secondEntry=candEntry;
      secondBuffer=candBuffer;
      secondShift=candShift;
   }
}

bool _find_fast_buffer_signal_by_rank(int rank,int maxShift,string &direction,datetime &signalTime,double &entry,int &bufferIndex,int &shiftOut)
{
   direction="";
   signalTime=0;
   entry=0.0;
   bufferIndex=-1;
   shiftOut=-1;
   if(!_fast_buffers_active())
      return false;

   int cappedRank=MathMax(0,MathMin(1,rank));
   int scanMax=MathMax(0,maxShift);
   datetime bestTime=0;
   double bestEntry=0.0;
   string bestDir="";
   int bestBuf=-1;
   int bestShift=-1;
   datetime secondTime=0;
   double secondEntry=0.0;
   string secondDir="";
   int secondBuf=-1;
   int secondShift=-1;
   for(int sh=0; sh<=scanMax; sh++)
   {
      double buyVal=0.0;
      if(_read_signal_buffer(InpFastBuyBufferIndex,sh,buyVal))
      {
         datetime t=iTime(Symbol(),Period(),sh);
         _insert_buffer_candidate("BUY",t,buyVal,InpFastBuyBufferIndex,sh,bestDir,bestTime,bestEntry,bestBuf,bestShift,secondDir,secondTime,secondEntry,secondBuf,secondShift);
      }
      double sellVal=0.0;
      if(_read_signal_buffer(InpFastSellBufferIndex,sh,sellVal))
      {
         datetime t2=iTime(Symbol(),Period(),sh);
         _insert_buffer_candidate("SELL",t2,sellVal,InpFastSellBufferIndex,sh,bestDir,bestTime,bestEntry,bestBuf,bestShift,secondDir,secondTime,secondEntry,secondBuf,secondShift);
      }
   }
   if(cappedRank==0)
   {
      direction=bestDir;
      signalTime=bestTime;
      entry=bestEntry;
      bufferIndex=bestBuf;
      shiftOut=bestShift;
   }
   else
   {
      direction=secondDir;
      signalTime=secondTime;
      entry=secondEntry;
      bufferIndex=secondBuf;
      shiftOut=secondShift;
   }
   if(direction!="BUY" && direction!="SELL")
      return false;
   if(signalTime<=0 || !_valid_signal_buffer_value(entry))
      return false;
   return true;
}

bool _find_latest_fast_buffer_signal(string &direction,datetime &signalTime,double &entry,int &bufferIndex,int &shiftOut)
{
   return _find_fast_buffer_signal_by_rank(0,InpFastSignalLookbackBars,direction,signalTime,entry,bufferIndex,shiftOut);
}

bool _find_latest_history_buffer_signal(string &direction,datetime &signalTime,double &entry,int &bufferIndex,int &shiftOut)
{
   return _find_fast_buffer_signal_by_rank(0,InpFastSignalHistoryLookbackBars,direction,signalTime,entry,bufferIndex,shiftOut);
}

bool _find_previous_history_buffer_signal(string &direction,datetime &signalTime,double &entry,int &bufferIndex,int &shiftOut)
{
   return _find_fast_buffer_signal_by_rank(1,InpFastSignalHistoryLookbackBars,direction,signalTime,entry,bufferIndex,shiftOut);
}

void _print_buffer_history_snapshot(string reason)
{
   if(!InpLogFastBufferSignals || !_fast_buffers_active())
      return;

   string direction;
   datetime signalTime;
   double entry;
   int bufferIndex,shift;
   if(_find_previous_history_buffer_signal(direction,signalTime,entry,bufferIndex,shift))
   {
      PrintFormat(
         "SIGNATICSBridge previous_buffer_signal reason=%s symbol=%s tf=%s dir=%s bar=%s entry=%s buffer=%d shift=%d history_lookback=%d",
         reason,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),bufferIndex,shift,MathMax(0,InpFastSignalHistoryLookbackBars)
      );
   }
}

bool _chart_object_confirm_ready(string eventId,string reason,datetime signalTime)
{
   if(!_is_chart_object_mode())
      return true;
   if(InpChartObjectRequireFreshConfirmed && !_confirmed_bar_fresh(signalTime))
   {
      PrintFormat(
         "SIGNATICSBridge chart_object_confirm_suppressed reason=%s event_id='%s' why=stale_signal bar=%s age_sec=%d max_age_sec=%d",
         reason,eventId,_fmt_time(signalTime),(int)MathMax(0,_timer_now()-signalTime),_max_confirmed_bar_age_sec()
      );
      return false;
   }
   int stableSeconds=MathMax(0,InpChartObjectStableSeconds);
   if(stableSeconds<=0)
      return true;
   datetime nowTs=_timer_now();
   if(g_pendingObjectEventId!=eventId)
   {
      g_pendingObjectEventId=eventId;
      g_pendingObjectFirstSeen=nowTs;
      PrintFormat(
         "SIGNATICSBridge chart_object_confirm_pending reason=%s event_id='%s' stable_sec=%d bar=%s",
         reason,eventId,stableSeconds,_fmt_time(signalTime)
      );
      return false;
   }
   int age=(int)(nowTs-g_pendingObjectFirstSeen);
   if(age<stableSeconds)
   {
      PrintFormat(
         "SIGNATICSBridge chart_object_confirm_pending reason=%s event_id='%s' age=%d stable_sec=%d",
         reason,eventId,age,stableSeconds
      );
      return false;
   }
   return true;
}

bool _matches_last_fast_signal(string direction,datetime signalTime)
{
   if(g_lastFastConfirmedSignalTime<=0)
      return false;
   if(direction!=g_lastFastConfirmedDirection)
      return false;
   int tolerance=MathMax(_tf_seconds()*2,120);
   return MathAbs((int)(signalTime-g_lastFastConfirmedSignalTime))<=tolerance;
}

bool _heartbeat_due(datetime lastPostTime)
{
   int sec=MathMax(0,InpResolvedHeartbeatSeconds);
   if(sec<=0)
      return false;
   datetime nowTs=_timer_now();
   if(lastPostTime<=0)
      return true;
   return (nowTs-lastPostTime)>=sec;
}

bool _register_heartbeat_due()
{
   int sec=MathMax(0,InpRegisterHeartbeatSeconds);
   if(sec<=0)
      return false;
   datetime nowTs=_timer_now();
   if(g_lastRegisterPostTime<=0)
      return true;
   return (nowTs-g_lastRegisterPostTime)>=sec;
}

bool _buffer_history_none_log_due()
{
   int sec=MathMax(0,InpBufferHistoryNoneLogSeconds);
   if(sec<=0)
      return false;
   datetime nowTs=_timer_now();
   if(g_lastBufferHistoryNoneLogTime<=0)
      return true;
   return (nowTs-g_lastBufferHistoryNoneLogTime)>=sec;
}

int _tf_seconds()
{
   int tf=Period();
   if(tf==PERIOD_M1) return 60;
   if(tf==PERIOD_M5) return 300;
   if(tf==PERIOD_M15) return 900;
   if(tf==PERIOD_M30) return 1800;
   if(tf==PERIOD_H1) return 3600;
   if(tf==PERIOD_H4) return 14400;
   if(tf==PERIOD_D1) return 86400;
   return 300;
}

int _max_confirmed_bar_age_sec()
{
   int configured=MathMax(0,InpMaxConfirmedBarAgeSeconds);
   return (configured>0 ? configured : MathMax(180,(int)MathRound(_tf_seconds()*2.5)));
}

bool _confirmed_bar_fresh(datetime signalTime)
{
   if(signalTime<=0)
      return false;
   datetime nowTs=_timer_now();
   return (nowTs-signalTime)<=_max_confirmed_bar_age_sec();
}

void MaybePostRegisterHeartbeat(string reason)
{
   if(!InpEnableProTradePost || !_register_heartbeat_due())
      return;
   _post_signatics_bridge_event("register","",-1,0.0,0.0,0.0,0.0,0.0,"",reason,false);
   g_lastRegisterPostTime=_timer_now();
}

bool _none_log_due(string reason)
{
   if(reason=="init")
      return true;
   int sec=MathMax(1,InpNoneLogIntervalSeconds);
   datetime nowTs=_timer_now();
   if(g_lastNoneLogTime<=0)
      return true;
   return (nowTs-g_lastNoneLogTime)>=sec;
}

bool _valid_price(double value)
{
   return MathIsValidNumber(value) && value!=EMPTY_VALUE && value!=2147483647.0 && value>0.0;
}

double _object_price0(string name)
{
   double p=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
   return (_valid_price(p)?p:0.0);
}

datetime _object_time0(string name)
{
   return (datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
}

string _object_text(string name)
{
   return ObjectGetString(0,name,OBJPROP_TEXT);
}

string _find_object_name(string wanted)
{
   if(ObjectFind(0,wanted)>=0)
      return wanted;

   string wantedLc=_lower_copy(wanted);
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(_lower_copy(name)==wantedLc)
         return name;
   }
   for(int j=total-1;j>=0;j--)
   {
      string candidate=ObjectName(0,j,-1,-1);
      if(StringFind(_lower_copy(candidate),wantedLc)>=0)
         return candidate;
   }
   return "";
}

bool _object_exists(string name)
{
   return StringLen(_find_object_name(name))>0;
}

double _parse_first_price_from_text(string text)
{
   string s=_trim(text);
   string cur="";
   bool seenDigit=false;
   int len=StringLen(s);
   for(int i=0;i<len;i++)
   {
      int ch=StringGetChar(s,i);
      bool ok=(ch>='0' && ch<='9') || ch=='.' || ch=='-';
      if(ok)
      {
         cur += StringSubstr(s,i,1);
         if(ch>='0' && ch<='9')
            seenDigit=true;
      }
      else if(StringLen(cur)>0 && seenDigit)
      {
         double v=StrToDouble(cur);
         if(_valid_price(v))
            return v;
         cur="";
         seenDigit=false;
      }
      else
      {
         cur="";
         seenDigit=false;
      }
   }
   if(StringLen(cur)>0 && seenDigit)
   {
      double last=StrToDouble(cur);
      if(_valid_price(last))
         return last;
   }
   return 0.0;
}

double _parse_last_price_from_text(string text)
{
   string s=_trim(text);
   string cur="";
   string lastToken="";
   bool seenDigit=false;
   int len=StringLen(s);
   for(int i=0;i<len;i++)
   {
      int ch=StringGetChar(s,i);
      bool ok=(ch>='0' && ch<='9') || ch=='.' || ch=='-';
      if(ok)
      {
         cur += StringSubstr(s,i,1);
         if(ch>='0' && ch<='9')
            seenDigit=true;
      }
      else if(StringLen(cur)>0 && seenDigit)
      {
         lastToken=cur;
         cur="";
         seenDigit=false;
      }
      else
      {
         cur="";
         seenDigit=false;
      }
   }
   if(StringLen(cur)>0 && seenDigit)
      lastToken=cur;
   if(StringLen(lastToken)>0)
   {
      double v=StrToDouble(lastToken);
      if(_valid_price(v))
         return v;
   }
   return 0.0;
}

double _price_from_object_or_text(string name)
{
   string actual=_find_object_name(name);
   if(StringLen(actual)<=0)
      return 0.0;
   double p=_object_price0(actual);
   if(_valid_price(p))
      return p;
   double txt=_parse_last_price_from_text(_object_text(actual));
   if(_valid_price(txt))
      return txt;
   return 0.0;
}

bool _group_slot_read(int groupIndex,int slot,string &actualName,datetime &slotTime,double &slotPrice,string &slotText)
{
   actualName="";
   slotTime=0;
   slotPrice=0.0;
   slotText="";
   string wanted=StringFormat("SA_SL_%d_%d",groupIndex,slot);
   actualName=_find_object_name(wanted);
   if(StringLen(actualName)<=0)
      return false;
   slotTime=_object_time0(actualName);
   slotText=_object_text(actualName);
   slotPrice=_object_price0(actualName);
   if(!_valid_price(slotPrice))
   {
      if(slot==0)
         slotPrice=_parse_first_price_from_text(slotText);
      else
         slotPrice=_parse_last_price_from_text(slotText);
   }
   return slotTime>0 && _valid_price(slotPrice);
}

bool _group_slot_time_ok(datetime baseTime,datetime slotTime)
{
   if(baseTime<=0 || slotTime<=0)
      return false;
   int maxSkew=MathMax(0,InpChartObjectMaxSlotTimeSkewSeconds);
   if(maxSkew<=0)
      return baseTime==slotTime;
   return MathAbs((int)(baseTime-slotTime))<=maxSkew;
}

string _clean_direction_text(string text)
{
   string s=_lower_copy(text);
   string compact=s;
   StringReplace(compact," ","");
   StringReplace(compact,"\t","");
   StringReplace(compact,"\r","");
   StringReplace(compact,"\n","");
   StringReplace(compact,".","");
   StringReplace(compact,"-","");
   StringReplace(compact,"_","");
   if(StringFind(s,"buy")>=0 || StringFind(compact,"buy")>=0 || StringFind(s,"long")>=0 || StringFind(compact,"long")>=0)
      return "BUY";
   if(StringFind(s,"sell")>=0 || StringFind(compact,"sell")>=0 || StringFind(s,"short")>=0 || StringFind(compact,"short")>=0)
      return "SELL";
   return "";
}

datetime _parse_signal_time(string text)
{
   string s=_trim(text);
   if(StringLen(s)<16)
      return 0;
   return StringToTime(s);
}

bool _setup_geometry_ok(string direction,double entry,double sl,double tp1,double tp2,double tp3);

bool _parse_int_after_prefix(string name,string prefix,int &idx,int &slot)
{
   idx=-1;
   slot=-1;
   int start=StringFind(name,prefix);
   if(start<0)
      return false;
   string rest=StringSubstr(name,start+StringLen(prefix));
   string parts[];
   int n=StringSplit(rest,95,parts);
   if(n<2)
      return false;
   idx=(int)StrToInteger(parts[0]);
   slot=(int)StrToInteger(parts[1]);
   return idx>=0 && slot>=0;
}

bool _find_latest_dashboard_signal(string &direction,datetime &signalTime,double &entry,double &sl,double &tp1,double &tp2,double &tp3,string &sourceName)
{
   direction="";
   signalTime=0;
   entry=0.0;
   sl=0.0;
   tp1=0.0;
   tp2=0.0;
   tp3=0.0;
   sourceName="";

   string dirObj=_find_object_name("SA_DB_S_V0");
   if(StringLen(dirObj)<=0)
      return false;
   direction=_clean_direction_text(_object_text(dirObj));
   if(direction!="BUY" && direction!="SELL")
      return false;

   entry=_price_from_object_or_text("SA_DB_L_V0");
   sl=_price_from_object_or_text("SA_DB_L_V1");
   tp1=_price_from_object_or_text("SA_DB_T_V0");
   tp2=_price_from_object_or_text("SA_DB_T_V1");
   tp3=_price_from_object_or_text("SA_DB_T_V2");
   string timeObj=_find_object_name("SA_DB_S_V3");
   signalTime=(StringLen(timeObj)>0 ? _parse_signal_time(_object_text(timeObj)) : 0);
   sourceName="SA_DB";

   if(entry<=0.0 || sl<=0.0 || tp1<=0.0)
      return false;
   if(InpRejectInvalidGeometry && !_setup_geometry_ok(direction,entry,sl,tp1,tp2,tp3))
   {
      if(InpLogRejectedGeometry)
      {
         PrintFormat(
            "SIGNATICSBridge dashboard_setup_rejected reason=invalid_geometry dir=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s",
            direction,_fmt_price(entry),_fmt_price(sl),_fmt_price(tp1),_fmt_price(tp2),_fmt_price(tp3)
         );
      }
      return false;
   }
   return true;
}

bool _find_latest_level_signal(string &direction,datetime &signalTime,double &entry,double &sl,double &tp1,double &tp2,double &tp3,string &sourceName)
{
   direction="";
   signalTime=0;
   entry=0.0;
   sl=0.0;
   tp1=0.0;
   tp2=0.0;
   tp3=0.0;
   sourceName="";

   entry=_price_from_object_or_text("SA_Lv_Entry_Lb");
   if(entry<=0.0)
      entry=_price_from_object_or_text("SA_Lv_Entry_Ln");
   if(entry<=0.0)
      entry=_price_from_object_or_text("SA_Lv_Entry_Rb");

   sl=_price_from_object_or_text("SA_Lv_SL_Lb");
   if(sl<=0.0)
      sl=_price_from_object_or_text("SA_Lv_SL_Ln");
   if(sl<=0.0)
      sl=_price_from_object_or_text("SA_Lv_SL_Rb");

   tp1=_price_from_object_or_text("SA_Lv_TP1_Lb");
   if(tp1<=0.0)
      tp1=_price_from_object_or_text("SA_Lv_TP1_Ln");
   if(tp1<=0.0)
      tp1=_price_from_object_or_text("SA_Lv_TP1_Rb");

   tp2=_price_from_object_or_text("SA_Lv_TP2_Lb");
   if(tp2<=0.0)
      tp2=_price_from_object_or_text("SA_Lv_TP2_Ln");
   if(tp2<=0.0)
      tp2=_price_from_object_or_text("SA_Lv_TP2_Rb");

   tp3=_price_from_object_or_text("SA_Lv_TP3_Lb");
   if(tp3<=0.0)
      tp3=_price_from_object_or_text("SA_Lv_TP3_Ln");
   if(tp3<=0.0)
      tp3=_price_from_object_or_text("SA_Lv_TP3_Rb");

   string entryObj=_find_object_name("SA_Lv_Entry_Lb");
   if(StringLen(entryObj)<=0)
      entryObj=_find_object_name("SA_Lv_Entry_Ln");
   if(StringLen(entryObj)<=0)
      entryObj=_find_object_name("SA_Lv_Entry_Rb");
   signalTime=(StringLen(entryObj)>0 ? _object_time0(entryObj) : 0);
   if(signalTime<=0)
      signalTime=_timer_now();

   if(entry<=0.0 || sl<=0.0 || tp1<=0.0)
      return false;

   if(sl < entry && tp1 > entry)
      direction="BUY";
   else if(sl > entry && tp1 < entry)
      direction="SELL";
   else
      return false;

   if(InpRejectInvalidGeometry && !_setup_geometry_ok(direction,entry,sl,tp1,tp2,tp3))
   {
      if(InpLogRejectedGeometry)
      {
         PrintFormat(
            "SIGNATICSBridge level_setup_rejected reason=invalid_geometry dir=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s",
            direction,_fmt_price(entry),_fmt_price(sl),_fmt_price(tp1),_fmt_price(tp2),_fmt_price(tp3)
         );
      }
      return false;
   }
   sourceName="SA_Lv";
   return true;
}

bool _setup_geometry_ok(string direction,double entry,double sl,double tp1,double tp2,double tp3)
{
   if(direction!="BUY" && direction!="SELL")
      return false;
   if(!_valid_price(entry) || !_valid_price(sl) || !_valid_price(tp1))
      return false;
   bool hasTp2=_valid_price(tp2);
   bool hasTp3=_valid_price(tp3);
   double pointTol=MathMax(Point*2.0,0.00000001);
   if(direction=="BUY")
   {
      if(!(sl < entry-pointTol && tp1 > entry+pointTol))
         return false;
      if(hasTp2 && !(tp2 >= tp1-pointTol && tp2 > entry+pointTol))
         return false;
      if(hasTp3 && hasTp2 && !(tp3 >= tp2-pointTol && tp3 > entry+pointTol))
         return false;
      return true;
   }
   if(!(sl > entry+pointTol && tp1 < entry-pointTol))
      return false;
   if(hasTp2 && !(tp2 <= tp1+pointTol && tp2 < entry-pointTol))
      return false;
   if(hasTp3 && hasTp2 && !(tp3 <= tp2+pointTol && tp3 < entry-pointTol))
      return false;
   return true;
}

bool _find_group_signal_by_rank(int rank,string &direction,datetime &signalTime,double &entry,double &sl,double &tp1,double &tp2,double &tp3,string &sourceName)
{
   direction="";
   signalTime=0;
   entry=0.0;
   sl=0.0;
   tp1=0.0;
   tp2=0.0;
   tp3=0.0;
   sourceName="";

   int total=ObjectsTotal(0,-1,-1);
   int idxs[512];
   datetime times[512];
   string dirs[512];
   double entries[512];
   ArrayInitialize(idxs,-1);
   ArrayInitialize(times,0);
   ArrayInitialize(entries,0.0);
   for(int init=0; init<512; init++)
   {
      dirs[init]="";
   }
   int count=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(_csv_name_hit(InpIgnoreNamePatterns,name))
         continue;
      int idx,slot;
      if(!_parse_int_after_prefix(name,"SA_SL_",idx,slot))
         continue;
      if(slot!=0)
         continue;
      string dir=_clean_direction_text(_object_text(name));
      if(dir!="BUY" && dir!="SELL")
         continue;
      datetime t=_object_time0(name);
      double e=_parse_first_price_from_text(_object_text(name));
      if(!_valid_price(e))
         e=_object_price0(name);
      if(!_valid_price(e) || t<=0)
         continue;

      bool already=false;
      for(int a=0;a<count;a++)
      {
         if(idxs[a]==idx)
         {
            already=true;
            if(t>times[a])
            {
               times[a]=t;
               dirs[a]=dir;
               entries[a]=e;
            }
            break;
         }
      }
      if(already)
         continue;
      if(count>=512)
         break;
      idxs[count]=idx;
      times[count]=t;
      dirs[count]=dir;
      entries[count]=e;
      count++;
   }

   for(int s=0;s<count-1;s++)
   {
      for(int j=s+1;j<count;j++)
      {
         if(times[j]>times[s])
         {
            int ti=idxs[s]; idxs[s]=idxs[j]; idxs[j]=ti;
            datetime tt=times[s]; times[s]=times[j]; times[j]=tt;
            string td=dirs[s]; dirs[s]=dirs[j]; dirs[j]=td;
            double te=entries[s]; entries[s]=entries[j]; entries[j]=te;
         }
      }
   }

   int maxCandidates=MathMax(1,MathMin(512,InpMaxGroupCandidates));
   int validSeen=0;
   for(int c=0;c<count && c<maxCandidates;c++)
   {
      int useIdx=idxs[c];
      datetime useTime=times[c];
      string useDir=dirs[c];
      double useEntry=entries[c];
      if(useIdx<0 || useTime<=0 || useDir=="")
         continue;

      string base=StringFormat("SA_SL_%d_",useIdx);
      string entryName,slName,tp1Name,tp2Name,tp3Name;
      datetime entryTime,slTime,tp1Time,tp2Time,tp3Time;
      double slotEntry,slotSl,slotTp1,slotTp2,slotTp3;
      string entryText,slText,tp1Text,tp2Text,tp3Text;
      bool hasEntry=_group_slot_read(useIdx,0,entryName,entryTime,slotEntry,entryText);
      bool hasSl=_group_slot_read(useIdx,1,slName,slTime,slotSl,slText);
      bool hasTp1=_group_slot_read(useIdx,2,tp1Name,tp1Time,slotTp1,tp1Text);
      bool hasTp2=_group_slot_read(useIdx,3,tp2Name,tp2Time,slotTp2,tp2Text);
      bool hasTp3=_group_slot_read(useIdx,4,tp3Name,tp3Time,slotTp3,tp3Text);
      if(hasEntry)
      {
         useEntry=slotEntry;
         useTime=entryTime;
      }
      double useSl=(hasSl ? slotSl : 0.0);
      double useTp1=(hasTp1 ? slotTp1 : 0.0);
      double useTp2=(hasTp2 ? slotTp2 : 0.0);
      double useTp3=(hasTp3 ? slotTp3 : 0.0);
      if(InpChartObjectStrictGroups && (!hasEntry || !hasSl || !hasTp1 || (InpChartObjectRequireAllTps && (!hasTp2 || !hasTp3))))
      {
         if(InpLogRejectedGeometry)
         {
            PrintFormat(
               "SIGNATICSBridge group_setup_rejected idx=%d reason=incomplete_group has_entry=%s has_sl=%s has_tp1=%s has_tp2=%s has_tp3=%s",
               useIdx,(hasEntry?"true":"false"),(hasSl?"true":"false"),(hasTp1?"true":"false"),(hasTp2?"true":"false"),(hasTp3?"true":"false")
            );
         }
         continue;
      }
      if(useEntry<=0.0 || useSl<=0.0 || useTp1<=0.0)
         continue;
      if(InpChartObjectStrictGroups)
      {
         bool timeOk=_group_slot_time_ok(useTime,slTime) && _group_slot_time_ok(useTime,tp1Time);
         if(hasTp2)
            timeOk = timeOk && _group_slot_time_ok(useTime,tp2Time);
         if(hasTp3)
            timeOk = timeOk && _group_slot_time_ok(useTime,tp3Time);
         if(!timeOk)
         {
            if(InpLogRejectedGeometry)
            {
               PrintFormat(
                  "SIGNATICSBridge group_setup_rejected idx=%d reason=time_skew entry_time=%s sl_time=%s tp1_time=%s tp2_time=%s tp3_time=%s",
                  useIdx,_fmt_time(useTime),_fmt_time(slTime),_fmt_time(tp1Time),_fmt_time(tp2Time),_fmt_time(tp3Time)
               );
            }
            continue;
         }
      }
      if(InpRejectInvalidGeometry && !_setup_geometry_ok(useDir,useEntry,useSl,useTp1,useTp2,useTp3))
      {
         if(InpLogRejectedGeometry)
         {
            PrintFormat(
               "SIGNATICSBridge group_setup_rejected idx=%d reason=invalid_geometry dir=%s time=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s",
               useIdx,useDir,_fmt_time(useTime),_fmt_price(useEntry),_fmt_price(useSl),_fmt_price(useTp1),_fmt_price(useTp2),_fmt_price(useTp3)
            );
         }
         continue;
      }
      if(validSeen<rank)
      {
         validSeen++;
         continue;
      }

      direction=useDir;
      signalTime=useTime;
      entry=useEntry;
      sl=useSl;
      tp1=useTp1;
      tp2=useTp2;
      tp3=useTp3;
      sourceName=StringFormat("SA_SL_%d_group strict=%s entry='%s' sl='%s' tp1='%s' tp2='%s' tp3='%s'",useIdx,(InpChartObjectStrictGroups?"true":"false"),entryName,slName,tp1Name,tp2Name,tp3Name);
      return true;
   }
   return false;
}

bool _find_latest_group_signal(string &direction,datetime &signalTime,double &entry,double &sl,double &tp1,double &tp2,double &tp3,string &sourceName)
{
   return _find_group_signal_by_rank(0,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
}

bool _find_latest_signatics_signal(string &direction,datetime &signalTime,double &entry,double &sl,double &tp1,double &tp2,double &tp3,string &sourceName)
{
   if(InpPreferGroupedSetup)
   {
      if(_find_latest_group_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
         return true;
      if(InpAllowLevelObjectFallback && _find_latest_level_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
         return true;
      return (InpAllowDashboardFallback && _find_latest_dashboard_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName));
   }
   if(_find_latest_dashboard_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
      return true;
   if(InpAllowLevelObjectFallback && _find_latest_level_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
      return true;
   return _find_latest_group_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
}

void _print_setup_line(string label,string reason,string direction,datetime signalTime,double entry,double sl,double tp1,double tp2,double tp3,string sourceName)
{
   PrintFormat(
      "SIGNATICSBridge %s reason=%s symbol=%s tf=%s dir=%s bar=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s source='%s'",
      label,reason,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),_fmt_price(sl),_fmt_price(tp1),_fmt_price(tp2),_fmt_price(tp3),sourceName
   );
}

void _print_previous_group_snapshot(string reason)
{
   string direction,sourceName;
   datetime signalTime;
   double entry,sl,tp1,tp2,tp3;
   if(_find_group_signal_by_rank(1,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
   {
      _print_setup_line("previous_trade",reason,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
      return;
   }
   PrintFormat("SIGNATICSBridge previous_trade NONE reason=%s symbol=%s tf=%s",reason,Symbol(),_tf_to_string(Period()));
}

void _debug_print_signatics_objects()
{
   if(!InpDebugObjects)
      return;
   int total=ObjectsTotal(0,-1,-1);
   int printed=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      string lc=_lower_copy(name+" "+_object_text(name));
      if(StringFind(lc,"sa_sl_")<0 && StringFind(lc,"sa_db_s_v")<0 && StringFind(lc,"sa_db_l_v")<0 && StringFind(lc,"sa_db_t_v")<0 && StringFind(lc,"sa_lv_")<0)
         continue;
      PrintFormat("SIGNATICSBridge object row=%03d name='%s' time=%s price=%s text='%s'",i,name,_fmt_time(_object_time0(name)),_fmt_price(_object_price0(name)),_object_text(name));
      if(++printed>=60)
         break;
   }
}

int _count_objects_contains(string pattern)
{
   string needle=_lower_copy(pattern);
   int total=ObjectsTotal(0,-1,-1);
   int count=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      string hay=_lower_copy(name+" "+_object_text(name));
      if(StringFind(hay,needle)>=0)
         count++;
   }
   return count;
}

void _print_initial_discovery_candidates()
{
   int total=ObjectsTotal(0,-1,-1);
   int printed=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      string lc=_lower_copy(name+" "+_object_text(name));
      if(StringFind(lc,"sa_sl_")<0 && StringFind(lc,"sa_lv_")<0 && StringFind(lc,"sa_db_")<0 && StringFind(lc,"entry")<0 && StringFind(lc,"tp")<0 && StringFind(lc,"sl")<0)
         continue;
      PrintFormat("SIGNATICSBridge initial_candidate row=%03d name='%s' time=%s price=%s text='%s'",i,name,_fmt_time(_object_time0(name)),_fmt_price(_object_price0(name)),_object_text(name));
      if(++printed>=12)
         break;
   }
   PrintFormat("SIGNATICSBridge initial_candidate summary printed=%d",printed);
}

void _print_probe_object(string wanted)
{
   string actual=_find_object_name(wanted);
   if(StringLen(actual)<=0)
   {
      PrintFormat("SIGNATICSBridge discovery_probe wanted='%s' actual=NONE",wanted);
      return;
   }
   PrintFormat(
      "SIGNATICSBridge discovery_probe wanted='%s' actual='%s' time=%s price=%s text='%s'",
      wanted,actual,_fmt_time(_object_time0(actual)),_fmt_price(_object_price0(actual)),_object_text(actual)
   );
}

void _print_initial_discovery_summary(string reason)
{
   if(!InpLogInitialDiscoverySummary)
      return;
   datetime nowTs=_timer_now();
   if(g_initialDiscoveryPrints>=2)
      return;
   if(g_initialDiscoveryLastPrint>0 && (nowTs-g_initialDiscoveryLastPrint)<10)
      return;
   g_initialDiscoveryLastPrint=nowTs;
   g_initialDiscoveryPrints++;

   int total=ObjectsTotal(0,-1,-1);
   PrintFormat(
      "SIGNATICSBridge initial_setup NONE build=%s reason=%s symbol=%s tf=%s objects=%d sa_sl=%d sa_lv=%d sa_db=%d entry=%d tp=%d sl=%d retry_print=%d",
      SIGNATICS_BRIDGE_BUILD,
      reason,
      Symbol(),
      _tf_to_string(Period()),
      total,
      _count_objects_contains("sa_sl_"),
      _count_objects_contains("sa_lv_"),
      _count_objects_contains("sa_db_"),
      _count_objects_contains("entry"),
      _count_objects_contains("tp"),
      _count_objects_contains("sl"),
      g_initialDiscoveryPrints
   );
   _print_probe_object("SA_Lv_Entry_Lb");
   _print_probe_object("SA_Lv_Entry_Ln");
   _print_probe_object("SA_Lv_Entry_Rb");
   _print_probe_object("SA_Lv_SL_Lb");
   _print_probe_object("SA_Lv_SL_Ln");
   _print_probe_object("SA_Lv_SL_Rb");
   _print_probe_object("SA_Lv_TP1_Lb");
   _print_probe_object("SA_Lv_TP1_Ln");
   _print_probe_object("SA_Lv_TP1_Rb");
   _print_probe_object("SA_DB_S_V0");
   _print_probe_object("SA_DB_L_V0");
   _print_probe_object("SA_DB_L_V1");
   _print_probe_object("SA_DB_T_V0");
   _print_initial_discovery_candidates();
}

void _debug_print_discovery_on_none(string reason)
{
   if(!InpDebugDiscoveryOnNone)
      return;
   datetime nowTs=_timer_now();
   int interval=MathMax(1,InpNoneDiscoveryIntervalSeconds);
   if(g_lastNoneDiscoveryTime>0 && (nowTs-g_lastNoneDiscoveryTime)<interval)
      return;
   g_lastNoneDiscoveryTime=nowTs;

   int total=ObjectsTotal(0,-1,-1);
   PrintFormat("SIGNATICSBridge discovery_on_none reason=%s symbol=%s tf=%s total_objects=%d",reason,Symbol(),_tf_to_string(Period()),total);
   _print_probe_object("SA_DB_S_V0");
   _print_probe_object("SA_DB_S_V3");
   _print_probe_object("SA_DB_L_V0");
   _print_probe_object("SA_DB_L_V1");
   _print_probe_object("SA_DB_T_V0");
   _print_probe_object("SA_DB_T_V1");
   _print_probe_object("SA_DB_T_V2");

   int printed=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      string lc=_lower_copy(name);
      if(StringFind(lc,"sa_db_")<0 && StringFind(lc,"sa_sl_")<0 && StringFind(lc,"sa_lv_")<0)
         continue;
      PrintFormat("SIGNATICSBridge discovery_candidate row=%03d name='%s' time=%s price=%s text='%s'",i,name,_fmt_time(_object_time0(name)),_fmt_price(_object_price0(name)),_object_text(name));
      if(++printed>=40)
         break;
   }
   PrintFormat("SIGNATICSBridge discovery_candidate summary printed=%d",printed);
}

bool _post_signatics_bridge_event(string eventType,string direction,datetime signalTime,double entry,double sl,double tp1,double tp2,double tp3,string sourceName,string reason,bool levelsAvailable)
{
   if(!InpEnableProTradePost)
      return true;

   string eventKind=_trim(eventType);
   if(eventKind=="resolved_state" && !InpSendResolvedStateEvents)
      return true;
   string dir=_trim(direction);
   string endpoint=_build_endpoint(InpApiBaseUrl,InpApiPath);
   string eventId=StringFormat("signatics|%s|%s|%s|%I64d|%s",Symbol(),_tf_to_string(Period()),dir,(long)signalTime,eventKind);
   string msg=StringFormat(
      "SIGNATICS %s %s %s entry=%s sl=%s tp1=%s tp2=%s tp3=%s source=%s",
      Symbol(),_tf_to_string(Period()),dir,_fmt_price(entry),_fmt_price(sl),_fmt_price(tp1),_fmt_price(tp2),_fmt_price(tp3),sourceName
   );
   string resolved=(dir=="BUY" || dir=="SELL") ? dir : "NONE";
   int signalBarAgeSec=-1;
   if(signalTime>0)
      signalBarAgeSec=(int)MathMax(0,_timer_now()-signalTime);
   bool confirmedFresh=_confirmed_bar_fresh(signalTime);
   int maxConfirmedAgeSec=_max_confirmed_bar_age_sec();
   string body=
      "{"
      "\"indicator\":\""+_json_escape(_bridge_indicator_label())+"\","
      "\"indicator_base\":\""+_json_escape(InpIndicatorName)+"\","
      "\"bridge_signal_mode\":\""+_json_escape(_bridge_signal_mode())+"\","
      "\"signal_hint\":\""+_json_escape(dir)+"\","
      "\"resolved_signal\":\""+_json_escape(resolved)+"\","
      "\"confirmed_direction\":\""+_json_escape((eventKind=="confirmed_signal")?dir:"")+"\","
      "\"bridge_version\":\"v2\","
      "\"symbol\":\""+_json_escape(Symbol())+"\","
      "\"timeframe\":\""+_json_escape(_tf_to_string(Period()))+"\","
      "\"signal_profile\":\""+_json_escape(InpSignalProfile)+"\","
      "\"bridge_event_type\":\""+_json_escape(eventKind)+"\","
      "\"event_id\":\""+_json_escape(eventId)+"\","
      "\"event_ts\":\""+_json_escape(_event_ts_now())+"\","
      "\"resolved_signal_bar_time\":\""+_json_escape(_fmt_time(signalTime))+"\","
      "\"resolved_signal_bar_unix\":"+IntegerToString((int)signalTime)+","
      "\"signal_bar_age_sec\":"+IntegerToString(signalBarAgeSec)+","
      "\"confirmed_bar_fresh\":"+(confirmedFresh ? "true" : "false")+","
      "\"max_confirmed_bar_age_sec\":"+IntegerToString(maxConfirmedAgeSec)+","
      "\"last_signal_direction\":\""+_json_escape(dir)+"\","
      "\"last_signal_bar_time\":\""+_json_escape(_fmt_time(signalTime))+"\","
      "\"last_signal_bar_unix\":"+IntegerToString((int)signalTime)+","
      "\"last_signal_value\":"+DoubleToString(entry,Digits)+","
      "\"secondary_enabled\":true,"
      "\"secondary_indicator\":\"SIGNATICSLevels\","
      "\"secondary_signal\":\""+_json_escape(dir)+"\","
      "\"secondary_resolved_signal\":\""+_json_escape(dir)+"\","
      "\"secondary_signal_shift\":-1,"
      "\"secondary_resolved_bar_time\":\""+_json_escape(_fmt_time(signalTime))+"\","
      "\"secondary_entry_enabled\":true,"
      "\"secondary_entry\":"+DoubleToString(entry,Digits)+","
      "\"secondary_sl_enabled\":"+(levelsAvailable ? "true" : "false")+","
      "\"secondary_stop_loss\":"+DoubleToString(sl,Digits)+","
      "\"secondary_tp_enabled\":"+(levelsAvailable ? "true" : "false")+","
      "\"secondary_tp1\":"+DoubleToString(tp1,Digits)+","
      "\"secondary_tp2\":"+DoubleToString(tp2,Digits)+","
      "\"secondary_tp3\":"+DoubleToString(tp3,Digits)+","
      "\"message\":\""+_json_escape(msg)+"\","
      "\"signatics_source\":\""+_json_escape(sourceName)+"\","
      "\"signatics_reason\":\""+_json_escape(reason)+"\","
      "\"bridge_token\":\""+_json_escape(InpBridgeToken)+"\""
      "}";

   char post[];
   StringToCharArray(body,post,0,StringLen(body));
   char result[];
   string responseHeaders="";
   string headers="Content-Type: application/json\r\n";
   if(StringLen(InpBridgeToken)>0)
      headers=headers+"X-MT4-Bridge-Token: "+InpBridgeToken+"\r\n";

   ResetLastError();
   int code=WebRequest("POST",endpoint,headers,MathMax(1000,InpHttpTimeoutMs),post,result,responseHeaders);
   string response=CharArrayToString(result,0,-1);
   if(code>=200 && code<300)
   {
      if(InpLogPostResponses || _should_log_handshake_response(eventKind,reason))
      {
         Print("SIGNATICSBridge handshake sent ",eventKind," ",dir," reason=",reason," response=",_compact_bridge_response(response));
      }
      else if(eventKind=="confirmed_signal")
      {
         Print("SIGNATICSBridge sent ",eventKind," ",dir);
      }
      return true;
   }
   Print("SIGNATICSBridge POST failed code=",code," err=",GetLastError()," event=",eventKind," dir=",dir," endpoint=",endpoint," response=",response);
   return false;
}

bool _is_initial_audit_reason(string reason)
{
   return (reason=="init" || reason=="init_retry" || reason=="baseline");
}

bool ScanFastBufferSignal(string reason)
{
   if(!_fast_buffers_active())
      return false;

   string direction;
   datetime signalTime;
   double entry;
   int bufferIndex,shift;
   if(!_find_latest_fast_buffer_signal(direction,signalTime,entry,bufferIndex,shift))
      return false;

   string eventId=_fast_buffer_event_id(direction,signalTime,entry,bufferIndex,shift);
   if(eventId==g_lastFastBufferEventId)
      return true;

   bool initialAudit=_is_initial_audit_reason(reason) || !g_baselineSetupSeen;
   g_lastFastBufferEventId=eventId;
   string sourceName=StringFormat("SIGNATICS_BUFFER_%d_shift_%d",bufferIndex,shift);
   if(InpLogFastBufferSignals)
   {
      PrintFormat(
         "SIGNATICSBridge fast_buffer_signal reason=%s event_id='%s' symbol=%s tf=%s dir=%s bar=%s entry=%s buffer=%d shift=%d initial=%s",
         reason,eventId,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),bufferIndex,shift,(initialAudit ? "true" : "false")
      );
   }

   if(_post_signatics_bridge_event("resolved_state",direction,signalTime,entry,0.0,0.0,0.0,0.0,sourceName,reason,false))
      g_lastResolvedPostTime=_timer_now();

   if(initialAudit && !InpSendInitialConfirmedOnStart)
      return true;

   _print_setup_line("trade_signal_sent_fast_buffer",reason,direction,signalTime,entry,0.0,0.0,0.0,0.0,sourceName);
   _post_signatics_bridge_event("confirmed_signal",direction,signalTime,entry,0.0,0.0,0.0,0.0,sourceName,reason,false);
   g_lastFastConfirmedDirection=direction;
   g_lastFastConfirmedSignalTime=signalTime;
   return true;
}

bool ScanBufferHistoryResolvedState(string reason)
{
   if(!_fast_buffers_active() || !InpSendBufferHistoryResolvedOnInit)
      return false;
   if(!_is_initial_audit_reason(reason) && g_baselineSetupSeen)
      return false;

   string direction;
   datetime signalTime;
   double entry;
   int bufferIndex,shift;
   if(!_find_latest_history_buffer_signal(direction,signalTime,entry,bufferIndex,shift))
      return false;

   string eventId=_fast_buffer_event_id(direction,signalTime,entry,bufferIndex,shift)+"|history";
   string sourceName=StringFormat("SIGNATICS_BUFFER_HISTORY_%d_shift_%d",bufferIndex,shift);
   if(InpLogFastBufferSignals)
   {
      PrintFormat(
         "SIGNATICSBridge buffer_history_resolved reason=%s event_id='%s' symbol=%s tf=%s dir=%s bar=%s entry=%s buffer=%d shift=%d history_lookback=%d",
         reason,eventId,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),bufferIndex,shift,MathMax(0,InpFastSignalHistoryLookbackBars)
      );
      _print_buffer_history_snapshot(reason);
   }

   if(_post_signatics_bridge_event("resolved_state",direction,signalTime,entry,0.0,0.0,0.0,0.0,sourceName,reason,false))
      g_lastResolvedPostTime=_timer_now();
   g_lastFastBufferEventId=eventId;
   g_baselineSetupSeen=true;
   return true;
}

bool ScanAndLogLatest(string reason)
{
   bool initialReason=_is_initial_audit_reason(reason);
   bool fastFound=ScanFastBufferSignal(reason);
   if(fastFound && initialReason && _fast_buffers_active())
   {
      _print_buffer_history_snapshot(reason);
      g_baselineSetupSeen=true;
      return true;
   }

   if(_fast_buffers_active() && (initialReason || !g_baselineSetupSeen))
   {
      bool historyFound=ScanBufferHistoryResolvedState(reason);
      if(historyFound)
         return true;
   }

   if(_fast_buffers_active() && !InpAllowObjectConfirmedFallback)
   {
      if((initialReason || !g_baselineSetupSeen) && InpLogFastBufferSignals && _buffer_history_none_log_due())
      {
         g_lastBufferHistoryNoneLogTime=_timer_now();
         PrintFormat(
            "SIGNATICSBridge buffer_history NONE reason=%s symbol=%s tf=%s live_lookback=%d history_lookback=%d object_scan=false",
            reason,Symbol(),_tf_to_string(Period()),MathMax(0,InpFastSignalLookbackBars),MathMax(0,InpFastSignalHistoryLookbackBars)
         );
      }
      return g_baselineSetupSeen;
   }

   string direction,sourceName;
   datetime signalTime;
   double entry,sl,tp1,tp2,tp3;
   if(!_find_latest_signatics_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
   {
      if(_is_initial_audit_reason(reason) || !g_baselineSetupSeen)
         _print_initial_discovery_summary(reason);
      if(_none_log_due(reason))
      {
         g_lastNoneLogTime=_timer_now();
         if(!InpLogOnlyTradeSignals)
            Print("SIGNATICSBridge latest_signal NONE reason=",reason," symbol=",Symbol()," tf=",_tf_to_string(Period()));
      }
      _debug_print_discovery_on_none(reason);
      _debug_print_signatics_objects();
      return false;
   }

   string eventId=_setup_event_id(direction,signalTime,entry,sl,tp1,tp2,tp3);
   if(InpLogOnlyOnChange && eventId==g_lastEventId)
   {
      if(_object_confirm_active() && _heartbeat_due(g_lastResolvedPostTime))
      {
         if(_post_signatics_bridge_event("resolved_state",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,"heartbeat",true))
            g_lastResolvedPostTime=_timer_now();
      }
      return true;
   }

   g_lastEventId=eventId;
   bool initialAudit = initialReason || !g_baselineSetupSeen;
   bool shouldPrintSetup = (!InpLogOnlyTradeSignals || (initialAudit && InpLogInitialSetup));
   if(shouldPrintSetup)
   {
      _print_setup_line("latest_signal",reason,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
      _print_setup_line("current_setup",reason,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
      _print_previous_group_snapshot(reason);
   }

   if(initialAudit)
   {
      if(_object_confirm_active() && _post_signatics_bridge_event("resolved_state",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason,true))
         g_lastResolvedPostTime=_timer_now();
      if(InpSendInitialConfirmedOnStart && _object_confirm_active() && _chart_object_confirm_ready(eventId,reason,signalTime))
      {
         _print_setup_line("trade_signal_sent",reason,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
         _post_signatics_bridge_event("confirmed_signal",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason,true);
         g_lastConfirmedEventId=eventId;
         g_pendingObjectEventId="";
         g_pendingObjectFirstSeen=0;
      }
      g_baselineSetupSeen=true;
   }
   else if(eventId!=g_lastConfirmedEventId)
   {
      if(_object_confirm_active() && _post_signatics_bridge_event("resolved_state",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason,true))
         g_lastResolvedPostTime=_timer_now();
      PrintFormat(
         "SIGNATICSBridge listener_new_setup reason=%s event_id='%s' symbol=%s tf=%s dir=%s bar=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s source='%s'",
         reason,eventId,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),_fmt_price(sl),_fmt_price(tp1),_fmt_price(tp2),_fmt_price(tp3),sourceName
      );
      if(_matches_last_fast_signal(direction,signalTime))
      {
         PrintFormat(
            "SIGNATICSBridge object_enrichment_only reason=%s event_id='%s' matched_fast_dir=%s fast_bar=%s object_bar=%s source='%s'",
            reason,eventId,direction,_fmt_time(g_lastFastConfirmedSignalTime),_fmt_time(signalTime),sourceName
         );
         _post_signatics_bridge_event("level_update",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason,true);
         g_lastConfirmedEventId=eventId;
         return true;
      }
      if(_fast_buffers_active() && !InpAllowObjectConfirmedFallback)
      {
         PrintFormat(
            "SIGNATICSBridge object_enrichment_skipped reason=%s event_id='%s' fast_buffer_primary=true object_bar=%s last_fast_bar=%s source='%s' why=object_does_not_match_fast_signal",
            reason,eventId,_fmt_time(signalTime),_fmt_time(g_lastFastConfirmedSignalTime),sourceName
         );
         return true;
      }
      if(_chart_object_confirm_ready(eventId,reason,signalTime))
      {
         _print_setup_line("trade_signal_sent",reason,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
         _post_signatics_bridge_event("confirmed_signal",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason,true);
         g_lastConfirmedEventId=eventId;
         g_pendingObjectEventId="";
         g_pendingObjectFirstSeen=0;
      }
   }
   return true;
}

int OnInit()
{
   int poll=MathMax(1,InpPollSeconds);
   EventSetTimer(poll);
   Print("SIGNATICSBridge BUILD=",SIGNATICS_BRIDGE_BUILD," indicator=",InpIndicatorName," instanceIndicator=",_bridge_indicator_label()," mode=",_bridge_signal_mode()," symbol=",Symbol()," tf=",_tf_to_string(Period())," poll=",poll," light=",InpLogOnlyTradeSignals," resolved=",InpSendResolvedStateEvents," groupPrimary=",InpPreferGroupedSetup," lvFallback=",InpAllowLevelObjectFallback," fastBuffers=",_fast_buffers_active()," fastLookback=",InpFastSignalLookbackBars," historyLookback=",InpFastSignalHistoryLookbackBars," tickScan=",InpScanFastBuffersOnTick," strictGroups=",InpChartObjectStrictGroups," requireAllTps=",InpChartObjectRequireAllTps," objectStableSec=",InpChartObjectStableSeconds);
   if(InpEnableProTradePost)
   {
      _post_signatics_bridge_event("register","",-1,0.0,0.0,0.0,0.0,0.0,"","init",false);
      g_lastRegisterPostTime=_timer_now();
   }
   g_initialSetupRetryUntil=_timer_now()+MathMax(0,InpInitialSetupRetrySeconds);
   if(InpLogOnInit)
      ScanAndLogLatest("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpSendUnregisterOnDeinit && InpEnableProTradePost)
      _post_signatics_bridge_event("unregister","",-1,0.0,0.0,0.0,0.0,0.0,"","deinit_"+IntegerToString(reason),false);
   if(!InpLogOnlyTradeSignals)
      Print("SIGNATICSBridge uninit reason=",reason);
}

void OnTimer()
{
   MaybePostRegisterHeartbeat("heartbeat");
   if(InpLogOnInit && !g_baselineSetupSeen && _timer_now()<=g_initialSetupRetryUntil)
   {
      ScanAndLogLatest("init_retry");
      return;
   }
   ScanAndLogLatest("timer");
}
void OnTick()
{
   if(_fast_buffers_active() && InpScanFastBuffersOnTick)
      ScanFastBufferSignal("tick");
}
