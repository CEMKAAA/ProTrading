param([switch]$RunProbes)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tag=Get-Date -Format yyyyMMdd_HHmmss
$stage=Join-Path $root ".tmp/ma_exit_$tag"
$src=Join-Path $stage 'IndicatorCodeExamples/macrossover_orb'
$tests=Join-Path $stage 'tests/mql5'
New-Item -ItemType Directory -Force $src,$tests | Out-Null
Get-ChildItem (Join-Path $root 'IndicatorCodeExamples/macrossover_orb') -File | Where-Object {$_.Extension -in '.mqh','.mq5'} | Copy-Item -Destination $src
$names=@('MaExitPolicyProbe','MaStrategySaveProbe','MaCrossPineStreamProbe')
foreach($name in $names){
 $text=[IO.File]::ReadAllText((Join-Path $root "tests/mql5/$name.mq5"))
 foreach($out in @('MaExitPolicyProbe.json','MaStrategySaveProbe.json','MaCrossPineProbe.json','MaCrossPineDirections.txt')){$text=$text.Replace('"'+$out+'"','"'+$tag+'_'+$out+'"')}
 [IO.File]::WriteAllText((Join-Path $tests "$name.mq5"),$text,[Text.UTF8Encoding]::new($false))
}
$files=@((Join-Path $src 'MaCrossOrderFlowWorker.mq5'),(Join-Path $src 'MaCrossOverOrbEA.mq5'))+@($names|ForEach-Object {Join-Path $tests "$_.mq5"})
foreach($file in $files){
 $log="$file.log"
 $p=Start-Process 'C:\MT5\DEMO\MetaEditor64.exe' -ArgumentList ('/compile:"'+$file+'" /log:"'+$log+'"') -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(120000)){throw 'compile timeout'}
 if(!(Test-Path $log) -or (Get-Content $log -Raw) -notmatch 'Result: 0 errors, 0 warnings'){Get-Content $log -Tail 22;throw 'compile failed'}
 Get-Content $log -Tail 1
}
if($RunProbes){
 $worker=Join-Path $root '.tmp/orb_jp225_full_worker';$terminal=Join-Path $worker 'terminal64.exe'
 foreach($name in $names){
  if(@(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'"|Where-Object ExecutablePath -eq $terminal).Count){throw 'worker busy'}
  $run=$name+'_'+$tag
  Copy-Item (Join-Path $tests "$name.ex5") (Join-Path $worker "MQL5/Scripts/$run.ex5")
  $ini=Join-Path $stage "$name.ini"
  @('[Experts]','Enabled=0','AllowDllImport=0','[StartUp]',"Script=$run",'Symbol=JP225m','Period=M5','ShutdownTerminal=1')|Set-Content $ini -Encoding ASCII
  $started=Get-Date
  $p=Start-Process $terminal -ArgumentList ('/portable /config:"'+$ini+'"') -WindowStyle Hidden -PassThru
  if(!$p.WaitForExit(180000)){throw 'probe timeout'}
  $out=if($name -eq 'MaCrossPineStreamProbe'){'MaCrossPineProbe.json'}else{"$name.json"}
  $result=Join-Path $worker "MQL5/Files/${tag}_$out"
  if(!(Test-Path $result) -or (Get-Item $result).LastWriteTime -lt $started){throw 'no fresh result'}
  Copy-Item $result $stage
  $r=Get-Content $result -Raw|ConvertFrom-Json
  Write-Output "$name $(Get-Content $result -Raw)"
  if($r.failed -ne 0){throw 'test failed'}
 }
}
Write-Output "STAGE=$stage"
