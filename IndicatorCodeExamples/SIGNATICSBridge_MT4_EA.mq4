//+------------------------------------------------------------------+
//| SIGNATICS Bridge MT4 EA                                          |
//| Reads SIGNATICS-ALGO V2 chart objects and posts V2 bridge events.|
//+------------------------------------------------------------------+
#property strict

#define SIGNATICS_BRIDGE_BUILD "2026-06-08.2330-daily-atr-no-fixed-cap"

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
input bool   InpShowDashboard = true;
input bool   InpEnableProTradePost = false;
input bool   InpSendUnregisterOnDeinit = true;
input bool   InpSendInitialConfirmedOnStart = false;
input bool   InpSendResolvedStateEvents = true;
input int    InpResolvedHeartbeatSeconds = 900;
input int    InpRegisterHeartbeatSeconds = 900;
input string InpApiBaseUrl = "http://127.0.0.1";
input string InpApiPath = "/api/v1/mt4/bridge/signal";
input string InpBridgeToken = "";
input string InpSignalProfile = "signatics";
input string InpBridgeSignalMode = "buffer"; // buffer | chart_object
input int    InpHttpTimeoutMs = 5000;
input bool   InpDirectMt4ExecutionEnabled = true;
input string InpDirectMt4Priority = "post_first"; // direct_first | post_first
input double InpDirectMt4Lot = 0.10; // Manual fallback when automatic risk sizing is unavailable.
input bool   InpDirectMt4AutoLotEnabled = true;
input string InpDirectMt4AutoLotReferenceSymbol = "XAUUSDm";
input double InpDirectMt4AutoLotReferenceLot = 0.10;
input int    InpDirectMt4AutoLotDailyAtrPeriod = 14;
input double InpDirectMt4AutoLotMax = 0.00; // 0=broker maximum only.
input int    InpDirectMt4Magic = 970201;
input int    InpDirectMt4Slippage = 30;
input int    InpDirectMt4MaxSpreadPoints = 0;
input string InpDirectMt4AllowedTradeWindowsGmt = "";
input string InpDirectMt4NoTradeWindowsGmt = "19:30-20:30";
input bool   InpDirectMt4CloseReverse = false;
input double InpDirectMt4HalfBeR = 2.0;
input bool   InpDirectMt4AuditCsv = true;
input int    InpDirectMt4HistoryAuditSeconds = 2;
input bool   InpDirectMt4PositionProbeAudit = true;
input int    InpDirectMt4PositionProbeIntervalSeconds = 30;
input bool   InpDirectMt4PositionProbeWriteOnChange = true;
input int    InpDirectAtrPeriod = 14;
input double InpDirectAtrMultiplier = 3.0;
input double InpDirectRR = 3.0;
input double InpDirectMinRiskPricePct = 0.0020;
input double InpDirectMinRiskPoints = 0.0;
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
input int    InpFastSignalLookbackBars = 3;
input int    InpFastSignalMaxAgeSeconds = 0; // 0=auto, allows the configured live shift window
input int    InpFastSignalRecoveryLookbackBars = 10;
input int    InpFastSignalRetrySeconds = 2;
input int    InpFastSignalHistoryLookbackBars = 1000;
input bool   InpSendBufferHistoryResolvedOnInit = true;
input bool   InpLogFastBufferSignals = true;
input bool   InpScanFastBuffersOnTick = true;
input bool   InpEnableFastBufferProbeAudit = true;
input int    InpFastBufferProbeIntervalSeconds = 30;
input int    InpFastBufferProbeMaxShift = 3;
input bool   InpFastBufferProbeWriteOnChange = true;
input int    InpBufferHistoryNoneLogSeconds = 300;
input bool   InpAllowObjectConfirmedFallback = false;
input bool   InpChartObjectStrictGroups = true;
input bool   InpChartObjectRequireAllTps = true;
input int    InpChartObjectMaxSlotTimeSkewSeconds = 5;
input int    InpChartObjectStableSeconds = 1;
input bool   InpChartObjectRequireFreshConfirmed = true;
input bool   InpSyncICustomInputsToChart = true;
input bool   InpSuppressHiddenICustomSideEffects = true; // Isolates only SMC chart objects.
input bool   InpProtectVisibleSignaticsZones = true;
input bool   InpSignaticsEnableHTFFilter = true;
input bool   InpSignaticsRequireBothHTF = true;
input int    InpSignaticsConfirmationDelay = 0;
input bool   InpSignaticsEnableHunt = true;
input bool   InpSignaticsEnableFVG = true;
input bool   InpSignaticsShowSMCVisuals = true;
input color  InpSignaticsFVGBuyColor = C'0,40,18';
input color  InpSignaticsFVGSellColor = C'40,0,12';
input color  InpSignaticsHuntBuyColor = C'0,220,180';
input color  InpSignaticsHuntSellColor = C'220,0,100';
input bool   InpSignaticsEnableD1Filter = true;
input bool   InpSignaticsEnableAlerts = true;
input bool   InpSignaticsAlertPopup = true;
input bool   InpSignaticsAlertSound = true;
input bool   InpSignaticsAlertEmail = false;
input bool   InpSignaticsAlertPush = true;
input string InpSignaticsSoundFile = "alert2.wav";
input int    InpSignaticsAlertCooldown = 60;
input int    InpSignaticsArrowSize = 4;
input color  InpSignaticsBuyArrowColor = C'0,255,160';
input color  InpSignaticsSellArrowColor = C'255,40,100';
input int    InpSignaticsArrowDistance = 18;
input int    InpSignaticsBuyArrowCode = 225;
input int    InpSignaticsSellArrowCode = 226;
input bool   InpSignaticsShowConfDots = true;
input bool   InpSignaticsShowSigLabels = true;
input int    InpSignaticsSigLabelFS = 9;
input color  InpSignaticsBuyLabelColor = C'0,230,255';
input color  InpSignaticsSellLabelColor = C'255,80,160';
input int    InpSignaticsRefreshInterval = 1;
input int    InpSignaticsDeepScanBars = 50;

struct SignaticsZoneSnapshot
{
   string name;
   bool exists;
   int type;
   datetime time0;
   datetime time1;
   double price0;
   double price1;
   long colorValue;
   long styleValue;
   long widthValue;
   long backValue;
   long fillValue;
   long hiddenValue;
   long selectableValue;
   long zorderValue;
};

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
string   g_lastFastConfirmedEventId = "";
string   g_pendingFastConfirmedEventId = "";
datetime g_pendingFastConfirmedLastTry = 0;
string   g_pendingFastConfirmedDirection = "";
datetime g_pendingFastConfirmedSignalTime = 0;
double   g_pendingFastConfirmedEntry = 0.0;
int      g_pendingFastConfirmedBufferIndex = -1;
int      g_pendingFastConfirmedShift = -1;
string   g_lastFastConfirmedDirection = "";
datetime g_lastFastConfirmedSignalTime = 0;
double   g_lastFastConfirmedEntry = 0.0;
datetime g_lastBufferHistoryNoneLogTime = 0;
string   g_lastObservedSignalDirection = "";
datetime g_lastObservedSignalTime = 0;
double   g_lastObservedSignalValue = 0.0;
datetime g_lastFastBufferProbeSnapshot = 0;
datetime g_lastFastBufferProbeChangeCheck = 0;
string   g_lastFastBufferProbeSignature = "";
string   g_pendingObjectEventId = "";
datetime g_pendingObjectFirstSeen = 0;
string   g_lastDirectMt4EventId = "";
int      g_lastDirectMt4Ticket = 0;
string   g_lastDirectMt4Direction = "";
int      g_zoneProtectionDepth = 0;
SignaticsZoneSnapshot g_zoneProtectionSnapshots[4];
bool     g_proTradePostEnabledRuntime = true;
bool     g_directMt4EnabledRuntime = false;
bool     g_directMt4PriorityDirectFirst = true;
double   g_directMt4LotRuntime = 0.0;
int      g_directMt4MaxSpreadRuntime = 0;
double   g_directMt4HalfBeRRuntime = 0.0;
string   g_directMt4AllowedWindowsRuntime = "";
string   g_directMt4NoTradeWindowsRuntime = "";
bool     g_dashboardCollapsed = false;
uint     g_lastDashClickMs = 0;
string   g_lastDashClickObject = "";
uint     g_lastPostDisabledMs = 0;
datetime g_directMt4LastHistoryAuditScan = 0;
datetime g_directMt4LastHistoryAuditTime = 0;
int      g_directMt4LastHistoryAuditTicket = 0;
datetime g_directMt4LastPositionProbe = 0;
string   g_directMt4LastPositionProbeHash = "";
string   DASH_PREFIX = "SIGNATICS_BRIDGE_DASH_";

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

int _direct_minutes_from_hhmm(string value)
{
   string s=_trim(value);
   int pos=StringFind(s,":");
   if(pos<=0)
      return -1;
   int hh=StrToInteger(StringSubstr(s,0,pos));
   int mm=StrToInteger(StringSubstr(s,pos+1));
   if(hh<0 || hh>23 || mm<0 || mm>59)
      return -1;
   return hh*60+mm;
}

bool _direct_minute_in_range(int minuteOfDay,string rangeText)
{
   string s=_trim(rangeText);
   int sep=StringFind(s,"-");
   if(sep<=0)
      return false;
   int start=_direct_minutes_from_hhmm(StringSubstr(s,0,sep));
   int stop=_direct_minutes_from_hhmm(StringSubstr(s,sep+1));
   if(start<0 || stop<0)
      return false;
   int cur=MathMax(0,MathMin(1439,minuteOfDay));
   if(start==stop)
      return true;
   if(start<stop)
      return (cur>=start && cur<stop);
   return (cur>=start || cur<stop);
}

bool _direct_in_no_trade_window_gmt()
{
   string raw=_trim(g_directMt4NoTradeWindowsRuntime);
   if(StringLen(raw)<=0)
      return false;
   datetime nowGmt=TimeGMT();
   int minute=TimeHour(nowGmt)*60+TimeMinute(nowGmt);
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string parts[];
   int n=StringSplit(raw,44,parts);
   for(int i=0;i<n;i++)
   {
      if(_direct_minute_in_range(minute,parts[i]))
         return true;
   }
   return false;
}

bool _direct_in_allowed_trade_window_gmt()
{
   string raw=_trim(g_directMt4AllowedWindowsRuntime);
   if(StringLen(raw)<=0)
      return true;
   datetime nowGmt=TimeGMT();
   int minute=TimeHour(nowGmt)*60+TimeMinute(nowGmt);
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string parts[];
   int n=StringSplit(raw,44,parts);
   for(int i=0;i<n;i++)
   {
      if(_direct_minute_in_range(minute,parts[i]))
         return true;
   }
   return false;
}

string _direct_trade_window_status()
{
   if(!_direct_in_allowed_trade_window_gmt())
      return "BLOCK allowed_window";
   if(_direct_in_no_trade_window_gmt())
      return "BLOCK no_trade_window";
   return "WINDOW OK";
}

string _direct_spread_status(int spread)
{
   if(g_directMt4MaxSpreadRuntime<=0)
      return "SPREAD GOV OFF";
   if(spread>g_directMt4MaxSpreadRuntime)
      return "SPREAD BLOCK "+IntegerToString(spread)+"/"+IntegerToString(g_directMt4MaxSpreadRuntime);
   return "SPREAD OK "+IntegerToString(spread)+"/"+IntegerToString(g_directMt4MaxSpreadRuntime);
}

bool _direct_priority_direct_first()
{
   return g_directMt4PriorityDirectFirst;
}

int _direct_owner_code()
{
   string mode=_lower_copy(_trim(InpBridgeSignalMode));
   int modeCode=StringFind(mode,"chart")>=0?2:1;
   return Period()*10+modeCode;
}

bool _direct_order_owned_by_instance(int ticket,string source,bool adoptLegacy)
{
   int ownerCode=_direct_owner_code();
   double owner=_direct_state_get("OWNER",ticket);
   if(owner>0.0)
      return (int)owner==ownerCode;
   bool bufferMode=(ownerCode%10)==1;
   bool sourceLooksBuffer=_contains_ci(source,"BUFFER") || _contains_ci(source,"SIGNATICS_BU") || _contains_ci(source,"fastbuf");
   if(bufferMode!=sourceLooksBuffer)
      return false;
   if(adoptLegacy)
      _direct_state_set("OWNER",ticket,ownerCode);
   return true;
}

bool _direct_close_reverse_positions(string direction)
{
   if(!InpDirectMt4CloseReverse)
      return true;
   int targetType=(direction=="BUY")?OP_SELL:OP_BUY;
   bool ok=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic || OrderType()!=targetType)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(),OrderComment(),true))
         continue;
      RefreshRates();
      double closePx=(targetType==OP_BUY)?Bid:Ask;
      if(!OrderClose(OrderTicket(),OrderLots(),closePx,InpDirectMt4Slippage,clrSilver))
      {
         Print("SIGNATICSBridge direct_mt4 reverse close failed ticket=",OrderTicket()," err=",GetLastError());
         ok=false;
      }
   }
   return ok;
}

bool _direct_price_ok(double value)
{
   return (MathIsValidNumber(value) && value!=EMPTY_VALUE && value!=2147483647.0 && value>0.0);
}

void _direct_fill_fallback_levels(string direction,double entry,double &sl,double &tp)
{
   if(_direct_price_ok(sl) && _direct_price_ok(tp))
      return;
   double point=MarketInfo(Symbol(),MODE_POINT);
   if(point<=0.0)
      point=Point;
   double atr=iATR(Symbol(),Period(),MathMax(1,InpDirectAtrPeriod),1);
   double defaultDist=MathMax(point*120.0,MathAbs(entry)*0.001);
   double atrRisk=MathMax(atr,defaultDist)*MathMax(0.1,InpDirectAtrMultiplier);
   double pctRisk=MathAbs(entry)*MathMax(0.0,InpDirectMinRiskPricePct);
   double absoluteRisk=MathMax(0.0,InpDirectMinRiskPoints)*point;
   double brokerFloor=MathMax(point*20.0,MarketInfo(Symbol(),MODE_STOPLEVEL)*point*1.5);
   double risk=MathMax(MathMax(atrRisk,pctRisk),MathMax(absoluteRisk,brokerFloor));
   double rr=MathMax(0.1,InpDirectRR);
   if(direction=="BUY")
   {
      if(!_direct_price_ok(sl))
         sl=entry-risk;
      if(!_direct_price_ok(tp))
         tp=entry+risk*rr;
   }
   else if(direction=="SELL")
   {
      if(!_direct_price_ok(sl))
         sl=entry+risk;
      if(!_direct_price_ok(tp))
         tp=entry-risk*rr;
   }
}

int _direct_lot_digits(double step)
{
   if(step>=1.0) return 0;
   if(step>=0.1) return 1;
   if(step>=0.01) return 2;
   return 3;
}

double _direct_normalize_order_lot(double requestedLot)
{
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(step<=0.0) step=0.01;
   if(minLot<=0.0) minLot=step;
   if(maxLot<=0.0) maxLot=100.0;
   double configuredCap=(InpDirectMt4AutoLotMax>0.0)
      ?MathMin(maxLot,MathMax(minLot,InpDirectMt4AutoLotMax))
      :maxLot;
   double capped=MathMin(MathMax(requestedLot,minLot),configuredCap);
   double units=MathFloor((capped/step)+0.0000001);
   double minUnits=MathCeil((minLot/step)-0.0000001);
   // Prefer an even number of broker volume steps so half-close is exactly 50/50.
   if(((int)units%2)!=0 && units-1.0>=MathMax(2.0,minUnits))
      units-=1.0;
   double lot=NormalizeDouble(units*step,_direct_lot_digits(step));
   if(lot<minLot)
      lot=NormalizeDouble(minLot,_direct_lot_digits(step));
   return lot;
}

double _direct_closed_daily_atr(string symbol,int period)
{
   int atrPeriod=MathMax(2,period);
   double atr=iATR(symbol,PERIOD_D1,atrPeriod,1);
   return (MathIsValidNumber(atr) && atr>0.0)?atr:0.0;
}

bool _direct_reference_daily_money(double &targetMoney,double &referenceAtr,string &detail)
{
   string ref=_trim(InpDirectMt4AutoLotReferenceSymbol);
   if(ref=="")
   {
      detail="auto_lot_fallback=empty_reference";
      return false;
   }
   SymbolSelect(ref,true);
   double tickSize=MarketInfo(ref,MODE_TICKSIZE);
   double tickValue=MarketInfo(ref,MODE_TICKVALUE);
   double refLot=MathMax(0.0,InpDirectMt4AutoLotReferenceLot);
   referenceAtr=_direct_closed_daily_atr(ref,InpDirectMt4AutoLotDailyAtrPeriod);
   if(referenceAtr<=0.0 || tickSize<=0.0 || tickValue<=0.0 || refLot<=0.0)
   {
      detail="auto_lot_fallback=invalid_reference_market_data"
         +" ref="+ref
         +" daily_atr="+DoubleToString(referenceAtr,5)
         +" tick_size="+DoubleToString(tickSize,8)
         +" tick_value="+DoubleToString(tickValue,5);
      return false;
   }
   targetMoney=(referenceAtr/tickSize)*tickValue*refLot;
   detail="auto_lot_ref="+ref
      +" ref_lot="+DoubleToString(refLot,2)
      +" atr_d1_period="+IntegerToString(MathMax(2,InpDirectMt4AutoLotDailyAtrPeriod))
      +" ref_daily_atr="+DoubleToString(referenceAtr,5)
      +" target_daily_money="+DoubleToString(targetMoney,2);
   return targetMoney>0.0;
}

double _direct_resolve_order_lot(double entry,double sl,string &detail)
{
   double fallbackLot=_direct_normalize_order_lot(g_directMt4LotRuntime);
   if(!InpDirectMt4AutoLotEnabled)
   {
      detail="auto_lot=off fallback_lot="+DoubleToString(fallbackLot,3);
      return fallbackLot;
   }
   double riskDistance=MathAbs(entry-sl);
   double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double targetMoney=0.0;
   double referenceAtr=0.0;
   string refDetail="";
   double symbolAtr=_direct_closed_daily_atr(Symbol(),InpDirectMt4AutoLotDailyAtrPeriod);
   if(symbolAtr<=0.0 || tickSize<=0.0 || tickValue<=0.0
      || !_direct_reference_daily_money(targetMoney,referenceAtr,refDetail))
   {
      detail="auto_lot=fallback fallback_lot="+DoubleToString(fallbackLot,3)
         +" symbol_daily_atr="+DoubleToString(symbolAtr,Digits)
         +" risk_distance="+DoubleToString(riskDistance,Digits)
         +" tick_size="+DoubleToString(tickSize,8)
         +" tick_value="+DoubleToString(tickValue,5)
         +" "+refDetail;
      return fallbackLot;
   }
   double dailyMoneyPerLot=(symbolAtr/tickSize)*tickValue;
   if(dailyMoneyPerLot<=0.0)
   {
      detail="auto_lot=fallback invalid_daily_money_per_lot fallback_lot="+DoubleToString(fallbackLot,3);
      return fallbackLot;
   }
   double adrLot=targetMoney/dailyMoneyPerLot;
   double slMoneyPerLot=(riskDistance>0.0?(riskDistance/tickSize)*tickValue:0.0);
   double slLimitedLot=(slMoneyPerLot>0.0?targetMoney/slMoneyPerLot:adrLot);
   double rawLot=MathMin(adrLot,slLimitedLot);
   double finalLot=_direct_normalize_order_lot(rawLot);
   detail="auto_lot=on "+refDetail
      +" symbol_daily_atr="+DoubleToString(symbolAtr,Digits)
      +" daily_money_per_lot="+DoubleToString(dailyMoneyPerLot,2)
      +" adr_lot="+DoubleToString(adrLot,4)
      +" risk_distance="+DoubleToString(riskDistance,Digits)
      +" sl_money_per_lot="+DoubleToString(slMoneyPerLot,2)
      +" sl_limited_lot="+DoubleToString(slLimitedLot,4)
      +" raw_lot="+DoubleToString(rawLot,4)
      +" final_lot="+DoubleToString(finalLot,3);
   return finalLot;
}

bool _direct_mt4_execute(string eventId,string direction,double entry,double sl,double tp,string source)
{
   string dir=_trim(direction);
   if(dir!="BUY" && dir!="SELL")
      return false;
   if(eventId==g_lastDirectMt4EventId)
      return true;
   g_lastDirectMt4Ticket=0;
   g_lastDirectMt4Direction=dir;
   RefreshRates();
   double signalPx=(dir=="BUY")?Ask:Bid;
   double auditEntry=_direct_price_ok(entry)?entry:signalPx;
   if(!g_directMt4EnabledRuntime)
   {
      g_lastDirectMt4EventId=eventId;
      _direct_audit_write("direct_signal_received",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,"confirmed_signal",0.0,"direct_disabled_path");
      _direct_audit_write("direct_skip_disabled",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,"direct_off",0.0,"");
      return true;
   }
   if(!_direct_in_allowed_trade_window_gmt())
   {
      g_lastDirectMt4EventId=eventId;
      Print("SIGNATICSBridge direct_mt4 skipped reason=outside_allowed_trade_window event=",eventId," dir=",dir);
      _direct_audit_write("direct_signal_received",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,"confirmed_signal",0.0,"outside_allowed_window_path");
      _direct_audit_write("direct_skip_allowed_window",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,g_directMt4AllowedWindowsRuntime,0.0,"");
      return false;
   }
   if(_direct_in_no_trade_window_gmt())
   {
      g_lastDirectMt4EventId=eventId;
      Print("SIGNATICSBridge direct_mt4 skipped reason=no_trade_window_gmt event=",eventId," dir=",dir);
      _direct_audit_write("direct_signal_received",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,"confirmed_signal",0.0,"no_trade_window_path");
      _direct_audit_write("direct_skip_no_trade_window",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,g_directMt4NoTradeWindowsRuntime,0.0,"");
      return false;
   }
   int spread=(int)MarketInfo(Symbol(),MODE_SPREAD);
   if(g_directMt4MaxSpreadRuntime>0 && spread>g_directMt4MaxSpreadRuntime)
   {
      g_lastDirectMt4EventId=eventId;
      Print("SIGNATICSBridge direct_mt4 skipped reason=spread_too_wide spread=",spread," max=",g_directMt4MaxSpreadRuntime," event=",eventId);
      _direct_audit_write("direct_signal_received",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,"confirmed_signal",0.0,"spread_skip_path");
      _direct_audit_write("direct_skip_spread",source,eventId,0,dir,g_directMt4LotRuntime,auditEntry,sl,tp,"spread="+IntegerToString(spread)+" max="+IntegerToString(g_directMt4MaxSpreadRuntime),0.0,"");
      return false;
   }
   _direct_fill_fallback_levels(dir,entry,sl,tp);
   _direct_close_reverse_positions(dir);
   RefreshRates();
   int type=(dir=="BUY")?OP_BUY:OP_SELL;
   double price=(type==OP_BUY)?Ask:Bid;
   double stopLoss=(_direct_price_ok(sl)?NormalizeDouble(sl,Digits):0.0);
   double takeProfit=(_direct_price_ok(tp)?NormalizeDouble(tp,Digits):0.0);
   string lotDetail="";
   double lot=_direct_resolve_order_lot(price,stopLoss,lotDetail);
   string comment="SIGNATICSBridgeMT4|"+source;
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lot,NormalizeDouble(price,Digits),InpDirectMt4Slippage,stopLoss,takeProfit,comment,InpDirectMt4Magic,0,(type==OP_BUY?clrLime:clrTomato));
   g_lastDirectMt4EventId=eventId;
   if(ticket>0)
   {
      g_lastDirectMt4Ticket=ticket;
      double initialRisk=(stopLoss>0.0?MathAbs(price-stopLoss):0.0);
      if(initialRisk>Point)
         _direct_state_set("IRISK",ticket,initialRisk);
      _direct_state_set("OWNER",ticket,_direct_owner_code());
      double halfTrigger=0.0;
      if(initialRisk>Point && g_directMt4HalfBeRRuntime>0.0)
         halfTrigger=(dir=="BUY")?price+initialRisk*g_directMt4HalfBeRRuntime:price-initialRisk*g_directMt4HalfBeRRuntime;
      if(halfTrigger>0.0)
         _direct_state_set("HTP",ticket,NormalizeDouble(halfTrigger,Digits));
      string lifecycle="initial_risk="+DoubleToString(initialRisk,Digits)
         +" half_trigger="+_fmt_price(halfTrigger)
         +" half_r="+DoubleToString(g_directMt4HalfBeRRuntime,2)
         +" owner="+IntegerToString(_direct_owner_code())
         +" "+lotDetail;
      Print("SIGNATICSBridge direct_mt4 order_sent ticket=",ticket," dir=",dir," lot=",DoubleToString(lot,2)," price=",DoubleToString(price,Digits)," sl=",DoubleToString(stopLoss,Digits)," tp=",DoubleToString(takeProfit,Digits)," event=",eventId);
      _direct_audit_write("direct_signal_received",source,eventId,0,dir,lot,auditEntry,sl,tp,"confirmed_signal",0.0,"written_after_order_send_to_avoid_latency "+lifecycle);
      _direct_audit_write("direct_order_sent",source,eventId,ticket,dir,lot,price,stopLoss,takeProfit,"order_send_ok",0.0,comment+" "+lifecycle);
      bool triggerAtOrBeyondTp=(takeProfit>0.0 && halfTrigger>0.0)
         && ((dir=="BUY" && halfTrigger>=takeProfit-Point) || (dir=="SELL" && halfTrigger<=takeProfit+Point));
      if(triggerAtOrBeyondTp)
         _direct_audit_write("direct_halfbe_config_conflict",source,eventId,ticket,dir,lot,price,stopLoss,takeProfit,"half_trigger_not_before_final_tp",0.0,lifecycle);
      return true;
   }
   int err=GetLastError();
   Print("SIGNATICSBridge direct_mt4 order_failed err=",err," dir=",dir," lot=",DoubleToString(lot,2)," price=",DoubleToString(price,Digits)," sl=",DoubleToString(stopLoss,Digits)," tp=",DoubleToString(takeProfit,Digits)," event=",eventId);
   _direct_audit_write("direct_signal_received",source,eventId,0,dir,lot,auditEntry,sl,tp,"confirmed_signal",0.0,"written_after_order_send_to_avoid_latency");
   _direct_audit_write("direct_order_failed",source,eventId,0,dir,lot,price,stopLoss,takeProfit,"err="+IntegerToString(err),0.0,comment);
   return false;
}

bool _direct_mt4_apply_level_update(string direction,double incomingSl,double incomingTp,string source)
{
   if(!g_directMt4EnabledRuntime)
      return true;

   int wantedType=(direction=="BUY")?OP_BUY:((direction=="SELL")?OP_SELL:-1);
   if(wantedType<0)
      return false;

   int ticket=g_lastDirectMt4Ticket;
   if(ticket<=0 || direction!=g_lastDirectMt4Direction || !OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)
      || OrderCloseTime()>0 || OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic
      || OrderType()!=wantedType || !_direct_order_owned_by_instance(OrderTicket(),OrderComment(),true))
   {
      _direct_audit_write("direct_level_update_no_position",source,"",0,direction,0.0,0.0,incomingSl,incomingTp,
         "no_signal_linked_open_position",0.0,"");
      return true;
   }

   double entry=OrderOpenPrice();
   double currentSl=OrderStopLoss();
   double currentTp=OrderTakeProfit();
   bool progressed=_direct_audit_marked("BE",ticket) || _direct_audit_marked("HALF",ticket);
   double chosenSl=currentSl;
   double chosenTp=currentTp;
   string slPolicy="unchanged";
   string tpPolicy="unchanged";

   bool incomingSlValid=_direct_price_ok(incomingSl)
      && ((wantedType==OP_BUY && incomingSl<entry) || (wantedType==OP_SELL && incomingSl>entry));
   if(!progressed && incomingSlValid)
   {
      double currentDist=_direct_price_ok(currentSl)?MathAbs(entry-currentSl):-1.0;
      double incomingDist=MathAbs(entry-incomingSl);
      if(currentDist<0.0 || incomingDist>currentDist+Point)
      {
         chosenSl=NormalizeDouble(incomingSl,Digits);
         slPolicy="incoming_wider";
      }
      else
         slPolicy="kept_existing_wider";
   }
   else if(progressed && incomingSlValid)
      slPolicy="ignored_after_progress";

   bool incomingTpValid=_direct_price_ok(incomingTp)
      && ((wantedType==OP_BUY && incomingTp>entry) || (wantedType==OP_SELL && incomingTp<entry));
   if(!progressed && incomingTpValid)
   {
      chosenTp=NormalizeDouble(incomingTp,Digits);
      tpPolicy="incoming_applied";
   }
   else if(progressed && incomingTpValid)
      tpPolicy="ignored_after_progress";

   bool slChanged=MathAbs(chosenSl-currentSl)>Point*0.5;
   bool tpChanged=MathAbs(chosenTp-currentTp)>Point*0.5;
   if(!slChanged && !tpChanged)
   {
      _direct_audit_write("direct_level_update_no_change",source,"",ticket,direction,OrderLots(),entry,currentSl,currentTp,
         "sl_policy="+slPolicy+" tp_policy="+tpPolicy,0.0,"");
      return true;
   }

   ResetLastError();
   if(!OrderModify(ticket,entry,chosenSl,chosenTp,0,clrDeepSkyBlue))
   {
      int err=GetLastError();
      _direct_audit_write("direct_level_update_failed",source,"",ticket,direction,OrderLots(),entry,chosenSl,chosenTp,
         "err="+IntegerToString(err)+" sl_policy="+slPolicy+" tp_policy="+tpPolicy,0.0,"");
      Print("SIGNATICSBridge direct level_update failed ticket=",ticket," err=",err);
      return false;
   }

   if(slChanged)
   {
      double risk=MathAbs(entry-chosenSl);
      if(risk>Point)
      {
         _direct_state_set("IRISK",ticket,risk);
         if(g_directMt4HalfBeRRuntime>0.0)
         {
            double trigger=(wantedType==OP_BUY)
               ? entry+risk*g_directMt4HalfBeRRuntime
               : entry-risk*g_directMt4HalfBeRRuntime;
            _direct_state_set("HTP",ticket,NormalizeDouble(trigger,Digits));
         }
      }
   }
   _direct_audit_write("direct_level_update_applied",source,"",ticket,direction,OrderLots(),entry,chosenSl,chosenTp,
      "sl_policy="+slPolicy+" tp_policy="+tpPolicy,0.0,"");
   Print("SIGNATICSBridge direct level_update applied ticket=",ticket,
      " sl=",DoubleToString(chosenSl,Digits)," tp=",DoubleToString(chosenTp,Digits),
      " sl_policy=",slPolicy," tp_policy=",tpPolicy);
   return true;
}

double _dash_clamp(double value,double lo,double hi){ return MathMax(lo,MathMin(hi,value)); }

void _dash_rect(string name,int x,int y,int w,int h,color bg,color border)
{
   string obj=DASH_PREFIX+name;
   if(ObjectFind(0,obj)<0) ObjectCreate(0,obj,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,obj,OBJPROP_BORDER_COLOR,border);
}

void _dash_label(string name,int x,int y,string text,color clr,int size=8)
{
   string obj=DASH_PREFIX+name;
   if(ObjectFind(0,obj)<0) ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
}

void _dash_button(string name,int x,int y,int w,int h,string text,color bg)
{
   string obj=DASH_PREFIX+name;
   if(ObjectFind(0,obj)<0) ObjectCreate(0,obj,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);
   ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,obj,OBJPROP_STATE,false);
}

void _dash_edit(string name,int x,int y,int w,int h,string text)
{
   string obj=DASH_PREFIX+name;
   bool created=false;
   if(ObjectFind(0,obj)<0){ ObjectCreate(0,obj,OBJ_EDIT,0,0,0); created=true; }
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,obj,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,obj,OBJPROP_YSIZE,h);
   if(created) ObjectSetString(0,obj,OBJPROP_TEXT,text);
   ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,C'35,43,58');
   ObjectSetInteger(0,obj,OBJPROP_BORDER_COLOR,C'90,178,255');
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
}

void _dash_progress(string name,int x,int y,int w,int h,double pct,string text,color fill)
{
   pct=_dash_clamp(pct,0.0,100.0);
   _dash_rect(name+"_BG",x,y,w,h,C'35,43,58',C'134,158,182');
   _dash_rect(name+"_FILL",x,y,(int)MathRound(w*pct/100.0),h,fill,fill);
   _dash_label(name+"_TXT",x+8,y+4,text,clrWhite,8);
}

void _delete_dash()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string obj=ObjectName(0,i,-1,-1);
      if(StringFind(obj,DASH_PREFIX)==0) ObjectDelete(0,obj);
   }
}

void _draw_collapsed_dashboard()
{
   _dash_rect("DOCK_BG",10,18,940,34,C'54,62,75',C'134,158,182');
   _dash_rect("DOCK_STRIPE",18,25,924,4,C'90,178,255',C'90,178,255');
   _dash_label("DOCK_TEXT",28,33,"SIGNATICS BRIDGE STARSHIP COCKPIT DOCKED",C'216,222,230',9);
   _dash_button("BTN_DASH_EXPAND",438,58,110,24,"v EXPAND",C'38,101,176');
   _dash_label("DOCK_HINT",560,62,Symbol()+" "+_tf_to_string(Period())+" | chart view clear",C'184,196,210',8);
}

void _set_dashboard_collapsed(bool collapsed)
{
   g_dashboardCollapsed=collapsed;
   _delete_dash();
   if(g_dashboardCollapsed)
      _draw_collapsed_dashboard();
   else
      _draw_dashboard();
   ChartRedraw(0);
}

bool _direct_open_progress(double &pct,string &label,color &fill)
{
   pct=0.0; label="DIRECT MT4 POSITION: none"; fill=C'88,96,112';
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      if(!_direct_order_owned_by_instance(OrderTicket(),OrderComment(),true)) continue;
      double sl=OrderStopLoss(), tp=OrderTakeProfit();
      int dir=OrderType()==OP_BUY?1:-1;
      RefreshRates();
      double px=dir>0?Bid:Ask;
      if(sl<=0.0 || tp<=0.0 || MathAbs(tp-sl)<=0.0) continue;
      pct=(dir>0)?((px-sl)/(tp-sl))*100.0:((sl-px)/(sl-tp))*100.0;
      pct=_dash_clamp(pct,0.0,100.0);
      fill=dir>0?C'31,141,255':C'221,55,78';
      label=StringFormat("%s ticket=%d Px=%s SL=%s TP=%s %.0f%%",(dir>0?"BUY":"SELL"),OrderTicket(),DoubleToString(px,Digits),DoubleToString(sl,Digits),DoubleToString(tp,Digits),pct);
      return true;
   }
   return false;
}

void _manage_direct_mt4_positions()
{
   double halfR=g_directMt4HalfBeRRuntime;
   if(halfR<=0.0)
   {
      _direct_position_probe_scan();
      _direct_history_audit_scan();
      return;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      double entry=OrderOpenPrice(), sl=OrderStopLoss(), tp=OrderTakeProfit();
      if(sl<=0.0 || tp<=0.0) continue;
      int orderType=OrderType();
      int dir=orderType==OP_BUY?1:-1;
      int ticket=OrderTicket();
      if(!_direct_order_owned_by_instance(ticket,OrderComment(),true))
         continue;
      double risk=_direct_state_get("IRISK",ticket);
      if(risk<=Point)
      {
         risk=MathAbs(entry-sl);
         if(risk>Point)
            _direct_state_set("IRISK",ticket,risk);
      }
      if(risk<=Point) continue;
      RefreshRates();
      double px=dir>0?Bid:Ask;
      double triggerPrice=_direct_state_get("HTP",ticket);
      if(triggerPrice<=0.0)
      {
         triggerPrice=(dir>0)?entry+risk*halfR:entry-risk*halfR;
         _direct_state_set("HTP",ticket,NormalizeDouble(triggerPrice,Digits));
      }
      double currentR=(dir>0)?(px-entry)/risk:(entry-px)/risk;
      double maxR=_direct_state_get("MAXR",ticket);
      if(currentR>maxR)
      {
         maxR=currentR;
         _direct_state_set("MAXR",ticket,maxR);
      }
      bool reached=(dir>0)?(px>=triggerPrice):(px<=triggerPrice);
      bool alreadyBe=(dir>0)?(sl>=entry-Point):(sl<=entry+Point);
      if(!reached) continue;
      _direct_state_set("SEEN",ticket,TimeCurrent());
      string direction=(dir>0?"BUY":"SELL");
      string source=OrderComment();
      string thresholdReason="trigger_price="+_fmt_price(triggerPrice)
         +" half_r="+DoubleToString(halfR,2)
         +" initial_risk="+DoubleToString(risk,Digits)
         +" current_r="+DoubleToString(currentR,3)
         +" max_r="+DoubleToString(maxR,3);
      if(!_direct_audit_marked("TP1",ticket))
      {
         _direct_audit_mark("TP1",ticket);
         _direct_audit_write("direct_halfbe_trigger_seen",source,"",ticket,direction,OrderLots(),px,sl,tp,thresholdReason,0.0,"");
      }

      // Move the surviving position to break-even before partial close. MT4
      // brokers may replace the ticket after a partial close.
      if(!alreadyBe)
      {
         ResetLastError();
         if(OrderModify(ticket,entry,NormalizeDouble(entry,Digits),tp,0,clrDodgerBlue))
         {
            _direct_audit_mark("BE",ticket);
            sl=NormalizeDouble(entry,Digits);
            alreadyBe=true;
            _direct_audit_write("direct_sl_to_be_sent",source,"",ticket,direction,OrderLots(),px,sl,tp,thresholdReason,0.0,"before_half_close");
            Print("SIGNATICSBridge direct_mt4 SL moved to BE before half-close ticket=",ticket," halfR=",DoubleToString(halfR,1));
         }
         else
         {
            int beErr=GetLastError();
            if(_direct_failure_log_due("BEFAILLOG",ticket,5))
            {
               _direct_audit_write("direct_sl_to_be_failed",source,"",ticket,direction,OrderLots(),px,sl,tp,"err="+IntegerToString(beErr)+" "+thresholdReason,0.0,"half_close_deferred");
               Print("SIGNATICSBridge direct_mt4 SL->BE failed; half-close deferred ticket=",ticket," err=",beErr);
            }
            continue;
         }
      }
      else if(!_direct_audit_marked("BE",ticket))
      {
         _direct_audit_mark("BE",ticket);
         _direct_audit_write("direct_sl_already_at_be",source,"",ticket,direction,OrderLots(),px,sl,tp,thresholdReason,0.0,"");
      }

      if(!_direct_audit_marked("HALF",ticket))
      {
         double currentLots=OrderLots();
         double minLot=MarketInfo(Symbol(),MODE_MINLOT);
         if(minLot<=0.0)
            minLot=0.01;
         double closeLot=_direct_lot_down(currentLots*0.5);
         if(closeLot>0.0 && currentLots-closeLot>=minLot-0.0000001)
         {
            double closePx=(dir>0)?Bid:Ask;
            double expectedLots=_direct_lot_down(currentLots-closeLot);
            ResetLastError();
            if(OrderClose(ticket,closeLot,closePx,InpDirectMt4Slippage,clrDeepSkyBlue))
            {
               _direct_audit_mark("HALF",ticket);
               _direct_audit_write("direct_half_close_sent",source,"",ticket,direction,closeLot,closePx,sl,tp,thresholdReason,0.0,"be_confirmed_before_half=1");
               int remainderTicket=_direct_find_remainder_ticket(ticket,orderType,entry,source,expectedLots);
               if(remainderTicket>0)
               {
                  _direct_transfer_ticket_state(ticket,remainderTicket);
                  if(remainderTicket!=ticket)
                     _direct_audit_write("direct_partial_remainder_linked",source,"",remainderTicket,direction,expectedLots,closePx,entry,tp,"old_ticket="+IntegerToString(ticket),0.0,"state_transferred");
               }
               else
               {
                  _direct_audit_write("direct_partial_remainder_not_found",source,"",ticket,direction,expectedLots,closePx,entry,tp,thresholdReason,0.0,"verify_terminal_position");
               }
               _direct_audit_write("direct_halfbe_complete",source,"",(remainderTicket>0?remainderTicket:ticket),direction,expectedLots,closePx,entry,tp,thresholdReason,0.0,"be=1 half=1 original_ticket="+IntegerToString(ticket));
            }
            else
            {
               int halfErr=GetLastError();
               if(halfErr==131)
               {
                  double reportedMinLot=MarketInfo(Symbol(),MODE_MINLOT);
                  double reportedLotStep=MarketInfo(Symbol(),MODE_LOTSTEP);
                  _direct_audit_mark("HALF",ticket);
                  _direct_audit_write(
                     "direct_half_close_skipped_invalid_volume",
                     source,"",ticket,direction,closeLot,closePx,sl,tp,
                     "err=131 "+thresholdReason,
                     0.0,
                     "be_already_confirmed=1 current_lots="+DoubleToString(currentLots,2)
                     +" requested_close="+DoubleToString(closeLot,2)
                     +" reported_min_lot="+DoubleToString(reportedMinLot,2)
                     +" reported_lot_step="+DoubleToString(reportedLotStep,2)
                  );
                  Print("SIGNATICSBridge direct_mt4 half_close skipped: broker rejected split volume ticket=",ticket," close_lot=",DoubleToString(closeLot,2));
                  continue;
               }
               if(_direct_failure_log_due("HALFFAILLOG",ticket,5))
               {
                  _direct_audit_write("direct_half_close_failed",source,"",ticket,direction,closeLot,closePx,sl,tp,"err="+IntegerToString(halfErr)+" "+thresholdReason,0.0,"be_already_confirmed=1");
                  Print("SIGNATICSBridge direct_mt4 half_close failed ticket=",ticket," err=",halfErr);
               }
            }
         }
         else
         {
            _direct_audit_mark("HALF",ticket);
            _direct_audit_write("direct_half_close_skipped_min_lot",source,"",ticket,direction,currentLots,px,sl,tp,"min_lot_or_step "+thresholdReason,0.0,"");
         }
      }
   }
   _direct_position_probe_scan();
   _direct_history_audit_scan();
}

void _draw_dashboard()
{
   if(!InpShowDashboard) return;
   if(g_dashboardCollapsed)
   {
      _draw_collapsed_dashboard();
      return;
   }
   _dash_rect("BG",10,18,940,300,C'24,30,42',C'134,158,182');
   _dash_rect("HULL",17,25,926,286,C'40,48,62',C'90,178,255');
   _dash_rect("DOCK_STRIPE",18,31,924,4,C'90,178,255',C'90,178,255');
   _dash_rect("CORE",26,56,640,242,C'18,24,36',C'65,116,172');
   _dash_rect("ACTION_PANEL",676,56,252,242,C'31,38,52',C'221,55,78');
   _dash_button("BTN_DASH_COLLAPSE",904,30,24,22,"^",C'90,178,255');
   _dash_label("TITLE",34,32,"AI STARSHIP SIGNATICS BRIDGE",C'216,222,230',12);
   _dash_label("SUB",380,34,Symbol()+" "+_tf_to_string(Period())+" | "+_bridge_signal_mode()+" | "+SIGNATICS_BRIDGE_BUILD,C'90,178,255',8);
   _dash_label("ACTIONS",696,64,"AIRLOCK / CONFIG",C'216,222,230',9);
   _dash_button("BTN_DIRECT",690,88,118,24,g_directMt4EnabledRuntime?"DIRECT ON":"DIRECT OFF",g_directMt4EnabledRuntime?C'32,150,96':C'178,37,57');
   _dash_button("BTN_POST",816,88,100,24,g_proTradePostEnabledRuntime?"POST ON":"POST OFF",g_proTradePostEnabledRuntime?C'32,150,96':C'178,37,57');
   _dash_button("BTN_PRIORITY",690,116,118,24,g_directMt4PriorityDirectFirst?"DIRECT FIRST":"POST FIRST",C'38,101,176');
   _dash_button("BTN_HALFBE",816,116,100,24,"BE "+DoubleToString(g_directMt4HalfBeRRuntime,1)+"R",C'34,136,160');
   _dash_button("BTN_APPLY",690,144,118,24,"APPLY CFG",C'38,101,176');
   _dash_label("L_LOT",38,66,"Lot",C'184,196,210',8);
   _dash_edit("EDIT_LOT",70,62,70,22,DoubleToString(g_directMt4LotRuntime,2));
   _dash_label("L_SPREAD",158,66,"Max spread pts",C'184,196,210',8);
   _dash_edit("EDIT_SPREAD",260,62,70,22,IntegerToString(g_directMt4MaxSpreadRuntime));
   _dash_label("L_HB",348,66,"BE at R",C'184,196,210',8);
   _dash_edit("EDIT_HALFBE",410,62,54,22,DoubleToString(g_directMt4HalfBeRRuntime,1));
   _dash_label("L_ALLOWED",38,226,"Allowed GMT",C'184,196,210',8);
   _dash_edit("EDIT_ALLOWED",126,222,170,22,g_directMt4AllowedWindowsRuntime);
   _dash_label("L_NOTRADE",318,226,"Block GMT",C'184,196,210',8);
   _dash_edit("EDIT_NOTRADE",390,222,170,22,g_directMt4NoTradeWindowsRuntime);
   int spread=(int)MarketInfo(Symbol(),MODE_SPREAD);
   RefreshRates();
   _dash_label("STATE",38,92,StringFormat("Live BID %s / ASK %s | %s | %s",DoubleToString(Bid,Digits),DoubleToString(Ask,Digits),_direct_spread_status(spread),_direct_trade_window_status()),clrWhite,8);
   _dash_label("LAST_SIG",38,116,"Last SIGNATICS signal: "+(g_lastObservedSignalDirection==""?"NONE":g_lastObservedSignalDirection)+" | "+_fmt_time(g_lastObservedSignalTime)+" | value "+_fmt_price(g_lastObservedSignalValue),C'90,178,255',8);
   _dash_label("MODE_STATE",38,138,StringFormat("Mode %s | ProTrade=%s | Direct=%s | AutoLot=%s (%s %.2f ATR%d)",
      _bridge_signal_mode(),(g_proTradePostEnabledRuntime?"ON":"OFF"),(g_directMt4EnabledRuntime?"ON":"OFF"),
      (InpDirectMt4AutoLotEnabled?"ON":"OFF"),InpDirectMt4AutoLotReferenceSymbol,InpDirectMt4AutoLotReferenceLot,
      InpDirectMt4AutoLotDailyAtrPeriod),C'184,196,210',8);
   double pct; string label; color fill;
   if(_direct_open_progress(pct,label,fill))
      _dash_progress("TRADE",38,184,590,24,pct,label,fill);
   else
      _dash_progress("TRADE",38,184,590,24,0.0,"DIRECT MT4 POSITION: none | dashboard does not mutate signal math",C'88,96,112');
}

void _apply_dashboard()
{
   string obj=DASH_PREFIX+"EDIT_LOT";
   if(ObjectFind(0,obj)>=0) g_directMt4LotRuntime=MathMax(0.01,StrToDouble(ObjectGetString(0,obj,OBJPROP_TEXT)));
   obj=DASH_PREFIX+"EDIT_SPREAD";
   if(ObjectFind(0,obj)>=0) g_directMt4MaxSpreadRuntime=MathMax(0,StrToInteger(ObjectGetString(0,obj,OBJPROP_TEXT)));
   obj=DASH_PREFIX+"EDIT_ALLOWED";
   if(ObjectFind(0,obj)>=0) g_directMt4AllowedWindowsRuntime=_trim(ObjectGetString(0,obj,OBJPROP_TEXT));
   obj=DASH_PREFIX+"EDIT_NOTRADE";
   if(ObjectFind(0,obj)>=0) g_directMt4NoTradeWindowsRuntime=_trim(ObjectGetString(0,obj,OBJPROP_TEXT));
   obj=DASH_PREFIX+"EDIT_HALFBE";
   if(ObjectFind(0,obj)>=0) g_directMt4HalfBeRRuntime=MathMax(0.0,StrToDouble(ObjectGetString(0,obj,OBJPROP_TEXT)));
   Print("SIGNATICSBridge dashboard applied direct=",(g_directMt4EnabledRuntime?"true":"false")," protrade_post=",(g_proTradePostEnabledRuntime?"true":"false")," priority=",(g_directMt4PriorityDirectFirst?"direct_first":"post_first")," lot=",DoubleToString(g_directMt4LotRuntime,2)," max_spread=",g_directMt4MaxSpreadRuntime," allowed_gmt='",g_directMt4AllowedWindowsRuntime,"' block_gmt='",g_directMt4NoTradeWindowsRuntime,"' halfbe_r=",DoubleToString(g_directMt4HalfBeRRuntime,2));
   _draw_dashboard();
   ChartRedraw(0);
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

string _direct_audit_date(datetime t)
{
   return StringFormat("%04d%02d%02d",TimeYear(t),TimeMonth(t),TimeDay(t));
}

string _direct_audit_file_name()
{
   return "SIGNATICSBridge_DirectAudit_"+_direct_audit_date(TimeGMT())+".csv";
}

string _direct_audit_gv_key(string kind,int ticket)
{
   return "SIGNATICSBridgeMT4|"+Symbol()+"|"+IntegerToString(InpDirectMt4Magic)+"|"+kind+"|"+IntegerToString(ticket);
}

bool _direct_audit_marked(string kind,int ticket)
{
   return GlobalVariableCheck(_direct_audit_gv_key(kind,ticket));
}

void _direct_audit_mark(string kind,int ticket)
{
   GlobalVariableSet(_direct_audit_gv_key(kind,ticket),TimeCurrent());
}

double _direct_state_get(string kind,int ticket)
{
   string key=_direct_audit_gv_key(kind,ticket);
   if(!GlobalVariableCheck(key))
      return 0.0;
   return GlobalVariableGet(key);
}

void _direct_state_set(string kind,int ticket,double value)
{
   if(ticket<=0)
      return;
   GlobalVariableSet(_direct_audit_gv_key(kind,ticket),value);
}

void _direct_state_copy(string kind,int fromTicket,int toTicket)
{
   double value=_direct_state_get(kind,fromTicket);
   if(value>0.0)
      _direct_state_set(kind,toTicket,value);
}

bool _direct_failure_log_due(string kind,int ticket,int seconds)
{
   datetime now=TimeCurrent();
   double last=_direct_state_get(kind,ticket);
   if(last>0.0 && now-(datetime)last<MathMax(1,seconds))
      return false;
   _direct_state_set(kind,ticket,now);
   return true;
}

void _direct_audit_write(string eventName,string source,string eventId,int ticket,string direction,double lot,double price,double sl,double tp,string reason,double pnl,string extra)
{
   if(!InpDirectMt4AuditCsv)
      return;
   int h=FileOpen(_direct_audit_file_name(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)
   {
      Print("SIGNATICSBridge direct_mt4 audit open failed err=",GetLastError()," file=",_direct_audit_file_name());
      return;
   }
   bool empty=(FileSize(h)<=0);
   FileSeek(h,0,SEEK_END);
   if(empty)
      FileWrite(h,"ts_gmt","ts_server","ts_local","ms","event","build","indicator","symbol","timeframe","source","event_id","ticket","direction","lot","price","sl","tp","bid","ask","spread","reason","pnl","extra");
   RefreshRates();
   int ms=(int)(GetTickCount()%1000);
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
      IntegerToString(ms),
      eventName,
      SIGNATICS_BRIDGE_BUILD,
      InpIndicatorName,
      Symbol(),
      _tf_to_string(Period()),
      source,
      eventId,
      IntegerToString(ticket),
      direction,
      DoubleToString(lot,2),
      _fmt_price(price),
      _fmt_price(sl),
      _fmt_price(tp),
      _fmt_price(Bid),
      _fmt_price(Ask),
      IntegerToString((int)MarketInfo(Symbol(),MODE_SPREAD)),
      reason,
      DoubleToString(pnl,2),
      extra
   );
   FileClose(h);
}

string _direct_position_probe_file_name()
{
   return "SIGNATICSBridge_PositionProbe_"+_direct_audit_date(TimeGMT())+".csv";
}

void _direct_position_probe_write(
   string eventName,int ticket,string direction,string source,double lots,double entry,double sl,double tp,
   double px,double risk,double finalRr,double currentR,double triggerPrice,bool reached,bool alreadyBe,
   bool halfMarked,bool beMarked,double pnl,string extra
)
{
   if(!InpDirectMt4PositionProbeAudit)
      return;
   int h=FileOpen(_direct_position_probe_file_name(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)
   {
      Print("SIGNATICSBridge position_probe open failed err=",GetLastError()," file=",_direct_position_probe_file_name());
      return;
   }
   bool empty=(FileSize(h)<=0);
   FileSeek(h,0,SEEK_END);
   if(empty)
      FileWrite(h,"ts_gmt","ts_server","ts_local","ms","event","build","indicator","bridge_mode","symbol","timeframe",
         "ticket","direction","source","lots","entry","sl","tp","px","bid","ask","spread","risk","final_rr",
         "current_r","half_trigger","reached_half","already_be","half_marked","be_marked","pnl","extra");
   int ms=(int)(GetTickCount()%1000);
   FileWrite(h,
      TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
      IntegerToString(ms),eventName,SIGNATICS_BRIDGE_BUILD,InpIndicatorName,_bridge_signal_mode(),Symbol(),_tf_to_string(Period()),
      IntegerToString(ticket),direction,source,DoubleToString(lots,2),_fmt_price(entry),_fmt_price(sl),_fmt_price(tp),
      _fmt_price(px),_fmt_price(Bid),_fmt_price(Ask),IntegerToString((int)MarketInfo(Symbol(),MODE_SPREAD)),
      DoubleToString(risk,Digits),DoubleToString(finalRr,3),DoubleToString(currentR,3),_fmt_price(triggerPrice),
      (reached?"1":"0"),(alreadyBe?"1":"0"),(halfMarked?"1":"0"),(beMarked?"1":"0"),DoubleToString(pnl,2),extra);
   FileClose(h);
}

void _direct_position_probe_scan()
{
   if(!InpDirectMt4PositionProbeAudit)
      return;
   int interval=MathMax(1,InpDirectMt4PositionProbeIntervalSeconds);
   datetime now=TimeCurrent();
   if(g_directMt4LastPositionProbe>0 && now-g_directMt4LastPositionProbe<interval)
      return;
   g_directMt4LastPositionProbe=now;
   RefreshRates();
   string hash="";
   int count=0;
   int ownerCode=_direct_owner_code();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic)
         continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         continue;
      int ticket=OrderTicket();
      if(!_direct_order_owned_by_instance(ticket,OrderComment(),true))
         continue;
      int dir=OrderType()==OP_BUY?1:-1;
      string direction=dir>0?"BUY":"SELL";
      double entry=OrderOpenPrice(),sl=OrderStopLoss(),tp=OrderTakeProfit();
      double px=dir>0?Bid:Ask;
      double risk=_direct_state_get("IRISK",ticket);
      if(risk<=Point && sl>0.0)
         risk=MathAbs(entry-sl);
      double finalRr=0.0,currentR=0.0;
      if(risk>Point)
      {
         finalRr=dir>0?(tp-entry)/risk:(entry-tp)/risk;
         currentR=dir>0?(px-entry)/risk:(entry-px)/risk;
      }
      double triggerPrice=_direct_state_get("HTP",ticket);
      if(triggerPrice<=0.0 && risk>Point && g_directMt4HalfBeRRuntime>0.0)
         triggerPrice=dir>0?entry+risk*g_directMt4HalfBeRRuntime:entry-risk*g_directMt4HalfBeRRuntime;
      bool reached=triggerPrice>0.0 && (dir>0?px>=triggerPrice:px<=triggerPrice);
      bool alreadyBe=sl>0.0 && (dir>0?sl>=entry-Point:sl<=entry+Point);
      bool halfMarked=_direct_audit_marked("HALF",ticket);
      bool beMarked=_direct_audit_marked("BE",ticket);
      bool triggerSeen=_direct_state_get("SEEN",ticket)>0.0;
      double maxR=_direct_state_get("MAXR",ticket);
      double pnl=OrderProfit()+OrderSwap()+OrderCommission();
      count++;
      hash+=IntegerToString(ticket)+":"+DoubleToString(OrderLots(),2)+":"+_fmt_price(sl)+":"+DoubleToString(currentR,2)+";";
      _direct_position_probe_write("position_probe",ticket,direction,OrderComment(),OrderLots(),entry,sl,tp,px,risk,finalRr,currentR,
         triggerPrice,reached,alreadyBe,halfMarked,beMarked,pnl,
         "trigger_seen="+(triggerSeen?"1":"0")+" max_r="+DoubleToString(maxR,3)+" owner="+IntegerToString(ownerCode));
   }
   if(count<=0)
   {
      hash="flat";
      if(!InpDirectMt4PositionProbeWriteOnChange || hash!=g_directMt4LastPositionProbeHash)
         _direct_position_probe_write("position_probe_flat",0,"","",0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,false,false,false,false,0.0,"no_managed_positions");
   }
   g_directMt4LastPositionProbeHash=hash;
}

double _direct_lot_down(double lots)
{
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0.0)
      step=0.01;
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   if(minLot<=0.0)
      minLot=0.01;
   double units=MathFloor((lots/step)+0.0000001);
   double out=NormalizeDouble(units*step,2);
   if(out<minLot)
      return 0.0;
   return out;
}

int _direct_find_remainder_ticket(int oldTicket,int orderType,double entry,string source,double expectedLots)
{
   int bestTicket=0;
   double bestScore=1.0e100;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;
      if(OrderTicket()==oldTicket)
         return oldTicket;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic || OrderType()!=orderType)
         continue;
      if(!_direct_order_owned_by_instance(OrderTicket(),OrderComment(),false))
         continue;
      if(source!="" && OrderComment()!=source)
         continue;
      double score=MathAbs(OrderOpenPrice()-entry)+MathAbs(OrderLots()-expectedLots)*MathMax(Point,1.0);
      if(score<bestScore)
      {
         bestScore=score;
         bestTicket=OrderTicket();
      }
   }
   return bestTicket;
}

void _direct_transfer_ticket_state(int oldTicket,int newTicket)
{
   if(oldTicket<=0 || newTicket<=0 || oldTicket==newTicket)
      return;
   _direct_state_copy("IRISK",oldTicket,newTicket);
   _direct_state_copy("HTP",oldTicket,newTicket);
   _direct_state_copy("TP1",oldTicket,newTicket);
   _direct_state_copy("BE",oldTicket,newTicket);
   _direct_state_copy("HALF",oldTicket,newTicket);
   _direct_state_copy("SEEN",oldTicket,newTicket);
   _direct_state_copy("MAXR",oldTicket,newTicket);
   _direct_state_copy("OWNER",oldTicket,newTicket);
}

void _direct_history_cursor_init()
{
   datetime newestTime=0;
   int newestTicket=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic)
         continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         continue;
      datetime ct=OrderCloseTime();
      int tk=OrderTicket();
      if(!_direct_order_owned_by_instance(tk,OrderComment(),false))
         continue;
      if(ct>newestTime || (ct==newestTime && tk>newestTicket))
      {
         newestTime=ct;
         newestTicket=tk;
      }
   }
   g_directMt4LastHistoryAuditTime=newestTime;
   g_directMt4LastHistoryAuditTicket=newestTicket;
}

bool _direct_history_trigger_touched(int orderType,datetime openTime,datetime closeTime,double triggerPrice,double &extremePrice)
{
   extremePrice=0.0;
   if(triggerPrice<=0.0 || openTime<=0 || closeTime<=0)
      return false;
   int openShift=iBarShift(NULL,0,openTime,false);
   int closeShift=iBarShift(NULL,0,closeTime,false);
   if(openShift<0 || closeShift<0)
      return false;
   int start=MathMin(openShift,closeShift);
   int count=MathMin(5000,MathAbs(openShift-closeShift)+1);
   if(count<=0)
      return false;
   if(orderType==OP_BUY)
   {
      int highShift=iHighest(NULL,0,MODE_HIGH,count,start);
      if(highShift<0)
         return false;
      extremePrice=iHigh(NULL,0,highShift);
      return extremePrice>=triggerPrice;
   }
   int lowShift=iLowest(NULL,0,MODE_LOW,count,start);
   if(lowShift<0)
      return false;
   extremePrice=iLow(NULL,0,lowShift);
   return extremePrice<=triggerPrice;
}

void _direct_history_audit_scan()
{
   int interval=MathMax(1,InpDirectMt4HistoryAuditSeconds);
   datetime now=TimeCurrent();
   if(g_directMt4LastHistoryAuditScan>0 && now-g_directMt4LastHistoryAuditScan<interval)
      return;
   g_directMt4LastHistoryAuditScan=now;
   datetime newestTime=g_directMt4LastHistoryAuditTime;
   int newestTicket=g_directMt4LastHistoryAuditTicket;
   int scanned=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && scanned<120;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpDirectMt4Magic)
         continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         continue;
      scanned++;
      datetime ct=OrderCloseTime();
      int tk=OrderTicket();
      if(!_direct_order_owned_by_instance(tk,OrderComment(),false))
         continue;
      if(ct<=0)
         continue;
      if(ct<g_directMt4LastHistoryAuditTime || (ct==g_directMt4LastHistoryAuditTime && tk<=g_directMt4LastHistoryAuditTicket))
         continue;
      string dir=(OrderType()==OP_BUY?"BUY":"SELL");
      double closePx=OrderClosePrice();
      double sl=OrderStopLoss();
      double tp=OrderTakeProfit();
      double tol=MathMax(Point*8.0,MarketInfo(Symbol(),MODE_STOPLEVEL)*Point);
      string eventName="direct_closed";
      if(sl>0.0 && MathAbs(closePx-sl)<=tol)
         eventName="direct_sl_hit";
      else if(tp>0.0 && MathAbs(closePx-tp)<=tol)
         eventName="direct_tp_hit";
      double pnl=OrderProfit()+OrderSwap()+OrderCommission();
      double initialRisk=_direct_state_get("IRISK",tk);
      double triggerPrice=_direct_state_get("HTP",tk);
      double maxR=_direct_state_get("MAXR",tk);
      bool triggerSeen=_direct_state_get("SEEN",tk)>0.0;
      bool halfMarked=_direct_audit_marked("HALF",tk);
      bool beMarked=_direct_audit_marked("BE",tk);
      double barExtreme=0.0;
      bool barTouched=_direct_history_trigger_touched(OrderType(),OrderOpenTime(),ct,triggerPrice,barExtreme);
      string lifecycle="initial_risk="+DoubleToString(initialRisk,Digits)
         +" trigger="+_fmt_price(triggerPrice)
         +" trigger_seen="+(triggerSeen?"1":"0")
         +" bar_touch_estimate="+(barTouched?"1":"0")
         +" bar_extreme="+_fmt_price(barExtreme)
         +" max_r="+DoubleToString(maxR,3)
         +" be_marked="+(beMarked?"1":"0")
         +" half_marked="+(halfMarked?"1":"0");
      _direct_audit_write(eventName,OrderComment(),"",tk,dir,OrderLots(),closePx,sl,tp,"history_close",pnl,lifecycle);
      if((triggerSeen || barTouched) && (!beMarked || !halfMarked))
      {
         string missing=(!beMarked && !halfMarked)?"be_and_half":(!beMarked?"be":"half");
         _direct_audit_write("direct_halfbe_missed_detected",OrderComment(),"",tk,dir,OrderLots(),closePx,sl,tp,"missing="+missing,pnl,lifecycle);
      }
      if(ct>newestTime || (ct==newestTime && tk>newestTicket))
      {
         newestTime=ct;
         newestTicket=tk;
      }
   }
   g_directMt4LastHistoryAuditTime=newestTime;
   g_directMt4LastHistoryAuditTicket=newestTicket;
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

string _bridge_runtime_telemetry_json()
{
   RefreshRates();
   datetime serverTs=_timer_now();
   datetime gmtTs=TimeGMT();
   datetime localTs=TimeLocal();
   double bid=MarketInfo(Symbol(),MODE_BID);
   double ask=MarketInfo(Symbol(),MODE_ASK);
   double point=MarketInfo(Symbol(),MODE_POINT);
   int spread=(int)MarketInfo(Symbol(),MODE_SPREAD);
   return
      "\"mt4_server_time\":\""+_json_escape(TimeToString(serverTs,TIME_DATE|TIME_SECONDS))+"\","
      "\"mt4_server_unix\":"+IntegerToString((int)serverTs)+","
      "\"mt4_gmt_time\":\""+_json_escape(TimeToString(gmtTs,TIME_DATE|TIME_SECONDS))+"\","
      "\"mt4_gmt_unix\":"+IntegerToString((int)gmtTs)+","
      "\"mt4_local_time\":\""+_json_escape(TimeToString(localTs,TIME_DATE|TIME_SECONDS))+"\","
      "\"mt4_local_unix\":"+IntegerToString((int)localTs)+","
      "\"mt4_bid\":"+DoubleToString(bid,Digits)+","
      "\"mt4_ask\":"+DoubleToString(ask,Digits)+","
      "\"mt4_point\":"+DoubleToString(point,Digits+2)+","
      "\"mt4_spread_points\":"+IntegerToString(spread)+",";
}

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

string _fast_buffer_confirm_event_id(string direction,datetime signalTime,double entry,int bufferIndex)
{
   return StringFormat(
      "%s|%s|%s|fastbuf_confirm|%s|%I64d|%d",
      Symbol(),_tf_to_string(Period()),_bridge_signal_mode(),direction,(long)signalTime,bufferIndex
   );
}

bool _fast_confirm_retry_due()
{
   int waitSec=MathMax(1,InpFastSignalRetrySeconds);
   return (g_pendingFastConfirmedLastTry<=0 || (_timer_now()-g_pendingFastConfirmedLastTry)>=waitSec);
}

void _clear_pending_fast_confirm()
{
   g_pendingFastConfirmedEventId="";
   g_pendingFastConfirmedLastTry=0;
   g_pendingFastConfirmedDirection="";
   g_pendingFastConfirmedSignalTime=0;
   g_pendingFastConfirmedEntry=0.0;
   g_pendingFastConfirmedBufferIndex=-1;
   g_pendingFastConfirmedShift=-1;
}

void _store_pending_fast_confirm(string confirmEventId,string direction,datetime signalTime,double entry,int bufferIndex,int shift)
{
   g_pendingFastConfirmedEventId=confirmEventId;
   g_pendingFastConfirmedLastTry=_timer_now();
   g_pendingFastConfirmedDirection=direction;
   g_pendingFastConfirmedSignalTime=signalTime;
   g_pendingFastConfirmedEntry=entry;
   g_pendingFastConfirmedBufferIndex=bufferIndex;
   g_pendingFastConfirmedShift=shift;
}

bool _valid_signal_buffer_value(double value)
{
   if(!MathIsValidNumber(value))
      return false;
   if(value==EMPTY_VALUE || value==2147483647.0 || value<=0.0)
      return false;
   return true;
}

void _capture_signatics_zone(string name,SignaticsZoneSnapshot &snapshot)
{
   snapshot.name=name;
   snapshot.exists=(ObjectFind(0,name)>=0);
   if(!snapshot.exists)
      return;

   snapshot.type=(int)ObjectGetInteger(0,name,OBJPROP_TYPE);
   snapshot.time0=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
   snapshot.time1=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,1);
   snapshot.price0=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
   snapshot.price1=ObjectGetDouble(0,name,OBJPROP_PRICE,1);
   snapshot.colorValue=ObjectGetInteger(0,name,OBJPROP_COLOR);
   snapshot.styleValue=ObjectGetInteger(0,name,OBJPROP_STYLE);
   snapshot.widthValue=ObjectGetInteger(0,name,OBJPROP_WIDTH);
   snapshot.backValue=ObjectGetInteger(0,name,OBJPROP_BACK);
   snapshot.fillValue=ObjectGetInteger(0,name,OBJPROP_FILL);
   snapshot.hiddenValue=ObjectGetInteger(0,name,OBJPROP_HIDDEN);
   snapshot.selectableValue=ObjectGetInteger(0,name,OBJPROP_SELECTABLE);
   snapshot.zorderValue=ObjectGetInteger(0,name,OBJPROP_ZORDER);
}

void _restore_signatics_zone(SignaticsZoneSnapshot &snapshot)
{
   if(!snapshot.exists)
   {
      if(ObjectFind(0,snapshot.name)>=0)
         ObjectDelete(0,snapshot.name);
      return;
   }

   if(ObjectFind(0,snapshot.name)<0)
   {
      if(!ObjectCreate(0,snapshot.name,snapshot.type,0,
         snapshot.time0,snapshot.price0,snapshot.time1,snapshot.price1))
         return;
   }
   else
   {
      ObjectMove(0,snapshot.name,0,snapshot.time0,snapshot.price0);
      ObjectMove(0,snapshot.name,1,snapshot.time1,snapshot.price1);
   }

   ObjectSetInteger(0,snapshot.name,OBJPROP_COLOR,snapshot.colorValue);
   ObjectSetInteger(0,snapshot.name,OBJPROP_STYLE,snapshot.styleValue);
   ObjectSetInteger(0,snapshot.name,OBJPROP_WIDTH,snapshot.widthValue);
   ObjectSetInteger(0,snapshot.name,OBJPROP_BACK,snapshot.backValue);
   ObjectSetInteger(0,snapshot.name,OBJPROP_FILL,snapshot.fillValue);
   ObjectSetInteger(0,snapshot.name,OBJPROP_HIDDEN,snapshot.hiddenValue);
   ObjectSetInteger(0,snapshot.name,OBJPROP_SELECTABLE,snapshot.selectableValue);
   ObjectSetInteger(0,snapshot.name,OBJPROP_ZORDER,snapshot.zorderValue);
}

void _begin_signatics_zone_protection()
{
   if(!InpProtectVisibleSignaticsZones)
      return;
   if(g_zoneProtectionDepth==0)
   {
      _capture_signatics_zone("SA_Zone_Risk",g_zoneProtectionSnapshots[0]);
      _capture_signatics_zone("SA_Zone_TP1",g_zoneProtectionSnapshots[1]);
      _capture_signatics_zone("SA_Zone_TP2",g_zoneProtectionSnapshots[2]);
      _capture_signatics_zone("SA_Zone_TP3",g_zoneProtectionSnapshots[3]);
   }
   g_zoneProtectionDepth++;
}

void _end_signatics_zone_protection()
{
   if(!InpProtectVisibleSignaticsZones || g_zoneProtectionDepth<=0)
      return;
   g_zoneProtectionDepth--;
   if(g_zoneProtectionDepth==0)
   {
      for(int i=0;i<4;i++)
         _restore_signatics_zone(g_zoneProtectionSnapshots[i]);
   }
}

double _signatics_icustom_buffer_value(int bufferIndex,int shift)
{
   if(!InpSyncICustomInputsToChart)
      return iCustom(Symbol(),Period(),InpIndicatorName,bufferIndex,shift);

   bool ownsProtection=(g_zoneProtectionDepth<=0);
   if(ownsProtection)
      _begin_signatics_zone_protection();

   // The visible indicator remains the sole owner of SA_Zone_* objects.
   // Calculation inputs stay synchronized; visual and alert side effects are disabled.
   bool hiddenShowSmcVisuals =
      (InpSuppressHiddenICustomSideEffects ? false : InpSignaticsShowSMCVisuals);
   bool hiddenEnableAlerts =
      (InpSuppressHiddenICustomSideEffects ? false : InpSignaticsEnableAlerts);
   bool hiddenAlertPopup =
      (InpSuppressHiddenICustomSideEffects ? false : InpSignaticsAlertPopup);
   bool hiddenAlertSound =
      (InpSuppressHiddenICustomSideEffects ? false : InpSignaticsAlertSound);
   bool hiddenAlertEmail =
      (InpSuppressHiddenICustomSideEffects ? false : InpSignaticsAlertEmail);
   bool hiddenAlertPush =
      (InpSuppressHiddenICustomSideEffects ? false : InpSignaticsAlertPush);

   double value=iCustom(
      Symbol(),Period(),InpIndicatorName,
      "---- FILTERS --------------------",
      InpSignaticsEnableHTFFilter,
      InpSignaticsRequireBothHTF,
      InpSignaticsConfirmationDelay,
      "---- SMART MONEY CONCEPTS -------",
      InpSignaticsEnableHunt,
      InpSignaticsEnableFVG,
      hiddenShowSmcVisuals,
      InpSignaticsFVGBuyColor,
      InpSignaticsFVGSellColor,
      InpSignaticsHuntBuyColor,
      InpSignaticsHuntSellColor,
      "---- BIAS D1 FILTER -------------",
      InpSignaticsEnableD1Filter,
      "---- ALERTS ---------------------",
      hiddenEnableAlerts,
      hiddenAlertPopup,
      hiddenAlertSound,
      hiddenAlertEmail,
      hiddenAlertPush,
      InpSignaticsSoundFile,
      InpSignaticsAlertCooldown,
      "---- SIGNAL VISUALS -------------",
      InpSignaticsArrowSize,
      InpSignaticsBuyArrowColor,
      InpSignaticsSellArrowColor,
      InpSignaticsArrowDistance,
      InpSignaticsBuyArrowCode,
      InpSignaticsSellArrowCode,
      InpSignaticsShowConfDots,
      InpSignaticsShowSigLabels,
      InpSignaticsSigLabelFS,
      InpSignaticsBuyLabelColor,
      InpSignaticsSellLabelColor,
      "---- MISC -----------------------",
      InpSignaticsRefreshInterval,
      InpSignaticsDeepScanBars,
      bufferIndex,shift
   );

   if(ownsProtection)
      _end_signatics_zone_protection();
   return value;
}

bool _read_signal_buffer(int bufferIndex,int shift,double &value)
{
   ResetLastError();
   value=_signatics_icustom_buffer_value(bufferIndex,shift);
   if(GetLastError()!=0)
      ResetLastError();
   return _valid_signal_buffer_value(value);
}

string _fast_buffer_probe_file_name()
{
   return "SIGNATICSBridge_BufferProbe_"+_direct_audit_date(TimeGMT())+".csv";
}

string _raw_buffer_label(double value)
{
   if(!MathIsValidNumber(value))
      return "nan";
   if(value==EMPTY_VALUE)
      return "EMPTY_VALUE";
   return DoubleToString(value,Digits);
}

bool _read_raw_signal_buffer(int bufferIndex,int shift,double &value,int &err)
{
   ResetLastError();
   value=_signatics_icustom_buffer_value(bufferIndex,shift);
   err=GetLastError();
   if(err!=0)
      ResetLastError();
   return _valid_signal_buffer_value(value);
}

string _fast_buffer_probe_signature()
{
   if(!InpEnableFastBufferProbeAudit || !_fast_buffers_active())
      return "";
   int maxShift=MathMax(0,InpFastBufferProbeMaxShift);
   if(maxShift>20)
      maxShift=20;
   string sig="";
   for(int sh=0; sh<=maxShift; sh++)
   {
      double buyVal=0.0,sellVal=0.0;
      int buyErr=0,sellErr=0;
      bool buyOk=_read_raw_signal_buffer(InpFastBuyBufferIndex,sh,buyVal,buyErr);
      bool sellOk=_read_raw_signal_buffer(InpFastSellBufferIndex,sh,sellVal,sellErr);
      sig=sig+"|"+IntegerToString(sh)+":"+IntegerToString(buyOk?1:0)+":"+_raw_buffer_label(buyVal)+":"+IntegerToString(buyErr)+":"+IntegerToString(sellOk?1:0)+":"+_raw_buffer_label(sellVal)+":"+IntegerToString(sellErr);
   }
   return sig;
}

void _fast_buffer_probe_audit_write(string eventName,string reason)
{
   if(!InpEnableFastBufferProbeAudit || !_fast_buffers_active())
      return;
   int maxShift=MathMax(0,InpFastBufferProbeMaxShift);
   if(maxShift>20)
      maxShift=20;
   int h=FileOpen(_fast_buffer_probe_file_name(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h==INVALID_HANDLE)
   {
      Print("SIGNATICSBridge buffer_probe audit open failed err=",GetLastError()," file=",_fast_buffer_probe_file_name());
      return;
   }
   bool empty=(FileSize(h)<=0);
   FileSeek(h,0,SEEK_END);
   if(empty)
      FileWrite(h,"ts_gmt","ts_server","ts_local","ms","event","reason","build","indicator","symbol","timeframe","buy_buffer","sell_buffer","shift","bar_time","buy_raw","buy_valid","buy_error","sell_raw","sell_valid","sell_error","selected_direction","selected_shift","selected_bar_time","selected_entry","bid","ask","spread");

   RefreshRates();
   string selectedDir="";
   datetime selectedTime=0;
   double selectedEntry=0.0;
   int selectedBuffer=-1,selectedShift=-1;
   _find_latest_fast_buffer_signal(selectedDir,selectedTime,selectedEntry,selectedBuffer,selectedShift);
   int ms=(int)(GetTickCount()%1000);
   for(int sh=0; sh<=maxShift; sh++)
   {
      double buyVal=0.0,sellVal=0.0;
      int buyErr=0,sellErr=0;
      bool buyOk=_read_raw_signal_buffer(InpFastBuyBufferIndex,sh,buyVal,buyErr);
      bool sellOk=_read_raw_signal_buffer(InpFastSellBufferIndex,sh,sellVal,sellErr);
      FileWrite(h,
         TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
         TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
         TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
         IntegerToString(ms),
         eventName,
         reason,
         SIGNATICS_BRIDGE_BUILD,
         InpIndicatorName,
         Symbol(),
         _tf_to_string(Period()),
         IntegerToString(InpFastBuyBufferIndex),
         IntegerToString(InpFastSellBufferIndex),
         IntegerToString(sh),
         _fmt_time(iTime(Symbol(),Period(),sh)),
         _raw_buffer_label(buyVal),
         IntegerToString(buyOk?1:0),
         IntegerToString(buyErr),
         _raw_buffer_label(sellVal),
         IntegerToString(sellOk?1:0),
         IntegerToString(sellErr),
         selectedDir,
         IntegerToString(selectedShift),
         _fmt_time(selectedTime),
         _fmt_price(selectedEntry),
         _fmt_price(Bid),
         _fmt_price(Ask),
         IntegerToString((int)MarketInfo(Symbol(),MODE_SPREAD))
      );
   }
   FileClose(h);
}

void MaybeWriteFastBufferProbeAudit(string reason,bool allowChange)
{
   if(!InpEnableFastBufferProbeAudit || !_fast_buffers_active())
      return;
   datetime now=_timer_now();
   int interval=MathMax(1,InpFastBufferProbeIntervalSeconds);
   if(g_lastFastBufferProbeSnapshot<=0 || now-g_lastFastBufferProbeSnapshot>=interval)
   {
      _fast_buffer_probe_audit_write("snapshot",reason);
      g_lastFastBufferProbeSnapshot=now;
      g_lastFastBufferProbeSignature=_fast_buffer_probe_signature();
      g_lastFastBufferProbeChangeCheck=now;
      return;
   }
   if(!allowChange || !InpFastBufferProbeWriteOnChange)
      return;
   if(g_lastFastBufferProbeChangeCheck>0 && now-g_lastFastBufferProbeChangeCheck<1)
      return;
   g_lastFastBufferProbeChangeCheck=now;
   string sig=_fast_buffer_probe_signature();
   if(g_lastFastBufferProbeSignature=="" || sig!=g_lastFastBufferProbeSignature)
   {
      _fast_buffer_probe_audit_write("change",reason);
      g_lastFastBufferProbeSignature=sig;
   }
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
   _begin_signatics_zone_protection();
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
   _end_signatics_zone_protection();
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

int _fast_signal_max_age_seconds()
{
   if(InpFastSignalMaxAgeSeconds>0)
      return InpFastSignalMaxAgeSeconds;
   int sec=PeriodSeconds();
   if(sec<=0)
      sec=60;
   // Keep every configured live shift eligible while excluding recovery/history.
   return MathMax(sec*(MathMax(0,InpFastSignalLookbackBars)+1),180);
}

bool _fast_signal_age_ok(datetime signalTime)
{
   if(signalTime<=0)
      return false;
   datetime now=TimeCurrent();
   if(now<=0)
      now=TimeLocal();
   int maxAge=_fast_signal_max_age_seconds();
   int age=(int)(now-signalTime);
   if(age<0)
      age=0;
   return (maxAge<=0 || age<=maxAge);
}

bool _find_latest_recoverable_fast_buffer_signal(string reason,string &direction,datetime &signalTime,double &entry,int &bufferIndex,int &shiftOut)
{
   int lookback=MathMax(0,InpFastSignalLookbackBars);
   if(reason!="tick")
      lookback=MathMax(lookback,MathMax(0,InpFastSignalRecoveryLookbackBars));
   return _find_fast_buffer_signal_by_rank(0,lookback,direction,signalTime,entry,bufferIndex,shiftOut);
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

bool _matches_last_fast_signal_setup(string direction,datetime signalTime,double objectEntry)
{
   if(!_matches_last_fast_signal(direction,signalTime))
      return false;
   if(!_direct_price_ok(g_lastFastConfirmedEntry) || !_direct_price_ok(objectEntry))
      return true;

   double atr=iATR(Symbol(),Period(),MathMax(1,InpDirectAtrPeriod),1);
   double tolerance=MathMax(MathAbs(g_lastFastConfirmedEntry)*0.003,atr*3.0);
   tolerance=MathMax(tolerance,Point*50.0);
   return MathAbs(objectEntry-g_lastFastConfirmedEntry)<=tolerance;
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
   if(!g_proTradePostEnabledRuntime || !_register_heartbeat_due())
      return;
   if(_post_signatics_bridge_event("register","",-1,0.0,0.0,0.0,0.0,0.0,"",reason,false))
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
   string eventKind=_trim(eventType);
   if(eventKind=="resolved_state" && !InpSendResolvedStateEvents)
      return true;
   string dir=_trim(direction);
   string endpoint=_build_endpoint(InpApiBaseUrl,InpApiPath);
   string eventId=StringFormat("signatics|%s|%s|%s|%I64d|%s",Symbol(),_tf_to_string(Period()),dir,(long)signalTime,eventKind);
   bool directLevelOk=true;
   if(eventKind=="level_update")
      directLevelOk=_direct_mt4_apply_level_update(dir,sl,tp3>0.0?tp3:tp1,sourceName);
   bool directFirst=(eventKind=="confirmed_signal" && _direct_priority_direct_first());
   if(directFirst)
      _direct_mt4_execute(eventId,dir,entry,sl,tp3>0.0?tp3:tp1,sourceName);
   if(!g_proTradePostEnabledRuntime)
   {
      if(eventKind=="confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId,dir,entry,sl,tp3>0.0?tp3:tp1,sourceName);
      return directLevelOk;
   }
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
   if((eventKind=="confirmed_signal" || eventKind=="resolved_state" || eventKind=="level_update") && (dir=="BUY" || dir=="SELL") && signalTime>0)
   {
      g_lastObservedSignalDirection=dir;
      g_lastObservedSignalTime=signalTime;
      g_lastObservedSignalValue=entry;
   }
   string lastSignalDirection=g_lastObservedSignalDirection;
   datetime lastSignalTime=g_lastObservedSignalTime;
   double lastSignalValue=g_lastObservedSignalValue;
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
      "\"event_ts\":\""+_json_escape(_event_ts_now())+"\","+
      _bridge_runtime_telemetry_json()+
      "\"resolved_signal_bar_time\":\""+_json_escape(_fmt_time(signalTime))+"\","
      "\"resolved_signal_bar_unix\":"+IntegerToString((int)signalTime)+","
      "\"signal_bar_age_sec\":"+IntegerToString(signalBarAgeSec)+","
      "\"confirmed_bar_fresh\":"+(confirmedFresh ? "true" : "false")+","
      "\"max_confirmed_bar_age_sec\":"+IntegerToString(maxConfirmedAgeSec)+","
      "\"last_signal_direction\":\""+_json_escape(lastSignalDirection)+"\","
      "\"last_signal_bar_time\":\""+_json_escape(_fmt_time(lastSignalTime))+"\","
      "\"last_signal_bar_unix\":"+IntegerToString((int)lastSignalTime)+","
      "\"last_signal_value\":"+DoubleToString(lastSignalValue,Digits)+","
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
      if(eventKind=="confirmed_signal" && !directFirst)
         _direct_mt4_execute(eventId,dir,entry,sl,tp3>0.0?tp3:tp1,sourceName);
      return directLevelOk;
   }
   Print("SIGNATICSBridge POST failed code=",code," err=",GetLastError()," event=",eventKind," dir=",dir," endpoint=",endpoint," response=",response);
   if(eventKind=="confirmed_signal" && !directFirst)
      _direct_mt4_execute(eventId,dir,entry,sl,tp3>0.0?tp3:tp1,sourceName);
   return false;
}

bool _is_initial_audit_reason(string reason)
{
   return (reason=="init" || reason=="init_retry" || reason=="baseline");
}

bool RetryPendingFastBufferConfirm(string reason)
{
   if(g_pendingFastConfirmedEventId=="" || !_fast_confirm_retry_due())
      return false;
   if(g_pendingFastConfirmedDirection!="BUY" && g_pendingFastConfirmedDirection!="SELL")
      return false;
   if(g_pendingFastConfirmedSignalTime<=0 || !_valid_signal_buffer_value(g_pendingFastConfirmedEntry))
      return false;

   string sourceName=StringFormat("SIGNATICS_BUFFER_%d_shift_%d_retry",g_pendingFastConfirmedBufferIndex,g_pendingFastConfirmedShift);
   _print_setup_line(
      "trade_signal_retry_fast_buffer",
      reason,
      g_pendingFastConfirmedDirection,
      g_pendingFastConfirmedSignalTime,
      g_pendingFastConfirmedEntry,
      0.0,
      0.0,
      0.0,
      0.0,
      sourceName
   );
   g_pendingFastConfirmedLastTry=_timer_now();
   bool confirmedOk=_post_signatics_bridge_event(
      "confirmed_signal",
      g_pendingFastConfirmedDirection,
      g_pendingFastConfirmedSignalTime,
      g_pendingFastConfirmedEntry,
      0.0,
      0.0,
      0.0,
      0.0,
      sourceName,
      reason,
      false
   );
   if(!confirmedOk)
   {
      if(InpLogFastBufferSignals)
      {
         PrintFormat(
            "SIGNATICSBridge confirmed_signal_retry_still_pending reason=%s confirm_id='%s' symbol=%s tf=%s dir=%s bar=%s entry=%s retry_sec=%d",
            reason,
            g_pendingFastConfirmedEventId,
            Symbol(),
            _tf_to_string(Period()),
            g_pendingFastConfirmedDirection,
            _fmt_time(g_pendingFastConfirmedSignalTime),
            _fmt_price(g_pendingFastConfirmedEntry),
            MathMax(1,InpFastSignalRetrySeconds)
         );
      }
      return true;
   }

   g_lastFastConfirmedEventId=g_pendingFastConfirmedEventId;
   g_lastFastConfirmedDirection=g_pendingFastConfirmedDirection;
   g_lastFastConfirmedSignalTime=g_pendingFastConfirmedSignalTime;
   g_lastFastConfirmedEntry=g_pendingFastConfirmedEntry;
   _clear_pending_fast_confirm();
   g_baselineSetupSeen=true;
   return true;
}

bool ScanFastBufferSignal(string reason)
{
   if(!_fast_buffers_active())
      return false;

   string direction;
   datetime signalTime;
   double entry;
   int bufferIndex,shift;
   // Confirmed trade execution must be driven only by the currently-live buffer
   // window. Wider recovery/history scans are for resolved-state/audit only;
   // otherwise an old M15 shift_7 signal can open a trade more than an hour late.
   if(!_find_latest_fast_buffer_signal(direction,signalTime,entry,bufferIndex,shift))
      return RetryPendingFastBufferConfirm(reason);

   if(!_fast_signal_age_ok(signalTime))
   {
      if(InpLogFastBufferSignals)
      {
         int age=(int)(TimeCurrent()-signalTime);
         if(age<0) age=0;
         PrintFormat(
            "SIGNATICSBridge fast_buffer_signal stale_skip reason=%s symbol=%s tf=%s dir=%s bar=%s entry=%s buffer=%d shift=%d age_sec=%d max_age_sec=%d",
            reason,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),bufferIndex,shift,age,_fast_signal_max_age_seconds()
         );
      }
      return RetryPendingFastBufferConfirm(reason);
   }

   string eventId=_fast_buffer_event_id(direction,signalTime,entry,bufferIndex,shift);
   string confirmEventId=_fast_buffer_confirm_event_id(direction,signalTime,entry,bufferIndex);
   if(confirmEventId==g_lastFastConfirmedEventId)
      return true;
   if(confirmEventId==g_pendingFastConfirmedEventId && !_fast_confirm_retry_due())
      return true;

   bool initialAudit=_is_initial_audit_reason(reason);
   string sourceName=StringFormat("SIGNATICS_BUFFER_%d_shift_%d",bufferIndex,shift);
   bool firstSeen=(eventId!=g_lastFastBufferEventId);
   if(InpLogFastBufferSignals && firstSeen)
   {
      PrintFormat(
         "SIGNATICSBridge fast_buffer_signal reason=%s event_id='%s' symbol=%s tf=%s dir=%s bar=%s entry=%s buffer=%d shift=%d initial=%s",
         reason,eventId,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),bufferIndex,shift,(initialAudit ? "true" : "false")
      );
   }
   g_lastFastBufferEventId=eventId;

   if(_post_signatics_bridge_event("resolved_state",direction,signalTime,entry,0.0,0.0,0.0,0.0,sourceName,reason,false))
      g_lastResolvedPostTime=_timer_now();

   if(initialAudit && !InpSendInitialConfirmedOnStart)
   {
      g_lastFastConfirmedEventId=confirmEventId;
      g_lastFastConfirmedDirection=direction;
      g_lastFastConfirmedSignalTime=signalTime;
      g_lastFastConfirmedEntry=entry;
      _clear_pending_fast_confirm();
      g_baselineSetupSeen=true;
      return true;
   }

   _print_setup_line("trade_signal_sent_fast_buffer",reason,direction,signalTime,entry,0.0,0.0,0.0,0.0,sourceName);
   _store_pending_fast_confirm(confirmEventId,direction,signalTime,entry,bufferIndex,shift);
   bool confirmedOk=_post_signatics_bridge_event("confirmed_signal",direction,signalTime,entry,0.0,0.0,0.0,0.0,sourceName,reason,false);
   if(!confirmedOk)
   {
      if(InpLogFastBufferSignals)
      {
         PrintFormat(
            "SIGNATICSBridge confirmed_signal_retry_pending reason=%s confirm_id='%s' symbol=%s tf=%s dir=%s bar=%s entry=%s retry_sec=%d",
            reason,confirmEventId,Symbol(),_tf_to_string(Period()),direction,_fmt_time(signalTime),_fmt_price(entry),MathMax(1,InpFastSignalRetrySeconds)
         );
      }
      g_baselineSetupSeen=true;
      return true;
   }
   g_lastFastConfirmedEventId=confirmEventId;
   _clear_pending_fast_confirm();
   g_lastFastConfirmedDirection=direction;
   g_lastFastConfirmedSignalTime=signalTime;
   g_lastFastConfirmedEntry=entry;
   g_baselineSetupSeen=true;
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
   }

   if(!fastFound && _fast_buffers_active() && (initialReason || !g_baselineSetupSeen))
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
            "SIGNATICSBridge buffer_history NONE reason=%s symbol=%s tf=%s live_lookback=%d history_lookback=%d object_scan=enrichment_only",
            reason,Symbol(),_tf_to_string(Period()),MathMax(0,InpFastSignalLookbackBars),MathMax(0,InpFastSignalHistoryLookbackBars)
         );
      }
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
      if(_fast_buffers_active() && _matches_last_fast_signal_setup(direction,signalTime,entry))
      {
         PrintFormat(
            "SIGNATICSBridge object_enrichment_only reason=%s event_id='%s' matched_fast_dir=%s fast_bar=%s object_bar=%s source='%s'",
            reason,eventId,direction,_fmt_time(g_lastFastConfirmedSignalTime),_fmt_time(signalTime),sourceName
         );
         bool enrichmentOk=_post_signatics_bridge_event("level_update",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason,true);
         if(!enrichmentOk)
         {
            g_lastEventId="";
            return false;
         }
         g_lastConfirmedEventId=eventId;
         g_baselineSetupSeen=true;
         return true;
      }
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
      if(_matches_last_fast_signal_setup(direction,signalTime,entry))
      {
         PrintFormat(
            "SIGNATICSBridge object_enrichment_only reason=%s event_id='%s' matched_fast_dir=%s fast_bar=%s object_bar=%s source='%s'",
            reason,eventId,direction,_fmt_time(g_lastFastConfirmedSignalTime),_fmt_time(signalTime),sourceName
         );
         bool enrichmentOk=_post_signatics_bridge_event("level_update",direction,signalTime,entry,sl,tp1,tp2,tp3,sourceName,reason,true);
         if(!enrichmentOk)
         {
            g_lastEventId="";
            return false;
         }
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
   g_directMt4EnabledRuntime=InpDirectMt4ExecutionEnabled;
   g_proTradePostEnabledRuntime=InpEnableProTradePost;
   string priority=_lower_copy(_trim(InpDirectMt4Priority));
   g_directMt4PriorityDirectFirst=(priority!="post_first" && priority!="quantdesk_first");
   g_directMt4LotRuntime=MathMax(0.01,InpDirectMt4Lot);
   g_directMt4MaxSpreadRuntime=MathMax(0,InpDirectMt4MaxSpreadPoints);
   g_directMt4HalfBeRRuntime=MathMax(0.0,InpDirectMt4HalfBeR);
   g_directMt4AllowedWindowsRuntime=_trim(InpDirectMt4AllowedTradeWindowsGmt);
   g_directMt4NoTradeWindowsRuntime=_trim(InpDirectMt4NoTradeWindowsGmt);
   _direct_history_cursor_init();
   Print("SIGNATICSBridge BUILD=",SIGNATICS_BRIDGE_BUILD," indicator=",InpIndicatorName," instanceIndicator=",_bridge_indicator_label()," mode=",_bridge_signal_mode()," symbol=",Symbol()," tf=",_tf_to_string(Period())," poll=",poll," light=",InpLogOnlyTradeSignals," resolved=",InpSendResolvedStateEvents," groupPrimary=",InpPreferGroupedSetup," lvFallback=",InpAllowLevelObjectFallback," fastBuffers=",_fast_buffers_active()," fastLookback=",InpFastSignalLookbackBars," fastMaxAge=",InpFastSignalMaxAgeSeconds," recoveryLookback=",InpFastSignalRecoveryLookbackBars," retrySec=",InpFastSignalRetrySeconds," historyLookback=",InpFastSignalHistoryLookbackBars," tickScan=",InpScanFastBuffersOnTick," probe=",InpEnableFastBufferProbeAudit," probeSec=",InpFastBufferProbeIntervalSeconds," probeShift=",InpFastBufferProbeMaxShift," strictGroups=",InpChartObjectStrictGroups," requireAllTps=",InpChartObjectRequireAllTps," objectStableSec=",InpChartObjectStableSeconds," autoLot=",InpDirectMt4AutoLotEnabled," autoLotRef=",InpDirectMt4AutoLotReferenceSymbol," autoLotRefLot=",DoubleToString(InpDirectMt4AutoLotReferenceLot,2)," autoLotDailyAtrPeriod=",InpDirectMt4AutoLotDailyAtrPeriod," autoLotMax=",DoubleToString(InpDirectMt4AutoLotMax,2));
   Print("SIGNATICSBridge iCustom_sync=",InpSyncICustomInputsToChart,
      " isolateHiddenSmcObjects=",InpSuppressHiddenICustomSideEffects,
      " protectVisibleZones=",InpProtectVisibleSignaticsZones,
      " htf=",InpSignaticsEnableHTFFilter,
      " bothHtf=",InpSignaticsRequireBothHTF,
      " confirmDelay=",InpSignaticsConfirmationDelay,
      " hunt=",InpSignaticsEnableHunt,
      " fvg=",InpSignaticsEnableFVG,
      " d1=",InpSignaticsEnableD1Filter,
      " refresh=",InpSignaticsRefreshInterval,
      " deepScan=",InpSignaticsDeepScanBars);
   if(g_proTradePostEnabledRuntime)
   {
      if(_post_signatics_bridge_event("register","",-1,0.0,0.0,0.0,0.0,0.0,"","init",false))
         g_lastRegisterPostTime=_timer_now();
   }
   g_initialSetupRetryUntil=_timer_now()+MathMax(0,InpInitialSetupRetrySeconds);
   if(InpLogOnInit)
      ScanAndLogLatest("init");
   MaybeWriteFastBufferProbeAudit("init",false);
   _draw_dashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpSendUnregisterOnDeinit && g_proTradePostEnabledRuntime)
      _post_signatics_bridge_event("unregister","",-1,0.0,0.0,0.0,0.0,0.0,"","deinit_"+IntegerToString(reason),false);
   if(!InpLogOnlyTradeSignals)
      Print("SIGNATICSBridge uninit reason=",reason);
   _delete_dash();
}

void OnTimer()
{
   _manage_direct_mt4_positions();
   MaybeWriteFastBufferProbeAudit("timer",true);
   MaybePostRegisterHeartbeat("heartbeat");
   if(InpLogOnInit && !g_baselineSetupSeen && _timer_now()<=g_initialSetupRetryUntil)
   {
      ScanAndLogLatest("init_retry");
      return;
   }
   ScanAndLogLatest("timer");
   _draw_dashboard();
}
void OnTick()
{
   _manage_direct_mt4_positions();
   if(_fast_buffers_active() && InpScanFastBuffersOnTick)
      ScanFastBufferSignal("tick");
   MaybeWriteFastBufferProbeAudit("tick",true);
   _draw_dashboard();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK && id!=CHARTEVENT_OBJECT_ENDEDIT)
      return;
   if(id==CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(StringFind(sparam,DASH_PREFIX+"EDIT_")==0)
         _apply_dashboard();
      return;
   }
   uint clickNow=GetTickCount();
   if(sparam==g_lastDashClickObject && clickNow-g_lastDashClickMs<800)
      return;
   g_lastDashClickObject=sparam;
   g_lastDashClickMs=clickNow;
   if(ObjectFind(0,sparam)>=0)
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   if(sparam==DASH_PREFIX+"BTN_DASH_COLLAPSE")
      _set_dashboard_collapsed(true);
   else if(sparam==DASH_PREFIX+"BTN_DASH_EXPAND")
      _set_dashboard_collapsed(false);
   else if(sparam==DASH_PREFIX+"BTN_DIRECT")
   {
      g_directMt4EnabledRuntime=!g_directMt4EnabledRuntime;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam==DASH_PREFIX+"BTN_POST")
   {
      if(g_proTradePostEnabledRuntime)
      {
         _post_signatics_bridge_event("unregister","",-1,0.0,0.0,0.0,0.0,0.0,"","dashboard_post_off",false);
         g_proTradePostEnabledRuntime=false;
         g_lastPostDisabledMs=clickNow;
         Print("SIGNATICSBridge dashboard ProTrade POST disabled");
      }
      else
      {
         if(g_lastPostDisabledMs>0 && clickNow-g_lastPostDisabledMs<10000)
         {
            Print("SIGNATICSBridge dashboard ProTrade POST enable ignored reason=recent_disable_guard");
            _draw_dashboard();
            ChartRedraw(0);
            return;
         }
         g_proTradePostEnabledRuntime=true;
         _post_signatics_bridge_event("register","",-1,0.0,0.0,0.0,0.0,0.0,"","dashboard_post_on",false);
         g_lastRegisterPostTime=_timer_now();
         Print("SIGNATICSBridge dashboard ProTrade POST enabled");
      }
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam==DASH_PREFIX+"BTN_PRIORITY")
   {
      g_directMt4PriorityDirectFirst=!g_directMt4PriorityDirectFirst;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam==DASH_PREFIX+"BTN_HALFBE")
   {
      if(g_directMt4HalfBeRRuntime<=0.0)
         g_directMt4HalfBeRRuntime=1.0;
      else if(g_directMt4HalfBeRRuntime<2.0)
         g_directMt4HalfBeRRuntime=2.0;
      else if(g_directMt4HalfBeRRuntime<3.0)
         g_directMt4HalfBeRRuntime=3.0;
      else
         g_directMt4HalfBeRRuntime=0.0;
      _draw_dashboard();
      ChartRedraw(0);
   }
   else if(sparam==DASH_PREFIX+"BTN_APPLY")
      _apply_dashboard();
}
