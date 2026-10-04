#ifndef LAB_NATIVE_TRADE_VISUALS_MQH
#define LAB_NATIVE_TRADE_VISUALS_MQH

// Native execution visuals are keyed by the broker position identifier, not
// by a timestamp or the latest signal. They never feed the historical audit.
ulong g_labVisualPending[];
string g_labVisualScope="";
struct LabNativeVisualEvent {ulong id;datetime opened;};
LabNativeVisualEvent g_labVisualEvents[];

string LabNativeVisualBase(ulong id){return PREFIX+"NATIVE_"+StringFormat("%I64u",id)+"_";}
color LabNativeResultColor(double net){return net>1e-8?clrLime:(net<-1e-8?clrTomato:clrLightSteelBlue);}
double LabNativeDealNet(double profit,double swap,double commission,double fee){return profit+swap+commission+fee;}
datetime LabNativeVisualBarCap(datetime opened)
{
   int seconds=MathMax(60,PeriodSeconds((ENUM_TIMEFRAMES)_Period));
   int shift=iBarShift(_Symbol,(ENUM_TIMEFRAMES)_Period,opened,false);
   if(shift>=20){datetime cap=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,shift-20);if(cap>opened)return cap;}
   return opened+seconds*20;
}
datetime LabNativeVisualEnd(datetime opened,datetime nextEntry)
{
   datetime cap=LabNativeVisualBarCap(opened);
   return nextEntry>opened&&nextEntry<cap?nextEntry:cap;
}
datetime LabNativeVisualNext(datetime opened)
{
   int lo=0,hi=ArraySize(g_labVisualEvents);
   while(lo<hi){int mid=(lo+hi)/2;if(g_labVisualEvents[mid].opened<=opened)lo=mid+1;else hi=mid;}
   return lo<ArraySize(g_labVisualEvents)?g_labVisualEvents[lo].opened:0;
}
void LabNativeVisualRegister(ulong id,datetime opened)
{
   int count=ArraySize(g_labVisualEvents);
   int lo=0,hi=count;
   while(lo<hi){int mid=(lo+hi)/2;if(g_labVisualEvents[mid].opened<opened)lo=mid+1;else hi=mid;}
   while(lo<count&&g_labVisualEvents[lo].opened==opened)
   {if(g_labVisualEvents[lo].id==id)return;lo++;}
   ArrayResize(g_labVisualEvents,count+1,128);
   for(int i=count;i>lo;i--)g_labVisualEvents[i]=g_labVisualEvents[i-1];
   g_labVisualEvents[lo].id=id;g_labVisualEvents[lo].opened=opened;
   // A new fill trims the previous time group, including archived results.
   int prior=lo-1;while(prior>=0&&g_labVisualEvents[prior].opened==opened)prior--;
   if(prior<0)return;
   datetime previous=g_labVisualEvents[prior].opened;
   datetime until=LabNativeVisualEnd(previous,opened);
   for(int i=prior;i>=0&&g_labVisualEvents[i].opened==previous;i--)
   {
      string base=LabNativeVisualBase(g_labVisualEvents[i].id);
      string levels[]={"ENTRY","SL","TP"};
      for(int j=0;j<3;j++)if(ObjectFind(0,base+levels[j])>=0)
         ObjectMove(0,base+levels[j],1,until,ObjectGetDouble(0,base+levels[j],OBJPROP_PRICE,0));
   }
}

void LabNativeVisualLine(string name,datetime from,datetime until,double price,color tint)
{
   if(price<=0.0||!InpDrawTradeLevelSegments){ObjectDelete(0,name);return;}
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,OBJ_TREND,0,from,price,until,price);
   ObjectMove(0,name,0,from,price);ObjectMove(0,name,1,until,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,tint);ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"Actual MT5 level: "+DoubleToString(price,_Digits));
}

void LabNativeVisualDraw(ulong id,int dir,datetime opened,datetime signalBar,double entry,double sl,double tp,
                         datetime closed=0,double net=0.0,string reason="")
{
   if(IsTesterMode()||id==0||dir==0||opened<=0||entry<=0.0)return;
   string base=LabNativeVisualBase(id);
   LabNativeVisualRegister(id,opened);
   datetime until=LabNativeVisualEnd(opened,LabNativeVisualNext(opened)),bar=0;double arrow=0,pad=0;
   MaCrossTradeMarker(opened,dir>0,entry,bar,arrow,pad);
   string fingerprint=(string)opened+"|"+(string)closed+"|"+(string)dir+"|"+(string)bar
      +"|"+DoubleToString(entry,_Digits)+"|"+DoubleToString(sl,_Digits)+"|"+DoubleToString(tp,_Digits)
      +"|"+(string)until
      +"|"+DoubleToString(arrow,_Digits)+"|"+DoubleToString(net,8)+"|"+(string)InpDrawTradeLevelSegments+"|"+reason;
   if(ObjectFind(0,base+"ARW")>=0&&ObjectGetString(0,base+"ARW",OBJPROP_TEXT)==fingerprint)return;
   color tint=closed>0?LabNativeResultColor(net):clrGold;
   LabNativeVisualLine(base+"ENTRY",opened,until,entry,C'230,230,230');
   LabNativeVisualLine(base+"SL",opened,until,sl,C'255,80,110');
   LabNativeVisualLine(base+"TP",opened,until,tp,C'80,255,180');
   DrawSignalArrow(base+"ARW",bar,arrow,dir>0,false);
   ObjectSetInteger(0,base+"ARW",OBJPROP_COLOR,tint);
   ObjectSetInteger(0,base+"ARW",OBJPROP_ANCHOR,dir>0?ANCHOR_TOP:ANCHOR_BOTTOM);
   ObjectSetString(0,base+"ARW",OBJPROP_TEXT,fingerprint);
   ObjectSetString(0,base+"ARW",OBJPROP_TOOLTIP,"MT5 position "+(string)id+" | "+MaCrossTradeMarkerTooltip(signalBar,opened));
   string status=closed>0?(net>1e-8?"WIN":(net<-1e-8?"LOSS":"FLAT")):"OPEN";
   string text="EXECUTED "+status+" "+(dir>0?"BUY":"SELL")+" #"+(string)id
      +" ENTRY="+DoubleToString(entry,_Digits)+" SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits);
   if(closed>0)text+=" NET="+DoubleToString(net,2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+" "+reason;
   DrawSignalText(base+"TXT",bar,dir>0?arrow-pad*0.65:arrow+pad*0.65,text,tint);
   // Accepted setup arrows describe direction, not profit. Remove only the
   // setup now represented by this confirmed native fill.
   if(signalBar>0)
   {
      string setup=PREFIX+"LIVE_"+(string)(long)signalBar+"_"+(dir>0?"BUY_":"SELL_");
      ObjectDelete(0,setup+"ARW");ObjectDelete(0,setup+"TXT");
   }
}

void LabNativeVisualQueue(ulong id)
{
   if(id==0)return;
   for(int i=0;i<ArraySize(g_labVisualPending);i++)if(g_labVisualPending[i]==id)return;
   int n=ArraySize(g_labVisualPending);ArrayResize(g_labVisualPending,n+1,64);g_labVisualPending[n]=id;
}

bool LabNativeVisualFromHistory(ulong id)
{
   if(!HistorySelectByPosition(id))return false;
   bool owned=false;int dir=0;datetime opened=0,closed=0,signalBar=0;
   double entryMoney=0,volume=0,sl=0,tp=0,net=0,exitPrice=0;long lastMs=0;string reason="";
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);if(deal==0)continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)continue;
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL)continue;
      long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
      datetime at=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      net+=LabNativeDealNet(HistoryDealGetDouble(deal,DEAL_PROFIT),HistoryDealGetDouble(deal,DEAL_SWAP),
         HistoryDealGetDouble(deal,DEAL_COMMISSION),HistoryDealGetDouble(deal,DEAL_FEE));
      if(kind==DEAL_ENTRY_IN)
      {
         if(MagicOwned((long)HistoryDealGetInteger(deal,DEAL_MAGIC)))owned=true;
         double size=HistoryDealGetDouble(deal,DEAL_VOLUME);
         entryMoney+=size*HistoryDealGetDouble(deal,DEAL_PRICE);volume+=size;
         if(opened==0||at<opened)
         {
            opened=at;dir=type==DEAL_TYPE_BUY?1:-1;
            ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
            sl=HistoryOrderGetDouble(order,ORDER_SL);tp=HistoryOrderGetDouble(order,ORDER_TP);
            string comment=HistoryDealGetString(deal,DEAL_COMMENT);
            if(StringFind(comment,"MAI|")==0)signalBar=(datetime)StringToInteger(StringSubstr(comment,4));
         }
      }
      else if(kind==DEAL_ENTRY_OUT||kind==DEAL_ENTRY_OUT_BY)
      {
         long ms=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
         if(ms>=lastMs){lastMs=ms;closed=at;exitPrice=HistoryDealGetDouble(deal,DEAL_PRICE);
            reason=HistoryDealGetString(deal,DEAL_COMMENT);}
      }
   }
   if(opened==0||volume<=0.0)return false;
   if(!owned)return true;
   if(OrbProPositionStillOpen(id))return true; // A partial close is not a final win/loss.
   if(closed<=0)return false;
   if(sl<=0.0)sl=OrbProGet(id,"sl",0);if(tp<=0.0)tp=OrbProGet(id,"tp",0);
   if(signalBar<=0)signalBar=(datetime)OrbProGet(id,"signalTs",0);
   LabNativeVisualDraw(id,dir,opened,signalBar,entryMoney/volume,sl,tp,closed,net,reason);
   DrawSignalText(LabNativeVisualBase(id)+"EXIT",closed,exitPrice,"X "+(net>1e-8?"WIN":(net<-1e-8?"LOSS":"FLAT")),LabNativeResultColor(net));
   return true;
}

void LabNativeVisualRefreshOpen()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);if(ticket==0||!PositionSelectByTicket(ticket)||!IsOwnPosition())continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);if(id==0)id=ticket;
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      if(sl<=0)sl=OrbProGet(id,"sl",0);if(tp<=0)tp=OrbProGet(id,"tp",0);
      LabNativeVisualDraw(id,dir,(datetime)PositionGetInteger(POSITION_TIME),
         (datetime)OrbProGet(id,"signalTs",0),PositionGetDouble(POSITION_PRICE_OPEN),sl,tp);
   }
}

void LabNativeVisualRestore()
{
   string scope=(string)AccountInfoInteger(ACCOUNT_LOGIN)+"|"+_Symbol+"|"+(string)RuntimeMagic();
   if(g_labVisualScope!=scope){DeleteByPrefix(PREFIX+"NATIVE_");ArrayResize(g_labVisualPending,0);ArrayResize(g_labVisualEvents,0);g_labVisualScope=scope;}
   datetime from=TimeCurrent()-(datetime)((long)RuntimeHistoricalDays()*86400);
   if(!HistorySelect(from,TimeCurrent()))return;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);if(deal==0)continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol||!MagicOwned((long)HistoryDealGetInteger(deal,DEAL_MAGIC)))continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);if(id==0)continue;
      int n=ArraySize(g_labVisualPending);ArrayResize(g_labVisualPending,n+1,256);g_labVisualPending[n]=id;
   }
   // Restoring a long native history must not do a quadratic duplicate scan.
   int count=ArraySize(g_labVisualPending);if(count==0)return;
   ArraySort(g_labVisualPending);int kept=1;
   for(int i=1;i<count;i++)if(g_labVisualPending[i]!=g_labVisualPending[kept-1])g_labVisualPending[kept++]=g_labVisualPending[i];
   ArrayResize(g_labVisualPending,kept);
}

void LabNativeVisualTimer()
{
   ulong start=GetTickCount64();int examined=0,kept=0,count=ArraySize(g_labVisualPending);
   while(examined<count&&GetTickCount64()-start<25)
   {
      ulong id=g_labVisualPending[examined++];
      if(!LabNativeVisualFromHistory(id))g_labVisualPending[kept++]=id;
   }
   if(examined>0){int remaining=count-examined;
      if(remaining>0)ArrayCopy(g_labVisualPending,g_labVisualPending,kept,examined,remaining);
      ArrayResize(g_labVisualPending,kept+remaining);}
}

void LabNativeVisualTransaction(const MqlTradeTransaction &trans)
{
   if(IsTesterMode()||trans.type!=TRADE_TRANSACTION_DEAL_ADD||trans.deal==0||!HistoryDealSelect(trans.deal))return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol)return;
   ulong id=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   if(MagicOwned((long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC))||ObjectFind(0,LabNativeVisualBase(id)+"ARW")>=0)
      LabNativeVisualQueue(id);
}
#endif
