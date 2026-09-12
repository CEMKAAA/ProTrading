"""Replay R8 using independently solved calibration equations; no orders or fitting."""
import json
import numpy as np
import pandas as pd
from scipy.optimize import brentq
from scipy.special import expit,logit
import orb_champion_calibration_r8 as r


def offset(p,y,penalty,minimum):
    if len(y)<minimum or min(sum(y),len(y)-sum(y))<5:return 0.
    z=logit(np.clip(p,1e-9,1-1e-9))
    def derivative(b):return float(np.sum(expit(z+b)-y)+penalty*b)
    if derivative(-3)>=0:return -3.
    if derivative(3)<=0:return 3.
    return brentq(derivative,-3,3,xtol=1e-13)


def run():
    contract=json.loads((r.ROOT/'contract.json').read_text())
    for p,h in contract['code'].items():assert r.R.digest(p)==h
    uf,us=r.r7.r4.r3.prepare();jf,js=r.jp.prepare();frames={**uf,**jf}
    results=json.loads((r.ROOT/'results.json').read_text());count=0;masks=0
    for source in contract['inputs']:
        ident=source['id'];kind=source['incumbent_kind'];f=frames[ident];information=source['incumbent_information_end']
        data=r.Path(source['incumbent']).read_bytes();assert r.R.digest(source['incumbent'])==source['incumbent_sha'];v=data.decode().splitlines()
        if kind=='MLP':p=r.portable_predict(data,f[r.FEATURES].to_numpy(float),source['incumbent_config']);threshold=float(v[6]);active=True
        else:p=r.predict_return(data,r.r7.r4.r3.returns.design(f).to_numpy(float));threshold=float(v[5]);active=v[6]=='1'
        ti=(f.features_at_broker>=r.START)&(f.features_at_broker>information+r.R.GAP)&(f.entry_at_broker<r.END)&(f.exit_at_broker<r.END-r.R.GAP)
        te=f.loc[ti].reset_index(drop=True);tp=p[ti];pred=pd.read_csv(r.ROOT/ident/'predictions.csv')
        np.testing.assert_allclose(tp,pred.legacy_score,atol=1e-12,rtol=1e-12)
        for s in json.loads((r.ROOT/ident/'states.json').read_text()):
            update=s['update'];ix=(f.features_at_broker>information+r.R.GAP)&(f.features_at_broker>=update-365*86400)&(f.features_at_broker<update)&(f.entry_at_broker<update)&(f.exit_at_broker<update-r.R.GAP)
            cal=f.loc[ix];cp=p[ix];y=cal.net_r.to_numpy();reg=r.r7.r6.r5.regime_ids(cal)
            assert len(cal)==s['rows'];assert not len(cal) or cal.exit_at_broker.max()<update-r.R.GAP
            if kind=='MLP':
                g=offset(cp,(y>0).astype(float),10,40);q=r.r7.shift(cp,g)
                local=[offset(q[reg==j],(y[reg==j]>0).astype(float),25,30) for j in range(6)]
            else:
                g=float(np.clip(np.mean(y-cp)*len(y)/(len(y)+50),-.25,.25)) if len(y)>=40 else 0.
                local=[]
                for j in range(6):
                    vals=(y-cp-g)[reg==j];n=len(vals)
                    local.append(float(np.clip(np.mean(vals)*n/(n+100),-.25,.25)) if n>=30 else 0.)
            np.testing.assert_allclose([g]+local,[s['global_offset']]+s['local_offsets'],atol=1e-11,rtol=0)
            changed=f.copy();changed.loc[~ix,'net_r']=10000
            assert r.fit_state(changed,p,kind,information,update)=={k:v for k,v in s.items() if k!='stop'}
            state=dict(s,global_offset=g,local_offsets=local);sel=(te.features_at_broker>=update)&(te.features_at_broker<s['stop'])
            for arm in ('global','regime'):
                score=r.apply(kind,tp[sel],r.r7.r6.r5.regime_ids(te.loc[sel]),state,arm)
                np.testing.assert_allclose(score,pred.loc[sel,arm+'_score'],atol=1e-10,rtol=1e-10)
                keep=score>=threshold if active else np.ones(len(score),bool)
                np.testing.assert_array_equal(keep,pred.loc[sel,arm+'_keep'].astype(bool));masks+=1
            count+=1
        for arm in ('global','regime'):
            rec=next(x for x in results if x['id']==ident and x['arm']==arm)
            stats=r.R.stats(te,pred[arm+'_keep'].astype(bool))
            for k in ('net_r','dd_r','trades','wins','losses'):np.testing.assert_allclose(stats[k],rec['new'][k],atol=1e-10)
    result=dict(strategies=49,states=count,monthly_masks=masks,independent_solver=True,unavailable_label_mutations=True,model_weights_unchanged=True,deployed=False)
    r.R.dump(r.ROOT/'verification.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':
    with r.threadpool_limits(limits=1):run()
