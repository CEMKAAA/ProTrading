"""Chronological four-year target comparisons. No post-test deployment."""
from pathlib import Path
import argparse
import json
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_target_r6 as r6
from orb_training_age_r4_report import day_values
from orb_regime_campaign_report import block_diagnostic,fingerprint


def run(root,draws=20000):
    c=r6.verify_contract(root);annual=[];records=[];incumbents=[];matrices=[];refs=[];groups={}
    start=r6.R.stamp('2022-09-09');end=r6.R.stamp('2026-09-09')
    for source in c['inputs']:
        ident=source['id'];parts=[];byyear=[]
        for year in r6.YEARS:
            folder=root/ident/str(year)
            if not r6.r4.checkpoint_valid(folder):raise ValueError('Invalid checkpoint')
            frozen=json.loads((folder/'frozen_before_test.json').read_text())
            for name,sha in frozen['hashes'].items():
                if r6.R.digest(folder/name)!=sha:raise ValueError('Changed model')
            f=pd.read_csv(folder/'predictions.csv');f['year']=year;parts.append(f)
            rows=json.loads((folder/'result.json').read_text());annual.extend(rows);byyear.extend(rows)
        f=pd.concat(parts,ignore_index=True);y=f.net_r.to_numpy();groups.setdefault(fingerprint(f),[]).append(ident)
        for kind in r6.KINDS:
            for policy in r6.POLICIES:
                k=f['keep_'+kind+'__'+policy].to_numpy(bool);u=r6.r4.r3.utility(f,k)
                old=f['keep_direct__'+policy].to_numpy(bool)
                rows=[x for x in byyear if x['kind']==kind and x['policy']==policy]
                std,_=r6.r4.r3report.quarter_stability(f,k)
                rec=dict(id=ident,name=source['name'],kind=kind,policy=policy,test=u,
                    annual_gain=[x['test']['gain'] for x in rows],
                    annual_net=[x['test']['ml']['net_r'] for x in rows],
                    annual_dd=[x['test']['ml']['dd_r'] for x in rows],
                    positive_years=sum(x['test']['gain']>0 for x in rows),
                    active_years=sum(x['active'] for x in rows),
                    optimism=float(np.mean([x['selection_optimism'] for x in rows])),quarter_stability=std,
                    delta_vs_direct=float(y@(k.astype(float)-old.astype(float))))
                records.append(rec)
                contrasts=r6.r4.r3report.contrasts(f,k)
                for i,metric in enumerate(('gain','skill')):
                    matrices.append(day_values(f,contrasts[:,i],start,end));refs.append((rec,metric))
                if kind!='direct':
                    matrices.append(day_values(f,y*(k.astype(float)-old.astype(float)),start,end));refs.append((rec,'direct'))
                    last=f.loc[(f.year==2025)&(f.fair_pair==1)].copy()
                    new=last['keep_'+kind+'__'+policy].to_numpy(bool);old_inc=last.incumbent_keep.to_numpy(bool)
                    a=r6.r4.r3.utility(last,new);b=r6.r4.r3.utility(last,old_inc)
                    inc=dict(id=ident,name=source['name'],kind=kind,policy=policy,new=a,old=b,
                        delta_r=a['ml']['net_r']-b['ml']['net_r'],dd_delta=a['ml']['dd_r']-b['ml']['dd_r'])
                    incumbents.append(inc)
                    # Last-year inference uses only its calendar, not three years
                    # of zero padding masquerading as independent observations.
        print(ident,'report data ready',flush=True)
    data=np.column_stack(matrices)
    for block in (5,20):
        print('four-year bootstrap',block,data.shape,flush=True);z=block_diagnostic(data,block,draws)
        for i,(rec,metric) in enumerate(refs):
            p=float(z['p'][i]);rec.setdefault('bootstrap',{}).setdefault(str(block),{})[metric]=dict(
                low=float(z['low'][i]),high=float(z['high'][i]),p=p,p132=min(1.,132*p),p528=min(1.,528*p))
    mats=[]
    for inc in incumbents:
        f=pd.read_csv(root/inc['id']/'2025'/'predictions.csv');f=f.loc[f.fair_pair==1].copy()
        a=f['keep_'+inc['kind']+'__'+inc['policy']].to_numpy(float);b=f.incumbent_keep.to_numpy(float)
        mats.append(day_values(f,f.net_r.to_numpy()*(a-b),r6.R.stamp('2025-09-09'),end))
    data=np.column_stack(mats)
    for block in (5,20):
        print('incumbent bootstrap',block,flush=True);z=block_diagnostic(data,block,draws)
        for i,rec in enumerate(incumbents):
            p=float(z['p'][i]);rec.setdefault('bootstrap',{})[str(block)]=dict(low=float(z['low'][i]),
                high=float(z['high'][i]),p=p,p132=min(1.,132*p),p528=min(1.,528*p))
    for rec in records:
        u=rec['test'];n=u['base']['trades']
        lower=min(rec['bootstrap'][str(b)]['gain']['low'] for b in (5,20))
        rec['score']=100*(u['e']+.25*u['d']-rec['quarter_stability']-rec['optimism']-max(0.,u['gain']-lower)/n)
        rec['historical_screen']=bool(rec['kind']!='direct' and rec['positive_years']>=3 and
            u['gain']>0 and u['skill']>0 and u['ml']['dd_r']<=u['base']['dd_r'] and
            all(rec['bootstrap'][str(b)][metric]['p132']<.05 for b in (5,20) for metric in ('gain','skill','direct')))
        rec['promotion_approved']=False
    for inc in incumbents:
        inc['corrected_pass']=all(inc['bootstrap'][str(b)]['p132']<.05 for b in (5,20))
    summary=[]
    for kind in r6.KINDS:
        for policy in r6.POLICIES:
            sub=[x for x in records if x['kind']==kind and x['policy']==policy]
            counts=lambda v:[sum(x>1e-8 for x in v),sum(x< -1e-8 for x in v),sum(abs(x)<=1e-8 for x in v)]
            summary.append(dict(kind=kind,policy=policy,vs_base=counts([x['test']['gain'] for x in sub]),
                vs_direct=counts([x['delta_vs_direct'] for x in sub]),
                positive_three_years=sum(x['positive_years']>=3 for x in sub),
                historical_screen=sum(x['historical_screen'] for x in sub)))
    r6.R.dump(root/'evaluation.json',dict(summary=summary,records=records,annual=annual,incumbents=incumbents,
        duplicate_groups=list(groups.values()),draws=draws,replacement_enabled=False,
        execution_replay_completed=False,prospective_shadow_completed=False))
    flat=[dict(id=x['id'],name=x['name'],kind=x['kind'],policy=x['policy'],
        base_r=x['test']['base']['net_r'],net_r=x['test']['ml']['net_r'],dd_r=x['test']['ml']['dd_r'],
        base_dd=x['test']['base']['dd_r'],retention=x['test']['ml']['retention'],
        positive_years=x['positive_years'],delta_direct=x['delta_vs_direct'],score=x['score']) for x in records]
    r6.R.atomic_write(root/'models.csv',pd.DataFrame(flat).to_csv(index=False).encode())
    lines=['# ORB Target R6 Results','','Research only; no live model replaced.',
        'Four chronological test years: September 2022 through September 2026.',
        '22 USDJPY strategies, same original 50 features; 352 model bundles, 704 policy-year outcomes.',
        'Historical periods already inspected. Six-day source export gap in 2021.','',
        '## Four-Year Comparison','',
        'B/W/S: better/worse/same PnL. Counts are correlated strategies, not independent trials.',
        'Same-policy direct regressor is the target-ablation reference.','',
        '| Model | Policy | Vs base B/W/S | Vs direct B/W/S | Gain in >=3 years | Historical screen |',
        '|---|---|---:|---:|---:|---:|']
    for x in summary:
        fmt=lambda v:'/'.join(map(str,v))
        lines.append(f"| {x['kind']} | {x['policy']} | {fmt(x['vs_base'])} | {fmt(x['vs_direct'])} | {x['positive_three_years']} | {x['historical_screen']} |")
    lines+=['','## Positive Gain In At Least Three Years','',
        'Retrospective observations. No post-test candidate promotion.','',
        '| Strategy | Model | Policy | Base / model net R | Base / model DD | Annual gains R |',
        '|---|---|---|---:|---:|---|']
    for x in records:
        if x['kind']!='direct' and x['positive_years']>=3 and x['test']['gain']>0:
            u=x['test'];g='/'.join(f'{v:+.2f}' for v in x['annual_gain'])
            lines.append(f"| {x['name']} | {x['kind']} | {x['policy']} | {u['base']['net_r']:+.2f} / {u['ml']['net_r']:+.2f} | {u['base']['dd_r']:.2f} / {u['ml']['dd_r']:.2f} | {g} |")
    lines+=['','## Limits','',
        f"- Historical screen passes: {sum(x['historical_screen'] for x in records)}.",
        f"- Corrected registered-incumbent comparisons: {sum(x['corrected_pass'] for x in incumbents)}.",
        '- No deployable model export or production replacement.',
        '- No outcome/feature changes, parameter search or selected-winner portfolio.',
        '- No new prospective shadow or stateful execution replay.',
        '- Score is engineering utility, not probability of overfit.',
        '- Closed-trade DD excludes EOD/floating/account risk. Bootstrap approximate under drift.',
        '- Methods and sources: docs/ORB_Target_R6_Protocol.md.']
    r6.R.atomic_write(root/'Results.md','\n'.join(lines).encode());r6.verify_contract(root)
    print('R6 report complete; promotions=0',flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=r6.ROOT)
    p.add_argument('--draws',type=int,default=20000);a=p.parse_args()
    with threadpool_limits(limits=1):run(a.root,a.draws)
