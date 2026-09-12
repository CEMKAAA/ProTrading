from pathlib import Path
import sys
import numpy as np
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import orb_target_r6 as r6
from test_orb_regime_local_r2 import sample


@pytest.fixture(scope='module')
def fitted():
    f=sample(400);cut=int(f.exit_at_broker.max()+3*86400)
    return f,r6.fit_family(f,cut)


@pytest.mark.parametrize('kind',r6.KINDS)
def test_predictions_are_finite_and_outcome_independent(fitted,kind):
    f,models=fitted;m=models[kind];before=r6.predict(m,f)
    changed=f.copy();changed['net_r']=99999.;changed['label_win']=0;changed['exit_at_broker']+=999999999
    after=r6.predict(m,changed)
    np.testing.assert_array_equal(before['score'],after['score'])
    if before['probability'] is not None:
        np.testing.assert_allclose(before['score'],before['probability']*before['gain']-(1-before['probability'])*before['loss'])
    changed['strategy']='B'
    with pytest.raises(ValueError):r6.predict(m,changed)


def test_probability_head_identical_and_mean_identity(fitted):
    f,models=fitted
    np.testing.assert_array_equal(r6.predict(models['hgb_mean'],f)['probability'],r6.predict(models['hgb_two_part'],f)['probability'])
    m=models['hgb_mean']
    assert np.isclose(m['prevalence']*m['gain_mean']-(1-m['prevalence'])*m['loss_mean'],f.net_r.mean())


def test_boundary_rejected_and_direct_matches_reference(fitted):
    f,models=fitted
    with pytest.raises(ValueError):r6.fit_family(f,int(f.exit_at_broker.max()))
    old=r6.r4.r3.fit(f,'hgb')
    np.testing.assert_allclose(r6.predict(models['direct'],f)['score'],r6.r4.r3.predict(old,f))


def test_sparse_loss_head_falls_back_and_single_class_safe():
    f=sample(200);f['net_r']=.2;f.loc[:9,'net_r']=-1
    m=r6.fit_family(f,int(f.exit_at_broker.max()+3*86400))['hgb_two_part']
    assert m['heads']['loss']['model'] is None and m['heads']['loss']['weight']==0
    np.testing.assert_array_equal(r6.predict(m,f)['loss'],np.ones(len(f)))
    f['net_r']=.2
    m=r6.fit_family(f,int(f.exit_at_broker.max()+3*86400))['hgb_mean']
    assert m['single_class']
    np.testing.assert_allclose(r6.predict(m,f)['score'],.2)


def test_probability_loss_uses_net_positive_and_no_fake_direct_probability(fitted):
    f,models=fitted
    assert r6.probability_stats(models['direct'],f,None) is None
    p=r6.predict(models['hgb_mean'],f)['probability']
    s=r6.probability_stats(models['hgb_mean'],f,p)
    assert np.isclose(s['brier'],np.mean((p-(f.net_r.to_numpy()>0))**2))
