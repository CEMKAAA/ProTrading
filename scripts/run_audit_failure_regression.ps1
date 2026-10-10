param([switch]$OriginOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'reports\verification_build\audit_failures'
$worker=Join-Path $root '.tmp\orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object Path -eq $terminal){throw 'Worker busy; no terminal stopped'}
Set-Location -LiteralPath $root
if($OriginOnly){
 foreach($name in @('AuditHistoryOriginProbe','AuditFailureBoundaryProbe')){
 $binary=Join-Path $stage ('source\tests\mql5\'+$name+'.ex5')
 $target=Join-Path $worker ('MQL5\Scripts\'+$name+'.ex5')
 Copy-Item -LiteralPath $binary -Destination ($target+'.pending') -Force
 Move-Item -LiteralPath ($target+'.pending') -Destination $target -Force
 $ini=Join-Path $stage 'origin-probe.ini'
 @('[Charts]','MaxBars=3000000','[Experts]','Enabled=0','AllowLiveTrading=0','AllowDllImport=0','[StartUp]',
   ('Script='+$name),'Symbol=BTCUSDm','Period=M5','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
 $started=Get-Date
 $process=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$process.WaitForExit(540000)){throw 'Origin probe timeout; only the existing worker is in use'}
 $report=Join-Path $worker ('MQL5\Files\'+$name+'.json')
 if(!(Test-Path -LiteralPath $report)-or (Get-Item $report).LastWriteTime-lt $started){throw 'Fresh origin report missing'}
 $destination=if($name-eq 'AuditHistoryOriginProbe'){'origin-probe.json'}else{'boundary-probe.json'}
 Copy-Item -LiteralPath $report -Destination (Join-Path $stage $destination) -Force
 $data=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
 Write-Output ($name+' '+$data.checks+' checks; '+$data.failed+' failures')
 $minimum=if($name-eq 'AuditHistoryOriginProbe'){18}else{24}
 if($data.failed-ne 0-or $data.checks-lt $minimum){throw ('Regression failed: '+$name)}
 }
 return
}
$epoch='2026.10.09 19:46:57'
$cases=@(
 @{id='orb_3e0172915b200d34c8536011e3f8';weeks=@(5,2)},
 @{id='macross_f6727de306f6a5ddf9a852139b83';weeks=@(260,208,156,104,52,20,10,5,2)},
 @{id='macross_192bebfbd6564e1507041179f898';weeks=@(260,208,156,104,52,20,10,5,2)},
 @{id='macross_efa9ad66e9bd221d1f4eb4c7f29b';weeks=@(260,208,156,104,52,20,10,5,2)},
 @{id='entrylab_c60359d5819d7663f71079cf72e6';weeks=@(5,2)},
 @{id='sol_b385e40b91a47fcfa5c0fa73400e';weeks=@(5,2)}
)
foreach($case in $cases){
 foreach($mode in @('campaign','dashboard')){
  $options=@{Mode='Run';ReportDir='reports/verification_build/audit_failures';StrategyIds=@($case.id);
    Weeks=$case.weeks;ResultSet=($mode+'-proof');AsOf=$epoch;TraceTrades=$true;Force=$true;TimeoutSeconds=1800;HistoryMaxBars=5000000}
  if($mode-eq 'dashboard'){$options.DashboardLoad=$true}
  & (Join-Path $PSScriptRoot 'run_strategy_window_campaign.ps1') @options
 }
}
& node (Join-Path $PSScriptRoot 'verify_audit_failure_regression.mjs') $stage
if($LASTEXITCODE-ne 0){throw 'Native audit regression failed; corrected results not published'}
& node (Join-Path $PSScriptRoot 'verify_strategy_campaign_parity.mjs') $stage
if($LASTEXITCODE-ne 0){throw 'Four-family native parity failed'}
