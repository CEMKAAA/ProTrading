#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
int probeChecks=0,probeFailed=0;
void ProbeCheck(bool ok,string name){probeChecks++;if(!ok){probeFailed++;Print("NAS_PROBE_FAIL ",name);}}
void OnStart()
{
   int init=ProbeInit();
   string rows="";
   for(int i=0;i<ArraySize(g_histSignals);i++)
      rows+=g_histSignals[i].id+"|"+(string)g_histSignals[i].dir+"|"
         +(string)g_histSignals[i].availableTime+"|"+DoubleToString(g_histSignalR[i],8)+"|"
         +(string)g_histSignalClosed[i]+"|"+(string)g_histSignalValid[i]+"\n";
#ifdef TRADE_CALENDAR_MATRIX_MQH
   if(init==INIT_SUCCEEDED&&ArraySize(g_histSignals)>0)
   {
      int originalCount=ArraySize(g_histSignals),originalTotal=g_hist.total;
      double originalR=g_hist.netR;
      int originalHours[7];
      for(int day=0;day<7;day++)originalHours[day]=g_tcalDayHours[day];
#ifdef LN_SOL_ADV_MACRO_AUDIT_ACTIVE
      int originalMacroResolved=0;
      for(int bucket=0;bucket<LIQ_MACRO_REGIME_COUNT;bucket++)
         originalMacroResolved+=g_macroAuditWins[bucket]+g_macroAuditLosses[bucket];
#endif
      MqlDateTime sample;TimeToStruct(g_histSignals[0].availableTime,sample);
      for(int day=0;day<7;day++)g_tcalDayHours[day]=16777215^(1<<sample.hour);
      g_tcalEnabled=true;
      RecalculateHistoricalStats(false);
      bool allAllowed=true;
      for(int i=0;i<ArraySize(g_histSignals);i++)
         if(!TCalAllows(g_histSignals[i].availableTime))allAllowed=false;
      ProbeCheck(allAllowed&&ArraySize(g_histSignals)<originalCount,
         "calendar audit excludes disallowed entry hours");
      g_tcalEnabled=false;RecalculateHistoricalStats(false);
      ProbeCheck(ArraySize(g_histSignals)==originalCount&&g_hist.total==originalTotal
         &&MathAbs(g_hist.netR-originalR)<1e-8,
         "calendar OFF restores exact default audit");
#ifdef LN_SOL_ADV_MACRO_AUDIT_ACTIVE
      for(int day=0;day<7;day++)g_tcalDayHours[day]=0;
      g_tcalEnabled=true;RecalculateHistoricalStats(false);
      int blockedMacroResolved=0;
      for(int bucket=0;bucket<LIQ_MACRO_REGIME_COUNT;bucket++)
         blockedMacroResolved+=g_macroAuditWins[bucket]+g_macroAuditLosses[bucket];
      ProbeCheck(g_hist.total==0&&blockedMacroResolved==0,
         "macro active W/L clears when all entry hours are blocked");
      g_tcalEnabled=false;RecalculateHistoricalStats(false);
      int restoredMacroResolved=0;
      for(int bucket=0;bucket<LIQ_MACRO_REGIME_COUNT;bucket++)
         restoredMacroResolved+=g_macroAuditWins[bucket]+g_macroAuditLosses[bucket];
      ProbeCheck(restoredMacroResolved==originalMacroResolved,
         "macro active W/L restores with original audit settings");
#endif
      for(int day=0;day<7;day++)g_tcalDayHours[day]=originalHours[day];
#ifdef LN_SOL_ADV_MACRO_AUDIT_ACTIVE
      ERL_RR_MODE macroTargetBefore=g_target;
      double macroCustomBefore=g_customTargetR;
      g_target=ERL_RR_CUSTOM;g_customTargetR=0.25;
      RecalculateHistoricalStats(false);
      int geometryMacroResolved=0;
      for(int bucket=0;bucket<LIQ_MACRO_REGIME_COUNT;bucket++)
         geometryMacroResolved+=g_macroAuditWins[bucket]+g_macroAuditLosses[bucket];
      ProbeCheck(geometryMacroResolved==g_hist.wins+g_hist.losses,
         "macro W/L reflects active custom-R geometry");
      g_target=macroTargetBefore;g_customTargetR=macroCustomBefore;
      RecalculateHistoricalStats(false);
#endif
   }
#endif
#ifdef LN_SOL_ADV_NAS_READY
   if(init==INIT_SUCCEEDED)
   {
#ifdef LN_SOL_ADV_MACRO_AUDIT_ACTIVE
      g_lnNasPanel=true;g_lnNasDraft=g_lnNas;
      g_lnNasDraft.stateMultiplier=1.23456789;
      DeleteByPrefix(PFX+"NAS_");LnNasDrawPanel();
      LnNasPolicy edited;LnNasDefaults(edited);
      ProbeCheck(LnNasReadPanel(edited)&&MathAbs(edited.stateMultiplier-1.23456789)<1e-8,
         "NAS edit field preserves eight-decimal volume multiplier");
      g_lnNasPanel=false;DeleteByPrefix(PFX+"NAS_");LnNasDrawNav();
#endif
      LnNasPolicy before=g_lnNas;
      LnNasDefaults(g_lnNas);g_lnNas.gate=2;g_lnNas.sensitivity=7;
      g_lnNas.stateVolume=true;g_lnNas.stateMultiplier=1.50;
      g_lnNas.flowVolume=true;g_lnNas.flowMultiplier=2.25;
      g_lnNas.waitMinutes=30;g_lnNas.entryAgeMinutes=90;g_lnNas.maxSameOpen=1;
      string name="__NAS_PROBE_"+(string)GetTickCount64(),path=LiqLibraryPath(name);
      string runtimePath=LiqLibraryFolder()+"\\nas_"+LiqLibraryHash(LnNasKey())+".txt";
      string runtimeBefore="";bool existed=FileIsExist(runtimePath,FILE_COMMON);
      ProbeCheck(!existed||LiqLibraryRead(runtimePath,runtimeBefore),"runtime backup readable");
      ResetLastError();bool saved=LiqLibrarySave(name);
      Print("NAS_PROBE_SAVE saved=",saved," error=",GetLastError()," path=",path);
      ProbeCheck(saved,"save strategy and NAS options");
      string record="",parts[];LnNasPolicy parsed;LnNasDefaults(parsed);
      bool recordOk=LiqLibraryRead(path,record);
      int end=StringFind(record,"\nSHA256=");
      int count=end>=0?StringSplit(StringSubstr(record,0,end),'\n',parts):0;
      bool foundPolicy=false;
      for(int line=0;line<count;line++)
         if(StringFind(parts[line],"LN_NAS_V1|")==0)
         {foundPolicy=LnNasUnpack(parts[line],parsed);break;}
      ProbeCheck(recordOk&&foundPolicy
         &&LnNasPack(parsed)==LnNasPack(g_lnNas),"strategy roundtrip has every NAS setting");
      LnNasDefaults(g_lnNas);
      bool applied=LiqLibraryApply(path);
      Print("NAS_PROBE_APPLY applied=",applied," status=",g_liqLibraryStatus," error=",GetLastError());
      ProbeCheck(applied&&LnNasPack(g_lnNas)==LnNasPack(parsed),"Apply restores NAS strategy");
      ERL_RR_MODE targetBefore=g_target;double customBefore=g_customTargetR;
      g_target=ERL_RR_CUSTOM;g_customTargetR=0.00001;
      string customName=name+"_CUSTOM",customPath=LiqLibraryPath(customName);
      ProbeCheck(LiqLibrarySave(customName),"save exact custom R strategy");
      g_target=ERL_RR_TP4;g_customTargetR=500.0;
      ProbeCheck(LiqLibraryApply(customPath)&&g_target==ERL_RR_CUSTOM
         &&MathAbs(TargetR(g_target)-0.00001)<1e-12,"custom R strategy restores exact tiny R");
      g_customTargetR=500.0;
      ProbeCheck(MathAbs(TargetR(g_target)-500.0)<1e-10,"large custom R stays exact");
      g_target=targetBefore;g_customTargetR=customBefore;
      FileDelete(customPath,FILE_COMMON);FileDelete(customPath+".lock",FILE_COMMON);
      if(existed)LiqLibraryAtomicWrite(runtimePath,runtimeBefore);
      else FileDelete(runtimePath,FILE_COMMON);
      FileDelete(path,FILE_COMMON);FileDelete(path+".lock",FILE_COMMON);

      LnNasDefaults(g_lnNas);g_lnNas.gate=2;
      datetime now=TimeCurrent(),signalAt=now-900;
      g_lnNasBar=iTime(_Symbol,(ENUM_TIMEFRAMES)_Period,1);g_lnNasSeed=signalAt-3600;
      g_lnNasSignature=_Symbol+"|"+(string)_Period+"|4|false|1.00000000|false|1.00000000";
      ArrayResize(g_lnNasEvents,1);g_lnNasEvents[0].at=signalAt-300;
      ErlSignal sig;ZeroMemory(sig);sig.valid=true;sig.id="probe-entry";sig.dir=1;sig.availableTime=signalAt;
      g_lnNasEvents[0].dir=-sig.dir;g_lnNasEvents[0].stateAllowed=true;g_lnNasEvents[0].flowAllowed=true;
      string bridgeBefore=g_lastBridgeStatus;int pendingBefore=ArraySize(g_bridgePending);
      datetime probeAccepted=0;
      int probeDecision=LnNasEntryDecision(sig.dir,sig.availableTime,TimeCurrent(),probeAccepted);
      Print("NAS_PROBE_PRE gate=",g_lnNas.gate," invert=",g_invertMode," decision=",probeDecision,
         " count=",ArraySize(g_lnNasEvents)," key=",g_lnNasSignature," first_dir=",g_lnNasEvents[0].dir,
         " required=",sig.dir," accepted=",probeAccepted);
      g_fileBridgeEnabled=true;g_fileBridgeOnlyMode=true;g_nativeTradeWithBridgeOnly=false;
      bool rejected=!OpenSignal(sig);
      Print("NAS_PROBE_TRACE rejected=",rejected," block=",g_lastBlock," bridge_before=",bridgeBefore,
         " bridge_after=",g_lastBridgeStatus," pending_before=",pendingBefore," pending_after=",ArraySize(g_bridgePending));
      ProbeCheck(rejected&&g_lastBlock=="NAS_STATE_REJECT"
         &&g_lastBridgeStatus==bridgeBefore&&ArraySize(g_bridgePending)==pendingBefore,
         "rejected entry never reaches bridge or native order");
      g_fileBridgeEnabled=false;g_fileBridgeOnlyMode=false;
      g_lnNas.gate=1;g_lnNasEvents[0].dir=-sig.dir;
      ArrayResize(g_lnNasEvents,2);g_lnNasEvents[1]=g_lnNasEvents[0];
      g_lnNasEvents[1].at=signalAt+120;g_lnNasEvents[1].dir=sig.dir;
      datetime accepted=0;
      ProbeCheck(LnNasEntryDecision(sig.dir,signalAt,signalAt+180,accepted)==1&&accepted==signalAt+120,
         "ENTRY waits for same direction closed NAS signal");
      g_lnNas.gate=0;g_lnNas.exitMode=2;
      ArrayResize(g_lnNasEvents,2);
      g_lnNasEvents[0].at=signalAt-10;g_lnNasEvents[0].dir=-1;
      g_lnNasEvents[1].at=signalAt+300;g_lnNasEvents[1].dir=-1;
      ProbeCheck(LnNasExitAt(1,signalAt,signalAt+360,0)==signalAt+300,
         "pre-entry NAS signal cannot close position");
      ProbeCheck(LnNasExitAt(1,signalAt,signalAt+360,10)==0
         &&LnNasExitAt(1,signalAt,signalAt+660,10)==signalAt+600,
         "NAS grace closes only after wait expires");
      g_lnNas.independent=true;g_lnNas.maxSameOpen=1;
      ArrayResize(g_histSignals,2);ArrayResize(g_histSignalValid,2);
      ArrayResize(g_histSignalClosed,2);ArrayResize(g_histSignalExitTime,2);
      ArrayResize(g_histSignalInvalidReason,2);
      g_histSignals[0]=sig;g_histSignals[1]=sig;g_histSignals[1].availableTime=signalAt+30;
      g_histSignalValid[0]=true;g_histSignalClosed[0]=false;g_histSignalInvalidReason[0]="";
      ProbeCheck(LnNasAuditCap(1)==1,"MAX=1 rejects second concurrent same-side trade");
      g_histSignalClosed[0]=true;g_histSignalExitTime[0]=signalAt+20;
      ProbeCheck(LnNasAuditCap(1)==0,"MAX=1 permits next trade after first closes");
      LnNasDefaults(g_lnNas);g_lnNas.gate=2;LnNasInvalidate();
      ProbeCheck(LnNasBuild(TimeCurrent()-14*86400)&&ArraySize(g_lnNasEvents)>0,
         "real closed-bar NAS core builds from chart history");
      g_lnNas=before;LnNasInvalidate();
   }
#endif
   string payload="{\"init\":"+(string)init+",\"checks\":"+(string)probeChecks+",\"failed\":"+(string)probeFailed+",\"total\":"+(string)g_hist.total
      +",\"wins\":"+(string)g_hist.wins+",\"losses\":"+(string)g_hist.losses
      +",\"open\":"+(string)g_hist.open+",\"invalid\":"+(string)g_hist.invalid
      +",\"netR\":"+DoubleToString(g_hist.netR,8)
      +",\"signalHash\":\""+LiqLibraryHash(rows)+"\"}";
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".json",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,payload);FileClose(f);}
   ProbeDeinit(0);
}
