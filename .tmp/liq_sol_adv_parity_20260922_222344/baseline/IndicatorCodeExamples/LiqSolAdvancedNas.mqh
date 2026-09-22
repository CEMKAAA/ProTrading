#ifndef LIQ_SOL_ADVANCED_NAS_MQH
#define LIQ_SOL_ADVANCED_NAS_MQH
#include "macrossover_orb/NasUltimate_Core.mqh"

// All defaults reproduce the pre-filter Sol Advanced execution policy.
struct LnNasPolicy
{
   int gate;                 // 0 off, 1 entry confirmation, 2 state
   int exitMode;             // 0 off, 1 opposite, 2 additional
   bool stateVolume,flowVolume,independent,reverseExit;
   double stateMultiplier,flowMultiplier;
   int sensitivity,waitMinutes,entryAgeMinutes,maxSameOpen,reverseWaitMinutes;
};
LnNasPolicy g_lnNas,g_lnNasDraft;
bool g_lnNasPanel=false,g_lnNasReady=false;
string g_lnNasStatus="";
struct LnNasEvent {datetime at;int dir;bool stateAllowed,flowAllowed;};
LnNasEvent g_lnNasEvents[];
datetime g_lnNasBar=0,g_lnNasSeed=0;
string g_lnNasSignature="";
ErlSignal g_lnNasPendingSignal;
bool g_lnNasPending=false,g_lnNasAuditData=true;

void LnNasDefaults(LnNasPolicy &p)
{
   ZeroMemory(p);p.reverseExit=InpCloseOnReverse;
   p.stateMultiplier=1.0;p.flowMultiplier=1.0;p.sensitivity=4;
   p.entryAgeMinutes=120;
}
string LnNasPack(const LnNasPolicy &p)
{
   return StringFormat("LN_NAS_V1|%d|%d|%d|%d|%d|%d|%.8f|%.8f|%d|%d|%d|%d|%d",
      p.gate,p.exitMode,(int)p.stateVolume,(int)p.flowVolume,(int)p.independent,(int)p.reverseExit,
      p.stateMultiplier,p.flowMultiplier,p.sensitivity,p.waitMinutes,p.entryAgeMinutes,p.maxSameOpen,p.reverseWaitMinutes);
}
bool LnNasValid(const LnNasPolicy &p)
{
   return p.gate>=0&&p.gate<=2&&p.exitMode>=0&&p.exitMode<=2
      &&MathIsValidNumber(p.stateMultiplier)&&p.stateMultiplier>0&&p.stateMultiplier<=100
      &&MathIsValidNumber(p.flowMultiplier)&&p.flowMultiplier>0&&p.flowMultiplier<=100
      &&p.sensitivity>=1&&p.sensitivity<=100&&p.waitMinutes>=0&&p.waitMinutes<=1440
      &&p.entryAgeMinutes>=0&&p.entryAgeMinutes<=10080&&p.maxSameOpen>=0&&p.maxSameOpen<=100
      &&p.reverseWaitMinutes>=0&&p.reverseWaitMinutes<=1440;
}
bool LnNasUnpack(string line,LnNasPolicy &p)
{
   string a[];if(StringSplit(line,'|',a)!=14||a[0]!="LN_NAS_V1")return false;
   for(int i=1;i<14;i++)if(a[i]=="")return false;
   p.gate=(int)StringToInteger(a[1]);p.exitMode=(int)StringToInteger(a[2]);
   p.stateVolume=(int)StringToInteger(a[3])!=0;p.flowVolume=(int)StringToInteger(a[4])!=0;
   p.independent=(int)StringToInteger(a[5])!=0;p.reverseExit=(int)StringToInteger(a[6])!=0;
   p.stateMultiplier=StringToDouble(a[7]);p.flowMultiplier=StringToDouble(a[8]);
   p.sensitivity=(int)StringToInteger(a[9]);p.waitMinutes=(int)StringToInteger(a[10]);
   p.entryAgeMinutes=(int)StringToInteger(a[11]);p.maxSameOpen=(int)StringToInteger(a[12]);
   p.reverseWaitMinutes=(int)StringToInteger(a[13]);
   if(!LnNasValid(p))return false;
   return LnNasPack(p)==line;
}
bool LnNasActive(){return g_lnNas.gate!=0||g_lnNas.exitMode!=0||g_lnNas.independent
   ||g_lnNas.reverseExit!=InpCloseOnReverse||(g_lnNas.reverseExit&&g_lnNas.reverseWaitMinutes>0);}
string LnNasKey(){return "LN_SOL_ADV_NAS."+_Symbol+"."+(string)RuntimeMagic();}
bool LnNasSaveRuntime()
{
   string packed=LnNasPack(g_lnNas);
   return LiqLibraryAtomicWrite(LiqLibraryFolder()+"\\nas_"+LiqLibraryHash(LnNasKey())+".txt",packed);
}
bool LnNasLoadRuntime()
{
   LnNasDefaults(g_lnNas);g_lnNasPending=false;string raw="";
   string path=LiqLibraryFolder()+"\\nas_"+LiqLibraryHash(LnNasKey())+".txt";
   if(!FileIsExist(path,FILE_COMMON))return true;
   return LiqLibraryRead(path,raw)&&LnNasUnpack(raw,g_lnNas);
}
bool LnNasCompatible(const LnNasPolicy &p)
{
   if(!LnNasValid(p))return false;
   if((p.gate!=0||p.exitMode!=0||p.independent||p.reverseExit!=InpCloseOnReverse||p.reverseWaitMinutes>0)
      &&g_targetModel==ERL_TARGET_OPPOSITE_SIGNAL)return false;
   if((p.independent||!p.reverseExit||p.reverseWaitMinutes>0)
      &&AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)return false;
   return true;
}
void LnNasInvalidate(){g_lnNasBar=0;g_lnNasSeed=0;g_lnNasSignature="";ArrayFree(g_lnNasEvents);ArrayFree(g_simCache);}

// One calculation per closed chart bar and parameter set. The same closed-bar
// events feed historical audit, live entry decisions and native exits.
bool LnNasBuild(datetime oldest)
{
   if(g_lnNas.gate==0&&g_lnNas.exitMode==0)return true;
   ENUM_TIMEFRAMES tf=(ENUM_TIMEFRAMES)_Period;
   datetime closed=iTime(_Symbol,tf,1);
   if(closed<=0||oldest<=0){g_lnNasStatus="NAS history unavailable";return false;}
   string signature=_Symbol+"|"+(string)tf+"|"+(string)g_lnNas.sensitivity+"|"
      +(string)g_lnNas.stateVolume+"|"+DoubleToString(g_lnNas.stateMultiplier,8)+"|"
      +(string)g_lnNas.flowVolume+"|"+DoubleToString(g_lnNas.flowMultiplier,8);
   if(g_lnNasBar==closed&&g_lnNasSignature==signature&&g_lnNasSeed<=oldest&&ArraySize(g_lnNasEvents)>0)return true;
   int shift=iBarShift(_Symbol,tf,oldest,false);
   if(shift<0){g_lnNasStatus="NAS start bar unavailable";return false;}
   int requested=MathMax(5200,shift+5200);
   MqlRates rates[];ArraySetAsSeries(rates,false);
   int count=CopyRates(_Symbol,tf,1,requested,rates);
   if(count<shift+200||count<5200||rates[count-1].time!=closed)
   {g_lnNasStatus="NAS warmup/history incomplete";return false;}
   NasSettings cfg;cfg.sensitivity=g_lnNas.sensitivity;cfg.rsiLength=14;cfg.atrRisk=1;cfg.atrLen=14;
   NasPoint points[];if(NAS_Calculate(rates,count,cfg,points)!=count){g_lnNasStatus="NAS calculation failed";return false;}
   LnNasEvent events[];
   for(int i=20;i<count-1;i++)
   {
      if(points[i].buy==points[i].sell)continue;
      double mean=0;for(int k=i-20;k<i;k++)mean+=(double)rates[k].tick_volume;
      mean/=20.0;double volume=(double)rates[i].tick_volume;
      int n=ArraySize(events);ArrayResize(events,n+1);
      events[n].at=rates[i+1].time;events[n].dir=points[i].buy?1:-1;
      events[n].stateAllowed=!g_lnNas.stateVolume||(mean>0&&volume>=mean*g_lnNas.stateMultiplier);
      events[n].flowAllowed=!g_lnNas.flowVolume||(mean>0&&volume>=mean*g_lnNas.flowMultiplier);
   }
   ArraySwap(g_lnNasEvents,events);g_lnNasBar=closed;g_lnNasSeed=rates[0].time;g_lnNasSignature=signature;
   return true;
}
// 1 allowed, 0 rejected/wait, -1 unknown data.
int LnNasEntryDecision(int dir,datetime signalAt,datetime through,datetime &acceptedAt)
{
   acceptedAt=signalAt;if(g_lnNas.gate==0)return 1;
   if(!LnNasBuild(signalAt))return -1;
   if(g_lnNas.gate==2)
   {
      for(int i=ArraySize(g_lnNasEvents)-1;i>=0;i--)
         if(g_lnNasEvents[i].at<=signalAt&&g_lnNasEvents[i].stateAllowed)
            return g_lnNasEvents[i].dir==dir?1:0;
      return -1;
   }
   datetime ageStart=signalAt-(datetime)(g_lnNas.entryAgeMinutes*60);
   for(int i=ArraySize(g_lnNasEvents)-1;i>=0;i--)
      if(g_lnNasEvents[i].at<=signalAt&&g_lnNasEvents[i].at>=ageStart&&g_lnNasEvents[i].flowAllowed)
      {if(g_lnNasEvents[i].dir==dir)return 1;break;}
   for(int i=0;i<ArraySize(g_lnNasEvents);i++)
      if(g_lnNasEvents[i].at>signalAt&&g_lnNasEvents[i].at<=through&&g_lnNasEvents[i].dir==dir&&g_lnNasEvents[i].flowAllowed)
      {acceptedAt=g_lnNasEvents[i].at;return 1;}
   return 0;
}
datetime LnNasExitAt(int dir,datetime opened,datetime through,int waitMinutes)
{
   if(g_lnNas.exitMode==0||!LnNasBuild(opened))return 0;
   datetime eligible=opened+(datetime)(waitMinutes*60),last=0;
   int lastDir=0;
   for(int i=0;i<ArraySize(g_lnNasEvents);i++)
   {
      LnNasEvent e=g_lnNasEvents[i];if(e.at<=opened||e.at>through||!e.flowAllowed)continue;
      if(e.at<=eligible){last=e.at;lastDir=e.dir;continue;}
      if(last>0&&lastDir==-dir)return eligible;
      if(e.dir==-dir)return e.at;
   }
   if(last>0&&lastDir==-dir&&through>=eligible)return eligible;
   return 0;
}
datetime LnNasReverseAt(const ErlSignal &raw[],int dir,datetime opened,datetime through,int waitMinutes)
{
   if(!g_lnNas.reverseExit)return 0;
   datetime eligible=opened+(datetime)(waitMinutes*60);
   for(int i=0;i<ArraySize(raw);i++)
      if(raw[i].availableTime>opened&&raw[i].availableTime<=through&&EffectiveTradeDir(raw[i].dir)==-dir)
         return MathMax(raw[i].availableTime,eligible);
   return 0;
}
datetime LnNasNextRaw(const ErlSignal &raw[],datetime after)
{
   for(int i=0;i<ArraySize(raw);i++)if(raw[i].availableTime>after)return raw[i].availableTime;
   return 0;
}
void LnNasFilterHistorical(ErlSignal &signals[],const ErlSignal &raw[])
{
   g_lnNasAuditData=true;
   if(!LnNasActive()||g_lnNas.gate==0)return;
   if(ArraySize(signals)>0&&!LnNasBuild(signals[0].availableTime))
   {g_lnNasAuditData=false;return;}
   ErlSignal kept[];
   for(int i=0;i<ArraySize(signals);i++)
   {
      ErlSignal candidate=signals[i];datetime accepted=0;
      datetime next=LnNasNextRaw(raw,candidate.availableTime);
      datetime through=next>0?next-1:TimeCurrent();
      int decision=LnNasEntryDecision(EffectiveTradeDir(candidate.dir),candidate.availableTime,through,accepted);
      if(decision<0){g_lnNasAuditData=false;break;}
      if(decision!=1)continue;
      candidate.availableTime=accepted;
      int n=ArraySize(kept);ArrayResize(kept,n+1);kept[n]=candidate;
   }
   if(g_lnNasAuditData){ArrayResize(signals,ArraySize(kept));for(int i=0;i<ArraySize(kept);i++)signals[i]=kept[i];}
}
datetime LnNasAuditExit(const ErlSignal &signal,const ErlSignal &raw[],datetime oldReverse)
{
   if(!LnNasActive())return oldReverse;
   int dir=EffectiveTradeDir(signal.dir);
   datetime reverse=LnNasReverseAt(raw,dir,signal.availableTime,TimeCurrent(),g_lnNas.reverseWaitMinutes);
   datetime nas=0;
   if(g_lnNas.exitMode!=0)
   {
      if(!LnNasBuild(signal.availableTime)){g_lnNasAuditData=false;return 0;}
      nas=LnNasExitAt(dir,signal.availableTime,TimeCurrent(),g_lnNas.waitMinutes);
   }
   if(reverse==0)return nas;
   if(nas==0)return reverse;
   return MathMin(reverse,nas);
}
int LnNasAuditCap(int index)
{
   if(!g_lnNas.independent||g_lnNas.maxSameOpen==0)return 0;
   int direction=EffectiveTradeDir(g_histSignals[index].dir),count=0;
   datetime at=g_histSignals[index].availableTime;
   for(int i=0;i<index;i++)
   {
      if(EffectiveTradeDir(g_histSignals[i].dir)!=direction||g_histSignalInvalidReason[i]=="MAX_SAME_OPEN")continue;
      if(!g_histSignalValid[i])return -1;
      if(!g_histSignalClosed[i]||g_histSignalExitTime[i]>=at)count++;
   }
   return count>=g_lnNas.maxSameOpen?1:0;
}
bool LnNasLiveAccept(ErlSignal &signal)
{
   if(!LnNasActive())return true;
   if(g_lnNas.independent&&g_fileBridgeOnlyMode&&!g_nativeTradeWithBridgeOnly)
   {g_lastBlock="MAX_REQUIRES_NATIVE_POSITION_VISIBILITY";return false;}
   int dir=EffectiveTradeDir(signal.dir);datetime accepted=signal.availableTime;
   if(g_lnNas.gate!=0)
   {
      int decision=LnNasEntryDecision(dir,signal.availableTime,TimeCurrent(),accepted);
      if(decision!=1)
      {
         if(decision==0&&g_lnNas.gate==1){g_lnNasPending=true;g_lnNasPendingSignal=signal;}
         g_lastBlock=decision<0?"NAS_DATA":g_lnNas.gate==1?"NAS_ENTRY_WAIT":"NAS_STATE_REJECT";
         return false;
      }
   }
   if(g_lnNas.independent&&g_lnNas.maxSameOpen>0&&LnNasOpenCount(dir)>=g_lnNas.maxSameOpen)
   {g_lastBlock="MAX_SAME_OPEN";g_lnNasPending=false;return false;}
   if(accepted>signal.availableTime)
   {
      if(TimeCurrent()-accepted>MathMax(180,2*PeriodSeconds(g_entryTf)))
      {g_lastBlock="NAS_CONFIRMATION_STALE";g_lnNasPending=false;return false;}
      signal.availableTime=accepted;
   }
   g_lnNasPending=false;return true;
}
void LnNasRetryPending()
{
   if(!g_lnNasPending||!g_eaEnabled)return;
   datetime next=LnNasNextRaw(g_histRawCache,g_lnNasPendingSignal.availableTime);
   if(next>0&&TimeCurrent()>=next){g_lnNasPending=false;return;}
   ErlSignal pending=g_lnNasPendingSignal;
   OpenSignal(pending);
}
void LnNasManageNative()
{
   if(!LnNasActive()||(g_lnNas.exitMode==0&&(!g_lnNas.reverseExit||g_lnNas.reverseWaitMinutes==0)))return;
   datetime now=TimeCurrent();
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0||PositionGetString(POSITION_SYMBOL)!=_Symbol
         ||!IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC)))continue;
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      datetime reverse=LnNasReverseAt(g_histRawCache,dir,opened,now,g_lnNas.reverseWaitMinutes);
      datetime nas=LnNasExitAt(dir,opened,now,g_lnNas.waitMinutes);
      if((reverse>0&&reverse<=now)||(nas>0&&nas<=now))
      {
         if(!trade.PositionClose(ticket))
            AuditWrite("nas_position_close_retry",(string)ticket,dir,0,0,0,0,
               "ret="+(string)trade.ResultRetcode());
         else AuditWrite("nas_position_close",(string)ticket,dir,0,0,0,0,
            nas>0&&(reverse==0||nas<=reverse)?"NAS_EXIT":"REVERSE_WAIT_EXIT");
      }
   }
}
int LnNasOpenCount(int dir)
{
   int n=0;for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0&&PositionGetString(POSITION_SYMBOL)==_Symbol
         &&IsOwnMagic((long)PositionGetInteger(POSITION_MAGIC))
         &&(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1)==dir)n++;
   return n;
}

string LnNasObject(string id){return PFX+"NAS_"+id;}
void LnNasWidget(string id,ENUM_OBJECT kind,int x,int y,int width,int height,string caption,color fill)
{
   string key=LnNasObject(id);bool fresh=ObjectFind(0,key)<0;
   if(fresh)ObjectCreate(0,key,kind,0,0,0);
   ObjectSetInteger(0,key,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,key,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,key,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,key,OBJPROP_XSIZE,width);ObjectSetInteger(0,key,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,key,OBJPROP_BGCOLOR,fill);ObjectSetInteger(0,key,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,key,OBJPROP_FONTSIZE,9);ObjectSetInteger(0,key,OBJPROP_ZORDER,DASH_Z+200);
   ObjectSetInteger(0,key,OBJPROP_SELECTABLE,false);
   if(kind!=OBJ_EDIT||fresh)ObjectSetString(0,key,OBJPROP_TEXT,caption);
}
string LnNasDuration(int minutes){return StringFormat("%02d:%02d",minutes/60,minutes%60);}
bool LnNasParseDigits(string raw,int &value)
{
   if(raw=="")return false;
   for(int i=0;i<StringLen(raw);i++){ushort c=StringGetCharacter(raw,i);if(c<48||c>57)return false;}
   value=(int)StringToInteger(raw);return value>=0;
}
bool LnNasParseDecimal(string raw,double &value)
{
   if(raw=="")return false;
   int dots=0;
   for(int i=0;i<StringLen(raw);i++)
   {ushort c=StringGetCharacter(raw,i);if(c==46){dots++;if(dots>1)return false;}else if(c<48||c>57)return false;}
   if(raw==".")return false;
   value=StringToDouble(raw);return MathIsValidNumber(value);
}
bool LnNasParseDuration(string raw,int &minutes)
{
   string parts[];if(StringSplit(raw,':',parts)!=2||StringLen(parts[1])!=2)return false;
   int h=0,m=0;if(!LnNasParseDigits(parts[0],h)||!LnNasParseDigits(parts[1],m)||m>59||h>24)return false;
   minutes=h*60+m;return minutes<=1440;
}
void LnNasDrawPanel()
{
   if(!g_lnNasPanel)return;
   int x=8,y=40,w=(int)MathMin(706,MathMax(330,ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-16));
   color off=C'55,64,75',on=C'25,114,91';
   LnNasWidget("BG",OBJ_RECTANGLE_LABEL,x,y,w,330,"",C'23,31,43');
   LnNasWidget("TITLE",OBJ_LABEL,x+12,y+9,w-60,20,"SOL ADV NAS / POSITIONS",off);
   LnNasWidget("CLOSE",OBJ_BUTTON,x+w-40,y+5,30,22,"X",clrMaroon);
   int col=(w-30)/3;
   LnNasWidget("MODE",OBJ_BUTTON,x+10,y+39,col-5,24,g_lnNasDraft.independent?"INDEPENDENT":"LEGACY",g_lnNasDraft.independent?on:off);
   LnNasWidget("GATE",OBJ_BUTTON,x+10+col,y+39,col-5,24,g_lnNasDraft.gate==1?"ENTRY GATE":g_lnNasDraft.gate==2?"STATE GATE":"GATE OFF",g_lnNasDraft.gate?on:off);
   LnNasWidget("EXIT",OBJ_BUTTON,x+10+2*col,y+39,col-5,24,g_lnNasDraft.exitMode==1?"OPP EXIT":g_lnNasDraft.exitMode==2?"ADD EXIT":"NAS EXIT OFF",g_lnNasDraft.exitMode?on:off);
   LnNasWidget("SV",OBJ_BUTTON,x+10,y+71,col-5,24,g_lnNasDraft.stateVolume?"STATE VOL ON":"STATE VOL OFF",g_lnNasDraft.stateVolume?on:off);
   LnNasWidget("FV",OBJ_BUTTON,x+10+col,y+71,col-5,24,g_lnNasDraft.flowVolume?"FLOW VOL ON":"FLOW VOL OFF",g_lnNasDraft.flowVolume?on:off);
   LnNasWidget("REV",OBJ_BUTTON,x+10+2*col,y+71,col-5,24,g_lnNasDraft.reverseExit?"REVERSE ON":"REVERSE OFF",g_lnNasDraft.reverseExit?on:off);
   string ids[]={"SVM","FVM","SENS","AGE","WAIT","MAX","RWAIT"};
   string labels[]={"State vol x","Flow vol x","Sensitivity","Entry age min","NAS wait HH:MM","MAX same open","Reverse wait HH:MM"};
   string vals[]={DoubleToString(g_lnNasDraft.stateMultiplier,2),DoubleToString(g_lnNasDraft.flowMultiplier,2),
      (string)g_lnNasDraft.sensitivity,(string)g_lnNasDraft.entryAgeMinutes,LnNasDuration(g_lnNasDraft.waitMinutes),
      (string)g_lnNasDraft.maxSameOpen,LnNasDuration(g_lnNasDraft.reverseWaitMinutes)};
   for(int i=0;i<7;i++)
   {
      int xx=x+10+(i%3)*col,yy=y+107+(i/3)*57;
      LnNasWidget("L"+ids[i],OBJ_LABEL,xx,yy,col-5,20,labels[i],off);
      LnNasWidget(ids[i],OBJ_EDIT,xx,yy+19,col-5,24,vals[i],off);
   }
   LnNasWidget("APPLY",OBJ_BUTTON,x+10,y+278,w-20,25,"APPLY NAS / POSITION SETTINGS",C'36,99,177');
   LnNasWidget("STATUS",OBJ_LABEL,x+10,y+308,w-20,18,StringSubstr(g_lnNasStatus,0,95),off);
}
void LnNasDrawNav()
{
   if(IsTesterMode()||!InpShowDashboard)return;
   LnNasWidget("NAV",OBJ_BUTTON,524,8,176,25,"NAS / POSITIONS",C'36,99,177');
}
bool LnNasReadPanel(LnNasPolicy &candidate)
{
   candidate=g_lnNasDraft;
   string sv=ObjectGetString(0,LnNasObject("SVM"),OBJPROP_TEXT);
   string fv=ObjectGetString(0,LnNasObject("FVM"),OBJPROP_TEXT);
   if(sv==""||fv=="")return false;
   if(!LnNasParseDecimal(sv,candidate.stateMultiplier)||!LnNasParseDecimal(fv,candidate.flowMultiplier))return false;
   if(!LnNasParseDigits(ObjectGetString(0,LnNasObject("SENS"),OBJPROP_TEXT),candidate.sensitivity)
      ||!LnNasParseDigits(ObjectGetString(0,LnNasObject("AGE"),OBJPROP_TEXT),candidate.entryAgeMinutes)
      ||!LnNasParseDigits(ObjectGetString(0,LnNasObject("MAX"),OBJPROP_TEXT),candidate.maxSameOpen)
      ||!LnNasParseDuration(ObjectGetString(0,LnNasObject("WAIT"),OBJPROP_TEXT),candidate.waitMinutes)
      ||!LnNasParseDuration(ObjectGetString(0,LnNasObject("RWAIT"),OBJPROP_TEXT),candidate.reverseWaitMinutes))return false;
   return LnNasValid(candidate);
}
bool LnNasPanelEvent(int id,string object)
{
   if(id==CHARTEVENT_OBJECT_CLICK&&object==LnNasObject("NAV"))
   {g_lnNasDraft=g_lnNas;g_lnNasPanel=true;LnNasDrawPanel();ChartRedraw(0);return true;}
   if(!g_lnNasPanel)return false;
   if(id==CHARTEVENT_CHART_CHANGE){LnNasDrawPanel();return true;}
   if(id!=CHARTEVENT_OBJECT_CLICK)return true;
   if(object==LnNasObject("CLOSE")){g_lnNasPanel=false;DeleteByPrefix(PFX+"NAS_");DrawDashboard();ChartRedraw(0);return true;}
   LnNasPolicy next;if(!LnNasReadPanel(next)){g_lnNasStatus="Invalid numeric or HH:MM field";LnNasDrawPanel();return true;}
   if(object==LnNasObject("MODE"))next.independent=!next.independent;
   else if(object==LnNasObject("GATE"))next.gate=(next.gate+1)%3;
   else if(object==LnNasObject("EXIT"))next.exitMode=(next.exitMode+1)%3;
   else if(object==LnNasObject("SV"))next.stateVolume=!next.stateVolume;
   else if(object==LnNasObject("FV"))next.flowVolume=!next.flowVolume;
   else if(object==LnNasObject("REV"))next.reverseExit=!next.reverseExit;
   else if(object!=LnNasObject("APPLY"))return true;
   if(object!=LnNasObject("APPLY"))
   {
      g_lnNasDraft=next;LnNasDrawPanel();ChartRedraw(0);return true;
   }
   if(!LnNasCompatible(next)){g_lnNasStatus="Independent/held reverse requires MT5 hedging";LnNasDrawPanel();return true;}
   if(!LiqLibraryCanApply()){g_lnNasStatus=g_liqLibraryStatus;LnNasDrawPanel();return true;}
   LnNasPolicy previous=g_lnNas;g_lnNas=next;
   if(!LnNasSaveRuntime()){g_lnNas=previous;g_lnNasStatus="Settings save failed";LnNasDrawPanel();return true;}
   g_lnNasDraft=g_lnNas;LnNasInvalidate();g_lnNasStatus="Applied (NAS on chart TF; exits native MT5 only)";
   RefreshAfterConfigChange(true);LnNasDrawPanel();ChartRedraw(0);return true;
}
#endif
