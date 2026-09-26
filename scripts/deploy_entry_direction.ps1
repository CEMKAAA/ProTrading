$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$terminal='C:\MT5\DEMO\terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){
 throw 'Close MT5 DEMO before deployment'
}
$backup=Join-Path $root ('.tmp/entry_direction_deploy_before_'+(Get-Date -Format yyyyMMdd_HHmmss))
$targets=@(
 @('orb','OrbUltimateEA_StrategyLibrary','orb'),
 @('macrossover_orb','MaCrossOverOrbEA','MaCrossOverOrb'),
 @('SolAdvanced','LiqNarrativeSol_Advanced','SolAdvanced')
)
foreach($target in $targets){
 $source=Join-Path $root ('IndicatorCodeExamples/'+$target[0])
 $dest=Join-Path 'C:\MT5\DEMO\MQL5\Experts' $target[2]
 $log=Join-Path $source ($target[1]+'.mq5.direction.log')
 if((Get-Content $log -Tail 1) -notmatch 'Result: 0 errors, 0 warnings'){throw "Unverified compile: $source"}
 $files=@((Join-Path $source ($target[1]+'.mq5')),(Join-Path $source ($target[1]+'.ex5')))
 $files+=@(Get-ChildItem -LiteralPath $source -Filter '*.mqh' -File|ForEach-Object {$_.FullName})
 New-Item -ItemType Directory -Path $dest -Force|Out-Null
 $before=Join-Path $backup $target[2]
 New-Item -ItemType Directory -Path $before -Force|Out-Null
 foreach($file in $files){
  $path=Join-Path $dest ([IO.Path]::GetFileName($file))
  if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination $before}
  Copy-Item -LiteralPath $file -Destination $path -Force
  if((Get-FileHash -LiteralPath $file).Hash -ne (Get-FileHash -LiteralPath $path).Hash){throw "Deployment mismatch: $path"}
 }
 Write-Output "DEPLOYED $dest : $($files.Count) files, hashes matched"
}
Write-Output "BACKUP=$backup"
