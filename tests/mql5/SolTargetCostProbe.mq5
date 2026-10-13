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
datetime ProbeNow(){return D'2025.10.27 08:00';}
int ProbeNoQuotes(string symbol,MqlTick &ticks[],uint flags,ulong from=0,ulong to=0){ArrayResize(ticks,0);return 0;}
#define TimeCurrent ProbeNow
#define CopyTicksRange ProbeNoQuotes
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#include "SolBefore.mqh"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef TimeCurrent
#undef CopyTicksRange
#undef ChartGetInteger
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("TARGET COST FAIL: ",label," ",g_lastSimInvalidReason);}}
#include "TargetCostGateChecks.mqh"
void OnStart()
{
   CheckTargetCostMath();g_invertMode=false;g_pipSlMode=false;g_slDistancePct=100;g_slBufferAtrPct=0;
   for(int day=0;day<7;day++)g_tcalDayHours[day]=16777215;
   g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btSameBarPolicy=BT_SAMEBAR_CONSERVATIVE;
   g_btSpreadPts=10;g_btSlippagePts=0;g_btCommissionPerLot=0;g_customTargetR=0.01;LnNasDefaults(g_lnNas);g_lnNas.reverseExit=false;
   ArraySetAsSeries(g_simRates,true);int n=CopyRates(_Symbol,PERIOD_M5,D'2025.10.20 07:00',ProbeNow(),g_simRates);
   g_simRatesTf=PERIOD_M5;g_simRatesLatestBar=iTime(_Symbol,PERIOD_M5,0);g_simRatesOldestBar=n>0?g_simRates[n-1].time:0;
   Check(n>50,"recorded bar fixture ready");
   for(int i=n-12;i>n-36&&i>0;i--)for(int side=0;side<2;side++)
   {
      ErlSignal sig;ZeroMemory(sig);sig.valid=true;sig.dir=side==0?1:-1;sig.entryTime=g_simRates[i].time;
      sig.availableTime=g_simRates[i-1].time;sig.entry=g_simRates[i-1].open;sig.risk=0.5;
      sig.sl=sig.entry-sig.dir*sig.risk;sig.id="cost"+(string)i+(string)side;SetSignalTargetLadder(sig);
      bool c,w,v,oc,ow,ov;TpCostSet(false,20);
      double a=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,0,c,w,v);
      datetime exit=g_lastSimExitTime;double entry=g_lastSimExecEntry,stop=g_lastSimExecSl,target=g_lastSimExecTp;
      double b=BeforeSimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,0,oc,ow,ov);
      Check(a==b&&c==oc&&w==ow&&v==ov&&exit==g_lastSimExitTime&&entry==g_lastSimExecEntry
         &&stop==g_lastSimExecSl&&target==g_lastSimExecTp,"filter OFF matches pre-change complete simulation");
      TpCostSet(true,0);a=SimulateSignal(sig,ERL_RR_CUSTOM,ERL_HC_OFF,ERL_TARGET_FIXED_R,PERIOD_M5,0,c,w,v);
      Check(!v&&!c&&a==0&&g_lastSimInvalidReason=="COST_TP_BLOCK","bar entry is rejected before future outcome");
   }
   ArrayResize(g_histSignals,2);ArrayResize(g_histSignalInvalidReason,2);ArrayResize(g_histSignalValid,2);
   ArrayResize(g_histSignalClosed,2);ArrayResize(g_histSignalExitTime,2);
   g_histSignals[0].dir=1;g_histSignals[0].availableTime=100;g_histSignals[1].dir=-1;g_histSignals[1].availableTime=200;
   g_histSignalInvalidReason[0]="COST_TP_BLOCK";g_histSignalValid[0]=false;
   g_lnNas.independent=true;g_lnNas.maxSameOpen=1;
   Check(LnNasAuditCap(1)==0,"cost rejection consumes no Independent slot and is not MAX DATA");
   LnNasDefaults(g_lnNas);g_target=ERL_RR_CUSTOM;g_targetModel=ERL_TARGET_FIXED_R;g_customTargetR=0.01;
   g_htf=PERIOD_H4;g_entryTf=PERIOD_M5;g_swingLookback=20;g_histWeeks=2;
   g_eaEnabled=false;g_fileBridgeEnabled=false;g_auditRuntime=false;
   string prefix="__TARGET_COST_"+(string)GetTickCount64();
   TpCostSet(true,17.125);Check(LiqLibrarySave(prefix+"ON"),"save Sol ON strategy");string onPath=LiqLibraryPath(prefix+"ON");
   TpCostSet(false,20);Check(LiqLibrarySave(prefix+"OLD"),"save Sol old-compatible OFF strategy");string offPath=LiqLibraryPath(prefix+"OLD");
   string name="";double values[];
   bool decoded=LiqLibraryUnpack(onPath,name,values);
   if(!decoded){string record="";LiqLibraryRead(onPath,record);Print("COST_SOL_RECORD\n",record);}
   Check(decoded,"new Sol policy file validates");
   Check(LiqLibraryUnpack(offPath,name,values),"old-compatible Sol policy file validates");
   TpCostSet(false,70);Check(LiqLibraryApply(onPath)&&g_tpCostEnabled&&g_tpCostMaxPct==17.125,"Sol full Apply restores ON policy");
   Check(LiqLibraryApply(offPath)&&!g_tpCostEnabled&&g_tpCostMaxPct==20,"Sol old strategy does not inherit preceding cost gate");
   FileDelete(onPath,FILE_COMMON);FileDelete(offPath,FILE_COMMON);FileDelete(onPath+".lock",FILE_COMMON);FileDelete(offPath+".lock",FILE_COMMON);
   g_liqLibrarySelected="";g_liqLibraryPanel=true;g_liqLibraryOpen=false;g_liqLibraryRPicker=false;
   LiqLibraryDraw();string value=TpCostObject(PFX,"VALUE"),toggle=TpCostObject(PFX,"ON"),apply=TpCostObject(PFX,"APPLY");
   Check(ObjectFind(0,value)>=0&&ObjectFind(0,apply)>=0,"Sol right-panel controls exist");
   long clickX=0;double clickY=0.0;
   ObjectSetString(0,value,OBJPROP_TEXT,"12.75");ProbeEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,toggle);
   Check(g_tpCostEnabled&&g_tpCostMaxPct==12.75,"Sol dashboard toggle reads current editor");
   ObjectSetString(0,value,OBJPROP_TEXT,"7.25");ProbeEvent(CHARTEVENT_OBJECT_CLICK,clickX,clickY,apply);
   Check(g_tpCostEnabled&&g_tpCostMaxPct==7.25,"Sol Apply reads current editor");
   ChartScreenShot(0,"SolTargetCostProbe.png",1600,950,ALIGN_LEFT);
   int f=FileOpen("SolTargetCostProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(f);}
}
