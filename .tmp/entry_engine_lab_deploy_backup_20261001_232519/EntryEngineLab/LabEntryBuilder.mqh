#ifndef LAB_ENTRY_BUILDER_MQH
#define LAB_ENTRY_BUILDER_MQH
#include "LabScalperPresets.mqh"
int g_labUi=0,g_labPage=0,g_labSide=0,g_labFeatureRow=-1,g_labOperandSide=0;
string g_labQuery="",g_labMessage="";
LabEngine g_labDraft,g_labLibrary[];
string LabUiPrefix(){return PREFIX+"LABUI_";}
string LabLibraryFolder(){return "EntryEngineLabEngines\\";}
string LabEngineFile(string name){StringToLower(name);return LabLibraryFolder()+StringSubstr(OrbMlSha256(name),0,32)+".engine";}
string LabActiveFile(){return LabLibraryFolder()+"active_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+(string)ChartID()+".state";}
bool LabReadFile(string path,LabEngine &e){string v[];return OrbMlReadLines(path,v,2,true)&&LabEngineRead(v[0],e);}
bool LabPersistActive(){return LabValidEngine(g_labEngine)&&OrbMlAtomicProtocol(LabActiveFile(),LabEngineIdentity()+"\n");}
void LabRestoreActive(){LabEngine e;if(g_rtMaCrossMode==MA_CROSS_LAB_RULES){if(LabReadFile(LabActiveFile(),e))g_labEngine=e;else g_rtMaCrossMode=MA_CROSS_ORIGINAL_MTF;}}
void LabReloadLibrary()
{
   ArrayResize(g_labLibrary,10);for(int i=0;i<10;i++)LabScalperPreset(i,g_labLibrary[i]);
   string name="";long h=FileFindFirst(LabLibraryFolder()+"*.engine",name,FILE_COMMON);if(h==INVALID_HANDLE)return;
   do{LabEngine e;if(!LabReadFile(LabLibraryFolder()+name,e)||name!=StringSubstr(LabEngineFile(e.name),StringLen(LabLibraryFolder())))continue;
      int found=-1;for(int i=0;i<ArraySize(g_labLibrary);i++)if(LabEngineFile(e.name)==LabEngineFile(g_labLibrary[i].name)){found=i;break;}
      if(found>=0){g_labLibrary[found]=e;continue;}
      int n=ArraySize(g_labLibrary);if(n>=1024)break;ArrayResize(g_labLibrary,n+1);g_labLibrary[n]=e;
   }while(FileFindNext(h,name));FileFindClose(h);
}
bool LabStoreEngine(const LabEngine &e)
{
   if(!LabValidEngine(e))return false;
   int lock=FileOpen(LabLibraryFolder()+"save.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);if(lock==INVALID_HANDLE)return false;
   bool ok=OrbMlAtomicProtocol(LabEngineFile(e.name),LabEngineText(e)+"\n");FileClose(lock);return ok;
}
void LabActivate(const LabEngine &e,bool preview)
{
   if(e.policy&&!preview&&(OwnPositionExists()||g_orbBridgePlanActive||MaIndependentOrdersPending()))
   {g_lastExecStatus="LAB POLICY: close existing positions/plan before changing engine";return;}
   g_labEngine=e;g_labPreviewOnly=preview;
   if(e.policy){g_rtPipSlMode=true;if(e.pipSl)g_rtPipSlPips=e.pipSlPips;}
   if(e.policy){if(preview){g_rtSignalTf=PERIOD_M1;g_rtEntryMode=ORB_ENTRY_BREAKOUT;g_rtExitMode=ORB_EXIT_FIXED_TARGET;
      g_rtTargetMode=ORB_TARGET_R_LEG;g_rtCustomR=e.tpAtr/e.slAtr;g_rtTargetLeg=(int)ORB_TARGET_CUSTOM;
      g_rtHalfBeLeg=0;g_rtBEOnTp1=false;g_rtTimeExit=false;g_maIndependent=false;g_maReverseExit=false;}
      else if(!LabConfigurePolicySelection()){g_labPreviewOnly=true;return;}}
   if(preview)g_rtMaCrossMode=MA_CROSS_LAB_RULES;
   else if(!SetRuntimeMaCrossMode(MA_CROSS_LAB_RULES)){g_labPreviewOnly=true;g_labMessage="Mode persistence failed; live entries remain blocked.";return;}
   // Preview is intentionally not persisted or permitted to enter native/bridge trades.
   if(!preview&&!LabPersistActive()){g_labPreviewOnly=true;g_labMessage="Engine persistence failed; live entries remain blocked.";return;}
   MaCrossAuditInvalidate();CancelHistoricalAuditBuild();
   // Selection is not permission to replay an already completed setup live.
   g_lastSignalBarTime=iTime(_Symbol,g_rtSignalTf,1);g_lastCheckedSignalBarTime=g_lastSignalBarTime;
   OrbStrategyPresetSetEdit("EDIT_SL_VALUE",RuntimeSlEditValue());
   QueueHistoricalRedraw(0);UpdateDashboard();
}
bool LabNumber(string s,double &v){StringTrimLeft(s);StringTrimRight(s);return OrbMlNumber(s,v)&&MathIsValidNumber(v)&&v!=EMPTY_VALUE;}
void LabUiObject(string name){
   string id=LabUiPrefix()+name;long type=ObjectGetInteger(0,id,OBJPROP_TYPE);
   long layer=name=="BG"?0:(type==OBJ_EDIT?3:(type==OBJ_BUTTON?2:1));
   ObjectSetInteger(0,id,OBJPROP_ZORDER,DASH_Z+10000+layer);}
// Modal layout is already in chart pixels, not the inherited dashboard canvas.
void LabUiPosition(string name,int x,int y,int w=0,int h=0,int font=0)
{
   string id=LabUiPrefix()+name;
   ObjectSetInteger(0,id,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,id,OBJPROP_YDISTANCE,y);
   if(w>0)ObjectSetInteger(0,id,OBJPROP_XSIZE,w);
   if(h>0)ObjectSetInteger(0,id,OBJPROP_YSIZE,h);
   if(font>0)ObjectSetInteger(0,id,OBJPROP_FONTSIZE,font);
   LabUiObject(name);
}
void LabButton(string name,int x,int y,int w,string text,color bg)
{CreateButton("LABUI_"+name,x,y,w,23,text,bg);LabUiPosition(name,x,y,w,23,9);}
void LabEdit(string name,int x,int y,int w,string text)
{CreateEdit("LABUI_"+name,x,y,w,23,text);LabUiPosition(name,x,y,w,23,9);}
void LabLabel(string name,int x,int y,string text,color c=clrSilver)
{CreateLabel("LABUI_"+name,x,y,text,c,9);LabUiPosition(name,x,y,0,0,9);}
int LabDraftSize(){return g_labSide==0?ArraySize(g_labDraft.buy):(g_labSide==1?ArraySize(g_labDraft.sell):(g_labSide==2?ArraySize(g_labDraft.exitBuy):ArraySize(g_labDraft.exitSell)));}
LabRule LabDraftRule(int i){if(g_labSide==0)return g_labDraft.buy[i];if(g_labSide==1)return g_labDraft.sell[i];if(g_labSide==2)return g_labDraft.exitBuy[i];return g_labDraft.exitSell[i];}
void LabDraftAssign(int i,const LabRule &r){if(g_labSide==0)g_labDraft.buy[i]=r;else if(g_labSide==1)g_labDraft.sell[i]=r;else if(g_labSide==2)g_labDraft.exitBuy[i]=r;else g_labDraft.exitSell[i]=r;}
bool LabCommitEdits()
{
   if(g_labUi==4){LabEngine e=g_labDraft;double sl=0,tp=0;int cd=0,bars=0,minutes=0;
      if(!LabInteger(ObjectGetString(0,LabUiPrefix()+"P_COOLDOWN",OBJPROP_TEXT),cd)
         ||!LabInteger(ObjectGetString(0,LabUiPrefix()+"P_BARS",OBJPROP_TEXT),bars)
         ||!LabInteger(ObjectGetString(0,LabUiPrefix()+"P_MINUTES",OBJPROP_TEXT),minutes)
         ||!LabNumber(ObjectGetString(0,LabUiPrefix()+"P_SL",OBJPROP_TEXT),sl)
         ||!LabNumber(ObjectGetString(0,LabUiPrefix()+"P_TP",OBJPROP_TEXT),tp)){g_labMessage="Invalid policy inputs";return false;}
      e.pipSl=true;e.pipSlPips=sl;e.slAtr=1;e.tpAtr=tp;e.cooldown=cd;e.maxBars=bars;e.maxMinutes=minutes;
      bool was=e.policy;e.policy=true;if(!LabValidEngine(e)){g_labMessage="Policy values out of range";return false;}e.policy=was;g_labDraft=e;return true;}
   if(g_labUi!=2)return true;
   g_labDraft.name=ObjectGetString(0,LabUiPrefix()+"NAME",OBJPROP_TEXT);StringTrimLeft(g_labDraft.name);StringTrimRight(g_labDraft.name);
   int n=LabDraftSize();
   for(int j=0;j<8;j++){int i=g_labPage*8+j;if(i>=n)break;double value=0;
      if(!LabNumber(ObjectGetString(0,LabUiPrefix()+"VALUE_"+(string)i,OBJPROP_TEXT),value)){g_labMessage="Invalid numeric threshold on row "+(string)(i+1);return false;}
      LabRule r=LabDraftRule(i);r.threshold=value;
      string lp=ObjectGetString(0,LabUiPrefix()+"PERIOD_"+(string)i,OBJPROP_TEXT),rp=ObjectGetString(0,LabUiPrefix()+"RPERIOD_"+(string)i,OBJPROP_TEXT);
      int leftPeriod=0,rightPeriod=0;if(!LabInteger(lp,leftPeriod)||!LabInteger(rp,rightPeriod)||leftPeriod<1||leftPeriod>5000||rightPeriod<1||rightPeriod>5000){g_labMessage="Indicator periods must be integer 1-5000.";return false;}
      r.period=leftPeriod;r.rhsPeriod=rightPeriod;LabDraftAssign(i,r);
   }return true;
}
bool LabMatch(string name)
{
   string s=name,q=g_labQuery;StringTrimLeft(q);StringTrimRight(q);
   if(q=="")return true;
   StringToLower(s);StringToLower(q);return StringFind(s,q)>=0;
}
void LabUiDraw()
{
   if(g_labUi==0)return;
   ObjectsDeleteAll(0,LabUiPrefix());
   int width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   int w=MathMin(820,MathMax(620,width-32)),h=MathMin(470,MathMax(400,height-32));int x=MathMax(8,(width-w)/2),y=MathMax(8,(height-h)/2);
   CreateRect("LABUI_BG",x,y,w,h,C'24,30,42',C'90,178,255');LabUiPosition("BG",x,y,w,h);
   LabLabel("TITLE",x+14,y+12,g_labUi==1?"ENTRY ENGINES":(g_labUi==3?"SELECT FEATURE":(g_labUi==4?"PIP SL / DEFAULT R / EXIT POLICY":"ENTRY ENGINE BUILDER // CLOSED BARS")),C'90,178,255');
   LabButton("CLOSE",x+w-48,y+8,34,"X",C'100,55,55');
   if(g_labUi==4)
   {
      LabButton("P_ON",x+14,y+48,220,g_labDraft.policy?"ENGINE POLICY: ON":"ENGINE POLICY: OFF",g_labDraft.policy?C'30,120,70':C'70,70,70');
      string fields[]={"SL","TP","COOLDOWN","BARS","MINUTES"};
      string labels[]={"SL (pips, 0.1 - 1000000)","Default target (R)","Cooldown (closed candle boundaries)","Maximum hold (candles, 0=OFF)","Maximum hold (minutes, 0=OFF)"};
      string val[]={StringFormat("%.12g",g_labDraft.pipSlPips),StringFormat("%.12g",g_labDraft.tpAtr/g_labDraft.slAtr),(string)g_labDraft.cooldown,(string)g_labDraft.maxBars,(string)g_labDraft.maxMinutes};
      for(int i=0;i<5;i++){LabLabel("PL_"+fields[i],x+14,y+92+i*34,labels[i]);LabEdit("P_"+fields[i],x+w-140,y+86+i*34,120,val[i]);}
      LabLabel("P_INFO",x+14,y+307,"Classic PIP SL + dashboard R. Native MT5 only: PUB OFF / NAT ON.");
      LabLabel("P_INFO2",x+14,y+328,"LONG EXIT / SHORT EXIT rules are separate. Exit fills use existing tick replay.");
      LabButton("P_APPLY",x+14,y+h-54,240,"APPLY TO ENGINE DRAFT",C'38,101,176');
      LabLabel("NOTE",x+14,y+h-22,g_labMessage,clrKhaki);
   }
   else if(g_labUi==2)
   {
      LabEdit("NAME",x+14,y+42,w-28,g_labDraft.name);
      LabButton("BUY",x+14,y+74,60,"BUY",g_labSide==0?C'30,120,70':C'70,70,70');
      LabButton("SELL",x+78,y+74,60,"SELL",g_labSide==1?C'140,55,55':C'70,70,70');
      LabButton("LONGEXIT",x+142,y+74,80,"LONG EXIT",g_labSide==2?C'184,103,22':C'70,70,70');
      LabButton("SHORTEXIT",x+226,y+74,80,"SHORT EXIT",g_labSide==3?C'184,103,22':C'70,70,70');
      LabButton("EDGE",x+310,y+74,110,g_labDraft.edge?"FALSE -> TRUE":"EVERY BAR",C'38,101,176');
      LabButton("POLICY",x+w-198,y+74,86,"POLICY",C'38,101,176');
      LabButton("ADD",x+w-100,y+74,86,"+ LOGIC",C'30,120,70');
      LabLabel("FOLD",x+14,y+105,"Left to right: ((A gate B) gate C). NOT negates one condition. Missing != false.");
      int n=LabDraftSize();g_labPage=MathMin(g_labPage,MathMax(0,(n-1)/8));
      for(int j=0;j<8;j++)
      {
         int i=g_labPage*8+j;if(i>=n)break;LabRule r=LabDraftRule(i);int ry=y+128+j*27;
         LabButton("GATE_"+(string)i,x+14,ry,64,i==0?"START":LabGateName(r.gate),C'60,65,80');
         LabButton("NOT_"+(string)i,x+82,ry,36,r.negate?"NOT":"-",r.negate?C'140,70,30':C'60,65,80');
         int fw=(w-486)/2;
         LabButton("FEATURE_"+(string)i,x+122,ry,fw,LabFeatureName(r.feature),C'38,101,176');
         LabEdit("PERIOD_"+(string)i,x+126+fw,ry,48,(string)r.period);
         LabButton("CMP_"+(string)i,x+178+fw,ry,84,LabCompareName(r.compare),C'60,65,80');
         LabButton("RHS_"+(string)i,x+266+fw,ry,fw,r.rhsFeature<0?"CONSTANT":LabFeatureName(r.rhsFeature),C'38,101,176');
         LabEdit("RPERIOD_"+(string)i,x+270+2*fw,ry,48,(string)r.rhsPeriod);
         LabEdit("VALUE_"+(string)i,x+322+2*fw,ry,96,StringFormat("%.12g",r.threshold));
         LabButton("DEL_"+(string)i,x+422+2*fw,ry,32,"-",C'120,55,55');
         ObjectSetString(0,LabUiPrefix()+"PERIOD_"+(string)i,OBJPROP_TOOLTIP,"Left indicator period (only for parameterized features)");
         ObjectSetString(0,LabUiPrefix()+"RPERIOD_"+(string)i,OBJPROP_TOOLTIP,"Right indicator period");
         ObjectSetString(0,LabUiPrefix()+"VALUE_"+(string)i,OBJPROP_TOOLTIP,"Threshold used only when right operand is CONSTANT");
      }
      LabButton("PREV",x+14,y+348,40,"<",C'60,65,80');LabButton("NEXT",x+60,y+348,40,">",C'60,65,80');
      LabLabel("PAGE",x+110,y+354,"Page "+(string)(g_labPage+1)+" // "+(string)n+" rules // empty side disabled");
      LabButton("PREVIEW",x+14,y+h-54,180,"APPLY + AUDIT PREVIEW",C'38,101,176');
      LabButton("SAVE",x+202,y+h-54,156,"SAVE ENGINE",C'30,120,70');
      LabLabel("NOTE",x+14,y+h-22,StringSubstr(g_labMessage,0,100),clrKhaki);
   }
   else
   {
      LabEdit("SEARCH",x+14,y+42,w-140,g_labQuery);LabButton("SEARCHGO",x+w-116,y+42,102,"SEARCH",C'38,101,176');
      int ids[];
      if(g_labUi==1){for(int i=0;i<6;i++)if(LabMatch(MaCrossModeText((MA_CROSS_SIGNAL_MODE)i))){int n=ArraySize(ids);ArrayResize(ids,n+1);ids[n]=i;}
         for(int i=0;i<ArraySize(g_labLibrary);i++)if(LabMatch(g_labLibrary[i].name)){int n=ArraySize(ids);ArrayResize(ids,n+1);ids[n]=6+i;}}
      else {if(g_labOperandSide==1&&LabMatch("CONSTANT")){ArrayResize(ids,1);ids[0]=-1;}for(int i=0;i<LAB_FEATURES;i++)if(LabMatch(LabFeatureName(i))){int n=ArraySize(ids);ArrayResize(ids,n+1);ids[n]=i;}}
      g_labPage=MathMin(g_labPage,MathMax(0,(ArraySize(ids)-1)/10));
      for(int j=0;j<10;j++){int at=g_labPage*10+j;if(at>=ArraySize(ids))break;int i=ids[at];string name=g_labUi==3?(i<0?"CONSTANT":LabFeatureName(i)):(i<6?"BUILT-IN: "+MaCrossModeText((MA_CROSS_SIGNAL_MODE)i):"CUSTOM: "+g_labLibrary[i-6].name);
         LabButton("PICK_"+(string)i,x+14,y+80+j*27,w-28,name,C'38,70,105');}
      if(ArraySize(ids)==0)LabLabel("EMPTY",x+14,y+88,"No matches. Clear the search to show all choices.",clrKhaki);
      LabButton("PREV",x+14,y+h-54,40,"<",C'60,65,80');LabButton("NEXT",x+60,y+h-54,40,">",C'60,65,80');
      LabLabel("PAGE",x+112,y+h-48,"Page "+(string)(g_labPage+1)+" // "+(string)ArraySize(ids)+" matches");
      if(g_labUi==1)LabButton("BUILD",x+w-194,y+h-54,180,"NEW / EDIT ENGINE",C'184,103,22');
   }
   ChartRedraw(0);
}
void LabOpenBuilder()
{
   g_labDraft=g_labEngine;if(!LabValidEngine(g_labDraft)){g_labDraft.name="New engine";g_labDraft.edge=true;ArrayResize(g_labDraft.buy,1);ArrayResize(g_labDraft.sell,1);
      LabRule r;LabRuleDefaults(r);r.feature=4;r.threshold=50;g_labDraft.buy[0]=r;r.compare=1;g_labDraft.sell[0]=r;}
   if(g_labDraft.atrPeriod<1)g_labDraft.atrPeriod=14;if(g_labDraft.slAtr<=0)g_labDraft.slAtr=1;if(g_labDraft.tpAtr<=0)g_labDraft.tpAtr=1;
   g_labUi=2;g_labPage=g_labSide=0;g_labMessage="Preview uses current audit window and all current risk/filter settings; native/PUB entries blocked.";LabUiDraw();
}
void LabRemoveRule(LabRule &rows[],int i){int n=ArraySize(rows);for(int k=i;k<n-1;k++)rows[k]=rows[k+1];ArrayResize(rows,n-1);}
bool LabUiEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(g_labUi==0&&id==CHARTEVENT_OBJECT_CLICK&&sparam==PREFIX+"BTN_LAB_ENGINES"){g_labUi=1;g_labQuery="";g_labPage=0;LabReloadLibrary();LabUiDraw();return true;}
   if(g_labUi==0&&id==CHARTEVENT_OBJECT_CLICK&&sparam==PREFIX+"BTN_LAB_BUILD"){LabOpenBuilder();return true;}
   if(g_labUi==0)return false;
   if(id==CHARTEVENT_CHART_CHANGE){LabCommitEdits();LabUiDraw();return true;}
   // Consume every event while open. Never route a click to an underlying modal.
   if(id!=CHARTEVENT_OBJECT_CLICK)return true;
   if(StringFind(sparam,LabUiPrefix())!=0){ObjectSetInteger(0,sparam,OBJPROP_STATE,false);return true;}
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);string key=StringSubstr(sparam,StringLen(LabUiPrefix()));
   if(key=="CLOSE"){if(g_labUi==3||g_labUi==4){int page=g_labUi==3?g_labFeatureRow/8:0;g_labUi=2;g_labPage=page;LabUiDraw();}else{g_labUi=0;ObjectsDeleteAll(0,LabUiPrefix());UpdateDashboard();}return true;}
   if(key=="NAME"||key=="SEARCH"||key=="BG"||StringFind(key,"VALUE_")==0||StringFind(key,"PERIOD_")==0||StringFind(key,"RPERIOD_")==0)return true;
   if(key=="P_ATR"||key=="P_SL"||key=="P_TP"||key=="P_COOLDOWN"||key=="P_BARS"||key=="P_MINUTES")return true;
   if(g_labUi==4){if(!LabCommitEdits()){LabUiDraw();return true;}if(key=="P_ON")g_labDraft.policy=!g_labDraft.policy;
      if(key=="P_APPLY"){g_labUi=2;g_labPage=0;g_labMessage="Policy applied to draft. PREVIEW or SAVE ENGINE to use it.";}LabUiDraw();return true;}
   if(g_labUi==2&&!LabCommitEdits()){LabLabel("NOTE",(int)ObjectGetInteger(0,LabUiPrefix()+"BG",OBJPROP_XDISTANCE)+14,(int)ObjectGetInteger(0,LabUiPrefix()+"BG",OBJPROP_YDISTANCE)+445,g_labMessage,clrTomato);return true;}
   if(key=="BUILD"){LabOpenBuilder();return true;}
   if(key=="SEARCHGO"){g_labQuery=ObjectGetString(0,LabUiPrefix()+"SEARCH",OBJPROP_TEXT);StringTrimLeft(g_labQuery);StringTrimRight(g_labQuery);g_labPage=0;}
   if(key=="PREV")g_labPage=MathMax(0,g_labPage-1);if(key=="NEXT")g_labPage++;
   if(g_labUi==2)
   {
      if(key=="BUY"||key=="SELL"||key=="LONGEXIT"||key=="SHORTEXIT"){g_labSide=key=="BUY"?0:(key=="SELL"?1:(key=="LONGEXIT"?2:3));g_labPage=0;}
      if(key=="POLICY"){g_labUi=4;LabUiDraw();return true;}
      if(key=="EDGE")g_labDraft.edge=!g_labDraft.edge;
      if(key=="ADD"){int n=LabDraftSize();if(n<LAB_MAX_RULES){LabRule r;LabRuleDefaults(r);r.feature=4;r.threshold=50;
         if(g_labSide==0)ArrayResize(g_labDraft.buy,n+1);else if(g_labSide==1)ArrayResize(g_labDraft.sell,n+1);else if(g_labSide==2)ArrayResize(g_labDraft.exitBuy,n+1);else ArrayResize(g_labDraft.exitSell,n+1);
         LabDraftAssign(n,r);g_labPage=n/8;}}
      string row[];if(StringSplit(key,'_',row)==2)
      {int i=(int)StringToInteger(row[1]),n=LabDraftSize();if(i>=0&&i<n){LabRule r=LabDraftRule(i);
         if(row[0]=="FEATURE"||row[0]=="RHS"){g_labOperandSide=row[0]=="RHS"?1:0;g_labFeatureRow=i;g_labUi=3;g_labQuery="";g_labPage=0;}
         if(row[0]=="GATE")r.gate=(r.gate+1)%3;if(row[0]=="NOT")r.negate=!r.negate;if(row[0]=="CMP")r.compare=(r.compare+1)%8;
         LabDraftAssign(i,r);
         if(row[0]=="DEL"){if(g_labSide==0)LabRemoveRule(g_labDraft.buy,i);else if(g_labSide==1)LabRemoveRule(g_labDraft.sell,i);else if(g_labSide==2)LabRemoveRule(g_labDraft.exitBuy,i);else LabRemoveRule(g_labDraft.exitSell,i);}
      }}
      if(key=="PREVIEW"||key=="SAVE")
      {
         if(!LabValidEngine(g_labDraft))g_labMessage="Invalid name/rules. Max 4096 rows/side, 64 distinct indicator/period pairs.";
         else if(key=="SAVE"){g_labMessage=LabStoreEngine(g_labDraft)?"Engine saved (same name updates). Select it from ENGINES to enable live entries.":"Save failed; retry.";}
         else{LabActivate(g_labDraft,true);g_labUi=0;ObjectsDeleteAll(0,LabUiPrefix());return true;}
      }
   }
   else if(StringFind(key,"PICK_")==0)
   {
      int i=(int)StringToInteger(StringSubstr(key,5));
      if(g_labUi==3&&i>=(g_labOperandSide==1?-1:0)&&i<LAB_FEATURES)
      {LabRule r=LabDraftRule(g_labFeatureRow);if(g_labOperandSide==0)r.feature=i;else r.rhsFeature=i;LabDraftAssign(g_labFeatureRow,r);g_labUi=2;g_labPage=g_labFeatureRow/8;}
      else if(g_labUi==1)
      {
         if(i>=0&&i<6){SetRuntimeMaCrossMode((MA_CROSS_SIGNAL_MODE)i);g_labPreviewOnly=false;MaCrossAuditInvalidate();CancelHistoricalAuditBuild();QueueHistoricalRedraw(0);}
         else if(i>=6&&i-6<ArraySize(g_labLibrary))LabActivate(g_labLibrary[i-6],false);
         g_labUi=0;ObjectsDeleteAll(0,LabUiPrefix());UpdateDashboard();return true;
      }
   }
   LabUiDraw();return true;
}
#endif
