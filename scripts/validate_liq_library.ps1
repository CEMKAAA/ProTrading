param([switch]$InstallDemo)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$stage=Join-Path $root ('.tmp/liq_library_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Force $stage|Out-Null
$names=@('LiquidityNarrative_MT5_EA','LiquidityNarrative_MT5_EA_Channel','LiqNarrativeSolVersion','LiqNarrativeSolVersion_Channel','LiqNarrativeSol_Advanced','LiqNarrativeSol_Advanced_Channel')
$seen=@{}
function StageFile([string]$rel){
 if($seen.ContainsKey($rel)){return};$seen[$rel]=$true
 $from=Join-Path $src $rel;$to=Join-Path $stage $rel
 New-Item -ItemType Directory -Force (Split-Path $to)|Out-Null
 Copy-Item -LiteralPath $from -Destination $to
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($from),'(?m)^\s*#include\s+"([^"]+)"')){
  $child=$m.Groups[1].Value
  if(Split-Path $rel){$child=Join-Path (Split-Path $rel) $child}
  StageFile $child
 }
}
foreach($n in $names){StageFile ($n+'.mq5')}
foreach($n in $names){
 $file=Join-Path $stage ($n+'.mq5');$log=$file+'.log'
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw "Compile timeout $n"}
 if(!(Test-Path $log) -or [IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){throw "Compile failed: $log"}
 Write-Output "$n : 0 errors, 0 warnings"
}
$targets=@($src,(Join-Path $src 'liq'))
if($InstallDemo){$targets+='C:\MT5\DEMO\MQL5\Experts\SolAdvanced';$targets+='C:\MT5\DEMO\MQL5\Experts'}
foreach($target in $targets){
 foreach($rel in @($seen.Keys)+@($names|ForEach-Object {$_+'.ex5'})){
  $from=Join-Path $stage $rel;$to=Join-Path $target $rel
  if((Test-Path $to) -and (Get-FileHash $from).Hash -eq (Get-FileHash $to).Hash){continue}
  if(Test-Path $to){$backup=Join-Path $stage ('backup/'+[IO.Path]::GetFileName($target)+'/'+$rel);New-Item -ItemType Directory -Force (Split-Path $backup)|Out-Null;Copy-Item -LiteralPath $to -Destination $backup}
  New-Item -ItemType Directory -Force (Split-Path $to)|Out-Null
  Copy-Item -LiteralPath $from -Destination $to
  if((Get-FileHash $from).Hash -ne (Get-FileHash $to).Hash){throw "Hash mismatch $to"}
 }
 Write-Output "Verified: $target"
}
Write-Output "STAGE=$stage"
