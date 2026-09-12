from pathlib import Path
import sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import export_orb_r7_runtime as e


def test_constant_class_and_shift_match():
    for p in (0.,1.,.3):
        m=dict(label=1,gain=.5,loss=1.,constant=p,bias=0.,mean=[0.]*50,scale=[1.]*50,coef=[0.]*50)
        for b in (0.,-3.,3.):
            actual=e.score_model(m,np.zeros((4,50)),b)
            q=e.r7.shift(np.full(4,p),b)
            np.testing.assert_allclose(actual,q*.5-(1-q),atol=1e-14)


def test_archive_exact_layout_checksum():
    import hashlib
    m=dict(label=1,gain=.5,loss=1.,constant=.3,bias=0.,mean=[0.]*50,scale=[1.]*50,coef=[0.]*50)
    state=dict(model=0,update=200000,stop=300000,label=1,offset=.1)
    b=e.encode(dict(id='a',config='b',dataset='c'),[m],[state]);v=b.decode().split('\n')
    assert len(v)==9+155+5
    assert hashlib.sha256(('\n'.join(v[:-2])+'\n').encode()).hexdigest()==v[-2]
    assert v[1]==hashlib.sha256(','.join(e.FEATURES).encode()).hexdigest()


def test_runtime_no_legacy_fallback_and_shared_gate():
    root=Path('IndicatorCodeExamples')
    pipeline=(root/'OrbStrategyMLPipeline.mqh').read_text()
    hist=(root/'OrbStrategyMLHistory.mqh').read_text()
    assert 'if(g_mlR7){g_mlUsingCampaign=false;g_mlModel.ready=false;return OrbR7Load();}' in pipeline
    assert 'OrbSlotScore(g_r7Slot,x,bar+PeriodSeconds(g_rtSignalTf),score,reason)' in hist
    assert 'GlobalVariableSet(OrbMlGenerationKey(),g_mlR7?0:1)' in pipeline
    assert 'g_mlExport||g_mlWriting||OrbStrategyPresetHasActiveLifecycle()' in pipeline


def test_three_leaderboard_modes_do_not_change_execution():
    text=Path('IndicatorCodeExamples/OrbStrategyLeaderboard.mqh').read_text()
    assert 'g_lbMode=(g_lbMode+1)%3' in text
    assert 'ML INCLUDES TRAINING DATA: NOT OOS' in text
    assert 'g_mlR7=' not in text and 'g_mlEnabled=' not in text
    assert 'OrbStrategyPresetApplyInteractive(g_strategyCandidateIndex)' in text


def test_retrospective_snapshot_is_complete_and_labelled():
    import json
    path=e.OUT/'leaderboard_5y_retrospective.json'
    if not path.exists():return
    rows=json.loads(path.read_text())
    assert len(rows)==len({r['id'] for r in rows})==53
    assert sum(r['legacy'] is not None for r in rows)==50
    assert sum(r['r7'] is not None for r in rows)==52
    assert len({(r['from_time'],r['to_time']) for r in rows})==1
    for r in rows:
        assert r['evaluation']=='RETROSPECTIVE_TRAINING_INCLUDED_NOT_OOS'
        assert r['to_time']-r['from_time']==1820*86400
        for k in ('legacy','r7'):
            if r[k] is not None:assert r[k]['trades']<=r['base']['trades']
