$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tag=Get-Date -Format yyyyMMdd_HHmmss
$stage=Join-Path $root ('.tmp/ma_trender_'+$tag)
New-Item -ItemType Directory -Force $stage|Out-Null
$file=Join-Path $root 'tests/mql5/MaTrenderProbe.mq5'
$log=Join-Path $stage 'compile.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'Compile timeout'}
if(!(Test-Path $log) -or [IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw 'Probe compile failed'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal).Count){throw 'Isolated worker busy'}
$name='MaTrenderProbe_'+$tag
Copy-Item ([IO.Path]::ChangeExtension($file,'.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
$ini=Join-Path $stage 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Probe timeout'}
$result=Join-Path $worker 'MQL5/Files/MaTrenderProbe.csv'
if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $start){throw 'Missing fresh probe output'}
Copy-Item $result $stage
python (Join-Path $root 'scripts/check_trender_reference.py') (Join-Path $stage 'MaTrenderProbe.csv')
if($LASTEXITCODE -ne 0){throw 'Reference checks failed'}
Write-Output "STAGE=$stage"
