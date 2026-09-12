from pathlib import Path
import sys
import numpy as np
import pandas as pd
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
sys.path.insert(0,str(Path(__file__).resolve().parent))
import orb_champion_calibration_r8 as r
from test_orb_regime_local_r2 import sample


def test_returns_shrinkage_bound_and_unknown_regime():
    p=np.zeros(100);y=np.full(100,10.);reg=np.zeros(100,int)
    g,l=r.correction('RIDGE',p,y,reg);assert g==.25 and l[0]==.25 and l[1:]==[0.]*5
    np.testing.assert_allclose(r.apply('RIDGE',p,reg,dict(global_offset=g,local_offsets=l),'regime'),.5)
    assert r.correction('RIDGE',p[:20],y[:20],reg[:20])==(0.,[0.]*6)


def test_only_unseen_closed_labels_enter_state():
    f=sample(240);p=np.full(len(f),.6);t=int(f.features_at_broker.iloc[200]);end=int(f.features_at_broker.iloc[100])
    a=r.fit_state(f,p,'MLP',end,t)
    changed=f.copy();unavailable=(f.features_at_broker<=end+r.R.GAP)|(f.features_at_broker>=t)|(f.exit_at_broker>=t-r.R.GAP)|(f.entry_at_broker>=t)
    changed.loc[unavailable,'net_r']=1000
    assert a==r.fit_state(changed,p,'MLP',end,t)
    assert a['first_feature'] is None or a['first_feature']>end+r.R.GAP
    assert a['last_label'] is None or a['last_label']<t-r.R.GAP


def test_raw_unchanged_and_global_order_preserved():
    p=np.linspace(.01,.99,100);reg=np.zeros(100,int);s=dict(global_offset=.3,local_offsets=[0.]*6)
    np.testing.assert_array_equal(r.apply('MLP',p,reg,s,'raw'),p)
    assert (np.diff(r.apply('MLP',p,reg,s,'global'))>0).all()
