#ifndef ORB_STRATEGY_USER_METRICS_MQH
#define ORB_STRATEGY_USER_METRICS_MQH
#include "StrategyWindowMetrics.mqh"
int g_userCompletedWeeks=52,g_userCompletedOpen=0,g_userCompletedFlat=0;
string g_userAuditSettings="",g_userCompletedSettings="";
bool g_userCompletedReady=false;
int g_userCompletedTotal=0,g_userCompletedW=0,g_userCompletedL=0;
double g_userCompletedR=0,g_userCompletedMc=0;
datetime g_userCompletedAt=0;

string OrbUserMetricKey(const string symbol,int tf,const string inputs,const string runtime,const OrbStrategyPreset &p,
                        bool advancedReverse,double advancedMaxCostPct,bool currentSchema=true)
{
   string switches=(p.rfMaster?"1":"0");
   for(int r=0;r<ORB_REGIME_COUNT;r++)switches+=OrbPresetRegimeAllowed(p,r)?"1":"0";
   for(int r=0;r<ORB_RF_COUNT;r++)switches+=OrbPresetRfBlocked(p,r)?"1":"0";
   string inverseRevision="";
   if(p.invertMode)
   {
      inverseRevision="|MA_INVERSE_ASK_PROOF_2|ADV_REV="+(advancedReverse?"1":"0");
      if(advancedReverse)inverseRevision+="|ADV_MAX="+DoubleToString(advancedMaxCostPct,6);
   }
   return OrbMlSha256(ORB_ML_SOURCE+(currentSchema?"|AUDIT_FILL_HORIZON2|MA_SERVER_ORIGIN1|":"")+symbol+(string)tf+"MA_EXIT_FILTERED3"+inverseRevision+inputs+runtime+switches);
}
string MaEntryMetricMeta(bool independent,int maximum){if(independent)return "|MAENTRY2_TOTAL_OPEN="+(string)maximum;return maximum==1?"":"|MAENTRY1=0,"+(string)maximum;}
string OrbUserRuntimeMetricKey()
{
   OrbStrategyPreset p;OrbCustomCapturePreset(p);
   return OrbUserMetricKey(_Symbol,(int)NasConfirmationTf(),OrbCustomInputSignature()+MaEntryMetricMeta(g_maIndependent,g_maMaxConsecutive)+"|MAEXIT2="+(string)g_maReverseExit+","+(string)g_maReverseWait+McOfIdentity(),OrbCustomRuntimeDump(),p,g_rtAdvancedReverse,g_rtAdvancedReverseMaxCostPct);
}
string OrbUserWindowKey(const OrbUserRecord &r,bool currentSchema=true)
{
   string ofKey=r.orderFlow.mode==0?"":"|ORDERFLOW_QUOTE_V1="+McOfConfigText(r.orderFlow);
   return SwSettingsKey(OrbUserMetricKey(r.symbol,r.chartTf,r.inputSignature+MaEntryMetricMeta(r.independent,r.maxSeries)
      +"|MAEXIT2="+(string)r.reverseExit+","+(string)r.reverseWait+ofKey,r.runtime,r.preset,r.advancedReverse,r.advancedReverseMaxCostPct,currentSchema)
      +"|TCAL="+r.timeMatrix+"|GAP="+DoubleToString(r.advancedReverseMaxCostPct,8));
}
void OrbUserLoadMetrics(int slot)
{
   if(slot<0||slot>=ArraySize(g_userStrategies))return;
   OrbUserRecord r=g_userStrategies[slot];g_userStrategies[slot].preset.metric1yReady=false;
   SwMetric m;string key=OrbUserWindowKey(r);
   if(SwReadView("MaCrossOrbStrategyLibrary\\WindowMetrics",r.preset.id,key,g_swWeeks,m)
      ||(g_swFrozen&&SwReadView("MaCrossOrbStrategyLibrary\\WindowMetrics",r.preset.id,OrbUserWindowKey(r,false),g_swWeeks,m)))
   {g_userStrategies[slot].preset.metric1yReady=true;g_userStrategies[slot].preset.metric1yAsOf=TimeToString(m.asOf,TIME_DATE|TIME_MINUTES);
    g_userStrategies[slot].preset.metric1yTotal=m.total;g_userStrategies[slot].preset.metric1yWins=m.wins;g_userStrategies[slot].preset.metric1yLosses=m.losses;
    g_userStrategies[slot].preset.metric1yNetR=m.netR;g_userStrategies[slot].preset.metric1yMinCumR=m.minCum;g_userStrategies[slot].preset.metric1yWr=SwWr(m);return;}
   // Legacy aggregate files remain archived, but are not verified window evidence.
}
bool OrbUserPersistCompletedMetrics()
{
   if(g_mcOf.mode!=0&&g_mcOfDataIncomplete)return false;
   OrbStrategyPreset p;
   if(!g_userCompletedReady||!OrbStrategyPresetLoad(g_strategyPresetIndex,p)||!OrbUserPreset(p)||!OrbUserMatches(p)
      ||g_userCompletedSettings!=OrbUserRuntimeMetricKey())return false;
   int savedSlot=OrbUserSlot(p.id);if(savedSlot<0)return false;
   // Runtime stability is checked above; persist under the same immutable identity SEARCH reads.
   string windowKey=OrbUserWindowKey(g_userStrategies[savedSlot]);
   if(!SwWrite("MaCrossOrbStrategyLibrary\\WindowMetrics",p.id,windowKey,g_userCompletedWeeks,g_userCompletedTotal,g_userCompletedW,g_userCompletedL,
      g_userCompletedOpen,g_userCompletedFlat,g_userCompletedR,g_userCompletedMc,g_userCompletedAt))return false;
   if(g_userCompletedWeeks!=52){OrbUserReload(true);OrbStrategyPresetBuildMatches(g_strategySearch);g_userStrategyNote="SAVED "+SwWindow(g_userCompletedWeeks)+": "+p.name;return true;}
   double wr=g_userCompletedW+g_userCompletedL>0?100.0*g_userCompletedW/(g_userCompletedW+g_userCompletedL):0;
   string payload="ORB_USER_METRICS1\n"+p.id+"\n"+g_userCompletedSettings+"\n"+(string)(long)g_userCompletedAt+"\n52\n"
      +(string)g_userCompletedTotal+"\n"+(string)g_userCompletedW+"\n"+(string)g_userCompletedL+"\n"
      +DoubleToString(g_userCompletedR,12)+"\n"+DoubleToString(g_userCompletedMc,12)+"\n"+DoubleToString(wr,12)+"\n";
   int lock=FileOpen("MaCrossOrbStrategyLibrary\\metrics.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lock==INVALID_HANDLE){g_userStrategyNote="Metrics writer busy; retry 1Y audit";return false;}
   bool written=OrbMlAtomicProtocol("MaCrossOrbStrategyLibrary\\"+p.id+".metrics",payload);
   FileClose(lock);
   if(!written)
   {g_userStrategyNote="1Y metrics write failed; retry a 1Y audit";return false;}
   OrbUserReload(true);OrbStrategyPresetBuildMatches(g_strategySearch);
   g_userStrategyNote="SAVED + 1Y METRICS: "+p.name+" | WR "+DoubleToString(wr,1)+"% | "+DoubleToString(g_userCompletedR,2)+"R";
   return true;
}
void OrbUserEnsureMetrics()
{
   if(!g_histAuditRunning&&!g_histRedrawQueued&&OrbUserPersistCompletedMetrics())return;
   SetHistoricalWeeks(g_swWeeks);QueueHistoricalRedraw(0);
}
void OrbUserAuditStarted(){g_userAuditSettings=OrbUserRuntimeMetricKey();}
void OrbUserAuditCompleted()
{
   if(g_mlHistoryFiltered)return; // Never overwrite base metrics with model-filtered results.
   if(!SwValidWindow(g_rtHistoricalWeeks)||g_histInvalid>0||g_histCoveragePending||g_userAuditSettings!=OrbUserRuntimeMetricKey())return;
   g_userCompletedSettings=g_userAuditSettings;g_userCompletedReady=true;g_userCompletedAt=g_histRunNow;
   g_userCompletedWeeks=g_rtHistoricalWeeks;g_userCompletedOpen=g_histOpen;g_userCompletedFlat=g_histFlat;
   g_userCompletedTotal=g_histTotal;g_userCompletedW=g_histWins;g_userCompletedL=g_histLosses;
   g_userCompletedR=g_histNetR;g_userCompletedMc=g_histMinCumulativeR;
   OrbUserPersistCompletedMetrics();
}
#endif
