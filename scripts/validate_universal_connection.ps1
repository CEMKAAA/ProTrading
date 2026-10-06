param([ValidateSet('authority','compile','compile-start','services','services-restart','roundtrip-start','attach','stop','deploy')][string]$Mode='authority',[string]$InstallationId='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root '.tmp/orb_jp225_full_worker'
$stage=Join-Path $root 'tmp/universal_connection_validation'
New-Item -ItemType Directory -Force $stage|Out-Null
$terminal=Join-Path $worker 'terminal64.exe'
if($Mode-eq 'deploy'){
 $source=Join-Path $root 'IndicatorCodeExamples/universal'
 $report=Get-Content (Join-Path $stage 'roundtrip-report.json') -Raw|ConvertFrom-Json
 if($report.status-ne 'PASS'-or !$report.chart.subscriberPanel-or !$report.chart.inactiveBadgeSignedVector){throw 'Current native authorization/chart verification must pass before deployment'}
 $binary=Join-Path $source 'UniversalConnectionEA.ex5'
 if($report.binarySha256-ne (Get-FileHash $binary -Algorithm SHA256).Hash.ToLower()){throw 'Tested binary does not match deployment binary'}
 $parity=Get-Content (Join-Path $stage 'canonical-parity-report.json') -Raw|ConvertFrom-Json
 if($parity.status-ne 'PASS'-or $parity.differences.Count-ne 0-or $parity.binarySha256-ne $report.binarySha256){throw 'Matching original-EA parity evidence required'}
 if((Get-Content (Join-Path $stage 'compile.log') -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Clean compilation required'}
 $expected=Get-Content (Join-Path $stage 'compile-sources.json') -Raw|ConvertFrom-Json
 foreach($item in $expected){if((Get-FileHash (Join-Path $source $item.file) -Algorithm SHA256).Hash-ne $item.sha256){throw ('Source changed since compilation: '+$item.file)}}
 $dest='C:\MT5\DEMO\MQL5\Experts\StratumUniversal';New-Item -ItemType Directory -Force $dest|Out-Null
 $files=@(Get-ChildItem -LiteralPath $source -File|Where-Object Extension -in '.mq5','.mqh','.ex5')
 $files+=@(Get-ChildItem -LiteralPath (Join-Path $source 'generated') -File|Where-Object Extension -eq '.mqh')
 $manifest=@()
 foreach($file in $files){
  $relative=$file.FullName.Substring($source.Length).TrimStart('\','/')
  $target=Join-Path $dest $relative;New-Item -ItemType Directory -Force (Split-Path -Parent $target)|Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $target -Force
  $hash=(Get-FileHash $file.FullName -Algorithm SHA256).Hash
  if((Get-FileHash $target -Algorithm SHA256).Hash-ne $hash){throw ('Copy verification failed: '+$relative)}
  $manifest+=@{file=$relative;sha256=$hash;bytes=$file.Length}
 }
 $manifest|ConvertTo-Json -Depth 3|Set-Content (Join-Path $stage 'deployment-manifest.json') -Encoding UTF8
 Write-Output ('DEPLOYED '+$files.Count+' verified files to '+$dest);exit
}
if($Mode-eq 'services'-or $Mode-eq 'services-restart'){
 $port=Get-NetTCPConnection -LocalPort 4321 -State Listen -ErrorAction SilentlyContinue
 if($port-and $Mode-eq 'services-restart'){
  $existing=Get-CimInstance Win32_Process -Filter ('ProcessId='+$port.OwningProcess)
  if($existing.CommandLine-notmatch 'control-service[/\\]start.mjs --local-dev'){throw 'Port is not owned by our local control service'}
  Stop-Process -Id $existing.ProcessId;Start-Sleep -Milliseconds 500;$port=$null
 }
 if(!$port){
  $p=Start-Process 'C:\nvm4w\nodejs\node.exe' -ArgumentList '--experimental-strip-types control-service/start.mjs --local-dev' -WorkingDirectory (Join-Path $root 'web-mvp') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stage 'service-out.log') -RedirectStandardError (Join-Path $stage 'service-error.log')
  Write-Output ('SERVICE_PID='+$p.Id)
 }
 $ready=$false
 for($i=0;$i-lt 50;$i++){
  try{$health=Invoke-RestMethod 'http://127.0.0.1:4321/health' -TimeoutSec 2;if($health.service-eq 'stratum-control'){$ready=$true;break}}catch{}
  Start-Sleep -Milliseconds 200
 }
 if(!$ready){throw 'Local control service failed readiness check'}
 exit
}
if($Mode-eq 'roundtrip-start'){
 $p=Start-Process 'C:\nvm4w\nodejs\node.exe' -ArgumentList '--experimental-strip-types scripts/test-mt5-roundtrip.mjs' -WorkingDirectory (Join-Path $root 'web-mvp') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stage 'roundtrip-out.log') -RedirectStandardError (Join-Path $stage 'roundtrip-error.log')
 Write-Output ('ROUNDTRIP_PID='+$p.Id);exit
}
if($Mode-eq 'compile'-or $Mode-eq 'compile-start'){
 $file=Join-Path $root 'IndicatorCodeExamples/universal/UniversalConnectionEA.mq5'
 $log=Join-Path $stage 'compile.log'
 $source=Split-Path -Parent $file
 $fingerprints=@(Get-ChildItem -LiteralPath $source -Recurse -File|Where-Object Extension -in '.mq5','.mqh'|ForEach-Object{
  @{file=$_.FullName.Substring($source.Length).TrimStart('\','/');sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}
 })
 $fingerprints|ConvertTo-Json -Depth 3|Set-Content (Join-Path $stage 'compile-sources.json') -Encoding UTF8
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if($Mode-eq 'compile-start'){Write-Output ('COMPILE_PID='+$p.Id);exit}
 if(!$p.WaitForExit(600000)){throw 'Compile timeout'}
 Get-Content $log -Tail 12
 if((Get-Content $log -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Universal compile failed'}
 exit
}
if($Mode-eq 'stop'){
 $p=Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal
 if($p){Get-Process -Id $p.ProcessId|ForEach-Object{$null=$_.CloseMainWindow()}}
 exit
}
if(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal){throw 'Existing validation worker is busy'}
if($Mode-eq 'authority'){
 $name='UniversalAuthorityProbe'
 $probe=Join-Path $root "tests/mql5/$name.mq5";$probeLog=Join-Path $stage 'authority-compile.log'
 $editor=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$probe+'" /log:"'+$probeLog+'"') -WindowStyle Hidden -PassThru
 if(!$editor.WaitForExit(60000)){throw 'Native probe compile timeout'}
 if((Get-Content $probeLog -Raw)-notmatch 'Result: 0 errors, 0 warnings'){throw 'Native authority probe compile failed'}
 Copy-Item -LiteralPath (Join-Path $root "tests/mql5/$name.ex5") -Destination (Join-Path $worker "MQL5/Scripts/$name.ex5") -Force
 $lines=@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',"Script=$name",'Symbol=JP225m','Period=M5','ShutdownTerminal=1')
}else{
 if($InstallationId-notmatch '^[a-f0-9-]{36}$'){throw 'Installation ID required'}
 $ex5=Join-Path $root 'IndicatorCodeExamples/universal/UniversalConnectionEA.ex5'
 foreach($source in @('UniversalConnectionEA.mq5','UniversalRuntime.mqh','UniversalAuthority.mqh','UniversalAuthorityKey.mqh','UniversalChart.mqh')){
  if((Get-Item $ex5).LastWriteTime-lt (Get-Item (Join-Path $root ('IndicatorCodeExamples/universal/'+$source))).LastWriteTime){throw 'EA binary is stale; complete compilation first'}
 }
 $dest=Join-Path $worker 'MQL5/Experts/StratumUniversal'
 New-Item -ItemType Directory -Force $dest|Out-Null
 Copy-Item -LiteralPath $ex5 -Destination $dest -Force
 $presets=Join-Path $worker 'MQL5/Presets';New-Item -ItemType Directory -Force $presets|Out-Null
 ('InpInstallationId='+$InstallationId)|Set-Content (Join-Path $presets 'stratum-validation.set') -Encoding Unicode
 $lines=@('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]','Expert=StratumUniversal\UniversalConnectionEA','ExpertParameters=stratum-validation.set','Symbol=JP225m','Period=M5','ShutdownTerminal=0')
}
$ini=Join-Path $stage ($Mode+'.ini');$lines|Set-Content $ini -Encoding ASCII
$p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
if($Mode-eq 'authority'){
 if(!$p.WaitForExit(90000)){throw 'Native authority probe timeout'}
 $result=Join-Path $env:APPDATA 'MetaQuotes/Terminal/Common/Files/Stratum/security-probe.json'
 $value=Get-Content $result -Raw|ConvertFrom-Json
 $value|ConvertTo-Json -Compress
 if($value.failed-ne 0){throw 'Native authority verification failed'}
}else{Write-Output ('UNIVERSAL_WORKER_PID='+$p.Id)}
