from pathlib import Path
import sys
import numpy as np
sys.path[:0]=[str(Path(__file__).resolve().parents[1]/'scripts'),str(Path(__file__).resolve().parent)]
import orb_jp225_r7 as jp
from test_orb_regime_local_r2 import sample


def test_coverage_is_counts_not_profit():
    f=sample(1200);a=jp.eligibility(f,2024);f['net_r']=-99999.
    assert jp.eligibility(f,2024)==a and a['eligible']
    assert not jp.eligibility(f.iloc[:30],2024)['eligible']


def test_training_family_identity_and_future_outcome_independence():
    f=sample(500);cut=int(f.exit_at_broker.max()+3*86400);m=jp.fit_models(f,cut)
    assert set(m)==set(jp.r7.KINDS)
    p=jp.r7.r6.predict(m['logistic_mean'],f)['probability'];f['net_r']=99999.
    np.testing.assert_array_equal(p,jp.r7.r6.predict(m['logistic_mean'],f)['probability'])
    assert m['logistic_mean']['last_label']<cut-jp.R.GAP


def test_same_frozen_r7_arms_and_update_schedule():
    assert jp.r7.ARMS==('raw','probability','magnitude','both','regime_both')
    assert len(jp.r7.schedule(jp.R.stamp('2025-09-09'),jp.END))==14
