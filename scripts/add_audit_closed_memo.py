"""Add audit-only completed-replay memoization without rewriting replay math."""
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
INC=ROOT/'IndicatorCodeExamples'
BASE=ROOT/'logs/AuditWindowReuse_20260914/baseline'

def read(name):
    p=INC/name;raw=p.read_bytes()
    BASE.mkdir(parents=True,exist_ok=True)
    if not (BASE/name).exists():(BASE/name).write_bytes(raw)
    return raw,raw.decode('utf-8-sig').replace('\r\n','\n')

def write(name,raw,text):
    nl='\r\n' if b'\r\n' in raw else '\n'
    (INC/name).write_bytes((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+text.replace('\n',nl).encode())

def nas():
    name='NasStrategyResearch.mqh';raw,s=read(name)
    if 'g_nasReplayMemo' in s:return
    at=s.index('\nbool NasLibraryStrictAudit()')
    s=s[:at]+'''
#include "AuditMemoIndex.mqh"
struct NasReplayMemoValue
{
   datetime at;double px,gross,mfe,mae;string reason,quality;
};
AuditMemoIndex g_nasReplayMemo;
NasReplayMemoValue g_nasReplayValues[];
long g_nasReplayMemoHits=0,g_nasReplayMemoMisses=0;

'''+s[at:]
    a=s.index('bool NasResearchOutcome(');b=s.index('\nbool NasLibraryReplayAudit',a)
    s=s[:a]+'''bool NasResearchOutcome(const NasResearchTrade &t,datetime &exitAt,double &exitPx,double &gross,string &reason,string &quality,double &mfe,double &mae)
{
   string epoch=AuditMemoDataEpoch(_Symbol);
   g_nasReplayMemo.Reset(epoch);
   string key=(string)t.entryAt+"|"+(string)t.deadline+"|"+(string)t.direction+"|"+(string)t.closeDirection
      +"|"+AuditMemoPrice(t.entry)+"|"+AuditMemoPrice(t.sl)+"|"+AuditMemoPrice(t.tp)
      +"|"+(string)t.entryValid+"|"+AuditMemoPrice(_Point);
   int cached=g_nasReplayMemo.Find(key);
   if(cached>=0&&g_nasReplayValues[cached].at<=g_nasResearchAsOf)
   {
      NasReplayMemoValue v=g_nasReplayValues[cached];
      exitAt=v.at;exitPx=v.px;gross=v.gross;reason=v.reason;quality=v.quality;mfe=v.mfe;mae=v.mae;
      g_nasReplayMemoHits++;return true;
   }
   g_nasReplayMemoMisses++;
   datetime end=g_nasResearchAsOf;
   if(t.deadline>0&&t.deadline<end)end=t.deadline;
   MqlRates m1[];ArraySetAsSeries(m1,false);
   CopyRates(_Symbol,PERIOD_M1,t.entryAt,MathMin(g_nasResearchAsOf-1,end+300),m1);
   bool valid=NasResearchReplay(t,m1,g_nasResearchAsOf,_Point,exitAt,exitPx,gross,reason,quality,mfe,mae);
   // An asynchronous history download during CopyRates must not seal stale data.
   if(valid&&reason!="OPEN"&&reason!="DATA"&&exitAt>0&&exitAt<=g_nasResearchAsOf&&epoch==AuditMemoDataEpoch(_Symbol))
   {
      int slot=g_nasReplayMemo.Add(key);
      if(slot>=0)
      {
         if(ArraySize(g_nasReplayValues)<=slot)ArrayResize(g_nasReplayValues,slot+1,512);
         g_nasReplayValues[slot].at=exitAt;g_nasReplayValues[slot].px=exitPx;g_nasReplayValues[slot].gross=gross;
         g_nasReplayValues[slot].reason=reason;g_nasReplayValues[slot].quality=quality;
         g_nasReplayValues[slot].mfe=mfe;g_nasReplayValues[slot].mae=mae;
      }
   }
   return valid;
}
'''+s[b:]
    write(name,raw,s)

def orb(name):
    raw,s=read(name)
    if 'OrbMemoLifecycle' in s:return
    # Inputs cannot mutate without OnInit. Runtime fill/exit geometry is captured
    # exactly; filtering and forced-exit discovery still run on each selected window.
    variables=re.findall(r'^(\w+)\s+(g_rt\w+)\s*=',s,re.M)
    variables=[(typ,n) for typ,n in variables if n!='g_rtHistoricalWeeks']
    variables += [(typ,n) for typ,n in re.findall(r'^(\w+)\s+(g_bt\w+)\s*=',s,re.M)
                  if n in ('g_btFillMode','g_btSameBarPolicy','g_btNativeParity','g_btSpreadPts','g_btSlippagePts','g_btCommissionPerLot')]
    fields=''
    for typ,n in variables:
        value=f'AuditMemoPrice({n})' if typ=='double' else f'(string){n}'
        fields+=f'   key+="|{n}="+{value};\n'
    wrapper='''
#include "AuditMemoIndex.mqh"
#include "OrbReplayMemoEpoch.mqh"
AuditMemoIndex g_orbReplayMemo;
HistResult g_orbReplayValues[];
datetime g_orbReplayEnds[];
long g_orbReplayMemoHits=0,g_orbReplayMemoMisses=0;

HistResult OrbMemoLifecycle(datetime entryTime,datetime sessionEnd,datetime now,double entry,double sl,bool isBuy,
   double tp1,double tp2,double tp3,int halfBeLeg,datetime &usedEnd,datetime forcedExitTime=0,string forcedExitOutcome="")
{
   string epoch=OrbReplayDataEpoch();
   g_orbReplayMemo.Reset(epoch);
   string key=(string)entryTime+"|"+(string)sessionEnd+"|"+AuditMemoPrice(entry)+"|"+AuditMemoPrice(sl)
      +"|"+(string)isBuy+"|"+AuditMemoPrice(tp1)+"|"+AuditMemoPrice(tp2)+"|"+AuditMemoPrice(tp3)
      +"|"+(string)halfBeLeg+"|"+(string)forcedExitTime+"|"+forcedExitOutcome
      +"|"+AuditMemoPrice(g_orbHigh)+"|"+AuditMemoPrice(g_orbLow)
      +"|"+(string)g_orbStartServer+"|"+(string)g_orbEndServer+"|"+(string)g_tradeEndServer
      +"|"+AuditMemoPrice(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE))
      +"|"+AuditMemoPrice(g_btCommissionPerLot!=0?SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE):0);
FIELDS
   int cached=g_orbReplayMemo.Find(key);
   if(cached>=0&&g_orbReplayValues[cached].exitTime<=now)
   {usedEnd=g_orbReplayEnds[cached];g_orbReplayMemoHits++;return g_orbReplayValues[cached];}
   g_orbReplayMemoMisses++;
   HistResult result=g_rtAdvancedAuditEngine
      ?SimulateHistoricalLifecycleAdvanced(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,usedEnd,forcedExitTime,forcedExitOutcome)
      :SimulateHistoricalLifecycle(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,usedEnd,forcedExitTime,forcedExitOutcome);
   // Do not freeze OPEN, DATA, asynchronous tick requests or this forming minute.
   if(result.valid&&result.outcome!="open"&&result.invalidReason==""&&result.exitTime>0
      &&result.exitTime<=now&&result.exitTime<iTime(_Symbol,PERIOD_M1,0)&&epoch==OrbReplayDataEpoch())
   {
      int slot=g_orbReplayMemo.Add(key);
      if(slot>=0)
      {
         if(ArraySize(g_orbReplayValues)<=slot)
         {ArrayResize(g_orbReplayValues,slot+1,512);ArrayResize(g_orbReplayEnds,slot+1,512);}
         g_orbReplayValues[slot]=result;g_orbReplayEnds[slot]=usedEnd;
      }
   }
   return result;
}
'''.replace('FIELDS',fields.rstrip())
    a=s.index('HistResult SimulateHistoricalLifecycle(')
    # Insert before the original lifecycle, preserve both replay implementations.
    s=s[:a]+wrapper+'\n'+s[a:]
    pattern=r'HistResult sim=g_rtAdvancedAuditEngine\s*\?SimulateHistoricalLifecycleAdvanced\((entryT,te,g_histRunNow,.*?)\)\s*:SimulateHistoricalLifecycle\(entryT,te,g_histRunNow,.*?\);'
    s,count=re.subn(pattern,lambda m:'HistResult sim=OrbMemoLifecycle('+m[1]+');',s,flags=re.S)
    if count!=1:raise ValueError(f'{name}: primary call drift {count}')
    pattern=r'referenceSim=g_rtAdvancedAuditEngine\s*\?SimulateHistoricalLifecycleAdvanced\((entryT,te,g_histRunNow,.*?)\)\s*:SimulateHistoricalLifecycle\(entryT,te,g_histRunNow,.*?\);'
    s,count=re.subn(pattern,lambda m:'referenceSim=OrbMemoLifecycle('+m[1]+');',s,flags=re.S)
    if count!=(1 if 'StrategyLibrary' in name else 0):raise ValueError('Reference call drift')
    write(name,raw,s)

if __name__=='__main__':
    nas()
    for name in ('OrbUltimateEA.mq5','OrbUltimateEA_StrategyLibrary.mq5'):orb(name)
