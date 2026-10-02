$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=(Get-Content (Join-Path $root '.tmp/native_balance_stage.txt') -Raw).Trim()
'pending'|Set-Content (Join-Path $stage 'balance_verified.txt')
Copy-Item (Join-Path $root 'IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5') (Join-Path $stage 'orb/OrbUltimateEA_StrategyLibrary.mq5') -Force
Copy-Item (Join-Path $root 'IndicatorCodeExamples/orb/OrbStrategyMLPipeline.mqh') (Join-Path $stage 'orb/OrbStrategyMLPipeline.mqh') -Force
Copy-Item (Join-Path $root 'tests/mql5/NativeMarginChecks.mqh') (Join-Path $stage 'orb/NativeMarginChecks.mqh') -Force
$name=(Get-Content (Join-Path $stage 'orb.name') -Raw).Trim()
foreach($relative in @('orb/OrbUltimateEA_StrategyLibrary.mq5',('orb/'+$name+'.mq5'))){
 $src=Join-Path $stage $relative;$log=$src+'.log'
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$src+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 Get-Content $log -Tail 1
 if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Compile failed'}
}
& (Join-Path $root 'scripts/validate_native_balance.ps1') -RunPrepared -Symbol JP225m
& (Join-Path $root 'scripts/validate_native_balance.ps1') -RunPrepared -Symbol USDJPYm
