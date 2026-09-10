$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build_orb_ml_export_probe.ps1')
$root=Split-Path -Parent $PSScriptRoot
$seed=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLExportProbe'
$dest=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbPresetEditProbe'
[IO.Directory]::CreateDirectory($dest) | Out-Null
$source=[IO.File]::ReadAllText((Join-Path $seed 'OrbMLExportProbe.mq5'))
$source=$source.Substring(0,$source.LastIndexOf('void OnStart()'))
$source+=@'
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   OrbStrategyPreset p;bool found=false;
   for(int i=0;i<OrbBuiltinStrategyPresetCount();i++)
      if(OrbBuiltinStrategyPresetLoad(i,p)&&p.id=="jp_025_8000"){found=true;break;}
   if(!found){Print("ORB_EDIT_PROBE FAIL preset missing");return;}
   CreateEdit("EDIT_SL_VALUE",20,20,100,20,"100");
   CreateEdit("EDIT_RISK_PCT",20,50,100,20,"0.30");
   CreateEdit("EDIT_NAS_EXIT_WAIT",20,80,100,20,"05:00");
   OrbStrategyPresetApplyValues(p);
   bool ok=g_rtPipSlMode&&g_rtPipSlPips==8000.0
      &&ObjectGetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT)=="8000.0"
      &&ObjectGetString(0,PREFIX+"EDIT_RISK_PCT",OBJPROP_TEXT)=="0.30"
      &&ObjectGetString(0,PREFIX+"EDIT_NAS_EXIT_WAIT",OBJPROP_TEXT)==DurationMinutesText(g_rtNasOppositeExitWaitMinutes);
   ObjectSetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT,"9000");
   CreateEdit("EDIT_SL_VALUE",20,20,100,20,"8000.0");
   ok=ok&&ObjectGetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT)=="9000";
   g_rtPipSlMode=false;g_rtSlDistancePct=75;OrbStrategyPresetSyncEdits();
   ok=ok&&ObjectGetString(0,PREFIX+"EDIT_SL_VALUE",OBJPROP_TEXT)=="75";
   CreateEdit("EDIT_PRESET_GEOMETRY",20,110,100,20,"0,05");
   ok=ok&&OrbStrategyApplyMetricFilters()&&g_strategyFilterGeometryEnabled&&g_strategyFilterGeometry==0.05;
   p.targetMode=ORB_TARGET_R_LEG;p.targetLeg=(int)ORB_TARGET_R005;p.invertMode=false;p.metric1yReady=false;
   ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   g_strategyFilterGeometry=0.5;ok=ok&&!OrbStrategyPresetPassesMetricFilters(p);
   p.targetLeg=1;ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   p.invertMode=true;ok=ok&&!OrbStrategyPresetPassesMetricFilters(p);
   g_strategyFilterGeometry=2;ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   g_strategyFilterWrEnabled=true;g_strategyFilterWr=60;
   ok=ok&&!OrbStrategyPresetPassesMetricFilters(p);
   p.metric1yReady=true;p.metric1yWr=65;ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   p.metric1yWr=55;ok=ok&&!OrbStrategyPresetPassesMetricFilters(p);
   ObjectSetString(0,PREFIX+"EDIT_PRESET_GEOMETRY",OBJPROP_TEXT,"bad");
   ok=ok&&!OrbStrategyApplyMetricFilters()&&g_strategyFilterGeometry==2;
   ObjectSetString(0,PREFIX+"EDIT_PRESET_GEOMETRY",OBJPROP_TEXT,"");
   ok=ok&&OrbStrategyApplyMetricFilters()&&!g_strategyFilterGeometryEnabled;
   Print("ORB_GEOMETRY_FILTER_PROBE ",ok?"PASS":"FAIL"," 0.05/comma/0.5/inversion/WR/invalid/blank");
   g_strategyFilterFamily=ORB_PRESET_FAMILY_JP225;
   p.family=ORB_PRESET_FAMILY_JP225;p.metric1yReady=false;
   ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   p.family=ORB_PRESET_FAMILY_USDJPY;ok=ok&&!OrbStrategyPresetPassesMetricFilters(p);
   g_strategyFilterFamily=ORB_PRESET_FAMILY_USDJPY;ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   g_strategyFilterGeometryEnabled=true;g_strategyFilterGeometry=0.5;
   p.invertMode=false;p.targetLeg=1;ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   p.family=ORB_PRESET_FAMILY_JP225;ok=ok&&!OrbStrategyPresetPassesMetricFilters(p);
   g_strategyFilterFamily=ORB_PRESET_FAMILY_ANY;ok=ok&&OrbStrategyPresetPassesMetricFilters(p);
   g_strategyFilterGeometryEnabled=false;
   Print("ORB_SYMBOL_FILTER_PROBE ",ok?"PASS":"FAIL"," JP225/USDJPY/ALL + geometry; no metrics required");
   ObjectDelete(0,PREFIX+"EDIT_PRESET_GEOMETRY");
   Print("ORB_EDIT_PROBE ",ok?"PASS":"FAIL"," preset 8000; drafts preserved; risk unchanged; percent mode synced");
   ObjectDelete(0,PREFIX+"EDIT_SL_VALUE");ObjectDelete(0,PREFIX+"EDIT_RISK_PCT");ObjectDelete(0,PREFIX+"EDIT_NAS_EXIT_WAIT");
}
'@
[IO.File]::WriteAllText((Join-Path $dest 'OrbPresetEditProbe.mq5'),$source,[Text.UTF8Encoding]::new($false))
Copy-Item -Path (Join-Path $seed '*.mqh') -Destination $dest -Force
[IO.File]::WriteAllText((Join-Path $dest '.gitignore'),"*`n")
$ini="[Experts]`r`nEnabled=0`r`nAllowDllImport=0`r`n[StartUp]`r`nScript=OrbPresetEditProbe\OrbPresetEditProbe`r`nSymbol=JP225m`r`nPeriod=M5`r`nShutdownTerminal=1`r`n"
[IO.File]::WriteAllText((Join-Path $root 'tmp/orb_ml_probe/preset_edit.ini'),$ini)
