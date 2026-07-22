#!/usr/bin/env python3
"""Causal two-sided sweep/reclaim routing for JP225 Sol Advanced."""
from __future__ import annotations
import argparse,json
from dataclasses import dataclass,asdict
from pathlib import Path
import numpy as np
import pandas as pd
from numba import njit
from research_sol_sequential_router import RISK_PRICE,fallback_continuation
from research_sol_adaptive_policy import simulate_detailed,summarize

@dataclass(frozen=True)
class Candidate:
    scale:str; probe:float; reclaim:float; wait_minutes:int; fallback:str
    @property
    def name(self): return f'{self.scale}_sweep{self.probe:g}_rec{self.reclaim:g}_w{self.wait_minutes}_{self.fallback}'

@njit(cache=True)
def route_core(times,highs,lows,closes,opens,available,refs,src,scale,fb,probe,reclaim,wait):
 n=len(available); dirs=np.empty(n,np.int64); idxs=np.empty(n,np.int64); entries=np.empty(n,np.float64); trig=np.empty(n,np.int8)
 for i in range(n):
  start=np.searchsorted(times,available[i],side='left'); end=np.searchsorted(times,available[i]+wait*60*1_000_000_000,side='left')
  if i+1<n: end=min(end,np.searchsorted(times,available[i+1],side='left'))
  end=max(start+1,min(end,len(times))); s=int(src[i]); dist=max(1e-9,probe*scale[i]); srclev=refs[i]+s*dist; opplev=refs[i]-s*dist
  srcreclaim=refs[i]+s*dist*(1.0-reclaim); oppreclaim=refs[i]-s*dist*(1.0-reclaim); srcarmed=False; opparmed=False; found=False
  direction=s; entryidx=end; code=0
  for j in range(start,end):
   sh=(highs[j]>=srclev) if s>0 else (lows[j]<=srclev); oh=(lows[j]<=opplev) if s>0 else (highs[j]>=opplev)
   if sh and oh: continue
   if sh: srcarmed=True
   if oh: opparmed=True
   srcok=srcarmed and ((closes[j]<=srcreclaim) if s>0 else (closes[j]>=srcreclaim))
   oppok=opparmed and ((closes[j]>=oppreclaim) if s>0 else (closes[j]<=oppreclaim))
   if srcok and oppok: continue
   if srcok or oppok:
    direction=-s if srcok else s; entryidx=j+1; code=1 if srcok else 2
    if entryidx<end: found=True
    break
  if not found:
   direction=-s if fb[i] else s; entryidx=end; code=0
  if entryidx>=len(times): entryidx=len(times)-1
  dirs[i]=direction; idxs[i]=entryidx; entries[i]=opens[entryidx]; trig[i]=code
 return dirs,idxs,entries,trig

def closed_h1_atr(frame,h1):
 h=h1.sort_values('time').copy(); prev=h.close.shift(1); tr=np.maximum(h.high-h.low,np.maximum((h.high-prev).abs(),(h.low-prev).abs())); a=tr.rolling(14,min_periods=14).mean().to_numpy(float); t=pd.to_datetime(h.time,utc=True).astype('int64').to_numpy(); q=frame.available.astype('int64').to_numpy(); ix=np.clip(np.searchsorted(t,q,side='left')-1,0,len(a)-1); z=a[ix]; return np.where(np.isfinite(z)&(z>0),z,np.nanmedian(a))

def decisions(frame,bars,atr,c):
 scale=np.repeat(RISK_PRICE,len(frame)) if c.scale=='risk' else atr; fb=fallback_continuation(frame,c.fallback)
 v=route_core(bars['time'],bars['high'],bars['low'],bars['close'],bars['open'],frame.available.astype('int64').to_numpy(),frame.entry_rev.to_numpy(float),frame.src_rev.to_numpy(np.int64),scale,fb,c.probe,c.reclaim,c.wait_minutes)
 return pd.DataFrame({'direction':v[0],'entry_index':v[1],'entry':v[2],'trigger':v[3]})

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('dataset',type=Path); ap.add_argument('m1',type=Path); ap.add_argument('h1',type=Path); ap.add_argument('--out',type=Path,default=Path('logs/sol_sweep_reclaim_router.json')); a=ap.parse_args()
 f=pd.read_csv(a.dataset,low_memory=False); f['available']=pd.to_datetime(f.available,utc=True); f['year']=f.available.dt.year
 m=pd.read_parquet(a.m1).sort_values('time'); bars={k:m[k].to_numpy(float) for k in ('open','high','low','close')}; bars['time']=pd.to_datetime(m.time,utc=True).astype('int64').to_numpy(); atr=closed_h1_atr(f,pd.read_parquet(a.h1))
 cand=[Candidate(sc,p,r,w,'v14') for sc in ('risk','atr') for p in (.10,.20,.33,.50,.75,1.0,1.5) for r in (.25,.50,.75,1.0) for w in (60,240,720)]
 rows=[]
 for c in cand:
  result=simulate_detailed(f,bars,decisions(f,bars,atr,c)); z=summarize(f,result,np.repeat(c.name,len(f))); z['candidate']=c.name; z['params']=asdict(c); z['dev_min_wr']=min(z['by_year'][str(y)]['wr'] or 0 for y in (2021,2022,2023)); z['holdout_min_wr']=min(z['by_year'][str(y)]['wr'] or 0 for y in (2024,2025,2026)); z['full_min_retention']=min(z['by_year'][str(y)]['retention'] for y in range(2021,2027)); rows.append(z)
 rank=sorted(rows,key=lambda z:(z['dev_min_wr'],z['wr']),reverse=True); a.out.write_text(json.dumps({'protocol':'causal M1 close sweep/reclaim; fixed 400 risk 2R target; v14 fallback; rank 2021-23, holdout 2024-26','count':len(rows),'top':rank[:60],'all':rows},indent=2)+'\n',encoding='utf-8')
 for z in rank[:25]: print(z['candidate'],f"all={z['wr']*100:.2f} dev={z['dev_min_wr']*100:.2f} hold={z['holdout_min_wr']*100:.2f} ret={z['full_min_retention']*100:.1f}",' '.join(f"{y}:{z['by_year'][str(y)]['wr']*100:.1f}" for y in range(2021,2027)))
if __name__=='__main__':main()
