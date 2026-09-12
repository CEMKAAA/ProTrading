"""Five-year retrospective comparison. Includes training data; NOT an OOS test."""
from pathlib import Path
import json
import joblib
import numpy as np
import pandas as pd
from orb_ml_filter import load_dataset, portable_predict, FEATURES
from export_orb_campaign_models import predict_return
from build_orb_leaderboard import quote, score
import export_orb_r7_runtime as e


def build():
    root=e.OUT
    campaign=json.loads((e.r7.r4.r3.CAMPAIGN/'campaign.json').read_text())
    registered={r['id']:r for r in json.loads((e.r7.r4.r3.COMMON/'OrbML/CampaignModels/adapter_verification.json').read_text())}
    r7reg={r['id']:r for r in json.loads((root/'verification.json').read_text())['records']}
    records=[]
    for item in campaign:
        ident=item['preset_id'];f,info=load_dataset(Path(item['csv']))
        if info['dataset_sha256']!=item['csv_sha256']:raise ValueError('Changed CSV')
        # Preserve common closed/feature-valid rows across all three alternatives.
        raw=pd.read_csv(item['csv']);bad=raw.loc[(raw.label_valid==1)&(raw.features_valid!=1)]
        if len(bad):raise ValueError('Cannot silently omit closed trades with missing features')
        f['strategy']=ident
        base=e.r7.R.stats(f,np.ones(len(f),bool));old=None;new=None;oldhash='';newhash=''
        r=registered.get(ident)
        if r:
            b=(e.r7.r4.r3.COMMON/'OrbML/CampaignModels'/(ident+'.experimental')).read_bytes()
            oldhash=e.hashlib.sha256(b).hexdigest()
            if oldhash!=r['model_sha']:raise ValueError('Legacy model changed')
            v=b.decode().splitlines()
            if r['kind']=='MLP':prediction=portable_predict(b,f[FEATURES].to_numpy(float),info['config_hash']);keep=prediction>=float(v[6])
            else:
                prediction=predict_return(b,e.r7.r4.r3.returns.design(f).to_numpy(float));keep=(prediction>=float(v[5])) if v[6]=='1' else np.ones(len(f),bool)
            old=e.r7.R.stats(f,keep)
        if ident in r7reg:
            folder=root/'forward'/ident;m=joblib.load(folder/'logistic_mean.research.joblib');s=json.loads((folder/'state.json').read_text())
            # Deliberately retrospective inference from the latest fixed snapshot.
            # Do NOT spoof feature timestamps or call this historical OOS inference.
            prediction=e.score_model(e.portable(m),e.r7.r4.r3.returns.design(f).to_numpy(float),s['global_offset'])
            new=e.r7.R.stats(f,prediction>=0);newhash=r7reg[ident]['model_sha']
        for stat in (base,old,new):
            if stat is not None:stat['score']=score(stat['wins'],stat['trades'],stat['dd_r'])
        records.append(dict(id=ident,name=item['name'],symbol=item['symbol'],family=r['kind'] if r else 'NONE',
            config=info['config_hash'],dataset=info['dataset_sha256'],legacy_sha=oldhash,r7_sha=newhash,
            from_time=int(info['window_from_broker']),to_time=int(info['asof_broker']),
            base=base,legacy=old,r7=new,excluded_open_or_invalid_labels=int(info['excluded_rows']),
            evaluation='RETROSPECTIVE_TRAINING_INCLUDED_NOT_OOS',execution_replay=False))
    lines=['// Five-year CLOSED trade snapshot; ML rows include training data, NOT OOS.',
           'int OrbLbFiveCount(){return '+str(len(records))+';}',
           'bool OrbLbFive(int index,OrbLbRow &r)','{','   switch(index)','   {']
    for i,r in enumerate(records):
        line=f'      case {i}: '+''.join('r.'+k+'='+quote(r[k])+';' for k in ('id','name','symbol','family','config','dataset'))
        line+='r.hasMl='+str(r['legacy'] is not None).lower()+';r.hasR7='+str(r['r7'] is not None).lower()+';'
        line+=f'r.fromTime=(datetime){r["from_time"]};r.toTime=(datetime){r["to_time"]};'
        for pre,key in [('base','base'),('ml','legacy'),('r7','r7')]:
            s=r[key] or dict(wr=0,net_r=0,dd_r=0,score=0,trades=0)
            for field,value in [('Wr',100*(s['wr'] or 0)),('R',s['net_r']),('Dd',s['dd_r']),('Score',s['score'])]:line+=f'r.{pre}{field}={value:.12f};'
            line+=f'r.{pre}N={s["trades"]};'
        lines.append(line+'return true;')
    lines+=['   }','   return false;','}']
    e.R.atomic_write(root/'OrbStrategyLeaderboardFiveYear.mqh',('\n'.join(lines)+'\n').encode())
    e.R.dump(root/'leaderboard_5y_retrospective.json',records)
    print('5Y RETROSPECTIVE',len(records),'Vanilla',sum(r['legacy'] is not None for r in records),'Legacy',sum(r['r7'] is not None for r in records),'R7; NOT OOS')


if __name__=='__main__':build()
