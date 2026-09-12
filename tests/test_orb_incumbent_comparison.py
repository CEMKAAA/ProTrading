from pathlib import Path
import sys
import numpy as np
import pandas as pd
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import compare_orb_incumbents_r7 as c


def test_decision_changes_reconcile():
    f=pd.DataFrame({'net_r':[1.,-1.,.2,-.4]})
    x=c.decision_delta(f,np.array([1,1,0,0],bool),np.array([1,0,1,0],bool))
    assert x['added']==1 and x['removed']==1 and x['both']==1 and x['neither']==1
    assert np.isclose(x['delta_r'],1.2)


def test_frontier_does_not_call_a_tradeoff_a_win():
    assert c.classification(1,1)=='TRADEOFF'
    assert c.classification(-1,-1)=='TRADEOFF'
    assert c.classification(1,0)=='NEW_PNL_DD_FRONTIER'
    assert c.classification(-1,0)=='CURRENT_PNL_DD_FRONTIER'
    assert c.classification(0,0)=='SAME'


def test_extra_cost_and_quarter_reconciliation():
    t=[c.r7.R.stamp(x) for x in ['2025-10-01','2026-01-01','2026-04-01','2026-07-01']]
    f=pd.DataFrame({'entry_at_broker':t,'exit_at_broker':t,'net_r':[1.,-1.,.2,-.4]})
    x=c.extra(f,np.ones(4,bool));assert np.isclose(sum(x['quarters']),x['net_r'])
    assert np.isclose(x['extra_cost']['0.05'],x['net_r']-.2)
    assert np.isclose(x['profit_factor'],1.2/1.4)
