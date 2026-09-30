$ErrorActionPreference='Stop'
$root=(Resolve-Path .).Path
$source=Join-Path $root 'IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5'
$shadow=Join-Path $root 'IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA_AuditDiag.mq5'
$probe=Join-Path $root 'tests/mql5/MaInverseAnomalyRepro.mq5'
$log=Join-Path $root '.tmp/MaInverseAnomalyRepro.log'
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$utf8=New-Object System.Text.UTF8Encoding($false)
$body=[IO.File]::ReadAllText($source,$utf8)
$old='if(!g_auditRuntime||!InpAuditHistoricalSimulationCsv) return;'
$new='if(!g_auditRuntime) return;'
if(-not $body.Contains($old)){throw 'Audit anchor missing'}
$body=$body.Replace($old,$new)
$body=$body.Replace('"ORB15_InternalSimAudit_v2_"+AuditDateStr()+".csv"','"MaInverseAnomalyRepro.csv"')
[IO.File]::WriteAllText($shadow,$body,$utf8)
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$probe+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(180000)){throw 'Probe compile timeout'}
if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 35;throw 'Probe compile failed'}
$compiled=[IO.Path]::ChangeExtension($probe,'.ex5')
Copy-Item -LiteralPath $compiled -Destination (Join-Path $worker 'MQL5/Scripts/MaInverseAnomalyRepro.ex5') -Force
$ini=Join-Path $root '.tmp/MaInverseAnomalyRepro.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=MaInverseAnomalyRepro','Symbol=EURUSDm','Period=M1','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(180000)){throw 'Probe terminal timeout'}
$result=Join-Path $worker 'MQL5/Files/MaInverseAnomalyRepro.txt'
if(-not (Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $start.AddSeconds(-2)){throw 'Probe report missing'}
Get-Content $result
$csv=Join-Path $worker 'MQL5/Files/MaInverseAnomalyRepro.csv'
if(Test-Path $csv){Get-Content $csv -Tail 16}
Remove-Item -LiteralPath $shadow -Force
