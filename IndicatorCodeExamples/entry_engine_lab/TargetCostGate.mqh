#ifndef TARGET_COST_GATE_MQH
#define TARGET_COST_GATE_MQH
input bool InpTargetCostFilter=false;
input double InpTargetCostMaxPct=20.0;
bool g_tpCostEnabled=false;
double g_tpCostMaxPct=20.0;
double g_tpCostRenderedPct=-1.0;
int g_tpCostRejected=0;
string g_tpCostKey="",g_tpCostStatus="";
bool TpCostPercent(string text,double &value)
{
   StringTrimLeft(text);StringTrimRight(text);StringReplace(text,",",".");
   int digits=0,dots=0;
   for(int i=0;i<StringLen(text);i++)
   {ushort c=StringGetCharacter(text,i);if(c=='.'){if(++dots>1)return false;}else if(c>='0'&&c<='9')digits++;else return false;}
   value=StringToDouble(text);return digits>0&&MathIsValidNumber(value)&&value>=0&&value<=100;
}
string TpCostPack(bool enabled,double maximum){return "TCOST1="+(enabled?"1":"0")+","+DoubleToString(maximum,8);}
string TpCostIdentity(bool enabled,double maximum){return enabled?"|TARGET_COST_GATE_1|"+TpCostPack(enabled,maximum):"";}
string TpCostIdentity(){return TpCostIdentity(g_tpCostEnabled,g_tpCostMaxPct);}
bool TpCostRead(string text,bool &enabled,double &maximum)
{
   string parts[];if(StringFind(text,"TCOST1=")!=0||StringSplit(StringSubstr(text,7),',',parts)!=2
      ||(parts[0]!="0"&&parts[0]!="1")||!TpCostPercent(parts[1],maximum))return false;
   enabled=parts[0]=="1";return true;
}
// Optional suffix leaves all old preset token counts and schemas intact.
bool TpCostStripMeta(string &text,bool &enabled,double &maximum)
{
   enabled=false;maximum=20.0;int at=StringFind(text,"|TCOST1=");
   if(at<0)return true;
   if(!TpCostRead(StringSubstr(text,at+1),enabled,maximum))return false;
   text=StringSubstr(text,0,at);return true;
}
bool TpCostStripLines(string &lines[],bool &enabled,double &maximum)
{
   enabled=false;maximum=20.0;int n=ArraySize(lines);
   if(n<1||StringFind(lines[n-1],"TCOST1=")!=0)return true;
   if(!TpCostRead(lines[n-1],enabled,maximum))return false;
   return ArrayResize(lines,n-1)==n-1;
}
bool TpCostSet(bool enabled,double maximum)
{
   if(!MathIsValidNumber(maximum)||maximum<0||maximum>100)return false;
   // One packed global commits both controls together across chart restarts.
   if(g_tpCostKey!=""&&GlobalVariableSet(g_tpCostKey,(enabled?1000.0:0.0)+maximum)<=0)return false;
   g_tpCostEnabled=enabled;g_tpCostMaxPct=maximum;g_tpCostRenderedPct=-1;GlobalVariablesFlush();return true;
}
void TpCostLoad(string family)
{
   g_tpCostKey="TPC."+family+"."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();
   g_tpCostEnabled=InpTargetCostFilter;g_tpCostMaxPct=InpTargetCostMaxPct;
   if(!MathIsValidNumber(g_tpCostMaxPct)||g_tpCostMaxPct<0||g_tpCostMaxPct>100){g_tpCostEnabled=false;g_tpCostMaxPct=20;}
   if(GlobalVariableCheck(g_tpCostKey))
   {double v=GlobalVariableGet(g_tpCostKey);if(MathIsValidNumber(v)&&((v>=0&&v<=100)||(v>=1000&&v<=1100)))
      {g_tpCostEnabled=v>=1000;g_tpCostMaxPct=g_tpCostEnabled?v-1000:v;}}
}
bool TpCostIsReject(string reason){return reason=="COST_TP_BLOCK"||reason=="COST_TP_NO_FIXED_TARGET";}
bool TpCostCheck(double profitDistance,double costDistance,string &reason)
{
   reason="";if(!g_tpCostEnabled)return true;
   if(!MathIsValidNumber(profitDistance)||profitDistance<=0){reason="COST_TP_NO_FIXED_TARGET";return false;}
   if(!MathIsValidNumber(costDistance)||costDistance<0){reason="COST_TP_DATA";return false;}
   double pct=100.0*costDistance/profitDistance;
   g_tpCostStatus="Estimated cost / target "+DoubleToString(pct,2)+"% / max "+DoubleToString(g_tpCostMaxPct,2)+"%";
   if(pct>g_tpCostMaxPct+1e-8){reason="COST_TP_BLOCK";return false;}return true;
}
bool TpCostEstimate(string symbol,double spreadPoints,double slipPoints,double commissionPerLot,double &distance)
{
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);distance=0;
   if(point<=0||!MathIsValidNumber(spreadPoints)||spreadPoints<0||!MathIsValidNumber(slipPoints)||slipPoints<0
      ||!MathIsValidNumber(commissionPerLot)||commissionPerLot<0)return false;
   distance=(spreadPoints+slipPoints)*point;
   if(commissionPerLot>0)
   {
      double size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),value=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      if(size<=0||value<=0)return false;distance+=commissionPerLot*size/value;
   }
   return MathIsValidNumber(distance);
}
bool TpCostAllow(string symbol,double profitDistance,double spreadPoints,double slipPoints,double commissionPerLot,string &reason)
{
   reason="";if(!g_tpCostEnabled)return true;
   double distance=0;if(!TpCostEstimate(symbol,spreadPoints,slipPoints,commissionPerLot,distance))
   {reason="COST_TP_DATA";return false;}return TpCostCheck(profitDistance,distance,reason);
}
string TpCostObject(string scope,string id){return scope+"TCOST_"+id;}
void TpCostHide(string scope)
{string ids[]={"ON","LABEL","VALUE","APPLY","COUNT"};for(int i=0;i<ArraySize(ids);i++)ObjectDelete(0,TpCostObject(scope,ids[i]));}
void TpCostDraw(string scope,int x,int y,double scale=1,long z=1000003)
{
   string ids[]={"ON","LABEL","VALUE","APPLY","COUNT"};
   ENUM_OBJECT types[]={OBJ_BUTTON,OBJ_LABEL,OBJ_EDIT,OBJ_BUTTON,OBJ_LABEL};
   int offsets[]={0,116,158,228,294},widths[]={110,40,64,60,220};
   string texts[]={g_tpCostEnabled?"TP COST ON":"TP COST OFF","MAX %",DoubleToString(g_tpCostMaxPct,2),"APPLY","Audit blocked: "+(string)g_tpCostRejected};
   for(int i=0;i<5;i++)
   {
      string name=TpCostObject(scope,ids[i]);bool created=ObjectFind(0,name)<0;
      if(created)ObjectCreate(0,name,types[i],0,0,0);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x+(int)MathRound(offsets[i]*scale));
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y+(int)MathRound((types[i]==OBJ_LABEL?4:0)*scale));
      ObjectSetInteger(0,name,OBJPROP_XSIZE,(int)MathRound(widths[i]*scale));ObjectSetInteger(0,name,OBJPROP_YSIZE,(int)MathRound(22*scale));
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,name,OBJPROP_BGCOLOR,i==0&&g_tpCostEnabled?C'30,150,95':C'38,46,60');
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'65,116,172');ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(int)MathMax(7,MathRound(8*scale)));
      ObjectSetInteger(0,name,OBJPROP_ZORDER,z);ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
      if(i!=2||created||g_tpCostRenderedPct!=g_tpCostMaxPct)ObjectSetString(0,name,OBJPROP_TEXT,texts[i]);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,"Entry filter: estimated spread + configured audit slippage/commission as % of planned target profit. 0-100. Needs a fixed target. Future entries only; no fill guarantee. "+g_tpCostStatus);
   }
   g_tpCostRenderedPct=g_tpCostMaxPct;
}
bool TpCostUiEvent(int id,string object,string scope)
{
   if(id!=CHARTEVENT_OBJECT_CLICK||(object!=TpCostObject(scope,"ON")&&object!=TpCostObject(scope,"APPLY")))return false;
   double value=0;bool enabled=object==TpCostObject(scope,"ON")?!g_tpCostEnabled:g_tpCostEnabled;
   bool ok=TpCostPercent(ObjectGetString(0,TpCostObject(scope,"VALUE"),OBJPROP_TEXT),value)&&TpCostSet(enabled,value);
   g_tpCostStatus=ok?"Applied: future entries and historical audit":"Not applied: enter a percentage from 0 to 100";
   ObjectSetInteger(0,object,OBJPROP_STATE,false);
   ObjectSetString(0,TpCostObject(scope,"VALUE"),OBJPROP_TEXT,DoubleToString(g_tpCostMaxPct,2));return true;
}
#endif
