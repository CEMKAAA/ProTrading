import json
from pathlib import Path
import sys
import numpy as np
import pandas as pd
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import orb_regime_leaderboard as c


def frame():
    f=pd.DataFrame({'net_r':[1.,-2.,3.,-1.,0.,2.,-1.,4.], 'entry_at_broker':np.arange(8)+1600000000,
                    'exit_at_broker':np.arange(8)+1600000100,'f_regime_valid':np.ones(8)})
    for i in range(6):f[f'f_regime{i}']=(np.arange(8)%7==i).astype(int)
    return f


def test_partition_is_exclusive_complete_and_unknown_preserved():
    f=frame();codes=c.regime_codes(f);assert codes.tolist()==[0,1,2,3,4,5,6,0]
    rows=c.partition(f,np.ones(len(f),bool),codes)
    assert rows[0]['n']==sum(r['n'] for r in rows[1:])==8
    assert rows[0]['net_r']==sum(r['net_r'] for r in rows[1:])==6
    assert rows[0]['dd_r']==2 and rows[-1]['n']==1
    assert sum(r['dd_r'] for r in rows[1:])!=rows[0]['dd_r']


def test_overlapping_regimes_rejected():
    f=frame();f.loc[0,'f_regime1']=1
    with pytest.raises(ValueError,match='overlapping'):c.regime_codes(f)


def test_same_timestamp_exits_grouped_and_empty_regime_not_loss():
    f=frame().iloc[:2].copy();f['exit_at_broker']=1600000100;f['net_r']=[-10,10]
    s=c.statistics(f);assert s['dd_r']==0 and s['net_r']==0 and s['n']==2
    s=c.statistics(f.iloc[:0]);assert s['n']==0 and s['wr'] is None and s['net_r']==0


def test_small_sample_cannot_outrank_adequate_sample():
    a=dict(id='a',mode='VANILLA',n=10,score=90,net_r=10)
    b=dict(id='b',mode='R7',n=30,score=5,net_r=8)
    assert c.rank_key(b)>c.rank_key(a)


def test_full_campaign_matches_frozen_all_regime_snapshot():
    path=c.OUT/'campaign.json'
    if not path.exists():pytest.skip('Run local campaign first')
    data=json.loads(path.read_text());old={r['id']:r for r in json.loads((c.ROOT/'logs/OrbR7Runtime_20260912/leaderboard_5y_retrospective.json').read_text())}
    assert len(data['rows'])==155 and len(data['files'])==155 and len(data['missing'])==4
    assert len({r['id'] for r in data['rows']})==53
    for r in data['rows']:
        all_=r['cells'][0];previous=old[r['id']][{'VANILLA':'base','LEGACY':'legacy','R7':'r7'}[r['mode']]]
        assert all_['n']==previous['trades'] and all_['w']==previous['wins'] and all_['l']==previous['losses']
        assert all_['net_r']==pytest.approx(previous['net_r'],abs=1e-9)
        assert all_['dd_r']==pytest.approx(previous['dd_r'],abs=1e-9)
        for key in ('n','w','l','flat'):
            assert sum(cell[key] for cell in r['cells'][1:])==all_[key]
        assert sum(cell['net_r'] for cell in r['cells'][1:])==pytest.approx(all_['net_r'],abs=1e-9)
        for cell in r['cells']:
            assert sum(y['n'] for y in cell['years'])==cell['n']
            assert sum(y['net_r'] for y in cell['years'])==pytest.approx(cell['net_r'],abs=1e-9)


def test_report_identity_and_model_bound_filename():
    f=frame();r=dict(id='test',config='a'*64,dataset='b'*64,mode='R7',model_sha='c'*64,
                    from_time=1631664000,to_time=1788912000,cells=c.partition(f,np.ones(len(f),bool),c.regime_codes(f)))
    raw=c.report_bytes(r);v=c.slot.lines(raw,16384)
    assert len(v)==20 and v[3:8]==['test','a'*64,'b'*64,'R7','c'*64]
    r['model_sha']='d'*64;assert raw!=c.report_bytes(r)


def test_regime_selection_cannot_change_live_permissions_or_model():
    text=Path('IndicatorCodeExamples/OrbStrategyLeaderboard.mqh').read_text()
    branch=text.split('else if(object==PREFIX+"BTN_LB_REGIME")',1)[1].split('\n',1)[0]
    assert 'g_lbRegime=' in branch and 'OrbLbSort()' in branch
    for forbidden in ('g_regimeAllowed[','g_mlR7=','g_mlEnabled=','OrderSend(', 'OrbMlLoad('):
        assert forbidden not in text
    assert 'g_lbOpen&&!control' in text and 'BTN_LB_REGIME' in text.split('string fixedNames[]',1)[1]
    parser=Path('IndicatorCodeExamples/OrbStrategyRegimeLeaderboard.mqh').read_text()
    for check in ('v[3]!=id','v[4]!=config','v[5]!=dataset','v[6]!=mode','v[7]!=model','start!=(long)fromTime'):
        assert check in parser
