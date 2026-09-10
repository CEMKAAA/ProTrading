from pathlib import Path
root=Path('IndicatorCodeExamples')
p=root/'OrbStrategyMLPipeline.mqh'
s=p.read_text(encoding='utf8')
s=s.replace('void OrbMlAbort(const string reason)', '#include "OrbStrategyMLHistory.mqh"\n\nvoid OrbMlAbort(const string reason)',1)
a=s.index('bool OrbMlAllow(const string raw,datetime bar)'); b=s.index('#include "OrbStrategyMLJobs.mqh"',a)
s=s[:a]+'''bool OrbMlAllow(const string raw,datetime bar)
{
   if(!g_mlEnabled)return true;
   string reason="";double score=0;
   bool allowed=OrbMlDecision(raw,bar,g_orbHigh,g_orbLow,g_orbEndServer,true,reason,score);
   g_mlStatus=(g_mlUsingCampaign?"ML EXP ":"ML ")+reason+" score="+DoubleToString(score,4);
   Audit("ml_filter",EffectiveOrbDirection(raw),0,0,0,0,"bar="+(string)(long)bar+" config="+OrbMlConfiguration()
      +" dataset="+(g_mlUsingCampaign?g_campaignInfo.dataset:g_mlModel.dataset)
      +" experimental="+(g_mlUsingCampaign?"1":"0")+" decision="+reason+" score="+DoubleToString(score,8));
   return allowed;
}

'''+s[b:]
s=s.replace('if(OrbMlJobUiEvent(object)){ObjectSetInteger(0,object,OBJPROP_STATE,false);return true;}', '''if(OrbMlJobUiEvent(object))
   {
      if(object==PREFIX+"BTN_ML_USE"&&g_mlEnabled)QueueHistoricalRedraw(0);
      ObjectSetInteger(0,object,OBJPROP_STATE,false);return true;
   }''')
s=s.replace('   else return false;\n   ObjectSetInteger(0,object,OBJPROP_STATE,false);return true;', '''   else return false;
   if(object==PREFIX+"BTN_ML_LOAD"||object==PREFIX+"BTN_ML_TOGGLE")QueueHistoricalRedraw(0);
   ObjectSetInteger(0,object,OBJPROP_STATE,false);return true;''',1)
s=s.replace('STRATEGY ML FILTER | base audit remains unfiltered','STRATEGY ML FILTER | live + historical entries')
s=s.replace('   if(!g_histAuditRunning&&!g_histRedrawQueued)EventSetTimer(5);\n}', '   if(g_mlEnabled)QueueHistoricalRedraw(0);\n   else if(!g_histAuditRunning&&!g_histRedrawQueued)EventSetTimer(5);\n}',1)
p.write_text(s,encoding='utf8',newline='')
p=root/'OrbUltimateEA_StrategyLibrary.mq5';s=p.read_text(encoding='utf8')
s=s.replace('2026-09-09.v6.87-pretrained-strategy-models','2026-09-09.v6.88-ml-history-filter')
needle='      OrbMlCapture(sigT,entryT,dir,hi,lo,oe,sim);'
assert s.count(needle)==1
s=s.replace(needle,'      if(!OrbMlHistoryAllow(sigT,dir,hi,lo,oe,sim)){g_histFiltered++;return;}\n'+needle)
s=s.replace('   OrbResetHistoricalStats();\n   g_histAuditRunning=true;', '   OrbResetHistoricalStats();\n   OrbMlHistoryBegin();\n   g_histAuditRunning=true;',1)
assert '   OrbMlHistoryBegin();' in s
s=s.replace('   if(g_histFiltered>0)g_histStatLine', '   g_histStatLine+=" | "+OrbMlHistorySummary();\n   if(g_histFiltered>0)g_histStatLine',1)
# Put diagnostics in existing stat line tooltip and compact prefix, no extra layout height.
s=s.replace('   if(g_histCoveragePending)\n   {\n      auditStat1=', '   if(g_mlHistoryFiltered)\n   {\n      auditStat1="ML | "+auditStat1;\n      auditStat2=OrbMlHistorySummary()+" | "+auditStat2;\n      if(g_mlHistoryErrors>0)auditStatColor=C\'255,95,140\';\n   }\n   if(g_histCoveragePending)\n   {\n      auditStat1=',1)
p.write_text(s,encoding='utf8',newline='')
p=root/'OrbStrategyUserMetrics.mqh';s=p.read_text(encoding='utf8')
s=s.replace('   if(g_rtHistoricalWeeks!=52||', '   if(g_mlHistoryFiltered)return; // Never overwrite base metrics with model-filtered results.\n   if(g_rtHistoricalWeeks!=52||',1)
p.write_text(s,encoding='utf8',newline='')
p=Path('scripts/build_orb_ml_contract.ps1');s=p.read_text(encoding='utf8').replace("'OrbStrategyMLPipeline.mqh',", "'OrbStrategyMLPipeline.mqh', 'OrbStrategyMLHistory.mqh',",1);p.write_text(s,encoding='utf8',newline='')
