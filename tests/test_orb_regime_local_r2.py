from pathlib import Path
import sys
import numpy as np
import pandas as pd
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import orb_regime_local_r2 as r2


def sample(n=240):
    rng=np.random.default_rng(417)
    f=pd.DataFrame(rng.normal(size=(n,len(r2.r1.FEATURES))),columns=r2.r1.FEATURES)
    f['strategy']='A'; f['symbol']='JP225m';f['broker']='test'
    f['source_hash']='a'*64;f['config_hash']='b'*64;f['dataset_id']='A_data'
    f['entry']=100.;f['sl']=99.;f['tp']=102.;f['obs_atr14']=1.
    f['f_regime_valid']=1.;f['f_regime_age']=np.arange(n)%20
    for j in range(6): f['f_regime'+str(j)]=((np.arange(n)%4)==j).astype(float)
    f['f_rf_index']=0.;f['f_direction']=1.
    f['features_at_broker']=r2.r1.stamp('2022-01-01')+np.arange(n)*86400
    f['entry_at_broker']=f.features_at_broker+1
    f['exit_at_broker']=f.features_at_broker+3600
    f['net_r']=np.where(f.f_regime0==1,2.,-1.)+.1*rng.normal(size=n)
    return f


@pytest.mark.parametrize('key',r2.IDENTITY)
def test_mixed_identity_training_and_wrong_identity_prediction_rejected(key):
    f=sample();m=r2.fit(f,'local_hier_100')
    wrong=f.copy();wrong.loc[0,key]='WRONG'
    with pytest.raises(ValueError): r2.fit(wrong,'local_hier_100')
    wrong[key]='WRONG'
    with pytest.raises(ValueError): r2.predict(m,wrong)


@pytest.mark.parametrize('kind',r2.CANDIDATES)
def test_finite_fit_and_future_outcomes_not_used_in_prediction(kind):
    f=sample();m=r2.fit(f,kind)
    a=r2.predict(m,f)
    f['net_r']=99999.;f['exit_at_broker']+=99999999
    f['cost_r']=-99999.;f['label_win']=0
    np.testing.assert_array_equal(a,r2.predict(m,f))
    assert np.isfinite(a).all()
    assert not any(x in m['features'] for x in ['net_r','cost_r','exit_at_broker'])


def test_increasing_penalty_shrinks_total_regime_deviation_norm():
    f=sample()
    a=r2.fit(f,'local_hier_100');b=r2.fit(f,'local_hier_400')
    p=len(a['features'])
    da=a['model'].coef_[p:]*np.sqrt(100/a['penalty'])
    db=b['model'].coef_[p:]*np.sqrt(100/b['penalty'])
    assert np.linalg.norm(db)<np.linalg.norm(da)


def test_unseen_regime_has_zero_deviation_and_shared_fallback():
    f=sample();m=r2.fit(f,'local_hier_100')
    p=len(m['features']);coef=m['model'].coef_[p:].reshape(6,9)
    np.testing.assert_allclose(coef[4:],0.,atol=1e-12)
    a=f.iloc[:2].copy()
    for j in range(6): a['f_regime'+str(j)]=float(j==5)
    shared=r2.shared_design(a,m['kind']);z=m['scaler'].transform(shared)
    expected=m['model'].intercept_+z@m['model'].coef_[:p]
    np.testing.assert_allclose(r2.predict(m,a),expected,atol=1e-12)
    a['f_regime_valid']=0
    a['f_regime0']=1.;a['f_regime5']=0.
    np.testing.assert_allclose(r2.predict(m,a),expected,atol=1e-12)


def test_sparse_gate_not_renormalized_and_invalid_hot_vector_rejected():
    f=sample(100);x=r2.shared_design(f,'local_hier_100')
    z=x.to_numpy(float)
    for j in range(6): f['f_regime'+str(j)]=0.
    f.loc[0,'f_regime5']=1.
    a=r2.expand(z,f,list(x.columns),400.)
    block=a[:,len(x.columns):].reshape(100,6,9)
    assert block[0,5,0]==.5
    assert np.count_nonzero(block[:,5,0])==1
    f.loc[0,'f_regime0']=1.
    with pytest.raises(ValueError,match='one-hot'): r2.gates(f)


def test_strategy_regime_prediction_is_learned_not_calendar_hardcoded():
    f=sample();m=r2.fit(f,'local_hier_100')
    a=f.iloc[[0]].copy();b=a.copy()
    for j in range(6):
        a['f_regime'+str(j)]=float(j==0); b['f_regime'+str(j)]=float(j==1)
    assert r2.predict(m,a)[0]>r2.predict(m,b)[0]


def test_flat_and_base_reproduce_r1_local_benchmarks():
    f=sample()
    for new,old in [('local_base','local_base'),('local_flat_regime','local_regime')]:
        m=r2.fit(f,new);reference=r2.r1.fit_one(f,old,['A'])
        np.testing.assert_allclose(r2.predict(m,f),r2.r1.predict(reference,f),rtol=1e-12,atol=1e-12)


def test_selection_needs_positive_validation_and_retention():
    f=sample(100);scores=np.where(f.net_r>0,.2,-.2)
    # Only 25% winners: selection cannot cheat the >=50% retention constraint.
    d,t=r2.select(['A'],f,f,{('A','local_hier_100'):scores},{('A','local_hier_100'):scores})
    assert d['A']['kind']=='NO_VETO'
