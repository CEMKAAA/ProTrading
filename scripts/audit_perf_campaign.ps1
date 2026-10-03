param([ValidateSet('Prepare','Baseline','Optimized','Checks','Compile')][string]$Mode='Prepare',[string]$Symbol='EURUSDm',[ValidateSet('Ma','Sol','Orb','Lab')][string]$Family='Ma',[ValidateSet(2,5,10,20,52,104,156,208,260)][int]$Weeks=20,[ValidateSet('','orb','macrossover_orb','entry_engine_lab','SolAdvanced')][string]$CompileFolder='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$pointer=Join-Path $root '.tmp/audit_perf_stage.txt'
$entries=@{orb='OrbUltimateEA_StrategyLibrary.mq5';macrossover_orb='MaCrossOverOrbEA.mq5';entry_engine_lab='EntryEngineLabEA.mq5';SolAdvanced='LiqNarrativeSol_Advanced.mq5'}
if($Mode-eq 'Prepare'){
 $stage=Join-Path $root ('.tmp/audit_perf_'+(Get-Date -Format yyyyMMdd_HHmmss))
 New-Item -ItemType Directory -Path $stage -Force|Out-Null
 Set-Content -LiteralPath $pointer -Value $stage
}else{$stage=(Get-Content -LiteralPath $pointer -Raw).Trim()}
$flavor=if($Mode-in @('Optimized','Checks','Compile')){'optimized'}else{'baseline'}
$dest=Join-Path $stage $flavor
$source=Join-Path $root 'IndicatorCodeExamples';$seen=@{}
function StageFile([string]$file){
 $file=[IO.Path]::GetFullPath($file)
 if(!$file.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Dependency escaped source'}
 if($seen.ContainsKey($file)){return};$seen[$file]=$true
 $out=Join-Path $dest $file.Substring($source.Length+1)
 New-Item -ItemType Directory -Path (Split-Path $out) -Force|Out-Null
 Copy-Item -LiteralPath $file -Destination $out
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){StageFile (Join-Path (Split-Path $file) $m.Groups[1].Value)}
}
if($Mode-ne 'Baseline'){foreach($eaFolder in $entries.Keys){StageFile (Join-Path $source ($eaFolder+'/'+$entries[$eaFolder]))}}
if($Mode-eq 'Prepare'){Write-Output "STAGE=$stage";exit}
if($Mode-eq 'Compile'){
 foreach($eaFolder in $entries.Keys){
  if($CompileFolder -and $eaFolder-ne $CompileFolder){continue}
  $file=Join-Path $dest ($eaFolder+'/'+$entries[$eaFolder]);$log=$file+'.log'
  $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
  if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 20;throw "Compile failed $eaFolder"}
  Write-Output "$eaFolder 0 errors, 0 warnings"
 }
 exit
}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path-eq $terminal}){throw 'Isolated worker busy'}
$name='AuditPerf_'+$flavor+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$folder=@{Ma='macrossover_orb';Sol='SolAdvanced';Orb='orb';Lab='entry_engine_lab'}[$Family]
$probe=Join-Path $dest ($folder+'/'+$name+'.mq5')
$template=if($Mode-eq 'Checks'){
 if($Family-eq 'Sol'){'AuditAccelerationSolChecks.mq5'}else{'AuditAccelerationAdvChecks.mq5'}
}else{
 if($Family-eq 'Orb'){throw 'Use the ADV checks for Orb; the Ma source-event benchmark is not an ORB session benchmark'}
 if($Family-eq 'Lab'){'AuditPerfMaProbe.mq5'}else{'AuditPerf'+$Family+'Probe.mq5'}
}
$text=[IO.File]::ReadAllText((Join-Path $root ('tests/mql5/'+$template))).Replace('__MAIN__',$entries[$folder]).Replace('__NAME__',$name).Replace('__WEEKS__',[string]$Weeks)
[IO.File]::WriteAllText($probe,$text,(New-Object Text.UTF8Encoding($false)))
$log=$probe+'.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$probe+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 35;throw 'Compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
$ini=Join-Path $dest ($name+'.ini')
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),('Symbol='+$Symbol),'Period=M1','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(900000)){throw 'Probe timeout (worker retained for diagnosis)'}
$extensions=if($Mode-eq 'Checks'){@('txt')}else{@('txt','trace')}
$stem=if($Mode-eq 'Checks'){'checks_'+$Family+'_'+$Symbol}else{$Family+'_'+$Symbol}
if($Mode-ne 'Checks' -and $Weeks-ne 20){$stem+='_'+$Weeks+'w'}
foreach($extension in $extensions){
 $out=Join-Path $worker ('MQL5/Files/'+$name+'.'+$extension)
 if(!(Test-Path $out)){throw "Result missing $out"}
 Copy-Item -LiteralPath $out -Destination (Join-Path $dest ($stem+'.'+$extension))
}
Get-Content (Join-Path $dest ($stem+'.txt'))
if($Mode-eq 'Checks' -and ((Get-Content (Join-Path $dest ($stem+'.txt')) -Raw) -notmatch 'failed=0')){throw 'Acceleration proof checks failed'}
Write-Output "STAGE=$stage"
