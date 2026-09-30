param([switch]$CompileEAs,[string]$ProbeName="DailyQuotaProbe",[string]$ProbeSymbol="USDJPYm")
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$editor='C:\MT5\DEMO\MetaEditor64.exe'
function Compile([string]$file,[string]$log){
 $started=Get-Date
 $p=Start-Process $editor -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $started){throw 'Fresh compile log missing'}
 $result=Get-Content $log -Tail 1
 if($result -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw 'Compile failure'}
 Write-Output "$file : $result"
}
foreach($module in @('TradeCalendarMatrix.mqh','DailyTradeQuota.mqh')){
 $hashes=@(@('','orb','macrossover_orb','SolAdvanced')|ForEach-Object{(Get-FileHash (Join-Path $root "IndicatorCodeExamples/$_/$module")).Hash}|Select-Object -Unique)
 if($hashes.Count -ne 1){throw "Module copies differ: $module"}
}
if($CompileEAs){foreach($ea in @('orb/OrbUltimateEA_StrategyLibrary','macrossover_orb/MaCrossOverOrbEA','SolAdvanced/LiqNarrativeSol_Advanced')){
 $file=Join-Path $root ('IndicatorCodeExamples/'+$ea+'.mq5')
 Compile $file ($file+'.direction.log')
 $s=[IO.File]::ReadAllText($file)
 foreach($call in @('DailyQuotaAuditAllows(','DailyQuotaSchedule(','DailyQuotaLauncher(','DailyQuotaLiveAllows(')){
  if(!$s.Contains($call)){throw "Missing integration: $call in $ea"}
 }
}}
$probe=Join-Path $root ('tests/mql5/'+$ProbeName+'.mq5')
Compile $probe ($probe+'.log')
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Isolated worker already running'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$ProbeName+'.ex5'))
$ini=Join-Path $root '.tmp/daily_quota_probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$ProbeName),('Symbol='+$ProbeSymbol),'Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$started=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Probe timeout'}
$result=Join-Path $worker ('MQL5/Files/'+$ProbeName+'.json')
if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started){throw 'Fresh result missing'}
$data=Get-Content $result -Raw|ConvertFrom-Json
Write-Output "${ProbeName}=$($data.checks) checks, $($data.failed) failures"
if($data.failed -ne 0){throw 'Daily quota contract failed'}
