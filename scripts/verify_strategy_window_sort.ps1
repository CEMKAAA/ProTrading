param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'reports/strategy_window_ui_20261009'
$build=Join-Path $report 'build'
$worker=Join-Path $root '.tmp/sol_selection_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal){throw 'Dedicated test worker busy'}
$folders=@('orb','macrossover_orb','entry_engine_lab','SolAdvanced')
$hashes=@($folders|ForEach-Object {(Get-FileHash (Join-Path $root ('IndicatorCodeExamples/'+$_+'/StrategyWindowMetrics.mqh'))).Hash}|Select-Object -Unique)
if($hashes.Count-ne 1){throw 'Four EA sorting implementations differ; test each before release'}
$files=@('IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5','IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5',
 'IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5','IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5','tests/mql5/StrategyWindowSortProbe.mq5')
$seen=@{}
function Stage([string]$file){
 $file=[IO.Path]::GetFullPath($file)
 if(!$file.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'External quoted include'}
 if($seen.ContainsKey($file)){return};$seen[$file]=$true
 $dest=Join-Path $build $file.Substring($root.Length+1)
 New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath $file -Destination $dest -Force
 foreach($include in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){Stage (Join-Path (Split-Path $file) $include.Groups[1].Value)}
}
foreach($relative in $files){Stage (Join-Path $root $relative)}
foreach($relative in $files){
 $file=Join-Path $build $relative;$log=Join-Path $report ((Split-Path $file -Leaf)+'.log');$start=Get-Date
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 if(!(Test-Path $log)-or (Get-Item $log).LastWriteTime-lt $start.AddSeconds(-2)-or (Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){
  if(Test-Path $log){Get-Content $log -Tail 35};throw "Compile failed: $relative"
 }
 Write-Output "COMPILE $relative : 0 errors, 0 warnings"
}
Copy-Item -LiteralPath (Join-Path $build 'tests/mql5/StrategyWindowSortProbe.ex5') -Destination (Join-Path $worker 'MQL5/Scripts/StrategyWindowSortProbe.ex5') -Force
$ini=Join-Path $report 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=StrategyWindowSortProbe','Symbol=BTCUSDm','Period=M1','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'Dedicated sort probe timeout; no campaign process was stopped'}
$path=Join-Path $worker 'MQL5/Files/StrategyWindowSortProbe.txt'
if(!(Test-Path $path)-or (Get-Item $path).LastWriteTime-lt $start.AddSeconds(-2)){throw 'Fresh native test result missing'}
$text=Get-Content $path -Raw;Copy-Item -LiteralPath $path -Destination $report -Force;Write-Output $text
if($text-notmatch '\bfailed=0\b'-or $text-notmatch '\border_attempts=0\b'){throw 'Native sorting regression failed'}
@{checkedAt=(Get-Date -Format o);compile='0 errors, 0 warnings';behavior="$text";sortImplementation=$hashes[0];
 binaries=@($files|ForEach-Object {$relative=[IO.Path]::ChangeExtension($_,'.ex5');@{relative=$relative;sha256=(Get-FileHash (Join-Path $build $relative)).Hash}});
 files=@($seen.Keys|ForEach-Object {@{relative=$_.Substring($root.Length+1);sha256=(Get-FileHash $_).Hash}})
}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $report 'verification.json') -Encoding UTF8
