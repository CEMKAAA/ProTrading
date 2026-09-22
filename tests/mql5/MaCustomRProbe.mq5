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
   int checks=0,failed=0;double parsed=0;
   if(!OrbRPickerParse("500",parsed)||parsed!=500.0)failed++;checks++;
   if(!OrbRPickerParse("0.00001",parsed)||MathAbs(parsed-0.00001)>1e-12)failed++;checks++;
   if(OrbRPickerParse("0",parsed)||OrbRPickerParse("nan",parsed))failed++;checks++;
   g_rtTargetLeg=(int)ORB_TARGET_R200;g_rtCustomR=0;
   string legacy=OrbCustomRuntimeDump(),fields[];StringSplit(legacy,'\n',fields);
   g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;g_rtCustomR=500.0;
   if(!OrbCustomRuntimeRead(fields,0,true)||g_rtCustomR!=0||g_rtTargetLeg!=(int)ORB_TARGET_R200)failed++;checks++;
   g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;g_rtCustomR=0.00001;
   string custom=OrbCustomRuntimeDump();StringSplit(custom,'\n',fields);
   g_rtTargetLeg=(int)ORB_TARGET_R100;g_rtCustomR=0;
   if(!OrbCustomRuntimeRead(fields,0,true)||g_rtTargetLeg!=(int)ORB_TARGET_CUSTOM
      ||MathAbs(g_rtCustomR-0.00001)>1e-12)failed++;checks++;
   if(MathAbs(LegR((int)ORB_TARGET_CUSTOM)-0.00001)>1e-12)failed++;checks++;
   g_rtCustomR=500.0;
   if(MathAbs(RuntimeTargetR()-500.0)>1e-10)failed++;checks++;
   OrbStrategyPreset p;OrbCustomCapturePreset(p);
   if(p.targetLeg!=(int)ORB_TARGET_CUSTOM)failed++;checks++;
   CreateButton("BTN_TP",8,8,80,20,"FIX",C'38,101,176');
   OrbRPickerEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"BTN_TP");
   if(!g_orbRPickerOpen||ObjectFind(0,PREFIX+"R_PICK_APPLY")<0)failed++;checks++;
   ObjectSetString(0,PREFIX+"R_PICK_VALUE",OBJPROP_TEXT,"0.00001");
   OrbRPickerEvent(CHARTEVENT_OBJECT_CLICK,PREFIX+"R_PICK_APPLY");
   if(g_orbRPickerOpen||g_rtTargetLeg!=(int)ORB_TARGET_CUSTOM
      ||MathAbs(g_rtCustomR-0.00001)>1e-12)failed++;checks++;
   string path="MaCustomRProbe_roundtrip.tmp",payload="probe\n"+OrbCustomRuntimeDump();
   int file=FileOpen(path,FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(file==INVALID_HANDLE||!OrbMlWriteUtf8(file,payload+OrbMlSha256(payload)+"\n"))failed++;
   if(file!=INVALID_HANDLE)FileClose(file);
   checks++;
   string saved[];
   bool loaded=OrbMlReadLines(path,saved,1+ORB_CUSTOM_RUNTIME_TOKENS+1+1,true);
   if(!loaded||!OrbCustomRuntimeRead(saved,1,false))failed++;checks++;
   FileDelete(path,FILE_COMMON);
   g_rtTargetMode=ORB_TARGET_R_LEG;g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;
   g_rtCustomR=0.00001;
   double price=NormalizeTradePrice(SymbolInfoDouble(_Symbol,SYMBOL_BID)),target=0,riskR=0;
   string shape="";double stop=MathMax(MinStopDistance()*2.0,TickSize()*1000.0);
   if(ResolveSourceTargetPriceAndR(true,price,stop,target,riskR,shape))failed++;checks++;
   g_rtCustomR=1.0;
   if(!ResolveSourceTargetPriceAndR(true,price,stop,target,riskR,shape)
      ||target<=price||MathAbs(riskR-1.0)>1e-10)failed++;checks++;
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}
   Print("MA_CUSTOM_R_PROBE ",result);
}
