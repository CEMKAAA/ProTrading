param([Parameter(Mandatory=$true)][string]$CampaignPath)
$ErrorActionPreference='Stop'
$summary=Join-Path $PSScriptRoot 'summarize_ma_of_20w.ps1'
$last=-1;$deadline=(Get-Date).AddHours(12)
while((Get-Date) -lt $deadline){
 try {
  $s=Get-Content (Join-Path $CampaignPath status.json) -Raw|ConvertFrom-Json
  if($s.finished -ne $last){& $summary -CampaignPath $CampaignPath|Out-Null;$last=$s.finished}
  if($s.state -eq 'finished'){
   & $summary -CampaignPath $CampaignPath|Out-Null
   $rows=@(Get-Content (Join-Path $CampaignPath summary.json) -Raw|ConvertFrom-Json)
   $complete=@($rows|ForEach-Object {$_}|Where-Object {$_.complete -eq $true}).Count
   @("# Campaign completed","Scheduled: $($s.planned)","Executed: $($s.finished)","Complete-data results: $complete","Incomplete jobs are excluded from performance rankings.","Full lifecycle results: summary.csv and summary.json.","No settings promoted to production. Multiple-testing and independent-forward validation still required.")|Set-Content (Join-Path $CampaignPath FINISHED.md)
   exit 0
  }
 } catch { $_.Exception.Message|Add-Content (Join-Path $CampaignPath reporter_errors.log) }
 Start-Sleep -Seconds 20
}
throw 'Reporter timed out; campaign status must be inspected, not assumed completed'
