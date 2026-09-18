param([switch]$InstallDemo)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$report=Join-Path $root 'logs/orb_timezone'
New-Item -ItemType Directory -Force $report|Out-Null
$names=@('OrbUltimateEA.mq5','OrbUltimateEA_Channel.mq5','OrbUltimateEA_StrategyLibrary.mq5')
$compile=@($names|ForEach-Object {Join-Path $src $_})
$compile+=Join-Path $root 'tests/mql5/OrbBrokerTimezoneProbe.mq5'
$compile+=Join-Path $root 'tests/mql5/OrbNativeMoneyRiskProbe.mq5'
$compile+=Join-Path $root 'tests/mql5/OrbAdvRamCacheProbe.mq5'
foreach($file in $compile){
 $log=Join-Path $report ((Split-Path $file -Leaf)+'.log');$start=Get-Date
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $start -or [IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){throw "Compile failed: $file"}
 Get-Content $log -Tail 1
}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal).Count){throw 'Isolated worker in use'}
Copy-Item (Join-Path $root 'tests/mql5/OrbBrokerTimezoneProbe.ex5') (Join-Path $worker 'MQL5/Scripts/OrbBrokerTimezoneProbe.ex5')
$ini=Join-Path $report 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=OrbBrokerTimezoneProbe','Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(90000)){throw 'Probe timeout'}
$result=Join-Path $worker 'MQL5/Files/OrbBrokerTimezoneProbe.json'
if((Get-Item $result).LastWriteTime -lt $start){throw 'Stale probe'}
$r=Get-Content $result -Raw|ConvertFrom-Json
if($r.failed -ne 0 -or $r.checks -ne 40311){throw 'Timezone / risk probe failed'}
Copy-Item $result $report;Get-Content $result
$pipeline=[IO.File]::ReadAllText((Join-Path $src 'OrbUltimate_ProfessionalPipeline.mqh'))
if([regex]::IsMatch($pipeline,'(?<!Bridge)RiskBudgetMoney\(|EffRiskPerTradePct\(')){throw 'Native risk leaked into bridge'}
Copy-Item (Join-Path $root 'tests/mql5/OrbNativeMoneyRiskProbe.ex5') (Join-Path $worker 'MQL5/Scripts/OrbNativeMoneyRiskProbe.ex5')
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=OrbNativeMoneyRiskProbe','Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(90000)){throw 'Money risk probe timeout'}
$result=Join-Path $worker 'MQL5/Files/OrbNativeMoneyRiskProbe.json'
if((Get-Item $result).LastWriteTime -lt $start){throw 'Stale money probe'}
$r=Get-Content $result -Raw|ConvertFrom-Json
if($r.failed -ne 0 -or $r.checks -ne 15){throw 'Native money / bridge separation probe failed'}
Copy-Item $result $report;Get-Content $result
Copy-Item (Join-Path $root 'tests/mql5/OrbAdvRamCacheProbe.ex5') (Join-Path $worker 'MQL5/Scripts/OrbAdvRamCacheProbe.ex5')
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=OrbAdvRamCacheProbe','Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(90000)){throw 'Money risk probe timeout'}
$result=Join-Path $worker 'MQL5/Files/OrbAdvRamCacheProbe.json'
if((Get-Item $result).LastWriteTime -lt $start){throw 'Stale RAM cache probe'}
$r=Get-Content $result -Raw|ConvertFrom-Json
if($r.failed -ne 0 -or $r.checks -ne 1002){throw 'RAM cache probe failed'}
Copy-Item $result $report;Get-Content $result
if(!$InstallDemo){return}
$files=@{}
function Add-Source([string]$name){
 if($files.ContainsKey($name)){return};$file=Join-Path $src $name
 if(!(Test-Path $file)){throw "Missing include: $name"};$files[$name]=$file
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){Add-Source $m.Groups[1].Value}
}
foreach($name in $names){Add-Source $name;$files[[IO.Path]::ChangeExtension($name,'.ex5')]=Join-Path $src ([IO.Path]::ChangeExtension($name,'.ex5'))}
$target='C:\MT5\DEMO\MQL5\Experts\orb'
$backup=Join-Path $report ('backup_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Force $backup,$target|Out-Null
foreach($name in $files.Keys){
 $dest=Join-Path $target $name
 if(Test-Path $dest){Copy-Item $dest (Join-Path $backup $name)}
 Copy-Item $files[$name] $dest
 Copy-Item $files[$name] (Join-Path $src ('orb/'+$name))
 if((Get-FileHash $files[$name]).Hash -ne (Get-FileHash $dest).Hash){throw "Hash mismatch: $name"}
}
Write-Output "Verified $($files.Count) files in $target. No running instance changed."
