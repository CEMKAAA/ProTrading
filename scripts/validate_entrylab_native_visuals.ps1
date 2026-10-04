$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root '.tmp/entrylab_native_visuals'
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$main=Join-Path $root 'IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5'
$probe=Join-Path $root 'tests/mql5/EntryLabNativeVisualProbe.mq5'
foreach($source in @($main,$probe)){
 $log=Join-Path $stage ((Split-Path $source -Leaf)+'.log')
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(120000)){throw 'Compile timeout'}
 if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 30;throw 'Compile failed'}
 Get-Content $log -Tail 1
}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Worker busy'}
Get-ChildItem -LiteralPath 'C:\MT5\DEMO\MQL5\Files' -Filter 'EntryLabIndependent_*.state' |
 ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $worker ('MQL5/Files/'+$_.Name)) -Force}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker 'MQL5/Scripts/EntryLabNativeVisualProbe.ex5') -Force
$ini=Join-Path $stage 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=EntryLabNativeVisualProbe','Symbol=BTCUSDm','Period=M1','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Probe timeout; worker retained'}
$result=Join-Path $worker 'MQL5/Files/EntryLabNativeVisualProbe.txt'
Get-Content $result
if((Get-Content $result -Raw)-notmatch '\bfailed=0\b'){throw 'Visual verification failed'}
