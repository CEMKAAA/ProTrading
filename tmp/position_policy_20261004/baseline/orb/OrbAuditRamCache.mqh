#ifndef ORB_AUDIT_RAM_CACHE_MQH
#define ORB_AUDIT_RAM_CACHE_MQH
// Exact, completed-day indexes. ArraySwap transfers ownership instead of
// copying thousands of nodes whenever overlapping trades revisit a day.
#define ORB_ADV_DAY_CACHE_SLOTS 64
struct OrbAdvCachedDay
{
   int dayKey;
   string symbol,server;
   long touched;
   bool fromDisk;
   OrbAdvMinuteBlock blocks[];
   OrbAdvTreeNode tree[];
};
OrbAdvCachedDay g_orbAdvDayCache[ORB_ADV_DAY_CACHE_SLOTS];
long g_orbAdvCacheClock=0,g_orbAdvRamHits=0;
void OrbAdvClearDayCache()
{
   for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS;i++)
   {
      g_orbAdvDayCache[i].dayKey=0;
      ArrayFree(g_orbAdvDayCache[i].blocks);ArrayFree(g_orbAdvDayCache[i].tree);
   }
   g_orbAdvCacheClock=0;g_orbAdvRamHits=0;
}
bool OrbAdvSelectCachedDay(int dayKey,string server)
{
   int hit=-1;
   int currentDay=OrbAdvDayKey(TimeCurrent());
   if(dayKey<currentDay)
      for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS;i++)
         if(g_orbAdvDayCache[i].dayKey==dayKey&&g_orbAdvDayCache[i].symbol==_Symbol
            &&g_orbAdvDayCache[i].server==server){hit=i;break;}
   if(g_orbAdvLoadedDayKey>0&&g_orbAdvLoadedDayKey<currentDay
      &&ArraySize(g_orbAdvBlocks)>0&&ArraySize(g_orbAdvTree)>0)
   {
      int slot=-1;long oldest=LONG_MAX;
      for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS;i++)
      {
         if(i==hit)continue;
         if(g_orbAdvDayCache[i].dayKey==0){slot=i;break;}
         if(g_orbAdvDayCache[i].touched<oldest){oldest=g_orbAdvDayCache[i].touched;slot=i;}
      }
      if(slot>=0)
      {
         ArrayFree(g_orbAdvDayCache[slot].blocks);ArrayFree(g_orbAdvDayCache[slot].tree);
         ArraySwap(g_orbAdvDayCache[slot].blocks,g_orbAdvBlocks);
         ArraySwap(g_orbAdvDayCache[slot].tree,g_orbAdvTree);
         g_orbAdvDayCache[slot].dayKey=g_orbAdvLoadedDayKey;
         g_orbAdvDayCache[slot].symbol=g_orbAdvLoadedSymbol;g_orbAdvDayCache[slot].server=g_orbAdvLoadedServer;
         g_orbAdvDayCache[slot].fromDisk=g_orbAdvLoadedFromDisk;g_orbAdvDayCache[slot].touched=++g_orbAdvCacheClock;
      }
   }
   OrbAdvClearLoadedDay();
   if(hit<0)return false;
   ArraySwap(g_orbAdvBlocks,g_orbAdvDayCache[hit].blocks);
   ArraySwap(g_orbAdvTree,g_orbAdvDayCache[hit].tree);
   g_orbAdvLoadedDayKey=dayKey;g_orbAdvLoadedSymbol=_Symbol;g_orbAdvLoadedServer=server;
   g_orbAdvLoadedFromDisk=g_orbAdvDayCache[hit].fromDisk;g_orbAdvDayCache[hit].dayKey=0;
   g_orbAdvRamHits++;g_orbAdvLastStatus="INDEX_RAM";return true;
}
int OrbAdvReadExactQuotes(ulong from,ulong to,MqlTick &fallback[],int &first,int &after,bool &view)
{
   first=0;after=0;view=false;
   if(g_histAuditRunning&&PrepareHistoricalTickReplayRange(from,to,first,after,240))
   {view=true;return after-first;}
   // Prefetch failure cannot substitute partial quotes for the requested minute.
   // Retry the exact range using the same guarded reader as the reference path.
   first=0;int count=AuditCopyTicksRange(_Symbol,fallback,COPY_TICKS_INFO,from,to);
   after=MathMax(0,count);return count;
}
#endif
