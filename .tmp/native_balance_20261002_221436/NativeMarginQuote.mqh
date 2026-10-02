#ifndef NATIVE_MARGIN_QUOTE_MQH
#define NATIVE_MARGIN_QUOTE_MQH
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
bool NativeMinimumMargin(bool buy,double &lots,double &margin)
{
   lots=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);margin=0;MqlTick tick;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)||lots<=0||!SymbolInfoTick(_Symbol,tick)
      ||tick.bid<=0||tick.ask<tick.bid)return false;
   return OrderCalcMargin(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,buy?tick.ask:tick.bid,margin)
      &&MathIsValidNumber(margin)&&margin>=0;
}
string NativeMinimumMarginText()
{
   double buyLot=0,buyMargin=0,sellLot=0,sellMargin=0;
   bool buy=NativeMinimumMargin(true,buyLot,buyMargin),sell=NativeMinimumMargin(false,sellLot,sellMargin);
   return "MIN LOT "+DoubleToString(MathMax(buyLot,sellLot),4)+" | BUY "+(buy?DoubleToString(buyMargin,2):"N/A")
      +" | SELL "+(sell?DoubleToString(sellMargin,2):"N/A")+" "+AccountInfoString(ACCOUNT_CURRENCY);
}
bool NativeMinimumSlLoss(bool buy,double entry,double stop,double &loss)
{
   loss=0;double lots=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),profit=0;
   if(!MathIsValidNumber(entry)||!MathIsValidNumber(stop)||entry<=0||stop<=0||lots<=0
      ||(buy?stop>=entry:stop<=entry))return false;
   if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,entry,stop,profit)
      ||!MathIsValidNumber(profit)||profit>=0)return false;
   loss=-profit;return true;
}
double NativeMinimumRiskCapital(double loss,double percent)
{
   if(!MathIsValidNumber(loss)||!MathIsValidNumber(percent)||loss<=0||percent<=0||percent>100)return -1;
   double capital=loss*100.0/percent;
   return MathIsValidNumber(capital)?capital:-1;
}
string NativeMinimumSlText(bool buyValid,double buyLoss,bool sellValid,double sellLoss)
{
   return "MIN LOT SL KAYBI: BUY "+(buyValid?DoubleToString(buyLoss,buyLoss<0.0001?8:4):"N/A")
      +" | SELL "+(sellValid?DoubleToString(sellLoss,sellLoss<0.0001?8:4):"N/A")+" "+AccountInfoString(ACCOUNT_CURRENCY);
}
string NativeMinimumCapitalText(bool buyValid,double buyLoss,bool sellValid,double sellLoss,double percent)
{
   if(!MathIsValidNumber(percent)||percent<=0||percent>100)return "RISK BAKIYESI: N/A (yuzdesel risk secilmeli)";
   double buy=buyValid?NativeMinimumRiskCapital(buyLoss,percent):-1;
   double sell=sellValid?NativeMinimumRiskCapital(sellLoss,percent):-1;
   // Round the required reference capital upwards, never below the risk threshold.
   return "RISK BAKIYESI @"+DoubleToString(percent,2)+"%: BUY "
      +(buy>0?DoubleToString(MathCeil(buy*100.0)/100.0,2):"N/A")+" | SELL "
      +(sell>0?DoubleToString(MathCeil(sell*100.0)/100.0,2):"N/A")+" "+AccountInfoString(ACCOUNT_CURRENCY);
}
string NativeMinimumSlTooltip()
{
   return "Broker minimum lot at the APPLIED pip SL: cash price loss calculated with OrderCalcProfit. "
      "Entry uses BUY ask / SELL bid. Excludes commission, swap and execution slippage. "
      "Not margin or an order acceptance guarantee; broker minimum stop distance still applies.";
}
string NativeMinimumCapitalTooltip()
{
   return "Percentage-risk reference capital = minimum-lot SL cash loss / (applied risk percent / 100). "
      "Rounded upwards to cents. Not a safe deposit recommendation or broker minimum deposit. "
      "Margin/free margin, spread, fees, slippage, existing exposure and stop-out buffers must also be considered. "
      "Does not apply a balance, change sizing or place orders.";
}
string NativeMarginTooltip(const NativeMarginQuote &quote,string side,double budget,bool autoLot)
{
   string currency=AccountInfoString(ACCOUNT_CURRENCY),text="Estimated native "+side+" margin for "+_Symbol+"; applied PIP SL only. ";
   if(quote.valid)
   {
      text+="Lot="+DoubleToString(quote.lots,4)+"; margin="+DoubleToString(quote.margin,2)+" "+currency
         +"; SL risk="+DoubleToString(quote.slRisk,2)+" "+currency+"; risk budget="+DoubleToString(budget,2)
         +"; account leverage=1:"+(string)AccountInfoInteger(ACCOUNT_LEVERAGE)+"; free margin="
         +DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2)+". ";
      if(autoLot&&NativeBalanceOverBudget(quote.slRisk,budget))text+="WARNING: lot step/minimum exceeds risk budget. ";
      if(quote.margin>MathMax(0.0,AccountInfoDouble(ACCOUNT_MARGIN_FREE)))text+="WARNING: insufficient free margin. ";
   }
   else text+=quote.reason+". ";
   return text+"OrderCalcMargin uses broker specifications, not hardcoded leverage. Standalone estimate before entry/portfolio caps; existing exposure and fills can change actual requirements. Margin is not a fee or guaranteed order acceptance.";
}
#endif
