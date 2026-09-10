"""Long-history, strategy-local research. There is deliberately no deployment API."""
import os
for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'): os.environ[key]='1'
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
import pandas as pd
import joblib
from threadpoolctl import threadpool_limits
import orb_regime_campaign as r1
import orb_regime_local_r2 as r2
import orb_ml_return_campaign as returns
import orb_ml_research as research
from orb_ml_filter import FEATURES, load_dataset, temporal_split, portable_predict
from evaluate_orb_ml_prior_five import compare_settings
from export_orb_campaign_models import predict_return

COMMON=Path(os.environ['APPDATA'])/'MetaQuotes/Terminal/Common/Files'
CAMPAIGN=Path('logs/OrbMLCampaign_20260909_v3/training_v1')
ROOT=Path('logs/OrbLongHistory_R3_20260910')
KINDS=('ridge','hgb','mlp','hier')
CAL=r1.stamp('2024-09-09'); TEST=r1.stamp('2025-09-09'); END=r1.stamp('2026-09-09')


def prepare():
    states=json.loads((CAMPAIGN/'campaign.json').read_text())
    oldroot=COMMON/'OrbMLPriorFive_20260910'
    manifest=pd.read_csv(oldroot/'manifest_USDJPYm.tsv',sep='\t')
    manifest=manifest.loc[manifest.status.eq('EXPORTED')].drop_duplicates('id',keep='last').set_index('id')
    registry=json.loads((COMMON/'OrbML/CampaignModels/adapter_verification.json').read_text())
    registered={x['id']:x for x in registry}
    frames={};records=[]
    for state in states:
        if state['symbol']!='USDJPYm': continue
        ident=state['preset_id']
        old=COMMON/Path(str(manifest.loc[ident,'path']).replace('\\','/'))
        new=Path(state['csv'])
        a,ai=load_dataset(old);b,bi=load_dataset(new)
        if bi['dataset_sha256']!=state['csv_sha256']: raise ValueError('Recent CSV changed')
        compare_settings(oldroot/'Settings'/(ident+'.txt'),new.parent.parent/'Settings'/(ident+'.txt'))
        for key in ('schema','preset_id','symbol','broker','signal_tf_seconds','chart_tf_seconds'):
            if ai[key]!=bi[key]: raise ValueError('Export contract differs: '+key)
        if int(ai['asof_broker'])!=r1.stamp('2021-09-09') or int(bi['asof_broker'])!=END:
            raise ValueError('Unexpected export boundaries')
        a=a.loc[a.features_at_broker>=r1.stamp('2018-01-01')].copy()
        if a.exit_at_broker.max()>=b.features_at_broker.min(): raise ValueError('Overlapping exports')
        f=pd.concat([a,b],ignore_index=True).sort_values('features_at_broker').reset_index(drop=True)
        if f.duplicated(['signal_bar_broker','entry_at_broker','execution_direction']).any():
            raise ValueError('Duplicate joined trade')
        # Preserve source lineage; R2 identity is the research join, not a production config.
        joined=hashlib.sha256((ai['dataset_sha256']+bi['dataset_sha256']).encode()).hexdigest()
        f['origin_dataset_id']=f.dataset_id;f['origin_source_hash']=f.source_hash
        f['origin_config_hash']=f.config_hash
        f['strategy']=ident;f['dataset_id']=ident+'_R3_'+joined
        f['source_hash']=joined;f['config_hash']=joined
        reg=registered[ident];mp=COMMON/'OrbML/CampaignModels'/(ident+'.experimental')
        if r1.digest(mp)!=reg['model_sha']: raise ValueError('Registered incumbent changed')
        if reg['dataset']!=bi['dataset_sha256'] or reg['config']!=bi['config_hash']:
            raise ValueError('Wrong incumbent dataset')
        _,v,_=temporal_split(b)
        # MLP header is deployment as-of, not the latest fitting/threshold label date.
        information_end=int(v.exit_at_broker.max())
        records.append(dict(id=ident,name=state['name'],symbol=state['symbol'],rows=len(f),
            old_csv=str(old),new_csv=str(new),old_sha=ai['dataset_sha256'],new_sha=bi['dataset_sha256'],
            old_source=ai['source_hash'],new_source=bi['source_hash'],old_config=ai['config_hash'],new_config=bi['config_hash'],
            settings_identical=True,incumbent=str(mp),incumbent_sha=reg['model_sha'],incumbent_kind=reg['kind'],
            incumbent_config=reg['config'],incumbent_information_end=information_end,
            export_gap_start=int(ai['asof_broker']),export_gap_end=int(bi['window_from_broker']),
            years={str(k):int(v) for k,v in pd.to_datetime(f.features_at_broker,unit='s').dt.year.value_counts().sort_index().items()}))
        frames[ident]=f
    if len(records)!=22: raise ValueError('Expected 22 verified USDJPY strategies')
    return frames,records


def fit(f,kind):
    ident=r2.identity(f)
    if len(f)<150: raise ValueError('Insufficient fit')
    m=dict(kind=kind,identity=ident,train_label_max=int(f.exit_at_broker.max()),rows=len(f))
    if kind=='hier': m['bundle']=r2.fit(f,'local_hier_400')
    elif kind=='mlp':
        model,scaler,early=research.fit_network(f,FEATURES,10.,r1.GAP,200,lambda *a:None,0,100,'R3')
        m.update(model=model,scaler=scaler,early=early)
    else:
        model=returns.estimator('ridge_100' if kind=='ridge' else 'hgb_7')
        model.fit(returns.design(f),f.net_r)
        m['model']=model
    return m


def predict(m,f):
    if r2.identity(f)!=m['identity']: raise ValueError('Wrong model identity')
    if m['kind']=='hier': value=r2.predict(m['bundle'],f)
    elif m['kind']=='mlp': value=m['model'].predict_proba(m['scaler'].transform(f[FEATURES].to_numpy(float)))[:,1]
    else: value=m['model'].predict(returns.design(f))
    if not np.isfinite(value).all(): raise ValueError('Nonfinite scores')
    return value


def calibrated(f,scores,kind):
    grid=(-1e9,*research.THRESHOLDS) if kind=='mlp' else (-1e9,-.1,-.05,0.,.025,.05,.1,.15,.2)
    options=[]
    for t in grid:
        k=scores>=t
        if k.sum()>=20 and k.mean()>=.4:
            options.append((float(f.loc[k,'net_r'].sum()),int(k.sum()),t))
    if not options: return None
    return max(options,key=lambda x:(x[0],x[1]))[2]


def utility(f,k):
    v=r1.selection_value(f,k);a=r1.stats(f,np.ones(len(f),bool));b=r1.stats(f,k)
    return dict(e=min(v['gain'],v['skill'])/len(f),d=(a['dd_r']-b['dd_r'])/len(f),
                base=a,ml=b,**v)


def robust_score(folds):
    if len(folds)!=3: return None
    e=np.array([x['validation']['e'] for x in folds]);d=np.array([x['validation']['d'] for x in folds])
    optimism=np.array([max(0.,x['training']['e']-x['validation']['e']) for x in folds])
    return dict(score=float(100*(e.mean()+.25*d.mean()-e.std()-optimism.mean())),
        mean_edge=float(e.mean()),mean_dd_improvement=float(d.mean()),stability_penalty=float(e.std()),
        optimism_penalty=float(optimism.mean()),positive_folds=int((e>1e-9).sum()))


def incumbent(record,f):
    path=Path(record['incumbent']);data=path.read_bytes()
    if r1.digest(path)!=record['incumbent_sha']: raise ValueError('Incumbent mutation')
    lines=data.decode('ascii').splitlines()
    if record['incumbent_kind']=='MLP':
        values=portable_predict(data,f[FEATURES].to_numpy(float),record['incumbent_config'])
        return values>=float(lines[6])
    values=predict_return(data,returns.design(f).to_numpy(float))
    return values>=float(lines[5]) if bool(int(lines[6])) else np.ones(len(f),bool)


def run(out):
    out.mkdir(parents=True,exist_ok=True)
    frames,records=prepare()
    paths=[Path(__file__),Path(r1.__file__),Path(r2.__file__),Path(returns.__file__),Path(research.__file__),
        Path('scripts/orb_ml_filter.py'),Path('scripts/export_orb_campaign_models.py'),
        Path('docs/ORB_LongHistory_R3_Protocol.md')]
    contract=dict(policy='ORB_LONG_HISTORY_R3',inputs=records,candidates=list(KINDS),
        code={str(p):r1.digest(p) for p in paths},train_end=CAL,calibration_end=TEST,test_end=END,
        replacement_enabled=False,holdout_previously_inspected=True)
    cp=out/'contract.json'
    if cp.exists() and json.loads(cp.read_text())!=contract: raise ValueError('Frozen campaign changed')
    r1.dump(cp,contract);summary=[]
    for index,record in enumerate(records,1):
        ident=record['id'];f=frames[ident];folder=out/ident;folder.mkdir(exist_ok=True)
        if (folder/'complete.json').exists():
            for p,sha in json.loads((folder/'complete.json').read_text()).items():
                if r1.digest(folder/p)!=sha: raise ValueError('Checkpoint changed')
            summary.append(json.loads((folder/'result.json').read_text()))
            print(index,ident,'resume verified',flush=True);continue
        print(index,ident,'begin',len(f),'rows',flush=True)
        r1.dump(out/'progress.json',dict(completed=index-1,total=22,strategy=ident))
        trials=[]
        for kind in KINDS:
            folds=[]
            for year in (2021,2022,2023):
                start=r1.stamp(f'{year}-09-09');stop=r1.stamp(f'{year+1}-09-09');c0=r1.stamp(f'{year}-03-09')
                tr=r1.partition(f,0,c0);ca=r1.partition(f,c0,start);va=r1.partition(f,start,stop)
                if len(tr)<150 or len(ca)<20 or len(va)<20: continue
                m=fit(tr,kind);t=calibrated(ca,predict(m,ca),kind)
                if t is None: continue
                folds.append(dict(fit_label_max=m['train_label_max'],cal_start=c0,score_start=start,score_end=stop,
                    threshold=t,training=utility(tr,predict(m,tr)>=t),validation=utility(va,predict(m,va)>=t)))
            score=robust_score(folds)
            trials.append(dict(kind=kind,folds=folds,robustness=score,
                eligible=bool(score and score['score']>0 and score['positive_folds']>=2)))
        choices=[x for x in trials if x['eligible']]
        choice=max(choices,key=lambda x:(x['robustness']['score'],-KINDS.index(x['kind']))) if choices else None
        selected=choice['kind'] if choice else 'NO_VETO'
        r1.dump(folder/'development.json',trials)
        r1.dump(folder/'family_before_calibration.json',dict(selected=selected))
        tr=r1.partition(f,0,CAL);ca=r1.partition(f,CAL,TEST);te=r1.partition(f,TEST,END)
        models={};thresholds={}
        for kind in KINDS:
            m=fit(tr,kind);t=calibrated(ca,predict(m,ca),kind)
            models[kind]=m;thresholds[kind]=t
            joblib.dump(m,folder/(kind+'.research.joblib'))
        selected_threshold=thresholds.get(selected)
        if selected!='NO_VETO':
            cv=utility(ca,predict(models[selected],ca)>=selected_threshold) if selected_threshold is not None else None
            if cv is None or cv['gain']<=1e-9 or cv['skill']<=1e-9: selected='NO_VETO'
        frozen=dict(selected=selected,threshold=thresholds.get(selected),all_thresholds=thresholds,
            models={p.name:r1.digest(p) for p in folder.glob('*.joblib')},replacement_enabled=False)
        r1.dump(folder/'frozen_before_test.json',frozen)
        p=te[['strategy','symbol','signal_bar_broker','features_at_broker','entry_at_broker','exit_at_broker','net_r']].copy()
        p['keep']=1 if selected=='NO_VETO' else (predict(models[selected],te)>=thresholds[selected]).astype(int)
        for kind in KINDS:
            t=thresholds[kind];p['keep_'+kind]=1 if t is None else (predict(models[kind],te)>=t).astype(int)
        p['incumbent_keep']=incumbent(record,te).astype(int)
        fair_start=max(TEST,record['incumbent_information_end']+r1.GAP+1)
        p['fair_pair']=(p.features_at_broker>=fair_start).astype(int)
        r1.atomic_write(folder/'predictions.csv',p.to_csv(index=False).encode())
        result=dict(id=ident,name=record['name'],selected=selected,pretest_robustness=choice['robustness'] if choice else None,
            train_rows=len(tr),calibration_rows=len(ca),test_rows=len(te),fair_pair_start=fair_start,
            fair_pair_rows=int(p.fair_pair.sum()),full_year=utility(te,p.keep.to_numpy(bool)),
            replacement_enabled=False,incumbent_optimism_comparable=False)
        r1.dump(folder/'result.json',result)
        for name,sha in frozen['models'].items():
            if r1.digest(folder/name)!=sha: raise ValueError('Frozen model changed')
        r1.dump(folder/'complete.json',{p.name:r1.digest(p) for p in folder.iterdir() if p.is_file() and p.name!='complete.json'})
        summary.append(result)
        print(index,ident,selected,'delta',round(result['full_year']['gain'],3),flush=True)
    for rec in records:
        for p,s in [('old_csv','old_sha'),('new_csv','new_sha'),('incumbent','incumbent_sha')]:
            if r1.digest(rec[p])!=rec[s]: raise ValueError('Frozen input changed')
    r1.dump(out/'summary.json',summary)
    r1.dump(out/'progress.json',dict(stage='complete',completed=22,replacement_enabled=False))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=ROOT);a=p.parse_args()
    with threadpool_limits(limits=1): run(a.out)
