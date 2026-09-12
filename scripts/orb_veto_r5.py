"""Frozen score-to-veto policy research. No retraining or deployment."""
import os
for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'):
    os.environ[key]='1'
from pathlib import Path
import argparse
import json
import time
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_training_age_r4 as r4

R=r4.R
ROOT=Path('logs/OrbVeto_R5_20260911')
POLICIES=('fixed_zero','plateau','bad_tail','regime_tail')
GRID=(-.10,-.05,0.,.025,.05,.10,.15,.20)


def regime_ids(f):
    a=f[['f_regime'+str(i) for i in range(6)]].to_numpy(float)
    ok=(f.f_regime_valid.to_numpy()==1)&np.isfinite(a).all(axis=1)
    ok &= np.isclose(a.sum(axis=1),1)&np.isin(a,[0.,1.]).all(axis=1)
    return np.where(ok,np.argmax(a,axis=1),-1)


def profile(f,scores,edges):
    if not np.isfinite(scores).all():raise ValueError('Nonfinite profile score')
    bins=np.searchsorted(edges,scores,side='right')
    rows=[]
    for b in range(5):
        sub=f.loc[bins==b];n=len(sub)
        rows.append(dict(bin=b,n=n,mean_r=float(sub.net_r.mean()) if n else None,
                         wr=float((sub.net_r>0).mean()) if n else None))
    sx=pd.Series(scores).rank().to_numpy();sy=f.net_r.rank().to_numpy()
    rho=float(np.corrcoef(sx,sy)[0,1]) if np.std(sx)>0 and np.std(sy)>0 else None
    spread=rows[-1]['mean_r']-rows[0]['mean_r'] if rows[-1]['n'] and rows[0]['n'] else None
    return dict(bins=rows,spearman=rho,top_bottom_r=spread,
                positive=bool(rho is not None and rho>0 and spread is not None and spread>0))


def bootstrap_counts(start,end,block,draws=2000):
    days=(end-start)//86400+1
    rng=np.random.default_rng(20260911+block)
    seeds=rng.integers(days,size=(draws,(days+block-1)//block))
    indices=((seeds[:,:,None]+np.arange(block))%days).reshape(draws,-1)[:,:days]
    return np.stack([np.bincount(x,minlength=days) for x in indices]).astype(float)


def mean_bound(f,local,global_mask,counts,start,prior=0.):
    n=int(local.sum());g=int(global_mask.sum())
    if n==0 or g==0:return dict(n=n,mean=None,shrunk_mean=None,upper=None,empty_fraction=1.)
    ix=(f.exit_at_broker.to_numpy(np.int64)//86400-start//86400).astype(int)
    y=f.net_r.to_numpy(float)
    daily=np.zeros((counts.shape[1],4))
    for col,values in enumerate((y*local,local.astype(float),y*global_mask,global_mask.astype(float))):
        np.add.at(daily[:,col],ix,values)
    draws=counts@daily
    valid=(draws[:,1]>0)&(draws[:,3]>0)
    distribution=np.full(len(counts),np.inf)
    distribution[valid]=(draws[valid,0]+prior*draws[valid,2]/draws[valid,3])/(draws[valid,1]+prior)
    empty=float(1-valid.mean())
    upper=float(np.quantile(distribution,.9,method='higher')) if empty<=.1 else None
    if upper is not None and not np.isfinite(upper):upper=None
    return dict(n=n,mean=float(y[local].mean()),
        shrunk_mean=float((y[local].sum()+prior*y[global_mask].mean())/(n+prior)),
        upper=upper,empty_fraction=empty)


def bounds(f,mask,global_mask,count_sets,start,prior=0.):
    result={str(b):mean_bound(f,mask,global_mask,c,start,prior) for b,c in count_sets.items()}
    return result


def negative_evidence(details,min_n):
    return all(x['n']>=min_n and x['mean'] is not None and x['mean']<0 and
               x['upper'] is not None and x['upper']<0 for x in details.values())


def admissible(f,k):
    return bool(k.sum()>=20 and (~k).sum()>=10 and k.mean()>=.4)


def positive_veto(f,k):
    u=r4.r3.utility(f,k)
    return bool(u['gain']>0 and u['skill']>0)


def apply(rule,scores,regimes):
    if not np.isfinite(scores).all():raise ValueError('Invalid model score')
    if len(scores)!=len(regimes):raise ValueError('Length mismatch')
    keep=np.ones(len(scores),bool)
    if not rule['active']:return keep
    if rule['name']=='regime_only':return ~np.isin(regimes,rule['regimes'])
    blocked=scores<rule['threshold']
    if rule['name']=='regime_tail':blocked &= np.isin(regimes,rule['regimes'])
    return ~blocked


def build_rules(a,sa,b,sb,start,middle,end):
    if not len(a) or not len(b):raise ValueError('Empty calibration half')
    if a.exit_at_broker.max()>=middle-R.GAP or b.exit_at_broker.max()>=end-R.GAP:
        raise ValueError('Calibration leakage')
    edges=np.quantile(sa,[.2,.4,.6,.8]);pa=profile(a,sa,edges);pb=profile(b,sb,edges)
    ranking=pa['positive'] and pb['positive']
    threshold=float(edges[0]);ra=regime_ids(a);rb=regime_ids(b)
    ca={n:bootstrap_counts(start,middle,n) for n in (5,20)}
    cb={n:bootstrap_counts(middle,end,n) for n in (5,20)}
    rules={'fixed_zero':dict(name='fixed_zero',active=True,threshold=0.)}
    grid=[]
    for t in GRID:
        k=sa>=t;u=r4.r3.utility(a,k)
        grid.append(dict(threshold=t,edge=u['e'],admissible=admissible(a,k),kept=int(k.sum())))
    choices=[]
    for i in range(1,len(grid)-1):
        triplet=grid[i-1:i+2]
        if all(x['admissible'] and x['edge']>0 for x in triplet):
            choices.append((min(x['edge'] for x in triplet),grid[i]['kept'],-grid[i]['threshold'],grid[i]['threshold']))
    t=max(choices)[3] if choices else None
    active=bool(ranking and t is not None and admissible(b,sb>=t) and positive_veto(b,sb>=t))
    rules['plateau']=dict(name='plateau',active=active,threshold=t,grid=grid,
                         ranking_pass=ranking,discovery_plateau_found=bool(choices))
    ta=sa<threshold;tb=sb<threshold
    ba=bounds(a,ta,ta,ca,start);bb=bounds(b,tb,tb,cb,middle)
    rules['bad_tail']=dict(name='bad_tail',threshold=threshold,
        active=bool(ranking and negative_evidence(ba,15) and negative_evidence(bb,10)),
        discovery=ba,confirmation=bb,ranking_pass=ranking)
    for name,use_tail in [('regime_tail',True),('regime_only',False)]:
        ga=ta if use_tail else np.ones(len(a),bool);gb=tb if use_tail else np.ones(len(b),bool)
        regimes=[];evidence=[]
        for rid in range(6):
            la=ga&(ra==rid);lb=gb&(rb==rid)
            da=bounds(a,la,ga,ca,start,20.);db=bounds(b,lb,gb,cb,middle,20.)
            good=negative_evidence(da,8) and negative_evidence(db,5)
            if use_tail:good=good and ranking and positive_veto(a,~la) and positive_veto(b,~lb)
            if good:regimes.append(rid)
            evidence.append(dict(regime=rid,discovery=da,confirmation=db,enabled=bool(good)))
        rules[name]=dict(name=name,active=bool(regimes),threshold=threshold if use_tail else None,
                         regimes=regimes,evidence=evidence,ranking_pass=ranking)
    return dict(rules=rules,discovery_profile=pa,confirmation_profile=pb,edges=edges.tolist(),
                discovery_rows=len(a),confirmation_rows=len(b),ranking_gate=ranking,
                discovery_label_max=int(a.exit_at_broker.max()),confirmation_label_max=int(b.exit_at_broker.max()))


def run(root):
    started=time.monotonic();root.mkdir(parents=True,exist_ok=True)
    r4.assert_frozen(r4.ROOT);frames,sources=r4.r3.prepare()
    paths=[Path(__file__),Path('scripts/orb_veto_r5_report.py'),Path('docs/ORB_Veto_R5_Protocol.md')]
    contract=dict(policy='ORB_VETO_R5',inputs=sources,policies=list(POLICIES),
        r4_contract_sha=R.digest(r4.ROOT/'contract.json'),code={str(p):R.digest(p) for p in paths},
        production=r4.production_snapshot(),replacement_enabled=False,holdout_previously_inspected=True)
    cp=root/'contract.json'
    if cp.exists() and json.loads(cp.read_text())!=contract:raise ValueError('Frozen contract changed')
    R.dump(cp,contract);results=[];rank_records=[]
    for index,source in enumerate(sources):
        ident=source['id'];f=frames[ident]
        for year in r4.YEARS:
            start,test,end=r4.dates(year);middle=R.stamp(f'{year}-03-09')
            a=R.partition(f,start,middle);b=R.partition(f,middle,test);te=R.partition(f,test,end)
            folder=root/ident/str(year);folder.mkdir(parents=True,exist_ok=True)
            if r4.checkpoint_valid(folder):
                results.extend(json.loads((folder/'result.json').read_text()))
                rank_records.extend(json.loads((folder/'ranking.json').read_text()));continue
            origin=r4.ROOT/ident/str(year)
            if not r4.checkpoint_valid(origin):raise ValueError('R4 checkpoint invalid')
            old_freeze=json.loads((origin/'frozen_before_test.json').read_text())
            models={};policies={}
            for kind in r4.KINDS:
                path=origin/(kind+'__all.research.joblib');m=joblib.load(path)
                if m['meta']['last_label']>=start-R.GAP:raise ValueError('Fit leakage')
                models[kind]=m
                policies[kind]=build_rules(a,r4.predict(m,a),b,r4.predict(m,b),start,middle,test)
                policies[kind].update(model_path=str(path),model_sha=R.digest(path),
                    old_threshold=old_freeze['models'][kind+'__all']['threshold'])
            R.dump(folder/'frozen_before_test.json',dict(policies=policies,test_start=test,test_end=end))
            rows=[];ranks=[]
            p=te[['strategy','symbol','features_at_broker','signal_bar_broker','entry_at_broker','exit_at_broker','net_r']].copy()
            p['regime']=regime_ids(te)
            for kind,m in models.items():
                spec=policies[kind];s=r4.predict(m,te);p['score_'+kind]=s
                p['old_'+kind]=(s>=spec['old_threshold']).astype(int)
                rank=dict(id=ident,name=source['name'],year=year,kind=kind,ranking_gate=spec['ranking_gate'],
                    discovery=spec['discovery_profile'],confirmation=spec['confirmation_profile'],
                    test=profile(te,s,spec['edges']))
                ranks.append(rank)
                sa=r4.predict(m,a);sb=r4.predict(m,b)
                for name,rule in spec['rules'].items():
                    k=apply(rule,s,p.regime.to_numpy());p['keep_'+kind+'__'+name]=k.astype(int)
                    da=r4.r3.utility(a,apply(rule,sa,regime_ids(a)))
                    db=r4.r3.utility(b,apply(rule,sb,regime_ids(b)))
                    u=r4.r3.utility(te,k);std,quarters=r4.r3report.quarter_stability(te,k)
                    rows.append(dict(id=ident,name=source['name'],year=year,kind=kind,policy=name,
                        active=rule['active'],test=u,discovery=da,confirmation=db,
                        selection_optimism=max(0.,da['e']-db['e']),quarter_stability=std,
                        quarters=quarters,old=r4.r3.utility(te,s>=spec['old_threshold']),
                        regime_counts=[dict(regime=rid,n=int((p.regime==rid).sum()),
                            rejected=int(((p.regime==rid)&~k).sum())) for rid in range(-1,6)]))
            if year==2025:
                p['incumbent_keep']=r4.r3.incumbent(source,te).astype(int)
                p['fair_pair']=(p.features_at_broker>=max(test,source['incumbent_information_end']+R.GAP+1)).astype(int)
            R.atomic_write(folder/'predictions.csv',p.to_csv(index=False).encode())
            R.dump(folder/'result.json',rows);R.dump(folder/'ranking.json',ranks)
            R.dump(folder/'complete.json',{p.name:R.digest(p) for p in folder.iterdir() if p.is_file() and p.name!='complete.json'})
            results.extend(rows);rank_records.extend(ranks)
            print(index+1,ident,year,'complete',flush=True)
            R.dump(root/'progress.json',dict(completed_pairs=len(rank_records),total_pairs=88,stage='calibration_and_test'))
    verify_inputs(root)
    R.dump(root/'summary.json',results);R.dump(root/'ranking.json',rank_records)
    R.dump(root/'progress.json',dict(stage='complete',pairs=len(rank_records),policies=len(results),
                                    elapsed_seconds=time.monotonic()-started,replacement_enabled=False))


def verify_inputs(root):
    contract=json.loads((root/'contract.json').read_text());r4.assert_frozen(r4.ROOT)
    if R.digest(r4.ROOT/'contract.json')!=contract['r4_contract_sha']:raise ValueError('R4 changed')
    for path,sha in contract['code'].items():
        if R.digest(path)!=sha:raise ValueError('R5 source changed')
    now=r4.production_snapshot()
    differences=[p for p,sha in contract['production'].items() if now.get(p)!=sha]
    R.dump(root/'production_integrity.json',dict(files_checked=len(now),differences=differences))
    if differences:raise ValueError('Production mutation')
    return contract


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT);args=p.parse_args()
    with threadpool_limits(limits=1):run(args.out)
