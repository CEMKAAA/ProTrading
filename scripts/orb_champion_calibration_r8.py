"""Registered champion weights stay fixed; calibration uses only unseen past labels."""
from pathlib import Path
import json
import numpy as np
from threadpoolctl import threadpool_limits
import orb_jp225_r7 as jp
from orb_ml_filter import FEATURES,portable_predict
from export_orb_campaign_models import predict_return
from orb_training_age_r4_report import day_values
from orb_regime_campaign_report import block_diagnostic

r7=jp.r7;R=r7.R;ROOT=Path('logs/OrbChampionCalibration_R8_20260912')
START=R.stamp('2025-09-09');END=jp.END


def correction(kind,p,y,reg):
    if kind=='MLP':
        global_=r7.offset(p,(y>0).astype(float),10,40)
        q=r7.shift(p,global_)
        local=[r7.offset(q[reg==j],(y[reg==j]>0).astype(float),25,30) for j in range(6)]
    else:
        residual=y-p;n=len(y)
        global_=float(np.clip(residual.sum()/(n+50),-.25,.25)) if n>=40 else 0.
        local=[]
        for j in range(6):
            z=residual[reg==j]-global_;n=len(z)
            local.append(float(np.clip(z.sum()/(n+100),-.25,.25)) if n>=30 else 0.)
    return global_,local


def fit_state(f,p,kind,information_end,update):
    ix=(f.features_at_broker>information_end+R.GAP)&(f.features_at_broker>=update-r7.WINDOW)&(f.features_at_broker<update)&(f.entry_at_broker<update)&(f.exit_at_broker<update-R.GAP)
    cal=f.loc[ix];global_,local=correction(kind,p[ix],cal.net_r.to_numpy(),r7.r6.r5.regime_ids(cal))
    return dict(update=int(update),rows=len(cal),global_offset=global_,local_offsets=local,
                last_label=int(cal.exit_at_broker.max()) if len(cal) else None,
                first_feature=int(cal.features_at_broker.min()) if len(cal) else None)


def apply(kind,p,reg,s,arm):
    if arm=='raw':return p.copy()
    if kind=='MLP':
        q=r7.shift(p,s['global_offset'])
        if arm=='regime':q=r7.shift(q,np.array([s['local_offsets'][j] if j>=0 else 0 for j in reg]))
    else:
        q=p+s['global_offset']
        if arm=='regime':q=q+np.array([s['local_offsets'][j] if j>=0 else 0 for j in reg])
    return q


def run():
    uf,us=r7.r4.r3.prepare();jf,js=jp.prepare();frames={**uf,**jf}
    sources=us+[x for x in js if x['incumbent_available']]
    ROOT.mkdir(parents=True,exist_ok=True)
    paths=[Path(__file__),Path('docs/ORB_ChampionCalibration_R8_Protocol.md'),Path('tests/test_orb_champion_calibration_r8.py')]
    contract=dict(inputs=sources,code={str(p):R.digest(p) for p in paths},production=r7.r4.production_snapshot(),replacement_enabled=False)
    R.dump(ROOT/'contract.json',contract);results=[];daily=[];refs=[]
    for source in sources:
        ident=source['id'];f=frames[ident];kind=source['incumbent_kind'];data=Path(source['incumbent']).read_bytes();v=data.decode().splitlines()
        if R.digest(source['incumbent'])!=source['incumbent_sha']:raise ValueError('Champion changed')
        if kind=='MLP':p=portable_predict(data,f[FEATURES].to_numpy(float),source['incumbent_config']);threshold=float(v[6]);active=True
        else:p=predict_return(data,r7.r4.r3.returns.design(f).to_numpy(float));threshold=float(v[5]);active=v[6]=='1'
        information=source['incumbent_information_end'];ix=(f.features_at_broker>=START)&(f.features_at_broker>information+R.GAP)&(f.entry_at_broker<END)&(f.exit_at_broker<END-R.GAP)
        te=f.loc[ix].copy().reset_index(drop=True);tp=p[ix];reg=r7.r6.r5.regime_ids(te)
        old=tp>=threshold if active else np.ones(len(te),bool)
        np.testing.assert_array_equal(old,r7.r4.r3.incumbent(source,te))
        oldstats=R.stats(te,old);oldskill=r7.r4.r3report.contrasts(te,old)[:,1]
        pred=te[['features_at_broker','exit_at_broker','net_r']].copy();pred['legacy_score']=tp;pred['legacy_keep']=old.astype(int)
        states=[];scores={arm:np.full(len(te),np.nan) for arm in ('global','regime')}
        bounds=r7.schedule(START,END)
        for update,stop in zip(bounds,bounds[1:]):
            s=fit_state(f,p,kind,information,update);s['stop']=stop;states.append(s)
            ti=(te.features_at_broker>=update)&(te.features_at_broker<stop)
            for arm in scores:scores[arm][ti]=apply(kind,tp[ti],reg[ti],s,arm)
        for arm,value in scores.items():
            if not np.isfinite(value).all():raise ValueError('Missing scores')
            keep=value>=threshold if active else np.ones(len(te),bool);stats=R.stats(te,keep)
            pred[arm+'_score']=value;pred[arm+'_keep']=keep.astype(int)
            rec=dict(id=ident,name=source['name'],symbol=source['symbol'],kind=kind,arm=arm,active=active,
                current=oldstats,new=stats,delta_r=stats['net_r']-oldstats['net_r'],dd_delta=stats['dd_r']-oldstats['dd_r'],
                changed=int((keep!=old).sum()),nonzero_states=sum(s['global_offset']!=0 or (arm=='regime' and any(s['local_offsets'])) for s in states),
                initial_calibration_rows=states[0]['rows'],replacement_enabled=False)
            skill=r7.r4.r3report.contrasts(te,keep)[:,1]-oldskill;rec['skill_delta']=float(skill.sum());results.append(rec)
            for metric,d in [('net',te.net_r.to_numpy()*(keep.astype(float)-old.astype(float))),('skill',skill)]:
                daily.append(day_values(te,d,START,END));refs.append((rec,metric))
        folder=ROOT/ident;folder.mkdir(exist_ok=True);R.dump(folder/'states.json',states);R.atomic_write(folder/'predictions.csv',pred.to_csv(index=False).encode())
        print(ident,'complete',flush=True)
    for b in (5,20):
        z=block_diagnostic(np.column_stack(daily),b,20000)
        for i,(rec,metric) in enumerate(refs):
            rec.setdefault('bootstrap',{}).setdefault(str(b),{})[metric]=dict(low=float(z['low'][i]),high=float(z['high'][i]),p_adjusted=min(1.,196*float(z['p'][i])))
    R.dump(ROOT/'results.json',results)
    now=r7.r4.production_snapshot()
    if any(now.get(p)!=h for p,h in contract['production'].items()):raise ValueError('Runtime changed during research')
    R.dump(ROOT/'integrity.json',dict(sources_unchanged=all(R.digest(p)==h for p,h in contract['code'].items()),production_files_unchanged=len(now),deployed=False))
    print('COMPLETE',len(results),'paired comparisons')


if __name__=='__main__':
    with threadpool_limits(limits=1):run()
