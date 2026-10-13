#ifndef LIQ_AUDIT_QUOTE_CACHE_MQH
#define LIQ_AUDIT_QUOTE_CACHE_MQH

// A per-audit cache of exact quotes, not an alternative execution model.
// Extrema only skip blocks that cannot change the existing replay state.
#define LN_QUOTE_SLOTS 16
#define LN_QUOTE_BLOCK 64
#define LN_QUOTE_BUDGET 67108864
#define LN_QUOTE_PAGE_MS 21600000
#define LN_QUOTE_SUMMARY_HOURS 32768
struct LnQuoteBlock
{
   double minBid,maxBid,minAsk,maxAsk;
   int lastValid;
};
struct LnQuotePage
{
   ulong from,to,touched;
   bool ready;
   MqlTick ticks[];
   LnQuoteBlock blocks[];
};
LnQuotePage g_lnQuotePages[LN_QUOTE_SLOTS];
MqlTick g_lnQuoteTicks[];
LnQuoteBlock g_lnQuoteBlocks[];
ulong g_lnQuoteFrom=0,g_lnQuoteTo=0,g_lnQuoteClock=0;
bool g_lnQuoteReady=false;
long g_lnQuoteHits=0,g_lnQuoteReads=0,g_lnQuoteSkipped=0;
bool g_lnQuoteAcceleration=true; // Reference replay switch for differential tests.
struct LnQuoteMinute
{
   double minBid,maxBid,minAsk,maxAsk,lastBid,lastAsk;
   datetime lastTime;
   long lastMs;
};
struct LnQuoteHourIndex {ulong hour;LnQuoteMinute minutes[];};
LnQuoteHourIndex g_lnQuoteHours[];
int g_lnQuoteHourSlots[131072];
string g_lnQuoteContext="";
datetime g_lnQuoteHistoryStart=0;
long g_lnQuoteHistoryLast=0,g_lnQuoteHistoryBars=0,g_lnQuoteHistorySynced=0;

bool LnQuoteHistoryChanged(string context,long first,long last,long bars,long synced)
{
   long appended=MathMax(0,(last-g_lnQuoteHistoryLast)/60);
   bool changed=context!=g_lnQuoteContext||first!=g_lnQuoteHistoryStart
      ||synced!=g_lnQuoteHistorySynced||last<g_lnQuoteHistoryLast
      ||bars<g_lnQuoteHistoryBars||bars-g_lnQuoteHistoryBars>appended;
   g_lnQuoteContext=context;g_lnQuoteHistoryStart=(datetime)first;
   g_lnQuoteHistoryLast=last;g_lnQuoteHistoryBars=bars;g_lnQuoteHistorySynced=synced;
   return changed;
}

int LnQuoteHourSlot(ulong hour)
{
   uint hash=(uint)(hour/3600000)*2654435761;
   int slot=(int)(hash&131071);
   for(int probe=0;probe<131072;probe++,slot=(slot+1)&131071)
   {
      int id=g_lnQuoteHourSlots[slot]-1;
      if(id<0||g_lnQuoteHours[id].hour==hour)return slot;
   }
   return -1;
}
void LnQuoteRememberHour()
{
   if(!g_lnQuoteReady||g_lnQuoteFrom%3600000!=0||g_lnQuoteTo%3600000!=3599999)return;
   int first=0,count=ArraySize(g_lnQuoteTicks);
   for(ulong hour=g_lnQuoteFrom;hour<=g_lnQuoteTo;hour+=3600000)
   {
      int after=first;
      while(after<count&&(ulong)g_lnQuoteTicks[after].time_msc<hour+3600000)after++;
      int slot=LnQuoteHourSlot(hour);
      if(slot<0||g_lnQuoteHourSlots[slot]>0||ArraySize(g_lnQuoteHours)>=LN_QUOTE_SUMMARY_HOURS)
      {first=after;continue;}
      int id=ArraySize(g_lnQuoteHours);
      if(ArrayResize(g_lnQuoteHours,id+1,256)!=id+1)return;
      g_lnQuoteHours[id].hour=hour;
      if(ArrayResize(g_lnQuoteHours[id].minutes,60)!=60)
      {ArrayResize(g_lnQuoteHours,id);return;}
      for(int m=0;m<60;m++)
      {
         LnQuoteMinute b;ZeroMemory(b);b.minBid=DBL_MAX;b.minAsk=DBL_MAX;
         g_lnQuoteHours[id].minutes[m]=b;
      }
      for(int k=first;k<after;k++)
      {
         MqlTick t=g_lnQuoteTicks[k];if(t.bid<=0||t.ask<=0)continue;
         int minute=(int)(((ulong)t.time_msc-hour)/60000);
         if(minute<0||minute>=60)continue;
         LnQuoteMinute b=g_lnQuoteHours[id].minutes[minute];
         b.minBid=MathMin(b.minBid,t.bid);b.maxBid=MathMax(b.maxBid,t.bid);
         b.minAsk=MathMin(b.minAsk,t.ask);b.maxAsk=MathMax(b.maxAsk,t.ask);
         b.lastBid=t.bid;b.lastAsk=t.ask;b.lastTime=t.time;b.lastMs=t.time_msc;
         g_lnQuoteHours[id].minutes[minute]=b;
      }
      g_lnQuoteHourSlots[slot]=id+1;
      first=after;
      }
}
ulong LnQuoteSkipRange(ulong from,ulong limit,int dir,double sl,double tp,double half,bool watchHalf,bool reverse,
                      datetime &lastAt,double &lastClose)
{
   ulong cursor=from;
   while(cursor<=limit)
   {
      ulong hour=(cursor/3600000)*3600000;
      int slot=LnQuoteHourSlot(hour);if(slot<0)return cursor;
      int id=g_lnQuoteHourSlots[slot]-1;if(id<0)return cursor;
      int minute=(int)((cursor-hour)/60000);
      for(int m=minute;m<60;m++)
      {
         ulong end=hour+(ulong)(m+1)*60000-1;if(end>limit)return cursor;
         LnQuoteMinute b=g_lnQuoteHours[id].minutes[m];
         if(b.lastMs>0&&!reverse)
         {
            double low=dir>0?b.minBid:b.minAsk,high=dir>0?b.maxBid:b.maxAsk;
            if(dir>0?(low<=sl):(high>=sl))return cursor;
            if(tp>0&&(dir>0?(high>=tp):(low<=tp)))return cursor;
            if(watchHalf&&half>0&&(dir>0?(high>=half):(low<=half)))return cursor;
         }
         if(b.lastMs>0&&(ulong)b.lastMs>=cursor)
         {lastAt=b.lastTime;lastClose=dir>0?b.lastBid:b.lastAsk;}
         cursor=end+1;
      }
   }
   return cursor;
}

void LnQuoteReset(bool dataChanged=false)
{
   g_lnQuoteReady=false;ArrayFree(g_lnQuoteTicks);ArrayFree(g_lnQuoteBlocks);
   for(int i=0;i<LN_QUOTE_SLOTS;i++)
   {g_lnQuotePages[i].ready=false;ArrayFree(g_lnQuotePages[i].ticks);ArrayFree(g_lnQuotePages[i].blocks);}
   g_lnQuoteClock=0;g_lnQuoteHits=0;g_lnQuoteReads=0;g_lnQuoteSkipped=0;
   string context=AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol+"|"+(string)_Digits
      +"|"+DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),12);
   bool changed=LnQuoteHistoryChanged(context,
      SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE),
      SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_LASTBAR_DATE),
      SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_BARS_COUNT),
      SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED));
   if(dataChanged||changed)
   {ArrayFree(g_lnQuoteHours);ArrayInitialize(g_lnQuoteHourSlots,0);}
}
long LnQuoteBytes()
{
   long bytes=(long)ArraySize(g_lnQuoteTicks)*sizeof(MqlTick)+(long)ArraySize(g_lnQuoteBlocks)*sizeof(LnQuoteBlock);
   for(int i=0;i<LN_QUOTE_SLOTS;i++)
      bytes+=(long)ArraySize(g_lnQuotePages[i].ticks)*sizeof(MqlTick)+(long)ArraySize(g_lnQuotePages[i].blocks)*sizeof(LnQuoteBlock);
   return bytes;
}
void LnQuoteSaveActive(int protectedSlot)
{
   if(!g_lnQuoteReady)return;
   int slot=-1;ulong oldest=ULONG_MAX;
   for(int i=0;i<LN_QUOTE_SLOTS;i++)
   {
      if(i==protectedSlot)continue;
      if(!g_lnQuotePages[i].ready){slot=i;break;}
      if(g_lnQuotePages[i].touched<oldest){oldest=g_lnQuotePages[i].touched;slot=i;}
   }
   if(slot<0)return;
   ArrayFree(g_lnQuotePages[slot].ticks);ArrayFree(g_lnQuotePages[slot].blocks);
   ArraySwap(g_lnQuotePages[slot].ticks,g_lnQuoteTicks);ArraySwap(g_lnQuotePages[slot].blocks,g_lnQuoteBlocks);
   g_lnQuotePages[slot].from=g_lnQuoteFrom;g_lnQuotePages[slot].to=g_lnQuoteTo;
   g_lnQuotePages[slot].ready=true;g_lnQuotePages[slot].touched=++g_lnQuoteClock;
   g_lnQuoteReady=false;
}
int LnQuoteBound(ulong at,bool upper)
{
   int lo=0,hi=ArraySize(g_lnQuoteTicks);
   while(lo<hi)
   {
      int mid=lo+(hi-lo)/2;ulong stamp=(ulong)g_lnQuoteTicks[mid].time_msc;
      if(stamp<at||(upper&&stamp==at))lo=mid+1;else hi=mid;
   }
   return lo;
}
void LnQuoteBuildBlocks()
{
   int count=ArraySize(g_lnQuoteTicks),n=(count+LN_QUOTE_BLOCK-1)/LN_QUOTE_BLOCK;
   if(ArrayResize(g_lnQuoteBlocks,n)!=n){ArrayFree(g_lnQuoteBlocks);return;}
   for(int b=0;b<n;b++)
   {
      LnQuoteBlock block;block.minBid=DBL_MAX;block.minAsk=DBL_MAX;
      block.maxBid=0;block.maxAsk=0;block.lastValid=-1;
      int end=MathMin(count,(b+1)*LN_QUOTE_BLOCK);
      for(int k=b*LN_QUOTE_BLOCK;k<end;k++)
      {
         double bid=g_lnQuoteTicks[k].bid,ask=g_lnQuoteTicks[k].ask;
         if(bid<=0||ask<=0)continue;
         block.minBid=MathMin(block.minBid,bid);block.maxBid=MathMax(block.maxBid,bid);
         block.minAsk=MathMin(block.minAsk,ask);block.maxAsk=MathMax(block.maxAsk,ask);block.lastValid=k;
      }
      g_lnQuoteBlocks[b]=block;
   }
}
// Return a zero-copy view into a completed six-hour page. Current hours and read
// failures use the original requested range, never a reusable partial page.
int LnQuoteLoad(ulong from,ulong limit,int &first,int &after,ulong &end)
{
   ulong hour=(from/3600000)*3600000,hourEnd=hour+3600000-1;
   ulong page=(from/LN_QUOTE_PAGE_MS)*LN_QUOTE_PAGE_MS,pageEnd=page+LN_QUOTE_PAGE_MS-1;
   // Near the live boundary only a completed hour may become immutable proof.
   if(pageEnd>=(ulong)TimeCurrent()*1000){page=hour;pageEnd=hourEnd;}
   end=MathMin(limit,pageEnd);
   if(!g_lnQuoteReady||g_lnQuoteFrom>from||g_lnQuoteTo<end)
   {
      int hit=-1;
      for(int i=0;i<LN_QUOTE_SLOTS;i++)
         if(g_lnQuotePages[i].ready&&g_lnQuotePages[i].from<=from&&g_lnQuotePages[i].to>=end){hit=i;break;}
      LnQuoteSaveActive(hit);
      if(hit>=0)
      {
         ArraySwap(g_lnQuoteTicks,g_lnQuotePages[hit].ticks);ArraySwap(g_lnQuoteBlocks,g_lnQuotePages[hit].blocks);
         g_lnQuoteFrom=g_lnQuotePages[hit].from;g_lnQuoteTo=g_lnQuotePages[hit].to;
         g_lnQuoteReady=true;g_lnQuotePages[hit].ready=false;g_lnQuoteHits++;
      }
      else
      {
         bool complete=pageEnd<(ulong)TimeCurrent()*1000;
         ulong readFrom=complete?page:from,readTo=complete?pageEnd:end;
         ResetLastError();g_lnQuoteReads++;
         int count=CopyTicksRange(_Symbol,g_lnQuoteTicks,COPY_TICKS_ALL,readFrom,readTo);
         int error=GetLastError();
         if(error!=0||count<0)
         {
            // Preserve the reference reader's range and fallback policy.
            end=MathMin(limit,from+3600000-1);readFrom=from;readTo=end;
            ResetLastError();g_lnQuoteReads++;count=CopyTicksRange(_Symbol,g_lnQuoteTicks,COPY_TICKS_ALL,readFrom,readTo);
            if(GetLastError()!=0)count=-1;
            complete=false;
         }
         if(count<0){ArrayFree(g_lnQuoteTicks);ArrayFree(g_lnQuoteBlocks);first=0;after=0;return -1;}
         g_lnQuoteFrom=readFrom;g_lnQuoteTo=readTo;g_lnQuoteReady=complete;
         LnQuoteBuildBlocks();
         LnQuoteRememberHour();
         while(LnQuoteBytes()>LN_QUOTE_BUDGET)
         {
            int victim=-1;ulong age=ULONG_MAX;
            for(int i=0;i<LN_QUOTE_SLOTS;i++)
               if(g_lnQuotePages[i].ready&&g_lnQuotePages[i].touched<age){victim=i;age=g_lnQuotePages[i].touched;}
            if(victim<0){g_lnQuoteReady=false;break;}
            g_lnQuotePages[victim].ready=false;ArrayFree(g_lnQuotePages[victim].ticks);ArrayFree(g_lnQuotePages[victim].blocks);
         }
      }
   }
   else g_lnQuoteHits++;
   first=LnQuoteBound(from,false);after=LnQuoteBound(end,true);
   return after-first;
}
int LnQuoteSkip(int at,int after,int dir,double sl,double tp,double half,bool watchHalf,bool reverse)
{
   if(at%LN_QUOTE_BLOCK!=0)return at;
   if(at/LN_QUOTE_BLOCK>=ArraySize(g_lnQuoteBlocks))return at;
   int end=MathMin(ArraySize(g_lnQuoteTicks),at+LN_QUOTE_BLOCK);
   if(end>after)return at;
   LnQuoteBlock block=g_lnQuoteBlocks[at/LN_QUOTE_BLOCK];
   if(block.lastValid>=0&&!reverse)
   {
      double low=dir>0?block.minBid:block.minAsk,high=dir>0?block.maxBid:block.maxAsk;
      if(dir>0?(low<=sl):(high>=sl))return at;
      if(tp>0&&(dir>0?(high>=tp):(low<=tp)))return at;
      if(watchHalf&&half>0&&(dir>0?(high>=half):(low<=half)))return at;
   }
   g_lnQuoteSkipped+=end-at;return end;
}
#endif
