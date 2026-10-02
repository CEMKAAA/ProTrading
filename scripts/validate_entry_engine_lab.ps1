param([switch]$OfflineHistory,[switch]$UiOnly,[switch]$PipOnly,[ValidateSet('USDJPYm','EURUSDm')][string]$Symbol='USDJPYm')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'IndicatorCodeExamples'
$stage=Join-Path $root ('.tmp/entry_engine_lab_'+(Get-Date -Format yyyyMMdd_HHmmss))
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Worker busy'}
$seen=@{}
function StageSource([string]$path){
 $path=[IO.Path]::GetFullPath($path)
 if(!$path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'External dependency'}
 if($seen.ContainsKey($path)){return};$seen[$path]=$true
 $dst=Join-Path $stage $path.Substring($source.Length+1)
 New-Item -ItemType Directory -Path (Split-Path $dst) -Force|Out-Null
 Copy-Item -LiteralPath $path -Destination $dst
 foreach($m in [regex]::Matches([IO.File]::ReadAllText($path),'(?m)^\s*#include\s+"([^"]+)"')){StageSource (Join-Path (Split-Path $path) $m.Groups[1].Value)}
}
StageSource (Join-Path $source 'entry_engine_lab/EntryEngineLabEA.mq5')
$original=[IO.File]::ReadAllText((Join-Path $source 'macrossover_orb/MaCrossPineStream.mqh'))
$baseline=[regex]::Match($original,'(?s)class McPineKernel\s*\{.*?(?=\r?\ndouble McFeedHtf)').Value
if(!$baseline){throw 'Original MaCross kernel extraction failed'}
$baseline=$baseline.Replace('class McPineKernel','class McPineKernelBaseline')
[IO.File]::WriteAllText((Join-Path $stage 'entry_engine_lab/EntryEngineBuiltinsBaseline.mqh'),$baseline,(New-Object Text.UTF8Encoding($false)))
$editor='C:\MT5\DEMO\MetaEditor64.exe'
function Compile([string]$file){
 $log=$file+'.log'
 $p=Start-Process $editor -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 if([IO.File]::ReadAllText($log) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log | Select-String 'error|warning';throw 'Compile failed'}
 Get-Content $log -Tail 1
}
Compile (Join-Path $stage 'entry_engine_lab/EntryEngineLabEA.mq5')
# Prevent automatic research-metric audits in the test-only copy.
$path=Join-Path $stage 'entry_engine_lab/OrbStrategyUserMetrics.mqh'
$text=[regex]::Replace([IO.File]::ReadAllText($path),'(?s)void OrbUserEnsureMetrics\(\)\s*\{.*?\n\}', 'void OrbUserEnsureMetrics(){}')
[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
$name='EntryEngineLabProbe_'+[Guid]::NewGuid().ToString('N').Substring(0,10)
$probe=Join-Path $stage ('entry_engine_lab/'+$name+'.mq5')
Copy-Item -LiteralPath (Join-Path $root 'tests/mql5/EntryEngineScalperChecks.mqh') -Destination (Join-Path $stage 'entry_engine_lab/EntryEngineScalperChecks.mqh')
Copy-Item -LiteralPath (Join-Path $root 'tests/mql5/EntryEngineLabPickerChecks.mqh') -Destination (Join-Path $stage 'entry_engine_lab/EntryEngineLabPickerChecks.mqh')
Copy-Item -LiteralPath (Join-Path $root 'tests/mql5/MaOpenCapacityChecks.mqh') -Destination (Join-Path $stage 'entry_engine_lab/MaOpenCapacityChecks.mqh')
$text=[IO.File]::ReadAllText((Join-Path $root 'tests/mql5/EntryEngineLabProbe.mq5')).Replace('EntryEngineLabProbe.txt',$name+'.txt')
$text=$text.Replace('EntryEngineScalperChecks.mqh',$name+'_checks.mqh')
$checksPath=Join-Path $stage ('entry_engine_lab/'+$name+'_checks.mqh')
[IO.File]::WriteAllText($checksPath,([IO.File]::ReadAllText((Join-Path $root 'tests/mql5/EntryEngineScalperChecks.mqh'))).Replace('EntryEngineLabScalpers.txt',$name+'_scalpers.txt'),(New-Object Text.UTF8Encoding($false)))
if($OfflineHistory){$text="#define LAB_OFFLINE_HISTORY_FIXTURE`n"+$text}
if($UiOnly){$text="#define LAB_UI_ONLY`n"+$text}
if($PipOnly){$text="#define LAB_PIP_ONLY`n"+$text}
[IO.File]::WriteAllText($probe,$text,(New-Object Text.UTF8Encoding($false)))
Compile $probe
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($probe,'.ex5')) -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5'))
$ini=Join-Path $stage 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),('Symbol='+$Symbol),'Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$started=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(600000)){throw 'Probe timeout'}
$report=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
if(!(Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh report missing'}
$result=Get-Content $report -Raw;$result|Set-Content (Join-Path $stage 'result.txt');Write-Output $result
foreach($image in @('EntryEngineLabEngines.png','EntryEngineLabFeatures.png','EntryEngineLabMargin.png')){
  if($UiOnly -and $image -eq 'EntryEngineLabMargin.png'){continue}
  Copy-Item -LiteralPath (Join-Path $worker ('MQL5/Files/'+$image)) -Destination (Join-Path $stage $image)
}
if($UiOnly){
 if($result -notmatch '\bfailed=0\b'){throw 'Picker UI validation failed'}
 Write-Output "UI_STAGE=$stage"
 exit
}
Copy-Item -LiteralPath (Join-Path $worker ('MQL5/Files/'+$name+'_scalpers.txt')) -Destination (Join-Path $stage 'scalpers.txt')
if($result -notmatch 'failed=0' -or $result -notmatch 'audit_same=true'){throw 'Validation failed'}
# Return production dependencies to the exact compiled content, not instrumented content.
Copy-Item -LiteralPath (Join-Path $source 'entry_engine_lab/OrbStrategyUserMetrics.mqh') -Destination $path -Force
Write-Output "STAGE=$stage"
$stage|Set-Content (Join-Path $root '.tmp/entry_engine_lab_release_path.txt') -Encoding ASCII
