#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

void OnStart()
{
   int checks=0,failed=0;
   int init=ProbeInit();
   if(init==INIT_SUCCEEDED)
   {
      g_lnNasDraft=g_lnNas;g_lnNasPanel=true;
      DrawDashboard();
      if(ObjectFind(0,PFX+"DASH_STATE")<0||ObjectFind(0,PFX+"NAS_BG")<0
         ||ObjectFind(0,PFX+"LIB_NAV_LIBRARY")<0)failed++;checks++;
      ObjectSetString(0,PFX+"NAS_SVM",OBJPROP_TEXT,"2.75");
      DrawDashboard();
      if(ObjectFind(0,PFX+"DASH_STATE")<0||ObjectGetString(0,PFX+"NAS_SVM",OBJPROP_TEXT)!="2.75")failed++;checks++;
      RefreshAfterConfigChange(false);UpdateDashboard();
      if(ObjectFind(0,PFX+"DASH_STATE")<0||ObjectFind(0,PFX+"NAS_APPLY")<0)failed++;checks++;
      if(LnNasPanelEvent(CHARTEVENT_OBJECT_CLICK,PFX+"LIB_SEARCH",0,0))failed++;checks++;
      long panelX=ObjectGetInteger(0,PFX+"NAS_BG",OBJPROP_XDISTANCE);
      long panelY=ObjectGetInteger(0,PFX+"NAS_BG",OBJPROP_YDISTANCE);
      if(!LnNasPanelEvent(CHARTEVENT_CLICK,"",panelX+5,(double)(panelY+5)))failed++;checks++;
      if(LnNasPanelEvent(CHARTEVENT_CHART_CHANGE,"",0,0))failed++;checks++;
      long navX=210;double navY=15;
      ProbeEvent(CHARTEVENT_CLICK,navX,navY,"");
      if(g_lnNasPanel||ObjectFind(0,PFX+"DASH_STATE")<0)failed++;checks++;
   }
   string result="{\"init\":"+(string)init+",\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("LiqSolAdvancedUiProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}
   Print("LIQ_UI_PROBE ",result);ProbeDeinit(0);
}
