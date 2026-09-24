#ifndef RESEARCH_FIVE_YEAR_LEADERBOARD_MQH
#define RESEARCH_FIVE_YEAR_LEADERBOARD_MQH
// Display-only research snapshot. Host EA supplies ResearchFiveYearData.mqh,
// ResearchSavedMatrixEnabled(), ResearchApplyStrategy(), and ResearchLaunchKey().
bool g_researchLbOpen=false;
int g_researchLbMode=0,g_researchLbPage=0,g_researchLbOrder[];
ulong g_researchLbOpenedAt=0,g_researchLbLastAction=0;
string g_researchLbNote="";

string ResearchLbPrefix(){return "FIVE_YEAR_RESEARCH_"+(string)ChartID()+"_";}

void ResearchLbLauncher(int x,int y)
{
   string key=ResearchLaunchKey();
   if(ObjectFind(0,key)<0)ObjectCreate(0,key,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,key,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,key,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,key,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,key,OBJPROP_XSIZE,110);ObjectSetInteger(0,key,OBJPROP_YSIZE,25);
   ObjectSetInteger(0,key,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,key,OBJPROP_BGCOLOR,C'38,101,176');
   ObjectSetInteger(0,key,OBJPROP_ZORDER,2500);
   ObjectSetInteger(0,key,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,key,OBJPROP_HIDDEN,true);
   ObjectSetString(0,key,OBJPROP_TEXT,"5Y RESEARCH");
}

void ResearchLbShutdown()
{
   ObjectsDeleteAll(0,ResearchLbPrefix());
   ObjectDelete(0,ResearchLaunchKey());
}

void ResearchLbWidget(string id,ENUM_OBJECT type,int x,int y,int w,int h,string value,color background)
{
   string key=ResearchLbPrefix()+id;
   if(ObjectFind(0,key)<0)ObjectCreate(0,key,type,0,0,0);
   ObjectSetInteger(0,key,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,key,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,key,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,key,OBJPROP_XSIZE,w);ObjectSetInteger(0,key,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,key,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,key,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,key,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,key,OBJPROP_BACK,false);
   ObjectSetInteger(0,key,OBJPROP_ZORDER,type==OBJ_BUTTON?3102:3100);
   ObjectSetInteger(0,key,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,key,OBJPROP_HIDDEN,true);
   ObjectSetString(0,key,OBJPROP_TEXT,value);
}

double ResearchLbScore(const ResearchFiveYearRow &r)
{
   if(r.baseStatus!="AUDITED"&&r.baseStatus!="AUDITED_OPEN")return -1000000000.0;
   int n=r.baseW+r.baseL;
   if(n<1)return -1000000000.0;
   double p=(double)r.baseW/n,z=1.96,z2=z*z;
   double lower=(p+z2/(2.0*n)-z*MathSqrt(p*(1.0-p)/n+z2/(4.0*n*n)))/(1.0+z2/n);
   double score=100.0*lower/(1.0+MathMax(0.0,r.baseDd));
   if(r.baseR<=0.0)score-=1000.0;
   if(r.baseStatus=="AUDITED_OPEN")score-=100.0;
   return score;
}

void ResearchLbBuild()
{
   ArrayResize(g_researchLbOrder,0);
   for(int i=0;i<ResearchFiveYearCount();i++)
   {
      ResearchFiveYearRow r;if(!ResearchFiveYearLoad(i,r))continue;
      if(g_researchLbMode==1&&!ResearchSavedMatrixEnabled(r))continue;
      if(g_researchLbMode==2&&r.selectedStatus!="TRUE_WINNER_CANDIDATE")continue;
      int at=ArraySize(g_researchLbOrder);ArrayResize(g_researchLbOrder,at+1);g_researchLbOrder[at]=i;
   }
   for(int i=1;i<ArraySize(g_researchLbOrder);i++)
   {
      int key=g_researchLbOrder[i],j=i-1;ResearchFiveYearRow a;ResearchFiveYearLoad(key,a);
      double scoreA=g_researchLbMode==2?a.oosR:ResearchLbScore(a);
      while(j>=0)
      {
         ResearchFiveYearRow b;ResearchFiveYearLoad(g_researchLbOrder[j],b);
         double scoreB=g_researchLbMode==2?b.oosR:ResearchLbScore(b);
         if(scoreB>=scoreA)break;
         g_researchLbOrder[j+1]=g_researchLbOrder[j];j--;
      }
      g_researchLbOrder[j+1]=key;
   }
   g_researchLbPage=0;
}

void ResearchLbDraw()
{
   ObjectsDeleteAll(0,ResearchLbPrefix());
   if(!g_researchLbOpen)return;
   int chartW=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   int w=(int)MathMax(400,MathMin(850,chartW-20));
   int rows=(int)MathMax(2,MathMin(7,(chartH-160)/51));
   int pages=MathMax(1,(ArraySize(g_researchLbOrder)+rows-1)/rows);
   g_researchLbPage=MathMax(0,MathMin(g_researchLbPage,pages-1));
   int x=(int)MathMax(8,(chartW-w)/2),y=35,h=130+rows*51;
   color bg=C'20,29,42',button=C'42,72,100';
   ResearchLbWidget("BG",OBJ_RECTANGLE_LABEL,x,y,w,h,"",bg);
   ResearchLbWidget("TITLE",OBJ_LABEL,x+12,y+8,w-62,22,"5Y STRATEGY RESEARCH | CLOSED TRADES | 2026-09-24",bg);
   ResearchLbWidget("CLOSE",OBJ_BUTTON,x+w-40,y+5,29,23,"X",C'160,45,60');
   string mode=g_researchLbMode==0?"ALL":(g_researchLbMode==1?"TIME MATRIX":"TRUE WINNER");
   ResearchLbWidget("MODE",OBJ_BUTTON,x+12,y+34,170,24,"VIEW: "+mode,button);
   ResearchLbWidget("PREV",OBJ_BUTTON,x+w-151,y+34,36,24,"<",button);
   ResearchLbWidget("NEXT",OBJ_BUTTON,x+w-109,y+34,36,24,">",button);
   ResearchLbWidget("PAGE",OBJ_LABEL,x+w-69,y+38,58,20,(string)(g_researchLbPage+1)+"/"+(string)pages,bg);
   string caution=g_researchLbMode==2
      ?"3Y train-hour selection; last 2Y OOS > 0. Exploratory candidate, not a guarantee."
      :"Frozen snapshot; after editing a strategy, rerun 5Y audit. Open trades excluded from PnL.";
   ResearchLbWidget("CAUTION",OBJ_LABEL,x+12,y+65,w-24,20,caution,C'20,29,42');
   for(int row=0;row<rows;row++)
   {
      int pos=g_researchLbPage*rows+row;
      if(pos>=ArraySize(g_researchLbOrder))break;
      ResearchFiveYearRow r;ResearchFiveYearLoad(g_researchLbOrder[pos],r);
      int ry=y+88+row*51;
      string name=r.symbol+" | "+r.name;
      if(StringLen(name)>82)name=StringSubstr(name,0,79)+"...";
      ResearchLbWidget("ROW"+(string)row,OBJ_BUTTON,x+12,ry,w-24,23,name,C'38,53,72');
      string metrics;
      if(g_researchLbMode==2)
         metrics=StringFormat("5Y %+0.2fR / %d trades | OOS 2Y %+0.2fR / %d trades | %d picked hours",
            r.selectedR,r.selectedN,r.oosR,r.oosN,r.picks);
      else
      {
         int n=r.baseW+r.baseL;
         double wr=n>0?100.0*r.baseW/n:0.0;
         metrics=StringFormat("%s | N %d W/L/O %d/%d/%d | WR %.1f%% | Net %+.2fR | DD %.2fR",
            r.baseStatus,r.baseN,r.baseW,r.baseL,r.baseO,wr,r.baseR,r.baseDd);
      }
      ResearchLbWidget("METRIC"+(string)row,OBJ_LABEL,x+16,ry+27,w-32,20,metrics,bg);
   }
   int foot=y+95+rows*51;
   string footer=g_researchLbNote!=""?g_researchLbNote:
      "Click a row to apply its SAVED base strategy only. Picked winner hours are research-only.";
   ResearchLbWidget("FOOT",OBJ_LABEL,x+12,foot,w-24,22,footer,bg);
   ChartRedraw(0);
}

bool ResearchLbAction(string action)
{
   if(action=="CLOSE")
   {g_researchLbOpen=false;ObjectsDeleteAll(0,ResearchLbPrefix());ChartRedraw(0);return true;}
   if(action=="MODE")
   {g_researchLbMode=(g_researchLbMode+1)%3;ResearchLbBuild();g_researchLbNote="";ResearchLbDraw();return true;}
   if(action=="PREV"){g_researchLbPage--;ResearchLbDraw();return true;}
   if(action=="NEXT"){g_researchLbPage++;ResearchLbDraw();return true;}
   if(StringFind(action,"ROW")==0)
   {
      int row=(int)StringToInteger(StringSubstr(action,3));
      int chartH=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
      int rows=(int)MathMax(2,MathMin(7,(chartH-160)/51));
      int pos=g_researchLbPage*rows+row;
      if(row<0||row>=rows||pos<0||pos>=ArraySize(g_researchLbOrder))return true;
      ResearchFiveYearRow r;ResearchFiveYearLoad(g_researchLbOrder[pos],r);
      if(g_researchLbMode==2)
         g_researchLbNote="Candidate hours NOT applied. Use TIME MATRIX manually; validate current audit.";
      else
         g_researchLbNote=ResearchApplyStrategy(r)?"Saved strategy applied; rerun audit to verify current result.":"Apply blocked or saved strategy unavailable.";
      ResearchLbDraw();return true;
   }
   return false;
}

bool ResearchLbEvent(int id,long mx,double my,string name)
{
   if(!g_researchLbOpen)
   {
      if(id!=CHARTEVENT_OBJECT_CLICK||name!=ResearchLaunchKey())return false;
      if(ObjectFind(0,name)>=0)ObjectSetInteger(0,name,OBJPROP_STATE,false);
      g_researchLbOpen=true;g_researchLbOpenedAt=GetTickCount64();g_researchLbNote="";
      ResearchLbBuild();ResearchLbDraw();return true;
   }
   if(id==CHARTEVENT_CHART_CHANGE){ResearchLbDraw();return true;}
   if(id==CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(name,ResearchLbPrefix())==0)
      {
         if(GetTickCount64()-g_researchLbOpenedAt<150)return true;
         if(GetTickCount64()-g_researchLbLastAction<120)return true;
         string action=StringSubstr(name,StringLen(ResearchLbPrefix()));
         g_researchLbLastAction=GetTickCount64();ResearchLbAction(action);return true;
      }
      if(ObjectFind(0,name)>=0&&ObjectGetInteger(0,name,OBJPROP_TYPE)==OBJ_BUTTON)
         ObjectSetInteger(0,name,OBJPROP_STATE,false);
      return true;
   }
   if(id!=CHARTEVENT_CLICK||GetTickCount64()-g_researchLbOpenedAt<150
      ||GetTickCount64()-g_researchLbLastAction<120)return true;
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string key=ObjectName(0,i);
      if(StringFind(key,ResearchLbPrefix())!=0||ObjectGetInteger(0,key,OBJPROP_TYPE)!=OBJ_BUTTON)continue;
      long x=ObjectGetInteger(0,key,OBJPROP_XDISTANCE),y=ObjectGetInteger(0,key,OBJPROP_YDISTANCE);
      if(mx>=x&&mx<x+ObjectGetInteger(0,key,OBJPROP_XSIZE)
         &&my>=y&&my<y+ObjectGetInteger(0,key,OBJPROP_YSIZE))
      {g_researchLbLastAction=GetTickCount64();ResearchLbAction(StringSubstr(key,StringLen(ResearchLbPrefix())));break;}
   }
   return true;
}
#endif
