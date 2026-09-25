#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

void OnStart()
{
   int out=FileOpen("SolAdvancedPairedInvertProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(out==INVALID_HANDLE)return;
   FileWrite(out,"invert","signal_time","source_direction","status");
   for(int retry=0;retry<60&&!TerminalInfoInteger(TERMINAL_CONNECTED);retry++)Sleep(500);
   if(ProbeInit()!=INIT_SUCCEEDED)
   {FileWrite(out,"ERROR","INIT");FileClose(out);return;}
   g_eaEnabled=false;g_fileBridgeEnabled=false;g_histWeeks=2;
   g_lnNas.gate=0;g_lnNas.exitMode=0;g_lnNas.independent=false;
   g_lnNas.reverseExit=false;
   double entry=SymbolInfoDouble(_Symbol,SYMBOL_BID),point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   for(int direction=0;direction<2;direction++)
   {
      ErlSignal source,inverse;ZeroMemory(source);
      source.dir=direction==0?1:-1;source.entry=NormTradePrice(entry);
      source.sl=NormTradePrice(entry-source.dir*1000*point);
      source.risk=MathAbs(source.entry-source.sl);
      SetSignalTargetLadder(source);
      string why="";double target=SelectedTarget(source,g_target,ERL_TARGET_FIXED_R);
      bool ok=ApplyFullInversionGeometry(source,g_target,ERL_TARGET_FIXED_R,inverse,why);
      if(!ok||MathAbs(inverse.sl-target)>TickSize()*0.5
         ||MathAbs(inverse.targetOverride-source.sl)>TickSize()*0.5)
      {FileWrite(out,"ERROR","SWAP",direction,why);ProbeDeinit(0);FileClose(out);return;}
   }
   for(int invert=0;invert<2;invert++)
   {
      g_invertMode=invert!=0;
      RecalculateHistoricalStats(false);
      for(int i=0;i<ArraySize(g_histSignals);i++)
         FileWrite(out,invert,(long)g_histSignals[i].availableTime,g_histSignals[i].dir,
            g_histSignalValid[i]?"valid":"data");
      FileWrite(out,"SUMMARY",invert,ArraySize(g_histSignals),g_hist.netR);
      FileFlush(out);
   }
   if(ArraySize(g_histSignals)>1)
   {
      g_lnNas.independent=true;g_lnNas.maxSameOpen=1;g_invertMode=true;
      g_histSignals[0].dir=1;g_histSignals[1].dir=1;
      g_histSignals[0].availableTime=100;g_histSignals[1].availableTime=200;
      g_histSignalValid[0]=true;g_histSignalClosed[0]=true;
      g_histSignalExitTime[0]=150;g_histSignalInvalidReason[0]="";
      g_lnNasSourceValid[0]=true;g_lnNasSourceClosed[0]=true;
      g_lnNasSourceExitTime[0]=250;
      FileWrite(out,"CAP",LnNasAuditCap(1)==1?"PASS":"FAIL");
   }
   ProbeDeinit(0);
   FileClose(out);
}
