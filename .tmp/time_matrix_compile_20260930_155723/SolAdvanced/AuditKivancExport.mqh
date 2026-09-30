#ifndef AUDIT_KIVANC_EXPORT_MQH
#define AUDIT_KIVANC_EXPORT_MQH
#include "AuditKivancFeatures.mqh"
AkEngine g_akEngine;
long g_akQueries[][2];
string g_akRows[],g_akHead="";
int g_akQuery=0,g_akRemaining=0,g_akTotal=0,g_akBufferIndex=0;
MqlRates g_akBuffer[];
datetime g_akAnchor=0;
bool g_akPreparing=false;
string AkExportHeader()
{if(g_akHead==""){string unused=g_akEngine.Snapshot(g_akHead,0);}return g_akHead;}
void AkExportReset()
{
   g_akPreparing=false;ArrayFree(g_akQueries);ArrayFree(g_akRows);ArrayFree(g_akBuffer);
   g_akEngine.Reset();g_akQuery=0;g_akRemaining=0;g_akTotal=0;g_akBufferIndex=0;g_akAnchor=0;
}
string AkMissingRow(string status)
{
   string names[],out="";int n=StringSplit(g_akHead,',',names);
   for(int i=0;i<n;i++)AxCell(out,i==0?status:"");return out;
}
void AkExportBegin()
{
   AkExportReset();string unused=g_akEngine.Snapshot(g_akHead,0);
   int n=ArraySize(g_axTrades);ArrayResize(g_akRows,n);ArrayResize(g_akQueries,n);
   for(int i=0;i<n;i++)
   {g_akQueries[i][0]=(long)(g_axTrades[i].entryTime>0?g_axTrades[i].entryTime:g_axTrades[i].availableTime);g_akQueries[i][1]=i;g_akRows[i]=AkMissingRow("DATA_MISSING");}
   ArraySort(g_akQueries);int count=Bars(_Symbol,g_axTf);
   if(count<2||!SeriesInfoInteger(_Symbol,g_axTf,SERIES_SYNCHRONIZED))return;
   g_akAnchor=iTime(_Symbol,g_axTf,1);if(g_akAnchor<=0)return;
   g_akRemaining=count-1;g_akTotal=g_akRemaining;g_akPreparing=true;
}
// Bounded chunks keep the UI responsive. Replaying once preserves recursive state
// across trades and avoids O(trades * history). Seed provenance is exported.
void AkExportStep()
{
   ulong start=GetTickCount64();int n=ArraySize(g_akQueries),seconds=PeriodSeconds(g_axTf);
   while(g_akPreparing&&GetTickCount64()-start<12)
   {
      if(g_akQuery>=n){g_akPreparing=false;ArrayFree(g_akBuffer);break;}
      if(g_akBufferIndex>=ArraySize(g_akBuffer)&&g_akRemaining>0)
      {
         int anchorShift=iBarShift(_Symbol,g_axTf,g_akAnchor,true),take=MathMin(128,g_akRemaining);
         ArraySetAsSeries(g_akBuffer,false);
         if(anchorShift<1||CopyRates(_Symbol,g_axTf,anchorShift+g_akRemaining-take,take,g_akBuffer)!=take)
         {g_akPreparing=false;break;}
         g_akRemaining-=take;g_akBufferIndex=0;
      }
      datetime cutoff=(datetime)g_akQueries[g_akQuery][0];
      if(g_akBufferIndex<ArraySize(g_akBuffer)&&g_akBuffer[g_akBufferIndex].time+seconds<=cutoff)
      {
         g_akEngine.Push(g_akBuffer[g_akBufferIndex]);g_akEngine.UpdateEvents();g_akBufferIndex++;continue;
      }
      int row=(int)g_akQueries[g_akQuery][1];string head;
      if(g_akEngine.Count()>0)g_akRows[row]=g_akEngine.Snapshot(head,g_axTrades[row].direction);
      g_akQuery++;
   }
}
string AkExportRow(int index)
{return index>=0&&index<ArraySize(g_akRows)?g_akRows[index]:AkMissingRow("NOT_PREPARED");}
#endif
