param([switch]$Install)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$report=Join-Path $root 'logs/OrbRegimeLeaderboard_20260912'
$stage=Join-Path $report 'compile'
$target='C:\MT5\DEMO\MQL5\Experts'
$common=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files'
$dataTarget=Join-Path $common 'OrbML\RegimeLeaderboard'
$expert='OrbUltimateEA_StrategyLibrary.mq5';$binary='OrbUltimateEA_StrategyLibrary.ex5'
$r=Get-Content -LiteralPath (Join-Path $report 'mql_parity.json') -Raw|ConvertFrom-Json
if($r.failed -ne 0 -or $r.reports -ne 155 -or $r.cells -ne 1240 -or $r.negative -ne 1085){throw 'Regime probe not verified'}
if(!([IO.File]::ReadAllText((Join-Path $stage ($expert+'.log'))).Contains('Result: 0 errors, 0 warnings'))){throw 'No clean compile'}
$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-Includes([string]$name){
 if(!$names.Add($name)){return}
 $from=Join-Path $src $name
 if((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash){throw "Changed since compile: $name"}
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($from),'(?m)^\s*#include\s+"([^"]+)"')){Add-Includes $m.Groups[1].Value}
}
Add-Includes $expert
foreach($name in @('OrbStrategyMLCore.mqh','OrbStrategyR7Core.mqh','OrbStrategyModelSlot.mqh','OrbStrategyRegimeLeaderboard.mqh')){
 $p=Join-Path $root ('.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbRegimeLbProbe/'+$name)
 if((Get-FileHash -LiteralPath $p).Hash -ne (Get-FileHash -LiteralPath (Join-Path $src $name)).Hash){throw 'Changed since no-order probe'}
}
$campaign=Get-Content -LiteralPath (Join-Path $report 'campaign.json') -Raw|ConvertFrom-Json
foreach($p in $campaign.provenance){if((Get-FileHash -LiteralPath $p.path).Hash.ToLowerInvariant() -ne $p.sha256){throw 'Campaign source/model changed'}}
foreach($p in $campaign.files){
 if([IO.Path]::GetFileName($p.name) -ne $p.name){throw 'Unsafe report name'}
 if((Get-FileHash -LiteralPath (Join-Path $report ('Files\OrbML\RegimeLeaderboard\'+$p.name))).Hash.ToLowerInvariant() -ne $p.sha256){throw 'Report changed'}
}
Write-Output "Plan: 155 identity-bound reports, $($names.Count) source/include files plus EX5 in DEMO Experts and Experts\orb. Models/listeners untouched. EX5 replacement may reload attached charts."
if(!$Install){exit 0}
$backup=Join-Path $report ('install_backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
[IO.Directory]::CreateDirectory($backup)|Out-Null
$records=[Collections.Generic.List[object]]::new()
function Install-Verified([string]$from,[string]$to){
 $absolute=[IO.Path]::GetFullPath($to)
 if(!$absolute.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase) -and !$absolute.StartsWith($dataTarget+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped targets'}
 [IO.Directory]::CreateDirectory((Split-Path -Parent $absolute))|Out-Null
 $sha=(Get-FileHash -LiteralPath $from).Hash
 $old=if(Test-Path -LiteralPath $absolute){(Get-FileHash -LiteralPath $absolute).Hash}else{''}
 if($sha -ne $old){
  if($old){Copy-Item -LiteralPath $absolute -Destination (Join-Path $backup ($records.Count.ToString()+'_'+[IO.Path]::GetFileName($absolute)))}
  $temp=$absolute+'.'+[Guid]::NewGuid().ToString('N')+'.tmp';Copy-Item -LiteralPath $from -Destination $temp
  if(Test-Path -LiteralPath $absolute){[IO.File]::Replace($temp,$absolute,[NullString]::Value)}else{[IO.File]::Move($temp,$absolute)}
 }
 if((Get-FileHash -LiteralPath $absolute).Hash -ne $sha){throw 'Post-install checksum'}
 $records.Add([pscustomobject]@{path=$absolute;old=$old;sha256=$sha})
}
foreach($p in $campaign.files){Install-Verified (Join-Path $report ('Files\OrbML\RegimeLeaderboard\'+$p.name)) (Join-Path $dataTarget $p.name)}
foreach($folder in @($target,(Join-Path $target 'orb'))){foreach($name in $names){Install-Verified (Join-Path $stage $name) (Join-Path $folder $name)}}
foreach($folder in @($target,(Join-Path $target 'orb'))){Install-Verified (Join-Path $stage $binary) (Join-Path $folder $binary)}
$records|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $report 'installation.json') -Encoding UTF8
$canonical=Join-Path $src $binary;$temp=$canonical+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
Copy-Item -LiteralPath (Join-Path $stage $binary) -Destination $temp
if(Test-Path -LiteralPath $canonical){[IO.File]::Replace($temp,$canonical,[NullString]::Value)}else{[IO.File]::Move($temp,$canonical)}
if((Get-FileHash -LiteralPath $canonical).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $binary)).Hash){throw 'Canonical EX5 mismatch'}
foreach($p in $campaign.provenance){if((Get-FileHash -LiteralPath $p.path).Hash.ToLowerInvariant() -ne $p.sha256){throw 'Source/model changed during install'}}
Write-Output "Installed/hash-verified $($records.Count) targets. Existing models, source datasets and assignments unchanged."
