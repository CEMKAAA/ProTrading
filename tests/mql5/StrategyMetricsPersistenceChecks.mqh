int metricsChecks=0,metricsFailed=0;
void MetricsCheck(bool yes,string label)
{metricsChecks++;if(!yes){metricsFailed++;Print("METRICS FAIL: ",label);}}
void MetricsCheckRead(string folder,string id,string key)
{
   for(int i=0;i<9;i++)
   {
      SwMetric m;bool ready=SwRead(folder,id,key,SwWeeks(i),m);
      MetricsCheck(ready,"window readback "+SwWindow(SwWeeks(i)));
      if(ready)MetricsCheck(m.total==20+i&&m.wins==10+i&&m.losses==5&&m.open==5
         &&MathAbs(m.netR-(2.0+i))<1e-9&&MathAbs(m.minCum+0.5)<1e-9,"exact counts/R/MC "+SwWindow(SwWeeks(i)));
   }
}
void MetricsClean(string folder,string id)
{
   for(int i=0;i<9;i++)
   {string path=SwPath(folder,id,SwWeeks(i));FileDelete(path,FILE_COMMON);FileDelete(path+".lock",FILE_COMMON);}
}
#ifdef METRICS_SOL
void MetricsRun()
{
   for(int d=0;d<7;d++)g_tcalDayHours[d]=16777215;
   LnNasDefaults(g_lnNas);g_target=ERL_RR_CUSTOM;g_customTargetR=0.2;
   g_targetModel=ERL_TARGET_FIXED_R;g_histWeeks=2;
   string identity=LiqWindowRuntimeFingerprint();g_histWeeks=260;
   MetricsCheck(identity==LiqWindowRuntimeFingerprint(),"audit window not part of execution fingerprint");
   g_customTargetR=0.3;
   MetricsCheck(identity!=LiqWindowRuntimeFingerprint(),"geometry remains part of identity");g_customTargetR=0.2;
   string stem="__METRICS_PROBE_"+(string)GetTickCount64(),first=stem+"_base",clone=stem+"_clone";
   MetricsCheck(LiqLibrarySave(first),"save unaudited strategy");
   string basePath=LiqLibraryPath(first),baseKey=LiqWindowKey(basePath),folder=LiqWindowFolder();
   for(int i=0;i<9;i++)
   {
      g_histWeeks=SwWeeks(i);
      MetricsCheck(SwRememberCompleted(LiqWindowRuntimeFingerprint(),g_histWeeks,20+i,10+i,5,5,0,2.0+i,-0.5,TimeCurrent()),"capture explicit test summary");
      MetricsCheck(LiqWindowPersistCompleted(),"automatic persist without another Save");
   }
   MetricsCheckRead(folder,basePath,baseKey);
   g_histWeeks=2;
   MetricsCheck(LiqLibrarySave(clone),"audit first then save new name");
   string clonePath=LiqLibraryPath(clone),cloneKey=LiqWindowKey(clonePath);
   MetricsCheckRead(folder,clonePath,cloneKey);MetricsCheckRead(folder,basePath,baseKey);
   g_swWeeks=260;MetricsCheck(StringFind(LiqWindowCaption(clonePath,clone),"N/A")<0,"search caption reads saved 5Y");
   g_swCompletedIdentity="";g_swCompletedLast=-1;
   for(int i=0;i<9;i++)ZeroMemory(g_swCompletedWindows[i]);
   g_histWeeks=260;
   MetricsCheck(LiqLibrarySave(clone),"same-name save after reload and window switch");
   MetricsCheckRead(folder,clonePath,LiqWindowKey(clonePath));
   g_customTargetR=0.4;MetricsCheck(!LiqWindowPersistCompleted(),"changed geometry cannot publish old summary");
   MetricsCheckRead(folder,basePath,baseKey);
   MetricsClean(folder,basePath);MetricsClean(folder,clonePath);
   FileDelete(basePath,FILE_COMMON);FileDelete(basePath+".lock",FILE_COMMON);
   FileDelete(clonePath,FILE_COMMON);FileDelete(clonePath+".lock",FILE_COMMON);
}
#else
void MetricsRun()
{
   for(int d=0;d<7;d++)g_tcalDayHours[d]=16777215;
   g_runtimeMagic=9192027000+(long)(GetTickCount64()%1000000);
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);
   MetricsCheck(OrbStrategyPresetApplyValues(defaults),"valid default setup");
   string stem="__METRICS_PROBE_"+(string)GetTickCount64();
   MetricsCheck(OrbUserSave(stem+"_base"),"save unaudited strategy");
   OrbStrategyPreset base;MetricsCheck(OrbStrategyPresetLoad(g_strategyPresetIndex,base),"load base");
   int baseSlot=OrbUserSlot(base.id);string baseKey=OrbUserWindowKey(g_userStrategies[baseSlot]);
   g_histRedrawQueued=false;g_histAuditRunning=false;
   for(int i=0;i<9;i++)
   {
      g_rtHistoricalWeeks=SwWeeks(i);g_histRunNow=TimeCurrent();g_histTotal=20+i;g_histWins=10+i;g_histLosses=5;
      g_histOpen=5;g_histFlat=0;g_histInvalid=0;g_histCoveragePending=false;g_histNetR=2.0+i;g_histMinCumulativeR=-0.5;
      OrbUserAuditStarted();OrbUserAuditCompleted();
      SwMetric m;MetricsCheck(SwRead(METRICS_FOLDER,base.id,baseKey,g_rtHistoricalWeeks,m),"audit completion auto-writes without Save");
   }
   MetricsCheckRead(METRICS_FOLDER,base.id,baseKey);
   g_rtHistoricalWeeks=2;
   MetricsCheck(OrbUserSave(stem+"_clone"),"audit first then save new name");
   OrbStrategyPreset clone;MetricsCheck(OrbStrategyPresetLoad(g_strategyPresetIndex,clone),"load clone");
   int cloneSlot=OrbUserSlot(clone.id);string cloneKey=OrbUserWindowKey(g_userStrategies[cloneSlot]);
   MetricsCheckRead(METRICS_FOLDER,clone.id,cloneKey);MetricsCheckRead(METRICS_FOLDER,base.id,baseKey);
   g_swWeeks=260;OrbUserLoadMetrics(cloneSlot);
   MetricsCheck(g_userStrategies[cloneSlot].preset.metric1yReady,"search reads saved 5Y");
   g_dailyTargetWins=3;
   MetricsCheck(!OrbUserPersistCompletedMetrics(),"changed time/quota setup cannot publish old summary");g_dailyTargetWins=0;
   g_histInvalid=1;g_histNetR=999.0;OrbUserAuditStarted();OrbUserAuditCompleted();
   SwMetric m;MetricsCheck(SwRead(METRICS_FOLDER,clone.id,cloneKey,260,m)&&m.netR==10.0,"DATA does not replace complete evidence");
   g_histInvalid=0;
   MetricsClean(METRICS_FOLDER,base.id);MetricsClean(METRICS_FOLDER,clone.id);
   FileDelete(OrbUserFile(baseSlot),FILE_COMMON);FileDelete(OrbUserFile(cloneSlot),FILE_COMMON);
   FileDelete(METRICS_LIBRARY+"\\"+base.id+".metrics",FILE_COMMON);
   FileDelete(METRICS_LIBRARY+"\\"+clone.id+".metrics",FILE_COMMON);
}
#endif
void OnStart()
{
   MetricsRun();
   string text=StringFormat("{\"checks\":%d,\"failed\":%d,\"kind\":\"synthetic_counter_persistence_not_market_audit\"}",metricsChecks,metricsFailed);
   int h=FileOpen("StrategyMetrics_"+METRICS_NAME+".json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE){FileWriteString(h,text);FileClose(h);}Print(text);
}
