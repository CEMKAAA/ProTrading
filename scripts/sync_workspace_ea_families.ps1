param([switch]$Check)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$families=[ordered]@{
    nas=@('NasUltimate_SATS_PartialNoBE_EA.mq5','NasUltimate_StrategyLibrary.mq5')
    liq=@('LiquidityNarrative_MT5_EA.mq5','LiquidityNarrative_Invert_MT5_EA.mq5','LiqNarrativeSolVersion.mq5','LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')
}
$plans=[Collections.Generic.List[object]]::new()
foreach($family in $families.Keys) {
    $folder=Join-Path $src $family
    $files=@{}; $edges=[Collections.Generic.List[object]]::new()
    function Visit-Source([string]$relative) {
        $source=[IO.Path]::GetFullPath((Join-Path $src $relative))
        if(!$source.StartsWith($src+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Include outside source root: $relative"}
        $relative=$source.Substring($src.Length+1)
        if($files.ContainsKey($relative)){return}
        if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing include: $relative"}
        $files[$relative]=[pscustomobject]@{file=$relative;sha256=(Get-FileHash -LiteralPath $source).Hash}
        foreach($m in [regex]::Matches([IO.File]::ReadAllText($source),'(?m)^\s*#include\s+"([^"]+)"')) {
            $include=$m.Groups[1].Value
            $child=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $source) $include))
            if(!$child.StartsWith($src+'\',[StringComparison]::OrdinalIgnoreCase)){throw "External include: $include"}
            $child=$child.Substring($src.Length+1)
            $edges.Add([pscustomobject]@{parent=$relative;include=$child})
            Visit-Source $child
        }
    }
    foreach($entry in $families[$family]){Visit-Source $entry}
    # Only copy available binaries; never attempt to compile an MQH by itself.
    foreach($entry in $families[$family]) {
        $binary=[IO.Path]::ChangeExtension($entry,'.ex5');$path=Join-Path $src $binary
        if(Test-Path -LiteralPath $path){$files[$binary]=[pscustomobject]@{file=$binary;sha256=(Get-FileHash -LiteralPath $path).Hash}}
    }
    $manifest=Join-Path $folder 'manifest.json';$previous=@{}
    if(Test-Path -LiteralPath $manifest) {
        foreach($row in (Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json).files){$previous[$row.file]=$row.sha256}
    }
    foreach($row in $files.Values) {
        $dest=Join-Path $folder $row.file
        if(Test-Path -LiteralPath $dest) {
            $hash=(Get-FileHash -LiteralPath $dest).Hash
            if($hash -ne $row.sha256 -and (!$previous.ContainsKey($row.file) -or $hash -ne $previous[$row.file])) {
                throw "Locally modified grouped file; reconcile before syncing: $dest"
            }
        }
        if($Check -and (!(Test-Path -LiteralPath $dest) -or (Get-FileHash -LiteralPath $dest).Hash -ne $row.sha256)) {
            throw "Missing/stale grouped file: $dest"
        }
    }
    if($previous.Keys.Where({!$files.ContainsKey($_)}).Count -and $family -ne 'liq'){
        throw "Dependency removed in $family; review old manifest before removing obsolete copies"
    }
    $plans.Add([pscustomobject]@{family=$family;folder=$folder;entries=$families[$family];files=@($files.Values|Sort-Object file);edges=@($edges|Sort-Object parent,include)})
}
if(!$Check) {
    foreach($plan in $plans) {
        New-Item -ItemType Directory -Path $plan.folder -Force|Out-Null
        foreach($row in $plan.files) {
            $source=Join-Path $src $row.file;$dest=Join-Path $plan.folder $row.file
            if((Get-FileHash -LiteralPath $source).Hash -ne $row.sha256){throw 'Source changed during sync'}
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force|Out-Null
            if(!(Test-Path -LiteralPath $dest) -or (Get-FileHash -LiteralPath $dest).Hash -ne $row.sha256){Copy-Item -LiteralPath $source -Destination $dest -Force}
            if((Get-FileHash -LiteralPath $dest).Hash -ne $row.sha256){throw "Copy mismatch: $dest"}
        }
        [ordered]@{canonical_root='..';entrypoints=$plan.entries;files=$plan.files;dependencies=$plan.edges}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $plan.folder 'manifest.json') -Encoding UTF8
        $lines=@('# '+$plan.family.ToUpper()+' EA Family','','Generated grouping. Canonical editable sources remain in `IndicatorCodeExamples/`.','Do not edit this mirror independently; use `scripts/sync_workspace_ea_families.ps1` after changing canonical sources.','Verify with `scripts/sync_workspace_ea_families.ps1 -Check`.','','## Entry Points','')
        $lines+=@($plan.entries|ForEach-Object {'- `'+$_+'`'})
        $lines+=@('','Compile MQ5 entry points only, not MQH files. `<Trade/...>` comes from the MT5 standard Include folder.','EX5 files are copies of available root binaries; synchronization is not recompilation.','The older ORB Channel variant is retained separately; inclusion here does not upgrade it.','','## Local Include Dependencies','','| Used by | Includes |','| --- | --- |')
        $lines+=@($plan.edges|ForEach-Object {'| `'+$_.parent+'` | `'+$_.include+'` |'})
        $lines+=@('','Shared includes may appear in several families. SHA-256 hashes are recorded in `manifest.json`.','Listeners, research data, trained models and SacredVersions are not moved or duplicated here.')
        $lines|Set-Content -LiteralPath (Join-Path $plan.folder 'README.md') -Encoding UTF8
    }
}
foreach($plan in $plans){Write-Output ($plan.family+': '+$plan.entries.Count+' entry points, '+$plan.files.Count+' matching files')}
