$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'build_orb_ml_prior_five.ps1')
$common=Join-Path $env:APPDATA 'MetaQuotes/Terminal/Common/Files'
$dest=Join-Path $common 'OrbMLPriorFive_20260910'
foreach($d in @('Datasets','Done','Settings','UserStrategies')){[IO.Directory]::CreateDirectory((Join-Path $dest $d))|Out-Null}
$original=Join-Path $common 'OrbMLCampaign_20260909_v3/UserStrategies'
foreach($f in Get-ChildItem $original -Filter '*.preset'){
    $to=Join-Path $dest ('UserStrategies/'+$f.Name)
    if(Test-Path $to){if((Get-FileHash $to).Hash -ne (Get-FileHash $f.FullName).Hash){throw 'Frozen custom preset mismatch'}}
    else{Copy-Item -LiteralPath $f.FullName -Destination $to}
}
$report=Join-Path $root 'logs/OrbMLPriorFive_20260910'
$src=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLPriorFive/OrbMLPriorFive.mq5'
$log=Join-Path $report 'export_compile.log'
$p=Start-Process 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$src+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(240000)){throw 'Compile timeout'}
if(!([IO.File]::ReadAllText($log).Contains('0 errors, 0 warnings'))){throw 'Export compile failed'}
Get-Content $log -Tail 1
$exe=Join-Path $root '.tmp/orb_jp225_full_worker/terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $exe}){throw 'Isolated worker busy'}
$p=Start-Process $exe -ArgumentList ('/portable /config:"'+(Join-Path $report 'export.ini')+'"') -WindowStyle Hidden -PassThru
$start=Get-Date
while(!$p.WaitForExit(15000)){
    $manifest=Join-Path $dest 'manifest_USDJPYm.tsv'
    if(Test-Path $manifest){Get-Content $manifest -Tail 1}
    if(((Get-Date)-$start).TotalMinutes -gt 60){throw 'Inspect isolated worker: export timeout'}
}
if(!(Test-Path (Join-Path $dest 'symbol_USDJPYm.finished'))){throw 'Export incomplete'}
Copy-Item (Join-Path $dest 'manifest_USDJPYm.tsv') (Join-Path $report 'manifest_USDJPYm.tsv')
'USDJPY PRIOR PERIOD EXPORT COMPLETE'
