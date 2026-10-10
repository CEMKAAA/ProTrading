param([Parameter(Mandatory)][string]$Csv,[Parameter(Mandatory)][ValidateSet('orb','macross','entrylab','sol')][string]$Family)
$ErrorActionPreference='Stop'
$common=Join-Path $env:APPDATA 'MetaQuotes/Terminal/Common/Files'
$culture=[Globalization.CultureInfo]::InvariantCulture
$utf8=New-Object Text.UTF8Encoding($false)
function Hash([string]$value){
 $h=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($h.ComputeHash($utf8.GetBytes($value))).Replace('-','').ToLower()}finally{$h.Dispose()}
}
$rows=@(Import-Csv -LiteralPath $Csv)
foreach($row in $rows){
 if($row.native_parity_verified-ne '1'-or $row.status-notin @('AUDITED','AUDITED_OPEN')){continue}
 if($row.data-ne '0'-or $row.order_attempts-ne '0'-or $row.settings_verified-ne '1'-or $row.settings_key-notmatch '^[a-f0-9]{64}$'){throw 'Unsafe metric'}
 $folder=if($Family-eq 'sol'){(Split-Path $row.native_id)+'\WindowMetrics'}else{
  @{orb='OrbStrategyUserLibrary';macross='MaCrossOrbStrategyLibrary';entrylab='EntryEngineLabStrategyLibrary'}[$Family]+'\WindowMetrics'
 }
 $dir=[IO.Path]::GetFullPath((Join-Path $common $folder))
 if(!$dir.StartsWith($common+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Metric path escaped Common'}
 New-Item -ItemType Directory -Force $dir|Out-Null
 $path=Join-Path $dir ((Hash $row.native_id)+'.'+$row.weeks+'.swm')
 $lock=$null
 try{
  $lock=[IO.File]::Open($path+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $body=@('SW_METRICS_2',$row.native_id,$row.settings_key,$row.weeks)
  foreach($key in @('as_of','total','wins','losses','open','flat','net_r','min_cum_r')){
   $number=[double]::Parse($row.$key,$culture);if([double]::IsNaN($number)-or [double]::IsInfinity($number)){throw 'Invalid metric number'}
   $body+=$number.ToString('F12',$culture)
  }
  if([int]$row.wins+[int]$row.losses+[int]$row.open+[int]$row.flat-ne [int]$row.total){throw 'Metric count mismatch'}
  if(Test-Path -LiteralPath $path){
   $oldText=[IO.File]::ReadAllText($path);$at=$oldText.IndexOf("`nSHA256=")
   $oldBody=if($at-ge 0){$oldText.Substring(0,$at)}else{''}
   $old=$oldBody.Split("`n")
   $oldValid=$at-ge 0-and $oldText.Substring($at+8)-eq (Hash $oldBody)-and $old.Length-eq 12
   $oldValid=$oldValid-and $old[0]-eq 'SW_METRICS_2'-and $old[1]-eq $row.native_id-and $old[2]-eq $row.settings_key-and $old[3]-eq $row.weeks
   if($oldValid){
    try{
     $numbers=@($old[4..11]|ForEach-Object{[double]::Parse($_,$culture)})
     $oldValid=$numbers[0]-gt 0-and $numbers[2]+$numbers[3]+$numbers[4]+$numbers[5]-eq $numbers[1]-and $numbers[7]-le 1e-8
     for($i=0;$i-lt 8;$i++){if([double]::IsNaN($numbers[$i])-or [double]::IsInfinity($numbers[$i])-or $numbers[$i].ToString('F12',$culture)-ne $old[$i+4]){$oldValid=$false}}
     for($i=1;$i-lt 6;$i++){if($numbers[$i]-lt 0-or $numbers[$i]-ne [math]::Floor($numbers[$i])){$oldValid=$false}}
    }catch{$oldValid=$false}
   }
   if($oldValid-and $numbers[0]-gt [double]::Parse($row.as_of,$culture)){
    $row.status='NEWER_NATIVE_RESULT_RETAINED';continue
   }
  }
  $text=$body-join "`n";$text+="`nSHA256="+(Hash $text)
  $temp=$path+'.verified.pending';[IO.File]::WriteAllText($temp,$text,$utf8)
  Move-Item -LiteralPath $temp -Destination $path -Force
  if([IO.File]::ReadAllText($path)-ne $text){throw 'Metric readback mismatch'}
  $row.metrics_saved='1'
 }catch{
  $row.status='METRIC_WRITE_FAILED';$row.detail=$_.Exception.Message
 }finally{if($lock){$lock.Dispose()}}
}
$csvText=(($rows|ConvertTo-Csv -NoTypeInformation)-join "`r`n")+"`r`n"
[IO.File]::WriteAllText($Csv+'.pending',$csvText,$utf8)
Move-Item -LiteralPath ($Csv+'.pending') -Destination $Csv -Force
