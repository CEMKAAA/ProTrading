$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$out=Join-Path $root 'reports\verification_build\mega_campaign'
New-Item -ItemType Directory -Path $out -Force|Out-Null
$sha=[Security.Cryptography.SHA256]::Create()
try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-','')}finally{$sha.Dispose()}
$mutex=New-Object Threading.Mutex($false,('Local\ProTradingSystem-MegaAudit-'+$key))
$owned=$false
try{
 try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
 if(!$owned){throw 'A manual mega campaign already owns the coordinator. Use the BAT monitor.'}
 $record=@{pid=$PID;startedUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');script=$PSCommandPath}
 $path=Join-Path $out 'campaign-process.json'
 [IO.File]::WriteAllText($path+'.pending',($record|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
 Move-Item -LiteralPath ($path+'.pending') -Destination $path -Force
 & node (Join-Path $PSScriptRoot 'mega_audit_campaign.mjs') run --report-dir $out --verified-dir (Join-Path $root 'reports\verification_build\audit_failures')
 exit $LASTEXITCODE
}finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
