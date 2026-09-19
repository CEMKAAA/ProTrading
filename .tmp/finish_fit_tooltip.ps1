$utf=New-Object Text.UTF8Encoding($false);$root=Join-Path $PWD 'IndicatorCodeExamples'
foreach($n in @('LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')){
$p=Join-Path $root $n;$s=[IO.File]::ReadAllText($p);$s=[regex]::Replace($s,'(void OnChartEvent\(const int id, const long &lparam, const double &dparam, const string &sparam\)\s*\{)','$1'+"`r`n"+'   if(id==CHARTEVENT_CHART_CHANGE){DrawDashboard();ChartRedraw(0);return;}');[IO.File]::WriteAllText($p,$s,$utf)}
$p=Join-Path $root 'macrossover_orb/MaCrossOverOrbEA.mq5';$s=[IO.File]::ReadAllText($p)
$s=$s.Replace('      DrawOrbHistoricalSegment(levelId+"_ENTRY",levelStart,levelEnd,sim.simEntry,C''230,230,230'',STYLE_SOLID);', '      DrawOrbHistoricalSegment(levelId+"_ENTRY",levelStart,levelEnd,sim.simEntry,C''230,230,230'',STYLE_SOLID);'+"`r`n"+'      ObjectSetString(0,HistoricalObjectRoot()+"LVL_"+levelId+"_ENTRY",OBJPROP_TOOLTIP,'+"`r`n"+'         "SIMULATED FILL (not signal close): "+DoubleToString(sim.simEntry,_Digits)+" | BUY enters ASK; SELL enters BID. Signal bar: "+FmtTime(sigT));')
$s=$s.Replace('+" F="+DoubleToString(sim.simEntry,_Digits)', '+" FILL="+DoubleToString(sim.simEntry,_Digits)')
[IO.File]::WriteAllText($p,$s,$utf)
$p=Join-Path $PWD 'scripts/validate_clock_save_ui.ps1';$s=[IO.File]::ReadAllText($p).Replace("'LiqNarrativeSol_Advanced.mq5')","'LiqNarrativeSol_Advanced.mq5','LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')");[IO.File]::WriteAllText($p,$s,$utf)
