//+------------------------------------------------------------------+
//| Atomic Bridge MT5 EA                                             |
//| MT5 port of AtomicBridge_MT4_EA: Atomic object scan,              |
//| AtomicRegime buffer scan, direct execution, dashboard, audit.     |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

#define ATOMIC_BRIDGE_MT5_BUILD "2026-06-26.0100-mt5-port"

input string InpIndicatorName = "Atomic";
input int    InpPollSeconds = 1;
input bool   InpLogOnInit = true;
input bool   InpLogOnlyOnChange = true;
input bool   InpDebugObjects = false;
input bool   InpLogPostResponses = false;
input bool   InpLogHandshakeResponses = true;
input bool   InpLogNoneSignals = false;
input bool   InpLogRegimeBuffer = false;
input bool   InpShowDashboard = true;
input bool   InpEnableAtomicMode = true;
input bool   InpEnableAtomicRegimeMode = true;
input int    InpInitialSetupRetrySeconds = 30;
input string InpIgnoreNamePatterns = "autotrade,->";
input bool   InpEnableProTradePost = false;
input bool   InpSendUnregisterOnDeinit = true;
input bool   InpSendInitialConfirmedOnStart = false;
input int    InpResolvedHeartbeatSeconds = 300;
input int    InpRegisterHeartbeatSeconds = 900;
input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt5/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "atomic";
input int    InpHttpTimeoutMs = 5000;
input bool   InpDirectMt5ExecutionEnabled = true;
input string InpDirectMt5Priority = "post_first";
input double InpDirectMt5Lot = 0.10;
input bool   InpDirectMt5AutoLotEnabled = true;
input int    InpDirectMt5AutoLotDailyAtrPeriod = 14;
input double InpDirectMt5AutoLotMax = 0.00;
input bool   InpAdvancedAccountRiskEnabled = true;
input double InpAccountRiskPerTradePct = 1.00;
input double InpAccountRiskDailyAtrExposurePct = 2.00;
input double InpAccountRiskMaxPortfolioPct = 4.00;
input double InpAccountRiskDailyLossLimitPct = 0.00;
input double InpAccountRiskMaxDrawdownPct = 0.00;
input double InpAccountRiskMaxMarginUsagePct = 40.00;
input double InpAccountRiskInitialBalanceOverride = 0.00;
input int    InpAccountRiskDayResetHourGmt = 0;
input bool   InpAccountRiskLiquidateOnBreach = true;
input double InpAccountRiskSafetyBufferPct = 95.00;
input bool   InpAccountRiskBlockUnprotectedPositions = true;
input bool   InpAccountRiskFailClosed = true;
input bool   InpAccountRiskAuditEnabled = true;
input int    InpAccountRiskAuditIntervalSeconds = 60;
input long   InpDirectMt5Magic = 970101;
input int    InpDirectMt5Slippage = 30;
input int    InpDirectMt5MaxSpreadPoints = 0;
input string InpDirectMt5AllowedTradeWindowsGmt = "";
input string InpDirectMt5NoTradeWindowsGmt = "21:55-22:10";
input bool   InpDirectMt5CloseReverse = true;
input int    InpDirectMt5TpIndex = 5;
input bool   InpAtomicDirectRiskGeometryEnabled = false;
input double InpAtomicDirectTargetR = 2.0;
input double InpDirectMt5HalfBeR = 2.0;
input int    InpDirectMt5HalfBeTpIndex = 2;
input double InpRegimeDirectMt5HalfBeR = 0.0;
input bool   InpDirectMt5AuditCsv = true;
input int    InpDirectMt5PositionProbeIntervalSeconds = 30;
input bool   InpRegimeSignalProbeAudit = true;
input int    InpRegimeSignalProbeIntervalSeconds = 30;
input bool   InpRegimeSignalProbeWriteOnChange = true;
input int    InpRegimeSignalProbeMaxShift = 20;
input bool   InpShowAtomicRegimeTradeLevels = true;
input int    InpAtomicRegimeTradeLevelLabelBars = 8;
input bool   InpEnableRegimeChangePost = true;
input bool   InpSendInitialRegimeConfirmedOnStart = false;
input string InpRegimeSignalProfile = "atomic_regime";
input string InpRegimeIndicatorName = "AtomicRegime";
input int    InpRegimeAtrPeriod = 14;
input double InpRegimeAtrMultiplier = 3.0;
input double InpRegimeRR = 2.0;
input double InpRegimeMinRiskPricePct = 0.00100;
input double InpRegimeMaxRiskPricePct = 0.00300;
input double InpRegimeMaxRiskMoneyPerLot = 0.0;
input double InpRegimeMinRiskPoints = 0.0;
input bool   InpRegimeClampSlToAtomicSignalSl = true;
input bool   InpRegimeSlWidenEnabled = true;
input double InpRegimeSlWidenPct = 25.0;
input double InpRegimeFinalRiskScalePct = 75.0;
input bool   InpRegimeUseTrendSignalBuffers = true;
input int    InpRegimeUpTrendSignalBuffer = 2;
input int    InpRegimeDnTrendSignalBuffer = 3;
input bool   InpRegimeUseTrendStopBuffers = false;
input int    InpRegimeUpTrendStopBuffer = 0;
input int    InpRegimeDnTrendStopBuffer = 1;
input bool   InpRegimeUseAtomicSignalAsTieBreak = true;
input bool   InpRegimeUseClosedBar = true;
input int    InpRegimeBufferLookbackBars = 200;
input bool   InpRegimeDelayValidationMode = false;
input int    InpRegimeConfirmDelaySeconds = 300;
input int    InpRegimeConfirmStableSeconds = 5;
input int    InpRegimeMaxConfirmShift = 1;
input bool   InpRegimeOpenPreWindowSignal = false;

CTrade trade;

string DASH_PREFIX = "ATOMIC_BRIDGE_MT5_DASH_";
string LEVEL_PREFIX = "ATOMIC_BRIDGE_MT5_LEVEL_";
int g_indicatorHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;

string g_lastEventId = "";
string g_lastRegimeEventId = "";
string g_lastRegimeConfirmedEventId = "";
string g_lastObservedSignalDirection = "";
string g_lastRegimeObservedSignalDirection = "";
datetime g_lastObservedSignalTime = 0;
datetime g_lastRegimeObservedSignalTime = 0;
double g_lastObservedSignalValue = 0.0;
double g_lastRegimeObservedSignalValue = 0.0;
string g_pendingRegimeEventId = "";
datetime g_pendingRegimeFirstSeen = 0;
string g_pendingRegimeWindowEventId = "";
string g_pendingRegimeWindowDirection = "";
datetime g_pendingRegimeWindowSignalTime = 0;
double g_pendingRegimeWindowSl = 0.0;
double g_pendingRegimeWindowTp = 0.0;

bool g_proTradePostEnabledRuntime = true;
bool g_directMt5EnabledRuntime = false;
bool g_directMt5PriorityDirectFirst = true;
bool g_atomicModeEnabledRuntime = true;
bool g_atomicRegimeModeEnabledRuntime = true;
double g_directMt5LotRuntime = 0.0;
int g_directMt5MaxSpreadRuntime = 0;
int g_directMt5TpIndexRuntime = 5;
bool g_atomicDirectRiskGeometryRuntime = false;
double g_atomicDirectTargetRRuntime = 2.0;
double g_directMt5HalfBeRRuntime = 0.0;
int g_directMt5HalfBeTpIndexRuntime = 2;
double g_regimeDirectMt5HalfBeRRuntime = 0.0;
double g_regimeRRRuntime = 0.0;
double g_regimeFinalRiskScalePctRuntime = 100.0;
bool g_regimeUseClosedBarRuntime = true;
bool g_regimeDelayValidationRuntime = false;
int g_regimeConfirmDelaySecondsRuntime = 300;
bool g_regimeOpenPreWindowSignalRuntime = false;
string g_directMt5AllowedWindowsRuntime = "";
string g_directMt5NoTradeWindowsRuntime = "";
bool g_ftmoModeRuntime = false;
bool g_riskLotOnlyRuntime = false;
bool g_auditEnabledRuntime = true;
bool g_dashboardCollapsed = false;
datetime g_lastPositionProbe = 0;
datetime g_lastRegimeProbe = 0;
string g_lastRegimeProbeHash = "";
datetime g_lastRiskAuditAt = 0;

struct AtomicSignal
{
   bool ok;
   string direction;
   int index;
   datetime time;
   double entry;
   double sl;
   double tp1;
   double tp2;
   double tp3;
   double tp4;
   double tp5;
   string trendName;
   string eventId;
};

string Trim(string s){ StringTrimLeft(s); StringTrimRight(s); return s; }
string Lower(string s){ StringToLower(s); return s; }
bool ContainsCi(string h,string n){ return StringLen(n)>0 && StringFind(Lower(h),Lower(n))>=0; }
datetime Now(){ datetime t=TimeCurrent(); return t>0?t:TimeLocal(); }
string FmtTime(datetime t){ return t>0?TimeToString(t,TIME_DATE|TIME_SECONDS):"-"; }
string DateKey(datetime t){ MqlDateTime st; TimeToStruct(t,st); return StringFormat("%04d%02d%02d",st.year,st.mon,st.day); }
string TfString(){ return EnumToString((ENUM_TIMEFRAMES)_Period); }
string DirName(int d){ return d>0?"BUY":(d<0?"SELL":""); }
int DirInt(string d){ d=Trim(d); if(d=="BUY") return 1; if(d=="SELL") return -1; return 0; }
double PointValue(){ double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT); return p>0?p:_Point; }
double NormPrice(double p){ return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)); }
string FmtPrice(double p){ return p>0.0 && MathIsValidNumber(p)?DoubleToString(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)):"0"; }
bool ValidPrice(double v){ return MathIsValidNumber(v) && v!=EMPTY_VALUE && v!=2147483647.0 && v>0.0; }
bool AccountRiskRuntime(){ return g_ftmoModeRuntime || g_riskLotOnlyRuntime; }
double EffDailyLimitPct(){ return g_ftmoModeRuntime ? (InpAccountRiskDailyLossLimitPct>0.0?InpAccountRiskDailyLossLimitPct:5.0) : 0.0; }
double EffMaxDdPct(){ return g_ftmoModeRuntime ? (InpAccountRiskMaxDrawdownPct>0.0?InpAccountRiskMaxDrawdownPct:10.0) : 0.0; }
bool AuditEnabled(){ return g_auditEnabledRuntime; }
long NormalMagic(){ return InpDirectMt5Magic*1000000 + (long)(ChartID()%1000000); }
long FtmoMagic(){ long m=InpDirectMt5Magic; if(m<0)m=-m; return 4000000000000000000 + (m%1000000000000)*1000000 + (long)(ChartID()%1000000); }
long RuntimeMagic(){ return AccountRiskRuntime()?FtmoMagic():NormalMagic(); }
bool MagicScoped(long magic){ return magic==NormalMagic() || magic==FtmoMagic(); }

bool CsvNameHit(string csv,string name)
{
   string parts[];
   int n=StringSplit(csv,',',parts);
   for(int i=0;i<n;i++) if(ContainsCi(name,Trim(parts[i]))) return true;
   return false;
}

string JsonEscape(string s)
{
   StringReplace(s,"\\","\\\\");
   StringReplace(s,"\"","\\\"");
   StringReplace(s,"\r\n","\\n");
   StringReplace(s,"\n","\\n");
   StringReplace(s,"\r","\\n");
   return s;
}

string Endpoint()
{
   string b=Trim(InpApiBaseUrl);
   if(b=="") b="http://127.0.0.1";
   if(StringSubstr(b,0,7)!="http://" && StringSubstr(b,0,8)!="https://") b="http://"+b;
   while(StringLen(b)>0 && StringSubstr(b,StringLen(b)-1,1)=="/") b=StringSubstr(b,0,StringLen(b)-1);
   string p=Trim(InpApiPath);
   if(p=="") p="/api/v1/mt5/bridge/signal";
   if(StringSubstr(p,0,1)!="/") p="/"+p;
   return b+p;
}

bool ParseAtomicObjectName(string name,string &direction,string &kind,int &tpIndex,int &signalIndex)
{
   direction=""; kind=""; tpIndex=-1; signalIndex=-1;
   string clean=Trim(name), cur="";
   int nums[], count=0; ArrayResize(nums,0);
   for(int i=0;i<StringLen(clean);i++)
   {
      ushort ch=StringGetCharacter(clean,i);
      if(ch>='0' && ch<='9') cur+=StringSubstr(clean,i,1);
      else if(StringLen(cur)>0)
      {
         ArrayResize(nums,count+1);
         nums[count++]=(int)StringToInteger(cur);
         cur="";
      }
   }
   if(StringLen(cur)>0)
   {
      ArrayResize(nums,count+1);
      nums[count++]=(int)StringToInteger(cur);
   }
   if(count<=0) return false;
   string lc=Lower(clean);
   if(StringFind(lc,"buytrend")>=0 || StringFind(lc,"selltrend")>=0)
   {
      direction=(StringFind(lc,"buytrend")>=0?"BUY":"SELL");
      kind="TREND";
      signalIndex=nums[count-1];
      return signalIndex>=0;
   }
   if(StringFind(lc,"buytxtsloss")>=0 || StringFind(lc,"selltxtsloss")>=0)
   {
      direction=(StringFind(lc,"buytxtsloss")>=0?"BUY":"SELL");
      kind="SL";
      signalIndex=nums[count-1];
      return signalIndex>=0;
   }
   if(StringFind(lc,"buytxttp")>=0 || StringFind(lc,"selltxttp")>=0)
   {
      if(count<2) return false;
      direction=(StringFind(lc,"buytxttp")>=0?"BUY":"SELL");
      kind="TP";
      tpIndex=nums[count-2];
      signalIndex=nums[count-1];
      return tpIndex>=0 && signalIndex>=0;
   }
   return false;
}

double ObjPrice(string name)
{
   if(ObjectFind(0,name)<0) return 0.0;
   double p=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
   if(ValidPrice(p)) return p;
   p=ObjectGetDouble(0,name,OBJPROP_PRICE);
   return ValidPrice(p)?p:0.0;
}

datetime ObjTime(string name)
{
   if(ObjectFind(0,name)<0) return 0;
   datetime t=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
   if(t>0) return t;
   return (datetime)ObjectGetInteger(0,name,OBJPROP_TIME);
}

bool FindLatestAtomicSignal(AtomicSignal &s,bool logOnNone=true)
{
   s.ok=false; s.direction=""; s.index=-1; s.time=0; s.entry=0; s.sl=0; s.tp1=0; s.tp2=0; s.tp3=0; s.tp4=0; s.tp5=0; s.trendName=""; s.eventId="";
   int total=ObjectsTotal(0,-1,-1), parsed=0, trends=0, levels=0, atomicLike=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(CsvNameHit(InpIgnoreNamePatterns,name)) continue;
      string lc=Lower(name);
      if(StringFind(lc,"buy")>=0 || StringFind(lc,"sell")>=0 || StringFind(lc,"atomic")>=0 || StringFind(lc,"buffer=")>=0) atomicLike++;
      string dir,kind; int tpIdx,sigIdx;
      if(!ParseAtomicObjectName(name,dir,kind,tpIdx,sigIdx)) continue;
      parsed++;
      if(kind!="TREND"){ levels++; continue; }
      trends++;
      datetime t=ObjTime(name);
      double p=ObjPrice(name);
      if(t<=0 || p<=0.0) continue;
      if(t>s.time)
      {
         s.direction=dir;
         s.index=sigIdx;
         s.time=t;
         s.entry=p;
         s.trendName=name;
      }
   }
   if(s.time<=0)
   {
      for(int j=total-1;j>=0;j--)
      {
         string name=ObjectName(0,j,-1,-1);
         if(CsvNameHit(InpIgnoreNamePatterns,name)) continue;
         string dir,kind; int tpIdx,sigIdx;
         if(!ParseAtomicObjectName(name,dir,kind,tpIdx,sigIdx)) continue;
         if(kind!="SL" && kind!="TP") continue;
         datetime t=ObjTime(name);
         double p=ObjPrice(name);
         if(t<=0 || p<=0.0) continue;
         if(t>s.time)
         {
            s.direction=dir;
            s.index=sigIdx;
            s.time=t;
            s.entry=p;
            s.trendName=name+" [fallback-level-object]";
         }
      }
   }
   if(s.time<=0 || s.index<0 || s.direction=="")
   {
      if(InpDebugObjects || (logOnNone && InpLogNoneSignals))
         PrintFormat("AtomicBridgeMT5 scan_stats total=%d atomic_like=%d parsed=%d trends=%d levels=%d selected_time=%s",total,atomicLike,parsed,trends,levels,FmtTime(s.time));
      return false;
   }
   for(int k=total-1;k>=0;k--)
   {
      string name=ObjectName(0,k,-1,-1);
      if(CsvNameHit(InpIgnoreNamePatterns,name)) continue;
      string dir,kind; int tpIdx,sigIdx;
      if(!ParseAtomicObjectName(name,dir,kind,tpIdx,sigIdx)) continue;
      if(dir!=s.direction || sigIdx!=s.index) continue;
      double p=ObjPrice(name);
      if(p<=0.0) continue;
      if(kind=="SL") s.sl=p;
      else if(kind=="TP")
      {
         if(tpIdx==0) s.tp1=p;
         else if(tpIdx==1) s.tp2=p;
         else if(tpIdx==2) s.tp3=p;
         else if(tpIdx==3) s.tp4=p;
         else if(tpIdx==4) s.tp5=p;
      }
   }
   s.ok=true;
   s.eventId=StringFormat("atomic|%s|%s|%s|%d|%I64d|confirmed_signal",_Symbol,TfString(),s.direction,s.index,(long)s.time);
   return true;
}

double TpByIndex(const AtomicSignal &s,int idx)
{
   idx=MathMax(1,MathMin(5,idx));
   if(idx==1) return s.tp1;
   if(idx==2) return s.tp2;
   if(idx==3) return s.tp3;
   if(idx==4) return s.tp4;
   return s.tp5;
}

double FinalTp(const AtomicSignal &s)
{
   double t=TpByIndex(s,g_directMt5TpIndexRuntime);
   if(t>0) return t;
   if(s.tp5>0) return s.tp5;
   if(s.tp4>0) return s.tp4;
   if(s.tp3>0) return s.tp3;
   if(s.tp2>0) return s.tp2;
   return s.tp1;
}

double StopMinDistance()
{
   double p=PointValue();
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(2.0*p,MathMax((double)stops,(double)freeze)*p);
}

bool AtomicRGeometrySl(string dir,double entry,double tp,double targetR,double &sl,string &detail)
{
   detail="indicator_sl";
   if(dir!="BUY" && dir!="SELL") return false;
   if(entry<=0 || tp<=0 || targetR<=0) return false;
   double reward=(dir=="BUY") ? (tp-entry) : (entry-tp);
   if(reward<=StopMinDistance()){ detail="reward_too_small"; return false; }
   double risk=reward/MathMax(0.1,targetR);
   double minRisk=StopMinDistance();
   if(risk<minRisk)
   {
      risk=minRisk;
      detail="r_geometry_widened_to_broker_min achieved_r="+DoubleToString(reward/risk,2);
   }
   else detail="r_geometry target_r="+DoubleToString(targetR,2);
   sl=NormPrice(dir=="BUY"?entry-risk:entry+risk);
   return sl>0;
}

int CurrentSpreadPoints()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return 0;
   double p=PointValue();
   return p>0?(int)MathRound((tick.ask-tick.bid)/p):0;
}

bool ParseHHMM(string v,int &minutes)
{
   v=Trim(v);
   int c=StringFind(v,":");
   if(c<0) return false;
   int h=(int)StringToInteger(StringSubstr(v,0,c));
   int m=(int)StringToInteger(StringSubstr(v,c+1));
   if(h<0 || h>23 || m<0 || m>59) return false;
   minutes=h*60+m;
   return true;
}

bool TimeInWindow(datetime gmt,string range)
{
   range=Trim(range);
   int d=StringFind(range,"-");
   if(d<0) return false;
   int a,b;
   if(!ParseHHMM(StringSubstr(range,0,d),a) || !ParseHHMM(StringSubstr(range,d+1),b)) return false;
   MqlDateTime st;
   TimeToStruct(gmt,st);
   int now=st.hour*60+st.min;
   if(a<=b) return now>=a && now<=b;
   return now>=a || now<=b;
}

bool InAnyWindow(string csv)
{
   csv=Trim(csv);
   if(csv=="") return false;
   string parts[];
   int n=StringSplit(csv,',',parts);
   for(int i=0;i<n;i++) if(TimeInWindow(TimeGMT(),parts[i])) return true;
   return false;
}

bool TradeWindowAllowed(string &reason)
{
   if(g_directMt5AllowedWindowsRuntime!="" && !InAnyWindow(g_directMt5AllowedWindowsRuntime))
   {
      reason="outside_allowed_window_gmt="+g_directMt5AllowedWindowsRuntime;
      return false;
   }
   if(g_directMt5NoTradeWindowsRuntime!="" && InAnyWindow(g_directMt5NoTradeWindowsRuntime))
   {
      reason="inside_no_trade_window_gmt="+g_directMt5NoTradeWindowsRuntime;
      return false;
   }
   reason="ok";
   return true;
}

string AuditFile(){ return "AtomicBridge_MT5_DirectAudit_"+DateKey(TimeGMT())+".csv"; }
string RiskAuditFile(){ return "AtomicBridge_MT5_AccountRiskAudit_"+DateKey(TimeGMT())+".csv"; }
string RegimeProbeFile(){ return "AtomicBridge_MT5_RegimeSignalProbe_"+DateKey(TimeGMT())+".csv"; }

void Audit(string eventName,string source,string eventId,ulong ticket,string direction,double lot,double price,double sl,double tp,string reason,double pnl,string detail)
{
   if(!AuditEnabled() || !InpDirectMt5AuditCsv) return;
   int h=FileOpen(AuditFile(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)
   {
      Print("AtomicBridgeMT5 audit open failed err=",GetLastError());
      return;
   }
   if(FileSize(h)==0)
      FileWrite(h,"server_time","gmt_time","local_time","event","build","platform","account","source","symbol","tf","event_id","ticket","direction","lot","price","sl","tp","bid","ask","spread_pts","reason","pnl","detail");
   FileSeek(h,0,SEEK_END);
   MqlTick tick;
   SymbolInfoTick(_Symbol,tick);
   FileWrite(h,
      FmtTime(TimeCurrent()),FmtTime(TimeGMT()),FmtTime(TimeLocal()),
      eventName,ATOMIC_BRIDGE_MT5_BUILD,"MT5",(string)AccountInfoInteger(ACCOUNT_LOGIN),source,_Symbol,TfString(),
      eventId,(string)ticket,direction,DoubleToString(lot,4),FmtPrice(price),FmtPrice(sl),FmtPrice(tp),
      FmtPrice(tick.bid),FmtPrice(tick.ask),IntegerToString(CurrentSpreadPoints()),reason,DoubleToString(pnl,2),detail);
   FileClose(h);
}

string StateKey(string kind,ulong ticket){ return "AtomicBridgeMT5|"+_Symbol+"|"+(string)RuntimeMagic()+"|"+kind+"|"+(string)ticket; }
void StateSet(string kind,ulong ticket,double v){ GlobalVariableSet(StateKey(kind,ticket),v); }
double StateGet(string kind,ulong ticket){ string k=StateKey(kind,ticket); return GlobalVariableCheck(k)?GlobalVariableGet(k):0.0; }
bool StateDone(string kind,ulong ticket){ return StateGet(kind,ticket)>0.5; }

bool IsOwnedPosition(ulong ticket)
{
   if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   return MagicScoped((long)PositionGetInteger(POSITION_MAGIC));
}


double VolumeStep()
{
   double s=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   return s>0?s:0.01;
}

double NormalizeVolume(double vol,bool halfSplit)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=VolumeStep();
   if(minLot<=0) minLot=step;
   if(maxLot<=0) maxLot=100.0;
   if(InpDirectMt5AutoLotMax>0) maxLot=MathMin(maxLot,InpDirectMt5AutoLotMax);
   vol=MathMax(minLot,MathMin(maxLot,vol));
   vol=MathFloor(vol/step+0.0000001)*step;
   if(halfSplit && vol>=minLot*2.0)
   {
      double half=MathFloor((vol*0.5)/step+0.0000001)*step;
      if(half<minLot) vol=minLot;
   }
   return NormalizeDouble(MathMax(minLot,vol),4);
}

double MoneyPerLot(double entry,double sl)
{
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(ts<=0) ts=PointValue();
   if(ts<=0 || tv<=0) return 0.0;
   return MathAbs(entry-sl)/ts*tv;
}

double D1Atr(int period)
{
   MqlRates rates[];
   int p=MathMax(2,period);
   int copied=CopyRates(_Symbol,PERIOD_D1,1,p+2,rates);
   if(copied<p+1) return 0.0;
   ArraySetAsSeries(rates,true);
   double sum=0.0;
   int used=0;
   for(int i=0;i<copied-1 && used<p;i++)
   {
      double prev=rates[i+1].close;
      double tr=MathMax(rates[i].high-rates[i].low,MathMax(MathAbs(rates[i].high-prev),MathAbs(rates[i].low-prev)));
      if(tr>0){ sum+=tr; used++; }
   }
   return used>0?sum/used:0.0;
}

datetime GmtDayStart()
{
   datetime g=TimeGMT();
   MqlDateTime st;
   TimeToStruct(g,st);
   int h=MathMax(0,MathMin(23,InpAccountRiskDayResetHourGmt));
   st.hour=h; st.min=0; st.sec=0;
   datetime start=StructToTime(st);
   if(g<start) start-=86400;
   return start;
}

double RiskCapital()
{
   return InpAccountRiskInitialBalanceOverride>0?InpAccountRiskInitialBalanceOverride:MathMax(1.0,AccountInfoDouble(ACCOUNT_EQUITY));
}

void ScopePnl(double &closedAll,double &closedToday,double &floating,int &positions,int &unprotected)
{
   closedAll=0; closedToday=0; floating=0; positions=0; unprotected=0;
   datetime dayStart=GmtDayStart();
   HistorySelect(TimeCurrent()-86400*365,TimeCurrent());
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      if(!MagicScoped((long)HistoryDealGetInteger(deal,DEAL_MAGIC))) continue;
      double pnl=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
      closedAll+=pnl;
      if((datetime)HistoryDealGetInteger(deal,DEAL_TIME)>=dayStart) closedToday+=pnl;
   }
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(!IsOwnedPosition(ticket)) continue;
      positions++;
      floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(PositionGetDouble(POSITION_SL)<=0) unprotected++;
   }
}

double OpenRiskMoney()
{
   double risk=0.0;
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(!IsOwnedPosition(ticket)) continue;
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(sl>0) risk+=MoneyPerLot(open,sl)*vol;
   }
   return risk;
}

bool AccountRiskBreached(string &reason)
{
   if(!AccountRiskRuntime()) return false;
   double ca,ct,fl;
   int pos,unp;
   ScopePnl(ca,ct,fl,pos,unp);
   double cap=RiskCapital();
   double safety=MathMax(1.0,MathMin(100.0,InpAccountRiskSafetyBufferPct))/100.0;
   double dailyPct=MathMax(0.0,-(ct+fl))/cap*100.0;
   double ddPct=MathMax(0.0,-(ca+fl))/cap*100.0;
   double marginPct=AccountInfoDouble(ACCOUNT_EQUITY)>0?AccountInfoDouble(ACCOUNT_MARGIN)/AccountInfoDouble(ACCOUNT_EQUITY)*100.0:0.0;
   if(InpAccountRiskBlockUnprotectedPositions && unp>0){ reason="unprotected_position_count="+(string)unp; return true; }
   if(EffDailyLimitPct()>0 && dailyPct>=EffDailyLimitPct()*safety){ reason="daily_loss_limit daily_pct="+DoubleToString(dailyPct,3); return true; }
   if(EffMaxDdPct()>0 && ddPct>=EffMaxDdPct()*safety){ reason="max_drawdown_limit total_pct="+DoubleToString(ddPct,3); return true; }
   if(InpAccountRiskMaxMarginUsagePct>0 && marginPct>=InpAccountRiskMaxMarginUsagePct){ reason="margin_limit margin_pct="+DoubleToString(marginPct,3); return true; }
   reason="ok";
   return false;
}

void RiskAudit(string eventName,string detail)
{
   if(!AuditEnabled() || !AccountRiskRuntime() || !InpAccountRiskAuditEnabled) return;
   datetime now=TimeCurrent();
   if(eventName=="heartbeat" && g_lastRiskAuditAt>0 && now-g_lastRiskAuditAt<MathMax(15,InpAccountRiskAuditIntervalSeconds)) return;
   g_lastRiskAuditAt=now;
   double ca,ct,fl;
   int pos,unp;
   ScopePnl(ca,ct,fl,pos,unp);
   double cap=RiskCapital();
   int h=FileOpen(RiskAuditFile(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
      FileWrite(h,"server_time","gmt_time","event","build","symbol","tf","risk_capital","trade_budget","portfolio_budget","open_risk","closed_all","closed_today","floating","positions","unprotected","daily_limit_pct","max_dd_pct","detail");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,FmtTime(TimeCurrent()),FmtTime(TimeGMT()),eventName,ATOMIC_BRIDGE_MT5_BUILD,_Symbol,TfString(),DoubleToString(cap,2),DoubleToString(cap*InpAccountRiskPerTradePct/100.0,2),DoubleToString(cap*InpAccountRiskMaxPortfolioPct/100.0,2),DoubleToString(OpenRiskMoney(),2),DoubleToString(ca,2),DoubleToString(ct,2),DoubleToString(fl,2),IntegerToString(pos),IntegerToString(unp),DoubleToString(EffDailyLimitPct(),2),DoubleToString(EffMaxDdPct(),2),detail);
   FileClose(h);
}

double ResolveLot(double entry,double sl,bool halfSplit,string &detail)
{
   double fixed=NormalizeVolume(g_directMt5LotRuntime,halfSplit);
   if(!InpDirectMt5AutoLotEnabled && !AccountRiskRuntime()){ detail="fixed_lot"; return fixed; }
   string breach;
   if(AccountRiskBreached(breach)){ detail="blocked_by_account_risk "+breach; return InpAccountRiskFailClosed?0.0:fixed; }
   double mpl=MoneyPerLot(entry,sl);
   if(mpl<=0){ detail="money_per_lot_unavailable"; return InpAccountRiskFailClosed?0.0:fixed; }
   double cap=RiskCapital();
   double tradeBudget=cap*MathMax(0.0,InpAccountRiskPerTradePct)/100.0;
   double portfolioBudget=cap*MathMax(0.0,InpAccountRiskMaxPortfolioPct)/100.0;
   double remaining=MathMax(0.0,portfolioBudget-OpenRiskMoney());
   double atr=D1Atr(InpDirectMt5AutoLotDailyAtrPeriod);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0) ts=PointValue();
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double atrMoney=(atr>0 && ts>0 && tv>0)?atr/ts*tv:0.0;
   double atrBudget=cap*MathMax(0.0,InpAccountRiskDailyAtrExposurePct)/100.0;
   double raw=MathMin(tradeBudget/mpl,MathMin(remaining>0?remaining/mpl:0.0,(atrMoney>0 && atrBudget>0)?atrBudget/atrMoney:tradeBudget/mpl));
   double vol=NormalizeVolume(raw,halfSplit);
   double margin=0.0;
   bool marginOk=OrderCalcMargin(entry>sl?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,vol,entry,margin);
   if(!marginOk)
   {
      detail="margin_calc_failed err="+(string)GetLastError();
      return InpAccountRiskFailClosed?0.0:fixed;
   }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double projected=equity>0?(AccountInfoDouble(ACCOUNT_MARGIN)+margin)/equity*100.0:0.0;
   if(InpAccountRiskMaxMarginUsagePct>0 && projected>InpAccountRiskMaxMarginUsagePct)
   {
      detail="blocked_projected_margin projected="+DoubleToString(projected,2);
      return InpAccountRiskFailClosed?0.0:fixed;
   }
   detail="advanced_lot raw="+DoubleToString(raw,4)+" vol="+DoubleToString(vol,4)+" money_per_lot="+DoubleToString(mpl,2)+" trade_budget="+DoubleToString(tradeBudget,2)+" portfolio_remaining="+DoubleToString(remaining,2)+" atr_budget="+DoubleToString(atrBudget,2)+" projected_margin_pct="+DoubleToString(projected,2);
   RiskAudit("lot_selected",detail);
   return vol;
}


void CloseReversePositions(string direction,string eventId)
{
   if(!InpDirectMt5CloseReverse) return;
   int dir=DirInt(direction);
   if(dir==0) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOwnedPosition(ticket)) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int pd=type==POSITION_TYPE_BUY?1:-1;
      if(pd==dir) continue;
      double vol=PositionGetDouble(POSITION_VOLUME);
      string comment=PositionGetString(POSITION_COMMENT);
      bool ok=trade.PositionClose(ticket);
      Audit(ok?"direct_reverse_closed":"direct_reverse_close_failed",comment,eventId,ticket,DirName(pd),vol,0,0,0,ok?"reverse_signal":"retcode="+(string)trade.ResultRetcode(),0.0,trade.ResultComment());
   }
}

bool EffectiveHalfEnabled(string source)
{
   bool isRegime=ContainsCi(source,"AtomicRegime");
   double r=isRegime?g_regimeDirectMt5HalfBeRRuntime:g_directMt5HalfBeRRuntime;
   if(r<=0.0) return false;
   if(!isRegime && g_directMt5HalfBeTpIndexRuntime>=g_directMt5TpIndexRuntime) return false;
   return true;
}

double TriggerPrice(string direction,double entry,double sl,double tp,double stored,double halfR)
{
   if(stored>0)
   {
      if(direction=="BUY" && stored>entry) return stored;
      if(direction=="SELL" && stored<entry) return stored;
   }
   double risk=MathAbs(entry-sl);
   if(risk<=PointValue() || halfR<=0) return 0.0;
   return direction=="BUY"?entry+risk*halfR:entry-risk*halfR;
}

void ManagePositions()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(!IsOwnedPosition(ticket)) continue;
      string comment=PositionGetString(POSITION_COMMENT);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int dir=type==POSITION_TYPE_BUY?1:-1;
      string d=DirName(dir);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double vol=PositionGetDouble(POSITION_VOLUME);
      if(sl<=0 || tp<=0) continue;
      if(!EffectiveHalfEnabled(comment)) continue;
      double halfR=ContainsCi(comment,"AtomicRegime")?g_regimeDirectMt5HalfBeRRuntime:g_directMt5HalfBeRRuntime;
      double trigger=TriggerPrice(d,entry,sl,tp,StateGet("HTP",ticket),halfR);
      if(trigger<=0) continue;
      bool touched=dir>0?tick.bid>=trigger:tick.ask<=trigger;
      if(!touched) continue;
      if(!StateDone("SEEN",ticket)) StateSet("SEEN",ticket,(double)TimeCurrent());
      if(!StateDone("BE",ticket))
      {
         double be=NormPrice(entry);
         bool shouldMove=dir>0?(sl<be):(sl>be || sl<=0);
         if(shouldMove)
         {
            bool ok=trade.PositionModify(ticket,be,tp);
            Audit(ok?"direct_sl_to_be_sent":"direct_sl_to_be_failed",comment,"",ticket,d,vol,entry,be,tp,"trigger="+FmtPrice(trigger),0.0,"retcode="+(string)trade.ResultRetcode()+" "+trade.ResultComment());
            if(!ok) continue;
            StateSet("BE",ticket,1.0);
         }
         else StateSet("BE",ticket,1.0);
      }
      if(!StateDone("HALF",ticket))
      {
         double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
         double closeVol=NormalizeVolume(vol*0.5,false);
         if(closeVol>=minLot && vol-closeVol>=minLot)
         {
            bool ok=trade.PositionClosePartial(ticket,closeVol,InpDirectMt5Slippage);
            Audit(ok?"direct_half_close_sent":"direct_half_close_failed",comment,"",ticket,d,closeVol,entry,sl,tp,"trigger="+FmtPrice(trigger),0.0,"retcode="+(string)trade.ResultRetcode()+" "+trade.ResultComment());
            if(ok) StateSet("HALF",ticket,1.0);
         }
         else
         {
            StateSet("HALF",ticket,1.0);
            Audit("direct_half_close_skipped_min_lot",comment,"",ticket,d,vol,entry,sl,tp,"min_lot",0.0,"");
         }
      }
   }
}

void PositionProbe()
{
   if(!AuditEnabled()) return;
   if(g_lastPositionProbe>0 && TimeCurrent()-g_lastPositionProbe<MathMax(1,InpDirectMt5PositionProbeIntervalSeconds)) return;
   g_lastPositionProbe=TimeCurrent();
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(!IsOwnedPosition(ticket)) continue;
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      string comment=PositionGetString(POSITION_COMMENT);
      Audit("position_probe",comment,"",ticket,DirName(dir),PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),"heartbeat",PositionGetDouble(POSITION_PROFIT),"half="+(StateDone("HALF",ticket)?"1":"0")+" be="+(StateDone("BE",ticket)?"1":"0"));
   }
}

bool DirectExecute(string eventId,string direction,double sl,double tp,string source,double halfTrigger,string halfLabel,datetime signalTime)
{
   string dir=Trim(direction);
   if(dir!="BUY" && dir!="SELL") return false;
   if(!g_directMt5EnabledRuntime)
   {
      Audit("direct_skipped",source,eventId,0,dir,0,0,sl,tp,"direct_disabled",0,"");
      return false;
   }
   string reason;
   if(!TradeWindowAllowed(reason))
   {
      Audit("direct_blocked_window",source,eventId,0,dir,0,0,sl,tp,reason,0,"");
      return false;
   }
   int spread=CurrentSpreadPoints();
   if(g_directMt5MaxSpreadRuntime>0 && spread>g_directMt5MaxSpreadRuntime)
   {
      Audit("direct_blocked_spread",source,eventId,0,dir,0,0,sl,tp,"spread="+(string)spread+" max="+(string)g_directMt5MaxSpreadRuntime,0,"");
      return false;
   }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      Audit("direct_blocked_tick",source,eventId,0,dir,0,0,sl,tp,"no_tick",0,"");
      return false;
   }
   double entry=dir=="BUY"?tick.ask:tick.bid;
   double actualSl=sl;
   double actualTp=tp;
   string geom="";
   if(ContainsCi(source,InpIndicatorName) && g_atomicDirectRiskGeometryRuntime)
      AtomicRGeometrySl(dir,entry,tp,g_atomicDirectTargetRRuntime,actualSl,geom);
   bool halfEnabled=EffectiveHalfEnabled(source);
   string lotDetail;
   double lot=ResolveLot(entry,actualSl,halfEnabled,lotDetail);
   if(lot<=0)
   {
      Audit("direct_blocked_lot",source,eventId,0,dir,lot,entry,actualSl,actualTp,lotDetail,0,geom);
      return false;
   }
   CloseReversePositions(dir,eventId);
   trade.SetExpertMagicNumber(RuntimeMagic());
   trade.SetDeviationInPoints(InpDirectMt5Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   string comment="AtomicBridgeMT5|"+source;
   bool ok=false;
   ResetLastError();
   if(dir=="BUY") ok=trade.Buy(lot,_Symbol,0.0,NormPrice(actualSl),NormPrice(actualTp),comment);
   else ok=trade.Sell(lot,_Symbol,0.0,NormPrice(actualSl),NormPrice(actualTp),comment);
   ulong ticket=trade.ResultOrder();
   if(ticket==0) ticket=trade.ResultDeal();
   if(ok)
   {
      Sleep(100);
      ulong posTicket=0;
      for(int p=PositionsTotal()-1;p>=0;p--)
      {
         ulong t=PositionGetTicket(p);
         if(!IsOwnedPosition(t)) continue;
         if(PositionGetString(POSITION_COMMENT)==comment){ posTicket=t; break; }
      }
      if(posTicket==0) posTicket=ticket;
      StateSet("IRISK",posTicket,MathAbs(entry-actualSl));
      if(halfTrigger>0) StateSet("HTP",posTicket,halfTrigger);
      StateSet("SIGTIME",posTicket,(double)signalTime);
      Audit("direct_order_sent",source,eventId,posTicket,dir,lot,entry,actualSl,actualTp,"sent",0,lotDetail+" "+geom+" half="+halfLabel);
      Print("AtomicBridgeMT5 direct order_sent ticket=",posTicket," dir=",dir," lot=",DoubleToString(lot,2)," price=",FmtPrice(entry)," sl=",FmtPrice(actualSl)," tp=",FmtPrice(actualTp)," event=",eventId);
      return true;
   }
   Audit("direct_order_failed",source,eventId,ticket,dir,lot,entry,actualSl,actualTp,"retcode="+(string)trade.ResultRetcode()+" err="+(string)GetLastError(),0,trade.ResultComment()+" "+lotDetail+" "+geom);
   Print("AtomicBridgeMT5 direct order_failed retcode=",trade.ResultRetcode()," err=",GetLastError()," ",trade.ResultComment());
   return false;
}


string RuntimeTelemetryJson()
{
   MqlTick tick;
   SymbolInfoTick(_Symbol,tick);
   double point=PointValue();
   return "\"mt5_server_time\":\""+JsonEscape(FmtTime(TimeCurrent()))+"\","+
          "\"mt5_server_unix\":"+(string)((long)TimeCurrent())+","+
          "\"mt5_gmt_time\":\""+JsonEscape(FmtTime(TimeGMT()))+"\","+
          "\"mt5_gmt_unix\":"+(string)((long)TimeGMT())+","+
          "\"mt5_local_time\":\""+JsonEscape(FmtTime(TimeLocal()))+"\","+
          "\"mt5_bid\":"+DoubleToString(tick.bid,_Digits)+","+
          "\"mt5_ask\":"+DoubleToString(tick.ask,_Digits)+","+
          "\"mt5_point\":"+DoubleToString(point,_Digits+2)+","+
          "\"mt5_spread_points\":"+(string)CurrentSpreadPoints()+","+
          "\"atomic_tp_index\":"+(string)g_directMt5TpIndexRuntime+","+
          "\"atomic_sl_geometry_enabled\":"+(g_atomicDirectRiskGeometryRuntime?"true":"false")+","+
          "\"atomic_target_r\":"+DoubleToString(g_atomicDirectTargetRRuntime,2)+","+
          "\"atomic_halfbe_tp_index\":"+(string)g_directMt5HalfBeTpIndexRuntime+","+
          "\"regime_halfbe_r\":"+DoubleToString(g_regimeDirectMt5HalfBeRRuntime,2)+",";
}

bool SendPost(string eventKind,string dir,string indicator,string profile,string eventId,datetime signalTime,double entry,double sl,double tp,string message,string reason)
{
   if(!g_proTradePostEnabledRuntime) return true;
   string body="{"+
      "\"indicator\":\""+JsonEscape(indicator)+"\","+
      "\"signal_hint\":\""+JsonEscape(dir)+"\","+
      "\"resolved_signal\":\""+JsonEscape((dir=="BUY"||dir=="SELL")?dir:"NONE")+"\","+
      "\"confirmed_direction\":\""+JsonEscape(eventKind=="confirmed_signal"?dir:"")+"\","+
      "\"bridge_version\":\"v2\","+
      "\"symbol\":\""+JsonEscape(_Symbol)+"\","+
      "\"timeframe\":\""+JsonEscape(TfString())+"\","+
      "\"signal_profile\":\""+JsonEscape(profile)+"\","+
      "\"bridge_event_type\":\""+JsonEscape(eventKind)+"\","+
      "\"event_id\":\""+JsonEscape(eventId)+"\","+
      "\"event_ts\":\""+JsonEscape(FmtTime(Now()))+"\","+
      RuntimeTelemetryJson()+
      "\"resolved_signal_bar_time\":\""+JsonEscape(FmtTime(signalTime))+"\","+
      "\"resolved_signal_bar_unix\":"+(string)((long)signalTime)+","+
      "\"secondary_enabled\":true,"+
      "\"secondary_indicator\":\"AtomicLevels\","+
      "\"secondary_signal\":\""+JsonEscape(dir)+"\","+
      "\"secondary_entry_enabled\":true,"+
      "\"secondary_entry\":"+DoubleToString(entry,_Digits)+","+
      "\"secondary_sl_enabled\":true,"+
      "\"secondary_stop_loss\":"+DoubleToString(sl,_Digits)+","+
      "\"secondary_tp_enabled\":true,"+
      "\"secondary_tp1\":"+DoubleToString(tp,_Digits)+","+
      "\"message\":\""+JsonEscape(message)+"\","+
      "\"atomic_reason\":\""+JsonEscape(reason)+"\","+
      "\"bridge_token\":\""+JsonEscape(InpBridgeToken)+"\"}";
   char post[];
   StringToCharArray(body,post,0,StringLen(body));
   char result[];
   string responseHeaders="";
   string headers="Content-Type: application/json\r\n";
   if(InpBridgeToken!="") headers+="X-MT5-Bridge-Token: "+InpBridgeToken+"\r\n";
   ResetLastError();
   int code=WebRequest("POST",Endpoint(),headers,MathMax(1000,InpHttpTimeoutMs),post,result,responseHeaders);
   string response=CharArrayToString(result,0,-1);
   if(code>=200 && code<300)
   {
      if(InpLogPostResponses || InpLogHandshakeResponses) Print("AtomicBridgeMT5 POST sent ",eventKind," ",dir," reason=",reason," response=",response);
      return true;
   }
   Print("AtomicBridgeMT5 POST failed code=",code," err=",GetLastError()," event=",eventKind," dir=",dir," endpoint=",Endpoint()," response=",response);
   return false;
}

bool PostAtomicEvent(string eventKind,const AtomicSignal &s,string reason)
{
   string eventId=StringFormat("atomic|%s|%s|%s|%d|%I64d|%s",_Symbol,TfString(),s.direction,s.index,(long)s.time,eventKind);
   double directTp=FinalTp(s);
   double execSl=s.sl;
   string detail="";
   if(g_atomicDirectRiskGeometryRuntime) AtomicRGeometrySl(s.direction,s.entry,directTp,g_atomicDirectTargetRRuntime,execSl,detail);
   int halfIdx=MathMax(1,MathMin(5,g_directMt5HalfBeTpIndexRuntime));
   bool halfEnabled=halfIdx<g_directMt5TpIndexRuntime;
   double halfTrigger=halfEnabled?TpByIndex(s,halfIdx):0.0;
   string halfLabel=halfEnabled?("tp"+(string)halfIdx):"disabled_at_or_after_final_tp";
   bool directFirst=(eventKind=="confirmed_signal" && g_directMt5PriorityDirectFirst);
   if(directFirst) DirectExecute(eventId,s.direction,execSl,directTp,InpIndicatorName,halfTrigger,halfLabel,s.time);
   bool posted=SendPost(eventKind,s.direction,InpIndicatorName,InpSignalProfile,eventId,s.time,s.entry,execSl,directTp,"Atomic "+_Symbol+" "+TfString()+" "+s.direction,reason);
   if(eventKind=="confirmed_signal" && !directFirst) DirectExecute(eventId,s.direction,execSl,directTp,InpIndicatorName,halfTrigger,halfLabel,s.time);
   return posted;
}

bool EnsureIndicatorHandle()
{
   if(g_indicatorHandle!=INVALID_HANDLE) return true;
   ResetLastError();
   g_indicatorHandle=iCustom(_Symbol,(ENUM_TIMEFRAMES)_Period,InpIndicatorName);
   if(g_indicatorHandle==INVALID_HANDLE)
   {
      if(InpLogRegimeBuffer) Print("AtomicBridgeMT5 iCustom handle failed indicator=",InpIndicatorName," err=",GetLastError());
      return false;
   }
   return true;
}

double BufferValue(int buffer,int shift)
{
   if(!EnsureIndicatorHandle()) return EMPTY_VALUE;
   double v[];
   ArraySetAsSeries(v,true);
   int copied=CopyBuffer(g_indicatorHandle,MathMax(0,buffer),shift,1,v);
   if(copied<=0) return EMPTY_VALUE;
   return v[0];
}

bool ValidAtomicBufferPrice(double v)
{
   if(!ValidPrice(v)) return false;
   MqlTick tick;
   SymbolInfoTick(_Symbol,tick);
   double ref=tick.bid>0?tick.bid:iClose(_Symbol,(ENUM_TIMEFRAMES)_Period,0);
   if(ref<=0) return true;
   return v>ref*0.20 && v<ref*5.00;
}

int RegimeBaseShift(){ return g_regimeUseClosedBarRuntime?1:0; }

bool FindLatestBuffer(int buffer,int startShift,int maxShift,int &foundShift,datetime &foundTime,double &foundValue)
{
   foundShift=-1; foundTime=0; foundValue=0;
   for(int sh=startShift;sh<=maxShift;sh++)
   {
      double v=BufferValue(buffer,sh);
      if(!ValidAtomicBufferPrice(v)) continue;
      foundShift=sh;
      foundTime=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,sh);
      foundValue=v;
      return foundTime>0;
   }
   return false;
}

bool FindRegimeSignal(string directionHint,string &direction,int &signalIndex,datetime &signalTime,double &entryPrice,string &sourceName)
{
   direction=""; signalIndex=-1; signalTime=0; entryPrice=0; sourceName="";
   if(!InpRegimeUseTrendSignalBuffers) return false;
   int shift=RegimeBaseShift();
   int bars=Bars(_Symbol,(ENUM_TIMEFRAMES)_Period);
   if(bars<=shift) return false;
   int maxLookback=MathMax(shift,MathMin(bars-1,MathMax(shift,InpRegimeBufferLookbackBars)));
   int upShift,dnShift;
   datetime upTime,dnTime;
   double upVal,dnVal;
   bool hasUp=FindLatestBuffer(InpRegimeUpTrendSignalBuffer,shift,maxLookback,upShift,upTime,upVal);
   bool hasDn=FindLatestBuffer(InpRegimeDnTrendSignalBuffer,shift,maxLookback,dnShift,dnTime,dnVal);
   if(!hasUp && !hasDn) return false;
   string state="";
   int selectedShift=-1;
   datetime selectedTime=0;
   double selectedValue=0;
   if(hasUp && (!hasDn || upShift<dnShift)){ state="BUY"; selectedShift=upShift; selectedTime=upTime; selectedValue=upVal; }
   else if(hasDn && (!hasUp || dnShift<upShift)){ state="SELL"; selectedShift=dnShift; selectedTime=dnTime; selectedValue=dnVal; }
   else if(hasUp && hasDn)
   {
      string hint=Trim(directionHint);
      if(InpRegimeUseAtomicSignalAsTieBreak && (hint=="BUY"||hint=="SELL")) state=hint;
      else state=(upVal>=dnVal?"BUY":"SELL");
      selectedShift=upShift;
      selectedTime=upTime;
      selectedValue=(state=="BUY"?upVal:dnVal);
   }
   if(state!="BUY" && state!="SELL") return false;
   signalIndex=selectedShift;
   signalTime=selectedTime;
   MqlTick tick;
   SymbolInfoTick(_Symbol,tick);
   entryPrice=(shift==0?(state=="BUY"?tick.ask:tick.bid):iClose(_Symbol,(ENUM_TIMEFRAMES)_Period,selectedShift));
   if(entryPrice<=0) entryPrice=(state=="BUY"?tick.ask:tick.bid);
   entryPrice=NormPrice(entryPrice);
   direction=state;
   sourceName=StringFormat("AtomicRegimeSignalBuffer up=%d dn=%d selected_shift=%d up_shift=%d dn_shift=%d up=%s dn=%s selected=%s",InpRegimeUpTrendSignalBuffer,InpRegimeDnTrendSignalBuffer,selectedShift,upShift,dnShift,FmtPrice(upVal),FmtPrice(dnVal),FmtPrice(selectedValue));
   return entryPrice>0 && signalTime>0;
}


double RegimeAtr(datetime signalTime)
{
   if(g_atrHandle==INVALID_HANDLE) g_atrHandle=iATR(_Symbol,(ENUM_TIMEFRAMES)_Period,MathMax(1,InpRegimeAtrPeriod));
   int shift=iBarShift(_Symbol,(ENUM_TIMEFRAMES)_Period,signalTime,true);
   if(shift<0) shift=0;
   if(g_atrHandle!=INVALID_HANDLE)
   {
      double v[];
      ArraySetAsSeries(v,true);
      if(CopyBuffer(g_atrHandle,0,shift,1,v)>0 && ValidPrice(v[0])) return v[0];
   }
   double h=iHigh(_Symbol,(ENUM_TIMEFRAMES)_Period,shift);
   double l=iLow(_Symbol,(ENUM_TIMEFRAMES)_Period,shift);
   if(h>l) return h-l;
   return MathMax(PointValue()*20.0,StopMinDistance());
}

double ValuePerPriceUnitPerLot()
{
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(ts<=0) ts=PointValue();
   if(ts<=0 || tv<=0) return 0.0;
   return tv/ts;
}

void ComputeRegimeLevels(string direction,datetime signalTime,double entryPrice,double &sl,double &tp)
{
   sl=0; tp=0;
   if(entryPrice<=0) return;
   double atr=RegimeAtr(signalTime);
   double minStop=MathMax(PointValue()*20.0,StopMinDistance()*1.5);
   double atrRisk=atr*MathMax(0.1,InpRegimeAtrMultiplier);
   double pctRisk=entryPrice*MathMax(0.0,InpRegimeMinRiskPricePct);
   double pctCap=entryPrice*MathMax(0.0,InpRegimeMaxRiskPricePct);
   double moneyCap=0.0;
   double vpu=ValuePerPriceUnitPerLot();
   if(InpRegimeMaxRiskMoneyPerLot>0 && vpu>0) moneyCap=InpRegimeMaxRiskMoneyPerLot/vpu;
   double absRisk=ValidPrice(InpRegimeMinRiskPoints)?InpRegimeMinRiskPoints:0.0;
   double risk=MathMax(MathMax(atrRisk,pctRisk),MathMax(minStop,absRisk));
   double floor=MathMax(minStop,absRisk);
   double cap=0.0;
   if(pctCap>floor) cap=pctCap;
   if(moneyCap>floor) cap=cap>0?MathMin(cap,moneyCap):moneyCap;
   if(cap>floor && risk>cap) risk=cap;
   if(risk<floor) risk=floor;
   double rr=MathMax(0.1,g_regimeRRRuntime);
   if(direction=="BUY")
   {
      sl=NormPrice(entryPrice-risk);
      tp=NormPrice(entryPrice+risk*rr);
   }
   else if(direction=="SELL")
   {
      sl=NormPrice(entryPrice+risk);
      tp=NormPrice(entryPrice-risk*rr);
   }
}

bool RegimeClampToAtomic(string direction,double entry,double atomicEntry,double atomicSl,double &sl,double &tp,string &detail)
{
   detail="";
   if(!InpRegimeClampSlToAtomicSignalSl) return false;
   if(direction!="BUY"&&direction!="SELL") return false;
   if(entry<=0||atomicEntry<=0||atomicSl<=0||sl<=0||tp<=0) return false;
   double ar=MathAbs(atomicEntry-atomicSl);
   double rrisk=MathAbs(entry-sl);
   if(ar<=PointValue() || rrisk+PointValue()>=ar) return false;
   double rr=MathMax(0.1,g_regimeRRRuntime);
   sl=NormPrice(direction=="BUY"?entry-ar:entry+ar);
   tp=NormPrice(direction=="BUY"?entry+ar*rr:entry-ar*rr);
   detail="atomic_companion_min_risk";
   return true;
}

void RegimeApplyWidenScale(string direction,double entry,double &sl,double &tp,string &detail)
{
   if(direction!="BUY"&&direction!="SELL") return;
   double risk=MathAbs(entry-sl);
   if(risk<=PointValue()) return;
   double rr=MathMax(0.1,g_regimeRRRuntime);
   if(InpRegimeSlWidenEnabled && InpRegimeSlWidenPct>0)
   {
      risk*=1.0+MathMax(0.0,MathMin(200.0,InpRegimeSlWidenPct))/100.0;
      detail+="|widen="+DoubleToString(InpRegimeSlWidenPct,1);
   }
   double pct=MathMax(10.0,MathMin(200.0,g_regimeFinalRiskScalePctRuntime));
   if(MathAbs(pct-100.0)>0.001)
   {
      risk=MathMax(StopMinDistance(),risk*pct/100.0);
      detail+="|scale="+DoubleToString(pct,1);
   }
   sl=NormPrice(direction=="BUY"?entry-risk:entry+risk);
   tp=NormPrice(direction=="BUY"?entry+risk*rr:entry-risk*rr);
}

string RegimeEventId(string dir,datetime t){ return StringFormat("atomic_regime|%s|%s|%s|%I64d",_Symbol,TfString(),dir,(long)t); }

bool PostRegimeEvent(string eventKind,string direction,int signalIndex,datetime signalTime,double entry,double sl,double tp,string source,string reason)
{
   string eventId=StringFormat("atomic_regime|%s|%s|%s|%d|%I64d|%s",_Symbol,TfString(),direction,signalIndex,(long)signalTime,eventKind);
   bool directFirst=(eventKind=="confirmed_signal" && g_directMt5PriorityDirectFirst);
   if(directFirst) DirectExecute(eventId,direction,sl,tp,InpRegimeIndicatorName,0.0,"r"+DoubleToString(g_regimeDirectMt5HalfBeRRuntime,1),signalTime);
   bool posted=SendPost(eventKind,direction,InpRegimeIndicatorName,InpRegimeSignalProfile,eventId,signalTime,entry,sl,tp,"AtomicRegime "+_Symbol+" "+TfString()+" "+direction,reason+" "+source);
   if(eventKind=="confirmed_signal" && !directFirst) DirectExecute(eventId,direction,sl,tp,InpRegimeIndicatorName,0.0,"r"+DoubleToString(g_regimeDirectMt5HalfBeRRuntime,1),signalTime);
   return posted;
}

void HandleRegime(string reason,string direction,int signalIndex,datetime signalTime,double entry,string source,string atomicDirection,double atomicEntry,double atomicSl)
{
   if(!InpEnableRegimeChangePost || direction=="") return;
   double sl,tp;
   ComputeRegimeLevels(direction,signalTime,entry,sl,tp);
   if(sl<=0||tp<=0)
   {
      Print("AtomicBridgeMT5 regime invalid SL/TP");
      return;
   }
   string detail="";
   if(direction==atomicDirection)
   {
      string c;
      if(RegimeClampToAtomic(direction,entry,atomicEntry,atomicSl,sl,tp,c)) detail+="|"+c;
   }
   RegimeApplyWidenScale(direction,entry,sl,tp,detail);
   string rid=RegimeEventId(direction,signalTime);
   bool changed=(rid!=g_lastRegimeEventId);
   if(reason=="init" || reason=="init_retry")
   {
      g_lastRegimeEventId=rid;
      PostRegimeEvent("resolved_state",direction,signalIndex,signalTime,entry,sl,tp,source,reason+detail);
      if(reason=="init" && InpSendInitialRegimeConfirmedOnStart)
      {
         PostRegimeEvent("confirmed_signal",direction,signalIndex,signalTime,entry,sl,tp,source,reason+detail);
         g_lastRegimeConfirmedEventId=rid;
      }
      return;
   }
   if(!changed) return;
   int delay=MathMax(0,g_regimeConfirmDelaySecondsRuntime>=0?g_regimeConfirmDelaySecondsRuntime:InpRegimeConfirmStableSeconds);
   bool tooStale=(InpRegimeMaxConfirmShift>=0 && signalIndex>InpRegimeMaxConfirmShift);
   if(g_regimeDelayValidationRuntime && signalIndex==0 && delay>0)
   {
      if(g_pendingRegimeEventId!=rid)
      {
         g_pendingRegimeEventId=rid;
         g_pendingRegimeFirstSeen=Now();
         Audit("regime_delay_started",InpRegimeIndicatorName,rid,0,direction,0,entry,sl,tp,"delay_sec="+(string)delay,0,source+detail);
         return;
      }
      if(Now()-g_pendingRegimeFirstSeen<delay)
      {
         Audit("regime_delay_pending",InpRegimeIndicatorName,rid,0,direction,0,entry,sl,tp,"age="+(string)(Now()-g_pendingRegimeFirstSeen),0,source+detail);
         return;
      }
   }
   if(tooStale)
   {
      Audit("regime_signal_stale",InpRegimeIndicatorName,rid,0,direction,0,entry,sl,tp,"shift="+(string)signalIndex,0,source+detail);
      g_lastRegimeEventId=rid;
      return;
   }
   string wReason;
   if(!TradeWindowAllowed(wReason))
   {
      if(g_regimeOpenPreWindowSignalRuntime)
      {
         g_pendingRegimeWindowEventId=rid;
         g_pendingRegimeWindowDirection=direction;
         g_pendingRegimeWindowSignalTime=signalTime;
         g_pendingRegimeWindowSl=sl;
         g_pendingRegimeWindowTp=tp;
         Audit("regime_deferred_until_window",InpRegimeIndicatorName,rid,0,direction,0,entry,sl,tp,wReason,0,source+detail);
      }
      else Audit("regime_blocked_window",InpRegimeIndicatorName,rid,0,direction,0,entry,sl,tp,wReason,0,source+detail);
      g_lastRegimeEventId=rid;
      return;
   }
   PostRegimeEvent("confirmed_signal",direction,signalIndex,signalTime,entry,sl,tp,source,reason+detail);
   g_lastRegimeEventId=rid;
   g_lastRegimeConfirmedEventId=rid;
}

void TryPendingRegimeWindow()
{
   if(g_pendingRegimeWindowEventId=="" || !g_regimeOpenPreWindowSignalRuntime) return;
   string reason;
   if(!TradeWindowAllowed(reason)) return;
   string dir; int idx; datetime t; double entry; string src;
   AtomicSignal a;
   FindLatestAtomicSignal(a,false);
   if(!FindRegimeSignal(a.direction,dir,idx,t,entry,src) || RegimeEventId(dir,t)!=g_pendingRegimeWindowEventId)
   {
      Audit("regime_deferred_window_cancelled",InpRegimeIndicatorName,g_pendingRegimeWindowEventId,0,g_pendingRegimeWindowDirection,0,entry,g_pendingRegimeWindowSl,g_pendingRegimeWindowTp,"signal_missing_or_changed",0,src);
      g_pendingRegimeWindowEventId="";
      return;
   }
   Audit("regime_deferred_window_open_execute",InpRegimeIndicatorName,g_pendingRegimeWindowEventId,0,dir,0,entry,g_pendingRegimeWindowSl,g_pendingRegimeWindowTp,"window_open",0,src);
   DirectExecute(g_pendingRegimeWindowEventId+"|window_open",dir,g_pendingRegimeWindowSl,g_pendingRegimeWindowTp,InpRegimeIndicatorName,0.0,"r"+DoubleToString(g_regimeDirectMt5HalfBeRRuntime,1),t);
   g_pendingRegimeWindowEventId="";
}

void RegimeProbe()
{
   if(!AuditEnabled() || !InpRegimeSignalProbeAudit) return;
   datetime now=TimeCurrent();
   if(g_lastRegimeProbe>0 && now-g_lastRegimeProbe<MathMax(1,InpRegimeSignalProbeIntervalSeconds)) return;
   string direction=""; int idx=-1; datetime t=0; double entry=0; string src="";
   AtomicSignal a;
   FindLatestAtomicSignal(a,false);
   bool found=FindRegimeSignal(a.direction,direction,idx,t,entry,src);
   string hash=(found?direction+"|"+(string)idx+"|"+(string)((long)t)+"|"+FmtPrice(entry):"NONE");
   if(InpRegimeSignalProbeWriteOnChange && hash==g_lastRegimeProbeHash && g_lastRegimeProbe>0) return;
   g_lastRegimeProbe=now;
   g_lastRegimeProbeHash=hash;
   int h=FileOpen(RegimeProbeFile(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0) FileWrite(h,"server_time","gmt_time","event","build","symbol","tf","found","dir","shift","signal_time","entry","source","up_buf","dn_buf","max_shift");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,FmtTime(TimeCurrent()),FmtTime(TimeGMT()),"probe",ATOMIC_BRIDGE_MT5_BUILD,_Symbol,TfString(),found?"1":"0",direction,(string)idx,FmtTime(t),FmtPrice(entry),src,(string)InpRegimeUpTrendSignalBuffer,(string)InpRegimeDnTrendSignalBuffer,(string)InpRegimeSignalProbeMaxShift);
   FileClose(h);
}


void DrawLine(string key,double price,color c,int style,string text)
{
   if(price<=0) return;
   string n=LEVEL_PREFIX+key;
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,n,OBJPROP_PRICE,price);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_STYLE,style);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
   ObjectSetString(0,n,OBJPROP_TEXT,text);
}

void DeleteLevels()
{
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,LEVEL_PREFIX)==0) ObjectDelete(0,n);
   }
}

void DrawOpenPositionLevels()
{
   if(!InpShowAtomicRegimeTradeLevels) return;
   DeleteLevels();
   int count=0;
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(!IsOwnedPosition(ticket)) continue;
      string c=PositionGetString(POSITION_COMMENT);
      if(!ContainsCi(c,"AtomicRegime") && !ContainsCi(c,"Atomic")) continue;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      DrawLine((string)ticket+"_ENTRY",entry,clrDeepSkyBlue,STYLE_SOLID,"ENTRY");
      DrawLine((string)ticket+"_SL",sl,clrTomato,STYLE_SOLID,"SL");
      DrawLine((string)ticket+"_TP",tp,clrLimeGreen,STYLE_SOLID,"TP");
      double htp=StateGet("HTP",ticket);
      if(htp>0) DrawLine((string)ticket+"_HC",htp,clrOrange,STYLE_DASH,"HC/BE");
      count++;
      if(count>=5) break;
   }
}

bool AtomicGeometryValid(const AtomicSignal &s,double execSl,double finalTp,string &reason)
{
   reason="";
   MqlTick tick;
   SymbolInfoTick(_Symbol,tick);
   double live=s.direction=="BUY"?tick.ask:tick.bid;
   double minGap=StopMinDistance();
   if(s.entry<=0 || execSl<=0 || finalTp<=0){ reason="missing_entry_sl_tp"; return false; }
   if(s.direction=="BUY")
   {
      if(execSl>=s.entry-minGap){ reason="buy_sl_not_below_signal_entry"; return false; }
      if(finalTp<=s.entry+minGap){ reason="buy_tp_not_above_signal_entry"; return false; }
      if(live>0 && finalTp<=live+minGap){ reason="buy_tp_already_passed_live_price"; return false; }
   }
   else if(s.direction=="SELL")
   {
      if(execSl<=s.entry+minGap){ reason="sell_sl_not_above_signal_entry"; return false; }
      if(finalTp>=s.entry-minGap){ reason="sell_tp_not_below_signal_entry"; return false; }
      if(live>0 && finalTp>=live-minGap){ reason="sell_tp_already_passed_live_price"; return false; }
   }
   else { reason="bad_direction"; return false; }
   return true;
}

void ProcessSignals(string reason)
{
   AtomicSignal s;
   bool hasAtomic=FindLatestAtomicSignal(s,reason=="init" || reason=="timer");
   if(hasAtomic)
   {
      if((reason=="init" || reason=="init_retry") || !InpLogOnlyOnChange || s.eventId!=g_lastEventId)
      {
         PrintFormat("AtomicBridgeMT5 latest_signal reason=%s symbol=%s tf=%s dir=%s idx=%d bar=%s entry=%s sl=%s tp1=%s tp2=%s tp3=%s tp4=%s tp5=%s trend='%s'",reason,_Symbol,TfString(),s.direction,s.index,FmtTime(s.time),FmtPrice(s.entry),FmtPrice(s.sl),FmtPrice(s.tp1),FmtPrice(s.tp2),FmtPrice(s.tp3),FmtPrice(s.tp4),FmtPrice(s.tp5),s.trendName);
      }
      g_lastObservedSignalDirection=s.direction;
      g_lastObservedSignalTime=s.time;
      g_lastObservedSignalValue=s.entry;
      double execSl=s.sl;
      string detail="";
      if(g_atomicDirectRiskGeometryRuntime) AtomicRGeometrySl(s.direction,s.entry,FinalTp(s),g_atomicDirectTargetRRuntime,execSl,detail);
      string geomReason="";
      bool geomOk=AtomicGeometryValid(s,execSl,FinalTp(s),geomReason);
      if(!geomOk)
         Print("AtomicBridgeMT5 warning: invalid signal geometry; not posting reason=",geomReason," dir=",s.direction," signal_entry=",FmtPrice(s.entry)," sl=",FmtPrice(execSl)," final_tp=",FmtPrice(FinalTp(s)));
      if(g_atomicModeEnabledRuntime && geomOk)
      {
         bool changed=(s.eventId!=g_lastEventId);
         if(reason=="init" || reason=="init_retry")
         {
            g_lastEventId=s.eventId;
            if(InpSendInitialConfirmedOnStart) PostAtomicEvent("confirmed_signal",s,reason);
            else PostAtomicEvent("resolved_state",s,reason);
         }
         else if(changed)
         {
            PostAtomicEvent("confirmed_signal",s,reason);
            g_lastEventId=s.eventId;
         }
      }
   }
   else if(InpLogNoneSignals) Print("AtomicBridgeMT5 latest_signal NONE reason=",reason," symbol=",_Symbol," tf=",TfString());

   if(g_atomicRegimeModeEnabledRuntime)
   {
      string rdir; int ridx; datetime rt; double re; string rsrc;
      if(FindRegimeSignal(hasAtomic?s.direction:"",rdir,ridx,rt,re,rsrc))
      {
         g_lastRegimeObservedSignalDirection=rdir;
         g_lastRegimeObservedSignalTime=rt;
         g_lastRegimeObservedSignalValue=re;
         HandleRegime(reason,rdir,ridx,rt,re,rsrc,hasAtomic?s.direction:"",hasAtomic?s.entry:0.0,hasAtomic?s.sl:0.0);
      }
   }
}

void DashRect(string name,int x,int y,int w,int h,color bg,color border)
{
   string o=DASH_PREFIX+name;
   if(ObjectFind(0,o)<0) ObjectCreate(0,o,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,o,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,o,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,o,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,o,OBJPROP_BORDER_COLOR,border);
}

void DashLabel(string name,int x,int y,string text,color c,int size=8)
{
   string o=DASH_PREFIX+name;
   if(ObjectFind(0,o)<0) ObjectCreate(0,o,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,o,OBJPROP_TEXT,text);
   ObjectSetInteger(0,o,OBJPROP_COLOR,c);
   ObjectSetInteger(0,o,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,o,OBJPROP_FONT,"Consolas");
}

void DashButton(string name,int x,int y,int w,int h,string text,color bg)
{
   string o=DASH_PREFIX+name;
   if(ObjectFind(0,o)<0) ObjectCreate(0,o,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,o,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,o,OBJPROP_YSIZE,h);
   ObjectSetString(0,o,OBJPROP_TEXT,text);
   ObjectSetInteger(0,o,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,o,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,o,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,o,OBJPROP_STATE,false);
}

void DashEdit(string name,int x,int y,int w,int h,string text)
{
   string o=DASH_PREFIX+name;
   bool created=false;
   if(ObjectFind(0,o)<0){ ObjectCreate(0,o,OBJ_EDIT,0,0,0); created=true; }
   ObjectSetInteger(0,o,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,o,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,o,OBJPROP_YSIZE,h);
   if(created) ObjectSetString(0,o,OBJPROP_TEXT,text);
   ObjectSetInteger(0,o,OBJPROP_BGCOLOR,C'35,43,58');
   ObjectSetInteger(0,o,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,o,OBJPROP_FONTSIZE,8);
}

void DeleteDashboard()
{
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,DASH_PREFIX)==0) ObjectDelete(0,n);
   }
}

string SpreadStatus()
{
   int s=CurrentSpreadPoints();
   return g_directMt5MaxSpreadRuntime<=0 ? "spread "+(string)s+" pt | no max" : (s<=g_directMt5MaxSpreadRuntime?"spread "+(string)s+" pt | OK":"spread "+(string)s+" pt | BLOCKED");
}

string WindowStatus()
{
   string r;
   bool ok=TradeWindowAllowed(r);
   return ok?"window OK":"window BLOCKED "+r;
}

void DrawDashboard()
{
   if(!InpShowDashboard) return;
   if(g_dashboardCollapsed)
   {
      DashRect("BG",10,18,330,42,C'24,30,42',C'90,178,255');
      DashLabel("TITLE",24,30,"ATOMIC BRIDGE MT5  "+string(ATOMIC_BRIDGE_MT5_BUILD),C'216,222,230',9);
      DashButton("BTN_DASH_COLLAPSE",304,28,24,22,"v",C'90,178,255');
      return;
   }
   DashRect("BG",10,18,1010,374,C'24,30,42',C'134,158,182');
   DashRect("CORE",26,56,664,316,C'18,24,36',C'65,116,172');
   DashRect("ACTION",704,56,286,316,C'31,38,52',C'221,55,78');
   DashButton("BTN_DASH_COLLAPSE",966,30,24,22,"^",C'90,178,255');
   DashLabel("TITLE",34,32,"AI STARSHIP ATOMIC BRIDGE MT5",C'216,222,230',12);
   DashLabel("SUB",356,34,_Symbol+" "+TfString()+" | "+string(ATOMIC_BRIDGE_MT5_BUILD),C'90,178,255',8);
   DashButton("BTN_DIRECT",718,88,118,24,g_directMt5EnabledRuntime?"DIRECT ON":"DIRECT OFF",g_directMt5EnabledRuntime?C'32,150,96':C'178,37,57');
   DashButton("BTN_POST",844,88,118,24,g_proTradePostEnabledRuntime?"POST ON":"POST OFF",g_proTradePostEnabledRuntime?C'32,150,96':C'178,37,57');
   DashButton("BTN_PRIORITY",718,116,118,24,g_directMt5PriorityDirectFirst?"DIRECT FIRST":"POST FIRST",C'38,101,176');
   DashButton("BTN_HALFBE",844,116,118,24,"ATOMIC HC TP"+(string)g_directMt5HalfBeTpIndexRuntime,C'34,136,160');
   DashButton("BTN_ATOMIC_MODE",718,144,118,24,g_atomicModeEnabledRuntime?"[x] ATOMIC":"[ ] ATOMIC",g_atomicModeEnabledRuntime?C'32,150,96':C'88,96,112');
   DashButton("BTN_REGIME_MODE",844,144,118,24,g_atomicRegimeModeEnabledRuntime?"[x] REGIME":"[ ] REGIME",g_atomicRegimeModeEnabledRuntime?C'32,150,96':C'88,96,112');
   DashButton("BTN_REGIME_SHIFT",718,172,118,24,g_regimeUseClosedBarRuntime?"REGIME SH1":"REGIME SH0",g_regimeUseClosedBarRuntime?C'34,136,160':C'178,37,57');
   DashButton("BTN_APPLY",844,172,118,24,"APPLY CFG",C'38,101,176');
   DashButton("BTN_REGIME_DELAY_MODE",718,200,244,24,g_regimeDelayValidationRuntime?"REG DELAY VALIDATE":"REG DIRECT",g_regimeDelayValidationRuntime?C'221,145,45':C'32,150,96');
   DashButton("BTN_FTMO",718,228,118,24,g_ftmoModeRuntime?"FTMO ON":"FTMO OFF",g_ftmoModeRuntime?C'32,150,96':C'88,96,112');
   DashButton("BTN_RISKLOT",844,228,118,24,g_riskLotOnlyRuntime?"RISKLOT ON":"RISKLOT OFF",g_riskLotOnlyRuntime?C'32,150,96':C'88,96,112');
   DashButton("BTN_AUDIT",718,256,118,24,g_auditEnabledRuntime?"AUDIT ON":"AUDIT OFF",g_auditEnabledRuntime?C'34,136,160':C'88,96,112');
   DashButton("BTN_REGIME_PREWIN",844,256,118,24,g_regimeOpenPreWindowSignalRuntime?"REG WIN ON":"REG WIN OFF",g_regimeOpenPreWindowSignalRuntime?C'32,150,96':C'88,96,112');
   DashButton("BTN_ATOMIC_TP",718,284,118,24,"ATOMIC TP"+(string)g_directMt5TpIndexRuntime,C'34,136,160');
   DashButton("BTN_ATOMIC_SL_MODE",844,284,118,24,g_atomicDirectRiskGeometryRuntime?"AT SL R-GEOM":"AT SL INDIC",g_atomicDirectRiskGeometryRuntime?C'32,150,96':C'88,96,112');
   DashButton("BTN_ATOMIC_RR",718,312,244,24,"ATOMIC TARGET "+DoubleToString(g_atomicDirectTargetRRuntime,1)+"R",C'38,101,176');
   DashLabel("L_LOT",38,66,"Lot",C'184,196,210'); DashEdit("EDIT_LOT",70,62,70,22,DoubleToString(g_directMt5LotRuntime,2));
   DashLabel("L_SPREAD",158,66,"Max spread pts",C'184,196,210'); DashEdit("EDIT_SPREAD",260,62,70,22,(string)g_directMt5MaxSpreadRuntime);
   DashLabel("L_RR",342,66,"Regime TP R",C'184,196,210'); DashEdit("EDIT_RR",420,62,48,22,DoubleToString(g_regimeRRRuntime,1));
   DashLabel("L_REG_HB",482,66,"Regime HC/BE R",C'184,196,210'); DashEdit("EDIT_REGIME_HALFBE",590,62,48,22,DoubleToString(g_regimeDirectMt5HalfBeRRuntime,1));
   DashLabel("L_AT_HC",38,88,"Atomic HC/BE TP leg",C'184,196,210'); DashEdit("EDIT_ATOMIC_HALFBE_TP",172,84,42,22,(string)g_directMt5HalfBeTpIndexRuntime);
   DashLabel("L_AT_R",226,88,"Atomic fallback HC/BE R",C'184,196,210'); DashEdit("EDIT_HALFBE",382,84,48,22,DoubleToString(g_directMt5HalfBeRRuntime,1));
   DashLabel("L_REG_DELAY",446,88,"Reg delay sec",C'184,196,210'); DashEdit("EDIT_REGIME_DELAY",538,84,56,22,(string)g_regimeConfirmDelaySecondsRuntime);
   DashLabel("L_REG_SCALE",608,88,"Reg SL %",C'184,196,210'); DashEdit("EDIT_REGIME_SCALE",650,84,34,22,DoubleToString(g_regimeFinalRiskScalePctRuntime,0));
   DashLabel("L_ALLOWED",38,246,"Allowed GMT",C'184,196,210'); DashEdit("EDIT_ALLOWED",126,242,180,22,g_directMt5AllowedWindowsRuntime);
   DashLabel("L_NOTRADE",324,246,"Block GMT",C'184,196,210'); DashEdit("EDIT_NOTRADE",396,242,180,22,g_directMt5NoTradeWindowsRuntime);
   MqlTick tick; SymbolInfoTick(_Symbol,tick);
   DashLabel("STATE",38,112,"Live BID "+FmtPrice(tick.bid)+" / ASK "+FmtPrice(tick.ask)+" | "+SpreadStatus()+" | "+WindowStatus(),clrWhite,8);
   DashLabel("MODES",38,134,"Modes: Atomic="+(g_atomicModeEnabledRuntime?"ON":"OFF")+" | Regime="+(g_atomicRegimeModeEnabledRuntime?"ON":"OFF")+" | RegExec="+(g_regimeDelayValidationRuntime?"DELAY":"DIRECT")+" | ProTrade="+(g_proTradePostEnabledRuntime?"ON":"OFF")+" | Risk="+(AccountRiskRuntime()?(g_ftmoModeRuntime?"FTMO":"RISKLOT"):"OFF")+" | Audit="+(g_auditEnabledRuntime?"ON":"OFF"),C'90,178,255',8);
   DashLabel("REGWIN",38,228,"AtomicRegime pre-window execution: "+(g_regimeOpenPreWindowSignalRuntime?"ON":"OFF")+" | pending="+(g_pendingRegimeWindowEventId==""?"none":g_pendingRegimeWindowDirection+" "+FmtTime(g_pendingRegimeWindowSignalTime)),C'184,196,210',8);
   DashLabel("LAST_A",38,154,"Last Atomic: "+(g_lastObservedSignalDirection==""?"NONE":g_lastObservedSignalDirection)+" | "+FmtTime(g_lastObservedSignalTime),C'184,196,210',8);
   DashLabel("LAST_R",38,172,"Last Regime: "+(g_lastRegimeObservedSignalDirection==""?"NONE":g_lastRegimeObservedSignalDirection)+" | "+FmtTime(g_lastRegimeObservedSignalTime),C'184,196,210',8);
   DashLabel("TPHC_A",38,192,"Atomic: TP leg="+(string)g_directMt5TpIndexRuntime+" | HC/BE TP leg="+(string)g_directMt5HalfBeTpIndexRuntime+" | SL="+(g_atomicDirectRiskGeometryRuntime?DoubleToString(g_atomicDirectTargetRRuntime,1)+"R geometry":"indicator"),C'184,196,210',8);
   DashLabel("TPHC_R",38,210,"AtomicRegime: TP R="+DoubleToString(g_regimeRRRuntime,1)+" | HC/BE R="+DoubleToString(g_regimeDirectMt5HalfBeRRuntime,1)+" | SL scale="+DoubleToString(g_regimeFinalRiskScalePctRuntime,0)+"%",C'184,196,210',8);
}

void ApplyDashboard()
{
   string o;
   o=DASH_PREFIX+"EDIT_LOT"; if(ObjectFind(0,o)>=0) g_directMt5LotRuntime=MathMax(0.01,StringToDouble(ObjectGetString(0,o,OBJPROP_TEXT)));
   o=DASH_PREFIX+"EDIT_SPREAD"; if(ObjectFind(0,o)>=0) g_directMt5MaxSpreadRuntime=MathMax(0,(int)StringToInteger(ObjectGetString(0,o,OBJPROP_TEXT)));
   o=DASH_PREFIX+"EDIT_ALLOWED"; if(ObjectFind(0,o)>=0) g_directMt5AllowedWindowsRuntime=Trim(ObjectGetString(0,o,OBJPROP_TEXT));
   o=DASH_PREFIX+"EDIT_NOTRADE"; if(ObjectFind(0,o)>=0) g_directMt5NoTradeWindowsRuntime=Trim(ObjectGetString(0,o,OBJPROP_TEXT));
   o=DASH_PREFIX+"EDIT_RR"; if(ObjectFind(0,o)>=0) g_regimeRRRuntime=MathMax(0.1,StringToDouble(ObjectGetString(0,o,OBJPROP_TEXT)));
   o=DASH_PREFIX+"EDIT_REGIME_HALFBE"; if(ObjectFind(0,o)>=0) g_regimeDirectMt5HalfBeRRuntime=MathMax(0.0,StringToDouble(ObjectGetString(0,o,OBJPROP_TEXT)));
   o=DASH_PREFIX+"EDIT_ATOMIC_HALFBE_TP"; if(ObjectFind(0,o)>=0) g_directMt5HalfBeTpIndexRuntime=MathMax(1,MathMin(5,(int)StringToInteger(ObjectGetString(0,o,OBJPROP_TEXT))));
   o=DASH_PREFIX+"EDIT_HALFBE"; if(ObjectFind(0,o)>=0) g_directMt5HalfBeRRuntime=MathMax(0.0,StringToDouble(ObjectGetString(0,o,OBJPROP_TEXT)));
   o=DASH_PREFIX+"EDIT_REGIME_DELAY"; if(ObjectFind(0,o)>=0) g_regimeConfirmDelaySecondsRuntime=MathMax(-1,(int)StringToInteger(ObjectGetString(0,o,OBJPROP_TEXT)));
   o=DASH_PREFIX+"EDIT_REGIME_SCALE"; if(ObjectFind(0,o)>=0) g_regimeFinalRiskScalePctRuntime=MathMax(10.0,MathMin(200.0,StringToDouble(ObjectGetString(0,o,OBJPROP_TEXT))));
   Print("AtomicBridgeMT5 dashboard applied direct=",g_directMt5EnabledRuntime," post=",g_proTradePostEnabledRuntime," lot=",DoubleToString(g_directMt5LotRuntime,2)," spread=",g_directMt5MaxSpreadRuntime," allowed=",g_directMt5AllowedWindowsRuntime," block=",g_directMt5NoTradeWindowsRuntime," risk=",(g_ftmoModeRuntime?"FTMO":(g_riskLotOnlyRuntime?"RISKLOT":"OFF")));
   DrawDashboard();
   ChartRedraw(0);
}

double NextAtomicR(double r){ if(r<0.75) return 1.0; if(r<1.5) return 2.0; if(r<2.5) return 3.0; return 0.5; }

int OnInit()
{
   g_proTradePostEnabledRuntime=InpEnableProTradePost;
   g_directMt5EnabledRuntime=InpDirectMt5ExecutionEnabled;
   g_directMt5PriorityDirectFirst=(Lower(InpDirectMt5Priority)=="direct_first");
   g_atomicModeEnabledRuntime=InpEnableAtomicMode;
   g_atomicRegimeModeEnabledRuntime=InpEnableAtomicRegimeMode;
   g_directMt5LotRuntime=InpDirectMt5Lot;
   g_directMt5MaxSpreadRuntime=MathMax(0,InpDirectMt5MaxSpreadPoints);
   g_directMt5TpIndexRuntime=MathMax(1,MathMin(5,InpDirectMt5TpIndex));
   g_atomicDirectRiskGeometryRuntime=InpAtomicDirectRiskGeometryEnabled;
   g_atomicDirectTargetRRuntime=InpAtomicDirectTargetR;
   g_directMt5HalfBeRRuntime=InpDirectMt5HalfBeR;
   g_directMt5HalfBeTpIndexRuntime=MathMax(1,MathMin(5,InpDirectMt5HalfBeTpIndex));
   g_regimeDirectMt5HalfBeRRuntime=MathMax(0.0,InpRegimeDirectMt5HalfBeR);
   g_regimeRRRuntime=MathMax(0.1,InpRegimeRR);
   g_regimeFinalRiskScalePctRuntime=MathMax(10.0,MathMin(200.0,InpRegimeFinalRiskScalePct));
   g_regimeUseClosedBarRuntime=InpRegimeUseClosedBar;
   g_regimeDelayValidationRuntime=InpRegimeDelayValidationMode;
   g_regimeConfirmDelaySecondsRuntime=MathMax(-1,InpRegimeConfirmDelaySeconds);
   g_regimeOpenPreWindowSignalRuntime=InpRegimeOpenPreWindowSignal;
   g_directMt5AllowedWindowsRuntime=InpDirectMt5AllowedTradeWindowsGmt;
   g_directMt5NoTradeWindowsRuntime=InpDirectMt5NoTradeWindowsGmt;
   g_auditEnabledRuntime=(InpDirectMt5AuditCsv || InpRegimeSignalProbeAudit || InpAccountRiskAuditEnabled);
   EventSetTimer(MathMax(1,InpPollSeconds));
   EnsureIndicatorHandle();
   if(InpShowDashboard) DrawDashboard();
   if(InpLogOnInit) Print("AtomicBridgeMT5 BUILD=",ATOMIC_BRIDGE_MT5_BUILD," indicator=",InpIndicatorName," symbol=",_Symbol," tf=",TfString()," direct=",g_directMt5EnabledRuntime," post=",g_proTradePostEnabledRuntime," regime=",g_atomicRegimeModeEnabledRuntime," risk=",(AccountRiskRuntime()?"ON":"OFF"));
   RiskAudit("init","loaded");
   ProcessSignals("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_indicatorHandle!=INVALID_HANDLE) IndicatorRelease(g_indicatorHandle);
   if(g_atrHandle!=INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   DeleteDashboard();
   DeleteLevels();
   if(InpSendUnregisterOnDeinit && g_proTradePostEnabledRuntime)
      SendPost("unregister","",InpIndicatorName,InpSignalProfile,"atomic_unregister|"+_Symbol+"|"+TfString(),0,0,0,0,"unregister","deinit");
   Print("AtomicBridgeMT5 uninit reason=",reason);
}

void OnTimer()
{
   ProcessSignals("timer");
   TryPendingRegimeWindow();
   ManagePositions();
   PositionProbe();
   RegimeProbe();
   RiskAudit("heartbeat","timer");
   DrawOpenPositionLevels();
   if(InpShowDashboard) DrawDashboard();
}

void OnTick()
{
   TryPendingRegimeWindow();
   ManagePositions();
   DrawOpenPositionLevels();
   if(InpShowDashboard) DrawDashboard();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   string p=DASH_PREFIX;
   if(sparam==p+"BTN_DASH_COLLAPSE") { g_dashboardCollapsed=!g_dashboardCollapsed; DeleteDashboard(); DrawDashboard(); return; }
   if(sparam==p+"BTN_DIRECT") g_directMt5EnabledRuntime=!g_directMt5EnabledRuntime;
   else if(sparam==p+"BTN_POST") g_proTradePostEnabledRuntime=!g_proTradePostEnabledRuntime;
   else if(sparam==p+"BTN_PRIORITY") g_directMt5PriorityDirectFirst=!g_directMt5PriorityDirectFirst;
   else if(sparam==p+"BTN_HALFBE") g_directMt5HalfBeTpIndexRuntime=(g_directMt5HalfBeTpIndexRuntime%5)+1;
   else if(sparam==p+"BTN_ATOMIC_MODE") g_atomicModeEnabledRuntime=!g_atomicModeEnabledRuntime;
   else if(sparam==p+"BTN_REGIME_MODE") g_atomicRegimeModeEnabledRuntime=!g_atomicRegimeModeEnabledRuntime;
   else if(sparam==p+"BTN_REGIME_SHIFT") g_regimeUseClosedBarRuntime=!g_regimeUseClosedBarRuntime;
   else if(sparam==p+"BTN_REGIME_DELAY_MODE") g_regimeDelayValidationRuntime=!g_regimeDelayValidationRuntime;
   else if(sparam==p+"BTN_FTMO") { g_ftmoModeRuntime=!g_ftmoModeRuntime; if(g_ftmoModeRuntime) g_riskLotOnlyRuntime=false; }
   else if(sparam==p+"BTN_RISKLOT") { g_riskLotOnlyRuntime=!g_riskLotOnlyRuntime; if(g_riskLotOnlyRuntime) g_ftmoModeRuntime=false; }
   else if(sparam==p+"BTN_AUDIT") g_auditEnabledRuntime=!g_auditEnabledRuntime;
   else if(sparam==p+"BTN_REGIME_PREWIN") g_regimeOpenPreWindowSignalRuntime=!g_regimeOpenPreWindowSignalRuntime;
   else if(sparam==p+"BTN_ATOMIC_TP") g_directMt5TpIndexRuntime=(g_directMt5TpIndexRuntime%5)+1;
   else if(sparam==p+"BTN_ATOMIC_SL_MODE") g_atomicDirectRiskGeometryRuntime=!g_atomicDirectRiskGeometryRuntime;
   else if(sparam==p+"BTN_ATOMIC_RR") g_atomicDirectTargetRRuntime=NextAtomicR(g_atomicDirectTargetRRuntime);
   else if(sparam==p+"BTN_APPLY") ApplyDashboard();
   if(StringFind(sparam,p)==0)
   {
      Print("AtomicBridgeMT5 dashboard click ",sparam);
      ApplyDashboard();
   }
}

