"""Generate the NAS adapter from the reviewed ORB numerical implementation.

Only identifiers/feature-contract bindings differ. ORB sources are read-only.
"""
from pathlib import Path
import hashlib
import re

ROOT=Path(__file__).resolve().parents[1]
INC=ROOT/'IndicatorCodeExamples'
FEATURES=('direction body_atr range_atr upper_wick_atr lower_wick_atr return1_atr return5_atr '
 'return20_atr rsi14 close_ema20_atr close_ema50_atr ema20_50_atr ema_cross volume_ratio20 '
 'atr_ratio64 efficiency20 spread_atr hour_sin hour_cos weekday_sin weekday_cos regime_valid '
 'regime0 regime1 regime2 regime3 regime4 regime5 regime_trend_depth regime_vol_depth '
 'regime_age regime_transition_conf regime_pending sma8_atr sma9_atr sma13_atr supertrend_atr '
 'nas_direction ema20_slope_atr invert').split()
SCHEMA='nas.closed256.v1'

def generate():
    core=(INC/'OrbStrategyMLCore.mqh').read_text(encoding='utf-8-sig')
    core=core.replace('ORB_STRATEGY_ML_CORE_MQH','NAS_STRATEGY_ML_CORE_MQH').replace('ORB_ML_', 'NAS_ML_').replace('OrbMl','NasMl').replace('orb.closed256.v1',SCHEMA)
    a=core.index('string NasMlFeatureNames()'); b=core.index('\nstring NasMlBytesSha256',a)
    core=core[:a]+'string NasMlFeatureNames()\n{\n   return "'+','.join('f_'+f for f in FEATURES)+'";\n}\n'+core[b:]
    (INC/'NasStrategyMLCore.mqh').write_text('// Generated from OrbStrategyMLCore.mqh; regenerate, do not fork.\n'+core,encoding='ascii')
    for name in ('StrategyR7Core','StrategyModelSlot'):
        text=(INC/('Orb'+name+'.mqh')).read_text(encoding='utf-8-sig')
        text=text.replace('OrbStrategy','NasStrategy').replace('OrbR7','NasR7').replace('OrbSlot','NasSlot').replace('OrbMl','NasMl')
        text=text.replace('ORB_STRATEGY_','NAS_STRATEGY_').replace('ORB_ML_','NAS_ML_').replace('OrbML\\\\','NasML\\\\')
        (INC/('Nas'+name+'.mqh')).write_text('// Generated from ORB versioned model-slot implementation.\n'+text,encoding='ascii')
    pipeline=(INC/'OrbStrategyMLPipeline.mqh').read_text(encoding='utf-8-sig')
    a=pipeline.index('bool OrbMlFeatures('); b=pipeline.index('\n#include "OrbStrategyMLHistory.mqh"',a)
    feature=pipeline[a:b]
    start=feature.index('   ArrayResize(x,'); end=feature.index('   double ema20=')
    feature='bool NasLibraryFeatures(const MqlRates &source[],int index,const NasPoint &point,int direction,double &x[],string &reason)\n{\n'+feature[start:end]+feature[end:]
    start=feature.index('   ArrayResize(x,'); end=feature.index('   double ema20=')
    feature=feature[:start]+'''   ArrayResize(x,40);ArrayInitialize(x,0);reason="FEATURE_HISTORY";
   int seconds=PeriodSeconds(_Period);
   if(InpSignalBarMode!=NAS_SIGNAL_BAR_CLOSED||index<255||index>=ArraySize(source))return false;
   datetime cutoff=source[index].time+seconds;
   MqlRates rates[];ArrayResize(rates,256);
   for(int k=0;k<256;k++)rates[k]=source[index-255+k];
'''+feature[end:]
    feature=feature.replace('x[0]=EffectiveOrbDirection(raw)=="BUY"?1:-1;','x[0]=direction;')
    feature=feature.replace('OrbRegimeBucketAt(bar,state)','LiqMacroRegimeBucketAt(cutoff,state)')
    start=feature.index('   int rf=-1;');end=feature.index('   x[38]=',start)
    feature=feature[:start]+'''   if(!NAS_IsValid(point.sma8)||!NAS_IsValid(point.sma9)||!NAS_IsValid(point.sma13)||!NAS_IsValid(point.superTrend))return false;
   x[33]=(close-point.sma8)/atr;x[34]=(close-point.sma9)/atr;
   x[35]=(close-point.sma13)/atr;x[36]=(close-point.superTrend)/atr;x[37]=point.direction;
'''+feature[end:]
    feature=feature.replace('g_rtInvertMode','g_invertTradeModeRuntime').replace('ORB_ML_FEATURES','NAS_ML_FEATURES')
    start=feature.index('   observed[0]=');end=feature.index('   for(int i=0;i<NAS_ML_FEATURES;',start)
    feature=feature[:start]+feature[end:]
    (INC/'NasStrategyFeatures.mqh').write_text('// Generated from ORB closed256 feature math; NAS-specific fields 33..37.\n'+feature,encoding='ascii')
    source=(INC/'NasUltimate_SATS_PartialNoBE_EA.mq5').read_text(encoding='utf-8-sig')
    # Immutable inputs form a compatibility profile. Runtime values are added
    # separately by NasLibraryConfig. Audit-window/presentation inputs are not alpha.
    inputs=re.findall(r'^input\s+(\w+)\s+(Inp\w+)\s*=',source,re.M)
    ignored=('InpDashboardAuditWeeks','InpShowDashboard','InpDrawLastSignalsOnStart','InpStartupSignalCount','InpDrawTradeLevels','InpDrawExecutionArrows','InpSignalParityAudit','InpAuditNoSignalEvaluations','InpDrawLastSignalsOnStart')
    dependencies=('NasUltimate_Core.mqh','SuperTrend_SATS_Core.mqh','NasStrategyWorkbench.mqh',
        'NasStrategyResearch.mqh','NasStrategyFeatures.mqh','NasStrategyMLCore.mqh',
        'NasStrategyR7Core.mqh','NasStrategyModelSlot.mqh','LiqNarrativeSol_RegimeV3.mqh')
    source_hash=hashlib.sha256(source.encode()+b''.join((INC/name).read_bytes() for name in dependencies)).hexdigest()
    lines=['// Generated immutable settings identity.',f'#define NAS_LIBRARY_SOURCE_HASH "{source_hash}"', 'string NasLibraryInputProfile()', '{','   string s="nas-input-profile-v1|"+NAS_LIBRARY_SOURCE_HASH;']
    for typ,name in inputs:
        if name in ignored: continue
        value=f'DoubleToString({name},16)' if typ=='double' else f'(string){name}'
        lines.append(f'   s+="|{name}="+{value};')
    # Include observer settings too, since changing these changes ML features.
    observer=(INC/'LiqNarrativeSol_RegimeV3.mqh').read_text(encoding='utf-8-sig')
    for typ,name in re.findall(r'^input\s+(\w+)\s+(Inp\w+)\s*=',observer,re.M):
        value=f'DoubleToString({name},16)' if typ=='double' else f'(string){name}'
        lines.append(f'   s+="|{name}="+{value};')
    lines+=['   return NasMlSha256(s);','}','']
    (INC/'NasStrategyInputProfile.mqh').write_text('\n'.join(lines),encoding='ascii')

if __name__=='__main__': generate()
