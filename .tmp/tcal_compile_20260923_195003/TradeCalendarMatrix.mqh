#ifndef TRADE_CALENDAR_MATRIX_MQH
#define TRADE_CALENDAR_MATRIX_MQH

// Calendar statistics use completed audit trades only. All times are MT5 broker-server time.
int g_tcalWins[7][24],g_tcalLosses[7][24];
int g_tcalDays=127,g_tcalHours=16777215;
int g_tcalDraftDays=127,g_tcalDraftHours=16777215;
bool g_tcalEnabled=false,g_tcalOpen=false,g_tcalChanged=false;
int g_tcalView=0,g_tcalPage=0,g_tcalDay=1;
int g_tcalX=0,g_tcalY=0;
string g_tcalPrefix="";

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
}
bool TCalAllows(datetime openedAt)
{
   if(!g_tcalEnabled)return true;
   if(openedAt<=0)return false;
   MqlDateTime stamp;TimeToStruct(openedAt,stamp);
   if(stamp.day_of_week<0||stamp.day_of_week>6||stamp.hour<0||stamp.hour>23)return false;
   return (g_tcalDays&(1<<stamp.day_of_week))!=0&&(g_tcalHours&(1<<stamp.hour))!=0;
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
   ObjectSetInteger(0,name,OBJPROP_ZORDER,100000);
}
void TCalClearModal()
{
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,TCalId("MOD_"))==0)ObjectDelete(0,name);
   }
}
void TCalOpen(int x,int y)
{
   g_tcalX=x;g_tcalY=y;g_tcalOpen=true;g_tcalDraftDays=g_tcalDays;
   g_tcalDraftHours=g_tcalHours;g_tcalView=0;g_tcalPage=0;
}
void TCalLauncher(string scope,int x,int y,int modalX,int modalY)
{
   if(g_tcalPrefix=="")g_tcalPrefix=scope+"TCAL_";
   g_tcalX=modalX;g_tcalY=modalY;
   TCalObj("OPEN",OBJ_BUTTON,x,y,116,20,"TIME MATRIX",C'43,93,105',clrWhite,8);
   if(g_tcalOpen)TCalDraw();
}
void TCalDraw()
{
   if(!g_tcalOpen)return;
   TCalClearModal();
   int x=g_tcalX,y=g_tcalY;
   TCalObj("MOD_BG",OBJ_RECTANGLE_LABEL,x,y,636,478,"",C'20,26,33',clrWhite);
   TCalObj("MOD_TITLE",OBJ_LABEL,x+16,y+12,0,0,"ENTRY TIME MATRIX  |  BROKER SERVER TIME",C'20,26,33',C'239,243,245',11);
   TCalObj("MOD_CLOSE",OBJ_BUTTON,x+590,y+8,30,23,"X",C'70,75,82',clrWhite);
   TCalObj("MOD_NOTE",OBJ_LABEL,x+16,y+39,0,0,"Selected audit window; closed trades only. Leaderboard requires n >= 10.",C'20,26,33',C'158,172,180',8);
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
      // Rank by WR, then sample count. Small samples remain visible in raw views.
      int ranked[168];for(int i=0;i<168;i++)ranked[i]=i;
      for(int i=0;i<168;i++)
      {
         int best=i;
         for(int j=i+1;j<168;j++)
         {
            int a=ranked[j],b=ranked[best];
            int an=g_tcalWins[a/24][a%24]+g_tcalLosses[a/24][a%24];
            int bn=g_tcalWins[b/24][b%24]+g_tcalLosses[b/24][b%24];
            double aw=an>=10?TCalWr(g_tcalWins[a/24][a%24],g_tcalLosses[a/24][a%24]):-1.0;
            double bw=bn>=10?TCalWr(g_tcalWins[b/24][b%24],g_tcalLosses[b/24][b%24]):-1.0;
            if(aw>bw+1e-8||(MathAbs(aw-bw)<=1e-8&&an>bn))best=j;
         }
         if(best!=i){int swap=ranked[i];ranked[i]=ranked[best];ranked[best]=swap;}
      }
      for(int row=0;row<8;row++)
      {
         int rank=g_tcalPage*8+row;if(rank>=168)break;
         int key=ranked[rank],day=key/24,hour=key%24;
         int wins=g_tcalWins[day][hour],losses=g_tcalLosses[day][hour];
         if(wins+losses<10)
         {
            if(row==0)TCalObj("MOD_ROW_0",OBJ_LABEL,x+30,y+137,0,0,"No combination has 10 closed trades.",C'20,26,33',C'225,231,234');
            break;
         }
         TCalObj("MOD_ROW_"+(string)row,OBJ_LABEL,x+30,y+132+row*34,0,0,
            (string)(rank+1)+".  "+TCalDayName(day)+" "+TCalHourName(hour)+"     "+TCalStats(wins,losses),
            C'20,26,33',C'225,231,234',9);
      }
   }
   else
   {
      TCalObj("MOD_STATUS",OBJ_LABEL,x+24,y+101,0,0,
         g_tcalEnabled?"FILTER ON - applied to new entries and audit":"FILTER OFF - existing behavior unchanged",
         C'20,26,33',g_tcalEnabled?C'88,224,177':C'188,200,207',9);
      TCalObj("MOD_DAYS",OBJ_BUTTON,x+24,y+128,142,24,"DAYS MULTI-SELECT",C'43,93,105',clrWhite,8);
      TCalObj("MOD_HOURS",OBJ_BUTTON,x+174,y+128,150,24,"HOURS MULTI-SELECT",C'43,93,105',clrWhite,8);
      if(g_tcalPage==0)
      {
         for(int day=0;day<7;day++)
            TCalObj("MOD_PICK_DAY_"+(string)day,OBJ_BUTTON,x+24+(day%4)*147,y+165+(day/4)*34,139,27,
               TCalDayName(day),(g_tcalDraftDays&(1<<day))!=0?C'41,118,107':C'61,65,70',clrWhite,8);
      }
      else
      {
         int base=(g_tcalPage-1)*8;
         for(int row=0;row<8;row++)
         {
            int hour=base+row;if(hour>=24)break;
            TCalObj("MOD_PICK_HOUR_"+(string)hour,OBJ_BUTTON,x+24+(row%4)*147,y+165+(row/4)*34,139,27,
               TCalHourName(hour),(g_tcalDraftHours&(1<<hour))!=0?C'41,118,107':C'61,65,70',clrWhite,8);
         }
      }
      TCalObj("MOD_ALL",OBJ_BUTTON,x+24,y+256,112,24,"SELECT ALL",C'43,50,59',clrWhite,8);
      TCalObj("MOD_APPLY",OBJ_BUTTON,x+24,y+304,160,28,"APPLY FILTER",C'41,118,107',clrWhite,9);
      TCalObj("MOD_DISABLE",OBJ_BUTTON,x+196,y+304,160,28,"FILTER OFF",C'80,68,65',clrWhite,9);
      TCalObj("MOD_HINT",OBJ_LABEL,x+24,y+353,0,0,"Selection is staged until APPLY. Empty day/hour selection is rejected.",C'20,26,33',C'158,172,180',8);
   }
   if(g_tcalView==1||g_tcalView==2||g_tcalView==3)
   {
      TCalObj("MOD_PREV",OBJ_BUTTON,x+222,y+430,45,24,"<",C'43,50,59',clrWhite);
      TCalObj("MOD_PAGE",OBJ_LABEL,x+280,y+436,0,0,"PAGE "+(string)(g_tcalPage+1),C'20,26,33',clrWhite,8);
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
   for(int i=0;i<5;i++)if(clicked==TCalId("MOD_TAB_"+(string)i)){g_tcalView=i;g_tcalPage=0;TCalDraw();ChartRedraw(0);return true;}
   if(clicked==TCalId("MOD_DAYS"))g_tcalPage=0;
   else if(clicked==TCalId("MOD_HOURS"))g_tcalPage=1;
   else if(clicked==TCalId("MOD_DAY_PREV"))g_tcalDay=(g_tcalDay+6)%7;
   else if(clicked==TCalId("MOD_DAY_NEXT"))g_tcalDay=(g_tcalDay+1)%7;
   else if(clicked==TCalId("MOD_PREV"))g_tcalPage=MathMax(0,g_tcalPage-1);
   else if(clicked==TCalId("MOD_NEXT"))g_tcalPage=MathMin(g_tcalView==3?20:2,g_tcalPage+1);
   else if(clicked==TCalId("MOD_PICK_PREV"))g_tcalPage=MathMax(1,g_tcalPage-1);
   else if(clicked==TCalId("MOD_PICK_NEXT"))g_tcalPage=MathMin(3,g_tcalPage+1);
   else if(clicked==TCalId("MOD_ALL")){g_tcalDraftDays=127;g_tcalDraftHours=16777215;}
   else if(clicked==TCalId("MOD_APPLY"))
   {
      if(g_tcalDraftDays!=0&&g_tcalDraftHours!=0)
      {g_tcalDays=g_tcalDraftDays;g_tcalHours=g_tcalDraftHours;g_tcalEnabled=true;g_tcalChanged=true;}
   }
   else if(clicked==TCalId("MOD_DISABLE")){g_tcalEnabled=false;g_tcalChanged=true;}
   else
   {
      string dayTag=TCalId("MOD_PICK_DAY_"),hourTag=TCalId("MOD_PICK_HOUR_");
      if(StringFind(clicked,dayTag)==0)
      {int day=(int)StringToInteger(StringSubstr(clicked,StringLen(dayTag)));if(day>=0&&day<7)g_tcalDraftDays^=1<<day;}
      if(StringFind(clicked,hourTag)==0)
      {int hour=(int)StringToInteger(StringSubstr(clicked,StringLen(hourTag)));if(hour>=0&&hour<24)g_tcalDraftHours^=1<<hour;}
   }
   TCalDraw();ChartRedraw(0);return true;
}
#endif
