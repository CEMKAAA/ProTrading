$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tag=(Get-Date -Format yyyyMMdd_HHmmss_fff)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
$run=Join-Path $root "logs/ma_of_runs/$tag"
$test=Join-Path $run 'tests/mql5'
$core=Join-Path $run 'IndicatorCodeExamples/macrossover_orb'
New-Item -ItemType Directory -Force $test,$core|Out-Null
$w=Join-Path $root '.tmp/orb_jp225_full_worker'
$t=Join-Path $w terminal64.exe
$lockPath=Join-Path $root '.tmp/ma_of_screen.lock'
$lock=$null
try {
 $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $t).Count){throw 'Worker busy'}
 $inputName="MaOfInput_$tag.csv"; $outputName="MaOfOutput_$tag.csv"
 Copy-Item "$w/MQL5/Files/MaOfScreenInput.csv" "$run/input.csv"
 Copy-Item "$run/input.csv" "$w/MQL5/Files/$inputName"
 Copy-Item "$root/IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlowCore.mqh" $core
 $source=[IO.File]::ReadAllText("$root/tests/mql5/MaOrderFlowScreen.mq5")
 $source=$source.Replace('MaOfScreenInput.csv',$inputName).Replace('MaOfScreenOutput.csv',$outputName)
 $f=Join-Path $test 'MaOrderFlowScreen.mq5'
 [IO.File]::WriteAllText($f,$source,[Text.UTF8Encoding]::new($false))
 $log="$f.log"
 $p=Start-Process C:/MT5/DEMO/MetaEditor64.exe -ArgumentList ('/compile:"'+$f+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(120000)){throw 'Compiler timeout'}
 if(!(Test-Path $log) -or (Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){throw 'Compile failed'}
 $scriptName="MaOf_$tag"
 Copy-Item ($f -replace '\.mq5$','.ex5') "$w/MQL5/Scripts/$scriptName.ex5"
 $ini=Join-Path $run screen.ini
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',"Script=$scriptName",'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini
 $started=Get-Date
 $p=Start-Process $t -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(330000)){throw 'Screen timeout; worker left running; do not start another run'}
 $result="$w/MQL5/Files/$outputName"
 if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started){throw 'Missing fresh result'}
 Copy-Item $result "$run/results.csv"
 $rows=@(Import-Csv "$run/results.csv");$expected=@(Get-Content "$run/input.csv").Count
 if($rows.Count -ne $expected){throw "Incomplete run $($rows.Count)/$expected"}
 $valid=@($rows|Where-Object valid -eq 'true')
 $summary=foreach($mask in 0..7){
  $a=@($valid|Where-Object {(!($mask-band 1)-or $_.profile -eq 'true') -and (!($mask-band 2)-or $_.activity_pass -eq 'true') -and (!($mask-band 4)-or $_.delta_pass -eq 'true')})
  [pscustomobject]@{mask=$mask;count=$a.Count;wins=@($a|Where-Object {[double]$_.r -gt 0}).Count;netR=($a|Measure-Object r -Sum).Sum;uniqueSymbolTimes=@($a|Group-Object symbol,time).Count}
 }
 $summary|ConvertTo-Json|Set-Content "$run/summary.json"
 $rows|Group-Object valid,reason|Select-Object Count,Name|ConvertTo-Json|Set-Content "$run/coverage.json"
 Get-ChildItem $run -Recurse -File|Where-Object Name -ne manifest.json|Get-FileHash|Select-Object Path,Hash|ConvertTo-Json|Set-Content "$run/manifest.json"
 $summary|Format-Table
 Write-Output "RUN=$run"
} finally {if($null -ne $lock){$lock.Dispose()}}
