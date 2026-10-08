param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'reports/sol_btc_selection_20261008'
$v=Get-Content (Join-Path $report 'verification.json') -Raw|ConvertFrom-Json
if($v.compile-ne '0 errors, 0 warnings'-or $v.behavior-notmatch '\bfailed=0\b'-or $v.behavior-notmatch '\border_attempts=0\b'){throw 'Native verification required'}
if(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq 'C:\MT5\DEMO\terminal64.exe'){
 throw 'Close only the user DEMO terminal; the separate audit campaign must remain running'
}
$build=Join-Path $report 'build'
$experts='C:\MT5\DEMO\MQL5\Experts'
$entry='IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced'
$binary=Join-Path $build ($entry+'.ex5')
if((Get-FileHash $binary).Hash-ne $v.binary){throw 'Verified binary changed'}
foreach($f in $v.files){
 $relative=$f.relative
 if(!$relative.StartsWith('IndicatorCodeExamples\',[StringComparison]::OrdinalIgnoreCase)-or $relative.Contains('..')){throw 'Invalid release path'}
 if((Get-FileHash (Join-Path $root $relative)).Hash-ne $f.sha256-or (Get-FileHash (Join-Path $build $relative)).Hash-ne $f.sha256){throw "Source changed: $relative"}
}
$release=@($v.files|ForEach-Object {@{from=(Join-Path $build $_.relative);relative=$_.relative.Substring('IndicatorCodeExamples\'.Length);sha256=$_.sha256}})
$release+=@{from=$binary;relative='SolAdvanced\LiqNarrativeSol_Advanced.ex5';sha256=$v.binary}
$changed=0
foreach($f in $release){
 $dest=Join-Path $experts $f.relative
 if((Test-Path $dest)-and (Get-FileHash $dest).Hash-eq $f.sha256){continue}
 if(Test-Path $dest){
  $backup=Join-Path $report ('demo_before/'+$f.relative)
  New-Item -ItemType Directory -Force (Split-Path $backup)|Out-Null
  if(!(Test-Path $backup)){Copy-Item -LiteralPath $dest -Destination $backup}
 }
 New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath $f.from -Destination $dest -Force
 if((Get-FileHash $dest).Hash-ne $f.sha256){throw "Copy verification failed: $dest"}
 $changed++;Write-Output "DEPLOYED $($f.relative)"
}
Copy-Item -LiteralPath $binary -Destination (Join-Path $root ($entry+'.ex5')) -Force
@{deployedAt=(Get-Date -Format o);changedFiles=$changed;binary=$v.binary;destination=(Join-Path $experts 'SolAdvanced');campaignStopped=$false}|ConvertTo-Json|Set-Content (Join-Path $report 'deployment.json') -Encoding UTF8
Write-Output "VERIFIED SolAdvanced release: $changed changed files; campaign untouched"
