"""Causal monthly probability/decision calibration, isolated from production."""
import argparse
import json
import time
from pathlib import Path
import joblib
import numpy as np
import pandas as pd
from scipy.special import expit, logit
from threadpoolctl import threadpool_limits
import orb_target_r6 as r6

R=r6.R; r4=r6.r4
ROOT=Path('logs/OrbCalibration_R7_20260911')
KINDS=('logistic_mean','hgb_mean')
ARMS=('raw','probability','magnitude','both','regime_both')
WINDOW=365*86400


def schedule(start,end):
    months=pd.date_range(pd.Timestamp(start,unit='s',tz='UTC').normalize(),
        pd.Timestamp(end,unit='s',tz='UTC'),freq='MS')
    return [start]+[int(x.timestamp()) for x in months if start<x.timestamp()<end]+[end]


def eligible(f,update,cutoff):
    return (f.features_at_broker>=max(cutoff,update-WINDOW)) & (f.features_at_broker<update) & \
        (f.entry_at_broker<update) & (f.exit_at_broker<update-R.GAP)


def offset(p,y,penalty,minimum):
    p=np.asarray(p,float);y=np.asarray(y,float)
    if not np.isfinite(p).all() or not np.isin(y,[0.,1.]).all() or ((p<0)|(p>1)).any():
        raise ValueError('Invalid calibration input')
    if len(p)!=len(y):raise ValueError('Mismatched labels')
    if len(y)<minimum or min(y.sum(),len(y)-y.sum())<5:return 0.
    z=logit(np.clip(p,1e-9,1-1e-9));lo=-3.;hi=3.
    for _ in range(60):
        mid=(lo+hi)/2
        if np.sum(expit(z+mid)-y)+penalty*mid>0:hi=mid
        else:lo=mid
    return (lo+hi)/2


def shift(p,b):
    p=np.asarray(p,float);b=np.broadcast_to(b,p.shape)
    return np.where(b==0,p,expit(logit(np.clip(p,1e-9,1-1e-9))+b))


def fit_state(f,p,model,update):
    if r4.r3.r2.identity(f)!=model['identity']:raise ValueError('Wrong calibration identity')
    if len(f)!=len(p):raise ValueError('Wrong probability rows')
    ix=eligible(f,update,model['cutoff']).to_numpy();cal=f.loc[ix];cp=np.asarray(p)[ix]
    y=(cal.net_r.to_numpy()>0).astype(float);b=offset(cp,y,10,40)
    reg=r6.r5.regime_ids(cal);gp=shift(cp,b)
    local=[offset(gp[reg==j],y[reg==j],25,30) for j in range(6)]
    magnitude={}
    for label,mask,values in [('gain',y==1,cal.net_r.to_numpy()),('loss',y==0,-cal.net_r.to_numpy())]:
        prior=model[label+'_mean'];n=int(mask.sum())
        magnitude[label]=(float(values[mask].sum())+50*prior)/(n+50) if len(cal)>=40 else prior
    return dict(identity=model['identity'],update=int(update),training_cutoff=model['cutoff'],
        rows=len(cal),positive_rows=int(y.sum()),last_label=int(cal.exit_at_broker.max()) if len(cal) else None,
        first_feature=int(cal.features_at_broker.min()) if len(cal) else None,
        global_offset=float(b),local_offsets=local,regime_rows=[int((reg==j).sum()) for j in range(6)],
        gain=float(magnitude['gain']),loss=float(magnitude['loss']))


def apply_state(f,p,model,state,arm):
    if arm not in ARMS:raise ValueError('Unknown arm')
    if r4.r3.r2.identity(f)!=state['identity'] or state['identity']!=model['identity']:
        raise ValueError('Wrong prediction identity')
    if (f.features_at_broker<state['update']).any():raise ValueError('Future state used on earlier row')
    p=np.asarray(p,float)
    if len(p)!=len(f) or not np.isfinite(p).all() or ((p<0)|(p>1)).any():raise ValueError('Invalid probabilities')
    q=p.copy()
    if arm in ('probability','both','regime_both'):q=shift(q,state['global_offset'])
    if arm=='regime_both':
        reg=r6.r5.regime_ids(f)
        b=np.array([state['local_offsets'][i] if i>=0 else 0. for i in reg])
        q=shift(q,b)
    use=arm in ('magnitude','both','regime_both')
    gain=state['gain'] if use else model['gain_mean'];loss=state['loss'] if use else model['loss_mean']
    score=q*gain-(1-q)*loss
    if not np.isfinite(score).all() or min(gain,loss)<0:raise ValueError('Invalid calibrated score')
    return score,q


def verify_contract(root):
    c=json.loads((root/'contract.json').read_text());r6.verify_contract(r6.ROOT)
    if R.digest(r6.ROOT/'contract.json')!=c['r6_contract_sha']:raise ValueError('R6 changed')
    for path,sha in c['code'].items():
        if R.digest(path)!=sha:raise ValueError('Frozen R7 source changed: '+path)
    now=r4.production_snapshot();changed=[p for p,sha in c['production'].items() if now.get(p)!=sha]
    R.dump(root/'production_integrity.json',dict(files_checked=len(now),differences=changed))
    if changed:raise ValueError('Production changed')
    return c


def run(root):
    clock=time.monotonic();root.mkdir(parents=True,exist_ok=True)
    r6.verify_contract(r6.ROOT);frames,sources=r4.r3.prepare()
    files=[Path(__file__),Path('scripts/orb_calibration_r7_report.py'),Path('scripts/verify_orb_calibration_r7.py'),
        Path('tests/test_orb_calibration_r7.py'),Path('docs/ORB_Calibration_R7_Protocol.md')]
    c=dict(policy='ORB_CALIBRATION_R7',inputs=sources,kinds=KINDS,arms=ARMS,years=r6.YEARS,
        r6_contract_sha=R.digest(r6.ROOT/'contract.json'),code={str(p):R.digest(p) for p in files},
        production=r4.production_snapshot(),replacement_enabled=False,holdout_previously_inspected=True)
    c=json.loads(json.dumps(c));cp=root/'contract.json'
    if cp.exists() and json.loads(cp.read_text())!=c:raise ValueError('Changed R7 contract')
    R.dump(cp,c);results=[];states_count=0
    for index,source in enumerate(sources):
        ident=source['id'];f=frames[ident]
        for year in r6.YEARS:
            folder=root/ident/str(year);folder.mkdir(parents=True,exist_ok=True)
            if r4.checkpoint_valid(folder):
                results.extend(json.loads((folder/'result.json').read_text()))
                states_count+=len(json.loads((folder/'states.json').read_text()))
                continue
            old=r6.ROOT/ident/str(year)
            if not r4.checkpoint_valid(old):raise ValueError('R6 artifact changed')
            cutoff,start,end=r4.dates(year);te=R.partition(f,start,end).reset_index(drop=True)
            history=f.loc[(f.features_at_broker>=cutoff)&(f.features_at_broker<end)].reset_index(drop=True)
            saved=pd.read_csv(old/'predictions.csv');bounds=schedule(start,end)
            pred=te[['strategy','symbol','features_at_broker','signal_bar_broker','entry_at_broker','exit_at_broker','net_r']].copy()
            pred['regime']=r6.r5.regime_ids(te);rows=[];states=[];model_hashes={}
            for kind in KINDS:
                path=old/(kind+'.research.joblib');model_hashes[str(path)]=R.digest(path);m=joblib.load(path)
                hp=r6.predict(m,history)['probability'];tp=r6.predict(m,te)['probability']
                scores={a:np.full(len(te),np.nan) for a in ARMS};probs={a:np.full(len(te),np.nan) for a in ARMS}
                for update,stop in zip(bounds,bounds[1:]):
                    state=fit_state(history,hp,m,update);state['stop']=stop;state['kind']=kind;states.append(state)
                    ix=(te.features_at_broker>=update)&(te.features_at_broker<stop)
                    if not ix.any():continue
                    pred.loc[ix,'update_at']=update
                    for arm in ARMS:
                        scores[arm][ix],probs[arm][ix]=apply_state(te.loc[ix],tp[ix],m,state,arm)
                for arm in ARMS:
                    s=scores[arm];q=probs[arm]
                    if not np.isfinite(s).all():raise ValueError('Incomplete predictions')
                    k=s>=0;pred['score_'+kind+'__'+arm]=s;pred['prob_'+kind+'__'+arm]=q
                    pred['keep_'+kind+'__'+arm]=k.astype(int)
                    rows.append(dict(id=ident,name=source['name'],year=year,kind=kind,arm=arm,
                        test=r4.r3.utility(te,k),probability=r6.probability_stats(m,te,q),
                        probability_bias=float(q.mean()-(te.net_r.to_numpy()>0).mean())))
                np.testing.assert_allclose(scores['raw'],saved['score_'+kind],rtol=1e-10,atol=1e-10)
                np.testing.assert_array_equal(scores['raw']>=0,saved['keep_'+kind+'__fixed_zero'].to_numpy(bool))
            if year==2025:
                pred['incumbent_keep']=saved.incumbent_keep;pred['fair_pair']=saved.fair_pair
            R.dump(folder/'states.json',states);R.dump(folder/'model_hashes.json',model_hashes)
            R.dump(folder/'result.json',rows);R.atomic_write(folder/'predictions.csv',pred.to_csv(index=False).encode())
            R.dump(folder/'complete.json',{p.name:R.digest(p) for p in folder.iterdir() if p.is_file() and p.name!='complete.json'})
            results.extend(rows);states_count+=len(states)
            R.dump(root/'progress.json',dict(stage='running',outcomes=len(results),total=880,states=states_count))
            print(index+1,ident,year,'complete',flush=True)
    verify_contract(root);R.dump(root/'summary.json',results)
    R.dump(root/'progress.json',dict(stage='complete',outcomes=len(results),states=states_count,
        elapsed_seconds=time.monotonic()-clock,replacement_enabled=False))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT);a=p.parse_args()
    with threadpool_limits(limits=1):run(a.out)
