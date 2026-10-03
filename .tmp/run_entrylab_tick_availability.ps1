$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Worker busy'}
$source=Join-Path $PSScriptRoot 'EntryLabTickAvailability.mq5'
$log=$source+'.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'Compile timeout'}
if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw 'Compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker 'MQL5/Scripts/EntryLabTickAvailability.ex5') -Force
$ini=Join-Path $PSScriptRoot 'entrylab_tick_availability.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=EntryLabTickAvailability','Symbol=BTCUSDm','Period=M1','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(600000)){throw 'Probe timeout; isolated worker retained'}
Get-Content -LiteralPath (Join-Path $worker 'MQL5/Files/EntryLabTickAvailability.txt')
