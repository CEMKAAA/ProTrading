#define OnStart OriginalCampaignOnStart
#include "StrategyWindows_orb.mq5"
#undef OnStart
void OnStart()
{
 OriginalCampaignOnStart();
 int f=FileOpen("AuditIncompleteReasonProbe.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
 if(f==INVALID_HANDLE)return;
 FileWrite(f,"signal","valid","reason","entry","tp","outcome");
 for(int i=0;i<ArraySize(g_axTrades);i++)
  FileWrite(f,(long)g_axTrades[i].signalTime,g_axTrades[i].valid?1:0,g_axTrades[i].reason,
   DoubleToString(g_axTrades[i].entry,12),DoubleToString(g_axTrades[i].tp,12),g_axTrades[i].outcome);
 FileClose(f);
 Print("INCOMPLETE_REASON_PROBE records=",ArraySize(g_axTrades)," order_attempts=",g_campaignOrderAttempts);
}
