$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/NasExportProbe/NasExportProbe.mq5'
$log=$source+'.compile.log';$before=Get-Date
$p=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(240000)){throw 'Compile timeout'}
if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $before -or !([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){Get-Content $log -Tail 25;throw 'Compile failed'}
Get-Content $log -Tail 3
$exe=Join-Path $root '.tmp/orb_jp225_full_worker/terminal64.exe'
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $exe}).Count){throw 'Isolated worker already running; not touching it'}
$p=Start-Process -FilePath $exe -ArgumentList ('/portable /config:"'+(Join-Path $root 'logs/NasStrategyLibrary_20260912/export.ini')+'"') -WindowStyle Hidden -PassThru
Write-Output ('Isolated no-order exporter PID='+$p.Id)
$p.WaitForExit()
Get-ChildItem -LiteralPath (Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Files/NasExportProbe') -Filter '*_results.jsonl' | ForEach-Object {Get-Content -LiteralPath $_.FullName -Tail 19}
