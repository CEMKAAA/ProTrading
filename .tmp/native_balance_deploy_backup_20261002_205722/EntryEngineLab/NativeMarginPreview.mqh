#ifndef NATIVE_MARGIN_PREVIEW_MQH
#define NATIVE_MARGIN_PREVIEW_MQH
struct NativeMarginQuote
{
   bool valid;double lots,margin,slRisk;string reason;
};
bool NativeMarginCalculate(string symbol,bool buy,double entry,double stop,double lots,NativeMarginQuote &quote)
{
   quote.valid=false;quote.lots=lots;quote.margin=quote.slRisk=0;quote.reason="";
   if(!MathIsValidNumber(entry)||!MathIsValidNumber(stop)||!MathIsValidNumber(lots)
      ||entry<=0||stop<=0||lots<=0||(buy?stop>=entry:stop<=entry))
   {quote.reason="No valid applied SL / lot geometry";return false;}
   ENUM_ORDER_TYPE side=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;double profit=0,margin=0;
   ResetLastError();
   if(!OrderCalcMargin(side,symbol,lots,entry,margin)||!MathIsValidNumber(margin)||margin<0)
   {quote.reason="Broker margin calculation unavailable: "+(string)GetLastError();return false;}
   ResetLastError();
   if(!OrderCalcProfit(side,symbol,lots,entry,stop,profit)||!MathIsValidNumber(profit)||profit>=0)
   {quote.reason="Broker SL-value calculation unavailable: "+(string)GetLastError();return false;}
   quote.margin=margin;quote.slRisk=-profit;quote.valid=true;return true;
}
void RenderNativeMarginPreview(int x,int y)
{
   // This occupies the narrow space beside the audit bar, below the SL input.
   bool pip=g_rtPipSlMode||LabPolicyEnabled();MqlTick tick;
   bool ready=pip&&TerminalInfoInteger(TERMINAL_CONNECTED)&&SymbolInfoTick(_Symbol,tick)&&tick.bid>0&&tick.ask>=tick.bid;
   double budget=RiskBudgetMoney();bool autoLot=InpUseAutoRiskLot||ManagedRiskMode()||FixedReferenceRiskMode()||NativeBalanceEnabled();
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   for(int i=0;i<2;i++)
   {
      bool buy=i==0;string side=buy?"BUY":"SELL",id=buy?"DASH_MARGIN_BUY":"DASH_MARGIN_SELL";
      NativeMarginQuote quote;quote.valid=false;quote.reason=!pip?"Apply PIP SL to preview margin":"Connect broker / quote unavailable";
      if(ready)
      {
         double entry=NormalizeTradePrice(buy?tick.ask:tick.bid),stop=ApplyRuntimeSlFromEntry(buy,entry,0);
         double lots=CalculateLot(entry,stop);
         if(autoLot&&budget<=0)quote.reason="Risk budget is zero";
         else NativeMarginCalculate(_Symbol,buy,entry,stop,lots,quote);
      }
      bool warning=quote.valid&&(quote.margin>MathMax(0.0,AccountInfoDouble(ACCOUNT_MARGIN_FREE))
         ||(autoLot&&NativeBalanceOverBudget(quote.slRisk,budget)));
      string text=i==0?"MARG B: ":"S: ";
      text+=quote.valid?DoubleToString(quote.margin,2):"N/A";if(i==1)text+=" "+currency;
      CreateLabel(id,x,y+i*15,text,warning?clrOrange:(quote.valid?C'80,255,180':C'184,196,210'),8);
      string detail="Estimated native "+side+" margin for "+_Symbol+"; applied PIP SL only. ";
      if(quote.valid)
      {
         detail+="Lot="+DoubleToString(quote.lots,4)+"; margin="+DoubleToString(quote.margin,2)+" "+currency
            +"; SL risk="+DoubleToString(quote.slRisk,2)+" "+currency+"; risk budget="+DoubleToString(budget,2)
            +"; account leverage=1:"+(string)AccountInfoInteger(ACCOUNT_LEVERAGE)+"; free margin="+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2)+". ";
         if(autoLot&&NativeBalanceOverBudget(quote.slRisk,budget))detail+="WARNING: lot step/minimum exceeds risk budget. ";
         if(quote.margin>MathMax(0.0,AccountInfoDouble(ACCOUNT_MARGIN_FREE)))detail+="WARNING: insufficient free margin. ";
      }
      else detail+=quote.reason+". ";
      detail+="OrderCalcMargin uses broker specifications, not a hardcoded 1:500. Standalone position estimate before ATR/portfolio/entry limits; existing exposure, fill prices and broker margin changes can alter actual requirements. This is margin, not a fee or guaranteed order acceptance.";
      ObjectSetString(0,PREFIX+id,OBJPROP_TOOLTIP,detail);
   }
}
#endif
