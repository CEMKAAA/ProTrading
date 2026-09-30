param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sources=Join-Path $root 'IndicatorCodeExamples'
$stageRoot=(Resolve-Path -LiteralPath $Stage).Path
if(!$stageRoot.StartsWith((Join-Path $root '.tmp')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Stage must be in workspace .tmp'}
$destination='C:\MT5\DEMO\MQL5\Experts'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq 'C:\MT5\DEMO\terminal64.exe'}){throw 'Close DEMO MT5 before deployment'}
$entry=Join-Path $stageRoot 'macrossover_orb/MaCrossOverOrbEA.mq5'
$binary=[IO.Path]::ChangeExtension($entry,'.ex5')
if(!(Test-Path -LiteralPath $binary) -or [IO.File]::ReadAllText($entry+'.log') -notmatch 'Result: 0 errors, 0 warnings'){throw 'Verified build missing'}
$seen=@{}
function Collect([string]$path){
 $path=[IO.Path]::GetFullPath($path)
 if(!$path.StartsWith($stageRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw "External dependency: $path"}
 if($seen.ContainsKey($path)){return}
 $relative=$path.Substring($stageRoot.Length+1)
 $current=Join-Path $sources $relative
 if(!(Test-Path -LiteralPath $current) -or (Get-FileHash -LiteralPath $current).Hash -ne (Get-FileHash -LiteralPath $path).Hash){throw "Source changed since compile: $relative"}
 $seen[$path]=$relative
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($path),'(?m)^\s*#include\s+"([^"]+)"')){
  Collect (Join-Path (Split-Path $path) $m.Groups[1].Value)
 }
}
Collect $entry
$backup=Join-Path $root ('.tmp/ma_window_deploy_backup_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$seen[$binary]='macrossover_orb\MaCrossOverOrbEA.ex5'
$records=@()
foreach($from in $seen.Keys){
 $relative=$seen[$from].Replace('macrossover_orb\','MaCrossOverOrb\')
 $target=[IO.Path]::GetFullPath((Join-Path $destination $relative))
 if(!$target.StartsWith($destination+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped Experts'}
 if(Test-Path -LiteralPath $target){
  $old=Join-Path $backup $relative
  New-Item -ItemType Directory -Path (Split-Path $old) -Force|Out-Null
  Copy-Item -LiteralPath $target -Destination $old -Force
 }
 New-Item -ItemType Directory -Path (Split-Path $target) -Force|Out-Null
 Copy-Item -LiteralPath $from -Destination $target -Force
 $hash=(Get-FileHash -LiteralPath $from).Hash
 if((Get-FileHash -LiteralPath $target).Hash -ne $hash){throw "Hash mismatch: $target"}
 $records+=@{path=$target;sha256=$hash}
}
$records|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $backup 'deployed_hashes.json') -Encoding UTF8
Write-Output "DEPLOYED=$($records.Count) files; all SHA-256 hashes match"
Write-Output "BACKUP=$backup"
