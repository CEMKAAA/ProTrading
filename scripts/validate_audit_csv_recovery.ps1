$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$terminal=Join-Path $worker 'terminal64.exe'
if(Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $terminal}){throw 'Isolated worker busy'}
$stage=Join-Path $root ('.tmp/csv_recovery_'+(Get-Date -Format yyyyMMdd_HHmmss))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach($name in @('AuditCsvRecoverySetup','AuditCsvRecoveryProbe')){
 $file=Join-Path $root ('tests/mql5/'+$name+'.mq5');$log=Join-Path $stage ($name+'.log')
 $started=Get-Date
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(180000)){throw 'Compile timeout'}
 if(!(Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $started -or (Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 20;throw 'Recovery compile failed'}
 $folder=if($name -like '*Setup'){'Scripts'}else{'Experts'}
 Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($file,'.ex5')) -Destination (Join-Path $worker ('MQL5/'+$folder+'/'+$name+'.ex5')) -Force
}
function RunFixture([string]$name,[string]$symbol,[string]$type){
 $ini=Join-Path $stage ($name+'.ini')
 @('[Experts]','Enabled=0','AllowDllImport=0','Account=0','Profile=0','Chart=0','[StartUp]',($type+'='+$name),('Symbol='+$symbol),'Period=M5','ShutdownTerminal=1') | Set-Content $ini -Encoding ASCII
 $started=Get-Date
 $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(150000)){if($p.Path -eq $terminal){$p.Kill()};throw 'Recovery worker timeout'}
 $result=Join-Path $worker ('MQL5/Files/'+$name+'.txt')
 if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started.AddSeconds(-2)){throw 'Fresh recovery result missing'}
 $text=Get-Content $result -Raw;$text | Set-Content (Join-Path $stage ($name+'.txt')) -Encoding UTF8
 return $text
}
$symbol=(RunFixture 'AuditCsvRecoverySetup' 'EURUSDm' 'Script').Trim()
if($symbol -notlike 'AXCSV_*'){throw 'Custom fixture setup failed'}
$result=RunFixture 'AuditCsvRecoveryProbe' $symbol 'Expert'
Write-Output $result
if($result -notmatch 'success=true waited=true injected=true'){throw 'Recovery integration failed'}
$path=($result -split '\r?\n' | Where-Object {$_ -like 'csv=*'}).Substring(4)
$rows=@(Import-Csv -LiteralPath $path)
if($rows.Count -ne 64 -or ($rows | Measure-Object -Property label_net_r -Sum).Sum -ne 20){throw 'Recovered rows/PnL changed'}
foreach($row in $rows){
 $at=[datetime]::ParseExact($row.entry_time,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
 foreach($column in @('feature_last_closed_bar','f_kiv_last_closed_bar')){
  $bar=[datetime]::ParseExact($row.$column,'yyyy.MM.dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
  if($bar.AddMinutes(5) -gt $at){throw 'Recovered features leaked future data'}
 }
 if($row.label_exit_reason -notin @('TP','SL')){throw 'Recovered exit reason missing'}
}
Write-Output "STAGE=$stage"
Write-Output 'Synthetic recovery: 64 rows, net 20R, zero missing groups, causal closed bars'
