#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "EntryEngineLabEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
void Check(bool ok,string why){checks++;if(!ok){failed++;if(failed<10)Print("ADV_ACCEL_FAIL ",why);}}
void Seed(datetime day,double price)
{
   OrbAdvClearLoadedDay();ArrayResize(g_orbAdvBlocks,2);
   for(int i=0;i<2;i++)
   {
      OrbAdvMinuteBlock b;ZeroMemory(b);
      b.minuteMs=(long)day*1000+i*60000;b.firstMs=b.minuteMs+1;b.lastMs=b.minuteMs+59000;
      b.minBid=price;b.maxBid=price+1;b.minAsk=price+0.1;b.maxAsk=price+1.1;b.validQuotes=2;
      g_orbAdvBlocks[i]=b;
   }
   OrbAdvBuildTree();g_orbAdvLoadedDayKey=OrbAdvDayKey(day);
   g_orbAdvLoadedSymbol=_Symbol;g_orbAdvLoadedServer=AccountInfoString(ACCOUNT_SERVER);
}
void CheckPages()
{
   OrbAdvancedAuditResetRunStats();string server=AccountInfoString(ACCOUNT_SERVER);
   datetime a=D'2018.01.02',b=D'2018.01.03';
   Seed(a,100);ulong hashA=OrbAdvBlocksChecksum();
   Check(!OrbAdvSelectCachedDay(OrbAdvDayKey(b),server),"miss saves active page");
   Seed(b,200);ulong hashB=OrbAdvBlocksChecksum();
   for(int i=0;i<1000;i++)
   {
      bool first=i%2==0;
      Check(OrbAdvLoadDay(first?a:b)&&OrbAdvBlocksChecksum()==(first?hashA:hashB)
         &&g_orbAdvTree[1].minBid==(first?100:200)&&ArraySize(g_orbAdvBlocks)==2,"ownership swaps preserve tree and checksum");
   }
   Check(g_orbAdvIndexColdBuilds==0&&g_orbAdvIndexDiskHits==0,"cache hit performs no terminal I/O");
   OrbAdvancedAuditResetRunStats();
   for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS;i++)
      Check(g_orbAdvDayCache[i].dayKey==0&&ArraySize(g_orbAdvDayCache[i].blocks)==0,"reset frees every page");
   for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS+3;i++)
   {
      Seed(a+i*86400,100+i);
      OrbAdvSelectCachedDay(OrbAdvDayKey(D'2030.01.01'),server);
   }
   Check(OrbAdvSelectCachedDay(OrbAdvDayKey(a+(ORB_ADV_DAY_CACHE_SLOTS+2)*86400),server),"newest page survives bounded eviction");
   Check(!OrbAdvSelectCachedDay(OrbAdvDayKey(a),server),"oldest page evicted without stale hit");
   Seed(OrbAdvDayStart(TimeCurrent()),100);
   OrbAdvSelectCachedDay(OrbAdvDayKey(D'2030.01.01'),server);
   Check(!OrbAdvSelectCachedDay(OrbAdvDayKey(TimeCurrent()),server),"mutable current day is never retained");
   OrbAdvancedAuditResetRunStats();
}
bool SameQuote(const MqlTick &a,const MqlTick &b)
{
   return a.time==b.time&&a.time_msc==b.time_msc&&a.bid==b.bid&&a.ask==b.ask
      &&a.last==b.last&&a.volume==b.volume&&a.volume_real==b.volume_real&&a.flags==b.flags;
}
void CheckViews()
{
   ClearHistoricalTickReplayCache();g_histAuditRunning=true;
   ulong start=(ulong)D'2020.01.01'*1000;
   ArrayResize(g_histTickReplayCache,32);
   for(int i=0;i<32;i++)
   {
      MqlTick t;ZeroMemory(t);t.time_msc=(long)start+(i/2)*1000;t.time=(datetime)(t.time_msc/1000);
      t.bid=100+i*0.01;t.ask=t.bid+0.03;g_histTickReplayCache[i]=t;
   }
   g_histTickReplayCacheSymbol=_Symbol;g_histTickReplayCacheFromMs=start;g_histTickReplayCacheToMs=start+15999;
   for(int i=0;i<16;i++)for(int j=i;j<16;j++)
   {
      MqlTick fallback[];int first=0,after=0;bool view=false;
      int count=OrbAdvReadExactQuotes(start+i*1000,start+j*1000,fallback,first,after,view);
      Check(view&&count==2*(j-i+1)&&first==2*i&&after==2*(j+1),"inclusive bounds retain duplicate timestamps");
   }
   ClearHistoricalTickReplayCache();
   g_histRunNow=iTime(_Symbol,PERIOD_M1,1)+60;
   ulong end=(ulong)(g_histRunNow-3600)*1000;
   MqlTick direct[];
   for(int i=0;i<8;i++)
   {
      ulong from=end+(ulong)i*60000,to=from+59999;
      int n=AuditCopyTicksRange(_Symbol,direct,COPY_TICKS_INFO,from,to);
      MqlTick fallback[];int first=0,after=0;bool view=false;
      int read=OrbAdvReadExactQuotes(from,to,fallback,first,after,view);
      Check(n==read,"bulk history slice count equals direct guarded range");
      if(n>=0&&n==read)
         for(int k=0;k<n;k++)
         {MqlTick actual=view?g_histTickReplayCache[first+k]:fallback[k];Check(SameQuote(direct[k],actual),"all quote fields and chronology match");}
   }
   g_histAuditRunning=false;ClearHistoricalTickReplayCache();
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   CheckPages();CheckViews();
   int f=FileOpen("AuditPerf_optimized_413636fb.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed+"\n");FileClose(f);}
   EventKillTimer();
}
