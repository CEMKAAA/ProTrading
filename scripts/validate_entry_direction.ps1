$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$editor='C:\MT5\DEMO\MetaEditor64.exe'
$eas=@('orb/OrbUltimateEA_StrategyLibrary.mq5','macrossover_orb/MaCrossOverOrbEA.mq5','SolAdvanced/LiqNarrativeSol_Advanced.mq5')
$hashes=@(@('orb','macrossover_orb','SolAdvanced')|ForEach-Object{
 (Get-FileHash (Join-Path $root ('IndicatorCodeExamples/'+$_+'/TradeCalendarMatrix.mqh'))).Hash
}|Select-Object -Unique)
if($hashes.Count -ne 1){throw 'Direction/calendar implementations differ'}
foreach($ea in $eas){
 $file=Join-Path $root ('IndicatorCodeExamples/'+$ea)
 $log=$file+'.direction.log'
 $p=Start-Process $editor -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 $result=Get-Content $log -Tail 1
 if($result -notmatch 'Result: 0 errors, 0 warnings'){throw "Compile failed: $ea $result"}
 Write-Output "$ea : $result"
 $s=[IO.File]::ReadAllText($file)
 if(!$s.Contains('DirectionRecordLoss(') -or !$s.Contains('DirectionLauncher(') -or !$s.Contains('EntryDirectionAllows(')){
  throw "Missing integration: $ea"
 }
}
$probe=Join-Path $root 'tests/mql5/EntryDirectionProbe.mq5'
$log=$probe+'.log'
$p=Start-Process $editor -ArgumentList ('/compile:"'+$probe+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Probe compile timeout'}
if([IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){throw 'Probe compile failure'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq (Join-Path $worker 'terminal64.exe')}){throw 'Worker is already running'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker 'MQL5/Scripts/EntryDirectionProbe.ex5')
$ini=Join-Path $root '.tmp/entry_direction_probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=EntryDirectionProbe','Symbol=USDJPYm','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$started=Get-Date
$p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Probe timeout'}
$result=Join-Path $worker 'MQL5/Files/EntryDirectionProbe.json'
if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started){throw 'Fresh probe result missing'}
$data=Get-Content $result -Raw|ConvertFrom-Json
Write-Output "DIRECTION_PROBE=$($data.checks) checks, $($data.failed) failures"
if($data.failed -ne 0){throw 'Direction contract failed'}
