$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Isolated worker busy'}
$name='MaAuditWindowCacheProbe_'+[Guid]::NewGuid().ToString('N').Substring(0,10)
$stage=Join-Path $root ('.tmp/ma_window_'+(Get-Date -Format yyyyMMdd_HHmmss))
$source=Join-Path $stage ('tests/mql5/'+$name+'.mq5')
New-Item -ItemType Directory -Path (Split-Path $source) -Force|Out-Null
$text=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/MaAuditWindowCacheProbe.mq5')).Replace('../../IndicatorCodeExamples/','../../../../IndicatorCodeExamples/').Replace('MaAuditWindowCacheProbe.txt',$name+'.txt')
[IO.File]::WriteAllText($source,$text,(New-Object Text.UTF8Encoding($false)))
$log=$source+'.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
if([IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 30;throw 'Compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
$ini=Join-Path $stage 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=USDJPYm','Period=M5','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
$started=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Probe timeout'}
$report=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
if(!(Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh result missing'}
$result=Get-Content $report -Raw
$result|Set-Content (Join-Path $stage 'result.txt')
Write-Output $result
if($result -notmatch 'failed=0'){throw 'Window cache checks failed'}
Write-Output "STAGE=$stage"
