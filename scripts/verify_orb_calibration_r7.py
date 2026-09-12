"""Source replay with independently solved calibration intercepts."""
import json
import joblib
import numpy as np
import pandas as pd
from scipy.optimize import brentq
from scipy.special import expit,logit
from threadpoolctl import threadpool_limits
import orb_calibration_r7 as r7


def independent_offset(p,y,lam,minimum):
    if len(y)<minimum or min(sum(y),len(y)-sum(y))<5:return 0.
    z=logit(np.clip(p,1e-9,1-1e-9))
    def derivative(b):return float(np.sum(expit(z+b)-y)+lam*b)
    if derivative(-3)>=0:return -3.
    if derivative(3)<=0:return 3.
    return brentq(derivative,-3,3,xtol=1e-13)


def run():
    root=r7.ROOT;c=r7.verify_contract(root);frames,_=r7.r4.r3.prepare()
    states_checked=masks=raw_matches=rows_total=0
    for source in c['inputs']:
        ident=source['id'];f=frames[ident]
        for year in r7.r6.YEARS:
            folder=root/ident/str(year);assert r7.r4.checkpoint_valid(folder)
            states=json.loads((folder/'states.json').read_text());pred=pd.read_csv(folder/'predictions.csv')
            expected=json.loads((folder/'result.json').read_text())
            hashes=json.loads((folder/'model_hashes.json').read_text())
            cutoff,start,end=r7.r4.dates(year);te=r7.R.partition(f,start,end).reset_index(drop=True)
            hist=f.loc[(f.features_at_broker>=cutoff)&(f.features_at_broker<end)].reset_index(drop=True)
            for col in ('features_at_broker','entry_at_broker','exit_at_broker','net_r'):
                np.testing.assert_allclose(te[col],pred[col],rtol=1e-12,atol=1e-12)
            for kind in r7.KINDS:
                path=r7.r6.ROOT/ident/str(year)/(kind+'.research.joblib')
                assert r7.R.digest(path)==hashes[str(path)]
                m=joblib.load(path);hp=r7.r6.predict(m,hist)['probability'];tp=r7.r6.predict(m,te)['probability']
                scores={a:np.full(len(te),np.nan) for a in r7.ARMS};probs={a:np.full(len(te),np.nan) for a in r7.ARMS}
                for s in [x for x in states if x['kind']==kind]:
                    t=s['update'];ix=(hist.features_at_broker>=max(cutoff,t-365*86400)) & \
                        (hist.features_at_broker<t)&(hist.entry_at_broker<t)&(hist.exit_at_broker<t-86400)
                    cal=hist.loc[ix];y=(cal.net_r.to_numpy()>0).astype(float);p=hp[ix]
                    assert s['rows']==len(cal) and s['positive_rows']==int(y.sum())
                    assert s['last_label']==(int(cal.exit_at_broker.max()) if len(cal) else None)
                    b=independent_offset(p,y,10,40)
                    np.testing.assert_allclose(b,s['global_offset'],atol=1e-10,rtol=1e-10)
                    gp=r7.shift(p,b);reg=r7.r6.r5.regime_ids(cal)
                    local=[independent_offset(gp[reg==j],y[reg==j],25,30) for j in range(6)]
                    np.testing.assert_allclose(local,s['local_offsets'],atol=1e-10,rtol=1e-10)
                    for label,mask,v in [('gain',y==1,cal.net_r.to_numpy()),('loss',y==0,-cal.net_r.to_numpy())]:
                        mean=(v[mask].sum()+50*m[label+'_mean'])/(mask.sum()+50) if len(cal)>=40 else m[label+'_mean']
                        np.testing.assert_allclose(mean,s[label],atol=1e-12,rtol=1e-12)
                    changed=hist.copy();changed.loc[~ix,'net_r']=123456.
                    changed['exit_at_broker']=changed.exit_at_broker.astype('int64')
                    changed.loc[~ix,'exit_at_broker']+=999999999
                    rebuilt=r7.fit_state(changed,hp,m,t)
                    for key,value in rebuilt.items():assert value==s[key]
                    take=(te.features_at_broker>=t)&(te.features_at_broker<s['stop'])
                    if take.any():
                        np.testing.assert_array_equal(pred.loc[take,'update_at'],np.full(int(take.sum()),t))
                        for arm in r7.ARMS:
                            out=r7.apply_state(te.loc[take],tp[take],m,s,arm)
                            scores[arm][take],probs[arm][take]=out
                            mutated=te.loc[take].copy();mutated['net_r']=99999.
                            mutated['exit_at_broker']=mutated.exit_at_broker.astype('int64')+999999999
                            np.testing.assert_array_equal(out,r7.apply_state(mutated,tp[take],m,s,arm))
                    states_checked+=1
                for arm in r7.ARMS:
                    np.testing.assert_allclose(scores[arm],pred['score_'+kind+'__'+arm],atol=1e-10,rtol=1e-10)
                    np.testing.assert_allclose(probs[arm],pred['prob_'+kind+'__'+arm],atol=1e-10,rtol=1e-10)
                    k=scores[arm]>=0;np.testing.assert_array_equal(k,pred['keep_'+kind+'__'+arm].to_numpy(bool))
                    row=next(x for x in expected if x['kind']==kind and x['arm']==arm)
                    u=r7.r4.r3.utility(te,k)
                    for key in ('gain','skill','e','d'):np.testing.assert_allclose(u[key],row['test'][key],atol=1e-10,rtol=1e-10)
                    masks+=1
                old=pd.read_csv(r7.r6.ROOT/ident/str(year)/'predictions.csv')
                np.testing.assert_allclose(scores['raw'],old['score_'+kind],atol=1e-10,rtol=1e-10)
                np.testing.assert_array_equal(scores['raw']>=0,old['keep_'+kind+'__fixed_zero'].to_numpy(bool));raw_matches+=1
            if year!=2025:assert 'incumbent_keep' not in pred
            else:
                np.testing.assert_array_equal(r7.r4.r3.incumbent(source,te),pred.incumbent_keep.to_numpy(bool))
                fair=max(start,source['incumbent_information_end']+r7.R.GAP+1)
                np.testing.assert_array_equal(te.features_at_broker>=fair,pred.fair_pair.to_numpy(bool))
            rows_total+=len(te)
        print(ident,'verified',flush=True)
    assert states_checked==2288 and masks==880 and raw_matches==176
    r7.verify_contract(root)
    result=dict(monthly_states_checked=states_checked,masks_replayed=masks,r6_raw_matches=raw_matches,source_test_rows=rows_total,
        independent_intercept_solver_matches=True,unavailable_labels_do_not_change_state=True,
        future_outcomes_do_not_change_predictions=True,production_files_unchanged=len(c['production']),
        execution_replay_completed=False,prospective_shadow_completed=False,replacement_enabled=False)
    r7.R.dump(root/'verification.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':
    with threadpool_limits(limits=1):run()
