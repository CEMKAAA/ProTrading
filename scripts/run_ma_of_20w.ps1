param([switch]$Execute,[int]$Limit=192)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tag=(Get-Date -Format yyyyMMdd_HHmmss)+'_'+[guid]::NewGuid().ToString('N').Substring(0,6)
$run=Join-Path $root "logs/ma_of_20w/$tag"
$src=Join-Path $run 'IndicatorCodeExamples/macrossover_orb';$test=Join-Path $run 'tests/mql5'
New-Item -ItemType Directory -Force $src,$test|Out-Null
Get-ChildItem "$root/IndicatorCodeExamples/macrossover_orb" -File|Where-Object Extension -in '.mq5','.mqh'|Copy-Item -Destination $src
Copy-Item "$root/logs/ma_legacy_parity_20260919/presets" "$run/presets" -Recurse
function WriteUtf($p,$s){[IO.File]::WriteAllText($p,$s,[Text.UTF8Encoding]::new($false))}
$core=Get-Content "$src/MaCrossOrderFlowCore.mqh" -Raw
$core=$core.Replace('s.activity<c.minActivity||direction*s.delta<c.minDelta','((campaignMask&2)!=0&&s.activity<c.minActivity)||((campaignMask&4)!=0&&direction*s.delta<c.minDelta)')
$core=$core.Replace('return c.mode==MC_OF_BREAKOUT?breakout:', 'return (campaignMask&1)==0?true:(c.mode==MC_OF_BREAKOUT?breakout:')
$core=$core.Replace('breakout||rejection);','breakout||rejection));')
WriteUtf "$src/MaCrossOrderFlowCore.mqh" $core
$adapter=Get-Content "$src/MaCrossOrderFlow.mqh" -Raw
$adapter=$adapter.Replace('+McOfConfigText(g_mcOf);','+McOfConfigText(g_mcOf)+"|MASK="+(string)campaignMask;')
$adapter=$adapter.Replace('int McOfPrepare(', 'int McOfPrepareAsync(')
$pos=$adapter.IndexOf('int McOfPrepareAsync(')
$adapter=$adapter.Insert($pos,(Get-Content "$root/scripts/orderflow_campaign/ResearchPrepare.mqh" -Raw)+"`n")
WriteUtf "$src/MaCrossOrderFlow.mqh" $adapter
$ea=Get-Content "$src/MaCrossOverOrbEA.mq5" -Raw
$needle='      g_histTotal++;'
if(([regex]::Matches($ea,[regex]::Escape($needle))).Count -ne 1){throw 'Trade hook anchor changed'}
$ea=$ea.Replace($needle,'      ProbeTrade(entryT,execDir,sim);'+"`n"+$needle)
WriteUtf "$src/MaCrossOverOrbEA.mq5" $ea
$probe=Get-Content "$root/tests/mql5/MaLegacyParityProbe.mq5" -Raw
$probe='int campaignMask=7;string campaignCache="OF20_CACHE_'+$tag+'";'+"`n"+$probe
$probe=$probe.Replace('probeFile=FileOpen("MaLegacyParity.jsonl",','int task=FileOpen("OF20_TASK_'+$tag+'.csv",FILE_READ|FILE_CSV|FILE_ANSI,'+[char]39+','+[char]39+'); if(task==INVALID_HANDLE)return; int selected=(int)StringToInteger(FileReadString(task));int variant=(int)StringToInteger(FileReadString(task));string out=FileReadString(task);FileClose(task); probeFile=FileOpen(out,')
$probe=$probe.Replace('from=until-14*86400','from=until-140*86400').Replace('slot=0;slot<16','slot=selected;slot<selected+1')
$probe=$probe.Replace('MaLegacyParity\\','OF20_PRESETS_'+$tag+'\\')
$probe=$probe.Replace('#ifdef MA_MIGRATION_CANDIDATE','#ifdef __MQL5__')
$probe=$probe.Replace('g_rtHistoricalWeeks=2','g_rtHistoricalWeeks=20').Replace('g_histRunDays=14','g_histRunDays=140')
$probe=$probe.Replace('EnsureOrbAuditHistoryCoverage(14,','EnsureOrbAuditHistoryCoverage(140,').Replace('BuildHistoricalNasEventCache(14,','BuildHistoricalNasEventCache(140,')
$probe=$probe.Replace('g_runtimeMagic=91919001;', 'McOfInit();campaignMask=variant<8?variant:(variant<10?7:4);g_mcOf.mode=variant==0?0:(variant==8?1:(variant==9?2:3));g_mcOf.minDelta=variant==10?.05:(variant==11?.20:.10);McOfReset();g_runtimeMagic=91919001;')
$probe=$probe.Replace('for(int i=0;i<count;i++)ProcessMaHistoricalPrepEvent(i);','for(int i=0;i<count&&!g_mcOfDataIncomplete&&!IsStopped();i++){g_mcOfAuditContext=true;ProcessMaHistoricalPrepEvent(i);g_mcOfAuditContext=false;if(i%100==0){Print("PREP ",i,"/",count);}}')
$probe=$probe.Replace('for(int i=0;i<count;i++){if(IsStopped())break;ProcessHistoricalCalcDay(i);}', 'for(int i=0;i<count&&!g_mcOfDataIncomplete;i++){if(IsStopped())break;g_mcOfAuditContext=true;ProcessHistoricalCalcDay(i);g_mcOfAuditContext=false;}')
$probe=$probe.Replace('+",\"independent\":', '+",\"complete\":"+(!g_mcOfDataIncomplete&&!IsStopped()&&g_histInvalid==0?"true":"false")+",\"of_incomplete\":"+(g_mcOfDataIncomplete?"true":"false")+",\"variant\":"+(string)variant+",\"independent\":')
$probe=$probe.Replace('for(int retry=0;retry<30;retry++){if(EnsureOrbAuditHistoryCoverage(140,detail,hard))break;Sleep(500);}', 'bool coverage=false;for(int retry=0;retry<60;retry++){if(EnsureOrbAuditHistoryCoverage(140,detail,hard)){coverage=true;break;}Sleep(500);}if(!coverage){FileWriteString(probeFile,"{\"kind\":\"error\",\"reason\":\"history_coverage\",\"slot\":"+(string)slot+"}\n");FileFlush(probeFile);continue;}')
$probe=$probe.Replace('FileClose(probeFile);','McOfRelease();FileClose(probeFile);')
WriteUtf "$test/MaOf20w.mq5" $probe
$matrix=foreach($slot in 0..15){$v=[IO.File]::ReadAllLines("$run/presets/$slot.preset");foreach($variant in 0..11){[pscustomobject]@{slot=$slot;variant=$variant;symbol=$v[3];name=$v[7];days=140}}}
$matrix|ConvertTo-Json|Set-Content "$run/matrix.json"
Get-ChildItem $src,$test,"$run/presets" -Recurse -File|Get-FileHash|Select-Object Path,Hash|ConvertTo-Json|Set-Content "$run/source_manifest.json"
Write-Output "CAMPAIGN=$run"
$f="$test/MaOf20w.mq5";$log="$f.log"
$p=Start-Process C:/MT5/DEMO/MetaEditor64.exe -ArgumentList ('/compile:"'+$f+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 20;throw 'Compile failed'}
Get-Content $log -Tail 1
if(!$Execute){return}
$w=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal="$w/terminal64.exe"
$lock=[IO.File]::Open((Join-Path $root '.tmp/ma_of_screen.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
 if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal).Count){throw 'Worker busy'}
 Copy-Item "$run/presets" "$w/MQL5/Files/OF20_PRESETS_$tag" -Recurse
 New-Item -ItemType Directory -Force "$w/MQL5/Files/OF20_CACHE_$tag"|Out-Null
 Copy-Item ($f -replace '\.mq5$','.ex5') "$w/MQL5/Scripts/OF20_$tag.ex5"
 $done=0
 # Baselines first, then paired ablations; at least ten strategies are not hidden by one early slow symbol.
 foreach($job in ($matrix|Sort-Object variant,slot|Select-Object -First $Limit)){
  $name="OF20_${tag}_$($job.slot)_$($job.variant).jsonl"
  "$($job.slot),$($job.variant),$name"|Set-Content "$w/MQL5/Files/OF20_TASK_$tag.csv" -Encoding ASCII
  $ini=Join-Path $run 'job.ini';@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',"Script=OF20_$tag","Symbol=$($job.symbol)",'Period=M5','ShutdownTerminal=1')|Set-Content $ini
  $started=Get-Date
  @{state='running';job=$job;finished=$done;total=$matrix.Count;started=$started.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content "$run/status.json"
  $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(3600000)){throw 'Job exceeded one hour; worker left running, campaign stopped'}
  $out="$w/MQL5/Files/$name"
  if(!(Test-Path $out) -or (Get-Item $out).LastWriteTime -lt $started){throw 'Missing fresh result'}
  Copy-Item $out "$run/$name";$done++
  Write-Output "JOB $done slot=$($job.slot) variant=$($job.variant)"
 }
 @{state='finished';finished=$done;planned=$matrix.Count}|ConvertTo-Json|Set-Content "$run/status.json"
} finally {$lock.Dispose()}
