#ifndef ORB_STRATEGY_USER_METRICS_MQH
#define ORB_STRATEGY_USER_METRICS_MQH
string g_userAuditSettings="",g_userCompletedSettings="";
bool g_userCompletedReady=false;
int g_userCompletedTotal=0,g_userCompletedW=0,g_userCompletedL=0;
double g_userCompletedR=0,g_userCompletedMc=0;
datetime g_userCompletedAt=0;

string OrbUserMetricKey(const string symbol,int tf,const string inputs,const string runtime,const OrbStrategyPreset &p)
{
   string switches=(p.rfMaster?"1":"0");
   for(int r=0;r<ORB_REGIME_COUNT;r++)switches+=OrbPresetRegimeAllowed(p,r)?"1":"0";
   for(int r=0;r<ORB_RF_COUNT;r++)switches+=OrbPresetRfBlocked(p,r)?"1":"0";
   return OrbMlSha256(ORB_ML_SOURCE+symbol+(string)tf+inputs+runtime+switches);
}
string OrbUserRuntimeMetricKey()
{
   OrbStrategyPreset p;OrbCustomCapturePreset(p);
   return OrbUserMetricKey(_Symbol,(int)_Period,OrbCustomInputSignature(),OrbCustomRuntimeDump(),p);
}
void OrbUserLoadMetrics(int slot)
{
   if(slot<0||slot>=ArraySize(g_userStrategies))return;
   OrbUserRecord r=g_userStrategies[slot];string v[];
   if(!OrbMlReadLines("OrbMLPriorFive_20260910\\UserStrategies\\"+r.preset.id+".metrics",v,12,true))return;
   if(v[0]!="ORB_USER_METRICS1"||v[1]!=r.preset.id||v[2]!=OrbUserMetricKey(r.symbol,r.chartTf,r.inputSignature,r.runtime,r.preset)||v[4]!="52")return;
   double n[8];for(int i=3;i<=10;i++)if(!OrbMlNumber(v[i],n[i-3]))return;
   if(n[0]<=0||n[2]<0||n[3]<0||n[4]<0||n[3]+n[4]>n[2]||n[7]<0||n[7]>100)return;
   if(n[2]!=MathFloor(n[2])||n[3]!=MathFloor(n[3])||n[4]!=MathFloor(n[4]))return;
   double expected=(n[3]+n[4]>0?100*n[3]/(n[3]+n[4]):0);
   if(MathAbs(expected-n[7])>1e-5)return;
   g_userStrategies[slot].preset.metric1yReady=true;
   g_userStrategies[slot].preset.metric1yAsOf=TimeToString((datetime)n[0],TIME_DATE|TIME_MINUTES);
   g_userStrategies[slot].preset.metric1yTotal=(int)n[2];
   g_userStrategies[slot].preset.metric1yWins=(int)n[3];g_userStrategies[slot].preset.metric1yLosses=(int)n[4];
   g_userStrategies[slot].preset.metric1yNetR=n[5];g_userStrategies[slot].preset.metric1yMinCumR=n[6];
   g_userStrategies[slot].preset.metric1yWr=n[7];
}
bool OrbUserPersistCompletedMetrics()
{
   OrbStrategyPreset p;
   if(!g_userCompletedReady||!OrbStrategyPresetLoad(g_strategyPresetIndex,p)||!OrbUserPreset(p)||!OrbUserMatches(p)
      ||g_userCompletedSettings!=OrbUserRuntimeMetricKey())return false;
   double wr=g_userCompletedW+g_userCompletedL>0?100.0*g_userCompletedW/(g_userCompletedW+g_userCompletedL):0;
   string payload="ORB_USER_METRICS1\n"+p.id+"\n"+g_userCompletedSettings+"\n"+(string)(long)g_userCompletedAt+"\n52\n"
      +(string)g_userCompletedTotal+"\n"+(string)g_userCompletedW+"\n"+(string)g_userCompletedL+"\n"
      +DoubleToString(g_userCompletedR,12)+"\n"+DoubleToString(g_userCompletedMc,12)+"\n"+DoubleToString(wr,12)+"\n";
   int lock=FileOpen("OrbMLPriorFive_20260910\\UserStrategies\\metrics.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lock==INVALID_HANDLE){g_userStrategyNote="Metrics writer busy; retry 1Y audit";return false;}
   bool written=OrbMlAtomicProtocol("OrbMLPriorFive_20260910\\UserStrategies\\"+p.id+".metrics",payload);
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
   SetHistoricalWeeks(52);QueueHistoricalRedraw(0);
}
void OrbUserAuditStarted(){g_userAuditSettings=OrbUserRuntimeMetricKey();}
void OrbUserAuditCompleted()
{
   if(g_rtHistoricalWeeks!=52||g_histInvalid>0||g_histCoveragePending||g_userAuditSettings!=OrbUserRuntimeMetricKey())return;
   g_userCompletedSettings=g_userAuditSettings;g_userCompletedReady=true;g_userCompletedAt=g_histRunNow;
   g_userCompletedTotal=g_histTotal;g_userCompletedW=g_histWins;g_userCompletedL=g_histLosses;
   g_userCompletedR=g_histNetR;g_userCompletedMc=g_histMinCumulativeR;
   OrbUserPersistCompletedMetrics();
}
#endif
