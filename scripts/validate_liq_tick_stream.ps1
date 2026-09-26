param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$stage=Join-Path $root ('.tmp/sol_tick_stream_'+(Get-Date -Format yyyyMMdd_HHmmss))
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq (Join-Path $worker 'terminal64.exe')}){throw 'Isolated worker is already running'}
function StageSource([string]$absolute,[string]$part,[hashtable]$seen){
 $absolute=[IO.Path]::GetFullPath($absolute)
 if(!$absolute.StartsWith($src+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw "External include: $absolute"}
 if($seen.ContainsKey($absolute)){return}
 $seen[$absolute]=$true
 $dest=Join-Path $part ('IndicatorCodeExamples/'+$absolute.Substring($src.Length+1))
 New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath $absolute -Destination $dest
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($absolute),'(?m)^\s*#include\s+"([^"]+)"')){
  StageSource (Join-Path (Split-Path $absolute) $m.Groups[1].Value) $part $seen
 }
}
$results=@()
foreach($kind in @('candidate','baseline')){
 $part=Join-Path $stage $kind
 StageSource (Join-Path $src 'SolAdvanced/LiqNarrativeSol_Advanced.mq5') $part @{}
 if($kind -eq 'baseline'){
  Copy-Item -LiteralPath (Join-Path $root '.tmp/sol_adv_tick_before/LiqNarrativeSol_Advanced.mq5') -Destination (Join-Path $part 'IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5') -Force
 }
 $file=Join-Path $part 'tests/mql5/LiqSolAdvancedTickStreamProbe.mq5'
 New-Item -ItemType Directory -Force (Split-Path $file)|Out-Null
 Copy-Item -LiteralPath (Join-Path $root 'tests/mql5/LiqSolAdvancedTickStreamProbe.mq5') -Destination $file
 $log=$file+'.log'
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 if([IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){throw "Compile failure: $log"}
 $name='SolTick_'+$kind+'_'+(Get-Date -Format HHmmss)
 Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($file,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $part 'probe.ini'
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
 $p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit($TimeoutSeconds*1000)){
  if($p.Path -eq (Join-Path $worker 'terminal64.exe')){Stop-Process -Id $p.Id}
  throw "$kind probe timeout; stage=$stage"
 }
 $csv=Join-Path $worker ('MQL5/Files/'+$name+'.csv')
 if(!(Test-Path $csv)){throw "Probe missing: $csv"}
 Copy-Item -LiteralPath $csv -Destination (Join-Path $part 'outcomes.csv')
 $results+=@{Kind=$kind;Hash=(Get-FileHash $csv).Hash}
 Get-Content (Join-Path $worker ('MQL5/Logs/'+(Get-Date -Format yyyyMMdd)+'.log')) | Where-Object {$_ -match [regex]::Escape($name) -and $_ -match 'TICK_STREAM_PERF'} | Write-Output
}
if($results[0].Hash -ne $results[1].Hash){throw "Tick trace mismatch; stage=$stage"}
Write-Output "TICK_TRACE_PARITY=PASS STAGE=$stage"
