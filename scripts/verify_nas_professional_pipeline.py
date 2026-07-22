#!/usr/bin/env python3
"""Verify NAS signal/risk mathematics survived professional pipeline integration."""
from __future__ import annotations
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OLD=ROOT/'logs/backups/NasUltimate_SATS_PartialNoBE_EA_20260722_pre_nas_professional_pipeline.mq5'
NEW=ROOT/'IndicatorCodeExamples/NasUltimate_SATS_PartialNoBE_EA.mq5'
COMPILE=ROOT/'logs/compile_nas_regime_filter_v2.log'
PAT=re.compile(r'(?m)^(?:bool|int|long|ulong|uint|double|string|void|datetime|NasSettings|SATSSettings|NAS_RISK_GEOMETRY_MODE)\s+([A-Za-z_]\w*)\s*\([^;]*?\)\s*\{')

def funcs(text):
    out={}
    for m in PAT.finditer(text):
        i=m.end()-1; depth=0; j=i
        while j<len(text):
            if text[j]=='{': depth+=1
            elif text[j]=='}':
                depth-=1
                if depth==0:
                    j+=1; break
            j+=1
        out.setdefault(m.group(1),[]).append(text[m.start():j])
    return out

def reachable(fmap,roots):
    seen=set(); stack=list(roots)
    while stack:
        name=stack.pop()
        if name in seen: continue
        seen.add(name)
        body='\n'.join(fmap.get(name,[]))
        for candidate in fmap:
            if candidate not in seen and re.search(rf'\b{re.escape(candidate)}\s*\(',body):
                stack.append(candidate)
    return seen

def inputs(text):
    out={}
    for line in text.splitlines():
        m=re.match(r'\s*input\s+.+?\s+(Inp\w+)\s*=\s*(.+?);',line)
        if m: out[m.group(1)]=re.sub(r'\s+',' ',line.strip())
    return out

old=OLD.read_text(encoding='utf-8-sig'); new=NEW.read_text(encoding='utf-8-sig')
of=funcs(old); nf=funcs(new)
roots=['BuildNasSettings','LastSignalScanIndex','NasSignalText','CalculateRisk','ApplyPipRiskGeometry']
scope=reachable(of,roots)
missing=sorted(x for x in scope if x not in nf)
mismatch=sorted(x for x in scope if of.get(x)!=nf.get(x))
assert not missing, f'missing functions: {missing}'
assert not mismatch, f'mathematics changed: {mismatch}'
body='\n'.join('\n'.join(of[x]) for x in scope)
used=sorted(set(re.findall(r'\bInp[A-Za-z0-9_]+\b',body)))
oi=inputs(old); ni=inputs(new)
allowed_execution_default_changes={'InpTpManagementMode'}
im=[x for x in used if oi.get(x)!=ni.get(x) and x not in allowed_execution_default_changes]
assert not im, f'signal/risk inputs changed: {im}'
assert 'InpTpManagementMode = NAS_TP_LEGACY_THREE_LEG' in old
assert 'InpTpManagementMode = NAS_TP_FIXED_SELECTED_LEG' in new
assert '#include "NasUltimate_ProfessionalPipeline.mqh"' in new
assert 'NasProPublishCurrentSignal(rates[i].time, direction)' in new
assert '#include "LiqNarrativeSol_RegimeV3.mqh"' in new
assert 'InpNasRegimeFilterDefault = false' in new
assert 'state.h1h2Phase != "NEUTRAL_ROTATION"' in new
assert 'NasProPublishRegimeCloseOnly(signalBar.time, closeDirection, rule)' in new
assert new.index('NAS_Calculate(rates, copied, BuildNasSettings(), p);') < new.index('NasRegimeRejectsAt(regimeAvailableTime, regimeRule, regimeDetail)')
assert new.index('NasRegimeRejectsAt(regimeAvailableTime, regimeRule, regimeDetail)') < new.index('IsSpreadExecutionAllowed(spreadReason)')
assert 'SimulateHistoricalSignalByTicks(rates, p, closeSignal' in new
assert new.index('if(!tradingWindowOpen)') < new.index('NasProPublishCurrentSignal(rates[i].time, direction)')
assert 'InpRiskGeometryMode = NAS_RISK_GEOMETRY_NORMAL' in new
assert 'InpPipSlDistance = 30.0' in new
include=(ROOT/'IndicatorCodeExamples/NasUltimate_ProfessionalPipeline.mqh').read_text(encoding='utf-8-sig')
assert 'if(g_nasBridgeOnlyRuntime)' in include and 'g_nasBridgeEnabledRuntime = true;' in include
assert 'legacy_aggregate_tp3' not in include
assert 'unsupported_legacy_multi_order' in include
assert 'R totals | Net ' in new and 'Won +' in new and 'Lost -' in new
ct=COMPILE.read_text(encoding='utf-16',errors='ignore')
if 'Result: 0 errors, 0 warnings' not in ct:
    ct=COMPILE.read_text(encoding='utf-8-sig',errors='ignore')
assert 'Result: 0 errors, 0 warnings' in ct
print('NAS professional pipeline verification: PASS')
print(f'protected_functions={len(scope)} protected_inputs={len(used)}')
print('signal_math=UNCHANGED audit_replay=REGIME_AWARE execution_default=SINGLE_ORDER close_only=RETRY_SAFE compile=0_errors_0_warnings')
