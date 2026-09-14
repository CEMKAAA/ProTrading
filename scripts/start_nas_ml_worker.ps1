param([switch]$InstallAtLogon)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $PSScriptRoot 'nas_ml_worker.py'
$common=Join-Path $env:APPDATA 'MetaQuotes/Terminal/Common/Files/NasML'
$python=(Get-Command python -ErrorAction Stop).Source
$arguments='-u "'+$worker+'" --root "'+$common+'"'
if($InstallAtLogon) {
    $taskPython=Join-Path (Split-Path -Parent $python) 'pythonw.exe'
    if(!(Test-Path -LiteralPath $taskPython)){throw 'pythonw.exe required for a hidden logon worker'}
    $name='ProTradingSystem-NAS-ML-Worker'
    $existing=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if($existing -and ($existing.Actions.Execute -ne $taskPython -or $existing.Actions.Arguments -ne $arguments)) {
        throw 'An existing NAS worker task has different paths; review it rather than overwriting.'
    }
    if(!$existing) {
        $action=New-ScheduledTaskAction -Execute $taskPython -Argument $arguments -WorkingDirectory $root
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
        $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    }
}
$running=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -in @('python.exe','pythonw.exe') -and $_.CommandLine -like ('*'+$worker+'*')})
if($running.Count){Write-Output ('NAS worker already running: '+($running.ProcessId -join ','));exit}
$logs=Join-Path $root 'logs/NasStrategyLibrary_20260912/worker'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$env:OMP_NUM_THREADS='1';$env:OPENBLAS_NUM_THREADS='1';$env:MKL_NUM_THREADS='1'
$p=Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'stdout.log') -RedirectStandardError (Join-Path $logs 'stderr.log')
Start-Sleep -Seconds 3
if($p.HasExited){Get-Content (Join-Path $logs 'stderr.log') -Tail 12;throw 'NAS worker did not stay running'}
Write-Output ('NAS research worker started, PID='+$p.Id+'. This does not enable EA trading or ML filters.')
