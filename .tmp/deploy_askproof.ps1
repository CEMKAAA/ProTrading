$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath '.').Path
$targetRoot = 'C:\MT5\DEMO\MQL5\Experts'
$targetRoot = (Resolve-Path -LiteralPath $targetRoot).Path
$backupRoot = Join-Path $root ('.tmp\askproof_deploy_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 terminal is running; deployment aborted.'
}

$files = @(
    @('macrossover_orb', 'MaCrossOverOrb', 'MaCrossOverOrbEA.mq5'),
    @('macrossover_orb', 'MaCrossOverOrb', 'MaCrossOverOrbEA.ex5'),
    @('macrossover_orb', 'MaCrossOverOrb', 'OrbStrategyUserMetrics.mqh'),
    @('orb', 'orb', 'OrbUltimateEA_StrategyLibrary.mq5'),
    @('orb', 'orb', 'OrbUltimateEA_StrategyLibrary.ex5'),
    @('orb', 'orb', 'OrbStrategyUserMetrics.mqh'),
    @('SolAdvanced', 'SolAdvanced', 'LiqNarrativeSol_Advanced.mq5'),
    @('SolAdvanced', 'SolAdvanced', 'LiqNarrativeSol_Advanced.ex5')
)

foreach ($file in $files) {
    $source = Join-Path $root (Join-Path 'IndicatorCodeExamples' (Join-Path $file[0] $file[2]))
    $destinationDir = (Resolve-Path -LiteralPath (Join-Path $targetRoot $file[1])).Path
    if (-not $destinationDir.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unexpected destination: $destinationDir"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing source: $source" }
    $destination = Join-Path $destinationDir $file[2]
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "Missing destination: $destination" }
}

foreach ($file in $files) {
    $source = Join-Path $root (Join-Path 'IndicatorCodeExamples' (Join-Path $file[0] $file[2]))
    $destination = Join-Path (Join-Path $targetRoot $file[1]) $file[2]
    $backupDir = Join-Path $backupRoot $file[1]
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item -LiteralPath $destination -Destination (Join-Path $backupDir $file[2]) -Force
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) { throw "Hash mismatch: $destination" }
    Write-Output "MATCH $destination"
}
Write-Output "BACKUP $backupRoot"
