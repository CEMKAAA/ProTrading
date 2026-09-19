$utf=New-Object Text.UTF8Encoding($false)
foreach($n in @('LiquidityNarrative_MT5_EA_Channel.mq5','LiqNarrativeSolVersion_Channel.mq5','LiqNarrativeSol_Advanced_Channel.mq5')){
$p=Join-Path $PWD ('IndicatorCodeExamples/'+$n);$s=[IO.File]::ReadAllText($p)
$h=[regex]::Match($s,'int H = (\d+);').Groups[1].Value
if(!$h){throw "No height $n"}
$s=$s.Replace('void RectObj(string id, int x, int y, int w, int h, color bg, color border)',"#define LIQ_DASH_LOGICAL_HEIGHT $h`r`n"+'#include "LiqDashboardFit.mqh"'+"`r`n"+'void RectObj(string id, int x, int y, int w, int h, color bg, color border)')
foreach($fn in @('RectObj','LabelObj','ButtonObj','EditObj')){
$pattern='(?s)(void '+$fn+'\([^\r\n]+\)\s*\{)(.*?)(\r?\n\})'
$s=[regex]::Replace($s,$pattern,{param($m)
$body=$m.Groups[2].Value
if($fn -eq 'LabelObj'){$body="`r`n   LiqFitPoint(x,y);fontSize=LiqFitFont(fontSize);"+$body}
else{$body="`r`n   LiqFitBox(x,y,w,h);"+$body;$body=$body.Replace('OBJPROP_FONTSIZE, 8','OBJPROP_FONTSIZE, LiqFitFont(8)').Replace('OBJPROP_FONTSIZE, 9','OBJPROP_FONTSIZE, LiqFitFont(9)')}
return $m.Groups[1].Value+$body+$m.Groups[3].Value
})
}
[IO.File]::WriteAllText($p,$s,$utf)
}

