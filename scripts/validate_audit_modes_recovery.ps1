param([ValidateSet('Parity','Recovery','Pipeline')][string]$Mode='Parity',
      [ValidateSet('Orb','Ma','Lab','Sol')][string]$Family='Ma',[string]$Symbol='BTCUSDm')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$stage=Join-Path $root ('.tmp/audit_modes_recovery_'+(Get-Date -Format yyyyMMdd_HHmmss)+'_'+$Family+'_'+$Mode)
$entries=@{Orb='orb/OrbUltimateEA_StrategyLibrary.mq5';Ma='macrossover_orb/MaCrossOverOrbEA.mq5';Lab='entry_engine_lab/EntryEngineLabEA.mq5';Sol='SolAdvanced/LiqNarrativeSol_Advanced.mq5'}
$seen=@{}
function StageFile([string]$file){
 $file=[IO.Path]::GetFullPath($file)
 if(!$file.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Dependency escaped source'}
 if($seen.ContainsKey($file)){return};$seen[$file]=$true
 $out=Join-Path $stage $file.Substring($source.Length+1)
 New-Item -ItemType Directory -Path (Split-Path $out) -Force|Out-Null
 Copy-Item -LiteralPath $file -Destination $out
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){StageFile (Join-Path (Split-Path $file) $m.Groups[1].Value)}
}
StageFile (Join-Path $source $entries[$Family])
$folder=Split-Path (Join-Path $stage $entries[$Family])
$name='ModeRecovery_'+[Guid]::NewGuid().ToString('N').Substring(0,10)
$main=Split-Path $entries[$Family] -Leaf
if($Mode-eq 'Pipeline'){
 if($Family-notin @('Ma','Lab')){throw 'Pipeline fixture is Ma/Lab-specific'}
 $text=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/AuditPerfMaProbe.mq5'))
 $text=$text.Replace('run<3','run<4').Replace('if(run==2)g_rtTargetLeg=ORB_TARGET_R050;','g_rtAdvancedAuditEngine=(run%2)==1;if(run==2)g_rtTargetLeg=ORB_TARGET_R050;')
 $text=$text.Replace('__WEEKS__','2')
}else{
 $template=if($Mode-eq 'Recovery'){'NativePositionRecoveryProbe.mq5'}else{'AuditNormalAdvParityProbe.mq5'}
 if($Family-eq 'Sol' -and $Mode-eq 'Parity'){throw 'Sol has one audit mode; use the existing accelerated/reference checks'}
 $text=[IO.File]::ReadAllText((Join-Path $root ('tests/mql5/'+$template)))
 if($Family-eq 'Sol'){$text="#define RECOVERY_SOL`n"+$text}
 if($Family-eq 'Orb'){$text="#define RECOVERY_ORB`n"+$text}
}
$text=$text.Replace('__MAIN__',$main).Replace('__NAME__',$name)
$probe=Join-Path $folder ($name+'.mq5')
[IO.File]::WriteAllText($probe,$text,(New-Object Text.UTF8Encoding($false)))
$log=$probe+'.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$probe+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 35;throw 'Compile failed'}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path-eq $terminal}){throw 'Isolated worker busy'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
$ini=Join-Path $stage 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),('Symbol='+$Symbol),'Period=M1','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(600000)){throw 'Probe timeout (worker retained for diagnosis)'}
$result=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
if(!(Test-Path $result)){throw 'Probe report missing'}
Copy-Item -LiteralPath $result -Destination (Join-Path $stage 'result.txt')
Get-Content $result
if($Mode-eq 'Pipeline'){
 $trace=Join-Path $worker ('MQL5/Files/'+$name+'.trace')
 Copy-Item -LiteralPath $trace -Destination (Join-Path $stage 'result.trace')
 $lines=Get-Content $trace
 for($run=0;$run-lt 4;$run+=2){
  $a=@($lines|Where-Object {$_ -like "$run|*"}|ForEach-Object {$_.Substring($_.IndexOf('|')+1)})
  $b=@($lines|Where-Object {$_ -like "$($run+1)|*"}|ForEach-Object {$_.Substring($_.IndexOf('|')+1)})
  if(!$a.Count -or $a.Count-ne $b.Count){throw 'Pipeline count mismatch'}
  for($i=0;$i-lt $a.Count;$i++){if($a[$i]-cne $b[$i]){throw "Pipeline trace mismatch run=$run row=$i"}}
  Write-Output "PIPELINE_EXACT_MATCH pair=$run/$($run+1) rows=$($a.Count)"
 }
 if((Get-Content $result -Raw)-notmatch 'DATA=0' -or (Get-Content $result -Raw)-match 'DATA=[1-9]'){throw 'Pipeline DATA unavailable'}
}elseif((Get-Content $result -Raw)-notmatch '\bfailed=0\b'){throw 'Validation failed'}
Write-Output "STAGE=$stage"
