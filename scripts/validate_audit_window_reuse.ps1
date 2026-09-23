$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$files=@('OrbUltimateEA.mq5','orb/OrbUltimateEA_StrategyLibrary.mq5','NasUltimate_StrategyLibrary.mq5','NasUltimate_SATS_PartialNoBE_EA.mq5','LiquidityNarrative_MT5_EA.mq5','LiquidityNarrative_Invert_MT5_EA.mq5','LiqNarrativeSolVersion.mq5','SolAdvanced/LiqNarrativeSol_Advanced.mq5','LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')
$report=Join-Path $root 'logs/AuditWindowReuse_20260914'
New-Item -ItemType Directory -Path $report -Force|Out-Null
foreach($name in $files) {
    $source=Join-Path $root ('IndicatorCodeExamples/'+$name)
    $log=Join-Path $report ((Split-Path $name -Leaf)+'.compile.log');$before=Get-Date
    for($attempt=1;$attempt -le 3;$attempt++) {
        $p=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
        if(!$p.WaitForExit(240000)){throw ('Compile timeout: '+$name)}
        if(!(Test-Path $log) -or !([IO.File]::ReadAllText($log).Contains('error 119: EX5 write error'))){break}
        Copy-Item -LiteralPath $log -Destination ($log+'.attempt'+$attempt)
        Start-Sleep -Seconds 2
    }
    if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $before -or !([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){Get-Content $log -Tail 15;throw ('Compile failed: '+$name)}
    Write-Output $name;Get-Content $log -Tail 1
}
