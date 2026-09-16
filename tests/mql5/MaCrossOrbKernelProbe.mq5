#property strict
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossSignalCore.mqh"

int g_checks=0,g_failed=0;
string g_failures="";
void ProbeCheck(bool ok,string label){g_checks++;if(!ok){g_failed++;g_failures+=label+";";Print("FAIL ",label);}}

void OnStart()
{
   // Every kernel must be callable with the same closed-bar data contract.
   for(int value=0;value<=4;value++)
   {
      MaCrossSignal signal;
      bool ok=MaCrossComputeSignal(_Symbol,PERIOD_M5,(MA_CROSS_SIGNAL_MODE)value,MA_CROSS_PAIR_FAST,9,27,200,signal);
      ProbeCheck(!ok||signal.valid,"mode_"+IntegerToString(value)+" valid_contract");
      if(ok)ProbeCheck(signal.barTime>0&&signal.price>0.0&&MathAbs(signal.direction)==1,
         "mode_"+IntegerToString(value)+" closed_bar_payload");
   }
   int file=FileOpen("MaCrossOrbKernelProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   string result="{\"checks\":"+(string)g_checks+",\"failed\":"+(string)g_failed+",\"failures\":\""+g_failures+"\"}";
   if(file!=INVALID_HANDLE){FileWriteString(file,result);FileClose(file);}
   Print("MACROSS_ORB_KERNEL_PROBE ",result);
}
