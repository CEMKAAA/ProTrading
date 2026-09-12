from pathlib import Path
import sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from orb_calibration_r7_diagnostics import decompose,supported


def test_only_regime_composition_changes():
    a=np.array([1.,1.,-1.,-1.]);ar=np.array([0,0,1,1])
    b=np.array([1.,1.,1.,-1.]);br=np.array([0,0,0,1])
    r=decompose(a,b,ar,br)
    assert r['within']==0 and r['composition']==.5 and r['delta']==.5


def test_only_within_regime_changes():
    a=np.array([1.,1.,-1.,-1.]);ar=np.array([0,0,1,1])
    r=decompose(a,a+1,ar,ar)
    assert r['composition']==0 and r['within']==1 and r['delta']==1


def test_unseen_regime_is_disclosed_and_reconciles():
    r=decompose(np.array([1.,3.]),np.array([4.,8.]),np.array([0,0]),np.array([-1,1]))
    assert r['imputed_regimes']==[-1,1]
    assert np.isclose(r['composition']+r['within'],r['delta'])


def test_common_support_excludes_imputed_bucket():
    r=supported(np.array([1.,3.]),np.array([4.,8.]),np.array([0,0]),np.array([0,1]))
    assert r['common_test_fraction']==.5 and r['common_past_fraction']==1
    assert r['common_support']['imputed_regimes']==[]
    assert r['common_support']['delta']==2
