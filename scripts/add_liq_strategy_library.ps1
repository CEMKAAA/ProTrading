$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$src=Join-Path $root 'IndicatorCodeExamples'
$names=@('LiquidityNarrative_MT5_EA','LiqNarrativeSolVersion','LiqNarrativeSol_Advanced','LiquidityNarrative_MT5_EA_Channel','LiqNarrativeSolVersion_Channel','LiqNarrativeSol_Advanced_Channel')
$en="// Existing TP enum values are persistent identifiers; never renumber them.`n#ifndef LIQ_R_OPTIONS_MQH`n#define LIQ_R_OPTIONS_MQH`nenum ERL_RR_MODE`n{`n"
for($i=0;$i -lt 6;$i++){$en+='   ERL_RR_TP'+($i+1)+' = '+$i+",`n"}
for($i=1;$i -le 100;$i++){$en+='   ERL_RR_R'+('{0:D3}' -f $i)+' = '+(100+$i)+' // '+($i*0.05).ToString('0.00',[cultureinfo]::InvariantCulture)+"R`n";if($i -lt 100){$en=$en.TrimEnd("`n");$en=$en.Replace(' // '+($i*0.05).ToString('0.00',[cultureinfo]::InvariantCulture)+'R',', // '+($i*0.05).ToString('0.00',[cultureinfo]::InvariantCulture)+'R')+"`n"}}
$en+="};`n#endif`n"
[IO.File]::WriteAllText((Join-Path $src 'LiqROptions.mqh'),$en,[Text.UTF8Encoding]::new($false))
foreach($name in $names){
 $path=Join-Path $src ($name+'.mq5');$s=[IO.File]::ReadAllText($path)
 if($s.Contains('LiqStrategyLibrary.mqh')){throw "Already patched: $name"}
 $s=[regex]::Replace($s,'enum ERL_RR_MODE\s*\{[^}]+\};','#include "LiqROptions.mqh"',1)
 $s=$s.Replace('   int leg = (int)rr + 1;',"   if((int)rr>=101 && (int)rr<=200) return ((int)rr-100)*0.05;`n   int leg = (int)rr + 1;")
 $s=$s.Replace('   return "TP" + IntegerToString((int)rr + 1)',"   if((int)rr>=101) return DoubleToString(TargetR(rr),2)+`"R`";`n   return `"TP`" + IntegerToString((int)rr + 1)")
 $s=$s.Replace('   if(target == ERL_RR_TP1) return sig.tp1;',"   if((int)target>=101 && (int)target<=200) return NormTradePrice(sig.entry+sig.dir*sig.risk*TargetR(target));`n   if(target == ERL_RR_TP1) return sig.tp1;")
 $s=$s.Replace('   int targetLeg = (int)g_target + 1;',"   int targetLeg = (int)MathCeil(TargetR(g_target)*2.0-1e-9);")
 $s=$s.Replace('(ERL_HC_MODE)(targetLeg - 1)','(ERL_HC_MODE)MathMin(5,targetLeg - 1)')
 $s=$s.Replace('(int)g_target + 1 >','TargetR(g_target)*2.0 >')
 $s=$s.Replace("void UpdateDashboard()`r`n{","void UpdateDashboard()`r`n{`r`n   if(LiqLibraryDashboard()) return;")
 if(!$s.Contains('if(LiqLibraryDashboard())')){$s=$s.Replace("void UpdateDashboard()`n{","void UpdateDashboard()`n{`n   if(LiqLibraryDashboard()) return;")}
 $pattern='(void OnChartEvent\(const int id, const long &lparam, const double &dparam, const string &sparam\)\s*\{)'
 $s=[regex]::Replace($s,$pattern,'$1'+"`n   if(LiqLibraryEvent(id,sparam)) return;",1)
 $fields=@('g_htf','g_entryTf','g_swingLookback','g_target','g_hc','g_weeklyBias','g_entryModel','g_stopModel','g_targetModel','g_requireIrlTouch','g_requireEntrySweep','g_requireDisplacementFvg','g_requireAsiaLiquidityDraw','g_useAsiaLiquidityTarget','g_requireSmt','g_allowDuplicateEntries','g_invertMode','g_slDistancePct','g_slBufferAtrPct','g_pipSlMode','g_pipSlPips','g_histWeeks','g_solRegimeFilterEnabled')
 $bindings=@()
 foreach($field in $fields){$m=[regex]::Match($s,'(?m)^\s*(bool|int|double|ENUM_TIMEFRAMES|ERL_\w+)\s+'+$field+'\s*[;=]');if($m.Success){$bindings+=@{name=$field;type=$m.Groups[1].Value}}}
 if($s.Contains('LiqNarrativeMacroRegime.mqh')){for($i=0;$i -lt 6;$i++){$bindings+=@{name="g_macroRegimeAllowed[$i]";type='bool'}}}
 if($s.Contains('g_solRegimeRuleBlocked[')){for($i=0;$i -lt 12;$i++){$bindings+=@{name="g_solRegimeRuleBlocked[$i]";type='bool'}}}
 $adapter="`n// Strategy snapshots exclude account risk, transport, channel and live lifecycle state.`n"
 $adapter+="string LiqLibraryFamily(){return `"$name`";}`n"
 $adapter+="string LiqLibraryInputContract(){string s=`"V1`";`n"
 foreach($m in [regex]::Matches($s,'(?m)^input\s+\w+\s+(Inp\w+)\s*=')){$v=$m.Groups[1].Value;$adapter+="s+=`"|$v=`"+(string)$v;`n"}
 $adapter+="return s;}`nint LiqLibraryCapture(double &v[]){ArrayResize(v,$($bindings.Count));`n"
 for($i=0;$i -lt $bindings.Count;$i++){$adapter+="v[$i]=(double)$($bindings[$i].name);`n"}
 $adapter+="return ArraySize(v);}`nvoid LiqLibraryAssign(const double &v[]){`n"
 for($i=0;$i -lt $bindings.Count;$i++){$adapter+="$($bindings[$i].name)=($($bindings[$i].type))v[$i];`n"}
 $adapter+="}`n#include `"LiqStrategyLibrary.mqh`"`n"
 [IO.File]::WriteAllText($path,$s+$adapter,[Text.UTF8Encoding]::new($false))
}
