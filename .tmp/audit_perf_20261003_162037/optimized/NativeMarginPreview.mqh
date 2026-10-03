#ifndef NATIVE_MARGIN_PREVIEW_MQH
#define NATIVE_MARGIN_PREVIEW_MQH
#include "NativeMarginQuote.mqh"
void RenderNativeMarginPreview(int x,int y,bool forcePip=false,bool percentageRisk=true)
{
   bool pip=g_rtPipSlMode||forcePip;MqlTick tick;
   bool ready=pip&&TerminalInfoInteger(TERMINAL_CONNECTED)&&SymbolInfoTick(_Symbol,tick)&&tick.bid>0&&tick.ask>=tick.bid;
   double budget=RiskBudgetMoney();bool autoLot=InpUseAutoRiskLot||ManagedRiskMode()||FixedReferenceRiskMode()||NativeBalanceEnabled();
   string currency=AccountInfoString(ACCOUNT_CURRENCY);bool overRisk=false,overMargin=false;
   bool minValid[2];double minLoss[2];
   ArrayInitialize(minValid,false);ArrayInitialize(minLoss,0.0);
   CreateLabel("DASH_MARGIN_TITLE",x,y,"GEREKLI TEMINAT (MARGIN) / "+currency+" / 1:"
      +(string)AccountInfoInteger(ACCOUNT_LEVERAGE),C'255,187,92',10);
   for(int i=0;i<2;i++)
   {
      bool buy=i==0;string side=buy?"BUY":"SELL",id=buy?"DASH_MARGIN_BUY":"DASH_MARGIN_SELL";
      NativeMarginQuote quote;quote.valid=false;quote.reason=!pip?"Apply PIP SL to preview margin":"Connect broker / quote unavailable";
      if(ready)
      {
         double entry=NormalizeTradePrice(buy?tick.ask:tick.bid),stop=ApplyRuntimeSlFromEntry(buy,entry,0);
         minValid[i]=NativeMinimumSlLoss(buy,entry,stop,minLoss[i]);
         if(autoLot&&budget<=0)quote.reason="Risk budget is zero";
         else NativeMarginCalculate(_Symbol,buy,entry,stop,CalculateLot(entry,stop),quote);
      }
      bool risk=quote.valid&&autoLot&&NativeBalanceOverBudget(quote.slRisk,budget);
      bool margin=quote.valid&&quote.margin>MathMax(0.0,AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      overRisk=overRisk||risk;overMargin=overMargin||margin;
      string text=side+" TEMINAT: "+(quote.valid?DoubleToString(quote.margin,2)+" "+currency+" | LOT "+DoubleToString(quote.lots,4):"N/A");
      CreateLabel(id,x,y+20+i*17,text,risk||margin?clrOrange:(quote.valid?C'80,255,180':C'184,196,210'),10);
      ObjectSetString(0,PREFIX+id,OBJPROP_TOOLTIP,NativeMarginTooltip(quote,side,budget,autoLot));
   }
   CreateLabel("DASH_MARGIN_MIN",x,y+55,NativeMinimumMarginText(),C'184,196,210',9);
   ObjectSetString(0,PREFIX+"DASH_MARGIN_MIN",OBJPROP_TOOLTIP,"Minimum broker volume standalone margin, not the selected EA risk budget. Spread, fees, stop-out buffer and existing exposure can require additional funds.");
   CreateLabel("DASH_MARGIN_MIN_SL",x,y+73,NativeMinimumSlText(minValid[0],minLoss[0],minValid[1],minLoss[1]),C'80,255,180',9);
   ObjectSetString(0,PREFIX+"DASH_MARGIN_MIN_SL",OBJPROP_TOOLTIP,NativeMinimumSlTooltip());
   CreateLabel("DASH_MARGIN_MIN_CAPITAL",x,y+91,NativeMinimumCapitalText(minValid[0],minLoss[0],minValid[1],minLoss[1],percentageRisk?g_rtRiskPerTradePct:0),C'255,187,92',9);
   ObjectSetString(0,PREFIX+"DASH_MARGIN_MIN_CAPITAL",OBJPROP_TOOLTIP,NativeMinimumCapitalTooltip());
   string note=overRisk?"UYARI: Minimum lot / lot step, risk butcesini asiyor.":(overMargin?"UYARI: Serbest teminat yetersiz.":(!pip?"Pozisyon tahmini icin PIP SL uygula; MIN LOT teminati ayridir.":"Tahmini teminat; ucret degil. Detaylar icin tutarin uzerine gel."));
   CreateLabel("DASH_MARGIN_NOTE",x,y+109,note,overRisk||overMargin?clrOrange:C'184,196,210',8);
}
#endif
