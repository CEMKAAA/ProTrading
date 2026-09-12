"""Frozen R7 transfer to JP225, historical evaluation plus forward-only bundles."""
import argparse
import json
import time
from pathlib import Path
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_calibration_r7 as r7
from orb_ml_filter import load_dataset,temporal_split

R=r7.R;ROOT=Path('logs/OrbJP225_R7_20260911')
YEARS=(2024,2025);END=R.stamp('2026-09-09');START=R.stamp('2021-09-09')


def prepare():
    base=r7.r4.r3;states=json.loads((base.CAMPAIGN/'campaign.json').read_text())
    registry={x['id']:x for x in json.loads((base.COMMON/'OrbML/CampaignModels/adapter_verification.json').read_text())}
    frames={};sources=[]
    for x in states:
        if x['symbol']!='JP225m':continue
        ident=x['preset_id'];path=Path(x['csv']);f,info=load_dataset(path);reg=registry.get(ident)
        if info['dataset_sha256']!=x['csv_sha256'] or (reg and info['dataset_sha256']!=reg['dataset']):
            raise ValueError('Dataset changed')
        if (reg and info['config_hash']!=reg['config']) or info['preset_id']!=ident or info['symbol']!='JP225m':
            raise ValueError('Wrong strategy contract')
        if int(info['asof_broker'])!=END:raise ValueError('Unexpected source endpoint')
        mp=base.COMMON/'OrbML/CampaignModels'/(ident+'.experimental')
        if reg and R.digest(mp)!=reg['model_sha']:raise ValueError('Incumbent changed')
        _,v,_=temporal_split(f)
        f=f.sort_values('features_at_broker').reset_index(drop=True);f['strategy']=ident
        if f.duplicated(['signal_bar_broker','entry_at_broker','execution_direction']).any():raise ValueError('Duplicate setup')
        frames[ident]=f
        sources.append(dict(id=ident,name=x['name'],symbol='JP225m',csv=str(path),csv_sha=info['dataset_sha256'],
            config_hash=info['config_hash'],incumbent_available=reg is not None,
            incumbent=str(mp) if reg else None,incumbent_sha=reg['model_sha'] if reg else None,
            incumbent_kind=reg['kind'] if reg else None,incumbent_config=reg['config'] if reg else None,
            incumbent_information_end=int(v.exit_at_broker.max()) if reg else None,
            first_feature=int(f.features_at_broker.min()),rows=len(f)))
    if len(frames)!=30:raise ValueError('Expected 30 JP225 strategies')
    return frames,sources


def eligibility(f,year):
    cutoff,start,end=r7.r4.dates(year)
    n=len(R.partition(f,START,cutoff));cal=int(r7.eligible(f,start,cutoff).sum());te=len(R.partition(f,start,end))
    return dict(year=year,train=n,initial_calibration=cal,test=te,eligible=n>=150 and cal>=20 and te>=20)


def verify_contract(root=ROOT):
    c=json.loads((root/'contract.json').read_text());r7.verify_contract(r7.ROOT)
    if R.digest(r7.ROOT/'contract.json')!=c['r7_contract_sha']:raise ValueError('R7 changed')
    for p,sha in c['code'].items():
        if R.digest(p)!=sha:raise ValueError('Frozen transfer code changed')
    for x in c['inputs']:
        if R.digest(x['csv'])!=x['csv_sha']:raise ValueError('Source changed')
        if x['incumbent_available'] and R.digest(x['incumbent'])!=x['incumbent_sha']:raise ValueError('Incumbent changed')
    now=r7.r4.production_snapshot();diff=[p for p,sha in c['production'].items() if now.get(p)!=sha]
    R.dump(root/'production_integrity.json',dict(files_checked=len(now),differences=diff))
    if diff:raise ValueError('Production changed')
    return c


def fit_models(f,cutoff):
    tr=R.partition(f,START,cutoff)
    return {k:v for k,v in r7.r6.fit_family(tr,cutoff).items() if k in r7.KINDS}


def evaluate_fold(f,source,year,folder):
    cutoff,start,end=r7.r4.dates(year);models=fit_models(f,cutoff)
    te=R.partition(f,start,end).reset_index(drop=True)
    hist=f.loc[(f.features_at_broker>=cutoff)&(f.features_at_broker<end)].reset_index(drop=True)
    p=te[['strategy','symbol','features_at_broker','signal_bar_broker','entry_at_broker','exit_at_broker','net_r']].copy()
    p['regime']=r7.r6.r5.regime_ids(te);states=[];rows=[];bounds=r7.schedule(start,end)
    for kind,m in models.items():
        joblib.dump(m,folder/(kind+'.research.joblib'))
        hp=r7.r6.predict(m,hist)['probability'];tp=r7.r6.predict(m,te)['probability']
        ss={a:np.full(len(te),np.nan) for a in r7.ARMS};qq={a:np.full(len(te),np.nan) for a in r7.ARMS}
        for update,stop in zip(bounds,bounds[1:]):
            s=r7.fit_state(hist,hp,m,update);s.update(kind=kind,stop=stop);states.append(s)
            ix=(te.features_at_broker>=update)&(te.features_at_broker<stop)
            if not ix.any():continue
            p.loc[ix,'update_at']=update
            for arm in r7.ARMS:ss[arm][ix],qq[arm][ix]=r7.apply_state(te.loc[ix],tp[ix],m,s,arm)
        for arm in r7.ARMS:
            score=ss[arm];q=qq[arm]
            if not np.isfinite(score).all():raise ValueError('Missing output')
            keep=score>=0;p['score_'+kind+'__'+arm]=score;p['prob_'+kind+'__'+arm]=q;p['keep_'+kind+'__'+arm]=keep.astype(int)
            rows.append(dict(id=source['id'],name=source['name'],year=year,kind=kind,arm=arm,
                test=r7.r4.r3.utility(te,keep),probability=r7.r6.probability_stats(m,te,q),
                probability_bias=float(q.mean()-(te.net_r.to_numpy()>0).mean())))
    if year==2025 and source['incumbent_available']:
        p['incumbent_keep']=r7.r4.r3.incumbent(source,te).astype(int)
        p['fair_pair']=(te.features_at_broker>=max(start,source['incumbent_information_end']+R.GAP+1)).astype(int)
    R.dump(folder/'states.json',states);R.dump(folder/'result.json',rows)
    R.atomic_write(folder/'predictions.csv',p.to_csv(index=False).encode())
    return rows


def seal(folder):
    R.dump(folder/'complete.json',{p.name:R.digest(p) for p in folder.iterdir() if p.is_file() and p.name!='complete.json'})


def run(root):
    clock=time.monotonic();r7.verify_contract(r7.ROOT);frames,sources=prepare();root.mkdir(parents=True,exist_ok=True)
    files=[Path(__file__),Path('docs/ORB_JP225_R7_Protocol.md'),Path('scripts/verify_orb_jp225_r7.py'),Path('tests/test_orb_jp225_r7.py')]
    c=dict(type='JP225_R7',inputs=sources,years=YEARS,kinds=r7.KINDS,arms=r7.ARMS,
        r7_contract_sha=R.digest(r7.ROOT/'contract.json'),code={str(p):R.digest(p) for p in files},
        production=r7.r4.production_snapshot(),replacement_enabled=False,previously_researched_history=True)
    c=json.loads(json.dumps(c));cp=root/'contract.json'
    if cp.exists() and json.loads(cp.read_text())!=c:raise ValueError('Changed experiment contract')
    R.dump(cp,c);coverage=[];results=[];forward=[]
    for n,source in enumerate(sources,1):
        ident=source['id'];f=frames[ident]
        for year in YEARS:
            cover=dict(id=ident,**eligibility(f,year));coverage.append(cover)
            if not cover['eligible']:continue
            folder=root/ident/str(year);folder.mkdir(parents=True,exist_ok=True)
            if r7.r4.checkpoint_valid(folder):rows=json.loads((folder/'result.json').read_text())
            else:rows=evaluate_fold(f,source,year,folder);seal(folder)
            results.extend(rows)
        folder=root/ident/'forward_20260909';folder.mkdir(parents=True,exist_ok=True)
        if not r7.r4.checkpoint_valid(folder):
            models=fit_models(f,R.stamp('2025-09-09'));states={}
            hist=f.loc[(f.features_at_broker>=R.stamp('2025-09-09'))&(f.features_at_broker<END)].copy()
            for kind,m in models.items():
                hp=r7.r6.predict(m,hist)['probability'];s=r7.fit_state(hist,hp,m,END)
                joblib.dump(m,folder/(kind+'.research.joblib'));states[kind]=s
            R.dump(folder/'states.json',states);seal(folder)
        forward.append(dict(id=ident,folder=str(folder),asof=END,models=2,
            subsequent_test_completed=False,portable_ea_model=False,activated=False))
        R.dump(root/'progress.json',dict(completed=n,total=30,historical_outcomes=len(results),forward_models=len(forward)*2))
        print(n,ident,'trained',flush=True)
    verify_contract(root);R.dump(root/'coverage.json',coverage);R.dump(root/'summary.json',results);R.dump(root/'forward_manifest.json',forward)
    R.dump(root/'progress.json',dict(stage='complete',strategies=30,historical_outcomes=len(results),
        forward_models=len(forward)*2,elapsed_seconds=time.monotonic()-clock,replacement_enabled=False))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT);a=p.parse_args()
    with threadpool_limits(limits=1):run(a.out)
