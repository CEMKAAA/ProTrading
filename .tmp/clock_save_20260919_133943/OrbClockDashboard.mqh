#ifndef ORB_CLOCK_DASHBOARD_MQH
#define ORB_CLOCK_DASHBOARD_MQH
bool g_orbClockPopup=false;
int g_orbClockList=-1,g_orbClockPage=0;
int g_orbClockDraftProfile=0,g_orbClockDraftBroker=0,g_orbClockDraftExchange=0,g_orbClockDraftSession=0;
double g_orbClockDraftOffset=0;
string g_orbClockUiNote="Broker clock and exchange session are DIFFERENT settings.";

string OrbClockProfileName(int n)
{
 string names[]={"Legacy (saved fixed offset)","Fixed UTC offset / no DST","New York Close +2/+3 (US DST)",
 "New York -5/-4","Chicago -6/-5","London 0/+1","Central Europe +1/+2",
 "Eastern Europe +2/+3","Sydney +10/+11","Adelaide +9:30/+10:30","Auckland +12/+13"};
 return n>=0&&n<ArraySize(names)?names[n]:"Invalid";
}
string OrbClockSeasonName(int n)
{return n==0?"AUTO calendar":(n==1?"STANDARD / winter (all dates)":"DAYLIGHT / summer (all dates)");}
string OrbClockOffsetName(double hours)
{return "UTC"+(hours>=0?"+":"")+DoubleToString(hours,2);}

void OrbClockUiObject(string id,ENUM_OBJECT type,int x,int y,int w,int h,string text,color bg)
{
 string name=PREFIX+"TZUI_"+id;
 if(ObjectFind(0,name)<0)ObjectCreate(0,name,type,0,0,0);
 ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
 ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
 ObjectSetInteger(0,name,OBJPROP_XSIZE,w);ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
 ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
 ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'70,100,130');
 ObjectSetInteger(0,name,OBJPROP_BACK,false);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
 ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);ObjectSetInteger(0,name,OBJPROP_ZORDER,type==OBJ_RECTANGLE_LABEL?20000:20001);
 if(type==OBJ_BUTTON){ObjectSetString(0,name,OBJPROP_TEXT,text);ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);ObjectSetInteger(0,name,OBJPROP_STATE,false);}
}
void OrbClockUiDraw()
{
 if(IsTesterMode()||!InpShowDashboard)return;
 int width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
 OrbClockUiObject("OPEN",OBJ_BUTTON,MathMax(4,width-170),4,160,24,"TIMEZONE SETTINGS",C'25,95,145');
 if(!g_orbClockPopup)return;
 int w=MathMin(530,width-16),x=MathMax(4,(width-w)/2),y=34;
 OrbClockUiObject("PANEL",OBJ_RECTANGLE_LABEL,x,y,w,432,"",C'24,31,42');
 OrbClockUiObject("TITLE",OBJ_BUTTON,x+8,y+7,w-50,23,"BROKER TIMEZONE + EXCHANGE SESSION",C'25,65,95');
 OrbClockUiObject("CLOSE",OBJ_BUTTON,x+w-36,y+7,28,23,"X",C'130,55,55');
 string labels[]={"UTC OFFSET: "+OrbClockOffsetName(g_orbClockDraftOffset),
   "BROKER: "+OrbClockProfileName(g_orbClockDraftProfile),
   "BROKER DST: "+OrbClockSeasonName(g_orbClockDraftBroker),
   "EXCHANGE DST: "+OrbClockSeasonName(g_orbClockDraftExchange),
   "SESSION: "+(g_orbClockDraftSession==0?"Existing symbol rules":"BIST CASH 10:00-10:15 / end 18:00 TRT")};
 for(int i=0;i<5;i++)OrbClockUiObject("FIELD_"+(string)i,OBJ_BUTTON,x+8,y+37+i*27,w-16,24,labels[i]+"  v",i==g_orbClockList?C'37,110,145':C'48,61,77');
 int count=g_orbClockList==0?105:(g_orbClockList==1?11:(g_orbClockList==4?2:3));
 for(int i=0;i<8;i++)
 {
   int n=g_orbClockPage*8+i;string id="ITEM_"+(string)i;
   if(g_orbClockList<0||n>=count){ObjectDelete(0,PREFIX+"TZUI_"+id);continue;}
   string title=g_orbClockList==0?OrbClockOffsetName((-720+n*15)/60.0):
      (g_orbClockList==1?OrbClockProfileName(n):(g_orbClockList==4?(n==0?"Existing symbol rules":"BIST cash continuous trading / UTC+3"):OrbClockSeasonName(n)));
   OrbClockUiObject(id,OBJ_BUTTON,x+8,y+181+i*22,w-16,20,title,C'35,73,92');
 }
 OrbClockUiObject("PREV",OBJ_BUTTON,x+8,y+361,40,23,"<",C'48,61,77');
 OrbClockUiObject("NEXT",OBJ_BUTTON,x+52,y+361,40,23,">",C'48,61,77');
 OrbClockUiObject("APPLY",OBJ_BUTTON,x+w-140,y+361,132,23,"APPLY TIMEZONE",C'25,120,85');
 OrbClockUiObject("NOTE",OBJ_BUTTON,x+8,y+392,w-16,30,StringSubstr(g_orbClockUiNote,0,80),C'24,31,42');
}
void OrbClockUiOpen()
{
 g_orbClockDraftOffset=OrbBrokerOffsetHours();g_orbClockDraftProfile=(int)OrbClockProfile();
 g_orbClockDraftBroker=(int)OrbClockBrokerSeason();g_orbClockDraftExchange=(int)OrbClockExchangeSeason();
 g_orbClockDraftSession=g_orbClockSession;g_orbClockList=-1;g_orbClockPage=0;g_orbClockPopup=true;
 g_strategyPopupOpen=false;OrbClockUiDraw();ChartRedraw(0);
}
bool OrbClockUiApply()
{
 if(OrbStrategyPresetHasActiveLifecycle()||g_btRunning)
 {g_orbClockUiNote="Blocked: close active lifecycle before changing clock.";return false;}
 for(int i=OrdersTotal()-1;i>=0;i--)
    if(OrderGetTicket(i)>0&&OrderGetString(ORDER_SYMBOL)==_Symbol&&MagicOwned(OrderGetInteger(ORDER_MAGIC)))
    {g_orbClockUiNote="Blocked: pending order exists.";return false;}
 CancelHistoricalAuditBuild();
 g_orbStrategyTimezone=g_orbClockDraftOffset;
 OrbClockUseSaved(g_orbClockDraftProfile,g_orbClockDraftBroker,g_orbClockDraftExchange,g_orbClockDraftSession);
 if(g_orbClockSession==1)g_rtUtcMidnightSession=false;
 ClearNasPending("timezone_changed");ClearRetestState("timezone_changed");ClearImbalanceState("timezone_changed");
 ClearNewDayReverseRetry("timezone_changed");
 g_orbReady=false;g_nyDayKey=0;ResetForNewNyDay();
 g_instanceStartedAt=TimeCurrent();g_startupOrbGuardPending=!IsTesterMode();g_startupOrbDayLocked=false;
 g_lastNasOverlayClosedBar=0;DeleteLive();DeleteExecutionVisuals();
 g_histNeedsRedraw=true;QueueHistoricalRedraw(0);OrbMlOnStrategyApplied();
 g_userStrategyNote="Timezone applied. SAVE STRATEGY retains profile + DST + session.";
 g_orbClockUiNote=g_userStrategyNote;return true;
}
bool OrbClockUiEvent(int id,string name)
{
 if(id!=CHARTEVENT_OBJECT_CLICK)return false;
 if(name==PREFIX+"TZUI_OPEN"||name==PREFIX+"BTN_USER_TZ")
 {OrbClockUiOpen();return true;}
 if(!g_orbClockPopup)return false;
 // Modal: underlying dashboard buttons must never receive these clicks.
 if(name==PREFIX+"TZUI_CLOSE")
 {g_orbClockPopup=false;DeleteByPrefix(PREFIX+"TZUI_");OrbClockUiDraw();ChartRedraw(0);return true;}
 for(int i=0;i<5;i++)if(name==PREFIX+"TZUI_FIELD_"+(string)i)
 {g_orbClockList=i;g_orbClockPage=0;}
 int count=g_orbClockList==0?105:(g_orbClockList==1?11:(g_orbClockList==4?2:3));
 if(name==PREFIX+"TZUI_PREV")g_orbClockPage=MathMax(0,g_orbClockPage-1);
 if(name==PREFIX+"TZUI_NEXT")g_orbClockPage=MathMin((count-1)/8,g_orbClockPage+1);
 for(int i=0;i<8;i++)if(name==PREFIX+"TZUI_ITEM_"+(string)i&&g_orbClockList>=0)
 {
   int n=g_orbClockPage*8+i;if(n>=count)continue;
   if(g_orbClockList==0)g_orbClockDraftOffset=(-720+n*15)/60.0;
   if(g_orbClockList==1)g_orbClockDraftProfile=n;
   if(g_orbClockList==2)g_orbClockDraftBroker=n;
   if(g_orbClockList==3)g_orbClockDraftExchange=n;
   if(g_orbClockList==4)g_orbClockDraftSession=n;
   g_orbClockList=-1;g_orbClockPage=0;
 }
 if(name==PREFIX+"TZUI_APPLY")OrbClockUiApply();
 OrbClockUiDraw();ChartRedraw(0);return true;
}
#endif
