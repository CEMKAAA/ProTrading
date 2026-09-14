$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    foreach($batch in @(@('BTCUSDm',12),@('US500m',3),@('USTECm',4))) {
        python scripts/build_nas_export_probe.py --symbol $batch[0] --limit $batch[1]
        if($LASTEXITCODE -ne 0){throw 'NAS exporter staging failed'}
        & scripts/run_nas_export_probe.ps1
        $result=Join-Path $root ('.tmp/orb_jp225_full_worker/MQL5/Files/NasExportProbe/'+$batch[0]+'_results.jsonl')
        $rows=@(Get-Content -LiteralPath $result | ForEach-Object {$_|ConvertFrom-Json})
        if($rows.Count -ne $batch[1] -or @($rows|Where-Object {$_.error -or $_.status -notlike 'CSV complete:*'}).Count){throw 'Incomplete NAS batch; inspect results'}
        Copy-Item -LiteralPath $result -Destination (Join-Path $root ('logs/NasStrategyLibrary_20260912/'+$batch[0]+'_exports.jsonl'))
    }
} finally {Pop-Location}
