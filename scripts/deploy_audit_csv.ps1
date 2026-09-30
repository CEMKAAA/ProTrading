param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$sources=Join-Path $root 'IndicatorCodeExamples'
$stageRoot=(Resolve-Path -LiteralPath $Stage).Path
if(!$stageRoot.StartsWith((Join-Path $root '.tmp')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Compile stage must be inside workspace .tmp'}
$destination='C:\MT5\DEMO\MQL5\Experts'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq 'C:\MT5\DEMO\terminal64.exe'}){throw 'Close DEMO MT5 before deployment'}
$entries=@('orb/OrbUltimateEA_StrategyLibrary.mq5','macrossover_orb/MaCrossOverOrbEA.mq5','SolAdvanced/LiqNarrativeSol_Advanced.mq5')
foreach($entry in $entries){
 $file=Join-Path $stageRoot $entry
 if(!(Test-Path -LiteralPath ($file+'.log')) -or [IO.File]::ReadAllText($file+'.log') -notmatch 'Result: 0 errors, 0 warnings'){throw "Unverified compile: $entry"}
 if(!(Test-Path -LiteralPath ([IO.Path]::ChangeExtension($file,'.ex5')))){throw "Missing executable: $entry"}
}
$files=@(Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Where-Object {$_.Extension -in @('.mq5','.mqh')})
foreach($file in $files){
 $relative=$file.FullName.Substring($stageRoot.Length+1)
 if($relative.StartsWith('tests\')){throw 'Use a production-only compile stage'}
 $current=Join-Path $sources $relative
 if(!(Test-Path -LiteralPath $current) -or (Get-FileHash -LiteralPath $current).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash){throw "Source changed after compile: $relative"}
}
$backup=Join-Path $root ('.tmp/audit_csv_deploy_backup_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$records=@()
function DeployFile([string]$from,[string]$relative){
 $target=[IO.Path]::GetFullPath((Join-Path $destination $relative))
 if(!$target.StartsWith($destination+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped Experts'}
 if(Test-Path -LiteralPath $target){
  $previous=Join-Path $backup $relative
  New-Item -ItemType Directory -Path (Split-Path $previous) -Force | Out-Null
  Copy-Item -LiteralPath $target -Destination $previous -Force
 }
 New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
 Copy-Item -LiteralPath $from -Destination $target -Force
 $hash=(Get-FileHash -LiteralPath $from).Hash
 if((Get-FileHash -LiteralPath $target).Hash -ne $hash){throw "Deployed hash mismatch: $target"}
 $script:records+=@{path=$target;sha256=$hash}
}
foreach($file in $files){
 $relative=$file.FullName.Substring($stageRoot.Length+1).Replace('macrossover_orb\','MaCrossOverOrb\')
 DeployFile $file.FullName $relative
}
foreach($entry in $entries){
 $binary=[IO.Path]::ChangeExtension($entry,'.ex5')
 $built=Join-Path $stageRoot $binary
 $current=Join-Path $sources $binary
 $previous=Join-Path $backup ('workspace/'+$binary)
 if(Test-Path -LiteralPath $current){New-Item -ItemType Directory -Path (Split-Path $previous) -Force | Out-Null;Copy-Item -LiteralPath $current -Destination $previous -Force}
 Copy-Item -LiteralPath $built -Destination $current -Force
 DeployFile $built ($binary.Replace('macrossover_orb/','MaCrossOverOrb/'))
}
$records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'deployed_hashes.json') -Encoding UTF8
Write-Output "DEPLOYED=$($records.Count) files; all SHA-256 hashes match"
Write-Output "BACKUP=$backup"
