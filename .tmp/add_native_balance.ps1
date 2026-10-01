$ErrorActionPreference='Stop'
function ReplaceOne([string]$text,[string]$old,[string]$new){
 if(([regex]::Matches($text,[regex]::Escape($old))).Count-ne 1){throw "Expected unique fragment: $old"}
 return $text.Replace($old,$new)
}
$entries=@{
 orb='OrbUltimateEA_StrategyLibrary.mq5';macrossover_orb='MaCrossOverOrbEA.mq5';entry_engine_lab='EntryEngineLabEA.mq5'
}
foreach($family in $entries.Keys){
 $path='IndicatorCodeExamples/'+$family+'/'+$entries[$family];$t=[IO.File]::ReadAllText($path)
 $t=ReplaceOne $t '#include <Trade/Trade.mqh>' "#include <Trade/Trade.mqh>`n#include `"NativeRiskBalance.mqh`""
 $match=[regex]::Match($t,'(?m)^double RiskBudgetMoney\(\)\{[^\r\n]+\}')
 if(!$match.Success){throw 'RiskBudgetMoney not found'}
 $original=$match.Value.Replace('RiskBudgetMoney()','AccountRiskBudgetMoney()')
 $wrapper=if($family-eq 'orb'){'double RiskBudgetMoney(){if(NativeBalanceEnabled()&&!g_orbMoneyRisk)return NativeBalanceBudget(g_rtRiskPerTradePct);return AccountRiskBudgetMoney();}'}else{'double RiskBudgetMoney(){return NativeBalanceEnabled()?NativeBalanceBudget(EffRiskPerTradePct()):AccountRiskBudgetMoney();}'}
 $t=ReplaceOne $t $match.Value ($original+"`n"+$wrapper)
 $t=ReplaceOne $t 'return InpAccountRiskEnabled||ManagedRiskMode()||FixedReferenceRiskMode();' 'return NativeBalanceEnabled()||InpAccountRiskEnabled||ManagedRiskMode()||FixedReferenceRiskMode();'
 $t=ReplaceOne $t 'if(!InpUseAutoRiskLot&&!ManagedRiskMode()&&!FixedReferenceRiskMode())' 'if(!InpUseAutoRiskLot&&!ManagedRiskMode()&&!FixedReferenceRiskMode()&&!NativeBalanceEnabled())'
 $t=$t.Replace('return InpFailClosed?0:fallback;','return (NativeBalanceEnabled()||InpFailClosed)?0:fallback;')
 $t=ReplaceOne $t '   double projectedRisk=slMpl*vol;' "   double projectedRisk=slMpl*vol;`n   if(NativeBalanceEnabled()&&NativeBalanceOverBudget(projectedRisk,tradeBudget))`n   {detail=`"reference_balance_min_volume_exceeds_budget`";return 0;}"
 $pnlCheck=if($family-eq 'orb'){'NativeBalanceEnabled()&&!g_orbMoneyRisk'}else{'NativeBalanceEnabled()'}
 $t=ReplaceOne $t "double SimMoneyPnl(double netR)`n{" "double SimMoneyPnl(double netR)`n{`n   if($pnlCheck)return netR*RiskBudgetMoney();"
 $load='   LoadRuntimeRiskPct();';$t=ReplaceOne $t $load ($load+"NativeBalanceLoad(`"$family`");")
 $render=@'
void RenderNativeBalance()
{
   int x=InpDashboardX+644,y=InpDashboardY+530;
   CreateLabel("DASH_NATIVE_BALANCE",x,y+4,"BALANCE (0=ACCOUNT)",C'184,196,210',8);
   CreateEdit("EDIT_NATIVE_BALANCE",x+158,y,108,22,DoubleToString(g_nativeRiskBalance,2));
   CreateButton("BTN_NATIVE_BALANCE",x+274,y,98,22,"APPLY BAL",C'38,101,176');
   CreateLabel("DASH_NATIVE_BUDGET",x,y+29,"NATIVE 1R BUDGET: "+DoubleToString(RiskBudgetMoney(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+" | listener % unchanged",C'80,255,180',8);
   ObjectSetString(0,PREFIX+"EDIT_NATIVE_BALANCE",OBJPROP_TOOLTIP,"Native MT5 percentage-risk reference capital in account currency. 0 restores the existing account basis. MONEY mode takes priority. Future entries only; risk settings stay separate from strategies.");
}

'@
 $t=ReplaceOne $t "void UpdateDashboard()`n{" ($render+"void UpdateDashboard()`n{")
 $t=ReplaceOne $t '   OrbUserDraw();' "   OrbUserDraw();RenderNativeBalance();"
 $apply=@'
   if(sparam==PREFIX+"BTN_NATIVE_BALANCE")
   {
      bool applied=NativeBalanceApply(ObjectGetString(0,PREFIX+"EDIT_NATIVE_BALANCE",OBJPROP_TEXT));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(applied){g_lastExecStatus="NATIVE_BALANCE_APPLIED";CancelHistoricalAuditBuild();QueueHistoricalRedraw(0);}
      else g_lastExecStatus="BALANCE_INVALID_OR_SAVE_FAILED";
      UpdateDashboard();ChartRedraw(0);return;
   }
'@
 $t=ReplaceOne $t '   if(id!=CHARTEVENT_OBJECT_CLICK)return;' ("   if(id!=CHARTEVENT_OBJECT_CLICK)return;`n"+$apply)
 if($family-ne 'orb'){
  # Preserve the existing listener payload budget, not the native override.
  $pipeline='IndicatorCodeExamples/'+$family+'/OrbUltimate_ProfessionalPipeline.mqh'
  $p=[IO.File]::ReadAllText($pipeline).Replace('riskBudgetMoney=RiskBudgetMoney()','riskBudgetMoney=AccountRiskBudgetMoney()')
  [IO.File]::WriteAllText($pipeline,$p,(New-Object Text.UTF8Encoding($false)))
 }
 [IO.File]::WriteAllText($path,$t,(New-Object Text.UTF8Encoding($false)))
}
$path='IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5';$t=[IO.File]::ReadAllText($path)
$t=ReplaceOne $t '#include <Trade/Trade.mqh>' "#include <Trade/Trade.mqh>`n#include `"NativeRiskBalance.mqh`""
$t=ReplaceOne $t 'return InpAccountRiskEnabled || ManagedRiskMode();' 'return NativeBalanceEnabled() || InpAccountRiskEnabled || ManagedRiskMode();'
$t=ReplaceOne $t "double ApproxMoneyFromR(double r)`n{" "double ApproxMoneyFromR(double r)`n{`n   if(NativeBalanceEnabled())return r*NativeBalanceBudget(RiskPerTradePct());"
$t=ReplaceOne $t 'double riskMoney = equity * MathMax(0.01, RiskPerTradePct()) / 100.0;' 'double riskMoney = NativeBalanceEnabled() ? NativeBalanceBudget(RiskPerTradePct()) : equity * MathMax(0.01, RiskPerTradePct()) / 100.0;'
$t=ReplaceOne $t '      double portfolioCap = equity * MathMax(0.01, MaxPortfolioRiskPct()) / 100.0;' "      if(NativeBalanceEnabled()&&NativeBalanceOverBudget(actualRiskMoney,riskMoney))`n      {reason=`"reference_balance_min_volume_exceeds_budget`";return false;}`n      double portfolioCap = equity * MathMax(0.01, MaxPortfolioRiskPct()) / 100.0;"
$t=ReplaceOne $t '   g_riskPerTradePct = ClampRiskPerTradePct(InpRiskPerTradePct);' "   g_riskPerTradePct = ClampRiskPerTradePct(InpRiskPerTradePct);NativeBalanceLoad(`"SolAdvanced`");"
[IO.File]::WriteAllText($path,$t,(New-Object Text.UTF8Encoding($false)))
$path='IndicatorCodeExamples/SolAdvanced/LiqStrategyLibrary.mqh';$t=[IO.File]::ReadAllText($path)
$draw=@'
   if(!g_liqLibraryOpen)
   {
      LiqLibraryWidget("BAL_LABEL",OBJ_LABEL,x+12,y+226,180,20,"BALANCE (0=ACCOUNT)",bg);
      LiqLibraryWidget("BAL_VALUE",OBJ_EDIT,x+198,y+220,100,24,DoubleToString(g_nativeRiskBalance,2),C'38,46,60');
      LiqLibraryWidget("BAL_APPLY",OBJ_BUTTON,x+306,y+220,100,24,"APPLY BAL",button);
      double budget=NativeBalanceEnabled()?NativeBalanceBudget(RiskPerTradePct()):AccountInfoDouble(ACCOUNT_EQUITY)*RiskPerTradePct()/100.0;
      LiqLibraryWidget("BAL_BUDGET",OBJ_LABEL,x+12,y+254,w-24,20,"NATIVE 1R BUDGET: "+DoubleToString(budget,2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+" | listener % unchanged",bg);
      ObjectSetString(0,LiqLibraryObject("BAL_VALUE"),OBJPROP_TOOLTIP,"Native percentage-risk reference capital; 0 restores account sizing. Future entries only. Risk controls remain separate from saved strategies.");
   }
   else {string balanceKeys[]={"BAL_LABEL","BAL_VALUE","BAL_APPLY","BAL_BUDGET"};for(int b=0;b<ArraySize(balanceKeys);b++)ObjectDelete(0,LiqLibraryObject(balanceKeys[b]));}
'@
$t=ReplaceOne $t '   LiqLibraryWidget("SAVE_TITLE",OBJ_LABEL,x+12,y+303,w-24,20,"SAVE CURRENT STRATEGY (APPLY edits first)",bg);' ($draw+"`n"+'   LiqLibraryWidget("SAVE_TITLE",OBJ_LABEL,x+12,y+303,w-24,20,"SAVE CURRENT STRATEGY (APPLY edits first)",bg);')
$apply=@'
   if(action=="BAL_APPLY")
   {
      bool applied=NativeBalanceApply(ObjectGetString(0,LiqLibraryObject("BAL_VALUE"),OBJPROP_TEXT));
      g_liqLibraryStatus=applied?"Native balance applied; listener risk unchanged":"Invalid balance or save failed";
      if(applied)RefreshAfterConfigChange(false);
      LiqLibraryDraw();ChartRedraw(0);return true;
   }
'@
$t=ReplaceOne $t '   if(action=="CLOSE_PANEL")' ($apply+"`n"+'   if(action=="CLOSE_PANEL")')
[IO.File]::WriteAllText($path,$t,(New-Object Text.UTF8Encoding($false)))
