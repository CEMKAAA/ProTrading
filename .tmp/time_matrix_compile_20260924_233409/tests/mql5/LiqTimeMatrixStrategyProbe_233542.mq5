#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("FAIL ",label," ",g_liqLibraryStatus);}}
void OnStart()
{
   int init=ProbeInit();
   Check(init==INIT_SUCCEEDED,"EA initialization");
   if(init==INIT_SUCCEEDED)
   {
      string wanted="TCAL1=1,0,64,8192,0,0,0,0";
      Check(TCalStrategyApplyText(wanted),"set per-day hours");
      string name="__LIQ_TCAL_PROBE_"+(string)GetTickCount64();
      Check(LiqLibrarySave(name),"save strategy");
      string path=LiqLibraryPath(name),readName="";double values[];
      Check(LiqLibraryUnpack(path,readName,values)&&readName==name,"read saved strategy");
      string fileText="";
      Check(LiqLibraryRead(path,fileText)&&StringFind(fileText,wanted)>=0,"file contains time matrix");
      Check(TCalStrategyApplyText(TCalStrategyOffText()),"clear current filter");
      Check(LiqLibraryApply(path),"apply saved strategy");
      Check(TCalStrategyMatchesText(wanted),"restore exact schedule");
      FileDelete(path,FILE_COMMON);
      ProbeDeinit(0);
   }
   string payload=StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed);
   int file=FileOpen("LiqTimeMatrixStrategyProbe_233542.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,payload);FileClose(file);}
   Print(payload);
}
