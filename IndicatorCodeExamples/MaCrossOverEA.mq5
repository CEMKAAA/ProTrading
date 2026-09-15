// MA crossover system derived from MaCrossOver.pine, yigdeli, MPL-2.0.
// Reuses the existing ORB/Liq regime engine; no ML and no preloaded strategies.
#property strict
#property version "1.00"
#include <Trade/Trade.mqh>
#include "MaCrossOver_Core.mqh"
#include "MaCrossOver_Replay.mqh"
#include "LiqNarrativeSol_RegimeV3.mqh"
#include "LiqNarrativeMacroRegime.mqh"
input group "MA Crossover / Safe startup"
input bool InpAllowNativeTrading=false;
input long InpMagic=150925701;
input double InpRiskPercent=.3;
input double InpFixedRiskCapital=0; // 0=current balance, otherwise fixed reference capital
input double InpPipSizeOverride=0;
input double InpBrokerGmtOffsetHours=0; // Broker historical clock; adjust for its DST policy
input int InpMaxSpreadPoints=0;
input int InpSlippagePoints=20;
input double InpRoundTurnNotionalFeePct=0; // Explicit assumed fee, not read from broker
input int InpAuditYears=5;
input int InpMaxDrawTrades=150;
input bool InpDrawRejectedSignals=true;
input group "MA initial values (dashboard overrides)"
input int InpFastEma=9;
input int InpMediumEma=27;
input int InpSlowHma=200;
input ENUM_TIMEFRAMES InpHigherTimeframe=PERIOD_H4;
input int InpHtfHma=200;

CTrade g_trade;
MaConfig g_cfg;
MaSeries g_ma;
MqlRates g_rates[],g_higher[],g_minutes[];
double g_hma[];
MaTrade g_results[],g_active;
int g_dirs[],g_buckets[];
string g_rejects[];
bool g_enabled=false,g_ready=false,g_loading=true,g_auditBusy=false,g_hasActive=false,g_popup=false,g_favOnly=false;
int g_cursor=0,g_eventCursor=0,g_weeks=2,g_page=0,g_drawCursor=0;
datetime g_armedAfter=0,g_dataBar=0,g_signalBar=0,g_from=0,g_asof=0,g_retry=0;
string g_status="Loading closed-bar history",g_prefix="",g_configKey="",g_activeName="CUSTOM",g_query="";
ulong g_started=0,g_lastUi=0;
double g_progress=0,g_lease=0;
string g_leaseKey="";
bool g_coverage=false;
string g_names[],g_files[];
bool g_favorites[];
int g_visible[];

double MaPip(){return InpPipSizeOverride>0?InpPipSizeOverride:(_Digits==3||_Digits==5?_Point*10:_Point);}
string MaHash(string value)
{
   uchar data[],key[],result[];int n=StringToCharArray(value,data,0,WHOLE_ARRAY,CP_UTF8);if(n>0)ArrayResize(data,n-1);
   if(CryptEncode(CRYPT_HASH_SHA256,data,key,result)<=0)return "";
   string out="";for(int i=0;i<ArraySize(result);i++)out+=StringFormat("%02x",result[i]);return out;
}
string MaOwner(){return AccountInfoString(ACCOUNT_SERVER)+"|"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+_Symbol+"|"+(string)InpMagic;}
bool MaOwnPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t&&PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==InpMagic)return true;}return false;
}
bool MaForeignPosition()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)return false;
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t&&PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)!=InpMagic)return true;}return false;
}
bool MaTradeOk(){uint c=g_trade.ResultRetcode();return c==TRADE_RETCODE_DONE||c==TRADE_RETCODE_DONE_PARTIAL;}
string MaStateKey(ulong ticket){return "MACS."+StringSubstr(MaHash(MaOwner()+"|"+(string)ticket),0,32);}
bool MaWrite(string path,string text)
{
   string tmp=path+"."+(string)ChartID()+".tmp";int h=FileOpen(tmp,FILE_WRITE|FILE_BIN|FILE_COMMON);if(h==INVALID_HANDLE)return false;
   uchar b[];int n=StringToCharArray(text,b,0,WHOLE_ARRAY,CP_UTF8)-1;bool ok=n>=0&&FileWriteArray(h,b,0,n)==(uint)n;
   FileFlush(h);FileClose(h);return ok&&FileMove(tmp,FILE_COMMON,path,FILE_COMMON|FILE_REWRITE);
}
bool MaRead(string path,string &text)
{
   int h=FileOpen(path,FILE_READ|FILE_BIN|FILE_COMMON|FILE_SHARE_READ);if(h==INVALID_HANDLE)return false;
   long size=(long)FileSize(h);if(size<0||size>65536){FileClose(h);return false;}
   uchar b[];ArrayResize(b,(int)size);uint n=FileReadArray(h,b,0,(int)size);FileClose(h);
   if(n!=(uint)size)return false;text=CharArrayToString(b,0,(int)size,CP_UTF8);return true;
}
void MaInvalidate()
{
   g_ready=false;g_auditBusy=false;g_loading=true;g_retry=0;g_configKey="";g_progress=0;
   g_armedAfter=TimeCurrent();g_dataBar=0;g_signalBar=0;
   ObjectsDeleteAll(0,g_prefix+"H_");g_status="Settings applied; rebuilding audit";
}
bool MaCanEdit()
{
   if(g_enabled||MaOwnPosition()){g_status="Turn EA OFF and wait for its position to close before changing strategy";return false;}return true;
}
void MaLoadLibrary()
{
   ArrayFree(g_names);ArrayFree(g_files);ArrayFree(g_favorites);string file;
   long f=FileFindFirst("MaCrossOverStrategies\\*.strategy",file,FILE_COMMON);
   if(f!=INVALID_HANDLE){do{string body,a[];if(!MaRead("MaCrossOverStrategies\\"+file,body)||StringSplit(body,'\n',a)!=7)continue;
      string payload="";for(int j=0;j<5;j++)payload+=a[j]+"\n";
      MaConfig c;if(a[0]!="MACROSS1"||MaHash(payload)!=a[5]||!MaUnpack(a[4],c))continue;
      if(a[2]!=_Symbol||StringToInteger(a[3])!=(int)_Period)continue;
      int i=ArraySize(g_names);ArrayResize(g_names,i+1);ArrayResize(g_files,i+1);ArrayResize(g_favorites,i+1);
      g_names[i]=a[1];g_files[i]=file;g_favorites[i]=FileIsExist("MaCrossOverStrategies\\"+file+".fav",FILE_COMMON);
   }while(FileFindNext(f,file));FileFindClose(f);}
}
bool MaSaveStrategy(string name)
{
   if(!MaCanEdit())return false;StringTrimLeft(name);StringTrimRight(name);
   if(name==""||StringLen(name)>80||StringFind(name,"\n")>=0||StringFind(name,"\r")>=0){g_status="Use a 1-80 character single-line name";return false;}
   string id=MaHash(_Symbol+"|"+(string)_Period+"|"+name),path="MaCrossOverStrategies\\"+id+".strategy";
   if(FileIsExist(path,FILE_COMMON)){g_status="Name already exists; choose a new name";return false;}
   string body="MACROSS1\n"+name+"\n"+_Symbol+"\n"+(string)(int)_Period+"\n"+MaPack(g_cfg)+"\n";
   int lock=FileOpen("MaCrossOverStrategies\\save.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lock==INVALID_HANDLE){g_status="Another instance is saving; retry";return false;}
   bool ok=!FileIsExist(path,FILE_COMMON)&&MaWrite(path,body+MaHash(body)+"\n");FileClose(lock);
   if(ok){g_activeName=name;MaLoadLibrary();g_status="Saved "+name;}else g_status="Save failed; no existing strategy overwritten";return ok;
}
bool MaApplyStrategy(int i)
{
   if(!MaCanEdit()||i<0||i>=ArraySize(g_files))return false;string text,a[];
   if(!MaRead("MaCrossOverStrategies\\"+g_files[i],text)||StringSplit(text,'\n',a)!=7)return false;
   string payload="";for(int j=0;j<5;j++)payload+=a[j]+"\n";MaConfig c;
   if(a[0]!="MACROSS1"||a[2]!=_Symbol||StringToInteger(a[3])!=(int)_Period||MaHash(payload)!=a[5]||!MaUnpack(a[4],c))
   {g_status="Strategy checksum / symbol / TF mismatch";return false;}
   g_cfg=c;g_activeName=a[1];g_popup=false;MaInvalidate();ObjectsDeleteAll(0,g_prefix+"UI_");return true;
}
void MaPrepareSignals()
{
   MaCalculate(g_rates,g_cfg,g_ma);double close[];ArrayResize(close,ArraySize(g_higher));
   for(int i=0;i<ArraySize(close);i++)close[i]=g_higher[i].close;MaHma(close,g_cfg.htfLen,g_hma);
   int n=ArraySize(g_rates);ArrayResize(g_dirs,n);ArrayResize(g_buckets,n);ArrayResize(g_rejects,n);
   RegimeV3EnsureTimeline(false);
   for(int i=0;i<n;i++)
   {
      g_dirs[i]=0;g_buckets[i]=-1;g_rejects[i]="";if(g_rates[i].time+PeriodSeconds(_Period)>g_asof)continue;
      int d=0;string reason;if(!MaFilter(g_rates,i,g_ma,g_cfg,g_higher,g_hma,PeriodSeconds(_Period),(int)MathRound(InpBrokerGmtOffsetHours*60),d,reason))
      {g_rejects[i]=reason;continue;}
      RegimeV3Snapshot snapshot;int bucket=LiqMacroRegimeBucketAt(g_rates[i].time+PeriodSeconds(_Period),snapshot);g_buckets[i]=bucket;
      if(bucket<0&&g_cfg.mask!=63){g_rejects[i]="REGIME DATA";continue;}
      if(bucket>=0&&!(g_cfg.mask&(1<<bucket))){g_rejects[i]="REGIME "+LiqMacroRegimeShortName(bucket);continue;}
      g_dirs[i]=d;
   }
}
bool MaLoadData()
{
   int sec=PeriodSeconds(_Period);g_asof=iTime(_Symbol,PERIOD_M1,0);if(g_asof<=0)return false;
   datetime wanted=g_asof-(long)InpAuditYears*365*86400;
   int warm=MathMax(2048,MathMax(g_cfg.fast,MathMax(g_cfg.medium,g_cfg.slow))*8);
   int n=CopyRates(_Symbol,_Period,wanted-(long)warm*sec,g_asof,g_rates);
   int h=CopyRates(_Symbol,(ENUM_TIMEFRAMES)g_cfg.htf,wanted-(long)(g_cfg.htfLen+100)*PeriodSeconds((ENUM_TIMEFRAMES)g_cfg.htf),g_asof,g_higher);
   int m=CopyRates(_Symbol,PERIOD_M1,wanted,g_asof-1,g_minutes);
   if(n<warm||m<10||(g_cfg.htfOn&&h<g_cfg.htfLen+20)){g_status="Waiting for broker history; missing data is not a loss";return false;}
   g_from=wanted;g_coverage=g_rates[0].time<=wanted&&g_minutes[0].time<=wanted+7*86400;
   g_status="Calculating causal MA/ADX/RSI features";g_progress=5;MaDraw();ChartRedraw(0);MaPrepareSignals();
   ArrayFree(g_results);g_hasActive=false;g_cursor=0;g_eventCursor=0;
   while(g_eventCursor<n&&g_rates[g_eventCursor].time+sec<g_minutes[0].time)g_eventCursor++;
   g_auditBusy=true;g_loading=false;g_ready=false;g_started=GetTickCount64();g_progress=15;
   g_dataBar=g_asof;g_signalBar=iTime(_Symbol,_Period,0);return true;
}
void MaRecord()
{
   int n=ArraySize(g_results);ArrayResize(g_results,n+1,256);g_results[n]=g_active;g_hasActive=false;
}
void MaAuditStep()
{
   if(!g_auditBusy)return;ulong start=GetTickCount64();int n=ArraySize(g_minutes),sec=PeriodSeconds(_Period);
   while(g_cursor<n&&GetTickCount64()-start<25)
   {
      MqlRates q=g_minutes[g_cursor];
      if(g_hasActive&&g_cursor>0&&q.time!=g_minutes[g_cursor-1].time+60)
      {g_active.data=true;g_active.done=true;g_active.reason="DATA: missing M1 interval";g_active.exitAt=q.time;MaRecord();}
      if(g_hasActive&&q.spread<=0){g_active.data=true;g_active.done=true;g_active.reason="DATA: unknown spread";g_active.exitAt=q.time;MaRecord();}
      if(g_hasActive&&MaAtOpen(g_active,q.open,q.spread*_Point,q.time,InpRoundTurnNotionalFeePct,g_cfg))MaRecord();
      while(g_eventCursor<ArraySize(g_rates)&&g_rates[g_eventCursor].time+sec<=q.time)
      {
         int i=g_eventCursor++,d=g_dirs[i];datetime at=g_rates[i].time+sec;
         if(d==0||at!=q.time||at<g_from)continue;
         if(g_hasActive&&g_active.direction!=d){MaFinish(g_active,q.open+(g_active.direction<0?q.spread*_Point:0),q.time,"REVERSE",InpRoundTurnNotionalFeePct);MaRecord();}
         if(g_hasActive)continue;
         if(q.spread<=0){MaTrade t;ZeroMemory(t);t.signal=g_rates[i].time;t.at=q.time;t.exitAt=q.time;t.data=true;t.done=true;t.reason="DATA: entry spread";
            int x=ArraySize(g_results);ArrayResize(g_results,x+1,256);g_results[x]=t;continue;}
         if(InpMaxSpreadPoints>0&&q.spread>InpMaxSpreadPoints)continue;
         if(MaStartTrade(g_active,g_rates[i].time,q.time,d,g_buckets[i],q.open+(d>0?q.spread*_Point:0),g_ma.atr[i],MaPip(),g_cfg))g_hasActive=true;
      }
      if(g_hasActive)
      {
         MaWithinBar(g_active,q,_Point,InpRoundTurnNotionalFeePct);
         if(g_active.done)MaRecord();
         else {int i=MaLastClosed(g_rates,q.time+60,sec);if(i>=0&&g_rates[i].time+sec==q.time+60)
            MaAtClose(g_active,q.close,q.spread*_Point,g_ma.atr[i],g_cfg);}
      }
      g_cursor++;
      g_progress=15+80.0*g_cursor/MathMax(1,n);
   }
   if(g_cursor>=n)
   {
      g_auditBusy=false;g_ready=true;g_progress=100;g_configKey=MaPack(g_cfg);g_drawCursor=0;
      g_status=string(g_coverage?"READY":"PARTIAL broker history")+" | "+DoubleToString((GetTickCount64()-g_started)/1000.0,2)+"s replay; windows now use cached trades";
      MaDrawHistory();
   }
}
void MaNativeManage()
{
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(!ticket||PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
      string key=MaStateKey(ticket);
      if(GlobalVariableCheck(key+".bad")){g_trade.PositionClose(ticket);g_status="Retry closing unverified protection/risk";continue;}
      if(!GlobalVariableCheck(key+".risk")){g_status="Owned position has no recovery state; existing broker protection retained";g_enabled=false;continue;}
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),risk=GlobalVariableGet(key+".risk"),volume=PositionGetDouble(POSITION_VOLUME);
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double px=dir>0?tick.bid:tick.ask,r=dir*(px-entry)/risk;
      double initial=GlobalVariableGet(key+".vol"),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      if(volume<initial-step*.5)GlobalVariableSet(key+".partial",1);
      if(g_cfg.management>=2&&r>=g_cfg.partialR&&!GlobalVariableCheck(key+".partial"))
      {
         double cut=MathFloor(initial*g_cfg.partialPct/100/step)*step;
         if(cut>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)&&volume-cut>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN))
         {if(g_trade.PositionClosePartial(ticket,cut)&&MaTradeOk())GlobalVariableSet(key+".partial",1);}
         else GlobalVariableSet(key+".partial",1); // Quantity too small; never close the whole position as a partial.
      }
      if(g_cfg.management>=1&&(r>=g_cfg.beR||GlobalVariableCheck(key+".be")))
      {
         GlobalVariableSet(key+".be",1);double stop=entry;
         int k=MaLastClosed(g_rates,TimeCurrent(),PeriodSeconds(_Period));
         if(g_cfg.management==3&&k>=0&&MaValid(g_ma.atr[k]))stop=dir>0?MathMax(entry,tick.bid-g_ma.atr[k]*g_cfg.trailMult):MathMin(entry,tick.ask+g_ma.atr[k]*g_cfg.trailMult);
         double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(tickSize<=0)tickSize=_Point;
         stop=NormalizeDouble(MathRound(stop/tickSize)*tickSize,_Digits);
         double old=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
         if((old==0||dir*(stop-old)>tickSize*.5)&&dir*(px-stop)>SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point)
            g_trade.PositionModify(ticket,stop,tp); // Failed BE changes are retried on a subsequent tick.
      }
   }
}
void MaNativeSignal(int i)
{
   if(!g_enabled||!g_ready||i<0||g_rates[i].time+PeriodSeconds(_Period)<=g_armedAfter)return;
   int d=g_dirs[i];if(d==0)return;MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;
   if(TimeCurrent()-tick.time>10||MaForeignPosition()){g_status="Native entry blocked: stale quote / foreign net position";return;}
   // Consume once, never re-open a stale signal after a rejected order or restart.
   g_armedAfter=g_rates[i].time+PeriodSeconds(_Period);
   for(int p=PositionsTotal()-1;p>=0;p--){ulong t=PositionGetTicket(p);if(!t||PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(dir==d)return;if(!g_trade.PositionClose(t)||!MaTradeOk()){g_status="Reverse close failed: no new entry";return;}}
   if(MaOwnPosition())return;
   if(InpMaxSpreadPoints>0&&(tick.ask-tick.bid)/_Point>InpMaxSpreadPoints){g_status="Entry blocked: spread";return;}
   MaTrade t;if(!MaStartTrade(t,g_rates[i].time,TimeCurrent(),d,g_buckets[i],d>0?tick.ask:tick.bid,g_ma.atr[i],MaPip(),g_cfg))return;
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(ts<=0)ts=_Point;
   t.stop=NormalizeDouble(MathRound(t.stop/ts)*ts,_Digits);t.target=NormalizeDouble(MathRound(t.target/ts)*ts,_Digits);
   double loss=0;ENUM_ORDER_TYPE type=d>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,1,t.entry,t.stop,loss)||loss>=0){g_status="Risk calculation failed";return;}
   double capital=InpFixedRiskCapital>0?InpFixedRiskCapital:AccountInfoDouble(ACCOUNT_BALANCE),budget=capital*InpRiskPercent/100;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(step<=0||budget<=0)return;
   double vol=MathFloor(MathMin(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),budget/(-loss))/step)*step;
   if(vol<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)){g_status="Minimum volume exceeds risk budget";return;}
   double margin=0;if(!OrderCalcMargin(type,_Symbol,vol,t.entry,margin)||margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)){g_status="Insufficient margin";return;}
   bool sent=d>0?g_trade.Buy(vol,_Symbol,0,t.stop,t.target,"MaCrossOver"):g_trade.Sell(vol,_Symbol,0,t.stop,t.target,"MaCrossOver");
   if(!sent||!MaTradeOk()){g_status="Order rejected: "+g_trade.ResultRetcodeDescription();return;}
   for(int p=PositionsTotal()-1;p>=0;p--){ulong ticket=PositionGetTicket(p);if(!ticket||PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;
      double fill=PositionGetDouble(POSITION_PRICE_OPEN),actual=0,sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      string key=MaStateKey(ticket);GlobalVariableSet(key+".risk",MathAbs(fill-t.stop));GlobalVariableSet(key+".vol",PositionGetDouble(POSITION_VOLUME));
      if(sl<=0||tp<=0||MathAbs(sl-t.stop)>ts*.5||MathAbs(tp-t.target)>ts*.5||!OrderCalcProfit(type,_Symbol,PositionGetDouble(POSITION_VOLUME),fill,sl,actual)||actual>=0||-actual>budget+MathMax(.01,budget*.001))
      {GlobalVariableSet(key+".bad",1);GlobalVariablesFlush();g_trade.PositionClose(ticket);g_status="Post-fill protection/risk guard closing position";}
      else g_status="Native trade opened with verified SL/TP";
   }GlobalVariablesFlush();
}
#include "MaCrossOver_UI.mqh"
int OnInit()
{
   MaDefaults(g_cfg);g_cfg.fast=InpFastEma;g_cfg.medium=InpMediumEma;g_cfg.slow=InpSlowHma;g_cfg.htf=InpHigherTimeframe;g_cfg.htfLen=InpHtfHma;
   if(!MaConfigValid(g_cfg)||InpRiskPercent<=0||InpRiskPercent>100||InpMagic<=0||InpFixedRiskCapital<0||InpAuditYears<1||InpAuditYears>5
      ||InpRoundTurnNotionalFeePct<0||InpPipSizeOverride<0||InpMaxSpreadPoints<0)return INIT_PARAMETERS_INCORRECT;
   if(InpAllowNativeTrading&&AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {Print("MaCrossOver native execution currently requires a hedging account.");return INIT_PARAMETERS_INCORRECT;}
   g_prefix="MAC_"+(string)ChartID()+"_";g_armedAfter=TimeCurrent();
   g_leaseKey="MACLEASE."+StringSubstr(MaHash(MaOwner()),0,28);
   if(InpAllowNativeTrading)
   {
      if(!GlobalVariableCheck(g_leaseKey))GlobalVariableTemp(g_leaseKey);
      double old=GlobalVariableGet(g_leaseKey);g_lease=(double)TimeLocal()+60;
      if(old>TimeLocal()||!GlobalVariableSetOnCondition(g_leaseKey,g_lease,old)){Print("Account/symbol/magic already owned by another MA instance.");return INIT_FAILED;}
   }
   g_trade.SetExpertMagicNumber(InpMagic);g_trade.SetDeviationInPoints(InpSlippagePoints);g_trade.SetTypeFillingBySymbol(_Symbol);
   FolderCreate("MaCrossOverStrategies",FILE_COMMON);MaLoadLibrary();LiqMacroRegimeInit();
   for(int j=0;j<6;j++)if(!g_macroRegimeAllowed[j])g_cfg.mask&=~(1<<j);
   EventSetMillisecondTimer(100);MaDraw();return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();ObjectsDeleteAll(0,g_prefix);
   if(g_lease>0)GlobalVariableSetOnCondition(g_leaseKey,0,g_lease);
}
void OnTick(){MaNativeManage();}
void OnTimer()
{
   if(g_lease>0){double next=(double)TimeLocal()+60;if(!GlobalVariableSetOnCondition(g_leaseKey,next,g_lease)){g_enabled=false;g_status="Ownership lease lost; native entries disabled";}else g_lease=next;}
   if(g_loading&&TimeLocal()>=g_retry){g_retry=TimeLocal()+5;MaLoadData();}
   MaAuditStep();MaNativeManage();
   if(g_ready&&!g_auditBusy&&!g_loading&&iTime(_Symbol,PERIOD_M1,0)>g_dataBar)
   {
      g_asof=iTime(_Symbol,PERIOD_M1,0);MqlRates tail[];int count=CopyRates(_Symbol,PERIOD_M1,g_dataBar,g_asof-1,tail);
      if(count>0){int n=ArraySize(g_minutes);ArrayResize(g_minutes,n+count);ArrayCopy(g_minutes,tail,n,0,count);g_dataBar=g_asof;g_auditBusy=true;g_started=GetTickCount64();}
      datetime signalBar=iTime(_Symbol,_Period,0);
      if(signalBar!=g_signalBar)
      {
         int warm=MathMax(2048,MathMax(g_cfg.fast,MathMax(g_cfg.medium,g_cfg.slow))*8);
         CopyRates(_Symbol,_Period,g_from-(long)warm*PeriodSeconds(_Period),g_asof,g_rates);
         CopyRates(_Symbol,(ENUM_TIMEFRAMES)g_cfg.htf,g_from-(long)(g_cfg.htfLen+100)*PeriodSeconds((ENUM_TIMEFRAMES)g_cfg.htf),g_asof,g_higher);
         MaPrepareSignals();g_signalBar=signalBar;
         int i=MaLastClosed(g_rates,g_asof,PeriodSeconds(_Period));MaNativeSignal(i);
      }
   }
   if(GetTickCount64()-g_lastUi>=250){MaDraw();g_lastUi=GetTickCount64();ChartRedraw(0);}
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam){MaUiEvent(id,sparam);}
