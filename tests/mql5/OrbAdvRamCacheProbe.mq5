#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../IndicatorCodeExamples/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
void SeedActive(datetime day,double price)
{
 OrbAdvClearLoadedDay();ArrayResize(g_orbAdvBlocks,2);
 for(int i=0;i<2;i++)
 {
   g_orbAdvBlocks[i].minuteMs=(long)day*1000+i*60000;
   g_orbAdvBlocks[i].firstMs=g_orbAdvBlocks[i].minuteMs+1;
   g_orbAdvBlocks[i].lastMs=g_orbAdvBlocks[i].minuteMs+59000;
   g_orbAdvBlocks[i].minBid=price;g_orbAdvBlocks[i].maxBid=price+1;
   g_orbAdvBlocks[i].minAsk=price+0.1;g_orbAdvBlocks[i].maxAsk=price+1.1;
   g_orbAdvBlocks[i].validQuotes=2;
 }
 OrbAdvBuildTree();g_orbAdvLoadedDayKey=OrbAdvDayKey(day);
 g_orbAdvLoadedSymbol=_Symbol;g_orbAdvLoadedServer=AccountInfoString(ACCOUNT_SERVER);
}
void OnStart()
{
 OrbAdvClearDayCache();int checks=0,failed=0;
 datetime a=D'2018.01.02',b=D'2018.01.03';
 SeedActive(a,100);
 g_orbAdvDayCache[0].dayKey=OrbAdvDayKey(a);g_orbAdvDayCache[0].symbol=_Symbol;
 g_orbAdvDayCache[0].server=AccountInfoString(ACCOUNT_SERVER);
 ArrayCopy(g_orbAdvDayCache[0].blocks,g_orbAdvBlocks);ArrayCopy(g_orbAdvDayCache[0].tree,g_orbAdvTree);
 ulong hashA=OrbAdvBlocksChecksum();SeedActive(b,200);ulong hashB=OrbAdvBlocksChecksum();
 ulong started=GetTickCount64();
 for(int i=0;i<1000;i++)
 {
   bool first=i%2==0;checks++;
   if(!OrbAdvLoadDay(first?a:b)||OrbAdvBlocksChecksum()!=(first?hashA:hashB)
      ||g_orbAdvTree[1].minBid!=(first?100:200)||ArraySize(g_orbAdvBlocks)!=2)failed++;
 }
 checks++;if(g_orbAdvRamHits!=1000||g_orbAdvIndexColdBuilds!=0||g_orbAdvIndexDiskHits!=0)failed++;
 OrbAdvancedAuditResetRunStats();checks++;
 for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS;i++)if(g_orbAdvDayCache[i].dayKey!=0||ArraySize(g_orbAdvDayCache[i].blocks)!=0)failed++;
 string result=StringFormat("{\"checks\":%d,\"failed\":%d,\"elapsed_ms\":%d}",checks,failed,(int)(GetTickCount64()-started));
 int f=FileOpen("OrbAdvRamCacheProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
 if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print(result);
}
