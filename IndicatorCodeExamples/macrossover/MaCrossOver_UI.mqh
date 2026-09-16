#ifndef MA_CROSSOVER_UI_MQH
#define MA_CROSSOVER_UI_MQH
void MaObject(string key,ENUM_OBJECT type,int x,int y,int w,int h,string text,color bg=clrNONE)
{
   string name=g_prefix+"UI_"+key;bool fresh=ObjectFind(0,name)<0;
   if(fresh)ObjectCreate(0,name,type,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);ObjectSetInteger(0,name,OBJPROP_YSIZE,h);ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,name,OBJPROP_ZORDER,StringFind(key,"POP")==0?300:(type==OBJ_RECTANGLE_LABEL?10:30));
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
   if(bg!=clrNONE)ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   if(type!=OBJ_EDIT||fresh)ObjectSetString(0,name,OBJPROP_TEXT,text);
   if(type==OBJ_EDIT)ObjectSetInteger(0,name,OBJPROP_READONLY,false);
   if(type==OBJ_BUTTON)ObjectSetInteger(0,name,OBJPROP_STATE,false);
}
void MaButton(string key,int x,int y,int w,string text,bool on=true){MaObject(key,OBJ_BUTTON,x,y,w,23,text,on?C'33,102,122':C'47,51,62');}
void MaField(string key,int x,int y,int w,string caption,string value)
{MaObject(key+"L",OBJ_LABEL,x,y,0,0,caption);MaObject(key,OBJ_EDIT,x,y+17,w,22,value,C'28,36,49');}
string MaText(string key){return ObjectGetString(0,g_prefix+"UI_"+key,OBJPROP_TEXT);}
string MaClock(int value){return StringFormat("%02d:%02d",value/60,value%60);}
bool MaParseClock(string text,int &minute)
{
   if(StringLen(text)!=5||StringSubstr(text,2,1)!=":")return false;
   for(int i=0;i<5;i++)if(i!=2&&(StringGetCharacter(text,i)<'0'||StringGetCharacter(text,i)>'9'))return false;
   int h=(int)StringToInteger(StringSubstr(text,0,2)),m=(int)StringToInteger(StringSubstr(text,3,2));
   if(h==24&&m==0){minute=0;return true;}if(h>23||m>59)return false;minute=h*60+m;return true;
}
bool MaReadEdits(MaConfig &c)
{
   string keys[]={"FAST","MEDIUM","SLOW","HTFLEN","SLPCT","TPPCT","RR","PIPS","ATRLEN","ATRMULT","BER","PARTR","PARTPCT","TRAIL","VOLX","ADXMIN","ADXPER","RSIPER","PIVOT","DIVAGE","ATRMIN","ATRMAX","DISPMIN"};
   double v[];ArrayResize(v,ArraySize(keys));for(int i=0;i<ArraySize(keys);i++)if(!MaNumber(MaText(keys[i]),v[i])){g_status="Invalid numeric field: "+keys[i];return false;}
   int integer[]={0,1,2,3,8,16,17,18,19};for(int j=0;j<ArraySize(integer);j++)if(v[integer[j]]!=MathFloor(v[integer[j]])){g_status="Period fields require whole numbers";return false;}
   c=g_cfg;c.fast=(int)v[0];c.medium=(int)v[1];c.slow=(int)v[2];c.htfLen=(int)v[3];c.slPct=v[4];c.tpPct=v[5];c.rr=v[6];c.pips=v[7];
   c.atrLen=(int)v[8];c.atrMult=v[9];c.beR=v[10];c.partialR=v[11];c.partialPct=v[12];c.trailMult=v[13];c.volMult=v[14];c.adxMin=v[15];
   c.adxLen=(int)v[16];c.rsiLen=(int)v[17];c.pivot=(int)v[18];c.divAge=(int)v[19];c.atrMin=v[20];c.atrMax=v[21];c.dispMin=v[22];
   if(!MaParseClock(MaText("START"),c.startMin)||!MaParseClock(MaText("END"),c.endMin)){g_status="Window must be HH:MM; equal start/end = all day";return false;}
   if(!MaConfigValid(c)||PeriodSeconds((ENUM_TIMEFRAMES)c.htf)<PeriodSeconds(_Period)){g_status="Invalid range; ADX 0..100, periods positive, HTF >= chart TF";return false;}return true;
}
void MaStats(int &wins,int &losses,int &data,double &net,double &minimum,double &dd,int &rw[],int &rl[])
{
   wins=0;losses=0;data=0;net=0;minimum=0;dd=0;double peak=0;ArrayResize(rw,6);ArrayResize(rl,6);ArrayInitialize(rw,0);ArrayInitialize(rl,0);
   datetime cutoff=(datetime)(g_asof-(long)g_weeks*7*86400);
   for(int i=0;i<ArraySize(g_results);i++)
   {
      MaTrade t=g_results[i];if(t.at<cutoff)continue;if(t.data){data++;continue;}
      if(t.net>1e-10){wins++;if(t.regime>=0)rw[t.regime]++;}else if(t.net<-1e-10){losses++;if(t.regime>=0)rl[t.regime]++;}
      net+=t.net;minimum=MathMin(minimum,net);peak=MathMax(peak,net);dd=MathMax(dd,peak-net);
   }
}
void MaDraw()
{
   MaObject("BG",OBJ_RECTANGLE_LABEL,8,20,1045,560,"",C'17,24,35');
   MaObject("TITLE",OBJ_LABEL,22,28,0,0,"MA CROSSOVER 1.00 | "+_Symbol+" "+EnumToString(_Period)+" | "+g_activeName);
   MaButton("EA",825,27,105,g_enabled?"EA ON":"EA OFF",g_enabled);MaButton("LIB",938,27,100,"STRATEGIES");
   MaField("FAST",22,62,65,"Fast EMA",(string)g_cfg.fast);MaField("MEDIUM",99,62,70,"Mid EMA",(string)g_cfg.medium);
   MaField("SLOW",182,62,70,"Slow HMA",(string)g_cfg.slow);MaField("HTFLEN",265,62,80,"HTF HMA",(string)g_cfg.htfLen);
   string modes[]={"Fast/Medium","Fast/Slow","Medium/Slow"};MaButton("CROSS",363,78,160,modes[g_cfg.cross]);
   MaButton("HTFTF",536,78,130,EnumToString((ENUM_TIMEFRAMES)g_cfg.htf));MaButton("HTF",680,78,115,g_cfg.htfOn?"HTF ON":"HTF OFF",g_cfg.htfOn);
   MaButton("INV",808,78,110,g_cfg.invert?"INV ON":"INV OFF",g_cfg.invert);MaButton("APPLY",930,78,110,"APPLY ALL");
   MaField("SLPCT",22,113,65,"SL %",DoubleToString(g_cfg.slPct,2));MaField("TPPCT",99,113,65,"TP %",DoubleToString(g_cfg.tpPct,2));
   MaField("RR",182,113,65,"TP R",DoubleToString(g_cfg.rr,2));MaField("PIPS",265,113,80,"SL pips",DoubleToString(g_cfg.pips,1));
   MaField("ATRLEN",363,113,75,"ATR len",(string)g_cfg.atrLen);MaField("ATRMULT",450,113,75,"ATR SL x",DoubleToString(g_cfg.atrMult,2));
   string risk[]={"PERCENT SL/TP","ATR SL + R","PIP SL + R"};MaButton("RISK",540,130,170,risk[g_cfg.riskMode]);
   string management[]={"BASIC","BE","PARTIAL + BE","TRAIL + PARTIAL"};MaButton("MANAGE",725,130,192,management[g_cfg.management]);
   MaField("BER",22,165,70,"BE at R",DoubleToString(g_cfg.beR,2));MaField("PARTR",104,165,80,"Partial R",DoubleToString(g_cfg.partialR,2));
   MaField("PARTPCT",197,165,82,"Partial %",DoubleToString(g_cfg.partialPct,1));MaField("TRAIL",295,165,80,"Trail ATR",DoubleToString(g_cfg.trailMult,2));
   MaField("START",391,165,75,"GMT start",MaClock(g_cfg.startMin));MaField("END",480,165,75,"GMT end",MaClock(g_cfg.endMin));
   MaObject("RISKINFO",OBJ_LABEL,575,184,0,0,"Native risk "+DoubleToString(InpRiskPercent,2)+"% | fee assumption "+DoubleToString(InpRoundTurnNotionalFeePct,3)+"%");
   MaButton("VOL",22,218,100,g_cfg.volOn?"VOL ON":"VOL OFF",g_cfg.volOn);MaButton("ADX",132,218,100,g_cfg.adxOn?"ADX ON":"ADX OFF",g_cfg.adxOn);
   MaButton("DIV",242,218,120,g_cfg.divOn?"RSI DIV ON":"RSI DIV OFF",g_cfg.divOn);MaButton("ATR",372,218,130,g_cfg.atrOn?"ATR RANGE ON":"ATR RANGE OFF",g_cfg.atrOn);
   MaButton("FVG",512,218,110,g_cfg.fvgOn?"FVG ON":"FVG OFF",g_cfg.fvgOn);MaButton("DISP",632,218,120,g_cfg.dispOn?"DISP ON":"DISP OFF",g_cfg.dispOn);
   MaField("VOLX",22,250,70,"Vol x",DoubleToString(g_cfg.volMult,2));MaField("ADXMIN",105,250,80,"ADX 0-100",DoubleToString(g_cfg.adxMin,1));
   MaField("ADXPER",199,250,70,"ADX len",(string)g_cfg.adxLen);MaField("RSIPER",282,250,70,"RSI len",(string)g_cfg.rsiLen);
   MaField("PIVOT",365,250,70,"Pivot L/R",(string)g_cfg.pivot);MaField("DIVAGE",448,250,70,"Div age",(string)g_cfg.divAge);
   MaField("ATRMIN",531,250,80,"Min ATR %",DoubleToString(g_cfg.atrMin,2));MaField("ATRMAX",624,250,80,"Max ATR %",DoubleToString(g_cfg.atrMax,2));
   MaField("DISPMIN",720,250,85,"Body/ATR",DoubleToString(g_cfg.dispMin,2));
   int w,l,data,rw[],rl[];double net,minimum,dd;MaStats(w,l,data,net,minimum,dd,rw,rl);
   for(int i=0;i<6;i++){int count=rw[i]+rl[i];string label=LiqMacroRegimeShortName(i)+" "+(string)rw[i]+"W/"+(string)rl[i]+"L "+(count?DoubleToString(100.0*rw[i]/count,0):"-")+"%";
      MaButton("REG"+(string)i,22+i*169,307,158,label,(g_cfg.mask&(1<<i))!=0);}
   int weeks[]={2,5,10,20,52,104,156,208,260};string labels[]={"2W","5W","10W","20W","1Y","2Y","3Y","4Y","5Y"};
   for(int i=0;i<9;i++)MaButton("W"+(string)i,22+i*79,344,70,labels[i],g_weeks==weeks[i]);
   string days[]={"Su","Mo","Tu","We","Th","Fr","Sa"};for(int i=0;i<7;i++)MaButton("DAY"+(string)i,756+i*40,344,35,days[i],(g_cfg.weekMask&(1<<i))!=0);
   string stats=(g_ready?"":"BUILDING | ")+(string)w+"W "+(string)l+"L "+(string)(g_hasActive?1:0)+"O "+(string)data+" DATA | WR "+(w+l>0?DoubleToString(100.0*w/(w+l),1):"-")
      +"% | "+DoubleToString(net,2)+"R | MinCum "+DoubleToString(minimum,2)+"R | PeakDD "+DoubleToString(dd,2)+"R";
   MaObject("STATS",OBJ_LABEL,22,383,0,0,stats);ObjectSetInteger(0,g_prefix+"UI_STATS",OBJPROP_COLOR,net>=0?clrLimeGreen:clrTomato);
   MaObject("PROGRESSBG",OBJ_RECTANGLE_LABEL,22,410,1005,13,"",C'40,46,55');
   MaObject("PROGRESS",OBJ_RECTANGLE_LABEL,22,410,MathMax(1,(int)(10.05*g_progress)),13,"",C'28,146,147');
   MaObject("STATUS",OBJ_LABEL,22,434,0,0,StringSubstr(g_status,0,120));
   MaObject("NOTES",OBJ_LABEL,22,458,0,0,"Closed HTF / M1 spread estimate / SL+TP same M1 = DATA / initial ATR frozen / no ML or listener publication");
   MaObject("NOTES2",OBJ_LABEL,22,480,0,0,"Live remains OFF until enabled. Config changes require flat/off. Regime counts = selected execution stream.");
   MaButton("REFRESH",22,512,150,"REFRESH DATA");MaObject("CACHE",OBJ_LABEL,185,517,0,0,"Window changes slice cached entry cohorts; DATA is excluded, not counted as losses.");
   if(g_popup)
   {
      MaObject("POPBG",OBJ_RECTANGLE_LABEL,60,70,920,437,"",C'22,34,46');ObjectSetInteger(0,g_prefix+"UI_POPBG",OBJPROP_ZORDER,200);
      MaObject("POPTITLE",OBJ_LABEL,78,82,0,0,"YOUR STRATEGIES | current symbol / chart TF | click to apply");
      MaObject("POPSEARCH",OBJ_EDIT,78,111,430,24,g_query,C'38,48,62');MaButton("POPSEARCHBTN",520,111,90,"SEARCH");
      MaButton("POPFAV",622,111,120,g_favOnly?"FAVORITES":"ALL",g_favOnly);MaButton("POPPREV",754,111,40,"<");MaButton("POPNEXT",805,111,40,">");MaButton("POPX",919,78,40,"X");
      ArrayFree(g_visible);string needle=g_query;StringToLower(needle);
      for(int i=0;i<ArraySize(g_names);i++){string name=g_names[i];StringToLower(name);if((needle!=""&&StringFind(name,needle)<0)||(g_favOnly&&!g_favorites[i]))continue;
         int j=ArraySize(g_visible);ArrayResize(g_visible,j+1);g_visible[j]=i;}
      int pages=MathMax(1,(ArraySize(g_visible)+7)/8);g_page=MathMax(0,MathMin(pages-1,g_page));
      for(int row=0;row<8;row++){int at=g_page*8+row;if(at>=ArraySize(g_visible)){ObjectDelete(0,g_prefix+"UI_POPROW"+(string)row);ObjectDelete(0,g_prefix+"UI_POPSTAR"+(string)row);continue;}
         int i=g_visible[at];MaButton("POPROW"+(string)row,78,153+row*30,777,g_names[i]);MaButton("POPSTAR"+(string)row,865,153+row*30,90,g_favorites[i]?"FAV YES":"FAVORITE",g_favorites[i]);}
      MaObject("POPNAME",OBJ_EDIT,78,407,620,24,"",C'38,48,62');MaButton("POPSAVE",712,407,240,"SAVE CURRENT SETTINGS");
      MaObject("POPNOTE",OBJ_LABEL,78,453,0,0,ArraySize(g_names)==0?"Library is empty. Set parameters, APPLY ALL, then save a name.":StringSubstr(g_status,0,110));
   }
}
void MaLevel(string key,datetime from,datetime to,double price,color c)
{
   if(price<=0||to<=from)return;string name=g_prefix+"H_"+key;
   ObjectCreate(0,name,OBJ_TREND,0,from,price,to,price);ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);ObjectSetInteger(0,name,OBJPROP_COLOR,c);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void MaDrawHistory()
{
   ObjectsDeleteAll(0,g_prefix+"H_");datetime cutoff=(datetime)(g_asof-(long)g_weeks*7*86400);int drawn=0;
   for(int i=ArraySize(g_results)-1;i>=0&&drawn<InpMaxDrawTrades;i--)
   {
      MaTrade t=g_results[i];if(t.at<cutoff)break;if(t.data)continue;drawn++;
      datetime end=t.at+20*PeriodSeconds(_Period);if(i+1<ArraySize(g_results))end=MathMin(end,g_results[i+1].at);
      if(g_hasActive&&g_active.at>t.at)end=MathMin(end,g_active.at);
      string id=(string)t.at;MaLevel(id+"E",t.at,end,t.entry,clrWhite);MaLevel(id+"S",t.at,end,t.initialStop,clrTomato);MaLevel(id+"T",t.at,end,t.initialTarget,clrLimeGreen);
      int bar=MaLastClosed(g_rates,t.signal+PeriodSeconds(_Period),PeriodSeconds(_Period));
      double arrow=bar>=0?(t.direction>0?g_rates[bar].low:g_rates[bar].high):t.entry;
      string name=g_prefix+"H_"+id+"A";ObjectCreate(0,name,OBJ_ARROW,0,t.signal,arrow);
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,t.direction>0?233:234);ObjectSetInteger(0,name,OBJPROP_COLOR,t.net>=0?clrLimeGreen:clrTomato);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,t.reason+" "+DoubleToString(t.net,3)+"R | entry "+TimeToString(t.at)+" | exit "+TimeToString(t.exitAt));
   }
   if(g_hasActive){datetime end=g_active.at+20*PeriodSeconds(_Period);MaLevel("ACTIVE_E",g_active.at,end,g_active.entry,clrWhite);MaLevel("ACTIVE_S",g_active.at,end,g_active.stop,clrTomato);MaLevel("ACTIVE_T",g_active.at,end,g_active.target,clrLimeGreen);}
   if(InpDrawRejectedSignals){int count=0;for(int i=ArraySize(g_rates)-1;i>=0&&count<InpMaxDrawTrades;i--){if(g_rates[i].time<cutoff)break;
      if(g_ma.direction[i]==0||g_rejects[i]=="")continue;string name=g_prefix+"H_W"+(string)g_rates[i].time;
      ObjectCreate(0,name,OBJ_ARROW,0,g_rates[i].time,g_ma.direction[i]>0?g_rates[i].low:g_rates[i].high);ObjectSetInteger(0,name,OBJPROP_ARROWCODE,159);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrDarkGray);ObjectSetString(0,name,OBJPROP_TOOLTIP,"WINDOW "+g_rejects[i]);count++;}}
}
void MaUiEvent(int id,string name)
{
   if(id!=CHARTEVENT_OBJECT_CLICK)return;
   if((ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE)!=OBJ_BUTTON)return;
   string prefix=g_prefix+"UI_";if(StringFind(name,prefix)!=0)return;string key=StringSubstr(name,StringLen(prefix));
   if(g_popup&&StringFind(key,"POP")!=0)return;
   if(key=="LIB"){g_popup=true;MaLoadLibrary();MaDraw();return;}
   if(key=="POPX"){g_popup=false;ObjectsDeleteAll(0,g_prefix+"UI_POP");MaDraw();return;}
   if(StringFind(key,"POP")==0)
   {
      if(key=="POPSEARCHBTN"){g_query=MaText("POPSEARCH");g_page=0;}
      else if(key=="POPPREV")g_page--;else if(key=="POPNEXT")g_page++;else if(key=="POPFAV")g_favOnly=!g_favOnly;
      else if(key=="POPSAVE")MaSaveStrategy(MaText("POPNAME"));
      else if(StringFind(key,"POPROW")==0||StringFind(key,"POPSTAR")==0)
      {bool row=StringFind(key,"POPROW")==0;int at=g_page*8+(int)StringToInteger(StringSubstr(key,row?6:7));
         if(at>=0&&at<ArraySize(g_visible)){int i=g_visible[at];if(row)MaApplyStrategy(i);else{
            string path="MaCrossOverStrategies\\"+g_files[i]+".fav";if(g_favorites[i])FileDelete(path,FILE_COMMON);else MaWrite(path,"1");MaLoadLibrary();}}}
      MaDraw();return;
   }
   if(key=="EA")
   {
      if(g_enabled)g_enabled=false;
      else if(!InpAllowNativeTrading||g_lease<=0||!g_ready){g_status="Enable InpAllowNativeTrading on a hedging account; wait for data first";}
      else {g_enabled=true;g_armedAfter=TimeCurrent();g_status="Native ON: only future closed-bar signals";}MaDraw();return;
   }
   if(StringFind(key,"W")==0){int i=(int)StringToInteger(StringSubstr(key,1));int weeks[]={2,5,10,20,52,104,156,208,260};
      if(i>=0&&i<9){g_weeks=weeks[i];if(g_ready)MaDrawHistory();MaDraw();}return;}
   if(!MaCanEdit()){MaDraw();return;}
   if(key=="REFRESH"){MaInvalidate();return;}
   MaConfig c;if(!MaReadEdits(c)){MaDraw();return;}
   if(key=="CROSS")c.cross=(c.cross+1)%3;else if(key=="HTF")c.htfOn=!c.htfOn;
   else if(key=="HTFTF"){int frames[]={PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H2,PERIOD_H4,PERIOD_D1};int j=0;for(int i=0;i<6;i++)if(frames[i]==c.htf)j=(i+1)%6;c.htf=frames[j];}
   else if(key=="RISK")c.riskMode=(c.riskMode+1)%3;else if(key=="MANAGE")c.management=(c.management+1)%4;
   else if(key=="INV")c.invert=!c.invert;else if(key=="VOL")c.volOn=!c.volOn;else if(key=="ADX")c.adxOn=!c.adxOn;
   else if(key=="DIV")c.divOn=!c.divOn;else if(key=="ATR")c.atrOn=!c.atrOn;else if(key=="FVG")c.fvgOn=!c.fvgOn;else if(key=="DISP")c.dispOn=!c.dispOn;
   else if(StringFind(key,"REG")==0){int i=(int)StringToInteger(StringSubstr(key,3));if(i>=0&&i<6)c.mask^=1<<i;}
   else if(StringFind(key,"DAY")==0){int i=(int)StringToInteger(StringSubstr(key,3));if(i>=0&&i<7)c.weekMask^=1<<i;}
   if(PeriodSeconds((ENUM_TIMEFRAMES)c.htf)<PeriodSeconds(_Period)){g_status="HTF must not be below chart timeframe";MaDraw();return;}
   g_cfg=c;g_activeName="CUSTOM";MaInvalidate();ObjectsDeleteAll(0,g_prefix+"UI_");MaDraw();
}
#endif
