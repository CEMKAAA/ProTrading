"""Audit-only diff contracts. Runtime/latency proof requires the MQL probe."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
INC=ROOT/'IndicatorCodeExamples'
BASE=ROOT/'logs/AuditWindowReuse_20260914/baseline'

def text(path):return path.read_text(encoding='utf-8-sig')

def function(source,name):
    match=re.search(r'^\w+\s+'+name+r'\([^\n]*(?:\n[^{}]*)?\)\s*\{',source,re.M)
    assert match,name
    start=source.index('{',match.start());depth=0
    # Count braces outside C++ strings/comments.
    tokens=re.finditer(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[{}]',source[start:])
    for token in tokens:
        if token[0]=='{':depth+=1
        elif token[0]=='}':
            depth-=1
            if depth==0:return source[match.start():start+token.end()]
    raise AssertionError(name)

def test_orb_replay_math_untouched():
    for name in ('OrbUltimateEA.mq5','OrbUltimateEA_StrategyLibrary.mq5'):
        current=INC/(Path('orb')/name if name=='OrbUltimateEA_StrategyLibrary.mq5' else Path(name))
        before=text(BASE/name);after=text(current)
        for func in ('SimulateHistoricalLifecycle','SimulateTrade','BuildSimGeometry'):
            assert function(before,func)==function(after,func),(name,func)
        memo=function(after,'OrbMemoLifecycle')
        assert 'forcedExitTime' in memo and 'forcedExitOutcome' in memo
        assert 'g_rtHistoricalWeeks' not in memo
        assert 'result.valid&&result.outcome!="open"' in memo
        assert 'result.exitTime<=now' in memo
        assert 'g_orbReplayValues[slot]=result' in memo
        assert 'g_btFillMode=' in memo and 'g_btSpreadPts=' in memo
        old=function(before,'ProcessHistoricalPrepDay')
        new=function(after,'ProcessHistoricalPrepDayUncached').replace('ProcessHistoricalPrepDayUncached','ProcessHistoricalPrepDay',1)
        assert old==new,(name,'prep math')
        prep=function(after,'ProcessHistoricalPrepDay')
        assert 'g_rtHistoricalWeeks' not in prep
        assert 'g_regimeAllowed' in prep and 'g_orbRfBlocked' in prep
        assert 'snapshot.tradeEnd<iTime' in prep
        if 'StrategyLibrary' in name:
            assert 'g_regimeReferenceSignals' in prep and 'g_regimeReferenceWindows' in prep

def test_nas_replay_math_untouched():
    before=text(BASE/'NasStrategyResearch.mqh');after=text(INC/'NasStrategyResearch.mqh')
    for func in ('NasResearchReplay','NasResearchTradePlan','NasLibraryReplayAudit','NasLibraryAuditCurve'):
        assert function(before,func)==function(after,func),func
    memo=function(after,'NasResearchOutcome')
    for dependency in ('t.entryAt','t.deadline','t.direction','t.closeDirection','t.entry','t.sl','t.tp','t.entryValid','_Point'):
        assert dependency in memo
    assert 'valid&&reason!="OPEN"&&reason!="DATA"' in memo

def test_liq_window_and_trace_contracts():
    names=['LiquidityNarrative_MT5_EA','LiquidityNarrative_Invert_MT5_EA','LiqNarrativeSolVersion','LiqNarrativeSol_Advanced',
           'LiquidityNarrative_MT5_EA_Channel','LiqNarrativeSolVersion_Channel','LiqNarrativeSol_Advanced_Channel']
    for stem in names:
        before=text(BASE/(stem+'.mq5'));after=text(INC/(stem+'.mq5'))
        assert function(before,'SimulateSignal')==function(after,'SimulateSignal'),stem
        assert function(before,'BuildSignals')==function(after,'BuildSignals'),stem
        buttons=re.findall(r'if\(Clicked\(sparam, "BTN_AUD_[^\n]+',after)
        assert buttons and all('RefreshAfterConfigChange(false)' in button for button in buttons)
        if 'Advanced' in stem:
            for field in ('traceDir','traceEntry','traceSl','traceTp','traceHalf','traceExitTime','traceExitReason'):
                assert field in function(after,'SimCacheGet') and field in function(after,'SimCachePut')

def test_cache_bounded_and_collision_safe():
    src=text(INC/'AuditMemoIndex.mqh')
    assert 'm_keys[slot]==key' in src
    assert 'm_count>=65536' in src
    assert 'SERIES_SYNCHRONIZED' in src and 'SERIES_FIRSTDATE' in src
    assert 'FileOpen' not in src and 'OrderSend' not in src
    epoch=text(INC/'OrbReplayMemoEpoch.mqh')
    assert 'b-bars>appended' in epoch and 'l<last' in epoch and 's!=synced' in epoch
