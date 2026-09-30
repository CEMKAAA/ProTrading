#ifndef MA_HISTORICAL_VISUAL_CACHE_MQH
#define MA_HISTORICAL_VISUAL_CACHE_MQH
#include "AuditMemoIndex.mqh"

// This caches drawing commands, not outcomes or window admission decisions.
// The complete drawing payload is the key; differing results get new objects.
struct MaHistoricalVisual
{
   string names[8];
   int count;
   bool ready,visible,wanted;
};
AuditMemoIndex g_maVisualIndex;
MaHistoricalVisual g_maVisuals[];
string g_maPlotRoot="",g_maVisualPrefix="";
bool g_maVisualBuilding=false;
long g_maVisualHits=0,g_maVisualMisses=0;

void MaVisualBeginAudit(const string prefix)
{
   g_maVisualPrefix=prefix;g_maPlotRoot="";g_maVisualBuilding=true;
   g_maVisualHits=0;g_maVisualMisses=0;
   for(int i=0;i<ArraySize(g_maVisuals);i++)g_maVisuals[i].wanted=false;
}
int MaVisualBeginPlot(const string key,bool &reused)
{
   reused=false;
   if(!g_maVisualBuilding)return -1;
   int slot=g_maVisualIndex.Find(key);
   if(slot<0)slot=g_maVisualIndex.Add(key);
   if(slot<0)return -1; // Bounded cache exhausted: draw normally.
   if(ArraySize(g_maVisuals)<=slot)
   {
      int before=ArraySize(g_maVisuals);ArrayResize(g_maVisuals,slot+1,512);
      for(int i=before;i<=slot;i++)ZeroMemory(g_maVisuals[i]);
   }
   g_maVisuals[slot].wanted=true;
   if(g_maVisuals[slot].ready){g_maVisualHits++;reused=true;return slot;}
   g_maVisualMisses++;
   g_maPlotRoot=g_maVisualPrefix+(string)slot+"_";
   return slot;
}
void MaVisualEndPlot(const int slot,const string eventSuffix,const string levelSuffix,bool target,bool exit,bool levels=true)
{
   if(slot<0){g_maPlotRoot="";return;}
   string root=g_maPlotRoot;
   string names[]={root+"LVL_"+levelSuffix+"_ENTRY",root+"LVL_"+levelSuffix+"_SL",
      root+"LVL_"+levelSuffix+"_TP",root+eventSuffix+"ARW",root+eventSuffix+"EXIT",
      root+eventSuffix+"TXT",root+eventSuffix+"LVLTXT"};
   g_maVisuals[slot].count=0;
   for(int i=0;i<ArraySize(names);i++)
   {
      if((i<3&&!levels)||(i==2&&!target)||(i==4&&!exit))continue;
      int n=g_maVisuals[slot].count++;
      g_maVisuals[slot].names[n]=names[i];
      // New drawings remain hidden until the entire audit commits. A cancelled
      // rebuild cannot overwrite or hide the previous committed snapshot.
      ObjectSetInteger(0,names[i],OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
   }
   g_maVisuals[slot].ready=true;g_maVisuals[slot].visible=false;g_maPlotRoot="";
}
void MaVisualCommit()
{
   if(!g_maVisualBuilding)return;
   for(int i=0;i<ArraySize(g_maVisuals);i++)
   {
      if(!g_maVisuals[i].ready||g_maVisuals[i].visible==g_maVisuals[i].wanted)continue;
      for(int j=0;j<g_maVisuals[i].count;j++)
         ObjectSetInteger(0,g_maVisuals[i].names[j],OBJPROP_TIMEFRAMES,
            g_maVisuals[i].wanted?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
      g_maVisuals[i].visible=g_maVisuals[i].wanted;
   }
   g_maPlotRoot="";g_maVisualBuilding=false;
}
void MaVisualAbort(){g_maPlotRoot="";g_maVisualBuilding=false;}
void MaVisualReset()
{
   static long revision=0;
   MaVisualAbort();g_maVisualIndex.Reset((string)++revision);
   ArrayResize(g_maVisuals,0);g_maVisualPrefix="";
}
#endif
