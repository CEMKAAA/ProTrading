"""Isolated chronological regime campaign. Never deploys or opens a terminal."""
import os
for key in ('OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS'):
    os.environ[key] = '1'
from copy import deepcopy
from pathlib import Path
import argparse
import hashlib
import json
import time
import warnings
import joblib
import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge, LogisticRegression
from sklearn.neural_network import MLPRegressor
from sklearn.preprocessing import StandardScaler
from threadpoolctl import threadpool_limits
from orb_ml_filter import FEATURES, load_dataset, atomic_write

POLICY = 'ORB_REGIME_R1_20260910'
CANDIDATES = ('local_base', 'local_regime', 'pool_base', 'pool_regime', 'pool_payoff', 'pool_mlp')
THRESHOLDS = (-1e9, 0., .025, .05, .10)
GAP = 86400
SEED = 20260910


def stamp(value):
    return int(pd.Timestamp(value, tz='UTC').timestamp())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def dump(path, data):
    atomic_write(path, json.dumps(data, indent=2, allow_nan=False).encode())


def partition(frame, start, end):
    # Labels crossing a boundary are excluded even when entries precede it.
    return frame.loc[(frame.features_at_broker >= start) &
        (frame.features_at_broker < end) & (frame.entry_at_broker < end) &
        (frame.exit_at_broker < end-GAP)].copy()


def weights(frame):
    group = frame.symbol.astype(str) + ':' + (frame.features_at_broker//86400).astype(str)
    w = 1. / group.map(group.value_counts()).to_numpy(float)
    return w / w.mean()


def design(frame, regime, pooled, identities):
    base = [c for c in FEATURES if not c.startswith('f_regime') and c != 'f_rf_index']
    x = frame[base].copy()
    risk = (frame.entry-frame.sl).abs()
    if (risk <= 0).any() or (frame.obs_atr14 <= 0).any():
        raise ValueError('Invalid planned risk geometry/ATR')
    x['x_sl_atr'] = risk/frame.obs_atr14
    x['x_target_r'] = np.where(frame.tp > 0, (frame.tp-frame.entry).abs()/risk, 0.)
    x['x_no_tp'] = (frame.tp <= 0).astype(float)
    x['x_spread_sl'] = frame.f_spread_atr/x.x_sl_atr
    x['x_sl_price'] = risk/frame.entry.abs()
    for name in ('return5_atr', 'return20_atr', 'ema20_50_atr'):
        x['x_aligned_'+name] = frame.f_direction*frame['f_'+name]
    if regime:
        for c in FEATURES:
            if c.startswith('f_regime'):
                x[c] = frame[c]
        for i in range(13):
            x['x_rf_'+str(i)] = (frame.f_rf_index == i).astype(float)
        x['x_direction_depth'] = frame.f_direction*frame.f_regime_trend_depth
        x['x_return_depth'] = x.x_aligned_return5_atr*frame.f_regime_trend_depth
        x['x_return_pending'] = x.x_aligned_return5_atr*frame.f_regime_pending
        x['x_age_trend'] = np.log1p(frame.f_regime_age.clip(lower=0))*x.x_aligned_ema20_50_atr
        x['x_vol_sl'] = frame.f_regime_vol_depth*x.x_sl_atr
        x['x_conf_range'] = frame.f_regime_transition_conf*frame.f_orb_range_atr
    if pooled:
        for ident in identities:
            x['strategy_'+ident] = frame.strategy.eq(ident).astype(float)
    if not np.isfinite(x.to_numpy(float)).all():
        raise ValueError('Nonfinite design')
    return x


def stats(frame, keep):
    if not len(frame):
        return dict(trades=0, wins=0, losses=0, flat=0, wr=None, net_r=0., dd_r=0., retention=0.)
    y = frame.loc[keep].sort_values(['exit_at_broker','entry_at_broker']).net_r.to_numpy(float)
    # Equal-time exits are grouped for DD; intra-second sequencing is unknown.
    daily_events = frame.loc[keep].groupby('exit_at_broker').net_r.sum().sort_index().to_numpy()
    equity = np.r_[0., daily_events.cumsum()]
    return dict(trades=len(y), wins=int((y>0).sum()), losses=int((y<0).sum()), flat=int((y==0).sum()),
        wr=float((y>0).mean()) if len(y) else None, net_r=float(y.sum()),
        dd_r=float(np.max(np.maximum.accumulate(equity)-equity)), retention=float(len(y)/len(frame)))


def selection_value(frame, keep):
    y = frame.net_r.to_numpy(float)
    actual = float(y[keep].sum())
    months = pd.to_datetime(frame.entry_at_broker,unit='s',utc=True).dt.strftime('%Y-%m')
    expected = 0.
    for m in months.unique():
        ix = months.to_numpy()==m
        expected += float(keep[ix].mean()*y[ix].sum())
    return dict(gain=actual-float(y.sum()), skill=actual-expected,
        count_skill=actual-float(keep.mean()*y.sum()), month_expected=expected)


def choose(frame, scores):
    if len(frame) < 20 or not np.isfinite(scores).all():
        return None
    options = []
    for t in THRESHOLDS:
        keep = scores >= t
        if keep.sum() < 20 or keep.mean() < .5:
            continue
        v = selection_value(frame,keep)
        options.append(dict(threshold=t, score=min(v['gain'],v['skill'])/len(frame),
            retention=float(keep.mean()), **v))
    return max(options,key=lambda a:(a['score'],a['retention'])) if options else None


def fit_one(frame, kind, identities):
    regime = kind not in ('local_base','pool_base')
    pooled = kind.startswith('pool')
    if len(frame)<100:
        return None
    meta = dict(kind=kind, regime=regime, pooled=pooled, identities=identities,
                train_rows=len(frame), train_label_max=int(frame.exit_at_broker.max()))
    if kind in ('pool_mlp', 'pool_payoff'):
        dates = np.unique(frame.features_at_broker//86400)
        boundary = int(dates[int(.8*len(dates))]*86400)
        fit = frame.loc[(frame.features_at_broker < boundary)&(frame.exit_at_broker < boundary-GAP)]
        stop = frame.loc[frame.features_at_broker >= boundary]
        if len(fit)<100 or len(stop)<40:
            return None
        meta.update(fit_label_max=int(fit.exit_at_broker.max()),stop_start=boundary)
    else:
        fit, stop = frame, None
    x = design(fit,regime,pooled,identities)
    w = weights(fit)
    scaler = StandardScaler().fit(x, sample_weight=w)
    z = scaler.transform(x)
    y = fit.net_r.to_numpy(float)
    meta.update(features=list(x.columns), scaler=scaler)
    if kind == 'pool_mlp':
        q = scaler.transform(design(stop,regime,pooled,identities))
        target = stop.net_r.to_numpy(float); sw = weights(stop)
        model = MLPRegressor(hidden_layer_sizes=(16,),alpha=10.,activation='relu',
            solver='adam',learning_rate_init=.001,shuffle=False,random_state=SEED,early_stopping=False)
        best, best_loss, stale = None, np.inf, 0
        for epoch in range(1,201):
            model.partial_fit(z,y,sample_weight=w)
            loss = float(np.average((model.predict(q)-target)**2,weights=sw))
            if not np.isfinite(loss):
                raise ValueError('Nonfinite neural checkpoint loss')
            if loss < best_loss-1e-6:
                best,best_loss,stale,best_epoch = deepcopy(model),loss,0,epoch
            else:
                stale += 1
            if epoch>=40 and stale>=25:
                break
        meta.update(model=best,epochs=epoch,best_epoch=best_epoch,stop_mse=best_loss)
    elif kind == 'pool_payoff':
        pos = y>0
        if pos.sum()<30 or (~pos).sum()<30 or stop.label_win.nunique()<2:
            return None
        classifier = LogisticRegression(C=.1,max_iter=2000,random_state=SEED).fit(z,pos,sample_weight=w)
        positive = Ridge(alpha=100.).fit(z[pos],y[pos],sample_weight=w[pos])
        negative = Ridge(alpha=100.).fit(z[~pos],-y[~pos],sample_weight=w[~pos])
        q = scaler.transform(design(stop,regime,pooled,identities))
        logits = classifier.decision_function(q).reshape(-1,1)
        calibration = LogisticRegression(C=.1,max_iter=1000).fit(logits,stop.net_r>0,sample_weight=weights(stop))
        meta.update(classifier=classifier,positive=positive,negative=negative,calibration=calibration)
    else:
        meta['model'] = Ridge(alpha=100.).fit(z,y,sample_weight=w)
    return meta


def predict(bundle, frame):
    x = design(frame,bundle['regime'],bundle['pooled'],bundle['identities'])
    if list(x.columns)!=bundle['features']:
        raise ValueError('Feature order mismatch')
    z = bundle['scaler'].transform(x)
    if bundle['kind']=='pool_payoff':
        logits = bundle['classifier'].decision_function(z).reshape(-1,1)
        p = bundle['calibration'].predict_proba(logits)[:,1]
        result = p*np.maximum(0,bundle['positive'].predict(z))-(1-p)*np.maximum(0,bundle['negative'].predict(z))
    else:
        result = bundle['model'].predict(z)
    if not np.isfinite(result).all():
        raise ValueError('Nonfinite scores')
    return result


def prepare(campaign):
    states = json.loads(campaign.read_text())
    frames, records = [], []
    for state in states:
        f, info = load_dataset(Path(state['csv']))
        if info['dataset_sha256']!=state['csv_sha256']:
            raise ValueError('Frozen dataset changed: '+state['preset_id'])
        if info['preset_id']!=state['preset_id'] or info['symbol']!=state['symbol']:
            raise ValueError('Identity mismatch')
        f['strategy']=state['preset_id']
        # Require planned geometry to be finite; outcome columns never enter design.
        design(f,True,False,[])
        if not f.f_rf_index.isin(range(13)).all():
            raise ValueError('Unknown RF category')
        frames.append(f)
        records.append(dict(id=state['preset_id'],name=state['name'],symbol=state['symbol'],
            csv=state['csv'],csv_sha256=info['dataset_sha256'],rows=len(f),excluded_rows=info['excluded_rows'],
            from_broker=int(f.features_at_broker.min()) if len(f) else None,
            to_broker=int(f.exit_at_broker.max()) if len(f) else None))
    if len(records)!=53 or len({r['id'] for r in records})!=53:
        raise ValueError('Expected all 53 unique frozen strategies')
    return pd.concat(frames,ignore_index=True).sort_values(['features_at_broker','strategy']).reset_index(drop=True), records


def score_map(models, frame, identities):
    result = {}
    for ident in identities:
        f = frame.loc[frame.strategy==ident]
        if not len(f):
            continue
        for kind, bundle in models.items():
            model = bundle.get(ident) if kind.startswith('local') else bundle
            if model is not None:
                result[(ident,kind)] = predict(model,f)
    return result


def train_stage(frame, identities, folder):
    models = {}
    for kind in CANDIDATES:
        started = time.monotonic()
        if kind.startswith('local'):
            bundle = {i:fit_one(frame.loc[frame.strategy==i],kind,identities) for i in identities}
        else:
            bundle = fit_one(frame,kind,identities)
        models[kind]=bundle
        joblib.dump(bundle,folder/(kind+'.research.joblib'))
        print(f'  {folder.name} {kind}: {time.monotonic()-started:.1f}s',flush=True)
    return models


def run(campaign, out):
    out.mkdir(parents=True,exist_ok=True)
    data, records = prepare(campaign)
    identities = sorted(r['id'] for r in records)
    cutoff = min(int(x) for x in data.asof_broker.unique())
    code = {p.name:digest(p) for p in [Path(__file__),Path(__file__).with_name('orb_ml_filter.py')]}
    contract = dict(policy=POLICY,code=code,inputs=records,candidates=CANDIDATES,thresholds=THRESHOLDS,
                    cutoff=cutoff,research_only=True,test_previously_inspected=True)
    contract=json.loads(json.dumps(contract))
    if (out/'contract.json').exists() and json.loads((out/'contract.json').read_text())!=contract:
        raise ValueError('Frozen campaign provenance differs: use new folder')
    dump(out/'contract.json',contract)
    all_summaries=[]
    for year in (2024,2025,2026):
        folder=out/str(year);folder.mkdir(exist_ok=True)
        if (folder/'complete.json').exists():
            done=json.loads((folder/'complete.json').read_text())
            for name,sha in done['artifacts'].items():
                if digest(folder/name)!=sha:
                    raise ValueError('Checkpoint corrupted: '+name)
            all_summaries.extend(json.loads((folder/'summary.json').read_text()))
            print(f'{year} RESUME COMPLETE',flush=True);continue
        c0=stamp(f'{year-1}-01-01');v0=stamp(f'{year-1}-07-01');t0=stamp(f'{year}-01-01')
        end=min(cutoff,stamp(f'{year+1}-01-01'))
        fit=partition(data,0,c0);cal=partition(data,c0,v0);val=partition(data,v0,t0);test=partition(data,t0,end)
        if not len(test):
            raise ValueError('Empty outer window')
        print(f'{year} fit={len(fit)} cal={len(cal)} val={len(val)} test={len(test)}',flush=True)
        dump(out/'progress.json',dict(year=year,stage='development_training',completed_years=year-2024))
        dev=folder/'development';dev.mkdir(exist_ok=True)
        models=train_stage(fit,identities,dev)
        cs=score_map(models,cal,identities);vs=score_map(models,val,identities)
        decisions={};development=[]
        for ident in identities:
            cf=cal.loc[cal.strategy==ident];vf=val.loc[val.strategy==ident]
            options=[]
            for kind in CANDIDATES:
                key=(ident,kind)
                if key not in cs or key not in vs:
                    development.append(dict(id=ident,kind=kind,status='insufficient_fit_or_period'));continue
                option=choose(cf,cs[key])
                if option is None or len(vf)<20:
                    development.append(dict(id=ident,kind=kind,status='insufficient_calibration_or_validation'));continue
                keep=vs[key]>=option['threshold'];value=selection_value(vf,keep)
                score=min(option['score'],min(value['gain'],value['skill'])/len(vf))
                valid=bool(score>1e-9 and keep.sum()>=20 and keep.mean()>=.5)
                row=dict(id=ident,kind=kind,status='evaluated',cal=option,val=value,
                    val_retention=float(keep.mean()),score=score,eligible=valid)
                development.append(row)
                if valid:options.append(row)
            selected=max(options,key=lambda r:(r['score'],-CANDIDATES.index(r['kind']))) if options else None
            decisions[ident]=dict(kind=selected['kind'] if selected else 'NO_VETO',reason='development_pass' if selected else 'no_candidate_passed')
        dump(folder/'development.json',development)
        dump(folder/'selection_before_refit.json',decisions)
        del models,cs,vs
        dump(out/'progress.json',dict(year=year,stage='final_refit',completed_years=year-2024))
        final=folder/'final';final.mkdir(exist_ok=True)
        models=train_stage(partition(data,0,v0),identities,final)
        vs=score_map(models,val,identities)
        candidate_thresholds={}
        for ident in identities:
            vf=val.loc[val.strategy==ident]
            for kind in CANDIDATES:
                key=(ident,kind)
                option=choose(vf,vs[key]) if key in vs else None
                candidate_thresholds[ident+'|'+kind]=option
            d=decisions[ident]
            opt=candidate_thresholds.get(ident+'|'+d['kind'])
            if d['kind']!='NO_VETO' and (opt is None or opt['score']<=1e-9):
                d.update(kind='NO_VETO',reason='refit_calibration_failed')
            d['threshold']=opt['threshold'] if d['kind']!='NO_VETO' else -1e9
        # Commit all final choices and model hashes BEFORE touching test predictions.
        frozen=dict(year=year,fit_end=v0,calibration_end=t0,test_end=end,decisions=decisions,
                    candidate_thresholds=candidate_thresholds,models={p.name:digest(p) for p in final.glob('*.joblib')})
        dump(folder/'frozen_before_test.json',frozen)
        dump(out/'progress.json',dict(year=year,stage='frozen_test',completed_years=year-2024))
        ts=score_map(models,test,identities)
        preds=[];summary=[];ablations=[]
        for ident in identities:
            f=test.loc[test.strategy==ident]
            if not len(f):
                summary.append(dict(id=ident,year=year,status='no_test_rows'));continue
            d=decisions[ident]
            scores=ts[(ident,d['kind'])] if d['kind']!='NO_VETO' else np.zeros(len(f))
            keep=scores>=d['threshold'] if d['kind']!='NO_VETO' else np.ones(len(f),dtype=bool)
            baseline=stats(f,np.ones(len(f),dtype=bool));selected=stats(f,keep)
            summary.append(dict(id=ident,year=year,status='scored',**d,base=baseline,ml=selected,**selection_value(f,keep)))
            p=f[['strategy','symbol','signal_bar_broker','features_at_broker','entry_at_broker','exit_at_broker','net_r','label_win',
                 *['f_regime'+str(i) for i in range(6)]]].copy()
            p['year']=year;p['kind']=d['kind'];p['score']=scores;p['keep']=keep.astype(int)
            for kind in CANDIDATES:
                option=candidate_thresholds[ident+'|'+kind];key=(ident,kind)
                if option is None or key not in ts:
                    continue
                k=ts[key]>=option['threshold']
                p['keep_'+kind]=k.astype(int)
                ablations.append(dict(id=ident,year=year,kind=kind,threshold=option['threshold'],
                    policy_selected=d['kind']==kind,base=baseline,ml=stats(f,k),**selection_value(f,k)))
            preds.append(p)
        for name,sha in frozen['models'].items():
            if digest(final/name)!=sha:raise ValueError('Model mutated while scoring')
        atomic_write(folder/'predictions.csv',pd.concat(preds).to_csv(index=False).encode())
        dump(folder/'summary.json',summary);dump(folder/'ablations.json',ablations)
        artifacts={str(p.relative_to(folder)):digest(p) for p in folder.rglob('*') if p.is_file() and p.name!='complete.json'}
        dump(folder/'complete.json',dict(artifacts=artifacts))
        all_summaries.extend(summary)
        print(f'{year} COMPLETE; active={sum(d["kind"]!="NO_VETO" for d in decisions.values())}/{len(identities)}',flush=True)
        del models,vs,ts
    # Recheck immutable data. No changes to frozen production weights or terminals.
    for record in records:
        if digest(record['csv'])!=record['csv_sha256']:raise ValueError('Input changed during campaign')
    dump(out/'summary.json',all_summaries)
    dump(out/'progress.json',dict(stage='complete',completed_years=3,production_modified=False))
    print('CAMPAIGN COMPLETE; NO MODEL DEPLOYED',flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--campaign',type=Path,default=Path('logs/OrbMLCampaign_20260909_v3/training_v1/campaign.json'))
    p.add_argument('--out',type=Path,default=Path('logs/OrbRegimeCampaign_20260910_R1'))
    args=p.parse_args()
    with threadpool_limits(limits=1):
        run(args.campaign,args.out)
