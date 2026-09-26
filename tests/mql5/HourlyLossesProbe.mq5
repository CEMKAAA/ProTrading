#property strict
#include "../../IndicatorCodeExamples/orb/TradeCalendarMatrix.mqh"
int checks=0,failed=0;
void Check(bool ok,string name){checks++;if(!ok){failed++;Print("HOURLY_FAIL ",name);}}
void OnStart()
{
   Check(TCalInit(),"initialize");TCalReset();
   TCalRecord(D'2026.09.21 00:30',-1);
   TCalRecord(D'2026.09.22 00:10',-0.4);
   TCalRecord(D'2026.09.21 01:00',-1);
   TCalRecord(D'2026.09.21 00:35',1);
   TCalRecord(D'2026.09.21 02:35',0);
   TCalRecordOutcome(D'2026.09.21 23:59',false);
   Check(LossHoursCount(0)==2,"aggregate same hour across days");
   Check(LossHoursCount(1)==1,"exact hour boundary");
   Check(LossHoursCount(2)==0,"flat and empty slots");
   Check(LossHoursCount(23)==1,"last hour");
   Check(LossHoursCount(-1)==0&&LossHoursCount(24)==0,"range guard");
   int total=0;for(int h=0;h<24;h++)total+=LossHoursCount(h);
   Check(total==4,"sum equals recorded losses");
   string settings=TCalStrategyText();
   g_tcalChanged=false;
   LossHoursLauncher("HOURLY_PROBE_",10,10);
   Check(LossHoursEvent(CHARTEVENT_OBJECT_CLICK,TCalId("LOSS_HOURS"))&&g_lossHoursOpen,"open panel");
   Check(!g_tcalChanged&&TCalStrategyText()==settings,"no filter mutation or audit request");
   Check(ObjectGetString(0,TCalId("LOSSMOD_H_23"),OBJPROP_TEXT)=="23-24  :  1 L","24-hour label");
   Check(LossHoursEvent(CHARTEVENT_OBJECT_CLICK,TCalId("DIRECTION"))&&!g_tcalChanged&&TCalStrategyText()==settings,"underlying clicks consumed");
   Check(LossHoursEvent(CHARTEVENT_OBJECT_CLICK,TCalId("LOSSMOD_CLOSE"))&&!g_lossHoursOpen,"close panel");
   g_tcalOpen=true;
   Check(!LossHoursEvent(CHARTEVENT_OBJECT_CLICK,TCalId("LOSS_HOURS"))&&!g_lossHoursOpen,"other modal blocks opening");
   g_tcalOpen=false;TCalReset();
   Check(LossHoursCount(0)==0&&LossHoursCount(23)==0,"reset with audit window");
   TCalDestroy();
   int f=FileOpen("HourlyLossesProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
