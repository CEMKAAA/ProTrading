$ErrorActionPreference = 'Stop'

function Replace-One([string]$Text, [string]$Old, [string]$New, [string]$File) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -eq 0) {
        $oldLf = $Old.Replace("`r`n", "`n")
        $newLf = $New.Replace("`r`n", "`n")
        $count = ([regex]::Matches($Text, [regex]::Escape($oldLf))).Count
        if ($count -eq 1) { $Old = $oldLf; $New = $newLf }
    }
    if ($count -eq 0) {
        $oldCrLf = $Old.Replace("`r`n", "`n").Replace("`n", "`r`n")
        $newCrLf = $New.Replace("`r`n", "`n").Replace("`n", "`r`n")
        $count = ([regex]::Matches($Text, [regex]::Escape($oldCrLf))).Count
        if ($count -eq 1) { $Old = $oldCrLf; $New = $newCrLf }
    }
    if ($count -ne 1) { throw "Expected one occurrence in $File, found ${count}: $Old" }
    return $Text.Replace($Old, $New)
}

$files = @(
    'IndicatorCodeExamples\OrbUltimateEA.mq5',
    'IndicatorCodeExamples\OrbUltimateEA_Channel.mq5',
    'IndicatorCodeExamples\A05OrbEA.mq5',
    'IndicatorCodeExamples\A10OrbEA.mq5',
    'IndicatorCodeExamples\N10OrbEA.mq5',
    'IndicatorCodeExamples\Q10OrbEA.mq5'
)

foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file)
    $text = Replace-One $text @'
enum ORB_SESSION_PROFILE
{
   ORB_SESSION_AUTO=0,
   ORB_SESSION_US=1,
   ORB_SESSION_EU_CET=2,
   ORB_SESSION_UK=3,
   ORB_SESSION_HK=4,
   ORB_SESSION_JP=5,
   ORB_SESSION_MANUAL_NY=6
};
'@ @'
enum ORB_SESSION_PROFILE
{
   ORB_SESSION_AUTO=0,
   ORB_SESSION_US=1,
   ORB_SESSION_EU_CET=2,
   ORB_SESSION_UK=3,
   ORB_SESSION_HK=4,
   ORB_SESSION_JP=5,
   ORB_SESSION_MANUAL_NY=6
};

enum ORB_RISK_CAPITAL_MODE
{
   ORB_RISK_CURRENT_EQUITY=0,
   ORB_RISK_FIXED_REFERENCE=1
};
'@ $file

    $text = Replace-One $text 'input double InpRiskPerTradePct  =' 'input ORB_RISK_CAPITAL_MODE InpRiskCapitalMode = ORB_RISK_CURRENT_EQUITY;`r`ninput double InpFixedRiskReferenceCapital = 0.0; // Required when fixed-reference mode is selected.`r`ninput double InpFixedRiskMaxOvershootMoney = 1.0; // Post-fill absolute account-currency ceiling.`r`ninput double InpRiskPerTradePct  =' $file
    $text = $text.Replace('`r`n', "`r`n")

    $text = Replace-One $text @'
bool RiskEnabled(){return InpAccountRiskEnabled||ManagedRiskMode();}
'@ @'
bool FixedReferenceRiskMode(){return InpRiskCapitalMode==ORB_RISK_FIXED_REFERENCE;}
double RiskSizingCapital(){return FixedReferenceRiskMode()?(InpFixedRiskReferenceCapital>0.0?InpFixedRiskReferenceCapital:0.0):MathMax(0.0,AccountInfoDouble(ACCOUNT_EQUITY));}
double RiskReferenceCapitalForBridge(){return FixedReferenceRiskMode()?MathMax(0.0,InpFixedRiskReferenceCapital):0.0;}
string RiskCapitalBasisCode(){return FixedReferenceRiskMode()?"FIXED_REFERENCE":"CURRENT_EQUITY";}
bool RiskEnabled(){return InpAccountRiskEnabled||ManagedRiskMode()||FixedReferenceRiskMode();}
'@ $file

    $text = Replace-One $text @'
double EffRiskPerTradePct(){return ClampRiskPerTradePct(g_rtRiskPerTradePct);}
'@ @'
double EffRiskPerTradePct(){return ClampRiskPerTradePct(g_rtRiskPerTradePct);}
double RiskBudgetMoney(){double capital=RiskSizingCapital();return capital>0.0?capital*MathMax(0.01,EffRiskPerTradePct())/100.0:0.0;}
'@ $file

    $text = Replace-One $text @'
double CalculateLot(double entry,double sl){if(!InpUseAutoRiskLot&&!ManagedRiskMode())return NormalizeVolume(InpFixedLot);double rd=MathAbs(entry-sl);double vpu=ValuePerPriceUnitPerLot();double eq=AccountInfoDouble(ACCOUNT_EQUITY);double rm=eq*MathMax(0.01,EffRiskPerTradePct())/100.0;if(rd<=0||vpu<=0||rm<=0)return NormalizeVolume(InpFixedLot);return NormalizeVolume(rm/(rd*vpu));}
'@ @'
double CalculateLot(double entry,double sl){if(!InpUseAutoRiskLot&&!ManagedRiskMode()&&!FixedReferenceRiskMode())return NormalizeVolume(InpFixedLot);double rd=MathAbs(entry-sl);double vpu=ValuePerPriceUnitPerLot();double rm=RiskBudgetMoney();if(rd<=0||vpu<=0||rm<=0)return FixedReferenceRiskMode()?0.0:NormalizeVolume(InpFixedLot);return NormalizeVolume(rm/(rd*vpu));}
'@ $file

    $text = Replace-One $text @'
   double base=InpInitialBalanceOverride>0?InpInitialBalanceOverride:MathMax(0.01,AccountInfoDouble(ACCOUNT_BALANCE));
'@ @'
   double base=FixedReferenceRiskMode()?MathMax(0.01,InpFixedRiskReferenceCapital):(InpInitialBalanceOverride>0?InpInitialBalanceOverride:MathMax(0.01,AccountInfoDouble(ACCOUNT_BALANCE)));
'@ $file

    $text = Replace-One $text @'
   double tradeBudget=cap*MathMax(0,EffRiskPerTradePct())/100.0;
   double atrBudget=cap*MathMax(0,EffAtrExposurePct())/100.0;
   double portfolioBudget=cap*MathMax(0,EffMaxPortfolioPct())/100.0;
   double avail=MathMax(0,portfolioBudget-OpenScopeRisk());
   if(tradeBudget<=0||atrBudget<=0||avail<=0){detail="budget_exhausted";return 0;}
   double raw=MathMin(tradeBudget/slMpl,MathMin(atrBudget/atrMpl,avail/slMpl));
   double vol=NormalizeVolume(raw);
'@ @'
   double tradeBudget=RiskBudgetMoney();
   if(FixedReferenceRiskMode()&&tradeBudget<=0.0){detail="fixed_reference_capital_invalid";return 0;}
   double atrBudget=cap*MathMax(0,EffAtrExposurePct())/100.0;
   double portfolioBudget=cap*MathMax(0,EffMaxPortfolioPct())/100.0;
   double avail=MathMax(0,portfolioBudget-OpenScopeRisk());
   if(tradeBudget<=0||(!FixedReferenceRiskMode()&&(atrBudget<=0||avail<=0))){detail="budget_exhausted";return 0;}
   double raw=FixedReferenceRiskMode()?tradeBudget/slMpl:MathMin(tradeBudget/slMpl,MathMin(atrBudget/atrMpl,avail/slMpl));
   double vol=NormalizeVolume(raw);
   double projectedRisk=slMpl*vol;
   if(FixedReferenceRiskMode()&&projectedRisk>tradeBudget+MathMax(0.0,InpFixedRiskMaxOvershootMoney))
   {detail="fixed_reference_min_volume_exceeds_budget projected="+DoubleToString(projectedRisk,2)+" budget="+DoubleToString(tradeBudget,2);return 0;}
'@ $file

    $text = Replace-One $text @'
double ClosedDailyAtr(){int h=iATR(_Symbol,PERIOD_D1,MathMax(2,InpAtrPeriod));if(h==INVALID_HANDLE)return 0;double v[];ArraySetAsSeries(v,true);int c=CopyBuffer(h,0,1,1,v);IndicatorRelease(h);return(c==1&&v[0]>0)?v[0]:0;}
'@ @'
double OwnFixedRiskMoney()
{
   double risk=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),volume=PositionGetDouble(POSITION_VOLUME),result=0.0;
      if(sl<=0.0||volume<=0.0)return -1.0;
      ENUM_ORDER_TYPE side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(!OrderCalcProfit(side,_Symbol,volume,entry,sl,result))return -1.0;
      risk+=MathAbs(result);
   }
   return risk;
}
bool ValidateFixedReferencePostFill(string &detail)
{
   if(!FixedReferenceRiskMode())return true;
   double budget=RiskBudgetMoney(),actual=OwnFixedRiskMoney(),maximum=budget+MathMax(0.0,InpFixedRiskMaxOvershootMoney);
   detail="fixed_reference_post_fill actual="+DoubleToString(actual,2)+" budget="+DoubleToString(budget,2)+" maximum="+DoubleToString(maximum,2);
   if(budget>0.0&&actual>=0.0&&actual<=maximum)return true;
   for(int i=PositionsTotal()-1;i>=0;i--){ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;trade.PositionClose(ticket);}
   return false;
}

double ClosedDailyAtr(){int h=iATR(_Symbol,PERIOD_D1,MathMax(2,InpAtrPeriod));if(h==INVALID_HANDLE)return 0;double v[];ArraySetAsSeries(v,true);int c=CopyBuffer(h,0,1,1,v);IndicatorRelease(h);return(c==1&&v[0]>0)?v[0]:0;}
'@ $file

    $text = Replace-One $text "   if(opened)`r`n   {" @'
   if(opened&&FixedReferenceRiskMode())
   {
      string fixedRiskDetail="";
      if(!ValidateFixedReferencePostFill(fixedRiskDetail))
      {
         opened=false;g_lastExecStatus="FIXED_RISK_POST_FILL_BLOCK";
         Audit("fixed_risk_post_fill_block",execDir,0,entry,sl,planTp,fixedRiskDetail);
      }
      else Audit("fixed_risk_post_fill_ok",execDir,0,entry,sl,planTp,fixedRiskDetail);
   }
   if(opened)
   {
'@ $file

    $text = [regex]::Replace($text, '(#define ORB15_BUILD "[^"]+)(")', '$1-fixed-ref-risk-v1$2', 1)
    [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($false))
}
