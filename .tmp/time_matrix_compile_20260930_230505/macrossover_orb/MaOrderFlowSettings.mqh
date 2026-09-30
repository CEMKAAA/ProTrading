#ifndef MA_ORDER_FLOW_SETTINGS_MQH
#define MA_ORDER_FLOW_SETTINGS_MQH

bool g_mcOfUiOpen=false;
McOfConfig g_mcOfUiDraft;
string g_mcOfUiStatus="Bid-tick quote proxy, not executed order flow";
string g_mcOfUiLastAction="";
ulong g_mcOfUiLastActionAt=0;

string McOfUiModeName(int mode)
{
   if(mode==MC_OF_BREAKOUT)return "BREAKOUT";
   if(mode==MC_OF_REJECTION)return "REJECTION";
   if(mode==MC_OF_EITHER)return "EITHER + ACT + DELTA";
   if(mode==MC_OF_PROFILE)return "PROFILE ONLY";
   if(mode==MC_OF_ACTIVITY)return "ACTIVITY ONLY";
   if(mode==MC_OF_DELTA)return "DELTA ONLY";
   return "OFF";
}
void McOfUiRaise(string name,int z){ObjectSetInteger(0,PREFIX+name,OBJPROP_ZORDER,DASH_Z+z);}
void McOfUiDraw()
{
   if(!g_mcOfUiOpen)return;
   int x=InpDashboardX+58,y=InpDashboardY+34,w=508;
   CreateRect("OF_UI_BG",x,y,w,266,C'24,30,42',C'90,178,255');McOfUiRaise("OF_UI_BG",80);
   CreateLabel("OF_UI_TITLE",x+14,y+10,"ORDER FLOW / QUOTE-TICK FILTER",C'216,222,230',10);McOfUiRaise("OF_UI_TITLE",82);
   CreateButton("OF_UI_CLOSE",x+w-42,y+7,28,22,"X",clrMaroon);McOfUiRaise("OF_UI_CLOSE",83);
   CreateLabel("OF_UI_NOTE",x+14,y+35,"Research proxy: no exchange volume or aggressor-side trades",C'184,196,210',8);
   McOfUiRaise("OF_UI_NOTE",82);
   CreateButton("OF_UI_MODE",x+14,y+60,w-28,26,"MODE: "+McOfUiModeName(g_mcOfUiDraft.mode),C'38,101,176');
   McOfUiRaise("OF_UI_MODE",83);
   string ids[]={"LOOKBACK","BINS","AREA","ACTIVITY","DELTA"};
   string labels[]={"Lookback bars","Profile bins","Value area 0.1..1","Activity min 0..100","Delta min 0..1"};
   string vals[]={(string)g_mcOfUiDraft.lookback,(string)g_mcOfUiDraft.bins,
      DoubleToString(g_mcOfUiDraft.valueArea,4),DoubleToString(g_mcOfUiDraft.minActivity,4),
      DoubleToString(g_mcOfUiDraft.minDelta,4)};
   for(int i=0;i<5;i++)
   {
      int col=i%3,row=i/3,xx=x+14+col*162,yy=y+99+row*58;
      CreateLabel("OF_UI_L_"+ids[i],xx,yy,labels[i],C'184,196,210',8);
      McOfUiRaise("OF_UI_L_"+ids[i],82);
      CreateEdit("OF_UI_E_"+ids[i],xx,yy+19,150,24,vals[i]);
      McOfUiRaise("OF_UI_E_"+ids[i],83);
   }
   CreateButton("OF_UI_APPLY",x+14,y+216,w-28,24,"APPLY / REBUILD AUDIT",C'38,101,176');
   McOfUiRaise("OF_UI_APPLY",83);
   CreateLabel("OF_UI_STATUS",x+14,y+246,StringSubstr(g_mcOfUiStatus,0,76),C'255,204,82',8);
   McOfUiRaise("OF_UI_STATUS",82);
}
bool McOfUiDecimal(string raw,double &value)
{
   StringTrimLeft(raw);StringTrimRight(raw);
   if(raw==""||raw==".")return false;
   int dots=0;
   for(int i=0;i<StringLen(raw);i++)
   {
      ushort c=StringGetCharacter(raw,i);
      if(c=='.'){if(++dots>1)return false;}
      else if(c<'0'||c>'9')return false;
   }
   value=StringToDouble(raw);return MathIsValidNumber(value);
}
bool McOfUiRead(McOfConfig &candidate)
{
   candidate=g_mcOfUiDraft;
   double n=0;
   string ids[]={"LOOKBACK","BINS","AREA","ACTIVITY","DELTA"};
   double parsed[];ArrayResize(parsed,5);
   for(int i=0;i<5;i++)
      if(!McOfUiDecimal(ObjectGetString(0,PREFIX+"OF_UI_E_"+ids[i],OBJPROP_TEXT),parsed[i]))return false;
   n=parsed[0];if(n!=MathFloor(n))return false;candidate.lookback=(int)n;
   n=parsed[1];if(n!=MathFloor(n))return false;candidate.bins=(int)n;
   candidate.valueArea=NormalizeDouble(parsed[2],8);
   candidate.minActivity=NormalizeDouble(parsed[3],8);
   candidate.minDelta=NormalizeDouble(parsed[4],8);
   return McOfConfigValid(candidate);
}
void McOfUiClose()
{
   g_mcOfUiOpen=false;DeleteByPrefix(PREFIX+"OF_UI_");UpdateDashboard();ChartRedraw(0);
}
bool McOfUiEvent(int id,const string object,long mx=0,double my=0)
{
   if(id==CHARTEVENT_OBJECT_CLICK&&object==PREFIX+"BTN_OF_SETTINGS"&&!g_mcOfUiOpen)
   {g_mcOfUiDraft=g_mcOf;g_mcOfUiOpen=true;g_mcOfUiStatus="Edit values, then APPLY to rebuild the audit";
    McOfUiDraw();ChartRedraw(0);return true;}
   if(!g_mcOfUiOpen)
      return id==CHARTEVENT_CLICK&&g_mcOfUiLastActionAt>0
         &&GetTickCount64()-g_mcOfUiLastActionAt<180;
   if(id==CHARTEVENT_CHART_CHANGE)return false;
   if(id==CHARTEVENT_OBJECT_ENDEDIT)return true;
   if(id!=CHARTEVENT_OBJECT_CLICK&&id!=CHARTEVENT_CLICK)return false;
   string action=object;
   if(id==CHARTEVENT_CLICK)
   {
      action="";
      for(int i=ObjectsTotal(0)-1;i>=0;i--)
      {
         string key=ObjectName(0,i);
         if(StringFind(key,PREFIX+"OF_UI_")!=0||ObjectGetInteger(0,key,OBJPROP_TYPE)!=OBJ_BUTTON)continue;
         long bx=ObjectGetInteger(0,key,OBJPROP_XDISTANCE),by=ObjectGetInteger(0,key,OBJPROP_YDISTANCE);
         if(mx>=bx&&mx<bx+ObjectGetInteger(0,key,OBJPROP_XSIZE)
            &&my>=by&&my<by+ObjectGetInteger(0,key,OBJPROP_YSIZE)){action=key;break;}
      }
   }
   if(ObjectFind(0,action)>=0&&ObjectGetInteger(0,action,OBJPROP_TYPE)==OBJ_BUTTON)
      ObjectSetInteger(0,action,OBJPROP_STATE,false);
   if(action==g_mcOfUiLastAction&&g_mcOfUiLastActionAt>0
      &&GetTickCount64()-g_mcOfUiLastActionAt<180)return true;
   g_mcOfUiLastAction=action;g_mcOfUiLastActionAt=GetTickCount64();
   if(action==PREFIX+"OF_UI_CLOSE"){McOfUiClose();return true;}
   if(action==PREFIX+"OF_UI_MODE")
   {g_mcOfUiDraft.mode=(g_mcOfUiDraft.mode+1)%7;McOfUiDraw();ChartRedraw(0);return true;}
   if(action==PREFIX+"OF_UI_APPLY")
   {
      McOfConfig candidate;
      if(!McOfUiRead(candidate))
      {g_mcOfUiStatus="Invalid: bars 2..128, bins 4..256, area .1..1, activity 0..100, delta 0..1";
       McOfUiDraw();ChartRedraw(0);return true;}
      if(McOfConfigText(candidate)!=McOfConfigText(g_mcOf))
      {
         ClearNasPending("orderflow_changed");ClearRetestState("orderflow_changed");
         ClearImbalanceState("orderflow_changed");g_mcOf=candidate;McOfReset(false);
         CancelHistoricalAuditBuild();g_histNeedsRedraw=true;QueueHistoricalRedraw(0);
      }
      g_mcOfUiDraft=g_mcOf;g_mcOfUiStatus="Applied; strategy SAVE records all six filter settings";
      McOfUiDraw();UpdateDashboard();ChartRedraw(0);return true;
   }
   return true;
}
#endif
