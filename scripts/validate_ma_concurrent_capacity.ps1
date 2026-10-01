param([switch]$PrepareOnly,[switch]$RunPrepared)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
$pointer=Join-Path $root '.tmp/ma_capacity_prepared_path.txt'
if(!$RunPrepared){
 $stage=Join-Path $root ('.tmp/ma_capacity_'+(Get-Date -Format yyyyMMdd_HHmmss))
 $anchor=[DateTime]::UtcNow.AddMinutes(-2).ToString('yyyy.MM.dd HH:mm:ss')
 $guid=[Guid]::NewGuid().ToString('N').Substring(0,10)
 foreach($variant in @('before','after')){
  $source=if($variant -eq 'before'){Join-Path $root '.tmp/capacity_before_20261001'}else{Join-Path $root 'IndicatorCodeExamples'}
  $target=Join-Path $stage ($variant+'/macrossover_orb')
  New-Item -ItemType Directory -Path $target -Force|Out-Null
  Copy-Item -Path ($source+'/macrossover_orb/*.mqh') -Destination $target
  Copy-Item -LiteralPath (Join-Path $source 'macrossover_orb/MaCrossOverOrbEA.mq5') -Destination $target
  Copy-Item -LiteralPath (Join-Path $source 'ResearchFiveYearLeaderboard.mqh') -Destination (Split-Path $target)
  if($variant -eq 'after'){$production=Join-Path $target 'MaCrossOverOrbEA.mq5'}
 }
 function Compile([string]$file){
  $log=$file+'.log';$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
  if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 8;throw 'Compile failed'}
  Get-Content $log -Tail 1
 }
 Compile $production
 foreach($variant in @('before','after')){
  $target=Join-Path $stage ($variant+'/macrossover_orb');$name='MaCapacity_'+$variant+'_'+$guid
  $probe=Join-Path $target ($name+'.mq5')
  Copy-Item -LiteralPath (Join-Path $root 'tests/mql5/MaOpenCapacityChecks.mqh') -Destination $target
  $text=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/MaConcurrentCapacityProbe.mq5')).Replace('MaConcurrentCapacityProbe.txt',$name+'.txt')
  $text="#define CAPACITY_PROBE_ANCHOR D'$anchor'`n"+$text
  if($variant -eq 'before'){$text="#define CAPACITY_BASELINE`n"+$text}
  [IO.File]::WriteAllText($probe,$text,(New-Object Text.UTF8Encoding($false)))
  Compile $probe
  $name|Set-Content (Join-Path $stage ($variant+'.name')) -Encoding ASCII
 }
 $stage|Set-Content $pointer -Encoding ASCII
 if($PrepareOnly){Write-Output "PREPARED=$stage";exit}
}else{$stage=(Get-Content $pointer -Raw).Trim()}
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Worker busy'}
foreach($variant in @('before','after')){
 $name=(Get-Content (Join-Path $stage ($variant+'.name')) -Raw).Trim()
 $binary=Join-Path $stage ($variant+'/macrossover_orb/'+$name+'.ex5')
 Copy-Item -LiteralPath $binary -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $stage ($variant+'.ini')
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=USDJPYm','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
 $started=Get-Date;$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(600000)){throw 'Probe timeout'}
 $path=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
 if(!(Test-Path $path) -or (Get-Item $path).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh report missing'}
 $result=Get-Content $path -Raw;Write-Output $result
 $result|Set-Content (Join-Path $stage ($variant+'.txt'))
 if($result -notmatch '\bfailed=0\b'){throw 'Capacity validation failed'}
}
$before=Get-Content (Join-Path $stage 'before.txt') -Raw;$after=Get-Content (Join-Path $stage 'after.txt') -Raw
$old=[regex]::Match($before,'legacy_hash=(\w+)').Groups[1].Value
$new=[regex]::Match($after,'legacy_hash=(\w+)').Groups[1].Value
if(!$old -or $old -ne $new){throw 'Legacy results changed'}
if($after -notmatch 'max10_open=10 max3_open=3'){throw 'Open-position limit invariant failed'}
"legacy_same=true $($after.Trim())"|Set-Content (Join-Path $stage 'result.txt')
Copy-Item (Join-Path $worker 'MQL5/Files/MaCrossOpenCounter.png') $stage
$stage|Set-Content (Join-Path $root '.tmp/ma_capacity_release_path.txt') -Encoding ASCII
Write-Output "VERIFIED=$stage LEGACY_SAME=true"
