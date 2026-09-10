#ifndef ORB_STRATEGY_LEADERBOARD_MQH
#define ORB_STRATEGY_LEADERBOARD_MQH
struct OrbLbRow
{
   string id,name,symbol,family;
   bool hasMl;
   datetime fromTime,toTime;
   double baseWr,baseR,baseDd,baseScore,mlWr,mlR,mlDd,mlScore;
   int baseN,mlN;
};
#include "OrbStrategyLeaderboardData.mqh"
bool g_lbOpen=false,g_lbMl=false,g_lbDrawn=false;
int g_lbPage=0,g_lbOrder[];

void OrbLbSort()
{
   int n=OrbLbSnapshotCount();ArrayResize(g_lbOrder,n);
   for(int i=0;i<n;i++)g_lbOrder[i]=i;
   for(int i=1;i<n;i++)
   {
      int key=g_lbOrder[i],j=i-1;OrbLbRow a;OrbLbSnapshot(key,a);
      double sa=g_lbMl?(a.hasMl?a.mlScore:-1):a.baseScore;
      while(j>=0)
      {
         OrbLbRow b;OrbLbSnapshot(g_lbOrder[j],b);
         double sb=g_lbMl?(b.hasMl?b.mlScore:-1):b.baseScore;
         if(sb>sa||(sb==sa&&StringCompare(b.id,a.id)<=0))break;
         g_lbOrder[j+1]=g_lbOrder[j];j--;
      }
      g_lbOrder[j+1]=key;
   }
}

bool OrbLbContains(long px,double py)
{
   if(!g_lbOpen)return false;
   int x=OrbLibraryX(InpDashboardX+644),y=OrbLibraryY(InpDashboardY+142);
   return px>=x&&px<x+OrbLibrarySize(594)&&py>=y&&py<y+OrbLibrarySize(418);
}

void OrbLbDraw()
{
   if(!g_lbOpen)
   {
      if(g_lbDrawn){DeleteByPrefix(PREFIX+"DASH_LB_");DeleteByPrefix(PREFIX+"BTN_LB_");g_lbDrawn=false;}
      return;
   }
   if(ArraySize(g_lbOrder)!=OrbLbSnapshotCount())OrbLbSort();
   g_lbDrawn=true;int x=InpDashboardX+644,y=InpDashboardY+142;
   CreateRect("DASH_LB_BG",x,y,594,418,C'20,27,39',C'90,178,255');
   CreateLabel("DASH_LB_TITLE",x+10,y+10,"LEADERBOARD / FROZEN TEST / 2026-09-09",clrWhite,8);
   CreateButton("BTN_LB_CLOSE",x+550,y+5,34,22,"X",C'178,37,57');
   CreateButton("BTN_LB_MODE",x+10,y+33,196,23,g_lbMl?"ML FILTERED [RESEARCH]":"NO ML FILTER",C'38,101,176');
   CreateButton("BTN_LB_PREV",x+440,y+33,38,23,"<",C'65,73,90');
   CreateButton("BTN_LB_NEXT",x+485,y+33,38,23,">",C'65,73,90');
   CreateLabel("DASH_LB_PAGE",x+530,y+39,(string)(g_lbPage+1)+"/"+(string)((OrbLbSnapshotCount()+6)/7),clrWhite,7);
   CreateLabel("DASH_LB_FORMULA",x+10,y+65,"Score = 100 x Wilson lower WR / (1 + closed-trade MaxDD R)",C'184,196,210',7);
   CreateLabel("DASH_LB_CAUTION",x+10,y+82,"Last 20% per preset; dates vary. No EOD/floating DD. Not live approval.",C'255,187,92',7);
   for(int slot=0;slot<7;slot++)
   {
      string k=(string)slot;int pos=g_lbPage*7+slot;
      if(pos>=ArraySize(g_lbOrder))
      {ObjectDelete(0,PREFIX+"BTN_LB_ROW_"+k);ObjectDelete(0,PREFIX+"DASH_LB_METRIC_"+k);continue;}
      OrbLbRow r;OrbLbSnapshot(g_lbOrder[pos],r);
      string shortName=r.name;if(StringLen(shortName)>54)shortName=StringSubstr(shortName,0,51)+"...";
      CreateButton("BTN_LB_ROW_"+k,x+10,y+103+slot*40,574,20,(string)(pos+1)+". "+r.symbol+" | "+shortName,C'38,53,72');
      string text="NO MODEL / insufficient data or validation blocked";
      if(!g_lbMl||r.hasMl)
      {
         double wr=g_lbMl?r.mlWr:r.baseWr,dd=g_lbMl?r.mlDd:r.baseDd,net=g_lbMl?r.mlR:r.baseR,sc=g_lbMl?r.mlScore:r.baseScore;
         int n=g_lbMl?r.mlN:r.baseN;
         text="Score "+DoubleToString(sc,2)+" | WR "+DoubleToString(wr,2)+"% | DD "+DoubleToString(dd,2)+"R | Net "+DoubleToString(net,2)+"R | N "+(string)n;
         if(g_lbMl)text+=" | "+r.family+" RESEARCH";
      }
      CreateLabel("DASH_LB_METRIC_"+k,x+14,y+126+slot*40,text,C'184,196,210',7);
      ObjectSetString(0,PREFIX+"BTN_LB_ROW_"+k,OBJPROP_TOOLTIP,r.name+"\nBroker dates: "+TimeToString(r.fromTime,TIME_DATE)+" - "+TimeToString(r.toTime,TIME_DATE)
         +"\nFrozen campaign settings, not current edited settings. Select only; use APPLY STRATEGY. No model activation.");
   }
   CreateLabel("DASH_LB_FOOT",x+10,y+394,"Rows select a preset only. ML family chosen on validation, not test rank.",C'255,187,92',7);
   // Set layering last. Events are also guarded, including covered input edits.
   string fixedNames[]={"DASH_LB_BG","DASH_LB_TITLE","BTN_LB_CLOSE","BTN_LB_MODE","BTN_LB_PREV","BTN_LB_NEXT",
      "DASH_LB_PAGE","DASH_LB_FORMULA","DASH_LB_CAUTION","DASH_LB_FOOT"};
   for(int i=0;i<ArraySize(fixedNames);i++)
   {
      string name=PREFIX+fixedNames[i];
      ObjectSetInteger(0,name,OBJPROP_ZORDER,DASH_Z+(i==0?30:32));
   }
   for(int i=0;i<7;i++)
   {
      ObjectSetInteger(0,PREFIX+"BTN_LB_ROW_"+(string)i,OBJPROP_ZORDER,DASH_Z+32);
      ObjectSetInteger(0,PREFIX+"DASH_LB_METRIC_"+(string)i,OBJPROP_ZORDER,DASH_Z+32);
   }
}

bool OrbLbEvent(int id,long px,double py,string object)
{
   bool control=StringFind(object,PREFIX+"BTN_LB_")==0;
   if(id==CHARTEVENT_OBJECT_ENDEDIT&&g_lbOpen){UpdateDashboard();return true;}
   if(id!=CHARTEVENT_OBJECT_CLICK)return false;
   if(control&&!g_lbOpen)return true;
   if(g_lbOpen&&!control)
   {
      if(ObjectFind(0,object)>=0&&ObjectGetInteger(0,object,OBJPROP_TYPE)==OBJ_BUTTON)
         ObjectSetInteger(0,object,OBJPROP_STATE,false);
      return true;
   }
   if(object==PREFIX+"BTN_LEADERBOARD")
   {g_strategyPopupOpen=false;g_lbOpen=true;g_lbPage=0;OrbLbSort();}
   else if(object==PREFIX+"BTN_LB_CLOSE")g_lbOpen=false;
   else if(object==PREFIX+"BTN_LB_MODE"){g_lbMl=!g_lbMl;g_lbPage=0;OrbLbSort();}
   else if(object==PREFIX+"BTN_LB_PREV")g_lbPage=MathMax(0,g_lbPage-1);
   else if(object==PREFIX+"BTN_LB_NEXT")g_lbPage=MathMin((OrbLbSnapshotCount()-1)/7,g_lbPage+1);
   else if(StringFind(object,PREFIX+"BTN_LB_ROW_")==0)
   {
      int slot=(int)StringToInteger(StringSubstr(object,StringLen(PREFIX+"BTN_LB_ROW_")));
      int pos=g_lbPage*7+slot;if(slot<0||slot>=7||pos>=ArraySize(g_lbOrder))return true;
      OrbLbRow r;OrbLbSnapshot(g_lbOrder[pos],r);bool found=false;
      for(int i=0;i<OrbStrategyPresetCount();i++)
      {
         OrbStrategyPreset p;if(!OrbStrategyPresetLoad(i,p)||p.id!=r.id)continue;
         g_strategyCandidateIndex=i;g_strategySearch=p.name;found=true;break;
      }
      g_lastExecStatus=found?"LEADERBOARD_SELECTED_USE_APPLY":"SNAPSHOT_PRESET_NOT_INSTALLED";
      g_lbOpen=false;
   }
   else return false;
   ObjectSetInteger(0,object,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return true;
}
#endif
