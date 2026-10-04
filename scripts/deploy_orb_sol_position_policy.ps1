param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'tmp/position_policy_20261004'
$manifest=Get-Content (Join-Path $stage 'verification.json') -Raw|ConvertFrom-Json
if($manifest.schema-ne 1-or $manifest.behavior-ne 'PASS'-or $manifest.defaultReplay-ne 'PASS'){
 throw 'Complete compile, behavior, and replay verification first'
}
if(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq 'C:\MT5\DEMO\terminal64.exe'){
 throw 'Close MT5 DEMO before deployment'
}
$experts='C:\MT5\DEMO\MQL5\Experts'
$backup=Join-Path $stage 'demo_before'
# Verify the entire release before writing any destination file.
foreach($record in $manifest.files){
 if($record.family-notin @('orb','SolAdvanced')-or [IO.Path]::GetFileName($record.name)-ne $record.name){throw 'Invalid release path'}
 $built=Join-Path $stage ('candidate_build/IndicatorCodeExamples/'+$record.family+'/'+$record.name)
 if((Get-FileHash -LiteralPath $built).Hash-ne $record.sha256){throw "Staged artifact changed: $built"}
 if([IO.Path]::GetExtension($record.name)-ne '.ex5'){
  $source=Join-Path $root ('IndicatorCodeExamples/'+$record.family+'/'+$record.name)
  if((Get-FileHash -LiteralPath $source).Hash-ne $record.sha256){throw "Source changed after verification: $source"}
 }
}
foreach($record in $manifest.files){
 $built=Join-Path $stage ('candidate_build/IndicatorCodeExamples/'+$record.family+'/'+$record.name)
 $source=Join-Path $root ('IndicatorCodeExamples/'+$record.family+'/'+$record.name)
 if([IO.Path]::GetExtension($record.name)-eq '.ex5'){Copy-Item -LiteralPath $built -Destination $source -Force}
 $destFolder=Join-Path $experts $record.family
 New-Item -ItemType Directory -Path $destFolder -Force|Out-Null
 $dest=Join-Path $destFolder $record.name
 if((Test-Path -LiteralPath $dest)-and (Get-FileHash -LiteralPath $dest).Hash-ne $record.sha256){
  $before=Join-Path $backup ($record.family+'/'+$record.name)
  if(!(Test-Path -LiteralPath $before)){
   New-Item -ItemType Directory -Path (Split-Path $before) -Force|Out-Null
   Copy-Item -LiteralPath $dest -Destination $before
  }
 }
 Copy-Item -LiteralPath $built -Destination $dest -Force
 if((Get-FileHash -LiteralPath $dest).Hash-ne $record.sha256){throw "Deployment hash mismatch: $dest"}
}
foreach($family in @('orb','SolAdvanced')){
 $count=@($manifest.files|Where-Object family -eq $family).Count
 Write-Output "DEPLOYED $experts\$family : $count files, all SHA256 matched"
}
$manifest|Add-Member -NotePropertyName deployedAt -NotePropertyValue (Get-Date -Format o) -Force
$manifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $stage 'deployment.json') -Encoding UTF8
