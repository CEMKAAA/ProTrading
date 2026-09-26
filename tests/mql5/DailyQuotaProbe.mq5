#property strict
#include "../../IndicatorCodeExamples/orb/TradeCalendarMatrix.mqh"
int checks=0,failed=0;
void Check(bool ok,string label){checks++;if(!ok){failed++;Print("DAILY_FAIL ",label);}}
void OnStart()
{
   Check(TCalInit(),"initialize");
   string old=TCalStrategyOffText();
   Check(TCalStrategyApplyText(old+",0,2,1"),"configure limits");
   string saved=TCalStrategyText();
   Check(TCalStrategyApplyText(old)&&!DailyQuotaEnabled(),"older strategy resets limits");
   Check(TCalStrategyApplyText(saved)&&g_dailyMaxLosses==2&&g_dailyTargetWins==1,"restore limits");
   Check(TCalInit()&&g_dailyMaxLosses==2&&g_dailyTargetWins==1,"restart restores limits");
   Check(TCalStrategyApplyText(old+",0,2,1,360")&&g_dailyStartMinute==360,"save configurable day start");
   Check(TCalInit()&&g_dailyStartMinute==360,"restart restores day start");
   Check(DailyQuotaDay(D'2026.09.22 05:59')==D'2026.09.21 06:00',"before reset belongs to preceding quota day");
   Check(DailyQuotaDay(D'2026.09.22 06:00')==D'2026.09.22 06:00',"exact reset starts new quota day");
   TCalReset();DailyQuotaSchedule(D'2026.09.22 05:30',1);
   Check(!DailyQuotaAuditAllows(D'2026.09.22 05:45'),"limit remains active through midnight until selected start");
   Check(DailyQuotaAuditAllows(D'2026.09.22 06:00'),"limit resets at selected start");
   Check(TCalStrategyApplyText(old+",0,2,1")&&g_dailyStartMinute==0,"old 11-field strategy restores midnight");
   datetime day=D'2026.09.21 00:00';
   TCalReset();
   Check(DailyQuotaAuditAllows(day+60),"first entry");
   DailyQuotaSchedule(day+1800,1);
   Check(DailyQuotaAuditAllows(day+1200),"future win cannot block earlier entry");
   DailyQuotaSchedule(day+2400,-1);
   Check(!DailyQuotaAuditAllows(day+1800),"win target blocks at actual close");
   Check(!DailyQuotaAuditAllows(day+3600),"blocked remainder of day");
   Check(DailyQuotaAuditAllows(day+86400),"midnight resets quota");
   g_dailyTargetWins=0;g_dailyMaxLosses=2;TCalReset();
   Check(DailyQuotaAuditAllows(day+60),"loss scenario first entry");
   DailyQuotaSchedule(day+100,-1);DailyQuotaSchedule(day+200,-1);
   Check(DailyQuotaAuditAllows(day+150)&&g_dailyAuditLosses==1,"one loss under threshold");
   Check(!DailyQuotaAuditAllows(day+200)&&g_dailyAuditLosses==2,"second loss blocks");
   TCalReset();DailyQuotaSchedule(day+86400+100,-1);
   Check(DailyQuotaAuditAllows(day+86400+50)&&g_dailyAuditLosses==0,"overnight exit not known before close");
   Check(DailyQuotaAuditAllows(day+86400+100)&&g_dailyAuditLosses==1,"overnight counts on close day");
   TCalReset();DailyQuotaSchedule(day+100,-1);DailyQuotaSchedule(day+200,0);
   Check(DailyQuotaAuditAllows(day+300)&&g_dailyAuditLosses==1&&g_dailyAuditWins==0,"flat ignored");
   TCalReset();DailyQuotaSchedule(day+200,-1);DailyQuotaSchedule(day+100,-1);
   Check(DailyQuotaAuditAllows(day+150)&&g_dailyAuditLosses==1,"heap handles overlapping exits");
   Check(!DailyQuotaAuditAllows(day+250),"heap second terminal outcome blocks");
   Check(!DailyQuotaAuditAllows(day+100)&&!g_dailyAuditValid,"unordered entries fail closed");
   TCalReset();DailyQuotaSchedule(0,1);
   Check(!DailyQuotaAuditAllows(day+100),"missing exact close timestamp fail closed");
   g_dailyMaxLosses=0;g_dailyTargetWins=0;TCalReset();
   Check(DailyQuotaAuditAllows(0)&&DailyQuotaAuditAllows(day),"disabled parity no ordering constraint");
   int n=0;Check(!DailyQuotaParse("-1",n)&&!DailyQuotaParse("1.5",n)&&!DailyQuotaParse("100001",n),"invalid edit rejected");
   Check(DailyQuotaParse(" 2 ",n)&&n==2,"current edit parse");
   g_dailyTargetWins=1;TCalReset();
   // Causal integration: only admitted entries contribute to Time Matrix.
   int admitted=0;
   for(int i=0;i<4;i++)
   {
      datetime entry=day+60+i*3600;
      if(!DailyQuotaAuditAllows(entry))continue;
      admitted++;DailyQuotaSchedule(entry+60,1);TCalRecordOutcome(entry,true);
   }
   Check(admitted==1&&g_tcalWins[1][0]==1&&g_tcalWins[1][1]==0,"daily cap excludes later Time Matrix buckets");
   g_tcalPrefix="DAILY_PROBE_TCAL_";DailyQuotaDraftReset();DailyQuotaLauncher("DAILY_PROBE_",10,10);
   ObjectSetString(0,TCalId("DAILY_LOSS"),OBJPROP_TEXT,"3");
   ObjectSetString(0,TCalId("DAILY_WIN"),OBJPROP_TEXT,"4");
   ObjectSetString(0,TCalId("DAILY_START"),OBJPROP_TEXT,"17:30");
   Check(TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("DAILY_APPLY"))&&g_dailyMaxLosses==3&&g_dailyTargetWins==4&&g_tcalChanged,"Apply reads current object values and invalidates audit");
   Check(g_dailyStartMinute==1050,"Apply reads current START value");
   Check(!DailyQuotaParseClock("24:00",n)&&!DailyQuotaParseClock("12:60",n)&&!DailyQuotaParseClock("6:00",n),"invalid clock rejected");
   g_tcalOpen=true;ObjectSetString(0,TCalId("DAILY_WIN"),OBJPROP_TEXT,"7");
   Check(TCalEvent(CHARTEVENT_OBJECT_CLICK,0,0,TCalId("DAILY_APPLY"))&&g_dailyTargetWins==4,"modal prevents click-through");
   g_tcalOpen=false;TCalDestroy();Check(TCalStrategyApplyText(old),"restore defaults");
   int file=FileOpen("DailyQuotaProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(file!=INVALID_HANDLE){FileWriteString(file,StringFormat("{\"checks\":%d,\"failed\":%d}",checks,failed));FileClose(file);}
   Print("DAILY_QUOTA ",checks," checks ",failed," failed");
}
