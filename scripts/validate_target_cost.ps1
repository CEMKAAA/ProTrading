param([string[]]$Families=@('Ma','Lab','Orb','Sol'))
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'reports/verification_build/target_cost'
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
$editor='C:\MT5\DEMO\MetaEditor64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object Path -eq $terminal){throw 'Worker busy; nothing stopped'}
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$sources=@{Ma='macrossover_orb/MaCrossOverOrbEA.mq5';Lab='entry_engine_lab/EntryEngineLabEA.mq5';Orb='orb/OrbUltimateEA_StrategyLibrary.mq5';Sol='SolAdvanced/LiqNarrativeSol_Advanced.mq5'}
foreach($h in @('TargetCostGateChecks.mqh','OrbTargetCostChecks.mqh')){Copy-Item -LiteralPath (Join-Path $root ('tests/mql5/'+$h)) -Destination $stage}
foreach($family in $Families){
 $name=$family+'TargetCostProbe';$relative='IndicatorCodeExamples/'+$sources[$family]
 $source=(Join-Path $root $relative).Replace('\','/')
 $before=(& git -C $root show ('HEAD:'+$relative)) -join "`n"
 $function=if($family-eq'Sol'){'SimulateSignal'}else{'SimulateTrade'}
 $match=[regex]::Match($before,'(?s)(?:double|HistResult) '+$function+'\(.*?\n\}\r?\n')
 if(!$match.Success){throw "Baseline function not found: $family"}
 [IO.File]::WriteAllText((Join-Path $stage ($family+'Before.mqh')),$match.Value.Replace($function+'(','Before'+$function+'('),(New-Object Text.UTF8Encoding($false)))
 if($family-eq'Sol'){
  $text=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/SolTargetCostProbe.mq5')).Replace('../../'+$relative,$source)
 }else{
  $text=@"
#property strict
long ProbeChartSize(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub=0)
{if(prop==CHART_WIDTH_IN_PIXELS)return 1600;if(prop==CHART_HEIGHT_IN_PIXELS)return 950;return ChartGetInteger(chart,prop,sub);}
bool ProbeChartSize(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub,long &value)
{value=ProbeChartSize(chart,prop,sub);return true;}
#define ChartGetInteger ProbeChartSize
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "$source"
#include "${family}Before.mqh"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef ChartGetInteger
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("TARGET COST FAIL: ",label);}}
#define PROBE_IMAGE "$name.png"
#include "TargetCostGateChecks.mqh"
#include "OrbTargetCostChecks.mqh"
void OnStart(){CheckOrbTargetCost();int f=FileOpen("$name.json",FILE_WRITE|FILE_TXT|FILE_ANSI);if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}}
"@
 }
 $path=Join-Path $stage ($name+'.mq5');[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
 $log=$path+'.log';$p=Start-Process $editor -ArgumentList ('/compile:"'+$path+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw "Compile timeout: $name"}
 if([IO.File]::ReadAllText($log)-notmatch'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw "Compile failed: $name"}
 Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($path,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $stage ($name+'.ini');@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=GBPUSDm','Period=M5','ShutdownTerminal=1')|Set-Content -LiteralPath $ini -Encoding ASCII
 $started=Get-Date;$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(240000)){throw "Probe timeout: $name; worker left running"}
 $result=Join-Path $worker ('MQL5/Files/'+$name+'.json')
 if(!(Test-Path $result)-or(Get-Item $result).LastWriteTime-lt$started.AddSeconds(-2)){throw "Fresh result missing: $name"}
 Copy-Item -LiteralPath $result -Destination $stage;$r=Get-Content $result -Raw|ConvertFrom-Json
 Copy-Item -LiteralPath (Join-Path $worker ('MQL5/Files/'+$name+'.png')) -Destination $stage -ErrorAction SilentlyContinue
 Write-Output "$name : $($r.checks) checks, $($r.failed) failures"
 if($r.failed-ne0){throw "Probe failed: $name"}
}
