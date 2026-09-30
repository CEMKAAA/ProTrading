#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTimer ProbeTimer
#define OnTick ProbeTick
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

void OnStart()
{
   int checks=0,failed=0;
   double pip=OrbPipSize(),bid=150.000;
   g_rtInvertMode=true;
   g_rtTargetLeg=ORB_TARGET_R100;
   g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtPipSlMode=true;
   g_rtPipSlPips=10.0;
   g_rtInverseMaxGapPct=10.0;
   for(int side=0;side<2;side++)
   {
      bool sourceBuy=side==0;
      double ask=bid+0.2*pip;
      double sourceEntry=sourceBuy?ask:bid;
      double inverseEntry=sourceBuy?bid:ask;
      double sourceSl=sourceEntry+(sourceBuy?-10.0:10.0)*pip;
      OrbPureSwapGeometry geometry;
      string detail="";
      bool ok=ResolvePureSwapGeometry(sourceBuy,!sourceBuy,sourceEntry,inverseEntry,sourceSl,geometry,detail);
      checks++;
      if(!ok){failed++;Print("FAIL resolve side=",side," ",detail);continue;}
      checks++;
      if(MathAbs(geometry.execSl-geometry.sourceTp)>TickSize()*0.5
         ||MathAbs(geometry.execTp-geometry.sourceSl)>TickSize()*0.5)
      {failed++;Print("FAIL unquoted preflight levels side=",side);}
      checks++;
      if(MathAbs(geometry.execTargetR-9.8/10.2)>0.0002)
      {failed++;Print("FAIL actual R side=",side," r=",geometry.execTargetR);}
      double sl=0.0,risk=0.0,tp=0.0,rValue=0.0;
      checks++;
      if(!ResolveExecutionStop(sourceBuy,!sourceBuy,inverseEntry,sourceSl,sl,risk,detail,sourceEntry)
         ||!ResolveTargetPriceAndR(!sourceBuy,inverseEntry,risk,tp,rValue,detail,sourceEntry)
         ||MathAbs(sl-geometry.sourceTp)>TickSize()*0.5
         ||MathAbs(tp-(geometry.sourceSl+(sourceBuy?1.0:-1.0)*0.2*pip))>TickSize()*0.5)
      {failed++;Print("FAIL ask-proof execution path side=",side," ",detail);}
      double wideAsk=bid+0.8*pip;
      double wideSource=sourceBuy?wideAsk:bid;
      double wideInverse=sourceBuy?bid:wideAsk;
      double wideSl=wideSource+(sourceBuy?-10.0:10.0)*pip;
      checks++;
      if(ResolvePureSwapGeometry(sourceBuy,!sourceBuy,wideSource,wideInverse,wideSl,geometry,detail,true)
         ||StringFind(detail,"INVERSE_GAP_BLOCK r_floor")!=0)
      {failed++;Print("FAIL 1R floor side=",side," ",detail);}
      checks++;
      if(ResolveExecutionStop(sourceBuy,!sourceBuy,wideInverse,wideSl,sl,risk,detail,wideSource)
         ||StringFind(detail,"INVERSE_GAP_BLOCK r_floor")!=0)
      {failed++;Print("FAIL live 1R floor side=",side," ",detail);}
      g_rtInverseMaxGapPct=1.0;
      checks++;
      if(ResolvePureSwapGeometry(sourceBuy,!sourceBuy,sourceEntry,inverseEntry,sourceSl,geometry,detail,true)
         ||StringFind(detail,"INVERSE_GAP_BLOCK")!=0)
      {failed++;Print("FAIL inverse gap guard side=",side," ",detail);}
      checks++;
      if(ResolveExecutionStop(sourceBuy,!sourceBuy,inverseEntry,sourceSl,sl,risk,detail,sourceEntry)
         ||StringFind(detail,"INVERSE_GAP_BLOCK")!=0)
      {failed++;Print("FAIL live gap guard side=",side," ",detail);}
      g_rtInverseMaxGapPct=10.0;
   }
   int f=FileOpen("OrbLevelSwapProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
