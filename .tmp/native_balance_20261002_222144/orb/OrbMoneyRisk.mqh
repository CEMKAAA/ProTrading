#ifndef ORB_MONEY_RISK_MQH
#define ORB_MONEY_RISK_MQH
input bool InpMoneyRiskDefault=false; // NAT only: fixed amount instead of percentage
input double InpMoneyRiskAmount=0.0; // Account currency; USD when account is USD
bool g_orbMoneyRisk=false;
double g_orbMoneyRiskAmount=0.0;
double OrbBoundedMoney(double amount,double balance)
{return MathIsValidNumber(amount)&&MathIsValidNumber(balance)?MathMax(0.0,MathMin(amount,balance)):0.0;}
bool OrbMoneyInputValid(double value,double balance)
{return MathIsValidNumber(value)&&MathIsValidNumber(balance)&&value>0&&value<=balance;}
bool OrbParseRiskInput(string text,double &value)
{
   StringTrimLeft(text);StringTrimRight(text);StringReplace(text,",",".");
   int digits=0,dots=0;
   for(int i=0;i<StringLen(text);i++)
   {
      ushort c=StringGetCharacter(text,i);
      if(c=='.'){if(++dots>1)return false;}
      else if(c>='0'&&c<='9')digits++;
      else return false;
   }
   if(digits==0)return false;
   value=StringToDouble(text);return MathIsValidNumber(value)&&value>0;
}
double OrbMoneyBudget(){return OrbBoundedMoney(g_orbMoneyRiskAmount,AccountInfoDouble(ACCOUNT_BALANCE));}
string OrbMoneyRiskKey(){return "ORB_MONEY."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();}
void OrbLoadMoneyRisk()
{
   g_orbMoneyRisk=InpMoneyRiskDefault;g_orbMoneyRiskAmount=MathMax(0.0,InpMoneyRiskAmount);
   string key=OrbMoneyRiskKey();
   if(GlobalVariableCheck(key+".mode"))g_orbMoneyRisk=GlobalVariableGet(key+".mode")==1;
   if(GlobalVariableCheck(key+".amount"))
   {double a=GlobalVariableGet(key+".amount");if(MathIsValidNumber(a)&&a>=0)g_orbMoneyRiskAmount=a;}
}
bool OrbSetMoneyAmount(double value)
{
   if(!OrbMoneyInputValid(value,AccountInfoDouble(ACCOUNT_BALANCE)))return false;
   if(GlobalVariableSet(OrbMoneyRiskKey()+".amount",value)<=0)return false;
   g_orbMoneyRiskAmount=value;GlobalVariablesFlush();return true;
}
bool OrbToggleMoneyRisk()
{
   bool next=!g_orbMoneyRisk;
   if(GlobalVariableSet(OrbMoneyRiskKey()+".mode",next?1:0)<=0)return false;
   g_orbMoneyRisk=next;GlobalVariablesFlush();return true;
}
double OrbRiskEditValue(){return g_orbMoneyRisk?g_orbMoneyRiskAmount:g_rtRiskPerTradePct;}
string OrbRiskUnit(){return g_orbMoneyRisk?AccountInfoString(ACCOUNT_CURRENCY):"%";}
#endif
