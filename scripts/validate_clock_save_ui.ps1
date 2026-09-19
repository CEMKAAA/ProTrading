param([switch]$Install,[switch]$RunProbes)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tag=Get-Date -Format yyyyMMdd_HHmmss
$stage=Join-Path $root ('.tmp/clock_save_'+$tag)
$src=Join-Path $root 'IndicatorCodeExamples'
$names=@('OrbUltimateEA.mq5','OrbUltimateEA_Channel.mq5','OrbUltimateEA_StrategyLibrary.mq5','macrossover_orb/MaCrossOverOrbEA.mq5','LiquidityNarrative_MT5_EA.mq5','LiquidityNarrative_Invert_MT5_EA.mq5','LiqNarrativeSolVersion.mq5','LiqNarrativeSol_Advanced.mq5','LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')
$seen=@{}
function StageFile($rel){
 if($seen.ContainsKey($rel)){return};$seen[$rel]=$true
 $f=Join-Path $src $rel;$dest=Join-Path $stage $rel
 New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath $f -Destination $dest
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($f),'(?m)^\s*#include\s+"([^"]+)"')){
 $child=$m.Groups[1].Value;if(Split-Path $rel){$child=Join-Path (Split-Path $rel) $child}
 if(!(Split-Path $rel)){$child=$m.Groups[1].Value}
 StageFile $child
 }
}
foreach($n in $names){StageFile $n}
$probes=@('MaStrategySaveProbe','OrbClockSaveProbe','OrbBrokerTimezoneProbe')
if($RunProbes){
 foreach($n in $probes){
  $text=[IO.File]::ReadAllText((Join-Path $root ('tests/mql5/'+$n+'.mq5'))).Replace('../../IndicatorCodeExamples/','')
  $text=$text.Replace($n+'.json',$n+'_'+$tag+'.json')
  [IO.File]::WriteAllText((Join-Path $stage ($n+'.mq5')),$text,(New-Object Text.UTF8Encoding($false)))
  $names+=$n+'.mq5'
 }
}
$failed=@()
foreach($n in $names){
 $file=Join-Path $stage $n;$log=$file+'.log'
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 $txt=if(Test-Path $log){[IO.File]::ReadAllText($log)}else{''}
 if($txt -notmatch 'Result: 0 errors, 0 warnings'){$failed+=$n;Write-Output $txt}else{Write-Output "$n : 0 errors, 0 warnings"}
}
Write-Output "STAGE=$stage"
if($failed.Count){throw ('Compile failures: '+($failed -join ','))}
if($RunProbes){
 $worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
 if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal).Count){throw 'Isolated worker already running'}
 foreach($n in $probes){
  $unique=$n+'_'+$tag
  Copy-Item (Join-Path $stage ($n+'.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$unique+'.ex5'))
  $ini=Join-Path $stage ($n+'.ini')
  @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$unique),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
  $start=Get-Date
  $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw "Probe timeout $n"}
  $result=Join-Path $worker ('MQL5/Files/'+$unique+'.json')
  if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $start){throw "Missing fresh output $n"}
  $r=Get-Content $result -Raw|ConvertFrom-Json
  Copy-Item $result $stage
  Write-Output "$n : $($r.checks) checks, $($r.failed) failed"
  if($r.failed -ne 0){throw "Probe failed $n"}
 }
}
