param([string]$Editor='C:\MT5\DEMO\MetaEditor64.exe',[switch]$RunProbe,[switch]$ProbeOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$calendarCopies=@('TradeCalendarMatrix.mqh','orb/TradeCalendarMatrix.mqh','macrossover_orb/TradeCalendarMatrix.mqh','SolAdvanced/TradeCalendarMatrix.mqh')
$calendarHashes=@($calendarCopies|ForEach-Object{(Get-FileHash -LiteralPath (Join-Path $source $_)).Hash}|Select-Object -Unique)
if($calendarHashes.Count -ne 1){throw 'TradeCalendarMatrix copies differ; synchronize all four before compiling'}
foreach($retired in @('OrbUltimateEA_StrategyLibrary.mq5','LiqNarrativeSol_Advanced.mq5')){
 if(Test-Path -LiteralPath (Join-Path $source $retired)){throw "Retired root EA was reintroduced: $retired"}
}
$stage=Join-Path $root ('.tmp/time_matrix_compile_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$seen=@{}
function StageSource([string]$path){
 $path=[IO.Path]::GetFullPath($path)
 if(!$path.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "External include: $path"}
 if($seen.ContainsKey($path)){return}
 $seen[$path]=$true
 $relative=$path.Substring($source.Length+1)
 $destination=Join-Path $stage $relative
 New-Item -ItemType Directory -Path (Split-Path $destination) -Force|Out-Null
 Copy-Item -LiteralPath $path -Destination $destination
 foreach($match in [regex]::Matches([IO.File]::ReadAllText($path),'(?m)^\s*#include\s+"([^"]+)"')){
  StageSource (Join-Path (Split-Path $path) $match.Groups[1].Value)
 }
}
$eas=@('orb/OrbUltimateEA_StrategyLibrary.mq5','macrossover_orb/MaCrossOverOrbEA.mq5','SolAdvanced/LiqNarrativeSol_Advanced.mq5')
foreach($ea in $eas){StageSource (Join-Path $source $ea)}
if($ProbeOnly){$RunProbe=$true}
foreach($ea in $(if($ProbeOnly){@()}else{$eas})){
 $file=Join-Path $stage $ea
 $log=$file+'.log'
 $started=Get-Date
 $process=Start-Process $Editor -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$process.WaitForExit(180000)){throw "Compile timeout: $ea"}
 if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $started){throw "Fresh log missing: $ea"}
 $result=Get-Content $log -Tail 1
 Write-Output "$ea : $result"
 if($result -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 35;throw "Compile failed: $ea"}
}
if($RunProbe){
 $worker=Join-Path $root '.tmp/orb_jp225_full_worker'
 $terminal=Join-Path $worker 'terminal64.exe'
 if(!(Test-Path $terminal)){throw 'Isolated MT5 worker is missing'}
 $sourceProbe=Join-Path $root 'tests/mql5/TradeCalendarMatrixProbe.mq5'
 $probe=Join-Path $stage 'tests/mql5/TradeCalendarMatrixProbe.mq5'
 New-Item -ItemType Directory -Path (Split-Path $probe) -Force|Out-Null
 $name='TradeCalendarMatrixProbe_'+(Get-Date -Format HHmmss)
 $probeText=[IO.File]::ReadAllText($sourceProbe).Replace('TradeCalendarMatrixProbe.json',$name+'.json')
 [IO.File]::WriteAllText($probe,$probeText,(New-Object Text.UTF8Encoding($false)))
 Copy-Item -LiteralPath (Join-Path $source 'TradeCalendarMatrix.mqh') -Destination (Join-Path $stage 'TradeCalendarMatrix.mqh')
 Copy-Item -LiteralPath (Join-Path $source 'DailyTradeQuota.mqh') -Destination (Join-Path $stage 'DailyTradeQuota.mqh')
 $log=$probe+'.log'
 $process=Start-Process $Editor -ArgumentList ('/compile:"'+$probe+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$process.WaitForExit(180000)){throw 'Calendar probe compile timeout'}
 if([IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 30;throw 'Calendar probe compile failed'}
 Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $stage 'probe.ini'
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
 $started=Get-Date
 $process=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$process.WaitForExit(180000)){throw 'Calendar probe timeout'}
 $result=Join-Path $worker ('MQL5/Files/'+$name+'.json')
 if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh calendar probe result missing'}
 $data=Get-Content $result -Raw|ConvertFrom-Json
 Write-Output "MQL_PROBE=$($data.checks) checks, $($data.failed) failures"
 if($data.checks -lt 7 -or $data.failed -ne 0){throw 'Calendar probe failed'}
 foreach($probeName in @('OrbClockSaveProbe','MaTimeMatrixStrategyProbe','LiqTimeMatrixStrategyProbe')){
  $sourceText=[IO.File]::ReadAllText((Join-Path $root ('tests/mql5/'+$probeName+'.mq5')))
  $sourceText=$sourceText.Replace('../../IndicatorCodeExamples/','../../')
  $sourceText=$sourceText.Replace('../../OrbUltimateEA_StrategyLibrary.mq5','../../orb/OrbUltimateEA_StrategyLibrary.mq5')
  $unique=$probeName+'_'+(Get-Date -Format HHmmss)
  $sourceText=$sourceText.Replace($probeName+'.json',$unique+'.json')
  $probePath=Join-Path $stage ('tests/mql5/'+$unique+'.mq5')
  [IO.File]::WriteAllText($probePath,$sourceText,(New-Object Text.UTF8Encoding($false)))
  $probeLog=$probePath+'.log'
  $process=Start-Process $Editor -ArgumentList ('/compile:"'+$probePath+'" /log:"'+$probeLog+'"') -WindowStyle Hidden -PassThru
  if(!$process.WaitForExit(180000)){throw "Strategy probe compile timeout: $probeName"}
  if(!(Test-Path $probeLog) -or [IO.File]::ReadAllText($probeLog) -notmatch 'Result: 0 errors, 0 warnings')
  {Get-Content $probeLog -Tail 30;throw "Strategy probe compile failed: $probeName"}
  Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probePath,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$unique+'.ex5'))
  $probeIni=Join-Path $stage ($unique+'.ini')
  @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$unique),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content -LiteralPath $probeIni -Encoding ASCII
  $started=Get-Date
  $process=Start-Process $terminal -ArgumentList ('/portable /config:"'+$probeIni+'"') -WindowStyle Hidden -PassThru
  if(!$process.WaitForExit(180000)){throw "Strategy probe timeout: $probeName"}
  $result=Join-Path $worker ('MQL5/Files/'+$unique+'.json')
  if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started.AddSeconds(-2))
  {throw "Fresh strategy probe result missing: $probeName"}
  $data=Get-Content $result -Raw|ConvertFrom-Json
  Write-Output "$probeName=$($data.checks) checks, $($data.failed) failures"
  if($data.failed -ne 0){throw "Strategy probe failed: $probeName"}
 }
}
Write-Output "STAGE=$stage"
