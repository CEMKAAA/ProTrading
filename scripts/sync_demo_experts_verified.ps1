param([switch]$Deploy,[string]$ReportDir='logs/demo_sync_20260909_v686',[switch]$StrategyLibraryOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$target='C:\MT5\DEMO\MQL5\Experts'
$report=[IO.Path]::GetFullPath((Join-Path $root $ReportDir))
if(!$report.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Report outside workspace'}
$stage=Join-Path $report 'stage'
[IO.Directory]::CreateDirectory($stage)|Out-Null
$canonical=@{}
Get-ChildItem -LiteralPath $src -File | Where-Object {$_.Extension -in '.mq5','.mqh','.ex5'} | ForEach-Object {$canonical[$_.Name]=$_.FullName}
$map=@{}
$unmatched=[Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath $target -Recurse -File | Where-Object {$_.Extension -in '.mq5','.mqh','.ex5'} | ForEach-Object {
    if($canonical.ContainsKey($_.Name)){$map[$_.FullName]=$_.Name}else{$unmatched.Add($_.FullName)}
}
foreach($name in @('OrbUltimateEA_StrategyLibrary.mq5','OrbUltimateEA.mq5','NasUltimate_SATS_PartialNoBE_EA.mq5','LiqNarrativeSolVersion.mq5','LiqNarrativeSol_Advanced.mq5','LiquidityNarrative_MT5_EA.mq5')){
    $map[(Join-Path $target $name)]=$name
}
$map[(Join-Path $target 'orb\OrbUltimateEA_StrategyLibrary.mq5')]='OrbUltimateEA_StrategyLibrary.mq5'
if($StrategyLibraryOnly){
    $map=@{}
    $map[(Join-Path $target 'OrbUltimateEA_StrategyLibrary.mq5')]='OrbUltimateEA_StrategyLibrary.mq5'
    $map[(Join-Path $target 'orb\OrbUltimateEA_StrategyLibrary.mq5')]='OrbUltimateEA_StrategyLibrary.mq5'
}
# Add quote-includes beside each source, including subfolder copies; never flatten vendor libraries.
$visited=@{}
function Add-Dependencies([string]$name,[string]$folder){
    $visit=Join-Path $folder $name
    if($visited.ContainsKey($visit)){return}
    $visited[$visit]=$true
    $content=[IO.File]::ReadAllText($canonical[$name])
    foreach($m in [regex]::Matches($content,'(?m)^\s*#include\s+"([^"]+)"')){
        $inc=$m.Groups[1].Value
        if(!$canonical.ContainsKey($inc)){throw "Missing canonical include $inc in $name"}
        $dest=Join-Path $folder $inc
        $map[$dest]=$inc
        Add-Dependencies $inc $folder
    }
}
foreach($dest in @($map.Keys)){
    if([IO.Path]::GetExtension($dest) -eq '.mq5'){Add-Dependencies $map[$dest] (Split-Path -Parent $dest)}
}
$sources=@($map.Values | Where-Object {$_ -like '*.mq5'} | Sort-Object -Unique)
# A project binary is never deployed without compiling its current canonical source.
foreach($dest in @($map.Keys)){
    if($dest -like '*.ex5'){
        $source=[IO.Path]::ChangeExtension($map[$dest],'.mq5')
        if(!$canonical.ContainsKey($source)){ $unmatched.Add($dest);$map.Remove($dest);continue }
        $map[[IO.Path]::ChangeExtension($dest,'.mq5')]=$source
        Add-Dependencies $source (Split-Path -Parent $dest)
    }
}
$sources=@($map.Values | Where-Object {$_ -like '*.mq5'} | Sort-Object -Unique)
foreach($dest in @($map.Keys)){
    if($dest -like '*.mq5'){$map[[IO.Path]::ChangeExtension($dest,'.ex5')]=[IO.Path]::ChangeExtension($map[$dest],'.ex5')}
}
$plan=@($map.GetEnumerator()|Sort-Object Key|ForEach-Object {[pscustomobject]@{destination=$_.Key;name=$_.Value}})
$plan|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $report 'plan.json') -Encoding UTF8
$unmatched|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $report 'unmanaged_not_changed.json') -Encoding UTF8
Write-Output "PLAN $($plan.Count) files; $($sources.Count) distinct EA compilations; $($unmatched.Count) unmatched files left alone"
if(!$Deploy){exit 0}
Get-ChildItem -LiteralPath $src -File|Where-Object {$_.Extension -in '.mq5','.mqh'}|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $stage -Force}
$compiled=[Collections.Generic.List[object]]::new()
foreach($name in $sources){
    $file=Join-Path $stage $name
    $log=Join-Path $stage ($name+'.log')
    $binary=[IO.Path]::ChangeExtension($file,'.ex5')
    $before=Get-Date
    $args='/compile:"'+$file+'" /log:"'+$log+'"'
    $proc=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
    if(!$proc.WaitForExit(240000)){throw "Compile timeout $name; no deployment started"}
    if(!(Test-Path -LiteralPath $log)){throw "Missing compile log $name"}
    $tail=Get-Content -LiteralPath $log -Tail 4
    if(($tail -join "`n") -notmatch 'Result: 0 errors, 0 warnings' -or !(Test-Path -LiteralPath $binary)){
        throw "Compile not clean $name : $($tail -join ' ') ; no deployment started"
    }
    if((Get-Item -LiteralPath $binary).LastWriteTime -lt $before.AddSeconds(-2)){throw "Stale binary $name"}
    $compiled.Add([pscustomobject]@{name=$name;binary_sha256=(Get-FileHash -LiteralPath $binary).Hash;result=$tail[-1]})
    Write-Output "COMPILED $name"
}
$compiled|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $report 'compile_results.json') -Encoding UTF8
# Abort if a user edited a canonical source during the compilation batch.
foreach($name in @($plan.name|Where-Object {$_ -notlike '*.ex5'}|Sort-Object -Unique)){
    if((Get-FileHash -LiteralPath $canonical[$name]).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash){throw "Source changed during compilation: $name"}
}
$backup=Join-Path $report ('backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
$results=[Collections.Generic.List[object]]::new()
function Set-VerifiedFile([string]$from,[string]$to){
    $temp=$to+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    Copy-Item -LiteralPath $from -Destination $temp
    for($attempt=0;$attempt -lt 20;$attempt++){
        try {
            if(Test-Path -LiteralPath $to){[IO.File]::Replace($temp,$to,[NullString]::Value)}
            else{[IO.File]::Move($temp,$to)}
            return
        } catch [IO.IOException] {
            if($attempt -eq 19){throw}
            Start-Sleep -Milliseconds 250
        }
    }
}
# Headers/sources first, verified self-contained binaries last. No partially written EX5.
foreach($item in ($plan|Sort-Object @{Expression={switch([IO.Path]::GetExtension($_.name)){'.mqh'{0};'.mq5'{1};default{2}}}},destination)){
    $dest=[IO.Path]::GetFullPath($item.destination)
    if(!$dest.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped Experts'}
    $file=Join-Path $stage $item.name
    $hash=(Get-FileHash -LiteralPath $file).Hash
    $old=if(Test-Path -LiteralPath $dest){(Get-FileHash -LiteralPath $dest).Hash}else{''}
    if($old -ne $hash){
        if($old){$bak=Join-Path $backup $dest.Substring($target.Length+1);[IO.Directory]::CreateDirectory((Split-Path -Parent $bak))|Out-Null;Copy-Item -LiteralPath $dest -Destination $bak}
        [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
        Set-VerifiedFile $file $dest
    }
    if((Get-FileHash -LiteralPath $dest).Hash -ne $hash){throw "Hash mismatch after deployment: $dest"}
    $results.Add([pscustomobject]@{destination=$dest;sha256=$hash;previous_sha256=$old;changed=($old -ne $hash)})
}
foreach($name in $sources){
    $binary=[IO.Path]::ChangeExtension($name,'.ex5')
    Set-VerifiedFile (Join-Path $stage $binary) (Join-Path $src $binary)
}
$results|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $report 'verified.json') -Encoding UTF8
Write-Output "VERIFIED $($results.Count) files; no terminal restart or trading setting changes requested"
