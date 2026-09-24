#property strict
#define OnInit CampaignInit
#define OnDeinit CampaignDeinit
#define OnTick CampaignTick
#define OnTimer CampaignTimer
#define OnChartEvent CampaignEvent
#define OnTradeTransaction CampaignTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction

// Research-only application avoids the production runtime's FILE_COMMON write.
bool CampaignApply(string path)
{
   string name="";double values[];
   if(!LiqLibraryUnpack(path,name,values))return false;
   LnNasPolicy policy;LnNasDefaults(policy);
   double customR=0.0;
   string calendarText=TCalStrategyOffText();
   string imageName="";double imageValues[];
   if(!LiqImageRead(path,imageName,imageValues))
   {
      string record="",lines[];
      if(!LiqLibraryRead(path,record))return false;
      int end=StringFind(record,"\nSHA256=");
      if(end<0)return false;
      int count=StringSplit(StringSubstr(record,0,end),'\n',lines);
      if(count<1)return false;
      int policyIndex=6+ArraySize(values);
      string version=lines[0];
      if(version!="LIQ_STRATEGY_V1")
      {
         if(count<=policyIndex||!LnNasUnpack(lines[policyIndex],policy))return false;
         if(version=="LIQ_STRATEGY_NAS_CUSTOM_R_V1"
            ||version=="LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1")
         {
            if(!LiqLibraryCustomR(lines[policyIndex+1],customR))return false;
         }
         if(version=="LIQ_STRATEGY_NAS_TCAL_V1"
            ||version=="LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1")calendarText=lines[count-1];
      }
   }
   bool enabled=false;int hours[];
   if(!TCalStrategyRead(calendarText,enabled,hours))return false;
   g_tcalEnabled=enabled;
   for(int day=0;day<7;day++)g_tcalDayHours[day]=hours[day];
   g_lnNas=policy;LnNasInvalidate();
   LiqLibraryAssign(values);g_customTargetR=customR;g_histWeeks=260;
   NormalizeEntryModelStrictness();SanitizeHalfMode();
   RecalculateHistoricalStats(false);
   return true;
}

void OnStart()
{
   int summary=FileOpen("LiqSolAdvancedFiveYearSummary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   int trades=FileOpen("LiqSolAdvancedFiveYearTrades.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   int selected=FileOpen("LiqSolAdvancedTimeMatrixSummary.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(summary==INVALID_HANDLE||trades==INVALID_HANDLE||selected==INVALID_HANDLE)
   {
      if(summary!=INVALID_HANDLE)FileClose(summary);
      if(trades!=INVALID_HANDLE)FileClose(trades);
      if(selected!=INVALID_HANDLE)FileClose(selected);
      Print("Five-year campaign output unavailable");
      return;
   }
   FileWrite(summary,"strategy","path","symbol","weeks","signals","total","wins","losses","open","invalid","net_r","status");
   FileWrite(trades,"strategy","path","symbol","available_time","net_r","closed","valid","exit_time","exit_reason");
   FileWrite(selected,"strategy","path","symbol","target_r","minimum_wr_percent","minimum_train_samples",
      "training_end_broker","picked_hours","masks_sun_to_sat","train_base_w","train_base_l",
      "five_year_total","five_year_w","five_year_l","five_year_open","five_year_invalid","five_year_net_r",
      "oos_two_year_n","oos_two_year_w","oos_two_year_l","oos_two_year_net_r","status");
   if(CampaignInit()!=INIT_SUCCEEDED)
   {
      FileWrite(summary,"","",_Symbol,260,0,0,0,0,0,0,0,"INIT_FAILED");
      FileClose(summary);FileClose(trades);FileClose(selected);return;
   }
   g_histWeeks=260;
   g_liqLibraryFavorites=false;g_liqLibraryQuery="";
   LiqLibraryScan();
   int count=ArraySize(g_liqLibraryFiles);
   string paths[],names[];ArrayCopy(paths,g_liqLibraryFiles);ArrayCopy(names,g_liqLibraryNames);
   for(int slot=0;slot<count;slot++)
   {
      string path=paths[slot],name=names[slot];
      if(!CampaignApply(path))
      {
         FileWrite(summary,name,path,_Symbol,260,0,0,0,0,0,0,0,"APPLY_FAILED");
         continue;
      }
      int signals=ArraySize(g_histSignals);
      datetime cutoff=TimeCurrent()-260*7*86400;
      datetime firstEntry=(datetime)SeriesInfoInteger(_Symbol,g_entryTf,SERIES_FIRSTDATE);
      datetime firstHtf=(datetime)SeriesInfoInteger(_Symbol,g_htf,SERIES_FIRSTDATE);
      datetime firstM1=(datetime)SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_FIRSTDATE);
      bool coverage=(firstEntry>0&&firstEntry<=cutoff&&firstHtf>0&&firstHtf<=cutoff
         &&firstM1>0&&firstM1<=cutoff);
      string auditStatus=!coverage?"COVERAGE_SHORT":(g_hist.invalid>0?"INCOMPLETE":(g_hist.open>0?"AUDITED_OPEN":"AUDITED"));
      FileWrite(summary,name,path,_Symbol,g_histWeeks,signals,g_hist.total,g_hist.wins,g_hist.losses,
         g_hist.open,g_hist.invalid,DoubleToString(g_hist.netR,12),auditStatus);
      for(int i=0;i<signals;i++)
      {
         FileWrite(trades,name,path,_Symbol,(long)g_histSignals[i].availableTime,
            DoubleToString(g_histSignalR[i],12),g_histSignalClosed[i]?1:0,g_histSignalValid[i]?1:0,
            (long)g_histSignalExitTime[i],g_histSignalExitReason[i]);
      }
      if(auditStatus!="AUDITED"&&auditStatus!="AUDITED_OPEN")
      {
         FileWrite(selected,name,path,_Symbol,DoubleToString(TargetR(g_target),8),0,10,0,0,"",0,0,
            g_hist.total,g_hist.wins,g_hist.losses,g_hist.open,g_hist.invalid,
            DoubleToString(g_hist.netR,12),0,0,0,0,auditStatus);
         FileFlush(summary);FileFlush(trades);FileFlush(selected);
         continue;
      }
      datetime trainingEnd=TimeCurrent()-104*7*86400;
      int trainW[7][24],trainL[7][24],originalMasks[7];
      ArrayInitialize(trainW,0);ArrayInitialize(trainL,0);
      bool originalEnabled=g_tcalEnabled;
      for(int day=0;day<7;day++)originalMasks[day]=g_tcalDayHours[day];
      int baseW=0,baseL=0;
      for(int i=0;i<signals;i++)
      {
         if(g_histSignals[i].availableTime>=trainingEnd||!g_histSignalValid[i]||!g_histSignalClosed[i])continue;
         MqlDateTime stamp;TimeToStruct(g_histSignals[i].availableTime,stamp);
         if(stamp.day_of_week<0||stamp.day_of_week>6||stamp.hour<0||stamp.hour>23)continue;
         if(g_histSignalR[i]>1e-8){trainW[stamp.day_of_week][stamp.hour]++;baseW++;}
         else if(g_histSignalR[i]<-1e-8){trainL[stamp.day_of_week][stamp.hour]++;baseL++;}
      }
      double targetR=TargetR(g_target);
      int minimumWr=targetR>0?(int)MathCeil(100.0/(1.0+targetR)-1e-9):101;
      int picked=0;string maskText="";
      for(int day=0;day<7;day++)
      {
         int mask=0;
         for(int hour=0;hour<24;hour++)
         {
            int n=trainW[day][hour]+trainL[day][hour];
            if(n>=10&&100.0*trainW[day][hour]/n+1e-9>=minimumWr)mask|=1<<hour;
         }
         if(originalEnabled)mask&=originalMasks[day];
         g_tcalDayHours[day]=mask;
         if(day>0)maskText+="|";
         maskText+=(string)mask;
         for(int hour=0;hour<24;hour++)if((mask&(1<<hour))!=0)picked++;
      }
      if(picked==0)
      {
         FileWrite(selected,name,path,_Symbol,DoubleToString(targetR,8),minimumWr,10,(long)trainingEnd,
            picked,maskText,baseW,baseL,0,0,0,0,0,0,0,0,0,0,"NO_TRAINING_PICKS");
      }
      else
      {
         g_tcalEnabled=true;
         RecalculateHistoricalStats(false);
         int oosN=0,oosW=0,oosL=0;double oosR=0;
         for(int i=0;i<ArraySize(g_histSignals);i++)
         {
            if(g_histSignals[i].availableTime<trainingEnd||!g_histSignalValid[i]||!g_histSignalClosed[i])continue;
            oosN++;oosR+=g_histSignalR[i];
            if(g_histSignalR[i]>1e-8)oosW++;else if(g_histSignalR[i]<-1e-8)oosL++;
         }
         string status=(g_hist.invalid==0&&g_hist.open==0&&g_hist.netR>0&&oosR>0&&oosN>=30)
            ?"TRUE_WINNER_CANDIDATE":(g_hist.open>0?"OPEN_EXPOSURE":"NOT_CONFIRMED");
         FileWrite(selected,name,path,_Symbol,DoubleToString(targetR,8),minimumWr,10,(long)trainingEnd,
            picked,maskText,baseW,baseL,g_hist.total,g_hist.wins,g_hist.losses,g_hist.open,g_hist.invalid,
            DoubleToString(g_hist.netR,12),oosN,oosW,oosL,DoubleToString(oosR,12),status);
      }
      g_tcalEnabled=originalEnabled;
      for(int day=0;day<7;day++)g_tcalDayHours[day]=originalMasks[day];
      FileFlush(summary);FileFlush(trades);
      FileFlush(selected);
   }
   FileClose(summary);FileClose(trades);FileClose(selected);
   CampaignDeinit(0);
}
