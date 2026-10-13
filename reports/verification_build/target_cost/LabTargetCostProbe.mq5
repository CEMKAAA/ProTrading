#property strict
long ProbeChartSize(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub=0)
{if(prop==CHART_WIDTH_IN_PIXELS)return 1600;if(prop==CHART_HEIGHT_IN_PIXELS)return 950;return ChartGetInteger(chart,prop,sub);}
bool ProbeChartSize(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub,long &value)
{value=ProbeChartSize(chart,prop,sub);return true;}
#define ChartGetInteger ProbeChartSize
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem/IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5"
#include "LabBefore.mqh"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef ChartGetInteger
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("TARGET COST FAIL: ",label);}}
#define PROBE_IMAGE "LabTargetCostProbe.png"
#include "TargetCostGateChecks.mqh"
#include "OrbTargetCostChecks.mqh"
void OnStart(){CheckOrbTargetCost();int f=FileOpen("LabTargetCostProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}}