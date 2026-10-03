param([switch]$Deploy)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$stage=(Get-Content (Join-Path $root '.tmp/audit_perf_stage.txt') -Raw).Trim()
$verified=Join-Path $stage 'optimized'
$entries=@{orb='OrbUltimateEA_StrategyLibrary.mq5';macrossover_orb='MaCrossOverOrbEA.mq5';entry_engine_lab='EntryEngineLabEA.mq5';SolAdvanced='LiqNarrativeSol_Advanced.mq5'}
$targets=@{orb='orb';macrossover_orb='MaCrossOverOrb';entry_engine_lab='EntryEngineLab';SolAdvanced='SolAdvanced'}
function CompareTrace([string]$stem){
 $a=[IO.File]::ReadAllLines((Join-Path $stage ('baseline/'+$stem+'.trace')))
 $b=[IO.File]::ReadAllLines((Join-Path $verified ($stem+'.trace')))
 if($a.Length-ne $b.Length){throw "Trace count mismatch: $stem"}
 for($i=0;$i-lt $a.Length;$i++){if($a[$i]-cne $b[$i]){throw "Trade trace mismatch: $stem row $($i+1)"}}
 return $a.Length
}
function Timing([string]$flavor,[string]$stem,[int]$run){
 $text=Get-Content (Join-Path $stage ($flavor+'/'+$stem+'.txt')) -Raw
 $m=[regex]::Match($text,'(?m)^run='+$run+' total_ms=(\d+).*')
 if(!$m.Success){throw "Timing missing: $flavor/$stem run $run"}
 if($m.Value-notmatch '\bDATA=0\b'){throw "Incomplete audit cannot be a performance claim: $flavor/$stem run $run"}
 return [long]$m.Groups[1].Value
}
$rows=0;$table=@()
$maProfile=Get-Content (Join-Path $verified 'Ma_XAUUSDm.txt') -Raw
$profile=[regex]::Match($maProfile,'(?m)^profile run=0 tick_ms=([0-9.]+) tick_calls=(\d+)')
if(!$profile.Success){throw 'Final MaCross profile missing'}
foreach($case in @(@('Ma_XAUUSDm','MaCross XAUUSD M1 / 20W'),@('Lab_XAUUSDm','Entry Lab builtin XAUUSD M1 / 20W'),@('Sol_USDJPYm','Sol USDJPY H1 / 20W'),@('Sol_USDJPYm_260w','Sol USDJPY H1 / 5Y'))){
 $stem=$case[0];$count=CompareTrace $stem;$rows+=$count
 foreach($run in @(0,1,2)){
  $before=Timing 'baseline' $stem $run;$after=Timing 'optimized' $stem $run
  $label=@('first audit','unchanged repeat','changed R target')[$run]
  $table+='| '+$case[1]+' / '+$label+' | '+('{0:F3}'-f ($before/1000.0))+' | '+('{0:F3}'-f ($after/1000.0))+' | '+('{0:F2}'-f ($before/[double]$after))+'x |'
 }
}
$checks=0;$checkRows=@()
foreach($family in @('Sol','Orb','Ma','Lab')){
 $text=Get-Content (Join-Path $verified ('checks_'+$family+'_USDJPYm.txt')) -Raw
 $m=[regex]::Match($text,'checks=(\d+) failed=0\b')
 if(!$m.Success){throw "Correctness checks failed: $family"}
 $checks+=[int]$m.Groups[1].Value;$checkRows+="| $family | $($m.Groups[1].Value) | 0 |"
}
$seen=@{}
function Collect([string]$file){
 $file=[IO.Path]::GetFullPath($file)
 if(!$file.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Quoted dependency escaped canonical source'}
 if($seen.ContainsKey($file)){return};$seen[$file]=$true
 $relative=$file.Substring($source.Length+1);$compiled=Join-Path $verified $relative
 if(!(Test-Path $compiled)-or (Get-FileHash $file).Hash-ne (Get-FileHash $compiled).Hash){throw "Verified source mismatch: $relative"}
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){Collect (Join-Path (Split-Path $file) $m.Groups[1].Value)}
}
foreach($family in $entries.Keys){
 $main=Join-Path $source ($family+'/'+$entries[$family]);Collect $main
 $compiled=Join-Path $verified ($family+'/'+$entries[$family])
 if((Get-Content ($compiled+'.log') -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw "Unclean production compile: $family"}
 if(!(Test-Path ([IO.Path]::ChangeExtension($compiled,'.ex5')))){throw "Missing binary: $family"}
}
$report=Join-Path $root 'reports/audit_acceleration_20261003.md'
$lines=@('# Exact Audit Acceleration / 2026-10-03','','## Measured Results','',
 'Frozen pre-change source and accelerated source were compiled separately and run in the same isolated MT5 worker. All measured runs below completed without DATA records. Network downloads are not included in the speedup claim: broker history and existing V2 day indexes were already available. The first audit means cold EA outcome caches, not a first-ever broker download. No broker orders or entry publishers were invoked.','',
 '| Workload | Before (s) | After (s) | Speedup |','| :--- | ---: | ---: | ---: |')
$lines+=$table
$lines+=@('',
 'MaCross/Entry Lab timing includes signal preparation, filtering, lifecycle execution, statistics, chart-object creation/commit and ChartRedraw. Initial Pine signal-kernel construction and tick synchronization are logged separately. Sol uses the production synchronous recalculation path including macro reference statistics and final dashboard draw. These are workload measurements, not a guarantee for every symbol, setup or broker.','',
 'The unchanged-repeat path was already cached in the old engine and need not improve by 4x. The target applies to actual recalculation workloads. The Orb shared ADV path has correctness/compile verification but no independent whole-ORB-session speed benchmark in this campaign.','',
 '## Bottleneck And Changes','',
 "- MaCross baseline spent 148.230 seconds of its 149.563-second first audit in 5292 tick reads. Final accelerated reads: $($profile.Groups[2].Value) calls / $($profile.Groups[1].Value) ms, with the same 497729 exact replay ticks examined. Rendering was not the bottleneck. An earlier accelerated run took 16.156 seconds end-to-end; the table reports the later final rerun, not the fastest observation.",
 '- Orb/MaCross/Entry Lab ADV candidate-minute reads now use exact zero-copy slices of the existing shared quote cache, with four-hour read batching and bounded extension. Failed bulk reads fall back to the original guarded exact-range reader.',
 '- Completed ADV day-index pages use a bounded 64-slot ownership-swap cache instead of repeatedly copying arrays or rereading a revisited day. Reset and mode changes clear these pages; the mutable current day is not retained.',
 '- Sol uses completed six-hour exact-quote pages, 64-tick extrema skip proofs, and minute extrema built from exact Bid/Ask quotes. A proof can only skip intervals with no possible state-changing SL/TP/HC event. Candidate intervals still use the original chronological tick loop. Exact last-quote time and price are retained for OPEN and forced exits.',
 '- Sol NAS predecessor/successor queries now use indexed chronological lookups rather than repeatedly scanning the entire prefix. Formula, direction, lookback age, wait semantics and raw-signal boundaries are preserved.',
 '- Entry Lab had an existing completed-outcome cache bug: its epoch included the engine identity, but the final consistency check omitted it. Both outcome and prepared-context checks now compare the same complete identity. The final repeated audit recorded 2122 memo hits and no tick reads; engine changes still invalidate the key.',
 '- Sol quote pages have a 64 MiB retention budget; a single oversized input may exist transiently without being retained. Completed-minute proof storage is separately capped at 32768 hours (about 120 MiB plus metadata). Capacity exhaustion disables further caching, not execution or correctness.',
 '- Completed Sol summaries are invalidated on server/symbol/tick-size changes, earlier history, non-append bar backfill, history reset and synchronization transitions. Explicit invalidation is also available internally. There is no new persistent cache format.',
 '- Signal kernels, entry/SL/TP/inversion mathematics, cost formulas, strategy schemas, CSV schemas, publishing and listeners were not changed. The legacy/default Orb/MaCross/Entry Lab engine remains the reference path; acceleration requires the existing ADV setting. Sol accelerates its existing tick-replay path.','',
 '## Correctness Evidence','',
 "$rows trade trace rows match the frozen source in original chronological order, byte for byte. These traces include fills, geometry, exit timestamps, outcomes, W/L/O/DATA status and R. No positive/negative PnL was substituted or rounded into a target result.",'',
 '| Test family | Checks | Failed |','| :--- | ---: | ---: |')
$lines+=$checkRows
$lines+=@('',
 "Total assertions: $checks. Sol tests include 72 real-market accelerated-versus-reference cases varying stop distance, HC, inversion, slippage/commission settings, fixed/reverse targets and forced horizons. NAS tests compare indexed answers with literal linear reference implementations. Quote tests cover inclusive endpoints, duplicate timestamps, empty minutes, last executable quote preservation, reset, LRU eviction and mutable current-day safety.",'',
 'All four canonical production mains compile with 0 errors and 0 warnings. Matching a reference is regression evidence, not proof that every historical assumption in the older engine is correct, nor a guarantee of live broker execution or universal 4-5x speedup. Broker tick revisions that do not expose a history/sync change require explicit invalidation or an EA reload.','',
 'Timings are observed wall-clock samples, not confidence intervals. Compilation/system contention affects elapsed time. The final MaCross repeat was slower than its frozen already-cached repeat; no improvement is claimed for that row. Five-year, all-symbol strategy campaigns, first-time tick downloads and live fills were not exhaustively tested. Entry Lab market performance here uses its inherited builtin Close/Reverse engine, not every custom builder engine.','',
 '## Reproduction','',
 'Harness: `scripts/audit_perf_campaign.ps1`. Frozen and optimized source/data/results: `'+$stage+'`. Do not rerun Prepare against modified source when comparing with this baseline.','',
 'Use Baseline or Optimized with Family Ma, Lab or Sol; Symbol XAUUSDm or USDJPYm; Weeks 20 or 260. Checks runs the corresponding family tests. Compile builds all four production mains. Correctness and performance probes do not run production OnInit or submit orders.','',
 '## Production Files','',
 '- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`',
 '- `IndicatorCodeExamples/orb/OrbAdvancedAuditEngine.mqh`',
 '- `IndicatorCodeExamples/orb/OrbAuditRamCache.mqh`',
 '- `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`',
 '- `IndicatorCodeExamples/macrossover_orb/OrbAdvancedAuditEngine.mqh`',
 '- `IndicatorCodeExamples/macrossover_orb/OrbAuditRamCache.mqh`',
 '- `IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5`',
 '- `IndicatorCodeExamples/entry_engine_lab/OrbAdvancedAuditEngine.mqh`',
 '- `IndicatorCodeExamples/entry_engine_lab/OrbAuditRamCache.mqh`',
 '- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`',
 '- `IndicatorCodeExamples/SolAdvanced/LiqAuditQuoteCache.mqh`',
 '- `IndicatorCodeExamples/SolAdvanced/LiqSolAdvancedNas.mqh`','',
 'Matching EX5 binaries and README release notes are updated alongside these canonical files. No root-level legacy EA or other listener family is deployed.','')
foreach($family in $entries.Keys){
 $binary=[IO.Path]::ChangeExtension((Join-Path $verified ($family+'/'+$entries[$family])),'.ex5')
 Copy-Item -LiteralPath $binary -Destination ([IO.Path]::ChangeExtension((Join-Path $source ($family+'/'+$entries[$family])),'.ex5')) -Force
}
if($Deploy){
 if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path-eq 'C:\MT5\DEMO\terminal64.exe'}){throw 'Close DEMO before deployment'}
 $experts='C:\MT5\DEMO\MQL5\Experts';$plan=@()
 foreach($file in $seen.Keys){
  $relative=$file.Substring($source.Length+1);$parts=$relative.Split('\');$family=$parts[0]
  if($targets.ContainsKey($family)){
   $target=Join-Path $experts ($targets[$family]+'\'+$relative.Substring($family.Length+1))
  }else{
   # Parent-relative includes must retain the directory layout used at compile.
   # Do not overwrite a different shared module used by an unrelated EA.
   if($relative-notin @('NativeMarginPreview.mqh','NativeMarginQuote.mqh','ResearchFiveYearLeaderboard.mqh')){throw "Unexpected shared deployment dependency: $relative"}
   $target=Join-Path $experts $relative
   if((Test-Path $target)-and (Get-FileHash $file).Hash-ne (Get-FileHash $target).Hash){throw "Shared deployed dependency differs: $target"}
  }
  if(![IO.Path]::GetFullPath($target).StartsWith($experts+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Deployment escaped Experts'}
  $plan+=@{Source=$file;Target=$target}
 }
 foreach($family in $entries.Keys){
  $plan+=@{Source=([IO.Path]::ChangeExtension((Join-Path $verified ($family+'/'+$entries[$family])),'.ex5'));Target=(Join-Path $experts ($targets[$family]+'/'+[IO.Path]::ChangeExtension($entries[$family],'.ex5')))}
  $plan+=@{Source=(Join-Path $source ($family+'/README.md'));Target=(Join-Path $experts ($targets[$family]+'/README.md'))}
 }
 $backup=Join-Path $root ('.tmp/audit_acceleration_backup_'+(Get-Date -Format yyyyMMdd_HHmmss));$manifest=@()
 foreach($item in $plan){
  if(Test-Path $item.Target){$saved=Join-Path $backup $item.Target.Substring($experts.Length+1);New-Item -ItemType Directory -Path (Split-Path $saved) -Force|Out-Null;Copy-Item -LiteralPath $item.Target -Destination $saved}
 }
 foreach($item in $plan){
  New-Item -ItemType Directory -Path (Split-Path $item.Target) -Force|Out-Null;Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
  $hash=(Get-FileHash $item.Source).Hash;if($hash-ne (Get-FileHash $item.Target).Hash){throw "Deployment mismatch: $($item.Target)"}
  $manifest+="$hash $($item.Target)"
 }
 $manifest|Set-Content (Join-Path $backup 'manifest.txt') -Encoding ASCII
 $lines+=@('## Deployment','',"Published $($plan.Count) files to the four canonical DEMO folders with SHA256 checks. Backup: $backup.",'')
 Write-Output "DEPLOYED=$($plan.Count) BACKUP=$backup"
}else{$lines+=@('## Deployment','','Workspace binaries updated; DEMO deployment not requested.','')}
$lines|Set-Content -LiteralPath $report -Encoding UTF8
Write-Output "REPORT=$report TRACE_ROWS=$rows CHECKS=$checks"
