$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build_orb_ml_export_probe.ps1')
$root=Split-Path -Parent $PSScriptRoot
$seed=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLExportProbe'
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLDashboardProbe'
[IO.Directory]::CreateDirectory($dest) | Out-Null
$source=[IO.File]::ReadAllText((Join-Path $seed 'OrbMLExportProbe.mq5'))
$source=$source.Substring(0,$source.LastIndexOf('void OnStart()'))
$source+=@'
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   g_rtEaEnabled=false;g_auditRuntime=false;g_mlEnabled=false;
   OrbStrategyPreset p;
   OrbStrategyPresetLoad(7,p);OrbStrategyPresetApplyValues(p);
   g_strategyPresetIndex=7;g_strategyCandidateIndex=7;g_rtAdvancedAuditEngine=true;
   g_rtSlDistancePct=InpSlDistancePct;g_btFillMode=InpBacktestFillMode;
   g_btSameBarPolicy=InpBacktestSameBarPolicy;g_btNativeParity=InpBacktestNativeParity;
   g_btSpreadPts=20;g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   g_rtNasOppositeExitWaitMinutes=137;g_rtNasFlowVolumeMultiplier=1.65;g_rtBEOnTp1=true;
   string expected=OrbCustomRuntimeDump();
   if(!OrbUserSave("PROBE "+(string)TimeGMT())){Print("ORB_ML_DASH_PROBE SAVE FAILED ",g_userStrategyNote);return;}
   int selected=g_strategyPresetIndex;
   OrbStrategyPreset saved;OrbStrategyPresetLoad(selected,saved);
   g_rtNasOppositeExitWaitMinutes=9;g_rtNasFlowVolumeMultiplier=0.1;g_rtBEOnTp1=false;
   if(OrbUserMatches(saved)){Print("ORB_ML_DASH_PROBE MUTATION UNDETECTED");return;}
   OrbStrategyPresetApplyValues(saved);OrbUserReload(true);
   if(!OrbUserMatches(saved)||expected!=OrbCustomRuntimeDump()||!OrbUserRemembered(saved))
   {Print("ORB_ML_DASH_PROBE RESTORE FAILED");return;}
   Print("ORB_ML_DASH_PROBE USER_STRATEGY_EXACT PASS id=",saved.id);
   RegimeV3Update(true);
   if(!OrbMlStartExport()){Print("ORB_ML_DASH_PROBE EXPORT START FAILED ",g_mlStatus);return;}
   ulong start=GetTickCount64();
   while(g_mlExport&&!IsStopped()&&GetTickCount64()-start<240000)
   {ProcessQueuedHistoricalRedraw();ProcessHistoricalAuditStep();OrbMlExportStep();Sleep(1);}
   if(g_mlExport){OrbMlAbort("PROBE TIMEOUT");return;}
   OrbMlRefreshFiles(true);
   if(OrbMlSelectedDataset()==""){Print("ORB_ML_DASH_PROBE DATASET BROWSE FAILED ",g_mlStatus);return;}
   g_strategyPresetIndex=7;OrbMlRefreshFiles(true);
   if(ArraySize(g_mlDatasets)!=0){Print("ORB_ML_DASH_PROBE CROSS_STRATEGY DATA LEAK");return;}
   g_strategyPresetIndex=selected;OrbMlRefreshFiles(true);
   Print("ORB_ML_DASH_PROBE DATASET_ISOLATION PASS count=",ArraySize(g_mlDatasets));
   if(!OrbMlSubmitJob("TRAIN")){Print("ORB_ML_DASH_PROBE TRAIN SUBMIT FAILED ",g_mlJobNote);return;}
   string job=OrbMlSelectedJob(),status[],previous="";
   start=GetTickCount64();bool complete=false;
   while(!IsStopped()&&GetTickCount64()-start<120000)
   {
      if(OrbMlJobStatus(job,status))
      {
         if(status[5]+status[6]!=previous){Print("ORB_ML_DASH_PROBE JOB ",status[5]," ",status[6],"% ",status[8]);previous=status[5]+status[6];}
         if(status[5]=="READY"||status[5]=="REJECTED"){complete=true;break;}
         if(status[5]=="FAILED"||status[5]=="CANCELLED")break;
      }
      Sleep(100);
   }
   if(!complete){Print("ORB_ML_DASH_PROBE TRAIN FAILED/TIMEOUT");return;}
   if(status[5]=="READY")
   {
      if(!OrbMlSubmitJob("PUBLISH",job)){Print("ORB_ML_DASH_PROBE PUBLISH FAILED ",g_mlJobNote);return;}
      start=GetTickCount64();bool published=false;
      while(!IsStopped()&&GetTickCount64()-start<15000)
      {if(OrbMlJobStatus(g_mlPublishJob,status)&&status[5]=="PUBLISHED"){published=true;break;}Sleep(100);}
      if(!published||!OrbMlLoad()||!g_mlModel.ready||g_mlEnabled){Print("ORB_ML_DASH_PROBE MODEL LOAD FAILED");return;}
      Print("ORB_ML_DASH_PROBE PUBLISH_LOAD PASS (test root only; filter remains OFF)");
   }
   else Print("ORB_ML_DASH_PROBE QUALITY_REJECTION PASS (research only, no model installed)");
   Print("ORB_ML_DASH_PROBE COMPLETE PASS");
   EventKillTimer();
}
'@
function Isolate([string]$text){
    $text=$text.Replace('"OrbML\\','"OrbMLTests\\Dashboard\\')
    return $text.Replace('"OrbStrategyUserLibrary\\','"OrbMLTests\\Dashboard\\UserStrategies\\')
}
[IO.File]::WriteAllText((Join-Path $dest 'OrbMLDashboardProbe.mq5'),(Isolate $source),[Text.UTF8Encoding]::new($false))
foreach($file in Get-ChildItem -LiteralPath $seed -Filter '*.mqh'){
    [IO.File]::WriteAllText((Join-Path $dest $file.Name),(Isolate ([IO.File]::ReadAllText($file.FullName))),[Text.UTF8Encoding]::new($false))
}
[IO.File]::WriteAllText((Join-Path $dest '.gitignore'),"*`n")
$ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbMLDashboardProbe\OrbMLDashboardProbe`r`nSymbol=JP225m`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $root 'tmp/orb_ml_probe/dashboard.ini'),$ini)
Write-Output 'Dashboard probe prepared: isolated worker + OrbMLTests/Dashboard files only.'
