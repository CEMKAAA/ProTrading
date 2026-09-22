param([Parameter(Mandatory=$true)][string]$Stage)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stagePath=(Resolve-Path -LiteralPath $Stage).Path
if(!$stagePath.StartsWith((Join-Path $root '.tmp/liq_library_').Replace('/','\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected staging directory'}
$files=@(Get-ChildItem -LiteralPath $stagePath -File|Where-Object Extension -in '.mq5','.mqh','.ex5')
foreach($f in $files|Where-Object Extension -eq '.mq5'){
 if([IO.File]::ReadAllText($f.FullName+'.log') -notmatch 'Result: 0 errors, 0 warnings'){throw "Unverified build $($f.Name)"}
}
$targets=@((Join-Path $root 'IndicatorCodeExamples'),(Join-Path $root 'IndicatorCodeExamples/liq'),'C:\MT5\DEMO\MQL5\Experts','C:\MT5\DEMO\MQL5\Experts\SolAdvanced')
$report=@();$tag=Get-Date -Format yyyyMMdd_HHmmss
for($i=0;$i -lt $targets.Count;$i++){
 foreach($f in $files){
  $to=Join-Path $targets[$i] $f.Name
  try{
   $hash=(Get-FileHash -LiteralPath $f.FullName).Hash
   if(!(Test-Path -LiteralPath $to) -or (Get-FileHash -LiteralPath $to).Hash -ne $hash){
    if(Test-Path -LiteralPath $to){$backup=Join-Path $stagePath "deploy_backup_$tag/$i/$($f.Name)";New-Item -ItemType Directory -Force (Split-Path $backup)|Out-Null;Copy-Item -LiteralPath $to -Destination $backup}
    Copy-Item -LiteralPath $f.FullName -Destination $to
   }
   if((Get-FileHash -LiteralPath $to).Hash -ne $hash){throw 'Hash mismatch'}
   $report+=[pscustomobject]@{path=$to;verified=$true;error=''}
  }catch{$report+=[pscustomobject]@{path=$to;verified=$false;error=$_.Exception.Message};Write-Warning "Blocked: $to"}
 }
}
$report|ConvertTo-Json -Depth 3|Set-Content (Join-Path $stagePath 'deployment_report.json') -Encoding UTF8
$bad=@($report|Where-Object {!$_.verified})
Write-Output "Verified $($report.Count-$bad.Count)/$($report.Count)"
if($bad.Count){$bad|Format-List;exit 1}
