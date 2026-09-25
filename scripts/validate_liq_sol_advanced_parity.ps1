param([switch]$CandidateOnly,[string]$BaselineFolder='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$stage=Join-Path $root ('.tmp/liq_sol_adv_parity_'+(Get-Date -Format yyyyMMdd_HHmmss))
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
if(!(Test-Path (Join-Path $worker 'terminal64.exe'))){Copy-Item -LiteralPath 'C:\MT5\DEMO\terminal64.exe' -Destination (Join-Path $worker 'terminal64.exe')}
if((Get-FileHash (Join-Path $worker 'terminal64.exe')).Hash -ne (Get-FileHash 'C:\MT5\DEMO\terminal64.exe').Hash){throw 'Isolated terminal binary hash mismatch'}
New-Item -ItemType Directory -Force $stage|Out-Null
function StageSource([string]$absolute,[string]$destinationRoot,[hashtable]$seen){
 $absolute=[IO.Path]::GetFullPath($absolute)
 if(!$absolute.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "External include: $absolute"}
 if($seen.ContainsKey($absolute)){return}
 $seen[$absolute]=$true
 $relative=$absolute.Substring($source.Length+1)
 $dest=Join-Path $destinationRoot ('IndicatorCodeExamples/'+$relative)
 New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath $absolute -Destination $dest
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($absolute),'(?m)^\s*#include\s+"([^"]+)"')){
  StageSource (Join-Path (Split-Path $absolute) $m.Groups[1].Value) $destinationRoot $seen
 }
}
$out=@()
$kinds=if($CandidateOnly){@('candidate')}else{@('candidate','baseline')}
foreach($kind in $kinds){
 $part=Join-Path $stage $kind
 $seen=@{}
 StageSource (Join-Path $source 'SolAdvanced/LiqNarrativeSol_Advanced.mq5') $part $seen
 $main=Join-Path $part 'IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5'
 if($kind -eq 'baseline'){
  $baseline=if($BaselineFolder){Join-Path $BaselineFolder 'LiqNarrativeSol_Advanced.mq5'}else{'C:\MT5\DEMO\MQL5\Experts\LiqNarrativeSol_Advanced.mq5'}
  if(!(Test-Path $baseline)){throw "Missing stable source: $baseline"}
  Copy-Item -LiteralPath $baseline -Destination $main -Force
  if($BaselineFolder){Copy-Item -Path (Join-Path $BaselineFolder '*.mqh') -Destination (Split-Path $main) -Force}
 }
 $file=Join-Path $part 'tests/mql5/LiqSolAdvancedParityProbe.mq5'
 New-Item -ItemType Directory -Force (Split-Path $file)|Out-Null
 Copy-Item (Join-Path $root 'tests/mql5/LiqSolAdvancedParityProbe.mq5') $file
 $log=$file+'.log'
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw "$kind compile timeout"}
 if(!(Test-Path $log) -or [IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw "$kind compile failed"}
 $name='LiqSolAdvancedParity_'+$kind+'_'+(Get-Date -Format HHmmss)
 Copy-Item ([IO.Path]::ChangeExtension($file,'.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $part 'probe.ini'
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
 $start=Get-Date
 $p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw "$kind probe timeout"}
 $result=Join-Path $worker ('MQL5/Files/'+$name+'.json')
 if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $start.AddSeconds(-2)){throw "$kind probe result missing"}
 Copy-Item $result (Join-Path $part 'result.json')
 $out+=Get-Content $result -Raw|ConvertFrom-Json
 Write-Output "$kind : $(Get-Content $result -Raw)"
}
$tested=$out[0]
if($tested.init -ne 0){throw 'EA initialization failed'}
if($tested.checks -lt 10 -or $tested.failed -ne 0){throw "NAS behavior probe failed: $($tested.failed) of $($tested.checks)"}
if($CandidateOnly){Write-Output "CANDIDATE_PROBE=PASS STAGE=$stage";return}
if($out[1].init -ne 0){throw 'Baseline initialization failed'}
foreach($field in @('total','wins','losses','open','invalid','netR','signalHash')){
 if($out[1].$field -ne $out[0].$field){throw "Default parity mismatch in $field"}
}
Write-Output "DEFAULT_PARITY=PASS STAGE=$stage"
