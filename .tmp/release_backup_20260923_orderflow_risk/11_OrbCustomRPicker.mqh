#ifndef ORB_CUSTOM_R_PICKER_MQH
#define ORB_CUSTOM_R_PICKER_MQH
bool g_orbRPickerOpen=false;
string g_orbRPickerStatus="Choose a preset or enter a positive R value";

int OrbRPickerLeg(int index)
{
   if(index<9)return (int)ORB_TARGET_R005+index;
   if(index==9)return (int)ORB_TARGET_R050;
   if(index<14)return (int)ORB_TARGET_R055+index-10;
   if(index==14)return (int)ORB_TARGET_R075;
   if(index<19)return (int)ORB_TARGET_R080+index-15;
   if(index==19)return (int)ORB_TARGET_R100;
   if(index<24)return (int)ORB_TARGET_R150+index-20;
   return (int)ORB_TARGET_R350+index-24;
}
bool OrbRPickerParse(string raw,double &result)
{
   StringTrimLeft(raw);StringTrimRight(raw);
   if(raw=="")return false;
   int dots=0;
   for(int i=0;i<StringLen(raw);i++)
   {
      ushort c=StringGetCharacter(raw,i);
      if(c=='.'){if(++dots>1)return false;}
      else if(c<'0'||c>'9')return false;
   }
   result=StringToDouble(raw);
   return MathIsValidNumber(result)&&result>=0.00000001&&result<=10000.0;
}
void OrbRPickerRaise(string id,int level)
{ObjectSetInteger(0,PREFIX+id,OBJPROP_ZORDER,DASH_Z+level);}
void OrbRPickerDraw()
{
   if(!g_orbRPickerOpen)return;
   int x=InpDashboardX+8,y=InpDashboardY+35;
   CreateRect("R_PICK_BG",x,y,604,278,C'24,30,42',C'90,178,255');OrbRPickerRaise("R_PICK_BG",100);
   CreateLabel("R_PICK_TITLE",x+12,y+11,"FIXED TARGET / SELECT R",C'216,222,230',10);OrbRPickerRaise("R_PICK_TITLE",102);
   CreateButton("R_PICK_CLOSE",x+556,y+8,34,24,"X",clrMaroon);OrbRPickerRaise("R_PICK_CLOSE",103);
   for(int i=0;i<28;i++)
   {
      int leg=OrbRPickerLeg(i),column=i%7,row=i/7;
      string id="R_PICK_STEP"+(string)i;
      CreateButton(id,x+12+column*83,y+42+row*35,79,29,
         DoubleToString(LegR(leg),2)+"R",RuntimeTargetLeg()==leg?C'184,103,22':C'38,101,176');
      OrbRPickerRaise(id,103);
   }
   CreateLabel("R_PICK_CAPTION",x+12,y+191,"CUSTOM R",C'216,222,230',9);OrbRPickerRaise("R_PICK_CAPTION",102);
   CreateEdit("R_PICK_VALUE",x+119,y+187,170,26,
      RuntimeTargetLeg()==(int)ORB_TARGET_CUSTOM?DoubleToString(g_rtCustomR,8):DoubleToString(RuntimeTargetR(),2));
   OrbRPickerRaise("R_PICK_VALUE",103);
   CreateButton("R_PICK_APPLY",x+300,y+187,96,26,"APPLY",C'38,101,176');OrbRPickerRaise("R_PICK_APPLY",103);
   CreateLabel("R_PICK_STATUS",x+12,y+237,g_orbRPickerStatus,C'184,196,210',8);OrbRPickerRaise("R_PICK_STATUS",102);
}
void OrbRPickerClose()
{
   g_orbRPickerOpen=false;DeleteByPrefix(PREFIX+"R_PICK_");UpdateDashboard();ChartRedraw(0);
}
bool OrbRPickerEvent(int id,const string object)
{
   if(id==CHARTEVENT_OBJECT_CLICK&&object==PREFIX+"BTN_TP"&&!g_orbRPickerOpen)
   {
      g_orbRPickerOpen=true;g_orbRPickerStatus="Choose a preset or enter a positive R value";
      ObjectSetInteger(0,object,OBJPROP_STATE,false);OrbRPickerDraw();ChartRedraw(0);return true;
   }
   if(!g_orbRPickerOpen)return false;
   if(id==CHARTEVENT_CHART_CHANGE){UpdateDashboard();return true;}
   if(id==CHARTEVENT_OBJECT_ENDEDIT)return true;
   if(id!=CHARTEVENT_OBJECT_CLICK)return true;
   if(ObjectFind(0,object)>=0&&ObjectGetInteger(0,object,OBJPROP_TYPE)==OBJ_BUTTON)
      ObjectSetInteger(0,object,OBJPROP_STATE,false);
   if(object==PREFIX+"R_PICK_CLOSE"){OrbRPickerClose();return true;}
   int leg=0;double custom=0.0;
   if(StringFind(object,PREFIX+"R_PICK_STEP")==0)
   {
      int index=(int)StringToInteger(StringSubstr(object,StringLen(PREFIX+"R_PICK_STEP")));
      if(index<0||index>=28)return true;
      leg=OrbRPickerLeg(index);
   }
   else if(object==PREFIX+"R_PICK_APPLY")
   {
      if(!OrbRPickerParse(ObjectGetString(0,PREFIX+"R_PICK_VALUE",OBJPROP_TEXT),custom))
      {g_orbRPickerStatus="Enter R from 0.00000001 to 10000";OrbRPickerDraw();return true;}
      leg=(int)ORB_TARGET_CUSTOM;
   }
   else return true; // The modal consumes clicks on dashboard controls below it.
   if(OwnPositionExists()||g_orbBridgePlanActive)
   {g_orbRPickerStatus="Close the active trade/bridge plan before changing target";OrbRPickerDraw();return true;}
   ClearNasPending("target_changed");
   if(leg==(int)ORB_TARGET_CUSTOM)g_rtCustomR=custom;
   ForceFixedRLegTarget();SetTargetLeg(leg);
   g_lastExecStatus="FIXED_TP_"+TargetLabel();
   QueueHistoricalRedraw(0);OrbRPickerClose();return true;
}
#endif
