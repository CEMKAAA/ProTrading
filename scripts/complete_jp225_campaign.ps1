param([switch]$CollectOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'reports/strategy_audit_20261008'
$report=Join-Path $out 'jp225-remap'
$worker=Join-Path $root '.tmp/sol_selection_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(!$CollectOnly-and (Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object Path -eq $terminal)){throw 'Dedicated test worker busy; campaign worker will not be touched'}
if(!$CollectOnly){
& node (Join-Path $PSScriptRoot 'prepare_jp225_campaign_remap.mjs')
if($LASTEXITCODE-ne 0){throw 'JP225 remap preparation failed'}
}
$authorization=Get-Content (Join-Path $report 'authorization.json') -Raw|ConvertFrom-Json
$source=$authorization.script
$binary=[IO.Path]::ChangeExtension($source,'.ex5')
$log=Join-Path $report 'compile.log'
if(!$CollectOnly){
$start=Get-Date
$compiler=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$compiler.WaitForExit(180000)){throw 'Remap compile timeout; no terminal was stopped'}
if(!(Test-Path $log)-or (Get-Item $log).LastWriteTime-lt $start.AddSeconds(-2)-or (Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Remap wrapper requires 0 errors, 0 warnings'}
Write-Output 'COMPILE: 0 errors, 0 warnings'
}elseif((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Clean remap compile missing'}
$manifest=Get-Content (Join-Path $out 'manifest.private.json') -Raw|ConvertFrom-Json
$jobs=@($manifest.jobs|Where-Object id -in @($authorization.jobs.id))
New-Item -ItemType Directory -Force (Join-Path $worker 'MQL5/Scripts'),(Join-Path $worker 'MQL5/Presets')|Out-Null
if(!$CollectOnly){Copy-Item -LiteralPath $binary -Destination (Join-Path $worker 'MQL5/Scripts/StrategyWindows_sol_jp225_remap.ex5') -Force}
foreach($job in $jobs){
 if($job.symbol-ne 'JP225m'-or $job.sourceSymbol-ne 'JP225s'){throw 'Unauthorized symbol mapping'}
 $prior=@();$dest=Join-Path $out ('results/'+$job.id+'.csv')
 if(Test-Path $dest){$prior=@(Import-Csv -LiteralPath $dest)}
 $ready=@($prior|Where-Object {$_.status-in @('AUDITED','AUDITED_OPEN')-and $_.metrics_saved-eq '1'}|ForEach-Object {[int]$_.weeks})
 $pending=@($job.windows|Where-Object {$_-notin $ready})
 if($pending.Count-eq 0){Write-Output ('ALREADY SAVED '+$job.name);continue}
 if(!$CollectOnly){
 $preset=@($job.inputs.PSObject.Properties|ForEach-Object {
  $value=if($_.Value-is [bool]){if($_.Value){'true'}else{'false'}}else{[string]$_.Value}
  $_.Name+'='+$value
 })
 $preset+=@("CampaignOrigin=$($job.origin)","CampaignId=$($job.id)","CampaignProfileSignature=$($job.profileSignature)","CampaignWeeks=$($pending-join ',')")
 $preset|Set-Content -LiteralPath (Join-Path $worker 'MQL5/Presets/jp225-remap.set') -Encoding Unicode
 $ini=Join-Path $report 'worker.ini'
 @('[Charts]','MaxBars=3000000','[Experts]','Enabled=0','AllowLiveTrading=0','AllowDllImport=0','[StartUp]',
 'Script=StrategyWindows_sol_jp225_remap','ScriptParameters=jp225-remap.set','Symbol=JP225m',('Period='+$job.period),'ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
 @{state='running';id=$job.id;name=$job.name;sourceSymbol='JP225s';auditSymbol='JP225m';started=(Get-Date -Format o)}|ConvertTo-Json|Set-Content (Join-Path $report 'progress.json') -Encoding UTF8
 Write-Output ('START '+$job.name+' JP225m ['+($pending-join ',')+']')
 $start=Get-Date
 $process=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$process.WaitForExit(1800000)){throw 'Dedicated JP225 audit timeout; main campaign was not stopped'}
 }else{
  $current=Get-Content (Join-Path $report 'progress.json') -Raw|ConvertFrom-Json
  if($current.id-ne $job.id){throw 'Collect-only requires the exact recorded job'}
  $start=[DateTime]::Parse($current.started)
 }
 $native=Join-Path $worker ('MQL5/Files/Campaign_'+$job.id+'.csv')
 # MT5 LiveUpdate can hand the job to a new PID; do not mistake launcher exit for audit completion.
 $deadline=(Get-Date).AddMinutes(30)
 do{
  $running=Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object Path -eq $terminal
  $available=(Test-Path $native)-and (Get-Item $native).LastWriteTime-ge $start.AddSeconds(-2)-and (Get-Item $native).Length-gt 200
  if(!$running-and $available){break}
  if((Get-Date)-ge $deadline){throw 'Native result collection timeout; no terminal was stopped'}
  Start-Sleep -Seconds 1
 }while($true)
 if(!(Test-Path $native)-or (Get-Item $native).LastWriteTime-lt $start.AddSeconds(-2)){throw ('No fresh native JP225 results: '+$job.name)}
 $rows=@(Import-Csv -LiteralPath $native)
 if($rows.Count-ne $pending.Count-or @($rows|Where-Object {$_.catalog_id-ne $job.id-or $_.symbol-ne 'JP225m'-or $_.name-ne $job.name-or $_.order_attempts-ne '0'}).Count-gt 0){throw 'Native identity/count/safety mismatch'}
 foreach($row in $rows){$row.detail='source_symbol=JP225s; audit_symbol=JP225m; explicit_user_approval_20261009; '+$row.detail}
 $remaining=@($prior|Where-Object {[int]$_.weeks-notin @($rows|ForEach-Object {[int]$_.weeks})})
 @($remaining)+@($rows)|Export-Csv -LiteralPath ($dest+'.next') -NoTypeInformation -Encoding UTF8
 Move-Item -LiteralPath ($dest+'.next') -Destination $dest -Force
 $rows|Select-Object name,weeks,wins,losses,open,net_r,status,metrics_saved|Format-Table -AutoSize
}
& node (Join-Path $PSScriptRoot 'report_strategy_window_campaign.mjs') --verify-common --write
if($LASTEXITCODE-ne 0){throw 'Campaign metric integrity verification failed'}
$mainProgress=Get-Content (Join-Path $out 'progress.json') -Raw|ConvertFrom-Json
if($mainProgress.state-eq 'finished'){
 $all=@(Get-ChildItem (Join-Path $out 'results') -Filter '*.csv'|ForEach-Object {Import-Csv -LiteralPath $_.FullName})
 $all|Export-Csv -LiteralPath (Join-Path $out 'summary.csv.next') -NoTypeInformation -Encoding UTF8
 Move-Item -LiteralPath (Join-Path $out 'summary.csv.next') -Destination (Join-Path $out 'summary.csv') -Force
 $mainProgress.resultRows=$all.Count
 $mainProgress.validWindows=@($all|Where-Object status -in @('AUDITED','AUDITED_OPEN')).Count
 $mainProgress.validFiveYear=@($all|Where-Object {[int]$_.weeks-eq 260-and $_.status-in @('AUDITED','AUDITED_OPEN')}).Count
 $mainProgress|Add-Member -NotePropertyName completedTotal -NotePropertyValue @($all.catalog_id|Select-Object -Unique).Count -Force
 $mainProgress|Add-Member -NotePropertyName jp225RemapFinished -NotePropertyValue (Get-Date -Format o) -Force
 $mainProgress|ConvertTo-Json -Depth 8|Set-Content (Join-Path $out 'progress.json.next') -Encoding UTF8
 Move-Item -LiteralPath (Join-Path $out 'progress.json.next') -Destination (Join-Path $out 'progress.json') -Force
}
@{state='finished';finished=(Get-Date -Format o);sourceSymbol='JP225s';auditSymbol='JP225m';jobIds=@($jobs.id);compile='0 errors, 0 warnings'}|ConvertTo-Json|Set-Content (Join-Path $report 'progress.json') -Encoding UTF8
