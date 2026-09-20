param([Parameter(Mandatory=$true)][string]$CampaignPath)
$ErrorActionPreference='Stop'
$matrix=Get-Content (Join-Path $CampaignPath matrix.json) -Raw|ConvertFrom-Json
$names=@('OFF','PROFILE','ACTIVITY','PROFILE_ACTIVITY','DELTA_010','PROFILE_DELTA','ACTIVITY_DELTA','STRICT_EITHER','STRICT_BREAKOUT','STRICT_REJECTION','DELTA_005','DELTA_020')
$out=foreach($job in $matrix){
 $files=@(Get-ChildItem $CampaignPath -Filter "OF20_*_$($job.slot)_$($job.variant).jsonl")
 if(!$files.Count){continue}
 $events=@(Get-Content $files[0].FullName|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json})
 $summary=@($events|Where-Object kind -eq summary)
 $errors=@($events|Where-Object kind -eq error)
 $complete=$summary.Count -eq 1 -and $summary[0].complete -eq $true -and $errors.Count -eq 0
 $trades=@($events|Where-Object {$_.kind -eq 'trade' -and $_.valid -and $_.outcome -ne 'open'})
 $cum=0.0;$peak=0.0;$dd=0.0;$min=0.0
 foreach($g in ($trades|Group-Object exit|Sort-Object {[long]$_.Name})){
  $cum+=($g.Group|Measure-Object r -Sum).Sum;$peak=[math]::Max($peak,$cum);$dd=[math]::Max($dd,$peak-$cum);$min=[math]::Min($min,$cum)
 }
 $wins=@($trades|Where-Object r -gt 0).Count
 [pscustomobject]@{slot=$job.slot;strategy=$job.name;symbol=$job.symbol;variant=$names[$job.variant];complete=$complete;closed=$trades.Count;wins=$wins;wr=$(if($trades.Count){100.0*$wins/$trades.Count}else{$null});netR=$(if($complete){$cum}else{$null});closedTradeMaxDD=$(if($complete){$dd}else{$null});minCum=$(if($complete){$min}else{$null});error=($errors.reason -join ';');data=$(if($summary.Count){$summary[0].data}else{$null});ofIncomplete=$(if($summary.Count){$summary[0].of_incomplete}else{$null})}
}
@($out)|ConvertTo-Json -Depth 5|Set-Content (Join-Path $CampaignPath summary.json)
@($out)|Export-Csv (Join-Path $CampaignPath summary.csv) -NoTypeInformation
$out|Format-Table strategy,variant,complete,closed,netR,closedTradeMaxDD,error
