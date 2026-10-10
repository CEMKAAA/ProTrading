param([string]$ReportDir='reports/strategy_audit_20261009_rolling')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=[IO.Path]::GetFullPath((Join-Path $root $ReportDir))
$proof=Get-Content (Join-Path $out 'release_verified.json') -Raw|ConvertFrom-Json
& node (Join-Path $PSScriptRoot 'verify_strategy_campaign_snapshot.mjs') $out
if($LASTEXITCODE-ne 0){throw 'Source/native proof changed; no deployment'}
if($proof.compile.errors-ne 0-or $proof.compile.warnings-ne 0-or $proof.binaries.Count-ne 4){throw 'Four clean production builds required'}
$manifest=Get-Content (Join-Path $out 'manifest.private.json') -Raw|ConvertFrom-Json
if($proof.sourceHash-ne $manifest.sourceHash){throw 'Release fingerprint mismatch'}
$demo='C:\MT5\DEMO\MQL5\Experts'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object Path -eq 'C:\MT5\DEMO\terminal64.exe'){
 Write-Output 'DEFERRED: DEMO is open. Verified files remain in their canonical workspace folders. No terminal was stopped.'
 return
}
function DemoRelative([string]$path){
 $path=$path.Replace('/','\')
 if($path.Contains('..')-or [IO.Path]::IsPathRooted($path)){throw 'Invalid release path'}
 if($path.StartsWith('macrossover_orb\')){return 'MaCrossOverOrb\'+$path.Substring(16)}
 if($path.StartsWith('entry_engine_lab\')){return 'EntryEngineLab\'+$path.Substring(17)}
 if($path.StartsWith('orb\')-or $path.StartsWith('SolAdvanced\')-or !$path.Contains('\')){return $path}
 throw ('Unrelated family in release: '+$path)
}
$files=@($manifest.sources|ForEach-Object{
 @{source=(Join-Path $root ('IndicatorCodeExamples/'+$_.file));relative=(DemoRelative $_.file);sha256=$_.sha256}
})
foreach($binary in $proof.binaries){
 $relative=$binary.relative.Replace('/','\')
 if(!$relative.StartsWith('IndicatorCodeExamples\')){throw 'Noncanonical binary'}
 $files+=@{source=(Join-Path $root $relative);relative=(DemoRelative $relative.Substring(22));sha256=$binary.sha256}
}
foreach($file in $files){
 if((Get-FileHash -LiteralPath $file.source).Hash-ne $file.sha256){throw ('Release file changed: '+$file.source)}
}
$changed=0
foreach($file in $files){
 $destination=Join-Path $demo $file.relative
 if(!(Test-Path -LiteralPath $destination)-or (Get-FileHash -LiteralPath $destination).Hash-ne $file.sha256){
  New-Item -ItemType Directory -Force (Split-Path $destination)|Out-Null
  Copy-Item -LiteralPath $file.source -Destination ($destination+'.pending') -Force
  Move-Item -LiteralPath ($destination+'.pending') -Destination $destination -Force
  $changed++
 }
 if((Get-FileHash -LiteralPath $destination).Hash-ne $file.sha256){throw ('Deployment readback mismatch: '+$destination)}
}
$text=@{deployedAt=[DateTimeOffset]::UtcNow.ToString('o');sourceHash=$proof.sourceHash;verifiedFiles=$files.Count;changedFiles=$changed;
 binaries=@($proof.binaries|ForEach-Object{Join-Path $demo (DemoRelative $_.relative.Replace('/','\').Substring(22))})}|ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $out 'deployment.json.pending'),$text,(New-Object Text.UTF8Encoding($false)))
Move-Item -LiteralPath (Join-Path $out 'deployment.json.pending') -Destination (Join-Path $out 'deployment.json') -Force
Write-Output ('DEPLOYED: four production EAs; '+$files.Count+' hashes verified; '+$changed+' files updated. Campaign worker was not touched.')
