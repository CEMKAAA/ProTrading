$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false)
function Update([string]$relative,[string]$old,[string]$new) {
  $path=(Resolve-Path -LiteralPath $relative).Path
  $text=[IO.File]::ReadAllText($path,$utf8)
  if(-not $text.Contains($old)){throw "Anchor missing: $relative / $($old.Substring(0,[Math]::Min($old.Length,45)))"}
  $text=$text.Replace($old,$new)
  $temp=$path+'.inverse_r_floor.tmp'
  [IO.File]::WriteAllText($temp,$text,$utf8)
  Move-Item -LiteralPath $temp -Destination $path -Force
}
$ma='IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5'
$orb='IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5'
$sol='IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5'
Update $ma '   detail="LEVEL_SWAP_INVERSE_OK source_entry="' @'
   // A 1R target must not silently become a tiny TP after quote conversion.
   if(enforceCost&&g_rtAdvancedReverseMaxCostPct<100.0
      &&MathAbs(geometry.sourceTargetR-1.0)<=0.01
      &&geometry.execTargetR+1e-6<1.0-g_rtAdvancedReverseMaxCostPct/100.0)
   {
      detail="INVERSE_GAP_BLOCK r_floor effective_r="+DoubleToString(geometry.execTargetR,4)
         +" min_r="+DoubleToString(1.0-g_rtAdvancedReverseMaxCostPct/100.0,4);
      return false;
   }

   detail="LEVEL_SWAP_INVERSE_OK source_entry="
'@
Update $orb '   detail="LEVEL_SWAP_INVERSE_OK source_entry="' @'
   if(enforceGap&&g_rtInverseMaxGapPct<100.0
      &&MathAbs(geometry.sourceTargetR-1.0)<=0.01
      &&geometry.execTargetR+1e-6<1.0-g_rtInverseMaxGapPct/100.0)
   {
      detail="INVERSE_GAP_BLOCK r_floor effective_r="+DoubleToString(geometry.execTargetR,4)
         +" min_r="+DoubleToString(1.0-g_rtInverseMaxGapPct/100.0,4);
      return false;
   }

   detail="LEVEL_SWAP_INVERSE_OK source_entry="
'@
Update $sol '   SetSignalTargetLadder(inverted);
   double effectiveR = MathAbs(inverted.targetOverride - inverted.entry) / inverted.risk;' @'
   double effectiveR = MathAbs(inverted.targetOverride - inverted.entry) / inverted.risk;
   double sourceTargetR = MathAbs(sourceTarget-source.entry)/sourceRisk;
   if(enforceGap&&inverseEntry>0.0&&g_inverseMaxGapPct<100.0
      &&MathAbs(sourceTargetR-1.0)<=0.01
      &&effectiveR+1e-6<1.0-g_inverseMaxGapPct/100.0)
   {
      detail="INVERSE_GAP_BLOCK r_floor effective_r="+DoubleToString(effectiveR,4)
         +" min_r="+DoubleToString(1.0-g_inverseMaxGapPct/100.0,4);
      return false;
   }
   SetSignalTargetLadder(inverted);
'@
Update $ma 'Max inverse entry Bid/Ask gap as % of source TP distance; 10 rejects a gap over 1 pip for a 10-pip 1R target. 100 disables.' 'Max inverse quote gap and 1R TP erosion in percent; 10 requires at least 0.90R gross TP. 100 disables.'
Update $orb 'Max inverse Bid/Ask gap as % of source TP distance. 100 disables the guard.' 'Max inverse quote gap and 1R TP erosion in percent; 10 requires at least 0.90R gross TP. 100 disables.'
Update $sol '   EditObj("EDIT_INV_GAP", x + 654, row, 42, bh, DoubleToString(g_inverseMaxGapPct,2));' @'
   EditObj("EDIT_INV_GAP", x + 654, row, 42, bh, DoubleToString(g_inverseMaxGapPct,2));
   ObjectSetString(0,PFX+"EDIT_INV_GAP",OBJPROP_TOOLTIP,
      "Max inverse quote gap and 1R TP erosion in percent; 10 requires at least 0.90R gross TP. 100 disables.");
'@
'Inverse 1R TP floor updated in three sources'
