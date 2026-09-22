param([switch]$InstallDemo)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples/macrossover_orb'
$stage=Join-Path $root ('.tmp/ma_of_leaderboard_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Force $stage|Out-Null
$seen=@{}
function StageFile([string]$rel){
 if($seen.ContainsKey($rel)){return};$seen[$rel]=$true
 $from=Join-Path $src $rel;$to=Join-Path $stage $rel
 New-Item -ItemType Directory -Force (Split-Path $to)|Out-Null
 Copy-Item -LiteralPath $from -Destination $to
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($from),'(?m)^\s*#include\s+"([^"]+)"')){
  $child=$m.Groups[1].Value;if(Split-Path $rel){$child=Join-Path (Split-Path $rel) $child};StageFile $child
 }
}
StageFile 'MaCrossOverOrbEA.mq5'
$file=Join-Path $stage 'MaCrossOverOrbEA.mq5';$log=$file+'.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
if(!(Test-Path $log) -or [IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 35;throw 'Compile failed'}
Write-Output 'MaCrossOverOrbEA : 0 errors, 0 warnings'
Copy-Item ([IO.Path]::ChangeExtension($file,'.ex5')) $src
if($InstallDemo){
 $target='C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb'
 foreach($rel in @($seen.Keys)+@('MaCrossOverOrbEA.ex5')){
  $from=Join-Path $stage $rel;$to=Join-Path $target $rel
  if(Test-Path $to){$backup=Join-Path $stage ('backup/'+$rel);New-Item -ItemType Directory -Force (Split-Path $backup)|Out-Null;Copy-Item -LiteralPath $to -Destination $backup}
  New-Item -ItemType Directory -Force (Split-Path $to)|Out-Null
  Copy-Item -LiteralPath $from -Destination $to
  if((Get-FileHash $from).Hash -ne (Get-FileHash $to).Hash){throw "Hash mismatch $to"}
 }
 Write-Output "Verified deployment: $target"
}
Write-Output "STAGE=$stage"
