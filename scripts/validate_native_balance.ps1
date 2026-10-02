param([switch]$CompileOnly,[switch]$RunPrepared,[switch]$RecompileProbes,[string]$Symbol='USDJPYm',[string]$PreparedStage='',[switch]$PipOnly,[string]$ProbeFamily='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$pointer=Join-Path $root '.tmp/native_balance_stage.txt'
$entries=@{orb='OrbUltimateEA_StrategyLibrary.mq5';macrossover_orb='MaCrossOverOrbEA.mq5';entry_engine_lab='EntryEngineLabEA.mq5';SolAdvanced='LiqNarrativeSol_Advanced.mq5'}
if(!$RunPrepared){
 if($PreparedStage){
  $stage=[IO.Path]::GetFullPath($PreparedStage)
  if(!$stage.StartsWith([IO.Path]::GetFullPath((Join-Path $root '.tmp'))+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Prepared stage escaped workspace'}
 }else{$stage=Join-Path $root ('.tmp/native_balance_'+(Get-Date -Format yyyyMMdd_HHmmss));New-Item -ItemType Directory -Path $stage -Force|Out-Null}
 $seen=@{}
 function StageFile([string]$file){
  $file=[IO.Path]::GetFullPath($file)
  if(!$file.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Dependency escaped source'}
  if($seen.ContainsKey($file)){return};$seen[$file]=$true
  $relative=$file.Substring($source.Length+1);$out=Join-Path $stage $relative
  if($PreparedStage){
   if(!(Test-Path $out)-or (Get-FileHash $file).Hash-ne (Get-FileHash $out).Hash){throw "Prepared source changed: $relative"}
  }else{New-Item -ItemType Directory -Path (Split-Path $out) -Force|Out-Null;Copy-Item -LiteralPath $file -Destination $out}
  foreach($m in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){StageFile (Join-Path (Split-Path $file) $m.Groups[1].Value)}
 }
 foreach($family in $entries.Keys){StageFile (Join-Path $source ($family+'/'+$entries[$family]))}
 function Compile([string]$file){
  $log=$file+'.log';$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
  if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 20;throw "Compile failed $file"}
  Write-Output "COMPILED=$file 0 errors, 0 warnings"
 }
 foreach($family in $entries.Keys){
  $main=Join-Path $stage ($family+'/'+$entries[$family])
  if($PreparedStage){if((Get-Content ($main+'.log') -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Prepared production compile not clean'}}
  else{Compile $main}
 }
 foreach($family in $entries.Keys){
  $name='NbProbe_'+$family+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8)
  $folder=Join-Path $stage $family;Copy-Item (Join-Path $root 'tests/mql5/NativeBalanceChecks.mqh') $folder
  Copy-Item (Join-Path $root 'tests/mql5/NativeMarginChecks.mqh') $folder
  Copy-Item (Join-Path $root 'tests/mql5/PipCeilingChecks.mqh') $folder
  $text=@'
#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent BalanceChartEvent
#define OnTradeTransaction UnusedTransaction
// UI viewport fixture for the hidden worker. Market data/APIs are unchanged.
long NmViewport(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub=0)
{if(prop==CHART_WIDTH_IN_PIXELS)return 1600;if(prop==CHART_HEIGHT_IN_PIXELS)return 900;return ChartGetInteger(chart,prop,sub);}
bool NmViewport(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub,long &value)
{value=NmViewport(chart,prop,sub);return true;}
#define ChartGetInteger NmViewport
#include "__MAIN__"
#include "NativeBalanceChecks.mqh"
#include "NativeMarginChecks.mqh"
#include "PipCeilingChecks.mqh"
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   NbChecks();
__CHECKS__
   GlobalVariableDel(g_nativeRiskBalanceKey);EventKillTimer();
   int report=FileOpen("__NAME__.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(report!=INVALID_HANDLE){FileWriteString(report,"checks="+(string)nbChecks+" failed="+(string)nbFailed+"\n");FileClose(report);}
}
'@
  if($family-eq 'SolAdvanced'){
   $checks=@'
   g_riskPerTradePct=1.0;g_ftmoMode=false;g_nativeRiskBalance=0;
   double baseline=ApproxMoneyFromR(2);
   g_nativeRiskBalance=30;NbCheck(MathAbs(ApproxMoneyFromR(2)-2*NativeBalanceBudget(1))<1e-10,"Sol audit money reference");
   NbCheck(RiskEnabled(),"reference enables risk sizing");g_nativeRiskBalance=0;
   NbCheck(ApproxMoneyFromR(2)==baseline,"default money parity");
   g_liqLibraryPanel=true;g_liqLibraryOpen=false;g_liqLibraryRPicker=false;g_liqLibraryOpenedAt=0;
   LiqLibraryDraw();string edit=LiqLibraryObject("BAL_VALUE"),button=LiqLibraryObject("BAL_APPLY");
   NbCheck(ObjectFind(0,edit)>=0&&ObjectFind(0,button)>=0,"balance UI visible");
   ObjectSetString(0,edit,OBJPROP_TEXT,"30");LiqLibraryDraw();
   NbCheck(ObjectGetString(0,edit,OBJPROP_TEXT)=="30"&&g_nativeRiskBalance==0,"draft not reset or applied");
   long x=ObjectGetInteger(0,button,OBJPROP_XDISTANCE)+4;double y=(double)ObjectGetInteger(0,button,OBJPROP_YDISTANCE)+4;
   BalanceChartEvent(CHARTEVENT_CLICK,x,y,"");NbCheck(g_nativeRiskBalance==30,"actual Sol raw-click apply route");
   NmChecks();PcChecks();ChartScreenShot(0,"__NAME__.png",1600,900);
'@
  }else{
   $extra=if($family-eq 'orb'){'g_orbMoneyRisk=false;double bridge=BridgeRiskBudgetMoney();'}else{'double bridge=AccountRiskBudgetMoney();'}
   $bridgeFn=if($family-eq 'orb'){'BridgeRiskBudgetMoney()'}else{'AccountRiskBudgetMoney()'}
   $checks=@'
   g_rtRiskPerTradePct=1.0;g_nativeRiskBalance=0;
__EXTRA__
   double baseline=RiskBudgetMoney(),baselineMoney=SimMoneyPnl(2);
   NbCheck(baseline==AccountRiskBudgetMoney(),"default budget parity");
   g_nativeRiskBalance=30;
   NbCheck(MathAbs(RiskBudgetMoney()-NativeBalanceBudget(1))<1e-10,"native reference budget");
   NbCheck(MathAbs(SimMoneyPnl(2)-2*RiskBudgetMoney())<1e-10,"audit reference money");
   NbCheck(__BRIDGE__==bridge,"listener budget unchanged");NbCheck(RiskEnabled(),"reference enables risk sizing");
   g_nativeRiskBalance=0;NbCheck(SimMoneyPnl(2)==baselineMoney,"default audit money parity");
   OrbLibraryRefreshLayout();RenderNativeBalance();
   string edit=PREFIX+"EDIT_NATIVE_BALANCE",button=PREFIX+"BTN_NATIVE_BALANCE";
   NbCheck(ObjectFind(0,edit)>=0&&ObjectFind(0,button)>=0,"balance UI visible");
   ObjectSetString(0,edit,OBJPROP_TEXT,"30");RenderNativeBalance();
   NbCheck(ObjectGetString(0,edit,OBJPROP_TEXT)=="30"&&g_nativeRiskBalance==0,"draft not reset or applied");
   long x=ObjectGetInteger(0,button,OBJPROP_XDISTANCE)+4;double y=(double)ObjectGetInteger(0,button,OBJPROP_YDISTANCE)+4;
   BalanceChartEvent(CHARTEVENT_OBJECT_CLICK,x,y,button);
   NbCheck(g_nativeRiskBalance==30,"actual main click apply route");
   NmChecks();PcChecks();ChartScreenShot(0,"__NAME__.png",1600,900);
'@
   $checks=$checks.Replace('__EXTRA__',$extra).Replace('__BRIDGE__',$bridgeFn)
  }
  if($PipOnly){$checks=$checks.Replace('NmChecks();PcChecks();','DrawDashboard();PcChecks();')}
  if($family-eq 'SolAdvanced'){$text="#define NM_SOL`n"+$text}
  if($family-eq 'entry_engine_lab'){$text="#define NM_LAB`n"+$text}
  $text=$text.Replace('__MAIN__',$entries[$family]).Replace('__CHECKS__',$checks).Replace('__NAME__',$name)
  $probe=Join-Path $folder ($name+'.mq5');[IO.File]::WriteAllText($probe,$text,(New-Object Text.UTF8Encoding($false)));Compile $probe
  $name|Set-Content (Join-Path $stage ($family+'.name')) -Encoding ASCII
 }
 $stage|Set-Content $pointer -Encoding ASCII
 if($CompileOnly){Write-Output "PREPARED=$stage";exit}
}else{
 $stage=(Get-Content $pointer -Raw).Trim()
 if($RecompileProbes){
  foreach($family in $entries.Keys){
   if($ProbeFamily-and $family-ne $ProbeFamily){continue}
   $name=(Get-Content (Join-Path $stage ($family+'.name')) -Raw).Trim()
   Copy-Item (Join-Path $root 'tests/mql5/NativeMarginChecks.mqh') (Join-Path $stage $family) -Force
   Copy-Item (Join-Path $root 'tests/mql5/PipCeilingChecks.mqh') (Join-Path $stage $family) -Force
   $probe=Join-Path $stage ($family+'/'+$name+'.mq5');$log=$probe+'.log'
   $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$probe+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
   if(!$p.WaitForExit(180000)){throw 'Probe compile timeout'}
   if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw "Probe compile failed $family"}
   Write-Output "RECOMPILED_PROBE=$family 0 errors, 0 warnings"
  }
 }
}
'pending'|Set-Content (Join-Path $stage 'balance_verified.txt')
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path-eq $terminal}){throw 'Worker busy'}
foreach($family in $entries.Keys){
 $name=(Get-Content (Join-Path $stage ($family+'.name')) -Raw).Trim()
 Copy-Item (Join-Path $stage ($family+'/'+$name+'.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $stage ($family+'.ini');@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),('Symbol='+$Symbol),'Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
 $started=Get-Date;$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Probe timeout'}
 $report=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
 if(!(Test-Path $report)-or (Get-Item $report).LastWriteTime-lt $started.AddSeconds(-2)){throw 'Fresh report missing'}
 $result=Get-Content $report -Raw;Write-Output "$family $result"
 if($result-notmatch '\bfailed=0\b'){throw 'Balance checks failed'}
 Copy-Item $report $stage;Copy-Item (Join-Path $worker ('MQL5/Files/'+$name+'.png')) $stage
 Copy-Item $report (Join-Path $stage ($name+'.'+$Symbol+'.txt'))
}
$scope=if($PipOnly){'pip (broker-dependent margin checks excluded)'}else{'balance margin pip'}
"failed=0 families=4 scope=$scope"|Set-Content (Join-Path $stage 'balance_verified.txt')
Write-Output "VERIFIED=$stage"
