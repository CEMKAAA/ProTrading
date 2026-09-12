#ifndef ORB_STRATEGY_ML_HISTORY_MQH
#define ORB_STRATEGY_ML_HISTORY_MQH
bool g_mlHistoryFiltered=false;
int g_mlHistoryAllowed=0,g_mlHistoryRejected=0,g_mlHistoryErrors=0;
int g_mlHistoryInSample=0,g_mlHistoryOosW=0,g_mlHistoryOosL=0;
double g_mlHistoryOosR=0;
string g_mlHistoryLastError="";

// Both callers use the same feature vector, weights and decision threshold.
// Historical training-period inference is diagnostic, never labelled OOS.
bool OrbMlDecision(const string raw,datetime bar,double hi,double lo,datetime orbEnd,
   bool requireOos,string &reason,double &score)
{
   string config=OrbMlConfiguration();double x[],observed[];score=0;
   if(g_mlR7)
   {
      if(!g_r7Slot.ready||config==""||config!=g_r7RuntimeConfig||!OrbCampaignBinding(g_r7Info))reason="R7 MISSING/MISMATCHED MODEL";
      else if(OrbMlFeatures(bar,raw,hi,lo,orbEnd,x,observed,reason))
         OrbSlotScore(g_r7Slot,x,bar+PeriodSeconds(g_rtSignalTf),score,reason);
   }
   else if(g_mlUsingCampaign)
   {
      if(!g_campaignReady||config==""||config!=g_campaignRuntimeConfig||!OrbCampaignBinding(g_campaignInfo))
         reason="CAMPAIGN_BINDING_CHANGED";
      else if(requireOos&&bar+PeriodSeconds(g_rtSignalTf)<=g_campaignCutoff)reason="NOT_OUT_OF_SAMPLE";
      else if(OrbMlFeatures(bar,raw,hi,lo,orbEnd,x,observed,reason))
      {
         if(!OrbCampaignPredict(x,score))reason="INFERENCE_ERROR";
         else reason=!g_campaignActive||score>=g_campaignThreshold?"ALLOW":"SCORE_REJECT";
      }
   }
   else
   {
      if(!g_mlModel.ready||config==""||g_mlModel.config!=config)reason="MISSING_OR_MISMATCHED_MODEL";
      else if(requireOos&&bar+PeriodSeconds(g_rtSignalTf)<=g_mlModel.lastLabelTime)reason="NOT_OUT_OF_SAMPLE";
      else if(OrbMlFeatures(bar,raw,hi,lo,orbEnd,x,observed,reason))
      {
         if(!OrbMlPredict(g_mlModel,x,score))reason="INFERENCE_ERROR";
         else reason=score>=g_mlModel.threshold?"ALLOW":"SCORE_REJECT";
      }
   }
   return reason=="ALLOW";
}

void OrbMlHistoryBegin()
{
   g_mlHistoryFiltered=g_mlEnabled&&!g_mlExport;
   g_mlHistoryAllowed=0;g_mlHistoryRejected=0;g_mlHistoryErrors=0;
   g_mlHistoryInSample=0;g_mlHistoryOosW=0;g_mlHistoryOosL=0;g_mlHistoryOosR=0;
   g_mlHistoryLastError="";
}

bool OrbMlHistoryAllow(datetime bar,const string raw,double hi,double lo,datetime orbEnd,const HistResult &sim)
{
   if(!g_mlHistoryFiltered)return true;
   string reason="";double score=0;
   bool allowed=OrbMlDecision(raw,bar,hi,lo,orbEnd,false,reason,score);
   datetime cutoff=g_mlUsingCampaign?g_campaignCutoff:g_mlModel.lastLabelTime;
   bool inSample=!g_mlR7&&bar+PeriodSeconds(g_rtSignalTf)<=cutoff;
   if(inSample)g_mlHistoryInSample++;
   if(!allowed)
   {
      if(reason=="SCORE_REJECT")g_mlHistoryRejected++;
      else {g_mlHistoryErrors++;g_mlHistoryLastError=reason;}
      return false;
   }
   g_mlHistoryAllowed++;
   if(!inSample&&sim.valid&&sim.outcome!="open")
   {
      if(sim.netR>1e-8)g_mlHistoryOosW++;
      else if(sim.netR<-1e-8)g_mlHistoryOosL++;
      g_mlHistoryOosR+=sim.netR;
   }
   return true;
}

string OrbMlHistorySummary()
{
   if(!g_mlHistoryFiltered)return "BASE AUDIT (ML OFF / CSV EXPORT)";
   string status="ML AUDIT keep="+(string)g_mlHistoryAllowed+" reject="+(string)g_mlHistoryRejected
      +" errors="+(string)g_mlHistoryErrors;
   if(g_mlHistoryErrors>0)return status+" INCOMPLETE: "+g_mlHistoryLastError;
   if(g_mlHistoryInSample>0)status+=" | IN-SAMPLE INCLUDED: NOT OOS";
   status+=" | OOS "+(string)g_mlHistoryOosW+"W/"+(string)g_mlHistoryOosL+"L "+DoubleToString(g_mlHistoryOosR,2)+"R";
   if(g_mlUsingCampaign&&!g_campaignActive)status+=" | NO VETO";
   return status;
}
#endif
