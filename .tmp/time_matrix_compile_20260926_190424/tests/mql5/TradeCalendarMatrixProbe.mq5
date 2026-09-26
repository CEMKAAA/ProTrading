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
   g_tcalEnabled=false;g_tcalRankPending=false;g_tcalDraftEdited=false;g_tcalChanged=false;
   bool stagedFirst=TCalStageRankedBucket(2,1*24+6),stagedSecond=TCalStageRankedBucket(2,2*24+13);
   checks++;if(!stagedFirst||!stagedSecond||g_tcalEnabled||g_tcalChanged||g_tcalRankPickCount!=2||
      g_tcalDraftDayHours[1]!=(1<<6)||g_tcalDraftDayHours[2]!=(1<<13))failed++;
   bool picksApplied=TCalApplyDraft();
   checks++;if(!picksApplied||!g_tcalEnabled||!g_tcalChanged||!TCalAllows(monday)||!TCalAllows(tuesday)||TCalAllows(mondayOther))failed++;
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
   TCalReset();TCalRecord(monday,1.0);TCalRecord(tuesday,1.0);
   TCalRecord(tuesday,-1.0);TCalRecord(tuesdayOther,1.0);
   checks++;if(TCalRankWins(0,1)!=1||TCalRankLosses(0,2)!=1||TCalRankWins(1,6)!=2||TCalRankLosses(2,2*24+13)!=1)failed++;
   g_tcalView=3;g_tcalEnabled=false;g_tcalMinSample=1;
   g_tcalRankPending=false;g_tcalDraftEdited=false;g_tcalRankPickCount=0;g_tcalChanged=false;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_MODE_0"));
   checks++;if(g_tcalRankMode!=0||TCalRankCount()!=7)failed++;
   checks++;if(StringFind(ObjectGetString(0,TCalId("MOD_ROW_0"),OBJPROP_TEXT),"MON")<0)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_ADD_1"));
   checks++;if(g_tcalEnabled||g_tcalChanged||g_tcalRankPickCount!=1||
      g_tcalDraftDayHours[1]!=16777215||g_tcalDayHours[1]==16777215)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_MODE_1"));
   checks++;if(g_tcalRankMode!=1||TCalRankCount()!=24)failed++;
   checks++;if(StringFind(ObjectGetString(0,TCalId("MOD_ROW_0"),OBJPROP_TEXT),"06-07")<0)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_ADD_13"));
   checks++;if(g_tcalEnabled||g_tcalChanged||g_tcalRankPickCount!=2||
      (g_tcalDraftDayHours[2]&(1<<13))==0||(g_tcalDraftDayHours[2]&(1<<6))!=0)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_MODE_2"));
   checks++;if(g_tcalRankMode!=2||TCalRankCount()!=168)failed++;
   checks++;if(StringFind(ObjectGetString(0,TCalId("MOD_ROW_0"),OBJPROP_TEXT),"MON 06-07")<0)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_ADD_54")); // TUE 06-07.
   checks++;if(g_tcalEnabled||g_tcalChanged||g_tcalRankPickCount!=3||
      (g_tcalDraftDayHours[2]&(1<<6))==0)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_APPLY"));
   checks++;if(!g_tcalEnabled||!g_tcalChanged||g_tcalRankPending||g_tcalRankPickCount!=0||
      !TCalAllows(mondayOther)||!TCalAllows(tuesday)||!TCalAllows(tuesdayOther))failed++;
   TCalReset();
   for(int hour=0;hour<10;hour++)TCalRecord(StringToTime("2026.09.20 00:15")+hour*3600,1.0);
   g_tcalEnabled=false;g_tcalChanged=false;g_tcalRankPending=false;
   g_tcalDraftEdited=false;g_tcalRankPickCount=0;
   g_tcalRankMode=2;g_tcalMinSample=1;g_tcalPage=0;TCalDraw();
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_PAGE"));
   checks++;if(g_tcalRankPickCount!=8||g_tcalEnabled||g_tcalChanged||
      g_tcalDraftDayHours[0]!=255)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_NEXT"));
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_PAGE"));
   checks++;if(g_tcalRankPickCount!=10||g_tcalDraftDayHours[0]!=1023||g_tcalChanged)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_PAGE"));
   checks++;if(g_tcalRankPickCount!=10||g_tcalDraftDayHours[0]!=1023)failed++;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_APPLY"));
   checks++;if(!g_tcalEnabled||!g_tcalChanged||g_tcalDayHours[0]!=1023)failed++;
   g_tcalMinSample=2;g_tcalPage=0;g_tcalChanged=false;
   TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("MOD_RANK_PAGE"));
   checks++;if(g_tcalRankPickCount!=0||g_tcalRankPending||g_tcalChanged||g_tcalDayHours[0]!=1023)failed++;
   string savedTime=TCalStrategyText();
   checks++;if(!TCalStrategyMatchesText(savedTime)||TCalStrategyMatchesText(TCalStrategyOffText()))failed++;
   checks++;if(!TCalStrategyApplyText(TCalStrategyOffText())||g_tcalEnabled||g_tcalDayHours[0]!=16777215)failed++;
   checks++;if(!TCalStrategyApplyText(savedTime)||!g_tcalEnabled||g_tcalDayHours[0]!=1023)failed++;
   bool parsed=false;int parsedHours[];
   checks++;if(TCalStrategyRead("TCAL1=1,16777216,0,0,0,0,0,0",parsed,parsedHours)
      ||TCalStrategyRead("TCAL1=1,0,0,0,0,0,0,0",parsed,parsedHours))failed++;
   TCalDestroy();
   GlobalVariableDel(TCalStorageKey("cfg2"));GlobalVariableDel(TCalStorageKey("cfg"));
   GlobalVariableDel(TCalStorageKey("base"));
   for(int slot=0;slot<2;slot++)for(int day=0;day<7;day++)
      GlobalVariableDel(TCalStorageKey("h"+(string)slot+"."+(string)day));
   string payload=StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed);
   int file=FileOpen("TradeCalendarMatrixProbe_190424.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,payload);FileClose(file);}
   Print(payload);
}
