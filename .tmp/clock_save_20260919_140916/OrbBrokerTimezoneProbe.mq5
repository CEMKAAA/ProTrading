#property strict
#include "OrbBrokerTimezone.mqh"
double g_rtRiskPerTradePct=1;
#include "OrbMoneyRisk.mqh"
void OnStart()
{
   int checks=0,failed=0;
   datetime utc=D'2026.09.17 00:15:00';
   for(int m=-720;m<=840;m+=15)
   {
      double hours=OrbOffsetHoursFor((ORB_BROKER_TIMEZONE)m,0);
      int seconds=(int)MathRound(hours*3600);
      g_orbStrategyTimezone=hours;
      checks++;
      if(seconds!=m*60||OrbUtcToServer(utc)!=utc+seconds||OrbServerToUtc(utc+seconds)!=utc)failed++;
   }
   g_orbStrategyTimezone=0;
   checks++;if(OrbBrokerOffsetHours()!=0)failed++;
   checks++;if(OrbOffsetHoursFor(ORB_GMT_CUSTOM,2.5)!=2.5)failed++;
   checks++;if(!OrbMoneyInputValid(60.93,60.93))failed++;
   checks++;if(OrbMoneyInputValid(60.94,60.93))failed++;
   checks++;if(OrbMoneyInputValid(0,60.93)||OrbMoneyInputValid(-1,60.93))failed++;
   checks++;if(OrbBoundedMoney(60.93,30)!=30)failed++;
   checks++;if(OrbBoundedMoney(10,60.93)!=10)failed++;
   checks++;if(OrbBoundedMoney(10,0)!=0)failed++;
   g_orbStrategyTimezone=5.75;
   checks++;if(OrbBrokerOffsetHours()!=5.75)failed++;
   g_orbStrategyTimezone=0;
   checks++;if(OrbBrokerOffsetHours()!=0)failed++;
   for(datetime t=D'2016.01.01';t<D'2027.01.01';t+=86400)
   {
      checks++;if(OrbUtcToServer(t)!=t||OrbServerToUtc(t)!=t)failed++;
      for(int profile=2;profile<=10;profile++)
      {
         datetime u=t+12*3600;
         int off=OrbClockOffsetAtUtc((ORB_BROKER_CLOCK_PROFILE)profile,ORB_SEASON_AUTO,u,0);
         checks++;if(OrbClockServerToUtc((ORB_BROKER_CLOCK_PROFILE)profile,ORB_SEASON_AUTO,u+off,0)!=u)failed++;
      }
   }
   datetime times[]={D'2026.03.08 06:59:59',D'2026.03.08 07:00:00',D'2026.11.01 05:59:59',D'2026.11.01 06:00:00'};
   int ny[]={-18000,-14400,-14400,-18000};
   for(int i=0;i<4;i++){checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_NEW_YORK,ORB_SEASON_AUTO,times[i],0)!=ny[i])failed++;}
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_NY_CLOSE,ORB_SEASON_AUTO,D'2026.07.01',0)!=10800)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_NY_CLOSE,ORB_SEASON_AUTO,D'2026.01.01',0)!=7200)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_CENTRAL_EUROPE,ORB_SEASON_AUTO,D'2026.03.29 00:59:59',0)!=3600)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_CENTRAL_EUROPE,ORB_SEASON_AUTO,D'2026.03.29 01:00:00',0)!=7200)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_SYDNEY,ORB_SEASON_AUTO,D'2026.01.01',0)!=39600)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_SYDNEY,ORB_SEASON_AUTO,D'2026.07.01',0)!=36000)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_AUCKLAND,ORB_SEASON_AUTO,D'2026.01.01',0)!=46800)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_AUCKLAND,ORB_SEASON_AUTO,D'2026.07.01',0)!=43200)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_NEW_YORK,ORB_SEASON_STANDARD,D'2026.07.01',0)!=-18000)failed++;
   checks++;if(OrbClockOffsetAtUtc(ORB_CLOCK_NEW_YORK,ORB_SEASON_DAYLIGHT,D'2026.01.01',0)!=-14400)failed++;
   checks++;if(OrbClockServerToUtc(ORB_CLOCK_NEW_YORK,ORB_SEASON_AUTO,D'2026.03.08 02:30',0)!=0)failed++;
   checks++;if(OrbClockServerToUtc(ORB_CLOCK_NEW_YORK,ORB_SEASON_AUTO,D'2026.11.01 01:30',0)!=D'2026.11.01 06:30')failed++;
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+"}";
   int f=FileOpen("OrbBrokerTimezoneProbe_20260919_140916.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}
   Print(result);
}
