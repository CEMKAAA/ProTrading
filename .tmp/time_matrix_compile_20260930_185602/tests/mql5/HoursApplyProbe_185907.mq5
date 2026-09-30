#property strict
#include "../../orb/TradeCalendarMatrix.mqh"
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("HOURS_APPLY_FAIL ",label);}}
void OnStart()
{
   Check(TCalInit(),"initialize");
   string old=TCalStrategyOffText();
   Check(TCalStrategyApplyText("TCAL1=1,0,64,8704,0,0,0,0,2,3,4,360"),"initial per-day schedule");
   int before[7];for(int day=0;day<7;day++)before[day]=g_tcalDayHours[day];
   g_tcalPrefix="HOURS_APPLY_PROBE_";TCalOpen(20,20);
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_TAB_1"));
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_NEXT"));
   Check(g_tcalView==1&&g_tcalPage==1,"hours page 08-16");
   Check(ObjectFind(0,TCalId("MOD_HOUR_APPLY_9"))>=0,"row button exists");
   // A pending Monday 13-14 edit must not be silently applied by this shortcut.
   g_tcalDraftDayHours[1]|=1<<13;g_tcalDraftEdited=true;
   g_tcalChanged=false;
   Check(TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_HOUR_APPLY_9")),"click handled");
   bool masks=true;for(int day=0;day<7;day++)if(g_tcalDayHours[day]!=(before[day]|(1<<9)))masks=false;
   Check(masks,"only selected hour added to all seven days");
   Check((g_tcalDayHours[1]&(1<<9))!=0,"Monday changes from blocked to allowed");
   Check(g_tcalDayHours[2]==before[2],"Tuesday already open remains identical");
   Check((g_tcalDayHours[1]&(1<<13))==0&&(g_tcalDraftDayHours[1]&(1<<13))!=0,"unrelated pending edits retained but not applied");
   Check(g_tcalEnabled&&g_tcalChanged,"filter activates and audit invalidates");
   Check(g_entryDirection==2&&g_dailyMaxLosses==3&&g_dailyTargetWins==4&&g_dailyStartMinute==360,"unrelated settings preserved");
   Check(TCalAllows(D'2026.09.21 09:30')&&TCalAllows(D'2026.09.22 09:30')&&!TCalAllows(D'2026.09.21 13:30'),"entry gate respects new masks");
   string applied=TCalStrategyText();g_tcalChanged=false;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_HOUR_APPLY_9"));
   Check(!g_tcalChanged&&TCalStrategyText()==applied,"repeated apply is idempotent");
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_HOUR_APPLY_1"));
   Check(TCalStrategyText()==applied,"stale off-page button ignored");
   Check(TCalInit()&&TCalStrategyMatchesText(applied),"restart restores applied masks");
   Check(TCalStrategyApplyText(old)&&TCalStrategyApplyText(applied)&&TCalStrategyMatchesText(applied),"strategy round trip");
   g_tcalView=2;g_tcalChanged=false;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_HOUR_APPLY_9"));
   Check(!g_tcalChanged&&TCalStrategyMatchesText(applied),"other tab cannot use shortcut");
   double header=GlobalVariableGet(TCalStorageKey("cfg2"));
   GlobalVariableSet(TCalStorageKey("cfg2"),99);
   Check(!TCalApplyHourAllDays(10)&&TCalStrategyText()==applied,"save failure rolls back all masks");
   GlobalVariableSet(TCalStorageKey("cfg2"),header);
   Check(!TCalApplyHourAllDays(-1)&&!TCalApplyHourAllDays(24),"invalid hours rejected");
   g_tcalEnabled=false;g_tcalChanged=false;
   Check(TCalApplyHourAllDays(9)&&g_tcalEnabled&&g_tcalChanged,"disabled filter enabled even when masks already contain hour");
   Check(TCalApplyHourAllDays(23)&&TCalHourAllDaysActive(23),"last page hour applies");
   g_tcalView=1;g_tcalPage=2;TCalDraw();
   Check(ObjectFind(0,TCalId("MOD_HOUR_APPLY_23"))>=0,"last page button exists");
   TCalDestroy();Check(TCalStrategyApplyText(old),"restore defaults");
   int file=FileOpen("HoursApplyProbe_185907.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(file);}
}
