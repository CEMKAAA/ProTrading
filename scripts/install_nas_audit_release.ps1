param(
    [switch]$Install,
    [string]$ExpertsPath='C:\MT5\DEMO\MQL5\Experts',
    [ValidateSet('all','nas')][string]$Family='all'
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$target=[IO.Path]::GetFullPath($ExpertsPath).TrimEnd('\')
if(!(Test-Path -LiteralPath $target -PathType Container) -or
   !(($target -replace '/','\').EndsWith('\MQL5\Experts',[StringComparison]::OrdinalIgnoreCase))) {
    throw 'Target must be an existing MQL5\Experts directory'
}
$report=Join-Path $root 'logs/AuditWindowReuse_20260914'
$entrypoints=@('OrbUltimateEA.mq5','OrbUltimateEA_StrategyLibrary.mq5','NasUltimate_StrategyLibrary.mq5','NasUltimate_SATS_PartialNoBE_EA.mq5','LiquidityNarrative_MT5_EA.mq5','LiquidityNarrative_Invert_MT5_EA.mq5','LiqNarrativeSolVersion.mq5','LiqNarrativeSol_Advanced.mq5','LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')
if($Family -eq 'nas'){$entrypoints=@('NasUltimate_StrategyLibrary.mq5','NasUltimate_SATS_PartialNoBE_EA.mq5')}
foreach($entry in $entrypoints) {
    $source=Join-Path $src $entry;$binary=[IO.Path]::ChangeExtension($source,'.ex5')
    $log=Join-Path $report ($entry+'.compile.log')
    if(!(Test-Path $binary) -or !(Test-Path $log) -or !([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){throw "Unverified entry point $entry"}
    if((Get-Item $binary).LastWriteTime -lt (Get-Item $source).LastWriteTime){throw "Stale binary $entry"}
}
$nas=@(Get-Content (Join-Path $report 'nas_window.jsonl')|ForEach-Object {$_|ConvertFrom-Json})
$orb=@(Get-Content (Join-Path $report 'orb_window.jsonl')|ForEach-Object {$_|ConvertFrom-Json})
if($nas.Count -ne 7 -or @($nas|Where-Object {!$_.same -or $_.blocked}).Count){throw 'NAS parity not passed'}
if($orb.Count -ne 7 -or @($orb|Where-Object {!$_.same -or !$_.ok}).Count){throw 'ORB parity not passed'}
$prediction=Get-Content (Join-Path $root 'logs/NasStrategyLibrary_20260912/mql_prediction_parity.json') -Raw|ConvertFrom-Json
if($prediction.failed -ne 0 -or $prediction.models -ne 38 -or $prediction.vectors -ne 456){throw 'Model inference not passed'}
# Keep each terminal's deployment evidence separate from validation and DEMO records.
if($target -ne 'C:\MT5\DEMO\MQL5\Experts') {
    $terminalName=Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $target))
    $report=Join-Path $report ('terminal_'+$terminalName)
    New-Item -ItemType Directory -Path $report -Force|Out-Null
}
$map=@{}
function Add-Source([string]$name,[string]$folder) {
    $dest=[IO.Path]::GetFullPath((Join-Path $folder $name))
    if(!$dest.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped Experts'}
    if($map.ContainsKey($dest)){return}
    $source=Join-Path $src $name
    if(!(Test-Path $source)){throw "Missing dependency $name"}
    $map[$dest]=$source
    if([IO.Path]::GetExtension($name) -eq '.mq5') {
        $map[[IO.Path]::ChangeExtension($dest,'.ex5')]=[IO.Path]::ChangeExtension($source,'.ex5')
    }
    foreach($m in [regex]::Matches([IO.File]::ReadAllText($source),'(?m)^\s*#include\s+"([^"]+)"')) {
        Add-Source $m.Groups[1].Value $folder
    }
}
foreach($entry in $entrypoints) {
    Add-Source $entry $target
    Get-ChildItem -LiteralPath $target -Filter $entry -Recurse -File|ForEach-Object {Add-Source $entry $_.DirectoryName}
}
# New standalone workbench is also grouped for easy MetaEditor discovery.
Add-Source 'NasUltimate_StrategyLibrary.mq5' (Join-Path $target 'NasStrategyLibrary')
$plan=@($map.GetEnumerator()|Sort-Object Key|ForEach-Object {
    if(!(Test-Path $_.Value)){throw ('Missing source/binary '+$_.Value)}
    [pscustomobject]@{source=$_.Value;destination=$_.Key;sha256=(Get-FileHash -LiteralPath $_.Value).Hash}
})
$plan|ConvertTo-Json -Depth 4|Set-Content (Join-Path $report 'deployment_plan.json') -Encoding UTF8
Write-Output ("Verified plan: "+$plan.Count+" files. EX5 replacement can reload attached charts. Listeners/accounts/models are not changed.")
if(!$Install){return}
$backup=Join-Path $report ('deployment_backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$record=[Collections.Generic.List[object]]::new()
# Copy includes/sources first, binaries last. Preserve every replaced version.
foreach($row in ($plan|Sort-Object @{Expression={[IO.Path]::GetExtension($_.destination) -eq '.ex5'}},destination)) {
    if((Get-FileHash -LiteralPath $row.source).Hash -ne $row.sha256){throw 'Source changed after preflight'}
    $old=''
    if(Test-Path -LiteralPath $row.destination) {
        $old=(Get-FileHash -LiteralPath $row.destination).Hash
        if($old -eq $row.sha256){continue}
        $relative=$row.destination.Substring($target.Length+1)
        $saved=Join-Path $backup $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force|Out-Null
        Copy-Item -LiteralPath $row.destination -Destination $saved
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $row.destination) -Force|Out-Null
    $staged=$row.destination+'.nas_audit_pending'
    Copy-Item -LiteralPath $row.source -Destination $staged -Force
    if((Get-FileHash -LiteralPath $staged).Hash -ne $row.sha256){throw 'Staging hash mismatch'}
    Move-Item -LiteralPath $staged -Destination $row.destination -Force
    if((Get-FileHash -LiteralPath $row.destination).Hash -ne $row.sha256){throw 'Installed hash mismatch'}
    $record.Add([pscustomobject]@{path=$row.destination;previous=$old;installed=$row.sha256})
    $record|ConvertTo-Json -Depth 4|Set-Content (Join-Path $report 'installation.json') -Encoding UTF8
}
foreach($row in $plan){if((Get-FileHash -LiteralPath $row.destination).Hash -ne $row.sha256){throw 'Final hash verification failed'}}
Write-Output ("Installed "+$record.Count+" changed files; all "+$plan.Count+" destination hashes match. Backup: "+$backup)
