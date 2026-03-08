param(
    [string]$CampaignName = "",
    [int]$IntervalSeconds = 300,
    [int]$MaxAttemptsPerScenario = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resultsDir = Join-Path $PSScriptRoot "results"
if (!(Test-Path $resultsDir)) {
    Write-Host "results directory not found: $resultsDir"
    exit 1
}

function Resolve-CampaignName {
    param([string]$Provided)
    if ($Provided -and $Provided.Trim().Length -gt 0) {
        return $Provided.Trim()
    }
    $jsonFiles = Get-ChildItem $resultsDir -Filter "*.json" -File |
        Sort-Object LastWriteTime -Descending
    if (!$jsonFiles) {
        throw "No campaign checkpoint (*.json) found in $resultsDir"
    }
    foreach ($f in $jsonFiles) {
        try {
            $raw = Get-Content $f.FullName -Raw
            $obj = $raw | ConvertFrom-Json
            if (!($obj -is [System.Array]) -and $null -ne $obj.runs -and $null -ne $obj.scenarios) {
                return [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            }
        } catch {
            continue
        }
    }
    return [System.IO.Path]::GetFileNameWithoutExtension($jsonFiles[0].Name)
}

function Read-CheckpointSummary {
    param([string]$JsonPath)
    $content = Get-Content $JsonPath -Raw
    $obj = $content | ConvertFrom-Json
    if ($obj -is [System.Array]) {
        $runs = @($obj).Count
        return [pscustomobject]@{
            Runs = $runs
            ScenarioCount = 0
            ExpectedRuns = $runs
            ProgressPct = 100.0
            BestScenarios = 0
            CompletedAt = "n/a (result list)"
        }
    }
    $runs = @($obj.runs).Count
    $scenarioCount = @($obj.scenarios).Count
    $expected = [Math]::Max(1, $scenarioCount * $MaxAttemptsPerScenario)
    $pct = [Math]::Round(($runs / $expected) * 100.0, 2)
    if ($pct -gt 100) { $pct = 100.0 }
    $best = @($obj.best_by_scenario.PSObject.Properties).Count
    $completedAt = $obj.completed_at
    return [pscustomobject]@{
        Runs = $runs
        ScenarioCount = $scenarioCount
        ExpectedRuns = $expected
        ProgressPct = $pct
        BestScenarios = $best
        CompletedAt = $completedAt
    }
}

$name = Resolve-CampaignName -Provided $CampaignName
$logPath = Join-Path $resultsDir ($name + ".log")
$errPath = Join-Path $resultsDir ($name + ".err.log")
$jsonPath = Join-Path $resultsDir ($name + ".json")

Write-Host "Watching campaign: $name"
Write-Host "Log: $logPath"
Write-Host "Err: $errPath"
Write-Host "Checkpoint: $jsonPath"
Write-Host ""

while ($true) {
    Clear-Host
    Write-Host ("[{0}] Campaign: {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $name)
    Write-Host ("Interval: {0}s" -f $IntervalSeconds)
    Write-Host ("-" * 110)

    if (Test-Path $jsonPath) {
        try {
            $s = Read-CheckpointSummary -JsonPath $jsonPath
            $completed = $s.CompletedAt
            if ($null -eq $completed -or [string]::IsNullOrWhiteSpace([string]$completed)) {
                $completed = "null"
            }
            Write-Host ("runs={0}/{1}  progress={2}%  scenarios={3}  best_scenarios={4}  completed_at={5}" -f `
                $s.Runs, $s.ExpectedRuns, $s.ProgressPct, $s.ScenarioCount, $s.BestScenarios, $completed)
        } catch {
            Write-Host ("checkpoint parse error: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Host "checkpoint file not found yet"
    }

    Write-Host ("-" * 110)
    Write-Host "Last log lines:"
    if (Test-Path $logPath) {
        Get-Content $logPath -Tail 20
    } else {
        Write-Host "log file not found yet"
    }

    Write-Host ("-" * 110)
    if (Test-Path $errPath) {
        Write-Host "Last error lines:"
        Get-Content $errPath -Tail 10
    } else {
        Write-Host "error log file not found yet"
    }

    Write-Host ""
    Write-Host ("Sleeping {0}s... Press Ctrl+C to stop." -f $IntervalSeconds)
    Start-Sleep -Seconds $IntervalSeconds
}
