#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
void Check(bool yes,string label){checks++;if(!yes){failed++;Print("FAIL ",label," ",g_userStrategyNote);}}
void OnStart()
{
   FolderCreate("OrbStrategyUserLibrary",FILE_COMMON);
   g_runtimeMagic=9192026000+(long)(GetTickCount64()%1000000);
   OrbStrategyPreset defaults;OrbPresetDefaults(defaults);OrbStrategyPresetApplyValues(defaults);
   Check(OrbBrokerClockKey()==""&&OrbBrokerOffsetHours()==0,"old defaults unchanged");
   for(int p=0;p<=10;p++)for(int b=0;b<=2;b++)for(int e=0;e<=2;e++)for(int s=0;s<=1;s++)
   {OrbClockUseSaved(p,b,e,s);int pp,bb,ee,ss;Check(OrbClockReadMeta(OrbClockSavedMeta(),pp,bb,ee,ss)&&pp==p&&bb==b&&ee==e&&ss==s,"clock metadata roundtrip");}
   int p,b,e,s;Check(!OrbClockReadMeta("11,0,0,0",p,b,e,s)&&!OrbClockReadMeta("0,x,0,0",p,b,e,s),"bad clock metadata");
   OrbClockUseSaved(1,0,0,1);g_orbStrategyTimezone=0;g_rtUtcMidnightSession=false;
   Check(SessionLocalToServer(2026,9,18,600)==D'2026.09.18 07:00',"BIST GMT0 conversion");
   g_orbStrategyTimezone=2;
   Check(SessionLocalToServer(2026,9,18,600)==D'2026.09.18 09:00',"same BIST instant GMT2");
   string savedTime="TCAL1=1,0,64,8192,0,0,0,0";
   Check(TCalStrategyApplyText(savedTime),"apply custom time matrix");
   int sm,em,tem;SessionClockMinutes(sm,em,tem);Check(sm==600&&em==615&&tem==1080,"BIST cash window");
   string name="__ORB_CLOCK_PROBE_"+(string)GetTickCount64();
   Check(OrbUserSave(name),"save custom clock");
   OrbStrategyPreset saved;int index=g_strategyPresetIndex;
   Check(OrbStrategyPresetLoad(index,saved),"load saved clock");
   int slot=OrbUserSlot(saved.id),oldCount=g_userCount;string identity=saved.id;
   if(slot>=0)
   {
      Check(g_userStrategies[slot].timeMatrix==savedTime,"time matrix stored in strategy");
      OrbClockUseSaved(0,0,0,0);g_orbStrategyTimezone=0;
      Check(TCalStrategyApplyText(TCalStrategyOffText()),"reset time matrix before load");
      Check(OrbUserApply(saved),"load user strategy");
      Check(OrbBrokerOffsetHours()==2&&OrbClockProfile()==ORB_CLOCK_FIXED&&g_orbClockSession==1,"restore clock and session");
      Check(TCalStrategyMatchesText(savedTime),"restore exact time matrix");
      Check(OrbUserMatches(saved),"exact saved match");
      g_orbStrategyTimezone=3;Check(OrbUserSave(name),"update same name");
      Check(g_userCount==oldCount&&g_strategyPresetIndex==index,"one strategy identity");
      Check(g_userStrategies[slot].brokerOffset==3,"updated offset");
      FileDelete(OrbUserFile(slot),FILE_COMMON);FileDelete("OrbStrategyUserLibrary\\"+identity+".metrics",FILE_COMMON);
   }
   GlobalVariableDel(OrbStrategyPresetSelectionKey());GlobalVariableDel(OrbStrategyPresetSelectionKey()+".id");
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("OrbClockSaveProbe_232312.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print(result);
}
