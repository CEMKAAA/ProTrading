#property strict
#define OnInit PolicyInit
#define OnDeinit PolicyDeinit
#define OnTick PolicyTick
#define OnTimer PolicyTimer
#define OnChartEvent PolicyEvent
#define OnTradeTransaction PolicyTransaction
#include "../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "MaPositionReference.mqh"
int checks=0,failed=0;
void Check(bool value,string name){checks++;if(!value){failed++;Print("FAIL ",name);}}
void CheckMaReference()
{
   PolicyMaEvent reference[];OrbWindowSignal events[];
   ArrayResize(reference,6);ArrayResize(events,6);
   int times[]={990,1000,1100,1250,1300,1450},opened[]={1000,1100,1300};
   int waits[]={0,1,5,30},through[]={950,1000,1100,1250,1300,1450,1500,3000};
   g_orbPositions.reverse=true;g_histAuditRunning=false;g_histRedrawQueued=false;
   ArrayResize(g_histAcceptedSignals,3);ArrayResize(g_orbPositionLiveEvents,3);
   for(int mask=0;mask<64;mask++)for(int inv=0;inv<2;inv++)
   {
      for(int i=0;i<6;i++)
      {
         reference[i].signalTime=times[i]-60;reference[i].direction=(mask&(1<<i))!=0?1:-1;
         ZeroMemory(events[i]);events[i].availableTime=times[i];
         events[i].executionDirection=reference[i].direction*(inv!=0?-1:1)>0?"BUY":"SELL";
         if(i%2==0)g_histAcceptedSignals[i/2]=events[i];else g_orbPositionLiveEvents[i/2]=events[i];
      }
      for(int d=-1;d<=1;d+=2)for(int o=0;o<3;o++)for(int w=0;w<4;w++)for(int u=0;u<8;u++)
      {
         g_orbPositions.waitMinutes=waits[w];datetime at=0;string detail="";
         datetime expected=ReferenceMaKernelExitAt(reference,opened[o],d,through[u],waits[w],60,inv!=0);
         FindOrbTimedReverseExit(events,opened[o],d>0?"BUY":"SELL",through[u],at,detail);
         Check(at==expected,"MaCross exact reverse reference");
         datetime seen=opened[o];int state=0;
         Check(OrbPositionObservedExit(opened[o],d>0?"BUY":"SELL",through[u],seen,state)==expected,
            "MaCross reverse reference on merged live/history streams");
      }
   }
   ArrayFree(g_histAcceptedSignals);ArrayFree(g_orbPositionLiveEvents);
}
void OnStart()
{
   OrbPositionDefaults(g_orbPositions);
   OrbPositionPolicy copy;
   Check(OrbPositionRead(OrbPositionPack(g_orbPositions),copy)&&OrbPositionIsDefault(copy),"old strategy defaults");
   g_orbPositions.independent=true;g_orbPositions.maxSameOpen=20;g_orbPositions.nextDay=false;
   g_orbPositions.reverse=true;g_orbPositions.waitMinutes=30;
   Check(OrbPositionRead(OrbPositionPack(g_orbPositions),copy)&&OrbPositionPack(copy)==OrbPositionPack(g_orbPositions),"strategy policy round trip");
   Check(!OrbPositionRead("POS1=2,0,1,20,30",copy),"malformed bool rejected");
   int wait=0;Check(OrbPositionWaitRead("04:30",wait)&&wait==270,"HH:MM current edit");
   Check(!OrbPositionWaitRead("01:60",wait)&&!OrbPositionWaitRead("100:00",wait),"invalid wait rejected");
   Check(OrbPositionWaitRead("99:59",wait)&&wait==5999,"MaCross duration range");
   OrbWindowSignal events[];ArrayResize(events,4);
   events[0].availableTime=990;events[0].executionDirection="SELL";
   events[1].availableTime=1100;events[1].executionDirection="SELL";
   events[2].availableTime=1250;events[2].executionDirection="BUY";
   events[3].availableTime=1450;events[3].executionDirection="SELL";
   g_orbPositions.waitMinutes=5;
   datetime at=0;string detail="";
   Check(!FindOrbTimedReverseExit(events,1000,"BUY",1200,at,detail),"grace not expired");
   Check(!FindOrbTimedReverseExit(events,1000,"BUY",1400,at,detail),"latest same-side cancels latch");
   Check(FindOrbTimedReverseExit(events,1000,"BUY",1500,at,detail)&&at==1450,"post-wait reverse closes");
   ArrayResize(events,2);
   Check(FindOrbTimedReverseExit(events,1000,"BUY",1400,at,detail)&&at==1300,"opposite during grace closes at expiry");
   ArrayResize(events,1);
   Check(!FindOrbTimedReverseExit(events,1000,"BUY",5000,at,detail),"pre-entry excluded");
   g_orbPositions.reverse=false;g_orbPositions.nextDay=false;
   Check(!FindNewDayAcceptedReverseExit(events,900,"BUY",5000,at,detail),"both reverse controls OFF");
   ArrayFree(g_orbPositionReservations);g_orbPositions.independent=true;g_orbPositions.maxSameOpen=1;
   OrbPositionReserve(1,true,1500);
   Check(OrbPositionAuditCap(1400)==1,"MAX total blocks any second position");
   Check(OrbPositionAuditCap(1500)==0,"completed trade releases slot");
   OrbPositionReserve(1,true,0);g_orbPositions.independent=false;
   Check(OrbPositionAuditCap(1600)==1,"legacy single across both sides");
   ArrayFree(g_orbPositionReservations);OrbPositionReserve(1,false,0);
   Check(OrbPositionAuditCap(1600)==-1,"unknown capacity remains DATA");
   g_orbPositions.independent=true;g_orbPositions.maxSameOpen=10;
   ArrayFree(g_orbPositionReservations);
   for(int n=0;n<=10;n++)
   {
      Check((OrbPositionAuditCap(1400)==0)==ReferenceMaOpenCapacityAllows(n,10),"MaCross total capacity reference");
      if(n<10)OrbPositionReserve(n<6?1:-1,true,n==0?1500:0);
   }
   Check(OrbPositionAuditCap(1500)==0,"mixed 6 BUY + 4 SELL release one total slot");
   OrbPositionReserve(-1,true,0);
   Check(OrbPositionAuditCap(1501)==1,"direction change never resets total count");
   g_orbPositions.maxSameOpen=1000;
   Check(OrbPositionRead(OrbPositionPack(g_orbPositions),copy),"MaCross MAX range");
   Check(StringFind(OrbPositionMetricMeta(g_orbPositions),"TOTAL_OPEN_V2")>=0,"old directional metrics invalidated");
   OrbPositionDefaults(g_orbPositions);g_orbStrategyTimezone=0;
   ArrayResize(events,1);events[0].availableTime=D'2026.09.22 12:00';events[0].executionDirection="SELL";
   Check(FindNewDayAcceptedReverseExit(events,D'2026.09.21 12:00',"BUY",D'2026.09.23',at,detail),"legacy next-day default preserved");
   g_orbPositions.nextDay=false;
   Check(!FindNewDayAcceptedReverseExit(events,D'2026.09.21 12:00',"BUY",D'2026.09.23',at,detail),"next-day toggle OFF");
   g_orbPositions.reverse=true;g_orbPositions.waitMinutes=5;
   g_histAuditRunning=false;g_histRedrawQueued=false;
   ArrayResize(g_histAcceptedSignals,1);ArrayResize(g_orbPositionLiveEvents,1);
   g_histAcceptedSignals[0].availableTime=1100;g_histAcceptedSignals[0].executionDirection="SELL";
   g_orbPositionLiveEvents[0].availableTime=1250;g_orbPositionLiveEvents[0].executionDirection="BUY";
   datetime seen=1000;int state=0;
   Check(OrbPositionObservedExit(1000,"BUY",1400,seen,state)==0&&state==1,"combined latest grace state cancels historical latch");
   g_orbPositionLiveEvents[0].availableTime=1450;g_orbPositionLiveEvents[0].executionDirection="SELL";
   seen=1000;state=0;
   Check(OrbPositionObservedExit(1000,"BUY",1500,seen,state)==1300,"combined grace opposite closes at expiry");
   ArrayFree(g_histAcceptedSignals);seen=1000;state=0;
   Check(OrbPositionObservedExit(1000,"BUY",1500,seen,state)==1450,"fresh post-grace event closes");
   ObjectCreate(0,PREFIX+"EDIT_POS_MAX",OBJ_EDIT,0,0,0);
   ObjectCreate(0,PREFIX+"EDIT_POS_WAIT",OBJ_EDIT,0,0,0);
   ObjectSetString(0,PREFIX+"EDIT_POS_MAX",OBJPROP_TEXT,"7");
   ObjectSetString(0,PREFIX+"EDIT_POS_WAIT",OBJPROP_TEXT,"02:30");
   Check(OrbPositionEvent(PREFIX+"BTN_POS_APPLY")&&g_orbPositions.maxSameOpen==7&&g_orbPositions.waitMinutes==150,"Apply uses current edits");
   string packed=OrbPositionPack(g_orbPositions);
   OrbPositionDefaults(g_orbPositions);OrbPositionLoad();
   Check(OrbPositionPack(g_orbPositions)==packed,"runtime restart restores policy");
   OrbPositionDefaults(g_orbPositions);
   g_userLoaded=true;g_userCount=1;ArrayResize(g_userStrategies,1);
   OrbUserRecord fixture;ZeroMemory(fixture);fixture.valid=true;
   OrbCustomCapturePreset(fixture.preset);fixture.preset.id="user_policy_fixture";
   fixture.symbol=_Symbol;fixture.runtime=OrbCustomRuntimeDump();
   g_orbStrategyTimezone=0;fixture.inputSignature=OrbCustomInputSignature();
   fixture.timeMatrix=TCalStrategyOffText();fixture.inverseMaxGapPct=100;
   OrbPositionDefaults(fixture.positions);fixture.positions.independent=true;
   fixture.positions.nextDay=false;fixture.positions.reverse=true;
   fixture.positions.maxSameOpen=7;fixture.positions.waitMinutes=150;
   g_userStrategies[0]=fixture;
   Check(OrbUserApply(fixture.preset)&&OrbPositionPack(g_orbPositions)==OrbPositionPack(fixture.positions),"strategy application restores all policy values");
   OrbPositionDefaults(g_userStrategies[0].positions);
   Check(OrbUserApply(fixture.preset)&&OrbPositionIsDefault(g_orbPositions),"old strategy does not inherit previous filters");
   OrbPositionDraw();ObjectSetString(0,PREFIX+"EDIT_POS_MAX",OBJPROP_TEXT,"23");OrbPositionDraw();
   Check(ObjectGetString(0,PREFIX+"EDIT_POS_MAX",OBJPROP_TEXT)=="23","dashboard refresh preserves unapplied edit");
   g_orbPositions.maxSameOpen=9;g_orbPositions.waitMinutes=45;OrbPositionDraw();
   Check(ObjectGetString(0,PREFIX+"EDIT_POS_MAX",OBJPROP_TEXT)=="9"
      &&ObjectGetString(0,PREFIX+"EDIT_POS_WAIT",OBJPROP_TEXT)=="00:45","strategy policy updates visible fields");
   Check(ObjectGetString(0,PREFIX+"DASH_POS_MAX",OBJPROP_TEXT)=="MAX OPEN","total capacity label");
   CheckMaReference();
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)checks+" failed="+(string)failed);FileClose(f);}
}
