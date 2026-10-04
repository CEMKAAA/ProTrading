#property strict
#define OnInit ReplayInit
#define OnDeinit ReplayDeinit
#define OnTick ReplayTick
#define OnTimer ReplayTimer
#define OnChartEvent ReplayEvent
#define OnTradeTransaction ReplayTransaction
datetime ReplayAsOf(){return D'2026.10.02 22:00';}
#define TimeCurrent ReplayAsOf
#include "../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#undef TimeCurrent
void OnStart()
{
   ulong readyAt=GetTickCount64();MqlTick readyQuote;
   while((!TerminalInfoInteger(TERMINAL_CONNECTED)||!SymbolIsSynchronized(_Symbol)
      ||!SymbolInfoTick(_Symbol,readyQuote)||readyQuote.bid<=0||readyQuote.ask<=readyQuote.bid)
      &&!IsStopped()&&GetTickCount64()-readyAt<20000)Sleep(250);
   Sleep(1500);
   g_rtEaEnabled=false;g_orbBridgeEnabled=false;g_auditRuntime=false;
   g_rtSignalTf=PERIOD_M5;g_rtUseDelay=false;g_rtFilterAtr=false;g_rtFilterVol=false;
   g_rtPipSlMode=true;g_rtPipSlPips=4000;g_rtTargetLeg=1;g_rtHalfBeLeg=0;
   g_rtAdvancedAuditEngine=true;g_orbStrategyTimezone=0;
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;g_btNativeParity=InpBacktestNativeParity;
   g_btSpreadPts=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   for(int i=0;i<6;i++)g_regimeAllowed[i]=true;
#ifdef ORB_POSITION_POLICY_MQH
   OrbPositionDefaults(g_orbPositions);
#endif
   RegimeV3Update(true);g_rtHistoricalWeeks=2;g_histNeedsRedraw=true;g_lastHistBuild=0;
   DrawHistoricalSignals();ulong started=GetTickCount64();
   while(g_histAuditRunning&&!IsStopped()&&GetTickCount64()-started<120000)ProcessHistoricalAuditStep();
   string rows="";
   for(int i=0;i<ArraySize(g_axTrades);i++)
   {
      AxTrade t=g_axTrades[i];
      rows+=(string)t.signalTime+"|"+(string)t.entryTime+"|"+(string)t.direction+"|"+(string)t.exitTime
         +"|"+AuditMemoPrice(t.entry)+"|"+AuditMemoPrice(t.sl)+"|"+AuditMemoPrice(t.tp)+"|"+AuditMemoPrice(t.netR)
         +"|"+t.outcome+"|"+(string)t.valid+"|"+t.reason+"\n";
   }
   string result="total="+(string)g_histTotal+" wins="+(string)g_histWins+" losses="+(string)g_histLosses
      +" open="+(string)g_histOpen+" data="+(string)g_histInvalid+" netR="+AuditMemoPrice(g_histNetR)
      +" running="+(string)g_histAuditRunning+" coverage="+(string)g_histCoveragePending+" hash="+OrbMlSha256(rows);
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result+"\n"+rows);FileClose(f);}EventKillTimer();
}
