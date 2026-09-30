$ErrorActionPreference = 'Stop'
$path = 'IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$s = [System.IO.File]::ReadAllText((Resolve-Path $path), $utf8)
function Rep([string]$old, [string]$new) {
    if (-not $script:s.Contains($old)) { throw "Missing anchor: $($old.Substring(0, [Math]::Min(70,$old.Length)))" }
    $script:s = $script:s.Replace($old, $new)
}
Rep 'string TargetLabel(ERL_RR_MODE rr)' @'
string RuntimeInverseGapKey(){return RuntimeInvertKey()+".max_gap_pct";}
bool SetRuntimeInverseGap(double value)
{
   if(!MathIsValidNumber(value)||value<0.0||value>100.0)return false;
   if(GlobalVariableSet(RuntimeInverseGapKey(),value)<=0.0)return false;
   g_inverseMaxGapPct=value;
   return true;
}
void LoadRuntimeInverseGap()
{
   g_inverseMaxGapPct=InpInverseMaxGapPctDefault;
   if(!MathIsValidNumber(g_inverseMaxGapPct)||g_inverseMaxGapPct<0.0||g_inverseMaxGapPct>100.0)
      g_inverseMaxGapPct=10.0;
   string key=RuntimeInverseGapKey();
   if(GlobalVariableCheck(key))
   {
      double saved=GlobalVariableGet(key);
      if(MathIsValidNumber(saved)&&saved>=0.0&&saved<=100.0)g_inverseMaxGapPct=saved;
   }
}
bool ParseInverseGap(string raw,double &value)
{
   StringTrimLeft(raw);StringTrimRight(raw);
   if(StringLen(raw)<1)return false;
   bool dot=false;
   for(int i=0;i<StringLen(raw);i++)
   {
      int ch=StringGetCharacter(raw,i);
      if(ch=='.'&&!dot){dot=true;continue;}
      if(ch<'0'||ch>'9')return false;
   }
   value=StringToDouble(raw);
   return MathIsValidNumber(value)&&value>=0.0&&value<=100.0;
}

string TargetLabel(ERL_RR_MODE rr)
'@
Rep '+ "|INV" + (g_invertMode ? "LEVEL_SWAP_1" : "0");' '+ "|INV" + (g_invertMode ? "LEVEL_SWAP_1" : "0") + "|INV_GAP" + DoubleToString(g_inverseMaxGapPct,4);'
Rep 'ErlSignal &inverted, string &detail, double inverseEntry=0.0)' 'ErlSignal &inverted, string &detail, double inverseEntry=0.0, bool enforceGap=true)'
Rep '   inverted = source;
   inverted.invertedGeometry = true;' @'
   if(enforceGap && inverseEntry>0.0 && g_inverseMaxGapPct<100.0)
   {
      double gapPct=100.0*MathAbs(inverseEntry-source.entry)/MathAbs(sourceTarget-source.entry);
      if(gapPct>g_inverseMaxGapPct+1e-8)
      {
         detail="INVERSE_GAP_BLOCK quote_gap_pct="+DoubleToString(gapPct,4)
            +" max_pct="+DoubleToString(g_inverseMaxGapPct,4);
         return false;
      }
   }
   inverted = source;
   inverted.invertedGeometry = true;
'@
Rep 'double &commissionR, string &detail)' 'double &commissionR, string &detail, bool enforceGap=true)'
Rep 'ApplyFullInversionGeometry(source, target, targetModel, tradeSig, detail, simEntry)' 'ApplyFullInversionGeometry(source, target, targetModel, tradeSig, detail, simEntry, enforceGap)'
Rep 'activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail))' 'activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail, false))'
# The tick path is the only place where real entry-side quotes are available.
Rep 'activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail, false)) break;' 'activeSl, tp, half, simRisk, activeHc, commissionR, geometryDetail, true))
               {
                  g_lastSimInvalidReason=StringFind(geometryDetail,"INVERSE_GAP_BLOCK")==0 ? "INVERSE_GAP_BLOCK" : "GEOMETRY";
                  valid=false;
                  return 0.0;
               }'
Rep '      g_hist.total++;
      if(!valid)' '      if(!valid && g_lastSimInvalidReason=="INVERSE_GAP_BLOCK")continue;
      g_hist.total++;
      if(!valid)'
Rep 'if(g_histSignalInvalidReason[i]=="DAILY_QUOTA")continue;' 'if(g_histSignalInvalidReason[i]=="DAILY_QUOTA"||g_histSignalInvalidReason[i]=="INVERSE_GAP_BLOCK")continue;'
Rep '   LoadRuntimeInvertMode();' '   LoadRuntimeInvertMode();
   LoadRuntimeInverseGap();'
Rep @'
   LabelObj("DASH_NARR_HINT", x + 424, row + 4, "Narrative gates", C'255,204,82', 8);
   ButtonObj("BTN_INV", x + 640, row, 104, bh, g_invertMode ? "FULL INV ON" : "FULL INV OFF", g_invertMode ? C'184,103,22' : off);
'@ @'
   LabelObj("DASH_NARR_HINT", x + 420, row + 4, "Gates", C'255,204,82', 8);
   ButtonObj("BTN_INV", x + 510, row, 104, bh, g_invertMode ? "FULL INV ON" : "FULL INV OFF", g_invertMode ? C'184,103,22' : off);
   LabelObj("DASH_INV_GAP", x + 618, row + 4, "GAP%", muted, 8);
   EditObj("EDIT_INV_GAP", x + 654, row, 42, bh, DoubleToString(g_inverseMaxGapPct,2));
   ButtonObj("BTN_INV_GAP_APPLY", x + 700, row, 44, bh, "SET", C'38,101,176');
'@
Rep '   if(Clicked(sparam, "BTN_INV"))' @'
   if(Clicked(sparam, "BTN_INV_GAP_APPLY"))
   {
      double requested=0.0;
      string raw=ObjectGetString(0,PFX+"EDIT_INV_GAP",OBJPROP_TEXT);
      if(!ParseInverseGap(raw,requested)||!SetRuntimeInverseGap(requested))
      {
         g_lastStatus="GAP% must be 0..100";
         UpdateDashboard();ChartRedraw(0);return;
      }
      ObjectSetString(0,PFX+"EDIT_INV_GAP",OBJPROP_TEXT,DoubleToString(g_inverseMaxGapPct,2));
      SimCacheClear();RefreshAfterConfigChange(false);return;
   }
   if(Clicked(sparam, "BTN_INV"))
'@
Rep 'int LiqLibraryCapture(double &v[]){ArrayResize(v,41);' 'int LiqLibraryCapture(double &v[]){ArrayResize(v,42);'
Rep 'v[40]=(double)g_solRegimeRuleBlocked[11];
return ArraySize(v);}' 'v[40]=(double)g_solRegimeRuleBlocked[11];
v[41]=g_inverseMaxGapPct;
return ArraySize(v);}'
Rep 'g_solRegimeRuleBlocked[11]=(bool)v[40];
}' 'g_solRegimeRuleBlocked[11]=(bool)v[40];
g_inverseMaxGapPct=ArraySize(v)>41 ? v[41] : 100.0;
}'
$resolved = (Resolve-Path $path).Path
$temp = Join-Path (Split-Path $resolved) 'LiqNarrativeSol_Advanced.mq5.inverse_gap.tmp'
if (-not $resolved.StartsWith((Resolve-Path 'IndicatorCodeExamples/SolAdvanced').Path + [IO.Path]::DirectorySeparatorChar)) { throw 'Unexpected target path' }
[System.IO.File]::WriteAllText($temp, $s, $utf8)
Move-Item -LiteralPath $temp -Destination $resolved -Force
'Sol source updated'
