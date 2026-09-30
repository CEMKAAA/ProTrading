$ErrorActionPreference='Stop'
$root=(Resolve-Path .).Path
$file=Join-Path $root 'tests/mql5/MaInverseTouchProbe.mq5'
$log=Join-Path $root '.tmp/MaInverseTouchProbe.log'
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(120000)){throw 'Compile timeout'}
if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw 'Compile failed'}
Copy-Item ([IO.Path]::ChangeExtension($file,'.ex5')) (Join-Path $worker 'MQL5/Scripts/MaInverseTouchProbe.ex5') -Force
$ini=Join-Path $root '.tmp/MaInverseTouchProbe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=MaInverseTouchProbe','Symbol=EURUSDm','Period=M1','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(120000)){throw 'Terminal timeout'}
$result=Join-Path $worker 'MQL5/Files/MaInverseTouchProbe.csv'
if(-not (Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $start.AddSeconds(-2)){throw 'Result missing'}
Get-Content $result
