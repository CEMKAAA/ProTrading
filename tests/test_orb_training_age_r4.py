from pathlib import Path
import sys
import numpy as np
import pandas as pd
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import orb_training_age_r4 as r4
import orb_training_age_r4_report as report
from test_orb_regime_local_r2 import sample


def history():
    f=sample(1000)
    f['features_at_broker']=pd.date_range('2018-01-01','2024-08-31',periods=len(f)).astype('int64')//10**9
    f['entry_at_broker']=f.features_at_broker+1
    f['exit_at_broker']=f.features_at_broker+3600
    return f


def test_training_windows_and_normalization():
    f=history();cut=r4.R.stamp('2024-09-09')
    parts={a:r4.training_slice(f,cut,a) for a in r4.ARMS}
    assert len(parts['trailing_3y'][0])<len(parts['trailing_5y'][0])<len(parts['all'][0])
    for a,(tr,w,meta) in parts.items():
        assert np.isclose(w.sum(),len(parts['all'][0]))
        assert tr.exit_at_broker.max()<cut-r4.R.GAP
        assert tr.features_at_broker.min()>=meta['lower']
    w=parts['decay_2y'][1]
    assert np.all(np.diff(w)>0)
    assert parts['decay_2y'][2]['effective_n']<parts['all'][2]['effective_n']
    assert np.isclose(w[-1]/w[0],2**((f.features_at_broker.iloc[-1]-f.features_at_broker.iloc[0])/86400/730.5))


@pytest.mark.parametrize('kind',r4.KINDS)
@pytest.mark.parametrize('arm',r4.ARMS)
def test_finite_predictions_label_independence_and_identity(kind,arm):
    f=history();tr,w,meta=r4.training_slice(f,r4.R.stamp('2024-09-09'),arm)
    m=r4.fit(tr,w,kind,meta);a=r4.predict(m,f)
    f['net_r']=99999.;f['exit_at_broker']+=999999999
    np.testing.assert_array_equal(a,r4.predict(m,f))
    f['strategy']='B'
    with pytest.raises(ValueError):r4.predict(m,f)


@pytest.mark.parametrize('kind',r4.KINDS)
def test_all_reproduces_r3(kind):
    f=history();tr,w,meta=r4.training_slice(f,r4.R.stamp('2024-09-09'),'all')
    a=r4.fit(tr,w,kind,meta);b=r4.r3.fit(tr,kind)
    np.testing.assert_allclose(r4.predict(a,f),r4.r3.predict(b,f),rtol=1e-12,atol=1e-12)


def test_future_labels_excluded_and_training_rejects_boundary():
    f=history();cut=r4.R.stamp('2024-09-09')
    f.loc[len(f)-1,'exit_at_broker']=cut
    tr,w,meta=r4.training_slice(f,cut,'all')
    assert len(tr)==len(f)-1
    tr.loc[tr.index[-1],'exit_at_broker']=cut
    with pytest.raises(ValueError):r4.fit(tr,w,'ridge',meta)


def test_folds_have_five_year_history_and_one_year_calibration():
    for year in r4.YEARS:
        fitend,start,end=r4.dates(year)
        assert (fitend-r4.START)/86400/365.25>5
        assert 365<= (start-fitend)/86400<=366
        assert (end-start)//86400==365


def test_score_penalties_and_daily_reconciliation():
    f=history();u=r4.r3.utility(f,np.arange(len(f))%2==0)
    row=dict(test=u,quarter_stability=0.,train_optimism=0.)
    a=report.score(row,u['gain'])['score']
    row['train_optimism']=.1
    assert np.isclose(report.score(row,u['gain'])['score'],a-10)
    assert report.score(row,u['gain']-5)['score']<a-10
    d=report.day_values(f,f.net_r.to_numpy(),r4.START,r4.R.stamp('2024-09-09'))
    np.testing.assert_allclose(d.sum(),f.net_r.sum())
