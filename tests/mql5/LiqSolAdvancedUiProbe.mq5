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

      LnNasPolicy saved=g_lnNas;
      LnNasEvent event;ZeroMemory(event);
      g_lnNas.gate=1;g_lnNas.exitMode=2;event.flowAllowed=true;
      if(LnNasVisualClass(event)!=3||LnNasVisualLabel(3)!="BOTH")failed++;checks++;
      g_lnNas.gate=2;event.stateAllowed=false;
      if(LnNasVisualClass(event)!=2||LnNasVisualLabel(2)!="EXIT")failed++;checks++;
      event.stateAllowed=true;event.flowAllowed=false;
      if(LnNasVisualClass(event)!=1||LnNasVisualLabel(1)!="STATE")failed++;checks++;
      g_lnNas.gate=1;event.flowAllowed=true;
      if(LnNasVisualClass(event)!=3)failed++;checks++;
      event.flowAllowed=false;
      if(LnNasVisualClass(event)!=0)failed++;checks++;

      g_lnNas.gate=1;g_lnNas.exitMode=0;event.flowAllowed=true;event.dir=1;
      event.at=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,1);
      event.high=iHigh(_Symbol,(ENUM_TIMEFRAMES)_Period,2);
      event.low=iLow(_Symbol,(ENUM_TIMEFRAMES)_Period,2);
      ArrayResize(g_lnNasEvents,1);g_lnNasEvents[0]=event;
      g_lnNasBar=event.at;g_lnNasSeed=1;
      g_lnNasSignature=_Symbol+"|"+(string)_Period+"|"+(string)g_lnNas.sensitivity+"|"
         +(string)g_lnNas.stateVolume+"|"+DoubleToString(g_lnNas.stateMultiplier,8)+"|"
         +(string)g_lnNas.flowVolume+"|"+DoubleToString(g_lnNas.flowMultiplier,8);
      LnNasDrawOverlay(true);
      string marker=PFX+"NASMARK_"+(string)(long)event.at+"_B_ARW";
      if(event.at<=0||ObjectFind(0,marker)<0)failed++;checks++;
      g_lnNas.gate=0;LnNasDrawOverlay(true);
      if(ObjectFind(0,marker)>=0)failed++;checks++;

      ErlSignal candidate;ZeroMemory(candidate);candidate.valid=true;
      candidate.id="nas-reject-probe";candidate.dir=1;candidate.availableTime=event.at;
      ArrayFree(g_lnNasDelayed);g_lnNas.gate=1;g_lnNas.exitMode=0;g_lnNas.reverseWaitMinutes=0;
      if(LnNasNeedsExactTicks(candidate,event.at+3600))failed++;checks++;
      g_lnNas.exitMode=2;
      if(!LnNasNeedsExactTicks(candidate,event.at+3600))failed++;checks++;
      g_lnNas.exitMode=0;ArrayResize(g_lnNasDelayed,1);g_lnNasDelayed[0]=candidate.id;
      if(LnNasNeedsExactTicks(candidate,0))failed++;checks++;
      ArrayFree(g_lnNasDelayed);
      double labelPad=0.0;
      double anchored=HistoricalArrowPrice(event.at,1,event.high+100000.0,100000.0,labelPad);
      double expected=event.low-MathMax((event.high-event.low)*0.20,TickSize()*15.0);
      if(event.low<=0.0||MathAbs(anchored-expected)>TickSize()*0.01)failed++;checks++;

      g_lnNas.gate=2;g_lnNas.exitMode=0;
      g_lnNasEvents[0].at=event.at-60;g_lnNasEvents[0].dir=-1;
      g_lnNasEvents[0].stateAllowed=true;g_lnNasEvents[0].flowAllowed=true;
      ErlSignal candidates[],raw[];ArrayResize(candidates,1);ArrayResize(raw,1);
      candidates[0]=candidate;raw[0]=candidate;
      LnNasFilterHistorical(candidates,raw);
      if(!g_lnNasAuditData||ArraySize(candidates)!=0||ArraySize(g_lnNasRejected)!=1
         ||g_lnNasRejected[0].id!=candidate.id)failed++;checks++;
      DrawHistoricalSignals(false);
      string rejectMarker=PFX+"HIST_NASREJ_0_"+(string)(long)candidate.availableTime;
      if(ObjectFind(0,rejectMarker)<0)failed++;checks++;
      g_lnNas.gate=0;LnNasFilterHistorical(candidates,raw);
      if(ArraySize(g_lnNasRejected)!=0)failed++;checks++;
      DrawHistoricalSignals(false);
      if(ObjectFind(0,rejectMarker)>=0)failed++;checks++;
      g_lnNas=saved;
   }
   string result="{\"init\":"+(string)init+",\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("LiqSolAdvancedUiProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}
   Print("LIQ_UI_PROBE ",result);ProbeDeinit(0);
}
