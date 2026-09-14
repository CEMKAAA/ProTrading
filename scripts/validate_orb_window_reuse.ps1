$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
python (Join-Path $PSScriptRoot 'build_orb_window_probe.py')
if($LASTEXITCODE -ne 0){throw 'Probe staging failed'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$exe=Join-Path $worker 'terminal64.exe'
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $exe}).Count){throw 'Isolated terminal busy; do not interrupt it'}
$source=Join-Path $worker 'MQL5/Scripts/OrbWindowProbe/OrbWindowProbe.mq5'
$report=Join-Path $root 'logs/AuditWindowReuse_20260914'
$log=Join-Path $report 'orb_window.compile.log'
for($attempt=1;$attempt -le 3;$attempt++) {
    $p=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
    if(!$p.WaitForExit(240000)){throw 'Compile timeout'}
    if(!([IO.File]::ReadAllText($log).Contains('error 119: EX5 write error'))){break}
    Start-Sleep -Seconds 2
}
Get-Content $log -Tail 3
if(!([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){Get-Content $log|Select-String 'error';throw 'Compile failed'}
$before=Get-Date
$p=Start-Process -FilePath $exe -ArgumentList ('/portable /config:"'+(Join-Path $report 'orb_window.ini')+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(3600000)){throw 'Benchmark timeout; isolated terminal only'}
$result=Join-Path $worker 'MQL5/Files/OrbWindowProbe/results.jsonl'
if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $before){throw 'Fresh benchmark missing'}
Copy-Item -LiteralPath $result -Destination (Join-Path $report 'orb_window.jsonl')
$rows=@(Get-Content $result|ForEach-Object {$_|ConvertFrom-Json})
$rows|Format-Table
if($rows.Count -ne 7 -or @($rows|Where-Object {!$_.same -or !$_.ok}).Count){throw 'Window parity/coverage failed'}
$evidence=@(Get-ChildItem (Join-Path $worker 'MQL5/Scripts/OrbWindowProbe') -File|Where-Object {$_.Extension -eq '.mqh'}|ForEach-Object {
    [pscustomobject]@{name=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
})
$evidence|ConvertTo-Json -Depth 3|Set-Content (Join-Path $report 'orb_window_dependencies.json') -Encoding UTF8
