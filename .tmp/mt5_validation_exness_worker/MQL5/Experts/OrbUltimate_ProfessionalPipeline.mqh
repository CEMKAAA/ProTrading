#ifndef ORB_ULTIMATE_PROFESSIONAL_PIPELINE_MQH
#define ORB_ULTIMATE_PROFESSIONAL_PIPELINE_MQH

struct OrbBridgePendingEvent
{
   string eventId;
   string dir;
   double entry;
   double sl;
   double tp;
   string source;
   double halfTrigger;
   string halfLabel;
   datetime signalTime;
   datetime nextRetryLocal;
   int attempts;
};

bool   g_orbBridgeEnabled=false;
bool   g_orbBridgeOnly=false;
bool   g_orbNativeWithBridgeOnly=false;
string g_orbBridgeStatus="BRIDGE OFF";
OrbBridgePendingEvent g_orbBridgePending[];

string OrbProTime(datetime value){return TimeToString(value,TIME_DATE|TIME_SECONDS);}
string OrbProDate(datetime value){MqlDateTime d;TimeToStruct(value,d);return StringFormat("%04d%02d%02d",d.year,d.mon,d.day);}
string OrbProSafeToken(string value)
{
   StringReplace(value,"/","_");StringReplace(value,":","_");StringReplace(value,"*","_");
   StringReplace(value,"?","_");StringReplace(value,"<","_");StringReplace(value,">","_");
   StringReplace(value,"|","_");StringReplace(value," ","_");
   return value;
}
string OrbProTf(ENUM_TIMEFRAMES tf)
{
   int seconds=PeriodSeconds(tf);
   if(seconds>0)return IntegerToString(seconds/60);
   return EnumToString(tf);
}
int OrbProBridgeFlags(int flags){return InpFileBridgeUseCommonFiles?(flags|FILE_COMMON):flags;}
int OrbProCommonFlag(){return InpFileBridgeUseCommonFiles?FILE_COMMON:0;}
string OrbProScopedLatestFile(){return "OrbUltimateBridge_Latest_"+OrbProSafeToken(_Symbol)+"_"+OrbProTf(g_rtSignalTf)+".csv";}
string OrbProOutboxFile(){return "OrbUltimateBridge_Outbox_"+OrbProSafeToken(_Symbol)+"_"+OrbProTf(g_rtSignalTf)+".csv";}
string OrbProBridgeSource(){return "OrbUltimate|"+RuntimeEntryLabel()+"|"+RuntimeTargetModeLabel()+"|"+RuntimeSlModeLabel();}
string OrbProTempFile(string fileName,int attempt){return fileName+".tmp."+StringFormat("%I64d",ChartID())+"."+IntegerToString((int)GetTickCount())+"."+IntegerToString(attempt);}

void OrbProBridgeHeader(int handle)
{
   FileWrite(handle,"version","written_gmt","source_login","symbol","tf","event_id","source","dir",
      "signal_time","bridge_entry","sl","tp","half_trigger","half_label","source_build","source_bid","source_ask","risk_pct");
}
void OrbProBridgeRow(int handle,string eventId,string dir,double entry,double sl,double tp,string source,
                     double halfTrigger,string halfLabel,datetime signalTime)
{
   MqlTick tick;ZeroMemory(tick);SymbolInfoTick(_Symbol,tick);
   FileWrite(handle,"1",OrbProTime(TimeGMT()),StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN)),_Symbol,
      OrbProTf(g_rtSignalTf),eventId,source,dir,OrbProTime(signalTime),DoubleToString(entry,_Digits),
      DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),DoubleToString(halfTrigger,_Digits),halfLabel,
      ORB15_BUILD,DoubleToString(tick.bid,_Digits),DoubleToString(tick.ask,_Digits),DoubleToString(MathMax(0.0,InpRiskPerTradePct),4));
}
bool OrbProPromoteTemp(string tempName,string fileName)
{
   int common=OrbProCommonFlag();ResetLastError();
   if(FileMove(tempName,common,fileName,common|FILE_REWRITE))return true;
   int err=GetLastError();FileDelete(tempName,common);
   Print("OrbUltimate atomic latest promote failed err=",err," temp=",tempName," file=",fileName);
   return false;
}
bool OrbProWriteLatest(string fileName,string eventId,string dir,double entry,double sl,double tp,string source,
                       double halfTrigger,string halfLabel,datetime signalTime)
{
   int flags=OrbProBridgeFlags(FILE_CSV|FILE_WRITE|FILE_ANSI);
   for(int attempt=0;attempt<3;attempt++)
   {
      string temp=OrbProTempFile(fileName,attempt);FileDelete(temp,OrbProCommonFlag());ResetLastError();
      int handle=FileOpen(temp,flags,',');
      if(handle!=INVALID_HANDLE)
      {
         OrbProBridgeHeader(handle);OrbProBridgeRow(handle,eventId,dir,entry,sl,tp,source,halfTrigger,halfLabel,signalTime);
         FileFlush(handle);FileClose(handle);
         if(OrbProPromoteTemp(temp,fileName))return true;
      }
      else Print("OrbUltimate atomic latest temp open failed err=",GetLastError()," temp=",temp);
      FileDelete(temp,OrbProCommonFlag());
      if(attempt<2)Sleep(20);
   }
   return false;
}
bool OrbProPersistPending()
{
   string fileName=OrbProOutboxFile(),temp=OrbProTempFile(fileName,0);
   FileDelete(temp,OrbProCommonFlag());
   int handle=FileOpen(temp,OrbProBridgeFlags(FILE_CSV|FILE_WRITE|FILE_ANSI),',');
   if(handle==INVALID_HANDLE)return false;
   for(int i=0;i<ArraySize(g_orbBridgePending);i++)
      FileWrite(handle,g_orbBridgePending[i].eventId,g_orbBridgePending[i].dir,
         DoubleToString(g_orbBridgePending[i].entry,_Digits),DoubleToString(g_orbBridgePending[i].sl,_Digits),
         DoubleToString(g_orbBridgePending[i].tp,_Digits),g_orbBridgePending[i].source,
         DoubleToString(g_orbBridgePending[i].halfTrigger,_Digits),g_orbBridgePending[i].halfLabel,
         StringFormat("%I64d",g_orbBridgePending[i].signalTime),IntegerToString(g_orbBridgePending[i].attempts));
   FileFlush(handle);FileClose(handle);
   return OrbProPromoteTemp(temp,fileName);
}
void OrbProLoadPending()
{
   ArrayResize(g_orbBridgePending,0);
   int handle=FileOpen(OrbProOutboxFile(),OrbProBridgeFlags(FILE_CSV|FILE_READ|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI),',');
   if(handle==INVALID_HANDLE)return;
   while(!FileIsEnding(handle)&&ArraySize(g_orbBridgePending)<128)
   {
      OrbBridgePendingEvent item;
      item.eventId=FileReadString(handle);if(item.eventId==""&&FileIsEnding(handle))break;
      item.dir=FileReadString(handle);item.entry=StringToDouble(FileReadString(handle));item.sl=StringToDouble(FileReadString(handle));
      item.tp=StringToDouble(FileReadString(handle));item.source=FileReadString(handle);item.halfTrigger=StringToDouble(FileReadString(handle));
      item.halfLabel=FileReadString(handle);item.signalTime=(datetime)StringToInteger(FileReadString(handle));
      item.attempts=(int)StringToInteger(FileReadString(handle));item.nextRetryLocal=0;
      if(item.eventId=="")continue;
      int n=ArraySize(g_orbBridgePending);ArrayResize(g_orbBridgePending,n+1);g_orbBridgePending[n]=item;
   }
   FileClose(handle);
}
bool OrbProQueuePending(string eventId,string dir,double entry,double sl,double tp,string source,double halfTrigger,string halfLabel,datetime signalTime)
{
   int index=-1,n=ArraySize(g_orbBridgePending);
   for(int i=0;i<n;i++)if(g_orbBridgePending[i].eventId==eventId){index=i;break;}
   if(index<0)
   {
      if(n>=128)return false;
      ArrayResize(g_orbBridgePending,n+1);index=n;g_orbBridgePending[index].attempts=0;
   }
   g_orbBridgePending[index].eventId=eventId;g_orbBridgePending[index].dir=dir;g_orbBridgePending[index].entry=entry;
   g_orbBridgePending[index].sl=sl;g_orbBridgePending[index].tp=tp;g_orbBridgePending[index].source=source;
   g_orbBridgePending[index].halfTrigger=halfTrigger;g_orbBridgePending[index].halfLabel=halfLabel;
   g_orbBridgePending[index].signalTime=signalTime;g_orbBridgePending[index].nextRetryLocal=TimeLocal()+2;
   return OrbProPersistPending();
}
void OrbProRemovePending(int index)
{
   int n=ArraySize(g_orbBridgePending);if(index<0||index>=n)return;
   for(int i=index;i<n-1;i++)g_orbBridgePending[i]=g_orbBridgePending[i+1];
   ArrayResize(g_orbBridgePending,n-1);
}
void OrbProRetryPending()
{
   if(!g_orbBridgeEnabled||IsTesterMode()||ArraySize(g_orbBridgePending)<=0)return;
   if(g_orbBridgePending[0].nextRetryLocal>TimeLocal())return;
   OrbBridgePendingEvent item=g_orbBridgePending[0];
   if(!OrbProWriteLatest(OrbProScopedLatestFile(),item.eventId,item.dir,item.entry,item.sl,item.tp,item.source,item.halfTrigger,item.halfLabel,item.signalTime))
   {
      g_orbBridgePending[0].attempts++;g_orbBridgePending[0].nextRetryLocal=TimeLocal()+MathMin(30,2+g_orbBridgePending[0].attempts*2);
      OrbProPersistPending();return;
   }
   OrbProRemovePending(0);OrbProPersistPending();
}
bool OrbProWriteInitMarker()
{
   if(!g_orbBridgeEnabled||IsTesterMode())return false;
   string eventId="orb_bridge_init|"+_Symbol+"|"+OrbProTf(g_rtSignalTf)+"|"+OrbProTime(TimeGMT());
   bool genericOk=OrbProWriteLatest(InpFileBridgeLatestFile,eventId,"INIT",0,0,0,"bridge_initiated",0,"init",TimeGMT());
   bool scopedOk=OrbProWriteLatest(OrbProScopedLatestFile(),eventId,"INIT",0,0,0,"bridge_initiated",0,"init",TimeGMT());
   g_orbBridgeStatus=scopedOk?"INIT WROTE":"INIT FAIL";
   if(!genericOk)Print("OrbUltimate generic init marker failed file=",InpFileBridgeLatestFile);
   return scopedOk;
}
bool OrbProPublishSignal(string dir,datetime signalTime,double entry,double sl,double tp,double halfTrigger,string halfLabel,string detail)
{
   if(!g_orbBridgeEnabled||IsTesterMode())return false;
   string eventId="ORB|"+_Symbol+"|"+OrbProTf(g_rtSignalTf)+"|"+dir+"|"+StringFormat("%I64d",signalTime);
   string source=OrbProBridgeSource();
   bool genericOk=OrbProWriteLatest(InpFileBridgeLatestFile,eventId,dir,entry,sl,tp,source,halfTrigger,halfLabel,signalTime);
   bool scopedOk=OrbProWriteLatest(OrbProScopedLatestFile(),eventId,dir,entry,sl,tp,source,halfTrigger,halfLabel,signalTime);
   bool accepted=scopedOk||OrbProQueuePending(eventId,dir,entry,sl,tp,source,halfTrigger,halfLabel,signalTime);
   int handle=FileOpen(InpFileBridgeAuditPrefix+OrbProDate(TimeGMT())+".csv",OrbProBridgeFlags(FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI),',');
   if(handle!=INVALID_HANDLE)
   {
      bool header=FileSize(handle)<=0;FileSeek(handle,0,SEEK_END);if(header)OrbProBridgeHeader(handle);
      OrbProBridgeRow(handle,eventId,dir,entry,sl,tp,source,halfTrigger,halfLabel,signalTime);FileClose(handle);
   }
   g_orbBridgeStatus=scopedOk?("WROTE "+dir):(accepted?("QUEUED "+dir):("PUBLISH FAIL "+dir));
   Audit(accepted?"bridge_published":"bridge_publish_failed",dir,0,entry,sl,tp,
      "event="+eventId+" scoped="+(scopedOk?"1":"0")+" generic="+(genericOk?"1":"0")+" half="+DoubleToString(halfTrigger,_Digits)+" "+detail);
   return accepted;
}

bool OrbProPublishCloseOnly(int dir,string reason)
{
   if(!g_orbBridgeEnabled||IsTesterMode()||dir==0)return false;
   datetime signalTime=TimeCurrent();
   string direction=dir>0?"BUY":"SELL";
   string safeReason=OrbProSafeToken(reason);
   string eventId="ORB|"+_Symbol+"|"+OrbProTf(g_rtSignalTf)+"|"+direction+"|invalidate_close|"+StringFormat("%I64d",signalTime)+"|"+safeReason;
   string source="OrbUltimate|CloseOnly|"+reason;
   MqlTick tick;ZeroMemory(tick);SymbolInfoTick(_Symbol,tick);
   double entry=g_tradeEntry>0?g_tradeEntry:(dir>0?tick.bid:tick.ask);
   bool genericOk=OrbProWriteLatest(InpFileBridgeLatestFile,eventId,direction,entry,0,0,source,0,"OFF",signalTime);
   bool scopedOk=OrbProWriteLatest(OrbProScopedLatestFile(),eventId,direction,entry,0,0,source,0,"OFF",signalTime);
   bool accepted=scopedOk||OrbProQueuePending(eventId,direction,entry,0,0,source,0,"OFF",signalTime);
   int handle=FileOpen(InpFileBridgeAuditPrefix+OrbProDate(TimeGMT())+".csv",OrbProBridgeFlags(FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI),',');
   if(handle!=INVALID_HANDLE)
   {
      bool header=FileSize(handle)<=0;FileSeek(handle,0,SEEK_END);if(header)OrbProBridgeHeader(handle);
      OrbProBridgeRow(handle,eventId,direction,entry,0,0,source,0,"OFF",signalTime);FileClose(handle);
   }
   g_orbBridgeStatus=scopedOk?("CLOSE "+direction):(accepted?("CLOSE QUEUED "+direction):("CLOSE FAIL "+direction));
   Audit(accepted?"bridge_close_published":"bridge_close_failed",direction,0,entry,0,0,
      "event="+eventId+" scoped="+(scopedOk?"1":"0")+" generic="+(genericOk?"1":"0")+" reason="+reason);
   return accepted;
}
string OrbProPlanKey(ulong positionId,string field)
{
   return "OP."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."+StringFormat("%I64u",positionId)+"."+field;
}
void OrbProSet(ulong positionId,string field,double value){if(positionId>0)GlobalVariableSet(OrbProPlanKey(positionId,field),value);}
double OrbProGet(ulong positionId,string field,double fallback=0.0)
{
   if(positionId<=0)return fallback;string key=OrbProPlanKey(positionId,field);
   return GlobalVariableCheck(key)?GlobalVariableGet(key):fallback;
}
bool OrbProHas(ulong positionId){return positionId>0&&GlobalVariableCheck(OrbProPlanKey(positionId,"entry"));}
void OrbProDelete(ulong positionId)
{
   string fields[]={"entry","sl","tp","half","dir","openTs","signalTs","regime","pipMode","pipValue","targetLeg","hcLeg",
      "mfePips","maePips","mfeMoney","maeMoney","mfePx","maePx","mfeTs","maeTs","halfDone","beDone"};
   for(int i=0;i<ArraySize(fields);i++)GlobalVariableDel(OrbProPlanKey(positionId,fields[i]));
}
void OrbProStorePlan(ulong ticket,int dir,double entry,double sl,double tp,double halfTrigger,datetime signalTime,int regimeBucket)
{
   if(ticket<=0)return;
   ulong positionId=ticket;
   datetime openTime=TimeCurrent();
   double volume=0.0;
   if(PositionSelectByTicket(ticket))
   {
      ulong actual=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(actual>0)positionId=actual;
      entry=PositionGetDouble(POSITION_PRICE_OPEN);
      openTime=(datetime)PositionGetInteger(POSITION_TIME);
      volume=PositionGetDouble(POSITION_VOLUME);
   }
   OrbProSet(positionId,"entry",entry);OrbProSet(positionId,"sl",sl);OrbProSet(positionId,"tp",tp);OrbProSet(positionId,"half",halfTrigger);
   OrbProSet(positionId,"dir",dir);OrbProSet(positionId,"openTs",openTime);OrbProSet(positionId,"signalTs",signalTime);
   OrbProSet(positionId,"regime",regimeBucket);OrbProSet(positionId,"pipMode",g_rtPipSlMode?1:0);OrbProSet(positionId,"pipValue",g_rtPipSlPips);
   OrbProSet(positionId,"targetLeg",RuntimeTargetLeg());OrbProSet(positionId,"hcLeg",RuntimeHalfBeLeg());
   OrbProSet(positionId,"mfePips",0);OrbProSet(positionId,"maePips",0);OrbProSet(positionId,"mfeMoney",0);OrbProSet(positionId,"maeMoney",0);
   OrbProSet(positionId,"mfePx",entry);OrbProSet(positionId,"maePx",entry);OrbProSet(positionId,"mfeTs",openTime);OrbProSet(positionId,"maeTs",openTime);
   OrbProSet(positionId,"halfDone",0);OrbProSet(positionId,"beDone",0);
   Audit("position_plan_stored",dir>0?"BUY":"SELL",volume,entry,sl,tp,
      "position_id="+StringFormat("%I64u",positionId)+" half="+DoubleToString(halfTrigger,_Digits)+" regime="+OrbRegimeName(regimeBucket));
}void OrbProStoreOpenPositions(int dir,double entry,double sl,double tp,double halfTrigger,datetime signalTime,int regimeBucket)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(positionId==0)positionId=ticket;
      if(!OrbProHas(positionId))OrbProStorePlan(ticket,dir,entry,sl,tp,halfTrigger,signalTime,regimeBucket);
   }
}
void OrbProRestoreRuntimeState()
{
   bool restored=false,halfDone=false,beDone=false;
   datetime earliestOpen=0;
   int restoredDir=0,restoredRegime=-1;
   double restoredEntry=0.0,restoredSl=0.0,restoredMfePx=0.0,restoredMaePx=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(positionId==0)positionId=ticket;
      int dir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(!OrbProHas(positionId))OrbProStorePlan(ticket,dir,PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),0,(datetime)PositionGetInteger(POSITION_TIME),-1);
      datetime openTime=(datetime)OrbProGet(positionId,"openTs",(double)PositionGetInteger(POSITION_TIME));
      if(!restored||earliestOpen==0||openTime<earliestOpen)
      {
         restored=true;earliestOpen=openTime;restoredDir=dir;
         restoredEntry=OrbProGet(positionId,"entry",PositionGetDouble(POSITION_PRICE_OPEN));
         restoredSl=OrbProGet(positionId,"sl",PositionGetDouble(POSITION_SL));
         restoredRegime=(int)OrbProGet(positionId,"regime",-1);
         restoredMfePx=OrbProGet(positionId,"mfePx",restoredEntry);
         restoredMaePx=OrbProGet(positionId,"maePx",restoredEntry);
      }
      if(OrbProGet(positionId,"halfDone",0)>0.5)halfDone=true;
      if(OrbProGet(positionId,"beDone",0)>0.5)beDone=true;
   }
   if(!restored)return;
   g_tradeDir=restoredDir;g_tradeEntry=restoredEntry;g_tradeSl=restoredSl;g_tradeRisk=MathAbs(restoredEntry-restoredSl);
   g_tradeOpenTime=earliestOpen;g_tradeTaken=true;g_halfClosed=halfDone;g_beMoved=beDone;
   g_tradeBestHigh=MathMax(restoredEntry,MathMax(restoredMfePx,restoredMaePx));
   g_tradeBestLow=MathMin(restoredEntry,MathMin(restoredMfePx,restoredMaePx));
   g_tradeLastDynamicExitBar=0;g_lastSignalRegime=restoredRegime;g_lastSignalRegimeName=OrbRegimeName(restoredRegime);
   if(g_tradeRisk>0)
   {
      bool isBuy=g_tradeDir>0;
      g_tradeTp1=PriceAtLeg(isBuy,g_tradeEntry,g_tradeRisk,1);g_tradeTp2=PriceAtLeg(isBuy,g_tradeEntry,g_tradeRisk,2);
      g_tradeTp3=PriceAtLeg(isBuy,g_tradeEntry,g_tradeRisk,3);g_tradeTp4=PriceAtLeg(isBuy,g_tradeEntry,g_tradeRisk,4);
      g_tradeTp5=PriceAtLeg(isBuy,g_tradeEntry,g_tradeRisk,5);g_tradeTp6=PriceAtLeg(isBuy,g_tradeEntry,g_tradeRisk,6);
   }
   g_lastExecStatus="RESTORED_OPEN_POSITION";
   Audit("position_runtime_restored",g_tradeDir>0?"BUY":"SELL",0,g_tradeEntry,g_tradeSl,0,
      "open="+OrbProTime(g_tradeOpenTime)+" risk="+DoubleToString(g_tradeRisk,_Digits)+" half_done="+(g_halfClosed?"1":"0")+" be_done="+(g_beMoved?"1":"0"));
}void OrbProMarkHalfDone(ulong ticket)
{
   if(ticket==0)return;ulong positionId=ticket;
   if(PositionSelectByTicket(ticket)){ulong actual=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(actual>0)positionId=actual;}
   OrbProSet(positionId,"halfDone",1);
}
void OrbProMarkBeDone(ulong ticket)
{
   if(ticket==0)return;ulong positionId=ticket;
   if(PositionSelectByTicket(ticket)){ulong actual=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(actual>0)positionId=actual;}
   OrbProSet(positionId,"beDone",1);
}
void OrbProUpdateOpenPositions()
{
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;double pip=OrbPipSize();if(pip<=0)return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(positionId==0)positionId=ticket;
      int dir=(long)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),px=dir>0?tick.bid:tick.ask;
      if(!OrbProHas(positionId))OrbProStorePlan(ticket,dir,entry,PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_TP),0,(datetime)PositionGetInteger(POSITION_TIME),-1);
      double signedPips=dir>0?(px-entry)/pip:(entry-px)/pip;
      double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(signedPips>OrbProGet(positionId,"mfePips",0)){OrbProSet(positionId,"mfePips",signedPips);OrbProSet(positionId,"mfeMoney",pnl);OrbProSet(positionId,"mfePx",px);OrbProSet(positionId,"mfeTs",TimeCurrent());}
      if(signedPips<OrbProGet(positionId,"maePips",0)){OrbProSet(positionId,"maePips",signedPips);OrbProSet(positionId,"maeMoney",pnl);OrbProSet(positionId,"maePx",px);OrbProSet(positionId,"maeTs",TimeCurrent());}
   }
}
bool OrbProPositionStillOpen(ulong positionId)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==positionId)return true;
   }
   return false;
}
string OrbProLifecycleFile(){return "ORB15_ProfessionalLifecycle_"+OrbProDate(TimeGMT())+".csv";}
void OrbProWriteLifecycleClose(ulong positionId,ulong dealTicket)
{
   if(positionId==0||!OrbProHas(positionId)||OrbProPositionStillOpen(positionId))return;
   if(!HistorySelectByPosition(positionId))return;
   double pnl=0,volumeOut=0,exitPrice=0;datetime closeTs=0;string reason="broker_close";
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);if(deal==0)continue;
      ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(e!=DEAL_ENTRY_OUT&&e!=DEAL_ENTRY_INOUT&&e!=DEAL_ENTRY_OUT_BY)continue;
      pnl+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
      volumeOut+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      datetime ts=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);if(ts>=closeTs){closeTs=ts;exitPrice=HistoryDealGetDouble(deal,DEAL_PRICE);reason=HistoryDealGetString(deal,DEAL_COMMENT);}
   }
   double entry=OrbProGet(positionId,"entry",0),sl=OrbProGet(positionId,"sl",0),tp=OrbProGet(positionId,"tp",0),half=OrbProGet(positionId,"half",0);
   int dir=(int)OrbProGet(positionId,"dir",0);double pip=OrbPipSize();double riskPips=pip>0?MathAbs(entry-sl)/pip:0;
   double pnlPips=pip>0?(dir>0?(exitPrice-entry)/pip:(entry-exitPrice)/pip):0;
   double pnlR=riskPips>0?pnlPips/riskPips:0;datetime openTs=(datetime)OrbProGet(positionId,"openTs",0);
   int regime=(int)OrbProGet(positionId,"regime",-1);
   int handle=FileOpen(OrbProLifecycleFile(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI,',');
   if(handle!=INVALID_HANDLE)
   {
      bool header=FileSize(handle)<=0;FileSeek(handle,0,SEEK_END);
      if(header)FileWrite(handle,"written_gmt","build","symbol","chart_tf","signal_tf","position_id","deal_ticket","direction","signal_time","open_time","close_time","duration_sec","volume_out","entry","initial_sl","target_tp","half_trigger","exit_price","risk_pips","pnl_pips","pnl_r","realized_pnl","mfe_pips","mae_pips","mfe_money","mae_money","mfe_price","mae_price","mfe_time","mae_time","regime_id","regime_name","pip_sl_on","pip_sl_pips","target_leg","hc_leg","half_done","be_done","exit_reason");
      FileWrite(handle,OrbProTime(TimeGMT()),ORB15_BUILD,_Symbol,OrbProTf(_Period),OrbProTf(g_rtSignalTf),StringFormat("%I64u",positionId),StringFormat("%I64u",dealTicket),dir>0?"BUY":"SELL",
         OrbProTime((datetime)OrbProGet(positionId,"signalTs",0)),OrbProTime(openTs),OrbProTime(closeTs),IntegerToString((int)MathMax(0,closeTs-openTs)),DoubleToString(volumeOut,4),
         DoubleToString(entry,_Digits),DoubleToString(sl,_Digits),DoubleToString(tp,_Digits),DoubleToString(half,_Digits),DoubleToString(exitPrice,_Digits),DoubleToString(riskPips,2),DoubleToString(pnlPips,2),DoubleToString(pnlR,4),DoubleToString(pnl,2),
         DoubleToString(MathMax(0,OrbProGet(positionId,"mfePips",0)),2),DoubleToString(MathMax(0,-OrbProGet(positionId,"maePips",0)),2),DoubleToString(OrbProGet(positionId,"mfeMoney",0),2),DoubleToString(OrbProGet(positionId,"maeMoney",0),2),
         DoubleToString(OrbProGet(positionId,"mfePx",0),_Digits),DoubleToString(OrbProGet(positionId,"maePx",0),_Digits),OrbProTime((datetime)OrbProGet(positionId,"mfeTs",0)),OrbProTime((datetime)OrbProGet(positionId,"maeTs",0)),
         IntegerToString(regime),OrbRegimeName(regime),OrbProGet(positionId,"pipMode",0)>0.5?"1":"0",DoubleToString(OrbProGet(positionId,"pipValue",0),1),IntegerToString((int)OrbProGet(positionId,"targetLeg",0)),IntegerToString((int)OrbProGet(positionId,"hcLeg",0)),
         OrbProGet(positionId,"halfDone",0)>0.5?"1":"0",OrbProGet(positionId,"beDone",0)>0.5?"1":"0",reason);
      FileClose(handle);
   }
   Audit("position_closed",dir>0?"BUY":"SELL",volumeOut,entry,sl,tp,"position_id="+StringFormat("%I64u",positionId)+" pnl="+DoubleToString(pnl,2)+" pnl_pips="+DoubleToString(pnlPips,2)+" pnl_r="+DoubleToString(pnlR,4)+" mfe_pips="+DoubleToString(OrbProGet(positionId,"mfePips",0),2)+" mae_pips="+DoubleToString(OrbProGet(positionId,"maePips",0),2)+" reason="+reason);
   OrbProDelete(positionId);
}
void OrbProOnTradeTransaction(const MqlTradeTransaction &trans)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD||trans.deal==0)return;
   if(!HistoryDealSelect(trans.deal))return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol||!MagicOwned((long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)))return;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT&&entry!=DEAL_ENTRY_INOUT&&entry!=DEAL_ENTRY_OUT_BY)return;
   ulong positionId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   OrbProWriteLifecycleClose(positionId,trans.deal);
}
datetime g_orbProLastRecovery=0;
void OrbProRecoverClosedPlans(bool force)
{
   datetime now=TimeCurrent();
   if(!force&&g_orbProLastRecovery>0&&now-g_orbProLastRecovery<30)return;
   g_orbProLastRecovery=now;
   string prefix="OP."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+".";
   ulong ids[];ArrayResize(ids,0);
   int total=GlobalVariablesTotal();
   for(int i=0;i<total;i++)
   {
      string name=GlobalVariableName(i);
      if(StringFind(name,prefix)!=0||StringFind(name,".entry")<0)continue;
      int from=StringLen(prefix),dot=StringFind(name,".",from);if(dot<=from)continue;
      ulong positionId=(ulong)StringToInteger(StringSubstr(name,from,dot-from));if(positionId==0)continue;
      bool exists=false;for(int j=0;j<ArraySize(ids);j++)if(ids[j]==positionId){exists=true;break;}
      if(!exists){int n=ArraySize(ids);ArrayResize(ids,n+1);ids[n]=positionId;}
   }
   for(int i=0;i<ArraySize(ids);i++)
   {
      if(OrbProPositionStillOpen(ids[i])||!HistorySelectByPosition(ids[i]))continue;
      ulong latestDeal=0;datetime latestTime=0;
      for(int d=0;d<HistoryDealsTotal();d++)
      {
         ulong deal=HistoryDealGetTicket(d);if(deal==0)continue;
         ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(e!=DEAL_ENTRY_OUT&&e!=DEAL_ENTRY_INOUT&&e!=DEAL_ENTRY_OUT_BY)continue;
         datetime ts=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         if(ts>=latestTime){latestTime=ts;latestDeal=deal;}
      }
      if(latestDeal>0)OrbProWriteLifecycleClose(ids[i],latestDeal);
   }
}
void OrbProInit()
{
   g_orbBridgeEnabled=InpFileBridgeEnabled;g_orbBridgeOnly=InpFileBridgeOnlyMode;
   g_orbNativeWithBridgeOnly=InpNativeTradeWithBridgeOnlyDefault;
   if(g_orbBridgeOnly)g_orbBridgeEnabled=true;
   OrbProLoadPending();OrbProRestoreRuntimeState();OrbProRecoverClosedPlans(true);
   if(g_orbBridgeEnabled)OrbProWriteInitMarker();
}
void OrbProTimer(){OrbProRetryPending();OrbProUpdateOpenPositions();}

#endif
