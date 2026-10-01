param([switch]$CompileOnly,[switch]$RunPrepared)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$pointer=Join-Path $root '.tmp/native_balance_stage.txt'
$entries=@{orb='OrbUltimateEA_StrategyLibrary.mq5';macrossover_orb='MaCrossOverOrbEA.mq5';entry_engine_lab='EntryEngineLabEA.mq5';SolAdvanced='LiqNarrativeSol_Advanced.mq5'}
if(!$RunPrepared){
 $stage=Join-Path $root ('.tmp/native_balance_'+(Get-Date -Format yyyyMMdd_HHmmss));New-Item -ItemType Directory -Path $stage -Force|Out-Null
 $seen=@{}
 function StageFile([string]$file){
  $file=[IO.Path]::GetFullPath($file)
  if(!$file.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Dependency escaped source'}
  if($seen.ContainsKey($file)){return};$seen[$file]=$true
  $relative=$file.Substring($source.Length+1);$out=Join-Path $stage $relative
  New-Item -ItemType Directory -Path (Split-Path $out) -Force|Out-Null;Copy-Item -LiteralPath $file -Destination $out
  foreach($m in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){StageFile (Join-Path (Split-Path $file) $m.Groups[1].Value)}
 }
 foreach($family in $entries.Keys){StageFile (Join-Path $source ($family+'/'+$entries[$family]))}
 function Compile([string]$file){
  $log=$file+'.log';$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
  if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 20;throw "Compile failed $file"}
  Write-Output "COMPILED=$file 0 errors, 0 warnings"
 }
 foreach($family in $entries.Keys){Compile (Join-Path $stage ($family+'/'+$entries[$family]))}
 foreach($family in $entries.Keys){
  $name='NbProbe_'+$family+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8)
  $folder=Join-Path $stage $family;Copy-Item (Join-Path $root 'tests/mql5/NativeBalanceChecks.mqh') $folder
  $text=@'
#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent BalanceChartEvent
#define OnTradeTransaction UnusedTransaction
#include "__MAIN__"
#include "NativeBalanceChecks.mqh"
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
   ChartScreenShot(0,"__NAME__.png",1600,900);
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
   ChartScreenShot(0,"__NAME__.png",1600,900);
'@
   $checks=$checks.Replace('__EXTRA__',$extra).Replace('__BRIDGE__',$bridgeFn)
  }
  $text=$text.Replace('__MAIN__',$entries[$family]).Replace('__CHECKS__',$checks).Replace('__NAME__',$name)
  $probe=Join-Path $folder ($name+'.mq5');[IO.File]::WriteAllText($probe,$text,(New-Object Text.UTF8Encoding($false)));Compile $probe
  $name|Set-Content (Join-Path $stage ($family+'.name')) -Encoding ASCII
 }
 $stage|Set-Content $pointer -Encoding ASCII
 if($CompileOnly){Write-Output "PREPARED=$stage";exit}
}else{$stage=(Get-Content $pointer -Raw).Trim()}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path-eq $terminal}){throw 'Worker busy'}
foreach($family in $entries.Keys){
 $name=(Get-Content (Join-Path $stage ($family+'.name')) -Raw).Trim()
 Copy-Item (Join-Path $stage ($family+'/'+$name+'.ex5')) (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
 $ini=Join-Path $stage ($family+'.ini');@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=USDJPYm','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
 $started=Get-Date;$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Probe timeout'}
 $report=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
 if(!(Test-Path $report)-or (Get-Item $report).LastWriteTime-lt $started.AddSeconds(-2)){throw 'Fresh report missing'}
 $result=Get-Content $report -Raw;Write-Output "$family $result"
 if($result-notmatch '\bfailed=0\b'){throw 'Balance checks failed'}
 Copy-Item $report $stage;Copy-Item (Join-Path $worker ('MQL5/Files/'+$name+'.png')) $stage
}
'failed=0 families=4'|Set-Content (Join-Path $stage 'balance_verified.txt')
Write-Output "VERIFIED=$stage"
