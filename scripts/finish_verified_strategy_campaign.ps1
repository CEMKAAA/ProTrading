param([ValidateRange(5,300)][int]$PollSeconds=15)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$out=Join-Path $root 'reports\verification_build\audit_failures'
$record=Get-Content -LiteralPath (Join-Path $out 'campaign-process.json') -Raw|ConvertFrom-Json
$status=Join-Path $out 'finish-state.json'
function State([string]$value,[string]$detail=''){
 $body=@{state=$value;pid=$PID;campaignPid=$record.pid;sourceHash=$record.sourceHash;
  updatedUtc=[DateTimeOffset]::UtcNow.ToString('o');detail=$detail}|ConvertTo-Json
 [IO.File]::WriteAllText($status+'.pending',$body,(New-Object Text.UTF8Encoding($false)))
 Move-Item -LiteralPath ($status+'.pending') -Destination $status -Force
}
try{
 while($process=Get-Process -Id $record.pid -ErrorAction SilentlyContinue){
  if([math]::Abs(($process.StartTime.ToUniversalTime()-[datetime]::Parse($record.startedUtc).ToUniversalTime()).TotalSeconds)-gt 2){
   throw 'Campaign process identity changed'
  }
  State 'WAITING_FOR_NATIVE_CAMPAIGN'
  Start-Sleep -Seconds $PollSeconds
 }
 $progress=Get-Content -LiteralPath (Join-Path $out 'progress.json') -Raw|ConvertFrom-Json
 if($progress.state-eq 'stopped_by_user'-or (Test-Path -LiteralPath (Join-Path $out 'campaign-stop.request.json'))){State 'CANCELLED_BY_USER';return}
 $epoch=Get-Content -LiteralPath (Join-Path $out 'campaign-epoch.json') -Raw|ConvertFrom-Json
 # Only unresolved windows are retried. Verified native results remain intact.
 for($attempt=1;$attempt-le 2;$attempt++){
  & node (Join-Path $PSScriptRoot 'targeted_strategy_campaign.mjs') plan
  if($LASTEXITCODE-ne 0){throw 'Current source or inventory verification failed'}
  $plan=Get-Content -LiteralPath (Join-Path $out 'targeted-plan.json') -Raw|ConvertFrom-Json
  $pending=@($plan.entries|Where-Object {$_.pairedWeeks.Count-gt 0-or $_.equivalenceWeeks.Count-gt 0-or $_.publishWeeks.Count-gt 0})
  if(!$pending.Count){break}
  State 'REPAIRING_UNRESOLVED_WINDOWS' ('Pass '+$attempt+'; strategies='+$pending.Count)
  foreach($job in $pending){
   $csv=Join-Path $out ('results\'+$job.id+'.csv')
   if($job.publishWeeks.Count-gt 0){& (Join-Path $PSScriptRoot 'write_verified_strategy_windows.ps1') -Csv $csv -Family $job.family}
   $weeks=@(@($job.pairedWeeks)+@($job.equivalenceWeeks)|Sort-Object -Unique)
   if($weeks.Count-gt 0){
    & (Join-Path $PSScriptRoot 'run_strategy_window_campaign.ps1') -Mode Run -ReportDir 'reports/verification_build/audit_failures' `
     -StrategyIds @($job.id) -Weeks $weeks -AsOf $epoch.asOf -PublishMetrics -HistoryMaxBars 5000000 -TimeoutSeconds 1800
   }
  }
 }
 & node (Join-Path $PSScriptRoot 'targeted_strategy_campaign.mjs') summary
 if($LASTEXITCODE-ne 0){throw 'Final report failed'}
 $proof=Get-Content -LiteralPath (Join-Path $out 'targeted-verification.json') -Raw|ConvertFrom-Json
 if(!$proof.completed){State 'INCOMPLETE_VERIFICATION' 'See targeted-verification.json; no verified baseline claimed';return}
 & node (Join-Path $PSScriptRoot 'seal_strategy_window_campaign.mjs') $out
 if($LASTEXITCODE-ne 0){throw 'Immutable verified baseline was not sealed'}
 & (Join-Path $PSScriptRoot 'install_strategy_window_refresh.ps1') -ReportDir 'reports/verification_build/audit_failures'
 State 'VERIFIED_COMPLETE' ('Strategies='+$proof.requestedStrategies+'; available windows='+$proof.validWindows+'; confirmed unavailable='+$proof.confirmedUnavailableWindows)
}catch{State 'FAILED' $_.Exception.Message;throw}
