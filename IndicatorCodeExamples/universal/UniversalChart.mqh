#ifndef UNIVERSAL_CHART_MQH
#define UNIVERSAL_CHART_MQH

struct UcChartTrade
{
   datetime signal,entryTime,exitTime,chartStart,chartEnd;
   int direction;
   double entry,sl,tp,netR,arrow;
   bool valid,closed;
   string reason;
};
UcChartTrade g_ucChartTrades[];
int g_ucChartCursor=0,g_ucChartChecked=0,g_ucChartVerified=0,g_ucChartFailures=0;
bool g_ucChartPending=false;
string g_ucIdentityPacket="",g_ucIdentityBody="",g_ucIdentitySequenceKey="";
long g_ucIdentitySequence=0;
ulong g_ucIdentityUntil=0;

void UcIdentityRead()
{
   string packet=UcRead(g_ucFolder+"identity.txt");
   if(packet==g_ucIdentityPacket)return;
   int at=StringFind(packet,"\nSERVER_RSA256=");if(at<0)return;
   string body=StringSubstr(packet,0,at);
   if(!UcIdentityScope(body,g_ucInstallation,(string)AccountInfoInteger(ACCOUNT_LOGIN),_Symbol,AccountInfoString(ACCOUNT_SERVER),TimeGMT(),g_ucIdentitySequence)
      ||!UcRsaVerify(body,StringSubstr(packet,at+15),UC_AUTHORITY_MODULUS))return;
   g_ucIdentitySequence=StringToInteger(UcField(body,"sequence"));
   GlobalVariableSet(g_ucIdentitySequenceKey,(double)g_ucIdentitySequence);
   g_ucIdentityUntil=GetTickCount64()+(ulong)MathMax(0,(long)StringToInteger(UcField(body,"expires"))-(long)TimeGMT())*1000;
   g_ucIdentityPacket=packet;g_ucIdentityBody=body;
}
bool UcIdentityFresh()
{
   return g_ucIdentityBody!=""&&GetTickCount64()<g_ucIdentityUntil
      &&UcField(g_ucIdentityBody,"accountLogin")== (string)AccountInfoInteger(ACCOUNT_LOGIN)
      &&UcField(g_ucIdentityBody,"symbol")==_Symbol&&UcField(g_ucIdentityBody,"brokerServer")==AccountInfoString(ACCOUNT_SERVER);
}
string UcPanelPrefix(){return "UC.STATUS."+g_ucInstallation+".";}
string UcChartPrefix(){return "UC.AUDIT."+g_ucInstallation+".";}
void UcLabel(string name,string text,int y,int size,color ink)
{
   if(ObjectFind(0,name)<0){ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,name,OBJPROP_XDISTANCE,25);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
      ObjectSetString(0,name,OBJPROP_FONT,"Segoe UI");ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);}
   if(ObjectGetString(0,name,OBJPROP_TEXT)!=text)ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
}
void UcPanelUpdate()
{
   bool fresh=UcIdentityFresh(),connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   string name=UcField(g_ucIdentityBody,"subscriberName");if(name=="")name="Abone";
   bool active=UcField(g_ucIdentityBody,"subscriptionActive")=="true"
      &&StringToInteger(UcField(g_ucIdentityBody,"subscriptionUntil"))>(long)TimeGMT();
   string subscription=g_ucIdentityBody==""?"ABONELIK: DOGRULAMA BEKLENIYOR":active?
      (fresh?"ABONELIK: AKTIF":"ABONELIK: AKTIF / TEYIT BEKLENIYOR"):"ABONELIK: PASIF";
   if(UcField(g_ucIdentityBody,"accessMode")=="demo"){
      long seconds=StringToInteger(UcField(g_ucIdentityBody,"trialUntil"))-(long)TimeGMT();
      int days=(int)MathMax(0,MathCeil((double)seconds/86400.0));
      subscription="ABONELIK: DEMO | "+(string)days+" GUN KALDI"+(fresh?"":" / TEYIT BEKLENIYOR");
   }
   bool healthy=connected&&fresh&&UcField(g_ucIdentityBody,"controllerActive")=="true";
   string health=!connected?"MT5: BAGLANTI YOK":healthy?"MT5 + WEB: SAGLIKLI":fresh?
      "MT5: BAGLI | WEB: YETKI BEKLIYOR":"MT5: BAGLI | WEB: BAGLANTI YOK";
   string prefix=UcPanelPrefix(),box=prefix+"panel";
   if(ObjectFind(0,box)<0){ObjectCreate(0,box,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,box,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,box,OBJPROP_XDISTANCE,14);
      ObjectSetInteger(0,box,OBJPROP_YDISTANCE,18);ObjectSetInteger(0,box,OBJPROP_YSIZE,91);
      ObjectSetInteger(0,box,OBJPROP_BGCOLOR,C'20,32,47');ObjectSetInteger(0,box,OBJPROP_COLOR,C'60,88,110');
      ObjectSetInteger(0,box,OBJPROP_BORDER_TYPE,BORDER_FLAT);ObjectSetInteger(0,box,OBJPROP_BACK,false);
      ObjectSetInteger(0,box,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,box,OBJPROP_HIDDEN,true);}
   int width=(int)MathMax(220,MathMin(430,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-28));
   ObjectSetInteger(0,box,OBJPROP_XSIZE,width);
   int maxName=(width-100)/9;if(StringLen(name)>maxName)name=StringSubstr(name,0,maxName-3)+"...";
   UcLabel(prefix+"hello","Merhaba "+name,26,14,C'245,247,250');
   UcLabel(prefix+"subscription",subscription,56,10,g_ucIdentityBody==""||!fresh?clrGold:active?clrMediumSpringGreen:clrTomato);
   UcLabel(prefix+"connection",health,80,10,healthy?clrMediumSpringGreen:connected?clrGold:clrTomato);
}
void UcChartClear()
{
   ObjectsDeleteAll(0,UcChartPrefix());ArrayResize(g_ucChartTrades,0);
   g_ucChartCursor=0;g_ucChartChecked=0;g_ucChartVerified=0;g_ucChartFailures=0;g_ucChartPending=false;
}
void UcChartPush(datetime signal,datetime entryTime,datetime exitTime,int direction,double entry,double sl,double tp,double netR,bool valid,bool closed,string reason)
{
   int i=ArraySize(g_ucChartTrades);if(i>=10000)return;
   if(ArrayResize(g_ucChartTrades,i+1,1024)!=i+1)return;
   g_ucChartTrades[i].signal=signal;g_ucChartTrades[i].entryTime=entryTime;g_ucChartTrades[i].exitTime=exitTime;
   g_ucChartTrades[i].direction=direction;g_ucChartTrades[i].entry=entry;g_ucChartTrades[i].sl=sl;g_ucChartTrades[i].tp=tp;
   g_ucChartTrades[i].netR=netR;g_ucChartTrades[i].valid=valid;g_ucChartTrades[i].closed=closed;g_ucChartTrades[i].reason=reason;
}
bool UcChartLine(string name,datetime start,datetime end,double price,color ink)
{
   if(price<=0||!MathIsValidNumber(price))return false;
   if(!ObjectCreate(0,name,OBJ_TREND,0,start,price,end,price))return false;
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   return true;
}
void UcChartValidate()
{
   // Read only after the entire creation batch is queued. Reading between writes
   // forces a synchronous chart flush for every single line on MT5.
   ulong budget=GetTickCount64()+20;
   int count=ArraySize(g_ucChartTrades),stride=count<=150?1:(int)MathCeil((double)count/64.0);
   while(g_ucChartChecked<g_ucChartCursor&&GetTickCount64()<budget){
      int i=g_ucChartChecked;g_ucChartChecked=MathMin(count,g_ucChartChecked+stride);g_ucChartVerified++;
      UcChartTrade t=g_ucChartTrades[i];string id=UcChartPrefix()+(string)i+".";
      datetime anchor=t.signal>0?t.signal:t.entryTime;
      if((datetime)ObjectGetInteger(0,id+"arrow",OBJPROP_TIME,0)!=anchor
         ||MathAbs(ObjectGetDouble(0,id+"arrow",OBJPROP_PRICE,0)-t.arrow)>_Point*.01)g_ucChartFailures++;
      string names[]={"entry","sl","tp"};double prices[3];prices[0]=t.entry;prices[1]=t.sl;prices[2]=t.tp;
      for(int k=0;k<3;k++){
         string name=id+names[k];
         if(MathAbs(ObjectGetDouble(0,name,OBJPROP_PRICE,0)-prices[k])>_Point*.01
            ||MathAbs(ObjectGetDouble(0,name,OBJPROP_PRICE,1)-prices[k])>_Point*.01
            ||(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0)!=t.chartStart
            ||(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,1)!=t.chartEnd)g_ucChartFailures++;
      }
   }
}
void UcChartStep()
{
   if(!g_ucChartPending)return;
   ulong budget=GetTickCount64()+20;int processed=0,count=ArraySize(g_ucChartTrades),seconds=PeriodSeconds(_Period);
   if(seconds<=0)seconds=60;
   while(g_ucChartCursor<count&&processed<128&&GetTickCount64()<budget){
      int i=g_ucChartCursor++;processed++;UcChartTrade t=g_ucChartTrades[i];
      datetime anchor=t.signal>0?t.signal:t.entryTime;int shift=iBarShift(_Symbol,_Period,anchor,false);
      if(shift<0){g_ucChartFailures++;continue;}
      datetime start=iTime(_Symbol,_Period,shift),one=shift>0?iTime(_Symbol,_Period,shift-1):start+seconds;
      if(one<=start)one=start+seconds;
      datetime end=shift>=20?iTime(_Symbol,_Period,shift-20):iTime(_Symbol,_Period,0)+(20-shift)*seconds;
      if(t.closed&&t.exitTime>0)end=(datetime)MathMin((long)end,(long)t.exitTime);
      if(i+1<count&&g_ucChartTrades[i+1].signal>start)end=(datetime)MathMin((long)end,(long)g_ucChartTrades[i+1].signal);
      end=(datetime)MathMax((long)one,(long)end);
      string id=UcChartPrefix()+(string)i+".",side=t.direction>0?"BUY":"SELL";
      string outcome=!t.valid?"DATA":!t.closed?"OPEN":t.netR>0?"WIN":t.netR<0?"LOSS":"FLAT";
      color ink=!t.valid?clrSilver:!t.closed?clrGold:t.netR>0?clrLimeGreen:t.netR<0?clrTomato:clrSilver;
      double low=iLow(_Symbol,_Period,shift),high=iHigh(_Symbol,_Period,shift);
      double pad=MathMax(_Point*3,(high-low)*.12),arrow=t.direction>0?low-pad:high+pad;
      g_ucChartTrades[i].chartStart=start;g_ucChartTrades[i].chartEnd=end;g_ucChartTrades[i].arrow=arrow;
      string detail=side+" / "+outcome+(t.valid&&t.closed?" "+DoubleToString(t.netR,4)+"R":"")+" / "+t.reason;
      if(ObjectCreate(0,id+"arrow",OBJ_ARROW,0,anchor,arrow)){
         ObjectSetInteger(0,id+"arrow",OBJPROP_ARROWCODE,t.direction>0?233:234);
         ObjectSetInteger(0,id+"arrow",OBJPROP_ANCHOR,t.direction>0?ANCHOR_TOP:ANCHOR_BOTTOM);
         ObjectSetInteger(0,id+"arrow",OBJPROP_COLOR,ink);ObjectSetInteger(0,id+"arrow",OBJPROP_WIDTH,2);
         ObjectSetInteger(0,id+"arrow",OBJPROP_SELECTABLE,false);ObjectSetInteger(0,id+"arrow",OBJPROP_HIDDEN,true);
         ObjectSetString(0,id+"arrow",OBJPROP_TOOLTIP,detail);
      }else g_ucChartFailures++;
      if(ObjectCreate(0,id+"label",OBJ_TEXT,0,anchor,t.direction>0?arrow-pad:arrow+pad)){
         ObjectSetString(0,id+"label",OBJPROP_TEXT,detail);ObjectSetInteger(0,id+"label",OBJPROP_COLOR,ink);
         ObjectSetInteger(0,id+"label",OBJPROP_FONTSIZE,8);ObjectSetInteger(0,id+"label",OBJPROP_ANCHOR,t.direction>0?ANCHOR_LEFT_UPPER:ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0,id+"label",OBJPROP_SELECTABLE,false);ObjectSetInteger(0,id+"label",OBJPROP_HIDDEN,true);
      }else g_ucChartFailures++;
      if(!UcChartLine(id+"entry",start,end,t.entry,clrWhite))g_ucChartFailures++;
      if(!UcChartLine(id+"sl",start,end,t.sl,clrTomato))g_ucChartFailures++;
      if(!UcChartLine(id+"tp",start,end,t.tp,clrMediumSpringGreen))g_ucChartFailures++;
   }
   ChartRedraw(0);UcChartValidate();g_ucChartPending=g_ucChartCursor<count||g_ucChartChecked<count;
}
void UcChartInit()
{
   g_ucIdentitySequenceKey="UC.IDENTITY."+g_ucInstallation;
   g_ucIdentitySequence=GlobalVariableCheck(g_ucIdentitySequenceKey)?(long)GlobalVariableGet(g_ucIdentitySequenceKey):0;
   UcPanelUpdate();
}
void UcChartShutdown(){ObjectsDeleteAll(0,UcPanelPrefix());UcChartClear();}
#endif
