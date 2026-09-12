param([switch]$Install)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$report=Join-Path $root 'logs/OrbModelSlots_20260912'
$stage=Join-Path $report 'compile'
$target='C:\MT5\DEMO\MQL5\Experts'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$slots=Join-Path $common 'OrbML\Slots'
$expert='OrbUltimateEA_StrategyLibrary.mq5';$binary='OrbUltimateEA_StrategyLibrary.ex5'
$parity=Get-Content -LiteralPath (Join-Path $report 'mql_parity.json') -Raw|ConvertFrom-Json
if($parity.failed -ne 0 -or $parity.packs -ne 53 -or $parity.vectors -ne 4143 -or $parity.negative -ne 277){throw 'Slot probe not verified'}
if(!([IO.File]::ReadAllText((Join-Path $stage ($expert+'.log'))).Contains('Result: 0 errors, 0 warnings'))){throw 'No clean compile'}
$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-Includes([string]$name){
 if(!$names.Add($name)){return}
 $from=Join-Path $src $name
 if((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash){throw "Changed since compile: $name"}
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($from),'(?m)^\s*#include\s+"([^"]+)"')){Add-Includes $m.Groups[1].Value}
}
Add-Includes $expert
foreach($name in @('OrbStrategyMLCore.mqh','OrbStrategyR7Core.mqh','OrbStrategyModelSlot.mqh')){
 $probe=Join-Path $root ('.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbSlotProbe/'+$name)
 if((Get-FileHash -LiteralPath $probe).Hash -ne (Get-FileHash -LiteralPath (Join-Path $src $name)).Hash){throw "Changed since probe: $name"}
}
Write-Output "Plan: seed 52 unassigned champion slots; $($names.Count) source/include files plus EX5 in DEMO Experts and Experts\orb. Legacy unchanged. EX5 replacement can reload attached charts."
if(!$Install){exit 0}
$legacy=@{}
$legacyDir=Join-Path $common 'OrbML\CampaignModels'
Get-ChildItem -LiteralPath $legacyDir -Filter '*.experimental' -File | ForEach-Object {$legacy[$_.FullName]=(Get-FileHash -LiteralPath $_.FullName).Hash}
$backup=Join-Path $report ('install_backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
[IO.Directory]::CreateDirectory($backup)|Out-Null
$records=[Collections.Generic.List[object]]::new()
function Install-Verified([string]$from,[string]$to){
 $absolute=[IO.Path]::GetFullPath($to)
 if(!$absolute.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped DEMO Experts'}
 [IO.Directory]::CreateDirectory((Split-Path -Parent $absolute))|Out-Null
 $sha=(Get-FileHash -LiteralPath $from).Hash
 $old=if(Test-Path -LiteralPath $absolute){(Get-FileHash -LiteralPath $absolute).Hash}else{''}
 if($sha -ne $old){
  if($old){Copy-Item -LiteralPath $absolute -Destination (Join-Path $backup ($records.Count.ToString()+'_'+[IO.Path]::GetFileName($absolute)))}
  $temp=$absolute+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
  Copy-Item -LiteralPath $from -Destination $temp
  if(Test-Path -LiteralPath $absolute){[IO.File]::Replace($temp,$absolute,[NullString]::Value)}else{[IO.File]::Move($temp,$absolute)}
 }
 if((Get-FileHash -LiteralPath $absolute).Hash -ne $sha){throw 'Post-install checksum'}
 $records.Add([pscustomobject]@{path=$absolute;old=$old;sha256=$sha})
}
# Seed assets first; an existing assignment is validated, never overwritten.
& python (Join-Path $root 'scripts/orb_model_slot.py') migrate --root $slots --report (Join-Path $root 'logs/OrbR7Runtime_20260912')
if($LASTEXITCODE -ne 0){throw 'Slot migration failed'}
foreach($folder in @($target,(Join-Path $target 'orb'))){foreach($name in $names){Install-Verified (Join-Path $stage $name) (Join-Path $folder $name)}}
foreach($folder in @($target,(Join-Path $target 'orb'))){Install-Verified (Join-Path $stage $binary) (Join-Path $folder $binary)}
foreach($path in $legacy.Keys){if((Get-FileHash -LiteralPath $path).Hash -ne $legacy[$path]){throw 'Legacy model changed'}}
$records|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $report 'installation.json') -Encoding UTF8
$legacy|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $report 'legacy_unchanged.json') -Encoding UTF8
$canonical=Join-Path $src $binary
$temp=$canonical+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
Copy-Item -LiteralPath (Join-Path $stage $binary) -Destination $temp
if(Test-Path -LiteralPath $canonical){[IO.File]::Replace($temp,$canonical,[NullString]::Value)}else{[IO.File]::Move($temp,$canonical)}
if((Get-FileHash -LiteralPath $canonical).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $binary)).Hash){throw 'Canonical EX5 mismatch'}
Write-Output "Installed/hash-verified $($records.Count) source/binary targets; $($legacy.Count) Legacy models unchanged. No listeners, risk settings or ML toggles changed."
