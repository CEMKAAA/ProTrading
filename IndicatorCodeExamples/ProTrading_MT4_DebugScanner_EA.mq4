//+------------------------------------------------------------------+
//| ProTrading MT4 Debug Scanner EA                                  |
//| Diagnostic only: scans chart objects and iCustom buffers.         |
//+------------------------------------------------------------------+
#property strict

input string InpIndicatorName = "";
input string InpICustomParamsCsv = "";
input int    InpSignalShift = 0;
input int    InpScanBufferMax = 32;
input int    InpScanShiftMax = 6;
input double InpSignalAbsMin = 0.0000001;
input string InpIgnoreNamePatterns = "autotrade,->";
input string InpButtonName = "BTN_SCAN_ARROWS";
input int    InpButtonX = 20;
input int    InpButtonY = 50;
input bool   InpLogAllObjects = true;

double g_params[];
int g_paramCount = 0;

string _trim(string s){ StringTrimLeft(s); StringTrimRight(s); return s; }
bool _is_signal_value(double v){ return MathIsValidNumber(v) && v != EMPTY_VALUE && MathAbs(v) >= InpSignalAbsMin; }
bool _contains_ci(string h,string n){ StringToLower(h); StringToLower(n); return StringLen(n)>0 && StringFind(h,n)>=0; }
bool _csv_name_hit(string csv,string name){ string raw=_trim(csv); StringReplace(raw,";",","); StringReplace(raw,"|",","); string parts[]; int n=StringSplit(raw,44,parts); for(int i=0;i<n;i++){ string t=_trim(parts[i]); if(StringLen(t)>0 && _contains_ci(name,t)) return true; } return false; }
string _color_hex(color c){ int r=((int)c)&0xFF,g=(((int)c)>>8)&0xFF,b=(((int)c)>>16)&0xFF; return StringFormat("#%02X%02X%02X",r,g,b); }

bool _parse_params(){ ArrayResize(g_params,0); g_paramCount=0; string raw=_trim(InpICustomParamsCsv); if(StringLen(raw)==0) return true; StringReplace(raw,";",","); StringReplace(raw,"|",","); string toks[]; int n=StringSplit(raw,44,toks); for(int i=0;i<n;i++){ string t=_trim(toks[i]); if(StringLen(t)<=0) continue; ArrayResize(g_params,g_paramCount+1); g_params[g_paramCount++]=StrToDouble(t); } return true; }
double _buffer_value(int b,int sh){ int c=g_paramCount; if(c<=0) return iCustom(NULL,0,InpIndicatorName,b,sh); if(c==1) return iCustom(NULL,0,InpIndicatorName,g_params[0],b,sh); if(c==2) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],b,sh); if(c==3) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],b,sh); if(c==4) return iCustom(NULL,0,InpIndicatorName,g_params[0],g_params[1],g_params[2],g_params[3],b,sh); return iCustom(NULL,0,InpIndicatorName,b,sh); }

void CreateButton(){ ObjectDelete(0,InpButtonName); ObjectCreate(0,InpButtonName,OBJ_BUTTON,0,0,0); ObjectSetInteger(0,InpButtonName,OBJPROP_CORNER,CORNER_RIGHT_UPPER); ObjectSetInteger(0,InpButtonName,OBJPROP_XDISTANCE,InpButtonX); ObjectSetInteger(0,InpButtonName,OBJPROP_YDISTANCE,InpButtonY); ObjectSetInteger(0,InpButtonName,OBJPROP_XSIZE,160); ObjectSetInteger(0,InpButtonName,OBJPROP_YSIZE,30); ObjectSetString(0,InpButtonName,OBJPROP_TEXT,"SCAN ARROWS"); ObjectSetInteger(0,InpButtonName,OBJPROP_COLOR,clrWhite); ObjectSetInteger(0,InpButtonName,OBJPROP_BGCOLOR,C'30,90,180'); ObjectSetInteger(0,InpButtonName,OBJPROP_HIDDEN,true); ChartRedraw(0); }
void RunScan(){ int total=ObjectsTotal(0,-1,-1); Print("------------------------------------------------------------"); Print("DebugScanner MT4 | chart=",Symbol()," objects=",total," indicator=",InpIndicatorName); int printed=0,ignored=0; for(int i=total-1;i>=0;i--){ string name=ObjectName(0,i,-1,-1); if(name==InpButtonName) continue; if(_csv_name_hit(InpIgnoreNamePatterns,name)){ ignored++; continue; } int type=(int)ObjectGetInteger(0,name,OBJPROP_TYPE); if(!InpLogAllObjects && type!=OBJ_ARROW) continue; datetime t=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME); double p=ObjectGetDouble(0,name,OBJPROP_PRICE); long code=ObjectGetInteger(0,name,OBJPROP_ARROWCODE); color c=(color)ObjectGetInteger(0,name,OBJPROP_COLOR); PrintFormat("OBJ row=%03d type=%d name='%s' time=%s price=%s code=%d color=%s",i,type,name,(t>0?TimeToString(t,TIME_DATE|TIME_SECONDS):"-"),DoubleToString(p,Digits),(int)code,_color_hex(c)); if(++printed>=120) break; } Print("OBJ summary printed=",printed," ignored_name=",ignored); int maxB=MathMax(1,MathMin(128,InpScanBufferMax)); int maxS=MathMax(1,MathMin(100,InpScanShiftMax)); for(int b=0;b<maxB;b++){ string row=""; bool active=false; for(int sh=0;sh<maxS;sh++){ double v=_buffer_value(b,sh); bool a=_is_signal_value(v); if(a) active=true; row+=StringFormat(" sh%d=%s%s",sh,DoubleToString(v,Digits),(a?"*":"")); } if(active) Print("BUFFER[",b,"]",row); } Print("------------------------------------------------------------"); }
int OnInit(){ _parse_params(); CreateButton(); Print("MT4 DebugScanner loaded. Press SCAN ARROWS."); return INIT_SUCCEEDED; }
void OnDeinit(const int reason){ ObjectDelete(0,InpButtonName); }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam){ if(id==CHARTEVENT_OBJECT_CLICK && sparam==InpButtonName){ ObjectSetInteger(0,InpButtonName,OBJPROP_STATE,false); RunScan(); } }
void OnTick(){}
