"""Reuse completed ORB day preparation, keeping original day logic verbatim."""
from pathlib import Path
import re
from add_audit_closed_memo import read,write

def update(name):
    raw,s=read(name)
    if 'struct OrbPrepMemoValue' in s:
        a=s.index('struct OrbPrepMemoValue');b=s.index('int ProcessHistoricalPrepDayUncached(const int back)',a)
        s=s[:a]+s[b:].replace('int ProcessHistoricalPrepDayUncached(const int back)','int ProcessHistoricalPrepDay(const int back)',1)
    fields=[]
    for typ,n in re.findall(r'^(\w+)\s+(g_rt\w+)\s*=',s,re.M):
        if n=='g_rtHistoricalWeeks':continue
        v=f'AuditMemoPrice({n})' if typ=='double' else f'(string){n}'
        fields.append(f'   key+="|{n}="+{v};')
    arrays=['g_histWindowSignals','g_histAcceptedSignals','g_histOperationalSignals']
    if 'StrategyLibrary' in name:arrays+=['g_regimeReferenceSignals','g_regimeReferenceWindows']
    members='\n'.join(f'   OrbWindowSignal a{i}[];' for i in range(len(arrays)))
    counts='\n'.join(f'   int before{i}=ArraySize({a});' for i,a in enumerate(arrays))
    restore='\n'.join(f'      int base{i}=ArraySize({a}),count{i}=ArraySize(g_orbPrepMemoValues[cached].a{i});\n      ArrayResize({a},base{i}+count{i},256);\n      for(int j=0;j<count{i};j++){a}[base{i}+j]=g_orbPrepMemoValues[cached].a{i}[j];' for i,a in enumerate(arrays))
    capture='\n'.join(f'         ArrayResize(g_orbPrepMemoValues[slot].a{i},ArraySize({a})-before{i});\n         for(int j=before{i};j<ArraySize({a});j++)g_orbPrepMemoValues[slot].a{i}[j-before{i}]={a}[j];' for i,a in enumerate(arrays))
    wrapper='''struct OrbPrepMemoValue
{
   OrbHistoricalDaySnapshot snapshot;
   int rejected;
MEMBERS
};
AuditMemoIndex g_orbPrepMemo;
OrbPrepMemoValue g_orbPrepMemoValues[];
long g_orbPrepMemoHits=0;

int ProcessHistoricalPrepDay(const int back)
{
   if(back<0||back>=ArraySize(g_histDaySnapshots))return ProcessHistoricalPrepDayUncached(back);
   string epoch=OrbReplayDataEpoch()+"|"+(string)g_histNasCacheClosedBar+"|"+(string)g_histNasCacheFrom
      +"|"+(string)g_histNasCacheEventFrom+"|"+(string)SeriesInfoInteger(_Symbol,g_rtSignalTf,SERIES_BARS_COUNT)
      +"|"+(string)SeriesInfoInteger(_Symbol,g_rtSignalTf,SERIES_FIRSTDATE);
   g_orbPrepMemo.Reset(epoch);
   string key=(string)(g_histRunNyMid-back*86400)+"|"+(string)g_orbRfEnabled;
FIELDS
   for(int r=0;r<ORB_REGIME_COUNT;r++)key+="|macro="+(string)g_regimeAllowed[r];
   for(int r=0;r<ORB_RF_COUNT;r++)key+="|rf="+(string)g_orbRfBlocked[r];
   int cached=g_orbPrepMemo.Find(key);
   if(cached>=0)
   {
      g_histDaySnapshots[back]=g_orbPrepMemoValues[cached].snapshot;
RESTORE
      g_orbPrepMemoHits++;return g_orbPrepMemoValues[cached].rejected;
   }
COUNTS
   int rejected=ProcessHistoricalPrepDayUncached(back);
   OrbHistoricalDaySnapshot snapshot=g_histDaySnapshots[back];
   // Never cache a forming session or a missing-data/invalid day. No-signal
   // completed sessions are reusable, but their full prepared context is kept.
   if(snapshot.known&&snapshot.valid&&snapshot.operationalKnown&&snapshot.tradeEnd>0
      &&snapshot.tradeEnd<iTime(_Symbol,PERIOD_M1,0)
      &&StringFind(epoch,OrbReplayDataEpoch()+"|")==0)
   {
      int slot=g_orbPrepMemo.Add(key);
      if(slot>=0)
      {
         if(ArraySize(g_orbPrepMemoValues)<=slot)ArrayResize(g_orbPrepMemoValues,slot+1,64);
         g_orbPrepMemoValues[slot].snapshot=snapshot;g_orbPrepMemoValues[slot].rejected=rejected;
CAPTURE
      }
   }
   return rejected;
}

'''.replace('MEMBERS',members).replace('FIELDS','\n'.join(fields)).replace('RESTORE',restore).replace('COUNTS',counts).replace('CAPTURE',capture)
    marker='int ProcessHistoricalPrepDay(const int back)'
    if s.count(marker)!=1:raise ValueError('Prep signature drift')
    s=s.replace(marker,wrapper+'int ProcessHistoricalPrepDayUncached(const int back)',1)
    write(name,raw,s)

if __name__=='__main__':
    for name in ('OrbUltimateEA.mq5','OrbUltimateEA_StrategyLibrary.mq5'):update(name)
