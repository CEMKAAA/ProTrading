"""JP225 R7 source refit and causal calibration replay; no terminal access."""
import json
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_jp225_r7 as jp
from verify_orb_calibration_r7 import independent_offset


def verify_state(hist,hp,m,s):
    r7=jp.r7;t=s['update'];rebuilt=r7.fit_state(hist,hp,m,t)
    for key,value in rebuilt.items():assert value==s[key]
    ix=r7.eligible(hist,t,m['cutoff']);cal=hist.loc[ix];p=hp[ix];y=(cal.net_r.to_numpy()>0).astype(float)
    b=independent_offset(p,y,10,40);np.testing.assert_allclose(b,s['global_offset'],atol=1e-10,rtol=1e-10)
    gp=r7.shift(p,b);reg=r7.r6.r5.regime_ids(cal)
    local=[independent_offset(gp[reg==j],y[reg==j],25,30) for j in range(6)]
    np.testing.assert_allclose(local,s['local_offsets'],atol=1e-10,rtol=1e-10)
    changed=hist.copy();changed['exit_at_broker']=changed.exit_at_broker.astype('int64')
    changed.loc[~ix,'net_r']=123456.;changed.loc[~ix,'exit_at_broker']+=999999999
    assert r7.fit_state(changed,hp,m,t)==rebuilt


def run():
    root=jp.ROOT;c=jp.verify_contract(root);frames,_=jp.prepare();r7=jp.r7
    coverage=json.loads((root/'coverage.json').read_text());folds=masks=states=refits=forwards=0
    for source in c['inputs']:
        ident=source['id'];f=frames[ident]
        for year in jp.YEARS:
            cover=next(x for x in coverage if x['id']==ident and x['year']==year)
            assert cover==dict(id=ident,**jp.eligibility(f,year))
            if not cover['eligible']:continue
            folder=root/ident/str(year);assert r7.r4.checkpoint_valid(folder)
            cutoff,start,end=r7.r4.dates(year);te=jp.R.partition(f,start,end).reset_index(drop=True)
            hist=f.loc[(f.features_at_broker>=cutoff)&(f.features_at_broker<end)].reset_index(drop=True)
            saved=pd.read_csv(folder/'predictions.csv');snapshots=json.loads((folder/'states.json').read_text())
            expected=json.loads((folder/'result.json').read_text());reference=jp.fit_models(f,cutoff)
            for col in ('features_at_broker','entry_at_broker','exit_at_broker','net_r'):
                np.testing.assert_allclose(te[col],saved[col],atol=1e-12,rtol=1e-12)
            for kind in r7.KINDS:
                m=joblib.load(folder/(kind+'.research.joblib'))
                assert m['last_label']<cutoff-jp.R.GAP
                hp=r7.r6.predict(m,hist)['probability'];tp=r7.r6.predict(m,te)['probability']
                np.testing.assert_array_equal(tp,r7.r6.predict(reference[kind],te)['probability']);refits+=1
                for s in [x for x in snapshots if x['kind']==kind]:
                    verify_state(hist,hp,m,s);states+=1
                    ix=(te.features_at_broker>=s['update'])&(te.features_at_broker<s['stop'])
                    if not ix.any():continue
                    for arm in r7.ARMS:
                        score,q=r7.apply_state(te.loc[ix],tp[ix],m,s,arm)
                        np.testing.assert_allclose(score,saved.loc[ix,'score_'+kind+'__'+arm],atol=1e-10,rtol=1e-10)
                        np.testing.assert_allclose(q,saved.loc[ix,'prob_'+kind+'__'+arm],atol=1e-10,rtol=1e-10)
                        np.testing.assert_array_equal(score>=0,saved.loc[ix,'keep_'+kind+'__'+arm].to_numpy(bool))
                        changed=te.loc[ix].copy();changed['net_r']=99999.
                        np.testing.assert_array_equal(score,r7.apply_state(changed,tp[ix],m,s,arm)[0])
                for arm in r7.ARMS:
                    k=saved['keep_'+kind+'__'+arm].to_numpy(bool);u=r7.r4.r3.utility(te,k)
                    row=next(x for x in expected if x['kind']==kind and x['arm']==arm)
                    for key in ('gain','skill','e','d'):np.testing.assert_allclose(u[key],row['test'][key],atol=1e-10,rtol=1e-10)
                    masks+=1
            if year==2025 and source['incumbent_available']:
                np.testing.assert_array_equal(r7.r4.r3.incumbent(source,te),saved.incumbent_keep.to_numpy(bool))
                np.testing.assert_array_equal(te.features_at_broker>=max(start,source['incumbent_information_end']+jp.R.GAP+1),saved.fair_pair.to_numpy(bool))
            else:assert 'incumbent_keep' not in saved
            folds+=1
        folder=root/ident/'forward_20260909';assert r7.r4.checkpoint_valid(folder)
        cutoff=jp.R.stamp('2025-09-09');reference=jp.fit_models(f,cutoff)
        hist=f.loc[(f.features_at_broker>=cutoff)&(f.features_at_broker<jp.END)].copy()
        snapshots=json.loads((folder/'states.json').read_text())
        for kind in r7.KINDS:
            m=joblib.load(folder/(kind+'.research.joblib'));assert m['last_label']<cutoff-jp.R.GAP
            hp=r7.r6.predict(m,hist)['probability'];np.testing.assert_array_equal(hp,r7.r6.predict(reference[kind],hist)['probability'])
            verify_state(hist,hp,m,snapshots[kind]);forwards+=1;refits+=1
        print(ident,'verified',flush=True)
    assert folds==55 and masks==550 and states==1430 and forwards==60 and refits==170
    jp.verify_contract(root)
    result=dict(historical_folds=folds,historical_masks=masks,monthly_states=states,forward_models=forwards,
        source_refits=refits,independent_intercept_solver_matches=True,unavailable_outcomes_invariant=True,
        production_files_unchanged=len(c['production']),forward_subsequent_test_completed=False,
        execution_replay_completed=False,prospective_shadow_completed=False,replacement_enabled=False)
    jp.R.dump(root/'verification.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':
    with threadpool_limits(limits=1):run()
