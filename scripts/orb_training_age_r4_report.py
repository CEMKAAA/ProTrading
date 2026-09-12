"""Post-freeze matched diagnostics. No model fitting, selection or deployment."""
from pathlib import Path
import argparse
import json
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_training_age_r4 as experiment
from orb_regime_campaign_report import block_diagnostic, fingerprint

R=experiment.R


def score(record, lower):
    u=record['test']; n=u['base']['trades']
    uncertainty=max(0.,u['gain']-lower)/n
    return dict(score=100*(u['e']+.25*u['d']-record['quarter_stability']-
                          record['train_optimism']-uncertainty),
                uncertainty_penalty=uncertainty,optimism_penalty=record['train_optimism'])


def day_values(f, value, start, end):
    daily=np.zeros((end-start)//86400+1)
    idx=(f.exit_at_broker.to_numpy(np.int64)//86400-start//86400).astype(int)
    if (idx<0).any() or (idx>=len(daily)).any(): raise ValueError('Daily index outside fold')
    np.add.at(daily,idx,value)
    np.testing.assert_allclose(daily.sum(),value.sum(),atol=1e-8)
    return daily


def run(root,draws=20000):
    contract=experiment.assert_frozen(root)
    records=[];comparisons=[];incumbents=[];groups={};checks=[]
    for year in experiment.YEARS:
        _,start,end=experiment.dates(year)
        columns=[];references=[];fold=[]
        for source in contract['inputs']:
            ident=source['id'];folder=root/ident/str(year)
            if not experiment.checkpoint_valid(folder): raise ValueError('Incomplete training')
            frozen=json.loads((folder/'frozen_before_test.json').read_text())
            rows=json.loads((folder/'result.json').read_text())
            f=pd.read_csv(folder/'predictions.csv');y=f.net_r.to_numpy()
            groups.setdefault(fingerprint(f),[]).append(dict(id=ident,year=year))
            for rec in rows:
                key=rec['kind']+'__'+rec['arm'];path=folder/(key+'.research.joblib')
                if R.digest(path)!=frozen['hashes'][path.name]: raise ValueError('Changed fit')
                m=joblib.load(path)
                if m['identity']['strategy']!=ident or m['meta']!=rec['meta']:
                    raise ValueError('Model metadata mismatch')
                if rec['meta']['last_label']>=rec['meta']['cutoff']-R.GAP or rec['cal_label_max']>=start-R.GAP:
                    raise ValueError('Temporal leakage')
                checks.append(dict(id=ident,year=year,key=key,rows=m['meta']['rows']))
                keep=f['keep_'+key].to_numpy(bool)
                np.testing.assert_array_equal(keep,f['score_'+key].to_numpy()>=rec['threshold'])
                np.testing.assert_allclose(experiment.r3.utility(f,keep)['ml']['net_r'],rec['test']['ml']['net_r'],atol=1e-8)
                c=experiment.r3report.contrasts(f,keep)
                for i,metric in enumerate(('gain','skill')):
                    columns.append(day_values(f,c[:,i],start,end));references.append((rec,metric))
                if rec['arm']!='all':
                    base=f['keep_'+rec['kind']+'__all'].to_numpy(bool)
                    all_row=next(x for x in rows if x['kind']==rec['kind'] and x['arm']=='all')
                    cmp=dict(id=ident,name=rec['name'],year=year,kind=rec['kind'],arm=rec['arm'],
                        delta_r=float(y@(keep.astype(float)-base.astype(float))),
                        dd_delta=rec['test']['ml']['dd_r']-all_row['test']['ml']['dd_r'],
                        fixed0_delta=rec['fixed0']['ml']['net_r']-all_row['fixed0']['ml']['net_r'],
                        gated_delta=rec['gated']['ml']['net_r']-all_row['gated']['ml']['net_r'],
                        r2_delta=rec['r2_vs_train_mean']-all_row['r2_vs_train_mean'],
                        mean_shift_delta=rec['test_shift']['median_standardized_mean_shift']-
                            all_row['test_shift']['median_standardized_mean_shift'],
                        regime_shift_delta=rec['test_shift']['regime_total_variation']-
                            all_row['test_shift']['regime_total_variation'])
                    comparisons.append(cmp)
                    columns.append(day_values(f,y*(keep.astype(float)-base.astype(float)),start,end))
                    references.append((cmp,'vs_all'))
                if year==2025:
                    fair=f.fair_pair.to_numpy(bool);paired=f.loc[fair].copy()
                    old=paired.incumbent_keep.to_numpy(bool);new=keep[fair]
                    old_u=experiment.r3.utility(paired,old);new_u=experiment.r3.utility(paired,new)
                    inc=dict(id=ident,name=rec['name'],kind=rec['kind'],arm=rec['arm'],
                        old=old_u,new=new_u,rows=len(paired),
                        delta_r=new_u['ml']['net_r']-old_u['ml']['net_r'],
                        dd_delta=new_u['ml']['dd_r']-old_u['ml']['dd_r'],
                        information_end=source['incumbent_information_end'])
                    incumbents.append(inc)
                    columns.append(day_values(paired,paired.net_r.to_numpy()*(new.astype(float)-old.astype(float)),start,end))
                    references.append((inc,'vs_incumbent'))
                fold.append(rec)
        matrix=np.column_stack(columns)
        for block in (5,20):
            print('bootstrap',year,block,len(columns),'contrasts',flush=True)
            stats=block_diagnostic(matrix,block,draws)
            for i,(record,metric) in enumerate(references):
                p=float(stats['p'][i])
                record.setdefault('bootstrap',{}).setdefault(str(block),{})[metric]=dict(
                    low=float(stats['low'][i]),high=float(stats['high'][i]),p=p,
                    p264=min(1.,264*p),p176=min(1.,176*p),p440=min(1.,440*p))
        for rec in fold:
            lower=min(rec['bootstrap'][str(b)]['gain']['low'] for b in (5,20))
            rec['robustness']=score(rec,lower)
        records.extend(fold)
    for c in comparisons:
        c['corrected_pass']=all(c['bootstrap'][str(b)]['vs_all']['p264']<.05 for b in (5,20))
    for c in incumbents:
        c['corrected_pass']=all(c['bootstrap'][str(b)]['vs_incumbent']['p176']<.05 for b in (5,20))
        c['promotion_approved']=False
    summary=[]
    for kind in experiment.KINDS:
        for arm in experiment.ARMS:
            for year in experiment.YEARS:
                subset=[x for x in records if (x['kind'],x['arm'],x['year'])==(kind,arm,year)]
                cs=[x for x in comparisons if (x['kind'],x['arm'],x['year'])==(kind,arm,year)]
                counts=lambda values: dict(better=int(sum(x>1e-8 for x in values)),
                    worse=int(sum(x< -1e-8 for x in values)),same=int(sum(abs(x)<=1e-8 for x in values)))
                summary.append(dict(kind=kind,arm=arm,year=year,strategies=len(subset),
                    vs_unfiltered=counts([x['test']['gain'] for x in subset]),
                    vs_all=counts([x['delta_r'] for x in cs]),
                    median_delta_vs_all=float(np.median([x['delta_r'] for x in cs])) if cs else 0.,
                    median_gain=float(np.median([x['test']['gain'] for x in subset])),
                    median_score=float(np.median([x['robustness']['score'] for x in subset])),
                    median_optimism=float(np.median([x['train_optimism'] for x in subset])),
                    calibration_gate_pass=sum(x['cal_gate'] for x in subset),
                    corrected_pass=sum(x['corrected_pass'] for x in cs)))
    # Duplicate variants are not independent confirmations of a finding.
    seen=set();unique=[]
    id_group={}
    for fingerprint_id,members in groups.items():
        for m in members:id_group[(m['id'],m['year'])]=fingerprint_id
    for row in comparisons:
        key=(id_group[(row['id'],row['year'])],row['kind'],row['arm'],row['year'])
        if key not in seen: unique.append(row);seen.add(key)
    R.dump(root/'evaluation.json',dict(summary=summary,records=records,comparisons=comparisons,
        unique_comparisons=unique,incumbents=incumbents,duplicate_groups=list(groups.values()),
        model_checks=checks,draws=draws,replacement_enabled=False))
    flat=[]
    for r in records:
        flat.append(dict(id=r['id'],name=r['name'],year=r['year'],kind=r['kind'],arm=r['arm'],
            net_r=r['test']['ml']['net_r'],base_r=r['test']['base']['net_r'],dd_r=r['test']['ml']['dd_r'],
            wr=r['test']['ml']['wr'],retention=r['test']['ml']['retention'],score=r['robustness']['score'],
            fit_n=r['meta']['rows'],effective_n=r['meta']['effective_n'],threshold=r['threshold'],
            cal_gate=r['cal_gate'],fixed0_r=r['fixed0']['ml']['net_r'],gated_r=r['gated']['ml']['net_r']))
    R.atomic_write(root/'models.csv',pd.DataFrame(flat).to_csv(index=False).encode())
    lines=['# ORB Training-Age R4 Results','','Research only. No production replacement.',
        'Test years: Sep 2024-Sep 2025 and Sep 2025-Sep 2026. Broker timestamp axis.',
        '22 USDJPY strategies; some exact duplicate signal series; not independent experiments.',
        'Same 50 features and model settings. 352 fits; all-history final fits reproduce R3.',
        'Six-day export gap in September 2021. Test history has previously been inspected.','',
        '## Matched Data-Age Ablation','',
        'B/W/S counts compare PnL against same-model all-history on identical test trades.',
        'Medians below are strategy diagnostics, NOT account/portfolio returns.','',
        '| Model | Window | Test start year | Vs all B/W/S | Median delta R | Vs base B/W/S | Cal gate pass |',
        '|---|---|---:|---:|---:|---:|---:|']
    for s in summary:
        fmt=lambda d:f"{d['better']}/{d['worse']}/{d['same']}"
        lines.append(f"| {s['kind']} | {s['arm']} | {s['year']} | {fmt(s['vs_all'])} | {s['median_delta_vs_all']:+.2f} | {fmt(s['vs_unfiltered'])} | {s['calibration_gate_pass']}/22 |")
    lines+=['','## Positive In Both Test Years Versus All History','',
        'These are retrospective observations, NOT pre-test-selected live policies.','',
        '| Strategy | Model | Arm | First delta R | Second delta R | First DD delta | Second DD delta |',
        '|---|---|---|---:|---:|---:|---:|']
    consistent=[]
    for c in comparisons:
        if c['year']!=2024 or c['delta_r']<=1e-8:continue
        other=next(x for x in comparisons if (x['id'],x['kind'],x['arm'],x['year'])==(c['id'],c['kind'],c['arm'],2025))
        if other['delta_r']>1e-8:
            consistent.append((c,other))
            lines.append(f"| {c['name']} | {c['kind']} | {c['arm']} | {c['delta_r']:+.2f} | {other['delta_r']:+.2f} | {c['dd_delta']:+.2f} | {other['dd_delta']:+.2f} |")
    lines+=['','## Controls And Limitations','',
        f"- Checked trained models: {len(checks)}. Paired all-history contrasts: {len(comparisons)}; deduplicated: {len(unique)}.",
        f"- All-history comparisons passing both block lengths, family 264: {sum(x['corrected_pass'] for x in comparisons)}.",
        f"- Incumbent comparisons passing both block lengths, family 176: {sum(x['corrected_pass'] for x in incumbents)}.",
        '- Live promotions: 0. Neither models nor thresholds were written to terminals.',
        '- Equal total weight fixes relative L2 strength; raw sample count/coverage still differ.',
        '- Covariate drift and train optimism are proxies, not causal proof or overfit probability.',
        '- Test-score formula and half-life were fixed before training; no test-driven refit.',
        '- Closed-trade DD excludes floating/EOD limits; frozen-row veto is not stateful execution replay.',
        '- Source strategy parameters were historically researched. The two years are not pristine holdouts.',
        '- Missing candles inside exports are not reconstructed. Registry/model hashes are checked, not live chart state.',
        '- Method and citations: docs/ORB_TrainingAge_R4_Protocol.md.']
    R.atomic_write(root/'Results.md','\n'.join(lines).encode())
    experiment.assert_frozen(root)
    now=experiment.production_snapshot()
    changed=[p for p,sha in contract['production'].items() if now.get(p)!=sha]
    R.dump(root/'production_integrity.json',dict(files_checked=len(now),differences=changed))
    if changed:raise ValueError('Production changed')
    print('R4 report complete; models',len(checks),'promotions 0',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=experiment.ROOT)
    parser.add_argument('--draws',type=int,default=20000);args=parser.parse_args()
    with threadpool_limits(limits=1):run(args.root,args.draws)
