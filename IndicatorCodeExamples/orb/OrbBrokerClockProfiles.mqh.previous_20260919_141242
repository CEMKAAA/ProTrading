#ifndef ORB_BROKER_CLOCK_PROFILES_MQH
#define ORB_BROKER_CLOCK_PROFILES_MQH
// Broker clock policy is independent of the exchange session clock.
enum ORB_BROKER_CLOCK_PROFILE
{
 ORB_CLOCK_LEGACY=0, // Legacy: preserve saved strategy offset
 ORB_CLOCK_FIXED=1, // Fixed: use Broker timezone dropdown, no DST
 ORB_CLOCK_NY_CLOSE=2, // New York close: UTC+2/+3, US DST calendar
 ORB_CLOCK_NEW_YORK=3, // New York: UTC-5/-4
 ORB_CLOCK_CHICAGO=4, // Chicago: UTC-6/-5
 ORB_CLOCK_LONDON=5, // London: UTC+0/+1
 ORB_CLOCK_CENTRAL_EUROPE=6, // Central Europe: UTC+1/+2
 ORB_CLOCK_EASTERN_EUROPE=7, // Eastern Europe: UTC+2/+3, EU calendar
 ORB_CLOCK_SYDNEY=8, // Sydney: UTC+10/+11
 ORB_CLOCK_ADELAIDE=9, // Adelaide: UTC+9:30/+10:30
 ORB_CLOCK_AUCKLAND=10 // Auckland: UTC+12/+13
};
enum ORB_CLOCK_SEASON
{
 ORB_SEASON_AUTO=0, // Automatic calendar (Legacy preserves existing behavior)
 ORB_SEASON_STANDARD=1, // Force standard/winter time for ALL dates
 ORB_SEASON_DAYLIGHT=2 // Force daylight/summer time for ALL dates
};
input group "=== TIMEZONE 2: BROKER AND EXCHANGE DST ==="
input ORB_BROKER_CLOCK_PROFILE InpBrokerClockProfile=ORB_CLOCK_LEGACY; // BROKER TIME PROFILE (Legacy keeps old strategies)
input ORB_CLOCK_SEASON InpBrokerClockSeason=ORB_SEASON_AUTO; // BROKER season: Auto / winter / summer
input ORB_CLOCK_SEASON InpExchangeClockSeason=ORB_SEASON_AUTO; // EXCHANGE season: Auto / winter / summer
input group "=== EXISTING SESSION AND STRATEGY SETTINGS ==="

datetime OrbClockDate(int y,int m,int d,int hour=0,int minute=0)
{MqlDateTime s;ZeroMemory(s);s.year=y;s.mon=m;s.day=d;s.hour=hour;s.min=minute;return StructToTime(s);}
int OrbClockSunday(int y,int m,int nth)
{
 MqlDateTime s;TimeToStruct(OrbClockDate(y,m,1),s);
 int first=1+(7-s.day_of_week)%7;
 if(nth>0)return first+7*(nth-1);
 int nextM=m==12?1:m+1,nextY=m==12?y+1:y;
 TimeToStruct(OrbClockDate(nextY,nextM,1)-86400,s);
 return s.day-s.day_of_week;
}
int OrbClockBaseMinutes(ORB_BROKER_CLOCK_PROFILE p)
{
 if(p==ORB_CLOCK_NY_CLOSE||p==ORB_CLOCK_EASTERN_EUROPE)return 120;
 if(p==ORB_CLOCK_NEW_YORK)return -300;
 if(p==ORB_CLOCK_CHICAGO)return -360;
 if(p==ORB_CLOCK_CENTRAL_EUROPE)return 60;
 if(p==ORB_CLOCK_SYDNEY)return 600;
 if(p==ORB_CLOCK_ADELAIDE)return 570;
 if(p==ORB_CLOCK_AUCKLAND)return 720;
 return 0;
}
bool OrbClockDstUtc(ORB_BROKER_CLOCK_PROFILE p,datetime utc)
{
 MqlDateTime s;TimeToStruct(utc,s);int y=s.year;
 datetime start=0,end=0;
 if(p==ORB_CLOCK_NY_CLOSE||p==ORB_CLOCK_NEW_YORK||p==ORB_CLOCK_CHICAGO)
 {
   int base=p==ORB_CLOCK_CHICAGO?-360:-300;
   int sm=y>=2007?3:4,em=y>=2007?11:10;
   int sn=y>=2007?2:1,en=y>=2007?1:0;
   start=OrbClockDate(y,sm,OrbClockSunday(y,sm,sn),2)-base*60;
   end=OrbClockDate(y,em,OrbClockSunday(y,em,en),2)-(base+60)*60;
 }
 else if(p==ORB_CLOCK_LONDON||p==ORB_CLOCK_CENTRAL_EUROPE||p==ORB_CLOCK_EASTERN_EUROPE)
 {
   start=OrbClockDate(y,3,OrbClockSunday(y,3,0),1);
   end=OrbClockDate(y,10,OrbClockSunday(y,10,0),1);
 }
 else if(p==ORB_CLOCK_SYDNEY||p==ORB_CLOCK_ADELAIDE||p==ORB_CLOCK_AUCKLAND)
 {
   int base=OrbClockBaseMinutes(p),sm=p==ORB_CLOCK_AUCKLAND?9:10;
   start=OrbClockDate(y,sm,OrbClockSunday(y,sm,p==ORB_CLOCK_AUCKLAND?0:1),2)-base*60;
   end=OrbClockDate(y,4,OrbClockSunday(y,4,1),3)-(base+60)*60;
   return utc<end||utc>=start;
 }
 else return false;
 return utc>=start&&utc<end;
}
int OrbClockOffsetAtUtc(ORB_BROKER_CLOCK_PROFILE p,ORB_CLOCK_SEASON season,datetime utc,int fixedMinutes)
{
 if(p==ORB_CLOCK_LEGACY||p==ORB_CLOCK_FIXED)return fixedMinutes*60;
 bool dst=season==ORB_SEASON_AUTO?OrbClockDstUtc(p,utc):season==ORB_SEASON_DAYLIGHT;
 return (OrbClockBaseMinutes(p)+(dst?60:0))*60;
}
int OrbBrokerFixedMinutes()
{
 double hours=InpBrokerClockProfile==ORB_CLOCK_LEGACY?OrbBrokerOffsetHours():OrbOffsetHoursFor(InpBrokerTimezone,InpBrokerGmtOffsetHours);
 return (int)MathRound(hours*60);
}
datetime OrbUtcToServer(datetime utc)
{
 if(InpBrokerClockProfile==ORB_CLOCK_LEGACY)return utc+(int)MathRound(OrbBrokerOffsetHours()*3600.0);
 return utc+OrbClockOffsetAtUtc(InpBrokerClockProfile,InpBrokerClockSeason,utc,OrbBrokerFixedMinutes());
}
// A repeated server timestamp during the autumn fold is inherently ambiguous.
// Prefer standard time deterministically; nonexistent spring timestamps return 0.
datetime OrbClockServerToUtc(ORB_BROKER_CLOCK_PROFILE p,ORB_CLOCK_SEASON season,datetime server,int fixedMinutes)
{
 if(p==ORB_CLOCK_LEGACY||p==ORB_CLOCK_FIXED)return server-fixedMinutes*60;
 int base=OrbClockBaseMinutes(p)*60;
 datetime standard=server-base,daylight=standard-3600;
 if(standard+OrbClockOffsetAtUtc(p,season,standard,fixedMinutes)==server)return standard;
 if(daylight+OrbClockOffsetAtUtc(p,season,daylight,fixedMinutes)==server)return daylight;
 return 0;
}
datetime OrbServerToUtc(datetime server)
{
 if(InpBrokerClockProfile==ORB_CLOCK_LEGACY)return server-(int)MathRound(OrbBrokerOffsetHours()*3600.0);
 return OrbClockServerToUtc(InpBrokerClockProfile,InpBrokerClockSeason,server,OrbBrokerFixedMinutes());
}
string OrbBrokerClockKey()
{
 if(InpBrokerClockProfile==ORB_CLOCK_LEGACY&&InpBrokerClockSeason==ORB_SEASON_AUTO&&InpExchangeClockSeason==ORB_SEASON_AUTO)return "";
 return "|clock_v1="+(string)(int)InpBrokerClockProfile+","+(string)(int)InpBrokerClockSeason+","+(string)(int)InpExchangeClockSeason+","+(string)OrbBrokerFixedMinutes();
}
bool OrbBrokerClockInputsValid()
{
 double hours=OrbOffsetHoursFor(InpBrokerTimezone,InpBrokerGmtOffsetHours);
 return MathIsValidNumber(hours)&&hours>=-12&&hours<=14
   &&(int)InpBrokerClockProfile>=0&&(int)InpBrokerClockProfile<=10
   &&(int)InpBrokerClockSeason>=0&&(int)InpBrokerClockSeason<=2
   &&(int)InpExchangeClockSeason>=0&&(int)InpExchangeClockSeason<=2;
}
string OrbBrokerClockLabel()
{
 datetime server=TimeCurrent(),utc=OrbServerToUtc(server);
 double offset=utc>0?(double)(server-utc)/3600.0:0;
 return "TIMEZONE [F7] UTC"+(offset>=0?"+":"")+DoubleToString(offset,2)
   +(InpBrokerClockProfile==ORB_CLOCK_LEGACY?" LEGACY":" P"+(string)(int)InpBrokerClockProfile);
}
#endif
