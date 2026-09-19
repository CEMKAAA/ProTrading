$ErrorActionPreference='Stop';$root=$PWD.Path;$tag=Get-Date -Format yyyyMMdd_HHmmss
$dir=Join-Path $root ('.tmp/sol_probe_'+$tag);New-Item -ItemType Directory -Force $dir|Out-Null
$src=Join-Path $root 'tests/mql5/SolanaQuoteProbe.mq5';$out='SolanaQuoteProbe_'+$tag
$s=[IO.File]::ReadAllText($src).Replace('SolanaQuoteProbe.json',$out+'.json');$f=Join-Path $dir ($out+'.mq5');[IO.File]::WriteAllText($f,$s)
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$f+'" /log:"'+$f+'.log"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'Compile timeout'};Get-Content ($f+'.log') -Tail 2
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal).Count){throw 'Worker busy'}
Copy-Item ([IO.Path]::ChangeExtension($f,'.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$out+'.ex5'))
$ini=Join-Path $dir 'probe.ini';@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$out),'Symbol=SOLUSDm','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Quote read timeout'}
$result=Join-Path $worker ('MQL5/Files/'+$out+'.json');Copy-Item $result $dir
$r=Get-Content $result -Raw|ConvertFrom-Json;$r|Select-Object symbol,bars,bars_error,ticks,tick_error
$r.samples|Where-Object {$_.signal_bar -match '(03:00|05:55|06:00|07:55|08:00|09:00|10:00)'}|Format-Table
Write-Output "REPORT=$dir"
