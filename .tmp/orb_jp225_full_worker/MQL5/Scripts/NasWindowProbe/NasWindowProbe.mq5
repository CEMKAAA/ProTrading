#property strict
#define OnInit WindowOriginalInit
#define OnDeinit WindowOriginalDeinit
#define OnTick WindowOriginalTick
#define OnTimer WindowOriginalTimer
#define OnChartEvent WindowOriginalEvent
#define OnTradeTransaction WindowOriginalTransaction
#include "NasUltimate_StrategyLibrary.mq5"
string ResultIdentity()
{
   string s="";
   for(int i=0;i<7;i++)s+=g_historyAuditRows[i]+"\n";
   for(int i=0;i<ArraySize(g_nasLibraryAuditExits);i++)
      s+=(string)g_nasLibraryAuditExits[i]+"|"+AuditMemoPrice(g_nasLibraryAuditReturns[i])+"\n";
   return NasMlSha256(s);
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0||_Symbol!="BTCUSDm")return;
   if(InpNasLibraryAllowLive||InpNasBridgeEnabled)return;
   if(WindowOriginalInit()!=INIT_SUCCEEDED)return;
   EventKillTimer();g_historyRefreshPending=false;g_eaEnabledRuntime=false;g_nasBridgeEnabledRuntime=false;
   int preset=-1;
   for(int i=0;i<ArraySize(g_nasLibrary);i++)if(g_nasLibrary[i].symbol==NasLibrarySymbol(_Symbol)){preset=i;break;}
   if(preset<0)return;
   g_nasLibrary[preset].user=true;g_nasLibrary[preset].profile=NasLibraryInputProfile();
   if(!NasLibraryApply(preset))return;
   g_historyRefreshPending=false;
   FolderCreate("NasWindowProbe");
   int h=FileOpen("NasWindowProbe\\results.jsonl",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(h==INVALID_HANDLE)return;
   int windows[]={260,52,20,10,5,2,260};
   // The first call may hydrate previously uncached M1 history. Establish a
   // stable data snapshot before measuring cached-vs-cold computational parity.
   g_auditWeeksRuntime=260;string previous="";bool stable=false;
   for(int pass=0;pass<5&&!IsStopped();pass++)
   {
      g_nasReplayMemo.Reset("SYNC_"+(string)pass);DrawRecentSignalHistory();
      string current=ResultIdentity();
      if(current==previous){stable=true;break;}
      previous=current;
   }
   if(!stable){FileWriteString(h,"{\"error\":\"market_data_not_stable\"}\n");FileClose(h);return;}
   for(int w=0;w<ArraySize(windows)&&!IsStopped();w++)
   {
      g_auditWeeksRuntime=windows[w];
      ulong start=GetTickCount64();long hits=g_nasReplayMemoHits;
      DrawRecentSignalHistory();
      ulong warm=GetTickCount64()-start;long warmHits=g_nasReplayMemoHits-hits;
      string warmHash=ResultIdentity();int warmN=ArraySize(g_nasLibraryAuditExits);
      g_nasReplayMemo.Reset("FORCE_COLD_"+(string)w);
      start=GetTickCount64();DrawRecentSignalHistory();ulong cold=GetTickCount64()-start;
      string coldHash=ResultIdentity();
      string row="{\"weeks\":"+(string)windows[w]+",\"warm_ms\":"+(string)warm
         +",\"cold_ms\":"+(string)cold+",\"memo_hits\":"+(string)warmHits+",\"closed\":"+(string)warmN
         +",\"same\":"+(warmHash==coldHash?"true":"false")+",\"blocked\":"+(g_historyCoverageBlocked?"true":"false")+"}";
      FileWriteString(h,row+"\n");FileFlush(h);Print("NAS_WINDOW_PROBE ",row);
   }
   FileClose(h);EventKillTimer();ObjectsDeleteAll(0,PREFIX);ObjectsDeleteAll(0,NAS_LIB_PREFIX);
}
