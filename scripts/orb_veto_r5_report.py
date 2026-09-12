"""R5 post-freeze diagnostics; all primary policies retained, no deployment."""
from pathlib import Path
import argparse
import json
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_veto_r5 as r5
from orb_training_age_r4_report import day_values
from orb_regime_campaign_report import block_diagnostic,fingerprint


def run(root,draws=20000):
    contract=r5.verify_inputs(root);records=[];ranks=[];incumbents=[];duplicates={}
    for year in r5.r4.YEARS:
        _,start,end=r5.r4.dates(year);matrix=[];refs=[];fold=[]
        for src in contract['inputs']:
            ident=src['id'];folder=root/ident/str(year)
            if not r5.r4.checkpoint_valid(folder):raise ValueError('Incomplete R5')
            f=pd.read_csv(folder/'predictions.csv');y=f.net_r.to_numpy(float)
            duplicates.setdefault(fingerprint(f),[]).append(dict(id=ident,year=year))
            frozen=json.loads((folder/'frozen_before_test.json').read_text())
            rows=json.loads((folder/'result.json').read_text())
            ranks.extend(json.loads((folder/'ranking.json').read_text()))
            for kind,spec in frozen['policies'].items():
                if r5.R.digest(spec['model_path'])!=spec['model_sha']:raise ValueError('Frozen model changed')
                if spec['discovery_label_max']>=r5.R.stamp(f'{year}-03-09')-r5.R.GAP or spec['confirmation_label_max']>=start-r5.R.GAP:
                    raise ValueError('Calibration crossed boundaries')
            for row in rows:
                name=row['policy'];kind=row['kind'];key=kind+'__'+name
                rule=frozen['policies'][kind]['rules'][name]
                k=f['keep_'+key].to_numpy(bool)
                np.testing.assert_array_equal(k,r5.apply(rule,f['score_'+kind].to_numpy(),f.regime.to_numpy()))
                np.testing.assert_allclose(r5.r4.r3.utility(f,k)['ml']['net_r'],row['test']['ml']['net_r'],atol=1e-8)
                old=f['old_'+kind].to_numpy(bool)
                row['delta_vs_old_threshold']=float(y@(k.astype(float)-old.astype(float)))
                if name in r5.POLICIES:
                    c=r5.r4.r3report.contrasts(f,k)
                    for i,metric in enumerate(('gain','skill')):
                        matrix.append(day_values(f,c[:,i],start,end));refs.append((row,metric,352))
                    matrix.append(day_values(f,y*(k.astype(float)-old.astype(float)),start,end));refs.append((row,'old_threshold',352))
                    if name=='regime_tail':
                        control=f['keep_'+kind+'__regime_only'].to_numpy(bool)
                        row['delta_vs_regime_only']=float(y@(k.astype(float)-control.astype(float)))
                        matrix.append(day_values(f,y*(k.astype(float)-control.astype(float)),start,end));refs.append((row,'regime_only',352))
                    if year==2025:
                        pair=f.loc[f.fair_pair==1].copy();new=k[f.fair_pair.to_numpy()==1]
                        incumbent=pair.incumbent_keep.to_numpy(bool)
                        a=r5.r4.r3.utility(pair,new);b=r5.r4.r3.utility(pair,incumbent)
                        rec=dict(id=ident,name=row['name'],kind=kind,policy=name,active=row['active'],new=a,old=b,
                                 delta_r=a['ml']['net_r']-b['ml']['net_r'],
                                 dd_delta=a['ml']['dd_r']-b['ml']['dd_r'],replacement_enabled=False)
                        incumbents.append(rec)
                        matrix.append(day_values(pair,pair.net_r.to_numpy()*(new.astype(float)-incumbent.astype(float)),start,end))
                        refs.append((rec,'incumbent',176))
                fold.append(row)
        data=np.column_stack(matrix)
        for block in (5,20):
            print('bootstrap',year,block,'contrasts',data.shape[1],flush=True)
            result=block_diagnostic(data,block,draws)
            for i,(row,metric,family) in enumerate(refs):
                p=float(result['p'][i])
                row.setdefault('bootstrap',{}).setdefault(str(block),{})[metric]=dict(
                    low=float(result['low'][i]),high=float(result['high'][i]),p=p,
                    p_family=min(1.,family*p),p1232=min(1.,1232*p))
        for row in fold:
            if row['policy'] not in r5.POLICIES:continue
            u=row['test'];n=u['base']['trades']
            lower=min(row['bootstrap'][str(b)]['gain']['low'] for b in (5,20))
            penalty=max(0.,u['gain']-lower)/n
            row['robustness_score']=100*(u['e']+.25*u['d']-row['quarter_stability']-row['selection_optimism']-penalty)
            row['corrected_base_pass']=all(row['bootstrap'][str(b)][metric]['p_family']<.05
                for b in (5,20) for metric in ('gain','skill'))
        records.extend(fold)
    for x in incumbents:
        x['economic_improvement']=bool(x['new']['ml']['retention']<1 and x['delta_r']>0 and x['dd_delta']<=0)
        x['corrected_pass']=all(x['bootstrap'][str(b)]['incumbent']['p_family']<.05 for b in (5,20))
    summary=[]
    for year in r5.r4.YEARS:
        for kind in r5.r4.KINDS:
            for name in (*r5.POLICIES,'regime_only'):
                sub=[x for x in records if (x['year'],x['kind'],x['policy'])==(year,kind,name)]
                def counts(values):
                    return [sum(x>1e-8 for x in values),sum(x< -1e-8 for x in values),sum(abs(x)<=1e-8 for x in values)]
                summary.append(dict(year=year,kind=kind,policy=name,
                    active=sum(x['active'] for x in sub),vetoed=sum(x['test']['ml']['retention']<1 for x in sub),
                    vs_base=counts([x['test']['gain'] for x in sub]),
                    vs_old_threshold=counts([x['delta_vs_old_threshold'] for x in sub]),
                    median_gain=float(np.median([x['test']['gain'] for x in sub])),
                    corrected_pass=sum(x.get('corrected_base_pass',False) for x in sub)))
    ranking_summary=[]
    for kind in r5.r4.KINDS:
        for year in r5.r4.YEARS:
            sub=[x for x in ranks if x['kind']==kind and x['year']==year]
            ranking_summary.append(dict(kind=kind,year=year,total=len(sub),
                discovery_positive=sum(x['discovery']['positive'] for x in sub),
                confirmation_positive=sum(x['confirmation']['positive'] for x in sub),
                gate_pass=sum(x['ranking_gate'] for x in sub),test_positive=sum(x['test']['positive'] for x in sub),
                gate_and_test_positive=sum(x['ranking_gate'] and x['test']['positive'] for x in sub)))
    r5.R.dump(root/'evaluation.json',dict(summary=summary,ranking_summary=ranking_summary,records=records,
        rankings=ranks,incumbents=incumbents,duplicate_groups=list(duplicates.values()),draws=draws,
        replacement_enabled=False,execution_replay_completed=False,prospective_shadow_completed=False))
    flat=[dict(id=x['id'],name=x['name'],year=x['year'],kind=x['kind'],policy=x['policy'],active=x['active'],
        net_r=x['test']['ml']['net_r'],dd_r=x['test']['ml']['dd_r'],base_r=x['test']['base']['net_r'],
        retention=x['test']['ml']['retention'],score=x.get('robustness_score'),
        delta_vs_old_threshold=x['delta_vs_old_threshold']) for x in records]
    r5.R.atomic_write(root/'policies.csv',pd.DataFrame(flat).to_csv(index=False).encode())
    lines=['# ORB Veto R5 Results','','Research only. Original models unchanged.','',
        '## Score Ranking','',
        'Positive = positive score/return Spearman AND positive top-minus-bottom mean net R.',
        'Quintile edges fixed in discovery; no test percentile fitting. Counts per 22 strategies.','',
        '| Model | Test year start | Discovery + | Confirmation + | Both/gate | Test + | Gate AND test + |',
        '|---|---:|---:|---:|---:|---:|---:|']
    for x in ranking_summary:
        lines.append(f"| {x['kind']} | {x['year']} | {x['discovery_positive']} | {x['confirmation_positive']} | {x['gate_pass']} | {x['test_positive']} | {x['gate_and_test_positive']} |")
    lines+=['','## Policies','',
        'B/W/S = better/worse/same net R. No-veto improvement over old threshold is not ML skill.','',
        '| Model | Year | Policy | Active | Test veto | Vs base B/W/S | Vs old threshold B/W/S |',
        '|---|---:|---|---:|---:|---:|---:|']
    for x in summary:
        fmt=lambda a:'/'.join(map(str,a))
        lines.append(f"| {x['kind']} | {x['year']} | {x['policy']} | {x['active']} | {x['vetoed']} | {fmt(x['vs_base'])} | {fmt(x['vs_old_threshold'])} |")
    lines+=['','## Final-Year Active Veto With Better PnL And DD Than Registered Model','',
        'Post-test observations, NOT a preselected strategy or promotion.','',
        '| Strategy | Model | Policy | Old / new R | Old / new DD |',
        '|---|---|---|---:|---:|']
    for x in incumbents:
        if x['economic_improvement']:
            lines.append(f"| {x['name']} | {x['kind']} | {x['policy']} | {x['old']['ml']['net_r']:+.2f} / {x['new']['ml']['net_r']:+.2f} | {x['old']['ml']['dd_r']:.2f} / {x['new']['ml']['dd_r']:.2f} |")
    lines+=['','## Limits','',
        f"- Primary policy cases: {sum(x['policy'] in r5.POLICIES for x in records)}; controls: {sum(x['policy']=='regime_only' for x in records)}.",
        f"- Both gain and monthly skill corrected passes versus base: {sum(x.get('corrected_base_pass',False) for x in records)}.",
        f"- Corrected passes versus registered incumbent: {sum(x['corrected_pass'] for x in incumbents)}.",
        '- Source strategy history was previously inspected. No pristine holdout claim.',
        '- Some strategy variants duplicate signals. Counts are not independent confirmations.',
        '- Bootstrap is approximate under regime drift; shrinkage bound is not a profit posterior.',
        '- R and DD are frozen closed-trade quantities, not account/EOD/floating results.',
        '- No stateful execution replay or new prospective shadow performed; no promotion.',
        '- Protocol and references: docs/ORB_Veto_R5_Protocol.md.']
    r5.R.atomic_write(root/'Results.md','\n'.join(lines).encode())
    r5.verify_inputs(root)
    print('R5 report complete; production replacements=0',flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=r5.ROOT)
    p.add_argument('--draws',type=int,default=20000);a=p.parse_args()
    with threadpool_limits(limits=1):run(a.root,a.draws)
