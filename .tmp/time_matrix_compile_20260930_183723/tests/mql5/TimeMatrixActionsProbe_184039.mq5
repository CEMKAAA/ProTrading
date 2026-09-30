#property strict
#include "../../macrossover_orb/TradeCalendarMatrix.mqh"
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("MATRIX_ACTION_FAIL ",label);}}
void Click(string suffix){TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId(suffix));}
void OnStart()
{
   Check(TCalInit(),"initialize");
   string saved=TCalStrategyText();
   Check(TCalStrategyApplyText("TCAL1=1,0,64,8192,0,0,0,0"),"seed Monday and Tuesday");
   g_tcalPrefix="MATRIX_ACTION_PROBE_";TCalOpen(20,20);TCalDraw();
   Check(ObjectFind(0,TCalId("MOD_DAY_APPLY_1"))>=0&&ObjectFind(0,TCalId("MOD_DAY_CANCEL_1"))>=0,"day controls exist");
   g_tcalDraftDayHours[3]=1<<14;g_tcalDraftEdited=true;g_tcalChanged=false;
   Click("MOD_DAY_APPLY_1");
   Check(g_tcalDayHours[1]==16777215&&g_tcalDayHours[2]==8192&&g_tcalDayHours[3]==0,"day apply affects only selected day");
   Check(g_tcalDraftDayHours[3]==(1<<14)&&g_tcalChanged,"unrelated draft preserved and audit invalidated");
   Click("MOD_DAY_CANCEL_1");
   Check(g_tcalDayHours[1]==0&&g_tcalDayHours[2]==8192,"day cancel removes all its hours only");
   Click("MOD_TAB_1");Click("MOD_NEXT");
   Check(ObjectFind(0,TCalId("MOD_HOUR_CANCEL_9"))>=0,"hour cancel control exists");
   Click("MOD_HOUR_APPLY_9");
   bool all=true;for(int day=0;day<7;day++)if((g_tcalDayHours[day]&(1<<9))==0)all=false;
   Check(all,"hour applies to all days");
   Click("MOD_HOUR_CANCEL_9");
   all=true;for(int day=0;day<7;day++)if((g_tcalDayHours[day]&(1<<9))!=0)all=false;
   Check(all&&g_tcalDayHours[2]==8192,"hour removes from all days without other changes");
   Click("MOD_TAB_2");g_tcalDay=4;g_tcalPage=2;TCalDraw();
   Check(ObjectFind(0,TCalId("MOD_CELL_APPLY_118"))>=0&&ObjectFind(0,TCalId("MOD_CELL_CANCEL_118"))>=0,"day-hour controls exist on last page");
   Click("MOD_CELL_APPLY_118");
   Check(g_tcalDayHours[4]==(1<<22)&&g_tcalDayHours[2]==8192,"one day-hour applies");
   string active=TCalStrategyText();
   Click("MOD_CELL_CANCEL_94");
   Check(TCalStrategyMatchesText(active),"stale other-day control ignored");
   Click("MOD_CELL_CANCEL_118");
   Check(g_tcalDayHours[4]==0&&g_tcalDayHours[2]==8192,"one day-hour cancels");
   g_tcalDay=2;g_tcalPage=1;TCalDraw();g_tcalChanged=false;
   active=TCalStrategyText();Click("MOD_CELL_CANCEL_61");
   Check(!g_tcalChanged&&TCalStrategyMatchesText(active),"last remaining bucket removal rolls back visibly");
   Check(StringFind(g_tcalActionNote,"at least one")>=0,"last-bucket explanation shown");
   double header=GlobalVariableGet(TCalStorageKey("cfg2"));
   GlobalVariableSet(TCalStorageKey("cfg2"),99);
   Check(!TCalSetBucket(0,1,true)&&TCalStrategyMatchesText(active),"storage failure rolls back");
   GlobalVariableSet(TCalStorageKey("cfg2"),header);

   TCalReset();g_tcalMinSample=10;
   g_tcalWins[1][6]=96;g_tcalLosses[1][6]=4;
   g_tcalWins[2][13]=95;g_tcalLosses[2][13]=5;
   g_tcalWins[4][22]=97;g_tcalLosses[4][22]=3;
   g_tcalWins[6][23]=1; // Below MIN N despite 100% WR.
   g_tcalWins[0][0]=20;
   Click("MOD_TAB_3");Click("MOD_RANK_MODE_0");
   Check(ObjectFind(0,TCalId("MOD_SMART_WR"))>=0&&ObjectFind(0,TCalId("MOD_SMART_PICK"))>=0,"smart controls exist");
   ObjectSetString(0,TCalId("MOD_SMART_WR"),OBJPROP_TEXT,"96");
   g_tcalChanged=false;Click("MOD_SMART_PICK");
   Check(g_tcalRankMode==2&&g_tcalRankPickCount==3,"smart selection always scans day-hour buckets across pages");
   Check(g_tcalDraftDayHours[1]==(1<<6)&&g_tcalDraftDayHours[4]==(1<<22)&&g_tcalDraftDayHours[0]==1,"WR threshold includes equality and larger values");
   Check(g_tcalDraftDayHours[2]==0&&g_tcalDraftDayHours[3]==0&&g_tcalDraftDayHours[6]==0,"lower WR, stale draft and small sample excluded");
   Check(!g_tcalChanged&&TCalStrategyMatchesText(active)&&g_tcalRankPending,"smart selection remains staged");
   ObjectSetString(0,TCalId("MOD_SMART_WR"),OBJPROP_TEXT,"96.5");
   Click("MOD_NEXT");
   Check(ObjectGetString(0,TCalId("MOD_SMART_WR"),OBJPROP_TEXT)=="96.5","edit survives redraw without end-edit event");
   Click("MOD_SMART_PICK");
   Check(g_tcalRankPickCount==2&&g_tcalDraftDayHours[1]==0,"current unrounded threshold read from edit");
   ObjectSetString(0,TCalId("MOD_SMART_WR"),OBJPROP_TEXT,"101");Click("MOD_SMART_PICK");
   Check(g_tcalRankPickCount==2&&!g_tcalChanged&&StringFind(g_tcalActionNote,"0 to 100")>=0,"invalid WR rejected without selection changes");
   ObjectSetString(0,TCalId("MOD_SMART_WR"),OBJPROP_TEXT,"96");Click("MOD_SMART_PICK");Click("MOD_RANK_APPLY");
   Check(g_tcalEnabled&&g_tcalChanged&&!g_tcalRankPending&&g_tcalDayHours[2]==0,"bulk apply activates only qualifying cells");
   Check(TCalAllows(D'2026.09.21 06:30')&&TCalAllows(D'2026.09.24 22:30')&&!TCalAllows(D'2026.09.22 13:30'),"entry gate uses smart selection");
   string picked=TCalStrategyText();
   Check(TCalStrategyApplyText(TCalStrategyOffText())&&TCalStrategyApplyText(picked)&&TCalStrategyMatchesText(picked),"smart picks strategy save/load round trip");
   Check(TCalInit()&&TCalStrategyMatchesText(picked),"restart restores smart picks");
   TCalReset();g_tcalRankPending=false;g_tcalChanged=false;
   int priorDraft=g_tcalDraftDayHours[1];
   Check(TCalStageSmartWr(96)==0&&g_tcalDraftDayHours[1]==priorDraft&&!g_tcalRankPending&&!g_tcalChanged,"no matches preserve active and staged state");
   double value=0;
   Check(TCalParseWr(" 96,5 ",value)&&value==96.5,"decimal comma supported");
   Check(!TCalParseWr("",value)&&!TCalParseWr("96abc",value)&&!TCalParseWr("-1",value)&&!TCalParseWr("1.2.3",value),"malformed thresholds rejected");
   g_tcalWins[1][1]=10;g_tcalWins[2][2]=0;g_tcalLosses[2][2]=10;
   Check(TCalStageSmartWr(0)==2&&(g_tcalDraftDayHours[2]&(1<<2))!=0,"zero threshold includes observed zero-WR cells only");
   Check(TCalStageSmartWr(100)==1&&g_tcalDraftDayHours[1]==(1<<1)&&g_tcalDraftDayHours[2]==0,"100 threshold selects perfect buckets only");
   g_tcalMinSample=20;
   Check(TCalStageSmartWr(0)==0,"sample floor honored");
   TCalDestroy();Check(TCalStrategyApplyText(saved),"restore original worker state");
   int file=FileOpen("TimeMatrixActionsProbe_184039.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(file);}
}
