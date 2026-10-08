param(
 [ValidateSet('Compile','Pilot','Run')][string]$Mode='Pilot',
 [ValidateSet('all','orb','macross','sol','entrylab')][string]$Family='all',
 [int]$Limit=0,
 [int[]]$Weeks=@(),
 [int]$TimeoutSeconds=21600
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'reports\strategy_audit_20261008'
$manifest=Get-Content (Join-Path $out 'manifest.private.json') -Raw | ConvertFrom-Json
$worker=Join-Path $root '.tmp\orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if($Mode -eq 'Compile'){
 foreach($entry in $manifest.compiles){
  if($Family-ne 'all'-and $entry.family-ne $Family){continue}
  $log=Join-Path $out ($entry.script+'.compile.log')
  $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$entry.source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(240000)){throw ('Compile timeout '+$entry.family)}
  $text=Get-Content $log -Raw
  if($text-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 30;throw ('Compile failed '+$entry.family)}
  Write-Host ($entry.family+' 0 errors, 0 warnings')
 }
 exit
}
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path-eq $terminal}){throw 'Research worker busy; user terminal will not be touched'}
New-Item -ItemType Directory -Force (Join-Path $worker 'MQL5\Presets'),(Join-Path $out 'results') | Out-Null
$selected=@($manifest.jobs | Where-Object {$Family-eq 'all'-or $_.family-eq $Family})
if($Mode-eq 'Pilot'){$selected=@($selected | Group-Object family | ForEach-Object {$_.Group[0]})}
if($Limit-gt 0){$selected=@($selected | Select-Object -First $Limit)}
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$progressPath=Join-Path $out 'progress.json'
$completed=0;$errors=0
foreach($job in $selected){
 $entry=$manifest.compiles | Where-Object family -eq $job.family
 $binary=[IO.Path]::ChangeExtension($entry.source,'.ex5')
 if(!(Test-Path $binary)){throw ('Compile required: '+$job.family)}
 if((Get-Item $binary).LastWriteTime-lt (Get-Item $entry.source).LastWriteTime){throw ('Research wrapper changed: compile '+$job.family+' before running')}
 $log=Join-Path $out ($entry.script+'.compile.log')
 if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Clean compile required'}
 $requested=if($Weeks.Count-gt 0){$Weeks}else{@($job.windows)}
 $dest=Join-Path $out ('results\'+$job.id+'.csv')
 $pending=@($requested)
 if(Test-Path $dest){
  $existing=@(Import-Csv -LiteralPath $dest)
  $ready=@($existing | Where-Object {$_.status -in @('AUDITED','AUDITED_OPEN') -and $_.metrics_saved-eq '1'} | ForEach-Object {[int]$_.weeks})
  $pending=@($requested | Where-Object {$_-notin $ready})
 }
 if($pending.Count-eq 0){$completed++;continue}
 # Verify that the saved strategy is still the captured record, not a same-name update.
 if($job.origin-notmatch '^(builtin|image):'){
  $record=Join-Path $common $job.origin
  if(!(Test-Path $record)){Write-Warning ('Strategy missing '+$job.name);$errors++;continue}
  $text=[IO.File]::ReadAllText($record)
  if($job.family-eq 'sol'){$text=$text.Replace("`r`n","`n")}
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','').ToLower()}finally{$sha.Dispose()}
  if($hash-ne $job.nativeSourceHash){throw ('Strategy changed after inventory: '+$job.name)}
 }
 Copy-Item -LiteralPath $binary -Destination (Join-Path $worker ('MQL5\Scripts\'+$entry.script+'.ex5')) -Force
 $lines=@($job.inputs.PSObject.Properties | ForEach-Object {
  $v=if($_.Value-is [bool]){if($_.Value){'true'}else{'false'}}else{[string]$_.Value}
  $_.Name+'='+$v
 })
 $lines+=@("CampaignOrigin=$($job.origin)","CampaignId=$($job.id)","CampaignProfileSignature=$($job.profileSignature)","CampaignWeeks=$($pending-join ',')")
 $preset='strategy-campaign.set'
 $lines | Set-Content -LiteralPath (Join-Path $worker ('MQL5\Presets\'+$preset)) -Encoding Unicode
 $ini=Join-Path $out 'worker.ini'
 @('[Charts]','MaxBars=3000000','[Experts]','Enabled=0','AllowLiveTrading=0','AllowDllImport=0','[StartUp]',
  ('Script='+$entry.script),('ScriptParameters='+$preset),('Symbol='+$job.symbol),('Period='+$job.period),'ShutdownTerminal=1') |
  Set-Content -LiteralPath $ini -Encoding ASCII
 $begin=Get-Date
 @{state='running';pid=$PID;started=$begin.ToString('o');sourceHash=$manifest.sourceHash;current=$job.id;name=$job.name;family=$job.family;
  requestedWindows=$pending;strategies=$manifest.strategies;completedThisRun=$completed;errorsThisRun=$errors} |
  ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $progressPath -Encoding UTF8
 Write-Host ('START '+$job.family+' '+$job.symbol+' '+$job.name+' ['+($pending-join ',')+']')
 $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 $timeOut=-not $p.WaitForExit($TimeoutSeconds*1000)
 if($timeOut){
  # Only the exact process created by this campaign may be stopped.
  Write-Warning ('Audit worker timeout pid='+$p.Id)
  Stop-Process -Id $p.Id -Force;$null=$p.WaitForExit(30000)
 }
 $native=Join-Path $worker ('MQL5\Files\Campaign_'+$job.id+'.csv')
 if(!(Test-Path $native)-or (Get-Item $native).LastWriteTime-lt $begin){
  Write-Warning ('No fresh output '+$job.name);$errors++;continue
 }
 $rows=@(Import-Csv -LiteralPath $native)
 if(@($rows | Where-Object {$_.catalog_id-ne $job.id-or $_.symbol-ne $job.symbol}).Count-gt 0){throw 'Result identity mismatch'}
 $prior=if(Test-Path $dest){@(Import-Csv -LiteralPath $dest | Where-Object {[int]$_.weeks-notin @($rows | ForEach-Object {[int]$_.weeks})})}else{@()}
 @($prior)+@($rows) | Export-Csv -LiteralPath $dest -NoTypeInformation -Encoding UTF8
 $completed++
 $bad=@($rows | Where-Object {$_.status-notin @('AUDITED','AUDITED_OPEN')})
 if($bad.Count-gt 0){$errors++;Write-Warning (($bad | ForEach-Object {$_.weeks+'W '+$_.status})-join '; ')}
 else{Write-Host ('SAVED '+$job.name+' windows='+$rows.Count)}
}
$all=@(Get-ChildItem (Join-Path $out 'results') -Filter '*.csv' | ForEach-Object {Import-Csv -LiteralPath $_.FullName})
$all | Export-Csv -LiteralPath (Join-Path $out 'summary.csv') -NoTypeInformation -Encoding UTF8
@{state='finished';finished=(Get-Date).ToString('o');sourceHash=$manifest.sourceHash;strategies=$manifest.strategies;
 resultRows=$all.Count;validWindows=@($all | Where-Object status -in @('AUDITED','AUDITED_OPEN')).Count;
 validFiveYear=@($all | Where-Object {[int]$_.weeks-eq 260-and $_.status-in @('AUDITED','AUDITED_OPEN')}).Count;
 completedThisRun=$completed;errorsThisRun=$errors} | ConvertTo-Json | Set-Content -LiteralPath $progressPath -Encoding UTF8
Get-Content $progressPath
