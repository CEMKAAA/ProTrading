$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
python (Join-Path $PSScriptRoot 'build_nas_window_probe.py')
if($LASTEXITCODE -ne 0){throw 'Probe staging failed'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$exe=Join-Path $worker 'terminal64.exe'
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $exe}).Count){throw 'Isolated terminal busy; do not interrupt it'}
$source=Join-Path $worker 'MQL5/Scripts/NasWindowProbe/NasWindowProbe.mq5'
$report=Join-Path $root 'logs/AuditWindowReuse_20260914'
$log=Join-Path $report 'nas_window.compile.log'
$p=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(240000)){throw 'Compile timeout'}
Get-Content $log -Tail 2
if(!([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){throw 'Compile failed'}
$before=Get-Date
$p=Start-Process -FilePath $exe -ArgumentList ('/portable /config:"'+(Join-Path $report 'nas_window.ini')+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(3600000)){throw 'Benchmark timeout; isolated terminal only'}
$result=Join-Path $worker 'MQL5/Files/NasWindowProbe/results.jsonl'
if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $before){throw 'Fresh benchmark missing'}
Copy-Item -LiteralPath $result -Destination (Join-Path $report 'nas_window.jsonl')
$rows=@(Get-Content $result|ForEach-Object {$_|ConvertFrom-Json})
$rows|Format-Table
if($rows.Count -ne 7 -or @($rows|Where-Object {!$_.same -or $_.blocked}).Count){throw 'Window parity/coverage failed'}
