#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTick ProbeTick
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnChartEvent
#undef OnTick
#undef OnTradeTransaction

void OnStart()
{
   int checks=0,failed=0;
   double pip=PipSize(),bid=150.000;
   g_invertMode=true;
   g_pipSlMode=true;
   g_pipSlPips=10.0;
   g_target=ERL_RR_TP2;
   g_targetModel=ERL_TARGET_FIXED_R;
   g_inverseMaxGapPct=10.0;
   for(int side=0;side<2;side++)
   {
      ErlSignal source,inverse;
      ZeroMemory(source);
      source.dir=side==0?1:-1;
      double ask=bid+0.2*pip;
      source.entry=NormTradePrice(source.dir>0?ask:bid);
      source.sl=NormTradePrice(source.entry-source.dir*10*pip);
      source.risk=MathAbs(source.entry-source.sl);
      SetSignalTargetLadder(source);
      double sourceTarget=SelectedTarget(source,ERL_RR_TP2,ERL_TARGET_FIXED_R);
      double inverseEntry=NormTradePrice(source.dir>0?bid:ask);
      string detail="";
      bool ok=ApplyFullInversionGeometry(source,ERL_RR_TP2,ERL_TARGET_FIXED_R,inverse,detail,inverseEntry);
      checks++;
      if(!ok){failed++;Print("FAIL resolve side=",side," ",detail);continue;}
      checks++;
      if(MathAbs(inverse.sl-sourceTarget)>TickSize()*0.5
         ||MathAbs(inverse.targetOverride-(source.sl+source.dir*0.2*pip))>TickSize()*0.5)
      {failed++;Print("FAIL ask-proof levels side=",side);}
      checks++;
      double actualR=MathAbs(inverse.targetOverride-inverse.entry)/inverse.risk;
      if(MathAbs(actualR-9.6/10.2)>0.0002)
      {failed++;Print("FAIL actual R side=",side," r=",actualR);}
      ErlSignal live;
      checks++;
      if(!BuildExecutableSignal(source,inverseEntry,source.entry,live,detail)
         ||MathAbs(live.entry-inverseEntry)>TickSize()*0.5
         ||MathAbs(live.sl-sourceTarget)>TickSize()*0.5
         ||MathAbs(live.targetOverride-(source.sl+source.dir*0.2*pip))>TickSize()*0.5)
      {failed++;Print("FAIL live execution side=",side," ",detail);}
      int simDir=0;double simSl=0.0,simTp=0.0,half=0.0,simRisk=0.0,commission=0.0;
      ERL_HC_MODE activeHc=ERL_HC_OFF;
      checks++;
      if(!ConfigureSimulationLevels(source,g_target,ERL_HC_OFF,g_targetModel,
         inverseEntry,source.entry,false,simDir,simSl,simTp,half,simRisk,activeHc,commission,detail)
         ||MathAbs(simSl-sourceTarget)>TickSize()*0.5
         ||MathAbs(simTp-(source.sl+source.dir*0.2*pip))>TickSize()*0.5)
      {failed++;Print("FAIL audit geometry side=",side," ",detail);}
      ErlSignal wide=source;
      double wideAsk=bid+0.8*pip;
      wide.entry=NormTradePrice(wide.dir>0?wideAsk:bid);
      wide.sl=NormTradePrice(wide.entry-wide.dir*10*pip);
      wide.risk=MathAbs(wide.entry-wide.sl);
      SetSignalTargetLadder(wide);
      double wideInverse=NormTradePrice(wide.dir>0?bid:wideAsk);
      checks++;
      if(ApplyFullInversionGeometry(wide,ERL_RR_TP2,ERL_TARGET_FIXED_R,inverse,detail,wideInverse)
         ||StringFind(detail,"INVERSE_GAP_BLOCK r_floor")!=0)
      {failed++;Print("FAIL 1R floor side=",side," ",detail);}
      checks++;
      if(BuildExecutableSignal(wide,wideInverse,wide.entry,live,detail)
         ||StringFind(detail,"INVERSE_GAP_BLOCK r_floor")<0)
      {failed++;Print("FAIL live 1R floor side=",side," ",detail);}
      g_inverseMaxGapPct=1.0;
      checks++;
      if(ApplyFullInversionGeometry(source,ERL_RR_TP2,ERL_TARGET_FIXED_R,inverse,detail,inverseEntry)
         ||StringFind(detail,"INVERSE_GAP_BLOCK")!=0)
      {failed++;Print("FAIL inverse gap guard side=",side," ",detail);}
      checks++;
      if(BuildExecutableSignal(source,inverseEntry,source.entry,live,detail)
         ||StringFind(detail,"INVERSE_GAP_BLOCK")<0)
      {failed++;Print("FAIL live gap guard side=",side," ",detail);}
      checks++;
      if(ConfigureSimulationLevels(source,g_target,ERL_HC_OFF,g_targetModel,
         inverseEntry,source.entry,false,simDir,simSl,simTp,half,simRisk,activeHc,commission,detail)
         ||StringFind(detail,"INVERSE_GAP_BLOCK")!=0)
      {failed++;Print("FAIL audit gap guard side=",side," ",detail);}
      g_inverseMaxGapPct=10.0;
   }
   int f=FileOpen("SolAdvancedLevelSwapProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
