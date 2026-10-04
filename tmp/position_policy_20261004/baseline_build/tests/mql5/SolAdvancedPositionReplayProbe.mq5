#property strict
#define OnInit ReplayInit
#define OnDeinit ReplayDeinit
#define OnTick ReplayTick
#define OnTimer ReplayTimer
#define OnChartEvent ReplayEvent
#define OnTradeTransaction ReplayTransaction
datetime ReplayAsOf(){return D'2026.10.02 22:00';}
#define TimeCurrent ReplayAsOf
#include "../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
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
   // No OnInit/OnTick: no plan recovery, publishing, or native execution.
   PFX="POSITION_PARITY_";g_eaEnabled=false;g_fileBridgeEnabled=false;g_auditRuntime=false;
   g_htf=InpDefaultHtf;g_entryTf=InpDefaultEntryTf;g_swingLookback=InpDefaultSwingLookback;
   g_target=InpDefaultTarget;g_hc=InpDefaultHalfBe;g_weeklyBias=InpDefaultWeeklyBias;
   g_entryModel=InpDefaultEntryModel;g_stopModel=InpDefaultStopModel;g_targetModel=InpDefaultTargetModel;
   g_requireIrlTouch=InpDefaultRequireIrlTouch;g_requireEntrySweep=InpDefaultRequireEntrySweep;
   g_requireDisplacementFvg=InpDefaultRequireDisplacementFvg;g_requireAsiaLiquidityDraw=InpDefaultRequireAsiaLiquidityDraw;
   g_useAsiaLiquidityTarget=InpDefaultUseAsiaLiquidityTarget;g_requireSmt=InpDefaultRequireSmt;
   g_slDistancePct=InpSlDistancePct;g_slBufferAtrPct=InpSlBufferAtrPct;
   g_pipSlMode=true;g_pipSlPips=4000;g_invertMode=false;g_histWeeks=2;
   g_btFillMode=InpBacktestFillMode;g_btSameBarPolicy=InpBacktestSameBarPolicy;
   g_btSpreadPts=InpBacktestSpreadPts;g_btSlippagePts=InpBacktestSlippagePts;g_btCommissionPerLot=InpBacktestCommissionPerLot;
   LnNasDefaults(g_lnNas);LiqMacroRegimeInit();RegimeV3Update(true);
   RecalculateHistoricalStats();
   string rows="";
   for(int i=0;i<ArraySize(g_histSignals);i++)
      rows+=g_histSignals[i].id+"|"+(string)g_histSignals[i].availableTime+"|"+(string)g_histSignalEntryTime[i]
         +"|"+(string)g_histSignalExitTime[i]+"|"+DoubleToString(g_histSignalExecEntry[i],8)
         +"|"+DoubleToString(g_histSignalExecSl[i],8)+"|"+DoubleToString(g_histSignalExecTp[i],8)
         +"|"+DoubleToString(g_histSignalR[i],8)+"|"+g_histSignalExitReason[i]+"|"+(string)g_histSignalValid[i]+"\n";
   string result="total="+(string)g_hist.total+" wins="+(string)g_hist.wins+" losses="+(string)g_hist.losses
      +" open="+(string)g_hist.open+" data="+(string)g_hist.invalid+" netR="+DoubleToString(g_hist.netR,8)
      +" hash="+LiqLibraryHash(rows);
   int f=FileOpen(MQLInfoString(MQL_PROGRAM_NAME)+".txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f!=INVALID_HANDLE){FileWriteString(f,result+"\n"+rows);FileClose(f);}EventKillTimer();
}
