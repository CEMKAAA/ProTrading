"""Matched training-age ablation; isolated artifacts, no deployment interface."""
import os
for key in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ[key] = '1'
from pathlib import Path
import argparse
import json
import time
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_long_history_r3 as r3
import orb_long_history_r3_report as r3report

R = r3.r1
ROOT = Path('logs/OrbTrainingAge_R4_20260911')
ARMS = ('trailing_3y', 'trailing_5y', 'all', 'decay_2y')
KINDS = ('ridge', 'hgb')
YEARS = (2024, 2025)
START = R.stamp('2018-01-01')


def dates(year):
    return tuple(R.stamp(f'{y}-09-09') for y in (year-1, year, year+1))


def training_slice(f, cutoff, arm):
    if arm not in ARMS:
        raise ValueError('Unknown arm')
    all_rows = R.partition(f, START, cutoff)
    lower = START
    if arm.startswith('trailing_'):
        years = 3 if arm == 'trailing_3y' else 5
        lower = max(START, int((pd.Timestamp(cutoff, unit='s', tz='UTC') -
                               pd.DateOffset(years=years)).timestamp()))
    tr = all_rows.loc[all_rows.features_at_broker >= lower].copy()
    if len(tr) < 150:
        raise ValueError('Insufficient training rows')
    age = (cutoff-tr.features_at_broker.to_numpy(float))/86400.
    w = np.exp2(-age/730.5) if arm == 'decay_2y' else np.ones(len(tr))
    w *= len(all_rows)/w.sum()
    meta = dict(arm=arm, cutoff=cutoff, lower=lower, rows=len(tr), all_rows=len(all_rows),
                first_feature=int(tr.features_at_broker.min()),
                last_label=int(tr.exit_at_broker.max()), weight_sum=float(w.sum()),
                effective_n=float(w.sum()**2/(w@w)),
                weighted_age_years=float(np.average(age, weights=w)/365.25))
    return tr, w, meta


def fit(tr, w, kind, meta):
    if kind not in KINDS or len(w) != len(tr) or not np.isfinite(w).all() or (w <= 0).any():
        raise ValueError('Invalid model or weights')
    if tr.exit_at_broker.max() >= meta['cutoff']-R.GAP:
        raise ValueError('Training label crosses cutoff')
    ident = r3.r2.identity(tr)
    x = r3.returns.design(tr)
    if not np.isfinite(x.to_numpy()).all():
        raise ValueError('Invalid features')
    m = r3.returns.estimator('ridge_100' if kind == 'ridge' else 'hgb_7')
    if meta['arm'] == 'all':
        m.fit(x, tr.net_r)
    elif kind == 'ridge':
        m.fit(x, tr.net_r, standardscaler__sample_weight=w, ridge__sample_weight=w)
    else:
        m.fit(x, tr.net_r, sample_weight=w)
    scaler_checks = None
    if kind == 'ridge':
        scaler = m.named_steps['standardscaler']
        if not np.isfinite(scaler.scale_).all() or (scaler.scale_ <= 0).any():
            raise ValueError('Invalid training scaler')
        # Weighted constant columns can have roundoff-negative variance; sklearn
        # assigns them unit scale. Record it rather than hiding a real NaN.
        negative = np.flatnonzero(scaler.var_ < 0)
        if len(negative) and ((scaler.var_[negative] < -1e-12).any() or
                              (scaler.scale_[negative] != 1).any()):
            raise ValueError('Invalid negative training variance')
        scaler_checks = [dict(feature=str(x.columns[i]), variance=float(scaler.var_[i]),
                              scale=float(scaler.scale_[i])) for i in negative]
    return dict(kind=kind, identity=ident, model=m, meta=meta, features=list(x.columns),
                scaler_checks=scaler_checks,train_mean=float(np.average(tr.net_r, weights=w)))


def predict(m, f):
    if r3.r2.identity(f) != m['identity']:
        raise ValueError('Wrong strategy/model identity')
    x = r3.returns.design(f)
    if list(x.columns) != m['features']:
        raise ValueError('Feature order mismatch')
    scores = m['model'].predict(x)
    if not np.isfinite(scores).all():
        raise ValueError('Nonfinite predictions')
    return scores


def shift(tr, w, target):
    x = r3.returns.design(tr).to_numpy(float)
    z = r3.returns.design(target).to_numpy(float)
    mu = np.average(x, weights=w, axis=0)
    sd = np.sqrt(np.average((x-mu)**2, weights=w, axis=0))
    valid = sd > 1e-8
    delta = np.abs(z.mean(axis=0)[valid]-mu[valid])/sd[valid]
    names = np.array(r3.returns.design(tr).columns)[valid]
    cols = ['f_regime'+str(i) for i in range(6)]
    a = np.average(tr[cols].to_numpy(), weights=w, axis=0)
    b = target[cols].mean().to_numpy()
    # Include missing/invalid regime mass instead of silently dropping it.
    a = np.r_[a, max(0., 1-a.sum())]; b = np.r_[b, max(0., 1-b.sum())]
    a /= a.sum(); b /= b.sum()
    return dict(median_standardized_mean_shift=float(np.median(delta)),
                regime_total_variation=float(np.abs(a-b).sum()/2),
                largest=[dict(feature=str(names[i]),shift=float(delta[i]))
                         for i in np.argsort(delta)[-5:][::-1]])


def production_snapshot():
    inventory = json.loads(Path('logs/OrbLongHistory_R3_20260910/production_before.json').read_text(encoding='utf-8-sig'))
    return {x['Path']: R.digest(x['Path']) for x in inventory}


def assert_frozen(root):
    c = json.loads((root/'contract.json').read_text())
    for p, sha in c['code'].items():
        if R.digest(p) != sha:
            raise ValueError('Frozen research source changed: '+p)
    for rec in c['inputs']:
        for p, s in (('old_csv','old_sha'), ('new_csv','new_sha'), ('incumbent','incumbent_sha')):
            if R.digest(rec[p]) != rec[s]:
                raise ValueError('Data/model input changed: '+rec[p])
    return c


def checkpoint_valid(folder):
    p = folder/'complete.json'
    if not p.exists():
        return False
    for name, sha in json.loads(p.read_text()).items():
        if R.digest(folder/name) != sha:
            raise ValueError('Checkpoint mutated: '+name)
    return True


def run(root):
    started = time.monotonic()
    root.mkdir(parents=True, exist_ok=True)
    frames, sources = r3.prepare()
    paths = [Path(__file__), Path(r3.__file__), Path(R.__file__), Path(r3.r2.__file__),
             Path(r3.returns.__file__), Path(r3report.__file__), Path('scripts/orb_ml_filter.py'),
             Path('scripts/orb_training_age_r4_report.py'),
             Path('docs/ORB_TrainingAge_R4_Protocol.md')]
    contract = dict(policy='ORB_TRAINING_AGE_R4', inputs=sources, arms=list(ARMS), kinds=list(KINDS),
                    years=list(YEARS), code={str(p):R.digest(p) for p in paths},
                    production=production_snapshot(), replacement_enabled=False,
                    holdout_previously_inspected=True)
    cp = root/'contract.json'
    if cp.exists() and json.loads(cp.read_text()) != contract:
        raise ValueError('Campaign contract changed; refusing resume')
    R.dump(cp, contract)
    results=[]
    for index, source in enumerate(sources):
        ident=source['id']; f=frames[ident]
        for year in YEARS:
            folder=root/ident/str(year); folder.mkdir(parents=True, exist_ok=True)
            if checkpoint_valid(folder):
                results.extend(json.loads((folder/'result.json').read_text()))
                print(ident,year,'verified resume',flush=True); continue
            cutoff, start, end=dates(year)
            ca=R.partition(f,cutoff,start); te=R.partition(f,start,end)
            if len(ca)<20 or len(te)<20:
                raise ValueError('Insufficient calibration/test: '+ident)
            models={}; frozen={}; histories={}
            for kind in KINDS:
                for arm in ARMS:
                    key=kind+'__'+arm
                    tr,w,meta=training_slice(f,cutoff,arm)
                    m=fit(tr,w,kind,meta)
                    scores=predict(m,ca); t=r3.calibrated(ca,scores,kind)
                    if t is None:
                        raise ValueError('No calibration threshold')
                    cal=r3.utility(ca,scores>=t); train=r3.utility(tr,predict(m,tr)>=t)
                    models[key]=m; histories[key]=(tr,w)
                    frozen[key]=dict(threshold=t,calibration=cal,training=train,
                        train_optimism=max(0.,train['e']-cal['e']),
                        cal_gate=bool(cal['gain']>0 and cal['skill']>0),
                        cal_label_max=int(ca.exit_at_broker.max()),meta=meta,
                        calibration_shift=shift(tr,w,ca))
                    joblib.dump(m,folder/(key+'.research.joblib'))
                    R.dump(root/'progress.json',dict(stage='training',strategy=ident,year=year,
                        completed_fits=index*16+(year-YEARS[0])*8+len(models),total_fits=352))
            R.dump(folder/'frozen_before_test.json',dict(models=frozen,
                hashes={p.name:R.digest(p) for p in folder.glob('*.joblib')},test_start=start,test_end=end))
            # Only now evaluate frozen choices on the next year.
            rows=[]
            p=te[['strategy','symbol','features_at_broker','signal_bar_broker','entry_at_broker','exit_at_broker','net_r']].copy()
            for key,m in models.items():
                spec=frozen[key]; pred=predict(m,te); keep=pred>=spec['threshold']
                p['score_'+key]=pred; p['keep_'+key]=keep.astype(int)
                p['fixed0_'+key]=(pred>=0).astype(int)
                p['gated_'+key]=(keep if spec['cal_gate'] else np.ones(len(te),bool)).astype(int)
                u=r3.utility(te,keep); stability,quarters=r3report.quarter_stability(te,keep)
                mse=float(np.mean((pred-te.net_r.to_numpy())**2))
                null_mse=float(np.mean((m['train_mean']-te.net_r.to_numpy())**2))
                tr,w=histories[key]
                if year==2025 and m['meta']['arm']=='all':
                    prior=Path('logs/OrbLongHistory_R3_20260910')/ident/(m['kind']+'.research.joblib')
                    prior_cp=json.loads((prior.parent/'complete.json').read_text())
                    if R.digest(prior)!=prior_cp[prior.name]: raise ValueError('R3 model changed')
                    np.testing.assert_allclose(pred,r3.predict(joblib.load(prior),te),rtol=1e-10,atol=1e-10)
                rows.append(dict(id=ident,name=source['name'],year=year,kind=m['kind'],arm=m['meta']['arm'],
                    test=u,fixed0=r3.utility(te,pred>=0),gated=r3.utility(te,p['gated_'+key].to_numpy(bool)),
                    **spec,quarter_stability=stability,quarters=quarters,
                    test_mse=mse,mean_baseline_mse=null_mse,r2_vs_train_mean=1-mse/null_mse if null_mse>0 else None,
                    test_shift=shift(tr,w,te),replacement_enabled=False))
            if year==2025:
                p['incumbent_keep']=r3.incumbent(source,te).astype(int)
                fair=max(start,source['incumbent_information_end']+R.GAP+1)
                p['fair_pair']=(p.features_at_broker>=fair).astype(int)
            R.atomic_write(folder/'predictions.csv',p.to_csv(index=False).encode())
            R.dump(folder/'result.json',rows)
            R.dump(folder/'complete.json',{p.name:R.digest(p) for p in folder.iterdir() if p.is_file() and p.name!='complete.json'})
            results.extend(rows)
            print(index+1,ident,year,'8 fits complete',flush=True)
    assert_frozen(root)
    after=production_snapshot()
    changed=[p for p in contract['production'] if contract['production'][p]!=after.get(p)]
    R.dump(root/'production_integrity.json',dict(files_checked=len(after),differences=changed))
    if changed: raise ValueError('Production mutation during research')
    R.dump(root/'summary.json',results)
    R.dump(root/'progress.json',dict(stage='complete',fits=len(results),replacement_enabled=False,
                                    elapsed_seconds=time.monotonic()-started))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,default=ROOT)
    args=parser.parse_args()
    with threadpool_limits(limits=1): run(args.out)
