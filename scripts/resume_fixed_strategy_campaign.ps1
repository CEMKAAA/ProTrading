param([switch]$ValidateOnly,[ValidateRange(5,300)][int]$PollSeconds=15)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$old=Join-Path $root 'reports\strategy_audit_20261009_rolling'
$fixed=Join-Path $root 'reports\verification_build\audit_failures'
$record=Get-Content -LiteralPath (Join-Path $old 'campaign-process.json') -Raw|ConvertFrom-Json
$status=Join-Path $fixed 'repair-queue.json'
function VerifyEvidence {
 $proof=Get-Content -LiteralPath (Join-Path $fixed 'parity_verified.json') -Raw|ConvertFrom-Json
 $regression=Get-Content -LiteralPath (Join-Path $fixed 'failure-regression.json') -Raw|ConvertFrom-Json
 $manifest=Get-Content -LiteralPath (Join-Path $fixed 'manifest.private.json') -Raw|ConvertFrom-Json
 $original=Get-Content -LiteralPath (Join-Path $old 'manifest.private.json') -Raw|ConvertFrom-Json
 if(!$proof.passed-or !$regression.passed-or $regression.windows-ne 33-or $proof.windows-ne 33){throw 'Verification required'}
 if(@('orb','macross','entrylab','sol'|Where-Object {$_-notin $proof.families}).Count){throw 'Four-family verification required'}
 if($proof.sourceHash-ne $manifest.sourceHash-or $regression.sourceHash-ne $manifest.sourceHash){throw 'Patch evidence/source mismatch'}
 if($manifest.jobs.Count-ne 188-or
   ($manifest.jobs|ConvertTo-Json -Depth 50 -Compress)-cne ($original.jobs|ConvertTo-Json -Depth 50 -Compress)){
  throw 'Original strategy inventory/settings changed'
 }
 & node (Join-Path $PSScriptRoot 'verify_strategy_campaign_snapshot.mjs') $fixed
 if($LASTEXITCODE-ne 0){throw 'Canonical source/native evidence changed'}
 return $manifest
}
$manifest=VerifyEvidence
if($ValidateOnly){Write-Output ('READY: 188 unchanged strategies; 33 verified windows; '+$manifest.sourceHash);return}
if(Test-Path -LiteralPath (Join-Path $fixed 'repair-cancel.request.json')){Write-Output 'CANCELLED_BY_USER';return}
$mutex=New-Object Threading.Mutex($false,'Local\ProTradingSystem-FixedMegaCampaign')
$acquired=$mutex.WaitOne(0)
if(!$acquired){$mutex.Dispose();throw 'Corrected campaign handoff already active'}
function State([string]$value,[string]$detail=''){
 $progress=Get-Content -LiteralPath (Join-Path $old 'progress.json') -Raw|ConvertFrom-Json
 $body=@{state=$value;pid=$PID;originalPid=$record.pid;originalStartedUtc=$record.startedUtc;
  originalCompleted=$progress.completedThisRun;originalTotal=188;originalErrors=$progress.errorsThisRun;
  sourceHash=$manifest.sourceHash;detail=$detail;updatedUtc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json
 [IO.File]::WriteAllText($status+'.pending',$body,(New-Object Text.UTF8Encoding($false)))
 Move-Item -LiteralPath ($status+'.pending') -Destination $status -Force
}
try{
 # Never stop or compete with the original worker. A cancelled original run
 # is not permission to start another campaign.
 while($process=Get-Process -Id $record.pid -ErrorAction SilentlyContinue){
  if([math]::Abs(($process.StartTime.ToUniversalTime()-[datetime]::Parse($record.startedUtc).ToUniversalTime()).TotalSeconds)-gt 2){
   State 'ORIGINAL_PROCESS_CHANGED_NOT_RESTARTED';return
  }
  State 'WAITING_FOR_ORIGINAL_CAMPAIGN'
  Start-Sleep -Seconds $PollSeconds
 }
 $progress=Get-Content -LiteralPath (Join-Path $old 'progress.json') -Raw|ConvertFrom-Json
 if($progress.state-ne 'finished'-or $progress.completedThisRun-ne 188){State 'ORIGINAL_INTERRUPTED_NOT_RESTARTED';return}
 $manifest=VerifyEvidence
 $epoch=Get-Content -LiteralPath (Join-Path $old 'campaign-epoch.json') -Raw|ConvertFrom-Json
 $epochPath=Join-Path $fixed 'campaign-epoch.json'
 $body=@{asOf=$epoch.asOf;sourceHash=$manifest.sourceHash;createdUtc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json
 [IO.File]::WriteAllText($epochPath+'.pending',$body,(New-Object Text.UTF8Encoding($false)))
 Move-Item -LiteralPath ($epochPath+'.pending') -Destination $epochPath -Force
 State 'REPAIR_RUNNING'
 & (Join-Path $PSScriptRoot 'complete_corrected_strategy_campaign.ps1') -ReportDir 'reports/verification_build/audit_failures' -HistoryMaxBars 5000000
 State 'REPAIR_FINISHED'
}catch{State 'REPAIR_FAILED' $_.Exception.Message;throw}
finally{$mutex.ReleaseMutex();$mutex.Dispose()}
