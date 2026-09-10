from pathlib import Path
import sys
import pandas as pd
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from orb_ml_selection_diagnostic import assess


def sample(keep):
    return pd.DataFrame(dict(entry_at_broker=[1514764800+i*86400 for i in range(4)],
        exit_at_broker=[1514768400+i*86400 for i in range(4)], net_r=[1,-1,1,-1],keep=keep))


def test_no_veto_has_zero_selection_value():
    r=assess(sample([1,1,1,1]),100)
    assert r['month_matched_excess_r']==0
    assert r['random_exceeds_fraction']==1


def test_known_perfect_selector_and_reproducibility():
    r=assess(sample([1,0,1,0]),100)
    assert r==assess(sample([1,0,1,0]),100)
    assert r['month_matched_expected_r']==0
    assert r['month_matched_excess_r']==2


def test_month_counts_remove_timing_exposure():
    f=sample([1,1,0,0]); f.loc[:1,'net_r']=1;f.loc[2:,'net_r']=-1
    for column in ['entry_at_broker','exit_at_broker']:
        f.loc[2:,column]+=32*86400
    r=assess(f,100)
    assert r['raw_improvement_r']==2
    assert r['month_matched_excess_r']==0


def test_invalid_prediction_rejected():
    f=sample([1,1,0,0]);f.loc[0,'net_r']=float('nan')
    with pytest.raises(ValueError):assess(f,100)
