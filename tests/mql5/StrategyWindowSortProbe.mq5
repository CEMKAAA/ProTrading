#property strict
int sortOrderAttempts=0;
bool SortDenyOrder(const MqlTradeRequest &request,MqlTradeResult &result){sortOrderAttempts++;return false;}
#define OrderSend SortDenyOrder
#define OrderSendAsync SortDenyOrder
#define OnInit SortInit
#define OnDeinit SortDeinit
#define OnTick SortTick
#define OnTimer SortTimer
#define OnChartEvent SortEvent
#define OnTradeTransaction SortTransaction
#include "../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef OrderSend
#undef OrderSendAsync
int sortChecks=0,sortFailed=0;
void SortCheck(bool value,string name)
{sortChecks++;if(!value)sortFailed++;Print(value?"SORT_PASS ":"SORT_FAIL ",name);}
void SortReset(){g_swSortCount=0;ArrayInitialize(g_swDirection,0);ArrayInitialize(g_swOrder,0);}
void OnStart()
{
   SwMetric small,large,better,missing;ZeroMemory(small);ZeroMemory(large);ZeroMemory(better);ZeroMemory(missing);
   small.ready=true;small.total=100;small.wins=99;small.losses=1;
   large.ready=true;large.total=10000;large.wins=9900;large.losses=100;
   better.ready=true;better.total=10;better.wins=10;
   SortCheck(SwWr(small)==99&&SwWr(large)==99,"user 99W/1L and 9900W/100L example");
   SortReset();SwSortCycle(0);SwSortCycle(1);
   SortCheck(g_swSortCount==2&&g_swOrder[0]==0&&g_swOrder[1]==1,"WR first TRADES second");
   SortCheck(SwCompare(large,small)<0&&SwCompare(small,large)>0,"equal WR ranks larger trade sample first");
   SortCheck(SwCompare(better,large)<0,"primary WR priority respected");
   SortCheck(SwSortCaption(0)=="1 WR v"&&SwSortCaption(1)=="2 TRADES v","priority and descending direction visible");
   SwSortCycle(1);SortCheck(SwCompare(small,large)<0&&SwSortCaption(1)=="2 TRADES ^","TRADES direction reverses without disabling WR");
   SwSortCycle(1);SortCheck(g_swSortCount==1&&g_swDirection[1]==0&&SwCompare(small,large)==0,"third click turns criterion OFF");
   SwSortCycle(0);SortCheck(SwCompare(large,better)<0,"WR ascending");
   SortCheck(SwCompare(missing,large)>0,"missing audit never outranks a valid result");
   SortReset();SwSortCycle(2);SortCheck(SwCompare(large,small)<0,"winner count descending");
   SwSortCycle(2);SortCheck(SwCompare(small,large)<0,"winner count ascending");
   SortReset();for(int i=0;i<5;i++)SwSortCycle(i);
   SortCheck(g_swSortCount==5,"five sort criteria coexist");
   SwSortCycle(1);SwSortCycle(1);SwSortCycle(1);
   SortCheck(g_swSortCount==5&&g_swOrder[4]==1&&SwSortCaption(1)=="5 TRADES v","re-enabled criterion joins last priority");
   string labels[]={"2W","5W","10W","20W","1Y","2Y","3Y","4Y","5Y"};
   for(int i=0;i<9;i++)SortCheck(SwWindow(SwWeeks(i))==labels[i],"all nine windows selectable");
   OrbStrategyPreset p;ZeroMemory(p);p.id="sort_probe_"+(string)ChartID()+"_"+(string)TimeLocal();p.name="Window sort fixture";
   string folder="OrbStrategyUserLibrary\\WindowMetrics",key=OrbBuiltinWindowKey(p);
   string five=SwPath(folder,p.id,260),two=SwPath(folder,p.id,2);
   if(FileIsExist(five,FILE_COMMON)||FileIsExist(two,FILE_COMMON))
   {SortCheck(false,"fixture IDs must be unused");return;}
   SortCheck(SwWrite(folder,p.id,key,260,10000,9900,100,0,0,8000,-5,TimeLocal()),"five-year fixture persisted");
   SortCheck(SwWrite(folder,p.id,key,2,100,99,1,0,0,80,-1,TimeLocal()),"two-week fixture persisted independently");
   g_swWeeks=260;OrbBuiltinLoadWindowMetrics(p);OrbStrategyWindowView(p);
   SortCheck(p.metric1yReady&&p.metric1yTotal==10000&&p.metric1yWins==9900,"builtin 5Y readiness survives display preparation");
   string caption=OrbStrategyPresetMetricCaption(p);
   SortCheck(StringFind(caption,"5Y N 10000 LEG")>=0&&StringFind(caption,"WR 99.0%")>=0,"card shows selected window trade count mode and WR");
   g_swWeeks=2;OrbStrategyWindowView(p);
   SortCheck(p.metric1yReady&&p.metric1yTotal==100&&p.metric1yWins==99,"switching window reads its own counts");
   g_swWeeks=208;OrbStrategyWindowView(p);
   SortCheck(!p.metric1yReady&&StringFind(OrbStrategyPresetMetricCaption(p),"4Y N/A")>=0,"missing window never borrows five-year or two-week values");
   FileDelete(five,FILE_COMMON);FileDelete(two,FILE_COMMON);
   FileDelete(five+".lock",FILE_COMMON);FileDelete(two+".lock",FILE_COMMON);
   SortCheck(sortOrderAttempts==0,"no orders requested");
   int f=FileOpen("StrategyWindowSortProbe.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,"checks="+(string)sortChecks+" failed="+(string)sortFailed+" order_attempts="+(string)sortOrderAttempts);FileClose(f);}
}
