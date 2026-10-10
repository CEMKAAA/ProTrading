// Closed-bar-only signal kernels ported from MaCrossOver.pine and Crossover2.pine.
// This file intentionally has no execution, audit, or bridge side effects.
#ifndef MACROSS_SIGNAL_CORE_MQH
#define MACROSS_SIGNAL_CORE_MQH

enum MA_CROSS_SIGNAL_MODE
{
   MA_CROSS_ORIGINAL_MTF = 0,
   MA_CROSS_EMA_50_200  = 1,
   MA_CROSS_TRENDLINE   = 2,
   MA_CROSS_PIVOT_ST    = 3,
   MA_CROSS_SCALP_PULLBACK = 4,
   MA_CROSS_TRENDER_IQ = 5,
   MA_CROSS_LAB_RULES = 6
};

// Mirrors MaCrossOver.pine's Cross Mode input. It applies only to MA MTF;
// the four Crossover2 kernels have their own fixed definitions.
enum MA_CROSS_PAIR
{
   MA_CROSS_PAIR_FAST = 0,   // EMA fast vs EMA medium
   MA_CROSS_PAIR_MEDIUM = 1, // EMA fast vs local HMA slow
   MA_CROSS_PAIR_SLOW = 2    // EMA medium vs local HMA slow
};

struct MaCrossSignal
{
   bool valid;
   int direction; // +1 BUY, -1 SELL
   datetime barTime;
   double price;
   double markerPrice; // Display coordinate only; never used for sizing or fills.
};

MaCrossSignal g_mcLastKernelSignal;
MA_CROSS_SIGNAL_MODE g_mcLastKernelMode=MA_CROSS_ORIGINAL_MTF;
ENUM_TIMEFRAMES g_mcLastKernelTf=PERIOD_CURRENT;

bool McCrossUp(double a,double b,double pa,double pb){return a>b&&pa<=pb;}
bool McCrossDown(double a,double b,double pa,double pb){return a<b&&pa>=pb;}
#include "MaCrossPineStream.mqh"

bool MaCrossSignalAt(const MqlRates &rates[],int at,MA_CROSS_SIGNAL_MODE mode,MA_CROSS_PAIR pair,
                     int fastLen,int mediumLen,int slowLen,const MqlRates &h4[],int &direction,int seconds=300)
{
   direction=0;if(at<0||at>=ArraySize(rates))return false;
   McPineKernel kernel;kernel.Reset(mode,pair,fastLen,mediumLen,slowLen);
   McRollingHma hma;hma.Reset(200);int h=0;double value=0;
   for(int i=0;i<=at;i++)
   {
      if(mode==MA_CROSS_ORIGINAL_MTF)McFeedHtf(h4,h,rates[i].time+seconds,hma,value);
      direction=kernel.Push(rates[i],value);
   }
   return direction!=0;
}

// SERIES_FIRSTDATE is only the currently loaded suffix and can move backwards
// during asynchronous downloads. Recursive Pine state needs a fixed origin.
datetime McHistorySeed(string symbol,ENUM_TIMEFRAMES tf)
{
   static string keys[16];static datetime servers[16],origins[16];static int next=0;
   datetime server=(datetime)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_SERVER_FIRSTDATE);
   if(server<=0)return 0;
   int seconds=PeriodSeconds(tf);if(seconds<=0)return 0;
   MqlDateTime date;TimeToStruct(server,date);
   datetime begin=(datetime)(((long)server/seconds)*seconds);
   if(tf==PERIOD_MN1){date.day=1;date.hour=0;date.min=0;date.sec=0;begin=StructToTime(date);}
   else if(tf==PERIOD_W1)
   {date.hour=0;date.min=0;date.sec=0;begin=StructToTime(date)-(datetime)(((date.day_of_week+6)%7)*86400);}
   string key=symbol+"|"+(string)tf;int slot=-1;
   datetime first=(datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE);
   for(int i=0;i<16;i++)if(keys[i]==key){slot=i;break;}
   if(slot>=0&&servers[slot]==server&&origins[slot]>0
      &&!(first>=begin&&first<origins[slot]))return origins[slot];
   // Brokers can report the first DAY at midnight even when the first actual
   // minute is later (BTCUSD starts at 10:00). Resolve that day's real first
   // bar once; do not demand nonexistent midnight candles or use today's suffix.
   datetime times[];ResetLastError();
   int copied=CopyTime(symbol,tf,begin,(datetime)(((long)server/86400+1)*86400-1),times);
   datetime terminal=(datetime)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_TERMINAL_FIRSTDATE);
   if(copied<1||GetLastError()!=0||terminal<=0||terminal>server
      ||!SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED))return 0;
   if(slot<0){slot=next;next=(next+1)%16;keys[slot]=key;}
   servers[slot]=server;origins[slot]=times[0];return origins[slot];
}

bool McHistoryReady(const string symbol,const ENUM_TIMEFRAMES tf,const datetime seed,string &detail,bool &hardBlocked)
{
   hardBlocked=false;detail="";
   datetime first=(datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE);
   if(seed>0&&first>0&&first<=seed&&SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED))return true;
   datetime times[];
   // A small request starts/rebuilds the missing prefix without allocating a
   // second full-history array or treating a partial copy as complete history.
   if(seed>0)CopyTime(symbol,tf,seed+PeriodSeconds(tf),1,times);
   else CopyTime(symbol,tf,0,1,times);
   first=(datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE);
   if(seed>0&&first>0&&first<=seed&&SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED))return true;
   hardBlocked=seed>0&&first>seed&&SeriesInfoInteger(symbol,tf,SERIES_BARS_COUNT)>=TerminalInfoInteger(TERMINAL_MAXBARS);
   detail=hardBlocked?"signal origin exceeds Max bars in chart":"signal origin history pending";
   detail+=" tf="+(string)tf+" origin="+TimeToString(seed,TIME_DATE|TIME_MINUTES)
      +" loaded="+TimeToString(first,TIME_DATE|TIME_MINUTES);
   return false;
}

bool MaCrossComputeSignal(const string symbol,const ENUM_TIMEFRAMES tf,const MA_CROSS_SIGNAL_MODE mode,
                          const MA_CROSS_PAIR pair,const int fastLen,const int mediumLen,const int slowLen,MaCrossSignal &out)
{
   static McPineKernel kernel;static McRollingHma hma;
   static string owner="";static datetime last=0,seed=0,hSeed=0,hLast=0;
   static double hv=0;static MaCrossSignal saved;
   out.valid=false;out.direction=0;out.barTime=0;out.price=0;out.markerPrice=0;
   datetime closed=iTime(symbol,tf,1),first=McHistorySeed(symbol,tf);
   datetime hf=mode==MA_CROSS_ORIGINAL_MTF?McHistorySeed(symbol,PERIOD_H4):0;
   string key=LabEngineIdentity()+symbol+"|"+(string)tf+"|"+(string)mode+"|"+(string)pair+"|"+(string)fastLen+"|"+(string)mediumLen+"|"+(string)slowLen;
   string historyDetail="";bool historyBlocked=false;
   if(!McHistoryReady(symbol,tf,first,historyDetail,historyBlocked))return false;
   if(mode==MA_CROSS_ORIGINAL_MTF&&!McHistoryReady(symbol,PERIOD_H4,hf,historyDetail,historyBlocked))return false;
   if(closed<=0||first<=0||!SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED))return false;
   if(mode==MA_CROSS_ORIGINAL_MTF&&(hf<=0||!SeriesInfoInteger(symbol,PERIOD_H4,SERIES_SYNCHRONIZED)))return false;
   bool reset=key!=owner||first!=seed||hf!=hSeed||closed<last;
   if(!reset&&closed==last){out=saved;return out.valid;}
   MqlRates rates[],higher[];ArraySetAsSeries(rates,false);ArraySetAsSeries(higher,false);
   datetime start=reset?first:last+1;
   int n=CopyRates(symbol,tf,start,closed,rates);
   if(n<1||rates[n-1].time!=closed||(reset&&rates[0].time!=first))return false;
   if(mode==MA_CROSS_ORIGINAL_MTF)
   {
      datetime end=closed+PeriodSeconds(tf)-PeriodSeconds(PERIOD_H4),hs=reset?hf:hLast+1;
      if(end>=hs)
      {
         int hc=CopyRates(symbol,PERIOD_H4,hs,end,higher);
         if(hc<0||(reset&&(hc<1||higher[0].time!=hf)))return false;
      }
   }
   if(reset){kernel.Reset(mode,pair,fastLen,mediumLen,slowLen);hma.Reset(200);hv=0;hLast=0;}
   int h=0,dir=0;
   for(int i=0;i<n;i++)
   {
      if(mode==MA_CROSS_ORIGINAL_MTF)McFeedHtf(higher,h,rates[i].time+PeriodSeconds(tf),hma,hv);
      dir=kernel.Push(rates[i],hv);
   }
   if(first!=McHistorySeed(symbol,tf)||(mode==MA_CROSS_ORIGINAL_MTF&&hf!=McHistorySeed(symbol,PERIOD_H4)))
   {owner="";last=0;return false;}
   if(h>0)hLast=higher[h-1].time;
   owner=key;last=closed;seed=first;hSeed=hf;
   saved.valid=dir!=0;saved.direction=dir;saved.barTime=closed;saved.price=rates[n-1].close;saved.markerPrice=kernel.MarkerPrice();
   g_mcLastKernelSignal=saved;
   g_mcLastKernelMode=mode;g_mcLastKernelTf=tf;
   out=saved;return out.valid;
}

string MaCrossSignalText(MA_CROSS_SIGNAL_MODE mode,int direction)
{
   if(mode==MA_CROSS_PIVOT_ST)return direction>0?"Close Short Order / Go to Long Now":"Close Long Order / Go to Short Now";
   return direction>0?"BUY":"SELL";
}
string MaCrossModeText(const MA_CROSS_SIGNAL_MODE mode)
{
   if(mode==MA_CROSS_LAB_RULES)return (g_labPreviewOnly?"PREVIEW: ":"")+g_labEngine.name;
   if(mode==MA_CROSS_ORIGINAL_MTF)return "MA MTF";
   if(mode==MA_CROSS_EMA_50_200)return "EMA 50/200";
   if(mode==MA_CROSS_TRENDLINE)return "Trendline";
   if(mode==MA_CROSS_PIVOT_ST)return "Close/Reverse";
   if(mode==MA_CROSS_TRENDER_IQ)return "Trender IQ";
   return "Scalp arrows";
}

string MaCrossPairText(const MA_CROSS_PAIR pair)
{
   if(pair==MA_CROSS_PAIR_MEDIUM)return "MED";
   if(pair==MA_CROSS_PAIR_SLOW)return "SLOW";
   return "FAST";
}
#endif
