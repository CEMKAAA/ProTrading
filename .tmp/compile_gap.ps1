$ErrorActionPreference='Stop'
$root=(Resolve-Path .).Path
$compiler='C:\MT5\DEMO\MetaEditor64.exe'
foreach($item in @(
  @('IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5','ma'),
  @('IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5','orb'),
  @('IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5','sol')
)) {
  $source=(Resolve-Path $item[0]).Path
  $dir=Split-Path $source
  $shadow=Join-Path $dir ('_inverse_gap_compile_'+$item[1]+'.mq5')
  $log=Join-Path $root ('.tmp/inverse_gap_'+$item[1]+'.log')
  $binary=[IO.Path]::ChangeExtension($shadow,'.ex5')
  if(-not ((Test-Path $binary) -and ((Get-Content $log -Tail 2 -ErrorAction SilentlyContinue) -match '0 errors'))) {
    Copy-Item -LiteralPath $source -Destination $shadow -Force
    $p=Start-Process $compiler -ArgumentList ('/compile:"'+$shadow+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
    if(-not $p.WaitForExit(120000)){Stop-Process -Id $p.Id -Force;throw "Compile timeout $($item[1])"}
  }
  $result=Get-Content -LiteralPath $log -Tail 8 -ErrorAction SilentlyContinue
  "=== $($item[1]) ===";$result
  if(-not ($result -match '0 errors')){throw "Compile failed $($item[1])"}
  if(-not (Test-Path -LiteralPath $binary)){throw "Missing compiled binary $($item[1])"}
  Move-Item -LiteralPath $binary -Destination ([IO.Path]::ChangeExtension($source,'.ex5')) -Force
  Remove-Item -LiteralPath $shadow -Force
}
