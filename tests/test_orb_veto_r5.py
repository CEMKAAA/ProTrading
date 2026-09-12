from pathlib import Path
import sys
import numpy as np
import pandas as pd
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import orb_veto_r5 as r5
from test_orb_regime_local_r2 import sample


def halves():
    a=sample(120);b=sample(120)
    start=r5.R.stamp('2023-09-09');middle=r5.R.stamp('2024-03-09');end=r5.R.stamp('2024-09-09')
    for f,origin in ((a,start),(b,middle)):
        f['features_at_broker']=origin+np.arange(len(f))*86400
        f['entry_at_broker']=f.features_at_broker+1
        f['exit_at_broker']=f.features_at_broker+3600
        for i in range(6):f['f_regime'+str(i)]=float(i==0)
        f['f_regime_valid']=1
    return a,b,start,middle,end


def test_profile_edges_ties_and_missing_not_fabricated():
    a,_,_,_,_=halves();s=np.ones(len(a));p=r5.profile(a,s,[1,1,1,1])
    assert p['spearman'] is None and p['top_bottom_r'] is None and not p['positive']
    assert p['bins'][0]['mean_r'] is None and p['bins'][4]['n']==len(a)


def test_invalid_regime_cannot_receive_regime_veto():
    a,_,_,_,_=halves();a.loc[0,'f_regime_valid']=0;a.loc[1,'f_regime1']=1
    ids=r5.regime_ids(a);assert ids[0]==ids[1]==-1
    rule=dict(name='regime_tail',active=True,threshold=0.,regimes=[0])
    keep=r5.apply(rule,-np.ones(len(a)),ids)
    assert keep[0] and keep[1] and not keep[2]


def test_bound_negative_group_and_sparse_resamples():
    a,_,start,middle,_=halves();a['net_r']=-1.
    counts=r5.bootstrap_counts(start,middle,5,200)
    mask=np.ones(len(a),bool)
    v=r5.mean_bound(a,mask,mask,counts,start,20.)
    assert v['upper']==-1 and v['shrunk_mean']==-1
    zero=np.zeros_like(counts)
    v=r5.mean_bound(a,mask,mask,zero,start,20.)
    assert v['upper'] is None and v['empty_fraction']==1.


def test_shrinkage_moves_small_group_toward_global():
    a,_,start,middle,_=halves();a['net_r']=1.;a.loc[:7,'net_r']=-1.
    local=np.arange(len(a))<8;global_mask=np.ones(len(a),bool)
    counts=r5.bootstrap_counts(start,middle,5,200)
    v=r5.mean_bound(a,local,global_mask,counts,start,20.)
    assert v['shrunk_mean']>v['mean']


def test_confirmation_rejects_discovery_success_without_retuning():
    a,b,start,middle,end=halves();sa=np.linspace(-1,1,len(a));sb=sa.copy()
    a['net_r']=np.where(sa<-.6,-1.,1.)
    b['net_r']=-a.net_r.to_numpy()
    spec=r5.build_rules(a,sa,b,sb,start,middle,end)
    assert spec['discovery_profile']['positive'] and not spec['ranking_gate']
    for name in ('plateau','bad_tail','regime_tail'):assert not spec['rules'][name]['active']
    assert spec['rules']['bad_tail']['threshold']==np.quantile(sa,.2)


def test_stable_bad_tail_detected_and_application_outcome_free():
    a,b,start,middle,end=halves();s=np.linspace(-1,1,len(a))
    a['net_r']=np.where(s<-.6,-1.,1.);b['net_r']=a.net_r.to_numpy()
    spec=r5.build_rules(a,s,b,s,start,middle,end)
    rule=spec['rules']['bad_tail'];assert rule['active']
    k=r5.apply(rule,s,r5.regime_ids(a))
    assert (~k).sum()==24
    a['net_r']=99999.;a['exit_at_broker']+=999999999
    np.testing.assert_array_equal(k,r5.apply(rule,s,r5.regime_ids(a)))


def test_label_boundary_rejected():
    a,b,start,middle,end=halves();a.loc[0,'exit_at_broker']=middle
    with pytest.raises(ValueError):r5.build_rules(a,np.arange(len(a)),b,np.arange(len(b)),start,middle,end)


def test_inactive_rule_retains_all_and_bad_scores_rejected():
    rule=dict(name='plateau',active=False,threshold=None)
    assert r5.apply(rule,np.array([-1.,1.]),np.array([0,0])).all()
    with pytest.raises(ValueError):r5.apply(rule,np.array([np.nan]),np.array([0]))
