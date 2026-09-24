param(
    [ValidateSet('MaCross', 'SolAdvanced', 'OrbCurrent')][string]$Family,
    [string[]]$Symbols,
    [int]$StartSlot = 0,
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$worker = Join-Path $root '.tmp\orb_jp225_full_worker'
$exe = Join-Path $worker 'terminal64.exe'
$output = Join-Path $root 'reports\time_matrix_5y_20260924'
New-Item -ItemType Directory -Path $output -Force | Out-Null

if ($Family -eq 'MaCross') {
    $scriptName = 'MaCrossFiveYearCampaign'
    $fileNames = @('MaCrossFiveYearSummary.csv', 'MaCrossFiveYearTrades.csv', 'MaCrossFiveYearTimeMatrix.csv')
} elseif ($Family -eq 'SolAdvanced') {
    $scriptName = 'LiqSolAdvancedFiveYearCampaign'
    $fileNames = @('LiqSolAdvancedFiveYearSummary.csv', 'LiqSolAdvancedFiveYearTrades.csv', 'LiqSolAdvancedTimeMatrixSummary.csv')
} else {
    $scriptName = 'OrbCurrentUserFiveYearCampaign'
    $fileNames = @('OrbCurrentUserFiveYearSummary.csv', 'OrbCurrentUserFiveYearTrades.csv', 'OrbCurrentUserFiveYearTimeMatrix.csv')
}

Copy-Item -LiteralPath (Join-Path $root "tests\mql5\$scriptName.ex5") -Destination (Join-Path $worker "MQL5\Scripts\$scriptName.ex5") -Force

foreach ($symbol in $Symbols) {
    if ($symbol -cnotmatch '^[A-Za-z0-9]+$') { throw "Invalid symbol: $symbol" }
    $config = Join-Path $root "tmp\time_matrix_5y_${Family}_${symbol}.ini"
    if ($Family -eq 'MaCross') {
        Set-Content -LiteralPath (Join-Path $worker 'MQL5\Files\MaCrossCampaignStartSlot.txt') -Value $StartSlot -Encoding ascii
    } elseif ($Family -eq 'OrbCurrent') {
        Set-Content -LiteralPath (Join-Path $worker 'MQL5\Files\OrbCampaignStartSlot.txt') -Value $StartSlot -Encoding ascii
    }
    @('[Experts]', 'Enabled=0', 'AllowDllImport=0', '[StartUp]', "Script=$scriptName", "Symbol=$symbol", 'Period=M5', 'ShutdownTerminal=1') |
        Set-Content -LiteralPath $config -Encoding ascii
    $started = Get-Date
    Write-Host "START $Family $symbol $($started.ToString('s'))"
    $process = Start-Process -FilePath $exe -ArgumentList ('/portable /config:"' + $config + '"') -WindowStyle Hidden -PassThru
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        Write-Warning "TIMEOUT $Family $symbol; isolated worker pid=$($process.Id)"
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(30000) | Out-Null
    }
    foreach ($name in $fileNames) {
        $source = Join-Path $worker "MQL5\Files\$name"
        if (-not (Test-Path -LiteralPath $source)) { Write-Warning "MISSING $name for $symbol"; continue }
        $item = Get-Item -LiteralPath $source
        if ($item.LastWriteTime -lt $started) { Write-Warning "STALE $name for $symbol"; continue }
        $rows = @(Import-Csv -LiteralPath $source)
        if (@($rows | Where-Object { $_.symbol -and $_.symbol -ne $symbol }).Count -gt 0) {
            Write-Warning "SYMBOL_MISMATCH $name for $symbol"
            continue
        }
        $suffix = switch ($name) {
            'MaCrossFiveYearSummary.csv' { '5y' }
            'MaCrossFiveYearTrades.csv' { 'trades' }
            'MaCrossFiveYearTimeMatrix.csv' { 'time_matrix' }
            'LiqSolAdvancedFiveYearSummary.csv' { '5y' }
            'LiqSolAdvancedFiveYearTrades.csv' { 'trades' }
            'LiqSolAdvancedTimeMatrixSummary.csv' { 'time_matrix' }
            'OrbCurrentUserFiveYearSummary.csv' { '5y' }
            'OrbCurrentUserFiveYearTrades.csv' { 'trades' }
            'OrbCurrentUserFiveYearTimeMatrix.csv' { 'time_matrix' }
        }
        $prefix = switch ($Family) { 'MaCross' { 'macross' } 'SolAdvanced' { 'soladvanced' } 'OrbCurrent' { 'orb_current' } }
        $slotSuffix = if ($StartSlot -gt 0) { "_from_slot_$StartSlot" } else { '' }
        $target = Join-Path $output "${prefix}_${symbol}_${suffix}${slotSuffix}.csv"
        Copy-Item -LiteralPath $source -Destination $target -Force
        Write-Host "SAVED $target rows=$($rows.Count)"
    }
    if ($timedOut) { Write-Warning "PARTIAL $Family $symbol; remaining strategies must be rerun" }
}
