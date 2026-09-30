"""Independent batch equations from the supplied Pine defaults vs MQL streaming output.

Not a TradingView feed-parity test. Run after AuditTradeCsvProbe.mq5.
No external packages, network, trading, or model fitting.
"""
import csv
import math
from pathlib import Path

N = 700
nan = float('nan')
def valid(x): return math.isfinite(x)
def nz(x): return x if valid(x) else 0.
def lag(x, k=1): return [nan]*k+x[:-k]
def sma(x, n):
    out, window = [], []
    for v in x:
        if valid(v): window.append(v)
        window = window[-n:]
        out.append(sum(window)/n if len(window)==n else nan)
    return out
def wma(x, n):
    out, window = [], []
    for v in x:
        if valid(v): window.append(v)
        window = window[-n:]
        out.append(sum((j+1)*v for j,v in enumerate(window))/(n*(n+1)/2) if len(window)==n else nan)
    return out
def ema(x, n):
    out, p = [], nan
    for v in x:
        if valid(v): p=v if not valid(p) else 2/(n+1)*v+(1-2/(n+1))*p
        out.append(p)
    return out
def rma(x, n):
    seed=sma(x,n); out=[];p=nan
    for i,v in enumerate(x):
        if not valid(p): p=seed[i]
        elif valid(v): p=(v+(n-1)*p)/n
        out.append(p)
    return out
def var(x, n):
    # Pine comparisons with na are false; math.sum needs 9 bars.
    ups=[0]+[max(0,a-b) if valid(a) and valid(b) else 0 for a,b in zip(x[1:],x)]
    dns=[0]+[max(0,b-a) if valid(a) and valid(b) else 0 for a,b in zip(x[1:],x)]
    out=[];p=0
    for i,v in enumerate(x):
        u=sum(ups[max(0,i-8):i+1]); d=sum(dns[max(0,i-8):i+1])
        a=2/(n+1)*abs((u-d)/(u+d)) if i>=8 and u+d else 0
        p=(a*v if valid(v) else 0)+(1-a)*p;out.append(p)
    return out
def trail(x, widths, percent=None):
    out=[];pl=ps=nan;direction=1
    for v,w in zip(x,widths):
        if not valid(v) or not valid(w): out.append(nan);pl=ps=nan;continue
        lo=v-w;hi=v+w;lp=pl if valid(pl) else lo;sp=ps if valid(ps) else hi
        pl=max(lo,lp) if v>lp else lo; ps=min(hi,sp) if v<sp else hi
        direction=1 if direction==-1 and v>sp else -1 if direction==1 and v<lp else direction
        t=pl if direction==1 else ps
        out.append(t if percent is None else t*(200+(percent if v>t else -percent))/200)
    return out
def ott(x,p): return trail(x,[v*p/100 for v in x],p)
def t3(x,n,a):
    stages=[]
    for _ in range(6): x=ema(x,n);stages.append(x)
    return [-a**3*f+(3*a*a+3*a**3)*e+(-6*a*a-3*a-3*a**3)*d+(1+3*a+a**3+3*a*a)*c for c,d,e,f in zip(*stages[2:])]
def extrema(x,n,fn): return [fn(x[max(0,i-n+1):i+1]) for i in range(len(x))]
def stdev(x,n):
    return [math.sqrt(sum((v-sum(x[i-n+1:i+1])/n)**2 for v in x[i-n+1:i+1])/n) if i>=n-1 else nan for i in range(len(x))]

c=[100+.012*k+4*math.sin(k*.13)+1.7*math.cos(k*.031) for k in range(N)]
o=[c[k]+.2*math.sin(k*.73) for k in range(N)]
h=[max(o[k],c[k])+.4+.1*(k%7) for k in range(N)]
l=[min(o[k],c[k])-.35-.08*(k%5) for k in range(N)]
tr=[h[0]-l[0]]+[max(h[k]-l[k],abs(h[k]-c[k-1]),abs(l[k]-c[k-1])) for k in range(1,N)]
gain=[nan]+[max(0,c[k]-c[k-1]) for k in range(1,N)]
loss=[nan]+[max(0,c[k-1]-c[k]) for k in range(1,N)]
gu=rma(gain,14);gd=rma(loss,14)
rsi=[100*u/(u+d) if valid(u) and valid(d) and u+d else nan for u,d in zip(gu,gd)]
expected={}
v12=var(c,12);v26=var(c,26);macd=[a-b for a,b in zip(v12,v26)]
expected.update(AK_VAR12=v12,AK_VAR26=v26,AK_MACD=macd,AK_MACDTRIGGER=var(macd,9))
v3=var(c,3);expected['AK_MOST']=trail(v3,[.02*v for v in v3])
expected['AK_HOTT']=ott(var(extrema(h,10,max),2),.6)
expected['AK_LOTT']=ott(var(extrema(l,10,min),2),.6)
otto=[a/(b-d+100000) for a,b,d in zip(var(c,12.5),var(c,25),var(c,250))]
expected['AK_OTTO_SRC']=otto;expected['AK_OTTO']=ott(var(otto,2),.6)
hh=extrema(h,250,max);ll=extrema(l,250,min)
sk=var([100*(v-low)/(high-low) for v,high,low in zip(c,hh,ll)],50)
expected['AK_STOCHK']=sk;expected['AK_STOCHOTT']=ott(var([v+1000 for v in sk],3),.618)
m=c
for n in [3,5,8,13,21,34]: m=wma(m,n)
expected['AK_MAV6']=m
src=[(hi+lo+2*cl)/4 for hi,lo,cl in zip(h,l,c)]
expected['AK_T3']=t3(src,8,.7);expected['AK_T3FIB']=t3(src,5,.618)
lr=[];old=[0.]*4
for v in c:
    new=[.2*v+.8*old[0]]
    for j in range(1,4):new.append(-.8*new[j-1]+old[j-1]+.8*old[j])
    up=sum(max(0,a-b) for a,b in zip(new,new[1:]));dn=sum(max(0,b-a) for a,b in zip(new,new[1:]))
    lr.append(100*up/(up+dn) if up+dn else 0);old=new
expected['AK_LARSI']=lr
qf=ema(rsi,5);qs=[];ww=atr=nan;previous=0
for i,v in enumerate(qf):
    delta=abs(v-qf[i-1]) if i and valid(v) and valid(qf[i-1]) else nan
    ww=delta/14+13/14*nz(ww) if valid(delta) else nan
    atr=ww/14+13/14*nz(atr) if valid(ww) else nan
    up=v+4.236*atr;down=v-4.236*atr;pv=qf[i-1] if i else nan
    previous=up if up<previous else down if v>previous and pv<previous else down if down>previous else up if v<previous and pv>previous else previous
    qs.append(previous)
expected['AK_QFAST']=qf;expected['AK_QSLOW']=qs
sl=[];ss=[];pl=ps=0
for i,v in enumerate(c):
    p=c[i-1] if i else nan
    pl=v*.97 if v*.97>pl or p<pl else pl;ps=v*1.03 if v*1.03<ps or p>ps else ps
    sl.append(pl);ss.append(ps)
expected['AK_STOPLONG']=sl;expected['AK_STOPSHORT']=ss
a10=rma(tr,10);su=sd=nan;direction=1;st=[]
for i,(hi,lo,v,at) in enumerate(zip(h,l,c,a10)):
    if not valid(at):st.append(nan);continue
    u=(hi+lo)/2-3*at;d=(hi+lo)/2+3*at;pu=su if valid(su) else u;pd=sd if valid(sd) else d;p=c[i-1] if i else nan
    su=max(u,pu) if p>pu else u;sd=min(d,pd) if p<pd else d
    direction=1 if direction==-1 and v>pd else -1 if direction==1 and v<pu else direction
    st.append(su if direction==1 else sd)
expected['AK_SUPER']=st
rawtr=[nan]+tr[1:]
at14=sma(rawtr,14);alpha=[];pa=0
for hi,lo,r,at in zip(h,l,rsi,at14):
    v=max(lo-at,pa) if r>=50 else min(hi+at,pa)
    # min/max with na in Pine must propagate rather than Python's ordering quirks.
    if not valid(at):v=nan
    alpha.append(v);pa=nz(v)
expected['AK_ALPHA_RSI']=alpha
mean=sma(c,20);cci=[];magic=[];pm=0;a5=sma(rawtr,5)
for i,(v,m,at) in enumerate(zip(c,mean,a5)):
    mad=sum(abs(z-m) for z in c[i-19:i+1])/20 if i>=19 else nan
    cc=(v-m)/(.015*mad) if valid(mad) and mad else nan;cci.append(cc)
    z=max(l[i]-at,pm) if cc>=0 else min(h[i]+at,pm)
    if not valid(at):z=nan
    magic.append(z);pm=nz(z)
expected['AK_CCI']=cci;expected['AK_MAGIC']=magic
base=var(c,2);dev=stdev(c,2)
expected['AK_BOOT1']=ott(var([a+2*b for a,b in zip(base,dev)],2),10)
expected['AK_BOOT2']=ott(var([a-2*b for a,b in zip(base,dev)],2),10)
bb=sma(c,21);bs=stdev(c,21);fa=rma(tr,5);fl=[];state=0;pfl=nan
for i,v in enumerate(c):
    if v>bb[i]+bs[i]:state=1
    elif v<bb[i]-bs[i]:state=-1
    if state==1:pfl=max(l[i]-fa[i],nz(pfl))
    elif state==-1:pfl=min(h[i]+fa[i],nz(pfl))
    fl.append(pfl)
expected['AK_FOLLOW']=fl

# TwinRange: preserve each equality branch and previous-band comparisons.
delta=[nan]+[abs(c[i]-c[i-1]) for i in range(1,N)]
fast=ema(ema(delta,27),53);slow=ema(ema(delta,55),109)
width=[(1.6*a+2*b)/2 for a,b in zip(fast,slow)]
filt=ub=lb=trf=nan;tw=[]
for i,(v,w) in enumerate(zip(c,width)):
    pf=nz(filt);pu=nz(ub);pl=nz(lb);pt=nz(trf);rawub=ub;rawlb=lb;p=c[i-1] if i else nan
    filt=(max(pf,v-w) if v>pf else min(pf,v+w)) if valid(w) else nan
    if valid(w):
        u=filt+w;d=filt-w;ub=u if u<pu or p>pu else pu;lb=d if d>pl or p<pl else pl
    else: ub=lb=nan
    trf=ub if pt==rawub and v<=ub else lb if pt==rawub and v>=ub else lb if pt==rawlb and v>=lb else ub if pt==rawlb and v<=lb else ub
    tw.append(trf)
expected['AK_TRF']=tw

# PMax's custom RSI, including the source's zero-seeded WWMA and high/low RSI.
up0=[0]+gain[1:];dn0=[0]+loss[1:];au=sma(up0,14);ad=sma(dn0,14)
pr=[];rh=[];rl=[];pu=pd=0
for i,v in enumerate(c):
    pu=up0[i]/14+13/14*pu;pd=dn0[i]/14+13/14*pd
    pr.append(100*pu/(pu+pd) if pd>0 else nan)
    p=c[i-1] if i else nan
    u=au[i]*13+max(0,h[i]-p);d=ad[i]*13+max(0,p-h[i]);rh.append(100*u/(u+d) if valid(d) and d>0 else nan)
    u=au[i]*13+max(0,l[i]-p);d=ad[i]*13+max(0,p-l[i]);rl.append(100*u/(u+d) if valid(d) and d>0 else nan)
ptr=[nan]+[max(rh[i]-rl[i],abs(rh[i]-pr[i-1]),abs(rl[i]-pr[i-1])) if all(valid(v) for v in (rh[i],rl[i],pr[i-1])) else nan for i in range(1,N)]
expected['AK_PMAX']=trail(t3(pr,8,.7),[3*v for v in sma(ptr,10)])

# RSX's six paired recursive filters, not an RSI approximation.
rsx=[];pos=[0.]*6;neg=[0.]*6;p88=p90=0;tp=[(a+b+d)/3 for a,b,d in zip(h,l,c)]
for i,v in enumerate(tp):
    x=100*(v-(tp[i-1] if i else 0));y=abs(x);a=3/16;b=1-a
    for j in range(0,6,2):
        pos[j]=b*pos[j]+a*x;pos[j+1]=a*pos[j]+b*pos[j+1];x=1.5*pos[j]-.5*pos[j+1]
        neg[j]=b*neg[j]+a*y;neg[j+1]=a*neg[j]+b*neg[j+1];y=1.5*neg[j]-.5*neg[j+1]
    n90=1 if p90==0 else p88+1 if p88<=p90 else p90+1;n88=13 if p90==0 else 5
    f0=1 if n88>=n90 and v!=(tp[i-1] if i else 0) else 0
    final=0 if n88==n90 and f0==0 else n90
    rsx.append(max(0,min(100,(x/y+1)*50 if n88<final and y>0 else 50)));p88,p90=n88,n90
expected['AK_RSX']=rsx

# Pivot confirmation at i (not i-2), with more-recent equal highs/lows winning.
center=up=down=nan;direction=1;ppst=[]
for i,v in enumerate(c):
    ph=i>=4 and all(h[i-2]>h[j] if j>i-2 else h[i-2]>=h[j] for j in range(i-4,i+1) if j!=i-2)
    pl=i>=4 and all(l[i-2]<l[j] if j>i-2 else l[i-2]<=l[j] for j in range(i-4,i+1) if j!=i-2)
    pp=h[i-2] if ph else l[i-2] if pl else nan
    if valid(pp):center=(2*center+pp)/3 if valid(center) else pp
    if not valid(center) or not valid(a10[i]):ppst.append(nan);continue
    rawup=center-3*a10[i];rawdown=center+3*a10[i];p=c[i-1] if i else nan
    newup=max(rawup,up) if p>up else rawup;newdown=min(rawdown,down) if p<down else rawdown
    direction=1 if v>down else -1 if v<up else direction
    up,down=newup,newdown;ppst.append(up if direction==1 else down)
expected['AK_PIVOTST']=ppst

def main():
    root=Path(__file__).resolve().parents[1]
    source=(root/'IndicatorCodeExamples/macrossover_orb/AuditKivancFeatures.mqh').read_text()
    enum=source.split('enum AkSlot')[1].split('{',1)[1].split('}',1)[0]
    slots=[v.strip() for v in enum.replace('\n','').split(',') if v.strip()]
    path=root/'.tmp/orb_jp225_full_worker/MQL5/Files/KivancFeatureProbe.csv'
    rows=list(csv.DictReader(path.open()))
    assert len(rows)==N
    failures=[];checks=0
    for name,values in expected.items():
        key=str(slots.index(name))
        for i,(row,want) in enumerate(zip(rows,values)):
            got=float(row[key]) if row[key] else nan;checks+=1
            if valid(want)!=valid(got) or (valid(want) and not math.isclose(got,want,rel_tol=1e-9,abs_tol=1e-9)):
                failures.append((name,i,got,want))
    print(f'{len(expected)} source calculations, {checks} numeric comparisons, {len(failures)} failures')
    for failure in failures[:20]: print(failure)
    assert not failures
if __name__=='__main__': main()
