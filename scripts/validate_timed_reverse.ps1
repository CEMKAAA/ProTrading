param([switch]$Baseline,[string[]]$Families=@('Ma','Lab','Sol'))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'reports/verification_build/timed_reverse'
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
$editor='C:\MT5\DEMO\MetaEditor64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object Path -eq $terminal){throw 'Research worker busy; nothing stopped'}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$sources=@{Ma='macrossover_orb/MaCrossOverOrbEA.mq5';Lab='entry_engine_lab/EntryEngineLabEA.mq5';Sol='SolAdvanced/LiqNarrativeSol_Advanced.mq5'}
Copy-Item -LiteralPath (Join-Path $root 'tests/mql5/MaTimedReverseProbe.mqh') -Destination $stage
foreach($family in $Families){
 $name=$family+'TimedReverseProbe'
 $path=Join-Path $stage ($name+'.mq5')
 $text=[IO.File]::ReadAllText((Join-Path $root ('tests/mql5/'+$name+'.mq5')))
 $source=Join-Path $root ('IndicatorCodeExamples/'+$sources[$family])
 $text=$text.Replace('../../IndicatorCodeExamples/'+$sources[$family],$source.Replace('\','/'))
 if($Baseline){
  $original=[IO.File]::ReadAllText($source)
  $function=if($family-eq'Sol'){'SimulateSignal'}else{'SimulateTrade'}
  $match=[regex]::Match($original,'(?s)(?:double|HistResult) '+$function+'\(.*?\n\}\r?\n')
  if(!$match.Success){throw "Baseline function not found: $family"}
  [IO.File]::WriteAllText((Join-Path $stage ($family+'Before.mqh')),$match.Value.Replace($function+'(', 'Before'+$function+'('),(New-Object Text.UTF8Encoding($false)))
 } else {
  $text=$text.Replace('#undef OnInit',('#include "'+$family+'Before.mqh"'+"`n#undef OnInit"))
  $text="#define PROBE_PARITY`n"+$text
 }
 [IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
 $log=$path+'.log';$started=Get-Date
 $p=Start-Process $editor -ArgumentList ('/compile:"'+$path+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw "Compile timeout: $name"}
 if(!(Test-Path $log)-or(Get-Item $log).LastWriteTime-lt$started-or[IO.File]::ReadAllText($log)-notmatch'Result: 0 errors, 0 warnings')
 {Get-Content $log -Tail 20;throw "Compile failed: $name"}
 Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($path,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $stage ($name+'.ini')
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=GBPUSDm','Period=M5','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
 $started=Get-Date
 $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw "Probe timeout: $name (worker left running)"}
 $result=Join-Path $worker ('MQL5/Files/'+$name+'.json')
 if(!(Test-Path $result)-or(Get-Item $result).LastWriteTime-lt$started.AddSeconds(-2)){throw "Fresh result missing: $name"}
 $suffix=if($Baseline){'before'}else{'after'}
 Copy-Item -LiteralPath $result -Destination (Join-Path $stage ($name+'.'+$suffix+'.json'))
 $r=Get-Content $result -Raw|ConvertFrom-Json
 Write-Output "$name : $($r.checks) checks, $($r.failed) failures"
 if(!$Baseline-and$r.failed-ne0){throw "Probe failed: $name"}
}
