#property strict
#include "../../TradeCalendarMatrix.mqh"

void OnStart()
{
   int checks=0,failed=0;
   datetime monday=StringToTime("2026.09.21 06:15");
   datetime mondayOther=StringToTime("2026.09.21 13:15");
   datetime tuesday=StringToTime("2026.09.22 13:15");
   datetime tuesdayOther=StringToTime("2026.09.22 06:15");
   GlobalVariableDel(TCalStorageKey("cfg2"));GlobalVariableDel(TCalStorageKey("cfg"));
   GlobalVariableDel(TCalStorageKey("base"));
   for(int slot=0;slot<2;slot++)for(int day=0;day<7;day++)
      GlobalVariableDel(TCalStorageKey("h"+(string)slot+"."+(string)day));
   bool initialized=TCalInit();
   checks++;if(!initialized)failed++;
   for(int day=0;day<7;day++)g_tcalDayHours[day]=0;
   g_tcalDayHours[1]=1<<6;g_tcalDayHours[2]=1<<13;g_tcalEnabled=false;
   checks++;if(!TCalAllows(mondayOther))failed++;
   g_tcalEnabled=true;
   checks++;if(!TCalAllows(monday))failed++;
   checks++;if(!TCalAllows(tuesday))failed++;
   checks++;if(TCalAllows(mondayOther)||TCalAllows(tuesdayOther))failed++;
   TCalReset();TCalRecord(monday,0.5);TCalRecord(monday,1.0);
   TCalRecord(monday,-1.0);TCalRecord(monday,0.0);
   checks++;if(g_tcalWins[1][6]!=2||g_tcalLosses[1][6]!=1)failed++;
   checks++;if(MathAbs(TCalWr(2,1)-66.6666667)>0.0001)failed++;
   checks++;if(TCalValidMasks(0,1)||TCalValidMasks(127,0)||!TCalValidMasks(127,16777215))failed++;
   bool saved=TCalSave();
   for(int day=0;day<7;day++)g_tcalDayHours[day]=16777215;
   g_tcalEnabled=false;
   bool restored=TCalInit();
   checks++;if(!saved||!restored||!g_tcalEnabled||!TCalAllows(monday)||!TCalAllows(tuesday)||TCalAllows(mondayOther))failed++;
   for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=0;
   checks++;if(TCalApplyDraft()||!TCalAllows(monday))failed++;
   g_tcalEnabled=false;
   bool addedFirst=TCalAddRanked(1,6),addedSecond=TCalAddRanked(2,13);
   checks++;if(!addedFirst||!addedSecond||!TCalAllows(monday)||!TCalAllows(tuesday)||TCalAllows(mondayOther))failed++;
   GlobalVariableDel(TCalStorageKey("cfg2"));
   GlobalVariableSet(TCalStorageKey("cfg"),TCalPack(true,(1<<1)|(1<<2),1<<6));
   bool migrated=TCalInit();
   checks++;if(!migrated||!TCalAllows(monday)||!TCalAllows(tuesdayOther)||TCalAllows(tuesday))failed++;
   g_tcalPrefix="TCAL_PROBE_";TCalOpen(8,8);g_tcalView=4;g_tcalPage=0;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_CLEAR"));
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_PICK_DAY_1"));
   checks++;if(g_tcalDay!=1||g_tcalPage!=1)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_PICK_HOUR_6"));
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_DAYS"));
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_PICK_DAY_2"));
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_PICK_NEXT"));
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_PICK_HOUR_13"));
   checks++;if(g_tcalDraftDayHours[1]!=(1<<6)||g_tcalDraftDayHours[2]!=(1<<13)||g_tcalPage!=2)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_APPLY"));
   checks++;if(!g_tcalEnabled||!TCalAllows(monday)||!TCalAllows(tuesday)||TCalAllows(mondayOther))failed++;
   TCalReset();TCalRecord(monday,1.0);TCalRecord(tuesday,1.0);TCalRecord(tuesday,-1.0);
   checks++;if(TCalRankWins(0,1)!=1||TCalRankLosses(0,2)!=1||TCalRankWins(1,6)!=1||TCalRankLosses(2,2*24+13)!=1)failed++;
   g_tcalView=3;g_tcalEnabled=false;g_tcalMinSample=1;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_MODE_0"));
   checks++;if(g_tcalRankMode!=0||TCalRankCount()!=7)failed++;
   checks++;if(StringFind(ObjectGetString(0,TCalId("MOD_ROW_0"),OBJPROP_TEXT),"MON")<0)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_ADD_1"));
   checks++;if(!g_tcalEnabled||!TCalAllows(monday)||!TCalAllows(mondayOther)||TCalAllows(tuesday))failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_MODE_1"));
   checks++;if(g_tcalRankMode!=1||TCalRankCount()!=24)failed++;
   checks++;if(StringFind(ObjectGetString(0,TCalId("MOD_ROW_0"),OBJPROP_TEXT),"06-07")<0)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_ADD_13"));
   checks++;if(!TCalAllows(tuesday)||TCalAllows(tuesdayOther))failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_MODE_2"));
   checks++;if(g_tcalRankMode!=2||TCalRankCount()!=168)failed++;
   checks++;if(StringFind(ObjectGetString(0,TCalId("MOD_ROW_0"),OBJPROP_TEXT),"MON 06-07")<0)failed++;
   TCalDestroy();
   GlobalVariableDel(TCalStorageKey("cfg2"));GlobalVariableDel(TCalStorageKey("cfg"));
   GlobalVariableDel(TCalStorageKey("base"));
   for(int slot=0;slot<2;slot++)for(int day=0;day<7;day++)
      GlobalVariableDel(TCalStorageKey("h"+(string)slot+"."+(string)day));
   string payload=StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed);
   int file=FileOpen("TradeCalendarMatrixProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,payload);FileClose(file);}
   Print(payload);
}
