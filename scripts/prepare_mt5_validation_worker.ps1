param(
  [string]$Source = "C:\MT5\DEMO",
  [string]$Target = "C:\tmp\MT5_VALIDATION_WORKER"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $Source)) {
  throw "Source MT5 folder not found: $Source"
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null

$topFiles = @("terminal64.exe", "MetaEditor64.exe", "metatester64.exe", "Terminal.ico", "uninstall.exe")
foreach ($file in $topFiles) {
  $src = Join-Path $Source $file
  if (Test-Path -LiteralPath $src) {
    Copy-Item -LiteralPath $src -Destination (Join-Path $Target $file) -Force
  }
}

$copyDirs = @("Config", "MQL5", "Profiles", "Sounds")
foreach ($dir in $copyDirs) {
  $src = Join-Path $Source $dir
  $dst = Join-Path $Target $dir
  if (Test-Path -LiteralPath $src) {
    robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) {
      throw "robocopy failed for $dir exit=$LASTEXITCODE"
    }
  }
}

foreach ($dir in @("logs", "Tester", "temp")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $Target $dir) | Out-Null
}

$basesSrc = Join-Path $Source "Bases"
$basesDst = Join-Path $Target "Bases"
if (Test-Path -LiteralPath $basesSrc) {
  if (!(Test-Path -LiteralPath $basesDst)) {
    New-Item -ItemType Junction -Path $basesDst -Target $basesSrc | Out-Null
  }
}

$summary = [ordered]@{
  source = $Source
  target = $Target
  terminal = (Join-Path $Target "terminal64.exe")
  portable_args = "/portable"
  bases = if (Test-Path -LiteralPath $basesDst) { "junction:$basesSrc" } else { "missing" }
}

$summary | ConvertTo-Json -Depth 4
