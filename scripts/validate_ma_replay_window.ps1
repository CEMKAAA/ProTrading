param([int]$BroadWeeks=52,[int]$NarrowWeeks=20,[string]$Period='M5',[switch]$OfflineHistory)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$family=Join-Path $root 'IndicatorCodeExamples/macrossover_orb'
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Worker busy'}
$stage=Join-Path $root ('.tmp/ma_replay_window_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $stage -Force|Out-Null
Copy-Item -Path ($family+'/*.mqh') -Destination $stage
Copy-Item -LiteralPath (Join-Path $family 'MaCrossOverOrbEA.mq5') -Destination $stage
# Instrument data-epoch resets without changing replay or price mathematics.
$path=Join-Path $stage 'OrbReplayMemoEpoch.mqh'
$text=[IO.File]::ReadAllText($path).Replace('string OrbReplayDataEpoch()','string ProbeOriginalEpoch()')
$text=$text.Replace('#endif',@'
long g_probeEpochChanges=0;
string OrbReplayDataEpoch()
{
   static string previous="";string epoch=ProbeOriginalEpoch();
   if(epoch!=previous){g_probeEpochChanges++;Print("PROBE_EPOCH ",epoch);previous=epoch;}
   return epoch;
}
#endif
'@)
[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
$path=Join-Path $stage 'OrbStrategyUserMetrics.mqh'
$text=[regex]::Replace([IO.File]::ReadAllText($path),'(?s)void OrbUserAuditCompleted\(\)\s*\{.*?\r?\n\}\r?\n#endif',"void OrbUserAuditCompleted(){}`r`n#endif")
[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
$name='MaAuditReplayWindowProbe_'+[Guid]::NewGuid().ToString('N').Substring(0,10)
$source=Join-Path $stage ($name+'.mq5')
$text=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/MaAuditReplayWindowProbe.mq5')).Replace('MaAuditReplayWindowProbe.txt',$name+'.txt').Replace('Run(52)',('Run('+$BroadWeeks+')')).Replace('Run(20)',('Run('+$NarrowWeeks+')'))
if($OfflineHistory){$text="#define MA_OFFLINE_HISTORY_FIXTURE`r`n"+$text}
[IO.File]::WriteAllText($source,$text,(New-Object Text.UTF8Encoding($false)))
$log=$source+'.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
if([IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw 'Compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
$ini=Join-Path $stage 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=USDJPYm',('Period='+$Period),'ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$started=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(1000000)){throw 'Probe timeout'}
$report=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
if(!(Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh report missing'}
$result=Get-Content $report -Raw
$result|Set-Content (Join-Path $stage 'result.txt')
Write-Output $result
if($result -notmatch 'broad=true warm=true cold=true same=true' -or $result -notmatch 'ui_cleanup=true' -or $result -notmatch 'visual_same=true' -or $result -notmatch ' data=0 ' -or $result -notmatch ' epoch_changes=0 '){throw 'Replay-window parity/cleanup/visual/coverage failed'}
Write-Output "STAGE=$stage"
