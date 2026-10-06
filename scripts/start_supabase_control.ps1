$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$web=Join-Path $root 'web-mvp'
$stage=Join-Path $root 'tmp/universal_connection_validation'
$port=Get-NetTCPConnection -LocalPort 4321 -State Listen -ErrorAction SilentlyContinue
if($port){
  $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+$port.OwningProcess)
  if($process.CommandLine-notmatch 'control-service[/\\]start.mjs --(local-dev|supabase)' -and
     $process.CommandLine-notmatch 'scripts[/\\]local-server.mjs control --(local-dev|supabase)'){
    throw 'Port 4321 is not owned by Stratum; no process stopped'
  }
  Stop-Process -Id $process.ProcessId
  Start-Sleep -Milliseconds 500
}
$node=(Get-Command node.exe).Source
$process=Start-Process -FilePath $node -ArgumentList '--experimental-strip-types control-service/start.mjs --supabase' -WorkingDirectory $web -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $stage 'supabase-service-out.log') -RedirectStandardError (Join-Path $stage 'supabase-service-error.log')
for($i=0;$i-lt 30;$i++){
  try{
    $health=Invoke-RestMethod 'http://127.0.0.1:4321/health' -TimeoutSec 2
    if($health.authMode-eq 'supabase'){$health|ConvertTo-Json -Compress;Write-Output ('PID='+$process.Id);exit}
  }catch{}
  Start-Sleep -Milliseconds 300
}
throw 'Supabase-backed control service failed readiness check'
