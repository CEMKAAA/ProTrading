$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/NasPredictionProbe/NasPredictionProbe.mq5'
$log=$source+'.compile.log';$before=Get-Date
$p=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(240000)){throw 'Compile timeout'}
if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $before -or !([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){Get-Content $log -Tail 12;throw 'Compile failed'}
$exe=Join-Path $root '.tmp/orb_jp225_full_worker/terminal64.exe'
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $exe}).Count){throw 'Isolated worker is busy'}
$p=Start-Process -FilePath $exe -ArgumentList ('/portable /config:"'+(Join-Path $root 'logs/NasStrategyLibrary_20260912/prediction.ini')+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Prediction probe timeout'}
$result=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Files/NasPredictionProbe/result.json'
if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $before){throw 'Fresh prediction results missing'}
Copy-Item -LiteralPath $result -Destination (Join-Path $root 'logs/NasStrategyLibrary_20260912/mql_prediction_parity.json')
$r=Get-Content $result -Raw|ConvertFrom-Json
$r|ConvertTo-Json
if($r.failed -ne 0 -or $r.models -ne 38 -or $r.vectors -ne 456 -or $r.max_error -gt 1e-10){throw 'Prediction parity failed'}
