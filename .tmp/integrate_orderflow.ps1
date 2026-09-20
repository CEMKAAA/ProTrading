$ErrorActionPreference='Stop'
$p='IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5'
$s=[IO.File]::ReadAllText((Join-Path $PWD $p))
function Replace-One([string]$old,[string]$new){if(!$script:s.Contains($old)){throw "missing: $old"};$script:s=$script:s.Replace($old,$new)}
Replace-One '#include "MaCrossAuditCache.mqh"' "#include `"MaCrossAuditCache.mqh`"`r`n#include `"MaCrossOrderFlow.mqh`""
Replace-One "int OnInit()`r`n{" "int OnInit()`r`n{`r`n   if(!McOfInit())return INIT_PARAMETERS_INCORRECT;"
Replace-One '   if(!requireDisp&&fvgMode==ORB_FVG_OFF)return true;' "   // Shared gate: both audit and live pass the effective (possibly inverted) direction.`r`n   string ofDetail=`"`";`r`n   if(!McOfFilter(_Symbol,tf,sigT,EffectiveOrbDirection(dir)==`"BUY`"?1:-1,reason,ofDetail)){detail=ofDetail;return false;}`r`n   if(!requireDisp&&fvgMode==ORB_FVG_OFF){detail=ofDetail;return true;}"
Replace-One '   AnalyzeModernSetup(from,to,tf,sigT,dir,hasDisp,hasFvg,detail);' "   AnalyzeModernSetup(from,to,tf,sigT,dir,hasDisp,hasFvg,detail);`r`n   if(ofDetail!=`"`")detail+=`" `"+ofDetail;"
# Order-flow is entry-only: do not turn its rejected candidates into exit events.
Replace-One "void HandleFilteredWindowSignal(string rawDir,datetime signalTime,double signalClose,string reason,string detail=`"`")`r`n{" "void HandleFilteredWindowSignal(string rawDir,datetime signalTime,double signalClose,string reason,string detail=`"`")`r`n{`r`n   if(StringFind(reason,`"OF_`")==0){g_lastFilterReason=reason;g_lastExecStatus=reason;Audit(`"orderflow_reject`",rawDir,0,signalClose,0,0,detail);return;}"
Replace-One "                           double sigC,double sigH,double sigL)`r`n{" "                           double sigC,double sigH,double sigL)`r`n{`r`n   if(StringFind(reason,`"OF_`")==0)return;"
# Separate memo identities without changing default OFF identity.
Replace-One '   key+="|g_rtFilterVol="+(string)g_rtFilterVol;' "   key+=McOfIdentity();`r`n   key+=`"|g_rtFilterVol=`"+(string)g_rtFilterVol;"
Replace-One '   int cached=g_orbPrepMemo.Find(key);' '   int cached=g_mcOf.mode!=0?-1:g_orbPrepMemo.Find(key);'
Replace-One '   if(snapshot.known&&snapshot.valid&&snapshot.operationalKnown&&snapshot.tradeEnd>0' '   if(g_mcOf.mode==0&&snapshot.known&&snapshot.valid&&snapshot.operationalKnown&&snapshot.tradeEnd>0'
Replace-One '   OrbStrategyPresetSyncSelection();' "   CreateButton(`"BTN_ORDERFLOW`",InpDashboardX+460,InpDashboardY+10,146,17,McOfModeName(),g_mcOf.mode==0?C'80,80,80':C'30,120,70');`r`n   ObjectSetString(0,PREFIX+`"BTN_ORDERFLOW`",OBJPROP_TOOLTIP,`"OFF -> BREAKOUT -> REJECTION -> EITHER. Bid tick proxy, not exchange volume. Parameters: EA Inputs / ORDER FLOW. `"+g_mcOfStatus);`r`n   OrbStrategyPresetSyncSelection();"
Replace-One '   bool needRedraw=false;' "   if(sparam==PREFIX+`"BTN_ORDERFLOW`")`r`n   {`r`n      g_mcOf.mode=(g_mcOf.mode+1)%4;McOfReset();CancelHistoricalAuditBuild();`r`n      g_histNeedsRedraw=true;QueueHistoricalRedraw(0);`r`n      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return;`r`n   }`r`n   bool needRedraw=false;"
# Never label incomplete tick audit as a complete result.
Replace-One '   g_histStatLine=IntegerToString(ArraySize(g_maCrossAuditEvents))' '   g_histStatLine=(g_mcOf.mode!=0&&g_mcOfDataIncomplete?"INCOMPLETE ORDER FLOW DATA | ":"")+IntegerToString(ArraySize(g_maCrossAuditEvents))'
[IO.File]::WriteAllText((Join-Path $PWD $p),$s,[Text.UTF8Encoding]::new($false))
