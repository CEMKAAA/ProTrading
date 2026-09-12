$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$report=Join-Path $root 'logs/OrbModelSlots_20260912'
$stage=Join-Path $report 'compile'
[IO.Directory]::CreateDirectory($stage)|Out-Null
Get-ChildItem -LiteralPath (Join-Path $root 'IndicatorCodeExamples') -File |
 Where-Object {$_.Extension -in '.mq5','.mqh'} | Copy-Item -Destination $stage
$probe=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Scripts/OrbSlotProbe/OrbSlotProbe.mq5'
foreach($source in @((Join-Path $stage 'OrbUltimateEA_StrategyLibrary.mq5'),$probe)){
 $log=$source+'.log';$before=Get-Date
 $p=Start-Process -FilePath 'C:\Program Files\MetaTrader 5\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(240000)){throw 'Compile timeout'}
 if(!(Test-Path -LiteralPath $log) -or (Get-Item -LiteralPath $log).LastWriteTime -lt $before){throw 'Stale compile log'}
 Get-Content -LiteralPath $log -Tail 4
 if(!([IO.File]::ReadAllText($log).Contains('Result: 0 errors, 0 warnings'))){throw 'Compile failed'}
}
$exe=Join-Path $root '.tmp/orb_jp225_full_worker/terminal64.exe'
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $exe}).Count){throw 'Isolated worker already running'}
$result=Join-Path $root '.tmp/orb_jp225_full_worker/MQL5/Files/OrbSlotProbe/result.json'
$before=Get-Date
$p=Start-Process -FilePath $exe -ArgumentList ('/portable /config:"'+(Join-Path $report 'probe.ini')+'"') -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(120000)){throw 'No-order probe timeout; no production deployment'}
if(!(Test-Path -LiteralPath $result) -or (Get-Item -LiteralPath $result).LastWriteTime -lt $before){throw 'Fresh probe missing'}
$r=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json
if($r.failed -ne 0 -or $r.packs -ne 53 -or $r.vectors -ne 4143 -or $r.negative -ne 277){$r|ConvertTo-Json;throw 'Slot parity failed'}
Copy-Item -LiteralPath $result -Destination (Join-Path $report 'mql_parity.json')
$r|ConvertTo-Json
Write-Output 'Isolated no-order slot validation complete. Production untouched.'
