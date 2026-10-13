#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedEvent
#define OnTradeTransaction UnusedTransaction
#include "../../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
void OnStart(){
 int f=FileOpen("StrategyMetricsInventory.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
 FileWrite(f,"name","kind","id","window","current","mega","key","diskKey");
 OrbUserReload(true);
 for(int i=0;i<OrbStrategyPresetCount();i++){
  OrbStrategyPreset p;if(!OrbStrategyPresetLoad(i,p))continue;
  int slot=OrbUserSlot(p.id);string key=slot>=0?OrbUserWindowKey(g_userStrategies[slot]):OrbBuiltinWindowKey(p);
  for(int w=0;w<9;w++){
   int weeks=SwWeeks(w);g_swWeeks=weeks;if(slot<0)OrbBuiltinLoadWindowMetrics(p);SwMetric m;bool ready=SwRead("OrbStrategyUserLibrary\\WindowMetrics",p.id,key,weeks,m);
   if(slot<0)ready=p.metric1yReady;g_swFrozen=true;bool mega=SwReadView("OrbStrategyUserLibrary\\WindowMetrics",p.id,key,weeks,m);g_swFrozen=false;
   int h=FileOpen(SwPath("OrbStrategyUserLibrary\\WindowMetrics",p.id,weeks),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
   string disk="";if(h!=INVALID_HANDLE){FileReadString(h);FileReadString(h);disk=FileReadString(h);FileClose(h);}
   FileWrite(f,p.name,slot>=0?"user":"builtin",p.id,weeks,ready,mega,key,disk);
  }
 }
 FileClose(f);
}