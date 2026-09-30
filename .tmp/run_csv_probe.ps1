$ErrorActionPreference='Stop'
$root=(Resolve-Path .).Path
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$source=Join-Path $root 'tests/mql5/AuditTradeCsvProbe.mq5'
$log=Join-Path $root '.tmp/AuditTradeCsvProbe.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(180000)){throw 'Probe compile timeout'}
if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw 'Probe compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker 'MQL5/Scripts/AuditTradeCsvProbe.ex5') -Force
$ini=Join-Path $root '.tmp/AuditTradeCsvProbe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=AuditTradeCsvProbe','Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(180000)){throw 'Probe timeout'}
$report=Join-Path $worker 'MQL5/Files/AuditTradeCsvProbe.txt'
if(-not (Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $start.AddSeconds(-2)){throw 'Probe output missing'}
Get-Content $report
