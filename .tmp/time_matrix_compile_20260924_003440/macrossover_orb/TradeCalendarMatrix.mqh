#ifndef TRADE_CALENDAR_MATRIX_MQH
#define TRADE_CALENDAR_MATRIX_MQH

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
   GlobalVariablesFlush();
   // Publish the new slot only after all seven masks have been written.
   if(GlobalVariableSet(header,(double)(slot+(g_tcalEnabled?2:0)))==0)return false;
   GlobalVariablesFlush();
   return true;
}
bool TCalInit()
{
   if(!TCalValidMasks(InpTimeMatrixDays,InpTimeMatrixHours))return false;
   for(int day=0;day<7;day++)
      g_tcalDayHours[day]=(InpTimeMatrixDays&(1<<day))!=0?InpTimeMatrixHours:0;
   g_tcalEnabled=InpTimeMatrixEnabled;
   string key=TCalStorageKey("cfg"),header=TCalStorageKey("cfg2"),base=TCalStorageKey("base");
   double inputPacked=TCalPack(InpTimeMatrixEnabled,InpTimeMatrixDays,InpTimeMatrixHours);
   bool sameInputs=GlobalVariableCheck(base)&&GlobalVariableGet(base)==inputPacked;
   bool loaded=false;
   if(sameInputs&&GlobalVariableCheck(header))
   {
      double value=GlobalVariableGet(header);
      if(!MathIsValidNumber(value)||value<0||value>3||MathFloor(value)!=value)return false;
      int slot=(int)value%2;
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
      if(!TCalSave()&&InpTimeMatrixEnabled)return false;
      if(GlobalVariableSet(base,inputPacked)==0&&InpTimeMatrixEnabled)return false;
   }
   else if(!GlobalVariableCheck(header)&&!TCalSave()&&g_tcalEnabled)return false;
   for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=g_tcalDayHours[day];
   TCalReset();return true;
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
   if(TCalSave()){g_tcalChanged=true;return true;}
   for(int day=0;day<7;day++)g_tcalDayHours[day]=oldHours[day];
   g_tcalEnabled=oldEnabled;
   return false;
}
bool TCalAddRanked(int day,int hour)
{
   if(day<0||day>6||hour<0||hour>23)return false;
   for(int i=0;i<7;i++)g_tcalDraftDayHours[i]=g_tcalEnabled?g_tcalDayHours[i]:0;
   g_tcalDraftDayHours[day]|=1<<hour;
   if(TCalApplyDraft())return true;
   for(int i=0;i<7;i++)g_tcalDraftDayHours[i]=g_tcalDayHours[i];
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
bool TCalAddRankedBucket(int mode,int key)
{
   if(mode==2)return key>=0&&key<168&&TCalAddRanked(key/24,key%24);
   if((mode==0&&(key<0||key>6))||(mode==1&&(key<0||key>23)))return false;
   for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=g_tcalEnabled?g_tcalDayHours[day]:0;
   if(mode==0)g_tcalDraftDayHours[key]=16777215;
   else for(int day=0;day<7;day++)g_tcalDraftDayHours[day]|=1<<key;
   if(TCalApplyDraft())return true;
   for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=g_tcalDayHours[day];
   return false;
}
void TCalLauncher(string scope,int x,int y,int modalX,int modalY,string clockLabel)
{
   if(g_tcalPrefix=="")g_tcalPrefix=scope+"TCAL_";
   g_tcalClockLabel=clockLabel;
   g_tcalX=modalX;g_tcalY=modalY;
   TCalObj("OPEN",OBJ_BUTTON,x,y,116,20,"TIME MATRIX",C'43,93,105',clrWhite,8);
   if(g_tcalOpen&&g_tcalUiDirty)TCalDraw();
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
   TCalObj("MOD_NOTE",OBJ_LABEL,x+16,y+39,0,0,"Selected audit window; closed trades only. Adjust leaderboard sample floor below.",C'20,26,33',C'158,172,180',8);
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
      int count=TCalRankCount(),ranked[168],winsByKey[168],lossesByKey[168];
      for(int i=0;i<count;i++)
      {
         ranked[i]=i;
         winsByKey[i]=TCalRankWins(g_tcalRankMode,i);
         lossesByKey[i]=TCalRankLosses(g_tcalRankMode,i);
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
      for(int row=0;row<8;row++)
      {
         int rank=g_tcalPage*8+row;if(rank>=count)break;
         int key=ranked[rank],wins=winsByKey[key],losses=lossesByKey[key];
         if(wins+losses<g_tcalMinSample)
         {
            if(row==0)TCalObj("MOD_ROW_0",OBJ_LABEL,x+30,y+137,0,0,"No row reaches min N = "+(string)g_tcalMinSample,C'20,26,33',C'225,231,234');
            break;
         }
         TCalObj("MOD_ROW_"+(string)row,OBJ_LABEL,x+30,y+132+row*34,0,0,
            (string)(rank+1)+".  "+TCalRankLabel(g_tcalRankMode,key)+"     "+TCalStats(wins,losses),
            C'20,26,33',C'225,231,234',9);
         TCalObj("MOD_RANK_ADD_"+(string)key,OBJ_BUTTON,x+508,y+128+row*34,100,24,"ADD + ON",C'41,118,107',clrWhite,8);
      }
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
bool TCalEvent(int id,long lx,double dy,string clicked)
{
   if(g_tcalOpen&&id==CHARTEVENT_OBJECT_ENDEDIT)return true;
   if(id!=CHARTEVENT_OBJECT_CLICK)return false;
   if(clicked==TCalId("OPEN"))
   {
      if(g_tcalOpen){g_tcalOpen=false;TCalClearModal();}
      else TCalOpen(g_tcalX,g_tcalY);
      ObjectSetInteger(0,clicked,OBJPROP_STATE,false);TCalDraw();ChartRedraw(0);return true;
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
      if(!TCalAddRankedBucket(g_tcalRankMode,key))Print("Time matrix leaderboard selection could not persist");
      TCalDraw();ChartRedraw(0);return true;
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
      if(g_tcalPage==0)for(int day=0;day<7;day++)g_tcalDraftDayHours[day]=16777215;
      else g_tcalDraftDayHours[g_tcalDay]=16777215;
   }
   else if(clicked==TCalId("MOD_CLEAR"))
   {
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
      if(TCalSave())g_tcalChanged=true;
      else {g_tcalEnabled=oldEnabled;Print("Time matrix could not persist; settings unchanged");}
   }
   else
   {
      string dayTag=TCalId("MOD_PICK_DAY_"),hourTag=TCalId("MOD_PICK_HOUR_");
      if(StringFind(clicked,dayTag)==0)
      {int day=(int)StringToInteger(StringSubstr(clicked,StringLen(dayTag)));if(day>=0&&day<7){g_tcalDay=day;g_tcalPage=1;}}
      if(StringFind(clicked,hourTag)==0)
      {int hour=(int)StringToInteger(StringSubstr(clicked,StringLen(hourTag)));if(hour>=0&&hour<24)g_tcalDraftDayHours[g_tcalDay]^=1<<hour;}
   }
   TCalDraw();ChartRedraw(0);return true;
}
#endif
