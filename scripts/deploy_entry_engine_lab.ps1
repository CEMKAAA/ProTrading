$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.Path]::GetFullPath((Join-Path $root 'IndicatorCodeExamples'))
$family=Join-Path $source 'entry_engine_lab'
$main=Join-Path $family 'EntryEngineLabEA.mq5'
$stage=(Get-Content (Join-Path $root '.tmp/entry_engine_lab_release_path.txt') -Raw).Trim()
$stage=[IO.Path]::GetFullPath($stage)
$stageRoot=[IO.Path]::GetFullPath((Join-Path $root '.tmp'))+'\'
if(!$stage.StartsWith($stageRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Release stage outside workspace'}
$result=Get-Content (Join-Path $stage 'result.txt') -Raw
if($result -notmatch '\bfailed=0\b' -or $result -notmatch '\baudit_same=true\b'){throw 'Release not verified'}
$compiled=Join-Path $stage 'entry_engine_lab/EntryEngineLabEA.mq5'
if((Get-Content ($compiled+'.log') -Raw) -notmatch 'Result: 0 errors, 0 warnings'){throw 'Production build not clean'}
$experts='C:\MT5\DEMO\MQL5\Experts'
$destination=Join-Path $experts 'EntryEngineLab'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq 'C:\MT5\DEMO\terminal64.exe'}){throw 'Close the DEMO terminal before publishing'}
$seen=@{}
function Collect([string]$path){
 $path=[IO.Path]::GetFullPath($path)
 if(!$path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'External quoted dependency'}
 if($seen.ContainsKey($path)){return};$seen[$path]=$true
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($path),'(?m)^\s*#include\s+"([^"]+)"')){Collect (Join-Path (Split-Path $path) $m.Groups[1].Value)}
}
Collect $main
$plan=@()
foreach($path in $seen.Keys){
 $relative=$path.Substring($source.Length+1)
 $build=Join-Path $stage $relative
 if(!(Test-Path $build) -or (Get-FileHash $path).Hash -ne (Get-FileHash $build).Hash){throw "Canonical source changed since verification: $relative"}
 if($path.StartsWith($family+'\',[StringComparison]::OrdinalIgnoreCase)){
  $target=Join-Path $destination $path.Substring($family.Length+1)
 }else{
  $target=Join-Path $experts $relative
  # Do not overwrite a different shared dependency used by another EA.
  if((Test-Path $target) -and (Get-FileHash $path).Hash -ne (Get-FileHash $target).Hash){throw "Shared dependency differs: $target"}
 }
 $plan+=@{Source=$path;Target=$target}
}
$binary=[IO.Path]::ChangeExtension($compiled,'.ex5')
if(!(Test-Path $binary)){throw 'Verified EX5 missing'}
$backup=Join-Path $root ('.tmp/entry_engine_lab_deploy_backup_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$plan+=@{Source=$binary;Target=(Join-Path $destination 'EntryEngineLabEA.ex5')}
foreach($doc in @('README.md','VERIFICATION.md','SCALPER_AUDIT.md')){
 $path=Join-Path $family $doc
 if(Test-Path $path){$plan+=@{Source=$path;Target=(Join-Path $destination $doc)}}
}
foreach($item in $plan){
 if(Test-Path $item.Target){
  $saved=Join-Path $backup $item.Target.Substring($experts.Length+1)
  New-Item -ItemType Directory -Path (Split-Path $saved) -Force|Out-Null
  Copy-Item -LiteralPath $item.Target -Destination $saved
 }
}
Copy-Item -LiteralPath $binary -Destination (Join-Path $family 'EntryEngineLabEA.ex5') -Force
$manifest=@("VERIFIED_STAGE=$stage","RESULT=$($result.Trim())","BACKUP=$backup")
foreach($item in $plan){
 New-Item -ItemType Directory -Path (Split-Path $item.Target) -Force|Out-Null
 Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
 $hash=(Get-FileHash $item.Source).Hash
 if($hash -ne (Get-FileHash $item.Target).Hash){throw "Deployment hash mismatch: $($item.Target)"}
 $manifest+="$hash $($item.Target)"
}
$manifest|Set-Content (Join-Path $backup 'manifest.txt') -Encoding UTF8
Write-Output "DEPLOYED=$destination FILES=$($plan.Count) BACKUP=$backup"
