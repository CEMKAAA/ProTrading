// Export effective settings from the original EA, not reconstructed defaults.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const root=new URL('../../',import.meta.url);
const catalog=JSON.parse(readFileSync(new URL('lib/ea-controls.json',new URL('../',import.meta.url)),'utf8')).macross;
const inputs={InpSignalTimeframe:'g_rtSignalTf',InpBreakoutDelayMinutes:'(g_rtUseDelay?g_rtDelayMin:0)',
  InpTargetTpLeg:'g_rtTargetLeg',InpHalfBeMode:'g_rtHalfBeLeg',InpEntryMode:'g_rtEntryMode',
  InpExitEngineMode:'g_rtExitMode',InpTargetMode:'g_rtTargetMode',InpPipSlModeDefault:'g_rtPipSlMode',
  InpPipSlPips:'g_rtPipSlPips',InpSlDistancePct:'g_rtSlDistancePct',InpUseAtrRangeFilter:'g_rtFilterAtr',
  InpUseVolumeFilter:'g_rtFilterVol',InpVolumeMultiplier:'g_rtVolumeMultiplier',InpUseDayFilter:'g_rtFilterDay',
  InpUseTimeExit:'g_rtTimeExit',InpUseDisplacementFilter:'g_rtDisplacement',InpFvgMode:'g_rtFvgMode',
  InpMoveToBEOnTp1:'g_rtBEOnTp1',InpUtcMidnightSessionDefault:'g_rtUtcMidnightSession',
  InpUseEntryTimeWindow:'g_rtEntryWindow',InpEntryWindowStartGmt:'ParityClockText(g_rtEntryWindowStartMin)',
  InpEntryWindowEndGmt:'ParityClockText(g_rtEntryWindowEndMin)',
  InpFilteredWindowReverseExitDefault:'g_rtFilteredWindowReverseExit',
  InpExitOnPostTradeSameDirectionDispBlockDefault:'g_rtPostTradeDispBlockExit',
  InpExitTrailStartLeg:'g_rtExitTrailStartLeg',InpExitEmaPeriod:'g_rtExitEmaPeriod',InpExitAtrMultiplier:'g_rtExitAtrMultiplier',
  InpMaCrossMode:'g_rtMaCrossMode',InpMaCrossPair:'g_rtMaCrossPair',InpRiskPerTradePct:'g_rtRiskPerTradePct',
  InpOrderFlowMode:'g_mcOf.mode',InpOrderFlowLookback:'g_mcOf.lookback',InpOrderFlowBins:'g_mcOf.bins',
  InpOrderFlowValueArea:'g_mcOf.valueArea',InpOrderFlowMinActivity:'g_mcOf.minActivity',InpOrderFlowMinDelta:'g_mcOf.minDelta',
  InpOrbRfFilterDefault:'g_orbRfEnabled',InpBacktestFillMode:'g_btFillMode',InpBacktestSameBarPolicy:'g_btSameBarPolicy',
  InpBacktestNativeParity:'g_btNativeParity',InpBacktestSpreadPts:'g_btSpreadPts',
  InpBacktestSlippagePts:'g_btSlippagePts',InpBacktestCommissionPerLot:'g_btCommissionPerLot'};
const regimes=['TrendLowVol','TrendHighVol','RangeLowVol','RangeHighVol','TransitionPending','TransitionFresh'];
regimes.forEach((name,i)=>inputs['InpRegime'+name+'Allowed']=`g_regimeAllowed[${i}]`);
for(let i=0;i<12;i++)inputs[`InpOrbRf${String(i+1).padStart(2,'0')}Blocked`]=`g_orbRfBlocked[${i}]`;
const runtime={targetR:'RuntimeTargetR()',balance:'g_nativeRiskBalance',independent:'g_maIndependent',maxOpen:'g_maMaxConsecutive',
  reverseExit:'g_maReverseExit',reverseWaitMinutes:'g_maReverseWait',inversion:'g_rtInvertMode',
  inverseMaxCostPct:'g_rtAdvancedReverseMaxCostPct',advancedAudit:'g_rtAdvancedAuditEngine',
  nasGate:'(g_rtNasStateGate?2:g_rtNasConfirmation?1:0)',nasExit:'(g_rtNasAdditionalExit?2:g_rtNasExitOnOppositeSignal?1:0)',
  nasStateVolume:'g_rtNasVolumeFilter',nasFlowVolume:'g_rtNasFlowVolumeFilter',nasStateMultiplier:'g_rtNasVolumeMultiplier',
  nasFlowMultiplier:'g_rtNasFlowVolumeMultiplier',nasSensitivity:'g_rtNasSensitivity',nasWaitMinutes:'g_rtNasOppositeExitWaitMinutes',
  nasAgeMinutes:'g_rtNasActiveSignalLookbackMinutes',timeMatrixEnabled:'g_tcalEnabled'};
let out='// Generated test-only effective-setting capture. No trading code.\nvoid ParityCaptureSettings(int file)\n{\n';
for(const group of ['inputs','runtime'])for(const s of catalog[group]){
  const expression=group==='inputs'?(inputs[s.key]??s.key):runtime[s.key];
  if(!expression)throw new Error('Unmapped runtime: '+s.key);
  const encoded=s.type==='bool'?`(${expression}?"true":"false")`:s.type==='string'?expression:
    s.type==='double'?`DoubleToString(${expression},16)`:`(string)(long)(${expression})`;
  out+=` FileWriteString(file,"${group==='inputs'?'i':'r'}.${s.key}="+${encoded}+"\\n");\n`;
}
out+=' for(int i=0;i<7;i++)FileWriteString(file,"m."+(string)i+"="+(string)g_tcalDayHours[i]+"\\n");\n}\n';
const path=new URL('tests/mql5/CanonicalParitySettings.mqh',root);writeFileSync(path,out);
console.log('Generated bounded probe settings:',fileURLToPath(path));
