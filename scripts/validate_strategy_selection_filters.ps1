param([string]$Editor='C:\MT5\DEMO\MetaEditor64.exe',[switch]$CompileProduction)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'reports/verification_build/strategy_selection'
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object Path -eq $terminal){throw 'Existing isolated worker is busy; nothing was stopped'}
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$families=@(
 @{Name='orb';Define='SELECTION_ORB';Source='orb/OrbUltimateEA_StrategyLibrary.mq5'},
 @{Name='macross';Define='SELECTION_MA';Source='macrossover_orb/MaCrossOverOrbEA.mq5'},
 @{Name='sol';Define='SELECTION_SOL';Source='SolAdvanced/LiqNarrativeSol_Advanced.mq5'},
 @{Name='entrylab';Define='SELECTION_LAB';Source='entry_engine_lab/EntryEngineLabEA.mq5'}
)
function Compile([string]$file,[string]$log){
 $started=Get-Date
 $p=Start-Process $Editor -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $started){throw 'Fresh compile log missing'}
 $result=Get-Content $log -Tail 1
 if($result -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 30;throw 'Compile failed'}
 Write-Output $result
}
$results=@()
foreach($family in $families){
 $source=Join-Path $root ('IndicatorCodeExamples/'+$family.Source)
 if($CompileProduction){Compile $source (Join-Path $stage ($family.Name+'_production.log'))}
 $name='StrategySelection_'+$family.Name
 $probe=Join-Path $stage ($name+'.mq5')
 $prefix=@('#property strict',('#define '+$family.Define),('#define SELECTION_NAME "'+$family.Name+'"'))
 foreach($event in @('OnInit','OnDeinit','OnTick','OnTimer','OnChartEvent','OnTradeTransaction')){$prefix+='#define '+$event+' SelectionUnused'+$event}
 $text=($prefix -join "`n")+"`n#include "+'"../../../IndicatorCodeExamples/'+$family.Source+'"'+"`n"
 foreach($event in @('OnInit','OnDeinit','OnTick','OnTimer','OnChartEvent','OnTradeTransaction')){$text+='#undef '+$event+"`n"}
 $text+='#include "../../../tests/mql5/StrategySelectionFilterChecks.mqh"'+"`n"
 [IO.File]::WriteAllText($probe,$text,(New-Object Text.UTF8Encoding($false)))
 Compile $probe (Join-Path $stage ($name+'.log'))
 Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5')) -Force
 $ini=Join-Path $stage ($name+'.ini')
 @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
 $started=Get-Date
 $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Probe timeout; the existing worker was not forcibly stopped'}
 $report=Join-Path $worker ('MQL5/Files/'+$name+'.json')
 if(!(Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh probe result missing'}
 $data=Get-Content $report -Raw|ConvertFrom-Json
 $results+=[pscustomobject]@{family=$family.Name;checks=$data.checks;failed=$data.failed}
 Write-Output ($family.Name+': '+$data.checks+' checks, '+$data.failed+' failures')
 if($data.failed -ne 0){$results|ConvertTo-Json|Set-Content (Join-Path $stage 'results.json');throw 'Filter checks failed'}
}
$results|ConvertTo-Json|Set-Content (Join-Path $stage 'results.json')
$image=Join-Path $worker 'MQL5/Files/StrategySelectionSol.png'
if(Test-Path $image){Copy-Item -LiteralPath $image -Destination (Join-Path $stage 'StrategySelectionSol.png') -Force}
