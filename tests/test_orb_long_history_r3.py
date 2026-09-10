from pathlib import Path
import sys
import numpy as np
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import orb_long_history_r3 as r3
from test_orb_regime_local_r2 import sample
import orb_long_history_r3_report as report


def test_score_penalizes_instability_and_optimism():
    clean=[dict(training=dict(e=.1),validation=dict(e=.1,d=.0)) for _ in range(3)]
    assert np.isclose(r3.robust_score(clean)['score'],10.)
    over=[dict(training=dict(e=.3),validation=dict(e=.1,d=.0)) for _ in range(3)]
    assert r3.robust_score(over)['score']<0
    variable=[dict(training=dict(e=e),validation=dict(e=e,d=0)) for e in (0,.1,.2)]
    assert r3.robust_score(variable)['score']<r3.robust_score(clean)['score']
    assert r3.robust_score(clean[:2]) is None


def test_score_dd_is_not_only_objective():
    rows=[dict(training=dict(e=.5),validation=dict(e=-.2,d=.2)) for _ in range(3)]
    assert r3.robust_score(rows)['score']<0


@pytest.mark.parametrize('kind',r3.KINDS)
def test_models_do_not_read_scoring_labels_and_reject_wrong_strategy(kind):
    f=sample(300);f['label_win']=(f.net_r>0).astype(int)
    m=r3.fit(f,kind);a=r3.predict(m,f)
    f['net_r']=99999.;f['label_win']=1;f['exit_at_broker']+=999999
    np.testing.assert_array_equal(a,r3.predict(m,f))
    f['strategy']='other'
    with pytest.raises(ValueError):r3.predict(m,f)


def test_calibration_has_no_veto_and_retention_floor():
    f=sample(100)
    assert r3.calibrated(f,np.ones(len(f)), 'ridge') is not None
    t=r3.calibrated(f,np.where(f.net_r>0,.2,-.2),'ridge')
    assert (np.where(f.net_r>0,.2,-.2)>=t).mean()>=.4


def test_test_window_is_one_year_and_inner_folds_end_before_calibration():
    assert r3.END-r3.TEST==365*86400
    assert r3.r1.stamp('2024-09-09')==r3.CAL
    f=sample(300)
    boundary=int(f.features_at_broker.iloc[250])
    a=r3.r1.partition(f,0,boundary)
    assert a.exit_at_broker.max()<boundary-r3.r1.GAP


def test_matched_contrasts_reconcile_and_no_veto_score_is_zero():
    f=sample(100);keep=np.ones(len(f),bool)
    c=report.contrasts(f,keep)
    np.testing.assert_allclose(c.sum(axis=0),[0.,0.],atol=1e-10)
    u=r3.utility(f,keep);stability,_=report.quarter_stability(f,keep)
    assert abs(report.test_score(u,stability,0.)['score'])<1e-10
    keep=np.arange(len(f))%2==0
    u=r3.utility(f,keep);c=report.contrasts(f,keep)
    np.testing.assert_allclose(c.sum(axis=0),[u['gain'],u['skill']],atol=1e-10)


def test_uncertainty_penalty_cannot_reward_weaker_lower_bound():
    f=sample(100);u=r3.utility(f,np.arange(len(f))%2==0)
    high=report.test_score(u,0.,u['gain'])
    low=report.test_score(u,0.,u['gain']-10)
    assert low['score']<high['score']
    assert np.isclose(low['uncertainty_penalty']-high['uncertainty_penalty'],.1)
