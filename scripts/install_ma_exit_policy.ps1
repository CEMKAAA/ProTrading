param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stagePath=(Resolve-Path -LiteralPath $Stage).Path
$source=Join-Path $root 'IndicatorCodeExamples/macrossover_orb'
$build=Join-Path $stagePath 'IndicatorCodeExamples/macrossover_orb'
$target='C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb'
$parityDir=Join-Path $root 'logs/ma_legacy_parity_20260919'
$parity=Get-Content (Join-Path $parityDir 'comparison.json') -Raw|ConvertFrom-Json
if(!$parity.all_equal -or $parity.strategies -ne 16 -or $parity.trade_rows -ne 463){throw 'Legacy parity not verified'}
$tag=Get-Date -Format yyyyMMdd_HHmmss
$backup=Join-Path $root "logs/ma_exit_install/$tag"
New-Item -ItemType Directory -Force $backup,$target | Out-Null
foreach($name in @('MaExitPolicyProbe','MaStrategySaveProbe','MaCrossPineProbe')){
 $result=@(Get-ChildItem -LiteralPath $stagePath -Filter "*_$name.json")
 if($result.Count -ne 1){throw "Missing verified result $name"}
 $r=Get-Content $result[0].FullName -Raw|ConvertFrom-Json
 if($r.failed -ne 0 -or $r.checks -le 0){throw "Failed test $name"}
}
$compile=Join-Path $build 'MaCrossOverOrbEA.mq5.log'
if((Get-Content $compile -Raw) -notmatch 'Result: 0 errors, 0 warnings'){throw 'EA build not verified'}
$files=@(Get-ChildItem $build -File | Where-Object {$_.Extension -eq '.mqh' -or $_.Name -eq 'MaCrossOverOrbEA.mq5'})
foreach($file in $files){
 if((Get-FileHash $file.FullName).Hash -ne (Get-FileHash (Join-Path $source $file.Name)).Hash){throw "Source changed after tests: $($file.Name)"}
 $replayed=Join-Path $parityDir ('candidate/IndicatorCodeExamples/macrossover_orb/'+$file.Name)
 if($file.Name -eq 'MaCrossOverOrbEA.mq5'){
  $replayText=[IO.File]::ReadAllText($replayed).Replace("      ProbeTrade(entryT,execDir,sim);`r`n",'')
  if($replayText -cne [IO.File]::ReadAllText($file.FullName)){throw 'EA changed after parity replay'}
 }elseif((Get-FileHash $file.FullName).Hash -ne (Get-FileHash $replayed).Hash){throw "Header changed after parity replay: $($file.Name)"}
}
function Install-VerifiedFile($from,$to,$backupName){
 if((Test-Path -LiteralPath $to) -and (Get-FileHash $from).Hash -eq (Get-FileHash $to).Hash){return}
 $temp=$to+'.staged_'+$tag
 Copy-Item -LiteralPath $from -Destination $temp
 if((Get-FileHash $temp).Hash -ne (Get-FileHash $from).Hash){throw 'Staged hash mismatch'}
 $old=Join-Path $backup $backupName
 if(Test-Path -LiteralPath $to){Move-Item -LiteralPath $to -Destination $old}
 try {Move-Item -LiteralPath $temp -Destination $to}
 catch {if((Test-Path $old) -and !(Test-Path $to)){Move-Item -LiteralPath $old -Destination $to};throw}
}
$binary=Join-Path $build 'MaCrossOverOrbEA.ex5'
Install-VerifiedFile $binary (Join-Path $source 'MaCrossOverOrbEA.ex5') 'workspace_MaCrossOverOrbEA.ex5'
$files+=Get-Item $binary
$files+=Get-Item (Join-Path $source 'EXIT_MODES.md')
$manifest=@()
foreach($file in $files){
 $to=Join-Path $target $file.Name
 Install-VerifiedFile $file.FullName $to ('demo_'+$file.Name)
 $hash=(Get-FileHash $file.FullName).Hash
 if((Get-FileHash $to).Hash -ne $hash){throw "Deploy mismatch: $to"}
 $manifest+=@{path=$to;sha256=$hash}
}
$manifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $backup 'manifest.json') -Encoding UTF8
Write-Output "Verified $($manifest.Count) files in $target. No running EA restarted. Backup: $backup"
