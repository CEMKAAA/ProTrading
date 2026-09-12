"""Read-only model campaign; identity-bound regime leaderboard reports, no training."""
from pathlib import Path
import argparse
import json
import os
import numpy as np
import pandas as pd

import orb_model_slot as slot
from orb_ml_filter import FEATURES, load_dataset, portable_predict
from export_orb_campaign_models import predict_return
from build_orb_leaderboard import score
import export_orb_r7_runtime as runtime

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path(os.environ['APPDATA'])/'MetaQuotes/Terminal/Common/Files'
CAMPAIGN = ROOT/'logs/OrbMLCampaign_20260909_v3/training_v1/campaign.json'
OUT = ROOT/'logs/OrbRegimeLeaderboard_20260912'
NAMES = ['TREND LOW VOL','TREND HIGH VOL','RANGE LOW VOL','RANGE HIGH VOL','TRANSITION PENDING','TRANSITION FRESH']
MIN_N = 30
EVAL = 'CLOSED_CANDIDATE_MASK_NOT_EXECUTION_REPLAY'


def regime_codes(frame):
    x = frame[[f'f_regime{i}' for i in range(6)]].to_numpy(float)
    valid = frame.f_regime_valid.to_numpy(float)
    if not np.isin(x, [0,1]).all() or not np.isin(valid,[0,1]).all() or (x.sum(axis=1)>1).any():
        raise ValueError('Invalid/overlapping regime one-hot')
    if ((valid==0)&(x.sum(axis=1)>0)).any():
        raise ValueError('Invalid regime marked as known')
    return np.where((valid==1)&(x.sum(axis=1)==1), x.argmax(axis=1), 6)


def statistics(frame):
    y = frame.net_r.to_numpy(float)
    events = frame.groupby('exit_at_broker').net_r.sum().sort_index().to_numpy(float)
    equity = np.r_[0., events.cumsum()]
    n = len(y); w=int((y>0).sum()); loss=int((y<0).sum()); flat=int((y==0).sum())
    dd=float(np.max(np.maximum.accumulate(equity)-equity))
    return dict(n=n,w=w,l=loss,flat=flat,wr=100*w/n if n else None,net_r=float(y.sum()),dd_r=dd,
                min_cum_r=float(equity.min()),score=score(w,n,dd),low_n=n<MIN_N)


def partition(frame, keep, codes):
    selected=frame.loc[keep]
    results=[]
    for bucket in [-1,0,1,2,3,4,5,6]:
        f=selected if bucket==-1 else frame.loc[keep&(codes==bucket)]
        annual=[]
        years=pd.to_datetime(f.entry_at_broker,unit='s').dt.year if len(f) else pd.Series([],dtype=int)
        for year in sorted(years.unique()):
            annual.append(dict(year=int(year),**statistics(f.loc[years==year])))
        results.append(dict(bucket=bucket,**statistics(f),years=annual))
    base=results[0]
    for k in ('n','w','l','flat'):
        if sum(r[k] for r in results[1:])!=base[k]:raise ValueError('Regime count reconciliation')
    if abs(sum(r['net_r'] for r in results[1:])-base['net_r'])>1e-8:raise ValueError('Regime PNL reconciliation')
    return results


def slot_mask(m, artifact, frame):
    slot.validate_artifact(m,artifact)
    v=slot.lines(artifact,1000000)
    if m['provider']=='ORB_MLP1':
        return portable_predict(artifact,frame[FEATURES].to_numpy(float),m['config'])>=float(v[6])
    at=7+155*int(v[5]); state=v[at:][-5:]; index=int(float(state[0])); a=v[7+155*index:7+155*(index+1)]
    model=dict(zip(('label','gain','loss','constant','bias'),map(float,a[:5])))
    model.update(mean=list(map(float,a[5::3])),scale=list(map(float,a[6::3])),coef=list(map(float,a[7::3])))
    return runtime.score_model(model,runtime.r7.r4.r3.returns.design(frame).to_numpy(float),float(state[4]))>=0


def report_bytes(r):
    fields=['ORB_REGIME_LB1','orb.regime.snapshot.v1',slot.feature_hash(),r['id'],r['config'],r['dataset'],r['mode'],
            r['model_sha'],str(r['from_time']),str(r['to_time']),EVAL,'SIGNAL_FEATURE_SNAPSHOT']
    for cell in r['cells']:
        fields.append(';'.join(str(cell[k]) if k in ('bucket','n','w','l','flat') else format(cell[k],'.17g')
                               for k in ('bucket','n','w','l','flat','net_r','dd_r','min_cum_r')))
    payload=('\n'.join(fields)+'\n').encode()
    return payload+slot.sha(payload).encode()+b'\n'


def rank_key(row):
    return (row['n']>=MIN_N,row['n']>0,row['score'],row['net_r'],row['id'],row['mode'])


def run(out=OUT, common=COMMON):
    out=Path(out);common=Path(common);out.mkdir(parents=True,exist_ok=True)
    campaign=json.loads(CAMPAIGN.read_text())
    registry={r['id']:r for r in json.loads((common/'OrbML/CampaignModels/adapter_verification.json').read_text())}
    rows=[];files=[];provenance=[];missing=[]
    for item in campaign:
        ident=item['preset_id'];frame,info=load_dataset(Path(item['csv']))
        if info['dataset_sha256']!=item['csv_sha256'] or info['preset_id']!=ident:raise ValueError('Source identity changed')
        raw=pd.read_csv(item['csv'])
        if len(raw.loc[(raw.label_valid==1)&(raw.features_valid!=1)]):raise ValueError('Closed trades have missing features')
        codes=regime_codes(frame)
        masks=[('VANILLA','-',np.ones(len(frame),bool),'')]
        if ident in registry:
            reg=registry[ident];path=common/'OrbML/CampaignModels'/(ident+'.experimental');data=path.read_bytes()
            if slot.sha(data)!=reg['model_sha'] or reg['config']!=info['config_hash'] or reg['dataset']!=info['dataset_sha256']:
                raise ValueError('Legacy identity changed')
            v=data.decode().splitlines()
            if reg['kind']=='MLP':keep=portable_predict(data,frame[FEATURES].to_numpy(float),reg['config'])>=float(v[6])
            else:
                pred=predict_return(data,runtime.r7.r4.r3.returns.design(frame).to_numpy(float))
                keep=pred>=float(v[5]) if v[6]=='1' else np.ones(len(frame),bool)
            masks.append(('LEGACY',reg['model_sha'],keep,reg['kind']))
            provenance.append(dict(path=str(path),sha256=slot.sha(data)))
        else:missing.append(dict(id=ident,mode='LEGACY'))
        pointer=common/'OrbML/Slots'/ident/'active.slot'
        if pointer.exists():
            data=pointer.read_bytes();m=slot.parse(data,ident)
            if m['config']!=info['config_hash'] or m['dataset']!=info['dataset_sha256']:raise ValueError('Slot dataset differs; regenerate campaign source')
            path=common/'OrbML/Slots/Artifacts'/(m['artifact']+'.model');artifact=path.read_bytes()
            masks.append(('R7',m['artifact'],slot_mask(m,artifact,frame),m['provider']+'@'+m['revision']))
            provenance.extend([dict(path=str(pointer),sha256=slot.sha(data)),dict(path=str(path),sha256=slot.sha(artifact))])
        else:missing.append(dict(id=ident,mode='R7'))
        for mode,model_sha,keep,revision in masks:
            r=dict(id=ident,name=item['name'],symbol=item['symbol'],config=info['config_hash'],dataset=info['dataset_sha256'],mode=mode,
                   model_sha=model_sha,revision=revision,from_time=int(info['window_from_broker']),to_time=int(info['asof_broker']),
                   cells=partition(frame,keep,codes))
            rows.append(r)
            name=ident+'_'+mode+'_'+('vanilla' if model_sha=='-' else model_sha)+'.regime'
            dest=out/'Files/OrbML/RegimeLeaderboard'/name;data=report_bytes(r);slot.atomic_write(dest,data)
            files.append(dict(name=name,sha256=slot.sha(data)))
        provenance.append(dict(path=item['csv'],sha256=info['dataset_sha256']))
        print(ident, len(frame), 'candidates', len(masks), 'modes',flush=True)
    # Detect a model switch or source edit during this campaign, before publishing the manifest.
    for p in provenance:
        if slot.sha(Path(p['path']).read_bytes())!=p['sha256']:raise ValueError('Input changed during campaign')
    payload=dict(protocol='ORB_REGIME_CAMPAIGN1',evaluation=EVAL,ml_evaluation='RETROSPECTIVE_TRAINING_INCLUDED_NOT_OOS',
                 min_n=MIN_N,regimes=NAMES,rows=rows,missing=missing,files=files,provenance=provenance)
    slot.atomic_write(out/'campaign.json',(json.dumps(payload,indent=2)+'\n').encode())
    write_summary(payload,out/'Results.md')
    print('Completed',len(rows),'strategy/modes;',len(rows)*6,'regime cells;',len(missing),'unavailable model modes')
    return payload


def write_summary(payload,path):
    rows=payload['rows']
    lines=['# Regime / Strategy / Model Results','','5Y: 2021-09-15 to 2026-09-09 (broker).',
           'ML includes training data: retrospective candidate-mask results, NOT OOS or order replay.',
           'Regime is the original signal feature snapshot. No new models were trained or activated.',
           'Ranking: 100 * Wilson lower WR / (1 + closed-trade DD R). N >= 30 for named leaders.',
           'A cell leader is exploratory, not proof of a deployable regime-selection policy.','']
    for symbol in sorted({r['symbol'] for r in rows}):
        lines += ['## '+symbol,'','| Regime | Strategy | Mode | N | W/L/F | WR | Net R | DD R | Score |',
                  '|---|---|---|---:|---|---:|---:|---:|---:|']
        for bucket,name in enumerate(NAMES):
            candidates=[dict(id=r['id'],name=r['name'],mode=r['mode'],**r['cells'][bucket+1]) for r in rows if r['symbol']==symbol]
            eligible=[r for r in candidates if r['n']>=MIN_N]
            if not eligible:
                lines.append(f'| {name} | Insufficient sample (N < 30) | - | - | - | - | - | - | - |');continue
            r=max(eligible,key=rank_key)
            lines.append(f"| {name} | {r['name']} | {r['mode']} | {r['n']} | {r['w']}/{r['l']}/{r['flat']} | {r['wr']:.2f}% | {r['net_r']:+.2f} | {r['dd_r']:.2f} | {r['score']:.2f} |")
        lines += ['','### Per-Regime Candidates And Annual Diagnostics','']
        for bucket,name in enumerate(NAMES):
            candidates=[dict(id=r['id'],name=r['name'],mode=r['mode'],**r['cells'][bucket+1]) for r in rows if r['symbol']==symbol and r['cells'][bucket+1]['n']>=MIN_N]
            lines += ['#### '+name,'']
            for r in sorted(candidates,key=rank_key,reverse=True)[:3]:
                annual=', '.join(f"{y['year']}: {y['net_r']:+.2f}R (N={y['n']})" for y in r['years'])
                lines.append(f"- `{r['id']}` / {r['mode']}: N={r['n']}, WR={r['wr']:.2f}%, Net={r['net_r']:+.2f}R, DD={r['dd_r']:.2f}R, Score={r['score']:.2f}. Years: {annual}.")
            if candidates:
                p=max(candidates,key=lambda r:r['net_r']);lines.append(f"- Highest net (not necessarily top score): `{p['id']}` / {p['mode']}, {p['net_r']:+.2f}R, DD={p['dd_r']:.2f}R, N={p['n']}.")
            else:lines.append('- No cell reaches N=30.')
            lines.append('')
    lines += ['## Coverage','',f"{len(rows)} available strategy/model pairs. {len(payload['missing'])} missing model modes are not treated as Vanilla.",
              'Six regimes + UNKNOWN reconcile to ALL for counts and net R; drawdowns are recomputed, not additive.',
              'Source CSVs may already reflect strategy-specific regime permissions. Zero observations are no evidence about an excluded regime.',
              'Annual diagnostics are descriptive, not untouched holdouts. No statistically corrected winner or overfit-free claim is made.','']
    slot.atomic_write(path,('\n'.join(lines)).encode())


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,default=OUT);p.add_argument('--common',type=Path,default=COMMON)
    a=p.parse_args();run(a.out,a.common)
