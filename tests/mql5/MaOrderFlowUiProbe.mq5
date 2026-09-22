#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

void OnStart()
{
   int checks=0,failed=0;
   McOfInit();
   McOfUiEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"BTN_OF_SETTINGS",0,0);
   if(!g_mcOfUiOpen||ObjectFind(0,PREFIX+"OF_UI_BG")<0)failed++;checks++;
   ObjectSetString(0,PREFIX+"OF_UI_E_AREA",OBJPROP_TEXT,"bad");
   McOfUiEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"OF_UI_APPLY",0,0);
   if(g_mcOf.valueArea!=InpOrderFlowValueArea)failed++;checks++;
   ObjectSetString(0,PREFIX+"OF_UI_E_LOOKBACK",OBJPROP_TEXT,"12");
   ObjectSetString(0,PREFIX+"OF_UI_E_BINS",OBJPROP_TEXT,"16");
   ObjectSetString(0,PREFIX+"OF_UI_E_AREA",OBJPROP_TEXT,"0.65");
   ObjectSetString(0,PREFIX+"OF_UI_E_ACTIVITY",OBJPROP_TEXT,"0");
   ObjectSetString(0,PREFIX+"OF_UI_E_DELTA",OBJPROP_TEXT,"0");
   for(int i=0;i<4;i++)
   {g_mcOfUiLastActionAt=0;McOfUiEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"OF_UI_MODE",0,0);}
   DrawDashboard();
   if(ObjectGetString(0,PREFIX+"OF_UI_E_AREA",OBJPROP_TEXT)!="0.65")failed++;checks++;
   McOfUiEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"OF_UI_APPLY",0,0);
   if(g_mcOf.mode!=MC_OF_PROFILE||g_mcOf.lookback!=12||g_mcOf.bins!=16
      ||MathAbs(g_mcOf.valueArea-0.65)>1e-10||g_mcOf.minActivity!=0||g_mcOf.minDelta!=0)failed++;checks++;
   McOfConfig restored;
   if(!McOfConfigRead(McOfConfigText(g_mcOf),restored)||restored.mode!=MC_OF_PROFILE
      ||restored.lookback!=12||restored.valueArea!=0.65)failed++;checks++;
   if(!McOfUiEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"BTN_PRESET_APPLY",0,0))failed++;checks++;
   McOfUiEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"OF_UI_CLOSE",0,0);
   if(g_mcOfUiOpen||ObjectFind(0,PREFIX+"OF_UI_BG")>=0)failed++;checks++;
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("MaOrderFlowUiProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}
   Print("MA_OF_UI_PROBE ",result);McOfRelease();
}
