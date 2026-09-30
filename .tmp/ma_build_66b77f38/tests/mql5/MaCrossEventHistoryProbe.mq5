// Include the actual EA adapters without starting any EA/trading callbacks.
#define MA_EVENT_PROBE
#define OnInit MaUnusedInit
#define OnDeinit MaUnusedDeinit
#define OnTimer MaUnusedTimer
#define OnTick MaUnusedTick
#define OnChartEvent MaUnusedChartEvent
#define OnTradeTransaction MaUnusedTransaction
#include "../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTimer
#undef OnTick
#undef OnChartEvent
#undef OnTradeTransaction
int checks=0,failed=0;
void Verify(bool condition,string description)
{checks++;if(!condition){failed++;Print("FAIL ",description);}}
void ClearProbeStreams()
{
   ArrayResize(g_histAcceptedSignals,0);ArrayResize(g_histOperationalSignals,0);ArrayResize(g_histWindowSignals,0);
   ArrayResize(g_regimeReferenceSignals,0);ArrayResize(g_regimeReferenceWindows,0);
}
void OnStart()
{
   int seriesDir=0,seriesCount=0,limit=0;
   Verify(MaParseSeriesLimit("3",limit)&&limit==3,"series limit input");
   Verify(!MaParseSeriesLimit("3.5",limit)&&!MaParseSeriesLimit("0",limit)
      &&!MaParseSeriesLimit("-1",limit)&&!MaParseSeriesLimit("1001",limit),"invalid series limits rejected");
   for(int i=0;i<3;i++){Verify(MaSeriesAllows(1,seriesDir,seriesCount,3),"three buys allowed");seriesCount++;}
   Verify(!MaSeriesAllows(1,seriesDir,seriesCount,3),"fourth buy rejected");
   Verify(MaSeriesAllows(-1,seriesDir,seriesCount,3)&&seriesCount==0,"opposite starts new series");
   seriesCount++;
   Verify(MaSeriesAllows(1,seriesDir,seriesCount,3)&&seriesCount==0,"return to buy resets");
   seriesCount=3;
   Verify(!MaSeriesAllows(1,seriesDir,seriesCount,2),"lowering limit does not create allowance");
   Verify(MaSeriesAllows(1,seriesDir,seriesCount,4)&&seriesCount==3,"raising limit retains usage");
   Verify(!MaSeriesAllows(0,seriesDir,seriesCount,4),"invalid direction rejected");
   seriesDir=1;seriesCount=8;
   Verify(MaSeriesAllows(-1,seriesDir,seriesCount,12)&&seriesDir==-1&&seriesCount==0,
      "opposite starts after 8 of 12 without filling the old allowance");
   Verify(MaIndependentDefiniteRejection(TRADE_RETCODE_MARKET_CLOSED),"definite rejection can release reservation");
   Verify(!MaIndependentDefiniteRejection(TRADE_RETCODE_TIMEOUT)
      &&!MaIndependentDefiniteRejection(TRADE_RETCODE_CONNECTION)
      &&!MaIndependentDefiniteRejection(TRADE_RETCODE_PLACED),"ambiguous outcomes retain reservation");
   // Independent mode must not route an opposite signal to legacy close-all.
   g_maIndependent=true;datetime independentExit=123;string independentDetail="";OrbWindowSignal emptySignals[];
   Verify(!FindNewDayAcceptedReverseExit(emptySignals,1,"BUY",1000,independentExit,independentDetail)
      &&independentExit==0,"independent history never reverses an older position");
   Verify(!IsAcceptedNewDayReverseCandidate("SELL",1000,independentDetail),"independent live reverse close disabled");
   Verify(!ProcessNasOppositeExit(),"independent NAS global close disabled");
   g_maIndependent=false;
   long savedMagic=g_runtimeMagic;
   g_runtimeMagic=9182026000+(long)(GetTickCount64()%1000000);
   Verify(MaIndependentAcquire(),"isolated series ledger creation");
   string testState=g_maSeriesFile;
   g_maSeriesDir=1;g_maSeriesCount=3;g_maSeriesBar=D'2026.09.17 12:00';
   Verify(MaIndependentWrite(),"atomic series reservation write");
   MaIndependentRelease();g_maSeriesCount=0;g_maSeriesBar=0;
   Verify(MaIndependentAcquire()&&g_maSeriesDir==1&&g_maSeriesCount==3
      &&g_maSeriesBar==D'2026.09.17 12:00',"restart preserves reservation and deduplication timestamp");
   Verify(!MaSeriesAllows(1,g_maSeriesDir,g_maSeriesCount,3),"restart cannot bypass limit");
   g_maSeriesUncertain=true;Verify(MaIndependentWrite(),"persist uncertain order intent");
   MaIndependentRelease();g_maSeriesUncertain=false;
   Verify(MaIndependentAcquire()&&g_maSeriesUncertain,"crash before broker acknowledgment remains blocked after restart");
   int secondOwner=FileOpen(testState+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
   Verify(secondOwner==INVALID_HANDLE,"second owner cannot acquire series scope");
   if(secondOwner!=INVALID_HANDLE)FileClose(secondOwner);
   MaIndependentRelease();
   int corrupt=FileOpen(testState,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(corrupt!=INVALID_HANDLE){FileWriteString(corrupt,"corrupt");FileClose(corrupt);}
   Verify(!MaIndependentAcquire(),"corrupted ledger fails closed");
   FileDelete(testState);FileDelete(testState+".lock");
   g_maSeriesUncertain=false;
   g_runtimeMagic=savedMagic;
   // No OnInit, TryOpenSignal or order API is called by this script.
   g_rtSignalTf=PERIOD_M5;g_rtMaCrossMode=MA_CROSS_PIVOT_ST;
   g_rtEntryWindow=false;g_rtFilterAtr=false;g_rtFilterDay=false;g_rtFilterVol=false;
   g_rtDisplacement=false;g_rtFvgMode=ORB_FVG_OFF;g_orbRfEnabled=false;
   g_rtNasConfirmation=false;g_rtNasStateGate=false;g_rtNasExitOnOppositeSignal=false;g_rtNasAdditionalExit=false;
   g_rtInvertMode=false;g_rtPipSlMode=true;g_rtPipSlPips=4000;
   g_rtSlDistancePct=100;g_rtEntryMode=ORB_ENTRY_BREAKOUT;
   for(int i=0;i<ORB_REGIME_COUNT;i++)g_regimeAllowed[i]=true;
   BeginHistoricalSnapshot();
   const int count=12;ArrayResize(g_maCrossAuditEvents,count);ArrayResize(g_histDaySnapshots,count);
   datetime start=D'2026.09.14 00:00';
   for(int i=0;i<count;i++)
   {
      MaCrossAuditEvent e;ZeroMemory(e);e.signalTime=start+i*300;e.direction=i%2==0?1:-1;
      e.close=50000;e.high=50010;e.low=49990;e.volume=200;e.priorVolume=100;e.markerPrice=e.direction>0?49950:50050;
      g_maCrossAuditEvents[i]=e;
   }
   for(int i=0;i<count;i++)ProcessMaHistoricalPrepEvent(i);
   Verify(ArraySize(g_histAcceptedSignals)==count,"all 12 same-day candidates accepted, including pre-opening hours");
   Verify(ArraySize(g_histOperationalSignals)==count,"all operational candidates retained");
   int arrows=0;
   for(int i=0;i<count;i++)
   {
      MaCrossAuditEvent e=g_maCrossAuditEvents[i];string key=MaHistoryEventBase(e.signalTime,e.direction>0?"BUY":"SELL")+"ARW";
      if(ObjectFind(0,key)>=0)arrows++;
      Verify(ObjectFind(0,key)<0,"PREP does not draw provisional candidates");
      Verify(g_histDaySnapshots[i].operationalSignalTime==e.signalTime,"unique snapshot per event");
   }
   Verify(arrows==0,"no candidate arrows before outcome decision");
   long replayCalls=g_orbReplayMemoHits+g_orbReplayMemoMisses;
   int filteredBefore=g_histFiltered;
   g_maIndependent=true;g_maMaxConsecutive=3;g_maHistSeriesDir=1;g_maHistSeriesCount=3;
   for(int i=0;i<count;i+=2)ProcessHistoricalCalcDay(i);
   Verify(g_histFiltered==filteredBefore+count/2,"exhausted BUY candidates skipped");
   Verify(g_orbReplayMemoHits+g_orbReplayMemoMisses==replayCalls,"series-limit skips call neither replay nor memoized replay");
   g_maIndependent=false;g_maAuditPositionUntil=start+86400;
   int heldBefore=g_maAuditHeldCandidates;
   for(int i=0;i<count;i++)ProcessHistoricalCalcDay(i);
   Verify(g_maAuditHeldCandidates==heldBefore+count,"single-mode occupied candidates skipped");
   Verify(g_orbReplayMemoHits+g_orbReplayMemoMisses==replayCalls,"single-mode skips do not call replay");
   g_maAuditPositionUntil=0;
   datetime exit;string detail;
   Verify(FindNewDayAcceptedReverseExit(g_histAcceptedSignals,start,"BUY",start+86400,exit,detail)&&exit==start+600,
      "next same-day reverse exits at its close, not next day");
   DeleteLive();
   for(int i=0;i<count;i++)Verify(ObjectFind(0,MaHistoryEventBase(g_maCrossAuditEvents[i].signalTime,i%2==0?"BUY":"SELL")+"ARW")<0,
      "skipped candidates create no chart objects");
   g_orbBridgePlanActive=true;g_orbBridgePlanDir=1;g_orbBridgePlanTime=start;g_orbBridgePlanEntry=50000;
   g_tradeDir=1;g_tradeOpenTime=start;g_beMoved=true;g_halfClosed=true;g_nyDayKey=0;
   ResetForNewNyDay();
   Verify(g_orbBridgePlanActive&&g_beMoved&&g_halfClosed&&g_tradeDir==1,"date reset cannot forget exposure or HCBE state");
   Verify(IsAcceptedNewDayReverseCandidate("SELL",start+600,detail),"live same-day reverse recognized");
   g_orbBridgePlanActive=false;
   // Retain the raw stream, without drawing rejected candidates.
   ClearProbeStreams();for(int i=0;i<ORB_REGIME_COUNT;i++)g_regimeAllowed[i]=false;
   for(int i=0;i<count;i++)ProcessMaHistoricalPrepEvent(i);
   Verify(ArraySize(g_histAcceptedSignals)==0,"blocked regime does not enter accepted execution stream");
   Verify(ArraySize(g_regimeReferenceSignals)==count,"regime diagnostic universe preserved");
   Verify(ArraySize(g_regimeReferenceWindows)==0,"regime blocks not misclassified as pre-regime exits");
   for(int i=0;i<count;i++)Verify(ObjectFind(0,MaHistoryEventBase(g_maCrossAuditEvents[i].signalTime,i%2==0?"BUY":"SELL")+"ARW")<0,
      "regime rejection does not draw provisional arrow");
   // Actual broker OHLC through the EA's complete preparation + trade replay.
   MqlRates rates[],minutes[];ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,PERIOD_M5,1,4000,rates);
   Verify(copied==4000,"real M5 fixture available");
   int realRaw=0,realTrades=0,realInvalid=0;double elapsed=0;
   if(copied==4000)
   {
      CopyRates(_Symbol,PERIOD_M1,rates[0].time,rates[copied-1].time+300,minutes);
      ClearProbeStreams();ArrayResize(g_maCrossAuditEvents,0);
      McPineKernel kernel;kernel.Reset(MA_CROSS_PIVOT_ST,MA_CROSS_PAIR_FAST,9,27,200);
      for(int i=0;i<copied;i++)
      {
         int direction=kernel.Push(rates[i]);if(i<500||direction==0)continue;
         MaCrossAuditEvent e;ZeroMemory(e);e.signalTime=rates[i].time;e.direction=direction;e.close=rates[i].close;
         e.high=rates[i].high;e.low=rates[i].low;e.volume=(double)rates[i].tick_volume;e.priorVolume=e.volume;e.markerPrice=kernel.MarkerPrice();
         int n=ArraySize(g_maCrossAuditEvents);ArrayResize(g_maCrossAuditEvents,n+1,256);g_maCrossAuditEvents[n]=e;
      }
      realRaw=ArraySize(g_maCrossAuditEvents);Verify(realRaw>12,"more than one MA signal per trading day");
      ArrayResize(g_histDaySnapshots,realRaw);g_maCrossAuditReady=true;
      g_histRunNow=rates[copied-1].time+300;g_histRunPoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      g_rtTimeExit=false;g_rtFilteredWindowReverseExit=false;g_rtPostTradeDispBlockExit=false;
      g_rtHalfBeLeg=0;SetTargetLeg(2);g_btNativeParity=false;g_rtAdvancedAuditEngine=false;
      g_btFillMode=BT_FILL_NEXT_BAR_OPEN;g_btSpreadPts=0;g_btSlippagePts=0;g_btCommissionPerLot=0;
      for(int i=0;i<ORB_REGIME_COUNT;i++)g_regimeAllowed[i]=true;
      g_maAuditPositionUntil=0;g_maAuditHeldCandidates=0;g_histChecked=0;OrbResetHistoricalStats();
      ulong started=GetTickCount64();
      for(int i=0;i<realRaw;i++)ProcessMaHistoricalPrepEvent(i);
      Verify(ArraySize(g_histAcceptedSignals)==realRaw,"all real unfiltered source candidates reach execution audit");
      for(int i=0;i<realRaw;i++)
      {
         int total=g_histTotal;
         ProcessHistoricalCalcDay(i);
         if(total==g_histTotal)Print("SKIP ",TimeToString(g_maCrossAuditEvents[i].signalTime)," held=",g_maAuditHeldCandidates," filtered=",g_histFiltered," positionUntil=",TimeToString(g_maAuditPositionUntil));
      }
      elapsed=(GetTickCount64()-started)/1000.0;realTrades=g_histTotal;realInvalid=g_histInvalid;
      Verify(g_histChecked==realRaw,"CALC visits every real source event");
      Verify(realTrades==realRaw,"alternating Pivot ST stream is not truncated to daily first trade");
      Verify(g_histInvalid==0,"real replay has no missing-data outcomes");
      Verify(g_histWins+g_histLosses+g_histOpen+g_histFlat+g_histInvalid==g_histTotal,"trade totals reconcile");
      int markers=0;
      for(int i=0;i<realRaw;i++)
      {
         MaCrossAuditEvent e=g_maCrossAuditEvents[i];
         if(ObjectFind(0,MaHistoryEventBase(e.signalTime,e.direction>0?"BUY":"SELL")+"ARW")>=0)markers++;
      }
      Verify(markers==realRaw,"every real event retains its own historical arrow after CALC");
   }
   int f=FileOpen("2ca905e3_MaCrossEventHistoryProbe.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   string result="{\"checks\":"+(string)checks+",\"failed\":"+(string)failed+",\"raw\":12,\"same_day_accepted\":12,\"real_raw\":"+(string)realRaw
      +",\"real_trades\":"+(string)realTrades+",\"real_invalid\":"+(string)realInvalid+",\"real_replay_sec\":"+DoubleToString(elapsed,3)+"}";
   if(f!=INVALID_HANDLE){FileWriteString(f,result);FileClose(f);}Print("MA_EVENT_HISTORY_PROBE ",result);
}
