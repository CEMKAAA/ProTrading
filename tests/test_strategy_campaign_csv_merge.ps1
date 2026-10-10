$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\run_strategy_window_campaign.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Campaign parse failure'}
foreach($name in @('Write-AtomicText','Write-AtomicCsv')){
 $definition=$ast.Find({param($node) $node-is [Management.Automation.Language.FunctionDefinitionAst]-and $node.Name-eq $name},$true)
 if(!$definition){throw ('Missing '+$name)}
 Invoke-Expression $definition.Extent.Text
}
$folder=Join-Path $root 'reports\verification_build\campaign_csv_merge'
New-Item -ItemType Directory -Force $folder|Out-Null
$path=Join-Path $folder 'fixture.csv'
$before=[pscustomobject]@{id='first';status='AUDITED';verification_mode='cached';detail='quotes " and commas,'}
$after=[pscustomobject]@{id='second';status='HISTORY_UNAVAILABLE';unavailable_parity_verified='1';detail="two`nlines"}
foreach($rows in @(@($before,$after),@($after,$before))){
 Write-AtomicCsv $path $rows
 $saved=@(Import-Csv -LiteralPath $path)
 if($saved.Count-ne 2){throw 'Row lost'}
 $a=$saved|Where-Object id -eq first;$b=$saved|Where-Object id -eq second
 if($a.verification_mode-ne 'cached'-or $b.unavailable_parity_verified-ne '1'){throw 'Heterogeneous column lost'}
 if($a.detail-cne $before.detail-or $b.detail-cne $after.detail){throw 'Quoted/multiline CSV changed'}
}
Write-Output 'CAMPAIGN_CSV_MERGE: both row orders preserve all verification columns and values'
