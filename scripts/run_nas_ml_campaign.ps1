$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:OMP_NUM_THREADS='1';$env:OPENBLAS_NUM_THREADS='1';$env:MKL_NUM_THREADS='1'
$common=Join-Path $env:APPDATA 'MetaQuotes/Terminal/Common/Files/NasML'
$out=Join-Path $root 'logs/NasStrategyLibrary_20260912/campaign'
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location $root
try {
    python -u scripts/nas_ml_campaign.py --root $common --out $out *> (Join-Path $out 'training.log')
    if($LASTEXITCODE -ne 0){Get-Content (Join-Path $out 'training.log') -Tail 20;throw 'NAS campaign failed'}
    Get-Content (Join-Path $out 'training.log') -Tail 5
} finally {Pop-Location}
