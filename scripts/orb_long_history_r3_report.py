"""Matched incumbent comparison with explicit stability and uncertainty scores."""
from pathlib import Path
import argparse
import json
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_long_history_r3 as r3
from orb_regime_campaign_report import block_diagnostic


def contrasts(f,keep):
    months=pd.to_datetime(f.entry_at_broker,unit='s',utc=True).dt.strftime('%Y-%m')
    q=pd.Series(keep.astype(float),index=f.index).groupby(months).transform('mean').to_numpy()
    y=f.net_r.to_numpy(float)
    return np.column_stack([y*(keep.astype(float)-1.),y*(keep.astype(float)-q)])


def quarter_stability(f,k):
    times=pd.to_datetime(f.entry_at_broker,unit='s',utc=True)
    key=times.dt.year.astype(str)+'Q'+times.dt.quarter.astype(str)
    records=[]
    for value in sorted(key.unique()):
        ix=key.eq(value).to_numpy()
        u=r3.utility(f.loc[ix],k[ix])
        records.append(dict(quarter=value,n=int(ix.sum()),e=u['e'],gain=u['gain'],skill=u['skill']))
    return float(np.std([x['e'] for x in records])),records


def test_score(u,stability,lower_gain):
    n=u['base']['trades']
    uncertainty=max(0.,u['gain']-lower_gain)/n
    return dict(score=float(100*(u['e']+.25*u['d']-stability-uncertainty)),
                edge=u['e'],dd_gain=u['d'],stability_penalty=stability,uncertainty_penalty=uncertainty)


def run(root,draws):
    contract=json.loads((root/'contract.json').read_text())
    for path,sha in contract['code'].items():
        if r3.r1.digest(path)!=sha: raise ValueError('Changed frozen protocol/code')
    records=[];pairs=[];matrices=[];candidates=[];model_checks=[];inner_count=0
    first=r3.TEST//86400;last=r3.END//86400
    for source in contract['inputs']:
        ident=source['id'];folder=root/ident
        for p,sha in json.loads((folder/'complete.json').read_text()).items():
            if r3.r1.digest(folder/p)!=sha: raise ValueError('Changed trained artifact')
        for p,s in [('old_csv','old_sha'),('new_csv','new_sha'),('incumbent','incumbent_sha')]:
            if r3.r1.digest(source[p])!=source[s]: raise ValueError('Changed input/registered model')
        development=json.loads((folder/'development.json').read_text())
        for trial in development:
            for fold in trial['folds']:
                if fold['fit_label_max']>=fold['cal_start']-r3.r1.GAP or fold['score_end']>r3.CAL:
                    raise ValueError('Inner fold temporal leakage')
                inner_count+=1
        for kind in r3.KINDS:
            model=joblib.load(folder/(kind+'.research.joblib'))
            if model['identity']['strategy']!=ident or model['train_label_max']>=r3.CAL-r3.r1.GAP:
                raise ValueError('Wrong final identity or temporal leakage')
            if kind=='mlp' and model['early']['fit_label_max']>=model['early']['stop_start']-r3.r1.GAP:
                raise ValueError('MLP stopping leakage')
            model_checks.append(dict(id=ident,kind=kind,rows=model['rows'],train_label_max=model['train_label_max']))
        full=pd.read_csv(folder/'predictions.csv');result=json.loads((folder/'result.json').read_text())
        f=full.loc[full.fair_pair==1].copy()
        if f.empty: raise ValueError('No fair common test')
        new=f.keep.to_numpy(bool);old=f.incumbent_keep.to_numpy(bool)
        a=r3.utility(f,new);b=r3.utility(f,old)
        ns,nq=quarter_stability(f,new);os,oq=quarter_stability(f,old)
        c=np.column_stack([contrasts(f,new),contrasts(f,old),f.net_r.to_numpy()*(new.astype(float)-old.astype(float))])
        daily=np.zeros((last-first+1,5));ix=(f.exit_at_broker.to_numpy()//86400-first).astype(int)
        for col in range(5):np.add.at(daily[:,col],ix,c[:,col])
        np.testing.assert_allclose(daily.sum(axis=0),[a['gain'],a['skill'],b['gain'],b['skill'],a['ml']['net_r']-b['ml']['net_r']],atol=1e-8)
        matrices.append(daily);pairs.append(f)
        records.append(dict(id=ident,name=source['name'],selected=result['selected'],pretest=result['pretest_robustness'],
            incumbent_kind=source['incumbent_kind'],incumbent_information_end=source['incumbent_information_end'],
            fair_start=result['fair_pair_start'],full_test_rows=len(full),paired_rows=len(f),full_year=result['full_year'],
            new=a,incumbent=b,new_quarter_stability=ns,incumbent_quarter_stability=os,
            new_quarters=nq,incumbent_quarters=oq,delta_vs_incumbent=a['ml']['net_r']-b['ml']['net_r'],
            incumbent_optimism_comparable=False,replacement_enabled=False))
        for kind in r3.KINDS:
            k=full['keep_'+kind].to_numpy(bool)
            candidates.append(dict(id=ident,kind=kind,**r3.utility(full,k),
                                   selected=result['selected']==kind))
    matrix=np.column_stack(matrices)
    for length in (5,20):
        print(f'R3 paired blocks {length}, draws={draws}',flush=True)
        bs=block_diagnostic(matrix,length,draws)
        for j,rec in enumerate(records):
            details={}
            for k,key in enumerate(('new_gain','new_month_skill','old_gain','old_month_skill','new_minus_old')):
                i=j*5+k;p=float(bs['p'][i])
                details[key]=dict(low=float(bs['low'][i]),high=float(bs['high'][i]),p=p,
                                  p22=min(1.,22*p),p88=min(1.,88*p))
            rec.setdefault('blocks',{})[str(length)]=details
    for r in records:
        for tag,label in [('new','new_gain'),('incumbent','old_gain')]:
            lower=min(r['blocks'][str(b)][label]['low'] for b in (5,20))
            r[tag+'_test_score']=test_score(r[tag],r[tag+'_quarter_stability'],lower)
        r['economic_screen']=bool(r['selected']!='NO_VETO' and r['delta_vs_incumbent']>0
            and r['new']['ml']['dd_r']<=r['incumbent']['ml']['dd_r']
            and r['new_test_score']['score']>r['incumbent_test_score']['score']
            and r['new']['gain']>0 and r['new']['skill']>0)
        r['corrected_evidence']=bool(all(r['blocks'][str(b)][m]['p88']<.05
            for b in (5,20) for m in ('new_gain','new_month_skill','new_minus_old')))
        r['promotion_approved']=False
        r['promotion_reason']='Research only; reused holdout, incumbent optimism not comparable, new forward/replay absent'
    payload=dict(policy=contract['policy'],records=records,candidates=candidates,draws=draws,
        model_checks=model_checks,inner_fits_checked=inner_count,final_models_checked=len(model_checks),
        replacement_enabled=False,holdout_previously_inspected=True,
        score_is_overfit_probability=False,unknown_incumbent_optimism_not_imputed=True)
    r3.r1.dump(root/'evaluation.json',payload)
    rows=[]
    for r in records:
        rows.append(dict(id=r['id'],name=r['name'],selected=r['selected'],paired_rows=r['paired_rows'],
            base_r=r['new']['base']['net_r'],old_r=r['incumbent']['ml']['net_r'],new_r=r['new']['ml']['net_r'],
            delta_r=r['delta_vs_incumbent'],old_dd=r['incumbent']['ml']['dd_r'],new_dd=r['new']['ml']['dd_r'],
            old_test_score=r['incumbent_test_score']['score'],new_test_score=r['new_test_score']['score'],
            economic_screen=r['economic_screen'],corrected_evidence=r['corrected_evidence'],promotion=False))
    r3.r1.atomic_write(root/'comparison.csv',pd.DataFrame(rows).to_csv(index=False).encode())
    lines=['# USDJPY Long-History R3','','No production replacement. All models and thresholds remain unchanged in the EA.',
        '', '## Dates And Scope','',
        '22 strategies; verified USDJPY prior/recent datasets joined without fabricating the six-day September 2021 export gap.',
        'Final model fit: 2018-01-01 to 2024-09-09. Calibration: next year. Test: 2025-09-09 to 2026-09-09.',
        'Date boundaries use broker time. 24h label purge. MLP additionally reserves chronological fit-tail for early stopping.',
        'This is a historical holdout from this training run, NOT previously unseen data across all research.',
        '', '## Matched Registered Incumbent Comparison','',
        'Six incumbents had calibration extending past test start. Paired rows begin after both information horizons plus purge.',
        'Test score is a descriptive economic/stability/uncertainty utility, not an overfit probability.',
        'NO_VETO means no new model qualified; any improvement versus incumbent then means disabling its veto, not discovering a new model.',
        '', '| Strategy | New selection | Base R | Registered R | New policy R | Delta | Old DD / new DD | Old score / new score |',
        '|---|---|---:|---:|---:|---:|---:|---:|']
    for r in sorted(records,key=lambda x:x['delta_vs_incumbent'],reverse=True):
        lines.append(f'| {r["id"]} | {r["selected"]} | {r["new"]["base"]["net_r"]:+.2f} | '+
            f'{r["incumbent"]["ml"]["net_r"]:+.2f} | {r["new"]["ml"]["net_r"]:+.2f} | '+
            f'{r["delta_vs_incumbent"]:+.2f} | {r["incumbent"]["ml"]["dd_r"]:.2f} / {r["new"]["ml"]["dd_r"]:.2f} | '+
            f'{r["incumbent_test_score"]["score"]:.2f} / {r["new_test_score"]["score"]:.2f} |')
    lines+=['','## Results','',
        f'- Actual new model selected: {sum(r["selected"]!="NO_VETO" for r in records)}/22.',
        f'- Matched PnL versus incumbent: {sum(r["delta_vs_incumbent"]>1e-8 for r in records)} better, '+
        f'{sum(r["delta_vs_incumbent"]< -1e-8 for r in records)} worse, '+
        f'{sum(abs(r["delta_vs_incumbent"])<=1e-8 for r in records)} unchanged (includes NO_VETO).',
        f'- Economic/DD/score screens: {sum(r["economic_screen"] for r in records)}.',
        f'- Corrected paired-evidence screens: {sum(r["corrected_evidence"] for r in records)}.',
        '- Promotion approved: 0. The script has no deployment path.',
        '', '## Score Definitions','',
        'Pre-test score = 100*[mean validation edge + .25*mean DD gain - edge std - training optimism].',
        'Edge = min(improvement over base, month-count-matched selection skill), divided by candidate trades.',
        'Optimism = max(0, training edge - chronological validation edge), averaged over three inner folds.',
        'Test score = 100*[edge + .25*DD gain/N - quarterly edge std - uncertainty penalty].',
        'Uncertainty penalty = (actual gain - worst 5/20-day bootstrap lower gain)/N, floored at zero.',
        'Incumbent historical optimism cannot fairly be recomputed on data it already trained on; it is unknown, not zero.',
        'Same test-score formula for old/new. Higher score does not certify lower true overfit or authorize switching.',
        '', '## Limits','',
        '- Four fixed candidate families, all chronological splits and settings recorded before test.',
        '- Regime features were already in the original models. This measures longer-history training and fixed-model selection, not regime presence alone.',
        '- Same strategy rows only; joined identity is research-specific and retains both original export hashes.',
        '- Confidence calculations are approximate under nonstationarity. Multiplicity corrections omit earlier human/model research.',
        '- Closed-trade R is not account returns, floating risk or EOD trailing DD. Do not sum correlated strategy R as a fund.',
        '- Frozen-row veto evaluation does not rerun strategy state/position eligibility. Future promotion needs execution replay.',
        '- New model family/threshold is not reselected after seeing these tables. All current models preserved.',
        '', '## Sources','',
        '[Gu, Kelly, Xiu: temporal validation and regularization](https://dachxiu.chicagobooth.edu/download/ML.pdf).',
        '[Gelman: partial pooling](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf).',
        '[Bailey et al.: repeated backtest selection risk](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf).', '']
    r3.r1.atomic_write(root/'Results.md','\n'.join(lines).encode())
    print('R3 report complete; production replacements=0',flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=r3.ROOT)
    p.add_argument('--draws',type=int,default=20000);a=p.parse_args()
    with threadpool_limits(limits=1):run(a.root,a.draws)
