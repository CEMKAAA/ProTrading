#property strict
#include "../../IndicatorCodeExamples/orb/TradeCalendarMatrix.mqh"
int checks=0,failures=0;
void Check(bool ok,string label)
{checks++;if(!ok){failures++;Print("DIRECTION_FAIL ",label);}}
void OnStart()
{
   string old="TCAL1=0,16777215,16777215,16777215,16777215,16777215,16777215,16777215";
   Check(TCalInit(),"initialize");
   for(int mode=0;mode<3;mode++)
   {
      Check(TCalStrategyApplyText(old+","+(string)mode),"apply mode");
      Check(EntryDirectionAllows(1)==(mode!=2),"BUY permission");
      Check(EntryDirectionAllows(-1)==(mode!=1),"SELL permission");
      Check(!EntryDirectionAllows(0),"invalid direction fail closed");
      Check(TCalStrategyMatchesText(TCalStrategyText()),"round trip");
      string saved=TCalStrategyText();
      Check(TCalStrategyApplyText(old),"load old strategy");
      Check(g_entryDirection==0,"old strategy resets BOTH");
      Check(TCalStrategyApplyText(saved)&&g_entryDirection==mode,"restore saved direction");
   }
   bool enabled=false;int hours[];
   Check(!TCalStrategyRead(old+",3",enabled,hours),"reject out of range");
   Check(!TCalStrategyRead(old+",garbage",enabled,hours),"reject malformed mode");
   Check(!TCalStrategyRead(old+",1,2",enabled,hours),"reject extra field");
   TCalReset();DirectionRecordLoss(1);DirectionRecordLoss(-1);DirectionRecordLoss(-1);
   Check(g_directionBuyLosses==1&&g_directionSellLosses==2,"split losses");
   Check(g_directionBuyLosses+g_directionSellLosses==3,"loss total");
   TCalReset();Check(g_directionBuyLosses==0&&g_directionSellLosses==0,"reset counters");
   Check(TCalStrategyApplyText(old+",1"),"persist BUY");
   Check(TCalInit()&&g_entryDirection==1,"restart restores chart choice");
   g_tcalPrefix="DIRECTION_PROBE_";
   DirectionLauncher("DIRECTION_PROBE_",10,10);
   Check(TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("DIRECTION"))
      &&g_entryDirection==2&&g_tcalChanged,"button cycles SELL and invalidates audit");
   g_tcalOpen=true;
   Check(TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("DIRECTION"))
      &&g_entryDirection==2,"modal blocks underlying direction button");
   g_tcalOpen=false;
   TCalDestroy();
   Check(TCalStrategyApplyText(old),"restore BOTH");
   int f=FileOpen("EntryDirectionProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE)
   {FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failures));FileClose(f);}
   Print("ENTRY_DIRECTION ",checks," checks ",failures," failures");
}
