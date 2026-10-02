#define NM_LAB
#property strict
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTick UnusedTick
#define OnTimer UnusedTimer
#define OnChartEvent BalanceChartEvent
#define OnTradeTransaction UnusedTransaction
// UI viewport fixture for the hidden worker. Market data/APIs are unchanged.
long NmViewport(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub=0)
{if(prop==CHART_WIDTH_IN_PIXELS)return 1600;if(prop==CHART_HEIGHT_IN_PIXELS)return 900;return ChartGetInteger(chart,prop,sub);}
bool NmViewport(long chart,ENUM_CHART_PROPERTY_INTEGER prop,int sub,long &value)
{value=NmViewport(chart,prop,sub);return true;}
#define ChartGetInteger NmViewport
#include "EntryEngineLabEA.mq5"
#include "NativeBalanceChecks.mqh"
#include "NativeMarginChecks.mqh"
#include "PipCeilingChecks.mqh"
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
   NbChecks();
   g_rtRiskPerTradePct=1.0;g_nativeRiskBalance=0;
double bridge=AccountRiskBudgetMoney();
   double baseline=RiskBudgetMoney(),baselineMoney=SimMoneyPnl(2);
   NbCheck(baseline==AccountRiskBudgetMoney(),"default budget parity");
   g_nativeRiskBalance=30;
   NbCheck(MathAbs(RiskBudgetMoney()-NativeBalanceBudget(1))<1e-10,"native reference budget");
   NbCheck(MathAbs(SimMoneyPnl(2)-2*RiskBudgetMoney())<1e-10,"audit reference money");
   NbCheck(AccountRiskBudgetMoney()==bridge,"listener budget unchanged");NbCheck(RiskEnabled(),"reference enables risk sizing");
   g_nativeRiskBalance=0;NbCheck(SimMoneyPnl(2)==baselineMoney,"default audit money parity");
   OrbLibraryRefreshLayout();RenderNativeBalance();
   string edit=PREFIX+"EDIT_NATIVE_BALANCE",button=PREFIX+"BTN_NATIVE_BALANCE";
   NbCheck(ObjectFind(0,edit)>=0&&ObjectFind(0,button)>=0,"balance UI visible");
   ObjectSetString(0,edit,OBJPROP_TEXT,"30");RenderNativeBalance();
   NbCheck(ObjectGetString(0,edit,OBJPROP_TEXT)=="30"&&g_nativeRiskBalance==0,"draft not reset or applied");
   long x=ObjectGetInteger(0,button,OBJPROP_XDISTANCE)+4;double y=(double)ObjectGetInteger(0,button,OBJPROP_YDISTANCE)+4;
   BalanceChartEvent(CHARTEVENT_OBJECT_CLICK,x,y,button);
   NbCheck(g_nativeRiskBalance==30,"actual main click apply route");
   NmChecks();PcChecks();ChartScreenShot(0,"NbProbe_entry_engine_lab_0ff22d32.png",1600,900);
   GlobalVariableDel(g_nativeRiskBalanceKey);EventKillTimer();
   int report=FileOpen("NbProbe_entry_engine_lab_0ff22d32.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(report!=INVALID_HANDLE){FileWriteString(report,"checks="+(string)nbChecks+" failed="+(string)nbFailed+"\n");FileClose(report);}
}