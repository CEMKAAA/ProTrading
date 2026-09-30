$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath '.').Path
$sourceDir = Join-Path $root 'IndicatorCodeExamples\macrossover_orb'
$destinationDir = (Resolve-Path -LiteralPath 'C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb').Path
if ($destinationDir -ne 'C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb') { throw 'Unexpected deployment directory' }
if (Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq 'C:\MT5\DEMO\terminal64.exe' }) {
    throw 'DEMO terminal is running; close it before deployment.'
}
$compileLog = Get-Content -LiteralPath (Join-Path $root '.tmp\MaCrossOverOrbEA_marker_compile.log') -Raw
if ($compileLog -notmatch 'Result: 0 errors, 0 warnings') { throw 'Clean compile result missing' }
$report = Get-Content -LiteralPath (Join-Path $root '.tmp\orb_jp225_full_worker\MQL5\Files\MaSignalMarkerTimingProbe.txt') -Raw
if ($report -notmatch 'CHECKS=28 FAILED=0') { throw 'Marker regression checks did not pass' }
$files = @('MaCrossOverOrbEA.mq5', 'MaCrossOverOrbEA.ex5', 'OrbAdvancedAuditEngine.mqh')
foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $name) -PathType Leaf)) { throw "Missing source: $name" }
    if (-not (Test-Path -LiteralPath (Join-Path $destinationDir $name) -PathType Leaf)) { throw "Missing target: $name" }
}
$backup = Join-Path $root ('.tmp\ma_marker_deploy_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($name in $files) {
    $source = Join-Path $sourceDir $name
    $destination = Join-Path $destinationDir $name
    Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $name)
    Copy-Item -LiteralPath $source -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
        throw "Hash mismatch: $name"
    }
    Write-Output "MATCH $destination"
}
Write-Output "BACKUP $backup"
