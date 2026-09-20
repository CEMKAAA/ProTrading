param([switch]$RunProbe,[switch]$Feed)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tag=Get-Date -Format yyyyMMdd_HHmmss
$stage=Join-Path $root ".tmp/ma_orderflow_$tag"
$src=Join-Path $stage 'IndicatorCodeExamples/macrossover_orb'
$test=Join-Path $stage 'tests/mql5'
New-Item -ItemType Directory -Force $src,$test | Out-Null
Copy-Item (Join-Path $root 'IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlowCore.mqh') $src
Copy-Item (Join-Path $root 'IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlow.mqh') $src
Copy-Item (Join-Path $root 'IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlowWorker.mq5') $src
$name=if($Feed){'MaOrderFlowFeedProbe'}else{'MaOrderFlowProbe'}
$extension=if($Feed){'txt'}else{'json'}
$text=[IO.File]::ReadAllText((Join-Path $root "tests/mql5/$name.mq5"))
$output="${tag}_${name}.$extension"
$text=$text.Replace('"'+$name+'.'+$extension+'"','"'+$output+'"')
$file=Join-Path $test "$name.mq5"
[IO.File]::WriteAllText($file,$text,[Text.UTF8Encoding]::new($false))
$log="$file.log"
if($Feed){
 $wf=Join-Path $src 'MaCrossOrderFlowWorker.mq5';$wl="$wf.log"
 $wp=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$wf+'" /log:"'+$wl+'"') -WindowStyle Hidden -PassThru
 if(!$wp.WaitForExit(120000)){throw 'worker compile timeout'}
 if(!(Test-Path $wl) -or (Get-Content $wl -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $wl -Tail 25;throw 'worker compile failed'}
}
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'compiler timeout'}
if(!(Test-Path $log) -or (Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){
 Get-Content $log -Tail 25;throw 'compile failed'
}
Get-Content $log -Tail 1
if($RunProbe){
 $worker=Join-Path $root '.tmp/orb_jp225_full_worker'
 $terminal=Join-Path $worker 'terminal64.exe'
 if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object ExecutablePath -eq $terminal).Count){throw 'isolated worker busy; retry after regression suite'}
 if($Feed){Copy-Item (Join-Path $src 'MaCrossOrderFlowWorker.ex5') (Join-Path $worker 'MQL5/Scripts/MaCrossOrderFlowWorker.ex5')}
 $run="${name}_$tag"
 Copy-Item ([IO.Path]::ChangeExtension($file,'.ex5')) (Join-Path $worker "MQL5/Scripts/$run.ex5")
 $ini=Join-Path $stage 'probe.ini'
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',"Script=$run",'Symbol=JP225m','Period=M5','ShutdownTerminal=1') | Set-Content $ini -Encoding ASCII
 $start=Get-Date
 $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'probe timeout'}
 $result=Join-Path $worker "MQL5/Files/$output"
 if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $start){throw 'missing fresh result'}
 Copy-Item $result $stage
 Get-Content $result -Raw
 if(!$Feed){$r=Get-Content $result -Raw | ConvertFrom-Json;if($r.failed -ne 0){throw 'probe failed'}}
}
Write-Output "STAGE=$stage"
