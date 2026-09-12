"""Retrospective attribution only; never supplies training or filter decisions."""
import json
import numpy as np
import pandas as pd
import orb_calibration_r7 as r7


def decompose(a,b,ar,br):
    """Test-minus-past mean = composition effect + within-bucket change.

    Unseen past buckets use the past global mean, explicitly marked as imputed.
    This accounting identity is descriptive, not causal identification.
    """
    prior=float(np.mean(a));mix=within=0.;missing=[];rows=[]
    for j in range(-1,6):
        ai=ar==j;bi=br==j;wa=float(ai.mean());wb=float(bi.mean())
        ma=float(np.mean(a[ai])) if ai.any() else prior
        mb=float(np.mean(b[bi])) if bi.any() else ma
        if bi.any() and not ai.any():missing.append(j)
        mix+=(wb-wa)*ma;within+=wb*(mb-ma)
        rows.append(dict(regime=j,past_n=int(ai.sum()),test_n=int(bi.sum()),past_mean=ma,test_mean=mb))
    delta=float(np.mean(b)-np.mean(a))
    np.testing.assert_allclose(mix+within,delta,atol=1e-12,rtol=1e-12)
    return dict(delta=delta,composition=mix,within=within,imputed_regimes=missing,rows=rows)


def supported(a,b,ar,br):
    full=decompose(a,b,ar,br)
    common=np.intersect1d(ar,br);ia=np.isin(ar,common);ib=np.isin(br,common)
    full['common_support']=decompose(a[ia],b[ib],ar[ia],br[ib]) if ia.any() and ib.any() else None
    full['common_past_fraction']=float(ia.mean());full['common_test_fraction']=float(ib.mean())
    return full


def run():
    root=r7.ROOT;c=r7.verify_contract(root);frames,_=r7.r4.r3.prepare()
    d=json.loads((root/'evaluation.json').read_text());records=d['records'];attribution=[];changes=[];summaries=[]
    for source in c['inputs']:
        ident=source['id'];f=frames[ident]
        for year in r7.r6.YEARS:
            cutoff,start,end=r7.r4.dates(year);a=f.loc[r7.eligible(f,start,cutoff)]
            b=r7.R.partition(f,start,end);ar=r7.r6.r5.regime_ids(a);br=r7.r6.r5.regime_ids(b)
            attribution.append(dict(id=ident,year=year,
                net_r=supported(a.net_r.to_numpy(),b.net_r.to_numpy(),ar,br),
                win_rate=supported((a.net_r.to_numpy()>0).astype(float),(b.net_r.to_numpy()>0).astype(float),ar,br)))
        for kind in r7.KINDS:
            frames_saved=[pd.read_csv(root/ident/str(y)/'predictions.csv') for y in r7.r6.YEARS]
            f_saved=pd.concat(frames_saved,ignore_index=True);y=f_saved.net_r.to_numpy()
            old=f_saved['keep_'+kind+'__raw'].to_numpy(bool)
            for arm in r7.ARMS[1:]:
                new=f_saved['keep_'+kind+'__'+arm].to_numpy(bool);added=new&~old;removed=old&~new
                delta=float(y[added].sum()-y[removed].sum())
                rec=next(x for x in records if x['id']==ident and x['kind']==kind and x['arm']==arm)
                np.testing.assert_allclose(delta,rec['delta_raw'],atol=1e-10,rtol=1e-10)
                changes.append(dict(id=ident,kind=kind,arm=arm,added=int(added.sum()),removed=int(removed.sum()),
                    added_r=float(y[added].sum()),removed_r=float(y[removed].sum()),delta=delta))
    representatives={g[0] for g in d['duplicate_groups']}
    for kind in r7.KINDS:
        for arm in r7.ARMS:
            sub=[x for x in records if x['kind']==kind and x['arm']==arm]
            old=[next(y for y in records if y['id']==x['id'] and y['kind']==kind and y['arm']=='raw') for x in sub]
            summaries.append(dict(kind=kind,arm=arm,brier_better=sum(x['brier']<y['brier'] for x,y in zip(sub,old)),
                median_bias=float(np.median([x['probability_bias'] for x in sub])),
                median_retention=float(np.median([x['test']['ml']['retention'] for x in sub]))))
    drift=[]
    for year in r7.r6.YEARS:
        sub=[x for x in attribution if x['year']==year and x['id'] in representatives]
        drift.append(dict(year=year,series=len(sub),
            within_larger_net_r=sum(abs(x['net_r']['within'])>abs(x['net_r']['composition']) for x in sub),
            within_larger_win_rate=sum(abs(x['win_rate']['within'])>abs(x['win_rate']['composition']) for x in sub),
            common_within_larger_net_r=sum(abs(x['net_r']['common_support']['within'])>abs(x['net_r']['common_support']['composition'])
                for x in sub if x['net_r']['common_support']),
            median_common_test_fraction=float(np.median([x['net_r']['common_test_fraction'] for x in sub])),
            with_imputed_regime=sum(bool(x['net_r']['imputed_regimes']) for x in sub)))
    r7.R.dump(root/'diagnostics.json',dict(descriptive_only=True,summaries=summaries,drift_summary=drift,
        attribution=attribution,changed_trades=changes,replacement_enabled=False))
    print(json.dumps(dict(summaries=summaries,drift_summary=drift),indent=2));r7.verify_contract(root)


if __name__=='__main__':
    run()
