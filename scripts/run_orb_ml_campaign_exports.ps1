param([string]$Campaign='OrbMLCampaign_20260909')
$ErrorActionPreference='Stop'
if($Campaign -notmatch '^OrbMLCampaign_[A-Za-z0-9_]+$'){throw 'Unsafe campaign name'}
$base=Split-Path -Parent $PSScriptRoot
$exe=Join-Path $base '.tmp/orb_jp225_full_worker/terminal64.exe'
$existing=@(Get-CimInstance Win32_Process | Where-Object {$_.ExecutablePath -eq $exe})
if($existing.Count){throw 'Isolated terminal already running; refusing competing launch'}
$common=Join-Path $env:APPDATA 'MetaQuotes/Terminal/Common/Files'
$dest=Join-Path $common $Campaign
foreach($dir in @('Datasets','Settings','Done','UserStrategies','Results')){[IO.Directory]::CreateDirectory((Join-Path $dest $dir))|Out-Null}
foreach($f in Get-ChildItem -LiteralPath (Join-Path $common 'OrbStrategyUserLibrary') -Filter '*.preset'){
    $target=Join-Path (Join-Path $dest 'UserStrategies') $f.Name
    if(Test-Path -LiteralPath $target){if((Get-FileHash $target).Hash -ne (Get-FileHash $f.FullName).Hash){throw 'Custom preset changed since snapshot: '+$f.Name}}
    else{Copy-Item -LiteralPath $f.FullName -Destination $target}
}
$log=Join-Path $base ('logs/'+$Campaign)
$compile=Join-Path $log 'compile.log'
$src=Join-Path $base '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbMLCampaign/OrbMLCampaign.mq5'
$args='/compile:"'+$src+'" /log:"'+$compile+'"'
$p=Start-Process 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
$p.WaitForExit()
if(!([IO.File]::ReadAllText($compile).Contains('0 errors, 0 warnings'))){throw 'Campaign compile failed; inspect compile.log'}
Get-Content $compile -Tail 2
foreach($symbol in @('JP225m','USDJPYm','USTECm')){
    if(Test-Path -LiteralPath (Join-Path $dest ('symbol_'+$symbol+'.finished'))){Write-Output ('Already completed '+$symbol);continue}
    $args='/portable /config:"'+(Join-Path $log ($symbol+'.ini'))+'"'
    $p=Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden -PassThru
    Write-Output ('RUNNING '+$symbol+' isolated PID='+$p.Id)
    $start=Get-Date
    while(!$p.WaitForExit(15000)){
        $manifest=Join-Path $dest ('manifest_'+$symbol+'.tsv')
        if(Test-Path $manifest){Get-Content $manifest -Tail 1}
        if(((Get-Date)-$start).TotalHours -gt 3){throw 'Export time budget reached; inspect isolated terminal before resuming'}
    }
    if(!(Test-Path -LiteralPath (Join-Path $dest ('symbol_'+$symbol+'.finished')))){throw 'Terminal exited without campaign completion: '+$symbol}
    Write-Output ('COMPLETED '+$symbol)
}
Write-Output ('ALL SYMBOL EXPORTS FINISHED '+$dest)
