$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'logs/NasStrategyLibrary_20260912'
$probe=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/NasLibraryProbe/NasLibraryProbe.mq5'
foreach($source in @((Join-Path $root 'IndicatorCodeExamples/NasUltimate_StrategyLibrary.mq5'),$probe)) {
 $log=$source+'.compile.log';$before=Get-Date
 $p=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(240000)){throw 'Compile timeout; no production deployment attempted'}
 if(!(Test-Path -LiteralPath $log) -or (Get-Item -LiteralPath $log).LastWriteTime -lt $before){throw 'Fresh compile log missing'}
 Get-Content -LiteralPath $log -Tail 3
 if(!([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){throw 'Compile failed'}
}
$exe=Join-Path $root '.tmp/orb_jp225_full_worker/terminal64.exe'
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $exe}).Count){throw 'Isolated worker already running'}
$before=Get-Date
$p=Start-Process -FilePath $exe -ArgumentList ('/portable /config:"'+(Join-Path $report 'probe.ini')+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(300000)){throw 'Probe timeout; check isolated worker logs; no production terminal touched'}
$result=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Files/NasLibraryProbe/result.json'
if(!(Test-Path -LiteralPath $result) -or (Get-Item -LiteralPath $result).LastWriteTime -lt $before){throw 'Fresh probe result missing'}
Copy-Item -LiteralPath $result -Destination (Join-Path $report 'mql_probe.json')
$r=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json
$r|ConvertTo-Json -Depth 4
if($r.failed -ne 0 -or $r.presets_parsed -lt 19){throw 'NAS probe failed'}
