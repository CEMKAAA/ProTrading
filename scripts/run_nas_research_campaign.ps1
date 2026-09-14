$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'run_nas_campaign_exports.ps1')
& (Join-Path $PSScriptRoot 'run_nas_ml_campaign.ps1')
