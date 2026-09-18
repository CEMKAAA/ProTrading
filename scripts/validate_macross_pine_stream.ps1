param([switch]$InstallDemo)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'logs/macross_pine_stream'
New-Item -ItemType Directory -Path $report -Force | Out-Null
$editor='C:\MT5\DEMO\MetaEditor64.exe'
$sources=@('IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5',
 'tests/mql5/MaCrossPineStreamProbe.mq5','tests/mql5/MaCrossMarketTimingProbe.mq5','tests/mql5/MaCrossEventHistoryProbe.mq5')
$build=Join-Path $root ('.tmp/ma_build_'+[guid]::NewGuid().ToString('N').Substring(0,8))
$runId=[guid]::NewGuid().ToString('N').Substring(0,8)
$outputs=@('MaCrossPineProbe.json','MaCrossMarketTiming.jsonl','MaCrossEventHistoryProbe.json','MaCrossPineDirections.txt')
New-Item -ItemType Directory -Path (Join-Path $build 'IndicatorCodeExamples/macrossover_orb'),(Join-Path $build 'tests/mql5') -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $root 'IndicatorCodeExamples/macrossover_orb') -Filter '*.mqh' | ForEach-Object {
 Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $build 'IndicatorCodeExamples/macrossover_orb')
}
foreach($relative in $sources){Copy-Item -LiteralPath (Join-Path $root $relative) -Destination (Join-Path $build $relative)}
foreach($relative in $sources | Where-Object {$_ -like 'tests/*'}){
 $path=Join-Path $build $relative
 $text=[IO.File]::ReadAllText($path)
 foreach($output in $outputs){$text=$text.Replace('"'+$output+'"','"'+$runId+'_'+$output+'"')}
 [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
}
foreach($relative in $sources){
 $source=Join-Path $build $relative
 $log=Join-Path $report ((Split-Path $source -Leaf)+'.verified.compile.log')
 $started=Get-Date
 $process=Start-Process $editor -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$process.WaitForExit(120000)){throw "Compile timeout: $relative"}
 if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $started){throw 'Missing fresh compile log'}
 if(![IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings')){throw "Compile failed: $log"}
 Get-Content -LiteralPath $log -Tail 1
}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
foreach($name in @('MaCrossPineStreamProbe','MaCrossMarketTimingProbe','MaCrossEventHistoryProbe')){
 if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object {$_.ExecutablePath -eq $terminal}).Count){throw 'Worker already running; not touching it'}
 $runName=$name+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
 Copy-Item -LiteralPath (Join-Path $build "tests/mql5/$name.ex5") -Destination (Join-Path $worker "MQL5/Scripts/$runName.ex5")
 $ini=Join-Path $report "$name.ini"
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',"Script=$runName",'Symbol=JP225m','Period=M5','ShutdownTerminal=1') | Set-Content -LiteralPath $ini -Encoding ASCII
 $started=Get-Date
 $process=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$process.WaitForExit(120000)){throw 'Isolated test timeout; no deployment'}
 $output=switch($name){'MaCrossPineStreamProbe'{'MaCrossPineProbe.json'} 'MaCrossMarketTimingProbe'{'MaCrossMarketTiming.jsonl'} default{'MaCrossEventHistoryProbe.json'}}
 $path=Join-Path $worker "MQL5/Files/${runId}_$output"
 if(!(Test-Path $path) -or (Get-Item $path).LastWriteTime -lt $started){throw "No fresh test result: $output"}
 Copy-Item -LiteralPath $path -Destination (Join-Path $report $output)
 Get-Content -LiteralPath $path
}
$probe=Get-Content -LiteralPath (Join-Path $report 'MaCrossPineProbe.json') -Raw | ConvertFrom-Json
if($probe.failed -ne 0 -or $probe.checks -lt 12000){throw 'MT5 regression failed'}
$events=Get-Content -LiteralPath (Join-Path $report 'MaCrossEventHistoryProbe.json') -Raw | ConvertFrom-Json
if($events.failed -ne 0 -or $events.checks -lt 65 -or $events.real_invalid -ne 0 -or $events.real_trades -ne $events.real_raw){throw 'Event history integration failed; no deployment'}
$comparison=& python (Join-Path $root 'scripts/check_macross_pine_reference.py') (Join-Path $worker "MQL5/Files/${runId}_MaCrossPineDirections.txt")
if($LASTEXITCODE -ne 0){throw 'Independent reference comparison failed'}
$comparison | Set-Content -LiteralPath (Join-Path $report 'reference.json') -Encoding UTF8
$comparison
foreach($relative in $sources | Where-Object {$_ -notlike 'tests/*'}){
 $binary=[IO.Path]::ChangeExtension($relative,'.ex5')
 if((Get-FileHash -LiteralPath (Join-Path $root $relative)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $build $relative)).Hash){throw 'Source changed during validation'}
 foreach($header in Get-ChildItem -LiteralPath (Join-Path $build 'IndicatorCodeExamples/macrossover_orb') -Filter '*.mqh'){
  if((Get-FileHash -LiteralPath $header.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $root ('IndicatorCodeExamples/macrossover_orb/'+$header.Name))).Hash){throw 'Include changed during validation'}
 }
 Copy-Item -LiteralPath (Join-Path $build $binary) -Destination (Join-Path $root $binary)
}
if(!$InstallDemo){return}
$sourceDir=Join-Path $root 'IndicatorCodeExamples/macrossover_orb'
$target='C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb'
$backup=Join-Path $report ('demo_backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup,$target -Force | Out-Null
$files=@(Get-ChildItem -LiteralPath $sourceDir -File | Where-Object {$_.Extension -eq '.mqh'})
$files+=@(Get-Item -LiteralPath (Join-Path $sourceDir 'MaCrossOverOrbEA.mq5'),(Join-Path $sourceDir 'MaCrossOverOrbEA.ex5'),(Join-Path $sourceDir 'README.md'))
$manifest=@()
foreach($file in $files){
 $destination=Join-Path $target $file.Name
 if(Test-Path -LiteralPath $destination){Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $file.Name)}
 Copy-Item -LiteralPath $file.FullName -Destination $destination
 $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
 if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hash){throw "Hash mismatch: $destination"}
 $manifest+=@{path=$destination;sha256=$hash}
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $report 'demo_manifest.json') -Encoding UTF8
Write-Output "Verified $($manifest.Count) DEMO files. No EA attached, restarted, or enabled."
