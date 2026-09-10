"""Strategy-local varying-regime slopes; isolated, frozen research campaign."""
from pathlib import Path
import argparse
import json
import time
import numpy as np
import pandas as pd
import joblib
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler
from threadpoolctl import threadpool_limits
import orb_regime_campaign as r1

CANDIDATES = ('local_base', 'local_flat_regime', 'local_hier_100', 'local_hier_400')
SLOPES = ('x_aligned_return5_atr', 'x_aligned_ema20_50_atr', 'x_sl_atr',
          'x_spread_sl', 'f_regime_age', 'f_regime_transition_conf',
          'f_regime_trend_depth', 'f_regime_vol_depth')
IDENTITY = ('strategy', 'symbol', 'broker', 'source_hash', 'config_hash', 'dataset_id')
ROOT = Path('logs/OrbRegimeLocal_R2_20260910')


def identity(frame):
    result = {}
    for key in IDENTITY:
        if key not in frame or frame[key].isna().any() or frame[key].nunique() != 1:
            raise ValueError('Mixed or missing identity: '+key)
        result[key] = str(frame[key].iloc[0])
    return result


def gates(frame):
    g = frame[['f_regime'+str(i) for i in range(6)]].to_numpy(float)
    if not np.isin(g, [0., 1.]).all() or (g.sum(axis=1) > 1).any():
        raise ValueError('Invalid one-hot regime')
    if not frame.f_regime_valid.isin([0, 1]).all():
        raise ValueError('Invalid regime validity')
    return g * frame.f_regime_valid.to_numpy(float)[:, None]


def shared_design(frame, kind):
    x = r1.design(frame, kind != 'local_base', False, [])
    if kind.startswith('local_hier'):
        categorical = ['f_regime_valid'] + ['f_regime'+str(i) for i in range(6)]
        x = x.drop(columns=categorical + ['x_rf_'+str(i) for i in range(13)])
    return x


def expand(z, frame, columns, deviation_penalty):
    # Do not unit-variance normalize gated columns: sparse regimes must shrink more.
    indices = [columns.index(x) for x in SLOPES]
    local = np.column_stack([np.ones(len(z)), z[:, indices]])
    blocks = (gates(frame)[:, :, None] * local[:, None, :]).reshape(len(z), -1)
    return np.column_stack([z, blocks*np.sqrt(100./deviation_penalty)])


def fit(frame, kind):
    if kind not in CANDIDATES:
        raise ValueError('Unknown candidate')
    ident = identity(frame)
    if len(frame) < 100:
        return None
    x = shared_design(frame, kind)
    w = r1.weights(frame)
    scaler = StandardScaler().fit(x, sample_weight=w)
    z = scaler.transform(x)
    if not np.isfinite(z).all():
        raise ValueError('Invalid training scale')
    penalty = float(kind.rsplit('_', 1)[1]) if kind.startswith('local_hier') else None
    if penalty is not None:
        z = expand(z, frame, list(x.columns), penalty)
    model = Ridge(alpha=100.).fit(z, frame.net_r.to_numpy(float), sample_weight=w)
    counts = gates(frame).sum(axis=0).astype(int).tolist()
    return dict(kind=kind, identity=ident, scaler=scaler, features=list(x.columns), model=model,
                penalty=penalty, train_rows=len(frame), regime_counts=counts,
                train_label_max=int(frame.exit_at_broker.max()),
                train_feature_max=int(frame.features_at_broker.max()))


def predict(bundle, frame):
    if identity(frame) != bundle['identity']:
        raise ValueError('Wrong strategy/config/dataset model')
    x = shared_design(frame, bundle['kind'])
    if list(x.columns) != bundle['features']:
        raise ValueError('Feature contract changed')
    z = bundle['scaler'].transform(x)
    if bundle['penalty'] is not None:
        z = expand(z, frame, bundle['features'], bundle['penalty'])
    value = bundle['model'].predict(z)
    if not np.isfinite(value).all():
        raise ValueError('Nonfinite prediction')
    return value


def train_stage(frame, ids, folder):
    folder.mkdir(exist_ok=True)
    models = {}
    started = time.monotonic()
    for ident in ids:
        f = frame.loc[frame.strategy == ident]
        for kind in CANDIDATES:
            bundle = fit(f, kind) if len(f) else None
            models[(ident, kind)] = bundle
            if bundle is not None:
                joblib.dump(bundle, folder/(ident+'__'+kind+'.research.joblib'))
    print(f'{folder.parent.name}/{folder.name}: {sum(v is not None for v in models.values())} models, '+
          f'{time.monotonic()-started:.2f}s', flush=True)
    return models


def scores(models, frame):
    result = {}
    for ident, f in frame.groupby('strategy', sort=True):
        for kind in CANDIDATES:
            m = models.get((ident, kind))
            if m is not None:
                result[(ident, kind)] = predict(m, f)
    return result


def select(ids, calibration, validation, cs, vs):
    decisions={}; trials=[]
    for ident in ids:
        cf=calibration.loc[calibration.strategy==ident]
        vf=validation.loc[validation.strategy==ident]
        options=[]
        for kind in CANDIDATES:
            key=(ident,kind)
            option=r1.choose(cf,cs[key]) if key in cs else None
            if option is None or key not in vs or len(vf)<20:
                trials.append(dict(id=ident,kind=kind,status='insufficient')); continue
            keep=vs[key]>=option['threshold']
            v=r1.selection_value(vf,keep)
            score=min(option['score'],v['gain']/len(vf),v['skill']/len(vf))
            eligible=bool(score>1e-9 and keep.sum()>=20 and keep.mean()>=.5)
            record=dict(id=ident,kind=kind,cal=option,val=v,score=score,eligible=eligible,
                        val_retention=float(keep.mean()),status='evaluated')
            trials.append(record)
            if eligible: options.append(record)
        best=max(options,key=lambda x:(x['score'],-CANDIDATES.index(x['kind']))) if options else None
        decisions[ident]=dict(kind=best['kind'] if best else 'NO_VETO',
                             reason='development_pass' if best else 'no_candidate_passed')
    return decisions,trials


def run(campaign, out):
    out.mkdir(parents=True,exist_ok=True)
    data, inputs=r1.prepare(campaign)
    ids=sorted(x['id'] for x in inputs)
    cutoff=min(int(x) for x in data.asof_broker.unique())
    paths=[Path(__file__),Path(r1.__file__),Path(r1.__file__).with_name('orb_ml_filter.py'),
           Path('docs/ORB_Regime_Local_R2_Protocol.md')]
    contract=dict(policy='ORB_LOCAL_REGIME_R2',code={str(p):r1.digest(p) for p in paths},
        inputs=inputs,candidates=list(CANDIDATES),slopes=list(SLOPES),thresholds=list(r1.THRESHOLDS),
        cutoff=cutoff,research_only=True,test_previously_inspected=True,pooled_across_strategies=False)
    cp=out/'contract.json'
    if cp.exists() and json.loads(cp.read_text())!=contract:
        raise ValueError('Frozen contract differs; use a new campaign directory')
    r1.dump(cp,contract)
    annual=[]
    for year in (2024,2025,2026):
        folder=out/str(year);folder.mkdir(exist_ok=True)
        if (folder/'complete.json').exists():
            for name,sha in json.loads((folder/'complete.json').read_text())['artifacts'].items():
                if r1.digest(folder/name)!=sha: raise ValueError('Corrupt checkpoint')
            annual.extend(json.loads((folder/'summary.json').read_text()))
            print(f'{year} resume verified',flush=True); continue
        c0=r1.stamp(f'{year-1}-01-01');v0=r1.stamp(f'{year-1}-07-01');t0=r1.stamp(f'{year}-01-01')
        end=min(cutoff,r1.stamp(f'{year+1}-01-01'))
        train=r1.partition(data,0,c0);cal=r1.partition(data,c0,v0)
        val=r1.partition(data,v0,t0);test=r1.partition(data,t0,end)
        r1.dump(out/'progress.json',dict(year=year,stage='development',completed_years=year-2024))
        models=train_stage(train,ids,folder/'development')
        decisions,trials=select(ids,cal,val,scores(models,cal),scores(models,val))
        r1.dump(folder/'development_trials.json',trials)
        r1.dump(folder/'selection_before_refit.json',decisions)
        models=train_stage(r1.partition(data,0,v0),ids,folder/'final')
        vs=scores(models,val);thresholds={}
        for ident in ids:
            vf=val.loc[val.strategy==ident]
            for kind in CANDIDATES:
                k=(ident,kind)
                thresholds[ident+'|'+kind]=r1.choose(vf,vs[k]) if k in vs else None
            d=decisions[ident];opt=thresholds.get(ident+'|'+d['kind'])
            if d['kind']!='NO_VETO' and (opt is None or opt['score']<=1e-9):
                d.update(kind='NO_VETO',reason='refit_calibration_failed')
            d['threshold']=opt['threshold'] if d['kind']!='NO_VETO' else -1e9
        frozen=dict(year=year,fit_end=v0,calibration_end=t0,test_end=end,decisions=decisions,
                    candidate_thresholds=thresholds,
                    model_hashes={p.name:r1.digest(p) for p in (folder/'final').glob('*.joblib')})
        r1.dump(folder/'frozen_before_test.json',frozen)
        r1.dump(out/'progress.json',dict(year=year,stage='frozen_test',completed_years=year-2024))
        ts=scores(models,test);parts=[];summary=[];ablations=[]
        for ident,f in test.groupby('strategy',sort=True):
            d=decisions[ident]
            s=ts[(ident,d['kind'])] if d['kind']!='NO_VETO' else np.zeros(len(f))
            keep=s>=d['threshold'] if d['kind']!='NO_VETO' else np.ones(len(f),bool)
            base=r1.stats(f,np.ones(len(f),bool))
            summary.append(dict(id=ident,year=year,**d,base=base,ml=r1.stats(f,keep),
                                **r1.selection_value(f,keep)))
            p=f[['strategy','symbol','signal_bar_broker','features_at_broker','entry_at_broker',
                 'exit_at_broker','net_r','label_win',*['f_regime'+str(i) for i in range(6)]]].copy()
            p['year']=year;p['kind']=d['kind'];p['score']=s;p['keep']=keep.astype(int)
            for kind in CANDIDATES:
                key=(ident,kind);opt=thresholds[ident+'|'+kind]
                if key not in ts or opt is None: continue
                k=ts[key]>=opt['threshold'];p['keep_'+kind]=k.astype(int)
                ablations.append(dict(id=ident,year=year,kind=kind,base=base,ml=r1.stats(f,k),
                                      **r1.selection_value(f,k)))
            parts.append(p)
        r1.atomic_write(folder/'predictions.csv',pd.concat(parts).to_csv(index=False).encode())
        r1.dump(folder/'summary.json',summary);r1.dump(folder/'ablations.json',ablations)
        for name,sha in frozen['model_hashes'].items():
            if r1.digest(folder/'final'/name)!=sha: raise ValueError('Frozen model changed')
        r1.dump(folder/'complete.json',dict(artifacts={str(p.relative_to(folder)):r1.digest(p)
            for p in folder.rglob('*') if p.is_file() and p.name!='complete.json'}))
        annual.extend(summary)
        print(f'{year} complete; selected {sum(d["kind"]!="NO_VETO" for d in decisions.values())}/53',flush=True)
    for record in inputs:
        if r1.digest(record['csv'])!=record['csv_sha256']: raise ValueError('CSV changed')
    r1.dump(out/'summary.json',annual)
    r1.dump(out/'progress.json',dict(stage='complete',completed_years=3,production_modified=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--campaign',type=Path,default=Path('logs/OrbMLCampaign_20260909_v3/training_v1/campaign.json'))
    parser.add_argument('--out',type=Path,default=ROOT)
    a=parser.parse_args()
    with threadpool_limits(limits=1): run(a.campaign,a.out)
