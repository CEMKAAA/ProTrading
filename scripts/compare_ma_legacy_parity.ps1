$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$dir=Join-Path $root 'logs/ma_legacy_parity_20260919'
function Read-Rows($path){
 if(!(Test-Path $path)){throw "Missing $path"}
 @(Get-Content $path|Where-Object {$_ -ne ''}|ForEach-Object {
  # The first baseline exporter used MQL's datetime string cast without quotes.
  # Normalize those two fields for parsing; keep the raw baseline untouched.
  $line=[regex]::Replace($_,'(\"(?:signal|exit)\":)(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})',{
   param($m)
   $dt=[datetime]::ParseExact($m.Groups[2].Value,'yyyy.MM.dd HH:mm:ss',[cultureinfo]::InvariantCulture)
   $epoch=[datetime]::SpecifyKind([datetime]'1970-01-01',[DateTimeKind]::Unspecified)
   $m.Groups[1].Value+([long]($dt-$epoch).TotalSeconds).ToString([cultureinfo]::InvariantCulture)
  })
  $line|ConvertFrom-Json
 })
}
$report=@();$differences=@();$total=0
foreach($symbol in @('JP225m','XAUUSDm','BTCUSDm','USDJPYm','USOILm','SOLUSDm')){
 $old=Read-Rows (Join-Path $dir "baseline/$symbol.jsonl")
 $new=Read-Rows (Join-Path $dir "candidate/$symbol.jsonl")
 if(@($old+$new|Where-Object kind -eq 'error').Count){throw "Probe error for $symbol"}
 foreach($s in @($old|Where-Object kind -eq 'summary')){
  $n=@($new|Where-Object {$_.kind -eq 'summary' -and $_.id -eq $s.id})
  if($n.Count -ne 1){throw "Missing candidate $($s.id)"}
  $n=$n[0];$a=@($old|Where-Object {$_.kind -eq 'trade' -and $_.id -eq $s.id});$b=@($new|Where-Object {$_.kind -eq 'trade' -and $_.id -eq $s.id})
  $equal=$a.Count -eq $b.Count
  for($i=0;$i -lt [Math]::Min($a.Count,$b.Count);$i++){
   foreach($field in @('signal','dir','valid','outcome','exit','price','r','data')){
    $same=if($field -in 'price','r'){[Math]::Abs([double]$a[$i].$field-[double]$b[$i].$field) -le 1e-9}else{$a[$i].$field -eq $b[$i].$field}
    if(!$same){$equal=$false;$differences+=@{id=$s.id;row=$i;field=$field;before=$a[$i].$field;after=$b[$i].$field}}
   }
  }
  foreach($field in @('raw','total','w','l','o','data','r')){if([Math]::Abs([double]$s.$field-[double]$n.$field) -gt 1e-9){$equal=$false}}
  $preset=[IO.File]::ReadAllLines((Join-Path $dir "presets/$($s.slot).preset"))
  $report+=[pscustomobject]@{slot=$s.slot;name=$preset[7];symbol=$symbol;independent=$s.independent;trades=$s.total;w=$s.w;l=$s.l;o=$s.o;data=$s.data;beforeR=$s.r;afterR=$n.r;equal=$equal}
  $total+=$a.Count
 }
}
if($report.Count -ne 16){throw "Expected 16 presets, got $($report.Count)"}
$result=@{from='2026-09-05 00:00:00';to='2026-09-19 00:00:00';strategies=$report.Count;trade_rows=$total;all_equal=(@($report|Where-Object {!$_.equal}).Count -eq 0);results=$report;differences=$differences}
$result|ConvertTo-Json -Depth 8|Set-Content (Join-Path $dir 'comparison.json') -Encoding UTF8
$report|Format-Table slot,symbol,independent,trades,w,l,o,beforeR,afterR,equal -AutoSize
Write-Output "Strategies=$($report.Count) TradeRows=$total AllEqual=$($result.all_equal)"
if(!$result.all_equal){throw 'Parity mismatch; deployment blocked'}
