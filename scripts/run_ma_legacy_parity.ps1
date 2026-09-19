param([ValidateSet('baseline','candidate')][string]$Phase='baseline',[string[]]$Symbols=@('JP225m','XAUUSDm','BTCUSDm','USDJPYm','USOILm','SOLUSDm'))
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$campaign=Join-Path $root 'logs/ma_legacy_parity_20260919'
$stage=Join-Path $campaign $Phase;$src=Join-Path $stage 'IndicatorCodeExamples/macrossover_orb'
$testDir=Join-Path $stage 'tests/mql5';New-Item -ItemType Directory -Force $src,$testDir|Out-Null
if($Phase -eq 'candidate'){Get-ChildItem (Join-Path $root 'IndicatorCodeExamples/macrossover_orb') -File|Where-Object {$_.Extension -in '.mqh','.mq5'}|Copy-Item -Destination $src}
$ea=Join-Path $src 'MaCrossOverOrbEA.mq5'
$text=[IO.File]::ReadAllText($ea)
if(!$text.Contains('ProbeTrade(entryT')){$text=$text.Replace('      g_histTotal++;','      ProbeTrade(entryT,execDir,sim);'+"`r`n"+'      g_histTotal++;')}
[IO.File]::WriteAllText($ea,$text,[Text.UTF8Encoding]::new($false))
$tag=Get-Date -Format yyyyMMdd_HHmmss;$run='MaLegacyParity_'+$Phase+'_'+$tag
$probe=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/MaLegacyParityProbe.mq5')).Replace('MaLegacyParity.jsonl',"$run.jsonl")
if($Phase -eq 'candidate'){$probe="#define MA_MIGRATION_CANDIDATE`r`n"+$probe}
$file=Join-Path $testDir "$run.mq5";[IO.File]::WriteAllText($file,$probe,[Text.UTF8Encoding]::new($false))
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$file+'.log"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'compile timeout'}
if((Get-Content "$file.log" -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content "$file.log" -Tail 25;throw 'compile failed'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
New-Item -ItemType Directory -Force "$worker/MQL5/Files/MaLegacyParity"|Out-Null
Copy-Item "$campaign/presets/*.preset" "$worker/MQL5/Files/MaLegacyParity"
Copy-Item ([IO.Path]::ChangeExtension($file,'.ex5')) "$worker/MQL5/Scripts/$run.ex5"
foreach($symbol in $Symbols){
 if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal).Count){throw 'Worker busy'}
 $ini=Join-Path $stage "$symbol.ini"
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',"Script=$run","Symbol=$symbol",'Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
 $started=Get-Date;$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(1800000)){throw "Replay timeout: $symbol"}
 $result="$worker/MQL5/Files/$run.jsonl"
 if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started){throw 'No fresh result'}
 Copy-Item $result (Join-Path $stage "$symbol.jsonl")
 Get-Content $result|Where-Object {$_ -match '"kind":"(summary|error)"'}
}
Write-Output "RESULTS=$stage"
