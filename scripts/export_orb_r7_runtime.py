"""Opt-in R7 logistic/probability archive; no Common Files writes or activation."""
from pathlib import Path
import json
import hashlib
import joblib
import numpy as np
from scipy.special import expit, logit
from threadpoolctl import threadpool_limits
import orb_jp225_r7 as jp
from export_orb_campaign_models import numeric_hash, quote
from orb_ml_filter import load_dataset, FEATURES

r7=jp.r7; R=r7.R
OUT=Path('logs/OrbR7Runtime_20260912')
KIND='logistic_mean'


def portable(m):
    if m['kind']!=KIND: raise ValueError('Wrong R7 family')
    c=m['classifier']
    if c is None:
        mean=np.zeros(50);scale=np.ones(50);coef=np.zeros(50);bias=0.;constant=m['prevalence']
    else:
        a,b=c.steps[0][1],c.steps[1][1]
        mean=a.mean_;scale=a.scale_;coef=b.coef_[0];bias=float(b.intercept_[0]);constant=-1.
    return dict(label=m['last_label'],gain=m['gain_mean'],loss=m['loss_mean'],constant=constant,
                bias=bias,mean=mean.tolist(),scale=scale.tolist(),coef=coef.tolist())


def score_model(m,x,offset):
    z=np.full(len(x),m['bias'])
    for i in range(50):z+=(x[:,i]-m['mean'][i])/m['scale'][i]*m['coef'][i]
    p=np.full(len(x),m['constant']) if m['constant']>=0 else expit(z)
    if offset!=0:p=expit(logit(np.clip(p,1e-9,1-1e-9))+offset)
    return p*m['gain']-(1-p)*m['loss']


def encode(info,models,states):
    lines=['ORB_R7_LOGISTIC1',R.digest_text(','.join(FEATURES)) if hasattr(R,'digest_text') else hashlib.sha256(','.join(FEATURES).encode()).hexdigest(),
           info['id'],info['config'],info['dataset'],str(len(models)),str(len(states))]
    for m in models:
        lines += [format(float(m[k]),'.17g') for k in ('label','gain','loss','constant','bias')]
        for i in range(50):lines += [format(m[k][i],'.17g') for k in ('mean','scale','coef')]
    for s in states:lines += [format(float(s[k]),'.17g') for k in ('model','update','stop','label','offset')]
    payload='\n'.join(lines)+'\n'
    return (payload+hashlib.sha256(payload.encode()).hexdigest()+'\n').encode()


def binding(row):
    csv=Path(row['csv']);f,info=load_dataset(csv);ident=row['preset_id']
    settings=(csv.parent.parent/'Settings'/(ident+'.txt')).read_text().splitlines()
    if len(settings)!=50 or settings[1]!=row['symbol']:raise ValueError('Settings mismatch')
    custom=''
    if ident.startswith('user_'):
        for p in (csv.parent.parent/'UserStrategies').glob('*.preset'):
            v=p.read_text(encoding='utf8').splitlines()
            if v[6]==ident:custom=numeric_hash(v[11:64]);break
        if not custom:raise ValueError('Missing custom binding')
    return dict(id=ident,config=info['config_hash'],dataset=info['dataset_sha256'],kind='R7_LOGISTIC_P',
        runtime_hash=numeric_hash(settings[4:44]),custom_hash=custom,symbol=row['symbol'],
        broker=str(f.iloc[0].broker),inputs=settings[3],tf=int(settings[2]),csv=row['export']['path'])


def run():
    # Validate the original snapshot BEFORE the explicitly authorized EA edits.
    jp.verify_contract();r7.verify_contract(r7.ROOT)
    OUT.mkdir(parents=True,exist_ok=True)
    R.dump(OUT/'pre_edit_integrity.json',dict(production=r7.r4.production_snapshot(),verified=True))
    uf,us=r7.r4.r3.prepare();jf,js=jp.prepare();frames={**uf,**jf}
    campaign=json.loads((r7.r4.r3.CAMPAIGN/'campaign.json').read_text())
    registry=[];vectors=[];errors=[];source_hashes={}
    for row in campaign:
        ident=row['preset_id']
        if ident not in frames:continue
        f=frames[ident];info=binding(row);models=[];states=[];maxerr=0.;nchecked=0
        isjp=row['symbol']=='JP225m';root=jp.ROOT if isjp else r7.ROOT
        years=jp.YEARS if isjp else r7.r6.YEARS
        for year in years:
            folder=root/ident/str(year)
            if not (folder/'complete.json').exists():continue
            if not r7.r4.checkpoint_valid(folder):raise ValueError('Changed checkpoint')
            source_hashes[str(folder/'complete.json')]=R.digest(folder/'complete.json')
            path=(folder if isjp else r7.r6.ROOT/ident/str(year))/(KIND+'.research.joblib')
            m=joblib.load(path);pm=portable(m);index=len(models);models.append(pm)
            for s in json.loads((folder/'states.json').read_text()):
                if s['kind']!=KIND:continue
                states.append(dict(model=index,update=s['update'],stop=s['stop'],label=s['last_label'] or 0,offset=s['global_offset']))
                sample=f.loc[(f.features_at_broker>=s['update'])&(f.features_at_broker<s['stop'])]
                if sample.empty:continue
                x=r7.r4.r3.returns.design(sample).to_numpy(float)
                expected,_=r7.apply_state(sample,r7.r6.predict(m,sample)['probability'],m,s,'probability')
                actual=score_model(pm,x,s['global_offset']);err=float(np.max(np.abs(expected-actual)))
                if err>1e-10 or not np.array_equal(expected>=0,actual>=0):raise ValueError('Decision parity')
                maxerr=max(maxerr,err);nchecked+=len(sample)
                for ii in sorted({0,len(sample)-1}):
                    vectors.append(';'.join([ident,str(int(sample.iloc[ii].features_at_broker)),format(actual[ii],'.17g')]+[format(v,'.17g') for v in sample.iloc[ii][FEATURES].to_numpy(float)]))
        forward=OUT/'forward'/ident;forward.mkdir(parents=True,exist_ok=True)
        if isjp:
            m=joblib.load(jp.ROOT/ident/'forward_20260909'/(KIND+'.research.joblib'))
            s=json.loads((jp.ROOT/ident/'forward_20260909/states.json').read_text())[KIND]
        else:
            cutoff=R.stamp('2025-09-09');tr=R.partition(f,r7.r4.START,cutoff)
            m=r7.r6.fit_family(tr,cutoff)[KIND]
            hist=f.loc[(f.features_at_broker>=cutoff)&(f.features_at_broker<jp.END)]
            s=r7.fit_state(hist,r7.r6.predict(m,hist)['probability'],m,jp.END)
        joblib.dump(m,forward/'logistic_mean.research.joblib');R.dump(forward/'state.json',s)
        models.append(portable(m));states.append(dict(model=len(models)-1,update=jp.END,stop=R.stamp('2026-10-01'),label=s['last_label'] or 0,offset=s['global_offset']))
        # Forward parity uses only numerical vectors, NOT a forward performance claim.
        sample=f.tail(8).copy();sample['features_at_broker']=jp.END
        expected,_=r7.apply_state(sample,r7.r6.predict(m,sample)['probability'],m,s,'probability')
        actual=score_model(models[-1],r7.r4.r3.returns.design(sample).to_numpy(float),s['global_offset'])
        np.testing.assert_allclose(expected,actual,atol=1e-10,rtol=0)
        np.testing.assert_array_equal(expected>=0,actual>=0)
        for ii in range(len(sample)):
            vectors.append(';'.join([ident,str(jp.END),format(actual[ii],'.17g')]+[format(v,'.17g') for v in sample.iloc[ii][FEATURES].to_numpy(float)]))
        if any(a['stop']>b['update'] for a,b in zip(states,states[1:])):raise ValueError('Overlapping states')
        data=encode(info,models,states);info['model_sha']=hashlib.sha256(data).hexdigest()
        folder=OUT/'Files/OrbML/R7';folder.mkdir(parents=True,exist_ok=True);R.atomic_write(folder/(ident+'.r7'),data)
        registry.append(info);errors.append(dict(id=ident,historical_rows=nchecked,max_error=maxerr,models=len(models),states=len(states)))
        print(ident,nchecked,'parity OK',flush=True)
    text='// Generated fixed R7 logistic/probability profile. No best-test selection.\n'
    text+='bool OrbR7Record(string id,OrbCampaignInfo &r)\n{\n'
    for rec in registry:
        text+='   if(id=='+quote(rec['id'])+'){'+''.join('r.'+k+'='+quote(v)+';' for k,v in rec.items() if k!='tf')+'r.tf='+str(rec['tf'])+';return true;}\n'
    text+='   return false;\n}\n'
    R.atomic_write(OUT/'OrbStrategyR7Registry.mqh',text.encode())
    R.atomic_write(OUT/'probe_vectors.txt',('\n'.join(vectors)+'\n').encode())
    R.dump(OUT/'verification.json',dict(records=registry,parity=errors,source_checkpoints=source_hashes,
        deployed=False,profile='logistic_mean/probability',forward_performance_tested=False))
    print('COMPLETE',len(registry),'strategies',len(vectors),'probe vectors')


if __name__=='__main__':
    with threadpool_limits(limits=1):run()
