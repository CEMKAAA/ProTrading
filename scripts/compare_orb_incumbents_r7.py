"""Comprehensive matched incumbent comparison; post-test analysis, no selection API."""
import json
from pathlib import Path
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_calibration_r7 as r7
import orb_jp225_r7 as jp
from orb_training_age_r4_report import day_values
from orb_regime_campaign_report import block_diagnostic,fingerprint

OUT=Path('logs/OrbIncumbentComparison_20260912')
START=r7.R.stamp('2025-09-09');END=r7.R.stamp('2026-09-09')


def extra(f,k):
    y=f.loc[k,'net_r'].to_numpy();s=r7.R.stats(f,k)
    gains=float(y[y>0].sum());losses=float(-y[y<0].sum())
    dates=pd.date_range('2025-09-09',periods=5,freq=pd.DateOffset(months=3),tz='UTC')
    quarters=[]
    for a,b in zip(dates,dates[1:]):
        ix=k&(f.exit_at_broker.to_numpy()>=a.timestamp())&(f.exit_at_broker.to_numpy()<b.timestamp())
        quarters.append(float(f.loc[ix,'net_r'].sum()))
    np.testing.assert_allclose(sum(quarters),s['net_r'],atol=1e-9,rtol=1e-9)
    return dict(**s,average_r=float(y.mean()) if len(y) else None,
        profit_factor=gains/losses if losses>0 else None,profit_factor_infinite=losses==0 and gains>0,
        gross_gain_r=gains,gross_loss_r=losses,quarters=quarters,
        extra_cost={str(c):float(y.sum()-c*len(y)) for c in (.01,.025,.05)})


def decision_delta(f,old,new):
    y=f.net_r.to_numpy();added=new&~old;removed=old&~new
    actual=float(y[new].sum()-y[old].sum());delta=float(y[added].sum()-y[removed].sum())
    np.testing.assert_allclose(delta,actual,atol=1e-10,rtol=1e-10)
    return dict(both=int((new&old).sum()),added=int(added.sum()),removed=int(removed.sum()),
        neither=int((~new&~old).sum()),added_r=float(y[added].sum()),removed_r=float(y[removed].sum()),delta_r=delta)


def classification(delta,dd):
    eps=1e-8
    if delta>=-eps and dd<=eps and (delta>eps or dd< -eps):return 'NEW_PNL_DD_FRONTIER'
    if delta<=eps and dd>=-eps and (delta< -eps or dd>eps):return 'CURRENT_PNL_DD_FRONTIER'
    if abs(delta)<=eps and abs(dd)<=eps:return 'SAME'
    return 'TRADEOFF'


def run():
    OUT.mkdir(parents=True,exist_ok=True);uc=r7.verify_contract(r7.ROOT);jc=jp.verify_contract()
    uf,_=r7.r4.r3.prepare();jf,_=jp.prepare()
    groups={};pairs=[];baselines=[];excluded=[];matrices=[];refs=[];snapshots={}
    for symbol,root,c,frames,years,family in [('USDJPYm',r7.ROOT,uc,uf,r7.r6.YEARS,176),
                                             ('JP225m',jp.ROOT,jc,jf,jp.YEARS,240)]:
        for source in c['inputs']:
            ident=source['id'];raw=r7.R.partition(frames[ident],START,END).reset_index(drop=True)
            available=source.get('incumbent_available',True)
            if not available:
                excluded.append(dict(id=ident,name=source['name'],symbol=symbol,reason='NO_REGISTERED_INCUMBENT'))
                continue
            fair=max(START,source['incumbent_information_end']+r7.R.GAP+1)
            take=raw.features_at_broker>=fair;f=raw.loc[take].reset_index(drop=True)
            old=r7.r4.r3.incumbent(source,f);base=extra(f,old)
            baselines.append(dict(id=ident,name=source['name'],symbol=symbol,kind=source['incumbent_kind'],
                model=source['incumbent'],model_sha=source['incumbent_sha'],fair_start=fair,rows=len(f),
                excluded_for_information_time=int((~take).sum()),current=base,no_filter=extra(f,np.ones(len(f),bool))))
            folder=root/ident/'2025'
            if not r7.r4.checkpoint_valid(folder):
                excluded.append(dict(id=ident,name=source['name'],symbol=symbol,reason='NO_ELIGIBLE_R7_TEST'))
                continue
            snapshots[str(folder/'complete.json')]=r7.R.digest(folder/'complete.json')
            p=pd.read_csv(folder/'predictions.csv');p=p.loc[p.fair_pair==1].reset_index(drop=True)
            for col in ('features_at_broker','entry_at_broker','exit_at_broker','net_r'):
                np.testing.assert_allclose(f[col],p[col],atol=1e-12,rtol=1e-12)
            np.testing.assert_array_equal(old,p.incumbent_keep.to_numpy(bool))
            groups.setdefault(symbol+':'+fingerprint(f),[]).append(ident)
            allrows=[]
            for year in years:
                past=root/ident/str(year)
                if r7.r4.checkpoint_valid(past):allrows.extend(json.loads((past/'result.json').read_text()))
            oldskill=r7.r4.r3report.contrasts(f,old)[:,1]
            for kind in r7.KINDS:
                for arm in r7.ARMS[1:]:
                    new=p['keep_'+kind+'__'+arm].to_numpy(bool);s=extra(f,new);changes=decision_delta(f,old,new)
                    qdelta=np.array(s['quarters'])-np.array(base['quarters'])
                    dd=s['dd_r']-base['dd_r'];hist=[x for x in allrows if x['kind']==kind and x['arm']==arm]
                    rawhist=[x for x in allrows if x['kind']==kind and x['arm']=='raw']
                    rawdelta=[x['test']['ml']['net_r']-o['test']['ml']['net_r'] for x,o in zip(hist,rawhist)]
                    rec=dict(id=ident,name=source['name'],symbol=symbol,kind=kind,arm=arm,
                        current=base,new=s,delta_r=changes['delta_r'],dd_delta=dd,
                        wr_delta=None if s['wr'] is None or base['wr'] is None else s['wr']-base['wr'],
                        quarter_delta=qdelta.tolist(),positive_quarters=int((qdelta>1e-8).sum()),
                        decision_changes=changes,classification=classification(changes['delta_r'],dd),
                        historical_years=[x['year'] for x in hist],historical_net=[x['test']['ml']['net_r'] for x in hist],
                        historical_base_delta=[x['test']['gain'] for x in hist],historical_raw_delta=rawdelta,
                        extra_cost_delta={key:s['extra_cost'][key]-base['extra_cost'][key] for key in s['extra_cost']},
                        promotion_approved=False)
                    pairs.append(rec)
                    contrasts=[f.net_r.to_numpy()*(new.astype(float)-old.astype(float)),
                               r7.r4.r3report.contrasts(f,new)[:,1]-oldskill]
                    rec['count_matched_skill_delta']=float(contrasts[1].sum())
                    for metric,v in zip(('net','skill'),contrasts):
                        matrices.append(day_values(f,v,START,END));refs.append((rec,metric,family))
            print(symbol,ident,'matched',flush=True)
    for block in (5,20):
        z=block_diagnostic(np.column_stack(matrices),block,20000)
        for i,(rec,metric,family) in enumerate(refs):
            p=float(z['p'][i]);rec.setdefault('bootstrap',{}).setdefault(str(block),{})[metric]=dict(
                low=float(z['low'][i]),high=float(z['high'][i]),p=p,p_family=min(1.,family*p),p_joint832=min(1.,832*p))
    summary=[]
    for symbol in ('USDJPYm','JP225m'):
        for kind in r7.KINDS:
            for arm in r7.ARMS[1:]:
                sub=[x for x in pairs if x['symbol']==symbol and x['kind']==kind and x['arm']==arm]
                summary.append(dict(symbol=symbol,kind=kind,arm=arm,pairs=len(sub),
                    pnl_better=sum(x['delta_r']>1e-8 for x in sub),pnl_worse=sum(x['delta_r']< -1e-8 for x in sub),
                    pnl_same=sum(abs(x['delta_r'])<=1e-8 for x in sub),
                    new_frontier=sum(x['classification']=='NEW_PNL_DD_FRONTIER' for x in sub),
                    current_frontier=sum(x['classification']=='CURRENT_PNL_DD_FRONTIER' for x in sub),
                    median_delta_r=float(np.median([x['delta_r'] for x in sub])),
                    median_dd_delta=float(np.median([x['dd_delta'] for x in sub])),
                    corrected_net=sum(all(x['bootstrap'][str(b)]['net']['p_family']<.05 for b in (5,20)) for x in sub),
                    corrected_skill=sum(all(x['bootstrap'][str(b)]['skill']['p_family']<.05 for b in (5,20)) for x in sub)))
    result=dict(summary=summary,pairs=pairs,baselines=baselines,excluded=excluded,
        duplicate_groups=list(groups.values()),matched_start=START,matched_end=END,
        post_test_descriptive_only=True,live_chart_status_checked=False,replacement_enabled=False)
    r7.R.dump(OUT/'comparison.json',result)
    flat=[]
    for x in pairs:
        row={k:x[k] for k in ('id','name','symbol','kind','arm','delta_r','dd_delta','count_matched_skill_delta','positive_quarters','classification')}
        for side in ('current','new'):
            row.update({side+'_'+k:x[side][k] for k in ('trades','wr','net_r','dd_r','average_r','profit_factor')})
        row['ci20_net_low']=x['bootstrap']['20']['net']['low'];row['ci20_net_high']=x['bootstrap']['20']['net']['high']
        flat.append(row)
    r7.R.atomic_write(OUT/'all_comparisons.csv',pd.DataFrame(flat).to_csv(index=False).encode())
    write_report(result)
    r7.verify_contract(r7.ROOT);jp.verify_contract()
    r7.R.dump(OUT/'integrity.json',dict(production_files_unchanged=len(uc['production']),
        usd_contract=r7.R.digest(r7.ROOT/'contract.json'),jp_contract=r7.R.digest(jp.ROOT/'contract.json'),
        source_checkpoints=snapshots,script_sha=r7.R.digest(Path(__file__)),pairs=len(pairs),replacement_enabled=False))


def write_report(d):
    lines=['# Registered Models Versus Latest R7 Candidates','','Research comparison, not deployment selection.',
        'Common final-year rows only: 2025-09-09 to 2026-09-09, additionally purged after incumbent information end.',
        'Current means the verified registered experimental artifact, not a live chart status claim.',
        'R7 has eight fixed challengers per strategy. Newest JP225 forward refits have no subsequent test.',
        'Prior years cannot be a fair out-of-sample test of an incumbent that trained on them.','',
        '## Family Comparisons','',
        '| Symbol | Family / arm | PnL better/worse/same | New PnL-DD frontier | Current frontier | Median delta R | Median DD delta |',
        '|---|---|---:|---:|---:|---:|---:|']
    for x in d['summary']:
        lines.append(f"| {x['symbol']} | {x['kind']} / {x['arm']} | {x['pnl_better']}/{x['pnl_worse']}/{x['pnl_same']} | {x['new_frontier']} | {x['current_frontier']} | {x['median_delta_r']:+.2f} | {x['median_dd_delta']:+.2f} |")
    lines+=['','Frontier uses only PnL and DD; it is descriptive, not statistical proof or a deployment recommendation.',
        'Negative DD delta is improvement. Correlated results are not summed as portfolio profit.','',
        '## All Strategy Comparisons','',
        'Each strategy lists all eight challengers. No hidden best-test-family selector.',
        'Quarter count: number of the four non-overlapping Sep9-anchored quarters with positive incremental R.',
        'CI: unadjusted 95% paired 20-calendar-day bootstrap interval for incremental R.','']
    for base in d['baselines']:
        ident=base['id'];b=base['current']
        lines+=[f"### {base['symbol']} / {base['name']}",'',
            f"Registered {base['kind']}: {b['net_r']:+.2f}R, DD {b['dd_r']:.2f}R, trades {b['trades']}, WR {100*b['wr']:.2f}%." if b['wr'] is not None else 'Registered model opens no trades on common rows.',
            f"Common source rows {base['rows']}; information-time exclusions {base['excluded_for_information_time']}.",'',
            '| Candidate | Net R | DD R | Trades | WR % | Delta R | Positive quarters | Delta CI |',
            '|---|---:|---:|---:|---:|---:|---:|---:|']
        for x in [x for x in d['pairs'] if x['id']==ident and x['symbol']==base['symbol']]:
            s=x['new'];ci=x['bootstrap']['20']['net'];wr='NA' if s['wr'] is None else f"{100*s['wr']:.2f}"
            lines.append(f"| {x['kind']} / {x['arm']} | {s['net_r']:+.2f} | {s['dd_r']:.2f} | {s['trades']} | {wr} | {x['delta_r']:+.2f} | {x['positive_quarters']}/4 | [{ci['low']:+.2f}, {ci['high']:+.2f}] |")
        lines.append('')
    lines+=['## Coverage And Limits','']
    for x in d['excluded']:lines.append(f"- {x['symbol']} / {x['name']}: {x['reason']}.")
    lines+=['- Cost sensitivity subtracts hypothetical EXTRA 0.01/0.025/0.05R per kept trade from already-net labels; not a broker fee estimate.',
        '- Decision additions/removals and count-matched selection differences are in comparison.json.',
        '- Prior annual candidate results are in comparison.json; they do not evaluate the newest forward refit.',
        '- New paired skill test is a post-test diagnostic. Family corrections 176 USDJPY/240 JP225; joint832 sensitivity.',
        '- Previously researched history, approximate bootstrap stationarity, correlated strategy samples.',
        '- Closed-trade DD is not floating/EOD/account drawdown. No stateful execution or new prospective shadow here.',
        '- No production artifact replaced or activated.']
    r7.R.atomic_write(OUT/'FullComparison.md','\n'.join(lines).encode())


if __name__=='__main__':
    with threadpool_limits(limits=1):run()
