"""Own-strategy target decomposition with frozen settings, no deployment."""
import os
for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'):os.environ[key]='1'
from pathlib import Path
import argparse
import json
import time
import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.exceptions import ConvergenceWarning
from threadpoolctl import threadpool_limits
import warnings
import orb_veto_r5 as r5

R=r5.R;r4=r5.r4
ROOT=Path('logs/OrbTarget_R6_20260911')
KINDS=('direct','logistic_mean','hgb_mean','hgb_two_part')
POLICIES=('fixed_zero','confirmed_zero')
YEARS=(2022,2023,2024,2025)


def fit_family(tr,cutoff):
    if len(tr)<150 or tr.exit_at_broker.max()>=cutoff-R.GAP:raise ValueError('Invalid training boundary')
    identity=r4.r3.r2.identity(tr);x=r4.r3.returns.design(tr);y=tr.net_r.to_numpy(float)
    if not np.isfinite(x.to_numpy()).all() or not np.isfinite(y).all():raise ValueError('Invalid training values')
    win=y>0;counts=[int((~win).sum()),int(win.sum())]
    mu_gain=float(y[win].mean()) if win.any() else 0.
    mu_loss=float(-y[~win].mean()) if (~win).any() else 0.
    meta=dict(identity=identity,features=list(x.columns),rows=len(tr),cutoff=cutoff,
        last_label=int(tr.exit_at_broker.max()),positive_rows=counts[1],nonpositive_rows=counts[0],
        prevalence=float(win.mean()),train_mean=float(y.mean()),gain_mean=mu_gain,loss_mean=mu_loss)
    direct=r4.r3.returns.estimator('hgb_7');direct.fit(x,y)
    models={'direct':dict(kind='direct',model=direct,**meta)}
    for kind in ('logistic_mean','hgb_mean'):
        classifier=None
        if min(counts)>0:
            if kind=='logistic_mean':
                classifier=make_pipeline(StandardScaler(),LogisticRegression(C=.1,max_iter=2000,random_state=42))
            else:
                classifier=HistGradientBoostingClassifier(max_iter=80,max_leaf_nodes=7,min_samples_leaf=30,
                    l2_regularization=10,early_stopping=False,random_state=42)
            with warnings.catch_warnings():
                warnings.simplefilter('error',ConvergenceWarning)
                classifier.fit(x,win.astype(int))
        models[kind]=dict(kind=kind,classifier=classifier,single_class=min(counts)==0,**meta)
    heads={}
    for label,mask,target,mean in [('gain',win,y,mu_gain),('loss',~win,-y,mu_loss)]:
        n=int(mask.sum());model=None
        if n>=60:
            model=r4.r3.returns.estimator('hgb_7');model.fit(x.loc[mask],target[mask])
        heads[label]=dict(model=model,n=n,mean=mean,weight=n/(n+100.) if model is not None else 0.)
    models['hgb_two_part']=dict(models['hgb_mean'],kind='hgb_two_part',heads=heads)
    return models


def predict(model,f):
    if r4.r3.r2.identity(f)!=model['identity']:raise ValueError('Wrong model identity')
    x=r4.r3.returns.design(f)
    if list(x.columns)!=model['features']:raise ValueError('Wrong feature order')
    if model['kind']=='direct':
        s=model['model'].predict(x);p=None;gain=None;loss=None
    else:
        c=model['classifier']
        p=c.predict_proba(x)[:,1] if c is not None else np.full(len(f),model['prevalence'])
        gain=np.full(len(f),model['gain_mean']);loss=np.full(len(f),model['loss_mean'])
        if model['kind']=='hgb_two_part':
            for label in ('gain','loss'):
                h=model['heads'][label]
                value=np.full(len(f),h['mean'])
                if h['model'] is not None:
                    value=(1-h['weight'])*h['mean']+h['weight']*np.maximum(0,h['model'].predict(x))
                if label=='gain':gain=value
                else:loss=value
        s=p*gain-(1-p)*loss
    arrays=[s] if p is None else [s,p,gain,loss]
    if not all(np.isfinite(v).all() for v in arrays):raise ValueError('Nonfinite forecast')
    if p is not None and ((p<0).any() or (p>1).any() or (gain<0).any() or (loss<0).any()):
        raise ValueError('Invalid probability or severity')
    return dict(score=s,probability=p,gain=gain,loss=loss)


def confirm(a,sa,b,sb):
    return all(r5.admissible(f,s>=0) and r5.positive_veto(f,s>=0) for f,s in ((a,sa),(b,sb)))


def probability_stats(model,f,p):
    if p is None:return None
    y=(f.net_r.to_numpy()>0).astype(float);v=model['prevalence'];eps=1e-12
    q=np.clip(p,eps,1-eps);prior=np.clip(v,eps,1-eps)
    return dict(brier=float(np.mean((p-y)**2)),prior_brier=float(np.mean((v-y)**2)),
        log_loss=float(-np.mean(y*np.log(q)+(1-y)*np.log1p(-q))),
        prior_log_loss=float(-np.mean(y*np.log(prior)+(1-y)*np.log1p(-prior))))


def verify_contract(root):
    c=json.loads((root/'contract.json').read_text());r5.verify_inputs(r5.ROOT)
    if R.digest(r5.ROOT/'contract.json')!=c['r5_contract_sha']:raise ValueError('R5 changed')
    for p,sha in c['code'].items():
        if R.digest(p)!=sha:raise ValueError('R6 source changed')
    now=r4.production_snapshot();changed=[p for p,sha in c['production'].items() if now.get(p)!=sha]
    R.dump(root/'production_integrity.json',dict(files_checked=len(now),differences=changed))
    if changed:raise ValueError('Production changed')
    return c


def run(root):
    start_clock=time.monotonic();root.mkdir(parents=True,exist_ok=True)
    r5.verify_inputs(r5.ROOT);frames,sources=r4.r3.prepare()
    files=[Path(__file__),Path('scripts/orb_target_r6_report.py'),Path('docs/ORB_Target_R6_Protocol.md')]
    c=dict(policy='ORB_TARGET_R6',inputs=sources,years=list(YEARS),kinds=list(KINDS),policies=list(POLICIES),
        r5_contract_sha=R.digest(r5.ROOT/'contract.json'),code={str(p):R.digest(p) for p in files},
        production=r4.production_snapshot(),replacement_enabled=False,holdout_previously_inspected=True)
    cp=root/'contract.json'
    if cp.exists() and json.loads(cp.read_text())!=c:raise ValueError('Refusing changed contract')
    R.dump(cp,c);results=[]
    for index,source in enumerate(sources):
        ident=source['id'];f=frames[ident]
        for year in YEARS:
            folder=root/ident/str(year);folder.mkdir(parents=True,exist_ok=True)
            if r4.checkpoint_valid(folder):
                results.extend(json.loads((folder/'result.json').read_text()));continue
            cutoff,test,end=r4.dates(year);middle=R.stamp(f'{year}-03-09')
            tr=R.partition(f,r4.START,cutoff);a=R.partition(f,cutoff,middle);b=R.partition(f,middle,test)
            te=R.partition(f,test,end)
            if min(len(a),len(b),len(te))<20:raise ValueError('Insufficient calibration/test')
            models=fit_family(tr,cutoff);frozen={}
            for kind,m in models.items():
                sa=predict(m,a)['score'];sb=predict(m,b)['score']
                edges=np.quantile(sa,[.2,.4,.6,.8])
                frozen[kind]=dict(confirmed=confirm(a,sa,b,sb),edges=edges.tolist(),
                    discovery_profile=r5.profile(a,sa,edges),confirmation_profile=r5.profile(b,sb,edges),
                    discovery_label_max=int(a.exit_at_broker.max()),confirmation_label_max=int(b.exit_at_broker.max()))
                joblib.dump(m,folder/(kind+'.research.joblib'))
            R.dump(folder/'frozen_before_test.json',dict(policies=frozen,
                hashes={p.name:R.digest(p) for p in folder.glob('*.joblib')},test_start=test,test_end=end))
            rows=[];p=te[['strategy','symbol','features_at_broker','signal_bar_broker','entry_at_broker','exit_at_broker','net_r']].copy()
            for kind,m in models.items():
                values=predict(m,te);s=values['score'];p['score_'+kind]=s
                if values['probability'] is not None:
                    p['prob_'+kind]=values['probability'];p['gain_'+kind]=values['gain'];p['loss_'+kind]=values['loss']
                if kind=='direct' and year in r4.YEARS:
                    old=r4.ROOT/ident/str(year)
                    if not r4.checkpoint_valid(old):raise ValueError('R4 invalid')
                    prior=joblib.load(old/'hgb__all.research.joblib')
                    np.testing.assert_allclose(s,r4.predict(prior,te),rtol=1e-10,atol=1e-10)
                for policy in POLICIES:
                    active=policy=='fixed_zero' or frozen[kind]['confirmed']
                    k=s>=0 if active else np.ones(len(te),bool);p['keep_'+kind+'__'+policy]=k.astype(int)
                    sa=predict(m,a)['score'];sb=predict(m,b)['score']
                    da=r4.r3.utility(a,sa>=0 if active else np.ones(len(a),bool))
                    db=r4.r3.utility(b,sb>=0 if active else np.ones(len(b),bool))
                    rows.append(dict(id=ident,name=source['name'],year=year,kind=kind,policy=policy,active=active,
                        test=r4.r3.utility(te,k),discovery=da,confirmation=db,
                        selection_optimism=max(0.,da['e']-db['e']),
                        discovery_profile=frozen[kind]['discovery_profile'],confirmation_profile=frozen[kind]['confirmation_profile'],
                        test_profile=r5.profile(te,s,frozen[kind]['edges']),
                        test_probability=probability_stats(m,te,values['probability']),
                        mse=float(np.mean((s-te.net_r.to_numpy())**2)),
                        mean_baseline_mse=float(np.mean((m['train_mean']-te.net_r.to_numpy())**2))))
            if year==2025:
                p['incumbent_keep']=r4.r3.incumbent(source,te).astype(int)
                p['fair_pair']=(p.features_at_broker>=max(test,source['incumbent_information_end']+R.GAP+1)).astype(int)
            R.atomic_write(folder/'predictions.csv',p.to_csv(index=False).encode());R.dump(folder/'result.json',rows)
            R.dump(folder/'complete.json',{p.name:R.digest(p) for p in folder.iterdir() if p.is_file() and p.name!='complete.json'})
            results.extend(rows);print(index+1,ident,year,'4 models complete',flush=True)
            R.dump(root/'progress.json',dict(stage='training',models=len(results)//2,total_models=352))
    verify_contract(root);R.dump(root/'summary.json',results)
    R.dump(root/'progress.json',dict(stage='complete',models=len(results)//2,policies=len(results),
        elapsed_seconds=time.monotonic()-start_clock,replacement_enabled=False))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT);a=p.parse_args()
    with threadpool_limits(limits=1):run(a.out)
