#property strict

// Research script: the original engine is included, never a second simulator.
int g_campaignOrderAttempts=0;
bool g_campaignAllowMetricWrites=false;
input datetime CampaignAsOf=0;
datetime CampaignNow(){return CampaignAsOf>0?CampaignAsOf:TimeCurrent();}
datetime CampaignNow(MqlDateTime &value){datetime now=CampaignNow();TimeToStruct(now,value);return now;}
void CampaignNoop(){}
bool CampaignOrderSend(const MqlTradeRequest &request,MqlTradeResult &result)
{g_campaignOrderAttempts++;ZeroMemory(result);result.retcode=TRADE_RETCODE_TRADE_DISABLED;return false;}
bool CampaignOrderSendAsync(const MqlTradeRequest &request,MqlTradeResult &result)
{return CampaignOrderSend(request,result);}
int CampaignFileOpen(string path,int flags,short delimiter='\t',uint codepage=CP_ACP)
{
   // Shared libraries may be read; only validated window metrics may be written.
   if((flags&FILE_COMMON)!=0&&(flags&FILE_WRITE)!=0
      &&(!g_campaignAllowMetricWrites||StringFind(path,"\\WindowMetrics\\")<0))return INVALID_HANDLE;
   return FileOpen(path,flags,delimiter,codepage);
}
#define OrderSend CampaignOrderSend
#define OrderSendAsync CampaignOrderSendAsync
#define FileOpen CampaignFileOpen
#define TimeCurrent CampaignNow
#define OnInit CampaignInit
#define OnDeinit CampaignDeinit
#define OnTick CampaignTick
#define OnTimer CampaignTimer
#define OnChartEvent CampaignEvent
#define OnTradeTransaction CampaignTransaction
#define CAMPAIGN_MA
#define CAMPAIGN_SOURCE_HASH "be6a04ce44dbed0ace9dc0f10f9aefe3aa643f2657efd24c45ce3424e6d5175a"
#define CAMPAIGN_TEMPLATE_HASH "069e9c0577c6d9c7d01e4954795a248ed828ae248ba2ebcf93f20c99255fb388"
#define CAMPAIGN_GENERATOR_HASH "9bf354fdc6b14ac845c002942f3aa62e96206a3b12a95d2f7cb774196da771ff"
#include "MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef FileOpen
#undef TimeCurrent
#undef OrderSend
#undef OrderSendAsync

input string CampaignOrigin="";
input string CampaignId="";
input string CampaignProfileSignature="";
input string CampaignWeeks="260,208,156,104,52,20,10,5,2";
input int CampaignSyncSeconds=180;
input int CampaignAuditSeconds=1800;
input bool CampaignDashboardLoad=false;
input bool CampaignPublishMetrics=false;
input bool CampaignTraceTrades=false;
input string CampaignBroker="";
string g_campaignNativeId="",g_campaignName="",g_campaignKey="",g_campaignFolder="";
string g_campaignCalendar="";
bool g_campaignIndependent=false;
bool CampaignPrepareMacro()
{
   if(!InpRegimeV3Observer)return true;
   ulong started=GetTickCount64();string previous="";
   while(!IsStopped()&&GetTickCount64()-started<(ulong)CampaignSyncSeconds*1000)
   {
      MqlRates d[],h1[],h2[],h4[];string reason="";
      if(RegimeV3LoadRates(d,h1,h2,h4,reason)
         &&SeriesInfoInteger(_Symbol,PERIOD_D1,SERIES_SYNCHRONIZED)
         &&SeriesInfoInteger(_Symbol,PERIOD_H1,SERIES_SYNCHRONIZED)
         &&SeriesInfoInteger(_Symbol,PERIOD_H2,SERIES_SYNCHRONIZED)
         &&SeriesInfoInteger(_Symbol,PERIOD_H4,SERIES_SYNCHRONIZED))
      {
         string stamp=(string)ArraySize(d)+"|"+(string)d[0].time+"|"+(string)ArraySize(h1)+"|"+(string)h1[0].time
            +"|"+(string)ArraySize(h2)+"|"+(string)h2[0].time+"|"+(string)ArraySize(h4)+"|"+(string)h4[0].time;
         if(stamp==previous&&RegimeV3EnsureTimeline(true))return true;
         previous=stamp;
      }
      else previous="";
      Sleep(500);
   }
   return false;
}
string CampaignCsvCell(string value)
{StringReplace(value,"\"","\"\"");return "\""+value+"\"";}
void CampaignTradeTrace(int weeks)
{
   if(!CampaignTraceTrades)return;
   string path="Trace_"+CampaignId+"_"+(string)weeks+"_"+(CampaignDashboardLoad?"dashboard":"campaign")+".csv";
   int f=FileOpen(path,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);if(f==INVALID_HANDLE)return;
   FileWrite(f,"signal","entry_time","exit_time","direction","entry","sl","tp","net_r","cost_r","closed","valid","outcome");
   for(int i=0;i<ArraySize(g_axTrades);i++)
   {
      AxTrade t=g_axTrades[i];
      FileWrite(f,(long)t.signalTime,(long)t.entryTime,(long)t.exitTime,t.direction,
         DoubleToString(t.entry,12),DoubleToString(t.sl,12),DoubleToString(t.tp,12),DoubleToString(t.netR,12),
         DoubleToString(t.costR,12),t.closed?1:0,t.valid?1:0,CampaignCsvCell(t.outcome));
   }
   FileClose(f);
}

bool CampaignCalendar(string text)
{
   bool enabled=false;int hours[];
   if(!TCalStrategyRead(text,enabled,hours))return false;
   int loss=0,win=0,start=0;
   if(!DailyQuotaReadStrategy(text,loss,win,start))return false;
   g_entryDirection=DirectionStrategyMode(text);
   g_dailyMaxLosses=loss;g_dailyTargetWins=win;g_dailyStartMinute=start;
   g_tcalEnabled=enabled;
   for(int day=0;day<7;day++)g_tcalDayHours[day]=hours[day];
   g_campaignCalendar=text;
   return TCalStrategyMatchesText(text);
}

#ifdef CAMPAIGN_SOL
bool CampaignApply()
{
   string path=CampaignOrigin;
   if(StringFind(path,"image:")==0)
   {
      string imageName=StringSubstr(path,6);path="";
      for(int i=0;i<ArraySize(g_liqImagePresets);i++)
         if(LiqImageCompatible(i)&&g_liqImagePresets[i].name==imageName){path=LiqImagePath(i);break;}
      if(path=="")return false;
   }
   StringReplace(path,"/","\\");
   double values[];
   // The host already recovered a checksum-matching original input profile.
   if(!LiqLibraryUnpack(path,g_campaignName,values,false))return false;
   LnNasPolicy policy;LnNasDefaults(policy);
   double customR=0;string calendar=TCalStrategyOffText();
   if(StringFind(CampaignOrigin,"image:")!=0)
   {
      string record="",lines[];
      if(!LiqLibraryRead(path,record))return false;
      int end=StringFind(record,"\nSHA256=");if(end<0)return false;
      int n=StringSplit(StringSubstr(record,0,end),'\n',lines),at=6+(int)StringToInteger(lines[5]);
      if(lines[0]!="LIQ_STRATEGY_V1")
      {
         if(n<=at||!LnNasUnpack(lines[at],policy))return false;
         if(lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_V1"||lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1")
            if(n<=at+1||!LiqLibraryCustomR(lines[at+1],customR))return false;
         if(lines[0]=="LIQ_STRATEGY_NAS_TCAL_V1"||lines[0]=="LIQ_STRATEGY_NAS_CUSTOM_R_TCAL_V1")calendar=lines[n-1];
      }
   }
   if(!CampaignCalendar(calendar))return false;
   LiqLibraryAssign(values);g_lnNas=policy;LnNasInvalidate();g_customTargetR=customR;
   NormalizeEntryModelStrictness();SanitizeHalfMode();
   if(CampaignDashboardLoad&&!LiqLibraryApply(path))return false;
   if(!TCalStrategyMatchesText(calendar))return false;
   g_fileBridgeEnabled=false;g_nativeTradeWithBridgeOnly=false;g_eaEnabled=false;
   g_campaignNativeId=path;g_campaignIndependent=policy.independent;
   g_campaignFolder=LiqWindowFolder();g_campaignKey=LiqWindowKey(path);
   // Disable the automatic selection writer; this script commits exact record keys.
   g_liqLibrarySelected="";g_liqWindowAppliedFingerprint="";
   return g_campaignKey!="";
}
bool CampaignCoverage(int weeks)
{
   datetime cutoff=CampaignNow()-weeks*7*86400;
   ENUM_TIMEFRAMES htf=g_htf;
   if((int)htf==90)htf=PERIOD_M30; // H90 is synthetic, not an MT5-native series.
   return SeriesInfoInteger(_Symbol,g_entryTf,SERIES_FIRSTDATE)>0
      &&SeriesInfoInteger(_Symbol,g_entryTf,SERIES_FIRSTDATE)<=cutoff
      &&SeriesInfoInteger(_Symbol,htf,SERIES_FIRSTDATE)>0
      &&SeriesInfoInteger(_Symbol,htf,SERIES_FIRSTDATE)<=cutoff;
}
void CampaignRun(int weeks)
{g_histWeeks=weeks;RecalculateHistoricalStats(false);}
#else
bool CampaignApply()
{
   g_orbBridgeEnabled=false;g_rtEaEnabled=false;g_mlEnabled=false;
   CancelHistoricalAuditBuild();OrbUserReload(true);
   OrbStrategyPreset p;
   if(StringFind(CampaignOrigin,"builtin:")==0)
   {
#ifdef CAMPAIGN_ORB
      string id=StringSubstr(CampaignOrigin,8);bool found=false;
      for(int i=0;i<OrbBuiltinStrategyPresetCount();i++)
         if(OrbBuiltinStrategyPresetLoad(i,p)&&p.id==id){found=true;break;}
      if(!found||!OrbStrategyPresetApplyValues(p)||!OrbStrategyPresetMatchesRuntime(p))return false;
      g_campaignCalendar=TCalStrategyOffText();g_strategyPresetIndex=-1;
      g_campaignNativeId=p.id;g_campaignName=p.name;
      g_campaignKey=OrbBuiltinWindowKey(p);
      g_campaignFolder="OrbStrategyUserLibrary\\WindowMetrics";
      return true;
#else
      return false;
#endif
   }
   string recordPath=CampaignOrigin;StringReplace(recordPath,"/","\\");
   string v[];int f=FileOpen(recordPath,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON,0,CP_UTF8);
   if(f==INVALID_HANDLE)return false;
   while(!FileIsEnding(f)){int n=ArraySize(v);ArrayResize(v,n+1);v[n]=FileReadString(f);}
   FileClose(f);if(ArraySize(v)<7)return false;
   int slot=(int)StringToInteger(v[2]);
   if(slot<0||slot>=g_userCount||!g_userStrategies[slot].valid)return false;
   OrbUserRecord r=g_userStrategies[slot];p=r.preset;
   if(r.symbol!=_Symbol||r.inputSignature!=CampaignProfileSignature)return false;
   string reason="";if(!OrbUserValidate(p,reason)){Print("CAMPAIGN APPLY: ",reason);return false;}
   if(CampaignDashboardLoad)
   {
#ifndef CAMPAIGN_ORB
      bool restoring=g_maRestoringPreset;g_maRestoringPreset=true;
      bool applied=OrbStrategyPresetApplyValues(p);g_maRestoringPreset=restoring;
#else
      bool applied=OrbStrategyPresetApplyValues(p);
#endif
      if(!applied)return false;
   }
   else
   {
   string runtime[];StringSplit(r.runtime,'\n',runtime);
   if(!OrbCustomRuntimeRead(runtime,0,true)||!CampaignCalendar(r.timeMatrix))return false;
   g_rtNasTf=(ENUM_TIMEFRAMES)r.chartTf;
   }
   g_campaignCalendar=r.timeMatrix;
#ifdef CAMPAIGN_ORB
   g_orbStrategyTimezone=r.brokerOffset;
   OrbClockUseSaved(r.clockProfile,r.brokerSeason,r.exchangeSeason,r.clockSession);
   g_rtInverseMaxGapPct=r.inverseMaxGapPct;g_orbPositions=r.positions;
   g_campaignIndependent=r.positions.independent;
   g_campaignKey=OrbUserWindowKey(r);
   g_campaignFolder="OrbStrategyUserLibrary\\WindowMetrics";
#else
   g_maIndependent=r.independent;g_maMaxConsecutive=r.maxSeries;
   g_maReverseExit=r.reverseExit;g_maReverseWait=r.reverseWait;
   g_rtAdvancedReverse=r.advancedReverse;g_rtAdvancedReverseMaxCostPct=r.advancedReverseMaxCostPct;
   g_mcOf=r.orderFlow;McOfReset();g_campaignIndependent=r.independent;
   string engine="";
#ifdef CAMPAIGN_LAB
   engine=r.entryEngine;
   if(engine!=""){LabEngine e;if(!LabEngineRead(engine,e))return false;g_labEngine=e;}
   g_labPreviewOnly=false;
   if(LabPolicyEnabled()){g_rtPipSlMode=true;if(g_labEngine.pipSl)g_rtPipSlPips=g_labEngine.pipSlPips;}
   g_campaignFolder="EntryEngineLabStrategyLibrary\\WindowMetrics";
#else
   g_campaignFolder="MaCrossOrbStrategyLibrary\\WindowMetrics";
#endif
   string ofKey=r.orderFlow.mode==0?"":"|ORDERFLOW_QUOTE_V1="+McOfConfigText(r.orderFlow);
   g_campaignKey=OrbUserWindowKey(r);
   MaCrossAuditInvalidate();
#endif
   for(int i=0;i<ORB_REGIME_COUNT;i++)g_regimeAllowed[i]=OrbPresetRegimeAllowed(p,i);
   g_orbRfEnabled=p.rfMaster;
   for(int i=0;i<ORB_RF_COUNT;i++)g_orbRfBlocked[i]=OrbPresetRfBlocked(p,i);
   if(!OrbUserMatches(p)){Print("CAMPAIGN SETTINGS MISMATCH: ",p.name," calendar=",TCalStrategyText());return false;}
   g_campaignNativeId=p.id;g_campaignName=p.name;g_strategyPresetIndex=-1;
   g_orbBridgeEnabled=false;g_rtEaEnabled=false;
   return true;
}
bool CampaignCoverage(int weeks)
{
   datetime cutoff=CampaignNow()-weeks*7*86400;
   return SeriesInfoInteger(_Symbol,g_rtSignalTf,SERIES_FIRSTDATE)>0
      &&SeriesInfoInteger(_Symbol,g_rtSignalTf,SERIES_FIRSTDATE)<=cutoff;
}
void CampaignRun(int weeks)
{
   SetHistoricalWeeks(weeks);g_histNeedsRedraw=true;g_lastHistBuild=0;DrawHistoricalSignals();
   ulong began=GetTickCount64();
   while(g_histCoveragePending&&!IsStopped()
      &&GetTickCount64()-began<(ulong)CampaignSyncSeconds*1000)
   {
#ifndef CAMPAIGN_ORB
      // The EA's three quick UI retries are not a complete terminal-startup wait.
      if(g_histCoverageDetail=="signal series not synchronized"||g_histCoverageDetail=="H4 series not synchronized")
      {g_maCacheFailedAttempts=0;g_histCoverageHardBlocked=false;}
#endif
      if(g_histCoverageHardBlocked)break;
      Sleep(1000);g_histCoverageAttempts=0;g_histNeedsRedraw=true;DrawHistoricalSignals();
   }
   began=GetTickCount64();
   while(g_histAuditRunning&&!IsStopped()&&GetTickCount64()-began<(ulong)CampaignAuditSeconds*1000)
   {ProcessHistoricalAuditStep();Sleep(1);}
}
#endif

void OnStart()
{
   string file="Campaign_"+CampaignId+".csv";
   int f=FileOpen(file,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
   if(f==INVALID_HANDLE)return;
   FileWrite(f,"catalog_id","native_id","name","symbol","chart_tf","weeks","total","wins","losses","open","flat","data","net_r","min_cum_r","as_of","status","metrics_saved","independent","elapsed_ms","detail","order_attempts","settings_verified","calendar","load_mode","settings_key","engine_hash","template_hash","generator_hash");
   ulong connectedAt=GetTickCount64();
   while(!TerminalInfoInteger(TERMINAL_CONNECTED)&&!IsStopped()&&GetTickCount64()-connectedAt<60000)Sleep(250);
   SymbolSelect(_Symbol,true);
   if(TerminalInfoInteger(TERMINAL_CONNECTED))Sleep(2000);
   if(CampaignId==""||CampaignOrigin==""||(CampaignBroker!=""&&AccountInfoString(ACCOUNT_SERVER)!=CampaignBroker)||CampaignInit()!=INIT_SUCCEEDED||!CampaignApply())
   {FileWrite(f,CampaignId,"",CampaignCsvCell(CampaignOrigin),_Symbol,(int)_Period,0,0,0,0,0,0,0,0,0,0,"APPLY_FAILED",0,0,0,CampaignProfileSignature,g_campaignOrderAttempts,0,CampaignCsvCell(TCalStrategyText()),CampaignDashboardLoad?"dashboard":"campaign","",CAMPAIGN_SOURCE_HASH,CAMPAIGN_TEMPLATE_HASH,CAMPAIGN_GENERATOR_HASH);FileClose(f);return;}
   g_campaignAllowMetricWrites=CampaignPublishMetrics;
   bool macroReady=CampaignPrepareMacro();
   string list[];int count=StringSplit(CampaignWeeks,',',list);
   for(int i=0;i<count&&!IsStopped();i++)
   {
      int weeks=(int)StringToInteger(list[i]);if(!SwValidWindow(weeks))continue;
      Print("CAMPAIGN START ",CampaignId," ",g_campaignName," ",weeks,"W");
      ulong began=GetTickCount64();if(macroReady)CampaignRun(weeks);
      string status="AUDITED",detail="";int total,wins,losses,open,flat,data;double netR,minCum;datetime asOf;
#ifdef CAMPAIGN_SOL
      total=g_hist.total;wins=g_hist.wins;losses=g_hist.losses;open=g_hist.open;data=g_hist.invalid;
      flat=MathMax(0,total-wins-losses-open-data);netR=g_hist.netR;minCum=g_directionMinCum;asOf=CampaignNow();
      if(g_auditMacroPending)status="REGIME_DATA_PENDING";
#else
      total=g_histTotal;wins=g_histWins;losses=g_histLosses;open=g_histOpen;flat=g_histFlat;data=g_histInvalid;
      netR=g_histNetR;minCum=g_histMinCumulativeR;asOf=g_histRunNow;
      detail=g_histCoverageDetail;
      if(g_histAuditRunning){status="AUDIT_TIMEOUT";CancelHistoricalAuditBuild();}
      else if(g_histCoveragePending||g_histCoverageHardBlocked)status="HISTORY_UNAVAILABLE";
      else if(g_histRunDays!=weeks*7)status="WINDOW_INCOMPLETE";
#ifndef CAMPAIGN_ORB
      if(g_mcOf.mode!=0&&g_mcOfDataIncomplete){status="ORDERFLOW_DATA_INCOMPLETE";detail=g_mcOfStatus;}
#endif
#endif
      if(!macroReady){status="REGIME_HISTORY_UNAVAILABLE";detail="MTF history not synchronized; no verified metrics published";asOf=CampaignNow();}
      if(status=="AUDITED"&&!CampaignCoverage(weeks))status="COVERAGE_SHORT";
      if(status=="AUDITED"&&data>0)status="DATA_INCOMPLETE";
      if(status=="AUDITED"&&open>0)status="AUDITED_OPEN";
      if(g_campaignOrderAttempts>0)status="SAFETY_GUARD_TRIGGERED";
      CampaignTradeTrace(weeks);
      bool settingsVerified=TCalStrategyMatchesText(g_campaignCalendar);
      if(!settingsVerified)status="SETTINGS_MISMATCH";
      bool saved=false;
      if(CampaignPublishMetrics&&(status=="AUDITED"||status=="AUDITED_OPEN"))
      {
         ResetLastError();
         saved=SwWrite(g_campaignFolder,g_campaignNativeId,g_campaignKey,weeks,total,wins,losses,open,flat,netR,minCum,asOf);
         if(!saved)Print("CAMPAIGN METRIC WRITE ERROR ",GetLastError()," ",g_campaignFolder," common=",TerminalInfoString(TERMINAL_COMMONDATA_PATH));
         SwMetric check;
         saved=saved&&SwRead(g_campaignFolder,g_campaignNativeId,g_campaignKey,weeks,check)
            &&check.total==total&&check.wins==wins&&check.losses==losses&&check.open==open&&check.flat==flat
            &&check.asOf==asOf&&MathAbs(check.netR-netR)<1e-8&&MathAbs(check.minCum-minCum)<1e-8;
         if(!saved)status="METRIC_WRITE_FAILED";
      }
      FileWrite(f,CampaignId,g_campaignNativeId,CampaignCsvCell(g_campaignName),_Symbol,(int)_Period,weeks,total,wins,losses,open,flat,data,
         DoubleToString(netR,12),DoubleToString(minCum,12),(long)asOf,status,saved?1:0,g_campaignIndependent?1:0,
         GetTickCount64()-began,CampaignCsvCell(detail),g_campaignOrderAttempts,settingsVerified?1:0,CampaignCsvCell(TCalStrategyText()),CampaignDashboardLoad?"dashboard":"campaign",g_campaignKey,CAMPAIGN_SOURCE_HASH,CAMPAIGN_TEMPLATE_HASH,CAMPAIGN_GENERATOR_HASH);
      FileFlush(f);Print("CAMPAIGN END ",CampaignId," ",weeks,"W ",status," W=",wins," L=",losses," R=",netR);
   }
   FileClose(f);
}
