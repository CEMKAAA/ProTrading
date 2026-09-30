$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $terminal}){throw 'Isolated worker busy'}
$stage=Join-Path $root ('.tmp/csv_boundary_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$name='AuditCsvBoundaryProbe_'+[Guid]::NewGuid().ToString('N').Substring(0,10)
$source=Join-Path $stage ('tests/mql5/'+$name+'.mq5')
New-Item -ItemType Directory -Path (Split-Path $source) -Force | Out-Null
$text=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/AuditCsvBoundaryProbe.mq5'))
$text=$text.Replace('../../IndicatorCodeExamples/','../../../../IndicatorCodeExamples/').Replace('AuditCsvBoundaryProbe.txt',$name+'.txt')
[IO.File]::WriteAllText($source,$text,(New-Object Text.UTF8Encoding($false)))
$log=Join-Path $stage 'compile.log'
$started=Get-Date
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(180000)){throw 'Boundary compile timeout'}
if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $started -or (Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings')
{Get-Content $log -Tail 25;throw 'Boundary compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
$ini=Join-Path $stage 'run.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1') | Set-Content $ini -Encoding ASCII
$started=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(180000)){if($p.Path -eq $terminal){$p.Kill()};throw 'Boundary worker timeout'}
$report=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
if(!(Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh boundary report missing'}
$text=Get-Content $report -Raw
$text | Set-Content (Join-Path $stage 'results.txt') -Encoding UTF8
Write-Output $text
if($text -notmatch 'failed=0'){throw 'Boundary checks failed'}
Write-Output "STAGE=$stage"
