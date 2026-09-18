// MA history is an event stream, not one representative trade per ORB day.
#ifndef MA_CROSS_EVENT_AUDIT_MQH
#define MA_CROSS_EVENT_AUDIT_MQH
datetime g_maAuditPositionUntil=0;
int g_maAuditHeldCandidates=0;
bool g_maObservedAuditDirty=false;
string g_maLastObservedKey="";

string MaHistoryEventBase(datetime when,string rawDirection)
{return HistoricalObjectRoot()+"MA_"+(string)(long)when+"_"+rawDirection+"_";}

void MaObserveClosedSignal()
{
   if(IsTesterMode())return;
   if(g_maObservedAuditDirty&&!g_histAuditRunning&&!g_histRedrawQueued)
   {g_maObservedAuditDirty=false;QueueHistoricalRedraw(0);}
   MaCrossSignal signal;
   if(!MaCrossComputeSignal(_Symbol,g_rtSignalTf,g_rtMaCrossMode,g_rtMaCrossPair,
      InpMaFastLength,InpMaMediumLength,InpMaSlowLength,signal))return;
   string base=PREFIX+"MA_OBS_"+(string)g_rtMaCrossMode+"_"+(string)g_rtSignalTf+"_"+(string)(long)signal.barTime+"_";
   string key=base+(string)g_rtMaCrossPair;
   if(key==g_maLastObservedKey)return;
   g_maLastObservedKey=key;
   // Reconcile the persistent source signal into a historical snapshot.
   if(g_histAuditRunning)g_maObservedAuditDirty=true;else QueueHistoricalRedraw(0);
}

void MaPruneObservedSignals(datetime coveredThrough)
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,PREFIX+"MA_OBS_")!=0)continue;
      datetime t=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME);
      if(t<=coveredThrough)ObjectDelete(0,name);
   }
}

int ProcessMaHistoricalPrepEvent(int index)
{
   if(index<0||index>=ArraySize(g_maCrossAuditEvents))return 0;
   MaCrossAuditEvent event=g_maCrossAuditEvents[index];
   OrbHistoricalDaySnapshot snapshot;ZeroMemory(snapshot);
   snapshot.known=true;snapshot.valid=true;snapshot.operationalKnown=true;snapshot.operationalHadRawCandidate=true;
   snapshot.hi=event.high;snapshot.lo=event.low;snapshot.avgVolume=event.priorVolume;snapshot.usedBars=1;
   snapshot.orbStart=event.signalTime;snapshot.orbEnd=event.signalTime;
   snapshot.tradeEnd=event.signalTime+86400;
   snapshot.operationalSignalTime=event.signalTime;snapshot.operationalDirection=event.direction>0?"BUY":"SELL";
   snapshot.operationalClose=event.close;snapshot.operationalHigh=event.high;snapshot.operationalLow=event.low;
   snapshot.operationalVolume=event.volume;snapshot.operationalPreAverageVolume=event.priorVolume;
   string dir=snapshot.operationalDirection,reason="",detail="";
   MqlDateTime day;TimeToStruct(ServerToSessionLocal(event.signalTime),day);
   bool allowed=EntryWindowAllowsAt(OrbSignalAvailableTime(event.signalTime));
   if(!allowed)reason="ENTRY_WINDOW";
   if(allowed&&!HistCheckDay(day.day_of_week,reason))allowed=false;
   if(allowed&&!HistCheckVol(event.volume,event.priorVolume,reason))allowed=false;
   if(allowed&&!ModernFilterAllows(event.signalTime,snapshot.tradeEnd,g_rtSignalTf,event.signalTime,dir,
                                  g_rtDisplacement,g_rtFvgMode,reason,detail))allowed=false;
   snapshot.operationalFound=allowed;snapshot.operationalLastReject=reason;snapshot.operationalModernDetail=detail;
   g_histDaySnapshots[index]=snapshot;
   if(allowed)AppendOrbOperationalSignal(g_histOperationalSignals,event.signalTime,dir,event.close,event.high,event.low);
   datetime entryTime=event.signalTime;double entryPrice=event.close;string entryDetail="";
   if(allowed&&!ResolveHistoricalEntry(g_rtEntryMode,dir,event.signalTime,event.close,event.high,event.low,
                                      snapshot.tradeEnd,entryTime,entryPrice,entryDetail))
   {allowed=false;reason="ENTRY "+entryDetail;}
   if(allowed)
   {
      double saveHi=g_orbHigh,saveLo=g_orbLow;datetime saveOs=g_orbStartServer,saveOe=g_orbEndServer,saveTe=g_tradeEndServer;
      g_orbHigh=event.high;g_orbLow=event.low;g_orbStartServer=event.signalTime;g_orbEndServer=event.signalTime;g_tradeEndServer=snapshot.tradeEnd;
      double buffer=InpSlBufferPoints*SymbolInfoDouble(_Symbol,SYMBOL_POINT),sl,risk;string geometry="";
      bool sb=dir=="BUY",eb=EffectiveOrbDirection(dir)=="BUY";
      allowed=ResolveExecutionStop(sb,eb,entryPrice,sb?event.low-buffer:event.high+buffer,sl,risk,geometry);
      g_orbHigh=saveHi;g_orbLow=saveLo;g_orbStartServer=saveOs;g_orbEndServer=saveOe;g_tradeEndServer=saveTe;
      if(!allowed)reason="GEOMETRY "+geometry;
   }
   bool beforeRegime=allowed;
   if(allowed)
   {
      AppendOrbAcceptedSignal(g_regimeReferenceSignals,event.signalTime,entryTime,dir,event.close,event.high,event.low);
      RegimeV3Snapshot regime;int bucket=OrbRegimeBucketAt(event.signalTime,regime);
      if(!OrbRegimeAllowed(bucket)){allowed=false;reason="REGIME";}
      if(allowed){int rule;string code,rf;if(!OrbRfEvaluate(dir,regime,rule,code,rf)){allowed=false;reason="RF "+code;}}
   }
   if(allowed)AppendOrbAcceptedSignal(g_histAcceptedSignals,event.signalTime,entryTime,dir,event.close,event.high,event.low);
   else
   {
      AppendOrbWindowSignal(g_histWindowSignals,event.signalTime,dir,reason,event.close,event.high,event.low);
      // Retain the event for exit/filter causality, without drawing rejected candidates.
      g_histWindowSignals[ArraySize(g_histWindowSignals)-1].drawOnChart=false;
      if(!beforeRegime)AppendOrbWindowSignal(g_regimeReferenceWindows,event.signalTime,dir,reason,event.close,event.high,event.low);
   }
   // Draw only final audited trades in CALC, never provisional PREP candidates.
   return allowed?0:1;
}
#endif
