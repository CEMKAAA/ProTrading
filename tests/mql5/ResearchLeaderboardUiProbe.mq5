#property strict
long DASH_Z=1000000;
struct ResearchFiveYearRow
{
   string id,name,symbol,baseStatus,selectedStatus;
   int baseN,baseW,baseL,baseO,picks,selectedN,oosN;
   double baseR,baseDd,targetR,selectedR,oosR;
};
int ResearchFiveYearCount(){return 3;}
bool ResearchFiveYearLoad(int index,ResearchFiveYearRow &r)
{
   if(index<0||index>=3)return false;
   r.id=(string)index;r.name="UI probe "+(string)index;r.symbol=_Symbol;
   r.baseStatus="AUDITED";r.baseN=100;r.baseW=70-index*10;r.baseL=30+index*10;
   r.baseO=0;r.baseR=10-index;r.baseDd=3+index;r.targetR=1;
   r.picks=2;r.selectedN=40;r.selectedR=6;r.oosN=20;r.oosR=3-index;
   r.selectedStatus=index==1?"TRUE_WINNER_CANDIDATE":"NOT_CONFIRMED";
   return true;
}
bool g_probeApplied=false;
string ResearchLaunchKey(){return "FY_PROBE_LAUNCH";}
bool ResearchSavedMatrixEnabled(const ResearchFiveYearRow &r){return r.id=="2";}
bool ResearchApplyStrategy(const ResearchFiveYearRow &r){g_probeApplied=true;return true;}
#include "../../IndicatorCodeExamples/ResearchFiveYearLeaderboard.mqh"

void OnStart()
{
   int checks=0,failed=0;
   ResearchLbLauncher(8,8);
   checks++;if(ObjectFind(0,ResearchLaunchKey())<0)failed++;
   ResearchLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,ResearchLaunchKey());
   checks++;if(!g_researchLbOpen||ArraySize(g_researchLbOrder)!=3)failed++;
   checks++;if(ObjectFind(0,ResearchLbPrefix()+"BG")<0
      ||ObjectGetInteger(0,ResearchLbPrefix()+"BG",OBJPROP_ZORDER)<=DASH_Z)failed++;
   Sleep(180);
   ResearchLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,ResearchLbPrefix()+"MODE");
   checks++;if(g_researchLbMode!=1||ArraySize(g_researchLbOrder)!=1)failed++;
   Sleep(180);
   ResearchLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,ResearchLbPrefix()+"MODE");
   checks++;if(g_researchLbMode!=2||ArraySize(g_researchLbOrder)!=1)failed++;
   Sleep(180);
   ResearchLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,ResearchLbPrefix()+"ROW0");
   checks++;if(g_probeApplied)failed++;
   Sleep(180);
   ResearchLbEvent(CHARTEVENT_OBJECT_CLICK,0,0,ResearchLbPrefix()+"CLOSE");
   checks++;if(g_researchLbOpen||ObjectFind(0,ResearchLbPrefix()+"BG")>=0)failed++;
   ResearchLbShutdown();
   int f=FileOpen("ResearchLeaderboardUiProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(f!=INVALID_HANDLE){FileWrite(f,"checks","failed");FileWrite(f,checks,failed);FileClose(f);}
   Print("RESEARCH_LEADERBOARD_UI_PROBE checks=",checks," failed=",failed);
}
