from pathlib import Path
import sys
import numpy as np
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import orb_calibration_r7 as r7
from test_orb_regime_local_r2 import sample


def setup():
    f=sample(240);f['net_r']=np.where(np.arange(len(f))%5==0,-1.,.5)
    m=dict(identity=r7.r4.r3.r2.identity(f),cutoff=int(f.features_at_broker.min()),gain_mean=.4,loss_mean=1.)
    update=int(f.features_at_broker.iloc[180]);p=np.linspace(.3,.8,len(f))
    return f,p,m,update


def test_month_schedule_and_delay_boundary():
    s=r7.schedule(r7.R.stamp('2022-09-09'),r7.R.stamp('2023-09-09'))
    assert len(s)==14 and s[1]==r7.R.stamp('2022-10-01')
    f,p,m,t=setup();f.loc[179,'exit_at_broker']=t-r7.R.GAP
    assert not r7.eligible(f,t,m['cutoff']).iloc[179]
    f.loc[179,'exit_at_broker']-=1
    assert r7.eligible(f,t,m['cutoff']).iloc[179]


def test_offset_fallback_shrinkage_and_rank():
    p=np.linspace(.1,.6,100);y=(np.arange(100)%5!=0).astype(float)
    a=r7.offset(p,y,10,40);b=r7.offset(p,y,100,40)
    assert 0<b<a<3
    np.testing.assert_array_equal(np.argsort(p),np.argsort(r7.shift(p,a)))
    assert r7.offset(p[:10],y[:10],10,40)==0
    assert r7.offset(p,np.ones(100),10,40)==0
    np.testing.assert_array_equal(r7.shift(np.array([0.,1.]),0),[0.,1.])


def test_unavailable_outcomes_cannot_change_state():
    f,p,m,t=setup();a=r7.fit_state(f,p,m,t)
    ix=~r7.eligible(f,t,m['cutoff']);f.loc[ix,'net_r']=999999.
    f['exit_at_broker']=f.exit_at_broker.astype('int64')
    f.loc[ix,'exit_at_broker']+=999999999
    assert r7.fit_state(f,p,m,t)==a
    f,p,m,t=setup();ix=r7.eligible(f,t,m['cutoff']);f.loc[ix,'net_r']=-1.
    assert r7.fit_state(f,p,m,t)!=a


@pytest.mark.parametrize('arm',r7.ARMS)
def test_prediction_outcome_independence_identity_and_finite(arm):
    f,p,m,t=setup();s=r7.fit_state(f,p,m,t);ix=f.features_at_broker>=t;te=f.loc[ix].copy()
    a=r7.apply_state(te,p[ix],m,s,arm)
    te['net_r']=99999.;te['exit_at_broker']=te.exit_at_broker.astype('int64')+999999999
    b=r7.apply_state(te,p[ix],m,s,arm)
    np.testing.assert_array_equal(a,b);assert np.isfinite(a).all()
    te['strategy']='OTHER'
    with pytest.raises(ValueError):r7.apply_state(te,p[ix],m,s,arm)
    with pytest.raises(ValueError):r7.apply_state(f.iloc[:2],p[:2],m,s,arm)


def test_sparse_regime_and_missing_class_magnitude_fallback():
    f,p,m,t=setup();f['net_r']=.5;s=r7.fit_state(f,p,m,t)
    assert s['loss']==m['loss_mean'] and s['global_offset']==0
    assert s['local_offsets']==[0.]*6
    ix=f.features_at_broker>=t;te=f.loc[ix].copy();te['f_regime_valid']=0
    np.testing.assert_array_equal(r7.apply_state(te,p[ix],m,s,'both'),r7.apply_state(te,p[ix],m,s,'regime_both'))


def test_raw_and_magnitude_probability_and_formula():
    f,p,m,t=setup();s=r7.fit_state(f,p,m,t);ix=f.features_at_broker>=t;te=f.loc[ix]
    raw,q=r7.apply_state(te,p[ix],m,s,'raw')
    np.testing.assert_array_equal(q,p[ix]);np.testing.assert_array_equal(raw,p[ix]*.4-(1-p[ix]))
    score,q=r7.apply_state(te,p[ix],m,s,'magnitude')
    np.testing.assert_array_equal(q,p[ix]);np.testing.assert_allclose(score,q*s['gain']-(1-q)*s['loss'])
