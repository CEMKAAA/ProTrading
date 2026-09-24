#property strict
struct CampaignTrade
{
   datetime sessionTime,entryTime;
   bool valid,closed;
   double netR;
};
CampaignTrade g_campaignTrades[];
string g_campaignStrategyId="";
int g_campaignTradeHandle=INVALID_HANDLE;
bool g_campaignExportBase=true;
void CampaignRecord(datetime sessionTime,datetime entryTime,bool valid,bool closed,double netR,string outcome);
#define OnInit CampaignInit
#define OnDeinit CampaignDeinit
#define OnTick CampaignTick
#define OnTimer CampaignTimer
#define OnChartEvent CampaignEvent
#define OnTradeTransaction CampaignTransaction
#include "../../tmp/orb_5y_campaign_source/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

void CampaignRecord(datetime sessionTime,datetime entryTime,bool valid,bool closed,double netR,string outcome)
{
   int at=ArraySize(g_campaignTrades);ArrayResize(g_campaignTrades,at+1,2048);
   g_campaignTrades[at].sessionTime=sessionTime;g_campaignTrades[at].entryTime=entryTime;
   g_campaignTrades[at].valid=valid;g_campaignTrades[at].closed=closed;g_campaignTrades[at].netR=netR;
   if(g_campaignExportBase&&g_campaignTradeHandle!=INVALID_HANDLE)
      FileWrite(g_campaignTradeHandle,g_campaignStrategyId,(long)sessionTime,(long)entryTime,
         valid?1:0,closed?1:0,DoubleToString(netR,12),outcome);
}

void CampaignAudit()
{
   g_histNeedsRedraw=true;g_lastHistBuild=0;
   DrawHistoricalSignals();
   ulong syncStarted=GetTickCount64();
   while(g_histCoveragePending&&!g_histCoverageHardBlocked&&GetTickCount64()-syncStarted<120000)
   {
      Sleep(1000);g_histCoverageAttempts=0;g_histNeedsRedraw=true;
      DrawHistoricalSignals();
   }
   ulong began=GetTickCount64();
   while(g_histAuditRunning&&GetTickCount64()-began<300000)
   {ProcessHistoricalAuditStep();Sleep(5);}
}

void OnStart()
{
   int startSlot=0;
   int checkpoint=FileOpen("OrbCampaignStartSlot.txt",FILE_READ|FILE_TXT|FILE_ANSI);
   if(checkpoint!=INVALID_HANDLE)
   {
      startSlot=(int)StringToInteger(FileReadString(checkpoint));
      FileClose(checkpoint);
   }
   if(startSlot<0)startSlot=0;
   int summary=FileOpen("OrbCurrentUserFiveYearSummary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   int selected=FileOpen("OrbCurrentUserFiveYearTimeMatrix.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   g_campaignTradeHandle=FileOpen("OrbCurrentUserFiveYearTrades.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(summary==INVALID_HANDLE||selected==INVALID_HANDLE||g_campaignTradeHandle==INVALID_HANDLE)
   {
      if(summary!=INVALID_HANDLE)FileClose(summary);
      if(selected!=INVALID_HANDLE)FileClose(selected);
      if(g_campaignTradeHandle!=INVALID_HANDLE)FileClose(g_campaignTradeHandle);
      return;
   }
   FileWrite(summary,"slot","strategy_id","name","symbol","weeks","total","wins","losses","open","flat","invalid",
      "net_r","max_peak_dd_r","status");
   FileWrite(selected,"slot","strategy_id","name","symbol","target_r","minimum_wr_percent","minimum_train_samples",
      "audit_end","training_end","picked_hours","masks_sun_to_sat","train_base_w","train_base_l",
      "five_year_total","five_year_w","five_year_l","five_year_open","five_year_invalid","five_year_net_r",
      "oos_two_year_n","oos_two_year_w","oos_two_year_l","oos_two_year_net_r","status");
   FileWrite(g_campaignTradeHandle,"strategy_id","time_matrix_time","entry_time","valid","closed","net_r","outcome");
   if(CampaignInit()!=INIT_SUCCEEDED)
   {
      FileWrite(summary,-1,"","",_Symbol,260,0,0,0,0,0,0,0,0,0,"INIT_FAILED");
      FileClose(summary);FileClose(selected);FileClose(g_campaignTradeHandle);return;
   }
   g_orbBridgeEnabled=false;g_mlEnabled=false;
   OrbUserReload(true);
   int count=OrbStrategyPresetCount();
   for(int slot=startSlot;slot<count;slot++)
   {
      OrbStrategyPreset preset;
      if(!OrbStrategyPresetLoad(slot,preset)||!OrbStrategyPresetFamilyMatches(preset.family))continue;
      g_campaignStrategyId=preset.id;g_campaignExportBase=true;
      ArrayResize(g_campaignTrades,0);
      if(!OrbStrategyPresetApplyValues(preset))
      {
         FileWrite(summary,slot,g_campaignStrategyId,preset.name,_Symbol,260,0,0,0,0,0,0,0,0,"APPLY_FAILED");
         continue;
      }
      SetHistoricalWeeks(260);
      CampaignAudit();
      string status="AUDITED";
      datetime cutoff=TimeCurrent()-260*7*86400;
      datetime firstSignal=(datetime)SeriesInfoInteger(_Symbol,g_rtSignalTf,SERIES_FIRSTDATE);
      datetime firstM1=(datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE);
      if(g_histAuditRunning){CancelHistoricalAuditBuild();status="TIMEOUT";}
      else if(g_histCoverageHardBlocked||g_histCoveragePending)status="DATA_UNAVAILABLE";
      else if(firstSignal<=0||firstSignal>cutoff||firstM1<=0||firstM1>cutoff)status="COVERAGE_SHORT";
      else if(g_histRunDays!=1820||g_histInvalid>0)status="INCOMPLETE";
      else if(g_histOpen>0)status="AUDITED_OPEN";
      FileWrite(summary,slot,g_campaignStrategyId,preset.name,_Symbol,g_rtHistoricalWeeks,
         g_histTotal,g_histWins,g_histLosses,g_histOpen,g_histFlat,g_histInvalid,
         DoubleToString(g_histNetR,12),DoubleToString(g_histMaxPeakDrawdownR,12),status);
      if(status=="AUDITED"||status=="AUDITED_OPEN")
      {
         datetime auditEnd=g_histRunNow,trainingEnd=auditEnd-104*7*86400;
         int wins[7][24],losses[7][24],originalHours[7];
         ArrayInitialize(wins,0);ArrayInitialize(losses,0);
         bool originalEnabled=g_tcalEnabled;
         int baseW=0,baseL=0,picked=0;
         for(int day=0;day<7;day++)originalHours[day]=g_tcalDayHours[day];
         for(int t=0;t<ArraySize(g_campaignTrades);t++)
         {
            CampaignTrade item=g_campaignTrades[t];
            if(!item.valid||!item.closed||item.sessionTime>=trainingEnd)continue;
            MqlDateTime stamp;TimeToStruct(item.sessionTime,stamp);
            if(stamp.day_of_week<0||stamp.day_of_week>6||stamp.hour<0||stamp.hour>23)continue;
            if(item.netR>1e-8){wins[stamp.day_of_week][stamp.hour]++;baseW++;}
            else if(item.netR<-1e-8){losses[stamp.day_of_week][stamp.hour]++;baseL++;}
         }
         double targetR=RuntimeEffectiveTargetR();
         int minimumWr=targetR>0?(int)MathCeil(100.0/(1.0+targetR)-1e-9):101;
         string masks="";
         for(int day=0;day<7;day++)
         {
            int mask=0;
            for(int hour=0;hour<24;hour++)
            {
               int n=wins[day][hour]+losses[day][hour];
               if(n>=10&&100.0*wins[day][hour]/n+1e-9>=minimumWr)mask|=1<<hour;
            }
            if(originalEnabled)mask&=originalHours[day];
            g_tcalDayHours[day]=mask;
            if(day>0)masks+="|";masks+=(string)mask;
            for(int hour=0;hour<24;hour++)if((mask&(1<<hour))!=0)picked++;
         }
         string selectedStatus="NO_TRAINING_PICKS";
         int oosN=0,oosW=0,oosL=0;double oosR=0;
         if(picked>0)
         {
            g_tcalEnabled=true;g_campaignExportBase=false;ArrayResize(g_campaignTrades,0);
            CampaignAudit();
            if(g_histAuditRunning){CancelHistoricalAuditBuild();selectedStatus="TIMEOUT";}
            else if(g_histCoveragePending||g_histCoverageHardBlocked)selectedStatus="DATA_UNAVAILABLE";
            else
            {
               for(int t=0;t<ArraySize(g_campaignTrades);t++)
               {
                  CampaignTrade item=g_campaignTrades[t];
                  if(item.sessionTime<trainingEnd||!item.valid||!item.closed)continue;
                  oosN++;oosR+=item.netR;
                  if(item.netR>1e-8)oosW++;else if(item.netR<-1e-8)oosL++;
               }
               selectedStatus=(g_histRunDays==1820&&g_histInvalid==0&&g_histOpen==0&&g_histNetR>0&&oosR>0&&oosN>=30)
                  ?"TRUE_WINNER_CANDIDATE":(g_histOpen>0?"OPEN_EXPOSURE":"NOT_CONFIRMED");
            }
         }
         FileWrite(selected,slot,g_campaignStrategyId,preset.name,_Symbol,DoubleToString(targetR,8),minimumWr,10,
            (long)auditEnd,(long)trainingEnd,picked,masks,baseW,baseL,g_histTotal,g_histWins,g_histLosses,
            g_histOpen,g_histInvalid,DoubleToString(g_histNetR,12),oosN,oosW,oosL,DoubleToString(oosR,12),selectedStatus);
         g_tcalEnabled=originalEnabled;
         for(int day=0;day<7;day++)g_tcalDayHours[day]=originalHours[day];
      }
      FileFlush(summary);FileFlush(selected);FileFlush(g_campaignTradeHandle);
   }
   FileClose(summary);FileClose(selected);FileClose(g_campaignTradeHandle);g_campaignTradeHandle=INVALID_HANDLE;
   CampaignDeinit(0);
}
