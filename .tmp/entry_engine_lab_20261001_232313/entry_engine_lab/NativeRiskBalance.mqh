#ifndef NATIVE_RISK_BALANCE_MQH
#define NATIVE_RISK_BALANCE_MQH
double g_nativeRiskBalance=0.0;
string g_nativeRiskBalanceKey="";
bool NativeBalanceEnabled(){return g_nativeRiskBalance>0.0;}
bool NativeBalanceParse(string text,double &value)
{
   StringTrimLeft(text);StringTrimRight(text);StringReplace(text,",",".");
   int digits=0,dots=0;
   for(int i=0;i<StringLen(text);i++)
   {
      ushort c=StringGetCharacter(text,i);
      if(c=='.'){if(++dots>1)return false;}
      else if(c>='0'&&c<='9')digits++;else return false;
   }
   if(digits==0)return false;
   value=StringToDouble(text);
   return MathIsValidNumber(value)&&value>=0.0&&value<=1e12;
}
void NativeBalanceLoad(string family)
{
   g_nativeRiskBalanceKey="NB."+family+"."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();
   g_nativeRiskBalance=0.0;
   if(GlobalVariableCheck(g_nativeRiskBalanceKey))
   {double value=GlobalVariableGet(g_nativeRiskBalanceKey);if(MathIsValidNumber(value)&&value>=0&&value<=1e12)g_nativeRiskBalance=value;}
}
bool NativeBalanceApply(string text)
{
   double value=0.0;if(!NativeBalanceParse(text,value)||g_nativeRiskBalanceKey=="")return false;
   if(GlobalVariableSet(g_nativeRiskBalanceKey,value)<=0)return false;
   g_nativeRiskBalance=value;GlobalVariablesFlush();return true;
}
// Reference sizing never changes the real account used for margin/drawdown guards.
double NativeBalanceBudget(double pct)
{
   if(!MathIsValidNumber(pct)||pct<0.0||pct>100.0)return 0.0;
   return MathMin(MathMax(0.0,AccountInfoDouble(ACCOUNT_BALANCE)),g_nativeRiskBalance*pct/100.0);
}
bool NativeBalanceOverBudget(double actual,double budget)
{return !MathIsValidNumber(actual)||!MathIsValidNumber(budget)||budget<=0.0||actual>budget+MathMax(1e-8,budget*1e-8);}
#endif
