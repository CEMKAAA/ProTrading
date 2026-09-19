param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$stagePath=(Resolve-Path -LiteralPath $Stage).Path
if(!$stagePath.StartsWith((Join-Path $root '.tmp/clock_save_').Replace('/','\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected stage path'}
$tag=Get-Date -Format yyyyMMdd_HHmmss
$backup=Join-Path $root ('logs/clock_save_install/'+$tag)
New-Item -ItemType Directory -Force $backup|Out-Null
$manifest=New-Object Collections.Generic.List[object]
$mains=@('OrbUltimateEA.mq5','OrbUltimateEA_Channel.mq5','OrbUltimateEA_StrategyLibrary.mq5','macrossover_orb/MaCrossOverOrbEA.mq5','LiquidityNarrative_MT5_EA.mq5','LiquidityNarrative_Invert_MT5_EA.mq5','LiqNarrativeSolVersion.mq5','LiqNarrativeSol_Advanced.mq5','LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')
foreach($n in $mains){
 $log=Join-Path $stagePath ($n+'.log')
 if(!(Test-Path $log) -or [IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){throw "Unverified build $n"}
}
function InstallFile($from,$to){
 $hash=(Get-FileHash -LiteralPath $from).Hash
 if((Test-Path -LiteralPath $to) -and (Get-FileHash -LiteralPath $to).Hash -eq $hash){return}
 New-Item -ItemType Directory -Force (Split-Path $to)|Out-Null
 if(Test-Path -LiteralPath $to){Copy-Item -LiteralPath $to -Destination (Join-Path $backup (([string]$manifest.Count)+'_'+(Split-Path $to -Leaf)))}
 $temp=$to+'.install_'+$tag
 Copy-Item -LiteralPath $from -Destination $temp
 if((Get-FileHash -LiteralPath $temp).Hash -ne $hash){throw "Staging checksum $to"}
 $previous=$to+'.previous_'+$tag
 $had=Test-Path -LiteralPath $to
 if($had){Move-Item -LiteralPath $to -Destination $previous}
 try{Move-Item -LiteralPath $temp -Destination $to}catch{if($had){Move-Item -LiteralPath $previous -Destination $to};throw}
 if((Get-FileHash -LiteralPath $to).Hash -ne $hash){throw "Final checksum $to"}
 $manifest.Add([pscustomobject]@{path=$to;sha256=$hash})
}
function Gather($rel,$files){
 if($files.ContainsKey($rel)){return};$files[$rel]=$true
 $source=Join-Path $src $rel;$staged=Join-Path $stagePath $rel
 if((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $staged).Hash){throw "Source changed since build $rel"}
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($source),'(?m)^\s*#include\s+"([^"]+)"')){
  $child=$m.Groups[1].Value;if(Split-Path $rel){$child=Join-Path (Split-Path $rel) $child};Gather $child $files
 }
}
foreach($n in $mains){
 $files=@{};Gather $n $files
 if($n.StartsWith('OrbUltimate')){$targets=@((Join-Path $src 'orb'),'C:\MT5\DEMO\MQL5\Experts\orb')}
 elseif($n.StartsWith('macrossover_orb/')){$targets=@('C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb')}
 else{$targets=@((Join-Path $src 'liq'),'C:\MT5\DEMO\MQL5\Experts');if($n -eq 'LiqNarrativeSol_Advanced.mq5'){$targets+='C:\MT5\DEMO\MQL5\Experts\SolAdvanced'}}
 foreach($rel in $files.Keys){foreach($target in $targets){InstallFile (Join-Path $stagePath $rel) (Join-Path $target (Split-Path $rel -Leaf))}}
 $binary=[IO.Path]::ChangeExtension($n,'.ex5')
 InstallFile (Join-Path $stagePath $binary) (Join-Path $src $binary)
 foreach($target in $targets){InstallFile (Join-Path $stagePath $binary) (Join-Path $target (Split-Path $binary -Leaf))}
}
$manifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $backup 'manifest.json') -Encoding UTF8
Write-Output "Verified $($manifest.Count) changed files. Backup: $backup. No running chart restarted."
