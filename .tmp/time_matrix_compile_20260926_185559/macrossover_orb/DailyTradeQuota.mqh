#ifndef DAILY_TRADE_QUOTA_MQH
#define DAILY_TRADE_QUOTA_MQH
input group "Daily Closed Trade Limits (Broker 00:00)"
input int InpDailyMaxLosses=0; // 0 disables the limit.
input int InpDailyTargetWins=0;
int g_dailyMaxLosses=0,g_dailyTargetWins=0;
int g_dailyAuditWins=0,g_dailyAuditLosses=0;
datetime g_dailyAuditDay=0,g_dailyAuditLastEntry=0;
bool g_dailyAuditValid=true;
struct DailyQuotaExit { datetime at; int verdict; };
DailyQuotaExit g_dailyQuotaHeap[];
string g_dailyLossDraft="0",g_dailyWinDraft="0";
string g_dailyUiPrefix="";
bool DailyQuotaValidNumber(double value)
{return MathIsValidNumber(value)&&value>=0&&value<=100000&&value==MathFloor(value);}
bool DailyQuotaParse(string text,int &value)
{
   StringTrimLeft(text);StringTrimRight(text);
   if(StringLen(text)==0||StringLen(text)>6)return false;
   for(int i=0;i<StringLen(text);i++)if(StringGetCharacter(text,i)<'0'||StringGetCharacter(text,i)>'9')return false;
   value=(int)StringToInteger(text);return value<=100000;
}
void DailyQuotaDraftReset()
{
   g_dailyLossDraft=(string)g_dailyMaxLosses;g_dailyWinDraft=(string)g_dailyTargetWins;
   if(g_dailyUiPrefix!="")
   {
      if(ObjectFind(0,g_dailyUiPrefix+"DAILY_LOSS")>=0)ObjectSetString(0,g_dailyUiPrefix+"DAILY_LOSS",OBJPROP_TEXT,g_dailyLossDraft);
      if(ObjectFind(0,g_dailyUiPrefix+"DAILY_WIN")>=0)ObjectSetString(0,g_dailyUiPrefix+"DAILY_WIN",OBJPROP_TEXT,g_dailyWinDraft);
   }
}
bool DailyQuotaReadStrategy(string text,int &loss,int &win)
{
   loss=0;win=0;string fields[];
   int count=StringSplit(StringSubstr(text,6),',',fields);
   if(count==8||count==9)return true;
   return count==11&&DailyQuotaParse(fields[9],loss)&&DailyQuotaParse(fields[10],win);
}
datetime DailyQuotaDay(datetime at)
{
   MqlDateTime d;TimeToStruct(at,d);d.hour=0;d.min=0;d.sec=0;
   return StructToTime(d);
}
bool DailyQuotaEnabled(){return g_dailyMaxLosses>0||g_dailyTargetWins>0;}
bool DailyQuotaHit(int wins,int losses)
{return (g_dailyMaxLosses>0&&losses>=g_dailyMaxLosses)||(g_dailyTargetWins>0&&wins>=g_dailyTargetWins);}
void DailyQuotaAuditReset()
{
   ArrayFree(g_dailyQuotaHeap);g_dailyAuditDay=0;g_dailyAuditLastEntry=0;
   g_dailyAuditWins=0;g_dailyAuditLosses=0;g_dailyAuditValid=true;
}
void DailyQuotaSchedule(datetime at,int verdict)
{
   if(!DailyQuotaEnabled()||verdict==0)return;
   if(at<=0){g_dailyAuditValid=false;return;}
   int i=ArraySize(g_dailyQuotaHeap);
   if(ArrayResize(g_dailyQuotaHeap,i+1,256)<0){g_dailyAuditValid=false;return;}
   DailyQuotaExit value;value.at=at;value.verdict=verdict;
   while(i>0)
   {
      int parent=(i-1)/2;
      if(g_dailyQuotaHeap[parent].at<=at)break;
      g_dailyQuotaHeap[i]=g_dailyQuotaHeap[parent];i=parent;
   }
   g_dailyQuotaHeap[i]=value;
}
DailyQuotaExit DailyQuotaPop()
{
   DailyQuotaExit value=g_dailyQuotaHeap[0];
   int count=ArraySize(g_dailyQuotaHeap)-1;
   DailyQuotaExit last=g_dailyQuotaHeap[count];ArrayResize(g_dailyQuotaHeap,count);
   int i=0;
   while(i*2+1<count)
   {
      int child=i*2+1;
      if(child+1<count&&g_dailyQuotaHeap[child+1].at<g_dailyQuotaHeap[child].at)child++;
      if(last.at<=g_dailyQuotaHeap[child].at)break;
      g_dailyQuotaHeap[i]=g_dailyQuotaHeap[child];i=child;
   }
   if(count>0)g_dailyQuotaHeap[i]=last;
   return value;
}
bool DailyQuotaAuditAllows(datetime enteredAt)
{
   if(!DailyQuotaEnabled())return true;
   if(enteredAt<=0||enteredAt<g_dailyAuditLastEntry){g_dailyAuditValid=false;return false;}
   g_dailyAuditLastEntry=enteredAt;
   datetime day=DailyQuotaDay(enteredAt);
   if(day!=g_dailyAuditDay){g_dailyAuditDay=day;g_dailyAuditWins=0;g_dailyAuditLosses=0;}
   while(ArraySize(g_dailyQuotaHeap)>0&&g_dailyQuotaHeap[0].at<=enteredAt)
   {
      DailyQuotaExit ended=DailyQuotaPop();
      if(DailyQuotaDay(ended.at)!=day)continue;
      if(ended.verdict>0)g_dailyAuditWins++;else g_dailyAuditLosses++;
   }
   return g_dailyAuditValid&&!DailyQuotaHit(g_dailyAuditWins,g_dailyAuditLosses);
}
// Rebuild from fully closed native positions so restart and partial fills do not
// reset/double-count the quota. Remote listener accounts are not observable here.
bool DailyQuotaLiveAllows(long magic,datetime now,int &wins,int &losses)
{
   wins=0;losses=0;
   if(!DailyQuotaEnabled())return true;
   datetime day=DailyQuotaDay(now);
   if(!HistorySelect(day,now))return false;
   ulong ids[];
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0||HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol)continue;
      long type=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(type!=DEAL_ENTRY_OUT&&type!=DEAL_ENTRY_OUT_BY&&type!=DEAL_ENTRY_INOUT)continue;
      int n=ArraySize(ids);ArrayResize(ids,n+1,128);
      ids[n]=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
   }
   ArraySort(ids);
   for(int i=0;i<ArraySize(ids);i++)
   {
      if(ids[i]==0||(i>0&&ids[i]==ids[i-1]))continue;
      bool open=false;
      for(int p=0;p<PositionsTotal();p++)
         if(PositionGetTicket(p)>0&&(ulong)PositionGetInteger(POSITION_IDENTIFIER)==ids[i]){open=true;break;}
      if(open)continue;
      if(!HistorySelectByPosition(ids[i]))return false;
      bool own=false,foreign=false;double net=0;datetime closedAt=0;
      for(int d=0;d<HistoryDealsTotal();d++)
      {
         ulong deal=HistoryDealGetTicket(d);if(deal==0)continue;
         long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_IN||entry==DEAL_ENTRY_INOUT)
         {
            if(HistoryDealGetInteger(deal,DEAL_MAGIC)==magic)own=true;else foreign=true;
         }
         net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)
            +HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
         if(entry==DEAL_ENTRY_OUT||entry==DEAL_ENTRY_OUT_BY||entry==DEAL_ENTRY_INOUT)
         {
            datetime stamp=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
            if(stamp>closedAt)closedAt=stamp;
         }
      }
      if(!own)continue;
      if(foreign)return false; // Netting mixed ownership cannot be attributed safely.
      if(DailyQuotaDay(closedAt)!=day)continue;
      if(net>1e-8)wins++;else if(net<-1e-8)losses++;
   }
   return !DailyQuotaHit(wins,losses);
}
#endif
