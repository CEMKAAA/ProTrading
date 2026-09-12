"""All-candidate R7 evidence; no retrospective winner deployment."""
import argparse
import json
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_calibration_r7 as r7
from orb_training_age_r4_report import day_values
from orb_regime_campaign_report import block_diagnostic,fingerprint


def counts(values):
    return [sum(v>1e-8 for v in values),sum(v< -1e-8 for v in values),sum(abs(v)<=1e-8 for v in values)]


def run(root,draws):
    c=r7.verify_contract(root);records=[];incumbents=[];annual=[];matrices=[];refs=[];imats=[];groups={}
    start=r7.R.stamp('2022-09-09');end=r7.R.stamp('2026-09-09')
    for source in c['inputs']:
        ident=source['id'];parts=[];byyear=[]
        for year in r7.r6.YEARS:
            folder=root/ident/str(year)
            if not r7.r4.checkpoint_valid(folder):raise ValueError('Changed checkpoint')
            for p,sha in json.loads((folder/'model_hashes.json').read_text()).items():
                if r7.R.digest(p)!=sha:raise ValueError('Changed base model')
            f=pd.read_csv(folder/'predictions.csv');f['year']=year;parts.append(f)
            rows=json.loads((folder/'result.json').read_text());byyear.extend(rows);annual.extend(rows)
        f=pd.concat(parts,ignore_index=True);groups.setdefault(fingerprint(f),[]).append(ident);y=f.net_r.to_numpy()
        for kind in r7.KINDS:
            old=f['keep_'+kind+'__raw'].to_numpy(bool)
            for arm in r7.ARMS:
                k=f['keep_'+kind+'__'+arm].to_numpy(bool);u=r7.r4.r3.utility(f,k)
                rows=[x for x in byyear if x['kind']==kind and x['arm']==arm]
                rawrows=[x for x in byyear if x['kind']==kind and x['arm']=='raw']
                delta=[x['test']['ml']['net_r']-o['test']['ml']['net_r'] for x,o in zip(rows,rawrows)]
                rec=dict(id=ident,name=source['name'],kind=kind,arm=arm,test=u,
                    annual_gain=[x['test']['gain'] for x in rows],annual_net=[x['test']['ml']['net_r'] for x in rows],
                    annual_raw_delta=delta,positive_years=sum(x['test']['gain']>0 for x in rows),
                    positive_raw_years=sum(v>1e-8 for v in delta),min_year_kept=min(x['test']['ml']['trades'] for x in rows),
                    delta_raw=float(y@(k.astype(float)-old.astype(float))),
                    brier=float(np.mean((f['prob_'+kind+'__'+arm].to_numpy()-(y>0))**2)),
                    probability_bias=float(f['prob_'+kind+'__'+arm].mean()-(y>0).mean()))
                records.append(rec);contrasts=r7.r4.r3report.contrasts(f,k)
                for i,metric in enumerate(('gain','skill')):
                    matrices.append(day_values(f,contrasts[:,i],start,end));refs.append((rec,metric))
                if arm!='raw':
                    matrices.append(day_values(f,y*(k.astype(float)-old.astype(float)),start,end));refs.append((rec,'raw'))
                    last=f.loc[(f.year==2025)&(f.fair_pair==1)].copy()
                    new=last['keep_'+kind+'__'+arm].to_numpy(bool);oldinc=last.incumbent_keep.to_numpy(bool)
                    a=r7.r4.r3.utility(last,new);b=r7.r4.r3.utility(last,oldinc)
                    inc=dict(id=ident,name=source['name'],kind=kind,arm=arm,new=a,old=b,
                        delta_r=a['ml']['net_r']-b['ml']['net_r'],dd_delta=a['ml']['dd_r']-b['ml']['dd_r'])
                    incumbents.append(inc)
                    imats.append(day_values(last,last.net_r.to_numpy()*(new.astype(float)-oldinc.astype(float)),
                        r7.R.stamp('2025-09-09'),end))
        print(ident,'report ready',flush=True)
    for block in (5,20):
        print('Bootstrap',block,flush=True);z=block_diagnostic(np.column_stack(matrices),block,draws)
        for i,(rec,metric) in enumerate(refs):
            p=float(z['p'][i]);rec.setdefault('bootstrap',{}).setdefault(str(block),{})[metric]=dict(
                low=float(z['low'][i]),high=float(z['high'][i]),p=p,p176=min(1.,176*p),p704=min(1.,704*p))
        z=block_diagnostic(np.column_stack(imats),block,draws)
        for i,rec in enumerate(incumbents):
            p=float(z['p'][i]);rec.setdefault('bootstrap',{})[str(block)]=dict(
                low=float(z['low'][i]),high=float(z['high'][i]),p=p,p176=min(1.,176*p),p704=min(1.,704*p))
    for rec in records:
        u=rec['test']
        rec['historical_screen']=bool(rec['arm']!='raw' and rec['positive_years']>=3 and rec['positive_raw_years']>=3
            and rec['min_year_kept']>=20 and u['ml']['retention']>=.4 and u['ml']['dd_r']<=u['base']['dd_r']
            and u['gain']>0 and u['skill']>0 and rec['delta_raw']>0
            and all(rec['bootstrap'][str(b)][m]['p176']<.05 for b in (5,20) for m in ('gain','skill','raw')))
        rec['promotion_approved']=False
    for rec in incumbents:
        rec['corrected_pass']=all(rec['bootstrap'][str(b)]['p176']<.05 for b in (5,20))
    summary=[]
    for kind in r7.KINDS:
        for arm in r7.ARMS:
            sub=[x for x in records if x['kind']==kind and x['arm']==arm]
            summary.append(dict(kind=kind,arm=arm,vs_base=counts([x['test']['gain'] for x in sub]),
                vs_raw=counts([x['delta_raw'] for x in sub]),positive_three_years=sum(x['positive_years']>=3 for x in sub),
                historical_screen=sum(x['historical_screen'] for x in sub)))
    result=dict(summary=summary,records=records,annual=annual,incumbents=incumbents,duplicate_groups=list(groups.values()),
        draws=draws,replacement_enabled=False,execution_replay_completed=False,prospective_shadow_completed=False)
    r7.R.dump(root/'evaluation.json',result)
    flat=[dict(id=x['id'],name=x['name'],kind=x['kind'],arm=x['arm'],base_r=x['test']['base']['net_r'],
        net_r=x['test']['ml']['net_r'],dd_r=x['test']['ml']['dd_r'],base_dd=x['test']['base']['dd_r'],
        retention=x['test']['ml']['retention'],delta_raw=x['delta_raw'],brier=x['brier'],bias=x['probability_bias']) for x in records]
    r7.R.atomic_write(root/'models.csv',pd.DataFrame(flat).to_csv(index=False).encode())
    lines=['# ORB R7 Calibration Results','','Research only; historical, not a pristine holdout.',
        '22 USDJPY strategies; four Sep-to-Sep test years; no production changes.','',
        '| Family | Arm | Vs base better/worse/same | Vs raw better/worse/same | >=3 years base gain | Screen |',
        '|---|---|---:|---:|---:|---:|']
    for x in summary:
        fmt=lambda v:'/'.join(map(str,v))
        lines.append(f"| {x['kind']} | {x['arm']} | {fmt(x['vs_base'])} | {fmt(x['vs_raw'])} | {x['positive_three_years']} | {x['historical_screen']} |")
    lines+=['','## Temporal Check','',
        '| Family | Arm | Improved base count by year | Improved raw count by year |',
        '|---|---|---|---|']
    for kind in r7.KINDS:
        for arm in r7.ARMS:
            rows=[x for x in records if x['kind']==kind and x['arm']==arm]
            gain=[sum(x['annual_gain'][i]>0 for x in rows) for i in range(4)]
            raw=[sum(x['annual_raw_delta'][i]>1e-8 for x in rows) for i in range(4)]
            lines.append(f"| {kind} | {arm} | {gain} | {raw} |")
    lines+=['','## Limits','',f"- Historical screen: {sum(x['historical_screen'] for x in records)}.",
        f"- Corrected incumbent comparisons: {sum(x['corrected_pass'] for x in incumbents)}.",
        '- All candidates and failures retained in evaluation.json. No best-test-family selector.',
        '- Existing setup CSV outcomes used even for rejected signals; not live shadow collection.',
        '- Month updates use only earlier closed labels with 24h delay.',
        '- DD is closed-trade R, not EOD/floating challenge risk.',
        '- No stateful execution replay or new prospective shadow; no deployment.',
        '- Block bootstrap assumes approximate stationarity. Previously searched years are not fresh evidence.']
    r7.R.atomic_write(root/'Results.md','\n'.join(lines).encode());r7.verify_contract(root)
    print('R7 report complete; no replacement',flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=r7.ROOT);p.add_argument('--draws',type=int,default=20000)
    a=p.parse_args()
    with threadpool_limits(limits=1):run(a.root,a.draws)
