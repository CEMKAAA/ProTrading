param([switch]$RunProbes,[switch]$CandidateOnly,[switch]$RunReplay)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$stage=Join-Path $root 'tmp/position_policy_20261004'
$entries=@{orb='OrbUltimateEA_StrategyLibrary.mq5';SolAdvanced='LiqNarrativeSol_Advanced.mq5'}
# Extract the actual MaCross functions, changing identifiers only, not logic.
function ReferenceFunction([string]$path,[string]$name){
 $text=[IO.File]::ReadAllText($path)
 $start=$text.IndexOf($name+'(',[StringComparison]::Ordinal)
 if($start-lt 0){throw "Reference function missing: $name"}
 $start=$text.LastIndexOf("`n",$start)+1
 $open=$text.IndexOf('{',$start);$depth=0;$end=-1
 for($i=$open;$i-lt $text.Length;$i++){
  if($text[$i]-eq '{'){$depth++}
  if($text[$i]-eq '}'){$depth--;if($depth-eq 0){$end=$i;break}}
 }
 if($open-lt 0-or $end-lt 0){throw "Incomplete reference function: $name"}
 return $text.Substring($start,$end-$start+1)
}
$maExit=Join-Path $source 'macrossover_orb/MaExitPolicy.mqh'
$maCapacity=Join-Path $source 'macrossover_orb/MaIndependentEntries.mqh'
$reference='struct PolicyMaEvent {datetime signalTime;int direction;};'+"`r`n"
$reference+=(ReferenceFunction $maExit 'MaKernelExitAt').Replace('MaKernelExitAt','ReferenceMaKernelExitAt').Replace('MaCrossAuditEvent','PolicyMaEvent')+"`r`n"
$reference+=(ReferenceFunction $maCapacity 'MaOpenCapacityAllows').Replace('MaOpenCapacityAllows','ReferenceMaOpenCapacityAllows')+"`r`n"
foreach($kind in @('baseline','candidate')){
 if($CandidateOnly-and !$RunReplay-and $kind-eq 'baseline'){continue}
 $seen=@{}
 function StageGraph([string]$path){
  $path=[IO.Path]::GetFullPath($path)
  if(!$path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'External quoted dependency'}
  if($seen.ContainsKey($path)){return};$seen[$path]=$true
  $relative=$path.Substring($source.Length+1)
  $read=$path;$saved=Join-Path $stage ('baseline/'+$relative)
  if($kind-eq 'baseline'-and (Test-Path $saved)){$read=$saved}
  $dest=Join-Path $stage ($kind+'_build/IndicatorCodeExamples/'+$relative)
  New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
  Copy-Item -LiteralPath $read -Destination $dest -Force
  foreach($m in [regex]::Matches([IO.File]::ReadAllText($read),'(?m)^\s*#include\s+"([^"]+)"')){
   StageGraph (Join-Path (Split-Path $path) $m.Groups[1].Value)
  }
 }
 foreach($family in $entries.Keys){StageGraph (Join-Path $source ($family+'/'+$entries[$family]))}
 $files=@()
 foreach($family in $entries.Keys){$files+=Join-Path $stage ($kind+'_build/IndicatorCodeExamples/'+$family+'/'+$entries[$family])}
 if($kind-eq 'candidate'){
  $fixture=Join-Path $stage ($kind+'_build/tests/mql5/MaPositionReference.mqh')
  New-Item -ItemType Directory -Force (Split-Path $fixture)|Out-Null
  [IO.File]::WriteAllText($fixture,$reference,[Text.Encoding]::ASCII)
  foreach($family in $entries.Keys){
   $probe=$family+'PositionPolicyProbe.mq5'
   $dest=Join-Path $stage ($kind+'_build/tests/mql5/'+$probe)
   New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
   Copy-Item (Join-Path $root ('tests/mql5/'+$probe)) $dest -Force
   $files+=$dest
  }
 }
 if($RunReplay){
  foreach($family in $entries.Keys){
   $probe=$family+'PositionReplayProbe.mq5'
   $dest=Join-Path $stage ($kind+'_build/tests/mql5/'+$probe)
   New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
   Copy-Item (Join-Path $root ('tests/mql5/'+$probe)) $dest -Force
   $files+=$dest
  }
 }
 foreach($file in $files){
  $log=$file+'.log'
  if($kind-eq 'baseline'-and $file-notmatch 'PositionReplayProbe'-and (Test-Path $log)-and (Get-Content $log -Raw)-match 'Result: 0 errors, 0 warnings'){continue}
  $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
  if(!(Test-Path $log)-or (Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){
   Get-Content $log -Tail 45;throw "Compile failed: $file"
  }
  Write-Output "$kind $(Split-Path $file -Leaf): 0 errors, 0 warnings"
 }
}
if($RunProbes-or $RunReplay){
 $worker=Join-Path $root '.tmp/orb_jp225_full_worker'
 $terminal=Join-Path $worker 'terminal64.exe'
 if(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal){throw 'Isolated worker busy'}
 if($RunProbes){foreach($family in $entries.Keys){
  $name=$family+'PositionPolicyProbe'
  Copy-Item (Join-Path $stage ('candidate_build/tests/mql5/'+$name+'.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5')) -Force
  $ini=Join-Path $stage ($name+'.ini')
  @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
  $started=Get-Date
  $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw 'Probe timeout'}
  $out=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
  if(!(Test-Path $out)-or (Get-Item $out).LastWriteTime-lt $started.AddSeconds(-2)){throw 'Fresh probe result missing'}
  $result=Get-Content $out -Raw
  Copy-Item $out $stage -Force
  Write-Output $result
  if($result-notmatch '\bfailed=0\b'){throw 'Behavior probe failed'}
 }}
 if($RunReplay){foreach($family in $entries.Keys){
  $results=@()
  foreach($kind in @('baseline','candidate')){
   $name=$family+'PositionReplay_'+$kind
   Copy-Item (Join-Path $stage ($kind+'_build/tests/mql5/'+$family+'PositionReplayProbe.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5')) -Force
   $ini=Join-Path $stage ($name+'.ini')
   @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
   $started=Get-Date
   $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
   if(!$p.WaitForExit(240000)){throw 'Replay timeout'}
   $out=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
   if(!(Test-Path $out)-or (Get-Item $out).LastWriteTime-lt $started.AddSeconds(-2)){throw 'Fresh replay missing'}
   Copy-Item $out $stage -Force;$results+=Get-Content $out -Raw
   Write-Output "$name : $((Get-Content $out -TotalCount 1))"
  }
  if($results[0]-match 'total=0\b'){throw 'Empty replay is not parity evidence'}
  if($results[0]-ne $results[1]){throw "$family default replay mismatch; inspect both trade traces"}
  Write-Output "$family DEFAULT_REPLAY_PARITY=PASS"
 }}
}
if($RunProbes-and $RunReplay){
 $verified=@()
 foreach($family in $entries.Keys){
  $compiled=Join-Path $stage ('candidate_build/IndicatorCodeExamples/'+$family)
  foreach($file in Get-ChildItem -LiteralPath $compiled -File){
   if($file.Extension-eq '.mqh'-or $file.Name-eq $entries[$family]-or $file.Name-eq ($entries[$family]-replace '\.mq5$','.ex5')){
    $verified+=@{family=$family;name=$file.Name;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash}
   }
  }
 }
 @{schema=1;checkedAt=(Get-Date -Format o);behavior='PASS';defaultReplay='PASS';
   maReverseReference=(Get-FileHash -LiteralPath $maExit).Hash;
   maCapacityReference=(Get-FileHash -LiteralPath $maCapacity).Hash;files=$verified}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $stage 'verification.json') -Encoding UTF8
}
Write-Output "STAGE=$stage"
