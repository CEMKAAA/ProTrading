#ifndef TRADE_CALENDAR_MATRIX_MQH
#define TRADE_CALENDAR_MATRIX_MQH
#include "DailyTradeQuota.mqh"

enum ENTRY_DIRECTION_MODE { ENTRY_BOTH=0, ENTRY_BUY_ONLY=1, ENTRY_SELL_ONLY=2 };
input group "Entry Direction"
input ENTRY_DIRECTION_MODE InpEntryDirection=ENTRY_BOTH;
int g_entryDirection=0,g_directionBuyLosses=0,g_directionSellLosses=0;
double g_directionMinCum=0.0;
bool EntryDirectionAllows(int effectiveDirection)
{
   return (effectiveDirection==1||effectiveDirection==-1)
      &&(g_entryDirection==0||(g_entryDirection==1&&effectiveDirection==1)
         ||(g_entryDirection==2&&effectiveDirection==-1));
}
string EntryDirectionLabel()
{return g_entryDirection==1?"BUY ONLY":(g_entryDirection==2?"SELL ONLY":"BOTH");}
string DirectionLossText()
{return "Loss BUY:"+(string)g_directionBuyLosses+" SELL:"+(string)g_directionSellLosses;}
void DirectionRecordLoss(int effectiveDirection)
{
   if(effectiveDirection==1)g_directionBuyLosses++;
   else if(effectiveDirection==-1)g_directionSellLosses++;
}
// Missing field in an older strategy means BOTH, never the previous selection.
int DirectionStrategyMode(string text)
{
   string parts[];int count=StringSplit(StringSubstr(text,6),',',parts);
   if(count==8)return 0;
   if(count!=9&&count!=11&&count!=12)return -1;
   int mode=(int)StringToInteger(parts[8]);
   return mode>=0&&mode<=2&&parts[8]==(string)mode?mode:-1;
}

// Calendar statistics use completed audit trades only; the EA supplies its displayed clock.
input group "Entry Time Matrix"
input bool InpTimeMatrixEnabled=false;
input int InpTimeMatrixDays=127;       // Bits 0..6: Sunday..Saturday.
input int InpTimeMatrixHours=16777215; // Bits 0..23: 00:00..23:00.
int g_tcalWins[7][24],g_tcalLosses[7][24];
int g_tcalDayHours[7],g_tcalDraftDayHours[7];
bool g_tcalEnabled=false,g_tcalOpen=false,g_tcalChanged=false,g_tcalUiDirty=true;
int g_tcalView=0,g_tcalPage=0,g_tcalDay=1;
int g_tcalRankMode=2; // 0: day, 1: hour, 2: day-hour.
int g_tcalRankPickCount=0;
bool g_tcalRankPending=false,g_tcalDraftEdited=false;
int g_tcalMinSample=10;
int g_tcalX=0,g_tcalY=0;
string g_tcalPrefix="";
string g_tcalClockLabel="BROKER SERVER TIME";
string TCalStorageKey(string field)
{
   return "TCM."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID()+"."+_Symbol+"."+field;
}
bool TCalValidMasks(int days,int hours)
{
   return days>0&&days<=127&&hours>0&&hours<=16777215;
}
bool TCalHasHours()
{
   for(int day=0;day<7;day++)if(g_tcalDayHours[day]!=0)return true;
   return false;
}
int TCalHourCount(int mask)
{
   int count=0;
   for(int hour=0;hour<24;hour++)if((mask&(1<<hour))!=0)count++;
   return count;
}
double TCalPack(bool enabled,int days,int hours)
{
   return (double)days+128.0*(double)hours+(enabled?2147483648.0:0.0);
}
bool TCalSave()
{
   if(!TCalHasHours())return false;
   string header=TCalStorageKey("cfg2");
   int active=-1;
   if(GlobalVariableCheck(header))
   {
      double value=GlobalVariableGet(header);
      if(!MathIsValidNumber(value)||value<0||value>3||MathFloor(value)!=value)return false;
      active=(int)value%2;
   }
   int slot=active==0?1:0;
   for(int day=0;day<7;day++)
   {
      if(g_tcalDayHours[day]<0||g_tcalDayHours[day]>16777215)return false;
      if(GlobalVariableSet(TCalStorageKey("h"+(string)slot+"."+(string)day),(double)g_tcalDayHours[day])==0)return false;
   }
   if(GlobalVariableSet(TCalStorageKey("dir"+(string)slot),(double)g_entryDirection)==0)return false;
   if(GlobalVariableSet(TCalStorageKey("loss"+(string)slot),g_dailyMaxLosses)==0)return false;
   if(GlobalVariableSet(TCalStorageKey("win"+(string)slot),g_dailyTargetWins)==0)return false;
   if(GlobalVariableSet(TCalStorageKey("start"+(string)slot),g_dailyStartMinute)==0)return false;
   GlobalVariablesFlush();
   // Publish the new slot only after all seven masks have been written.
   if(GlobalVariableSet(header,(double)(slot+(g_tcalEnabled?2:0)))==0)return false;
   GlobalVariablesFlush();
   return true;
}
string TCalStrategyOffText(){return "TCAL1=0,16777215,16777215,16777215,16777215,16777215,16777215,16777215";}
string TCalStrategyText()
{
   string text="TCAL1="+(g_tcalEnabled?"1":"0");
   for(int day=0;day<7;day++)text+=","+(string)g_tcalDayHours[day];
   return text+","+(string)g_entryDirection+","+(string)g_dailyMaxLosses+","+(string)g_dailyTargetWins+","+(string)g_dailyStartMinute;
}
bool TCalStrategyRead(string text,bool &enabled,int &hours[])
{
   if(StringFind(text,"TCAL1=")!=0)return false;
   string parts[];
   int fields=StringSplit(StringSubstr(text,6),',',parts);
   int maxLoss=0,targetWin=0,startMinute=0;
   if((fields!=8&&fields!=9&&fields!=11&&fields!=12)||DirectionStrategyMode(text)<0||!DailyQuotaReadStrategy(text,maxLoss,targetWin,startMinute))return false;
   if(parts[0]!="0"&&parts[0]!="1")return false;
   enabled=parts[0]=="1";int selected=0;
   ArrayResize(hours,7);
   for(int day=0;day<7;day++)
   {
      int mask=(int)StringToInteger(parts[day+1]);
      if(mask<0||mask>16777215||parts[day+1]!=(string)mask)return false;
      hours[day]=mask;selected|=mask;
   }
   return selected!=0;
}
bool TCalStrategyMatchesText(string text)
{
   bool enabled=false;int hours[];
   if(!TCalStrategyRead(text,enabled,hours)||g_tcalEnabled!=enabled||g_entryDirection!=DirectionStrategyMode(text))return false;
   int maxLoss=0,targetWin=0,startMinute=0;
   if(!DailyQuotaReadStrategy(text,maxLoss,targetWin,startMinute)||g_dailyMaxLosses!=maxLoss||g_dailyTargetWins!=targetWin||g_dailyStartMinute!=startMinute)return false;
   for(int day=0;day<7;day++)if(g_tcalDayHours[day]!=hours[day])return false;
   return true;
}
bool TCalStrategyApplyText(string text)
{
   bool enabled=false;int hours[];
   if(!TCalStrategyRead(text,enabled,hours))return false;
   if(TCalStrategyMatchesText(text)){DailyQuotaDraftReset();return true;}
   int oldLoss=g_dailyMaxLosses,oldWin=g_dailyTargetWins,oldStart=g_dailyStartMinute;
   DailyQuotaReadStrategy(text,g_dailyMaxLosses,g_dailyTargetWins,g_dailyStartMinute);
   int oldDirection=g_entryDirection;g_entryDirection=DirectionStrategyMode(text);
   bool oldEnabled=g_tcalEnabled;int oldHours[7];
   for(int day=0;day<7;day++){oldHours[day]=g_tcalDayHours[day];g_tcalDayHours[day]=hours[day];}
   g_tcalEnabled=enabled;
   if(!TCalSave())
   {
      g_tcalEnabled=oldEnabled;g_entryDirection=oldDirection;g_dailyMaxLosses=oldLoss;g_dailyTargetWins=oldWin;g_dailyStartMinute=oldStart;
      for(int day=0;day<7;day++)g_tcalDayHours[day]=oldHours[day];
      return false;
   }
   for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=hours[day];
   g_tcalRankPending=false;g_tcalDraftEdited=false;g_tcalRankPickCount=0;
   DailyQuotaDraftReset();g_tcalChanged=true;g_tcalUiDirty=true;
   return true;
}
bool TCalInit()
{
   if(!DailyQuotaParseClock(InpDailyStart,g_dailyStartMinute))return false;
   g_dailyMaxLosses=InpDailyMaxLosses;g_dailyTargetWins=InpDailyTargetWins;
   if(g_dailyMaxLosses<0||g_dailyTargetWins<0||g_dailyMaxLosses>100000||g_dailyTargetWins>100000)return false;
   g_entryDirection=(int)InpEntryDirection;
   if(g_entryDirection<0||g_entryDirection>2)return false;
   if(!TCalValidMasks(InpTimeMatrixDays,InpTimeMatrixHours))return false;
   for(int day=0;day<7;day++)
      g_tcalDayHours[day]=(InpTimeMatrixDays&(1<<day))!=0?InpTimeMatrixHours:0;
   g_tcalEnabled=InpTimeMatrixEnabled;
   string key=TCalStorageKey("cfg"),header=TCalStorageKey("cfg2"),base=TCalStorageKey("base");
   double inputPacked=TCalPack(InpTimeMatrixEnabled,InpTimeMatrixDays,InpTimeMatrixHours)+4294967296.0*g_entryDirection;
   double dailyBase=g_dailyMaxLosses+100001.0*g_dailyTargetWins+10000200001.0*g_dailyStartMinute;
   string dailyBaseKey=TCalStorageKey("dailyBase");
   bool sameInputs=GlobalVariableCheck(base)&&GlobalVariableGet(base)==inputPacked
      &&(GlobalVariableCheck(dailyBaseKey)?GlobalVariableGet(dailyBaseKey)==dailyBase:dailyBase==0);
   bool loaded=false;
   if(sameInputs&&GlobalVariableCheck(header))
   {
      double value=GlobalVariableGet(header);
      if(!MathIsValidNumber(value)||value<0||value>3||MathFloor(value)!=value)return false;
      int slot=(int)value%2;
      double lossValue=GlobalVariableCheck(TCalStorageKey("loss"+(string)slot))?GlobalVariableGet(TCalStorageKey("loss"+(string)slot)):0;
      double winValue=GlobalVariableCheck(TCalStorageKey("win"+(string)slot))?GlobalVariableGet(TCalStorageKey("win"+(string)slot)):0;
      if(!DailyQuotaValidNumber(lossValue)||!DailyQuotaValidNumber(winValue))return false;
      double startValue=GlobalVariableCheck(TCalStorageKey("start"+(string)slot))?GlobalVariableGet(TCalStorageKey("start"+(string)slot)):0;
      if(!DailyQuotaValidNumber(startValue)||startValue>=1440)return false;
      g_dailyStartMinute=(int)startValue;
      g_dailyMaxLosses=(int)lossValue;g_dailyTargetWins=(int)winValue;
      string dirKey=TCalStorageKey("dir"+(string)slot);
      if(GlobalVariableCheck(dirKey))
      {
         double direction=GlobalVariableGet(dirKey);
         if(!MathIsValidNumber(direction)||direction<0||direction>2||direction!=MathFloor(direction))return false;
         g_entryDirection=(int)direction;
      }
      for(int day=0;day<7;day++)
      {
         string hourKey=TCalStorageKey("h"+(string)slot+"."+(string)day);
         if(!GlobalVariableCheck(hourKey))return false;
         double hours=GlobalVariableGet(hourKey);
         if(!MathIsValidNumber(hours)||hours<0||hours>16777215||MathFloor(hours)!=hours)return false;
         g_tcalDayHours[day]=(int)hours;
      }
      if(!TCalHasHours())return false;
      g_tcalEnabled=value>=2;
      loaded=true;
   }
   else if(sameInputs&&GlobalVariableCheck(key))
   {
      double packed=GlobalVariableGet(key);
      if(!MathIsValidNumber(packed)||packed<0.0||packed>4294967295.0||MathFloor(packed)!=packed)return false;
      bool savedEnabled=packed>=2147483648.0;
      if(savedEnabled)packed-=2147483648.0;
      int savedHours=(int)MathFloor(packed/128.0),savedDays=(int)(packed-128.0*savedHours);
      if(!TCalValidMasks(savedDays,savedHours))return false;
      for(int day=0;day<7;day++)g_tcalDayHours[day]=(savedDays&(1<<day))!=0?savedHours:0;
      g_tcalEnabled=savedEnabled;
      loaded=true;
   }
   if(!loaded)
   {
      // Explicitly changed Inputs outrank an older chart-scoped dashboard choice.
      if(!TCalSave()&&(InpTimeMatrixEnabled||DailyQuotaEnabled()))return false;
      if(GlobalVariableSet(base,inputPacked)==0&&(InpTimeMatrixEnabled||DailyQuotaEnabled()))return false;
      if(GlobalVariableSet(dailyBaseKey,dailyBase)==0&&DailyQuotaEnabled())return false;
   }
   else if(!GlobalVariableCheck(header)&&!TCalSave()&&g_tcalEnabled)return false;
   for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=g_tcalDayHours[day];
   DailyQuotaDraftReset();TCalReset();return true;
}

string TCalDayName(int day)
{
   string names[7]={"SUN","MON","TUE","WED","THU","FRI","SAT"};
   return day>=0&&day<7?names[day]:"?";
}
string TCalHourName(int hour)
{
   return StringFormat("%02d-%02d",hour,(hour+1)%24);
}
string TCalId(string suffix){return g_tcalPrefix+suffix;}
void TCalReset()
{
   g_tcalUiDirty=true;
   DailyQuotaAuditReset();g_directionBuyLosses=0;g_directionSellLosses=0;g_directionMinCum=0.0;
   for(int day=0;day<7;day++)for(int hour=0;hour<24;hour++)
   {g_tcalWins[day][hour]=0;g_tcalLosses[day][hour]=0;}
}
void TCalRecord(datetime openedAt,double netR)
{
   if(openedAt<=0||MathAbs(netR)<=1e-8)return;
   MqlDateTime stamp;TimeToStruct(openedAt,stamp);
   if(stamp.day_of_week<0||stamp.day_of_week>6||stamp.hour<0||stamp.hour>23)return;
   if(netR>0)g_tcalWins[stamp.day_of_week][stamp.hour]++;
   else g_tcalLosses[stamp.day_of_week][stamp.hour]++;
   g_tcalUiDirty=true;
}
void TCalRecordOutcome(datetime openedAt,bool won)
{
   if(openedAt<=0)return;
   MqlDateTime stamp;TimeToStruct(openedAt,stamp);
   if(stamp.day_of_week<0||stamp.day_of_week>6||stamp.hour<0||stamp.hour>23)return;
   if(won)g_tcalWins[stamp.day_of_week][stamp.hour]++;
   else g_tcalLosses[stamp.day_of_week][stamp.hour]++;
   g_tcalUiDirty=true;
}
bool TCalAllows(datetime openedAt)
{
   if(!g_tcalEnabled)return true;
   if(openedAt<=0)return false;
   MqlDateTime stamp;TimeToStruct(openedAt,stamp);
   if(stamp.day_of_week<0||stamp.day_of_week>6||stamp.hour<0||stamp.hour>23)return false;
   return (g_tcalDayHours[stamp.day_of_week]&(1<<stamp.hour))!=0;
}
double TCalWr(int wins,int losses)
{
   int n=wins+losses;return n>0?100.0*(double)wins/(double)n:0.0;
}
string TCalStats(int wins,int losses)
{
   int n=wins+losses;
   return n>0?StringFormat("%dW  %dL  %.1f%%  n=%d",wins,losses,TCalWr(wins,losses),n):"no closed trades";
}
void TCalObj(string suffix,ENUM_OBJECT kind,int x,int y,int w,int h,string label,color bg,color fg,int size=9)
{
   string name=TCalId(suffix);
   if(ObjectFind(0,name)<0)ObjectCreate(0,name,kind,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   if(kind!=OBJ_LABEL)
   {
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'73,82,93');
   }
   ObjectSetInteger(0,name,OBJPROP_COLOR,fg);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetString(0,name,OBJPROP_TEXT,label);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   long z=suffix=="MOD_BG"?2000000:(suffix=="OPEN"?2000001:2000002);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,z);
}
void TCalClearModal()
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,TCalId("MOD_"))==0)ObjectDelete(0,name);
   }
}
void TCalDestroy()
{
   if(g_tcalPrefix=="")return;
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,g_tcalPrefix)==0)ObjectDelete(0,name);
   }
   g_tcalOpen=false;
}
void TCalOpen(int x,int y)
{
   g_tcalX=x;g_tcalY=y;g_tcalOpen=true;
   for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=g_tcalDayHours[day];
   g_tcalRankPending=false;g_tcalDraftEdited=false;g_tcalRankPickCount=0;
   g_tcalView=0;g_tcalPage=0;g_tcalUiDirty=true;
}
bool TCalApplyDraft()
{
   int oldHours[7];bool oldEnabled=g_tcalEnabled;
   for(int day=0;day<7;day++)
   {
      oldHours[day]=g_tcalDayHours[day];
      g_tcalDayHours[day]=g_tcalDraftDayHours[day];
   }
   g_tcalEnabled=true;
   if(TCalSave())
   {
      g_tcalChanged=true;g_tcalRankPending=false;g_tcalDraftEdited=false;g_tcalRankPickCount=0;
      return true;
   }
   for(int day=0;day<7;day++)g_tcalDayHours[day]=oldHours[day];
   g_tcalEnabled=oldEnabled;
   return false;
}
int TCalRankCount(){return g_tcalRankMode==0?7:(g_tcalRankMode==1?24:168);}
int TCalRankWins(int mode,int key)
{
   if(mode==2)return g_tcalWins[key/24][key%24];
   int wins=0;
   if(mode==0)for(int hour=0;hour<24;hour++)wins+=g_tcalWins[key][hour];
   else for(int day=0;day<7;day++)wins+=g_tcalWins[day][key];
   return wins;
}
int TCalRankLosses(int mode,int key)
{
   if(mode==2)return g_tcalLosses[key/24][key%24];
   int losses=0;
   if(mode==0)for(int hour=0;hour<24;hour++)losses+=g_tcalLosses[key][hour];
   else for(int day=0;day<7;day++)losses+=g_tcalLosses[day][key];
   return losses;
}
string TCalRankLabel(int mode,int key)
{
   if(mode==0)return TCalDayName(key);
   if(mode==1)return TCalHourName(key);
   return TCalDayName(key/24)+" "+TCalHourName(key%24);
}
bool TCalRankBucketSelected(int mode,int key)
{
   if(mode==0)return key>=0&&key<7&&g_tcalDraftDayHours[key]==16777215;
   if(mode==1)
   {
      if(key<0||key>=24)return false;
      for(int day=0;day<7;day++)if((g_tcalDraftDayHours[day]&(1<<key))==0)return false;
      return true;
   }
   return mode==2&&key>=0&&key<168&&(g_tcalDraftDayHours[key/24]&(1<<(key%24)))!=0;
}
bool TCalStageRankedBucket(int mode,int key)
{
   if((mode==0&&(key<0||key>=7))||(mode==1&&(key<0||key>=24))||
      (mode==2&&(key<0||key>=168))||mode<0||mode>2)return false;
   if(!g_tcalRankPending)
   {
      if(!g_tcalDraftEdited)
         for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=g_tcalEnabled?g_tcalDayHours[day]:0;
      g_tcalRankPending=true;
   }
   bool alreadySelected=TCalRankBucketSelected(mode,key);
   if(mode==0)g_tcalDraftDayHours[key]=16777215;
   else if(mode==1)for(int day=0;day<7;day++)g_tcalDraftDayHours[day]|=1<<key;
   else g_tcalDraftDayHours[key/24]|=1<<(key%24);
   if(!alreadySelected)g_tcalRankPickCount++;
   g_tcalDraftEdited=true;
   return true;
}
void TCalBuildRankedKeys(int mode,int &ranked[])
{
   int count=mode==0?7:(mode==1?24:168);
   int winsByKey[168],lossesByKey[168];
   for(int i=0;i<count;i++)
   {
      ranked[i]=i;
      winsByKey[i]=TCalRankWins(mode,i);
      lossesByKey[i]=TCalRankLosses(mode,i);
   }
   for(int i=0;i<count;i++)
   {
      int best=i;
      for(int j=i+1;j<count;j++)
      {
         int a=ranked[j],b=ranked[best];
         int an=winsByKey[a]+lossesByKey[a],bn=winsByKey[b]+lossesByKey[b];
         double aw=an>=g_tcalMinSample?TCalWr(winsByKey[a],lossesByKey[a]):-1.0;
         double bw=bn>=g_tcalMinSample?TCalWr(winsByKey[b],lossesByKey[b]):-1.0;
         if(aw>bw+1e-8||(MathAbs(aw-bw)<=1e-8&&an>bn))best=j;
      }
      if(best!=i){int swap=ranked[i];ranked[i]=ranked[best];ranked[best]=swap;}
   }
}
int TCalStageRankedPage()
{
   int ranked[168];TCalBuildRankedKeys(g_tcalRankMode,ranked);
   int added=0,count=TCalRankCount();
   for(int row=0;row<8;row++)
   {
      int rank=g_tcalPage*8+row;if(rank>=count)break;
      int key=ranked[rank];
      if(TCalRankWins(g_tcalRankMode,key)+TCalRankLosses(g_tcalRankMode,key)<g_tcalMinSample)break;
      bool selected=TCalRankBucketSelected(g_tcalRankMode,key);
      if(TCalStageRankedBucket(g_tcalRankMode,key)&&!selected)added++;
   }
   return added;
}
void TCalLauncher(string scope,int x,int y,int modalX,int modalY,string clockLabel)
{
   if(g_tcalPrefix=="")g_tcalPrefix=scope+"TCAL_";
   g_tcalClockLabel=clockLabel;
   g_tcalX=modalX;g_tcalY=modalY;
   TCalObj("OPEN",OBJ_BUTTON,x,y,116,20,"TIME MATRIX",C'43,93,105',clrWhite,8);
   if(g_tcalOpen&&g_tcalUiDirty)TCalDraw();
}
void DirectionLauncher(string scope,int x,int y)
{
   if(g_tcalPrefix=="")g_tcalPrefix=scope+"TCAL_";
   TCalObj("DIRECTION",OBJ_BUTTON,x,y,116,20,"ENTRY: "+EntryDirectionLabel(),C'43,93,105',clrWhite,8);
}
void TCalDraw()
{
   if(!g_tcalOpen)return;
   g_tcalUiDirty=false;
   TCalClearModal();
   int x=g_tcalX,y=g_tcalY;
   TCalObj("MOD_BG",OBJ_RECTANGLE_LABEL,x,y,636,478,"",C'20,26,33',clrWhite);
   TCalObj("MOD_TITLE",OBJ_LABEL,x+16,y+12,0,0,"ENTRY TIME MATRIX  |  "+g_tcalClockLabel,C'20,26,33',C'239,243,245',11);
   TCalObj("MOD_CLOSE",OBJ_BUTTON,x+590,y+8,30,23,"X",C'70,75,82',clrWhite);
   TCalObj("MOD_NOTE",OBJ_LABEL,x+16,y+39,0,0,
      g_tcalView==3?"Pick multiple rows first; APPLY PICKS changes the active filter and audit together.":
      "Selected audit window; closed trades only. Adjust leaderboard sample floor below.",
      C'20,26,33',C'158,172,180',8);
   string tabs[5]={"DAYS WR","HOURS WR","DAY x HOUR","LEADERBOARD","SELECT TIME"};
   for(int i=0;i<5;i++)
      TCalObj("MOD_TAB_"+(string)i,OBJ_BUTTON,x+16+i*121,y+62,115,24,tabs[i],
         i==g_tcalView?C'41,118,107':C'43,50,59',clrWhite,8);
   if(g_tcalView==0)
   {
      for(int day=0;day<7;day++)
      {
         int wins=0,losses=0;
         for(int hour=0;hour<24;hour++){wins+=g_tcalWins[day][hour];losses+=g_tcalLosses[day][hour];}
         TCalObj("MOD_ROW_"+(string)day,OBJ_LABEL,x+30,y+101+day*38,0,0,
            TCalDayName(day)+"     "+TCalStats(wins,losses),C'20,26,33',C'225,231,234',9);
      }
   }
   else if(g_tcalView==1||g_tcalView==2)
   {
      if(g_tcalView==2)
      {
         TCalObj("MOD_DAY_PREV",OBJ_BUTTON,x+20,y+98,28,22,"<",C'43,50,59',clrWhite);
         TCalObj("MOD_DAY_LABEL",OBJ_LABEL,x+58,y+103,0,0,TCalDayName(g_tcalDay),C'20,26,33',clrWhite);
         TCalObj("MOD_DAY_NEXT",OBJ_BUTTON,x+120,y+98,28,22,">",C'43,50,59',clrWhite);
      }
      for(int row=0;row<8;row++)
      {
         int hour=g_tcalPage*8+row;if(hour>=24)break;
         int wins=0,losses=0;
         if(g_tcalView==2){wins=g_tcalWins[g_tcalDay][hour];losses=g_tcalLosses[g_tcalDay][hour];}
         else for(int day=0;day<7;day++){wins+=g_tcalWins[day][hour];losses+=g_tcalLosses[day][hour];}
         TCalObj("MOD_ROW_"+(string)row,OBJ_LABEL,x+30,y+132+row*34,0,0,
            TCalHourName(hour)+"     "+TCalStats(wins,losses),C'20,26,33',C'225,231,234',9);
      }
   }
   else if(g_tcalView==3)
   {
      string modes[3]={"DAYS","HOURS","DAY x HOUR"};
      int modeX[3]={24,155,286},modeW[3]={126,126,143};
      for(int mode=0;mode<3;mode++)
         TCalObj("MOD_RANK_MODE_"+(string)mode,OBJ_BUTTON,x+modeX[mode],y+98,modeW[mode],24,modes[mode],
            mode==g_tcalRankMode?C'41,118,107':C'43,50,59',clrWhite,8);
      TCalObj("MOD_MIN_N",OBJ_BUTTON,x+478,y+98,130,24,"MIN N: "+(string)g_tcalMinSample,C'43,50,59',clrWhite,8);
      // Rank by WR, then sample count. Small samples remain visible in raw views.
      int count=TCalRankCount(),ranked[168];
      TCalBuildRankedKeys(g_tcalRankMode,ranked);
      for(int row=0;row<8;row++)
      {
         int rank=g_tcalPage*8+row;if(rank>=count)break;
         int key=ranked[rank],wins=TCalRankWins(g_tcalRankMode,key),losses=TCalRankLosses(g_tcalRankMode,key);
         if(wins+losses<g_tcalMinSample)
         {
            if(row==0)TCalObj("MOD_ROW_0",OBJ_LABEL,x+30,y+137,0,0,"No row reaches min N = "+(string)g_tcalMinSample,C'20,26,33',C'225,231,234');
            break;
         }
         TCalObj("MOD_ROW_"+(string)row,OBJ_LABEL,x+30,y+132+row*34,0,0,
            (string)(rank+1)+".  "+TCalRankLabel(g_tcalRankMode,key)+"     "+TCalStats(wins,losses),
            C'20,26,33',C'225,231,234',9);
         bool picked=g_tcalRankPending&&TCalRankBucketSelected(g_tcalRankMode,key);
         TCalObj("MOD_RANK_ADD_"+(string)key,OBJ_BUTTON,x+508,y+128+row*34,100,24,
            picked?"PICKED":"+ PICK",picked?C'41,118,107':C'43,93,105',clrWhite,8);
      }
      TCalObj("MOD_PICK_STATUS",OBJ_LABEL,x+30,y+405,0,0,
         g_tcalRankPending?"STAGED: "+(string)g_tcalRankPickCount+" new rows | audit unchanged until APPLY":
         "Pick rows across pages or categories, then apply together.",
         C'20,26,33',C'188,200,207',8);
      TCalObj("MOD_RANK_PAGE",OBJ_BUTTON,x+24,y+427,160,28,"PICK PAGE",
         C'43,93,105',clrWhite,8);
      TCalObj("MOD_RANK_APPLY",OBJ_BUTTON,x+452,y+427,156,28,"APPLY PICKS",
         g_tcalRankPickCount>0?C'41,118,107':C'61,65,70',clrWhite,9);
   }
   else
   {
      TCalObj("MOD_STATUS",OBJ_LABEL,x+24,y+101,0,0,
         g_tcalEnabled?"FILTER ON - applied to new entries and audit":"FILTER OFF - existing behavior unchanged",
         C'20,26,33',g_tcalEnabled?C'88,224,177':C'188,200,207',9);
      if(g_tcalPage==0)
      {
         TCalObj("MOD_PICK_TITLE",OBJ_LABEL,x+24,y+134,0,0,"CHOOSE A DAY, THEN SET ITS HOURS",C'20,26,33',clrWhite,9);
         for(int day=0;day<7;day++)
            TCalObj("MOD_PICK_DAY_"+(string)day,OBJ_BUTTON,x+24+(day%4)*147,y+165+(day/4)*34,139,27,
               TCalDayName(day)+"  "+(string)TCalHourCount(g_tcalDraftDayHours[day])+"h",
               g_tcalDraftDayHours[day]!=0?C'41,118,107':C'61,65,70',clrWhite,8);
      }
      else
      {
         TCalObj("MOD_DAYS",OBJ_BUTTON,x+24,y+128,142,24,"< BACK TO DAYS",C'43,93,105',clrWhite,8);
         TCalObj("MOD_PICK_TITLE",OBJ_LABEL,x+180,y+134,0,0,
            TCalDayName(g_tcalDay)+"  "+(string)TCalHourCount(g_tcalDraftDayHours[g_tcalDay])+" HOURS SELECTED",
            C'20,26,33',clrWhite,9);
         int base=(g_tcalPage-1)*8;
         for(int row=0;row<8;row++)
         {
            int hour=base+row;if(hour>=24)break;
            TCalObj("MOD_PICK_HOUR_"+(string)hour,OBJ_BUTTON,x+24+(row%4)*147,y+165+(row/4)*34,139,27,
               TCalHourName(hour),(g_tcalDraftDayHours[g_tcalDay]&(1<<hour))!=0?C'41,118,107':C'61,65,70',clrWhite,8);
         }
      }
      TCalObj("MOD_ALL",OBJ_BUTTON,x+24,y+256,112,24,g_tcalPage==0?"ALL DAYS":"ALL HOURS",C'43,50,59',clrWhite,8);
      TCalObj("MOD_CLEAR",OBJ_BUTTON,x+144,y+256,112,24,g_tcalPage==0?"CLEAR ALL":"CLEAR DAY",C'80,68,65',clrWhite,8);
      TCalObj("MOD_APPLY",OBJ_BUTTON,x+24,y+304,160,28,"APPLY FILTER",C'41,118,107',clrWhite,9);
      TCalObj("MOD_DISABLE",OBJ_BUTTON,x+196,y+304,160,28,"FILTER OFF",C'80,68,65',clrWhite,9);
      TCalObj("MOD_HINT",OBJ_LABEL,x+24,y+353,0,0,"Each day has its own hours. APPLY requires at least one selected hour.",C'20,26,33',C'158,172,180',8);
   }
   if(g_tcalView==1||g_tcalView==2||g_tcalView==3)
   {
      TCalObj("MOD_PREV",OBJ_BUTTON,x+222,y+430,45,24,"<",C'43,50,59',clrWhite);
      int pages=g_tcalView==3?(TCalRankCount()+7)/8:3;
      TCalObj("MOD_PAGE",OBJ_LABEL,x+280,y+436,0,0,"PAGE "+(string)(g_tcalPage+1)+"/"+(string)pages,C'20,26,33',clrWhite,8);
      TCalObj("MOD_NEXT",OBJ_BUTTON,x+348,y+430,45,24,">",C'43,50,59',clrWhite);
   }
   if(g_tcalView==4&&g_tcalPage>0)
   {
      TCalObj("MOD_PICK_PREV",OBJ_BUTTON,x+222,y+430,45,24,"<",C'43,50,59',clrWhite);
      TCalObj("MOD_PICK_PAGE",OBJ_LABEL,x+280,y+436,0,0,"HOURS "+(string)g_tcalPage+"/3",C'20,26,33',clrWhite,8);
      TCalObj("MOD_PICK_NEXT",OBJ_BUTTON,x+348,y+430,45,24,">",C'43,50,59',clrWhite);
   }
}
void DailyQuotaLauncher(string scope,int x,int y,double scale=1.0)
{
   g_dailyUiPrefix=scope+"TCAL_";
   g_tcalPrefix=scope+"TCAL_";
   TCalObj("DAILY_LOSS_LABEL",OBJ_LABEL,x,y+(int)MathRound(4*scale),0,0,"MAX LOSS",clrBlack,clrWhite,8);
   TCalObj("DAILY_LOSS",OBJ_EDIT,x+(int)MathRound(68*scale),y, (int)MathRound(55*scale),(int)MathRound(22*scale),(ObjectFind(0,TCalId("DAILY_LOSS"))>=0?ObjectGetString(0,TCalId("DAILY_LOSS"),OBJPROP_TEXT):g_dailyLossDraft),C'26,33,42',clrWhite);
   TCalObj("DAILY_WIN_LABEL",OBJ_LABEL,x+(int)MathRound(130*scale),y+(int)MathRound(4*scale),0,0,"WIN TARGET",clrBlack,clrWhite,8);
   TCalObj("DAILY_WIN",OBJ_EDIT,x+(int)MathRound(214*scale),y, (int)MathRound(55*scale),(int)MathRound(22*scale),(ObjectFind(0,TCalId("DAILY_WIN"))>=0?ObjectGetString(0,TCalId("DAILY_WIN"),OBJPROP_TEXT):g_dailyWinDraft),C'26,33,42',clrWhite);
   TCalObj("DAILY_START_LABEL",OBJ_LABEL,x+(int)MathRound(276*scale),y+(int)MathRound(4*scale),0,0,"START",clrBlack,clrWhite,8);
   TCalObj("DAILY_START",OBJ_EDIT,x+(int)MathRound(322*scale),y,(int)MathRound(58*scale),(int)MathRound(22*scale),(ObjectFind(0,TCalId("DAILY_START"))>=0?ObjectGetString(0,TCalId("DAILY_START"),OBJPROP_TEXT):g_dailyStartDraft),C'26,33,42',clrWhite);
   TCalObj("DAILY_APPLY",OBJ_BUTTON,x+(int)MathRound(386*scale),y, (int)MathRound(90*scale),(int)MathRound(22*scale),"APPLY DAY",C'40,72,91',clrWhite);
   TCalObj("DAILY_HINT",OBJ_LABEL,x+(int)MathRound(484*scale),y+(int)MathRound(4*scale),0,0,"0=OFF",clrBlack,clrSilver,8);
}
bool TCalEvent(int id,long lx,double dy,string clicked)
{
   if(g_tcalOpen&&id==CHARTEVENT_OBJECT_ENDEDIT)return true;
   if(!g_tcalOpen&&id==CHARTEVENT_OBJECT_ENDEDIT&&(clicked==TCalId("DAILY_LOSS")||clicked==TCalId("DAILY_WIN")||clicked==TCalId("DAILY_START")))
   {if(clicked==TCalId("DAILY_LOSS"))g_dailyLossDraft=ObjectGetString(0,clicked,OBJPROP_TEXT);
    else if(clicked==TCalId("DAILY_WIN"))g_dailyWinDraft=ObjectGetString(0,clicked,OBJPROP_TEXT);
    else g_dailyStartDraft=ObjectGetString(0,clicked,OBJPROP_TEXT);return true;}
   if(!g_tcalOpen&&id==CHARTEVENT_OBJECT_CLICK&&clicked==TCalId("DAILY_APPLY"))
   {
      g_dailyLossDraft=ObjectGetString(0,TCalId("DAILY_LOSS"),OBJPROP_TEXT);
      g_dailyWinDraft=ObjectGetString(0,TCalId("DAILY_WIN"),OBJPROP_TEXT);
      g_dailyStartDraft=ObjectGetString(0,TCalId("DAILY_START"),OBJPROP_TEXT);
      int loss=0,win=0,startMinute=0;
      if(!DailyQuotaParse(g_dailyLossDraft,loss)||!DailyQuotaParse(g_dailyWinDraft,win)||!DailyQuotaParseClock(g_dailyStartDraft,startMinute))
      {Print("Daily limits require whole numbers 0..100000 and START HH:MM 00:00..23:59");ObjectSetInteger(0,clicked,OBJPROP_STATE,false);return true;}
      int oldLoss=g_dailyMaxLosses,oldWin=g_dailyTargetWins,oldStart=g_dailyStartMinute;g_dailyMaxLosses=loss;g_dailyTargetWins=win;g_dailyStartMinute=startMinute;
      if(TCalSave()){g_tcalChanged=true;DailyQuotaDraftReset();}
      else {g_dailyMaxLosses=oldLoss;g_dailyTargetWins=oldWin;g_dailyStartMinute=oldStart;Print("Daily limits not saved; unchanged");}
      ObjectSetInteger(0,clicked,OBJPROP_STATE,false);return true;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK)return false;
   if(clicked==TCalId("OPEN"))
   {
      if(g_tcalOpen){g_tcalOpen=false;TCalClearModal();}
      else TCalOpen(g_tcalX,g_tcalY);
      ObjectSetInteger(0,clicked,OBJPROP_STATE,false);TCalDraw();ChartRedraw(0);return true;
   }
   if(!g_tcalOpen&&clicked==TCalId("DIRECTION"))
   {
      int old=g_entryDirection;g_entryDirection=(old+1)%3;
      if(TCalSave())g_tcalChanged=true;
      else {g_entryDirection=old;Print("Entry direction could not persist; unchanged");}
      ObjectSetInteger(0,clicked,OBJPROP_STATE,false);
      ObjectSetString(0,clicked,OBJPROP_TEXT,"ENTRY: "+EntryDirectionLabel());
      return true;
   }
   if(!g_tcalOpen)return false;
   // A modal consumes underlying dashboard object clicks, including click-through.
   if(StringFind(clicked,TCalId("MOD_"))!=0)
   {
      if(ObjectFind(0,clicked)>=0&&ObjectGetInteger(0,clicked,OBJPROP_TYPE)==OBJ_BUTTON)
         ObjectSetInteger(0,clicked,OBJPROP_STATE,false);
      return true;
   }
   ObjectSetInteger(0,clicked,OBJPROP_STATE,false);
   if(clicked==TCalId("MOD_CLOSE")){g_tcalOpen=false;TCalClearModal();ChartRedraw(0);return true;}
   g_tcalUiDirty=true;
   for(int i=0;i<5;i++)if(clicked==TCalId("MOD_TAB_"+(string)i)){g_tcalView=i;g_tcalPage=0;TCalDraw();ChartRedraw(0);return true;}
   for(int mode=0;mode<3;mode++)if(clicked==TCalId("MOD_RANK_MODE_"+(string)mode))
   {g_tcalRankMode=mode;g_tcalPage=0;TCalDraw();ChartRedraw(0);return true;}
   string rankTag=TCalId("MOD_RANK_ADD_");
   if(StringFind(clicked,rankTag)==0)
   {
      int key=(int)StringToInteger(StringSubstr(clicked,StringLen(rankTag)));
      if(!TCalStageRankedBucket(g_tcalRankMode,key))Print("Invalid time matrix leaderboard row");
      TCalDraw();ChartRedraw(0);return true;
   }
   if(clicked==TCalId("MOD_RANK_APPLY"))
   {
      if(g_tcalRankPending&&g_tcalRankPickCount>0&&!TCalApplyDraft())
         Print("Time matrix leaderboard picks could not persist; active filter unchanged");
      TCalDraw();ChartRedraw(0);return true;
   }
   if(clicked==TCalId("MOD_RANK_PAGE"))
   {
      TCalStageRankedPage();TCalDraw();ChartRedraw(0);return true;
   }
   if(clicked==TCalId("MOD_DAYS"))g_tcalPage=0;
   else if(clicked==TCalId("MOD_DAY_PREV"))g_tcalDay=(g_tcalDay+6)%7;
   else if(clicked==TCalId("MOD_DAY_NEXT"))g_tcalDay=(g_tcalDay+1)%7;
   else if(clicked==TCalId("MOD_PREV"))g_tcalPage=MathMax(0,g_tcalPage-1);
   else if(clicked==TCalId("MOD_NEXT"))g_tcalPage=MathMin(g_tcalView==3?(TCalRankCount()-1)/8:2,g_tcalPage+1);
   else if(clicked==TCalId("MOD_PICK_PREV"))g_tcalPage=MathMax(1,g_tcalPage-1);
   else if(clicked==TCalId("MOD_PICK_NEXT"))g_tcalPage=MathMin(3,g_tcalPage+1);
   else if(clicked==TCalId("MOD_MIN_N"))
   {
      g_tcalMinSample=g_tcalMinSample==1?3:(g_tcalMinSample==3?5:(g_tcalMinSample==5?10:(g_tcalMinSample==10?20:1)));
      g_tcalPage=0;
   }
   else if(clicked==TCalId("MOD_ALL"))
   {
      g_tcalRankPending=false;g_tcalRankPickCount=0;g_tcalDraftEdited=true;
      if(g_tcalPage==0)for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=16777215;
      else g_tcalDraftDayHours[g_tcalDay]=16777215;
   }
   else if(clicked==TCalId("MOD_CLEAR"))
   {
      g_tcalRankPending=false;g_tcalRankPickCount=0;g_tcalDraftEdited=true;
      if(g_tcalPage==0)for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=0;
      else g_tcalDraftDayHours[g_tcalDay]=0;
   }
   else if(clicked==TCalId("MOD_APPLY"))
   {
      if(!TCalApplyDraft())Print("Time matrix needs at least one hour and a successful save; settings unchanged");
   }
   else if(clicked==TCalId("MOD_DISABLE"))
   {
      bool oldEnabled=g_tcalEnabled;g_tcalEnabled=false;
      if(TCalSave())
      {
         g_tcalChanged=true;g_tcalRankPending=false;g_tcalRankPickCount=0;g_tcalDraftEdited=false;
         for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=g_tcalDayHours[day];
      }
      else {g_tcalEnabled=oldEnabled;Print("Time matrix could not persist; settings unchanged");}
   }
   else
   {
      string dayTag=TCalId("MOD_PICK_DAY_"),hourTag=TCalId("MOD_PICK_HOUR_");
      if(StringFind(clicked,dayTag)==0)
      {int day=(int)StringToInteger(StringSubstr(clicked,StringLen(dayTag)));if(day>=0&&day<7){g_tcalDay=day;g_tcalPage=1;}}
      if(StringFind(clicked,hourTag)==0)
      {
         int hour=(int)StringToInteger(StringSubstr(clicked,StringLen(hourTag)));
         if(hour>=0&&hour<24)
         {
            g_tcalDraftDayHours[g_tcalDay]^=1<<hour;
            g_tcalRankPending=false;g_tcalRankPickCount=0;g_tcalDraftEdited=true;
         }
      }
   }
   TCalDraw();ChartRedraw(0);return true;
}
#endif
