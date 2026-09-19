$root=Join-Path $PWD 'IndicatorCodeExamples';$utf=New-Object Text.UTF8Encoding($false)
foreach($r in @('OrbUltimateEA.mq5','OrbUltimateEA_StrategyLibrary.mq5','macrossover_orb/MaCrossOverOrbEA.mq5')){
$p=Join-Path $root $r;$s=[IO.File]::ReadAllText($p)
$s=$s.Replace('   MqlRates r[];int c=CopyRates(_Symbol,entryTf,sigTime,tradeEnd,r);', '   ResetLastError();'+"`r`n"+'   MqlRates r[];int c=CopyRates(_Symbol,entryTf,sigTime,tradeEnd,r);'+"`r`n"+'   int ratesError=GetLastError();'+"`r`n"+'   if(ratesError!=0){res.invalidReason="BAR_HISTORY_PENDING";return res;}')
$s=$s.Replace('   int fillBarIndex=(g_btFillMode==BT_FILL_SIGNAL_CLOSE?0:1);', '   int signalSeconds=PeriodSeconds(entryTf);if(signalSeconds<=0)signalSeconds=60;'+"`r`n"+'   if(r[0].time>sigTime||r[0].time+signalSeconds<=sigTime){res.invalidReason="BAR_HISTORY_PREFIX_MISSING";return res;}'+"`r`n"+'   int fillBarIndex=(g_btFillMode==BT_FILL_SIGNAL_CLOSE?0:1);')
[IO.File]::WriteAllText($p,$s,$utf)
}
