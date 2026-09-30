#ifndef MA_OF_LEADERBOARD_MQH
#define MA_OF_LEADERBOARD_MQH
// Frozen research results, not live strategy settings or a production selector.
struct MaOfRankRow
{
   string strategy,symbol,variant;
   int baseTrades,trades;
   double baseR,netR,baseDD,dd,baseWR,wr;
};
MaOfRankRow g_maOfRankRows[];
#include "MaOrderFlowLeaderboardData.mqh"
bool g_maOfRankOpen=false,g_maOfRankImproved=true,g_maOfRankDD=false,g_maOfRankMinTrades=true,g_maOfRankSymbol=false,g_maOfRankRetain=false;
int g_maOfRankVariant=0,g_maOfRankSort=0,g_maOfRankPage=0;
ulong g_maOfRankOpened=0;
string MaOfRankPrefix(){return "MA_OF_RESEARCH_";}
void MaOfRankWidget(string id,ENUM_OBJECT type,int x,int y,int w,int h,string text,color bg)
{
   string key=MaOfRankPrefix()+id;
   if(ObjectFind(0,key)<0)ObjectCreate(0,key,type,0,0,0);
   ObjectSetInteger(0,key,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,key,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,key,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,key,OBJPROP_XSIZE,w);ObjectSetInteger(0,key,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,key,OBJPROP_FONTSIZE,9);ObjectSetInteger(0,key,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,key,OBJPROP_BGCOLOR,bg);ObjectSetInteger(0,key,OBJPROP_BACK,false);
   ObjectSetInteger(0,key,OBJPROP_ZORDER,type==OBJ_BUTTON?3010:3000);
   ObjectSetInteger(0,key,OBJPROP_SELECTABLE,false);ObjectSetInteger(0,key,OBJPROP_HIDDEN,true);
   ObjectSetString(0,key,OBJPROP_TEXT,text);
}
double MaOfRankScore(const MaOfRankRow &r)
{
   return g_maOfRankSort==1?r.netR:(g_maOfRankSort==2?r.baseDD-r.dd:r.netR-r.baseR);
}
void MaOfRankDraw()
{
   ObjectsDeleteAll(0,MaOfRankPrefix());
   if(ArraySize(g_maOfRankRows)==0)MaOfRankLoad();
   int picks[];
   string variant=g_maOfRankVariant==1?"DELTA_005":(g_maOfRankVariant==2?"DELTA_010":"DELTA_020");
   for(int i=0;i<ArraySize(g_maOfRankRows);i++)
   {
      MaOfRankRow r=g_maOfRankRows[i];
      if(g_maOfRankVariant>0&&r.variant!=variant)continue;
      if(g_maOfRankImproved&&r.netR<=r.baseR+1e-9)continue;
      if(g_maOfRankDD&&r.dd>=r.baseDD-1e-9)continue;
      if(g_maOfRankMinTrades&&r.trades<20)continue;
      if(g_maOfRankSymbol&&r.symbol!=_Symbol)continue;
      if(g_maOfRankRetain&&r.trades<r.baseTrades*0.25)continue;
      int n=ArraySize(picks);ArrayResize(picks,n+1);picks[n]=i;
   }
   for(int i=1;i<ArraySize(picks);i++)for(int j=i;j>0&&MaOfRankScore(g_maOfRankRows[picks[j]])>MaOfRankScore(g_maOfRankRows[picks[j-1]]);j--)
   {int t=picks[j];picks[j]=picks[j-1];picks[j-1]=t;}
   int w=(int)MathMin(1000,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-20);
   int rows=(int)MathMax(1,MathMin(6,(ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS)-210)/58));
   int pages=MathMax(1,(ArraySize(picks)+rows-1)/rows);
   g_maOfRankPage=MathMax(0,MathMin(g_maOfRankPage,pages-1));
   color bg=C'20,29,42',button=C'42,72,100';
   MaOfRankWidget("BG",OBJ_RECTANGLE_LABEL,10,35,w,160+rows*58,"",bg);
   MaOfRankWidget("TITLE",OBJ_LABEL,22,43,w-60,20,"DELTA RESEARCH | 20W: 2026-05-02 / 2026-09-19 | NOT LIVE",bg);
   MaOfRankWidget("CLOSE",OBJ_BUTTON,w-26,40,30,24,"X",clrMaroon);
   int cw=(w-24)/4;
   MaOfRankWidget("VAR",OBJ_BUTTON,22,70,cw-4,23,g_maOfRankVariant==0?"Delta: ALL":variant,button);
   MaOfRankWidget("GAIN",OBJ_BUTTON,22+cw,70,cw-4,23,g_maOfRankImproved?"Net R improved":"All outcomes",button);
   MaOfRankWidget("DD",OBJ_BUTTON,22+cw*2,70,cw-4,23,g_maOfRankDD?"DD: better only":"DD: all",button);
   MaOfRankWidget("MIN",OBJ_BUTTON,22+cw*3,70,cw-4,23,g_maOfRankMinTrades?"Trades >= 20":"Trades: all",button);
   MaOfRankWidget("SYM",OBJ_BUTTON,22,98,cw-4,23,g_maOfRankSymbol?"Symbol: chart":"Symbol: all",button);
   MaOfRankWidget("KEEP",OBJ_BUTTON,22+cw,98,cw-4,23,g_maOfRankRetain?"Retain >= 25%":"Retain: all",button);
   MaOfRankWidget("SORT",OBJ_BUTTON,22+cw*2,98,cw-4,23,g_maOfRankSort==0?"Sort: R improvement":(g_maOfRankSort==1?"Sort: filtered R":"Sort: DD reduction"),button);
   MaOfRankWidget("NOTE",OBJ_LABEL,22,127,w-20,20,"OFF -> FILTERED | DD = closed trades (R) | Quote proxy, not exchange delta",bg);
   for(int i=0;i<rows;i++)
   {
      int index=g_maOfRankPage*rows+i;if(index>=ArraySize(picks))break;
      MaOfRankRow r=g_maOfRankRows[picks[index]];int y=154+i*58;
      MaOfRankWidget("NAME"+(string)i,OBJ_LABEL,22,y,w-20,20,r.symbol+" | "+r.strategy+" | "+r.variant,bg);
      string metrics=StringFormat("N %d -> %d  | WR %.1f -> %.1f%% | R %+.2f -> %+.2f | DD %.2f -> %.2f | Keep %.1f%%",
         r.baseTrades,r.trades,r.baseWR,r.wr,r.baseR,r.netR,r.baseDD,r.dd,100.0*r.trades/r.baseTrades);
      MaOfRankWidget("METRIC"+(string)i,OBJ_LABEL,22,y+21,w-20,20,metrics,bg);
   }
   int bottom=155+rows*58;
   MaOfRankWidget("PREV",OBJ_BUTTON,22,bottom,34,24,"<",button);
   MaOfRankWidget("NEXT",OBJ_BUTTON,62,bottom,34,24,">",button);
   MaOfRankWidget("PAGE",OBJ_LABEL,110,bottom+3,w-120,20,StringFormat("%d/%d | %d matches | Exploratory results; no automatic application",g_maOfRankPage+1,pages,ArraySize(picks)),bg);
   ChartRedraw(0);
}
bool MaOfRankEvent(int id,long mx,double my,string name)
{
   if(!g_maOfRankOpen)
   {
      if(id!=CHARTEVENT_OBJECT_CLICK||name!=PREFIX+"BTN_OF_RESULTS")return false;
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
      g_maOfRankOpen=true;g_maOfRankOpened=GetTickCount64();MaOfRankDraw();return true;
   }
   if(id==CHARTEVENT_CHART_CHANGE){MaOfRankDraw();return true;}
   if(id!=CHARTEVENT_CLICK||GetTickCount64()-g_maOfRankOpened<150)return true;
   string action="";
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string key=ObjectName(0,i);
      if(StringFind(key,MaOfRankPrefix())!=0||ObjectGetInteger(0,key,OBJPROP_TYPE)!=OBJ_BUTTON)continue;
      long x=ObjectGetInteger(0,key,OBJPROP_XDISTANCE),y=ObjectGetInteger(0,key,OBJPROP_YDISTANCE);
      if(mx>=x&&mx<x+ObjectGetInteger(0,key,OBJPROP_XSIZE)&&my>=y&&my<y+ObjectGetInteger(0,key,OBJPROP_YSIZE))
      {action=StringSubstr(key,StringLen(MaOfRankPrefix()));break;}
   }
   if(action=="")return true;
   if(action=="CLOSE"){g_maOfRankOpen=false;ObjectsDeleteAll(0,MaOfRankPrefix());UpdateDashboard();ChartRedraw(0);return true;}
   if(action=="PREV")g_maOfRankPage--;
   else if(action=="NEXT")g_maOfRankPage++;
   else
   {
      g_maOfRankPage=0;
      if(action=="VAR")g_maOfRankVariant=(g_maOfRankVariant+1)%4;
      if(action=="GAIN")g_maOfRankImproved=!g_maOfRankImproved;
      if(action=="DD")g_maOfRankDD=!g_maOfRankDD;
      if(action=="MIN")g_maOfRankMinTrades=!g_maOfRankMinTrades;
      if(action=="SYM")g_maOfRankSymbol=!g_maOfRankSymbol;
      if(action=="KEEP")g_maOfRankRetain=!g_maOfRankRetain;
      if(action=="SORT")g_maOfRankSort=(g_maOfRankSort+1)%3;
   }
   MaOfRankDraw();return true;
}
#endif
