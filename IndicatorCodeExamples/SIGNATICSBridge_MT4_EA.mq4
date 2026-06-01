//+------------------------------------------------------------------+
//| SIGNATICS Bridge MT4 EA                                          |
//| Reads SIGNATICS-ALGO V2 chart objects and posts V2 bridge events.|
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "SIGNATICS-ALGO V2 (2)";
input int    InpPollSeconds = 1;
input bool   InpLogOnInit = true;
input bool   InpLogOnlyOnChange = true;
input bool   InpDebugObjects = false;
input bool   InpDebugDiscoveryOnNone = true;
input int    InpNoneDiscoveryIntervalSeconds = 10;
input int    InpNoneLogIntervalSeconds = 10;
input string InpIgnoreNamePatterns = "autotrade,->";
input bool   InpEnableProTradePost = true;
input bool   InpSendInitialConfirmedOnStart = false;
input int    InpResolvedHeartbeatSeconds = 60;
input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "signatics";
input int    InpHttpTimeoutMs = 5000;

string   g_lastEventId = "";
string   g_lastConfirmedEventId = "";
datetime g_lastResolvedPostTime = 0;
datetime g_lastNoneDiscoveryTime = 0;
datetime g_lastNoneLogTime = 0;

string _trim(string s){ StringTrimLeft(s); StringTrimRight(s); return s; }

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

double _price_from_object_or_text(string name)
{
   string actual=_find_object_name(name);
   if(StringLen(actual)<=0)
      return 0.0;
   double p=_object_price0(actual);
   double txt=_parse_first_price_from_text(_object_text(actual));
   if(_valid_price(txt))
      return txt;
   return p;
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
   if(signalTime<=0)
      signalTime=_timer_now();
   sourceName="SA_DB";

   return entry>0.0 && sl>0.0 && tp1>0.0;
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
   int bestIdx=-1;
   int secondIdx=-1;
   datetime bestTime=0;
   datetime secondTime=0;
   string bestDir="";
   string secondDir="";
   double bestEntry=0.0;
   double secondEntry=0.0;
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

      if(t>bestTime)
      {
         secondIdx=bestIdx;
         secondTime=bestTime;
         secondDir=bestDir;
         secondEntry=bestEntry;
         bestIdx=idx;
         bestTime=t;
         bestDir=dir;
         bestEntry=e;
      }
      else if(t>secondTime && idx!=bestIdx)
      {
         secondIdx=idx;
         secondTime=t;
         secondDir=dir;
         secondEntry=e;
      }
   }

   int useIdx=bestIdx;
   datetime useTime=bestTime;
   string useDir=bestDir;
   double useEntry=bestEntry;
   if(rank>0)
   {
      useIdx=secondIdx;
      useTime=secondTime;
      useDir=secondDir;
      useEntry=secondEntry;
   }

   if(useIdx<0 || useTime<=0 || useDir=="")
      return false;

   string base=StringFormat("SA_SL_%d_",useIdx);
   direction=useDir;
   signalTime=useTime;
   entry=useEntry;
   sl=_price_from_object_or_text(base+"1");
   tp1=_price_from_object_or_text(base+"2");
   tp2=_price_from_object_or_text(base+"3");
   tp3=_price_from_object_or_text(base+"4");
   sourceName=base+"group";
   return entry>0.0 && sl>0.0 && tp1>0.0;
}

bool _find_latest_group_signal(string &direction,datetime &signalTime,double &entry,double &sl,double &tp1,double &tp2,double &tp3,string &sourceName)
{
   return _find_group_signal_by_rank(0,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
}

bool _find_latest_signatics_signal(string &direction,datetime &signalTime,double &entry,double &sl,double &tp1,double &tp2,double &tp3,string &sourceName)
{
   if(_find_latest_dashboard_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
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

bool _post_signatics_bridge_event(string eventType,string direction,datetime signalTime,double entry,double sl,double tp1,double tp2,double tp3,string sourceName,string reason)
{
   if(!InpEnableProTradePost)
      return true;

   string eventKind=_trim(eventType);
   string dir=_trim(direction);
   string endpoint=_build_endpoint(InpApiBaseUrl,InpApiPath);
   string eventId=StringFormat("signatics|%s|%s|%s|%I64d|%s",Symbol(),_tf_to_string(Period()),dir,(long)signalTime,eventKind);
   string msg=StringFormat(
      "SIGNATICS %s %s %s entry=%s sl=%s tp1=%s tp2=%s tp3=%s source=%s",
      Symbol(),_tf_to_string(Period()),dir,_fmt_price(entry),_fmt_price(sl),_fmt_price(tp1),_fmt_price(tp2),_fmt_price(tp3),sourceName
   );
   string resolved=(dir=="BUY" || dir=="SELL") ? dir : "NONE";
   string body=
      "{"
      "\"indicator\":\""+_json_escape(InpIndicatorName)+"\","
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
      "\"secondary_sl_enabled\":true,"
      "\"secondary_stop_loss\":"+DoubleToString(sl,Digits)+","
      "\"secondary_tp_enabled\":true,"
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
      Print("SIGNATICSBridge sent ",eventKind," ",dir," response=",response);
      return true;
   }
   Print("SIGNATICSBridge POST failed code=",code," err=",GetLastError()," event=",eventKind," dir=",dir," endpoint=",endpoint," response=",response);
   return false;
}

void ScanAndLogLatest(string reason)
{
   string direction,sourceName;
   datetime signalTime;
   double entry,sl,tp1,tp2,tp3;
   if(!_find_latest_signatics_signal(direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName))
   {
      if(_none_log_due(reason))
      {
         g_lastNoneLogTime=_timer_now();
         Print("SIGNATICSBridge latest_signal NONE reason=",reason," symbol=",Symbol()," tf=",_tf_to_string(Period()));
      }
      _debug_print_discovery_on_none(reason);
      _debug_print_signatics_objects();
      return;
   }

   string eventId=StringFormat("%s|%s|%I64d|%s",Symbol(),direction,(long)signalTime,sourceName);
   if(InpLogOnlyOnChange && eventId==g_lastEventId)
   {
      if(_heartbeat_due(g_lastResolvedPostTime))
      {
         if(_post_signatics_bridge_event("resolved_state",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,"heartbeat"))
            g_lastResolvedPostTime=_timer_now();
      }
      return;
   }

   g_lastEventId=eventId;
   _print_setup_line("latest_signal",reason,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
   _print_setup_line("current_setup",reason,direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName);
   _print_previous_group_snapshot(reason);

   if(reason=="init")
   {
      if(_post_signatics_bridge_event("resolved_state",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason))
         g_lastResolvedPostTime=_timer_now();
      if(InpSendInitialConfirmedOnStart)
      {
         _post_signatics_bridge_event("confirmed_signal",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason);
         g_lastConfirmedEventId=eventId;
      }
   }
   else if(eventId!=g_lastConfirmedEventId)
   {
      if(_post_signatics_bridge_event("resolved_state",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason))
         g_lastResolvedPostTime=_timer_now();
      _post_signatics_bridge_event("confirmed_signal",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason);
      g_lastConfirmedEventId=eventId;
   }
}

int OnInit()
{
   int poll=MathMax(1,InpPollSeconds);
   EventSetTimer(poll);
   Print("SIGNATICSBridge initialized indicator=",InpIndicatorName," symbol=",Symbol()," tf=",_tf_to_string(Period())," poll=",poll);
   if(InpEnableProTradePost)
      _post_signatics_bridge_event("register","",-1,0.0,0.0,0.0,0.0,0.0,"","init");
   if(InpLogOnInit)
      ScanAndLogLatest("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("SIGNATICSBridge uninit reason=",reason);
}

void OnTimer(){ ScanAndLogLatest("timer"); }
void OnTick(){}
