param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'reports/sol_btc_selection_20261008'
$worker=Join-Path $root '.tmp/sol_selection_worker'
$reference=Join-Path $root '.tmp/orb_jp225_full_worker'
New-Item -ItemType Directory -Force $report|Out-Null
$build=Join-Path $report 'build'
$seen=@{}
function StageSource([string]$file){
 $file=[IO.Path]::GetFullPath($file)
 if(!$file.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'External quoted include'}
 if($seen.ContainsKey($file)){return};$seen[$file]=$true
 $dest=Join-Path $build $file.Substring($root.Length+1)
 New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath $file -Destination $dest -Force
 foreach($include in [regex]::Matches([IO.File]::ReadAllText($file),'(?m)^\s*#include\s+"([^"]+)"')){
  StageSource (Join-Path (Split-Path $file) $include.Groups[1].Value)
 }
}
$files=@('IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5','tests/mql5/SolAdvancedBtcSelectionProbe.mq5')
StageSource (Join-Path $root $files[0])
$release=@($seen.Keys|ForEach-Object {@{relative=$_.Substring($root.Length+1);sha256=(Get-FileHash $_).Hash}})
StageSource (Join-Path $root $files[1])
foreach($relative in $files){
 $file=Join-Path $build $relative
 $log=Join-Path $report ((Split-Path $file -Leaf)+'.log')
 $start=Get-Date
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compiler timeout'}
 if(!(Test-Path $log)-or (Get-Item $log).LastWriteTime-lt $start.AddSeconds(-2)-or (Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){
  if(Test-Path $log){Get-Content $log -Tail 35};throw "Compile failed: $relative"
 }
 Write-Output "COMPILE $relative : 0 errors, 0 warnings"
}
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal){throw 'Selection probe worker already active'}
New-Item -ItemType Directory -Force $worker,(Join-Path $worker 'config'),(Join-Path $worker 'MQL5/Scripts')|Out-Null
# Reuse the binary without copying tick histories or interfering with the campaign.
if(!(Test-Path $terminal)){New-Item -ItemType HardLink -Path $terminal -Target 'C:\MT5\DEMO\terminal64.exe'|Out-Null}
foreach($name in @('common.ini','servers.dat','accounts.dat')){
 Copy-Item -LiteralPath (Join-Path $reference ('config/'+$name)) -Destination (Join-Path $worker ('config/'+$name)) -Force
}
foreach($symbols in Get-ChildItem (Join-Path $reference 'bases') -File -Filter symbols* -Recurse){
 $dest=Join-Path $worker $symbols.FullName.Substring($reference.Length+1)
 New-Item -ItemType Directory -Force (Split-Path $dest)|Out-Null
 Copy-Item -LiteralPath $symbols.FullName -Destination $dest -Force
}
Copy-Item -LiteralPath (Join-Path $build 'tests/mql5/SolAdvancedBtcSelectionProbe.ex5') -Destination (Join-Path $worker 'MQL5/Scripts/SolAdvancedBtcSelectionProbe.ex5') -Force
$ini=Join-Path $report 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=SolAdvancedBtcSelectionProbe','Symbol=BTCUSDm','Period=M1','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){
 # Only the dedicated mock probe process may be stopped.
 Stop-Process -Id $p.Id
 throw 'Selection probe timeout; user terminal and campaign were not stopped'
}
$result=Join-Path $worker 'MQL5/Files/SolAdvancedBtcSelectionProbe.txt'
if(!(Test-Path $result)-or (Get-Item $result).LastWriteTime-lt $start.AddSeconds(-2)){throw 'Fresh native result missing'}
$text=Get-Content $result -Raw
Copy-Item -LiteralPath $result -Destination $report -Force
Write-Output $text
if($text-notmatch '\bfailed=0\b'-or $text-notmatch '\border_attempts=0\b'){throw 'Selection regression failed'}
@{checkedAt=(Get-Date -Format o);compile='0 errors, 0 warnings';behavior="$text";files=$release;
 source=(Get-FileHash (Join-Path $root $files[0])).Hash;
 library=(Get-FileHash (Join-Path $root 'IndicatorCodeExamples/SolAdvanced/LiqStrategyLibrary.mqh')).Hash;
 binary=(Get-FileHash (Join-Path $build 'IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.ex5')).Hash
}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $report 'verification.json') -Encoding UTF8
