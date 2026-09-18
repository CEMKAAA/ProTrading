double probeBalance=10000,probeEquity=9000;
double ProbeAccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE prop)
{return prop==ACCOUNT_BALANCE?probeBalance:(prop==ACCOUNT_EQUITY?probeEquity:0);}
#define AccountInfoDouble ProbeAccountInfoDouble
#define OnInit UnusedInit
#define OnDeinit UnusedDeinit
#define OnTimer UnusedTimer
#define OnTick UnusedTick
#define OnChartEvent UnusedChartEvent
#define OnTradeTransaction UnusedTransaction
#include "../../IndicatorCodeExamples/OrbUltimateEA_StrategyLibrary.mq5"
#undef AccountInfoDouble
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
void Check(bool ok,string description){checks++;if(!ok){failed++;Print("FAIL ",description);}}
void OnStart()
{
 // Pure budget/configuration calls only. No EA init, writes or trading APIs.
 g_rtRiskPerTradePct=0.3;g_orbMoneyRisk=false;
 double pct=BridgeRiskPerTradePct(),budget=BridgeRiskBudgetMoney(),ref=RiskReferenceCapitalForBridge();
 string basis=RiskCapitalBasisCode();
 Check(MathAbs(pct-0.3)<1e-9,"bridge percent");
 g_orbMoneyRisk=true;g_orbMoneyRiskAmount=2000;
 Check(RiskBudgetMoney()==2000,"native amount");
 Check(BridgeRiskPerTradePct()==pct&&BridgeRiskBudgetMoney()==budget,"bridge independent of native money");
 Check(RiskReferenceCapitalForBridge()==ref&&RiskCapitalBasisCode()==basis,"bridge basis unchanged");
 Check(!OrbMoneyInputValid(10001,probeBalance),"above balance rejected");
 g_orbMoneyRiskAmount=0;
 Check(RiskBudgetMoney()==0&&BridgeRiskBudgetMoney()==budget,"invalid native amount cannot block bridge budget");
 g_orbMoneyRiskAmount=2000;probeBalance=1000;
 Check(RiskBudgetMoney()==1000,"balance drop caps budget");
 Check(BridgeRiskBudgetMoney()==budget,"native balance cap does not change bridge policy");
 probeBalance=60.93;g_orbMoneyRiskAmount=60.93;
 Check(RiskBudgetMoney()==60.93&&OrbMoneyInputValid(60.93,60.93),"exact balance accepted");
 Check(!OrbMoneyInputValid(60.94,60.93),"one cent above rejected");
 double v=0;
 Check(OrbParseRiskInput("60,93",v)&&MathAbs(v-60.93)<1e-9,"decimal comma");
 Check(!OrbParseRiskInput("60abc",v),"junk rejected");
 Check(!OrbParseRiskInput("1.2.3",v),"multiple separators rejected");
 Check(!OrbParseRiskInput("-1",v)&&!OrbParseRiskInput("0",v),"nonpositive rejected");
 g_orbMoneyRisk=false;
 Check(BridgeRiskPerTradePct()==pct&&EffRiskPerTradePct()==pct,"percentage restored");
 string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
 int f=FileOpen("OrbNativeMoneyRiskProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
 if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print(result);
}
