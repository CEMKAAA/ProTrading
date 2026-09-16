param([switch]$Install)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'logs/MaCrossOver_20260915'
New-Item -ItemType Directory -Path $report -Force | Out-Null
$sources=@('IndicatorCodeExamples/MaCrossOverEA.mq5','tests/mql5/MaCrossOverProbe.mq5')
foreach($relative in $sources) {
 $source=Join-Path $root $relative
 $log=Join-Path $report ((Split-Path $source -Leaf)+'.compile.log')
 $before=Get-Date
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(120000)){throw 'Compile timeout'}
 if(!(Test-Path -LiteralPath $log) -or (Get-Item -LiteralPath $log).LastWriteTime -lt $before){throw 'Fresh compile log missing'}
 Get-Content -LiteralPath $log -Tail 1
 if(![IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings')){throw "Compile failed: $log"}
}
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$exe=Join-Path $worker 'terminal64.exe'
if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object {$_.ExecutablePath -eq $exe}).Count){throw 'Isolated worker is already running; not touching it'}
Copy-Item -LiteralPath (Join-Path $root 'tests/mql5/MaCrossOverProbe.ex5') -Destination (Join-Path $worker 'MQL5/Scripts/MaCrossOverProbe.ex5')
$ini=Join-Path $report 'probe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Script=MaCrossOverProbe','Symbol=JP225m','Period=M5','ShutdownTerminal=1') | Set-Content -LiteralPath $ini -Encoding ASCII
$before=Get-Date
$p=Start-Process $exe -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'Isolated probe timeout; no production deployment'}
$result=Join-Path $worker 'MQL5/Files/MaCrossOverProbe.json'
if(!(Test-Path -LiteralPath $result) -or (Get-Item -LiteralPath $result).LastWriteTime -lt $before){throw 'Fresh probe result missing'}
$json=Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
$json | ConvertTo-Json
Copy-Item -LiteralPath $result -Destination (Join-Path $report 'probe.json')
if($json.failed -ne 0 -or $json.checks -lt 25){throw 'Probe failed; no deployment'}
$files=@('MaCrossOverEA.mq5','MaCrossOverEA.ex5','MaCrossOver_Core.mqh','MaCrossOver_Replay.mqh','MaCrossOver_UI.mqh','LiqNarrativeSol_RegimeV3.mqh','LiqNarrativeMacroRegime.mqh')
$destinations=@((Join-Path $root 'IndicatorCodeExamples/macrossover'))
if($Install){$destinations+=@('C:\MT5\DEMO\MQL5\Experts\macrossover','C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\macrossover')}
$manifest=@();$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
foreach($destination in $destinations) {
 New-Item -ItemType Directory -Path $destination -Force | Out-Null
 foreach($name in $files) {
  $source=Join-Path $root ('IndicatorCodeExamples/'+$name);$target=Join-Path $destination $name
  $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  if(Test-Path -LiteralPath $target){
   if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash){
    $backup=Join-Path $report ('backup_'+$stamp+'/'+[Array]::IndexOf($destinations,$destination))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination (Join-Path $backup $name)
   }
  }
  Copy-Item -LiteralPath $source -Destination $target
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash){throw "Hash mismatch $target"}
  $manifest+=@{path=$target;sha256=$hash}
 }
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $report 'manifest.json') -Encoding UTF8
Write-Output ('Verified '+$manifest.Count+' files. No EA attached to any production chart.')
