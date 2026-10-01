$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq (Join-Path $worker 'terminal64.exe')}){throw 'Worker busy'}
$source=Join-Path $PSScriptRoot 'LabHistoryDiagnostic.mq5'
$log=$source+'.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'Compile timeout'}
Get-Content $log -Tail 1
if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){throw 'Compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker 'MQL5/Scripts/LabHistoryDiagnostic.ex5') -Force
$ini=Join-Path $PSScriptRoot 'lab_history_diagnostic.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=LabHistoryDiagnostic','Symbol=EURUSDm','Period=M1','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Diagnostic timeout'}
Get-Content (Join-Path $worker 'MQL5/Files/LabHistoryDiagnostic.txt')
