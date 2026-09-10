param([string]$MlRoot=(Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\OrbML'))
$ErrorActionPreference='Stop'
$python=(Get-Command python -ErrorAction Stop).Source
& $python -c "import numpy,pandas,sklearn"
if($LASTEXITCODE -ne 0){throw 'Required Python dependencies are missing.'}
$worker=Join-Path $PSScriptRoot 'orb_ml_worker.py'
$launcher=Join-Path $PSScriptRoot 'Start-OrbMLWorker.ps1'
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -File "'+$launcher+'" -MlRoot "'+$MlRoot+'" -WaitForWorker')
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $user
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'ORB Strategy ML Worker' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Local ORB training queue only; no trading API; single-worker lock.' -Force | Out-Null
Start-ScheduledTask -TaskName 'ORB Strategy ML Worker'
Write-Output 'Installed and started ORB Strategy ML Worker. Starts at Windows login; retries failures after one minute.'
Write-Output 'Remove with: Unregister-ScheduledTask -TaskName "ORB Strategy ML Worker"'
