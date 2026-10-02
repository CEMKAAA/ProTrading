int nbChecks=0,nbFailed=0;
void NbCheck(bool ok,string message){nbChecks++;if(!ok){nbFailed++;Print("NB_FAIL ",message);}}
void NbChecks()
{
   double parsed=0;
   NbCheck(NativeBalanceParse(" 30,00 ",parsed)&&parsed==30,"decimal parsing");
   NbCheck(NativeBalanceParse("0",parsed)&&parsed==0,"zero restores account basis");
   string invalid[]={"","-1","NaN","30abc","1.2.3","1e300"};
   for(int i=0;i<ArraySize(invalid);i++)NbCheck(!NativeBalanceParse(invalid[i],parsed),"reject "+invalid[i]);
   NbCheck(!NativeBalanceOverBudget(0.30,0.30),"exact budget accepted");
   NbCheck(NativeBalanceOverBudget(0.31,0.30),"minimum volume overshoot rejected");
   NbCheck(NativeBalanceOverBudget(1,0),"zero budget blocks");
   NativeBalanceLoad("PROBE_"+(string)GetTickCount64());
   NbCheck(g_nativeRiskBalance==0,"new chart family has no override");
   NbCheck(NativeBalanceApply("30"),"save reference");
   NbCheck(g_nativeRiskBalance==30&&GlobalVariableGet(g_nativeRiskBalanceKey)==30,"persist applied balance");
   NbCheck(MathAbs(NativeBalanceBudget(1)-MathMin(0.3,MathMax(0.0,AccountInfoDouble(ACCOUNT_BALANCE))))<1e-10,"30 times one percent");
   double saved=g_nativeRiskBalance;NbCheck(!NativeBalanceApply("bad")&&g_nativeRiskBalance==saved,"invalid apply does not mutate state");
   NbCheck(NativeBalanceApply("0")&&!NativeBalanceEnabled(),"disable reference");
}
