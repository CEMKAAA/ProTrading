param([ValidateSet('compile-start','baseline')][string]$Mode='compile-start')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'tmp/universal_connection_validation'
$source=Join-Path $root 'tests/mql5/CanonicalMaCrossParity.mq5'
$log=Join-Path $stage 'canonical-compile.log'
if($Mode-eq 'compile-start'){
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 Write-Output ('CANONICAL_COMPILE_PID='+$p.Id);exit
}
if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Canonical probe requires a clean compile'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
if(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal){throw 'Isolated worker is busy'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker 'MQL5/Scripts/CanonicalMaCrossParity.ex5') -Force
$ini=Join-Path $stage 'canonical.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=CanonicalMaCrossParity','Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
Write-Output ('CANONICAL_WORKER_PID='+$p.Id)
