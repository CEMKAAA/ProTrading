#!/usr/bin/env python3
"""Causal ATR-normalized OCO routing research for JP225 Sol Advanced."""
from __future__ import annotations
import argparse, json
from dataclasses import dataclass, asdict
from pathlib import Path
import numpy as np
import pandas as pd
from numba import njit
from research_sol_sequential_router import RISK_PRICE, fallback_continuation
from research_sol_adaptive_policy import simulate_detailed, summarize

@dataclass(frozen=True)
class Candidate:
    source_atr: float
    opposite_atr: float
    wait_minutes: int
    momentum: bool
    fallback: str
    @property
    def name(self):
        mode='mom' if self.momentum else 'rej'
        return f'atr_{mode}_s{self.source_atr:g}_o{self.opposite_atr:g}_w{self.wait_minutes}_{self.fallback}'

@njit(cache=True)
def resolve_core(times, highs, lows, opens, available, refs, source, atr, fallback_cont,
                 source_atr, opposite_atr, wait_minutes, momentum):
    n=len(available); directions=np.empty(n,np.int64); indices=np.empty(n,np.int64); entries=np.empty(n,np.float64)
    triggers=np.empty(n,np.int8)
    for i in range(n):
        start=np.searchsorted(times,available[i],side='left')
        cutoff=available[i]+wait_minutes*60*1_000_000_000
        end=np.searchsorted(times,cutoff,side='left')
        if i+1<n:
            nxt=np.searchsorted(times,available[i+1],side='left'); end=min(end,nxt)
        end=max(start+1,min(end,len(times)))
        src=int(source[i]); src_level=refs[i]+src*source_atr*atr[i]; opp_level=refs[i]-src*opposite_atr*atr[i]
        src_hit=-1; opp_hit=-1
        for j in range(start,end):
            if src_hit<0 and ((src>0 and highs[j]>=src_level) or (src<0 and lows[j]<=src_level)): src_hit=j-start
            if opp_hit<0 and ((src>0 and lows[j]<=opp_level) or (src<0 and highs[j]>=opp_level)): opp_hit=j-start
            if src_hit>=0 and opp_hit>=0: break
        ambiguous=src_hit>=0 and opp_hit>=0 and src_hit==opp_hit
        if (src_hit<0 and opp_hit<0) or ambiguous:
            direction=-src if fallback_cont[i] else src; idx=end
            if idx>=len(times): idx=len(times)-1
            entry=opens[idx]; trigger=0 if not ambiguous else 3
        else:
            source_first=opp_hit<0 or (src_hit>=0 and src_hit<opp_hit)
            if momentum: direction=src if source_first else -src
            else: direction=-src if source_first else src
            rel=src_hit if source_first else opp_hit; idx=start+rel
            level=src_level if source_first else opp_level; op=opens[idx]
            if direction>0: entry=max(op,level) if source_first==momentum else op
            else: entry=min(op,level) if source_first==momentum else op
            trigger=1 if source_first else 2
        directions[i]=direction; indices[i]=idx; entries[i]=entry; triggers[i]=trigger
    return directions,indices,entries,triggers

def causal_atr(frame,h1):
    h=h1.sort_values('time').copy(); prev=h.close.shift(1)
    tr=np.maximum(h.high-h.low,np.maximum((h.high-prev).abs(),(h.low-prev).abs()))
    vals=tr.rolling(14,min_periods=14).mean().to_numpy(float)
    times=pd.to_datetime(h.time,utc=True).astype('int64').to_numpy(); setup=frame.available.astype('int64').to_numpy()
    idx=np.searchsorted(times,setup,side='left')-1; idx=np.clip(idx,0,len(vals)-1); out=vals[idx]
    med=np.nanmedian(vals); out=np.where(np.isfinite(out)&(out>0),out,med)
    return out

def decisions(frame,bars,atr,c):
    fb=fallback_continuation(frame,c.fallback)
    v=resolve_core(bars['time'],bars['high'],bars['low'],bars['open'],frame.available.astype('int64').to_numpy(),
        frame.entry_rev.to_numpy(float),frame.src_rev.to_numpy(np.int64),atr,fb,
        c.source_atr,c.opposite_atr,c.wait_minutes,c.momentum)
    return pd.DataFrame({'direction':v[0],'entry_index':v[1],'entry':v[2],'trigger':v[3]})

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('dataset',type=Path); ap.add_argument('m1',type=Path); ap.add_argument('h1',type=Path); ap.add_argument('--out',type=Path,default=Path('logs/sol_atr_oco_router.json')); a=ap.parse_args()
    f=pd.read_csv(a.dataset,low_memory=False); f['available']=pd.to_datetime(f.available,utc=True); f['year']=f.available.dt.year
    m=pd.read_parquet(a.m1).sort_values('time'); bars={k:m[k].to_numpy(float) for k in ('open','high','low','close')}; bars['time']=pd.to_datetime(m.time,utc=True).astype('int64').to_numpy()
    atr=causal_atr(f,pd.read_parquet(a.h1)); probes=(.10,.20,.33,.50,.75,1.0,1.5)
    candidates=[Candidate(s,o,w,mom,fb) for s in probes for o in probes for w in (60,240,720) for mom in (False,True) for fb in ('reversal','v14')]
    rows=[]
    for c in candidates:
        dec=decisions(f,bars,atr,c); result=simulate_detailed(f,bars,dec); z=summarize(f,result,np.repeat(c.name,len(f)))
        z['candidate']=c.name; z['params']=asdict(c); z['dev_min_wr']=min(z['by_year'][str(y)]['wr'] or 0 for y in (2021,2022,2023)); z['holdout_min_wr']=min(z['by_year'][str(y)]['wr'] or 0 for y in (2024,2025,2026)); z['full_min_retention']=min(z['by_year'][str(y)]['retention'] for y in (2021,2022,2023,2024,2025,2026)); rows.append(z)
    ranked=sorted(rows,key=lambda z:(z['dev_min_wr'],z['wr']),reverse=True)
    a.out.write_text(json.dumps({'protocol':'causal closed H1 ATR14; fixed 400 risk and 2R target; development ranking 2021-2023; untouched holdout 2024-2026','count':len(rows),'top':ranked[:50],'all':rows},indent=2)+'\n',encoding='utf-8')
    for z in ranked[:20]: print(z['candidate'],f"all={z['wr']*100:.2f} devmin={z['dev_min_wr']*100:.2f} holdmin={z['holdout_min_wr']*100:.2f}",' '.join(f"{y}:{z['by_year'][str(y)]['wr']*100:.1f}" for y in range(2021,2027)))
if __name__=='__main__': main()
