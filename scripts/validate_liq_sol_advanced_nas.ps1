param([switch]$InstallDemo)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$stage=Join-Path $root ('.tmp/liq_sol_adv_filter_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Force $stage|Out-Null
$seen=@{}
function StageSource([string]$absolute){
 $absolute=[IO.Path]::GetFullPath($absolute)
 if(!$absolute.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "External include: $absolute"}
 if($seen.ContainsKey($absolute)){return}
 $seen[$absolute]=$true
 $relative=$absolute.Substring($source.Length+1)
 $destination=Join-Path $stage $relative
 New-Item -ItemType Directory -Force (Split-Path $destination)|Out-Null
 Copy-Item -LiteralPath $absolute -Destination $destination
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($absolute),'(?m)^\s*#include\s+"([^"]+)"')){
  StageSource (Join-Path (Split-Path $absolute) $m.Groups[1].Value)
 }
}
StageSource (Join-Path $source 'SolAdvanced/LiqNarrativeSol_Advanced.mq5')
$file=Join-Path $stage 'SolAdvanced/LiqNarrativeSol_Advanced.mq5'
$log=$file+'.log'
$editor='C:\MT5\DEMO\MetaEditor64.exe'
$process=Start-Process $editor -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$process.WaitForExit(180000)){throw 'Compile timeout'}
if(!(Test-Path $log) -or [IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){
 Get-Content $log -Tail 70
 throw "Compile failed: $log"
}
Write-Output 'Sol Advanced: 0 errors, 0 warnings'
if(!$InstallDemo){Write-Output "STAGE=$stage";return}
$destination='C:\MT5\DEMO\MQL5\Experts\SolAdvanced'
foreach($absolute in $seen.Keys){
 $relative=$absolute.Substring($source.Length+1)
 $to=Join-Path $destination $relative
 New-Item -ItemType Directory -Force (Split-Path $to)|Out-Null
 if(Test-Path $to){
  $backup=Join-Path $stage ('backup/'+$relative)
  New-Item -ItemType Directory -Force (Split-Path $backup)|Out-Null
  Copy-Item -LiteralPath $to -Destination $backup
 }
 Copy-Item -LiteralPath (Join-Path $stage $relative) -Destination $to
 if((Get-FileHash $absolute).Hash -ne (Get-FileHash $to).Hash){throw "Source hash mismatch: $to"}
}
$to=Join-Path $destination 'LiqNarrativeSol_Advanced.ex5'
if(Test-Path $to){Copy-Item -LiteralPath $to -Destination (Join-Path $stage 'backup/LiqNarrativeSol_Advanced.ex5')}
Copy-Item -LiteralPath (Join-Path $stage 'LiqNarrativeSol_Advanced.ex5') -Destination $to
if((Get-FileHash (Join-Path $stage 'LiqNarrativeSol_Advanced.ex5')).Hash -ne (Get-FileHash $to).Hash){throw 'EX5 hash mismatch'}
Write-Output "DEPLOYED=$destination"
Write-Output "STAGE=$stage"
