param([switch]$StatusOnly,[switch]$InventoryOnly,[switch]$MonitorOnly,[switch]$Once,[ValidateRange(2,60)][int]$PollSeconds=5)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$script=Join-Path $PSScriptRoot 'mega_audit_campaign.mjs'
$manual=Join-Path $root 'reports\verification_build\mega_campaign'
$verified=Join-Path $root 'reports\verification_build\audit_failures'
function Read-Json([string]$path){
 try{return Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}catch{return $null}
}
function Live-Record([string]$file){
 $r=Read-Json $file
 if(!$r-or !$r.pid-or !$r.startedUtc){return $false}
 $p=Get-Process -Id $r.pid -ErrorAction SilentlyContinue
 if(!$p){return $false}
 return [math]::Abs(($p.StartTime.ToUniversalTime()-[datetime]::Parse($r.startedUtc).ToUniversalTime()).TotalSeconds)-le 2
}
function Active-Campaign {
 foreach($dir in @($manual,$verified,(Join-Path $root 'reports\strategy_audit_20261009_rolling'))){
  foreach($file in @('campaign-process.json','finish-process.json')){
   if(Live-Record (Join-Path $dir $file)){return $dir}
  }
 }
 return $null
}
if($InventoryOnly){
 & node $script inventory --report-dir $manual --verified-dir $verified
 exit $LASTEXITCODE
}
$out=Active-Campaign
if(!$out){
 if($StatusOnly-or $MonitorOnly-or $Once){
  $out=if(Test-Path -LiteralPath (Join-Path $manual 'campaign-epoch.json')){$manual}else{$verified}
 }else{
  New-Item -ItemType Directory -Path $manual -Force|Out-Null
  $worker=Join-Path $PSScriptRoot 'run_mega_audit.ps1'
  $p=Start-Process powershell.exe -WindowStyle Hidden -PassThru -WorkingDirectory $root `
   -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'"') `
   -RedirectStandardOutput (Join-Path $manual 'campaign.stdout.log') -RedirectStandardError (Join-Path $manual 'campaign.stderr.log')
  $out=$manual
  # The worker owns the campaign mutex; a concurrent double-click cannot start another audit.
  for($i=0;$i-lt 20;$i++){
   if((Live-Record (Join-Path $manual 'campaign-process.json'))-or $p.HasExited){break}
   Start-Sleep -Milliseconds 250
  }
 }
}elseif(!$StatusOnly){Write-Host 'Existing campaign is running. Attaching the monitor; no audit is stopped.' -ForegroundColor Yellow}
if($StatusOnly){& node $script status --report-dir $out;exit $LASTEXITCODE}
Write-Host 'MEGA AUDIT | ORB / MaCross / EntryLab / SolAdvanced' -ForegroundColor Cyan
Write-Host ('Report: '+$out)
Write-Host 'Each NEW campaign rescans all native libraries. No fixed strategy limit.'
Write-Host 'Verified results feed EA SEARCH / WindowMetrics. Original MEGA archives are preserved.'
Write-Host 'Ctrl+C closes this monitor only. The background audit continues.'
do{
 $raw=& node $script status --report-dir $out 2>$null
 if($LASTEXITCODE-eq 0){
  $s=$raw|ConvertFrom-Json
  $fill=[math]::Min(30,[math]::Floor($s.progressPercent*30/100))
  $bar=('='*$fill)+('.'*(30-$fill))
  Write-Host ('[{0}] {1:N2}% | processed {2}/{3} strategies | full 9/9 {4}/{3} | verified {5}/{6} windows ({7:N2}%)' -f `
   $bar,$s.progressPercent,$s.processed,$s.strategies,$s.complete,$s.verifiedWindows,$s.windows,$s.verifiedPercent) -ForegroundColor Green
  Write-Host ('  partial={0} | confirmed DATA={1} | failed={2} | pending={3} | {4} | {5}' -f `
   $s.partial,$s.unavailableWindows,$s.failedWindows,$s.pendingWindows,$s.phase,$s.current)
 }else{
  $state=Read-Json (Join-Path $out 'manual-state.json')
  Write-Host ('Preparing current inventory / verified engine. '+$state.state+' '+$state.detail)
 }
 $active=Active-Campaign
 if(!$active-or $Once){break}
 if($active-ne $out){$out=$active}
 Start-Sleep -Seconds $PollSeconds
}while($true)
Write-Host ('Monitor finished. Detailed results: '+$out) -ForegroundColor Cyan
$state=Read-Json (Join-Path $out 'manual-state.json')
if($state.state-in @('FAILED','INCOMPLETE')){Write-Host $state.detail -ForegroundColor Red;exit 1}
