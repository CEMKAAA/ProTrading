$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$stage=Join-Path $root 'reports/verification_build/window_writer'
$savedAppData=$env:APPDATA
$utf8=New-Object Text.UTF8Encoding($false)
$culture=[Globalization.CultureInfo]::InvariantCulture
function Hash([string]$text){
 $h=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($h.ComputeHash($utf8.GetBytes($text))).Replace('-','').ToLower()}finally{$h.Dispose()}
}
function WriteText([string]$path,[string]$text){
 [IO.File]::WriteAllText($path+'.pending',$text,$utf8)
 Move-Item -LiteralPath ($path+'.pending') -Destination $path -Force
}
try{
 $env:APPDATA=Join-Path $stage 'AppData'
 $folder=Join-Path $env:APPDATA 'MetaQuotes/Terminal/Common/Files/OrbStrategyUserLibrary/WindowMetrics'
 New-Item -ItemType Directory -Force $folder|Out-Null
 $id='TEST_FIXTURE_NOT_A_STRATEGY';$key='a'*64
 $path=Join-Path $folder ((Hash $id)+'.2.swm')
 $csv=Join-Path $stage 'verified-fixture.csv'
 $checks=0
 foreach($case in @('valid_newer','corrupt_checksum','invalid_counts','other_settings','older')){
  $oldKey=if($case-eq 'other_settings'){'b'*64}else{$key}
  $oldAsOf=if($case-eq 'older'){1791500000}else{1791700000}
  $wins=if($case-eq 'invalid_counts'){2}else{1}
  $body=@('SW_METRICS_2',$id,$oldKey,'2')
  foreach($n in @($oldAsOf,1,$wins,0,0,0,0.5,0)){$body+=([double]$n).ToString('F12',$culture)}
  $body=$body-join "`n";$digest=if($case-eq 'corrupt_checksum'){'0'*64}else{Hash $body}
  WriteText $path ($body+"`nSHA256="+$digest)
  $row=[pscustomobject]@{native_id=$id;settings_key=$key;weeks='2';native_parity_verified='1';settings_verified='1';
   status='AUDITED';data='0';order_attempts='0';as_of='1791600000';total='1';wins='1';losses='0';open='0';flat='0';
   net_r='0.5';min_cum_r='0';metrics_saved='0';detail=''}
  WriteText $csv ((($row|ConvertTo-Csv -NoTypeInformation)-join "`r`n")+"`r`n")
  & (Join-Path $root 'scripts/write_verified_strategy_windows.ps1') -Csv $csv -Family orb
  $result=Import-Csv -LiteralPath $csv
  if($case-eq 'valid_newer'){
   if($result.status-ne 'NEWER_NATIVE_RESULT_RETAINED'-or $result.metrics_saved-ne '0'){throw $case}
  }else{
   if($result.status-ne 'AUDITED'-or $result.metrics_saved-ne '1'){throw ($case+': '+$result.detail)}
   if([IO.File]::ReadAllText($path).Split("`n")[4]-ne '1791600000.000000000000'){throw ($case+': wrong endpoint')}
  }
  $checks++
 }
 Write-Output "METRIC_WRITER: $checks passed, 0 failed; workspace-only test fixtures"
}finally{$env:APPDATA=$savedAppData}
