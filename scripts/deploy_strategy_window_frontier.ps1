param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'reports/strategy_window_ui_20261009'
$build=Join-Path $report 'build'
$experts='C:\MT5\DEMO\MQL5\Experts'
$verification=Get-Content (Join-Path $report 'verification.json') -Raw|ConvertFrom-Json
if($verification.compile-ne '0 errors, 0 warnings'-or $verification.behavior-notmatch '\bfailed=0\b'-or $verification.behavior-notmatch '\border_attempts=0\b'){throw 'Clean compile and native UI regression required'}
$binaries=@($verification.binaries|Where-Object relative -like 'IndicatorCodeExamples*')
if($binaries.Count-ne 4){throw 'Four verified production binaries required'}
if((Get-Content (Join-Path $root 'reports/strategy_audit_20261008/progress.json') -Raw|ConvertFrom-Json).state-ne 'finished'){throw 'Audit campaign is not finished'}
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object Path -eq 'C:\MT5\DEMO\terminal64.exe'){throw 'Close the DEMO terminal before deployment; no terminal was stopped'}
& node (Join-Path $PSScriptRoot 'report_strategy_window_campaign.mjs') --verify-common --write
if($LASTEXITCODE-ne 0){throw 'Saved audit metric integrity check failed'}

function DemoRelative([string]$path){
 $prefix='IndicatorCodeExamples\';$path=$path.Replace('/','\')
 if(!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)-or $path.Contains('..')){throw ('Invalid release path: '+$path)}
 $path=$path.Substring($prefix.Length)
 if($path.StartsWith('macrossover_orb\')){return 'MaCrossOverOrb\'+$path.Substring('macrossover_orb\'.Length)}
 if($path.StartsWith('entry_engine_lab\')){return 'EntryEngineLab\'+$path.Substring('entry_engine_lab\'.Length)}
 if($path.StartsWith('orb\')-or $path.StartsWith('SolAdvanced\')-or !$path.Contains('\')){return $path}
 throw ('Unrelated EA dependency: '+$path)
}
$release=@()
foreach($file in $verification.files){
 if((Get-FileHash (Join-Path $root $file.relative)).Hash-ne $file.sha256-or (Get-FileHash (Join-Path $build $file.relative)).Hash-ne $file.sha256){throw ('Source changed after verification: '+$file.relative)}
 if(!$file.relative.StartsWith('IndicatorCodeExamples\',[StringComparison]::OrdinalIgnoreCase)){continue}
 $release+=@{source=(Join-Path $build $file.relative);relative=(DemoRelative $file.relative);sha256=$file.sha256}
}
foreach($file in $binaries){
 if((Get-FileHash (Join-Path $build $file.relative)).Hash-ne $file.sha256){throw ('Verified binary changed: '+$file.relative)}
 $release+=@{source=(Join-Path $build $file.relative);relative=(DemoRelative $file.relative);sha256=$file.sha256}
}
$changed=0;$published=@()
foreach($file in $release){
 $destination=Join-Path $experts $file.relative
 if(!(Test-Path $destination)-or (Get-FileHash $destination).Hash-ne $file.sha256){
  if(Test-Path $destination){
   $backup=Join-Path $report ('demo_before/'+$file.relative)
   New-Item -ItemType Directory -Force (Split-Path $backup)|Out-Null
   if(!(Test-Path $backup)){Copy-Item -LiteralPath $destination -Destination $backup}
  }
  New-Item -ItemType Directory -Force (Split-Path $destination)|Out-Null
  Copy-Item -LiteralPath $file.source -Destination $destination -Force
  $changed++
 }
 if((Get-FileHash $destination).Hash-ne $file.sha256){throw ('Deployment readback failed: '+$destination)}
 $published+=@{path=$destination;sha256=$file.sha256}
}
foreach($file in $binaries){Copy-Item -LiteralPath (Join-Path $build $file.relative) -Destination (Join-Path $root $file.relative) -Force}
@{deployedAt=(Get-Date -Format o);changedFiles=$changed;verifiedFiles=$published.Count;compile=$verification.compile;
 nativeTest=$verification.behavior;strategiesAndAuditResultsUnchanged=$true;files=$published;
 binaries=@($binaries|ForEach-Object {@{path=(Join-Path $experts (DemoRelative $_.relative));sha256=$_.sha256}})
}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $report 'deployment.json') -Encoding UTF8
Write-Output ('VERIFIED: four production EAs deployed; '+$changed+' changed files; '+$published.Count+' file hashes checked')
$binaries|ForEach-Object {Write-Output (Join-Path $experts (DemoRelative $_.relative))}
