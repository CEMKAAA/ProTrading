from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from check_orb_campaign_compatibility import body, check


def read(name):
    return (ROOT / 'IndicatorCodeExamples/orb' / name).read_text(encoding='utf8')


def test_history_gate_precedes_counts_and_drawing_not_reverse_exits():
    main = read('OrbUltimateEA_StrategyLibrary.mq5')
    calc = body(main, 'ProcessHistoricalCalcDay')
    assert calc.index('FindNewDayAcceptedReverseExit') < calc.index('OrbMlHistoryAllow')
    assert calc.index('OrbMlHistoryAllow') < calc.index('g_histTotal++') < calc.index('DrawOrbHistoricalSegment')
    assert calc.index('g_regimeWins') < calc.index('OrbMlHistoryAllow')
    assert 'OrbMlHistoryAllow' not in body(main, 'ProcessHistoricalPrepDay')


def test_shared_decision_and_export_bypass():
    pipeline = read('OrbStrategyMLPipeline.mqh')
    hist = read('OrbStrategyMLHistory.mqh')
    assert 'OrbMlDecision(raw,bar,g_orbHigh,g_orbLow,g_orbEndServer,true' in body(pipeline, 'OrbMlAllow')
    assert 'OrbMlDecision(raw,bar,hi,lo,orbEnd,false' in body(hist, 'OrbMlHistoryAllow')
    assert 'g_mlEnabled&&!g_mlExport' in body(hist, 'OrbMlHistoryBegin')
    assert 'IN-SAMPLE INCLUDED: NOT OOS' in hist
    assert 'g_mlHistoryErrors++' in hist
    assert 'g_mlHistoryFiltered)return;' in read('OrbStrategyUserMetrics.mqh')


def test_toggle_and_use_result_rebuild():
    ui = body(read('OrbStrategyMLPipeline.mqh'), 'OrbMlUiEvent')
    assert 'BTN_ML_USE"&&g_mlEnabled)QueueHistoricalRedraw(0)' in ui
    assert 'BTN_ML_LOAD"||object==PREFIX+"BTN_ML_TOGGLE")QueueHistoricalRedraw(0)' in ui
    assert 'OrbMlHistoryBegin();' in read('OrbUltimateEA_StrategyLibrary.mq5')


def test_original_feature_and_simulation_contract_still_matches():
    result = check(ROOT)
    if 'reason' not in result:
        assert result['compatible'], result
