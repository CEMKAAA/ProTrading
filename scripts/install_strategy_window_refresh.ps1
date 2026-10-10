param([string]$ReportDir='reports/strategy_audit_20261009_rolling')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=[IO.Path]::GetFullPath((Join-Path $root $ReportDir))
$proof=Get-Content (Join-Path $out 'parity_verified.json') -Raw|ConvertFrom-Json
if(!$proof.passed){throw 'Verified native pilot required before enabling automatic refresh'}
$node=(Get-Command node.exe).Source
$script=Join-Path $PSScriptRoot 'watch_strategy_window_refresh.mjs'
$taskName='ProTradingSystem-StrategyWindowRefresh'
$old=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($old){
 foreach($oldAction in $old.Actions){
  $oldArgs=$oldAction.Arguments
  if($oldArgs-match '-EncodedCommand (\S+)'){$oldArgs=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))}
  if($oldArgs-notlike ('*'+$script+'*')){throw 'Existing task is not owned by this project'}
 }
}
$command="& '"+$node.Replace("'","''")+"' '"+$script.Replace("'","''")+"' --report-dir '"+$out.Replace("'","''")+"'"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -EncodedCommand '+$encoded) -WorkingDirectory $root
$trigger=New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval ([TimeSpan]::FromMinutes(1)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output ('Automatic rolling metric worker installed: '+$taskName)
