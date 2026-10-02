$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=[IO.Path]::GetFullPath((Join-Path $root 'IndicatorCodeExamples'))
$stage=[IO.Path]::GetFullPath((Get-Content (Join-Path $root '.tmp/native_balance_stage.txt') -Raw).Trim())
if(!$stage.StartsWith([IO.Path]::GetFullPath((Join-Path $root '.tmp'))+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Stage escaped workspace'}
if((Get-Content (Join-Path $stage 'balance_verified.txt') -Raw)-notmatch 'failed=0 families=4'){throw 'Four-family balance verification missing'}
$entries=@{orb='OrbUltimateEA_StrategyLibrary.mq5';macrossover_orb='MaCrossOverOrbEA.mq5';entry_engine_lab='EntryEngineLabEA.mq5';SolAdvanced='LiqNarrativeSol_Advanced.mq5'}
$folders=@{orb='orb';macrossover_orb='MaCrossOverOrb';entry_engine_lab='EntryEngineLab';SolAdvanced='SolAdvanced'}
$experts='C:\MT5\DEMO\MQL5\Experts'
$sharedPrevious=@{
 'NativeMarginQuote.mqh'='AA54A08FFF80135C36B5139730A8AFDD1FBC65922931B4C7C96D20211A7FE6C3'
 'NativeMarginPreview.mqh'='81F233949AB4B7B4D6C07E9CDBD18E328F8382F9F9408F63062FE223F73D408B'
}
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path-eq 'C:\MT5\DEMO\terminal64.exe'}){throw 'Close DEMO before publishing'}
$seen=@{}
function Collect([string]$path){
 $path=[IO.Path]::GetFullPath($path)
 if(!$path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'External source'}
 if($seen.ContainsKey($path)){return};$seen[$path]=$true
 $relative=$path.Substring($source.Length+1);$built=Join-Path $stage $relative
 if(!(Test-Path $built)-or (Get-FileHash $path).Hash-ne (Get-FileHash $built).Hash){throw "Changed source since verification: $relative"}
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($path),'(?m)^\s*#include\s+"([^"]+)"')){Collect (Join-Path (Split-Path $path) $m.Groups[1].Value)}
}
$plan=@()
foreach($family in $entries.Keys){
 $relative=$family+'/'+$entries[$family];$built=Join-Path $stage $relative
 if((Get-Content ($built+'.log') -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Production compile not clean'}
 $name=(Get-Content (Join-Path $stage ($family+'.name')) -Raw).Trim()
 if((Get-Content (Join-Path $stage ($name+'.txt')) -Raw)-notmatch '\bfailed=0\b'){throw 'Probe not verified'}
 Collect (Join-Path $source $relative)
 $binary=[IO.Path]::ChangeExtension($built,'.ex5')
 if(!(Test-Path $binary)){throw 'EX5 missing'}
 $plan+=@{Source=$binary;Target=(Join-Path $experts ($folders[$family]+'/'+[IO.Path]::ChangeExtension($entries[$family],'.ex5')));Workspace=(Join-Path $source ($family+'/'+[IO.Path]::ChangeExtension($entries[$family],'.ex5')))}
}
foreach($path in $seen.Keys){
 $relative=$path.Substring($source.Length+1);$pieces=$relative.Split('\');$targetRelative=$relative
 if($folders.ContainsKey($pieces[0])){$pieces[0]=$folders[$pieces[0]];$targetRelative=$pieces-join '\'}
 $target=[IO.Path]::GetFullPath((Join-Path $experts $targetRelative))
 if(!$target.StartsWith($experts+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Target escaped Experts'}
 if($pieces.Length-eq 1-and (Test-Path $target)-and (Get-FileHash $path).Hash-ne (Get-FileHash $target).Hash){
  if(!$sharedPrevious.ContainsKey($relative)-or (Get-FileHash $target).Hash-ne $sharedPrevious[$relative]){throw 'Shared dependency differs from known release'}
 }
 $plan+=@{Source=$path;Target=$target}
}
$backup=Join-Path $root ('.tmp/native_balance_deploy_backup_'+(Get-Date -Format yyyyMMdd_HHmmss));New-Item -ItemType Directory -Path $backup -Force|Out-Null
foreach($item in $plan){
 if(Test-Path $item.Target){$saved=Join-Path $backup $item.Target.Substring($experts.Length+1);New-Item -ItemType Directory -Path (Split-Path $saved) -Force|Out-Null;Copy-Item -LiteralPath $item.Target -Destination $saved}
 if($item.Workspace-and (Test-Path $item.Workspace)){$saved=Join-Path $backup ('workspace/'+$item.Workspace.Substring($source.Length+1));New-Item -ItemType Directory -Path (Split-Path $saved) -Force|Out-Null;Copy-Item -LiteralPath $item.Workspace -Destination $saved}
}
$manifest=@("VERIFIED_STAGE=$stage","BACKUP=$backup")
foreach($item in $plan){
 New-Item -ItemType Directory -Path (Split-Path $item.Target) -Force|Out-Null;Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
 $hash=(Get-FileHash $item.Source).Hash;if((Get-FileHash $item.Target).Hash-ne $hash){throw 'Deployment hash mismatch'}
 if($item.Workspace){Copy-Item -LiteralPath $item.Source -Destination $item.Workspace -Force;if((Get-FileHash $item.Workspace).Hash-ne $hash){throw 'Workspace EX5 mismatch'}}
 $manifest+="$hash $($item.Target)"
}
$manifest|Set-Content (Join-Path $backup 'manifest.txt') -Encoding UTF8
Write-Output "DEPLOYED_FAMILIES=4 FILES=$($plan.Count) BACKUP=$backup"
