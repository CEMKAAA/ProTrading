$ErrorActionPreference='Stop'
$root=(Resolve-Path .).Path
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$compiler='C:\MT5\DEMO\MetaEditor64.exe'
foreach($base in @('MaCrossInversePairProbe','OrbLevelSwapProbe','SolAdvancedLevelSwapProbe')) {
  $source=Join-Path $root ('tests/mql5/'+$base+'.mq5')
  $shadow=Join-Path $root ('tests/mql5/_inverse_gap_'+$base+'.mq5')
  $log=Join-Path $root ('.tmp/inverse_gap_probe_'+$base+'.log')
  Copy-Item -LiteralPath $source -Destination $shadow -Force
  $p=Start-Process $compiler -ArgumentList ('/compile:"'+$shadow+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
  if(-not $p.WaitForExit(180000)){throw "Probe compile timeout $base"}
  if((Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 25;throw "Probe compile failed $base"}
  $name='Gap_'+$base
  $binary=[IO.Path]::ChangeExtension($shadow,'.ex5')
  Copy-Item -LiteralPath $binary -Destination (Join-Path $worker ('MQL5/Scripts/'+$name+'.ex5')) -Force
  $ini=Join-Path $root ('.tmp/inverse_gap_probe_'+$base+'.ini')
  @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',('Script='+$name),'Symbol=EURUSDm','Period=M1','ShutdownTerminal=1') | Set-Content $ini -Encoding ASCII
  $start=Get-Date
  $p=Start-Process (Join-Path $worker 'terminal64.exe') -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
  if(-not $p.WaitForExit(180000)){throw "Probe timeout $base"}
  $result=Join-Path $worker ('MQL5/Files/'+$base+'.json')
  if(-not (Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $start.AddSeconds(-2)){throw "Probe result missing $base"}
  $json=Get-Content $result -Raw|ConvertFrom-Json
  "$base checks=$($json.checks) failed=$($json.failed)"
  if($json.failed -ne 0){throw "Probe failed $base"}
  Remove-Item -LiteralPath $shadow,$binary -Force
}
