#include "AuditTickReadGuard.mqh"
#ifndef ORB_ADVANCED_AUDIT_ENGINE_MQH
#define ORB_ADVANCED_AUDIT_ENGINE_MQH

// Exact audit accelerator. The legacy replay engine remains the reference
// implementation and is used whenever this index cannot prove parity-safe use.
#define ORB_ADV_INDEX_MAGIC          1329742929
#define ORB_ADV_INDEX_SCHEMA         2
#define ORB_ADV_MINUTE_MS            60000
#define ORB_ADV_MAX_DAY_BLOCKS       1500

struct OrbAdvMinuteBlock
{
   long minuteMs;
   long firstMs;
   long lastMs;
   double minBid;
   double maxBid;
   double minAsk;
   double maxAsk;
   int validQuotes;
};

struct OrbAdvTreeNode
{
   int leftBlock;
   int rightBlock;
   long firstMs;
   long lastMs;
   double minBid;
   double maxBid;
   double minAsk;
   double maxAsk;
   int validQuotes;
};

// Per-run cache only: never retain a potentially revised history across audits.
#define ORB_ADV_DAY_CACHE_SLOTS 8
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

OrbAdvMinuteBlock g_orbAdvBlocks[];
OrbAdvTreeNode g_orbAdvTree[];
int g_orbAdvLoadedDayKey=0;
string g_orbAdvLoadedSymbol="";
string g_orbAdvLoadedServer="";
bool g_orbAdvLoadedFromDisk=false;
long g_orbAdvIndexDiskHits=0;
long g_orbAdvIndexColdBuilds=0;
long g_orbAdvIndexInvalid=0;
long g_orbAdvTreeQueries=0;
long g_orbAdvTreeNodesSkipped=0;
long g_orbAdvExactMinutes=0;
long g_orbAdvExactTicks=0;
long g_orbAdvParityChecks=0;
long g_orbAdvParityMismatches=0;
double g_orbAdvIndexIoSec=0.0;
string g_orbAdvLastStatus="IDLE";

string OrbAdvSafeToken(string value)
{
   string out=value;
   StringReplace(out,"\\","_");StringReplace(out,"/","_");
   StringReplace(out,":","_");StringReplace(out,"*","_");
   StringReplace(out,"?","_");StringReplace(out,"\"","_");
   StringReplace(out,"<","_");StringReplace(out,">","_");
   StringReplace(out,"|","_");StringReplace(out," ","_");
   if(StringLen(out)<=0)out="UNKNOWN";
   return out;
}

int OrbAdvDayKey(const datetime value)
{
   MqlDateTime st;TimeToStruct(value,st);
   return st.year*10000+st.mon*100+st.day;
}

datetime OrbAdvDayStart(const datetime value)
{
   MqlDateTime st;TimeToStruct(value,st);
   st.hour=0;st.min=0;st.sec=0;
   return StructToTime(st);
}

string OrbAdvIndexRoot()
{
   return "ORB_ADV_EXACT_V"+IntegerToString(ORB_ADV_INDEX_SCHEMA)+"\\"
      +OrbAdvSafeToken(AccountInfoString(ACCOUNT_SERVER))+"\\"+OrbAdvSafeToken(_Symbol);
}

string OrbAdvIndexFile(const int dayKey)
{
   return OrbAdvIndexRoot()+"\\"+IntegerToString(dayKey)+".bin";
}

ulong OrbAdvHashByte(ulong hash,const uchar value)
{
   hash^=(ulong)value;
   return hash*(ulong)1099511628211;
}

ulong OrbAdvHashText(ulong hash,const string value)
{
   uchar bytes[];
   int count=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(count>0&&bytes[count-1]==0)count--;
   for(int i=0;i<count;i++)hash=OrbAdvHashByte(hash,bytes[i]);
   return hash;
}

ulong OrbAdvHashLong(ulong hash,const long value)
{
   ulong bits=(ulong)value;
   for(int i=0;i<8;i++)hash=OrbAdvHashByte(hash,(uchar)((bits>>(i*8))&0xff));
   return hash;
}

ulong OrbAdvBlocksChecksum()
{
   ulong hash=(ulong)1469598103934665603;
   int count=ArraySize(g_orbAdvBlocks);
   hash=OrbAdvHashLong(hash,(long)count);
   double quantum=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(quantum<=0.0)quantum=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(quantum<=0.0)quantum=0.00000001;
   for(int i=0;i<count;i++)
   {
      OrbAdvMinuteBlock block=g_orbAdvBlocks[i];
      hash=OrbAdvHashLong(hash,block.minuteMs);
      hash=OrbAdvHashLong(hash,block.firstMs);
      hash=OrbAdvHashLong(hash,block.lastMs);
      hash=OrbAdvHashLong(hash,(long)block.validQuotes);
      hash=OrbAdvHashLong(hash,(long)MathRound(block.minBid/quantum));
      hash=OrbAdvHashLong(hash,(long)MathRound(block.maxBid/quantum));
      hash=OrbAdvHashLong(hash,(long)MathRound(block.minAsk/quantum));
      hash=OrbAdvHashLong(hash,(long)MathRound(block.maxAsk/quantum));
   }
   return hash;
}

void OrbAdvClearLoadedDay()
{
   ArrayResize(g_orbAdvBlocks,0);
   ArrayResize(g_orbAdvTree,0);
   g_orbAdvLoadedDayKey=0;
   g_orbAdvLoadedSymbol="";
   g_orbAdvLoadedServer="";
   g_orbAdvLoadedFromDisk=false;
}

bool OrbAdvCreateFolders()
{
   string root="ORB_ADV_EXACT_V"+IntegerToString(ORB_ADV_INDEX_SCHEMA);
   if(!FolderCreate(root,FILE_COMMON))ResetLastError();
   string serverPath=root+"\\"+OrbAdvSafeToken(AccountInfoString(ACCOUNT_SERVER));
   if(!FolderCreate(serverPath,FILE_COMMON))ResetLastError();
   string symbolPath=serverPath+"\\"+OrbAdvSafeToken(_Symbol);
   if(!FolderCreate(symbolPath,FILE_COMMON))ResetLastError();
   return true;
}

bool OrbAdvWriteIndexAtomic(const int dayKey)
{
   if(!InpAdvancedAuditPersistIndex)return true;
   OrbAdvCreateFolders();
   string target=OrbAdvIndexFile(dayKey);
   string temp=target+".tmp."+StringFormat("%I64d",ChartID());
   FileDelete(temp,FILE_COMMON);
   int handle=FileOpen(temp,FILE_BIN|FILE_WRITE|FILE_COMMON);
   if(handle==INVALID_HANDLE)return false;
   ulong checksum=OrbAdvBlocksChecksum();
   int count=ArraySize(g_orbAdvBlocks);
   FileWriteInteger(handle,ORB_ADV_INDEX_MAGIC,INT_VALUE);
   FileWriteInteger(handle,ORB_ADV_INDEX_SCHEMA,INT_VALUE);
   FileWriteInteger(handle,dayKey,INT_VALUE);
   FileWriteInteger(handle,_Digits,INT_VALUE);
   FileWriteInteger(handle,count,INT_VALUE);
   FileWriteDouble(handle,SymbolInfoDouble(_Symbol,SYMBOL_POINT));
   FileWriteDouble(handle,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE));
   FileWriteLong(handle,(long)checksum);
   for(int i=0;i<count;i++)
   {
      OrbAdvMinuteBlock block=g_orbAdvBlocks[i];
      FileWriteLong(handle,block.minuteMs);
      FileWriteLong(handle,block.firstMs);
      FileWriteLong(handle,block.lastMs);
      FileWriteDouble(handle,block.minBid);
      FileWriteDouble(handle,block.maxBid);
      FileWriteDouble(handle,block.minAsk);
      FileWriteDouble(handle,block.maxAsk);
      FileWriteInteger(handle,block.validQuotes,INT_VALUE);
   }
   FileFlush(handle);
   FileClose(handle);
   if(FileMove(temp,FILE_COMMON,target,FILE_COMMON|FILE_REWRITE))return true;
   FileDelete(temp,FILE_COMMON);
   return false;
}

bool OrbAdvReadIndex(const int dayKey)
{
   if(!InpAdvancedAuditPersistIndex)return false;
   string fileName=OrbAdvIndexFile(dayKey);
   int handle=FileOpen(fileName,FILE_BIN|FILE_READ|FILE_COMMON|FILE_SHARE_READ);
   if(handle==INVALID_HANDLE)return false;
   int magic=FileReadInteger(handle,INT_VALUE);
   int schema=FileReadInteger(handle,INT_VALUE);
   int storedDay=FileReadInteger(handle,INT_VALUE);
   int digits=FileReadInteger(handle,INT_VALUE);
   int count=FileReadInteger(handle,INT_VALUE);
   double point=FileReadDouble(handle);
   double tickSize=FileReadDouble(handle);
   ulong checksum=(ulong)FileReadLong(handle);
   double livePoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double liveTick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   bool headerOk=(magic==ORB_ADV_INDEX_MAGIC&&schema==ORB_ADV_INDEX_SCHEMA&&storedDay==dayKey
      &&digits==_Digits&&count>0&&count<=ORB_ADV_MAX_DAY_BLOCKS
      &&MathAbs(point-livePoint)<=MathMax(1e-12,livePoint*1e-9)
      &&MathAbs(tickSize-liveTick)<=MathMax(1e-12,MathMax(tickSize,liveTick)*1e-9));
   if(!headerOk){FileClose(handle);g_orbAdvIndexInvalid++;return false;}
   ArrayResize(g_orbAdvBlocks,count);
   long previousMinute=-1;
   bool valid=true;
   for(int i=0;i<count;i++)
   {
      OrbAdvMinuteBlock block;
      block.minuteMs=FileReadLong(handle);
      block.firstMs=FileReadLong(handle);
      block.lastMs=FileReadLong(handle);
      block.minBid=FileReadDouble(handle);
      block.maxBid=FileReadDouble(handle);
      block.minAsk=FileReadDouble(handle);
      block.maxAsk=FileReadDouble(handle);
      block.validQuotes=FileReadInteger(handle,INT_VALUE);
      if(block.validQuotes<=0||block.minuteMs<=previousMinute||block.firstMs<block.minuteMs
         ||block.lastMs<block.firstMs||block.lastMs>=block.minuteMs+ORB_ADV_MINUTE_MS
         ||block.minBid<=0.0||block.maxBid<block.minBid||block.minAsk<=0.0||block.maxAsk<block.minAsk)
         valid=false;
      previousMinute=block.minuteMs;
      g_orbAdvBlocks[i]=block;
   }
   if(!FileIsEnding(handle))valid=false;
   FileClose(handle);
   if(!valid||OrbAdvBlocksChecksum()!=checksum)
   {
      ArrayResize(g_orbAdvBlocks,0);
      g_orbAdvIndexInvalid++;
      return false;
   }
   return true;
}

bool OrbAdvBuildDayIndex(const datetime dayStart)
{
   datetime dayEnd=dayStart+86400-1;
   datetime now=TimeCurrent();
   if(dayEnd>now)dayEnd=now;
   if(dayEnd<=dayStart)return false;
   MqlTick ticks[];
   ResetLastError();
   int copied=AuditCopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)dayStart*1000,(ulong)dayEnd*1000+999);
   if(copied<=0)return false;
   ArrayResize(g_orbAdvBlocks,ORB_ADV_MAX_DAY_BLOCKS);
   int count=0;
   long activeMinute=-1;
   OrbAdvMinuteBlock block;
   ZeroMemory(block);
   for(int i=0;i<copied;i++)
   {
      double bid=ticks[i].bid,ask=ticks[i].ask;
      if(bid<=0.0||ask<=0.0||ticks[i].time_msc<=0)continue;
      long minuteMs=(ticks[i].time_msc/ORB_ADV_MINUTE_MS)*ORB_ADV_MINUTE_MS;
      if(minuteMs!=activeMinute)
      {
         if(activeMinute>=0)
         {
            if(count>=ORB_ADV_MAX_DAY_BLOCKS){ArrayResize(g_orbAdvBlocks,0);return false;}
            g_orbAdvBlocks[count++]=block;
         }
         ZeroMemory(block);
         activeMinute=minuteMs;
         block.minuteMs=minuteMs;
         block.firstMs=ticks[i].time_msc;
         block.lastMs=ticks[i].time_msc;
         block.minBid=bid;block.maxBid=bid;block.minAsk=ask;block.maxAsk=ask;
         block.validQuotes=1;
      }
      else
      {
         block.lastMs=ticks[i].time_msc;
         if(bid<block.minBid)block.minBid=bid;if(bid>block.maxBid)block.maxBid=bid;
         if(ask<block.minAsk)block.minAsk=ask;if(ask>block.maxAsk)block.maxAsk=ask;
         block.validQuotes++;
      }
   }
   if(activeMinute>=0)
   {
      if(count>=ORB_ADV_MAX_DAY_BLOCKS){ArrayResize(g_orbAdvBlocks,0);return false;}
      g_orbAdvBlocks[count++]=block;
   }
   ArrayResize(g_orbAdvBlocks,count);
   if(count<=0)return false;
   int currentDay=OrbAdvDayKey(now);
   if(OrbAdvDayKey(dayStart)<currentDay&&!OrbAdvWriteIndexAtomic(OrbAdvDayKey(dayStart)))
      g_orbAdvLastStatus="INDEX_WRITE_FALLBACK";
   return true;
}

void OrbAdvMergeNode(const int node,const int left,const int right)
{
   OrbAdvTreeNode a=g_orbAdvTree[left],b=g_orbAdvTree[right],out;
   out.leftBlock=a.leftBlock;out.rightBlock=b.rightBlock;
   out.firstMs=a.firstMs;out.lastMs=b.lastMs;
   out.minBid=MathMin(a.minBid,b.minBid);out.maxBid=MathMax(a.maxBid,b.maxBid);
   out.minAsk=MathMin(a.minAsk,b.minAsk);out.maxAsk=MathMax(a.maxAsk,b.maxAsk);
   out.validQuotes=a.validQuotes+b.validQuotes;
   g_orbAdvTree[node]=out;
}

void OrbAdvBuildTreeNode(const int node,const int leftBlock,const int rightBlock)
{
   if(leftBlock==rightBlock)
   {
      OrbAdvMinuteBlock block=g_orbAdvBlocks[leftBlock];OrbAdvTreeNode out;
      out.leftBlock=leftBlock;out.rightBlock=rightBlock;
      out.firstMs=block.firstMs;out.lastMs=block.lastMs;
      out.minBid=block.minBid;out.maxBid=block.maxBid;
      out.minAsk=block.minAsk;out.maxAsk=block.maxAsk;out.validQuotes=block.validQuotes;
      g_orbAdvTree[node]=out;
      return;
   }
   int middle=leftBlock+(rightBlock-leftBlock)/2;
   OrbAdvBuildTreeNode(node*2,leftBlock,middle);
   OrbAdvBuildTreeNode(node*2+1,middle+1,rightBlock);
   OrbAdvMergeNode(node,node*2,node*2+1);
}

bool OrbAdvBuildTree()
{
   int count=ArraySize(g_orbAdvBlocks);
   if(count<=0)return false;
   ArrayResize(g_orbAdvTree,count*4+8);
   OrbAdvBuildTreeNode(1,0,count-1);
   return true;
}

bool OrbAdvLoadDay(const datetime dayStart)
{
   int dayKey=OrbAdvDayKey(dayStart);
   string server=AccountInfoString(ACCOUNT_SERVER);
   if(g_orbAdvLoadedDayKey==dayKey&&g_orbAdvLoadedSymbol==_Symbol&&g_orbAdvLoadedServer==server
      &&ArraySize(g_orbAdvBlocks)>0&&ArraySize(g_orbAdvTree)>0)return true;
   // Only completed days are cacheable. The currently forming day stays in
   // the original snapshot path. Cache failures fall back to the disk path.
   if(g_orbAdvLoadedDayKey>0&&g_orbAdvLoadedDayKey<OrbAdvDayKey(TimeCurrent())
      &&ArraySize(g_orbAdvBlocks)>0&&ArraySize(g_orbAdvTree)>0)
   {
      int slot=0;long oldest=LONG_MAX;
      for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS;i++)
      {
         if(g_orbAdvDayCache[i].dayKey==g_orbAdvLoadedDayKey
            &&g_orbAdvDayCache[i].symbol==g_orbAdvLoadedSymbol&&g_orbAdvDayCache[i].server==g_orbAdvLoadedServer){slot=i;break;}
         if(g_orbAdvDayCache[i].dayKey==0){slot=i;break;}
         if(g_orbAdvDayCache[i].touched<oldest){oldest=g_orbAdvDayCache[i].touched;slot=i;}
      }
      g_orbAdvDayCache[slot].dayKey=0;
      int nb=ArraySize(g_orbAdvBlocks),nt=ArraySize(g_orbAdvTree);
      if(ArrayResize(g_orbAdvDayCache[slot].blocks,nb)==nb&&ArrayResize(g_orbAdvDayCache[slot].tree,nt)==nt
         &&ArrayCopy(g_orbAdvDayCache[slot].blocks,g_orbAdvBlocks)==nb&&ArrayCopy(g_orbAdvDayCache[slot].tree,g_orbAdvTree)==nt)
      {
         g_orbAdvDayCache[slot].dayKey=g_orbAdvLoadedDayKey;
         g_orbAdvDayCache[slot].symbol=g_orbAdvLoadedSymbol;g_orbAdvDayCache[slot].server=g_orbAdvLoadedServer;
         g_orbAdvDayCache[slot].fromDisk=g_orbAdvLoadedFromDisk;g_orbAdvDayCache[slot].touched=++g_orbAdvCacheClock;
      }
   }
   OrbAdvClearLoadedDay();
   for(int i=0;i<ORB_ADV_DAY_CACHE_SLOTS;i++)
   {
      if(dayKey>=OrbAdvDayKey(TimeCurrent())||g_orbAdvDayCache[i].dayKey!=dayKey
         ||g_orbAdvDayCache[i].symbol!=_Symbol||g_orbAdvDayCache[i].server!=server)continue;
      int nb=ArraySize(g_orbAdvDayCache[i].blocks),nt=ArraySize(g_orbAdvDayCache[i].tree);
      if(ArrayCopy(g_orbAdvBlocks,g_orbAdvDayCache[i].blocks)==nb&&ArrayCopy(g_orbAdvTree,g_orbAdvDayCache[i].tree)==nt)
      {
         g_orbAdvLoadedDayKey=dayKey;g_orbAdvLoadedSymbol=_Symbol;g_orbAdvLoadedServer=server;
         g_orbAdvLoadedFromDisk=g_orbAdvDayCache[i].fromDisk;g_orbAdvDayCache[i].touched=++g_orbAdvCacheClock;
         g_orbAdvRamHits++;g_orbAdvLastStatus="INDEX_RAM";return true;
      }
      OrbAdvClearLoadedDay();break;
   }
   ulong started=GetTickCount64();
   bool loaded=OrbAdvReadIndex(dayKey);
   if(loaded){g_orbAdvIndexDiskHits++;g_orbAdvLoadedFromDisk=true;}
   else
   {
      if(!OrbAdvBuildDayIndex(dayStart))
      {
         g_orbAdvIndexIoSec+=(double)(GetTickCount64()-started)/1000.0;
         g_orbAdvLastStatus="INDEX_UNAVAILABLE";
         return false;
      }
      g_orbAdvIndexColdBuilds++;g_orbAdvLoadedFromDisk=false;
   }
   if(!OrbAdvBuildTree())
   {
      OrbAdvClearLoadedDay();
      g_orbAdvIndexIoSec+=(double)(GetTickCount64()-started)/1000.0;
      g_orbAdvLastStatus="TREE_BUILD_FAILED";
      return false;
   }
   g_orbAdvLoadedDayKey=dayKey;g_orbAdvLoadedSymbol=_Symbol;g_orbAdvLoadedServer=server;
   g_orbAdvIndexIoSec+=(double)(GetTickCount64()-started)/1000.0;
   g_orbAdvLastStatus=g_orbAdvLoadedFromDisk?"INDEX_WARM":"INDEX_COLD";
   return true;
}

int OrbAdvFirstBlockAtOrAfter(const long fromMs)
{
   int lo=0,hi=ArraySize(g_orbAdvBlocks);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if(g_orbAdvBlocks[mid].lastMs<fromMs)lo=mid+1;else hi=mid;
   }
   return lo;
}

int OrbAdvAfterLastBlockAtOrBefore(const long toMs)
{
   int lo=0,hi=ArraySize(g_orbAdvBlocks);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;
      if(g_orbAdvBlocks[mid].firstMs<=toMs)lo=mid+1;else hi=mid;
   }
   return lo;
}

bool OrbAdvNodeCanSkip(const OrbAdvTreeNode &node,const bool isBuy,
                       const double entry,const double risk,const double effSl,
                       const double &tps[],const int maxTp,const bool fixedTarget,
                       const double targetPrice,const datetime fillTime,
                       const datetime tradeEnd,const bool scheduledEndReached,
                       const datetime brokerExitAt,const datetime forcedExitTime)
{
   if(node.validQuotes<=0)return true;
   datetime lastTime=(datetime)(node.lastMs/1000);
   if(forcedExitTime>fillTime&&lastTime>=forcedExitTime)return false;
   if(scheduledEndReached&&(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)
      &&lastTime>=tradeEnd)return false;
   if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&lastTime>=brokerExitAt)return false;
   double minClose=isBuy?node.minBid:node.minAsk;
   double maxClose=isBuy?node.maxBid:node.maxAsk;
   if(isBuy?(minClose<=effSl):(maxClose>=effSl))return false;
   int firstUnseen=MathMax(0,maxTp);
   for(int k=firstUnseen;k<6;k++)
      if(isBuy?(maxClose>=tps[k]):(minClose<=tps[k]))return false;
   if(fixedTarget&&(isBuy?(maxClose>=targetPrice):(minClose<=targetPrice)))return false;
   if(g_rtTimeExit&&InpTimeExitMinutes>0&&lastTime>=fillTime+InpTimeExitMinutes*60)
   {
      double threshold=isBuy?(entry+InpTimeExitMinProgress*risk):(entry-InpTimeExitMinProgress*risk);
      if(isBuy?(minClose<threshold):(maxClose>threshold))return false;
   }
   return true;
}

int OrbAdvFindCandidateNode(const int node,const int queryLeft,const int queryRight,
                            const bool isBuy,const double entry,const double risk,const double effSl,
                            const double &tps[],const int maxTp,const bool fixedTarget,
                            const double targetPrice,const datetime fillTime,const datetime tradeEnd,
                            const bool scheduledEndReached,const datetime brokerExitAt,const datetime forcedExitTime)
{
   OrbAdvTreeNode current=g_orbAdvTree[node];
   if(current.rightBlock<queryLeft||current.leftBlock>queryRight)return -1;
   if(queryLeft<=current.leftBlock&&current.rightBlock<=queryRight
      &&OrbAdvNodeCanSkip(current,isBuy,entry,risk,effSl,tps,maxTp,fixedTarget,targetPrice,
                           fillTime,tradeEnd,scheduledEndReached,brokerExitAt,forcedExitTime))
   {g_orbAdvTreeNodesSkipped+=(long)(current.rightBlock-current.leftBlock+1);return -1;}
   if(current.leftBlock==current.rightBlock)return current.leftBlock;
   int found=OrbAdvFindCandidateNode(node*2,queryLeft,queryRight,isBuy,entry,risk,effSl,tps,maxTp,
      fixedTarget,targetPrice,fillTime,tradeEnd,scheduledEndReached,brokerExitAt,forcedExitTime);
   if(found>=0)return found;
   return OrbAdvFindCandidateNode(node*2+1,queryLeft,queryRight,isBuy,entry,risk,effSl,tps,maxTp,
      fixedTarget,targetPrice,fillTime,tradeEnd,scheduledEndReached,brokerExitAt,forcedExitTime);
}

int OrbAdvFindCandidateBlock(const long fromMs,const long toMs,const bool isBuy,
                             const double entry,const double risk,const double effSl,
                             const double &tps[],const int maxTp,const bool fixedTarget,
                             const double targetPrice,const datetime fillTime,const datetime tradeEnd,
                             const bool scheduledEndReached,const datetime brokerExitAt,const datetime forcedExitTime)
{
   int first=OrbAdvFirstBlockAtOrAfter(fromMs);
   int after=OrbAdvAfterLastBlockAtOrBefore(toMs);
   if(first>=after)return -1;
   g_orbAdvTreeQueries++;
   return OrbAdvFindCandidateNode(1,first,after-1,isBuy,entry,risk,effSl,tps,maxTp,fixedTarget,
      targetPrice,fillTime,tradeEnd,scheduledEndReached,brokerExitAt,forcedExitTime);
}

bool OrbAdvFindFirstQuote(const long fromMs,const long toMs,MqlTick &firstTick)
{
   long cursor=fromMs;
   while(cursor<=toMs)
   {
      datetime dayStart=OrbAdvDayStart((datetime)(cursor/1000));
      long dayTo=MathMin(toMs,(long)(dayStart+86400)*1000-1);
      if(!OrbAdvLoadDay(dayStart))return false;
      int first=OrbAdvFirstBlockAtOrAfter(cursor);
      int after=OrbAdvAfterLastBlockAtOrBefore(dayTo);
      if(first<after)
      {
         OrbAdvMinuteBlock block=g_orbAdvBlocks[first];
         MqlTick ticks[];
         long blockFrom=MathMax(cursor,block.minuteMs);
         long blockTo=MathMin(dayTo,block.minuteMs+ORB_ADV_MINUTE_MS-1);
         int copied=AuditCopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)blockFrom,(ulong)blockTo);
         for(int i=0;i<copied;i++)
         {
            if(ticks[i].time_msc<blockFrom||ticks[i].time_msc>blockTo)continue;
            if(ticks[i].bid>0.0&&ticks[i].ask>0.0){firstTick=ticks[i];return true;}
         }
      }
      cursor=dayTo+1;
   }
   return false;
}

void OrbAdvFinalizeResult(HistResult &res,const bool isBuy,const double entry,const double risk,
                          const bool fixedTarget,const double targetR,const int targetLeg,const int hcLeg)
{
   if(InpExecutionMode==ORB_EXEC_PARTIAL_3LEG)
   {
      bool marketExit=IsSimMarketExitOutcome(res.outcome);
      double runnerR=marketExit?SimSignedR(isBuy,entry,res.exitPrice,risk):0.0;
      double leg1=res.maxTp>=1?LegR(1):(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0));
      double leg2=res.maxTp>=2?LegR(2):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      double leg3=res.maxTp>=3?LegR(3):(res.maxTp>=1&&hcLeg>0?0:(res.outcome=="SL"?-1.0:(marketExit?runnerR:0.0)));
      if(res.outcome=="SL"&&res.maxTp==0){leg1=-1;leg2=-1;leg3=-1;}
      res.netR=(leg1+leg2+leg3)/3.0;
   }
   else
   {
      bool targetOutcome=(g_rtTargetMode==ORB_TARGET_R_LEG&&res.outcome==TargetOutcomeLabel(targetLeg))
         ||(g_rtTargetMode!=ORB_TARGET_R_LEG&&res.outcome=="TARGET");
      if(fixedTarget&&targetOutcome)
         res.netR=hcLeg>0?0.5*LegR(hcLeg)+0.5*targetR:targetR;
      else if(IsSimMarketExitOutcome(res.outcome))
      {
         double runnerR=SimSignedR(isBuy,entry,res.exitPrice,risk);
         res.netR=(hcLeg>0&&res.maxTp>=hcLeg)?0.5*LegR(hcLeg)+0.5*runnerR:runnerR;
      }
      else if((res.outcome=="BE"||res.outcome=="open"||res.outcome=="TP"+IntegerToString(res.maxTp))
         &&hcLeg>0&&res.maxTp>=hcLeg)res.netR=0.5*LegR(hcLeg);
      else if(res.outcome=="SL")res.netR=-1.0;
   }
   res.costR=BtCostR(risk,false,false);
   res.netR-=res.costR;
   res.isWin=res.netR>0.0;
}

bool SimulateTradeTicksAdvanced(datetime sigTime,datetime tradeEnd,double entry,double sl,bool isBuy,
                                int halfBeLeg,bool scheduledEndReached,HistResult &res,
                                datetime forcedExitTime=0,string forcedExitOutcome="")
{
   if(!g_rtAdvancedAuditEngine||!InpBacktestUseTickReplay||!g_btNativeParity)return false;
   if(g_rtExitMode!=ORB_EXIT_FIXED_TARGET&&g_rtExitMode!=ORB_EXIT_EOD_ONLY&&g_rtExitMode!=ORB_EXIT_BROKER_TIME)return false;
   ENUM_TIMEFRAMES entryTf=RuntimeEntryTf();
   datetime startTime=BarCloseTime(entryTf,sigTime);
   if(g_btFillMode==BT_FILL_NEXT_BAR_OPEN)
   {
      int sec=PeriodSeconds(entryTf);if(sec<=0)sec=60;
      startTime=sigTime+sec;
   }
   else if(g_btFillMode==BT_FILL_CONSERVATIVE)startTime=BarCloseTime(entryTf,sigTime);
   if(tradeEnd<=startTime)return false;
   long fromMs=(long)startTime*1000,toMs=(long)tradeEnd*1000;
   if(g_histTickCoverageKnown&&(ulong)fromMs<g_histTickFirstAvailableMs)return false;

   MqlTick firstTick;ZeroMemory(firstTick);
   if(!OrbAdvFindFirstQuote(fromMs,toMs,firstTick))return false;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);if(point<=0.0)point=0.00001;
   double slip=MathMax(0.0,g_btSlippagePts)*point;
   entry=NormalizeTradePrice(isBuy?(firstTick.ask+slip):(firstTick.bid-slip));
   bool sourceIsBuy=g_rtInvertMode?!isBuy:isBuy;
   double sourceReferenceEntry=NormalizeTradePrice(sourceIsBuy?(firstTick.ask+slip):(firstTick.bid-slip));
   double risk=0.0,tp1=0,tp2=0,tp3=0,tp4=0,tp5=0,tp6=0;
   if(!BuildSimGeometry(isBuy,entry,sl,sl,risk,tp1,tp2,tp3,tp4,tp5,tp6,sourceReferenceEntry))return false;
   double targetPrice=0.0,targetR=0.0;string targetDetail="";
   if(!ResolveTargetPriceAndR(isBuy,entry,risk,targetPrice,targetR,targetDetail,sourceReferenceEntry))return false;
   int targetLeg=RuntimeTargetLeg();
   int hcLeg=ClampHalfBeLeg(halfBeLeg,targetLeg);
   bool fixedTarget=ExitModeUsesFixedTp(g_rtExitMode)&&targetPrice>0.0;
   bool beApplied=false;
   double effSl=sl;
   datetime fillTime=(datetime)firstTick.time;
   datetime brokerExitAt=(g_rtExitMode==ORB_EXIT_BROKER_TIME?BrokerTimeExitFor(fillTime):0);
   res.targetLeg=targetLeg;res.hcLeg=hcLeg;res.valid=true;res.invalidReason="";
   res.simEntry=entry;res.simSl=sl;res.simTarget=fixedTarget?targetPrice:0.0;
   double tps[6];tps[0]=tp1;tps[1]=tp2;tps[2]=tp3;tps[3]=tp4;tps[4]=tp5;tps[5]=tp6;

   long cursor=MathMax(fromMs,(long)firstTick.time_msc);
   while(cursor<=toMs&&res.outcome=="open")
   {
      datetime dayStart=OrbAdvDayStart((datetime)(cursor/1000));
      long dayTo=MathMin(toMs,(long)(dayStart+86400)*1000-1);
      if(!OrbAdvLoadDay(dayStart))return false;
      int candidate=OrbAdvFindCandidateBlock(cursor,dayTo,isBuy,entry,risk,effSl,tps,res.maxTp,
         fixedTarget,targetPrice,fillTime,tradeEnd,scheduledEndReached,brokerExitAt,forcedExitTime);
      if(candidate<0){cursor=dayTo+1;continue;}
      OrbAdvMinuteBlock block=g_orbAdvBlocks[candidate];
      long exactFrom=MathMax(cursor,block.minuteMs);
      long exactTo=MathMin(dayTo,block.minuteMs+ORB_ADV_MINUTE_MS-1);
      MqlTick ticks[];
      int copied=AuditCopyTicksRange(_Symbol,ticks,COPY_TICKS_INFO,(ulong)exactFrom,(ulong)exactTo);
      if(copied<=0)return false;
      g_orbAdvExactMinutes++;
      for(int i=0;i<copied;i++)
      {
         MqlTick tick=ticks[i];
         if(tick.time_msc<exactFrom||tick.time_msc>exactTo||tick.bid<=0.0||tick.ask<=0.0)continue;
         g_orbAdvExactTicks++;
         double closePx=isBuy?tick.bid:tick.ask;
         datetime tickTime=(datetime)tick.time;
         if(forcedExitTime>fillTime&&tickTime>=forcedExitTime)
         {
            bool forcedSlHit=isBuy?(closePx<=effSl):(closePx>=effSl);
            bool forcedTargetHit=fixedTarget&&(isBuy?(closePx>=targetPrice):(closePx<=targetPrice));
            if(forcedSlHit){res.outcome=beApplied?"BE":"SL";res.exitPrice=effSl;}
            else if(forcedTargetHit){res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");res.exitPrice=targetPrice;}
            else
            {
               int hitLeg=0;
               for(int k=0;k<6;k++)if(isBuy?(closePx>=tps[k]):(closePx<=tps[k]))hitLeg=k+1;
               if(hitLeg>res.maxTp)res.maxTp=hitLeg;
               if(hcLeg>0&&res.maxTp>=hcLeg&&!beApplied){effSl=entry;beApplied=true;}
               res.outcome=forcedExitOutcome!=""?forcedExitOutcome:"FILTER_REVERSE_EXIT";res.exitPrice=closePx;
            }
            res.exitTime=tickTime;break;
         }
         if(g_rtTimeExit&&InpTimeExitMinutes>0&&tickTime>=fillTime+InpTimeExitMinutes*60)
         {
            double progressR=SimSignedR(isBuy,entry,closePx,risk);
            if(progressR<InpTimeExitMinProgress){res.outcome="TIME_EXIT";res.exitPrice=closePx;res.exitTime=tickTime;break;}
         }
         if(scheduledEndReached&&(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD)&&tickTime>=tradeEnd)
         {res.outcome="EOD_EXIT";res.exitPrice=closePx;res.exitTime=tickTime;break;}
         if(g_rtExitMode==ORB_EXIT_BROKER_TIME&&brokerExitAt>0&&tickTime>=brokerExitAt)
         {res.outcome="BROKER_TIME_EXIT";res.exitPrice=closePx;res.exitTime=tickTime;break;}
         bool slHit=isBuy?(closePx<=effSl):(closePx>=effSl);
         if(slHit){res.exitPrice=effSl;res.outcome=beApplied?"BE":"SL";res.exitTime=tickTime;break;}
         int hitLeg=0;
         for(int k=0;k<6;k++)if(isBuy?(closePx>=tps[k]):(closePx<=tps[k]))hitLeg=k+1;
         if(hitLeg>res.maxTp)res.maxTp=hitLeg;
         if(hcLeg>0&&res.maxTp>=hcLeg&&!beApplied){effSl=entry;beApplied=true;}
         bool targetHit=fixedTarget&&(isBuy?(closePx>=targetPrice):(closePx<=targetPrice));
         if(targetHit)
         {res.outcome=(g_rtTargetMode==ORB_TARGET_R_LEG?TargetOutcomeLabel(targetLeg):"TARGET");res.exitPrice=targetPrice;res.exitTime=tickTime;break;}
      }
      cursor=exactTo+1;
   }
   OrbAdvFinalizeResult(res,isBuy,entry,risk,fixedTarget,targetR,targetLeg,hcLeg);
   g_orbAdvLastStatus="ADV_EXACT";
   return true;
}

HistResult SimulateHistoricalLifecycleAdvanced(datetime entryTime,datetime sessionEnd,datetime now,
                                                double entry,double sl,bool isBuy,
                                                double tp1,double tp2,double tp3,int halfBeLeg,datetime &usedEnd,
                                                datetime forcedExitTime=0,string forcedExitOutcome="")
{
   if(!g_rtAdvancedAuditEngine)
      return SimulateHistoricalLifecycle(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,
         usedEnd,forcedExitTime,forcedExitOutcome);
   bool sessionBound=(g_rtExitMode==ORB_EXIT_EOD_ONLY||g_rtTargetMode==ORB_TARGET_EOD);
   bool brokerBound=(g_rtExitMode==ORB_EXIT_BROKER_TIME);
   int sec=PeriodSeconds(RuntimeEntryTf());if(sec<=0)sec=60;
   datetime horizon=now;
   if(sessionBound)
   {
      horizon=sessionEnd;
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   else if(brokerBound)
   {
      horizon=BrokerTimeExitFor(entryTime)+sec;
      if(horizon<entryTime+sec)horizon=entryTime+sec;
      if(horizon>now)horizon=now;
   }
   if(horizon<=entryTime)horizon=now;
   bool scheduledEndReached=(!sessionBound||now>=sessionEnd);
   HistResult advanced;
   advanced.maxTp=0;advanced.outcome="open";advanced.netR=0;advanced.isWin=false;
   advanced.simEntry=entry;advanced.simSl=sl;advanced.simTarget=0;advanced.costR=0;
   advanced.exitMode=RuntimeExitLabel();advanced.exitPrice=0;advanced.exitTime=0;
   advanced.valid=false;advanced.invalidReason="NO_MARKET_DATA";
   advanced.targetLeg=RuntimeTargetLeg();advanced.hcLeg=ClampHalfBeLeg(halfBeLeg,advanced.targetLeg);
   ulong tickReadFailures=g_auditTickReadFailures;
   if(!SimulateTradeTicksAdvanced(entryTime,horizon,entry,sl,isBuy,halfBeLeg,scheduledEndReached,
                                  advanced,forcedExitTime,forcedExitOutcome))
   {
      if(g_auditTickReadFailures!=tickReadFailures){advanced.valid=false;advanced.invalidReason="TICK_HISTORY_PENDING";advanced.netR=0;advanced.isWin=false;usedEnd=horizon;return advanced;}
      return SimulateHistoricalLifecycle(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,usedEnd,forcedExitTime,forcedExitOutcome);
   }
   usedEnd=horizon;
   if(!InpAdvancedAuditShadowParity)return advanced;
   datetime legacyEnd=sessionEnd;
   HistResult legacy=SimulateHistoricalLifecycle(entryTime,sessionEnd,now,entry,sl,isBuy,tp1,tp2,tp3,halfBeLeg,
      legacyEnd,forcedExitTime,forcedExitOutcome);
   g_orbAdvParityChecks++;
   string parityDetail="";
   if(!OrbAdvancedAuditEquivalent(advanced,legacy,parityDetail))
   {
      g_orbAdvParityMismatches++;
      usedEnd=legacyEnd;
      Print("ORB15v3 ADV LIFECYCLE PARITY MISMATCH; legacy selected | ",parityDetail);
      return legacy;
   }
   return advanced;
}

string OrbAdvancedAuditLabel()
{
   return g_rtAdvancedAuditEngine?"ADV AUD":"LEGACY AUD";
}

bool OrbAdvancedAuditEquivalent(const HistResult &advanced,const HistResult &legacy,string &detail)
{
   detail="";
   double priceTolerance=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),SymbolInfoDouble(_Symbol,SYMBOL_POINT));
   if(priceTolerance<=0.0)priceTolerance=0.00000001;
   bool same=(advanced.valid==legacy.valid&&advanced.outcome==legacy.outcome
      &&advanced.exitTime==legacy.exitTime&&advanced.maxTp==legacy.maxTp
      &&MathAbs(advanced.exitPrice-legacy.exitPrice)<=priceTolerance*0.25
      &&MathAbs(advanced.simEntry-legacy.simEntry)<=priceTolerance*0.25
      &&MathAbs(advanced.netR-legacy.netR)<=0.0000001);
   if(!same)
      detail="adv="+advanced.outcome+"@"+IntegerToString((int)advanced.exitTime)+"/"+DoubleToString(advanced.exitPrice,_Digits)
         +"/"+DoubleToString(advanced.netR,8)+" legacy="+legacy.outcome+"@"+IntegerToString((int)legacy.exitTime)
         +"/"+DoubleToString(legacy.exitPrice,_Digits)+"/"+DoubleToString(legacy.netR,8);
   return same;
}

string OrbAdvancedAuditRuntimeKey()
{
   return "ORB_ADV_AUD."+StringFormat("%I64d",AccountInfoInteger(ACCOUNT_LOGIN))+"."
      +StringFormat("%I64d",ChartID())+"."+(InpAdvancedAuditEngineDefault?"1":"0");
}

void OrbAdvancedAuditLoadRuntime()
{
   g_rtAdvancedAuditEngine=InpAdvancedAuditEngineDefault;
   string key=OrbAdvancedAuditRuntimeKey();
   if(GlobalVariableCheck(key))g_rtAdvancedAuditEngine=(GlobalVariableGet(key)>0.5);
}

bool OrbAdvancedAuditSetRuntime(const bool enabled)
{
   string key=OrbAdvancedAuditRuntimeKey();
   if(!GlobalVariableSet(key,enabled?1.0:0.0))return false;
   g_rtAdvancedAuditEngine=enabled;
   OrbAdvClearDayCache();
   OrbAdvClearLoadedDay();
   return true;
}

void OrbAdvancedAuditResetRunStats()
{
   OrbAdvClearDayCache();
   // Completed shards are reloaded from disk. The active trading day is
   // intentionally rebuilt against the immutable audit snapshot timestamp.
   OrbAdvClearLoadedDay();
   g_orbAdvIndexDiskHits=0;g_orbAdvIndexColdBuilds=0;g_orbAdvIndexInvalid=0;
   g_orbAdvTreeQueries=0;g_orbAdvTreeNodesSkipped=0;g_orbAdvExactMinutes=0;g_orbAdvExactTicks=0;
   g_orbAdvParityChecks=0;g_orbAdvParityMismatches=0;
   g_orbAdvIndexIoSec=0.0;g_orbAdvLastStatus=g_rtAdvancedAuditEngine?"READY":"LEGACY";
}

#endif
