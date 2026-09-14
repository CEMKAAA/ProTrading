"""NAS strategy-local campaign and regime leaderboard, using the ORB trainer.

Leaderboards are retrospective candidate masks, not a replay of changed position
replacement lifecycles. Exclusions and training-period contamination are explicit.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
import numpy as np
import pandas as pd

try:
    from .nas_ml_filter import engine
    from .nas_strategy_catalog import catalogue
    from .nas_ml_worker import within
    from .build_orb_leaderboard import score
    from .orb_ml_worker import exclusive_worker
    from .nas_model_slot import stage_qualified
except ImportError:
    from nas_ml_filter import engine
    from nas_strategy_catalog import catalogue
    from nas_ml_worker import within
    from build_orb_leaderboard import score
    from orb_ml_worker import exclusive_worker
    from nas_model_slot import stage_qualified

def statistics(frame):
    pnl=frame.net_r.to_numpy(float)
    events=frame.groupby('exit_at_broker').net_r.sum().sort_index().to_numpy(float)
    curve=np.r_[0.,events.cumsum()]
    n=len(frame);w=int((pnl>0).sum());l=int((pnl<0).sum())
    dd=float((np.maximum.accumulate(curve)-curve).max())
    return dict(n=n,w=w,l=l,wr=100*w/n if n else None,net_r=float(pnl.sum()),
        dd_r=dd,min_cum_r=float(curve.min()),score=score(w,n,dd))

def run(root: Path,out: Path,train=True):
    # Read-only artifact collection can coexist with the queue worker. Per-model
    # dataset/report/model checksums below reject a concurrent stale replacement.
    # Only the actual training path owns the worker lock and publishes releases.
    if not train:return run_locked(root,out,False)
    with exclusive_worker(root):
        return run_locked(root,out,train)


def run_locked(root: Path,out: Path,train=True):
    if root.name!='NasML':raise ValueError('Dedicated NAS namespace required')
    ml=engine();names={p['id']:p['name'] for p in catalogue()}
    profile=Path(__file__).resolve().parents[1]/'IndicatorCodeExamples/NasStrategyInputProfile.mqh'
    source_hash=re.search(r'NAS_LIBRARY_SOURCE_HASH "([a-f0-9]{64})"',profile.read_text()).group(1)
    results=[];cells=[]
    for pointer in sorted(within(root,'Datasets').glob('*.latest')):
        a=pointer.read_text(encoding='utf-8').splitlines()
        if len(a)!=4 or ml.sha256(('\n'.join(a[:3])+'\n').encode())!=a[3]:
            raise ValueError(f'Pointer checksum: {pointer}')
        csv=within(root,f'Datasets/{a[2]}.csv')
        try:
            frame,info=ml.load_dataset(csv)
            if info['config_hash']!=a[1] or info['preset_id']!=a[0]:raise ValueError('Pointer/dataset binding')
            if info['source_hash']!=source_hash:raise ValueError('Archived source version; excluded from current campaign')
        except Exception as error:
            results.append(dict(csv=str(csv),error=str(error)));continue
        record=dict(csv=str(csv),dataset=info,models={})
        masks={'VANILLA':np.ones(len(frame),dtype=bool)}
        model_hashes={'VANILLA':'-'}
        for mode in (0,1):
            dest=within(root,f'Models/{mode}')
            try:
                if train:
                    report=ml.train(csv,dest,False,advanced=mode==1,epochs=200 if mode else 0,
                        progress=lambda pct,message:print(f'{a[0]} mode={mode} {pct:.1f}% {message}',flush=True))
                else:
                    report=json.loads((dest/(a[1]+'.report.json')).read_text())
                record['models'][str(mode)]=report
                if report['dataset']['dataset_sha256']!=info['dataset_sha256']:raise ValueError('Stale model evaluation')
                bundle=(dest/(a[1]+'.candidate.model')).read_bytes()
                if ml.sha256(bundle)!=report['model_sha256']:raise ValueError('Model hash changed')
                label='LEGACY' if mode==0 else 'CANDIDATE'
                probability=ml.portable_predict(bundle,frame[ml.FEATURES].to_numpy(float),a[1])
                masks[label]=probability>=report['threshold'];model_hashes[label]=ml.sha256(bundle)
                # Retain immutable artifacts; no terminal toggle is enabled.
                release=dest/'Releases'/(ml.sha256(bundle)+'.model')
                if train:ml.atomic_write(release,bundle)
                if train and report['deployment_checks_passed']:
                    ml.atomic_write(dest/(a[1]+'.model'),bundle)
                    if mode==1:
                        record['champion_slot']=stage_qualified(root,report,release)
            except Exception as error:
                record['models'][str(mode)]=dict(error=str(error))
        if len(frame):
            onehot=frame[[f'f_regime{i}' for i in range(6)]].to_numpy(float)
            if not np.isin(onehot,[0,1]).all() or (onehot.sum(axis=1)>1).any():raise ValueError('Regime encoding')
            codes=np.where(onehot.sum(axis=1)==1,onehot.argmax(axis=1),6)
        else:codes=np.array([],dtype=int)
        for mode,keep in masks.items():
            for regime in range(-1,7):
                selected=frame.loc[keep if regime==-1 else keep&(codes==regime)]
                cells.append(dict(id=a[0],name=names.get(a[0],a[0]),symbol=info['symbol'],config=a[1],
                    tf=int(info['signal_tf_seconds'])//60,mode=mode,regime=regime,
                    from_time=int(info['window_from_broker']),to_time=int(info['asof_broker']),
                    excluded=info['excluded_rows'],dataset_sha256=info['dataset_sha256'],model_sha256=model_hashes[mode],
                    scope='ELIGIBLE_CANDIDATE_MASK_NOT_EXECUTION_REPLAY',**statistics(selected)))
        results.append(record)
    out.mkdir(parents=True,exist_ok=True)
    ml.atomic_write(out/'campaign.json',json.dumps(dict(results=results,cells=cells,
        warning='Full-history ML scores include training observations. Missing/ambiguous labels are excluded, not wins or losses.'),indent=2,allow_nan=False).encode())
    pd.DataFrame(cells).to_csv(out/'leaderboard.csv',index=False)
    lines=['NAS_LB1','ELIGIBLE_CANDIDATE_MASK_NOT_EXECUTION_REPLAY']
    for c in cells:
        keys=('id','name','symbol','tf','config','mode','regime','n','w','l','net_r','dd_r','min_cum_r','score','from_time','to_time','excluded','dataset_sha256','model_sha256')
        lines.append('|'.join(str(c[k]) for k in keys))
    body=('\n'.join(lines)+'\n').encode()
    ml.atomic_write(root/'leaderboard.txt',body+ml.sha256(body).encode()+b'\n')
    return results,cells

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);p.add_argument('--skip-train',action='store_true')
    args=p.parse_args();r,c=run(args.root,args.out,not args.skip_train)
    print(f'{len(r)} datasets, {len(c)} leaderboard cells; no live ML toggle enabled.')
