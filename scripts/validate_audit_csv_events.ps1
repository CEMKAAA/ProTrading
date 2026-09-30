$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $terminal}){throw 'Isolated worker already running'}
$source=Join-Path $root 'tests/mql5/AuditCsvEventProbe.mq5'
$log=Join-Path $root '.tmp/AuditCsvEventProbe.log'
$p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$source+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(180000)){throw 'Compile timeout'}
if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 20;throw 'Compile failed'}
Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source,'.ex5')) -Destination (Join-Path $worker 'MQL5/Experts/AuditCsvEventProbe.ex5') -Force
$ini=Join-Path $root '.tmp/AuditCsvEventProbe.ini'
@('[Experts]','Enabled=0','AllowDllImport=0','Account=0','Profile=0','Chart=0','[StartUp]','Expert=AuditCsvEventProbe','Symbol=EURUSDm','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
$start=Get-Date
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if(-not $p.WaitForExit(150000)){
 if($p.Path -eq $terminal){$p.Kill();$p.WaitForExit(10000)|Out-Null}
 throw 'Isolated event worker timed out'
}
$report=Join-Path $worker 'MQL5/Files/AuditCsvEventProbe.txt'
if(-not (Test-Path $report) -or (Get-Item $report).LastWriteTime -lt $start.AddSeconds(-2)){throw 'Fresh output missing'}
$text=Get-Content $report -Raw
Write-Output $text
if($text -notmatch 'success=true'){throw 'Event export failed'}
$path=($text -split '\r?\n'|Where-Object{$_ -like 'csv=*'}).Substring(4)
$rows=@(Import-Csv -LiteralPath $path)
if($rows.Count -ne 64){throw 'CSV row count mismatch'}
if(@($rows|Where-Object{$_.f_kiv_status -eq 'SEEDED_LOCAL_HISTORY'}).Count -ne 64){throw 'Kivanc coverage missing'}
$sum=($rows|Measure-Object -Property label_net_r -Sum).Sum
if($sum -ne 20){throw "Fixture PnL changed: $sum"}
foreach($row in $rows){
 $at=[datetime]::ParseExact($row.entry_time,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
 foreach($column in @('feature_last_closed_bar','f_kiv_last_closed_bar')){
  $bar=[datetime]::ParseExact($row.$column,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
  if($bar.AddMinutes(5) -gt $at){throw "Future bar leaked in $column"}
 }
 if($row.feature_cutoff -ne $row.entry_time){throw 'Feature cutoff differs from trade entry'}
}
$names=@($rows[0].PSObject.Properties.Name)
if(@($names | Select-Object -Unique).Count -ne $names.Count){throw 'Duplicate feature names'}
Write-Output "CSV verified: rows=64 netR=$sum columns=$(@($rows[0].PSObject.Properties).Count)"
Write-Output 'Entry-time causality verified for every permuted trade row'
