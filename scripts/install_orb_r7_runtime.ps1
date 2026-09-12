param([switch]$Install)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$report=Join-Path $root 'logs/OrbR7Runtime_20260912'
$stage=Join-Path $report 'compile'
$expert='OrbUltimateEA_StrategyLibrary.mq5'
$binary='OrbUltimateEA_StrategyLibrary.ex5'
$target='C:\MT5\DEMO\MQL5\Experts'
$modelTarget=Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\OrbML\R7'
$parity=Get-Content -LiteralPath (Join-Path $report 'mql_parity.json') -Raw|ConvertFrom-Json
if($parity.failed -ne 0 -or $parity.packs -ne 52 -or $parity.vectors -ne 4111){throw 'MQL parity not verified'}
if(!([IO.File]::ReadAllText((Join-Path $stage ($expert+'.log'))).Contains('Result: 0 errors, 0 warnings'))){throw 'No clean compile'}
$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
function Add-Includes([string]$name){
 if(!$names.Add($name)){return}
 $from=Join-Path $src $name
 if((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash){throw "Changed since compile: $name"}
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($from),'(?m)^\s*#include\s+"([^"]+)"')){Add-Includes $m.Groups[1].Value}
}
Add-Includes $expert
$manifest=Get-Content -LiteralPath (Join-Path $report 'verification.json') -Raw|ConvertFrom-Json
foreach($r in $manifest.records){
 $p=Join-Path $report ('Files\OrbML\R7\'+$r.id+'.r7')
 if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -ne $r.model_sha){throw "Model checksum $($r.id)"}
}
Write-Output "Plan: 52 new R7 archives; $($names.Count) source/include files plus EX5 in DEMO Experts and Experts\orb. No Legacy model overwrite."
if(!$Install){exit 0}
$backup=Join-Path $report ('install_backup_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
[IO.Directory]::CreateDirectory($backup)|Out-Null
$records=[Collections.Generic.List[object]]::new()
function Install-Verified([string]$from,[string]$to){
 $absolute=[IO.Path]::GetFullPath($to)
 if(!$absolute.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase) -and !$absolute.StartsWith($modelTarget+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped target'}
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
# Assets before EX5; no model-generation/ML global variables are changed.
foreach($r in $manifest.records){Install-Verified (Join-Path $report ('Files\OrbML\R7\'+$r.id+'.r7')) (Join-Path $modelTarget ($r.id+'.r7'))}
foreach($folder in @($target,(Join-Path $target 'orb'))){foreach($name in $names){Install-Verified (Join-Path $stage $name) (Join-Path $folder $name)}}
foreach($folder in @($target,(Join-Path $target 'orb'))){Install-Verified (Join-Path $stage $binary) (Join-Path $folder $binary)}
Copy-Item -LiteralPath (Join-Path $stage $binary) -Destination (Join-Path $src $binary)
$records|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $report 'installation.json') -Encoding UTF8
Write-Output "Installed and hash-verified $($records.Count) files. No listener files or Legacy models changed; no process restart requested."
