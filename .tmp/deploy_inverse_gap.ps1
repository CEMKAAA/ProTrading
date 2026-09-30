$ErrorActionPreference='Stop'
$root=(Resolve-Path .).Path
$destRoot='C:\MT5\DEMO\MQL5\Experts'
if(-not (Test-Path -LiteralPath $destRoot)){throw 'MT5 demo Experts directory missing'}
if(Get-Process terminal64 -ErrorAction SilentlyContinue){throw 'Close MT5 terminal before deployment'}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $root ('.tmp/inverse_gap_deploy_backup_'+$stamp)
New-Item -ItemType Directory -Path $backup|Out-Null
$files=@(
  @('IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5','MaCrossOverOrb/MaCrossOverOrbEA.mq5'),
  @('IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.ex5','MaCrossOverOrb/MaCrossOverOrbEA.ex5'),
  @('IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5','orb/OrbUltimateEA_StrategyLibrary.mq5'),
  @('IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.ex5','orb/OrbUltimateEA_StrategyLibrary.ex5'),
  @('IndicatorCodeExamples/orb/OrbStrategyUserLibrary.mqh','orb/OrbStrategyUserLibrary.mqh'),
  @('IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5','SolAdvanced/LiqNarrativeSol_Advanced.mq5'),
  @('IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.ex5','SolAdvanced/LiqNarrativeSol_Advanced.ex5'),
  @('IndicatorCodeExamples/SolAdvanced/LiqStrategyLibrary.mqh','SolAdvanced/LiqStrategyLibrary.mqh'),
  @('IndicatorCodeExamples/SolAdvanced/LiqImagePresets.mqh','SolAdvanced/LiqImagePresets.mqh')
)
foreach($pair in $files){
  $source=(Resolve-Path -LiteralPath $pair[0]).Path
  $dest=Join-Path $destRoot $pair[1]
  $resolvedDest=[IO.Path]::GetFullPath($dest)
  if(-not $resolvedDest.StartsWith($destRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe destination'}
  if(-not (Test-Path -LiteralPath (Split-Path $dest))){throw "Missing destination folder $dest"}
  $old=Join-Path $backup $pair[1]
  New-Item -ItemType Directory -Path (Split-Path $old) -Force|Out-Null
  if(Test-Path -LiteralPath $dest){Copy-Item -LiteralPath $dest -Destination $old -Force}
  $temp=$dest+'.inverse_gap.tmp'
  Copy-Item -LiteralPath $source -Destination $temp -Force
  Move-Item -LiteralPath $temp -Destination $dest -Force
  if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $dest).Hash){throw "Hash mismatch $dest"}
  "VERIFIED $($pair[1])"
}
"BACKUP $backup"
