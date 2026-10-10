#ifndef ORB_POSITION_POLICY_MQH
#define ORB_POSITION_POLICY_MQH
struct OrbPositionPolicy
{
   bool independent,nextDay,reverse;
   int maxSameOpen,waitMinutes; // Stored name retained; MAX is total BUY + SELL.
};
OrbPositionPolicy g_orbPositions;
ulong g_orbManagedTicket=0;
void OrbPositionDefaults(OrbPositionPolicy &p)
{p.independent=false;p.nextDay=true;p.reverse=false;p.maxSameOpen=10;p.waitMinutes=0;}
string OrbPositionPack(const OrbPositionPolicy &p)
{return StringFormat("POS1=%d,%d,%d,%d,%d",(int)p.independent,(int)p.nextDay,(int)p.reverse,p.maxSameOpen,p.waitMinutes);}
bool OrbPositionRead(string text,OrbPositionPolicy &p)
{
   if(StringFind(text,"POS1=")!=0)return false;
   string v[];if(StringSplit(StringSubstr(text,5),',',v)!=5)return false;
   p.independent=StringToInteger(v[0])!=0;p.nextDay=StringToInteger(v[1])!=0;
   p.reverse=StringToInteger(v[2])!=0;p.maxSameOpen=(int)StringToInteger(v[3]);p.waitMinutes=(int)StringToInteger(v[4]);
   return p.maxSameOpen>=1&&p.maxSameOpen<=1000&&p.waitMinutes>=0&&p.waitMinutes<=5999&&OrbPositionPack(p)==text;
}
bool OrbPositionIsDefault(const OrbPositionPolicy &p)
{OrbPositionPolicy d;OrbPositionDefaults(d);return OrbPositionPack(p)==OrbPositionPack(d);}
string OrbPositionMetricMeta(const OrbPositionPolicy &p)
{return OrbPositionIsDefault(p)?"":"|"+OrbPositionPack(p)+(p.independent?"|TOTAL_OPEN_V2":"");}
string OrbPositionKey()
{return "ORB_POS."+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"."+(string)ChartID();}
void OrbPositionLoad()
{
   OrbPositionDefaults(g_orbPositions);string key=OrbPositionKey();
   if(!GlobalVariableCheck(key+".V"))return;
   OrbPositionPolicy p;
   p.independent=GlobalVariableGet(key+".I")>0.5;p.nextDay=GlobalVariableGet(key+".D")>0.5;
   p.reverse=GlobalVariableGet(key+".R")>0.5;p.maxSameOpen=(int)GlobalVariableGet(key+".M");p.waitMinutes=(int)GlobalVariableGet(key+".W");
   OrbPositionPolicy check;if(OrbPositionRead(OrbPositionPack(p),check))g_orbPositions=p;
}
bool OrbPositionSave()
{
   string key=OrbPositionKey();
   bool ok=GlobalVariableSet(key+".I",g_orbPositions.independent?1:0)>0;
   ok=GlobalVariableSet(key+".D",g_orbPositions.nextDay?1:0)>0&&ok;
   ok=GlobalVariableSet(key+".R",g_orbPositions.reverse?1:0)>0&&ok;
   ok=GlobalVariableSet(key+".M",g_orbPositions.maxSameOpen)>0&&ok;
   ok=GlobalVariableSet(key+".W",g_orbPositions.waitMinutes)>0&&ok;
   if(ok)ok=GlobalVariableSet(key+".V",1)>0;GlobalVariablesFlush();return ok;
}
bool OrbPositionWaitRead(string text,int &minutes)
{
   string v[];if(StringSplit(text,':',v)!=2||StringLen(v[0])!=2||StringLen(v[1])!=2)return false;
   for(int j=0;j<2;j++)for(int i=0;i<2;i++){ushort c=StringGetCharacter(v[j],i);if(c<48||c>57)return false;}
   int h=(int)StringToInteger(v[0]),m=(int)StringToInteger(v[1]);minutes=h*60+m;
   return m<60&&minutes<=5999;
}
struct OrbPositionReservation {int direction;datetime exitAt;bool known;};
OrbPositionReservation g_orbPositionReservations[];
int OrbPositionAuditCap(datetime at)
{
   int active=0,count=0;bool unknown=false;
   for(int i=0;i<ArraySize(g_orbPositionReservations);i++)
   {
      OrbPositionReservation p=g_orbPositionReservations[i];
      if(p.known&&p.exitAt>0&&p.exitAt<=at)continue;
      g_orbPositionReservations[active++]=p;
      if(!p.known)unknown=true;else count++;
   }
   ArrayResize(g_orbPositionReservations,active);
   int maximum=g_orbPositions.independent?g_orbPositions.maxSameOpen:1;
   return count>=maximum?1:(unknown?-1:0);
}
void OrbPositionReserve(int direction,bool valid,datetime exitAt)
{
   int n=ArraySize(g_orbPositionReservations);ArrayResize(g_orbPositionReservations,n+1,16);
   g_orbPositionReservations[n].direction=direction;g_orbPositionReservations[n].known=valid;
   g_orbPositionReservations[n].exitAt=exitAt;
}
#endif
