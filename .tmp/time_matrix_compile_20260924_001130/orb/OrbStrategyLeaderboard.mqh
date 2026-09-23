#ifndef ORB_STRATEGY_LEADERBOARD_MQH
#define ORB_STRATEGY_LEADERBOARD_MQH
struct OrbLbRow
{
   string id,name,symbol,family,config,dataset,slotRevision;
   bool hasMl,hasR7,regimeAvailable;
   datetime fromTime,toTime;
   double baseWr,baseR,baseDd,baseScore,mlWr,mlR,mlDd,mlScore;
   double r7Wr,r7R,r7Dd,r7Score;
   int baseN,mlN,r7N,viewW,viewL,viewFlat;
};
#include "OrbStrategyLeaderboardData.mqh"
#include "OrbStrategyLeaderboardFiveYear.mqh"
#include "OrbStrategyRegimeLeaderboard.mqh"
bool g_lbOpen=false,g_lbDrawn=false;
int g_lbMode=0; // Vanilla, registered Legacy, replaceable R7 slot.
int g_lbPage=0,g_lbOrder[];
int g_lbRegime=-1; // Display-only: ALL, then the six original signal-snapshot buckets.
OrbLbRow g_lbRows[];

void OrbLbApplyRegime(OrbLbRow &r)
{
   r.regimeAvailable=false;r.viewW=0;r.viewL=0;r.viewFlat=0;
   string mode=g_lbMode==2?"R7":(g_lbMode==1?"LEGACY":"VANILLA"),model="-",text,hash,reason;
   if(g_lbMode==2)
   {
      OrbSlotManifest m;
      if(!OrbSlotActive(r.id,m,reason)||m.config!=r.config||m.dataset!=r.dataset||m.symbol!=r.symbol)return;
      if(!OrbSlotRead("OrbML\\Slots\\Artifacts\\"+m.artifact+".model",1000000,text,hash,reason)||hash!=m.artifact)return;
      model=m.artifact;r.slotRevision=m.provider+"@"+m.revision;
   }
   if(g_lbMode==1)
   {
      OrbCampaignInfo m;
      if(!OrbCampaignRecord(r.id,m)||m.config!=r.config||m.dataset!=r.dataset)return;
      if(!OrbSlotRead("OrbML\\CampaignModels\\"+r.id+".experimental",4000000,text,hash,reason)||hash!=m.model_sha)return;
      model=m.model_sha;
   }
   OrbRegimeLbReport report;
   if(!OrbRegimeLbLoad(r.id,r.config,r.dataset,mode,model,r.fromTime,r.toTime,report))return;
   OrbRegimeLbCell c=report.cells[g_lbRegime+1];r.regimeAvailable=true;
   r.viewW=c.w;r.viewL=c.l;r.viewFlat=c.flat;
   double wr=c.n>0?100.0*c.w/c.n:0,sc=OrbRegimeLbScore(c.w,c.n,c.dd);
   if(g_lbMode==0){r.baseN=c.n;r.baseWr=wr;r.baseR=c.netR;r.baseDd=c.dd;r.baseScore=sc;}
   if(g_lbMode==1){r.hasMl=true;r.mlN=c.n;r.mlWr=wr;r.mlR=c.netR;r.mlDd=c.dd;r.mlScore=sc;}
   if(g_lbMode==2){r.hasR7=true;r.r7N=c.n;r.r7Wr=wr;r.r7R=c.netR;r.r7Dd=c.dd;r.r7Score=sc;}
}
double OrbLbRank(const OrbLbRow &r)
{
   double sc=g_lbMode==2?(r.hasR7?r.r7Score:-1):(g_lbMode==1?(r.hasMl?r.mlScore:-1):r.baseScore);
   if(g_lbRegime<0)return sc;
   if(!r.regimeAvailable)return -1000000000;
   int n=g_lbMode==2?r.r7N:(g_lbMode==1?r.mlN:r.baseN);
   if(n==0)return -1000000;
   return sc-(n<30?10000:0);
}

void OrbLbRefreshSlots()
{
   int n=OrbLbFiveCount();ArrayResize(g_lbRows,n);
   for(int i=0;i<n;i++)
   {
      OrbLbRow r;OrbLbFive(i,r);r.hasR7=false;r.slotRevision="";
      r.regimeAvailable=false;r.viewW=0;r.viewL=0;r.viewFlat=0;
      if(g_lbRegime>=0){OrbLbApplyRegime(r);g_lbRows[i]=r;continue;}
      // One snapshot per popup refresh, never file I/O in sorting/drawing/inference.
      OrbSlotManifest m;string reason;
      if(OrbSlotActive(r.id,m,reason)&&m.symbol==r.symbol&&m.config==r.config&&m.dataset==r.dataset
         &&m.metricFrom==r.fromTime&&m.metricUntil==r.toTime&&m.evaluation=="RETROSPECTIVE_TRAINING_INCLUDED_NOT_OOS")
      {
         string text,hash;
         if(OrbSlotRead("OrbML\\Slots\\Artifacts\\"+m.artifact+".model",1000000,text,hash,reason)&&hash==m.artifact)
         {
            r.hasR7=true;r.r7N=m.n;r.r7Wr=m.wr;r.r7R=m.netR;r.r7Dd=m.dd;
            double p=m.wr/100.0,z2=1.96*1.96;
            double lower=(p+z2/(2*m.n)-1.96*MathSqrt(p*(1-p)/m.n+z2/(4.0*m.n*m.n)))/(1+z2/m.n);
            r.r7Score=100*lower/(1+m.dd);r.slotRevision=m.provider+"@"+m.revision;
         }
      }
      g_lbRows[i]=r;
   }
}

void OrbLbSort()
{
   OrbLbRefreshSlots();
   int n=OrbLbFiveCount();ArrayResize(g_lbOrder,n);
   for(int i=0;i<n;i++)g_lbOrder[i]=i;
   for(int i=1;i<n;i++)
   {
      int key=g_lbOrder[i],j=i-1;OrbLbRow a=g_lbRows[key];
      double sa=OrbLbRank(a);
      while(j>=0)
      {
         OrbLbRow b=g_lbRows[g_lbOrder[j]];
         double sb=OrbLbRank(b);
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
   if(ArraySize(g_lbOrder)!=OrbLbFiveCount())OrbLbSort();
   g_lbDrawn=true;int x=InpDashboardX+644,y=InpDashboardY+142;
   CreateRect("DASH_LB_BG",x,y,594,418,C'20,27,39',C'90,178,255');
   CreateLabel("DASH_LB_TITLE",x+10,y+10,"LEADERBOARD / 5Y CLOSED PNL / AS OF 2026-09-09",clrWhite,8);
   CreateButton("BTN_LB_CLOSE",x+550,y+5,34,22,"X",C'178,37,57');
   CreateButton("BTN_LB_MODE",x+10,y+33,280,23,g_lbMode==2?"R7 ML / 5Y RETROSPECTIVE":(g_lbMode==1?"LEGACY ML / 5Y RETROSPECTIVE":"VANILLA / NO ML / 5Y"),C'38,101,176');
   CreateButton("BTN_LB_PREV",x+440,y+33,38,23,"<",C'65,73,90');
   CreateButton("BTN_LB_NEXT",x+485,y+33,38,23,">",C'65,73,90');
   CreateLabel("DASH_LB_PAGE",x+530,y+39,(string)(g_lbPage+1)+"/"+(string)((OrbLbFiveCount()+6)/7),clrWhite,7);
   CreateButton("BTN_LB_REGIME",x+10,y+60,320,20,g_lbRegime<0?"REGIME: ALL":"REGIME: "+OrbRegimeName(g_lbRegime),C'38,101,176');
   ObjectSetString(0,PREFIX+"BTN_LB_REGIME",OBJPROP_TOOLTIP,"Display-only. ALL > TLV > THV > RLV > RHV > TR PEND > TR FRESH. Original signal feature snapshot, not exit regime. N<30 sorted below adequate samples. Does not change live regime permissions.");
   CreateLabel("DASH_LB_FORMULA",x+337,y+66,g_lbRegime<0?"Wilson WR / (1+DD)":"Wilson WR / (1+DD); N>=30 first",C'184,196,210',7);
   CreateLabel("DASH_LB_CAUTION",x+10,y+82,"ML INCLUDES TRAINING DATA: NOT OOS. Closed DD, not EOD/floating.",C'255,187,92',7);
   for(int slot=0;slot<7;slot++)
   {
      string k=(string)slot;int pos=g_lbPage*7+slot;
      if(pos>=ArraySize(g_lbOrder))
      {ObjectDelete(0,PREFIX+"BTN_LB_ROW_"+k);ObjectDelete(0,PREFIX+"DASH_LB_METRIC_"+k);continue;}
      OrbLbRow r=g_lbRows[g_lbOrder[pos]];
      string shortName=r.name;if(StringLen(shortName)>54)shortName=StringSubstr(shortName,0,51)+"...";
      CreateButton("BTN_LB_ROW_"+k,x+10,y+103+slot*40,574,20,(string)(pos+1)+". "+r.symbol+" | "+shortName,C'38,53,72');
      string text=g_lbRegime<0?"NO MODEL / insufficient data or validation blocked":"NO REGIME REPORT / missing model or stale report";
      if((g_lbRegime<0||r.regimeAvailable)&&(g_lbMode==0||(g_lbMode==1&&r.hasMl)||(g_lbMode==2&&r.hasR7)))
      {
         double wr=g_lbMode==2?r.r7Wr:(g_lbMode==1?r.mlWr:r.baseWr),dd=g_lbMode==2?r.r7Dd:(g_lbMode==1?r.mlDd:r.baseDd);
         double net=g_lbMode==2?r.r7R:(g_lbMode==1?r.mlR:r.baseR),sc=g_lbMode==2?r.r7Score:(g_lbMode==1?r.mlScore:r.baseScore);
         int n=g_lbMode==2?r.r7N:(g_lbMode==1?r.mlN:r.baseN);
         text="Score "+DoubleToString(sc,2)+" | WR "+DoubleToString(wr,2)+"% | DD "+DoubleToString(dd,2)+"R | Net "+DoubleToString(net,2)+"R | N "+(string)n;
         if(g_lbRegime>=0){text+=" W/L "+(string)r.viewW+"/"+(string)r.viewL;if(n<30)text+=" LOW N";if(n==0)text="NO TRADES IN THIS REGIME (NOT A LOSS)";}
         if(g_lbMode>0)text+=" | "+(g_lbMode==2?"SLOT":r.family)+" RETRO";
      }
      CreateLabel("DASH_LB_METRIC_"+k,x+14,y+126+slot*40,text,C'184,196,210',7);
      ObjectSetString(0,PREFIX+"BTN_LB_ROW_"+k,OBJPROP_TOOLTIP,r.name+"\nSlot: "+r.slotRevision+"\nBroker dates: "+TimeToString(r.fromTime,TIME_DATE)+" - "+TimeToString(r.toTime,TIME_DATE)
         +"\nSelected regime: "+(g_lbRegime<0?"ALL":OrbRegimeName(g_lbRegime))+". Flat="+(string)r.viewFlat
         +"\nFrozen 5Y CSV, latest fixed ML weights applied retrospectively (training included). Not causal validation. Live/audit R7 uses dated vintages, so those results differ.\nClick applies strategy; ML generation and ON/OFF preserved.");
   }
   CreateLabel("DASH_LB_FOOT",x+10,y+394,"Click APPLY strategy only. Live ML mode and ON/OFF unchanged by browsing.",C'255,187,92',7);
   // Set layering last. Events are also guarded, including covered input edits.
   string fixedNames[]={"DASH_LB_BG","DASH_LB_TITLE","BTN_LB_CLOSE","BTN_LB_MODE","BTN_LB_PREV","BTN_LB_NEXT",
      "DASH_LB_PAGE","DASH_LB_FORMULA","DASH_LB_CAUTION","DASH_LB_FOOT","BTN_LB_REGIME"};
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
   else if(object==PREFIX+"BTN_LB_MODE"){g_lbMode=(g_lbMode+1)%3;g_lbPage=0;OrbLbSort();}
   else if(object==PREFIX+"BTN_LB_REGIME"){g_lbRegime=g_lbRegime>=5?-1:g_lbRegime+1;g_lbPage=0;OrbLbSort();}
   else if(object==PREFIX+"BTN_LB_PREV")g_lbPage=MathMax(0,g_lbPage-1);
   else if(object==PREFIX+"BTN_LB_NEXT")g_lbPage=MathMin((OrbLbFiveCount()-1)/7,g_lbPage+1);
   else if(StringFind(object,PREFIX+"BTN_LB_ROW_")==0)
   {
      int slot=(int)StringToInteger(StringSubstr(object,StringLen(PREFIX+"BTN_LB_ROW_")));
      int pos=g_lbPage*7+slot;if(slot<0||slot>=7||pos>=ArraySize(g_lbOrder))return true;
      OrbLbRow r;OrbLbFive(g_lbOrder[pos],r);bool found=false;
      for(int i=0;i<OrbStrategyPresetCount();i++)
      {
         OrbStrategyPreset p;if(!OrbStrategyPresetLoad(i,p)||p.id!=r.id)continue;
         g_strategyCandidateIndex=i;g_strategySearch=p.name;found=true;break;
      }
      if(found)
      {
         if(!OrbStrategyPresetApplyInteractive(g_strategyCandidateIndex))g_userStrategyNote=g_lastExecStatus;
         else g_userStrategyNote="STRATEGY APPLIED. Trained model loaded if available; ML ON/OFF preserved.";
      }
      else g_lastExecStatus="SNAPSHOT_PRESET_NOT_INSTALLED";
      g_lbOpen=false;
   }
   else return false;
   ObjectSetInteger(0,object,OBJPROP_STATE,false);UpdateDashboard();ChartRedraw(0);return true;
}
#endif
