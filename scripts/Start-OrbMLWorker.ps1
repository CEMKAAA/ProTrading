param([string]$MlRoot=(Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\OrbML'),[switch]$WaitForWorker)
$ErrorActionPreference='Stop'
$python=(Get-Command python -ErrorAction Stop).Source
& $python -c "import numpy, pandas, sklearn"
if($LASTEXITCODE -ne 0){throw 'Install numpy, pandas and scikit-learn in this Python environment first.'}
$script=Join-Path $PSScriptRoot 'orb_ml_worker.py'
$heartbeat=Join-Path $MlRoot 'worker.heartbeat'
if(Test-Path -LiteralPath $heartbeat){
    $last=[long]([IO.File]::ReadAllText($heartbeat))
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if($now-$last -ge 0 -and $now-$last -lt 30 -and !$WaitForWorker){Write-Output 'ML worker is already online.';exit 0}
}
if($WaitForWorker){
    # If a manually started worker already owns the root, wait for it rather
    # than leaving the scheduled supervisor permanently stopped.
    while($true){
        $recent=$false
        if(Test-Path -LiteralPath $heartbeat){
            try {$age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-[long]([IO.File]::ReadAllText($heartbeat));$recent=$age -ge 0 -and $age -lt 30}catch{}
        }
        if($recent){Start-Sleep -Seconds 10;continue}
        & $python $script --root $MlRoot
        exit 1 # Task Scheduler retries unexpected exits, without replaying jobs.
    }
}
# A single-worker OS lock is authoritative even if the heartbeat is stale.
$arguments='"'+$script+'" --root "'+$MlRoot+'"'
$process=Start-Process -FilePath $python -ArgumentList $arguments -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 3
$process.Refresh()
if($process.HasExited){throw 'Worker exited. Run python scripts/orb_ml_worker.py --root <OrbML directory> to see the error.'}
Write-Output ('ML training worker started. PID='+$process.Id+'; root='+$MlRoot)
