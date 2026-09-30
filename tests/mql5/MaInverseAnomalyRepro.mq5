#property strict
#define OnInit ReproUnusedInit
#define OnDeinit ReproUnusedDeinit
#define OnTimer ReproUnusedTimer
#define OnTick ReproUnusedTick
#define OnChartEvent ReproUnusedChartEvent
#define OnTradeTransaction ReproUnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA_AuditDiag.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction

void OnStart()
{
   int report=FileOpen("MaInverseAnomalyRepro.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(report==INVALID_HANDLE)return;
   for(int retry=0;retry<60&&!TerminalInfoInteger(TERMINAL_CONNECTED);retry++)Sleep(500);
   OrbUserReload(true);
   int slot=-1;
   for(int i=0;i<g_userCount;i++)
      if(g_userStrategies[i].valid&&g_userStrategies[i].preset.name=="firsteurusd")slot=i;
   if(slot<0){FileWriteString(report,"strategy not found\n");FileClose(report);return;}
   OrbStrategyPreset preset=g_userStrategies[slot].preset;
   string reason="";
   if(!OrbUserValidate(preset,reason))
   {FileWriteString(report,"strategy validation failed: "+reason+"\n");FileClose(report);return;}
   g_maRestoringPreset=true;
   bool applied=OrbUserApply(preset);
   g_maRestoringPreset=false;
   if(!applied){FileWriteString(report,"strategy apply failed\n");FileClose(report);return;}
   g_rtInvertMode=true;
   g_rtAdvancedAuditEngine=false;
   g_rtTargetLeg=ORB_TARGET_R100;
   g_rtTargetMode=ORB_TARGET_R_LEG;
   g_rtExitMode=ORB_EXIT_FIXED_TARGET;
   g_rtPipSlMode=true;
   g_rtPipSlPips=10.0;
   g_rtAdvancedReverse=false;
   g_maIndependent=false;
   g_maReverseExit=false;
   g_auditRuntime=true;
   datetime from=D'2026.09.21 00:00',until=D'2026.09.25 12:00';
   string detail="";bool hard=false;
   for(int retry=0;retry<30;retry++)
      if(EnsureOrbAuditHistoryCoverage(10,detail,hard))break;
      else Sleep(500);
   if(!MaCrossAuditBuild(_Symbol,g_rtSignalTf,from,until,g_rtMaCrossMode,g_rtMaCrossPair,
      MathMax(1,InpMaFastLength),MathMax(1,InpMaMediumLength),MathMax(2,InpMaSlowLength)))
   {FileWriteString(report,"MA cache failed: "+g_maCrossAuditFailure+"\n");FileClose(report);return;}
   g_histRunNow=until;g_histRunDays=5;g_histRunPoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   g_maAuditPositionUntil=0;g_maHistSeriesDir=0;g_maHistSeriesCount=0;
   OrbResetHistoricalStats();BeginHistoricalSnapshot();InitializeHistoricalTickReplayCoverage();
   ArrayResize(g_histAcceptedSignals,0);ArrayResize(g_histOperationalSignals,0);
   ArrayResize(g_histWindowSignals,0);ArrayResize(g_regimeReferenceSignals,0);
   ArrayResize(g_regimeReferenceWindows,0);
   int count=ArraySize(g_maCrossAuditEvents);ArrayResize(g_histDaySnapshots,count);
   for(int i=0;i<count;i++)ProcessMaHistoricalPrepEvent(i);
   for(int i=0;i<count;i++)
   {
      if(IsStopped())break;
      ProcessHistoricalCalcDay(i);
   }
   FileWriteString(report,StringFormat("events=%d total=%d wins=%d losses=%d invalid=%d filtered=%d mode=%d tf=%d gap=%.2f\n",
      count,g_histTotal,g_histWins,g_histLosses,g_histInvalid,g_histFiltered,(int)g_rtMaCrossMode,(int)g_rtSignalTf,g_rtAdvancedReverseMaxCostPct));
   FileClose(report);
}
