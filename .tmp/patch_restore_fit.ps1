$root=Join-Path $PWD 'IndicatorCodeExamples';$utf=New-Object Text.UTF8Encoding($false)
foreach($n in @('LiquidityNarrative_MT5_EA.mq5','LiquidityNarrative_Invert_MT5_EA.mq5','LiqNarrativeSolVersion.mq5','LiqNarrativeSol_Advanced.mq5')){
$p=Join-Path $root $n;$s=[IO.File]::ReadAllText($p);$s=[regex]::Replace($s,'(void OnChartEvent\(const int id, const long &lparam, const double &dparam, const string &sparam\)\s*\{)','$1'+"`r`n"+'   if(id==CHARTEVENT_CHART_CHANGE){DrawDashboard();ChartRedraw(0);return;}');[IO.File]::WriteAllText($p,$s,$utf)}
$p=Join-Path $root 'macrossover_orb/OrbStrategyUserLibrary.mqh';$s=[IO.File]::ReadAllText($p);$s=$s.Replace('bool g_userLoaded=false;', 'bool g_userLoaded=false;bool g_maRestoringPreset=false,g_maPresetModeRestored=false;')
$s=$s.Replace('   if(!MaIndependentApply(g_userStrategies[i].independent,g_userStrategies[i].maxSeries))','   if(g_maRestoringPreset){g_maIndependent=g_userStrategies[i].independent;g_maMaxConsecutive=g_userStrategies[i].maxSeries;g_maPresetModeRestored=true;}'+"`r`n"+'   else if(!MaIndependentApply(g_userStrategies[i].independent,g_userStrategies[i].maxSeries))')
[IO.File]::WriteAllText($p,$s,$utf)
$p=Join-Path $root 'macrossover_orb/MaIndependentEntries.mqh';$s=[IO.File]::ReadAllText($p)
# These declarations must precede the user-library include.
$s=$s.Replace('bool g_maIndependent=false;','bool g_maIndependent=false;'+"`r`n"+'bool g_maRestoringPreset=false,g_maPresetModeRestored=false;')
$s=$s.Replace('   g_maIndependent=InpIndependentEntries;g_maMaxConsecutive=InpMaxConsecutiveEntries;', '   if(!g_maPresetModeRestored){g_maIndependent=InpIndependentEntries;g_maMaxConsecutive=InpMaxConsecutiveEntries;}')
$s=$s.Replace('   if(GlobalVariableCheck(key))', '   if(!g_maPresetModeRestored&&GlobalVariableCheck(key))')
[IO.File]::WriteAllText($p,$s,$utf)
$p=Join-Path $root 'macrossover_orb/OrbStrategyUserLibrary.mqh';$s=[IO.File]::ReadAllText($p).Replace('bool g_userLoaded=false;bool g_maRestoringPreset=false,g_maPresetModeRestored=false;','bool g_userLoaded=false;');[IO.File]::WriteAllText($p,$s,$utf)
$p=Join-Path $root 'macrossover_orb/MaCrossOverOrbEA.mq5';$s=[IO.File]::ReadAllText($p).Replace('   OrbStrategyPresetRestore();','   g_maRestoringPreset=true;OrbStrategyPresetRestore();g_maRestoringPreset=false;');[IO.File]::WriteAllText($p,$s,$utf)
# Old built-in selection must not report applied under a custom clock.
$p=Join-Path $root 'OrbUltimateEA_StrategyLibrary.mq5';$s=[IO.File]::ReadAllText($p).Replace('if(MathAbs(OrbBrokerOffsetHours())>0.0000001)return false;','if(MathAbs(OrbBrokerOffsetHours())>0.0000001||OrbBrokerClockKey()!="")return false;');[IO.File]::WriteAllText($p,$s,$utf)
