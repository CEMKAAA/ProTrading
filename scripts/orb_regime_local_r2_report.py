"""Post-freeze, strategy-local campaign audit; never writes production models."""
from pathlib import Path
import argparse
import json
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_regime_local_r2 as r2
from orb_regime_campaign_report import daily_contrasts, block_diagnostic, fingerprint


def run(root, draws=20000):
    contract=json.loads((root/'contract.json').read_text())
    for path,sha in contract['code'].items():
        if r2.r1.digest(path)!=sha: raise ValueError('Changed frozen training code/protocol')
    names={x['id']:x['name'] for x in contract['inputs']}
    source={x['id']:x for x in contract['inputs']}
    data=[];annual=[];checks=[];regime_effects=[]
    for year in (2024,2025,2026):
        folder=root/str(year)
        done=json.loads((folder/'complete.json').read_text())
        for name,sha in done['artifacts'].items():
            if r2.r1.digest(folder/name)!=sha: raise ValueError('Changed frozen artifact')
        for path in folder.glob('*/*.joblib'):
            m=joblib.load(path)
            end=r2.r1.stamp(f'{year-1}-'+('01-01' if path.parent.name=='development' else '07-01'))
            if m['train_label_max']>=end-r2.r1.GAP: raise ValueError('Training label leakage')
            s=m['scaler']
            if not np.isfinite(s.scale_).all() or (s.scale_<=0).any(): raise ValueError('Invalid scaler')
            if m['identity']['strategy'] not in names: raise ValueError('Unbound model')
            ident=m['identity']['strategy']
            if m['identity']['symbol']!=source[ident]['symbol']: raise ValueError('Symbol mismatch')
            checks.append(dict(year=year,stage=path.parent.name,id=ident,kind=m['kind'],rows=m['train_rows']))
            if m['penalty'] is not None:
                p=len(m['features'])
                deviations=m['model'].coef_[p:].reshape(6,9)*np.sqrt(100./m['penalty'])
                for regime,n in enumerate(m['regime_counts']):
                    if not n and not np.allclose(deviations[regime],0.,atol=1e-10):
                        raise ValueError('Unseen regime has learned deviation')
                    regime_effects.append(dict(year=year,stage=path.parent.name,id=ident,kind=m['kind'],
                        regime=regime,train_count=n,deviation_norm=float(np.linalg.norm(deviations[regime])),
                        coefficients=deviations[regime].tolist()))
        data.append(pd.read_csv(folder/'predictions.csv'))
        annual.extend(json.loads((folder/'summary.json').read_text()))
    f=pd.concat(data,ignore_index=True)
    records=[];paired=[];regimes=[]
    for ident,s in f.groupby('strategy',sort=True):
        base=r2.r1.stats(s,np.ones(len(s),bool));ml=r2.r1.stats(s,s.keep.to_numpy(bool))
        records.append(dict(id=ident,name=names[ident],symbol=str(s.symbol.iloc[0]),base=base,ml=ml,
            **r2.r1.selection_value(s,s.keep.to_numpy(bool)),fingerprint=fingerprint(s),
            selected_years=[int(x) for x in s.loc[s.kind!='NO_VETO','year'].unique()]))
        for a,b in [('local_base','local_flat_regime'),('local_flat_regime','local_hier_100'),
                    ('local_flat_regime','local_hier_400')]:
            ca,cb='keep_'+a,'keep_'+b
            common=s.loc[s[ca].notna() & s[cb].notna()] if ca in s and cb in s else s.iloc[:0]
            if common.empty: continue
            sa=r2.r1.stats(common,common[ca].to_numpy(bool));sb=r2.r1.stats(common,common[cb].to_numpy(bool))
            va=r2.r1.selection_value(common,common[ca].to_numpy(bool))
            vb=r2.r1.selection_value(common,common[cb].to_numpy(bool))
            paired.append(dict(id=ident,a=a,b=b,rows=len(common),baseline=sa,candidate=sb,
                               gain=sb['net_r']-sa['net_r'],month_skill_gain=vb['skill']-va['skill']))
        for j in range(6):
            t=s.loc[s['f_regime'+str(j)]==1]
            regimes.append(dict(id=ident,regime=j,base=r2.r1.stats(t,np.ones(len(t),bool)),
                                ml=r2.r1.stats(t,t.keep.to_numpy(bool))))
    ids=[r['id'] for r in records]
    matrix=daily_contrasts(f,ids,r2.r1.stamp('2024-01-01')//86400,contract['cutoff']//86400)
    for b in (5,20):
        print(f'{b}-day paired block diagnostic, {draws} draws',flush=True)
        result=block_diagnostic(matrix,b,draws)
        for j,rec in enumerate(records):
            np.testing.assert_allclose(result['actual'][2*j:2*j+2],[rec['gain'],rec['skill']],atol=1e-8)
            metrics={}
            for k,name in enumerate(('gain','month_skill')):
                i=2*j+k;p=float(result['p'][i])
                metrics[name]=dict(low=float(result['low'][i]),high=float(result['high'][i]),
                    p_raw=p,p_bonferroni53=min(1.,53*p),p_bonferroni530=min(1.,530*p))
            rec.setdefault('uncertainty',{})[str(b)]=metrics
    for r in records:
        for factor in (53,530):
            r['pass'+str(factor)]=bool(r['gain']>0 and r['skill']>0 and all(
                r['uncertainty'][str(b)][m]['p_bonferroni'+str(factor)]<.05
                for b in (5,20) for m in ('gain','month_skill')))
    # These are known duplicates; do not count them as independent experiments.
    dup={}
    for r in records: dup.setdefault(r['fingerprint'],[]).append(r['id'])
    result=dict(contract=contract['policy'],fresh_holdout=False,production_deployed=False,
        fitted_bundles=len(checks),records=records,annual=annual,paired_candidates=paired,
        regime_results=regimes,regime_coefficients=regime_effects,model_checks=checks,
        unique_outcome_series=len(dup),duplicates=[v for v in dup.values() if len(v)>1])
    r2.r1.dump(root/'evaluation.json',result)
    rows=[]
    for r in records:
        rows.append(dict(id=r['id'],name=r['name'],symbol=r['symbol'],base_n=r['base']['trades'],
            ml_n=r['ml']['trades'],base_r=r['base']['net_r'],ml_r=r['ml']['net_r'],gain_r=r['gain'],
            month_skill_r=r['skill'],base_wr=r['base']['wr'],ml_wr=r['ml']['wr'],
            base_dd=r['base']['dd_r'],ml_dd=r['ml']['dd_r'],pass53=r['pass53'],pass530=r['pass530']))
    r2.r1.atomic_write(root/'comparison.csv',pd.DataFrame(rows).to_csv(index=False).encode())
    lines=['# Strategy-Local Regime R2 Results','','Research only. No model deployment.',
        'Each strategy model used only its own CSV, identity and training outcomes.',
        'Regime deviations shrink toward the same strategy shared component, not toward other strategies.',
        '', '## Pre-Test-Selected Policy', '',
        '| Year | Selected models | Improved R | Worse R | Unchanged |', '|---|---:|---:|---:|---:|']
    for year in (2024,2025,2026):
        a=[x for x in annual if x['year']==year]
        lines.append(f'| {year} | {sum(x["kind"]!="NO_VETO" for x in a)} | '+
            f'{sum(x["gain"]>1e-8 for x in a)} | {sum(x["gain"]< -1e-8 for x in a)} | '+
            f'{sum(abs(x["gain"])<=1e-8 for x in a)} |')
    lines+=['','## All Strategies','','| Strategy | Base N / ML N | Base R / ML R | Gain R | Month-skill R | Base DD / ML DD |',
            '|---|---:|---:|---:|---:|---:|']
    for r in sorted(records,key=lambda x:x['gain'],reverse=True):
        a,b=r['base'],r['ml']
        lines.append(f'| {r["id"]} | {a["trades"]} / {b["trades"]} | {a["net_r"]:+.2f} / {b["net_r"]:+.2f} | '+
            f'{r["gain"]:+.2f} | {r["skill"]:+.2f} | {a["dd_r"]:.2f} / {b["dd_r"]:.2f} |')
    lines+=['','## Matched Candidate Ablations','','Not post-test production choices; matching rows only.',
            '', '| Baseline | Candidate | Better R | Worse R | Same R | Better monthly skill |',
            '|---|---|---:|---:|---:|---:|']
    for a,b in [('local_base','local_flat_regime'),('local_flat_regime','local_hier_100'),('local_flat_regime','local_hier_400')]:
        p=[x for x in paired if x['a']==a and x['b']==b]
        lines.append(f'| {a} | {b} | {sum(x["gain"]>1e-8 for x in p)} | {sum(x["gain"]< -1e-8 for x in p)} | '+
                     f'{sum(abs(x["gain"])<=1e-8 for x in p)} | {sum(x["month_skill_gain"]>1e-8 for x in p)} |')
    lines+=['','## Verification And Limits','',
        f'- {len(checks)} frozen fitted bundles checked for positive finite scaling and purged label boundaries.',
        f'- {len(dup)} exact distinct outcome series; related series still dependent.',
        f'- Bonferroni-53 joint passes: {sum(r["pass53"] for r in records)}.',
        f'- Bonferroni-530 sensitivity joint passes: {sum(r["pass530"] for r in records)}.',
        '- 2026 is partial. Historical 2024-2026 was already inspected in prior research; this is NOT a fresh holdout.',
        '- 5/20-day circular block bootstrap is approximate in nonstationary markets. Corrections do not account for all human research.',
        '- No claim of zero overfit, DSR or PBO certification. The 530 correction is a sensitivity bound for R1/R2 model families only.',
        '- Candidate thresholds were frozen before test. Model-family winner cannot be reselected using these tables.',
        '- Validation retention floor does not guarantee test/live retention floor.',
        '- Closed-trade R and DD are not floating, currency/account or EOD-trailing-DD paths.',
        '- Frozen-row filtering does not resimulate stateful signal eligibility or broker fills; execution replay is required before deployment.',
        '- Shared formula choices are inspired by published methodology, not the same as reproducing authors\' financial experiments.',
        '- Model identities reject mixed strategies/configs/datasets. These research models are not runtime-compatible portable EA models.',
        '', '## Methodology Sources', '',
        '[Gelman (2006), partial pooling and sparse-group predictions](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf).',
        '[Gu, Kelly, Xiu (2020), regularization and temporal validation](https://dachxiu.chicagobooth.edu/download/ML.pdf).',
        '[Bailey et al. (2015), repeated backtest selection risk](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf).', '']
    r2.r1.atomic_write(root/'Results.md','\n'.join(lines).encode())
    print(f'R2 report complete: {len(records)} strategies; {len(checks)} fitted bundles',flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=r2.ROOT)
    p.add_argument('--draws',type=int,default=20000);a=p.parse_args()
    with threadpool_limits(limits=1):run(a.root,a.draws)
